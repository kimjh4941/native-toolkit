/**
 * @file Dialog.h
 * @brief The dialogs of Windows: message boxes, file pickers, folder pickers.
 * @details
 *  Part of the public C++ API added in stage 3 of the windows-architecture
 *  topic (design section 8, OP-01..OP-06). These are free functions rather
 *  than members of a class: a dialog owns no state and holds no resource
 *  between calls, so there is nothing for an object to carry.
 *
 *  Every call is modal and blocks the calling thread, so call them from the
 *  UI thread. The folder pickers initialise COM themselves as
 *  apartment-threaded and tolerate a thread that is already in another
 *  apartment (DLG-06).
 *
 *  Cancelling is not a failure of the call but it is not a value either, so it
 *  arrives as DialogError::Canceled. Whatever the OS reported stays in
 *  Failure::systemCode.
 *
 *  Do not pull this namespace in with a using-directive: Result and the
 *  request types are plain names that the feature namespace gives meaning to.
 *
 *  Keep this header ASCII only.
 */
#pragma once

#include <string>
#include <vector>

#include "NativeToolkit/BuildStamp.h"
#include "NativeToolkit/Error.h"
#include "NativeToolkit/Types.h"

namespace NativeToolkit::Dialog {

/// Which buttons a message box shows.
enum class AlertButtons {
    Ok,                ///< MB_OK
    OkCancel,          ///< MB_OKCANCEL
    YesNo,             ///< MB_YESNO
    YesNoCancel,       ///< MB_YESNOCANCEL
    RetryCancel,       ///< MB_RETRYCANCEL
    AbortRetryIgnore,  ///< MB_ABORTRETRYIGNORE
    CancelTryContinue, ///< MB_CANCELTRYCONTINUE
};

/// Which icon a message box shows.
enum class AlertIcon {
    None,        ///< No icon.
    Information, ///< MB_ICONINFORMATION
    Warning,     ///< MB_ICONWARNING
    Error,       ///< MB_ICONERROR
    Question,    ///< MB_ICONQUESTION
};

/// Which button starts out focused.
enum class AlertDefaultButton {
    First,  ///< MB_DEFBUTTON1
    Second, ///< MB_DEFBUTTON2
    Third,  ///< MB_DEFBUTTON3
    Fourth, ///< MB_DEFBUTTON4
};

/// Which button the user pressed.
enum class AlertResult {
    Ok, Cancel, Yes, No, Retry, Abort, Ignore, TryAgain, Continue,
    Close,  ///< The dialog was closed with its own control (IDCLOSE).
    Help,   ///< The help button (IDHELP), which only appears with showHelpButton.
};

/**
 * @brief What to show in a message box.
 * @details
 *  extraFlags exists because showAlertDialog of the C ABI ORs four arbitrary
 *  UINTs into MessageBoxW without validating them, so callers can pass MB_*
 *  bits the enumerations above do not name (MB_SYSTEMMODAL, MB_SETFOREGROUND,
 *  MB_RTLREADING and so on). The compatibility bridge needs to hand those
 *  through unchanged (design N-9). New code should stay with the enumerations.
 */
struct AlertRequest {
    std::wstring       title;
    std::wstring       message;
    AlertButtons       buttons        = AlertButtons::Ok;
    AlertIcon          icon           = AlertIcon::None;
    AlertDefaultButton defaultButton  = AlertDefaultButton::First;
    bool               topMost        = false;  ///< MB_TOPMOST
    bool               showHelpButton = false;  ///< MB_HELP
    uint32_t           extraFlags     = 0;      ///< Raw MB_* bits; for the bridge.
    WindowHandle       owner          = nullptr;///< The C ABI always passes none (DLG-09).
};

/**
 * @brief One entry of a file dialog's type list.
 * @details
 *  The C ABI takes the Win32 block directly: pairs of strings separated by
 *  NULs and terminated by two (DLG-12). This is that block as data. An entry
 *  with no patterns matches everything.
 */
struct FileFilter {
    std::wstring              description;  ///< What the user sees, e.g. "Text files".
    std::vector<std::wstring> patterns;     ///< e.g. { L"*.txt", L"*.log" }.
};

/**
 * @brief What to show in an open-file dialog.
 * @details
 *  With no filters the dialog offers every file, which is what the C ABI does
 *  when it is handed no filter at all (DLG-12). title has no counterpart in
 *  the C ABI, where these dialogs take no title (DLG-13).
 */
struct FileRequest {
    std::wstring            title;
    std::vector<FileFilter> filters;
    bool                    fileMustExist = true;   ///< OFN_FILEMUSTEXIST (DLG-11).
    WindowHandle            owner         = nullptr;
};

/// What to show in a save-file dialog.
struct SaveFileRequest {
    std::wstring            title;
    std::vector<FileFilter> filters;
    std::wstring            defaultExtension;       ///< Appended when the user types none.
    bool                    overwritePrompt = true; ///< OFN_OVERWRITEPROMPT (DLG-11); the C ABI always asks.
    WindowHandle            owner           = nullptr;
};

/// What to show in a folder picker. An empty title leaves the OS default (DLG-05).
struct FolderRequest {
    std::wstring title;
    WindowHandle owner = nullptr;
};

/**
 * @brief OP-01. Shows a message box and reports which button was pressed.
 * @details Pressing Cancel is a button like any other and comes back as
 *          AlertResult::Cancel, not as a failure.
 * @retval InvalidParameter A request the message box could not be built from.
 * @retval SystemError      MessageBoxW failed; systemCode holds GetLastError.
 * @retval Unknown          The message box failed without saying why.
 */
Result<AlertResult> ShowAlert(const AlertRequest& request);

/**
 * @brief OP-02. Asks for one existing file.
 * @retval InvalidParameter A request the dialog could not be built from.
 * @retval Canceled         The user dismissed the dialog.
 * @retval SystemError      The OS reported a failure; systemCode holds its value.
 * @retval Unknown          The dialog failed without saying why.
 */
Result<std::wstring> ShowOpenFile(const FileRequest& request);

/**
 * @brief OP-03. Asks for one or more existing files, in the order the dialog returned them.
 * @details Every path is a full path. The C ABI hands back the folder and the
 *          names separately and counts the folder as an entry (DLG-02); here
 *          that is already joined.
 * @retval InvalidParameter A request the dialog could not be built from.
 * @retval Canceled         The user dismissed the dialog.
 * @retval SystemError      The OS reported a failure; systemCode holds its value.
 * @retval Unknown          The dialog failed without saying why.
 */
Result<std::vector<std::wstring>> ShowOpenFiles(const FileRequest& request);

/**
 * @brief OP-04. Asks where to save a file.
 * @retval InvalidParameter A request the dialog could not be built from.
 * @retval Canceled         The user dismissed the dialog.
 * @retval SystemError      The OS reported a failure; systemCode holds its value.
 * @retval Unknown          The dialog failed without saying why.
 */
Result<std::wstring> ShowSaveFile(const SaveFileRequest& request);

/**
 * @brief OP-05. Asks for one folder.
 * @retval InvalidParameter A request the dialog could not be built from.
 * @retval Canceled         The user dismissed the dialog.
 * @retval SystemError      The OS reported a failure; systemCode holds its value.
 * @retval Unknown          The dialog failed without saying why.
 */
Result<std::wstring> ShowPickFolder(const FolderRequest& request);

/**
 * @brief OP-06. Asks for one or more folders.
 * @retval InvalidParameter A request the dialog could not be built from.
 * @retval Canceled         The user dismissed the dialog.
 * @retval SystemError      The OS reported a failure; systemCode holds its value.
 * @retval Unknown          The dialog failed without saying why.
 */
Result<std::vector<std::wstring>> ShowPickFolders(const FolderRequest& request);

}  // namespace NativeToolkit::Dialog
