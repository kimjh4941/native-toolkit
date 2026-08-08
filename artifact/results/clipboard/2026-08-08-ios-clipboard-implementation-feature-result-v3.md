# 実装結果レポート v3（実装レビュー v2 反映）

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v2.md`
- 前版: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v2.md`
- ブランチ: feature/NTKIT-14

## 1. 実装サマリー

### 1.1 レビュー指摘の反映（high 1件）

| ID | 指摘 | 反映内容 | 状態 |
|---|---|---|---|
| H-01 | source file size を検証できない場合でも一時領域へコピーを開始する | `startFileLoad` の分岐を `preCopySize == nil` → **即 `fileCopyFailed`（コピー未実行）** に変更。`preCopySize > maxLoadByteCount` → `contentTooLarge`、それ以外のみ `fileStore.store` へ進む。post-copy 検証は従来どおり維持し、pre / post の両方でサイズ検証不能を失敗として扱う | 解消 |

対応箇所: `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift`（`startFileLoad`）

追加テスト（いずれも「一時ディレクトリが空であること」まで検証）:

- `fileLoadRejectsOversizeSourceWithoutCopyingIt` — 上限超過 source が 1 バイトもコピーされない
- `fileLoadFailsWhenTheSourceSizeCannotBeVerified` — `fileSize` を持たない source（ディレクトリ）でコピーを開始しない
- `fileLoadSucceedsAndProducesACopy` — 正常系がセッションディレクトリ配下へコピーされる

### 1.2 レビュー指摘の反映（medium 5件 / low 1件）

| ID | 反映内容 | 状態 |
|---|---|---|
| M-01 | S11 のキャンセル契約を設計 D-4 どおり**内部 completion と UI コールバックで分離**した。`AggregateResult` に `isCancelled` を追加し、`cancelAll()` は `failures: [.cancelled]` / `isCancelled: true` を**内部 completion へ 1 回だけ**配信する（`Session.deliver` が exactly-once を保証）。UI 抑止は `ClipboardPasteReceiverView` 側で `guard !result.isCancelled` により行う（U-90） | 解消 |
| M-02 | `options.localOnly` 省略時に既定 `true` を採用。型が存在して bool でない場合のみ hard failure とする。あわせて `expirationDate` の ISO 8601 解釈を修正（下記 1.3） | 解消 |
| M-03 | full-module strict build を再計測し、**13 件（Dialog 1 / Notification 8 / Share 4）**を本レポートに記載。v2 レポートの「5 件」が過小だった原因も特定（下記 7.1） | 記録を訂正 |
| M-04 | 不足していた観点にテストを追加（U-111 の 3 者到着順、image / file の境界、temp cleanup、S11 内部 completion と UI callback の分離、`options: {}` の既定値）。U-83 は**実装側を設計に合わせて修正**（空 provider 配列 → items / failures とも空）。observer 世代 gate の直接再現のみ未達（下記 7.3） | 部分解消 |
| M-05 | `ClipboardProviderLoadHandle.cancel` / `ClipboardProviderLoadExecutor.requestKind` / `ClipboardPasteReceiverView.cancelPendingLoad` へ先頭ログを追加。値は出さず kind / count のみ | 解消 |
| L-01 | 本レポートにレビュー対象時点および現在の build number を明記（下記 7.2） | 解消 |

### 1.3 反映作業中に判明した追加不具合（M-02 関連）

`options.localOnly` の既定値テストを追加したところ、`{"options": {"expirationDate": "2026-08-08T00:00:00Z"}}` が `CLIPBOARD_INVALID_REQUEST` になることが判明した。

- 原因: `iso8601Formatter` が `[.withInternetDateTime, .withFractionalSeconds]` 固定であり、**小数秒のない ISO 8601 文字列を解釈できない**
- 設計の schema は `expirationDate` を「ISO 8601 string」としか規定しておらず、小数秒必須は過剰な制約
- 対応: `parseISO8601(_:)` を追加し、小数秒あり → なしの順にフォールバックする。シリアライズ側は従来どおり小数秒付きで出力する
- 追加テスト: `expirationDateAcceptsISO8601WithAndWithoutFractionalSeconds`（2 ケース）、`malformedExpirationDateIsRejected`

