//
//  LibraryLogPrivacyTests.swift
//  IosLibraryTests
//

import Foundation
import OSLog
import Testing
@testable import IosLibrary

/// UT-15: secret values never reach the library's log (design 8.7, `ios.md`).
///
/// Calls the library with sentinel values in the parameters that hold secrets (Share text, URL,
/// paths, subject and title, the contents of a notification, the clipboard text, an error that
/// carries a URL), then reads back this process's messages of the library's subsystem with
/// `OSLogStore` and checks that no sentinel is in any of them. `OSLogStore` does not return
/// `.debug` messages (MS-13), so the test raises the library's routine messages to `.info`
/// while it runs (`LibraryLogLevel`, Debug builds only).
///
/// In the simulator's test process `OSLogStore` shows `.private` values in clear (MS-13), so this
/// also catches a secret interpolated as `.private`. Where `.private` values are redacted, only
/// `.public` leaks are caught; `privateValuesAreVisible` records which case the run was.
@Suite(.serialized)
struct LibraryLogPrivacyTests {

    private static let subsystem = "com.jonghyunkim.nativetoolkit.IosLibrary"
    private static let secret = "sentinel-secret-5d0b"

    private func readLibraryMessages(since start: Date) throws -> [String] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        return try store.getEntries(at: store.position(date: start))
            .compactMap { $0 as? OSLogEntryLog }
            .filter { $0.subsystem == Self.subsystem }
            .map { "[\($0.category)] \($0.composedMessage)" }
    }

    private func withRaisedLevel<T>(_ body: () async throws -> T) async rethrows -> T {
        LibraryLogLevel.raisesDebugToInfo.store(true, ordering: .relaxed)
        defer { LibraryLogLevel.raisesDebugToInfo.store(false, ordering: .relaxed) }
        return try await body()
    }

    @Test func secretValuesNeverReachTheLog() async throws {
        let secret = Self.secret
        let start = Date().addingTimeInterval(-1)

        try await withRaisedLevel {
            // Share: the repository logs the subject (redacted), the manager logs the error.
            let presenter = await MainActor.run { MockShareSheetPresenter() }
            let repository = ShareRepositoryImpl(presenter: presenter)
            _ = try await repository.present(content: ShareContent(
                items: [.text("text-\(secret)"), .url("https://example.com/\(secret)")],
                subject: "subject-\(secret)",
                previewTitle: "title-\(secret)"
            ), presenter: .foreground)
            let failing = await MainActor.run { () -> MockShareRepository in
                let mock = MockShareRepository()
                mock.shouldFail = true
                mock.errorToThrow = .invalidURL("https://example.com/\(secret)")
                return mock
            }
            let shareManager = IosShareManager(repository: failing)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                shareManager.share(content: ShareContent(items: [.file(path: "/private/\(secret).txt")])) { _, _, _, _ in
                    continuation.resume()
                }
            }

            // Notification: the contents and the user info values.
            let notificationRepository = MockNotificationRepository()
            let notificationManager = IosNotificationManager(
                repository: notificationRepository,
                permissionHelper: NotificationPermissionHelper(repository: notificationRepository)
            )
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                notificationManager.show(content: NotificationContent(
                    id: "notification-id",
                    title: "title-\(secret)",
                    subtitle: "subtitle-\(secret)",
                    body: "body-\(secret)",
                    userInfo: ["key": "value-\(secret)"]
                )) { _, _ in continuation.resume() }
            }

            // Clipboard: the copied text.
            await MainActor.run {
                let useCases = ClipboardUseCases(
                    repository: MockClipboardRepository(),
                    loader: MockClipboardItemLoader(),
                    typeValidator: MockClipboardTypeIdentifierValidating()
                )
                IosClipboardManager(useCases: useCases).copy(.plainText("clipboard-\(secret)"))
            }
            await drainMainQueue(times: 3)
        }

        let messages = try readLibraryMessages(since: start)
        // The test reads what it means to read: the raised routine messages and the error.
        try #require(messages.contains { $0.contains("[ShareRepositoryImpl] [present] items: 2") },
                     "the library's routine messages must be readable, or the test checks nothing")
        try #require(messages.contains { $0.contains("[IosShareManager] [share] error: ") })
        try #require(messages.contains { $0.contains("[IosNotificationManager] [show] content.id: notification-id") })
        let leaks = messages.filter { $0.contains(secret) }
        #expect(leaks.isEmpty, "messages with a secret value: \(leaks)")
        // An error that carries a URL is logged by its case name (8.7.2).
        #expect(messages.contains { $0.contains("[IosShareManager] [share] error: ShareError.invalidURL") })
    }

    /// Dialog (8.7.2): the values entered in a text input and a login dialog, through the new API
    /// and the `show...` methods, on real alerts in the host app.
    @Test func dialogInputsNeverReachTheLog() async throws {
        // A sentinel of its own: the messages read back can include the previous test's.
        let secret = "sentinel-dialog-7c41"
        let start = Date().addingTimeInterval(-1)

        try await withRaisedLevel {
            try await withHostWindow { _ in
                let sessions = SessionRecorder()
                let manager = IosDialogManager(core: AlertDialogPresenter.recording(into: sessions))
                let done = MainRecorder<String>()

                manager.show(.textInput(title: nil, message: nil), presenter: .foreground) { _ in done.record("text") }
                try await Self.answer(sessions, count: 1, with: ["text-\(secret)"])
                manager.show(.login(title: nil, message: nil), presenter: .foreground) { _ in done.record("login") }
                try await Self.answer(sessions, count: 2, with: ["user-\(secret)", "password-\(secret)"])
                manager.showTextInputDialog(onConfirm: { _, _, _, _ in done.record("legacy text") })
                try await Self.answer(sessions, count: 3, with: ["legacy-text-\(secret)"])
                manager.showLoginDialog(onLogin: { _, _, _, _, _ in done.record("legacy login") })
                try await Self.answer(sessions, count: 4, with: ["legacy-user-\(secret)", "legacy-password-\(secret)"])
                #expect(await waitUntil { done.values.count == 4 })
            }
        }

        let messages = try readLibraryMessages(since: start)
        try #require(messages.contains { $0.contains("[IosDialogManager] [show] answer: primary, input: text(length: ") },
                     "the library's routine messages must be readable, or the test checks nothing")
        try #require(messages.contains { $0.contains("[IosDialogManager] [showLoginDialog] answer: primary, input: login(") })
        let leaks = messages.filter { $0.contains(secret) }
        #expect(leaks.isEmpty, "messages with a secret value: \(leaks)")
    }

    /// Share (8.7.2) through the manager's three forms, the library's repository and its real
    /// presenter on the host app: the text, URL, subject and title of what is shared, a file path,
    /// and an error that carries a URL. Both sheets end through the handler (completed, and with an
    /// error); dismissing them afterwards only cleans up (the external dismissal is not covered).
    @Test func shareContentThroughTheRealPresenterNeverReachesTheLog() async throws {
        let secret = "sentinel-share-a3f8"
        let start = Date().addingTimeInterval(-1)

        try await withRaisedLevel {
            try await withHostWindow { host in
                let sheets = SheetRecorder()
                let manager = IosShareManager(repository: ShareRepositoryImpl(presenter: ShareSheetPresenter.recording(into: sheets)))
                let content = ShareContent(items: [.text("text-\(secret)"), .url("https://example.com/\(secret)")],
                                           subject: "subject-\(secret)", previewTitle: "title-\(secret)",
                                           excludedActivityTypes: ["excluded-\(secret)"])
                let done = MainRecorder<String>()

                manager.share(content: content, presenter: .foreground) { _ in done.record("result") }
                #expect(await waitUntil { sheets.count == 1 && sheets.last?.presentingViewController != nil && sheets.last?.isBeingPresented == false })
                sheets.last?.completionWithItemsHandler?(.copyToPasteboard, true, nil, nil)
                #expect(await waitUntil { done.values.count == 1 })
                host.root.dismiss(animated: false)
                #expect(await waitUntil { host.root.presentedViewController == nil })

                manager.share(content: content) { _, _, _, _ in done.record("legacy") }
                #expect(await waitUntil { sheets.count == 2 && sheets.last?.presentingViewController != nil && sheets.last?.isBeingPresented == false })
                sheets.last?.completionWithItemsHandler?(nil, false, nil, NSError(domain: "TestShareDomain", code: 5,
                                                                                 userInfo: [NSLocalizedDescriptionKey: "error-\(secret)"]))
                #expect(await waitUntil { done.values.count == 2 })
                host.root.dismiss(animated: false)
                #expect(await waitUntil { host.root.presentedViewController == nil })

                await #expect(throws: ShareError.invalidURL("not a url \(secret)")) {
                    try await manager.share(content: ShareContent(items: [.url("not a url \(secret)"), .file(path: "/private/\(secret).txt")]),
                                            presenter: .foreground)
                }
            }
        }

        let messages = try readLibraryMessages(since: start)
        try #require(messages.contains { $0.contains("[ShareSheetPresenter] [completionWithItemsHandler] ") },
                     "the library's routine messages must be readable, or the test checks nothing")
        try #require(messages.contains { $0.contains("[IosShareManager] [share] error: ShareError.activityFailed(domain=TestShareDomain, code=5)") })
        try #require(messages.contains { $0.contains("[IosShareManager] [share async] error: ShareError.invalidURL") })
        let leaks = messages.filter { $0.contains(secret) }
        #expect(leaks.isEmpty, "messages with a secret value: \(leaks)")
    }

    /// Types `values` into the fields of the latest dialog and presses its primary button.
    @MainActor
    private static func answer(_ sessions: SessionRecorder, count: Int, with values: [String]) async throws {
        #expect(await waitUntil { sessions.sessions.count == count && sessions.last?.isPresented == true })
        let session = try #require(sessions.last)
        for (field, value) in zip(session.alert?.textFields ?? [], values) {
            field.text = value
        }
        session.press(0)
        _ = await waitUntil { session.alert == nil || session.alert?.presentingViewController == nil }
    }

    /// Notification through `NotificationRepositoryImpl` and the host app's real notification
    /// center (C1 could only reach the manager: the repository needs an app).
    @Test func notificationContentsThroughTheRealCenterNeverReachTheLog() async throws {
        let secret = "sentinel-notification-2e93"
        let start = Date().addingTimeInterval(-1)
        let identifier = "ut15-\(UUID().uuidString)"

        await withRaisedLevel {
            let repository = NotificationRepositoryImpl()
            // An hour away, and removed again: nothing is shown whether or not the host app may
            // post notifications (without the permission `add` fails, which logs the error path).
            try? await repository.schedule(content: NotificationContent(
                id: identifier,
                title: "title-\(secret)",
                subtitle: "subtitle-\(secret)",
                body: "body-\(secret)",
                userInfo: ["key": "value-\(secret)"]
            ), trigger: .timeInterval(3600, repeats: false), identifier: identifier)
            await repository.cancelScheduled(identifier: identifier)
            _ = await repository.getScheduled()
        }

        let messages = try readLibraryMessages(since: start)
        try #require(messages.contains { $0.contains("[NotificationRepositoryImpl] [schedule] identifier: \(identifier)") },
                     "the repository's messages must be readable, or the test checks nothing")
        let leaks = messages.filter { $0.contains(secret) }
        #expect(leaks.isEmpty, "messages with a secret value: \(leaks)")
    }

    /// Records whether this environment shows `.private` values in `OSLogStore` (MS-13). Not an
    /// assertion about the library.
    @Test func privateValuesAreVisible() throws {
        let start = Date().addingTimeInterval(-1)
        let token = UUID().uuidString
        Logger(subsystem: Self.subsystem, category: "LibraryLogPrivacyTests").info("canary \(token, privacy: .private)")

        let messages = try readLibraryMessages(since: start).filter { $0.contains("canary") }
        let visible = messages.contains { $0.contains(token) }
        print("UT-15: .private values are \(visible ? "visible" : "redacted") in OSLogStore here")
        #expect(messages.count == 1)
    }

    @Test func theRaisedLevelIsOnlyOnWhileTheTestRuns() async {
        #expect(OSLogType.libraryDebug == .debug)
        await withRaisedLevel {
            #expect(OSLogType.libraryDebug == .info)
        }
        #expect(OSLogType.libraryDebug == .debug)
    }
}

