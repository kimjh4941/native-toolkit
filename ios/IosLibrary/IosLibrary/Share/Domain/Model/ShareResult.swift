//
//  ShareResult.swift
//  IosLibrary
//

import Foundation

/// The outcome of a share sheet interaction.
public struct ShareResult {
    /// true if the user completed an activity; false if cancelled.
    public let completed: Bool
    /// The selected activity's raw identifier, or nil (cancelled / unknown).
    public let activityType: String?

    /// Creates a share result.
    public init(completed: Bool, activityType: String?) {
        self.completed = completed
        self.activityType = activityType
    }
}
