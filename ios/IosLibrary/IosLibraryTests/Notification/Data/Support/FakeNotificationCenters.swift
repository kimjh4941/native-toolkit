//
//  FakeNotificationCenters.swift
//  IosLibraryTests
//
//  Stand-ins for the requests and the categories of `UNUserNotificationCenter` (the test host app
//  has no notification permission, and the system keeps no request then).
//

import Foundation
import UserNotifications
@testable import IosLibrary

/// Keeps the requests added, in order, and what was removed.
///
/// `@unchecked Sendable` (test code only): `UNNotificationRequest` is not `Sendable`; every access
/// to the stored requests is under the lock, and the tests read them after the calls returned.
final class FakeRequestCenter: NotificationRequestCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [UNNotificationRequest] = []
    private var recordedCalls: [String] = []
    private var addError: (any Error)?

    var calls: [String] { lock.withLock { recordedCalls } }

    /// Makes every later `add` fail with `error`.
    func failAdding(with error: any Error) {
        lock.withLock { addError = error }
    }

    func request(_ identifier: String) -> UNNotificationRequest? {
        lock.withLock { requests.last { $0.identifier == identifier } }
    }

    func add(_ request: UNNotificationRequest) async throws {
        try lock.withLock {
            recordedCalls.append("add \(request.identifier)")
            if let addError { throw addError }
            requests.removeAll { $0.identifier == request.identifier }
            requests.append(request)
        }
    }

    func removePendingNotificationRequests(withIdentifiers identifiers: [String]) {
        lock.withLock {
            recordedCalls.append("remove \(identifiers.joined(separator: ","))")
            requests.removeAll { identifiers.contains($0.identifier) }
        }
    }

    func removeAllPendingNotificationRequests() {
        lock.withLock {
            recordedCalls.append("removeAll")
            requests.removeAll()
        }
    }

    func pendingNotificationRequests() async -> [UNNotificationRequest] {
        lock.withLock { requests }
    }
}

/// The categories of a center, with a log of what happened (UT-28).
///
/// The log has `read`, `write <+id|-id …>` (what the write-back changed) and whatever the tests
/// append (`note(_:)`). `categories()` suspends once before it reads, so that two changes running
/// at the same time would read the same old set. `holdNextRead()` makes the next read wait until
/// `releaseRead()`.
///
/// `@unchecked Sendable` (test code only): `UNNotificationCategory` is not `Sendable`; the stored
/// set is only touched under the lock.
final class FakeCategoryCenter: NotificationCategoryCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Set<UNNotificationCategory> = []
    private var entries: [String] = []
    private var heldRead: CheckedContinuation<Void, Never>?
    private var holdsNextRead = false
    private var readCount = 0

    var log: [String] { lock.withLock { entries } }
    /// Only the `write` entries, without the prefix.
    var writes: [String] { log.filter { $0.hasPrefix("write ") }.map { String($0.dropFirst(6)) } }
    var identifiers: Set<String> { lock.withLock { Set(stored.map(\.identifier)) } }
    var reads: Int { lock.withLock { readCount } }
    var isHoldingARead: Bool { lock.withLock { heldRead != nil } }

    func note(_ entry: String) {
        lock.withLock { entries.append(entry) }
    }

    func holdNextRead() {
        lock.withLock { holdsNextRead = true }
    }

    func releaseRead() {
        let held = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            defer { heldRead = nil }
            return heldRead
        }
        held?.resume()
    }

    /// The stored categories of `identifier`.
    func categories(withIdentifier identifier: String) -> [UNNotificationCategory] {
        lock.withLock { stored.filter { $0.identifier == identifier } }
    }

    func categories() async -> Set<UNNotificationCategory> {
        await Task.yield()
        let holds = lock.withLock { () -> Bool in
            defer { holdsNextRead = false }
            return holdsNextRead
        }
        if holds {
            await withCheckedContinuation { continuation in
                lock.withLock { heldRead = continuation }
            }
        }
        return lock.withLock {
            readCount += 1
            entries.append("read")
            return stored
        }
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        lock.withLock {
            let before = Set(stored.map(\.identifier))
            let after = Set(categories.map(\.identifier))
            let added = after.subtracting(before).sorted().map { "+\($0)" }
            let removed = before.subtracting(after).sorted().map { "-\($0)" }
            entries.append("write " + (added + removed).joined(separator: " "))
            stored = categories
        }
    }
}
