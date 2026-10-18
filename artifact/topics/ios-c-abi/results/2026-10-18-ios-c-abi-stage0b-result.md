# 段階 0b の結果: サンプルの識別子と、通知の最後のイベントの表示

- 記録日: 2026-10-18
- 段階: 0b（`README.md` 5 章。UI テストの設計書の 5 章、U-3、U-4、U-17）
- 状態: **完了**
- 変えたもの: サンプルだけ（`ios/IosLibraryExample/IosLibraryExample/`）。`ios/IosLibrary`、`ios/UnityIosPlugin`、UI テストのターゲット（`IosLibraryExampleUITests`）は変えていない
- 確かめた環境: シミュレーター（iPhone 17、iOS 26.2）だけ。実機には触れていない

## 1. 変えたこと

| ファイル | 中身 |
|---|---|
| `ContentView.swift` | `MenuIdentifiers` を足し、`menu.dialog` / `menu.notification` / `menu.share` を付けた。既存の `menu.clipboard` は値を変えずに enum を通す形にした |
| `DialogSampleView.swift` | 結果の行に `dialog.result`、ボタン 6 つに `Button` そのものに識別子を付けた。結果の行の `accessibilityValue` は `completion=<n>,callback=<n>`（画面全体の累計。`resultText` と同じ `main.async` の中で増やす） |
| `NotificationSampleView.swift` | 結果の行（`updates=<n>`）、節 7、ボタン 25、最後のイベント 5 に識別子を付けた。結果の行の下に最後のイベントの表示（`sequence`、`kind`、`notificationId`、`actionId`、`userText`）を足した。画面は `@StateObject` の `NotificationEventViewModel` を持ち、`onAppear` で読み直す |
| `ShareSampleView.swift` | 結果の行（`updates=<n>`）、節 6、ボタン 14 に識別子を付けた |
| `ClipboardSampleView.swift` | `clipboard.pasteControl` を足し、`makeUIView` で `UIPasteControl` そのものに付けた（下の 3 章） |
| `IosLibraryExampleApp.swift` | 2 つの受け手を設定してから `IosNotificationManager.setup()` を呼ぶ順に入れ替えた（U-4）。受け手は今の `Log.d` を残したまま、入れ物に書く |
| `NotificationEventLog.swift`（新規） | 最後のイベントの入れ物。`NSLock` で守り、受け手の中で同期に書く（`completionHandler` より前に書き終わる）。main には値を持たない合図だけを送り、画面は入れ物から読む。永続化はしない。`@MainActor final class NotificationEventViewModel: ObservableObject` と `@Published private(set) var snapshot` |

見た目の変化は、通知の画面の最後のイベントの表示だけ。

## 2. 確かめたこと（シミュレーター）

| 確かめ | 結果 |
|---|---|
| `build-for-testing` | 成功。エラー 0、サンプルの警告 0 |
| `IosLibraryExampleTests`（単体テスト） | 10 件中 10 件が成功 |
| 識別子の数（一時のテストで、アプリの全要素から前方一致で数えた） | メニュー 4（新規 3）、Dialog 7、Notification 38、Share 21、`clipboard.pasteControl` 1。UI テストの設計書の 5.1 と一致。どれもちょうど 1 回だけ現れた。Clipboard の `clipboard.` の要素は 68 |
| Dialog の回数 | ShowAlert を 2 回押すと、`0,0 → 1,0 → 1,1 → 2,1 → 2,2` と増えた |
| 通知の最後のイベント | 5 秒の予約 → ホーム → バナーのタップで、`sequence=1`、`kind=action`、`notificationId=sample-notification`、`actionId=com.apple.UNNotificationDefaultActionIdentifier`、`userText=-` |
| コールドスタート | アプリを止めてからバナーをタップし、通知の画面を開くと `sequence=1` が出た（`onAppear` の読み直しが効く） |
| 既存の `ClipboardUITests` の U1〜U3（`-only-testing`） | 3 件中 3 件が成功（U2・U3 はそれぞれ約 94 秒） |

一時のテスト（`Stage0bTempTests`）は流した後に消し、UI テストのターゲットに差分が無いことを確かめた。シミュレーターは最後に Shutdown。

## 3. UI テストの設計書と合わなかった所

設計書を、ここに合わせて直した（同じ日）。

| 所 | 実際 | 扱い |
|---|---|---|
| `clipboard.pasteControl` の付け方 | `UIViewRepresentable` に `.accessibilityIdentifier` を付けると、識別子は外側のコンテナ（label の無い Other）に付き、「Paste」のボタンに届かなかった | 設計書の代わりの案のとおり、`makeUIView` で `UIPasteControl` に直接付けた。付けた後は Button（label「Paste」）が 1 つだけ当たる。設計書の 5.1 と 8.1 を直した |
| Dialog の「種類ごとの回数」 | 画面全体の累計 2 つ（completion と callback）と解釈した。Dialog ごとの回数ではない | D14 は各 Dialog の操作の前からの増分で判定するので、この形で足りる。設計書の U-3 に書いた |
| 8.1「Dialog が出ている間に、後ろの結果の行を読めるか」 | iOS 26.2 のシミュレーターでは読めた（アラートが出ている間に `completion=1,callback=0` を読んだ） | 8.1 の行を、シミュレーターでは確かめた、に直した。実機は 0c の最初に確かめる |
| 権限のダイアログの経路 | シミュレーターは 0a で通知を許可した状態のままなので、今回は通っていない | 0c で扱う |
| 設計書のサンプルの行番号 | 今回の変更でずれた | 0c で UI テストを書くときに読み直す |

## 4. 気になったこと（直していない）

- 最後のイベントの入れ物は、返信の文字（`userText`）を `Log.d` に出す。もとの受け手も同じ値をログに出しており、ログの規則（秘密の値を伏せる）は段階 1b で直す（`README.md` 1.4、8.6）
