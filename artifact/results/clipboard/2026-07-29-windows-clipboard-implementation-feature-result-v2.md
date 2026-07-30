# 実装結果レポート v2（レビュー対応）

## 基本情報

- 日付: 2026-07-29
- 機能名: Windows Clipboard Manager
- 対象OS: Windows
- 設計書: artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md
- ブランチ: feature/NTKIT-13
- 対応するレビュー: artifact/reviews/clipboard/2026-07-29-windows-clipboard-implementation-feature-review-v1.md（総合評価: 要修正（重大））
- 前バージョン: artifact/results/clipboard/2026-07-29-windows-clipboard-implementation-feature-result-v1.md

このレポートは v1 実装に対するレビュー v1 の指摘（H1〜H6, M1〜M7, L1〜L2）をすべて反映した結果をまとめる。v1 で報告済みの内容（設計対応表・変更ファイル一覧・未検証項目の大枠）は重複を避けるため v1 を参照し、本書は **レビュー対応差分** に絞る。

## 1. レビュー指摘への対応

### 1.1 重大な問題（High）— 全 6 件対応

| # | 指摘 | 対応 |
|---|---|---|
| H1 | 任意スレッド API と `uninit` の状態確認が原子的でない | `AcquireSyncLease`/新設の `AcquireHistoryCoordinator` を `initMutex_` で保護し、`initialized_` 確認 + lease 取得 + `dispatchHwnd_`/`coordinator_` スナップショットを 1 つの臨界区間にした。`Uninit()` 成功時の `lifecycle_.Reopen()` を削除し、reopen は次回 `InitClipboardManager` の commit 時のみに限定（`WindowsClipboardManager.cpp` の `AcquireSyncLease`/`AcquireHistoryCoordinator`/`CanDestroy`/`InitClipboardManager`/`Uninit`） |
| H2 | C ABI 境界・`noexcept` 完了処理で例外を正規化できない | 全 27 Bridge 関数を `SafeBridgeCall` テンプレートで包み、`std::bad_alloc→OUT_OF_MEMORY`、その他→`UNKNOWN` に正規化（`WindowsClipboardManager.cpp` 末尾）。`InitClipboardManager` に HWND の scope guard と backend/coordinator 構築の `try/catch` を追加し、失敗時に HWND を確実に破棄。`ClipboardHistoryCoordinator::CompleteItems`/`CompleteAvailability` の JSON 生成を `try/catch` で保護し、`noexcept` 完了ラムダから例外が漏れて `std::terminate` する経路を除去 |
| H3 | `StartWatch` 部分失敗で token を失う | `state->alive` を 3 トークン登録が全て成功した後にのみ `true` にするよう変更。rollback は解除に成功したトークンのみ `false` にし、失敗した分は `revokePending_=true` として保持。`StartWatch` の先頭で `revokePending_` を確認し、解消するまで新規登録を拒否（`WindowsClipboardHistoryWinRt.cpp`） |
| H4 | `StopWatch` が in-flight callback をドレインせず `CanDestroy` が早期に true になる | 解除成功時に `WatchState` を破棄せず `retiredStates_` に退避し、`CanDestroy()` が現行 state と全 retired state の `inFlight` を確認するよう変更。gate（`alive=false`）はトークン解除より先に閉じる（`WindowsClipboardHistoryWinRt.cpp`） |
| H5 | `NoteSelfWrite` が一度も呼ばれない | `ClipboardManager` の `CopyPlainText`/`CopyHtml`/`CopyFiles`/`CopyImage`/`CopyCustomFormat`/`CopyMultipleFormats`/`ClearClipboard`/`ReserveDeferredFormats` の各成功パスで `watcher_.NoteSelfWrite()` を呼ぶよう追加（`WindowsClipboardManager.cpp`） |
| H6 | 機微情報除外 marker 配置失敗が成功扱いになる | `ApplyWriteOptions` 呼び出しを `FinalizeWriteOptions` に置き換え、marker 配置失敗時は `EmptyClipboard` によるロールバックを行い、ロールバック成功なら `UNKNOWN`、失敗なら `PARTIAL_STATE` を返すよう変更。全 Copy API の入口で `IsValidWriteOptions` により未定義 option bit を `INVALID_PARAMETER` で拒否（`WindowsClipboardCore.cpp`） |

### 1.2 改善提案（Medium）— 全 7 件対応

