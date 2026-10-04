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
| 作成日 | 2026-10-04（第 1 版） |
| ブランチ | `feature/NTKIT-17` |

## 1. 目的と範囲

- サンプルの Receiver 3 つ（`NotificationActionReceiver`、`NotificationDeleteReceiver`、`ShareChooserActionReceiver`）を、ライブラリのイベントの口に置き換える（Kotlin の API の設計書 2 章、5.1）
- **サンプル全体を 4 つの Manager（`AndroidClipboardManager`・`AndroidDialogManager`・`AndroidNotificationManager`・`AndroidShareManager`）を使う形にする**（利用者の決定。2026-10-04。iOS・macOS・Windows のサンプルがすべて Manager を使うのとそろえる）
- 1b で足した口を使う画面を足す（権限の要求の callback 版と `suspend` 版、設定の画面、通知のイベント、shown、選択のイベントつきの Share、型のある Chooser Action、Clipboard の監視とエラーコード、Dialog の Manager）
- 既存の画面の文言・testTag は、なるべく今のまま残す（0d の基準の 317 件を保つため）

範囲の外:

- 既存の口（`*UseCases`、`NotificationPermissionHelper`、`AndroidDialogFragment` など）の動作の確かめ。ライブラリの IT-23 で行う（Kotlin の API の設計書 12 章）
- IT-19（権限を外した版）・IT-22（R8）・IT-26（更新をまたぐ Alarm）のための flavor と版。T-21 で行う

## 2. 前提（設計書・実装から取ったもの）

### 2.1 使う公開の口

| 機能 | 口 | 結果・エラー |
|---|---|---|
| 通知の既存の操作 | `AndroidNotificationManager` の `show`・`update`・`cancel`・`createChannel`・`schedule`・`cancelScheduled`・`isScheduled`・`getActive`・`hasPermission`・`areNotificationsEnabled`・`startProgress`〜`stopProgress` | `Result<Unit>` など、既存の UseCase と同じ |
| 権限の要求 | `requestPermission(onResult)` / `suspend requestPermission()` / `cancelPermissionRequest` | `PermissionRequestResult`（`Granted`・`Denied`・`Canceled(reason)`・`Failed(reason)`）。`suspend` 版は `Boolean` を返し、`PermissionRequestDomainError.Canceled` / `Unavailable` を投げる |
| 設定の画面 | `canScheduleExactAlarms()`、`openSettings(target, from)` | `NotificationSettingsOpenResult`（`OPENED`・`OPENED_FALLBACK`・`FAILED`） |
| 通知のイベント | `interactions`（タップ・アクション・dismiss）、`shown` | main で届く。`interactions` は受け手が無い間 32 件まで保つ。`shown` は保たない |
| イベントの PendingIntent | `NotificationEventIntents.bodyTap` / `action` / `dismiss` / `fullScreenLaunch`（Manager を通さない factory） | `AndroidPendingIntentRequest` |
| Share の既存の操作 | `AndroidShareManager` の `shareText(content, preview)`・`shareImage`〜`removeDirectShareTargets`・`shareWithCallback`・`cancelPendingCallback` | 既存の UseCase と同じ例外 |
| 選択のイベント | `shareForSelection(content, preview): Long`、`cancelShareSelection(token)`、`selections` | `ShareSelection(token, packageName)`。閉じたとき・Copy などは何も来ない |
| 型のある Chooser Action | `shareTextWithActions(content, actions, preview)`、`chooserActions` | アクションの id。前の Share のアクションは届かない。`InvalidChooserAction(id)` |
| Clipboard | `AndroidClipboardManager` の既存の操作、`startObserving`・`stopObserving`・`isObserving`（main だけ）、`changes`、`errorCodeOf` | 既存の UseCase と同じ例外。`ClipboardErrorCode` の 7 つ |
| Dialog | `AndroidDialogManager.show(request, onResult)` / `suspend show(request)` / `cancel(requestId)` | `DialogResult`（`Answer`（`Button` か `Dismissed`）・`Canceled`・`Failed`）。`suspend` 版は `Answer` を返し、`DialogDomainError.Canceled` / `Unavailable` を投げる |

