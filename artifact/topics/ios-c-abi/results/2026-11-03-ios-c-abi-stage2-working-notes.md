# 段階 2 の作業の記録（C ABI の実装）

- 記録日: 2026-11-03
- 段階: 2（`README.md` の 5 章。設計書は `designs/2026-11-03-ios-c-abi-c-abi-design-part2.md`。以下「第 2 部」）
- ブランチ: `feature/NTKIT-18`
- 環境: Xcode 26.3（`xcode-select` のまま）。単体テストは Xcode 26.6

## 1. TB-0（第 2 部 7 章）

### 1.1 `IosLibrary` に足したもの

| 決定 | 変更 | Swift の利用者から見ると |
|---|---|---|
| P2-6 | `removeDelivered`、`removeAllDelivered`、`cancelScheduled`、`cancelAllScheduled` に `completion: (@MainActor @Sendable () -> Void)? = nil` | 普通の呼び出しは同じ。関数の参照は組めなくなる（Swift の設計書 3.3） |
| P2-12 | `nonisolated public static func cancelLoad(_ box: RequestBox)`。インスタンスの形はこれを呼ぶ | 足しただけ |
| P2-26 | `NotificationTrigger.isValid`、`NotificationError.invalidTrigger`。Repository の `checkTrigger`（userInfo の後、添付の前） | **落ちていた `timeInterval` だけが失敗になる**。`NotificationError` の `switch` に case が要る |
| 7 章 | `show`、`update`、`schedule` の DocC に、権限が無いと成功を返して残らないこと（M2）。`PresenterSelection` の古い Note を消した | 文書だけ |

- `cancelLoad(_:)` の DocC のリンクは、インスタンスと `static` で曖昧になるので文字にした（`cancelLoad(_:)`）。docbuild の関係する警告は 0 件
- `invalidTrigger` は Domain（`NotificationError`）、`isValid` は Domain（`NotificationTrigger`）に置いた。`Foundation` のほかを import しない

### 1.2 公開 API の差

`results/swiftinterface/IosLibrary-after-tb0.swiftinterface`、差分は `2026-11-03-stage2-tb0.diff`（`after-1b-c6` から）。足した `static cancelLoad`、`invalidTrigger`、`isValid` と、4 つの関数の `completion`（前の宣言が 4 行消える）だけ。

### 1.3 テスト

| 実行 | 結果 |
|---|---|
| `IosLibraryTests`（iPhone 17 / 26.2、iPhone 16 / 18.3、iPad Pro 11-inch (M4) / 18.3。Xcode 26.6、`-parallel-testing-enabled NO`） | どれも 563/563（548 + 15）。警告 0 |
| TSan（`NotificationRepositoryTriggerCheckTests`、`IosNotificationManagerCallFormTests`、`IosClipboardManagerRequestBoxTests`。iPhone 17 Pro / 26.2） | 通った。報告 0 件 |
| サンプルと UI テストの `build-for-testing`（Xcode 26.3） | 組めた。UI テストは変えていないので流していない（全件の基準の取り直しは段階 2 の区切りで）。サンプルは `switch` の 1 行だけ |

### 1.4 壊して確かめたこと（使い捨ての写し）

| # | 壊し方 | 落ちたテスト |
|---|---|---|
| M167 | `isValid` が 0 を通す | `isValidIsFalseOnly…` |
| M168 | 繰り返しの下限を 59 に | 同上 |
| M169〜M171 | `show`、`update`、`schedule` の確かめを外す | プロセスが落ちる（`NSInternalInconsistencyException`） |
| M172 | 完了を Repository の前に呼ぶ | 1 回目は生き残った。Repository を止めるテストを足し、`theRemovalFormsCompleteOnlyAfterTheRepositoryReturned` で落ちる |
| M173、M174 | 完了を呼ばない、2 回呼ぶ | `theRemovalFormsComplete…` |
| M175 | `static` が箱を閉じない | `aBoxCancelledBefore…` ほか |
| M176 | `invalidTrigger` の文言を変える | `everyCaseHasItsOwnFixedDescription`、`theTriggerCaseHasItsText` |
| M177 | `schedule` の確かめを添付の後へ | `theTriggerIsCheckedBeforeTheAttachments` |

**`.private` はテストで守れない**: レビューの提案で UT-15 に位置の trigger の番兵を足すと、`.private` の行でも落ちた。プロセスの中から `OSLogStore` で読むと `.private` の値も見えるので、`.private` と `.public` を区別できない（足した行は外した）。`checkTrigger` の `.private` はレビューと目で確かめた。**見え方は 2.0.0 の前の実機の区切り（MS-13）で確かめる**。UT-15 が守るのは、値をログに出さない行だけ。

### 1.5 レビューと直したこと

レビューは 2 本（Claude: コードと文書、Codex: 並行と隔離）。Codex は A も B も無し。Claude は A 1、B 9、C 8 で、コードの動きの誤りは無かった。

| 指摘 | 対応 |
|---|---|
| A: `checkTrigger` のログが trigger を `.public` で出し、位置の緯度と経度が平文になる | `.private` にした（テストでは守れない。1.4） |
| B: 第 2 部 7 章の行の未対応（第 1 部 8 章と 5.7、1b の記録の B-1、Swift の設計書 10.1） | 直した |
| B: `update`、`schedule` の DocC | 足した |
| B: `checkTrigger` が添付より前であることを守るテストが無い | `theTriggerIsCheckedBeforeTheAttachments` |
| B: インスタンスの `cancelLoad` に先頭のログが無い | 足した |
| B: 関数の参照の破壊が書かれていない | Swift の設計書 3.3 |
| C | 文面、`completion` のログの語、Manager を通した `invalidTrigger` のテスト、`update(trigger: nil)`、文言のテスト |

途中で次の失敗があった: 1 回目に足した順序のテストは 1 つの `AsyncStream` を 4 つのタスクで待ち、iOS 18.3 で完了が来ずに落ちた。`Mutex` の印を待つ形に直した。
