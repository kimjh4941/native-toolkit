import Combine
import Foundation
import IosLibrary

/// The most recent notification event the sample received, plus how many events arrived.
///
/// Shown on the Notification screen so a UI test can confirm that a tap, an action or a reply
/// actually reached the app (the receivers used to only log it).
struct NotificationEventSnapshot: Equatable {

    enum Kind: String {
        /// `IosNotificationManager.onActionReceived` (taps use the default action identifier).
        case action
        /// `IosNotificationManager.onTextInputActionReceived`.
        case textInput
    }

    /// Number of events received by this process. Increases by one per event.
    let sequence: Int
    /// `nil` until the first event.
    let kind: Kind?
    let notificationId: String?
    let actionId: String?
    /// Reply text of a text input action. `nil` for a plain action.
    let userText: String?

    static let initial = NotificationEventSnapshot(
        sequence: 0,
        kind: nil,
        notificationId: nil,
        actionId: nil,
        userText: nil
    )
}

/// App-wide store of the last notification event.
///
/// `record(...)` writes synchronously on the calling thread under a lock, so the event is stored
/// before `IosNotificationManager` calls the system `completionHandler` — even when the process is
/// suspended right after a background action. Only the "reload" signal is sent to the main thread;
/// it carries no value, and the screen always reads the current value from this store. Nothing is
/// persisted: every process starts from `NotificationEventSnapshot.initial`.
final class NotificationEventLog: @unchecked Sendable {

    static let shared = NotificationEventLog()

    /// Posted on the main thread after each `record(...)`. Carries no value.
    static let didRecord = Notification.Name("NotificationEventLog.didRecord")

    private let TAG = "NotificationEventLog"

    private let lock = NSLock()
    private var current = NotificationEventSnapshot.initial

    private init() {}

    func record(
        kind: NotificationEventSnapshot.Kind,
        notificationId: String,
        actionId: String,
        userText: String?
    ) {
        Log.d(
            TAG,
            "[record] kind: \(kind.rawValue), notificationId: \(notificationId), actionId: \(actionId), userText: \(userText ?? "nil")"
        )
        lock.lock()
        current = NotificationEventSnapshot(
            sequence: current.sequence + 1,
            kind: kind,
            notificationId: notificationId,
            actionId: actionId,
            userText: userText
        )
        lock.unlock()

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.didRecord, object: nil)
        }
    }

    func snapshot() -> NotificationEventSnapshot {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}

/// Main-thread view of `NotificationEventLog` for the Notification screen.
///
/// The screen owns it with `@StateObject` and calls `reload()` in `onAppear`, so events that
/// arrived before the screen existed (cold start) are shown when the screen is opened.
@MainActor
final class NotificationEventViewModel: ObservableObject {

    private let TAG = "NotificationEventViewModel"

    @Published private(set) var snapshot: NotificationEventSnapshot

    private let log: NotificationEventLog
    private var subscription: AnyCancellable?

    init(log: NotificationEventLog = .shared) {
        self.log = log
        self.snapshot = log.snapshot()
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
        Log.d(TAG, "[reload]")
        snapshot = log.snapshot()
    }
}
