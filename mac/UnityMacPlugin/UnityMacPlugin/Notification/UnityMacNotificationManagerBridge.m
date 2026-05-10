//
//  UnityMacNotificationManagerBridge.m
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
#import "UnityMacNotificationManagerBridge.h"

static NSString *const TAG = @"UnityMacNotificationManagerBridge";

// MARK: - Setup

void NotificationSetup(void) {
    [Log d:TAG :@"NotificationSetup called"];
    [[UnityMacNotificationManager shared] setup];
}

// MARK: - Permission

void NotificationRequestPermission(NotificationSimpleCallback callback) {
    [Log d:TAG :@"NotificationRequestPermission called"];
    if (!callback) {
        [Log e:TAG :@"NotificationRequestPermission: callback is NULL"];
        return;
    }
    [[UnityMacNotificationManager shared] requestPermissionWithCompletion:^(bool isSuccess, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationRequestPermission result: isSuccess=%d errorCode=%ld", isSuccess, (long)errorCode]];
        callback(isSuccess, (int)errorCode, errorMessage.UTF8String);
    }];
}

void NotificationGetAuthorizationStatus(NotificationJsonCallback callback) {
    [Log d:TAG :@"NotificationGetAuthorizationStatus called"];
    if (!callback) {
        [Log e:TAG :@"NotificationGetAuthorizationStatus: callback is NULL"];
        return;
    }
    [[UnityMacNotificationManager shared] getAuthorizationStatusWithCompletion:^(NSString* _Nullable json, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationGetAuthorizationStatus result: errorCode=%ld", (long)errorCode]];
        callback(json.UTF8String, (int)errorCode, errorMessage.UTF8String);
    }];
}

void NotificationOpenSettings(NotificationSimpleCallback callback) {
    [Log d:TAG :@"NotificationOpenSettings called"];
    if (!callback) {
        [Log e:TAG :@"NotificationOpenSettings: callback is NULL"];
        return;
    }
    [[UnityMacNotificationManager shared] openNotificationSettingsWithCompletion:^(bool isSuccess, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationOpenSettings result: isSuccess=%d errorCode=%ld", isSuccess, (long)errorCode]];
        callback(isSuccess, (int)errorCode, errorMessage.UTF8String);
    }];
}

// MARK: - Show / Update

void NotificationShow(const char* contentJson,
                      const char* triggerJson,
                      NotificationSimpleCallback callback) {
    [Log d:TAG :@"NotificationShow called"];
    if (!callback) {
        [Log e:TAG :@"NotificationShow: callback is NULL"];
        return;
    }
    NSString* nsContentJson = contentJson ? [NSString stringWithUTF8String:contentJson] : @"";
    NSString* nsTriggerJson = triggerJson ? [NSString stringWithUTF8String:triggerJson] : @"{}";
    [[UnityMacNotificationManager shared] showWithContentJson:nsContentJson
                                                  triggerJson:nsTriggerJson
                                                   completion:^(bool isSuccess, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationShow result: isSuccess=%d errorCode=%ld", isSuccess, (long)errorCode]];
        callback(isSuccess, (int)errorCode, errorMessage.UTF8String);
    }];
}

void NotificationUpdate(const char* identifier,
                         const char* contentJson,
                         const char* triggerJson,
                         NotificationSimpleCallback callback) {
    [Log d:TAG :@"NotificationUpdate called"];
    if (!callback) {
        [Log e:TAG :@"NotificationUpdate: callback is NULL"];
        return;
    }
    NSString* nsIdentifier = identifier ? [NSString stringWithUTF8String:identifier] : @"";
    NSString* nsContentJson = contentJson ? [NSString stringWithUTF8String:contentJson] : @"";
    NSString* nsTriggerJson = triggerJson ? [NSString stringWithUTF8String:triggerJson] : @"{}";
    [[UnityMacNotificationManager shared] updateWithIdentifier:nsIdentifier
                                                   contentJson:nsContentJson
                                                   triggerJson:nsTriggerJson
                                                    completion:^(bool isSuccess, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationUpdate result: isSuccess=%d errorCode=%ld", isSuccess, (long)errorCode]];
        callback(isSuccess, (int)errorCode, errorMessage.UTF8String);
    }];
}

