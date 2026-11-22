# 段階 0b の結果: サンプルの識別子、結果の行の番号、通知の最後のイベント

- 記録日: 2026-11-23
- 段階: 0b（企画 5 章。UI テストの設計書 `designs/2026-11-23-macos-c-abi-ui-test-design.md` の 4 章、U-3、U-4、U-5、U-17、U-21）
- 状態: **完了**
- 変えたもの: サンプルだけ（`mac/MacLibraryExample/MacLibraryExample/`）。`mac/MacLibrary`、`mac/UnityMacPlugin`、テストのターゲット（`MacLibraryExampleTests`、`MacLibraryExampleUITests`）は変えていない
- 元にした版: `32a53c25`（feature/NTKIT-19）
- 確かめた環境: この Mac では組むだけ（Xcode 26.3 と 26.6）。動かす確かめは VM `ntk-macos-15-new`（macOS 15.8.3、Xcode 26.3、en-US、`--no-graphics --no-clipboard`）だけ。この Mac では UI・通知・クリップボードを使うものを何も動かしていない

## 1. 変えたこと

| ファイル | 中身 |
|---|---|
| `ContentView.swift` | `MenuIdentifiers` を足し、4 つのカード（`NavigationLink`）に `menu.dialog` / `menu.notification` / `menu.share` / `menu.clipboard` を付けた |
| `DialogSampleView.swift` | `DialogSampleIdentifiers`（`ButtonName` は `CaseIterable`）を足した。結果の行に `dialog.result` と `accessibilityValue` の `#<n> <本文>`、その下に `dialog.resultHistory`（直近 3 件を新しい順に `#<n> <本文>` を ` / ` でつないだ値。結果が無い間は `-`）、ボタン 6 つに識別子。番号と履歴は、本文と同じ同期の `@State` の更新の中で変える（積み方は変えない。4.2） |
| `NotificationSampleView.swift` | `NotificationSampleIdentifiers`（`Section`・`ButtonName` は `CaseIterable`）を足した。結果の行に `notification.result` と `#<n> <本文>`（番号は本文と同じ `DispatchQueue.main.async` の中で増やす）、その下に `notification.lastEvent` と `notification.launchCopy` の 2 行（スクロールの外）、節 7 に `.accessibilityElement(children: .contain)` と識別子、ボタン 22 に識別子。返信の placeholder を `Type message` から `MacLibraryExample reply` に変えた。`onAppear` で受け手を設定し直すのをやめ、`NotificationEventViewModel` を読み直すだけにした。新しいイベントが来たら（`snapshot.sequence` が変わったら）、結果の行に今までと同じ文（`[actionReceived] ...` / `[textActionReceived] ...`）を出す |
| `ShareSampleView.swift` | `ShareSampleIdentifiers` を足した。結果の行に `share.result` と `#<n> <本文>`、節 5 に `.contain` と識別子、ボタン 15 に識別子 |
| `MacLibraryExampleApp.swift` | 2 つの受け手を設定してから `MacNotificationManager.shared.setup()` を呼ぶ順に入れ替えた（U-4）。受け手は今の `Log.d` を残したまま、入れ物に書く |
| `NotificationEventLog.swift`（新規） | 入れ物 `NotificationEventLog.shared`（`NSLock` で守り、`record` は呼ばれたスレッドで同期に書く。main には値を持たない合図だけを送る。永続化しない）、`NotificationEventSnapshot`（`displayValue` が 4.3 の形）、`@MainActor final class NotificationEventViewModel: ObservableObject`（`@Published private(set) var snapshot`）、`SampleLaunchCopy`（`Bundle.main.bundlePath` の SHA-256 の先頭 12 文字。`copy=<12 桁>`）。プロジェクトは同期のグループなので、pbxproj は変えていない |

見た目の変化は、Dialog の履歴の行（1 行）、通知の画面の 2 行、返信の欄の薄い文字だけ。通知の画面は 2 行の分（約 41 pt）スクロールの見える範囲が狭くなった（3 章の 3）。

細かい決めごと（設計書に書かれていない所）:

