//
//  UnityIosShareManagerBridge.h
//
//  C ABI bridge exposing Swift share APIs (UnityIosShareManager) to Unity (C# P/Invoke).
//
//  Design Notes:
//  - All strings are UTF-8 encoded `const char*` and may be NULL where documented.
//  - Callbacks are invoked on the main thread.
//  - `isSuccess` reports whether the share sheet could be presented and the user could
//    interact with it. User cancellation is NOT an error: isSuccess=true, completed=false.
//  - `errorMessage` is NULL unless isSuccess=false.
//  - Do not retain raw pointer values past the callback; copy to managed strings immediately.
//

#import <Foundation/Foundation.h>
#import <IosLibrary/IosLibrary-Swift.h>
#import <UnityIosPlugin/UnityIosPlugin-Swift.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Callback for a share sheet presentation.
/// - Parameters:
///   - isSuccess: Whether the share sheet could be presented (false = error).
///   - completed: Whether the user completed an activity (false = cancelled).
///   - activityType: Raw identifier of the selected activity, or NULL if cancelled/unknown.
///   - errorMessage: Human-readable diagnostic (NULL unless isSuccess=false).
typedef void (*ShareCallback)(bool isSuccess,
                              bool completed,
                              const char* activityType,
                              const char* errorMessage);

/// Presents the system share sheet.
/// - Parameters:
///   - contentJson: UTF-8 JSON describing items/subject/previewTitle/excludedActivityTypes (required).
///   - callback: Result callback; may be NULL if caller does not need the result.
void shareContent(const char* contentJson, ShareCallback callback);

#ifdef __cplusplus
}
#endif
