/**
 * @file Probe.h
 * @brief macOS C ABI 1a-9 probe: functions that exist only to check the Unity host. Not the product.
 */
#ifndef NATIVETOOLKITC_PROBE_H
#define NATIVETOOLKITC_PROBE_H

#if defined(__has_include) && __has_include(<NtkProbeMacCApi/NativeToolkitC/Common.h>)
#include <NtkProbeMacCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_probe_error;
enum {
    NTK_PROBE_ERROR_NONE = 0,
    NTK_PROBE_ERROR_INVALID_PARAMETER = 1
};

/**
 * Where the caller runs. Synchronous; any thread. Every out pointer may be NULL.
 * out_is_main: pthread_main_np() of the calling thread (1 main, 0 not).
 * out_thread_id: pthread_threadid_np() of the calling thread.
 * out_has_nsapp: 1 when NSApp exists (read without creating it), 0 when it does not.
 * Returns NONE.
 */
ntk_probe_error NTK_CALL ntk_probe_thread_info(int32_t* out_is_main, uint64_t* out_thread_id, int32_t* out_has_nsapp);

/** The completion of ntk_probe_echo_async: the value it was given and pthread_main_np() at the call. */
typedef void (NTK_CALL *ntk_probe_echo_fn)(void* user_data, int32_t value, int32_t is_main);

/**
 * Queues the completion on the main queue (DispatchQueue.main.async, the way every completion of the
 * C ABI is delivered; with delay_ms > 0, DispatchQueue.main.asyncAfter) and returns. Call it with a
 * delay right after ntk_dialog_show_alert_async to see whether other completions arrive while the
 * alert is open, even when the host's frame loop stops. INVALID_PARAMETER when callback is NULL
 * (release is called before returning).
 */
ntk_probe_error NTK_CALL ntk_probe_echo_async(int32_t value, uint32_t delay_ms, ntk_probe_echo_fn callback,
                                              void* user_data, ntk_release_fn release);

/**
 * One line of facts about the process, for the results: the main bundle id and path, the class of
 * NSApp, whether NSApp is active, the key window and whether it is full screen (AppKit facts only on
 * the main thread), whether the app is sandboxed, and the paths the two probe frameworks were loaded
 * from. Any thread. The receiver frees the string. Never NULL.
 */
ntk_string* NTK_CALL ntk_probe_describe(void);

/**
 * The form ntk_probe_describe and the logs use for a path (no home folder, no user name): from
 * "<name>.app" on, ".../<name>.framework/...", "~/..." under the login user's home (from the user
 * database, not HOME), or ".../<last component>". The output writes the leading "..." as one
 * character, U+2026 (HORIZONTAL ELLIPSIS), in UTF-8. For the smoke. NULL or invalid UTF-8 gives NULL.
 * The receiver frees the string.
 */
ntk_string* NTK_CALL ntk_probe_redact_path(const char* path);

#ifdef __cplusplus
}
#endif
#endif
