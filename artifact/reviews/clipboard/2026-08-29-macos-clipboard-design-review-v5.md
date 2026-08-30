# レビュー結果（第5回・収束レビュー）

- 日付: 2026-08-29
- 対象ファイル: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v5.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-29-macos-clipboard-design-review-v4.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降
- レビュー方法: 設計書・企画書・プロジェクト規約の照合、および別モデルによる独立レビュー

---

## 結論

v5 は `FilePromiseEventSubscription`、actor-safe state box、`FilePromiseSource`、off-MainActor snapshot、`ReceiptCompletionGate` を導入し、v4 の主要な方向性を改善した。

一方、収束確認では provider の正常解放、stale 判定、receipt rollback、Bridge OP-16、OP-16 の正式シグネチャに実装阻害が残った。判定は **要修正**。高優先度5件は、いずれも実装者の裁量で補うと公開契約またはリソース寿命が変わるため、実装前に設計を一本化する必要がある。

## 強み

- stream と receipt handle を `FilePromiseEventSubscription` にまとめ、同一セッションを OP-20 で指定できるようになった。
- lock-owning `FilePromiseLifecycleState` を coordinator の actor-isolated state から分離し、Swift 6 の actor isolation 問題へ正しく対応している。
- `scheduledGeneration` に claim identity を持たせ、古い予約が新しい予約を消す競合を認識している。
- `.writer` / `.snapshot(URL)` を Domain で分離し、重い snapshot を MainActor 外へ移す方針は妥当である。
- aggregate cancellation に actor hop と completion gateを導入し、continuation の二重 resume を設計対象に含めた。
- callback 必須 endpoint、receipt cleanup、process-wide cleanup、テスト項目は v4 より具体的になった。

## 改善点

### 高優先度

#### 1. `.writer` の正常解放と解放予約失敗を `nil` で区別できない

- 対象: §7.12 提供側（872〜875、889〜897、911、948行付近）
- 問題: `commitRelease(generation:) -> URL?` は再判定失敗を `nil` で表す。一方、`.writer` の正常解放も `stagingURL == nil` なので、成功時にも `nil` が返る。MainActor は失敗と判断して provider/delegate を辞書から除去できず、state は `isReleased == true` のまま残留する。
- 改善: `CommitReleaseOutcome` を定義し、`.released(stagingURL: URL?)` と `.reservationInvalid` を分離する。辞書除去は `.released` なら staging URL の有無に関係なく必ず実行する。`.writer` 正常解放テストを追加する。

#### 2. OP-16 の正式契約が章ごとに分裂している

- 対象: §4、§6.6、§7.12、§8.1、§8.3、§8.4.5、§9（239、493、926〜985、990、1165、1227、1511、1534行付近）
- 問題: §8.1 は OP-16 を `async throws` とするが、§4・§6.6・§9は同期 factory のままである。§7.12 は予約済み handle を使う新 Port を示す一方、正式な §8.3 は旧 `registerFilePromise(_:)` のまま、旧 transaction も重複している。delegate と §8.4.5 は、`FilePromiseSource` 導入後には存在しない `request.write` / `FilePromiseRequest.write` を参照する。
- 追加問題: `.snapshot` の履行時に original source ではなく staging copy を destination へ書く内部 source/writer 変換が確定していない。
- 改善: §7.12 の予約済み transaction を唯一の正規契約にする。`ClipboardPromiseRegistry`、UseCase、Manager callback/native、§9、Mock、テストを同じ署名へ更新し、delegate は `.writer` と staging-backed source を switch する契約へ直す。旧 transaction と旧フィールド参照を削除する。

#### 3. stale 解放に必要な `PasteboardOwnership` が lifecycle state へ記録されない

