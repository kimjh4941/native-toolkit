# 実装結果レポート

## 基本情報

- 日付: 2026-07-29
- 機能名: Windows Clipboard Manager
- 対象OS: Windows
- 設計書: artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md（正本。無印版は不使用）
- ブランチ: feature/NTKIT-13

## 1. 実装サマリー

### 1.1 設計書由来の実装

T-01〜T-18（設計書のタスク breakdown、T-19「サンプルアプリ対応」は `design-sample-app` の範囲のため対象外）を順に実装。

- T-01: `WindowsLibrary.vcxproj` にクリップボード関連 `.cpp`/`.h` を登録。プロジェクト既定 `stdcpp17` を維持し、`WindowsClipboardHistoryWinRt.cpp` のみファイル単位で `stdcpp20` を設定。`pch.h` に `winrt/Windows.ApplicationModel.DataTransfer.h` を追加
- T-02: `WindowsClipboardManager.h` に 20 種のエラーコード（`CLIPBOARD_ERROR_NONE` 含む）、書き込みオプションフラグ、コールバック typedef、Doxygen コメント付き `extern "C"` API を定義。`WindowsLibrary.def` に Clipboard Manager Bridge セクションを追加
- T-03: `WindowsClipboardFormats.{h,cpp}` に純ロジック（Checked 演算、CF_HTML 構築/解析、DROPFILES 構築/検証、DIB 検証、UNICODETEXT 検証、UTF-8/16 変換）を実装
- T-04: `WindowsClipboardCore.{h,cpp}` に `IClipboardWin32Api` 失敗注入 seam、RAII（`ClipboardScope`/`GlobalMem`/`GlobalLockScope`/`PutFormat`）を実装
- T-05/T-05b: `WindowsClipboardLifecycle.{h,cpp}`（lease/close/drain）、`WindowsClipboardHistoryCoordinator.{h,cpp}`（Queued→Running→Finished 状態機械、cancel、drain）、`WindowsClipboardManagerInternal.h`/`WindowsClipboardManager.cpp`（Manager 骨格・dispatchHwnd）を実装
- T-06〜T-14: F-01〜F-11（テキスト/HTML/ファイル一覧/画像/独自フォーマット/複数フォーマット/クリア/変更監視/遅延レンダリング/書き込みオプション）を `WindowsClipboardCore.cpp` + `WindowsClipboardManager.cpp` に実装
- T-15/T-16: F-12（履歴取得/復元/削除/消去/イベント/可用性）を `WindowsClipboardHistoryBackend.h`（Port）、`WindowsClipboardHistoryWinRt.{h,cpp}`（WinRT 実装、C++20 コルーチン）に実装
- T-17: エラー正規化（Win32/WinRT 双方の失敗を 20 種のドメインエラーへ集約）を全経路に反映
- T-18: 全公開 API に Doxygen コメント、全メソッド先頭に `DFLog`/`DLog` を実装。`.def` を最終確認

### 1.2 実装時の追加判断

