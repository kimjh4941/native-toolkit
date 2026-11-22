// Hand-off 1 probe: registrations, the ID table and the release state machine (part 1, 5.7).
import Dispatch
import Synchronization

enum RegState: UInt8 { case active = 0, cancelRequested = 1, released = 2 }

/// One accepted request with a completion. @unchecked Sendable (P1-17 (1)/(2)): user_data and the
/// function pointers cross to main unchanged; state is atomic; `completed` is touched on main only.
class Registration: @unchecked Sendable {
    let id: UInt64
    let userData: UnsafeMutableRawPointer?
    let release: ntk_release_fn?
    let state = Atomic<UInt8>(RegState.active.rawValue)
    /// Main thread only: the completion has been called.
    var completed = false

    init(id: UInt64, userData: UnsafeMutableRawPointer?, release: ntk_release_fn?) {
        self.id = id
        self.userData = userData
        self.release = release
    }

    var currentState: RegState { RegState(rawValue: state.load(ordering: .acquiring)) ?? .released }
}

enum Registry {
    private static let ids = Atomic<UInt64>(0)
    private static let table = Mutex<[UInt64: Registration]>([:])

    /// 64-bit IDs from 1, never reused (AC-17).
    static func nextId() -> UInt64 { ids.wrappingAdd(1, ordering: .relaxed).newValue }

    static func insert(_ registration: Registration) { table.withLock { $0[registration.id] = registration } }

    /// The only place that calls release (5.7): CAS to RELEASED inside the lock, release outside it.
    static func tryRelease(_ registration: Registration, expected: RegState) {
        let won = table.withLock { table -> Bool in
            let exchanged = registration.state.compareExchange(
                expected: expected.rawValue, desired: RegState.released.rawValue, ordering: .acquiringAndReleasing).exchanged
            if exchanged { table[registration.id] = nil }
            return exchanged
        }
        if won { registration.release?(registration.userData) }
    }

    /// Cancel by ID (any thread): ACTIVE -> CANCEL_REQUESTED. nil for a finished or unknown ID.
    static func requestCancel(_ id: UInt64, where matches: (Registration) -> Bool) -> Registration? {
        table.withLock { table in
            guard let registration = table[id], matches(registration) else { return nil }
            let exchanged = registration.state.compareExchange(
                expected: RegState.active.rawValue, desired: RegState.cancelRequested.rawValue, ordering: .acquiringAndReleasing).exchanged
            return exchanged ? registration : nil
        }
    }

    /// The "complete" row of 5.7 (main only). deliver(true) means: report CANCELED instead of the result.
    static func complete(_ registration: Registration, _ deliver: (_ canceled: Bool) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !registration.completed else { return }
        switch registration.currentState {
        case .active:
            registration.completed = true
            deliver(false)
            tryRelease(registration, expected: .active)   // fails if the callback cancelled itself
        case .cancelRequested:
            registration.completed = true
            deliver(true)
            tryRelease(registration, expected: .cancelRequested)
        case .released:
            return
        }
    }

    /// The "remove" row of 5.7 (main only), queued by a cancel.
    static func remove(_ registration: Registration, _ deliverCanceled: () -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        if !registration.completed {
            registration.completed = true
            deliverCanceled()
        }
        tryRelease(registration, expected: .cancelRequested)
    }
}
