//
//  DialogPresenting.swift
//  IosLibrary
//

/// Shows one ``DialogRequest`` and reports how it ended (the port of ``ShowDialogUseCase``).
///
/// The library's implementation presents a `UIAlertController`; the dialog manager uses it. You
/// can write your own, for example to show the request in your own UI or to answer it in a test,
/// and pass it to ``ShowDialogUseCase/init(presenter:)``. Your implementation should:
///
/// * Call `completion` exactly once, on the main thread, and never inside the call of
///   ``present(_:presenter:box:completion:)`` (queue it on the main queue instead).
/// * Check ``RequestBox/isClosed`` before it shows anything: when the box is already closed (the
///   request was cancelled before it started), show nothing and complete with
///   `.failure(.canceled)`.
/// * Complete a pressed button with `.success(DialogAnswer(button:title:input:))`, and any other
///   end with a ``DialogError``.
///
/// What only the library's implementation does: the box is tied to the request and closed by
/// it, so `IosDialogManager.cancel(_:)` dismisses the dialog and ends the request as
/// ``DialogError/canceled``, and the use case refuses a box that another request already uses
/// (``DialogError/invalidRequest``). With your own implementation, `cancel(_:)` only closes the
/// box (read ``RequestBox/isClosed`` to notice it) and the use case does not refuse a box used
/// twice.
public protocol DialogPresenting: Sendable {
    /// Presents `request` from the view controller `presenter` selects.
    /// - Parameters:
    ///   - request: The dialog to show.
    ///   - presenter: How to choose the view controller to present from.
    ///   - box: The request's box. When it is already closed, show nothing and complete with
    ///     ``DialogError/canceled``.
    ///   - completion: The answer, or why there is none. Call it once, on the main thread, never
    ///     inside this call.
    func present(_ request: DialogRequest, presenter: PresenterSelection, box: RequestBox,
                 completion: @escaping @MainActor @Sendable (Result<DialogAnswer, DialogError>) -> Void)
}
