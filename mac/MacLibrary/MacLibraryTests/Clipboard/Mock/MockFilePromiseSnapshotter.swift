//
//  MockFilePromiseSnapshotter.swift
//  MacLibraryTests
//

import Foundation
@testable import MacLibrary

/// Records snapshot and discard calls without touching the file system.
///
/// The type is `@unchecked Sendable` because the port is `Sendable` and the mock is reached
/// from the caller's isolation. A lock guards every field, so the unchecked claim holds.
final class MockFilePromiseSnapshotter: FilePromiseSnapshotting, @unchecked Sendable {

    private let lock = NSLock()

    private var _shouldFail: ClipboardError?
    private var _snapshotCallCount = 0
    private var _discardCallCount = 0
    private var _lastSource: URL?
    private var _lastStagingRoot: URL?
    private var _discardedURLs: [URL] = []
    /// Runs inside `snapshot` before it returns. Lets a test cancel the calling task at the
    /// exact point where the copy has finished but nothing is registered yet.
    private var _onSnapshot: (@Sendable () -> Void)?

    var shouldFail: ClipboardError? {
        get { lock.withLock { _shouldFail } }
        set { lock.withLock { _shouldFail = newValue } }
    }
    var onSnapshot: (@Sendable () -> Void)? {
        get { lock.withLock { _onSnapshot } }
        set { lock.withLock { _onSnapshot = newValue } }
    }
    var snapshotCallCount: Int { lock.withLock { _snapshotCallCount } }
    var discardCallCount: Int { lock.withLock { _discardCallCount } }
    var lastSource: URL? { lock.withLock { _lastSource } }
    var lastStagingRoot: URL? { lock.withLock { _lastStagingRoot } }
    var discardedURLs: [URL] { lock.withLock { _discardedURLs } }

    func snapshot(from source: URL, into stagingRoot: URL) async throws -> URL {
        let (failure, hook) = lock.withLock { () -> (ClipboardError?, (@Sendable () -> Void)?) in
            _snapshotCallCount += 1
            _lastSource = source
            _lastStagingRoot = stagingRoot
            return (_shouldFail, _onSnapshot)
        }
        hook?()
        if let failure { throw failure }
        return stagingRoot.appending(path: source.lastPathComponent)
    }

    func discard(stagingURL: URL) async {
        lock.withLock {
            _discardCallCount += 1
            _discardedURLs.append(stagingURL)
        }
    }
}
