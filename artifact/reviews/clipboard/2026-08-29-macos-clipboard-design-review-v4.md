# レビュー結果（第4回）

- 日付: 2026-08-29
- 対象ファイル: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v4.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-29-macos-clipboard-design-review-v3.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降
- レビュー方法: 設計書・企画書・プロジェクト規約の照合、および別モデルによる独立レビュー

---

## 結論

v4 は前回指摘の中心だった stream 終端、解放再判定、staging 所有者を正しい方向へ修正している。公開 OP 20件と Bridge endpoint 19件も機械的に一致した。

ただし、修正後の API 境界を詳細に追うと、OP-18 stream から cancel handle を取得できない、nonisolated delegate が `@MainActor` coordinator 内の state を更新できない、Bridge の `sourcePath` が Manager → UseCase → Port を通る確定シグネチャがない、という3件の実装阻害が残る。判定は **要修正**。この3件と OP-18 lifecycle を閉じてから実装へ進むのが安全である。

## 強み

- stream の Task キャンセル後に `.finished` を配送しない契約へ直し、`onTermination` を cleanup 用に分離した判断は妥当である。
- `releaseScheduled`、`generation`、MainActor 側の再判定を導入し、v3 の単純な TOCTOU race を認識している。
- staging の作成・保持・削除を coordinator に集約する方針により、stale 解放時の cleanup を扱える構造へ近づいた。
- `CancelReceiveFilePromisesUseCase`、handle 返却 endpoint の NULL 方針、OP-08 の `@discardableResult` 除外、§6.6 の同期 API 表現は改善されている。
- 公開 OP と Bridge prototype の実数は、それぞれ20件・19件で一致する。
- File Promise の競合、rollback、Bridge、並行性テストが追加され、失敗経路の追跡性が高まった。

## 改善点

### 高優先度

#### 1. OP-18 stream から同一セッションの明示 cancel handle を取得できない

- 対象: §7.12.3、§7.12.4、§8.1、§9（953〜987、1020〜1022、1372行付近）
- 問題: truth table は OP-20 によって購読継続中の stream へ `.finished(.cancelled)` を配送できるとしているが、factory の戻り値は `AsyncStream<FilePromiseReceiptEvent>` だけである。内部で発行された `FilePromiseReceiptHandle` が呼び出し側へ公開されないため、同じ stream session を指定して OP-20 を呼べない。
- 改善: `FilePromiseEventSubscription` のような Domain 値型を追加し、`handle` と `events` を返す。例: `receiveFilePromiseEvents(...) throws -> FilePromiseEventSubscription`。または `(handle, stream)` を返す契約にする。明示 cancel、Task cancel、通常終端後の handle 寿命を表とテストへ追加する。

#### 2. nonisolated delegate から `@MainActor` coordinator 内の state を lock 更新できない

- 対象: §6.2、§7.12 提供側、CT-08〜CT-10（381〜391、806〜849、1588〜1590行付近）
- 問題: `ClipboardSystemCoordinator` は `@MainActor` だが、`FilePromiseState` は coordinator 内部 state とされ、nonisolated `FilePromiseDelegate` から `NSLock` で直接更新するとしている。lock は Swift の actor isolation を解除しないため、このままでは Swift 6 で actor-isolated state へアクセスできない。
- 追加問題: 解放 Task は generation をローカルに capture するだけで、state は `releaseScheduled: Bool` しか持たない。古い予約 Task が再判定失敗時に `releaseScheduled = false` とすると、より新しい予約の claim まで消せる。
- 改善: delegate と coordinator が共有する独立した lock-owning state box を定義する。例: `final class FilePromiseLifecycleState: @unchecked Sendable` が lock と全状態を private に持ち、安全性条件を明記したメソッドだけを公開する。`scheduledGeneration: UInt64?` を保持し、予約 Task は自分の generation と一致するときだけ clear/release できるようにする。MainActor の辞書はこの box を保持し、辞書変更だけを MainActor で行う。

#### 3. staging の新契約が Manager → UseCase → Port の単一 API へ接続されていない

