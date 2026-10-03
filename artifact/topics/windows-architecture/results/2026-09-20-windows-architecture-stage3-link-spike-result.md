# 段階 3 T-03: ビルドのスパイク（ブロッキング）

- 日付: 2026-09-20
- 対象タスク: 設計書 `designs/2026-09-20-windows-architecture-cpp-api-design.md` の T-03
- 目的: 設計書 7.5 の配布構成（`/MT` の可否、伝播するライブラリ、`WINRT_*` のマクロ）を**実測で確定させる**
- 環境: Visual Studio 2022 Community、MSVC 14.44.35207、Windows App SDK 1.7.250513003、C++/WinRT 2.0.250303.1、x64

## 1. 結論

| 確かめたこと | 結果 |
|---|---|
| **`/MT`（静的 CRT）で使えるか**（RK-08） | **使える**。コンパイル・リンク・実行のすべてを確認 |
| 配布する `.lib` の種類 | **x64 の Debug / Release × `/MD` / `/MT` の 4 種で確定**。案 B（`/MD` のみ）や案 C（ソース配布）への退避は不要 |
| 伝播するライブラリ | 1.2 のとおり。**Windows App SDK の `.lib` は NuGet の中にしか無い** |
| `detect_mismatch` の有効性 | **不一致を検出できることを実証**（1.4） |

設計書 7.5 の「T-03 の結果で確定する」という留保は外れた。

## 1.1 実験の方法

素の `cl` で最小の利用者（コンソール exe）をコアにリンクした。利用者のソースは `DLog` を呼ぶだけにし、**`/WHOLEARCHIVE` でコアの全オブジェクトを強制的に取り込む**ことで、利用者のコードが何を include するかに依存せず、コアが持つ外部依存の全量を未解決シンボルとして得た。

通知の内部ヘッダーは C++/WinRT の射影ヘッダー（プロジェクトのビルド時に生成される）を要求するため、利用者のソースから include する方法では再現できない。`/WHOLEARCHIVE` はこの制約を回避しつつ、リンク時の依存を正確に測れる。

## 1.2 伝播するライブラリ（設計書 G-3 / RK-05 の答え）

未解決シンボルは 39 種。次の指定ですべて解決した。

| ライブラリ | 解決するシンボルの例 |
|---|---|
| `user32.lib` | `OpenClipboard`、`SetClipboardData`、`AddClipboardFormatListener`、`CreateWindowExW`、`PostMessageW`、`GetForegroundWindow` |
| `advapi32.lib` | `OpenProcessToken`、`GetTokenInformation`、`RegCreateKeyExW`、`RegSetValueExW` |
| `shell32.lib` | `DragQueryFileW`、`SHGetSpecialFolderPathW` |
| `shlwapi.lib` / `ole32.lib` / `oleaut32.lib` | COM とダイアログの経路 |
| `propsys.lib` | `InitPropVariantFromCLSID` |
| `windowsapp.lib` | C++/WinRT のランタイム（`WINRT_IMPL_RoGetActivationFactory`、`WINRT_IMPL_SysFreeString` ほか） |
| **`Microsoft.WindowsAppRuntime.Bootstrap.lib`** | `MddBootstrapInitialize` |

最後の 1 つは NuGet パッケージの中にあり、パスは `packages\Microsoft.WindowsAppSDK.1.7.250513003\lib\**win10-x64**\` である（`win-x64` ではない）。**DLL 配布ではこれらは内側に隠れていた**。静的ライブラリを配る以上、この一覧を `.props` / `.targets` で供給しないと、利用者は自力でこのパスを見つけることになる。

## 1.3 作ったもの

| ファイル | 内容 |
|---|---|
| `windows/WindowsLibrary/build/NativeToolkit.WindowsLibraryCore.props` | include パス（公開ヘッダー + Windows App SDK）と 1.2 のライブラリを供給する。利用者の `RuntimeLibrary` から `/MD` か `/MT` かを自動で判定する |
| `windows/WindowsLibrary/build/NativeToolkit.WindowsLibraryCore.targets` | 4 種の `.lib` から構成に合うものを選ぶ。x64 以外と `.lib` 不在はビルド前にエラー、`/GL` 有効時は警告 |
| `windows/WindowsLibrary/src/Common/BuildStamp.h` | `#pragma detect_mismatch` でヘッダーの版と C++/WinRT のマクロ設定を記録する |

