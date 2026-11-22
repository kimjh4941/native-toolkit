//
//  MockShareSheetPresenter.swift
//  IosLibraryTests
//

import UIKit
@testable import IosLibrary

// Main-actor isolated like the `ShareSheetPresenting` requirement, so the mutable test state is Sendable.
@MainActor
final class MockShareSheetPresenter: ShareSheetPresenting {

    var shouldFail = false
    var errorToThrow: ShareError = .noRootViewController
    var stubbedResult = ShareResult(completed: true, activityType: nil)

    private(set) var lastItems: [Any]?
    private(set) var lastExcluded: [UIActivity.ActivityType]?
    /// The `logName` of the last presenter passed in.
    private(set) var lastPresenter: String?

    func present(items: [Any], excluded: [UIActivity.ActivityType], presenter: PresenterSelection) async throws -> ShareResult {
        lastItems = items
        lastExcluded = excluded
        lastPresenter = presenter.logName
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }
}
