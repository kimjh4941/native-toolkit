# 通知機能

言語:

- 日本語（このページ）
- English: [notification.md](notification.md)
- 한국어: [notification.ko.md](notification.ko.md)

← [マニュアルトップに戻る](index.ja.md)

---

## 目次

- [Android](#android)
  - [AndroidNotificationManager](#androidnotificationmanager)
  - [1.x からの変更点](#1x-からの変更点)
  - [セットアップ](#セットアップ)
    - [権限とコンポーネント](#権限とコンポーネント)
    - [初期化](#初期化)
    - [マネージャーの取得](#マネージャーの取得)
  - [パーミッション](#パーミッション)
    - [権限の状態を確認する](#権限の状態を確認する)
    - [権限をリクエストする（コールバック）](#権限をリクエストするコールバック)
    - [権限をリクエストする（コルーチン）](#権限をリクエストするコルーチン)
    - [権限リクエストをキャンセルする](#権限リクエストをキャンセルする)
    - [設定画面を開く](#設定画面を開く)
  - [チャンネル管理](#チャンネル管理)
  - [基本的な通知操作](#基本的な通知操作)
  - [通知スタイル](#通知スタイル)
  - [プラットフォームオプション](#プラットフォームオプション)
  - [カスタムビュースタイル](#カスタムビュースタイル)
  - [グループ通知](#グループ通知)
  - [インタラクション](#インタラクション)
    - [イベントの受け取り](#イベントの受け取り)
    - [本体タップイベント](#本体タップイベント)
    - [アクションボタン](#アクションボタン)
    - [DeleteIntent（削除イベント）](#deleteintent削除イベント)
    - [FullScreenIntent（フルスクリーン表示）](#fullscreenintentフルスクリーン表示)
  - [進捗通知](#進捗通知)
  - [フォアグラウンドサービス通知](#フォアグラウンドサービス通知)
  - [スケジュール通知](#スケジュール通知)
    - [スケジュールのキャンセル](#スケジュールのキャンセル)
    - [スケジュール済み確認](#スケジュール済み確認)
    - [端末再起動後の復元](#端末再起動後の復元)
    - [1.x が保存したスケジュール](#1x-が保存したスケジュール)
  - [C ABI](#c-abi)
    - [初期化・権限・設定](#初期化権限設定)
    - [チャンネルと内容のビルダー](#チャンネルと内容のビルダー)
    - [スタイル・タップ・アクション](#スタイルタップアクション)
    - [スケジュールと進捗](#スケジュールと進捗)
    - [インタラクションと表示イベント](#インタラクションと表示イベント)
    - [通知のエラー](#通知のエラー)
- [iOS](#ios)
  - [IosNotificationManager](#iosnotificationmanager)
  - [セットアップ](#セットアップ-1)
  - [パーミッション](#パーミッション-1)
    - [通知権限をリクエストする](#通知権限をリクエストする)
    - [権限の確認](#権限の確認)
    - [認証ステータスの取得](#認証ステータスの取得)
    - [通知設定を開く](#通知設定を開く)
  - [通知の表示](#通知の表示-1)
    - [即時表示](#即時表示)
    - [添付ファイル付き即時表示](#添付ファイル付き即時表示)
    - [時間間隔トリガー](#時間間隔トリガー)
    - [カレンダートリガー](#カレンダートリガー)
    - [位置情報トリガー](#位置情報トリガー)
  - [添付ファイル](#添付ファイル)
  - [通知の更新](#通知の更新)
  - [通知のキャンセル / 削除](#通知のキャンセル--削除)
  - [スケジュール通知](#スケジュール通知-1)
    - [スケジュールのキャンセル](#スケジュールのキャンセル)
  - [クエリ](#クエリ)
  - [バッジ](#バッジ)
  - [カテゴリとアクション](#カテゴリとアクション)
    - [カテゴリの登録](#カテゴリの登録)
    - [カテゴリを通知に紐づける](#カテゴリを通知に紐づける)
    - [カテゴリの削除](#カテゴリの削除)
    - [アクション受信コールバック](#アクション受信コールバック)
- [Windows](#windows)
  - [NativeToolkit::Notification](#nativetoolkitnotification)
  - [セットアップ](#セットアップ-2)
    - [Package.appxmanifest（パッケージ済みアプリ）](#packageappxmanifestパッケージ済みアプリ)
    - [Manager の作成 パッケージ済みアプリ](#manager-の作成-パッケージ済みアプリ)
    - [Manager の作成 パッケージ無しアプリ](#manager-の作成-パッケージ無しアプリ)
    - [終了](#終了)
  - [初期化 / 設定](#初期化--設定)
    - [通知設定の取得](#通知設定の取得)
    - [通知設定を開く](#通知設定を開く-1)
  - [通知の表示](#通知の表示-1)
    - [基本](#基本)
    - [ボタン付き](#ボタン付き)
    - [画像付き](#画像付き)
    - [入力付き](#入力付き)
    - [進捗バー付き](#進捗バー付き)
    - [有効期限付き](#有効期限付き)
    - [サウンド付き](#サウンド付き)
  - [スケジュール通知](#スケジュール通知-2)
    - [スケジュールのキャンセル](#スケジュールのキャンセル-2)
  - [進捗の更新](#進捗の更新)
  - [バッジ](#バッジ-1)
  - [削除 / クエリ](#削除--クエリ)
    - [全通知の取得](#全通知の取得)
    - [ID 指定削除](#id-指定削除)
    - [タグ指定削除](#タグ指定削除)
    - [全削除](#全削除)
  - [活性化ハンドラー](#活性化ハンドラー)
  - [エラーコード](#エラーコード)
  - [C ABI](#c-abi-1)
    - [ランタイム・マネージャー・活性化](#ランタイムマネージャー活性化)
    - [内容の組み立て・表示・予約](#内容の組み立て表示予約)
    - [進捗・バッジ・OS の設定](#進捗バッジos-の設定)
    - [一覧と削除](#一覧と削除)
- [macOS](#macos)
  - [MacNotificationManager](#macnotificationmanager)
  - [セットアップ](#セットアップ-2)
  - [パーミッション](#パーミッション-2)
    - [権限のリクエスト](#権限のリクエスト)
    - [パーミッション確認](#パーミッション確認)
    - [認証ステータスの取得](#認証ステータスの取得)
    - [通知設定を開く](#通知設定を開く)
    - [通知権限のリセット（macOS 26.3）](#通知権限のリセットmacos-263)
  - [通知の表示](#通知の表示-2)
    - [即時表示](#即時表示)
    - [時間間隔トリガー](#時間間隔トリガー)
    - [カレンダートリガー](#カレンダートリガー)
  - [更新 / キャンセル / 削除](#更新--キャンセル--削除)
    - [IDで更新](#idで更新)
    - [IDでキャンセル](#idでキャンセル)
    - [すべてキャンセル](#すべてキャンセル)
    - [配信済み通知の削除](#配信済み通知の削除)
    - [配信済み通知をすべて削除](#配信済み通知をすべて削除)
  - [スケジュール](#スケジュール)
    - [時間間隔でスケジュール](#時間間隔でスケジュール)
    - [カレンダーでスケジュール](#カレンダーでスケジュール)
    - [IDでキャンセル（スケジュール）](#idでキャンセルスケジュール)
    - [すべてキャンセル（スケジュール）](#すべてキャンセルスケジュール)
  - [クエリ](#クエリ)
    - [スケジュール済みを取得](#スケジュール済みを取得)
    - [配信済みを取得](#配信済みを取得)
  - [バッジ](#バッジ-1)
  - [カテゴリ](#カテゴリ)
    - [カテゴリの登録](#カテゴリの登録-1)
    - [カテゴリの削除](#カテゴリの削除-1)
  - [エラーコード](#エラーコード)

---

## Android

Android 12（API 31）以降のローカル通知です。Android ライブラリ 2.0.0 は、1 つの実装の上に 2 つの公開 API を用意しています。サンプルアプリは Kotlin の API を使います。

| API | 名前 | パッケージ / ヘッダー | AAR |
|---|---|---|---|
| Kotlin の API | `AndroidNotificationManager` | `com.jonghyunkim.nativetoolkit.notification` | `android-native-toolkit-2.0.0.aar` |
| C ABI | `ntk_notification_*` | `<NativeToolkitC/Notification.h>` | `android-native-toolkit-capi-2.0.0.aar` |

C ABI は、この節の最後の [C ABI](#c-abi) で説明します。1.x から移行する場合は、[1.x からの変更点](#1x-からの変更点) と [Android ライブラリを 2.0.0 へ移行する](index.ja.md#android-ライブラリを-200-へ移行する) を読んでください。

### AndroidNotificationManager

- `AndroidNotificationManager.getInstance(context)` はプロセスに 1 つのマネージャーを返します。保持するのは Application Context だけなので、どの Context を渡しても構いません。
- 通知を表示・変更・削除する操作は `Result<Unit>` を返します。例外は進捗フォアグラウンドサービスの呼び出し（`startProgress`、`updateProgress`、`completeProgress`、`stopProgress`）で、これらは `Unit` を返し、Android がサービスを拒否したときに例外を投げます。問い合わせ（`hasPermission`、`areNotificationsEnabled`、`canScheduleExactAlarms`、`isScheduled`、`getActive`）は値をそのまま返します。これらの呼び出しは同期的で、どのスレッドからでも呼べ、メインスレッドを待つことはありません。
- `schedule`、`cancelScheduled`、`cancelAllScheduled` は、保存済みのスケジュールを呼び出し元のスレッドでファイルに書き込みます。メインスレッドで呼ぶと、そこでディスクにアクセスし、別のスレッドの書き込みを待つことがあります。
- `requestPermission` は非同期です。結果はメインスレッドで届き、呼び出しの中で届くことはありません。
- `interactions` と `shown` はイベントハブ（`EventHub`）です。リスナーの追加と削除はメインスレッドでのみ行います（それ以外では `IllegalStateException`）。リスナーはメインスレッドで呼ばれ、リスナーが投げた例外は捕捉されてログに記録されます。
- `NotificationUseCases`、`NotificationPermissionHelper`、`ProgressForegroundNotifications` は 1.x の動作のまま公開されています。このページではマネージャーを使います。

---

### 1.x からの変更点

| 1.x | 2.0.0 |
|---|---|
| パッケージ `android.library.notification.*` | パッケージ `com.jonghyunkim.nativetoolkit.notification.*`。サブパッケージ（`domain.model`、`application.model`、`presentation.*`）は同じです |
| `NotificationUseCases(context)` | `AndroidNotificationManager.getInstance(context)`。操作名は同じです。`isScheduled(context, id)` は `isScheduled(id, tag)` になります |
| `NotificationPermissionHelper(activity).requestPermission { granted -> }` | `manager.requestPermission { result -> }`、または `suspend` 版。Activity は不要です |
| `openNotificationSettings()` / `openExactAlarmSettings()` | `manager.openSettings(NotificationSettingsTarget.NOTIFICATIONS, activity)` / `manager.openSettings(NotificationSettingsTarget.EXACT_ALARM, activity)` |
| `ProgressForegroundNotifications.start(context, command)` ほか | `manager.startProgress(command)` / `updateProgress` / `completeProgress` / `stopProgress` |
| アクションボタンと消去のための独自の `BroadcastReceiver` | `NotificationEventIntents` と `manager.interactions`（[インタラクション](#インタラクション) を参照） |
| マニフェストに書いたライブラリの `<service>` と `<receiver>` | 不要です。AAR が新しい名前で宣言します。1.x のマニュアルで追加した `android.library.*` のエントリーは削除してください |
| 1.x でスケジュールした通知 | アプリが初めて 2.0.0 で動いたときに一度だけ破棄されます（[1.x が保存したスケジュール](#1x-が保存したスケジュール) を参照） |
| 1.x が表示し、まだ画面に残っている通知 | 更新後はタップにもアクションボタンにも反応しません。指す先のレシーバーのクラス名が変わったためです。必要なら表示し直してください |

---

### セットアップ

[マニュアルトップ](index.ja.md#方法-a-maven-リポジトリ推奨) の説明に従って、AAR をアプリに追加します。

#### 権限とコンポーネント

通知に必要なものはすべて AAR が宣言しており、マニフェストのマージによってアプリに加わります。アプリ自身の `AndroidManifest.xml` に追加するものはありません。

- 権限: `POST_NOTIFICATIONS`、`RECEIVE_BOOT_COMPLETED`、`SCHEDULE_EXACT_ALARM`、`USE_FULL_SCREEN_INTENT`、`FOREGROUND_SERVICE`、`FOREGROUND_SERVICE_DATA_SYNC`、`FOREGROUND_SERVICE_SPECIAL_USE`
- コンポーネント: 通知イベントとスケジュール通知のためのレシーバー（再起動後にスケジュールを復元するものを含みます）、通知からアプリを開くための見えない Activity、必要なときに権限ダイアログを載せる透明な Activity、進捗（`dataSync`）と通話（`specialUse`）のフォアグラウンドサービス

アプリで使わない権限を取り除く方法は、[アプリに加わる権限とコンポーネント](index.ja.md#アプリに加わる権限とコンポーネント) を参照してください。

#### 初期化

ライブラリは、アプリの起動時に AndroidX App Startup を通じて自身を初期化します。App Startup を無効にしたアプリは、最初の Activity の `onCreate` で `LibraryRuntime.ensureInitialized(activity)` を自分で呼び、その Activity を渡します。それまでの間、権限のリクエストは `Failed(NOT_INITIALIZED)` で完了します。ただし、権限がすでに許可されている場合や、端末が Android 12L（API 32）以前の場合は、初期化の前でも `Granted` で完了します。そのほかの操作は初期化なしで動きます。

```kotlin
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime

// App Startup を無効にした場合だけ、最初の Activity の onCreate で呼びます。Activity を渡します。
// 渡した Activity がフォアグラウンドの Activity として扱われます。
when (LibraryRuntime.ensureInitialized(this)) {
    LibraryRuntime.InitState.DONE -> Unit        // 初期化済み（以後の呼び出しでも同じ）
    LibraryRuntime.InitState.IN_PROGRESS -> Unit // 別のスレッドが初期化中。後でもう一度呼びます
    LibraryRuntime.InitState.ERROR -> Unit       // この呼び出しは失敗し、行ったことを元に戻しました。再試行するにはもう一度呼びます
}
```

#### マネージャーの取得

```kotlin
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager

val manager = AndroidNotificationManager.getInstance(activity)
```

---

### パーミッション

#### 権限の状態を確認する

```kotlin
// 実行時の権限がない Android 12L（API 32）以前では常に true です。
val permissionGranted: Boolean = manager.hasPermission()

// ユーザーが設定でアプリの通知をオフにしていると false です。
val notificationsEnabled: Boolean = manager.areNotificationsEnabled()

// 正確なアラームが許可されているか（「アラームとリマインダー」）。
val exactAlarmAllowed: Boolean = manager.canScheduleExactAlarms()
```

リクエストの前に説明を表示すべきかどうかの判定には Activity が必要なため、`NotificationPermissionHelper` に残っています。ヘルパーは Activity の `onCreate` で作成してください。ヘルパーは Activity Result のランチャーを登録しますが、Activity がそれを受け付けるのは開始される前だけです。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.presentation.permission.NotificationPermissionHelper

class MainActivity : AppCompatActivity() {

    private lateinit var notificationPermissionHelper: NotificationPermissionHelper

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        notificationPermissionHelper = NotificationPermissionHelper(this)
    }

    fun shouldShowRationale(): Boolean =
        notificationPermissionHelper.shouldShowPermissionRationale()
}
```

#### 権限をリクエストする（コールバック）

ライブラリは、アプリのフォアグラウンドの Activity の上にシステムのダイアログを表示します。呼び出し側は Activity を渡しません。どのスレッドからでも呼べ、リクエスト ID を返します。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult

// リクエストは Activity の再生成を越えて続くため、結果はリクエストした画面の状態ではなく、
// 結果が届いたときに表示されている画面に渡します。
val requestId: Long = manager.requestPermission { result ->
    // メインスレッドで、ちょうど 1 回、requestPermission の中ではなく呼ばれます。
    ScreenResults.notificationStatus.deliver(when (result) {
        PermissionRequestResult.Granted -> "Notification permission granted."
        PermissionRequestResult.Denied ->
            "Notification permission is not granted. Use 'Open Notification Settings' above to enable it."
        is PermissionRequestResult.Canceled -> "Permission request ended: ${result.reason}"
        is PermissionRequestResult.Failed -> "Permission request ended: ${result.reason}"
    })
}
```

| 結果 | 条件 |
|---|---|
| `Granted` | ユーザーが許可した、すでに許可されていた、または端末が Android 12L 以前（後の 2 つではダイアログを表示しません） |
| `Denied` | ユーザーが拒否した、またはシステムが確認せずに拒否した |
| `Canceled(CancelReason.REQUESTED)` | `cancelPermissionRequest` が呼ばれた |
| `Canceled(CancelReason.HOST_DESTROYED)` | ダイアログを表示した Activity が破棄された（構成変更によるものを除く） |
| `Failed(UiUnavailableReason.NOT_FOREGROUND)` | アプリの Activity がフォアグラウンドになかった |
| `Failed(UiUnavailableReason.NOT_INITIALIZED)` | ライブラリが初期化されておらず、権限もまだ許可されていない（[初期化](#初期化) を参照） |
| `Failed(UiUnavailableReason.HOST_START_FAILED)` | ライブラリが透明なホスト Activity を開始できなかった |

`CancelReason` と `UiUnavailableReason` は `com.jonghyunkim.nativetoolkit.common.domain` にあります。

- 別のリクエストがダイアログを待っている間に行ったリクエストは、その回答を共有します。
- リクエストは Activity の構成変更を越えて続くため、リクエストした Activity がなくなった後にコールバックが来ることがあります。リクエストした画面の状態には書き込まないでください。サンプルアプリは、そのときに表示されている画面に結果を渡しています（`ScreenResults.notificationStatus`。表示中の画面が接続する小さな保持オブジェクトです）。

#### 権限をリクエストする（コルーチン）

`suspend` 版は権限が許可されているかどうかを返し、回答がないときは例外を投げます。コルーチンをキャンセルすると、リクエストもキャンセルされます。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.error.PermissionRequestDomainError

scope.launch {
    statusText = try {
        if (manager.requestPermission()) {
            "Notification permission granted (coroutine)."
        } else {
            "Notification permission is not granted (coroutine)."
        }
    } catch (e: PermissionRequestDomainError.Canceled) {
        "Permission request ended: ${e.reason}"
    } catch (e: PermissionRequestDomainError.Unavailable) {
        "Permission request ended: ${e.reason}"
    }
}
```

#### 権限リクエストをキャンセルする

リクエストは、まだ結果が出ていなければ `Canceled(REQUESTED)` で完了します。システムのダイアログが表示されている場合は、ほかのリクエストのために残ります。不明な ID は無視されます。

```kotlin
manager.cancelPermissionRequest(requestId)
```

#### 設定画面を開く

`openSettings` はアプリの設定画面の 1 つを開き、求めた画面が使えないときはアプリの詳細画面を代わりに開きます。開く元の Activity を渡します。`null` の場合は Application Context から新しいタスクで開きます。アプリがフォアグラウンドにあるかどうかは確認しません。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget

// アプリの通知設定。
val opened = manager.openSettings(NotificationSettingsTarget.NOTIFICATIONS, activity) != NotificationSettingsOpenResult.FAILED

// アプリの詳細画面。
manager.openSettings(NotificationSettingsTarget.APP_DETAILS, activity)

// ユーザーが正確なアラームを許可する「アラームとリマインダー」。
manager.openSettings(NotificationSettingsTarget.EXACT_ALARM, activity)
```

| `NotificationSettingsOpenResult` | 意味 |
|---|---|
| `OPENED` | 求めた画面が開いた |
| `OPENED_FALLBACK` | 求めた画面が使えず、代わりにアプリの詳細画面が開いた |
| `FAILED` | どの画面も開けなかった |

---

### チャンネル管理

通知はチャンネルに投稿されます。`show` は、内容のチャンネルがまだ存在しなければ作成します。チャンネルの設定が登録される時点を制御したい場合は、事前にチャンネルを作成してください。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel

val sampleChannel = NotificationChannel(
    id = "native_toolkit_sample",
    name = "Native Toolkit Sample",
    description = "Notification sample channel"
)

// 作成
manager.createChannel(sampleChannel)
    .onFailure { Log.w(TAG, "[ensureChannel] failed: channelId=${sampleChannel.id}", it) }

// 複数まとめて作成
manager.createChannels(listOf(sampleChannel, scheduleSampleChannel))

// 削除
manager.deleteChannel("native_toolkit_sample")
```

- ここでの `NotificationChannel` はライブラリの型（`com.jonghyunkim.nativetoolkit.notification.domain.model`）で、`android.app.NotificationChannel` ではありません。
- `importance` には `android.app.NotificationManager` の定数を指定します。既定値は `IMPORTANCE_DEFAULT`（3）です。`IMPORTANCE_MAX` のようにライブラリが知らない値は `IMPORTANCE_DEFAULT` になります。
- Android は、チャンネルの重要度・サウンド・バイブレーションを最初に作成したときのまま保持し、以後はユーザーが管理します。変更するには新しいチャンネル ID を使ってください。

---

### 基本的な通知操作

#### 表示

通知は `AndroidNotificationCommand` で表します。内容（`NotificationContent`）と、Android 固有のオプション（`AndroidNotificationPlatformOptions`。[プラットフォームオプション](#プラットフォームオプション) を参照）からなります。

```kotlin
import android.app.PendingIntent
import android.content.Intent
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationStyle

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1001,
        title = "Native Toolkit",
        message = "Default style notification sample",
        channel = sampleChannel,
        subText = "Default",
        style = NotificationStyle.Default
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        // 通知をタップすると MainActivity が開きます。
        contentIntent = AndroidPendingIntentRequest(
            intent = Intent(activity, MainActivity::class.java).apply {
                action = "native.toolkit.notification.open"
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            requestCode = 1001,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    )
)

// 権限がないか通知がオフのとき、show は何も投稿せずに成功します。
if (!manager.hasPermission() || !manager.areNotificationsEnabled()) {
    statusText = "Unable to show notifications. Check permissions or notification settings."
    return
}

manager.show(command)
    .onSuccess { statusText = "Displayed Default style notification." }
    .onFailure { throwable ->
        statusText = "Failed to show notification: ${throwable.message ?: throwable::class.java.simpleName}"
    }
```

- `smallIconResId` を指定しない場合、通知は `android.R.drawable.ic_dialog_info` を使います。
- `NotificationContent` のほかのプロパティ（`tag`、`largeIconResId`、`priority`、`autoCancel`、`ongoing`、`showTimestamp`、`timestampMillis`、`soundUri`、`category`、`visibility`、`color`、`number`、`ticker`、`onlyAlertOnce`、`localOnly`、`silent`、`usesChronometer`、`timeoutAfterMillis`、および後述のグループと進捗のプロパティ）は省略できます。

#### 更新

同じ `id` と `tag` のコマンドを渡すと、表示中の通知を置き換えます。

```kotlin
manager.update(updatedCommand)
```

#### キャンセル

```kotlin
// 1 件の通知を削除
manager.cancel(command.content.id, command.content.tag)
    .onSuccess { statusText = "Deleted Default Style notification." }

// アプリのすべての通知を削除
manager.cancelAll()
```

#### アクティブな通知の取得

アプリが現在表示している通知を返します。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.ActiveNotification

val activeList: List<ActiveNotification> = manager.getActive()
activeList.forEach { it.id; it.tag; it.channelId; it.title; it.message; it.isOngoing; it.groupKey }
```

---

### 通知スタイル

`NotificationContent` の `style` プロパティに指定します。以下の値はサンプルアプリのものです。

#### Default

```kotlin
style = NotificationStyle.Default
```

<p align="center">
    <img src="images/android/notification/Example_Default.png" alt="Example_Default" width="400" />
</p>

#### BigText

通知を展開すると長いテキストを表示します。

```kotlin
style = NotificationStyle.BigText(
    bigText = "This is a BigText notification sample from Native Toolkit Example. Expand the notification to verify the full body text rendering.",
    summaryText = "BigText",
    bigContentTitle = "BigText Style"
)
```

<p align="center">
    <img src="images/android/notification/Example_BigText.png" alt="Example_BigText" width="400" />
</p>

#### Inbox

展開すると複数行をリスト形式で表示します。

```kotlin
style = NotificationStyle.Inbox(
    lines = listOf(
        "• Permission status checked",
        "• Channel created successfully",
        "• Immediate notification sent",
        "• Scheduled notification ready"
    ),
    summaryText = "4 sample events",
    bigContentTitle = "Inbox Style"
)
```

<p align="center">
    <img src="images/android/notification/Example_Inbox.png" alt="Example_Inbox" width="400" />
</p>

#### BigPicture

通知を展開すると画像を表示します。画像は `pictureResId` または `pictureUriString` で指定します。

```kotlin
style = NotificationStyle.BigPicture(
    pictureResId = R.mipmap.ic_launcher,
    summaryText = "Launcher image preview",
    bigContentTitle = "BigPicture Style",
    largeIconResId = R.mipmap.ic_launcher_round  // 展開時に表示。hideExpandedLargeIcon = true で非表示
)
```

<p align="center">
    <img src="images/android/notification/Example_BigPicture.png" alt="Example_BigPicture" width="400" />
</p>

#### Messaging

チャットの履歴を会話形式で表示します。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationMessage

val now = System.currentTimeMillis()

style = NotificationStyle.Messaging(
    userDisplayName = "You",
    conversationTitle = "Native Toolkit Example",
    isGroupConversation = true,
    messages = listOf(
        NotificationMessage(
            text = "Can you verify the notification styles?",
            timestampMillis = now - 120_000L,
            senderName = "Alex"
        ),
        NotificationMessage(
            text = "Sure, BigText / Inbox / BigPicture / Messaging are ready.",
            timestampMillis = now - 60_000L,
            senderName = "Jordan"
        ),
        NotificationMessage(
            text = "Confirmed. This is the Messaging sample.",
            timestampMillis = now,
            senderName = "You"         // null = 端末のユーザー
        )
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_Messaging.png" alt="Example_Messaging" width="400" />
</p>

#### Media

メディアプレーヤー形式で表示します。`compactActionIndices` には、折りたたみ表示に出すアクションボタンを指定します（最大 3 個）。

```kotlin
import androidx.core.app.NotificationCompat
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationAction
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents

// メディアボタンはタップをイベントとして伝え、アプリを前面に出します。
fun buildMediaActions(notificationId: Int): List<AndroidNotificationAction> {
    fun action(actionId: String, label: String, iconResId: Int) = AndroidNotificationAction(
        title = label,
        pendingIntent = NotificationEventIntents.action(
            context = activity,
            notificationId = notificationId,
            tag = null,
            actionId = actionId,
            data = mapOf("label" to label),
            launchApp = true
        ),
        iconResId = iconResId
    )
    return listOf(
        action("previous", "Previous", android.R.drawable.ic_media_previous),
        action("play", "Play", android.R.drawable.ic_media_play),
        action("next", "Next", android.R.drawable.ic_media_next)
    )
}

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1006,
        title = "Native Toolkit Player",
        message = "Media style notification sample",
        channel = sampleChannel,
        subText = "Media",
        largeIconResId = R.mipmap.ic_launcher_round,
        category = NotificationCompat.CATEGORY_TRANSPORT,
        priority = NotificationCompat.PRIORITY_LOW,
        ongoing = true,
        autoCancel = false,
        style = NotificationStyle.Media(compactActionIndices = listOf(0, 1, 2))
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        // buildActivityPendingIntentRequest: プラットフォームオプションを参照
        contentIntent = buildActivityPendingIntentRequest(2000, "native.toolkit.media.open"),
        actions = buildMediaActions(1006)
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_Media.png" alt="Example_Media" width="400" />
</p>

`NotificationStyle.Call`（通話通知）は [Call Style FGS](#call-style-fgs通話通知) で説明します。

---

### プラットフォームオプション

`AndroidNotificationPlatformOptions` は Android だけにあるものを保持します。各 `PendingIntent` は `AndroidPendingIntentRequest` で記述し、ライブラリが通知を投稿するときに `PendingIntent` に変換します。

| プロパティ | 型 | 用途 |
|---|---|---|
| `contentIntent` | `AndroidPendingIntentRequest?` | 通知本体がタップされたときに発行 |
| `deleteIntent` | `AndroidPendingIntentRequest?` | 通知が消去されたときに発行 |
| `fullScreenIntent` | `AndroidPendingIntentRequest?` | フルスクリーン表示（[FullScreenIntent](#fullscreenintentフルスクリーン表示) を参照） |
| `actions` | `List<AndroidNotificationAction>` | アクションボタン |
| `largeIconBitmap` | `Bitmap?` | ビットマップで指定するラージアイコン。`NotificationContent.largeIconResId` と併用しないでください |
| `callStyleOptions` | `AndroidNotificationCallPlatformOptions?` | `NotificationStyle.Call` の通知の `answerIntent`、`declineIntent`、`hangUpIntent` |
| `customViewOptions` | `AndroidNotificationCustomViewPlatformOptions?` | カスタムビューの内容（[カスタムビュースタイル](#カスタムビュースタイル) を参照） |

`AndroidPendingIntentRequest(intent, requestCode, type, flags, mutable)` は、包む `Intent`、リクエストコード、対象（既定は `AndroidPendingIntentType.ACTIVITY`。ほかに `BROADCAST`、`SERVICE`、`FOREGROUND_SERVICE`）、追加の `PendingIntent` フラグ、`PendingIntent` を変更可能にするかどうか（既定は `false`）を受け取ります。サンプルアプリは、Activity 向けのリクエストをヘルパーで作成しています。

```kotlin
import android.app.PendingIntent
import android.content.Intent
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest

fun buildActivityPendingIntentRequest(
    targetActivityClass: Class<*>,
    requestCode: Int,
    action: String
): AndroidPendingIntentRequest {
    return AndroidPendingIntentRequest(
        intent = Intent(activity, targetActivityClass).apply {
            this.action = action
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
        },
        requestCode = requestCode,
        flags = PendingIntent.FLAG_UPDATE_CURRENT
    )
}

fun buildActivityPendingIntentRequest(requestCode: Int, action: String): AndroidPendingIntentRequest =
    buildActivityPendingIntentRequest(MainActivity::class.java, requestCode, action)
```

本体のタップ、アクションボタン、消去をコードで受け取りたい場合は、代わりに `NotificationEventIntents` が作成するリクエストを使ってください。ライブラリがそれらをイベントとして届けるため、独自のレシーバーは不要です（[インタラクション](#インタラクション) を参照）。

`AndroidNotificationAction` は `title` と `pendingIntent` を持ち、省略可能な `iconResId`、`allowGeneratedReplies`、`semanticAction`（`NotificationCompat.Action` の定数）、`contextual`、`showsUserInterface` を持ちます。

`NotificationResourceResolver(context)`（`com.jonghyunkim.nativetoolkit.notification.presentation.resource`）は、アイコンやレイアウトの名前をデータで持つアプリ向けに、リソース名を ID に変換します。`resolve(name, type)` は名前を `type`（`drawable`、`mipmap`、`layout`、`id`。`null` の場合は `drawable`、次に `mipmap`）として探し、`defaultSmallIcon()` はアプリのアイコンを返します。

---

### カスタムビュースタイル

独自のレイアウトで通知を表示します。`RemoteViewAction` でビューの内容とクリック対象を設定します。

#### DecoratedCustomView

```kotlin
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.RemoteViewAction
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationCustomViewStyleData

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1007,
        title = "Native Toolkit",
        message = "Decorated custom view notification sample",
        channel = sampleChannel,
        subText = "DecoratedCustomView",
        style = NotificationStyle.DecoratedCustomView(
            customView = NotificationCustomViewStyleData(
                layoutResId = R.layout.notification_custom_style_sample,             // 折りたたみ時のビュー
                bigLayoutResId = R.layout.notification_custom_style_sample_expanded  // 展開時のビュー（省略可）
            )
        )
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        contentIntent = buildActivityPendingIntentRequest(2100, "native.toolkit.custom.open"),
        customViewOptions = AndroidNotificationCustomViewPlatformOptions(
            viewActions = listOf(
                // テキストを設定
                RemoteViewAction.SetText(R.id.notification_title, "Native Toolkit"),
                RemoteViewAction.SetText(R.id.notification_message, "Decorated custom view sample"),
                // 画像を設定
                RemoteViewAction.SetImage(R.id.notification_icon, R.mipmap.ic_launcher_round),
                // ビューのクリックは、このアクション ID の ACTION イベントとして届きます
                RemoteViewAction.SetClickIntent(
                    viewId = R.id.notification_btn_dismiss,
                    pendingIntent = NotificationEventIntents.action(
                        context = activity,
                        notificationId = 1007,
                        tag = null,
                        actionId = "custom_view_dismiss",
                        data = mapOf("label" to "Dismiss")
                    )
                )
            )
        )
    )
)

manager.show(command)
```

<p align="center">
    <img src="images/android/notification/Example_DecoratedCustomView.png" alt="Example_DecoratedCustomView" width="400" />
</p>

> **注意:** `RemoteViews` の制約により、クリックできる要素には `Button` ではなく `LinearLayout` + `TextView` を使ってください。クリックイベントは `setOnClickPendingIntent` で設定されます。

#### DecoratedMediaCustomView

Media スタイルとカスタムビューを組み合わせます。

```kotlin
style = NotificationStyle.DecoratedMediaCustomView(
    customView = NotificationCustomViewStyleData(
        layoutResId = R.layout.notification_media_custom_style_sample,
        bigLayoutResId = R.layout.notification_media_custom_style_sample_expanded
    ),
    compactActionIndices = listOf(0, 1, 2)
)
```

<p align="center">
    <img src="images/android/notification/Example_DecoratedMediaCustomView.png" alt="Example_DecoratedMediaCustomView" width="400" />
</p>

`customViewOptions` は `DecoratedCustomView` と同じように働き、メディアボタンは [Media](#media) と同じく `actions` に指定します。

---

### グループ通知

複数の通知をまとめて表示します。

```kotlin
val GROUP_SAMPLE_KEY = "native.toolkit.grouping.sample"

// 子通知 1
val child1 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1101,
        title = "Native Toolkit Group",
        message = "Group child notification #1",
        channel = interactionGroupingSampleChannel,
        groupKey = GROUP_SAMPLE_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "01"
    )
)

// 子通知 2
val child2 = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1102,
        title = "Native Toolkit Group",
        message = "Group child notification #2",
        channel = interactionGroupingSampleChannel,
        groupKey = GROUP_SAMPLE_KEY,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "02"
    )
)

// サマリー通知（グループのヘッダー）
val summary = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1100,
        title = "Native Toolkit Group Summary",
        message = "2 notifications grouped together",
        channel = interactionGroupingSampleChannel,
        groupKey = GROUP_SAMPLE_KEY,
        isGroupSummary = true,
        groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
        sortKey = "00",
        style = NotificationStyle.Inbox(
            lines = listOf("Group child notification #1", "Group child notification #2"),
            summaryText = "2 grouped notifications",
            bigContentTitle = "Grouping / Summary"
        )
    )
)

runCatching {
    listOf(child1, child2, summary).forEach { manager.show(it).getOrThrow() }
}
```

<p align="center">
    <img src="images/android/notification/Example_Group.png" alt="Example_Group" width="400" />
</p>

> **ヒント:** `groupAlertBehavior = GROUP_ALERT_SUMMARY` を設定すると、サウンドとバイブレーションはサマリーだけで鳴り、子通知は鳴りません。

---

### インタラクション

2.0.0 では、ライブラリが本体のタップ、アクションボタン、消去をイベントとしてコードに届けます。それぞれの `AndroidPendingIntentRequest` は `NotificationEventIntents` が作成します。それを `AndroidNotificationPlatformOptions` に指定し、`manager.interactions` でリッスンします。独自の `BroadcastReceiver` は不要で、これらのリクエストはスケジュール通知でも動きます。

| 関数 | 指定先 | `launchApp` の既定値 |
|---|---|---|
| `NotificationEventIntents.bodyTap(context, notificationId, tag, data, launchApp)` | `contentIntent` | `true` |
| `NotificationEventIntents.action(context, notificationId, tag, actionId, data, launchApp)` | `AndroidNotificationAction.pendingIntent`、`RemoteViewAction.SetClickIntent` | `false` |
| `NotificationEventIntents.dismiss(context, notificationId, tag, data)` | `deleteIntent` | - |
| `NotificationEventIntents.fullScreenLaunch(context, notificationId, tag)` | `fullScreenIntent` | - |

- `data` は、イベントと一緒に届く文字列のマップです。
- `launchApp = true` の場合、タップでアプリも開きます。ライブラリは独自の見えない Activity を経由し、イベントを伝えてから、ランチャーと同じようにアプリの起動 Activity を開始します（実行中のアプリは前面に出ます）。通知からのブロードキャストで Activity を開始できない Android 12 以降でも、この方法で動きます。`false` の場合、イベントはブロードキャストで届き、アプリはそのままです。
- `fullScreenLaunch` は、アプリの起動 Activity をフルスクリーンインテントとして開きます。起動 Activity がないアプリでは `null` を返します。イベントは伝えません。
- 各リクエストはデータ URI で区別され、リクエストコード 0 を使います。そのため、2 つの通知が同じ `PendingIntent` を共有することはありません。

#### イベントの受け取り

`manager.interactions` は `NotificationInteraction` を届けます。`kind`（`BODY_TAP`、`ACTION`、`DISMISS`）、`notificationId`、`tag`、`actionId`（`ACTION` のとき）、`data` を持ちます。`manager.shown` は、スケジュール通知が発火したときに `NotificationShown`（`notificationId`、`tag`、`channelId`）を届けます。

サンプルアプリは、`MainActivity.onCreate` でリスナーを登録し、`onDestroy` で削除しています。

```kotlin
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction

class MainActivity : AppCompatActivity() {

    private var eventRegistrations: List<EventHub.Registration> = emptyList()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val notifications = AndroidNotificationManager.getInstance(this)
        // リスナーがない間にライブラリが保持したイベントは、この呼び出しの中で届きます。
        eventRegistrations = listOf(
            notifications.interactions.addListener { event, _ ->
                val label = event.data["label"] ?: "Notification"
                when (event.kind) {
                    NotificationInteraction.Kind.BODY_TAP -> { /* event.notificationId, event.tag */ }
                    NotificationInteraction.Kind.ACTION -> { /* event.actionId, label */ }
                    NotificationInteraction.Kind.DISMISS -> { /* "$label dismissed (deleteIntent)" */ }
                }
            },
            notifications.shown.addListener { event, _ ->
                // スケジュール通知が発火しました: event.notificationId, event.tag, event.channelId
            }
        )
    }

    override fun onDestroy() {
        eventRegistrations.forEach { it.remove() }
        eventRegistrations = emptyList()
        super.onDestroy()
    }
}
```

- `interactions` は、リスナーがない間、最大 32 件のイベントを保持し（古いものから捨てます）、次に追加されたリスナーへ `addListener` の中で、届いた順に渡します。そのため、アプリを起動したタップは、最初の Activity の `onCreate` で追加したリスナーに届きます。`shown` は何も保持しません。
- `addListener` と `Registration.remove` はメインスレッド専用です。リスナーは自分の `Registration` を 2 番目の引数として受け取り、その中で自分を削除できます。
- `NotificationInteraction.toString()` は `data` の値を伏せます。

#### 本体タップイベント

```kotlin
val EVENT_SAMPLE_NOTIFICATION_ID = 1120

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = EVENT_SAMPLE_NOTIFICATION_ID,
        title = "Native Toolkit Event",
        message = "Tap this notification to send a body tap event.",
        channel = interactionGroupingSampleChannel,
        subText = "Interaction / Body Tap Event"
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        // アプリを開き、BODY_TAP を伝えます。
        contentIntent = NotificationEventIntents.bodyTap(
            context = activity,
            notificationId = EVENT_SAMPLE_NOTIFICATION_ID,
            tag = null,
            launchApp = true
        )
    )
)
```

#### アクションボタン

```kotlin
val ACTION_SAMPLE_NOTIFICATION_ID = 1112

fun buildAcceptDeclineActions(): List<AndroidNotificationAction> {
    fun action(actionId: String, label: String, iconResId: Int) = AndroidNotificationAction(
        title = label,
        pendingIntent = NotificationEventIntents.action(
            context = activity,
            notificationId = ACTION_SAMPLE_NOTIFICATION_ID,
            tag = null,
            actionId = actionId,
            data = mapOf("label" to label),
            launchApp = false
        ),
        iconResId = iconResId
    )
    return listOf(
        action("accept", "Accept", android.R.drawable.ic_menu_call),
        action("decline", "Decline", android.R.drawable.ic_menu_close_clear_cancel)
    )
}

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = ACTION_SAMPLE_NOTIFICATION_ID,
        title = "Native Toolkit Action Sample",
        message = "Use Accept / Decline action buttons",
        channel = interactionGroupingSampleChannel,
        autoCancel = false
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        contentIntent = buildActivityPendingIntentRequest(5130, "native.toolkit.notification.grouping.open"),
        actions = buildAcceptDeclineActions()
    )
)

// interactions のリスナーの中で:
// NotificationInteraction.Kind.ACTION -> "Action button pressed: ${event.data["label"]} (id=${event.actionId})"
```

<p align="center">
    <img src="images/android/notification/Example_ActionButtons.png" alt="Example_ActionButtons" width="400" />
</p>

#### DeleteIntent（削除イベント）

ユーザーが通知をスワイプして消すと、`DISMISS` として伝えられます。

```kotlin
platformOptions = AndroidNotificationPlatformOptions(
    contentIntent = buildActivityPendingIntentRequest(5110, "native.toolkit.notification.grouping.open"),
    deleteIntent = NotificationEventIntents.dismiss(
        context = activity,
        notificationId = 1110,
        tag = null,
        data = mapOf("label" to "DeleteIntent Sample")
    )
)
```

#### FullScreenIntent（フルスクリーン表示）

端末がロック中や画面オフのときに、全画面の Activity を起動します（アラーム、着信など）。サンプルアプリは独自の Activity を開きます。

```kotlin
// 高優先度のチャンネルと適切な category が必要です
val fullScreenSampleChannel = NotificationChannel(
    id = "native_toolkit_fullscreen_sample",
    name = "Native Toolkit FullScreen Sample",
    importance = NotificationManager.IMPORTANCE_HIGH,
    description = "Reference fullScreenIntent notification sample channel"
)

val command = AndroidNotificationCommand(
    content = NotificationContent(
        id = 1111,
        title = "Native Toolkit Alarm Sample",
        message = "Reference fullScreenIntent notification sample",
        channel = fullScreenSampleChannel,
        category = NotificationCompat.CATEGORY_ALARM,
        priority = NotificationCompat.PRIORITY_HIGH
    ),
    platformOptions = AndroidNotificationPlatformOptions(
        contentIntent = buildActivityPendingIntentRequest(5120, "native.toolkit.notification.grouping.open"),
        fullScreenIntent = buildActivityPendingIntentRequest(
            targetActivityClass = NotificationFullScreenSampleActivity::class.java,
            requestCode = 5121,
            action = "native.toolkit.notification.fullscreen.open"
        )
    )
)
```

<p align="center">
    <img src="images/android/notification/Example_FullScreenIntent.png" alt="Example_FullScreenIntent" width="400" />
</p>

代わりにアプリの起動 Activity を開くには、`NotificationEventIntents.fullScreenLaunch(activity, 1111, null)` を渡します。

> **注意:** 端末の状態や Android のポリシーによっては、フルスクリーンではなく heads-up 通知として表示される場合があります。

---

### 進捗通知

ダウンロードや時間のかかる処理の進捗をプログレスバーで表示します。同じ `id` で再度表示するとバーが更新されます。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationProgress

fun buildProgressCommand(progressValue: Int, max: Int = 100): AndroidNotificationCommand {
    val safeProgress = progressValue.coerceIn(0, max)
    val isComplete = safeProgress >= max
    return AndroidNotificationCommand(
        content = NotificationContent(
            id = 1009,
            title = "Native Toolkit Download",
            message = if (isComplete) "Download completed" else "Downloading sample asset... $safeProgress%",
            channel = sampleChannel,
            subText = "Progress",
            ongoing = !isComplete,
            autoCancel = isComplete,
            progress = NotificationProgress(max = max, current = safeProgress, indeterminate = false)
        )
    )
}

manager.show(buildProgressCommand(progressValue = 50))

// 不確定のプログレスバー（max と current は無視されます）
val indeterminate = NotificationProgress(max = 0, current = 0, indeterminate = true)
```

<p align="center">
    <img src="images/android/notification/Example_Progress.png" alt="Example_Progress" width="400" />
</p>

---

### フォアグラウンドサービス通知

以下の 2 つのサービスは AAR が宣言しています。マニフェストに追加するものはありません。

#### Progress FGS（長時間バックグラウンド処理）

マネージャーは、`dataSync` のフォアグラウンドサービスに結び付いた進捗通知を表示します。これらの呼び出しは何も返さず、Android がサービスの開始や到達を拒否したとき（たとえばバックグラウンドから開始したとき）に例外を投げるため、`runCatching` などで囲んでください。

```kotlin
val progressForegroundSampleChannel = NotificationChannel(
    id = "native_toolkit_progress_fgs",
    name = "Native Toolkit Progress FGS",
    importance = NotificationManager.IMPORTANCE_LOW,
    description = "Foreground service progress sample channel"
)

// フォアグラウンドサービスを開始（通知の表示も兼ねます）
runCatching { manager.startProgress(buildProgressForegroundCommand(progressValue = 10)) }
    .onFailure { throwable -> statusText = "Failed to start progress foreground service: ${throwable.message}" }

// 進捗を更新
runCatching { manager.updateProgress(buildProgressForegroundCommand(progressValue = 50)) }

// 完了（サービスを停止し、通常の通知を残します）
runCatching { manager.completeProgress(buildProgressForegroundCompleteCommand()) }

// 強制停止（通知も削除します）
runCatching { manager.stopProgress() }
```

`buildProgressForegroundCommand` は、上の `buildProgressCommand` と同じようなコマンドを `id = 1011`、`channel = progressForegroundSampleChannel`、`ongoing = true`、`autoCancel = false` で作成します。`buildProgressForegroundCompleteCommand` は同じ `id` に `ongoing = false`、`autoCancel = true`、`BigText` スタイルを使います。

<p align="center">
    <img src="images/android/notification/Example_ProgressForeground.png" alt="Example_ProgressForeground" width="400" />
</p>

#### Call Style FGS（通話通知）

`CallStyleForegroundService` は、`specialUse` のフォアグラウンドサービスから `CallStyle` の通知（着信、通話中、スクリーニング）を表示します。表示するのは `CallStyleNotificationFactory` の固定のサンプル通話で、デモ用です。実際の通話アプリは `phoneCall` のフォアグラウンドサービスを使い、Android が通話アプリに求める要件を満たす必要があります。

```kotlin
import androidx.core.content.ContextCompat
import com.jonghyunkim.nativetoolkit.notification.presentation.call.CallStyleForegroundService
import com.jonghyunkim.nativetoolkit.notification.presentation.call.CallStyleNotificationFactory

// 通話通知が使うチャンネル
manager.createChannel(CallStyleNotificationFactory.createChannel())

// 着信通知を開始
ContextCompat.startForegroundService(activity, CallStyleForegroundService.createIncomingStartIntent(activity))

// 通話中の通知に切り替え
ContextCompat.startForegroundService(activity, CallStyleForegroundService.createOngoingStartIntent(activity))

// スクリーニング中の通知に切り替え
ContextCompat.startForegroundService(activity, CallStyleForegroundService.createScreeningStartIntent(activity))

// 停止
activity.startService(CallStyleForegroundService.createStopIntent(activity))
```

<p align="center">
    <img src="images/android/notification/Example_CallStyle.png" alt="Example_CallStyle" width="400" />
</p>

独自の通話通知を投稿するには、`style = NotificationStyle.Call(callType, person, isVideo, verificationText)` を設定し、ボタンを `callStyleOptions` に指定します。`INCOMING` では `answerIntent` と `declineIntent`、`ONGOING` では `hangUpIntent`、`SCREENING` では `hangUpIntent` と `answerIntent` です。

---

### スケジュール通知

指定した時刻に通知を表示します。

```kotlin
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule

manager.createChannel(scheduleSampleChannel)
if (!manager.hasPermission() || !manager.areNotificationsEnabled()) {
    statusText = "Unable to schedule notifications. Check permissions or notification settings."
} else if (!manager.canScheduleExactAlarms()) {
    statusText = "Exact alarms are not allowed. Use 'Open Exact Alarm Settings' above to enable them."
} else {
    val triggerAt = System.currentTimeMillis() + 15_000L // 今から 15 秒後
    manager.schedule(
        buildScheduledCommand(),
        NotificationSchedule(triggerAtMillis = triggerAt)
    ).onSuccess {
        val command = buildScheduledCommand()
        val scheduled = manager.isScheduled(command.content.id, command.content.tag)
        statusText = "Scheduled a high-priority notification for 15 seconds later. (isScheduled=$scheduled)"
    }.onFailure { throwable ->
        statusText = "Failed to schedule notification: ${throwable.message ?: throwable::class.java.simpleName}"
    }
}
```

<p align="center">
    <img src="images/android/notification/Example_Scheduled.png" alt="Example_Scheduled" width="400" />
</p>

| `NotificationSchedule` のプロパティ | 既定値 | 意味 |
|---|---|---|
| `triggerAtMillis` | - | Unix 時間（ミリ秒）。0 より大きい値が必要です（それ以外では `IllegalArgumentException`） |
| `exact` | `true` | 正確なアラーム。正確なアラームの権限がない場合、ライブラリはエラーにせず、不正確なアラームを代わりに使います |
| `allowWhileIdle` | `true` | Doze モード中も発火します |
| `persistAcrossBoot` | `true` | 保存され、再起動やアプリの更新の後に復元されます |
| `alarmType` | `0`（`AlarmManager.RTC_WAKEUP`） | `AlarmManager` のアラームの種類 |

- すでに過ぎた時刻を指定すると、アラームを使わずにすぐ通知を表示します。この場合 `manager.shown` は伝えられません。
- `manager.shown` はアラームが発火したときに伝えられます。権限はその時点で確認されます。権限がない場合は何も表示されませんが、`manager.shown` は伝えられます。
- 保存されたスケジュールは、コマンドを JSON としてアプリのファイル（`files/ntk/notification_schedules.json`。自動バックアップの対象です）に保持します。その中の `Intent`（たとえば `contentIntent` の中のもの）は URI として保存されます。そのため、再起動、アプリの再インストール、端末の移行の後にスケジュールを復元すると、文字列やプリミティブ値以外の extras（`Parcelable`、配列、`Bundle`、`Uri` など）と `ClipData` は失われています。

#### スケジュールのキャンセル

```kotlin
// 1 件のスケジュールをキャンセルし、すでに発火していた場合に備えて通知も削除します。
manager.cancelScheduled(command.content.id, command.content.tag)
    .mapCatching { manager.cancel(command.content.id, command.content.tag).getOrThrow() }

// 保存されたすべてのスケジュールをキャンセル
manager.cancelAllScheduled()
```

`cancelAllScheduled` がキャンセルするのは、保存されたスケジュール（`persistAcrossBoot = true`）だけです。それ以外は ID を指定してキャンセルしてください。

#### スケジュール済み確認

```kotlin
val isScheduled: Boolean = manager.isScheduled(command.content.id, command.content.tag)
```

`isScheduled` が見るのは、保存されたスケジュール（`persistAcrossBoot = true`）だけです。

#### 端末再起動後の復元

ライブラリは、再起動の後（`BOOT_COMPLETED`、`LOCKED_BOOT_COMPLETED`）とアプリの更新の後（`MY_PACKAGE_REPLACED`）に、保存されたスケジュールを自動で復元します。レシーバーは AAR に含まれています。ほかのタイミングで同じことを行うには、次を呼びます。

```kotlin
manager.restoreScheduled()
```

#### 1.x が保存したスケジュール

2.0.0 はスケジュールを新しい形式で保存し、1.x が保存したものは読めません。アプリが初めて 2.0.0 で動いたとき、ライブラリは 1.x が保存したスケジュールのアラームをキャンセルし、それらを一度だけ削除します。更新の後に、スケジュールし直してください。`persistAcrossBoot = false` で作成した 1.x のスケジュールは見つけられないため Android に残りますが、発火しても何も表示しません。

1.x が表示し、更新の後も画面に残っている通知は、タップにもアクションボタンにも反応しません。指す先のレシーバーのクラス名が変わったためです。まだ必要であれば、2.0.0 で表示し直してください。

---

### C ABI

- C から、そして C のライブラリを呼べる言語（C#、Rust、Dart、Go など）から同じ通知を使うための API です。関数は `android-native-toolkit-capi-2.0.0.aar` の `libntk.so` にあり、アプリには `android-native-toolkit-2.0.0.aar` も必要です。要件を含むセットアップは、マニュアルトップの [C ABI](index.ja.md#c-abi) にあります。
- `libntk.so` は 64 ビットの ABI（`arm64-v8a`、`x86_64`）にだけあります。32 ビットとしてインストールされたアプリでは読み込みに失敗しますが、アプリは動き続けます。
- CMake を使う C と C++ は、Prefab を通じてヘッダーとライブラリを得ます。APK と CMake のビルドの両方を 64 ビットの ABI に限定してください。Android Gradle Plugin は CMake がビルドするすべての ABI について Prefab パッケージを確認し、32 ビットの ABI では `CXX1210` で停止します（マニュアルトップの [C ABI](index.ja.md#c-abi) を参照）。

```kotlin
android {
    buildFeatures { prefab = true }
    defaultConfig {
        ndk { abiFilters += listOf("arm64-v8a", "x86_64") }
        externalNativeBuild {
            cmake { abiFilters("arm64-v8a", "x86_64") }
        }
    }
}
```

```cmake
find_package(ntk REQUIRED CONFIG)
target_link_libraries(your_library PRIVATE ntk::ntk)
```

- **スレッド。** すべての関数はどのスレッドからでも呼べ、メインスレッドを待つものはありません。完了、イベント、受け付けられた登録の `release` は Android のメインスレッドで呼ばれ、それらを登録した呼び出しの中で呼ばれることはありません。メインスレッドから呼んだ場合、完了は関数が戻った後に来ます。別のスレッドから呼んだ場合は関数が戻る前に来ることがあるため、完了は `user_data` で対応付けてください。
- **`release`。** 登録は `user_data` と `release` コールバックを伴い、`release` はちょうど 1 回呼ばれます。入口で拒否された呼び出し（不正な引数、未初期化）はエラーを返し、完了を呼ばず、戻る前に呼び出し元のスレッドで `release` を呼びます。プロセスが終了したときは、完了も `release` も呼ばれません。
- **ハンドル。** 内容とチャンネルのビルダーはライブラリの既定値から始まり、セッターが受け取ったものをコピーします。初期化の前でも使え、スレッドセーフではありません。`ntk_notification_content_free` と `ntk_notification_channel_free` で解放します。コールバックに渡されるイベントのハンドルは受け取った側のものです。コールバックが戻った後も、受け取った側が解放するまで有効です。
- **リクエスト ID** は `uint64_t` で、再利用されません。完了後や不明な ID でのキャンセルは何もしません。
- **初期化。** App Startup がアプリの起動時に C ABI を初期化します。App Startup を無効にしたアプリや、既定のプロセス以外のプロセスから呼ぶアプリは、先に `ntk_android_init` を呼びます。初期化の前、操作は `NTK_NOTIFICATION_ERROR_NOT_INITIALIZED` を返します（引数のエラーが先に報告されます。キャンセルは `NONE` を返します）。
- **フォアグラウンド。** `ntk_notification_request_permission`（権限がまだ許可されていない場合）と `ntk_notification_open_settings_async` は、アプリがフォアグラウンドにある必要があります。バックグラウンドから呼ぶと受け付けられ、`NTK_NOTIFICATION_ERROR_NOT_FOREGROUND` で完了します。戻り値が示すのは、リクエストが受け付けられたかどうかだけです。
- **コールバックは例外を投げてはいけません。** コールバックから抜ける C++ の例外、C# の例外、Rust の panic はプロセスを終了させます。
- **黙った補正はしません。** Kotlin の API が値を調整する箇所では、C ABI は `NTK_NOTIFICATION_ERROR_INVALID_PARAMETER` を返します。チャンネルの重要度は 0〜4、ロック画面での表示と `visibility` は -1〜1、`priority` は -2〜2、`group_alert_behavior` は 0〜2、タイムスタンプとタイムアウトは 0 以上、確定のプログレスバーは `0 <= current <= max`、`alarm_type` は 0（`RTC_WAKEUP`）か 1（`RTC`）です。文字列は NUL 終端の UTF-8 で、セッターに `NULL` を渡すとその項目は既定値に戻ります。
- **権限の確認。** Kotlin の API が何もせずに成功する箇所では、C ABI は呼び出しの時点で先に確認します。`show`、`update`、時刻が過ぎたスケジュールは、権限がないか通知がオフのときに `PERMISSION_DENIED` を返し、未来の時刻への正確なスケジュールは、正確なアラームの権限がないときに `EXACT_ALARM_NOT_ALLOWED` を返します。確認の後の変化は捉えません。確認と呼び出しの間に通知がオフになった場合や、数ミリ秒先のスケジュールが作成時にはすでに過ぎていた場合は、`NONE` を返して何も表示しないことがあります。
- **リソース名。** アイコン、BigPicture の画像、レイアウト、ビュー ID は名前で指定し、内容が `ntk_notification_show`、`_update`、`_schedule`、進捗の関数に渡されたときに探されます（アイコンと画像は `drawable`、次に `mipmap`、レイアウトは `layout`、ビュー ID は `id` として）。見つからない名前があると、その関数は `RESOURCE_NOT_FOUND` を返します。セッターは名前を探しません。リソースの縮小は名前からしか参照されないリソースを取り除くため、たとえば `res/raw/keep.xml` で残してください。

```xml
<resources xmlns:tools="http://schemas.android.com/tools"
    tools:keep="@drawable/ic_notification,@layout/notification_custom_style_sample" />
```

#### 初期化・権限・設定

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Android.h>
#include <NativeToolkitC/Notification.h>

/* App Startup を無効にしたアプリか、別のプロセスから呼ぶアプリだけが使います。env は
   呼び出し元のスレッドの JNIEnv*、context は任意の Context です。Activity があれば Activity を渡します。 */
static void initialize_without_startup(void* env, void* context)
{
    ntk_android_error result = ntk_android_init(env, context);
    if (result == NTK_ANDROID_ERROR_IN_PROGRESS || result == NTK_ANDROID_ERROR_JNI_FAILURE) {
        /* 待つことはありません。後でもう一度呼びます。CLASS_NOT_FOUND は再試行しても解決しません。 */
    }
}

static void NTK_CALL on_permission(void* user_data, uint64_t request_id, ntk_notification_error error,
                                   uint32_t system_code, ntk_notification_permission_result result)
{
    /* Android のメインスレッドで、受け付けられたリクエストごとに 1 回呼ばれます。system_code は常に 0 です。 */
    (void)user_data; (void)request_id; (void)system_code;
    if (error == NTK_NOTIFICATION_ERROR_NONE && result == NTK_NOTIFICATION_PERMISSION_RESULT_GRANTED) {
        /* 許可された、すでに許可されていた、または不要（Android 12L 以前）。 */
    } else if (error == NTK_NOTIFICATION_ERROR_NONE && result == NTK_NOTIFICATION_PERMISSION_RESULT_DENIED) {
        /* 拒否された。 */
    } else if (error == NTK_NOTIFICATION_ERROR_NOT_FOREGROUND) {
        /* アプリがバックグラウンドにある間にリクエストした。 */
    } else if (error == NTK_NOTIFICATION_ERROR_CANCELED || error == NTK_NOTIFICATION_ERROR_CANCELED_BY_SYSTEM) {
        /* 呼び出し側がキャンセルした、またはダイアログを表示していた Activity が破棄された。 */
    }
}

static void NTK_CALL on_settings(void* user_data, ntk_notification_error error, uint32_t system_code,
                                 ntk_notification_settings_result result)
{
    (void)user_data; (void)system_code;
    if (error == NTK_NOTIFICATION_ERROR_NONE && result == NTK_NOTIFICATION_SETTINGS_RESULT_OPENED_FALLBACK) {
        /* 求めた画面が使えず、アプリの詳細画面が開いた。 */
    } else if (error == NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED) {
        /* どの画面も開けなかった。 */
    }
}

static void NTK_CALL release_user_data(void* user_data)
{
    /* 登録した呼び出しが失敗したときも含め、登録ごとにちょうど 1 回呼ばれます。 */
    (void)user_data;
}

/* ヘッダーのバージョンとライブラリのバージョン。 */
if (ntk_version() != NTK_VERSION) {
    return;
}
if (!ntk_android_is_initialized()) {
    return;   /* App Startup がまだ動いていないか、initialize_without_startup が必要です。 */
}

/* 権限の状態。 */
int32_t granted = 0;
int32_t enabled = 0;
int32_t exact_alarms = 0;
ntk_notification_error error = ntk_notification_has_permission(&granted);
error = ntk_notification_are_enabled(&enabled);
error = ntk_notification_can_schedule_exact_alarms(&exact_alarms);
uint32_t system_code = ntk_last_system_code();   /* Android では常に 0 */

/* 権限のリクエスト。 */
uint64_t request_id = 0;
error = ntk_notification_request_permission(&on_permission, NULL, &release_user_data, &request_id);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    /* 入口で拒否されました。on_permission は呼ばれず、release_user_data はすでに呼ばれています。 */
}

/* 結果が不要になった場合。まだ完了していなければ、リクエストは CANCELED で完了します。 */
error = ntk_notification_cancel_permission_request(request_id);

/* 設定画面: NOTIFICATIONS、APP_DETAILS、EXACT_ALARM のいずれか。 */
error = ntk_notification_open_settings_async(NTK_NOTIFICATION_SETTINGS_TARGET_EXACT_ALARM,
                                             &on_settings, NULL, &release_user_data);
```

#### チャンネルと内容のビルダー

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

/* チャンネル: id、名前、重要度（0〜4。3 は IMPORTANCE_DEFAULT）。 */
ntk_notification_channel* channel = NULL;
if (ntk_notification_channel_create("native_toolkit_sample", "Native Toolkit Sample", 3, &channel)
        != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}
ntk_notification_channel_set_description(channel, "Notification sample channel");
ntk_notification_channel_set_show_badge(channel, 1);
ntk_notification_channel_set_enable_lights(channel, 1);
ntk_notification_channel_set_light_color(channel, 0xFF2196F3u);   /* ARGB */
ntk_notification_channel_set_enable_vibration(channel, 1);
const int64_t pattern[] = { 0, 200, 100, 200 };                    /* ミリ秒 */
ntk_notification_channel_set_vibration_pattern(channel, pattern, 4);
ntk_notification_channel_set_sound(channel, NULL);                 /* NULL: 既定のサウンド */
ntk_notification_channel_set_lockscreen_visibility(channel, 1);   /* -1〜1 */
ntk_notification_channel_set_group(channel, "samples", "Samples");
ntk_notification_error error = ntk_notification_create_channel(channel);

/* 内容: id、タイトル、メッセージは必須です。 */
ntk_notification_content* content = NULL;
error = ntk_notification_content_create(1001, "Native Toolkit", "Default style notification sample", &content);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    ntk_notification_channel_free(channel);
    return;
}
ntk_notification_content_set_channel(content, channel);           /* コピーされます */
ntk_notification_channel_free(channel);

/* 文言と識別子。すべて UTF-8 で、NULL は項目を既定値に戻します。 */
ntk_notification_content_set_tag(content, NULL);
ntk_notification_content_set_sub_text(content, "Default");
ntk_notification_content_set_ticker(content, "Native Toolkit");
ntk_notification_content_set_category(content, "status");
ntk_notification_content_set_sound(content, NULL);

/* アイコンはリソース名で指定し、show、update、schedule、進捗の関数が探します。
   スモールアイコンがなければアプリのアイコンを使います。 */
ntk_notification_content_set_small_icon(content, "ic_notification");
ntk_notification_content_set_large_icon(content, "ic_launcher_round");

/* 数値。priority は -2〜2、visibility は -1〜1。 */
ntk_notification_content_set_priority(content, 0);
ntk_notification_content_set_visibility(content, 1);
ntk_notification_content_set_color(content, 0xFF2196F3u);
ntk_notification_content_set_number(content, 1);
ntk_notification_content_set_timestamp(content, 1760054400000);   /* Unix ミリ秒 */
ntk_notification_content_set_timeout_after(content, 600000);      /* 10 分後に削除 */

/* フラグ。 */
ntk_notification_content_set_auto_cancel(content, 1);
ntk_notification_content_set_ongoing(content, 0);
ntk_notification_content_set_show_timestamp(content, 1);
ntk_notification_content_set_only_alert_once(content, 0);
ntk_notification_content_set_local_only(content, 0);
ntk_notification_content_set_silent(content, 0);
ntk_notification_content_set_uses_chronometer(content, 0);

/* グループ: キー、サマリーかどうか、どの通知が鳴るか（0〜2）、並び順。 */
ntk_notification_content_set_group(content, "native.toolkit.grouping.sample");
ntk_notification_content_set_group_summary(content, 0);
ntk_notification_content_set_group_alert_behavior(content, 1);    /* GROUP_ALERT_SUMMARY */
ntk_notification_content_set_sort_key(content, "01");

/* プログレスバー: max、current、indeterminate。 */
ntk_notification_content_set_progress(content, 100, 50, 0);

/* 表示、置き換え、削除。 */
error = ntk_notification_show(content);
if (error == NTK_NOTIFICATION_ERROR_PERMISSION_DENIED) {
    /* 権限がないか、アプリの通知がオフ。 */
} else if (error == NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND) {
    /* アイコン、画像、レイアウト、ビューのいずれかの名前が見つからなかった。 */
}
error = ntk_notification_update(content);
ntk_notification_content_free(content);

error = ntk_notification_remove(1001, NULL);   /* タグ、または NULL */
error = ntk_notification_remove_all();
error = ntk_notification_delete_channel("native_toolkit_sample");
```

#### スタイル・タップ・アクション

最後に設定したスタイルが有効になります。`add_message` と `add_view_click` は、先にそれぞれのスタイルを設定しておく必要があります。

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

ntk_notification_content* content = NULL;
ntk_notification_error error = ntk_notification_content_create(1002, "Native Toolkit",
                                                               "BigText style notification sample", &content);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}

/* BigText: big_text は必須です。 */
ntk_notification_content_set_style_big_text(content,
    "This is a BigText notification sample from Native Toolkit Example.", "BigText", "BigText Style");

/* Inbox。 */
const char* const lines[] = { "Permission status checked", "Channel created successfully" };
ntk_notification_content_set_style_inbox(content, lines, 2, "2 sample events", "Inbox Style");

/* BigPicture: 画像の名前か URI（名前が優先）、次に展開時のラージアイコン。 */
ntk_notification_content_set_style_big_picture(content, "ic_launcher", NULL, "Launcher image preview",
                                               "BigPicture Style", "ic_launcher_round", 0);

/* Messaging: group_conversation が -1 なら未設定のままです。送信者が NULL なら端末のユーザーです。 */
ntk_notification_content_set_style_messaging(content, "You", "Native Toolkit Example", 1);
ntk_notification_content_add_message(content, "Can you verify the notification styles?", 1760054280000, "Alex");
ntk_notification_content_add_message(content, "Confirmed. This is the Messaging sample.", 1760054400000, NULL);

/* DecoratedCustomView: レイアウト名、次に ACTION イベントとして届くクリック。 */
ntk_notification_content_set_style_custom_view(content, "notification_custom_style_sample",
                                               "notification_custom_style_sample_expanded");
ntk_notification_content_add_view_click(content, "notification_btn_dismiss", "custom_view_dismiss");

/* 本体のタップ: OPEN_APP（既定）はアプリを開いて BODY_TAP を送り、
   EVENT_ONLY は BODY_TAP だけを送り、NONE は何もしません。 */
ntk_notification_content_set_tap(content, NTK_NOTIFICATION_TAP_OPEN_APP);

/* この通知のすべてのイベント（タップ、アクション、クリック、消去）と一緒に届く文字列。 */
ntk_notification_content_add_data(content, "label", "Sample");

/* DISMISS イベントは既定で送られます。0 でオフにします。 */
ntk_notification_content_set_dismiss_event(content, 1);

/* アプリの起動 Activity を開くフルスクリーンインテント。 */
ntk_notification_content_set_full_screen(content, 0);

/* アクションボタン。 */
ntk_notification_action accept;
memset(&accept, 0, sizeof(accept));
accept.struct_size = (uint32_t)sizeof(accept);
accept.title = "Accept";
accept.action_id = "accept";        /* ACTION イベントで届きます */
accept.icon_name = NULL;            /* または drawable / mipmap の名前 */
accept.launch_app = 0;              /* 0 以外: アプリも開きます */
error = ntk_notification_content_add_action(content, &accept);

error = ntk_notification_show(content);
ntk_notification_content_free(content);
```

#### スケジュールと進捗

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

ntk_notification_content* content = NULL;
if (ntk_notification_content_create(1010, "Native Toolkit", "Scheduled notification sample", &content)
        != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}

/* 0 で埋めて trigger_at_millis を設定すると: 正確、Doze 中も発火、再起動後も保持、RTC_WAKEUP。 */
const int64_t now_unix_ms = 1760054400000;   /* 現在時刻。アプリの時計から取得します */
ntk_notification_schedule_options schedule;
memset(&schedule, 0, sizeof(schedule));
schedule.struct_size = (uint32_t)sizeof(schedule);
schedule.trigger_at_millis = now_unix_ms + 15000;

/* 保存済みのスケジュールを呼び出し元のスレッドで書き込みます。 */
ntk_notification_error error = ntk_notification_schedule(content, &schedule);
if (error == NTK_NOTIFICATION_ERROR_EXACT_ALARM_NOT_ALLOWED) {
    /* NTK_NOTIFICATION_SETTINGS_TARGET_EXACT_ALARM でユーザーに求めるか、inexact を設定します。 */
} else if (error == NTK_NOTIFICATION_ERROR_STORAGE_FAILED) {
    /* スケジュールを保存できなかった。 */
}
ntk_notification_content_free(content);

/* Kotlin の API と同じく、保存されたスケジュール（not_persist_across_boot == 0）だけが対象です。 */
int32_t scheduled = 0;
error = ntk_notification_is_scheduled(1010, NULL, &scheduled);
error = ntk_notification_cancel_scheduled(1010, NULL);
error = ntk_notification_cancel_all_scheduled();

/* フォアグラウンドサービスの進捗通知。ongoing、auto cancel、alert once はライブラリが
   設定します。プログレスバーのない内容は INVALID_PARAMETER です。 */
ntk_notification_content* progress = NULL;
if (ntk_notification_content_create(1011, "Native Toolkit Background Sync", "Running background sync... 10%",
                                    &progress) != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}
ntk_notification_content_set_progress(progress, 100, 10, 0);
error = ntk_notification_start_progress(progress);
if (error == NTK_NOTIFICATION_ERROR_SERVICE_START_NOT_ALLOWED) {
    /* Android がサービスの開始を拒否した（たとえばバックグラウンドから）。 */
}
ntk_notification_content_set_progress(progress, 100, 50, 0);
error = ntk_notification_update_progress(progress);
error = ntk_notification_complete_progress(progress);   /* バーを満たし、通常の通知が残ります */
ntk_notification_content_free(progress);

error = ntk_notification_stop_progress();               /* 停止して通知を削除します */
```

進捗の関数が伝えるのは、リクエストがサービスに届いたかどうかです。フォアグラウンドサービスの権限がないなど、サービスの中での失敗は logcat にだけ現れます。

#### インタラクションと表示イベント

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

static void NTK_CALL on_interaction(void* user_data, ntk_notification_interaction* event)
{
    /* Android のメインスレッドで呼ばれます。イベントは受け取った側のものです。今でも後でもよいので解放します。 */
    ntk_notification_event_kind kind = ntk_notification_interaction_kind(event);
    int32_t id = ntk_notification_interaction_notification_id(event);
    const char* tag = ntk_notification_interaction_tag(event, NULL);              /* NULL: タグなし */
    const char* action_id = ntk_notification_interaction_action_id(event, NULL);  /* ACTION のときだけ */
    size_t count = ntk_notification_interaction_data_count(event);
    size_t i;
    for (i = 0; i < count; ++i) {
        const char* key = ntk_notification_interaction_data_key_at(event, i, NULL);
        const char* value = ntk_notification_interaction_data_value_at(event, i, NULL);
        (void)key; (void)value;
    }
    if (kind == NTK_NOTIFICATION_EVENT_KIND_BODY_TAP) {
        /* 本体がタップされた。 */
    } else if (kind == NTK_NOTIFICATION_EVENT_KIND_ACTION) {
        /* ボタンかカスタムビューのクリック: action_id。 */
    } else if (kind == NTK_NOTIFICATION_EVENT_KIND_DISMISS) {
        /* スワイプで消された。 */
    }
    (void)user_data; (void)id; (void)tag; (void)action_id;
    ntk_notification_interaction_free(event);
}

static void NTK_CALL on_shown(void* user_data, ntk_notification_shown* event)
{
    /* スケジュール通知が発火した。 */
    int32_t id = ntk_notification_shown_notification_id(event);
    const char* tag = ntk_notification_shown_tag(event, NULL);
    const char* channel_id = ntk_notification_shown_channel_id(event, NULL);
    (void)user_data; (void)id; (void)tag; (void)channel_id;
    ntk_notification_shown_free(event);
}

static void NTK_CALL release_user_data(void* user_data)
{
    (void)user_data;
}

/* リスナーがない間に来たタップ、アクション、消去（最大 32 件）は、最初に追加された
   リスナーに届きます。表示イベントは保持されません。 */
ntk_notification_listener* interactions = NULL;
ntk_notification_error error = ntk_notification_add_interaction_listener(&on_interaction, NULL,
                                                                         &release_user_data, &interactions);
ntk_notification_listener* shown = NULL;
error = ntk_notification_add_shown_listener(&on_shown, NULL, &release_user_data, &shown);

/* メインスレッドから呼んだ場合、これが戻った後にコールバックへ届くイベントはありません。別の
   スレッドから呼んだ場合は、release_user_data が呼ばれるまでイベントが届くことがあります。
   以後、ハンドルは無効です。ライブラリが自分からリスナーを削除することはありません。 */
ntk_notification_listener_remove(interactions);
ntk_notification_listener_remove(shown);
```

#### 通知のエラー

`ntk_notification_error` です。値 0〜5 は、Android の C ABI のすべての機能で同じ意味です。

| 値 | 名前 | 条件 |
|---|---|---|
| 0 | `NTK_NOTIFICATION_ERROR_NONE` | 成功 |
| 1 | `NTK_NOTIFICATION_ERROR_INVALID_PARAMETER` | 不正な引数: `NULL`、不正な UTF-8、範囲外の値、誤った `struct_size` |
| 2 | `NTK_NOTIFICATION_ERROR_NOT_INITIALIZED` | 初期化の前に呼ばれた |
| 3 | `NTK_NOTIFICATION_ERROR_NOT_SUPPORTED` | このバージョンが知らない部分に、構造体が 0 以外の値を持っている |
| 4 | `NTK_NOTIFICATION_ERROR_UNKNOWN` | その他の失敗 |
| 5 | `NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY` | メモリが不足した |
| 6 | `NTK_NOTIFICATION_ERROR_CANCELED` | 権限のリクエストが `ntk_notification_cancel_permission_request` でキャンセルされた |
| 7 | `NTK_NOTIFICATION_ERROR_CANCELED_BY_SYSTEM` | 権限ダイアログを表示していた Activity が破棄された |
| 8 | `NTK_NOTIFICATION_ERROR_NOT_FOREGROUND` | 権限のリクエストか設定画面を、バックグラウンドから求めた |
| 9 | `NTK_NOTIFICATION_ERROR_HOST_START_FAILED` | ライブラリが透明なホスト Activity を開始できなかった |
| 10 | `NTK_NOTIFICATION_ERROR_PERMISSION_DENIED` | 権限がないか通知がオフの状態での `show`、`update`、過去の時刻の `schedule` |
| 11 | `NTK_NOTIFICATION_ERROR_EXACT_ALARM_NOT_ALLOWED` | 正確なアラームの権限がない状態での、未来の時刻への正確な `schedule` |
| 12 | `NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND` | アイコン、画像、レイアウト、ビューのいずれかの名前が見つからなかった |
| 13 | `NTK_NOTIFICATION_ERROR_STORAGE_FAILED` | 保存済みのスケジュールを書き込めなかった |
| 14 | `NTK_NOTIFICATION_ERROR_SERVICE_START_NOT_ALLOWED` | Android が進捗フォアグラウンドサービスの開始や到達を拒否した |
| 15 | `NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED` | どの設定画面も開けなかった |

`ntk_android_init` は `ntk_android_error` を返します。`NONE`（0）、`INVALID_PARAMETER`（1。`env` か `context` が `NULL`）、`CLASS_NOT_FOUND`（2。AAR のクラスがないか、R8 で名前が変えられた。再試行しても解決しません）、`JNI_FAILURE`（3。一時的なもので、後でもう一度呼びます。詳細は logcat のタグ `ntk` にあります）、`IN_PROGRESS`（4。別のスレッドが初期化中。後でもう一度呼びます）です。

| Kotlin の API | C ABI |
|---|---|
| `AndroidNotificationManager.getInstance` | -（関数はマネージャーを必要としません） |
| `LibraryRuntime.ensureInitialized` | `ntk_android_init` / `ntk_android_is_initialized` |
| `NotificationChannel` | `ntk_notification_channel_create` と 9 個のセッター |
| `AndroidNotificationCommand` | `ntk_notification_content_create` とそのセッター |
| `NotificationEventIntents` | `ntk_notification_content_set_tap` / `_add_action` / `_add_view_click` / `_set_dismiss_event` / `_set_full_screen` / `_add_data` |
| `show` / `update` | `ntk_notification_show` / `ntk_notification_update` |
| `cancel` / `cancelAll` | `ntk_notification_remove` / `ntk_notification_remove_all` |
| `createChannel` / `deleteChannel` | `ntk_notification_create_channel` / `ntk_notification_delete_channel` |
| `schedule` / `cancelScheduled` / `cancelAllScheduled` / `isScheduled` | `ntk_notification_schedule` / `_cancel_scheduled` / `_cancel_all_scheduled` / `_is_scheduled` |
| `startProgress` / `updateProgress` / `completeProgress` / `stopProgress` | `ntk_notification_start_progress` / `_update_progress` / `_complete_progress` / `_stop_progress` |
| `hasPermission` / `areNotificationsEnabled` / `canScheduleExactAlarms` | `ntk_notification_has_permission` / `_are_enabled` / `_can_schedule_exact_alarms` |
| `requestPermission` / `cancelPermissionRequest` | `ntk_notification_request_permission` / `ntk_notification_cancel_permission_request` |
| `openSettings` | `ntk_notification_open_settings_async`（フォアグラウンドの Activity から） |
| `interactions` / `shown` | `ntk_notification_add_interaction_listener` / `ntk_notification_add_shown_listener` |
| `EventHub.Registration.remove` | `ntk_notification_listener_remove` |

C ABI にないもの: `createChannels`、`getActive`、`restoreScheduled`、Media・DecoratedMediaCustomView・Call の各スタイル、`largeIconBitmap`、独自の `PendingIntent`、通話のフォアグラウンドサービスです。

---

## iOS

### IosNotificationManager

`IosNotificationManager` は iOS ローカル通知のすべての操作を提供するシングルトンクラスです。

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager.png" alt="Example_IosNotificationManager" width="400" />
</p>

### セットアップ

アプリ起動時（例: `AppDelegate.application(_:didFinishLaunchingWithOptions:)`）に `setup()` を一度だけ呼び出します。

```swift
import IosLibrary

IosNotificationManager.setup()
```

### パーミッション

#### 通知権限をリクエストする

```swift
IosNotificationManager.shared.requestPermission { isSuccess, errorMessage in
    if isSuccess {
        // 許可された
    } else {
        // 拒否された。設定アプリから手動で有効化が必要
    }
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_RequestPermission.png" alt="Example_IosNotificationManager_RequestPermission" width="400" />
</p>

#### 権限の確認

```swift
IosNotificationManager.shared.hasPermission { hasPermission in
    print(hasPermission) // true / false
}
```

#### 認証ステータスの取得

```swift
IosNotificationManager.shared.authorizationStatus { status in
    // .notDetermined / .denied / .authorized / .provisional / .ephemeral / .unknown
    print(status)
}
```

#### 通知設定を開く

```swift
IosNotificationManager.shared.openNotificationSettings()
```

### 通知の表示

`NotificationContent` を作成して `show()` を呼び出します。

#### 即時表示

```swift
let content = NotificationContent(
    id: "sample-notification",
    title: "Immediate Notification",
    body: "Displayed now",
    categoryIdentifier: "sample-category",
    userInfo: ["source": "IosLibraryExample", "id": "sample-notification"]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_ShowImmediate.png" alt="Example_IosNotificationManager_ShowImmediate" width="400" />
</p>

#### 添付ファイル付き即時表示

Bundle に含めた画像ファイルを添付として通知を表示します。
通知を長押し（展開表示）するとサムネイルが表示されます。

```swift
guard let imageURL = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else { return }

let attachment = NotificationAttachment(identifier: "app-icon", fileURL: imageURL)
let content = NotificationContent(
    id: "sample-notification",
    title: "Immediate Notification with Attachment",
    body: "Displayed with app icon attachment",
    categoryIdentifier: "sample-category",
    userInfo: ["source": "IosLibraryExample", "id": "sample-notification"],
    attachments: [attachment]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_ShowImmediateWithAttachment.png" alt="Example_IosNotificationManager_ShowImmediateWithAttachment" width="400" />
</p>

#### 時間間隔トリガー

```swift
IosNotificationManager.shared.show(
    content: content,
    trigger: .timeInterval(5.0, repeats: false)
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### カレンダートリガー

```swift
var components = DateComponents()
components.hour = 9
components.minute = 0

IosNotificationManager.shared.show(
    content: content,
    trigger: .calendar(components, repeats: true)
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### 位置情報トリガー

位置情報通知は CoreLocation を使用します。`Info.plist` に位置情報の利用説明文を追加してください。

```swift
IosNotificationManager.shared.show(
    content: content,
    trigger: .location(
        identifier: "tokyo-station",
        latitude: 35.6812,
        longitude: 139.7671,
        radius: 100,
        notifyOnEntry: true,
        notifyOnExit: false
    )
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### 添付ファイル

`NotificationAttachment` を使って通知に画像・音声・動画を添付できます。
通知を長押し（展開表示）するとサムネイルが表示されます。

```swift
guard let imageURL = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png") else { return }

let attachment = NotificationAttachment(identifier: "app-icon", fileURL: imageURL)
let content = NotificationContent(
    id: "sample-notification",
    title: "画像付き通知",
    body: "展開して画像を確認してください",
    attachments: [attachment]
)

IosNotificationManager.shared.show(content: content) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### 通知の更新

保留中の通知の内容やトリガーを更新します。

```swift
let updatedContent = NotificationContent(
    id: "sample-notification",
    title: "更新されたタイトル",
    body: "内容が変わりました"
)

IosNotificationManager.shared.update(
    identifier: "sample-notification",
    content: updatedContent,
    trigger: nil
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### 通知のキャンセル / 削除

```swift
// 特定の保留中通知をキャンセル
IosNotificationManager.shared.cancel(identifier: "sample-notification")

// 保留中通知をすべてキャンセル
IosNotificationManager.shared.cancelAll()

// 配信済み通知を通知センターから削除
IosNotificationManager.shared.removeDelivered(identifier: "sample-notification")

// 配信済み通知をすべて削除
IosNotificationManager.shared.removeAllDelivered()
```

### スケジュール通知

特定の ID で将来の通知をスケジュールします。

```swift
let content = NotificationContent(
    id: "scheduled-notification",
    title: "スケジュール通知",
    body: "10 秒後に表示されます"
)

IosNotificationManager.shared.schedule(
    content: content,
    trigger: .timeInterval(10.0, repeats: false),
    identifier: "scheduled-notification"
) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

#### スケジュールのキャンセル

```swift
// 特定のスケジュールをキャンセル
IosNotificationManager.shared.cancelScheduled(identifier: "scheduled-notification")

// すべてのスケジュールをキャンセル
IosNotificationManager.shared.cancelAllScheduled()
```

### クエリ

```swift
// 保留中（未配信）の通知リストを取得
IosNotificationManager.shared.getScheduled { requests in
    requests.forEach { print($0.identifier) }
}

// 配信済み通知リストを取得
IosNotificationManager.shared.getDelivered { notifications in
    notifications.forEach { print($0.identifier) }
}
```

### バッジ

```swift
// バッジ数を設定（0 でクリア）
IosNotificationManager.shared.setBadgeCount(1) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}

IosNotificationManager.shared.setBadgeCount(0) { isSuccess, errorMessage in
    print(isSuccess, errorMessage ?? "")
}
```

### カテゴリとアクション

通知にアクションボタンやテキスト入力を追加します。

#### カテゴリの登録

```swift
let category = NotificationCategory(
    identifier: "sample-category",
    actions: [
        NotificationAction(
            identifier: "open",
            title: "開く",
            options: [.foreground]
        ),
        NotificationAction(
            identifier: "delete",
            title: "削除",
            options: [.destructive]
        )
    ],
    textInputActions: [
        TextInputNotificationAction(
            identifier: "reply",
            title: "返信",
            buttonTitle: "送信",
            textInputPlaceholder: "メッセージを入力"
        )
    ],
    options: [.customDismissAction, .allowAnnouncement]
)

IosNotificationManager.shared.registerCategory(category)
```

#### カテゴリを通知に紐づける

`NotificationContent` の `categoryIdentifier` にカテゴリ ID を指定します。
通知を長押しするとアクションボタンが表示されます。

```swift
let content = NotificationContent(
    id: "sample-notification",
    title: "アクション付き通知",
    body: "長押ししてアクションを確認",
    categoryIdentifier: "sample-category"
)
```

#### カテゴリの削除

```swift
IosNotificationManager.shared.removeCategory(identifier: "sample-category")
```

<p align="center">
    <img src="images/ios/notification/Example_IosNotificationManager_Category.png" alt="Example_IosNotificationManager_Category" width="400" />
</p>

#### アクション受信コールバック

```swift
// アクションボタンのタップを受け取る
IosNotificationManager.shared.onActionReceived = { notificationId, actionId, userInfo in
    print("notification: \(notificationId), action: \(actionId)")
}

// テキスト入力アクションの送信を受け取る
IosNotificationManager.shared.onTextInputActionReceived = { notificationId, actionId, userText, userInfo in
    print("notification: \(notificationId), action: \(actionId), text: \(userText)")
}
```

---

## Windows

**パッケージ済み**（MSIX）アプリと**パッケージ無し**（通常の Win32）アプリの両方に対応したトースト通知です。Windows 11 以降が必要です。Windows ライブラリは、1 つの実装を 2 つの公開 API から提供します。サンプルアプリは C++ API を使用しています。

| API | 名前 | ヘッダー | NuGet パッケージ |
|---|---|---|---|
| C++ API | `NativeToolkit::Notification` | `<NativeToolkit/Notification.h>` | `NativeToolkit` |
| C ABI | `ntk_notification_*` | `<NativeToolkitC/Notification.h>` | `NativeToolkit.CApi` |

### NativeToolkit::Notification

- `Notification::Manager` はプロセスの通知サービスです。Windows はプロセスごとに 1 つの活性化ハンドラーしか登録しないため、`Manager` は同時に 1 つだけです。2 つ目の `Create` は `ErrorCode::NotSupported` で失敗します。
- すべての操作は同期で、呼び出したスレッドをブロックします。
- 戻り値は `Notification::Result<T>` です。`has_value()` で成否を判定し、失敗時の `error()` は `Notification::ErrorCode` と OS の生の値 `systemCode` を持ちます。
- `Manager::Create` は呼び出したスレッドを MTA（マルチスレッドアパートメント）にします。MTA になったスレッドでは、STA を必要とする `Clipboard::Session` を作れません。同じスレッドで両方を使う場合は、先にそのスレッドを STA で初期化してください。
- パッケージ無しのアプリでは、`SetBadge`、`RemoveById`、`GetAll` が `ErrorCode::NotSupported` になります。これらはプラットフォームがパッケージ済みアプリにのみ提供している機能です。

---

### セットアップ

#### Package.appxmanifest（パッケージ済みアプリ）

トーストの活性化を有効にするため、`<Application>` 要素の中に次の拡張を追加します。

```xml
<Extensions>
  <com:Extension Category="windows.comServer">
    <com:ComServer>
      <com:ExeServer Executable="YourApp.exe"
                     DisplayName="Native Toolkit Notification Activator"
                     Arguments="----AppNotificationActivated:">
        <com:Class Id="5F6A1B27-7C0B-4E1B-9070-6F1966502BAF"
                   DisplayName="Toast Activator"/>
      </com:ExeServer>
    </com:ComServer>
  </com:Extension>
  <desktop:Extension Category="windows.toastNotificationActivation">
    <desktop:ToastNotificationActivation
        ToastActivatorCLSID="5F6A1B27-7C0B-4E1B-9070-6F1966502BAF"/>
  </desktop:Extension>
</Extensions>
```

CLSID は、ご自身のマニフェストに登録したものに置き換えてください。サンプルアプリは `5F6A1B27-7C0B-4E1B-9070-6F1966502BAF` を使用しています。

#### Manager の作成 パッケージ済みアプリ

```cpp
#include <NativeToolkit/Notification.h>

#include <optional>

namespace Notification = NativeToolkit::Notification;

// このプロセスで唯一の Manager です。ムーブ専用なので、
// 作成した画面より長く生きる場所に置きます。
std::optional<Notification::Manager> g_manager;

void OnNotificationInvoked(Notification::ActivationArgs const& args)
{
    // OS が選んだスレッドで呼ばれます。UI を触る前に UI スレッドへ移してください。
    // 「活性化ハンドラー」を参照してください。
}

Notification::ManagerOptions options;
// 利用者が通知を操作したときに呼ばれます。空のままにすると活性化は捨てられます。
options.onInvoked = &OnNotificationInvoked;
// パッケージ済み（MSIX）アプリでは、表示名もアイコンも不要です。
options.isPackaged = true;

auto created = Notification::Manager::Create(options);
if (created.has_value())
{
    g_manager.emplace(std::move(created).value());
}
else
{
    // NotSupported: このプロセスにはすでに Manager があります。
    const Notification::ErrorCode code = created.error().code;
}
```

#### Manager の作成 パッケージ無しアプリ

パッケージ識別子を持たないアプリでは、先に Windows App SDK のランタイムを読み込み、通知を使う間そのトークンを保持し続けます。

```cpp
#include <NativeToolkit/Notification.h>

namespace Notification = NativeToolkit::Notification;

// 手順 1: Windows App SDK のランタイムを読み込みます。0x00010007 は 1.7 です。
auto runtime = Notification::Runtime::Initialize(Notification::RuntimeVersion{ 0x00010007 });
if (!runtime.has_value())
{
    // HResultFailure: systemCode にブートストラッパーの HRESULT が入ります。
    return;
}
// 破棄するとランタイムが下りるため、値を保持し続けます。
Notification::Runtime held = std::move(runtime).value();

// 手順 2: 表示名とアイコン（どちらも必須）を指定して Manager を作ります。
Notification::ManagerOptions options;
options.onInvoked = &OnNotificationInvoked;
options.isPackaged = false;
options.displayName = L"MyApp";
options.iconUri = L"C:\\path\\to\\app-icon.png";

auto created = Notification::Manager::Create(options);
```

ここでの `displayName` は表示名にとどまらず、アプリの AppUserModelID（AUMID）になります。`Create` はこの名前でスタートメニューのショートカットを作り、活性化の CLSID をこの名前から導き、`HKCU\Software\Classes\AppUserModelId\<displayName>` を書き込みます。この中には、起動中のプロセスに活性化を届ける `CustomActivator` も含まれます。書き込みは上書きなので、アプリごとに別の名前にしてください。同じ `displayName` を使う 2 つのアプリは、互いの活性化を奪い合います。C ABI の `display_name` も同じです。

#### 終了

```cpp
// 登録を解除し、活性化を止めます。2 回呼んでも何も起きません。
g_manager->Close();
g_manager.reset();
```

---

### 初期化 / 設定

#### 通知設定の取得

```cpp
const auto setting = g_manager->GetSetting();
if (setting.has_value())
{
    switch (setting.value())
    {
    case Notification::NotificationSetting::Enabled:                break; // 0
    case Notification::NotificationSetting::DisabledForApplication: break; // 1
    case Notification::NotificationSetting::DisabledForUser:        break; // 2
    case Notification::NotificationSetting::DisabledByGroupPolicy:  break; // 3
    case Notification::NotificationSetting::DisabledByManifest:     break; // 4
    }
}
```

#### 通知設定を開く

Windows の通知設定の画面を開きます。`GetSetting` が `Enabled` 以外を返したときに、利用者に通知を有効化してもらうために使用します。

```cpp
const auto result = g_manager->OpenSettings();
```

---

### 通知の表示

トーストに載せられる内容はすべて `NotificationContent` にあります。サンプルはタイトル・本文・タグを入れ、そこから 1 つずつ足していきます。

```cpp
Notification::NotificationContent MakeContent(std::wstring title, std::wstring body, std::wstring tag)
{
    Notification::NotificationContent content;
    content.title = std::move(title);
    content.body = std::move(body);
    content.tag = std::move(tag);
    return content;
}
```

#### 基本

```cpp
const auto content = MakeContent(L"Hello", L"Basic toast", L"sample");
const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowBasic.png" alt="Example_WindowsNotificationManager_ShowBasic" width="800" />
</p>

#### ボタン付き

ボタンは自身の引数を持ち、押されたときに活性化ハンドラーへ届きます。ボタンは最大 5 個です。

```cpp
Notification::Button MakeButton(std::wstring label, std::wstring action)
{
    Notification::Button button;
    button.label = std::move(label);
    // キーは任意です。ActivationArgs::values で戻ってきます。
    button.args = Notification::ArgumentPairs{ { L"action", std::move(action) } };
    return button;
}

auto content = MakeContent(L"Actionable", L"Toast with buttons", L"sample");
content.buttons = { MakeButton(L"Open", L"open"), MakeButton(L"Dismiss", L"dismiss") };
const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowWithButtons.png" alt="Example_WindowsNotificationManager_ShowWithButtons" width="800" />
</p>

#### 画像付き

```cpp
auto content = MakeContent(L"With Image", L"Toast with hero image", L"sample");
// パッケージ済みアプリでは ms-appx:/// が使えます。file:/// や http(s):// も使えます。
content.heroImage = L"ms-appx:///Assets/StoreLogo.png";
const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowWithImage.png" alt="Example_WindowsNotificationManager_ShowWithImage" width="800" />
</p>

#### 入力付き

利用者が入力・選択した値は、フィールドの id をキーとして活性化ハンドラーに届きます。

```cpp
auto content = MakeContent(L"Reply", L"Type a reply and pick an option", L"sample");

Notification::TextInput reply;
reply.id = L"reply";
reply.placeholder = L"Type a message";
content.textInputs = { reply };

Notification::ComboInput status;
status.id = L"opt";
status.title = L"Status";
// items との突き合わせは行いません。存在しない id を指定すると未選択になります。
status.defaultSelection = L"busy";
status.items = { { L"free", L"Free" }, { L"busy", L"Busy" } };
content.comboInputs = { status };

content.buttons = { MakeButton(L"Send", L"send") };
const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowWithInput.png" alt="Example_WindowsNotificationManager_ShowWithInput" width="800" />
</p>

#### 進捗バー付き

進捗バーを表示します。あとから同じタグで `UpdateProgress` を呼ぶと更新できます。

```cpp
auto content = MakeContent(L"Downloading", L"In progress", L"progress-sample");

Notification::ProgressSpec progress;
progress.title = L"Toolkit.zip";
// 0.0 〜 1.0 です。ここでは範囲の検査はしません。
progress.value = 0.3;
progress.valueStr = L"30%";
progress.status = L"Downloading";
content.progress = progress;

const auto result = g_manager->Show(content);
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_ShowWithProgress.png" alt="Example_WindowsNotificationManager_ShowWithProgress" width="800" />
</p>

#### 有効期限付き

指定した時間が過ぎると、通知は通知センターから消えます。配信からの相対時間で、`Schedule` では無視されます。

```cpp
auto content = MakeContent(L"Expires", L"This toast expires in 10 seconds", L"sample");
content.expiration = std::chrono::seconds(10);
const auto result = g_manager->Show(content);
```

#### サウンド付き

```cpp
auto content = MakeContent(L"Reminder", L"Toast with reminder sound", L"sample");

Notification::AudioSpec audio;
// Event: 名前付きのシステム音。Mute: 無音。Uri: audio.uri の音。
audio.kind = Notification::AudioKind::Event;
audio.eventName = L"reminder";
content.audio = audio;

const auto result = g_manager->Show(content);
```

---

### スケジュール通知

`Schedule` は絶対時刻を `std::chrono::system_clock::time_point` で受け取ります。予約では `expiration` と `progress` は無視されます。

```cpp
#include <chrono>

const auto when = std::chrono::system_clock::now() + std::chrono::seconds(60);
const auto content = MakeContent(L"Scheduled", L"Fires in ~1 minute", L"scheduled");
const auto result = g_manager->Schedule(content, when);
```

> **注意:** 5 分以上過去の時刻を指定した通知は、配信時刻にアプリが起動していなかった場合、OS に破棄されることがあります。

#### スケジュールのキャンセル

```cpp
// 予約した通知のタグとグループを指定します。
const auto result = g_manager->CancelScheduled(L"scheduled", L"");
```

---

### 進捗の更新

進捗バーを表示している通知を更新します。`ErrorCode::ProgressNotFound` は、該当する通知が通知センターに無いか、シーケンス番号が古いことを意味します。

```cpp
Notification::ProgressUpdate update;
// Show に渡したタグ・グループと一致させます。
update.tag = L"progress-sample";
update.group = L"";
update.value = 0.6;
update.valueString = L"60%";
update.status = L"Downloading";
// 呼び出し側が増やします。逆戻りした更新は OS が捨てます。
update.sequenceNumber = seq++;

const auto result = g_manager->UpdateProgress(update);
if (!result.has_value() && result.error().code == Notification::ErrorCode::ProgressNotFound)
{
    // 更新対象がありません。先に進捗付きの通知を表示してください。
}
```

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_UpdateProgress.png" alt="Example_WindowsNotificationManager_UpdateProgress" width="800" />
</p>

---

### バッジ

タスクバーのアイコンにバッジを付けます。パッケージ済みアプリ専用で、パッケージ無しのアプリでは `ErrorCode::NotSupported` になります。

```cpp
g_manager->SetBadge(5);   // 数字のバッジ
g_manager->SetBadge(-1);  // グリフ: alert
g_manager->SetBadge(0);   // バッジを消す
```

**グリフの値:** `-1`=alert、`-2`=activity、`-3`=newMessage、`-4`=available、`-5`=busy、`-6`=away。-6 より小さい値は `ErrorCode::InvalidParameter` です。

<p align="center">
    <img src="images/windows/notification/Example_WindowsNotificationManager_Badge.png" alt="Example_WindowsNotificationManager_Badge" width="800" />
</p>

---

### 削除 / クエリ

#### 全通知の取得

通知センターにあるものを一覧します。パッケージ済みアプリ専用です。

```cpp
const auto result = g_manager->GetAll();
if (result.has_value())
{
    for (const Notification::NotificationRef& notification : result.value())
    {
        const uint32_t id = notification.id;
        const std::wstring& tag = notification.tag;
        const std::wstring& group = notification.group;
    }
}
```

#### ID 指定削除

`GetAll` が返した id を指定して 1 件だけ削除します。パッケージ済みアプリ専用です。

```cpp
const auto result = g_manager->RemoveById(notificationId);
```

#### タグ指定削除

```cpp
const auto result = g_manager->RemoveByTag(L"sample", L"");
```

#### 全削除

```cpp
const auto result = g_manager->RemoveAll();
```

---

### 活性化ハンドラー

ハンドラーは OS が活性化を配信したスレッドで動き、呼び出し側のスレッドへは移されません。`ActivationArgs::values` には、押されたボタンの引数と、すべてのテキスト欄・選択欄の内容が id をキーとしてまとめて入ります。`rawArguments` は手を加えていない引数の文字列です。

パッケージ無しのアプリがトーストのクリックで起動した場合（コールドスタート）も、その活性化はほかの活性化と同じ経路で 1 回だけ届きます。`Manager::Create` が戻る前に届くことがあり、呼び出したスレッドが STA のときは、`Create` の中でそのスレッドに届くことを確かめています。ハンドラーは、自分が属する Manager がすでに存在していると想定してはいけません。プロセスのコマンドラインには COM に起動されたこと（`-ToastActivated -Embedding`）しか載らず、トーストの内容は含まれません。

サンプルアプリでは、ハンドラーを作成時に 1 回だけ登録し、そのときに画面に出ているページへ転送しています。

```cpp
namespace
{
    std::function<void(winrt::hstring)> g_notificationHandler;

    void OnNotificationInvoked(Notification::ActivationArgs const& args)
    {
        if (g_notificationHandler)
        {
            g_notificationHandler(winrt::hstring{ args.rawArguments });
        }
    }
}

// OnNavigatedTo で登録し、UI スレッドへ移します。
auto weakText = winrt::make_weak(ResultTextBlock());
auto dq = DispatcherQueue();
g_notificationHandler = [weakText, dq](winrt::hstring args)
{
    dq.TryEnqueue([weakText, args]()
    {
        if (auto text = weakText.get())
            text.Text(L"\U0001F514 Notification invoked:\n" + args);
    });
};

// OnNavigatedFrom で解除します。
g_notificationHandler = nullptr;
```

---

### エラーコード

`Notification::ErrorCode`（`NativeToolkit::NotificationError`）です。同じ数値が C ABI の `NTK_NOTIFICATION_ERROR_*` になります。

| コード | 名前 | 説明 |
|---|---|---|
| 0 | `None` | 成功 |
| 1 | `NotInitialized` | `Create` の前、または `Close` の後に使用しました |
| 2 | `Disabled` | このアプリまたは利用者に対して通知が無効です |
| 3 | `InvalidPayload` | 予約済みで返りません。1.x の C ABI で JSON が解析できなかった場合の値です |
| 4 | `ProgressNotFound` | 更新対象の通知が無いか、シーケンス番号が古いです |
| 5 | `HResultFailure` | 登録、ショートカット、またはランタイムの読み込みに失敗しました |
| 6 | `BadgeFailed` | バッジの更新に失敗しました |
| 7 | `InvalidParameter` | 引数が不正です（-6 より小さいバッジ値など） |
| 8 | `NotSupported` | このアプリの種類では使用できません（パッケージ無しでの `SetBadge` / `RemoveById` / `GetAll`）、または 2 つ目の Manager です |

### C ABI

- C から、そして C の DLL を呼べる言語から同じ通知を使うための API です。
- 内容は構造体ではなくハンドルで組み立てます。セッターを 1 つずつ呼び、`ntk_notification_content_free` で解放します。
- 登録は `user_data` と `release` を伴います。`release` は登録ごとに必ず 1 回呼ばれます（登録した関数が失敗したときも呼ばれます）。バインディングが確保したものは、ここで解放します。
- ハンドルは `ntk_notification_manager_free`、`ntk_notification_runtime_free`、`ntk_notification_list_free` で解放します。
- すべての関数はどのスレッドからでも呼べます。活性化は OS が選んだスレッドで届き、そこで受け取るものはその呼び出しの間だけ有効です。

#### ランタイム・マネージャー・活性化

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

static void NTK_CALL on_invoked(void* user_data, const ntk_notification_activation* activation)
{
    /* OS が選んだスレッドで呼ばれます。ここで読んだものは呼び出しの外では使えません。 */
    size_t size = 0;
    const char* raw = ntk_notification_activation_raw_arguments(activation, &size);
    (void)raw; (void)user_data;

    /* 押されたボタンの引数と利用者の入力が、id をキーとしてまとまっています。 */
    size_t count = ntk_notification_activation_value_count(activation);
    size_t i;
    for (i = 0; i < count; ++i) {
        const char* key = ntk_notification_activation_key_at(activation, i, NULL);
        const char* value = ntk_notification_activation_value_at(activation, i, NULL);
        (void)key; (void)value;
    }
}

static void NTK_CALL release_user_data(void* user_data)
{
    /* 登録した関数が失敗したときも含め、ちょうど 1 回呼ばれます。 */
    (void)user_data;
}

/* パッケージ識別子を持たないアプリは、先に Windows App SDK のランタイムを
   読み込み、通知を使う間ハンドルを保持します。0x00010007 は 1.7 です。
   パッケージ済みアプリでは不要です。 */
ntk_notification_runtime* runtime = NULL;
ntk_notification_error error = ntk_notification_runtime_initialize(0x00010007u, &runtime);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}

ntk_notification_manager_options options;
memset(&options, 0, sizeof(options));
options.struct_size = (uint32_t)sizeof(options);
options.on_invoked = &on_invoked;
options.user_data = NULL;
options.release = &release_user_data;
options.is_unpackaged = 1;                 /* パッケージ済み（MSIX）アプリでは 0 */
options.display_name = "MyApp";            /* パッケージ無しのときは必須 */
options.icon_uri = "C:\\path\\to\\app-icon.png";

ntk_notification_manager* manager = NULL;
error = ntk_notification_manager_create(&options, &manager);
if (error != NTK_NOTIFICATION_ERROR_NONE) {
    ntk_notification_runtime_free(runtime);
    return;
}

/* あとからハンドラーを差し替える場合。前の登録の release は、その登録で
   走っている活性化がすべて戻ってから呼ばれます。 */
error = ntk_notification_manager_set_invoked_handler(manager, &on_invoked, NULL, &release_user_data);

/* 終了時は close → マネージャーの解放 → ランタイムの解放の順です。 */
ntk_notification_manager_close(manager);
ntk_notification_manager_free(manager);
ntk_notification_runtime_free(runtime);
```

#### 内容の組み立て・表示・予約

OS が必須とするもの以外、セッターはすべて任意です。`add_button` と `add_combo` は追加したものの添字を返し、引数や項目のセッターはその添字を指定します。

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

ntk_notification_content* content = NULL;
if (ntk_notification_content_create(&content) != NTK_NOTIFICATION_ERROR_NONE) {
    return;
}

/* 文言と識別子です。すべて UTF-8 です。 */
ntk_notification_content_set_title(content, "Hello");
ntk_notification_content_set_body(content, "Basic toast");
ntk_notification_content_set_tag(content, "sample");
ntk_notification_content_set_group(content, "");
ntk_notification_content_set_attribution(content, "native-toolkit");
ntk_notification_content_set_scenario(content, NTK_NOTIFICATION_SCENARIO_DEFAULT);
ntk_notification_content_set_duration(content, NTK_NOTIFICATION_DURATION_SHORT);

/* 画像です。 */
ntk_notification_content_set_hero_image(content, "ms-appx:///Assets/StoreLogo.png");
ntk_notification_content_set_inline_image(content, NULL);   /* NULL で取り消し */
ntk_notification_content_set_app_logo(content, "ms-appx:///Assets/StoreLogo.png",
                                      NTK_NOTIFICATION_LOGO_CROP_CIRCLE);

/* 音です。名前付きのシステム音で、繰り返しはしません。 */
ntk_notification_content_set_audio(content, NTK_NOTIFICATION_AUDIO_KIND_EVENT,
                                   "reminder", NULL, 0);

/* ボタンです。with_arguments を 0 以外にすると、引数の一覧が用意されます。 */
size_t button = 0;
ntk_notification_content_add_button(content, "Open", NULL, 1, &button);
ntk_notification_content_add_button_argument(content, button, "action", "open");

/* テキスト欄と選択欄です。 */
ntk_notification_content_add_text_input(content, "reply", "Type a message", NULL);

size_t combo = 0;
ntk_notification_content_add_combo(content, "opt", "Status", "busy", &combo);
ntk_notification_content_add_combo_item(content, combo, "free", "Free");
ntk_notification_content_add_combo_item(content, combo, "busy", "Busy");

/* 進捗バーと時刻です。どちらも予約では無視されます。 */
ntk_notification_content_set_progress(content, "Toolkit.zip", 0.3, "30%", "Downloading");
ntk_notification_content_set_expiration(content, 10);            /* 配信からの秒数 */
ntk_notification_content_set_expires_on_reboot(content, 0);      /* パッケージ済みアプリのみ */
ntk_notification_content_set_timestamp(content, 1758585600000);  /* Unix ミリ秒 */

/* いま表示する場合。 */
ntk_notification_error error = ntk_notification_show(manager, content);

/* 絶対時刻を指定して予約する場合。時刻は Unix ミリ秒です。 */
error = ntk_notification_schedule(manager, content, 1758585660000);

ntk_notification_content_free(content);

/* 予約した通知は、タグとグループで取り消します。 */
error = ntk_notification_cancel_scheduled(manager, "scheduled", "");
```

#### 進捗・バッジ・OS の設定

```c
#include <string.h>
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

/* 進捗バーを表示している通知を更新します。 */
ntk_notification_progress_update update;
memset(&update, 0, sizeof(update));
update.struct_size = (uint32_t)sizeof(update);
update.tag = "progress-sample";      /* ntk_notification_show に渡したもの */
update.group = "";
update.value = 0.6;
update.value_string = "60%";
update.status = "Downloading";
update.sequence_number = 2;          /* 呼び出し側が増やします */

ntk_notification_error error = ntk_notification_update_progress(manager, &update);
if (error == NTK_NOTIFICATION_ERROR_PROGRESS_NOT_FOUND) {
    /* 更新対象が無いか、シーケンス番号が古いです。 */
}

/* タスクバーのアイコンのバッジです。パッケージ済みアプリ専用で、それ以外は
   NOT_SUPPORTED です。5 は数字、-1 は alert のグリフ、0 は消去です。 */
error = ntk_notification_set_badge(manager, 5);

/* OS の設定の状態と、それを変える画面です。 */
ntk_notification_setting setting = NTK_NOTIFICATION_SETTING_ENABLED;
error = ntk_notification_get_setting(manager, &setting);
if (setting != NTK_NOTIFICATION_SETTING_ENABLED) {
    error = ntk_notification_open_settings(manager);
}
```

#### 一覧と削除

```c
#include <NativeToolkitC/Common.h>
#include <NativeToolkitC/Notification.h>

/* 通知センターにあるものです。パッケージ済みアプリ専用です。 */
ntk_notification_list* list = NULL;
ntk_notification_error error = ntk_notification_get_all(manager, &list);
if (error == NTK_NOTIFICATION_ERROR_NONE) {
    size_t count = ntk_notification_list_count(list);
    size_t i;
    for (i = 0; i < count; ++i) {
        uint32_t id = ntk_notification_list_id_at(list, i);
        const char* tag = ntk_notification_list_tag_at(list, i, NULL);
        const char* group = ntk_notification_list_group_at(list, i, NULL);
        (void)id; (void)tag; (void)group;
    }
    /* 上のポインターは、この呼び出しまで有効です。 */
    ntk_notification_list_free(list);
}

/* 削除は、get_all が返した id（パッケージ済みアプリ専用）、タグとグループ、
   またはこのアプリが出したものすべて、の 3 通りです。 */
error = ntk_notification_remove_by_id(manager, 1u);
error = ntk_notification_remove_by_tag(manager, "sample", "");
error = ntk_notification_remove_all(manager);
```

| C++ API | C ABI |
|---|---|
| `Runtime::Initialize` / デストラクター | `ntk_notification_runtime_initialize` / `ntk_notification_runtime_free` |
| `Manager::Create` | `ntk_notification_manager_create` |
| `Manager::SetInvokedHandler` | `ntk_notification_manager_set_invoked_handler` |
| `Manager::Close` | `ntk_notification_manager_close` / `ntk_notification_manager_free` |
| `NotificationContent` | `ntk_notification_content_create` と 22 個のセッター |
| `ActivationArgs` | `ntk_notification_activation_raw_arguments` / `_value_count` / `_key_at` / `_value_at` |
| `Manager::Show` | `ntk_notification_show` |
| `Manager::Schedule` | `ntk_notification_schedule`（時刻は Unix ミリ秒） |
| `Manager::CancelScheduled` | `ntk_notification_cancel_scheduled` |
| `Manager::UpdateProgress` | `ntk_notification_update_progress` |
| `Manager::SetBadge` | `ntk_notification_set_badge` |
| `Manager::GetAll` | `ntk_notification_get_all` と `ntk_notification_list_*` |
| `Manager::RemoveById` / `RemoveByTag` / `RemoveAll` | `ntk_notification_remove_by_id` / `_by_tag` / `_all` |
| `Manager::GetSetting` | `ntk_notification_get_setting` |
| `Manager::OpenSettings` | `ntk_notification_open_settings` |

---

## macOS

### MacNotificationManager

`MacNotificationManager` は、macOS のローカル通知操作をすべて提供するシングルトンクラスです。

**要件:** macOS 15 以上。それ以前の OS バージョンでの呼び出しは `unsupportedOS`（エラーコード 1001）を返します。

**スレッド安全性:** 公開 API はどのスレッドからでも呼び出せます。すべての completion コールバックは **メインキュー** で実行されます。

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager.png" alt="Example_MacNotificationManager" width="800" />
</p>

### セットアップ

アプリ起動時（例: `applicationDidFinishLaunching`）に一度だけ `setup()` を呼び出します。アクション受信コールバックはここで登録します。

```swift
import MacLibrary

MacNotificationManager.shared.setup()

// アクションボタンのタップを受信
MacNotificationManager.shared.setActionReceivedHandler { notificationId, actionId, userInfoJson in
    print("アクション受信: \(notificationId), \(actionId)")
}

// テキスト入力アクションの送信を受信
MacNotificationManager.shared.setTextInputActionReceivedHandler { notificationId, actionId, userText, userInfoJson in
    print("テキスト入力受信: \(userText)")
}
```

### パーミッション

#### 権限のリクエスト

```swift
MacNotificationManager.shared.requestPermission { result in
    // メインキューで実行
    switch result {
    case .success:
        print("通知権限が許可されました")
    case .failure(let error):
        if error.errorCode == 1002 || error.errorCode == 1003 {
            // 拒否済み - 設定アプリから手動で有効化が必要
            print("権限が拒否されています。設定から通知を有効にしてください。")
        } else {
            print("エラー \(error.errorCode): \(error.errorMessage)")
        }
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_RequestPermission.png" alt="Example_MacNotificationManager_RequestPermission" width="800" />
</p>

#### パーミッション確認

許可済みかどうかを真偽値で確認します。

```swift
MacNotificationManager.shared.getAuthorizationStatus { result in
    switch result {
    case .success(let status):
        let hasPermission = status == .authorized || status == .provisional
        print("通知許可: \(hasPermission)")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### 認証ステータスの取得

詳細なステータス値を取得します。

```swift
MacNotificationManager.shared.getAuthorizationStatus { result in
    switch result {
    case .success(let status):
        // .notDetermined / .denied / .authorized / .provisional / .unsupported
        print(status)
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### 通知設定を開く

```swift
MacNotificationManager.shared.openNotificationSettings { result in
    if case .failure(let error) = result {
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### 通知権限のリセット（macOS 26.3）

一度拒否した権限を開発中にリセットする手順です。

1. **システム設定** → **通知** を開く
2. アプリ一覧から対象アプリを**右クリック**
3. **「通知をリセット...」** を選択
4. 確認ダイアログで **「通知をリセット」** ボタンを押す
5. 次回アプリ起動時に権限ダイアログが再表示される

### 通知の表示

`NotificationContent` を作成して `show()` を呼び出します。

**`NotificationContent` の制約:**

- `id`: 1〜128 文字（`[A-Za-z0-9\-_]`）
- `title`: 1〜128 文字
- `body`: 0〜1024 文字（省略可）

#### 即時表示

```swift
import MacLibrary

let content = NotificationContent(
    id: "mac-sample-notification",
    title: "Immediate Notification",
    body: "Displayed now",
    subtitle: "MacLibraryExample",
    categoryIdentifier: "mac-sample-category",
    userInfo: ["source": "MacLibraryExample", "id": "mac-sample-notification"],
    badge: nil
)

MacNotificationManager.shared.show(content: content) { result in
    // メインキューで実行
    switch result {
    case .success:
        print("通知を表示しました")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_ShowImmediate.png" alt="Example_MacNotificationManager_ShowImmediate" width="800" />
</p>

#### 時間間隔トリガー

```swift
MacNotificationManager.shared.show(
    content: content,
    trigger: .timeInterval(seconds: 10, repeats: false)
) { result in
    switch result {
    case .success:
        print("10秒後にスケジュール済み")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### カレンダートリガー

```swift
let nextDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()
var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
components.second = 0

MacNotificationManager.shared.show(
    content: content,
    trigger: .calendar(dateComponents: components, repeats: false)
) { result in
    switch result {
    case .success:
        print("1分後にスケジュール済み")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

### 更新 / キャンセル / 削除

#### IDで更新

保留中の通知を新しい内容に置き換えます。

```swift
let updatedContent = NotificationContent(
    id: "mac-sample-notification",
    title: "Updated Notification",
    body: "This content was updated",
    subtitle: "MacLibraryExample",
    categoryIdentifier: "mac-sample-category",
    userInfo: ["source": "MacLibraryExample", "id": "mac-sample-notification"],
    badge: nil
)

MacNotificationManager.shared.update(
    identifier: "mac-sample-notification",
    content: updatedContent,
    trigger: .immediate
) { result in
    switch result {
    case .success:
        print("更新しました")
    case .failure(let error):
        // 通知が見つからない場合はエラーコード 1104
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_UpdateById.png" alt="Example_MacNotificationManager_UpdateById" width="800" />
</p>

#### IDでキャンセル

```swift
MacNotificationManager.shared.cancelScheduled(identifier: "mac-sample-notification")
```

#### すべてキャンセル

```swift
MacNotificationManager.shared.cancelAllScheduled()
```

#### 配信済み通知の削除

通知センターから特定の通知を削除します。

```swift
MacNotificationManager.shared.removeDelivered(identifier: "mac-sample-notification")
```

#### 配信済み通知をすべて削除

```swift
MacNotificationManager.shared.removeAllDelivered()
```

### スケジュール

`schedule()` を使って将来の通知を登録します。トリガーは `.immediate` 以外を指定してください。

#### 時間間隔でスケジュール

```swift
let content = NotificationContent(
    id: "mac-sample-scheduled",
    title: "Scheduled Notification",
    body: "Scheduled in 10 seconds",
    subtitle: "MacLibraryExample",
    categoryIdentifier: "mac-sample-category",
    userInfo: ["source": "MacLibraryExample", "id": "mac-sample-scheduled"],
    badge: nil
)

MacNotificationManager.shared.schedule(
    content: content,
    trigger: .timeInterval(seconds: 10, repeats: false)
) { result in
    switch result {
    case .success:
        print("スケジュール済み")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### カレンダーでスケジュール

```swift
let nextDate = Calendar.current.date(byAdding: .minute, value: 1, to: Date()) ?? Date()
var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: nextDate)
components.second = 0

MacNotificationManager.shared.schedule(
    content: content,
    trigger: .calendar(dateComponents: components, repeats: false)
) { result in
    switch result {
    case .success:
        print("カレンダースケジュール済み")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### IDでキャンセル（スケジュール）

```swift
MacNotificationManager.shared.cancelScheduled(identifier: "mac-sample-scheduled")
```

#### すべてキャンセル（スケジュール）

```swift
MacNotificationManager.shared.cancelAllScheduled()
```

### クエリ

#### スケジュール済みを取得

```swift
MacNotificationManager.shared.getScheduled { result in
    switch result {
    case .success(let items):
        let ids = items.map { $0.identifier }.joined(separator: ", ")
        print("スケジュール済み: \(items.count) 件, ids=[\(ids)]")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### 配信済みを取得

```swift
MacNotificationManager.shared.getDelivered { result in
    switch result {
    case .success(let items):
        let ids = items.map { $0.identifier }.joined(separator: ", ")
        print("配信済み: \(items.count) 件, ids=[\(ids)]")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

### バッジ

#### バッジカウントを設定（1）

```swift
MacNotificationManager.shared.setBadgeCount(1) { result in
    switch result {
    case .success:
        print("バッジを 1 に設定しました")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

#### バッジをクリア（0）

```swift
MacNotificationManager.shared.setBadgeCount(0) { result in
    switch result {
    case .success:
        print("バッジをクリアしました")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

### カテゴリ

#### カテゴリの登録

```swift
let category = NotificationCategory(
    id: "mac-sample-category",
    actions: [
        NotificationAction(id: "open", title: "Open", isForeground: true),
        NotificationAction(id: "reply", title: "Reply", isTextInput: true, textInputPlaceholder: "Type message")
    ]
)

MacNotificationManager.shared.registerCategory(category) { result in
    switch result {
    case .success:
        // 通知を送信して右クリックするとアクション（Open, Reply）が表示される
        print("カテゴリを登録しました")
    case .failure(let error):
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

`NotificationContent` の `categoryIdentifier` に設定することでカテゴリを通知に紐づけます。

```swift
let content = NotificationContent(
    id: "mac-sample-notification",
    title: "アクション付き通知",
    body: "右クリックするとアクションが表示されます",
    subtitle: "MacLibraryExample",
    categoryIdentifier: "mac-sample-category",
    userInfo: ["source": "MacLibraryExample", "id": "mac-sample-notification"],
    badge: nil
)
```

<p align="center">
    <img src="images/mac/notification/Example_MacNotificationManager_RegisterCategory.png" alt="Example_MacNotificationManager_RegisterCategory" width="800" />
</p>

#### カテゴリの削除

```swift
MacNotificationManager.shared.removeCategory(identifier: "mac-sample-category") { result in
    if case .failure(let error) = result {
        print("エラー \(error.errorCode): \(error.errorMessage)")
    }
}
```

### エラーコード

| コード | ケース                    | 説明                                           |
| ------ | ------------------------- | ---------------------------------------------- |
| 1001   | `unsupportedOS`           | macOS 15 以上が必要                            |
| 1002   | `permissionDenied`        | ユーザーが通知権限を拒否                       |
| 1003   | `permissionRequestFailed` | 権限リクエストに失敗                           |
| 1101   | `invalidContent`          | id、title、または body が無効                  |
| 1102   | `invalidTrigger`          | トリガーが無効（例: timeInterval が 1 秒未満） |
| 1103   | `invalidCategory`         | カテゴリが無効                                 |
| 1104   | `notificationNotFound`    | 指定した識別子の保留中通知が見つからない       |
| 1201   | `addFailed`               | 通知リクエストの追加に失敗                     |
| 1202   | `removeFailed`            | 通知の削除に失敗                               |
| 1203   | `queryFailed`             | 通知の取得に失敗                               |
| 1204   | `setBadgeFailed`          | バッジカウントの設定に失敗                     |
| 1205   | `openSettingsFailed`      | 通知設定を開くのに失敗                         |
| 1999   | `unknown`                 | 不明なエラー                                   |
