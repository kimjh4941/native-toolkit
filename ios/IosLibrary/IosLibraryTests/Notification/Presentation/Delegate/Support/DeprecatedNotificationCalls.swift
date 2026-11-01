//
//  DeprecatedNotificationCalls.swift
//  IosLibraryTests
//
//  The tests of the deprecated entries (`setup()`, `onActionReceived`, `onTextInputActionReceived`.
//  Design S-P8) must call them. The calls are made in deprecated witnesses reached through a
//  protocol, so that the test target builds without deprecation warnings.
//

import Foundation
@testable import IosLibrary

/// The deprecated notification entries the tests call.
protocol DeprecatedNotificationEntries: Sendable {
    func setup()
    func setReceivers(of manager: IosNotificationManager, action: NotificationActionHandler?, textInput: NotificationTextInputActionHandler?)
    func receivers(of manager: IosNotificationManager) -> (action: NotificationActionHandler?, textInput: NotificationTextInputActionHandler?)
}

private struct DeprecatedNotificationCalls: DeprecatedNotificationEntries {
    @available(*, deprecated)
    func setup() {
        IosNotificationManager.setup()
    }

    @available(*, deprecated)
    func setReceivers(of manager: IosNotificationManager, action: NotificationActionHandler?, textInput: NotificationTextInputActionHandler?) {
        manager.onActionReceived = action
        manager.onTextInputActionReceived = textInput
    }

    @available(*, deprecated)
    func receivers(of manager: IosNotificationManager) -> (action: NotificationActionHandler?, textInput: NotificationTextInputActionHandler?) {
        (manager.onActionReceived, manager.onTextInputActionReceived)
    }
}

/// The deprecated entries, called without a deprecation warning.
let deprecatedNotification: any DeprecatedNotificationEntries = DeprecatedNotificationCalls()
