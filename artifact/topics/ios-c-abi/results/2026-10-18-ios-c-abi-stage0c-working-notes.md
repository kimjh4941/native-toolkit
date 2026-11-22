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

## 7. 後半（2026-10-19）: Notification、Share、Clipboard の新しいテスト

シミュレーター（iPhone 17、iOS 26.2、en）だけ。実機には触れていない。実測に使ったテストは `probes/stage0c/Stage0c2ProbeTests.swift`。

### 7.1 足したテストと結果

| クラス | 件数 | 3 回の結果 | 1 回の時間 |
|---|---|---|---|
| `NotificationPermissionUITests`（毎回アプリを削除 → NP2 → 削除 → NP1） | 2 | 3/3 | NP2 約 25 秒、NP1 約 11 秒 |
| `NotificationUITests` | 23 | 3/3（N11 と N19 は直した後にさらに 3/3） | 1053〜1066 秒 |
| `NotificationEventUITests` | 7 | 3/3 | 465〜470 秒 |
| `NotificationColdStartUITests` | 4 | 3/3 | 202〜207 秒 |
| `ShareUITests` | 16 | 2 回目に S9 が 1 回落ちた。直した後に 3/3、さらに S8・S9 だけを 3/3 | 183〜191 秒 |
| `ClipboardPasteUITests` | 3 | 3/3 | 約 75 秒 |
| `ClipboardPasteDenyUITests`（単独で流す） | 1 | 3/3 | 約 23 秒 |

宣言の表は 97 件（新しい 56 件を足した）。列挙の結果と表は、件数・重複・集合ともちょうど一致した。Support を変えたので、`DialogUITests` と `IdentifierInventoryUITests` も流し直し、19/19 が通った。人の確認（computer use）に移したケースは無い（設計どおり HC1・HC4・HC7・HC8 は残る。HC3・HC5・HC6・HC9 はシミュレーターでは要らなかった。実機は確かめていない）。

### 7.2 8.1 の実測（シミュレーター、en）

| 項目 | 結果 |
|---|---|
| 広げた通知の要素 | 長押しで identifier `notification-expanded-view` が出る（category が無くても出るので「広げた」印に使える）。アクションのボタンは全画面の BannerNotification（公開されていない型）の中にあるので、そこに範囲を限る。返信の入力欄と Send はその外にあるので springboard 全体から取る（入力欄は placeholder で取る） |
| 同じ id の更新（N10） | 表示中の通知を UpdateById で更新しても `count: 1, ids: [sample-notification]` のまま |
| 同じファイルを 2 回添付（N5） | どちらも成功 |
| 前面のバナーのタップ（N26） | イベントは 0.3 秒以内に来た |
| 背景で起動したプロセス（N32・N33） | 止めた後に返信や Delete をすると、サンプルは背景で起動したまま（runningBackground）。`activate` の後にイベントが読めた |
| 設定の App（N3） | 約 0.55 秒で前面に来た |
| カレンダーの +1 分（N7） | 約 73 秒で発火した（待ちは 90 秒のまま） |
| ホームのアイコンのバッジ（N34） | `icons["IosLibraryExample"]` の value が、1 で `1 new item`、0 で空 |
| 位置の予約（N8・N18） | どちらも成功の文言（✅ Registered）を返し、予約の一覧に入った |
| category の反映（N23・N24） | 削除の後は 3 回とも 3 秒間アクションが無く、登録の後は約 1.1 秒で出た |
| Share のプレビューの題（S5） | `LP.CaptionBar.TopCaption` で読める。シートが出た時点から `Apple` のまま |
| 複数の Copy と Save to Files（S6・S9・S10） | どれも `completed=true` |
| 貼り付けの許可のダイアログ（CB2） | ランナーが新しい内容を書くたびに毎回出る（前に許可したか拒否したか、再起動したか、別の xcodebuild かに関わらない）。一度許可した同じ内容を読み直したときだけ出ない。**CB2 にアプリの削除（`reinstall`）は要らない** |
| 画像だけの貼り付け（CB4） | `items=1, failures=0`、ダイアログは出ない |