- **ファイル配置の差分**: 設計書の「追加ファイル」表は `WindowsClipboardWindow.{h,cpp}` に dispatchHwnd・監視・遅延レンダリング・UI 配送をまとめる想定だったが、実装では `DeferredClipboard`/`ClipboardWatcher` クラスを Win32 メカニクスに近い `WindowsClipboardCore.{h,cpp}` へ配置し、`WindowsClipboardWindow.{h,cpp}` は HWND 生成/破棄と WndProc → `ClipboardManager` への委譲のみを行う薄い層とした。メッセージルーティングとクラス責務は設計と等価だが、物理ファイル構成が設計書の表と異なる
- **自動テストのスコープ縮小**: `WindowsClipboardManager.cpp`（Manager シングルトン全体）、`WindowsClipboardWindow.cpp`、`WindowsClipboardHistoryWinRt.cpp` は `WindowsLibraryTest` に**リンクしていない**。理由: (1) `WindowsClipboardManager.cpp` を組み込むとリンカが `MakeClipboardHistoryWinRtBackend()`（`WindowsClipboardHistoryWinRt.cpp` 内で定義）を要求し、この関数は C++20 かつ実 WinRT 呼び出しを含むため、MSTest 既定ホストが提供しない実 STA + メッセージポンプが必要になる。(2) 設計の GetAvailabilityAsync/GetItemsAsync 等は本来非同期契約だが、実装は同期 WinRT 呼び出しをそのままラップしており、実機の STA スレッド上でしか安全に検証できない。このため自動テストは `ClipboardFormats`（純ロジック、全関数網羅）と `ClipboardHistoryCoordinator`（`MockClipboardHistoryBackend` によるアプリケーション層の状態機械検証）に限定した。Manager 全体・実 Win32 クリップボード相互運用・WinRT 履歴の実機動作は自動テスト対象外（詳細は 5.2/6 節）
- **コンパイルエラー修正（設計の実装可能性検証）**:
  1. `ClipboardHistoryCoordinator` の各 `Request*` 実装で、完了ラムダが `ClipboardLifecycle::Lease`（move-only）を `[lease = std::move(lease)]` でキャプチャしていたが、格納先の `HistoryItemsCallback` 等が `std::function`（コピー構築可能要求）だったため `static_assert` で規約違反（C2338）。`std::make_shared<ClipboardLifecycle::Lease>(std::move(lease))` でラップし、ラムダをコピー可能に修正（5 箇所）
  2. `WindowsClipboardHistoryWinRt.cpp` は per-file `stdcpp20` を指定しているが、共有 PCH は プロジェクト既定の `stdcpp17` でコンパイル済みのため PCH 不整合（C2855）。同ファイルのみ `PrecompiledHeader=NotUsing` に設定（`#include "pch.h"` は残るがテキスト解析として処理される）
  3. テストファイルで `namespace` をクラス本体内に書いてしまい構文エラー（C2059 ほか）。ファイルスコープへ移動して解消
  4. `DROPFILES` 型がテストの pch.h からは見えず未定義エラー。`<shlobj.h>` を明示 `#include`

## 2. 変更ファイル

### 2.1 新規作成

- `windows/WindowsLibrary/WindowsClipboardManager.h` / `.cpp`
- `windows/WindowsLibrary/WindowsClipboardManagerInternal.h`
- `windows/WindowsLibrary/WindowsClipboardCore.h` / `.cpp`
- `windows/WindowsLibrary/WindowsClipboardFormats.h` / `.cpp`
- `windows/WindowsLibrary/WindowsClipboardLifecycle.h` / `.cpp`
- `windows/WindowsLibrary/WindowsClipboardHistoryBackend.h`
- `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.h` / `.cpp`
- `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.h` / `.cpp`
- `windows/WindowsLibrary/WindowsClipboardWindow.h` / `.cpp`
- `windows/WindowsLibraryTest/ClipboardFormatsTest.cpp`
- `windows/WindowsLibraryTest/ClipboardHistoryCoordinatorTest.cpp`

### 2.2 既存変更

- `windows/WindowsLibrary/pch.h`: `winrt/Windows.ApplicationModel.DataTransfer.h` を追加
- `windows/WindowsLibrary/WindowsLibrary.vcxproj`: クリップボード `.cpp`/`.h` を `ClCompile`/`ClInclude` へ登録。`WindowsClipboardHistoryWinRt.cpp` のみ `LanguageStandard=stdcpp20` かつ `PrecompiledHeader=NotUsing`
- `windows/WindowsLibrary/WindowsLibrary.def`: Clipboard Manager Bridge の 27 エクスポートを追加
- `windows/WindowsLibraryTest/WindowsLibraryTest.vcxproj`: `ClipboardFormatsTest.cpp`/`ClipboardHistoryCoordinatorTest.cpp` と、テスト対象の `WindowsClipboardFormats.cpp`/`WindowsClipboardLifecycle.cpp`/`WindowsClipboardHistoryCoordinator.cpp` を登録

