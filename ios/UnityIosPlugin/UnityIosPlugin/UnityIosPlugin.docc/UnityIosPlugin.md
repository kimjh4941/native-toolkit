# ``UnityIosPlugin``

High-level Unity‑facing bridge for native iOS dialogs. Wraps the Swift ``UnityIosDialogManager`` (which itself delegates to ``IosLibrary/IosDialogManager``) plus a stable C ABI (Objective‑C bridge) so C# (P/Invoke) code in Unity can present alerts, confirmations, destructive prompts, action sheets, single text input, and login dialogs.

## Overview
`UnityIosPlugin` provides:

- **Swift Facade**: ``UnityIosDialogManager`` unifies callback shapes for all dialog types.
- **C Bridge Layer**: Plain C functions (declared in `UnityIosDialogManagerBridge.h`) export a minimal, version‑friendly ABI for Unity.
- **Consistent Results**: Each callback ends with `(isSuccess, errorMessage)`; user cancellation is considered a successful interaction (not an error).
- **Validation Support**: Text & login dialogs can disable confirm/login buttons until required fields contain text.
- **NULL Semantics**: Optional strings return `NULL` (not empty) when absent; Unity must NULL‑check pointers before UTF‑8 conversion.

## Architecture
```
Unity C#  --P/Invoke-->  C Bridge (C/ObjC)  -->  Swift UnityIosDialogManager  -->  IosDialogManager (IosLibrary)  -->  UIKit (UIAlertController)
```

1. **Unity C# Layer** defines `DllImport("__Internal")` signatures for each C bridge function.
2. **Bridge C Functions** perform UTF‑8 conversion, call Swift facade, and pass raw C string pointers back through callbacks.
3. **Swift Facade** normalizes result tuples and delegates actual UI work to the reusable `IosDialogManager`.
4. **UIKit** presents `UIAlertController` safely on the main thread.

