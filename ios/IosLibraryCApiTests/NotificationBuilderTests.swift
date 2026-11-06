//
//  NotificationBuilderTests.swift
//  IosLibraryCApiTests
//

import Foundation
import XCTest
@testable import IosLibrary
@testable import IosLibraryCApi

/// The content builder through C (part 2, 6.3 and 12.1, "ビルダー"). Nothing here reaches
/// UNUserNotificationCenter: the content is compared through `NotificationContentValue` and `makeContent()`.
/// These tests also run on the private device under ASan, so no notification is scheduled and no permission
/// is asked for.
final class NotificationBuilderTests: ClipboardTestCase {
    private let none: Int32 = 0
    private let invalid: Int32 = 1
    private var builders: [OpaquePointer] = []

    override func tearDown() async throws {
        builders.forEach { ntk_notification_content_free($0) }
        builders = []
        try await super.tearDown()
    }

    private func builder(id: String = "n1", title: String = "Title", file: StaticString = #filePath, line: UInt = #line) -> OpaquePointer? {
        var out: OpaquePointer?
        XCTAssertEqual(ntk_notification_content_create(c(id), c(title), &out), none, file: file, line: line)
        if let out { builders.append(out) }
        return out
    }

    private func value(_ handle: OpaquePointer?) -> NotificationContentValue? {
        NotificationContentBuilders.snapshot(handle)
    }

    private func soundName(_ sound: NotificationSound?) -> String {
        switch sound {
        case .none: return "none"
        case .some(.default): return "default"
        case .some(.defaultCritical): return "defaultCritical"
        case .some(.named(let name)): return "named(\(name))"
        @unknown default: return "unknown"
        }
    }

    // MARK: - Creating

    /// The library's defaults (`sound` is `.default`), checked against the library's own init.
    func testANewBuilderHasTheDefaultsOfTheLibrary() throws {
        let content = try XCTUnwrap(value(builder())).makeContent()
        let library = NotificationContent(id: "n1", title: "Title")
        XCTAssertEqual(content.id, library.id)
        XCTAssertEqual(content.title, library.title)
        XCTAssertEqual(soundName(content.sound), soundName(library.sound))
        XCTAssertEqual(soundName(content.sound), "default")
        XCTAssertNil(content.subtitle)
        XCTAssertNil(content.body)
        XCTAssertNil(content.badge)
        XCTAssertNil(content.categoryIdentifier)
        XCTAssertNil(content.interruptionLevel)
        XCTAssertNil(content.threadIdentifier)
        XCTAssertNil(content.targetContentIdentifier)
        XCTAssertNil(content.relevanceScore)
        XCTAssertNil(content.filterCriteria)
        XCTAssertTrue(content.userInfo.isEmpty)
        XCTAssertTrue(content.attachments.isEmpty)
    }

    /// R-8: the output is NULL on every rejection, and nothing is made.
    func testCreatingRejects() {
        let table: [(String, UnsafePointer<CChar>?, UnsafePointer<CChar>?)] = [
            ("NULL id", nil, c("t")), ("empty id", c(""), c("t")), ("id not UTF-8", raw([0xFF]), c("t")),
            ("NULL title", c("n"), nil), ("title not UTF-8", c("n"), raw([0xC0, 0xAF])),
        ]
        for (name, id, title) in table {
            var out = OpaquePointer(bitPattern: 0x10)
            XCTAssertEqual(ntk_notification_content_create(id, title, &out), invalid, name)
            XCTAssertNil(out, "R-8: \(name)")
        }
        XCTAssertEqual(ntk_notification_content_create(c("n"), c("t"), nil), invalid, "no output")
    }

    func testAnEmptyTitleIsATitle() throws {
        XCTAssertEqual(value(builder(title: ""))?.title, "")
    }

    func testFreeingNullDoesNothing() {
        ntk_notification_content_free(nil)
    }