### 2.2 不足している前提

| 項目 | 扱い |
|---|---|
| `shouldShowRationale`（権限の確かめの表示。UI テスト n01・n04 が見る） | Manager に無い（Activity が要る）。この 1 か所だけ既存の公開の口 `NotificationPermissionHelper(activity).shouldShowPermissionRationale()` を使う（S-1。利用者の決定） |
| CallStyle の前景サービス | Manager に口が無い（Kotlin の API の設計書の付録 A にも無い）。今のまま `CallStyleForegroundService` の公開の Intent の factory と `ContextCompat.startForegroundService` を使う（既存の公開の口。追加の判断） |
| 実装結果の文書 | T-23 で書く。この設計書の「設計と実装の違い」は、Kotlin の API の設計書 0.7 と、コミットのメッセージに書いたものだけ |

## 3. 既存のサンプルの調べ（深掘りの結果）

### 3.1 Android（今）

| 項目 | 今の形 |
|---|---|
| 導線 | `MainActivity` → `AppRouter`（`MainRouter.kt`）→ `MainMenuScreen` の 4 枚のカード（`menu.dialog`・`menu.notification`・`menu.share`・`menu.clipboard`）→ 機能の画面。`RECEIVED_SHARE` は受けた Share で自動で開く |
| 画面の形 | 「← Back to Main」（`<機能>.back`）、見出し、結果の表示（`<機能>.status`）、`LazyColumn` のカテゴリの見出しとボタン |
| 結果の表示 | `statusText` を ✅ / ❌ / ℹ️ / 🗑️ で始まる文言に替える。UI テストは `waitForStatus(screen, 文言の一部)` で見る |
| 呼ぶ口 | `NotificationUseCases(activity)`、`NotificationPermissionHelper(activity)`、`ShareUseCases(activity)`、`ClipboardUseCases(context)`、`ClipboardChangeMonitor()`、`ProgressForegroundNotifications`、`AndroidDialogFragment` |
| Receiver | `NotificationActionReceiver`（アクション。画面が出ていれば内部の broadcast で `statusText`、出ていなければ Toast）、`NotificationDeleteReceiver`（dismiss の Toast）、`ShareChooserActionReceiver`（Chooser Action の Toast） |
| testTag | 全ボタンに `<機能>.<名前>`。`TagInventoryTest` が一覧を固定する |

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
| 再利用 | 導線、画面の形、`statusText` と testTag の作り、通知の command の組み立て（`build*Command`）、チャンネル、UI テストの土台（`infra/`） |
| 追加 | `SampleEvents.kt`（アプリで 1 つのイベントの受け手。4.2）、`DialogSampleScreen.kt`（4.5。`AndroidDialogFragmentTestScreen.kt` を置き換える） |
| 変更 | `MainActivity.kt`、`MainRouter.kt`、`MainMenuScreen.kt`、`NotificationSampleScreen.kt`、`ShareSampleScreen.kt`、`ClipboardSampleScreen.kt`、`AndroidManifest.xml`、UI テスト |
| 削除 | `NotificationActionReceiver.kt`、`NotificationDeleteReceiver.kt`、`ShareChooserActionReceiver.kt` と manifest の 3 つの `<receiver>`、`AndroidDialogFragmentTestScreen.kt`（4.5） |
| 変えない | `NotificationFullScreenSampleActivity.kt`、`ReceivedShareScreen.kt`、`IncomingShareParser.kt` |

## 4. 実装の詳細

### 4.1 共通

- 各画面は `remember(context) { Android*Manager.getInstance(context) }` で Manager を取る
- 結果の文言は今の文言を保つ。新しいボタンも ✅ / ❌ / ℹ️ で始める
- 呼び出しの前後に `Log.d` を残す（今のまま）
- **入力欄は置かない**（`common.md`）。値はすべて固定の代表値

