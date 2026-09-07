//
//  ClipboardOperationKind.swift
//  IosLibrary
//

import Foundation

/// The kind of asynchronous operation that timed out.
public enum ClipboardOperationKind: String, Sendable {
    case detection
    case providerLoad
    case imageCoding
}
