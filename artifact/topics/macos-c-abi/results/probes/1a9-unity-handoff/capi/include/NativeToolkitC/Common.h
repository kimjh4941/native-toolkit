/**
 * @file Common.h
 * @brief macOS C ABI 1a-9 probe (not the product). The part of Common.h this probe needs: the
 *        version, the release callback and the string handle. The declarations are the same as the
 *        iOS / Android Common.h; the bytes and string-list handles are left out of this probe.
 *
 * Rules (iOS C ABI design part 1, chapter 1, and macOS D-6): every function may be called from any
 * thread and never waits for the main thread, except ntk_notification_install and
 * ntk_probe_notification_install_at (main only, synchronous). An accepted request completes exactly
 * once, on the main thread, and then its release (when not NULL) is called once on the main thread.
 * The completion is never called synchronously inside the function that started it. Called from the
 * main thread, it therefore comes after the function returned. Called from another thread, it may run
 * on main in parallel with whatever the caller does after the call (iOS / Android AC-5). A request
 * rejected at the entry gets no completion, and its release is called on the calling thread before
 * the function returns.
 * Strings are NUL-terminated UTF-8. C99, ASCII only.
 */
#ifndef NATIVETOOLKITC_COMMON_H
#define NATIVETOOLKITC_COMMON_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_MSC_VER)
#define NTK_CALL __cdecl
#else
#define NTK_CALL
#endif

#define NTK_VERSION_MAJOR 2
#define NTK_VERSION_MINOR 0
#define NTK_VERSION_PATCH 0
/** (MAJOR << 16) | (MINOR << 8) | PATCH. */
#define NTK_VERSION 0x020000

/** Tells the caller that the library is done with a user_data pointer. Called exactly once. */
typedef void (NTK_CALL *ntk_release_fn)(void* user_data);

/** The version of the library, in the form of NTK_VERSION. */
uint32_t NTK_CALL ntk_version(void);

/** A string the library returned. The receiver owns it and frees it with ntk_string_free. */
typedef struct ntk_string ntk_string;
/** The text, NUL-terminated. Valid until the handle is freed. NULL for NULL. */
const char* NTK_CALL ntk_string_data(const ntk_string* s);
/** The length in bytes, without the terminator. */
size_t      NTK_CALL ntk_string_size(const ntk_string* s);
/** Releases the string. Does nothing for NULL. */
void        NTK_CALL ntk_string_free(ntk_string* s);

#ifdef __cplusplus
}
#endif
#endif