### 4.2 イベントの受け手（`SampleEvents.kt`、新規）

`MainActivity.onCreate` で 1 回だけ登録し、`onDestroy` で外す。`interactions` は受け手が無い間の 32 件を保つので、アプリが閉じている間のタップも、起動の後に届く。

| イベント | 動き（今の Receiver と同じ文言） |
|---|---|
| `NotificationInteraction`（`ACTION`） | 通知の画面が出ていれば、その画面の `statusText` を「✅ Action button pressed: <label> (id=<actionId>, notificationId=<id>)」にする。出ていなければ Toast「<label> action pressed」。`<label>` はアクションの PendingIntent の `data` に入れた `label` |
| `NotificationInteraction`（`DISMISS`） | Toast「<label> dismissed (deleteIntent)」。`<label>` は `data` の `label` |
| `NotificationInteraction`（`BODY_TAP`） | 通知の画面が出ていれば、イベントの行（`notification.events`、新規）を「ℹ️ Body tapped (notificationId=<id>, tag=<tag>)」にする |
| `NotificationShown` | 通知の画面が出ていれば、イベントの行を「ℹ️ Scheduled notification shown (notificationId=<id>)」にする |
| `chooserActions` の id | Toast「Custom chooser action tapped」（今と同じ） |

- 「通知の画面が出ているか」と画面への渡し方は、今の `NotificationActionReceiver.isSampleScreenActive` と内部の broadcast の代わりに、`SampleEvents` が持つ `MutableStateFlow`（画面が `collectAsState` する）を使う
- イベントの行（`notification.events`）は `statusText` と分ける。予約の発火やタップで `statusText` が替わると、今の UI テストが見る文言が上書きされるため

### 4.3 通知の画面（`NotificationSampleScreen.kt`）

| カテゴリ | ボタン（testTag） | 変更 |
|---|---|---|
| Permission | `checkNotificationPermission` | Manager の `hasPermission`・`areNotificationsEnabled`・`canScheduleExactAlarms`。`shouldShowRationale` は S-1 |
| | `requestNotificationPermission` | `requestPermission(onResult)`。`Granted` →「✅ Notification permission granted.」、`Denied` → 今の ❌ の文言、`Canceled` / `Failed` →「❌ Permission request ended: <reason>」（新しい文言） |
| | `requestNotificationPermissionCoroutine`（**新規**） | `suspend requestPermission()` を `rememberCoroutineScope` で呼ぶ。真 →「✅ Notification permission granted (coroutine).」、偽 →「❌ Notification permission is not granted (coroutine).」、例外 →「❌ Permission request ended: <型名>」 |
| | `openNotificationSettings`・`openAppDetailsSettings`・`openExactAlarmSettings` | `openSettings(target, activity)`。`OPENED` と `OPENED_FALLBACK` は今の ℹ️ の文言、`FAILED` は今の ❌ の文言 |
| Style | 16 個（今のまま） | `show` / `cancel` を Manager に。カスタムビューの「Dismiss」とメディアの 3 つのアクションは `NotificationEventIntents.action(..., data = mapOf("label" to <名前>))` に |
| Interaction & Grouping | `showDeleteIntentSample` | `deleteIntent` を `NotificationEventIntents.dismiss(..., data = mapOf("label" to "DeleteIntent Sample"))` に |
| | `showActionButtonsSample`・`deleteActionButtonsSample` | Accept / Decline を `NotificationEventIntents.action(..., launchApp = false, data = label)` に |
| | `showEventSample`（**新規**） | 本文のタップを `NotificationEventIntents.bodyTap(..., launchApp = true)` にした通知（id 1120）。タップでアプリが前に出て、イベントの行が BODY_TAP を表示する |
| | その他（グループ、全画面） | Manager に替えるだけ。全画面はアプリの `NotificationFullScreenSampleActivity` のまま |
| Progress | 6 個 | Manager に替えるだけ |
| Progress FGS | 5 個 | `startProgress`〜`stopProgress` に |
| Call FGS | 4 個 | 今のまま（2.2）。権限の確かめだけ Manager に |
| Schedule | `scheduleNotification15Sec`・`checkScheduleIsScheduled`・`deleteScheduleNotification` | Manager に。発火したら `shown` がイベントの行に出る |

