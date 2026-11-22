//
//  SampleUITestCase.swift
//  MacLibraryExampleUITests
//
//  Base class of every new UI test class (UI test design U-9, 6.1). Trusted Support file: it reads
//  the declaration table, tells the qualified VM from this Mac by fact, decides whether a test may
//  run here, issues the per-category tokens and installs the interruption monitor. Test classes
//  are `final class <Name>: SampleUITestCase` and only override `setUpAfterGate()` /
//  `tearDownAfterGate()`.
//

import XCTest
import Foundation
import Darwin

// MARK: - Errors

/// A plain `Error` (not `XCTSkip`) thrown by the base and the Support helpers, so that the test
/// fails and stops at that point. The text starts with `NTK-STEP:<step>` (design 3.4).
struct SampleUITestError: Error, CustomStringConvertible {
    let step: StepCode
    let detail: String

    init(_ step: StepCode, _ detail: String) {
        self.step = step
        self.detail = detail
    }

    var description: String { "NTK-STEP:\(step.rawValue) \(detail)" }
}

// MARK: - Declared categories and tokens

/// The ten categories a test declares in `DeviceRequirements.json` (design 3.3, U-9).
enum DeviceCategory: String, CaseIterable {
    case notification
    case ncsettings
    case settings
    case badge
    case clipboard
    case pasteprivacy
    case sharepicker
    case realservice
    case panels
    case coldstart

    /// Categories that run only on the qualified VM, never on this Mac.
    var isVMOnly: Bool {
        self == .ncsettings || self == .pasteprivacy || self == .realservice
    }
}

/// Proof that the running test declared `notification` and that it is allowed here. Only this file
/// creates tokens; tests get one through `notificationToken()`.
struct NotificationToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `ncsettings`. See `NotificationToken`.
struct NCSettingsToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `settings`. See `NotificationToken`.
struct SettingsToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `badge`. See `NotificationToken`.
struct BadgeToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `clipboard`. See `NotificationToken`.
struct ClipboardToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `pasteprivacy`. See `NotificationToken`.
struct PastePrivacyToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `sharepicker`. See `NotificationToken`.
struct SharePickerToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `realservice`. See `NotificationToken`.
struct RealServiceToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `panels`. See `NotificationToken`.
struct PanelsToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `coldstart`. See `NotificationToken`.
struct ColdStartToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

// MARK: - Host

/// Where the tests run (U-9). `vm` is accepted only when the runner says so and the machine is a
/// virtual machine by fact; any other value of `NTK_HOST` is this Mac.
enum TestHost: Equatable {
    case vm
    case mac

    /// `TEST_RUNNER_NTK_HOST`, received by the runner process as `NTK_HOST` (stage 0c, VM).
    static func resolve(environment: [String: String], hypervisorPresent: () -> Int32?) throws -> TestHost {
        guard environment["NTK_HOST"] == "vm" else { return .mac }
        guard hypervisorPresent() == 1 else {
            throw SampleUITestError(.gate, "NTK_HOST is vm but kern.hv_vmm_present is not 1")
        }
        return .vm
    }

