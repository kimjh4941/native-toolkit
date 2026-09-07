//
//  ClipboardTypeIdentifierValidatorTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
import UniformTypeIdentifiers
@testable import MacLibrary

@Suite("ClipboardTypeIdentifierValidator")
@MainActor
struct ClipboardTypeIdentifierValidatorTests {

    private let validator = ClipboardTypeIdentifierValidator()

    @Test("well known identifiers are valid", arguments: [
        "public.utf8-plain-text", "public.rtf", "public.png", "public.file-url",
        "public.data", "public.directory", "com.adobe.pdf",
    ])
    func acceptsKnownIdentifiers(identifier: String) {
        #expect(validator.isValid(identifier))
    }

    @Test("malformed identifiers are rejected", arguments: [
        "", " ", "not a uti", "public..text", "パブリック", "abc",
    ])
    func rejectsMalformedIdentifiers(identifier: String) {
        #expect(!validator.isValid(identifier))
    }

    // The cases below pin the rule NSPasteboardItem.setData enforces, measured on macOS 26.3.
    // Validity is not UTType resolution: an app's own undeclared format is accepted by the
    // pasteboard and must be accepted here. If a future macOS changes the rule, these fail.

    @Test("an app's own undeclared identifier is accepted", arguments: [
        "com.nativetoolkit.tests.custom-type", "com.mycompany.myformat", "a.b",
    ])
    func acceptsUndeclaredIdentifier(identifier: String) {
        #expect(UTType(identifier) == nil, "precondition: the system must not know this type")
        #expect(validator.isValid(identifier))
    }

    @Test("a single segment is rejected")
    func rejectsSingleSegment() {
        #expect(!validator.isValid("abc"))
        #expect(validator.isValid("a.b"))
    }

    @Test("empty segments are rejected", arguments: [
        "com.a..b", ".com.a", "com.a.", "..", ".",
    ])
    func rejectsEmptySegments(identifier: String) {
        #expect(!validator.isValid(identifier))
    }

    @Test("hyphens are allowed inside a segment only", arguments: [
        ("com.a.b-c", true), ("a.b--c", true), ("public.utf8-plain-text", true),
        ("a.b-", false), ("a-.b", false), ("-a.b", false), ("a.--", false),
    ])
    func hyphenPlacement(identifier: String, expected: Bool) {
        #expect(validator.isValid(identifier) == expected)
    }

    @Test("only ASCII alphanumerics and hyphens are allowed", arguments: [
        "com.a.b+c", "com.a.b_c", "com.a.b c", "com.a.b/c", "com.a.b:c",
        "com.a.b#c", "com.a.b%c", "com.a.b*c", "com.a.b@c", "com.a.b\tc", "com.a.b\nc",
    ])
    func rejectsDisallowedCharacters(identifier: String) {
        #expect(!validator.isValid(identifier))
    }

    @Test("uppercase and digits are allowed", arguments: [
        "com.a.B", "com.a.1", "1com.a", "a.1-2",
    ])
    func acceptsUppercaseAndDigits(identifier: String) {
        #expect(validator.isValid(identifier))
    }

    @Test("long identifiers are not truncated or rejected")
    func acceptsLongIdentifier() {
        // Measured: accepted up to 2004 characters. There is no practical length limit to
        // enforce, so none is imposed.
        #expect(validator.isValid("com." + String(repeating: "a", count: 2000)))
    }

    @Test("conformance matches a subtype against its supertype")
    func conformsToSupertype() {
        #expect(validator.conforms("public.utf8-plain-text", to: "public.text"))
        #expect(validator.conforms("public.png", to: "public.image"))
        #expect(validator.conforms("public.png", to: "public.data"))
    }

    @Test("conformance is not symmetric")
    func conformanceIsDirectional() {
        // A filter of public.utf8-plain-text must not select every public.text item.
        #expect(!validator.conforms("public.text", to: "public.utf8-plain-text"))
    }

    @Test("a type conforms to itself")
    func conformsToSelf() {
        #expect(validator.conforms("public.png", to: "public.png"))
    }

    @Test("unrelated types do not conform")
    func rejectsUnrelated() {
        #expect(!validator.conforms("public.png", to: "public.text"))
    }

    @Test("an unresolvable identifier conforms to nothing")
    func unresolvableConformsToNothing() {
        #expect(!validator.conforms("not a uti", to: "public.data"))
        #expect(!validator.conforms("public.png", to: "not a uti"))
    }

    @Test("an undeclared custom type still matches a filter naming it exactly")
    func undeclaredTypeMatchesItself() {
        // The pasteboard accepts this type, so a snapshot filter naming it has to select the
        // item. UTType cannot express that because it never resolves the identifier.
        let custom = "com.mycompany.myformat"
        #expect(UTType(custom) == nil)
        #expect(validator.conforms(custom, to: custom))
        #expect(validator.conforms(custom, toAnyOf: ["public.text", custom]))
        #expect(!validator.conforms(custom, to: "public.data"))
    }

    @Test("a malformed identifier does not even conform to itself")
    func malformedDoesNotConformToItself() {
        #expect(!validator.conforms("not a uti", to: "not a uti"))
    }

    @Test("any-of matching succeeds when one filter conforms")
    func conformsToAnyOf() {
        #expect(validator.conforms("public.png", toAnyOf: ["public.text", "public.image"]))
    }

    @Test("any-of matching fails when no filter conforms")
    func conformsToNoneOf() {
        #expect(!validator.conforms("public.png", toAnyOf: ["public.text", "public.rtf"]))
    }

    @Test("an empty filter list matches nothing")
    func emptyFilterMatchesNothing() {
        #expect(!validator.conforms("public.png", toAnyOf: []))
    }
}