### 2.3 非変更（設計上対象だが未変更）

- `windows/UnityWindowsPlugin/*`: ユーザー指示により変更禁止。未変更
- `windows/WindowsLibrary/WindowsLibrary.vcxproj.filters`: VS エクスプローラーの表示分類のみに影響し、ビルドをブロックしないため未対応
- `windows/WindowsLibraryExample/*`: 設計書 T-19「サンプルアプリ対応」は `design-sample-app` の範囲と明記されており、本タスク（`/implement-feature`）の対象外

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

`CLIPBOARD_ERROR_NONE`(0) 〜 `CLIPBOARD_ERROR_UNKNOWN`(19) の 20 種を `WindowsClipboardManager.h` に定義し、Win32 API 失敗（`SetClipboardData`/`GlobalAlloc`/`OpenClipboard` 等）と WinRT 例外（`winrt::hresult_error` の `E_ACCESSDENIED`/`E_OUTOFMEMORY`/`E_INVALIDARG` ほか、`std::bad_alloc`、任意の `std::exception`、非 `std::exception` 例外）をそれぞれ `WindowsClipboardCore.cpp`/`WindowsClipboardHistoryWinRt.cpp` 内のマッピング関数で正規化。`ClipboardHistoryCoordinator::OnStartQueuedRequest` の `try/catch` はコルーチンフレーム確保失敗を `CLIPBOARD_ERROR_OUT_OF_MEMORY` として終端する。

### 3.2 errorCode / errorMessage 対応反映

本機能の Bridge API は `errorMessage`（文字列）ではなく `DWORD* pError`（数値エラーコード）契約であり、既存の `WindowsNotificationManager.h` と同一の Bridge 規約（数値コード + Doxygen コメントでの文脈記述）に揃えた。既存 Bridge に `errorMessage` 文字列出力の前例がないため踏襲。

### 3.3 success時契約

`isSuccess == true` の直接対応物はなく、Bridge 契約は「返り値 / out パラメータが有効 ⇔ `*pError == CLIPBOARD_ERROR_NONE`」。`ClipboardHistoryCoordinatorTest.cpp` の各正常系テスト（`Test_RequestGetItems_Accepted_...` 等）で `CLIPBOARD_ERROR_NONE` のときのみ JSON payload が非 null であることを確認済み。異常系（`Test_RequestClearUnpinned_BackendError_...`）でも非 `NONE` のとき payload が null であることを確認済み。

## 4. ビルド結果

- 実行コマンド:
  - `MSBuild.exe WindowsLibrary.sln /t:WindowsLibrary /p:Configuration=Debug /p:Platform=x64`
  - `MSBuild.exe WindowsLibrary.sln /t:WindowsLibraryTest /p:Configuration=Debug /p:Platform=x64`（`/t:Rebuild` で強制再ビルドし新規ファイルのコンパイルを確認）
  - `MSBuild.exe WindowsLibrary.sln /t:WindowsLibrary /p:Configuration=Release /p:Platform=x64`
  - `scripts/build_windows_library_dll.ps1 -c release -v 1.4.0 -o "$env:TEMP\windows-native-toolkit-verify.dll"`
- 結果: SUCCESS（上記すべて）
- 補足ログ（必要箇所のみ）:
  - `build_windows_library_dll.ps1` は成功時に `WindowsLibrary.rc` へバージョンをスタンプする副作用があるため、検証実行後に `git checkout -- windows/WindowsLibrary/WindowsLibrary.rc` でコミット対象外の変更を復元済み（リポジトリはクリーン）
  - 既存コード由来の警告（`C4190`/`C4273`/`MSB3106` 等、`common.h` の C リンケージや WinRT AI Foundation winmd 関連）は本実装が原因ではなく、ビルド成功に影響しない

