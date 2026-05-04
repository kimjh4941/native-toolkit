//
//  UnityIosNotificationManagerBridge.m
//  UnityIosPlugin
//

#import "UnityIosNotificationManagerBridge.h"

static NSString *const TAG = @"UnityIosNotificationManagerBridge";

void notificationSetup(void) {
    [Log d:TAG :[NSString stringWithFormat:@"[notificationSetup]"]];
    [[UnityIosNotificationManager shared] setup];
}

void showNotification(const char* contentJson, const char* triggerJson, NotificationCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[showNotification] contentJson: %s, triggerJson: %s", contentJson, triggerJson ? triggerJson : "NULL"]];
    NSString* nsContentJson = [NSString stringWithUTF8String:contentJson];
    NSString* nsTriggerJson = triggerJson ? [NSString stringWithUTF8String:triggerJson] : nil;
    [[UnityIosNotificationManager shared] showNotificationWithContentJson:nsContentJson
                                                               triggerJson:nsTriggerJson
                                                               completion:^(BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"[showNotification] isSuccess: %d, errorMessage: %@", isSuccess, errorMessage]];
        if (callback) {
            const char* errorStr = errorMessage ? errorMessage.UTF8String : NULL;
            callback(isSuccess, errorStr);
        }
    }];
}

void scheduleNotification(const char* contentJson, const char* triggerJson, const char* identifier, NotificationCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[scheduleNotification] identifier: %s", identifier]];
    NSString* nsContentJson = [NSString stringWithUTF8String:contentJson];
    NSString* nsTriggerJson = [NSString stringWithUTF8String:triggerJson];
    NSString* nsIdentifier = [NSString stringWithUTF8String:identifier];
    [[UnityIosNotificationManager shared] scheduleNotificationWithContentJson:nsContentJson
                                                                   triggerJson:nsTriggerJson
                                                                    identifier:nsIdentifier
                                                                    completion:^(BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"[scheduleNotification] isSuccess: %d, errorMessage: %@", isSuccess, errorMessage]];
        if (callback) {
            const char* errorStr = errorMessage ? errorMessage.UTF8String : NULL;
            callback(isSuccess, errorStr);
        }
    }];
}

void updateNotification(const char* identifier, const char* contentJson, const char* triggerJson, NotificationCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[updateNotification] identifier: %s", identifier]];
    NSString* nsIdentifier = [NSString stringWithUTF8String:identifier];
    NSString* nsContentJson = [NSString stringWithUTF8String:contentJson];
    NSString* nsTriggerJson = triggerJson ? [NSString stringWithUTF8String:triggerJson] : nil;
    [[UnityIosNotificationManager shared] updateNotificationWithIdentifier:nsIdentifier
                                                                contentJson:nsContentJson
                                                                triggerJson:nsTriggerJson
                                                                completion:^(BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"[updateNotification] isSuccess: %d, errorMessage: %@", isSuccess, errorMessage]];
        if (callback) {
            const char* errorStr = errorMessage ? errorMessage.UTF8String : NULL;
            callback(isSuccess, errorStr);
        }
    }];
}

void cancelNotification(const char* identifier) {
    [Log d:TAG :[NSString stringWithFormat:@"[cancelNotification] identifier: %s", identifier]];
    NSString* nsIdentifier = [NSString stringWithUTF8String:identifier];
    [[UnityIosNotificationManager shared] cancelNotificationWithIdentifier:nsIdentifier];
}

void cancelAllNotifications(void) {
    [Log d:TAG :[NSString stringWithFormat:@"[cancelAllNotifications]"]];
    [[UnityIosNotificationManager shared] cancelAllNotifications];
}

void removeDeliveredNotification(const char* identifier) {
    [Log d:TAG :[NSString stringWithFormat:@"[removeDeliveredNotification] identifier: %s", identifier]];
    NSString* nsIdentifier = [NSString stringWithUTF8String:identifier];
    [[UnityIosNotificationManager shared] removeDeliveredNotificationWithIdentifier:nsIdentifier];
}

