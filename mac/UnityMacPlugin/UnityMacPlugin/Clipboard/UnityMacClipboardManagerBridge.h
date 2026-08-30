//
//  UnityMacClipboardManagerBridge.h
//  UnityMacPlugin
//
//  C ABI bridge exposing the Swift clipboard API (UnityMacClipboardManager) to Unity
//  (C# P/Invoke).
//
//  Design Notes:
//  - All strings are UTF-8 `const char*` and may be NULL where documented.
//  - May be called from any thread. Every callback is invoked on the main thread.
//  - Operation callbacks fire exactly once per call, including on early failures such as
//    malformed JSON. Event callbacks fire zero or more times while a subscription is live.
//  - A NULL operation callback is NOT an error. The work runs and nothing is reported back,
//    so a caller that does not need the result can simply pass NULL. Two exceptions, both
//    about a result the caller cannot do without:
//      * clipboardCreatePasteboard, clipboardProvideFilePromise and
//        clipboardReceiveFilePromises do nothing at all when their callback is NULL, because
//        the handle they return is the only way to release what they create.
//      * clipboardStartObserving and clipboardReceiveFilePromises report 1302 when their
//        EVENT callback is NULL, because the subscription would produce no observable result.
//  - `errorCode` is 0 on success. 1301 (bad JSON) and 1302 (missing argument) are bridge
//    level failures; 1501-1599 come from the clipboard itself.
//  - Do not retain raw pointer values past the callback; copy to managed strings immediately.
//  - Pasteboards created here live in the pasteboard server and outlive this process. Release
//    a unique pasteboard with clipboardRemovePasteboard, and never place confidential data on
//    a named one.
//  - Reading a pasteboard may cause the system to tell the person using the app. No call here
//    guarantees otherwise.
//

#import <Foundation/Foundation.h>
#import <MacLibrary/MacLibrary-Swift.h>
#import <UnityMacPlugin/UnityMacPlugin-Swift.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - Callback typedefs

/// Operation callback for a call that returns no value. Invoked exactly once.
/// - Parameters:
///   - isSuccess: NO on failure.
///   - errorCode: 0 on success.
///   - errorMessage: NULL unless isSuccess is NO.
typedef void (*ClipboardCallback)(BOOL isSuccess,
                                  NSInteger errorCode,
                                  const char* errorMessage);

/// Operation callback for a call that returns JSON. Invoked exactly once.
/// - Parameters:
///   - json: Non-NULL only when isSuccess is YES.
typedef void (*ClipboardJsonCallback)(BOOL isSuccess,
                                      const char* json,
                                      NSInteger errorCode,
                                      const char* errorMessage);

/// Event callback for clipboard observation. Invoked N times while subscribed; there is no
/// terminal event.
typedef void (*ClipboardChangeCallback)(const char* eventJson);

/// Event callback for receiving promised files.
/// - Parameters:
///   - isFinished: YES for the terminal event, which arrives exactly once.
typedef void (*ClipboardReceiptCallback)(BOOL isFinished, const char* eventJson);

#pragma mark - Copy and append

/// Replaces the pasteboard contents. Returns OwnershipJson.
/// - Parameter optionsJson: Optional. Defaults to localOnly.
void clipboardCopy(const char* contentJson,
                   const char* optionsJson,
                   const char* scopeJson,
                   ClipboardJsonCallback callback);

/// Adds items to a pasteboard this app still owns. Returns OwnershipJson.
///
/// - Important: Unlike iOS, appending needs ownership. If another app has taken the
///   pasteboard this reports 1511 rather than silently doing nothing.
void clipboardAppend(const char* contentJson,
                     const char* ownershipJson,
                     ClipboardJsonCallback callback);

#pragma mark - Read and query

/// Reads every item and representation. Returns ReadResultJson.
///
/// - Important: The result can contain representations that were never written. The
///   pasteboard derives convertible types, so text written as RTF also reads back as plain
///   text. Do not assume a read mirrors a write.
void clipboardRead(const char* scopeJson, ClipboardJsonCallback callback);

/// Reads the bytes for one uniform type identifier. Returns ReadDataJson.
///
/// A type that is not present is success with a null payload, not an error.
void clipboardReadData(const char* utType,
                       const char* scopeJson,
                       ClipboardJsonCallback callback);

/// Describes the pasteboard's types without reading any payload. Returns SnapshotJson.
/// - Parameter matchingTypesJson: NULL means no filter. An empty array reports 1512.
void clipboardSnapshot(const char* matchingTypesJson,
                       const char* scopeJson,
                       ClipboardJsonCallback callback);

#pragma mark - Clear and pasteboard lifetime

/// Empties the pasteboard. Returns ChangeCountJson.
void clipboardClear(const char* scopeJson, ClipboardJsonCallback callback);

