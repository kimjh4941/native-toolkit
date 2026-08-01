# Clipboard Feature

Language:

- 日本語: [clipboard.ja.md](clipboard.ja.md)
- English (this page)
- 한국어: [clipboard.ko.md](clipboard.ko.md)

← [Back to Manual Top](index.md)

---

## Table of Contents

- [Android](#android)
  - [Setup](#setup)
  - [Copy](#copy)
    - [Copy Plain Text](#copy-plain-text)
    - [Copy Plain Text (Empty)](#copy-plain-text-empty)
    - [Copy HTML Text](#copy-html-text)
    - [Copy URI](#copy-uri)
    - [Copy Multiple Text](#copy-multiple-text)
  - [Copy - Sensitive](#copy---sensitive)
    - [Copy Sensitive Text](#copy-sensitive-text)
  - [Read / Inspect](#read--inspect)
    - [Read Clipboard](#read-clipboard)
    - [Has Clip](#has-clip)
    - [Get Description](#get-description)
  - [Clear](#clear)
    - [Clear Clipboard](#clear-clipboard)
  - [Observe](#observe)
    - [Start Observing](#start-observing)
    - [Stop Observing](#stop-observing)
  - [Error Handling](#error-handling)

---

## Android

- Library: `android-native-toolkit-1.3.0.aar`
- Minimum SDK: Android 12 (API 31)
- Sensitive content preview suppression: Android 13 (API 33)+
- Scope: copy, read, metadata inspection, clear, and clipboard change observation via `android_library` (native). No Unity Bridge dependency is required for any of these operations.

### Setup

#### Android native (AAR)

1. Place `android-native-toolkit-1.3.0.aar` in `app/libs`.
2. Add dependency in `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation(files("libs/android-native-toolkit-1.3.0.aar"))
}
```

No additional manifest configuration is required for clipboard operations. If you plan to copy a `content://` URI (see [Copy URI](#copy-uri)), you need a `FileProvider` that can resolve a URI for the file you want to share; the AAR itself does not declare one for general-purpose use.

---

### Copy

`ClipboardUseCases` is obtained via a factory function that takes a `Context`:

```kotlin
val clipboardUseCases = ClipboardUseCases(context)
```

#### Copy Plain Text

```kotlin
try {
    clipboardUseCases.copyPlainText(
        ClipContent.PlainText(text = "Hello from native-toolkit", label = "sample")
    )
} catch (e: ClipboardDomainError) {
    // handle error
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyPlainText.png" alt="Example_ClipboardSampleScreen_CopyPlainText" width="400" />
</p>

#### Copy Plain Text (Empty)

Blank text is allowed and does not throw.

```kotlin
clipboardUseCases.copyPlainText(ClipContent.PlainText(text = ""))
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyPlainTextEmpty.png" alt="Example_ClipboardSampleScreen_CopyPlainTextEmpty" width="400" />
</p>

#### Copy HTML Text

```kotlin
clipboardUseCases.copyHtmlText(
    ClipContent.HtmlText(plainText = "Hello", htmlText = "<b>Hello</b>")
)
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyHtmlText.png" alt="Example_ClipboardSampleScreen_CopyHtmlText" width="400" />
</p>

#### Copy URI

Copies a `content://` (or `file://`) URI. Only the `content` and `file` schemes are accepted; other schemes throw `ClipboardDomainError.InvalidUri`.

```kotlin
val file = File(context.cacheDir, "clipboard_sample.txt")
file.writeText("Clipboard sample file content")
val uri = FileProvider.getUriForFile(
    context,
    "${context.packageName}.native_toolkit.share.fileprovider",
    file
)

clipboardUseCases.copyUri(ClipContent.UriContent(uri = uri.toString()))
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyUri.png" alt="Example_ClipboardSampleScreen_CopyUri" width="400" />
</p>

#### Copy Multiple Text

Multiple plain-text items of the same form (a single `ClipData` with several items).

```kotlin
clipboardUseCases.copyMultipleText(
    ClipContent.MultipleText(texts = listOf("first", "second", "third"))
)
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyMultipleText.png" alt="Example_ClipboardSampleScreen_CopyMultipleText" width="400" />
</p>

---

### Copy - Sensitive

Set `isSensitive = true` to hint that the copied content is sensitive (a password, a one-time code, etc.).

- On Android 13 (API 33) and above, the system's own copy-confirmation UI suppresses the content preview.
- On Android 12L (API 32) and below, there is no system confirmation UI at all; show your own feedback (for example a `Toast`) after copying.

#### Copy Sensitive Text

```kotlin
clipboardUseCases.copyPlainText(
    ClipContent.PlainText(text = "P@ssw0rd-sample", isSensitive = true)
)

if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2) {
    Toast.makeText(context, "Copied (sensitive)", Toast.LENGTH_SHORT).show()
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopySensitiveText.png" alt="Example_ClipboardSampleScreen_CopySensitiveText" width="400" />
</p>

---

### Read / Inspect

#### Read Clipboard

An empty clipboard is a **normal case**, not an error: `read()` returns `null`.

```kotlin
val result = clipboardUseCases.read()
if (result != null) {
    // result.label, result.mimeTypes, result.items (text / htmlText / uri / coercedText per item)
} else {
    // clipboard is empty (normal)
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_ReadClipboard.png" alt="Example_ClipboardSampleScreen_ReadClipboard" width="400" />
</p>

#### Has Clip

```kotlin
val hasClip: Boolean = clipboardUseCases.hasClip()
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_HasClip.png" alt="Example_ClipboardSampleScreen_HasClip" width="400" />
</p>

#### Get Description

Reads metadata only, without touching the clip body (avoids the Android 12+ "pasted from clipboard" access notification). Also `null` when the clipboard is empty (normal case).

```kotlin
val info = clipboardUseCases.getDescription()
if (info != null) {
    // info.label, info.mimeTypes
    // info.isStyledText: whether the content is styled (rich) text
    // info.classificationStatus: raw ClipDescription.CLASSIFICATION_* value, or null if unavailable
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_GetDescription.png" alt="Example_ClipboardSampleScreen_GetDescription" width="400" />
</p>

---

### Clear

#### Clear Clipboard

```kotlin
clipboardUseCases.clear()
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_ClearClipboard.png" alt="Example_ClipboardSampleScreen_ClearClipboard" width="400" />
</p>

---

### Observe

`ClipboardChangeMonitor` owns the system clipboard-change listener. It lives in `android_library` (not the Unity Bridge), so it can be used directly from native code.

Observation is only reliable while the app is in the foreground (Android 10+ restricts background clipboard reads).

```kotlin
val monitor = ClipboardChangeMonitor()
```

#### Start Observing

`onChange` is called on the system listener's callback thread; marshal to the main thread yourself if you update UI state.

```kotlin
monitor.start(context) {
    // Called on the system listener's callback thread.
    mainHandler.post {
        // update UI state here
    }
}

val isObserving: Boolean = monitor.isObserving()
```

A second call to `start` while already observing is a no-op (no duplicate system listener registration).

#### Stop Observing

```kotlin
monitor.stop()
```

Call `stop()` when the observing screen/component is torn down to avoid leaking the system listener:

```kotlin
DisposableEffect(monitor) {
    onDispose { monitor.stop() }
}
```

---

### Error Handling

`ClipboardUseCases` throws `ClipboardDomainError` subtypes.

| Error | Cause | Error message |
|---|---|---|
| `EmptyContent` | `htmlText` is blank in `copyHtmlText` | `"Clipboard content is empty. Please provide text or HTML."` |
| `EmptyItemList` | `texts` list is empty in `copyMultipleText` | `"No items provided for clipboard copy."` |
| `InvalidUri` | `uri` is blank, or its scheme is neither `content` nor `file` | `"Invalid URI: <uri>"` |
| `ClipboardUnavailable` | The system `ClipboardManager` could not be obtained | `"Clipboard service is unavailable."` |
| `ReadNotAllowed` | `read()` was denied by the system (`SecurityException`); the app is likely not in the foreground | `"Clipboard read is not allowed. The app must be in the foreground."` |

An empty clipboard is **not** one of these errors: `read()` and `getDescription()` return `null` as a normal case.

```kotlin
try {
    clipboardUseCases.copyUri(ClipContent.UriContent(uri = ""))
} catch (e: ClipboardDomainError.InvalidUri) {
    // Blank or unsupported-scheme URI
} catch (e: ClipboardDomainError) {
    // Other domain error
}
```
