# macOS Clipboard 機能実装レビュー v1

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 差分: `git diff develop...HEAD`（112 files、+29,310 / -19）
- 対象コミット: `b3b398e5`、`01825f11`
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 実装結果: `artifact/results/clipboard/2026-08-29-macos-clipboard-implementation-feature-result-v2.md`
- 企画書: `artifact/plans/clipboard/2026-08-29-macos-clipboard-research-v3.md`

## レビュー概要

- Clipboard の Domain / Application Port・UseCase / Data / Presentation / Manager / Unity Bridge とテストを追加する差分。
- 設計書 §13 の T-01〜T-17 はコード差分で実装を確認した。T-18（サンプルアプリ）は未着手だが、確定済みのスコープどおりであり指摘対象にしていない。
- 実装結果 v2 の記載対象が T-01 / T-02 / T-11a / T-11b に限られることは、T-03〜T-17 の未実装根拠として扱っていない。
- 提示済みの検証結果（MacLibrary 405 件、UnityMacPlugin 72 件、失敗 0 件、Clipboard 由来 strict concurrency 診断 0 件）を前提事実として扱った。追加のテスト再実行はしていない。
- `scripts/check_design_consistency.py` はレビュー時にも実行し、22 検査すべて通過した。

## 重大な問題（high）

### H-1: PasteButton の timeout が応答しない provider を打ち切れず、`onPaste` が永久に返らない

- 設計書 §7.11（917〜918、946〜948 行）は、全体 timeout 到達時に未完了 provider を `pasteLoadTimedOut` として確定し、その時点の結果で `onPaste` を exactly-once で呼ぶ契約としている。
- `ClipboardPasteLoader.loadAll` は `withTaskGroup` 内で sleep と provider task を競争させ、timeout 後に `group.cancelAll()` するが、task group はスコープを抜ける前に全 child task の終了を待つ（`mac/MacLibrary/MacLibrary/Clipboard/Presentation/ClipboardPasteLoader.swift:106-134`）。
- 実 provider の `ItemProviderSource.loadData` は `withCheckedThrowingContinuation` で `NSItemProvider.loadDataRepresentation` を待つだけで、返された `Progress` を保持・cancel せず、Task cancellation も continuation へ接続していない（`mac/MacLibrary/MacLibrary/Clipboard/Presentation/PasteButtonFactory.swift:32-45`）。provider が callback を返さない場合、sleep が勝っても child task が終わらず `loadAll` が戻らないため、timeout 契約を満たせない。
- 影響: ハングした provider が 1 件あるだけで `pasteLoadTimedOut` も `onPaste` も届かず、UI 操作が無期限に完了しない。
- 修正案: 非構造化 task / actor 管理の completion gate など、deadline 到達時に結果を確定して呼び出し元へ戻れる構造にし、`loadDataRepresentation` の `Progress` を保持して cancel する。callback の late arrival は世代トークンで破棄する。callback を一切返さない Source を使う PT-03 相当テストを追加する。

### H-2: File Promise 受領が最初の callback 前にも quiet timeout で終了し、遅い provider の全結果を捨てる

- 設計書 §7.12（1241〜1250、1255〜1261 行）は、`quietInterval` を「最後の reader 到達から」の時間、`overallTimeout` を「1 件も来なくても必ず終端する」期限として分離し、極端に遅い provider は overall timeout まで待つとしている。
- `FilePromiseReceiptSession.start` は reader が 1 件も到達していない開始時点で `restartQuietTimer()` を呼ぶ（`mac/MacLibrary/MacLibrary/Clipboard/Data/Promise/FilePromiseReceiptSession.swift:59-71`）。既定値では開始 2 秒後に空の `.finished(.quiescence)` を配送し、以後の callback は `accept` で破棄される（同ファイル 115〜124 行）。
- 影響: 最初のファイル生成に 2 秒超かかる正常な provider からは、既定 overall timeout 60 秒を待たず全ファイルを失う。Bridge / stream / 集約 async の全 OP-18 経路に波及する。
- 修正案: quiet timer は最初の `recordReceived` / `recordFailure` で初めて開始し、開始直後は overall timer のみを動かす。0 件到達時に `.overallTimeout` となるテストと、最初の到達が quietInterval より遅いが overallTimeout より早いテストを追加する。

### H-3: Unity ObjC Bridge がクリップボード内容を平文ログへ出力する

