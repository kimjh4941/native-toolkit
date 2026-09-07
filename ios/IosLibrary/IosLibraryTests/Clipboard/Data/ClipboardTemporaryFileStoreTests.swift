//
//  ClipboardTemporaryFileStoreTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
@testable import IosLibrary

struct ClipboardTemporaryFileStoreTests {
    private func makeSourceFile(named name: String = "\(UUID().uuidString).png", contents: Data = Data([0x1, 0x2])) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: url)
        return url
    }

    @Test func storeCopiesFileIntoOwnDirectory() throws {
        let store = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let source = try makeSourceFile()
        let destination = try store.store(sourceURL: source, suggestedName: "photo.png")
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(destination.path.contains(store.sessionDirectory.path))
    }

    @Test func maliciousSuggestedNameDoesNotEscapeDirectory() throws {
        let store = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let source = try makeSourceFile()
        let destination = try store.store(sourceURL: source, suggestedName: "../../evil.png")
        #expect(destination.path.contains(store.sessionDirectory.path))
        #expect(!destination.path.contains(".."))
    }

    @Test func suggestedNameOnlyContributesExtension() throws {
        let store = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        // Source has no allow-listed extension, so the destination's extension must come from
        // `suggestedName` — but only its extension, never its (malicious/oversized) base name.
        let source = try makeSourceFile(named: "\(UUID().uuidString).tmp")
        let destination = try store.store(sourceURL: source, suggestedName: "a/b\0c" + String(repeating: "x", count: 2000) + ".jpg")
        #expect(destination.pathExtension == "jpg")
    }

    @Test func disallowedExtensionFallsBackToBin() throws {
        let store = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let source = try makeSourceFile(named: "\(UUID().uuidString).exe")
        let destination = try store.store(sourceURL: source, suggestedName: nil)
        #expect(destination.pathExtension == "bin")
    }

    @Test func discardRemovesRequestDirectory() throws {
        let store = ClipboardTemporaryFileStore(sessionID: UUID().uuidString)
        let source = try makeSourceFile()
        let destination = try store.store(sourceURL: source, suggestedName: "photo.png")
        let requestDirectory = destination.deletingLastPathComponent()
        store.discard(destination)
        #expect(!FileManager.default.fileExists(atPath: requestDirectory.path))
    }
}
