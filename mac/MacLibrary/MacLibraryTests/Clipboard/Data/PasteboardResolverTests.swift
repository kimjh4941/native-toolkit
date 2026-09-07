//
//  PasteboardResolverTests.swift
//  MacLibraryTests
//

import Testing
import AppKit
import Foundation
@testable import MacLibrary

@Suite("PasteboardResolver")
@MainActor
struct PasteboardResolverTests {

    @Test("general resolves to the system general pasteboard")
    func resolvesGeneral() throws {
        let pasteboard = try PasteboardResolver.resolve(.general)
        #expect(pasteboard === NSPasteboard.general)
    }

    @Test("a named scope resolves to a pasteboard carrying that name")
    func resolvesNamed() throws {
        let name = "com.nativetoolkit.tests.resolve.\(UUID().uuidString)"
        let pasteboard = try PasteboardResolver.resolve(.named(name))
        #expect(pasteboard.name.rawValue == name)
        pasteboard.releaseGlobally()
    }

    @Test("resolving the same name twice addresses the same pasteboard")
    func resolvesStableIdentity() throws {
        let name = "com.nativetoolkit.tests.stable.\(UUID().uuidString)"
        let first = try PasteboardResolver.resolve(.named(name))
        first.clearContents()
        #expect(first.setString("value", forType: .string))

        let second = try PasteboardResolver.resolve(.named(name))
        #expect(second.string(forType: .string) == "value")
        second.releaseGlobally()
    }

    @Test("an empty name is rejected", arguments: [
        PasteboardScope.named(""), PasteboardScope.unique(""),
    ])
    func rejectsEmptyName(scope: PasteboardScope) {
        #expect(throws: ClipboardError.invalidPasteboardName("")) {
            _ = try PasteboardResolver.resolve(scope)
        }
    }

    @Test("creating a named pasteboard returns the resolved name in the scope")
    func createNamed() throws {
        let name = "com.nativetoolkit.tests.create.\(UUID().uuidString)"
        let (pasteboard, scope) = try PasteboardResolver.create(.named(name))
        #expect(scope == .named(name))
        #expect(pasteboard.name.rawValue == name)
        pasteboard.releaseGlobally()
    }

    @Test("creating a unique pasteboard reports the system chosen name")
    func createUnique() throws {
        let (pasteboard, scope) = try PasteboardResolver.create(.unique)
        // The caller cannot know the name in advance, so the scope has to carry it back or the
        // pasteboard becomes unaddressable and therefore unreleasable.
        #expect(scope == .unique(pasteboard.name.rawValue))
        #expect(scope.name?.isEmpty == false)
        pasteboard.releaseGlobally()
    }

    @Test("two unique pasteboards do not collide")
    func uniqueNamesDiffer() throws {
        let (first, firstScope) = try PasteboardResolver.create(.unique)
        let (second, secondScope) = try PasteboardResolver.create(.unique)
        #expect(firstScope != secondScope)
        first.releaseGlobally()
        second.releaseGlobally()
    }

    @Test("creating with an empty name is rejected")
    func createRejectsEmptyName() {
        #expect(throws: ClipboardError.invalidPasteboardName("")) {
            _ = try PasteboardResolver.create(.named(""))
        }
    }

    @Test("general is always a standard pasteboard")
    func generalIsStandard() {
        #expect(PasteboardResolver.isStandard(.general))
    }

    @Test("the five system pasteboard names are standard")
    func systemNamesAreStandard() {
        let names = [
            NSPasteboard.Name.general, .font, .ruler, .find, .drag,
        ]
        for name in names {
            // A caller can spell a standard name into `.named`, so the guard cannot rely on the
            // scope case alone.
            #expect(PasteboardResolver.isStandard(.named(name.rawValue)), "\(name.rawValue)")
        }
        #expect(PasteboardResolver.standardNames.count == names.count)
    }

    @Test("an app owned name is not standard")
    func customNameIsNotStandard() {
        #expect(!PasteboardResolver.isStandard(.named("com.nativetoolkit.tests.custom")))
        #expect(!PasteboardResolver.isStandard(.unique("com.nativetoolkit.tests.unique")))
    }
}
