//
//  NotificationMappingTests.swift
//  IosLibraryCApiTests
//

import Foundation
import XCTest
@testable import IosLibrary
@testable import IosLibraryCApi

/// The trigger and the category of part 2, 6.3, compared with Swift values directly (12.1, "trigger" and
/// "0 で埋めた構造体"). The operations that take them are in NotificationOperationTests: no notification is added here.
final class NotificationMappingTests: ClipboardTestCase {
    private func assertRejected<Value>(_ expected: EntryError = .invalidParameter, _ name: String = "", file: StaticString = #filePath, line: UInt = #line,
                                       _ body: () throws(EntryError) -> Value) {
        do throws(EntryError) {
            XCTFail("accepted \(name): \(try body())", file: file, line: line)
        } catch {
            XCTAssertEqual(error, expected, name, file: file, line: line)
        }
    }

    private func sized<Value>(_ value: Value, _ set: (inout Value) -> Void = { _ in }) -> Value {
        var result = value
        withUnsafeMutableBytes(of: &result) { $0.storeBytes(of: UInt32(MemoryLayout<Value>.size), as: UInt32.self) }
        set(&result)
        return result
    }

    private func describe(_ trigger: NotificationTrigger?) -> String {
        switch trigger {
        case .none: return "nil"
        case .timeInterval(let seconds, let repeats): return "interval(\(seconds), \(repeats))"
        case .calendar(let components, let repeats):
            let parts = [components.year, components.month, components.day, components.hour, components.minute, components.second]
                .map { $0.map(String.init) ?? "-" }.joined(separator: ",")
            return "calendar(\(parts), \(repeats))"
        case .location(let identifier, let latitude, let longitude, let radius, let entry, let exit):
            return "location(\(identifier), \(latitude), \(longitude), \(radius), \(entry), \(exit))"
        @unknown default: return "unknown"
        }
    }

    private func mapped(_ raw: ntk_notification_trigger) -> String {
        var value = raw
        do throws(EntryError) {
            return describe(try NotificationMapping.trigger(&value))
        } catch {
            return "rejected \(error.rawValue)"
        }
    }

    private let trigger = ntk_notification_trigger()
    private let interval = Int32(NTK_NOTIFICATION_TRIGGER_TIME_INTERVAL)
    private let calendar = Int32(NTK_NOTIFICATION_TRIGGER_CALENDAR)
    private let location = Int32(NTK_NOTIFICATION_TRIGGER_LOCATION)

    // MARK: - Trigger

    func testNoTriggerIsNil() throws {
        XCTAssertNil(try NotificationMapping.trigger(nil))
    }

    /// A zero-filled trigger is a time interval of 0, which is rejected (P2-26).
    func testAZeroFilledTriggerIsRejected() {
        XCTAssertEqual(mapped(sized(trigger)), "rejected 1")
    }

    /// `isValid`'s branches through C, and the finite rule of the C input (M8: infinity would stay pending).
    func testTheTimeInterval() {
        func run(_ seconds: Double, _ repeats: Int32) -> String {
            mapped(sized(trigger) { $0.kind = interval; $0.interval_seconds = seconds; $0.repeats = repeats; $0.location_identifier = unreadable() })
        }
        XCTAssertEqual(run(0.1, 0), "interval(0.1, false)")
        XCTAssertEqual(run(60, 1), "interval(60.0, true)")
        XCTAssertEqual(run(1e9, 1), "interval(1000000000.0, true)")
        for (seconds, repeats) in [(0.0, 0), (-1.0, 0), (59.9, 1), (Double.nan, 0), (.infinity, 0), (-.infinity, 0), (.infinity, 1)] as [(Double, Int32)] {
            XCTAssertEqual(run(seconds, repeats), "rejected 1", "\(seconds) \(repeats)")
        }
    }

