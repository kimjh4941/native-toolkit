//
//  UnityMacShareManagerBridge.h
//  UnityMacPlugin
//
//  C ABI bridge exposing Swift share APIs (UnityMacShareManager) to Unity (C# P/Invoke).
//
//  Design Notes:
//  - All strings are UTF-8 encoded `const char*` and may be NULL where documented.
//  - Callbacks are invoked on the main thread.
//  - `isSuccess` reports whether the share could be presented/performed and the user could
//    interact with it. User cancellation is NOT an error: isSuccess=true, completed=false.
//  - `errorMessage` is NULL unless isSuccess=false.
//  - `shareContent` presents the sharing service picker and MUST be invoked from a
//    user-initiated action (e.g. a button click), since `NSSharingServicePicker.show(...)`
//    requires a `mouseDown` event context.
//  - Do not retain raw pointer values past the callback; copy to managed strings immediately.
//

#import <Foundation/Foundation.h>
#import <MacLibrary/MacLibrary-Swift.h>
#import <UnityMacPlugin/UnityMacPlugin-Swift.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Callback for a share interaction.
/// - Parameters:
///   - isSuccess: Whether the share could be presented/performed (false = error).
///   - completed: Whether the user completed a service (false = cancelled).
///   - serviceName: Display name of the chosen service, or NULL if cancelled/unknown.
///   - errorMessage: Human-readable diagnostic (NULL unless isSuccess=false).
typedef void (*ShareCallback)(bool isSuccess,
                              bool completed,
                              const char* serviceName,
                              const char* errorMessage);

/// Presents the sharing service picker.
///
/// - Important: Must be invoked from a user-initiated action (e.g. a button click) on the
///   Unity side. Calling this outside of a `mouseDown` event context may result in unstable
///   presentation.
/// - Parameters:
///   - contentJson: UTF-8 JSON describing items/recipients/subject/excludedServiceTitles (required).
///   - callback: Result callback; may be NULL if caller does not need the result.
void shareContent(const char* contentJson, ShareCallback callback);

/// Performs a single named sharing service directly (no picker UI).
/// - Parameters:
///   - serviceName: UTF-8 raw `NSSharingService.Name` value (required, e.g. "com.apple.share.Mail.compose").
///   - contentJson: UTF-8 JSON describing items/recipients/subject (required).
///   - callback: Result callback; may be NULL if caller does not need the result.
void shareViaService(const char* serviceName, const char* contentJson, ShareCallback callback);

#ifdef __cplusplus
}
#endif
