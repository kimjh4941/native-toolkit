/**
 * @file ProbeNotification.h
 * @brief Stage 1a hand-off 2 probe only: notification events, the launch response, and a way to
 *        schedule a library notification. Not the names of the real Notification.h (part 2).
 *
 * Rules (part 1, chapter 1): every function may be called from any thread and never waits for the
 * main thread; events, completions and accepted releases arrive on the main thread.
 */
#ifndef NATIVETOOLKITC_PROBE_NOTIFICATION_H
#define NATIVETOOLKITC_PROBE_NOTIFICATION_H

#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Notification.h>)
#include <IosLibraryCApi/NativeToolkitC/Notification.h>
#else
#include "Notification.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_probe_notification_event_kind;
enum {
    NTK_PROBE_NOTIFICATION_EVENT_RESPONSE = 0,   /**< tap, action, text input or dismissal (didReceive) */
    NTK_PROBE_NOTIFICATION_EVENT_SETTINGS = 1    /**< openSettingsFor (P1-10); identifier NULL: no notification */
};

/** Called on the main thread for every event. The three strings are owned by the receiver
    (ntk_string_free) and may be NULL: identifier for a settings request without a notification,
    action and user_text for settings requests, user_text unless the action was a text input. */
typedef void (NTK_CALL *ntk_probe_notification_event_fn)(void* user_data, ntk_probe_notification_event_kind kind,
                                                         ntk_string* notification_identifier, ntk_string* action_identifier,
                                                         ntk_string* user_text, int32_t is_launch_response);

/** Called once on the main thread. granted is nonzero when notifications are allowed. */
typedef void (NTK_CALL *ntk_probe_notification_done_fn)(void* user_data, ntk_notification_error error,
                                                        uint32_t system_code, int32_t granted);

typedef struct ntk_probe_notification_listener ntk_probe_notification_listener;

/* Registers a listener for both kinds of events. NOT_INITIALIZED until ntk_notification_install has
   succeeded once in this process (P1-6). Events that arrived while no listener was registered are kept
   (up to 32 per kind) and handed to the next registered listener, inside its registration (5.12.7).
   *out_listener is NULL on failure. */
ntk_notification_error NTK_CALL ntk_probe_notification_add_listener(ntk_probe_notification_event_fn callback,
                                                                    void* user_data, ntk_release_fn release,
                                                                    ntk_probe_notification_listener** out_listener);

/* Removes a listener. From the main thread no event arrives after the call; from another thread
   events may arrive until release. release follows on the main thread. Do not remove twice. */
void NTK_CALL ntk_probe_notification_listener_remove(ntk_probe_notification_listener* listener);

/* The notification response that launched the app (P1-22), or NULLs when there is none (yet: the
   value is fixed after the app first becomes active). NOT_INITIALIZED before the first install. */
ntk_notification_error NTK_CALL ntk_probe_notification_get_launch_response(ntk_string** out_identifier,
                                                                           ntk_string** out_action);

/* Asks for permission (alert, sound, badge, app notification settings). While the state is not
   determined and the app is not in the foreground, completes with NOT_FOREGROUND. */
ntk_notification_error NTK_CALL ntk_probe_notification_request_permission(ntk_probe_notification_done_fn callback,
                                                                          void* user_data, ntk_release_fn release);

/* Schedules a library notification (userInfo marker, P1-9) after `seconds` (0: right away). Its
   category has a background action "BgAct" (options: none) and a text input action "Reply".
   identifier and title must be non-empty UTF-8. The completion reports the add result. */
ntk_notification_error NTK_CALL ntk_probe_notification_schedule_marked(uint32_t seconds, const char* identifier,
                                                                       const char* title,
                                                                       ntk_probe_notification_done_fn callback,
                                                                       void* user_data, ntk_release_fn release);

#ifdef __cplusplus
}
#endif
#endif
