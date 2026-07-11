//
//  ShareErrorTests.swift
//  MacLibraryTests
//
import Testing
@testable import MacLibrary

struct ShareErrorTests {

    // MARK: - Error Codes

    @Test func noValidItemsHasCode1401() {
        #expect(ShareError.noValidItems.errorCode == 1401)
    }

    @Test func invalidURLHasCode1402() {
        #expect(ShareError.invalidURL("bad").errorCode == 1402)
    }

    @Test func imageLoadFailedHasCode1403() {
        #expect(ShareError.imageLoadFailed(path: "/p").errorCode == 1403)
    }

    @Test func fileNotFoundHasCode1404() {
        #expect(ShareError.fileNotFound(path: "/p").errorCode == 1404)
    }

    @Test func noAnchorViewHasCode1405() {
        #expect(ShareError.noAnchorView.errorCode == 1405)
    }

    @Test func serviceUnavailableHasCode1406() {
        #expect(ShareError.serviceUnavailable(name: "x").errorCode == 1406)
    }

    @Test func presentationFailedHasCode1407() {
        let error = ShareError.presentationFailed(NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1407)
    }

    @Test func alreadyInProgressHasCode1408() {
        #expect(ShareError.alreadyInProgress.errorCode == 1408)
    }

    @Test func unknownHasCode1499() {
        let error = ShareError.unknown(NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1499)
    }

    // MARK: - Error Messages

    @Test func noValidItemsMessage() {
        #expect(ShareError.noValidItems.errorMessage == "No shareable items were provided.")
    }

    @Test func invalidURLMessage() {
        #expect(ShareError.invalidURL("bad-url").errorMessage == "Invalid URL: bad-url.")
    }

    @Test func imageLoadFailedMessage() {
        #expect(ShareError.imageLoadFailed(path: "/tmp/a.png").errorMessage == "Failed to load image at path: /tmp/a.png.")
    }

    @Test func fileNotFoundMessage() {
        #expect(ShareError.fileNotFound(path: "/tmp/a.pdf").errorMessage == "File not found at path: /tmp/a.pdf.")
    }

    @Test func noAnchorViewMessage() {
        #expect(ShareError.noAnchorView.errorMessage == "No key window available to anchor the sharing picker.")
    }

    @Test func serviceUnavailableMessage() {
        #expect(ShareError.serviceUnavailable(name: "com.apple.share.Mail.compose").errorMessage
                == "Sharing service unavailable: com.apple.share.Mail.compose.")
    }

    @Test func alreadyInProgressMessage() {
        #expect(ShareError.alreadyInProgress.errorMessage == "A share operation is already in progress.")
    }

    @Test func errorDescriptionMatchesErrorMessage() {
        let error = ShareError.noValidItems
        #expect(error.errorDescription == error.errorMessage)
    }
}
