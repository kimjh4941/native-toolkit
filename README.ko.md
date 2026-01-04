# native-toolkit

Unity 등의 앱에서 사용할 수 있는 “네이티브 다이얼로그 / 파일 선택” 유틸리티를 플랫폼별로 모아둔 툴킷입니다.

- Android: `DialogFragment` 기반 범용 다이얼로그 + Unity용 JNI 브리지
- iOS: `UIAlertController` 기반 다이얼로그 + Unity용 C ABI 브리지
- macOS: `NSAlert` / `NSOpenPanel` / `NSSavePanel` 기반 다이얼로그/파일 패널 + Unity용 C 브리지
- Windows: Win32 공통 다이얼로그의 C 형태 API (예: MessageBox / GetOpenFileName 등)

> 목표: 게임/툴(특히 Unity)에서 각 OS의 표준 UI를 “공통된 호출 방식”으로 사용할 수 있게 한다.

---

## 포함 모듈(개요)

### Android

- `android/android_library`

  - 핵심: 다중 패턴 `AndroidDialogFragment` (6종 다이얼로그를 `newInstance(...)` 오버로드로 생성)
  - 지원: Simple / Confirm / Single Choice / Multi Choice / Text Input / Login
  - 문서: Dokka (`MODULE.md` 를 includes 하여 개요 포함)

- `android/unity_android_plugin`
  - Unity용: `UnityAndroidDialogManager`(Java/Kotlin) + C# 래퍼 `AndroidDialogManager`
  - Java 결과를 Unity 메인 스레드로 디스패치하는 설계 (`UnityMainThreadDispatcher` 전제)
  - 문서: Dokka (`MODULE.md` 포함)

### iOS

- `ios/IosLibrary`

  - 핵심: `IosDialogManager` (`UIAlertController` 패턴을 통일된 콜백 형태로 제공)
  - 지원: Alert / Confirm / Destructive / ActionSheet / TextInput / Login
  - 문서: DocC (`.docc`)

- `ios/UnityIosPlugin`
  - Unity용: Swift 파사드 `UnityIosDialogManager` + Objective-C/C 브리지(C ABI)
  - Unity 측에서 `DllImport("__Internal")` 의 P/Invoke로 호출하는 것을 가정
  - 문서: DocC (`.docc`)

### macOS

- `mac/MacLibrary`

  - 핵심: `MacDialogManager` (`NSAlert`/`NSOpenPanel`/`NSSavePanel` 을 `Result` 로 통일)
  - 지원: Alert / File / MultiFile / Folder / MultiFolder / Save
  - 문서: DocC (`.docc`)

- `mac/UnityMacPlugin`
  - Unity용: Swift + ObjC/C 브리지 + C# 래퍼(예: JSON 기반 Alert 설정)
  - 문서: DocC (`.docc`)

### Windows

- `windows/WindowsLibrary`

  - C 형태로 export 된 API (예: `showAlertDialog`, `showFileDialog`, `showFolderDialog` 등)
  - 헤더: `windows/WindowsLibrary/WindowsDialogManager.h`
  - 문서: Doxygen (`windows/WindowsLibrary/Doxyfile`)

- `windows/UnityWindowsPlugin`
  - Unity용 플러그인 솔루션/프로젝트 포함
  - 현재 `UnityWindowsDialogManager` 는 최소 스텁이므로, WindowsLibrary 기능을 Unity로 연결하는 구현은 향후 추가 예정

---

## 디렉터리 구조

```
android/
	android_library/            # Android 코어 다이얼로그
	unity_android_plugin/        # Unity용 Android 브리지
	AndroidLibraryExample/       # 샘플 앱/빌드 래퍼

ios/
	IosLibrary/                  # iOS 코어 다이얼로그
	UnityIosPlugin/              # Unity용 iOS 브리지
	IosLibraryExample/           # 샘플
	generate_docc.sh             # DocC 생성

mac/
	MacLibrary/                  # macOS 코어 다이얼로그/파일 패널
	UnityMacPlugin/              # Unity용 macOS 브리지
	MacLibraryExample/           # 샘플
	generate_docc.sh             # DocC 생성

windows/
	WindowsLibrary/              # Windows 코어(Win32 공통 다이얼로그)
	UnityWindowsPlugin/          # Unity용(현재는 최소 스텁)
	WindowsLibraryExample/       # 샘플
```

