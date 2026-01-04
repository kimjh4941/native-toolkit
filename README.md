# native-toolkit

A cross-platform toolkit that bundles native dialog and file picker utilities for use from apps (especially Unity).

- Android: `DialogFragment`-based dialogs + Unity JNI bridge
- iOS: `UIAlertController`-based dialogs + Unity C ABI bridge
- macOS: `NSAlert` / `NSOpenPanel` / `NSSavePanel` dialogs + Unity C bridge
- Windows: Win32 common dialogs exposed as C-style APIs

> Goal: make it easy for a game/tool (especially Unity) to present each OS's standard UI with a consistent calling pattern.

Other languages:

- Korean: [README.ko.md](README.ko.md)
- Japanese: [README.ja.md](README.ja.md)

---

## Modules (high level)

### Android

- `android/android_library`

  - Core: multi-variant `AndroidDialogFragment` (6 dialog types via `newInstance(...)` overloads)
  - Variants: Simple / Confirm / Single Choice / Multi Choice / Text Input / Login
  - Docs: Dokka (includes `MODULE.md`)

- `android/unity_android_plugin`
  - Unity-facing: `UnityAndroidDialogManager` (Java/Kotlin) + C# wrapper `AndroidDialogManager`
  - Dispatches results onto Unity main thread (`UnityMainThreadDispatcher` expected)
  - Docs: Dokka (includes `MODULE.md`)

### iOS

- `ios/IosLibrary`

  - Core: `IosDialogManager` (wraps `UIAlertController` patterns behind a unified callback model)
  - Variants: Alert / Confirm / Destructive / ActionSheet / TextInput / Login
  - Docs: DocC (`.docc`)

- `ios/UnityIosPlugin`
  - Unity-facing: Swift facade `UnityIosDialogManager` + Objective-C/C bridge (stable C ABI)
  - Unity calls via P/Invoke: `DllImport("__Internal")`
  - Docs: DocC (`.docc`)

### macOS

- `mac/MacLibrary`

  - Core: `MacDialogManager` (unifies `NSAlert` / `NSOpenPanel` / `NSSavePanel` using `Result`)
  - Variants: Alert / File / MultiFile / Folder / MultiFolder / Save
  - Docs: DocC (`.docc`)

- `mac/UnityMacPlugin`
  - Unity-facing: Swift + ObjC/C bridge + C# wrapper (e.g., JSON-based alert configuration)
  - Docs: DocC (`.docc`)

### Windows

- `windows/WindowsLibrary`

  - C-exported APIs (e.g., `showAlertDialog`, `showFileDialog`, `showFolderDialog`, ...)
  - Header: `windows/WindowsLibrary/WindowsDialogManager.h`
  - Docs: Doxygen (`windows/WindowsLibrary/Doxyfile`)

- `windows/UnityWindowsPlugin`
  - Unity plugin solution/project is included
  - `UnityWindowsDialogManager` is currently a minimal stub; bridging WindowsLibrary to Unity is expected to be added later

---

## Repository layout

```
android/
  android_library/             # Android core dialogs
  unity_android_plugin/         # Unity-facing Android bridge
  AndroidLibraryExample/        # sample app / build wrapper

ios/
  IosLibrary/                   # iOS core dialogs
  UnityIosPlugin/               # Unity-facing iOS bridge
  IosLibraryExample/            # sample
  generate_docc.sh              # DocC generation

mac/
  MacLibrary/                   # macOS core dialogs / file panels
  UnityMacPlugin/               # Unity-facing macOS bridge
  MacLibraryExample/            # sample
  generate_docc.sh              # DocC generation

windows/
  WindowsLibrary/               # Windows core (Win32 common dialogs)
  UnityWindowsPlugin/           # Unity-facing (currently minimal stub)
  WindowsLibraryExample/        # sample
```

---

## Requirements

- Android

  - JDK 11
  - Android SDK / Android Studio
  - Gradle Wrapper (included)

- iOS / macOS

  - Xcode (DocC uses `xcrun docc`)

- Windows
  - Visual Studio 2022 (C++)
  - Doxygen (for generating docs)

---

## Build & docs

### Android

Android builds are driven from `android/AndroidLibraryExample`, which includes the two modules.

```bash
cd android/AndroidLibraryExample

# Example: Android core library
./gradlew :android_library:assembleRelease

# Example: Unity-facing Android bridge (depends on android_library)
./gradlew :unity_android_plugin:assembleRelease
```

#### Android API docs (Dokka)

```bash
cd android/AndroidLibraryExample

./gradlew :android_library:dokkaHtml
./gradlew :unity_android_plugin:dokkaHtml
```

Output:

- `android/android_library/build/dokka/html`
- `android/unity_android_plugin/build/dokka/html`

#### Android notes

- `android/android_library/build.gradle.kts`
  - `compileSdk = 35`, `minSdk = 31`, JVM target 11

---

### iOS

#### Open in Xcode

- Workspace: `ios/IosWorkspace.xcworkspace`
- Schemes: `IosLibrary`, `UnityIosPlugin`

#### iOS API docs (DocC)

```bash
cd ios
./generate_docc.sh
```

Output:

- `ios/Docs/IosLibrary`
- `ios/Docs/UnityIosPlugin`

> Note: `ios/generate_docc.sh` may contain machine-specific absolute paths. If so, adjust it to use repository-relative paths.

---

### macOS

#### Open in Xcode

- Workspace: `mac/MacWorkspace.xcworkspace`
- Schemes: `MacLibrary`, `UnityMacPlugin`

#### macOS API docs (DocC)

```bash
cd mac
./generate_docc.sh
```

Output:

- `mac/Docs/MacLibrary`
- `mac/Docs/UnityMacPlugin`

> Note: `mac/generate_docc.sh` may contain machine-specific absolute paths. If so, adjust it to use repository-relative paths.

---

### Windows

#### Build in Visual Studio

- `windows/WindowsLibrary/WindowsLibrary.sln`
- `windows/WindowsLibraryExample/WindowsLibraryExample.sln`

Build configurations assume `Debug/Release` and `x86/x64`.

#### Windows API docs (Doxygen)

Generate using `windows/WindowsLibrary/Doxyfile`.

```bash
cd windows/WindowsLibrary
doxygen Doxyfile
```

Output (as configured):

- `windows/WindowsLibrary/docs`

---

## Unity integration (minimal pointers)

For Unity integration, start from the Unity-facing module docs per platform.

- Android: `android/unity_android_plugin/MODULE.md`

  - Assumes `UnityAndroidDialogManager` (Java/Kotlin) + `AndroidDialogManager` (C#)

- iOS: `ios/UnityIosPlugin/UnityIosPlugin/UnityIosPlugin.docc/UnityIosPlugin.md`

  - Calls C ABI bridge functions via `DllImport("__Internal")`

- macOS: `mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.docc/UnityMacPlugin.md`

  - Documents JSON schema (alert buttons/options) and result dictionary keys

- Windows: `windows/WindowsLibrary/WindowsDialogManager.h`
  - Unity bridge is expected to be implemented in `windows/UnityWindowsPlugin` (currently stub)

---

## License

Apache License 2.0. See `LICENSE`.
