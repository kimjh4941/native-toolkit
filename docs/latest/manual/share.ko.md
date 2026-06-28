# Share 기능

Language:

- 日本語: [share.ja.md](share.ja.md)
- English: [share.md](share.md)
- 한국어（이 페이지）

← [매뉴얼 홈으로 돌아가기](index.ko.md)

---

## 목차

- [Android](#android)
  - [설정](#설정)
  - [텍스트 공유](#텍스트-공유)
    - [텍스트 공유](#텍스트-공유-1)
    - [URL 공유](#url-공유)
    - [리치 프리뷰 포함 텍스트 공유](#리치-프리뷰-포함-텍스트-공유)
    - [커스텀 Chooser Action 포함 텍스트 공유](#커스텀-chooser-action-포함-텍스트-공유)
    - [Chooser Action 콜백](#chooser-action-콜백)
    - [제목 및 서브젝트 포함 공유](#제목-및-서브젝트-포함-공유)
  - [이미지 공유](#이미지-공유)
  - [여러 이미지 공유](#여러-이미지-공유)
  - [파일 공유](#파일-공유)
  - [여러 파일 공유](#여러-파일-공유)
  - [Direct Share Target](#direct-share-target)
    - [Direct Share Target 등록](#direct-share-target-등록)
    - [Direct Share Target 삭제](#direct-share-target-삭제)
  - [콜백 포함 공유](#콜백-포함-공유)
    - [기본 콜백](#기본-콜백)
    - [리치 프리뷰 포함 콜백](#리치-프리뷰-포함-콜백)
    - [대기 중인 콜백 취소](#대기-중인-콜백-취소)
  - [수신 공유 콘텐츠 처리](#수신-공유-콘텐츠-처리)
  - [에러 처리](#에러-처리)

---

## Android

- 라이브러리: `android-native-toolkit-1.2.0.aar`
- 최소 SDK: Android 12 (API 31)
- 커스텀 Chooser Action: Android 14 (API 34) 이상

### 설정

#### Android 네이티브 (AAR)

1. `android-native-toolkit-1.2.0.aar`를 `app/libs`에 배치한다.
2. `app/build.gradle.kts`에 의존성을 추가한다:

```kotlin
dependencies {
    implementation(files("libs/android-native-toolkit-1.2.0.aar"))
}
```

3. 파일·이미지 공유를 위해 `AndroidManifest.xml`에 `FileProvider`를 선언한다:

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

4. `res/xml/file_paths.xml`을 생성한다:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="share_cache" path="." />
    <external-cache-path name="share_external_cache" path="." />
    <files-path name="share_files" path="." />
</paths>
```

---

### 텍스트 공유

#### 텍스트 공유

```kotlin
val shareUseCases = ShareUseCases(activity)

try {
    shareUseCases.shareText(
        ShareContent(text = "Hello from native-toolkit"),
        chooserActionsJson = "[]"
    )
} catch (e: ShareDomainError) {
    // 에러 처리
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareText.png" alt="Example_ShareSampleScreen_ShareText" width="400" />
</p>

#### URL 공유

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

#### 리치 프리뷰 포함 텍스트 공유

리치 프리뷰는 Android 31 이상과 유효한 썸네일 파일 경로가 필요합니다.

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

#### 커스텀 Chooser Action 포함 텍스트 공유

커스텀 Chooser Action은 Android 14 (API 34) 이상에서만 동작합니다. 이전 기기에서는 `chooserActionsJson` 파라미터가 무시됩니다.

- `intentAction`은 **고유하고 비어있지 않아야** 하며, `android.intent.action.SEND`는 사용할 수 없습니다.
- 권장 namespace: `${applicationId}.share.action.<name>`

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

커스텀 Action이 탭되었을 때 콜백을 받으려면 [Chooser Action 콜백](#chooser-action-콜백)을 참고하세요.

#### Chooser Action 콜백

`AndroidManifest.xml`에 `BroadcastReceiver`를 선언합니다. `<action>`의 `android:name`은 `chooserActionsJson`에 전달한 `intentAction`과 일치해야 합니다.

```xml
<receiver
    android:name=".ShareChooserActionReceiver"
    android:exported="false">
    <intent-filter>
        <action android:name="com.example.myapp.share.action.CUSTOM" />
    </intent-filter>
</receiver>
```

리시버를 구현합니다:

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

#### 제목 및 서브젝트 포함 공유

`subject`는 이메일 제목줄을 설정합니다. `title`은 Sharesheet 제목을 설정합니다.

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

### 이미지 공유

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

### 여러 이미지 공유

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

### 파일 공유

```kotlin
val file = File(context.cacheDir, "share_sample.txt")
    .apply { writeText("Share sample from native-toolkit") }

shareUseCases.shareFile(file.absolutePath)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareFile.png" alt="Example_ShareSampleScreen_ShareFile" width="400" />
</p>

---

### 여러 파일 공유

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

Direct Share Target은 사용자가 앱을 선택하지 않아도 Sharesheet에 추천 수신자로 표시되는 바로가기입니다.

#### Direct Share Target 등록

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

#### Direct Share Target 삭제

```kotlin
shareUseCases.removeDirectShareTargets(listOf("sample_1"))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_RemoveDirectShareTarget.png" alt="Example_ShareSampleScreen_RemoveDirectShareTarget" width="400" />
</p>

---

### 콜백 포함 공유

`shareWithCallback`은 Sharesheet를 열고 사용자가 선택한 앱의 패키지명을 `onResult`로 알려줍니다. `onFinished`는 선택 여부와 관계없이 Sharesheet가 닫히면 호출됩니다.

#### 기본 콜백

```kotlin
shareUseCases.shareWithCallback(
    ShareContent(text = "Hello with callback from native-toolkit")
) { pkg ->
    // pkg == null이면 선택은 되었지만 패키지명을 가져올 수 없었음
    val status = if (pkg != null) "Selected: $pkg" else "Shared (package unavailable)"
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallback.png" alt="Example_ShareSampleScreen_ShareWithCallback" width="400" />
</p>

사용자가 선택하기 전에 취소하려면 `cancelPendingCallback()`을 호출합니다.

#### 리치 프리뷰 포함 콜백

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
        // Sharesheet가 닫힘
    }
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallbackRichPreview.png" alt="Example_ShareSampleScreen_ShareWithCallbackRichPreview" width="400" />
</p>

#### 대기 중인 콜백 취소

대기 중인 `shareWithCallback` BroadcastReceiver를 취소합니다. 화면 종료 시 호출하여 리시버 누수를 방지하세요.

```kotlin
shareUseCases.cancelPendingCallback()
```

Composable 화면이 제거될 때 자동으로 취소하려면:

```kotlin
DisposableEffect(shareUseCases) {
    onDispose { shareUseCases.cancelPendingCallback() }
}
```

---

### 수신 공유 콘텐츠 처리

샘플 앱은 다른 앱에서 `ACTION_SEND` / `ACTION_SEND_MULTIPLE`로 전송된 공유 콘텐츠 수신도 보여줍니다.

수신하려면 `AndroidManifest.xml`의 Activity에 intent-filter를 추가하고 `onCreate` / `onNewIntent`에서 처리합니다:

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

### 에러 처리

`ShareUseCases`는 `ShareDomainError` 서브타입을 throw합니다.

| 에러 | 원인 | 에러 메시지 |
|---|---|---|
| `EmptyContent` | `text`가 공백 | `"Share content is empty. Please provide text or a file path."` |
| `FileNotFound` | 파일 경로가 존재하지 않음 | `"File not found: <path>"` |
| `IllegalFileAccess` | 접근 가능한 디렉토리 외부 파일 | `"File cannot be shared: <path>. Ensure the file is in a supported directory."` |
| `InvalidMimeType` | 지원하지 않는 MIME 타입 | `"Invalid MIME type: <mimeType>"` |
| `NoShareTarget` | 공유 Intent를 처리할 수 있는 앱 없음 | `"No app available to handle this share request."` |
| `DirectShareRegistrationFailed` | 바로가기 등록 실패 | `"Failed to register Direct Share target: <reason>"` |
| `EmptyIdList` | `removeDirectShareTargets`의 `ids`가 비어있음 | `"No shortcut IDs provided for removal."` |
| `EmptyFileList` | `shareFiles` / `shareImages`의 `filePaths`가 비어있음 | `"No file paths provided for share."` |
| `InvalidBase64Icon` | 아이콘 Base64 디코딩 실패 | `"Invalid icon data for Direct Share target: <id>"` |

```kotlin
try {
    shareUseCases.shareText(ShareContent(text = "Hello"), chooserActionsJson = "[]")
} catch (e: ShareDomainError.NoShareTarget) {
    // 공유 가능한 앱 없음
} catch (e: ShareDomainError.EmptyContent) {
    // 텍스트가 공백
} catch (e: ShareDomainError) {
    // 기타 도메인 에러
}
```
