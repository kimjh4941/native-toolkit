//
//  PresentationRecords.swift
//  IosLibrary
//

import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "PresentationRecords")

/// The share sheets the library has started to present and whose `present` has not completed yet,
/// and the requests waiting for them (SH-13; the design memo `2026-11-21-ios-c-abi-share-same-turn-design.md`,
/// 4.2 and chapter 10).
///
/// UIKit presents a share sheet only when its remote scene is ready. Until then nothing on the
/// presenting view controller shows the presentation (`presentedViewController` and
/// `transitionCoordinator` are still `nil`), and a second sheet presented then is declined and kept,
/// so its release watch never ends it. ``PresentationProcedure`` therefore counts its own sheets
/// here and does not present on the same window until they are cleared.
///
/// A record is cleared once, by the first of `present`'s completion or the sheet being freed
/// (``end(_:_:)`` with ``End/cleared``). When its lifetime passes first (``End/expired``), the
/// requests waiting for it are failed, and the record stays, as stuck, until it is cleared: UIKit
/// may still be presenting that sheet, and would decline (and keep) anything presented on the
/// window meanwhile. A request finding a stuck record fails at once instead of waiting.
///
/// Each record belongs to the window of the view controller it was presented on, held weakly; a
/// request only looks at the records of its own window, and a record whose window or sheet is
/// gone is cleared.
///
/// The requests share one instance: ``UIKitPresentationEnvironment`` returns ``shared``, and a
/// test environment returns the instance the test made.
@MainActor
final class PresentationRecords {
    /// The instance the UIKit environment uses.
    static let shared = PresentationRecords()

    /// Why a record ended or a waiter was woken.
    enum End {
        /// The sheet's `present` completed, or the sheet was freed: the presentation is over.
        case cleared
        /// The record outlived its lifetime without either: it stays as stuck.
        case expired
    }

    /// What the records of one window say about presenting on it now.
    enum State {
        /// No sheet of the library is being presented there.
        case clear
        /// A sheet is being presented there and may still clear: wait for it.
        case pending
        /// A sheet outlived its lifetime there without clearing: do not present.
        case stuck
    }

    typealias ID = UInt64

    /// A window, held weakly, with the identity it had when it was recorded (for waking: a waiter
    /// and the record it waits for are made while the window is alive).
    private struct Scope {
        let identity: ObjectIdentifier?
        weak var window: AnyObject?

        init(_ window: AnyObject?) {
            identity = window.map(ObjectIdentifier.init)
            self.window = window
        }

        /// Whether the window is gone (a record in no window is never gone this way).
        var isGone: Bool { identity != nil && window == nil }

        /// Whether `window` is this one, still alive.
        func holds(_ window: AnyObject?) -> Bool {
            guard let window else { return identity == nil }
            return self.window === window
        }
    }

    private struct Record {
        weak var presented: AnyObject?
        let scope: Scope
        var isStuck = false
    }

    private struct Waiter {
        let scope: Scope
        let wake: @MainActor (End) -> Void
    }

    private var records: [ID: Record] = [:]
    private var waiters: [ID: Waiter] = [:]
    private var lastID: ID = 0

    init() {
        logger.log(level: .libraryDebug, "[init]")
    }

    /// A new ID, for a record or a waiter.
    func makeID() -> ID {
        logger.log(level: .libraryDebug, "[makeID] lastID: \(self.lastID, privacy: .public)")
        lastID += 1
        return lastID
    }

    /// Records `presented`, presented on a view controller in `window`.
    func begin(_ id: ID, presented: AnyObject, window: AnyObject?) {
        logger.log(level: .libraryDebug, "[begin] id: \(id, privacy: .public), presented: \(String(describing: type(of: presented)), privacy: .public), hasWindow: \(window != nil, privacy: .public)")
        records[id] = Record(presented: presented, scope: Scope(window))
    }

    /// Ends the record `id`: removes it when cleared, marks it stuck when expired, and wakes the
    /// requests waiting in its window with `reason`. A cleared record ignores what comes later.
    func end(_ id: ID, _ reason: End) {
        logger.log(level: .libraryDebug, "[end] id: \(id, privacy: .public), reason: \(String(describing: reason), privacy: .public)")
        guard let record = records[id] else {
            logger.log(level: .libraryDebug, "[end] the record was already cleared")
            return
        }
        switch reason {
        case .cleared:
            records.removeValue(forKey: id)
        case .expired:
            guard !record.isStuck else { return }
            records[id]?.isStuck = true
            logger.error("[end] a share sheet did not clear within its lifetime: stuck until it does")
        }
        wakeWaiters(in: record.scope, reason)
    }

    /// The state of `window`. Records whose sheet or window is gone are cleared here first,
    /// without waiting for the release watch's notice.
    func state(in window: AnyObject?) -> State {
        logger.log(level: .libraryDebug, "[state] hasWindow: \(window != nil, privacy: .public)")
        let gone = records.filter { $0.value.presented == nil || $0.value.scope.isGone }.map(\.key)
        for id in gone.sorted() {
            end(id, .cleared)
        }
        let mine = records.values.filter { $0.scope.holds(window) }
        let state: State = mine.contains(where: \.isStuck) ? .stuck : (mine.isEmpty ? .clear : .pending)
        logger.log(level: .libraryDebug, "[state] state: \(String(describing: state), privacy: .public), gone: \(gone.count, privacy: .public)")
        return state
    }

    /// Calls `wake` once, when a record of `window` is cleared or expires (at the latest when it
    /// expires: a waiter always starts after the record it waits for). The waiter is dropped once
    /// it is woken.
    func wait(_ id: ID, in window: AnyObject?, wake: @escaping @MainActor (End) -> Void) {
        logger.log(level: .libraryDebug, "[wait] id: \(id, privacy: .public), hasWindow: \(window != nil, privacy: .public), wake: provided")
        waiters[id] = Waiter(scope: Scope(window), wake: wake)
    }

    /// The number of records, stuck ones included, and of waiters (tests only).
    var counts: (records: Int, waiters: Int) { (records.count, waiters.count) }

    private func wakeWaiters(in scope: Scope, _ reason: End) {
        logger.log(level: .libraryDebug, "[wakeWaiters] hasWindow: \(scope.identity != nil, privacy: .public), reason: \(String(describing: reason), privacy: .public)")
        let woken = waiters.filter { $0.value.scope.identity == scope.identity }.map(\.key).sorted()
        for id in woken {
            guard let waiter = waiters.removeValue(forKey: id) else { continue }
            waiter.wake(reason)
        }
    }
}
