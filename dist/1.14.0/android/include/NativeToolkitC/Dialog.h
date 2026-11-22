/**
 * @file Dialog.h
 * @brief Dialogs. Every dialog is asynchronous: the result arrives in a completion callback on the
 *        main thread.
 *
 * Rules for the whole C ABI (C ABI design part 1, chapter 1): every function may be called from any
 * thread and never waits for the main thread; completions, events and accepted releases arrive on
 * the main thread; strings are NUL-terminated UTF-8; this header is C99, includes only <stddef.h>
 * and <stdint.h>, and is ASCII only. The declarations are those of Appendix A of the C ABI design
 * part 2, which scripts/check_c_abi_contract_android.py compares with this file.
 */
#ifndef NATIVETOOLKITC_DIALOG_H
#define NATIVETOOLKITC_DIALOG_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_dialog_error;
enum {
    NTK_DIALOG_ERROR_NONE = 0,
    NTK_DIALOG_ERROR_INVALID_PARAMETER = 1,
    NTK_DIALOG_ERROR_NOT_INITIALIZED = 2,
    NTK_DIALOG_ERROR_NOT_SUPPORTED = 3,
    NTK_DIALOG_ERROR_UNKNOWN = 4,
    NTK_DIALOG_ERROR_OUT_OF_MEMORY = 5,
    NTK_DIALOG_ERROR_CANCELED = 6,
    NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM = 7,
    NTK_DIALOG_ERROR_NOT_FOREGROUND = 8,
    NTK_DIALOG_ERROR_HOST_START_FAILED = 9,
    NTK_DIALOG_ERROR_SHOW_FAILED = 10
};

typedef int32_t ntk_dialog_answer;
enum {
    NTK_DIALOG_ANSWER_BUTTON = 0,
    NTK_DIALOG_ANSWER_DISMISSED = 1
};

typedef int32_t ntk_dialog_button;
enum {
    NTK_DIALOG_BUTTON_POSITIVE = 0,
    NTK_DIALOG_BUTTON_NEGATIVE = 1
};

/** The answer of a dialog. Owned by the receiver: free it with ntk_dialog_result_free. */
typedef struct ntk_dialog_result ntk_dialog_result;

/** Called once on the main thread. result is NULL unless error is NTK_DIALOG_ERROR_NONE. */
typedef void (NTK_CALL *ntk_dialog_result_fn)(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                              uint32_t system_code, ntk_dialog_result* result);

#pragma pack(push, 8)
/* NULL texts take the library's defaults; a zero-filled struct is the default dialog. */
typedef struct ntk_dialog_alert_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* button_text;                      /**< NULL: "OK". */
    int32_t     not_cancelable;                   /**< Nonzero: Back does not close it. */
    int32_t     not_cancelable_on_touch_outside;  /**< Nonzero: an outside tap does not close it. */
} ntk_dialog_alert_request;

typedef struct ntk_dialog_confirm_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* negative_text;                    /**< NULL: "No". */
    const char* positive_text;                    /**< NULL: "Yes". */
    int32_t     not_cancelable;
    int32_t     not_cancelable_on_touch_outside;
} ntk_dialog_confirm_request;

typedef struct ntk_dialog_single_choice_request {
    uint32_t           struct_size;
    uint32_t           reserved0;
    const char*        title;
    const char* const* items;
    size_t             item_count;
    int32_t            checked_index;             /**< -1: none checked. */
    int32_t            not_cancelable;
    int32_t            not_cancelable_on_touch_outside;
    uint32_t           reserved1;
    const char*        negative_text;             /**< NULL: "Cancel". */
    const char*        positive_text;             /**< NULL: "OK". */
} ntk_dialog_single_choice_request;

typedef struct ntk_dialog_multi_choice_request {
    uint32_t           struct_size;
    uint32_t           reserved0;
    const char*        title;
    const char* const* items;
    size_t             item_count;
    const int32_t*     checked;                   /**< NULL: none checked; else item_count values. */
    const char*        negative_text;             /**< NULL: "Cancel". */
    const char*        positive_text;             /**< NULL: "OK". */
    int32_t            not_cancelable;
    int32_t            not_cancelable_on_touch_outside;
} ntk_dialog_multi_choice_request;

typedef struct ntk_dialog_text_input_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* hint;
    const char* negative_text;                    /**< NULL: "Cancel". */
    const char* positive_text;                    /**< NULL: "OK". */
    int32_t     enable_positive_when_empty;
    int32_t     not_cancelable;
    int32_t     not_cancelable_on_touch_outside;
    uint32_t    reserved1;
} ntk_dialog_text_input_request;

typedef struct ntk_dialog_login_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* username_hint;                    /**< NULL: "Username". */
    const char* password_hint;                    /**< NULL: "Password". */
    const char* negative_text;                    /**< NULL: "Cancel". */
    const char* positive_text;                    /**< NULL: "Login". */
    int32_t     enable_positive_when_empty;
    int32_t     not_cancelable;
    int32_t     not_cancelable_on_touch_outside;
    uint32_t    reserved1;
} ntk_dialog_login_request;
#pragma pack(pop)

/* Asynchronous (AC-7): NONE means accepted; the answer comes through callback on the main thread.
   out_request_id may be NULL. */
ntk_dialog_error NTK_CALL ntk_dialog_show_alert_async(const ntk_dialog_alert_request* request,
                                                      ntk_dialog_result_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_confirm_async(const ntk_dialog_confirm_request* request,
                                                        ntk_dialog_result_fn callback, void* user_data,
                                                        ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_single_choice_async(const ntk_dialog_single_choice_request* request,
                                                              ntk_dialog_result_fn callback, void* user_data,
                                                              ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_multi_choice_async(const ntk_dialog_multi_choice_request* request,
                                                             ntk_dialog_result_fn callback, void* user_data,
                                                             ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_text_input_async(const ntk_dialog_text_input_request* request,
                                                           ntk_dialog_result_fn callback, void* user_data,
                                                           ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_login_async(const ntk_dialog_login_request* request,
                                                      ntk_dialog_result_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);
/** Never waits. Does nothing after completion or for an unknown ID. */
ntk_dialog_error NTK_CALL ntk_dialog_cancel(uint64_t request_id);

/* Readers: pointers stay valid until the result is freed. out_size may be NULL. */
ntk_dialog_answer NTK_CALL ntk_dialog_result_answer(const ntk_dialog_result* result);
ntk_dialog_button NTK_CALL ntk_dialog_result_button(const ntk_dialog_result* result);
const char*       NTK_CALL ntk_dialog_result_button_text(const ntk_dialog_result* result, size_t* out_size);
/** Single choice: the checked index, or -1. */
int32_t           NTK_CALL ntk_dialog_result_checked_index(const ntk_dialog_result* result);
/** Multi choice: the number of items and whether each is checked. */
size_t            NTK_CALL ntk_dialog_result_checked_count(const ntk_dialog_result* result);
int32_t           NTK_CALL ntk_dialog_result_checked_at(const ntk_dialog_result* result, size_t index);
/** Text input: the text. */
const char*       NTK_CALL ntk_dialog_result_text(const ntk_dialog_result* result, size_t* out_size);
/** Login: the username and the password. */
const char*       NTK_CALL ntk_dialog_result_username(const ntk_dialog_result* result, size_t* out_size);
const char*       NTK_CALL ntk_dialog_result_password(const ntk_dialog_result* result, size_t* out_size);
void              NTK_CALL ntk_dialog_result_free(ntk_dialog_result* result);

#ifdef __cplusplus
}
#endif
#endif
