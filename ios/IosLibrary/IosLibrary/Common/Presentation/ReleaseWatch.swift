//
//  ReleaseWatch.swift
//  IosLibrary
//

import ObjectiveC
import os
import Synchronization

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ReleaseWatch")

/// Closes a request box when the view controller presented for it is freed (P1-14, part 1,
/// 5.13.1).
///
/// ``attach(to:)`` ties the watch to the presented view controller as an associated object, so
/// the view controller is its only owner. When the view controller is freed without the box
/// being closed (dismissed from outside, or UIKit declined the presentation), `deinit` closes
/// the box: ``RequestBoxOutcome/dismissedBySystem`` when `present`'s completion came
/// (``markPresented()``), ``RequestBoxOutcome/presentationFailed`` when it never came. A box
/// that is already closed stays as it is, so a normal result is never replaced.
///
/// `onRelease`, when given, runs in `deinit` after the box is closed, on whatever thread frees the
/// view controller. It must only hand an ID to the main queue (``PresentationRecords``): it is
/// immutable and `Sendable`, so the watch stays checked `Sendable`.
///
/// This relies on the library holding the presented view controller weakly, and on the box's
/// close handler and the view controller's handlers not capturing the view controller strongly
/// (otherwise the view controller, the watch and the box keep one another alive).
///
/// `Sendable` without `@unchecked`: the box is `Sendable` and the flag is an `Atomic`. `deinit`
/// runs on whatever thread frees the view controller and touches neither the view controller
/// nor main-actor state.
final class ReleaseWatch: Sendable {
    private let box: RequestBox
    private let presented = Atomic<Bool>(false)
    private let onRelease: (@Sendable () -> Void)?

    /// The associated-object key. Only its address is used, never what it points to, so the
    /// unsafe opt-out is limited to an immutable pointer (P1-17 (5)).
    private nonisolated(unsafe) static let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    init(box: RequestBox, onRelease: (@Sendable () -> Void)? = nil) {
        logger.log(level: .libraryDebug, "[init] onRelease: \(onRelease != nil ? "provided" : "nil", privacy: .public)")
        self.box = box
        self.onRelease = onRelease
    }

    deinit {
        let wasPresented = presented.load(ordering: .acquiring)
        logger.log(level: .libraryDebug, "[deinit] wasPresented: \(wasPresented, privacy: .public)")
        box.close(wasPresented ? .dismissedBySystem : .presentationFailed)
        onRelease?()
    }

    /// Makes `object` (the presented view controller) the owner of this watch. Call it once per
    /// request, before presenting.
    @MainActor
    func attach(to object: AnyObject) {
        logger.log(level: .libraryDebug, "[attach]")
        objc_setAssociatedObject(object, Self.key, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    /// Notes that `present`'s completion came, so that a later release means the presented UI
    /// went away rather than that it never appeared.
    func markPresented() {
        logger.log(level: .libraryDebug, "[markPresented]")
        presented.store(true, ordering: .releasing)
    }
}