- 対象: §7.12 transaction、§8.2、§8.3（840、910、929〜935、966〜971、1209〜1210行付近）
- 問題: stale 検出には登録後の `scope` と `changeCount` が必要だが、`repository.writeFilePromise` が返す `PasteboardOwnership` を transaction が捨てている。registry/state が受け取るのは request、handle、staging URL のみで、5秒 tick が比較する基準を保持できない。
- 改善: provisional registration と ownership activation を分ける。pasteboard write 成功後に `activateFilePromise(handle:ownership:)` で state へ ownership を記録し、失敗時は release/rollback する。activation 前後に delegate request や stale tick が到達した場合の扱いも遷移表へ追加する。

#### 4. receipt 開始失敗の rollback が「イベントなし」契約に反する

- 対象: §7.12.3 / §7.12.4（1040、1084、1090〜1091、1105〜1114行付近）
- 問題: truth table は開始失敗時に `onEvent` を呼ばないとするが、rollback は OP-20 と同じ `cancelReceipt(handle)` を使う。通常 cancel は `.finished(.cancelled)` を配送するため、開始失敗にも terminal event が出る可能性がある。
- 改善: delivery を伴わない cleanup-only API（例: `discardReceiptAfterStartFailure`）を追加する。公開 cancel と内部 rollback を分離し、開始失敗で session/timer/closure が消え、イベントは0件であることをテストする。

#### 5. Bridge OP-16 から Manager の `scope` を指定できない

- 対象: §8.1、§8.4.3、FilePromiseRequestJson（1165、1344〜1347、1411〜1415行付近）
- 問題: Manager API は `provideFilePromise(_:scope:)` だが、C prototype は `requestJson` と callback しか持たず、`FilePromiseRequestJson` にも scope がない。Bridge は provider を書く pasteboard を決定できない。
- 改善: C prototype に `scopeJson` を追加するか、request JSON に `scope` を必須フィールドとして含める。OP-16 round-trip、NULL、scope resolution failure の Bridge テストを追加する。

### 中優先度

#### 6. snapshot の Task cancellation と late completion cleanup が未定義

- 対象: §7.12 snapshot transaction、§8.1（939〜964、1177行付近）
- 問題: `async throws` protocol にしても、同期的な `FileManager.copyItem` は自動では協調キャンセルされない。Task cancel 後に copy が完了した場合、登録を抑止するか、完成・部分 staging を誰が削除するかがない。
- 改善: copy 前後の cancellation check、late completion gate、cancel 時の部分/full staging cleanup を定義する。blocking file I/O は専用 DispatchQueue 等へ隔離し、callback 版と native Task cancel の差も明記する。

#### 7. `ReceiptCompletionGate` の claim と OP-20 の順序が不足している

- 対象: §7.12.4（1131〜1134行付近）
- 問題: cancel Task が先に OP-20 を呼ぶと、その terminal callback が gate を claim して receipt を返し、Task cancellation 時に `CancellationError` を投げる契約を満たせない。
- 改善: cancel Task は最初に gate を claimし、成功した場合に continuation を `CancellationError` で resume、その後 OP-20 で session cleanupする順序を固定する。terminal-first / cancel-first の両テストで返却結果まで検証する。

#### 8. event callback の NULL 契約がない

- 対象: §8.4.1〜§8.4.3（1239〜1249、1271〜1277、1333〜1337、1353〜1359行付近）
- 問題: operation callback の NULL 方針は定義されたが、`onChange` と `onEvent` の NULL 可否がない。特に receipt を開始して `onEvent == NULL` の場合、結果を受け取れない session を生成できる。
- 改善: event callback を必須にするか、NULL を許す理由と寿命を定義する。必須なら operation callbackへ1302を返して開始せず、対応する Bridge テストを追加する。

#### 9. 新しい concurrency 型・snapshot Port の配置と DI がファイル構成にない

