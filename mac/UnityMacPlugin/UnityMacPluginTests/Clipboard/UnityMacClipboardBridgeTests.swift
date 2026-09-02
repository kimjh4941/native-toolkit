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

    @Test("BT-17: the header declares exactly fifteen endpoints")
    func fifteenEndpoints() throws {
        let prototypes = header.split(separator: "\n").filter { $0.hasPrefix("void clipboard") }
        #expect(prototypes.count == 15)
    }

    @Test("BT-17: every declared endpoint is defined")
    func everyEndpointIsDefined() throws {
        let declared = try endpointNames(in: header)
        let defined = try endpointNames(in: implementation)
        #expect(declared == defined)
        #expect(declared.count == 15)
    }

    @Test("BT-17: every endpoint reaches the Swift façade")
    func everyEndpointHasAFacadeMethod() throws {
        // A prototype with no façade call would compile and silently do nothing.
        let facadeMethods = Set(
            facade.matches(of: /public func (\w+)/).map { String($0.output.1) })
        #expect(facadeMethods.count == 15)
    }

    @Test("BT-17: three callback typedefs are declared")
    func callbackTypedefs() {
        for name in ["ClipboardCallback", "ClipboardJsonCallback",
                     "ClipboardChangeCallback"] {
            #expect(header.contains("typedef void (*\(name))"), "\(name)")
        }
    }

    // MARK: - Required callbacks

    @Test("R3-M4 and R4-M6: the resource creating endpoint refuses a NULL callback")
    func requiredOperationCallbacks() {
        // It hands back a handle the caller needs in order to release something. Without the
        // guard the resource would be created and immediately unreachable.
        for name in ["clipboardCreatePasteboard"] {
            let body = implementation.components(separatedBy: "void \(name)(")
            #expect(body.count == 2, "\(name)")
            let guarded = body[1].prefix(while: { $0 != "}" })
            #expect(guarded.contains("if (!callback)"), "\(name) must reject a NULL callback")
        }
    }

    @Test("R5-M8: the event callback is documented as required")
    func requiredEventCallbacks() {
        // Enforced in the façade, which reports 1302; the header states the contract.
        #expect(facade.contains("onChange is required"))
    }

    @Test("endpoints that create nothing tolerate a NULL callback")
    func optionalCallbacksAreOptional() {
        // The remaining fourteen must not refuse a NULL callback: a caller that does not need
        // the result should still be able to perform the operation.
        let guardCount = implementation.components(separatedBy: "if (!callback)").count - 1
        #expect(guardCount == 1)
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
        #expect(header.contains("reports 1302 when its"))
    }

    @Test("R2-M14: the header names exactly the endpoints that require a callback")
    func headerNamesRequiredCallbackEndpoints() {
        // The prose and the guards in the .m must agree, or the header documents a contract
        // the code does not implement.
        let documented = ["clipboardCreatePasteboard"]
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

    // MARK: - BT-24 malformed options reach the callback

    @Test("BT-24: a malformed optionsJson reaches the caller as 1301")
    func malformedOptionsReportsParseFailed() async throws {
        // The parser returning nil is only half the contract; what the caller sees is the
        // callback. Checking the parser alone would not catch a façade that swallowed it.
        let received = CallbackRecorder()
        UnityMacClipboardManager.shared.copy(
            contentJson: #"{"items":[{"representations":{"public.utf8-plain-text":"aGk="}}]}"#,
            optionsJson: "garbage",
            scopeJson: #"{"kind":"general"}"#
        ) { isSuccess, _, errorCode, _ in
            received.record(isSuccess: isSuccess, errorCode: errorCode)
        }
        try await Task.sleep(for: .milliseconds(200))

        #expect(received.isSuccess == false)
        #expect(received.errorCode == 1301)
    }

    @Test("BT-24: absent options are accepted rather than reported as malformed")
    func absentOptionsAreAccepted() async throws {
        let received = CallbackRecorder()
        UnityMacClipboardManager.shared.copy(
            contentJson: #"{"items":[{"representations":{"public.utf8-plain-text":"aGk="}}]}"#,
            optionsJson: nil,
            scopeJson: #"{"kind":"named","name":"com.nativetoolkit.tests.bt24"}"#
        ) { isSuccess, _, errorCode, _ in
            received.record(isSuccess: isSuccess, errorCode: errorCode)
        }
        try await Task.sleep(for: .milliseconds(300))

        // Absent is not malformed: it means "use the defaults".
        #expect(received.errorCode != 1301)
    }

    // MARK: - BT-25 the C layer must not log payloads

    /// Helper an argument must go through, derived from its name.
    ///
    /// Scope arguments become a hash so a named pasteboard cannot be identified; everything
    /// else becomes a length. Derived rather than listed, because a hand written list is only
    /// as complete as whoever last edited it — the previous version of this audit omitted
    /// `optionsJson` and therefore could not see it being logged verbatim.
    private func helper(for argument: String) -> String {
        argument.lowercased().contains("scope") ? "NTScope" : "NTLen"
    }

    /// Every `const char*` parameter of an endpoint, taken from its signature.
    ///
    /// The audit's subject is the signature itself, so an argument added later is covered
    /// without anyone remembering to register it here.
    private func payloadArguments(in signature: String) -> [String] {
        signature.matches(of: /const char\*\s+(\w+)/).map { String($0.output.1) }
    }

    /// Each endpoint's name, signature and body.
    ///
    /// Splitting on the next definition is enough: the file has one function per endpoint and
    /// nothing between them.
    private func endpointBodies() -> [(name: String, signature: String, body: String)] {
        var result: [(String, String, String)] = []
        for part in implementation.components(separatedBy: "\nvoid clipboard").dropFirst() {
            let source = "void clipboard" + part
            guard let nameMatch = source.firstMatch(of: /void (clipboard\w+)\(/),
                  let signatureEnd = source.firstIndex(of: ")"),
                  let bodyStart = source.firstIndex(of: "{") else { continue }
            result.append((String(nameMatch.output.1),
                           String(source[..<signatureEnd]),
                           String(source[bodyStart...])))
        }
        return result
    }

    /// The value part of every `Log` call in a function body.
    ///
    /// Every `[Log d:...]` and `[Log e:...]` is covered, not only the `stringWithFormat:`
    /// ones. Restricting the audit to formatted calls left a way through: a direct
    /// `[Log e:TAG :@"..."]` could carry a payload and never be looked at. The audit must not
    /// be narrower than the ways the code can log.
    ///
    /// Within each call the leading string literal is dropped, because it names each value
    /// (`"scopeJson: %@"`) and searching it for an identifier would flag every label.
    private func logCalls(in body: String) -> [String] {
        var results: [String] = []
        for part in body.components(separatedBy: "[Log ").dropFirst() {
            let call = String(part.prefix(while: { $0 != ";" }))
            // Everything after the first string literal, which is the format or the message.
            if let literalEnd = call.range(of: "\",") {
                results.append(String(call[literalEnd.upperBound...]))
            } else if let literalStart = call.range(of: ":@\"") {
                // A direct message with no arguments. Anything interpolated into it would
                // appear here.
                results.append(String(call[literalStart.upperBound...]))
            } else {
                // An unrecognised shape is handed over whole rather than skipped.
                results.append(call)
            }
        }
        return results
    }

    @Test("BT-25: no payload argument reaches a log line unredacted")
    func noPayloadReachesLogRaw() {
        // Per argument, taken from the signature, so the audit cannot be narrower than the
        // code it audits.
        var offenders: [String] = []
        for endpoint in endpointBodies() {
            for logCall in logCalls(in: endpoint.body) {
                for argument in payloadArguments(in: endpoint.signature) {
                    // Remove the legitimate helper call, then look for the identifier again.
                    // Independent of how a raw value is spelled: `?:`, a bare pointer or a
                    // strlen all survive this strip and are caught.
                    let stripped = logCall
                        .replacingOccurrences(of: "\(helper(for: argument))(\(argument))", with: "")
                    if stripped.contains(argument) {
                        offenders.append("\(endpoint.name): raw \(argument)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders.prefix(6))")
    }

    @Test("BT-25: an argument that is logged goes through its helper")
    func loggedArgumentsUseTheirHelper() {
        var offenders: [String] = []
        for endpoint in endpointBodies() {
            for logCall in logCalls(in: endpoint.body) {
                for argument in payloadArguments(in: endpoint.signature)
                where logCall.contains(argument) {
                    let call = "\(helper(for: argument))(\(argument))"
                    if !logCall.contains(call) {
                        offenders.append("\(endpoint.name): \(argument) not via \(call)")
                    }
                }
            }
        }
        #expect(offenders.isEmpty, "\(offenders.prefix(6))")
    }

    @Test("BT-25: the redaction helpers exist")
    func redactionHelpersExist() {
        #expect(implementation.contains("static NSString *NTLen("))
        #expect(implementation.contains("static NSString *NTScope("))
    }

    @Test("BT-25: the audit sees every endpoint and every declared argument")
    func auditCoversEveryEndpoint() {
        // A subject set that quietly matched nothing would make the checks above pass by doing
        // nothing. Earlier versions of this audit did exactly that, twice.
        let bodies = endpointBodies()
        #expect(bodies.count == 15)

        // Every const char* parameter across the whole bridge, from the signatures.
        let declared = bodies.reduce(0) { $0 + payloadArguments(in: $1.signature).count }
        #expect(declared == 21, "the bridge declares \(declared) string parameters")

        // Every Log call in the file is reachable by the audit, whatever its shape.
        let logCallCount = bodies.reduce(0) { $0 + logCalls(in: $1.body).count }
        let rawLogOccurrences = implementation.components(separatedBy: "[Log ").count - 1
        #expect(logCallCount == rawLogOccurrences,
                "the audit sees \(logCallCount) of \(rawLogOccurrences) Log calls")

        // And every declared argument that is actually logged was examined.
        var examined = 0
        for endpoint in bodies {
            for logCall in logCalls(in: endpoint.body) {
                for argument in payloadArguments(in: endpoint.signature)
                where logCall.contains(argument) {
                    examined += 1
                }
            }
        }
        #expect(examined >= 20, "only \(examined) argument log sites were examined")
    }

    // MARK: - Privacy

    // MARK: - Helpers

    private func endpointNames(in source: String) throws -> Set<String> {
        Set(source.matches(of: /void (clipboard\w+)\(/).map { String($0.output.1) })
    }
}


/// Collects a bridge callback from whichever thread delivers it.
private final class CallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedSuccess: Bool?
    private var storedCode: Int?

    func record(isSuccess: Bool, errorCode: Int) {
        lock.withLock {
            storedSuccess = isSuccess
            storedCode = errorCode
        }
    }

    var isSuccess: Bool? { lock.withLock { storedSuccess } }
    var errorCode: Int? { lock.withLock { storedCode } }
}