### 4.4 Share の画面（`ShareSampleScreen.kt`）

| カテゴリ | ボタン（testTag） | 変更 |
|---|---|---|
| Text | `shareText`・`shareUrl`・`shareTextWithRichPreview`・`shareWithSubjectTitle` | `shareText(content, preview)`（JSON の引数は無い） |
| | `shareTextWithCustomAction` | `shareTextWithActions(content, listOf(ShareChooserAction("custom", "Custom", <アイコンの PNG>)))`。タップは `SampleEvents` の Toast（今と同じ文言） |
| Image / File / Direct Share | 6 個 | Manager に替えるだけ |
| Callback | `shareWithCallback`・`shareWithCallbackRichPreview`・`cancelPendingCallback` | Manager に替えるだけ（文言は今のまま） |
| Selection Event（**新規**） | `shareForSelection` | 印を覚え、「ℹ️ Sharesheet opened (token=<印>), waiting for selection...」。選択のイベント（画面が出ている間だけ受ける）で「✅ Selected (token=<印>): <パッケージ>」 |
| | `cancelShareSelection` | 覚えた印で取り消し、「✅ cancelShareSelection called (token=<印>)」。印が無ければ「ℹ️ No selection is pending.」 |

### 4.5 Dialog（S-2。利用者の決定）

今の「Dialog Example」（`menu.dialog`）を `AndroidDialogManager` を使う画面に替え、iOS と同じく Dialog の画面を 1 つにする。

- `AndroidDialogManager` は中で同じ `AndroidDialogFragment` を出す（`FragmentDialogPresenter` が `AndroidDialogFragment.newRequestInstance` を前面の FragmentActivity か透明な宿主に出す）。見た目は変わらず、変わるのは結果の受け方と表示の文言だけ
- `AndroidDialogFragmentTestScreen.kt`（`handleAndroidDialogTestButtonClick` を含む）は `DialogSampleScreen.kt` に置き換える。`MainRouter` の `dialogResultText` の持ち方は画面の中へ移す
- 既存の入口（`AndroidDialogFragment` の listener の形）はサンプルから使われなくなる。確かめはライブラリの IT-23 で行う（Kotlin の API の設計書 12 章）

| ボタン（testTag。今の 6 つは名前を保つ） | 呼ぶ口 | 結果の表示（`dialog.status`） |
|---|---|---|
| `dialog.showDialog` | `show(DialogRequest.Alert("Native Toolkit", "This is a sample dialog."))` | 「✅ Button: POSITIVE (OK)」「✅ Dismissed」など、`DialogResult` を 1 行で（`Answer` は押したボタン `Button(which, text, value)` か、閉じた `Dismissed`） |
| `dialog.showConfirmDialog` | `DialogRequest.Confirm` | 同上 |
| `dialog.showSingleChoiceItemDialog` | `DialogRequest.SingleChoice`（3 つの項目） | 同上と選んだ番号 |
| `dialog.showMultiChoiceItemDialog` | `DialogRequest.MultiChoice` | 同上と選んだ番号の並び |
| `dialog.showTextInputDialog` | `DialogRequest.TextInput` | 同上と入力の長さ（値は出さない。ログの規則と同じ） |
| `dialog.showLoginDialog` | `DialogRequest.Login` | 同上とユーザー名・パスワードの長さ |
| `dialog.showConfirmCoroutine`（**新規**） | `suspend show(DialogRequest.Confirm)` | 答え、または「❌ Canceled: <reason>」「❌ Unavailable: <reason>」 |
| `dialog.showAndCancel`（**新規**） | `show` の 2 秒後に `cancel(requestId)` | 「ℹ️ Canceled: REQUESTED」 |

