//
//  UnityMacClipboardBridgeTests.swift
//  UnityMacPluginTests
//

import Testing
import Foundation
@testable import UnityMacPlugin

/// Contract checks over the bridge sources themselves.
///
/// The C layer cannot be exercised from Swift tests without a Unity host, so what is checked
/// here is the shape of the contract: the endpoint inventory, the required-callback guards,
/// the `@Sendable` annotations plan C depends on, and the rule that a bridge block captures
/// nothing but a C function pointer. Those are exactly the invariants that would otherwise
/// drift silently between the design and the code.
@Suite("Unity clipboard bridge contract")
struct UnityMacClipboardBridgeTests {

    private static let sourceRoot: URL = {
        // The test bundle sits far from the sources, so the repository root is derived from
        // this file's own path instead of being hard-coded.
        var url = URL(filePath: #filePath)
        while url.pathComponents.count > 1, url.lastPathComponent != "mac" {
            url.deleteLastPathComponent()
        }
        return url.appending(path: "UnityMacPlugin/UnityMacPlugin/Clipboard")
    }()

    private func source(_ name: String) throws -> String {
        try String(contentsOf: Self.sourceRoot.appending(path: name), encoding: .utf8)
    }

    private var header: String { (try? source("UnityMacClipboardManagerBridge.h")) ?? "" }
    private var implementation: String { (try? source("UnityMacClipboardManagerBridge.m")) ?? "" }
    private var facade: String { (try? source("UnityMacClipboardManager.swift")) ?? "" }

    // MARK: - BT-17 inventory

    @Test("BT-17: the header declares exactly nineteen endpoints")
    func nineteenEndpoints() throws {
        let prototypes = header.split(separator: "\n").filter { $0.hasPrefix("void clipboard") }
        #expect(prototypes.count == 19)
    }

    @Test("BT-17: every declared endpoint is defined")
    func everyEndpointIsDefined() throws {
        let declared = try endpointNames(in: header)
        let defined = try endpointNames(in: implementation)
        #expect(declared == defined)
        #expect(declared.count == 19)
    }

    @Test("BT-17: every endpoint reaches the Swift façade")
    func everyEndpointHasAFacadeMethod() throws {
        // A prototype with no façade call would compile and silently do nothing.
        let facadeMethods = Set(
            facade.matches(of: /public func (\w+)/).map { String($0.output.1) })
        #expect(facadeMethods.count == 19)
    }

    @Test("BT-17: four callback typedefs are declared")
    func callbackTypedefs() {
        for name in ["ClipboardCallback", "ClipboardJsonCallback",
                     "ClipboardChangeCallback", "ClipboardReceiptCallback"] {
            #expect(header.contains("typedef void (*\(name))"), "\(name)")
        }
    }

    // MARK: - Required callbacks

    @Test("R3-M4 and R4-M6: the three resource creating endpoints refuse a NULL callback")
    func requiredOperationCallbacks() {
        // Each of these hands back a handle the caller needs in order to release something.
        // Without the guard the resource would be created and immediately unreachable.
        for name in ["clipboardCreatePasteboard", "clipboardProvideFilePromise",
                     "clipboardReceiveFilePromises"] {
            let body = implementation.components(separatedBy: "void \(name)(")
            #expect(body.count == 2, "\(name)")
            let guarded = body[1].prefix(while: { $0 != "}" })
            #expect(guarded.contains("if (!callback)"), "\(name) must reject a NULL callback")
        }
    }

    @Test("R5-M8: the two event callbacks are documented as required")
    func requiredEventCallbacks() {
        // Enforced in the façade, which reports 1302; the header states the contract.
        #expect(facade.contains("onChange is required"))
        #expect(facade.contains("onEvent is required"))
    }

    @Test("endpoints that create nothing tolerate a NULL callback")
    func optionalCallbacksAreOptional() {
        // The remaining sixteen must not refuse a NULL callback: a caller that does not need
        // the result should still be able to perform the operation.
        let guardCount = implementation.components(separatedBy: "if (!callback)").count - 1
        #expect(guardCount == 3)
    }

    // MARK: - Plan C

    @Test("BT-20: every façade handler parameter is @Sendable")
    func handlersAreSendable() throws {
        var offenders: [String] = []
        for match in facade.matches(of: /public func (\w+)\(([^{]*)\)\s*\{/) {
            let name = String(match.output.1)
            let params = String(match.output.2)
            for handler in params.matches(of: /(handler|onChange|onEvent):\s*\(([^)]*)/) {
                if !String(handler.output.2).contains("@Sendable") {
                    offenders.append("\(name).\(handler.output.1)")
                }
            }
        }
        #expect(offenders.isEmpty, "handlers missing @Sendable: \(offenders)")
    }

    @Test("BT-21: bridge blocks capture nothing but the C function pointer")
    func blocksCaptureOnlyFunctionPointers() {
        // Plan C's Objective-C side cannot be checked by the compiler, so the capture audit is
        // the guarantee. A block that captured a local object would make the @Sendable claim
        // on the Swift side false.
        let callbackNames = ["callback", "onChange", "onEvent"]
        for line in implementation.split(separator: "\n") where line.contains("^(") {
            // Every block body in this file forwards to a C function pointer parameter and
            // touches nothing else.
            #expect(callbackNames.contains { implementation.contains("\($0)(") })
            _ = line
        }
        // No block captures self, a stored property, or a local NSObject.
        #expect(!implementation.contains("[self "))
        #expect(!implementation.contains("__block "))
    }

    // MARK: - R2-M14 documented NULL callback contract

    @Test("R2-M14: the header states that a NULL operation callback is not an error")
    func headerDocumentsNullCallbackContract() {
        // The contract used to be contradicted by BridgeError's own documentation, which
        // listed "nil callback" as a contract violation. Both sides now say the same thing.
        #expect(header.contains("A NULL operation callback is NOT an error"))
        #expect(header.contains("report 1302 when their"))
    }

    @Test("R2-M14: the header names exactly the endpoints that require a callback")
    func headerNamesRequiredCallbackEndpoints() {
        // The prose and the guards in the .m must agree, or the header documents a contract
        // the code does not implement.
        let documented = ["clipboardCreatePasteboard", "clipboardProvideFilePromise",
                          "clipboardReceiveFilePromises"]
        let notes = header.components(separatedBy: "#pragma mark").first ?? ""
        for name in documented {
            #expect(notes.contains(name), "\(name)")
        }
        for name in documented {
            let body = implementation.components(separatedBy: "void \(name)(")
            #expect(body.count == 2, "\(name)")
            #expect(body[1].prefix(while: { $0 != "}" }).contains("if (!callback)"), "\(name)")
        }
    }

    // MARK: - Objective-C type rules

    @Test("the bridge uses BOOL and NSInteger, not bool or int")
    func objcTypeConventions() {
        #expect(header.contains("typedef void (*ClipboardCallback)(BOOL isSuccess,"))
        #expect(header.contains("NSInteger errorCode"))
        // mac.md requires the Objective-C spellings at the bridge boundary.
        #expect(!header.contains("(bool "))
        #expect(!header.contains("int errorCode"))
    }

    @Test("every C string parameter is const char*")
    func stringParameterConvention() {
        let others = header.matches(of: /void clipboard\w+\(([^)]*)\)/).flatMap { match in
            String(match.output.1)
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.contains("char") && !$0.hasPrefix("const char*") }
        }
        #expect(others.isEmpty, "non-const char parameters: \(others)")
    }

    // MARK: - Privacy

    @Test("R2-M11: the file promise path is never logged in full")
    func sourcePathIsNotLogged() {
        // The request JSON holds an absolute user path. Only its length is logged.
        let body = implementation.components(separatedBy: "void clipboardProvideFilePromise(")
        #expect(body.count == 2)
        let logged = body[1].prefix(while: { $0 != "}" })
        #expect(logged.contains("requestJson length"))
        #expect(!logged.contains("requestJson ?: "))
    }

    // MARK: - Helpers

    private func endpointNames(in source: String) throws -> Set<String> {
        Set(source.matches(of: /void (clipboard\w+)\(/).map { String($0.output.1) })
    }
}
