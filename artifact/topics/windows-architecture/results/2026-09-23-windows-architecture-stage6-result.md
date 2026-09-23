# 段階 6 結果: NuGet・マニュアル・Doxygen を新しい API に合わせる

- 実施日: 2026-09-23
- 対象: `artifact/topics/windows-architecture/README.md` の段階 6
- ブランチ: `feature/NTKIT-16`
- 前提: 段階 5（`results/2026-09-23-windows-architecture-stage5-result.md`）

## 1. 何をしたか

| 対象 | 内容 |
|---|---|
| NuGet | パッケージを 2 つに分けた。`NativeToolkit`（C++ API の静的ライブラリ）と `NativeToolkit.CApi`（C ABI の DLL）。雛形は `scripts/nuget/NativeToolkit/` と `scripts/nuget/NativeToolkitCApi/` |
| ビルドスクリプト | `scripts/build_windows_library_dll.ps1` が 2 つのモジュールを作り、`-Package` で 2 つのパッケージを出す。リリース版（`-ReleaseVersion`）とライブラリ版（`-LibraryVersion`）を分けた |
| 版番号 | C++ API に `NATIVETOOLKIT_VERSION_*` を足した（`NativeToolkit/BuildStamp.h`）。C ABI の `NTK_VERSION_*` と同じ扱いで、スクリプトが照合する |
| マニュアル | `manual/1.12.0/` を作り、Windows の章 3 つ（dialog / notification / clipboard）× 3 言語を C++ API に書き直した。各章に C ABI の節を足し、index に 1.x からの移行を書いた |
| Doxygen | `windows/WindowsLibrary/Doxyfile` を C++ API と C ABI の公開ヘッダー 2 か所だけに向け、`windows/WindowsLibrary/docs/` を作り直した |
| ルール | `agent-rules/coding-rules/windows.md` に「配布（NuGet / 版番号）」の節を足した |
| README | 3 言語の版番号と Windows の配布物の記述を更新した |

## 2. 決めたこと

| # | 決定 | 理由 |
|---|---|---|
| F-1 | リリース版は **1.12.0**、Windows ライブラリの版は **2.0.0** | これまでも両者は別だった（`dist/1.11.0/android/android-native-toolkit-1.3.0.aar`）。Windows だけの破壊的変更で製品の版を上げない |
| F-2 | NuGet は **2 パッケージ**（利用者の決定） | 利用者は必要な方だけを取れる。静的ライブラリの構成依存（v143 / `/std:c++20` / `/MD`）を C ABI の利用者に押し付けない |
| F-3 | マニュアルは **C++ API を本文、C ABI を節**（利用者の決定） | サンプルアプリが C++ API を使っており、コード例をサンプルと一致させられる。他言語から呼ぶ人向けに C ABI の節と対応表を置く |
| F-4 | C++ API に版番号のマクロを足す | ビルドスクリプトの「版はヘッダーが持つ」規則を C++ API にも適用するため。`NATIVETOOLKIT_ABI_VERSION`（リンク時の照合）とは別物として書いた |
| F-5 | 静的ライブラリのパッケージは **Release と Debug の両方**を入れる | 利用者の Debug ビルドは CRT とイテレーターデバッグレベルが違い、Release 版とはリンクできない |
| F-6 | C++ のパッケージ props が **システムライブラリを足す** | 静的ライブラリは自分のビルド設定を運ばない。3 節の消費テストで実際にリンクが失敗して分かった |
| F-7 | ドキュメントサイト（`docs/<版>/`）の公開は**リリース時に行う** | `publish_docs.sh` は `docs/latest/` も更新する。まだリリースしていない版を latest にしない |

## 3. 確かめたこと

### 3.1 パッケージの中身

`./scripts/build_windows_library_dll.ps1 -c release -v 2.0.0 -r 1.12.0 -Package`

| パッケージ | 中身 |
|---|---|
| `windows-native-toolkit-2.0.0.nupkg`（`NativeToolkit`） | `build/native/NativeToolkit.props`、公開ヘッダー 6 つ（`NativeToolkit/`）、`lib/x64/Release/WindowsLibraryCore.lib`、`lib/x64/Debug/WindowsLibraryCore-Debug.lib`（5 章で `WindowsLibrary.lib` / `WindowsLibrary-Debug.lib` に改名） |
| `windows-native-toolkit-capi-2.0.0.nupkg`（`NativeToolkit.CApi`） | `build/native/NativeToolkit.CApi.props` と `.targets`、公開ヘッダー 4 つ（`NativeToolkitC/`）、`runtimes/win-x64/native/NativeToolkitC.dll` と `.lib` |

どちらも `Microsoft.WindowsAppSDK 1.7.250513003` を依存として宣言している。

### 3.2 消費テスト（利用者側からのビルド）

パッケージを展開し、NuGet が packages.config のプロジェクトに対して行うのと同じ形で props / targets を import する最小のプロジェクトを作って確かめた。

| 確認 | 結果 |
|---|---|
| C++ の利用者（Release / Debug、v143、x64） | どちらも成功。props が include とライブラリを足し、構成に応じて Release / Debug の `.lib` を選ぶ |
| C の利用者（`CompileAsC`、/W4 かつ警告をエラー扱い） | 成功。C99 のヘッダーだけでコンパイルできる |
| C ABI の DLL の配置 | `.targets` が `NativeToolkitC.dll` を出力先に複写した |
| 実行 | `ntk_version()` が `0x00020000` を返し、ヘッダーの `NTK_VERSION` と一致した |

