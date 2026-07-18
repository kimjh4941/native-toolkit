//
//  UnityMacShareManagerBridge.m
//  UnityMacPlugin
//
#import "UnityMacShareManagerBridge.h"

static NSString *const TAG = @"UnityMacShareManagerBridge";

/// Presents the sharing service picker via Unity bridge.
///
/// - Parameters:
///   - contentJson: UTF-8 JSON describing items/recipients/subject/excludedServiceTitles.
///   - callback: Receives (isSuccess, completed, serviceName, errorMessage)
///     * `isSuccess`: NO on error (e.g. invalid JSON, no anchor view).
///     * `completed`: NO if the user cancelled.
///     * `serviceName`: chosen service display name, or NULL.
///     * `errorMessage`: UTF-8 C string (owned by callee) or NULL.
/// - Important: Must be called from a user-initiated action (mouseDown event context).
/// - Thread Safety: May be called from any thread; callback is delivered on the main thread.
void shareContent(const char* contentJson, ShareCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"shareContent called with contentJson: %s, callback: %p",
                 contentJson ?: "(null)", callback]];

    NSString* nsContentJson = [NSString stringWithUTF8String:contentJson];

    [[UnityMacShareManager shared] shareWithContentJson:nsContentJson
                                                 handler:^(BOOL isSuccess, BOOL completed, NSString* serviceName, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"shareContent isSuccess: %d, completed: %d, serviceName: %@, errorMessage: %@", (int)isSuccess, (int)completed, serviceName, errorMessage]];
        if (callback) {
            callback(isSuccess, completed, serviceName.UTF8String, errorMessage.UTF8String);
        }
    }];
}

/// Performs a single named sharing service directly via Unity bridge.
///
/// - Parameters:
///   - serviceName: UTF-8 raw `NSSharingService.Name` value.
///   - contentJson: UTF-8 JSON describing items/recipients/subject.
///   - callback: Receives (isSuccess, completed, serviceName, errorMessage). See `shareContent`.
/// - Thread Safety: May be called from any thread; callback is delivered on the main thread.
void shareViaService(const char* serviceName, const char* contentJson, ShareCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"shareViaService called with serviceName: %s, contentJson: %s, callback: %p",
                 serviceName ?: "(null)", contentJson ?: "(null)", callback]];

    NSString* nsServiceName = [NSString stringWithUTF8String:serviceName];
    NSString* nsContentJson = [NSString stringWithUTF8String:contentJson];

    [[UnityMacShareManager shared] shareViaServiceWithServiceName:nsServiceName
                                                        contentJson:nsContentJson
                                                            handler:^(BOOL isSuccess, BOOL completed, NSString* resultServiceName, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"shareViaService isSuccess: %d, completed: %d, serviceName: %@, errorMessage: %@", (int)isSuccess, (int)completed, resultServiceName, errorMessage]];
        if (callback) {
            callback(isSuccess, completed, resultServiceName.UTF8String, errorMessage.UTF8String);
        }
    }];
}
