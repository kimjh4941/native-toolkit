# native-toolkit

Unity などのアプリから利用できる「ネイティブのダイアログ／ファイル選択」系ユーティリティを、各プラットフォーム別にまとめたツールキットです。

- Android: `DialogFragment` ベースの汎用ダイアログ + Unity 向け JNI ブリッジ
- iOS: `UIAlertController` ベースのダイアログ + Unity 向け C ABI ブリッジ
- macOS: `NSAlert` / `NSOpenPanel` / `NSSavePanel` ベースのダイアログ/ファイルパネル + Unity 向け C ブリッジ
- Windows: Win32 共通ダイアログの C 形式 API（例: MessageBox / GetOpenFileName 等）

> 目的: ゲーム/ツール側（特に Unity）から、各 OS の標準 UI を統一した“呼び方”で使えるようにする。

---

## 収録モジュール（概要）

### Android

- `android/android_library`

  - 中核: 多パターンの `AndroidDialogFragment`（6 種類のダイアログを `newInstance(...)` オーバーロードで生成）
  - 対応: Simple / Confirm / Single Choice / Multi Choice / Text Input / Login
  - Doc: Dokka（`MODULE.md` を includes して API 概要も生成）

- `android/unity_android_plugin`
  - Unity 向け: `UnityAndroidDialogManager`（Java/Kotlin 側） + C# ラッパ `AndroidDialogManager`
  - Java の結果を Unity メインスレッドへディスパッチする設計（`UnityMainThreadDispatcher` 前提）
  - Doc: Dokka（`MODULE.md` 収録）

### iOS

- `ios/IosLibrary`

  - 中核: `IosDialogManager`（`UIAlertController` パターンを統一したコールバック形式で提供）
  - 対応: Alert / Confirm / Destructive / ActionSheet / TextInput / Login
  - Doc: DocC（`.docc`）

- `ios/UnityIosPlugin`
  - Unity 向け: Swift ファサード `UnityIosDialogManager` + Objective-C/C ブリッジ（C ABI）
  - Unity 側は `DllImport("__Internal")` の P/Invoke で呼び出す想定
  - Doc: DocC（`.docc`）

### macOS

- `mac/MacLibrary`

  - 中核: `MacDialogManager`（`NSAlert`/`NSOpenPanel`/`NSSavePanel` を `Result` で統一）
  - 対応: Alert / File / MultiFile / Folder / MultiFolder / Save
  - Doc: DocC（`.docc`）

- `mac/UnityMacPlugin`
  - Unity 向け: Swift + ObjC/C ブリッジ + C# ラッパ（JSON を介した Alert 設定など）
  - Doc: DocC（`.docc`）

### Windows

- `windows/WindowsLibrary`

  - C 形式エクスポート API（例: `showAlertDialog`, `showFileDialog`, `showFolderDialog` など）
  - ヘッダ: `windows/WindowsLibrary/WindowsDialogManager.h`
  - Doc: Doxygen（`windows/WindowsLibrary/Doxyfile`）

- `windows/UnityWindowsPlugin`
  - Unity 向けプラグイン用のソリューション/プロジェクトが同梱
  - 現時点の `UnityWindowsDialogManager` は最小スタブのため、WindowsLibrary の機能を Unity へ橋渡しする実装はこれから追加する想定

---

## リポジトリ構成

```
android/
	android_library/            # Android コアダイアログ
	unity_android_plugin/        # Unity 向け Android ブリッジ
	AndroidLibraryExample/       # サンプルアプリ/ビルド用ラッパ

ios/
	IosLibrary/                  # iOS コアダイアログ
	UnityIosPlugin/              # Unity 向け iOS ブリッジ
	IosLibraryExample/           # サンプル
	generate_docc.sh             # DocC 生成

mac/
	MacLibrary/                  # macOS コアダイアログ/ファイルパネル
	UnityMacPlugin/              # Unity 向け macOS ブリッジ
	MacLibraryExample/           # サンプル
	generate_docc.sh             # DocC 生成

windows/
	WindowsLibrary/              # Windows コア（Win32 共通ダイアログ）
	UnityWindowsPlugin/          # Unity 向け（現状は最小スタブ）
	WindowsLibraryExample/       # サンプル
```

