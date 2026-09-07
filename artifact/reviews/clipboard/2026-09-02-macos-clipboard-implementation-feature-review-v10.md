# macOS Clipboard 機能実装レビュー v10

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`
- working tree: 未コミット変更を含む現在状態
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v11.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implementation-feature-review-v9.md`
- スコープ: File Promise 4 操作（OP-16 / OP-17 / OP-18 / OP-20）を v1 対象外にした後の削除完了性。§7.12 の実測根拠そのもの、T-18、手動確認、旧サンプル計画 v1 は判定対象外

## レビュー概要

- v9 の M-5 / L-2 / L-3 は解消している。UnityMacPlugin の実行数は xcresult で 72、`invalidFileTypeIdentifiers` は削除済み、working tree を含む `git diff develop --check` も 0 件だった。
- production code から File Promise / Receipt 系の実行シンボルは見つからなかった。lazy data provider（OP-01 の内部機構）と paste loader（OP-19）は、削り過ぎず残すべきものとして残っている。
- エラーコード 1516〜1520 を欠番のまま残し、1521 以降を動かさない判断は実装・設計とも一致している。
- ただし v9 の H-3 はまだ完全には閉じていない。現行設計の JSON schema サンプル、並行性テスト、タスク完了条件、DoD に、削除済み File Promise 時代の契約または存在しないテスト範囲が残っている。`scripts/check_design_consistency.py` は 26 / 26 を返すが、この残存を検出できない。
- コード本体の clean test / strict build は成功した。新しいロジック不具合や Clipboard 由来の strict concurrency failure は検出していない。

## 前回指摘の解消状況

| ID | 前回 severity | 判定 | 確認結果 |
|---|---|---|---|
| H-3 | high | **一部未解消** | 大半は削除されたが、現行 JSON schema / CT / DoD / task 範囲に削除済み契約が残る（H-4）。 |
| M-5 | medium | 解消 | xcresult で UnityMacPlugin は宣言 71 / 実行 72 / failed 0。 |
| L-2 | low | 解消 | `MockClipboardTypeIdentifierValidating.invalidFileTypeIdentifiers` は削除済み。 |
| L-3 | low | 解消 | v11 は `git diff develop --check` を再現コマンドとして記載。手元でも 0 件。 |

## 重大な問題（high）

### H-4: File Promise 削除後の現行設計・DoD に、まだ削除済み契約と存在しないテスト範囲が残っている

- §8.4.4 は JSON shape を実体 17 型に確定し、`HandleJson` は削除したと説明しているが、直後の「JSON schema（全型）」サンプルに `// HandleJson (required: id)` と `{ "id": ... }` が残っている（`artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md:1265-1300`）。実装側の `UnityMacClipboardJsonParserTests.seventeenConcreteTypes()` は `HandleJson` が含まれないことを検査しているため、設計サンプルだけが現行 wire format と矛盾している。
- §12.5 の CT-09 / CT-10 / CT-15 / CT-17 は、nonisolated delegate の状態更新、解放予約、terminal と `CancellationError` の競合、handle 登録中 cancel と session 残留を検証するとしている（同:1640-1643）。これらは OP-16 / OP-18 / OP-20 の File Promise lifecycle 用語であり、現在の production code には該当する File Promise / Receipt 実装がない。
- T-16b の完了条件は `BT-12〜BT-19` を要求するが、§12.4 の現行 Bridge テスト表は BT-12 の次が BT-17 で、BT-13〜BT-16 / BT-18 / BT-19 が存在しない（同:1612-1629、1678）。範囲表記を読む限り、実在しないテストの全通過を要求している。
- §15 の実装完了条件に、削除したはずの `OP-16 が async throws で、.snapshot のコピーが MainActor 外で実行される` が残っている（同:1774-1784）。同じ DoD には `IT-21〜IT-53` 全通過も残るが、§12.2 の現行 IT は IT-01〜IT-11 / IT-20 / IT-50 のみで、範囲内の大半が存在しない（同:1571-1586、1786-1788）。
- `scripts/check_design_consistency.py` はこの状態でも 26 / 26 OK を返す。原因は、現行契約の検査が backtick 内の `\w{6,}` 識別子と `全 N endpoint` / `実体 N 型` に寄っており、`OP-16` のようなハイフン付き ID、範囲表記、JSONC コメント内の `HandleJson`、非 backtick の意味的な File Promise 残骸を拾えないためである（`scripts/check_design_consistency.py:334-365`）。

**修正方針**

- 現行章から `HandleJson` の schema サンプル、File Promise lifecycle 由来の CT-09 / CT-10 / CT-15 / CT-17、削除済み OP-16 の DoD、存在しない IT / BT 範囲を削除または現存 ID に置き換える。
- checker は live lines に出る OP ID、IT/BT/CT/PT の範囲表記、JSONC コメントの shape 名も対象にする。特に「表に存在しない ID を範囲で要求していないこと」は今回の false green を直接捕まえる検査にできる。

