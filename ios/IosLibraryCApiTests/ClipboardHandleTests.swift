//
//  ClipboardHandleTests.swift
//  IosLibraryCApiTests
//

import IosLibrary
import XCTest
@testable import IosLibraryCApi

/// The readers of the result handles through their C functions (part 2, 8.2 and 12.1 "出力のハンドル").
/// The handles come from `ClipboardHandles.make*`, as the receiver makes them.
final class ClipboardHandleTests: XCTestCase {
    private let tooFar = Int(bitPattern: UInt.max)

    private func string(_ pointer: UnsafePointer<CChar>?) -> String? {
        pointer.map { String(cString: $0) }
    }

    private func readResult() -> OpaquePointer {
        ClipboardHandles.makeReadResult(ClipboardReadResult(items: [
            ClipboardItemData(typeIdentifiers: ["public.a", "public.b"], text: "text", urlString: "https://a.example", imageDataUTType: "public.png"),
            ClipboardItemData(typeIdentifiers: [], text: nil, urlString: nil, imageDataUTType: nil),
            ClipboardItemData(typeIdentifiers: ["public.c"], text: "", urlString: "", imageDataUTType: ""),
        ], numberOfItems: 3))
    }

    private func snapshot(matching: [Int]? = [2, 0]) -> OpaquePointer {
        ClipboardHandles.makeSnapshot(ClipboardSnapshot(hasStrings: true, hasURLs: false, hasImages: true, hasColors: false, numberOfItems: 2,
                                                        typeIdentifiers: ["public.a", "public.b"],
                                                        allTypeIdentifiers: [["public.a"], ["public.a", "public.b"]],
                                                        matchingItemIndexes: matching))
    }

    // MARK: - ntk_clipboard_read_result

    func testTheItemsOfAReadResult() {
        let handle = readResult()
        defer { ntk_clipboard_read_result_free(handle) }

        XCTAssertEqual(ntk_clipboard_read_result_item_count(handle), 3)
        XCTAssertEqual(ntk_clipboard_read_result_item_type_count(handle, 0), 2)
        XCTAssertEqual(ntk_clipboard_read_result_item_type_count(handle, 1), 0)

        var size = -1
        XCTAssertEqual(string(ntk_clipboard_read_result_item_type_at(handle, 0, 0, &size)), "public.a")
        XCTAssertEqual(size, 8)
        XCTAssertEqual(string(ntk_clipboard_read_result_item_type_at(handle, 0, 1, nil)), "public.b")
        XCTAssertEqual(string(ntk_clipboard_read_result_item_text_at(handle, 0, &size)), "text")
        XCTAssertEqual(size, 4)
        XCTAssertEqual(string(ntk_clipboard_read_result_item_url_at(handle, 0, &size)), "https://a.example")
        XCTAssertEqual(size, 17)
        XCTAssertEqual(string(ntk_clipboard_read_result_item_image_type_at(handle, 0, &size)), "public.png")
        XCTAssertEqual(size, 10)
    }

    /// A denied paste looks like this item: nothing, with NONE (part 2, 6.1).
    func testAnItemWithNothing() {
        let handle = readResult()
        defer { ntk_clipboard_read_result_free(handle) }
        var size = -1
        XCTAssertNil(ntk_clipboard_read_result_item_text_at(handle, 1, &size))
        XCTAssertEqual(size, 0)
        size = -1
        XCTAssertNil(ntk_clipboard_read_result_item_url_at(handle, 1, &size))
        XCTAssertEqual(size, 0)
        size = -1
        XCTAssertNil(ntk_clipboard_read_result_item_image_type_at(handle, 1, &size))
        XCTAssertEqual(size, 0)
    }

    /// An empty value is there: not NULL.
    func testEmptyValuesAreNotNull() {
        let handle = readResult()
        defer { ntk_clipboard_read_result_free(handle) }
        var size = -1
        XCTAssertEqual(string(ntk_clipboard_read_result_item_text_at(handle, 2, &size)), "")
        XCTAssertEqual(size, 0)
        XCTAssertEqual(string(ntk_clipboard_read_result_item_url_at(handle, 2, nil)), "")
        XCTAssertEqual(string(ntk_clipboard_read_result_item_image_type_at(handle, 2, nil)), "")
    }

