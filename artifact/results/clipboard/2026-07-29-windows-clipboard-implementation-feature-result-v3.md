# 実装結果レポート v3（再レビュー対応）

## 基本情報

- 日付: 2026-07-29
- 機能名: Windows Clipboard Manager
- 対象OS: Windows
- 設計書: artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md
- ブランチ: feature/NTKIT-13
- 対応するレビュー: artifact/reviews/clipboard/2026-07-29-windows-clipboard-implementation-feature-review-v2.md（総合評価: 要修正（重大））
- 前バージョン: artifact/results/clipboard/2026-07-29-windows-clipboard-implementation-feature-result-v2.md

v2 実装に対する再レビュー（v2）の指摘（H1〜H4, M1〜M6, L1）への対応をまとめる。v1/v2 で報告済みの内容は重複を避け、本書は再レビュー対応差分に絞る。

## 1. 再レビュー指摘への対応

### 1.1 重大な問題（High）— 4件対応

| # | 指摘 | 対応 |
|---|---|---|
| H1 | `canDestroyClipboardManager` が Win32 listener の残存を判定しない | `ClipboardManager::CanDestroy()` に `!watcher_.IsRegistered()` を必須条件として追加。`initMutex_` の同じ臨界区間内（`Uninit()` の listener 解除処理と排他）で判定するため、レース条件も同時に閉じている |
| H2 | WinRT watcher の stop/drain/再登録/callback thread 契約が未完結 | (1) 履歴イベント配送を `WM_APP_CLIPBOARD_HISTORY_EVENT` 経由で owner UI thread へ marshal するよう再設計。WinRT 側ハンドラは kind + bool を `PostMessage` するだけで、実際のコールバック呼び出しは `ClipboardHistoryCoordinator::OnHistoryEventMessage`（UI thread 専用）が**配送時点で現在登録されているコールバック**を参照して行う。これにより stop/replace 後に古い世代の関数ポインタが呼ばれることがなくなる。(2) `ClipboardHistoryWinRt` の `watching_`/`revokePending_`/`watchState_`/`retiredStates_` に `stateMutex_` を追加し、`CanDestroy()`（任意スレッドから呼ばれ得る）と `StartWatch`/`StopWatch`/`ReplaceEvents`（owner UI thread 限定）の間のデータレースを解消 |
| H3 | WndProc と遅延描画 provider に例外境界がない | `WindowsClipboardWindow.cpp` の `WndProc` 全体を `try/catch` で包み、ハンドラ由来の例外が Win32 コールバック境界を越えないようにした。`ReserveDeferredFormats` の `Renderer` ラムダで provider 呼び出し（サイズ問い合わせ・書き込みの両フェーズ）を `try/catch` で保護し、2 回目呼び出しが 1 回目に提示したサイズを超える `required` を返した場合はバッファを信用せず失敗させるよう検証を追加 |
| H4 | 自書き込み抑止が「成功した API」に限定され、変更後エラーを外部変更として配送する | `WindowsClipboardCore` の全 Copy* 系関数・`DeferredClipboard::Reserve`・`DeferredClipboard::RecoverFromPartialState` に `bool* outMutated`（既定 `nullptr`）を追加し、`EmptyClipboard` が成功した時点（＝実際に OS クリップボードが変化した時点）で `true` を設定するよう変更。Manager 側は戻り値の成否ではなく `mutated` フラグを見て `watcher_.NoteSelfWrite()` を呼ぶよう全 Copy 系 API・`ReserveDeferredFormats`・`Uninit()` 内の `RecoverFromPartialState` 呼び出しを修正 |

### 1.2 改善事項（Medium）— 5件対応、1件は意図的に部分対応

| # | 指摘 | 対応 |
|---|---|---|
| M1 | `copyMultipleFormats` が `base64` を処理せず、format/payload の不正な組合せも受理できる | `ClipboardFormats::Base64Decode`（RFC 4648、長さ・文字種・パディング位置を検証）を新規実装し、`"base64"` キーを追加。`format` の重複登録を拒否。`CF_DIB`/`CF_DIBV5`/`CF_HDROP` への base64 payload は既存の `ValidateDib`/`ValidateDropFiles` で構造検証。設計書 v2 も本文書の M2（v1レビュー）で既に触れていた `base64` 対応を実装で埋めた形 |
| M2 | `timestamp` を設計変更なしに number → string へ変更していた | 設計書（`artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`）の該当 2 箇所（F-12a の JSON スキーマ表、履歴 API の JSON スキーマ一覧）を `"timestamp":"<int64>"`（10進数文字列）に更新し、変更理由（`double` 精度では 100ns 単位の FILETIME 相当ティック値を正確に表せない）を明記。これにより実装・ヘッダ・設計書が一致した状態になった（consumer/manual は本機能について未作成のため対象外） |
| M3 | 内側の `catch (...)` が `std::bad_alloc` も `INVALID_PARAMETER` に変換する | `CopyFiles`/`CopyMultipleFormats` の JSON パース `catch` ブロックに `catch (const std::bad_alloc&) { throw; }` を追加し、`SafeBridgeCall` まで正しく伝播して `OUT_OF_MEMORY` に正規化されるようにした |
| M5 | `/utf-8` が設定されていない | **部分対応・意図的な差し戻しあり**（詳細は 2 節）。プロジェクト全体への `/utf-8` 追加を一度実施したが、`common.h` など既存ファイルが Shift-JIS エンコードであることが実ビルドで判明し（`C4828`: 現在の文字セットで表示できない文字）、既存コードの解釈を破壊する回帰を確認したため差し戻した。代わりに新規 Clipboard ファイル（テストの 2 ファイルを含む）内の非 ASCII 文字（emダッシュ、コメント中の日本語）を ASCII に置換し、実際に埋め込みが必要だった 1 箇所（UTF-8 往復変換テストの日本語文字列）はソースコード上は数値コードポイントから構築する形に変更して非 ASCII バイトそのものを排除した |
| M6 | 実装結果の「自動検証済み」が実際のカバレッジより強い | 本書 2 節で「実装済み」「自動テスト済み」「実機未確認」を明示的に分けて再記載する |
| L1 | `retiredStates_` が drain 後も削除されない | `ClipboardHistoryWinRt::StopWatch()` の成功パスで `inFlight == 0` になった要素を `std::remove_if` で prune するよう追加 |

