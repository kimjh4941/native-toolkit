import Combine
import Foundation
import IosLibrary
import os

private let logger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "NotificationEventLog")
private let viewModelLogger = Logger(subsystem: "com.jonghyunkim.ios.nativetoolkit.example", category: "NotificationEventViewModel")

/// The most recent notification event the sample received, plus how many events arrived.
///
/// Shown on the Notification screen so a UI test can confirm that a tap, an action or a reply
/// actually reached the app (the receivers used to only log it).
struct NotificationEventSnapshot: Equatable {

    enum Kind: String {
        /// A response without text (taps use the default action identifier).
        case action
        /// A text input reply.
        case textInput
    }

    /// Which entry of the library delivered the event (Swift API design SA-18).
    enum Path: String {
        /// A listener of `IosNotificationManager.responses`.
        case hub
        /// The deprecated `onActionReceived` / `onTextInputActionReceived`.
        case legacy
    }

    /// When a hub listener received the event.
    enum Delivery: String {
        /// After the listener was added (a later main-queue block).
        case live
        /// Inside the `addListener` call: the hub kept it while there was no listener.
        case held
    }

    /// Number of events received by this process. Increases by one per event.
    let sequence: Int
    /// `nil` until the first event.
    let kind: Kind?
    let notificationId: String?
    let actionId: String?
    /// Reply text of a text input action. `nil` for a plain action.
    let userText: String?
    let path: Path?
    let isLaunchResponse: Bool
    let delivery: Delivery?

    static let initial = NotificationEventSnapshot(
        sequence: 0,
        kind: nil,
        notificationId: nil,
        actionId: nil,
        userText: nil,
        path: nil,
        isLaunchResponse: false,
        delivery: nil
    )
}

/// The other state of the notification events the screen shows (SA-06, SA-11, SA-12, SA-18):
/// how this launch set the library up, the listeners' counts, the last settings request and
/// what the host delegate received.
struct NotificationSampleStatus: Equatable {
    /// `installed`, `notMainThread`, or `setup()` (the legacy path).
    var install = "-"
    var isDelegateInstalled = false
    var mode: SampleTestMode = .none
    var source: SampleConfigurationSource = .defaults
    var hostDelegate = false
    /// Events the first listener of `responses` received.
    var firstListenerCount = 0
    /// Events the second listener received (SA-06).
    var secondListenerCount = 0
    /// `none`, `added` or `removed`.
    var secondListenerState = "none"
    var settingsRequestCount = 0
    var lastSettingsRequestId: String?
    var hostWillPresentCount = 0
    var hostDidReceiveCount = 0
    var hostLastNotificationId: String?
    var hostLastActionId: String?
}

/// App-wide store of the last notification event and the status.
///
/// `record(...)` writes synchronously on the calling thread under a lock, so the event is stored
/// before the library calls the system `completionHandler` — even when the process is suspended
/// right after a background action. Only the "reload" signal is sent to the main thread; it
/// carries no value, and the screen always reads the current value from this store. Nothing is
/// persisted: every process starts from `NotificationEventSnapshot.initial`.
final class NotificationEventLog: @unchecked Sendable {

    static let shared = NotificationEventLog()

    /// Posted on the main thread after each change. Carries no value.
    static let didRecord = Notification.Name("NotificationEventLog.didRecord")

    private let lock = NSLock()
    private var current = NotificationEventSnapshot.initial
    private var currentStatus = NotificationSampleStatus()

    private init() {}

    func record(
        kind: NotificationEventSnapshot.Kind,
        notificationId: String,
        actionId: String,
        userText: String?,
        path: NotificationEventSnapshot.Path,
        isLaunchResponse: Bool,
        delivery: NotificationEventSnapshot.Delivery
    ) {
        logger.debug("[record] kind: \(kind.rawValue, privacy: .public), notificationId: \(notificationId, privacy: .public), actionId: \(actionId, privacy: .public), userTextLength: \(userText?.utf8.count ?? 0, privacy: .public), path: \(path.rawValue, privacy: .public), isLaunchResponse: \(isLaunchResponse, privacy: .public), delivery: \(delivery.rawValue, privacy: .public)")
        lock.lock()
        current = NotificationEventSnapshot(
            sequence: current.sequence + 1,
            kind: kind,
            notificationId: notificationId,
            actionId: actionId,
            userText: userText,
            path: path,
            isLaunchResponse: isLaunchResponse,
            delivery: delivery
        )
        lock.unlock()
        signal()
    }

    /// Changes the status under the lock.
    func updateStatus(_ change: (inout NotificationSampleStatus) -> Void) {
        logger.debug("[updateStatus] change: provided")
        lock.lock()
        change(&currentStatus)
        lock.unlock()
        signal()
    }

    func snapshot() -> NotificationEventSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func status() -> NotificationSampleStatus {
        logger.debug("[status]")
        lock.lock()
        defer { lock.unlock() }
        return currentStatus
    }

    private func signal() {
        logger.debug("[signal]")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didRecord, object: nil)
        }
    }
}

/// Main-thread view of `NotificationEventLog` for the Notification screen.
///
/// The screen owns it with `@StateObject` and calls `reload()` in `onAppear`, so events that
/// arrived before the screen existed (cold start) are shown when the screen is opened.
@MainActor
final class NotificationEventViewModel: ObservableObject {

    @Published private(set) var snapshot: NotificationEventSnapshot
    @Published private(set) var status: NotificationSampleStatus

    private let log: NotificationEventLog
    private var subscription: AnyCancellable?

    init(log: NotificationEventLog = .shared) {
        self.log = log
        self.snapshot = log.snapshot()
        self.status = log.status()
        subscription = NotificationCenter.default
            .publisher(for: NotificationEventLog.didRecord)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.reload()
                }
            }
    }

    func reload() {
        viewModelLogger.debug("[reload]")
        snapshot = log.snapshot()
        status = log.status()
    }
}
