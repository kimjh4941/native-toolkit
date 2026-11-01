//
//  NotificationRepositoryUserInfoCheckTests.swift
//  IosLibraryTests
//
//  UT-18 (design 13.1, 8.5.3, S-P15), the check part: `show`, `update` and `schedule` reject a
//  userInfo that is not a property list, first, after the reserved key and before anything is
//  removed (SR-9): a rejected `update` leaves the pending request. The system errors become
//  `FailureDetail` cases (S-P7).
//

import Foundation
import Testing
import UserNotifications
@testable import IosLibrary

/// Not a property-list value.
private final class NotAPropertyList: NSObject {}

struct NotificationRepositoryUserInfoCheckTests {

    private func content(_ identifier: String, userInfo: [String: Any]) -> NotificationContent {
        NotificationContent(id: identifier, title: "UT-18", body: "check", userInfo: userInfo)
    }

    /// The values that are not property-list values, also deep inside.
    private static var invalidUserInfos: [[String: Any]] { [
        ["object": NotAPropertyList()],
        ["null": NSNull()],
        ["url": URL(string: "https://example.com")!],
        ["nested": ["inner": ["deep": NotAPropertyList()]]],
        ["array": [1, "two", NSNull()]],
        ["intKeys": [1: "one"] as [Int: String]],
    ] }

    @Test func thePropertyListCheckAcceptsEveryPropertyListType() {
        let valid: [String: Any] = [
            "string": "s", "int": 1, "double": 1.5, "bool": true, "date": Date(timeIntervalSince1970: 0),
            "data": Data([1, 2]), "array": [1, "two", [3.0]], "dictionary": ["a": ["b": false]], "big": UInt64.max,
        ]
        #expect(NotificationRepositoryImpl.isPropertyList(valid))
        #expect(NotificationRepositoryImpl.isPropertyList([:]))
        for userInfo in Self.invalidUserInfos {
            #expect(!NotificationRepositoryImpl.isPropertyList(userInfo), "\(userInfo.keys)")
        }
    }