**見つかった不具合（F-6）**: 最初の C++ の利用者ビルドは `WINRT_IMPL_RoGetActivationFactory` と `InitPropVariantFromCLSID` が未解決でリンクに失敗した。静的ライブラリは自分のリンク設定を運ばないため、段階 3 のリンクスパイクで測った一覧（`user32` `advapi32` `shell32` `shlwapi` `ole32` `oleaut32` `propsys` `windowsapp`）をパッケージの props に入れて解決した。`Microsoft.WindowsAppRuntime.Bootstrap.lib` は Windows App SDK のパッケージが自分で足すので、こちらでは足さない。

C ABI の実行ファイルは、最初は `Microsoft.WindowsAppRuntime.Bootstrap.dll` が隣に無く 0xC0000135 で落ちた。これは仕様どおりで（DLL がそれを import している）、隣に置いたら成功した。マニュアルにもその前提を書いてある。

### 3.3 マニュアルの整合（`scripts/verify_manual.sh`）

| 検査 | 1.11.0（前版） | 1.12.0 |
|---|---|---|
| 1 画像参照（停止） | FAIL 30 | FAIL 30（同じ。macOS の通知の画像が前版から欠けている） |
| 2 サンプル整合（警告） | WARN 4 | WARN 2 |
| 3 アンカー（停止） | FAIL 5 | **OK** |
| 4 成果物名（停止） | OK | **OK** |
| 5 文体（警告） | WARN 2 | WARN 2（share の 1 行。前版から） |
| 6 言語差分（警告） | WARN 14 | WARN 14（1 の画像と同じ原因） |
| 7 index 機能一覧（停止） | OK | OK |

停止項目は 1 つだけで、前版から引き継いだ macOS の画像欠けである。今回の作業で作り込んだものではない。アンカーの 5 件は、Windows の目次を作り直すときに合わせて直した（英語版の「Category and Actions」の見出しと目次の不一致を含む）。

### 3.4 Doxygen

`windows/WindowsLibrary/docs/` を作り直した。入力は公開ヘッダーの 2 か所だけで、実装（`src/`）は入らない。C++ API の `NativeToolkit::Clipboard::Session` などのクラスと、C ABI の 4 ヘッダーの関数が両方出ている。

## 4. 残っていること

- **ドキュメントサイトの公開**（`./scripts/publish_docs.sh 1.12.0 --os all`）。`docs/<版>/` と `docs/latest/` を更新する作業で、リリースのときに行う（F-7）
- マニュアルの macOS の通知の画像 30 件（前版からの引き継ぎ）
- 段階 7: CI（ユニットテストのみ）

## 5. 追補: プロジェクトと成果物を `WindowsLibrary` に戻した（2026-09-23）

段階 6 のコミットの後、利用者の決定でプロジェクト名と成果物名を `WindowsLibraryCore` から `WindowsLibrary` に戻した。フォルダーを改名しないという E-11 の決定はそのままなので、結果としてフォルダー・プロジェクト・`.lib`・`.props` がすべて `WindowsLibrary` でそろう。

| 項目 | 前 | 後 |
|---|---|---|
| プロジェクト | `WindowsLibraryCore.vcxproj` | `WindowsLibrary.vcxproj` |
| 静的ライブラリ | `WindowsLibraryCore.lib` / `WindowsLibraryCore-Debug.lib` | `WindowsLibrary.lib` / `WindowsLibrary-Debug.lib` |
| 利用者向け props | `build/NativeToolkit.WindowsLibraryCore.props`（と `.targets`） | `build/NativeToolkit.WindowsLibrary.props`（と `.targets`） |
| ビルドスクリプトのモジュール名 | `-m WindowsLibraryCore` | `-m WindowsLibrary` |

`Core` を付けたのは段階 3 で、当時は同じフォルダーに 1.x の C ABI の `WindowsLibrary.vcxproj` があり名前が衝突したためである。その理由は段階 5 の T-12（プロジェクトごと削除）で消えていた。

併せて直したもの:

- `WindowsLibraryExample.sln` に、T-12 で削除した 1.x プロジェクトの項目（GUID `44A5717A-BB61-08F5-6279-98AD08C8E2F7`）が残っていた。存在しないファイルを指していたが、今回の改名でそれが新しいプロジェクトに解決し、同じプロジェクトが 2 つの GUID で登録される状態になるため、項目と構成の 12 行を取り除いた
- NuGet パッケージ `NativeToolkit` がリンクさせる名前が変わるので、パッケージと `dist/1.12.0/windows/` を作り直した。1.12.0 は未リリースなので外部への影響は無い

確認:

| 確認 | 結果 |
|---|---|
| `WindowsLibrary.sln` と `WindowsLibraryExample.sln` のビルド（Release / x64） | どちらも成功 |
| ユニットテスト（`WindowsLibraryTest` + `WindowsLibraryCApiTest`） | 404 件、失敗 0 |
| パッケージの中身 | `build/native/lib/x64/{Release/WindowsLibrary.lib, Debug/WindowsLibrary-Debug.lib}`。props も同じ名前を参照する |
| 消費テスト（3.2 と同じ手順を再実行） | C++ は Release / Debug とも成功、C は成功して `ntk_version()` が `0x00020000` |
