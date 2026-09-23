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
- [iOS](#ios)
  - [IosClipboardManager](#iosclipboardmanager)
  - [Setup](#setup-1)
    - [Threading](#threading)
    - [Two calling styles](#two-calling-styles)
    - [Defaults](#defaults)
  - [Scope](#scope)
    - [Use General](#use-general)
    - [Create Named Pasteboard](#create-named-pasteboard)
    - [Use Fixed Named Scope (no create)](#use-fixed-named-scope-no-create)
    - [Create Unique Pasteboard](#create-unique-pasteboard)
    - [Remove Active Pasteboard](#remove-active-pasteboard)
    - [Named and unique pasteboards are not a persistent store](#named-and-unique-pasteboards-are-not-a-persistent-store)
  - [Copy](#copy-1)
    - [Copy Plain Text](#copy-plain-text-1)
    - [Copy Plain Text (Empty)](#copy-plain-text-empty-1)
    - [Copy HTML Text](#copy-html-text-1)
    - [Copy URL](#copy-url)
    - [Copy Image File](#copy-image-file)
    - [Copy Image Data](#copy-image-data)
    - [Copy Color](#copy-color)
    - [Copy Custom Data](#copy-custom-data)
    - [Copy Multiple Text](#copy-multiple-text-1)
    - [Copy Multi Representation](#copy-multi-representation)
  - [Copy Options](#copy-options)
    - [Copy with localOnly](#copy-with-localonly)
    - [Copy with expirationDate](#copy-with-expirationdate)
  - [Append](#append)
    - [Append Plain Text](#append-plain-text)
    - [Append URL](#append-url)
    - [append does not carry privacy options](#append-does-not-carry-privacy-options)
  - [Read / Inspect](#read--inspect-1)
    - [Read](#read)
    - [Read Data](#read-data)
    - [Snapshot](#snapshot)
    - [Snapshot (Matching Types)](#snapshot-matching-types)
    - [Privacy: prompts and notifications](#privacy-prompts-and-notifications)
  - [Load (async)](#load-async)
    - [Load Text](#load-text)
    - [Load URL](#load-url)
    - [Load Image](#load-image)
    - [Load File](#load-file)
    - [Cancel All Loads](#cancel-all-loads)
  - [Detect](#detect)
    - [Detect Patterns](#detect-patterns)
    - [Detect Values](#detect-values)
    - [number and probableWebSearch classify the whole clipboard](#number-and-probablewebsearch-classify-the-whole-clipboard)
    - [Detection has no cancellation token](#detection-has-no-cancellation-token)
  - [Observe](#observe-1)
    - [Start Observing](#start-observing-1)
    - [Stop Observing](#stop-observing-1)
    - [Check Foreground Change](#check-foreground-change)
  - [Paste Control](#paste-control)
    - [Make Paste Control](#make-paste-control)
  - [Clear](#clear-1)
  - [Error Handling](#error-handling-1)
- [macOS](#macos)
  - [MacClipboardManager](#macclipboardmanager)
  - [Setup](#setup-2)
  - [Scope](#scope-1)
    - [Create Named Pasteboard](#create-named-pasteboard-1)
    - [Create Unique Pasteboard](#create-unique-pasteboard-1)
    - [Remove Current Pasteboard](#remove-current-pasteboard)
    - [Remove General (error 1508)](#remove-general-error-1508)
    - [Create Empty Named Pasteboard (error 1505)](#create-empty-named-pasteboard-error-1505)
  - [Copy](#copy-2)
    - [Copy Text](#copy-text)
    - [Copy URL](#copy-url-1)
    - [Copy Image](#copy-image)
    - [Copy Multiple Items](#copy-multiple-items)
    - [Copy Multiple Representations](#copy-multiple-representations)
    - [Copy Empty (error 1501)](#copy-empty-error-1501)
    - [Copy Empty Representations (error 1502)](#copy-empty-representations-error-1502)
  - [Copy Options](#copy-options-1)
    - [localOnly defaults to true](#localonly-defaults-to-true)
  - [Append](#append-1)
    - [Copy Then Append](#copy-then-append)
    - [Append keeps the privacy of what it appends to](#append-keeps-the-privacy-of-what-it-appends-to)
    - [Append with lost ownership (error 1511)](#append-with-lost-ownership-error-1511)
  - [Read / Inspect](#read--inspect-2)
    - [Read](#read)
    - [Read Data for one type](#read-data-for-one-type)
    - [Snapshot](#snapshot)
    - [Snapshot with a type filter](#snapshot-with-a-type-filter)
    - [Snapshot with an empty filter (error 1512)](#snapshot-with-an-empty-filter-error-1512)
    - [Access Behavior](#access-behavior)
  - [Detect](#detect-1)
    - [Detect Patterns](#detect-patterns-1)
    - [Detect Values](#detect-values-1)
    - [Detect Metadata](#detect-metadata)
    - [Detect with no patterns (error 1503)](#detect-with-no-patterns-error-1503)
  - [Observe](#observe-2)
    - [Start Observing](#start-observing-1)
    - [Invalid interval (error 1523)](#invalid-interval-error-1523)
    - [Stop Observing](#stop-observing-2)
    - [Check Foreground Change](#check-foreground-change-1)
  - [Paste Control](#paste-control-1)
    - [Invalid type identifier (error 1504)](#invalid-type-identifier-error-1504)
  - [Clear](#clear-2)
  - [Error Handling](#error-handling-2)
    - [About 1514](#about-1514)
- [Windows](#windows)
  - [Setup](#setup-3)
    - [The owner STA thread](#the-owner-sta-thread)
    - [Synchronous and asynchronous operations](#synchronous-and-asynchronous-operations)
    - [Write options](#write-options)
  - [Init / Lifecycle](#init--lifecycle)
    - [Create the session](#create-the-session)
    - [History event handlers](#history-event-handlers)
    - [Close](#close)
    - [CanClose](#canclose)
  - [Copy](#copy-3)
    - [Copy Plain Text](#copy-plain-text-2)
    - [Copy Plain Text (Empty)](#copy-plain-text-empty-2)
    - [Copy HTML](#copy-html)
    - [Copy Files](#copy-files)
    - [Copy Image](#copy-image-1)
    - [Copy Custom Format](#copy-custom-format)
    - [Copy Multiple Formats](#copy-multiple-formats)
  - [Write Options](#write-options-1)
  - [Paste](#paste)
    - [Paste Plain Text](#paste-plain-text)
    - [Paste HTML](#paste-html)
    - [Paste Files](#paste-files)
    - [Paste Image](#paste-image)
    - [Paste Custom Format](#paste-custom-format)
  - [Inspect / Clear](#inspect--clear)
    - [Has Format](#has-format)
    - [Get Clipboard Formats](#get-clipboard-formats)
    - [Get Preferred Format](#get-preferred-format)
    - [Clear Clipboard](#clear-clipboard-1)
  - [Deferred Rendering](#deferred-rendering)
    - [Reserve Deferred Formats](#reserve-deferred-formats)
    - [Recover Deferred State](#recover-deferred-state)
  - [History](#history)
    - [Get History Availability](#get-history-availability)
    - [Get Clipboard History](#get-clipboard-history)
    - [Restore History Item](#restore-history-item)
    - [Delete History Item](#delete-history-item)
    - [Clear Unpinned History](#clear-unpinned-history)
    - [Cancel Request](#cancel-request)
  - [Error Handling](#error-handling-3)
  - [C ABI](#c-abi)

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

---

## iOS

- Library: `ios-native-toolkit-1.3.0.xcframework`
- Minimum Deployment Target: iOS 18
- Scope: copy / append, synchronous read, metadata snapshot, named and unique pasteboard lifecycle, asynchronous `NSItemProvider` loading, pattern detection, change observation, and a ready-to-place `UIPasteControl` paste button.

### IosClipboardManager

`IosClipboardManager` is a singleton class that wraps `UIPasteboard`.

### Setup

1. Add `ios-native-toolkit-1.3.0.xcframework` to your Xcode project (drag it into the project and set "Embed & Sign" in the target's Frameworks, Libraries, and Embedded Content).
2. Import the library where you use the clipboard:

```swift
import IosLibrary
```

No additional initialization and no `Info.plist` entry are required.

#### Threading

`IosClipboardManager` is `@MainActor`-isolated. Call it from the main actor (SwiftUI / UIKit code is already there); from a non-main context, use `await MainActor.run { ... }`.

#### Two calling styles

Every data-bearing operation offers both forms:

- `async throws` (preferred for native Swift callers): returns a typed value and throws `ClipboardError` on failure.
- Callback: `(isSuccess, value?, errorCode?, errorMessage?)`, or `(isSuccess, errorCode?, errorMessage?)` for operations without a return value.

```swift
// async throws (recommended for Swift callers)
Task {
    do {
        try await IosClipboardManager.shared.copy(.plainText("Hello"))
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorDescription ?? "nil")
    }
}

// callback (equivalent)
IosClipboardManager.shared.copy(.plainText("Hello")) { isSuccess, errorCode, errorMessage in
    print(isSuccess, errorCode ?? "nil", errorMessage ?? "nil")
}
```

`cancelAllLoads`, `startObserving`, `stopObserving`, `checkForegroundChange`, and `makePasteControl` complete synchronously and therefore have a single, synchronous form only.

The examples below use the `async throws` style. Because SwiftUI `Button` actions are synchronous, each call is wrapped in `Task { ... }`.

#### Defaults

| Setting | Default |
|---|---|
| Maximum copy size | 64 MiB |
| Maximum load size | 64 MiB |
| Maximum image pixel count | 100,000,000 |
| Detection timeout | 5 seconds |
| Provider load timeout | 15 seconds |
| Image encode timeout | 10 seconds |

Use `IosClipboardManager(timeouts:limits:)` to build an instance with different values; prefer `shared` for ordinary use.

---

### Scope

Every operation takes a `scope: PasteboardScope` parameter that defaults to `.general`. The general pasteboard is shared with every app and persists across launches; named and unique pasteboards are for handing data between live apps.

```swift
public enum PasteboardScope {
    case general
    case named(String)   // shared with apps of the same Team ID
    case unique(String)  // created via withUniqueName(); the name is an output
}
```

#### Use General

`.general` is the default, so it can also simply be omitted.

```swift
let scope: PasteboardScope = .general
```

#### Create Named Pasteboard

`createPasteboard(.named(_:))` resolves an existing pasteboard of that name, or creates it if none exists. It returns the resulting `PasteboardScope`, which is what later calls should be given.

```swift
Task {
    let scope = try await IosClipboardManager.shared.createPasteboard(
        .named("com.jonghyunkim.nativetoolkit.example.sample")
    )
    // scope == .named("com.jonghyunkim.nativetoolkit.example.sample")
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CreateNamedPasteboard.png" alt="Example_IosClipboardManager_CreateNamedPasteboard" width="400" />
</p>

#### Use Fixed Named Scope (no create)

Referring to a name without creating it is legal, but every operation on it fails with `CLIPBOARD_UNAVAILABLE` until something creates it.

```swift
let scope = PasteboardScope.named("com.jonghyunkim.nativetoolkit.example.sample")
```

#### Create Unique Pasteboard

`.unique` asks the system to generate the name. The generated name comes back in the returned scope, so it must be kept if the pasteboard is to be used again.

```swift
Task {
    let scope = try await IosClipboardManager.shared.createPasteboard(.unique)
    // scope == .unique("<system-generated name>")
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CreateUniquePasteboard.png" alt="Example_IosClipboardManager_CreateUniquePasteboard" width="400" />
</p>

#### Remove Active Pasteboard

```swift
Task {
    try await IosClipboardManager.shared.removePasteboard(scope)
}
```

Removing `.general` throws `ClipboardError.cannotRemoveGeneralPasteboard`.

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_RemovePasteboard.png" alt="Example_IosClipboardManager_RemovePasteboard" width="400" />
</p>

#### Named and unique pasteboards are not a persistent store

A pasteboard created via `createPasteboard(.named(_:))` or `.unique` is not meant to persist, but its contents are **not guaranteed to be discarded when the creating app quits** either. Measured on iOS 18.7.2: after force-quitting the app and relaunching it, a named pasteboard written before the quit was still readable. The system does not specify when such a pasteboard is reclaimed.

Use these scopes only to hand data between live apps, and **delete sensitive data explicitly with `removePasteboard(_:)`** — do not rely on app termination to discard it. A force-quit does not run `deinit`, so no cleanup the library could perform on teardown would help here.

For sharing that must outlive the creating app by design, use an App Group shared container instead; that is outside this library's scope.

---

### Copy

`copy` replaces the pasteboard contents. `ClipboardContent` covers every supported form.

#### Copy Plain Text

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .plainText("Hello from IosLibraryExample"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyPlainText.png" alt="Example_IosClipboardManager_CopyPlainText" width="400" />
</p>

#### Copy Plain Text (Empty)

Blank text is allowed and does not throw.

```swift
Task {
    try await IosClipboardManager.shared.copy(.plainText(""), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyPlainTextEmpty.png" alt="Example_IosClipboardManager_CopyPlainTextEmpty" width="400" />
</p>

#### Copy HTML Text

Written as a single item carrying two representations, so an app that cannot render HTML still finds the plain-text fallback.

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .htmlText(plain: "plain body", html: "<b>html body</b>"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyHtmlText.png" alt="Example_IosClipboardManager_CopyHtmlText" width="400" />
</p>

#### Copy URL

A URL is passed as a raw string and validated in the library: only the `http`, `https`, and `file` schemes are accepted (otherwise `ClipboardError.invalidURL` is thrown).

```swift
Task {
    try await IosClipboardManager.shared.copy(.url("https://www.apple.com"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyURL.png" alt="Example_IosClipboardManager_CopyURL" width="400" />
</p>

#### Copy Image File

Loads an image from a file path. A missing path throws `ClipboardError.fileNotFound`; a file that is not a decodable image throws `ClipboardError.imageLoadFailed`.

```swift
Task {
    guard let path = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path else { return }
    try await IosClipboardManager.shared.copy(.imageFile(path: path), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyImageFile.png" alt="Example_IosClipboardManager_CopyImageFile" width="400" />
</p>

#### Copy Image Data

Raw image bytes with an explicit, known image uniform type identifier. Data that cannot be decoded as an image throws `ClipboardError.invalidImageData`.

```swift
Task {
    guard let url = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png"),
          let data = try? Data(contentsOf: url) else { return }
    try await IosClipboardManager.shared.copy(
        .imageData(data, utType: "public.png"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyImageData.png" alt="Example_IosClipboardManager_CopyImageData" width="400" />
</p>

#### Copy Color

Each RGBA component must be finite and within `0.0...1.0`, otherwise `ClipboardError.invalidColor` is thrown.

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyColor.png" alt="Example_IosClipboardManager_CopyColor" width="400" />
</p>

#### Copy Custom Data

Arbitrary bytes under an application-defined uniform type identifier. The identifier is validated for syntax; an invalid one throws `ClipboardError.invalidTypeIdentifier`.

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .customData(Data([0xCA, 0xFE]), utType: "com.jonghyunkim.nativetoolkit.example.custom"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyCustomData.png" alt="Example_IosClipboardManager_CopyCustomData" width="400" />
</p>

A custom identifier that is not declared in your app's `Info.plist` does not conform to `public.data`, so `Load File (public.data)` will not find it. Use the `public.data` identifier itself when the item is meant to be loaded as a generic file:

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .customData(Data(repeating: 0x41, count: 64), utType: "public.data"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyFileFixture.png" alt="Example_IosClipboardManager_CopyFileFixture" width="400" />
</p>

#### Copy Multiple Text

Multiple plain-text items of the same form. An empty array throws `ClipboardError.emptyItemList`.

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .multipleText(["first", "second", "third"]),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyMultipleText.png" alt="Example_IosClipboardManager_CopyMultipleText" width="400" />
</p>

#### Copy Multi Representation

A single item exposing several representations, keyed by uniform type identifier. Receiving apps pick whichever they understand. An empty dictionary throws `ClipboardError.emptyItemList`.

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .multiRepresentation([
            "public.plain-text": Data("multi representation".utf8),
            "public.utf8-plain-text": Data("multi representation".utf8)
        ]),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyMultiRepresentation.png" alt="Example_IosClipboardManager_CopyMultiRepresentation" width="400" />
</p>

---

### Copy Options

`ClipboardCopyOptions` carries the privacy settings of a `copy`. The default is `localOnly: true` with no expiration.

```swift
public struct ClipboardCopyOptions {
    public let localOnly: Bool       // do not transfer to nearby devices (Universal Clipboard)
    public let expirationDate: Date? // the system discards the item after this instant
    public static let `default` = ClipboardCopyOptions(localOnly: true, expirationDate: nil)
}
```

#### Copy with localOnly

`localOnly: true` asks the system not to hand the item to nearby devices through Universal Clipboard. Set it to `false` only when cross-device transfer is intended.

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .plainText("LOCALONLY-BODY"),
        options: ClipboardCopyOptions(localOnly: true, expirationDate: nil),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyLocalOnly.png" alt="Example_IosClipboardManager_CopyLocalOnly" width="400" />
</p>

#### Copy with expirationDate

The date must be in the future, otherwise `ClipboardError.invalidExpirationDate` is thrown.

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .plainText("expiring body"),
        options: ClipboardCopyOptions(
            localOnly: true,
            expirationDate: Date().addingTimeInterval(30)
        ),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyExpiring.png" alt="Example_IosClipboardManager_CopyExpiring" width="400" />
</p>

---

### Append

`append` adds an item without replacing what is already on the pasteboard.

#### Append Plain Text

```swift
Task {
    try await IosClipboardManager.shared.append(.plainText("appended item"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_AppendPlainText.png" alt="Example_IosClipboardManager_AppendPlainText" width="400" />
</p>

#### Append URL

```swift
Task {
    try await IosClipboardManager.shared.append(.url("https://developer.apple.com"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_AppendURL.png" alt="Example_IosClipboardManager_AppendURL" width="400" />
</p>

#### append does not carry privacy options

`append` cannot accept `ClipboardCopyOptions`, and does not guarantee that a prior `copy`'s `localOnly` / `expirationDate` apply to the appended item. **Always use `copy(_:options:)` for sensitive data.**

---

### Read / Inspect

#### Read

Reads the pasteboard synchronously. Large payloads (image bytes) are not included in the result; only the uniform type identifier is reported. An empty pasteboard is a **normal case**, not an error: `numberOfItems` is `0`.

```swift
Task {
    let result = try await IosClipboardManager.shared.read(scope: scope)
    print(result.numberOfItems)
    for item in result.items {
        // item.typeIdentifiers, item.text, item.urlString, item.imageDataUTType
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_Read.png" alt="Example_IosClipboardManager_Read" width="400" />
</p>

#### Read Data

Returns the raw bytes registered under one uniform type identifier, or `nil` when no item matches.

```swift
Task {
    let data = try await IosClipboardManager.shared.readData(utType: "public.png", scope: scope)
    print(data?.count ?? 0)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_ReadData.png" alt="Example_IosClipboardManager_ReadData" width="400" />
</p>

#### Snapshot

Reads metadata only, without touching the body. Prefer it for pre-checks: it is built exclusively from APIs Apple documents as triggering neither the iOS 16+ permission prompt nor the iOS 14+ access notification.

```swift
Task {
    let snapshot = try await IosClipboardManager.shared.snapshot(scope: scope)
    // snapshot.hasStrings, snapshot.hasURLs, snapshot.hasImages, snapshot.hasColors
    // snapshot.numberOfItems, snapshot.typeIdentifiers, snapshot.allTypeIdentifiers
    if snapshot.hasStrings {
        // show a paste affordance
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_Snapshot.png" alt="Example_IosClipboardManager_Snapshot" width="400" />
</p>

`hasStrings` cannot decide whether a paste will succeed for a specific type. For example `public.vcard` is a sibling of `public.plain-text`, not a subtype, so an item can satisfy `hasStrings` and still not be loadable as plain text. Declare the types you accept explicitly (see [Paste Control](#paste-control)).

#### Snapshot (Matching Types)

Pass `matchingTypes` to also learn which item indexes carry one of those types. `matchingItemIndexes` is `nil` when `matchingTypes` was not supplied.

```swift
Task {
    let snapshot = try await IosClipboardManager.shared.snapshot(
        matchingTypes: ["public.plain-text"],
        scope: scope
    )
    print(snapshot.matchingItemIndexes ?? [])
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_SnapshotMatching.png" alt="Example_IosClipboardManager_SnapshotMatching" width="400" />
</p>

#### Privacy: prompts and notifications

`read` / `readData` / `loadItem` pull data from the pasteboard and may trigger an iOS 16+ permission prompt and/or an iOS 14+ access notification, at the system's discretion. Use `snapshot` for pre-checks.

`UIPasteControl` (via `makePasteControl`) avoids the iOS 16+ permission prompt, but Apple does not document it as avoiding the iOS 14+ access notification as well — verify on-device for your target OS versions before relying on either being silent.

---

### Load (async)

`loadItem` resolves an item through `NSItemProvider`, which can convert between representations and decode images off the main thread. Use it when `read` alone is not enough.

#### Load Text

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(.text, scope: scope)
    if case .text(let value) = item {
        print(value.count)
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadText.png" alt="Example_IosClipboardManager_LoadText" width="400" />
</p>

#### Load URL

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(.url, scope: scope)
    if case .url(let value) = item {
        print(value)
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadURL.png" alt="Example_IosClipboardManager_LoadURL" width="400" />
</p>

#### Load Image

The image is re-encoded as PNG on a background executor, so the returned uniform type identifier is always `public.png`.

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(.image, scope: scope)
    if case .imageData(let data, let utType) = item {
        print(data.count, utType)
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadImage.png" alt="Example_IosClipboardManager_LoadImage" width="400" />
</p>

#### Load File

Copies the item to a temporary file and hands over the URL. **The caller owns the returned URL and its parent directory** and must delete it once done; undelivered files (failure, cancellation, timeout) are cleaned up internally.

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(
        .file(utType: "public.data"),
        scope: scope
    )
    if case .file(let url) = item {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        print(size)
        // Delete the directory the library handed over, not the file alone.
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadFile.png" alt="Example_IosClipboardManager_LoadFile" width="400" />
</p>

#### Cancel All Loads

Cancels every pending load. A cancelled load throws `ClipboardError.cancelled` (`CLIPBOARD_CANCELLED`) in the `async throws` form, or reports `isSuccess == false` with that code in the callback form; callers may treat it as a normal, ignorable outcome.

```swift
IosClipboardManager.shared.cancelAllLoads()
```

The callback form returns a `ClipboardLoadToken` so a single load can be cancelled on its own:

```swift
let token = IosClipboardManager.shared.loadItem(.image, scope: scope) { isSuccess, item, errorCode, errorMessage in
    print(isSuccess, errorCode ?? "nil")
}
token.cancel()
```

---

### Detect

Data detection reports what the pasteboard *contains* without reading (and thus without prompting for) the body.

```swift
public enum ClipboardDetectionPattern: String, CaseIterable {
    case probableWebURL, probableWebSearch, number, link, emailAddress, phoneNumber
    case postalAddress, calendarEvent, flightNumber, moneyAmount, shipmentTrackingNumber
}
```

#### Detect Patterns

Returns which of the requested patterns were found. An empty request set throws `ClipboardError.emptyDetectionPatterns`.

```swift
Task {
    let patterns = try await IosClipboardManager.shared.detectPatterns(
        Set(ClipboardDetectionPattern.allCases),
        scope: scope
    )
    print(patterns.map(\.rawValue).sorted())
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_DetectPatterns.png" alt="Example_IosClipboardManager_DetectPatterns" width="400" />
</p>

#### Detect Values

Returns the detected values themselves. This does read the content, so treat it like `read` with respect to privacy.

```swift
Task {
    let values = try await IosClipboardManager.shared.detectValues(
        Set(ClipboardDetectionPattern.allCases),
        scope: scope
    )
    print(values.detectedPatterns.count)
    // values.links, values.emailAddresses, values.phoneNumbers, values.postalAddresses,
    // values.calendarEvents, values.flightNumbers, values.moneyAmounts,
    // values.shipmentTrackingNumbers, values.number, values.probableWebURL, values.probableWebSearch
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_DetectValues.png" alt="Example_IosClipboardManager_DetectValues" width="400" />
</p>

#### number and probableWebSearch classify the whole clipboard

`number` and `probableWebSearch` describe the clipboard **as a whole** rather than extracting occurrences from it. A paragraph that merely mentions a number is neither a number nor a search phrase, so those two patterns do not appear for mixed content. Copy the value on its own to exercise them:

```swift
try await IosClipboardManager.shared.copy(.plainText("42"), scope: scope)                 // number
try await IosClipboardManager.shared.copy(.plainText("swift concurrency"), scope: scope)  // probableWebSearch
```

#### Detection has no cancellation token

`detectPatterns` / `detectValues` wrap `UIPasteboard`'s `async` detection APIs, which have no native cancellation support. A Task cancellation or the internal 5-second timeout returns control to the caller immediately, but the underlying system call may continue running in the background; its eventual result is discarded.

---

### Observe

#### Start Observing

Starts observing changes for one scope. A second call (for the same or a different scope) first stops the previous observation, so there is never more than one active subscription.

Events are delivered on the main thread.

```swift
do {
    try IosClipboardManager.shared.startObserving(scope: scope) { event in
        switch event.kind {
        case .changed(let typesAdded, let typesRemoved):
            print(typesAdded, typesRemoved)
        case .changedDetectedOnForeground:
            // detected by comparing changeCount on foreground return
            break
        case .removed:
            // the named pasteboard itself was removed
            break
        }
    }
} catch let error as ClipboardError {
    // pasteboardUnavailable: the scope could not be resolved; observation was not started
    print(error.errorCode)
}
```

`UIPasteboard.changedNotification` is only posted for changes made by **this app while it is in the foreground**. A change made by another app, or while this app was backgrounded, produces no notification — use `checkForegroundChange` for that case.

#### Stop Observing

```swift
IosClipboardManager.shared.stopObserving()
```

Call it when the observing screen is torn down:

```swift
.onDisappear {
    IosClipboardManager.shared.stopObserving()
}
```

#### Check Foreground Change

Compares the pasteboard's `changeCount` against the last value this manager recorded and returns whether it moved. Call it when the app returns to the foreground to catch the changes that produce no notification.

```swift
let changed = IosClipboardManager.shared.checkForegroundChange(scope: scope)
```

The first call for a scope establishes the baseline and therefore returns `false`. The baseline is also updated by `startObserving` and by receiving a change notification. The `Bool` return value cannot distinguish "resolved and unchanged" from "unresolvable" — use `snapshot` if that difference matters.

---

### Paste Control

`UIPasteControl` is the system paste button. Because the user's tap is itself the consent, it avoids the iOS 16+ permission prompt.

#### Make Paste Control

`makePasteControl` returns a single ready-to-place view whose internal receiver joins the responder chain automatically. Add it to your hierarchy as-is.

`acceptedTypes` must not be empty (`ClipboardError.invalidRequest`) and every entry must be a valid uniform type identifier (`ClipboardError.invalidTypeIdentifier`).

```swift
let pasteView = try IosClipboardManager.shared.makePasteControl(
    acceptedTypes: ["public.plain-text", "public.url", "public.image"],
    onPaste: { items in
        print(items.count)
    },
    onPartialFailure: { errors in
        // some of the pasted items could not be loaded
        print(errors.map(\.errorCode))
    },
    onPasteFailure: { error in
        // the paste itself failed
        print(error.errorCode)
    }
)
```

`displayMode` defaults to `.iconAndLabel`. Pass `.iconOnly`, `.labelOnly`, or `.arrowAndLabel` to change the button's appearance; the paste behaviour is the same in every mode.

In SwiftUI, wrap it with `UIViewRepresentable`:

```swift
struct ClipboardPasteControlView: UIViewRepresentable {
    let acceptedTypes: [String]
    let onPaste: ([ClipboardLoadedItem]) -> Void
    let onPartialFailure: ([ClipboardError]) -> Void
    let onPasteFailure: (ClipboardError) -> Void
    let onCreationFailure: (ClipboardError) -> Void

    func makeUIView(context: Context) -> UIView {
        do {
            return try IosClipboardManager.shared.makePasteControl(
                acceptedTypes: acceptedTypes,
                onPaste: onPaste,
                onPartialFailure: onPartialFailure,
                onPasteFailure: onPasteFailure
            )
        } catch let error as ClipboardError {
            // Reporting synchronously inside makeUIView triggers "Modifying state during view
            // update", so defer it to the next main-actor turn.
            Task { @MainActor in onCreationFailure(error) }
            return UIView()
        } catch {
            Task { @MainActor in onCreationFailure(.unknown(ClipboardFailureDetail(systemError: error))) }
            return UIView()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_PasteControl.png" alt="Example_IosClipboardManager_PasteControl" width="400" />
</p>

The paste button always targets the system general pasteboard, independently of any `scope` used elsewhere.

Cancelling a pending paste (a new paste arriving, or the view being torn down) does **not** invoke `onPaste` / `onPartialFailure` / `onPasteFailure`. Cancellation is caller-initiated and is never surfaced as a paste result.

`PasteControlFactory.makeComponents` is available for advanced cases where the button and its receiver must be placed independently; in that case **you** are responsible for retaining and placing the receiver.

---

### Clear

Removes every item from the scope. The pasteboard itself remains.

```swift
Task {
    try await IosClipboardManager.shared.clear(scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_Clear.png" alt="Example_IosClipboardManager_Clear" width="400" />
</p>

---

### Error Handling

The `async throws` form throws `ClipboardError`. The callback form reports the same failure as `errorCode` / `errorMessage`; on success both are `nil`.

`errorMessage` is a fixed, English, per-case string that **never embeds the input value**, so it is safe to log.

| `errorCode` | Case | Cause | Error message |
|---|---|---|---|
| `CLIPBOARD_EMPTY_CONTENT` | `emptyContent` | Content carries neither text nor HTML | `"Clipboard content is empty. Please provide text or HTML."` |
| `CLIPBOARD_EMPTY_ITEMS` | `emptyItemList` | `.multipleText([])` or `.multiRepresentation([:])` | `"No items provided for clipboard copy."` |
| `CLIPBOARD_EMPTY_PATTERNS` | `emptyDetectionPatterns` | Detection called with an empty pattern set | `"No detection patterns were specified."` |
| `CLIPBOARD_INVALID_URL` | `invalidURL` | URL is blank, or its scheme is not `http` / `https` / `file` | `"The URL is invalid."` |
| `CLIPBOARD_INVALID_TYPE` | `invalidTypeIdentifier` | Uniform type identifier is syntactically invalid | `"The uniform type identifier is invalid."` |
| `CLIPBOARD_INVALID_NAME` | `invalidPasteboardName` | Pasteboard name is blank or otherwise unusable | `"The pasteboard name is invalid."` |
| `CLIPBOARD_INVALID_COLOR` | `invalidColor` | An RGBA component is not finite or is outside `0.0...1.0` | `"Color components must be finite and within 0.0...1.0."` |
| `CLIPBOARD_INVALID_IMAGE_DATA` | `invalidImageData` | The supplied bytes could not be decoded as an image | `"The provided image data could not be decoded."` |
| `CLIPBOARD_INVALID_EXPIRATION` | `invalidExpirationDate` | `expirationDate` is not in the future | `"expirationDate must be in the future."` |
| `CLIPBOARD_INVALID_REQUEST` | `invalidRequest` | Request is malformed (e.g. empty `acceptedTypes`) | `"The request is invalid."` |
| `CLIPBOARD_CONTENT_TOO_LARGE` | `contentTooLarge` | Payload exceeds the configured size limit (64 MiB by default) | `"The clipboard content exceeds the configured size limit."` |
| `CLIPBOARD_FILE_NOT_FOUND` | `fileNotFound` | `.imageFile(path:)` points at a path that does not exist | `"The requested file was not found."` |
| `CLIPBOARD_IMAGE_LOAD_FAILED` | `imageLoadFailed` | The file exists but is not a decodable image | `"Failed to load the image."` |
| `CLIPBOARD_IMAGE_ENCODE_FAILED` | `imageEncodingFailed` | A pasted image could not be re-encoded as PNG | `"Failed to encode the pasted image."` |
| `CLIPBOARD_UNAVAILABLE` | `pasteboardUnavailable` | The named / unique pasteboard could not be resolved | `"The requested pasteboard is unavailable."` |
| `CLIPBOARD_CANNOT_REMOVE_GENERAL` | `cannotRemoveGeneralPasteboard` | `removePasteboard(.general)` was called | `"The general pasteboard cannot be removed."` |
| `CLIPBOARD_NO_MATCHING_ITEM` | `noMatchingItem` | No item carries the requested type | `"No clipboard item matches the requested type."` |
| `CLIPBOARD_LOAD_FAILED` | `providerLoadFailed` | `NSItemProvider` failed to load the item | `"Failed to load the clipboard item."` |
| `CLIPBOARD_UNEXPECTED_TYPE` | `unexpectedType` | The item could not be converted to the requested type | `"The clipboard item could not be converted to the requested type."` |
| `CLIPBOARD_FILE_COPY_FAILED` | `fileCopyFailed` | Copying the pasted file to a temporary location failed | `"Failed to copy the pasted file."` |
| `CLIPBOARD_CANCELLED` | `cancelled` | The load was cancelled by the caller | `"The clipboard load was cancelled."` |
| `CLIPBOARD_TIMED_OUT` | `timedOut` | The operation exceeded its timeout | `"The clipboard operation timed out."` |
| `CLIPBOARD_DETECTION_FAILED` | `detectionFailed` | The data detection system reported a failure | `"Pattern detection failed."` |
| `CLIPBOARD_UNKNOWN` | `unknown` | An unclassified system error | `"An unknown error occurred."` |

An empty clipboard is **not** one of these errors: `read` returns `numberOfItems == 0` and `readData` returns `nil` as normal cases.

```swift
Task {
    do {
        try await IosClipboardManager.shared.copy(.url("example.com"), scope: scope)
    } catch ClipboardError.invalidURL {
        // no scheme
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorDescription ?? "nil")
    }
}
```

---

## macOS

- Library: `mac-native-toolkit-1.3.0.xcframework`
- Minimum Deployment Target: macOS 15
- Scope: copy / append, read and snapshot, named and unique pasteboard lifecycle, pattern detection (macOS 15.4 and later), change observation, and a ready-to-place `PasteButton`.

### MacClipboardManager

`MacClipboardManager` is a singleton class that wraps `NSPasteboard`.

The screenshots in this section come from `MacLibraryExample`, whose Clipboard screen groups the operations in the same order as the sections below.

<p align="center">
    <img src="images/mac/clipboard/Example_MacClipboardManager_Overview.png" alt="Example_MacClipboardManager_Overview" width="400" />
</p>

### Setup

1. Add `mac-native-toolkit-1.3.0.xcframework` to your Xcode project (drag it into the project and set "Embed & Sign" in the target's Frameworks, Libraries, and Embedded Content).
2. Import the library where you use the clipboard:

```swift
import MacLibrary
```

No additional initialization and no entitlement are required.

#### Threading

Every operation reaches `NSPasteboard` on the main actor. The asynchronous methods are `async throws`; call them from a `Task`. Four operations complete immediately and are synchronous instead: `accessBehavior(scope:)`, `startObserving(scope:interval:onEvent:)`, `stopObserving()`, `checkForegroundChange(scope:)`, and the `makePasteButton` factory.

#### Two calling styles

Each asynchronous operation has two forms. The `async throws` form is for Swift callers. The `completion:` form exists for the Unity bridge, which cannot carry Swift error handling across the C ABI, and reports `(isSuccess, value, errorCode, errorMessage)` instead.

```swift
// Swift
let ownership = try await MacClipboardManager.shared.copy(content)

// Callback
MacClipboardManager.shared.copy(content) { isSuccess, ownership, errorCode, errorMessage in
    // runs exactly once, on the main actor
}
```

#### Content is a dictionary of type identifiers and bytes

`ClipboardContent` holds an ordered list of items, and each item holds a dictionary from a uniform type identifier to its bytes. There is no `.plainText` convenience case: what you write is what the pasteboard carries.

```swift
let content = ClipboardContent(items: [
    ClipboardItemData(representations: [
        "public.utf8-plain-text": Data("Copied from MacLibraryExample.".utf8)
    ])
])
```

#### Defaults

| Parameter | Default | Meaning |
|---|---|---|
| `scope` | `.general` | The system pasteboard |
| `options` | `.default` | `localOnly: true` |
| `interval` (observation) | `0.5` seconds | Poll interval, must be greater than 0 and at most 60 |
| `timeout` (paste button) | `15` seconds | Deadline for loading the pasted items |

### Scope

A scope is `.general`, `.named(String)`, or `.unique(String)`. The general pasteboard always exists. A named or unique pasteboard has to be created, and it is **not released when your app quits**: release it with `removePasteboard(_:)`.

#### Create Named Pasteboard

`createPasteboard` creates the pasteboard **or fetches it if the name already exists**, so asking twice for the same name returns the same pasteboard with its contents intact.

```swift
Task {
    let scope = try await MacClipboardManager.shared.createPasteboard(.named("nt-sample"))
}
```

#### Create Unique Pasteboard

A unique pasteboard is given a fresh system name every time. Creating a second one leaves the first with no name you can address, so release the previous one before creating another.

```swift
Task {
    let scope = try await MacClipboardManager.shared.createPasteboard(.unique)
}
```

#### Remove Current Pasteboard

```swift
Task {
    try await MacClipboardManager.shared.removePasteboard(scope)
}
```

#### Remove General (error 1508)

The standard pasteboards cannot be released.

```swift
Task {
    do {
        try await MacClipboardManager.shared.removePasteboard(.general)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1508
    }
}
```

#### Create Empty Named Pasteboard (error 1505)

An empty name is rejected.

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.createPasteboard(.named(""))
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1505
    }
}
```

### Copy

`copy` takes ownership of the pasteboard, replaces its contents, and returns a `PasteboardOwnership` that `append` needs later.

#### Copy Text

```swift
Task {
    let ownership = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: [
                "public.utf8-plain-text": Data("Copied from MacLibraryExample.".utf8)
            ])
        ]),
        scope: scope
    )
}
```

#### Copy URL

```swift
Task {
    _ = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: [
                "public.url": Data("https://www.apple.com".utf8)
            ])
        ]),
        scope: scope
    )
}
```

#### Copy Image

```swift
Task {
    _ = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: ["public.png": pngData])
        ]),
        scope: scope
    )
}
```

#### Copy Multiple Items

Every item reaches the pasteboard. **Which of them a receiving app uses is that app's decision**: TextEdit, for one, pastes all of them.

```swift
Task {
    _ = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: ["public.utf8-plain-text": Data("first".utf8)]),
            ClipboardItemData(representations: ["public.utf8-plain-text": Data("second".utf8)]),
        ]),
        scope: scope
    )
}
```

#### Copy Multiple Representations

One item carrying the same content twice, so an app that cannot read one format finds the other.

```swift
Task {
    _ = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: [
                "public.utf8-plain-text": Data(text.utf8),
                "public.rtf": Data(rtf.utf8),
            ])
        ]),
        scope: scope
    )
}
```

#### Copy Empty (error 1501)

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.copy(ClipboardContent(items: []), scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1501
    }
}
```

#### Copy Empty Representations (error 1502)

An item with no representations is rejected.

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.copy(
            ClipboardContent(items: [ClipboardItemData(representations: [:])]),
            scope: scope
        )
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1502
    }
}
```

### Copy Options

`ClipboardCopyOptions(localOnly:)` decides whether the contents are offered to your other devices through Universal Clipboard.

#### localOnly defaults to true

**Nothing you copy is shared with another device unless you ask for it.** `ClipboardCopyOptions.default` is `localOnly: true`, and `copy` uses it when you pass no options. To let the contents travel, pass `localOnly: false` explicitly.

```swift
Task {
    let ownership = try await MacClipboardManager.shared.copy(
        content,
        options: ClipboardCopyOptions(localOnly: false),   // share with other devices
        scope: scope
    )
}
```

Measured on 2026-09-03 between macOS 26.3 and iOS 18.7.2 over Handoff: with `localOnly: false` the contents reached the paired device in about a second; with `localOnly: true` they did not arrive, and the other device kept its own clipboard. That is one device pairing, so treat it as evidence for that pairing rather than a guarantee for every device and OS.

### Append

`append` adds items **to the pasteboard the ownership names**. It takes no scope of its own: the ownership carries it.

#### Copy Then Append

```swift
Task {
    let ownership = try await MacClipboardManager.shared.copy(content, scope: scope)
    let appended = try await MacClipboardManager.shared.append(more, ownership: ownership)
}
```

#### Append keeps the privacy of what it appends to

Appending to a `localOnly: true` copy does not republish the pasteboard: neither the original contents nor the appended item reach another device. Measured on 2026-09-03 with the same pairing as above.

#### Append with lost ownership (error 1511)

Ownership is lost as soon as anything else writes to the pasteboard, including another application. `append` compares the change count first and throws without writing.

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.append(late, ownership: stale)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1511
    }
}
```

The error is the same whether your own app or another application took the pasteboard: the library reports that the ownership no longer holds, not who took it.

### Read / Inspect

#### Read

`read` returns every item with all of its representations.

```swift
Task {
    let result = try await MacClipboardManager.shared.read(scope: scope)
    for (index, item) in result.items.enumerated() {
        print(index, item.totalBytes, item.representations.keys.sorted())
    }
}
```

Two things about what comes back are worth knowing before you write code against it.

**An item carries more representations than the writer asked for.** AppKit adds text flavors of its own: copying rich text from TextEdit yields `public.rtf`, `public.utf8-plain-text` and `public.utf16-external-plain-text` together. Match the type you need; do not compare the set of types for equality.

**`totalBytes` is the sum of every representation of every item, not the size of what was copied.** Copying a single text file in Finder measured about 850 KB, because the pasteboard also carries the file's icon as `com.apple.icns`.

#### Read Data for one type

`readData` returns the bytes of a single type, or `nil` when the pasteboard has no such type. **A missing type is an ordinary result, not an error.**

```swift
Task {
    let data = try await MacClipboardManager.shared.readData(
        utType: "public.utf8-plain-text",
        scope: scope
    )
    print(data?.count ?? -1)   // nil when there is no plain text
}
```

A file copied in Finder does carry `public.utf8-plain-text`, and those bytes are generally the file's full path. Treat what you read as content the user may not have meant to hand over.

#### Snapshot

`snapshot` reports the types and the change count without reading the contents.

```swift
Task {
    let snapshot = try await MacClipboardManager.shared.snapshot(scope: scope)
    print(snapshot.itemTypes.count, snapshot.changeCount)
}
```

#### Snapshot with a type filter

```swift
Task {
    let snapshot = try await MacClipboardManager.shared.snapshot(
        matchingTypes: ["public.utf8-plain-text"],
        scope: scope
    )
    print(snapshot.matchingItemIndexes)
}
```

#### Snapshot with an empty filter (error 1512)

An empty filter would match nothing, which reads the same as an empty pasteboard at the call site, so it is rejected instead.

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.snapshot(matchingTypes: [], scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1512
    }
}
```

#### Access Behavior

Synchronous. Reports how the system treats programmatic reads of this pasteboard.

```swift
let behavior = try MacClipboardManager.shared.accessBehavior(scope: scope)
```

### Detect

Detection requires **macOS 15.4 or later**. Below that the operations throw `detectionUnavailable` (1513) without reading anything.

#### Detect Patterns

Reports which patterns match, without reading the contents.

```swift
Task {
    let found = try await MacClipboardManager.shared.detectPatterns(
        [.probableWebURL, .links, .emailAddresses],
        scope: scope
    )
}
```

#### Detect Values

Returns the matched values. **This one reads the contents**, so call it from a user-initiated action.

```swift
Task {
    let values = try await MacClipboardManager.shared.detectValues(
        [.probableWebURL, .links, .emailAddresses],
        scope: scope
    )
    print(values.links.count, values.emailAddresses.count)
}
```

#### Detect Metadata

```swift
Task {
    let metadata = try await MacClipboardManager.shared.detectMetadata(scope: scope)
}
```

#### Detect with no patterns (error 1503)

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.detectPatterns([], scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1503
    }
}
```

### Observe

#### Start Observing

Synchronous. `onEvent` runs on the main actor each time the pasteboard changes.

```swift
try MacClipboardManager.shared.startObserving(scope: scope) { event in
    print(event.changeCount)
}
```

Observation pauses while your app is inactive and reconciles when it returns: **three changes made while you were in the background arrive as one event**, because a pasteboard keeps no history of what it held.

#### Invalid interval (error 1523)

The interval must be greater than 0 and at most 60 seconds.

```swift
do {
    try MacClipboardManager.shared.startObserving(scope: scope, interval: 0) { _ in }
} catch let error as ClipboardError {
    print(error.errorCode)   // 1523
}
```

#### Stop Observing

Idempotent and non-throwing. Call it when the screen goes away; the manager is shared and would otherwise keep polling.

```swift
MacClipboardManager.shared.stopObserving()
```

#### Check Foreground Change

Synchronous. Reports whether the pasteboard changed since this app last looked, and returns `true` on the first call for a scope.

```swift
let changed = try MacClipboardManager.shared.checkForegroundChange(scope: scope)
```

**Use this instead of observation, not alongside it.** Both move the same mark, so while observation is running this returns `false` almost always: the poll has already seen the change and reported it through `onEvent`.

### Paste Control

`makePasteButton` returns a system paste button as an `NSView`. It is synchronous: building a view is an immediate factory operation, and the load it starts when pressed reports through `onPaste`.

```swift
let button = try MacClipboardManager.shared.makePasteButton(
    acceptedTypes: ["public.utf8-plain-text", "public.png"],
    timeout: 5
) { result in
    print(result.items.count, result.failures.count, result.isPartial)
}
```

Host it in SwiftUI with an `NSViewRepresentable`, and build it **once**: each call registers a loader.

```swift
struct PasteButtonHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

<p align="center">
    <img src="images/mac/clipboard/Example_MacClipboardManager_PasteControl.png" alt="Example_MacClipboardManager_PasteControl" width="400" />
</p>

Three things follow from how the system control behaves.

**The button is general scope only.** It pastes from the system pasteboard whatever scope your other calls use.

**The system hands the loader only what matches `acceptedTypes`.** An item whose type you did not accept never reaches you: pasting a pasteboard that holds one accepted item and one unaccepted item yields one item, not a partial failure.

**The button stays enabled** whether or not the pasteboard holds a type you accept.

#### Invalid type identifier (error 1504)

A type identifier the system cannot resolve is rejected when the button is built, not when it is pressed.

```swift
do {
    _ = try MacClipboardManager.shared.makePasteButton(acceptedTypes: ["not a uti"]) { _ in }
} catch let error as ClipboardError {
    print(error.errorCode)   // 1504
}
```

### Clear

`clear` empties the pasteboard and returns **the pasteboard's new change count**, which is what `clearContents()` reports. It is not a count of the items that were removed.

```swift
Task {
    let changeCount = try await MacClipboardManager.shared.clear(scope: scope)
}
```

### Error Handling

Every operation throws `ClipboardError`, which carries an `errorCode` and an `errorMessage`.

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.copy(content, scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorMessage)
    }
}
```

| Code | Case | When |
|---|---|---|
| 1501 | `emptyContent` | `copy` or `append` with no items |
| 1502 | `emptyRepresentations` | An item with no representations |
| 1503 | `emptyDetectionPatterns` | Detection with an empty pattern set |
| 1504 | `invalidTypeIdentifier` | A type identifier the system cannot resolve |
| 1505 | `invalidPasteboardName` | An empty or malformed pasteboard name |
| 1506 | `contentTooLarge` | The content exceeds the size limit |
| 1507 | `pasteboardUnavailable` | The named pasteboard could not be resolved |
| 1508 | `cannotReleaseStandardPasteboard` | `removePasteboard` on a standard pasteboard |
| 1509 | `writeRejected` | The pasteboard refused the write |
| 1510 | `appendRejected` | The pasteboard refused the append while ownership still held |
| 1511 | `ownershipLost` | Something else wrote to the pasteboard since the copy |
| 1512 | `emptyTypeFilter` | `snapshot` with an empty filter |
| 1513 | `detectionUnavailable` | Detection below macOS 15.4 |
| 1514 | `detectionDenied` | The user denied access during detection (see below) |
| 1515 | `detectionFailed` | Detection failed for any other reason |
| 1521 | `pasteLoadFailed` | An item could not be loaded after a paste |
| 1522 | `pasteLoadTimedOut` | The paste load passed its deadline |
| 1523 | `invalidConfiguration` | An observation interval outside 0 to 60 seconds |
| 1524 | `cancelled` | The operation was cancelled |
| 1599 | `unknown` | Anything else |

#### About 1514

1514 means the user denied access to the pasteboard contents during detection. **Whether this path occurs on macOS has not been confirmed**: no detection prompt appeared in testing, and a refusal may instead arrive as 1515.

**Do not branch on 1514 alone.** Treat a refusal and an ordinary detection failure the same way, as "the contents could not be detected". That handling is correct either way.

#### Error codes you will not see from ordinary use

1506, 1507, 1509, 1510, 1521, 1522 and 1524 describe conditions the API can report but that an application cannot easily produce on purpose. They are listed so that a code you receive can be looked up, not because you need a branch for each.

---

## Windows

The Win32 clipboard and the WinRT clipboard history, on Windows 11 or later. The Windows library offers them through two public APIs over one implementation, and the sample app uses the C++ API.

| API | Names | Header | NuGet package |
|---|---|---|---|
| C++ API | `NativeToolkit::Clipboard` | `<NativeToolkit/Clipboard.h>` | `NativeToolkit` |
| C ABI | `ntk_clipboard_*` | `<NativeToolkitC/Clipboard.h>` | `NativeToolkit.CApi` |

- Scope: copy and paste for text, HTML, files, images and custom formats; multi-format writes; content inspection; change monitoring; delayed rendering; and clipboard history.

The screenshot in this section comes from `WindowsLibraryExample`, whose Clipboard screen groups the operations in the same order as the sections below.

<p align="center">
    <img src="images/windows/clipboard/Example_WindowsClipboardManager.png" alt="Example_WindowsClipboardManager" width="800" />
</p>

---

### Setup

```cpp
#include <NativeToolkit/Clipboard.h>

namespace Clipboard = NativeToolkit::Clipboard;
```

#### The owner STA thread

The thread that calls `Clipboard::Session::Create` owns the session, and it has two obligations:

1. It must run a message pump for the lifetime of the session. This cannot be checked at run time, so it is a caller contract rather than a reported error.
2. It must already be a single-threaded apartment (`CoInitializeEx` with `COINIT_APARTMENTTHREADED`, or `winrt::init_apartment(winrt::apartment_type::single_threaded)`). This **is** checked: an MTA or uninitialised thread gets `ErrorCode::WrongApartment` and no session is created.

The toolkit never initialises or uninitialises the apartment; it belongs to the host.

There is one clipboard per process, so a second `Create` fails: `ErrorCode::NotSupported` from the owning thread, `ErrorCode::WrongThread` from any other.

Operations that touch process-wide state are limited to the owner thread and return `ErrorCode::WrongThread` elsewhere: `SetHistoryHandlers`, `Close`, `ReserveDeferred` and `RecoverDeferredState`. Every handler is delivered on the owner thread.

Inside a handler, do not destroy the session and do not call `Close` or `SetHistoryHandlers` on it. Do not capture the session in a handler you give it either - that is a cycle.

#### Synchronous and asynchronous operations

| Shape | Result | Used by |
|---|---|---|
| Synchronous | `Clipboard::Result<T>`, before returning | Every copy, paste and inspection operation |
| Asynchronous request | `Clipboard::Result<RequestId>`; the handler runs exactly once | The five clipboard history operations |

An accepted request returns its `RequestId` and its handler runs exactly once, on the owner thread. A rejected request returns a failure and never runs the handler.

The values are typed: reads hand back a `std::wstring` or a `std::vector<std::byte>`, so there is no sizing call and no buffer to manage.

#### Write options

Every copy operation takes `Clipboard::WriteOptions`, which controls how Windows may propagate the content. Both fields default to allowed.

| Field | Effect |
|---|---|
| (none set) | No restriction |
| `excludeFromHistory` | Keeps the entry out of the clipboard history (Win+V) |
| `excludeFromRoaming` | Keeps the entry from syncing to other devices |
| both | What the C ABI calls SENSITIVE |

These affect history and roaming only. Content written with any of them is still pasted normally with Ctrl+V. Placing the markers is not best effort: a failure rolls the whole write back.

---

### Init / Lifecycle

#### Create the session

```cpp
#include <optional>

// Move only, and it outlives the screen that created it.
std::optional<Clipboard::Session> g_session;

void OnClipboardChanged()
{
    // Someone other than this session wrote to the clipboard.
    // Delivered on the owner thread, never inside the call that caused it.
}

Clipboard::SessionOptions options;
// Leaving this empty skips registering the listener.
options.onClipboardChanged = &OnClipboardChanged;

auto created = Clipboard::Session::Create(options);
if (created.has_value())
{
    g_session.emplace(std::move(created).value());
}
else
{
    // WrongApartment: the calling thread is not an initialised STA.
    const Clipboard::ErrorCode code = created.error().code;
}
```

#### History event handlers

Owner thread only. A default-constructed `HistoryHandlers` unregisters everything. `onHistoryChanged` fires when an item is added, not when one is removed or the history is cleared.

```cpp
Clipboard::HistoryHandlers handlers;
handlers.onHistoryChanged = &OnHistoryChanged;                  // void()
handlers.onHistoryEnabledChanged = &OnHistoryEnabledChanged;    // void(bool)
handlers.onRoamingEnabledChanged = &OnRoamingEnabledChanged;    // void(bool)

const auto result = g_session->SetHistoryHandlers(std::move(handlers));
// On failure the previous handlers stay in place.
```

#### Close

Owner thread only. Closing is the caller's job: `Close` reports why it could not finish, and a caller that gets a failure is expected to deal with it and try again.

```cpp
const auto closed = g_session->Close();
if (closed.has_value())
{
    g_session.reset();
}
else
{
    // Busy: another thread is still inside an operation. Let it finish and retry.
}
```

Destroying a session that was never closed successfully **abandons** it: its window, its listeners and its pending requests stay in place until the process exits, and `Create` keeps failing from then on with no way back.

#### CanClose

Answers whether a `Close` could finish now - that is, whether there is no work in flight. It is false while an operation is running, and an open session with nothing in flight answers true.

```cpp
const bool canClose = !g_session.has_value() || g_session->CanClose();
```

---

### Copy

#### Copy Plain Text

```cpp
const auto result = g_session->CopyText(L"Hello from native-toolkit", Clipboard::WriteOptions{});
```

#### Copy Plain Text (Empty)

An empty string is a valid payload, not an error.

```cpp
const auto result = g_session->CopyText(L"", Clipboard::WriteOptions{});
```

#### Copy HTML

The CF_HTML header is built inside the library. The second argument is the plain-text alternative written alongside it.

```cpp
const auto result = g_session->CopyHtml(
    L"<b>Hello</b> from native-toolkit",   // the HTML fragment
    L"Hello from native-toolkit",          // the plain text alternative
    Clipboard::WriteOptions{});
```

#### Copy Files

Every path is a full path, and the list must not be empty.

```cpp
const std::vector<std::wstring> paths{ firstFilePath, secondFilePath };
const auto result = g_session->CopyFiles(paths, Clipboard::WriteOptions{});
```

#### Copy Image

The bytes are a packed DIB (a `BITMAPINFOHEADER`, its colour table if any, and the pixels). The library checks the header.

```cpp
const std::vector<std::byte> dib = BuildSampleDib();  // 8x8, 32bpp, BI_RGB
const auto result = g_session->CopyDib(dib, Clipboard::WriteOptions{});
```

#### Copy Custom Format

The name is registered with Windows if it is not a standard one.

```cpp
const std::vector<std::byte> blob = ToBytes("native-toolkit-sample-payload");
const auto result = g_session->CopyCustom(L"NativeToolkitSample", blob, Clipboard::WriteOptions{});
```

#### Copy Multiple Formats

One clipboard write that places several formats at once. An item is text, HTML or bytes - never half of each - and the placement order is part of what receiving applications see, so the richest format goes first.

```cpp
const std::vector<Clipboard::FormatPayload> items{
    Clipboard::HtmlPayload{ L"HTML Format", L"<b>Hello</b> from native-toolkit" },
    Clipboard::TextPayload{ L"CF_UNICODETEXT", L"Hello from native-toolkit" },
    Clipboard::BytesPayload{ L"CF_DIB", BuildSampleDib() },
};
const auto result = g_session->CopyMultiple(items, Clipboard::WriteOptions{});
```

A duplicate format name, or an item whose payload does not suit its format, is `ErrorCode::InvalidParameter` and nothing is written.

---

### Write Options

```cpp
// Both exclusions at once: what the C ABI calls SENSITIVE.
const Clipboard::WriteOptions sensitive{ true, true };
const auto result = g_session->CopyText(L"Sensitive sample value", sensitive);

// One at a time.
const Clipboard::WriteOptions excludeHistory{ true, false };
const Clipboard::WriteOptions excludeRoaming{ false, true };
```

---

### Paste

#### Paste Plain Text

```cpp
const auto text = g_session->PasteText();
if (text.has_value())
{
    const std::wstring& value = text.value();
}
else if (text.error().code == Clipboard::ErrorCode::FormatUnavailable)
{
    // There is no text on the clipboard.
}
```

#### Paste HTML

Returns the fragment, with the CF_HTML header removed.

```cpp
const auto html = g_session->PasteHtml();
```

#### Paste Files

```cpp
const auto files = g_session->PasteFiles();
if (files.has_value())
{
    for (const std::wstring& path : files.value())
    {
        // One dropped file.
    }
}
```

#### Paste Image

Hands back the packed DIB as it sits on the clipboard.

```cpp
const auto pasted = g_session->PasteDib();
if (pasted.has_value())
{
    const std::vector<std::byte>& dib = pasted.value();
}
```

#### Paste Custom Format

```cpp
const auto pasted = g_session->PasteCustom(L"NativeToolkitSample");
```

---

### Inspect / Clear

#### Has Format

```cpp
const auto present = g_session->HasFormat(L"CF_UNICODETEXT");
const bool yes = present.has_value() && present.value();
```

#### Get Clipboard Formats

Every format currently on the clipboard, by name.

```cpp
const auto formats = g_session->GetFormats();
```

#### Get Preferred Format

The format Windows would hand over first. An empty string means there is no candidate.

```cpp
const auto name = g_session->GetPreferredFormat();
```

#### Clear Clipboard

```cpp
const auto result = g_session->Clear();
```

---

### Deferred Rendering

The session offers formats without producing their bytes, and the provider is asked for them only when an application pastes.

#### Reserve Deferred Formats

Owner thread only. The provider runs on the owner thread, inside the message that collects the data, which sets three hard limits: it must not call any clipboard operation, it must not block, and it must not capture the session.

```cpp
Clipboard::Result<std::vector<std::byte>> RenderDeferredFormat(std::wstring_view formatName)
{
    const auto it = g_deferredPayloads.find(std::wstring(formatName));
    if (it == g_deferredPayloads.end())
    {
        return NativeToolkit::Unexpected{ Clipboard::Error{ Clipboard::ErrorCode::FormatUnavailable } };
    }
    return it->second;   // the bytes, decided when the formats were offered
}

const std::vector<std::wstring> formats{ L"HTML Format", L"CF_UNICODETEXT" };
const auto result = g_session->ReserveDeferred(formats, &RenderDeferredFormat);
```

Returning a failure, or throwing, renders that format as nothing: by then the asking application is mid-paste and there is no one left to report to. Both are logged.

#### Recover Deferred State

Owner thread only. Clears a half-placed reservation after `ErrorCode::PartialState`.

```cpp
const auto result = g_session->RecoverDeferredState();
```

---

### History

The five history operations are asynchronous: each returns a `RequestId` and calls its handler exactly once, on the owner thread. `ErrorCode::HistoryDisabled` means the user has the history turned off in Windows Settings.

#### Get History Availability

```cpp
const auto accepted = g_session->GetHistoryAvailability(
    [](Clipboard::RequestId id, Clipboard::Result<Clipboard::HistoryAvailability> result)
    {
        if (result.has_value())
        {
            const bool historyEnabled = result.value().historyEnabled;
            const bool roamingEnabled = result.value().roamingEnabled;
        }
    });
```

#### Get Clipboard History

```cpp
const auto accepted = g_session->GetHistory(
    [](Clipboard::RequestId id, Clipboard::Result<std::vector<Clipboard::HistoryItem>> result)
    {
        if (!result.has_value()) return;
        for (const Clipboard::HistoryItem& item : result.value())
        {
            const std::wstring& id = item.id;                  // for restore / delete
            const std::optional<std::wstring>& text = item.text;  // absent for a non-text item
            const std::vector<std::wstring>& types = item.contentTypes;
            const int64_t ticks = item.timestampTicks;
        }
    });
```

#### Restore History Item

Puts the item back on the clipboard. The id comes from `GetHistory`.

```cpp
const auto accepted = g_session->RestoreHistoryItem(itemId,
    [](Clipboard::RequestId id, Clipboard::Result<void> result) { /* ... */ });
```

#### Delete History Item

`ErrorCode::ItemDeleted` means the item is already gone.

```cpp
const auto accepted = g_session->DeleteHistoryItem(itemId,
    [](Clipboard::RequestId id, Clipboard::Result<void> result) { /* ... */ });
```

#### Clear Unpinned History

Removes everything the user has not pinned.

```cpp
const auto accepted = g_session->ClearUnpinnedHistory(
    [](Clipboard::RequestId id, Clipboard::Result<void> result) { /* ... */ });
```

#### Cancel Request

Cancels a request that has not completed. Its handler still runs, once, with `ErrorCode::Canceled`.

```cpp
if (accepted.has_value())
{
    const auto result = g_session->CancelRequest(accepted.value());
}
```

---

### Error Handling

Synchronous operations report through the returned `Result`; asynchronous requests report through the `Result` their handler receives. `Clipboard::Error` carries the case and the raw `systemCode`.

```cpp
const auto result = g_session->CopyText(text, Clipboard::WriteOptions{});
if (!result.has_value())
{
    const Clipboard::ErrorCode code = result.error().code;
    const uint32_t systemCode = result.error().systemCode;
}
```

`Clipboard::ErrorCode` (`NativeToolkit::ClipboardError`). The same numbers are the C ABI's `NTK_CLIPBOARD_ERROR_*`.

| Code | Name | When |
|---|---|---|
| 0 | `None` | Success |
| 1 | `InvalidParameter` | A malformed argument, an empty file list, a duplicate or mismatched multi-format entry, `CF_BITMAP` |
| 2 | `NotInitialized` | Used before `Create`, or after `Close` |
| 3 | `Busy` | The clipboard could not be opened, or `Close` still has work in flight |
| 4 | `Empty` | The format is present but carries no data |
| 5 | `FormatUnavailable` | The requested format is not on the clipboard |
| 6 | `InvalidData` | The data failed structural validation, such as a malformed DIB |
| 7 | `BufferTooSmall` | Reserved: never returned. The 1.x C ABI's caller buffer was too small |
| 8 | `OutOfMemory` | An allocation failed |
| 9 | `AccessDenied` | The system refused the operation |
| 10 | `HistoryDisabled` | Clipboard history is turned off in Windows Settings |
| 11 | `ItemDeleted` | The history item no longer exists |
| 12 | `MonitorRegisterFailed` | A listener or event token could not be registered or revoked |
| 13 | `PartialState` | A placement failed and the rollback failed too; call `RecoverDeferredState` |
| 14 | `WrongThread` | An owner-thread-only operation was called from another thread |
| 15 | `Canceled` | Cancelled, or drained by `Close` |
| 16 | `NotSupported` | No Windows equivalent, or a second session |
| 17 | `NotForeground` | This process is not in the foreground; reported through the handler |
| 18 | `WrongApartment` | The calling thread is not an STA |
| 19 | `Unknown` | Anything else |

### C ABI

- The same clipboard for C, and for any language that can call a C DLL.
- The session is a handle: `ntk_clipboard_session_create` on an STA thread that pumps messages, then `ntk_clipboard_session_close` from that same thread and `ntk_clipboard_session_free`.
- `ntk_clipboard_reserve_deferred` takes `user_data` and a `release` callback, and `release` is called exactly once whatever the call returned - that is where a binding frees what it allocated. The session options and the history handlers carry `user_data` only; they last as long as the session.
- Reads hand back handles: `ntk_string`, `ntk_bytes` and `ntk_string_list`, each freed with its own `_free`. A pointer read from a handle stays valid until that handle is freed.

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Clipboard.h>

static void NTK_CALL on_clipboard_changed(void* user_data)
{
    /* On the owner thread. */
    (void)user_data;
}

ntk_clipboard_session_options options;
memset(&options, 0, sizeof(options));
options.struct_size = (uint32_t)sizeof(options);
options.on_clipboard_changed = &on_clipboard_changed;
options.user_data = NULL;

ntk_clipboard_session* session = NULL;
ntk_clipboard_error error = ntk_clipboard_session_create(&options, &session);
if (error != NTK_CLIPBOARD_ERROR_NONE) {
    return;   /* WRONG_APARTMENT when the thread is not an STA */
}

/* Write, then read back. Strings are UTF-8. */
error = ntk_clipboard_copy_text(session, "Hello from native-toolkit", NTK_CLIPBOARD_WRITE_DEFAULT);

ntk_string* text = NULL;
if (ntk_clipboard_paste_text(session, &text) == NTK_CLIPBOARD_ERROR_NONE) {
    const char* utf8 = ntk_string_data(text);   /* valid until ntk_string_free */
    (void)utf8;
    ntk_string_free(text);
}

/* From the owner thread, and check the result: close can fail. */
error = ntk_clipboard_session_close(session);
ntk_clipboard_session_free(session);
```

| C++ API | C ABI |
|---|---|
| `Session::Create` | `ntk_clipboard_session_create` |
| `Session::Close` / destructor | `ntk_clipboard_session_close` / `ntk_clipboard_session_free` |
| `Session::CanClose` | `ntk_clipboard_session_can_close` |
| `Session::SetHistoryHandlers` | `ntk_clipboard_set_history_handlers` |
| `CopyText` / `CopyHtml` / `CopyFiles` / `CopyDib` / `CopyCustom` | `ntk_clipboard_copy_text` / `_copy_html` / `_copy_files` / `_copy_dib` / `_copy_custom` |
| `CopyMultiple` with `FormatPayload` | `ntk_clipboard_items_create` and its `_add_text` / `_add_html` / `_add_bytes`, then `ntk_clipboard_copy_multiple` |
| `PasteText` / `PasteHtml` / `PasteFiles` / `PasteDib` / `PasteCustom` | `ntk_clipboard_paste_text` / `_paste_html` / `_paste_files` / `_paste_dib` / `_paste_custom` |
| `HasFormat` / `GetFormats` / `GetPreferredFormat` / `Clear` | `ntk_clipboard_has_format` / `_get_formats` / `_get_preferred_format` / `_clear` |
| `ReserveDeferred` / `RecoverDeferredState` | `ntk_clipboard_reserve_deferred` / `_recover_deferred_state` |
| `GetHistory` / `RestoreHistoryItem` / `DeleteHistoryItem` / `ClearUnpinnedHistory` / `GetHistoryAvailability` | `ntk_clipboard_get_history` / `_restore_history_item` / `_delete_history_item` / `_clear_unpinned_history` / `_get_history_availability` |
| `CancelRequest` | `ntk_clipboard_cancel_request` |
| `WriteOptions` | The `flags` argument: `NTK_CLIPBOARD_WRITE_DEFAULT` / `_EXCLUDE_HISTORY` / `_EXCLUDE_ROAMING` / `_SENSITIVE` |