/// Creates or fetches a pasteboard. Returns ScopeJson.
///
/// - Important: `callback` is required. A unique pasteboard's name is chosen by the system,
///   so a caller that cannot receive the scope can never release it (R4-M6). Passing NULL
///   creates nothing.
void clipboardCreatePasteboard(const char* requestJson, ClipboardJsonCallback callback);

/// Releases a pasteboard's server side resources.
///
/// The general pasteboard and the other standard names report 1508 and are never released.
void clipboardRemovePasteboard(const char* scopeJson, ClipboardCallback callback);

#pragma mark - Detection

/// Reports which of the requested patterns the pasteboard matches. Returns PatternsJson.
/// Reports 1513 below macOS 15.4.
void clipboardDetectPatterns(const char* patternsJson,
                             const char* scopeJson,
                             ClipboardJsonCallback callback);

/// Reads the matched values. Returns DetectedValuesJson.
///
/// - Important: This reads the contents. The system tells the person using the app on a match
///   and can deny access, which reports 1514. Call it from a user action.
void clipboardDetectValues(const char* patternsJson,
                           const char* scopeJson,
                           ClipboardJsonCallback callback);

/// Reads limited metadata. Returns DetectedMetadataJson.
///
/// - Note: Reports 1515 for a pasteboard the system cannot describe, which includes plain
///   text. Absence of metadata is not distinguishable from a failure.
void clipboardDetectMetadata(const char* scopeJson, ClipboardJsonCallback callback);

/// Current pasteboard access behaviour. Returns AccessBehaviorJson.
/// Reports "unavailable" below macOS 15.4 rather than failing.
void clipboardAccessBehavior(const char* scopeJson, ClipboardJsonCallback callback);

#pragma mark - Observation

/// Starts reporting pasteboard changes.
///
/// - Parameters:
///   - intervalSeconds: Must be greater than 0 and at most 60.
///   - callback: Subscription acknowledgement, exactly once.
///   - onChange: Required. Invoked N times while subscribed. Passing NULL reports 1302 and
///     starts nothing, because the subscription would produce no observable result (R5-M8).
/// - Important: Polling is suspended while the app is inactive and catches up when it becomes
///   active again, so a change made by another app is reported on return to the foreground.
/// - Note: Calling this again restarts observation with the new configuration.
void clipboardStartObserving(const char* scopeJson,
                             double intervalSeconds,
                             ClipboardCallback callback,
                             ClipboardChangeCallback onChange);

/// Stops reporting pasteboard changes. Idempotent.
void clipboardStopObserving(ClipboardCallback callback);

/// Whether the pasteboard changed since this app last looked. Returns BoolJson.
/// The first call for a scope reports YES.
void clipboardCheckForegroundChange(const char* scopeJson, ClipboardJsonCallback callback);

#pragma mark - File promises

/// Promises a file to other apps without producing its bytes yet. Returns HandleJson.
///
/// - Parameters:
///   - requestJson: fileTypeIdentifier, fileName and sourcePath. The file is copied into app
///     owned staging at registration, so the promise still succeeds if the original is later
///     moved. `sourcePath` must be a path this app can read; a sandboxed app has no access to
///     arbitrary user paths.
///   - scopeJson: Required. Decides which pasteboard the promise is advertised on (R5-H5).
///   - callback: Required. Without the handle the promise and its staging directory can never
///     be released (R3-M4). Passing NULL registers nothing.
void clipboardProvideFilePromise(const char* requestJson,
                                 const char* scopeJson,
                                 ClipboardJsonCallback callback);

/// Releases a file promise. Fully idempotent: an unknown or already released handle still
/// reports success.
void clipboardReleaseFilePromise(const char* handleJson, ClipboardCallback callback);

/// Starts receiving files another app has promised. Returns HandleJson.
///
/// - Parameters:
///   - policyJson: Optional. Defaults to a 2 second quiet interval and a 60 second overall
///     timeout. The quiet interval must be shorter than the overall timeout.
///   - callback: Required, exactly once. Without the handle the session can never be
///     cancelled (R3-M4).
///   - onEvent: Required. Intermediate events N times, then the terminal event once with
///     isFinished YES. Passing NULL reports 1302 and starts nothing (R5-M8).
/// - Important: The terminal event is a heuristic. The system does not report how many files
///   are coming, so the session ends after the quiet interval without a new arrival, or at
///   the overall timeout at the latest. A timeout is a normal ending: the files that did
///   arrive are still reported.
void clipboardReceiveFilePromises(const char* destinationPath,
                                  const char* scopeJson,
                                  const char* policyJson,
                                  ClipboardJsonCallback callback,
                                  ClipboardReceiptCallback onEvent);

/// Ends a receive session early. Fully idempotent: an unknown or already finished handle
/// still reports success. A session still subscribed receives a terminal event with
/// terminatedBy "cancelled" and keeps the files it already received.
void clipboardCancelReceiveFilePromises(const char* handleJson, ClipboardCallback callback);

#ifdef __cplusplus
}
#endif
