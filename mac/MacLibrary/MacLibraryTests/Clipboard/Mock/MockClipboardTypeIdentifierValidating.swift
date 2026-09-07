//
//  MockClipboardTypeIdentifierValidating.swift
//  MacLibraryTests
//

import Foundation
@testable import MacLibrary

/// Accepts everything unless an identifier is listed as invalid.
///
/// The default is permissive so that a test about size limits does not have to spell out valid
/// type identifiers, while a test about identifier rejection can name exactly one bad value.
@MainActor
final class MockClipboardTypeIdentifierValidating: ClipboardTypeIdentifierValidating {

    var invalidIdentifiers: Set<String> = []
    private(set) var isValidCallCount = 0
    private(set) var checkedIdentifiers: [String] = []

    func isValid(_ identifier: String) -> Bool {
        isValidCallCount += 1
        checkedIdentifiers.append(identifier)
        return !invalidIdentifiers.contains(identifier)
    }

}
