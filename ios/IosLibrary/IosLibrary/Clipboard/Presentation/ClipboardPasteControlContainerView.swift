//
//  ClipboardPasteControlContainerView.swift
//  IosLibrary
//

import UIKit

/// A ready-to-place container that strongly retains both a paste button (`control`) and its
/// receiver (`receiver`), and adds the receiver as a subview so it automatically joins the
/// responder chain.
///
/// Add this single view to your hierarchy; there is no need to separately retain or place its
/// `receiver`. For independent placement, see `PasteControlFactory.makeComponents`.
@MainActor
public final class ClipboardPasteControlContainerView: UIView {
    private let TAG = "ClipboardPasteControlContainerView"

    public private(set) var control: UIPasteControl!
    public private(set) var receiver: ClipboardPasteReceiverView!

    /// Called once when one or more providers loaded successfully.
    public var onPaste: (([ClipboardLoadedItem]) -> Void)?
    /// Called once, after `onPaste`, when some providers succeeded and others failed.
    public var onPartialFailure: (([ClipboardError]) -> Void)?
    /// Called once when no provider could be loaded.
    public var onPasteFailure: ((ClipboardError) -> Void)?

    /// - Throws: `ClipboardError.invalidRequest` if `acceptedTypes` is empty, or
    ///   `ClipboardError.invalidTypeIdentifier` if any entry is not a resolvable/valid identifier.
    public init(
        acceptedTypes: [String],
        displayMode: UIPasteControl.DisplayMode = .iconAndLabel,
        typeValidator: ClipboardTypeIdentifierValidating = ClipboardTypeIdentifierValidator()
    ) throws {
        Log.d(TAG, "[init] acceptedTypesCount: \(acceptedTypes.count)")
        guard !acceptedTypes.isEmpty else {
            throw ClipboardError.invalidRequest("acceptedTypes must not be empty")
        }
        for type in acceptedTypes {
            try typeValidator.validateGeneric(type)
        }

        let receiverView = ClipboardPasteReceiverView(acceptedTypes: acceptedTypes)
        var configuration = UIPasteControl.Configuration()
        configuration.displayMode = displayMode
        let pasteControl = UIPasteControl(configuration: configuration)
        pasteControl.target = receiverView

        super.init(frame: .zero)

        receiver = receiverView
        control = pasteControl

        receiverView.onPaste = { [weak self] items in self?.onPaste?(items) }
        receiverView.onPartialFailure = { [weak self] failures in self?.onPartialFailure?(failures) }
        receiverView.onPasteFailure = { [weak self] error in self?.onPasteFailure?(error) }

        receiverView.translatesAutoresizingMaskIntoConstraints = false
        pasteControl.translatesAutoresizingMaskIntoConstraints = false
        addSubview(receiverView)
        addSubview(pasteControl)
        NSLayoutConstraint.activate([
            receiverView.leadingAnchor.constraint(equalTo: leadingAnchor),
            receiverView.trailingAnchor.constraint(equalTo: trailingAnchor),
            receiverView.topAnchor.constraint(equalTo: topAnchor),
            receiverView.bottomAnchor.constraint(equalTo: bottomAnchor),
            pasteControl.leadingAnchor.constraint(equalTo: leadingAnchor),
            pasteControl.trailingAnchor.constraint(equalTo: trailingAnchor),
            pasteControl.topAnchor.constraint(equalTo: topAnchor),
            pasteControl.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipboardPasteControlContainerView does not support NSCoding")
    }

    public override var intrinsicContentSize: CGSize {
        control.intrinsicContentSize
    }

    isolated deinit {
        receiver.cancelPendingLoad()
    }
}
