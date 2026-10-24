//
//  SampleUITestCase.swift
//  IosLibraryExampleUITests
//
//  Base class of every UI test class (UI test design U-9, 6.1). Part of the trusted Support files:
//  it decides whether a test may run on a (private) device, issues the per-category tokens, and
//  installs the interruption monitor. Test classes are `final class <Name>: SampleUITestCase` and
//  only override `setUpAfterGate()` / `tearDownAfterGate()`.
//

import XCTest
import Foundation

// MARK: - Errors

/// A plain `Error` (not `XCTSkip`) thrown by the base and the Support helpers, so that the test
/// fails and stops at that point.
struct SampleUITestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

// MARK: - Device permission categories and tokens

/// The six categories a test declares in `DeviceRequirements.json` (U-9).
enum DeviceCategory: String, CaseIterable {
    case systemui
    case sharesheet
    case clipboard
    case files
    case reinstall
    case credentials
}

/// Proof that the running test declared `systemui` and that it is allowed here.
/// Only this file can create a token; tests get one through `systemUIToken()`.
struct SystemUIToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `sharesheet`. See `SystemUIToken`.
struct ShareSheetToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `clipboard`. See `SystemUIToken`.
struct ClipboardToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `files`. See `SystemUIToken`.
struct FilesToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `reinstall`. See `SystemUIToken`.
struct ReinstallToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

/// Proof for `credentials`. See `SystemUIToken`.
struct CredentialsToken {
    let session: UITestSession
    fileprivate init(session: UITestSession) { self.session = session }
}

// MARK: - Per-test session state

/// Mutable state of one test, shared by the base, the Support helpers and the interruption
/// monitor. A new instance is created for every test (XCTest creates one test case object per
/// test method).
final class UITestSession {

    /// What the interruption monitor did (U-8). Set only inside the monitor.
    enum InterruptionMark: Equatable {
        case none
        /// A known negative button of an alert of the sample was pressed.
        case knownAlertDenied
        /// Something else interrupted; nothing was pressed and the app was terminated.
        case unknownInterruption
    }

    let isDevice: Bool
    let testKey: String

    var interruption: InterruptionMark = .none
    /// Description of the interruption for the failure message. On the device it never contains
    /// a label of the system UI.
    var interruptionDetail = ""
    /// Number of times the monitor was invoked (diagnostics).
    var monitorInvocations = 0

    /// Identifiers of the sample's buttons pressed through `SampleApp`, in first-press order and
    /// without duplicates (design 3.7).
    private(set) var pressedButtons: [String] = []

    /// Whether this test received a `SystemUIToken` (springboard cleanup only runs then. U-15).
    fileprivate(set) var systemUITokenIssued = false

    fileprivate init(isDevice: Bool, testKey: String) {
        self.isDevice = isDevice
        self.testKey = testKey
    }

    func recordPressed(_ identifier: String) {
        if !pressedButtons.contains(identifier) {
            pressedButtons.append(identifier)
        }
    }

    /// Throws when the interruption monitor has marked this test. Every Support wrapper calls it
    /// right after an XCUI operation.
    func checkInterruption() throws {
        switch interruption {
        case .none:
            return
        case .knownAlertDenied:
            throw SampleUITestError("an alert of the sample interrupted the test and its negative button was pressed: \(interruptionDetail)")
        case .unknownInterruption:
            throw SampleUITestError("an unknown interruption stopped the test; nothing was pressed and the app was terminated: \(interruptionDetail)")
        }
    }
}

// MARK: - Declaration table

/// Reads `Support/DeviceRequirements.json` from the test bundle (U-9, 6.1).
enum DeviceRequirements {

    static let resourceName = "DeviceRequirements"

    /// Categories declared for `key` (`<Class>/<method>`). Throws when the table is broken or has
    /// no entry for the test.
    static func categories(for key: String) throws -> Set<DeviceCategory> {
        let table = try load()
        guard let entry = table[key] else {
            throw SampleUITestError("\(resourceName).json has no entry for \(key)")
        }
        return entry
    }

