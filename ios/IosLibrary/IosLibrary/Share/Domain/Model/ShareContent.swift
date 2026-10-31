//
//  ShareContent.swift
//  IosLibrary
//

import Foundation

/// The full payload for a share invocation.
public struct ShareContent: Sendable {
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

extension ShareContent {
    /// The content for the log: the number of items of each kind, whether the subject and the
    /// preview title are there and their lengths, and the number of excluded activity types.
    /// The texts, URLs and paths are user content and never part of it (`ios.md`).
    var logSummary: String {
        var kinds = (text: 0, url: 0, imageFile: 0, file: 0)
        for item in items {
            switch item {
            case .text: kinds.text += 1
            case .url: kinds.url += 1
            case .imageFile: kinds.imageFile += 1
            case .file: kinds.file += 1
            }
        }
        return "items: \(items.count) (text: \(kinds.text), url: \(kinds.url), imageFile: \(kinds.imageFile), file: \(kinds.file)), "
            + "subject: \(LogRedaction.redact(subject)), previewTitle: \(LogRedaction.redact(previewTitle)), "
            + "excludedActivityTypes: \(excludedActivityTypes.count)"
    }
}
