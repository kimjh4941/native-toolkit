//
//  IosShareManager.swift
//  IosLibrary
//

import Foundation
import os

private let logger = Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibrary", category: "IosShareManager")

/// # IosShareManager
///
/// Central entry point for presenting the system share sheet.
///
/// ## Overview
/// * Provides a singleton (`shared`) for global access.
/// * Wraps `ShareContentUseCase` and converts errors to a Unity-friendly callback tuple.
/// * User cancellation is not an error: `completed == false` with `isSuccess == true`.
///
/// ## Threading
/// The manager is `Sendable` and may be called from any thread. The callback form delivers
/// `completion` on the main thread exactly once, on every path (including validation failures).
///
/// ## Example
/// ```swift
/// IosShareManager.shared.share(
///     content: ShareContent(items: [.text("Hello")])
/// ) { isSuccess, completed, activityType, errorMessage in
///     print(isSuccess, completed, activityType ?? "", errorMessage ?? "")
/// }
/// ```
public final class IosShareManager: NSObject, Sendable {

    /// Shared singleton instance.
    public static let shared = IosShareManager()

    private let repository: ShareRepository
    private let shareUseCase: ShareContentUseCase

    private override init() {
        logger.log(level: .libraryDebug, "[init]")
        let repo = ShareRepositoryImpl()
        self.repository = repo
        self.shareUseCase = ShareContentUseCase(repository: repo)
        super.init()
    }

    /// Internal initializer for tests to inject a repository.
    init(repository: ShareRepository) {
        logger.log(level: .libraryDebug, "[init:test]")
        self.repository = repository
        self.shareUseCase = ShareContentUseCase(repository: repository)
        super.init()
    }

    /// Presents the share sheet for the given content.
    ///
    /// - Note: `completion` is always invoked on the main thread (main actor), exactly once,
    ///   regardless of the calling thread, matching the Unity Bridge's documented threading
    ///   contract. It is `@Sendable` because it is carried from the calling thread to the main
    ///   actor, and `@MainActor` to state in the type where it runs (the same as the completions
    ///   of `IosNotificationManager`).
    /// - Note: Intended for the Unity Bridge (C callback interop). Swift callers should prefer
    ///   ``share(content:)-(ShareContent)`` (`async throws`) for typed error handling.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - completion: `(isSuccess, completed, activityType, errorMessage)`.
    ///     * `isSuccess`: presentation succeeded (user could interact).
    ///     * `completed`: user finished an activity (`false` means cancelled).
    ///     * `activityType`: the selected activity's raw identifier, or `nil`.
    ///     * `errorMessage`: set only when `isSuccess == false`.
    public func share(
        content: ShareContent,
        completion: (@MainActor @Sendable (Bool, Bool, String?, String?) -> Void)? = nil
    ) {
        logger.log(level: .libraryDebug, "[share] items: \(content.items.count, privacy: .public)")
        Task { @MainActor in
            do {
                let result = try await shareUseCase.execute(content: content)
                completion?(true, result.completed, result.activityType, nil)
            } catch {
                logger.error("[share] error: \(LogRedaction.describe(error), privacy: .public)")
                completion?(false, false, nil, error.localizedDescription)
            }
        }
    }

    /// Presents the share sheet for the given content.
    ///
    /// - Note: Preferred entry point for native Swift callers (e.g. SwiftUI views). Surfaces
    ///   typed `ShareError` on failure instead of a string message. The Unity Bridge uses the
    ///   callback-based ``share(content:completion:)`` overload instead, since C interop has no
    ///   equivalent to `throws`/`async`.
    /// - Parameter content: The content to share.
    /// - Returns: The interaction result. `result.completed == false` means the user cancelled
    ///   (not an error).
    /// - Throws: `ShareError` on failure before or during presentation.
    @discardableResult
    public func share(content: ShareContent) async throws -> ShareResult {
        logger.log(level: .libraryDebug, "[share] items: \(content.items.count, privacy: .public)")
        return try await shareUseCase.execute(content: content)
    }
}
