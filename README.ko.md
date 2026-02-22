# native-toolkit

네이티브 앱에서 사용할 수 있는 “네이티브 다이얼로그 / 파일 선택” 유틸리티를 플랫폼별로 모아둔 툴킷입니다.

- Android: `DialogFragment` 기반 네이티브 API
- iOS: `UIAlertController` 기반 네이티브 API
- macOS: `NSAlert` / `NSOpenPanel` / `NSSavePanel` 기반 네이티브 API
- Windows: Win32 공통 다이얼로그의 C 형태 API (예: MessageBox / GetOpenFileName 등)

> 목표: 네이티브 앱에서 각 OS의 표준 UI를 “공통된 호출 방식”으로 사용할 수 있게 한다.

다른 언어 README:

- English: [README.md](README.md)
- Japanese: [README.ja.md](README.ja.md)

---

## 빠른 시작

1. 사전 빌드 산출물을 사용할 경우 `dist/<version>/` 에서 OS별 파일을 가져옵니다.
2. 연동 절차는 `manual/<version>/index.ko.md` 를 확인합니다.
3. API 참조는 `docs/<version>/` 또는 `docs/latest/` 를 사용합니다.

예시 (`1.0.0`):

- 매뉴얼: `manual/1.0.0/index.ko.md`
- 배포 문서: `docs/1.0.0/manual/`

---

## 지원 OS (1.0.0)

- Android 12 이상
- iOS 18 이상
- Windows 11 이상
- macOS 15 이상

---

## 배포 산출물 (1.0.0)

- Android: `dist/1.0.0/android/native-toolkit-1.0.0.aar`
- iOS: `dist/1.0.0/ios/NativeToolkit-1.0.0.xcframework`
- macOS:
  - `dist/1.0.0/mac/NativeToolkit-1.0.0-xcode16.xcframework`
  - `dist/1.0.0/mac/NativeToolkit-1.0.0-xcode26.xcframework`
- Windows: `dist/1.0.0/windows/nuget/NativeToolkit/NativeToolkit.1.0.0.nupkg`

---

## 포함 모듈(개요)

### Android

- `android/android_library`
  - 핵심: `AndroidDialogFragment`
  - 지원: Simple / Confirm / Single Choice / Multi Choice / Text Input / Login
  - 문서: Dokka

- `android/unity_android_plugin`
  - 보조 모듈: C ABI / JNI 브리지 계층
  - 문서: Dokka

### iOS

- `ios/IosLibrary`
  - 핵심: `IosDialogManager`
  - 지원: Alert / Confirm / Destructive / ActionSheet / TextInput / Login
  - 문서: DocC (`.docc`)

- `ios/UnityIosPlugin`
  - 보조 모듈: Swift 파사드 + Objective-C/C 브리지(C ABI)
  - 문서: DocC (`.docc`)

### macOS

- `mac/MacLibrary`
  - 핵심: `MacDialogManager`
  - 지원: Alert / File / MultiFile / Folder / MultiFolder / Save
  - 문서: DocC (`.docc`)

- `mac/UnityMacPlugin`
  - 보조 모듈: Swift + ObjC/C 브리지
  - 문서: DocC (`.docc`)

### Windows

- `windows/WindowsLibrary`
  - C 형태 API (예: `showAlertDialog`, `showFileDialog`, `showFolderDialog`)
  - 헤더: `windows/WindowsLibrary/WindowsDialogManager.h`
  - 문서: Doxygen (`windows/WindowsLibrary/Doxyfile`)

- `windows/UnityWindowsPlugin`
  - 보조 모듈: 플러그인 연동용 프로젝트 포함(현재 최소 스텁)

---

## 디렉터리 구조

```text
android/
  android_library/
  unity_android_plugin/
  AndroidLibraryExample/

ios/
  IosLibrary/
  UnityIosPlugin/
  IosLibraryExample/
  generate_docc.sh

mac/
  MacLibrary/
  UnityMacPlugin/
  MacLibraryExample/
  generate_docc.sh

windows/
  WindowsLibrary/
  UnityWindowsPlugin/
  WindowsLibraryExample/

manual/
  <version>/

docs/
  <version>/
  latest/
```

---

## 필요 환경

- Android: JDK 11 / Android SDK / Android Studio
- iOS / macOS: Xcode
- Windows: Visual Studio 2022(C++), 문서 생성 시 Doxygen

---

## 빌드(배포 산출물)

```bash
# Android AAR
./scripts/build_android_library_aar.sh --build-type release --output dist/1.0.0/android/native-toolkit-1.0.0.aar

# iOS XCFramework
./scripts/build_ios_library_xcframework.sh --configuration release --output dist/1.0.0/ios/NativeToolkit-1.0.0.xcframework

# macOS XCFramework (Xcode 16 / 26)
./scripts/build_xcode16_library_xcframework.sh --configuration release --output dist/1.0.0/mac/NativeToolkit-1.0.0-xcode16.xcframework
./scripts/build_xcode26_library_xcframework.sh --configuration release --output dist/1.0.0/mac/NativeToolkit-1.0.0-xcode26.xcframework

# Windows DLL / NuGet
./scripts/create_native_toolkit_dll.bat
```

---

## API 문서 생성

### Android

```bash
cd android/AndroidLibraryExample
./gradlew :android_library:dokkaHtml :unity_android_plugin:dokkaHtml
```

---

### iOS (DocC)

```bash
cd ios
./generate_docc.sh
```

---

### macOS (DocC)

```bash
cd mac
./generate_docc.sh
```

---

### Windows (Doxygen)

```bash
cd windows/WindowsLibrary
doxygen Doxyfile
```

---

## 문서 배포(version / latest)

`docs/<version>/` 를 생성하고, `docs/latest/` 는 `docs/` 내 가장 높은 버전으로 갱신됩니다.

```bash
./scripts/publish_docs.sh 1.0.0
```

생성 없이 복사만 할 경우:

```bash
./scripts/publish_docs.sh 1.0.0 --skip-build
```

manual 복사 원본은 `manual/<version>/` 입니다.

---

## 네이티브 연동 참조 경로

플랫폼별 네이티브 연동은 “코어 라이브러리” 문서를 시작점으로 확인하세요.

- Android: `android/android_library/MODULE.md`
- iOS: `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md`
- macOS: `mac/MacLibrary/MacLibrary/MacLibrary.docc/MacLibrary.md`
- Windows: `windows/WindowsLibrary/WindowsDialogManager.h`

---

## 라이선스

Apache License 2.0 (자세한 내용은 `LICENSE` 참조).