- 対象: §7.12、§8.1、§8.3、§8.4.5（856〜900、1018、1073〜1084、1331〜1347行付近）
- 問題: §7.12 は `reserveFilePromiseHandle()` と `registerFilePromise(_:reserved:snapshotting:)` を示す一方、正式な §8.3 Port は旧 `registerFilePromise(_:)` のままである。直後には旧 transaction も重複して残る。さらに Bridge は `sourcePath` を Manager native API へ渡すとしているが、公開 OP-16 は `FilePromiseRequest` と `scope` しか受け取らず、`FilePromiseRequest` に `sourcePath` はない。したがって Bridge から coordinator の snapshot 経路へ値を渡せない。
- 追加問題: coordinator は `@MainActor` で、`sourcePath` はファイルまたはディレクトリを再帰コピーし得る。これを同期 factory 内で行うと、サイズ上限のないコピーが MainActor を長時間ブロックし、「即時 factory」例外にも該当しなくなる。
- 改善: native closure 経路と Bridge snapshot 経路の型・実行方式を分離して確定する。例えば `ProvideFilePromiseRequest` の source を `.writer(closure)` / `.snapshot(URL)` にするか、Bridge 用の Manager/UseCase APIを別に設ける。後者の snapshot は background executor で実行する `async throws` 操作とし、登録・pasteboard write のみ MainActor へ戻す。§7.12、§8.1、§8.3、§9、transaction、Mock、テストを同じ署名へ統一する。

### 中優先度

#### 4. 集約 async 版の Task cancellation は actor hop と exactly-once resume が未定義

- 対象: §7.12.3、§9、T-13（951〜965、1372、1625行付近）
- 問題: `withTaskCancellationHandler` の `onCancel` は同期・`@Sendable` で実行されるため、`@MainActor` の OP-20 を直接呼べず、handler 自体から throw もできない。最小 Swift 6 typecheck でも、MainActor-isolated cancel の直接呼び出しは actor isolation error になる。また cancel、terminal callback、timeout が競合したときに continuation を誰が1回だけ resume するかがない。
- 改善: `onCancel` では `Task { @MainActor in ... }` で OP-20 へ hop し、aggregate operation 側に atomic/actor-isolated completion gate を置く。terminal で resume した後に cancellation 状態を確認し、Task cancel が勝った場合だけ `CancellationError` を投げる契約を定義する。cancel と terminal の同時発生テストを追加する。

#### 5. OP-18 の開始失敗時に receipt 登録を rollback する経路がない

- 対象: §8.2、§8.3、truth table、テスト（955、1063〜1065、1081〜1083、1491、1533行付近）
- 問題: `registerReceipt` で session/timer を登録した後、`startReceivingFilePromises` は throw し得るが、開始失敗時の `cancelReceipt` / 登録除去 transaction が定義されていない。「stream を作らず throw」しても内部 session が残留し得る。
- 改善: `registerReceipt → start → catch で cancel/remove → return handle/stream` の transaction を UseCase に明記し、callback、stream、aggregate、Bridge の全開始 APIが同じ経路を使うようにする。開始失敗後に session/timer/event closure が残らないテストを追加する。

#### 6. NULL callback 必須対象から unique pasteboard 作成が漏れている

- 対象: §8.4.1、`clipboardCreatePasteboard`、BT-04a/04b（1098〜1100、1161〜1165、1561〜1562行付近）
- 問題: `.unique` pasteboard は生成された `ScopeJson` を callback でしか取得できない。callback NULL のまま操作すると、呼び出し側は作成した unique pasteboard を再参照・release できない。現在の「残り17 endpoint は callback NULL でも実行」はこの endpoint で資源漏れを作る。
- 改善: `clipboardCreatePasteboard` も callback 必須にするか、少なくとも `kind == unique` では NULL 時 no-op とする。BT-04 の endpoint 分類と HeaderDoc を更新する。

#### 7. OP-08 の `@discardableResult` 除外がテスト・タスク・DoDへ反映し切れていない

