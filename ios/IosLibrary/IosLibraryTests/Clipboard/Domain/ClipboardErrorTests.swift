//
//  ClipboardErrorTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct ClipboardErrorTests {
    private static let detail = ClipboardFailureDetail(domain: "d", code: 1, debugMessage: "secret debug message")

    private static let allCases: [ClipboardError] = [
        .emptyContent, .emptyItemList, .emptyDetectionPatterns,
        .invalidURL("secret-url"), .invalidTypeIdentifier("secret-type"), .invalidPasteboardName("secret-name"),
        .invalidColor, .invalidImageData, .invalidExpirationDate, .invalidRequest("secret-reason"),
        .contentTooLarge(byteCount: 100, limit: 10),
        .fileNotFound(path: "/secret/path"), .imageLoadFailed(path: "/secret/path"), .imageEncodingFailed,
        .pasteboardUnavailable(name: "secret-pasteboard"), .cannotRemoveGeneralPasteboard,
        .noMatchingItem, .providerLoadFailed(detail), .unexpectedType, .fileCopyFailed(detail),
        .cancelled, .timedOut(operation: .detection), .detectionFailed(detail), .unknown(detail)
    ]

    @Test func hasExactlyTwentyFourCases() {
        #expect(Self.allCases.count == 24)
    }

    @Test func errorCodesAreUniqueAndNonEmpty() {
        let codes = Set(Self.allCases.map(\.errorCode))
        #expect(codes.count == Self.allCases.count)
        #expect(codes.allSatisfy { !$0.isEmpty })
    }

    @Test func errorDescriptionsAreFixedAndDoNotLeakInputValues() {
        for error in Self.allCases {
            let message = error.errorDescription ?? ""
            #expect(!message.isEmpty)
            #expect(!message.contains("secret"))
        }
    }

    @Test func unknownConstantsMatchUnknownCase() {
        #expect(ClipboardError.unknown(Self.detail).errorCode == ClipboardError.unknownErrorCode)
        #expect(ClipboardError.unknown(Self.detail).errorDescription == ClipboardError.unknownMessage)
    }

    @Test func diagnosticDetailOnlyPresentForFourCases() {
        let withDetail: [ClipboardError] = [.providerLoadFailed(Self.detail), .fileCopyFailed(Self.detail),
                                            .detectionFailed(Self.detail), .unknown(Self.detail)]
        for error in withDetail {
            #expect(error.diagnosticDetail != nil)
        }
        #expect(ClipboardError.emptyContent.diagnosticDetail == nil)
    }
}
