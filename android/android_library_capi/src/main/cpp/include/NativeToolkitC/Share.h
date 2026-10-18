/**
 * @file Share.h
 * @brief Sharing through the Android Sharesheet, Chooser Actions, Direct Share targets and the
 *        selection events.
 *
 * Rules for the whole C ABI (C ABI design part 1, chapter 1): every function may be called from any
 * thread and never waits for the main thread; completions, events and accepted releases arrive on
 * the main thread; strings are NUL-terminated UTF-8; this header is C99, includes only <stddef.h>
 * and <stdint.h>, and is ASCII only. The declarations are those of Appendix A of the C ABI design
 * part 2, which scripts/check_c_abi_contract_android.py compares with this file.
 */
#ifndef NATIVETOOLKITC_SHARE_H
#define NATIVETOOLKITC_SHARE_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_share_error;
enum {
    NTK_SHARE_ERROR_NONE = 0,
    NTK_SHARE_ERROR_INVALID_PARAMETER = 1,
    NTK_SHARE_ERROR_NOT_INITIALIZED = 2,
    NTK_SHARE_ERROR_NOT_SUPPORTED = 3,
    NTK_SHARE_ERROR_UNKNOWN = 4,
    NTK_SHARE_ERROR_OUT_OF_MEMORY = 5,
    NTK_SHARE_ERROR_NOT_FOREGROUND = 6,
    NTK_SHARE_ERROR_EMPTY_CONTENT = 7,
    NTK_SHARE_ERROR_NO_SHARE_TARGET = 8,
    NTK_SHARE_ERROR_FILE_NOT_FOUND = 9,
    NTK_SHARE_ERROR_ILLEGAL_FILE_ACCESS = 10,
    NTK_SHARE_ERROR_INVALID_MIME_TYPE = 11,
    NTK_SHARE_ERROR_DIRECT_SHARE_REGISTRATION_FAILED = 12,
    NTK_SHARE_ERROR_EMPTY_ID_LIST = 13,
    NTK_SHARE_ERROR_EMPTY_FILE_LIST = 14,
    NTK_SHARE_ERROR_INVALID_ICON = 15,
    NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION = 16
};

/** An event listener registration. */
typedef struct ntk_share_listener ntk_share_listener;

/** Called once on the main thread: the Sharesheet opened (NONE), or why it did not. */
typedef void (NTK_CALL *ntk_share_done_fn)(void* user_data, ntk_share_error error, uint32_t system_code);
/** A custom action was pressed. action_id is owned by the receiver. */
typedef void (NTK_CALL *ntk_share_chooser_action_fn)(void* user_data, ntk_string* action_id);
/** An app was chosen in the Sharesheet of request_id. package_name is NULL when unknown; owned by the receiver. */
typedef void (NTK_CALL *ntk_share_selection_fn)(void* user_data, uint64_t request_id, ntk_string* package_name);

#pragma pack(push, 8)
typedef struct ntk_share_text_content {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* text;
    const char* title;                            /**< NULL: none. */
    const char* subject;                          /**< NULL: none. */
    const char* mime_type;                        /**< NULL: "text/plain". */
    const char* preview_title;                    /**< NULL: none. */
    const char* preview_thumbnail_path;           /**< NULL: none. */
} ntk_share_text_content;

/** A custom Sharesheet action (API 34 and later). No struct_size: this set of fields is fixed. */
typedef struct ntk_share_chooser_action {
    const char*    id;
    const char*    label;
    const uint8_t* icon;                          /**< An image (PNG, JPEG, WebP). */
    size_t         icon_size;
} ntk_share_chooser_action;

typedef struct ntk_share_direct_target {
    uint32_t       struct_size;
    uint32_t       reserved0;
    const char*    id;
    const char*    label;
    const char*    category;                      /**< NULL: "android.shortcut.conversation". */
    const uint8_t* icon;
    size_t         icon_size;
} ntk_share_direct_target;
#pragma pack(pop)

/* Opening the Sharesheet is asynchronous and needs the app in the foreground. */
ntk_share_error NTK_CALL ntk_share_text(const ntk_share_text_content* content,
                                        const ntk_share_chooser_action* actions, size_t action_count,
                                        ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
ntk_share_error NTK_CALL ntk_share_image(const char* path, const char* mime_type,
                                         ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
ntk_share_error NTK_CALL ntk_share_images(const char* const* paths, size_t count,
                                          ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
ntk_share_error NTK_CALL ntk_share_file(const char* path,
                                        ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
ntk_share_error NTK_CALL ntk_share_files(const char* const* paths, size_t count,
                                         ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
/* Direct Share targets are synchronous. */
ntk_share_error NTK_CALL ntk_share_register_direct_target(const ntk_share_direct_target* target);
ntk_share_error NTK_CALL ntk_share_remove_direct_targets(const char* const* ids, size_t count);
/** Opens the Sharesheet; the chosen app arrives as a selection event with this request ID.
    out_request_id may be NULL, but then the selection cannot be matched. */
ntk_share_error NTK_CALL ntk_share_text_for_selection(const ntk_share_text_content* content,
                                                      ntk_share_done_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);
/** Never waits; the cancel is posted to the main thread. Does nothing unless request_id is the
    waiting request. */
ntk_share_error NTK_CALL ntk_share_cancel_selection(uint64_t request_id);
ntk_share_error NTK_CALL ntk_share_add_chooser_action_listener(ntk_share_chooser_action_fn callback, void* user_data,
                                                               ntk_release_fn release,
                                                               ntk_share_listener** out_listener);
ntk_share_error NTK_CALL ntk_share_add_selection_listener(ntk_share_selection_fn callback, void* user_data,
                                                          ntk_release_fn release, ntk_share_listener** out_listener);
/** The handle is invalid afterwards. Does nothing for NULL. */
void NTK_CALL ntk_share_listener_remove(ntk_share_listener* listener);

#ifdef __cplusplus
}
#endif
#endif
