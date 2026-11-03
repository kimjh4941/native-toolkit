//
//  ClipboardMappingTests.swift
//  IosLibraryCApiTests
//

import IosLibrary
import XCTest
@testable import IosLibraryCApi

/// The conversions of part 2, 6.1 and 12.1 ("0 で埋めた構造体", "写しの表"), compared with Swift values
/// directly: `localOnly` and such cannot be read back from the OS, and no pasteboard is touched here.
final class ClipboardMappingTests: ClipboardTestCase {
    private let invalid = ClipboardRejection.entry(.invalidParameter)
    private let notSupported = ClipboardRejection.entry(.notSupported)

    private func assertRejected<Value>(_ expected: ClipboardRejection, file: StaticString = #filePath, line: UInt = #line,
                                       _ body: () throws(ClipboardRejection) -> Value) {
        do throws(ClipboardRejection) {
            XCTFail("accepted: \(try body())", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    // MARK: - Scope

    func testNoScopeIsTheGeneralPasteboard() throws {
        XCTAssertEqual(try ClipboardMapping.scope(nil), .general)
    }

    func testAZeroFilledScopeIsTheGeneralPasteboard() throws {
        var scope = zeroScope()
        XCTAssertEqual(try ClipboardMapping.scope(&scope), .general)
    }

    func testTheGeneralKindDoesNotReadTheName() throws {
        var scope = zeroScope()
        scope.name = unreadable()
        XCTAssertEqual(try ClipboardMapping.scope(&scope), .general)
    }

    func testNamedAndUniqueCarryTheirName() throws {
        var scope = named("a.name")
        XCTAssertEqual(try ClipboardMapping.scope(&scope), .named("a.name"))
        scope.kind = Int32(NTK_CLIPBOARD_SCOPE_UNIQUE)
        XCTAssertEqual(try ClipboardMapping.scope(&scope), .unique("a.name"))
    }

    func testNamedAndUniqueNeedANameThatIsNotEmpty() {
        for kind in [NTK_CLIPBOARD_SCOPE_NAMED, NTK_CLIPBOARD_SCOPE_UNIQUE] {
            var scope = zeroScope()
            scope.kind = Int32(kind)
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.scope(&scope) }
            scope.name = c("")
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.scope(&scope) }
            for bytes in invalidUTF8 {
                scope.name = raw(bytes)
                assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.scope(&scope) }
            }
        }
    }