/// The helpers that keep secret values out of the log.
struct LogRedactionTests {

    private enum SampleError: Error {
        case plain
        case withPath(path: String)
    }

    @Test func redactShowsOnlyTheLength() {
        #expect(LogRedaction.redact("pässword") == "<redacted, length=9>")
        #expect(LogRedaction.redact(nil) == "nil")
        #expect(LogRedaction.length("abc") == "length=3")
        #expect(LogRedaction.length(nil) == "nil")
        #expect(!LogRedaction.redact("secret-value").contains("secret"))
    }

    @Test func caseNameDropsTheAssociatedValues() {
        #expect(LogRedaction.caseName(ShareError.imageLoadFailed(path: "/private/secret.png")) == "imageLoadFailed")
        #expect(LogRedaction.caseName(ShareError.noValidItems) == "noValidItems")
        #expect(LogRedaction.caseName(SampleError.withPath(path: "/secret")) == "withPath")
        #expect(LogRedaction.caseName("not an enum") == "String")
    }

    @Test func describeAddsTheDomainAndCodeOfAnInnerError() {
        let inner = NSError(domain: "UNErrorDomain", code: 1, userInfo: [NSLocalizedDescriptionKey: "secret text"])
        let described = LogRedaction.describe(NotificationError.addRequestFailed(inner))

        #expect(described == "NotificationError.addRequestFailed(domain=UNErrorDomain, code=1)")
        #expect(!described.contains("secret"))
        #expect(LogRedaction.describe(ShareError.activityFailed(FailureDetail(systemError: inner))) == "ShareError.activityFailed(domain=UNErrorDomain, code=1)")
        // A payload that is not an error is never shown.
        #expect(LogRedaction.describe(ShareError.fileNotFound(path: "/private/secret.txt")) == "ShareError.fileNotFound")
    }

    @Test func describeUsesTheCaseNameOrTheDomainAndCode() {
        #expect(LogRedaction.describe(ShareError.invalidURL("https://secret.example")) == "ShareError.invalidURL")
        #expect(LogRedaction.describe(SampleError.plain) == "SampleError.plain")
        let error = NSError(domain: "com.example", code: 3, userInfo: [NSLocalizedDescriptionKey: "secret text"])
        #expect(LogRedaction.describe(error) == "domain=com.example, code=3")
    }
}