- 最後のイベントの `userInfo` は、文字列の値が 1 つも無いときも `-` にした（読めないときは `?`）。返信の文字が空の文字列なら `userText=` の後ろは空になる
- 結果の行へのイベントの文は「`sequence` が変わったとき 1 回」出す。main の 1 回の処理の中に 2 つのイベントが重なると、結果の行は新しい方の 1 回だけになる（最後のイベントの番号は 2 つ進む）。前は受け手ごとに 1 回出ていた
- 入れ物の `record` のログは、返信の文字を長さだけにした（受け手の `Log.d` は今のまま文字を出す。iOS の 0b と同じ扱い。ログの規則は 1b）

## 2. 識別子の数（設計書 4.1 と照らした）

| 画面 | 設計書 | 実装（コードの数） | VM の木で引けた数 | 内訳 |
|---|---|---|---|---|
| メニュー | 4 | 4 | 4（どれも 1 回だけ。型は Button） | カード 4 |
| Dialog | 8 | 8 | 8 | 結果、履歴、ボタン 6 |
| Notification | 32 | 32 | 32 | 結果、最後のイベント、コピーの印、節 7、ボタン 22 |
| Share | 21 | 21 | 21 | 結果、節 5、ボタン 15 |
| 計（新規） | 65 | 65 | 65 | |
| Clipboard（変えていない） | 54 | 54 | **53** | `clipboard.pasteButton`（`NSViewRepresentable` の入れ物）だけが 15.8.3 の木に現れなかった。ほかの 53（固定の表示 7、節 10、ボタン 36）は 1 回ずつ |

VM の確かめは、一時の UI テストがアプリの木を 1 回の snapshot で辿り、`<画面>.` で始まる識別子の集合が設計書の一覧（テストの中に一覧から写して書いた。サンプルの enum は使っていない）と完全に一致し、どれも 1 回だけ現れることを見た。初めの値は `dialog.result` が `#0 Result will be displayed here`、`dialog.resultHistory` が `-`、`notification.lastEvent` が `#0 kind=none notificationId=- actionId=- userText=- userInfo=-`、`notification.launchCopy` が `copy=` と 16 進 12 桁、`share.result` が `#0 Result will be displayed here` だった。

## 3. 組み立て（この Mac。動かしていない）

DerivedData は scratchpad、署名は ad-hoc（`CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`。チームの ID を出さないため）。対象はワークスペースの `MacLibraryExample` のスキーム（`MacLibrary`、サンプル、`MacLibraryExampleTests`、`MacLibraryExampleUITests`）。

| Xcode | 版 | `build-for-testing` | エラー | コンパイラーの警告 | そのほかの警告 |
|---|---|---|---|---|---|
| 26.3（`xcode-select` の既定） | 17C529 | 成功 | 0 | 0 | `appintentsmetadataprocessor` の「Metadata extraction skipped」4 |
| 26.6（`DEVELOPER_DIR`） | 17F113 | 成功 | 0 | 0 | 同じ 4 |
| 参考: 0b の前（`32a53c25` の写し、26.3） | 17C529 | 成功 | 0 | 0 | 同じ 4 |

VM の中（26.3、ad-hoc）でも組み立てはコンパイラーの警告 0 だった。

## 4. VM での確かめ

ソースは、未コミットの変更を含めるため `mac/`（`mac/Build`・`mac/Docs`・`xcuserdata` を除く）を `tar` で ssh に流して `~/ntk/s0b/` に写した（`git archive` と `scp -r` は使っていない）。VM の通知の設定は 0a のまま（`dndMirrored` が false、サンプルは通知を許可済み）。

### 4.1 既存の UI テスト（38 件）

| 回 | 版 | 通った | 落ちた |
|---|---|---|---|
| 1 | 0b | 33 | 0a の 4 件（Share の Copy の 3 件、C9）と **ShareViaMail** |
| 2 | 0b | 33 | 0a の 4 件と **CanPerformMail** |
| 3 | 0b（一時のテストを外して組み直した） | 34 | 0a の 4 件だけ（0a と同じ） |
| 参考 | 0b の前（HEAD の写し） | 34 | 0a の 4 件（0a と同じ） |

0b の全件の 1・2 回目では、メールを使う 2 件（`testCanPerformMailReturnsResult`、`testShareViaMailCompletesWithMailService`）のどちらか 1 件が回ごとに替わって落ちた。どちらも結果の行に期待の文が出ないまま待ち（5 秒・8 秒）が切れた。次のことから、0b の変更によるものではなく、メールのアプリの起動の時間の揺らぎと見ている（推測。原因は確かめていない）:

