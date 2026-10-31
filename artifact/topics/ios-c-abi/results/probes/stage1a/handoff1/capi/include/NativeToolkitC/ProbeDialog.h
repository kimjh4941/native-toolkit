/**
 * @file ProbeDialog.h
 * @brief Stage 1a hand-off 1 probe only: one alert with up to two buttons, cancellable by request
 *        ID (C ABI design part 1, P1-11 to P1-14 and P1-24). Not the names of the real Dialog.h.
 *
 * Rules (part 1, chapter 1): every function may be called from any thread and never waits for the
 * main thread; the completion and an accepted release arrive on the main thread, never inside the
 * starting function; a rejected call releases on the calling thread before returning.
 */
#ifndef NATIVETOOLKITC_PROBE_DIALOG_H
#define NATIVETOOLKITC_PROBE_DIALOG_H

#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Same names and numbers as Android's ntk_dialog_error; 9 (HOST_START_FAILED) is unused on iOS. */
typedef int32_t ntk_probe_dialog_error;
enum {
    NTK_PROBE_DIALOG_ERROR_NONE = 0,
    NTK_PROBE_DIALOG_ERROR_INVALID_PARAMETER = 1,
    NTK_PROBE_DIALOG_ERROR_NOT_INITIALIZED = 2,
    NTK_PROBE_DIALOG_ERROR_NOT_SUPPORTED = 3,
    NTK_PROBE_DIALOG_ERROR_UNKNOWN = 4,
    NTK_PROBE_DIALOG_ERROR_OUT_OF_MEMORY = 5,
    NTK_PROBE_DIALOG_ERROR_CANCELED = 6,
    NTK_PROBE_DIALOG_ERROR_CANCELED_BY_SYSTEM = 7,
    NTK_PROBE_DIALOG_ERROR_NOT_FOREGROUND = 8,
    NTK_PROBE_DIALOG_ERROR_SHOW_FAILED = 10
};

typedef int32_t ntk_probe_dialog_button;
enum {
    NTK_PROBE_DIALOG_BUTTON_NONE = -1,      /**< error is not NONE. */
    NTK_PROBE_DIALOG_BUTTON_POSITIVE = 0,
    NTK_PROBE_DIALOG_BUTTON_NEGATIVE = 1
};

/** Called once on the main thread. button is NTK_PROBE_DIALOG_BUTTON_NONE unless error is NONE. */
typedef void (NTK_CALL *ntk_probe_dialog_done_fn)(void* user_data, uint64_t request_id, ntk_probe_dialog_error error,
                                                  uint32_t system_code, ntk_probe_dialog_button button);

/* Asynchronous: NONE means accepted. title and message may be NULL (no text). positive_text NULL is
   "OK"; negative_text NULL means no negative button. The alert goes on the top view controller of the
   foreground scene's key window (active or inactive, P1-11); while that view controller is still in a
   transition, the library waits once and checks again (P1-12). out_request_id may be NULL. */
ntk_probe_dialog_error NTK_CALL ntk_probe_dialog_show_alert(const char* title, const char* message,
                                                            const char* positive_text, const char* negative_text,
                                                            ntk_probe_dialog_done_fn callback, void* user_data,
                                                            ntk_release_fn release, uint64_t* out_request_id);

/* Cancels an accepted alert (P1-24): the completion comes with CANCELED and release follows. The alert
   is closed unless another view controller is presented on top of it. A finished or unknown ID does
   nothing. Always returns NONE. */
ntk_probe_dialog_error NTK_CALL ntk_probe_dialog_cancel(uint64_t request_id);

#ifdef __cplusplus
}
#endif
#endif
