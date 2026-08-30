# レビュー結果（第6回）

- 日付: 2026-08-29
- 対象ファイル: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v6.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-29-macos-clipboard-design-review-v5.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降
- レビュー方法: 設計書全文、企画書 v3、前回レビュー、`common.md` / `mac.md`、既存 macOS 実装、および別エージェントによる独立レビューの照合

---

## 結論

v6 は `CommitReleaseOutcome`、provisional registration、silent receipt rollback、Bridge OP-16 の `scopeJson` を導入し、v5 の主要問題を改善した。

一方、OP-16 の正規契約には旧 transaction とレイヤー表の矛盾が残り、snapshot transaction の実行主体、stale 判定の現在値取得、集約 async の登録前キャンセルが未確定である。これらは実装者の裁量で補うと依存方向、キャンセル、資源寿命が変わるため、判定は **要修正** とする。

前回13件の反映判定は **8件解消、5件一部解消**。全面実装の前に高優先度4件を一本化する必要がある。

## 強み

- `CommitReleaseOutcome` により、`.writer` の正常解放と解放予約無効を区別できるようになった。
- provisional registration と `activateFilePromise(handle:ownership:)` の二段階化により、pasteboard write 成功後だけ stale 監視へ移るモデルになった。
- `discardReceiptAfterStartFailure` を公開 cancel から分離し、開始失敗時のイベント0件契約を表現した。
- generation identity を持つ二段階 release claim は、古い予約が新しい予約を消す競合を扱えている。
- Bridge OP-16 の `scopeJson`、event callback の NULL 契約、排他的な JSON shape 20型の集合は前版より明確になった。
- File Promise、Bridge、並行性のテスト観点が広く、企画書の RK-21〜RK-23を概ね追跡できている。

## 改善点

### 高優先度

#### 1. OP-16 の正規契約がまだ分裂している

- 対象: §3、§4、§7.12、§8.1〜§8.4.5、§9（259、274、1066〜1075、1282、1326〜1328、1625〜1632、1665行付近）
- 問題:
  - 274行は OP-16 を同期 factory としている。
  - 1066〜1075行に、削除済みとした旧 `registerFilePromise(request) -> handle` transaction が残っている。
  - 正式 Port の `ClipboardRepository.writeFilePromise` は同期 `throws` だが、§9 は Repository を `async throws` としている。
  - §8.1 は Manager callback 版を定義しているが、§9 の OP-16 は Manager callback を「なし」としている。
  - §8.4.5 は `.snapshot(URL)` 導入後も「`write` クロージャを合成する」と記述している。
- 改善: §7.12 の新 transaction だけを残し、全章を次へ統一する。
  - Repository: 同期 `throws`
  - UseCase: snapshot I/O を含むため `async throws`
  - Manager callback: あり
  - Manager native: `async throws`
  - Bridge: callback
  - delegate: `FilePromiseSource` を switch

#### 2. snapshot transaction の実行主体・DI・late cleanup が接続されていない

- 対象: §6.5.1、§7.12、§8.4.5、T-02、T-11a〜T-11c（505、1012〜1019、1041〜1064、1629〜1634、1927、1936〜1938行付近）
- 問題:
  - DI は snapshotter を coordinator に保持させる一方、正規 transaction の実行主体を定めていない。
  - coordinator は Repository を保持しないため、snapshot → register → repository write → activate を単独で完結できない。
  - `stagingRoot(handle)` の提供者と API がない。
  - 外側の `Task.checkCancellation()` がコピー完了後のキャンセルを検出しても、完成 staging を破棄する API が `FilePromiseSnapshotting` にない。
  - T-02 は Port を3種としており、4番目の `FilePromiseSnapshotting` と Mock を追跡していない。
- 改善: `ProvideFilePromiseUseCase` を transaction の唯一の実行主体にし、Repository、Registry、Snapshotter を注入する。staging root の取得契約、完成 snapshot の破棄責務、`MockFilePromiseSnapshotter` も明示する。

#### 3. stale tick が現在の `changeCount` を取得できない

