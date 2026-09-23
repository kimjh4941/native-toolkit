# 段階 4 結果: サンプルの C++ API への移行

- 実施日: 2026-09-21
- 対象: `artifact/topics/windows-architecture/README.md` の段階 4
- ブランチ: `feature/NTKIT-16`
- 設計書: 書かない（README 5.1）。段階 3 の設計書（`designs/2026-09-20-windows-architecture-cpp-api-design.md`）に従う

## 1. 方針

- **表示する文字列は変えない。** UI テストは結果の行の断片（`errorCode=N`、`ShowAlertDialog Result: 1` など）で判定している。C++ API のエラーの値は C ABI の定数と同じ数なので（段階 3 の DoD）、`errorCode=N` はそのまま出せる
- **C ABI にしかない動作は、サンプルで真似しない。** そうした動作を確かめていた UI テストは、C++ API での対応する動作に置き換える（2026-09-21 に利用者が決定）。C ABI の動作は `WindowsLibraryTest` のブリッジのテストが押さえている
- **サンプルは公開ヘッダーだけを使う。** `src` の内部ヘッダー（`Common/common.h`）への依存をやめた
- 1 画面ずつ移し、その画面の UI テストを流してからコミットした。移行中は DLL と Core の両方を参照した（機能ごとに移すため、状態はぶつからない）

## 2. 変更したこと

| 対象 | 変更 |
|---|---|
| `DialogPage` | 6 つの操作を `Dialog::Show*` にした。アラートの答えは MessageBox の ID（`IDOK` = 1）に戻して表示する |
| `NotificationPage` | プロセスで 1 つの `Notification::Manager` を持つ。JSON の文字列ではなく `NotificationContent` を組み立てる。起動時の引数は `ActivationArgs::rawArguments` を表示する（C のコールバックが受け取っていた文字列と同じ） |
| `ClipboardPage` | プロセスで 1 つの `Clipboard::Session` を持つ。2 回呼ぶバッファの取得は無くなり、値を受け取る。複数形式は `FormatPayload` の配列にした。ファイル、形式の一覧、履歴は、画面が JSON にして表示する（結果の行の見た目を変えないため）。遅延描画の provider は 1 回の呼び出しでバイト列を返すので、ログは `phase=fill` の行だけになった |
| `SampleLog.h`（新規） | `DLog` / `DFLog`。内部ヘッダーの `Common/common.h` の代わり |
| `WindowsLibraryExample.vcxproj` | 参照先を `WindowsLibrary`（DLL）から `WindowsLibraryCore`（静的ライブラリ）に替えた。インクルードのパスは `..\WindowsLibrary\include` だけにした（`src` を外した） |
| Core の `#pragma comment(lib, ...)` | `comdlg32.lib`（`WindowsDialogWin32.h`）と `shell32.lib`（`WindowsClassicActivator.cpp`）。WinUI アプリは `windowsapp.lib` しかリンクしないので、静的ライブラリが必要なものを自分で名乗る。段階 6 の利用者も同じ状況になる |

アプリの終了時に `Session::Close` が失敗した場合は、セッションをヒープに移して手放す。閉じていないセッションをデストラクタで破棄すると、Debug では assert になるため。

## 3. UI テストの変更（4 件）

C ABI にしかない動作を確かめていたもの。ほかの UI テストは変えていない。

| テスト | 前 | 後 | 理由 |
|---|---|---|---|
| D-06 `OpenMultipleFiles_PickTwo_*` | `Result: 3`、フォルダとファイル名 | `Result: 2`、フルパス 2 つ | C++ API がフォルダとファイル名を結合する（OP-03）。UI テスト設計書の U-4 で「形式を変えるならテストもそのとき合わせる」と決めていた |
| `CopyPlainText_WithNullText_*` | null で INVALID_PARAMETER(1) | 途中に NUL がある文字列で INVALID_PARAMETER(1) | `wstring_view` は null を表せない。途中の NUL が C++ API での無効な引数 |
| `PasteImage_SizeQuery_*` | BUFFER_TOO_SMALL(7) | **削除**（ボタンも削除） | C++ API は値を返すので、サイズの問い合わせが無い。`BufferTooSmall` は C ABI でしか起きない（C++ API 設計 11.4） |
| `ForceInitialize_WhileShuttingDown_*` | 2 回目の初期化が成功(0) | NOT_SUPPORTED(16) | `Session::Create` は 2 つ目を断る。成功と答えていたのは C ABI 側の互換のための扱い（ブリッジの `initClipboardManager`） |

## 4. 確かめたこと

| 確認 | 結果 |
|---|---|
| 画面ごとの UI テスト | Dialog 13 件、Notification と NotificationBanner 23 件、Clipboard と ClipboardHistory 54 件、すべて成功 |
| `test_windows.ps1 -IncludeDestructive -Baseline`（全件） | **390 件すべて成功**（ユニットテスト 297、UI テスト 93）。OS の設定はすべて戻った。基準との差は 3 章の 4 件と、`ClearUnpinned_RemovesTheUnpinnedItems` が実行されたこと（前回は NotExecuted）だけ。基準を記録し直した（390 件。1 件の削除で 391 から減った） |
| DLL 無しでのビルド | Debug / Release とも、サンプルのビルドで作られるのは `WindowsLibraryCore` だけ。AppX に残っていた古い DLL を消してから実行し、配置されるファイルに DLL が無いこと（レシピ 16 → 14 項目）を確かめた |
| サンプル自身のコンパイルの警告 | 0 件 |
| `check_design_consistency.py`（UI テスト設計書）、`check_cpp_api_contract.py` | すべて OK |
| CU-01 | **合格**（2026-09-23。段階 3 と段階 5 の分を兼ねて実行した。`2026-09-23-windows-architecture-stage5-result.md` の 3.2） |

## 5. 教訓

- **「移行前と同じ UI テスト」は、テストが C ABI の動作を確かめている箇所では成り立たない。** 表示の形を保てば大半は変えずに済むが、null、バッファの大きさ、互換のための成功のように、API の形そのものを確かめているテストは置き換えるしかない。次に API を移すときは、着手前にテストを「表示の形を見ているもの」と「API の形を見ているもの」に分けておく
- **静的ライブラリは、DLL が既定でリンクしていたライブラリを失う。** DLL のプロジェクトは Win32 の既定の import library 一式をリンクしていたが、WinUI のアプリはしない。リンクエラーは参照された `.obj` の分だけ出るので、機能を 1 つ移すたびに 1 つずつ見つかった
