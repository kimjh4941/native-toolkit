//
//  UnityIosShareManager.swift
//  UnityIosPlugin
//

import Foundation
import IosLibrary

/// # UnityIosShareManager
///
/// Swift façade exposing the share sheet API to Unity via the Objective-C bridge
/// (`UnityIosShareManagerBridge`). Internally delegates to `IosShareManager` and
/// normalizes JSON parsing for C# interop.
///
/// ## Overview
/// * Provides a singleton: `shared`.
/// * JSON parsing is handled by `UnityIosShareJsonParser`.
/// * Callback semantics: `(isSuccess, completed, activityType, errorMessage)`.
///
/// ## Threading
/// Safe to call from any thread; work is dispatched internally.
@objcMembers
public class UnityIosShareManager: NSObject {

    private let TAG = "UnityIosShareManager"

    /// Shared singleton instance used by the Objective-C bridge.
    public static let shared = UnityIosShareManager()

    private let parser = UnityIosShareJsonParser()

    private override init() {
        Log.d(TAG, "[init]")
        super.init()
    }

    /// Presents the share sheet from a JSON content string.
    /// - Parameters:
    ///   - contentJson: JSON string for `ShareContent` (see `UnityIosShareJsonParser`).
    ///   - handler: `(isSuccess, completed, activityType, errorMessage)`.
    public func share(
        contentJson: String,
        handler: ((Bool, Bool, String?, String?) -> Void)?
    ) {
        Log.d(TAG, "[share] contentJson: \(contentJson)")
        guard let content = parser.parseContent(from: contentJson) else {
            Log.e(TAG, "[share] failed to parse content JSON")
            handler?(false, false, nil, "Invalid share content JSON.")
            return
        }
        IosShareManager.shared.share(content: content, completion: handler)
    }
}
