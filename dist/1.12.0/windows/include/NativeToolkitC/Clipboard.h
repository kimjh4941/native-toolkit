/**
 * @file Clipboard.h
 * @brief The clipboard: a session, reading and writing, deferred rendering,
 *        and the clipboard history (OP-21..OP-47).
 *
 * The owner thread: the thread that calls ntk_clipboard_session_create owns
 * the session. It must be initialised for COM as an STA
 * (CoInitializeEx(NULL, COINIT_APARTMENTTHREADED)) and must keep running a
 * message loop (GetMessageW, TranslateMessage, DispatchMessageW): the session
 * owns a hidden window, and every callback and completion is delivered
 * through it. A thread with no message loop receives nothing.
 *
 * Which thread may call what:
 *  - Reading and writing, and starting a history request: any thread. While
 *    this session has formats reserved for deferred rendering, a read or write
 *    on another thread waits until the owner handles the messages Windows
 *    sends it, so the owner must not wait for such a thread.
 *  - The session itself, the history handlers and deferred rendering: the
 *    owner thread only.
 *  - Completions and callbacks arrive on the owner thread.
 *
 * One session per process. A second ntk_clipboard_session_create is
 * NTK_CLIPBOARD_ERROR_NOT_SUPPORTED from the owner thread and
 * NTK_CLIPBOARD_ERROR_WRONG_THREAD from any other.
 *
 * Inside a callback of a session, do not close, free, or replace the history
 * handlers of that session (design 1.3.5).
 */
#ifndef NATIVETOOLKITC_CLIPBOARD_H
#define NATIVETOOLKITC_CLIPBOARD_H

#include "NativeToolkitC/Common.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

/** The result of every clipboard function that can fail. */
typedef int32_t ntk_clipboard_error;
enum {
    NTK_CLIPBOARD_ERROR_NONE = 0,
    NTK_CLIPBOARD_ERROR_INVALID_PARAMETER = 1,      /**< A NULL handle, output or required argument; malformed input. */
    NTK_CLIPBOARD_ERROR_NOT_INITIALIZED = 2,        /**< The session is closed. */
    NTK_CLIPBOARD_ERROR_BUSY = 3,                   /**< Another program holds the clipboard, or close has work in flight on another thread. */
    NTK_CLIPBOARD_ERROR_EMPTY = 4,
    NTK_CLIPBOARD_ERROR_FORMAT_UNAVAILABLE = 5,
    NTK_CLIPBOARD_ERROR_INVALID_DATA = 6,
    NTK_CLIPBOARD_ERROR_BUFFER_TOO_SMALL = 7,       /* reserved, never returned */
    NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY = 8,
    NTK_CLIPBOARD_ERROR_ACCESS_DENIED = 9,
    NTK_CLIPBOARD_ERROR_HISTORY_DISABLED = 10,
    NTK_CLIPBOARD_ERROR_ITEM_DELETED = 11,
    NTK_CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED = 12,
    NTK_CLIPBOARD_ERROR_PARTIAL_STATE = 13,         /**< A deferred reservation failed and could not be rolled back. */
    NTK_CLIPBOARD_ERROR_WRONG_THREAD = 14,          /**< An owner-thread function called from another thread. */
    NTK_CLIPBOARD_ERROR_CANCELED = 15,
    NTK_CLIPBOARD_ERROR_NOT_SUPPORTED = 16,         /**< A second session, or an input struct from a newer version. */
    NTK_CLIPBOARD_ERROR_NOT_FOREGROUND = 17,        /**< History needs this process in the foreground. */
    NTK_CLIPBOARD_ERROR_WRONG_APARTMENT = 18,       /**< The owner thread is not an STA. */
    NTK_CLIPBOARD_ERROR_UNKNOWN = 19
};

/** The flags of every copy function. Any other bit is NTK_CLIPBOARD_ERROR_INVALID_PARAMETER. */
enum {
    NTK_CLIPBOARD_WRITE_DEFAULT = 0,
    NTK_CLIPBOARD_WRITE_EXCLUDE_HISTORY = 1,        /**< Keep it out of the clipboard history. */
    NTK_CLIPBOARD_WRITE_EXCLUDE_ROAMING = 2,        /**< Do not let it reach the user's other devices. */
    NTK_CLIPBOARD_WRITE_SENSITIVE = 3               /**< Both of the above. */
};

/** The one clipboard session of the process. */
typedef struct ntk_clipboard_session ntk_clipboard_session;
/** Several formats to write at once. Not thread safe: build it on one thread. */
typedef struct ntk_clipboard_items ntk_clipboard_items;
/** The items of the clipboard history. Lent to ntk_clipboard_history_fn for the call only. */
typedef struct ntk_clipboard_history ntk_clipboard_history;
/** Where a deferred format's bytes go. Lent to ntk_clipboard_render_fn for the call only. */
typedef struct ntk_clipboard_render_target ntk_clipboard_render_target;

