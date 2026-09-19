# macOS Clipboard 機能実装レビュー v8

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`（115 files、+32,632 / -19）
- スコープ変更コミット: `78203ef9`（File Promise 4 操作の削除）
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v9.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v7.md`（LGTM）
- ユーザー指定に従い、§7.12 のスコープ変更根拠そのもの、T-18、手動確認、旧サンプル計画 v1 は判定対象外

## レビュー概要

- File Promise の実行経路、型、4 Bridge endpoint、receipt callback typedef、専用 UseCase / test file の削除は概ね完了している。production code に `FilePromise` / `Receipt` を名前に含む実行シンボルは残っていない。
- 現在の実数は公開 OP 16、Bridge endpoint 15、UseCase 14、Port 3 で、設計書冒頭の宣言と一致する。
- `ClipboardSystemCoordinator` を paste loader と lazy data provider の所有者として縮小して残した判断は正しい。OP-01 の遅延データ提供と OP-19 の view lifetime / cancel に必要な状態だけが残り、File Promise の staging、receipt、stale 監視は残っていない（`mac/MacLibrary/MacLibrary/Clipboard/Manager/ClipboardSystemCoordinator.swift:9-108`）。
- `ClipboardError` 実装は 1516〜1520 を欠番にし、1521〜1524 と 1599を維持している。この実装判断は正しい（`mac/MacLibrary/MacLibrary/Clipboard/Domain/Error/ClipboardError.swift:64-84`）。
- clean test はレビュー時の再実行でも MacLibrary 357 passed / 0 failed、UnityMacPlugin 74 passed / 0 failedだった。
- 一方、設計書の公開エラーコード表と Bridge JSON schema は現在の実装と一致せず、削除済み File Promise 契約を参照する現行テスト設計・Port API・DocC も残っている。22 / 22 の機械照合はこれらを検出していない。

## 重大な問題（high）

### H-1: 設計書の公開エラーコード表が実装および「番号を動かさない」方針と矛盾している

- 設計書は 1516〜1520 を欠番にし、1521 以降を動かさないと明記している（`artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md:42-43`）。
- しかし §11 は `emptyContent`〜`detectionFailed` を 1496〜1510、`pasteLoadFailed`〜`cancelled` を 1516〜1519、`unknown` を 1594 と記載している（同:1509-1528）。これでは 1516〜1520 が欠番にならず、既存コードも5ずつ移動する。
- 実装は `emptyContent == 1501`、`detectionFailed == 1515`、`pasteLoadFailed == 1521`、`cancelled == 1524`、`unknown == 1599` であり、互換性を保つ正しい割り当てである（`ClipboardError.swift:64-84`）。テストも 1501 / 1511 / 1523 / 1524 / 1599 を固定している（`mac/MacLibrary/MacLibraryTests/Clipboard/Domain/ClipboardErrorTests.swift:93-99`）。
- Bridge 利用者が設計書を正として実装すると、全ドメインエラーを誤解釈する。§11 を実装の割り当てへ戻し、機械照合に「ケース名 → 固定コード」の完全対応検査を追加する必要がある。

### H-2: Bridge JSON schema が設計 16 型、実装 18 型、テスト 20 型の三つに分裂している

- 設計 §8.4.4 は入力4 + 共用4 + 出力7 + event1 = 16 型とするが、共用に削除対象だった `HandleJson` を残し、出力から実際に使う `AccessBehaviorJson` を落としている（`artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md:1258-1265`）。同じ設計の endpoint 表は `clipboardAccessBehavior` の戻り値を `AccessBehaviorJson` としている（同:1231-1232）。
- 実装は未使用の `HandleJson` / `parseHandleId` / `encodeHandle` とその専用テストを残している一方、設計の inventory にない `ScopeResultJson` と `AccessBehaviorJson` を持つ。`createPasteboard` は設計の `ScopeJson` 直返しではなく `{"scope": ...}` の `ScopeResultJson` を encode する（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardJsonParser.swift:56-58,218-225,357-360,385-387,434-441`、設計:1213-1214）。したがって実装上の top-level shape は18型である。
- production DocC は旧20型のままである（`UnityMacClipboardJsonParser.swift:9-19`）。さらに BT-11 は実在する型を列挙せず、削除済み `FilePromiseRequestJson` / `PolicyJson` / `ReceiptEventJson` を単なる文字列として並べて20件を確認しているため、実装と無関係に成功する false green になっている（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardJsonParserTests.swift:22-42`）。
- C# 側が依存する wire shape の契約を一つに確定する必要がある。設計の「16型」と `createPasteboard -> ScopeJson` を正とするなら、`HandleJson` と `ScopeResultJson` を削除し、集合を入力4 / 共用3（Scope / Ownership / Patterns）/ 出力8（AccessBehavior を追加）/ event1へ直すと16型になる。別の wire shape を意図するなら、その形と件数を設計へ明記する。いずれの場合も BT-11 は実型の encode/decode または型ごとの fixture を参照し、削除済み型名だけでは通らない検査にする。