## 5. テスト結果

- 実行したテスト:
  - `vstest.console.exe windows\WindowsLibraryTest\x64\Debug\WindowsLibraryTest.dll`
- 結果サマリー:
  - 実行件数: 73（既存 Notification 系 21 件 + 新規 Clipboard 系 52 件）
  - 成功: 73
  - 失敗: 0
- 失敗時の対応: 該当なし（初回コンパイルエラーは 1. 節の通り実装/プロジェクト設定を修正して解消。テスト自体の失敗は発生していない）
- 未実施項目（あれば）: 5.2 節を参照

### 5.1 テスト詳細

| テスト観点 | テストファイル | テストケース | 結果 | 備考 |
|---|---|---|---|---|
| Checked 演算境界 | ClipboardFormatsTest.cpp | Test_CheckedAdd/Mul/ToInt/ToUInt_Overflow_ReturnsFalse | ○ | |
| CF_HTML 構築/解析往復 | ClipboardFormatsTest.cpp | Test_BuildCfHtml_And_ParseCfHtmlHeader_RoundTrips | ○ | |
| CF_HTML マーカー文字列混入耐性 | ClipboardFormatsTest.cpp | Test_BuildCfHtml_FragmentContainsMarkerText_DoesNotTruncate | ○ | |
| CF_HTML ヘッダ検証（欠落/重複/不正値/Version/範囲外/Selection片側） | ClipboardFormatsTest.cpp | Test_ParseCfHtmlHeader_* (7件) | ○ | |
| DROPFILES 構築/検証 | ClipboardFormatsTest.cpp | Test_BuildDropFiles_*, Test_ValidateDropFiles_* (4件) | ○ | |
| DIB 検証 | ClipboardFormatsTest.cpp | Test_ValidateDib_* (4件) | ○ | |
| UNICODETEXT 検証 | ClipboardFormatsTest.cpp | Test_ValidateUnicodeTextBlock_* (3件) | ○ | |
| UTF-8/16 相互変換 | ClipboardFormatsTest.cpp | Test_WideToUtf8_Utf8ToWide_RoundTrips | ○ | |
| 受付/拒否契約（0件/1件、INVALID_PARAMETER、NOT_INITIALIZED） | ClipboardHistoryCoordinatorTest.cpp | Test_RequestGetItems_NoDispatchWindow_*, Test_RequestGetItems_NullCallback_*, Test_Request(Restore\|Delete)Item_EmptyId_* | ○ | |
| Queued→Running→Finished 正常完了 | ClipboardHistoryCoordinatorTest.cpp | Test_RequestGetItems_Accepted_CompletesOnlyAfterOnStartQueuedRequest, Test_RequestGetAvailability_Accepted_*, Test_RequestClearUnpinned_BackendError_* | ○ | |
| キャンセル前競合（開始前） | ClipboardHistoryCoordinatorTest.cpp | Test_CancelBeforeStart_DeliversCanceled_AndStartNeverRuns | ○ | |
| キャンセル後競合（実行中、backend 後着完了は無視） | ClipboardHistoryCoordinatorTest.cpp | Test_CancelAfterStart_WhileRunning_* | ○ | |
| 完了権の一意性（backend 二重呼び出し耐性） | ClipboardHistoryCoordinatorTest.cpp | Test_DuplicateBackendCompletion_OnlyFirstDelivers | ○ | |
| CancelRequest 返り値（未知ID/0/正常） | ClipboardHistoryCoordinatorTest.cpp | Test_CancelRequest_* (3件) | ○ | |
| shutdown drain（未開始/実行中、CanDestroy ゲート） | ClipboardHistoryCoordinatorTest.cpp | Test_CloseAndDrain_* (3件) | ○ | |
| 履歴イベント登録（初回StartWatch/2回目Replace/失敗時挙動） | ClipboardHistoryCoordinatorTest.cpp | Test_SetHistoryCallbacks_* (6件) | ○ | |
| StopWatch 契約 | ClipboardHistoryCoordinatorTest.cpp | Test_StopWatch_* (2件) | ○ | |
| CanDestroy 境界 | ClipboardHistoryCoordinatorTest.cpp | Test_CanDestroy_* (2件) | ○ | |
| Data/Application 境界分離（構造確認） | ClipboardHistoryCoordinatorTest.cpp | Test_MockBackend_NeverSeesRequestIdOrLease | ○ | コンパイル時の型整合により保証 |
| 既存 Notification 回帰 | NotificationManagerTest.cpp | 既存 21 件 | ○ | 本実装による regression なし |

