//
//  NotificationMarker.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "NotificationMarker")

/// The userInfo marker of the notifications the library makes (P1-9, design 8.3.3).
///
/// The delegate router tells the library's notifications from the others by this key (part 1,
/// 5.12.2). The repository rejects a userInfo that already has the key before anything else
/// (``NotificationError/reservedUserInfoKey``), adds the marker to every request it adds, and the
/// library removes it from every userInfo it hands back (the scheduled and delivered lists, the
/// events and the existing receivers).
///
/// Internal: the key and its value are not part of the public API, and they are never logged
/// with a user's values (only whether the key is there).
enum NotificationMarker {
    /// The reserved userInfo key.
    static let key = "com.jonghyunkim.nativetoolkit"
    /// The value the library stores under ``key``: the version of the marker's form.
    static let value = 1

    /// Whether `userInfo` carries the marker key (any value: the key alone is reserved).
    static func isPresent(in userInfo: [AnyHashable: Any]) -> Bool {
        let present = userInfo[key] != nil
        logger.log(level: .libraryDebug, "[isPresent] keyCount: \(userInfo.count, privacy: .public), present: \(present, privacy: .public)")
        return present
    }

    /// Whether a userInfo a user passes uses the reserved key (rejected, design 8.3.3).
    static func isReserved(in userInfo: [String: Any]) -> Bool {
        let reserved = userInfo[key] != nil
        logger.log(level: .libraryDebug, "[isReserved] keyCount: \(userInfo.count, privacy: .public), reserved: \(reserved, privacy: .public)")
        return reserved
    }

    /// `userInfo` with the marker added, for the request the library adds. The caller has
    /// rejected a userInfo with the key before (``isReserved(in:)``).
    static func attaching(to userInfo: [String: Any]) -> [AnyHashable: Any] {
        logger.log(level: .libraryDebug, "[attaching] keyCount: \(userInfo.count, privacy: .public)")
        var marked: [AnyHashable: Any] = [:]
        for (name, item) in userInfo {
            marked[name] = item
        }
        marked[key] = value
        return marked
    }

    /// `userInfo` without the marker, for what the library hands back.
    static func removing(from userInfo: [AnyHashable: Any]) -> [AnyHashable: Any] {
        logger.log(level: .libraryDebug, "[removing] keyCount: \(userInfo.count, privacy: .public), hasMarker: \(isPresent(in: userInfo), privacy: .public)")
        var unmarked = userInfo
        unmarked[key] = nil
        return unmarked
    }
}
