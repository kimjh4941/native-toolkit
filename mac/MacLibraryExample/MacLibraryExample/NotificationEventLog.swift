//
//  NotificationEventLog.swift
//  MacLibraryExample
//

import Combine
import CryptoKit
import Foundation
import MacLibrary

/// The most recent notification event the sample received, plus how many events arrived.
///
/// Shown on the Notification screen so a UI test can confirm that a click, an action or a reply
/// actually reached the app, including when the click launched it (the receivers used to only
/// log it).
struct NotificationEventSnapshot: Equatable {

    enum Kind: String {
        /// No event yet.
        case none
        /// A response without text (a click on the body uses the default action identifier).
        case action
        /// A text input reply.
        case textInput
    }

    /// Number of events received by this process. Increases by one per event.
    let sequence: Int
    let kind: Kind
    let notificationId: String?
    let actionId: String?
    /// Reply text of a text input action. `nil` for a plain action.
    let userText: String?
    /// The user info as the library handed it over (a JSON object).
    let userInfoJson: String?

    static let initial = NotificationEventSnapshot(
        sequence: 0,
        kind: .none,
        notificationId: nil,
        actionId: nil,
        userText: nil,
        userInfoJson: nil
    )

    /// The value of `notification.lastEvent`:
    /// `#<n> kind=<kind> notificationId=<id> actionId=<id> userText=<text|-> userInfo=<key:value,...|-|?>`.
    var displayValue: String {
        "#\(sequence) kind=\(kind.rawValue) notificationId=\(notificationId ?? "-") actionId=\(actionId ?? "-") "
            + "userText=\(userText ?? "-") userInfo=\(Self.userInfoText(userInfoJson))"
    }

    /// The string values of the user info as `key:value`, sorted by key and joined with commas.
    /// `-` when there is no user info or no string value in it, `?` when the JSON cannot be read.
    static func userInfoText(_ json: String?) -> String {
        guard let json else { return "-" }
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any]
        else {
            return "?"
        }
        let pairs = dictionary.keys.sorted().compactMap { key -> String? in
            guard let value = dictionary[key] as? String else { return nil }
            return "\(key):\(value)"
        }
        return pairs.isEmpty ? "-" : pairs.joined(separator: ",")
    }
}

/// App-wide store of the last notification event.
///
/// The receivers are set once, in `MacLibraryExampleApp.init` before `setup()`, and call
/// `record(...)`, which writes synchronously on the calling thread under a lock. Only the
/// "reload" signal is sent to the main thread; it carries no value, and the screen always reads
/// the current value from this store, so an event that arrived before the screen existed (a
/// launch from a notification) is shown when the screen is opened. Nothing is persisted: every
/// process starts from `NotificationEventSnapshot.initial`.
final class NotificationEventLog: @unchecked Sendable {

    static let shared = NotificationEventLog()

    /// Posted on the main thread after each event. Carries no value.
    static let didRecord = Notification.Name("NotificationEventLog.didRecord")

    private let TAG = "NotificationEventLog"
    private let lock = NSLock()
    private var current = NotificationEventSnapshot.initial

    private init() {}

    func record(
        kind: NotificationEventSnapshot.Kind,
        notificationId: String,
        actionId: String,
        userText: String?,
        userInfoJson: String
    ) {
        // The reply text is the user's input: only its length is logged here.
        Log.d(TAG, "[record] kind: \(kind.rawValue), notificationId: \(notificationId), actionId: \(actionId), userTextLength: \(userText?.utf8.count ?? 0), userInfoJson: \(userInfoJson)")
        lock.lock()
        current = NotificationEventSnapshot(
            sequence: current.sequence + 1,
            kind: kind,
            notificationId: notificationId,
            actionId: actionId,
            userText: userText,
            userInfoJson: userInfoJson
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
/// The screen owns it with `@StateObject` and calls `reload()` in `onAppear`; after that it
/// reloads on every signal of the store.
@MainActor
final class NotificationEventViewModel: ObservableObject {

    @Published private(set) var snapshot: NotificationEventSnapshot

    private let TAG = "NotificationEventViewModel"
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

/// Which copy of the sample is running, for the launches from a notification
/// (`notification.launchCopy`): the first 12 hex digits of the SHA-256 of `Bundle.main.bundlePath`.
///
/// It tells copies at different places apart; it does not prove that two copies are the same build.
enum SampleLaunchCopy {

    static let value: String = {
        let digest = SHA256.hash(data: Data(Bundle.main.bundlePath.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "copy=\(hex.prefix(12))"
    }()
}