- 対象: §6.1、§6.2、§7.12、T-11〜T-13（306〜410、844〜876、939〜943、1121〜1128、1796〜1798行付近）
- 問題: `FilePromiseLifecycleState`、`ReceiptCompletionGate`、`FilePromiseSnapshotting` と concrete implementation がファイル一覧にない。snapshotter をどの層に置き、どの executor/queueを所有し、UseCaseへどう注入するかが未定義である。
- 改善: Application Port、Data implementation、Manager/Coordinator internal state、Mock/Test の配置を追加し、DI順序と isolationを明記する。

#### 10. OP-18 の Task cancellation/error 説明が統一されていない

- 対象: §7.12.3、§10（1036、1047〜1049、1588〜1591行付近）
- 問題: 冒頭は「throwするのは開始前だけ」とするが、集約 Task cancel は `CancellationError` をthrowする。さらに本文は `cancelled` を集約Task cancelでも使うとする一方、Domain error表は `ClipboardError.cancelled` を検出API専用としている。
- 改善: 明示 cancelは正常 receipt、Task cancelは標準 `CancellationError`、Domain `ClipboardError.cancelled` は検出API専用、と明確に分けて全表を統一する。

### 低優先度

#### 11. JSON shape の件数計算がまだ一致しない

- 対象: §8.4.4、BT-11/BT-17（1374〜1381、1739、1745行付近）
- 問題: 出力専用欄には実質8型があるが、説明は7型として合計19にしている。列挙どおりなら入力専用7 + 共用3 + 出力専用8 + event2 = 20型である。
- 改善: `PatternsJson` を共用に移すなど集合を排他的に定義し直し、実数、BT-11、BT-17を再照合する。

#### 12. receipt cleanup の旧 staging 表現がテストに残る

- 対象: truth table、IT-27（1046、1696行付近）
- 問題: 本文は提供側 staging を receipt cleanup の対象外にしたが、truth table と IT-27 はまだ staging を解放するとしている。
- 改善: session、timer、reader/event closure の解除に置き換える。

#### 13. タスク粒度の DoD と T-11 が矛盾する

- 対象: T-11、設計DoD（1796、1903行付近）
- 問題: DoD は0.5〜2.0日粒度とするが、T-11は3.0日である。
- 改善: lifecycle state、snapshotter、provider/delegate integrationを別タスクへ分割するか、DoDの粒度条件を更新する。

## 第4回レビュー10件の反映確認

| 状態 | 指摘 |
|---|---|
| 解消 | R4-H1（subscription handle）、R4-H2 の actor isolation 分離、R4-M6（create callback NULL）、R4-M7（`@discardableResult`）、R4-L10（process-wide cleanup） |
| 一部解消 | R4-H3（source型/off-main方針は追加、正式APIが未収束）、R4-M4（gate/hopは追加、claim順序が不足）、R4-M5（rollbackは追加、delivery付きcancelを流用）、R4-L8（集合は追加、件数不一致）、R4-L9（本文は修正、truth table/IT-27に旧表現） |

## 不足項目

- staging URLの有無とrelease成否を分離した結果型
- pasteboard ownershipをstateへactivateする二段階transaction
- 開始失敗専用のsilent receipt cleanup
- Bridge OP-16のscope入力
- `.writer` / staged snapshotのdelegate履行契約
- snapshot Task cancellationとlate completion cleanup
- event callback NULL契約
- 新規state/gate/snapshotterの配置・DI

## 総合評価

v5 はコンパイラで確認されたactor問題を正しく設計へ還元し、主要な抽象型も改善した。しかし、各抽象を正式Port・Bridge・state transitionへ接続する段階で未収束が残っている。特に正常releaseの`nil` ambiguity、ownership未記録、rollback時の誤配送、Bridge scope欠落、OP-16契約分裂は実装開始後に公開APIまたは資源寿命の変更を招く。

高優先度5件を同じ修正で横断的に同期し、機械照合後に実装へ進むべきである。次版は新しい抽象を追加するより、§7.12を唯一の正規契約として§8.3・§9・Bridge・テスト・DoDを揃えることを優先する。
