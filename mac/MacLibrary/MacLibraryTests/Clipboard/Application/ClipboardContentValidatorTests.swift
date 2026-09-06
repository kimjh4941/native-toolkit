//
//  ClipboardContentValidatorTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("ClipboardContentValidator")
@MainActor
struct ClipboardContentValidatorTests {

    private let text = "public.utf8-plain-text"

    private func makeValidator(warn: Int = 100, max: Int = 200, total: Int = 300)
    throws -> (ClipboardContentValidator, MockClipboardTypeIdentifierValidating) {
        let typeValidator = MockClipboardTypeIdentifierValidating()
        let limits = try ClipboardLimits(warnBytesPerRepresentation: warn,
                                         maxBytesPerRepresentation: max,
                                         maxTotalBytes: total)
        return (ClipboardContentValidator(limits: limits, typeValidator: typeValidator), typeValidator)
    }

    private func content(_ representations: [String: Data]...) -> ClipboardContent {
        ClipboardContent(items: representations.map { ClipboardItemData(representations: $0) })
    }

    private func bytes(_ count: Int) -> Data {
        Data(repeating: 0, count: count)
    }

    @Test("valid content passes")
    func acceptsValidContent() throws {
        let (validator, _) = try makeValidator()
        try validator.validate(content([text: bytes(10)]))
    }

    @Test("empty content is rejected")
    func rejectsEmptyContent() throws {
        let (validator, _) = try makeValidator()
        #expect(throws: ClipboardError.emptyContent) {
            try validator.validate(ClipboardContent(items: []))
        }
    }

    @Test("an item with no representations is rejected and names its index")
    func rejectsEmptyRepresentations() throws {
        let (validator, _) = try makeValidator()
        #expect(throws: ClipboardError.emptyRepresentations(itemIndex: 1)) {
            try validator.validate(self.content([self.text: self.bytes(1)], [:]))
        }
    }

    @Test("an invalid identifier is rejected")
    func rejectsInvalidIdentifier() throws {
        let (validator, typeValidator) = try makeValidator()
        typeValidator.invalidIdentifiers = ["bad.type"]
        #expect(throws: ClipboardError.invalidTypeIdentifier("bad.type")) {
            try validator.validate(self.content(["bad.type": self.bytes(1)]))
        }
    }

    @Test("every identifier is checked")
    func checksEveryIdentifier() throws {
        let (validator, typeValidator) = try makeValidator()
        try validator.validate(content([text: bytes(1), "public.rtf": bytes(1)],
                                       ["public.png": bytes(1)]))
        #expect(typeValidator.isValidCallCount == 3)
    }

    @Test("a representation exactly on the hard limit is accepted")
    func acceptsRepresentationAtLimit() throws {
        let (validator, _) = try makeValidator(warn: 100, max: 200, total: 300)
        try validator.validate(content([text: bytes(200)]))
    }

    @Test("a representation one byte over the hard limit is rejected")
    func rejectsRepresentationOverLimit() throws {
        let (validator, _) = try makeValidator(warn: 100, max: 200, total: 300)
        #expect(throws: ClipboardError.contentTooLarge(bytes: 201, limit: 200)) {
            try validator.validate(self.content([self.text: self.bytes(201)]))
        }
    }

    @Test("a representation exactly on the warn threshold is accepted")
    func acceptsRepresentationAtWarnThreshold() throws {
        let (validator, _) = try makeValidator(warn: 100, max: 200, total: 300)
        // The warn threshold only logs; it must never reject.
        try validator.validate(content([text: bytes(100)]))
        try validator.validate(content([text: bytes(101)]))
    }

    @Test("a total exactly on the limit is accepted")
    func acceptsTotalAtLimit() throws {
        let (validator, _) = try makeValidator(warn: 100, max: 200, total: 300)
        try validator.validate(content([text: bytes(150)], ["public.rtf": bytes(150)]))
    }

    @Test("a total one byte over the limit is rejected")
    func rejectsTotalOverLimit() throws {
        let (validator, _) = try makeValidator(warn: 100, max: 200, total: 300)
        // Each representation is under its own limit, so only the total can catch this.
        #expect(throws: ClipboardError.contentTooLarge(bytes: 301, limit: 300)) {
            try validator.validate(self.content([self.text: self.bytes(150)],
                                                ["public.rtf": self.bytes(151)]))
        }
    }

    @Test("the per representation limit is reported before the total")
    func representationLimitTakesPrecedence() throws {
        let (validator, _) = try makeValidator(warn: 100, max: 200, total: 300)
        // A single 400 byte representation breaks both limits. The more specific one is the
        // useful message, so it has to win.
        #expect(throws: ClipboardError.contentTooLarge(bytes: 400, limit: 200)) {
            try validator.validate(self.content([self.text: self.bytes(400)]))
        }
    }
}
