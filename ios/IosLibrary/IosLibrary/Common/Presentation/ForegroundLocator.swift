//
//  ForegroundLocator.swift
//  IosLibrary
//

import os
import UIKit

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "ForegroundLocator")

/// Finds the view controller to present from: the current search (`.firstActiveScene`) and the
/// foreground of the C ABI design part 1, 5.13 (`.foreground`).
///
/// The rules are written once over plain values (``Scene``) so that the unit tests can check
/// them with fake scenes and view controllers; ``firstActiveScene()`` and ``foreground()`` feed
/// them from `UIApplication.shared.connectedScenes`. Every presenting operation of the library
/// uses this type, and `IosDialogManager.getRootViewController()` returns
/// ``firstActiveScene()``.
@MainActor
enum ForegroundLocator {
    /// What the rules need to know about one connected scene.
    struct Scene<Node> {
        /// `UIScene.activationState`.
        var activationState: UIScene.ActivationState
        /// Whether the scene is a `UIWindowScene`.
        var isWindowScene: Bool
        /// Whether the scene has a window whose `isKeyWindow` is `true`.
        var hasKeyWindow: Bool
        /// The `rootViewController` of that key window.
        var keyWindowRoot: Node?
    }

    // MARK: - Rules

    /// The current search: the first `foregroundActive` scene, which must be a window scene with
    /// a key window, then every presented view controller from its root (also one being
    /// dismissed). One search, no waiting.
    static func firstActiveSceneTop<Node>(in scenes: [Scene<Node>], presented: (Node) -> Node?) -> Node? {
        logger.log(level: .libraryDebug, "[firstActiveSceneTop] scenes: \(scenes.count, privacy: .public)")
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }),
              scene.isWindowScene, scene.hasKeyWindow else {
            return nil
        }
        var top = scene.keyWindowRoot
        while let current = top, let next = presented(current) {
            top = next
        }
        return top
    }

    /// The foreground (part 1, 5.13): a `foregroundActive` or `foregroundInactive` window scene
    /// with the key window, then the presented view controllers from its root that are not being
    /// dismissed. An active scene is preferred when, against the assumption that the app has one
    /// key window (G-6), more than one scene qualifies.
    static func foregroundTop<Node>(
        in scenes: [Scene<Node>],
        presented: (Node) -> Node?,
        isBeingDismissed: (Node) -> Bool
    ) -> Node? {
        logger.log(level: .libraryDebug, "[foregroundTop] scenes: \(scenes.count, privacy: .public)")
        let candidates = scenes.filter { scene in
            (scene.activationState == .foregroundActive || scene.activationState == .foregroundInactive)
                && scene.isWindowScene && scene.hasKeyWindow && scene.keyWindowRoot != nil
        }
        if candidates.count > 1 {
            logger.info("[foregroundTop] more than one foreground scene has a key window, count: \(candidates.count, privacy: .public)")
        }
        guard let scene = candidates.first(where: { $0.activationState == .foregroundActive }) ?? candidates.first,
              var top = scene.keyWindowRoot else {
            return nil
        }
        while let next = presented(top), !isBeingDismissed(next) {
            top = next
        }
        return top
    }

    // MARK: - UIKit

    /// The current search over the app's connected scenes.
    static func firstActiveScene() -> UIViewController? {
        logger.log(level: .libraryDebug, "[firstActiveScene]")
        let top = firstActiveSceneTop(in: connectedScenes(), presented: { $0.presentedViewController })
        if top == nil {
            logger.error("[firstActiveScene] failed to get window scene or key window")
        }
        return top
    }

    /// The foreground over the app's connected scenes.
    static func foreground() -> UIViewController? {
        logger.log(level: .libraryDebug, "[foreground]")
        let top = foregroundTop(
            in: connectedScenes(),
            presented: { $0.presentedViewController },
            isBeingDismissed: { $0.isBeingDismissed }
        )
        if top == nil {
            logger.info("[foreground] no view controller in the foreground")
        }
        return top
    }

    /// The scenes in `connectedScenes` order (a `Set`, so the order is not defined; the first
    /// `foregroundActive` one is what the current search has always used).
    private static func connectedScenes() -> [Scene<UIViewController>] {
        UIApplication.shared.connectedScenes.map { scene in
            let windowScene = scene as? UIWindowScene
            let keyWindow = windowScene?.windows.first(where: { $0.isKeyWindow })
            return Scene(
                activationState: scene.activationState,
                isWindowScene: windowScene != nil,
                hasKeyWindow: keyWindow != nil,
                keyWindowRoot: keyWindow?.rootViewController
            )
        }
    }
}
