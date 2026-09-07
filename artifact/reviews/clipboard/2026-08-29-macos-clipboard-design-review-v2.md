# レビュー結果（第2回）

- 日付: 2026-08-29
- 対象ファイル: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v2.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-29-macos-clipboard-design-review.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降

---

## 強み

- 前回の20件はすべて設計書内で追跡され、Port の Domain 化、Coordinator、File Promise の推定終端、PasteButton loader、Bridge callback 化まで具体的な型とテストへ落とし込まれている。
- `fileTypes.count` を終了条件から排除し、保証不能な終端をヒューリスティックとして DocC と DV-05 に残した点は SDK 制約に対して誠実である。
- API ID 対応表、OP-01〜OP-19 のレイヤー表、26件の `ClipboardError` と2件の `BridgeError`、テスト、タスクのトレーサビリティが v1 より大幅に改善している。
- `readData`、`accessBehavior(scope:)`、監視 restart、snapshot、サイズ制御、画像 coder 削除は、前回の矛盾を一貫した契約へ直している。
- Unity Bridge の全 control を callback 化し、nonisolated facade から MainActor へ hop する方針は、既存の任意スレッド受付契約と整合する。

## 改善点

### 高優先度

#### 1. OP-01〜OP-08 の native API が `mac.md` 必須契約から退行している

- 対象: §4、§8.1、§9 OP-01〜OP-08
- 問題: v2 は native API を同期 `throws` に変更し、「System API が同期だから」と説明している。しかし `mac.md` は新規 Manager の native API を `async throws` の薄いラッパーとして callback 版と併設するよう要求し、同期例外は即時 control / factory に限定している。copy/read/create/remove はその例外ではない。下位の Repository / UseCase を同期に保つことと、Manager native API を同期へ戻すことが混同されている。§4 の「適合」判定も事実と一致しない。
- 改善: OP-01〜OP-11 は callback + `async throws` を維持する。OP-01〜OP-08 の Repository / UseCase は同期のまま、Manager だけを薄く async 化する。OP-12〜OP-17 / OP-19 の即時 control / factory は同期のままでよい。

#### 2. OP-18 のキャンセル経路が native callback / Bridge 公開面にない

- 対象: §8.1、§8.3、§8.4、§9 OP-18
- 問題: callback 版は `FilePromiseReceiptHandle` を返し、内部 Port には `cancelReceipt(_:)` があるが、その handle を使う Manager 公開 API がない。Bridge の `clipboardReceiveFilePromises` も開始 handle を返す契約と cancel endpoint を持たないため、Unity から §9 の `cancelReceipt` を実行できない。
- 改善: `cancelReceiveFilePromises(_:)` を同期・冪等な native control として追加する。Bridge は開始結果 callback で receipt handle を返し、event callback を分離したうえで cancel endpoint を追加する。async stream は `onTermination`、集約 async 版は Task cancel から同じ control へ接続する。

#### 3. Bridge 契約が「全 endpoint 定義済み」という DoD を満たしていない

- 対象: §8.4、§12.4、§15
- 問題: C 関数名と callback typedef はあるが、完全な C prototype がなく、JSON schema は明示的に「抜粋」である。`requestJson`、`handleJson`、`policyJson`、全 receipt event、全 detection result、scalar wrapper、nullable / required、failure payload が未定義で、BT-06 の round-trip oracle を作れない。また「各呼び出しの callback は exactly-once」という共通規約は、change / receipt event callback が N 回来る契約と文言上矛盾する。
- 改善: cancel 追加後の全 endpoint の完全な C prototype、operation callback と event callback の区別、全 request/result/event union の schema、required/optional/null、開始失敗、terminal event を列挙する。exactly-once は operation/terminal callback に限定し、event callback は購読中 N 回と明記する。

#### 4. File Promise 提供側の状態機械が複数書き出し要求と actor raceを扱えない

