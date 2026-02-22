# native-toolkit

A cross-platform toolkit that bundles native dialog and file picker utilities for native apps.

- Android: `DialogFragment`-based native API
- iOS: `UIAlertController`-based native API
- macOS: `NSAlert` / `NSOpenPanel` / `NSSavePanel`-based native API
- Windows: Win32 common dialogs exposed as C-style APIs

> Goal: make it easy for native apps to present each OS's standard UI with a consistent calling pattern.

Other languages:

- Korean: [README.ko.md](README.ko.md)
- Japanese: [README.ja.md](README.ja.md)

---

## Quick start

1. If you use prebuilt artifacts, pick files from `dist/<version>/`.
2. For integration steps, read `docs/<version>/manual/index.md`.
3. For API references, use `docs/<version>/` (or `docs/latest/`).

Example (`1.0.0`):

- Manual: `docs/1.0.0/manual/index.md`
- Published docs: `docs/1.0.0/manual/`

## Detailed Documentation

- Latest (English): [docs/latest/manual/index.md](docs/latest/manual/index.md)
- Latest (Korean): [docs/latest/manual/index.ko.md](docs/latest/manual/index.ko.md)
- Latest (Japanese): [docs/latest/manual/index.ja.md](docs/latest/manual/index.ja.md)

## Version

- Current release: 1.0.0
- Latest published docs version: [docs/latest/VERSION.txt](docs/latest/VERSION.txt)

---

## Supported OS (1.0.0)

- Android 12+
- iOS 18+
- Windows 11+
- macOS 15+

---

## Distributables (1.0.0)

- Android: `dist/1.0.0/android/native-toolkit-1.0.0.aar`
- iOS: `dist/1.0.0/ios/NativeToolkit-1.0.0.xcframework`
- macOS:
  - `dist/1.0.0/mac/NativeToolkit-1.0.0-xcode16.xcframework`
  - `dist/1.0.0/mac/NativeToolkit-1.0.0-xcode26.xcframework`
- Windows: `dist/1.0.0/windows/nuget/NativeToolkit/NativeToolkit.1.0.0.nupkg`

---

## Modules (overview)

### Android

- `android/android_library`
  - Core: `AndroidDialogFragment`
  - Variants: Simple / Confirm / Single Choice / Multi Choice / Text Input / Login
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

---

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

---

## Requirements

- Android: JDK 11 / Android SDK / Android Studio
- iOS / macOS: Xcode
- Windows: Visual Studio 2022 (C++), Doxygen when generating docs

---

## Build (distributables)

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

## API docs generation

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

## Docs publish (version / latest)

Publishes to `docs/<version>/`, and refreshes `docs/latest/` from the highest version under `docs/`.

```bash
./scripts/publish_docs.sh 1.0.0
```

Copy only (skip generation):

```bash
./scripts/publish_docs.sh 1.0.0 --skip-build
```

Manual source path is `manual/<version>/`.

---

## Native integration references

For native integration, start from the core library docs per platform.

- Android: `android/android_library/MODULE.md`
- iOS: `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md`
- macOS: `mac/MacLibrary/MacLibrary/MacLibrary.docc/MacLibrary.md`
- Windows: `windows/WindowsLibrary/WindowsDialogManager.h`

---

## License

Apache License 2.0. See `LICENSE`.
