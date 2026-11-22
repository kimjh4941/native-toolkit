//
//  StructReaderTests.swift
//  IosLibraryCApiTests
//

import Darwin
import Foundation
import XCTest
@testable import IosLibraryCApi

/// `ntk_clipboard_scope` with a field added, as a later version of the library would have it, or a
/// newer header would give it to this library.
private struct GrownScope {
    var struct_size: UInt32 = 0
    var reserved0: UInt32 = 0
    var kind: Int32 = 0
    var reserved1: UInt32 = 0
    var name: UnsafePointer<CChar>?
    var added: UInt64 = 0
}

private let scopeSize = MemoryLayout<ntk_clipboard_scope>.size
private let actionSize = MemoryLayout<ntk_notification_action>.size

/// Memory whose last byte is followed by an unmapped page, so that reading past `count` bytes stops the
/// process. That is how the tests prove the reads are bounded.
private final class GuardedMemory {
    private let mapping: UnsafeMutableRawPointer
    private let mappingSize: Int
    let start: UnsafeMutableRawPointer

    init(count: Int) throws {
        let page = Int(getpagesize())
        let pages = (count + page - 1) / page + 1
        mappingSize = pages * page
        let result = mmap(nil, mappingSize, PROT_READ | PROT_WRITE, MAP_ANON | MAP_PRIVATE, -1, 0)
        guard let result, result != UnsafeMutableRawPointer(bitPattern: -1) else { throw POSIXError(.ENOMEM) }
        mapping = result
        guard mprotect(mapping + (pages - 1) * page, page, PROT_NONE) == 0 else { throw POSIXError(.EACCES) }
        start = mapping + (pages - 1) * page - count
        start.initializeMemory(as: UInt8.self, repeating: 0, count: count)
    }

    deinit {
        munmap(mapping, mappingSize)
    }

    func pointer<T>(as type: T.Type = T.self) -> UnsafePointer<T> {
        UnsafePointer(start.assumingMemoryBound(to: T.self))
    }

    func setUInt32(_ value: UInt32, at offset: Int) {
        (start + offset).storeBytes(of: value, as: UInt32.self)
    }

    func setByte(_ value: UInt8, at offset: Int) {
        (start + offset).storeBytes(of: value, as: UInt8.self)
    }
}

final class StructReaderTests: XCTestCase {

    private func scope(size: Int, reserved0: UInt32 = 0, reserved1: UInt32 = 0, kind: Int32 = 2) throws -> GuardedMemory {
        let memory = try GuardedMemory(count: size)
        memory.setUInt32(UInt32(size), at: 0)
        memory.setUInt32(reserved0, at: 4)
        memory.setUInt32(UInt32(bitPattern: kind), at: 8)
        memory.setUInt32(reserved1, at: 12)
        return memory
    }

    private func read(_ memory: GuardedMemory) throws(EntryError) -> ntk_clipboard_scope {
        try StructReader.read(memory.pointer(as: ntk_clipboard_scope.self), reserved: [\.reserved1])
    }

    private func assertFails(_ expected: EntryError, line: UInt = #line, _ body: () throws(EntryError) -> Void) {
        do {
            try body()
            XCTFail("it was accepted", line: line)
        } catch {
            XCTAssertEqual(error, expected, line: line)
        }
    }

    func testAStructOfExactlyItsSizeIsCopied() throws {
        let name = strdup("name")
        defer { free(name) }
        var value = ntk_clipboard_scope()
        value.struct_size = UInt32(scopeSize)
        value.kind = 2
        value.name = UnsafePointer(name)

        var copy = try withUnsafePointer(to: &value) { try StructReader.read($0, reserved: []) }
        value.kind = 1

        XCTAssertEqual(copy.struct_size, UInt32(scopeSize))
        XCTAssertEqual(copy.kind, 2)
        XCTAssertEqual(copy.name, UnsafePointer(name))
        copy.kind = 3
        XCTAssertEqual(value.kind, 1)
    }

    func testNull() throws {
        assertFails(.invalidParameter) { () throws(EntryError) in
            let _: ntk_clipboard_scope = try StructReader.read(nil, reserved: [])
        }
        let absent: ntk_clipboard_scope? = try StructReader.readIfPresent(nil, reserved: [])
        XCTAssertNil(absent)
    }

