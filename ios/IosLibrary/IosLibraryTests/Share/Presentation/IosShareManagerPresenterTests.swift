//
//  IosShareManagerPresenterTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
import UIKit
@testable import IosLibrary

/// UT-13: the share manager's `presenter` forms (S-P18) and what the form from before 1b reports
/// for the new ends. The eight tests of `IosShareManagerTests` keep the values of the form from
/// before 1b.
@MainActor
struct IosShareManagerPresenterTests {

    private let content = ShareContent(items: [.text("hello")])

    /// The callback form from before 1b, once, with whether it came on the main thread.
    private func legacyShare(_ manager: IosShareManager, _ content: ShareContent) async -> (Bool, Bool, String?, String?, Bool) {
        await withCheckedContinuation { continuation in
            manager.share(content: content) { isSuccess, completed, activityType, errorMessage in
                continuation.resume(returning: (isSuccess, completed, activityType, errorMessage, Thread.isMainThread))
            }
        }
    }

    // MARK: - Which presenter reaches the repository

    @Test func theFormFromBefore1bUsesFirstActiveScene() async {
        let repo = MockShareRepository()
        _ = await legacyShare(IosShareManager(repository: repo), content)
        #expect(repo.presenters == ["firstActiveScene"])
    }

    @Test func theResultFormPassesThePresenterOn() async {
        let repo = MockShareRepository()
        let manager = IosShareManager(repository: repo)
        for selection in [PresenterSelection.foreground, .viewController { nil }, .firstActiveScene] {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                manager.share(content: content, presenter: selection) { _ in continuation.resume() }
            }
        }
        #expect(repo.presenters == ["foreground", "viewController", "firstActiveScene"])
    }

    @Test func theAsyncFormDefaultsToFirstActiveSceneAndPassesThePresenterOn() async throws {
        let repo = MockShareRepository()
        let manager = IosShareManager(repository: repo)
        try await manager.share(content: content)
        try await manager.share(content: content, presenter: .foreground)
        #expect(repo.presenters == ["firstActiveScene", "foreground"])
    }

    // MARK: - The result form

    @Test func theResultFormReportsTheResult() async {
        let repo = MockShareRepository()
        repo.stubbedResult = ShareResult(completed: true, activityType: "com.apple.UIKit.activity.Mail")
        let manager = IosShareManager(repository: repo)
        let results = MainRecorder<Result<ShareResult, ShareError>>()
        let returned = MainRecorder<Bool>()
        manager.share(content: content, presenter: .foreground) { result in
            #expect(returned.values == [true], "never inside the call")
            results.record(result)
        }
        returned.record(true)
        #expect(await waitUntil { results.values.count == 1 })
        guard case .success(let result)? = results.values.first else {
            Issue.record("expected a result: \(results.values)")
            return
        }
        #expect(result.completed)
        #expect(result.activityType == "com.apple.UIKit.activity.Mail")
        #expect(results.allOnMainThread)
    }

    @Test func theResultFormReportsEveryShareError() async {
        let errors: [ShareError] = [
            .noRootViewController, .notForeground, .presentationFailed, .dismissedBySystem,
            .activityFailed(FailureDetail(domain: "D", code: 3)), .invalidURL("u"), .imageLoadFailed(path: "/i"),
            .fileNotFound(path: "/f"),
        ]
        for error in errors {
            let repo = MockShareRepository()
            repo.shouldFail = true
            repo.errorToThrow = error
            let results = MainRecorder<Result<ShareResult, ShareError>>()
            IosShareManager(repository: repo).share(content: content, presenter: .foreground) { results.record($0) }
            #expect(await waitUntil { results.values.count == 1 })
            #expect(results.names == [failed(error)])
        }
    }

    @Test func theResultFormFailsWithoutItemsBeforeTheRepository() async {
        let repo = MockShareRepository()
        let results = MainRecorder<Result<ShareResult, ShareError>>()
        IosShareManager(repository: repo).share(content: ShareContent(items: []), presenter: .foreground) { results.record($0) }
        #expect(await waitUntil { results.values.count == 1 })
        #expect(results.names == [failed(.noValidItems)])
        #expect(repo.presentCallCount == 0)
    }

    /// Only a test repository can throw another error: the result form reports it as
    /// `presentationFailed`, the async form rethrows it as it is.
    @Test func anErrorThatIsNotAShareError() async {
        struct Other: Error {}
        let repo = MockShareRepository()
        repo.otherErrorToThrow = Other()
        let manager = IosShareManager(repository: repo)
        let results = MainRecorder<Result<ShareResult, ShareError>>()
        manager.share(content: content, presenter: .foreground) { results.record($0) }
        #expect(await waitUntil { results.values.count == 1 })
        #expect(results.names == [failed(.presentationFailed)])
        await #expect(throws: Other.self) {
            try await manager.share(content: content, presenter: .foreground)
        }
    }

    @Test func theResultFormFromABackgroundThreadDeliversOnTheMainThread() async {
        let manager = IosShareManager(repository: MockShareRepository())
        let content = content
        let onMain = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            DispatchQueue.global().async {
                manager.share(content: content, presenter: .foreground) { _ in
                    continuation.resume(returning: Thread.isMainThread)
                }
            }
        }
        #expect(onMain)
    }

    @Test func theAsyncFormThrowsTheShareError() async {
        let repo = MockShareRepository()
        repo.shouldFail = true
        repo.errorToThrow = .dismissedBySystem
        await #expect(throws: ShareError.dismissedBySystem) {
            try await IosShareManager(repository: repo).share(content: content, presenter: .foreground)
        }
    }

    // MARK: - The form from before 1b (3.3)

    /// The new ends reach the form from before 1b as fixed messages.
    @Test func theFormFromBefore1bReportsTheNewEndsWithFixedMessages() async {
        for (error, message) in [(ShareError.presentationFailed, "Failed to present the share sheet."),
                                 (.dismissedBySystem, "The share sheet was dismissed without a result."),
                                 (.activityFailed(FailureDetail(domain: "D", code: 1)), "The share activity failed."),
                                 (.noRootViewController, "No root view controller available to present the share sheet.")] {
            let repo = MockShareRepository()
            repo.shouldFail = true
            repo.errorToThrow = error
            let outcome = await legacyShare(IosShareManager(repository: repo), content)
            #expect(outcome.0 == false)
            #expect(outcome.1 == false)
            #expect(outcome.2 == nil)
            #expect(outcome.3 == message)
            #expect(outcome.4)
        }
    }

    // MARK: - Through the library's presenter, on the host app

    /// 3.3: a sheet dismissed from outside, which calls no handler, now reports once: the form
    /// from before 1b with `(false, false, nil, <fixed>)`, the result form with
    /// `dismissedBySystem` (before 1b nothing came).
    @Test func aSheetDismissedFromOutsideReportsOnceThroughBothForms() async throws {
        try await withHostWindow { host in
            let sheets = SheetRecorder()
            let manager = IosShareManager(repository: ShareRepositoryImpl(presenter: ShareSheetPresenter.recording(into: sheets)))

            let legacy = MainRecorder<[String?]>()
            manager.share(content: content) { isSuccess, completed, activityType, errorMessage in
                legacy.record(["\(isSuccess)", "\(completed)", activityType, errorMessage])
            }
            #expect(await waitUntil { sheets.last?.presentingViewController != nil && sheets.last?.isBeingPresented == false })
            host.root.dismiss(animated: true)
            #expect(await waitUntil(timeout: 10) { legacy.values.count == 1 })
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(legacy.values == [["false", "false", nil, "The share sheet was dismissed without a result."]])
            #expect(legacy.allOnMainThread)

            let results = MainRecorder<Result<ShareResult, ShareError>>()
            manager.share(content: content, presenter: .foreground) { results.record($0) }
            #expect(await waitUntil { sheets.count == 2 && sheets.last?.presentingViewController != nil && sheets.last?.isBeingPresented == false })
            host.root.dismiss(animated: true)
            #expect(await waitUntil(timeout: 10) { results.values.count == 1 })
            try await Task.sleep(nanoseconds: 300_000_000)
            #expect(results.names == [failed(.dismissedBySystem)])
        }
    }

    /// The form from before 1b through the library's presenter: the handler's result keeps its
    /// values (`(true, completed, activityType, nil)`).
    @Test func theFormFromBefore1bReportsTheHandlersResult() async throws {
        try await withHostWindow { _ in
            let sheets = SheetRecorder()
            let manager = IosShareManager(repository: ShareRepositoryImpl(presenter: ShareSheetPresenter.recording(into: sheets)))
            let legacy = MainRecorder<[String?]>()
            manager.share(content: content) { isSuccess, completed, activityType, errorMessage in
                legacy.record(["\(isSuccess)", "\(completed)", activityType, errorMessage])
            }
            #expect(await waitUntil { sheets.last?.presentingViewController != nil && sheets.last?.isBeingPresented == false })
            sheets.last?.completionWithItemsHandler?(.copyToPasteboard, true, nil, nil)
            #expect(await waitUntil { legacy.values.count == 1 })
            #expect(legacy.values == [["true", "true", UIActivity.ActivityType.copyToPasteboard.rawValue, nil]])
        }
    }
}