- 文言の形は実装のときに `DialogResult` の型に合わせて決め、`DialogUiTest` を同じ文言に直す。直した理由（入口を Manager に替えた）は 1b の実装結果に書く

### 4.6 Clipboard の画面（`ClipboardSampleScreen.kt`）

- `ClipboardUseCases` と `ClipboardChangeMonitor` の直接の使用をやめ、`AndroidClipboardManager` にする
- 監視: `startObserving()` と、画面が出ている間の `changes` の受け手。文言は今のまま（「✅ observing started」「ℹ️ Clipboard changed (<回数>)」「✅ observing stopped」）。画面を閉じたら `stopObserving()`（今と同じ）
- エラー: 今の ❌ の文言の後ろに ` [errorCode=<errorCodeOf の値>]` を足す

### 4.7 manifest

- サンプルの 3 つの `<receiver>` を消す。ライブラリの受け手は AAR の manifest で入る

## 5. UI テスト

| 区分 | 対象 |
|---|---|
| そのまま通る見込み | 文言を保つもの全部（Style・Interaction・Progress・Call・Schedule・Settings・Share・Clipboard の既存のケース） |
| 直す | `TagInventoryTest`（新しい testTag を足す）、`DialogUiTest`（結果の文言。4.5） |
| 足す | `requestNotificationPermissionCoroutine`（許可・拒否。HostState）、`showEventSample` のタップで BODY_TAP、予約の発火で shown、`shareForSelection` で選ぶ・閉じる・取り消す、Clipboard のエラーコード、Dialog の `showConfirmCoroutine`・`showAndCancel` |
| 理由を結果に書く | Receiver を置き換えたテスト（文言は同じでも経路が変わる）、`DialogUiTest`（入口を Manager に替えて文言が変わる）、`HostPhaseTest`（補いを消した。済み） |

- 0d の基準との差は「足したケース」と「`DialogUiTest` の文言」だけになる見込み（要検証）

## 6. 手動で確かめる項目

| 項目 | 自動化できない理由 |
|---|---|
| アプリを閉じた状態で通知のアクションを押し、起動の後に Toast が出る | 状態を誘発できない（プロセスを止めた後の起動の順序を UI テストで作れない。IT-09 の保ちはライブラリで確かめ済み） |

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
| 変更 | `main/java/.../example/MainActivity.kt`、`MainRouter.kt`、`NotificationSampleScreen.kt`、`ShareSampleScreen.kt`、`ClipboardSampleScreen.kt`、`main/AndroidManifest.xml`、`androidTest/java/.../example/` の `TagInventoryTest.kt`・`NotificationHostStateUiTest.kt`・`NotificationInteractionUiTest.kt`・`NotificationTapUiTest.kt`・`NotificationScheduleUiTest.kt`・`ShareUiTest.kt`・`ClipboardSampleScreenUiTest.kt`（ケースの追加）、`DialogUiTest.kt`（文言とケースの追加） |
| 削除 | `main/java/.../example/NotificationActionReceiver.kt`、`NotificationDeleteReceiver.kt`、`ShareChooserActionReceiver.kt`、`AndroidDialogFragmentTestScreen.kt` |
| 変えない | `MainMenuScreen.kt`、`NotificationFullScreenSampleActivity.kt`、`ReceivedShareScreen.kt`、`IncomingShareParser.kt`、`ReceivedShareContent.kt`、`ui/theme/` |

`.../example` は `com/jonghyunkim/android/nativetoolkit/example`。

## 9. 確かめていないこと

- アイコンの PNG（`shareTextWithActions`）は、今の JSON の版と同じ画像をリソースから読む想定。今の画像の出どころを実装のときに確かめる
- `shown` のイベントの行が、`NotificationScheduleUiTest` の見る文言に影響しないこと（行を分けたので影響しない見込み）
