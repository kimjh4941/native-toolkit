# Dialog

Language:

- English (this page)
- 日本語: [dialog.ja.md](dialog.ja.md)
- 한국어: [dialog.ko.md](dialog.ko.md)

← [Back to manual top](index.md)

---

## Table of Contents

- [Android](#android)
  - [AndroidDialogManager](#androiddialogmanager)
    - [Basic dialog](#basic-dialog)
    - [Confirmation dialog](#confirmation-dialog)
    - [Single-choice dialog](#single-choice-dialog)
    - [Multi-choice dialog](#multi-choice-dialog)
    - [Text input dialog](#text-input-dialog)
    - [Login dialog](#login-dialog)
    - [Waiting with a coroutine](#waiting-with-a-coroutine)
    - [Closing with Back or an outside tap](#closing-with-back-or-an-outside-tap)
    - [Canceling a dialog](#canceling-a-dialog)
  - [C ABI](#c-abi)
    - [Alert and confirmation dialogs](#alert-and-confirmation-dialogs)
    - [Choice list dialogs](#choice-list-dialogs)
    - [Text input and login dialogs](#text-input-and-login-dialogs)
- [iOS](#ios)
  - [IosDialogManager](#iosdialogmanager)
    - [Basic dialog](#basic-dialog-1)
    - [Confirmation dialog](#confirmation-dialog-1)
    - [Destructive dialog](#destructive-dialog)
    - [Action sheet](#action-sheet)
    - [Text input dialog](#text-input-dialog-1)
    - [Login dialog](#login-dialog-1)
    - [One request, one result](#one-request-one-result)
    - [Choosing the view controller](#choosing-the-view-controller)
    - [Canceling a dialog](#canceling-a-dialog-1)
  - [C ABI](#c-abi-1)
    - [Alert, confirmation and destructive dialogs](#alert-confirmation-and-destructive-dialogs)
    - [Action sheets](#action-sheets)
    - [Text input and login dialogs](#text-input-and-login-dialogs-1)
- [Windows](#windows)
  - [NativeToolkit::Dialog](#nativetoolkitdialog)
    - [ShowAlert - Basic dialog](#showalert---basic-dialog)
    - [ShowOpenFile - File picker dialog](#showopenfile---file-picker-dialog)
    - [ShowOpenFiles - Multi-file picker dialog](#showopenfiles---multi-file-picker-dialog)
    - [ShowPickFolder - Folder picker dialog](#showpickfolder---folder-picker-dialog)
    - [ShowPickFolders - Multi-folder picker dialog](#showpickfolders---multi-folder-picker-dialog)
    - [ShowSaveFile - Save file dialog](#showsavefile---save-file-dialog)
  - [C ABI](#c-abi-2)
    - [Message box](#message-box)
    - [File pickers](#file-pickers)
    - [Folder pickers](#folder-pickers)
- [macOS](#macos)
  - [MacDialogManager](#macdialogmanager)

---

## Android

The Android library offers the same dialogs through two public APIs. Both come from one implementation, and the sample app uses the Kotlin API.

| API | Names | Package / header | AAR (Maven coordinate) |
|---|---|---|---|
| Kotlin API | `AndroidDialogManager` | `com.jonghyunkim.nativetoolkit.dialog` | `android-native-toolkit-2.0.0.aar` (`io.github.kimjh4941:android-native-toolkit:2.0.0`) |
| C ABI | `ntk_dialog_*` | `<NativeToolkitC/Dialog.h>` | `android-native-toolkit-capi-2.0.0.aar` (`io.github.kimjh4941:android-native-toolkit-capi:2.0.0`) |

- The library needs minSdk 31 and compileSdk 36. Kotlin apps need Kotlin 2.1 or later.
- Code written for the 1.x library has to be updated, because the package name and the API changed: see [Migrating the Android library to 2.0.0](index.md#migrating-the-android-library-to-200). `AndroidDialogFragment` and its listeners are still public in `com.jonghyunkim.nativetoolkit.dialog`, but new code should use `AndroidDialogManager`.

### AndroidDialogManager

- `AndroidDialogManager.getInstance(context)` returns the process-wide instance. Any `Context` will do, and it is not kept.
- No Activity or `FragmentManager` is passed in. The dialog appears on the foreground Activity of the app. When that Activity is not a `FragmentActivity` (for example a plain `ComponentActivity` or a game's Activity), the library opens a transparent Activity of its own to hold the dialog.
- The app has to be in the foreground. Called from the background, the request ends with `DialogResult.Failed(DialogError.NOT_FOREGROUND)`.
- The library initializes itself at app start through androidx.startup, so there is nothing to call first. An app that removes the Startup initializer calls `LibraryRuntime.ensureInitialized(activity)` (`com.jonghyunkim.nativetoolkit.common.runtime`) from its first Activity's `onCreate`, passing that Activity; until then a request ends with `DialogResult.Failed(DialogError.NOT_INITIALIZED)`. Given only the application context, the library misses the Activity already on screen, and dialogs end with `DialogError.NOT_FOREGROUND` until the next Activity starts.
- `show(request, onResult)` may be called from any thread. It returns the request ID (`Long`) that `cancel` takes. `onResult` is called exactly once, on the main thread, and never inside `show`.
- A dialog survives a configuration change such as a rotation: the library restores it, and the result is still delivered to the same `onResult`.
- An invalid request (an empty item list, a `checked` list whose size differs from the items, a `checkedIndex` out of range) makes `show` throw `IllegalArgumentException`.

The result is one of four `DialogResult` values.

| Result | When |
|---|---|
| `DialogResult.Button(which, text, value)` | The user pressed a button. `which` is `DialogButton.POSITIVE` or `DialogButton.NEGATIVE`, `text` is its label |
| `DialogResult.Dismissed` | The user closed the dialog with Back or a tap outside (only when `DialogOptions` allows it) |
| `DialogResult.Canceled(reason)` | The request ended without an answer. `CancelReason.REQUESTED` after `cancel`, `CancelReason.HOST_DESTROYED` when the Activity showing the dialog was destroyed for good |
| `DialogResult.Failed(error)` | The dialog could not be shown: `DialogError.NOT_INITIALIZED`, `NOT_FOREGROUND`, `HOST_START_FAILED` (the transparent Activity did not start) or `SHOW_FAILED` |

`Button.value` carries what the user entered. The negative button always gives `DialogValue.None`. `DialogValue.Text` and `DialogValue.Login` hide their contents in `toString()`, so printing a result does not log what the user typed.

| Request | `value` of the positive button |
|---|---|
| `DialogRequest.Alert`, `DialogRequest.Confirm` | `DialogValue.None` |
| `DialogRequest.SingleChoice` | `DialogValue.SingleChoice(index)`. `index` is `null` when nothing is selected |
| `DialogRequest.MultiChoice` | `DialogValue.MultiChoice(checked)`, one `Boolean` per item |
| `DialogRequest.TextInput` | `DialogValue.Text(text)` |
| `DialogRequest.Login` | `DialogValue.Login(username, password)` |

#### Basic dialog

- Displays a message with one button.

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult

// Any Context. It is not kept.
val manager = AndroidDialogManager.getInstance(context)

val request = DialogRequest.Alert(
    // Set the title. This field is required.
    title = "Hello from Android",
    // Set the message. This field is required.
    message = "This is a native Android dialog!",
    // Set the button text. If not set, "OK" is used.
    buttonText = "OK",
    // Set whether Back and a tap outside close the dialog. If not set, both do.
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

// Returns the request ID used with cancel().
// Throws IllegalArgumentException when the request is invalid.
val requestId = manager.show(request) { result ->
    // Called once, on the main thread.
    when (result) {
        is DialogResult.Button -> Log.d(TAG, "button: ${result.which} (${result.text})")
        DialogResult.Dismissed -> Log.d(TAG, "Dismissed")
        is DialogResult.Canceled -> Log.d(TAG, "Canceled: ${result.reason}")
        is DialogResult.Failed -> Log.d(TAG, "Unavailable: ${result.error}")
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowDialog.png" alt="Example_AndroidDialogFragment_ShowDialog" width="400" />
</p>

#### Confirmation dialog

- Displays a message with a negative and a positive button.

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogButton
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult

val request = DialogRequest.Confirm(
    // Set the title. This field is required.
    title = "Confirmation",
    // Set the message. This field is required.
    message = "Do you want to proceed with this action?",
    // Set the negative button text. If not set, "No" is used.
    negativeText = "No",
    // Set the positive button text. If not set, "Yes" is used.
    positiveText = "Yes",
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    when (result) {
        is DialogResult.Button -> {
            if (result.which == DialogButton.POSITIVE) {
                // The user pressed "Yes".
            }
        }
        else -> Log.d(TAG, "result: $result")
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowConfirmDialog.png" alt="Example_AndroidDialogFragment_ShowConfirmDialog" width="400" />
</p>

#### Single-choice dialog

- Displays a list in which one item can be selected.

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

val request = DialogRequest.SingleChoice(
    // Set the title. This field is required.
    title = "Please select one",
    // Set the items. This field is required and must not be empty.
    items = listOf("Option 1", "Option 2", "Option 3"),
    // Set the item selected first, or null for none. If not set, 0 is used.
    checkedIndex = 0,
    // Set the negative button text. If not set, "Cancel" is used.
    negativeText = "Cancel",
    // Set the positive button text. If not set, "OK" is used.
    positiveText = "OK",
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result is DialogResult.Button) {
        // DialogValue.SingleChoice for the positive button, DialogValue.None for the negative one.
        val value = result.value
        if (value is DialogValue.SingleChoice) {
            // The selected index, or null when nothing is selected.
            Log.d(TAG, "button: ${result.which}, index: ${value.index}")
        }
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowSingleChoiceItemDialog.png" alt="Example_AndroidDialogFragment_ShowSingleChoiceItemDialog" width="400" />
</p>

#### Multi-choice dialog

- Displays a list in which any number of items can be selected.

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

val request = DialogRequest.MultiChoice(
    // Set the title. This field is required.
    title = "Multiple Selection",
    // Set the items. This field is required and must not be empty.
    items = listOf("Option 1", "Option 2", "Option 3", "Option 4"),
    // Set the initial selection. This field is required, with one value per item.
    checked = listOf(false, true, false, true),
    // Set the negative button text. If not set, "Cancel" is used.
    negativeText = "Cancel",
    // Set the positive button text. If not set, "OK" is used.
    positiveText = "OK",
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result is DialogResult.Button) {
        val value = result.value
        if (value is DialogValue.MultiChoice) {
            // One value per item: true for checked.
            Log.d(TAG, "button: ${result.which}, checked: ${value.checked}")
        }
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowMultiChoiceItemDialog.png" alt="Example_AndroidDialogFragment_ShowMultiChoiceItemDialog" width="400" />
</p>

#### Text input dialog

- Displays a message with one text field.

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

val request = DialogRequest.TextInput(
    // Set the title. This field is required.
    title = "Text Input",
    // Set the message. This field is required.
    message = "Please enter your name",
    // Set the hint. If not set, an empty string is used.
    hint = "Enter here...",
    // Set the negative button text. If not set, "Cancel" is used.
    negativeText = "Cancel",
    // Set the positive button text. If not set, "OK" is used.
    positiveText = "OK",
    // Set whether the positive button works while the field is empty. If not set, false is used.
    enablePositiveWhenEmpty = false,
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result is DialogResult.Button) {
        val value = result.value
        if (value is DialogValue.Text) {
            // value.text is what the user entered. Log its length, not the text.
            Log.d(TAG, "button: ${result.which}, textLength: ${value.text.length}")
        }
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowTextInputDialog.png" alt="Example_AndroidDialogFragment_ShowTextInputDialog" width="400" />
</p>

#### Login dialog

- Displays a message with a username field and a password field.

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue

val request = DialogRequest.Login(
    // Set the title. This field is required.
    title = "Login",
    // Set the message. This field is required.
    message = "Please enter your credentials",
    // Set the username hint. If not set, "Username" is used.
    usernameHint = "Username",
    // Set the password hint. If not set, "Password" is used.
    passwordHint = "Password",
    // Set the negative button text. If not set, "Cancel" is used.
    negativeText = "Cancel",
    // Set the positive button text. If not set, "Login" is used.
    positiveText = "Login",
    // Set whether the positive button works while a field is empty. If not set, false is used.
    enablePositiveWhenEmpty = false,
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result is DialogResult.Button) {
        val value = result.value
        if (value is DialogValue.Login) {
            // value.username and value.password are what the user entered. Never log the password.
            Log.d(TAG, "usernameLength: ${value.username.length}, passwordLength: ${value.password.length}")
        }
    }
}
```

<p align="center">
    <img src="images/android/dialog/Example_AndroidDialogFragment_ShowLoginDialog.png" alt="Example_AndroidDialogFragment_ShowLoginDialog" width="400" />
</p>

#### Waiting with a coroutine

- `show(request)` without a callback is a `suspend` function. It returns the answer, `DialogResult.Button` or `DialogResult.Dismissed` (both are `DialogResult.Answer`).
- A request that ends without an answer throws `DialogDomainError.Canceled(reason)`, and a dialog that cannot be shown throws `DialogDomainError.Unavailable(error)`.
- Canceling the coroutine closes the dialog. Tie the coroutine to the screen (in Compose, `rememberCoroutineScope()`), so that leaving the screen closes the dialog too.

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogDomainError
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import kotlinx.coroutines.launch

val manager = AndroidDialogManager.getInstance(context)
val request = DialogRequest.Confirm(
    title = "Confirmation",
    message = "Do you want to proceed with this action?",
    negativeText = "No",
    positiveText = "Yes",
    options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)
)

scope.launch {
    try {
        when (val answer = manager.show(request)) {
            is DialogResult.Button -> Log.d(TAG, "button: ${answer.which} (${answer.text})")
            DialogResult.Dismissed -> Log.d(TAG, "Dismissed")
        }
    } catch (e: DialogDomainError.Canceled) {
        // e.reason is CancelReason.REQUESTED or CancelReason.HOST_DESTROYED.
        Log.d(TAG, "Canceled: ${e.reason}")
    } catch (e: DialogDomainError.Unavailable) {
        // e.error is a DialogError, for example NOT_FOREGROUND.
        Log.d(TAG, "Unavailable: ${e.error}")
    }
}
```

#### Closing with Back or an outside tap

- `DialogOptions()` with no arguments lets Back and a tap outside close the dialog. The result is then `DialogResult.Dismissed`, which carries no value.

```kotlin
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogOptions
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult

val request = DialogRequest.Alert(
    title = "Cancelable",
    message = "Tap outside or press Back.",
    buttonText = "OK",
    // cancelable = true and cancelableOnTouchOutside = true.
    options = DialogOptions()
)

AndroidDialogManager.getInstance(context).show(request) { result ->
    if (result == DialogResult.Dismissed) {
        // The user pressed Back or tapped outside the dialog.
    }
}
```

#### Canceling a dialog

- `cancel(requestId)` closes a dialog from code. Its result becomes `DialogResult.Canceled(CancelReason.REQUESTED)`, unless it already has one.
- `cancel` may be called from any thread. An unknown ID, or the ID of a dialog that already has its result, is ignored.

```kotlin
import android.os.Handler
import android.os.Looper
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager

val manager = AndroidDialogManager.getInstance(context)
// request: any DialogRequest, for example the one of the basic dialog.
val requestId = manager.show(request) { result ->
    // DialogResult.Canceled(CancelReason.REQUESTED) when cancel() came first.
    Log.d(TAG, "result: $result")
}

// Close the dialog after 2 seconds.
Handler(Looper.getMainLooper()).postDelayed({ manager.cancel(requestId) }, 2_000)
```

### C ABI

- The same dialogs for C, and for any language that can call a C function (C#, Dart, Rust and others). A Kotlin or Java app calls `AndroidDialogManager` instead: the C ABI calls it through JNI, so it would only add a round trip.
- Add both AARs to the app: `android-native-toolkit-capi-2.0.0.aar` holds `libntk.so` and the headers, and it needs `android-native-toolkit-2.0.0.aar` next to it. `libntk.so` exists for 64-bit ABIs only (`arm64-v8a`, `x86_64`). An app installed as 32-bit still starts, but `libntk.so` is missing, so loading it fails.
- The headers and `libntk.so` come through Prefab. Turn Prefab on and limit the app's ABIs and its CMake build to the 64-bit ABIs, both of them; [Setup](index.md#c-abi) explains why (an `if()` in `CMakeLists.txt` does not avoid the `CXX1210` build error, and 32-bit native code of your own goes in a separate module without Prefab):

```kotlin
android {
    buildFeatures { prefab = true }
    defaultConfig {
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { abiFilters("arm64-v8a", "x86_64") }
        }
    }
}
```

```cmake
find_package(ntk REQUIRED CONFIG)
target_link_libraries(your_library PRIVATE ntk::ntk)
```

- androidx.startup initializes the library at app start. An app that turns Startup off, calls from a process other than the default one, or loads `libntk.so` only with `dlopen`, calls `ntk_android_init(env, context)` (`<NativeToolkitC/Android.h>`) first. Until the library is initialized, the `ntk_dialog_show_*_async` functions return `NTK_DIALOG_ERROR_NOT_INITIALIZED`. The argument checks come first, so a bad argument still gets `NTK_DIALOG_ERROR_INVALID_PARAMETER`, and `ntk_dialog_cancel` returns `NTK_DIALOG_ERROR_NONE` without doing anything. The result readers and `ntk_dialog_result_free` work regardless.
- The headers are plain C99 and include nothing but `<stddef.h>` and `<stdint.h>`. Strings are NUL-terminated UTF-8. A `NULL` button or hint text takes the Kotlin default (`"OK"`, `"Cancel"` and so on), a `NULL` title or message is an empty string.
- A request struct is filled with zeros and given its own `sizeof` in `struct_size`; the zeros are the defaults. That inverts two flag names against the Kotlin API, so that the default stays zero: `not_cancelable` is the opposite of `cancelable`, and `not_cancelable_on_touch_outside` the opposite of `cancelableOnTouchOutside`.
- Every function may be called from any thread and never waits for the main thread. The return value only says whether the request was accepted. A call rejected on entry (an invalid argument, `NOT_INITIALIZED`) never calls the callback, and calls `release` on the calling thread before it returns.
- An accepted request completes exactly once, on the Android main thread, and `release` follows. Neither runs inside the call that started the request. Called off the main thread, the completion may arrive before that call returns, so tie a completion to its request through `user_data`. Called while the app is in the background, a request completes with `NTK_DIALOG_ERROR_NOT_FOREGROUND`.
- The `ntk_dialog_result` handed to the callback is owned by the receiver, which frees it with `ntk_dialog_result_free`, during the callback or later. It is `NULL` unless the error is `NTK_DIALOG_ERROR_NONE`. `system_code` and `ntk_last_system_code()` are always 0 on Android.
- Request IDs are `uint64_t` and never reused. `ntk_dialog_cancel` takes one from any thread, and ignores an unknown ID or a request that already completed.
- A callback must not block the main thread or let an exception escape: the library does not catch it, and the process ends.

#### Alert and confirmation dialogs

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Dialog.h>

static void NTK_CALL on_dialog_result(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                      uint32_t system_code, ntk_dialog_result* result)
{
    /* On the Android main thread, once per accepted request. system_code is always 0. */
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        /* result is NULL. CANCELED after ntk_dialog_cancel, CANCELED_BY_SYSTEM when the
           Activity went away, NOT_FOREGROUND when the app was in the background. */
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON) {
        ntk_dialog_button button = ntk_dialog_result_button(result);
        size_t size = 0;
        const char* label = ntk_dialog_result_button_text(result, &size);
        (void)button; (void)label;
    } else {
        /* NTK_DIALOG_ANSWER_DISMISSED: Back or a tap outside. It carries no value. */
    }
    /* The result belongs to the receiver. Free it here, or later on any thread. */
    ntk_dialog_result_free(result);
}

static void NTK_CALL release_user_data(void* user_data)
{
    /* Called exactly once: on the main thread after the completion, or on the calling
       thread before the call returns when the call was rejected. */
    (void)user_data;
}

/* The headers and libntk.so have to be the same version. */
if (ntk_version() != NTK_VERSION) {
    return;
}
/* androidx.startup initializes the library at app start. An app that turned Startup
   off calls ntk_android_init(env, context) first. */
if (!ntk_android_is_initialized()) {
    return;
}

/* --- Basic dialog --------------------------------------------------- */
ntk_dialog_alert_request alert;
memset(&alert, 0, sizeof(alert));
alert.struct_size = (uint32_t)sizeof(alert);
alert.title = "Hello from Android";
alert.message = "This is a native Android dialog!";
alert.button_text = "OK";                    /* NULL: "OK" */
alert.not_cancelable = 1;                    /* Back does not close it */
alert.not_cancelable_on_touch_outside = 1;   /* nor does a tap outside */

uint64_t request_id = 0;
ntk_dialog_error error = ntk_dialog_show_alert_async(&alert, &on_dialog_result, NULL,
                                                     &release_user_data, &request_id);
if (error != NTK_DIALOG_ERROR_NONE) {
    /* Rejected: the callback is never called, and release_user_data has already run. */
    return;
}

/* Later, for example when the screen closes: the dialog closes and completes with
   NTK_DIALOG_ERROR_CANCELED. A finished or unknown ID does nothing. */
ntk_dialog_cancel(request_id);

/* --- Confirmation dialog -------------------------------------------- */
ntk_dialog_confirm_request confirm;
memset(&confirm, 0, sizeof(confirm));
confirm.struct_size = (uint32_t)sizeof(confirm);
confirm.title = "Confirmation";
confirm.message = "Do you want to proceed with this action?";
confirm.negative_text = "No";                /* NULL: "No" */
confirm.positive_text = "Yes";               /* NULL: "Yes" */
confirm.not_cancelable = 1;
confirm.not_cancelable_on_touch_outside = 1;

/* out_request_id may be NULL when the dialog is never canceled. */
error = ntk_dialog_show_confirm_async(&confirm, &on_dialog_result, NULL, &release_user_data, NULL);
```

#### Choice list dialogs

`ntk_dialog_result_checked_index` reads the single-choice answer and is -1 when nothing is checked; `ntk_dialog_result_checked_count` and `ntk_dialog_result_checked_at` read the multi-choice answer, nonzero for a checked item. The negative button carries no selection.

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

static void NTK_CALL on_single_choice(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                      uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON
        && ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        int32_t index = ntk_dialog_result_checked_index(result);   /* -1: none checked */
        (void)index;
    }
    ntk_dialog_result_free(result);
}

static void NTK_CALL on_multi_choice(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                     uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON
        && ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        size_t count = ntk_dialog_result_checked_count(result);
        size_t i;
        for (i = 0; i < count; ++i) {
            int32_t checked = ntk_dialog_result_checked_at(result, i);   /* nonzero: checked */
            (void)checked;
        }
    }
    ntk_dialog_result_free(result);
}

/* --- One item ------------------------------------------------------- */
const char* const single_items[] = { "Option 1", "Option 2", "Option 3" };

ntk_dialog_single_choice_request single;
memset(&single, 0, sizeof(single));
single.struct_size = (uint32_t)sizeof(single);
single.title = "Please select one";
single.items = single_items;
single.item_count = 3;                       /* must not be 0 */
single.checked_index = 0;                    /* -1: none checked */
single.negative_text = "Cancel";             /* NULL: "Cancel" */
single.positive_text = "OK";                 /* NULL: "OK" */
single.not_cancelable = 1;
single.not_cancelable_on_touch_outside = 1;

/* user_data and release may be NULL when there is nothing to free. */
ntk_dialog_error error = ntk_dialog_show_single_choice_async(&single, &on_single_choice, NULL, NULL, NULL);

/* --- Any number of items -------------------------------------------- */
const char* const multi_items[] = { "Option 1", "Option 2", "Option 3", "Option 4" };
const int32_t multi_checked[] = { 0, 1, 0, 1 };

ntk_dialog_multi_choice_request multi;
memset(&multi, 0, sizeof(multi));
multi.struct_size = (uint32_t)sizeof(multi);
multi.title = "Multiple Selection";
multi.items = multi_items;
multi.item_count = 4;
multi.checked = multi_checked;               /* NULL: none checked; else item_count values */
multi.negative_text = "Cancel";
multi.positive_text = "OK";
multi.not_cancelable = 1;
multi.not_cancelable_on_touch_outside = 1;

error = ntk_dialog_show_multi_choice_async(&multi, &on_multi_choice, NULL, NULL, NULL);
```

#### Text input and login dialogs

The text, the username and the password point into the result and stay valid until it is freed.

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

static void NTK_CALL on_text_input(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                   uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON
        && ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        size_t size = 0;
        const char* text = ntk_dialog_result_text(result, &size);   /* UTF-8 */
        (void)text;
    }
    ntk_dialog_result_free(result);
}

static void NTK_CALL on_login(void* user_data, uint64_t request_id, ntk_dialog_error error,
                              uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_answer(result) == NTK_DIALOG_ANSWER_BUTTON
        && ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        const char* username = ntk_dialog_result_username(result, NULL);
        const char* password = ntk_dialog_result_password(result, NULL);   /* never log it */
        (void)username; (void)password;
    }
    ntk_dialog_result_free(result);
}

/* --- Text input ----------------------------------------------------- */
ntk_dialog_text_input_request input;
memset(&input, 0, sizeof(input));
input.struct_size = (uint32_t)sizeof(input);
input.title = "Text Input";
input.message = "Please enter your name";
input.hint = "Enter here...";                /* NULL: no hint */
input.negative_text = "Cancel";              /* NULL: "Cancel" */
input.positive_text = "OK";                  /* NULL: "OK" */
input.enable_positive_when_empty = 0;
input.not_cancelable = 1;
input.not_cancelable_on_touch_outside = 1;

ntk_dialog_error error = ntk_dialog_show_text_input_async(&input, &on_text_input, NULL, NULL, NULL);

/* --- Login ---------------------------------------------------------- */
ntk_dialog_login_request login;
memset(&login, 0, sizeof(login));
login.struct_size = (uint32_t)sizeof(login);
login.title = "Login";
login.message = "Please enter your credentials";
login.username_hint = "Username";            /* NULL: "Username" */
login.password_hint = "Password";            /* NULL: "Password" */
login.negative_text = "Cancel";              /* NULL: "Cancel" */
login.positive_text = "Login";               /* NULL: "Login" */
login.enable_positive_when_empty = 0;
login.not_cancelable = 1;
login.not_cancelable_on_touch_outside = 1;

error = ntk_dialog_show_login_async(&login, &on_login, NULL, NULL, NULL);
```

| Error | Returned or completed | Meaning |
|---|---|---|
| `NTK_DIALOG_ERROR_NONE` | Both | Accepted, or answered |
| `NTK_DIALOG_ERROR_INVALID_PARAMETER` | Returned (rarely completed) | A `NULL` callback or request, invalid UTF-8, no items, an index out of range, a `struct_size` below the 2.0.0 size or above 4096, a nonzero reserved field. It can also complete a request the Kotlin API rejected with `IllegalArgumentException` after it was accepted |
| `NTK_DIALOG_ERROR_NOT_INITIALIZED` | Returned | Called before initialization. The argument checks come first, and `ntk_dialog_cancel` returns `NONE` |
| `NTK_DIALOG_ERROR_NOT_SUPPORTED` | Returned | A newer `struct_size` with nonzero fields this library does not know |
| `NTK_DIALOG_ERROR_UNKNOWN` | Both | Anything else (logcat has the detail) |
| `NTK_DIALOG_ERROR_OUT_OF_MEMORY` | Both | Out of memory |
| `NTK_DIALOG_ERROR_CANCELED` | Completed | `ntk_dialog_cancel` (`CancelReason.REQUESTED`) |
| `NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM` | Completed | The Activity showing the dialog was destroyed (`CancelReason.HOST_DESTROYED`) |
| `NTK_DIALOG_ERROR_NOT_FOREGROUND` | Completed | The app was not in the foreground (`DialogError.NOT_FOREGROUND`) |
| `NTK_DIALOG_ERROR_HOST_START_FAILED` | Completed | The transparent Activity did not start (`DialogError.HOST_START_FAILED`) |
| `NTK_DIALOG_ERROR_SHOW_FAILED` | Completed | Showing the dialog failed (`DialogError.SHOW_FAILED`) |

| Kotlin API | C ABI |
|---|---|
| `show(DialogRequest.Alert(...))` | `ntk_dialog_show_alert_async` |
| `show(DialogRequest.Confirm(...))` | `ntk_dialog_show_confirm_async` |
| `show(DialogRequest.SingleChoice(...))` | `ntk_dialog_show_single_choice_async` |
| `show(DialogRequest.MultiChoice(...))` | `ntk_dialog_show_multi_choice_async` |
| `show(DialogRequest.TextInput(...))` | `ntk_dialog_show_text_input_async` |
| `show(DialogRequest.Login(...))` | `ntk_dialog_show_login_async` |
| `cancel(requestId)` | `ntk_dialog_cancel` |
| `DialogResult.Button` / `DialogResult.Dismissed` | `ntk_dialog_result_answer` |
| `DialogResult.Button.which` / `text` | `ntk_dialog_result_button`, `ntk_dialog_result_button_text` |
| `DialogValue` | `ntk_dialog_result_checked_index`, `ntk_dialog_result_checked_count`, `ntk_dialog_result_checked_at`, `ntk_dialog_result_text`, `ntk_dialog_result_username`, `ntk_dialog_result_password` |
| - | `ntk_dialog_result_free` |

---

## iOS

The iOS library offers the dialogs through two public APIs. Both come from one implementation, and the sample app uses the Swift API.

| API | Names | Module / header | XCFramework |
|---|---|---|---|
| Swift API | `IosDialogManager` | `IosLibrary` | `ios-native-toolkit-2.0.0.xcframework` |
| C ABI | `ntk_dialog_*` | `<NativeToolkitC/Dialog.h>` | `ios-native-toolkit-capi-2.0.0.xcframework`, embedded together with `ios-native-toolkit-2.0.0.xcframework` |

- The library needs iOS 18.0 or later. An app that uses the Swift API is built with Xcode 26.3 or later.
- iOS has a destructive dialog and an action sheet, which Android does not have. Android's single-choice and multi-choice dialogs have no iOS counterpart. An iOS alert does not close when the user taps outside it, so there is no "dismissed" answer as on Android.
- Code written for the 1.x library has to be updated: see [Migrating the iOS library to 2.0.0](index.md#migrating-the-ios-library-to-200). For dialogs, the `show...` methods keep their names, parameters and defaults, but:
  - Their callbacks are `@MainActor @Sendable` and are called on the main thread.
  - A failure is reported only through `completion`. `showLoginDialog` no longer calls `onLogin` with `isSuccess == false`, and when UIKit declines the presentation, `completion(false, "Failed to present the dialog")` is called once.
  - `getRootViewController()` is `@MainActor`: a synchronous nonisolated context cannot call it.
  - New in 2.0.0: `show(_:presenter:requestBox:completion:)` and its `async` form, which report one result per request, `cancel(_:)`, `foregroundViewController()`, and the types `DialogRequest`, `DialogAnswer`, `DialogInput`, `DialogError`, `PresenterSelection` and `RequestBox`.

### IosDialogManager

- `IosDialogManager.shared` is the process-wide instance. Every method except `getRootViewController()` and `foregroundViewController()` may be called from any thread; those two read UIKit state and are `@MainActor`.
- There are two ways to show a dialog, and the sample screen shows both, in this order:
  - One `show...` method per kind (`showAlert`, `showConfirmDialog`, `showDestructiveDialog`, `showActionSheet`, `showTextInputDialog`, `showLoginDialog`). This is the 1.x API. A button callback reports the pressed button, and `completion` reports whether the dialog was presented. `showDialog(...)` with your own `UIAlertAction`s is also still there.
  - `show(_:presenter:requestBox:completion:)` takes a `DialogRequest` and reports one `Result<DialogAnswer, DialogError>`: the pressed button, or why the request ended without one. It can be canceled, and it can be told which view controller to present from.
- Every callback is called on the main thread, at most once, and never inside the call that showed the dialog, also when that call was made on the main thread. The callback types are `@MainActor @Sendable`, so a closure written in a SwiftUI view can use the view's state directly.
- A dialog needs a window scene in the foreground. The library keeps a presented dialog weakly and drops the callbacks when the request ends. Avoid capturing large objects strongly in the closures.

The `show...` methods report as follows.

| Callback | When |
|---|---|
| The button callback (`onButton`, `onConfirm`, `onCancel`, `onDestructive`, `onAction`, `onLogin`) | The user pressed that button. It receives the button's text (and, for text input and login, what was entered), `isSuccess == true` and `errorMessage == nil` |
| `completion(true, nil)` | UIKit presented the dialog |
| `completion(false, "Failed to get root view controller")` | No view controller to present from was found |
| `completion(false, "Failed to present the dialog")` | UIKit declined the presentation, for example because the view controller found was already presenting another one |

- When the dialog goes away without a button being pressed (other code dismissed it, or its scene was disconnected), none of these is called: the `show...` methods have no result for it. `show(_:presenter:requestBox:completion:)` reports it as `DialogError.dismissedBySystem`.
- The `show...` methods present from the topmost view controller of the key window of the first `foregroundActive` scene, and do not wait. A second dialog requested while the first one is still being presented is likely to fail with `"Failed to present the dialog"`. To show it over the first one, use `show(_:presenter:requestBox:completion:)` with `presenter: .foreground` (see [Choosing the view controller](#choosing-the-view-controller)).

#### Basic dialog

- Displays a message with one button.

```swift
import IosLibrary

IosDialogManager.shared.showAlert(
    // Set the title. If not set, no title is shown.
    title: "Hello from iOS",
    // Set the message. If not set, no message is shown.
    message: "This is a native iOS dialog!",
    // Set the button text. If not set, "OK" is used.
    buttonText: "OK",
    // Called on the main thread when the button is pressed.
    onButton: { buttonText, isSuccess, errorMessage in
        // buttonText: the button's text ("OK"). isSuccess is true and errorMessage is nil.
    },
    // Called once, on the main thread, when the dialog was presented or could not be.
    completion: { isSuccess, errorMessage in
        // isSuccess: true once the dialog is presented.
        // errorMessage: nil on success, otherwise "Failed to get root view controller"
        // or "Failed to present the dialog".
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowAlert.png" alt="Example_IosDialogManager_ShowAlert" width="400" />
</p>

#### Confirmation dialog

- Displays a message with a confirm button and a cancel button.

```swift
import IosLibrary

IosDialogManager.shared.showConfirmDialog(
    // Set the title. If not set, no title is shown.
    title: "Confirm Action",
    // Set the message. If not set, no message is shown.
    message: "Are you sure you want to proceed?",
    // Set the confirm button text. If not set, "OK" is used.
    confirmTitle: "Yes",
    // Set the cancel button text. If not set, "Cancel" is used.
    cancelTitle: "No",
    // Called when the confirm button is pressed.
    onConfirm: { confirmButtonText, isSuccess, errorMessage in
        // confirmButtonText: "Yes".
    },
    // Called when the cancel button is pressed.
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText: "No".
    },
    // Called once when the dialog was presented or could not be.
    completion: { isSuccess, errorMessage in
        // As for showAlert.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowConfirmDialog.png" alt="Example_IosDialogManager_ShowConfirmDialog" width="400" />
</p>

#### Destructive dialog

- Displays a message with a destructive button, shown in red, and a cancel button. iOS only.

```swift
import IosLibrary

IosDialogManager.shared.showDestructiveDialog(
    // Set the title. If not set, no title is shown.
    title: "Delete File",
    // Set the message. If not set, no message is shown.
    message: "This action cannot be undone. Are you sure?",
    // Set the destructive button text. If not set, "Delete" is used.
    destructiveTitle: "Delete",
    // Set the cancel button text. If not set, "Cancel" is used.
    cancelTitle: "Cancel",
    // Called when the destructive button is pressed.
    onDestructive: { destructiveButtonText, isSuccess, errorMessage in
        // destructiveButtonText: "Delete".
    },
    // Called when the cancel button is pressed.
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText: "Cancel".
    },
    // Called once when the dialog was presented or could not be.
    completion: { isSuccess, errorMessage in
        // As for showAlert.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowDestructiveDialog.png" alt="Example_IosDialogManager_ShowDestructiveDialog" width="400" />
</p>

#### Action sheet

- Displays a list of options and a cancel button. iOS only.
- On iPad the action sheet is a popover anchored in `sourceView`. `sourceRect` is the rectangle in `sourceView` the popover points at; `nil` uses the whole bounds of `sourceView`. When `sourceView` is large (for example the whole screen), the popover has no room and shows without its options, so pass a small rectangle, as the sample does with the center point.
- On iPad, and on iPhone with iOS 26, a tap outside the action sheet chooses the cancel button: `onAction` receives `cancelTitle`.
- `getRootViewController()` is `@MainActor`. A SwiftUI button action runs on the main actor, so it can call it directly.

```swift
import IosLibrary
import UIKit

if let rootVC = IosDialogManager.shared.getRootViewController() {
    IosDialogManager.shared.showActionSheet(
        // Set the title. If not set, no title is shown.
        title: "Please select",
        // Set the message. If not set, no message is shown.
        message: "Please choose an option",
        // Set the options. This field is required.
        options: ["Camera", "Photo Library", "Documents"],
        // Set the cancel button text. If not set, "Cancel" is used.
        cancelTitle: "Cancel",
        // Set the view the iPad popover is anchored in. This field is required.
        sourceView: rootVC.view,
        // A point at the center: with the whole view (nil), the iPad popover has no room for its options.
        sourceRect: CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0),
        // Set whether to animate the presentation. If not set, true is used.
        animated: true,
        // Called when an option or the cancel button is chosen.
        onAction: { action, isSuccess, errorMessage in
            // action: the chosen option ("Camera", ...), or "Cancel" for the cancel button.
        },
        // Called once when the action sheet was presented or could not be.
        completion: { isSuccess, errorMessage in
            // As for showAlert.
        }
    )
}
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowActionSheet.png" alt="Example_IosDialogManager_ShowActionSheet" width="400" />
</p>

#### Text input dialog

- Displays a message with one text field.

```swift
import IosLibrary

IosDialogManager.shared.showTextInputDialog(
    // Set the title. If not set, no title is shown.
    title: "Enter Name",
    // Set the message. If not set, no message is shown.
    message: "Please enter your name",
    // Set the placeholder. If not set, no placeholder is shown.
    placeholder: "Your name here",
    // Set the confirm button text. If not set, "OK" is used.
    confirmTitle: "OK",
    // Set the cancel button text. If not set, "Cancel" is used.
    cancelTitle: "Cancel",
    // Set whether the confirm button works while the field is empty. If not set, true is used.
    enableConfirmWhenEmpty: false,
    // Called when the confirm button is pressed.
    onConfirm: { confirmButtonText, inputText, isSuccess, errorMessage in
        // inputText: what the user entered. Log its length, not the text.
    },
    // Called when the cancel button is pressed. What was entered is not passed.
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText: "Cancel".
    },
    // Called once when the dialog was presented or could not be.
    completion: { isSuccess, errorMessage in
        // As for showAlert.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowTextInputDialog.png" alt="Example_IosDialogManager_ShowTextInputDialog" width="400" />
</p>

#### Login dialog

- Displays a message with a username field and a password field (secure entry).

```swift
import IosLibrary

IosDialogManager.shared.showLoginDialog(
    // Set the title. If not set, no title is shown.
    title: "Login Required",
    // Set the message. If not set, no message is shown.
    message: "Please enter your credentials",
    // Set the username placeholder. If not set, "Username" is used.
    usernamePlaceholder: "Username",
    // Set the password placeholder. If not set, "Password" is used.
    passwordPlaceholder: "Password",
    // Set the login button text. If not set, "Login" is used.
    loginTitle: "Login",
    // Set the cancel button text. If not set, "Cancel" is used.
    cancelTitle: "Cancel",
    // Set whether the login button works while a field is empty. If not set, true is used.
    enableLoginWhenEmpty: false,
    // Called only when the login button is pressed. A failure goes to completion.
    onLogin: { loginButtonText, username, password, isSuccess, errorMessage in
        // username and password: what the user entered. Never log the password.
    },
    // Called when the cancel button is pressed.
    onCancel: { cancelButtonText, isSuccess, errorMessage in
        // cancelButtonText: "Cancel".
    },
    // Called once when the dialog was presented or could not be.
    completion: { isSuccess, errorMessage in
        // As for showAlert.
    }
)
```

<p align="center">
    <img src="images/ios/dialog/Example_IosDialogManager_ShowLoginDialog.png" alt="Example_IosDialogManager_ShowLoginDialog" width="400" />
</p>

#### One request, one result

- `show(_:presenter:requestBox:completion:)` shows one `DialogRequest` and calls `completion` exactly once, on the main thread, with `Result<DialogAnswer, DialogError>`. It returns the request's `RequestBox`, which `cancel(_:)` takes.
- `show(_:presenter:)` without a completion is `async throws`. It returns the `DialogAnswer` and throws a `DialogError`. When the task is canceled, the request is canceled and the call throws `CancellationError` (unless a button was pressed before).
- The defaults of a request are those of the `show...` methods. `nil` for a title, a message or a placeholder shows none.

| Request (`DialogRequest`) | Buttons (`DialogAnswer.Button`) | `DialogAnswer.input` |
|---|---|---|
| `.alert(title:message:buttonTitle:)` | `.primary` | `nil` |
| `.confirm(title:message:confirmTitle:cancelTitle:)` | `.primary`, `.cancel` | `nil` |
| `.destructive(title:message:destructiveTitle:cancelTitle:)` | `.destructive`, `.cancel` | `nil` |
| `.actionSheet(title:message:options:cancelTitle:)` | `.option(index:)`, `.cancel` | `nil` |
| `.textInput(title:message:placeholder:confirmTitle:cancelTitle:enableConfirmWhenEmpty:)` | `.primary`, `.cancel` | `.text(text)` for `.primary`, `nil` for `.cancel` |
| `.login(title:message:usernamePlaceholder:passwordPlaceholder:loginTitle:cancelTitle:enableLoginWhenEmpty:)` | `.primary`, `.cancel` | `.login(username:password:)` for `.primary`, `nil` for `.cancel` |

- `DialogAnswer.title` is the text of the pressed button, as given in the request (for `.option(index:)`, the option's text). `.option(index:)` is the index in `options`.
- `DialogInput` shows only the lengths of what was entered in its `description` (`text(length: 5)`), so printing an answer does not log what the user typed.
- An action sheet shown with `show` is anchored, on iPad, at the center of the view of the view controller it is presented from. To choose the anchor, use `showActionSheet`.
- `DialogAnswer.Button`, `DialogInput` and `DialogError` can gain cases in a later version. Write an `@unknown default` branch when you switch over them, as the sample does.

```swift
import IosLibrary

// The six kinds, with the sample's texts.
let alert: DialogRequest = .alert(title: "Request Alert", message: "Shown by show(_:presenter:)")
let confirm: DialogRequest = .confirm(title: "Request Confirm", message: "Proceed?", confirmTitle: "Yes", cancelTitle: "No")
let destructive: DialogRequest = .destructive(title: "Request Delete", message: "This cannot be undone.")
let actionSheet: DialogRequest = .actionSheet(title: "Request Sheet", message: "Choose a color", options: ["Red", "Green", "Blue"])
let textInput: DialogRequest = .textInput(title: "Request Name", message: "Enter your name", placeholder: "Your name here",
                                          enableConfirmWhenEmpty: false)
let login: DialogRequest = .login(title: "Request Login", message: "Enter your credentials", enableLoginWhenEmpty: false)

Task {
    do {
        let answer = try await IosDialogManager.shared.show(confirm, presenter: .foreground)
        switch answer.button {
        case .primary:
            // The confirm button ("Yes"). For .textInput and .login, answer.input holds what was entered.
            break
        case .cancel:
            // The cancel button ("No").
            break
        case .destructive:
            break
        case .option(let index):
            // The option at index in options.
            _ = index
        @unknown default:
            break
        }
        if case .text(let text)? = answer.input {
            // What the user entered in a text input dialog. Log its length, not the text.
            _ = text.utf8.count
        }
        if case .login(let username, let password)? = answer.input {
            // Never log the password.
            _ = (username, password)
        }
    } catch let error as DialogError {
        // .notForeground, .presentationFailed or .dismissedBySystem (see the table below).
        print(error)
    } catch {
        // CancellationError: the task was canceled, and the dialog was closed.
    }
}
```

The request ends without an answer in these cases.

| `DialogError` | When |
|---|---|
| `.canceled` | `cancel(_:)` ended the request. The `async` form throws `CancellationError` instead |
| `.notForeground` | No view controller to present from was found: the app has no window scene in the foreground, or the `.viewController(_:)` closure returned `nil` |
| `.presentationFailed` | The view controller to present from was still in a transition after waiting once, UIKit declined the presentation, or a share sheet of this library in the same window did not finish appearing within 10 seconds |
| `.dismissedBySystem` | The dialog went away without a button being pressed: other code dismissed it, or its scene was disconnected and the dialog was freed |
| `.invalidRequest` | The `RequestBox` passed in is already used by another request. The first request is not affected |

- The result is not guaranteed when the app replaces the window, its root view controller or the scene while the dialog is shown, or keeps the presented alert alive, nor when the dialog's scene is disconnected but the dialog is not freed. Cancel the request then to get its result.
- `errorDescription` of `DialogError` is a fixed English sentence, for logs. Do not show it to users as it is.

#### Choosing the view controller

- `presenter` decides which view controller the dialog is presented from. It is a `PresenterSelection`.

| `presenter` | View controller | Waiting |
|---|---|---|
| `.firstActiveScene` (default) | The topmost presented view controller of the key window of the first `foregroundActive` scene. The `show...` methods always use it | None. A dialog requested while another one is being presented is likely to end with `.presentationFailed` |
| `.foreground` | The topmost view controller that is not being dismissed, of the key window of a `foregroundActive` or `foregroundInactive` scene (`foregroundInactive`: right after launch, or while Control Center is pulled over the app) | When that view controller is in a transition, the request waits once for the transition to end. Two requests made one after the other are both shown, the second over the first |
| `.viewController(_:)` | The one the closure returns. The closure is called once, on the main thread, when the dialog is about to be presented | As for `.foreground` |

- On an iPad that shows two windows of the app side by side, both scenes can be `foregroundActive`, and `.firstActiveScene` and `.foreground` may choose the window the user is not looking at. Pass the view controller with `.viewController(_:)` there.
- `foregroundViewController()` returns the view controller `.foreground` would choose, and `getRootViewController()` the one of `.firstActiveScene`. Both are `@MainActor`.

The sample shows two alerts in the same turn of the main queue with `.foreground`; the second one appears over the first one.

```swift
import IosLibrary

for (title, button) in [("First", "First OK"), ("Second", "Second OK")] {
    IosDialogManager.shared.show(.alert(title: title, message: nil, buttonTitle: button),
                                 presenter: .foreground) { result in
        switch result {
        case .success(let answer):
            // answer.title is "First OK" or "Second OK".
            print(answer.button)
        case .failure(let error):
            print(error)
        }
    }
}
```

In a view controller of your own, pass the view controller and capture it weakly:

```swift
import IosLibrary
import UIKit

final class SettingsViewController: UIViewController {
    func confirmReset() {
        IosDialogManager.shared.show(.confirm(title: "Confirm Action", message: "Are you sure you want to proceed?"),
                                     presenter: .viewController { [weak self] in self }) { result in
            if case .success(let answer) = result, answer.button == .primary {
                // The user pressed "OK".
            }
        }
    }
}
```

#### Canceling a dialog

- `cancel(_:)` takes the box `show(_:presenter:requestBox:completion:)` returned. The request ends at once with `.failure(.canceled)` (the completion follows on the main thread), and the dialog is closed. A request that already ended is not changed.
- `cancel(_:)` may be called from any thread and does not wait.
- When another view controller is presented over the dialog, the dialog is not closed (that would close the view controller over it too). It stays until that view controller goes away, and its buttons then do nothing. The request has already ended with `.canceled`.
- To hold the box before the request starts, create it with `RequestBox()` and pass it as `requestBox`. A box canceled before its request starts makes the request end at once as `.canceled` without showing anything. A box belongs to one request: passing it to a second request ends that request with `.invalidRequest`.
- With the `async` form, cancel the `Task` instead. It throws `CancellationError`.

```swift
import IosLibrary

let box = IosDialogManager.shared.show(.alert(title: "Cancel Me", message: "Cancelled after 3 seconds"),
                                       presenter: .foreground) { result in
    // .failure(.canceled) when cancel(_:) came before a button was pressed.
    print(result)
}

// Close the dialog after 3 seconds.
DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    IosDialogManager.shared.cancel(box)
}
```

### C ABI

- The same dialogs for C, and for any language that can call a C function (C#, Dart, Rust and others). A Swift app calls `IosDialogManager` instead.
- Embed `ios-native-toolkit-capi-2.0.0.xcframework` and `ios-native-toolkit-2.0.0.xcframework`, both with **Embed & Sign** and both of the same version: the C ABI calls the Swift API. Include `<IosLibraryCApi/NativeToolkitC/Dialog.h>`, or `<NativeToolkitC/Dialog.h>` with `dist/1.14.0/ios/include` on the header search path. The requirements and the steps to add them are in [Supported platform: iOS](index.md#supported-platform-ios-device-arm64--simulator-arm64-x86_64), and the rules common to every feature in [C ABI](index.md#c-abi-1), on the manual top.
- The headers are plain C99 and include nothing but `<stddef.h>` and `<stdint.h>`. Strings are NUL-terminated UTF-8 and are checked strictly: invalid UTF-8 is rejected. A `NULL` title, message or `placeholder` shows none; any other `NULL` text takes the Swift default (`"OK"`, `"Cancel"`, `"Delete"`, `"Username"`, `"Password"`, `"Login"`).
- A request struct is filled with zeros and given its own `sizeof` in `struct_size`; the zeros are the defaults, and the `reserved` fields have to stay 0. So that the default stays zero, two flag names are the inverse of the Swift API: `confirm_disabled_when_empty` is the opposite of `enableConfirmWhenEmpty`, and `login_disabled_when_empty` the opposite of `enableLoginWhenEmpty`. Booleans are `int32_t`.
- The C ABI is asynchronous only. Every function may be called from any thread and never waits for the main thread. The return value only says whether the request was accepted. A call rejected on entry never calls the callback, and calls `release` (when it is not `NULL`) on the calling thread before it returns.
- An accepted request completes exactly once, on the main thread (the main queue), and `release` follows, exactly once. Neither runs inside the call that started the request. Called off the main thread, the completion may arrive before that call returns, before `out_request_id` is visible, so tie a completion to its request through `user_data`.
- A dialog needs a window scene in the foreground (`foregroundActive` or `foregroundInactive`, with a key window). Called while the app is in the background, a request completes with `NTK_DIALOG_ERROR_NOT_FOREGROUND`. The C ABI presents from the foreground view controller as the Swift API's `.foreground` does, so a request made while another dialog is appearing waits for it and is shown over it.
- On an iPad that shows several windows of the app side by side, which window the dialog appears on is not decided. The C ABI has no way to pass a view controller; the Swift API's `.viewController(_:)` has one. On iPad an action sheet is a popover anchored at the center of the view it is presented from, and the C ABI cannot choose another anchor.
- The `ntk_dialog_result` handed to the callback is owned by the receiver, which frees it with `ntk_dialog_result_free`, during the callback or later, on any thread. It is `NULL` unless the error is `NTK_DIALOG_ERROR_NONE`. The readers return pointers into the result that stay valid until it is freed; `out_size` may be `NULL`. `ntk_dialog_result_free(NULL)` does nothing. `system_code` and `ntk_last_system_code()` are always 0 on iOS.
- Request IDs are `uint64_t` and never reused. `ntk_dialog_cancel` takes one from any thread, does not wait, and returns `NTK_DIALOG_ERROR_NONE`. It ignores an unknown ID or a request that already completed. A dialog covered by another screen stays until that screen goes away (its buttons then do nothing), but its request still completes with `NTK_DIALOG_ERROR_CANCELED`.
- The callback and `release` may not come when the app replaces its window or root view controller while the dialog is shown, or when the system disconnects the scene and the dialog is not freed. `ntk_dialog_cancel` ends the request then.
- A callback must not block the main thread for long or let an exception escape (C++, Objective-C, a Rust panic, a C# exception).
- There is no "dismissed" answer as on Android. A tap outside an action sheet (on iPad, and on iPhone with iOS 26) is the cancel button, `NTK_DIALOG_BUTTON_NEGATIVE`. A dialog closed by other code completes with `NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM`.

#### Alert, confirmation and destructive dialogs

`ntk_dialog_result_button` tells which button was pressed, and `ntk_dialog_result_button_text` gives its text. The button values can grow in a later version: write a `default` branch.

```c
static void NTK_CALL on_dialog_result(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                      uint32_t system_code, ntk_dialog_result* result)
{
    /* On the main thread, once per accepted request. system_code is always 0 on iOS. */
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        /* result is NULL. CANCELED after ntk_dialog_cancel, CANCELED_BY_SYSTEM when other code
           closed the dialog, NOT_FOREGROUND when no scene was in the foreground,
           SHOW_FAILED when the dialog could not be presented. */
        return;
    }
    size_t size = 0;
    const char* label = ntk_dialog_result_button_text(result, &size);   /* "OK", "Yes", "Delete"... */
    switch (ntk_dialog_result_button(result)) {
    case NTK_DIALOG_BUTTON_POSITIVE:      /* the alert's button, or the confirm button */
        break;
    case NTK_DIALOG_BUTTON_NEGATIVE:      /* the cancel button */
        break;
    case NTK_DIALOG_BUTTON_DESTRUCTIVE:   /* the destructive button */
        break;
    default:
        break;
    }
    (void)label;
    /* The result belongs to the receiver. Free it here, or later on any thread. */
    ntk_dialog_result_free(result);
}

static void NTK_CALL release_user_data(void* user_data)
{
    /* Called exactly once: on the main thread after the completion, or on the calling
       thread before the call returns when the call was rejected. */
    (void)user_data;
}

/* --- Basic dialog --------------------------------------------------- */
ntk_dialog_alert_request alert;
memset(&alert, 0, sizeof(alert));
alert.struct_size = (uint32_t)sizeof(alert);
alert.title = "Hello from iOS";                   /* NULL: no title */
alert.message = "This is a native iOS dialog!";   /* NULL: no message */
alert.button_text = "OK";                         /* NULL: "OK" */

uint64_t request_id = 0;
ntk_dialog_error error = ntk_dialog_show_alert_async(&alert, &on_dialog_result, NULL,
                                                     &release_user_data, &request_id);
if (error != NTK_DIALOG_ERROR_NONE) {
    /* Rejected: the callback is never called, and release_user_data has already run. */
    return;
}

/* Later, from any thread: the dialog closes and completes with
   NTK_DIALOG_ERROR_CANCELED. A finished or unknown ID does nothing. */
ntk_dialog_cancel(request_id);

/* --- Confirmation dialog -------------------------------------------- */
ntk_dialog_confirm_request confirm;
memset(&confirm, 0, sizeof(confirm));
confirm.struct_size = (uint32_t)sizeof(confirm);
confirm.title = "Confirm Action";
confirm.message = "Are you sure you want to proceed?";
confirm.confirm_text = "Yes";                     /* NULL: "OK" */
confirm.cancel_text = "No";                       /* NULL: "Cancel" */

/* out_request_id may be NULL; the request then cannot be canceled. */
error = ntk_dialog_show_confirm_async(&confirm, &on_dialog_result, NULL, &release_user_data, NULL);

/* --- Destructive dialog --------------------------------------------- */
ntk_dialog_destructive_request destructive;
memset(&destructive, 0, sizeof(destructive));
destructive.struct_size = (uint32_t)sizeof(destructive);
destructive.title = "Delete File";
destructive.message = "This action cannot be undone. Are you sure?";
destructive.destructive_text = "Delete";          /* NULL: "Delete" */
destructive.cancel_text = "Cancel";               /* NULL: "Cancel" */

/* user_data and release may be NULL when there is nothing to free. */
error = ntk_dialog_show_destructive_async(&destructive, &on_dialog_result, NULL, NULL, NULL);
```

#### Action sheets

`ntk_dialog_result_option_index` is the index of the chosen option from 0, and -1 for any other button. `option_count` may be 0, which leaves only the cancel button; `options` must not be `NULL` when the count is not 0, and no option may be `NULL`.

```c
static void NTK_CALL on_action_sheet(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                     uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_OPTION) {
        int64_t index = ntk_dialog_result_option_index(result);          /* 0 for "Camera" */
        const char* option = ntk_dialog_result_button_text(result, NULL);
        (void)index; (void)option;
    } else {
        /* NTK_DIALOG_BUTTON_NEGATIVE: the cancel button, or a tap outside the action sheet. */
    }
    ntk_dialog_result_free(result);
}

const char* const options[] = { "Camera", "Photo Library", "Documents" };

ntk_dialog_action_sheet_request sheet;
memset(&sheet, 0, sizeof(sheet));
sheet.struct_size = (uint32_t)sizeof(sheet);
sheet.title = "Please select";
sheet.message = "Please choose an option";
sheet.options = options;
sheet.option_count = 3;
sheet.cancel_text = "Cancel";                     /* NULL: "Cancel" */

ntk_dialog_error error = ntk_dialog_show_action_sheet_async(&sheet, &on_action_sheet, NULL, NULL, NULL);
```

#### Text input and login dialogs

The text, the username and the password are read only for `NTK_DIALOG_BUTTON_POSITIVE`; for the cancel button the readers return `NULL`. They point into the result and stay valid until it is freed.

```c
static void NTK_CALL on_text_input(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                   uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        size_t size = 0;
        const char* text = ntk_dialog_result_text(result, &size);   /* UTF-8; log its size, not the text */
        (void)text;
    }
    ntk_dialog_result_free(result);
}

static void NTK_CALL on_login(void* user_data, uint64_t request_id, ntk_dialog_error error,
                              uint32_t system_code, ntk_dialog_result* result)
{
    (void)user_data; (void)request_id; (void)system_code;
    if (error != NTK_DIALOG_ERROR_NONE) {
        return;
    }
    if (ntk_dialog_result_button(result) == NTK_DIALOG_BUTTON_POSITIVE) {
        const char* username = ntk_dialog_result_username(result, NULL);
        const char* password = ntk_dialog_result_password(result, NULL);   /* never log it */
        (void)username; (void)password;
    }
    ntk_dialog_result_free(result);
}

/* --- Text input ----------------------------------------------------- */
ntk_dialog_text_input_request input;
memset(&input, 0, sizeof(input));
input.struct_size = (uint32_t)sizeof(input);
input.title = "Enter Name";
input.message = "Please enter your name";
input.placeholder = "Your name here";             /* NULL: no placeholder */
input.confirm_text = "OK";                        /* NULL: "OK" */
input.cancel_text = "Cancel";                     /* NULL: "Cancel" */
input.confirm_disabled_when_empty = 1;            /* 0: the confirm button works while empty */

ntk_dialog_error error = ntk_dialog_show_text_input_async(&input, &on_text_input, NULL, NULL, NULL);

/* --- Login ---------------------------------------------------------- */
ntk_dialog_login_request login;
memset(&login, 0, sizeof(login));
login.struct_size = (uint32_t)sizeof(login);
login.title = "Login Required";
login.message = "Please enter your credentials";
login.username_placeholder = "Username";          /* NULL: "Username" */
login.password_placeholder = "Password";          /* NULL: "Password" */
login.login_text = "Login";                       /* NULL: "Login" */
login.cancel_text = "Cancel";                     /* NULL: "Cancel" */
login.login_disabled_when_empty = 1;              /* 0: the login button works while empty */

error = ntk_dialog_show_login_async(&login, &on_login, NULL, NULL, NULL);
```

| Error | Returned or completed | Meaning |
|---|---|---|
| `NTK_DIALOG_ERROR_NONE` | Both | Accepted, or answered |
| `NTK_DIALOG_ERROR_INVALID_PARAMETER` | Returned | A `NULL` callback or request, invalid UTF-8, a `struct_size` below the 2.0.0 size or above 4096, a nonzero reserved field, `NULL` options with a nonzero count, or a `NULL` option |
| `NTK_DIALOG_ERROR_NOT_SUPPORTED` | Returned | A newer `struct_size` with nonzero fields this library does not know |
| `NTK_DIALOG_ERROR_UNKNOWN` | Completed | Not expected in 2.0.0. The log has the detail |
| `NTK_DIALOG_ERROR_CANCELED` | Completed | `ntk_dialog_cancel` (`DialogError.canceled`) |
| `NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM` | Completed | The dialog went away without a button being pressed: other code dismissed it, or its scene was disconnected and the dialog was freed (`DialogError.dismissedBySystem`) |
| `NTK_DIALOG_ERROR_NOT_FOREGROUND` | Completed | No window scene in the foreground (`DialogError.notForeground`) |
| `NTK_DIALOG_ERROR_SHOW_FAILED` | Completed | The view controller was still in a transition after waiting once, UIKit declined the presentation, or a share sheet in the same window did not finish appearing within 10 seconds (`DialogError.presentationFailed`) |

`NTK_DIALOG_ERROR_NOT_INITIALIZED` and `NTK_DIALOG_ERROR_OUT_OF_MEMORY` are declared for all platforms but never returned on iOS.

| Swift API | C ABI |
|---|---|
| `show(.alert(...))` | `ntk_dialog_show_alert_async` |
| `show(.confirm(...))` | `ntk_dialog_show_confirm_async` |
| `show(.destructive(...))` | `ntk_dialog_show_destructive_async` |
| `show(.actionSheet(...))` | `ntk_dialog_show_action_sheet_async` |
| `show(.textInput(...))` | `ntk_dialog_show_text_input_async` |
| `show(.login(...))` | `ntk_dialog_show_login_async` |
| `cancel(_:)` | `ntk_dialog_cancel` |
| `DialogAnswer.button` | `ntk_dialog_result_button`, `ntk_dialog_result_option_index` |
| `DialogAnswer.title` | `ntk_dialog_result_button_text` |
| `DialogAnswer.input` | `ntk_dialog_result_text`, `ntk_dialog_result_username`, `ntk_dialog_result_password` |
| - | `ntk_dialog_result_free` |

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
- A request struct is filled with zeros and given its own `sizeof` in `struct_size`; the zeros are the defaults. That inverts two flag names against the C++ API, so that the default stays zero: `allow_missing_file` is the opposite of `fileMustExist`, and `skip_overwrite_prompt` the opposite of `overwritePrompt`.
- A function reports its error as the return value. The raw value the OS gave is `ntk_last_system_code()`, read on the same thread right after the failure.
- Anything the library hands back is a handle that the caller frees with the matching `_free`. A pointer read out of a handle stays valid until that handle is freed.

#### Message box

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

/* The headers and the DLL have to be the same version. */
if (ntk_version() != NTK_VERSION) {
    return;
}

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
/* Optional: request.top_most = 1; request.show_help_button = 1;
   request.owner = hwnd; */

ntk_dialog_alert_result pressed = 0;
ntk_dialog_error error = ntk_dialog_show_alert(&request, &pressed);
if (error == NTK_DIALOG_ERROR_NONE) {
    /* Cancel is a button, so it is NTK_DIALOG_ALERT_RESULT_CANCEL here. */
} else if (error == NTK_DIALOG_ERROR_SYSTEM_ERROR) {
    uint32_t system_code = ntk_last_system_code();
    (void)system_code;
}
```

#### File pickers

`ntk_dialog_show_open_file` and `ntk_dialog_show_save_file` hand back one path as an `ntk_string`; `ntk_dialog_show_open_files` hands back an `ntk_string_list`, whose entries are read by index and are valid until the list is freed.

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

/* The type list. Patterns are separated by ';'. Pass NULL with a count of 0
   for every file. */
ntk_dialog_filter filters[1];
filters[0].name = "All Files";
filters[0].patterns = "*.*";

/* --- One existing file --------------------------------------------- */
ntk_dialog_file_request open_request;
memset(&open_request, 0, sizeof(open_request));
open_request.struct_size = (uint32_t)sizeof(open_request);
open_request.title = "Open File";
/* Zero means the picked file has to exist (OFN_FILEMUSTEXIST). */
open_request.allow_missing_file = 0;

ntk_string* path = NULL;
ntk_dialog_error error = ntk_dialog_show_open_file(&open_request, filters, 1, &path);
if (error == NTK_DIALOG_ERROR_NONE) {
    /* Borrowed: valid until ntk_string_free. */
    const char* utf8 = ntk_string_data(path);
    size_t size = ntk_string_size(path);
    (void)utf8; (void)size;
    ntk_string_free(path);
} else if (error == NTK_DIALOG_ERROR_CANCELED) {
    /* The user dismissed the dialog; path stays NULL. */
}

/* --- One or more existing files ------------------------------------ */
ntk_string_list* paths = NULL;
error = ntk_dialog_show_open_files(&open_request, filters, 1, &paths);
if (error == NTK_DIALOG_ERROR_NONE) {
    size_t count = ntk_string_list_count(paths);
    size_t i;
    for (i = 0; i < count; ++i) {
        size_t size = 0;
        const char* entry = ntk_string_list_at(paths, i, &size);  /* a full path */
        (void)entry; (void)size;
    }
    ntk_string_list_free(paths);
}

/* --- Where to save ------------------------------------------------- */
ntk_dialog_save_file_request save_request;
memset(&save_request, 0, sizeof(save_request));
save_request.struct_size = (uint32_t)sizeof(save_request);
save_request.title = "Save File";
save_request.default_extension = "txt";
/* Zero means the dialog asks before an existing file is picked. */
save_request.skip_overwrite_prompt = 0;

ntk_string* save_path = NULL;
error = ntk_dialog_show_save_file(&save_request, filters, 1, &save_path);
if (error == NTK_DIALOG_ERROR_NONE) {
    ntk_string_free(save_path);
}
```

#### Folder pickers

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Dialog.h>

ntk_dialog_folder_request request;
memset(&request, 0, sizeof(request));
request.struct_size = (uint32_t)sizeof(request);
/* NULL or "" leaves the system title. */
request.title = "Select Folder";

/* --- One folder ----------------------------------------------------- */
ntk_string* folder = NULL;
ntk_dialog_error error = ntk_dialog_show_pick_folder(&request, &folder);
if (error == NTK_DIALOG_ERROR_NONE) {
    const char* utf8 = ntk_string_data(folder);
    (void)utf8;
    ntk_string_free(folder);
}

/* --- One or more folders -------------------------------------------- */
request.title = "Select Folders";

ntk_string_list* folders = NULL;
error = ntk_dialog_show_pick_folders(&request, &folders);
if (error == NTK_DIALOG_ERROR_NONE) {
    size_t count = ntk_string_list_count(folders);
    size_t i;
    for (i = 0; i < count; ++i) {
        size_t size = 0;
        const char* entry = ntk_string_list_at(folders, i, &size);
        (void)entry; (void)size;
    }
    ntk_string_list_free(folders);
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
