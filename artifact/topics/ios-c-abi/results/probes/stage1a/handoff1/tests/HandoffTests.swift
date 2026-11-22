// Hand-off 1 probe: XCTest for the Dialog and Share probe functions (part 1, 5.7, 5.13, P1-24).
// Lines starting with "HANDOFF1:" are measured values copied into the hand-off notes.
import Foundation
import MachO
import IosLibraryCApi
import ObjectiveC
import UIKit
import XCTest

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var callbacks = 0
    private(set) var releases = 0
    private(set) var callbackOnMain = true
    private(set) var releaseOnMain = true
    private(set) var releaseAfterCallback = true
    private(set) var callbackBeforeReturn = false
    private(set) var releaseThread: Thread?
    private(set) var error: Int32 = -100
    private(set) var button: Int32 = -100
    private(set) var completed: Int32 = -100
    private(set) var requestId: UInt64 = 0
    private var returned = false
    var cancelInsideCallback = false
    let expectation: XCTestExpectation?

    /// user_data is passed unretained, and a late release (after its test) must not reach a freed object.
    private static let keepAlive = NSMutableArray()

    init(_ expectation: XCTestExpectation? = nil) {
        expectation?.assertForOverFulfill = false   // a second release is counted, not a crash
        self.expectation = expectation
        objc_sync_enter(Recorder.keepAlive); Recorder.keepAlive.add(self); objc_sync_exit(Recorder.keepAlive)
    }

    var pointer: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    static func from(_ p: UnsafeMutableRawPointer?) -> Recorder { Unmanaged.fromOpaque(p!).takeUnretainedValue() }

    func markReturned() { lock.withLock { returned = true } }

    func onCallback(requestId: UInt64, error: Int32, button: Int32 = -100, completed: Int32 = -100) {
        lock.withLock {
            callbacks += 1
            callbackOnMain = callbackOnMain && Thread.isMainThread
            callbackBeforeReturn = callbackBeforeReturn || !returned
            self.requestId = requestId
            self.error = error
            self.button = button
            self.completed = completed
        }
        if cancelInsideCallback { XCTAssertEqual(ntk_probe_dialog_cancel(requestId), 0) }
    }

    func onRelease() {
        lock.withLock {
            releases += 1
            releaseOnMain = releaseOnMain && Thread.isMainThread
            releaseThread = Thread.current
            releaseAfterCallback = releaseAfterCallback && callbacks == 1
        }
        expectation?.fulfill()
    }

    var once: Bool { lock.withLock { callbacks == 1 && releases == 1 && callbackOnMain && releaseOnMain && releaseAfterCallback && !callbackBeforeReturn } }
}

let dialogDone: ntk_probe_dialog_done_fn = { ud, id, error, _, button in Recorder.from(ud).onCallback(requestId: id, error: error, button: button) }
let shareDone: ntk_probe_share_done_fn = { ud, error, _, completed, activity in
    ntk_string_free(activity)
    Recorder.from(ud).onCallback(requestId: 0, error: error, completed: completed)
}
let releaseFn: ntk_release_fn = { ud in Recorder.from(ud).onRelease() }

private let CANCELED: Int32 = 6, CANCELED_BY_SYSTEM: Int32 = 7, DIALOG_NOT_FOREGROUND: Int32 = 8
private let INVALID: Int32 = 1, SHARE_NOT_FOREGROUND: Int32 = 6, EMPTY_CONTENT: Int32 = 7

final class HandoffTests: XCTestCase {
    private var window: UIWindow { UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first! }
    private var root: UIViewController { window.rootViewController! }

    @discardableResult
    private func waitUntil(_ seconds: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        return condition()
    }

    /// Lets queued main blocks (a late second release, say) run before anything is counted.
    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

    override func tearDown() {
        if root.presentedViewController != nil { root.dismiss(animated: false) }
        waitUntil(2) { root.presentedViewController == nil }
        super.tearDown()
    }

    private func show(_ recorder: Recorder, title: String? = "T") -> UInt64 {
        var id: UInt64 = 0
        let error = title.withOptionalCString { ntk_probe_dialog_show_alert($0, "M", "Yes", "No", dialogDone, recorder.pointer, releaseFn, &id) }
        recorder.markReturned()
        XCTAssertEqual(error, 0)
        return id
    }

    func testCommonStillHolds() {
        XCTAssertEqual(ntk_version(), 0x020000)
        XCTAssertEqual(ntk_last_system_code(), 0)
        var request = ntk_probe_echo_request()
        request.struct_size = UInt32(MemoryLayout<ntk_probe_echo_request>.size)
        var out: OpaquePointer?
        XCTAssertEqual(ntk_probe_echo(&request, &out), 0)
        XCTAssertNotNil(ntk_string_data(out))
        XCTAssertNil(ntk_bytes_data(out), "a string handle is not a bytes handle (R-30)")
        ntk_string_free(out)
    }