    /// Only the fields whose bit is set: 0 o'clock is not "no hour".
    func testTheCalendar() {
        let hour = UInt32(NTK_NOTIFICATION_CALENDAR_HOUR)
        let minute = UInt32(NTK_NOTIFICATION_CALENDAR_MINUTE)
        let all: UInt32 = 0b111111
        XCTAssertEqual(mapped(sized(trigger) { $0.kind = calendar; $0.calendar_fields = hour | minute; $0.hour = 0; $0.minute = 30; $0.year = 2030; $0.repeats = 1 }),
                       "calendar(-,-,-,0,30,-, true)")
        XCTAssertEqual(mapped(sized(trigger) { $0.kind = calendar; $0.calendar_fields = all; $0.year = 2030; $0.month = 1; $0.day = 2; $0.hour = 3; $0.minute = 4; $0.second = 5 }),
                       "calendar(2030,1,2,3,4,5, false)")
        for fields: UInt32 in [0, 1 << 6, all | 1 << 31] {
            XCTAssertEqual(mapped(sized(trigger) { $0.kind = calendar; $0.calendar_fields = fields }), "rejected 1", "\(fields)")
        }
    }

    private func place(_ set: (inout ntk_notification_trigger) -> Void = { _ in }) -> ntk_notification_trigger {
        sized(trigger) {
            $0.kind = location
            $0.location_identifier = c("home")
            $0.latitude = 35.0
            $0.longitude = 139.0
            $0.radius = 100
            set(&$0)
        }
    }

    /// E-9: the default notifies on entry only.
    func testTheLocation() {
        XCTAssertEqual(mapped(place()), "location(home, 35.0, 139.0, 100.0, true, false)")
        XCTAssertEqual(mapped(place { $0.not_notify_on_entry = 1; $0.notify_on_exit = 1 }), "location(home, 35.0, 139.0, 100.0, false, true)")
        XCTAssertEqual(mapped(place { $0.notify_on_exit = 1 }), "location(home, 35.0, 139.0, 100.0, true, true)")
        XCTAssertEqual(mapped(place { $0.latitude = 90; $0.longitude = -180 }), "location(home, 90.0, -180.0, 100.0, true, false)")
        XCTAssertEqual(mapped(place { $0.latitude = -90; $0.longitude = 180 }), "location(home, -90.0, 180.0, 100.0, true, false)")
    }

    func testTheLocationRejects() {
        let cases: [(String, (inout ntk_notification_trigger) -> Void)] = [
            ("NULL identifier", { $0.location_identifier = nil }), ("empty identifier", { $0.location_identifier = self.c("") }),
            ("identifier not UTF-8", { $0.location_identifier = self.raw([0xFF]) }),
            ("latitude above", { $0.latitude = 90.000001 }), ("latitude below", { $0.latitude = -90.000001 }),
            ("longitude above", { $0.longitude = 180.000001 }), ("longitude below", { $0.longitude = -180.000001 }),
            ("radius 0", { $0.radius = 0 }), ("radius below", { $0.radius = -1 }),
            ("latitude NaN", { $0.latitude = .nan }), ("longitude infinite", { $0.longitude = .infinity }), ("radius infinite", { $0.radius = .infinity }),
            ("radius NaN", { $0.radius = .nan }), ("neither way", { $0.not_notify_on_entry = 1 }),
        ]
        for (name, change) in cases {
            XCTAssertEqual(mapped(place(change)), "rejected 1", name)
        }
    }

    func testATriggerKindOutOfRange() {
        for kind: Int32 in [-1, 3] {
            XCTAssertEqual(mapped(place { $0.kind = kind }), "rejected 1")
        }
    }

    func testTheStructRulesOfTheTrigger() {
        var value = place { $0.reserved0 = 1 }
        assertRejected { () throws(EntryError) in try NotificationMapping.trigger(&value) }
        value = place { $0.reserved1 = 1 }
        assertRejected { () throws(EntryError) in try NotificationMapping.trigger(&value) }
        value = place { $0.struct_size -= 8 }
        assertRejected { () throws(EntryError) in try NotificationMapping.trigger(&value) }
        value = place { $0.struct_size = 4097 }
        assertRejected { () throws(EntryError) in try NotificationMapping.trigger(&value) }
        assertStructTail(place()) { (p) throws(EntryError) in _ = try NotificationMapping.trigger(p) }
    }