- ShareViaMail だけを 2 回流すと 2 回とも通った
- Share のクラス（17 件）だけを HEAD と 0b で交互に 2 回ずつ流すと、4 回とも 0a の 3 件だけが落ち、メールの 2 件は通った
- 0b で Share の画面に足したのは識別子と結果の行の `#<n> ` の前置きだけで、今のテストは `value CONTAINS` で照らすので前置きの影響を受けない。ほかの結果の行のテスト（ShareEmpty など）は通っている
- どの回も、始める前にメールのアプリを止めていた（初めの 1 件がメールを起こす）

3 回目は 0a と同じ 34 件が通った。0c で Share の 17 件は S1〜S17 に置き換え、メールの 2 件は VM だけの `realservice` になる（U-13）。置き換えの後も揺れるなら、0c の最初の 3 回の確かめで待ちの長さを決める。

### 4.2 結果の行の番号と Dialog の履歴（U-3、4.2）

- Dialog: ShowDialog を 4 回出し、`action-button-1`（OK）・`-2`（Cancel）・`-3`（Delete）・`-1` で閉じると、結果の行が `#1`〜`#4` と 1 つずつ増え、本文は `ShowDialog - result: DialogResult(buttonIndex: 0, buttonTitle: "OK", suppressionButtonState: false, helpButtonPressed: false, isSuccess: true)` など。2 秒待っても `#4` のまま。履歴は `#4 <本文> / #3 <本文> / #2 <本文>` と結果の行の値に一致した
- Notification: HasPermission で `#1 ✅ \nResult: [hasPermission] true`、GetScheduled で `#2 ✅ \nResult: [getScheduled] count=0, ids=[]`。2 秒待っても増えない
- Share: ShareEmpty で `#1 ❌ \nResult: [shareEmpty] errorCode=1401, errorMessage=No shareable items were provided.`。2 秒待っても増えない

### 4.3 通知の最後のイベント（U-4、4.3）

| 経路 | 最後のイベント | 結果の行 |
|---|---|---|
| サンプルが前面のまま、バナーの本文をクリック（N22 の形） | `#1 kind=action notificationId=mac-sample-notification-<数字> actionId=com.apple.UNNotificationDefaultActionIdentifier userText=- userInfo=id:mac-sample-notification-<数字>,source:MacLibraryExample`。2 秒待っても `#1` | `[actionReceived] notificationId=..., actionId=com.apple.UNNotificationDefaultActionIdentifier, userInfoJson={...}`（前と同じ文） |
| Finder を前に出し、`Open`（N23 の形） | `#2 kind=action ... actionId=open userText=- userInfo=...`。サンプルが前面に来た | - |
| Finder を前に出し、`Reply` → 返信の欄に `hello reply` → Return（N24 の形） | `#3 kind=textInput ... actionId=reply userText=hello reply userInfo=...` | `[textActionReceived] ..., actionId=reply, text=hello reply, userInfoJson={...}`（前と同じ文） |
| コールドスタート: ShowTimeInterval(10s) → `terminate` → バナーの本文をクリック → 起こされたプロセスで `menu.notification`（NC1 の形） | `#1 kind=action notificationId=mac-sample-notification actionId=com.apple.UNNotificationDefaultActionIdentifier userText=- userInfo=id:mac-sample-notification,source:MacLibraryExample`。結果の行は `#0 Result will be displayed here` のまま。`notification.launchCopy` は止める前と同じ値。2 秒待っても `#1` | - |

userInfo の JSON のキーの順は回によって `{"id":...,"source":...}` と `{"source":...,"id":...}` の両方が出たが、最後のイベントの表示はどちらもキーの順に並んだ。コールドスタートでは、予約を押してから `notRunning` まで 1.1 秒、根が見えるまで 10.2 秒だった（1 回）。コールドスタートの前に、VM の LaunchServices から今回のビルド以外のサンプルのコピー（`~/ntk/dd263` と比べのための HEAD の写し）の登録を外した（U-21 の VM の道と同じ扱い）。

### 4.4 一時のテストと 3 回目の全件