### 1.4 実装判断

- **`ClipboardAsyncRaceCoordinator.attach` / `resolve` を `private` → `internal` へ変更**: U-111 は「completion / cancel / timeout の 3 者について 3 通りの到着順序を検証」を要求するが、`run` 経由では到着順序を決定的に制御できない。gate 本体を直接駆動できるよう可視性を internal に上げ、`resolve` は「配信した側のみ `true`」を返す `@discardableResult Bool` とした。外部モジュールへの露出はない
- **U-83 は実装側を設計に合わせた**: 空 provider 配列を `failures == [.noMatchingItem]` としていたのは loader の越権であり、`.noMatchingItem` への変換は U-89 のとおり `ClipboardPasteReceiverView` の責務。loader は「items / failures とも空」を返すよう修正した

## 2. 変更ファイル

### 2.1 新規作成

- `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/ClipboardPasteReceiverViewTests.swift`（U-86〜U-91 相当、6 ケース）

### 2.2 変更（実装）

- `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift` — H-01、M-05
- `ios/IosLibrary/IosLibrary/Clipboard/Data/Concurrency/ClipboardAsyncRaceCoordinator.swift` — M-04（`attach` / `resolve` の可視性と戻り値、`run` の先頭ログ）
- `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift` — M-01、M-04（U-83）
- `ios/IosLibrary/IosLibrary/Clipboard/Presentation/ClipboardPasteReceiverView.swift` — M-01（UI 抑止）、M-05
- `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift` — M-02、1.3

### 2.3 変更（テスト）

- `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardProviderLoadExecutorTests.swift` — image / file 境界、pre-copy size 検証、cancel / timeout 後の temp cleanup（+9 ケース）、`@Suite(.serialized)` 化
- `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardAsyncRaceCoordinatorTests.swift` — U-111 の 3 到着順 + 早期 cancel 後の late arrival（+2 ケース）
- `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/PasteItemProviderLoaderTests.swift` — 内部 completion の `.cancelled` 1 回、temp ディレクトリ残存なし、U-83（+1 ケース、3 ケース書き換え）
- `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/IosClipboardManagerTests.swift` — `@Suite(.serialized)` 化、世代 gate テストの強化
- `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardJsonParserTests.swift` — `localOnly` 既定値、ISO 8601 の許容形式（+4 ケース）

### 2.4 変更なし

- 既存 Notification / Dialog / Share のソース（設計 DoD 条件を維持）
- 設計書 `2026-08-02-ios-clipboard-design-v4.md`（M-03 の DoD 変更提案は 7.1 に記載し、判断を仰ぐ）

## 3. エラー契約反映

- 追加・変更したエラー経路はいずれも既存 24 ケースへ正規化される
  - pre-copy size 検証不能 → `fileCopyFailed`（`CLIPBOARD_FILE_COPY_FAILED`）
  - S11 キャンセル → 内部 completion のみに `cancelled`（`CLIPBOARD_CANCELLED`）。UI へは伝播しない
  - `options` の型不正 / `expirationDate` の解釈不能 → `CLIPBOARD_INVALID_REQUEST`
- 新規エラーコードの追加なし。公開メッセージは固定英語文のままで、入力値を含まない

## 4. ビルド結果

| 対象 | コマンド | 結果 |
|---|---|---|
| IosLibrary | `xcodebuild -workspace IosWorkspace.xcworkspace -scheme IosLibrary -destination 'generic/platform=iOS Simulator' build` | **BUILD SUCCEEDED** |
| UnityIosPlugin | 同上（`-scheme UnityIosPlugin`） | **BUILD SUCCEEDED** |
| IosLibrary（strict / batch） | `+ SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` | 失敗（exit 65、error 5 件） |
| IosLibrary（strict / wholemodule） | `+ SWIFT_COMPILATION_MODE=wholemodule` | 失敗（exit 65、**error 13 件**） |
| UnityIosPlugin（strict） | 同上 | 依存先 IosLibrary の同一エラーにより失敗（exit 65） |

- **Clipboard 配下に起因する strict error / warning は 0 件**（`strict-wmo` 出力を Clipboard パスで grep して確認）
- 通常ビルドの warning は 0 件

## 5. テスト結果