    /// The part beyond the size known here: all 0 is fine, anything else is NOT_SUPPORTED.
    private func assertStructTail<Value>(_ value: Value, file: StaticString = #filePath, line: UInt = #line, _ read: (UnsafePointer<Value>) throws(EntryError) -> Void) {
        let size = MemoryLayout<Value>.size
        let memory = UnsafeMutableRawPointer.allocate(byteCount: size + 8, alignment: 8)
        defer { memory.deallocate() }
        memory.initializeMemory(as: UInt8.self, repeating: 0, count: size + 8)
        withUnsafeBytes(of: value) { memory.copyMemory(from: $0.baseAddress!, byteCount: size) }
        memory.storeBytes(of: UInt32(size + 8), as: UInt32.self)
        let pointer = UnsafePointer(memory.assumingMemoryBound(to: Value.self))
        do throws(EntryError) { try read(pointer) } catch { XCTFail("rejected with a zero tail: \(error)", file: file, line: line) }
        memory.storeBytes(of: UInt8(1), toByteOffset: size + 7, as: UInt8.self)
        assertRejected(.notSupported, file: file, line: line) { () throws(EntryError) in try read(pointer) }
    }

    // MARK: - Category

    private func action(_ identifier: String, options: UInt32 = 0) -> ntk_notification_action {
        sized(ntk_notification_action()) { $0.identifier = c(identifier); $0.title = c("T \(identifier)"); $0.options = options }
    }

    private func textInput(_ identifier: String) -> ntk_notification_text_input_action {
        sized(ntk_notification_text_input_action()) { $0.identifier = c(identifier); $0.title = c("t"); $0.button_title = c("b"); $0.placeholder = c("") }
    }

    private func category(_ set: (inout ntk_notification_category) -> Void = { _ in }) -> ntk_notification_category {
        sized(ntk_notification_category()) { $0.identifier = c("cat"); set(&$0) }
    }

    private func mapped(_ raw: ntk_notification_category) -> NotificationCategory? {
        var value = raw
        do throws(EntryError) { return try NotificationMapping.category(&value) } catch { return nil }
    }

    private func rejection(_ raw: ntk_notification_category) -> EntryError? {
        var value = raw
        do throws(EntryError) { _ = try NotificationMapping.category(&value); return nil } catch { return error }
    }

    func testACategory() throws {
        let actions = array([action("a", options: 0b101), action("b")])
        let inputs = array([textInput("t")])
        let result = try XCTUnwrap(mapped(category {
            $0.options = 0b1011
            $0.actions = actions
            $0.action_count = 2
            $0.text_input_actions = inputs
            $0.text_input_action_count = 1
        }))
        XCTAssertEqual(result.identifier, "cat")
        XCTAssertEqual(result.options, NotificationCategoryOptions(rawValue: 0b1011))
        XCTAssertEqual(result.options.contains(.customDismissAction), true)
        XCTAssertEqual(result.actions.map(\.identifier), ["a", "b"])
        XCTAssertEqual(result.actions.map(\.title), ["T a", "T b"])
        XCTAssertEqual(result.actions[0].options, [.authenticationRequired, .foreground])
        XCTAssertNil(result.actions[0].sfSymbolName)
        XCTAssertEqual(result.textInputActions.map(\.identifier), ["t"])
        XCTAssertEqual(result.textInputActions[0].buttonTitle, "b")
        XCTAssertEqual(result.textInputActions[0].textInputPlaceholder, "", "an empty placeholder is allowed")
    }

    /// The bits are the library's `rawValue`s.
    func testTheBitsAreTheLibrarys() {
        XCTAssertEqual(UInt(NTK_NOTIFICATION_ACTION_AUTHENTICATION_REQUIRED), NotificationActionOptions.authenticationRequired.rawValue)
        XCTAssertEqual(UInt(NTK_NOTIFICATION_ACTION_DESTRUCTIVE), NotificationActionOptions.destructive.rawValue)
        XCTAssertEqual(UInt(NTK_NOTIFICATION_ACTION_FOREGROUND), NotificationActionOptions.foreground.rawValue)
        XCTAssertEqual(UInt(NTK_NOTIFICATION_CATEGORY_CUSTOM_DISMISS_ACTION), NotificationCategoryOptions.customDismissAction.rawValue)
        XCTAssertEqual(UInt(NTK_NOTIFICATION_CATEGORY_ALLOW_IN_CAR_PLAY), NotificationCategoryOptions.allowInCarPlay.rawValue)
        XCTAssertEqual(UInt(NTK_NOTIFICATION_CATEGORY_HIDDEN_PREVIEWS_SHOW_TITLE), NotificationCategoryOptions.hiddenPreviewsShowTitle.rawValue)
        XCTAssertEqual(UInt(NTK_NOTIFICATION_CATEGORY_ALLOW_ANNOUNCEMENT), 1 << 3)
    }