    /// `sysctl kern.hv_vmm_present`; nil when it cannot be read.
    static func readHypervisorPresent() -> Int32? {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.hv_vmm_present", &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}

// MARK: - Per-test session state

/// Mutable state of one test, shared by the base, the Support helpers and the interruption monitor.
/// XCTest creates one test case object per test method, so each test gets its own.
final class UITestSession {

    enum InterruptionMark: Equatable {
        case none
        /// Something interrupted; nothing was pressed and the sample was terminated (U-8).
        case unknownInterruption
    }

    let host: TestHost
    let testKey: String

    var interruption: InterruptionMark = .none
    /// The element type of the interruption (no label is read. U-8).
    var interruptionDetail = ""
    var monitorInvocations = 0

    /// Identifiers of the sample's buttons pressed through `SampleApp`, in first-press order and
    /// without duplicates (design 5.7).
    private(set) var pressedButtons: [String] = []

    fileprivate init(host: TestHost, testKey: String) {
        self.host = host
        self.testKey = testKey
    }

    func recordPressed(_ identifier: String) {
        if !pressedButtons.contains(identifier) {
            pressedButtons.append(identifier)
        }
    }

    /// Throws when the interruption monitor has marked this test. Every Support wrapper calls it
    /// right after an XCUI operation (U-8).
    func checkInterruption() throws {
        switch interruption {
        case .none:
            return
        case .unknownInterruption:
            throw SampleUITestError(.interrupted, "NTK-INTERRUPTED an interruption stopped the test; nothing was pressed and the sample was terminated (\(interruptionDetail))")
        }
    }
}

// MARK: - Declaration table

/// Reads `Support/DeviceRequirements.json` from the test bundle (U-9, 6.1).
enum DeviceRequirements {

    static let resourceName = "DeviceRequirements"

    /// Categories declared for `key` (`<Class>/<method>`). Throws when the table is broken or has no
    /// entry for the test.
    static func categories(for key: String) throws -> Set<DeviceCategory> {
        let table = try load()
        guard let entry = table[key] else {
            throw SampleUITestError(.gate, "\(resourceName).json has no entry for \(key)")
        }
        return entry
    }

    /// Parses the whole table. Re-read on every call so that every check sees the bundled file.
    static func load() throws -> [String: Set<DeviceCategory>] {
        guard let url = Bundle(for: SampleUITestCase.self).url(forResource: resourceName, withExtension: "json") else {
            throw SampleUITestError(.gate, "\(resourceName).json is not in the test bundle")
        }
        return try parse(Data(contentsOf: url))
    }

    static func parse(_ data: Data) throws -> [String: Set<DeviceCategory>] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SampleUITestError(.gate, "\(resourceName).json is not an object")
        }
        guard Set(root.keys) == ["schema", "tests"] else {
            throw SampleUITestError(.gate, "\(resourceName).json must have exactly the keys schema and tests")
        }
        guard let schema = root["schema"] as? Int, schema == 1 else {
            throw SampleUITestError(.gate, "\(resourceName).json schema must be 1")
        }
        guard let tests = root["tests"] as? [String: Any] else {
            throw SampleUITestError(.gate, "\(resourceName).json tests must be an object")
        }
        // JSONSerialization keeps the last of duplicated keys silently; count the keys in the text.
        let text = String(decoding: data, as: UTF8.self)
        let keyPattern = try NSRegularExpression(pattern: "\"([^\"\\\\]+)\"\\s*:\\s*\\[")
        let keyCount = keyPattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        guard keyCount == tests.count else {
            throw SampleUITestError(.gate, "\(resourceName).json has duplicated test keys (\(keyCount) keys, \(tests.count) unique)")
        }
        var table: [String: Set<DeviceCategory>] = [:]
        for (key, value) in tests {
            guard SampleUITestCase.isWellFormedKey(key) else {
                throw SampleUITestError(.gate, "\(resourceName).json key is not <Class>/<testMethod>: \(key)")
            }
            guard let names = value as? [String] else {
                throw SampleUITestError(.gate, "\(resourceName).json value of \(key) must be an array of strings")
            }
            var categories: Set<DeviceCategory> = []
            for name in names {
                guard let category = DeviceCategory(rawValue: name) else {
                    throw SampleUITestError(.gate, "\(resourceName).json \(key) has an unknown category: \(name)")
                }
                guard categories.insert(category).inserted else {
                    throw SampleUITestError(.gate, "\(resourceName).json \(key) repeats the category \(name)")
                }
            }
            table[key] = categories
        }
        return table
    }
}

// MARK: - Base class

/// Base of every new UI test class.
///
/// `setUpWithError` runs the gate (U-9 second stage) and then calls `setUpAfterGate()`;
/// `tearDownWithError` calls `tearDownAfterGate()` only when the gate passed and the interruption
/// monitor has not stopped the test (U-8). `setUp()`, `tearDown()` and the completion-handler forms
/// are `final` and only call `super`; the async forms are not overridden (iOS stage 0c: overriding
/// them crashed the runner on a failure), so the closed source rule (design 6.1) stops a subclass
/// from overriding them.
class SampleUITestCase: XCTestCase {

