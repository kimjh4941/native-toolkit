# Dialog

Language:

- English (this page)
- 日本語: [dialog.ja.md](dialog.ja.md)
- 한국어: [dialog.ko.md](dialog.ko.md)

← [Back to manual top](index.md)

---

## Table of Contents

- [Android](#android)
  - [AndroidDialogFragment](#androiddialogfragment)
- [iOS](#ios)
  - [iOSDialogManager](#iosdialogmanager)
- [Windows](#windows)
  - [NativeToolkit::Dialog](#nativetoolkitdialog)
    - [ShowAlert - Basic dialog](#showalert---basic-dialog-1)
    - [ShowOpenFile - File picker dialog](#showopenfile---file-picker-dialog)
    - [ShowOpenFiles - Multi-file picker dialog](#showopenfiles---multi-file-picker-dialog)
    - [ShowPickFolder - Folder picker dialog](#showpickfolder---folder-picker-dialog)
    - [ShowPickFolders - Multi-folder picker dialog](#showpickfolders---multi-folder-picker-dialog)
    - [ShowSaveFile - Save file dialog](#showsavefile---save-file-dialog)
  - [C ABI](#c-abi)
- [macOS](#macos)
  - [MacDialogManager](#macdialogmanager)

---

## Android

### AndroidDialogFragment

#### Basic dialog

- Displays a dialog.

```kotlin
import android.library.dialog.AndroidDialogFragment

// Set the title. This field is required.
val title = "Hello from Android";
// Set the message. This field is required.
val message = "This is a native Android dialog!";
// Set the button text. If not set, "OK" is used.
val buttonText = "OK";
// Set whether tapping outside the dialog can cancel it. If not set, true is used.
val cancelableOnTouchOutside = false;
// Set whether the dialog can be canceled with the back key, etc. If not set, true is used.
val cancelable = false;

AndroidDialogFragment.newInstance(
    title = title,
    message = message,
    buttonText = buttonText,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // Set a listener to receive dialog results.
    setDialogListener(object : AndroidDialogFragment.DialogListener {
        // dialog: dialog instance
        // buttonText: text of the pressed button. Returns null on error.
        // isSuccessful: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns null on success.
        override fun onDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // First argument: FragmentManager
    // Second argument: dialog tag name
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowDialog.png" alt="Example_AndroidDialogFragment_ShowDialog" width="400" />
</p>

#### Confirmation dialog

- Displays a dialog.

```kotlin
import android.library.dialog.AndroidDialogFragment

// Set the title. This field is required.
val title = "Confirmation"
// Set the message. This field is required.
val message = "Do you want to proceed with this action?"
// Set the negative button text. If not set, "No" is used.
val negativeButtonText = "No"
// Set the positive button text. If not set, "Yes" is used.
val positiveButtonText = "Yes"
// Set whether tapping outside the dialog can cancel it. If not set, true is used.
val cancelableOnTouchOutside = false
// Set whether the dialog can be canceled with the back key, etc. If not set, true is used.
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    message = message,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // Set a listener to receive confirmation dialog results.
    setConfirmDialogListener(object : AndroidDialogFragment.ConfirmDialogListener {
        // dialog: dialog instance
        // buttonText: text of the pressed button. Returns null on error.
        // isSuccessful: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns null on success.
        override fun onConfirmDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onConfirmDialog - buttonText: $buttonText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // First argument: FragmentManager
    // Second argument: dialog tag name
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowConfirmDialog.png" alt="Example_AndroidDialogFragment_ShowConfirmDialog" width="400" />
</p>

#### Single-choice dialog

- Displays a dialog.

```kotlin
import android.library.dialog.AndroidDialogFragment

// Set the title. This field is required.
val title = "Please select one"
// Set choices. This field is required.
val singleChoiceItems = arrayOf("Option 1", "Option 2", "Option 3")
// Set the default selected item index. If not set, 0 is used.
val checkedItem = 0
// Set the negative button text. If not set, "Cancel" is used.
val negativeButtonText = "Cancel"
// Set the positive button text. If not set, "OK" is used.
val positiveButtonText = "OK"
// Set whether tapping outside the dialog can cancel it. If not set, true is used.
val cancelableOnTouchOutside = false
// Set whether the dialog can be canceled with the back key, etc. If not set, true is used.
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    singleChoiceItems = singleChoiceItems,
    checkedItem = checkedItem,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // Set a listener to receive single-choice dialog results.
    setSingleChoiceItemDialogListener(object : AndroidDialogFragment.SingleChoiceItemDialogListener {
        // dialog: dialog instance
        // buttonText: text of the pressed button. Returns null on error.
        // checkedItem: selected item index. Returns null on error.
        // isSuccessful: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns null on success.
        override fun onSingleChoiceItemDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            checkedItem: Int?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onSingleChoiceItemDialog - buttonText: $buttonText, checkedItem: $checkedItem, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // First argument: FragmentManager
    // Second argument: dialog tag name
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowSingleChoiceItemDialog.png" alt="Example_AndroidDialogFragment_ShowSingleChoiceItemDialog" width="400" />
</p>

#### Multi-choice dialog

- Displays a dialog.

```kotlin
import android.library.dialog.AndroidDialogFragment

// Set the title. This field is required.
val title = "Multiple Selection"
// Set choices. This field is required.
val multiChoiceItems = arrayOf("Option 1", "Option 2", "Option 3", "Option 4")
// Set the default checked states. If not set, all false is used.
val checkedItems = booleanArrayOf(false, true, false, true)
// Set the negative button text. If not set, "Cancel" is used.
val negativeButtonText = "Cancel"
// Set the positive button text. If not set, "OK" is used.
val positiveButtonText = "OK"
// Set whether tapping outside the dialog can cancel it. If not set, true is used.
val cancelableOnTouchOutside = false
// Set whether the dialog can be canceled with the back key, etc. If not set, true is used.
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    multiChoiceItems = multiChoiceItems,
    checkedItems = checkedItems,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // Set a listener to receive multi-choice dialog results.
    setMultiChoiceItemDialogListener(object : AndroidDialogFragment.MultiChoiceItemDialogListener {
        // dialog: dialog instance
        // buttonText: text of the pressed button. Returns null on error.
        // checkedItems: checked states of selected items. true for selected, false for unselected. Returns null on error.
        // isSuccessful: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns null on success.
        override fun onMultiChoiceItemDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            checkedItems: BooleanArray?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onMultiChoiceItemDialog - buttonText: $buttonText, checkedItems: ${checkedItems.contentToString()}, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // First argument: FragmentManager
    // Second argument: dialog tag name
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowMultiChoiceItemDialog.png" alt="Example_AndroidDialogFragment_ShowMultiChoiceItemDialog" width="400" />
</p>

#### Text input dialog

- Displays a dialog.

```kotlin
import android.library.dialog.AndroidDialogFragment

// Set the title. This field is required.
val title = "Text Input"
// Set the message. This field is required.
val message = "Please enter your name"
// Set the placeholder. If not set, an empty string is used.
val hint = "Enter here..."
// Set the negative button text. If not set, "Cancel" is used.
val negativeButtonText = "Cancel"
// Set the positive button text. If not set, "OK" is used.
val positiveButtonText = "OK"
// Set whether the positive button is enabled when input is empty. If not set, false is used.
val enablePositiveButtonWhenEmpty = false
// Set whether tapping outside the dialog can cancel it. If not set, true is used.
val cancelableOnTouchOutside = false
// Set whether the dialog can be canceled with the back key, etc. If not set, true is used.
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    message = message,
    hint = hint,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    enablePositiveButtonWhenEmpty = enablePositiveButtonWhenEmpty,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // Set a listener to receive text input dialog results.
    setTextInputDialogListener(object : AndroidDialogFragment.TextInputDialogListener {
        // dialog: dialog instance
        // buttonText: text of the pressed button. Returns null on error.
        // inputText: entered text. Returns null on error.
        // isSuccessful: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns null on success.
        override fun onTextInputDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            inputText: String?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onTextInputDialog - buttonText: $buttonText, inputText: $inputText, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    // First argument: FragmentManager
    // Second argument: dialog tag name
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowTextInputDialog.png" alt="Example_AndroidDialogFragment_ShowTextInputDialog" width="400" />
</p>

#### Login dialog

- Displays a dialog.

```kotlin
import android.library.dialog.AndroidDialogFragment

// Set the title. This field is required.
val title = "Login"
// Set the message. This field is required.
val message = "Please enter your credentials"
// Set username placeholder. If not set, "Username" is used.
val usernameHint = "Username"
// Set password placeholder. If not set, "Password" is used.
val passwordHint = "Password"
// Set the negative button text. If not set, "Cancel" is used.
val negativeButtonText = "Cancel"
// Set the positive button text. If not set, "Login" is used.
val positiveButtonText = "Login"
// Set whether the positive button is enabled when input is empty. If not set, false is used.
val enablePositiveButtonWhenEmpty = false
// Set whether tapping outside the dialog can cancel it. If not set, true is used.
val cancelableOnTouchOutside = false
// Set whether the dialog can be canceled with the back key, etc. If not set, true is used.
val cancelable = false

AndroidDialogFragment.newInstance(
    title = title,
    message = message,
    usernameHint = usernameHint,
    passwordHint = passwordHint,
    negativeButtonText = negativeButtonText,
    positiveButtonText = positiveButtonText,
    enablePositiveButtonWhenEmpty = enablePositiveButtonWhenEmpty,
    cancelableOnTouchOutside = cancelableOnTouchOutside,
    cancelable = cancelable
).apply {
    // Set a listener to receive login dialog results.
    setLoginDialogListener(object : AndroidDialogFragment.LoginDialogListener {
        // dialog: dialog instance
        // buttonText: text of the pressed button. Returns null on error.
        // username: entered username. Returns null on error.
        // password: entered password. Returns null on error.
        // isSuccessful: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns null on success.
        override fun onLoginDialog(
            dialog: AndroidDialogFragment,
            buttonText: String?,
            username: String?,
            password: String?,
            isSuccessful: Boolean,
            errorMessage: String?) {
                Log.d(TAG, "onLoginDialog - buttonText: $buttonText, username: $username, password: $password, isSuccessful: $isSuccessful, errorMessage: $errorMessage")
        }
    })
    show(supportFragmentManager, "AndroidDialogFragment")
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowLoginDialog.png" alt="Example_AndroidDialogFragment_ShowLoginDialog" width="400" />
</p>

---

## iOS

### iOSDialogManager

#### ShowAlert - Basic dialog

- Displays a dialog.

```swift
IosDialogManager.shared.showAlert(
    // Set the title.
    title: "Hello from iOS",
    // Set the message.
    message: "This is a native iOS dialog!",
    // Set the button text. If not set, "OK" is used.
    buttonText: "OK",
    // Set event for button tap.
    onButton: { buttonText, isSuccess, errorMessage in
        // buttonText: text of the pressed button. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for dialog completion.
    completion: { isSuccess, errorMessage in
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowAlert.png" alt="Example_IosDialogManager_ShowAlert" width="400" />
</p>

#### ShowConfirmDialog - Confirmation dialog

- Displays a dialog.

```swift
IosDialogManager.shared.showConfirmDialog(
    // Set the title.
    title: "Confirm Action",
    // Set the message.
    message: "Are you sure you want to proceed?",
    // Set confirmation button text. If not set, "OK" is used.
    confirmTitle: "Yes",
    // Set cancel button text. If not set, "Cancel" is used.
    cancelTitle: "No",
    // Set event for confirmation button tap.
    onConfirm: { confirmButtonText, isSuccess, errorMessage in
        // confirmButtonText: text of the pressed button. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for cancel button tap.
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText: text of the pressed button. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for dialog completion.
    completion: { isSuccess, errorMessage in
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowConfirmDialog.png" alt="Example_IosDialogManager_ShowConfirmDialog" width="400" />
</p>

#### ShowDestructiveDialog - Destructive dialog

- Displays a dialog.

```swift
IosDialogManager.shared.showDestructiveDialog(
    // Set the title.
    title: "Delete File",
    // Set the message.
    message: "This action cannot be undone. Are you sure?",
    // Set destructive action button text. If not set, "Delete" is used.
    destructiveTitle: "Delete",
    // Set cancel button text. If not set, "Cancel" is used.
    cancelTitle: "Cancel",
    // Set event for destructive action button tap.
    onDestructive: { destructiveButtonText, isSuccess, errorMessage in
        // destructiveButtonText: text of the pressed button. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for cancel button tap.
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText: text of the pressed button. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for dialog completion.
    completion: { isSuccess, errorMessage in
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowDestructiveDialog.png" alt="Example_IosDialogManager_ShowDestructiveDialog" width="400" />
</p>

#### ShowActionSheet - Action sheet

- Displays an action sheet.

```swift
if let rootVC = IosDialogManager.shared.getRootViewController() {
    IosDialogManager.shared.showActionSheet(
        // Set the title.
        title: "Please select",
        // Set the message.
        message: "Please choose an option",
        // Set options. This field is required.
        options: ["Camera", "Photo Library", "Documents"],
        // Set cancel button text. If not set, "Cancel" is used.
        cancelTitle: "Cancel",
        // Set the source view for presenting the action sheet. This field is required.
        sourceView: rootVC.view,
        // Set the source rectangle of the presenting view.
        sourceRect: nil,
        // Set whether to animate presentation. If not set, true is used.
        animated: true,
        // Set event for action button tap.
        onAction: { action, isSuccess, errorMessage in
            // action: selected item. Returns nil on error.
            // isSuccess: success flag for dialog display. Returns true on success.
            // errorMessage: error detail if an error occurs. Returns nil on success.
        },
        completion: { isSuccess, errorMessage in
            // isSuccess: success flag for dialog display. Returns true on success.
            // errorMessage: error detail if an error occurs. Returns nil on success.
        }
    )
}
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowActionSheet.png" alt="Example_IosDialogManager_ShowActionSheet" width="400" />
</p>

#### ShowTextInputDialog - Text input dialog

- Displays a dialog.

```swift
IosDialogManager.shared.showTextInputDialog(
    // Set the title.
    title: "Enter Name",
    // Set the message.
    message: "Please enter your name",
    // Set the placeholder.
    placeholder: "Your name here",
    // Set confirmation button text. If not set, "OK" is used.
    confirmTitle: "OK",
    // Set cancel button text. If not set, "Cancel" is used.
    cancelTitle: "Cancel",
    // Set whether confirm button is enabled when input is empty. If not set, true is used.
    enableConfirmWhenEmpty: false,
    // Set event for confirm button tap.
    onConfirm: { confirmButtonText, inputText, isSuccess, errorMessage in
        // confirmButtonText: text of the pressed button. Returns nil on error.
        // inputText: entered text. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for cancel button tap.
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText: text of the pressed button. Returns nil on error.
        // inputText: entered text. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for dialog completion.
    completion: { isSuccess, errorMessage in
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowTextInputDialog.png" alt="Example_IosDialogManager_ShowTextInputDialog" width="400" />
</p>

#### ShowLoginDialog - Login dialog

- Displays a dialog.

```swift
IosDialogManager.shared.showLoginDialog(
    // Set the title.
    title: "Login Required",
    // Set the message.
    message: "Please enter your credentials",
    // Set username placeholder. If not set, "Username" is used.
    usernamePlaceholder: "Username",
    // Set password placeholder. If not set, "Password" is used.
    passwordPlaceholder: "Password",
    // Set login button text. If not set, "Login" is used.
    loginTitle: "Login",
    // Set cancel button text. If not set, "Cancel" is used.
    cancelTitle: "Cancel",
    // Set whether login button is enabled when input is empty. If not set, true is used.
    enableLoginWhenEmpty: false,
    // Set event for login button tap.
    onLogin: { loginButtonText, username, password, isSuccess, errorMessage in
        // loginButtonText: text of the pressed button. Returns nil on error.
        // username: entered username. Returns nil on error.
        // password: entered password. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for cancel button tap.
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText: text of the pressed button. Returns nil on error.
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    },
    // Set event for dialog completion.
    completion: { isSuccess, errorMessage in
        // isSuccess: success flag for dialog display. Returns true on success.
        // errorMessage: error detail if an error occurs. Returns nil on success.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowLoginDialog.png" alt="Example_IosDialogManager_ShowLoginDialog" width="400" />
</p>

---

## Windows

The Windows library offers the same dialogs through two public APIs. Both come from one implementation, and the sample app uses the C++ API.

| API | Names | Header | NuGet package |
|---|---|---|---|
| C++ API | `NativeToolkit::Dialog` | `<NativeToolkit/Dialog.h>` | `NativeToolkit` |
| C ABI | `ntk_dialog_*` | `<NativeToolkitC/Dialog.h>` | `NativeToolkit.CApi` |

### NativeToolkit::Dialog

- Every dialog is modal and blocks the calling thread, so call these functions from the UI thread.
- A call returns `Dialog::Result<T>`. `has_value()` tells the two cases apart, `value()` is the result and `error()` is a `Dialog::Error`, which carries the documented `code` and the raw `systemCode` the OS reported.
- The user dismissing a dialog is not a failure of the call, but it is not a value either: it arrives as `Dialog::ErrorCode::Canceled`.
- The headers never include `<windows.h>`. `request.owner` takes a `NativeToolkit::WindowHandle`, which is `HWND`.

#### ShowAlert - Basic dialog

- Displays a message box and reports which button was pressed.

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::AlertRequest request;
// Set the title.
request.title = L"Native Windows Dialog";
// Set the message.
request.message = L"This is a native Windows dialog!";
// Set which buttons are shown. Here, OK and Cancel.
request.buttons = Dialog::AlertButtons::OkCancel;
// Set the icon. Here, an information icon.
request.icon = Dialog::AlertIcon::Information;
// Set which button starts out focused. Here, the second one.
request.defaultButton = Dialog::AlertDefaultButton::Second;
// Optional: the window the dialog belongs to, and MB_TOPMOST / MB_HELP.
// request.owner = hwnd;
// request.topMost = true;
// request.showHelpButton = true;

const auto result = Dialog::ShowAlert(request);
if (result.has_value())
{
    // Cancel is a button like any other, so it arrives as
    // AlertResult::Cancel rather than as a failure.
    const Dialog::AlertResult pressed = result.value();
    if (pressed == Dialog::AlertResult::Ok)
    {
        // The user pressed OK.
    }
}
else
{
    // code is the documented case, systemCode the raw value from the OS.
    const Dialog::ErrorCode code = result.error().code;
    const uint32_t systemCode = result.error().systemCode;
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowAlertDialog.png" alt="Example_WindowsDialogManager_ShowAlertDialog" width="300" />
</p>

#### ShowOpenFile - File picker dialog

- Asks for one existing file and returns its full path.

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::FileRequest request;
// Set the title.
request.title = L"Open File";
// Set the type list. An entry is a description and its patterns.
// With no filters at all the dialog offers every file.
request.filters = { Dialog::FileFilter{ L"All Files", { L"*.*" } } };
// The picked file has to exist (OFN_FILEMUSTEXIST). This is the default.
request.fileMustExist = true;

const auto result = Dialog::ShowOpenFile(request);
if (result.has_value())
{
    // A full path.
    const std::wstring& filePath = result.value();
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // The user dismissed the dialog.
}
else
{
    const uint32_t systemCode = result.error().systemCode;
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowFileDialog.png" alt="Example_WindowsDialogManager_ShowFileDialog" width="1000" />
</p>

#### ShowOpenFiles - Multi-file picker dialog

- Asks for one or more existing files, in the order the dialog returned them.

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::FileRequest request;
// Set the title.
request.title = L"Open Files";
// Set the type list.
request.filters = { Dialog::FileFilter{ L"All Files", { L"*.*" } } };

const auto result = Dialog::ShowOpenFiles(request);
if (result.has_value())
{
    // Every entry is a full path, and the folder is not an entry of its own.
    const std::vector<std::wstring>& paths = result.value();
    for (const std::wstring& path : paths)
    {
        // One selected file.
    }
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // The user dismissed the dialog.
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowMultiFileDialog.png" alt="Example_WindowsDialogManager_ShowMultiFileDialog" width="1000" />
</p>

#### ShowPickFolder - Folder picker dialog

- Asks for one folder.

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::FolderRequest request;
// Set the title. An empty title leaves the system default.
request.title = L"Select Folder";

const auto result = Dialog::ShowPickFolder(request);
if (result.has_value())
{
    const std::wstring& folderPath = result.value();
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // The user dismissed the dialog.
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowFolderDialog.png" alt="Example_WindowsDialogManager_ShowFolderDialog" width="1000" />
</p>

#### ShowPickFolders - Multi-folder picker dialog

- Asks for one or more folders.

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::FolderRequest request;
// Set the title.
request.title = L"Select Folders";

const auto result = Dialog::ShowPickFolders(request);
if (result.has_value())
{
    // Every entry is a full path.
    const std::vector<std::wstring>& paths = result.value();
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // The user dismissed the dialog.
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowMultiFolderDialog.png" alt="Example_WindowsDialogManager_ShowMultiFolderDialog" width="1000" />
</p>

#### ShowSaveFile - Save file dialog

- Asks where to save a file. The file itself is not created.

```cpp
#include <NativeToolkit/Dialog.h>

namespace Dialog = NativeToolkit::Dialog;

Dialog::SaveFileRequest request;
// Set the title.
request.title = L"Save File";
// Set the type list.
request.filters = { Dialog::FileFilter{ L"All Files", { L"*.*" } } };
// Set the extension appended when the user types none.
request.defaultExtension = L"txt";
// Ask before an existing file is picked (OFN_OVERWRITEPROMPT). This is the default.
request.overwritePrompt = true;

const auto result = Dialog::ShowSaveFile(request);
if (result.has_value())
{
    const std::wstring& savePath = result.value();
}
else if (result.error().code == Dialog::ErrorCode::Canceled)
{
    // The user dismissed the dialog.
}
```

<p align="center">
    <img src="images/windows/dialog/Example_WindowsDialogManager_ShowSaveFileDialog.png" alt="Example_WindowsDialogManager_ShowSaveFileDialog" width="1000" />
</p>

### C ABI

- The same dialogs for C, and for any language that can call a C DLL. The header is plain C99 and includes nothing but `<stddef.h>` and `<stdint.h>`.
- Strings are NUL-terminated UTF-8 in both directions. `NULL` means an empty string.
- A request struct is filled with zeros and given its own `sizeof` in `struct_size`; the zeros are the defaults.
- A function reports its error as the return value. The raw value the OS gave is `ntk_last_system_code()`, read on the same thread right after the failure.
- Anything the library hands back is a handle that the caller frees with the matching `_free`. A pointer read out of a handle stays valid until that handle is freed.

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

/* Zero-filled means "the defaults"; struct_size is what tells the DLL
   which version of the struct this is. */
ntk_dialog_alert_request request;
memset(&request, 0, sizeof(request));
request.struct_size = (uint32_t)sizeof(request);
request.title = "Native Windows Dialog";
request.message = "This is a native Windows dialog!";
request.buttons = NTK_DIALOG_ALERT_BUTTONS_OK_CANCEL;
request.icon = NTK_DIALOG_ALERT_ICON_INFORMATION;
request.default_button = NTK_DIALOG_ALERT_DEFAULT_BUTTON_SECOND;

ntk_dialog_alert_result pressed = 0;
ntk_dialog_error error = ntk_dialog_show_alert(&request, &pressed);
if (error == NTK_DIALOG_ERROR_NONE) {
    /* Cancel is a button, so it is NTK_DIALOG_ALERT_RESULT_CANCEL here. */
} else if (error == NTK_DIALOG_ERROR_SYSTEM_ERROR) {
    uint32_t system_code = ntk_last_system_code();
    (void)system_code;
}
```

The pickers return their paths as a handle:

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

ntk_dialog_file_request request;
memset(&request, 0, sizeof(request));
request.struct_size = (uint32_t)sizeof(request);
request.title = "Open File";

/* One entry of the type list. Patterns are separated by ';'. */
ntk_dialog_filter filters[1];
filters[0].name = "All Files";
filters[0].patterns = "*.*";

ntk_string* path = NULL;
ntk_dialog_error error = ntk_dialog_show_open_file(&request, filters, 1, &path);
if (error == NTK_DIALOG_ERROR_NONE) {
    /* Borrowed: valid until ntk_string_free. */
    const char* utf8 = ntk_string_data(path);
    size_t size = ntk_string_size(path);
    (void)utf8; (void)size;
    ntk_string_free(path);
} else if (error == NTK_DIALOG_ERROR_CANCELED) {
    /* The user dismissed the dialog; path stays NULL. */
}
```

| C++ API | C ABI |
|---|---|
| `Dialog::ShowAlert` | `ntk_dialog_show_alert` |
| `Dialog::ShowOpenFile` | `ntk_dialog_show_open_file` |
| `Dialog::ShowOpenFiles` | `ntk_dialog_show_open_files` |
| `Dialog::ShowSaveFile` | `ntk_dialog_show_save_file` |
| `Dialog::ShowPickFolder` | `ntk_dialog_show_pick_folder` |
| `Dialog::ShowPickFolders` | `ntk_dialog_show_pick_folders` |
---

## macOS

### MacDialogManager

#### ShowDialog - Basic dialog

- Displays a dialog.

```swift
// Set the title. This field is required.
let title = "Hello from macOS"
// Set the message. If omitted, it is not shown.
let message = "This is a native macOS dialog!"
// Configure buttons. At least one button is required.
let buttons = [
    // title: button title. Required.
    // isDefault: set true to make this the default button. Defaults to false. Only one default button is allowed per dialog.
    // keyEquivalent: keyboard shortcut for the button. Defaults to null. If isDefault is true, Enter is automatically assigned.
    DialogButton(title: "OK", isDefault: true),
    DialogButton(title: "Cancel", keyEquivalent: "\u{1b}"),
    DialogButton(title: "Delete", keyEquivalent: "d")
]
// Configure options. Required.
let options = DialogOptions(
    // alertStyle: dialog style. Required.
    alertStyle: .informational,
    // buttons: array of buttons shown in the dialog. Required.
    buttons: buttons,
    // showsHelp: set true to show a help button. Defaults to false.
    showsHelp: true,
    // showsSuppressionButton: set true to show suppression checkbox. Defaults to false.
    showsSuppressionButton: true,
    // suppressionButtonTitle: title for suppression checkbox. If omitted, OS default is used. Ignored when showsSuppressionButton is false.
    suppressionButtonTitle: "Don't show this again",
    // icon: icon shown in the dialog.
    icon: IconConfiguration(
        // Examples for each icon type are shown below. Configure as needed.
        ...
    ),
    // accessoryView: accessory view shown in the dialog. Defaults to nil.
    accessoryView: nil
)

// Example when icon type is a system symbol icon.
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: icon type is system symbol. Required.
        type: .systemSymbol,
        // value: system symbol name. Required.
        value: "info.square.fill",
        // renderingMode: icon rendering mode. Required.
        renderingMode: .palette,
        // colors: icon color array. For Palette mode, 1 to 3 colors are required. For Hierarchical mode, 1 color can be set. Colors use #RRGGBB or color name format.
        colors: ["white", "systemblue", "systemblue"],
        // size: icon size in points. OS default is used when omitted. In dialogs, this may be ignored due to platform constraints.
        size: 64,
        // weight: icon weight. OS default is used when omitted.
        weight: .regular,
        // scale: icon scale. OS default is used when omitted. In dialogs, this may be ignored due to platform constraints.
        scale: .medium
    )
)

// Example when icon type is file path.
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: icon type is file path. Required.
        type: .filePath,
        // value: file path. Required.
        value: "/Users/user/Downloads/test.png"
    )
);

// Example when icon type is named image.
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: icon type is named image. Required.
        type: .namedImage,
        // value: named image identifier. Required.
        value: "test-image"
    )
);

// Example when icon type is app icon.
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: icon type is app icon. Required.
        type: .appIcon
    )
);

// Example when icon type is system image.
let options = DialogOptions(
    ...
    icon: IconConfiguration(
        // type: icon type is system image. Required.
        type: .systemImage,
        // value: system image name. Required.
        value: "cautionName"
    )
)

MacDialogManager.shared.showDialog(
    title: title,
    message: message,
    options: options
    // Set event to receive dialog result.
) { result in
    // result: dialog result.
    switch result {
    // buttonIndex: index of pressed button.
    // buttonTitle: title of pressed button.
    // suppressionButtonState: suppression checkbox state.
    // helpButtonPressed: whether the help button was pressed.
    // isSuccess: success flag for dialog display. Returns true on success.
    case .success(let dialogResult):
        Log.d(TAG, "[ShowDialog] success: \(dialogResult)")
    // error: error details.
    case .failure(let error):
        Log.e(TAG, "[ShowDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowDialog.png" alt="Example_MacDialogManager_ShowDialog" width="400" />
</p>

#### ShowFileDialog - File picker dialog

- Displays a dialog.

```swift
MacDialogManager.shared.showFileDialog(
    // Set the title. This field is required.
    title: "Select a file",
    // Set the message. If omitted, it is not shown.
    message: "Please select a file to open.",
    // Set allowed file extensions. If omitted, OS defaults are used.
    allowedContentTypes: ["txt", "png"],
    // Set initial directory. If omitted, OS defaults are used.
    directoryURL: nil
    // Set event to receive file picker result.
) { result in
    // result: file picker result.
    switch result {
    // filePaths: array of selected file paths. Returns [] when canceled.
    // fileCount: number of returned files. 0 when canceled.
    // directoryURL: directory URL where selection was made. Returns "" when canceled.
    // isCancelled: whether the user canceled the dialog.
    // isSuccess: success flag for dialog display. Returns true on success.
    case .success(let openResult):
        Log.d(TAG, "[ShowFileDialog] success: \(openResult)")
    // error: error details.
    case .failure(let error):
        Log.e(TAG, "[ShowFileDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowFileDialog.png" alt="Example_MacDialogManager_ShowFileDialog" width="1000" />
</p>

#### ShowMultiFileDialog - Multi-file picker dialog

- Displays a dialog.

```swift
MacDialogManager.shared.showMultiFileDialog(
    // Set the title. This field is required.
    title: "Select files",
    // Set the message. If omitted, it is not shown.
    message: "Please select files to open.",
    // Set allowed file extensions. If omitted, OS defaults are used.
    allowedContentTypes: ["txt", "png"],
    // Set initial directory. If omitted, OS defaults are used.
    directoryURL: nil
    // Set event to receive multi-file picker result.
) { result in
    // result: multi-file picker result.
    switch result {
    // filePaths: array of selected file paths. Returns [] when canceled.
    // fileCount: number of returned files. 0 when canceled.
    // directoryURL: directory URL where selection was made. Returns "" when canceled.
    // isCancelled: whether the user canceled the dialog.
    // isSuccess: success flag for dialog display. Returns true on success.
    case .success(let openResult):
        Log.d(TAG, "[ShowMultiFileDialog] success: \(openResult)")
    // error: error details.
    case .failure(let error):
        Log.e(TAG, "[ShowMultiFileDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowMultiFileDialog.png" alt="Example_MacDialogManager_ShowMultiFileDialog" width="1000" />
</p>

#### ShowFolderDialog - Folder picker dialog

- Displays a dialog.

```swift
MacDialogManager.shared.showFolderDialog(
    // Set the title. This field is required.
    title: "Select a folder",
    // Set the message. If omitted, it is not shown.
    message: "Please select a folder to open.",
    // Set initial directory. If omitted, OS defaults are used.
    directoryURL: nil
    // Set event to receive folder picker result.
) { result in
    // result: folder picker result.
    switch result {
    // filePaths: array of selected folder paths. Returns [] when canceled.
    // fileCount: number of returned folders. 0 when canceled.
    // directoryURL: directory URL where selection was made. Returns "" when canceled.
    // isCancelled: whether the user canceled the dialog.
    // isSuccess: success flag for dialog display. Returns true on success.
    case .success(let openResult):
        Log.d(TAG, "[ShowFolderDialog] success: \(openResult)")
    case .failure(let error):
        Log.e(TAG, "[ShowFolderDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowFolderDialog.png" alt="Example_MacDialogManager_ShowFolderDialog" width="1000" />
</p>

#### ShowMultiFolderDialog - Multi-folder picker dialog

- Displays a dialog.

```swift
MacDialogManager.shared.showMultiFolderDialog(
    // Set the title. This field is required.
    title: "Select folders",
    // Set the message. If omitted, it is not shown.
    message: "Please select folders to open.",
    // Set initial directory. If omitted, OS defaults are used.
    directoryURL: nil
    // Set event to receive multi-folder picker result.
) { result in
    // result: multi-folder picker result.
    switch result {
    // filePaths: array of selected folder paths. Returns [] when canceled.
    // fileCount: number of returned folders. 0 when canceled.
    // directoryURL: directory URL where selection was made. Returns "" when canceled.
    // isCancelled: whether the user canceled the dialog.
    // isSuccess: success flag for dialog display. Returns true on success.
    case .success(let openResult):
        Log.d(TAG, "[ShowMultiFolderDialog] success: \(openResult)")
    // error: error details.
    case .failure(let error):
        Log.e(TAG, "[ShowMultiFolderDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowMultiFolderDialog.png" alt="Example_MacDialogManager_ShowMultiFolderDialog" width="1000" />
</p>

#### ShowSaveFileDialog - Save file dialog

- Displays a dialog.

```swift
MacDialogManager.shared.showSaveFileDialog(
    // Set the title. This field is required.
    title: "Save File",
    // Set the message. If omitted, it is not shown.
    message: "Choose a destination",
    // Set default file name. If omitted, OS defaults are used.
    nameFieldStringValue: "default",
    // Set allowed file extensions. If omitted, OS defaults are used.
    allowedContentTypes: ["txt"],
    // Set initial directory. If omitted, OS defaults are used.
    directoryURL: nil
    // Set event to receive save file dialog result.
) { result in
    // result: save file dialog result.
    switch result {
    // filePath: saved file path. Returns "" when canceled.
    // fileCount: number of returned paths. 1 on success, 0 when canceled.
    // directoryURL: directory URL where save was performed. Returns "" when canceled.
    // isCancelled: whether the user canceled the dialog.
    // isSuccess: success flag for dialog display. Returns true on success.
    case .success(let saveResult):
        Log.d(TAG, "[ShowSaveFileDialog] success: \(saveResult)")
    // error: error details.
    case .failure(let error):
        Log.e(TAG, "[ShowSaveFileDialog] error: \(error)")
    }
}
```

<p align="center">
    <img src="images/mac/dialog/Example_MacDialogManager_ShowSaveFileDialog.png" alt="Example_MacDialogManager_ShowSaveFileDialog" width="600" />
</p>
