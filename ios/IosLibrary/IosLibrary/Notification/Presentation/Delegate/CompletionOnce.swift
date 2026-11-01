//
//  CompletionOnce.swift
//  IosLibrary
//

import os
import Synchronization

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "CompletionOnce")

/// Passes a system completion handler of `UNUserNotificationCenterDelegate` through at most
/// once (part 1, 5.12.4). Later calls are dropped and logged.
///
/// The library wraps every completion handler the system gives the delegate, and hands only the
/// wrapper's ``call(_:)`` (inside a nonisolated `@Sendable` closure) to the previous delegate. A
/// previous delegate may call it from any thread (stage 1a saw a global queue), twice, or never.
///
/// When the wrapper is freed without having been called (the previous delegate dropped the
/// closure), nothing happens: the system completion is not called, as without the library
/// (1a-8).
///
/// `Sendable` without `@unchecked`: Swift 6 imports the completion handlers of the delegate's
/// methods as `@Sendable` closures (the methods have `async` forms), so the wrapped closure is
/// kept in a `Mutex`, taken out under the lock and called once outside it. The class and
/// ``call(_:)`` are nonisolated and inherit no actor, so a call from a background thread trips
/// no runtime actor check (part 1 R-4).
final class CompletionOnce<Value: Sendable>: Sendable {
    private struct State {
        /// The system completion until the first call takes it out.
        var completion: (@Sendable (Value) -> Void)?
        /// How many times ``call(_:)`` was entered.
        var calls = 0
    }

    private let state: Mutex<State>
    /// The delegate method this completion belongs to, for the log.
    private let method: String

    /// Wraps `completion`.
    ///
    /// - Parameters:
    ///   - method: The delegate method (`willPresent` / `didReceive`), for the log.
    ///   - completion: The system's completion handler.
    init(method: String, _ completion: @escaping @Sendable (Value) -> Void) {
        logger.log(level: .libraryDebug, "[init] method: \(method, privacy: .public), completion: provided")
        self.method = method
        self.state = Mutex(State(completion: completion))
    }

    /// The number of times ``call(_:)`` was entered so far.
    var callCount: Int {
        state.withLock { $0.calls }
    }

    /// Calls the wrapped completion with `value` the first time; drops every later call.
    /// Any thread; never waits for the main thread.
    func call(_ value: Value) {
        logger.log(level: .libraryDebug, "[call] method: \(self.method, privacy: .public), value: \(String(describing: type(of: value)), privacy: .public)")
        let (count, taken) = state.withLock { state -> (Int, (@Sendable (Value) -> Void)?) in
            state.calls += 1
            defer { state.completion = nil }
            return (state.calls, state.completion)
        }
        guard let taken else {
            logger.info("[call] method: \(self.method, privacy: .public), call \(count, privacy: .public) dropped: the completion was already called")
            return
        }
        // Outside the lock (S-8): this is the system's completion.
        taken(value)
    }
}
