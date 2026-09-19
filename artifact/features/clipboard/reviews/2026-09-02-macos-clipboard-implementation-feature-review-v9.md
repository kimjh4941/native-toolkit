# macOS Clipboard 機能実装レビュー v9

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`
- 再レビュー差分: 未コミット working tree 13 files（+166 / -147）および実装結果 v10
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`（working tree で更新）
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v10.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implementation-feature-review-v8.md`
- §7.12 のスコープ変更根拠そのもの、T-18、手動確認、旧サンプル計画 v1 は前回同様に判定対象外

## レビュー概要

- v8 の H-1 は解消した。§11 の20ケースは実装の 1501〜1515 / 1521〜1524 / 1599 と一致し、新しい機械照合もケース単位で実装と比較する。
- H-2 は解消した。File Promise 専用 `HandleJson` を削除し、wire format を入力4 / 共用3 / 出力9 / event1 = 17型として実装・設計・BT-11で統一した。
- M-1 の public `isValidFileType`、M-4 の production DocC / HeaderDoc、L-1 の Bridge `.m` 末尾空行は実コード上解消した。
- M-2 は未解消である。設計書の現行テスト設計、タスク、リスク、DoDには、削除済み File Promise / receipt 契約が多数残っている。新設の `superseded counts removed` 検査は25 / 25を返すが、それらを検出しない。
- M-3 は一部解消した。宣言数と実行数を分離したが、UnityMacPlugin の展開後実行数は71ではなく72である。
- レビュー時に clean test と CT-01 strict whole-module build を再実行した。production code の新しいロジック不具合、競合、Bridge ABI破損、Clipboard由来 concurrency 診断は検出しなかった。

## 前回指摘の解消状況

| ID | 前回 severity | 判定 | 確認結果 |
|---|---|---|---|
| H-1 | high | 解消 | 設計の全エラーコードが実装と一致。実装由来の対応検査も追加。 |
| H-2 | high | 解消 | JSON shape 17型へ統一。死んだ Handle parser / encoder / test を削除。 |
| M-1 | medium | ほぼ解消 | public requirement、Data実装、専用テストを削除。mock property 1件のみ残存（L-2）。 |
| M-2 | medium | **未解消** | 現行章に削除済みテスト・リスク・DoDが多数残る（H-3）。 |
| M-3 | medium | **一部解消** | Mac件数は正しいが、Unityの展開後実行数が誤り（M-5）。 |
| M-4 | medium | 解消 | 指摘した4箇所の prose を現行契約へ更新。 |
| L-1 | low | 解消 | working treeを含む最終差分では末尾空行なし。 |

## 重大な問題（high）

### H-3: File Promise を削除した設計書の現行契約が、依然として File Promise の実装・テスト完了を要求している

- common.md 適用表は、存在しない `FilePromiseHandle` と `ReceiveFilePromisesUseCase` を現在の適合根拠にしている（`artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md:311-312`）。Bridge方針にも削除済み `releaseFilePromise` が残る（同:560）。
- §12.1 は `ClipboardError` を全25ケースとし、現在存在しない `quiet >= overall` を `ClipboardLimits` 境界値に含める。実装は20ケースで、limitsは warn / max / total の3値だけである（同:1561-1562、`mac/MacLibrary/MacLibrary/Clipboard/Domain/Model/ClipboardLimits.swift:13-42`）。
- §12.2 は `inFlightCount`、receipt reader、`overallTimeout`、file promise operation queue、snapshot stagingなど削除済み経路を IT-14 / IT-16〜18 / IT-21〜23 / IT-30 / IT-39 / IT-51〜52 として要求する（設計:1585-1597）。
- §12.4 は total 15 endpoint に対して「資源を生成しない16 endpoint」と記載し、受領 terminal、`sourcePath`、receive `onEvent` を BT-09 / BT-15 / BT-16 / BT-19 に残す（同:1623-1638）。createPasteboard だけが callback 必須なので、NULL許容 operation endpoint は14件である。
- T-16a は JSON実体を16型とし、File Promise staging / `sourcePath` をレビュー条件に残す（同:1693）。§14.1 の DV-04 / DV-05も File Promise lifecycle / timeout の要検証項目である（同:1739-1740）。
- §15 は「File Promise完了条件25件を本リストから削除した」と宣言する一方、`OP-16 async throws` を実装済みDoDとして残し、削除済み範囲の IT-21〜53 / CT-17 を全通過とする（同:1795-1809）。設計を実装完了判定や後続サンプル設計へ使えない状態である。
- 新しい `superseded counts removed` は current state を実装から導出せず、過去に見つかった8個の文字列だけを deny-list にしている（`scripts/check_design_consistency.py:56-64,297-313`）。そのため `16 endpoint`、`実体 16 JSON 型`、`全 25 ケース`、File Promise の意味を別名で書いたテスト行をすべて見逃し、25 / 25が false green になっている。

**修正方針**

- §2.1 の対象外表、§7.12 の実測、§0の変更履歴以外の現行契約から、File Promise提供・受領・receipt・staging専用記述を除去する。
- §12 の test ID、§13 のタスク完了条件、§14 のDV、§15 のDoDを、現存する production / test symbolから再構成する。単に今回見つかった文字列を `STALE_FIGURES` へ追加するだけでは同じ問題が再発する。
- checkerは、エラーコードと同様に可能な範囲で実装・テストから件数と名前を導出する。少なくとも設計冒頭の canonical count（20 errors / 17 JSON / 15 endpoints / callback NULL許容14）と現行章の数値を比較し、許容する履歴・実測セクションを章単位で限定する。

## 改善提案（medium）

### M-5: UnityMacPlugin の展開後実行数は71ではなく72

- 実装結果 v10 は UnityMacPlugin を宣言71 / 実行71と記載する（`artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v10.md:115-118`）。
- レビュー時の source は `@Test` 71宣言で一致したが、xcresult は `totalTestCount: 71`、device configuration の `passedTests: 72` だった。`namedScopeRequiresName(kind:)` が2引数へ展開されるためである（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardJsonParserTests.swift:85-90`）。
- 正しい記録は MacLibrary 302 / 346、UnityMacPlugin 71 / **72**、失敗0。v9の実行74から削除した handle test 2件を引いても72になる。§4と§4.1を訂正する必要がある。

