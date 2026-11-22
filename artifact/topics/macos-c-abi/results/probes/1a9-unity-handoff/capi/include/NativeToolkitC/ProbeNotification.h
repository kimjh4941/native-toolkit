/**
 * @file ProbeNotification.h
 * @brief macOS C ABI 1a-9 probe: the minimal notification functions for the cold-start check.
 *        Probe names and shapes; the product's are decided in C ABI design part 2.
 *        Every function returns NOT_SUPPORTED (release before returning) in a process without an app bundle.
 */
#ifndef NATIVETOOLKITC_PROBE_NOTIFICATION_H
#define NATIVETOOLKITC_PROBE_NOTIFICATION_H

#if defined(__has_include) && __has_include(<NtkProbeMacCApi/NativeToolkitC/Notification.h>)
#include <NtkProbeMacCApi/NativeToolkitC/Notification.h>
#else
#include "Notification.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_probe_notification_event_kind;
enum {
    NTK_PROBE_NOTIFICATION_EVENT_RESPONSE = 0, /* a click on the notification or an action */
    NTK_PROBE_NOTIFICATION_EVENT_SETTINGS = 1  /* openSettingsFor */
};

/** Strings are owned by the receiver and may be NULL. is_launch_response: 1 when this response came
    before the first NSApplicationDidBecomeActive of the process and the library handled it (the iOS
    original P1-22 rule; macOS decides it in D-7 with the 1a-8 material). */
typedef void (NTK_CALL *ntk_probe_notification_event_fn)(void* user_data, int32_t kind,
                                                         ntk_string* notification_identifier, ntk_string* action_identifier,
                                                         ntk_string* user_text, int32_t is_launch_response);
typedef void (NTK_CALL *ntk_probe_notification_done_fn)(void* user_data, int32_t error, int32_t granted);
typedef struct ntk_probe_notification_listener ntk_probe_notification_listener;

/** Registers a listener (events on main). A listener has no completion: its release comes once, on
    main, after ntk_probe_notification_listener_remove. Events that came while no listener was active
    (before the first one, or after the last one was removed; up to 32) are handed to the next one on
    main (after this returns when it is called on main; called from another thread, possibly before the
    caller sees out_listener). NOT_INITIALIZED before a successful install. */
ntk_notification_error NTK_CALL ntk_probe_notification_add_listener(ntk_probe_notification_event_fn callback, void* user_data,
                                                                    ntk_release_fn release,
                                                                    ntk_probe_notification_listener** out_listener);
/** Removes the listener; its release comes on main. NULL does nothing. */
void NTK_CALL ntk_probe_notification_listener_remove(ntk_probe_notification_listener* listener);
/** The launch response (identifier and action) or NULL / NULL. Read it after the app became active.
    NOT_INITIALIZED before a successful install. */
ntk_notification_error NTK_CALL ntk_probe_notification_get_launch_response(ntk_string** out_identifier, ntk_string** out_action);
/** requestAuthorization([.alert, .sound, .badge]). Shows the system permission prompt the first time. */
ntk_notification_error NTK_CALL ntk_probe_notification_request_permission(ntk_probe_notification_done_fn callback, void* user_data,
                                                                          ntk_release_fn release);
/** The current authorization status, in the completion's `granted` argument: 0 notDetermined,
    1 denied, 2 authorized, 3 provisional (UNAuthorizationStatus). error is NONE. Shows nothing. */
ntk_notification_error NTK_CALL ntk_probe_notification_get_authorization_status(ntk_probe_notification_done_fn callback, void* user_data,
                                                                                ntk_release_fn release);
/** Schedules one notification marked as the library's (userInfo com.jonghyunkim.nativetoolkit = 1)
    after seconds (0: at once). Completion with error NONE once it is added. */
ntk_notification_error NTK_CALL ntk_probe_notification_schedule_marked(uint32_t seconds, const char* identifier, const char* title,
                                                                       ntk_probe_notification_done_fn callback, void* user_data,
                                                                       ntk_release_fn release);
/** For the Unity check (1a-9): called by the host in main() before PlayerMain. Main thread only.
    when = 1: registers an NSApplicationWillFinishLaunchingNotification observer that calls
              ntk_notification_install when the notification is posted;
    when = 3: the same with NSApplicationDidFinishLaunchingNotification (for comparison);
    when = 2: calls ntk_notification_install now (NSApp does not exist yet).
    From this call on, willFinishLaunching / didFinishLaunching / didBecomeActive are recorded
    (ntk_probe_notification_describe). Returns WRONG_THREAD off main, INVALID_PARAMETER for another
    value, the result of ntk_notification_install for 2, and NONE for 1 and 3. */
ntk_notification_error NTK_CALL ntk_probe_notification_install_at(int32_t when);

/** The record of this process: install calls (thread, NSApp present, result), the launch notifications
    (willFinishLaunching, didFinishLaunching, didBecomeActive) and every delegate call, in order with the
    milliseconds since the first record, and the class of the current and previous delegate.
    Any thread. Never NULL; the receiver frees it. Works without an app bundle (no delegate read). */
ntk_string* NTK_CALL ntk_probe_notification_describe(void);

#ifdef __cplusplus
}
#endif
#endif
