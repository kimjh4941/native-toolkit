//
//  GetSnapshotUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-05. Describes a pasteboard's types without reading any payload.
///
/// - Important: Not reading the payload does **not** guarantee the system will refrain from
///   telling the user the pasteboard was accessed (RK-01 / RK-22).
@MainActor
public struct GetSnapshotUseCase {

    private let TAG = "GetSnapshotUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// - Parameter matchingTypes: `nil` disables filtering; matching is by UTI conformance.
    /// - Throws: ``ClipboardError/emptyTypeFilter`` for an empty array, which would otherwise
    ///   be indistinguishable from an empty pasteboard at the call site.
    public func callAsFunction(matchingTypes: [String]?,
                               scope: PasteboardScope) throws -> ClipboardSnapshot {
        Log.d(TAG, "[callAsFunction] matchingTypes: "
              + "\(matchingTypes.map(ClipboardLog.types) ?? "nil"), scope: \(ClipboardLog.scope(scope))")
        return try repository.snapshot(matchingTypes: matchingTypes, scope: scope)
    }
}
