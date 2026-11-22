//
//  DialogMappingTests.swift
//  IosLibraryCApiTests
//

import IosLibrary
import XCTest
@testable import IosLibraryCApi

/// The conversions of part 2, 6.2 and P2-22, compared with Swift values directly. No dialog is shown here.
final class DialogMappingTests: ClipboardTestCase {
    private func assertRejected<Value>(_ expected: EntryError = .invalidParameter, file: StaticString = #filePath, line: UInt = #line,
                                       _ body: () throws(EntryError) -> Value) {
        do throws(EntryError) {
            XCTFail("accepted: \(try body())", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, file: file, line: line)
        }
    }

    private func sized<Request>(_ request: Request, _ set: (inout Request) -> Void = { _ in }) -> Request {
        var value = request
        set(&value)
        withUnsafeMutableBytes(of: &value) { $0.storeBytes(of: UInt32(MemoryLayout<Request>.size), as: UInt32.self) }
        return value
    }

    private let alert = ntk_dialog_alert_request()
    private let confirm = ntk_dialog_confirm_request()
    private let destructive = ntk_dialog_destructive_request()
    private let sheet = ntk_dialog_action_sheet_request()
    private let textInput = ntk_dialog_text_input_request()
    private let login = ntk_dialog_login_request()

    // MARK: - Zero-filled: the library's defaults (P2-22)

    func testZeroFilledIsTheDefaultOfTheLibrary() throws {
        var a = sized(alert)
        XCTAssertEqual(try DialogMapping.alert(&a), .alert(title: nil, message: nil))
        var c = sized(confirm)
        XCTAssertEqual(try DialogMapping.confirm(&c), .confirm(title: nil, message: nil))
        var d = sized(destructive)
        XCTAssertEqual(try DialogMapping.destructive(&d), .destructive(title: nil, message: nil))
        var s = sized(sheet)
        XCTAssertEqual(try DialogMapping.actionSheet(&s), .actionSheet(title: nil, message: nil, options: []))
        var t = sized(textInput)
        XCTAssertEqual(try DialogMapping.textInput(&t), .textInput(title: nil, message: nil))
        var l = sized(login)
        XCTAssertEqual(try DialogMapping.login(&l), .login(title: nil, message: nil))
    }

    // MARK: - Every field

    func testAnAlert() throws {
        var value = sized(alert) { $0.title = c("t"); $0.message = c("m"); $0.button_text = c("b") }
        XCTAssertEqual(try DialogMapping.alert(&value), .alert(title: "t", message: "m", buttonTitle: "b"))
    }

    func testAConfirm() throws {
        var value = sized(confirm) { $0.title = c("t"); $0.message = c("m"); $0.confirm_text = c("y"); $0.cancel_text = c("n") }
        XCTAssertEqual(try DialogMapping.confirm(&value), .confirm(title: "t", message: "m", confirmTitle: "y", cancelTitle: "n"))
    }

    func testADestructive() throws {
        var value = sized(destructive) { $0.title = c("t"); $0.message = c("m"); $0.destructive_text = c("d"); $0.cancel_text = c("n") }
        XCTAssertEqual(try DialogMapping.destructive(&value), .destructive(title: "t", message: "m", destructiveTitle: "d", cancelTitle: "n"))
    }

    func testAnActionSheet() throws {
        let options = array([c("a"), c("\u{65E5}")] as [UnsafePointer<CChar>?])
        var value = sized(sheet) { $0.title = c("t"); $0.message = c("m"); $0.options = options; $0.option_count = 2; $0.cancel_text = c("n") }
        XCTAssertEqual(try DialogMapping.actionSheet(&value), .actionSheet(title: "t", message: "m", options: ["a", "\u{65E5}"], cancelTitle: "n"))
    }

    func testATextInput() throws {
        var value = sized(textInput) { $0.title = c("t"); $0.message = c("m"); $0.placeholder = c("p"); $0.confirm_text = c("y"); $0.cancel_text = c("n"); $0.confirm_disabled_when_empty = 1 }
        XCTAssertEqual(try DialogMapping.textInput(&value), .textInput(title: "t", message: "m", placeholder: "p", confirmTitle: "y", cancelTitle: "n", enableConfirmWhenEmpty: false))
    }

