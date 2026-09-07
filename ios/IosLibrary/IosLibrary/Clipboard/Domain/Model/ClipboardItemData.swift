//
//  ClipboardItemData.swift
//  IosLibrary
//

import Foundation

/// A synchronously-read description of a single pasteboard item.
///
/// Large payloads (image bytes) are not included; only the UTI is reported. Use `readData` or
/// `loadItem` to retrieve the body.
public struct ClipboardItemData: Equatable, Sendable {
    public let typeIdentifiers: [String]
    public let text: String?
    public let urlString: String?
    public let imageDataUTType: String?

    public init(typeIdentifiers: [String], text: String?, urlString: String?, imageDataUTType: String?) {
        self.typeIdentifiers = typeIdentifiers
        self.text = text
        self.urlString = urlString
        self.imageDataUTType = imageDataUTType
    }
}

/// Result of a synchronous clipboard read.
public struct ClipboardReadResult: Equatable, Sendable {
    public let items: [ClipboardItemData]
    public let numberOfItems: Int

    public init(items: [ClipboardItemData], numberOfItems: Int) {
        self.items = items
        self.numberOfItems = numberOfItems
    }
}
