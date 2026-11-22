// macOS C ABI 1a-9 probe: strings, handles and the one-shot request (completion + release, D-6).
import Foundation
import Synchronization

enum CApiString {
    enum Input { case absent, value(String), invalid }

    /// NULL is .absent, invalid UTF-8 is .invalid.
    static func input(_ pointer: UnsafePointer<CChar>?) -> Input {
        guard let pointer else { return .absent }
        guard let value = String(validatingCString: pointer) else { return .invalid }
        return .value(value)
    }

    /// U+0000 becomes U+FFFD so that the NUL-terminated text is the whole string.
    static func outputUTF8(_ value: String) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(value.utf8.count)
        for scalar in value.unicodeScalars {
            bytes.append(contentsOf: UTF8.encode(scalar.value == 0 ? Unicode.Scalar(0xFFFD)! : scalar)!)
        }
        return bytes
    }
}

/// NUL-terminated bytes owned by the handle.
final class NTKString {
    let storage: UnsafeMutablePointer<UInt8>
    let count: Int

    init(_ value: String) {
        let bytes = CApiString.outputUTF8(value)
        count = bytes.count
        storage = .allocate(capacity: count + 1)
        _ = UnsafeMutableBufferPointer(start: storage, count: count).initialize(from: bytes)
        storage[count] = 0
    }

    deinit { storage.deallocate() }
}

enum Handle {
    static func make(_ object: AnyObject) -> OpaquePointer { OpaquePointer(Unmanaged.passRetained(object).toOpaque()) }

    static func borrow<T: AnyObject>(_ handle: OpaquePointer?, as type: T.Type) -> T? {
        guard let handle else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(handle)).takeUnretainedValue() as? T
    }

    static func free(_ handle: OpaquePointer?) {
        guard let handle else { return }
        Unmanaged<AnyObject>.fromOpaque(UnsafeRawPointer(handle)).release()
    }

    static func string(_ value: String) -> OpaquePointer { make(NTKString(value)) }
}

/// A probe-only mechanism, not part of the contract and not checked by the smoke: for a call made on
/// another thread, it holds main-thread deliveries until the starting entry has run its last statement.
/// (D-6's "never called synchronously inside the function" comes from queuing on main, not from this.) The entry calls `returned()` as its last
/// statement; a delivery that finds it not yet set re-queues itself on main (1 ms) until it is.
/// This is NOT a guarantee that the C function has returned to a caller on another thread: the flag is
/// set before the Swift frames and the C entry unwind, and the caller's code after the call runs in
/// parallel with main. Only for a call made on main is "after the return" guaranteed (main cannot run
/// the delivery while the entry runs).
class ReturnGate: @unchecked Sendable {
    private let flag = Atomic<Bool>(false)

    func returned() {
        ProbeHook.delayBeforeReturn()
        flag.store(true, ordering: .releasing)
    }

    var hasReturned: Bool { flag.load(ordering: .acquiring) }

    /// Runs body on main once the entry has set the flag in its last statement (for a call made on
    /// another thread this is not the return of the C function).
    func onMainAfterReturn(_ body: @escaping @Sendable () -> Void) {
        if pthread_main_np() != 0 && hasReturned {
            body()
            return
        }
        DispatchQueue.main.async { self.waitThen(body) }
    }

    private func waitThen(_ body: @escaping @Sendable () -> Void) {
        guard hasReturned else {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(1)) { self.waitThen(body) }
            return
        }
        body()
    }
}

/// One accepted request: the C callback, user_data and release. @unchecked Sendable: the pointers cross
/// to main unchanged and `done` is touched on main only.
final class Request<Callback>: ReturnGate, @unchecked Sendable {
    let id: UInt64
    let callback: Callback
    let userData: UnsafeMutableRawPointer?
    let release: ntk_release_fn?
    private var done = false

    init(_ callback: Callback, _ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) {
        id = requestIds.wrappingAdd(1, ordering: .relaxed).newValue
        self.callback = callback
        self.userData = userData
        self.release = release
    }

    /// Main only, after the entry's last statement: the completion once, then release once.
    private func finishNow(_ body: (Callback, UnsafeMutableRawPointer?) -> Void) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard !done else { return }
        done = true
        body(callback, userData)
        release?(userData)
    }

    /// Queues the completion on the main queue: never called synchronously inside the starting function
    /// (that is what queuing on main guarantees; the flag only delays it past the entry's last statement).
    func finishAsync(_ body: @escaping @Sendable (Callback, UnsafeMutableRawPointer?) -> Void) {
        DispatchQueue.main.async { self.onMainAfterReturn { self.finishNow(body) } }
    }

    /// Already on main (a delayed block): completes now if the entry set its flag, else waits for it.
    func finishOnMain(_ body: @escaping @Sendable (Callback, UnsafeMutableRawPointer?) -> Void) {
        onMainAfterReturn { self.finishNow(body) }
    }
}

let requestIds = Atomic<UInt64>(0)

/// A request rejected at the entry: release on the calling thread before returning.
func rejectRelease(_ userData: UnsafeMutableRawPointer?, _ release: ntk_release_fn?) {
    release?(userData)
}

/// Probe-only test hook: NTK_PROBE_ENTRY_DELAY_MS (read once) makes every accepting entry sleep that
/// long after it queued its work and before it returns, as if the calling thread were preempted there.
/// The smoke uses it to show that the gate holds the completion back. Never set it in a real host.
enum ProbeHook {
    static let entryDelayMs: UInt32 = {
        guard let text = ProcessInfo.processInfo.environment["NTK_PROBE_ENTRY_DELAY_MS"], let value = UInt32(text) else { return 0 }
        return min(value, 5000)
    }()

    static func delayBeforeReturn() {
        // Only off main: on main the delivery cannot run during the sleep anyway.
        guard entryDelayMs > 0, pthread_main_np() == 0 else { return }
        usleep(entryDelayMs * 1000)
    }
}
