/**
 * @file Dialog.h
 * @brief macOS C ABI 1a-9 probe: an alert shown the D-8 A' way. The name is the product-like one, the
 *        arguments are the probe's (the product's are decided in C ABI design part 2).
 */
#ifndef NATIVETOOLKITC_DIALOG_H
#define NATIVETOOLKITC_DIALOG_H

#if defined(__has_include) && __has_include(<NtkProbeMacCApi/NativeToolkitC/Common.h>)
#include <NtkProbeMacCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_dialog_error;
enum {
    NTK_DIALOG_ERROR_NONE = 0,
    NTK_DIALOG_ERROR_INVALID_PARAMETER = 1,
    /** Closed by auto_close_ms (abortModal) before a button was pressed. */
    NTK_DIALOG_ERROR_CANCELED = 6,
    /** NSApp does not exist (a command-line process). */
    NTK_DIALOG_ERROR_SHOW_FAILED = 10
};

/** button: 0 the positive button, 1 the negative button, -1 none (error is not NONE). */
typedef void (NTK_CALL *ntk_dialog_done_fn)(void* user_data, uint64_t request_id, int32_t error, int32_t button);

/**
 * Shows an app-modal NSAlert. The function queues a run-loop block on the main run loop
 * (CFRunLoopPerformBlock, common modes) and returns; the block calls NSAlert.runModal(). Because the
 * modal loop is not entered from inside a main-queue (GCD) block, the main queue keeps draining while
 * the alert is open (1a-6), so ntk_probe_echo_async and other completions still arrive.
 * title and positive_text are required; message and negative_text may be NULL (no message / no second
 * button). auto_close_ms > 0 closes the alert with NSApp.abortModal() after that many milliseconds when
 * it is still the modal window (completion CANCELED, button -1); 0 waits for a button.
 * The completion is queued on the main queue after runModal returned. out_request_id may be NULL.
 * INVALID_PARAMETER (release before returning) for a NULL callback, a NULL or empty title or positive
 * text, or invalid UTF-8.
 */
ntk_dialog_error NTK_CALL ntk_dialog_show_alert_async(const char* title, const char* message,
                                                      const char* positive_text, const char* negative_text,
                                                      uint32_t auto_close_ms,
                                                      ntk_dialog_done_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);

/**
 * The control of the Unity check (M-8), not a product function: the same alert, entered the D-8 A way
 * (today's MacDialogManager: runModal inside a DispatchQueue.main.async block). While it is open the
 * main queue is expected to stop (1a-6), so ntk_probe_echo_async completions wait until it closes.
 */
ntk_dialog_error NTK_CALL ntk_probe_dialog_show_alert_gcd_async(const char* title, const char* message,
                                                                const char* positive_text, const char* negative_text,
                                                                uint32_t auto_close_ms,
                                                                ntk_dialog_done_fn callback, void* user_data,
                                                                ntk_release_fn release, uint64_t* out_request_id);

#ifdef __cplusplus
}
#endif
#endif
