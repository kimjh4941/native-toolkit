# macOS Clipboard 機能実装レビュー v2

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`（112 files、+29,310 / -19）
- 修正差分: 未コミットの `git diff`（追跡対象 21 files、+538 / -177）および未追跡の `GetChangeCountUseCase.swift`
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v3.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v1.md`
- T-18（サンプルアプリ）および Swift 6 移行は指定どおり対象外

## 結論

- 前回の 7 件は **解消 6 件、部分解消 1 件**。H-1 の主症状である deadline 後の永久待機と continuation の二重 resume は解消したが、`Progress` の設定とキャンセルが競合すると underlying provider を cancel できない窓が残る。
- 新規の high は 0 件、medium は 3 件、low は 0 件。
- MacLibrary 413 件、UnityMacPlugin 73 件はレビュー時にも再実行して両方 `TEST SUCCEEDED`。提示済みの strict concurrency（Clipboard 由来 0 件）とも矛盾はない。
- 総合判定は **マージ保留（medium 修正後に再確認）**。特に M-4 は View 破棄／supersede／deadline 後にも provider 処理が残り得るため、マージ前の修正を推奨する。

## 前回指摘 7 件の解消状況

| ID | 判定 | 根拠 | 実害シナリオの評価 |
|---|---|---|---|
| H-1 | **部分解消** | `ClipboardPasteLoader.load(from:)` は provider ごとの非構造化 `Task` と独立した `deadlineTask` を開始し、`settleByDeadline` は未完了 task を await せず結果を確定する（`mac/MacLibrary/MacLibrary/Clipboard/Presentation/ClipboardPasteLoader.swift:84-116,157-179`）。`PasteButtonFactory.ItemProviderSource.loadData` は `LoadGate` で callback と cancel の競合を exactly-once resume にする（`mac/MacLibrary/MacLibrary/Clipboard/Presentation/PasteButtonFactory.swift:32-55,101-137`）。一方、`ProgressBox` には cancel 済み状態がなく、M-4 の競合が残る。 | callback を返さない Source があっても deadline で `onPaste` が届くため、前回の永久待機は解消。二重 resume も gate で遮断。ただし underlying `NSItemProvider` 処理のキャンセル保証は未完了。 |
| H-2 | **解消** | `FilePromiseReceiptSession.start` から `restartQuietTimer()` が削除され、overall timer のみ開始する（`mac/MacLibrary/MacLibrary/Clipboard/Data/Promise/FilePromiseReceiptSession.swift:59-75`）。既存の `recordReceived` / `recordFailure` が到達後に quiet timer を開始する。 | 最初の到達が quiet interval より遅い正常 provider を早期終了しない。0 件時は overall timeout まで待つ。 |
| H-3 | **解消** | C 層の `NTLen` / `NTScope` と各 endpoint のログ置換（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.m:17-36,40-304`）、Swift の `ClipboardLog.json` / `scopeJson`（`mac/MacLibrary/MacLibrary/Clipboard/Common/ClipboardLog.swift:68-86`）、parser / façade の置換を確認。 | `contentJson`、ownership/request JSON、named scope の平文はログへ出ない。パスワード・文書・pasteboard 名がログへ複製される前回経路は遮断。BT-25 の自動回帰検査は M-5 のとおり不足。 |
| H-4 | **解消** | loader-wide の `hasDelivered` を廃止し、`generation` / `deliveredGeneration` と supersede 時の `stopInFlightWork()` を導入（`ClipboardPasteLoader.swift:46-58,84-99,128-179`）。 | 2 回目の押下も独立して配送され、旧世代の遅延結果は `record` の generation guard で破棄される。cancel 後は `isCancelled` により恒久的に配送しない。 |
| M-1 | **解消** | `ProvideFilePromiseUseCase` の late-cancel rollback は child `staged` ではなく `root` を discard（`mac/MacLibrary/MacLibrary/Clipboard/Application/UseCase/ProvideFilePromiseUseCase.swift:55-69`）。coordinator の通常／stale／write-failure 共通 release も handle から root を再構築して discard（`mac/MacLibrary/MacLibrary/Clipboard/Manager/ClipboardSystemCoordinator.swift:224-241`）。 | 明示 release、stale release、write rollback、copy 完了後 cancel のいずれも `<handleId>/` 自体を削除する実装となり、空 root の蓄積経路は解消。 |
| M-2 | **解消** | `GetChangeCountUseCase` を新設し repository 呼び出しを Application 層に隔離（`mac/MacLibrary/MacLibrary/Clipboard/Application/UseCase/GetChangeCountUseCase.swift:16-34`）。`ClipboardUseCases.changeCount` へ集約し、monitor と stale query は双方 `useCases.changeCount` を呼ぶ。Manager initializer の repository 引数も削除（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:101-122`）。 | Manager → Repository の直接経路はなくなり、監視／stale 判定とも同じ UseCase 経路を通る。 |
| M-3 | **解消** | `parseOptions` は nil／空を `.default`、非空 decode 失敗を `nil` とする（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardJsonParser.swift:329-340`）。`UnityMacClipboardManager.copy` は nil を `.parseFailed` へ渡す（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift:87-107`）。`BridgeError.parseFailed` の契約により 1301 となる。 | 不正 JSON が成功として既定値へ丸められず、`localOnly: false` の要求が黙って `true` になる経路は遮断。façade の 1301 を直接確認するテストは M-5 のとおり不足。 |

