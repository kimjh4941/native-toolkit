# macOS Clipboard 機能実装レビュー v6

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`（123 files、+31,541 / -19）
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v7.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v5.md`
- T-18（サンプルアプリ）、MT-01〜MT-09、Swift 6 言語モードへの移行は設計どおり対象外

## レビュー概要

- M-7 は解消した。BT-25 は C endpoint の signature から全 28 個の `const char*` 引数を抽出し、`stringWithFormat:` に限定せず全 22 個の `[Log ...]` 呼び出しを監査する。現行 production に平文 payload ログも確認されなかった。
- L-3 は解消した。OP-16 と callback 版 OP-18 から `@discardableResult` が除かれ、設計 §8.1 / §12.1 / T-08 / DoD も同じ適用集合になった。
- M-8 は改善したが部分解消に留まる。「登録中」と「登録直後」の開始点は状態または同期 hook で作られた一方、「予約直後」の同一 handle 検証が条件付きであり、cleanup 完了も固定 sleep に依存する。CT-17 の文言どおり 3 境界すべてを決定的に証明できていない。
- 新規に、通常の MacLibrary test build が Clipboard の actor-isolation 警告を 1 件出すことを確認した。規定の CT-01 strict whole-module build は警告なしで成功するが、同じ public API は Swift 6 言語モードではエラーになるため修正が必要である。
- テスト本体は成功した。レビュー時の xcresult では MacLibrary 437 tests / 0 failures、UnityMacPlugin 80 tests / 0 failures であり、結果レポートの 421 / 79 は古い件数である。

## 前回指摘の解消状況

### M-7 [medium]: C 層ログ監査が全 payload を保証しない

**判定: 解消**

