//
//  ShareErrorTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct ShareErrorTests {

    private struct TestError: Error {}

    @Test func noValidItemsDescription() {
        #expect(ShareError.noValidItems.errorDescription == "No shareable items were provided.")
    }

    @Test func invalidURLDescription() {
        #expect(ShareError.invalidURL("bad").errorDescription == "Invalid URL: bad.")
    }

    @Test func imageLoadFailedDescription() {
        #expect(ShareError.imageLoadFailed(path: "/a.png").errorDescription
                == "Failed to load image at path: /a.png.")
    }

    @Test func fileNotFoundDescription() {
        #expect(ShareError.fileNotFound(path: "/a.pdf").errorDescription
                == "File not found at path: /a.pdf.")
    }

    @Test func noRootViewControllerDescription() {
        #expect(ShareError.noRootViewController.errorDescription
                == "No root view controller available to present the share sheet.")
    }

    @Test func presentationFailedDescriptionContainsUnderlyingMessage() {
        let error = ShareError.presentationFailed(TestError())
        #expect(error.errorDescription?.hasPrefix("Failed to present the share sheet:") == true)
    }

    @Test func unknownDescriptionContainsUnderlyingMessage() {
        let error = ShareError.unknown(TestError())
        #expect(error.errorDescription?.hasPrefix("An unknown error occurred:") == true)
    }
}