    /// `show` and `schedule` reject them and call nothing on the center.
    @Test func showAndScheduleRejectAUserInfoThatIsNotAPropertyList() async {
        for userInfo in Self.invalidUserInfos {
            let center = FakeRequestCenter()
            let repository = NotificationRepositoryImpl(requestCenter: center)
            await #expect(throws: NotificationError.invalidUserInfo) {
                try await repository.show(content: content("n", userInfo: userInfo), trigger: nil)
            }
            await #expect(throws: NotificationError.invalidUserInfo) {
                try await repository.schedule(content: content("n", userInfo: userInfo), trigger: .timeInterval(3600, repeats: false), identifier: "n")
            }
            #expect(center.calls.isEmpty, "\(userInfo.keys)")
        }
    }

    /// `update` rejects it before it removes the pending request (SR-9).
    @Test func updateWithAUserInfoThatIsNotAPropertyListLeavesThePendingRequest() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.schedule(content: content("u", userInfo: ["before": 1]), trigger: .timeInterval(3600, repeats: false), identifier: "u")

        await #expect(throws: NotificationError.invalidUserInfo) {
            try await repository.update(identifier: "u", content: content("u", userInfo: ["object": NotAPropertyList()]),
                                        trigger: .timeInterval(3600, repeats: false))
        }

        let kept = try #require(center.request("u"), "update removed the pending request before it checked the userInfo")
        #expect(kept.content.userInfo["before"] as? Int == 1)
        #expect(center.calls == ["add u"])
    }

    /// The reserved key is checked first: a userInfo with both is a reserved-key error.
    @Test func theReservedKeyIsCheckedBeforeThePropertyList() async {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        await #expect(throws: NotificationError.reservedUserInfoKey) {
            try await repository.show(content: content("n", userInfo: [NotificationMarker.key: 1, "object": NotAPropertyList()]), trigger: nil)
        }
        #expect(center.calls.isEmpty)
    }

    /// A property list passes, with the marker added.
    @Test func aPropertyListPasses() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.show(content: content("n", userInfo: ["nested": ["a": [1, 2.5, true, "s"]], "date": Date(timeIntervalSince1970: 1)]), trigger: nil)
        let request = try #require(center.request("n"))
        #expect(request.content.userInfo[NotificationMarker.key] as? Int == NotificationMarker.value)
        #expect(center.calls == ["add n"])
    }

    // MARK: - The system errors (S-P7)

    /// A failed `add` is `addRequestFailed` with the error's domain and code.
    @Test func aFailedAddKeepsTheDomainAndTheCode() async {
        let center = FakeRequestCenter()
        center.failAdding(with: NSError(domain: "UNErrorDomain", code: 7, userInfo: [NSLocalizedDescriptionKey: "secret"]))
        let repository = NotificationRepositoryImpl(requestCenter: center)
        let expected = NotificationError.addRequestFailed(FailureDetail(domain: "UNErrorDomain", code: 7))

        await #expect(throws: expected) {
            try await repository.show(content: content("n", userInfo: [:]), trigger: nil)
        }
        await #expect(throws: expected) {
            try await repository.update(identifier: "n", content: content("n", userInfo: [:]), trigger: nil)
        }
        await #expect(throws: expected) {
            try await repository.schedule(content: content("n", userInfo: [:]), trigger: .timeInterval(60, repeats: false), identifier: "n")
        }
    }

    /// A file whose type the system does not take as an attachment (written to the temporary
    /// directory; the caller removes it).
    private func makeUnusableAttachmentFile() throws -> URL {
        let unusable = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ut18-\(UUID().uuidString).ut18unknown")
        try Data([0x00, 0x01, 0x02]).write(to: unusable)
        return unusable
    }

    /// An attachment that cannot be made (a file type the system rejects; a missing file is not
    /// reported by the system in the test host) is `attachmentLoadFailed` with its identifier and
    /// the domain and code; nothing is added.
    @Test func anAttachmentOfAFileTypeTheSystemRejectsKeepsItsIdentifierAndTheDetail() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        let unusable = try makeUnusableAttachmentFile()
        defer { try? FileManager.default.removeItem(at: unusable) }
        let content = NotificationContent(id: "n", title: "UT-18", attachments: [NotificationAttachment(identifier: "icon", fileURL: unusable)])

        do {
            try await repository.show(content: content, trigger: nil)
            Issue.record("the attachment was accepted")
        } catch let NotificationError.attachmentLoadFailed(identifier, detail) {
            #expect(identifier == "icon")
            #expect(detail.domain == UNErrorDomain)
        }
        #expect(center.calls.isEmpty)
    }

    /// `update` makes the content, with its attachments, before it removes the pending request:
    /// an attachment the system rejects leaves the pending request (the order before C6 removed
    /// it first).
    @Test func updateWithAnAttachmentTheSystemRejectsLeavesThePendingRequest() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.schedule(content: content("u", userInfo: ["before": 1]), trigger: .timeInterval(3600, repeats: false), identifier: "u")
        let unusable = try makeUnusableAttachmentFile()
        defer { try? FileManager.default.removeItem(at: unusable) }
        let replacement = NotificationContent(id: "u", title: "UT-18", attachments: [NotificationAttachment(identifier: "icon", fileURL: unusable)])

        do {
            try await repository.update(identifier: "u", content: replacement, trigger: .timeInterval(3600, repeats: false))
            Issue.record("the attachment was accepted")
        } catch let NotificationError.attachmentLoadFailed(identifier, _) {
            #expect(identifier == "icon")
        }

        let kept = try #require(center.request("u"), "update removed the pending request before it made the attachment")
        #expect(kept.content.userInfo["before"] as? Int == 1)
        #expect(center.calls == ["add u"])
    }
}