    func testReadIfPresentAppliesTheRulesToWhatIsThere() throws {
        let good = try scope(size: scopeSize, kind: 2)
        XCTAssertEqual(try StructReader.readIfPresent(good.pointer(as: ntk_clipboard_scope.self), reserved: [\.reserved1])?.kind, 2)
        let bad = try scope(size: scopeSize, reserved1: 1)
        assertFails(.invalidParameter) { () throws(EntryError) in
            _ = try StructReader.readIfPresent(bad.pointer(as: ntk_clipboard_scope.self), reserved: [\.reserved1])
        }
        let tooSmall = try scope(size: scopeSize - 8)
        assertFails(.invalidParameter) { () throws(EntryError) in
            _ = try StructReader.readIfPresent(tooSmall.pointer(as: ntk_clipboard_scope.self), reserved: [])
        }
    }

    // MARK: - Rule 1: reserved

    func testReserved0IsRejectedForEveryBit() throws {
        for value: UInt32 in [1, 0x0000_0100, 0x8000_0000, 0xFFFF_FFFF] {
            let memory = try scope(size: scopeSize, reserved0: value)
            assertFails(.invalidParameter) { () throws(EntryError) in _ = try read(memory) }
        }
    }

    func testAnotherReservedFieldIsRejectedWhenNamed() throws {
        let memory = try scope(size: scopeSize, reserved1: 1)
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try read(memory) }
        // The reader knows only the fields it is told about.
        XCTAssertEqual(try StructReader.read(memory.pointer(as: ntk_clipboard_scope.self), reserved: []).reserved1, 1)
    }

    func testEveryNamedReservedFieldCounts() throws {
        struct TwoReserved {
            var struct_size: UInt32 = 0
            var reserved0: UInt32 = 0
            var value: UInt64 = 0
            var reserved1: UInt32 = 0
            var reserved2: UInt32 = 0
        }
        for offset in [16, 20] {
            let memory = try GuardedMemory(count: 24)
            memory.setUInt32(24, at: 0)
            memory.setUInt32(1, at: offset)
            assertFails(.invalidParameter) { () throws(EntryError) in
                _ = try StructReader.read(memory.pointer(as: TwoReserved.self), reserved: [\.reserved1, \.reserved2])
            }
        }
    }

    /// A reserved field a shorter struct does not reach is 0 (rule 3): it does not fail, and it is not read.
    func testAReservedFieldBeyondTheCallersStructIsNotRead() throws {
        struct Grown {
            var struct_size: UInt32 = 0
            var reserved0: UInt32 = 0
            var value: UInt64 = 0
            var reserved1: UInt32 = 0
            var reserved2: UInt32 = 0
        }
        let memory = try GuardedMemory(count: 16)
        memory.setUInt32(16, at: 0)
        memory.setUInt32(7, at: 8)

        let read = try StructReader.read(memory.pointer(as: Grown.self), minimumSize: 16, reserved: [\.reserved1, \.reserved2])

        XCTAssertEqual(read.value, 7)
        XCTAssertEqual(read.reserved1, 0)
    }

    // MARK: - Rule 2: the minimum and the maximum

    func testBelowTheMinimum() throws {
        for size in [0, 1, 4, 7, 8, scopeSize - 1] {
            let memory = try GuardedMemory(count: max(size, 4))
            memory.setUInt32(UInt32(size), at: 0)
            assertFails(.invalidParameter) { () throws(EntryError) in _ = try read(memory) }
        }
    }

    func testAboveTheMaximum() throws {
        let memory = try GuardedMemory(count: 4)
        for size: UInt32 in [4097, 0x7FFF_FFFF, 0x8000_0000, 0xFFFF_FFFF] {
            memory.setUInt32(size, at: 0)
            // Only 4 bytes are there: nothing but struct_size can have been read.
            assertFails(.invalidParameter) { () throws(EntryError) in _ = try read(memory) }
        }
    }

    func testTheMaximumItselfIsAccepted() throws {
        let memory = try scope(size: 4096)
        XCTAssertEqual(try read(memory).kind, 2)
    }

    /// A value below the minimum says the struct may end there: reserved0 is not looked at.
    func testASmallSizeIsRejectedBeforeAnythingElseIsRead() throws {
        let memory = try GuardedMemory(count: 4)
        memory.setUInt32(4, at: 0)
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try read(memory) }
    }

    // MARK: - Rule 3: only what struct_size covers

    func testNothingPastStructSizeIsRead() throws {
        // GuardedMemory stops the process on a read past the struct, for each of these sizes.
        for size in [scopeSize, scopeSize + 1, scopeSize + 8, 4095] {
            let memory = try scope(size: size)
            XCTAssertEqual(try read(memory).kind, 2, "size \(size)")
        }
    }

    func testAFieldTheCallerDoesNotHaveIsZero() throws {
        let memory = try scope(size: scopeSize, kind: 5)
        let grown = try StructReader.read(memory.pointer(as: GrownScope.self), minimumSize: scopeSize, reserved: [\.reserved1])
        XCTAssertEqual(grown.kind, 5)
        XCTAssertEqual(grown.added, 0)

        let full = try scope(size: MemoryLayout<GrownScope>.size)
        (full.start + 24).storeBytes(of: UInt64(9), as: UInt64.self)
        XCTAssertEqual(try StructReader.read(full.pointer(as: GrownScope.self), minimumSize: scopeSize, reserved: []).added, 9)
    }

    /// A `struct_size` that covers a field in part: the field stays 0, whatever those bytes are (rule 3).
    func testAFieldCoveredInPartIsZero() throws {
        for size in [25, 28, 31] {
            let memory = try scope(size: size, kind: 5)
            for offset in scopeSize..<size { memory.setByte(0xAB, at: offset) }

            let grown = try StructReader.read(memory.pointer(as: GrownScope.self), minimumSize: scopeSize, reserved: [\.reserved1])

            XCTAssertEqual(grown.kind, 5, "size \(size)")
            XCTAssertEqual(grown.added, 0, "size \(size)")
        }
    }

    /// The minimum is that of 2.0.0: without saying so, a grown type's own size is the minimum.
    func testTheMinimumIsThatOfTheGivenVersion() throws {
        let memory = try scope(size: scopeSize)
        assertFails(.invalidParameter) { () throws(EntryError) in
            _ = try StructReader.read(memory.pointer(as: GrownScope.self), reserved: [])
        }
    }

    // MARK: - Rule 4: what is unknown

    func testAnUnknownPartOfZerosIsAccepted() throws {
        for size in [scopeSize + 1, scopeSize + 8, 256, 4096] {
            XCTAssertEqual(try read(scope(size: size)).kind, 2, "size \(size)")
        }
    }

    /// The prototype accepted exactly this (part 1, 1.1).
    func testATailFilledWith0xABIsNotSupported() throws {
        let memory = try scope(size: scopeSize + 16)
        for offset in scopeSize..<(scopeSize + 16) { memory.setByte(0xAB, at: offset) }
        assertFails(.notSupported) { () throws(EntryError) in _ = try read(memory) }
    }

    func testEveryByteOfTheUnknownPartCounts() throws {
        let size = scopeSize + 8
        for offset in scopeSize..<size {
            let memory = try scope(size: size)
            memory.setByte(1, at: offset)
            assertFails(.notSupported) { () throws(EntryError) in _ = try read(memory) }
        }
        let farEnd = try scope(size: 4096)
        farEnd.setByte(1, at: 4095)
        assertFails(.notSupported) { () throws(EntryError) in _ = try read(farEnd) }
    }

    func testAByteOutsideStructSizeDoesNotCount() throws {
        let memory = try scope(size: scopeSize + 8)
        memory.setUInt32(UInt32(scopeSize), at: 0)
        memory.setByte(1, at: scopeSize)
        XCTAssertEqual(try read(memory).kind, 2)
    }

    func testReservedComesBeforeTheUnknownPart() throws {
        let memory = try scope(size: scopeSize + 8, reserved1: 1)
        memory.setByte(1, at: scopeSize)
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try read(memory) }
    }

    // MARK: - Arrays (P2-5)

    private func actionArray(count: Int, step: Int, set: (GuardedMemory, Int) -> Void = { _, _ in }) throws -> GuardedMemory {
        let memory = try GuardedMemory(count: count * step)
        for index in 0..<count {
            memory.setUInt32(UInt32(step), at: index * step)
            // A value per element, to tell them apart.
            let optionsOffset = MemoryLayout<ntk_notification_action>.offset(of: \.options) ?? 0
            memory.setUInt32(UInt32(index + 1), at: index * step + optionsOffset)
            set(memory, index)
        }
        return memory
    }

    private func readActions(_ memory: GuardedMemory, count: Int) throws(EntryError) -> [ntk_notification_action] {
        try StructReader.readArray(memory.pointer(as: ntk_notification_action.self), count: count, reserved: [])
    }

    func testNoElementsAreNoRead() throws {
        let none: [ntk_notification_action] = try StructReader.readArray(nil, count: 0, reserved: [])
        XCTAssertEqual(none.count, 0)
        // A pointer to nothing: GuardedMemory(count: 0) ends right at the guard page.
        let memory = try GuardedMemory(count: 0)
        XCTAssertEqual(try readActions(memory, count: 0).count, 0)
    }

    func testNullWithElementsAndANegativeCount() throws {
        assertFails(.invalidParameter) { () throws(EntryError) in
            let _: [ntk_notification_action] = try StructReader.readArray(nil, count: 1, reserved: [])
        }
        let memory = try actionArray(count: 1, step: actionSize)
        // size_t above Int.max
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(memory, count: -1) }
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(memory, count: Int.min) }
    }

    /// Checked arithmetic: the second element is not there, and nothing tries it.
    func testACountThatOverflowsIsRejectedBeforeTheSecondElement() throws {
        let memory = try actionArray(count: 1, step: actionSize)
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(memory, count: Int.max) }
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(memory, count: Int.max / actionSize + 1) }
    }

    /// The elements are as the caller's header has them.
    func testElementsOfTheKnownSize() throws {
        let memory = try actionArray(count: 3, step: actionSize)
        XCTAssertEqual(try readActions(memory, count: 3).map(\.options), [1, 2, 3])
    }

    /// A larger caller struct: it steps by the caller's size, not the type's.
    func testElementsOfALargerCallerStruct() throws {
        let step = actionSize + 16
        let memory = try actionArray(count: 3, step: step)
        XCTAssertEqual(try readActions(memory, count: 3).map(\.options), [1, 2, 3])
    }

    /// A smaller caller struct, for a type that gained a field: the steps are the older size, and the added field is 0.
    func testElementsOfASmallerCallerStruct() throws {
        struct GrownAction {
            var action: ntk_notification_action
            var added: UInt64
        }
        let memory = try actionArray(count: 3, step: actionSize)

        let read = try StructReader.readArray(memory.pointer(as: GrownAction.self), count: 3, minimumSize: actionSize, reserved: [])

        XCTAssertEqual(read.map(\.action.options), [1, 2, 3])
        XCTAssertEqual(read.map(\.added), [0, 0, 0])
    }

    /// A step the header would not make, leaving the elements misaligned, must not trap.
    func testElementsThatAreNotAligned() throws {
        let step = actionSize + 4
        let memory = try actionArray(count: 3, step: step)
        XCTAssertEqual(try readActions(memory, count: 3).map(\.options), [1, 2, 3])
    }

    func testMixedSizesAreRejected() throws {
        // One element larger than the first.
        let larger = try actionArray(count: 3, step: actionSize + 8)
        larger.setUInt32(UInt32(actionSize + 16), at: (actionSize + 8) * 2)
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(larger, count: 3) }

        // One element smaller than the first, still at least the minimum.
        let smaller = try actionArray(count: 2, step: actionSize + 8)
        smaller.setUInt32(UInt32(actionSize), at: actionSize + 8)
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(smaller, count: 2) }
    }

    func testAnElementBelowTheMinimumOrAboveTheMaximum() throws {
        let tooSmall = try actionArray(count: 1, step: actionSize)
        tooSmall.setUInt32(UInt32(actionSize - 8), at: 0)
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(tooSmall, count: 1) }

        // The bad value is all that a read may see: 2 elements of 4097 are not there.
        let tooLarge = try GuardedMemory(count: 4)
        tooLarge.setUInt32(4097, at: 0)
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(tooLarge, count: 2) }
    }

    /// Only the first `count` elements count, however many follow.
    func testNothingPastTheLastElementIsRead() throws {
        for step in [actionSize, actionSize + 8, 4096] {
            let memory = try actionArray(count: 2, step: step)
            XCTAssertEqual(try readActions(memory, count: 2).count, 2, "step \(step)")
        }
    }

    func testTheRulesHoldForEveryElement() throws {
        let reserved = try actionArray(count: 3, step: actionSize) { memory, index in
            if index == 2 { memory.setUInt32(1, at: index * actionSize + 4) }
        }
        assertFails(.invalidParameter) { () throws(EntryError) in _ = try readActions(reserved, count: 3) }

        let step = actionSize + 8
        let tail = try actionArray(count: 3, step: step)
        tail.setByte(0xAB, at: step * 2 + actionSize)
        assertFails(.notSupported) { () throws(EntryError) in _ = try readActions(tail, count: 3) }

        let reservedOffset = MemoryLayout<ntk_clipboard_scope>.offset(of: \.reserved1) ?? 0
        let scopes = try GuardedMemory(count: scopeSize * 2)
        scopes.setUInt32(UInt32(scopeSize), at: 0)
        scopes.setUInt32(UInt32(scopeSize), at: scopeSize)
        scopes.setUInt32(1, at: scopeSize + reservedOffset)
        assertFails(.invalidParameter) { () throws(EntryError) in
            _ = try StructReader.readArray(scopes.pointer(as: ntk_clipboard_scope.self), count: 2, reserved: [\.reserved1])
        }
    }
}
