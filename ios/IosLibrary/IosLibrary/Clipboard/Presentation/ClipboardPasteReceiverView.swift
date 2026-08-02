//
//  ClipboardPasteReceiverView.swift
//  IosLibrary
//

import UIKit

/// A `UIResponder` that accepts pasted `NSItemProvider`s via `UIPasteControl` (or the standard
/// edit menu). Not intended to be instantiated directly by callers — obtain one via
/// `IosClipboardManager.makePasteControl` (recommended) or `PasteControlFactory.makeComponents`.
///
/// - Note: This view must be part of the responder chain (added to a view hierarchy) for
///   `UIPasteControl` to reach it. `ClipboardPasteControlContainerView` guarantees this by adding
///   it as a subview.
@MainActor
public final class ClipboardPasteReceiverView: UIView {
    private let TAG = "ClipboardPasteReceiverView"
    private let loader: PasteItemProviderLoader

    /// Called once when one or more providers loaded successfully.
    public var onPaste: (([ClipboardLoadedItem]) -> Void)?
    /// Called once, after `onPaste`, when some providers succeeded and others failed.
    public var onPartialFailure: (([ClipboardError]) -> Void)?
    /// Called once when no provider could be loaded (all failed, none matched, or the provider
    /// list was empty).
    public var onPasteFailure: ((ClipboardError) -> Void)?

    init(acceptedTypes: [String], loader: PasteItemProviderLoader = PasteItemProviderLoader()) {
        self.loader = loader
        super.init(frame: .zero)
        self.pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipboardPasteReceiverView does not support NSCoding")
    }

    public override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        guard let acceptable = pasteConfiguration?.acceptableTypeIdentifiers, !acceptable.isEmpty else {
            return false
        }
        return itemProviders.contains { provider in
            acceptable.contains { provider.hasItemConformingToTypeIdentifier($0) }
        }
    }

    public override func paste(itemProviders: [NSItemProvider]) {
        Log.d(TAG, "[paste] providerCount: \(itemProviders.count)")
        loader.load(providers: itemProviders) { [weak self] result in
            guard let self else { return }
            if !result.items.isEmpty {
                self.onPaste?(result.items)
                if !result.failures.isEmpty {
                    self.onPartialFailure?(result.failures)
                }
            } else if let first = result.failures.first {
                self.onPasteFailure?(first)
            } else {
                self.onPasteFailure?(.noMatchingItem)
            }
        }
    }

    /// Cancels any in-flight paste load without invoking `onPaste` / `onPartialFailure` /
    /// `onPasteFailure` (cancellation is caller-initiated and must not surface as a UI callback).
    func cancelPendingLoad() {
        loader.cancelAll()
    }
}
