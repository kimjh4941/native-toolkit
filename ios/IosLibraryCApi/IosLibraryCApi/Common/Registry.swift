//
//  Registry.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary
import Synchronization

// The registrations and the one way they are released (part 1, 5.7; part 2, 5.3). The state of a
// registration decides everything that runs on the main thread, in the order it was queued:
//
//   event \ state   ACTIVE                       CANCEL_REQUESTED                RELEASED
//   start           start, or put in the ledger  nothing (the removal follows)   nothing
//   delivery        call                         no call                         nothing
//   completion      once, then tryRelease        CANCELED once, then tryRelease  nothing
//   removal         (does not happen)            CANCELED once, then tryRelease  nothing
//
// A result that was not handed over is deleted in every cell of the completion row. The release never
// overlaps a callback of its registration: one that comes due during a callback waits for it to return.

/// The state of a registration. It only moves forward: ACTIVE, then CANCEL_REQUESTED or straight to
/// RELEASED, and from CANCEL_REQUESTED to RELEASED.
enum RegistrationState: UInt8, Sendable {
    case active
    case cancelRequested
    case released
}

/// A kind of request that can be cancelled by id, and how its box closes (P1-24; part 2, 5.3). The features
/// define them; a kind is known by its name.
struct CancellableKind: Sendable, Equatable {
    let name: String
    let closeBox: @Sendable (RequestBox) -> Void

    static func == (left: CancellableKind, right: CancellableKind) -> Bool {
        left.name == right.name
    }
}

/// What holds on to a result until the caller has it: a `.file` load's file and folder, which
/// Clipboard knows how to delete (part 2, 5.3). Main thread only.
@MainActor
final class OwnedResult {
    private let discard: @MainActor () -> Void
    private var isDiscarded = false

    /// Set before the callback, so that a cancel from inside the callback cannot delete what it was given.
    private(set) var isHandedOver = false

    init(discard: @escaping @MainActor () -> Void) {
        CApiLog.common.debug("[OwnedResult.init] discard: provided")
        self.discard = discard
    }

    func markHandedOver() {
        CApiLog.common.debug("[markHandedOver]")
        isHandedOver = true
    }

    func discardUnlessHandedOver() {
        CApiLog.common.debug("[discardUnlessHandedOver] handed over: \(self.isHandedOver, privacy: .public), discarded: \(self.isDiscarded, privacy: .public)")
        guard !isHandedOver, !isDiscarded else { return }
        isDiscarded = true
        discard()
    }
}

/// What `Registry` reaches without the type of the callback: `ntk_notification_listener_remove` takes
/// the listeners of two callback types, and the table holds the requests of all features.
protocol RegistryEntry: AnyObject, Sendable {
    var cancellable: CancellableKind? { get }
    var requestBox: RequestBox? { get }

    /// ACTIVE to CANCEL_REQUESTED, and whether this call did it.
    func requestCancel() -> Bool
    func closeRequestBox()
    func enqueueRemoval()
}

/// One accepted operation or event registration, from any thread until `Registry.tryRelease`.
///
/// `@unchecked Sendable` is P1-17's (1) and (2): `callback` and `userData` are C values that are only
/// called and passed on, on the main thread, and the safety of `user_data` is the caller's by the C ABI's
/// contract. `state` is atomic, the other stored properties do not change, and `isCompleted` is main-only.
final class Registration<Callback>: RegistryEntry, @unchecked Sendable {
    /// Calls the callback with the feature's canceled value (the feature knows the value and the form).
    typealias CanceledCompletion = @MainActor @Sendable (Callback, UnsafeMutableRawPointer?, UInt64) -> Void

    let id: UInt64
    let callback: Callback
    let userData: UnsafeMutableRawPointer?
    let release: ntk_release_fn?
    let cancellable: CancellableKind?
    let requestBox: RequestBox?

    private let canceled: CanceledCompletion?
    private let onRemoval: (@MainActor @Sendable (Registration<Callback>) -> Void)?
    private let state = Atomic<UInt8>(RegistrationState.active.rawValue)