## 改善提案（medium）

### M-6: `MacClipboardManager` の公開 DocC が native API の同期/非同期契約を誤って説明している

- `MacClipboardManager` の型 DocC は `Every operation has a native async throws form.` と書いている（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:21-25`）。
- 実際の設計と実装では、OP-12〜OP-15 と OP-19 は common.md の即時 control / factory 例外で同期 API である（設計:1004-1015、実装:472-493、501-512、534-537）。
- 同じ DocC 内に `Immediate control operations are synchronous` もあるため、文書内で矛盾している。public API 利用者向けの契約なので、「OP-01〜OP-11 は native async throws、即時 control / factory は同期」の形へ直すべき。

## 軽微な指摘（low）

### L-4: 機械照合の説明が v11 の実体 26 検査まで更新されていない

- §15 は `scripts/check_design_consistency.py` による機械照合を「全 22 検査」としている（`artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md:1735`）。
- §16.1 の検査項目表も 10 分類のままで、v11 で追加・差し替えた 26 検査の実体、特に `named symbols exist in the implementation` と `quoted counts match the declarations` が説明されていない（同:1810-1825）。
- 実装結果 v11 は 26 / 26 と書いており、実行結果もその通りなので、設計側の説明だけが古い。重大ではないが、次のレビュー時に検査の期待値を読み違えやすい。

## 設計書整合性チェック

- 企画書との整合性: ○（File Promise を v1 対象外とする判断と §7.12 の根拠は明記済み）
- Clean Architecture 準拠: ○（実装）
- 既存実装との差分分析の正確性: △（実装側の削除は正しいが、設計 DoD / CT / schema に残骸あり）
- テスト設計の網羅性: △（現存機能の主要テストは通るが、存在しない ID 範囲と File Promise CT が残る）
- ドメインエラー全ケース実装: ○
- エラーコード／メッセージ対応表との整合: ○
- JSON wire format 17型: ○（実装） / △（設計 schema サンプルに `HandleJson` 残存）
- 公開 OP 16 / Bridge endpoint 15 / UseCase 14 / Port 3: ○
- `scripts/check_design_consistency.py`: 26 / 26 成功。ただし H-4 を検出できず、現行契約の合格判定としてはまだ不足

## プロジェクトルール適合チェック

- `common.md` 準拠: ○（実装）
- `mac.md` 準拠: ○（実装） / △（public DocC の同期/非同期説明）
- エラー契約反映: ○
- 既存 API 互換性: ○
- Manager → UseCase → Repository: ○
- system delegate / loader の一元所有: ○
- public DocC / HeaderDoc: △（M-6）
- Bridge payload秘匿・入力検証: ○
- セキュリティ上の新規問題: なし

## テストカバレッジ

| 対象 | レビュー時の結果 |
|---|---|
| MacLibrary clean test | 成功。xcresult: 宣言302 / parameter展開後346 / failed 0 |
| UnityMacPlugin clean test | 成功。xcresult: 宣言71 / parameter展開後72 / failed 0 |
| CT-01 strict whole-module clean build | `BUILD SUCCEEDED` |
| 設計機械照合 | 26 / 26 成功。ただし H-4 の false green あり |
| production の `FilePromise` / `Receipt` 実行シンボル | 0件 |
| final diff check | `git diff develop --check` 0件 |

補足: 最初に MacLibrary と UnityMacPlugin の clean test を並列実行したところ、MacLibrary 側だけ DerivedData の `build.db` disk I/O error で失敗した。UnityMacPlugin 完了後に MacLibrary を単独再実行すると成功したため、コード不具合ではなく同一 DerivedData への並列 clean/test 競合として扱った。

## 指摘一覧

| ID | Severity | 内容 |
|---|---|---|
| H-4 | high | File Promise 削除後の現行設計・DoDに `HandleJson`、File Promise CT、存在しない IT/BT 範囲、OP-16 DoD が残り、26/26 検査が false green。 |
| M-6 | medium | `MacClipboardManager` の public DocC が「全 operation に native async throws がある」と誤説明している。 |
| L-4 | low | 設計書の機械照合説明が v11 の 26 検査に追随していない。 |

- critical: 0件
- high: 1件
- medium: 1件
- low: 1件

## 総合評価

**要修正（重大）**

コード本体、Bridge ABI、エラーコード、JSON parser、テスト実行値は良好で、v9 の M-5 / L-2 / L-3 は閉じている。ただし v9 H-3 の根はまだ残っており、設計書が削除済み File Promise 契約と存在しないテスト範囲を現行 DoD として保持したまま、機械照合が 26 / 26 で通っている。H-4 を解消し、M-6 / L-4 を整えた後に再確認が必要。