- 設計書 §4.2（331〜339 行）は内容そのものをログへ出さず、文字列は長さ、Data はバイト数、名前付き pasteboard は短縮ハッシュにする契約である。実装 DoD §15（2463 行）も秘匿済みログを完了条件にしている。
- `clipboardCopy` は Base64 化された全 representation を含む `contentJson` を `%s` で記録し、`clipboardAppend` も同様に `contentJson` を記録する（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.m:17-19`, `32-34`）。さらに多くの endpoint が `scopeJson` / named pasteboard request を平文記録している。
- 影響: パスワード、トークン、画像・文書などクリップボード上の機密データがデバッグ／収集ログへ複製される。ログ保存期間と送信先によってはデータ漏えいになる。
- 修正案: ObjC Bridge にも秘匿ログ helper を設け、content は長さ・item 数・byte 数だけ、scope は general または短縮ハッシュだけを記録する。BT-16 を `sourcePath` だけでなく copy / append / named scope の非漏えいまで拡張する。

### H-4: 同じ PasteButton は 2 回目以降の押下結果を一切通知しない

- 設計書 §7.11 は PasteButton の payload ごとにロードし `onPaste` を exactly-once で返す公開 UI を定義しており、Manager DocC も「per press」の契約を記載している。
- `ClipboardPasteLoader` の `hasDelivered` は loader の生存期間全体で 1 個だけで、`deliver` 後に永続的に `true` となる。`load(from:)` は次の押下時にこれをリセットせず、新しい task を開始しても `deliver` が結果を捨てる（`mac/MacLibrary/MacLibrary/Clipboard/Presentation/ClipboardPasteLoader.swift:34-37`, `63-77`, `89-94`）。
- 影響: 返却された PasteButton は最初の 1 回しか機能せず、2 回目以降の正常な貼り付け操作が無反応になる。
- 修正案: exactly-once state を押下ごとの generation / operation state に分離する。新しい押下時に前回 task を cancel し、新 generation の結果だけを 1 回配送するテストを追加する。

## 改善提案（medium）

### M-1: File Promise 解放後も handle ごとの空 staging directory が残る

- 設計書 §7.12（1165〜1167 行）と §8.4.5（1942〜1949 行）は `<ClipboardPromise>/<handleId>/` を staging path とし、release / stale / rollback で staging を削除する契約である。
- `FilePromiseSnapshotter.snapshot` は `<handleId>/<source.lastPathComponent>` を返し（`mac/MacLibrary/MacLibrary/Clipboard/Data/Promise/FilePromiseSnapshotter.swift:41-73`）、coordinator はその子 URL を state に保存して `discard` する（`mac/MacLibrary/MacLibrary/Clipboard/Manager/ClipboardSystemCoordinator.swift:224-235`, `296-302`）。`discard` は渡された子だけを削除するため、親の `<handleId>/` が残る（Snapshotter 76〜85 行）。既存 IT-33 は子ファイルの消滅だけを検証しており親を確認していない。
- 修正案: state が staging root と fulfillment source を別々に保持するか、discard API を root 単位に統一し、明示 release / stale / rollback の各テストで handle directory 自体の消滅を確認する。

### M-2: stale query と変更監視が Manager から Repository を直接呼んでいる

- `common.md` 81〜87 行は Manager → Repository の直接呼び出しを禁止する。設計書 §6.5.1（544〜565 行）も stale query を `useCases.getChangeCount` 経由に固定している。
- `MacClipboardManager` は repository を initializer 引数で受け、monitor の `readChangeCount` と coordinator の `staleQuery` から `repository.changeCount` を直接呼ぶ（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:105-123`）。設計された `getChangeCount` UseCase も存在しない。
- 修正案: 副作用のない `GetChangeCountUseCase` を Application 層へ追加し、monitor / stale query とも同 UseCase を注入する。

### M-3: 不正な `optionsJson` が parse error にならず既定値として受理される

- 設計書 §8.4.1（1647〜1648 行）は必須引数 NULL を 1302、JSON parse 失敗を 1301 とする。§8.4.4（1800〜1801 行）の「すべて optional」は `OptionsJson` のフィールドを省略可能にする契約であり、不正 JSON を許容する契約ではない。
- `parseOptions` は absent と malformed を区別せず、decode 失敗時に `.default` を返す（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardJsonParser.swift:329-334`）。`copy` facade も失敗判定せず処理を続行する（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManager.swift:87-102`）。
- 影響: 呼び出し側の JSON バグが成功として隠れ、特に `localOnly: false` の要求が黙って `true` へ変わる。
- 修正案: C NULL / Swift nil のみ既定値とし、非 nil 文字列の decode 失敗は 1301 を返す。nil、`{}`、正常値、不正 JSON を分けた Bridge テストを追加する。

## 軽微な指摘（low）

- なし。

## 設計書整合性チェック

- 企画書との整合性: ○
- Clean Architecture 準拠: △（M-2）
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △（H-1 / H-2 / H-4 / M-1 の実害シナリオが未検出）
- ドメインエラー全ケース実装: ○（25 ケースと 1501〜1524 / 1599 を確認）
- エラーコード/メッセージ対応表との整合: ○

## プロジェクトルール適合チェック

- `common.md` 準拠: △（Manager → Repository の直接経路あり。M-2）
- `mac.md` 準拠: △（ログ配置・型・DocC は概ね準拠するが、設計 §4.2 の秘匿契約に反するログあり。H-3）
- エラー契約反映: △（通常の Domain / Manager callback 契約は整合。不正 `optionsJson` の 1301 契約のみ不整合。M-3）
- 既存 API 互換性: ○（新規 API が中心で、既存 `BridgeError` は DocC 変更のみ）

## テストカバレッジ

- カバー済み: Domain error 25 ケース、設定境界、UTI、Repository の copy / append / read / snapshot、File Promise lifecycle・race・receipt、変更監視、Paste loader の通常 timeout、Manager callback、Bridge JSON / callback 契約。
- 検証済み事実: MacLibrary 405 件、UnityMacPlugin 72 件、失敗 0 件。strict concurrency の Clipboard 由来診断 0 件。
- 不足:
  - callback を永久に返さず Task cancellation にも反応しない provider に対する Paste loader deadline（H-1）
  - OP-18 で最初の reader 到達が quietInterval より遅いケース、および 0 件時の終端理由（H-2）
  - 同じ PasteButton / loader の連続 2 回押下（H-4）
  - File Promise 解放後の子ファイルだけでなく handle root directory の削除（M-1）
  - ObjC Bridge の copy / append / named scope ログ非漏えい（H-3）
  - `optionsJson` の nil / 空 object / malformed の区別（M-3）

## 総合評価

**要修正（重大）**

OP-18 と PasteButton の完了契約に利用者が結果を受け取れない／正常結果を失う不具合があり、Clipboard 内容の平文ログ出力もあるため、修正後の再レビューが必要。
