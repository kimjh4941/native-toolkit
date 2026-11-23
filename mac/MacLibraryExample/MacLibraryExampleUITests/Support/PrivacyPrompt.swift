//
//  PrivacyPrompt.swift
//  MacLibraryExampleUITests
//
//  The paste confirmation of the pasteboard privacy preview (UI test design U-12, 6.1). Needs a
//  `PastePrivacyToken`: the confirmation appears only with the preview setting the runner puts
//  into the sample's container on the VM (`pasteprivacy` is VM only). The confirmation is the one
//  dialog of the sample's tree that holds both `action-button--999` (Allow Paste) and
//  `action-button--998` (Don’t Allow Paste); the buttons are pressed by identifier, after the check
//  before a press (its window belongs to the sample on the 15.8.3 VM. Stage 0c 3.3).
//  Trusted Support file.
//

import XCTest
import Foundation

struct PrivacyPrompt {

    private let sample: SampleApp

    init(_ sample: SampleApp, _ token: PastePrivacyToken) {
        self.sample = sample
    }

    /// Waits until exactly one confirmation is shown (design 5.5: within 5 seconds).
    @discardableResult
    func waitShown(timeout: TimeInterval = SampleApp.systemUITimeout) throws -> XCUIElement {
        let prompt = try sample.waitForExactlyOne(sample.pasteConfirmations, "paste confirmation", timeout: timeout,
                                                  step: .pasteConfirmation)
        _ = try button(SystemLabels.pasteAllowIdentifier, in: prompt)
        _ = try button(SystemLabels.pasteDenyIdentifier, in: prompt)
        return prompt
    }

    func waitGone() throws {
        guard sample.pasteConfirmations.firstMatch.waitForNonExistence(timeout: SampleApp.systemUITimeout) else {
            throw SampleUITestError(.pasteConfirmation, "the paste confirmation did not close")
        }
        try sample.session.checkInterruption()
    }

    /// Presses Allow Paste (`action-button--999`).
    func allow() throws {
        try press(SystemLabels.pasteAllowIdentifier)
    }

    /// Presses Don’t Allow Paste (`action-button--998`).
    func deny() throws {
        try press(SystemLabels.pasteDenyIdentifier)
    }

    private func press(_ identifier: String) throws {
        let prompt = try exactlyOne(sample.pasteConfirmations, "paste confirmation", step: .pasteConfirmation)
        try sample.guardedClick(try button(identifier, in: prompt), .pasteConfirmation, name: identifier)
    }

    private func button(_ identifier: String, in prompt: XCUIElement) throws -> XCUIElement {
        try exactlyOne(prompt.buttons.matching(identifier: identifier), identifier, step: .pasteConfirmation)
    }
}
