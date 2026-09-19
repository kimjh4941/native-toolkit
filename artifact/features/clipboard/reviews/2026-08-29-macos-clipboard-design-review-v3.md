# レビュー結果（第3回）

- 日付: 2026-08-29
- 対象ファイル: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v3.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-29-macos-clipboard-design-review-v2.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降
- レビュー方法: 設計書・企画書・プロジェクト規約の照合、および別モデルによる独立レビュー

---

## 結論

v3 は第2回レビューの14件を大筋で反映している。特に Manager native API の `async throws` 復帰、OP-20 の追加、Bridge prototype/schema の具体化、`inFlightCount`、入力検証、PasteButton の寿命、rollback は明確に改善した。

ただし、現状のまま実装へ進むと成立しない OP-18 の stream 契約、File Promise 解放時の actor-hop race、Bridge staging の cleanup 所有権が残る。判定は **要修正**。高優先度3件を解消してから実装へ進むのが安全である。

## 強み

- OP-01〜OP-11 の Manager native API と下位同期層の役割が分離され、`mac.md` の公開 API 規約へ戻っている。
- OP-20 と receipt handle が native / Bridge の両方へ追加され、外部から明示 cancel できる公開面ができた。
- Bridge は19 endpoint の C prototype、operation/event/terminal callback、JSON payload を具体化し、v2 の実装不能な曖昧さを大幅に減らした。
- File Promise 提供側に `inFlightCount`、serial queue、register/write rollback が入り、複数要求と失敗時 leak を考慮している。
- OP-18 で保証不能な受領総数を使わず、quiescence / overall timeout をヒューリスティックとして明記している。
- detection、設定値、PasteButton、テスト、タスクのトレーサビリティは v2 より実装可能な粒度になった。

## 改善点

### 高優先度

#### 1. OP-18 の stream 開始失敗・Task キャンセル契約が実装できない

- 対象: §7.12.3、§7.12.4、§8.1、IT-27、T-13（914、862、868、881、1420、1504行付近）
- 問題1: `receiveFilePromiseEvents(...) -> AsyncThrowingStream<...>` は `throws` ではないのに、truth table は「開始 API が throw し、stream を作らない」としている。提示シグネチャでは開始前エラーを呼び出し元へ throw できない。
- 問題2: consumer Task のキャンセルで `AsyncThrowingStream` が終端した後、`onTermination` から OP-20 を呼んで同じ stream に `.finished` を yield しても、consumer への配送は保証できない。IT-27 の「Task キャンセル後に `finished` が出る」も同じ前提に依存している。
- 改善: stream factory を `throws -> AsyncThrowingStream` にして開始失敗を同期的に返すか、開始失敗時は作成した stream を `finish(throwing:)` する契約へ統一する。Task キャンセル時は `onTermination` から内部 receipt を cancel/cleanup するだけとし、キャンセル済み consumer への `.finished` 配送は保証しない。明示 OP-20 のときだけ、まだ購読中の stream へ `.finished(.cancelled)` を配送する。truth table、IT-27、T-13、§9 を同時に直す。

#### 2. `inFlightCount == 0` 判定と MainActor の辞書削除の間に TOCTOU race が残る

- 対象: §7.12 提供側、CT-08、CT-09（772〜794、1467〜1470行付近）
- 問題: state は `NSLock` 内で更新するが、実際の解放は `Task { @MainActor in ... }` に後送される。その間に新しい `writePromiseTo` が開始して `inFlightCount` を増やせるため、先に予約された MainActor Task が履行中の provider/delegate を辞書から除去し得る。`isReleased` をいつ true にするか、新規開始をどう扱うか、MainActor 側で再判定するかが定義されていない。
- 改善: lock 内で解放予約を一意に claim する状態（例: `releaseScheduled`）と generation を導入するか、MainActor の除去直前に同じ lock/generation で `releaseRequested && inFlightCount == 0` を再確認する。新しい開始が入った場合は予約を無効化し、最後の完了で再予約する。`isReleased` の設定点と、解放予約後に届く開始要求の扱いも遷移表に追加する。

#### 3. Bridge staging の作成者と cleanup 実行者を結ぶ所有権がない

- 対象: §6.5、§7.12、§8.4.5、IT-28/IT-29、T-16（369〜401、1222〜1236、1421〜1422、1507行付近）
- 問題: staging は Bridge の `clipboardProvideFilePromise` 受理時に作る一方、handle の stale 解放は `ClipboardSystemCoordinator` が内部で行う。`FilePromiseRequest` は write closure しか持たず cleanup hook/path を持たないため、coordinator から Bridge 所有の staging を stale 解放時に削除する経路がない。また staging path は `<handleId>` を前提にするが、handle は登録後に発行されるため、コピー・handle 生成・登録の transaction 順も閉じていない。登録失敗時の staging 即時削除も明記されていない。
- 改善: staging の作成と ownership を coordinator/Manager 側へ移すか、登録 state に staging cleanup closure/token を含め、明示 release・stale・rollback の全経路から exactly-once で呼ぶ。handle ID を事前生成する factory、または staging token と handle の対応付けを定義し、コピー失敗・登録失敗・pasteboard write 失敗の各 rollback を遷移表とテストへ追加する。

### 中優先度

