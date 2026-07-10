//
//  UnityIosShareManagerTests.swift
//  UnityIosPluginTests
//

import Testing
@testable import UnityIosPlugin

struct UnityIosShareManagerTests {

    @Test func shareWithInvalidJsonInvokesHandlerOnMainThreadWithError() async throws {
        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<(Bool, Bool, String?, String?, Bool), Error>) in
            UnityIosShareManager.shared.share(contentJson: "not-json") { isSuccess, completed, activityType, errorMessage in
                continuation.resume(returning: (isSuccess, completed, activityType, errorMessage, Thread.isMainThread))
            }
        }

        #expect(outcome.0 == false)
        #expect(outcome.1 == false)
        #expect(outcome.2 == nil)
        #expect(outcome.3 == "Invalid share content JSON.")
        #expect(outcome.4 == true, "handler must be invoked on the main thread")
    }
}
