/**
 * @file Probe.h
 * @brief Stage 1a prototype only. A struct with struct_size, an asynchronous call with a callback,
 *        user_data and release, and a call that queues a UIKit exception on the main thread.
 *        Not a proposal for the names of the real feature headers.
 */
#ifndef NATIVETOOLKITC_PROBE_H
#define NATIVETOOLKITC_PROBE_H

/* Inside IosLibraryCApi.framework the module verifier rejects a quoted include, so the framework
   path comes first; the quoted form stays for the loose copy of the headers (dist/include). */
#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_probe_error;
enum {
    NTK_PROBE_ERROR_NONE = 0,
    NTK_PROBE_ERROR_INVALID_PARAMETER = 1,
    NTK_PROBE_ERROR_NOT_INITIALIZED = 2,
    NTK_PROBE_ERROR_NOT_SUPPORTED = 3,
    NTK_PROBE_ERROR_UNKNOWN = 4,
    NTK_PROBE_ERROR_OUT_OF_MEMORY = 5,
    NTK_PROBE_ERROR_READ_FAILED = 6
};

#pragma pack(push, 8)
/* A zero-filled struct (apart from struct_size) is the default request. sizeof 24. */
typedef struct ntk_probe_echo_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* text;        /**< UTF-8; NULL is the empty string. */
    int32_t     uppercase;   /**< Nonzero: upper-case the text. */
    uint32_t    reserved1;
} ntk_probe_echo_request;
#pragma pack(pop)

/* Synchronous. Copies request->text through an NSString and back into *out_text. */
ntk_probe_error NTK_CALL ntk_probe_echo(const ntk_probe_echo_request* request, ntk_string** out_text);

/** Called once on the main thread. text is owned by the receiver (ntk_string_free); NULL unless error is NONE. */
typedef void (NTK_CALL *ntk_probe_text_fn)(void* user_data, uint64_t request_id, ntk_probe_error error,
                                           uint32_t system_code, ntk_string* text);

/* Asynchronous: NONE means accepted. Reads the first text item of the named pasteboard
   "com.jonghyunkim.nativetoolkit.stage1a.probe" (created by the caller) through IosLibrary; the result arrives through callback on the main thread, then release (if not NULL).
   When the call is rejected, release is called on the calling thread before the function returns.
   out_request_id may be NULL. */
ntk_probe_error NTK_CALL ntk_probe_clipboard_read_text_async(ntk_probe_text_fn callback, void* user_data,
                                                             ntk_release_fn release, uint64_t* out_request_id);

typedef int32_t ntk_probe_exception_kind;
enum {
    NTK_PROBE_EXCEPTION_NONE = 0,
    NTK_PROBE_EXCEPTION_ALERT_TEXT_FIELD = 1,   /**< addTextField on an action sheet. */
    NTK_PROBE_EXCEPTION_POPOVER_NO_ANCHOR = 2   /**< present an action sheet without an anchor (iPad). */
};

/** Called once on the main thread after the queued block ran without an exception. */
typedef void (NTK_CALL *ntk_probe_done_fn)(void* user_data, uint64_t request_id, ntk_probe_error error,
                                           uint32_t system_code);

/* Asynchronous. Queues a block on the main thread that makes UIKit raise an NSException. */
ntk_probe_error NTK_CALL ntk_probe_raise_uikit_exception_async(ntk_probe_exception_kind kind,
                                                               ntk_probe_done_fn callback, void* user_data,
                                                               ntk_release_fn release, uint64_t* out_request_id);

#ifdef __cplusplus
}
#endif
#endif