    func testAReadResultOutOfRange() {
        let handle = readResult()
        defer { ntk_clipboard_read_result_free(handle) }
        for item in [3, tooFar] {
            var size = -1
            XCTAssertEqual(ntk_clipboard_read_result_item_type_count(handle, item), 0)
            XCTAssertNil(ntk_clipboard_read_result_item_type_at(handle, item, 0, &size))
            XCTAssertEqual(size, 0)
            size = -1
            XCTAssertNil(ntk_clipboard_read_result_item_text_at(handle, item, &size))
            XCTAssertEqual(size, 0)
            size = -1
            XCTAssertNil(ntk_clipboard_read_result_item_url_at(handle, item, &size))
            XCTAssertEqual(size, 0)
            size = -1
            XCTAssertNil(ntk_clipboard_read_result_item_image_type_at(handle, item, &size))
            XCTAssertEqual(size, 0)
        }
        for index in [2, tooFar] {
            var size = -1
            XCTAssertNil(ntk_clipboard_read_result_item_type_at(handle, 0, index, &size))
            XCTAssertEqual(size, 0)
        }
    }

    func testAReadResultOfNull() {
        var size = -1
        XCTAssertEqual(ntk_clipboard_read_result_item_count(nil), 0)
        XCTAssertEqual(ntk_clipboard_read_result_item_type_count(nil, 0), 0)
        XCTAssertNil(ntk_clipboard_read_result_item_type_at(nil, 0, 0, &size))
        XCTAssertEqual(size, 0)
        XCTAssertNil(ntk_clipboard_read_result_item_text_at(nil, 0, nil))
        XCTAssertNil(ntk_clipboard_read_result_item_url_at(nil, 0, nil))
        XCTAssertNil(ntk_clipboard_read_result_item_image_type_at(nil, 0, nil))
        ntk_clipboard_read_result_free(nil)
    }

    func testAReadResultReplacesWhatCIsNotToSee() {
        let handle = ClipboardHandles.makeReadResult(ClipboardReadResult(items: [
            ClipboardItemData(typeIdentifiers: ["a\0b"], text: "c\0d", urlString: "e\0f", imageDataUTType: "g\0h"),
        ], numberOfItems: 1))
        defer { ntk_clipboard_read_result_free(handle) }
        XCTAssertEqual(string(ntk_clipboard_read_result_item_type_at(handle, 0, 0, nil)), "a\u{FFFD}b")
        XCTAssertEqual(string(ntk_clipboard_read_result_item_text_at(handle, 0, nil)), "c\u{FFFD}d")
        XCTAssertEqual(string(ntk_clipboard_read_result_item_url_at(handle, 0, nil)), "e\u{FFFD}f")
        XCTAssertEqual(string(ntk_clipboard_read_result_item_image_type_at(handle, 0, nil)), "g\u{FFFD}h")
    }

    // MARK: - ntk_clipboard_snapshot

