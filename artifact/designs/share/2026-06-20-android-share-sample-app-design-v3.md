# 実装計画: Share サンプルアプリ（AndroidLibraryExample）v3

- 対象アプリ: `android/AndroidLibraryExample`
- 参照設計書: `artifact/designs/share/2026-06-20-android-share-design-v3.md`
- 前版: `artifact/designs/share/2026-05-24-android-share-implement-sample-app-v2.md`
- 作成日: 2026-06-20
- 改訂: v3（**受信側デモの追加** + 親設計 v3 反映：リッチプレビュー送信・コールバック文言修正）

---

## 概要

v2 サンプル（送信 8 機能の手動確認画面）に対し、v3 では以下を追加・変更する。

1. **受信側の実装（本 v3 の主目的）**
   他アプリから共有された内容、および Direct Share ターゲット（"Sample User"）選択時の共有を
   サンプルアプリで受け取り、内容を画面に表示する。
2. **リッチプレビュー送信ボタンの追加**（親設計 #5）
3. **コールバック文言の修正**（親設計 #2：キャンセル時は結果が来ない場合がある）

> 受信処理はライブラリ（`android_library` / `unity_android_plugin`）には実装しない。
> 受信後の扱いはアプリ固有の責務であり、本サンプルは「利用側アプリでの受信実装例」として示す。

---

## 受信の前提（既存の Manifest 状態）

これまでの作業で以下は既に追加済み。受信実装はこれらの上に成り立つ。

| 要素 | 状態 | 役割 |
|---|---|---|
| `MainActivity` の `ACTION_SEND` intent-filter | 追加済み | 他アプリの Sharesheet にこのアプリを表示し、共有を受信可能にする（Direct Share の必須要素でもある） |
| `res/xml/shortcuts.xml` の `<share-target>` | 追加済み | Direct Share ターゲットの宣言（`targetClass = MainActivity`, `text/plain`, `android.shortcut.conversation`） |
| `android.app.shortcuts` meta-data | 追加済み | shortcuts.xml の関連付け |

**注意:** 受信を実装するからといって `ACTION_SEND`（text/plain）filter を変更・削除しない。filter は Direct Share の動作にも必須。

**既存 Manifest の不足（要追加）:** 現状の intent-filter は `ACTION_SEND` + `text/plain` のみ。
**画像受信を完了条件に含めるため、`image/*` の `ACTION_SEND` と `ACTION_SEND_MULTIPLE` filter を追加する**
（下記「0. AndroidManifest 受信 filter」）。これがないと画像の共有先に本アプリが表示されない。

---

## v3 追加・変更サマリー