    func testDialogRejectsAtTheEntry() {
        let done = expectation(description: "background")
        DispatchQueue.global().async {
            var id: UInt64 = 77
            let r1 = Recorder()
            XCTAssertEqual(ntk_probe_dialog_show_alert("T", nil, nil, nil, nil, r1.pointer, releaseFn, &id), INVALID)
            XCTAssertEqual(r1.releases, 1)
            XCTAssertEqual(r1.releaseThread, Thread.current)
            let r2 = Recorder()
            let bad: [CChar] = [CChar(bitPattern: 0xFF), 0]
            XCTAssertEqual(ntk_probe_dialog_show_alert(bad, nil, nil, nil, dialogDone, r2.pointer, releaseFn, &id), INVALID)
            XCTAssertEqual(r2.releases, 1)
            XCTAssertEqual(r2.callbacks, 0)
            XCTAssertEqual(id, 77, "value outputs are not written on failure")
            XCTAssertEqual(ntk_probe_dialog_show_alert(nil, nil, nil, nil, nil, nil, nil, nil), INVALID)
            done.fulfill()
        }
        wait(for: [done], timeout: 5)
    }

    /// Show and cancel in the same main turn: the queued start sees CANCEL_REQUESTED and never shows.
    /// (From another thread main may start first; then the alert is shown and closed again.)
    func testCancelBeforeTheAlertIsShown() {
        let recorder = Recorder(expectation(description: "release"))
        let id = show(recorder)
        XCTAssertGreaterThan(id, 0)
        XCTAssertEqual(ntk_probe_dialog_cancel(id), 0)
        XCTAssertEqual(recorder.callbacks, 0, "nothing is called inside the functions")
        wait(for: [recorder.expectation!], timeout: 5)
        settle()
        XCTAssertTrue(recorder.once)
        XCTAssertEqual(recorder.error, CANCELED)
        XCTAssertEqual(recorder.button, -1)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNil(root.presentedViewController, "a cancelled request is never shown")
    }

    func testCancelAfterTheAlertIsShown() {
        let recorder = Recorder(expectation(description: "release"))
        let id = show(recorder)
        XCTAssertTrue(waitUntil { (root.presentedViewController as? UIAlertController)?.isBeingPresented == false })
        DispatchQueue.global().async { XCTAssertEqual(ntk_probe_dialog_cancel(id), 0) }
        wait(for: [recorder.expectation!], timeout: 5)
        settle()
        XCTAssertTrue(recorder.once)
        XCTAssertEqual(recorder.error, CANCELED)
        XCTAssertTrue(waitUntil { root.presentedViewController == nil }, "the alert is closed")
        XCTAssertEqual(ntk_probe_dialog_cancel(id), 0, "cancelling a finished request does nothing")
        XCTAssertEqual(ntk_probe_dialog_cancel(999_999), 0, "an unknown ID does nothing")
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(recorder.callbacks, 1)
        XCTAssertEqual(recorder.releases, 1)
    }

    /// G-7: an alert dismissed by someone else is freed, and the release watch reports it.
    func testAlertDismissedFromOutside() throws {
        // Measured: under TSan the dismissed alert was not freed within 15 s, so the watch never fired.
        let underTSan = (0..<_dyld_image_count()).contains { _dyld_get_image_name($0).map { strstr($0, "libclang_rt.tsan") != nil } ?? false }
        if underTSan {
            throw XCTSkip("under TSan the dismissed alert is not freed in time (hand-off 1, chapter 6)")
        }
        let recorder = Recorder(expectation(description: "release"))
        _ = show(recorder)
        XCTAssertTrue(waitUntil { (root.presentedViewController as? UIAlertController)?.isBeingPresented == false })
        root.dismiss(animated: false)
        wait(for: [recorder.expectation!], timeout: 15)   // the alert is freed later under TSan
        print("HANDOFF1: alert dismissed from outside -> error \(recorder.error), callbacks \(recorder.callbacks), releases \(recorder.releases)")
        settle()
        XCTAssertTrue(recorder.once)
        XCTAssertEqual(recorder.error, CANCELED_BY_SYSTEM)
    }

    func testNotForegroundAndCancelInsideTheCompletion() {
        let window = self.window
        window.isHidden = true   // no key window: not in the foreground (P1-11)
        defer { window.makeKeyAndVisible() }
        let recorder = Recorder(expectation(description: "release"))
        recorder.cancelInsideCallback = true
        _ = show(recorder)
        wait(for: [recorder.expectation!], timeout: 5)
        settle()
        XCTAssertTrue(recorder.once)
        XCTAssertEqual(recorder.error, DIALOG_NOT_FOREGROUND)

        let share = Recorder(expectation(description: "share release"))
        XCTAssertEqual(ntk_probe_share_text("x", shareDone, share.pointer, releaseFn), 0)
        share.markReturned()
        wait(for: [share.expectation!], timeout: 5)
        settle()
        XCTAssertTrue(share.once)
        XCTAssertEqual(share.error, SHARE_NOT_FOREGROUND)
    }