確かめていないもの: 実機の項目、ja のラベル、Universal Clipboard、写真とローカルネットワークの権限のダイアログ。

### 7.3 変異（1 つずつ入れて確かめた。すべて戻した）

| 壊したもの | 落ちたテスト |
|---|---|
| `foregroundPresentationOptions` を空にする | N4、N26 |
| `cancel` を何もしない形にする | N11（最初は生き残ったのでテストを強めた。7.4 の 4） |
| `removeDelivered` を何もしない形にする | N14 |
| `didReceive` で、アクションの id の代わりに通知の id を渡す | N25、N27、N28 |
| `registerCategory` で `setNotificationCategories` を呼ばない | N23 |
| `ShareSheetPresenter` で completed をいつも true にする | S2、S3 |
| サンプルの除外のリストを空にする | S12 |
| `onPaste` で貼り付けの結果を変えない | CB3 |
| 読み込みの失敗を成功（✅）として表示する | CB2 |

### 7.4 設計とずれたこと（設計書の 8.6 に書いた）

1. 最後のイベントの `userText` は、テキストの無いアクションでサンプルが `-` と表示する（設計の 3.3 は `nil`）。今の動作を期待値にした
2. N6: ShowTimeInterval(5s) の後、ボタンが離れていてスクロールに約 12 秒かかり、5 秒以内に GetScheduled まで行けない。発火の前の `count: 1` の確かめは N7 に任せ、N6 は背景での発火と発火の後の一覧を確かめる
3. N13・N20: 5 秒・10 秒の予約では CancelAll の前に 5 秒のほうが発火したので、+1 分のカレンダー（ShowCalendar と ScheduleCalendar）に替え、取り消す前に 2 件あることを読む
4. N11・N19: 一覧の読み直しの上限を予約の時刻より前にし、窓が終わった後に GetDelivered が空であることも確かめる（バナーを見逃しても、発火していれば落ちる）
5. CB2: `reinstall` を宣言しない（7.2）
6. Share: プレビューがあるとナビゲーションバーの名前が題になるので、開いた印に `ActivityListView` を足した。Copy はセルだけを探す。Save to Files の Save は、ピッカーが落ち着いてから押す（動いている間に押すと保存も完了の知らせも無いままシートに戻った。S9 の 1 回の失敗の原因）
7. 前面にバナーが出ている間のスクロールは、XCTest の既定のハンドラが毎回最大約 7 秒待つ。通知のテストが 1 件 40〜90 秒かかるのはこのため
8. `SampleApp.remainingAlertCount` は、印を取らずに springboard のアラートの**数だけ**を読む（何も押さず、ラベルも読まない）。Share と CB3 は `systemui` を宣言していないため。信頼する部分の中の、読むだけの例外として認めた（設計書の 6.1）
9. 0d のランナーへ: xcodebuild の実行の後、シミュレーターは Shutdown になっているので、`simctl uninstall` の前に起動が要る（`simctl bootstatus -b`）

### 7.5 後始末

xcodebuild・simctl・待ちのループで残っているものは無い（こちらでも確かめた）。シミュレーターは Shutdown。シミュレーターには、通知の権限（許可）、登録済みの category、クリップボードのテストの文字列、Files の「このiPhone内」の share-sample の写しが残っている。

### 7.6 残り（0c の終わりまで）

- 実機での確かめ: 0d のランナー（柱 1）ができてから、流すテストの一覧を利用者に見せて許可を得て行う（設計の U-9。ランナー無しに実機で流さない）
- 信頼する部分（基底と Support）のハッシュの固定と、今の `ClipboardUITests` のファイルのハッシュの固定
- 0c の結果の文書