---

## 필요 환경

- Android

  - JDK 11
  - Android SDK / Android Studio
  - Gradle Wrapper(동봉)

- iOS / macOS

  - Xcode (DocC 생성에 `xcrun docc` 사용)

- Windows
  - Visual Studio 2022(C++)
  - (문서 생성 시) Doxygen

---

## 빌드 & 문서 생성

### Android

Android 빌드는 `android/AndroidLibraryExample` 가 워크스페이스 역할(2개 모듈 include)을 합니다.

```bash
cd android/AndroidLibraryExample

# 예: Android 코어 라이브러리
./gradlew :android_library:assembleRelease

# 예: Unity용 Android 브리지(android_library 의존)
./gradlew :unity_android_plugin:assembleRelease
```

#### Android API 문서(Dokka)

```bash
cd android/AndroidLibraryExample

./gradlew :android_library:dokkaHtml
./gradlew :unity_android_plugin:dokkaHtml
```

출력 경로:

- `android/android_library/build/dokka/html`
- `android/unity_android_plugin/build/dokka/html`

#### Android 사양 메모

- `android/android_library/build.gradle.kts`
  - `compileSdk = 35`, `minSdk = 31`, JVM target 11

---

### iOS

#### Xcode로 열기

- 워크스페이스: `ios/IosWorkspace.xcworkspace`
- 스킴: `IosLibrary`, `UnityIosPlugin`

#### iOS API 문서(DocC)

```bash
cd ios
./generate_docc.sh
```

출력 경로:

- `ios/Docs/IosLibrary`
- `ios/Docs/UnityIosPlugin`

> 참고: `ios/generate_docc.sh` 는 환경에 따라 절대 경로가 고정되어 있을 수 있습니다. 필요하면 리포지토리 루트 기준 상대 경로로 조정하세요.

---

### macOS

#### Xcode로 열기

- 워크스페이스: `mac/MacWorkspace.xcworkspace`
- 스킴: `MacLibrary`, `UnityMacPlugin`

#### macOS API 문서(DocC)

```bash
cd mac
./generate_docc.sh
```

출력 경로:

- `mac/Docs/MacLibrary`
- `mac/Docs/UnityMacPlugin`

> 참고: `mac/generate_docc.sh` 도 환경에 따라 절대 경로가 고정되어 있을 수 있습니다. 필요하면 상대 경로로 조정하세요.

---

### Windows

#### Visual Studio로 빌드

- `windows/WindowsLibrary/WindowsLibrary.sln`
- `windows/WindowsLibraryExample/WindowsLibraryExample.sln`

빌드 구성은 `Debug/Release` 와 `x86/x64` 를 가정합니다.

#### Windows API 문서(Doxygen)

`windows/WindowsLibrary/Doxyfile` 로 생성합니다.

```bash
cd windows/WindowsLibrary
doxygen Doxyfile
```

출력 경로(설정값):

- `windows/WindowsLibrary/docs`

---

## Unity 연동 메모(최소)

플랫폼별 Unity 연동은 “Unity용 모듈” 문서를 시작점으로 확인하세요.

- Android: `android/unity_android_plugin/MODULE.md`

  - Java/Kotlin 의 `UnityAndroidDialogManager` 와 C# `AndroidDialogManager` 를 전제로 함

- iOS: `ios/UnityIosPlugin/UnityIosPlugin/UnityIosPlugin.docc/UnityIosPlugin.md`

  - C ABI 브리지 함수를 `DllImport("__Internal")` 로 호출하는 방식

- macOS: `mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.docc/UnityMacPlugin.md`

  - alert 의 buttons/options JSON 스키마, 각 다이얼로그의 반환 키 정리 포함

- Windows: `windows/WindowsLibrary/WindowsDialogManager.h`
  - Unity용 브리지는 `windows/UnityWindowsPlugin` 쪽에 추가 예정(현재는 스텁)

---

## 라이선스

Apache License 2.0 (자세한 내용은 `LICENSE` 참조).
