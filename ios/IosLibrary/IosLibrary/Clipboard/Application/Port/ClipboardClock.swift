//
//  ClipboardClock.swift
//  IosLibrary
//

import Foundation

/// Provides the current time. Injected so that `expirationDate` boundary checks are deterministic
/// in tests instead of racing against `Date()`.
public protocol ClipboardClock: Sendable {
    func now() -> Date
}

/// Default clock backed by the system time.
public struct SystemClock: ClipboardClock {
    public init() {}
    public func now() -> Date { Date() }
}