    /// P1-12: the second alert of the same main turn waits for the first and goes on top of it.
    func testTwoAlertsInTheSameTurn() {
        let first = Recorder(expectation(description: "first"))
        let second = Recorder(expectation(description: "second"))
        let id1 = show(first, title: "first")
        let id2 = show(second, title: "second")
        let stacked = waitUntil {
            guard let a = root.presentedViewController as? UIAlertController, let b = a.presentedViewController as? UIAlertController else { return false }
            return !b.isBeingPresented
        }
        print("HANDOFF1: two alerts in the same turn stacked = \(stacked), second callbacks before cancel = \(second.callbacks)")
        XCTAssertTrue(stacked)
        XCTAssertEqual(ntk_probe_dialog_cancel(id2), 0)
        XCTAssertEqual(ntk_probe_dialog_cancel(id1), 0)
        wait(for: [first.expectation!, second.expectation!], timeout: 5)
        settle()
        XCTAssertTrue(first.once && second.once)
        XCTAssertEqual([first.error, second.error], [CANCELED, CANCELED])
        let closed = waitUntil { root.presentedViewController == nil }
        print("HANDOFF1: after cancelling both (top first), both closed = \(closed)")
        XCTAssertTrue(closed)
    }

    /// The TSan target: many threads show and cancel at once; every request ends once.
    func testConcurrentShowAndCancel() {
        let count = 8 * 10
        let recorders = (0..<count).map { _ in Recorder(expectation(description: "r")) }
        DispatchQueue.concurrentPerform(iterations: 8) { t in
            for i in 0..<10 {
                let r = recorders[t * 10 + i]
                var id: UInt64 = 0
                XCTAssertEqual(ntk_probe_dialog_show_alert("c", nil, nil, nil, dialogDone, r.pointer, releaseFn, &id), 0)
                r.markReturned()
                XCTAssertEqual(ntk_probe_dialog_cancel(id), 0)
            }
        }
        waitForExpectations(timeout: 20)
        settle()
        XCTAssertTrue(recorders.allSatisfy { $0.once && $0.error == CANCELED })
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertNil(root.presentedViewController)
    }

    func testShareRejectsAtTheEntry() {
        for (text, expected) in [(nil, INVALID), ("", EMPTY_CONTENT)] as [(String?, Int32)] {
            let r = Recorder()
            XCTAssertEqual(text.withOptionalCString { ntk_probe_share_text($0, shareDone, r.pointer, releaseFn) }, expected)
            XCTAssertEqual(r.releases, 1)
            XCTAssertEqual(r.callbacks, 0)
        }
        let r = Recorder()
        XCTAssertEqual(ntk_probe_share_text("x", nil, r.pointer, releaseFn), INVALID)
        XCTAssertEqual(r.releases, 1)
    }

    /// P1-13 and G-7: the share sheet is anchored (iPad) and what a dismissal from outside reports.
    func testShareSheetAnchorAndOutsideDismissal() {
        let recorder = Recorder()   // the completion may never come (measured, G-7)
        XCTAssertEqual(ntk_probe_share_text("Handoff text", shareDone, recorder.pointer, releaseFn), 0)
        recorder.markReturned()
        let shown = waitUntil(8) { (root.presentedViewController as? UIActivityViewController)?.isBeingPresented == false }
        XCTAssertTrue(shown)
        if let sheet = root.presentedViewController as? UIActivityViewController {
            let popover = sheet.popoverPresentationController
            print("HANDOFF1: idiom=\(UIDevice.current.userInterfaceIdiom.rawValue) share popover sourceView=\(popover?.sourceView != nil) rect=\(popover.map { NSCoder.string(for: $0.sourceRect) } ?? "-")")
        }
        root.dismiss(animated: false)
        let ended = waitUntil(5) { recorder.releases == 1 }
        print("HANDOFF1: share dismissed from outside -> ended=\(ended) error=\(recorder.error) completed=\(recorder.completed) callbacks=\(recorder.callbacks) releases=\(recorder.releases)")
        XCTAssertLessThanOrEqual(recorder.callbacks, 1)
        XCTAssertEqual(recorder.callbacks, recorder.releases)
        if ended { XCTAssertTrue(recorder.once) }
    }

    /// D-11 (2): the capi image registers only module-qualified Swift classes.
    func testObjectiveCClasses() {
        var info = Dl_info()
        XCTAssertNotEqual(dladdr(unsafeBitCast(ntk_version as @convention(c) () -> UInt32, to: UnsafeRawPointer.self), &info), 0)
        var count: UInt32 = 0
        let names = objc_copyClassNamesForImage(info.dli_fname, &count)
        let list = (0..<Int(count)).map { String(cString: names![$0]) }
        free(names)
        print("HANDOFF1: objc classes = \(list)")
        XCTAssertTrue(list.allSatisfy { $0.hasPrefix("IosLibraryCApi.") })
    }
}

extension Optional where Wrapped == String {
    func withOptionalCString<R>(_ body: (UnsafePointer<CChar>?) -> R) -> R {
        switch self {
        case .some(let s): return s.withCString { body($0) }
        case .none: return body(nil)
        }
    }
}