    /// The Swift defaults: no action is allowed, with NULL.
    func testAZeroFilledCategoryNeedsOnlyItsIdentifier() throws {
        let result = try XCTUnwrap(mapped(category()))
        XCTAssertTrue(result.actions.isEmpty)
        XCTAssertTrue(result.textInputActions.isEmpty)
        XCTAssertEqual(result.options, [])
        XCTAssertNil(mapped(sized(ntk_notification_category())), "the identifier is required")
    }

    func testTheCategoryRejects() {
        let unreadableActions = array([action("x")])
        let cases: [(String, (inout ntk_notification_category) -> Void)] = [
            ("empty identifier", { $0.identifier = self.c("") }), ("identifier not UTF-8", { $0.identifier = self.raw([0xFF]) }),
            ("unknown category bit", { $0.options = 1 << 4 }),
            ("NULL actions", { $0.action_count = 1 }), ("NULL text inputs", { $0.text_input_action_count = 1 }),
            ("unknown action bit", { $0.actions = self.array([self.action("a", options: 1 << 3)]); $0.action_count = 1 }),
            ("empty action identifier", { $0.actions = self.array([self.action("")]); $0.action_count = 1 }),
            ("NULL action title", { var a = self.action("a"); a.title = nil; $0.actions = self.array([a]); $0.action_count = 1 }),
            ("action reserved0", { var a = self.action("a"); a.reserved0 = 1; $0.actions = self.array([a]); $0.action_count = 1 }),
            ("action reserved1", { var a = self.action("a"); a.reserved1 = 1; $0.actions = self.array([a]); $0.action_count = 1 }),
            ("symbol not UTF-8", { var a = self.action("a"); a.sf_symbol_name = self.raw([0xFF]); $0.actions = self.array([a]); $0.action_count = 1 }),
            ("NULL text input title", { var t = self.textInput("t"); t.title = nil; $0.text_input_actions = self.array([t]); $0.text_input_action_count = 1 }),
            ("text inputs of two sizes", { var t = self.textInput("u"); t.struct_size -= 8; $0.text_input_actions = self.array([self.textInput("t"), t]); $0.text_input_action_count = 2 }),
            ("actions of two sizes", { var a = self.action("b"); a.struct_size -= 8; $0.actions = self.array([self.action("a"), a]); $0.action_count = 2 }),
            ("NULL button title", { var t = self.textInput("t"); t.button_title = nil; $0.text_input_actions = self.array([t]); $0.text_input_action_count = 1 }),
            ("NULL placeholder", { var t = self.textInput("t"); t.placeholder = nil; $0.text_input_actions = self.array([t]); $0.text_input_action_count = 1 }),
            ("text input reserved0", { var t = self.textInput("t"); t.reserved0 = 1; $0.text_input_actions = self.array([t]); $0.text_input_action_count = 1 }),
            ("empty text input identifier", { $0.text_input_actions = self.array([self.textInput("")]); $0.text_input_action_count = 1 }),
            ("a count that overflows", { $0.actions = unreadableActions; $0.action_count = 1 << 61 }),
            ("category reserved0", { $0.reserved0 = 1 }), ("category reserved1", { $0.reserved1 = 1 }),
            ("small struct_size", { $0.struct_size -= 8 }),
        ]
        for (name, change) in cases {
            XCTAssertEqual(rejection(category(change)), .invalidParameter, name)
        }
        assertRejected { () throws(EntryError) in try NotificationMapping.category(nil) }
        assertStructTail(category()) { (p) throws(EntryError) in _ = try NotificationMapping.category(p) }
    }

    /// The action with a symbol, and an empty title (allowed).
    func testAnActionWithASymbolAndAnEmptyTitle() throws {
        var a = action("a")
        a.title = c("")
        a.sf_symbol_name = c("star")
        let actions = array([a])
        let result = try XCTUnwrap(mapped(category { $0.actions = actions; $0.action_count = 1 }))
        XCTAssertEqual(result.actions[0].title, "")
        XCTAssertEqual(result.actions[0].sfSymbolName, "star")
    }
}
