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
