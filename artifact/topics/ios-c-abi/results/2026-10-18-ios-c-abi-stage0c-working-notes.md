# 段階 0c の作業の記録

- 記録日: 2026-10-18
- 段階: 0c（UI テストの実装。`README.md` 5 章、UI テストの設計書）
- 状態: 前半が終わった（テストの土台、Dialog、識別子の照合）。後半（Notification、Share、Clipboard の新しいテスト、実機での確かめ）はこれから。段階の結果は 0c の終わりに別に書く
- 環境: シミュレーター（iPhone 17、iOS 26.2、en）だけ。実機には触れていない（`NTK_DEVICE_ALLOW` も渡していない）
- 試したコード: `probes/stage0c/Stage0cProbeTests.swift`（8.1 の項目を確かめたテスト。テストのターゲットには入れていない）

## 1. 前半で作ったもの（`ios/IosLibraryExample/IosLibraryExampleUITests/`）

| ファイル | 中身 |
|---|---|
| `Support/SampleUITestCase.swift`（基底） | 入口の `final override`、印の型 6 つ（初期化子は `fileprivate`）と印を出す 6 つの関数、`self.name` の正規化（`-[C m]` → `C/m`。ほかの形は throw）、宣言の表の読み込み（キーの重複も検出）、`NTK_DEVICE_ALLOW` の読み取り（知らない区分名は throw）、押したボタンの記録の添付（3.7） |
| `Support/SampleApp.swift` | `XCUIApplication` を private に持つ。ボタンの enum、識別子の一覧（設計書の 5.1 の写し）、結果の行の回数、アラートと action sheet の包み、1 回の snapshot で識別子を集める処理 |
| `Support/UnexpectedAlertGuard.swift`、`Springboard.swift`、`ShareSheet.swift`、`RunnerPasteboard.swift`、`NotificationCleanup.swift`（`inApp` と `springboard` に分けた）、`SystemLabels.swift` | 監視（U-8）と、印を要る操作の口 |
| `Support/DeviceRequirements.json` | 宣言の表。41 件（Clipboard 22、Dialog 15、I1 4） |
| `DialogUITests.swift`（D1〜D15）、`IdentifierInventoryUITests.swift`（I1a〜I1d） | 新しいテスト |
| `IosLibraryExampleUITests.swift` | 雛形のクラスを消し、`final class ClipboardUITests: SampleUITestCase` にした。setUp と tearDown を `setUpAfterGate` / `tearDownAfterGate` に改名した。テストの本体は変えていない |
| `IosLibraryExampleUITestsLaunchTests.swift` | 消した（雛形） |

`ios/IosLibrary` とサンプルは変えていない。

## 2. 設計のとおりに動かなかったこと

| 設計 | 実際 | 扱い |
|---|---|---|
| 基底で `setUp() async throws` と `tearDown() async throws` も `final override` にする | 基底で async の形を上書きすると、`continueAfterFailure = false` の下で XCTest の中の失敗（タップの失敗や `XCTFail`）が起きるたびに、テストのランナーがアサーション（`_caughtUnhandledDeveloperExceptionPermittingControlFlowInterruptions`）で落ちて起動し直した。`@MainActor` を付けても同じ | 基底は completion の形（`setUp(completion:)` / `tearDown(completion:)`）を `final` にし、async の形は上書きしない。子が async の形を上書きするとビルドが通り、ゲートより前に走る（`gatePassed=false` を確かめた）ので、6.1 の閉じた形の規則（`override` は 2 つの口だけ）で止める。設計書の 6.1 を直した |
| 監視が「押さずに terminate して true を返し、包む関数で throw する」 | 経路によって違った。(a) 既知のアラートの経路は、監視が否定のボタンを押し、XCTest が元の操作をやり直し、包む関数が throw してきれいに止まる。(b) 押さずに止める経路では、監視が terminate すると、XCTest が要素を探し直すときにサンプルを自分で起動し直し、「no longer valid after interruption handling」という XCTest 自身の失敗で止まる。包む関数の throw までは届かない | どちらの経路もテストは止まる（安全の側）。(b) の失敗の文に監視の詳しい内容は残らない。0c の終わりの結果に書く |
| 6.1 の `ClipboardID` の範囲（52〜58 行） | 雛形を消した後は 16〜24 行 | 設計書の 6.1 を直した |

## 3. 8.1 の項目の実測（シミュレーター、en）

