/**
 * @file Dialog.h
 * @brief Message boxes and the file and folder pickers (OP-01..OP-06).
 *
 * Every function here is modal: it blocks the calling thread until the user
 * closes the dialog, so call it from a UI thread. The folder pickers
 * initialise COM on the calling thread as an STA if nothing has yet.
 *
 * A NULL request means every field at its default; so does a request filled
 * with zeros apart from struct_size (design E-9).
 */
#ifndef NATIVETOOLKITC_DIALOG_H
#define NATIVETOOLKITC_DIALOG_H

#include "NativeToolkitC/Common.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

/** The result of every dialog function. The raw OS value of a failure is ntk_last_system_code(). */
typedef int32_t ntk_dialog_error;
enum {
    NTK_DIALOG_ERROR_NONE = 0,
    NTK_DIALOG_ERROR_INVALID_PARAMETER = 1,
    NTK_DIALOG_ERROR_CANCELED = 2,
    NTK_DIALOG_ERROR_BUFFER_TOO_SMALL = 3,   /* reserved, never returned */
    NTK_DIALOG_ERROR_SYSTEM_ERROR = 4,
    NTK_DIALOG_ERROR_UNKNOWN = 5
};

typedef int32_t ntk_dialog_alert_buttons;
enum {
    NTK_DIALOG_ALERT_BUTTONS_OK = 0,
    NTK_DIALOG_ALERT_BUTTONS_OK_CANCEL = 1,
    NTK_DIALOG_ALERT_BUTTONS_YES_NO = 2,
    NTK_DIALOG_ALERT_BUTTONS_YES_NO_CANCEL = 3,
    NTK_DIALOG_ALERT_BUTTONS_RETRY_CANCEL = 4,
    NTK_DIALOG_ALERT_BUTTONS_ABORT_RETRY_IGNORE = 5,
    NTK_DIALOG_ALERT_BUTTONS_CANCEL_TRY_CONTINUE = 6
};

typedef int32_t ntk_dialog_alert_icon;
enum {
    NTK_DIALOG_ALERT_ICON_NONE = 0,
    NTK_DIALOG_ALERT_ICON_INFORMATION = 1,
    NTK_DIALOG_ALERT_ICON_WARNING = 2,
    NTK_DIALOG_ALERT_ICON_ERROR = 3,
    NTK_DIALOG_ALERT_ICON_QUESTION = 4
};

typedef int32_t ntk_dialog_alert_default_button;
enum {
    NTK_DIALOG_ALERT_DEFAULT_BUTTON_FIRST = 0,
    NTK_DIALOG_ALERT_DEFAULT_BUTTON_SECOND = 1,
    NTK_DIALOG_ALERT_DEFAULT_BUTTON_THIRD = 2,
    NTK_DIALOG_ALERT_DEFAULT_BUTTON_FOURTH = 3
};

typedef int32_t ntk_dialog_alert_result;
enum {
    NTK_DIALOG_ALERT_RESULT_OK = 0,
    NTK_DIALOG_ALERT_RESULT_CANCEL = 1,
    NTK_DIALOG_ALERT_RESULT_YES = 2,
    NTK_DIALOG_ALERT_RESULT_NO = 3,
    NTK_DIALOG_ALERT_RESULT_RETRY = 4,
    NTK_DIALOG_ALERT_RESULT_ABORT = 5,
    NTK_DIALOG_ALERT_RESULT_IGNORE = 6,
    NTK_DIALOG_ALERT_RESULT_TRY_AGAIN = 7,
    NTK_DIALOG_ALERT_RESULT_CONTINUE = 8,
    NTK_DIALOG_ALERT_RESULT_CLOSE = 9,
    NTK_DIALOG_ALERT_RESULT_HELP = 10
};

/**
 * One entry of a file dialog's type list. Frozen: it has no struct_size and
 * will never gain a member.
 */
typedef struct ntk_dialog_filter {
    const char* name;       /**< What the user sees, e.g. "Text files". NULL is "". */
    const char* patterns;   /**< Patterns separated by ';', e.g. "*.txt;*.log". Required. */
} ntk_dialog_filter;

/** What to show in a message box. sizeof 56. */
typedef struct ntk_dialog_alert_request {
    uint32_t    struct_size;
    uint32_t    reserved0;                     /**< Must be 0. */
    const char* title;                         /**< NULL is "". */
    const char* message;                       /**< NULL is "". */
    ntk_dialog_alert_buttons        buttons;
    ntk_dialog_alert_icon           icon;
    ntk_dialog_alert_default_button default_button;
    int32_t     top_most;                      /**< Non-zero: MB_TOPMOST. */
    int32_t     show_help_button;              /**< Non-zero: MB_HELP. */
    uint32_t    reserved1;                     /**< Must be 0. */
    void*       owner;                         /**< HWND of the owner window, or NULL. */
} ntk_dialog_alert_request;

