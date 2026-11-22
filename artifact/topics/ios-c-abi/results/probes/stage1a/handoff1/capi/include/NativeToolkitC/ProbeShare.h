/**
 * @file ProbeShare.h
 * @brief Stage 1a hand-off 1 probe only: share one text through IosLibrary's IosShareManager.
 *        Not the names of the real Share.h. Share cannot be cancelled (P1-24).
 */
#ifndef NATIVETOOLKITC_PROBE_SHARE_H
#define NATIVETOOLKITC_PROBE_SHARE_H

#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Same names and numbers as Android's ntk_share_error for the values used here. */
typedef int32_t ntk_probe_share_error;
enum {
    NTK_PROBE_SHARE_ERROR_NONE = 0,
    NTK_PROBE_SHARE_ERROR_INVALID_PARAMETER = 1,
    NTK_PROBE_SHARE_ERROR_NOT_INITIALIZED = 2,
    NTK_PROBE_SHARE_ERROR_NOT_SUPPORTED = 3,
    NTK_PROBE_SHARE_ERROR_UNKNOWN = 4,
    NTK_PROBE_SHARE_ERROR_OUT_OF_MEMORY = 5,
    NTK_PROBE_SHARE_ERROR_NOT_FOREGROUND = 6,
    NTK_PROBE_SHARE_ERROR_EMPTY_CONTENT = 7
};

/** Called once on the main thread. completed is nonzero when the user finished an activity;
    activity_type (owned by the receiver, ntk_string_free) is NULL when there is none. */
typedef void (NTK_CALL *ntk_probe_share_done_fn)(void* user_data, ntk_probe_share_error error, uint32_t system_code,
                                                 int32_t completed, ntk_string* activity_type);

/* Asynchronous: NONE means accepted. text must be non-empty UTF-8 (NULL: INVALID_PARAMETER,
   "": EMPTY_CONTENT). On iPad the sheet is anchored at the centre of the presenting view (P1-13). */
ntk_probe_share_error NTK_CALL ntk_probe_share_text(const char* text, ntk_probe_share_done_fn callback,
                                                    void* user_data, ntk_release_fn release);

#ifdef __cplusplus
}
#endif
#endif
