//
//  IosShareManager.swift
//  IosLibrary
//

import Foundation

/// # IosShareManager
///
/// Central entry point for presenting the system share sheet.
///
/// ## Overview
/// * Provides a singleton (`shared`) for global access.
/// * Wraps `ShareContentUseCase` and converts errors to a Unity-friendly callback tuple.
/// * User cancellation is not an error: `completed == false` with `isSuccess == true`.
///
/// ## Example
/// ```swift
/// IosShareManager.shared.share(
///     content: ShareContent(items: [.text("Hello")])
/// ) { isSuccess, completed, activityType, errorMessage in
///     print(isSuccess, completed, activityType ?? "", errorMessage ?? "")
/// }
/// ```
public final class IosShareManager: NSObject {

    private let TAG = "IosShareManager"

    /// Shared singleton instance.
    public static let shared = IosShareManager()

    private let repository: ShareRepository
    private let shareUseCase: ShareContentUseCase

    private override init() {
        Log.d(TAG, "[init]")
        let repo = ShareRepositoryImpl()
        self.repository = repo
        self.shareUseCase = ShareContentUseCase(repository: repo)
        super.init()
    }

    /// Internal initializer for tests to inject a repository.
    init(repository: ShareRepository) {
        Log.d(TAG, "[init:test]")
        self.repository = repository
        self.shareUseCase = ShareContentUseCase(repository: repository)
        super.init()
    }

    /// Presents the share sheet for the given content.
    ///
    /// - Note: `completion` is always invoked on the main thread (main actor), regardless of
    ///   the calling thread, matching the Unity Bridge's documented threading contract.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - completion: `(isSuccess, completed, activityType, errorMessage)`.
    ///     * `isSuccess`: presentation succeeded (user could interact).
    ///     * `completed`: user finished an activity (`false` means cancelled).
    ///     * `activityType`: the selected activity's raw identifier, or `nil`.
    ///     * `errorMessage`: set only when `isSuccess == false`.
    public func share(
        content: ShareContent,
        completion: ((Bool, Bool, String?, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[share] items: \(content.items.count)")
        Task { @MainActor in
            do {
                let result = try await shareUseCase.execute(content: content)
                completion?(true, result.completed, result.activityType, nil)
            } catch {
                Log.e(TAG, "[share] error: \(error)")
                completion?(false, false, nil, error.localizedDescription)
            }
        }
    }
}
