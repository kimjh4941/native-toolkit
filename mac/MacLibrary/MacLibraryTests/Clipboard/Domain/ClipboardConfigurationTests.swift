//
//  ClipboardConfigurationTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("ClipboardLimits")
struct ClipboardLimitsTests {

    @Test("default satisfies its own constraints")
    func defaultIsValid() throws {
        let limits = ClipboardLimits.default
        #expect(limits.warnBytesPerRepresentation > 0)
        #expect(limits.warnBytesPerRepresentation <= limits.maxBytesPerRepresentation)
        #expect(limits.maxBytesPerRepresentation <= limits.maxTotalBytes)
        // The same values must pass the validating initializer.
        _ = try ClipboardLimits(warnBytesPerRepresentation: limits.warnBytesPerRepresentation,
                                maxBytesPerRepresentation: limits.maxBytesPerRepresentation,
                                maxTotalBytes: limits.maxTotalBytes)
    }

    @Test("accepts values exactly on the boundary")
    func acceptsEqualThresholds() throws {
        let limits = try ClipboardLimits(warnBytesPerRepresentation: 100,
                                         maxBytesPerRepresentation: 100,
                                         maxTotalBytes: 100)
        #expect(limits.maxTotalBytes == 100)
    }

    @Test("rejects non positive values", arguments: [
        (0, 10, 20), (10, 0, 20), (10, 20, 0), (-1, 10, 20),
    ])
    func rejectsNonPositive(warn: Int, max: Int, total: Int) {
        #expect(throws: ClipboardError.invalidConfiguration("Clipboard limits must be positive.")) {
            _ = try ClipboardLimits(warnBytesPerRepresentation: warn,
                                    maxBytesPerRepresentation: max,
                                    maxTotalBytes: total)
        }
    }

    @Test("rejects warn greater than max")
    func rejectsWarnAboveMax() {
        #expect(throws: ClipboardError.self) {
            _ = try ClipboardLimits(warnBytesPerRepresentation: 200,
                                    maxBytesPerRepresentation: 100,
                                    maxTotalBytes: 300)
        }
    }

    @Test("rejects max greater than total")
    func rejectsMaxAboveTotal() {
        #expect(throws: ClipboardError.self) {
            _ = try ClipboardLimits(warnBytesPerRepresentation: 10,
                                    maxBytesPerRepresentation: 300,
                                    maxTotalBytes: 100)
        }
    }
}
