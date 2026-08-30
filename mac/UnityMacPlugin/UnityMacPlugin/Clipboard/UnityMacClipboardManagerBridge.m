//
//  UnityMacClipboardManagerBridge.m
//  UnityMacPlugin
//
#import "UnityMacClipboardManagerBridge.h"

static NSString *const TAG = @"UnityMacClipboardManagerBridge";

/// Converts a C string to NSString, mapping NULL to nil rather than trapping.
///
/// `stringWithUTF8String:` is documented as taking a non-null pointer, so every argument has
/// to be checked before it reaches the Swift façade.
static NSString * _Nullable NTStr(const char* value) {
    return value ? [NSString stringWithUTF8String:value] : nil;
}

void clipboardCopy(const char* contentJson, const char* optionsJson, const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardCopy contentJson: %s, optionsJson: %s, scopeJson: %s, callback: %p",
                 contentJson ?: "(null)", optionsJson ?: "(null)", scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] copyWithContentJson:NTStr(contentJson)
                                             optionsJson:NTStr(optionsJson)
                                             scopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardAppend(const char* contentJson, const char* ownershipJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardAppend contentJson: %s, ownershipJson: %s, callback: %p",
                 contentJson ?: "(null)", ownershipJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] appendWithContentJson:NTStr(contentJson)
                                             ownershipJson:NTStr(ownershipJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardRead(const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardRead scopeJson: %s, callback: %p",
                 scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] readWithScopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardReadData(const char* utType, const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardReadData utType: %s, scopeJson: %s, callback: %p",
                 utType ?: "(null)", scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] readDataWithUtType:NTStr(utType)
                                             scopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardSnapshot(const char* matchingTypesJson, const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardSnapshot matchingTypesJson: %s, scopeJson: %s, callback: %p",
                 matchingTypesJson ?: "(null)", scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] snapshotMatchingTypesJson:NTStr(matchingTypesJson)
                                             scopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardClear(const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardClear scopeJson: %s, callback: %p",
                 scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] clearWithScopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardCreatePasteboard(const char* requestJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardCreatePasteboard requestJson: %s, callback: %p",
                 requestJson ?: "(null)", callback]];
    if (!callback) {
        [Log e:TAG :@"clipboardCreatePasteboard: callback is required; nothing was created."];
        return;
    }
    [[UnityMacClipboardManager shared] createPasteboardWithRequestJson:NTStr(requestJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardDetectPatterns(const char* patternsJson, const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardDetectPatterns patternsJson: %s, scopeJson: %s, callback: %p",
                 patternsJson ?: "(null)", scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] detectPatternsWithPatternsJson:NTStr(patternsJson)
                                             scopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardDetectValues(const char* patternsJson, const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardDetectValues patternsJson: %s, scopeJson: %s, callback: %p",
                 patternsJson ?: "(null)", scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] detectValuesWithPatternsJson:NTStr(patternsJson)
                                             scopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardDetectMetadata(const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardDetectMetadata scopeJson: %s, callback: %p",
                 scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] detectMetadataWithScopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardAccessBehavior(const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardAccessBehavior scopeJson: %s, callback: %p",
                 scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] accessBehaviorWithScopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardCheckForegroundChange(const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardCheckForegroundChange scopeJson: %s, callback: %p",
                 scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] checkForegroundChangeWithScopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        // Captures the C function pointer only, so the block is safe to move between
        // isolation domains (MIGRATION.md section 6, plan C).
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardRemovePasteboard(const char* scopeJson, ClipboardCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardRemovePasteboard scopeJson: %s, callback: %p",
                 scopeJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] removePasteboardWithScopeJson:NTStr(scopeJson)
                                             handler:^(BOOL isSuccess, NSInteger errorCode, NSString* errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardReleaseFilePromise(const char* handleJson, ClipboardCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardReleaseFilePromise handleJson: %s, callback: %p",
                 handleJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] releaseFilePromiseWithHandleJson:NTStr(handleJson)
                                             handler:^(BOOL isSuccess, NSInteger errorCode, NSString* errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardCancelReceiveFilePromises(const char* handleJson, ClipboardCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardCancelReceiveFilePromises handleJson: %s, callback: %p",
                 handleJson ?: "(null)", callback]];
    [[UnityMacClipboardManager shared] cancelReceiveFilePromisesWithHandleJson:NTStr(handleJson)
                                             handler:^(BOOL isSuccess, NSInteger errorCode, NSString* errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardStartObserving(const char* scopeJson,
                             double intervalSeconds,
                             ClipboardCallback callback,
                             ClipboardChangeCallback onChange) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardStartObserving scopeJson: %s, interval: %f, callback: %p, onChange: %p",
                 scopeJson ?: "(null)", intervalSeconds, callback, onChange]];
    // The event callback is turned into a block here rather than in Swift, so the Swift side
    // never sees a C function pointer.
    [[UnityMacClipboardManager shared] startObservingWithScopeJson:NTStr(scopeJson)
                                                   intervalSeconds:intervalSeconds
                                                          onChange:onChange ? ^(NSString* eventJson) {
        onChange(eventJson.UTF8String);
    } : nil
                                                           handler:^(BOOL isSuccess, NSInteger errorCode, NSString* errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardStopObserving(ClipboardCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardStopObserving callback: %p", callback]];
    [[UnityMacClipboardManager shared] stopObservingWithHandler:^(BOOL isSuccess, NSInteger errorCode, NSString* errorMessage) {
        if (callback) {
            callback(isSuccess, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardProvideFilePromise(const char* requestJson,
                                 const char* scopeJson,
                                 ClipboardJsonCallback callback) {
    // The request holds a full file path, which is never logged (section 4.2).
    [Log d:TAG :[NSString stringWithFormat:@"clipboardProvideFilePromise requestJson length: %lu, scopeJson: %s, callback: %p",
                 (unsigned long)(requestJson ? strlen(requestJson) : 0), scopeJson ?: "(null)", callback]];
    if (!callback) {
        [Log e:TAG :@"clipboardProvideFilePromise: callback is required; nothing was registered."];
        return;
    }
    [[UnityMacClipboardManager shared] provideFilePromiseWithRequestJson:NTStr(requestJson)
                                                              scopeJson:NTStr(scopeJson)
                                                                handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}

void clipboardReceiveFilePromises(const char* destinationPath,
                                  const char* scopeJson,
                                  const char* policyJson,
                                  ClipboardJsonCallback callback,
                                  ClipboardReceiptCallback onEvent) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardReceiveFilePromises scopeJson: %s, policyJson: %s, callback: %p, onEvent: %p",
                 scopeJson ?: "(null)", policyJson ?: "(null)", callback, onEvent]];
    if (!callback) {
        [Log e:TAG :@"clipboardReceiveFilePromises: callback is required; nothing was started."];
        return;
    }
    [[UnityMacClipboardManager shared] receiveFilePromisesWithDestinationPath:NTStr(destinationPath)
                                                                   scopeJson:NTStr(scopeJson)
                                                                  policyJson:NTStr(policyJson)
                                                                     onEvent:onEvent ? ^(BOOL isFinished, NSString* eventJson) {
        onEvent(isFinished, eventJson.UTF8String);
    } : nil
                                                                     handler:^(BOOL isSuccess, NSString* json, NSInteger errorCode, NSString* errorMessage) {
        if (callback) {
            callback(isSuccess, json.UTF8String, errorCode, errorMessage.UTF8String);
        }
    }];
}