    /// The mark of part 1, 5.7: the callback has been called, with a result or with CANCELED.
    @MainActor private var isCompleted = false
    /// How many calls of the callback are on the stack: a callback can reach this registration again.
    @MainActor private var callbackDepth = 0
    /// A release came due during a callback.
    @MainActor private var isReleaseDeferred = false

    init(callback: Callback, userData: UnsafeMutableRawPointer?, release: ntk_release_fn?,
         cancellable: CancellableKind?, canceled: CanceledCompletion?,
         onRemoval: (@MainActor @Sendable (Registration<Callback>) -> Void)?) {
        CApiLog.common.debug("[Registration.init] callback: provided, userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), cancellable: \(cancellable?.name ?? "nil", privacy: .public), canceled: \(canceled == nil ? "nil" : "provided", privacy: .public), onRemoval: \(onRemoval == nil ? "nil" : "provided", privacy: .public)")
        id = Registry.nextID()
        self.callback = callback
        self.userData = userData
        self.release = release
        self.cancellable = cancellable
        requestBox = cancellable == nil ? nil : RequestBox()
        self.canceled = canceled
        self.onRemoval = onRemoval
    }

    var currentState: RegistrationState {
        RegistrationState(rawValue: state.load(ordering: .acquiring)) ?? .released
    }

    var isActive: Bool {
        currentState == .active
    }

    func transition(from expected: RegistrationState, to desired: RegistrationState) -> Bool {
        CApiLog.common.debug("[transition] id: \(self.id, privacy: .public), from: \(String(describing: expected), privacy: .public), to: \(String(describing: desired), privacy: .public)")
        return state.compareExchange(expected: expected.rawValue, desired: desired.rawValue, ordering: .acquiringAndReleasing).exchanged
    }

    func requestCancel() -> Bool {
        CApiLog.common.debug("[requestCancel] id: \(self.id, privacy: .public)")
        return transition(from: .active, to: .cancelRequested)
    }

    func closeRequestBox() {
        CApiLog.common.debug("[closeRequestBox] id: \(self.id, privacy: .public)")
        if let cancellable, let requestBox {
            cancellable.closeBox(requestBox)
        }
    }

    /// The block holds this registration, so the caller may let go of its own reference.
    func enqueueRemoval() {
        CApiLog.common.debug("[enqueueRemoval] id: \(self.id, privacy: .public)")
        MainQueue.async { self.runRemoval() }
    }

    /// The start row: the operation starts only while nothing asked to cancel it.
    @MainActor
    func startIfActive(_ start: @MainActor (Registration<Callback>) -> Void) {
        CApiLog.common.debug("[startIfActive] id: \(self.id, privacy: .public), state: \(String(describing: self.currentState), privacy: .public), start: provided")
        guard isActive else { return }
        start(self)
    }

    /// The call of the callback, for completions and events: the release never overlaps it. A release that
    /// comes due inside (`Registry.tryRelease`) happens when the outermost call returns, from the state
    /// then, since a cancel may have come meanwhile. If that state moves before the release, the removal
    /// the cancel queued does it, as it does anywhere else.
    @MainActor
    func runCallback(_ call: @MainActor () -> Void) {
        CApiLog.common.debug("[runCallback] id: \(self.id, privacy: .public), depth: \(self.callbackDepth, privacy: .public), call: provided")
        callbackDepth += 1
        call()
        callbackDepth -= 1
        guard callbackDepth == 0, isReleaseDeferred else { return }
        isReleaseDeferred = false
        Registry.tryRelease(self, expected: currentState)
    }

    /// Whether a callback is on the stack, which also leaves a note to release when it returns.
    @MainActor
    func deferReleaseIfInCallback() -> Bool {
        CApiLog.common.debug("[deferReleaseIfInCallback] id: \(self.id, privacy: .public), depth: \(self.callbackDepth, privacy: .public)")
        guard callbackDepth > 0 else { return false }
        isReleaseDeferred = true
        return true
    }

