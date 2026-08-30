//
//  ClipboardErrorTests.swift
//  MacLibraryTests
//

import Testing
import Foundation
@testable import MacLibrary

@Suite("ClipboardError")
struct ClipboardErrorTests {

    /// One representative value per case, so the code and message tables can be walked.
    private static let allCases: [ClipboardError] = [
        .emptyContent,
        .emptyRepresentations(itemIndex: 3),
        .emptyDetectionPatterns,
        .invalidTypeIdentifier("not a uti"),
        .invalidPasteboardName(""),
        .contentTooLarge(bytes: 200, limit: 100),
        .pasteboardUnavailable(name: "general"),
        .cannotReleaseStandardPasteboard(name: "general"),
        .writeRejected,
        .appendRejected,
        .ownershipLost(expected: 4, actual: 5),
        .emptyTypeFilter,
        .detectionUnavailable(minimumOS: "15.4"),
        .detectionDenied,
        .detectionFailed("boom"),
        .filePromiseTypeInvalid("public.folder"),
        .invalidFileName(".."),
        .filePromiseWriteFailed("disk full"),
        .filePromiseReceiveFailed("reader failed"),
        .destinationNotWritable("/nope"),
        .pasteLoadFailed("provider failed"),
        .pasteLoadTimedOut(seconds: 15),
        .invalidConfiguration("negative"),
        .cancelled,
        .unknown("???"),
    ]

    @Test("every case is covered by the table")
    func caseCount() {
        #expect(Self.allCases.count == 25)
    }

    @Test("error codes are unique")
    func codesAreUnique() {
        let codes = Self.allCases.map(\.errorCode)
        #expect(Set(codes).count == codes.count)
    }

    @Test("error codes stay inside the reserved clipboard band")
    func codesInBand() {
        for error in Self.allCases {
            #expect((1501...1599).contains(error.errorCode),
                    "\(error) used \(error.errorCode)")
        }
    }

    @Test("error codes do not collide with the bridge band")
    func noBridgeCollision() {
        let bridgeCodes = [BridgeError.parseFailed(reason: "x").errorCode,
                           BridgeError.contractViolation(reason: "x").errorCode]
        for error in Self.allCases {
            #expect(!bridgeCodes.contains(error.errorCode))
        }
    }

    @Test("messages are non empty, English and end with a period")
    func messagesWellFormed() {
        for error in Self.allCases {
            let message = error.errorMessage
            #expect(!message.isEmpty)
            #expect(message.hasSuffix("."), "\(error) -> \(message)")
            #expect(message.allSatisfy { $0.isASCII }, "\(error) -> \(message)")
        }
    }

    @Test("messages interpolate their associated values")
    func messagesCarryContext() {
        #expect(ClipboardError.emptyRepresentations(itemIndex: 3).errorMessage.contains("3"))
        #expect(ClipboardError.contentTooLarge(bytes: 200, limit: 100)
            .errorMessage.contains("200"))
        #expect(ClipboardError.ownershipLost(expected: 4, actual: 5)
            .errorMessage.contains("expected change count 4"))
        #expect(ClipboardError.detectionUnavailable(minimumOS: "15.4")
            .errorMessage.contains("15.4"))
    }

    @Test("localizedDescription mirrors errorMessage")
    func localizedDescriptionMatches() {
        for error in Self.allCases {
            #expect((error as LocalizedError).errorDescription == error.errorMessage)
        }
    }

    @Test("specific codes match the design table")
    func spotCheckCodes() {
        #expect(ClipboardError.emptyContent.errorCode == 1501)
        #expect(ClipboardError.ownershipLost(expected: 1, actual: 2).errorCode == 1511)
        #expect(ClipboardError.invalidConfiguration("x").errorCode == 1523)
        #expect(ClipboardError.cancelled.errorCode == 1524)
        #expect(ClipboardError.unknown("x").errorCode == 1599)
    }
}
