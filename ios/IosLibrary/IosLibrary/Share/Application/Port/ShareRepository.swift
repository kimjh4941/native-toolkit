//
//  ShareRepository.swift
//  IosLibrary
//

import Foundation

/// Defines the contract for presenting the system share sheet (the port of
/// ``ShareContentUseCase``).
///
/// The library's implementation presents a `UIActivityViewController` from the view controller
/// `presenter` selects; the share manager uses it. You can write your own, for example to answer
/// the request in a test, and pass it to ``ShareContentUseCase/init(repository:)``. Your
/// implementation should:
///
/// * Return once the share has ended, with the ``ShareResult`` (`completed == false` when the user
///   closed the sheet without choosing an activity), or throw a ``ShareError``. Never leave the
///   call suspended for good.
/// * Throw ``ShareError`` only: ``ShareContentUseCase`` rethrows what you throw unchanged, and its
///   callers expect a ``ShareError``.
///
/// What only the library's implementation does: `presenter` chooses the view controller to
/// present from (``PresenterSelection`` has no public members to read its value, so your
/// implementation chooses by its own means), and a sheet that goes away without reporting a
/// result ends the call with ``ShareError/dismissedBySystem``.
///
/// Conforming types are `Sendable`: `IosShareManager` (a `Sendable` singleton) holds one and calls it
/// from any thread.
public protocol ShareRepository: Sendable {
    /// Presents the share sheet for the given content.
    /// - Parameters:
    ///   - content: The content to share. ``ShareContentUseCase`` has checked that it has items.
    ///   - presenter: How to choose the view controller to present from.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` on failure before or during presentation, or when the sheet ends
    ///   without a result.
    func present(content: ShareContent, presenter: PresenterSelection) async throws -> ShareResult
}