    /// The completion row. When a cancel comes during `deliver`, `tryRelease(ACTIVE)` fails and the removal
    /// that cancel queued does the release. The mark comes before the call. `result`, when it holds something, is deleted unless `deliver`
    /// is what gets it to the caller: when the request was cancelled, and when the result comes after
    /// RELEASED, where neither the callback nor `user_data` is touched (part 2, 5.3).
    @MainActor
    func complete(result: OwnedResult? = nil, deliver: @MainActor (Callback, UnsafeMutableRawPointer?, UInt64) -> Void) {
        CApiLog.common.debug("[complete] id: \(self.id, privacy: .public), state: \(String(describing: self.currentState), privacy: .public), completed: \(self.isCompleted, privacy: .public), result: \(result == nil ? "nil" : "owned", privacy: .public), deliver: provided")
        switch currentState {
        case .active:
            if !isCompleted {
                isCompleted = true
                result?.markHandedOver()
                runCallback { deliver(callback, userData, id) }
            }
            _ = Registry.tryRelease(self, expected: .active)
        case .cancelRequested:
            completeAsCanceled()
            _ = Registry.tryRelease(self, expected: .cancelRequested)
        case .released:
            break
        }
        result?.discardUnlessHandedOver()
    }

    /// The removal row: out of the ledger, CANCELED unless the callback was already called, and the
    /// release, whatever the kind and the mark were (R-3).
    @MainActor
    func runRemoval() {
        CApiLog.common.debug("[runRemoval] id: \(self.id, privacy: .public), state: \(String(describing: self.currentState), privacy: .public), completed: \(self.isCompleted, privacy: .public)")
        guard currentState == .cancelRequested else { return }
        onRemoval?(self)
        completeAsCanceled()
        _ = Registry.tryRelease(self, expected: .cancelRequested)
    }

    @MainActor
    private func completeAsCanceled() {
        guard !isCompleted, let canceled else { return }
        isCompleted = true
        runCallback { canceled(callback, userData, id) }
    }
}

/// The table of requests that can be cancelled, and everything that moves a registration.
enum Registry {
    /// ID to registration, for the requests that can be cancelled. Never freed (part 1, 5.14).
    private static let table = Mutex<[UInt64: any RegistryEntry]>([:])
    private static let lastID = Atomic<UInt64>(0)

    /// Counts from 1 and never reuses a value (AC-17); 0 means "none".
    static func nextID() -> UInt64 {
        CApiLog.common.debug("[nextID]")
        return lastID.add(1, ordering: .relaxed).newValue
    }

    /// Steps 4 to 7 of acceptance (part 1, 5.7), for an operation that completes: the entry has checked
    /// and copied its input. `start` runs on the main thread, unless the request was cancelled before.
    static func accept<Callback>(callback: Callback, userData: UnsafeMutableRawPointer?, release: ntk_release_fn?,
                                 cancellable: CancellableKind? = nil,
                                 canceled: @escaping Registration<Callback>.CanceledCompletion,
                                 outRequestID: UnsafeMutablePointer<UInt64>? = nil,
                                 start: @escaping @MainActor @Sendable (Registration<Callback>) -> Void) -> Int32 {
        CApiLog.common.debug("[accept] callback: provided, userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), cancellable: \(cancellable?.name ?? "nil", privacy: .public), canceled: provided, outRequestID: \(outRequestID == nil ? "nil" : "provided", privacy: .public), start: provided")
        VersionCheck.run()
        let registration = Registration(callback: callback, userData: userData, release: release, cancellable: cancellable,
                                        canceled: canceled, onRemoval: nil)
        if cancellable != nil {
            table.withLock { $0[registration.id] = registration }
        }
        // Before the block is queued, but a caller must not count on it: on the main thread the completion
        // can be there first (P1-5).
        outRequestID?.pointee = registration.id
        MainQueue.async { registration.startIfActive(start) }
        return Entry.accepted
    }

    /// The one function that calls `release` after acceptance (part 1, 5.7, C-3): under the table's lock,
    /// the state moves from `expected` to RELEASED and the request leaves the table; only the call that did
    /// that calls `release`, outside the lock, since it is the caller's code and may call back in. During a
    /// callback of the registration it does neither: `runCallback` calls it again when the callback returns.
    @MainActor
    @discardableResult
    static func tryRelease<Callback>(_ registration: Registration<Callback>, expected: RegistrationState) -> Bool {
        CApiLog.common.debug("[tryRelease] id: \(registration.id, privacy: .public), expected: \(String(describing: expected), privacy: .public)")
        guard expected != .released, !registration.deferReleaseIfInCallback() else { return false }
        let released = table.withLock { table -> Bool in
            guard registration.transition(from: expected, to: .released) else { return false }
            table[registration.id] = nil
            return true
        }
        guard released else { return false }
        registration.release?(registration.userData)
        return true
    }