    func testASnapshot() {
        let handle = snapshot()
        defer { ntk_clipboard_snapshot_free(handle) }
        XCTAssertEqual(ntk_clipboard_snapshot_has_strings(handle), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_has_urls(handle), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_has_images(handle), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_has_colors(handle), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_number_of_items(handle), 2)
        XCTAssertEqual(ntk_clipboard_snapshot_type_count(handle), 2)
        var size = -1
        XCTAssertEqual(string(ntk_clipboard_snapshot_type_at(handle, 1, &size)), "public.b")
        XCTAssertEqual(size, 8)
        XCTAssertEqual(ntk_clipboard_snapshot_item_type_count(handle, 0), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_item_type_count(handle, 1), 2)
        size = -1
        XCTAssertEqual(string(ntk_clipboard_snapshot_item_type_at(handle, 1, 1, &size)), "public.b")
        XCTAssertEqual(size, 8)
        XCTAssertEqual(ntk_clipboard_snapshot_has_matching(handle), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_count(handle), 2)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(handle, 0), 2)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(handle, 1), 0)
    }

    /// The other side of each flag.
    func testTheFlagsOfASnapshotAreTheirOwn() {
        let handle = ClipboardHandles.makeSnapshot(ClipboardSnapshot(hasStrings: false, hasURLs: true, hasImages: false, hasColors: true, numberOfItems: 0,
                                                                     typeIdentifiers: [], allTypeIdentifiers: [], matchingItemIndexes: nil))
        defer { ntk_clipboard_snapshot_free(handle) }
        XCTAssertEqual(ntk_clipboard_snapshot_has_strings(handle), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_has_urls(handle), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_has_images(handle), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_has_colors(handle), 1)
    }

    func testASnapshotWithNoMatching() {
        let handle = snapshot(matching: nil)
        defer { ntk_clipboard_snapshot_free(handle) }
        XCTAssertEqual(ntk_clipboard_snapshot_has_matching(handle), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_count(handle), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(handle, 0), -1)
    }

    /// Matching was asked for and nothing matched: not the same as not asking.
    func testASnapshotThatMatchedNothing() {
        let handle = snapshot(matching: [])
        defer { ntk_clipboard_snapshot_free(handle) }
        XCTAssertEqual(ntk_clipboard_snapshot_has_matching(handle), 1)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_count(handle), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(handle, 0), -1)
    }

    func testASnapshotOutOfRange() {
        let handle = snapshot()
        defer { ntk_clipboard_snapshot_free(handle) }
        var size = -1
        XCTAssertNil(ntk_clipboard_snapshot_type_at(handle, 2, &size))
        XCTAssertEqual(size, 0)
        size = -1
        XCTAssertNil(ntk_clipboard_snapshot_type_at(handle, tooFar, &size))
        XCTAssertEqual(size, 0)
        XCTAssertEqual(ntk_clipboard_snapshot_item_type_count(handle, 2), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_item_type_count(handle, tooFar), 0)
        size = -1
        XCTAssertNil(ntk_clipboard_snapshot_item_type_at(handle, 2, 0, &size))
        XCTAssertEqual(size, 0)
        size = -1
        XCTAssertNil(ntk_clipboard_snapshot_item_type_at(handle, 0, 1, &size))
        XCTAssertEqual(size, 0)
        XCTAssertNil(ntk_clipboard_snapshot_item_type_at(handle, tooFar, 0, nil))
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(handle, 2), -1)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(handle, tooFar), -1)
    }

    /// P2-29: an index reads -1 for NULL, the rest 0 or NULL.
    func testASnapshotOfNull() {
        var size = -1
        XCTAssertEqual(ntk_clipboard_snapshot_has_strings(nil), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_has_urls(nil), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_has_images(nil), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_has_colors(nil), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_number_of_items(nil), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_type_count(nil), 0)
        XCTAssertNil(ntk_clipboard_snapshot_type_at(nil, 0, &size))
        XCTAssertEqual(size, 0)
        XCTAssertEqual(ntk_clipboard_snapshot_item_type_count(nil, 0), 0)
        XCTAssertNil(ntk_clipboard_snapshot_item_type_at(nil, 0, 0, nil))
        XCTAssertEqual(ntk_clipboard_snapshot_has_matching(nil), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_count(nil), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(nil, 0), -1)
        ntk_clipboard_snapshot_free(nil)
    }

    // MARK: - A handle of another type (undefined by the contract; part 1, chapter 6)

    func testHandlesOfOtherTypesReadAsNothing() {
        let read = readResult()
        let snap = snapshot()
        defer {
            ntk_clipboard_read_result_free(read)
            ntk_clipboard_snapshot_free(snap)
        }
        XCTAssertEqual(ntk_clipboard_read_result_item_count(snap), 0)
        XCTAssertNil(ntk_clipboard_read_result_item_text_at(snap, 0, nil))
        XCTAssertEqual(ntk_clipboard_snapshot_number_of_items(read), 0)
        XCTAssertEqual(ntk_clipboard_snapshot_matching_at(read, 0), -1)
        XCTAssertNil(ntk_string_data(read))
    }

    /// A pointer stays valid until the handle is freed, and the handle owns its bytes.
    func testAPointerOfAReaderIsStable() {
        let handle = readResult()
        defer { ntk_clipboard_read_result_free(handle) }
        let first = ntk_clipboard_read_result_item_text_at(handle, 0, nil)
        let second = ntk_clipboard_read_result_item_text_at(handle, 0, nil)
        XCTAssertEqual(first, second)
    }
}
