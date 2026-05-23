//
//  UnityMacNotificationJsonParserTests.swift
//  UnityMacPluginTests
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Testing
@testable import UnityMacPlugin
import MacLibrary

struct UnityMacNotificationJsonParserTests {

    let parser = UnityMacNotificationJsonParser()

    // MARK: - parseContent: success

    @Test func parseContentSuccessWithAllFields() {
        let json = "{\"id\":\"notif-1\",\"title\":\"Hello\",\"body\":\"World\",\"subtitle\":\"Sub\",\"categoryIdentifier\":\"cat-1\",\"badge\":3}"
        let result = parser.parseContent(json)
        guard case .success(let content) = result else {
            Issue.record("Expected success")
            return
        }
        #expect(content.id == "notif-1")
        #expect(content.title == "Hello")
        #expect(content.body == "World")
        #expect(content.subtitle == "Sub")
        #expect(content.categoryIdentifier == "cat-1")
        #expect(content.badge == 3)
    }

    @Test func parseContentCategoryIdentifierIsNilWhenAbsent() {
        let json = "{\"id\":\"n1\",\"title\":\"T\"}"
        let result = parser.parseContent(json)
        if case .success(let content) = result {
            #expect(content.categoryIdentifier == nil)
        } else {
            Issue.record("Expected success")
        }
    }

    @Test func parseContentSuccessWithMinimalFields() {
        let json = "{\"id\":\"n1\",\"title\":\"T\"}"
        let result = parser.parseContent(json)
        if case .success(let content) = result {
            #expect(content.id == "n1")
            #expect(content.body == nil)
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - parseContent: failure

    @Test func parseContentFailsOnInvalidJson() {
        let result = parser.parseContent("not json")
        guard case .failure(let e) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(e.errorCode == 1301)
    }

    @Test func parseContentFailsOnMissingId() {
        let result = parser.parseContent("{\"title\":\"Hi\"}")
        guard case .failure(let e) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(e.errorCode == 1301)
    }

    @Test func parseContentFailsOnMissingTitle() {
        let result = parser.parseContent("{\"id\":\"n1\"}")
        guard case .failure(let e) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(e.errorCode == 1301)
    }

    // MARK: - parseTrigger: success

    @Test func parseTriggerImmediateSuccess() {
        let result = parser.parseTrigger("{\"type\":\"immediate\"}")
        if case .success(let trigger) = result {
            if case .immediate = trigger {} else { Issue.record("Expected immediate") }
        } else {
            Issue.record("Expected success")
        }
    }

    @Test func parseTriggerTimeIntervalSuccess() {
        let result = parser.parseTrigger("{\"type\":\"timeInterval\",\"seconds\":30.0,\"repeats\":false}")
        if case .success(let trigger) = result {
            if case .timeInterval(let seconds, let repeats) = trigger {
                #expect(seconds == 30.0)
                #expect(repeats == false)
            } else {
                Issue.record("Expected timeInterval")
            }
        } else {
            Issue.record("Expected success")
        }
    }

    @Test func parseTriggerCalendarSuccess() {
        let result = parser.parseTrigger("{\"type\":\"calendar\",\"hour\":9,\"minute\":0,\"repeats\":true}")
        if case .success(let trigger) = result {
            if case .calendar(let components, let repeats) = trigger {
                #expect(components.hour == 9)
                #expect(components.minute == 0)
                #expect(repeats == true)
            } else {
                Issue.record("Expected calendar")
            }
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - parseTrigger: failure

    @Test func parseTriggerFailsOnUnknownType() {
        let result = parser.parseTrigger("{\"type\":\"weekly\"}")
        guard case .failure(let e) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(e.errorCode == 1301)
    }

    @Test func parseTriggerTimeIntervalFailsWithoutSeconds() {
        let result = parser.parseTrigger("{\"type\":\"timeInterval\"}")
        guard case .failure(let e) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(e.errorCode == 1301)
    }

    // MARK: - parseCategory: success

    @Test func parseCategorySuccessWithActions() {
        let json = "{\"id\":\"cat-1\",\"actions\":[{\"id\":\"act-1\",\"title\":\"OK\",\"isForeground\":false,\"isTextInput\":false}]}"
        let result = parser.parseCategory(json)
        if case .success(let category) = result {
            #expect(category.id == "cat-1")
            #expect(category.actions.count == 1)
            #expect(category.actions[0].id == "act-1")
        } else {
            Issue.record("Expected success")
        }
    }

    // MARK: - parseCategory: failure

    @Test func parseCategoryFailsOnMissingId() {
        let result = parser.parseCategory("{\"actions\":[]}")
        guard case .failure(let e) = result else {
            Issue.record("Expected failure")
            return
        }
        #expect(e.errorCode == 1301)
    }

    // MARK: - toJson(scheduled:)

    @Test func toJsonScheduledReturnsValidArray() {
        let notifications = [
              ScheduledNotification(identifier: "s1", title: "A", body: "B", trigger: nil),
              ScheduledNotification(identifier: "s2", title: "C", body: nil, trigger: nil)
        ]
        let json = parser.toJson(scheduled: notifications)
        #expect(json.contains("s1"))
        #expect(json.contains("A"))
        #expect(json.contains("B"))
        #expect(json.contains("s2"))
    }

    @Test func toJsonScheduledEmptyReturnsEmptyArray() {
        let json = parser.toJson(scheduled: [])
        #expect(json == "[]")
    }

    // MARK: - toJson(status:)

    @Test func toJsonStatusAuthorized() {
        let json = parser.toJson(status: .authorized)
        #expect(json.contains("authorized"))
    }

    @Test func toJsonStatusDenied() {
        let json = parser.toJson(status: .denied)
        #expect(json.contains("denied"))
    }

    @Test func toJsonStatusUnsupported() {
        let json = parser.toJson(status: .unsupported)
        #expect(json.contains("unsupported"))
    }
}