| 項目 | 種別 | 対象ファイル |
|---|---|---|
| 受信 filter 追加（image/* 単一・複数） | 変更 | `AndroidManifest.xml` |
| 受信内容モデル `ReceivedShareContent` | 新規 | `ReceivedShareContent.kt` |
| 受信 Intent パーサ `IncomingShareParser` | 新規 | `IncomingShareParser.kt` |
| 受信内容表示画面 `ReceivedShareScreen` | 新規 | `ReceivedShareScreen.kt` |
| `MainActivity` 受信ハンドリング | 変更 | `MainActivity.kt` |
| `MainActivity` launchMode | 変更 | `AndroidManifest.xml` |
| 受信時のルーティング | 変更 | `MainRouter.kt` |
| リッチプレビュー送信ボタン（`previewThumbnailPath`） | 変更 | `ShareSampleScreen.kt` |
| コールバック文言修正 + `cancelPendingCallback` 配線 | 変更 | `ShareSampleScreen.kt` |

---

## 受信側 詳細設計

### 0. AndroidManifest 受信 filter（画像受信の整合）

完了条件で画像・複数画像の受信を求めるため、`MainActivity` に `image/*` の filter を追加する。
Direct Share の `<share-target>`（text/plain のみ）とは別物として並記する。

```xml
<!-- 既存（text 受信 + Direct Share の必須要素） -->
<intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="text/plain" />
</intent-filter>
<!-- 追加：単一画像の受信 -->
<intent-filter>
    <action android:name="android.intent.action.SEND" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="image/*" />
</intent-filter>
<!-- 追加：複数画像の受信 -->
<intent-filter>
    <action android:name="android.intent.action.SEND_MULTIPLE" />
    <category android:name="android.intent.category.DEFAULT" />
    <data android:mimeType="image/*" />
</intent-filter>
```

> Direct Share の `share-target`（shortcuts.xml）は `text/plain` のままにする。画像受信 filter の追加は
> 通常共有での受信表示のためであり、Direct Share の mimeType 方針とは分けて扱う。

---

### 1. launchMode 方針（`AndroidManifest.xml`）

`MainActivity` に `android:launchMode="singleTop"` を設定する。

```xml
<activity
    android:name=".MainActivity"
    android:exported="true"
    android:launchMode="singleTop"      <!-- 追加 -->
    android:screenOrientation="portrait"
    android:theme="@style/Theme.AppCompat">
```

理由:
- アプリ起動中に共有を受けても新規インスタンスを作らず、既存インスタンスの `onNewIntent` で受信できる
- 二重起動を防ぎ、受信内容の表示を 1 箇所に集約できる

受信は **`onCreate`（コールドスタート時の起動 intent）** と **`onNewIntent`（起動中の受信）** の両方で処理する。

---

### 2. 受信内容モデル（`ReceivedShareContent.kt`、新規）

パス: `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ReceivedShareContent.kt`

```kotlin
/**
 * Content received from another app or a Direct Share target.
 *
 * @property action Received intent action (ACTION_SEND / ACTION_SEND_MULTIPLE).
 * @property mimeType Received intent type.
 * @property text Received text (EXTRA_TEXT), or null.
 * @property streamUris Received stream URIs (EXTRA_STREAM), or empty.
 * @property shortcutId Selected Direct Share target id (EXTRA_SHORTCUT_ID); null for a normal share.
 */
data class ReceivedShareContent(
    val action: String,
    val mimeType: String?,
    val text: String?,
    val streamUris: List<android.net.Uri>,
    val shortcutId: String?
)
```

---

### 3. 受信 Intent パーサ（`IncomingShareParser.kt`、新規）

パス: `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/IncomingShareParser.kt`

`Intent` → `ReceivedShareContent?` への純粋変換。`ACTION_SEND` / `ACTION_SEND_MULTIPLE` 以外は `null`。

```kotlin
object IncomingShareParser {

    private const val TAG = "IncomingShareParser"

    /**
     * Converts a received intent to [ReceivedShareContent]; returns null if it is not a share intent.
     *
     * @param intent Received intent (nullable).
     */
    fun parse(intent: Intent?): ReceivedShareContent? {
        Log.d(TAG, "[parse] intent: $intent, action: ${intent?.action}")
        if (intent == null) return null
        val shortcutId = intent.getStringExtra(Intent.EXTRA_SHORTCUT_ID)
        return when (intent.action) {
            Intent.ACTION_SEND -> {
                // EXTRA_TEXT is a CharSequence (may be Spanned); read as CharSequence then stringify.
                val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
                val uri = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
                ReceivedShareContent(
                    action = Intent.ACTION_SEND,
                    mimeType = intent.type,
                    text = text,
                    streamUris = listOfNotNull(uri),
                    shortcutId = shortcutId
                )
            }
            Intent.ACTION_SEND_MULTIPLE -> {
                val uris = IntentCompat.getParcelableArrayListExtra(
                    intent, Intent.EXTRA_STREAM, Uri::class.java
                ) ?: arrayListOf()
                ReceivedShareContent(
                    action = Intent.ACTION_SEND_MULTIPLE,
                    mimeType = intent.type,
                    text = null,
                    streamUris = uris,
                    shortcutId = shortcutId
                )
            }
            else -> null
        }
    }
}
```

- API 差分吸収のため `androidx.core.content.IntentCompat` の `getParcelableExtra` / `getParcelableArrayListExtra` を使用する
- `EXTRA_SHORTCUT_ID` により「どの Direct Share ターゲットが選ばれたか」（例: `"sample_1"`）を取得できる

---

### 4. 受信状態の保持と受け渡し（`MainActivity.kt`、変更）

`MainActivity` が受信内容を `mutableStateOf` で保持し、Compose 側（`AppRouter`）へ公開する。

```kotlin
class MainActivity : AppCompatActivity() {