段階 6 の NuGet パッケージは、この骨組みをそのまま使う。

## 1.4 `detect_mismatch` を壊して確認した

MSVC は `RuntimeLibrary` と `_ITERATOR_DEBUG_LEVEL` しか記録しないため、ヘッダーの版と C++/WinRT のマクロ設定は自前で記録した。検査が生きていることを、**通る確認だけでなく壊す確認**で示した。

| 条件 | 結果 |
|---|---|
| 利用者とライブラリの設定が一致 | リンク成功 |
| 利用者だけが `WINRT_NO_MODULE_LOCK` を定義 | **`LNK2038: 'nativetoolkit_winrt_module_lock' の不一致が検出されました。値 'default' が none の値 'consumer.obj' と一致しません。`** |

## 2. コアの設定の変更

| 変更 | 理由 |
|---|---|
| `WINDOWSLIBRARY_EXPORTS` を Core の 4 構成から除去 | export マクロは DLL 側だけが定義する（設計書 7.6.1） |
| `WholeProgramOptimization`（`/GL`）を Release 2 構成で無効化 | 配る `.lib` では `/GL` を使わない（D-3）。利用者のコンパイラの版に縛られるため |
| `/p:NtkCrt=MT` で CRT を切り替えられる条件を追加（8 か所） | 構成を 4 つに増やさずに `/MT` を検証できる。配布の 4 種もこの仕組みで作る |

## 3. 見つかった欠陥

**`WindowsDialogManagerInternal.h` が `<commdlg.h>` を includer 任せにしていた。** 分割前は `.cpp` が `windows.h` 経由で取り込んでいたため表に出なかったが、内部ヘッダーとして切り出した時点で単独では使えない状態になっていた。`#include <commdlg.h>` を足して修正した。

**設計書への申し送り**: U-D（ヘッダーの単独 include の検査）は `include/NativeToolkit/` の 5 つだけを対象にしているが、**`src/**/*Internal.h` にも同じ問題が起きる**。T-04 で U-D の対象を内部ヘッダーへ広げる。

## 4. 残っている項目

| 項目 | 扱い |
|---|---|
| ARM64 | 配らない。パッケージに ARM64 対応と書かない（設計書 7.5.1 のまま） |
| `.props` / `.targets` をサンプルで検証する | 段階 4 でサンプルを Core に直接リンクするときに行う |
| 4 種の `.lib` を実際に並べて配る | 段階 6 の NuGet パッケージの作業 |
| 配置レシピの項目が 15 → 16 に増えた（`WindowsLibraryCore.lib` が出力先に出る） | AppX レイアウトには入らないので動作に影響なし。段階 6 で出力先を分けるか判断する |

## 5. UI テストの不安定さについて（この作業で分かったこと）

T-03 の検証中、UI テストが 3 回にわたり失敗した。**いずれも環境起因**で、コードの問題ではなかった。

| 実行 | 失敗したテスト | 所要 |
|---|---|---|
| 1 回目 | `ClipboardExternalChangeTests.ReservedFormat_IsRenderedOnlyWhenAnotherProgramPastes`、`NotificationTests.ShowWithButtons_PressingOpen_DeliversItsArguments` | 37 分 |
| 2 回目（2 件だけ） | `ReservedFormat_...` | 2 分 |
| 3 回目 | `DialogTests.Alert_Ok_ReturnsIdOk`（それまで一度も落ちていない） | 34 分 |
| PC を再起動した後 | **無し（200 件すべて baseline と一致）** | **9 分** |

**毎回違うテストが落ち、単独で走らせると通り、再起動後は 9 分で全件通った。** 所要時間が通常（9〜24 分）の 3〜4 倍に伸びていたことから、原因はマシンの負荷である。

**この経験から得た手順上の教訓**:

- UI テストの失敗を見たら、**まず所要時間を見る**。通常より大幅に長い場合は環境を疑う
- 失敗したテストだけを再実行して判断しない。**同じテストが他の実行で通っているかを確認する**
- 1〜2 回の一致で因果を結論づけない。この作業では「`/GL` の無効化が原因」と一度誤って結論づけ、`/GL` を無効のまま 3 回成功したことで否定された
- 全実行の最中は PC を操作しない。UI テストはデスクトップとクリップボードを占有する
