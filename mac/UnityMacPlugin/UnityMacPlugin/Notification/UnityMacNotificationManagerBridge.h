//
//  UnityMacNotificationManagerBridge.h
//  UnityMacPlugin
//
//  Created by Kim Jong Hyun on 2026/05/09.
//
#import <Foundation/Foundation.h>
#import <MacLibrary/MacLibrary-Swift.h>
#import <UnityMacPlugin/UnityMacPlugin-Swift.h>

#ifdef __cplusplus
extern "C" {
#endif

/*!
 * @typedef NotificationSimpleCallback
 * @abstract Callback for fire-and-forget notification operations (no returned data).
 *
 * @param isSuccess YES if the operation succeeded.
 * @param errorCode 0 on success; non-zero error code on failure.
 * @param errorMessage UTF-8 C string describing the error (NULL on success).
 *        Valid only during the callback invocation — copy immediately.
 */
typedef void (*NotificationSimpleCallback)(bool isSuccess,
                                           int errorCode,
                                           const char* errorMessage);

/*!
 * @typedef NotificationJsonCallback
 * @abstract Callback for operations that return a UTF-8 JSON string.
 *
 * @param json UTF-8 NUL-terminated JSON string (NULL on failure).
 *        Valid only during the callback invocation — copy immediately.
 * @param errorCode 0 on success; non-zero error code on failure.
 * @param errorMessage UTF-8 C string describing the error (NULL on success).
 *        Valid only during the callback invocation — copy immediately.
 */
typedef void (*NotificationJsonCallback)(const char* json,
                                         int errorCode,
                                         const char* errorMessage);

/*!
 * @typedef NotificationActionCallback
 * @abstract Callback invoked when the user taps a notification action button.
 *
 * @param notificationId UTF-8 identifier of the originating notification.
 * @param actionId UTF-8 identifier of the tapped action.
 *        Both pointers are valid only during the callback invocation — copy immediately.
 */
typedef void (*NotificationActionCallback)(const char* notificationId,
                                           const char* actionId);

/*!
 * @typedef NotificationTextInputActionCallback
 * @abstract Callback invoked when the user submits text in a text-input action.
 *
 * @param notificationId UTF-8 identifier of the originating notification.
 * @param actionId UTF-8 identifier of the text-input action.
 * @param userText UTF-8 text entered by the user.
 *        All pointers are valid only during the callback invocation — copy immediately.
 */
typedef void (*NotificationTextInputActionCallback)(const char* notificationId,
                                                    const char* actionId,
                                                    const char* userText);

/*!
 * @function NotificationSetup
 * @abstract Registers the notification delegate. Call once at application launch.
 */
void NotificationSetup(void);

/*!
 * @function NotificationRequestPermission
 * @abstract Requests notification authorization from the user.
 *
 * @param callback Receives (isSuccess, errorCode, errorMessage).
 */
void NotificationRequestPermission(NotificationSimpleCallback callback);

/*!
 * @function NotificationGetAuthorizationStatus
 * @abstract Returns the current notification authorization status as JSON.
 *
 * JSON: {"status": "authorized"|"denied"|"notDetermined"|"provisional"|"unsupported"}
 *
 * @param callback Receives (json, errorCode, errorMessage).
 */
void NotificationGetAuthorizationStatus(NotificationJsonCallback callback);

/*!
 * @function NotificationOpenSettings
 * @abstract Opens the system Notification Settings page.
 *
 * @param callback Receives (isSuccess, errorCode, errorMessage).
 */
void NotificationOpenSettings(NotificationSimpleCallback callback);

/*!
 * @function NotificationShow
 * @abstract Displays a notification immediately or at the specified trigger time.
 *
 * @param contentJson UTF-8 JSON string for NotificationContent.
 * @param triggerJson UTF-8 JSON string for NotificationTrigger.
 * @param callback Receives (isSuccess, errorCode, errorMessage).
 */
void NotificationShow(const char* contentJson,
                      const char* triggerJson,
                      NotificationSimpleCallback callback);

/*!
 * @function NotificationUpdate
 * @abstract Updates an existing pending notification.
 *
 * @param identifier UTF-8 notification identifier to replace.
 * @param contentJson UTF-8 JSON string for NotificationContent.
 * @param triggerJson UTF-8 JSON string for NotificationTrigger.
 * @param callback Receives (isSuccess, errorCode, errorMessage).
 */
void NotificationUpdate(const char* identifier,
                         const char* contentJson,
                         const char* triggerJson,
                         NotificationSimpleCallback callback);

/*!
 * @function NotificationSchedule
 * @abstract Schedules a future notification.
 *
 * @param contentJson UTF-8 JSON string for NotificationContent.
 * @param triggerJson UTF-8 JSON string for NotificationTrigger (must not be immediate).
 * @param callback Receives (isSuccess, errorCode, errorMessage).
 */
void NotificationSchedule(const char* contentJson,
                           const char* triggerJson,
                           NotificationSimpleCallback callback);

/*!
 * @function NotificationCancelScheduled
 * @abstract Cancels the pending notification with the given identifier.
 *
 * @param identifier UTF-8 notification identifier.
 */
void NotificationCancelScheduled(const char* identifier);

/*!
 * @function NotificationCancelAllScheduled
 * @abstract Cancels all pending notifications.
 */
void NotificationCancelAllScheduled(void);

/*!
 * @function NotificationGetScheduled
 * @abstract Returns all pending notifications as a UTF-8 JSON array.
 *
 * @param callback Receives (json, errorCode, errorMessage).
 */
void NotificationGetScheduled(NotificationJsonCallback callback);

/*!
 * @function NotificationGetDelivered
 * @abstract Returns all delivered notifications as a UTF-8 JSON array.
 *
 * @param callback Receives (json, errorCode, errorMessage).
 */
void NotificationGetDelivered(NotificationJsonCallback callback);

/*!
 * @function NotificationRemoveDelivered
 * @abstract Removes a delivered notification by identifier.
 *
 * @param identifier UTF-8 notification identifier.
 */
void NotificationRemoveDelivered(const char* identifier);

/*!
 * @function NotificationRemoveAllDelivered
 * @abstract Removes all delivered notifications.
 */
void NotificationRemoveAllDelivered(void);

/*!
 * @function NotificationRegisterCategory
 * @abstract Registers a notification category from a JSON string.
 *
 * @param categoryJson UTF-8 JSON string for NotificationCategory.
 * @param callback Receives (isSuccess, errorCode, errorMessage).
 */
void NotificationRegisterCategory(const char* categoryJson,
                                   NotificationSimpleCallback callback);

/*!
 * @function NotificationRemoveCategory
 * @abstract Removes a registered category by identifier.
 *
 * @param identifier UTF-8 category identifier.
 * @param callback Receives (isSuccess, errorCode, errorMessage).
 */
void NotificationRemoveCategory(const char* identifier,
                                 NotificationSimpleCallback callback);

/*!
 * @function NotificationSetActionReceivedCallback
 * @abstract Registers the global callback for action button taps.
 *
 * Only one callback is retained at a time (last registration wins).
 *
 * @param callback Receives (notificationId, actionId).
 *        Pointer lifetimes: valid only during the callback invocation.
 */
void NotificationSetActionReceivedCallback(NotificationActionCallback callback);

/*!
 * @function NotificationSetTextInputActionReceivedCallback
 * @abstract Registers the global callback for text-input action submissions.
 *
 * Only one callback is retained at a time (last registration wins).
 *
 * @param callback Receives (notificationId, actionId, userText).
 *        Pointer lifetimes: valid only during the callback invocation.
 */
void NotificationSetTextInputActionReceivedCallback(NotificationTextInputActionCallback callback);

/*!
 * @function NotificationSetBadgeCount
 * @abstract Sets the application badge count (0 clears the badge).
 *
 * @param count Badge count (0–9999).
 * @param callback Receives (isSuccess, errorCode, errorMessage).
 */
void NotificationSetBadgeCount(int count, NotificationSimpleCallback callback);

#ifdef __cplusplus
}
#endif
