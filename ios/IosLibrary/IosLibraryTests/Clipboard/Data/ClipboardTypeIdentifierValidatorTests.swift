//
//  ClipboardTypeIdentifierValidatorTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct ClipboardTypeIdentifierValidatorTests {
    private let validator = ClipboardTypeIdentifierValidator()

    @Test(arguments: ["public.utf8-plain-text", "public.png", "public.html", "public.url"])
    func standardUTIsResolve(_ identifier: String) throws {
        try validator.validateGeneric(identifier)
    }

    @Test func unresolvableGarbageIsRejected() {
        #expect(throws: ClipboardError.self) {
            try validator.validateGeneric("not a valid identifier!!")
        }
    }

    @Test func unregisteredButSyntacticallyValidCustomIdentifierIsAccepted() throws {
        try validator.validateGeneric("com.jonghyunkim.nativetoolkit.custom-payload")
    }

    @Test func imageUTIAcceptsPNG() throws {
        try validator.validateImage("public.png")
    }

    @Test func imageUTIRejectsNonImageStandardType() {
        #expect(throws: ClipboardError.self) {
            try validator.validateImage("public.utf8-plain-text")
        }
    }

    @Test func imageUTIRejectsUnknownIdentifier() {
        #expect(throws: ClipboardError.self) {
            try validator.validateImage("com.jonghyunkim.nativetoolkit.not-an-image")
        }
    }
}