| 対象 | 実行 | 結果 |
|---|---|---|
| IosLibrary | iPhone 17 Pro / iOS 26.2 Simulator | **184 passed / 0 failed**（v2: 166） |
| UnityIosPlugin | iPhone 17 Pro Max / iOS 26.2 Simulator | **73 passed / 0 failed**（v2: 69） |

### 5.1 今回追加でカバーした観点

- pre-copy size 取得不能時にコピーを開始しないこと（H-01）
- image の入力上限超過 / 上限ちょうど / pixel 数上限超過
- file の正常コピー / 上限超過 / サイズ検証不能
- cancel 後・timeout 後に一時ディレクトリが残らないこと
- completion / cancel / timeout の 3 到着順すべてで配信が 1 回のみ（U-111）
- attach 前 cancel のあとに到着した completion が落ちること
- S11 内部 completion の `.cancelled` 1 回と UI callback 0 回の分離（U-84 / U-90）
- 空 provider 配列で items / failures とも空（U-83）と、その `.noMatchingItem` 化が View 側で起きること（U-89）
- 成功のみ / 成功+失敗（順序込み）/ 全失敗 / 連続 paste の UI コールバック真理値表（U-86〜U-88、U-91）
- `options: {}` と expirationDate のみの `options` で `localOnly` 既定 `true`
- `expirationDate` の小数秒あり / なし双方の受理と、不正文字列の拒否

### 5.2 テスト実行時に判明した問題と対処

- `IosClipboardManagerTests` の observing 系テストは `UIPasteboard.general` を共有するため、並列実行時に他テストの post が別テストの購読者へ届いていた。`@Suite(.serialized)` を付与して解消した
- provider timeout の cleanup テストは、provider が timeout より先に完了してしまい不安定だった。`delayedFileProvider`（表現を遅延返却する provider）を導入し、timeout（0.05秒）と配信（2秒）の差を 40 倍に広げたうえで `ClipboardProviderLoadExecutorTests` も `@Suite(.serialized)` 化した。timeout は main actor 上の Task から発火するため、並列実行による main actor の輻輳で順序が反転しうる（実際に 1 回反転を観測したため対処した）
- 上記いずれもテストコード側の安定化であり、本番の timeout / cancel 契約は変更していない

## 6. Definition of Done（レビュー v2 後の再評価）

判定基準: ○=OK / △=一部OK / ×=未達 / -=対象外

### レビュー v2 項目
- ○ H-01 pre-copy size 検証不能時にコピーを開始しない
- ○ M-01 S11 内部 completion の exactly-once cancel と UI 抑止の分離
- ○ M-02 `options.localOnly` の既定値
- ○ M-03 I-10 実測値の記録訂正（DoD 変更そのものは要判断）
- △ M-04 テスト網羅（observer 世代 gate の直接再現のみ未達）
- ○ M-05 新規 internal API の先頭ログ
- ○ L-01 build number の最終値明記

### 実装
- ○ Clipboard 配下の strict concurrency error / warning が 0 件
- ○ Application 層 Port にプラットフォーム型が含まれない
- ○ `NSItemProvider` が Data 層と Presentation 層に閉じている
- ○ 公開エラーメッセージ・ログが URL / path / pasteboard name / invalid reason を含まない
- ○ 非同期処理のタイムアウト・キャンセル・exactly-once が P-11 と P-16 で同一実装を共有
- ○ copy / load / image / file の全 kind にサイズ上限が実装されている
- ○ サイズ検証不能が pre-copy / post-copy の双方で失敗として扱われる
- ○ Bridge が errorCode を透過し、監視開始失敗を operation callback へ返す
- ○ 既存 Notification / Dialog / Share のファイルに変更がない
- × I-10（両モジュールが strict build で警告・エラーなし）

### テスト
- △ 単体テスト（184 + 73 = 257 件 green）。設計 U-01〜U-148 の全件網羅ではない
- × I-08（15 endpoint / 9 content kind の Bridge end-to-end）
- × I-09（`ClipboardRedaction` の独立モジュール境界テスト）
- × 手動確認 M-01〜M-16（実機必須のため未実施）

## 7. 設計差分・未解決事項

### 7.1 I-10 の実測値と DoD スコープ（要判断）

