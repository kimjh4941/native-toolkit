//
//  NotificationAttachment.swift
//  IosLibrary
//

import Foundation

/// A media attachment (image, audio, or video) to include in a notification.
public struct NotificationAttachment {
    /// A unique identifier for this attachment.
    public let identifier: String
    /// The URL of the attachment file.
    public let fileURL: URL

    /// Creates a notification attachment.
    /// - Parameters:
    ///   - identifier: A unique identifier for this attachment.
    ///   - fileURL: The URL of the attachment file.
    public init(identifier: String, fileURL: URL) {
        self.identifier = identifier
        self.fileURL = fileURL
    }
}
