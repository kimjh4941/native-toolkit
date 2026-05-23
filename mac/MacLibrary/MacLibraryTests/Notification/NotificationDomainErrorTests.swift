//
//  NotificationDomainErrorTests.swift
//  MacLibraryTests
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Testing
@testable import MacLibrary

struct NotificationDomainErrorTests {

    // MARK: - Error Codes

    @Test func unsupportedOSHasCode1001() {
        let error = NotificationDomainError.unsupportedOS(minimum: "15.0")
        #expect(error.errorCode == 1001)
    }

    @Test func permissionDeniedHasCode1002() {
        let error = NotificationDomainError.permissionDenied
        #expect(error.errorCode == 1002)
    }

    @Test func permissionRequestFailedHasCode1003() {
        let error = NotificationDomainError.permissionRequestFailed(underlying: NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1003)
    }

    @Test func invalidContentHasCode1101() {
        let error = NotificationDomainError.invalidContent(reason: "test")
        #expect(error.errorCode == 1101)
    }

    @Test func invalidTriggerHasCode1102() {
        let error = NotificationDomainError.invalidTrigger(reason: "test")
        #expect(error.errorCode == 1102)
    }

    @Test func invalidCategoryHasCode1103() {
        let error = NotificationDomainError.invalidCategory(reason: "test")
        #expect(error.errorCode == 1103)
    }

    @Test func notificationNotFoundHasCode1104() {
        let error = NotificationDomainError.notificationNotFound(identifier: "id")
        #expect(error.errorCode == 1104)
    }

    @Test func addFailedHasCode1201() {
        let error = NotificationDomainError.addFailed(underlying: NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1201)
    }

    @Test func removeFailedHasCode1202() {
        let error = NotificationDomainError.removeFailed(underlying: NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1202)
    }

    @Test func queryFailedHasCode1203() {
        let error = NotificationDomainError.queryFailed(underlying: NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1203)
    }

    @Test func setBadgeFailedHasCode1204() {
        let error = NotificationDomainError.setBadgeFailed(underlying: NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1204)
    }

    @Test func openSettingsFailedHasCode1205() {
        let error = NotificationDomainError.openSettingsFailed(underlying: NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1205)
    }

    @Test func unknownHasCode1999() {
        let error = NotificationDomainError.unknown(underlying: NSError(domain: "t", code: 0))
        #expect(error.errorCode == 1999)
    }

    // MARK: - Error Messages

    @Test func unsupportedOSErrorMessageContainsMinimum() {
        let error = NotificationDomainError.unsupportedOS(minimum: "15.0")
        #expect(error.errorMessage.contains("15.0"))
    }

    @Test func notificationNotFoundErrorMessageContainsIdentifier() {
        let error = NotificationDomainError.notificationNotFound(identifier: "my-id")
        #expect(error.errorMessage.contains("my-id"))
    }

    @Test func invalidContentErrorMessageContainsReason() {
        let error = NotificationDomainError.invalidContent(reason: "bad title")
        #expect(error.errorMessage.contains("bad title"))
    }
}
