//
//  IosShareManagerTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct IosShareManagerTests {

    private func makeContent() -> ShareContent {
        ShareContent(items: [.text("hello")])
    }

    @Test func shareReturnsSuccessAndCompletedOnHappyPath() async throws {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, activityType: "com.apple.UIKit.activity.Mail")
        let manager = IosShareManager(repository: repo)

        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Bool, Bool, String?, String?, Bool), Error>) in
            manager.share(content: makeContent()) { isSuccess, completed, activityType, errorMessage in
                continuation.resume(returning: (isSuccess, completed, activityType, errorMessage, Thread.isMainThread))
            }
        }

        #expect(outcome.0 == true)
        #expect(outcome.1 == true)
        #expect(outcome.2 == "com.apple.UIKit.activity.Mail")
        #expect(outcome.3 == nil)
        #expect(outcome.4 == true, "completion must be invoked on the main thread")
    }

    @Test func shareReturnsSuccessWithNotCompletedOnCancel() async throws {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: false, activityType: nil)
        let manager = IosShareManager(repository: repo)

        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Bool, Bool, String?, String?, Bool), Error>) in
            manager.share(content: makeContent()) { isSuccess, completed, activityType, errorMessage in
                continuation.resume(returning: (isSuccess, completed, activityType, errorMessage, Thread.isMainThread))
            }
        }

        #expect(outcome.0 == true)
        #expect(outcome.1 == false)
        #expect(outcome.2 == nil)
        #expect(outcome.3 == nil)
        #expect(outcome.4 == true, "completion must be invoked on the main thread")
    }

    @Test func shareReturnsFailureOnRepositoryError() async throws {
        let repo = MockShareRepository()
        repo.shouldFail = true
        repo.errorToThrow = .noRootViewController
        let manager = IosShareManager(repository: repo)

        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Bool, Bool, String?, String?, Bool), Error>) in
            manager.share(content: makeContent()) { isSuccess, completed, activityType, errorMessage in
                continuation.resume(returning: (isSuccess, completed, activityType, errorMessage, Thread.isMainThread))
            }
        }

        #expect(outcome.0 == false)
        #expect(outcome.1 == false)
        #expect(outcome.2 == nil)
        #expect(outcome.3 != nil)
        #expect(outcome.4 == true, "completion must be invoked on the main thread")
    }
}