#### 4. handle 返却 endpoint で callback NULL を許すと回収不能なリソースを作れる

- 対象: §8.4.1、§8.4.3、§8.4.5（991、1087〜1104、1232行付近）
- 問題: `clipboardProvideFilePromise` と `clipboardReceiveFilePromises` は handle を operation callback でのみ返す。callback が NULL でも操作を実行すると、呼び出し側は release/cancel 用 handle を取得できず、provider、receipt、staging を回収できない。
- 改善: handle を返す2 endpoint は callback を必須にして NULL を `contractViolation` とする。あるいは callback NULL 時は登録を開始せず no-op/error とする。BT-04 は endpoint の種類別に期待値を分ける。

#### 5. OP-20 の Application 経路と UseCase が未定義

- 対象: §6.1、§7.12.4、§8.3、§12.1、T-06（282〜300、880、968〜977、1377〜1379、1497行付近）
- 問題: OP-20 は Manager から `registry.cancelReceipt` を直接呼ぶ記述だが、ファイル構成・UseCase テスト・タスクに `CancelReceiveFilePromisesUseCase` がない。Manager が UseCase を集約する規約との境界が OP-20 だけ曖昧で、T-06 の「UseCase 19本」と列挙実体も一致しない。
- 改善: 同期・冪等な `CancelReceiveFilePromisesUseCase` を追加して OP-20 を通すか、即時 control は Manager が Port を直接呼べる明示的な設計例外を §3/§6 に記載する。ファイル一覧、テスト、UseCase 本数、T-06 を同期する。

#### 6. OP-08 に `@discardableResult` を付けると warning zero と両立しない

- 対象: §8.1、§12.1、§15（904、920、1386、1563、1596行付近）
- 問題: OP-08 `removePasteboard(_:) async throws` は `Void` 戻り値である。全 OP-01〜OP-11 に `@discardableResult` を付ける方針を最小 Swift 6 コードで typecheck したところ、`'@discardableResult' declared on a function returning 'Void' is unnecessary` の warning が発生した。これは Swift 6 strict concurrency の warning zero DoD と矛盾する。
- 改善: `@discardableResult` は戻り値がある OP-01〜OP-07 / OP-09〜OP-11 に限定し、OP-08 には付けない。シグネチャ検査と DoD の表現も同じ範囲に直す。

#### 7. §6.6 の「ネイティブ Swift API は同期」が §8.1 と矛盾する

- 対象: §6.6、§8.1、§9（428、920〜923、1244行以降）
- 問題: §6.6 は native Swift API 全体が同期のように読めるが、確定契約では OP-01〜OP-11 が `async throws` である。前回指摘の修正文が一部残っている。
- 改善: 「該当する即時 control / factory（OP-12〜17、19、20）の native API は同期」と限定し、後続の差分説明も同じ範囲にする。

### 低優先度

#### 8. OP-20 追加後の件数・旧名称が複数箇所でドリフトしている

- 対象: §0、§12.2、§12.4、§15（24、1412、1441、1451、1585行付近）
- 問題: Bridge は OP-19 非公開なので C endpoint は19件だが、§0 は20件、BT-01 は18件、BT-10/T-16/DoD は19件になっている。BT-11 は入力9種とする一方、§8.4.4 の入力欄には10種ある。IT-19 は旧内部名 `cancelReceipt`、DoD は `OP-01〜OP-19` のままである。
- 改善: 「公開 OP は20、Bridge endpoint は19」に用語を固定する。BT-01を19、BT-11の型数を実数へ修正し、IT-19を公開名へ、DoDを OP-01〜OP-20 へ更新する。機械照合テストを追加する。

## 第2回レビュー14件の反映確認

| 状態 | 指摘 |
|---|---|
| 解消 | R2-H1、R2-M5、R2-M7、R2-M8、R2-M9、R2-M10、R2-M12、R2-M14 |
| 一部解消 | R2-H2（公開 cancel は追加、stream cancel 契約が不成立）、R2-H3（prototype/schema は追加、NULL・件数整合が残る）、R2-H4（counter は追加、actor-hop race が残る）、R2-M6（truth table は追加、stream の開始失敗/Task cancel が不成立）、R2-M11（staging 方針は追加、cleanup ownership が未接続）、R2-M13（テストは追加、期待値・件数が一部不整合） |

## 不足項目

- 実装可能な OP-18 stream の開始失敗・Task cancellation 契約
- lock 内の状態判定と MainActor 解放を原子的に接続する遷移
- Bridge staging の owner、cleanup hook、rollback transaction
- handle 返却 endpoint 固有の NULL callback 契約
- OP-20 の Application/UseCase 経路
- warning zero と両立する `@discardableResult` の適用範囲
- 公開 OP 数、Bridge endpoint 数、schema 型数の機械的整合

## 総合評価

v3 は v2 の主要な設計不足をかなり閉じており、方向性は妥当である。一方、OP-18 の stream cancel は API の性質上そのまま実装できず、File Promise 提供側も lock と MainActor の境界に最後の race が残る。staging cleanup も owner 間の接続がないため、明示 release 以外で leak し得る。

高優先度3件を直し、中優先度の NULL callback、OP-20 経路、`@discardableResult` を同期すれば、実装開始可能な水準に到達できる。