    /// Part 1, 1.3.1: not thread safe, but usable from any one thread, also with the main thread stopped.
    func testABuilderIsMadeOffTheMainThread() {
        let address = onAnotherThread { () -> UInt in
            var out: OpaquePointer?
            guard ntk_notification_content_create("off", "main", &out) == 0, ntk_notification_content_set_body(out, "b") == 0 else { return 0 }
            return UInt(bitPattern: out)
        }
        let handle = OpaquePointer(bitPattern: address ?? 0)
        XCTAssertEqual(value(handle)?.body, "b")
        ntk_notification_content_free(handle)
    }

    // MARK: - Texts

    private typealias TextSetter = (OpaquePointer?, UnsafePointer<CChar>?) -> Int32

    private var textSetters: [(String, TextSetter, KeyPath<NotificationContentValue, String?>)] {
        [
            ("subtitle", ntk_notification_content_set_subtitle, \.subtitle),
            ("body", ntk_notification_content_set_body, \.body),
            ("category", ntk_notification_content_set_category, \.categoryIdentifier),
            ("thread", ntk_notification_content_set_thread, \.threadIdentifier),
            ("targetContent", ntk_notification_content_set_target_content, \.targetContentIdentifier),
            ("filterCriteria", ntk_notification_content_set_filter_criteria, \.filterCriteria),
        ]
    }

    func testEachTextSetter() {
        for (name, setter, field) in textSetters {
            let handle = builder()
            XCTAssertEqual(setter(handle, c("a\u{65E5}")), none, name)
            XCTAssertEqual(value(handle)?[keyPath: field], "a\u{65E5}", name)
            XCTAssertEqual(setter(handle, c("")), none, name)
            XCTAssertEqual(value(handle)?[keyPath: field], "", "an empty text is there: \(name)")
            for bytes in invalidUTF8 {
                XCTAssertEqual(setter(handle, raw(bytes)), invalid, name)
                XCTAssertEqual(value(handle)?[keyPath: field], "", "a rejected value changes nothing: \(name)")
            }
            XCTAssertEqual(setter(handle, nil), none, name)
            XCTAssertNil(value(handle)?[keyPath: field], "NULL restores the default: \(name)")
        }
    }

