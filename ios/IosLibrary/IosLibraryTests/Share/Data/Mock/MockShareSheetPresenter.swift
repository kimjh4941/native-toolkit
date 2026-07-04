//
//  MockShareSheetPresenter.swift
//  IosLibraryTests
//

import UIKit
@testable import IosLibrary

final class MockShareSheetPresenter: ShareSheetPresenting {

    var shouldFail = false
    var errorToThrow: ShareError = .noRootViewController
    var stubbedResult = ShareResult(completed: true, activityType: nil)

    private(set) var lastItems: [Any]?
    private(set) var lastExcluded: [UIActivity.ActivityType]?

    func present(items: [Any], excluded: [UIActivity.ActivityType]) async throws -> ShareResult {
        lastItems = items
        lastExcluded = excluded
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }
}