確かめの UI テスト（`Stage0bCheckTests`）は VM の写しにだけ置き、リポジトリには入れていない。テストごとに通知の daemon を立て直して 1 件ずつ流した（前のテストの失敗の後の状態を持ち越さないため）。流した後に VM の写しから消し、3 回目の全件はそれを除いて組み直して流した（4.1）。

## 5. 設計書と合わなかった所（0c への申し送り）

設計書は決定済みなので直していない。0c の最初の確かめ（9.1）で扱う。

| 所 | 設計書 | 実際（VM 15.8.3、今回） | 扱いの案 |
|---|---|---|---|
| 通知のアクションの出し方（U-5、9.0 の 4） | 根を hover すると根の中に `Options`（menuButton）が出て、押すと根の外のメニューに `Open`・`Reply` | 今回は HEAD のサンプルでも 0b のサンプルでも、hover で出るのは `Show Details`（identifier `chevron.forward`）だけで、通知センターの木に `Options` は 0 個だった。`Show Details` を押すと、根の中に `Open` と `Reply` のボタン（label で 1 つずつ）と `More Actions…` が出て、押すとイベントが届いた（4.3） | 0c の補助は 2 つの出し方の両方を、根の中でちょうど 1 つの形で扱うか、どちらが出るかの条件（通知の数、表示の状態など）を先に調べる。`Show Details` の形なら押す相手はすべて根の中になる |
| 返信の欄の placeholder（U-5） | `TextView` を placeholder `MacLibraryExample reply` で絞る | 根の中の `TextView` はちょうど 1 つで焦点を持っていたが、`placeholderValue` は空の文字列で読めなかった。placeholder は変えたが、木からは確かめられていない（見た目も見ていない） | 絞りは「根の中でちょうど 1 つ、焦点あり」で行い、placeholder は読めたときだけ照らす。placeholder を変えた狙い（ほかのアプリの欄と取り違えない）は、根の中に限ることで満たす |
| スクロールの外のボタン（5.0 の押す前の確かめ） | （書かれていない） | 通知の画面で下のボタン（RemoveAllDelivered）を押すとスクロールが動き、上のボタン（ShowTimeInterval）はスクロールの見える範囲の上の外（枠の y=181、範囲の上端 329）に出るのに `isHittable` が true と読め、`click()` は範囲の外に落ちて何も起きなかった（XCUITest はスクロールし直さない）。0b で通知の画面に 2 行足し、見える範囲が約 41 pt 狭くなったので起きやすくなった | `SampleApp` の押す口は、押す前にボタンの枠がスクロールの見える範囲の中にあることを確かめ、外ならスクロールして戻してから押す（一時のテストではこの形で通った）。5.0 の「押す点を覆う最前面の窓の持ち主」だけでは捕まえられない（点はサンプルの窓の中） |
| Clipboard の識別子の数（4.1、I1d） | 54 | 53（`clipboard.pasteButton` が木に無い） | 9.1 の「`clipboard.pasteButton` の中の `PasteButton` を取れるか」で扱う。0b では Clipboard を変えていない |

## 6. 残したこと

- この Mac（macOS 26）では何も動かしていない（決まりのとおり）。26 での識別子・最後のイベント・スクロールの振る舞いは、区切りで許可を得て U-30 の形で確かめる
- 返信の欄の新しい placeholder が画面に出ることは、木から読めず見てもいない（5 章）
- メールの 2 件の揺らぎの原因（4.1。3 回のうち 2 回で 1 件ずつ）
- 5 章の 4 点を設計書に反映するかは親が決める
- VM の後片付け: 写したソース・DerivedData・ログ・結果のバンドルを消した（6.1）

### 6.1 VM に残したもの・変えたもの

- `~/ntk/s0b/`（0b と HEAD の写し、DerivedData、ログ、`.xcresult`）は消した。消す前に、そこのサンプルのコピーの LaunchServices の登録を外した
- 前の段の `~/ntk/dd263` のサンプルのコピーは、コールドスタートの確かめの前に LaunchServices の登録を外したが、片付けの時点では登録し直されていた（ファイルは触れていない）。VM のサンプルの登録は、これ 1 つに戻った
- 通知の UI の daemon（`usernoted`、`NotificationCenter`）を何度か立て直した。通知の設定（`com.apple.ncprefs`）は変えていない
