//
//  PresenterSelection.swift
//  IosLibrary
//

/// How an operation that shows system UI chooses the view controller to present from.
///
/// Pass one to the operations that present a dialog or a share sheet, or that may show a system
/// prompt (requesting the notification permission, opening the notification settings).
///
/// | Value | View controller | Checks before presenting |
/// |---|---|---|
/// | ``firstActiveScene`` (default) | The topmost presented view controller of the key window of the first `foregroundActive` window scene | Searched once, no waiting: the behavior of each operation before this type existed. A dialog is presented whatever the state of that view controller; a share sheet fails when that view controller is being presented or dismissed or is presenting something |
/// | ``foreground`` | The topmost presented view controller that is not being dismissed, of the key window of a `foregroundActive` or `foregroundInactive` window scene | When none is found the operation fails as not in the foreground. When that view controller is in a transition, the operation waits once for the transition to end and checks again; it fails when it is still not settled |
/// | ``viewController(_:)`` | The one the closure returns, called once on the main thread | When the closure returns `nil`, the operation fails as not in the foreground. Otherwise the same single wait as ``foreground`` |
///
/// An operation that does not present a view controller itself but may show a system prompt
/// (requesting the notification permission, opening the settings) only checks that the app is
/// in the foreground: ``firstActiveScene`` checks nothing, ``foreground`` needs a view
/// controller as above but does not wait for it to settle, and ``viewController(_:)`` needs the
/// returned view controller to be in a window.
///
/// - Note: The operations that take a `PresenterSelection` (dialogs, share sheets, the
///   notification permission request and settings) are added in later commits of 2.0.0.
///
/// `foregroundInactive` covers the moments when the app is visible but not active: right after
/// launch, and while Control Center or Notification Center is pulled over the app.
///
/// The type is a struct with static members, so that a value reads like an enum case at the call
/// site (`presenter: .foreground`) and later values can be added without breaking a `switch`.
/// Values cannot be compared, because one of them holds a closure.
///
/// ## Threading
/// `PresenterSelection` is `Sendable`, so it can be passed to the operations from any thread.
/// The closure of ``viewController(_:)`` always runs on the main thread.
public struct PresenterSelection: Sendable {
    /// The internal form. `provided` keeps the closure as `AnyObject` so that this Domain file
    /// does not import UIKit; `PresenterSelection+UIKit.swift` builds it from a view controller.
    enum Kind: Sendable {
        case firstActiveScene
        case foreground
        case provided(@MainActor @Sendable () -> AnyObject?)
    }

    let kind: Kind

    init(kind: Kind) {
        self.kind = kind
    }

    /// The topmost presented view controller of the key window of the first `foregroundActive`
    /// window scene, searched once without waiting.
    ///
    /// This is the default of every operation that takes a presenter, and the way they chose a
    /// view controller before ``PresenterSelection`` existed.
    public static let firstActiveScene = PresenterSelection(kind: .firstActiveScene)

    /// The topmost view controller in the foreground: of the key window of a `foregroundActive`
    /// or `foregroundInactive` window scene, following the presented view controllers that are
    /// not being dismissed.
    ///
    /// When no such view controller exists, the operation fails as not in the foreground. When
    /// it is in a transition (being presented or dismissed, or presenting another view
    /// controller), the operation waits once for the transition to end, checks again on the
    /// next turn of the main queue, and fails when it is still not settled.
    public static let foreground = PresenterSelection(kind: .foreground)
}
