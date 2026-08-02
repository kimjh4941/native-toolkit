//
//  MockClipboardTypeIdentifierValidating.swift
//  IosLibraryTests
//

import Foundation
@testable import IosLibrary

final class MockClipboardTypeIdentifierValidating: ClipboardTypeIdentifierValidating, @unchecked Sendable {
    var shouldFailGeneric = false
    var shouldFailImage = false
    private(set) var validateGenericCallCount = 0
    private(set) var validateImageCallCount = 0

    func validateGeneric(_ identifier: String) throws {
        validateGenericCallCount += 1
        if shouldFailGeneric { throw ClipboardError.invalidTypeIdentifier(identifier) }
    }

    func validateImage(_ identifier: String) throws {
        validateImageCallCount += 1
        if shouldFailImage { throw ClipboardError.invalidTypeIdentifier(identifier) }
    }
}

struct FixedClock: ClipboardClock {
    let fixedNow: Date
    func now() -> Date { fixedNow }
}
