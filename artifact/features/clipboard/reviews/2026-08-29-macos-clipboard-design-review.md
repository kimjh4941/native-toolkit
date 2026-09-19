# レビュー結果

- 日付: 2026-08-29
- 対象ファイル: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design.md`
- 機能名: clipboard
- 対象 OS: macOS 15 以降

---

## 強み

- 企画書 v3 の実測結果（RK-21 / RK-23 / RK-22）を設計へ引き継ぎ、所有権・weak delegate・通知不確実性を構造的な設計判断に落としている。
- `System API → Repository → UseCase → Manager callback → Manager native → Bridge` の対応表を持ち、同期 / 非同期の理由まで明示している。
- `ClipboardChangeMonitor` と File Promise 関連型を `mac/MacLibrary` 側へ配置し、Unity plugin に system callback を持ち込まないモジュール境界は守っている。
- テスト設計が単体 / 統合 / 並行性 / 手動確認に分かれ、企画書リスクとの対応付けも追いやすい。

## 改善点

### 高優先度

- **8.2 Port / 7.11 File Promise**
  - 問題: `ClipboardRepository` が `FilePromiseSession` を返しており、Application Port に Presentation 層の参照型が漏れている。common.md の「Port はドメイン型のみ」「Manager は UseCase 経由」の前提と衝突し、UseCase が session の寿命管理詳細を知る構造になる。
  - 改善: 公開 API と Port はドメイン型の `FilePromiseHandle` だけを返す。provider / delegate / session store は Manager 所有 coordinator に閉じ、明示解放と stale 解放を handle 基準へ統一する。

- **8.1 / 8.2 / T-13 Unity Bridge**
  - 問題: operation callback / JSON callback の使い分け、JSON 成功・失敗形、C 文字列寿命、exactly-once、JSON パース失敗時の error code が未定義である。現状の `ClipboardError` にも Bridge 境界エラーがなく、実装側がその場で契約を作れてしまう。
  - 改善: `UnityMacClipboardManager` / `.h` / `.m` の公開契約を固定し、Bridge 境界の失敗は既存 `BridgeError`、Manager 以降は `ClipboardError` と責務分離する。

- **7.11 / 9 OP-18 `receiveFilePromises` の完了判定**
  - 問題: `fileTypes.count` 回の reader 到達を待つ設計だが、SDK ヘッダはその count が約束ファイル数を示すことを保証していない。legacy provider は一意な型を1回だけ列挙し、同じ型で複数ファイルを書き得るため、completion が永久に来ない、または早過ぎる可能性がある。DV-05 に残すだけでは安全な実装仕様にならない。
  - 改善: 不確かな総数による集約を廃止する。ファイル単位イベント、対応 provider の明示的制限、timeout を含む coordinator など、保証可能な終了モデルを定義する。

- **7.11 / 8.1 / 9 OP-18 native async 欠落**
  - 問題: System API に Swift async overload がないことを理由に native async 版を省略しているが、OP-18 は結果が後着する待機操作である。`common.md` は Manager に callback + native async の併設を要求する。
  - 改善: 下位層は callback のまま、Manager native 版で continuation を使って async 化する。部分成功を表す result、exactly-once、cancel、timeout、late callback 抑止も定義する。

- **3 / 4.1 / 7.3 / 7.11 system delegate 所有**
  - 問題: `LazyDataProvider` を Repository が強参照し、File Promise の delegate/session を Presentation が所有する設計は、system Delegate / Listener を Manager 層の1クラスだけが所有し RepositoryImpl に持たせないという `common.md` と一致しない。
  - 改善: Manager 所有 coordinator に delegate 登録・保持・解放を一元化し、Repository は Domain と `NSPasteboard` の変換へ限定する。

- **6.1 / 8.2 / T-10 OP-18 UseCase 欠落**
  - 問題: Port と Manager API に `receiveFilePromises` がある一方、`ReceiveFilePromisesUseCase` とそのテストがない。Manager が Repository を直接呼ばないというルールを満たせない。
  - 改善: 専用 UseCase、Mock、単体テストを追加する。Manager coordinator の直接責務とする場合も、Repository 直呼びにならない境界を明記する。

- **6.2 / 9 OP-12〜OP-15 MainActor と同期 C Bridge**
  - 問題: Manager 全体を `@MainActor` にしながら Bridge control を同期 C 関数としている。既存 UnityMacPlugin は任意スレッド受付を公開契約としており、同期戻り値を保ったまま actor hop はできない。
  - 改善: facade を nonisolated にして control も完了 callback 付きで main actor へ渡すか、C API を main-thread-only として HeaderDoc・assert・test で固定する。

- **7.10 / 9 OP-19 `PasteButton` payload 変換**
  - 問題: U-02 の callback は `[NSItemProvider]` だが、設計上の `onPaste` は `[ClipboardItemData]` を即座に返す。Data 化に必要な非同期 load、複数表現選択、部分失敗、cancel、provider/一時ファイル寿命が未設計である。
  - 改善: `[NSItemProvider]` を Presentation API として返すか、専用 loader/coordinator で Domain result へ非同期変換する。

### 中優先度

- **7.5 / 10 / 11 / 12.1 `readData`**
  - 問題: 該当なしを `nil` とする一方、`noMatchingItem` を error として定義し、テストでも両方を要求している。
  - 改善: `Data?` を維持するなら `noMatchingItem` を削除し、エラー表・コード表・テストを同期する。

- **7.9 / 8.1 / 8.2 `accessBehavior`**
  - 問題: `NSPasteboard.accessBehavior` は pasteboard インスタンスの値だが公開 API / Port は無引数で、named / unique scope、15.4未満、解決不能 scope の契約が不明である。
  - 改善: `accessBehavior(scope:)` とし、15.4未満は `.unavailable`、解決不能 scope の error を固定する。

- **6.2 / 10 / 14.1 サイズ制御**
  - 問題: 10MB 超過を警告とする記述と `contentTooLarge` で拒否する記述が矛盾する。`ClipboardLimits` の型・配置・注入点もない。
  - 改善: warning と hard failure を分離し、既定値・総量計算・Validator への注入点を定義する。

- **7.11 / 14 RK-21 File Promise session 解放**
  - 問題: stale 解放が任意の監視 tick に依存する。caller が session を保持していれば Manager の一覧から外すだけでも解放されず、冪等性・履行中との競合も未定義である。
  - 改善: 監視と独立した lifecycle coordinator と opaque handle を用い、明示 release / stale / deinit / 履行中の状態遷移を定義する。

- **7.8 / 10 `observationAlreadyActive`**
  - 問題: `start` は既存監視を停止して再開すると記述される一方、`observationAlreadyActive` error も定義され、到達条件とテストがない。
  - 改善: restart と二重 start 拒否のどちらかに統一し、scope 解決失敗時の停止順序も決める。

- **7.9 / 8 / 9 非同期契約**
  - 問題: OP-09〜OP-11 の cancel 時の返却、late result の破棄、timeout、callback exactly-once がない。OP-18 と PasteButton はさらに不明確である。
  - 改善: 操作ごとに timeout、cancel、late-result 抑止、exactly-once、resource release を対応表へ追加する。

- **7.9 / 12 検出値の Domain mapping**
  - 問題: 企画書の `DetectedValues.patterns` と `DetectedMetadata.metadataTypes` が欠落する。`DDMatch*` を一律 `String` 化する決定的規則もない。
  - 改善: 全フィールドを lossless な Domain struct に写像するか、locale 非依存の正規化形式を定義する。

- **7.6 `snapshot(matchingTypes:)`**
  - 問題: 全 item の全型、一致 item のみ、代表型のみのどれを返すか不明で、nil / 空配列、完全一致 / UTI conformance の差も未定義である。
  - 改善: `matchingItemIndexes` 等で結果を型として明示し、優先順位と境界値をテストで固定する。

- **7.11 / 10 File Promise 入力と URL 契約**
  - 問題: `request.write(url)` の URL が destination directory か完成ファイル URL か不明。fileName の空文字・区切り文字・`..`、destination、同名衝突等の error もない。
  - 改善: closure 引数、basename validation、destination policy、部分成功 result、system error mapping を定義する。

- **12 / 13 テスト網羅性**
  - 問題: OP-18 の複数 callback・部分失敗・総数不一致、PasteButton load、全 Bridge endpoint/schema/thread/lifetime、observer 再入、session race が未収録である。
  - 改善: 全 OP を ID で追跡し、exactly-once、NULL、parse failure、partial failure、late callback、release race のテストを追加する。

- **2 / 12.4 / 15 scope と試験**
  - 問題: F 群の in-scope 表は provide/release のみだが receive も設計している。D&D UI は out だが MT-05 は Finder への drag を要求し、U-05〜U-07 の不採用理由もない。
  - 改善: API ID 単位の in/out 表を作り、receive、最小 drag harness、Edit menu API の採否を明記する。

### 低優先度

- **6.1 / 10 画像変換の到達経路**
  - 問題: 公開 content は UTI→raw `Data` なのに `ClipboardImageCoder` と画像 encode/decode error があり、どの OP から使うか追えない。
  - 改善: canonical image 変換を正式フローへ追加するか、未使用 coder/error を v1 から外す。

## 不足項目

- `receiveFilePromises` の保証可能な完了モデル、native async API、専用 UseCase、result、timeout/cancel/lifetime 契約
- Manager が一元所有する delegate/session coordinator と Domain-only handle
- Unity Bridge 全 endpoint の callback、JSON schema、C文字列寿命、thread、NULL、exactly-once 契約
- `PasteButton` の `NSItemProvider` load、部分失敗、cancel、寿命契約
- `ClipboardLimits` の型、既定値、警告と hard failure の境界
- 検出値の全フィールドを保つ決定的 Domain mapping
- File Promise、PasteButton、Bridge、observer 再入、session race を覆うテスト
- 企画書の API ID ごとの採用・内部限定・対象外の完全対応表

## 総合評価

設計の土台は強く、research v3 で確定した危険点を中心に置けている。一方、現状はまだ実装開始可能な確定版ではない。特に `receiveFilePromises` は SDK が保証しない count に完了判定を依存し、Port の Presentation 依存、delegate 所有規約、MainActor と同期 Bridge の境界、PasteButton の非同期 load が実装を直接阻害する。高優先度を先に再設計し、その結果に合わせてエラー表、レイヤー対応表、Bridge schema、テスト、DoD を再同期する必要がある。