/** The clipboard changed. Changes this session made itself are not reported. */
typedef void (NTK_CALL *ntk_clipboard_changed_fn)(void* user_data);
/** An item was added to the clipboard history. */
typedef void (NTK_CALL *ntk_clipboard_history_changed_fn)(void* user_data);
/** The user turned the history, or its roaming, on (non-zero) or off (0). */
typedef void (NTK_CALL *ntk_clipboard_flag_changed_fn)(void* user_data, int32_t enabled);

/**
 * @brief Produces the bytes of a deferred format when a program asks for it.
 * @details Runs on the owner thread. Hand the bytes over with at most one
 *          ntk_clipboard_render_target_set, then return
 *          NTK_CLIPBOARD_ERROR_NONE. Returning NONE without setting renders
 *          nothing; returning anything else renders nothing even if set was
 *          called. Call no other clipboard function and do not block.
 */
typedef ntk_clipboard_error (NTK_CALL *ntk_clipboard_render_fn)(
    void* user_data, const char* format_name, ntk_clipboard_render_target* target);

/**
 * @brief The completion of ntk_clipboard_get_history. On the owner thread,
 *        exactly once per accepted request.
 * @param history The items, valid during the call only; NULL on failure.
 */
typedef void (NTK_CALL *ntk_clipboard_history_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error, uint32_t system_code,
    const ntk_clipboard_history* history);
/** The completion of a history request that returns no data. On the owner thread, exactly once per accepted request. */
typedef void (NTK_CALL *ntk_clipboard_completion_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error, uint32_t system_code);
/** The completion of ntk_clipboard_get_history_availability. Both flags are 0 on failure. */
typedef void (NTK_CALL *ntk_clipboard_availability_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error, uint32_t system_code,
    int32_t history_enabled, int32_t roaming_enabled);

/** How to create the session. sizeof 24. */
typedef struct ntk_clipboard_session_options {
    uint32_t                 struct_size;
    uint32_t                 reserved0;             /**< Must be 0. */
    ntk_clipboard_changed_fn on_clipboard_changed;  /**< NULL: no listener. */
    void*                    user_data;             /**< Passed to on_clipboard_changed. */
} ntk_clipboard_session_options;

/** The history handlers. sizeof 40. Any of the three may be NULL. */
typedef struct ntk_clipboard_history_handlers {
    uint32_t                         struct_size;
    uint32_t                         reserved0;     /**< Must be 0. */
    ntk_clipboard_history_changed_fn on_history_changed;
    ntk_clipboard_flag_changed_fn    on_history_enabled_changed;
    ntk_clipboard_flag_changed_fn    on_roaming_enabled_changed;
    void*                            user_data;     /**< Passed to all three. */
} ntk_clipboard_history_handlers;

/* ------------------------------------------------------------------------ */
/* Session                                                                  */
/* ------------------------------------------------------------------------ */

/**
 * @brief OP-21. Opens the session; the calling thread becomes its owner.
 * @param options NULL, or zeroed apart from struct_size, for no listener.
 * @retval NTK_CLIPBOARD_ERROR_WRONG_APARTMENT The calling thread is not an STA.
 * @retval NTK_CLIPBOARD_ERROR_NOT_SUPPORTED   A session exists (or was abandoned) on this thread, or options come from a newer version.
 * @retval NTK_CLIPBOARD_ERROR_WRONG_THREAD    A session exists (or was abandoned) on another thread.
 */
ntk_clipboard_error NTK_CALL ntk_clipboard_session_create(
    const ntk_clipboard_session_options* options, ntk_clipboard_session** out_session);

/**
 * @brief OP-23. Closes the session. Owner thread only. Free the handle after.
 * @details Requests still in flight are cancelled: their completions arrive
 *          inside this call with NTK_CLIPBOARD_ERROR_CANCELED, so no message
 *          loop is needed. Retry only on NTK_CLIPBOARD_ERROR_BUSY, once the
 *          other threads' reads and writes have finished.
 */
ntk_clipboard_error NTK_CALL ntk_clipboard_session_close(ntk_clipboard_session* session);

/**
 * @brief OP-24. Whether a close that is under way has nothing left to wait for.
 * @details 0 for a session that has not started closing, non-zero once it is
 *          closed, and non-zero for NULL: there is nothing to close. Advice
 *          for a retry loop between two close attempts; close decides.
 */
