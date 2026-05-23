# `UnityMacPlugin`

High‑level Unity bridge for macOS dialog presentation built on top of `MacLibrary`.

## Overview

`UnityMacPlugin` exposes the dialog and file panel functionality implemented in the Swift
`MacLibrary/MacDialogManager` to Unity (C#) or other native layers through a thin
Objective‑C / C bridge. It handles:

- Alert dialogs (`UnityMacDialogManager/showDialog(title:message:buttonsJson:optionsJson:completion:)`)
- Single & multi file pickers (open panels)
- Single & multi folder pickers
- Save file dialogs
- Suppression checkbox state reporting
- JSON → Swift option translation for alert configuration
- Safe marshaling of results back to Unity via C function callbacks

### Architecture

`UnityMacDialogManager` wraps `MacLibrary/MacDialogManager` and converts strongly typed Swift `Result`
completions into Objective‑C friendly `(NSDictionary?, NSError?)` callbacks. The C bridge functions
(defined in _UnityMacDialogManagerBridge.h / .m_) further flatten those into plain C primitives so they can be
consumed with P/Invoke (`[DllImport("__Internal")]`) from Unity C# code. A managed helper (`MacDialogManager` C# MonoBehaviour)
exposes idiomatic events, performs marshaling, and handles memory cleanup.

Layering:

```
Unity C# (MacDialogManager.cs)
   ↓ (P/Invoke / DllImport)
C Bridge (UnityMacDialogManagerBridge.*)
   ↓ (Objective‑C → Swift)
UnityMacDialogManager (Swift facade)
   ↓
MacDialogManager (Core logic)
   ↓
AppKit (NSAlert / NSOpenPanel / NSSavePanel)
```

### Result Dictionaries

Each dialog type returns a dictionary with well‑defined keys (all values are Foundation bridged types):

| Dialog Type                             | Keys                                                                                               |
| --------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Alert                                   | `buttonTitle:String`, `buttonIndex:Int`, `suppressionButtonState:Bool`                             |
| File / MultiFile / Folder / MultiFolder | `filePaths:[String]`, `fileCount:Int`, `directoryURL:String`, `isCancelled:Bool`, `isSuccess:Bool` |
| Save                                    | `filePath:String`, `fileCount:Int`, `directoryURL:String`, `isCancelled:Bool`, `isSuccess:Bool`    |

Error cases provide an `NSError` whose `localizedDescription` mirrors `MacLibrary/DialogError` text.

### Cancellation Semantics

Cancellation is reported as `isCancelled == true` while still treating the operation as logically successful (`isSuccess == true`)—it is a user choice, not a failure. Runtime issues (configuration errors, unexpected failures) set `isSuccess == false` and provide an `NSError`.

### Alert JSON Schema

`buttonsJson` example:

```json
{
  "buttons": [
    { "title": "OK", "isDefault": true, "keyEquivalent": "" },
    { "title": "Cancel" }
  ]
}
```

`optionsJson` example:

```json
{
  "alertStyle": "warning",
  "showsSuppressionButton": true,
  "suppressionButtonTitle": "Do not show again"
}
```

`alertStyle` accepts: `informational` | `warning` | `critical`.

### File & Folder Selection

File filters are passed as an array of filename extensions (no leading dot) and converted to `UTType`s in Swift. Folder dialogs disable file selection flags and invert selection logic accordingly.

### Save Panel

The save dialog returns a single path. `fileCount` remains for structural symmetry (1 on success, 0 if cancelled).

### Threading

All public functions are safe to call from any thread. UI work is dispatched onto the main queue by the underlying manager. The C# wrapper enqueues callbacks back to Unity's main thread (via a dispatcher) before firing events.

### Memory & Lifetime Notes

C callback string pointers reference autoreleased NSStrings valid only during the execution of the callback. The Unity C# wrapper copies them (`Marshal.PtrToStringUTF8`) into managed strings immediately. Caller code only receives safe managed data.

---

## Unity C# Wrapper (MacDialogManager.cs)

The provided sample `MacDialogManager` MonoBehaviour offers:

- Lazy singleton creation (`Instance` property); object is marked `DontDestroyOnLoad`.
- Event-based result delivery for each dialog type:
  - `AlertDialogResult(string? buttonTitle, int buttonIndex, bool suppressionState, bool isSuccess, string? errorMessage)`
  - `FileDialogResult(string[]? filePaths, int fileCount, string? directoryURL, bool isCancelled, bool isSuccess, string? errorMessage)`
  - `MultiFileDialogResult(…)`
  - `FolderDialogResult(…)`
  - `MultiFolderDialogResult(…)`
  - `SaveFileDialogResult(string? filePath, int fileCount, string? directoryURL, bool isCancelled, bool isSuccess, string? errorMessage)`
- Validation (title, buttons/options presence) with early error event emission.
- Explicit unmanaged memory allocation & guaranteed release inside callback (even on error) for content type arrays.
- Main‑thread dispatch for all event invocations.

### C# Alert Usage

```csharp
var buttons = new [] {
    new DialogButton { title = "OK", isDefault = true },
    new DialogButton { title = "Cancel" }
};
var options = new DialogOptions { alertStyle = "informational", showsSuppressionButton = true, suppressionButtonTitle = "Do not show again" };
MacDialogManager.Instance.AlertDialogResult += (title, index, suppression, success, err) => {
    if (success) Debug.Log($"Pressed {title} (index {index}) suppression={suppression}");
    else Debug.LogError(err);
};
MacDialogManager.Instance.ShowDialog("Example", "Choose an option", buttons, options);
```

### C# Single File Dialog

```csharp
MacDialogManager.Instance.FileDialogResult += (paths, count, dir, cancelled, success, err) => {
    if (!success) { Debug.LogError(err); return; }
    if (cancelled) Debug.Log("User cancelled"); else Debug.Log(string.Join("\n", paths));
};
MacDialogManager.Instance.ShowFileDialog("Select File", "Pick a single file", new [] { "txt", "md" });
```

### C# Multi File Dialog

```csharp
MacDialogManager.Instance.MultiFileDialogResult += (paths, count, dir, cancelled, success, err) => {
    if (success && !cancelled) Debug.Log($"Selected {count} files");
};
MacDialogManager.Instance.ShowMultiFileDialog("Select Files", "Choose multiple", new [] { "png", "jpg" });
```

### C# Folder & Multi Folder

```csharp
MacDialogManager.Instance.FolderDialogResult += (paths, count, dir, cancelled, success, err) => {
    if (success && !cancelled) Debug.Log($"Folder: {paths?[0]}");
};
MacDialogManager.Instance.ShowFolderDialog("Select Folder", "Choose a folder");

MacDialogManager.Instance.MultiFolderDialogResult += (paths, count, dir, cancelled, success, err) => {
    if (success && !cancelled) Debug.Log($"Folders: {string.Join(", ", paths ?? Array.Empty<string>())}");
};
MacDialogManager.Instance.ShowMultiFolderDialog("Select Folders", "Choose multiple folders");
```

### C# Save File Dialog

```csharp
MacDialogManager.Instance.SaveFileDialogResult += (path, count, dir, cancelled, success, err) => {
    if (success && !cancelled) Debug.Log($"Save path: {path}");
};
MacDialogManager.Instance.ShowSaveFileDialog("Save File", "Provide a location", "sample.txt", new [] { "txt" });
```

### Events Lifecycle Notes

- Subscribe **before** invoking the corresponding `Show*` method to avoid race conditions if a dialog closes quickly (rare but possible).
- Unsubscribe when no longer needed to avoid memory leaks in long‑running editor sessions.
- Multiple listeners are supported; each is invoked sequentially.

---

## C Bridge Mapping

| C Function              | C# DllImport Signature (Simplified)                                                      | Managed Invoke Method        | Result Event              |
| ----------------------- | ---------------------------------------------------------------------------------------- | ---------------------------- | ------------------------- |
| `showDialog`            | `void showDialog(string,string,string,string,DialogCallback)`                            | `ShowDialog(...)`            | `AlertDialogResult`       |
| `showFileDialog`        | `void showFileDialog(string,string,IntPtr,int,string,FileDialogCallback)`                | `ShowFileDialog(...)`        | `FileDialogResult`        |
| `showMultiFileDialog`   | `void showMultiFileDialog(string,string,IntPtr,int,string,MultiFileDialogCallback)`      | `ShowMultiFileDialog(...)`   | `MultiFileDialogResult`   |
| `showFolderDialog`      | `void showFolderDialog(string,string,string,FolderDialogCallback)`                       | `ShowFolderDialog(...)`      | `FolderDialogResult`      |
| `showMultiFolderDialog` | `void showMultiFolderDialog(string,string,string,MultiFolderDialogCallback)`             | `ShowMultiFolderDialog(...)` | `MultiFolderDialogResult` |
| `showSaveFileDialog`    | `void showSaveFileDialog(string,string,string,IntPtr,int,string,SaveFileDialogCallback)` | `ShowSaveFileDialog(...)`    | `SaveFileDialogResult`    |

### Memory Safety in C# Wrapper

- Each `string[] allowedContentTypes` element is marshalled as an individual unmanaged UTF‑8 buffer + NULL terminator.
- A contiguous pointer array is allocated and passed to the C bridge.
- Cleanup occurs inside the callback’s `finally` block after the Unity main thread event dispatch, ensuring no premature free.
- On exceptions during setup, allocated buffers are freed before emitting an error event.

### Error Patterns

| Condition           | Emitted Event Values                                                       | Notes                              |
| ------------------- | -------------------------------------------------------------------------- | ---------------------------------- |
| Empty title         | `buttonIndex / fileCount = -1`, `isSuccess=false`, error message populated | Validation short‑circuit           |
| No buttons (alert)  | `buttonIndex = -1`, `isSuccess=false`                                      | `DialogError.noButtons` equivalent |
| User cancel (panel) | `isCancelled=true`, `isSuccess=true`                                       | Not an error                       |
| Runtime failure     | `isSuccess=false`, error message                                           | Underlying Swift error             |

### Suppression Checkbox

If `showsSuppressionButton=true` and the user checks it, `suppressionButtonState` is `true` in the alert callback—persist preference in your own config (e.g. PlayerPrefs / JSON file).

### Localization

All strings are caller‑supplied; localize before passing into the plugin if your game supports multiple languages.

### Testing Tips

- Use Console.app (filter by subsystem/category if you wrap `Log`) or Xcode debug console to inspect native logging.
- Simulate cancellation paths early (press ESC or click Cancel).
- Provide invalid JSON intentionally to verify graceful error handling (ensure you restore correct JSON afterward).

### Extensibility

To add a new dialog category:

1. Extend `MacLibrary/MacDialogManager`.
2. Add a Swift bridging method in `UnityMacDialogManager` that flattens the result to `NSDictionary`.
3. Add a C bridge function + C typedef.

### Notification Bridge

- `UnityMacNotificationManager`
- `UnityMacNotificationJsonParser`

4. Extend `MacDialogManager.cs` with DllImport, delegate, event, and a public `Show*` method.
5. Update this document & provide new C# usage examples.

---

## Quick Start (Unity C#)

(See expanded examples above.) Minimal alert recap:

```csharp
MacDialogManager.Instance.AlertDialogResult += (t,i,s,ok,err)=>Debug.Log($"Pressed {t} idx={i} ok={ok}");
MacDialogManager.Instance.ShowDialog(
    "Hello",
    "From Unity",
    new[]{ new DialogButton{ title="OK", isDefault=true }, new DialogButton{ title="Cancel" } },
    new DialogOptions{ alertStyle="informational" }
);
```
