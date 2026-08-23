//
//  ClipboardSnapshot.swift
//  IosLibrary
//

import Foundation

/// A metadata-only view of the clipboard, built exclusively from system APIs that Apple
/// documents as avoiding user notifications and prompts.
public struct ClipboardSnapshot: Equatable, Sendable {
    public let hasStrings: Bool
    public let hasURLs: Bool
    public let hasImages: Bool
    public let hasColors: Bool
    public let numberOfItems: Int
    /// Representation types of the first item.
    public let typeIdentifiers: [String]
    /// Representation types of every item, in clipboard order.
    public let allTypeIdentifiers: [[String]]
    /// Indexes of items matching the `matchingTypes` requested from `snapshot(matchingTypes:scope:)`,
    /// or `nil` when no `matchingTypes` were requested.
    public let matchingItemIndexes: [Int]?

    public init(
        hasStrings: Bool,
        hasURLs: Bool,
        hasImages: Bool,
        hasColors: Bool,
        numberOfItems: Int,
        typeIdentifiers: [String],
        allTypeIdentifiers: [[String]],
        matchingItemIndexes: [Int]?
    ) {
        self.hasStrings = hasStrings
        self.hasURLs = hasURLs
        self.hasImages = hasImages
        self.hasColors = hasColors
        self.numberOfItems = numberOfItems
        self.typeIdentifiers = typeIdentifiers
        self.allTypeIdentifiers = allTypeIdentifiers
        self.matchingItemIndexes = matchingItemIndexes
    }
}