    /// Major version of the OS the runner runs on (the same OS as the sample).
    static var osMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// True once the gate of `setUpWithError` has passed for this test.
    private(set) var gatePassed = false

    private var testSession: UITestSession?
    private var launchedSample: SampleApp?

    // MARK: Entry points (final)

    final override func setUp() {
        super.setUp()
    }

    final override func setUp(completion: @escaping (Error?) -> Void) {
        super.setUp(completion: completion)
    }

    final override func tearDown() {
        super.tearDown()
    }

    final override func tearDown(completion: @escaping (Error?) -> Void) {
        super.tearDown(completion: completion)
    }

    final override func setUpWithError() throws {
        gatePassed = false
        continueAfterFailure = false
        let key = try Self.normalizedTestKey(fromName: name)
        let declared = try DeviceRequirements.categories(for: key)
        let host = try TestHost.resolve(environment: ProcessInfo.processInfo.environment,
                                        hypervisorPresent: TestHost.readHypervisorPresent)
        let allowed = try Self.allowance(host: host)
        if let missing = DeviceCategory.allCases.first(where: { declared.contains($0) && !allowed.contains($0) }) {
            throw XCTSkip("NTK-GATED:\(missing.rawValue)")
        }
        let session = UITestSession(host: host, testKey: key)
        testSession = session
        UnexpectedInterruptionGuard.install(on: self, session: session)
        gatePassed = true
        try setUpAfterGate()
    }

    final override func tearDownWithError() throws {
        guard gatePassed, let session = testSession else { return }
        var firstError: Error?
        // After the monitor stopped the test the ordinary cleanup is not called (U-8).
        if session.interruption == .none {
            do {
                try tearDownAfterGate()
            } catch {
                firstError = error
            }
        }
        if let sample = launchedSample {
            attachButtonCoverage(session.pressedButtons)
            // Leave no alert, panel or picker of the sample on screen after the test.
            sample.terminateQuietly()
        }
        if let firstError {
            throw firstError
        }
    }

    // MARK: Hooks for test classes

    /// Called after the gate passed. Test classes launch the sample here.
    func setUpAfterGate() throws {}

    /// Called only when the gate passed and the interruption monitor did not stop the test.
    func tearDownAfterGate() throws {}

    // MARK: Sample app

    /// Launches the sample for this test (a new process for every test. U-15).
    func launchSample() throws -> SampleApp {
        let session = try requireSession()
        let sample = SampleApp(session: session)
        launchedSample = sample
        try sample.launch()
        return sample
    }

    /// The host this test runs on (after the gate).
    func testHost() throws -> TestHost {
        try requireSession().host
    }

    // MARK: Tokens

    func notificationToken() throws -> NotificationToken {
        NotificationToken(session: try authorize(.notification))
    }

    func ncSettingsToken() throws -> NCSettingsToken {
        NCSettingsToken(session: try authorize(.ncsettings))
    }

    func settingsToken() throws -> SettingsToken {
        SettingsToken(session: try authorize(.settings))
    }

    func badgeToken() throws -> BadgeToken {
        BadgeToken(session: try authorize(.badge))
    }

    func clipboardToken() throws -> ClipboardToken {
        ClipboardToken(session: try authorize(.clipboard))
    }

    func pastePrivacyToken() throws -> PastePrivacyToken {
        PastePrivacyToken(session: try authorize(.pasteprivacy))
    }

    func sharePickerToken() throws -> SharePickerToken {
        SharePickerToken(session: try authorize(.sharepicker))
    }

    func realServiceToken() throws -> RealServiceToken {
        RealServiceToken(session: try authorize(.realservice))
    }

    func panelsToken() throws -> PanelsToken {
        PanelsToken(session: try authorize(.panels))
    }

    func coldStartToken() throws -> ColdStartToken {
        ColdStartToken(session: try authorize(.coldstart))
    }