- `endpointBodies()` は 19 endpoint を分離し、各 signature から payload 引数を抽出する（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift:235-254`）。
- `logCalls(in:)` は `[Log ` を起点に全形式を抽出し、未知の形式も捨てずに監査へ渡す（同:257-283）。
- `auditCoversEveryEndpoint()` は 19 endpoint、28文字列引数に加え、監査した Log 数とファイル内の全 Log 数が一致することを検査する（同:330-357）。現行実装では 22 / 22 呼び出しが対象となる。
- `noPayloadReachesLogRaw()` と `loggedArgumentsUseTheirHelper()` は全抽出ログを検査し、現行 production の文字列引数は `NTLen` または `NTScope` 経由である（同:285-321、`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.m:41-296`）。
- レビュー時に UnityMacPlugin のクリーン workspace test を実行し、BT-25 を含め成功した。

### M-8 [medium]: CT-17 の 3 境界が決定的に検証されていない

**判定: 部分解消**

改善した点:

- 「登録中」は `startReceivingFilePromises` 内の同期 hook から cancel し、開始 transaction 内の実行点を固定している（`FilePromiseReceiveAsyncTests.swift:236-257,337-357`）。
- 「登録直後」は `startCallCount` を `Task.yield()` で待ち、開始前の固定 sleep を除去している（同:359-378,418-425）。MainActor の直列実行により、待機側が再開した時点では同期 start は返却済みである。
- production は immutable な予約 handle を cancellation handler と UseCase start の両方へ渡す構造を維持している（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:670-707`）。新しい production race は確認されなかった。

残る問題:

- `cancelJustAfterReservation()` は task body の実行前に cancel して session 数だけを確認し、予約された handle または teardown に渡された handle を記録しない（テスト:320-335）。`repository` も検証に使われていない。
- `cancellationUsesTheReservedHandle()` は `startedHandles.first` が存在するときだけ session 消滅を検査する（同:380-415）。特に `beforeStart` は optional の `if let` なので、start が呼ばれない実装へ変化した場合には handle 同一性の assert が 0 件でも成功する。コメントの「same assertion at each of the three points」と実態が一致しない。
- cancel 後の cleanup 完了は 150〜200ms の固定 sleep のままである（同:333,351,374,409）。前回の修正条件に含めた signal / eventual condition による完了待ちは未実装で、負荷による flake の余地が残る。

修正条件:

- test-only spy または coordinator の観測 hook で、`reserveReceiptHandle()` が返した handle と `terminateReceiptWithoutDelivery(_:)` に渡された handle を各境界で必ず記録し、3 ケースすべてで equality を無条件に assert する。
- cleanup は固定 sleep ではなく、session 除去または teardown 呼び出しを状態条件で待つ。timeout 時は明示的にテストを失敗させる。

### L-3 [low]: `@discardableResult` の設計・実装不一致

**判定: 解消**

- OP-16 `provideFilePromise` と callback 版 OP-18 `receiveFilePromises` に `@discardableResult` はなく、handle を捨てた呼び出しへ警告を出す意図と一致する（`MacClipboardManager.swift:538-544,598-615`）。
- 設計 §8.1 は OP-16 / OP-18 を明示的に除外し、§12.1、T-08、DoD の集合も OP-01〜07 / OP-09〜11 に統一されている（設計書:1486,2173,2336,2485）。

## 重大な問題（high）

- なし。

## 改善提案（medium）

### M-8: CT-17 の予約直後 handle 同一性と cleanup 完了が未証明

前節のとおり、production の実装は妥当だが回帰テストが設計 CT-17 の全条件を決定的に保証していない。過去の mutable handle publication race を再発防止するテストなので、条件付き assert と固定 sleep を残したまま完了扱いにはできない。

### M-9: public default argument が Swift 6 で actor-isolation error になる

- `MacClipboardManager` は `@MainActor` のため、`defaultObservationInterval` も暗黙に main actor-isolated である（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:62-74`）。
- `startObserving` の default argument は nonisolated context からその property を参照する（同:502-504）。レビュー時の通常 `xcodebuild test` で次の診断を再現した。

  ```text
  warning: main actor-isolated static property 'defaultObservationInterval'
  can not be referenced from a nonisolated context; this is an error in the Swift 6 language mode
  ```

- 規定の CT-01 条件（Swift 5 + strict complete + whole-module + clean workspace build）では診断なしで成功したため、結果レポートの「CT-01 条件で Clipboard 由来 0 件」自体は再現できた。ただし通常 test build が feature code の警告を出し、設計冒頭の「Swift 6 でも通る書き方を選ぶ」という方針にも反する。

修正案: 定数を `nonisolated public static let` として明示するか、actor-isolated property を default argument から参照しない定数配置へ変更し、通常 test build と CT-01 build の両方で診断 0 件を確認する。

## 軽微な指摘（low）

### L-4: 実装結果 v7 のテスト件数が現行 suite と一致しない

- 結果レポートは MacLibrary 421件、UnityMacPlugin 79件とする（`artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v7.md:85-94`）。
- 現行 source の `@Test` 宣言はそれぞれ 437 / 80 件であり、レビュー時の xcresult も total 437 / 80、失敗 0 だった。parameter 展開込みの device 集計は 497 / 81 である。
- 合否の主張は正しいが、件数が古い。再現コマンド、件数の定義（宣言数または展開後 run 数）、xcresult の summary を結果レポートへ揃えること。

### L-5: `git diff --check` が設計書末尾の余分な空行を検出する

- `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md:2547` に `new blank line at EOF` がある。
- 機能影響はないが、merge 前に除去して diff check を通すこと。

### L-6: feature 差分に Clipboard 実装結果で説明されていないファイルが混在する

- `develop...HEAD` には `agent-rules/workflows/{design-feature,research-feature,review-document}/workflow.md`、`artifact/MIGRATION.md`、iOS workspace の `UserInterfaceState.xcuserstate` も含まれる。
- workflow / migration 更新が Clipboard 設計の再発防止として意図した変更なら、実装結果へ明記して scope を説明すること。少なくとも user-specific な iOS `xcuserstate` は macOS Clipboard の成果物ではないため merge 対象から外すこと。

## 設計書整合性チェック

- 企画書との整合性: ○
- Clean Architecture 準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △（M-8）
- ドメインエラー全ケース実装: ○
- エラーコード／メッセージ対応表との整合: ○
- OP-16 / OP-18 の `@discardableResult` 契約: ○
- CT-01 strict whole-module 条件: ○
- Swift 6 互換の実装方針: △（M-9）
- T-18 / 手動確認の未完了表示: ○
- `scripts/check_design_consistency.py`: 22 / 22通過

## プロジェクトルール適合チェック

- `common.md` の層・依存方向: ○
- Manager → UseCase → Repository 経路: ○
- Port の Domain 型制約: ○
- system delegate の Manager 層一元所有: ○
- `mac.md` の Bridge 型規約（BOOL / NSInteger / const char*）: ○
- callback / native API 併設と同期 control 例外: ○
- public DocC / HeaderDoc: ○
- ログ秘匿 production 実装: ○
- ログ秘匿回帰監査: ○
- Swift 6 互換性: △（M-9）
- branch hygiene: △（L-5 / L-6）

## テストカバレッジ・検証結果

| 対象 | レビュー時の結果 |
|---|---|
| MacLibrary | `xcodebuild test` 成功。xcresult total 437 / failed 0。ただし M-9 の warning 1件 |
| UnityMacPlugin | `MacWorkspace.xcworkspace` のクリーン DerivedData から成功。xcresult total 80 / failed 0 |
| BT-25 | 成功。19 endpoint / 28 payload 引数 / 22 Log 呼び出しを監査 |
| CT-17 | 4テスト成功。ただし M-8 の条件付き handle assert と固定 sleep が残る |
| strict concurrency | CT-01 の指定条件で `BUILD SUCCEEDED`、Clipboard 診断 0 件 |
| 設計整合スクリプト | 22 / 22成功 |
| `git diff --check` | 1件失敗（L-5） |

## 指摘一覧

| ID | Severity | 判定 | 内容 |
|---|---|---|---|
| M-7 | medium | 解消 | 全 Log 形式と signature 由来 payload 集合を監査する。 |
| M-8 | medium | 部分解消 | 予約直後の handle 同一性が条件付きで、cleanup が固定 sleep 依存。 |
| L-3 | low | 解消 | OP-16 / OP-18 の属性と設計記述を統一。 |
| M-9 | medium | 新規 | default argument の actor-isolation 警告。Swift 6 では error。 |
| L-4 | low | 新規 | 結果レポートのテスト件数が現行 suite より古い。 |
| L-5 | low | 新規 | 設計書末尾の余分な空行で diff check が失敗。 |
| L-6 | low | 新規 | workflow / migration / iOS user state の scope 外差分が未説明。 |

- critical: 0件
- high: 0件
- medium: 2件（M-8 / M-9）
- low: 3件（L-4〜L-6。解消済み L-3 を除く）

## 総合評価

**要修正（軽微）／マージ保留**

production の既知の機能不具合、C Bridge の平文ログ、`@discardableResult` 契約不一致は解消しており、全 automated test と設計機械照合も成功した。M-7 は今回で解消と判定できる。

残る M-8 は production 障害ではなく回帰テストの検出力、M-9 は Swift 6 移行前の actor-isolation 警告である。いずれも局所修正で解消できるが、CT-17 と通常ビルドの品質契約に関わるため merge 前に直すことを推奨する。L-4〜L-6を併せて整理し、MacLibrary test、UnityMacPlugin workspace test、CT-01 strict build、設計照合、`git diff --check` を再実行すれば最終判定できる。