/** What to show in an open-file dialog. sizeof 32. */
typedef struct ntk_dialog_file_request {
    uint32_t    struct_size;
    uint32_t    reserved0;                     /**< Must be 0. */
    const char* title;                         /**< NULL or "": the system title. */
    int32_t     allow_missing_file;            /**< Non-zero: the picked file need not exist. */
    uint32_t    reserved1;                     /**< Must be 0. */
    void*       owner;                         /**< HWND of the owner window, or NULL. */
} ntk_dialog_file_request;

/** What to show in a save-file dialog. sizeof 40. */
typedef struct ntk_dialog_save_file_request {
    uint32_t    struct_size;
    uint32_t    reserved0;                     /**< Must be 0. */
    const char* title;                         /**< NULL or "": the system title. */
    const char* default_extension;             /**< Appended when the user types none. NULL or "": none. */
    int32_t     skip_overwrite_prompt;         /**< Non-zero: do not ask before an existing file is picked. */
    uint32_t    reserved1;                     /**< Must be 0. */
    void*       owner;                         /**< HWND of the owner window, or NULL. */
} ntk_dialog_save_file_request;

/** What to show in a folder picker. sizeof 24. */
typedef struct ntk_dialog_folder_request {
    uint32_t    struct_size;
    uint32_t    reserved0;                     /**< Must be 0. */
    const char* title;                         /**< NULL or "": the system title. */
    void*       owner;                         /**< HWND of the owner window, or NULL. */
} ntk_dialog_folder_request;

/**
 * @brief OP-01. Shows a message box and reports which button was pressed.
 * @details Cancel is a button like any other: it comes back as
 *          NTK_DIALOG_ALERT_RESULT_CANCEL with NTK_DIALOG_ERROR_NONE.
 * @retval NTK_DIALOG_ERROR_INVALID_PARAMETER out_result is NULL, or the request is malformed.
 * @retval NTK_DIALOG_ERROR_SYSTEM_ERROR      MessageBoxW failed; see ntk_last_system_code().
 * @retval NTK_DIALOG_ERROR_UNKNOWN           Anything else.
 */
ntk_dialog_error NTK_CALL ntk_dialog_show_alert(
    const ntk_dialog_alert_request* request, ntk_dialog_alert_result* out_result);

/**
 * @brief OP-02. Asks for one existing file. The path, up to 1023 characters, is returned in *out_path.
 * @param filters      The type list, or NULL with filter_count 0 for every file.
 * @param out_path     Receives a handle to free with ntk_string_free; NULL on failure.
 * @retval NTK_DIALOG_ERROR_INVALID_PARAMETER A NULL out_path, a malformed request or filter.
 * @retval NTK_DIALOG_ERROR_CANCELED          The user dismissed the dialog.
 * @retval NTK_DIALOG_ERROR_SYSTEM_ERROR      The OS reported a failure; see ntk_last_system_code().
 * @retval NTK_DIALOG_ERROR_UNKNOWN           Anything else.
 */
ntk_dialog_error NTK_CALL ntk_dialog_show_open_file(
    const ntk_dialog_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string** out_path);

/** @brief OP-03. Asks for one or more existing files; every entry is a full path. Errors as ntk_dialog_show_open_file. */
ntk_dialog_error NTK_CALL ntk_dialog_show_open_files(
    const ntk_dialog_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string_list** out_paths);

/** @brief OP-04. Asks where to save. The file is not created. Errors as ntk_dialog_show_open_file. */
ntk_dialog_error NTK_CALL ntk_dialog_show_save_file(
    const ntk_dialog_save_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string** out_path);

/** @brief OP-05. Asks for one folder. Errors as ntk_dialog_show_open_file. */
ntk_dialog_error NTK_CALL ntk_dialog_show_pick_folder(
    const ntk_dialog_folder_request* request, ntk_string** out_path);

/** @brief OP-06. Asks for one or more folders; every entry is a full path. Errors as ntk_dialog_show_open_file. */
ntk_dialog_error NTK_CALL ntk_dialog_show_pick_folders(
    const ntk_dialog_folder_request* request, ntk_string_list** out_paths);

#pragma pack(pop)

#ifdef __cplusplus
}
#endif
#endif