    /// Re-reads `self.name`, the table, the host and `NTK_ALLOW` on every call.
    private func authorize(_ category: DeviceCategory) throws -> UITestSession {
        guard gatePassed else {
            throw SampleUITestError(.gate, "token \(category.rawValue) requested before the gate passed")
        }
        let session = try requireSession()
        let key = try Self.normalizedTestKey(fromName: name)
        guard key == session.testKey else {
            throw SampleUITestError(.gate, "test key changed during the test: \(session.testKey) -> \(key)")
        }
        guard try DeviceRequirements.categories(for: key).contains(category) else {
            throw SampleUITestError(.gate, "\(key) does not declare \(category.rawValue) in DeviceRequirements.json")
        }
        let host = try TestHost.resolve(environment: ProcessInfo.processInfo.environment,
                                        hypervisorPresent: TestHost.readHypervisorPresent)
        guard host == session.host else {
            throw SampleUITestError(.gate, "the host changed during the test")
        }
        guard try Self.allowance(host: host).contains(category) else {
            throw SampleUITestError(.gate, "\(category.rawValue) is not allowed here (NTK_ALLOW)")
        }
        return session
    }

    private func requireSession() throws -> UITestSession {
        guard gatePassed, let session = testSession else {
            throw SampleUITestError(.gate, "the gate of setUpWithError has not passed")
        }
        return session
    }

    // MARK: Name and allowance

    /// `-[<Module>.<Class> <method>]` or `-[<Class> <method>]` -> `<Class>/<method>`. Any other shape
    /// throws, so a test whose name cannot be read never runs.
    static func normalizedTestKey(fromName name: String) throws -> String {
        guard name.hasPrefix("-["), name.hasSuffix("]") else {
            throw SampleUITestError(.gate, "unexpected test name shape: \(name)")
        }
        let inner = name.dropFirst(2).dropLast()
        let parts = inner.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw SampleUITestError(.gate, "unexpected test name shape: \(name)")
        }
        let classParts = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard classParts.count == 1 || (classParts.count == 2 && classParts[0] == "MacLibraryExampleUITests") else {
            throw SampleUITestError(.gate, "unexpected test name shape: \(name)")
        }
        let key = "\(classParts[classParts.count - 1])/\(parts[1])"
        guard isWellFormedKey(key) else {
            throw SampleUITestError(.gate, "unexpected test name shape: \(name)")
        }
        return key
    }

    /// `<Class>/test<Name>` with identifier characters only (no module prefix, no `()`).
    static func isWellFormedKey(_ key: String) -> Bool {
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return false }
        return isIdentifier(parts[0]) && isIdentifier(parts[1]) && parts[1].hasPrefix("test")
    }

    private static func isIdentifier(_ text: Substring) -> Bool {
        guard let first = text.first, first == "_" || (first.isASCII && first.isLetter) else { return false }
        return text.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isLetter || $0.isNumber)) }
    }

    /// Categories allowed by the runner (`TEST_RUNNER_NTK_ALLOW`, received as `NTK_ALLOW`). Unknown
    /// names throw, and so does a VM-only category on this Mac (fail closed).
    static func allowance(host: TestHost) throws -> Set<DeviceCategory> {
        try allowance(raw: ProcessInfo.processInfo.environment["NTK_ALLOW"] ?? "", host: host)
    }

    static func allowance(raw: String, host: TestHost) throws -> Set<DeviceCategory> {
        var allowed: Set<DeviceCategory> = []
        for name in raw.split(separator: ",") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard let category = DeviceCategory(rawValue: trimmed) else {
                throw SampleUITestError(.gate, "NTK_ALLOW has an unknown category: \(trimmed)")
            }
            if host == .mac && category.isVMOnly {
                throw SampleUITestError(.gate, "NTK_ALLOW has the VM-only category \(trimmed) on this Mac")
            }
            allowed.insert(category)
        }
        return allowed
    }

    // MARK: Button coverage (design 5.7)

    private func attachButtonCoverage(_ pressed: [String]) {
        let data = (try? JSONSerialization.data(withJSONObject: pressed, options: [.sortedKeys])) ?? Data("[]".utf8)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ntk-button-coverage-v1.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
