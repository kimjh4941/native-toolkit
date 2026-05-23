# `MacLibrary`

A lightweight utility library providing unified macOS dialog presentation (alerts, open/save panels) and structured logging helpers.

## Overview

`MacLibrary` offers a single façade `MacDialogManager` that wraps:

- `NSAlert` configurable alert dialogs
- `NSOpenPanel` based file / folder pickers (single & multi‑selection)
- `NSSavePanel` based save dialogs
- Strongly typed option & result value types
- Unified error reporting via `DialogError`
- A minimal `Log` helper built on Apple’s Unified Logging (`os.Logger`)

All UI presentation is marshalled onto the main thread internally; your call sites may invoke the API from background threads. Each async style API uses a `Result<..., DialogError>` completion closure (bridged to Objective‑C / Unity via dictionary + `NSError`).

### Core Principles

1. **Type Safety** – Explicit option / result structs (`DialogOptions`, `OpenDialogOptions`, `SaveDialogResult`, etc.)
2. **Deterministic Ordering** – Button indices reflect declaration order.
3. **Non‑Blocking Simplicity** – Main thread dispatch handled for you.
4. **Bridge Friendly** – Structures are flattened when crossing into Objective‑C / C.
5. **Clarity** – DocC & inline documentation for every public symbol.

### Threading

All public APIs are safe to call from any thread. UI work is executed on the main queue.

### Errors

`DialogError` enumerates configuration and runtime issues. A failure short‑circuits the completion with `.failure(error)`.

## Quick Start

```swift
import MacLibrary

MacDialogManager.shared.showDialog(title: "Info", message: "Operation finished") { result in
    switch result {
    case .success(let r):
        print("Button index:", r.buttonIndex, "title:", r.buttonTitle)
    case .failure(let e):
        print("Alert failed:", e.localizedDescription)
    }
}
```

Selecting multiple files:

```swift
MacDialogManager.shared.showMultiFileDialog(
    title: "Select Assets",
    message: "Choose one or more images",
    allowedContentTypes: ["png", "jpg"]
) { result in
    switch result {
    case .success(let r) where !r.isCancelled:
        print("Chosen paths:\n", r.filePaths.joined(separator: "\n"))
    case .success:
        print("User cancelled")
    case .failure(let e):
        print("Open panel failed:", e.localizedDescription)
    }
}
```

Saving a file:

```swift
MacDialogManager.shared.showSaveFileDialog(
    title: "Save Report",
    nameFieldStringValue: "report.txt",
    allowedContentTypes: ["txt"]
) { result in
    if case .success(let r) = result, !r.isCancelled {
        print("Save to:", r.filePath)
    }
}
```

## Topics

### Manager

- `MacDialogManager`

### Alerts

- `DialogButton`
- `DialogOptions`
- `DialogResult`
- `DialogError`
- `MacDialogManager/showDialog(title:message:options:completion:)`

### Open Panels (Files & Folders)

- `OpenDialogOptions`
- `OpenDialogResult`
- `MacDialogManager/showOpenDialog(title:message:options:completion:)`
- `MacDialogManager/showFileDialog(title:message:allowedContentTypes:directoryURL:completion:)`
- `MacDialogManager/showMultiFileDialog(title:message:allowedContentTypes:directoryURL:completion:)`
- `MacDialogManager/showFolderDialog(title:message:directoryURL:completion:)`
- `MacDialogManager/showMultiFolderDialog(title:message:directoryURL:completion:)`

### Save Panel

- `SaveDialogResult`
- `MacDialogManager/showSaveFileDialog(title:message:nameFieldStringValue:allowedContentTypes:directoryURL:completion:)`

### Logging

- `Log`

### Design Notes

- Button indices are zero‑based and map directly to order supplied in `DialogOptions/buttons`.
- `suppressionButtonState` is `true` only if a suppression checkbox was shown **and** checked.
- A cancelled open or save panel returns `isCancelled == true` while still reporting `isSuccess == true` (logical success, user choice).
- Save panel returns at most one path; `fileCount` kept for structural symmetry.

### Privacy & Security

Do not log sensitive data via `Log`. All messages use `.public` privacy.

### Extensibility

Add custom UI (e.g. accessory views) by extending `DialogOptions` / wrapping new functionality in `MacDialogManager` or a dedicated manager facade.

### Notification

- `MacNotificationManager`
- `NotificationContent`
- `NotificationTrigger`
- `NotificationCategory`
- `NotificationAction`
- `NotificationAuthorizationStatus`
- `ActiveNotification`
- `ScheduledNotification`
- `NotificationDomainError`
- `BridgeError`
