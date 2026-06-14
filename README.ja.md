# native-toolkit

ネイティブアプリから利用できる、クロスプラットフォームのネイティブ機能ツールキットです。

- Android: `DialogFragment` + 通知ベースのネイティブ API
- iOS: `UIAlertController` ベースのネイティブ API
- macOS: `NSAlert` / `NSOpenPanel` / `NSSavePanel` ベースのネイティブ API
- Windows: Win32 共通ダイアログおよびトースト通知の C 形式 API

> 目的: ネイティブアプリから、各 OS の標準機能を一貫した呼び方で利用できるようにする。

他言語 README:

- English: [README.md](README.md)
- Korean: [README.ko.md](README.ko.md)

## はじめに（最短）

1. 配布物を使う場合は、`dist/<version>/` から対象 OS の成果物を取得。
2. 組み込み手順は `docs/<version>/manual/index.ja.md` を参照。
3. API 仕様は `docs/<version>/`（または `docs/latest/`）の各プラットフォーム資料を参照。

例（`1.4.0`）:

- マニュアル: `docs/1.4.0/manual/index.ja.md`
- 公開ドキュメント: `docs/1.4.0/manual/`

## 詳細ドキュメント

- 最新版（日本語）: [docs/latest/manual/index.ja.md](docs/latest/manual/index.ja.md)
- 最新版（English）: [docs/latest/manual/index.md](docs/latest/manual/index.md)
- 最新版（한국어）: [docs/latest/manual/index.ko.md](docs/latest/manual/index.ko.md)

## バージョン

- 現在のリリース: 1.4.0
- 最新公開ドキュメントのバージョン: [docs/latest/VERSION.txt](docs/latest/VERSION.txt)

## 対応 OS（1.4.0）

- Android 12 以降
- iOS 18 以降
- Windows 11 以降
- macOS 15 以降

## 配布物（1.4.0）

- Android: `dist/1.4.0/android/android-native-toolkit-1.1.0.aar`
- iOS:
  - `dist/1.4.0/ios/ios-native-toolkit-1.1.0.xcframework`
  - `dist/1.4.0/ios/unity-ios-native-toolkit-1.1.0.xcframework`
- macOS:
  - `dist/1.4.0/mac/mac-native-toolkit-1.1.0.xcframework`
  - `dist/1.4.0/mac/unity-mac-native-toolkit-1.1.0.xcframework`
- Windows: `dist/1.4.0/windows/windows-native-toolkit-1.1.0.nupkg`

## 収録モジュール（概要）

### Android

- `android/android_library`
  - 中核: `AndroidDialogFragment` / Android 通知 API
  - 対応: Simple / Confirm / Single Choice / Multi Choice / Text Input / Login / Notification
  - Doc: Dokka

- `android/unity_android_plugin`
  - 補助モジュール: C ABI / JNI ブリッジ層
  - Doc: Dokka

### iOS

- `ios/IosLibrary`
  - 中核: `IosDialogManager`
  - 対応: Alert / Confirm / Destructive / ActionSheet / TextInput / Login
  - Doc: DocC

- `ios/UnityIosPlugin`
  - 補助モジュール: Swift + Objective-C/C ブリッジ（C ABI）
  - Doc: DocC

### macOS

- `mac/MacLibrary`
  - 中核: `MacDialogManager`
  - 対応: Alert / File / MultiFile / Folder / MultiFolder / Save
  - Doc: DocC

- `mac/UnityMacPlugin`
  - 補助モジュール: Swift + ObjC/C ブリッジ
  - Doc: DocC

### Windows

- `windows/WindowsLibrary`
  - C 形式 API（例: `showAlertDialog`, `showFileDialog`, `showFolderDialog`）
  - ヘッダ: `windows/WindowsLibrary/WindowsDialogManager.h`
  - Doc: Doxygen

- `windows/UnityWindowsPlugin`
  - 補助モジュール: プラグイン連携用プロジェクト（現状は最小スタブ）

## リポジトリ構成

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

## 必要環境

- Android: JDK 11 / Android SDK / Android Studio
- iOS / macOS: Xcode
- Windows: Visual Studio 2022（C++）、必要に応じて Doxygen

## ビルド（配布物作成）

```bash
# Android AAR（全モジュール）
./scripts/build_android_library_aar.sh -b release -m android_library -m unity_android_plugin -v 1.1.0

# iOS XCFramework（全モジュール）
./scripts/build_ios_library_xcframework.sh -c release -m IosLibrary -m UnityIosPlugin -v 1.1.0

# macOS XCFramework（全モジュール）
./scripts/build_xcode26_library_xcframework.sh -c release -m MacLibrary -m UnityMacPlugin -v 1.1.0 --minimum-macos 15.0

# Windows DLL / NuGet
./scripts/build_windows_library_dll.ps1 -c release -m WindowsLibrary -v 1.3.0 -Package
```

## API ドキュメント生成

- Android (Dokka)

```bash
cd android/AndroidLibraryExample
./gradlew :android_library:dokkaHtml :unity_android_plugin:dokkaHtml
```

- iOS (DocC)

```bash
cd ios
./generate_docc.sh
```

- macOS (DocC)

```bash
cd mac
./generate_docc.sh
```

- Windows (Doxygen)

```bash
cd windows/WindowsLibrary
doxygen Doxyfile
```

## ドキュメント公開（version / latest）

`docs/<version>/` を作成し、`docs/latest/` は `docs/` 配下の最大バージョンで更新されます。

```bash
./scripts/publish_docs.sh 1.3.0
```

既存の生成物をコピーだけする場合:

```bash
./scripts/publish_docs.sh 1.3.0 --skip-build
```

manual のコピー元は `manual/<version>/` です。

## Native 連携の参照先

- Android: `android/android_library/MODULE.md`
- iOS: `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md`
- macOS: `mac/MacLibrary/MacLibrary/MacLibrary.docc/MacLibrary.md`
- Windows: `windows/WindowsLibrary/WindowsDialogManager.h`

## Unity Native Toolkit (Unity 6)

- Unity 6 以降でネイティブ機能を提供するツールキットです。
- パッケージには Android / iOS / Windows / macOS 向けのネイティブプラグインとサンプルシーンが含まれ、各プラットフォームのネイティブ機能をシングルトン API で扱えます。
- Editor 用ウィンドウからネイティブライブラリや Gradle / Xcode 設定を追加でき、ビルド後のプロジェクト整備をワークフロー化できます。
- Repository: [unity-native-plugin](https://github.com/kimjh4941/unity-native-plugin)

## ライセンス

Apache License 2.0（詳細は `LICENSE`）。