- 対象: §6.5〜§6.5.1、§7.12、§8.2（491〜505、887、932〜936、978〜980、1319行付近）
- 問題: lifecycle state は activation 時の `PasteboardOwnership` を保持するが、比較対象となる現在の `changeCount` を取得する経路がない。Repository は `changeCount(scope:)` を持つ一方、coordinator は Repository を保持しないと明記されている。
- 影響: RK-21 の所有権喪失による自動解放を実装できない。coordinator が直接 `NSPasteboard` を読むと Manager → UseCase 規約および Repository への変換集約に反する。
- 改善: stale 判定専用 UseCase、または `@MainActor` query closure を coordinator に注入する。循環を作らない初期化順序と、tick → query → `requestRelease()` の経路を定義する。

#### 4. 集約 async のキャンセルに receipt handle 公開前の race が残る

- 対象: §7.12.4（1222〜1252行付近）
- 問題: `ReceiptCompletionGate` は continuation の二重 resume を防ぐが、`onCancel` が receipt handle の登録・代入前に走る場合を扱わない。mutable handle を concurrent closure で捕捉する実装は Swift 6 の Sendable 警告も招き得る。
- 影響: cancel は `CancellationError` を返しても、後から開始した receipt session が cancel されず残留する可能性がある。
- 改善: immutable handle を先に得てから cancellation handler を設置する構造にするか、handle publication と pending cancel を lock 保護する operation state を追加する。開始直前・登録中・登録直後のキャンセルテストを追加する。

### 中優先度

#### 5. stream の `onTermination` が配送付き公開 cancel を流用している

- 対象: §7.12.3〜§7.12.4（1155〜1157、1185〜1187、1213〜1218行付近）
- 問題: `onTermination` はイベント配送を試みない契約だが、呼び出す `cancelReceipt` は `.finished(.cancelled)` を配送する公開 OP-20 用 API である。終端済み stream に届かないことと、配送を試みないことは同義ではない。
- 改善: `terminateReceiptWithoutDelivery` など cleanup-only の内部 API を追加し、公開 OP-20 と分離する。

#### 6. 正常 terminal 後の receipt session 除去経路が明文化されていない

- 対象: §7.12.3〜§7.12.4、§8.3（1176〜1219、1351〜1355行付近）
- 問題: coordinator は session を強参照するが、Registry Port にある除去操作は cancel と開始失敗 discard だけである。quiescence / overallTimeout の terminal 配送後に辞書から session を除去する経路が不明である。
- 改善: terminal claim、event 配送、timer/reader解除、coordinator 辞書除去の順序を定義し、全正常終端で exactly-once に除去されるテストを追加する。

#### 7. Manager callback の完全な型と error 変換が未定義

- 対象: §8.1、§8.4.1〜§8.4.3、§9、§10（1265〜1286、1363〜1379、1648〜1669、1728行付近）
- 問題: Manager callback 版はメソッド名だけで、結果型、optional、`errorCode`、`errorMessage` を含む完全なシグネチャがない。Bridge が要求する `ClipboardError.errorCode` へ、どの層で変換するかも固定されていない。
- 改善: callback typealias または全 callback の完全シグネチャを示し、Domain error → Manager callback → facade → C callback の変換規則を追加する。

#### 8. JSON は型数が一致するが完全な schema になっていない

- 対象: §8.4.4（1496〜1619行付近）
- 問題: JSON 例が中心で、出力型・イベント型の required / optional / nullable、`kind` ごとの条件付き必須フィールド、未知フィールドの扱いが十分に固定されていない。
- 改善: 少なくとも `DetectedValuesJson`、`DetectedMetadataJson`、`ReceiptEventJson` をフィールド表で定義し、decode/encode の未知フィールド方針も明記する。

#### 9. タスク分解の依存・完了条件が実装順と一致しない

- 対象: §13（1927、1932、1936〜1945行付近）
- 問題:
  - T-07 coordinator が T-11a lifecycle state より先で、登録・解放・冪等性テストの完了を要求している。
  - T-11a 単独の完了条件に coordinator 統合を要する CT-11 / IT-41 が含まれる。
  - T-11b の IT-34 / IT-45 も transaction 統合なしでは完了できない。
  - T-08 は後続で実装する機能を含め「全 OP が呼べる」ことを完了条件としている。
  - T-17 は存在しない `T-16` に依存している。
- 改善: 少なくとも `T-01 → T-02 → T-11a/T-11b → T-07 → T-08 → T-11c` の順へ直し、単体完了条件と統合完了条件を分ける。T-17 は T-16a / T-16b / T-16c の必要な終点へ依存させる。