int32_t NTK_CALL ntk_clipboard_session_can_close(const ntk_clipboard_session* session);

/**
 * @brief Frees the handle. No callback of the session runs after this returns.
 * @details A session that was not closed is abandoned: its callbacks stop,
 *          but no new session can be created in this process.
 */
void NTK_CALL ntk_clipboard_session_free(ntk_clipboard_session* session);

/**
 * @brief OP-22. Replaces the history handlers. Owner thread only.
 * @param handlers NULL, or all three NULL, removes them.
 * @details On success the previous user_data is no longer used once this
 *          returns. On failure the previous handlers stay and the new
 *          user_data is not kept.
 */
ntk_clipboard_error NTK_CALL ntk_clipboard_set_history_handlers(
    ntk_clipboard_session* session, const ntk_clipboard_history_handlers* handlers);

/* ------------------------------------------------------------------------ */
/* Read and write. Each returns NTK_CLIPBOARD_ERROR_INVALID_PARAMETER for a */
/* NULL session, output or required argument, invalid UTF-8 or an unknown   */
/* flag, and NTK_CLIPBOARD_ERROR_NOT_INITIALIZED once the session is closed.*/
/* ------------------------------------------------------------------------ */

/** OP-25. text is required. */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_text(
    ntk_clipboard_session* session, const char* text, uint32_t flags);
/** OP-26. */
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_text(
    ntk_clipboard_session* session, ntk_string** out_text);
/** OP-27. fragment is required; plain_text NULL is "". */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_html(
    ntk_clipboard_session* session, const char* fragment, const char* plain_text, uint32_t flags);
/** OP-28. The fragment, as it was copied. */
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_html(
    ntk_clipboard_session* session, ntk_string** out_html);
/** OP-29. Every path is required. */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_files(
    ntk_clipboard_session* session, const char* const* paths, size_t count, uint32_t flags);
/** OP-30. */
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_files(
    ntk_clipboard_session* session, ntk_string_list** out_paths);
/** OP-31. A packed DIB (CF_DIB). dib may be NULL only when size is 0. */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_dib(
    ntk_clipboard_session* session, const uint8_t* dib, size_t size, uint32_t flags);
/** OP-32. */
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_dib(
    ntk_clipboard_session* session, ntk_bytes** out_dib);
/** OP-33. format_name is required; data may be NULL only when size is 0. */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_custom(
    ntk_clipboard_session* session, const char* format_name, const uint8_t* data, size_t size,
    uint32_t flags);
/** OP-34. format_name is required. */
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_custom(
    ntk_clipboard_session* session, const char* format_name, ntk_bytes** out_data);
/** OP-35. Writes every item at once, in the order they were added. */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_multiple(
    ntk_clipboard_session* session, const ntk_clipboard_items* items, uint32_t flags);
/** OP-36. format_name is required; *out_present is non-zero when the format is there. */
ntk_clipboard_error NTK_CALL ntk_clipboard_has_format(
    ntk_clipboard_session* session, const char* format_name, int32_t* out_present);
/** OP-37. The names of the formats on the clipboard. */
ntk_clipboard_error NTK_CALL ntk_clipboard_get_formats(
    ntk_clipboard_session* session, ntk_string_list** out_formats);
/** OP-38. The richest format this library can read, or "" when there is none. */
ntk_clipboard_error NTK_CALL ntk_clipboard_get_preferred_format(
    ntk_clipboard_session* session, ntk_string** out_format);
/** OP-39. */
ntk_clipboard_error NTK_CALL ntk_clipboard_clear(ntk_clipboard_session* session);

/* ------------------------------------------------------------------------ */
/* Multi-format builder (for ntk_clipboard_copy_multiple). format_name is   */
/* required everywhere; whether it suits the kind is checked by the copy.   */
/* ------------------------------------------------------------------------ */

ntk_clipboard_error NTK_CALL ntk_clipboard_items_create(ntk_clipboard_items** out_items);
/** Adds text under a format name, e.g. "CF_UNICODETEXT". */
ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_text(
    ntk_clipboard_items* items, const char* format_name, const char* text);
/** Adds an HTML fragment under a format name, e.g. "HTML Format". */
ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_html(
    ntk_clipboard_items* items, const char* format_name, const char* html);
/** Adds bytes under a format name. data may be NULL only when size is 0. */
ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_bytes(
    ntk_clipboard_items* items, const char* format_name, const uint8_t* data, size_t size);
/** Releases the builder. Does nothing for NULL. */
void NTK_CALL ntk_clipboard_items_free(ntk_clipboard_items* items);

/* ------------------------------------------------------------------------ */
/* Deferred rendering (owner thread)                                        */
/* ------------------------------------------------------------------------ */

