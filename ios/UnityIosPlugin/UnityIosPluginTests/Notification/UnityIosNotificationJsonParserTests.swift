//
//  UnityIosNotificationJsonParserTests.swift
//  UnityIosPluginTests
//

import Testing
@testable import UnityIosPlugin

struct UnityIosNotificationJsonParserTests {

    private let parser = UnityIosNotificationJsonParser()

    // MARK: - parseContent: required fields

    @Test func parseContentWithRequiredFields() {
        let json = #"{"id":"n1","title":"Hello"}"#
        let result = parser.parseContent(from: json)
        #expect(result != nil)
        #expect(result?.id == "n1")
        #expect(result?.title == "Hello")
    }

    @Test func parseContentMissingIdReturnsNil() {
        let json = #"{"title":"Hello"}"#
        #expect(parser.parseContent(from: json) == nil)
    }

    @Test func parseContentMissingTitleReturnsNil() {
        let json = #"{"id":"n1"}"#
        #expect(parser.parseContent(from: json) == nil)
    }

    @Test func parseContentInvalidJsonReturnsNil() {
        #expect(parser.parseContent(from: "not-json") == nil)
    }

    // MARK: - parseContent: optional fields

    @Test func parseContentWithAllOptionalFields() {
        let json = #"""
        {
            "id": "n1",
            "title": "T",
            "subtitle": "S",
            "body": "B",
            "badge": 3,
            "sound": "default",
            "categoryIdentifier": "cat1",
            "interruptionLevel": "timeSensitive",
            "threadIdentifier": "thread1",
            "targetContentIdentifier": "target1",
            "relevanceScore": 0.8,
            "filterCriteria": "filter1",
            "userInfo": {"key": "value"}
        }
        """#
        let result = parser.parseContent(from: json)
        #expect(result?.subtitle == "S")
        #expect(result?.body == "B")
        #expect(result?.badge == 3)
        #expect(result?.categoryIdentifier == "cat1")
        #expect(result?.threadIdentifier == "thread1")
        #expect(result?.targetContentIdentifier == "target1")
        #expect(result?.relevanceScore == 0.8)
        #expect(result?.filterCriteria == "filter1")
        #expect(result?.userInfo["key"] as? String == "value")
    }

    // MARK: - parseContent: sound

    @Test func parseContentSoundDefault() {
        let json = #"{"id":"n1","title":"T","sound":"default"}"#
        if case .default = parser.parseContent(from: json)?.sound { } else {
            Issue.record("Expected .default sound")
        }
    }

    @Test func parseContentSoundDefaultCritical() {
        let json = #"{"id":"n1","title":"T","sound":"defaultCritical"}"#
        if case .defaultCritical = parser.parseContent(from: json)?.sound { } else {
            Issue.record("Expected .defaultCritical sound")
        }
    }

    @Test func parseContentSoundCustomName() {
        let json = #"{"id":"n1","title":"T","sound":"mySound"}"#
        if case .named(let name) = parser.parseContent(from: json)?.sound {
            #expect(name == "mySound")
        } else {
            Issue.record("Expected .named sound")
        }
    }

    @Test func parseContentNoSoundDefaultsToDefault() {
        let json = #"{"id":"n1","title":"T"}"#
        if case .default = parser.parseContent(from: json)?.sound { } else {
            Issue.record("Expected .default sound when omitted")
        }
    }

    // MARK: - parseContent: interruptionLevel

    @Test func parseContentInterruptionLevelPassive() {
        let json = #"{"id":"n1","title":"T","interruptionLevel":"passive"}"#
        #expect(parser.parseContent(from: json)?.interruptionLevel == .passive)
    }

    @Test func parseContentInterruptionLevelActive() {
        let json = #"{"id":"n1","title":"T","interruptionLevel":"active"}"#
        #expect(parser.parseContent(from: json)?.interruptionLevel == .active)
    }

    @Test func parseContentInterruptionLevelTimeSensitive() {
        let json = #"{"id":"n1","title":"T","interruptionLevel":"timeSensitive"}"#
        #expect(parser.parseContent(from: json)?.interruptionLevel == .timeSensitive)
    }

    @Test func parseContentInterruptionLevelCritical() {
        let json = #"{"id":"n1","title":"T","interruptionLevel":"critical"}"#
        #expect(parser.parseContent(from: json)?.interruptionLevel == .critical)
    }

    @Test func parseContentUnknownInterruptionLevelFallsBackToActive() {
        let json = #"{"id":"n1","title":"T","interruptionLevel":"unknown"}"#
        #expect(parser.parseContent(from: json)?.interruptionLevel == .active)
    }

    @Test func parseContentNoInterruptionLevelIsNil() {
        let json = #"{"id":"n1","title":"T"}"#
        #expect(parser.parseContent(from: json)?.interruptionLevel == nil)
    }

    // MARK: - parseTrigger: nil input

    @Test func parseTriggerNilReturnsNil() {
        #expect(parser.parseTrigger(from: nil) == nil)
    }

    @Test func parseTriggerInvalidJsonReturnsNil() {
        #expect(parser.parseTrigger(from: "not-json") == nil)
    }

    @Test func parseTriggerUnknownTypeReturnsNil() {
        let json = #"{"type":"unknown"}"#
        #expect(parser.parseTrigger(from: json) == nil)
    }

    // MARK: - parseTrigger: timeInterval

    @Test func parseTriggerTimeInterval() {
        let json = #"{"type":"timeInterval","interval":30.0,"repeats":true}"#
        if case .timeInterval(let interval, let repeats) = parser.parseTrigger(from: json) {
            #expect(interval == 30.0)
            #expect(repeats == true)
        } else {
            Issue.record("Expected .timeInterval trigger")
        }
    }

    @Test func parseTriggerTimeIntervalDefaultsRepeatsToFalse() {
        let json = #"{"type":"timeInterval","interval":10.0}"#
        if case .timeInterval(_, let repeats) = parser.parseTrigger(from: json) {
            #expect(repeats == false)
        } else {
            Issue.record("Expected .timeInterval trigger")
        }
    }

    @Test func parseTriggerTimeIntervalMissingIntervalReturnsNil() {
        let json = #"{"type":"timeInterval"}"#
        #expect(parser.parseTrigger(from: json) == nil)
    }

    // MARK: - parseTrigger: calendar

    @Test func parseTriggerCalendar() {
        let json = #"{"type":"calendar","year":2026,"month":5,"day":4,"hour":10,"minute":30,"second":0,"repeats":false}"#
        if case .calendar(let components, let repeats) = parser.parseTrigger(from: json) {
            #expect(components.year == 2026)
            #expect(components.month == 5)
            #expect(components.day == 4)
            #expect(components.hour == 10)
            #expect(components.minute == 30)
            #expect(components.second == 0)
            #expect(repeats == false)
        } else {
            Issue.record("Expected .calendar trigger")
        }
    }

    @Test func parseTriggerCalendarPartialComponents() {
        let json = #"{"type":"calendar","hour":9,"minute":0}"#
        if case .calendar(let components, _) = parser.parseTrigger(from: json) {
            #expect(components.hour == 9)
            #expect(components.minute == 0)
            #expect(components.year == nil)
        } else {
            Issue.record("Expected .calendar trigger")
        }
    }

    // MARK: - parseTrigger: location

    @Test func parseTriggerLocation() {
        let json = #"{"type":"location","identifier":"home","latitude":35.6,"longitude":139.7,"radius":100.0,"notifyOnEntry":true,"notifyOnExit":false}"#
        if case .location(let id, let lat, let lon, let radius, let entry, let exit) = parser.parseTrigger(from: json) {
            #expect(id == "home")
            #expect(lat == 35.6)
            #expect(lon == 139.7)
            #expect(radius == 100.0)
            #expect(entry == true)
            #expect(exit == false)
        } else {
            Issue.record("Expected .location trigger")
        }
    }

    @Test func parseTriggerLocationDefaultsEntryExitFlags() {
        let json = #"{"type":"location","identifier":"work","latitude":35.0,"longitude":139.0,"radius":50.0}"#
        if case .location(_, _, _, _, let entry, let exit) = parser.parseTrigger(from: json) {
            #expect(entry == true)
            #expect(exit == false)
        } else {
            Issue.record("Expected .location trigger")
        }
    }

    @Test func parseTriggerLocationMissingRequiredFieldReturnsNil() {
        let json = #"{"type":"location","latitude":35.0,"longitude":139.0,"radius":50.0}"#
        #expect(parser.parseTrigger(from: json) == nil)
    }

    // MARK: - parseCategory: required fields

    @Test func parseCategoryWithIdentifier() {
        let json = #"{"identifier":"cat1"}"#
        let result = parser.parseCategory(from: json)
        #expect(result?.identifier == "cat1")
        #expect(result?.actions.isEmpty == true)
        #expect(result?.textInputActions.isEmpty == true)
    }

    @Test func parseCategoryMissingIdentifierReturnsNil() {
        let json = #"{"options":[]}"#
        #expect(parser.parseCategory(from: json) == nil)
    }

    @Test func parseCategoryInvalidJsonReturnsNil() {
        #expect(parser.parseCategory(from: "not-json") == nil)
    }

    // MARK: - parseCategory: actions

    @Test func parseCategoryWithActions() {
        let json = #"""
        {
            "identifier": "cat1",
            "actions": [
                {"identifier": "ok", "title": "OK", "options": ["foreground"]},
                {"identifier": "cancel", "title": "Cancel", "options": ["destructive"]}
            ]
        }
        """#
        let result = parser.parseCategory(from: json)
        #expect(result?.actions.count == 2)
        #expect(result?.actions[0].identifier == "ok")
        #expect(result?.actions[0].options.contains(.foreground) == true)
        #expect(result?.actions[1].identifier == "cancel")
        #expect(result?.actions[1].options.contains(.destructive) == true)
    }

    @Test func parseCategoryActionMissingRequiredFieldIsSkipped() {
        let json = #"""
        {
            "identifier": "cat1",
            "actions": [
                {"title": "NoId"},
                {"identifier": "ok", "title": "OK"}
            ]
        }
        """#
        let result = parser.parseCategory(from: json)
        #expect(result?.actions.count == 1)
        #expect(result?.actions[0].identifier == "ok")
    }

    @Test func parseCategoryActionAllOptions() {
        let json = #"""
        {
            "identifier": "cat1",
            "actions": [
                {"identifier": "a", "title": "A", "options": ["authenticationRequired","destructive","foreground"]}
            ]
        }
        """#
        let action = parser.parseCategory(from: json)?.actions.first
        #expect(action?.options.contains(.authenticationRequired) == true)
        #expect(action?.options.contains(.destructive) == true)
        #expect(action?.options.contains(.foreground) == true)
    }

    // MARK: - parseCategory: textInputActions

    @Test func parseCategoryWithTextInputActions() {
        let json = #"""
        {
            "identifier": "cat1",
            "textInputActions": [
                {
                    "identifier": "reply",
                    "title": "Reply",
                    "buttonTitle": "Send",
                    "textInputPlaceholder": "Type here"
                }
            ]
        }
        """#
        let result = parser.parseCategory(from: json)
        #expect(result?.textInputActions.count == 1)
        #expect(result?.textInputActions[0].identifier == "reply")
        #expect(result?.textInputActions[0].buttonTitle == "Send")
        #expect(result?.textInputActions[0].textInputPlaceholder == "Type here")
    }

    @Test func parseCategoryTextInputActionMissingRequiredFieldIsSkipped() {
        let json = #"""
        {
            "identifier": "cat1",
            "textInputActions": [
                {"identifier": "reply", "title": "Reply", "buttonTitle": "Send"}
            ]
        }
        """#
        #expect(parser.parseCategory(from: json)?.textInputActions.isEmpty == true)
    }

    // MARK: - parseCategory: options

    @Test func parseCategoryOptions() {
        let json = #"""
        {
            "identifier": "cat1",
            "options": ["customDismissAction", "allowInCarPlay", "hiddenPreviewsShowTitle", "allowAnnouncement"]
        }
        """#
        let opts = parser.parseCategory(from: json)?.options
        #expect(opts?.contains(.customDismissAction) == true)
        #expect(opts?.contains(.allowInCarPlay) == true)
        #expect(opts?.contains(.hiddenPreviewsShowTitle) == true)
        #expect(opts?.contains(.allowAnnouncement) == true)
    }

    @Test func parseCategoryNoOptionsIsEmpty() {
        let json = #"{"identifier":"cat1"}"#
        #expect(parser.parseCategory(from: json)?.options.isEmpty == true)
    }

    // MARK: - parseContent: attachments

    @Test func parseContentWithAttachments() {
        let json = #"""
        {
            "id": "n1",
            "title": "T",
            "attachments": [
                {"identifier": "img-1", "fileURL": "file:///tmp/image.png"},
                {"identifier": "img-2", "fileURL": "file:///tmp/image2.jpg"}
            ]
        }
        """#
        let result = parser.parseContent(from: json)
        #expect(result?.attachments.count == 2)
        #expect(result?.attachments[0].identifier == "img-1")
        #expect(result?.attachments[0].fileURL == URL(string: "file:///tmp/image.png"))
        #expect(result?.attachments[1].identifier == "img-2")
    }

    @Test func parseContentAttachmentMissingIdentifierIsSkipped() {
        let json = #"""
        {
            "id": "n1",
            "title": "T",
            "attachments": [
                {"fileURL": "file:///tmp/image.png"},
                {"identifier": "img-2", "fileURL": "file:///tmp/image2.jpg"}
            ]
        }
        """#
        let result = parser.parseContent(from: json)
        #expect(result?.attachments.count == 1)
        #expect(result?.attachments[0].identifier == "img-2")
    }

    @Test func parseContentAttachmentMissingFileURLIsSkipped() {
        let json = #"""
        {
            "id": "n1",
            "title": "T",
            "attachments": [
                {"identifier": "img-1"},
                {"identifier": "img-2", "fileURL": "file:///tmp/image2.jpg"}
            ]
        }
        """#
        let result = parser.parseContent(from: json)
        #expect(result?.attachments.count == 1)
        #expect(result?.attachments[0].identifier == "img-2")
    }

    @Test func parseContentNoAttachmentsIsEmpty() {
        let json = #"{"id":"n1","title":"T"}"#
        #expect(parser.parseContent(from: json)?.attachments.isEmpty == true)
    }
}