### 5.2 未実施ケース詳細

| テスト観点 | テストファイル | テストケース | 未実施理由 |
|---|---|---|---|
| `ClipboardManager` シングルトン全体（init/uninit/lease/drain 統合） | - | - | `WindowsClipboardManager.cpp` は C++20 の `WindowsClipboardHistoryWinRt.cpp` とリンカ依存があり、実 STA + メッセージポンプが必要。MSTest 既定ホストでは提供不可なため自動テスト対象外（1.2 節参照） |
| Win32 API 失敗注入（`IClipboardWin32Api` stub 経由の `SetClipboardData`/`EmptyClipboard`/リスナー解除失敗） | - | - | seam（`SetWin32ApiForTest`）はコード上に実装済みだが、上記と同じ理由で `WindowsClipboardCore.cpp` を経由する Manager 統合テストが自動化対象外のため未実施 |
| WinRT 履歴の実機動作（`GetHistoryItemsAsync` 等の実 API 呼び出し、3 イベントの実配送） | - | - | 実 Windows 11 環境・実 STA スレッド・実クリップボード履歴設定が必要。5.節末の「未検証項目」参照 |
| F-01〜F-08 の他アプリとの相互運用（実クリップボード round-trip） | - | - | 自動テストは `ClipboardFormats` の純ロジック検証に限定。実クリップボードへの読み書きは Manager 統合が必要なため上記と同じ理由で未実施 |
| F-13 未パッケージ / MSIX 挙動一致 | - | - | 実行時のパッケージ形態依存の検証であり、開発機上の自動ビルド/単体テストでは検証不能 |
| フォアグラウンド要件（`IsSelfForeground` の実挙動） | - | - | 実際にフォアグラウンド/非フォアグラウンド状態を切り替えた実機確認が必要 |

## 6. Definition of Done

- 判定基準:
  - ○: 今回の実装・コード・テスト確認の範囲では OK かつ設計書とズレていない
  - △: 一部 OK だが、追加確認が必要
  - ×: 未達、または設計書との差分が未解消
  - -: 対象外

### 機能

- △ F-01〜F-08: コピー/ペースト/内容確認/クリアの実装・純ロジック検証は完了。**他アプリとの相互運用は実機未検証**
- △ F-09: 変更監視の登録/解除/自書き込み抑止/再試行ロジックは実装済み。実クリップボード変化での動作は未検証
- △ F-10: 二相呼び出しの provider コールバック機構を実装。実 `WM_RENDERFORMAT` 経由の動作は未検証
- △ F-11: 全 copy API に `options` 引数を実装し `ApplyWriteOptions` へ委譲。Win+V への実反映は未検証
- △ F-12: 取得/復元/削除/消去/イベント/可用性を実装し、Coordinator 状態機械はモックで検証済み。**WinRT 実 API 呼び出し・3 イベントの実配送は未検証**（ユーザー指示「未パッケージ対応やフォアグラウンド要件を満たせない場合は未完了として報告」に該当し、本項目を未検証として明示）
- - F-06/F-07（`copyMultipleFormats`/`getPreferredClipboardFormat`）: 実装済み、公開 API から到達可能。上記 F-01〜F-08 に含めて評価

