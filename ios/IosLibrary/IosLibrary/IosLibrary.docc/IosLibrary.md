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

## Clipboard

`IosLibrary` also provides ``IosClipboardManager``, a `UIPasteboard`-backed API for copy/append,
synchronous read, metadata snapshots, named/unique pasteboard lifecycle, asynchronous
`NSItemProvider` loading, pattern detection, change observation, and a ready-to-place
`UIPasteControl` button.

### Quick Start
```swift
import IosLibrary

// Copy
try await IosClipboardManager.shared.copy(.plainText("Hello"))

// Read (may trigger an iOS 16+ permission prompt / iOS 14+ access notification; see below)
let result = try await IosClipboardManager.shared.read()

// Check without reading the body (does not trigger a prompt/notification)
let snapshot = try await IosClipboardManager.shared.snapshot()
if snapshot.hasStrings { /* show a paste affordance */ }

// A ready-to-place paste button; add the returned view to your hierarchy as-is
let pasteView = try IosClipboardManager.shared.makePasteControl(
    acceptedTypes: [UTType.plainText.identifier],
    onPaste: { items in print(items) }
)
```

### Threading
`IosClipboardManager` is `@MainActor`-isolated. Call it from the main actor; from a non-main
context use `await MainActor.run { ... }`. The Unity Bridge façade (`UnityIosClipboardManager`) is
the one entry point designed for arbitrary-thread calls — it hops to the main actor internally.

### Privacy: prompts and notifications
`read` / `readData` / `loadItem` pull data from the pasteboard and may trigger an iOS 16+
permission prompt and/or an iOS 14+ access notification, at the system's discretion. Prefer
`snapshot` for pre-checks: it is built exclusively from APIs Apple documents as avoiding both.
`UIPasteControl` (via `makePasteControl`) avoids the iOS 16+ permission prompt, but Apple does not
document it as avoiding the iOS 14+ access notification as well — verify on-device for your target
OS versions before relying on either being silent.

### Named / unique pasteboards are not persistent
A pasteboard created via `createPasteboard(.named(_:))` or `.unique` exists **only while the
creating app is running** — it is not a persistent store. Use it only to hand data from one live
app to another (e.g. via an App Group). For anything that must survive the creating app quitting,
use an App Group shared container instead; that is outside this library's scope.

### append does not carry privacy options
`append` cannot accept `ClipboardCopyOptions`, and does not guarantee that a prior `copy`'s
`localOnly` / `expirationDate` apply to the appended item. Always use `copy(_:options:)` for
sensitive data.

### Loaded files and cleanup
`loadItem(.file)` and `ClipboardPasteControlContainerView`'s `onPaste` may deliver a `.file(URL)`
whose parent temporary directory is owned by the **caller** once delivered — delete it when done.
Undelivered files (failure, cancellation, timeout) are cleaned up internally.

### Cancellation
A cancelled `loadItem` reports `isSuccess == false` with `errorCode == "CLIPBOARD_CANCELLED"` in
the callback form, or throws `ClipboardError.cancelled` in the `async throws` form; callers may
treat this as a normal, ignorable outcome. Cancelling a pending paste on
`ClipboardPasteControlContainerView` (a new paste, or the view being torn down) does **not**
invoke `onPaste` / `onPartialFailure` / `onPasteFailure` — cancellation is caller-initiated and is
never surfaced as a paste result.

### Pattern detection has no cancellation token
`detectPatterns` / `detectValues` wrap `UIPasteboard`'s `async` detection APIs, which have no
native cancellation support. A Task cancellation or internal timeout returns control to the caller
immediately, but the underlying system call may continue running in the background; its eventual
result is discarded.

### Placing the paste button
Use `IosClipboardManager.makePasteControl(...)` (preferred) or
`ClipboardPasteControlContainerView` directly: add the single returned view to your hierarchy —
its internal receiver joins the responder chain automatically. `PasteControlFactory.makeComponents`
is available for advanced cases where the button and its receiver must be placed independently; in
that case **you** are responsible for retaining and placing the receiver.

## See Also
- Unity bridge module: *UnityIosPlugin* (symbol wrappers for C#)
