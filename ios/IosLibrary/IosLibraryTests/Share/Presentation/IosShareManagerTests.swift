//
//  IosShareManagerTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

@MainActor
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

    // MARK: - Delivery from a background thread (migration README, plan C)

    // A second resume of a checked continuation traps, so each test also checks exactly-once.
    @Test func shareFromBackgroundThreadDeliversOnTheMainThread() async throws {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, activityType: "com.apple.UIKit.activity.Mail")
        let manager = IosShareManager(repository: repo)
        let content = makeContent()

        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Bool, Bool, Bool), Error>) in
            DispatchQueue.global().async {
                manager.share(content: content) { isSuccess, completed, _, _ in
                    continuation.resume(returning: (isSuccess, completed, Thread.isMainThread))
                }
            }
        }

        #expect(outcome.0 == true)
        #expect(outcome.1 == true)
        #expect(outcome.2 == true, "completion must be invoked on the main thread")
    }

    @Test func shareWithNoItemsFromBackgroundThreadFailsOnTheMainThread() async throws {
        let repo = MockShareRepository()
        let manager = IosShareManager(repository: repo)

        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Bool, String?, Bool), Error>) in
            DispatchQueue.global().async {
                manager.share(content: ShareContent(items: [])) { isSuccess, _, _, errorMessage in
                    continuation.resume(returning: (isSuccess, errorMessage, Thread.isMainThread))
                }
            }
        }

        #expect(outcome.0 == false)
        #expect(outcome.1 == ShareError.noValidItems.errorDescription)
        #expect(outcome.2 == true, "completion must be invoked on the main thread")
        #expect(repo.presentCallCount == 0)
    }

    @Test func shareWithoutCompletionDoesNotTrap() async throws {
        let repo = MockShareRepository()
        let manager = IosShareManager(repository: repo)

        manager.share(content: makeContent(), completion: nil)
        // The share runs in a main-actor task; wait (up to 5 s) until it has reached the repository.
        for _ in 0..<500 where repo.presentCallCount == 0 {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(repo.presentCallCount == 1)
    }

    // MARK: - async throws overload

    @Test func asyncShareReturnsResultOnSuccess() async throws {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, activityType: "com.apple.UIKit.activity.Mail")
        let manager = IosShareManager(repository: repo)

        let result = try await manager.share(content: makeContent())

        #expect(result.completed == true)
        #expect(result.activityType == "com.apple.UIKit.activity.Mail")
    }

    @Test func asyncShareThrowsOnFailure() async {
        let repo = MockShareRepository()
        repo.shouldFail = true
        repo.errorToThrow = .noRootViewController
        let manager = IosShareManager(repository: repo)

        await #expect(throws: ShareError.self) {
            try await manager.share(content: makeContent())
        }
    }
}