    /// Parses the whole table. Re-read on every call so that every check sees the bundled file.
    static func load() throws -> [String: Set<DeviceCategory>] {
        guard let url = Bundle(for: SampleUITestCase.self).url(forResource: resourceName, withExtension: "json") else {
            throw SampleUITestError("\(resourceName).json is not in the test bundle")
        }
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SampleUITestError("\(resourceName).json is not an object")
        }
        guard Set(root.keys) == ["schema", "tests"] else {
            throw SampleUITestError("\(resourceName).json must have exactly the keys schema and tests")
        }
        guard let schema = root["schema"] as? Int, schema == 1 else {
            throw SampleUITestError("\(resourceName).json schema must be 1")
        }
        guard let tests = root["tests"] as? [String: Any] else {
            throw SampleUITestError("\(resourceName).json tests must be an object")
        }
        // JSONSerialization keeps the last of duplicated keys silently; count the keys in the text.
        let text = String(decoding: data, as: UTF8.self)
        let keyPattern = try NSRegularExpression(pattern: "\"([^\"\\\\]+)\"\\s*:\\s*\\[")
        let keyCount = keyPattern.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
        guard keyCount == tests.count else {
            throw SampleUITestError("\(resourceName).json has duplicated test keys (\(keyCount) keys, \(tests.count) unique)")
        }
        var table: [String: Set<DeviceCategory>] = [:]
        for (key, value) in tests {
            guard SampleUITestCase.isWellFormedKey(key) else {
                throw SampleUITestError("\(resourceName).json key is not <Class>/<testMethod>: \(key)")
            }
            guard let names = value as? [String] else {
                throw SampleUITestError("\(resourceName).json value of \(key) must be an array of strings")
            }
            var categories: Set<DeviceCategory> = []
            for name in names {
                guard let category = DeviceCategory(rawValue: name) else {
                    throw SampleUITestError("\(resourceName).json \(key) has an unknown category: \(name)")
                }
                guard categories.insert(category).inserted else {
                    throw SampleUITestError("\(resourceName).json \(key) repeats the category \(name)")
                }
            }
            table[key] = categories
        }
        return table
    }
}

// MARK: - Base class

/// Base of every UI test class.
///
/// `setUpWithError` runs the gate (U-9 second stage) and then calls `setUpAfterGate()`;
/// `tearDownWithError` calls `tearDownAfterGate()` and the cleanups only when the gate passed
/// (`XCTSkip` thrown from `setUpWithError` still runs `tearDownWithError`. Stage 0a section 8).
/// `setUp()`, `tearDown()` and the completion-handler forms are `final` and only call `super`
/// (the async forms are not overridden; see "Entry points").
class SampleUITestCase: XCTestCase {

