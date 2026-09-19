# macOS Clipboard 機能実装レビュー v7

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`
- 最終修正差分: staged `git diff --cached`（9 files、+462 / -39）
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v8.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v6.md`
- T-18、MT-01〜MT-09、Swift 6 言語モード移行、develop から追跡済みの他の `xcuserdata` は対象外

## レビュー概要

- v6 の M-8 / M-9 / L-4 / L-5 / L-6 はすべて解消した。
- CT-17 は3境界すべてで予約 handle と start handle の一致を無条件に検査し、session teardown も状態条件で待つ。固定 sleep と条件付き `if let` は残っていない。
- `defaultObservationInterval` は安全な immutable `TimeInterval` として `nonisolated` が明示され、通常 clean test と CT-01 のどちらにも Clipboard 診断は出ない。
- MacLibrary と UnityMacPlugin の clean test、CT-01、設計機械照合、diff check をレビュー時に独立再実行し、すべて成功した。
- production / test code に新しい機能不具合、競合、ログ漏えい、設計逸脱は検出しなかった。
- 非ブロッキングな文書誤記が1件ある。実装結果 v8 の strict 診断内訳は Notification 53 ではなく 54 である。

## 前回指摘の解消状況

### M-8 [medium]: CT-17 の handle identity と cleanup 完了

**判定: 解消**

- `cancelJustAfterReservation()` は coordinator が登録中に保持する handle と repository start に渡された handle を比較し、start の実在も `#require` する（`mac/MacLibrary/MacLibraryTests/Clipboard/Manager/FilePromiseReceiveAsyncTests.swift:334-362`）。
- 3境界を巡回するテストでも `reservedHandle` と `startedHandles.first` の一致を無条件に検査し、各 session の消滅を確認する（同:410-451）。以前の `if let` による空振りはない。
- teardown 完了は5秒 deadline 付き `waitUntil` で状態を待ち、成立しなければ `Issue.record` で失敗する（同:454-473）。CT-17 の cleanup 用固定 sleep は除去された。
- レビュー時の clean test で CT-17 を含む全 MacLibrary test が成功した。

### M-9 [medium]: default argument の actor-isolation warning

**判定: 解消**

- `defaultObservationInterval` は `nonisolated public static let` となり、値型かつ immutable なので隔離解除による競合はない（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:70-79`）。
- なぜ default argument から参照する定数に `nonisolated` が必要か、英語 DocC に記録されている。
- レビュー時の通常 `clean test` と strict whole-module clean build の両方で、この箇所を含む Clipboard warning / error は0件だった。
- 同時に発見された test code の captured-var 診断は、lock 保護された `OutcomeLog` へ置換されている（`FilePromiseReceiveAsyncTests.swift:188-245`）。未使用変数も除去済み（`mac/MacLibrary/MacLibraryTests/Clipboard/Presentation/ClipboardPasteLoaderTests.swift:471-478`）。

### L-4 [low]: テスト件数の記録

**判定: 解消**

- 実装結果 v8 は宣言数と parameter 展開後の実行数を分離し、再現コマンドも `clean test` で固定した（`artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v8.md:92-102,129-155`）。
- レビュー時の source / xcresult と一致した。

### L-5 [low]: 設計書末尾の余分な空行

**判定: 解消**

- 末尾空行は削除され、`git diff --cached --check` と `git diff develop --check` はともに0件だった。
- 設計機械照合も22 / 22成功した。

### L-6 [low]: scope 外差分

**判定: 解消**

- 本ブランチで変更された iOS `UserInterfaceState.xcuserstate` は追跡解除されている。
- `ios/.gitignore` と `mac/.gitignore` の `xcuserdata/` は各 subtree 内の Xcode user data を任意深度で除外することを確認した。
- workflow / consistency script / `MIGRATION.md` の変更理由は実装結果 v8 に明記され、未整理の既存追跡ファイル15件も範囲外残作業として分離された（実装結果:108-125,190-195）。

## 重大な問題（high）

- なし。

## 改善提案（medium）

- なし。

## 軽微な指摘（low）

### L-7: strict 診断の領域別内訳が1件ずれている

- 実装結果 v8 は total 173件の内訳を Dialog 101 / Notification 53 / Share 18 とするが、合計は172になる（`artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v8.md:157-159`）。
- レビュー時に同じ path + message の unique 条件で再集計した結果は Dialog 101 / **Notification 54** / Share 18 / Clipboard 0 = 173だった。
- `artifact/MIGRATION.md:215-223` の詳細表も MacLibrary Notification 52 + UnityMacPlugin Notification 2 = 54を示す。
- 合否、Clipboard 0件、total 173件には影響しない。mergeを妨げない文書誤記として、53を54へ訂正することを推奨する。

## 設計書整合性チェック

- 企画書との整合性: ○
- Clean Architecture 準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: ○
- ドメインエラー全ケース実装: ○
- エラーコード／メッセージ対応表との整合: ○
- cancellation / exactly-once / timeout 契約: ○
- CT-17 の3境界検証: ○
- T-18 / 手動確認の未完了表示: ○
- `scripts/check_design_consistency.py`: 22 / 22成功

## プロジェクトルール適合チェック

- `common.md` 準拠: ○
- `mac.md` 準拠: ○
- エラー契約反映: ○
- 既存 API 互換性: ○
- Manager → UseCase → Repository: ○
- system delegate の一元所有: ○
- public DocC / HeaderDoc: ○
- Bridge payload 秘匿: ○
- Swift concurrency 診断: ○
- branch hygiene: ○

## テストカバレッジ

| 対象 | レビュー時の結果 |
|---|---|
| MacLibrary clean test | 宣言 437 / 実行 497 / 失敗 0 |
| UnityMacPlugin clean test | 宣言 80 / 実行 81 / 失敗 0 |
| 通常 clean test の Clipboard 診断 | 0件 |
| CT-01 strict whole-module clean build | `BUILD SUCCEEDED` |
| strict unique 診断 | 173件 / Clipboard 0件（Dialog 101 / Notification 54 / Share 18） |
| CT-17 | 3境界の identity / teardown を含め成功 |
| 設計機械照合 | 22 / 22成功 |
| `git diff --check` | 0件 |

未実施項目は設計どおり T-18 と実機確認 MT-01〜MT-09であり、今回の automated implementation review の LGTM を妨げない。

## 指摘一覧

| ID | Severity | 判定 | 内容 |
|---|---|---|---|
| M-8 | medium | 解消 | 3境界の handle identity と状態ベース cleanup 待機を実装。 |
| M-9 | medium | 解消 | actor-isolation 警告と test code の concurrency 診断を解消。 |
| L-4 | low | 解消 | 宣言数／実行数／再現コマンドを正規化。 |
| L-5 | low | 解消 | 設計書末尾と diff check を修正。 |
| L-6 | low | 解消 | user state を追跡解除し scope を説明。 |
| L-7 | low | 新規・非ブロッキング | strict 内訳の Notification 53 は54の誤記。 |

- critical: 0件
- high: 0件
- medium: 0件
- low: 1件（非ブロッキング）

## 総合評価

**LGTM**

v6 のブロッキング指摘はすべて解消され、production、回帰テスト、ビルド診断、設計照合、差分 hygiene の各条件を独立に再現できた。L-7 は合否や診断総数へ影響しない単純な内訳誤記であり、mergeを保留する理由にはしない。T-18 と実機確認は設計上の後続作業として継続する。