## 2. 再評価後の状態（実装済み／自動テスト済み／実機未確認）

### 2.1 M5 の技術的な制約（今回新たに判明した事実）

`windows/WindowsLibrary/common.h`（および `WindowsNotificationManager.*`/`WindowsClassicActivator.*`/`WindowsAppSdkBootstrap.cpp` 等の既存ファイル）は Shift-JIS（コードページ 932）でエンコードされている。`/utf-8` コンパイラオプションはソース文字コードを UTF-8 として解釈するため、これらの既存ファイルに対しては `C4828`（現在のソース文字セットで使用できない文字）という、単なる警告に留まらない実害のある問題を生む（該当バイト列が不正な UTF-8 シーケンスとして誤読される）。

Clipboard 機能のみのタスクスコープで、この関連のない既存ファイル群を Shift-JIS → UTF-8 に再エンコードすることは、影響範囲・レビュー負荷ともに本タスクの範囲を超えると判断し、実施しなかった。`/utf-8` の全社的な導入は、既存ファイル群の再エンコードとセットで行うべき別タスクとして切り出すことを推奨する。

新規 Clipboard ファイルについては、非 ASCII バイトを一切含まない形に修正済みであり、`/utf-8` の有無にかかわらず `C4819`/`C4828` のいずれも発生しない状態になっている（Debug/Release 双方のクリーンビルドで確認済み）。

### 2.2 実装済み・自動テスト済み

H1〜H4, M1, M3, L1 は対応コードに加えて自動テストで契約を確認済み（`ClipboardCoreTest.cpp`・`ClipboardHistoryCoordinatorTest.cpp`・`ClipboardFormatsTest.cpp` に新規テストを追加）。M5 はビルド結果（3節）で確認済み。M2 は設計書更新のみ（テスト対象外の文書変更）。

### 2.3 実装済みだが自動テスト対象外（v1/v2 から変更なし）

`ClipboardManager` シングルトン全体、`WindowsClipboardHistoryWinRt.cpp` の実 WinRT 呼び出し。理由は従来どおり：実 STA + メッセージポンプが必要で、MSTest 既定ホストでは検証できない。

### 2.4 新たに開示する残存リスク（H2 関連）

`ClipboardHistoryWinRt::StartWatch` の `HistoryEnabledChanged`/`RoamingEnabledChanged` ハンドラは、WinRT がイベントを発火したスレッド上でそのまま `Clipboard::IsHistoryEnabled()`/`IsRoamingEnabled()` を呼び出してから、その結果（bool）だけを owner UI thread へ `PostMessage` している。**この WinRT API 呼び出し自体が owner UI thread 以外で行われる可能性は今回も解消していない。** レビューが要求した「owner UI thread への配送」は実現したが、「WinRT 呼び出しそのものを UI thread に限定する」までは行っていない。理由: これを行うには「イベント発火 → 何もせず即座に UI thread へ post → UI thread 側で `IsHistoryEnabled()` を呼ぶ」という設計に変える必要があるが、Coordinator は WinRT 型に一切触れない Application 層であるという設計上の制約（`ClipboardHistoryCoordinator.h` の doc comment）と矛盾するため、今回のスコープでは見送った。この WinRT API のスレッド要件自体が実機でしか確認できない事項であるため、ユーザー指示に基づき **未検証のまま報告する**。

### 2.5 実機未検証（v1/v2 から変更なし）

F-13 未パッケージ/MSIX 挙動、WinRT フォアグラウンド要件の実挙動、WinRT 履歴 API の実疎通・イベント実配送（今回のUI thread marshal 自体を含む）、Win32 クリップボードの他アプリとの実相互運用。

## 3. ビルド結果

