# ``IosLibrary``

A lightweight dialog presentation utility wrapping `UIAlertController` patterns (alerts, confirmation, destructive actions, action sheets, single text input and login style prompts) with a unified callback model.

## Overview
`IosLibrary` centralizes dialog logic inside ``IosDialogManager``. It focuses on:

- **Consistency** – All helpers normalize completion signatures to `(result, isSuccess, errorMessage)` or extensions thereof.
- **Safety** – Always marshals to the main queue before touching UIKit.
- **iPad Compatibility** – Handles popover configuration (source view / rect / bar button) with graceful fallback.
- **Input Validation** – Optional automatic disabling of confirm / login buttons until required fields are non‑empty.
- **Extensibility** – Public generic `showDialog` underpins higher‑level helpers.

## Quick Start
```swift
import IosLibrary

// Simple alert
IosDialogManager.shared.showAlert(title: "Notice", message: "Operation finished") { button, ok, error in
    guard ok else { print(error ?? "Unknown error"); return }
    print("User tapped: \(button ?? "?")")
}

// Confirmation
IosDialogManager.shared.showConfirmDialog(
    title: "Confirm",
    message: "Proceed with action?",
    confirmTitle: "Proceed",
    cancelTitle: "Cancel",
    onConfirm: { _, _, _ in print("Confirmed") },
    onCancel:  { _, _, _ in print("Cancelled") }
)

// Text input with validation (disables OK until text entered)
IosDialogManager.shared.showTextInputDialog(
    title: "Enter Name",
    message: "Please input your display name",
    placeholder: "Name",
    confirmTitle: "OK",
    cancelTitle: "Cancel",
    enableConfirmWhenEmpty: false,
    onConfirm: { _, text, _, _ in print("Name: \(text ?? "")") },
    onCancel: { _, _, _ in }
)
```

## Features
- Unified API surface via ``IosDialogManager``
- Alerts, confirmations, destructive dialogs
- Action sheets (iPhone & iPad popover support)
- Single text input + validation
- Login (username + password) dialog + validation
- Generic builder `showDialog` for custom compositions
- Thread‑safe (main queue dispatch)
- Clear error reporting when presentation preconditions fail

## Error Handling
`isSuccess == false` indicates a *pre‑presentation* failure (e.g. unable to resolve a root view controller). User cancellation is still reported with `isSuccess == true` and a button label.

`errorMessage` is only non‑nil when `isSuccess == false`.

## Thread Safety
Public APIs can be called from any thread; presentation is dispatched to the main thread internally.

## Input Validation
`showTextInputDialog` and `showLoginDialog` accept `enableConfirmWhenEmpty` / `enableLoginWhenEmpty` flags. When `false`, the primary action is disabled until the relevant field(s) contain non‑empty text.

## Destructive Actions
`showDestructiveDialog` renders a `.destructive` button (red) alongside a cancel action. Use descriptive labels (e.g. "Delete", "Remove") for clarity.

## Callbacks
- **result / button title** – Title of the tapped button (may be `nil` only on pre‑presentation failure)
- **input values** – Present only when confirm/login succeeded
- **isSuccess** – False only for infrastructure failures
- **errorMessage** – Diagnostic message when `isSuccess == false`

## Unity Integration
A separate module *UnityIosPlugin* provides a C / Objective‑C bridge and Swift façade so Unity (C#) can invoke these dialogs. See that module for P/Invoke signatures.

## Versioning
Follow semantic versioning. Backwards compatible additions (new methods / parameters with defaults) increment the minor version; breaking changes increment the major version.

## Topics

### Core Manager
- ``IosDialogManager``
- ``IosDialogManager/showDialog(title:message:preferredStyle:actions:textFields:sourceView:sourceRect:barButtonItem:permittedArrowDirections:animated:completion:)``
- ``IosDialogManager/getRootViewController()``

### Alerts
- ``IosDialogManager/showAlert(title:message:buttonText:completion:)``
- ``IosDialogManager/showConfirmDialog(title:message:confirmTitle:cancelTitle:onConfirm:onCancel:)``
- ``IosDialogManager/showDestructiveDialog(title:message:destructiveTitle:cancelTitle:onDestructive:onCancel:)``

### Action Sheets
- ``IosDialogManager/showActionSheet(title:message:actions:sourceView:sourceRect:animated:completion:)``

### Text & Login Input
- ``IosDialogManager/showTextInputDialog(title:message:placeholder:confirmTitle:cancelTitle:enableConfirmWhenEmpty:onConfirm:onCancel:)``
- ``IosDialogManager/showLoginDialog(title:message:usernamePlaceholder:passwordPlaceholder:loginTitle:cancelTitle:enableLoginWhenEmpty:onLogin:onCancel:)``

## See Also
- Unity bridge module: *UnityIosPlugin* (symbol wrappers for C#)
