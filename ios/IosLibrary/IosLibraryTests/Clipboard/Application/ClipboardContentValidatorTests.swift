//
//  ClipboardContentValidatorTests.swift
//  IosLibraryTests
//

import Testing
import Foundation
@testable import IosLibrary

struct ClipboardContentValidatorTests {
    private let validator = ClipboardContentValidator()

    @Test func emptyPlainTextIsAllowed() throws {
        try validator.validate(.plainText(""))
    }

    @Test func blankHtmlIsRejected() {
        #expect(throws: ClipboardError.emptyContent) {
            try validator.validate(.htmlText(plain: "", html: "   "))
        }
    }

    @Test func blankPlainInHtmlIsAllowed() throws {
        try validator.validate(.htmlText(plain: "", html: "<b>hi</b>"))
    }

    @Test(arguments: ["", "example.com", "https://"])
    func invalidURLsAreRejected(_ value: String) {
        #expect(throws: ClipboardError.self) {
            try validator.validate(.url(value))
        }
    }

    @Test func validURLIsAllowed() throws {
        try validator.validate(.url("https://example.com"))
    }

    @Test func emptyMultipleTextIsRejected() {
        #expect(throws: ClipboardError.emptyItemList) {
            try validator.validate(.multipleText([]))
        }
    }

    @Test func emptyMultiRepresentationIsRejected() {
        #expect(throws: ClipboardError.emptyItemList) {
            try validator.validate(.multiRepresentation([:]))
        }
    }

    @Test func multiRepresentationWithEmptyDataIsRejected() {
        #expect(throws: ClipboardError.emptyContent) {
            try validator.validate(.multiRepresentation(["public.text": Data()]))
        }
    }

    @Test(arguments: [Double.infinity, -0.1, 1.1])
    func invalidColorComponentsAreRejected(_ value: Double) {
        #expect(throws: ClipboardError.invalidColor) {
            try validator.validate(.color(red: value, green: 0, blue: 0, alpha: 1))
        }
    }

    @Test func boundaryColorComponentsAreAllowed() throws {
        try validator.validate(.color(red: 0.0, green: 1.0, blue: 0.0, alpha: 1.0))
    }

    @Test func expirationAtOrBeforeNowIsRejected() {
        let clock = FixedClock(fixedNow: Date(timeIntervalSince1970: 1000))
        let validator = ClipboardContentValidator(clock: clock)
        #expect(throws: ClipboardError.invalidExpirationDate) {
            try validator.validateExpirationDate(Date(timeIntervalSince1970: 1000))
        }
        #expect(throws: ClipboardError.invalidExpirationDate) {
            try validator.validateExpirationDate(Date(timeIntervalSince1970: 999))
        }
    }

    @Test func expirationAfterNowIsAllowed() throws {
        let clock = FixedClock(fixedNow: Date(timeIntervalSince1970: 1000))
        let validator = ClipboardContentValidator(clock: clock)
        try validator.validateExpirationDate(Date(timeIntervalSince1970: 1001))
    }

    @Test func emptyImageFilePathIsRejected() {
        #expect(throws: ClipboardError.self) {
            try validator.validate(.imageFile(path: ""))
        }
    }

    @Test func contentExceedingSizeLimitIsRejected() {
        let limits = ClipboardLimits(maxCopyByteCount: 10, maxLoadByteCount: 10, maxImagePixelCount: 10)!
        let validator = ClipboardContentValidator(limits: limits)
        #expect(throws: ClipboardError.self) {
            try validator.validate(.plainText(String(repeating: "a", count: 100)))
        }
    }
}
