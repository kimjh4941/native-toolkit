//
//  FilePromiseSnapshotterTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("FilePromiseSnapshotter")
struct FilePromiseSnapshotterTests {

    /// Scratch directory removed at the end of each test.
    private func withScratch(_ body: (URL) async throws -> Void) async throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("snapshotter-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await body(root)
    }

    @Test("copies a file and returns the copy's URL")
    func copiesFile() async throws {
        try await withScratch { root in
            let source = root.appendingPathComponent("source.txt")
            try "hello".write(to: source, atomically: true, encoding: .utf8)
            let staging = root.appendingPathComponent("staging")

            let copy = try await FilePromiseSnapshotter().snapshot(from: source, into: staging)

            #expect(copy.lastPathComponent == "source.txt")
            #expect(FileManager.default.fileExists(atPath: copy.path))
            #expect(try String(contentsOf: copy, encoding: .utf8) == "hello")
        }
    }

    /// The promise must survive the original being deleted, which is the whole reason the
    /// snapshot exists.
    @Test("the copy survives deleting the source")
    func copySurvivesSourceDeletion() async throws {
        try await withScratch { root in
            let source = root.appendingPathComponent("source.txt")
            try "payload".write(to: source, atomically: true, encoding: .utf8)
            let staging = root.appendingPathComponent("staging")

            let copy = try await FilePromiseSnapshotter().snapshot(from: source, into: staging)
            try FileManager.default.removeItem(at: source)

            #expect(try String(contentsOf: copy, encoding: .utf8) == "payload")
        }
    }

    @Test("copies a directory recursively")
    func copiesDirectory() async throws {
        try await withScratch { root in
            let source = root.appendingPathComponent("folder")
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try "a".write(to: source.appendingPathComponent("a.txt"),
                          atomically: true, encoding: .utf8)
            let staging = root.appendingPathComponent("staging")

            let copy = try await FilePromiseSnapshotter().snapshot(from: source, into: staging)

            #expect(FileManager.default.fileExists(
                atPath: copy.appendingPathComponent("a.txt").path))
        }
    }

    @Test("a missing source fails and leaves no staging directory behind")
    func missingSourceLeavesNothing() async throws {
        try await withScratch { root in
            let missing = root.appendingPathComponent("does-not-exist.txt")
            let staging = root.appendingPathComponent("staging")

            await #expect(throws: ClipboardError.self) {
                _ = try await FilePromiseSnapshotter().snapshot(from: missing, into: staging)
            }
            #expect(!FileManager.default.fileExists(atPath: staging.path))
        }
    }

    @Test("a stale staging directory is replaced rather than merged")
    func replacesExistingStaging() async throws {
        try await withScratch { root in
            let source = root.appendingPathComponent("source.txt")
            try "new".write(to: source, atomically: true, encoding: .utf8)
            let staging = root.appendingPathComponent("staging")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            let leftover = staging.appendingPathComponent("leftover.txt")
            try "old".write(to: leftover, atomically: true, encoding: .utf8)

            _ = try await FilePromiseSnapshotter().snapshot(from: source, into: staging)

            #expect(!FileManager.default.fileExists(atPath: leftover.path))
        }
    }

    @Test("discard removes the staging directory")
    func discardRemoves() async throws {
        try await withScratch { root in
            let staging = root.appendingPathComponent("staging")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

            await FilePromiseSnapshotter().discard(stagingURL: staging)

            #expect(!FileManager.default.fileExists(atPath: staging.path))
        }
    }

    @Test("discard is idempotent for a directory that is already gone")
    func discardIsIdempotent() async throws {
        try await withScratch { root in
            let staging = root.appendingPathComponent("never-created")
            await FilePromiseSnapshotter().discard(stagingURL: staging)
            await FilePromiseSnapshotter().discard(stagingURL: staging)
            #expect(!FileManager.default.fileExists(atPath: staging.path))
        }
    }

    /// `FileManager.copyItem` is not cooperatively cancellable, so the contract is that a
    /// task cancelled before the copy starts throws without leaving staging behind.
    @Test("cancellation before the copy leaves no staging directory")
    func cancellationBeforeCopy() async throws {
        try await withScratch { root in
            let source = root.appendingPathComponent("source.txt")
            try "hello".write(to: source, atomically: true, encoding: .utf8)
            let staging = root.appendingPathComponent("staging")
            let snapshotter = FilePromiseSnapshotter()

            let task = Task {
                try await snapshotter.snapshot(from: source, into: staging)
            }
            task.cancel()

            await #expect(throws: CancellationError.self) { _ = try await task.value }
            #expect(!FileManager.default.fileExists(atPath: staging.path))
        }
    }
}
