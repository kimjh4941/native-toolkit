//
//  ForegroundLocatorTests.swift
//  IosLibraryTests
//

import Testing
import UIKit
@testable import IosLibrary

/// UT-02: the two searches of `ForegroundLocator` over fake scenes (design 6.3.1, part 1 5.13).
@MainActor
struct ForegroundLocatorTests {

    /// A view controller as the rules see it.
    final class Node {
        let name: String
        var presented: Node?
        var isBeingDismissed = false

        init(_ name: String, presenting presented: Node? = nil) {
            self.name = name
            self.presented = presented
        }
    }

    private typealias Scene = ForegroundLocator.Scene<Node>

    private func scene(
        _ state: UIScene.ActivationState,
        root: Node?,
        isWindowScene: Bool = true,
        hasKeyWindow: Bool = true
    ) -> Scene {
        Scene(activationState: state, isWindowScene: isWindowScene, hasKeyWindow: hasKeyWindow, keyWindowRoot: root)
    }

    private func firstActive(_ scenes: [Scene]) -> String? {
        ForegroundLocator.firstActiveSceneTop(in: scenes, presented: { $0.presented })?.name
    }

    private func foreground(_ scenes: [Scene]) -> String? {
        ForegroundLocator.foregroundTop(in: scenes, presented: { $0.presented }, isBeingDismissed: { $0.isBeingDismissed })?.name
    }

    // MARK: - .firstActiveScene (the search of getRootViewController)

    @Test func currentSearchTakesTheFirstActiveSceneAndEveryPresentedViewController() {
        let dismissing = Node("dismissing")
        dismissing.isBeingDismissed = true
        let root = Node("root", presenting: Node("sheet", presenting: dismissing))
        let scenes = [scene(.background, root: Node("other")), scene(.foregroundActive, root: root)]

        // Also the view controller being dismissed: the search has never skipped it.
        #expect(firstActive(scenes) == "dismissing")
    }

    @Test func currentSearchDoesNotUseInactiveScenes() {
        #expect(firstActive([scene(.foregroundInactive, root: Node("root"))]) == nil)
        #expect(firstActive([scene(.background, root: Node("root")), scene(.unattached, root: Node("root"))]) == nil)
    }

    @Test func currentSearchStopsAtTheFirstActiveSceneEvenWhenItCannotBeUsed() {
        let usable = scene(.foregroundActive, root: Node("usable"))
        // The first foregroundActive scene decides: not a window scene, or without a key window,
        // means no view controller (`first(where:)` and then `as? UIWindowScene`).
        #expect(firstActive([scene(.foregroundActive, root: Node("x"), isWindowScene: false), usable]) == nil)
        #expect(firstActive([scene(.foregroundActive, root: Node("x"), hasKeyWindow: false), usable]) == nil)
        #expect(firstActive([scene(.foregroundActive, root: nil), usable]) == nil)
    }

    // MARK: - .foreground

    @Test func foregroundAcceptsAnInactiveScene() {
        // Right after launch, or with Control Center pulled over the app.
        #expect(foreground([scene(.foregroundInactive, root: Node("root"))]) == "root")
    }

    @Test func foregroundSkipsAViewControllerBeingDismissed() {
        let dismissing = Node("dismissing", presenting: Node("above"))
        dismissing.isBeingDismissed = true
        let root = Node("root", presenting: Node("sheet", presenting: dismissing))

        #expect(foreground([scene(.foregroundActive, root: root)]) == "sheet")
    }

    @Test func foregroundNeedsAWindowSceneWithTheKeyWindow() {
        #expect(foreground([scene(.background, root: Node("bg")), scene(.unattached, root: Node("u"))]) == nil)
        #expect(foreground([scene(.foregroundActive, root: Node("a"), isWindowScene: false)]) == nil)
        #expect(foreground([scene(.foregroundActive, root: Node("a"), hasKeyWindow: false)]) == nil)
        #expect(foreground([scene(.foregroundActive, root: nil)]) == nil)
        // Unlike the current search, a later scene is used when the first one cannot be.
        #expect(foreground([scene(.foregroundActive, root: Node("a"), hasKeyWindow: false),
                            scene(.foregroundInactive, root: Node("b"))]) == "b")
    }

    @Test func foregroundPrefersAnActiveSceneWhenMoreThanOneHasAKeyWindow() {
        let scenes = [scene(.foregroundInactive, root: Node("inactive")), scene(.foregroundActive, root: Node("active"))]
        #expect(foreground(scenes) == "active")
    }

    // MARK: - UIKit

    /// The unit tests have no host app, so there is no scene: both searches find nothing, and
    /// `getRootViewController()` gives what the current search gives. The searches over real
    /// scenes are covered by the sample's UI tests (Dialog D1 to D15, Share S1 to S16).
    @Test func withoutScenesBothSearchesFindNothing() {
        #expect(UIApplication.shared.connectedScenes.isEmpty)
        #expect(ForegroundLocator.firstActiveScene() == nil)
        #expect(ForegroundLocator.foreground() == nil)
        #expect(IosDialogManager.shared.getRootViewController() == nil)
    }
}
