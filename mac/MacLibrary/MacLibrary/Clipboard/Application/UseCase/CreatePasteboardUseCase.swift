//
//  CreatePasteboardUseCase.swift
//  MacLibrary
//

import Foundation

/// OP-07. Creates or fetches a pasteboard.
///
/// - Important: A pasteboard created here lives in the pasteboard server and outlives this
///   app. Release a unique pasteboard with ``RemovePasteboardUseCase`` when it is no longer
///   needed, and never put confidential data on a named one (RK-06).
@MainActor
public struct CreatePasteboardUseCase {

    private let TAG = "CreatePasteboardUseCase"

    private let repository: any ClipboardRepository

    /// Creates the use case with the ports it needs. Dependencies are injected so a test can substitute mocks.
    public init(repository: any ClipboardRepository) {
        self.repository = repository
    }

    /// - Returns: The scope naming the pasteboard. For a unique request the name is chosen by
    ///   the system, so the returned scope is the only way to address it later.
    public func callAsFunction(_ request: PasteboardCreationRequest) throws -> PasteboardScope {
        Log.d(TAG, "[callAsFunction] request: \(ClipboardLog.request(request))")
        return try repository.createPasteboard(request)
    }
}
