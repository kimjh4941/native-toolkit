//
//  UnityIosClipboardManagerBridge.m
//  UnityIosPlugin
//

#import "UnityIosClipboardManagerBridge.h"

static NSString *const TAG = @"UnityIosClipboardManagerBridge";

static NSString *_Nullable NSStringFromCString(const char *_Nullable value) {
    return value ? [NSString stringWithUTF8String:value] : nil;
}

void clipboardCopy(const char* requestJson, ClipboardOperationCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardCopy] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] copyWithRequestJson:nsRequestJson
                                                    handler:^(BOOL isSuccess, NSString *errorCode, NSString *errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode.UTF8String, errorMessage.UTF8String);
        }
    }];
}

void clipboardAppend(const char* requestJson, ClipboardOperationCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardAppend] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] appendWithRequestJson:nsRequestJson
                                                      handler:^(BOOL isSuccess, NSString *errorCode, NSString *errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode.UTF8String, errorMessage.UTF8String);
        }
    }];
}

void clipboardRead(const char* requestJson, ClipboardJsonCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardRead] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] readWithRequestJson:nsRequestJson
                                                    handler:^(NSString *json) {
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void clipboardReadData(const char* requestJson, ClipboardJsonCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardReadData] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] readDataWithRequestJson:nsRequestJson
                                                        handler:^(NSString *json) {
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void clipboardGetSnapshot(const char* requestJson, ClipboardJsonCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardGetSnapshot] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] getSnapshotWithRequestJson:nsRequestJson
                                                           handler:^(NSString *json) {
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void clipboardClear(const char* requestJson, ClipboardOperationCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardClear] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] clearWithRequestJson:nsRequestJson
                                                     handler:^(BOOL isSuccess, NSString *errorCode, NSString *errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode.UTF8String, errorMessage.UTF8String);
        }
    }];
}

void clipboardCreatePasteboard(const char* requestJson, ClipboardJsonCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardCreatePasteboard] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] createPasteboardWithRequestJson:nsRequestJson
                                                                handler:^(NSString *json) {
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void clipboardRemovePasteboard(const char* requestJson, ClipboardOperationCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardRemovePasteboard] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] removePasteboardWithRequestJson:nsRequestJson
                                                                 handler:^(BOOL isSuccess, NSString *errorCode, NSString *errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode.UTF8String, errorMessage.UTF8String);
        }
    }];
}

void clipboardDetectPatterns(const char* requestJson, ClipboardJsonCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardDetectPatterns] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] detectPatternsWithRequestJson:nsRequestJson
                                                               handler:^(NSString *json) {
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void clipboardDetectValues(const char* requestJson, ClipboardJsonCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardDetectValues] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] detectValuesWithRequestJson:nsRequestJson
                                                             handler:^(NSString *json) {
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void clipboardLoadItem(const char* requestJson, ClipboardJsonCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardLoadItem] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] loadItemWithRequestJson:nsRequestJson
                                                        handler:^(NSString *json) {
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void clipboardCancelLoads(ClipboardOperationCallback callback) {
    [Log d:TAG :@"[clipboardCancelLoads]"];
    [[UnityIosClipboardManager shared] cancelLoadsWithHandler:^(BOOL isSuccess, NSString *errorCode, NSString *errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode.UTF8String, errorMessage.UTF8String);
        }
    }];
}

void clipboardStartObserving(const char* requestJson,
                             ClipboardChangeCallback changeCallback,
                             ClipboardOperationCallback startCallback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardStartObserving] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] startObservingWithRequestJson:nsRequestJson
        changeHandler:^(NSString *eventJson) {
            if (changeCallback) {
                changeCallback(eventJson.UTF8String);
            }
        }
        startHandler:^(BOOL isSuccess, NSString *errorCode, NSString *errorMessage) {
            if (startCallback) {
                startCallback(isSuccess, errorCode.UTF8String, errorMessage.UTF8String);
            }
        }];
}

void clipboardStopObserving(ClipboardOperationCallback callback) {
    [Log d:TAG :@"[clipboardStopObserving]"];
    [[UnityIosClipboardManager shared] stopObservingWithHandler:^(BOOL isSuccess, NSString *errorCode, NSString *errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode.UTF8String, errorMessage.UTF8String);
        }
    }];
}

void clipboardCheckForegroundChange(const char* requestJson, ClipboardJsonCallback callback) {
    NSString *nsRequestJson = NSStringFromCString(requestJson);
    [Log d:TAG :[NSString stringWithFormat:@"[clipboardCheckForegroundChange] requestJson: %@",
                 [ClipboardRedaction json:nsRequestJson ?: @""]]];
    [[UnityIosClipboardManager shared] checkForegroundChangeWithRequestJson:nsRequestJson
                                                                     handler:^(NSString *json) {
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}