- 対象: §6.2、§7.12 提供側、§9 OP-16、CT-06
- 問題: 企画書は同じ provider に複数の書き出し要求が来ることを明記しているが、状態は単一の `active → fulfilling → active` で、in-flight 件数を持たない。専用 `OperationQueue` も serial と定義されていない。複数要求が重なると、1件目の完了で `active` に戻り、2件目の履行中に release/stale 解放され得る。また nonisolated delegate での開始・完了と `@MainActor` coordinator の状態更新をどう原子的に接続するかが未定義である。
- 改善: lock または専用 serial executor 上の `inFlightCount` と `releaseRequested/stale` を持つ状態へ変更する。各要求の開始をクロージャ実行前に原子的に記録し、全要求完了後のみ解放する。stale 検出中の履行も `pendingRelease` とし、同時開始・完了・release・stale の race test を追加する。

### 中優先度

#### 5. `releaseFilePromise` の signature・冪等性・error が矛盾する

- 対象: §7.12、§8.1、§8.3、§10、§12.1
- 問題: 公開 API と Registry は non-throwing だが、未登録 handle は `promiseHandleNotFound` とされ、UseCase テストも異常系として要求する。一方で二重 release は冪等である。解放済み handle と未知 handle をどう区別するか、tombstone をいつ破棄するかもない。
- 改善: unknown / released の扱いを決める。完全冪等なら unknown も成功として error を削除する。未知だけを error にするなら API を `throws` にし、解放済み ID の保持期間と上限を定義する。

#### 6. OP-18 の terminal result と throw/error code の対応が不明

- 対象: §7.12、§8.1、§8.4、§10、§11
- 問題: `overallTimeout` と cancel は `finished(FilePromiseReceipt)` の正常終端理由として定義される一方、`filePromiseTimedOut` / `cancelled` error も存在する。`AsyncThrowingStream` と集約 `async throws` が partial receipt を返すのか throw するのか、Bridge が terminal `eventJson` と errorCode のどちらで示すのか決まっていない。
- 改善: 開始失敗、per-file failure、quiescence、overall timeout、explicit cancel、Task cancel の truth table を作り、stream / aggregate async / callback / Bridge の各結果を固定する。partial receipt を失わず throw する必要があるなら、error に receipt を含める result 型を検討する。

#### 7. Coordinator 境界の `PromiseObjectLookup` と `PasteHandle` が未定義

- 対象: §6.1、§6.5、§7.4、§8.2 / §8.3
- 問題: H-5 の中核となる2型が ownership 図と本文にだけ現れ、ファイル構成、protocol、可視性、返却型、寿命がない。Repository が Manager 実装から AppKit provider を解決する境界と、View 破棄時に loader 登録を外す経路が実装者依存である。
- 改善: `PromiseObjectLookup` の配置と内部 AppKit 型 contract、非保持 lookup か lease か、DI 順序を明記する。`PasteHandle` と View/container の deinit hook を定義するか、不要なら図から除く。

#### 8. DDMatch の「全フィールド保持」が未達である

- 対象: §7.10、`ClipboardDetectionMapper` tests
- 問題: 全 `DDMatch` subclass が継承する `matchedString` が8種すべての Domain struct から欠落している。SDK ヘッダは各 match が matched string を持つと明記しており、「全フィールド保持」という M-7 / DoD と一致しない。
- 改善: 共通 `matchedString` を各 entity または共通 value に追加し、全 mapper fixture で検証する。

#### 9. timeout / interval / limits の入力制約がない

- 対象: §6.7、§7.9、§7.11、§7.12
- 問題: observation interval、PasteButton timeout、quietInterval、overallTimeout、`ClipboardLimits` の正数性・大小関係が未定義である。0/負数、quiet > overall、warn > hard、per-representation hard > total で状態機械や Validator が不定になる。
- 改善: initializer validation または precondition を決め、公開入力には固定 Domain error を返す。境界値テストを追加する。

#### 10. PasteButton の結果順序・全失敗・View寿命が閉じていない