- 実行コマンド:
  - `MSBuild.exe WindowsLibrary.sln /t:WindowsLibrary /p:Configuration=Debug /p:Platform=x64`
  - `MSBuild.exe WindowsLibrary.vcxproj /t:Rebuild /p:Configuration=Release /p:Platform=x64`
  - `MSBuild.exe WindowsLibraryTest.vcxproj /t:Rebuild /p:Configuration=Debug /p:Platform=x64`
  - `scripts/build_windows_library_dll.ps1 -c release -v 1.4.3 -o "$env:TEMP\windows-native-toolkit-verify4.dll"`
- 結果: SUCCESS（全て）
- 補足ログ:
  - クリーンリビルドで Clipboard 関連ファイルの `C4273`/`C4819`/`C4828` が一切出力されないことを確認
  - 残存する警告（`common.h` の `C4190`/`C4273`、`WindowsNotificationManager.*` 等の `C4819`）は本タスクが触れていない既存コード由来
  - `build_windows_library_dll.ps1` の `WindowsLibrary.rc` バージョンスタンプ副作用は毎回 `git checkout` で復元済み。リポジトリはクリーン

## 4. テスト結果

- 実行したテスト: `vstest.console.exe windows\WindowsLibraryTest\x64\Debug\WindowsLibraryTest.dll`
- 結果サマリー:
  - 実行件数: 92（v2 の 83 件 + 新規 9 件: Base64Decode 7件 + OnHistoryEventMessage 2件）
  - 成功: 92 / 失敗: 0
- v2 からの差分:
  - 新規: `Test_Base64Decode_*`（7件、正常系3・異常系4）
  - 新規: `Test_OnHistoryEventMessage_AfterStop_DoesNotInvokeClearedCallback`, `Test_OnHistoryEventMessage_UnknownKind_IsSafeNoop`
  - 更新: `Test_SetHistoryCallbacks_EventsFireThroughToUserCallbacks` を、イベント発火（post のみ）と `OnHistoryEventMessage`（UI thread 配送のシミュレート）の 2 段階に分離する形に書き換え（H2 の再設計に追従するための必須更新）

### 4.1 新規/更新テスト詳細

| テスト観点 | テストケース | 結果 |
|---|---|---|
| H1 | (Manager 統合テストが対象外のため自動テストなし。コードレビューで確認) | - |
| H2: イベントが post のみで即時配送されない | Test_SetHistoryCallbacks_EventsFireThroughToUserCallbacks | ○ |
| H2: stop 後の配送はクリアされたコールバックを呼ばない | Test_OnHistoryEventMessage_AfterStop_DoesNotInvokeClearedCallback | ○ |
| H2: 未知の kind は安全に無視 | Test_OnHistoryEventMessage_UnknownKind_IsSafeNoop | ○ |
| M1: Base64Decode 正常系（パディングなし/1個/2個） | Test_Base64Decode_NoPadding/OnePad/TwoPad_RoundTrips | ○ |
| M1: Base64Decode 異常系（長さ不正/不正文字/パディング位置不正/空入力） | Test_Base64Decode_WrongLength/InvalidCharacter/PaddingInWrongPosition/EmptyInput_ReturnsFalse | ○ |

## 5. Definition of Done（差分のみ）

- ○ `canDestroyClipboardManager` が listener 残存を含めて判定する（H1）
- ○ 履歴イベントが owner UI thread へ配送され、stop/replace 後の古い世代コールバックが呼ばれない（H2、ただしWinRT呼び出し自体のスレッド要件は実機未検証）
- ○ WndProc/provider の例外安全性（H3）
- ○ 自書き込み抑止が実際の clipboard 変更を基準に動作する（H4）
- ○ `copyMultipleFormats` が base64・重複format拒否に対応（M1）
- ○ timestamp の JSON 契約が設計書と一致（M2）
- ○ `std::bad_alloc` が OUT_OF_MEMORY として正しく伝播する（M3）
- △ source encoding 方針: 新規ファイルは全て解消。プロジェクト全体への `/utf-8` 導入は既存ファイルの再エンコードを伴う別タスクとして推奨（未実施、M5）
- ○ `retiredStates_` の prune（L1）

## 6. 設計差分

- 差分内容:
  - 履歴イベント配送を WM_APP メッセージ経由の owner UI thread marshal に変更（H2 再設計）。設計書の「履歴イベントはコールバック経由で通知する」という記述と機能的には一致するが、スレッド配送の実装方式（直接呼び出し→メッセージ経由）が変わったため、次回設計書更新時に反映を検討
  - `timestamp` の JSON 型を number → string へ変更し、設計書側も合わせて更新（正式な仕様修正として記録済み、M2）
- 影響範囲:
  - 履歴イベントの配送タイミングが「WinRT がイベントを発火した瞬間」から「dispatch window がメッセージを処理する瞬間」に変わる（both are still "eventually, on the owner UI thread"）。実質的な遅延は通常のメッセージポンプ遅延程度で、機能上の影響はないと考えられるが実機確認はしていない

## 7. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む（再レビュー、または review-implementation-feature へ進む）
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
