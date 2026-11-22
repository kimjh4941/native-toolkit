//
//  NotificationRepositoryAttachmentCheckTests.swift
//  IosLibraryTests
//
//  UT-18, the attachment files (1b working notes, chapters 21 and 23): `show`, `update` and
//  `schedule` check that the file of every attachment exists before any attachment is made. A
//  missing file is `attachmentLoadFailed` with `NSCocoaErrorDomain` and `NSFileReadNoSuchFileError`;
//  nothing is added, and `update` leaves the pending request. (Without the check the system takes
//  the missing file in `UNNotificationAttachment` and rejects the whole request in `add`.)
//

import Foundation
import Testing
import UIKit
import UserNotifications
@testable import IosLibrary

struct NotificationRepositoryAttachmentCheckTests {

    private static let missingFileError = NotificationError.attachmentLoadFailed(
        identifier: "missing", detail: FailureDetail(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError))

    /// A URL in the temporary directory with no file.
    private func missingFileURL() -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ut18-missing-\(UUID().uuidString).png")
    }

    /// A small PNG the system takes as an attachment (written to the temporary directory under
    /// `name`, or a plain unique name; the caller removes it).
    private func makeImageFile(named name: String? = nil) throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name ?? "ut18-\(UUID().uuidString).png")
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let data = renderer.pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        try data.write(to: url)
        return url
    }

    /// An existing file whose type the system does not take as an attachment (`UNErrorDomain` 101
    /// when it is made; the caller removes it).
    private func makeUnusableFile() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ut18-\(UUID().uuidString).ut18unknown")
        try Data([0x00, 0x01, 0x02]).write(to: url)
        return url
    }

    private func content(_ identifier: String, attachments: [NotificationAttachment], userInfo: [String: Any] = [:]) -> NotificationContent {
        NotificationContent(id: identifier, title: "UT-18", body: "attachment", userInfo: userInfo, attachments: attachments)
    }

    /// `show` and `schedule` fail at the entry with the detail of a missing file, and call nothing
    /// on the center. The file of every attachment is checked, also after one that exists.
    @Test func showAndScheduleWithAMissingFileFailAndAddNothing() async throws {
        let image = try makeImageFile()
        defer { try? FileManager.default.removeItem(at: image) }
        let attachmentLists: [[NotificationAttachment]] = [
            [NotificationAttachment(identifier: "missing", fileURL: missingFileURL())],
            [NotificationAttachment(identifier: "present", fileURL: image),
             NotificationAttachment(identifier: "missing", fileURL: missingFileURL())],
        ]
        for attachments in attachmentLists {
            let center = FakeRequestCenter()
            let repository = NotificationRepositoryImpl(requestCenter: center)
            await #expect(throws: Self.missingFileError) {
                try await repository.show(content: content("n", attachments: attachments), trigger: nil)
            }
            await #expect(throws: Self.missingFileError) {
                try await repository.schedule(content: content("n", attachments: attachments),
                                              trigger: .timeInterval(3600, repeats: false), identifier: "n")
            }
            #expect(center.calls.isEmpty, "\(attachments.map(\.identifier))")
        }
    }

    /// Every attachment is checked before the first one is made: a file the system would refuse to
    /// make comes first, and the missing file after it is still what is reported (with 260).
    @Test func everyAttachmentIsCheckedBeforeTheFirstIsMade() async throws {
        let unusable = try makeUnusableFile()
        defer { try? FileManager.default.removeItem(at: unusable) }
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        let attachments = [NotificationAttachment(identifier: "unusable", fileURL: unusable),
                           NotificationAttachment(identifier: "missing", fileURL: missingFileURL())]

        await #expect(throws: Self.missingFileError) {
            try await repository.show(content: content("n", attachments: attachments), trigger: nil)
        }
        #expect(center.calls.isEmpty)
    }

    /// A URL that is not a file URL is not checked (the deviation in the 1b working notes 23.2): it
    /// is not rejected with 260 and is left to the system, which in the test host takes it, so the
    /// request is added.
    @Test func aURLThatIsNotAFileURLIsLeftToTheSystem() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        let attachments = [NotificationAttachment(identifier: "remote", fileURL: URL(string: "https://example.com/a.png")!)]

        do {
            try await repository.show(content: content("n", attachments: attachments), trigger: nil)
        } catch NotificationError.attachmentLoadFailed(_, let detail)
            where detail == FailureDetail(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError) {
            Issue.record("a URL that is not a file URL was checked as a file")
        }
        #expect(center.calls == ["add n"])
    }

    /// `update` fails before it removes the pending request: the request stays, nothing is added.
    @Test func updateWithAMissingFileKeepsThePendingRequest() async throws {
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        try await repository.schedule(content: content("u", attachments: [], userInfo: ["before": 1]),
                                      trigger: .timeInterval(3600, repeats: false), identifier: "u")

        await #expect(throws: Self.missingFileError) {
            try await repository.update(identifier: "u",
                                        content: content("u", attachments: [NotificationAttachment(identifier: "missing", fileURL: missingFileURL())]),
                                        trigger: .timeInterval(3600, repeats: false))
        }

        let kept = try #require(center.request("u"), "update removed the pending request before it checked the attachment file")
        #expect(kept.content.userInfo["before"] as? Int == 1)
        #expect(center.calls == ["add u"])
    }

    /// An attachment whose file exists still goes through `show`, `schedule` and `update`, also
    /// when its name has a space, `%20` and Japanese (the check reads the decoded path).
    @Test func anExistingFileStillGoesThrough() async throws {
        let image = try makeImageFile()
        defer { try? FileManager.default.removeItem(at: image) }
        let named = try makeImageFile(named: "ut18 画像 %20-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: named) }
        let center = FakeRequestCenter()
        let repository = NotificationRepositoryImpl(requestCenter: center)
        let attachments = [NotificationAttachment(identifier: "icon", fileURL: image),
                           NotificationAttachment(identifier: "named", fileURL: named)]

        try await repository.show(content: content("n", attachments: attachments), trigger: nil)
        try await repository.schedule(content: content("s", attachments: attachments),
                                      trigger: .timeInterval(3600, repeats: false), identifier: "s")
        try await repository.update(identifier: "s", content: content("s", attachments: attachments),
                                    trigger: .timeInterval(3600, repeats: false))

        #expect(center.calls == ["add n", "add s", "remove s", "add s"])
        for identifier in ["n", "s"] {
            let request = try #require(center.request(identifier))
            #expect(request.content.attachments.map(\.identifier) == ["icon", "named"], "\(identifier)")
        }
    }
}
