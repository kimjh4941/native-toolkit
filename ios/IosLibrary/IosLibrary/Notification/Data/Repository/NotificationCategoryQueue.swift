//
//  NotificationCategoryQueue.swift
//  IosLibrary
//

import Foundation
import os
import Synchronization
import UserNotifications

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationCategoryQueue")
private let centerLogger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "CurrentNotificationCategoryCenter")

/// The categories part of `UNUserNotificationCenter` the queue reads and writes. The library's is
/// ``CurrentNotificationCategoryCenter``; tests pass a stand-in (design SR2-10).
protocol NotificationCategoryCenter: Sendable {
    func categories() async -> Set<UNNotificationCategory>
    func setCategories(_ categories: Set<UNNotificationCategory>)
}

/// `UNUserNotificationCenter.current()`, read per call (it is not `Sendable`).
struct CurrentNotificationCategoryCenter: NotificationCategoryCenter {
    func categories() async -> Set<UNNotificationCategory> {
        centerLogger.log(level: .libraryDebug, "[categories]")
        return await UNUserNotificationCenter.current().notificationCategories()
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        centerLogger.log(level: .libraryDebug, "[setCategories] identifiers: \(categories.map(\.identifier).sorted(), privacy: .public)")
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }
}

/// The one first-in first-out queue of the process for the changes to the notification
/// categories (design 8.5.6, S-P14, S-P28).
///
/// `UNUserNotificationCenter` has no call that adds or removes one category: a change reads the
/// whole set, changes it and writes it back. Two changes that run at the same time read the same
/// old set, and the later write-back undoes the earlier change. So every change of the process
/// goes into this queue, and one drain applies one change at a time.
///
/// | Step | What happens |
/// |---|---|
/// | Enqueue (``enqueue(_:completion:)``, synchronous) | In one lock region: append the change, look at the draining flag, and set it when it was down (the right to start the drain). Outside the lock, start one task only with that right |
/// | Drain | In one lock region: take the first change, or lower the flag and end when the queue is empty. Outside the lock: apply the change, call its completion, repeat |
/// | Apply one change | Read the categories, add or remove, write them back, read them again to confirm (a registration by its identifier, action identifiers and options; logged when the change is not read back). No other change starts in between |
///
/// Seeing the queue empty and lowering the flag happen in the same lock region as appending and
/// looking at the flag, so a change enqueued at the end of a drain is either taken by that drain
/// or starts a new one; a change enqueued while a drain runs never starts a second drain.
///
/// ## Threading
/// `Sendable`; ``enqueue(_:completion:)`` can be called on any thread and never waits. The lock is
/// never held while the center or a completion is called (S-8). Completions are called on the
/// drain's task, in the order of the changes.
final class NotificationCategoryQueue: Sendable {

    /// The queue of the process: every `NotificationRepositoryImpl()` uses it (design SR-18).
    static let shared = NotificationCategoryQueue(center: CurrentNotificationCategoryCenter())

    /// A change and the call to make once it is applied.
    private struct Request: Sendable {
        let change: NotificationCategoryChange
        let completion: @Sendable () -> Void
    }

    private struct State {
        var pending: [Request] = []
        var isDraining = false
        /// How many drains have started (tests check that a change enqueued during a drain starts
        /// none).
        var drainStartCount = 0
    }

    /// The points of a drain where a test can step in (UT-28).
    enum DrainPoint: Sendable {
        /// Right before the drain takes the next change (or sees the queue empty).
        case beforeTakingNext
        /// Right after the drain saw the queue empty and lowered the flag.
        case afterEnding
    }

    private let state = Mutex(State())
    private let center: any NotificationCategoryCenter
    private let drainHook: (@Sendable (DrainPoint) -> Void)?

    /// - Parameters:
    ///   - center: Where the categories are read and written (the app's center, or a stand-in in
    ///     tests).
    ///   - drainHook: For tests: called at the points of ``DrainPoint``, outside the lock.
    init(center: any NotificationCategoryCenter, drainHook: (@Sendable (DrainPoint) -> Void)? = nil) {
        logger.log(level: .libraryDebug, "[init] center: \(String(describing: type(of: center)), privacy: .public), drainHook: \(drainHook == nil ? "nil" : "provided", privacy: .public)")
        self.center = center
        self.drainHook = drainHook
    }

    /// How many drains have started so far.
    var drainStartCount: Int {
        state.withLock { $0.drainStartCount }
    }

    /// Appends `change` to the queue, synchronously, and returns at once; `completion` is called
    /// once, on the drain's task, after the change is applied.
    func enqueue(_ change: NotificationCategoryChange, completion: @escaping @Sendable () -> Void) {
        logger.log(level: .libraryDebug, "[enqueue] change: \(change.logSummary, privacy: .public), completion: provided")
        let request = Request(change: change, completion: completion)
        let startsDrain = state.withLock { state -> Bool in
            state.pending.append(request)
            guard !state.isDraining else { return false }
            state.isDraining = true
            state.drainStartCount += 1
            return true
        }
        // Outside the lock (S-8). A task, not the caller's thread: the drain awaits the center.
        guard startsDrain else { return }
        Task { await self.drain() }
    }

