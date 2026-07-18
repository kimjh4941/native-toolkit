//
//  MacShareManager.swift
//  MacLibrary
//

import Foundation

/// # MacShareManager
///
/// Central entry point for presenting the macOS sharing service picker and performing
/// individual sharing services.
///
/// ## Overview
/// * Provides a singleton (`shared`) for global access.
/// * Wraps `SharePickerUseCase` / `ShareServiceUseCase` / `ShareServiceQueryUseCase` and converts
///   errors to a Unity-friendly callback tuple.
/// * User cancellation is not an error: `completed == false` with `isSuccess == true`.
///
/// ## mouseDown Requirement
/// `share(content:completion:)` (picker mode) must be invoked from a user-initiated action
/// (e.g. a button click), since `NSSharingServicePicker.show(...)` requires a `mouseDown`
/// event context. See `SharePickerPresenter` for details.
///
/// - Important: `share(content:completion:)` and `share(content:serviceName:completion:)` hop
///   through `Task { @MainActor in ... }` before reaching AppKit. Swift does not guarantee this
///   hop executes synchronously within the *same* call stack as the caller, even when the
///   caller is already on the main thread inside a real mouseDown-triggered action handler.
///   This means the picker-mode call path (`share(content:completion:)`) may not reliably
///   satisfy `NSSharingServicePicker.show(...)`'s mouseDown-context requirement, and this has
///   **not been empirically verified against a real user click** (no interactive UI automation
///   was available during implementation/review). Prefer `shareViaService(content:serviceName:)`
///   / `share(content:serviceName:completion:)` (direct service execution, e.g. `.composeEmail`)
///   as the verified-safe path when reliability matters; treat picker mode as best-effort until
///   manually confirmed on real hardware with a genuine click. See design doc §12 "設計上の分岐".
///
/// - Note: The native `async throws` overload `share(content:) async throws` does not add its
///   own `Task {}` hop; if a caller already awaits it directly from a synchronous mouseDown
///   handler via structured concurrency (not a detached `Task {}`), it is closer to (but still
///   not guaranteed identical to) the original call stack than the callback overload above.
///
/// ## Example
/// ```swift
/// MacShareManager.shared.share(
///     content: ShareContent(items: [.text("Hello")])
/// ) { isSuccess, completed, serviceName, errorMessage in
///     print(isSuccess, completed, serviceName ?? "", errorMessage ?? "")
/// }
/// ```
public final class MacShareManager: NSObject {

    private let TAG = "MacShareManager"

    /// Shared singleton instance.
    public static let shared = MacShareManager()

    private let repository: ShareRepository
    private let pickerUseCase: SharePickerUseCase
    private let serviceUseCase: ShareServiceUseCase
    private let queryUseCase: ShareServiceQueryUseCase

    private override init() {
        Log.d(TAG, "[init]")
        let repo = ShareRepositoryImpl()
        self.repository = repo
        self.pickerUseCase = SharePickerUseCase(repository: repo)
        self.serviceUseCase = ShareServiceUseCase(repository: repo)
        self.queryUseCase = ShareServiceQueryUseCase(repository: repo)
        super.init()
    }

    /// Internal initializer for tests to inject a repository.
    init(repository: ShareRepository) {
        Log.d(TAG, "[init:test]")
        self.repository = repository
        self.pickerUseCase = SharePickerUseCase(repository: repository)
        self.serviceUseCase = ShareServiceUseCase(repository: repository)
        self.queryUseCase = ShareServiceQueryUseCase(repository: repository)
        super.init()
    }

    /// Presents the sharing service picker for the given content.
    ///
    /// - Note: `completion` is always invoked on the main thread (main actor), regardless of
    ///   the calling thread, matching the Unity Bridge's documented threading contract.
    /// - Note: Intended for the Unity Bridge (C callback interop). Swift callers should prefer
    ///   ``share(content:)-(ShareContent)`` (`async throws`) for typed error handling.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - completion: `(isSuccess, completed, serviceName, errorMessage)`.
    ///     * `isSuccess`: presentation succeeded (user could interact).
    ///     * `completed`: user finished a service (`false` means cancelled).
    ///     * `serviceName`: the chosen service's display name, or `nil`.
    ///     * `errorMessage`: set only when `isSuccess == false`.
    public func share(
        content: ShareContent,
        completion: ((Bool, Bool, String?, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[share] items: \(content.items.count)")
        Task { @MainActor in
            do {
                let result = try await pickerUseCase.execute(content: content)
                completion?(true, result.completed, result.serviceName, nil)
            } catch {
                Log.e(TAG, "[share] error: \(error)")
                completion?(false, false, nil, MacShareManager.message(for: error))
            }
        }
    }

    /// Performs a named sharing service directly (Bridge-facing callback form).
    ///
    /// - Note: `completion` is always invoked on the main thread (main actor).
    /// - Parameters:
    ///   - content: The content to share.
    ///   - serviceName: Raw `NSSharingService.Name` value (e.g. "com.apple.share.Mail.compose").
    ///   - completion: `(isSuccess, completed, serviceName, errorMessage)`.
    public func share(
        content: ShareContent,
        serviceName: String,
        completion: ((Bool, Bool, String?, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[share:service] serviceName: \(serviceName), items: \(content.items.count)")
        Task { @MainActor in
            do {
                let result = try await serviceUseCase.execute(content: content, serviceName: serviceName)
                completion?(true, result.completed, result.serviceName, nil)
            } catch {
                Log.e(TAG, "[share:service] error: \(error)")
                completion?(false, false, nil, MacShareManager.message(for: error))
            }
        }
    }

    /// Presents the sharing service picker for the given content.
    ///
    /// - Note: Preferred entry point for native Swift callers (e.g. sample app). Surfaces typed
    ///   `ShareError` on failure instead of a string message. The Unity Bridge uses the
    ///   callback-based ``share(content:completion:)`` overload instead.
    /// - Parameter content: The content to share.
    /// - Returns: The interaction result. `result.completed == false` means the user cancelled
    ///   (not an error).
    /// - Throws: `ShareError` on failure before or during presentation.
    @discardableResult
    public func share(content: ShareContent) async throws -> ShareResult {
        Log.d(TAG, "[share:async] items: \(content.items.count)")
        return try await pickerUseCase.execute(content: content)
    }

    /// Performs a named sharing service directly.
    ///
    /// - Note: Preferred entry point for native Swift callers.
    /// - Parameters:
    ///   - content: The content to share.
    ///   - serviceName: Raw `NSSharingService.Name` value.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` on failure before or during the service call.
    @discardableResult
    public func shareViaService(content: ShareContent, serviceName: String) async throws -> ShareResult {
        Log.d(TAG, "[shareViaService:async] serviceName: \(serviceName)")
        return try await serviceUseCase.execute(content: content, serviceName: serviceName)
    }

    /// Reports whether a named service can share the content (native async form).
    /// - Parameters:
    ///   - content: The content to share.
    ///   - serviceName: Raw `NSSharingService.Name` value.
    /// - Returns: `true` if the service exists and can share the content.
    /// - Throws: `ShareError` on conversion failure.
    public func canPerform(content: ShareContent, serviceName: String) async throws -> Bool {
        Log.d(TAG, "[canPerform] serviceName: \(serviceName)")
        return try await queryUseCase.canPerform(content: content, serviceName: serviceName)
    }

    private static func message(for error: Error) -> String {
        (error as? ShareError)?.errorMessage ?? error.localizedDescription
    }
}
