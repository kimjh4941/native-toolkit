//
//  ShareItemConverterTests.swift
//  MacLibraryTests
//
import Testing
import Foundation
@testable import MacLibrary

struct ShareItemConverterTests {

    let converter = ShareItemConverter()

    // MARK: - .text

    @Test func textConvertsToString() throws {
        let result = try converter.convert([.text("hello")])
        #expect(result[0] as? String == "hello")
    }

    // MARK: - .url success

    @Test func httpsURLConverts() throws {
        let result = try converter.convert([.url("https://example.com")])
        #expect((result[0] as? URL)?.absoluteString == "https://example.com")
    }

    @Test func httpURLConverts() throws {
        let result = try converter.convert([.url("http://example.com")])
        #expect((result[0] as? URL)?.scheme == "http")
    }

    @Test func fileURLConverts() throws {
        let result = try converter.convert([.url("file:///tmp/a.txt")])
        #expect((result[0] as? URL)?.isFileURL == true)
    }

    // MARK: - .url failure

    @Test func emptyURLThrowsInvalidURL() {
        #expect(throws: ShareError.self) {
            _ = try converter.convert([.url("")])
        }
    }

    @Test func whitespaceOnlyURLThrowsInvalidURL() {
        #expect(throws: ShareError.self) {
            _ = try converter.convert([.url("   ")])
        }
    }

    @Test func schemelessURLThrowsInvalidURL() {
        #expect(throws: ShareError.self) {
            _ = try converter.convert([.url("example.com")])
        }
    }

    @Test func httpsURLWithoutHostThrowsInvalidURL() {
        #expect(throws: ShareError.self) {
            _ = try converter.convert([.url("https://")])
        }
    }

    @Test func ftpURLThrowsInvalidURL() {
        #expect(throws: ShareError.self) {
            _ = try converter.convert([.url("ftp://example.com")])
        }
    }

    // MARK: - .file

    @Test func existingFileConverts() throws {
        let path = NSTemporaryDirectory() + "share-converter-test-\(UUID().uuidString).txt"
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try converter.convert([.file(path: path)])
        #expect((result[0] as? URL)?.path == path)
    }

    @Test func missingFileThrowsFileNotFound() {
        #expect(throws: ShareError.self) {
            _ = try converter.convert([.file(path: "/nonexistent/path/\(UUID().uuidString).pdf")])
        }
    }

    // MARK: - .imageFile

    @Test func missingImageFileThrowsImageLoadFailed() {
        #expect(throws: ShareError.self) {
            _ = try converter.convert([.imageFile(path: "/nonexistent/path/\(UUID().uuidString).png")])
        }
    }

    // MARK: - order preservation

    @Test func conversionPreservesInputOrder() throws {
        let path = NSTemporaryDirectory() + "share-converter-order-\(UUID().uuidString).txt"
        FileManager.default.createFile(atPath: path, contents: Data("x".utf8))
        defer { try? FileManager.default.removeItem(atPath: path) }

        let result = try converter.convert([.text("a"), .url("https://example.com"), .file(path: path)])
        #expect(result.count == 3)
        #expect(result[0] as? String == "a")
        #expect(result[1] is URL)
        #expect(result[2] is URL)
    }
}
