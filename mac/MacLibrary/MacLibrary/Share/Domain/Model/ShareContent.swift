//
//  ShareContent.swift
//  MacLibrary
//

import Foundation

/// The full payload for a share invocation.
public struct ShareContent {
    /// Items to share (must be non-empty).
    public let items: [ShareItem]
    /// Recipients for direct-service mode (email/message). Ignored in picker mode.
    public let recipients: [String]
    /// Subject for direct-service mode (Mail etc.). Ignored in picker mode.
    public let subject: String?
    /// Service display titles to exclude from the picker (best-effort match against
    /// `NSSharingService.title`). Applied in picker mode only.
    public let excludedServiceTitles: [String]

    /// Creates share content.
    public init(
        items: [ShareItem],
        recipients: [String] = [],
        subject: String? = nil,
        excludedServiceTitles: [String] = []
    ) {
        self.items = items
        self.recipients = recipients
        self.subject = subject
        self.excludedServiceTitles = excludedServiceTitles
    }
}
