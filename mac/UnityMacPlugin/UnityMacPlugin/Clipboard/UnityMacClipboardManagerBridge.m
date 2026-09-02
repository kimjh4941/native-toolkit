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

/// Describes a JSON payload by length only.
///
/// Clipboard JSON carries the payload itself, base64 encoded. Logging it verbatim would copy
/// passwords, tokens and documents into whatever collects debug logs, which section 4.2 of the
/// design forbids. The Swift layer redacts through `ClipboardLog`; this is its counterpart for
/// the C layer.
static NSString *NTLen(const char* value) {
    return value ? [NSString stringWithFormat:@"len:%lu", (unsigned long)strlen(value)]
                 : @"(null)";
}

/// Describes a scope without revealing a named pasteboard.
///
/// A pasteboard name is chosen by the caller and can identify a workflow or a document, so
/// only `general` is logged verbatim; anything else becomes a short hash that is still enough
/// to correlate log lines.
static NSString *NTScope(const char* value) {
    if (!value) { return @"(null)"; }
    NSString *json = [NSString stringWithUTF8String:value];
    if ([json rangeOfString:@"\"general\""].location != NSNotFound) { return @"scope(general)"; }
    return [NSString stringWithFormat:@"scope(%08x)", (unsigned int)json.hash];
}

void clipboardCopy(const char* contentJson, const char* optionsJson, const char* scopeJson, ClipboardJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"clipboardCopy contentJson: %@, optionsJson: %@, scopeJson: %@, callback: %p",
                 NTLen(contentJson), NTLen(optionsJson), NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardAppend contentJson: %@, ownershipJson: %@, callback: %p",
                 NTLen(contentJson), NTLen(ownershipJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardRead scopeJson: %@, callback: %p",
                 NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardReadData utType: %@, scopeJson: %@, callback: %p",
                 NTLen(utType), NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardSnapshot matchingTypesJson: %@, scopeJson: %@, callback: %p",
                 NTLen(matchingTypesJson), NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardClear scopeJson: %@, callback: %p",
                 NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardCreatePasteboard requestJson: %@, callback: %p",
                 NTLen(requestJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardDetectPatterns patternsJson: %@, scopeJson: %@, callback: %p",
                 NTLen(patternsJson), NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardDetectValues patternsJson: %@, scopeJson: %@, callback: %p",
                 NTLen(patternsJson), NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardDetectMetadata scopeJson: %@, callback: %p",
                 NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardAccessBehavior scopeJson: %@, callback: %p",
                 NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardCheckForegroundChange scopeJson: %@, callback: %p",
                 NTScope(scopeJson), callback]];
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardRemovePasteboard scopeJson: %@, callback: %p",
                 NTScope(scopeJson), callback]];
    [[UnityMacClipboardManager shared] removePasteboardWithScopeJson:NTStr(scopeJson)
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
    [Log d:TAG :[NSString stringWithFormat:@"clipboardStartObserving scopeJson: %@, interval: %f, callback: %p, onChange: %p",
                 NTScope(scopeJson), intervalSeconds, callback, onChange]];
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

