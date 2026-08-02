//
//  UnityIosClipboardManagerBridge.h
//
//  C ABI bridge exposing Swift clipboard APIs (UnityIosClipboardManager) to Unity (C# P/Invoke).
//
//  Design Notes:
//  - All strings are UTF-8 encoded `const char*` and may be NULL where documented.
//  - Operation callbacks report (isSuccess, errorCode, errorMessage); errorCode/errorMessage are
//    NULL when isSuccess is true.
//  - JSON callbacks always report a JSON envelope: {"ok":true,"data":...} or
//    {"ok":false,"error":{"code":...,"message":...,"details":{...}?}}.
//  - A NULL requestJson (or an unparsable one) yields CLIPBOARD_INVALID_REQUEST.
//  - Callbacks are invoked on the main thread, exactly once per call.
//  - Callback argument C strings are valid only for the duration of the callback; copy them to
//    managed strings immediately. Do not retain raw pointer values past the callback.
//  - A NULL callback is accepted; the result is simply discarded (never crashes).
//

#import <Foundation/Foundation.h>
#import <IosLibrary/IosLibrary-Swift.h>
#import <UnityIosPlugin/UnityIosPlugin-Swift.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Callback for an operation with no return value.
typedef void (*ClipboardOperationCallback)(bool isSuccess,
                                           const char* errorCode,
                                           const char* errorMessage);

/// Callback delivering a JSON-encoded success/error envelope.
typedef void (*ClipboardJsonCallback)(const char* json);

/// Callback delivering a JSON-encoded clipboard change event (not wrapped in an envelope).
typedef void (*ClipboardChangeCallback)(const char* eventJson);

/// Writes content to the clipboard, replacing existing items.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?, content, options?}` (required).
///   - callback: Result callback; may be NULL.
void clipboardCopy(const char* requestJson, ClipboardOperationCallback callback);

/// Appends content to the clipboard. Cannot carry privacy options: passing an `options` key is
/// rejected with CLIPBOARD_INVALID_REQUEST.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?, content}` (required).
///   - callback: Result callback; may be NULL.
void clipboardAppend(const char* requestJson, ClipboardOperationCallback callback);

/// Reads all clipboard items synchronously (without their large payloads).
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?}` (required).
///   - callback: JSON callback; may be NULL.
void clipboardRead(const char* requestJson, ClipboardJsonCallback callback);

/// Reads the raw data for a given uniform type identifier.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?, utType}` (required).
///   - callback: JSON callback; may be NULL.
void clipboardReadData(const char* requestJson, ClipboardJsonCallback callback);

/// Reads clipboard metadata using only system APIs documented to avoid user
/// notifications/prompts.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?, matchingTypes?}` (required).
///   - callback: JSON callback; may be NULL.
void clipboardGetSnapshot(const char* requestJson, ClipboardJsonCallback callback);

/// Clears all clipboard items.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?}` (required).
///   - callback: Result callback; may be NULL.
void clipboardClear(const char* requestJson, ClipboardOperationCallback callback);

/// Creates (or resolves an existing named) pasteboard, or a new unique-named pasteboard.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{request: {kind: "named", name} | {kind: "unique"}}` (required).
///   - callback: JSON callback; may be NULL.
void clipboardCreatePasteboard(const char* requestJson, ClipboardJsonCallback callback);

/// Invalidates a named/unique pasteboard. Rejects `.general` with
/// CLIPBOARD_CANNOT_REMOVE_GENERAL.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope}` (required).
///   - callback: Result callback; may be NULL.
void clipboardRemovePasteboard(const char* requestJson, ClipboardOperationCallback callback);

/// Detects which patterns are present, without reading their matched values.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?, patterns}` (required).
///   - callback: JSON callback; may be NULL.
void clipboardDetectPatterns(const char* requestJson, ClipboardJsonCallback callback);

/// Detects patterns and reads their matched values.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?, patterns}` (required).
///   - callback: JSON callback; may be NULL.
void clipboardDetectValues(const char* requestJson, ClipboardJsonCallback callback);

/// Loads a single item from the pasteboard's item providers asynchronously.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?, request}` (required).
///   - callback: JSON callback; may be NULL.
void clipboardLoadItem(const char* requestJson, ClipboardJsonCallback callback);

/// Cancels every pending `clipboardLoadItem` request.
/// - Parameter callback: Result callback, invoked once cancellation has completed; may be NULL.
void clipboardCancelLoads(ClipboardOperationCallback callback);

/// Starts observing clipboard changes. A second call first stops the previous observation.
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?}` (required).
///   - changeCallback: Invoked once per change event; may be NULL.
///   - startCallback: Invoked once observation has started (or failed to start); may be NULL.
void clipboardStartObserving(const char* requestJson,
                             ClipboardChangeCallback changeCallback,
                             ClipboardOperationCallback startCallback);

/// Stops observing clipboard changes. No further change events are delivered once `callback`
/// fires.
/// - Parameter callback: Result callback; may be NULL.
void clipboardStopObserving(ClipboardOperationCallback callback);

/// Checks whether the clipboard changed since the last check (`changeCount` comparison).
/// - Parameters:
///   - requestJson: UTF-8 JSON `{scope?}` (required).
///   - callback: JSON callback delivering `{"changed": bool}`; may be NULL.
void clipboardCheckForegroundChange(const char* requestJson, ClipboardJsonCallback callback);

#ifdef __cplusplus
}
#endif
