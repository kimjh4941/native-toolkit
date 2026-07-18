//
//  UnityMacShareManager.swift
//  UnityMacPlugin
//

import Foundation
import MacLibrary

/// # UnityMacShareManager
///
/// Swift façade exposing the sharing service API to Unity via the Objective-C bridge
/// (`UnityMacShareManagerBridge`). Internally delegates to `MacShareManager` and
/// normalizes JSON parsing for C# interop.
///
/// ## Overview
/// * Provides a singleton: `shared`.
/// * JSON parsing is handled by `UnityMacShareJsonParser`.
/// * Callback semantics: `(isSuccess, completed, serviceName, errorMessage)`.
///
/// ## Threading
/// Safe to call from any thread; work is dispatched internally. Handlers are invoked on the
/// main thread.
///
/// ## mouseDown Requirement
/// `share(contentJson:handler:)` (picker mode) must be invoked from a user-initiated action
/// (e.g. a button click) on the Unity side, since the underlying picker requires a `mouseDown`
/// event context.
@objcMembers
public class UnityMacShareManager: NSObject {

    private let TAG = "UnityMacShareManager"

    /// Shared singleton instance used by the Objective-C bridge.
    public static let shared = UnityMacShareManager()

    private let parser = UnityMacShareJsonParser()

    private override init() {
        Log.d(TAG, "[init]")
        super.init()
    }

    /// Presents the sharing service picker from a JSON content string.
    ///
    /// - Note: `handler` is always invoked on the main thread, on every code path
    ///   (including invalid JSON), matching the Bridge header's threading contract.
    /// - Parameters:
    ///   - contentJson: JSON string for `ShareContent` (see `UnityMacShareJsonParser`).
    ///   - handler: `(isSuccess, completed, serviceName, errorMessage)`.
    public func share(
        contentJson: String,
        handler: ((Bool, Bool, String?, String?) -> Void)?
    ) {
        Log.d(TAG, "[share] contentJson: \(contentJson)")
        guard let content = parser.parseContent(from: contentJson) else {
            Log.e(TAG, "[share] failed to parse content JSON")
            DispatchQueue.main.async {
                handler?(false, false, nil, "Invalid share content JSON.")
            }
            return
        }
        MacShareManager.shared.share(content: content, completion: handler)
    }

    /// Performs a single named sharing service directly from a JSON content string.
    ///
    /// - Note: `handler` is always invoked on the main thread, on every code path.
    /// - Parameters:
    ///   - serviceName: Raw `NSSharingService.Name` value (e.g. "com.apple.share.Mail.compose").
    ///   - contentJson: JSON string for `ShareContent`.
    ///   - handler: `(isSuccess, completed, serviceName, errorMessage)`.
    public func shareViaService(
        serviceName: String,
        contentJson: String,
        handler: ((Bool, Bool, String?, String?) -> Void)?
    ) {
        Log.d(TAG, "[shareViaService] serviceName: \(serviceName), contentJson: \(contentJson)")
        guard let content = parser.parseContent(from: contentJson) else {
            Log.e(TAG, "[shareViaService] failed to parse content JSON")
            DispatchQueue.main.async {
                handler?(false, false, nil, "Invalid share content JSON.")
            }
            return
        }
        MacShareManager.shared.share(content: content, serviceName: serviceName, completion: handler)
    }
}
