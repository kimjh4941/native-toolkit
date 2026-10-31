//
//  CancelAllLoadsUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "CancelAllLoadsUseCase")

/// Cancels every pending `loadItem` request (P-12).
@MainActor
public struct CancelAllLoadsUseCase {
    private let loader: ClipboardItemLoader

    public init(loader: ClipboardItemLoader) {
        self.loader = loader
    }

    public func execute() {
        logger.log(level: .libraryDebug, "[execute]")
        loader.cancelAll()
    }
}