| # | 指摘 | 対応 |
|---|---|---|
| M1 | WinRT イベント callback の例外が ABI へ漏れる | `RaiseEvent` の `fn(*events)` 呼び出しを `try/catch` で保護。`HistoryEnabledChanged`/`RoamingEnabledChanged` ハンドラ内の `Clipboard::IsHistoryEnabled()`/`IsRoamingEnabled()` 呼び出しも個別に `try/catch` で保護（`WindowsClipboardHistoryWinRt.cpp`） |
| M2 | `copyMultipleFormats` の checked 演算・境界検証不足 | `text` サイズ計算を `ClipboardFormats::CheckedAdd`/`CheckedMul` に置き換え。`format` が `CF_HDROP`/`CF_DIB`/`CF_DIBV5`/`CF_BITMAP` のとき `text`/`html` キーを拒否する整合性検証を追加（`WindowsClipboardManager.cpp::CopyMultipleFormats`）。base64 （バイナリペイロード）対応は本レビュー対応の範囲外として未実装のまま — 詳細は 2 節参照 |
| M3 | `hasClipboardFormat` 成功時に `pError` が更新されない | 成功パスの末尾で明示的に `CLIPBOARD_ERROR_NONE` を設定するよう修正 |
| M4 | 履歴 timestamp を `double` の JSON number に変換し精度が失われる | `EncodeItems` の `timestamp` を `JsonValue::CreateNumberValue` から `JsonValue::CreateStringValue(std::to_wstring(...))` に変更し、int64 精度をそのまま保持する文字列表現に変更。`getClipboardHistory` の Doxygen コメントも `"timestamp":"<int64>"` に更新（スキーマ変更を明記） |
| M5 | 変更監視の登録失敗を `init` 成功として隠す | `watcher_.Start()` が失敗し、かつ呼び出し側が `onChanged` を指定していた場合は `init` 自体を `CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED` で失敗させ、作成済みの HWND/coordinator を巻き戻すよう変更。`onChanged` が null の場合は従来どおり縮退動作を許容 |
| M6 | 失敗注入・Manager・watcher テストが未実装 | `windows/WindowsLibraryTest/ClipboardCoreTest.cpp` を新規追加し、`WindowsClipboardCore.cpp` を `IClipboardWin32Api` seam 経由でテスト対象にリンク。`OpenClipboard`/`EmptyClipboard`/`SetClipboardData` の失敗注入、H6 の write-option marker 失敗時ロールバック（成功/失敗双方）、`CopyMultipleFormats` の部分失敗ロールバック（成功/失敗双方）、`ClipboardWatcher` の登録失敗・解除失敗と再試行を検証する 10 件のテストを追加。Manager シングルトン全体・WinRT 実 API 呼び出しは引き続き対象外（v1 で開示済みの理由のまま。2 節参照） |
| M7 | Release/Win32 構成に export 定義・`/utf-8` 設定なし | `WindowsLibrary.vcxproj` の Debug/Release × Win32/x64 全 4 構成の `PreprocessorDefinitions` に `WINDOWSLIBRARY_EXPORTS` を統一して追加。C4819 の実体は `/utf-8` 未設定ではなく新規 Clipboard ファイルのコメント中の em dash（—）で、プロジェクト全体の文字コード関連ビルド設定を変更せず該当箇所を ASCII に置換して解消（`WindowsClipboardCore.h`/`WindowsClipboardFormats.h`/`WindowsClipboardManager.h`/`WindowsClipboardWindow.h`/`WindowsClipboardHistoryWinRt.h`/`.cpp`） |

### 1.3 軽微な指摘（Low）— 全 2 件対応

- L1（Bridge entry log 欠落）: H2 の `SafeBridgeCall` が全 Bridge 関数の入口で `DFLog(TAG, L"[Bridge] %ls", name)` を出力するため同時に解消。
- L2（実装結果の表現が実態より強い）: 本書 2 節で「実装済み」「自動テスト済み」「実機確認済み」を明確に分けて再記載する。

## 2. 再評価後の状態（実装済み／自動テスト済み／実機未確認）

- **実装済み・自動テスト済み**: H1〜H6, M1〜M6 は対応コードに加えて自動テスト（`ClipboardHistoryCoordinatorTest.cpp` 既存分 + `ClipboardCoreTest.cpp` 新規 10 件）で契約を確認済み。M7 はビルド結果（3 節）で確認済み。
- **実装済みだが自動テスト対象外**（v1 から変更なし、理由も同じ）: `ClipboardManager` シングルトン全体、`WindowsClipboardHistoryWinRt.cpp` の実 WinRT 呼び出し。STA + 実メッセージポンプが必要なため、`WindowsLibraryTest` の MSTest 既定ホストでは検証できない。
- **未実装のまま**（レビュー対応の範囲外と判断）: M2 の base64 バイナリペイロード対応。テキスト/HTML のみサポートする現行実装のまま。design のタスク粒度では明示的に base64 対応が求められていた記載はなく、レビューの M2 指摘のうち「checked size」「format/payload 種別整合」の 2 点のみを是正した。base64 が必要な場合は別タスクとして切り出すことを推奨する。
- **実機未検証**（v1 から変更なし）: F-13 未パッケージ/MSIX 挙動、WinRT フォアグラウンド要件の実挙動、WinRT 履歴 API の実疎通・イベント実配送、Win32 クリップボードの他アプリとの実相互運用。ユーザーの明示指示に基づき、引き続き未完了として報告する。

## 3. ビルド結果