## 改善提案（medium）

### M-1: File Promise 専用の公開 Port API と実装・テストが残っている

- `ClipboardTypeIdentifierValidating` は public requirement として「promised file」を判定する `isValidFileType` を残している（`mac/MacLibrary/MacLibrary/Clipboard/Application/Port/ClipboardTypeIdentifierValidating.swift:13-22`）。
- Data 実装も `public.data` / `public.directory` への適合判定を残すが、production caller はなく、現在は mock と File Promise 固有テストからしか参照されない（`mac/MacLibrary/MacLibrary/Clipboard/Data/Repository/ClipboardTypeIdentifierValidator.swift:73-80`、`mac/MacLibrary/MacLibraryTests/Clipboard/Data/ClipboardTypeIdentifierValidatorTests.swift:147-169`）。
- 名前に `FilePromise` が含まれないため単純な残存検索を通過しているが、削除対象の公開契約である。requirement、実装、mock、専用テストをまとめて削除すべきである。

### M-2: 設計書の現行テスト設計・タスク・完了条件に削除済み契約が残っている

- §12.1 は `CancelReceiveFilePromisesUseCase` と `ProvideFilePromiseUseCase` を現在のテスト対象として残す（`artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md:1556,1560`）。
- §12.4 は受領 terminal、19 endpoint、20 JSON型など旧 BT-09〜BT-17 を残す（同:1629-1635）。T-06b のレビュー条件にも `CancelReceiveFilePromisesUseCase` が残る（同:1684）。
- §15 の過去チェック項目にも公開 OP 20 / Bridge 19、全19 endpoint、File Promise 状態機械が「現行の達成済み条件」として残る（同:1767-1771）。履歴として残すなら変更履歴へ移し、現行テスト設計・タスク・DoD からは除外または v9 で廃止済みと明示するべきである。
- `check_design_consistency.py` は22 / 22を返すが、これらの旧 ID / 型名 / 件数を検出しない。変更履歴だけを除外したうえで、現行章に `FilePromise` / `Receipt`、19 endpoint、20 JSON型などが再出現しない検査を追加する必要がある。

### M-3: 実装結果 v9 がテスト宣言数と展開後実行数を再び混同している

- 実装結果は 357 / 74 を「宣言」と記載する（`artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v9.md:89-96`）。実際の `@Test` 宣言は `rg -n '@Test'` で MacLibrary 305、UnityMacPlugin 73である。
- レビュー時の xcresult は parameter 展開後の passed tests が 357 / 74、base test count が 305 / 73だった。従って clean test の合否値は正しいが、§3.1 のラベルと「削除した80件」の導出は正しくない。
- v8 で定義した「宣言数 / 展開後実行数」を維持し、v9 は MacLibrary 305 / 357、UnityMacPlugin 73 / 74 と記録するべきである。削除件数も同じ基準同士で再計算する必要がある。

### M-4: 削除済み File Promise / receipt を説明する production DocC が残っている

- `BridgeError` は NULL callback の資源例として file promise registration と receive session を列挙している（`mac/MacLibrary/MacLibrary/Notification/Domain/Error/BridgeError.swift:19-24`）。現在該当する Clipboard endpoint は unique pasteboard のみである。
- `GetChangeCountUseCase` は coordinator の stale check と file promise change count を用途として残す（`mac/MacLibrary/MacLibrary/Clipboard/Application/UseCase/GetChangeCountUseCase.swift:8-15`）。現在の caller は change monitor だけである。
- Unity facade の section MARK も `file promises` のままである（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift:288`）。Bridge header は create endpoint が返す値を「handle」と呼ぶが、実際には scope JSON である（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.h:13-18`）。
- 実行ロジックへの影響はないが、今回重点指定された DocC / Bridge prose と実装の一致を満たしていないため更新が必要である。

