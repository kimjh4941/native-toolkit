//
//  UnityIosShareManagerBridge.m
//  UnityIosPlugin
//

#import "UnityIosShareManagerBridge.h"

static NSString *const TAG = @"UnityIosShareManagerBridge";

/// Presents the system share sheet from a JSON content string.
///
/// - Parameters:
///   - contentJson: UTF-8 C string for the JSON content (required).
///   - callback: Invoked with `(isSuccess, completed, activityTypeOrNULL, errorMessageOrNULL)`.
///
/// - Discussion:
///   `isSuccess=false` indicates the sheet could not be presented or JSON parsing failed.
///   User cancellation is reported as `isSuccess=true, completed=false`.
void shareContent(const char* contentJson, ShareCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[shareContent] contentJson: %s, callback: %p", contentJson, callback]];
    NSString* nsContentJson = [NSString stringWithUTF8String:contentJson];

    [[UnityIosShareManager shared] shareWithContentJson:nsContentJson
                                                 handler:^(BOOL isSuccess, BOOL completed, NSString* activityType, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"[shareContent] isSuccess: %d, completed: %d, activityType: %@, errorMessage: %@", isSuccess, completed, activityType, errorMessage]];
        if (callback) {
            const char* activityTypeStr = activityType ? activityType.UTF8String : NULL;
            const char* errorStr = errorMessage ? errorMessage.UTF8String : NULL;
            callback(isSuccess, completed, activityTypeStr, errorStr);
        }
    }];
}