    func testAScopeKindOutOfRangeIsRejected() {
        for kind: Int32 in [-1, 3, Int32.max] {
            var scope = named("a.name")
            scope.kind = kind
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.scope(&scope) }
        }
    }

    /// Each reserved field of the struct: `reserved:` has to name it (StructReader's rule 1).
    func testEveryReservedFieldOfTheScopeIsChecked() {
        var scope = zeroScope()
        scope.reserved0 = 1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.scope(&scope) }
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.requiredScope(&scope) }
        scope = zeroScope()
        scope.reserved1 = 1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.scope(&scope) }
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.requiredScope(&scope) }
    }

    func testTheSizeOfTheScopeIsChecked() {
        var scope = zeroScope()
        scope.struct_size -= 8
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.scope(&scope) }
        scope.struct_size = 4097
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.scope(&scope) }
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.requiredScope(&scope) }
    }

    func testTheUnknownPartOfTheScope() throws {
        let size = MemoryLayout<ntk_clipboard_scope>.size
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size + 8, alignment: 8)
        defer { memory.deallocate() }
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: size + 8)
        memory.storeBytes(of: UInt32(size + 8), as: UInt32.self)
        let pointer = memory.assumingMemoryBound(to: ntk_clipboard_scope.self)
        XCTAssertEqual(try ClipboardMapping.scope(pointer), .general)
        memory.storeBytes(of: UInt8(1), toByteOffset: size + 7, as: UInt8.self)
        assertRejected(notSupported) { () throws(ClipboardRejection) in try ClipboardMapping.scope(pointer) }
    }

    func testTheRemovalNeedsAScope() throws {
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.requiredScope(nil) }
        var scope = named("a.name")
        XCTAssertEqual(try ClipboardMapping.requiredScope(&scope), .named("a.name"))
        var zero = zeroScope()
        XCTAssertEqual(try ClipboardMapping.requiredScope(&zero), .general)
    }

    // MARK: - Creating

    func testCreating() throws {
        XCTAssertEqual(try ClipboardMapping.creationRequest(kind: Int32(NTK_CLIPBOARD_SCOPE_NAMED), name: c("a.name")), .named("a.name"))
        // UNIQUE does not read the name.
        XCTAssertEqual(try ClipboardMapping.creationRequest(kind: Int32(NTK_CLIPBOARD_SCOPE_UNIQUE), name: unreadable()), .unique)
        XCTAssertEqual(try ClipboardMapping.creationRequest(kind: Int32(NTK_CLIPBOARD_SCOPE_UNIQUE), name: nil), .unique)
    }

    func testCreatingRejects() {
        let named = Int32(NTK_CLIPBOARD_SCOPE_NAMED)
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.creationRequest(kind: named, name: nil) }
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.creationRequest(kind: named, name: c("")) }
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.creationRequest(kind: named, name: raw([0xFF])) }
        for kind in [Int32(NTK_CLIPBOARD_SCOPE_GENERAL), -1, 3] {
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.creationRequest(kind: kind, name: c("a.name")) }
        }
    }

    func testTheNameOfAScope() {
        XCTAssertEqual(ClipboardMapping.name(of: .named("a")), "a")
        XCTAssertEqual(ClipboardMapping.name(of: .unique("b")), "b")
        XCTAssertNil(ClipboardMapping.name(of: .general))
    }

    // MARK: - Content

    /// Every field that `kind` does not name holds a pointer that stops the process when read.
    private func onlyFieldsOf(_ kind: Int32) -> ntk_clipboard_write_content {
        var value = ntk_clipboard_write_content()
        value.struct_size = UInt32(MemoryLayout<ntk_clipboard_write_content>.size)
        value.kind = kind
        value.text = unreadable()
        value.html = unreadable()
        value.url = unreadable()
        value.path = unreadable()
        value.data = unreadable()
        value.data_size = 1
        value.ut_type = unreadable()
        value.red = .nan
        value.green = .nan
        value.blue = .nan
        value.alpha = .nan
        value.texts = unreadable()
        value.text_count = 1
        value.representations = unreadable()
        value.representation_count = 1
        return value
    }

    func testPlainText() throws {
        var value = onlyFieldsOf(Int32(NTK_CLIPBOARD_CONTENT_PLAIN_TEXT))
        value.text = c("a\u{1F600}")
        XCTAssertEqual(try ClipboardMapping.content(&value), .plainText("a\u{1F600}"))
        value.text = c("")
        XCTAssertEqual(try ClipboardMapping.content(&value), .plainText(""))
    }

    func testHtml() throws {
        var value = onlyFieldsOf(Int32(NTK_CLIPBOARD_CONTENT_HTML))
        value.text = c("plain")
        value.html = c("<b>x</b>")
        XCTAssertEqual(try ClipboardMapping.content(&value), .htmlText(plain: "plain", html: "<b>x</b>"))
        // As on Android: the plain text may be left out.
        value.text = nil
        XCTAssertEqual(try ClipboardMapping.content(&value), .htmlText(plain: "", html: "<b>x</b>"))
    }

    func testUrl() throws {
        var value = onlyFieldsOf(Int32(NTK_CLIPBOARD_CONTENT_URL))
        value.url = c("not a url")
        XCTAssertEqual(try ClipboardMapping.content(&value), .url("not a url"), "the scheme is the library's")
    }

    func testImageFile() throws {
        var value = onlyFieldsOf(Int32(NTK_CLIPBOARD_CONTENT_IMAGE_FILE))
        value.path = c("/no/such/file.png")
        XCTAssertEqual(try ClipboardMapping.content(&value), .imageFile(path: "/no/such/file.png"), "whether it exists is the library's")
    }

    func testImageAndCustomData() throws {
        for (kind, isImage) in [(NTK_CLIPBOARD_CONTENT_IMAGE_DATA, true), (NTK_CLIPBOARD_CONTENT_CUSTOM_DATA, false)] {
            var value = onlyFieldsOf(Int32(kind))
            value.data = array([1, 2, 3])
            value.data_size = 3
            value.ut_type = c("com.example.type")
            let bytes = Data([1, 2, 3])
            XCTAssertEqual(try ClipboardMapping.content(&value),
                           isImage ? .imageData(bytes, utType: "com.example.type") : .customData(bytes, utType: "com.example.type"))
            // Size 0 is the library's EMPTY_CONTENT, with or without a pointer.
            value.data = nil
            value.data_size = 0
            XCTAssertEqual(try ClipboardMapping.content(&value),
                           isImage ? .imageData(Data(), utType: "com.example.type") : .customData(Data(), utType: "com.example.type"))
        }
    }

    func testColor() throws {
        var value = onlyFieldsOf(Int32(NTK_CLIPBOARD_CONTENT_COLOR))
        value.red = 0.1
        value.green = 0.2
        value.blue = 0.3
        value.alpha = 0.4
        XCTAssertEqual(try ClipboardMapping.content(&value), .color(red: 0.1, green: 0.2, blue: 0.3, alpha: 0.4))
        value.red = 7
        XCTAssertEqual(try ClipboardMapping.content(&value), .color(red: 7, green: 0.2, blue: 0.3, alpha: 0.4), "the range is the library's")
    }

    func testAZeroFilledColorIsTransparent() throws {
        var value = content(Int(NTK_CLIPBOARD_CONTENT_COLOR))
        XCTAssertEqual(try ClipboardMapping.content(&value), .color(red: 0, green: 0, blue: 0, alpha: 0))
    }

    func testMultipleText() throws {
        var value = onlyFieldsOf(Int32(NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT))
        value.texts = array([c("a"), c("b")] as [UnsafePointer<CChar>?])
        value.text_count = 2
        XCTAssertEqual(try ClipboardMapping.content(&value), .multipleText(["a", "b"]))
    }

    func testMultipleTextRejects() {
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT))
        assertRejected(.emptyItems) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.texts = array([c("a")] as [UnsafePointer<CChar>?])
        assertRejected(.emptyItems) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.texts = nil
        value.text_count = 1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.texts = array([c("a"), nil] as [UnsafePointer<CChar>?])
        value.text_count = 2
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.texts = array([c("a"), raw([0xFF])] as [UnsafePointer<CChar>?])
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.text_count = -1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
    }

    func testMultiRepresentation() throws {
        var value = onlyFieldsOf(Int32(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION))
        value.representations = array([representation(c("com.example.a"), [1]), representation(c("com.example.b"), [2, 3])])
        value.representation_count = 2
        XCTAssertEqual(try ClipboardMapping.content(&value),
                       .multiRepresentation(["com.example.a": Data([1]), "com.example.b": Data([2, 3])]))
    }

    /// P2-5: the step is the element's own `struct_size`.
    func testMultiRepresentationSteppedByTheSizeOfTheElement() throws {
        let known = MemoryLayout<ntk_clipboard_representation>.size
        let wide = known + 8
        let memory = UnsafeMutableRawPointer.allocate(byteCount: wide * 2, alignment: 8)
        defer { memory.deallocate() }
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: wide * 2)
        for (index, name) in ["com.example.a", "com.example.b"].enumerated() {
            var element = representation(c(name), [UInt8(index)])
            element.struct_size = UInt32(wide)
            memory.advanced(by: index * wide).copyMemory(from: &element, byteCount: known)
        }
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION))
        value.representations = UnsafePointer(memory.assumingMemoryBound(to: ntk_clipboard_representation.self))
        value.representation_count = 2
        XCTAssertEqual(try ClipboardMapping.content(&value),
                       .multiRepresentation(["com.example.a": Data([0]), "com.example.b": Data([1])]))
        // The unknown part of an element.
        memory.storeBytes(of: UInt8(1), toByteOffset: wide + known, as: UInt8.self)
        assertRejected(notSupported) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
    }

    func testMultiRepresentationRejects() {
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION))
        assertRejected(.emptyItems) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.representation_count = 1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.representation_count = -1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }

        // The same type twice.
        value.representations = array([representation(c("com.example.a"), [1]), representation(c("com.example.a"), [2])])
        value.representation_count = 2
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }

        // A NULL type, and an invalid one.
        value.representations = array([representation(nil, [1])])
        value.representation_count = 1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.representations = array([representation(raw([0xFF]), [1])])
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }

        // NULL bytes with a size.
        var element = representation(c("com.example.a"), [1])
        element.data = nil
        value.representations = array([element])
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }

        // The reserved field of the element.
        element = representation(c("com.example.a"), [1])
        element.reserved0 = 1
        value.representations = array([element])
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }

        // Elements of two sizes.
        element = representation(c("com.example.a"), [1])
        var other = representation(c("com.example.b"), [1])
        other.struct_size -= 8
        value.representations = array([element, other])
        value.representation_count = 2
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
    }

    func testAMultiRepresentationOfNoBytesIsTheLibrarys() throws {
        var element = representation(c("com.example.a"), [])
        element.data = nil
        var value = content(Int(NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION))
        value.representations = array([element])
        value.representation_count = 1
        XCTAssertEqual(try ClipboardMapping.content(&value), .multiRepresentation(["com.example.a": Data()]))
    }

    /// The field each kind needs, one at a time: NULL and each invalid sequence.
    func testRequiredTextOfEachKind() {
        let fields: [(Int32, WritableKeyPath<ntk_clipboard_write_content, UnsafePointer<CChar>?>)] = [
            (Int32(NTK_CLIPBOARD_CONTENT_PLAIN_TEXT), \.text),
            (Int32(NTK_CLIPBOARD_CONTENT_HTML), \.html),
            (Int32(NTK_CLIPBOARD_CONTENT_URL), \.url),
            (Int32(NTK_CLIPBOARD_CONTENT_IMAGE_FILE), \.path),
            (Int32(NTK_CLIPBOARD_CONTENT_IMAGE_DATA), \.ut_type),
            (Int32(NTK_CLIPBOARD_CONTENT_CUSTOM_DATA), \.ut_type),
        ]
        for (kind, field) in fields {
            var value = content(Int(kind))
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
            for bytes in invalidUTF8 {
                value[keyPath: field] = raw(bytes)
                assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
            }
        }
    }

    func testAnHtmlPlainTextThatIsNotUTF8IsRejected() {
        var value = content(Int(NTK_CLIPBOARD_CONTENT_HTML))
        value.html = c("<b>x</b>")
        value.text = raw([0xFF])
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
    }

    func testAnEmptyImagePathIsRejected() {
        var value = content(Int(NTK_CLIPBOARD_CONTENT_IMAGE_FILE))
        value.path = c("")
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
    }

    func testNullBytesWithASizeAreRejected() {
        for kind in [NTK_CLIPBOARD_CONTENT_IMAGE_DATA, NTK_CLIPBOARD_CONTENT_CUSTOM_DATA] {
            var value = content(Int(kind))
            value.ut_type = c("com.example.type")
            value.data_size = 1
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
            value.data = array([1])
            value.data_size = -1
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        }
    }

    func testAContentKindOutOfRangeIsRejected() {
        for kind: Int32 in [-1, 9] {
            var value = plainText("x")
            value.kind = kind
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        }
    }

    func testEveryReservedFieldOfTheContentIsChecked() {
        var value = plainText("x")
        value.reserved0 = 1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value = plainText("x")
        value.reserved1 = 1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
    }

    func testTheSizeOfTheContentIsChecked() {
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(nil) }
        var value = plainText("x")
        value.struct_size -= 8
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
        value.struct_size = 4097
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.content(&value) }
    }

    // MARK: - Options

    func testNoOptionsAndZeroFilledOptionsAreTheDefault() throws {
        XCTAssertEqual(try ClipboardMapping.options(nil), .default)
        var value = options()
        XCTAssertEqual(try ClipboardMapping.options(&value), .default)
        XCTAssertEqual(ClipboardCopyOptions.default, ClipboardCopyOptions(localOnly: true, expirationDate: nil))
    }

    func testNotLocalOnlyIsInverted() throws {
        var value = options()
        value.not_local_only = 1
        XCTAssertEqual(try ClipboardMapping.options(&value), ClipboardCopyOptions(localOnly: false, expirationDate: nil))
        value.not_local_only = -5
        XCTAssertEqual(try ClipboardMapping.options(&value).localOnly, false)
    }

    func testTheExpiration() throws {
        var value = options()
        value.has_expiration = 1
        value.expiration_unix_seconds = 1_000_000.5
        XCTAssertEqual(try ClipboardMapping.options(&value),
                       ClipboardCopyOptions(localOnly: true, expirationDate: Date(timeIntervalSince1970: 1_000_000.5)))
    }

    func testTheSecondsAreReadOnlyWithTheFlag() throws {
        var value = options()
        value.expiration_unix_seconds = .nan
        XCTAssertEqual(try ClipboardMapping.options(&value), .default)
    }

    func testAnExpirationThatIsNotFiniteIsRejected() {
        for seconds in [Double.nan, .infinity, -.infinity] {
            var value = options()
            value.has_expiration = 1
            value.expiration_unix_seconds = seconds
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.options(&value) }
        }
    }

    func testTheOptionsStructIsChecked() {
        var value = options()
        value.reserved0 = 1
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.options(&value) }
        value = options()
        value.struct_size -= 8
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.options(&value) }
    }

    // MARK: - struct_size: the unknown part and the upper limit

    /// `value`, 8 bytes longer than this version knows: `body` gets it with those bytes 0, then with the last one not.
    private func withUnknownPart<Value>(_ value: Value, _ body: (UnsafePointer<Value>, _ isZero: Bool) -> Void) {
        let size = MemoryLayout<Value>.size
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size + 8, alignment: 8)
        defer { memory.deallocate() }
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: size + 8)
        withUnsafeBytes(of: value) { memory.copyMemory(from: $0.baseAddress!, byteCount: size) }
        memory.storeBytes(of: UInt32(size + 8), as: UInt32.self)
        let pointer = UnsafePointer(memory.assumingMemoryBound(to: Value.self))
        body(pointer, true)
        memory.storeBytes(of: UInt8(1), toByteOffset: size + 7, as: UInt8.self)
        body(pointer, false)
    }

    func testTheUnknownPartOfTheContent() {
        withUnknownPart(plainText("x")) { pointer, isZero in
            if isZero {
                XCTAssertEqual(try? ClipboardMapping.content(pointer), .plainText("x"))
            } else {
                assertRejected(notSupported) { () throws(ClipboardRejection) in try ClipboardMapping.content(pointer) }
            }
        }
    }

    func testTheUnknownPartOfTheOptions() {
        var value = options()
        value.not_local_only = 1
        withUnknownPart(value) { pointer, isZero in
            if isZero {
                XCTAssertEqual(try? ClipboardMapping.options(pointer), ClipboardCopyOptions(localOnly: false, expirationDate: nil))
            } else {
                assertRejected(notSupported) { () throws(ClipboardRejection) in try ClipboardMapping.options(pointer) }
            }
        }
    }

    func testTheUpperLimitOfTheOptions() {
        var value = options()
        value.struct_size = 4097
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.options(&value) }
    }

    // MARK: - Types

    func testTheType() throws {
        XCTAssertEqual(try ClipboardMapping.utType(c("public.png")), "public.png")
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.utType(nil) }
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.utType(raw([0xFF])) }
    }

    func testMatchingTypes() throws {
        XCTAssertNil(try ClipboardMapping.matchingTypes(nil, count: 0))
        XCTAssertNil(try ClipboardMapping.matchingTypes(array([c("a")] as [UnsafePointer<CChar>?]), count: 0))
        XCTAssertEqual(try ClipboardMapping.matchingTypes(array([c("a"), c("b")] as [UnsafePointer<CChar>?]), count: 2), ["a", "b"])
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.matchingTypes(nil, count: 1) }
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.matchingTypes(nil, count: -1) }
        let withNull = array([c("a"), nil] as [UnsafePointer<CChar>?])
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.matchingTypes(withNull, count: 2) }
        let notUTF8 = array([raw([0xFF])] as [UnsafePointer<CChar>?])
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.matchingTypes(notUTF8, count: 1) }
    }

    // MARK: - Load

    func testTheKindsToLoad() throws {
        // Only FILE reads the type.
        XCTAssertEqual(try ClipboardMapping.loadRequest(kind: 0, utType: unreadable()), .text)
        XCTAssertEqual(try ClipboardMapping.loadRequest(kind: 1, utType: unreadable()), .url)
        XCTAssertEqual(try ClipboardMapping.loadRequest(kind: 2, utType: unreadable()), .image)
        XCTAssertEqual(try ClipboardMapping.loadRequest(kind: 3, utType: c("public.png")), .file(utType: "public.png"))
        XCTAssertEqual(try ClipboardMapping.loadRequest(kind: 3, utType: c("")), .file(utType: ""), "a type no item has is the library's")
    }

    func testTheKindsToLoadReject() {
        for kind: Int32 in [-1, 4] {
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.loadRequest(kind: kind, utType: c("public.png")) }
        }
        assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.loadRequest(kind: 3, utType: nil) }
        for bytes in invalidUTF8 {
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.loadRequest(kind: 3, utType: raw(bytes)) }
        }
    }

    func testTheKindOfAScopeInAnEvent() {
        XCTAssertEqual(ClipboardMapping.scopeKind(of: .general), 0)
        XCTAssertEqual(ClipboardMapping.scopeKind(of: .named("a")), 1)
        XCTAssertEqual(ClipboardMapping.scopeKind(of: .unique("a")), 2)
    }

    func testAChangeEvent() {
        XCTAssertEqual(ClipboardMapping.change(of: ClipboardChangeEvent(kind: .changed(typesAdded: ["a"], typesRemoved: ["b"]), scope: .named("n"))),
                       ClipboardChange(kind: 0, scopeKind: 1, scopeName: "n", typesAdded: ["a"], typesRemoved: ["b"]))
        XCTAssertEqual(ClipboardMapping.change(of: ClipboardChangeEvent(kind: .removed, scope: .unique("u"))),
                       ClipboardChange(kind: 1, scopeKind: 2, scopeName: "u", typesAdded: [], typesRemoved: []))
        XCTAssertEqual(ClipboardMapping.change(of: ClipboardChangeEvent(kind: .changed(typesAdded: [], typesRemoved: []), scope: .general)),
                       ClipboardChange(kind: 0, scopeKind: 0, scopeName: nil, typesAdded: [], typesRemoved: []))
    }

    /// Part 2, 6.1: no value in C. The `@unknown default` branches cannot be reached from a test.
    func testAForegroundDetectionHasNoChange() {
        XCTAssertNil(ClipboardMapping.change(of: ClipboardChangeEvent(kind: .changedDetectedOnForeground, scope: .general)))
    }

    // MARK: - Patterns

    /// Written out: the numbers of the header, the raw values of the library.
    private let patternTable: [(UInt32, String)] = [
        (1 << 0, "probableWebURL"), (1 << 1, "probableWebSearch"), (1 << 2, "number"), (1 << 3, "link"),
        (1 << 4, "emailAddress"), (1 << 5, "phoneNumber"), (1 << 6, "postalAddress"), (1 << 7, "calendarEvent"),
        (1 << 8, "flightNumber"), (1 << 9, "moneyAmount"), (1 << 10, "shipmentTrackingNumber"),
    ]

    func testEachPatternBit() throws {
        XCTAssertEqual(patternTable.count, ClipboardDetectionPattern.allCases.count)
        for (bit, name) in patternTable {
            let pattern = try XCTUnwrap(ClipboardDetectionPattern(rawValue: name))
            XCTAssertEqual(try ClipboardMapping.patterns(bit), [pattern], name)
            XCTAssertEqual(ClipboardMapping.bits(of: [pattern]), bit, name)
        }
    }

    func testAllThePatternsTogether() throws {
        let all = patternTable.reduce(UInt32(0)) { $0 | $1.0 }
        XCTAssertEqual(try ClipboardMapping.patterns(all), Set(ClipboardDetectionPattern.allCases))
        XCTAssertEqual(ClipboardMapping.bits(of: Set(ClipboardDetectionPattern.allCases)), all)
        XCTAssertEqual(ClipboardMapping.bits(of: []), 0)
    }

    func testNoPatternsAndUnknownBits() {
        assertRejected(.emptyPatterns) { () throws(ClipboardRejection) in try ClipboardMapping.patterns(0) }
        for bits: UInt32 in [1 << 11, 1 << 31, 1 | 1 << 11] {
            assertRejected(invalid) { () throws(ClipboardRejection) in try ClipboardMapping.patterns(bits) }
        }
    }

    // MARK: - Errors

    /// Part 2, 11.3: every case, through `errorCode`, to the number written out.
    func testEveryErrorOfTheLibrary() {
        let detail = ClipboardFailureDetail(domain: "d", code: 1, debugMessage: "m")
        let table: [(ClipboardError, Int32)] = [
            (.invalidRequest("x"), 1), (.unknown(detail), 4), (.emptyContent, 6), (.emptyItemList, 7), (.invalidURL("x"), 8),
            (.pasteboardUnavailable(name: "x"), 9), (.emptyDetectionPatterns, 12), (.invalidTypeIdentifier("x"), 13),
            (.invalidPasteboardName("x"), 14), (.invalidColor, 15), (.invalidImageData, 16), (.invalidExpirationDate, 17),
            (.contentTooLarge(byteCount: 2, limit: 1), 18), (.fileNotFound(path: "x"), 19), (.imageLoadFailed(path: "x"), 20),
            (.imageEncodingFailed, 21), (.cannotRemoveGeneralPasteboard, 22), (.noMatchingItem, 23), (.providerLoadFailed(detail), 24),
            (.unexpectedType, 25), (.fileCopyFailed(detail), 26), (.cancelled, 27), (.timedOut(operation: .detection), 28),
            (.detectionFailed(detail), 29),
        ]
        for (error, value) in table {
            XCTAssertEqual(ClipboardMapping.error(forCode: error.errorCode), value, "\(error)")
        }
    }

    func testAnErrorNotInTheTableIsUnknown() {
        XCTAssertEqual(ClipboardMapping.error(forCode: nil), 4)
        XCTAssertEqual(ClipboardMapping.error(forCode: "CLIPBOARD_SOMETHING_NEW"), 4)
        XCTAssertEqual(ClipboardMapping.error(forCode: ""), 4)
    }

    func testTheValuesOfARejection() {
        XCTAssertEqual(ClipboardRejection.entry(.invalidParameter).value, 1)
        XCTAssertEqual(ClipboardRejection.entry(.notSupported).value, 3)
        XCTAssertEqual(ClipboardRejection.emptyItems.value, 7)
        XCTAssertEqual(ClipboardRejection.emptyPatterns.value, 12)
    }
}