// MARK: - Schedule

void NotificationSchedule(const char* contentJson,
                           const char* triggerJson,
                           NotificationSimpleCallback callback) {
    [Log d:TAG :@"NotificationSchedule called"];
    if (!callback) {
        [Log e:TAG :@"NotificationSchedule: callback is NULL"];
        return;
    }
    NSString* nsContentJson = contentJson ? [NSString stringWithUTF8String:contentJson] : @"";
    NSString* nsTriggerJson = triggerJson ? [NSString stringWithUTF8String:triggerJson] : @"{}";
    [[UnityMacNotificationManager shared] scheduleWithContentJson:nsContentJson
                                                      triggerJson:nsTriggerJson
                                                       completion:^(bool isSuccess, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationSchedule result: isSuccess=%d errorCode=%ld", isSuccess, (long)errorCode]];
        callback(isSuccess, (int)errorCode, errorMessage.UTF8String);
    }];
}

void NotificationCancelScheduled(const char* identifier) {
    [Log d:TAG :[NSString stringWithFormat:@"NotificationCancelScheduled called with identifier: %s", identifier ?: "(null)"]];
    NSString* nsIdentifier = identifier ? [NSString stringWithUTF8String:identifier] : @"";
    [[UnityMacNotificationManager shared] cancelScheduledWithIdentifier:nsIdentifier];
}

void NotificationCancelAllScheduled(void) {
    [Log d:TAG :@"NotificationCancelAllScheduled called"];
    [[UnityMacNotificationManager shared] cancelAllScheduled];
}

void NotificationGetScheduled(NotificationJsonCallback callback) {
    [Log d:TAG :@"NotificationGetScheduled called"];
    if (!callback) {
        [Log e:TAG :@"NotificationGetScheduled: callback is NULL"];
        return;
    }
    [[UnityMacNotificationManager shared] getScheduledWithCompletion:^(NSString* _Nullable json, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationGetScheduled result: errorCode=%ld", (long)errorCode]];
        callback(json.UTF8String, (int)errorCode, errorMessage.UTF8String);
    }];
}

// MARK: - Delivered

void NotificationGetDelivered(NotificationJsonCallback callback) {
    [Log d:TAG :@"NotificationGetDelivered called"];
    if (!callback) {
        [Log e:TAG :@"NotificationGetDelivered: callback is NULL"];
        return;
    }
    [[UnityMacNotificationManager shared] getDeliveredWithCompletion:^(NSString* _Nullable json, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationGetDelivered result: errorCode=%ld", (long)errorCode]];
        callback(json.UTF8String, (int)errorCode, errorMessage.UTF8String);
    }];
}

void NotificationRemoveDelivered(const char* identifier) {
    [Log d:TAG :[NSString stringWithFormat:@"NotificationRemoveDelivered called with identifier: %s", identifier ?: "(null)"]];
    NSString* nsIdentifier = identifier ? [NSString stringWithUTF8String:identifier] : @"";
    [[UnityMacNotificationManager shared] removeDeliveredWithIdentifier:nsIdentifier];
}

void NotificationRemoveAllDelivered(void) {
    [Log d:TAG :@"NotificationRemoveAllDelivered called"];
    [[UnityMacNotificationManager shared] removeAllDelivered];
}

// MARK: - Category

void NotificationRegisterCategory(const char* categoryJson,
                                   NotificationSimpleCallback callback) {
    [Log d:TAG :@"NotificationRegisterCategory called"];
    if (!callback) {
        [Log e:TAG :@"NotificationRegisterCategory: callback is NULL"];
        return;
    }
    NSString* nsCategoryJson = categoryJson ? [NSString stringWithUTF8String:categoryJson] : @"";
    [[UnityMacNotificationManager shared] registerCategoryWithCategoryJson:nsCategoryJson
                                                                completion:^(bool isSuccess, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationRegisterCategory result: isSuccess=%d errorCode=%ld", isSuccess, (long)errorCode]];
        callback(isSuccess, (int)errorCode, errorMessage.UTF8String);
    }];
}

