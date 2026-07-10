# native-toolkit

A cross-platform toolkit that bundles native platform features for native apps.

- Android: `DialogFragment` + notification + share-based native API
- iOS: `UIAlertController`-based native API
- macOS: `NSAlert` / `NSOpenPanel` / `NSSavePanel`-based native API
- Windows: Win32 common dialogs and toast notifications exposed as C-style APIs

> Goal: make it easy for native apps to use each OS's standard features with a consistent calling pattern.

Other languages:

- Korean: [README.ko.md](README.ko.md)
- Japanese: [README.ja.md](README.ja.md)

## Quick start

1. If you use prebuilt artifacts, pick files from `dist/<version>/`.
2. For integration steps, read `docs/<version>/manual/index.md`.
3. For API references, use `docs/<version>/` (or `docs/latest/`).

Example (`1.6.0`):

- Manual: `docs/1.6.0/manual/index.md`
- Published docs: `docs/1.6.0/manual/`

## Detailed Documentation

- Latest (English): [docs/latest/manual/index.md](docs/latest/manual/index.md)
- Latest (Korean): [docs/latest/manual/index.ko.md](docs/latest/manual/index.ko.md)
- Latest (Japanese): [docs/latest/manual/index.ja.md](docs/latest/manual/index.ja.md)

## Version

- Current release: 1.6.0
- Latest published docs version: [docs/latest/VERSION.txt](docs/latest/VERSION.txt)

## Supported OS (1.6.0)

- Android 12+
- iOS 18+
- Windows 11+
- macOS 15+

## Distributables (1.6.0)

- Android: `dist/1.6.0/android/android-native-toolkit-1.2.0.aar`
- iOS:
  - `dist/1.6.0/ios/ios-native-toolkit-1.2.0.xcframework`
  - `dist/1.6.0/ios/unity-ios-native-toolkit-1.2.0.xcframework`
- macOS:
  - `dist/1.6.0/mac/mac-native-toolkit-1.1.0.xcframework`
  - `dist/1.6.0/mac/unity-mac-native-toolkit-1.1.0.xcframework`
- Windows: `dist/1.6.0/windows/windows-native-toolkit-1.1.0.nupkg`

## Modules (overview)

### Android

- `android/android_library`
  - Core: `AndroidDialogFragment` / Android notification APIs / `ShareUseCases`
  - Variants: Simple / Confirm / Single Choice / Multi Choice / Text Input / Login / Notification / Share
  - Docs: Dokka

- `android/unity_android_plugin`
  - Optional integration module: C ABI / JNI bridge layer
  - Docs: Dokka

### iOS

- `ios/IosLibrary`
  - Core: `IosDialogManager`
  - Variants: Alert / Confirm / Destructive / ActionSheet / TextInput / Login
  - Docs: DocC (`.docc`)

- `ios/UnityIosPlugin`
  - Optional integration module: Swift facade + Objective-C/C bridge (C ABI)
  - Docs: DocC (`.docc`)

### macOS

- `mac/MacLibrary`
  - Core: `MacDialogManager`
  - Variants: Alert / File / MultiFile / Folder / MultiFolder / Save
  - Docs: DocC (`.docc`)

- `mac/UnityMacPlugin`
  - Optional integration module: Swift + ObjC/C bridge
  - Docs: DocC (`.docc`)

### Windows

- `windows/WindowsLibrary`
  - C-exported APIs (e.g., `showAlertDialog`, `showFileDialog`, `showFolderDialog`)
  - Header: `windows/WindowsLibrary/WindowsDialogManager.h`
  - Docs: Doxygen (`windows/WindowsLibrary/Doxyfile`)

- `windows/UnityWindowsPlugin`
  - Optional integration project is included (currently minimal stub)

## Repository layout

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

## Requirements

- Android: JDK 11 / Android SDK / Android Studio
- iOS / macOS: Xcode
- Windows: Visual Studio 2022 (C++), Doxygen when generating docs

## Build (distributables)

```bash
# Android AAR (all modules)
./scripts/build_android_library_aar.sh -b release -m android_library -m unity_android_plugin -v 1.1.0

# iOS XCFramework (all modules)
./scripts/build_ios_library_xcframework.sh -c release -m IosLibrary -m UnityIosPlugin -v 1.1.0

# macOS XCFramework (all modules)
./scripts/build_xcode26_library_xcframework.sh -c release -m MacLibrary -m UnityMacPlugin -v 1.1.0 --minimum-macos 15.0

# Windows DLL / NuGet
./scripts/build_windows_library_dll.ps1 -c release -m WindowsLibrary -v 1.3.0 -Package
```

## API docs generation

### Android

```bash
cd android/AndroidLibraryExample
./gradlew :android_library:dokkaHtml :unity_android_plugin:dokkaHtml
```

### iOS (DocC)

```bash
cd ios
./generate_docc.sh
```

### macOS (DocC)

```bash
cd mac
./generate_docc.sh
```

### Windows (Doxygen)

```bash
cd windows/WindowsLibrary
doxygen Doxyfile
```

## Docs publish (version / latest)

Publishes to `docs/<version>/`, and refreshes `docs/latest/` from the highest version under `docs/`.

```bash
./scripts/publish_docs.sh 1.6.0
```

Copy only (skip generation):

```bash
./scripts/publish_docs.sh 1.6.0 --skip-build
```

Manual source path is `manual/<version>/`.

## Native integration references

For native integration, start from the core library docs per platform.

- Android: `android/android_library/MODULE.md`
- iOS: `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md`
- macOS: `mac/MacLibrary/MacLibrary/MacLibrary.docc/MacLibrary.md`
- Windows: `windows/WindowsLibrary/WindowsDialogManager.h`

## Unity Native Toolkit (Unity 6)

- A toolkit that provides native platform features for Unity 6 and later.
- The package includes native plugins and sample scenes for Android / iOS / Windows / macOS, and native platform features can be handled through singleton APIs per platform.
- From an Editor window, you can add native libraries and Gradle / Xcode settings to streamline post-build project setup as a workflow.
- Repository: [unity-native-plugin](https://github.com/kimjh4941/unity-native-plugin)

## License

Apache License 2.0. See `LICENSE`.
