//
//  ShowDialogUseCase.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ShowDialogUseCase")

/// Shows one dialog request through a ``DialogPresenting`` port.
///
/// The use case refuses a ``RequestBox`` that another request already uses: the request then
/// ends at once with ``DialogError/invalidRequest`` (on the main thread, after the call returns)
/// and the port is not called. The first request that uses the box is not affected. Only the
/// library's own port takes a box in a way this check sees (see ``DialogPresenting``); with your
/// own port, a box passed twice is not refused.
public struct ShowDialogUseCase: Sendable {
    private let presenter: any DialogPresenting

    /// Creates the use case.
    /// - Parameter presenter: The port that presents the dialog.
    public init(presenter: any DialogPresenting) {
        logger.log(level: .libraryDebug, "[init] presenter: \(String(describing: type(of: presenter)), privacy: .public)")
        self.presenter = presenter
    }

    /// Shows `request`.
    /// - Parameters:
    ///   - request: The dialog to show.
    ///   - presenter: How to choose the view controller to present from.
    ///   - box: The request's box.
    ///   - completion: The answer, or why there is none. Called once, on the main thread, never
    ///     inside this call.
    public func execute(_ request: DialogRequest, presenter: PresenterSelection, box: RequestBox,
                        completion: @escaping @MainActor @Sendable (Result<DialogAnswer, DialogError>) -> Void) {
        logger.log(level: .libraryDebug, "[execute] request: \(request.kindName, privacy: .public), title: \(request.logTitle ?? "nil", privacy: .private), message: \(request.logMessage ?? "nil", privacy: .private), presenter: \(presenter.logName, privacy: .public), box closed: \(box.isClosed, privacy: .public), completion: provided")
        guard !box.isAttached else {
            logger.error("[execute] the request box is already used by another request")
            DispatchQueue.main.async {
                MainActor.assumeIsolated { completion(.failure(.invalidRequest)) }
            }
            return
        }
        self.presenter.present(request, presenter: presenter, box: box, completion: completion)
    }
}