    private lateinit var notificationPermissionHelper: NotificationPermissionHelper

    /** Received share content; updated on receipt and observed by Compose to navigate to the received screen. */
    var receivedShare by mutableStateOf<ReceivedShareContent?>(null)
        private set

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        Log.d(TAG, "[onCreate] intent: $intent")
        notificationPermissionHelper = NotificationPermissionHelper(this)
        title = "Native Toolkit Example"
        enableEdgeToEdge()
        handleIncomingShare(intent)        // cold-start receipt
        setContent {
            AndroidTheme {
                AppRouter(
                    activity = this,
                    permissionHelper = notificationPermissionHelper
                )
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        Log.d(TAG, "[onNewIntent] intent: $intent")
        setIntent(intent)
        handleIncomingShare(intent)        // receipt while running
    }

    /** Parses the received intent and updates receivedShare when it is a share. */
    private fun handleIncomingShare(intent: Intent?) {
        Log.d(TAG, "[handleIncomingShare] intent: $intent")
        val received = IncomingShareParser.parse(intent)
        if (received != null) {
            receivedShare = received
        }
    }

    /** Clears the received content after it has been shown (called when leaving the received screen). */
    fun clearReceivedShare() {
        Log.d(TAG, "[clearReceivedShare]")
        receivedShare = null
    }

    companion object {
        private const val TAG = "MainActivity"
    }
}
```

> `var ... by mutableStateOf(...) private set` + 公開メソッド `clearReceivedShare()` とすることで、
> 外部からの直接代入を防ぎつつ Compose に状態変化を観測させる。

---

### 5. 受信時のルーティング（`MainRouter.kt`、変更）

#### 変更点 1: `MainScreen` enum に `RECEIVED_SHARE` を追加

```kotlin
private enum class MainScreen {
    MAIN_MENU,
    ANDROID_DIALOG_TEST,
    NOTIFICATION_TEST,
    SHARE_TEST,
    RECEIVED_SHARE          // 追加
}
```

#### 変更点 2: 受信検知で `RECEIVED_SHARE` へ自動遷移

`AppRouter` 内で `activity.receivedShare` を観測し、非 null になったら受信画面へ遷移する。

```kotlin
val received = activity.receivedShare
LaunchedEffect(received) {
    if (received != null) {
        currentScreen = MainScreen.RECEIVED_SHARE
    }
}
```

#### 変更点 3: システム Back でも受信状態をクリア

既存の共通 `BackHandler` は画面だけをメインメニューへ戻すため、受信画面では
`clearReceivedShare()` も実行する。画面内 Back ボタンとシステム Back の状態遷移を一致させる。

```kotlin
BackHandler(enabled = currentScreen != MainScreen.MAIN_MENU) {
    if (currentScreen == MainScreen.RECEIVED_SHARE) {
        activity.clearReceivedShare()
    }
    currentScreen = MainScreen.MAIN_MENU
}
```

#### 変更点 4: `RECEIVED_SHARE` のルーティング追加

```kotlin
MainScreen.RECEIVED_SHARE -> {
    ReceivedShareScreen(
        modifier = Modifier.padding(innerPadding),
        content = activity.receivedShare,
        onBack = {
            activity.clearReceivedShare()
            currentScreen = MainScreen.MAIN_MENU
        }
    )
}
```

---

### 6. 受信内容表示画面（`ReceivedShareScreen.kt`、新規）

パス: `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ReceivedShareScreen.kt`

`ShareSampleScreen` の UI パターン（Back ボタン + タイトル + 情報表示）を踏襲し、
受信内容を読み取り専用で表示する。

表示項目:

| 表示ラベル | 値 |
|---|---|
| Action | `content.action`（ACTION_SEND / ACTION_SEND_MULTIPLE） |
| MIME type | `content.mimeType` |
| Text | `content.text`（テキスト共有時） |
| Stream URIs | `content.streamUris`（件数 + 各 URI） |
| Direct Share target | `content.shortcutId`（"sample_1" = "Sample User" 選択時のみ） |

```kotlin
/**
 * Screen that displays the share content received from another app or a Direct Share target.
 *
 * @param modifier Modifier applied to the root layout.
 * @param content Received share content; shows an empty state when null.
 * @param onBack Called when the back button is tapped.
 */
@Composable
fun ReceivedShareScreen(
    modifier: Modifier = Modifier,
    content: ReceivedShareContent?,
    onBack: () -> Unit
) {
    Log.d(TAG, "[ReceivedShareScreen] content: $content")
    // Back button + "Received Share" title + the fields above listed as Text.
    // When content == null, show "No shared content received."
}

private const val TAG = "ReceivedShareScreen"
```

- 画像 URI のプレビュー表示は任意（最小実装では URI 文字列の表示で可）。
  サムネイル表示する場合は `AsyncImage` 等は導入せず、`ImageDecoder` / `contentResolver` で
  軽量に読み込む方針を整理フェーズで判断する。

---

## リッチプレビュー送信ボタン（親設計 #5、`ShareSampleScreen.kt` 変更）

セクション 1（テキスト共有）に **"Share Text with Rich Preview"** ボタンを 1 件追加する。
`previewTitle` とサムネイルを指定して Sharesheet 上部にプレビューを表示させる。

```kotlin
// Write the thumbnail PNG to cacheDir (IO), then share its file path (Main).
scope.launch(Dispatchers.IO) {
    val bmp = BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
    val file = File(context.cacheDir, "share_preview.png")
    file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    withContext(Dispatchers.Main) {
        try {
            shareUseCases.shareText(
                ShareContent(
                    text = "https://developer.android.com/",
                    mimeType = "text/plain",
                    previewTitle = "Introducing content previews"
                ),
                chooserActionsJson = "[]",
                previewThumbnailPath = file.absolutePath   // file path (parent design confirmed)
            )
            statusText = "✅ shareText (rich preview) called"
        } catch (e: ShareDomainError) {
            statusText = "❌ ${e.message}"
        } catch (e: Exception) {
            statusText = "❌ Unexpected: ${e.message}"
        }
    }
}
```

| ボタンラベル | 呼び出し |
|---|---|
| Share Text with Rich Preview | 上記擬似コードに準じて実行 |

> サムネイルは**ファイルパス**（`previewThumbnailPath = file.absolutePath`）で渡す（親設計 v3 確定）。
> `cacheDir` 配下のため既存 FileProvider `<cache-path>` でカバーされ、`fileToContentUri` がそのまま使える。

---

## コールバック文言の修正（親設計 #2、`ShareSampleScreen.kt` 変更）

`createChooser` の IntentSender は **選択時のみ**発火し、キャンセルでは呼ばれない。
v2 の `"ℹ️ Cancelled"`（= null 時）表現は実挙動と乖離するため修正する。

変更前:
```kotlin
statusText = if (pkg != null) "✅ Selected: $pkg" else "ℹ️ Cancelled"
```

変更後:
```kotlin
// onResult fires only on selection; pkg == null means selected but the package was unavailable.
statusText = if (pkg != null) {
    "✅ Selected: $pkg"
} else {
    "ℹ️ Shared (package unavailable)"
}
```

- 「キャンセル時に結果が来る」前提の文言・完了条件を削除する
- 既に `runOnUiThread` は削除済み（onReceive はメインスレッド）
- 親設計 #2 の通り、Copy/Edit では `onResult` 自体が呼ばれない（誤通知しない）

### `cancelPendingCallback` の配線（親設計 HP2/HP3）

画面破棄時に pending callback を解除する。Compose の `DisposableEffect` で配線する。

```kotlin
DisposableEffect(shareUseCases) {
    onDispose { shareUseCases.cancelPendingCallback() }
}
```

---

## 作成・変更ファイル一覧（v3）

| ファイル | 種別 | 内容 |
|---|---|---|
| `app/src/main/java/.../ReceivedShareContent.kt` | 新規 | 受信内容モデル |
| `app/src/main/java/.../IncomingShareParser.kt` | 新規 | 受信 Intent パーサ |
| `app/src/androidTest/java/.../IncomingShareParserInstrumentedTest.kt` | 新規 | 実Android Intentを使う ACTION_SEND / ACTION_SEND_MULTIPLE / Direct Share の parserテスト |
| `app/src/main/java/.../ReceivedShareScreen.kt` | 新規 | 受信内容表示画面 |
| `app/src/main/java/.../MainActivity.kt` | 変更 | `receivedShare` 状態、`onNewIntent`、`handleIncomingShare`、`clearReceivedShare` |
| `app/src/main/AndroidManifest.xml` | 変更 | `MainActivity` に `launchMode="singleTop"` + `image/*` の `ACTION_SEND` / `ACTION_SEND_MULTIPLE` 受信 filter 追加 |
| `app/src/main/java/.../MainRouter.kt` | 変更 | `RECEIVED_SHARE` 追加・受信自動遷移・ルーティング |
| `app/src/main/java/.../ShareSampleScreen.kt` | 変更 | リッチプレビュー送信ボタン（`previewThumbnailPath`）、コールバック文言修正、`DisposableEffect` で `cancelPendingCallback` |

> `ShareSampleScreen.kt` の "Result will be displayed here" 初期値・`runOnUiThread` 削除・URL 変更は適用済み。
> コード例の KDoc / コメントは英語で記述する（共通規約）。`EXTRA_TEXT` は `getCharSequenceExtra(...)?.toString()` で取得する。

---

## 自動テスト

`IncomingShareParserInstrumentedTest` で新規 parser の分岐を実Android `Intent`を使って直接検証する。
現行app moduleにはRobolectric依存がないため、local JVM testではなく`androidTest`へ配置する。

| テストケース | 確認内容 |
|---|---|
| ACTION_SEND text | CharSequence の EXTRA_TEXT を String へ変換する |
| ACTION_SEND stream | 単一 EXTRA_STREAM を 1 件の `streamUris` として返す |
| ACTION_SEND_MULTIPLE | 複数 EXTRA_STREAM を順序どおり返す |
| Direct Share | EXTRA_SHORTCUT_ID を `shortcutId` として返す |
| Unsupported action | `null` を返す |
| Null intent | `null` を返す |

システム Back は Compose UI test または手動確認で、受信画面から戻った後に
`receivedShare == null` となり受信画面へ再遷移しないことを確認する。

---

## 完了条件

### 受信側
- [ ] `MainActivity` に `launchMode="singleTop"` が設定されている
- [ ] `image/*` の `ACTION_SEND` / `ACTION_SEND_MULTIPLE` 受信 filter が `MainActivity` に追加されている
- [ ] 他アプリ（例: Chrome / ギャラリー）から「テキスト」を本アプリに共有すると、`ReceivedShareScreen` に
      action / text / mimeType が表示される
- [ ] 他アプリ（ギャラリー）から「画像」を本アプリに共有すると、本アプリが共有先に表示され `streamUris` が表示される
- [ ] 「複数画像」を共有すると `ACTION_SEND_MULTIPLE` で `streamUris`（複数）が表示される
- [ ] Direct Share の "Sample User" を他アプリで選択すると、`shortcutId = "sample_1"` が表示される
- [ ] アプリ起動中の受信（`onNewIntent`）でも受信画面に遷移する
- [ ] コールドスタート受信（`onCreate`）でも受信画面に遷移する
- [ ] 受信画面内 Back ボタンとシステム Back の両方で `clearReceivedShare` が呼ばれ、メインメニューに戻る（再表示でループしない）
- [ ] `EXTRA_TEXT` を `getCharSequenceExtra(...)?.toString()` で取得している
- [ ] `IncomingShareParser` / `ReceivedShareScreen` / `MainActivity` の全メソッドに `Log.d` がある
- [ ] public composable / 関数に KDoc がある（コメント・KDoc は英語）
- [ ] `IncomingShareParserInstrumentedTest` が text / single stream / multiple streams / shortcut ID / unsupported action / null を網羅して passed

### 送信側（v3 追加分）
- [ ] "Share Text with Rich Preview" ボタンが配置されている
- [ ] サムネイルを `previewThumbnailPath = file.absolutePath` で渡している
- [ ] 実行すると Sharesheet 上部にタイトル＋サムネイルが表示される（API 31, 35, 36）
- [ ] "Share with Callback" の文言がキャンセル前提でなくなっている
- [ ] `DisposableEffect.onDispose` で `cancelPendingCallback()` を呼んでいる

---

## 手動確認手順（end-to-end）

### 受信（通常共有）
1. 本サンプルアプリをインストール
2. Chrome で任意ページを開き「共有」→ 共有先一覧から本アプリ（Native Toolkit Example）を選択
3. 本アプリが起動し `ReceivedShareScreen` に URL テキストが表示されることを確認

### 受信（Direct Share）
1. ShareSampleScreen で "Register Direct Share Target" を実行（"Sample User" 登録）
2. 他アプリ（Chrome 等）で「共有」→ 上部の Direct Share 欄の "Sample User" を選択
3. 本アプリが起動し `shortcutId = "sample_1"` が表示されることを確認
   - 表示まで数秒のラグがある場合あり

### 受信画面の Back
1. 通常共有または Direct Share で `ReceivedShareScreen` を表示する
2. 画面内 Back ボタンで戻り、受信状態がクリアされ再表示されないことを確認する
3. 再度受信画面を表示し、システム Back でも同様に受信状態がクリアされることを確認する

### 受信（画像 / 複数画像）
1. ギャラリー等で画像を選び「共有」→ 共有先に本アプリが表示されることを確認（`image/*` filter）
2. 本アプリが起動し `ReceivedShareScreen` に `streamUris` が表示されることを確認
3. 複数画像選択時は `ACTION_SEND_MULTIPLE` で複数 URI が表示されることを確認

### 送信（リッチプレビュー）
1. ShareSampleScreen で "Share Text with Rich Preview" を実行
2. Sharesheet 上部にタイトル "Introducing content previews" とアイコンサムネイルが出ることを確認

---

## 注意事項

- **`ACTION_SEND`（text/plain）intent-filter は削除しない。** Direct Share の必須要素であり、外すと
  "Sample User" が他アプリの Sharesheet に表示されなくなる
- 画像受信 filter（`image/*`）は通常共有の受信表示用。Direct Share の `share-target` は `text/plain` のまま
- 受信処理はサンプルアプリ（利用側）にのみ実装する。`android_library` / `unity_android_plugin` には追加しない
- `singleTop` により、起動中の受信は `onNewIntent` 経由になる。`setIntent(intent)` を忘れると
  `getIntent()` が古い intent を返すため必ず呼ぶ
- 受信した content URI（`EXTRA_STREAM`）は送信元アプリが付与した一時的な read 権限でのみアクセス可能。
  画面回転等で権限が切れる可能性があるため、表示が必要なら早期に読み込む
- Unity ゲームで同等の受信を行う場合は、`UnityPlayerActivity` の intent を C# 側でハンドリングする
  （単一 Activity モデル）。本サンプルはネイティブ Activity での実装例
- リッチプレビューのサムネイルは**ファイルパス**で渡す（親設計 v3 確定。`cacheDir` 配下なら既存 FileProvider でカバー）
- `cancelPendingCallback` は `DisposableEffect.onDispose` で呼ぶ（親設計 HP2/HP3）。Unity 側は
  `clearShareOperationListener()` が pending callback も解除する（親設計 MP2）
