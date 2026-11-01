//
//  IosNotificationManagerCallFormTests.swift
//  IosLibraryTests
//
//  UT-31 (design 13.1, S-P26): the call forms from before 1b that still compile. 1b added
//  `async` forms with the same names, so a call that leaves out `completion` in an `async`
//  context now selects the `async` form and no longer compiles without `await` (and `try`). The
//  forms that stop compiling are listed in design 3.3 and the stage 1b result (checked with
//  `swiftc -typecheck`, T-21). The forms in this file keep compiling: removing the `= nil`
//  default of a `completion` breaks the build of this file.
//

import Foundation
import Testing
@testable import IosLibrary

@MainActor
struct IosNotificationManagerCallFormTests {

    /// Nonisolated, so each content is a new value that the `sending` parameter can take.
    private nonisolated static func makeContent() -> NotificationContent {
        NotificationContent(id: "ut31", title: "t")
    }

    private let category = NotificationCategory(identifier: "ut31")

    /// In an `async` function, the forms with `completion` written select the callback form. Also
    /// holds `show(content:)` without a trigger, which pins that the `async` form's `trigger` has
    /// no default (SR2-7): with a default, this call would select the `async` form and stop
    /// compiling.
    @Test func inAnAsyncContextTheFormsWithACompletionRunTheCallbackForm() async {
        let repo = MockNotificationRepository()
        let manager = IosNotificationManager(repository: repo)
        let done = MainRecorder<String>()

        manager.setBadgeCount(1, completion: { _, _ in done.record("setBadgeCount") })
        manager.show(content: Self.makeContent(), trigger: nil, completion: { _, _ in done.record("show") })
        manager.update(identifier: "ut31", content: Self.makeContent(), trigger: nil, completion: { _, _ in done.record("update") })
        manager.schedule(content: Self.makeContent(), trigger: .timeInterval(60, repeats: false), identifier: "ut31",
                         completion: { _, _ in done.record("schedule") })
        manager.requestPermission(options: [.alert], completion: { _, _ in done.record("requestPermission") })
        manager.registerCategory(category, completion: { done.record("registerCategory") })
        manager.removeCategory(identifier: "ut31", completion: { done.record("removeCategory") })
        // `show(content:)` without a trigger has no `async` form to select (design 3.3).
        manager.show(content: Self.makeContent())

        #expect(await waitUntil { done.values.count == 7 })
        #expect(Set(done.values) == ["setBadgeCount", "show", "update", "schedule", "requestPermission",
                                     "registerCategory", "removeCategory"])
        #expect(done.allOnMainThread)
        #expect(await waitUntil { repo.showCallCount == 2 })
        #expect(repo.setBadgeCountCallCount == 1)
        #expect(repo.updateCallCount == 1)
        #expect(repo.scheduleCallCount == 1)
        #expect(repo.requestPermissionCallCount == 1)
        #expect(repo.registerCategoryCallCount == 1)
        #expect(repo.removeCategoryCallCount == 1)
    }

    /// In a synchronous closure, the forms without `completion` still select the callback form,
    /// also inside an `async` test (the closure itself is not `async`).
    @Test func inASynchronousContextTheFormsWithoutACompletionStillCompile() async {
        let repo = MockNotificationRepository()
        let manager = IosNotificationManager(repository: repo)

        let callTheExistingForms = {
            manager.setBadgeCount(2)
            manager.show(content: Self.makeContent(), trigger: nil)
            manager.update(identifier: "ut31", content: Self.makeContent(), trigger: nil)
            manager.schedule(content: Self.makeContent(), trigger: .timeInterval(60, repeats: false), identifier: "ut31")
            manager.requestPermission()
            manager.requestPermission(options: [.alert])
            manager.openNotificationSettings()
            manager.registerCategory(self.category)
            manager.removeCategory(identifier: "ut31")
        }
        callTheExistingForms()

        #expect(await waitUntil {
            repo.setBadgeCountCallCount == 1 && repo.showCallCount == 1 && repo.updateCallCount == 1
                && repo.scheduleCallCount == 1 && repo.requestPermissionCallCount == 2 && repo.openSettingsCallCount == 1
                && repo.registerCategoryCallCount == 1 && repo.removeCategoryCallCount == 1
        })
        #expect(repo.setBadgeCountCallCount == 1)
        #expect(repo.showCallCount == 1)
        #expect(repo.updateCallCount == 1)
        #expect(repo.scheduleCallCount == 1)
        #expect(repo.requestPermissionCallCount == 2)
        #expect(repo.openSettingsCallCount == 1)
        #expect(repo.registerCategoryCallCount == 1)
        #expect(repo.removeCategoryCallCount == 1)
    }
}
