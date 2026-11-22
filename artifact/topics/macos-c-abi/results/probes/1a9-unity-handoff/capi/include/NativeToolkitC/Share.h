/**
 * @file Share.h
 * @brief macOS C ABI 1a-9 probe: the share picker shown from a main-queue block (D-6, 1a-7).
 */
#ifndef NATIVETOOLKITC_SHARE_H
#define NATIVETOOLKITC_SHARE_H

#if defined(__has_include) && __has_include(<NtkProbeMacCApi/NativeToolkitC/Common.h>)
#include <NtkProbeMacCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_share_error;
enum {
    NTK_SHARE_ERROR_NONE = 0,
    NTK_SHARE_ERROR_INVALID_PARAMETER = 1,
    /** No key window and no main window to anchor the picker. */
    NTK_SHARE_ERROR_NOT_FOREGROUND = 6,
    NTK_SHARE_ERROR_EMPTY_CONTENT = 7
};

/**
 * chosen: 1 when a service was chosen in the picker (service_title is its title), 0 when the picker
 * closed without one (service_title is NULL). service_title is owned by the receiver.
 * NOTE: choosing a service starts that service (Mail, Messages, AirDrop...). The checks never choose one.
 */
typedef void (NTK_CALL *ntk_share_done_fn)(void* user_data, int32_t error, int32_t chosen, ntk_string* service_title);

/**
 * Queues on the main queue and shows NSSharingServicePicker with the text, anchored at the centre of
 * the content view of the key window (or the main window). The completion comes from the picker
 * delegate's didChoose (a service, or none when it closed). auto_close_ms > 0 calls picker.close()
 * after that many milliseconds (completion chosen = 0). INVALID_PARAMETER for a NULL callback or invalid
 * UTF-8, EMPTY_CONTENT for NULL or empty text (both with release before returning). NOT_FOREGROUND is
 * reported through the completion.
 */
ntk_share_error NTK_CALL ntk_share_show_async(const char* text, uint32_t auto_close_ms,
                                              ntk_share_done_fn callback, void* user_data, ntk_release_fn release);

#ifdef __cplusplus
}
#endif
#endif