void NotificationRemoveCategory(const char* identifier,
                                 NotificationSimpleCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"NotificationRemoveCategory called with identifier: %s", identifier ?: "(null)"]];
    if (!callback) {
        [Log e:TAG :@"NotificationRemoveCategory: callback is NULL"];
        return;
    }
    NSString* nsIdentifier = identifier ? [NSString stringWithUTF8String:identifier] : @"";
    [[UnityMacNotificationManager shared] removeCategoryWithIdentifier:nsIdentifier
                                                            completion:^(bool isSuccess, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationRemoveCategory result: isSuccess=%d errorCode=%ld", isSuccess, (long)errorCode]];
        callback(isSuccess, (int)errorCode, errorMessage.UTF8String);
    }];
}

// MARK: - Action Callbacks

void NotificationSetActionReceivedCallback(NotificationActionCallback callback) {
    [Log d:TAG :@"NotificationSetActionReceivedCallback called"];
    if (!callback) {
        [Log e:TAG :@"NotificationSetActionReceivedCallback: callback is NULL"];
        return;
    }
    [[UnityMacNotificationManager shared] setActionReceivedHandler:^(NSString* notificationId, NSString* actionId, NSString* userInfoJson) {
        [Log d:TAG :[NSString stringWithFormat:@"action received notificationId: %@ actionId: %@", notificationId, actionId]];
        callback(notificationId.UTF8String, actionId.UTF8String, userInfoJson.UTF8String);
    }];
}

void NotificationSetTextInputActionReceivedCallback(NotificationTextInputActionCallback callback) {
    [Log d:TAG :@"NotificationSetTextInputActionReceivedCallback called"];
    if (!callback) {
        [Log e:TAG :@"NotificationSetTextInputActionReceivedCallback: callback is NULL"];
        return;
    }
    [[UnityMacNotificationManager shared] setTextInputActionReceivedHandler:^(NSString* notificationId, NSString* actionId, NSString* userText, NSString* userInfoJson) {
        [Log d:TAG :[NSString stringWithFormat:@"text input action received notificationId: %@ actionId: %@ userText: %@", notificationId, actionId, userText]];
        callback(notificationId.UTF8String, actionId.UTF8String, userText.UTF8String, userInfoJson.UTF8String);
    }];
}

// MARK: - Has Permission

static NotificationBoolCallback s_hasPermissionCallback = NULL;

void NotificationHasPermission(NotificationBoolCallback callback) {
    [Log d:TAG :@"NotificationHasPermission called"];
    s_hasPermissionCallback = callback;
    [[UnityMacNotificationManager shared] hasPermissionWithCompletion:^(BOOL value) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationHasPermission result: value=%d", value]];
        if (s_hasPermissionCallback) {
            s_hasPermissionCallback(value);
        }
    }];
}

// MARK: - Cancel

void NotificationCancel(const char* identifier) {
    [Log d:TAG :[NSString stringWithFormat:@"NotificationCancel called with identifier: %s", identifier ?: "(null)"]];
    NSString* nsIdentifier = identifier ? [NSString stringWithUTF8String:identifier] : @"";
    [[UnityMacNotificationManager shared] cancelNotificationWithIdentifier:nsIdentifier];
}

void NotificationCancelAll(void) {
    [Log d:TAG :@"NotificationCancelAll called"];
    [[UnityMacNotificationManager shared] cancelAllNotifications];
}

// MARK: - Badge

void NotificationSetBadgeCount(int count, NotificationSimpleCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"NotificationSetBadgeCount called with count: %d", count]];
    if (!callback) {
        [Log e:TAG :@"NotificationSetBadgeCount: callback is NULL"];
        return;
    }
    [[UnityMacNotificationManager shared] setBadgeCount:count completion:^(bool isSuccess, NSInteger errorCode, NSString* _Nullable errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"NotificationSetBadgeCount result: isSuccess=%d errorCode=%ld", isSuccess, (long)errorCode]];
        callback(isSuccess, (int)errorCode, errorMessage.UTF8String);
    }];
}