---

## 必要環境

- Android

  - JDK 11
  - Android SDK / Android Studio
  - Gradle Wrapper（同梱）

- iOS / macOS

  - Xcode（DocC 生成に `xcrun docc` を使用）

- Windows
  - Visual Studio 2022（C++）
  - （Doc 生成する場合）Doxygen

---

## ビルド & ドキュメント生成

### Android

Android のビルドは `android/AndroidLibraryExample` がワークスペース役（2 つのモジュールを include）になっています。

```bash
cd android/AndroidLibraryExample

# 例: Android コアライブラリ
./gradlew :android_library:assembleRelease

# 例: Unity 向け Android ブリッジ（android_library に依存）
./gradlew :unity_android_plugin:assembleRelease
```

#### Android API ドキュメント（Dokka）

```bash
cd android/AndroidLibraryExample

./gradlew :android_library:dokkaHtml
./gradlew :unity_android_plugin:dokkaHtml
```

出力先:

- `android/android_library/build/dokka/html`
- `android/unity_android_plugin/build/dokka/html`

#### Android 仕様メモ

- `android/android_library/build.gradle.kts`
  - `compileSdk = 35`, `minSdk = 31`, JVM target 11

---

### iOS

#### Xcode で開く

- ワークスペース: `ios/IosWorkspace.xcworkspace`
- スキーム: `IosLibrary`, `UnityIosPlugin`

#### iOS API ドキュメント（DocC）

```bash
cd ios
./generate_docc.sh
```

出力先:

- `ios/Docs/IosLibrary`
- `ios/Docs/UnityIosPlugin`

> 注: `ios/generate_docc.sh` は環境によってパスが固定になっている場合があります。必要に応じてリポジトリルート相対に調整してください。

---

### macOS

#### Xcode で開く

- ワークスペース: `mac/MacWorkspace.xcworkspace`
- スキーム: `MacLibrary`, `UnityMacPlugin`

#### macOS API ドキュメント（DocC）

```bash
cd mac
./generate_docc.sh
```

出力先:

- `mac/Docs/MacLibrary`
- `mac/Docs/UnityMacPlugin`

> 注: `mac/generate_docc.sh` は環境によってパスが固定になっている場合があります。必要に応じてリポジトリルート相対に調整してください。

---

### Windows

#### Visual Studio でビルド

- `windows/WindowsLibrary/WindowsLibrary.sln`
- `windows/WindowsLibraryExample/WindowsLibraryExample.sln`

ビルド構成は `Debug/Release` と `x86/x64` を想定しています。

#### Windows API ドキュメント（Doxygen）

`windows/WindowsLibrary/Doxyfile` により生成します。

```bash
cd windows/WindowsLibrary
doxygen Doxyfile
```

出力先（設定値）:

- `windows/WindowsLibrary/docs`

---

## Unity 連携メモ（最小）

プラットフォーム別の Unity 連携は「Unity 向けモジュール」を起点に確認してください。

- Android: `android/unity_android_plugin/MODULE.md`

  - Java/Kotlin 側の `UnityAndroidDialogManager` と C# の `AndroidDialogManager` を前提

- iOS: `ios/UnityIosPlugin/UnityIosPlugin/UnityIosPlugin.docc/UnityIosPlugin.md`

  - C ABI のブリッジ関数を `DllImport("__Internal")` で呼ぶ想定

- macOS: `mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.docc/UnityMacPlugin.md`

  - JSON スキーマ（alert の buttons/options）や各ダイアログの戻り値キーが整理済み

- Windows: `windows/WindowsLibrary/WindowsDialogManager.h`
  - Unity 向けの橋渡しは `windows/UnityWindowsPlugin` に追加していく想定（現状スタブ）

---

## ライセンス

Apache License 2.0（詳細は `LICENSE` を参照）。
