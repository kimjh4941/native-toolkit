// Hand-off 1 probe: the foreground definition (P1-11) and the presentation steps (P1-12, 5.13.2),
// standing in for the `presenter` option that 1b adds to IosLibrary.
import UIKit

@MainActor
enum ForegroundPresenter {
    /// The top view controller of the key window of a foreground (active or inactive) scene.
    static func topViewController() -> UIViewController? {
        for scene in UIApplication.shared.connectedScenes {
            guard let windowScene = scene as? UIWindowScene,
                  windowScene.activationState == .foregroundActive || windowScene.activationState == .foregroundInactive,
                  let window = windowScene.windows.first(where: { $0.isKeyWindow }) else { continue }
            var top = window.rootViewController
            while let presented = top?.presentedViewController, !presented.isBeingDismissed { top = presented }
            if let top { return top }
        }
        return nil
    }

    static func isSettled(_ viewController: UIViewController) -> Bool {
        viewController.viewIfLoaded?.window != nil && !viewController.isBeingPresented && !viewController.isBeingDismissed
            && viewController.presentedViewController == nil && viewController.transitionCoordinator == nil
    }

    /// P1-13: action sheets and share sheets are anchored at the centre of the presenting view.
    static func anchorCenter(_ viewController: UIViewController, on presenter: UIViewController) {
        guard let popover = viewController.popoverPresentationController,
              popover.sourceView == nil, popover.barButtonItem == nil, popover.sourceItem == nil else { return }
        popover.sourceView = presenter.view
        popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
    }

    /// Steps 2 to 6 of 5.13.2: find the foreground, present when settled, otherwise wait once
    /// (transition completion or the next main turn) and check again.
    static func show(isOpen: @escaping @MainActor () -> Bool,
                     notForeground: @escaping @MainActor () -> Void,
                     failed: @escaping @MainActor () -> Void,
                     present: @escaping @MainActor (UIViewController) -> Void,
                     retried: Bool = false) {
        guard isOpen() else { return }
        guard let top = topViewController() else { notForeground(); return }
        if isSettled(top) { present(top); return }
        if retried { failed(); return }
        let again: @Sendable () -> Void = {
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    show(isOpen: isOpen, notForeground: notForeground, failed: failed, present: present, retried: true)
                }
            }
        }
        let moving = top.presentedViewController ?? top
        if let coordinator = moving.transitionCoordinator, coordinator.isAnimated {
            coordinator.animate(alongsideTransition: nil) { _ in again() }
        } else {
            again()
        }
    }
}