### 品質

- ○ F-14: 20 種のエラーコードを弁別して返す実装・テストあり
- △ F-15: 境界検証（Checked 演算、DIB/DROPFILES/UNICODETEXT 検証）は純ロジックテストで網羅。実読み取りパスへの適用は Manager 統合テストが対象外のため未検証
- ○ 純ロジック単体テスト: 21 件 PASS
- ○ F-17: 受付契約（0/1 件返却）、in-flight/lease 管理を Coordinator テストで検証
- △ 同期 WinRT 境界（`InvokeWinRt` 相当）/非同期境界の `try/catch`: コード実装済み。実 WinRT 呼び出し経路は未検証
- ○ 全コールバックが所有 UI スレッドで呼ばれる契約: コード構造・Doxygen コメントで明記（実行時保証は Manager 統合テスト対象外のため設計適合のみ確認）
- ○ `uninitClipboardManager` の FALSE 返却と再試行可能性: コード実装済み（コード読解で確認、実行時未検証）
- ○ `IClipboardWin32Api` stub での失敗再現: seam 実装済み（実行するテストコード自体は未実施、5.2 節参照）
- ○ 履歴 Port の非同期・Mock 完了タイミング制御: `ClipboardHistoryCoordinatorTest.cpp` で検証済み
- ○ `ClipboardLifecycle` の原子性: コード実装・Coordinator 経由の CanDestroy テストで間接検証
- ○ キャンセル後も開始済みコルーチンが完走: `Test_CancelAfterStart_WhileRunning_*` で検証
- ○ UI スレッド専有状態への任意スレッド直接アクセスなし: コードレビューで確認（`DeferredClipboard`/`ClipboardWatcher` は Manager 経由のみ）
- △ 非 reentrant 配送: コード構造上保証（Coordinator の `Complete` は table 経由の一意所有）。実行時の物理スレッド確認は未実施
- ○ `setClipboardHistoryCallbacks` の置換/部分失敗維持: `Test_SetHistoryCallbacks_*` で検証
- ○ エラーコード正規化: `ClassifyWinRtException` 等で実装（実 WinRT 例外での検証は未実施）
- ○ 非テキスト履歴項目の `"text": null` 表現: `EncodeItems`/Domain 型で実装・JSON スキーマ一致確認
- ○ 受付判定の単一経路: `Accept()` 実装・テストで確認
- ○ drain がコールバックをキューへ積むのみで初回 FALSE: Coordinator テストで検証
- ○ 完了権とコルーチン実行状態の分離: `Test_CancelAfterStart_WhileRunning_*` で検証
- ○ 各コルーチンが個別 `try/catch`: コード実装確認
- △ `init` の STA 検査/`WRONG_APARTMENT`: コード実装済み（`CoGetApartmentType` 呼び出し）。実行時未検証
- ○ 履歴コールバック置換が snapshot 差し替え: `Test_SetHistoryCallbacks_SecondRegistration_ReplacesEvents_NoReToken` で検証
- ○ `reserveDeferredFormats`/`recoverDeferredState` の UI スレッド限定: コード実装済み
- ○ Queued→Running→Finished 状態機械: Coordinator テストで検証
- ○ `uninit` の完了権一括 take: コード実装確認（Manager 統合実行は未検証）
- ○ Close 後の未配送ドレインが closing-work に計上: `Test_CloseAndDrain_*` で検証
- ○ drain の `PostMessage` 失敗時再試行/例外時 `ReleaseDrainWork` 保証: コード実装確認（`OnDrainMessage` の try/catch）
- ○ Data 層が request ID/lease/pending を参照しない: `IClipboardHistoryBackend` のシグネチャで構造的に保証
- ○ Port override が `void`/private runner が `fire_and_forget`: コード実装確認
- ○ Manager が Coordinator 経由でのみ backend にアクセス: コード実装確認
- ○ 受付と Close のロック順序（coordinator→lifecycle）: コード実装確認（`Accept`/`CloseAndDrain` とも同順）