- 対象: §4、§12.1、T-08、§15（208、1498、1620、1692行付近）
- 問題: §8.1 と実装 DoD は正しく限定されたが、複数箇所が依然「OP-01〜OP-11 は `async throws` + `@discardableResult`」としている。このままテスト/T-08を実装すると OP-08 の warning を再導入する。
- 改善: すべて「OP-01〜OP-11 は `async throws`。`@discardableResult` は OP-01〜07 / OP-09〜11」に統一する。履歴上の旧記述は「当時の記述」と明示する。

### 低優先度

#### 8. schema 型数と BT-17/T-16 の追跡がまだ一致していない

- 対象: §8.4.4、BT-11、BT-17、T-16（1218〜1327、1569、1575、1628行付近）
- 問題: 入力欄は10型だが、出力欄に明示された型は9型であり、endpoint の出力として再利用される `OwnershipJson`、`ScopeJson`、`HandleJson` を数えるなら出力 shape は12型になる。BT-11 の「出力10種」はどの基準でも追跡できない。また BT-17 を追加したのに、T-16 の完了条件は BT-01〜BT-16 のままである。
- 改善: 入力専用、出力専用、入出力共用、イベントを名前付き集合で列挙してから件数を導出する。BT-11/BT-17をその集合に合わせ、T-16を BT-01〜BT-17へ更新する。

#### 9. 受領 session cleanup と提供側 staging cleanup が混同されている

- 対象: §7.12.3、IT-27（961、976、1532行付近）
- 問題: OP-18 の receipt session は destination へ受領する側であり、OP-16 provider の `stagingURL` を所有しない。stream `onTermination` と IT-27 に「staging を削除」と書くと、無関係な提供側 staging を削除するように読める。一方、集約 async の説明では受領済みファイルは残すとしている。
- 改善: OP-18 cleanup は receipt session、reader callback、quiet/overall timer、event closure の解除に限定する。提供側 staging は `FilePromiseHandle` の release/stale/rollback でのみ削除する。もし受領側にも一時領域を設けるなら、別名・別所有モデルを定義する。

#### 10. 起動時 staging 残骸削除の process-wide 実行点が未定義

- 対象: §8.4.5（1343行付近）
- 問題: coordinator/Manager を複数生成できる場合、各 init で staging root を削除すると、同一プロセス内の別 coordinator が保持する active session を破壊し得る。
- 改善: cleanup を process-wide once のアプリ起動フックで行うか、active handle の directory を除外する。削除失敗はログに残し、次回起動で再試行する方針を定義する。

## 第3回レビュー8件の反映確認

| 状態 | 指摘 |
|---|---|
| 解消 | R3-M5（Cancel UseCase）、R3-M7（§6.6 の同期 API 表現） |
| 一部解消 | R3-H1（stream 終端は修正、handle/aggregate cancel が残る）、R3-H2（再判定は追加、actor-safe state/claim identity が残る）、R3-H3（owner 方針は妥当、API 経路が不一致）、R3-M4（2 endpoint は修正、unique create が漏れる）、R3-M6（正規 API は修正、テスト等に旧表現）、R3-L8（公開 OP/Bridge endpoint は一致、schema/BT-17 が残る） |

## 不足項目

- stream と同一 receipt session を指定できる公開 handle
- Swift 6 actor isolation を満たす lock-owning lifecycle state box
- Bridge `sourcePath` の Manager → UseCase → Port 契約と off-MainActor snapshot
- aggregate async cancellation の actor hop、completion gate、競合テスト
- OP-18 開始失敗時の receipt/session rollback
- unique pasteboard 作成の NULL callback 契約
- schema shape の名前付き集合と機械照合基準

## 総合評価

v4 の修正方針自体は適切で、v3 の原理的に成立しない stream 配送契約と単純な解放 race は改善した。しかし、公開 handle、actor-safe state、staging API の接続という実装境界がまだ閉じていない。この3件はコードを書き始めると API変更または構造変更を伴うため、設計段階で修正すべきである。

高優先度3件を解消し、OP-18 の aggregate cancellation と開始 rollback を固定すれば、実装開始可能な水準に到達できる。