## 軽微な指摘（low）

### L-1: develop 基準の diff check が1件失敗する

- `git diff --check develop...HEAD` は `mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.m:246: new blank line at EOF.` を報告する。
- 末尾の余分な空行を削除する。

## 設計書整合性チェック

- 企画書との整合性: ○（スコープ変更と根拠は §7.12 に明示。根拠自体は今回の判定対象外）
- Clean Architecture 準拠: ○
- 既存実装との差分分析の正確性: △（主要削除と件数は一致するが、Port / DocC / JSON test の残存とテスト件数に誤り）
- テスト設計の網羅性: ×（削除済み契約が残り、BT-11 が false green）
- ドメインエラー全ケース実装: ○
- エラーコード／メッセージ対応表との整合: ×（実装は正しいが設計表が全面的にずれている）
- 公開 OP 16 / Bridge endpoint 15 / UseCase 14 / Port 3: ○
- lazy data provider / paste loader の保持: ○
- File Promise / receipt 実行経路の削除: ○
- `scripts/check_design_consistency.py`: 22 / 22成功。ただし H-1 / H-2 / M-2 を検出できない

## プロジェクトルール適合チェック

- `common.md` 準拠: △（依存方向は適合。不要な public Port requirement と stale DocC が残る）
- `mac.md` 準拠: ○
- エラー契約反映: ×（runtime は互換だが設計上の公開対応表が不一致）
- 既存 API 互換性: ○（残存 API の番号は維持。4操作の削除は明示的スコープ変更）
- Manager → UseCase → Repository: ○
- system delegate / loader の一元所有: ○
- Bridge endpoint / callback 数: ○
- public DocC / HeaderDoc: △
- Bridge payload 秘匿・入力検証: ○
- セキュリティ上の新規問題: なし

## テストカバレッジ

| 対象 | レビュー時の結果 |
|---|---|
| MacLibrary clean test | 宣言 305 / parameter 展開後 357 passed / failed 0 |
| UnityMacPlugin clean test | 宣言 73 / parameter 展開後 74 passed / failed 0 |
| 設計機械照合 | 22 / 22成功。ただし契約の実装照合には不足 |
| 公開 OP / Bridge / UseCase / Port 件数 | 16 / 15 / 14 / 3 を確認 |
| production の `FilePromise` / `Receipt` 実行シンボル | 0件 |
| `git diff --check develop...HEAD` | 1件失敗（L-1） |

- lazy data provider の登録・解放・lookup と paste loader の cancel / view lifetime は回帰テストが残っており、削り過ぎは検出しなかった。
- エラーコードの spot check は実装を正しく固定しているが、設計表との機械比較がない。
- JSON inventory test は削除済み型名の文字列だけで成功するため、Bridge schema の回帰を検出できない。
- T-18、手動確認、旧サンプル計画 v1 はユーザー指定どおり既知の後続作業として扱い、新規指摘には数えない。

## 指摘一覧

| ID | Severity | 内容 |
|---|---|---|
| H-1 | high | 設計のエラーコード表が互換性方針および正しい実装と矛盾。 |
| H-2 | high | Bridge JSON schema が設計16、実装18、テスト20に分裂し、BT-11が false green。 |
| M-1 | medium | File Promise 専用の public `isValidFileType` requirement が残存。 |
| M-2 | medium | 現行テスト設計・タスク・DoD に削除済み File Promise 契約が残存。 |
| M-3 | medium | 実装結果がテスト宣言数と展開後実行数を混同。 |
| M-4 | medium | production DocC / HeaderDoc に削除済み契約が残存。 |
| L-1 | low | Bridge `.m` の末尾空行で develop 基準 diff check が失敗。 |

- critical: 0件
- high: 2件
- medium: 4件
- low: 1件

## 総合評価

**要修正（重大）**

File Promise の主要実装削除、残すべき coordinator 機能、公開 OP / Bridge / UseCase / Port の実数、エラーコードの runtime 互換性、clean test は良好である。しかし、公開エラーコード表と Bridge JSON wire contract が現在の実装を正しく表しておらず、削除済み型を文字列で数えるテストが false green になっている。利用者側契約を誤らせる H-1 / H-2 を解消し、M-1〜M-4 の削除残存を整理したうえで再レビューが必要である。