void removeAllDeliveredNotifications(void) {
    [Log d:TAG :[NSString stringWithFormat:@"[removeAllDeliveredNotifications]"]];
    [[UnityIosNotificationManager shared] removeAllDeliveredNotifications];
}

void cancelScheduledNotification(const char* identifier) {
    [Log d:TAG :[NSString stringWithFormat:@"[cancelScheduledNotification] identifier: %s", identifier]];
    NSString* nsIdentifier = [NSString stringWithUTF8String:identifier];
    [[UnityIosNotificationManager shared] cancelScheduledNotificationWithIdentifier:nsIdentifier];
}

void cancelAllScheduledNotifications(void) {
    [Log d:TAG :[NSString stringWithFormat:@"[cancelAllScheduledNotifications]"]];
    [[UnityIosNotificationManager shared] cancelAllScheduledNotifications];
}

void getScheduledNotifications(NotificationJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[getScheduledNotifications]"]];
    [[UnityIosNotificationManager shared] getScheduledNotificationsWithCompletion:^(NSString* json) {
        [Log d:TAG :[NSString stringWithFormat:@"[getScheduledNotifications] json: %@", json]];
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void getDeliveredNotifications(NotificationJsonCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[getDeliveredNotifications]"]];
    [[UnityIosNotificationManager shared] getDeliveredNotificationsWithCompletion:^(NSString* json) {
        [Log d:TAG :[NSString stringWithFormat:@"[getDeliveredNotifications] json: %@", json]];
        if (callback) {
            callback(json.UTF8String);
        }
    }];
}

void requestNotificationPermission(NotificationCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[requestNotificationPermission]"]];
    [[UnityIosNotificationManager shared] requestPermissionWithCompletion:^(BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"[requestNotificationPermission] isSuccess: %d, errorMessage: %@", isSuccess, errorMessage]];
        if (callback) {
            const char* errorStr = errorMessage ? errorMessage.UTF8String : NULL;
            callback(isSuccess, errorStr);
        }
    }];
}

void getNotificationAuthorizationStatus(NotificationStatusCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[getNotificationAuthorizationStatus]"]];
    [[UnityIosNotificationManager shared] getAuthorizationStatusWithCompletion:^(NSString* status) {
        [Log d:TAG :[NSString stringWithFormat:@"[getNotificationAuthorizationStatus] status: %@", status]];
        if (callback) {
            callback(status.UTF8String);
        }
    }];
}

void openNotificationSettings(void) {
    [Log d:TAG :[NSString stringWithFormat:@"[openNotificationSettings]"]];
    [[UnityIosNotificationManager shared] openNotificationSettings];
}

void setNotificationBadgeCount(int count, NotificationCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[setNotificationBadgeCount] count: %d", count]];
    [[UnityIosNotificationManager shared] setBadgeCount:count completion:^(BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"[setNotificationBadgeCount] isSuccess: %d, errorMessage: %@", isSuccess, errorMessage]];
        if (callback) {
            const char* errorStr = errorMessage ? errorMessage.UTF8String : NULL;
            callback(isSuccess, errorStr);
        }
    }];
}

void registerNotificationCategory(const char* categoryJson, NotificationCallback callback) {
    [Log d:TAG :[NSString stringWithFormat:@"[registerNotificationCategory] categoryJson: %s", categoryJson]];
    NSString* nsCategoryJson = [NSString stringWithUTF8String:categoryJson];
    [[UnityIosNotificationManager shared] registerCategoryWithCategoryJson:nsCategoryJson
                                                                completion:^(BOOL isSuccess, NSString* errorMessage) {
        [Log d:TAG :[NSString stringWithFormat:@"[registerNotificationCategory] isSuccess: %d, errorMessage: %@", isSuccess, errorMessage]];
        if (callback) {
            const char* errorStr = errorMessage ? errorMessage.UTF8String : NULL;
            callback(isSuccess, errorStr);
        }
    }];
}