    /// Takes and applies one change at a time until the queue is empty.
    private func drain() async {
        logger.log(level: .libraryDebug, "[drain]")
        while true {
            drainHook?(.beforeTakingNext)
            guard let request = takeNext() else { break }
            await apply(request.change)
            request.completion()
        }
        drainHook?(.afterEnding)
    }

    /// The first change, or `nil` after lowering the flag when the queue is empty (one lock
    /// region; see the type's table).
    private func takeNext() -> Request? {
        logger.log(level: .libraryDebug, "[takeNext]")
        return state.withLock { state -> Request? in
            guard !state.pending.isEmpty else {
                state.isDraining = false
                return nil
            }
            return state.pending.removeFirst()
        }
    }

    /// Reads, changes, writes back and reads again (design 8.5.6 "1 件の処理").
    private func apply(_ change: NotificationCategoryChange) async {
        logger.log(level: .libraryDebug, "[apply] change: \(change.logSummary, privacy: .public)")
        var categories = await center.categories()
        let identifier: String
        // The category written, for a registration.
        let written: UNNotificationCategory?
        switch change {
        case .register(let category):
            identifier = category.identifier
            let unCategory = NotificationCategoryQueue.makeUNCategory(from: category)
            written = unCategory
            // Replaces a registered category with the same identifier (a set of categories
            // compares the whole category, not the identifier).
            categories = categories.filter { $0.identifier != identifier }
            categories.insert(unCategory)
        case .remove(let removed):
            identifier = removed
            written = nil
            categories = categories.filter { $0.identifier != identifier }
        }
        center.setCategories(categories)
        let readBack = await center.categories()
        if Self.isReadBack(written, identifier: identifier, in: readBack) {
            logger.log(level: .libraryDebug, "[apply] applied: \(change.logSummary, privacy: .public)")
        } else {
            // Not seen on the simulators (MS-09); the completion still follows the write-back (RK-10).
            logger.error("[apply] the change is not read back yet: \(change.logSummary, privacy: .public)")
        }
    }

    /// Whether `readBack` shows the change applied. A registration (`written`): a category with
    /// `identifier`, the action identifiers of `written` in the same order, and its options (an
    /// unapplied replacement keeps the identifier of the old category, so the identifier alone does
    /// not tell). A removal (`written` is `nil`): no category with `identifier`.
    static func isReadBack(_ written: UNNotificationCategory?, identifier: String, in readBack: Set<UNNotificationCategory>) -> Bool {
        logger.log(level: .libraryDebug, "[isReadBack] written: \(written == nil ? "nil" : "provided", privacy: .public), identifier: \(identifier, privacy: .public), readBack: \(readBack.count, privacy: .public)")
        guard let written else {
            return !readBack.contains { $0.identifier == identifier }
        }
        let actionIdentifiers = written.actions.map(\.identifier)
        return readBack.contains { read in
            read.identifier == identifier
                && read.actions.map(\.identifier) == actionIdentifiers
                && read.options == written.options
        }
    }

    /// The system category of `category`.
    static func makeUNCategory(from category: NotificationCategory) -> UNNotificationCategory {
        logger.log(level: .libraryDebug, "[makeUNCategory] identifier: \(category.identifier, privacy: .public), actions: \(category.actions.count, privacy: .public), textInputActions: \(category.textInputActions.count, privacy: .public)")
        let unActions: [UNNotificationAction] = category.actions.map { action in
            var options: UNNotificationActionOptions = []
            if action.options.contains(.authenticationRequired) { options.insert(.authenticationRequired) }
            if action.options.contains(.destructive) { options.insert(.destructive) }
            if action.options.contains(.foreground) { options.insert(.foreground) }
            if let symbolName = action.sfSymbolName {
                let icon = UNNotificationActionIcon(systemImageName: symbolName)
                return UNNotificationAction(identifier: action.identifier, title: action.title, options: options, icon: icon)
            }
            return UNNotificationAction(identifier: action.identifier, title: action.title, options: options)
        }
        let unTextInputActions: [UNTextInputNotificationAction] = category.textInputActions.map { action in
            return UNTextInputNotificationAction(
                identifier: action.identifier,
                title: action.title,
                options: [],
                icon: nil,
                textInputButtonTitle: action.buttonTitle,
                textInputPlaceholder: action.textInputPlaceholder
            )
        }
        let allActions: [UNNotificationAction] = unActions + unTextInputActions
        var unOptions: UNNotificationCategoryOptions = []
        if category.options.contains(.customDismissAction) { unOptions.insert(.customDismissAction) }
        if category.options.contains(.allowInCarPlay) { unOptions.insert(.allowInCarPlay) }
        if category.options.contains(.hiddenPreviewsShowTitle) { unOptions.insert(.hiddenPreviewsShowTitle) }
        // `allowAnnouncement` is not passed on: the system ignores it since iOS 15.
        return UNNotificationCategory(
            identifier: category.identifier,
            actions: allActions,
            intentIdentifiers: [],
            options: unOptions
        )
    }
}
