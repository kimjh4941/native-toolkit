//
//  UnityIosNotificationManagerBridge.h
//
//  C ABI bridge exposing Swift notification APIs (UnityIosNotificationManager) to Unity (C# P/Invoke).
//
//  Design Notes:
//  - All strings are UTF-8 encoded `const char*` and may be NULL where documented.
//  - Callbacks are invoked on the main thread.
//  - `isSuccess` reports whether the operation succeeded (false = error occurred).
//  - Optional error strings use NULL (not empty string) when no error.
//  - Do not retain raw pointer values past the callback; copy to managed strings immediately.
//

#import <Foundation/Foundation.h>
#import <IosLibrary/IosLibrary-Swift.h>
#import <UnityIosPlugin/UnityIosPlugin-Swift.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Callback for operations that report success/failure only.
/// - Parameters:
///   - isSuccess: Whether the operation succeeded.
///   - errorMessage: Human-readable diagnostic (NULL if no error).
typedef void (*NotificationCallback)(bool isSuccess, const char* errorMessage);

/// Callback that returns a JSON string result.
/// - Parameter json: UTF-8 JSON string (never NULL; may be empty array "[]").
typedef void (*NotificationJsonCallback)(const char* json);

/// Callback that returns an authorization status string.
/// - Parameter status: One of: "authorized", "denied", "notDetermined", "provisional", "ephemeral", "unknown".
typedef void (*NotificationStatusCallback)(const char* status);

/// Callback that returns a boolean value.
/// - Parameter value: The boolean result.
typedef void (*NotificationBoolCallback)(bool value);

/// Persistent callback invoked when a notification action button is tapped.
/// - Parameters:
///   - notificationId: The identifier of the notification.
///   - actionId: The identifier of the tapped action.
///   - userInfoJson: JSON object string containing custom notification data.
typedef void (*NotificationActionCallback)(const char* notificationId, const char* actionId, const char* userInfoJson);

/// Persistent callback invoked when a text input notification action is submitted.
/// - Parameters:
///   - notificationId: The identifier of the notification.
///   - actionId: The identifier of the tapped action.
///   - userText: The text entered by the user.
///   - userInfoJson: JSON object string containing custom notification data.
typedef void (*NotificationTextInputActionCallback)(const char* notificationId, const char* actionId, const char* userText, const char* userInfoJson);

/// Registers IosNotificationManager as UNUserNotificationCenterDelegate. Call once at app launch.
void notificationSetup(void);

/// Immediately shows a notification.
/// - Parameters:
///   - contentJson: JSON string for NotificationContent (required).
///   - triggerJson: JSON string for NotificationTrigger (NULL for immediate delivery).
///   - callback: Result callback; may be NULL.
void showNotification(const char* contentJson, const char* triggerJson, NotificationCallback callback);

/// Schedules a notification for future delivery.
/// - Parameters:
///   - contentJson: JSON string for NotificationContent (required).
///   - triggerJson: JSON string for NotificationTrigger (required).
///   - identifier: Unique identifier for the request.
///   - callback: Result callback; may be NULL.
void scheduleNotification(const char* contentJson, const char* triggerJson, const char* identifier, NotificationCallback callback);

/// Updates an existing pending notification.
void updateNotification(const char* identifier, const char* contentJson, const char* triggerJson, NotificationCallback callback);

/// Cancels a specific pending notification.
void cancelNotification(const char* identifier);

/// Cancels all pending notifications.
void cancelAllNotifications(void);

/// Removes a specific delivered notification from Notification Center.
void removeDeliveredNotification(const char* identifier);

/// Removes all delivered notifications from Notification Center.
void removeAllDeliveredNotifications(void);

/// Cancels a specific scheduled notification.
void cancelScheduledNotification(const char* identifier);

/// Cancels all scheduled notifications.
void cancelAllScheduledNotifications(void);

/// Returns all pending notification requests as a JSON array string.
void getScheduledNotifications(NotificationJsonCallback callback);

/// Returns all delivered notifications as a JSON array string.
void getDeliveredNotifications(NotificationJsonCallback callback);

/// Requests notification authorization.
void requestNotificationPermission(NotificationCallback callback);

/// Returns the current authorization status.
void getNotificationAuthorizationStatus(NotificationStatusCallback callback);

/// Opens the app's notification settings page.
void openNotificationSettings(void);

/// Sets the app icon badge count. Pass 0 to clear.
void setNotificationBadgeCount(int count, NotificationCallback callback);

/// Registers a notification category from a JSON string.
void registerNotificationCategory(const char* categoryJson, NotificationCallback callback);

/// Removes a registered notification category.
/// - Parameter identifier: The identifier of the category to remove.
void removeNotificationCategory(const char* identifier);

/// Returns whether the app currently has notification permission.
void hasNotificationPermission(NotificationBoolCallback callback);

/// Registers a persistent callback invoked when a notification action button is tapped.
/// Pass NULL to unregister. The callback is called on the main thread.
void setNotificationActionReceivedCallback(NotificationActionCallback callback);

/// Registers a persistent callback invoked when a text input notification action is submitted.
/// Pass NULL to unregister. The callback is called on the main thread.
void setNotificationTextInputActionReceivedCallback(NotificationTextInputActionCallback callback);

#ifdef __cplusplus
}
#endif