## 新規に発見した問題

### M-4: `Progress` の生成と Task cancellation が競合すると provider 処理を cancel できない

- `ItemProviderSource.loadData` の cancellation handler は `progress.value?.cancel()` の後に gate を完了する（`mac/MacLibrary/MacLibrary/Clipboard/Presentation/PasteButtonFactory.swift:37-55`）。しかし `ProgressBox.value` の setter は値を保存するだけで、既に cancel 要求が来たかを保持しない（同:89-99）。
- 次の順序が成立する。
  1. Task が既に cancel 済み、または `loadDataRepresentation` の呼び出し中に cancel される。
  2. `onCancel` が `progress.value == nil` を読み、gate だけを `CancellationError` で完了する。
  3. operation 側が `loadDataRepresentation` から返った `Progress` を後から `progress.value` に保存する。
  4. 保存された `Progress` は cancel されず、provider callback まで underlying 処理が残る。
- `LoadGate` が continuation の二重 resume を防ぐため loader の deadline／配送は止まらないが、View 破棄、supersede、deadline 後にも provider の読み込み・資源保持が継続し得る。設計書 §7.11（931〜948 行）の「`Progress.cancel()`」契約を完全には満たさない。
- 修正案: `ProgressBox` に `isCancelled` を持たせ、`cancel()` と `install(_:)` を同じ lock で直列化し、cancel 後に install された `Progress` も直ちに cancel する。cancel-before-install と install-before-cancel の両順序を本番 adapter 経由でテストする。

### M-5: 追加テストの一部が、修正した本番境界を通らず回帰を検出できない

- PT-09〜PT-13 は `ClipboardPasteLoader` 本体の generation／deadline を直接通るため、その部分の実経路性は高い。ただし全て `FakeSource` / `HangingSource` を注入し、H-1 で同時に修正した `PasteButtonFactory.ItemProviderSource`、`ProgressBox`、`LoadGate` を一度も実行しない（`mac/MacLibrary/MacLibraryTests/Clipboard/Presentation/ClipboardPasteLoaderTests.swift:265-362`）。このため M-4 を検出できない。既存 PT-05 も delivery 抑止だけで `Progress.cancel()` を観測していない（同:230-250）。
- IT-51 / IT-52 相当は本番 `FilePromiseReceiptSession` を直接生成してタイマー状態機械を通るため H-2 の原因箇所は実経路である（`mac/MacLibrary/MacLibraryTests/Clipboard/Data/FilePromiseReceiptSessionTests.swift:97-145`）。ただし Repository → session callback の接続まで含む OP-18 統合経路ではない。
- IT-53 は実 `ClipboardSystemCoordinator`、実 `FilePromiseSnapshotter`、実 filesystem を通り、release 後に child と root の双方が消えることを確認するため、M-1 の通常 release 経路を十分に覆う（`mac/MacLibrary/MacLibraryTests/Clipboard/Data/FilePromiseProvisionTests.swift:263-283`）。late-cancel test は discard URL が root であることを assert していない（`FilePromiseUseCaseTests.swift:165-180`）。
- BT-24 相当は parser の nil／空／正常／不正を確認するが、`UnityMacClipboardManager.copy` を呼ばず callback の `errorCode == 1301` を検証していない（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardJsonParserTests.swift:113-135`）。
- BT-25 は追加されていない。既存 `UnityMacClipboardBridgeTests` の privacy 検査は `clipboardProvideFilePromise` の `sourcePath` だけであり、copy / append / named scope のログ式を検査しない（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift:183-193`）。
- 修正案: `NSItemProvider` の data representation handler を使う factory-level cancel test、façade callback の 1301 test、C source の全 endpoint に raw `contentJson` / `scopeJson` がないことを検査する BT-25 を追加する。

### M-6: 設計書 §7.11 に H-1 修正前の `withTaskGroup` 指示が残り、実装と正面から矛盾する

