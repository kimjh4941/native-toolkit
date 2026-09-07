# 実装結果レポート v4（実装レビュー v3 反映）

> **Errata（2026-08-08）**
> 本レポートの **strict 診断評価は誤りであり、v5 で訂正済み**。
> 「Clipboard 由来は 0 件」（§4 / §6 / §7.1）は成立しない。正しくは 19 件。
>
> なお「新規追加した `isolated deinit` は strict build で新たな診断を発生させていない」という
> **個別主張自体は現在も成立する**（Swift 5 strict の再計測でも `isolated deinit` 起因の診断はない）。
> ただし当時の計測方法では、これを **Clipboard 全体が 0 件である根拠にはできなかった**。
> 撤回対象は「Clipboard 全体 0 件」の評価であり、`isolated deinit` の評価ではない。
>
> 訂正: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v5.md`
> 監査性のため本文は当時のまま保持している。

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v3.md`
- 前版: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v3.md`
- ブランチ: feature/NTKIT-14

## 1. 実装サマリー

### 1.1 レビュー指摘の反映（high 1件）

**H-01: `PasteItemProviderLoader` 解放時に pending load を cancel せず、一時 file が残りうる**

設計 D-16 / S6 が要求する `isolated deinit` が `PasteItemProviderLoader` に存在しなかった。指摘は正しく、以下を実装した。

```swift
isolated deinit {
    Log.d(TAG, "[deinit] hasPendingSession: \(currentSession != nil)")
    cancelAll()
}
```

- 対象: `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift`
- 効果: loader（＝それを保持する receiver）が解放された時点で全 handle が cancel され、`ClipboardProviderLoadHandle.finish` が resolved 状態になる。その後に provider の file 表現が到着しても「解決済み late result」経路に入り、`fileStore.discard` で一時ディレクトリごと削除される
- これが無い場合、集約クロージャが loader を `[weak self]` で保持しているため、**成果物 file は呼び出し側に渡らず、かつ誰にも削除されない**状態になっていた

推奨経路（`ClipboardPasteControlContainerView`）は従来どおり container の `isolated deinit` が動くが、公開 API である `PasteControlFactory.makeComponents` 経路は container を経由しないため、loader 自身の deinit が唯一の cleanup 契機になる。

追加テスト:

- `PasteItemProviderLoaderTests.releasingTheLoaderCancelsPendingLoadsAndDiscardsLateFiles`
  — loader を解放した時点で内部 completion が `.cancelled` を**1回**受け取り、その後 1 秒遅れで到着する file 表現がセッションディレクトリに残らないことを検証（deinit が無ければ「1回」の時点で落ちる回帰テスト）
- `ClipboardPasteReceiverViewTests.releasingTheReceiverCleansUpPendingFileLoads`
  — raw factory 経路相当。receiver のみを解放しても UI コールバックが 0 回（U-90）で、遅延到着 file が残らないこと

### 1.2 レビュー指摘の反映（medium 3件）

| ID | 反映内容 | 状態 |
|---|---|---|
| M-01 | strict error の module 別内訳を **Dialog 1 / Notification 9 / Share 3** へ訂正（下記 7.1）。v3 レポートの「Notification 8 / Share 4」は分類ミス | 解消 |
| M-02 | 「通常ビルドの warning 0件」を撤回。clean build で実測した 2 件を明記し、**Clipboard 由来 0 件**と target 全体の warning を区別して記載（下記 7.1） | 解消 |
| M-03 | `ClipboardProviderLoadExecutor.FailureDetailCode`（`domain` / `sourceSizeUnverifiable = -3` / `copiedSizeUnverifiable = -2`）を導入し、`fileLoadFailsWhenTheSourceSizeCannotBeVerified` が error code だけでなく**どの境界で弾かれたか**まで検証するようにした。provider 側の representation error では通らない | 解消 |

### 1.3 I-10 の方針（レビュー判断を反映）

レビュー v3 で「既存 Dialog / Notification / Share の Swift 6 移行を別タスクへ切り出す方針でよい」との判断を受領した。本タスクでは引き続き既存 3 機能のソースを変更していない。

設計 v4 の改訂（I-10 の分離）は design ワークフローの対象であり、本タスクの実装差分としては行っていない。改訂案は 7.2 に記載する。

## 2. 変更ファイル

### 2.1 変更（実装）

- `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift` — H-01（`isolated deinit`）
- `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift` — M-03（`FailureDetailCode` の導入と適用。マジックナンバー `-2` / `-3` を置換）

### 2.2 変更（テスト）

- `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/PasteItemProviderLoaderTests.swift` — loader 解放時の cancel / 遅延 file cleanup（+1 ケース、`delayedFileProvider` ヘルパー追加）
- `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/ClipboardPasteReceiverViewTests.swift` — receiver 解放時の cleanup と UI 非配信（+1 ケース）
- `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardProviderLoadExecutorTests.swift` — size 検証不能テストを failure detail まで検証するよう強化

### 2.3 変更なし

- 既存 Notification / Dialog / Share のソース
- 設計書 `2026-08-02-ios-clipboard-design-v4.md`（改訂案は 7.2）

## 3. エラー契約反映

- 新規エラーコードの追加なし
- loader 解放時のキャンセルは内部 completion の `cancelled`（`CLIPBOARD_CANCELLED`）のみで、UI / Bridge へは伝播しない（D-4）
- pre-copy size 検証不能は従来どおり `fileCopyFailed`（`CLIPBOARD_FILE_COPY_FAILED`）。detail の `domain` / `code` を定数化しただけで、公開コード・メッセージは不変

## 4. ビルド結果

| 対象 | コマンド | 結果 |
|---|---|---|
| IosLibrary | `clean build`（generic/platform=iOS Simulator） | **BUILD SUCCEEDED** |
| UnityIosPlugin | 同上 | **BUILD SUCCEEDED** |
| IosLibrary（strict / wholemodule） | `+ SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete SWIFT_COMPILATION_MODE=wholemodule` | 失敗（exit 65、既存機能由来 error 13 件） |
| UnityIosPlugin（strict） | 同上 | 依存先 IosLibrary の同一エラーにより失敗（exit 65） |
| xcframework | `scripts/build_ios_library_xcframework.sh --library-version 1.2.0` | 両モジュール **ARCHIVE SUCCEEDED**（IosLibrary build 11 / UnityIosPlugin build 10） |

新規追加した `isolated deinit` は strict build で新たな診断を発生させていない。

## 5. テスト結果

| 対象 | 実行 | 結果 |
|---|---|---|
| IosLibrary | iPhone 17 Pro / iOS 26.2 Simulator | **186 passed / 0 failed**（v3: 184） |
| UnityIosPlugin | iPhone 17 Pro Max / iOS 26.2 Simulator | **73 passed / 0 failed**（v3 と同数） |

### 5.1 今回追加でカバーした観点

- loader 解放時に内部 completion が `.cancelled` を 1 回だけ受け取ること
- loader 解放後に到着した file 表現がセッションディレクトリに残らないこと
- receiver のみを解放した場合（raw factory 経路）に UI コールバックが 0 回で、かつ一時 file が残らないこと
- source size 検証不能の失敗が「どの境界で弾かれたか」まで一意に特定できること

## 6. Definition of Done（レビュー v3 後の再評価）

判定基準: ○=OK / △=一部OK / ×=未達 / -=対象外

### レビュー v3 項目
- ○ H-01 `PasteItemProviderLoader.isolated deinit` と解放時 cleanup テスト
- ○ M-01 strict error 内訳の訂正（1 / 9 / 3）
- ○ M-02 通常 build warning の実測記録と Clipboard 限定評価の明示
- ○ M-03 size 検証不能テストの失敗原因の固定

### 実装
- ○ Clipboard 追加・変更ソースから strict concurrency error / warning が新規発生しない
- ○ Clipboard 追加・変更ソースから通常 build warning が新規発生しない
- ○ 設計 D-16 の `isolated deinit` を Manager / ItemLoader / **Presentation loader** / Container の 4 型すべてに実装
- ○ Application 層 Port にプラットフォーム型が含まれない
- ○ `NSItemProvider` が Data 層と Presentation 層に閉じている
- ○ 公開エラーメッセージ・ログが URL / path / pasteboard name / invalid reason を含まない
- ○ 非同期処理のタイムアウト・キャンセル・exactly-once が P-11 と P-16 で同一実装を共有
- ○ copy / load / image / file の全 kind にサイズ上限が実装されている
- ○ 一時 file が失敗 / キャンセル / タイムアウト / **loader 解放**のすべてで削除される
- ○ 既存 Notification / Dialog / Share のファイルに変更がない
- × I-10（target 全体の strict green）— 別タスクへ切り出す方針で合意済み

### テスト
- △ 単体テスト（186 + 73 = 259 件 green）。設計 U-01〜U-148 の全件網羅ではない
- × I-08（15 endpoint / 9 content kind の Bridge end-to-end）
- × I-09（`ClipboardRedaction` の独立モジュール境界テスト）
- × 手動確認 M-01〜M-16（実機必須のため未実施）

## 7. 設計差分・未解決事項

### 7.1 strict / 通常ビルド診断の実測（M-01 / M-02 への回答）

**strict（whole-module）error: 13 件。内訳の訂正:**

| module | 件数 | 内訳 |
|---|---|---|
| Dialog | 1 | `IosDialogManager.shared` |
| Notification | 9 | `NotificationActionOptions` 3、`NotificationCategoryOptions` 4、`IosNotificationManager.shared` 1、`NotificationPermissionHelper.shared` 1 |
| Share | 3 | `ShareSheetPresenter` 2、`IosShareManager.shared` 1 |

v3 レポートの「Notification 8 / Share 4」は `NotificationAction.swift` の 3 件と `ShareSheetPresenter` の 2 件を数え違えたもの。合計 13 は一致していたが分類が誤っていた。**Clipboard 由来は 0 件。**

**通常ビルド warning: 2 件（clean build で実測）**

```
IosLibrary/Notification/Data/Repository/NotificationRepositoryImpl.swift:294
  'allowAnnouncement' was deprecated in iOS 15.0