**レビュー v2 の指摘は正しく、v2 レポートの「Notification 5 件」は過小だった。**

原因: 既定の incremental（batch）コンパイルでは、最初にエラーを出したバッチで打ち切られ、Dialog / Share を含む後続バッチが診断を出す前にビルドが終了していた。`SWIFT_COMPILATION_MODE=wholemodule` を付けて全ファイルを同時にコンパイルすると、レビューと同じ 13 件が再現する。

実測した 13 件（すべて **Clipboard 実装以前から存在**）:

```
Dialog/IosDialogManager.swift:51                              static property 'shared' is not concurrency-safe
Notification/Domain/Model/NotificationAction.swift:17,19,21   static property ... (NotificationActionOptions)
Notification/Domain/Model/NotificationCategoryOptions.swift:18,20,22,24
Notification/IosNotificationManager.swift:58                  static property 'shared'
Notification/Presentation/Permission/NotificationPermissionHelper.swift:15
Share/IosShareManager.swift:30                                static property 'shared'
Share/Presentation/ShareSheetPresenter.swift:45 ×2            non-Sendable parameter / return type
```

再現コマンド:

```
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme IosLibrary \
  -destination 'generic/platform=iOS Simulator' \
  SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete SWIFT_COMPILATION_MODE=wholemodule build
```

**Clipboard 由来の診断は 0 件**である。

レビューの指摘どおり、これは論理矛盾ではなく**スコープ衝突**である。推奨は次のとおりで、いずれも設計書 v4 の改訂を伴うため本タスクでは実施していない。

- 推奨案: 既存機能（Dialog / Notification / Share）の Swift 6 移行を**別タスクへ切り出し**、本タスクの DoD を「**Clipboard 差分が新しい strict 診断を追加しないこと**」へ変更する
- 代替案: 現行 I-10 を維持し、Dialog / Notification / Share の修正を本タスクの明示スコープへ追加する（`IosDialogManager.shared` / `IosShareManager.shared` / `NotificationPermissionHelper.shared` の isolation 変更は既存機能の挙動に影響しうるため、各機能のレビューが必要）

**どちらを採るかご判断ください。**

### 7.2 build number（L-01 への回答）

- レビュー v2 対象時点（未コミット差分）: IosLibrary **8 → 9**、UnityIosPlugin **7 → 8**
- 本 v3 の成果物再生成後の現在値: IosLibrary **9 → 10**、UnityIosPlugin **8 → 9**
- 由来は v2 レポート 7.2 のとおり `scripts/build_ios_library_xcframework.sh` の自動インクリメント仕様（同スクリプト 184〜305 行）であり、手動編集ではない

### 7.3 observer 世代 gate の直接再現（M-04 の残件）

世代 gate の本来の目的である「**旧購読向けに既に main queue へ積まれた block が新購読者へ届かないこと**」は、テストで直接再現できていない。

再現には「バックグラウンドスレッドから notification を post し、main queue を drain させないまま stop / start する」必要があるが、main thread をセマフォでブロックした状態で UIKit 通知をバックグラウンドから post するとシミュレータがデッドロックする（実測で検証し、ハングを確認したうえで撤回した）。

現状カバーしているのは「同一 scope で stop → start しても旧購読者が発火せず、新購読者へ二重配信されないこと」までである。制約はテストコード内にもコメントとして記載した。

### 7.4 ビルドスクリプトの不具合（参考・未修正）

`scripts/build_ios_library_xcframework.sh:292` は `--library-version` 省略時に `XCODE_EXTRA_SETTINGS[@]: unbound variable` で失敗する（空配列展開が `set -u` に抵触）。今回は `--library-version 1.2.0`（現行値と同一）を指定して回避した。Clipboard のスコープ外かつ共有ビルド基盤のため未修正。

### 7.5 その他の設計差分（v1 / v2 から継続）

- `ClipboardTypeIdentifierValidator` を `internal` → `public`（default 引数の可視性制約）
- `UIColor` の表現型識別子 `"com.apple.uikit.color"` は公式ドキュメント未確認の実装時判断。**要検証**
- T-00（実機プライバシー検証）/ T-12（サンプルアプリ）/ T-13（実機手動確認 M-01〜M-16）は未実施

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