    /// The only place in the test target that tells the simulator from the device (6.1 `#if`).
    static var isDevice: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return true
        #endif
    }

    /// Major version of the OS the runner runs on (the same OS as the sample app).
    static var osMajorVersion: Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }

    /// True once the gate of `setUpWithError` has passed for this test.
    private(set) var gatePassed = false

    private var testSession: UITestSession?
    private var launchedSample: SampleApp?

    // MARK: Entry points (final)

    // The async forms `setUp() async throws` / `tearDown() async throws` are not overridden: with
    // them, a failure raised inside XCTest with `continueAfterFailure == false` crashed the test
    // runner (Xcode 26.3, stage 0c). They share their Objective-C selectors with the completion
    // forms below, yet a subclass can still override the async forms (it compiles and runs before
    // the gate), so only the closed source rule (design 6.1, `override` limited to the two hooks)
    // stops them.

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
        if Self.isDevice {
            let allowed = try Self.deviceAllowance()
            if let missing = DeviceCategory.allCases.first(where: { declared.contains($0) && !allowed.contains($0) }) {
                throw XCTSkip("NTK-GATED:\(missing.rawValue)")
            }
        }
        let session = UITestSession(isDevice: Self.isDevice, testKey: key)
        testSession = session
        XCUIDevice.shared.orientation = .portrait
        UnexpectedAlertGuard.install(
            on: self,
            session: session,
            mode: UnexpectedAlertGuard.mode(forTestKey: key),
            declared: declared
        )
        gatePassed = true
        try setUpAfterGate()
    }

    final override func tearDownWithError() throws {
        guard gatePassed, let session = testSession else { return }
        var firstError: Error?
        do {
            try tearDownAfterGate()
        } catch {
            firstError = error
        }
        // On the device, after the monitor stopped the test at an alert it did not answer, the
        // springboard cleanup (the home button) is skipped: it could close a private system alert
        // (stage 0d review R-4).
        if session.systemUITokenIssued && !(session.isDevice && session.interruption != UITestSession.InterruptionMark.none) {
            do {
                try NotificationCleanup.springboard(SystemUIToken(session: session))
            } catch {
                firstError = firstError ?? error
            }
        }
        if launchedSample != nil {
            attachButtonCoverage(session.pressedButtons)
        }
        if let firstError {
            throw firstError
        }
    }

    // MARK: Hooks for test classes

    /// Called after the gate passed. Test classes launch the sample here.
    func setUpAfterGate() throws {}

    /// Called only when the gate passed.
    func tearDownAfterGate() throws {}

    // MARK: Sample app

    /// Launches the sample app for this test (a new process for every test. U-15).
    func launchSample() throws -> SampleApp {
        let session = try requireSession()
        let sample = SampleApp(session: session)
        try sample.launch()
        launchedSample = sample
        return sample
    }

    // MARK: Tokens

    func systemUIToken() throws -> SystemUIToken {
        let session = try authorize(.systemui)
        session.systemUITokenIssued = true
        return SystemUIToken(session: session)
    }

    func shareSheetToken() throws -> ShareSheetToken {
        ShareSheetToken(session: try authorize(.sharesheet))
    }

    func clipboardToken() throws -> ClipboardToken {
        ClipboardToken(session: try authorize(.clipboard))
    }

    func filesToken() throws -> FilesToken {
        FilesToken(session: try authorize(.files))
    }

    func reinstallToken() throws -> ReinstallToken {
        ReinstallToken(session: try authorize(.reinstall))
    }

    func credentialsToken() throws -> CredentialsToken {
        CredentialsToken(session: try authorize(.credentials))
    }

    /// Re-reads `self.name`, the table and `NTK_DEVICE_ALLOW` on every call.
    private func authorize(_ category: DeviceCategory) throws -> UITestSession {
        guard gatePassed else {
            throw SampleUITestError("token \(category.rawValue) requested before the gate passed")
        }
        let session = try requireSession()
        let key = try Self.normalizedTestKey(fromName: name)
        guard key == session.testKey else {
            throw SampleUITestError("test key changed during the test: \(session.testKey) -> \(key)")
        }
        let declared = try DeviceRequirements.categories(for: key)
        guard declared.contains(category) else {
            throw SampleUITestError("\(key) does not declare \(category.rawValue) in DeviceRequirements.json")
        }
        if Self.isDevice {
            guard try Self.deviceAllowance().contains(category) else {
                throw SampleUITestError("\(category.rawValue) is not allowed on this device (NTK_DEVICE_ALLOW)")
            }
        }
        return session
    }

    private func requireSession() throws -> UITestSession {
        guard gatePassed, let session = testSession else {
            throw SampleUITestError("the gate of setUpWithError has not passed")
        }
        return session
    }

    // MARK: Name and allowance

    /// `-[<Class> <method>]` (Xcode 26.3, stage 0a section 8) -> `<Class>/<method>`.
    /// Any other shape throws, so a test whose name cannot be read never runs.
    static func normalizedTestKey(fromName name: String) throws -> String {
        guard name.hasPrefix("-["), name.hasSuffix("]") else {
            throw SampleUITestError("unexpected test name shape: \(name)")
        }
        let inner = name.dropFirst(2).dropLast()
        let parts = inner.split(separator: " ", omittingEmptySubsequences: false)
        guard parts.count == 2 else {
            throw SampleUITestError("unexpected test name shape: \(name)")
        }
        let key = "\(parts[0])/\(parts[1])"
        guard isWellFormedKey(key) else {
            throw SampleUITestError("unexpected test name shape: \(name)")
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

    /// Categories allowed on the device by the runner (`TEST_RUNNER_NTK_DEVICE_ALLOW`, received as
    /// `NTK_DEVICE_ALLOW`). Unknown names throw (fail closed). Not read on the simulator.
    static func deviceAllowance() throws -> Set<DeviceCategory> {
        let raw = ProcessInfo.processInfo.environment["NTK_DEVICE_ALLOW"] ?? ""
        var allowed: Set<DeviceCategory> = []
        for name in raw.split(separator: ",") {
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard let category = DeviceCategory(rawValue: trimmed) else {
                throw SampleUITestError("NTK_DEVICE_ALLOW has an unknown category: \(trimmed)")
            }
            allowed.insert(category)
        }
        return allowed
    }

    // MARK: Button coverage (design 3.7)

    private func attachButtonCoverage(_ pressed: [String]) {
        let data = (try? JSONSerialization.data(withJSONObject: pressed, options: [.sortedKeys])) ?? Data("[]".utf8)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "ntk-button-coverage-v1.json"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