- 対象: §6.5、§7.11、§12.3
- 問題: provider を並行ロードする一方、`items` / `failures` を入力順と完了順のどちらで返すか不明である。`isPartial` は failures があれば true とされ、全件失敗でも partial になる。Coordinator が loader を保持するのに、返却 `NSView` の破棄を検知して cancel/登録解除する具体的 container/deinit 契約もない。
- 改善: provider index を result/failure に保持し、入力順へ正規化する。partial は成功・失敗が両方ある場合だけと定義し、all-failure を区別する。View container の deinit から handle cancel/release する所有グラフを追加する。

#### 11. Bridge OP-16 の `sourcePath` は遅延履行までの寿命・Sandbox契約がない

- 対象: §8.4 OP-16、RK-12、T-16
- 問題: Bridge は `sourcePath` を capture して write closure を合成するが、実際の履行は後刻である。登録後の削除・変更、App Sandbox のアクセス権、directory promise、security-scoped access、いつ source を解放するかが定義されていない。
- 改善: 登録時に app-owned staging へ snapshot するか、source URL lease/bookmark を保持するかを決める。file/directory の copy policy、失敗通知、release時の cleanup、機密 path のログ禁止を追加する。

#### 12. provider 登録後に pasteboard write が失敗した場合の rollback がない

- 対象: §7.4、§7.12、UseCase / Coordinator tests
- 問題: lazy provider / file promise は先に Coordinator へ登録して handle を得てから Repository が pasteboard へ書く構造だが、`writeObjects == false` や mapper throw 時に登録を確実に解放する transaction がない。失敗するたび provider/delegate が残留し得る。
- 改善: UseCase で register → write → commit、catch 時 release の rollback を定義し、write failure / cancellation / mapper failure の leak test を追加する。

#### 13. テスト表が今回の残存契約を固定していない

- 対象: §12、§13
- 問題: native Manager の async wrapper signature、receipt handle cancel、OP-18 terminal truth table、複数同時 fulfillment、unknown/released handle、全 JSON schema、`matchedString`、無効 timeout/interval、Bridge source lifetime、register/write rollback が未収録である。
- 改善: 上記を unit / integration / concurrency / Bridge testへ追加し、DoD の「全20件反映」を「第2回レビュー残件解消後」に更新する。

### 低優先度

#### 14. `BridgeError` の既存 DocC と NULL callback 契約が食い違う

- 対象: §5.2、§8.4、既存 `BridgeError.swift`
- 問題: v2 は callback NULL を許容し `BridgeError` を変更しないとしているが、既存 `contractViolation` の DocC は nil callback を例に挙げている。
- 改善: callback NULL を許容するなら既存 DocC を修正対象へ追加する。変更しないなら NULL callback を contract violation とする。

## 不足項目

- `mac.md` に沿う OP-01〜OP-08 の Manager native `async throws` API
- OP-18 の公開 cancel API、Bridge start acknowledgement / receipt handle / cancel endpoint
- 全 endpoint の完全な C prototype と JSON schema、operation/event callback truth table
- 複数同時 fulfillment を扱う atomic in-flight lifecycle
- OP-18 の timeout/cancel/partial-result semantics
- `PromiseObjectLookup`、`PasteHandle`、View deinit cleanup の内部 contract
- `matchedString` を含む完全な detection mapping
- timeout / interval / limits の validation
- deferred `sourcePath` の Sandbox・snapshot・cleanup policy
- register後の write failure rollback と対応テスト

## 総合評価

v2 は前回レビューの方向性をすべて取り込み、特に総数依存の排除、Coordinator、Bridge の任意スレッド対応、PasteButton loader は大きく改善した。ただし実装開始可能な確定版にはまだ届いていない。最優先は、Manager native API の規約退行、OP-18 の公開 cancel、Bridge の完全 schema、File Promise の複数同時履行 race の4件である。これらを閉じた後、terminal/error semantics、Coordinator の内部型、validation、resource rollback を同期させる必要がある。
