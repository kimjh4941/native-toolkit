//
//  ShareContent.swift
//  IosLibrary
//

import Foundation

/// The full payload for a share invocation.
public struct ShareContent {
    /// Items to share (must be non-empty).
    public let items: [ShareItem]
    /// Optional subject (used by Mail and similar activities).
    public let subject: String?
    /// Optional preview title shown in the share sheet header.
    public let previewTitle: String?
    /// Activity types to exclude (raw identifiers, e.g. "com.apple.UIKit.activity.PostToFacebook").
    public let excludedActivityTypes: [String]

    /// Creates share content.
    public init(
        items: [ShareItem],
        subject: String? = nil,
        previewTitle: String? = nil,
        excludedActivityTypes: [String] = []
    ) {
        self.items = items
        self.subject = subject
        self.previewTitle = previewTitle
        self.excludedActivityTypes = excludedActivityTypes
    }
}