| 項目 | 結果 |
|---|---|
| I1 の集め方（画面の外のボタンが 1 回の snapshot に入るか） | 入る。スクロールせずに全ボタンが取れた（Dialog 6/6、Notification 25/25（うち画面の外か一部だけ見える 19）、Share 14/14（同 7）、Clipboard 54/54）。位置ごとの和集合は要らない。ナビゲーションバーのボタンは `BackButton`（label `Main Menu`）の 1 つだけで、明示して除く。実機は確かめていない |
| Dialog が出ている間に後ろの結果の行を読めるか | 読める（D1・D2・D6 で `completion=1,callback=0` と全文が一致。ラベルは改行を含む） |
| 26.2 の action sheet | sheets=1、popovers=1、`Cancel` は 0 件。`PopoverDismissRegion` で閉じる |
| 通知のバナーが監視に来るか | 来る。バナーの下のアプリの要素を押すと、`NotificationShortLookView`（種類は BannerNotification）で監視が呼ばれる。`systemui` を宣言したテストでは `false` を返すと、XCTest の既定のハンドラはアラートでない要素を押さず、バナーが自然に消えるのを最大 15 秒待って元の操作を続けた。バナーが出ている間にアプリを操作するテストは最大 15 秒遅くなる |
| springboard を明示して待って押す操作が監視を起こさないか | 起こさない（「何も押さない」監視のまま、権限のダイアログを待って Allow を押し、成功した） |
| 権限と貼り付けのダイアログのラベルにサンプルの名前が入るか（en） | 入る。権限: `“IosLibraryExample” Would Like to Send You Notifications`（`Don’t Allow` / `Allow`）。貼り付け: springboard に `“IosLibraryExample” would like to paste from “IosLibraryExampleUITests-Runner”`（`Don’t Allow Paste` / `Allow Paste`）。監視の照合は `“IosLibraryExample”`（引用符まで含める）に錨を打った（ランナーの名前も部分に含むため）。ja は確かめていない（合わなければ押さずに止める） |

## 4. テストの結果（シミュレーター）

| 対象 | 結果 |
|---|---|
| `build-for-testing` | 成功。UI テストのターゲットの警告は 0 |
| 列挙 | 41 件（ほかに基底クラスの 1 件）が宣言の表のキーとちょうど一致 |
| `DialogUITests` | 15/15 が成功、3 回とも同じ（1 回あたり約 200 秒） |
| `IdentifierInventoryUITests` | 4/4 が成功、3 回とも同じ（1 回あたり約 28 秒） |
| `ClipboardUITests` の U1〜U3 | 3/3 が成功（載せ替えで壊れていない） |
| 押したボタンの記録の添付 | `SampleApp` を使うテストにちょうど 1 つずつ付いた（Dialog 15、I1 4）。Clipboard の既存のテストには付かない（設計どおり） |

## 5. 変異（シミュレーター。すべて戻した）

| 変異 | 結果 |
|---|---|
| 表から D1 の行を消す | D1 が setUp で落ちた |
| 表のキーを重複させる | setUp で落ちた |
| D12 の宣言を `[]` にする | `credentialsToken()` が throw して落ちた（二段目） |
| Confirm の確認のボタンが `onCancel` を呼ぶ | D2 が落ちた。D3 は通った（予想どおり） |
| `onLogin` を 2 回呼ぶ | D15 が落ちた |
| showAlert で `onButton` を 2 回呼び、completion を呼ばない | D1 と D14 が落ちた |
| 識別子の無いボタン、間接の補助で一覧に無い識別子を付けたボタン、識別子の重複 | どれも I1a が落ちた |
| 子が `setUpWithError` や `setUp(completion:)` を上書きする | ビルドが通らない |
| 子が `setUp() async throws` や `tearDown() async throws` を上書きする | ビルドが通る（2 章。閉じた形の規則で止める） |

## 6. 後半に持ち越すこと

- まだ動かしていない補助: `ShareSheet`（全体。`saveToFiles` の「両方とも残す」の 3 秒の待ちは U-14 の例外の表に無いので見直す）、`NotificationCleanup.inApp`、`Springboard` の長押し・アクション・返信、`RunnerPasteboard`（書き込みだけ確かめた）。springboard の片付けは、広げた通知の要素を確かめるまでホームを押すだけにしている。これらを使うテストを書いて確かめた後に、信頼する部分のハッシュを固定する
- 「何も押さない」監視の対象はクラス名とメソッド名の頭で決めている（`NotificationPermissionUITests`、`ClipboardPasteDenyUITests`、`ClipboardPasteUITests/testCB1_`）。CB1 のメソッド名は `testCB1_` で始める
- 今の `ClipboardUITests` に `continueAfterFailure = false` が残っている（基底と重複。差分を小さくするため残した）
- シミュレーターの後始末: 確かめのためにアプリを 2 回削除した。通知の権限は最後に許可に戻した。クリップボードにテストの文字列が残っている