    func testALogin() throws {
        var value = sized(login) { $0.title = c("t"); $0.message = c("m"); $0.username_placeholder = c("u"); $0.password_placeholder = c("p"); $0.login_text = c("l"); $0.cancel_text = c("n"); $0.login_disabled_when_empty = -1 }
        XCTAssertEqual(try DialogMapping.login(&value), .login(title: "t", message: "m", usernamePlaceholder: "u", passwordPlaceholder: "p", loginTitle: "l", cancelTitle: "n", enableLoginWhenEmpty: false))
    }

    /// An empty text is a text: not the default, and not "none" (E-15).
    func testAnEmptyTextIsThere() throws {
        var value = sized(alert) { $0.title = c(""); $0.button_text = c("") }
        XCTAssertEqual(try DialogMapping.alert(&value), .alert(title: "", message: nil, buttonTitle: ""))
    }

    // MARK: - Options

    func testNoOptionIsAllowedAndNullThen() throws {
        var value = sized(sheet)
        XCTAssertEqual(try DialogMapping.actionSheet(&value), .actionSheet(title: nil, message: nil, options: []))
        value.options = array([Optional(unreadable(CChar.self))])
        XCTAssertEqual(try DialogMapping.actionSheet(&value), .actionSheet(title: nil, message: nil, options: []), "count 0 reads none")
    }

    func testOptionsReject() {
        var value = sized(sheet) { $0.option_count = 1 }
        assertRejected { () throws(EntryError) in try DialogMapping.actionSheet(&value) }
        value.options = array([c("a"), nil] as [UnsafePointer<CChar>?])
        value.option_count = 2
        assertRejected { () throws(EntryError) in try DialogMapping.actionSheet(&value) }
        value.options = array([c("a"), raw([0xFF])] as [UnsafePointer<CChar>?])
        assertRejected { () throws(EntryError) in try DialogMapping.actionSheet(&value) }
        value.option_count = -1
        assertRejected { () throws(EntryError) in try DialogMapping.actionSheet(&value) }
        // A count whose size overflows: the element stops the process when it is read.
        value.options = array([Optional(unreadable(CChar.self))])
        value.option_count = 1 << 61
        assertRejected { () throws(EntryError) in try DialogMapping.actionSheet(&value) }
    }

    // MARK: - Every struct: NULL, reserved fields, struct_size

