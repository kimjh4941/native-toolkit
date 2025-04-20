//
//  UnityIosDialogManagerBridge.m
//  UnityIosPlugin
//
//  Created by Kim Jong Hyun on 2025/04/12.
//
#import "UnityIosDialogManagerBridge.h"

static NSString *const TAG = @"UnityIosDialogManagerBridge";

void showDialog(const char* title,
                const char* message,
                DialogManagerCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"showDialog called with title: %s, message: %s, callback: %p", title, message, callback]];
    NSString* nsTitle = [NSString stringWithUTF8String:title];
    NSString* nsMessage = [NSString stringWithUTF8String:message];
    [[UnityIosDialogManager shared] showDialogWithTitle:nsTitle
                                                message:nsMessage
                                                handler:^(NSString* result) {
        [Log d:TAG :[NSString stringWithFormat:@"Dialog result: %@", result]];
        callback(result.UTF8String);
    }];
}