## 軽微な指摘（low）

### L-2: M-1由来の未使用mock propertyが残っている

- `MockClipboardTypeIdentifierValidating.invalidFileTypeIdentifiers` は `isValidFileType` とともに不要になったが、propertyだけ残っている（`mac/MacLibrary/MacLibraryTests/Clipboard/Mock/MockClipboardTypeIdentifierValidating.swift:20`）。参照は0件なので削除する。

### L-3: 実装結果に記載したdiff checkコマンドは現在の状態では0件にならない

- 実装結果は `git diff develop...HEAD --check` が0件とする（実装結果 v10:125）。しかし修正は未コミットなので、このコマンドはコミット `78203ef9` 側の末尾空行を検査し、現在も1件を返す。
- working treeを含めた最終状態を検査する `git diff develop --check` と `git diff --check` は0件だった。修正をcommitした後は記載どおり `develop...HEAD` でも0件になる。現時点の再現コマンドとしては `git diff develop --check` を記載する。

## 設計書整合性チェック

- 企画書との整合性: ○（File Promiseをv1対象外とする判断は明記済み）
- Clean Architecture 準拠: ○（実装） / ×（設計の適合説明に削除済み型・UseCaseが残る）
- 既存実装との差分分析の正確性: △（主要コード削除は正確だが「全7件反映」「M-2解消」は不正確）
- テスト設計の網羅性: ×（実在しないFile Promiseテストを多数要求）
- ドメインエラー全ケース実装: ○
- エラーコード／メッセージ対応表との整合: ○
- JSON wire format 17型: ○
- 公開 OP 16 / Bridge endpoint 15 / UseCase 14 / Port 3: ○
- `scripts/check_design_consistency.py`: 25 / 25成功。ただしH-3を検出できず、合格判定として不十分

## プロジェクトルール適合チェック

- `common.md` 準拠: ○（実装）
- `mac.md` 準拠: ○
- エラー契約反映: ○
- 既存 API 互換性: ○
- Manager → UseCase → Repository: ○
- system delegate / loader の一元所有: ○
- public DocC / HeaderDoc: ○
- Bridge payload秘匿・入力検証: ○
- セキュリティ上の新規問題: なし

## テストカバレッジ

| 対象 | レビュー時の結果 |
|---|---|
| MacLibrary clean test | 宣言302 / parameter展開後346 / failed 0 |
| UnityMacPlugin clean test | 宣言71 / parameter展開後72 / failed 0 |
| 通常 clean testのClipboard診断 | 0件 |
| CT-01 strict whole-module clean build | `BUILD SUCCEEDED` / Clipboard由来診断0件 |
| 設計機械照合 | 25 / 25成功。ただしH-3のfalse greenあり |
| productionの `FilePromise` / `Receipt` 実行シンボル | 0件 |
| combined final diff check | `git diff develop --check` 0件 |

- H-1の固定コード比較とH-2のsource-derived JSON inventory testは意図した破損を検出できる構造になった。
- clean testとstrict buildはすべて成功しており、今回変更したproduction codeに実行時の回帰は検出しなかった。
- T-18、手動確認、旧サンプル計画 v1は既知の後続作業として新規指摘に数えない。

## 指摘一覧

| ID | Severity | 内容 |
|---|---|---|
| H-3 | high | 現行設計・テスト・DoDに削除済みFile Promise契約が多数残り、25/25検査がfalse green。 |
| M-5 | medium | UnityMacPluginの展開後実行数は71ではなく72。 |
| L-2 | low | `invalidFileTypeIdentifiers` mock propertyが未使用のまま残存。 |
| L-3 | low | 未コミット状態では実装結果記載の`develop...HEAD --check`を再現できない。 |

- critical: 0件
- high: 1件
- medium: 1件
- low: 2件

## 総合評価

**要修正（重大）**

production codeに関するv8のブロッキング指摘は解消し、clean test、strict build、エラーコード、JSON wire format、Bridge ABIは良好である。しかしM-2の削除は大幅に未完了で、設計書が存在しないFile Promise実装・テストを現行契約として要求しながら25 / 25で合格している。H-3を解消し、M-5 / L-2 / L-3を整えた後に再確認が必要である。
