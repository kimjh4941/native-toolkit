//
//  VersionCheck.swift
//  IosLibraryCApi
//

import Foundation
import IosLibrary
import Synchronization

/// The check that the two frameworks are of the same version (P1-19, C-9): only a log, never a stop.
/// It runs once, at the first call that accepts or rejects something, or installs the delegate: not
/// from the reads, the `_free`s, `ntk_version` and `ntk_last_system_code`, as with the first-line log
/// of part 1, 5.15.
enum VersionCheck {
    enum Outcome: Equatable {
        case same
        case different
        case unreadable
    }

    private static let runs = Atomic<Int>(0)

    private static let once: Void = {
        let library = libraryVersion
        switch compare(library: library, capi: capiVersion) {
        case .same:
            CApiLog.common.debug("[VersionCheck] IosLibrary and IosLibraryCApi are both \(capiVersion, privacy: .public)")
        case .different:
            CApiLog.common.error("[VersionCheck] IosLibrary is \(library ?? "", privacy: .public) and IosLibraryCApi is \(capiVersion, privacy: .public): use the two frameworks of the same version")
        case .unreadable:
            CApiLog.common.error("[VersionCheck] the version of IosLibrary cannot be read; IosLibraryCApi is \(capiVersion, privacy: .public)")
        }
    }()

    /// Any thread; never waits for the main thread. Calls that come together wait for the first one to
    /// read the version (`static let` runs once). A later call only counts.
    static func run() {
        CApiLog.common.debug("[VersionCheck.run]")
        runs.add(1, ordering: .relaxed)
        _ = once
    }

    /// How many times `run` was called, for the tests: the log comes once, so it cannot tell which
    /// functions call `run`.
    static var runCount: Int {
        runs.load(ordering: .relaxed)
    }

    static func compare(library: String?, capi: String) -> Outcome {
        CApiLog.common.debug("[compare] library: \(library ?? "nil", privacy: .public), capi: \(capi, privacy: .public)")
        guard let library else { return .unreadable }
        return library == capi ? .same : .different
    }

    static var libraryVersion: String? {
        Bundle(for: RequestBox.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    /// The header's version, which a test keeps equal to the framework's `CFBundleShortVersionString`.
    static var capiVersion: String {
        "\(NTK_VERSION_MAJOR).\(NTK_VERSION_MINOR).\(NTK_VERSION_PATCH)"
    }
}
