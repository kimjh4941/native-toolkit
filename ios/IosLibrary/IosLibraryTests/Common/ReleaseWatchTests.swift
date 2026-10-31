//
//  ReleaseWatchTests.swift
//  IosLibraryTests
//

import Foundation
import Testing
import UIKit
@testable import IosLibrary

/// UT-05: the release watch (design 6.3.4, P1-14).
@MainActor
struct ReleaseWatchTests {

    /// Attaches a watch for `box` to a new object, lets `prepare` act on the watch, then frees the
    /// object. Nothing else holds the object or the watch.
    private func attachAndFree(box: RequestBox, _ prepare: (ReleaseWatch) -> Void = { _ in }) {
        autoreleasepool {
            var owner: NSObject? = NSObject()
            let watch = ReleaseWatch(box: box)
            watch.attach(to: owner!)
            prepare(watch)
            owner = nil
        }
    }

    @Test func freedBeforeThePresentationCompletedIsAPresentationFailure() {
        let box = RequestBox()
        attachAndFree(box: box)

        #expect(box.outcome?.testName == "presentationFailed")
    }

    @Test func freedAfterThePresentationCompletedIsDismissedBySystem() {
        let box = RequestBox()
        attachAndFree(box: box) { $0.markPresented() }

        #expect(box.outcome?.testName == "dismissedBySystem")
    }

    @Test func theWatchDoesNotCloseWhileTheObjectIsAlive() {
        let box = RequestBox()
        let owner = NSObject()
        let watch = ReleaseWatch(box: box)
        watch.attach(to: owner)

        #expect(!box.isClosed)
        withExtendedLifetime(owner) {}
    }

    @Test func aNormalResultIsNeverReplaced() async {
        let box = RequestBox()
        let recorder = OutcomeRecorder()
        #expect(box.attach { recorder.record($0) })

        attachAndFree(box: box) { _ in
            // The user answered before the view controller went away.
            box.close(.completed("answer"))
        }
        await drainMainQueue()

        #expect(box.outcome?.testName == "completed(answer)")
        #expect(recorder.names == ["completed(answer)"])
    }

    @Test func aCancellationIsNeverReplaced() {
        let box = RequestBox()
        attachAndFree(box: box) { watch in
            watch.markPresented()
            box.close(.canceled)
        }

        #expect(box.outcome?.testName == "canceled")
    }

    /// Through the procedure: presented, then freed (dismissed from outside).
    @Test func aPresentedViewControllerFreedLaterIsDismissedBySystem() async {
        let environment = FakePresentationEnvironment()
        environment.foreground = FakeViewController("top")
        let box = RequestBox()
        let recorder = OutcomeRecorder()
        #expect(box.attach { recorder.record($0) })

        autoreleasepool {
            var presented: FakeViewController? = FakeViewController("presented")
            PresentationProcedure.present(presented!, presenter: .foreground, box: box,
                                          firstActiveScenePolicy: .presentAnyway, environment: environment)
            environment.finishPresentations()
            #expect(!box.isClosed)
            presented = nil
        }
        await drainMainQueue()

        #expect(recorder.names == ["dismissedBySystem"])
    }

    /// The last owner of the watched object goes away on a background thread: the box closes
    /// there (the watch's `deinit` touches no main-actor state, so nothing traps) and the
    /// completion still arrives on main, exactly once.
    @Test func freedOnABackgroundThreadDeliversOnMainOnce() async {
        let box = RequestBox()
        let recorder = OutcomeRecorder()
        #expect(box.attach { recorder.record($0) })

        // Hand the only strong reference to a background thread as a plain address.
        let address: UInt = autoreleasepool {
            let owner = NSObject()
            let watch = ReleaseWatch(box: box)
            watch.attach(to: owner)
            watch.markPresented()
            return UInt(bitPattern: Unmanaged.passRetained(owner).toOpaque())
        }
        #expect(!box.isClosed)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Thread.detachNewThread {
                Unmanaged<NSObject>.fromOpaque(UnsafeRawPointer(bitPattern: address)!).release()
                continuation.resume()
            }
        }
        #expect(box.outcome?.testName == "dismissedBySystem")
        await drainMainQueue(times: 2)

        #expect(recorder.names == ["dismissedBySystem"])
        #expect(recorder.all.allSatisfy { $0.isMainThread })
    }

    /// With a real view controller. Skipped with the Thread Sanitizer: in hand-off 1 a dismissed
    /// `UIAlertController` was not freed within 15 s in the TSan build, so a test that waits for
    /// a view controller to be freed cannot pass there (design 6.3.4, RK-11).
    @Test(.disabled(if: isThreadSanitizerEnabled, "UIKit view controllers are not freed promptly under TSan (hand-off 1)"))
    func aRealViewControllerClosesTheBoxWhenFreed() async throws {
        let box = RequestBox()
        autoreleasepool {
            var viewController: UIViewController? = UIAlertController(title: "t", message: nil, preferredStyle: .alert)
            ReleaseWatch(box: box).attach(to: viewController!)
            viewController = nil
        }
        for _ in 0..<100 where !box.isClosed {
            try await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(box.outcome?.testName == "presentationFailed")
    }
}
