//
//  ShareErrorTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
@testable import IosLibrary

/// UT-16 (Share): the descriptions are fixed. The four that S13〜S16 compare in full and
/// `noRootViewController` are the same as before 1b; the others hold no value that was passed in.
struct ShareErrorTests {

    // MARK: - The texts from before 1b (S13〜S16 compare them in full)

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

    // MARK: - The new fixed texts

    /// 3.3: the presentation failure no longer appends a system description, and the activity
    /// failure has its own text (before 1b both were "Failed to present the share sheet: <...>.").
    @Test func theNewCasesHaveFixedTexts() {
        #expect(ShareError.notForeground.errorDescription
                == "The app has no view controller in the foreground to present the share sheet.")
        #expect(ShareError.presentationFailed.errorDescription == "Failed to present the share sheet.")
        #expect(ShareError.dismissedBySystem.errorDescription == "The share sheet was dismissed without a result.")
        #expect(ShareError.activityFailed(FailureDetail(domain: "D", code: 1)).errorDescription == "The share activity failed.")
    }

    /// The activity failure's text shows nothing of the system error it carries.
    @Test func theActivityFailureTextHoldsNoDetail() throws {
        let description = try #require(ShareError.activityFailed(FailureDetail(domain: "secret-domain-41", code: 9137)).errorDescription)
        #expect(!description.contains("secret-domain-41"))
        #expect(!description.contains("9137"))
    }

    /// Every case has a description, and the cases without a value all differ (a C ABI caller
    /// tells them apart by case, a Swift caller may also by text).
    @Test func everyCaseHasItsOwnDescription() {
        let cases: [ShareError] = [
            .noValidItems, .invalidURL("u"), .imageLoadFailed(path: "/i"), .fileNotFound(path: "/f"),
            .noRootViewController, .notForeground, .presentationFailed, .dismissedBySystem,
            .activityFailed(FailureDetail(domain: "D", code: 1)),
        ]
        // The switch is exhaustive, so a new case does not compile until it gets a number here;
        // the numbers then show that `cases` lists every case once.
        func ordinal(_ error: ShareError) -> Int {
            switch error {
            case .noValidItems: return 0
            case .invalidURL: return 1
            case .imageLoadFailed: return 2
            case .fileNotFound: return 3
            case .noRootViewController: return 4
            case .notForeground: return 5
            case .presentationFailed: return 6
            case .dismissedBySystem: return 7
            case .activityFailed: return 8
            }
        }
        #expect(cases.map(ordinal).sorted() == Array(0..<9))
        for error in cases {
            #expect(error.errorDescription?.isEmpty == false)
        }
        let descriptions = cases.compactMap(\.errorDescription)
        #expect(Set(descriptions).count == cases.count)
    }

    // MARK: - Equatable and the detail

    @Test func casesCompareByTheirValues() {
        #expect(ShareError.activityFailed(FailureDetail(domain: "D", code: 1)) == .activityFailed(FailureDetail(domain: "D", code: 1)))
        #expect(ShareError.activityFailed(FailureDetail(domain: "D", code: 1)) != .activityFailed(FailureDetail(domain: "D", code: 2)))
        #expect(ShareError.invalidURL("a") != .invalidURL("b"))
        #expect(ShareError.notForeground != .noRootViewController)
    }
}
