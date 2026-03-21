# Module android_library

Core Android UI / system helper module providing both a versatile `AndroidDialogFragment` and a comprehensive notification toolkit used directly or through higher-level Unity bridge modules.

## Notification Architecture

The notification module follows a clean layered structure:

- `android.library.notification.domain.model`
  - Pure notification models split by responsibility:
    - `NotificationChannel.kt`
    - `NotificationProgress.kt`
    - `NotificationMessage.kt`
    - `NotificationStyle.kt`
    - `NotificationContent.kt`
    - `NotificationSchedule.kt`
    - `ActiveNotification.kt`
- `android.library.notification.application.model`
  - Android-facing command types such as `AndroidNotificationCommand`
- `android.library.notification.application.port`
  - `NotificationCommandRepository.kt`
  - `AndroidNotificationRuntimeRepository.kt`
- `android.library.notification.application.usecase`
  - `NotificationDispatchUseCases.kt`
  - `NotificationChannelUseCases.kt`
  - `NotificationScheduleUseCases.kt`
  - `NotificationQueryUseCases.kt`
  - `ForegroundNotificationUseCases.kt`
- `android.library.notification.data.repository`
  - Android-specific implementations and payload mapping
- `android.library.notification.presentation.permission`
  - UI permission helper for Android 13+

### Legacy status

Legacy notification files have been physically removed. The notification module now exposes only the new `domain.model`, `application.*`, `presentation.permission`, and `data.repository.NotificationRepositoryImpl` APIs.

## Notification Toolkit

The module includes support for:
- Android 13+ notification permission check / request helper
- Notification channel create / batch create / delete
- Immediate notification send / update / cancel / cancel all
- Group notifications and group summary notifications
- Action buttons and content / delete / full-screen intents
- Styles: default, big text, inbox, big picture, messaging
- Progress notifications
- Foreground notification start / update / stop
- Scheduled notifications via `AlarmManager`
- Re-scheduling persisted notifications after reboot / package replace
- Active notification inspection

### Main entry points
- `NotificationRepositoryImpl`
- `AndroidNotificationCommand`
- `NotificationContent`
- `NotificationChannel`
- `NotificationSchedule`
- `ShowNotificationUseCase`
- `CreateNotificationChannelUseCase`
- `ScheduleNotificationUseCase`
- `StartForegroundNotificationUseCase`
- `android.library.notification.presentation.permission.NotificationPermissionHelper`

### Notification quick example
```kotlin
val repository = NotificationRepositoryImpl(context)

CreateNotificationChannelUseCase(repository)(
    NotificationChannel(
        id = "updates",
        name = "Updates",
        description = "General update notifications"
    )
)

ShowNotificationUseCase(repository)(
    AndroidNotificationCommand(
        content = NotificationContent(
            id = 1001,
            title = "Native Toolkit",
            message = "Notification system is ready.",
            channel = NotificationChannel(
                id = "updates",
                name = "Updates"
            ),
            style = NotificationStyle.BigText(
                bigText = "Native Toolkit notification system is ready and supports rich styles.",
                summaryText = "Ready"
            )
        )
    )
)
```

### Scheduling example
```kotlin
ScheduleNotificationUseCase(repository)(
    command = AndroidNotificationCommand(
        content = NotificationContent(
            id = 2001,
            title = "Scheduled",
            message = "This was scheduled in advance.",
            channel = NotificationChannel(
                id = "updates",
                name = "Updates"
            )
        )
    ),
    schedule = NotificationSchedule(
        triggerAtMillis = System.currentTimeMillis() + 60_000L,
        exact = true,
        allowWhileIdle = true,
        persistAcrossBoot = true
    )
)
```

### Manifest integration notes
- `POST_NOTIFICATIONS` is declared for Android 13+
- `RECEIVE_BOOT_COMPLETED` is declared for restoring persisted schedules
- `SCHEDULE_EXACT_ALARM` is declared for exact scheduling support
- Internal broadcast receivers are declared for scheduled delivery and reboot restore