    private func assertTheStructRules<Request>(_ request: Request, reserved: [WritableKeyPath<Request, UInt32>], read: (UnsafePointer<Request>?) throws(EntryError) -> DialogRequest,
                                               file: StaticString = #filePath, line: UInt = #line) throws {
        assertRejected(file: file, line: line) { () throws(EntryError) in try read(nil) }
        for field in reserved {
            var value = request
            value[keyPath: field] = 1
            assertRejected(file: file, line: line) { () throws(EntryError) in try read(&value) }
        }
        let size = MemoryLayout<Request>.size
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size + 8, alignment: 8)
        defer { memory.deallocate() }
        func prepared(structSize: Int) -> UnsafePointer<Request> {
            memory.initializeMemory(as: UInt8.self, repeating: 0, count: size + 8)
            withUnsafeBytes(of: request) { memory.copyMemory(from: $0.baseAddress!, byteCount: size) }
            memory.storeBytes(of: UInt32(structSize), as: UInt32.self)
            return UnsafePointer(memory.assumingMemoryBound(to: Request.self))
        }
        let small = prepared(structSize: size - 8)
        assertRejected(file: file, line: line) { () throws(EntryError) in try read(small) }
        let large = prepared(structSize: 4097)
        assertRejected(file: file, line: line) { () throws(EntryError) in try read(large) }
        let longer = prepared(structSize: size + 8)
        XCTAssertNoThrow(try read(longer), "the unknown part is 0", file: file, line: line)
        memory.storeBytes(of: UInt8(1), toByteOffset: size + 7, as: UInt8.self)
        assertRejected(.notSupported, file: file, line: line) { () throws(EntryError) in try read(longer) }
    }

    func testTheStructRulesOfEachRequest() throws {
        try assertTheStructRules(sized(alert), reserved: [\.reserved0]) { (p) throws(EntryError) in try DialogMapping.alert(p) }
        try assertTheStructRules(sized(confirm), reserved: [\.reserved0]) { (p) throws(EntryError) in try DialogMapping.confirm(p) }
        try assertTheStructRules(sized(destructive), reserved: [\.reserved0]) { (p) throws(EntryError) in try DialogMapping.destructive(p) }
        try assertTheStructRules(sized(sheet), reserved: [\.reserved0]) { (p) throws(EntryError) in try DialogMapping.actionSheet(p) }
        try assertTheStructRules(sized(textInput), reserved: [\.reserved0, \.reserved1]) { (p) throws(EntryError) in try DialogMapping.textInput(p) }
        try assertTheStructRules(sized(login), reserved: [\.reserved0, \.reserved1]) { (p) throws(EntryError) in try DialogMapping.login(p) }
    }

    /// Each text field of each struct, with each sequence that is not UTF-8.
    private func assertEachText<Request>(_ request: Request, _ fields: [WritableKeyPath<Request, UnsafePointer<CChar>?>], read: (UnsafePointer<Request>?) throws(EntryError) -> DialogRequest,
                                         file: StaticString = #filePath, line: UInt = #line) {
        for field in fields {
            for bytes in invalidUTF8 {
                var value = request
                value[keyPath: field] = raw(bytes)
                assertRejected(file: file, line: line) { () throws(EntryError) in try read(&value) }
            }
        }
    }

    func testEveryTextMustBeUTF8() {
        assertEachText(sized(alert), [\.title, \.message, \.button_text]) { (p) throws(EntryError) in try DialogMapping.alert(p) }
        assertEachText(sized(confirm), [\.title, \.message, \.confirm_text, \.cancel_text]) { (p) throws(EntryError) in try DialogMapping.confirm(p) }
        assertEachText(sized(destructive), [\.title, \.message, \.destructive_text, \.cancel_text]) { (p) throws(EntryError) in try DialogMapping.destructive(p) }
        assertEachText(sized(sheet), [\.title, \.message, \.cancel_text]) { (p) throws(EntryError) in try DialogMapping.actionSheet(p) }
        assertEachText(sized(textInput), [\.title, \.message, \.placeholder, \.confirm_text, \.cancel_text]) { (p) throws(EntryError) in try DialogMapping.textInput(p) }
        assertEachText(sized(login), [\.title, \.message, \.username_placeholder, \.password_placeholder, \.login_text, \.cancel_text]) { (p) throws(EntryError) in try DialogMapping.login(p) }
    }

    // MARK: - The answer

    func testEachButton() {
        XCTAssertEqual(DialogMapping.result(of: DialogAnswer(button: .primary, title: "b", input: nil)),
                       DialogResultValue(button: 0, optionIndex: -1, buttonText: "b", text: nil, username: nil, password: nil))
        XCTAssertEqual(DialogMapping.result(of: DialogAnswer(button: .cancel, title: "b", input: nil)),
                       DialogResultValue(button: 1, optionIndex: -1, buttonText: "b", text: nil, username: nil, password: nil))
        XCTAssertEqual(DialogMapping.result(of: DialogAnswer(button: .destructive, title: nil, input: nil)),
                       DialogResultValue(button: 2, optionIndex: -1, buttonText: nil, text: nil, username: nil, password: nil))
        XCTAssertEqual(DialogMapping.result(of: DialogAnswer(button: .option(index: 0), title: "b", input: nil)),
                       DialogResultValue(button: 3, optionIndex: 0, buttonText: "b", text: nil, username: nil, password: nil))
        XCTAssertEqual(DialogMapping.result(of: DialogAnswer(button: .option(index: 5), title: "b", input: nil))?.optionIndex, 5)
    }

    func testEachInput() {
        XCTAssertEqual(DialogMapping.result(of: DialogAnswer(button: .primary, title: "b", input: .text("x"))),
                       DialogResultValue(button: 0, optionIndex: -1, buttonText: "b", text: "x", username: nil, password: nil))
        XCTAssertEqual(DialogMapping.result(of: DialogAnswer(button: .primary, title: "b", input: .login(username: "u", password: "p"))),
                       DialogResultValue(button: 0, optionIndex: -1, buttonText: "b", text: nil, username: "u", password: "p"))
    }

    /// Part 2, 11.1: every case, to the number written out.
    func testEveryErrorOfTheLibrary() {
        let table: [(DialogError, Int32)] = [(.invalidRequest, 1), (.canceled, 6), (.dismissedBySystem, 7), (.notForeground, 8), (.presentationFailed, 10)]
        for (error, value) in table {
            XCTAssertEqual(DialogMapping.error(for: error), value, "\(error)")
        }
    }
}
