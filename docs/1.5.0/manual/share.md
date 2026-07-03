# Share Feature

Language:

- 日本語: [share.ja.md](share.ja.md)
- English (this page)
- 한국어: [share.ko.md](share.ko.md)

← [Back to Manual Top](index.md)

---

## Table of Contents

- [Android](#android)
  - [Setup](#setup)
  - [Text Share](#text-share)
    - [Share Text](#share-text)
    - [Share URL](#share-url)
    - [Share Text with Rich Preview](#share-text-with-rich-preview)
    - [Share Text with Custom Chooser Action](#share-text-with-custom-chooser-action)
    - [Chooser Action Callback](#chooser-action-callback)
    - [Share with Subject and Title](#share-with-subject-and-title)
  - [Image Share](#image-share)
  - [Multiple Images](#multiple-images)
  - [File Share](#file-share)
  - [Multiple Files](#multiple-files)
  - [Direct Share Target](#direct-share-target)
    - [Register Direct Share Target](#register-direct-share-target)
    - [Remove Direct Share Target](#remove-direct-share-target)
  - [Share with Callback](#share-with-callback)
    - [Basic Callback](#basic-callback)
    - [Callback with Rich Preview](#callback-with-rich-preview)
    - [Cancel Pending Callback](#cancel-pending-callback)
  - [Receiving Incoming Shares](#receiving-incoming-shares)
  - [Error Handling](#error-handling)

---

## Android

- Library: `android-native-toolkit-1.2.0.aar`
- Minimum SDK: Android 12 (API 31)
- Custom Chooser Actions: Android 14 (API 34)+

### Setup

#### Android native (AAR)

1. Place `android-native-toolkit-1.2.0.aar` in `app/libs`.
2. Add dependency in `app/build.gradle.kts`:

```kotlin
dependencies {
    implementation(files("libs/android-native-toolkit-1.2.0.aar"))
}
```

3. Declare a `FileProvider` in `AndroidManifest.xml` for file/image sharing:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

4. Create `res/xml/file_paths.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="share_cache" path="." />
    <external-cache-path name="share_external_cache" path="." />
    <files-path name="share_files" path="." />
</paths>
```

---

### Text Share

#### Share Text

```kotlin
val shareUseCases = ShareUseCases(activity)

try {
    shareUseCases.shareText(
        ShareContent(text = "Hello from native-toolkit"),
        chooserActionsJson = "[]"
    )
} catch (e: ShareDomainError) {
    // handle error
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareText.png" alt="Example_ShareSampleScreen_ShareText" width="400" />
</p>

#### Share URL

```kotlin
shareUseCases.shareText(
    ShareContent(
        text = "https://developer.android.com/",
        mimeType = "text/plain"
    ),
    chooserActionsJson = "[]"
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareURL.png" alt="Example_ShareSampleScreen_ShareURL" width="400" />
</p>

#### Share Text with Rich Preview

Rich preview requires Android 31+ and a valid thumbnail file path.

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val file = File(context.cacheDir, "share_preview.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareUseCases.shareText(
    ShareContent(
        text = "https://developer.android.com/",
        mimeType = "text/plain"
    ),
    chooserActionsJson = "[]",
    SharePreviewOptions(
        title = "Introducing content previews",
        thumbnailPath = file.absolutePath
    )
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareTextWithRichPreview.png" alt="Example_ShareSampleScreen_ShareTextWithRichPreview" width="400" />
</p>

#### Share Text with Custom Chooser Action

Custom chooser actions require Android 14 (API 34)+. On older devices the `chooserActionsJson` parameter is ignored.

- `intentAction` must be **unique, non-blank**, and must not be `android.intent.action.SEND`.
- Recommended namespace: `${applicationId}.share.action.<name>`

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_edit)
val iconBase64 = ByteArrayOutputStream().use { baos ->
    bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
    Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
}

val chooserActionsJson = JSONArray().put(
    JSONObject().apply {
        put("label", "Custom")
        put("iconBase64", iconBase64)
        put("intentAction", "com.example.myapp.share.action.CUSTOM")
    }
).toString()

shareUseCases.shareText(
    ShareContent(
        text = "Shared with a custom chooser action",
        mimeType = "text/plain"
    ),
    chooserActionsJson = chooserActionsJson
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareTextWithCustomAction.png" alt="Example_ShareSampleScreen_ShareTextWithCustomAction" width="400" />
</p>

To receive a callback when the custom action is tapped, see [Chooser Action Callback](#chooser-action-callback).

#### Chooser Action Callback

Declare a `BroadcastReceiver` in `AndroidManifest.xml`. The `android:name` of the `<action>` must match the `intentAction` passed in `chooserActionsJson`.

```xml
<receiver
    android:name=".ShareChooserActionReceiver"
    android:exported="false">
    <intent-filter>
        <action android:name="com.example.myapp.share.action.CUSTOM" />
    </intent-filter>
</receiver>
```

Implement the receiver:

```kotlin
class ShareChooserActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context != null) {
            Toast.makeText(context, "Custom chooser action tapped", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        const val ACTION_CUSTOM_CHOOSER = "com.example.myapp.share.action.CUSTOM"
    }
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ChooserActionCallback.png" alt="Example_ShareSampleScreen_ChooserActionCallback" width="400" />
</p>

#### Share with Subject and Title

`subject` sets the email subject line. `title` sets the Sharesheet title.

```kotlin
shareUseCases.shareText(
    ShareContent(
        text = "Body text shared from native-toolkit",
        title = "Choose an app",
        subject = "Sample subject line",
        mimeType = "text/plain"
    ),
    chooserActionsJson = "[]"
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithSubjectAndTitle.png" alt="Example_ShareSampleScreen_ShareWithSubjectAndTitle" width="400" />
</p>

---

### Image Share

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_share)
val file = File(context.cacheDir, "share_sample.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareUseCases.shareImage(file.absolutePath, "image/png")
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareImage.png" alt="Example_ShareSampleScreen_ShareImage" width="400" />
</p>

---

### Multiple Images

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_share)
val file1 = File(context.cacheDir, "share_sample_1.png")
val file2 = File(context.cacheDir, "share_sample_2.png")
file1.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
file2.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareUseCases.shareImages(listOf(file1.absolutePath, file2.absolutePath))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareMultipleImages.png" alt="Example_ShareSampleScreen_ShareMultipleImages" width="400" />
</p>

---

### File Share

```kotlin
val file = File(context.cacheDir, "share_sample.txt")
    .apply { writeText("Share sample from native-toolkit") }

shareUseCases.shareFile(file.absolutePath)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareFile.png" alt="Example_ShareSampleScreen_ShareFile" width="400" />
</p>

---

### Multiple Files

```kotlin
val file1 = File(context.cacheDir, "share_sample_1.txt")
    .apply { writeText("Share sample 1 from native-toolkit") }
val file2 = File(context.cacheDir, "share_sample_2.txt")
    .apply { writeText("Share sample 2 from native-toolkit") }

shareUseCases.shareFiles(listOf(file1.absolutePath, file2.absolutePath))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareMultipleFiles.png" alt="Example_ShareSampleScreen_ShareMultipleFiles" width="400" />
</p>

---

### Direct Share Target

Direct Share Targets appear in the Sharesheet as suggested recipients without requiring the user to select an app first.

#### Register Direct Share Target

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val baos = ByteArrayOutputStream()
bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
val iconBytes = baos.toByteArray()

shareUseCases.registerDirectShareTarget(
    DirectShareTarget(
        id = "sample_1",
        label = "Sample User",
        category = "android.shortcut.conversation"
    ),
    iconBytes
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_RegisterDirectShareTarget.png" alt="Example_ShareSampleScreen_RegisterDirectShareTarget" width="400" />
</p>

#### Remove Direct Share Target

```kotlin
shareUseCases.removeDirectShareTargets(listOf("sample_1"))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_RemoveDirectShareTarget.png" alt="Example_ShareSampleScreen_RemoveDirectShareTarget" width="400" />
</p>

---

### Share with Callback

`shareWithCallback` opens the Sharesheet and reports the selected app package name via `onResult`. `onFinished` is called when the Sharesheet is dismissed regardless of selection.

#### Basic Callback

```kotlin
shareUseCases.shareWithCallback(
    ShareContent(text = "Hello with callback from native-toolkit")
) { pkg ->
    // pkg == null if selected but the package was unavailable
    val status = if (pkg != null) "Selected: $pkg" else "Shared (package unavailable)"
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallback.png" alt="Example_ShareSampleScreen_ShareWithCallback" width="400" />
</p>

To cancel the pending receiver before the user selects, call `cancelPendingCallback()`.

#### Callback with Rich Preview

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val file = File(context.cacheDir, "callback_preview.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareUseCases.shareWithCallback(
    ShareContent(
        text = "https://developer.android.com/",
        mimeType = "text/plain"
    ),
    SharePreviewOptions(
        title = "Callback with rich preview",
        thumbnailPath = file.absolutePath
    ),
    onResult = { pkg ->
        val status = if (pkg != null) "Selected: $pkg" else "Shared (package unavailable)"
    },
    onFinished = {
        // Sharesheet dismissed
    }
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallbackRichPreview.png" alt="Example_ShareSampleScreen_ShareWithCallbackRichPreview" width="400" />
</p>

#### Cancel Pending Callback

Cancels the pending `shareWithCallback` BroadcastReceiver. Call this when the current screen is being torn down to avoid leaking the receiver.

```kotlin
shareUseCases.cancelPendingCallback()
```

To cancel automatically when a composable screen is removed:

```kotlin
DisposableEffect(shareUseCases) {
    onDispose { shareUseCases.cancelPendingCallback() }
}
```

---

### Receiving Incoming Shares

The sample app also demonstrates receiving content shared from other apps via `ACTION_SEND` and `ACTION_SEND_MULTIPLE`.

To receive incoming shares, declare intent filters in `AndroidManifest.xml` on the receiving `Activity` and handle them in `onCreate` / `onNewIntent`:

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTop">
    <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="text/*" />
    </intent-filter>
    <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="image/*" />
    </intent-filter>
    <intent-filter>
        <action android:name="android.intent.action.SEND_MULTIPLE" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="image/*" />
    </intent-filter>
</activity>
```

---

### Error Handling

`ShareUseCases` throws `ShareDomainError` subtypes.

| Error | Cause | Error message |
|---|---|---|
| `EmptyContent` | `text` is blank | `"Share content is empty. Please provide text or a file path."` |
| `FileNotFound` | File path does not exist | `"File not found: <path>"` |
| `IllegalFileAccess` | File is outside accessible directories | `"File cannot be shared: <path>. Ensure the file is in a supported directory."` |
| `InvalidMimeType` | Unsupported MIME type | `"Invalid MIME type: <mimeType>"` |
| `NoShareTarget` | No app can handle the share intent | `"No app available to handle this share request."` |
| `DirectShareRegistrationFailed` | Shortcut registration failed | `"Failed to register Direct Share target: <reason>"` |
| `EmptyIdList` | `ids` list is empty in removeDirectShareTargets | `"No shortcut IDs provided for removal."` |
| `EmptyFileList` | `filePaths` list is empty in shareFiles / shareImages | `"No file paths provided for share."` |
| `InvalidBase64Icon` | Base64 decoding failed for icon | `"Invalid icon data for Direct Share target: <id>"` |

```kotlin
try {
    shareUseCases.shareText(ShareContent(text = "Hello"), chooserActionsJson = "[]")
} catch (e: ShareDomainError.NoShareTarget) {
    // No app can handle this share
} catch (e: ShareDomainError.EmptyContent) {
    // Text was blank
} catch (e: ShareDomainError) {
    // Other domain error
}
```