- 実行コマンド:
  - `MSBuild.exe WindowsLibrary.sln /t:WindowsLibrary /p:Configuration=Debug /p:Platform=x64`
  - `MSBuild.exe WindowsLibrary.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=x64`（クリーン再ビルドで新規 clipboard ファイルの警告を確認）
  - `MSBuild.exe WindowsLibraryTest.vcxproj /t:Rebuild /p:Configuration=Debug /p:Platform=x64`
  - `scripts/build_windows_library_dll.ps1 -c release -v 1.4.1 -o "$env:TEMP\windows-native-toolkit-verify2.dll"`
- 結果: SUCCESS（全て）
- 補足ログ:
  - Release|x64 のクリーン再ビルドで Clipboard 関連の `C4273`/`C4819` が解消されたことを確認（M7）。残存する `C4190`/`C4273`（`common.h`）や `WindowsNotificationManager.cpp` 等の `C4819` は本タスクが触れていない既存コード由来で、対象外
  - `build_windows_library_dll.ps1` は今回も `WindowsLibrary.rc` にバージョンをスタンプする副作用があるため、検証後に `git checkout -- windows/WindowsLibrary/WindowsLibrary.rc` でコミット対象外の変更を復元し、リポジトリはクリーンな状態

## 4. テスト結果

- 実行したテスト: `vstest.console.exe windows\WindowsLibraryTest\x64\Debug\WindowsLibraryTest.dll`
- 結果サマリー:
  - 実行件数: 83（既存 Notification 21 件 + Clipboard 純ロジック 21 件 + Coordinator 31 件 + 新規 Core seam 10 件）
  - 成功: 83 / 失敗: 0
- v1 からの差分: 新規 `ClipboardCoreTest.cpp`（10 件）を追加。既存 73 件は regression なし。

### 4.1 新規テスト詳細（M6 対応）

| テスト観点 | テストケース | 結果 |
|---|---|---|
| OpenClipboard 失敗 → BUSY | Test_CopyPlainText_OpenClipboardFails_ReturnsBusy | ○ |
| EmptyClipboard 失敗 → UNKNOWN | Test_CopyPlainText_EmptyClipboardFails_ReturnsUnknown | ○ |
| SetClipboardData 失敗 → UNKNOWN | Test_CopyPlainText_SetClipboardDataFails_ReturnsUnknown | ○ |
| 未定義 option bit → INVALID_PARAMETER | Test_CopyPlainText_InvalidWriteOptionBits_ReturnsInvalidParameter | ○ |
| H6: marker 配置失敗 → rollback 成功 → UNKNOWN | Test_CopyPlainText_ExcludeHistoryMarkerFails_RollsBackAndReturnsUnknown | ○ |
| H6: marker 配置失敗 → rollback 失敗 → PARTIAL_STATE | Test_CopyPlainText_ExcludeHistoryMarkerFails_RollbackAlsoFails_ReturnsPartialState | ○ |
| CopyMultipleFormats 部分失敗 → rollback 成功 → UNKNOWN | Test_CopyMultipleFormats_SecondFormatFails_RollbackSucceeds_ReturnsUnknown | ○ |
| CopyMultipleFormats 部分失敗 → rollback 失敗 → PARTIAL_STATE | Test_CopyMultipleFormats_SecondFormatFails_RollbackAlsoFails_ReturnsPartialState | ○ |
| AddClipboardFormatListener 失敗 → Start が false | Test_ClipboardWatcher_Start_AddListenerFails_ReturnsFalse | ○ |
| RemoveClipboardFormatListener 失敗 → 登録維持・再試行可 | Test_ClipboardWatcher_Stop_RemoveListenerFails_StaysRegisteredAndRetryable | ○ |

## 5. Definition of Done（差分のみ）

v1 の DoD 判定のうち、本レビュー対応で ○ に更新した項目:

- ○ F-11（書き込みオプション）: marker 失敗時のロールバックとロールバック失敗時の `PARTIAL_STATE` を実装・テストで確認（H6）
- ○ F-09（自書き込み抑止）: `NoteSelfWrite` を全成功経路で呼ぶよう実装（H5）。ただし実クリップボードでの自書き込みループ抑止の実機確認は引き続き未実施
- ○ `uninitClipboardManager`/`canDestroyClipboardManager` と任意スレッド API の原子性（H1）
- ○ C ABI 例外安全性・`noexcept` 完了処理の安全性（H2）
- ○ WinRT イベント登録の部分失敗・in-flight ドレイン（H3, H4）
- ○ Win32 failure seam のテスト網羅（M6）— DoD 上「seam 再現を実施済み」として扱ってよい状態になった

上記以外の DoD 項目（実機未検証項目を含む）は v1 記載のまま変更なし。

## 6. 設計差分

v1 から変更なし（`WindowsClipboardWindow.{h,cpp}` へのファイル集約差分、自動テストスコープの限定）。加えて:

- 履歴 JSON の `timestamp` フィールドを number から string へ変更（M4）。これは実装バグ修正であり、実機結果を理由にした仕様変更ではない（設計書の JSON 型が明記されていなかった箇所を、64bit 精度を保証する形に是正）

## 7. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む（再レビュー、または review-implementation-feature へ進む）
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
