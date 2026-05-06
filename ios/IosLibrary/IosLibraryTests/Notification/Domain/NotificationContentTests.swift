//
//  NotificationContentTests.swift
//  IosLibraryTests
//

import Testing
@testable import IosLibrary

struct NotificationContentTests {

    @Test func initializesWithRequiredFields() {
        let content = NotificationContent(id: "test-id", title: "Hello")
        #expect(content.id == "test-id")
        #expect(content.title == "Hello")
        #expect(content.subtitle == nil)
        #expect(content.body == nil)
        #expect(content.badge == nil)
        #expect(content.userInfo.isEmpty)
        #expect(content.attachments.isEmpty)
    }

    @Test func initializesWithAllFields() {
        let attachment = NotificationAttachment(identifier: "att1", fileURL: URL(string: "file:///test.png")!)
        let content = NotificationContent(
            id: "id1",
            title: "Title",
            subtitle: "Subtitle",
            body: "Body",
            badge: 3,
            sound: .named("custom"),
            categoryIdentifier: "cat1",
            interruptionLevel: .timeSensitive,
            threadIdentifier: "thread1",
            targetContentIdentifier: "target1",
            relevanceScore: 0.8,
            filterCriteria: "criteria",
            userInfo: ["key": "value"],
            attachments: [attachment]
        )
        #expect(content.subtitle == "Subtitle")
        #expect(content.badge == 3)
        #expect(content.categoryIdentifier == "cat1")
        #expect(content.relevanceScore == 0.8)
        #expect(content.attachments.count == 1)
    }

    @Test func notificationSoundEquality() {
        if case .default = NotificationSound.default { } else { Issue.record("Expected .default") }
        if case .defaultCritical = NotificationSound.defaultCritical { } else { Issue.record("Expected .defaultCritical") }
        if case .named(let name) = NotificationSound.named("alert") {
            #expect(name == "alert")
        } else {
            Issue.record("Expected .named")
        }
    }

    @Test func notificationCategoryOptionsAreOptionSet() {
        var opts: NotificationCategoryOptions = [.customDismissAction, .allowInCarPlay]
        #expect(opts.contains(.customDismissAction))
        #expect(opts.contains(.allowInCarPlay))
        #expect(!opts.contains(.hiddenPreviewsShowTitle))
        opts.insert(.allowAnnouncement)
        #expect(opts.contains(.allowAnnouncement))
    }
}
