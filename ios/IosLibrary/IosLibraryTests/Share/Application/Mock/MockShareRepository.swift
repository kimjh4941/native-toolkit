//
//  MockShareRepository.swift
//  IosLibraryTests
//

import Foundation
@testable import IosLibrary

// Main-actor isolated so the mutable test state is Sendable, as `ShareRepository` requires.
@MainActor
final class MockShareRepository: ShareRepository {

    var shouldFail = false
    var errorToThrow: ShareError = .noRootViewController
    var stubbedResult = ShareResult(completed: true, activityType: "com.apple.UIKit.activity.CopyToPasteboard")

    /// Thrown in place of `errorToThrow` when set (an error that is not a `ShareError`).
    var otherErrorToThrow: (any Error)?

    private(set) var presentCallCount = 0
    private(set) var lastContent: ShareContent?
    /// The `logName` of each presenter passed in, in order.
    private(set) var presenters: [String] = []

    func present(content: ShareContent, presenter: PresenterSelection) async throws -> ShareResult {
        presentCallCount += 1
        lastContent = content
        presenters.append(presenter.logName)
        if let otherErrorToThrow { throw otherErrorToThrow }
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }
}
