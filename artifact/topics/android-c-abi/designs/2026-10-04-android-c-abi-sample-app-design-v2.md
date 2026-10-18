# Android サンプル（段階 1b）設計書

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/android-c-abi/README.md`（段階 1b） |
| 元にした設計書 | `designs/2026-10-04-android-c-abi-kotlin-api-design.md`（第 7 版と 0.7。以下「Kotlin の API の設計書」）の T-20 |
| 実装結果 | まだ無い。1b の実装結果は T-23 で書く（利用者の決定。2026-10-04）。この設計書は Kotlin の API の設計書と、コミット済みの実装（`7f3d8946`、`4ba60200` まで）の公開の口を元にする |
| 対象 OS | Android 12（API 31）以降 |
| 対象サンプル | `android/AndroidLibraryExample` |
| 主に参照するサンプル | iOS（`ios/IosLibraryExample`。Android ⇔ iOS の対） |
| 作成日 | 2026-10-04（第 2 版。1 回目のレビュー（`reviews/2026-10-04-android-c-abi-sample-app-design-review-v1.md`）を反映） |
| ブランチ | `feature/NTKIT-17` |

## 0. レビューの反映（第 2 版）

| ID | 区分 | 反映した所 |
|---|---|---|
| S-X1、S-C1 | A | メディアの 3 つのアクションは `launchApp = true`（4.3）。n28 に表示の確かめを足す（5 章） |
| S-X2、S-C2 | A | Dialog の 6 つの要求は題・本文・ボタン・項目・既定の選択・options を今の値のまま（4.5）。結果の文言と、直す期待値をケースの ID で挙げた（4.5、5 章）。`NavigationUiTest.kt` を変更に足した（8 章） |
| S-C3、S-X4 | A | 手動の項目を UI テストへ移し、6 章は「なし」。保ちはプロセスの寿命まで（4.2、5 章） |
| S-C4、S-X3 | B | 画面への受け渡しを再生しない `SharedFlow` に。画面が出ているかは購読の数で。Toast の時機の違い、試験の間の保ちの捨て方、作り直しの確かめ（4.2、5 章） |
| S-C5 | B | Manager に無い口（CallStyle、rationale）を記録し、申し送る（2.2、10 章） |
| S-X5 | B | 不正な Chooser Action のボタン（4.4） |
| S-X6 | B | 選んだアプリが分からないときの文言（4.4） |
| S-C6 | B | UI テストの表を直し、影響を受けるテストを名前で挙げた。UI テストの設計書の扱い（5 章） |
| S-C7 | B | Dialog の結果は今と同じく `MainRouter` で `rememberSaveable` で持つ（画面の中へ移すと `NavigationUiTest.m03` が落ちるため。4.5） |
| S-C8 | B | Share の画面の破棄で選択の待ちも消えることを明記（4.4） |
| S-X7〜S-C13 | C | `MainMenuScreen.kt` は「変えない」にそろえた。アイコンの出どころ、欄の名前と記号、`data` の書き方、既存の口を使う試験の土台（3.3、4.3〜4.5、8 章） |

## 1. 目的と範囲

- サンプルの Receiver 3 つ（`NotificationActionReceiver`、`NotificationDeleteReceiver`、`ShareChooserActionReceiver`）を、ライブラリのイベントの口に置き換える（Kotlin の API の設計書 2 章、5.1）
- **サンプル全体を 4 つの Manager（`AndroidClipboardManager`・`AndroidDialogManager`・`AndroidNotificationManager`・`AndroidShareManager`）を使う形にする**（利用者の決定。2026-10-04。iOS・macOS・Windows のサンプルがすべて Manager を使うのとそろえる）
- 1b で足した口を使う画面を足す（権限の要求の callback 版と `suspend` 版、設定の画面、通知のイベント、shown、選択のイベントつきの Share、型のある Chooser Action、Clipboard の監視とエラーコード、Dialog の Manager）
- 既存の画面の文言・testTag は、なるべく今のまま残す（0d の基準の 317 件を保つため）

範囲の外:

- 既存の口（`*UseCases`、`NotificationPermissionHelper`、`AndroidDialogFragment` の listener の形など）の動作の確かめ。ライブラリの IT-23 で行う（Kotlin の API の設計書 12 章）
- IT-19（権限を外した版）・IT-22（R8）・IT-26（更新をまたぐ Alarm）のための flavor と版。T-21 で行う

## 2. 前提（設計書・実装から取ったもの）

### 2.1 使う公開の口

| 機能 | 口 | 結果・エラー |
|---|---|---|
| 通知の既存の操作 | `AndroidNotificationManager` の `show`・`update`・`cancel`・`createChannel`・`schedule`・`cancelScheduled`・`isScheduled`・`getActive`・`hasPermission`・`areNotificationsEnabled`・`startProgress`〜`stopProgress` | `Result<Unit>` など、既存の UseCase と同じ |
| 権限の要求 | `requestPermission(onResult)` / `suspend requestPermission()` / `cancelPermissionRequest` | `PermissionRequestResult`（`Granted`・`Denied`・`Canceled(reason)`・`Failed(reason)`）。`suspend` 版は `Boolean` を返し、`PermissionRequestDomainError.Canceled(reason)` / `Unavailable(reason)` を投げる |
| 設定の画面 | `canScheduleExactAlarms()`、`openSettings(target, from)` | `NotificationSettingsOpenResult`（`OPENED`・`OPENED_FALLBACK`・`FAILED`） |
| 通知のイベント | `interactions`（タップ・アクション・dismiss）、`shown` | main で届く。`interactions` は受け手が無い間 32 件までプロセスの寿命の間だけ保ち、最初の受け手を足す呼び出しの中で渡す。`shown` は保たない |
| イベントの PendingIntent | `NotificationEventIntents.bodyTap` / `action` / `dismiss` / `fullScreenLaunch`（Manager を通さない factory） | `AndroidPendingIntentRequest`。`action` の `launchApp` の既定値は `false`（broadcast）、`true` で見えない Activity からアプリを前に出す |
| Share の既存の操作 | `AndroidShareManager` の `shareText(content, preview)`・`shareImage`〜`removeDirectShareTargets`・`shareWithCallback`・`cancelPendingCallback` | 既存の UseCase と同じ例外 |
| 選択のイベント | `shareForSelection(content, preview): Long`、`cancelShareSelection(token)`、`selections` | `ShareSelection(token, packageName: String?)`。閉じたとき・Copy などは何も来ない |
| 型のある Chooser Action | `shareTextWithActions(content, actions, preview)`、`chooserActions` | アクションの id。前の Share のアクションは届かない。空・重複の id と読めない画像は `ShareDomainError.InvalidChooserAction(id)` |
| Clipboard | `AndroidClipboardManager` の既存の操作、`startObserving`・`stopObserving`・`isObserving`（main だけ）、`changes`、`errorCodeOf` | 既存の UseCase と同じ例外。`ClipboardErrorCode` の 7 つ |
| Dialog | `AndroidDialogManager.show(request, onResult)` / `suspend show(request)` / `cancel(requestId)` | `DialogResult`（`Answer`（`Button(which, text, value)` か `Dismissed`）・`Canceled(reason)`・`Failed(error)`）。`suspend` 版は `Answer` を返し、`DialogDomainError.Canceled(reason)` / `Unavailable(error)` を投げる |

### 2.2 不足している前提

| 項目 | 扱い |
|---|---|
| `shouldShowRationale`（権限の確かめの表示。UI テスト n01・n04 が見る） | Manager に無い（Activity が要る）。この 1 か所だけ既存の公開の口 `NotificationPermissionHelper.shouldShowPermissionRationale()` を使う（S-1。利用者の決定）。`NotificationPermissionHelper` はコンストラクターで `registerForActivityResult` を呼ぶので、今と同じく `MainActivity.onCreate` で作り、`AppRouter` から渡す |
| CallStyle の前景サービス | Manager に口が無い（Kotlin の API の設計書の付録 A にも無い）。今のまま `CallStyleForegroundService` の公開の Intent の factory と `ContextCompat.startForegroundService` を使う（既存の公開の口） |
| Manager に無い口の記録 | `common.md` は、Manager に口が無いことを機能設計の不足として扱うよう求める。上の 2 つを 10 章に記録し、申し送る（S-C5） |
| 実装結果の文書 | T-23 で書く。この設計書の「設計と実装の違い」は、Kotlin の API の設計書 0.7 と、コミットのメッセージに書いたものだけ |

## 3. 既存のサンプルの調べ（深掘りの結果）

### 3.1 Android（今）

| 項目 | 今の形 |
|---|---|
| 導線 | `MainActivity`（`singleTask`、縦固定）→ `AppRouter`（`MainRouter.kt`）→ `MainMenuScreen` の 4 枚のカード（`menu.dialog`・`menu.notification`・`menu.share`・`menu.clipboard`）→ 機能の画面。`RECEIVED_SHARE` は受けた Share で自動で開く |
| 画面の形 | 「← Back to Main」（`<機能>.back`）、見出し、結果の表示（`<機能>.status`）、`LazyColumn` のカテゴリの見出しとボタン |
| 結果の表示 | `statusText` を ✅ / ❌ / ℹ️ / 🗑️ で始まる文言に替える。UI テストは `waitForStatus(screen, 文言の一部)` で見る |
| 呼ぶ口 | `NotificationUseCases(activity)`、`NotificationPermissionHelper(activity)`、`ShareUseCases(activity)`、`ClipboardUseCases(context)`、`ClipboardChangeMonitor()`、`ProgressForegroundNotifications`、`AndroidDialogFragment` |
| Receiver | `NotificationActionReceiver`（アクション。画面が出ていれば内部の broadcast で `statusText`、出ていなければその場で Toast）、`NotificationDeleteReceiver`（dismiss のその場の Toast）、`ShareChooserActionReceiver`（Chooser Action の Toast） |
| メディアのアクション | Previous / Play / Next は MainActivity への Activity の PendingIntent（押すとアプリが前に出る。`NotificationTapUiTest.n28`） |
| Dialog の結果 | `MainRouter` の `rememberSaveable`（画面を離れて戻っても残る。`NavigationUiTest.m03`） |
| testTag | 全ボタンに `<機能>.<名前>`。`TagInventoryTest` は載せたタグが 1 つずつあることを見る |

### 3.2 iOS（主に参照する対）

| 項目 | iOS の形 | Android での扱い |
|---|---|---|
| 導線 | メインメニューの 4 枚のカード → 機能の画面 | 同じ（今のまま） |
| 画面の形 | 見出し、結果の表示、`sectionView` のカテゴリ | 同じ（今のまま） |
| 呼ぶ口 | すべて `Ios*Manager.shared` | すべて `Android*Manager.getInstance(context)` にする |
| 通知のイベント | アプリの起動で `IosNotificationManager.setup()` と受け手の登録。受け手はログだけ | `MainActivity` で受け手を 1 回登録する（4.2）。Android は今の Toast と `statusText` を保つ |
| 権限 | callback 版だけ | callback 版を今のボタンに使い、`suspend` 版のボタンを 1 つ足す（Kotlin の API の口を見せるため。追加の判断） |
| Clipboard のエラー | `errorCode=<CODE>, errorMessage=…` | 今の `❌ <型名>…` の後ろに ` [errorCode=<CODE>]` を足す（文言の一部で見る今の UI テストを壊さない） |
| Dialog | Manager の callback 版だけ、カテゴリなし、Dialog の画面は 1 つ | 同じく 1 つの画面にし、Manager を使う（4.5。S-2） |

### 3.3 再利用・追加・変更

| 区分 | 対象 |
|---|---|
| 再利用 | 導線、画面の形、`statusText` と testTag の作り、通知の command の組み立て（`build*Command`）、チャンネル、Chooser Action のアイコン（`android.R.drawable.ic_menu_edit` を PNG にする今の処理。`ShareSampleScreen.kt` 242〜252 行）、UI テストの土台（`infra/`） |
| 追加 | `SampleEvents.kt`（アプリで 1 つのイベントの受け手。4.2）、`DialogSampleScreen.kt`（4.5。`AndroidDialogFragmentTestScreen.kt` を置き換える） |
| 変更 | `MainActivity.kt`、`MainRouter.kt`、`NotificationSampleScreen.kt`、`ShareSampleScreen.kt`、`ClipboardSampleScreen.kt`、`AndroidManifest.xml`、UI テスト（5 章） |
| 削除 | `NotificationActionReceiver.kt`、`NotificationDeleteReceiver.kt`、`ShareChooserActionReceiver.kt` と manifest の 3 つの `<receiver>`、`AndroidDialogFragmentTestScreen.kt`（4.5） |
| 変えない | `MainMenuScreen.kt`（4 枚のカードのまま）、`NotificationFullScreenSampleActivity.kt`、`ReceivedShareScreen.kt`、`IncomingShareParser.kt`、試験の土台の `infra/DeviceState.kt` と `HostPhaseTest.kt`（既存の口 `NotificationUseCases`・`CallStyleForegroundService`・`ProgressForegroundNotifications` を直接使うまま。試験の後始末は画面の口に依存させない） |

## 4. 実装の詳細

### 4.1 共通

- 各画面は `remember(context) { Android*Manager.getInstance(context) }` で Manager を取る
- 結果の文言は今の文言を保つ。新しいボタンも ✅ / ❌ / ℹ️ で始める
- 呼び出しの前後に `Log.d` を残す（今のまま）
- **入力欄は置かない**（`common.md`）。値はすべて固定の代表値（不正な値を見せるボタンも固定の値）

### 4.2 イベントの受け手（`SampleEvents.kt`、新規）

`SampleEvents` はアプリで 1 つの `object`。`MainActivity.onCreate` で登録し、`onDestroy` で外す（`Registration` は `MainActivity` が持つ）。

| イベント | 動き |
|---|---|
| `NotificationInteraction`（`ACTION`） | 通知の画面が出ていれば、画面へ渡し、画面が `statusText` を「✅ Action button pressed: <label> (id=<actionId>, notificationId=<notificationId>)」にする。出ていなければ Toast「<label> action pressed」。`<label>` は `data["label"]` |
| `NotificationInteraction`（`DISMISS`） | Toast「<label> dismissed (deleteIntent)」。`<label>` は `data["label"]` |
| `NotificationInteraction`（`BODY_TAP`） | 通知の画面が出ていれば、画面へ渡し、イベントの行（`notification.events`、新規）を「ℹ️ Body tapped (notificationId=<id>, tag=<tag>)」にする |
| `NotificationShown` | 通知の画面が出ていれば、イベントの行を「ℹ️ Scheduled notification shown (notificationId=<id>)」にする |
| `chooserActions` の id | Toast「Custom chooser action tapped」（今と同じ） |

**画面への受け渡し**（S-C4、S-X3）:

- `SampleEvents` は再生しない `MutableSharedFlow`（`replay = 0`、`extraBufferCapacity` は小さく）を持ち、通知の画面が `LaunchedEffect` の中で `collect` する。再生しないので、画面に入り直しても前のイベントは出ない。等しいイベントが続いても、どれも届く
- 「通知の画面が出ているか」は `subscriptionCount` が 1 以上かで判定する。0 なら ACTION は Toast にする
- イベントの行（`notification.events`）は `statusText` と分ける。予約の発火やタップで `statusText` が替わると、今の UI テストが見る文言が上書きされるため

**今の Receiver との違い**（明記する）:

- 今の Receiver は manifest の受け手なので、アプリの Activity が無くても、その場で Toast を出す。`SampleEvents` の受け手は `MainActivity` の寿命に結びつくので、`MainActivity` が無い間（プロセスは生きている）に押されたアクション・dismiss は、ライブラリが保ち（32 件まで、プロセスの寿命の間だけ）、次に `MainActivity` を作ったときの登録の中で渡され、そこで Toast が出る。プロセスが止まった後に押されたものは、ライブラリの受け手がプロセスを起こして保ち、起動の後に渡される（ライブラリの IT-10）
- `MainActivity` は `singleTask` で縦固定。設定の変化で作り直されても、破棄と生成の間に登録が 0 になる瞬間はあるが、その間のイベントは保たれて新しい登録に渡るので、二重にも欠けにもならない（5 章で確かめる）

**試験の間の保ち**:

- 同じプロセスで試験を続けて流すと、Activity が無い間のイベントが保たれ、次の試験の `onCreate` で渡されうる。`infra/DeviceState` の後始末で、`AndroidNotificationManager.interactions` に受け手を一度足してすぐ外し（main で）、保たれたイベントを捨てる（ライブラリの `NotificationEventsTest` と同じやり方）

### 4.3 通知の画面（`NotificationSampleScreen.kt`）

| カテゴリ | ボタン（testTag） | 変更 |
|---|---|---|
| Permission | `checkNotificationPermission` | Manager の `hasPermission`・`areNotificationsEnabled`・`canScheduleExactAlarms`。`shouldShowRationale` は `NotificationPermissionHelper`（S-1） |
| | `requestNotificationPermission` | `requestPermission(onResult)`。`Granted` →「✅ Notification permission granted.」、`Denied` → 今の ❌ の文言、`Canceled(reason)` / `Failed(reason)` →「❌ Permission request ended: <reason>」（新しい文言） |
| | `requestNotificationPermissionCoroutine`（**新規**） | `suspend requestPermission()` を `rememberCoroutineScope` で呼ぶ。真 →「✅ Notification permission granted (coroutine).」、偽 →「❌ Notification permission is not granted (coroutine).」、`PermissionRequestDomainError` →「❌ Permission request ended: <reason>」 |
| | `openNotificationSettings`・`openAppDetailsSettings`・`openExactAlarmSettings` | `openSettings(target, activity)`。`OPENED` と `OPENED_FALLBACK` は今の ℹ️ の文言、`FAILED` は今の ❌ の文言 |
| Style | 16 個（今のまま） | `show` / `cancel` を Manager に。カスタムビューの「Dismiss」は `NotificationEventIntents.action(context, id, tag, "custom_view_dismiss", data = mapOf("label" to "Dismiss"))`（`launchApp` は既定の `false`。今と同じく画面の `statusText` に出す）。**メディアの 3 つ（Previous / Play / Next）は `NotificationEventIntents.action(..., launchApp = true, data = mapOf("label" to <名前>))`**（今と同じくアプリが前に出る。S-X1、S-C1） |
| Interaction & Grouping | `showDeleteIntentSample` | `deleteIntent` を `NotificationEventIntents.dismiss(context, id, tag, data = mapOf("label" to "DeleteIntent Sample"))` に |
| | `showActionButtonsSample`・`deleteActionButtonsSample` | Accept / Decline を `NotificationEventIntents.action(context, 1112, tag, "accept", launchApp = false, data = mapOf("label" to "Accept"))` など |
| | `showEventSample`（**新規**） | 本文のタップを `NotificationEventIntents.bodyTap(context, 1120, null, launchApp = true)` にした通知。タップでアプリが前に出て、イベントの行が BODY_TAP を表示する |
| | その他（グループ、全画面） | Manager に替えるだけ。全画面はアプリの `NotificationFullScreenSampleActivity` のまま |
| Progress | 6 個 | Manager に替えるだけ |
| Progress FGS | 5 個 | `startProgress`〜`stopProgress` に |
| Call FGS | 4 個 | 今のまま（2.2）。権限の確かめだけ Manager に |
| Schedule | `scheduleNotification15Sec`・`checkScheduleIsScheduled`・`deleteScheduleNotification` | Manager に。発火したら `shown` がイベントの行に出る |

### 4.4 Share の画面（`ShareSampleScreen.kt`）

| カテゴリ | ボタン（testTag） | 変更 |
|---|---|---|
| Text | `shareText`・`shareUrl`・`shareTextWithRichPreview`・`shareWithSubjectTitle` | `shareText(content, preview)`（JSON の引数は無い） |
| | `shareTextWithCustomAction` | `shareTextWithActions(content, listOf(ShareChooserAction("custom", "Custom action", <今のアイコンの PNG のバイト列>)))`。タップは `SampleEvents` の Toast（今と同じ文言）。結果の文言は今のまま |
| | `shareTextWithInvalidAction`（**新規**） | 固定の重複した id（`"dup"` を 2 つ）で `shareTextWithActions`。`ShareDomainError.InvalidChooserAction` →「❌ InvalidChooserAction: dup」。Sharesheet は開かない（S-X5） |
| Image / File / Direct Share | 6 個 | Manager に替えるだけ |
| Callback | `shareWithCallback`・`shareWithCallbackRichPreview`・`cancelPendingCallback` | Manager に替えるだけ（文言は今のまま） |
| Selection Event（**新規**） | `shareForSelection` | 印を覚え、「ℹ️ Sharesheet opened (token=<印>), waiting for selection...」。選択のイベント（画面が出ている間だけ受ける）で「✅ Selected (token=<印>): <パッケージ>」。`packageName` が `null` なら「✅ Selected (token=<印>): (unknown package)」（S-X6） |
| | `cancelShareSelection` | 覚えた印で取り消し、「✅ cancelShareSelection called (token=<印>)」。印が無ければ「ℹ️ No selection is pending.」 |

- 画面を閉じたときに今と同じく `cancelPendingCallback()` を呼ぶ。これは今の待ち（`shareWithCallback` と `shareForSelection` のどちらも）を消す（Kotlin の API の設計書 8.9 の `cancel()`）。閉じた後に選んでも、どちらの結果も届かない（S-C8）

### 4.5 Dialog（S-2。利用者の決定）

今の「Dialog Example」（`menu.dialog`）を `AndroidDialogManager` を使う画面に替え、iOS と同じく Dialog の画面を 1 つにする。

- `AndroidDialogManager` は中で同じ `AndroidDialogFragment` を出す（`FragmentDialogPresenter` が `AndroidDialogFragment.newRequestInstance` を前面の FragmentActivity か透明な宿主に出す）
- `AndroidDialogFragmentTestScreen.kt`（`handleAndroidDialogTestButtonClick` を含む）は `DialogSampleScreen.kt` に置き換える
- **結果の文言は今と同じく `MainRouter` の `rememberSaveable` で持つ**（画面の中へ移すと、画面を離れて戻ったときに消え、`NavigationUiTest.m03` が落ちる。S-C7）
- 既存の入口（`AndroidDialogFragment` の listener の形）はサンプルから使われなくなる。確かめはライブラリの IT-23 で行う

**要求の値**（今の値をそのまま保つ。S-X2、S-C2）:

| ボタン（testTag） | 要求 |
|---|---|
| `dialog.showDialog` | `Alert(title = "Hello from Android", message = "This is a native Android dialog!", buttonText = "OK")` |
| `dialog.showConfirmDialog` | `Confirm(title = "Confirmation", message = "Do you want to proceed with this action?", negativeText = "No", positiveText = "Yes")` |
| `dialog.showSingleChoiceItemDialog` | `SingleChoice(title = "Please select one", items = ["Option 1", "Option 2", "Option 3"], checkedIndex = 0, negativeText = "Cancel", positiveText = "OK")` |
| `dialog.showMultiChoiceItemDialog` | `MultiChoice(title = "Multiple Selection", items = ["Option 1"〜"Option 4"], checked = [false, true, false, true], negativeText = "Cancel", positiveText = "OK")` |
| `dialog.showTextInputDialog` | `TextInput(title = "Text Input", message = "Please enter your name", hint = "Enter here...", negativeText = "Cancel", positiveText = "OK", enablePositiveWhenEmpty = false)` |
| `dialog.showLoginDialog` | `Login(title = "Login", message = "Please enter your credentials", usernameHint = "Username", passwordHint = "Password", negativeText = "Cancel", positiveText = "Login", enablePositiveWhenEmpty = false)` |

- 6 つとも `options = DialogOptions(cancelable = false, cancelableOnTouchOutside = false)`（今のサンプルと同じ。D-16 を保つ）

**新しいボタン**:

| ボタン（testTag） | 要求と呼ぶ口 | 結果 |
|---|---|---|
| `dialog.showConfirmCoroutine` | 上の `Confirm` を `suspend show(...)` で | 答え、または「❌\nResult: Canceled: <reason>」「❌\nResult: Unavailable: <error>」 |
| `dialog.showCancelableDialog` | `Alert(title = "Cancelable", message = "Tap outside or press Back.", buttonText = "OK", options = DialogOptions())`（既定の閉じられる形） | Back または外のタップで「✅\nResult: Dismissed」 |
| `dialog.showAndCancel` | 上の `Alert` を `show` し、2 秒後に `cancel(requestId)` | 「❌\nResult: Canceled: REQUESTED」 |

**結果の文言**（`dialog.status`。今の「✅\nResult: 」の前置きを保つ）:

| 結果 | 文言 |
|---|---|
| `Button` | 「✅\nResult: <kind> - button: <which> (<text>)<値>」。`<kind>` は要求の種類（`alert`・`confirm`・`singleChoice`・`multiChoice`・`textInput`・`login`）。`<値>` は `SingleChoice` →「, index: <index>」、`MultiChoice` →「, checked: [<…>]」、`Text` →「, textLength: <長さ>」、`Login` →「, usernameLength: <長さ>, passwordLength: <長さ>」、`None` → なし |
| `Dismissed` | 「✅\nResult: <kind> - Dismissed」 |
| `Canceled(reason)` | 「❌\nResult: <kind> - Canceled: <reason>」（callback 版と `suspend` 版で同じ記号） |
| `Failed(error)` | 「❌\nResult: <kind> - Unavailable: <error>」 |

- 入力の値（テキスト、ユーザー名、パスワード）は出さず長さだけを出す（ログの規則と同じ。UI テストの設計書 3.8 のパスワードの件）
- ボタンを押したときの `value` が要求の種類ごとにどう入るか（例: Cancel のときの `SingleChoice` の `index`）は、`FragmentDialogPresenter` の実装の値に合わせて期待値を決める（実装の時に確かめる）

### 4.6 Clipboard の画面（`ClipboardSampleScreen.kt`）

- `ClipboardUseCases` と `ClipboardChangeMonitor` の直接の使用をやめ、`AndroidClipboardManager` にする
- 監視: `startObserving()` と、画面が出ている間の `changes` の受け手。文言は今のまま（「✅ observing started」「ℹ️ Clipboard changed (<回数>)」「✅ observing stopped」）。画面を閉じたら `stopObserving()`（今と同じ）
- エラー: 今の ❌ の文言の後ろに ` [errorCode=<errorCodeOf の値>]` を足す

### 4.7 manifest

- サンプルの 3 つの `<receiver>` を消す。ライブラリの受け手は AAR の manifest で入る

## 5. UI テスト

**影響を受ける既存のケース**（文言は保つが経路が変わるもの。理由を 1b の実装結果に書く）:

| テスト | ケース | 変わる経路 |
|---|---|---|
| `NotificationStyleUiTest` | n16（カスタムビューの Dismiss） | `NotificationActionReceiver` → `interactions` |
| `NotificationInteractionUiTest` | n22（dismiss の Toast）、n24・n25・n26（Accept / Decline） | 同上 |
| `NotificationTapUiTest` | n28（メディアのアクションでアプリが前に出る） | Activity の PendingIntent → `NotificationLaunchActivity`。前に出た後の `statusText`（「✅ Action button pressed: Previous …」）の確かめを足す |
| `ShareUiTest` | s04（Chooser Action の Toast） | `ShareChooserActionReceiver` → `chooserActions` |

**文言を直す既存のケース**（入口を Manager に替えたため。理由を結果に書く）:

| テスト | ケース | 直す所 |
|---|---|---|
| `DialogUiTest` | d01〜d15 の `expectResult` | 4.5 の文言へ。d11・d14 は値ではなく長さ（`textLength: 5`、`usernameLength: 5, passwordLength: 5`）を確かめる形に変わる |
| `NavigationUiTest` | m03 | 4.5 の文言へ（結果が残ることの確かめは保つ） |

**足すケース**:

| テスト | ケース |
|---|---|
| `NotificationHostStateUiTest` | `requestNotificationPermissionCoroutine` の許可・拒否 |
| `NotificationInteractionUiTest` | MainActivity を壊した（プロセスは生きている）状態でシェードの Accept を押し、MainActivity を起動すると Toast「Accept action pressed」が出る（S-C3） |
| `NotificationInteractionUiTest` | 画面に入り直しても前のアクションのイベントが `statusText` に再び出ない。同じアクションを 2 回押すと 2 回とも届く（S-C4） |
| `NotificationInteractionUiTest` | MainActivity を作り直した（`ActivityScenario.recreate`）後にアクションを押すと、`statusText` に 1 回だけ出る（受け手が二重にならない） |
| `NotificationTapUiTest` | `showEventSample` のタップでアプリが前に出て、イベントの行に BODY_TAP |
| `NotificationScheduleUiTest` | 予約の発火でイベントの行に shown |
| `ShareUiTest` | `shareForSelection` で選ぶ・閉じる（何も来ない）・取り消す、`shareTextWithInvalidAction` |
| `ClipboardSampleScreenUiTest` | エラーの表示に `errorCode` が入る |
| `DialogUiTest` | `showConfirmCoroutine`、`showCancelableDialog`（Back で Dismissed）、`showAndCancel` |
| `TagInventoryTest` | 新しい testTag を足す（足さなくても落ちないが、方針として足す） |

- 0d の基準との差は「足したケース」と「`DialogUiTest`・`NavigationUiTest.m03` の文言」だけになる見込み（要検証）
- UI テストの設計書（`designs/2026-10-03-android-c-abi-ui-test-design.md`）は、足したケースと直した文言を 1b の実装の後に追記する（`TagInventoryTest` が元にする 5.1 と 6 章を含む）

## 6. 手動で確かめる項目

なし（第 1 版の 1 件は、Activity を壊せばアプリの中で作れるので UI テストへ移した。プロセスを止めた後の保ちはライブラリの IT-10 で確かめる）。

## 7. 利用者の決定（2026-10-04）

| ID | 事項 | 決定 |
|---|---|---|
| - | サンプルの入口 | 全体を 4 つの Manager にする（ほかの OS とそろえる） |
| S-1 | `shouldShowRationale` の表示 | この 1 か所だけ既存の公開の口 `NotificationPermissionHelper` を使う。表示と UI テストを保ち、Kotlin の API は変えない |
| S-2 | Dialog の画面 | 今の「Dialog Example」を Manager に替え、画面を 1 つにする。`DialogUiTest` の文言を直す |

## 8. 変更ファイル一覧

| 区分 | ファイル（`android/AndroidLibraryExample/app/src/` の下） |
|---|---|
| 新規 | `main/java/.../example/SampleEvents.kt`、`main/java/.../example/DialogSampleScreen.kt` |
| 変更 | `main/java/.../example/MainActivity.kt`、`MainRouter.kt`、`NotificationSampleScreen.kt`、`ShareSampleScreen.kt`、`ClipboardSampleScreen.kt`、`main/AndroidManifest.xml`、`androidTest/java/.../example/` の `DialogUiTest.kt`・`NavigationUiTest.kt`（文言とケース）、`NotificationHostStateUiTest.kt`・`NotificationInteractionUiTest.kt`・`NotificationTapUiTest.kt`・`NotificationScheduleUiTest.kt`・`ShareUiTest.kt`・`ClipboardSampleScreenUiTest.kt`・`TagInventoryTest.kt`（ケースの追加）、`androidTest/java/.../example/infra/DeviceState.kt`（保たれたイベントを捨てる後始末だけ。4.2） |
| 削除 | `main/java/.../example/NotificationActionReceiver.kt`、`NotificationDeleteReceiver.kt`、`ShareChooserActionReceiver.kt`、`AndroidDialogFragmentTestScreen.kt` |
| 変えない | `MainMenuScreen.kt`、`NotificationFullScreenSampleActivity.kt`、`ReceivedShareScreen.kt`、`IncomingShareParser.kt`、`ReceivedShareContent.kt`、`ui/theme/`、`androidTest/java/.../example/HostPhaseTest.kt`（既存の口を直接使うまま） |

`.../example` は `com/jonghyunkim/android/nativetoolkit/example`。

## 9. 確かめていないこと

- `shown` のイベントの行が、`NotificationScheduleUiTest` の見る文言に影響しないこと（行を分けたので影響しない見込み）
- Dialog のボタンを押したときの `value` の入り方（4.5。実装の時に確かめて期待値を決める）
- MainActivity の作り直しの間のイベントが保たれて新しい登録に渡ること（4.2。5 章の UI テストで確かめる）

## 10. Manager に無い口の記録（申し送り。S-C5）

| 口 | 今の扱い | 申し送り先 |
|---|---|---|
| 権限の説明を出すべきか（`shouldShowRequestPermissionRationale`） | サンプルは既存の `NotificationPermissionHelper` を使う | C ABI の設計書 第 2 部（N の行の扱い）と、マニュアル（段階 4。Manager を勧める入口として書くときに、この口だけ別の入口になることを書く） |
| CallStyle の前景サービス | サンプルは既存の `CallStyleForegroundService` の公開の Intent の factory を使う | 同上。D-5 で C ABI の範囲の外としたが、Kotlin の Manager の範囲の外かは別の判断として、段階 2 の前に決める |

- 1b の実装結果（T-23）の「Kotlin の API の設計書との違い・申し送り」にも同じ 2 行を書く
