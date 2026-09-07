//
//  ClipboardPasteContainerView.swift
//  MacLibrary
//

import AppKit
import Foundation

/// Hosts a paste button and cancels its loader when it goes away.
///
/// The view is what the caller holds, so its lifetime is the only reliable signal that a paste
/// in progress is no longer wanted. Without this, a loader would keep running and could call
/// back into a view hierarchy that no longer exists (R2-M10).
@MainActor
final class ClipboardPasteContainerView: NSView {

    private let TAG = "ClipboardPasteContainerView"

    private let handle: ClipboardPasteHandle
    /// Cancels the loader. Held as a closure so the view does not need the coordinator type.
    private let onCancel: @MainActor (ClipboardPasteHandle) -> Void

    init(handle: ClipboardPasteHandle,
         content: NSView,
         onCancel: @escaping @MainActor (ClipboardPasteHandle) -> Void) {
        Log.d("ClipboardPasteContainerView", "[init] handle: \(handle.id)")
        self.handle = handle
        self.onCancel = onCancel
        super.init(frame: .zero)
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClipboardPasteContainerView is created in code only")
    }

    deinit {
        // `deinit` is nonisolated, and both stored properties are needed here. Hopping would
        // be too late: the view is already being torn down. `assumeIsolated` is sound because
        // an NSView is only ever released on the main thread.
        MainActor.assumeIsolated {
            onCancel(handle)
        }
    }
}