    /// Cancels a request from any thread without waiting (part 1, 5.7; part 2, 5.3). An id that is unknown,
    /// completed, already cancelled, or of the other kind of request does nothing.
    static func cancel(id: UInt64, request: CancellableKind) {
        CApiLog.common.debug("[cancel] id: \(id, privacy: .public), request: \(request.name, privacy: .public)")
        let entry = table.withLock { table -> (any RegistryEntry)? in
            guard let entry = table[id], entry.cancellable == request, entry.requestCancel() else { return nil }
            return entry
        }
        guard let entry else { return }
        entry.closeRequestBox()
        entry.enqueueRemoval()
    }

    /// Removes an event registration by its handle, from any thread without waiting (part 1, 5.7). NULL
    /// does nothing. A second removal is undefined (AC-17); while the object is still alive it does nothing.
    static func removeListener(_ handle: OpaquePointer?) {
        CApiLog.common.debug("[removeListener] handle: \(handle == nil ? "nil" : "provided", privacy: .public)")
        guard let handle else { return }
        let reference = Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(handle))
        guard let entry = reference.takeUnretainedValue() as? any RegistryEntry, entry.requestCancel() else { return }
        entry.enqueueRemoval()
        reference.release()
    }

    /// The box of a request in the table, for the tests.
    static func requestBox(id: UInt64) -> RequestBox? {
        CApiLog.common.debug("[requestBox] id: \(id, privacy: .public)")
        return table.withLock { $0[id]?.requestBox }
    }

    /// The number of requests in the table, for the tests.
    static var requestCount: Int {
        table.withLock { $0.count }
    }
}

/// The ledger of one kind of event (part 1, 5.7, 5.12.7; part 2, 5.4), whatever the event and the C
/// callback are. Everything but `add` is on the main thread.
///
/// Events that come while no registration of this kind is ACTIVE wait here, up to `holdLimit`, dropping
/// the oldest, for the next registration alone (AP-21, P2-18). They are taken one at a time and the next
/// one only while that registration is ACTIVE, so a callback that removes the only registration leaves
/// the rest for the registration after it. An event that arrives while any wait goes behind them.
///
/// An event that arrives inside a delivery, with none waiting, waits for that delivery to end and then goes
/// to the registrations ACTIVE at that point, so every registration sees the events in the same order.
/// When none is, it is held like any other: the limit is about those.
@MainActor
final class EventLedger<Event, Callback> {
    typealias Deliver = @MainActor @Sendable (Callback, UnsafeMutableRawPointer?, Event) -> Void

    private let holdLimit: Int
    private let deliver: Deliver
    private let onFirstInsertion: (@MainActor @Sendable () -> Void)?
    private var didFirstInsertion = false
    private var entries: [Registration<Callback>] = []
    private var held: [Event] = []
    private var isDelivering = false
    private var arrivedDuringDelivery: [Event] = []
    /// Moves when what was not delivered is dropped, so that a delivery in progress stops at its next call.
    private var discardCount = 0

    /// - Parameters:
    ///   - holdLimit: How many events wait for the next registration; 0 keeps none (Clipboard).
    ///   - deliver: Calls the callback with what the event becomes for this registration (each gets its
    ///     own handle, part 2, 5.4).
    ///   - onFirstInsertion: Runs once ever, inside the first registration's insertion and after it is in
    ///     the ledger, since the library's listener delivers while it is being added (AP-21).
    nonisolated init(holdLimit: Int, deliver: @escaping Deliver, onFirstInsertion: (@MainActor @Sendable () -> Void)? = nil) {
        CApiLog.common.debug("[EventLedger.init] holdLimit: \(holdLimit, privacy: .public), deliver: provided, onFirstInsertion: \(onFirstInsertion == nil ? "nil" : "provided", privacy: .public)")
        self.holdLimit = holdLimit
        self.deliver = deliver
        self.onFirstInsertion = onFirstInsertion
    }