/**
 * @brief OP-40. Puts formats on the clipboard whose bytes provider produces
 *        only when a program asks for them.
 * @details release is called exactly once whatever this returns: when the
 *          reservation ends (the next reservation, a write or clear, another
 *          program emptying the clipboard, recovery, a successful close, or
 *          free), and on failure before this returns. After
 *          NTK_CLIPBOARD_ERROR_PARTIAL_STATE it is kept until one of those.
 */
ntk_clipboard_error NTK_CALL ntk_clipboard_reserve_deferred(
    ntk_clipboard_session* session, const char* const* formats, size_t count,
    ntk_clipboard_render_fn provider, void* user_data, ntk_release_fn release);
/** OP-41. Clears what a failed reservation left behind. */
ntk_clipboard_error NTK_CALL ntk_clipboard_recover_deferred_state(ntk_clipboard_session* session);
/** Hands the requested format's bytes over; copied at once. Once per call of the provider. */
ntk_clipboard_error NTK_CALL ntk_clipboard_render_target_set(
    ntk_clipboard_render_target* target, const uint8_t* data, size_t size);

/* ------------------------------------------------------------------------ */
/* History requests. callback is required. The completion comes later on    */
/* the owner thread, exactly once per accepted request and never inside the */
/* call that started it; a request that was refused never completes. From  */
/* another thread the completion may come before the call returns, so match */
/* completions by user_data rather than by request id. out_request_id may   */
/* be NULL.                                                                 */
/* ------------------------------------------------------------------------ */

/** OP-42. */
ntk_clipboard_error NTK_CALL ntk_clipboard_get_history(
    ntk_clipboard_session* session, ntk_clipboard_history_fn callback, void* user_data,
    uint32_t* out_request_id);
/** OP-43. Puts a history item back on the clipboard. item_id is required. */
ntk_clipboard_error NTK_CALL ntk_clipboard_restore_history_item(
    ntk_clipboard_session* session, const char* item_id, ntk_clipboard_completion_fn callback,
    void* user_data, uint32_t* out_request_id);
/** OP-44. item_id is required. */
ntk_clipboard_error NTK_CALL ntk_clipboard_delete_history_item(
    ntk_clipboard_session* session, const char* item_id, ntk_clipboard_completion_fn callback,
    void* user_data, uint32_t* out_request_id);
/** OP-45. Deletes every item that is not pinned. */
ntk_clipboard_error NTK_CALL ntk_clipboard_clear_unpinned_history(
    ntk_clipboard_session* session, ntk_clipboard_completion_fn callback, void* user_data,
    uint32_t* out_request_id);
/** OP-46. */
ntk_clipboard_error NTK_CALL ntk_clipboard_get_history_availability(
    ntk_clipboard_session* session, ntk_clipboard_availability_fn callback, void* user_data,
    uint32_t* out_request_id);
/**
 * @brief OP-47. Cancels a request: its completion comes with
 *        NTK_CLIPBOARD_ERROR_CANCELED unless it was already on its way.
 * @retval NTK_CLIPBOARD_ERROR_INVALID_PARAMETER Unknown or already completed.
 */
ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_request(
    ntk_clipboard_session* session, uint32_t request_id);

/* ------------------------------------------------------------------------ */
/* History (argument of ntk_clipboard_history_fn). Valid during the call    */
/* only. NULL or an index out of range reads as 0 or NULL: check the count. */
/* ------------------------------------------------------------------------ */

size_t      NTK_CALL ntk_clipboard_history_count(const ntk_clipboard_history* history);
/** The id of the item at index, which restore and delete take. */
const char* NTK_CALL ntk_clipboard_history_item_id(
    const ntk_clipboard_history* history, size_t index, size_t* out_size);
/** NULL for an item that carries no text, as well as out of range. */
const char* NTK_CALL ntk_clipboard_history_item_text(
    const ntk_clipboard_history* history, size_t index, size_t* out_size);
/** How many format names the item carries. */
size_t      NTK_CALL ntk_clipboard_history_item_content_type_count(
    const ntk_clipboard_history* history, size_t index);
/** One of the item's format names, as the OS reports it. */
const char* NTK_CALL ntk_clipboard_history_item_content_type_at(
    const ntk_clipboard_history* history, size_t index, size_t type_index, size_t* out_size);
/** Milliseconds since 1970-01-01 UTC; 0 when the OS gave no time. */
int64_t     NTK_CALL ntk_clipboard_history_item_timestamp_unix_ms(
    const ntk_clipboard_history* history, size_t index);

#pragma pack(pop)

#ifdef __cplusplus
}
#endif
#endif
