//
//  PasteControlFactory.swift
//  IosLibrary
//

import UIKit

/// Creates the raw `UIPasteControl` + `ClipboardPasteReceiverView` pair.
///
/// Prefer `ClipboardPasteControlContainerView` (or `IosClipboardManager.makePasteControl`), which
/// retains both components and guarantees the receiver joins the responder chain. Use this
/// factory only when you need to place the control and receiver independently — in that case
/// **you** are responsible for retaining `receiver` and adding it to your view hierarchy.
@MainActor
public enum PasteControlFactory {
    public static func makeComponents(
        acceptedTypes: [String],
        displayMode: UIPasteControl.DisplayMode = .iconAndLabel,
        typeValidator: ClipboardTypeIdentifierValidating = ClipboardTypeIdentifierValidator()
    ) throws -> (control: UIPasteControl, receiver: ClipboardPasteReceiverView) {
        guard !acceptedTypes.isEmpty else {
            throw ClipboardError.invalidRequest("acceptedTypes must not be empty")
        }
        for type in acceptedTypes {
            try typeValidator.validateGeneric(type)
        }

        let receiver = ClipboardPasteReceiverView(acceptedTypes: acceptedTypes)
        let configuration = UIPasteControl.Configuration()
        configuration.displayMode = displayMode
        let control = UIPasteControl(configuration: configuration)
        control.target = receiver
        return (control, receiver)
    }
}
