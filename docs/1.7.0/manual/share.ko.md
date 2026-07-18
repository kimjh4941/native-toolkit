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
- [iOS](#ios)
  - [IosShareManager](#iossharemanager)
  - [설정](#설정-1)
  - [텍스트 공유](#텍스트-공유-2)
    - [텍스트 공유](#텍스트-공유-3)
    - [URL 공유](#url-공유-1)
    - [프리뷰 포함 URL 공유](#프리뷰-포함-url-공유)
  - [이미지 공유](#이미지-공유-1)
    - [이미지 공유](#이미지-공유-2)
    - [여러 이미지 공유](#여러-이미지-공유-1)
  - [파일 공유](#파일-공유-1)
    - [파일 공유](#파일-공유-2)
    - [여러 파일 공유](#여러-파일-공유-1)
  - [결합 콘텐츠](#결합-콘텐츠)
    - [여러 항목 공유](#여러-항목-공유)
    - [제목(Subject) 포함 공유](#제목subject-포함-공유)
    - [액티비티 타입 제외](#액티비티-타입-제외)
  - [에러 처리](#에러-처리-1)
- [macOS](#macos)
  - [MacShareManager](#macsharemanager)
  - [설정](#설정-2)
  - [피커 - 기본](#피커---기본)
    - [텍스트 공유](#텍스트-공유-4)
    - [URL 공유](#url-공유-2)
    - [이미지 공유](#이미지-공유-3)
    - [파일 공유](#파일-공유-3)
  - [피커 - 여러 항목](#피커---여러-항목)
    - [여러 이미지 공유](#여러-이미지-공유-2)
    - [여러 파일 공유](#여러-파일-공유-2)
    - [텍스트와 URL 공유](#텍스트와-url-공유)
  - [피커 - 필터](#피커---필터)
    - [특정 서비스 제외하고 공유](#특정-서비스-제외하고-공유)
  - [개별 서비스 직접 실행](#개별-서비스-직접-실행)
    - [Mail 직접 실행으로 공유](#mail-직접-실행으로-공유)
    - [서비스 실행 가능 여부 확인](#서비스-실행-가능-여부-확인)
  - [에러 처리](#에러-처리-2)

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

---

## iOS

- 라이브러리: `ios-native-toolkit-1.2.0.xcframework`
- 최소 배포 타깃: iOS 18
- 지원 범위: 전송 전용(`UIActivityViewController` 기반 시스템 공유 시트 표시). 수신(Share Extension)은 포함되지 않습니다.

### IosShareManager

`IosShareManager` 는 iOS에서 시스템 공유 시트를 표시하는 싱글턴 클래스입니다.

<p align="center">
    <img src="images/ios/share/Example_IosShareManager.png" alt="Example_IosShareManager" width="400" />
</p>

### 설정

1. `ios-native-toolkit-1.2.0.xcframework` 를 Xcode 프로젝트에 추가합니다(프로젝트로 드래그한 뒤 타깃의 Frameworks, Libraries, and Embedded Content에서 "Embed & Sign"으로 설정).
2. 공유 시트를 표시하는 파일에서 라이브러리를 임포트합니다.

```swift
import IosLibrary
```

추가 초기화는 필요하지 않습니다.

`IosShareManager.share` 는 두 가지 호출 방식을 제공합니다.

- `async throws`(네이티브 Swift 호출자에 권장): 타입이 지정된 `ShareResult` 를 반환하고, 실패 시 `ShareError` 를 throw합니다.
- 콜백(Unity Bridge에서 사용, Swift에서도 사용 가능): `(isSuccess, completed, activityType, errorMessage)`.

```swift
// async throws(Swift 호출자에 권장)
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.text("Hello")])
        )
        // result.completed == false 는 사용자가 취소했음을 의미합니다(에러 아님)
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}

// 콜백(동일)
IosShareManager.shared.share(
    content: ShareContent(items: [.text("Hello")])
) { isSuccess, completed, activityType, errorMessage in
    print(isSuccess, completed, activityType ?? "nil", errorMessage ?? "nil")
}
```

아래 예제는 `async throws` 방식을 사용합니다. SwiftUI의 `Button` 액션은 동기 클로저이므로 각 호출을 `Task { ... }` 로 감쌉니다.

### 텍스트 공유

#### 텍스트 공유

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.text("Shared from IosLibraryExample")])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareText.png" alt="Example_IosShareManager_ShareText" width="400" />
</p>

#### URL 공유

URL은 문자열로 전달합니다. 라이브러리에서 검증되며, `http` / `https` / `file` 스킴이면서 유효한 호스트를 가진 URL만 허용됩니다(그 외에는 `ShareError.invalidURL` 이 throw됩니다).

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.url("https://www.apple.com")])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareURL.png" alt="Example_IosShareManager_ShareURL" width="400" />
</p>

#### 프리뷰 포함 URL 공유

`previewTitle` 을 지정하면 네트워크 조회를 기다리지 않고 공유 시트 헤더에 리치 링크 프리뷰를 즉시 표시할 수 있습니다.

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(
            items: [.url("https://www.apple.com")],
            previewTitle: "Apple"
        )
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareURLWithPreview.png" alt="Example_IosShareManager_ShareURLWithPreview" width="400" />
</p>

### 이미지 공유

#### 이미지 공유

`.imageFile(path:)` 에 로컬 이미지의 파일 경로를 전달합니다. 라이브러리는 이를 `UIImage` 로 로드합니다(읽을 수 없으면 `ShareError.imageLoadFailed` 를 throw).

```swift
guard let imagePath = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path else {
    return
}

Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.imageFile(path: imagePath)])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareImage.png" alt="Example_IosShareManager_ShareImage" width="400" />
</p>

#### 여러 이미지 공유

`ShareContent.items` 는 여러 요소를 받으므로 여러 이미지를 한 번에 공유할 수 있습니다.

```swift
let imagePaths: [String] = /* 로컬 이미지 파일 경로 */

Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: imagePaths.map { .imageFile(path: $0) })
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultipleImages.png" alt="Example_IosShareManager_ShareMultipleImages" width="400" />
</p>

### 파일 공유

#### 파일 공유

`.file(path:)` 에 로컬 파일 경로를 전달합니다. 라이브러리는 파일 존재 여부를 확인합니다(없으면 `ShareError.fileNotFound` 를 throw).

```swift
let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("share-sample.txt")
try "Shared from IosLibraryExample.".write(to: fileURL, atomically: true, encoding: .utf8)

Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.file(path: fileURL.path)])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareFile.png" alt="Example_IosShareManager_ShareFile" width="400" />
</p>

#### 여러 파일 공유

```swift
let fileURLs: [URL] = /* 로컬 파일 URL */

Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: fileURLs.map { .file(path: $0.path) })
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultipleFiles.png" alt="Example_IosShareManager_ShareMultipleFiles" width="400" />
</p>

### 결합 콘텐츠

#### 여러 항목 공유

텍스트, URL, 이미지, 파일 등 서로 다른 종류의 항목을 한 번의 공유에 섞을 수 있습니다.

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [
            .text("Check this out"),
            .url("https://www.apple.com")
        ])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultiple.png" alt="Example_IosShareManager_ShareMultiple" width="400" />
</p>

#### 제목(Subject) 포함 공유

`subject` 는 이를 지원하는 액티비티(예: Mail의 제목 줄)에서 사용됩니다.

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(
            items: [.text("Body text")],
            subject: "Sample Subject"
        )
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareWithSubject.png" alt="Example_IosShareManager_ShareWithSubject" width="400" />
</p>

#### 액티비티 타입 제외

`excludedActivityTypes` 에 원시 액티비티 타입 식별자를 전달하면 공유 시트에서 숨길 수 있습니다.

```swift
Task {
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
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareExcludingActivities.png" alt="Example_IosShareManager_ShareExcludingActivities" width="400" />
</p>

### 에러 처리

`async throws` API는 실패 시 `ShareError` 를 throw합니다. 사용자의 취소는 에러가 아니며 `ShareResult.completed == false` 로 통지됩니다.

| 에러 | 원인 | 에러 메시지 |
|---|---|---|
| `noValidItems` | `items` 가 비어 있음 | `"No shareable items were provided."` |
| `invalidURL(String)` | URL 문자열이 유효한 `http`/`https`/`file` URL이 아님 | `"Invalid URL: <value>."` |
| `imageLoadFailed(path:)` | 해당 경로의 이미지를 로드할 수 없음 | `"Failed to load image at path: <path>."` |
| `fileNotFound(path:)` | 해당 경로의 파일이 존재하지 않음 | `"File not found at path: <path>."` |
| `noRootViewController` | 표시할 루트 뷰 컨트롤러가 없음 | `"No root view controller available to present the share sheet."` |
| `presentationFailed(Error)` | 표시 실패 또는 시스템 에러 | `"Failed to present the share sheet: <detail>."` |
| `unknown(Error)` | 예기치 않은 에러 | `"An unknown error occurred: <detail>."` |

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.text("Hello")])
        )
        if result.completed {
            // result.activityType 를 통해 공유 성공
        } else {
            // 사용자가 취소
        }
    } catch let error as ShareError {
        // 타입이 지정된 에러(예: .noValidItems, .invalidURL, .fileNotFound)
        print(error.localizedDescription)
    } catch {
        // 기타 에러
    }
}
```

콜백 API를 사용하는 경우, 실패는 `isSuccess == false` 와 nil이 아닌 `errorMessage` 로 전달됩니다.

```swift
IosShareManager.shared.share(
    content: ShareContent(items: [])
) { isSuccess, completed, activityType, errorMessage in
    // isSuccess == false, errorMessage == "No shareable items were provided."
}
```

---

## macOS

- 라이브러리: `mac-native-toolkit-1.2.0.xcframework`
- 최소 배포 타깃: macOS 15
- 지원 범위: 전송 전용. 피커(`NSSharingServicePicker`)와 개별 서비스 직접 실행(`NSSharingService`)을 제공합니다. 수신은 포함되지 않습니다.
- macOS에는 두 가지 공유 방식이 있습니다. 사용자가 공유 대상을 선택하는 **피커**(`NSSharingServicePicker`)와, 피커를 표시하지 않고 지정한 서비스를 바로 실행하는 **개별 서비스 직접 실행**(`NSSharingService`. 예: `recipients`/`subject`를 설정한 상태로 Mail 실행)입니다.

### MacShareManager

`MacShareManager`는 macOS에서 시스템 공유 피커 표시와 개별 서비스 직접 실행을 제공하는 싱글턴 클래스입니다.

**중요:** 피커 표시는 버튼 클릭 등 사용자 조작에 의해 트리거되는 처리 안에서만 호출하세요. `NSSharingServicePicker.show(...)`는 `mouseDown` 이벤트 컨텍스트에서의 호출을 요구하지만, 피커 호출 경로는 내부적으로 `Task { @MainActor in ... }`를 거치기 때문에 이 컨텍스트가 유지된다는 것이 사양상 엄격히 보장되지는 않습니다. 본 툴킷에 포함된 샘플 앱에서는 실제 클릭으로 트리거했을 때 피커가 정상적으로 표시되고 해석(표시/취소/완료)됨을 확인했습니다. 개별 서비스 직접 실행(`shareViaService` / `share(content:serviceName:completion:)`)은 `mouseDown` 컨텍스트에 의존하지 않으므로, 신뢰성이 중요한 경우 더 견고한 방법입니다.

<p align="center">
    <img src="images/mac/share/Example_MacShareManager.png" alt="Example_MacShareManager" width="800" />
</p>

### 설정

1. `mac-native-toolkit-1.2.0.xcframework`를 Xcode 프로젝트에 추가합니다(프로젝트로 드래그하고 타깃의 Frameworks, Libraries, and Embedded Content에서 "Embed & Sign"으로 설정).
2. 공유 피커나 서비스를 실행하는 파일에서 라이브러리를 임포트합니다.

```swift
import MacLibrary
```

추가 초기화는 필요하지 않습니다.

`MacShareManager`는 각 작업에 대해 두 가지 호출 방식을 제공합니다.

- `async throws`(네이티브 Swift 호출자에 권장): 타입이 지정된 `ShareResult`를 반환하고, 실패 시 `ShareError`를 throw합니다.
- 콜백(Unity Bridge가 사용, Swift에서도 사용 가능): `(isSuccess, completed, serviceName, errorMessage)`.

```swift
// async throws (Swift 호출자에 권장)
Task {
    do {
        let result = try await MacShareManager.shared.share(
            content: ShareContent(items: [.text("Hello")])
        )
        // result.completed == false는 사용자가 취소했음을 의미합니다(에러 아님)
        print(result.completed, result.serviceName ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}

// 콜백 (동일한 동작)
MacShareManager.shared.share(
    content: ShareContent(items: [.text("Hello")])
) { isSuccess, completed, serviceName, errorMessage in
    print(isSuccess, completed, serviceName ?? "nil", errorMessage ?? "nil")
}
```

아래 예제는 `async throws` 방식을 사용합니다. SwiftUI `Button`의 action은 동기 처리이므로 각 호출을 `Task { ... }`로 감쌉니다.

### 피커 - 기본

#### 텍스트 공유

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

#### URL 공유

URL은 문자열로 전달합니다. 라이브러리 내부에서 검증되며, `http` / `https` / `file` 스킴이면서 호스트가 유효한 경우만 허용됩니다(그 외에는 `ShareError.invalidURL`이 throw됩니다).

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

#### 이미지 공유

`.imageFile(path:)`에 이미지의 로컬 파일 경로를 전달합니다. 라이브러리는 이를 `NSImage`로 로드합니다(읽을 수 없으면 `ShareError.imageLoadFailed`가 throw됩니다).

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

#### 파일 공유

`.file(path:)`에 파일의 로컬 경로를 전달합니다. 라이브러리는 파일 존재 여부를 확인합니다(존재하지 않으면 `ShareError.fileNotFound`가 throw됩니다).

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

### 피커 - 여러 항목

#### 여러 이미지 공유

`ShareContent.items`는 여러 항목을 받을 수 있으므로 한 번에 여러 이미지를 공유할 수 있습니다(샘플 이미지는 하나만 번들되어 있어 여러 임시 파일로 복사해서 사용합니다).

```swift
let imagePaths: [String] = /* 로컬 이미지 파일 경로 배열 */

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

#### 여러 파일 공유

```swift
let fileURLs: [URL] = /* 로컬 파일 URL 배열 */

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

#### 텍스트와 URL 공유

텍스트, URL, 이미지, 파일 등 서로 다른 종류의 항목을 한 번의 공유에 섞어서 지정할 수 있습니다.

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

### 피커 - 필터

#### 특정 서비스 제외하고 공유

`excludedServiceTitles`에 서비스의 표시 이름을 전달하면 피커에서 해당 서비스를 숨깁니다. 이는 **best-effort** 방식입니다. `NSSharingService`는 호출자에게 안정적인 raw identifier를 제공하지 않으므로, 비교는 로컬라이즈될 수 있는 표시 이름(`title`)을 기준으로 이루어지며 환경에 따라 일치하지 않을 수 있습니다. 확실한 제어가 필요하다면 개별 서비스 직접 실행(`shareViaService`)을 사용하세요.

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

### 개별 서비스 직접 실행

#### Mail 직접 실행으로 공유

피커를 표시하지 않고 지정한 서비스 하나를 바로 실행합니다. `serviceName`에는 raw `NSSharingService.Name` 값(예: `"com.apple.share.Mail.compose"`)을 전달합니다. `recipients`와 `subject`는 서비스 실행 전에 적용됩니다. 피커 방식에서는 적용되지 않습니다.

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

#### 서비스 실행 가능 여부 확인

지정한 서비스가 전달한 콘텐츠를 공유할 수 있는지 조회합니다. 예를 들어 버튼을 탭하기 전에 활성/비활성 상태를 전환할 때 사용합니다.

```swift
Task {
    let canPerform = try await MacShareManager.shared.canPerform(
        content: ShareContent(items: [.text("Body text")]),
        serviceName: "com.apple.share.Mail.compose"
    )
    print(canPerform)
}
```

### 에러 처리

`async throws` API는 실패 시 `ShareError`를 throw합니다. 사용자의 취소는 에러가 아니며 `ShareResult.completed == false`로 전달됩니다.

| 에러 | 원인 | 에러 메시지 |
|---|---|---|
| `noValidItems` | `items`가 비어 있음 | `"No shareable items were provided."` |
| `invalidURL(String)` | URL 문자열이 유효한 `http`/`https`/`file` URL이 아님 | `"Invalid URL: <value>."` |
| `imageLoadFailed(path:)` | 지정한 경로의 이미지를 로드할 수 없음 | `"Failed to load image at path: <path>."` |
| `fileNotFound(path:)` | 지정한 경로의 파일이 존재하지 않음 | `"File not found at path: <path>."` |
| `noAnchorView` | 피커를 표시할 기준이 되는 key window를 가져올 수 없음 | `"No key window available to anchor the sharing picker."` |
| `serviceUnavailable(name:)` | 지정한 서비스 이름을 알 수 없거나 콘텐츠를 공유할 수 없음 | `"Sharing service unavailable: <name>."` |
| `alreadyInProgress` | 다른 공유 작업이 이미 진행 중 | `"A share operation is already in progress."` |
| `presentationFailed(Error)` | 표시에 실패했거나 시스템이 에러를 보고함 | `"Failed to share: <detail>."` |
| `unknown(Error)` | 예기치 않은 에러 발생 | `"An unknown share error occurred: <detail>."` |

```swift
Task {
    do {
        let result = try await MacShareManager.shared.share(
            content: ShareContent(items: [.text("Hello")])
        )
        if result.completed {
            // result.serviceName으로 공유 성공
        } else {
            // 사용자가 취소
        }
    } catch let error as ShareError {
        // 타입이 지정된 에러. errorCode / errorMessage 포함 (예: .noValidItems, .invalidURL, .fileNotFound)
        print(error.errorCode, error.errorMessage)
    } catch {
        // 기타 에러
    }
}
```

콜백 API를 사용하는 경우, 실패는 `isSuccess == false` 와 nil이 아닌 `errorMessage` 로 전달됩니다.

```swift
MacShareManager.shared.share(
    content: ShareContent(items: [])
) { isSuccess, completed, serviceName, errorMessage in
    // isSuccess == false, errorMessage == "No shareable items were provided."
}
```
