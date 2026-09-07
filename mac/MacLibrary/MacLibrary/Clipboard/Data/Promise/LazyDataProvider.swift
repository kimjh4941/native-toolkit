//
//  LazyDataProvider.swift
//  MacLibrary
//

import AppKit
import Foundation

/// Supplies pasteboard bytes only when another app actually asks for them.
///
/// A normal copy hands the whole payload to the pasteboard server up front, which for a large
/// item means a long synchronous IPC on the main actor for data nobody may ever paste. A lazy
/// provider defers that work to the moment a reader requests the type.
///
/// This is an internal optimisation, chosen automatically for items over the warn threshold.
/// It is not exposed publicly: the closure it needs cannot cross the Unity bridge, and putting
/// a non-`Sendable` closure in the domain would violate the port contract.
///
/// - Important: The coordinator holds the strong reference. `NSPasteboard` retaining the
///   provider is unverified (RK-17 / V-3), so the safe assumption is that it does not.
final class LazyDataProvider: NSObject, NSPasteboardItemDataProvider, @unchecked Sendable {

    private let TAG = "LazyDataProvider"

    private let provide: @Sendable (String) -> Data?
    /// Called when the pasteboard says it no longer needs this provider, so the coordinator
    /// can drop its strong reference.
    private let onFinished: @Sendable () -> Void

    init(provide: @escaping @Sendable (String) -> Data?,
         onFinished: @escaping @Sendable () -> Void) {
        Log.d("LazyDataProvider", "[init]")
        self.provide = provide
        self.onFinished = onFinished
        super.init()
    }

    func pasteboard(_ pasteboard: NSPasteboard?,
                    item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        Log.d(TAG, "[provideDataForType] type: \(type.rawValue)")
        guard let data = provide(type.rawValue) else {
            // Declining is legitimate: the reader asked for a type this item cannot produce.
            // Setting nothing leaves the type absent rather than empty.
            Log.e(TAG, "[provideDataForType] no data for type: \(type.rawValue)")
            return
        }
        item.setData(data, forType: type)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {
        Log.d(TAG, "[pasteboardFinishedWithDataProvider]")
        // The only signal that the provider will never be asked again (L-03).
        onFinished()
    }
}
