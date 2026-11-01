//
//  NotificationErrorTests.swift
//  IosLibraryTests
//
//  UT-16 (design 13.1), the Notification part: every case of `NotificationError` has a fixed
//  English description without the values that were passed in (S-P7), the cases compare by their
//  values, and the callback forms report those descriptions as their `errorMessage`.
//

import Foundation
import Testing
@testable import IosLibrary

struct NotificationErrorTests {

    private static let detail = FailureDetail(domain: "UNErrorDomain", code: 1)
    private static let secret = "secret-attachment-id-7c41"

    /// Every case, once (checked by the exhaustive `ordinal`).
    private static let cases: [NotificationError] = [
        .permissionDenied,
        .attachmentLoadFailed(identifier: secret, detail: detail),
        .addRequestFailed(detail),
        .setBadgeCountFailed(detail),
        .authorizationFailed(detail),
        .reservedUserInfoKey,
        .invalidUserInfo,
        .notForeground,
        .openSettingsFailed,
        .delegateNotInstalled,
    ]

    /// The switch is exhaustive, so a new case does not compile until it gets a number here; the
    /// numbers then show that `cases` lists every case once.
    private static func ordinal(_ error: NotificationError) -> Int {
        switch error {
        case .permissionDenied: return 0
        case .attachmentLoadFailed: return 1
        case .addRequestFailed: return 2
        case .setBadgeCountFailed: return 3
        case .authorizationFailed: return 4
        case .reservedUserInfoKey: return 5
        case .invalidUserInfo: return 6
        case .notForeground: return 7
        case .openSettingsFailed: return 8
        case .delegateNotInstalled: return 9
        }
    }

    @Test func everyCaseHasItsOwnFixedDescription() {
        #expect(Self.cases.map(Self.ordinal).sorted() == Array(0..<10))
        for error in Self.cases {
            #expect(error.errorDescription?.isEmpty == false, "\(Self.ordinal(error))")
            // `localizedDescription` is the fixed text too (LocalizedError), not the generic
            // sentence of the device language.
            #expect(error.localizedDescription == error.errorDescription, "\(Self.ordinal(error))")
        }
        #expect(Set(Self.cases.compactMap(\.errorDescription)).count == Self.cases.count)
    }

    /// The texts are fixed: the same for other values, and never with a value passed in.
    @Test func theDescriptionsHoldNoValues() {
        let other = FailureDetail(domain: "Other", code: 99)
        #expect(NotificationError.attachmentLoadFailed(identifier: "a", detail: Self.detail).errorDescription
                == NotificationError.attachmentLoadFailed(identifier: "b", detail: other).errorDescription)
        #expect(NotificationError.addRequestFailed(Self.detail).errorDescription == NotificationError.addRequestFailed(other).errorDescription)
        for error in Self.cases {
            let text = error.errorDescription ?? ""
            #expect(!text.contains(Self.secret))
            #expect(!text.contains("UNErrorDomain"))
        }
    }

    /// The two cases C5 added keep their texts (stage 1b C5 hand-off 13.21).
    @Test func theCasesOfTheDelegateAndTheMarkerHaveTheirTexts() {
        #expect(NotificationError.reservedUserInfoKey.errorDescription == "The userInfo uses the key the library reserves.")
        #expect(NotificationError.delegateNotInstalled.errorDescription
                == "The library's notification delegate is not installed. Call IosNotificationManager.installDelegate() first.")
        #expect(NotificationError.invalidUserInfo.errorDescription == "The userInfo holds a value that is not a property-list value.")
    }

    @Test func casesCompareByTheirValues() {
        #expect(NotificationError.addRequestFailed(Self.detail) == .addRequestFailed(FailureDetail(domain: "UNErrorDomain", code: 1)))
        #expect(NotificationError.addRequestFailed(Self.detail) != .addRequestFailed(FailureDetail(domain: "UNErrorDomain", code: 2)))
        #expect(NotificationError.addRequestFailed(Self.detail) != .setBadgeCountFailed(Self.detail))
        #expect(NotificationError.attachmentLoadFailed(identifier: "a", detail: Self.detail) != .attachmentLoadFailed(identifier: "b", detail: Self.detail))
        #expect(NotificationError.reservedUserInfoKey != .invalidUserInfo)
    }

    /// The log shows the case and the detail's domain and code only.
    @Test func theLogFormShowsTheCaseAndTheDetail() {
        #expect(LogRedaction.describe(NotificationError.setBadgeCountFailed(Self.detail)) == "NotificationError.setBadgeCountFailed(domain=UNErrorDomain, code=1)")
        let attachment = LogRedaction.describe(NotificationError.attachmentLoadFailed(identifier: Self.secret, detail: Self.detail))
        #expect(attachment == "NotificationError.attachmentLoadFailed")
        #expect(LogRedaction.describe(NotificationError.invalidUserInfo) == "NotificationError.invalidUserInfo")
    }

    /// The callback forms' `errorMessage` is the fixed text; another error keeps its own description.
    @Test func theCallbackMessageIsTheFixedText() {
        for error in Self.cases {
            #expect(IosNotificationManager.errorMessage(of: error) == error.errorDescription)
        }
        let other = NSError(domain: "Custom", code: 3, userInfo: [NSLocalizedDescriptionKey: "a repository of your own"])
        #expect(IosNotificationManager.errorMessage(of: other) == "a repository of your own")
    }
}
