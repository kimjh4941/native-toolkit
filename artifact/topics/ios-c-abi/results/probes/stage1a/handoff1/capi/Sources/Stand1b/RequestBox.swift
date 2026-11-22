// Hand-off 1 probe: stand-ins for what 1b adds to IosLibrary (part 1, 5.13.1, S-15). IosLibrary has
// no request box or release watch yet, so the probe keeps a minimal one here.
import Foundation
import ObjectiveC
import Synchronization
import UIKit

/// Closed once by whoever comes first (handler, cancel, presentation failure, release watch).
/// @unchecked Sendable (P1-17 (4)): the state is behind a Mutex; onClose runs on main.
final class RequestBox<Outcome: Sendable>: @unchecked Sendable {
    private let state = Mutex<Outcome?>(nil)
    private let onClose: @Sendable (Outcome) -> Void

    init(onClose: @escaping @Sendable (Outcome) -> Void) { self.onClose = onClose }

    var isClosed: Bool { state.withLock { $0 != nil } }

    /// Any thread. Only the first close counts; its outcome is handed to main.
    @discardableResult
    func close(_ outcome: Outcome) -> Bool {
        let first = state.withLock { value -> Bool in
            guard value == nil else { return false }
            value = outcome
            return true
        }
        if first { DispatchQueue.main.async { self.onClose(outcome) } }
        return first
    }
}

/// Tied to a presented view controller; when that view controller is freed, deinit reports whether
/// the presentation had finished (P1-14). Touches neither the view controller nor main state.
final class ReleaseWatch: @unchecked Sendable {
    let presented = Atomic<Bool>(false)
    private let onRelease: @Sendable (_ presented: Bool) -> Void

    init(_ onRelease: @escaping @Sendable (_ presented: Bool) -> Void) { self.onRelease = onRelease }

    deinit { onRelease(presented.load(ordering: .acquiring)) }

    /// The association key: only its address is used (P1-17 (5)).
    private nonisolated(unsafe) static let key = UnsafeMutableRawPointer.allocate(byteCount: 1, alignment: 1)

    @MainActor func attach(to viewController: UIViewController) {
        objc_setAssociatedObject(viewController, Self.key, self, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
}
