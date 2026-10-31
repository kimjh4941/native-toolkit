//
//  HostAppSupport.swift
//  IosLibraryTests
//

import Foundation
import Synchronization
import Testing
import UIKit
@testable import IosLibrary

/// One test at a time on the host app's screen.
///
/// The tests run inside `IosLibraryTestHost`, which has one window scene and no window. A test
/// that presents real UI makes a key window (``HostWindow``); a test that relies on there being
/// none (the "nothing to present from" paths) must not overlap with it. Both kinds run their body
/// inside ``withHostScreen(_:)``, which lets one body run at a time whatever the suites'
/// parallelism.
actor HostScreen {
    static let shared = HostScreen()

    private var isBusy = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    func release() {
        if waiting.isEmpty {
            isBusy = false
        } else {
            waiting.removeFirst().resume()
        }
    }
}

/// Runs `body` on the main actor while no other test uses the host app's screen.
@MainActor
func withHostScreen<T>(_ body: @MainActor () async throws -> T) async rethrows -> T {
    await HostScreen.shared.acquire()
    do {
        let value = try await body()
        await HostScreen.shared.release()
        return value
    } catch {
        await HostScreen.shared.release()
        throw error
    }
}

/// Runs `body` with a new ``HostWindow`` while no other test uses the host app's screen, and
/// closes the window afterwards (also when `body` throws).
@MainActor
func withHostWindow<T>(_ body: @MainActor (HostWindow) async throws -> T) async throws -> T {
    try await withHostScreen {
        let host = try HostWindow()
        do {
            let value = try await body(host)
            await host.close()
            return value
        } catch {
            await host.close()
            throw error
        }
    }
}

/// A key window on the host app's scene, with a plain root view controller to present from.
/// ``close()`` dismisses what is presented and removes the window, so that the next test finds
/// no key window again.
@MainActor
final class HostWindow {
    let window: UIWindow
    let root: UIViewController

    init() throws {
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first,
                                 "the host app must have a window scene")
        window = UIWindow(windowScene: scene)
        root = UIViewController()
        root.view.backgroundColor = .systemBackground
        window.rootViewController = root
        window.makeKeyAndVisible()
    }

    /// The view controllers presented above the root, bottom first.
    var presentedChain: [UIViewController] {
        var chain: [UIViewController] = []
        var current = root.presentedViewController
        while let next = current {
            chain.append(next)
            current = next.presentedViewController
        }
        return chain
    }

    /// The alert presented directly on the root, if any.
    var presentedAlert: UIAlertController? {
        root.presentedViewController as? UIAlertController
    }

    func close() async {
        if root.presentedViewController != nil {
            root.dismiss(animated: false)
            _ = await waitUntil(timeout: 5) { self.root.presentedViewController == nil }
        }
        window.isHidden = true
        window.rootViewController = nil
    }
}

/// Polls `condition` on the main actor until it holds or `timeout` seconds pass.
/// - Returns: Whether the condition held.
@MainActor
func waitUntil(timeout: TimeInterval = 5, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return true
}

/// Records values on the main actor, in arrival order, with whether they arrived on the main
/// thread.
@MainActor
final class MainRecorder<Value> {
    private(set) var values: [Value] = []
    private(set) var allOnMainThread = true

    func record(_ value: Value) {
        allOnMainThread = allOnMainThread && Thread.isMainThread
        values.append(value)
    }
}

/// The sessions an ``AlertDialogPresenter`` created, in order.
@MainActor
final class SessionRecorder {
    private(set) var sessions: [DialogSession] = []

    func record(_ session: DialogSession) {
        sessions.append(session)
    }

    var last: DialogSession? { sessions.last }
}

extension AlertDialogPresenter where Environment == UIKitPresentationEnvironment {
    /// The UIKit presenter, with `recorder` seeing each session.
    static func recording(into recorder: SessionRecorder) -> AlertDialogPresenter<UIKitPresentationEnvironment> {
        AlertDialogPresenter(makeEnvironment: { UIKitPresentationEnvironment() },
                             observeSession: { session in recorder.record(session) })
    }
}

extension DialogSession {
    /// Presses the library button at `index` as a tap would: runs its `UIAlertAction` handler,
    /// then (unless `dismissing` is `false`) dismisses the alert as UIKit does after a tap.
    func press(_ index: Int, dismissing: Bool = true) {
        actionHandlers[index](actions[index])
        if dismissing {
            alert?.presentingViewController?.dismiss(animated: false)
        }
    }
}
