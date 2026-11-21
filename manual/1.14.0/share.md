# Share Feature

Language:

- 日本語: [share.ja.md](share.ja.md)
- English (this page)
- 한국어: [share.ko.md](share.ko.md)

← [Back to Manual Top](index.md)

---

## Table of Contents

- [Android](#android)
  - [AndroidShareManager](#androidsharemanager)
  - [Setup](#setup)
    - [Add the library](#add-the-library)
    - [FileProvider](#fileprovider)
    - [Threads and events](#threads-and-events)
  - [Text Share](#text-share)
    - [Share Text](#share-text)
    - [Share URL](#share-url)
    - [Share Text with Rich Preview](#share-text-with-rich-preview)
    - [Share Text with Custom Chooser Action](#share-text-with-custom-chooser-action)
    - [Chooser Action Events](#chooser-action-events)
    - [Share Text with Invalid Action](#share-text-with-invalid-action)
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
  - [Selection Event](#selection-event)
    - [Share For Selection](#share-for-selection)
    - [Cancel Share Selection](#cancel-share-selection)
  - [Receiving Incoming Shares](#receiving-incoming-shares)
  - [Error Handling](#error-handling)
  - [C ABI](#c-abi)
    - [Building](#building)
    - [Opening the Sharesheet](#opening-the-sharesheet)
    - [Selection and chooser action events](#selection-and-chooser-action-events)
    - [Direct Share targets](#direct-share-targets)
    - [Error values](#error-values)
- [iOS](#ios)
  - [IosShareManager](#iossharemanager)
  - [Setup](#setup-1)
    - [Add the library](#add-the-library-1)
    - [Threads and presenting](#threads-and-presenting)
  - [Text Share](#text-share-1)
    - [Share Text](#share-text-1)
  - [URL Share](#url-share)
    - [Share URL](#share-url-1)
    - [Share URL with Preview](#share-url-with-preview)
  - [Image Share](#image-share-1)
    - [Share Image](#share-image)
    - [Share Multiple Images](#share-multiple-images)
  - [File Share](#file-share-1)
    - [Share File](#share-file)
    - [Share Multiple Files](#share-multiple-files)
  - [Combined Content](#combined-content)
    - [Share Multiple Items](#share-multiple-items)
    - [Share with Subject](#share-with-subject)
    - [Exclude Activity Types](#exclude-activity-types)
  - [Error Handling](#error-handling-1)
  - [Presenter and Result](#presenter-and-result)
    - [Share from the Foreground](#share-from-the-foreground)
    - [Result Callback](#result-callback)
    - [Two Shares in One Turn](#two-shares-in-one-turn)
  - [C ABI](#c-abi-1)
    - [Building](#building-1)
    - [Sharing content](#sharing-content)
    - [One share sheet at a time](#one-share-sheet-at-a-time)
    - [Error values](#error-values-1)
- [macOS](#macos)
  - [MacShareManager](#macsharemanager)
  - [Setup](#setup-2)
  - [Picker - Basic](#picker---basic)
    - [Share Text](#share-text-2)
    - [Share URL](#share-url-2)
    - [Share Image](#share-image-1)
    - [Share File](#share-file-1)
  - [Picker - Multiple](#picker---multiple)
    - [Share Multiple Images](#share-multiple-images-1)
    - [Share Multiple Files](#share-multiple-files-1)
    - [Share Text and URL](#share-text-and-url)
  - [Picker - Filter](#picker---filter)
    - [Share Excluding Services](#share-excluding-services)
  - [Direct Service](#direct-service)
    - [Share via Mail](#share-via-mail)
    - [Check if a Service Can Perform](#check-if-a-service-can-perform)
  - [Error Handling](#error-handling-2)

---

## Android

The Android Sharesheet: text, URLs, images and files, rich previews, custom chooser actions, Direct Share targets, and the app the user picked. Android library 2.0.0 offers them through two public APIs over one implementation, and the sample app (`AndroidLibraryExample`) uses the Kotlin API.

| API | Names | Header / package | Maven coordinates |
|---|---|---|---|
| Kotlin API | `AndroidShareManager` | `com.jonghyunkim.nativetoolkit.share` | `io.github.kimjh4941:android-native-toolkit:2.0.0` |
| C ABI | `ntk_share_*` | `<NativeToolkitC/Share.h>` | `io.github.kimjh4941:android-native-toolkit-capi:2.0.0` |

- Libraries: `android-native-toolkit-2.0.0.aar` (Kotlin API) and `android-native-toolkit-capi-2.0.0.aar` (C ABI)
- Minimum SDK: Android 12 (API 31). The app compiles with compileSdk 36 or later, and Kotlin code that calls the library needs Kotlin 2.1 or later.
- Custom chooser actions: Android 14 (API 34)+
- Coming from 1.x: see [Migrating the Android library to 2.0.0](index.md#migrating-the-android-library-to-200).

The sections below follow the Share screen of the sample app. [C ABI](#c-abi) at the end covers the same operations for C.

---

### AndroidShareManager

`AndroidShareManager` is the entry point for sharing. There is one instance per process, and it keeps only the Application Context, so any Context can be passed to `getInstance`.

```kotlin
import com.jonghyunkim.nativetoolkit.share.AndroidShareManager

val shareManager = AndroidShareManager.getInstance(activity)
```

| Member | Description |
|---|---|
| `shareText(content, preview)` | Shares text or a URL |
| `shareTextWithActions(content, actions, preview)` | Shares text with custom chooser actions |
| `shareImage(filePath, mimeType)` / `shareImages(filePaths)` | Shares one image / several images |
| `shareFile(filePath)` / `shareFiles(filePaths)` | Shares one file / several files |
| `registerDirectShareTarget(target, iconBytes)` / `removeDirectShareTargets(ids)` | Adds / removes Direct Share targets |
| `shareWithCallback(content, preview, onResult, onFinished)` / `cancelPendingCallback()` | Shares text and reports the picked app to a callback / stops waiting |
| `shareForSelection(content, preview)` / `cancelShareSelection(token)` | Shares text and returns a token; the picked app arrives as a `selections` event / stops waiting |
| `chooserActions` | `EventHub<String>`: taps on custom chooser actions, as the action ID |
| `selections` | `EventHub<ShareSelection>`: apps picked in Sharesheets opened by `shareForSelection` |

The model types (`ShareContent`, `SharePreviewOptions`, `ShareChooserAction`, `DirectShareTarget`, `ShareSelection`) are in `com.jonghyunkim.nativetoolkit.share.domain.model`, and `ShareDomainError` is in `com.jonghyunkim.nativetoolkit.share.domain.error`. `preview` defaults to `SharePreviewOptions()` (no preview) wherever it appears.

---

### Setup

#### Add the library

The release ships a Maven repository in `dist/1.14.0/android/m2/`. Copy it into your project, for example as `third_party/native-toolkit-m2/`, and add it to the repositories:

**settings.gradle.kts:**

```kotlin
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        maven { url = uri("third_party/native-toolkit-m2") }
    }
}
```

**app/build.gradle.kts:**

```kotlin
dependencies {
    implementation("io.github.kimjh4941:android-native-toolkit:2.0.0")
}
```

The repository carries the POM and Gradle Module Metadata, so Gradle also resolves the androidx libraries the library depends on. The AAR file alone does not carry them; see [Library integration](index.md#library-integration) if you add the AAR file directly.

#### FileProvider

The AAR declares its own `FileProvider` with the authority `${applicationId}.native_toolkit.share.fileprovider`, and image, file and thumbnail sharing go through it. The app does not declare a `FileProvider` for sharing. It covers these directories:

| Path element | Directory |
|---|---|
| `files-path` | `context.filesDir` |
| `cache-path` | `context.cacheDir` |
| `external-files-path` | `context.getExternalFilesDir(...)` |

A file anywhere else, including `context.externalCacheDir`, fails with `ShareDomainError.IllegalFileAccess`.

Do not declare `androidx.core.content.FileProvider` in your own manifest: the manifest merger matches providers by `android:name`, so it conflicts with the library's. The 1.x manual told apps to declare it for sharing; remove that declaration when moving to 2.0.0 (see [Migrating the Android library to 2.0.0](index.md#migrating-the-android-library-to-200)). A provider the app needs for its own purposes must be a subclass of `FileProvider` with its own authority; the library does not use it.

#### Threads and events

- The share operations can be called from any thread. The sample prepares files on `Dispatchers.IO` and calls the library on the main thread.
- `onResult` and `onFinished` of `shareWithCallback`, and the `chooserActions` and `selections` events, are called on the main thread.
- `addListener` and `EventHub.Registration.remove` are main-thread only; elsewhere they throw `IllegalStateException`.
- Neither `chooserActions` nor `selections` keeps events: an event that arrives while no listener is registered is dropped. Register the listener before opening the Sharesheet.
- An exception thrown by an event listener is caught and logged, and the other listeners still run.
- Sharing does not depend on the library's androidx.startup initializer. An app that disables Startup still calls `LibraryRuntime.ensureInitialized(activity)` for the other features, passing the Activity (see [Initialization](index.md#initialization)).

---

### Text Share

#### Share Text

```kotlin
val shareManager = AndroidShareManager.getInstance(activity)

try {
    shareManager.shareText(
        ShareContent(text = "Hello from native-toolkit")
    )
} catch (e: ShareDomainError) {
    // See Error Handling
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareText.png" alt="Example_ShareSampleScreen_ShareText" width="400" />
</p>

#### Share URL

```kotlin
shareManager.shareText(
    ShareContent(text = "https://developer.android.com/", mimeType = "text/plain")
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareURL.png" alt="Example_ShareSampleScreen_ShareURL" width="400" />
</p>

#### Share Text with Rich Preview

`SharePreviewOptions` adds a title and a thumbnail to the Sharesheet preview. The thumbnail must be a file in one of the [FileProvider](#fileprovider) directories. A thumbnail that is missing or outside them is skipped with a warning in logcat, and the text is still shared.

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val file = File(context.cacheDir, "share_preview.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareManager.shareText(
    ShareContent(
        text = "https://developer.android.com/",
        mimeType = "text/plain"
    ),
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

`shareTextWithActions` adds `ShareChooserAction`s to the Sharesheet. They are shown on Android 14 (API 34) and later; on older versions the text is shared without them, but the actions are still checked.

| Field | Description |
|---|---|
| `id` | Comes back in the [`chooserActions` event](#chooser-action-events). Must not be empty, and must be unique within one call |
| `label` | The text shown under the icon |
| `iconBytes` | An image `BitmapFactory` can decode (PNG, JPEG, WebP) |

Each call makes the actions of earlier calls stop working: a tap on an action of an older Sharesheet is not delivered. A call rejected with `InvalidChooserAction` leaves the earlier actions working. No `BroadcastReceiver` or manifest entry is needed.

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_edit)
val iconBytes = ByteArrayOutputStream().use { baos ->
    bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
    baos.toByteArray()
}

shareManager.shareTextWithActions(
    ShareContent(
        text = "Shared with a custom chooser action",
        mimeType = "text/plain"
    ),
    listOf(ShareChooserAction(id = "custom", label = "Custom", iconBytes = iconBytes))
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareTextWithCustomAction.png" alt="Example_ShareSampleScreen_ShareTextWithCustomAction" width="400" />
</p>

#### Chooser Action Events

A tap on a custom action arrives through `chooserActions` as the action's `id`, on the main thread. The sample registers the listener for the lifetime of `MainActivity`, so a tap is received whichever screen is shown.

```kotlin
class MainActivity : AppCompatActivity() {

    private var chooserActionRegistration: EventHub.Registration? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appContext = applicationContext
        val share = AndroidShareManager.getInstance(this)
        chooserActionRegistration = share.chooserActions.addListener { id, _ ->
            // id is the ShareChooserAction.id that was tapped ("custom" above)
            Toast.makeText(appContext, "Custom chooser action tapped", Toast.LENGTH_SHORT).show()
        }
    }

    override fun onDestroy() {
        chooserActionRegistration?.remove()
        chooserActionRegistration = null
        super.onDestroy()
    }
}
```

`EventHub` is `com.jonghyunkim.nativetoolkit.common.event.EventHub`. The second parameter of the listener is its own `Registration`, which it can remove from inside the listener.

#### Share Text with Invalid Action

Two actions with the same `id` are rejected before the Sharesheet opens, with `ShareDomainError.InvalidChooserAction`. An empty `id`, or an icon that is not a readable image, is rejected the same way.

```kotlin
val icon = ByteArrayOutputStream().use { out ->
    Bitmap.createBitmap(4, 4, Bitmap.Config.ARGB_8888).compress(Bitmap.CompressFormat.PNG, 100, out)
    out.toByteArray()
}

try {
    shareManager.shareTextWithActions(
        ShareContent(text = "This share is rejected"),
        listOf(ShareChooserAction("dup", "First", icon), ShareChooserAction("dup", "Second", icon))
    )
} catch (e: ShareDomainError.InvalidChooserAction) {
    // e.id == "dup". Nothing opened, and the actions of the previous share still work.
}
```

#### Share with Subject and Title

`subject` is sent as the email subject line (`Intent.EXTRA_SUBJECT`). `title` sets the Sharesheet title.

```kotlin
shareManager.shareText(
    ShareContent(
        text = "Body text shared from native-toolkit",
        title = "Choose an app",
        subject = "Sample subject line",
        mimeType = "text/plain"
    )
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithSubjectAndTitle.png" alt="Example_ShareSampleScreen_ShareWithSubjectAndTitle" width="400" />
</p>

---

### Image Share

The file must be in one of the [FileProvider](#fileprovider) directories.

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_share)
val file = File(context.cacheDir, "share_sample.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareManager.shareImage(file.absolutePath, "image/png")
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareImage.png" alt="Example_ShareSampleScreen_ShareImage" width="400" />
</p>

---

### Multiple Images

The MIME type comes from the file extensions: the common type when all images share one, `image/*` otherwise.

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_share)
val file1 = File(context.cacheDir, "share_sample_1.png")
val file2 = File(context.cacheDir, "share_sample_2.png")
file1.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
file2.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareManager.shareImages(listOf(file1.absolutePath, file2.absolutePath))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareMultipleImages.png" alt="Example_ShareSampleScreen_ShareMultipleImages" width="400" />
</p>

---

### File Share

The MIME type comes from the file extension (`*/*` for an extension the library does not know).

```kotlin
val file = File(context.cacheDir, "share_sample.txt")
    .apply { writeText("Share sample from native-toolkit") }

shareManager.shareFile(file.absolutePath)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareFile.png" alt="Example_ShareSampleScreen_ShareFile" width="400" />
</p>

---

### Multiple Files

The MIME type is the common type when all files share one, `*/*` otherwise.

```kotlin
val file1 = File(context.cacheDir, "share_sample_1.txt")
    .apply { writeText("Share sample 1 from native-toolkit") }
val file2 = File(context.cacheDir, "share_sample_2.txt")
    .apply { writeText("Share sample 2 from native-toolkit") }

shareManager.shareFiles(listOf(file1.absolutePath, file2.absolutePath))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareMultipleFiles.png" alt="Example_ShareSampleScreen_ShareMultipleFiles" width="400" />
</p>

---

### Direct Share Target

Direct Share targets appear in the Sharesheet as suggested recipients in your app. The library publishes each target as a long-lived dynamic shortcut. For the Sharesheet to show it, the app declares a share target whose category matches the target's `category`, as the sample does. Replace `com.example.app.ShareReceiverActivity` below with your own Activity that is registered in the manifest and receives `ACTION_SEND`:

**AndroidManifest.xml** (inside the `<activity>` that receives shares):

```xml
<meta-data
    android:name="android.app.shortcuts"
    android:resource="@xml/shortcuts" />
```

**res/xml/shortcuts.xml:**

```xml
<?xml version="1.0" encoding="utf-8"?>
<shortcuts xmlns:android="http://schemas.android.com/apk/res/android">
    <share-target android:targetClass="com.example.app.ShareReceiverActivity">
        <data android:mimeType="text/plain" />
        <category android:name="android.shortcut.conversation" />
    </share-target>
</shortcuts>
```

#### Register Direct Share Target

`iconBytes` is an image `BitmapFactory` can decode. Registering an `id` again replaces that target.

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val baos = ByteArrayOutputStream()
bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
val iconBytes = baos.toByteArray()

shareManager.registerDirectShareTarget(
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
shareManager.removeDirectShareTargets(listOf("sample_1"))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_RemoveDirectShareTarget.png" alt="Example_ShareSampleScreen_RemoveDirectShareTarget" width="400" />
</p>

---

### Share with Callback

`shareWithCallback` opens the Sharesheet for text and calls `onResult` with the package of the app the user picked, or `null` when Android did not report it. `onFinished` runs once after any result the Sharesheet reports. On Android 15 (API 35) and later that includes Copy and Edit, which call `onFinished` without `onResult`; on earlier versions only a picked app is reported. Closing the Sharesheet without picking reports nothing, so neither callback runs.

The library waits for one result at a time, shared with [`shareForSelection`](#selection-event). Opening another Sharesheet with either function replaces the wait: the replaced callbacks are never called, and a pick in the older Sharesheet is not delivered to the newer one. Exceptions thrown by `onResult` and `onFinished` are not caught by the library.

#### Basic Callback

```kotlin
shareManager.shareWithCallback(
    ShareContent(text = "Hello with callback from native-toolkit"),
    onResult = { pkg ->
        // Called only when an app was picked; pkg == null when Android did not report its package
        val status = if (pkg != null) "Selected: $pkg" else "Shared (package unavailable)"
    }
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallback.png" alt="Example_ShareSampleScreen_ShareWithCallback" width="400" />
</p>

#### Callback with Rich Preview

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val file = File(context.cacheDir, "callback_preview.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareManager.shareWithCallback(
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
        // Runs once after the result is handled
    }
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallbackRichPreview.png" alt="Example_ShareSampleScreen_ShareWithCallbackRichPreview" width="400" />
</p>

#### Cancel Pending Callback

Stops waiting: neither callback runs afterward. Because the wait is shared, it also stops a wait started by `shareForSelection`. Call it when the screen that asked goes away, so that a late pick does not update a screen that no longer exists; the sample does so in the `onDispose` shown in [Selection Event](#selection-event).

```kotlin
shareManager.cancelPendingCallback()
```

---

### Selection Event

`shareForSelection` opens the Sharesheet for text and returns a token (a `Long` that is not reused within the process). The app the user picks arrives through `selections` as a `ShareSelection` carrying that token and the package name (`null` when Android did not report it). Closing the Sharesheet, and results that are not an app (Copy, Edit), send nothing. Only Sharesheets opened by `shareForSelection` produce `selections` events.

The sample registers the listener while its Share screen is shown:

```kotlin
@Composable
fun ShareSampleScreen(activity: AppCompatActivity) {
    val shareManager = remember(activity) { AndroidShareManager.getInstance(activity) }
    var statusText by remember { mutableStateOf("Result will be displayed here") }
    // The token of the Sharesheet opened by shareForSelection, while its pick is awaited
    var selectionToken by remember { mutableStateOf<Long?>(null) }

    DisposableEffect(shareManager) {
        val registration = shareManager.selections.addListener { selection, _ ->
            if (selection.token == selectionToken) selectionToken = null
            statusText = "Selected (token=${selection.token}): ${selection.packageName ?: "(unknown package)"}"
        }
        onDispose {
            registration.remove()
            shareManager.cancelPendingCallback()
        }
    }

    // The buttons below
}
```

#### Share For Selection

```kotlin
try {
    val token = shareManager.shareForSelection(
        ShareContent(text = "Hello with a selection event from native-toolkit")
    )
    selectionToken = token
} catch (e: ShareDomainError) {
    statusText = e.javaClass.simpleName
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareForSelection.png" alt="Example_ShareSampleScreen_ShareForSelection" width="400" />
</p>

#### Cancel Share Selection

Stops waiting for the pick of `token`. It does nothing when another Sharesheet was opened since.

```kotlin
val token = selectionToken
if (token != null) {
    shareManager.cancelShareSelection(token)
    selectionToken = null
}
```

---

### Receiving Incoming Shares

The sample app also receives content shared from other apps via `ACTION_SEND` and `ACTION_SEND_MULTIPLE`. This is plain Android and does not use the library. Declare intent filters on the receiving `Activity` and read the Intent in `onCreate` and `onNewIntent`:

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTask">
    <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="text/plain" />
    </intent-filter>
    <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="image/*" />
    </intent-filter>
    <intent-filter>
        <action android:name="android.intent.action.SEND_MULTIPLE" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="text/plain" />
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

The operations throw `ShareDomainError` subtypes. They carry no message (`message` is `null`), so tell them apart by type and read their properties.

| Error | Thrown by | Cause |
|---|---|---|
| `EmptyContent` | `shareText`, `shareTextWithActions`, `shareWithCallback`, `shareForSelection` | `text` is blank |
| `InvalidMimeType(mimeType)` | `shareText`, `shareTextWithActions`, `shareImage` | The MIME type is blank |
| `InvalidChooserAction(id)` | `shareTextWithActions` | An action's `id` is empty or repeated, or its icon is not a readable image |
| `FileNotFound(path)` | `shareImage`, `shareImages`, `shareFile`, `shareFiles` | The file does not exist |
| `IllegalFileAccess(path)` | `shareImage`, `shareImages`, `shareFile`, `shareFiles` | The file is outside the [FileProvider](#fileprovider) directories |
| `EmptyFileList` | `shareImages`, `shareFiles` | The list is empty |
| `NoShareTarget` | Every operation that opens the Sharesheet | No activity can handle the share |
| `DirectShareRegistrationFailed(reason)` | `registerDirectShareTarget` | Android did not publish the shortcut |
| `InvalidBase64Icon(id)` | `registerDirectShareTarget` | The icon is not a readable image. The name is kept from 1.x, where the icon was Base64 |
| `EmptyIdList` | `removeDirectShareTargets` | The list is empty |

```kotlin
try {
    shareManager.shareText(ShareContent(text = "Hello"))
} catch (e: ShareDomainError.NoShareTarget) {
    // No app can handle this share
} catch (e: ShareDomainError.EmptyContent) {
    // Text was blank
} catch (e: ShareDomainError) {
    // Other domain error
}
```

---

### C ABI

- The same sharing for C, and for any language that can call a C function in a shared library. Kotlin and Java code calls `AndroidShareManager` instead.
- `android-native-toolkit-capi-2.0.0.aar` carries `libntk.so` for `arm64-v8a` and `x86_64` only, and the headers `NativeToolkitC/*.h` as a Prefab package. An app installed as 32-bit has no `libntk.so`.
- The C ABI calls the Kotlin API through JNI, so both AARs and their dependencies are part of the app's Gradle build. androidx.startup initializes the C ABI when the app starts. An app that disables Startup, or calls from a process other than the default one, calls `ntk_android_init(env, context)` (`<NativeToolkitC/Android.h>`) first; until then the operations return `NTK_SHARE_ERROR_NOT_INITIALIZED`.
- Every function can be called from any thread and never waits for the main thread. Completions, events and accepted `release` calls arrive on the Android main thread. Do not block in them, and do not let an exception leave a callback: the process terminates.
- Opening the Sharesheet is asynchronous and needs the app in the foreground. The return value says whether the request was accepted. The completion (`ntk_share_done_fn`) then runs once, with `NTK_SHARE_ERROR_NONE` when the Sharesheet opened or the reason it did not; called from the background, that is `NTK_SHARE_ERROR_NOT_FOREGROUND`. The completion says nothing about what the user picks: the chosen app arrives later as a selection event carrying the request ID.
- Called from a thread other than the main thread, the completion can arrive before the function returns. Match completions to requests with `user_data`.
- A call rejected on entry (a `NULL` argument, invalid UTF-8, an empty list, an empty text, an empty or repeated chooser action ID) returns the error, never calls the completion, and calls `release` once on the calling thread before returning. An accepted call's `release` runs on the main thread after the completion. `release` may be `NULL`.
- The library copies every input (strings, arrays, icon bytes) before the call returns.
- Handles passed to a callback (`ntk_string*`) belong to the receiver, which frees them with `ntk_string_free`, during the callback or later, on any thread.
- Request IDs are `uint64_t` and never reused within the process.
- The Direct Share functions are synchronous and do not need the foreground.
- `ntk_last_system_code()` and every completion's `system_code` are always 0 on Android.

#### Building

**app/build.gradle.kts:**

```kotlin
android {
    defaultConfig {
        // libntk.so exists for these ABIs only. Restrict CMake too: AGP checks the Prefab
        // package for every ABI CMake builds and fails with CXX1210 when one is missing.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { abiFilters("arm64-v8a", "x86_64") }
        }
    }
    buildFeatures { prefab = true }
}

dependencies {
    implementation("io.github.kimjh4941:android-native-toolkit-capi:2.0.0")
    // Declare the Kotlin API too when your own Kotlin or Java code calls it:
    // the capi POM depends on it for run time only.
    implementation("io.github.kimjh4941:android-native-toolkit:2.0.0")
}
```

**CMakeLists.txt:**

```cmake
find_package(ntk REQUIRED CONFIG)

add_library(myapp SHARED myapp.c)
target_link_libraries(myapp PRIVATE ntk::ntk)
```

See [C ABI](index.md#c-abi) in index.md for the whole setup.

Only when androidx.startup is disabled, or in a process other than the default one:

```c
#include <NativeToolkitC/Android.h>

/* env: the JNIEnv* of the calling thread. context: any Context (jobject); an Activity is also
   taken as the current foreground Activity. */
static void initialize_native_toolkit(void* env, void* context)
{
    /* Never waits; safe to call more than once. */
    ntk_android_error init_error = ntk_android_init(env, context);
    if (init_error == NTK_ANDROID_ERROR_IN_PROGRESS || init_error == NTK_ANDROID_ERROR_JNI_FAILURE) {
        /* Call it again later. NTK_ANDROID_ERROR_CLASS_NOT_FOUND does not recover: the AAR's
           classes are missing (for example removed by R8). */
    }
}
```

#### Opening the Sharesheet

Paths are full paths in the [FileProvider](#fileprovider) directories (files, cache, external files), and the thumbnail follows the same rule. A `NULL` MIME type for `ntk_share_image` means `image/*`.

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Share.h>

static void NTK_CALL on_share_done(void* user_data, ntk_share_error error, uint32_t system_code)
{
    /* Main thread, exactly once for an accepted call. NONE: the Sharesheet opened. */
    (void)user_data; (void)system_code;
    if (error == NTK_SHARE_ERROR_NOT_FOREGROUND) {
        /* The app was in the background; nothing opened. */
    }
}

/* icon_png: PNG, JPEG or WebP bytes. */
static void open_sharesheets(const char* thumbnail_path, const uint8_t* icon_png, size_t icon_png_size,
                             const char* image_path_1, const char* image_path_2,
                             const char* file_path_1, const char* file_path_2)
{
    /* Text. Zeroed fields are the defaults: no title, subject or preview, and "text/plain". */
    ntk_share_text_content content;
    memset(&content, 0, sizeof(content));
    content.struct_size = (uint32_t)sizeof(content);
    content.text = "Hello from native-toolkit";

    ntk_share_error error = ntk_share_text(&content, NULL, 0, &on_share_done, NULL, NULL);

    /* Subject, title and a rich preview. */
    content.title = "Choose an app";
    content.subject = "Sample subject line";
    content.preview_title = "Introducing content previews";
    content.preview_thumbnail_path = thumbnail_path;
    error = ntk_share_text(&content, NULL, 0, &on_share_done, NULL, NULL);

    /* Custom chooser actions (shown on API 34 and later). Every ntk_share_text call, even with
       no actions, makes the actions of earlier Sharesheets stop working. */
    ntk_share_chooser_action actions[1];
    actions[0].id = "custom";
    actions[0].label = "Custom";
    actions[0].icon = icon_png;
    actions[0].icon_size = icon_png_size;
    memset(&content, 0, sizeof(content));
    content.struct_size = (uint32_t)sizeof(content);
    content.text = "Shared with a custom chooser action";
    error = ntk_share_text(&content, actions, 1, &on_share_done, NULL, NULL);

    /* Images and files. */
    error = ntk_share_image(image_path_1, "image/png", &on_share_done, NULL, NULL);

    const char* images[2];
    images[0] = image_path_1;
    images[1] = image_path_2;
    error = ntk_share_images(images, 2, &on_share_done, NULL, NULL);

    error = ntk_share_file(file_path_1, &on_share_done, NULL, NULL);

    const char* files[2];
    files[0] = file_path_1;
    files[1] = file_path_2;
    error = ntk_share_files(files, 2, &on_share_done, NULL, NULL);
}
```

#### Selection and chooser action events

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Share.h>

static void NTK_CALL on_share_done(void* user_data, ntk_share_error error, uint32_t system_code)
{
    /* As in "Opening the Sharesheet": NONE when the Sharesheet opened. */
    (void)user_data; (void)error; (void)system_code;
}

static void NTK_CALL on_selection(void* user_data, uint64_t request_id, ntk_string* package_name)
{
    /* Main thread. package_name is NULL when Android did not report it; the receiver frees it. */
    (void)user_data; (void)request_id;
    if (package_name != NULL) {
        const char* name = ntk_string_data(package_name);   /* valid until ntk_string_free */
        size_t size = ntk_string_size(package_name);
        (void)name; (void)size;
        ntk_string_free(package_name);
    }
}

static void NTK_CALL on_chooser_action(void* user_data, ntk_string* action_id)
{
    /* Main thread. action_id is the id of the tapped ntk_share_chooser_action. */
    const char* id = ntk_string_data(action_id);
    size_t size = ntk_string_size(action_id);
    (void)user_data; (void)id; (void)size;
    ntk_string_free(action_id);
}

/* Register before opening: neither event is kept while no listener is registered. */
ntk_share_listener* selection_listener = NULL;
ntk_share_error error = ntk_share_add_selection_listener(&on_selection, NULL, NULL, &selection_listener);

ntk_share_listener* action_listener = NULL;
error = ntk_share_add_chooser_action_listener(&on_chooser_action, NULL, NULL, &action_listener);

/* Open the Sharesheet; the pick arrives in on_selection with this request ID. */
ntk_share_text_content content;
memset(&content, 0, sizeof(content));
content.struct_size = (uint32_t)sizeof(content);
content.text = "Hello with a selection event from native-toolkit";

uint64_t request_id = 0;
error = ntk_share_text_for_selection(&content, &on_share_done, NULL, NULL, &request_id);

/* Stop waiting for the pick. Never waits, and does nothing unless request_id is the request
   being waited for. It cancels the wait for the pick, not the open (which has no CANCELED). */
error = ntk_share_cancel_selection(request_id);

/* Removing a listener only removes it: the wait for the pick and the current actions stay.
   Removed on the main thread, nothing more is delivered; removed elsewhere, events can arrive
   until its release runs. The handle is invalid afterwards. */
ntk_share_listener_remove(selection_listener);
ntk_share_listener_remove(action_listener);
```

- Only one pick is awaited at a time, as in the Kotlin API: opening another Sharesheet with `ntk_share_text_for_selection` ends the wait for the previous one.
- A request that failed before the Sharesheet was requested (`NTK_SHARE_ERROR_NOT_FOREGROUND`, or `NTK_SHARE_ERROR_EMPTY_CONTENT` for a text of white space) leaves the previous request's wait in place. A request that failed after (`NTK_SHARE_ERROR_NO_SHARE_TARGET`, `NTK_SHARE_ERROR_UNKNOWN`) has ended it.
- `out_request_id` may be `NULL`, but then the selection cannot be matched to the request.
- Selections of Sharesheets that the app's Kotlin code opened with `shareForSelection` are not delivered to C.

#### Direct Share targets

```c
#include <string.h>
#include <NativeToolkitC/Share.h>

/* icon_png: PNG, JPEG or WebP bytes. */
static void update_direct_share_targets(const uint8_t* icon_png, size_t icon_png_size)
{
    ntk_share_direct_target target;
    memset(&target, 0, sizeof(target));
    target.struct_size = (uint32_t)sizeof(target);
    target.id = "sample_1";
    target.label = "Sample User";
    target.category = NULL;              /* "android.shortcut.conversation" */
    target.icon = icon_png;              /* NULL or empty: NTK_SHARE_ERROR_INVALID_ICON */
    target.icon_size = icon_png_size;

    ntk_share_error error = ntk_share_register_direct_target(&target);

    const char* ids[1];
    ids[0] = "sample_1";
    error = ntk_share_remove_direct_targets(ids, 1);
}
```

The app still declares the share target in `shortcuts.xml`, as in [Direct Share Target](#direct-share-target).

#### Error values

`ntk_share_error`. 0 to 5 mean the same in every feature of the C ABI.

| Code | Name | When | Returned by |
|---|---|---|---|
| 0 | `NTK_SHARE_ERROR_NONE` | Success; for an open, the Sharesheet opened | Both |
| 1 | `NTK_SHARE_ERROR_INVALID_PARAMETER` | A `NULL` argument or callback, invalid UTF-8, a `struct_size` that is too small | Return value |
| 2 | `NTK_SHARE_ERROR_NOT_INITIALIZED` | Called before initialization. The argument checks come first, and `ntk_share_cancel_selection` returns `NONE` | Return value |
| 3 | `NTK_SHARE_ERROR_NOT_SUPPORTED` | A nonzero value in the part of a struct this version does not know | Return value |
| 4 | `NTK_SHARE_ERROR_UNKNOWN` | Anything else; logcat (tag `ntk`) has the detail | Both |
| 5 | `NTK_SHARE_ERROR_OUT_OF_MEMORY` | An allocation failed | Both |
| 6 | `NTK_SHARE_ERROR_NOT_FOREGROUND` | The app is not in the foreground; nothing opened | Completion |
| 7 | `NTK_SHARE_ERROR_EMPTY_CONTENT` | The text is empty (return value) or white space only (completion) | Both |
| 8 | `NTK_SHARE_ERROR_NO_SHARE_TARGET` | No activity can handle the share | Completion |
| 9 | `NTK_SHARE_ERROR_FILE_NOT_FOUND` | The file does not exist | Completion |
| 10 | `NTK_SHARE_ERROR_ILLEGAL_FILE_ACCESS` | The file is outside the FileProvider directories | Completion |
| 11 | `NTK_SHARE_ERROR_INVALID_MIME_TYPE` | The MIME type is blank | Completion |
| 12 | `NTK_SHARE_ERROR_DIRECT_SHARE_REGISTRATION_FAILED` | Android did not publish the shortcut | Return value |
| 13 | `NTK_SHARE_ERROR_EMPTY_ID_LIST` | `ntk_share_remove_direct_targets` with no IDs | Return value |
| 14 | `NTK_SHARE_ERROR_EMPTY_FILE_LIST` | `ntk_share_images` or `ntk_share_files` with no paths | Return value |
| 15 | `NTK_SHARE_ERROR_INVALID_ICON` | The Direct Share icon is `NULL`, empty, or not a readable image | Return value |
| 16 | `NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION` | An empty or repeated action ID, or a `NULL` or empty icon (return value); an icon that is not a readable image (completion). The actions of the previous Sharesheet keep working | Both |

There is no `CANCELED`: the open completes as soon as the Sharesheet opens, and cancelling the wait for the pick is separate from it.

| Kotlin API | C ABI |
|---|---|
| `shareText` / `shareTextWithActions` | `ntk_share_text` with `ntk_share_text_content` and `ntk_share_chooser_action` |
| `shareImage` / `shareImages` / `shareFile` / `shareFiles` | `ntk_share_image` / `_images` / `_file` / `_files` |
| `registerDirectShareTarget` / `removeDirectShareTargets` | `ntk_share_register_direct_target` with `ntk_share_direct_target` / `ntk_share_remove_direct_targets` |
| `shareForSelection` / `cancelShareSelection` | `ntk_share_text_for_selection` / `ntk_share_cancel_selection` |
| `selections.addListener` | `ntk_share_add_selection_listener` |
| `chooserActions.addListener` | `ntk_share_add_chooser_action_listener` |
| `EventHub.Registration.remove` | `ntk_share_listener_remove` |
| `shareWithCallback` / `cancelPendingCallback` | None; use `ntk_share_text_for_selection` |
| `ShareDomainError` | `ntk_share_error` 7 to 16, in the same order |

---

## iOS

The system share sheet (`UIActivityViewController`): text, URLs, images and files, alone or mixed in one share, with a subject, a link preview title, and activity types to leave out. iOS library 2.0.0 offers it through two public APIs over one implementation, and the sample app (`IosLibraryExample`) uses the Swift API.

| API | Names | Module / header | Artifact |
|---|---|---|---|
| Swift API | `IosShareManager` | `import IosLibrary` | `ios-native-toolkit-2.0.0.xcframework` |
| C ABI | `ntk_share_*` | `<NativeToolkitC/Share.h>` | `ios-native-toolkit-capi-2.0.0.xcframework` |

- Artifacts: `dist/1.14.0/ios/` holds both xcframeworks and the C headers (`include/NativeToolkitC/*.h`).
- Minimum iOS: 18.0. Swift code that calls the library is built with Xcode 26.3 or later.
- Scope: sending only. Receiving shares (a Share Extension) is not included.
- Coming from 1.x: see [Migrating the iOS library to 2.0.0](index.md#migrating-the-ios-library-to-200). For sharing, the cases of `ShareError` changed (see [Error Handling](#error-handling-1)), the completions are `@MainActor @Sendable`, `share` takes a `presenter` (see [Presenter and Result](#presenter-and-result)), and a share sheet is no longer shown on top of another one (see [Two Shares in One Turn](#two-shares-in-one-turn)). An app that implements `ShareRepository` itself now makes it `Sendable` and implements `present(content:presenter:)` in place of `present(content:)`.

The sections below follow the Share screen of the sample app. [C ABI](#c-abi-1) at the end covers the same operation for C.

---

### IosShareManager

`IosShareManager.shared` is the entry point for sharing. The manager is `Sendable`, so it can be called from any thread.

```swift
import IosLibrary

let shareManager = IosShareManager.shared
```

| Member | Description |
|---|---|
| `share(content:presenter:) async throws -> ShareResult` | Presents the share sheet and returns how it ended. `presenter` defaults to `.firstActiveScene` |
| `share(content:presenter:completion:)` | The same, reporting a `Result<ShareResult, ShareError>` to `completion`. `presenter` has no default |
| `share(content:completion:)` | The 1.x callback form, `(isSuccess, completed, activityType, errorMessage)`. It always uses `.firstActiveScene` |

The model types are in the `IosLibrary` module:

| Type | Contents |
|---|---|
| `ShareContent` | `items` (`[ShareItem]`, not empty), `subject`, `previewTitle`, `excludedActivityTypes` (raw identifiers). Everything but `items` has a default |
| `ShareItem` | `.text(String)`, `.url(String)`, `.imageFile(path:)`, `.file(path:)` |
| `ShareResult` | `completed` (`false` when the user closed the sheet) and `activityType` (the raw identifier of the chosen activity, or `nil`) |
| `ShareError` | See [Error Handling](#error-handling-1) |
| `PresenterSelection` | How the view controller to present from is chosen. See [Presenter and Result](#presenter-and-result) |

<p align="center">
    <img src="images/ios/share/Example_IosShareManager.png" alt="Example_IosShareManager" width="400" />
</p>

---

### Setup

#### Add the library

1. Add `ios-native-toolkit-2.0.0.xcframework` to the Xcode project and set it to "Embed & Sign" in the target's Frameworks, Libraries, and Embedded Content.
2. Import the module where you share:

```swift
import IosLibrary
```

Sharing needs no initialization.

#### Threads and presenting

- `share` can be called from any thread. The completion of each callback form runs on the main thread, exactly once, never inside the call, on every path (validation failures included). The `async` form returns when the sheet ends.
- A share cannot be cancelled. Cancelling the `Task` that awaits it does not end it: the call returns when the sheet ends.
- The user closing the sheet is not an error: the result has `completed == false`.
- The sheet is presented from the view controller that `presenter` chooses (see [Presenter and Result](#presenter-and-result)). On an iPad it is a popover anchored at the center of that view controller's view. There is no parameter for the anchor; to choose where the sheet appears, pass the view controller with `.viewController(_:)`.
- A share sheet is never shown on top of another share sheet. See [Two Shares in One Turn](#two-shares-in-one-turn).
- Do not call `share` while a view controller your app presented itself (for example its own `UIActivityViewController`) is still being presented, before that `present` call's completion has run. UIKit may then decline the library's sheet and keep it, and the share never ends. Wait for your own `present` completion before you share.
- The result is not guaranteed when the app replaces the window, its root view controller or the scene while the sheet is shown, or keeps the presented `UIActivityViewController` alive, nor when the system disconnects the sheet's scene but the sheet is not freed.

The examples below use `share(content:)` (the `async` form with the default presenter), as the sample does. SwiftUI `Button` actions are synchronous, so each call runs in a `Task`.

---

### Text Share

#### Share Text

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.text("Shared from IosLibraryExample")])
        )
        // completed == false: the user closed the sheet
        print(result.completed, result.activityType ?? "nil")
    } catch {
        // See Error Handling
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareText.png" alt="Example_IosShareManager_ShareText" width="400" />
</p>

---

### URL Share

#### Share URL

A URL is passed as a string and checked by the library after white space at both ends is removed: `http` and `https` need a host, and `file` must be a file URL. Any other string, an empty one included, fails with `ShareError.invalidURL`.

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.url("https://www.apple.com")])
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareURL.png" alt="Example_IosShareManager_ShareURL" width="400" />
</p>

#### Share URL with Preview

`previewTitle` gives the share sheet's header a title at once, without waiting for the link to be fetched. It applies to the first item; when that item is a URL, the preview also carries the URL.

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(
                items: [.url("https://www.apple.com")],
                previewTitle: "Apple"
            )
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareURLWithPreview.png" alt="Example_IosShareManager_ShareURLWithPreview" width="400" />
</p>

---

### Image Share

#### Share Image

`.imageFile(path:)` takes the full path of a local image file. The library loads it as a `UIImage` and fails with `ShareError.imageLoadFailed` when it cannot.

```swift
guard let imagePath = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path else {
    return
}

Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.imageFile(path: imagePath)])
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareImage.png" alt="Example_IosShareManager_ShareImage" width="400" />
</p>

#### Share Multiple Images

`items` takes several entries, so several images are shared at once. The sample copies its bundled image to two files in the temporary directory.

```swift
let imagePaths: [String] = /* full paths of local image files */

Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: imagePaths.map { .imageFile(path: $0) })
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultipleImages.png" alt="Example_IosShareManager_ShareMultipleImages" width="400" />
</p>

---

### File Share

#### Share File

`.file(path:)` takes the full path of a local file. The library checks that the file exists (otherwise `ShareError.fileNotFound`) and shares it as a file URL.

```swift
let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("share-sample.txt")

Task {
    do {
        try "Shared from IosLibraryExample.".write(to: fileURL, atomically: true, encoding: .utf8)
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.file(path: fileURL.path)])
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareFile.png" alt="Example_IosShareManager_ShareFile" width="400" />
</p>

#### Share Multiple Files

```swift
let fileURLs: [URL] = /* local file URLs */

Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: fileURLs.map { .file(path: $0.path) })
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultipleFiles.png" alt="Example_IosShareManager_ShareMultipleFiles" width="400" />
</p>

---

### Combined Content

#### Share Multiple Items

Items of different kinds (text, URL, image, file) can be mixed in one share.

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [
                .text("Check this out"),
                .url("https://www.apple.com")
            ])
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultiple.png" alt="Example_IosShareManager_ShareMultiple" width="400" />
</p>

#### Share with Subject

`subject` is used by the activities that support one, such as the subject line in Mail. Like `previewTitle`, it is attached to the first item.

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(
                items: [.text("Body text")],
                subject: "Sample Subject"
            )
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareWithSubject.png" alt="Example_IosShareManager_ShareWithSubject" width="400" />
</p>

#### Exclude Activity Types

`excludedActivityTypes` takes raw activity type identifiers and hides those activities from the sheet.

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(
                items: [.url("https://www.apple.com")],
                excludedActivityTypes: [
                    "com.apple.UIKit.activity.CopyToPasteboard",
                    "com.apple.UIKit.activity.PostToFacebook"
                ]
            )
        )
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareExcludingActivities.png" alt="Example_IosShareManager_ShareExcludingActivities" width="400" />
</p>

---

### Error Handling

The `async` form throws `ShareError`, and `share(content:presenter:completion:)` reports it as `.failure`. The user closing the sheet is not an error (`completed == false`). Every case is stable: none carries an arbitrary system `Error`.

| Error | When | Description (`localizedDescription`) |
|---|---|---|
| `noValidItems` | `items` is empty | `No shareable items were provided.` |
| `invalidURL(String)` | A `.url` item is not a valid `http`, `https` or `file` URL | `Invalid URL: <value>.` |
| `imageLoadFailed(path:)` | The image of an `.imageFile` item cannot be loaded | `Failed to load image at path: <path>.` |
| `fileNotFound(path:)` | The file of a `.file` item does not exist | `File not found at path: <path>.` |
| `noRootViewController` | `.firstActiveScene` found no view controller to present from | `No root view controller available to present the share sheet.` |
| `notForeground` | `.foreground` or `.viewController(_:)` found no view controller in the foreground | `The app has no view controller in the foreground to present the share sheet.` |
| `presentationFailed` | The sheet was not shown: the view controller to present from was not settled, UIKit declined the presentation, the sheet was freed before it finished appearing, or the foreground is a share sheet (see [Two Shares in One Turn](#two-shares-in-one-turn)) | `Failed to present the share sheet.` |
| `dismissedBySystem` | The sheet went away without reporting a result: dismissed from outside the library, or its scene was disconnected and the sheet freed | `The share sheet was dismissed without a result.` |
| `activityFailed(FailureDetail)` | The chosen activity reported an error. `FailureDetail` holds its `NSError` `domain` and `code` | `The share activity failed.` |

No sheet is shown for the first four. The descriptions are fixed English sentences; those of `invalidURL`, `imageLoadFailed` and `fileNotFound` contain the URL or path that was passed in.

Changes from 1.x: `presentationFailed` no longer carries an `Error`, `unknown(Error)` is gone, and `notForeground`, `dismissedBySystem` and `activityFailed` are new. A `switch` written for the 1.x cases no longer compiles. Write an `@unknown default` branch, since cases can be added.

The Error section of the sample shares an empty list, an invalid URL, a missing file and a missing image:

```swift
Task {
    do {
        _ = try await IosShareManager.shared.share(
            content: ShareContent(items: [.url("not a valid url")])
        )
    } catch let error as ShareError {
        switch error {
        case .noValidItems, .invalidURL, .imageLoadFailed, .fileNotFound:
            // The content cannot be shared; no sheet was shown
            break
        case .noRootViewController, .notForeground:
            // No view controller to present from
            break
        case .presentationFailed:
            // The sheet was not shown
            break
        case .dismissedBySystem:
            // The sheet went away without a result
            break
        case .activityFailed(let detail):
            print(detail.domain, detail.code)
        @unknown default:
            break
        }
    } catch {
        // share(content:presenter:) throws only ShareError
    }
}
```

`share(content:completion:)` reports a failure as `isSuccess == false`, `completed == false`, `activityType == nil`, and the description above as `errorMessage`. Unlike 1.x, its completion also comes once when the sheet is dismissed from outside the library (`"The share sheet was dismissed without a result."`).

```swift
IosShareManager.shared.share(
    content: ShareContent(items: [])
) { isSuccess, completed, activityType, errorMessage in
    // isSuccess == false, errorMessage == "No shareable items were provided."
}
```

---

### Presenter and Result

`PresenterSelection` decides which view controller the sheet is presented from:

| Value | View controller | Before presenting |
|---|---|---|
| `.firstActiveScene` (default of the `async` form; always used by `share(content:completion:)`) | The topmost presented view controller of the key window of the first `foregroundActive` window scene | Searched once, with no waiting. Fails with `noRootViewController` when none is found, and with `presentationFailed` when that view controller is being presented or dismissed or is presenting something |
| `.foreground` | The topmost view controller that is not being dismissed, of the key window of a `foregroundActive` or `foregroundInactive` window scene | Fails with `notForeground` when none is found. When that view controller is in a transition, waits once for the transition to end, checks again, and fails with `presentationFailed` when it is still not settled |
| `.viewController(_:)` | The one the closure returns. The closure is called once, on the main thread, when the sheet is about to be presented | Fails with `notForeground` when the closure returns `nil`; otherwise the same single wait as `.foreground` |

`foregroundInactive` covers the moments when the app is visible but not active: right after launch, and while Control Center or Notification Center is pulled over the app. On an iPad with two of the app's windows side by side, both can be active, so `.firstActiveScene` and `.foreground` may choose the window the user is not looking at; pass the view controller with `.viewController(_:)` there:

```swift
// In a view controller: present from this view controller while it is alive.
let presenter: PresenterSelection = .viewController { [weak self] in self }
```

The closure is kept until the sheet has been presented, so capture the view controller weakly.

#### Share from the Foreground

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.text("Shared through the Swift API")]),
            presenter: .foreground
        )
        print(result.completed, result.activityType ?? "nil")
    } catch let error as ShareError {
        // notForeground when the app is in the background
        print(error)
    } catch {
        // share(content:presenter:) throws only ShareError
    }
}
```

#### Result Callback

`share(content:presenter:completion:)` reports the same result to a completion on the main thread. The sample dismisses the sheet from outside the library 3 seconds after the tap; the completion then comes once with `.dismissedBySystem`.

```swift
IosShareManager.shared.share(
    content: ShareContent(items: [.text("Dismissed from outside after 3 seconds")]),
    presenter: .foreground
) { result in
    switch result {
    case .success(let share):
        print(share.completed, share.activityType ?? "nil")
    case .failure(.dismissedBySystem):
        // The sheet went away without reporting a result
        break
    case .failure(let error):
        print(error)
    }
}

DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
    let top = IosDialogManager.shared.foregroundViewController()
    top?.presentingViewController?.dismiss(animated: true)
}
```

#### Two Shares in One Turn

A share sheet is never shown on top of another share sheet. This is what happens when shares overlap:

- Two shares requested in the same turn of the main queue: one sheet is shown, and the other share waits until that sheet has finished appearing (at most 10 seconds) and then ends with `presentationFailed`. Which of the two is shown is not decided; it is not always the first call. Each completion comes exactly once. (In 1.x, one of the two completions never came.)
- A share requested while the foreground is a share sheet, the library's or the app's own, ends with `presentationFailed`.
- `.firstActiveScene` does not wait: a share requested while a share sheet of the library is still appearing in the same window ends at once with `presentationFailed`.
- When a share sheet of the library takes more than 10 seconds to finish appearing (for example because the app went to the background meanwhile), the shares waiting for it end with `presentationFailed`, and the library's later presentations in that window (shares, and dialogs shown through the `presenter` API) end with `presentationFailed` at once until that sheet has finished appearing or has been freed. The same applies after the case to avoid in [Threads and presenting](#threads-and-presenting), where UIKit keeps a declined sheet.

```swift
for number in 1...2 {
    IosShareManager.shared.share(
        content: ShareContent(items: [.text("Share \(number) of two in one turn")]),
        presenter: .foreground
    ) { result in
        // One of the two ends with .failure(.presentationFailed)
        print(number, result)
    }
}
```

---

### C ABI

- The same sharing for C, and for any language that can call a C function in a framework. Swift code calls `IosShareManager` instead.
- `ios-native-toolkit-capi-2.0.0.xcframework` (framework `IosLibraryCApi`) carries the C ABI and its headers `NativeToolkitC/*.h`. It calls the Swift API, so the app embeds both xcframeworks of the same release. The requirements and the steps to add them are in [Supported platform: iOS](index.md#supported-platform-ios-device-arm64--simulator-arm64-x86_64), and the rules common to every feature in [C ABI](index.md#c-abi-1), on the manual top.
- Android's `Share.h` has a function per kind of content. iOS has one function, `ntk_share_content_async`, that takes an array of mixed items, as the Swift API does, and returns the result as a handle.
- Every function can be called from any thread and never waits for the main thread. The callback and an accepted call's `release` run on the main queue, never inside the function when it is called on the main thread; called from another thread, the callback can arrive before the function returns. Match callbacks to requests with `user_data`. Do not block in callbacks, and do not let an exception leave one.
- `NTK_SHARE_ERROR_NONE` from `ntk_share_content_async` means the request was accepted; the callback then comes once, followed by `release`. Any other value means it was rejected: no callback, and `release` has already run on the calling thread, so do not free `user_data` yourself. A `NULL` callback is rejected; `release` may be `NULL`.
- The library copies the request (the strings, the items and the excluded types) before the call returns. Strings are NUL-terminated UTF-8, and invalid UTF-8 is rejected with `NTK_SHARE_ERROR_INVALID_PARAMETER`.
- A zero-filled struct with `struct_size` set is the default of every field. In `ntk_share_request` that is no subject, no preview title and nothing excluded (`excluded_activity_types` may then be `NULL`), and also no items, which the call rejects with `NTK_SHARE_ERROR_EMPTY_CONTENT`: set `items` and `item_count`. In `ntk_share_item` it is `NTK_SHARE_ITEM_TEXT` with a `NULL` `value`, which is rejected with `NTK_SHARE_ERROR_INVALID_PARAMETER`: every item needs its `value`. The reserved fields must be 0. Every element of the item array has the same `struct_size`.
- Sharing needs the foreground. The C ABI presents from the foreground view controller, as `.foreground` does in Swift; from the background, the callback gets `NTK_SHARE_ERROR_NOT_FOREGROUND`. The C ABI cannot choose the view controller: on an iPad that shows several of the app's windows side by side, which window shows the sheet is not decided. On an iPad the sheet is a popover anchored at the center of the presenting view.
- A share cannot be cancelled; there is no cancel function and no `CANCELED` value. The callback and `release` (and with them `user_data`) are held until the sheet ends. If the host replaces its window or root view controller while the sheet is shown, or the system disconnects the scene and the sheet is kept, they may never come, and `user_data` leaks.
- The result handle (`ntk_share_result*`) belongs to the receiver, who frees it with `ntk_share_result_free`, during the callback or later, on any thread. The string from `ntk_share_result_activity_type` is valid until the handle is freed. `ntk_share_result_free(NULL)` does nothing.
- `ntk_last_system_code()` and the callback's `system_code` are always 0 on iOS.

#### Building

1. Add `ios-native-toolkit-2.0.0.xcframework` and `ios-native-toolkit-capi-2.0.0.xcframework` to the app target and set both to "Embed & Sign".
2. Include the header from the framework, `#include <IosLibraryCApi/NativeToolkitC/Share.h>`, or add `dist/1.14.0/ios/include` to Header Search Paths and write `#include <NativeToolkitC/Share.h>`. `Share.h` includes `Common.h` itself.

#### Sharing content

```c
static void NTK_CALL on_share_result(void* user_data, ntk_share_error error, uint32_t system_code,
                                     ntk_share_result* result)
{
    /* Main thread, exactly once for an accepted call. result is NULL unless error is NONE. */
    (void)user_data; (void)system_code;   /* system_code is always 0 on iOS */
    if (error == NTK_SHARE_ERROR_NONE) {
        if (ntk_share_result_completed(result)) {
            size_t size = 0;
            const char* activity = ntk_share_result_activity_type(result, &size);   /* NULL when unknown */
            (void)activity;
        } else {
            /* The user closed the sheet. Not an error. */
        }
        ntk_share_result_free(result);   /* here or later, on any thread */
        return;
    }
    switch (error) {
    case NTK_SHARE_ERROR_NOT_FOREGROUND:    /* the app was in the background; nothing was shown */
    case NTK_SHARE_ERROR_SHOW_FAILED:       /* the sheet was not shown */
        break;
    case NTK_SHARE_ERROR_INVALID_URI:
    case NTK_SHARE_ERROR_FILE_NOT_FOUND:
    case NTK_SHARE_ERROR_IMAGE_LOAD_FAILED: /* an item cannot be shared; nothing was shown */
        break;
    case NTK_SHARE_ERROR_CANCELED_BY_SYSTEM: /* the sheet went away without a result */
    case NTK_SHARE_ERROR_ACTIVITY_FAILED:    /* the chosen activity reported an error */
        break;
    default:
        break;
    }
}

static void NTK_CALL on_share_release(void* user_data)
{
    /* Once: after the callback on the main thread, or on the calling thread when the call
       is rejected. Free user_data here. */
    (void)user_data;
}

/* Text and a URL in one share, with a subject, a preview title and an excluded activity. */
static ntk_share_error share_text_and_url(void* user_data)
{
    ntk_share_item items[2];
    memset(items, 0, sizeof(items));
    items[0].struct_size = (uint32_t)sizeof(items[0]);
    items[0].kind = NTK_SHARE_ITEM_TEXT;
    items[0].value = "Check this out";
    items[1].struct_size = (uint32_t)sizeof(items[1]);
    items[1].kind = NTK_SHARE_ITEM_URL;
    items[1].value = "https://www.apple.com";

    const char* excluded[1];
    excluded[0] = "com.apple.UIKit.activity.PostToFacebook";

    /* Zeroed fields are the defaults: no subject, no preview title, nothing excluded. */
    ntk_share_request request;
    memset(&request, 0, sizeof(request));
    request.struct_size = (uint32_t)sizeof(request);
    request.items = items;
    request.item_count = 2;
    request.subject = "Sample Subject";      /* attached to the first item, as in Swift */
    request.preview_title = "Apple";
    request.excluded_activity_types = excluded;
    request.excluded_activity_type_count = 1;

    /* The library copies the request before returning: items may go out of scope. */
    return ntk_share_content_async(&request, &on_share_result, user_data, &on_share_release);
}

/* An image and a file, by full path. */
static ntk_share_error share_image_and_file(const char* image_path, const char* file_path, void* user_data)
{
    ntk_share_item items[2];
    memset(items, 0, sizeof(items));
    items[0].struct_size = (uint32_t)sizeof(items[0]);
    items[0].kind = NTK_SHARE_ITEM_IMAGE_FILE;
    items[0].value = image_path;
    items[1].struct_size = (uint32_t)sizeof(items[1]);
    items[1].kind = NTK_SHARE_ITEM_FILE;
    items[1].value = file_path;

    ntk_share_request request;
    memset(&request, 0, sizeof(request));
    request.struct_size = (uint32_t)sizeof(request);
    request.items = items;
    request.item_count = 2;

    ntk_share_error error = ntk_share_content_async(&request, &on_share_result, user_data, &on_share_release);
    if (error != NTK_SHARE_ERROR_NONE) {
        /* Rejected: no callback, and on_share_release has already run. */
    }
    return error;
}
```

- An item's `value` is the text, the URL, or the full path. Empty strings are not rejected at the call. An empty or blank text is shared as it is, as the Swift API does (unlike Android, where an empty text is `NTK_SHARE_ERROR_EMPTY_CONTENT`). A URL or a path is checked by the library, which reports `NTK_SHARE_ERROR_INVALID_URI`, `NTK_SHARE_ERROR_FILE_NOT_FOUND` or `NTK_SHARE_ERROR_IMAGE_LOAD_FAILED` in the callback, an empty one included, as the Swift API does.
- `item_count` 0 returns `NTK_SHARE_ERROR_EMPTY_CONTENT`. An item `kind` out of range, a `NULL` `value`, a `NULL` array with a nonzero count, and a `NULL` excluded type return `NTK_SHARE_ERROR_INVALID_PARAMETER`.

#### One share sheet at a time

The rules of [Two Shares in One Turn](#two-shares-in-one-turn) apply to C:

- Of two `ntk_share_content_async` calls in the same turn of the main queue, one shows its sheet; the other waits until that sheet has finished appearing (at most 10 seconds), and its callback gets `NTK_SHARE_ERROR_SHOW_FAILED`. Which one is shown is not decided, and the order of the callbacks of several shares is not promised. Each accepted call gets its callback and `release` once.
- A call made while the foreground is a share sheet gets `NTK_SHARE_ERROR_SHOW_FAILED`.
- Do not call `ntk_share_content_async` while a view controller the host presented itself (for example its own `UIActivityViewController`) is still being presented, before that `present` call's completion has run. UIKit may then decline the library's sheet and keep it, and the callback and `release` may never come. Call it after the host's `present` completion.
- When a share sheet takes more than 10 seconds to finish appearing, the waiting call gets `NTK_SHARE_ERROR_SHOW_FAILED`, and later shares in that window get `NTK_SHARE_ERROR_SHOW_FAILED` until that sheet has finished appearing or has been freed.

#### Error values

`ntk_share_error`. 0 to 5 mean the same in every feature of the C ABI. The numbers that are missing (8, 10 to 16) are values of Android's `Share.h` that iOS does not use.

| Code | Name | When | Returned by |
|---|---|---|---|
| 0 | `NTK_SHARE_ERROR_NONE` | Accepted (return value); the sheet ended with a result (callback) | Both |
| 1 | `NTK_SHARE_ERROR_INVALID_PARAMETER` | A `NULL` request or callback, invalid UTF-8, a `struct_size` that is too small or above 4096, a nonzero reserved field, items of different sizes, an item `kind` out of range, a `NULL` value | Return value |
| 2 | `NTK_SHARE_ERROR_NOT_INITIALIZED` | Not returned on iOS | - |
| 3 | `NTK_SHARE_ERROR_NOT_SUPPORTED` | A nonzero value in the part of a struct this version does not know | Return value |
| 4 | `NTK_SHARE_ERROR_UNKNOWN` | A `ShareError` case the C ABI does not know. Not returned while both xcframeworks are of the same release | Callback |
| 5 | `NTK_SHARE_ERROR_OUT_OF_MEMORY` | Not returned on iOS | - |
| 6 | `NTK_SHARE_ERROR_NOT_FOREGROUND` | The app has no view controller in the foreground; nothing was shown | Callback |
| 7 | `NTK_SHARE_ERROR_EMPTY_CONTENT` | `item_count` is 0 | Return value |
| 9 | `NTK_SHARE_ERROR_FILE_NOT_FOUND` | The file of an `NTK_SHARE_ITEM_FILE` item does not exist | Callback |
| 17 | `NTK_SHARE_ERROR_INVALID_URI` | An `NTK_SHARE_ITEM_URL` item is not a valid `http`, `https` or `file` URL | Callback |
| 18 | `NTK_SHARE_ERROR_IMAGE_LOAD_FAILED` | The image of an `NTK_SHARE_ITEM_IMAGE_FILE` item cannot be loaded | Callback |
| 19 | `NTK_SHARE_ERROR_SHOW_FAILED` | The sheet was not shown: the foreground view controller was not settled, UIKit declined, or the foreground is a share sheet | Callback |
| 20 | `NTK_SHARE_ERROR_CANCELED_BY_SYSTEM` | The sheet went away without a result: dismissed from outside the library, or its scene was disconnected and the sheet freed | Callback |
| 21 | `NTK_SHARE_ERROR_ACTIVITY_FAILED` | The chosen activity reported an error. Its domain and code are not passed to C | Callback |

There is no `CANCELED`: a share cannot be cancelled, and the user closing the sheet is `NTK_SHARE_ERROR_NONE` with `ntk_share_result_completed` returning 0.

| Swift API | C ABI |
|---|---|
| `share(content:presenter:completion:)` (`.foreground`) | `ntk_share_content_async` with `ntk_share_request` |
| `ShareItem` `.text` / `.url` / `.imageFile(path:)` / `.file(path:)` | `ntk_share_item` with `NTK_SHARE_ITEM_TEXT` / `_URL` / `_IMAGE_FILE` / `_FILE` |
| `ShareContent.subject` / `previewTitle` / `excludedActivityTypes` | `subject` / `preview_title` / `excluded_activity_types` and `excluded_activity_type_count` |
| `ShareResult.completed` / `activityType` | `ntk_share_result_completed` / `ntk_share_result_activity_type`, then `ntk_share_result_free` |
| `ShareError` | `ntk_share_error`: `noRootViewController` and `notForeground` are 6, `noValidItems` is 7, `fileNotFound` 9, `invalidURL` 17, `imageLoadFailed` 18, `presentationFailed` 19, `dismissedBySystem` 20, `activityFailed` 21 |
| `PresenterSelection` | None; the C ABI always presents from the foreground |

---

## macOS

- Library: `mac-native-toolkit-1.3.0.xcframework`
- Minimum Deployment Target: macOS 15
- Scope: sending only, via `NSSharingServicePicker` (picker) and `NSSharingService` (direct service execution). Receiving incoming shares is not included.
- macOS offers two ways to share: a **picker** that lets the user choose a service (`NSSharingServicePicker`), and **direct service execution** that runs a single named service without showing the picker (`NSSharingService`, for example launching Mail with prefilled `recipients`/`subject`).

### MacShareManager

`MacShareManager` is a singleton class that presents the system sharing service picker and performs individual sharing services on macOS.

**Important:** Present the picker only in response to a user-initiated action (for example, a button click). `NSSharingServicePicker.show(...)` requires a `mouseDown` event context, and the picker call path hops through `Task { @MainActor in ... }` internally, which does not formally guarantee that context is preserved. In the sample app included with this toolkit, the picker was confirmed to appear correctly and resolve (appear / cancel / complete) when triggered by a real click. Direct service execution (`shareViaService`, `share(content:serviceName:completion:)`) does not depend on `mouseDown` context and is the more robust path when reliability matters.

<p align="center">
    <img src="images/mac/share/Example_MacShareManager.png" alt="Example_MacShareManager" width="800" />
</p>

### Setup

1. Add `mac-native-toolkit-1.3.0.xcframework` to your Xcode project (drag it into the project and set "Embed & Sign" in the target's Frameworks, Libraries, and Embedded Content).
2. Import the library where you present the share picker or run a service:

```swift
import MacLibrary
```

No additional initialization is required.

`MacShareManager` offers two calling styles for each operation:

- `async throws` (preferred for native Swift callers): returns a typed `ShareResult` and throws `ShareError` on failure.
- Callback (used by the Unity Bridge, also available in Swift): `(isSuccess, completed, serviceName, errorMessage)`.

```swift
// async throws (recommended for Swift callers)
Task {
    do {
        let result = try await MacShareManager.shared.share(
            content: ShareContent(items: [.text("Hello")])
        )
        // result.completed == false means the user cancelled (not an error)
        print(result.completed, result.serviceName ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}

// callback (equivalent)
MacShareManager.shared.share(
    content: ShareContent(items: [.text("Hello")])
) { isSuccess, completed, serviceName, errorMessage in
    print(isSuccess, completed, serviceName ?? "nil", errorMessage ?? "nil")
}
```

The examples below use the `async throws` style. Because SwiftUI `Button` actions are synchronous, each call is wrapped in `Task { ... }`.

### Picker - Basic

#### Share Text

```swift
Task {
    let result = try await MacShareManager.shared.share(
        content: ShareContent(items: [.text("Shared from MacLibraryExample")])
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareText.png" alt="Example_MacShareManager_ShareText" width="800" />
</p>

#### Share URL

A URL is passed as a raw string. It is validated in the library: only `http`, `https`, and `file` schemes with a valid host are accepted (otherwise `ShareError.invalidURL` is thrown).

```swift
Task {
    let result = try await MacShareManager.shared.share(
        content: ShareContent(items: [.url("https://www.apple.com")])
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareURL.png" alt="Example_MacShareManager_ShareURL" width="800" />
</p>

#### Share Image

Pass the local file path of an image with `.imageFile(path:)`. The library loads it as an `NSImage` (throws `ShareError.imageLoadFailed` if it cannot be read).

```swift
guard let image = NSImage(named: "test-image") else { return }
guard let tiffData = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiffData),
      let pngData = bitmap.representation(using: .png, properties: [:])
else { return }

let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("share-sample-image.png")
try pngData.write(to: imageURL)

Task {
    let result = try await MacShareManager.shared.share(
        content: ShareContent(items: [.imageFile(path: imageURL.path)])
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareImage.png" alt="Example_MacShareManager_ShareImage" width="800" />
</p>

#### Share File

Pass the local file path with `.file(path:)`. The library checks that the file exists (throws `ShareError.fileNotFound` otherwise).

```swift
let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("share-sample.txt")
try "Shared from MacLibraryExample.".write(to: fileURL, atomically: true, encoding: .utf8)

Task {
    let result = try await MacShareManager.shared.share(
        content: ShareContent(items: [.file(path: fileURL.path)])
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareFile.png" alt="Example_MacShareManager_ShareFile" width="800" />
</p>

### Picker - Multiple

#### Share Multiple Images

`ShareContent.items` accepts multiple entries, so several images can be shared at once (there is only one bundled sample image, so it is copied to distinct temporary files).

```swift
let imagePaths: [String] = /* local image file paths */

Task {
    let result = try await MacShareManager.shared.share(
        content: ShareContent(items: imagePaths.map { .imageFile(path: $0) })
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareMultipleImages.png" alt="Example_MacShareManager_ShareMultipleImages" width="800" />
</p>

#### Share Multiple Files

```swift
let fileURLs: [URL] = /* local file URLs */

Task {
    let result = try await MacShareManager.shared.share(
        content: ShareContent(items: fileURLs.map { .file(path: $0.path) })
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareMultipleFiles.png" alt="Example_MacShareManager_ShareMultipleFiles" width="800" />
</p>

#### Share Text and URL

Mix different item types (text, URL, image, file) in a single share.

```swift
Task {
    let result = try await MacShareManager.shared.share(
        content: ShareContent(items: [
            .text("Check this out"),
            .url("https://www.apple.com")
        ])
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareTextAndURL.png" alt="Example_MacShareManager_ShareTextAndURL" width="800" />
</p>

### Picker - Filter

#### Share Excluding Services

Pass service display titles in `excludedServiceTitles` to hide them from the picker. This is **best-effort**: `NSSharingService` does not expose a stable raw identifier to the caller, so the match is against the service's display `title`, which can be localized and may not match in every environment. Where reliable control is required, use direct service execution (`shareViaService`) instead.

```swift
Task {
    let result = try await MacShareManager.shared.share(
        content: ShareContent(
            items: [.url("https://www.apple.com")],
            excludedServiceTitles: ["Add to Reading List"]
        )
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareExcludingServices.png" alt="Example_MacShareManager_ShareExcludingServices" width="800" />
</p>

### Direct Service

#### Share via Mail

Run a single named service directly, bypassing the picker. `serviceName` is a raw `NSSharingService.Name` value (for example `"com.apple.share.Mail.compose"`). `recipients` and `subject` are applied to the service before it runs; they have no effect in picker mode.

```swift
Task {
    let result = try await MacShareManager.shared.shareViaService(
        content: ShareContent(
            items: [.text("Body text")],
            recipients: ["test@example.com"],
            subject: "Sample Subject"
        ),
        serviceName: "com.apple.share.Mail.compose"
    )
    print(result.completed, result.serviceName ?? "nil")
}
```

<p align="center">
    <img src="images/mac/share/Example_MacShareManager_ShareViaMail.png" alt="Example_MacShareManager_ShareViaMail" width="800" />
</p>

#### Check if a Service Can Perform

Query whether a named service can share the given content, for example to enable/disable a button before the user taps it.

```swift
Task {
    let canPerform = try await MacShareManager.shared.canPerform(
        content: ShareContent(items: [.text("Body text")]),
        serviceName: "com.apple.share.Mail.compose"
    )
    print(canPerform)
}
```

### Error Handling

The `async throws` API throws `ShareError` on failure. User cancellation is not an error: it is reported as `ShareResult.completed == false`.

| Error | Cause | Error message |
|---|---|---|
| `noValidItems` | `items` is empty | `"No shareable items were provided."` |
| `invalidURL(String)` | URL string is not a valid `http`/`https`/`file` URL | `"Invalid URL: <value>."` |
| `imageLoadFailed(path:)` | Image at the path could not be loaded | `"Failed to load image at path: <path>."` |
| `fileNotFound(path:)` | File at the path does not exist | `"File not found at path: <path>."` |
| `noAnchorView` | No key window was available to anchor the picker | `"No key window available to anchor the sharing picker."` |
| `serviceUnavailable(name:)` | The named service is unknown or cannot share the content | `"Sharing service unavailable: <name>."` |
| `alreadyInProgress` | Another share operation is already in progress | `"A share operation is already in progress."` |
| `presentationFailed(Error)` | Presentation failed or the system reported an error | `"Failed to share: <detail>."` |
| `unknown(Error)` | An unexpected error occurred | `"An unknown share error occurred: <detail>."` |

```swift
Task {
    do {
        let result = try await MacShareManager.shared.share(
            content: ShareContent(items: [.text("Hello")])
        )
        if result.completed {
            // Shared successfully via result.serviceName
        } else {
            // User cancelled
        }
    } catch let error as ShareError {
        // Typed error with errorCode / errorMessage (e.g. .noValidItems, .invalidURL, .fileNotFound)
        print(error.errorCode, error.errorMessage)
    } catch {
        // Other error
    }
}
```

When using the callback API, failures are delivered as `isSuccess == false` with a non-nil `errorMessage`:

```swift
MacShareManager.shared.share(
    content: ShareContent(items: [])
) { isSuccess, completed, serviceName, errorMessage in
    // isSuccess == false, errorMessage == "No shareable items were provided."
}
```
