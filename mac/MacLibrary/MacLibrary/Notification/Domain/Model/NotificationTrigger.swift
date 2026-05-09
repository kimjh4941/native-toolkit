//
//  NotificationTrigger.swift
//  MacLibrary
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
import Foundation

/// Specifies when a scheduled notification should fire.
public enum NotificationTrigger {
    /// Fire immediately (no trigger).
    case immediate
    /// Fire after `seconds` seconds. Must be >= 1. Set `repeats` to fire repeatedly.
    case timeInterval(seconds: TimeInterval, repeats: Bool)
    /// Fire at the specified calendar date components. Set `repeats` for recurrence.
    case calendar(dateComponents: DateComponents, repeats: Bool)
}
