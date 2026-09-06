# Clipboard 기능

Language:

- 日本語: [clipboard.ja.md](clipboard.ja.md)
- English: [clipboard.md](clipboard.md)
- 한국어（이 페이지）

← [매뉴얼 홈으로 돌아가기](index.ko.md)

---

## 목차

- [Android](#android)
  - [설정](#설정)
  - [복사](#복사)
    - [일반 텍스트 복사](#일반-텍스트-복사)
    - [일반 텍스트 복사（빈 문자열）](#일반-텍스트-복사빈-문자열)
    - [HTML 텍스트 복사](#html-텍스트-복사)
    - [URI 복사](#uri-복사)
    - [여러 텍스트 복사](#여러-텍스트-복사)
  - [복사 - 민감 정보](#복사---민감-정보)
    - [민감 정보 텍스트 복사](#민감-정보-텍스트-복사)
  - [읽기 / 확인](#읽기--확인)
    - [클립보드 읽기](#클립보드-읽기)
    - [데이터 존재 여부 확인](#데이터-존재-여부-확인)
    - [메타데이터 가져오기](#메타데이터-가져오기)
  - [지우기](#지우기)
    - [클립보드 지우기](#클립보드-지우기)
  - [변경 감시](#변경-감시)
    - [감시 시작](#감시-시작)
    - [감시 중지](#감시-중지)
  - [에러 처리](#에러-처리)
- [iOS](#ios)
  - [IosClipboardManager](#iosclipboardmanager)
  - [설정](#설정-1)
    - [스레드](#스레드)
    - [두 가지 호출 방식](#두-가지-호출-방식)
    - [기본값](#기본값)
  - [스코프](#스코프)
    - [일반 페이스트보드 사용](#일반-페이스트보드-사용)
    - [이름 있는 페이스트보드 생성](#이름-있는-페이스트보드-생성)
    - [이름만 참조(생성하지 않음)](#이름만-참조생성하지-않음)
    - [고유 페이스트보드 생성](#고유-페이스트보드-생성)
    - [활성 페이스트보드 삭제](#활성-페이스트보드-삭제)
    - [이름 있는 / 고유 페이스트보드는 영속 저장소가 아닙니다](#이름-있는--고유-페이스트보드는-영속-저장소가-아닙니다)
  - [복사](#복사-1)
    - [일반 텍스트 복사](#일반-텍스트-복사-1)
    - [일반 텍스트 복사(빈 문자열)](#일반-텍스트-복사빈-문자열-1)
    - [HTML 텍스트 복사](#html-텍스트-복사-1)
    - [URL 복사](#url-복사)
    - [이미지 파일 복사](#이미지-파일-복사)
    - [이미지 데이터 복사](#이미지-데이터-복사)
    - [색상 복사](#색상-복사)
    - [커스텀 데이터 복사](#커스텀-데이터-복사)
    - [여러 텍스트 복사](#여러-텍스트-복사-1)
    - [다중 표현 복사](#다중-표현-복사)
  - [복사 옵션](#복사-옵션)
    - [localOnly 를 지정해 복사](#localonly-를-지정해-복사)
    - [expirationDate 를 지정해 복사](#expirationdate-를-지정해-복사)
  - [추가](#추가)
    - [일반 텍스트 추가](#일반-텍스트-추가)
    - [URL 추가](#url-추가)
    - [추가는 개인정보 옵션을 이어받지 않습니다](#추가는-개인정보-옵션을-이어받지-않습니다)
  - [읽기 / 확인](#읽기--확인-1)
    - [읽기](#읽기)
    - [데이터 읽기](#데이터-읽기)
    - [스냅샷](#스냅샷)
    - [스냅샷(타입 지정)](#스냅샷타입-지정)
    - [개인정보: 권한 요청과 접근 알림](#개인정보-권한-요청과-접근-알림)
  - [비동기 로드](#비동기-로드)
    - [텍스트 로드](#텍스트-로드)
    - [URL 로드](#url-로드)
    - [이미지 로드](#이미지-로드)
    - [파일 로드](#파일-로드)
    - [모든 로드 취소](#모든-로드-취소)
  - [감지](#감지)
    - [패턴 감지](#패턴-감지)
    - [값 감지](#값-감지)
    - [number 와 probableWebSearch 는 클립보드 전체를 분류합니다](#number-와-probablewebsearch-는-클립보드-전체를-분류합니다)
    - [감지에는 취소 토큰이 없습니다](#감지에는-취소-토큰이-없습니다)
  - [변경 감시](#변경-감시-1)
    - [감시 시작](#감시-시작-1)
    - [감시 중지](#감시-중지-1)
    - [포그라운드 복귀 시 변경 확인](#포그라운드-복귀-시-변경-확인)
  - [붙여넣기 컨트롤](#붙여넣기-컨트롤)
    - [붙여넣기 컨트롤 생성](#붙여넣기-컨트롤-생성)
  - [지우기](#지우기-1)
  - [에러 처리](#에러-처리-1)
- [macOS](#macos)
  - [MacClipboardManager](#macclipboardmanager)
  - [설정](#설정-2)
    - [스레드](#스레드-1)
    - [두 가지 호출 방식](#두-가지-호출-방식-1)
    - [콘텐츠는 타입 식별자와 바이트의 딕셔너리입니다](#콘텐츠는-타입-식별자와-바이트의-딕셔너리입니다)
    - [기본값](#기본값-1)
  - [스코프](#스코프-1)
    - [이름 있는 페이스트보드 생성](#이름-있는-페이스트보드-생성-1)
    - [고유 페이스트보드 생성](#고유-페이스트보드-생성-1)
    - [현재 페이스트보드 삭제](#현재-페이스트보드-삭제)
    - [general 삭제(에러 1508)](#general-삭제에러-1508)
    - [빈 이름으로 페이스트보드 생성(에러 1505)](#빈-이름으로-페이스트보드-생성에러-1505)
  - [복사](#복사-2)
    - [텍스트 복사](#텍스트-복사)
    - [URL 복사](#url-복사-1)
    - [이미지 복사](#이미지-복사)
    - [여러 item 복사](#여러-item-복사)
    - [여러 representation 복사](#여러-representation-복사)
    - [빈 복사(에러 1501)](#빈-복사에러-1501)
    - [representation 이 빈 item 복사(에러 1502)](#representation-이-빈-item-복사에러-1502)
  - [복사 옵션](#복사-옵션-1)
    - [localOnly 의 기본값은 true 입니다](#localonly-의-기본값은-true-입니다)
  - [추가](#추가-1)
    - [복사한 뒤 추가](#복사한-뒤-추가)
    - [append 는 추가 대상의 프라이버시 설정을 이어받습니다](#append-는-추가-대상의-프라이버시-설정을-이어받습니다)
    - [소유권을 잃은 상태에서의 추가(에러 1511)](#소유권을-잃은-상태에서의-추가에러-1511)
  - [읽기 / 검사](#읽기--검사)
    - [Read](#read)
    - [특정 타입 읽기](#특정-타입-읽기)
    - [Snapshot](#snapshot)
    - [타입 필터가 있는 Snapshot](#타입-필터가-있는-snapshot)
    - [빈 필터로 Snapshot(에러 1512)](#빈-필터로-snapshot에러-1512)
    - [Access Behavior](#access-behavior)
  - [감지](#감지-1)
    - [패턴 감지](#패턴-감지-1)
    - [값 감지](#값-감지-1)
    - [메타데이터 감지](#메타데이터-감지)
    - [패턴을 지정하지 않은 감지(에러 1503)](#패턴을-지정하지-않은-감지에러-1503)
  - [감시](#감시)
    - [감시 시작](#감시-시작-2)
    - [잘못된 간격(에러 1523)](#잘못된-간격에러-1523)
    - [감시 중지](#감시-중지-2)
    - [포그라운드 복귀 시 변경 확인](#포그라운드-복귀-시-변경-확인-1)
  - [붙여넣기 컨트롤](#붙여넣기-컨트롤-1)
    - [잘못된 타입 식별자(에러 1504)](#잘못된-타입-식별자에러-1504)
  - [지우기](#지우기-2)
  - [에러 처리](#에러-처리-2)
    - [1514 에 대하여](#1514-에-대하여)
    - [일반적인 사용에서는 발생하지 않는 에러 코드](#일반적인-사용에서는-발생하지-않는-에러-코드)

---

## Android

- 라이브러리: `android-native-toolkit-1.3.0.aar`
- 최소 SDK: Android 12 (API 31)
- 민감한 콘텐츠 미리보기 억제: Android 13 (API 33) 이상
- 지원 범위: 복사, 읽기, 메타데이터 확인, 지우기, 클립보드 변경 감시를 `android_library`（네이티브）를 통해 제공합니다. 모든 작업에 Unity Bridge 의존성이 필요하지 않습니다.

### 설정

#### Android 네이티브（AAR）

1. `android-native-toolkit-1.3.0.aar`를 `app/libs`에 배치합니다.
2. `app/build.gradle.kts`에 의존성을 추가합니다:

```kotlin
dependencies {
    implementation(files("libs/android-native-toolkit-1.3.0.aar"))
}
```

클립보드 작업에는 추가적인 매니페스트 설정이 필요하지 않습니다. `content://` URI를 복사하려면（[URI 복사](#uri-복사) 참고）공유하려는 파일의 URI를 해석할 수 있는 `FileProvider`가 별도로 필요합니다. AAR 자체는 범용 목적의 `FileProvider`를 선언하지 않습니다.

---

### 복사

`ClipboardUseCases`는 `Context`를 받는 팩토리 함수로 가져옵니다:

```kotlin
val clipboardUseCases = ClipboardUseCases(context)
```

#### 일반 텍스트 복사

```kotlin
try {
    clipboardUseCases.copyPlainText(
        ClipContent.PlainText(text = "Hello from native-toolkit", label = "sample")
    )
} catch (e: ClipboardDomainError) {
    // 에러 처리
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyPlainText.png" alt="Example_ClipboardSampleScreen_CopyPlainText" width="400" />
</p>

#### 일반 텍스트 복사（빈 문자열）

빈 문자열은 허용되며 예외가 발생하지 않습니다.

```kotlin
clipboardUseCases.copyPlainText(ClipContent.PlainText(text = ""))
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyPlainTextEmpty.png" alt="Example_ClipboardSampleScreen_CopyPlainTextEmpty" width="400" />
</p>

#### HTML 텍스트 복사

```kotlin
clipboardUseCases.copyHtmlText(
    ClipContent.HtmlText(plainText = "Hello", htmlText = "<b>Hello</b>")
)
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyHtmlText.png" alt="Example_ClipboardSampleScreen_CopyHtmlText" width="400" />
</p>

#### URI 복사

`content://`（또는 `file://`）URI를 복사합니다. `content` / `file` 스킴만 허용되며, 그 외 스킴은 `ClipboardDomainError.InvalidUri`를 발생시킵니다.

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

#### 여러 텍스트 복사

동일한 형식의 여러 일반 텍스트 항목입니다（하나의 `ClipData`에 여러 항목을 저장합니다）.

```kotlin
clipboardUseCases.copyMultipleText(
    ClipContent.MultipleText(texts = listOf("first", "second", "third"))
)
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyMultipleText.png" alt="Example_ClipboardSampleScreen_CopyMultipleText" width="400" />
</p>

---

### 복사 - 민감 정보

`isSensitive = true`를 지정하면 복사한 내용이 민감 정보（비밀번호, 일회용 코드 등）임을 시스템에 알릴 수 있습니다.

- Android 13 (API 33) 이상에서는 시스템 표준 복사 확인 UI가 콘텐츠 미리보기를 억제합니다.
- Android 12L (API 32) 이하에서는 시스템 확인 UI 자체가 없으므로, 복사 후 직접 피드백（`Toast` 등）을 표시해야 합니다.

#### 민감 정보 텍스트 복사

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

### 읽기 / 확인

#### 클립보드 읽기

빈 클립보드는 **정상 케이스**이며 에러가 아닙니다. `read()`는 `null`을 반환합니다.

```kotlin
val result = clipboardUseCases.read()
if (result != null) {
    // result.label, result.mimeTypes, result.items（각 항목의 text / htmlText / uri / coercedText）
} else {
    // 클립보드가 비어 있음（정상）
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_ReadClipboard.png" alt="Example_ClipboardSampleScreen_ReadClipboard" width="400" />
</p>

#### 데이터 존재 여부 확인

```kotlin
val hasClip: Boolean = clipboardUseCases.hasClip()
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_HasClip.png" alt="Example_ClipboardSampleScreen_HasClip" width="400" />
</p>

#### 메타데이터 가져오기

본문 데이터에 접근하지 않고 메타데이터만 가져옵니다（Android 12+ 의 "클립보드에서 붙여넣었습니다" 접근 알림을 피할 수 있습니다）. 클립보드가 비어 있을 때도 `null`（정상 케이스）을 반환합니다.

```kotlin
val info = clipboardUseCases.getDescription()
if (info != null) {
    // info.label, info.mimeTypes
    // info.isStyledText: 서식이 있는（리치） 텍스트인지 여부
    // info.classificationStatus: ClipDescription.CLASSIFICATION_* 원시 값. 가져올 수 없으면 null
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_GetDescription.png" alt="Example_ClipboardSampleScreen_GetDescription" width="400" />
</p>

---

### 지우기

#### 클립보드 지우기

```kotlin
clipboardUseCases.clear()
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_ClearClipboard.png" alt="Example_ClipboardSampleScreen_ClearClipboard" width="400" />
</p>

---

### 변경 감시

`ClipboardChangeMonitor`는 시스템 클립보드 변경 리스너를 소유하는 클래스로, `android_library`（Unity Bridge가 아닌 네이티브 쪽）에 위치하므로 네이티브 코드에서 직접 사용할 수 있습니다.

감시는 앱이 포그라운드에 있는 동안에만 확실히 동작합니다（Android 10+ 는 백그라운드에서의 클립보드 읽기를 제한합니다）.

```kotlin
val monitor = ClipboardChangeMonitor()
```

#### 감시 시작

`onChange`는 시스템 리스너의 콜백 스레드에서 호출됩니다. UI 상태를 업데이트하는 경우 직접 메인 스레드로 전달해야 합니다.

```kotlin
monitor.start(context) {
    // 시스템 리스너의 콜백 스레드에서 호출됨
    mainHandler.post {
        // 여기서 UI 상태 업데이트
    }
}

val isObserving: Boolean = monitor.isObserving()
```

감시 중에 `start`를 다시 호출해도 no-op입니다（시스템 리스너가 중복 등록되지 않습니다）.

#### 감시 중지

```kotlin
monitor.stop()
```

감시 중인 화면/컴포넌트가 해제될 때 `stop()`을 호출하여 시스템 리스너 누수를 방지하세요:

```kotlin
DisposableEffect(monitor) {
    onDispose { monitor.stop() }
}
```

---

### 에러 처리

`ClipboardUseCases`는 `ClipboardDomainError`의 서브타입을 발생시킵니다.

| 에러 | 원인 | 에러 메시지 |
|---|---|---|
| `EmptyContent` | `copyHtmlText`에서 `htmlText`가 비어 있음 | `"Clipboard content is empty. Please provide text or HTML."` |
| `EmptyItemList` | `copyMultipleText`에서 `texts` 리스트가 비어 있음 | `"No items provided for clipboard copy."` |
| `InvalidUri` | `uri`가 비어 있거나 scheme이 `content`/`file`이 아님 | `"Invalid URI: <uri>"` |
| `ClipboardUnavailable` | 시스템 `ClipboardManager`를 가져올 수 없음 | `"Clipboard service is unavailable."` |
| `ReadNotAllowed` | `read()`가 시스템에 의해 거부됨（`SecurityException`）. 앱이 포그라운드에 있지 않을 가능성이 높음 | `"Clipboard read is not allowed. The app must be in the foreground."` |

빈 클립보드는 이러한 에러에 **포함되지 않습니다**: `read()` / `getDescription()`은 정상 케이스로 `null`을 반환합니다.

```kotlin
try {
    clipboardUseCases.copyUri(ClipContent.UriContent(uri = ""))
} catch (e: ClipboardDomainError.InvalidUri) {
    // URI가 비어 있거나 지원되지 않는 scheme
} catch (e: ClipboardDomainError) {
    // 기타 도메인 에러
}
```

---

## iOS

- 라이브러리: `ios-native-toolkit-1.3.0.xcframework`
- 최소 배포 타깃: iOS 18
- 지원 범위: 복사 / 추가, 동기 읽기, 메타데이터 스냅샷, 이름 있는 페이스트보드와 고유 페이스트보드의 수명 주기, `NSItemProvider` 기반 비동기 로드, 패턴 감지, 변경 감시, 그리고 배치만 하면 바로 동작하는 `UIPasteControl` 붙여넣기 버튼을 제공합니다.

### IosClipboardManager

`IosClipboardManager` 는 `UIPasteboard` 를 감싸는 싱글턴 클래스입니다.

### 설정

1. `ios-native-toolkit-1.3.0.xcframework` 를 Xcode 프로젝트에 추가합니다(프로젝트로 드래그한 뒤 타깃의 Frameworks, Libraries, and Embedded Content에서 "Embed & Sign"으로 설정).
2. 클립보드를 사용하는 파일에서 라이브러리를 임포트합니다.

```swift
import IosLibrary
```

추가 초기화나 `Info.plist` 설정은 필요하지 않습니다.

#### 스레드

`IosClipboardManager` 는 `@MainActor` 로 격리되어 있습니다. 메인 액터에서 호출하십시오(SwiftUI / UIKit 코드는 이미 메인 액터에 있습니다). 메인 액터가 아닌 곳에서 호출할 때는 `await MainActor.run { ... }` 을 사용합니다.

#### 두 가지 호출 방식

값을 다루는 모든 작업은 다음 두 가지 형식을 제공합니다.

- `async throws`(네이티브 Swift 호출자에게 권장): 타입이 지정된 값을 반환하며, 실패 시 `ClipboardError` 를 throw 합니다.
- 콜백: `(isSuccess, value?, errorCode?, errorMessage?)`. 반환값이 없는 작업은 `(isSuccess, errorCode?, errorMessage?)` 입니다.

```swift
// async throws(Swift 호출자에게 권장)
Task {
    do {
        try await IosClipboardManager.shared.copy(.plainText("Hello"))
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorDescription ?? "nil")
    }
}

// 콜백(동일한 동작)
IosClipboardManager.shared.copy(.plainText("Hello")) { isSuccess, errorCode, errorMessage in
    print(isSuccess, errorCode ?? "nil", errorMessage ?? "nil")
}
```

`cancelAllLoads` / `startObserving` / `stopObserving` / `checkForegroundChange` / `makePasteControl` 은 동기적으로 완료되므로 동기 형식만 제공합니다.

아래 예제는 `async throws` 형식을 사용합니다. SwiftUI 의 `Button` 액션은 동기이므로 각 호출을 `Task { ... }` 로 감쌉니다.

#### 기본값

| 설정 | 기본값 |
|---|---|
| 복사 최대 크기 | 64 MiB |
| 로드 최대 크기 | 64 MiB |
| 이미지 최대 픽셀 수 | 100,000,000 |
| 감지 타임아웃 | 5초 |
| 프로바이더 로드 타임아웃 | 15초 |
| 이미지 인코딩 타임아웃 | 10초 |

다른 값을 사용하려면 `IosClipboardManager(timeouts:limits:)` 로 인스턴스를 생성합니다. 일반적인 용도에는 `shared` 를 사용하십시오.

---

### 스코프

모든 작업은 `scope: PasteboardScope` 매개변수를 받으며 기본값은 `.general` 입니다. 일반 페이스트보드는 모든 앱과 공유되고 실행을 넘어 유지됩니다. 이름 있는 페이스트보드와 고유 페이스트보드는 실행 중인 앱 사이에서 데이터를 주고받기 위한 것입니다.

```swift
public enum PasteboardScope {
    case general
    case named(String)   // 동일한 Team ID 앱과 공유
    case unique(String)  // withUniqueName() 으로 생성. 이름은 출력값
}
```

#### 일반 페이스트보드 사용

`.general` 은 기본값이므로 생략할 수도 있습니다.

```swift
let scope: PasteboardScope = .general
```

#### 이름 있는 페이스트보드 생성

`createPasteboard(.named(_:))` 는 해당 이름의 페이스트보드가 있으면 해석하고, 없으면 생성합니다. 반환된 `PasteboardScope` 를 이후 호출에 전달하십시오.

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

#### 이름만 참조(생성하지 않음)

생성하지 않고 이름만 참조할 수도 있지만, 무언가가 생성하기 전까지는 해당 이름에 대한 모든 작업이 `CLIPBOARD_UNAVAILABLE` 로 실패합니다.

```swift
let scope = PasteboardScope.named("com.jonghyunkim.nativetoolkit.example.sample")
```

#### 고유 페이스트보드 생성

`.unique` 는 이름 생성을 시스템에 맡깁니다. 생성된 이름은 반환된 스코프에 담겨 오므로, 그 페이스트보드를 다시 사용하려면 보관해야 합니다.

```swift
Task {
    let scope = try await IosClipboardManager.shared.createPasteboard(.unique)
    // scope == .unique("<시스템이 생성한 이름>")
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CreateUniquePasteboard.png" alt="Example_IosClipboardManager_CreateUniquePasteboard" width="400" />
</p>

#### 활성 페이스트보드 삭제

```swift
Task {
    try await IosClipboardManager.shared.removePasteboard(scope)
}
```

`.general` 을 삭제하려고 하면 `ClipboardError.cannotRemoveGeneralPasteboard` 를 throw 합니다.

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_RemovePasteboard.png" alt="Example_IosClipboardManager_RemovePasteboard" width="400" />
</p>

#### 이름 있는 / 고유 페이스트보드는 영속 저장소가 아닙니다

`createPasteboard(.named(_:))` 나 `.unique` 로 만든 페이스트보드는 영속을 의도한 것이 아니지만, **생성한 앱이 종료될 때 내용이 폐기된다는 보장도 없습니다**. iOS 18.7.2 에서 측정한 결과, 앱을 강제 종료한 뒤 다시 실행해도 종료 전에 기록한 이름 있는 페이스트보드를 읽을 수 있었습니다. 시스템은 그러한 페이스트보드가 언제 회수되는지 규정하지 않습니다.

이 스코프들은 실행 중인 앱 사이에서 데이터를 주고받는 용도로만 사용하고, **민감한 데이터는 `removePasteboard(_:)` 로 명시적으로 삭제하십시오**. 앱 종료에 폐기를 의존하지 마십시오. 강제 종료에서는 `deinit` 이 실행되지 않으므로, 라이브러리가 종료 시점에 정리를 수행하더라도 이 상황에는 도움이 되지 않습니다.

설계상 생성한 앱보다 오래 유지되어야 하는 공유에는 App Group 공유 컨테이너를 사용하십시오. 이는 본 라이브러리의 범위를 벗어납니다.

---

### 복사

`copy` 는 페이스트보드의 내용을 교체합니다. `ClipboardContent` 가 지원하는 모든 형식을 표현합니다.

#### 일반 텍스트 복사

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

#### 일반 텍스트 복사(빈 문자열)

빈 문자열도 허용되며 throw 하지 않습니다.

```swift
Task {
    try await IosClipboardManager.shared.copy(.plainText(""), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyPlainTextEmpty.png" alt="Example_IosClipboardManager_CopyPlainTextEmpty" width="400" />
</p>

#### HTML 텍스트 복사

두 가지 표현을 가진 하나의 항목으로 기록되므로, HTML 을 처리하지 못하는 앱도 일반 텍스트 대체값을 얻을 수 있습니다.

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

#### URL 복사

URL 은 문자열로 전달하며 라이브러리 내부에서 검증합니다. `http` / `https` / `file` 스킴만 허용하고, 그 외에는 `ClipboardError.invalidURL` 을 throw 합니다.

```swift
Task {
    try await IosClipboardManager.shared.copy(.url("https://www.apple.com"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyURL.png" alt="Example_IosClipboardManager_CopyURL" width="400" />
</p>

#### 이미지 파일 복사

파일 경로에서 이미지를 읽어들입니다. 경로가 없으면 `ClipboardError.fileNotFound`, 이미지로 디코딩할 수 없으면 `ClipboardError.imageLoadFailed` 를 throw 합니다.

```swift
Task {
    guard let path = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path else { return }
    try await IosClipboardManager.shared.copy(.imageFile(path: path), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyImageFile.png" alt="Example_IosClipboardManager_CopyImageFile" width="400" />
</p>

#### 이미지 데이터 복사

이미지 바이트를 알려진 이미지 UTI 와 함께 명시적으로 기록합니다. 이미지로 디코딩할 수 없는 데이터는 `ClipboardError.invalidImageData` 를 throw 합니다.

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

#### 색상 복사

RGBA 각 성분은 유한한 값이면서 `0.0...1.0` 범위여야 합니다. 범위를 벗어나면 `ClipboardError.invalidColor` 를 throw 합니다.

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

#### 커스텀 데이터 복사

앱이 정의한 UTI 로 임의의 바이트를 기록합니다. UTI 는 구문이 검증되며, 잘못된 경우 `ClipboardError.invalidTypeIdentifier` 를 throw 합니다.

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

앱의 `Info.plist` 에 선언하지 않은 커스텀 UTI 는 `public.data` 에 적합하지 않으므로, `public.data` 로 파일을 로드할 때 찾을 수 없습니다. 범용 파일로 로드하려면 `public.data` 자체를 지정하십시오.

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

#### 여러 텍스트 복사

같은 형식의 일반 텍스트를 여러 개 기록합니다. 빈 배열은 `ClipboardError.emptyItemList` 를 throw 합니다.

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

#### 다중 표현 복사

하나의 항목에 여러 표현을 UTI 를 키로 담습니다. 받는 앱이 해석할 수 있는 표현을 선택합니다. 빈 딕셔너리는 `ClipboardError.emptyItemList` 를 throw 합니다.

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

### 복사 옵션

`ClipboardCopyOptions` 는 `copy` 의 개인정보 설정을 담습니다. 기본값은 `localOnly: true` 이고 만료 시각은 없습니다.

```swift
public struct ClipboardCopyOptions {
    public let localOnly: Bool       // 근처 기기로 전송하지 않음(유니버설 클립보드)
    public let expirationDate: Date? // 이 시각이 지나면 시스템이 항목을 폐기함
    public static let `default` = ClipboardCopyOptions(localOnly: true, expirationDate: nil)
}
```

#### localOnly 를 지정해 복사

`localOnly: true` 는 유니버설 클립보드를 통해 근처 기기로 항목을 전달하지 말 것을 시스템에 요청합니다. 기기 간 전송을 의도할 때만 `false` 로 설정하십시오.

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

#### expirationDate 를 지정해 복사

지정하는 시각은 미래여야 하며, 그렇지 않으면 `ClipboardError.invalidExpirationDate` 를 throw 합니다.

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

### 추가

`append` 는 이미 페이스트보드에 있는 내용을 교체하지 않고 항목을 추가합니다.

#### 일반 텍스트 추가

```swift
Task {
    try await IosClipboardManager.shared.append(.plainText("appended item"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_AppendPlainText.png" alt="Example_IosClipboardManager_AppendPlainText" width="400" />
</p>

#### URL 추가

```swift
Task {
    try await IosClipboardManager.shared.append(.url("https://developer.apple.com"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_AppendURL.png" alt="Example_IosClipboardManager_AppendURL" width="400" />
</p>

#### 추가는 개인정보 옵션을 이어받지 않습니다

`append` 는 `ClipboardCopyOptions` 를 받을 수 없으며, 직전 `copy` 에서 지정한 `localOnly` / `expirationDate` 가 추가된 항목에 적용된다는 보장도 없습니다. **민감한 데이터에는 반드시 `copy(_:options:)` 를 사용하십시오.**

---

### 읽기 / 확인

#### 읽기

페이스트보드를 동기적으로 읽습니다. 큰 페이로드(이미지 바이트)는 결과에 포함되지 않고 UTI 만 보고됩니다. 빈 페이스트보드는 에러가 아니라 **정상 상태**이며 `numberOfItems` 가 `0` 이 됩니다.

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

#### 데이터 읽기

지정한 UTI 로 등록된 바이트를 반환합니다. 일치하는 항목이 없으면 `nil` 을 반환합니다.

```swift
Task {
    let data = try await IosClipboardManager.shared.readData(utType: "public.png", scope: scope)
    print(data?.count ?? 0)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_ReadData.png" alt="Example_IosClipboardManager_ReadData" width="400" />
</p>

#### 스냅샷

본문을 건드리지 않고 메타데이터만 읽습니다. 사전 확인에는 이 API 를 사용하십시오. iOS 16 이상의 권한 요청과 iOS 14 이상의 접근 알림 중 어느 것도 발생시키지 않는다고 Apple 이 명시한 API 만으로 구성되어 있습니다.

```swift
Task {
    let snapshot = try await IosClipboardManager.shared.snapshot(scope: scope)
    // snapshot.hasStrings, snapshot.hasURLs, snapshot.hasImages, snapshot.hasColors
    // snapshot.numberOfItems, snapshot.typeIdentifiers, snapshot.allTypeIdentifiers
    if snapshot.hasStrings {
        // 붙여넣기 UI 를 표시합니다
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_Snapshot.png" alt="Example_IosClipboardManager_Snapshot" width="400" />
</p>

`hasStrings` 로는 특정 타입에 대한 붙여넣기가 성공할지 판단할 수 없습니다. 예를 들어 `public.vcard` 는 `public.plain-text` 의 하위 타입이 아니라 형제 타입이므로, `hasStrings` 를 만족해도 일반 텍스트로는 로드할 수 없습니다. 허용할 타입을 명시적으로 선언하십시오([붙여넣기 컨트롤](#붙여넣기-컨트롤) 참고).

#### 스냅샷(타입 지정)

`matchingTypes` 를 전달하면 해당 타입을 가진 항목의 인덱스도 알 수 있습니다. `matchingTypes` 를 지정하지 않으면 `matchingItemIndexes` 는 `nil` 입니다.

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

#### 개인정보: 권한 요청과 접근 알림

`read` / `readData` / `loadItem` 은 페이스트보드에서 데이터를 가져오므로, 시스템의 판단에 따라 iOS 16 이상의 권한 요청이나 iOS 14 이상의 접근 알림이 표시될 수 있습니다. 사전 확인에는 `snapshot` 을 사용하십시오.

`UIPasteControl`(`makePasteControl` 경유)은 iOS 16 이상의 권한 요청을 피하지만, iOS 14 이상의 접근 알림까지 피한다고 Apple 이 명시하지는 않았습니다. 어느 쪽이든 표시되지 않는다고 전제하기 전에 대상 OS 버전의 실기기에서 확인하십시오.

---

### 비동기 로드

`loadItem` 은 `NSItemProvider` 를 통해 항목을 해석합니다. 표현 간 변환이나 메인 스레드 밖에서의 이미지 디코딩이 가능합니다. `read` 만으로 부족할 때 사용하십시오.

#### 텍스트 로드

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

#### URL 로드

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

#### 이미지 로드

이미지는 백그라운드 executor 에서 PNG 로 다시 인코딩되므로, 반환되는 UTI 는 항상 `public.png` 입니다.

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

#### 파일 로드

항목을 임시 파일로 복사하고 그 URL 을 넘겨줍니다. **반환된 URL 과 그 상위 디렉터리의 소유권은 호출자에게 넘어가므로**, 사용이 끝나면 삭제해야 합니다. 전달되지 못한 파일(실패, 취소, 타임아웃)은 라이브러리 내부에서 정리합니다.

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(
        .file(utType: "public.data"),
        scope: scope
    )
    if case .file(let url) = item {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        print(size)
        // 파일 하나가 아니라, 라이브러리가 넘겨준 디렉터리를 삭제합니다.
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadFile.png" alt="Example_IosClipboardManager_LoadFile" width="400" />
</p>

#### 모든 로드 취소

대기 중인 로드를 모두 취소합니다. 취소된 로드는 `async throws` 형식에서 `ClipboardError.cancelled`(`CLIPBOARD_CANCELLED`)를 throw 하고, 콜백 형식에서는 같은 코드와 함께 `isSuccess == false` 를 보고합니다. 호출자는 이를 무시해도 되는 정상적인 결과로 다룰 수 있습니다.

```swift
IosClipboardManager.shared.cancelAllLoads()
```

콜백 형식은 `ClipboardLoadToken` 을 반환하므로 개별 로드만 취소할 수도 있습니다.

```swift
let token = IosClipboardManager.shared.loadItem(.image, scope: scope) { isSuccess, item, errorCode, errorMessage in
    print(isSuccess, errorCode ?? "nil")
}
token.cancel()
```

---

### 감지

데이터 감지는 본문을 읽지 않고(따라서 권한 요청 없이) 페이스트보드가 무엇을 담고 있는지 보고합니다.

```swift
public enum ClipboardDetectionPattern: String, CaseIterable {
    case probableWebURL, probableWebSearch, number, link, emailAddress, phoneNumber
    case postalAddress, calendarEvent, flightNumber, moneyAmount, shipmentTrackingNumber
}
```

#### 패턴 감지

요청한 패턴 중 발견된 것을 반환합니다. 빈 패턴 집합을 전달하면 `ClipboardError.emptyDetectionPatterns` 를 throw 합니다.

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

#### 값 감지

감지된 값 자체를 반환합니다. 이 작업은 내용을 읽으므로 개인정보 측면에서는 `read` 와 동일하게 다루십시오.

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

#### number 와 probableWebSearch 는 클립보드 전체를 분류합니다

`number` 와 `probableWebSearch` 는 내용에서 등장 위치를 추출하는 것이 아니라 클립보드 **전체**를 분류합니다. 숫자를 언급하기만 한 문단은 숫자도 검색어도 아니므로, 혼합된 내용에서는 이 두 패턴이 감지되지 않습니다. 확인하려면 값만 단독으로 복사하십시오.

```swift
try await IosClipboardManager.shared.copy(.plainText("42"), scope: scope)                 // number
try await IosClipboardManager.shared.copy(.plainText("swift concurrency"), scope: scope)  // probableWebSearch
```

#### 감지에는 취소 토큰이 없습니다

`detectPatterns` / `detectValues` 는 `UIPasteboard` 의 `async` 감지 API 를 감싸고 있으며, 이 API 는 취소를 지원하지 않습니다. Task 취소나 내부의 5초 타임아웃은 즉시 호출자에게 제어를 돌려주지만, 그 뒤에서 시스템 호출이 계속 실행될 수 있습니다. 그 결과는 폐기됩니다.

---

### 변경 감시

#### 감시 시작

하나의 스코프에 대해 변경 감시를 시작합니다. 두 번째 호출은(같은 스코프든 다른 스코프든) 먼저 이전 감시를 중지하므로, 동시에 유효한 구독은 항상 하나뿐입니다.

이벤트는 메인 스레드에서 전달됩니다.

```swift
do {
    try IosClipboardManager.shared.startObserving(scope: scope) { event in
        switch event.kind {
        case .changed(let typesAdded, let typesRemoved):
            print(typesAdded, typesRemoved)
        case .changedDetectedOnForeground:
            // 포그라운드 복귀 시 changeCount 비교로 감지된 변경
            break
        case .removed:
            // 이름 있는 페이스트보드 자체가 삭제됨
            break
        }
    }
} catch let error as ClipboardError {
    // pasteboardUnavailable: 스코프를 해석할 수 없어 감시가 시작되지 않았습니다
    print(error.errorCode)
}
```

`UIPasteboard.changedNotification` 은 **이 앱이 포그라운드에 있는 동안 이 앱이 수행한 변경**에 대해서만 전달됩니다. 다른 앱의 변경이나 백그라운드 중의 변경에는 알림이 발생하지 않으므로, 그 경우에는 `checkForegroundChange` 를 사용하십시오.

#### 감시 중지

```swift
IosClipboardManager.shared.stopObserving()
```

감시하는 화면을 해제할 때 호출하십시오.

```swift
.onDisappear {
    IosClipboardManager.shared.stopObserving()
}
```

#### 포그라운드 복귀 시 변경 확인

페이스트보드의 `changeCount` 를 이 매니저가 마지막으로 기록한 값과 비교해 변했는지 반환합니다. 알림이 발생하지 않는 변경을 잡기 위해, 앱이 포그라운드로 복귀했을 때 호출하십시오.

```swift
let changed = IosClipboardManager.shared.checkForegroundChange(scope: scope)
```

특정 스코프에 대한 첫 호출은 기준값을 확립하므로 항상 `false` 를 반환합니다. 기준값은 `startObserving` 이나 변경 알림 수신으로도 갱신됩니다. 반환되는 `Bool` 로는 "해석되었고 변경이 없음"과 "해석할 수 없음"을 구분할 수 없습니다. 그 차이가 필요하면 `snapshot` 을 사용하십시오.

---

### 붙여넣기 컨트롤

`UIPasteControl` 은 시스템 붙여넣기 버튼입니다. 사용자의 탭 자체가 동의에 해당하므로 iOS 16 이상의 권한 요청을 피할 수 있습니다.

#### 붙여넣기 컨트롤 생성

`makePasteControl` 은 배치만 하면 바로 동작하는 하나의 뷰를 반환합니다. 내부 리시버가 자동으로 리스폰더 체인에 참여하므로, 반환된 뷰를 그대로 뷰 계층에 추가하십시오.

`acceptedTypes` 는 비어 있을 수 없으며(`ClipboardError.invalidRequest`), 각 요소는 유효한 UTI 여야 합니다(`ClipboardError.invalidTypeIdentifier`).

```swift
let pasteView = try IosClipboardManager.shared.makePasteControl(
    acceptedTypes: ["public.plain-text", "public.url", "public.image"],
    onPaste: { items in
        print(items.count)
    },
    onPartialFailure: { errors in
        // 붙여넣은 항목 중 일부를 로드하지 못한 경우
        print(errors.map(\.errorCode))
    },
    onPasteFailure: { error in
        // 붙여넣기 자체가 실패한 경우
        print(error.errorCode)
    }
)
```

`displayMode` 의 기본값은 `.iconAndLabel` 입니다. 버튼의 모양을 바꾸려면 `.iconOnly` / `.labelOnly` / `.arrowAndLabel` 을 지정합니다. 붙여넣기 동작은 어느 모드에서나 동일합니다.

SwiftUI 에서는 `UIViewRepresentable` 로 감쌉니다.

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
            // makeUIView 안에서 동기적으로 보고하면 "Modifying state during view update" 가
            // 발생하므로, 다음 메인 액터 턴으로 미룹니다.
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

붙여넣기 버튼은 다른 곳에서 사용하는 `scope` 와 무관하게 항상 시스템 일반 페이스트보드를 대상으로 합니다.

대기 중인 붙여넣기가 취소된 경우(새 붙여넣기가 발생하거나 뷰가 해제된 경우) `onPaste` / `onPartialFailure` / `onPasteFailure` 는 **호출되지 않습니다**. 취소는 호출자가 시작한 것이며 붙여넣기 결과로 전달하지 않습니다.

버튼과 리시버를 각각 따로 배치해야 하는 고급 사례에는 `PasteControlFactory.makeComponents` 를 사용할 수 있습니다. 그 경우 리시버의 보유와 배치는 **호출자의 책임**입니다.

---

### 지우기

스코프에서 모든 항목을 삭제합니다. 페이스트보드 자체는 남습니다.

```swift
Task {
    try await IosClipboardManager.shared.clear(scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_Clear.png" alt="Example_IosClipboardManager_Clear" width="400" />
</p>

---

### 에러 처리

`async throws` 형식은 `ClipboardError` 를 throw 합니다. 콜백 형식은 같은 실패를 `errorCode` / `errorMessage` 로 보고하며, 성공 시에는 둘 다 `nil` 입니다.

`errorMessage` 는 케이스별로 고정된 영어 문자열이며 **입력값을 포함하지 않습니다**. 그대로 로그에 남겨도 안전합니다.

| `errorCode` | 케이스 | 원인 | 에러 메시지 |
|---|---|---|---|
| `CLIPBOARD_EMPTY_CONTENT` | `emptyContent` | 텍스트도 HTML 도 없는 콘텐츠 | `"Clipboard content is empty. Please provide text or HTML."` |
| `CLIPBOARD_EMPTY_ITEMS` | `emptyItemList` | `.multipleText([])` 또는 `.multiRepresentation([:])` | `"No items provided for clipboard copy."` |
| `CLIPBOARD_EMPTY_PATTERNS` | `emptyDetectionPatterns` | 빈 패턴 집합으로 감지를 호출 | `"No detection patterns were specified."` |
| `CLIPBOARD_INVALID_URL` | `invalidURL` | URL 이 비었거나 스킴이 `http` / `https` / `file` 이 아님 | `"The URL is invalid."` |
| `CLIPBOARD_INVALID_TYPE` | `invalidTypeIdentifier` | UTI 구문이 올바르지 않음 | `"The uniform type identifier is invalid."` |
| `CLIPBOARD_INVALID_NAME` | `invalidPasteboardName` | 페이스트보드 이름이 비었거나 사용할 수 없음 | `"The pasteboard name is invalid."` |
| `CLIPBOARD_INVALID_COLOR` | `invalidColor` | RGBA 성분이 유한하지 않거나 `0.0...1.0` 범위를 벗어남 | `"Color components must be finite and within 0.0...1.0."` |
| `CLIPBOARD_INVALID_IMAGE_DATA` | `invalidImageData` | 전달된 바이트를 이미지로 디코딩할 수 없음 | `"The provided image data could not be decoded."` |
| `CLIPBOARD_INVALID_EXPIRATION` | `invalidExpirationDate` | `expirationDate` 가 미래가 아님 | `"expirationDate must be in the future."` |
| `CLIPBOARD_INVALID_REQUEST` | `invalidRequest` | 요청이 올바르지 않음(`acceptedTypes` 가 비어 있는 등) | `"The request is invalid."` |
| `CLIPBOARD_CONTENT_TOO_LARGE` | `contentTooLarge` | 페이로드가 설정된 크기 상한(기본 64 MiB)을 초과 | `"The clipboard content exceeds the configured size limit."` |
| `CLIPBOARD_FILE_NOT_FOUND` | `fileNotFound` | `.imageFile(path:)` 의 경로가 존재하지 않음 | `"The requested file was not found."` |
| `CLIPBOARD_IMAGE_LOAD_FAILED` | `imageLoadFailed` | 파일은 있으나 이미지로 디코딩할 수 없음 | `"Failed to load the image."` |
| `CLIPBOARD_IMAGE_ENCODE_FAILED` | `imageEncodingFailed` | 붙여넣은 이미지를 PNG 로 다시 인코딩할 수 없음 | `"Failed to encode the pasted image."` |
| `CLIPBOARD_UNAVAILABLE` | `pasteboardUnavailable` | 이름 있는 / 고유 페이스트보드를 해석할 수 없음 | `"The requested pasteboard is unavailable."` |
| `CLIPBOARD_CANNOT_REMOVE_GENERAL` | `cannotRemoveGeneralPasteboard` | `removePasteboard(.general)` 을 호출 | `"The general pasteboard cannot be removed."` |
| `CLIPBOARD_NO_MATCHING_ITEM` | `noMatchingItem` | 요청한 타입을 가진 항목이 없음 | `"No clipboard item matches the requested type."` |
| `CLIPBOARD_LOAD_FAILED` | `providerLoadFailed` | `NSItemProvider` 가 항목 로드에 실패 | `"Failed to load the clipboard item."` |
| `CLIPBOARD_UNEXPECTED_TYPE` | `unexpectedType` | 항목을 요청한 타입으로 변환할 수 없음 | `"The clipboard item could not be converted to the requested type."` |
| `CLIPBOARD_FILE_COPY_FAILED` | `fileCopyFailed` | 붙여넣은 파일을 임시 위치로 복사하지 못함 | `"Failed to copy the pasted file."` |
| `CLIPBOARD_CANCELLED` | `cancelled` | 호출자가 로드를 취소함 | `"The clipboard load was cancelled."` |
| `CLIPBOARD_TIMED_OUT` | `timedOut` | 작업이 타임아웃됨 | `"The clipboard operation timed out."` |
| `CLIPBOARD_DETECTION_FAILED` | `detectionFailed` | 데이터 감지 시스템이 실패를 보고 | `"Pattern detection failed."` |
| `CLIPBOARD_UNKNOWN` | `unknown` | 분류되지 않은 시스템 에러 | `"An unknown error occurred."` |

빈 클립보드는 이 에러들에 **해당하지 않습니다**. `read` 는 `numberOfItems == 0` 을, `readData` 는 `nil` 을 반환하며 둘 다 정상 상태입니다.

```swift
Task {
    do {
        try await IosClipboardManager.shared.copy(.url("example.com"), scope: scope)
    } catch ClipboardError.invalidURL {
        // 스킴이 없음
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorDescription ?? "nil")
    }
}
```

---

## macOS

- 라이브러리: `mac-native-toolkit-1.3.0.xcframework`
- 최소 배포 타깃: macOS 15
- 지원 범위: 복사 / 추가, 읽기와 스냅샷, 이름 있는 페이스트보드와 고유 페이스트보드의 수명 주기, 패턴 감지(macOS 15.4 이상), 변경 감시, 그리고 배치만 하면 바로 동작하는 `PasteButton` 을 제공합니다.

### MacClipboardManager

`MacClipboardManager` 는 `NSPasteboard` 를 감싸는 싱글턴 클래스입니다.

이 절의 스크린샷은 `MacLibraryExample` 의 것입니다. 이 앱의 Clipboard 화면은 아래 절과 같은 순서로 작업을 묶어 두었습니다.

<p align="center">
    <img src="images/mac/clipboard/Example_MacClipboardManager_Overview.png" alt="Example_MacClipboardManager_Overview" width="400" />
</p>

### 설정

1. `mac-native-toolkit-1.3.0.xcframework` 를 Xcode 프로젝트에 추가합니다(프로젝트로 드래그한 뒤 타깃의 Frameworks, Libraries, and Embedded Content 에서 "Embed & Sign" 으로 설정합니다).
2. 클립보드를 사용하는 파일에서 라이브러리를 임포트합니다.

```swift
import MacLibrary
```

추가 초기화나 entitlement 는 필요하지 않습니다.

#### 스레드

모든 작업은 메인 액터에서 `NSPasteboard` 에 도달합니다. 비동기 메서드는 `async throws` 이므로 `Task` 에서 호출해 주십시오. 즉시 완료되는 네 가지 작업은 동기 메서드입니다: `accessBehavior(scope:)`, `startObserving(scope:interval:onEvent:)`, `stopObserving()`, `checkForegroundChange(scope:)`, 그리고 `makePasteButton` 팩토리입니다.

#### 두 가지 호출 방식

각 비동기 작업에는 두 가지 형태가 있습니다. `async throws` 형태는 Swift 호출자를 위한 것입니다. `completion:` 형태는 Unity 브리지를 위한 것으로, C ABI 를 넘어 Swift 의 에러 처리를 전달할 수 없기 때문에 `(isSuccess, value, errorCode, errorMessage)` 로 결과를 알립니다.

```swift
// Swift
let ownership = try await MacClipboardManager.shared.copy(content)

// 콜백
MacClipboardManager.shared.copy(content) { isSuccess, ownership, errorCode, errorMessage in
    // 메인 액터에서 정확히 한 번만 실행됩니다
}
```

#### 콘텐츠는 타입 식별자와 바이트의 딕셔너리입니다

`ClipboardContent` 는 순서가 있는 item 목록을 가지며, 각 item 은 uniform type identifier 에서 바이트로 가는 딕셔너리를 가집니다. `.plainText` 같은 편의 case 는 없습니다. **작성한 그대로 페이스트보드에 실립니다.**

```swift
let content = ClipboardContent(items: [
    ClipboardItemData(representations: [
        "public.utf8-plain-text": Data("Copied from MacLibraryExample.".utf8)
    ])
])
```

#### 기본값

| 파라미터 | 기본값 | 의미 |
|---|---|---|
| `scope` | `.general` | 시스템 페이스트보드 |
| `options` | `.default` | `localOnly: true` |
| `interval`(감시) | `0.5` 초 | 폴링 간격. 0 보다 크고 60 초 이하 |
| `timeout`(붙여넣기 버튼) | `15` 초 | 붙여넣은 item 을 로드하는 기한 |

### 스코프

스코프는 `.general`, `.named(String)`, `.unique(String)` 중 하나입니다. general 페이스트보드는 항상 존재합니다. 이름 있는 페이스트보드와 고유 페이스트보드는 생성해야 하며, **앱을 종료해도 해제되지 않습니다.** `removePasteboard(_:)` 로 해제해 주십시오.

#### 이름 있는 페이스트보드 생성

`createPasteboard` 는 페이스트보드를 생성하지만, **같은 이름이 이미 있으면 그것을 가져옵니다.** 따라서 같은 이름으로 두 번 호출해도 내용을 유지한 채 같은 페이스트보드가 반환됩니다.

```swift
Task {
    let scope = try await MacClipboardManager.shared.createPasteboard(.named("nt-sample"))
}
```

#### 고유 페이스트보드 생성

고유 페이스트보드에는 매번 새로운 시스템 이름이 부여됩니다. 두 번째를 생성하면 첫 번째를 가리킬 이름이 사라지므로, 새로 만들기 전에 이전 것을 해제해 주십시오.

```swift
Task {
    let scope = try await MacClipboardManager.shared.createPasteboard(.unique)
}
```

#### 현재 페이스트보드 삭제

```swift
Task {
    try await MacClipboardManager.shared.removePasteboard(scope)
}
```

#### general 삭제(에러 1508)

표준 페이스트보드는 해제할 수 없습니다.

```swift
Task {
    do {
        try await MacClipboardManager.shared.removePasteboard(.general)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1508
    }
}
```

#### 빈 이름으로 페이스트보드 생성(에러 1505)

빈 이름은 거부됩니다.

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.createPasteboard(.named(""))
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1505
    }
}
```

### 복사

`copy` 는 페이스트보드의 소유권을 얻어 내용을 교체하고, 이후 `append` 가 필요로 하는 `PasteboardOwnership` 을 반환합니다.

#### 텍스트 복사

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

#### URL 복사

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

#### 이미지 복사

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

#### 여러 item 복사

모든 item 이 페이스트보드에 실립니다. **그중 무엇을 사용할지는 받는 쪽 앱이 결정합니다.** 예를 들어 TextEdit 은 전부 붙여넣습니다.

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

#### 여러 representation 복사

하나의 item 이 같은 내용을 두 가지 형식으로 가집니다. 한쪽을 읽지 못하는 앱도 다른 쪽을 찾을 수 있습니다.

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

#### 빈 복사(에러 1501)

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.copy(ClipboardContent(items: []), scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1501
    }
}
```

#### representation 이 빈 item 복사(에러 1502)

representation 이 없는 item 은 거부됩니다.

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

### 복사 옵션

`ClipboardCopyOptions(localOnly:)` 는 내용을 Universal Clipboard 를 통해 다른 기기에 제공할지를 결정합니다.

#### localOnly 의 기본값은 true 입니다

**명시적으로 지정하지 않는 한, 복사한 내용은 다른 기기로 공유되지 않습니다.** `ClipboardCopyOptions.default` 는 `localOnly: true` 이며, options 를 전달하지 않는 `copy` 는 이 값을 사용합니다. 내용을 다른 기기로 보내려면 `localOnly: false` 를 명시적으로 지정해 주십시오.

```swift
Task {
    let ownership = try await MacClipboardManager.shared.copy(
        content,
        options: ClipboardCopyOptions(localOnly: false),   // 다른 기기와 공유합니다
        scope: scope
    )
}
```

2026-09-03 에 macOS 26.3 과 iOS 18.7.2 사이에서 Handoff 를 통해 측정했습니다. `localOnly: false` 에서는 약 1 초 만에 상대 기기에 도달했고, `localOnly: true` 에서는 도달하지 않았으며 상대 기기는 자신의 클립보드를 그대로 유지했습니다. 이는 한 조합의 기기에서 측정한 결과이므로, 모든 기기와 OS 에 대한 보장이 아니라 해당 조합에서의 근거로 다뤄 주십시오.

### 추가

`append` 는 **ownership 이 가리키는 페이스트보드**에 item 을 추가합니다. `append` 자체는 scope 를 받지 않습니다. ownership 이 scope 를 전달합니다.

#### 복사한 뒤 추가

```swift
Task {
    let ownership = try await MacClipboardManager.shared.copy(content, scope: scope)
    let appended = try await MacClipboardManager.shared.append(more, ownership: ownership)
}
```

#### append 는 추가 대상의 프라이버시 설정을 이어받습니다

`localOnly: true` 로 복사한 내용에 추가해도 페이스트보드가 다시 공개되지 않습니다. 원래 내용도 추가한 item 도 다른 기기에 도달하지 않습니다. 위와 같은 기기 조합으로 2026-09-03 에 측정했습니다.

#### 소유권을 잃은 상태에서의 추가(에러 1511)

다른 앱을 포함해 무언가가 페이스트보드에 쓰는 순간 소유권은 사라집니다. `append` 는 먼저 changeCount 를 대조하고, 쓰지 않은 채 throw 합니다.

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.append(late, ownership: stale)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1511
    }
}
```

자신의 앱이 소유권을 가져간 경우에도, 다른 앱이 가져간 경우에도 에러는 같습니다. 라이브러리는 "소유권이 더 이상 성립하지 않는다" 는 사실을 알릴 뿐, 누가 가져갔는지는 알리지 않습니다.

### 읽기 / 검사

#### Read

`read` 는 모든 item 을 그 전체 representation 과 함께 반환합니다.

```swift
Task {
    let result = try await MacClipboardManager.shared.read(scope: scope)
    for (index, item) in result.items.enumerated() {
        print(index, item.totalBytes, item.representations.keys.sorted())
    }
}
```

반환되는 내용에 대해, 코드를 작성하기 전에 알아 두어야 할 것이 두 가지 있습니다.

**item 은 작성한 쪽이 지정한 것보다 많은 representation 을 가집니다.** AppKit 이 자체적으로 텍스트 형식을 추가하기 때문입니다. TextEdit 에서 서식 있는 텍스트를 복사하면 `public.rtf`, `public.utf8-plain-text`, `public.utf16-external-plain-text` 가 함께 실립니다. 필요한 타입을 대조해 주십시오. 타입 집합을 완전 일치로 비교하지 말아 주십시오.

**`totalBytes` 는 모든 item, 모든 representation 의 합계이며 복사한 대상의 크기가 아닙니다.** Finder 에서 텍스트 파일 하나를 복사하니 약 850 KB 였습니다. 페이스트보드가 파일 아이콘을 `com.apple.icns` 로 함께 전달하기 때문입니다.

#### 특정 타입 읽기

`readData` 는 한 타입의 바이트를 반환하고, 해당 타입이 없으면 `nil` 을 반환합니다. **타입이 없는 것은 일반적인 결과이며 에러가 아닙니다.**

```swift
Task {
    let data = try await MacClipboardManager.shared.readData(
        utType: "public.utf8-plain-text",
        scope: scope
    )
    print(data?.count ?? -1)   // 일반 텍스트가 없으면 nil
}
```

Finder 에서 복사한 파일은 `public.utf8-plain-text` 를 가지며, 그 바이트는 일반적으로 파일의 전체 경로입니다. 읽어 들인 내용은 사용자가 전달할 의도가 없었을 수 있는 정보를 포함한다고 보고 다뤄 주십시오.

#### Snapshot

`snapshot` 은 내용을 읽지 않고 타입과 changeCount 를 알립니다.

```swift
Task {
    let snapshot = try await MacClipboardManager.shared.snapshot(scope: scope)
    print(snapshot.itemTypes.count, snapshot.changeCount)
}
```

#### 타입 필터가 있는 Snapshot

```swift
Task {
    let snapshot = try await MacClipboardManager.shared.snapshot(
        matchingTypes: ["public.utf8-plain-text"],
        scope: scope
    )
    print(snapshot.matchingItemIndexes)
}
```

#### 빈 필터로 Snapshot(에러 1512)

빈 필터는 아무것도 일치시키지 않습니다. 그것은 호출하는 쪽에서 보면 "페이스트보드가 비어 있다" 와 구분되지 않으므로 거부됩니다.

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

동기 메서드입니다. 시스템이 이 페이스트보드에 대한 프로그램적 읽기를 어떻게 다루는지 알립니다.

```swift
let behavior = try MacClipboardManager.shared.accessBehavior(scope: scope)
```

### 감지

감지에는 **macOS 15.4 이상**이 필요합니다. 그 미만에서는 내용을 읽지 않고 `detectionUnavailable`(1513) 을 throw 합니다.

#### 패턴 감지

내용을 읽지 않고 어떤 패턴이 일치하는지 알립니다.

```swift
Task {
    let found = try await MacClipboardManager.shared.detectPatterns(
        [.probableWebURL, .links, .emailAddresses],
        scope: scope
    )
}
```

#### 값 감지

일치한 값을 반환합니다. **이 작업은 내용을 읽으므로**, 사용자 조작을 기점으로 호출해 주십시오.

```swift
Task {
    let values = try await MacClipboardManager.shared.detectValues(
        [.probableWebURL, .links, .emailAddresses],
        scope: scope
    )
    print(values.links.count, values.emailAddresses.count)
}
```

#### 메타데이터 감지

```swift
Task {
    let metadata = try await MacClipboardManager.shared.detectMetadata(scope: scope)
}
```

#### 패턴을 지정하지 않은 감지(에러 1503)

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.detectPatterns([], scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1503
    }
}
```

### 감시

#### 감시 시작

동기 메서드입니다. `onEvent` 는 페이스트보드가 변경될 때마다 메인 액터에서 실행됩니다.

```swift
try MacClipboardManager.shared.startObserving(scope: scope) { event in
    print(event.changeCount)
}
```

앱이 비활성 상태인 동안 감시는 멈추고, 복귀할 때 대조합니다. **백그라운드에 있는 동안 세 번 변경되어도 도달하는 이벤트는 한 번입니다.** 페이스트보드는 과거에 담고 있던 내용의 이력을 갖지 않기 때문입니다.

#### 잘못된 간격(에러 1523)

간격은 0 보다 크고 60 초 이하여야 합니다.

```swift
do {
    try MacClipboardManager.shared.startObserving(scope: scope, interval: 0) { _ in }
} catch let error as ClipboardError {
    print(error.errorCode)   // 1523
}
```

#### 감시 중지

멱등하며 throw 하지 않습니다. 화면이 사라질 때 호출해 주십시오. 매니저는 공유되므로, 호출하지 않으면 폴링이 계속됩니다.

```swift
MacClipboardManager.shared.stopObserving()
```

#### 포그라운드 복귀 시 변경 확인

동기 메서드입니다. 이 앱이 마지막으로 확인한 시점 이후 페이스트보드가 변경되었는지 알리며, 해당 스코프의 첫 호출에서는 `true` 를 반환합니다.

```swift
let changed = try MacClipboardManager.shared.checkForegroundChange(scope: scope)
```

**감시와 함께 쓰지 말고, 감시 대신 사용해 주십시오.** 두 기능은 같은 기준을 공유하므로, 감시가 동작하는 동안 이 호출은 거의 항상 `false` 를 반환합니다. 폴링이 이미 변경을 확인하고 `onEvent` 로 알렸기 때문입니다.

### 붙여넣기 컨트롤

`makePasteButton` 은 시스템 붙여넣기 버튼을 `NSView` 로 반환합니다. 동기 메서드입니다. 뷰 생성은 즉시 완료되는 팩토리 작업이며, 눌렀을 때 시작되는 로드는 `onPaste` 로 알립니다.

```swift
let button = try MacClipboardManager.shared.makePasteButton(
    acceptedTypes: ["public.utf8-plain-text", "public.png"],
    timeout: 5
) { result in
    print(result.items.count, result.failures.count, result.isPartial)
}
```

SwiftUI 에서는 `NSViewRepresentable` 로 호스팅하고, **생성은 한 번만** 해 주십시오. 호출할 때마다 로더가 등록됩니다.

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

시스템 컨트롤의 동작에서 다음 세 가지가 따라 나옵니다.

**이 버튼은 general 스코프 전용입니다.** 다른 호출이 어떤 스코프를 쓰든 시스템 페이스트보드에서 붙여넣습니다.

**시스템은 `acceptedTypes` 에 일치하는 것만 로더에 전달합니다.** 받아들이지 않은 타입의 item 은 도달하지 않습니다. 받아들이는 item 과 받아들이지 않는 item 을 하나씩 담은 페이스트보드를 붙여넣어도 결과는 item 한 건이며, 부분 실패가 되지 않습니다.

**버튼은 항상 누를 수 있는 상태입니다.** 받아들이는 타입이 페이스트보드에 없어도 비활성화되지 않습니다.

#### 잘못된 타입 식별자(에러 1504)

시스템이 해석할 수 없는 타입 식별자는 누를 때가 아니라 버튼을 만들 때 거부됩니다.

```swift
do {
    _ = try MacClipboardManager.shared.makePasteButton(acceptedTypes: ["not a uti"]) { _ in }
} catch let error as ClipboardError {
    print(error.errorCode)   // 1504
}
```

### 지우기

`clear` 는 페이스트보드를 비우고 **페이스트보드의 새로운 changeCount** 를 반환합니다. 이는 `clearContents()` 가 반환하는 값이며, 삭제한 item 의 개수가 아닙니다.

```swift
Task {
    let changeCount = try await MacClipboardManager.shared.clear(scope: scope)
}
```

### 에러 처리

모든 작업은 `ClipboardError` 를 throw 합니다. 이 에러는 `errorCode` 와 `errorMessage` 를 가집니다.

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.copy(content, scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorMessage)
    }
}
```

| 코드 | 케이스 | 발생 조건 |
|---|---|---|
| 1501 | `emptyContent` | item 이 0 건인 `copy` / `append` |
| 1502 | `emptyRepresentations` | representation 이 없는 item |
| 1503 | `emptyDetectionPatterns` | 패턴 집합이 빈 감지 |
| 1504 | `invalidTypeIdentifier` | 시스템이 해석할 수 없는 타입 식별자 |
| 1505 | `invalidPasteboardName` | 비어 있거나 잘못된 페이스트보드 이름 |
| 1506 | `contentTooLarge` | 내용이 크기 상한을 넘음 |
| 1507 | `pasteboardUnavailable` | 이름 있는 페이스트보드를 해석할 수 없음 |
| 1508 | `cannotReleaseStandardPasteboard` | 표준 페이스트보드에 대한 `removePasteboard` |
| 1509 | `writeRejected` | 페이스트보드가 쓰기를 거부함 |
| 1510 | `appendRejected` | 소유권은 유효하지만 페이스트보드가 추가를 거부함 |
| 1511 | `ownershipLost` | 복사 이후 다른 무언가가 페이스트보드에 씀 |
| 1512 | `emptyTypeFilter` | 필터가 빈 `snapshot` |
| 1513 | `detectionUnavailable` | macOS 15.4 미만에서의 감지 |
| 1514 | `detectionDenied` | 감지 중 사용자가 접근을 거부함(아래 참조) |
| 1515 | `detectionFailed` | 그 밖의 이유로 감지가 실패함 |
| 1521 | `pasteLoadFailed` | 붙여넣기 후 item 을 로드하지 못함 |
| 1522 | `pasteLoadTimedOut` | 붙여넣기 로드가 기한을 넘김 |
| 1523 | `invalidConfiguration` | 감시 간격이 0~60 초 범위 밖 |
| 1524 | `cancelled` | 작업이 취소됨 |
| 1599 | `unknown` | 그 밖의 경우 |

#### 1514 에 대하여

1514 는 감지 중 사용자가 페이스트보드 내용에 대한 접근을 거부했음을 나타냅니다. **다만 macOS 에서 이 경로가 발생하는지는 확인되지 않았습니다.** 검증 과정에서 감지 프롬프트는 한 번도 표시되지 않았으며, 거부가 1515 로 도달할 가능성이 있습니다.

**1514 만으로 분기하지 말아 주십시오.** 거부와 일반적인 감지 실패를 같은 방식으로 다루어, 둘 다 "내용을 감지할 수 없었다" 로 처리해 주십시오. 이렇게 하면 어느 쪽이든 올바르게 동작합니다.

#### 일반적인 사용에서는 발생하지 않는 에러 코드

1506, 1507, 1509, 1510, 1521, 1522, 1524 는 API 가 알릴 수 있지만 애플리케이션에서 의도적으로 만들어 내기 어려운 조건을 나타냅니다. 받은 코드를 찾아볼 수 있도록 목록에 실었을 뿐이며, 각각에 대해 분기를 작성할 필요는 없습니다.
