//
//  EntryError.swift
//  IosLibraryCApi
//

/// Why a call is rejected at its entry, for the values every feature's error shares (AP-12; part 1,
/// 5.10). `StructReader` and `CApiString` throw it; a receiver returns it as its feature's error, all
/// of which are `int32_t`. The value 0 is `Entry.accepted`. A feature's own values come from its header.
enum EntryError: Int32, Error, Sendable {
    case invalidParameter = 1
    case notInitialized = 2
    case notSupported = 3
}

/// What the receivers share at their entry.
enum Entry {
    /// The value of `NTK_*_ERROR_NONE`.
    static let accepted: Int32 = 0

    /// Rejects a call before anything is registered: release on the calling thread before the function
    /// returns, no completion (part 1, 1.3, C-3). This is the only `release` that `tryRelease` does not call.
    static func reject(_ error: Int32, userData: UnsafeMutableRawPointer?, release: ntk_release_fn?,
                       function: String = #function) -> Int32 {
        CApiLog.common.error("[reject] function: \(function, privacy: .public), error: \(error, privacy: .public), userData: \(String(describing: userData), privacy: .private), release: \(release == nil ? "nil" : "provided", privacy: .public)")
        VersionCheck.run()
        release?(userData)
        return error
    }

    static func reject(_ error: EntryError, userData: UnsafeMutableRawPointer?, release: ntk_release_fn?,
                       function: String = #function) -> Int32 {
        reject(error.rawValue, userData: userData, release: release, function: function)
    }
}