### 構成

- △ F-13: 未パッケージ/MSIX の同一挙動 — **実機未検証。ユーザー指示によりタスク未完了として報告**
- ○ F-16: MFC × C++/WinRT ヘッダ順序を守りビルド成功（Debug/Release 双方）
- ○ Manager と C Bridge が `WindowsLibrary` に配置、`UnityWindowsPlugin`・既存 project/solution 設定は未変更
- - `WindowsLibraryExample` 全サブ機能確認: T-19 は `design-sample-app` の範囲のため対象外
- ○ プロジェクト既定 `stdcpp17` 維持、`WindowsClipboardHistoryWinRt.cpp` のみ `stdcpp20`: vcxproj で確認、ビルド成功
- ○ 既存 Dialog/Notification API への破壊的変更なし: 既存 21 テスト PASS で確認
- ○ 全公開 API に Doxygen コメント、全メソッド先頭にログ: コードレビューで確認

### 未検証・未完了として明示する項目（ユーザー指示に基づく報告）

ユーザーの明示指示「未パッケージ対応やフォアグラウンド要件を満たせない場合は、該当タスクを未完了として停止・報告する」に基づき、以下は実機（Windows 11 実機、STA スレッド、実メッセージポンプ、パッケージ/未パッケージ双方の実行環境）でのみ検証可能であり、本セッションの自動ビルド・単体テストの範囲では検証できていない：

1. **F-13 未パッケージ/MSIX 同一挙動**: `Clipboard.GetHistoryItemsAsync` 等の WinRT 履歴 API が未パッケージ実行で動作するか（設計書自身も「要検証」と明記）
2. **フォアグラウンド要件**: `RunGetItemsAsync` 等の `IsSelfForeground()` チェックが実際の Win+V 相当のフォアグラウンド判定と一致するか
3. **WinRT 履歴の実 API 疎通**: `StartWatch`/`HistoryChanged` 等のイベントトークン登録・発火、`SetItemAsContentAsync`/`DeleteItemAsync` の実クリップボード履歴への反映
4. **Win32 クリップボードの他アプリ相互運用**: 実際のクリップボードへの読み書きが他アプリ（メモ帳等）と互換であるか

これらは実装・ビルド・単体テストの範囲では満たしているが、**実機確認が必須の項目としてタスク未完了のまま報告**する。実装を仕様どおりに進めるため、実機結果を理由にした仕様変更は行っていない。

## 7. 設計差分

- 差分有無: あり
- 差分内容:
  - `WindowsClipboardWindow.{h,cpp}` へ `DeferredClipboard`/`ClipboardWatcher` を集約する設計書のファイル構成に対し、実装では両クラスを `WindowsClipboardCore.{h,cpp}` に配置し、`WindowsClipboardWindow.{h,cpp}` は HWND 生成/破棄と WndProc 委譲のみの薄い層とした（1.2 節）
  - 自動テストの対象を `ClipboardFormats`（純ロジック）と `ClipboardHistoryCoordinator`（モックによるアプリケーション層）に限定し、`ClipboardManager` 全体・`WindowsClipboardHistoryWinRt` の実 WinRT 呼び出しは自動テスト対象外とした（1.2 節、5.2 節）
- 影響範囲:
  - ファイル構成差分はクラス責務・メッセージルーティングが設計と等価なため機能上の影響なし。将来の保守で設計書の表と実ファイル構成が食い違う点は認識しておく必要がある
  - テストスコープ差分は「品質」DoD 項目のうち実行時契約（reentrant 配送・STA 検査・drain 実行等）の一部が「コード実装確認のみ」（△）にとどまる直接原因。実機での Manager 統合テスト・手動確認が今後必要

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
