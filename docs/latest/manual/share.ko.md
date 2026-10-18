# Share 기능

Language:

- 日本語: [share.ja.md](share.ja.md)
- English: [share.md](share.md)
- 한국어（이 페이지）

← [매뉴얼 홈으로 돌아가기](index.ko.md)

---

## 목차

- [Android](#android)
  - [AndroidShareManager](#androidsharemanager)
  - [설정](#설정)
    - [라이브러리 추가](#라이브러리-추가)
    - [FileProvider](#fileprovider)
    - [스레드와 이벤트](#스레드와-이벤트)
  - [텍스트 공유](#텍스트-공유)
    - [텍스트 공유](#텍스트-공유-1)
    - [URL 공유](#url-공유)
    - [리치 프리뷰 포함 텍스트 공유](#리치-프리뷰-포함-텍스트-공유)
    - [커스텀 Chooser Action 포함 텍스트 공유](#커스텀-chooser-action-포함-텍스트-공유)
    - [Chooser Action 이벤트](#chooser-action-이벤트)
    - [잘못된 Action 포함 텍스트 공유](#잘못된-action-포함-텍스트-공유)
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
  - [선택 이벤트](#선택-이벤트)
    - [선택 이벤트 포함 공유](#선택-이벤트-포함-공유)
    - [공유 선택 대기 취소](#공유-선택-대기-취소)
  - [수신 공유 콘텐츠 처리](#수신-공유-콘텐츠-처리)
  - [에러 처리](#에러-처리)
  - [C ABI](#c-abi)
    - [빌드](#빌드)
    - [Sharesheet 열기](#sharesheet-열기)
    - [선택과 Chooser Action 이벤트](#선택과-chooser-action-이벤트)
    - [Direct Share Target 등록과 삭제](#direct-share-target-등록과-삭제)
    - [에러 값](#에러-값)
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

Android의 Sharesheet입니다. 텍스트·URL·이미지·파일 공유, 리치 프리뷰, 커스텀 Chooser Action, Direct Share Target, 사용자가 선택한 앱을 다룹니다. Android 라이브러리 2.0.0은 하나의 구현을 두 가지 공개 API로 제공합니다. 샘플 앱(`AndroidLibraryExample`)은 Kotlin API를 사용합니다.

| API | 이름 | 헤더 / 패키지 | Maven 좌표 |
|---|---|---|---|
| Kotlin API | `AndroidShareManager` | `com.jonghyunkim.nativetoolkit.share` | `io.github.kimjh4941:android-native-toolkit:2.0.0` |
| C ABI | `ntk_share_*` | `<NativeToolkitC/Share.h>` | `io.github.kimjh4941:android-native-toolkit-capi:2.0.0` |

- 라이브러리: `android-native-toolkit-2.0.0.aar`(Kotlin API)와 `android-native-toolkit-capi-2.0.0.aar`(C ABI)입니다.
- 최소 SDK: Android 12 (API 31)입니다. 앱은 compileSdk 36 이상으로 컴파일하며, 라이브러리를 호출하는 Kotlin 코드에는 Kotlin 2.1 이상이 필요합니다.
- 커스텀 Chooser Action: Android 14 (API 34) 이상입니다.
- 1.x에서 마이그레이션하는 경우: [Android 라이브러리를 2.0.0으로 마이그레이션](index.ko.md#android-라이브러리를-200으로-마이그레이션)을 참조하십시오.

아래 섹션은 샘플 앱의 Share 화면 순서를 따릅니다. 마지막의 [C ABI](#c-abi)에서는 같은 작업을 C에서 수행하는 방법을 설명합니다.

---

### AndroidShareManager

`AndroidShareManager`는 공유의 진입점입니다. 인스턴스는 프로세스당 하나이며 Application Context만 보관합니다. 따라서 `getInstance`에는 어떤 Context를 전달해도 됩니다.

```kotlin
import com.jonghyunkim.nativetoolkit.share.AndroidShareManager

val shareManager = AndroidShareManager.getInstance(activity)
```

| 멤버 | 설명 |
|---|---|
| `shareText(content, preview)` | 텍스트 또는 URL을 공유합니다 |
| `shareTextWithActions(content, actions, preview)` | 커스텀 Chooser Action과 함께 텍스트를 공유합니다 |
| `shareImage(filePath, mimeType)` / `shareImages(filePaths)` | 이미지를 하나 / 여러 개 공유합니다 |
| `shareFile(filePath)` / `shareFiles(filePaths)` | 파일을 하나 / 여러 개 공유합니다 |
| `registerDirectShareTarget(target, iconBytes)` / `removeDirectShareTargets(ids)` | Direct Share Target을 추가 / 삭제합니다 |
| `shareWithCallback(content, preview, onResult, onFinished)` / `cancelPendingCallback()` | 텍스트를 공유하고 선택된 앱을 콜백으로 알립니다 / 대기를 중단합니다 |
| `shareForSelection(content, preview)` / `cancelShareSelection(token)` | 텍스트를 공유하고 토큰을 반환합니다. 선택된 앱은 `selections` 이벤트로 도착합니다 / 대기를 중단합니다 |
| `chooserActions` | `EventHub<String>`: 커스텀 Chooser Action의 탭을 액션 ID로 알립니다 |
| `selections` | `EventHub<ShareSelection>`: `shareForSelection`으로 연 Sharesheet에서 선택된 앱을 알립니다 |

모델 타입(`ShareContent`, `SharePreviewOptions`, `ShareChooserAction`, `DirectShareTarget`, `ShareSelection`)은 `com.jonghyunkim.nativetoolkit.share.domain.model`에, `ShareDomainError`는 `com.jonghyunkim.nativetoolkit.share.domain.error`에 있습니다. `preview`는 어디에 나타나든 기본값이 `SharePreviewOptions()`(프리뷰 없음)입니다.

---

### 설정

#### 라이브러리 추가

릴리스에는 `dist/1.13.0/android/m2/`에 Maven 저장소가 포함되어 있습니다. 이를 프로젝트에, 예를 들어 `third_party/native-toolkit-m2/`로 복사하고 저장소에 추가합니다.

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

저장소에는 POM과 Gradle Module Metadata가 포함되어 있으므로, 라이브러리가 의존하는 androidx 라이브러리도 Gradle이 해결합니다. AAR 파일 단독으로는 이것들이 포함되지 않습니다. AAR 파일을 직접 추가하는 경우 [라이브러리 통합 방법](index.ko.md#라이브러리-통합-방법)을 참조하십시오.

#### FileProvider

AAR은 authority가 `${applicationId}.native_toolkit.share.fileprovider`인 자체 `FileProvider`를 선언하며, 이미지·파일·썸네일 공유는 이를 거칩니다. 앱이 공유를 위해 `FileProvider`를 선언할 필요는 없습니다. 대상 디렉터리는 다음과 같습니다.

| 경로 요소 | 디렉터리 |
|---|---|
| `files-path` | `context.filesDir` |
| `cache-path` | `context.cacheDir` |
| `external-files-path` | `context.getExternalFilesDir(...)` |

그 외의 위치에 있는 파일은 `context.externalCacheDir`를 포함하여 `ShareDomainError.IllegalFileAccess`로 실패합니다.

앱 자체의 매니페스트에서 `androidx.core.content.FileProvider`를 선언하지 마십시오. 매니페스트 병합은 provider를 `android:name`으로 대조하므로 라이브러리의 선언과 충돌합니다. 1.x 매뉴얼은 공유를 위해 이 선언을 요구했습니다. 2.0.0으로 마이그레이션할 때는 그 선언을 삭제하십시오([Android 라이브러리를 2.0.0으로 마이그레이션](index.ko.md#android-라이브러리를-200으로-마이그레이션) 참조). 앱이 자체 용도로 provider가 필요하다면 `FileProvider`의 서브클래스를 자체 authority로 선언하십시오. 라이브러리는 그것을 사용하지 않습니다.

#### 스레드와 이벤트

- 공유 작업은 어느 스레드에서나 호출할 수 있습니다. 샘플은 `Dispatchers.IO`에서 파일을 준비하고 메인 스레드에서 라이브러리를 호출합니다.
- `shareWithCallback`의 `onResult`와 `onFinished`, 그리고 `chooserActions`와 `selections` 이벤트는 메인 스레드에서 호출됩니다.
- `addListener`와 `EventHub.Registration.remove`는 메인 스레드 전용입니다. 다른 스레드에서는 `IllegalStateException`을 던집니다.
- `chooserActions`와 `selections` 모두 이벤트를 보관하지 않습니다. 리스너가 등록되지 않은 동안 도착한 이벤트는 버려집니다. Sharesheet를 열기 전에 리스너를 등록하십시오.
- 이벤트 리스너가 던진 예외는 포착되어 로그에 기록되며, 다른 리스너는 그대로 실행됩니다.
- 공유는 라이브러리의 androidx.startup 이니셜라이저에 의존하지 않습니다. Startup을 비활성화한 앱은 다른 기능을 위해 Activity를 전달하여 `LibraryRuntime.ensureInitialized(activity)`를 호출합니다([초기화](index.ko.md#초기화) 참조).

---

### 텍스트 공유

#### 텍스트 공유

```kotlin
val shareManager = AndroidShareManager.getInstance(activity)

try {
    shareManager.shareText(
        ShareContent(text = "Hello from native-toolkit")
    )
} catch (e: ShareDomainError) {
    // 에러 처리 참조
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareText.png" alt="Example_ShareSampleScreen_ShareText" width="400" />
</p>

#### URL 공유

```kotlin
shareManager.shareText(
    ShareContent(text = "https://developer.android.com/", mimeType = "text/plain")
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareURL.png" alt="Example_ShareSampleScreen_ShareURL" width="400" />
</p>

#### 리치 프리뷰 포함 텍스트 공유

`SharePreviewOptions`는 Sharesheet 프리뷰에 제목과 썸네일을 추가합니다. 썸네일은 [FileProvider](#fileprovider) 디렉터리 중 하나에 있는 파일이어야 합니다. 존재하지 않거나 디렉터리 밖에 있는 썸네일은 logcat에 경고를 남기고 생략되며, 텍스트는 그대로 공유됩니다.

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

#### 커스텀 Chooser Action 포함 텍스트 공유

`shareTextWithActions`는 Sharesheet에 `ShareChooserAction`을 추가합니다. 액션은 Android 14 (API 34) 이상에서 표시됩니다. 그보다 이전 버전에서는 액션 없이 텍스트가 공유되지만, 액션 검사는 수행됩니다.

| 필드 | 설명 |
|---|---|
| `id` | [`chooserActions` 이벤트](#chooser-action-이벤트)로 돌아옵니다. 비어 있으면 안 되며, 한 번의 호출 안에서 고유해야 합니다 |
| `label` | 아이콘 아래에 표시되는 텍스트입니다 |
| `iconBytes` | `BitmapFactory`가 디코딩할 수 있는 이미지(PNG, JPEG, WebP)입니다 |

호출할 때마다 이전 호출의 액션은 더 이상 동작하지 않습니다. 오래된 Sharesheet의 액션을 탭해도 전달되지 않습니다. `InvalidChooserAction`으로 거부된 호출에서는 이전 액션이 계속 동작합니다. `BroadcastReceiver`나 매니페스트 항목은 필요하지 않습니다.

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

#### Chooser Action 이벤트

커스텀 액션의 탭은 `chooserActions`를 통해 액션의 `id`로 메인 스레드에 도착합니다. 샘플은 `MainActivity`가 존재하는 동안 리스너를 등록해 두므로, 어느 화면을 표시하고 있어도 탭을 받을 수 있습니다.

```kotlin
class MainActivity : AppCompatActivity() {

    private var chooserActionRegistration: EventHub.Registration? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val appContext = applicationContext
        val share = AndroidShareManager.getInstance(this)
        chooserActionRegistration = share.chooserActions.addListener { id, _ ->
            // id는 탭된 ShareChooserAction.id입니다(위 예에서는 "custom")
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

`EventHub`는 `com.jonghyunkim.nativetoolkit.common.event.EventHub`입니다. 리스너의 두 번째 파라미터는 그 리스너 자신의 `Registration`이며, 리스너 안에서 등록을 해제할 수 있습니다.

#### 잘못된 Action 포함 텍스트 공유

`id`가 같은 액션이 두 개 있으면 Sharesheet가 열리기 전에 `ShareDomainError.InvalidChooserAction`으로 거부됩니다. 빈 `id`나 읽을 수 있는 이미지가 아닌 아이콘도 같은 방식으로 거부됩니다.

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
    // e.id == "dup". 아무것도 열리지 않으며, 이전 공유의 액션은 계속 동작합니다.
}
```

#### 제목 및 서브젝트 포함 공유

`subject`는 이메일 제목줄(`Intent.EXTRA_SUBJECT`)로 전송됩니다. `title`은 Sharesheet 제목을 설정합니다.

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

### 이미지 공유

파일은 [FileProvider](#fileprovider) 디렉터리 중 하나에 있어야 합니다.

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

### 여러 이미지 공유

MIME 타입은 파일 확장자로 정해집니다. 모든 이미지의 타입이 같으면 그 타입, 다르면 `image/*`입니다.

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

### 파일 공유

MIME 타입은 파일 확장자로 정해집니다(라이브러리가 모르는 확장자는 `*/*`입니다).

```kotlin
val file = File(context.cacheDir, "share_sample.txt")
    .apply { writeText("Share sample from native-toolkit") }

shareManager.shareFile(file.absolutePath)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareFile.png" alt="Example_ShareSampleScreen_ShareFile" width="400" />
</p>

---

### 여러 파일 공유

MIME 타입은 모든 파일의 타입이 같으면 그 타입, 다르면 `*/*`입니다.

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

Direct Share Target은 Sharesheet에 앱 내 추천 수신자로 표시됩니다. 라이브러리는 각 타깃을 장기 유지되는 동적 바로가기로 게시합니다. Sharesheet에 표시되게 하려면, 샘플처럼 타깃의 `category`와 일치하는 카테고리의 share target을 앱이 선언합니다. 아래의 `com.example.app.ShareReceiverActivity`는 매니페스트에 등록되어 있고 `ACTION_SEND`를 받는 자신의 Activity로 바꾸십시오.

**AndroidManifest.xml**(공유를 받는 `<activity>` 안):

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

#### Direct Share Target 등록

`iconBytes`는 `BitmapFactory`가 디코딩할 수 있는 이미지입니다. 같은 `id`를 다시 등록하면 그 타깃이 교체됩니다.

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

#### Direct Share Target 삭제

```kotlin
shareManager.removeDirectShareTargets(listOf("sample_1"))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_RemoveDirectShareTarget.png" alt="Example_ShareSampleScreen_RemoveDirectShareTarget" width="400" />
</p>

---

### 콜백 포함 공유

`shareWithCallback`은 텍스트의 Sharesheet를 열고, 사용자가 선택한 앱의 패키지명을 `onResult`에 전달합니다. Android가 패키지명을 알려주지 않은 경우에는 `null`입니다. `onFinished`는 Sharesheet가 알린 결과 뒤에 한 번 실행됩니다. Android 15 (API 35) 이상에서는 복사와 편집도 결과에 포함되며, `onResult` 없이 `onFinished`가 호출됩니다. 그보다 이전 버전에서는 선택된 앱만 알려집니다. 아무것도 선택하지 않고 Sharesheet를 닫으면 아무것도 알려지지 않으므로 어느 콜백도 실행되지 않습니다.

라이브러리는 한 번에 하나의 결과만 기다리며, 이 대기는 [`shareForSelection`](#선택-이벤트)과 공유됩니다. 어느 함수로든 다른 Sharesheet를 열면 대기가 교체됩니다. 교체된 콜백은 호출되지 않으며, 이전 Sharesheet에서의 선택은 새 Sharesheet로 전달되지 않습니다. `onResult`와 `onFinished`가 던진 예외는 라이브러리가 포착하지 않습니다.

#### 기본 콜백

```kotlin
shareManager.shareWithCallback(
    ShareContent(text = "Hello with callback from native-toolkit"),
    onResult = { pkg ->
        // 앱이 선택된 경우에만 호출됩니다. Android가 패키지명을 알려주지 않은 경우 pkg == null입니다
        val status = if (pkg != null) "Selected: $pkg" else "Shared (package unavailable)"
    }
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallback.png" alt="Example_ShareSampleScreen_ShareWithCallback" width="400" />
</p>

#### 리치 프리뷰 포함 콜백

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
        // 결과를 처리한 뒤 한 번 실행됩니다
    }
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallbackRichPreview.png" alt="Example_ShareSampleScreen_ShareWithCallbackRichPreview" width="400" />
</p>

#### 대기 중인 콜백 취소

대기를 중단합니다. 이후에는 어느 콜백도 실행되지 않습니다. 대기가 공유되므로 `shareForSelection`이 시작한 대기도 중단합니다. 요청한 화면이 사라질 때 호출하십시오. 그러면 늦게 도착한 선택이 더 이상 존재하지 않는 화면을 갱신하지 않습니다. 샘플은 [선택 이벤트](#선택-이벤트)에 나오는 `onDispose`에서 호출합니다.

```kotlin
shareManager.cancelPendingCallback()
```

---

### 선택 이벤트

`shareForSelection`은 텍스트의 Sharesheet를 열고 토큰(프로세스 안에서 재사용되지 않는 `Long`)을 반환합니다. 사용자가 선택한 앱은 그 토큰과 패키지명(Android가 알려주지 않은 경우 `null`)을 담은 `ShareSelection`으로 `selections`에 도착합니다. Sharesheet를 닫은 경우나 앱이 아닌 결과(복사, 편집)에서는 아무것도 전송되지 않습니다. `selections` 이벤트를 만드는 것은 `shareForSelection`으로 연 Sharesheet뿐입니다.

샘플은 Share 화면을 표시하는 동안 리스너를 등록합니다.

```kotlin
@Composable
fun ShareSampleScreen(activity: AppCompatActivity) {
    val shareManager = remember(activity) { AndroidShareManager.getInstance(activity) }
    var statusText by remember { mutableStateOf("Result will be displayed here") }
    // shareForSelection으로 연 Sharesheet의 토큰. 선택을 기다리는 동안만 보관합니다
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

    // 아래에 버튼이 이어집니다
}
```

#### 선택 이벤트 포함 공유

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

#### 공유 선택 대기 취소

`token`의 선택 대기를 중단합니다. 그 사이에 다른 Sharesheet가 열렸다면 아무것도 하지 않습니다.

```kotlin
val token = selectionToken
if (token != null) {
    shareManager.cancelShareSelection(token)
    selectionToken = null
}
```

---

### 수신 공유 콘텐츠 처리

샘플 앱은 다른 앱에서 `ACTION_SEND`와 `ACTION_SEND_MULTIPLE`로 공유한 콘텐츠의 수신도 보여 줍니다. 이는 일반적인 Android 기능이며 라이브러리를 사용하지 않습니다. 수신하는 `Activity`에 intent-filter를 선언하고 `onCreate`와 `onNewIntent`에서 Intent를 읽습니다.

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

### 에러 처리

각 작업은 `ShareDomainError`의 서브타입을 던집니다. 메시지를 갖지 않으므로(`message`는 `null`) 타입으로 구별하고 프로퍼티를 읽으십시오.

| 에러 | 던지는 작업 | 원인 |
|---|---|---|
| `EmptyContent` | `shareText`, `shareTextWithActions`, `shareWithCallback`, `shareForSelection` | `text`가 공백입니다 |
| `InvalidMimeType(mimeType)` | `shareText`, `shareTextWithActions`, `shareImage` | MIME 타입이 공백입니다 |
| `InvalidChooserAction(id)` | `shareTextWithActions` | 액션의 `id`가 비어 있거나 중복되었거나, 아이콘이 읽을 수 있는 이미지가 아닙니다 |
| `FileNotFound(path)` | `shareImage`, `shareImages`, `shareFile`, `shareFiles` | 파일이 존재하지 않습니다 |
| `IllegalFileAccess(path)` | `shareImage`, `shareImages`, `shareFile`, `shareFiles` | 파일이 [FileProvider](#fileprovider) 디렉터리 밖에 있습니다 |
| `EmptyFileList` | `shareImages`, `shareFiles` | 리스트가 비어 있습니다 |
| `NoShareTarget` | Sharesheet를 여는 모든 작업 | 공유를 처리할 수 있는 Activity가 없습니다 |
| `DirectShareRegistrationFailed(reason)` | `registerDirectShareTarget` | Android가 바로가기를 게시하지 않았습니다 |
| `InvalidBase64Icon(id)` | `registerDirectShareTarget` | 아이콘이 읽을 수 있는 이미지가 아닙니다. 이름은 아이콘이 Base64였던 1.x의 것을 유지합니다 |
| `EmptyIdList` | `removeDirectShareTargets` | 리스트가 비어 있습니다 |

```kotlin
try {
    shareManager.shareText(ShareContent(text = "Hello"))
} catch (e: ShareDomainError.NoShareTarget) {
    // 이 공유를 처리할 수 있는 앱이 없습니다
} catch (e: ShareDomainError.EmptyContent) {
    // 텍스트가 공백이었습니다
} catch (e: ShareDomainError) {
    // 그 밖의 도메인 에러
}
```

---

### C ABI

- C에서, 그리고 공유 라이브러리의 C 함수를 호출할 수 있는 언어에서 같은 공유를 사용하기 위한 API입니다. Kotlin과 Java 코드는 `AndroidShareManager`를 호출합니다.
- `android-native-toolkit-capi-2.0.0.aar`에는 `arm64-v8a`와 `x86_64`용 `libntk.so`만, 그리고 Prefab 패키지로서 헤더 `NativeToolkitC/*.h`가 포함됩니다. 32비트로 설치된 앱에는 `libntk.so`가 없습니다.
- C ABI는 JNI를 통해 Kotlin API를 호출하므로, 두 AAR과 그 의존성을 앱의 Gradle 빌드에 포함합니다. C ABI는 앱이 시작될 때 androidx.startup이 초기화합니다. Startup을 비활성화한 앱이나 기본 프로세스가 아닌 프로세스에서 호출하는 경우에는 먼저 `ntk_android_init(env, context)`(`<NativeToolkitC/Android.h>`)를 호출합니다. 그 전까지 작업은 `NTK_SHARE_ERROR_NOT_INITIALIZED`를 반환합니다.
- 모든 함수는 어느 스레드에서나 호출할 수 있으며 메인 스레드를 기다리지 않습니다. 완료, 이벤트, 수락된 호출의 `release`는 Android 메인 스레드에서 도착합니다. 그 안에서 블로킹하지 말고, 콜백 밖으로 예외가 나가지 않게 하십시오. 프로세스가 종료됩니다.
- Sharesheet를 여는 작업은 비동기이며 앱이 포그라운드에 있어야 합니다. 반환값은 요청이 수락되었는지를 나타냅니다. 그 후 완료(`ntk_share_done_fn`)가 한 번 실행됩니다. Sharesheet가 열렸으면 `NTK_SHARE_ERROR_NONE`, 열리지 않았으면 그 이유입니다. 백그라운드에서 호출한 경우에는 `NTK_SHARE_ERROR_NOT_FOREGROUND`입니다. 완료는 사용자가 무엇을 선택하는지에 대해서는 알려주지 않습니다. 선택된 앱은 나중에 요청 ID를 담은 선택 이벤트로 도착합니다.
- 메인 스레드가 아닌 스레드에서 호출하면 함수가 반환되기 전에 완료가 도착할 수 있습니다. 완료와 요청은 `user_data`로 대응시키십시오.
- 진입 시점에 거부된 호출(`NULL` 인수, 잘못된 UTF-8, 빈 리스트, 빈 텍스트, 비어 있거나 중복된 Chooser Action ID)은 에러를 반환하고, 완료를 호출하지 않으며, 반환하기 전에 호출한 스레드에서 `release`를 한 번 호출합니다. 수락된 호출의 `release`는 완료 뒤에 메인 스레드에서 실행됩니다. `release`는 `NULL`이어도 됩니다.
- 라이브러리는 모든 입력(문자열, 배열, 아이콘 바이트)을 호출이 반환되기 전에 복사합니다.
- 콜백에 전달되는 핸들(`ntk_string*`)은 받는 쪽의 것입니다. 받는 쪽이 콜백 안에서든 나중에든, 어느 스레드에서든 `ntk_string_free`로 해제합니다.
- 요청 ID는 `uint64_t`이며 프로세스 안에서 재사용되지 않습니다.
- Direct Share 함수는 동기이며 포그라운드가 필요하지 않습니다.
- Android에서 `ntk_last_system_code()`와 모든 완료의 `system_code`는 항상 0입니다.

#### 빌드

**app/build.gradle.kts:**

```kotlin
android {
    defaultConfig {
        // libntk.so는 이 ABI에만 존재합니다. CMake도 제한하십시오. AGP는 CMake가 빌드하는
        // 모든 ABI에 대해 Prefab 패키지를 확인하며, 빠진 것이 있으면 CXX1210으로 실패합니다.
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { abiFilters("arm64-v8a", "x86_64") }
        }
    }
    buildFeatures { prefab = true }
}

dependencies {
    implementation("io.github.kimjh4941:android-native-toolkit-capi:2.0.0")
    // 자신의 Kotlin이나 Java 코드에서 호출하는 경우 Kotlin API도 선언하십시오.
    // capi의 POM은 그것을 실행 시에만 의존합니다.
    implementation("io.github.kimjh4941:android-native-toolkit:2.0.0")
}
```

**CMakeLists.txt:**

```cmake
find_package(ntk REQUIRED CONFIG)

add_library(myapp SHARED myapp.c)
target_link_libraries(myapp PRIVATE ntk::ntk)
```

전체 설정은 index.ko.md의 [C ABI](index.ko.md#c-abi)를 참조하십시오.

androidx.startup을 비활성화한 경우나 기본 프로세스가 아닌 프로세스에서만 다음과 같이 합니다.

```c
#include <NativeToolkitC/Android.h>

/* env: 호출하는 스레드의 JNIEnv*. context: 임의의 Context(jobject). Activity를 전달하면
   현재 포그라운드 Activity로도 사용됩니다. */
static void initialize_native_toolkit(void* env, void* context)
{
    /* 기다리지 않으며, 여러 번 호출해도 안전합니다. */
    ntk_android_error init_error = ntk_android_init(env, context);
    if (init_error == NTK_ANDROID_ERROR_IN_PROGRESS || init_error == NTK_ANDROID_ERROR_JNI_FAILURE) {
        /* 나중에 다시 호출합니다. NTK_ANDROID_ERROR_CLASS_NOT_FOUND는 복구되지 않습니다. AAR의
           클래스가 없습니다(예: R8이 제거한 경우). */
    }
}
```

#### Sharesheet 열기

경로는 [FileProvider](#fileprovider) 디렉터리(files, cache, external files) 안의 전체 경로이며, 썸네일도 같은 규칙을 따릅니다. `ntk_share_image`의 MIME 타입이 `NULL`이면 `image/*`입니다.

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Share.h>

static void NTK_CALL on_share_done(void* user_data, ntk_share_error error, uint32_t system_code)
{
    /* 메인 스레드에서, 수락된 호출마다 정확히 한 번 호출됩니다. NONE: Sharesheet가 열렸습니다. */
    (void)user_data; (void)system_code;
    if (error == NTK_SHARE_ERROR_NOT_FOREGROUND) {
        /* 앱이 백그라운드에 있었습니다. 아무것도 열리지 않았습니다. */
    }
}

/* icon_png: PNG, JPEG 또는 WebP 바이트입니다. */
static void open_sharesheets(const char* thumbnail_path, const uint8_t* icon_png, size_t icon_png_size,
                             const char* image_path_1, const char* image_path_2,
                             const char* file_path_1, const char* file_path_2)
{
    /* 텍스트. 0인 필드는 기본값입니다. 제목·서브젝트·프리뷰 없이 "text/plain"입니다. */
    ntk_share_text_content content;
    memset(&content, 0, sizeof(content));
    content.struct_size = (uint32_t)sizeof(content);
    content.text = "Hello from native-toolkit";

    ntk_share_error error = ntk_share_text(&content, NULL, 0, &on_share_done, NULL, NULL);

    /* 서브젝트, 제목, 리치 프리뷰. */
    content.title = "Choose an app";
    content.subject = "Sample subject line";
    content.preview_title = "Introducing content previews";
    content.preview_thumbnail_path = thumbnail_path;
    error = ntk_share_text(&content, NULL, 0, &on_share_done, NULL, NULL);

    /* 커스텀 Chooser Action(API 34 이상에서 표시). ntk_share_text를 호출할 때마다, 액션이 없더라도
       이전 Sharesheet의 액션은 더 이상 동작하지 않습니다. */
    ntk_share_chooser_action actions[1];
    actions[0].id = "custom";
    actions[0].label = "Custom";
    actions[0].icon = icon_png;
    actions[0].icon_size = icon_png_size;
    memset(&content, 0, sizeof(content));
    content.struct_size = (uint32_t)sizeof(content);
    content.text = "Shared with a custom chooser action";
    error = ntk_share_text(&content, actions, 1, &on_share_done, NULL, NULL);

    /* 이미지와 파일. */
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

#### 선택과 Chooser Action 이벤트

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Share.h>

static void NTK_CALL on_share_done(void* user_data, ntk_share_error error, uint32_t system_code)
{
    /* "Sharesheet 열기"와 같습니다. Sharesheet가 열렸으면 NONE입니다. */
    (void)user_data; (void)error; (void)system_code;
}

static void NTK_CALL on_selection(void* user_data, uint64_t request_id, ntk_string* package_name)
{
    /* 메인 스레드. Android가 알려주지 않은 경우 package_name은 NULL입니다. 받는 쪽이 해제합니다. */
    (void)user_data; (void)request_id;
    if (package_name != NULL) {
        const char* name = ntk_string_data(package_name);   /* ntk_string_free 전까지 유효합니다 */
        size_t size = ntk_string_size(package_name);
        (void)name; (void)size;
        ntk_string_free(package_name);
    }
}

static void NTK_CALL on_chooser_action(void* user_data, ntk_string* action_id)
{
    /* 메인 스레드. action_id는 탭된 ntk_share_chooser_action의 id입니다. */
    const char* id = ntk_string_data(action_id);
    size_t size = ntk_string_size(action_id);
    (void)user_data; (void)id; (void)size;
    ntk_string_free(action_id);
}

/* 열기 전에 등록합니다. 리스너가 등록되지 않은 동안에는 어느 이벤트도 보관되지 않습니다. */
ntk_share_listener* selection_listener = NULL;
ntk_share_error error = ntk_share_add_selection_listener(&on_selection, NULL, NULL, &selection_listener);

ntk_share_listener* action_listener = NULL;
error = ntk_share_add_chooser_action_listener(&on_chooser_action, NULL, NULL, &action_listener);

/* Sharesheet를 엽니다. 선택은 이 요청 ID와 함께 on_selection에 도착합니다. */
ntk_share_text_content content;
memset(&content, 0, sizeof(content));
content.struct_size = (uint32_t)sizeof(content);
content.text = "Hello with a selection event from native-toolkit";

uint64_t request_id = 0;
error = ntk_share_text_for_selection(&content, &on_share_done, NULL, NULL, &request_id);

/* 선택 대기를 중단합니다. 기다리지 않으며, request_id가 대기 중인 요청이 아니면 아무것도 하지 않습니다.
   취소하는 것은 선택 대기이며, 열기가 아닙니다(열기에는 CANCELED가 없습니다). */
error = ntk_share_cancel_selection(request_id);

/* 리스너를 삭제해도 삭제되는 것은 리스너뿐입니다. 선택 대기와 현재 액션은 남습니다.
   메인 스레드에서 삭제하면 이후 아무것도 전달되지 않습니다. 다른 스레드에서 삭제하면 그 release가
   실행될 때까지 이벤트가 도착할 수 있습니다. 삭제 후 핸들은 무효입니다. */
ntk_share_listener_remove(selection_listener);
ntk_share_listener_remove(action_listener);
```

- Kotlin API와 마찬가지로 한 번에 하나의 선택만 기다립니다. `ntk_share_text_for_selection`으로 다른 Sharesheet를 열면 이전 Sharesheet의 대기는 끝납니다.
- Sharesheet를 요청하기 전에 실패한 요청(`NTK_SHARE_ERROR_NOT_FOREGROUND`, 또는 공백만 있는 텍스트에 대한 `NTK_SHARE_ERROR_EMPTY_CONTENT`)에서는 이전 요청의 대기가 남습니다. 요청한 뒤에 실패한 요청(`NTK_SHARE_ERROR_NO_SHARE_TARGET`, `NTK_SHARE_ERROR_UNKNOWN`)에서는 이전 대기가 이미 끝났습니다.
- `out_request_id`는 `NULL`이어도 되지만, 그 경우 선택을 요청과 대응시킬 수 없습니다.
- 앱의 Kotlin 코드가 `shareForSelection`으로 연 Sharesheet의 선택은 C로 전달되지 않습니다.

#### Direct Share Target 등록과 삭제

```c
#include <string.h>
#include <NativeToolkitC/Share.h>

/* icon_png: PNG, JPEG 또는 WebP 바이트입니다. */
static void update_direct_share_targets(const uint8_t* icon_png, size_t icon_png_size)
{
    ntk_share_direct_target target;
    memset(&target, 0, sizeof(target));
    target.struct_size = (uint32_t)sizeof(target);
    target.id = "sample_1";
    target.label = "Sample User";
    target.category = NULL;              /* "android.shortcut.conversation"입니다 */
    target.icon = icon_png;              /* NULL 또는 빈 값: NTK_SHARE_ERROR_INVALID_ICON */
    target.icon_size = icon_png_size;

    ntk_share_error error = ntk_share_register_direct_target(&target);

    const char* ids[1];
    ids[0] = "sample_1";
    error = ntk_share_remove_direct_targets(ids, 1);
}
```

앱은 [Direct Share Target](#direct-share-target)에서와 같이 `shortcuts.xml`에 share target을 선언해야 합니다.

#### 에러 값

`ntk_share_error`입니다. 0부터 5까지는 C ABI의 모든 기능에서 같은 의미입니다.

| 코드 | 이름 | 발생하는 경우 | 반환 방법 |
|---|---|---|---|
| 0 | `NTK_SHARE_ERROR_NONE` | 성공입니다. 열기에서는 Sharesheet가 열렸음을 뜻합니다 | 둘 다 |
| 1 | `NTK_SHARE_ERROR_INVALID_PARAMETER` | `NULL` 인수나 콜백, 잘못된 UTF-8, 너무 작은 `struct_size` | 반환값 |
| 2 | `NTK_SHARE_ERROR_NOT_INITIALIZED` | 초기화 전의 호출입니다. 인수 검사가 먼저 수행되며, `ntk_share_cancel_selection`은 `NONE`을 반환합니다 | 반환값 |
| 3 | `NTK_SHARE_ERROR_NOT_SUPPORTED` | 구조체 중 이 버전이 모르는 부분에 0이 아닌 값이 있습니다 | 반환값 |
| 4 | `NTK_SHARE_ERROR_UNKNOWN` | 그 밖의 모든 경우입니다. 자세한 내용은 logcat(태그 `ntk`)에 있습니다 | 둘 다 |
| 5 | `NTK_SHARE_ERROR_OUT_OF_MEMORY` | 메모리 할당에 실패했습니다 | 둘 다 |
| 6 | `NTK_SHARE_ERROR_NOT_FOREGROUND` | 앱이 포그라운드에 있지 않습니다. 아무것도 열리지 않았습니다 | 완료 |
| 7 | `NTK_SHARE_ERROR_EMPTY_CONTENT` | 텍스트가 비어 있거나(반환값) 공백뿐입니다(완료) | 둘 다 |
| 8 | `NTK_SHARE_ERROR_NO_SHARE_TARGET` | 공유를 처리할 수 있는 Activity가 없습니다 | 완료 |
| 9 | `NTK_SHARE_ERROR_FILE_NOT_FOUND` | 파일이 존재하지 않습니다 | 완료 |
| 10 | `NTK_SHARE_ERROR_ILLEGAL_FILE_ACCESS` | 파일이 FileProvider 디렉터리 밖에 있습니다 | 완료 |
| 11 | `NTK_SHARE_ERROR_INVALID_MIME_TYPE` | MIME 타입이 공백입니다 | 완료 |
| 12 | `NTK_SHARE_ERROR_DIRECT_SHARE_REGISTRATION_FAILED` | Android가 바로가기를 게시하지 않았습니다 | 반환값 |
| 13 | `NTK_SHARE_ERROR_EMPTY_ID_LIST` | ID 없이 호출한 `ntk_share_remove_direct_targets` | 반환값 |
| 14 | `NTK_SHARE_ERROR_EMPTY_FILE_LIST` | 경로 없이 호출한 `ntk_share_images` 또는 `ntk_share_files` | 반환값 |
| 15 | `NTK_SHARE_ERROR_INVALID_ICON` | Direct Share 아이콘이 `NULL`이거나 비어 있거나 읽을 수 있는 이미지가 아닙니다 | 반환값 |
| 16 | `NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION` | 비어 있거나 중복된 액션 ID, `NULL`이거나 빈 아이콘(반환값), 읽을 수 있는 이미지가 아닌 아이콘(완료)입니다. 이전 Sharesheet의 액션은 계속 동작합니다 | 둘 다 |

`CANCELED`는 없습니다. 열기는 Sharesheet가 열리는 즉시 완료되며, 선택 대기의 취소는 그것과 별개입니다.

| Kotlin API | C ABI |
|---|---|
| `shareText` / `shareTextWithActions` | `ntk_share_text`(`ntk_share_text_content`와 `ntk_share_chooser_action`) |
| `shareImage` / `shareImages` / `shareFile` / `shareFiles` | `ntk_share_image` / `_images` / `_file` / `_files` |
| `registerDirectShareTarget` / `removeDirectShareTargets` | `ntk_share_register_direct_target`(`ntk_share_direct_target`) / `ntk_share_remove_direct_targets` |
| `shareForSelection` / `cancelShareSelection` | `ntk_share_text_for_selection` / `ntk_share_cancel_selection` |
| `selections.addListener` | `ntk_share_add_selection_listener` |
| `chooserActions.addListener` | `ntk_share_add_chooser_action_listener` |
| `EventHub.Registration.remove` | `ntk_share_listener_remove` |
| `shareWithCallback` / `cancelPendingCallback` | 없습니다. `ntk_share_text_for_selection`을 사용하십시오 |
| `ShareDomainError` | `ntk_share_error`의 7부터 16까지(같은 순서) |

---

## iOS

- 라이브러리: `ios-native-toolkit-1.3.0.xcframework`
- 최소 배포 타깃: iOS 18
- 지원 범위: 전송 전용(`UIActivityViewController` 기반 시스템 공유 시트 표시). 수신(Share Extension)은 포함되지 않습니다.

### IosShareManager

`IosShareManager` 는 iOS에서 시스템 공유 시트를 표시하는 싱글턴 클래스입니다.

<p align="center">
    <img src="images/ios/share/Example_IosShareManager.png" alt="Example_IosShareManager" width="400" />
</p>

### 설정

1. `ios-native-toolkit-1.3.0.xcframework` 를 Xcode 프로젝트에 추가합니다(프로젝트로 드래그한 뒤 타깃의 Frameworks, Libraries, and Embedded Content에서 "Embed & Sign"으로 설정).
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

- 라이브러리: `mac-native-toolkit-1.3.0.xcframework`
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

1. `mac-native-toolkit-1.3.0.xcframework`를 Xcode 프로젝트에 추가합니다(프로젝트로 드래그하고 타깃의 Frameworks, Libraries, and Embedded Content에서 "Embed & Sign"으로 설정).
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