UnityIosPlugin/Notification/UnityIosNotificationManager.swift:169
  switch covers known cases, but 'NotificationAuthorizationStatus' may have additional
  unknown values; this is an error in the Swift 6 language mode
```

v3 レポートの「通常ビルドの warning は 0 件」は、**strict build（先に失敗して打ち切られる）の出力を見ていたための誤り**である。正しくは:

- **Clipboard 追加・変更ソース由来の warning: 0 件**
- target 全体（既存機能を含む）: 上記 2 件（いずれも Clipboard 実装以前から存在）

以後、本レポートでは「warning 0」を無条件では主張せず、必ず Clipboard 限定であることを明記する。

### 7.2 I-10 の設計改訂案（別タスク化・要 design ワークフロー）

レビュー v3 の判断に従い、設計 v5 で I-10 を次のように分離することを提案する。

1. 本タスクの DoD: **Clipboard の追加・変更ソースが Swift 6 strict error / warning を新規発生させないこと**
2. baseline として、target 全体の既存 13 error と既存 2 warning を列挙し、別タスク ID へリンクする
3. 全 module strict-green は別タスク（Dialog / Notification / Share の Swift 6 移行）の DoD として維持する

検証手順は `grep Clipboard == 0` だけに依らず、**whole-module build（`SWIFT_COMPILATION_MODE=wholemodule`）と baseline 差分比較**を必須とする。incremental build は最初にエラーを出したバッチで打ち切られ、未診断のまま通過しうるため（v2 → v3 で実際にこの誤りが起きた）。

再現コマンド:

```
xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme IosLibrary \
  -destination 'generic/platform=iOS Simulator' \
  SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete SWIFT_COMPILATION_MODE=wholemodule build
```

### 7.3 build number

- 本 v4 の成果物再生成後: IosLibrary **10 → 11**、UnityIosPlugin **9 → 10**
- 由来は `scripts/build_ios_library_xcframework.sh` の自動インクリメント仕様（同スクリプト 184〜305 行）

### 7.4 observer 世代 gate の直接再現（v3 から継続・未達）

「旧購読向けに既に main queue へ積まれた block が新購読者へ届かないこと」の直接再現は、main thread をブロックしたままバックグラウンドから UIKit 通知を post する必要があり、シミュレータがデッドロックするため断念している（実測でハングを確認）。制約はテストコードにコメントとして記載済み。

### 7.5 その他の設計差分（v1〜v3 から継続）

- `ClipboardTypeIdentifierValidator` を `internal` → `public`（default 引数の可視性制約）
- `UIColor` の表現型識別子 `"com.apple.uikit.color"` は公式ドキュメント未確認の実装時判断。**要検証**
- `scripts/build_ios_library_xcframework.sh:292` は `--library-version` 省略時に `unbound variable` で失敗する（Clipboard スコープ外のため未修正）
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