    /// Steps 4 to 7 of acceptance for an event registration, from any thread: `outListener` gets the
    /// handle, which is the caller's reference to the registration until `Registry.removeListener`.
    nonisolated func add(callback: Callback, userData: UnsafeMutableRawPointer?, release: ntk_release_fn?,
                         outListener: UnsafeMutablePointer<OpaquePointer?>) -> Int32 {
        CApiLog.common.debug("[add] callback: provided, userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public), outListener: provided")
        VersionCheck.run()
        let registration = Registration<Callback>(callback: callback, userData: userData, release: release, cancellable: nil,
                                                  canceled: nil, onRemoval: { [self] in take($0) })
        outListener.pointee = OpaquePointer(Unmanaged.passRetained(registration).toOpaque())
        MainQueue.async { [self] in insert(registration) }
        return Entry.accepted
    }

    /// An event from the library, on the main thread.
    func receive(_ event: Event) {
        CApiLog.common.debug("[receive] event: provided, entries: \(self.entries.count, privacy: .public), held: \(self.held.count, privacy: .public), delivering: \(self.isDelivering, privacy: .public)")
        guard held.isEmpty else {
            hold(event)
            return
        }
        guard !isDelivering else {
            arrivedDuringDelivery.append(event)
            return
        }
        delivering { deliverToActive(event) }
    }

    /// Drops the events that came and have not reached everyone: those waiting for the delivery in progress,
    /// and what is left of that delivery. For a source that stopped, when "nothing more comes" has to hold
    /// from now on. What is held for the next registration stays.
    func discardUndelivered() {
        CApiLog.common.debug("[discardUndelivered] waiting: \(self.arrivedDuringDelivery.count, privacy: .public), delivering: \(self.isDelivering, privacy: .public)")
        arrivedDuringDelivery.removeAll()
        discardCount += 1
    }

    /// The number of registrations in the ledger, for the tests.
    var entryCount: Int { entries.count }

    /// The number of events waiting, for the tests.
    var heldCount: Int { held.count }

    /// The start row for an event registration.
    private func insert(_ registration: Registration<Callback>) {
        CApiLog.common.debug("[insert] id: \(registration.id, privacy: .public), state: \(String(describing: registration.currentState), privacy: .public)")
        guard registration.isActive else { return }
        entries.append(registration)
        if !didFirstInsertion {
            didFirstInsertion = true
            onFirstInsertion?()
        }
        delivering {
            while registration.isActive, !held.isEmpty {
                call(registration, with: held.removeFirst())
            }
        }
    }

    /// `body` calls callbacks. When the outermost one ends, so do the events that arrived meanwhile.
    private func delivering(_ body: () -> Void) {
        guard !isDelivering else {
            body()
            return
        }
        isDelivering = true
        body()
        while !arrivedDuringDelivery.isEmpty {
            deliverToActive(arrivedDuringDelivery.removeFirst())
        }
        isDelivering = false
    }

    /// With events held there is no one ACTIVE here: an event is held only when no one is, and only a new
    /// registration, through its insertion, changes that.
    private func deliverToActive(_ event: Event) {
        var delivered = false
        let discards = discardCount
        // `entries` is copied by the loop: a callback may change it. Each state is read right before its call.
        for registration in entries where registration.isActive {
            guard discards == discardCount else { return }
            delivered = true
            call(registration, with: event)
        }
        if !delivered {
            hold(event)
        }
    }

    private func call(_ registration: Registration<Callback>, with event: Event) {
        registration.runCallback { deliver(registration.callback, registration.userData, event) }
    }

    private func take(_ registration: Registration<Callback>) {
        CApiLog.common.debug("[take] id: \(registration.id, privacy: .public)")
        entries.removeAll { $0 === registration }
    }

    private func hold(_ event: Event) {
        CApiLog.common.debug("[hold] held: \(self.held.count, privacy: .public), limit: \(self.holdLimit, privacy: .public)")
        guard holdLimit > 0 else { return }
        if held.count >= holdLimit {
            held.removeFirst()
        }
        held.append(event)
    }
}