## Unity C# Integration Details
The provided Unity manager (`IosDialogManager` MonoBehaviour in C#) implements:

- **Lazy Singleton** with persistent GameObject (`DontDestroyOnLoad`).
- **Event-Based Result Propagation** for each dialog category (Alert / Confirm / Destructive / ActionSheet / TextInput / Login).
- **IL2CPP-Compatible Delegates** decorated with `[UnmanagedFunctionPointer(CallingConvention.Cdecl)]` and `[MonoPInvokeCallback]`.
- **Unified Event Signatures** adding `isSuccess` + `errorMessage` to every result.
- **Memory Management for ActionSheet Options**: Allocates unmanaged UTF‑8 strings + array of pointers, frees them in the action sheet callback `finally` block.
- **Thread Marshaling**: Dispatches back to main Unity thread via `UnityMainThreadDispatcher.Instance.Enqueue` (ensure dispatcher implementation is present in the project).

### C# Singleton Pattern (Excerpt)
```csharp
public static IosDialogManager Instance {
    get {
        if (_instance == null) {
            var go = new GameObject("IosDialogManager");
            _instance = go.AddComponent<IosDialogManager>();
            DontDestroyOnLoad(go);
        }
        return _instance;
    }
}
```

### C# Native Function Imports (Excerpt)
```csharp
[DllImport("__Internal", CallingConvention = CallingConvention.Cdecl)]
private static extern void showDialog(string title, string message, string buttonText, DialogCallback callback);

[DllImport("__Internal", CallingConvention = CallingConvention.Cdecl)]
private static extern void showTextInputDialog(string title, string message, string placeholder,
    string confirmButtonText, string cancelButtonText, bool enableConfirmWhenEmpty, TextInputDialogCallback callback);
```

### Callback & Event Mapping
| Native Function | C# Delegate | Unity Event | Notes |
|-----------------|-------------|-------------|-------|
| `showDialog` | `DialogCallback` | `DialogResult` | Single button alert |
| `showConfirmDialog` | `ConfirmDialogCallback` | `ConfirmDialogResult` | Confirm / Cancel |
| `showDestructiveDialog` | `DestructiveDialogCallback` | `DestructiveDialogResult` | Destructive / Cancel |
| `showActionSheet` | `ActionSheetCallback` | `ActionSheetResult` | Options + Cancel; frees unmanaged memory in callback |
| `showTextInputDialog` | `TextInputDialogCallback` | `TextInputDialogResult` | Single input field |
| `showLoginDialog` | `LoginDialogCallback` | `LoginDialogResult` | Username + Password |

### NULL vs Empty in C# Layer
The bridge now forwards *raw* NULL pointers (no empty string substitution). In the C# layer the signatures already accept managed `string?`; if you need to differentiate, check for `null` before usage. Always treat `isSuccess == false` as infrastructure failure (presentation issue). User cancellation sets `isSuccess == true` and returns the cancel button label.

### Action Sheet Unmanaged Memory Lifecycle
1. Allocate per option: UTF‑8 bytes + null terminator.
2. Allocate pointer array and copy each option pointer.
3. Pass pointer array to native.
4. On callback completion (success or failure) free each option pointer and the pointer array.

## Usage Recipes (Unity C#)

### Basic Alert
```csharp
IosDialogManager.Instance.DialogResult += (btn, ok, err) => {
    if (!ok) Debug.LogError(err); else Debug.Log($"Pressed: {btn}");
};
IosDialogManager.Instance.ShowDialog("Notice", "Operation finished", "Confirm");
```

### Confirmation
```csharp
IosDialogManager.Instance.ConfirmDialogResult += (btn, ok, err) => Debug.Log($"Choice: {btn}, ok={ok}, err={err}");
IosDialogManager.Instance.ShowConfirmDialog("Confirm", "Proceed?", "Proceed", "Cancel");
```

### Destructive
```csharp
IosDialogManager.Instance.DestructiveDialogResult += (btn, ok, err) => Debug.Log($"Destructive result: {btn}");
IosDialogManager.Instance.ShowDestructiveDialog("Warning", "Delete item?", "Delete", "Cancel");
```

### Action Sheet
```csharp
IosDialogManager.Instance.ActionSheetResult += (btn, ok, err) => Debug.Log($"Sheet: {btn}");
IosDialogManager.Instance.ShowActionSheet("Select", "Choose option", new[]{"A","B","Delete"}, "Cancel");
```

### Text Input (Validation Disabled)
```csharp
IosDialogManager.Instance.TextInputDialogResult += (btn, text, ok, err) => Debug.Log($"Input: {text}");
IosDialogManager.Instance.ShowTextInputDialog("Name", "Enter name", "", "OK", "Cancel", true);
```

### Text Input (Validation Enabled)
```csharp
IosDialogManager.Instance.ShowTextInputDialog("Name", "Required", "Name", "OK", "Cancel", false);
```

### Login (Both Fields Required)
```csharp
IosDialogManager.Instance.LoginDialogResult += (btn, user, pass, ok, err) => {
    if (btn == "Login") Debug.Log($"User={user}, passLength={pass?.Length ?? 0}");
};
IosDialogManager.Instance.ShowLoginDialog("Login", "Enter credentials", "Username", "Password", "Login", "Cancel", false);
```

## Callback Semantics
| Field | Meaning |
|-------|---------|
| `buttonText` / option | Pressed button label (NULL only if failed pre‑presentation). |
| `inputText` / `username` / `password` | Present when user confirmed; NULL on cancel / failure. |
| `isSuccess` | `false` only if infrastructure (presentation) failed. |
| `errorMessage` | Diagnostic text when `isSuccess == false`; otherwise NULL. |

User pressing *Cancel* is a successful interaction (`isSuccess = true`).

## Error Handling
Typical failure cause: inability to resolve a root view controller (rare). Bridge returns `isSuccess = false` with diagnostic text. Unity should log and optionally surface to QA.

## Threading
All native callbacks -> main thread; events enqueued through a dispatcher ensure Unity safety. Avoid heavy work inside callbacks.

## Memory & Lifetime
Return string pointers live only for the callback duration. C# layer receives already marshaled strings (IL2CPP handles conversion). For ActionSheet option arrays we explicitly free unmanaged allocations right after callback.

## Input Validation Flags
| Dialog | Flag | Effect when `false` |
|--------|------|---------------------|
| Text Input | `enableConfirmWhenEmpty` | Disables confirm until non‑empty text |
| Login | `enableLoginWhenEmpty` | Disables login until username & password both non‑empty |

## Security Notes
Passwords from login dialog are plaintext transient values. Do not log or store; process then release references.

## Versioning & Compatibility
- Additive C functions / optional parameters: **minor** version.
- Breaking signature changes: **major** version only when unavoidable.
- Maintain a CHANGELOG for SDK consumers.

## Migrating from Ad‑hoc Native Plugins
Replace bespoke Objective‑C alert code with these standardized calls. Consolidates memory management, validation, error semantics.

## Topics

### Swift Facade
- ``UnityIosDialogManager``
- ``UnityIosDialogManager/showDialog(title:message:buttonText:handler:)``
- ``UnityIosDialogManager/showConfirmDialog(title:message:confirmButtonText:cancelButtonText:handler:)``
- ``UnityIosDialogManager/showDestructiveDialog(title:message:destructiveButtonText:cancelButtonText:handler:)``
- ``UnityIosDialogManager/showActionSheet(title:message:options:cancelButtonText:handler:)``
- ``UnityIosDialogManager/showTextInputDialog(title:message:placeholder:confirmButtonText:cancelButtonText:enableConfirmWhenEmpty:handler:)``
- ``UnityIosDialogManager/showLoginDialog(title:message:usernamePlaceholder:passwordPlaceholder:loginButtonText:cancelButtonText:enableLoginWhenEmpty:handler:)``

### C Bridge (Header Identifiers)
The following are C callback typedefs and functions (documented in `UnityIosDialogManagerBridge.h`). Not all appear as DocC symbols, but are part of the public ABI:

- `DialogCallback`
- `ConfirmDialogCallback`
- `DestructiveDialogCallback`
- `ActionSheetCallback`
- `TextInputDialogCallback`
- `LoginDialogCallback`
- `showDialog`
- `showConfirmDialog`
- `showDestructiveDialog`
- `showActionSheet`
- `showTextInputDialog`
- `showLoginDialog`

### Related Modules
- ``IosLibrary`` (core dialog implementation)

## See Also
- *IosLibrary* for the underlying presentation engine.
- CHANGELOG (add once maintained) for evolution and migration notes.