    /// NULL and a handle of another type (undefined by the contract; part 1, chapter 6) are rejected.
    func testEverySetterRejectsWhatIsNotABuilder() {
        let other = Handle.makeString("x")
        defer { ntk_string_free(other) }
        for handle in [nil, other] as [OpaquePointer?] {
            for (name, setter, _) in textSetters {
                XCTAssertEqual(setter(handle, c("x")), invalid, name)
            }
            XCTAssertEqual(ntk_notification_content_set_badge(handle, 1), invalid)
            XCTAssertEqual(ntk_notification_content_set_sound(handle, 0, nil), invalid)
            XCTAssertEqual(ntk_notification_content_set_interruption_level(handle, 0), invalid)
            XCTAssertEqual(ntk_notification_content_set_relevance_score(handle, 0.5), invalid)
            XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, c("{}")), invalid)
            XCTAssertEqual(ntk_notification_content_add_attachment(handle, c("a"), c("file:///tmp/a.png")), invalid)
        }
    }

    // MARK: - Values

    func testTheBadge() {
        let handle = builder()
        XCTAssertEqual(ntk_notification_content_set_badge(handle, 0), none)
        XCTAssertEqual(value(handle)?.badge, 0)
        XCTAssertEqual(ntk_notification_content_set_badge(handle, Int32.max), none)
        XCTAssertEqual(value(handle)?.badge, Int(Int32.max))
        for bad: Int32 in [-2, Int32.min] {
            XCTAssertEqual(ntk_notification_content_set_badge(handle, bad), invalid)
            XCTAssertEqual(value(handle)?.badge, Int(Int32.max))
        }
        XCTAssertEqual(ntk_notification_content_set_badge(handle, -1), none)
        XCTAssertNil(value(handle)?.badge)
    }

    func testTheSound() {
        let handle = builder()
        XCTAssertEqual(ntk_notification_content_set_sound(handle, Int32(NTK_NOTIFICATION_SOUND_NONE), unreadable()), none)
        XCTAssertEqual(soundName(value(handle)?.sound), "none")
        XCTAssertEqual(ntk_notification_content_set_sound(handle, Int32(NTK_NOTIFICATION_SOUND_DEFAULT_CRITICAL), unreadable()), none)
        XCTAssertEqual(soundName(value(handle)?.sound), "defaultCritical")
        XCTAssertEqual(ntk_notification_content_set_sound(handle, Int32(NTK_NOTIFICATION_SOUND_NAMED), c("ding.caf")), none)
        XCTAssertEqual(soundName(value(handle)?.sound), "named(ding.caf)")
        XCTAssertEqual(ntk_notification_content_set_sound(handle, Int32(NTK_NOTIFICATION_SOUND_DEFAULT), unreadable()), none)
        XCTAssertEqual(soundName(value(handle)?.sound), "default")
        for (kind, name) in [(Int32(NTK_NOTIFICATION_SOUND_NAMED), nil), (Int32(NTK_NOTIFICATION_SOUND_NAMED), c("")),
                             (Int32(NTK_NOTIFICATION_SOUND_NAMED), raw([0xFF])), (-1, c("x")), (4, c("x"))] as [(Int32, UnsafePointer<CChar>?)] {
            XCTAssertEqual(ntk_notification_content_set_sound(handle, kind, name), invalid, "\(kind)")
            XCTAssertEqual(soundName(value(handle)?.sound), "default")
        }
    }

    func testTheInterruptionLevel() {
        let handle = builder()
        let table: [(Int32, NotificationInterruptionLevel?)] = [(1, .passive), (2, .active), (3, .timeSensitive), (4, .critical), (0, nil)]
        for (level, expected) in table {
            XCTAssertEqual(ntk_notification_content_set_interruption_level(handle, level), none, "\(level)")
            XCTAssertEqual(value(handle)?.interruptionLevel, expected, "\(level)")
        }
        for bad: Int32 in [-1, 5] {
            XCTAssertEqual(ntk_notification_content_set_interruption_level(handle, bad), invalid)
            XCTAssertNil(value(handle)?.interruptionLevel)
        }
    }

    func testTheRelevanceScore() {
        let handle = builder()
        for score in [0.0, 1.0, 0.25] {
            XCTAssertEqual(ntk_notification_content_set_relevance_score(handle, score), none, "\(score)")
            XCTAssertEqual(value(handle)?.relevanceScore, score)
        }
        for bad in [Double.nan, .infinity, -.infinity, -0.0001, 1.0001] {
            XCTAssertEqual(ntk_notification_content_set_relevance_score(handle, bad), invalid, "\(bad)")
            XCTAssertEqual(value(handle)?.relevanceScore, 0.25)
        }
    }

    func testTheUserInfo() {
        let handle = builder()
        XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, c(#"{"a":1,"b":{"c":[true,"x"]}}"#)), none)
        XCTAssertEqual(value(handle)?.userInfo, ["a": .integer(1), "b": .dictionary(["c": .array([.bool(true), .string("x")])])])
        for bad in ["[1]", "{", #"{"a":null}"#, #"{"a":[1,null]}"#, #"{"a":1e400}"#, #"{"com.jonghyunkim.nativetoolkit":1}"#, "\"x\"", ""] {
            XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, c(bad)), invalid, bad)
            XCTAssertEqual(value(handle)?.userInfo.count, 2, "a rejected value changes nothing: \(bad)")
        }
        XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, raw([0x7B, 0xFF, 0x7D])), invalid)
        XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, nil), none)
        XCTAssertEqual(value(handle)?.userInfo, [:])
    }

    /// Part 2, 6.3: only an absolute `file://` URL, with no host or `localhost`. The scheme is matched without case
    /// (RFC 3986, 3.1).
    func testTheAttachmentURL() {
        func accepted(_ text: String) -> String? {
            do throws(EntryError) { return try NotificationContentBuilders.attachmentURL(text).path } catch { return nil }
        }
        XCTAssertEqual(accepted("file:///tmp/a.png"), "/tmp/a.png")
        XCTAssertEqual(accepted("file://localhost/tmp/a.png"), "/tmp/a.png")
        XCTAssertEqual(accepted("FILE:///tmp/a.png"), "/tmp/a.png")
        XCTAssertEqual(accepted("File://LocalHost/tmp/a.png"), "/tmp/a.png")
        for text in ["file:abc", "file:/tmp/a.png", "file:relative/a.png", "file://host/tmp/a.png", "file://", "/tmp/a.png", "tmp/a.png",
                     "https://example.com/a.png", "filex:///tmp/a.png", ""] {
            XCTAssertNil(accepted(text), text)
        }
    }

    /// On this SDK `URL(string:)` encodes a space instead of failing, so it is taken. Pinned here, so that a change
    /// of Foundation shows.
    func testASpaceInTheAttachmentURLIsEncoded() throws {
        let handle = builder()
        XCTAssertEqual(ntk_notification_content_add_attachment(handle, c("a"), c("file:///tmp/a b.png")), none)
        let url = try XCTUnwrap(value(handle)?.attachments.first?.fileURL)
        XCTAssertEqual(url.path, "/tmp/a b.png")
        XCTAssertEqual(url.absoluteString, "file:///tmp/a%20b.png")
    }

    /// The five sequences part 1, chapter 6 names, in each string the builder takes.
    func testEveryStringOfTheBuilderMustBeUTF8() {
        let handle = builder()
        let sequences: [[UInt8]] = [[0xC3, 0x28], [0xED, 0xA0, 0x80], [0xC0, 0xAF], [0xFF], [0xF4, 0x90, 0x80, 0x80]]
        for bytes in sequences {
            var out = OpaquePointer(bitPattern: 0x10)
            XCTAssertEqual(ntk_notification_content_create(raw(bytes), c("t"), &out), invalid, "id \(bytes)")
            XCTAssertNil(out)
            XCTAssertEqual(ntk_notification_content_create(c("n"), raw(bytes), &out), invalid, "title \(bytes)")
            XCTAssertEqual(ntk_notification_content_add_attachment(handle, raw(bytes), c("file:///tmp/a.png")), invalid, "identifier \(bytes)")
            XCTAssertEqual(ntk_notification_content_add_attachment(handle, c("a"), raw(bytes)), invalid, "url \(bytes)")
            XCTAssertEqual(ntk_notification_content_set_sound(handle, Int32(NTK_NOTIFICATION_SOUND_NAMED), raw(bytes)), invalid, "sound \(bytes)")
            XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, raw(bytes)), invalid, "userInfo \(bytes)")
        }
        XCTAssertEqual(value(handle)?.attachments.count, 0)
        XCTAssertEqual(soundName(value(handle)?.sound), "default")
    }

    func testAttachments() throws {
        let handle = builder()
        XCTAssertEqual(ntk_notification_content_add_attachment(handle, c("first"), c("file:///tmp/first.png")), none)
        XCTAssertEqual(ntk_notification_content_add_attachment(handle, c(""), c("file:///tmp/second%20image.png")), none)
        let attachments = try XCTUnwrap(value(handle)?.attachments)
        XCTAssertEqual(attachments.map(\.identifier), ["first", ""])
        XCTAssertEqual(attachments.map(\.fileURL.path), ["/tmp/first.png", "/tmp/second image.png"])
        // M4: anything else than file:// fails only when the request is added, so the entry rejects it.
        let table: [(UnsafePointer<CChar>?, UnsafePointer<CChar>?)] = [
            (nil, c("file:///tmp/a.png")), (c("a"), nil), (c("a"), c("https://example.com/a.png")), (c("a"), c("/tmp/a.png")),
            (c("a"), c("")), (raw([0xFF]), c("file:///tmp/a.png")), (c("a"), raw([0xED, 0xA0, 0x80])),
        ]
        for (identifier, url) in table {
            XCTAssertEqual(ntk_notification_content_add_attachment(handle, identifier, url), invalid)
        }
        XCTAssertEqual(value(handle)?.attachments.count, 2)
    }

    // MARK: - What an operation takes (part 1, 1.1; 12.1)

    /// The copy does not follow later changes, and outlives the builder.
    func testTheCopyDoesNotChangeWithTheBuilder() throws {
        let handle = builder()
        XCTAssertEqual(ntk_notification_content_set_body(handle, c("before")), none)
        XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, c(#"{"k":"v"}"#)), none)
        let copy = try XCTUnwrap(NotificationContentBuilders.snapshot(handle))

        XCTAssertEqual(ntk_notification_content_set_body(handle, c("after")), none)
        XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, nil), none)
        builders.removeAll { $0 == handle }
        ntk_notification_content_free(handle)

        let content = copy.makeContent()
        XCTAssertEqual(content.body, "before")
        XCTAssertEqual(content.userInfo["k"] as? String, "v")
    }

    func testEverythingReachesTheContent() throws {
        let handle = builder(id: "full", title: "T")
        XCTAssertEqual(ntk_notification_content_set_subtitle(handle, c("s")), none)
        XCTAssertEqual(ntk_notification_content_set_body(handle, c("b")), none)
        XCTAssertEqual(ntk_notification_content_set_badge(handle, 3), none)
        XCTAssertEqual(ntk_notification_content_set_sound(handle, Int32(NTK_NOTIFICATION_SOUND_NAMED), c("s.caf")), none)
        XCTAssertEqual(ntk_notification_content_set_category(handle, c("cat")), none)
        XCTAssertEqual(ntk_notification_content_set_interruption_level(handle, Int32(NTK_NOTIFICATION_INTERRUPTION_TIME_SENSITIVE)), none)
        XCTAssertEqual(ntk_notification_content_set_thread(handle, c("th")), none)
        XCTAssertEqual(ntk_notification_content_set_target_content(handle, c("tc")), none)
        XCTAssertEqual(ntk_notification_content_set_relevance_score(handle, 0.5), none)
        XCTAssertEqual(ntk_notification_content_set_filter_criteria(handle, c("fc")), none)
        XCTAssertEqual(ntk_notification_content_set_user_info_json(handle, c(#"{"n":2.5,"u":18446744073709551615}"#)), none)
        XCTAssertEqual(ntk_notification_content_add_attachment(handle, c("img"), c("file:///tmp/img.png")), none)

        let content = try XCTUnwrap(value(handle)).makeContent()
        XCTAssertEqual(content.id, "full")
        XCTAssertEqual(content.title, "T")
        XCTAssertEqual(content.subtitle, "s")
        XCTAssertEqual(content.body, "b")
        XCTAssertEqual(content.badge, 3)
        XCTAssertEqual(soundName(content.sound), "named(s.caf)")
        XCTAssertEqual(content.categoryIdentifier, "cat")
        XCTAssertEqual(content.interruptionLevel, .timeSensitive)
        XCTAssertEqual(content.threadIdentifier, "th")
        XCTAssertEqual(content.targetContentIdentifier, "tc")
        XCTAssertEqual(content.relevanceScore, 0.5)
        XCTAssertEqual(content.filterCriteria, "fc")
        XCTAssertEqual((content.userInfo["n"] as? NSNumber)?.doubleValue, 2.5)
        XCTAssertEqual((content.userInfo["u"] as? NSNumber)?.uint64Value, UInt64.max)
        XCTAssertEqual(content.attachments.map(\.identifier), ["img"])
        // What the library would check before adding it: no reserved key, and a property list.
        XCTAssertFalse(NotificationMarker.isReserved(in: content.userInfo))
        XCTAssertTrue(NotificationRepositoryImpl.isPropertyList(content.userInfo))
    }
}
