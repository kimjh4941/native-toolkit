//
//  PresenterSelection+UIKit.swift
//  IosLibrary
//

import os
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "PresenterSelection")

extension PresenterSelection {
    /// The view controller that `provider` returns.
    ///
    /// The operation calls `provider` once, on the main thread, when it is about to present, so
    /// the closure can return the view controller that is current at that moment. When it
    /// returns `nil`, the operation fails as not in the foreground. When the view controller is
    /// not settled (not in a window, being presented or dismissed, already presenting another
    /// view controller, or in a transition), the operation waits once for the transition to end,
    /// checks the same view controller again, and fails when it is still not settled.
    ///
    /// The view controller is used as it is: the operation does not look for a view controller
    /// it presents.
    ///
    /// ```swift
    /// // In a view controller: present from this view controller while it is alive.
    /// let presenter: PresenterSelection = .viewController { [weak self] in self }
    /// ```
    ///
    /// - Parameter provider: Returns the view controller to present from. Capture the view
    ///   controller weakly: the operation keeps the closure until it has presented.
    /// - Returns: A selection that uses the returned view controller.
    public static func viewController(
        _ provider: @escaping @MainActor @Sendable () -> UIViewController?
    ) -> PresenterSelection {
        logger.log(level: .libraryDebug, "[viewController] provider: provided")
        return PresenterSelection(kind: .provided { provider() })
    }
}