#### 10. 新 transaction と cancellation race をテストが十分に固定していない

- 対象: §12.1、§12.2、§12.5（1783〜1793、1832〜1843、1901〜1904行付近）
- 問題: `ProvideFilePromiseUseCase` のテストは旧 register → write → release を中心にしており、reserve → snapshot → provisional register → write → activate、各段階の rollback を固定していない。集約 async も handle 登録前 cancel のケースがない。
- 改善: transaction の各境界失敗、activate の呼び出し回数、snapshot late cleanup、cancel-before-handle-publication を Mock call order まで検証する。

### 低優先度

#### 11. 旧表現が一部残っている

- 対象: 1138、1666、1814、1988行付近
- 問題: receipt cleanup に `staging`、状態名に `fulfilling` / `pendingRelease` が残り、現在の state machine と矛盾する。
- 改善: receipt session の cleanup 用語と現行の `inFlightCount` / `releaseRequested` / generation claim に統一する。

#### 12. T-16b と T-16c が1行に連結され、表が壊れている

- 対象: 1944行
- 問題: 1行に14個の `|` があり、T-16c が独立タスクとして機械的に認識できない。
- 改善: T-16b と T-16c を別行にする。

#### 13. タスク件数・見積・粒度の宣言が実数と一致しない

- 対象: §13、§15（1944、1951、2011行付近）
- 問題:
  - T-18 を除く実タスクは21件、見積合計は22.75日だが、本文は20件・22.5日としている。
  - T-16c は0.25日で、「全タスク0.5〜2.0日」と矛盾する。
- 改善: T-16c を0.5日にするか T-16bへ統合し、件数と合計を再計算する。

#### 14. 軽微な追跡・章順ドリフトがある

- 対象: §6、§12、§13
- 問題:
  - T-02 は Port 3種と書くが、ファイル構成上は `FilePromiseSnapshotting` を含む4種である。
  - IT-28 / IT-29、BT-17 の並び順が逆転している。
  - §6.8 が §6.6 / §6.7 より前に置かれている。
- 改善: 機械照合対象に Port 数、ID 昇順、見出し順、Markdown table の列数を追加する。

## 第5回レビュー13件の反映確認

| 状態 | 指摘 |
|---|---|
| 解消 | R5-H1（release outcome）、R5-H3（ownership activation）、R5-H4（silent receipt rollback）、R5-H5（Bridge scope）、R5-M7（gate claim 順序）、R5-M8（event callback NULL）、R5-M10（キャンセル表現）、R5-L11（JSON shape 集合） |
| 一部解消 | R5-H2（OP-16 正規契約）、R5-M6（snapshot cancellation / late cleanup）、R5-M9（配置・DI）、R5-L12（receipt cleanup 用語）、R5-L13（タスク分割・粒度） |

## 不足項目

- OP-16 の唯一の正式なレイヤー別シグネチャと transaction
- snapshot transaction の実行主体、staging root、破棄 API、Mock
- stale tick が現在の `changeCount` を取得する Application 経路
- aggregate async の handle publication / pending cancel 状態
- stream termination 専用の無配送 cleanup
- 正常 receipt terminal 後の coordinator 辞書除去
- Manager callback の完全シグネチャと error 変換規則
- 条件付き必須フィールドまで含む JSON schema
- transaction 各段階と登録前キャンセルのテスト
- タスク表・件数・見積を検査する機械照合

## 総合評価

v6 は lifecycle state 自体の精度が上がり、Bridge の scope・NULL・shape 件数も改善した。しかし、§7.12 を正規契約と宣言した一方で、旧 transaction、§4、§9、DI、タスク表への反映が完了していない。特に OP-16 の実行主体、stale query、aggregate cancellation race は実装阻害である。

次版では新しい公開抽象を増やすより、次の順で収束させるべきである。

1. OP-16 transaction の実行主体を `ProvideFilePromiseUseCase` に固定する。
2. stale query と receipt cleanup の内部経路を確定する。
3. aggregate cancellation の handle publication race を状態機械で閉じる。
4. §8.1 / §8.3 / §9 / テスト / タスクを正規契約から機械生成または機械照合する。

高優先度4件を修正し、機械照合を通した後であれば、T-01〜T-08 / T-11a / T-11b の先行実装へ進める水準になる。