---

## Dialog Toolkit

Core versatile dialog implementation providing a multi-pattern `AndroidDialogFragment`, used directly or through higher‑level Unity bridge modules.

## Overview
`AndroidDialogFragment` is a single class that can render six dialog variants via multiple `newInstance` factory overloads. After creation you attach the appropriate listener interface for the desired variant.

## Supported Variants
1. Simple: single OK button
2. Confirm: Negative / Positive (e.g. No / Yes)
3. Single Choice: radio list + OK / Cancel
4. Multi Choice: checkbox list + OK / Cancel
5. Text Input: single line input (optional empty gating)
6. Login: username + password fields (optional empty gating on both)

## Key Features
- Dedicated factory overload for each variant: `newInstance(...)`
- Unified AlertDialog-based implementation for list / input / confirmation patterns
- Dynamic positive button enable/disable for TextInput / Login (when `enablePositiveButtonWhenEmpty = false`)
- Control outside-tap and back-press cancellation (`cancelableOnTouchOutside`, `cancelable`)
- Separate listener interfaces (callback skipped if not set):
  - `DialogListener` (Simple)
  - `ConfirmDialogListener`
  - `SingleChoiceItemDialogListener`
  - `MultiChoiceItemDialogListener`
  - `TextInputDialogListener`
  - `LoginDialogListener`
- Cancellation still invokes the corresponding listener with a "Cancel" style buttonText and empty / default payload
- All construction parameters persisted in a Bundle to survive configuration changes (e.g. rotation)

## Factory Summary
(All are overloads of `AndroidDialogFragment.newInstance(...)`)

- Simple  
  `(title, message, buttonText = "OK", cancelableOnTouchOutside = true, cancelable = true)`
- Confirm  
  `(title, message, negativeButtonText = "No", positiveButtonText = "Yes", cancelableOnTouchOutside = true, cancelable = true)`
- Single Choice  
  `(title, singleChoiceItems: Array<String>, checkedItem = 0, negativeButtonText = "Cancel", positiveButtonText = "OK", cancelableOnTouchOutside = true, cancelable = true)`
- Multi Choice  
  `(title, multiChoiceItems: Array<String>, checkedItems: BooleanArray, negativeButtonText = "Cancel", positiveButtonText = "OK", cancelableOnTouchOutside = true, cancelable = true)`
- Text Input  
  `(title, message, hint, negativeButtonText = "Cancel", positiveButtonText = "OK", enablePositiveButtonWhenEmpty = false, cancelableOnTouchOutside = true, cancelable = true)`
- Login  
  `(title, message, usernameHint, passwordHint, negativeButtonText = "Cancel", positiveButtonText = "OK", enablePositiveButtonWhenEmpty = false, cancelableOnTouchOutside = true, cancelable = true)`

## Listener Interfaces
```kotlin
interface DialogListener {
    fun onDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?)
}
interface ConfirmDialogListener {
    fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?)
}
interface SingleChoiceItemDialogListener {
    fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItem: Int?, isSuccessful: Boolean, errorMessage: String?)
}
interface MultiChoiceItemDialogListener {
    fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?)
}
interface TextInputDialogListener {
    fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?)
}
interface LoginDialogListener {
    fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?)
}
```
Notes:
- Selection / input payloads are only populated when the positive button is pressed; on cancel they may be null / empty.
- `isSuccessful` is reserved for internal error reporting (current implementation usually returns `true` on normal paths).

## Usage Examples

### Simple
```kotlin
AndroidDialogFragment.newInstance(
    title = "Notice",
    message = "Operation completed"
).apply {
    setDialogListener(object : AndroidDialogFragment.DialogListener {
        override fun onDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
            // OK or Cancel
        }
    })
}.show(supportFragmentManager, "SimpleDialog")
```

