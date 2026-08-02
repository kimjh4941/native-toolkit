//
//  CancelAllLoadsUseCase.swift
//  IosLibrary
//

import Foundation

/// Cancels every pending `loadItem` request (P-12).
@MainActor
public struct CancelAllLoadsUseCase {
    private let TAG = "CancelAllLoadsUseCase"
    private let loader: ClipboardItemLoader

    public init(loader: ClipboardItemLoader) {
        self.loader = loader
    }

    public func execute() {
        Log.d(TAG, "[execute]")
        loader.cancelAll()
    }
}