- 設計書 §7.11 の 931〜933 行は「provider task は非構造化」「deadline は未完了 task を待たない」と正しく更新され、実装も `ClipboardPasteLoader.load(from:)` の非構造化 task 群と独立 deadline に一致する。
- しかし直後の §7.11「timeout の実装」（959〜961 行）は、依然として「`withTaskGroup` に sleep task を足して競争」と指示している。これは H-1 を再発させる旧方式であり、同じ節の新記述および現実装と矛盾する。
- §13 の T-14 完了条件も PT-01〜PT-08 のままで PT-09〜PT-13 を含まず（2339 行）、§15 の完了条件も PT-01〜PT-08／IT-21〜IT-50／BT-01〜BT-19 のまま（2484〜2487 行）。§8.4.5 の手順番号も 7 が重複する（1963〜1964 行）。
- `scripts/check_design_consistency.py` は22検査すべて通過するが、これらの意味上の矛盾は検査対象外である。
- 修正案: 959〜961 行を非構造化 task + 独立 deadline の記述へ置換し、T-14 と DoD のテスト範囲を PT-13／IT-53／BT-25 まで更新する。手順番号も連番へ直す。

## 追加テストの実経路カバレッジ評価

| テスト | 評価 | 理由 |
|---|---|---|
| PT-09 | ○ | 同じ production loader instance を2回 `load` し、押下単位の generation 配送を確認。 |
| PT-10 | ○ | production `stopInFlightWork` と generation guard を通り、旧世代の遅延完了を破棄。 |
| PT-11 | ○ | production `isCancelled` guard を通り、cancel 後の load を抑止。 |
| PT-12 / PT-13 | △ | 無応答 Source に対する production loader deadline は実行するが、production `ItemProviderSource`／Progress cancellation 境界は通らない。 |
| IT-51 / IT-52 | ○（session 層） | production `FilePromiseReceiptSession` の start／arrival／terminal 状態機械を直接実行。OP-18 全層統合ではないが、H-2 原因箇所を正しく覆う。 |
| IT-53 | ○（通常 release） | production coordinator、snapshotter、filesystem を通り root の実削除を確認。late-cancel root 引数の assertion は不足。 |
| BT-24 | △ | parser の4分類は確認するが、façade callback の 1301 までは通らない。 |
| BT-25 | × | 該当テスト自体が存在せず、既存 privacy test の対象は sourcePath のみ。 |

## 設計書との整合性

- §6.5.1 の `GetChangeCountUseCase`、§7.11 の generation／非構造化 deadline、§7.12 の quiet timer、§8.4.4 の absent／malformed 区別、§8.4.5 の staging root 削除、§12 の追加テスト一覧は実装方針と一致する。
- §4.2 のログ秘匿は C／Swift 実装に反映されている。
- 一方、M-6 の旧 `withTaskGroup` 指示と完了条件のテスト範囲が未更新であり、設計書全体としては **一部不整合**。
- 機械照合スクリプトはレビュー時に再実行し、22 / 22 項目が通過した。

## プロジェクトルール適合

- Clean Architecture: ○。M-2 の Manager → Repository 直結は解消。
- macOS / Swift concurrency: ○。提示済みの Clipboard 由来 strict concurrency 診断 0 件を前提とし、今回の再実行でも build / test は成功。
- ログ秘匿: 実装は○、自動回帰検査は△（M-5）。
- cancellation / exactly-once: continuation と配送は○、underlying Progress cancellation は△（M-4）。

## 検証結果

| 検証 | 結果 |
|---|---|
| `xcodebuild test -workspace MacWorkspace.xcworkspace -scheme MacLibrary -destination 'platform=macOS'` | `TEST SUCCEEDED`（413件 / 0失敗） |
| `xcodebuild test -workspace MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS'` | `TEST SUCCEEDED`（73件 / 0失敗） |
| strict concurrency（提示済み結果） | unique 173件、Clipboard由来 0件 |
| `python3 scripts/check_design_consistency.py <design-v7>` | 22 / 22 通過 |
| `git diff --check` | 問題なし |

## 総合判定

**マージ保留（medium 3 件）**

前回の high 4 件が生んだ「永久待機」「遅い初回結果の喪失」「平文ログ漏えい」「2回目押下の無反応」はコード上すべて遮断され、M-1〜M-3 の本体修正も正しい。新規 high はない。ただし H-1 の修正境界に `Progress` cancellation race が残り、その境界を追加テストが通っていない。M-4 と回帰テストを修正し、H-1 を完全解消したうえでマージ可とする。設計書の矛盾（M-6）も同時に解消すること。
