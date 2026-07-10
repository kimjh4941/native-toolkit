//
//  MockShareRepository.swift
//  IosLibraryTests
//

import Foundation
@testable import IosLibrary

final class MockShareRepository: ShareRepository {

    var shouldFail = false
    var errorToThrow: ShareError = .noRootViewController
    var stubbedResult = ShareResult(completed: true, activityType: "com.apple.UIKit.activity.CopyToPasteboard")

    private(set) var presentCallCount = 0
    private(set) var lastContent: ShareContent?

    func present(content: ShareContent) async throws -> ShareResult {
        presentCallCount += 1
        lastContent = content
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }
}