### Confirm
```kotlin
AndroidDialogFragment.newInstance(
    title = "Delete",
    message = "Are you sure?",
    negativeButtonText = "No",
    positiveButtonText = "Yes"
).apply {
    setConfirmDialogListener(object : AndroidDialogFragment.ConfirmDialogListener {
        override fun onConfirmDialog(dialog: AndroidDialogFragment, buttonText: String?, isSuccessful: Boolean, errorMessage: String?) {
            if (buttonText == "Yes") { /* proceed */ }
        }
    })
}.show(supportFragmentManager, "ConfirmDialog")
```

### Single Choice
```kotlin
AndroidDialogFragment.newInstance(
    title = "Color",
    singleChoiceItems = arrayOf("Red","Green","Blue"),
    checkedItem = 0
).apply {
    setSingleChoiceItemDialogListener(object : AndroidDialogFragment.SingleChoiceItemDialogListener {
        override fun onSingleChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItem: Int?, isSuccessful: Boolean, errorMessage: String?) {
            if (buttonText == "OK" && checkedItem != null) { /* use index */ }
        }
    })
}.show(supportFragmentManager, "SingleChoiceDialog")
```

### Multi Choice
```kotlin
AndroidDialogFragment.newInstance(
    title = "Tags",
    multiChoiceItems = arrayOf("A","B","C"),
    checkedItems = booleanArrayOf(false, true, false)
).apply {
    setMultiChoiceItemDialogListener(object : AndroidDialogFragment.MultiChoiceItemDialogListener {
        override fun onMultiChoiceItemDialog(dialog: AndroidDialogFragment, buttonText: String?, checkedItems: BooleanArray?, isSuccessful: Boolean, errorMessage: String?) {
            if (buttonText == "OK" && checkedItems != null) { /* use states */ }
        }
    })
}.show(supportFragmentManager, "MultiChoiceDialog")
```

### Text Input
```kotlin
AndroidDialogFragment.newInstance(
    title = "Input",
    message = "Enter name",
    hint = "Name",
    enablePositiveButtonWhenEmpty = false
).apply {
    setTextInputDialogListener(object : AndroidDialogFragment.TextInputDialogListener {
        override fun onTextInputDialog(dialog: AndroidDialogFragment, buttonText: String?, inputText: String?, isSuccessful: Boolean, errorMessage: String?) {
            if (buttonText == "OK" && !inputText.isNullOrEmpty()) { /* use text */ }
        }
    })
}.show(supportFragmentManager, "TextInputDialog")
```

### Login
```kotlin
AndroidDialogFragment.newInstance(
    title = "Sign In",
    message = "Enter credentials",
    usernameHint = "Username",
    passwordHint = "Password"
).apply {
    setLoginDialogListener(object : AndroidDialogFragment.LoginDialogListener {
        override fun onLoginDialog(dialog: AndroidDialogFragment, buttonText: String?, username: String?, password: String?, isSuccessful: Boolean, errorMessage: String?) {
            if (buttonText == "OK") { /* authenticate */ }
        }
    })
}.show(supportFragmentManager, "LoginDialog")
```

## Cancellation Behavior
- Back press or (if allowed) outside tap triggers `onCancel`, which then invokes the corresponding listener with a "Cancel" style buttonText.
- Single / Multi choice dialogs pass the last tracked selection state (index or boolean array) even on cancel.

## Threading
Must be invoked on the Android main (UI) thread. The `show` call on the FragmentManager should not be dispatched from a background thread.

## Error Handling
Currently throws when fundamental preconditions fail (e.g. Activity is null). Future enhancements could convert such failures into callbacks with `isSuccessful = false`.

## Integration Notes
- A JNI / Unity bridge can map each listener to managed callbacks, dispatching by variant.
- Positive button enablement for TextInput / Login is driven by `enablePositiveButtonWhenEmpty` plus a TextWatcher updating state in real time.

## Dokka
```
./gradlew :android_library:clean :android_library:dokkaHtml
```
Output: `android_library/build/dokka/html`
