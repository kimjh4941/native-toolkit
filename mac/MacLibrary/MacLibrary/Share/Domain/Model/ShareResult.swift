//
//  ShareResult.swift
//  MacLibrary
//

import Foundation

/// The outcome of a share interaction.
public struct ShareResult {
    /// true if the user completed a service; false if cancelled.
    public let completed: Bool
    /// The chosen service's display name (`NSSharingService.title`), or nil (cancelled / unknown).
    public let serviceName: String?

    /// Creates a share result.
    public init(completed: Bool, serviceName: String?) {
        self.completed = completed
        self.serviceName = serviceName
    }
}
