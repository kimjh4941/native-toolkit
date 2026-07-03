# Android シェア機能 実装設計書 v3

- 前版: artifact/designs/share/2026-05-24-android-share-implementation-v2.md
- 作成日: 2026-06-20
- 改訂日: 2026-06-20（v3: 既存実装のレビュー指摘反映 + Unity 観点の機能拡張）
- 対象OS: Android
- 対象機能: シェア機能（Share）

---

## v3 改訂目的

v1/v2 設計に基づき実装済みの share 機能を、実機検証・公式ドキュメント突合・Unity 利用観点でレビューした結果、
以下を確定する。

1. **確定バグの修正**（v2 設計に誤りが含まれていたもの）
2. **仕様の穴の明文化**（キャンセル時コールバック・Direct Share 受信側）
3. **Unity 観点での機能拡張の取捨選択**（#4〜#6 のうち #5 のみ採用）

本書は v2 からの差分を中心に記述する。記載のない項目は v2 設計を踏襲する。

---

## レビュー結論サマリー

| 番号 | 指摘 | 種別 | v3 での扱い | 根拠 |
|---|---|---|---|---|
| #1 | `ChooserResult` の API 判定が API 34 になっている | 確定バグ | 修正（34 → 35） | `ChooserResult` は API 35（Android 15）追加。公式 API 34→35 差分で確認 |
| #2 | キャンセル時に `onResult(null)` が呼ばれない | 仕様の穴 | 仕様明文化 | `createChooser` の IntentSender は「選択時のみ」発火。キャンセルでは未発火 |
| #3 | Direct Share 受信側が未実装 | 仕様確認 | ライブラリは対応不要と明文化／filter は必須として維持 | Direct Share は targetClass の `ACTION_SEND` intent-filter が必須。受信は利用側責務 |
| #4 | Direct Share 選択後の画面遷移なし | 拡張 | スコープ外（Unity 観点で不要） | Unity は単一 Activity・受信は game 側責務 |
| #5 | リッチプレビュー未対応 | 拡張 | **採用**（送信機能拡張） | スクショ/スコア共有という Unity 典型用途に直結 |
| #6 | 高度な Direct Share 管理なし | 拡張 | スコープ外（Unity では niche） | ランキング/usage reporting は SNS 向け最適化 |

---

## スコープ（v3）

### In scope（v2 から継続）
- テキスト・URL シェア
- 単一・複数画像シェア
- 単一・複数ファイルシェア（FileProvider）
- Direct Share ターゲット登録・削除
- ChooserAction（カスタムアクションボタン、API 34+）
- シェア結果コールバック

### In scope（v3 追加・修正）
- **[修正]** シェア結果コールバックの API 分岐（API 31〜34: `EXTRA_CHOSEN_COMPONENT` / **API 35+**: `ChooserResult`）
- **[追加]** リッチプレビュー（`EXTRA_TITLE` + サムネイル content URI、API 29+）

### Out of scope（v3 で明示的に除外）
- iOS / macOS / Windows のシェア API
- **受信側（Intent Filter で受け取った共有内容の処理）** — 利用側アプリ（Unity ゲーム等）の責務
- **Direct Share 選択後の画面遷移**（#4） — Unity は単一 Activity・受信側責務のため
- **高度な Direct Share 管理**（#6：ランキング・usage reporting・複数 MIME category・adaptive icon）
- サードパーティ SDK

---

## #1 シェア結果コールバックの API 分岐修正（確定バグ）

### 問題

`ChooserResult` は **API 35（Android 15 / VANILLA_ICE_CREAM）** で追加されたクラスである。
v2 設計・現行実装は API 34（UPSIDE_DOWN_CAKE）でゲートしているため、以下の不具合がある。

- **API 34（Android 14）実機**でコールバックが発火すると、存在しない `ChooserResult` を参照し
  `NoClassDefFoundError` でクラッシュする
- 意味的にも `EXTRA_CHOOSER_RESULT` が配信されるのは API 35 以降であり、API 31〜34 では
  `EXTRA_CHOSEN_COMPONENT` のみが届く（off-by-one）

### 修正内容

`ShareRepositoryImpl` のバージョン分岐閾値を `UPSIDE_DOWN_CAKE`(34) → **`VANILLA_ICE_CREAM`(35)** に変更する。

```
minSdk = 31
├── API 31〜34: EXTRA_CHOSEN_COMPONENT (ComponentName)        ← 旧 API
└── API 35+   : EXTRA_CHOOSER_RESULT (ChooserResult.selectedComponent)
```

**コールバック抽出は内部 sealed 型 `CallbackResult` を返す**（HP1 再レビュー対応）。
nullable String だけでは「選択されたが package 取得不可」と「非選択操作（Copy/Edit）」を区別できないため、
`Selected` / `Ignored` を導入し、**`Selected` のときだけ公開 callback を呼ぶ**。

**配置（第3回 HP1 対応）:** `CallbackResult` と抽出処理は、これを呼ぶ `ShareCallbackCoordinator`
（#2）と同一ファイル `ShareCallbackCoordinator.kt` に **`internal`** で置く。
`ShareRepositoryImpl` には置かない（private では別ファイルの Coordinator から参照できないため）。

```kotlin
// ShareCallbackCoordinator.kt （data layer）

// Internal result distinguishing an app selection from non-selection actions (Copy/Edit/Unknown).
internal sealed interface CallbackResult {
    data class Selected(val packageName: String?) : CallbackResult
    data object Ignored : CallbackResult
}

internal object ShareCallbackResultParser {

    fun parse(intent: Intent?): CallbackResult {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {  // API 35
            parseApi35(intent)
        } else {
            // Pre-35 callback fires only on an app selection.
            @Suppress("DEPRECATION")
            val pkg = intent?.getParcelableExtra<ComponentName>(Intent.EXTRA_CHOSEN_COMPONENT)?.packageName
            CallbackResult.Selected(pkg)
        }
    }

    @RequiresApi(Build.VERSION_CODES.VANILLA_ICE_CREAM)  // API 35
    private fun parseApi35(intent: Intent?): CallbackResult {
        val result = intent?.extras
            ?.getParcelable("android.intent.extra.CHOOSER_RESULT", ChooserResult::class.java)
            ?: return CallbackResult.Ignored
        // Only a component selection maps to a package callback. Copy/Edit/Unknown are ignored.
        return if (result.type == ChooserResult.CHOOSER_RESULT_SELECTED_COMPONENT) {
            CallbackResult.Selected(result.selectedComponent?.packageName)
        } else {
            CallbackResult.Ignored
        }
    }
}
```

`ShareCallbackCoordinator` の `onReceive` 側は `Selected` のみ通知する（#2 参照）:

```kotlin
when (val r = ShareCallbackResultParser.parse(intent)) {
    is CallbackResult.Selected -> onSelected(r.packageName)   // null = selected but package unavailable
    CallbackResult.Ignored -> Log.d(TAG, "[onReceive] non-selection action; not notifying")
}
```

**対象ファイル:**
- `android_library/.../data/repository/ShareCallbackCoordinator.kt`（新規・`CallbackResult` / `ShareCallbackResultParser` を同居、`internal`）
- 単体テスト対象も `ShareCallbackResultParser`（#2 のテスト表に統一）
- `ShareRepositoryImpl` 側の旧 `extractSelectedPackageApi34` は削除（Coordinator/Parser へ移設）

**ChooserAction（#5 とは別）の閾値は変更しない。**
`ChooserAction` / `EXTRA_CHOOSER_CUSTOM_ACTIONS` は API 34 追加で正しいため `UPSIDE_DOWN_CAKE` のまま。

### HP1: API 35 の `ChooserResult` は「選択時のみ」ではない（result type 判定）

`ChooserResult.getType()` は以下を返す。**共有先選択以外（Copy / Edit）でも callback が発火する**ため、
`selectedComponent == null` を一律「選択されたが取得不可」とみなすと Copy/Edit を誤通知する。

| type | 意味 | 本実装の扱い |
|---|---|---|
| `CHOOSER_RESULT_SELECTED_COMPONENT` | 共有先アプリを選択 | `Selected(packageName)` → 通知 |
| `CHOOSER_RESULT_COPY` | コピー操作 | `Ignored` → **通知しない** |
| `CHOOSER_RESULT_EDIT` | 編集操作 | `Ignored` → **通知しない** |
| `CHOOSER_RESULT_UNKNOWN` | 不明 | `Ignored` → **通知しない** |

- **v3 方針（API 非破壊）:** 公開 API は `onResult(String?)` のまま。`Selected` のときだけ呼び、
  `Ignored`（Copy/Edit/Unknown）では**一切呼ばない**（`onResult(null)` も呼ばない）。
  `null` は「`Selected` だが package 取得不可」のみを意味する
- **将来拡張（任意）:** Copy/Edit も公開する場合は `ShareResultType` + packageName を持つ
  ドメイン結果へ拡張する（別途設計）。本 v3 ではスコープ外

---

## #2 キャンセル時コールバックの仕様明文化

### 事実

`Intent.createChooser(target, title, IntentSender)` の IntentSender は、
**ユーザーがいずれかの共有先を選択したときのみ**発火する。Sharesheet を閉じた（キャンセル）場合は
IntentSender は呼ばれず、BroadcastReceiver も発火しない。

したがって「キャンセル時に `onResult(null)` が一度呼ばれる」ことは **OS 仕様上保証できない**。

### v3 での扱い

- `ShareRepository.shareWithCallback` の KDoc を「**共有先選択時のみ** `onResult(packageName)` を呼ぶ。
  キャンセル・Copy・Edit では呼ばれない場合がある」と修正する
- `onResult` の引数 `String?` の `null` は「選択されたが extra からパッケージ名を取得できなかった」ケースを表す
  （Copy/Edit/Unknown は HP1 の通り `onResult` 自体を呼ばない）
- サンプルアプリ・Unity ドキュメントの「キャンセル → null」表現を「結果が来ない場合がある」に修正する

### 制約（仕様上の制限）

**Android の標準 API では「Sharesheet を閉じた（キャンセル）」を確実に検知できない。** 本機能の既知の制約として記載する。

| 手段 | キャンセル検知 | 備考 |
|---|---|---|
| BroadcastReceiver コールバック（本実装で採用） | ❌ 不可 | IntentSender は**選択時のみ**発火。dismiss では `onReceive` が呼ばれない。さらに本実装は `startActivity`（forResult ではない）ためキャンセルを知るチャンネルが存在しない |
| 専用 onCancel コールバック | ❌ 存在しない | Android のシェア API に「キャンセルされた」を返す正式な API はない |
| `startActivityForResult` + `RESULT_CANCELED` | △ 間接・不安定 | dismiss で `RESULT_CANCELED` が返る場合があるが、選択コールバック（別チャンネル）とのタイミング保証がなく、OS バージョンで挙動が変わる |

- **結論:** 本機能は「**選択された**ことのみ通知し、**キャンセルされた**ことは通知しない」仕様とする
- 厳密なキャンセル検知が必要になった場合は、Sharesheet を起動する側の Activity result / ライフサイクルで
  「コールバック未着のまま復帰した」ことを観測する別設計が必要。**本 v3 ではスコープ外**（将来課題）とする

### HP2: キャンセル時に BroadcastReceiver が解除されず蓄積する（要対応・重大）

#### 問題

現行実装は `onReceive` 内でのみ Receiver を解除する。上記の通りキャンセルでは `onReceive` が
呼ばれないため Receiver が解除されず生存し続ける。Receiver の action は `${packageName}.SHARE_CALLBACK`
**固定**のため、`shareWithCallback` を繰り返すと同一 action の Receiver が蓄積し、
後続の選択で**過去のキャンセル分まで二重発火**する（古い `onResult` が呼ばれる）。

#### 所有モデルの問題（再レビュー指摘）

単一登録制御を `ShareRepositoryImpl` のフィールドに置くと **Unity 経路で成立しない**。
`UnityAndroidShareManager` は操作ごとに `ShareUseCases(context)` を呼び、factory は毎回**新しい
`ShareRepositoryImpl`** を生成する（[ShareUseCases.kt:14](android/android_library/src/main/java/android/library/share/data/repository/ShareUseCases.kt#L14)）。
新インスタンスは前回インスタンスの `pendingCallbackReceiver` を参照できず「最大 1 個」が崩れ、
`cancelPendingCallback` も別インスタンスへ委譲され無効になる。

#### 修正方針（application スコープの `ShareCallbackCoordinator`）

Receiver 登録・解除の所有を **application スコープの単一 Coordinator** に集約する。
RepositoryImpl はインスタンスが何個生成されても、同じ Coordinator に委譲するため
「Receiver は常に最大 1 個」がインスタンス数に依らず成立する。

**スレッド安全性（第3回 MP1 / 第4回 HP1 対応）:** Unity の公開 API は任意スレッドから呼ばれ得るため、
全操作を `synchronized` で直列化し、`register` は **登録トークン**を返す。
HP4 の起動失敗時は `cancel(token)` で**自分のトークンに対応する Receiver のときだけ**解除する。
Receiver 発火時も現在の `PendingRegistration` を atomic に claim できた場合だけ callback を通知し、
置換・cancel 後に遅れて届いた古い broadcast は無視する。

```kotlin
// data layer. Application-scoped single owner of the share-callback BroadcastReceiver.
// All public methods are synchronized; safe to call from any thread.
internal class ShareCallbackCoordinator(private val appContext: Context) {

    private val lock = Any()
    private data class PendingRegistration(
        val token: Long,
        val receiver: BroadcastReceiver
    )

    private var pending: PendingRegistration? = null
    private var nextToken: Long = 0L

    /** Registers a one-shot receiver, replacing any previous pending one. Returns a token for cancel(token). */
    fun register(action: String, onSelected: (String?) -> Unit): Long = synchronized(lock) {
        Log.d(TAG, "[register] action: $action")
        unregisterLocked()                       // drop the previous pending receiver first
        val token = ++nextToken
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                Log.d(TAG, "[onReceive] intent: $intent")
                val claimed = synchronized(lock) {
                    val current = pending
                    if (current?.token != token || current.receiver !== this) {
                        false
                    } else {
                        unregisterLocked()
                        true
                    }
                }
                if (!claimed) {
                    Log.d(TAG, "[onReceive] stale or cancelled registration; ignoring")
                    return
                }
                when (val r = ShareCallbackResultParser.parse(intent)) {
                    is CallbackResult.Selected -> onSelected(r.packageName)
                    CallbackResult.Ignored -> Log.d(TAG, "[onReceive] non-selection action; not notifying")
                }
            }
        }
        pending = PendingRegistration(token, receiver)
        try {
            ContextCompat.registerReceiver(
                appContext, receiver, IntentFilter(action), ContextCompat.RECEIVER_NOT_EXPORTED
            )
        } catch (e: RuntimeException) {
            // Registration failed; do not retain an unregistered pending entry.
            if (pending?.token == token) pending = null
            throw e
        }
        token
    }

    /** Unregisters only if the given token is still the current registration (HP4 launch-failure path). */
    fun cancel(token: Long) = synchronized(lock) {
        Log.d(TAG, "[cancel] token: $token")
        if (pending?.token == token) unregisterLocked()
    }

    /** Unconditionally unregisters the current pending receiver (explicit cancel / teardown). */
    fun cancel() = synchronized(lock) {
        Log.d(TAG, "[cancel]")
        unregisterLocked()
    }

    private fun unregisterLocked() {
        pending?.let {
            runCatching { appContext.unregisterReceiver(it.receiver) }
            pending = null
        }
    }

    companion object {
        private const val TAG = "ShareCallbackCoordinator"

        @Volatile private var instance: ShareCallbackCoordinator? = null

        /** Returns the application-scoped singleton (one per process). */
        fun get(context: Context): ShareCallbackCoordinator =
            instance ?: synchronized(this) {
                instance ?: ShareCallbackCoordinator(context.applicationContext).also { instance = it }
            }
    }
}
```

`ShareRepositoryImpl` は Coordinator に委譲する。**chooser 起動失敗時は自分のトークンの Receiver を解除して
再 throw**する（HP4）。

```kotlin
private val coordinator = ShareCallbackCoordinator.get(context)

override fun shareWithCallback(content: ShareContent, previewThumbnailPath: String?, onResult: (String?) -> Unit) {
    Log.d(TAG, "[shareWithCallback] content: $content")
    val callbackAction = "${context.packageName}.SHARE_CALLBACK"
    val token = coordinator.register(callbackAction, onResult)
    try {
        // build pendingIntent + ACTION_SEND + EXTRA_TITLE / preview thumbnail, then:
        startActivity(chooserIntent)
    } catch (e: Throwable) {
        coordinator.cancel(token)   // HP4: drop only this call's receiver before rethrowing
        throw e
    }
}

override fun cancelPendingCallback() {
    Log.d(TAG, "[cancelPendingCallback]")
    coordinator.cancel()
}
```

**Manager 入口の dispatch（MP1 / 第4回 MP3）:** `UnityAndroidShareManager.shareWithCallback` /
`cancelPendingShareCallback` は `executeOperationOnMain` を通し、**`executeOperation` 全体を main looper 上で実行**する。
これにより、Unity から任意スレッドで呼ばれても、処理・例外捕捉・成功失敗通知が同じ runnable 内で完結する。
main thread から呼ばれた場合は即時実行し、それ以外は `Handler(Looper.getMainLooper()).post` する。

```kotlin
private val mainHandler = Handler(Looper.getMainLooper())
private var pendingCallbackContext: Context? = null

private fun executeOperationOnMain(name: String, block: () -> Unit) {
    val task = Runnable { executeOperation(name, block) }
    if (Looper.myLooper() == Looper.getMainLooper()) task.run() else mainHandler.post(task)
}

fun shareWithCallback(context: Context, shareJson: String) {
    executeOperationOnMain(OPERATION_SHARE_WITH_CALLBACK) {
        pendingCallbackContext = context.applicationContext
        // Parse input and invoke ShareUseCases(context).shareWithCallback(...).
        // Clear pendingCallbackContext in the selection callback before notifying the listener.
    }
}
```

Coordinator 自体も `synchronized` で二重に保護する。

- 効果: Receiver は **プロセス全体で常に最大 1 個**。Unity（毎回新 Repository・任意スレッド）でも成立
- HP4: 起動失敗時はトークン一致時のみ解除し、後続呼び出しの Receiver を巻き込まない
- 第4回 HP1: 置換・明示 cancel 後に古い broadcast が queue から届いても、pending を claim できず通知しない
- 残存制約: キャンセル直後〜次回開始 or `cancelPendingCallback()` までの間は Receiver が 1 個生存する
  （`applicationContext` 登録のため自動解除されない）

#### HP3: `cancelPendingCallback` の UseCase / suite 追加（アーキ規約遵守）

「Manager → UseCase → Repository」規約に従い、解除操作にも UseCase を設ける。

- `application/usecase/CancelPendingShareCallbackUseCase.kt`（新規、`operator fun invoke()` → `repository.cancelPendingCallback()`）
- `ShareUseCases` suite に `cancelPendingCallback = CancelPendingShareCallbackUseCase(repository)` を追加
- `UnityAndroidShareManager` に operation `cancelPendingShareCallback`（`OPERATION_CANCEL_PENDING_SHARE_CALLBACK`）を追加し、
  `ShareUseCases(context).cancelPendingCallback()` を薄く委譲

#### cleanup 呼び出しタイミング（第3回 MP2 対応・確定）

| 経路 | 呼び出し点 |
|---|---|
| サンプルアプリ（Compose） | `DisposableEffect(shareUseCases) { onDispose { shareUseCases.cancelPendingCallback() } }` |
| Unity | `shareWithCallback` 開始時に `pendingCallbackContext = context.applicationContext` を保持する。**`clearShareOperationListener()` は main looper 上で、この context から `ShareUseCases(context).cancelPendingCallback()` を実行してから context と listener をクリアする**。これが単一の teardown 入口 |

- `clearShareOperationListener()` が cancel も担うことで「C# が別 API を必ず呼ぶ」前提を排除する
- 明示的に pending callback だけ解除したい場合の `cancelPendingShareCallback` operation も別途公開する
- callback 選択結果を受け取った場合も `pendingCallbackContext = null` にして、完了済み context を保持しない

```kotlin
fun clearShareOperationListener() {
    runOnMain {
        pendingCallbackContext?.let { ShareUseCases(it).cancelPendingCallback() }
        pendingCallbackContext = null
        shareOperationListener = null
    }
}

private fun runOnMain(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) block() else mainHandler.post(block)
}
```

**Port 追加:** `fun cancelPendingCallback()`

**対象ファイル:**
- `android_library/.../application/port/ShareRepository.kt`（KDoc + `cancelPendingCallback`）
- `android_library/.../application/usecase/ShareWithCallbackUseCase.kt`（KDoc）
- `android_library/.../application/usecase/CancelPendingShareCallbackUseCase.kt`（新規）
- `android_library/.../application/usecase/ShareUseCases.kt`（`cancelPendingCallback` suite 追加）
- `android_library/.../data/repository/ShareCallbackCoordinator.kt`（新規・application スコープ Receiver 所有 + `CallbackResult` / `ShareCallbackResultParser` 同居 / `synchronized` + token）
- `android_library/.../data/repository/ShareRepositoryImpl.kt`（Coordinator 委譲・HP4 token 解除。旧 `extractSelectedPackageApi34` 削除）
- `unity_android_plugin/.../share/UnityAndroidShareManager.kt`（`cancelPendingShareCallback` operation 委譲・main looper dispatch・`clearShareOperationListener` で cancel も実行）
- サンプルアプリ `ShareSampleScreen.kt`（status 文言 / `DisposableEffect` で `cancelPendingCallback`）

---

## #3 Direct Share 受信側の責務分界（仕様確認）

### 事実

公式仕様上、Direct Share ターゲットを機能させるには以下が**セットで**必要。

1. `res/xml/shortcuts.xml` の `<share-target>`（`targetClass` / `data` mimeType / `category`）
2. **`targetClass` Activity の `ACTION_SEND` intent-filter（必須）**
3. `ShortcutManagerCompat.pushDynamicShortcut` による動的ショートカット登録（= `registerDirectShareTarget`）

選択時、システムは `targetClass` に `ACTION_SEND` + `EXTRA_SHORTCUT_ID` を配信する。

### 責務分界（確定）

| レイヤー | 受信処理 | 判断 |
|---|---|---|
| `android_library` / `unity_android_plugin` | **実装しない** | 受信後の遷移・内容利用はアプリ固有。ライブラリの責務外（現状維持で正しい） |
| 利用側アプリ（Unity ゲーム / サンプルアプリ） | アプリが実装 | `ACTION_SEND` を受け取り任意処理。Unity では C# 側で intent をハンドリング |

### サンプルアプリの注意（重要）

- `ACTION_SEND` intent-filter は **Direct Share の必須要素**であり、**外してはならない**
  （外すと "Sample User" が Sharesheet に表示されなくなる）
- 現状サンプルの `MainActivity` は受信 intent を処理していないため、Direct Share 選択時は
  アプリが起動するのみ。これは「ライブラリのデモ」としては許容。end-to-end デモを示す場合のみ、
  サンプル側で `EXTRA_SHORTCUT_ID` / `EXTRA_TEXT` を読んで表示する最小実装を任意で追加する

**対象ファイル:** ライブラリ側コード変更なし。ドキュメント / サンプル方針のみ。

---

## #5 リッチプレビュー（新規・Unity 主眼）

### 目的

Unity ゲームの典型用途（**スクリーンショット・スコア・実績の共有**）で、Sharesheet 上部に
タイトル＋サムネイルを表示し UX を向上させる。送信機能への純粋な追加で、Unity / ネイティブ共通で利用可能。

### 仕様（公式準拠）

リッチプレビューは **Android 10（API 29）以降**で利用可能（minSdk 31 のため常に利用可）。

- **タイトル:** `Intent.EXTRA_TITLE` に文字列を設定
- **サムネイル:** `Intent.data` に画像の content URI（FileProvider 経由）を設定し、
  `Intent.FLAG_GRANT_READ_URI_PERMISSION` を付与

```kotlin
// Thumbnail is optional: if conversion fails, continue sharing the body without a preview (HP4).
val previewThumbnailUri: Uri? = resolveOptionalPreviewUri(previewThumbnailPath)

Intent(Intent.ACTION_SEND).apply {
    type = content.mimeType
    putExtra(Intent.EXTRA_TEXT, content.text)
    content.subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }

    // --- リッチプレビュー（任意） ---
    content.previewTitle?.let { putExtra(Intent.EXTRA_TITLE, it) }
    previewThumbnailUri?.let {
        data = it                                       // content:// (FileProvider)
        addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
}
```

### HP4: 不正なサムネイルパスの fallback

サムネイルは**任意**であり、パスが不正でも**本文共有は成功させる**（プレビューだけ落とす）。
再利用予定の `fileToContentUri` は `FileNotFound` / `IllegalFileAccess` を throw するため、
**サムネイル変換専用のラッパ** `resolveOptionalPreviewUri` でこれらだけを握り、null 化する。

```kotlin
/** Converts an optional preview thumbnail path to a content URI; returns null (with a warning) if not convertible. */
private fun resolveOptionalPreviewUri(path: String?): android.net.Uri? {
    if (path.isNullOrBlank()) return null
    return try {
        fileToContentUri(path)
    } catch (e: ShareDomainError.FileNotFound) {
        Log.w(TAG, "[resolveOptionalPreviewUri] thumbnail not found: $path"); null
    } catch (e: ShareDomainError.IllegalFileAccess) {
        Log.w(TAG, "[resolveOptionalPreviewUri] thumbnail not shareable: $path"); null
    }
}
```

- **握るのはサムネイル変換のエラーのみ**。本文 Intent の組み立て・`startActivity` 失敗
  （`NoShareTarget` 等）は従来通り throw し、握りつぶさない
- テスト: 「不正パス → プレビューなしで `repository.shareText` 相当が成功」「正常パス → URI + grant flag 付与」を追加

### 設計方針

- **テキスト・URL シェア（`shareText` / `shareWithCallback`）に対するオプション**として追加する
- **適用範囲は text/URL シェアのみ**（論点 #2 確定）。画像/ファイルシェアは OS が自動でプレビューを
  生成するため、プレビュー指定は設けない
- **サムネイルは「ファイルパス」で受け取る**（論点 #1 確定）。既存 `shareImage` と同一経路で
  `FileProvider.getUriForFile` により content URI 化する（`<cache-path>` は既存 `file_paths.xml` を流用）。
  これにより Base64→cache 書き出し・クリーンアップ（論点 #3）は**不要**になる
- `previewTitle`（プレーン String）は `title` / `subject` と同列の表示属性として Domain 型 `ShareContent`
  に持たせる。サムネイルは Android 変換を伴うため `ShareContent` に含めず、`shareText` の別引数として渡す

### データ構造変更（確定）

```kotlin
// Domain: ShareContent にプレビュータイトルを追加（title/subject と同列）
data class ShareContent(
    val text: String,
    val title: String? = null,
    val subject: String? = null,
    val mimeType: String = "text/plain",
    val previewTitle: String? = null          // ← 追加（EXTRA_TITLE）
)
```

```kotlin
// Bridge: UnityShareTextSpec にプレビュー入力を追加
data class UnityShareTextSpec(
    val text: String,
    val title: String? = null,
    val subject: String? = null,
    val mimeType: String = "text/plain",
    val chooserActions: List<UnityChooserActionSpec> = emptyList(),
    val previewTitle: String? = null,           // ← 追加（EXTRA_TITLE）
    val previewThumbnailPath: String? = null    // ← 追加（ファイルパス。FileProvider で content URI 化）
)
// JSON: { "text": "...", "previewTitle": "...", "previewThumbnailPath": "..." }
```

> Unity 側はスクリーンショット等を既にディスク（`persistentDataPath`）に保存しているため、
> そのファイルパスをそのまま渡せる。`shareImage` の `filePath` と一貫した入力形式。

### Port 変更（確定）

```kotlin
// サムネイルは ShareContent に含めず、RepositoryImpl 内で path → FileProvider content URI 変換
fun shareText(content: ShareContent, chooserActionsJson: String = "[]", previewThumbnailPath: String? = null)
fun shareWithCallback(content: ShareContent, previewThumbnailPath: String? = null, onResult: (String?) -> Unit)
```

**対象ファイル:**
- `android_library/.../domain/model/ShareContent.kt`（`previewTitle` 追加）
- `android_library/.../application/port/ShareRepository.kt`（`shareText` / `shareWithCallback` 引数）
- `android_library/.../application/usecase/ShareTextUseCase.kt`, `ShareWithCallbackUseCase.kt`
- `android_library/.../data/repository/ShareRepositoryImpl.kt`（EXTRA_TITLE / サムネイル path→URI 化、既存 `fileToContentUri` 再利用）
- `unity_android_plugin/.../share/UnityShareSpecs.kt`（`previewTitle` / `previewThumbnailPath`）
- `unity_android_plugin/.../share/UnityShareJsonParser.kt`（パース追加）
- `unity_android_plugin/.../share/UnityAndroidShareManager.kt`（受け渡し）

---

## #4 / #6 スコープ外の根拠（Unity 観点）

| 項目 | 不採用理由 |
|---|---|
| #4 Direct Share 選択後の画面遷移 | Unity は単一 Activity（`UnityPlayerActivity`）で、画面遷移はエンジン内（C#）が担う。受信 intent のルーティングは game 側責務であり、ツールキットでは対応できない・すべきでない。Direct Share 自体がゲームでは用途限定的 |
| #6 高度な Direct Share 管理（ランキング / `reportShortcutUsed` / 複数 MIME category / adaptive icon） | Direct Share を多用する SNS / メッセージアプリ向けの最適化。ゲームでは niche で投資対効果が低い |

> **注:** 下記 #7 の quota 事前チェック撤廃は #6（高度な管理）ではなく、**in-scope の登録・更新の正しさ**に関わる
> 既存不具合修正である。

---

## #7 Direct Share 登録の quota 事前チェック撤廃（既存不具合修正・MP2）

### 問題

現行実装は登録前に手動で上限判定し、超過時は `DirectShareRegistrationFailed("quota_exceeded")` を throw する。

```kotlin
val maxCount = ShortcutManagerCompat.getMaxShortcutCountPerActivity(context)
val currentCount = ShortcutManagerCompat.getDynamicShortcuts(context).size
if (currentCount >= maxCount) throw ShareDomainError.DirectShareRegistrationFailed("quota_exceeded")
```

これには 2 つの誤りがある。

1. **同一 ID の更新まで拒否する。** `pushDynamicShortcut` は同一 ID があれば**更新**（件数は増えない）だが、
   事前チェックは件数だけ見るため、上限到達後は既存ターゲットの更新すら失敗させる
2. **`pushDynamicShortcut` の自動退避と二重制御になる。** AndroidX 仕様上、上限到達時 `pushDynamicShortcut` は
   **最低ランクの非ピン留め動的ショートカットを自動削除**して新規を登録する。事前チェックはこれを潰す

### 修正方針

- **手動の `currentCount >= maxCount` 事前チェックを撤廃**する
- `pushDynamicShortcut` の戻り値・例外のみでエラー判定する
  - 戻り値 `false`（レート制限等）→ `DirectShareRegistrationFailed("push_failed")`
  - `IllegalArgumentException` 等 → `DirectShareRegistrationFailed(reason)`
- `DirectShareRegistrationFailed("quota_exceeded")` の発生箇所がなくなるため、
  エラーコード表から該当行を整理（または push 失敗の一般ケースに統合）する

**対象ファイル:**
- `android_library/.../data/repository/ShareRepositoryImpl.kt`（`registerDirectShareTarget` の事前チェック削除）
- エラーコード表 / DoD の `quota_exceeded` 記述を更新

---

## テスト設計（v3 差分）

### 単体テスト 追加・変更

| テストケース | 対象 | 確認内容 |
|---|---|---|
| **[追加]** previewTitle パース | `UnityShareJsonParser` | `previewTitle` / `previewThumbnailPath` が正しくマッピングされる |
| **[追加]** previewTitle なしのパース | `UnityShareJsonParser` | 未指定時 null で処理される |
| **[追加]** リッチプレビュー付きシェア | `ShareTextUseCase` | `previewTitle` を含む `content` で `repository.shareText` が呼ばれる |
| **[追加]** コールバック抽出移設追従 | 既存 `ShareUseCasesTest` 等 | `extractSelectedPackageApi34` 撤去・`ShareCallbackResultParser` 移設後も既存テストが passed |

#### MP3: 主要修正点を直接検証するテスト

API レベル依存・OS 連携部分は **Android API をラップした parser/coordinator を単体テスト**するか、
**instrumented test（API 34 / 35 / 36）** で検証する。「手動寄り」の曖昧記述は廃止する。

| テストケース | 対象 | 確認内容 |
|---|---|---|
| **[HP1]** result = SELECTED_COMPONENT | `ShareCallbackResultParser` | `CallbackResult.Selected(packageName)` を返す |
| **[HP1]** result = COPY / EDIT / UNKNOWN | `ShareCallbackResultParser` | `CallbackResult.Ignored` を返し `onResult` を呼ばない |
| **[HP1]** API 31〜34 経路 | `ShareCallbackResultParser` | `EXTRA_CHOSEN_COMPONENT` から `Selected(packageName)` を返す |
| **[MP1]** 並行 register/cancel | `ShareCallbackCoordinator` | `synchronized` で競合せず、token 不一致の `cancel(token)` は他呼び出しの Receiver を解除しない |
| **[HP2]** Coordinator 単一登録 | `ShareCallbackCoordinator` | `register` 連続呼び出しで前回 Receiver が解除される（常に最大1個） |
| **[第4回 HP1]** 置換後の stale broadcast | `ShareCallbackCoordinator` | 古い Receiver の `onReceive` が遅れて実行されても callback を通知しない |
| **[第4回 HP1]** cancel 後の queued broadcast | `ShareCallbackCoordinator` | 明示 cancel 後に旧 `onReceive` が実行されても callback を通知しない |
| **[HP2]** Unity 経路でも単一 | `ShareCallbackCoordinator` | RepositoryImpl を複数生成しても同一 Coordinator を共有し蓄積しない |
| **[HP2]** 二重発火しない | `ShareCallbackCoordinator` | キャンセル後再実行で選択時に 1 回だけ通知（過去分が発火しない） |
| **[HP2]** `cancelPendingCallback` | `CancelPendingShareCallbackUseCase` / Coordinator | 呼び出し後に Receiver が解除され以降通知されない |
| **[HP4]** chooser 起動失敗で Receiver 解除 | `ShareRepositoryImpl` | `startActivity` が `NoShareTarget` で失敗時、Receiver を解除してから再 throw |
| **[HP4]** 不正サムネイルパス | `ShareRepositoryImpl` | プレビューなしで本文共有が成功する（例外を投げない） |
| **[HP4]** 正常サムネイルパス | `ShareRepositoryImpl` | `data` に content URI、`FLAG_GRANT_READ_URI_PERMISSION` が付与される |
| **[HP3]** cancel UseCase 委譲 | `CancelPendingShareCallbackUseCase` | `repository.cancelPendingCallback` が 1 回呼ばれる |
| **[第4回 HP2]** listener cleanup ownership | `UnityAndroidShareManager` | 保持した application context で cancel してから context / listener をクリアする |
| **[第4回 MP3]** main looper dispatch | `UnityAndroidShareManager` | background thread 呼び出しでも main 上の `executeOperation` が成功・失敗を一度だけ通知する |
| **[MP2]** 上限到達時の同一 ID 更新 | `ShareRepositoryImpl` | 事前チェック撤廃により上限到達後も同一 ID 更新が成功する |
| **[MP2]** push 失敗 | `ShareRepositoryImpl` | `pushDynamicShortcut` が false で `DirectShareRegistrationFailed("push_failed")` を throw |

### 統合テスト（Instrumented Test）

| テストケース | 確認内容 | 確認 API バージョン |
|---|---|---|
| コールバック result type 統合 | 選択 / Copy / Edit を実機で発火させ通知有無を確認 | API 34, 35, 36 |
| Receiver 蓄積なし | キャンセル→再共有→選択で二重発火しない | API 31, 34, 35, 36 |
| preview URI grant | サムネイル付き共有で受信側が URI を読める | API 31, 35, 36 |

### 手動確認項目（v3 差分）

| 項目 | 確認内容 | 確認 API バージョン |
|---|---|---|
| **[変更]** コールバック（旧 API） | 選択アプリのパッケージ名が返る | API 31, 34 |
| **[変更]** コールバック（新 API） | `ChooserResult` の `SELECTED_COMPONENT` 時のみパッケージ名が返る | **API 35, 36** |
| **[追加]** コールバック Copy/Edit | Copy/Edit 操作では `onResult` が呼ばれない（誤通知しない） | **API 35, 36** |
| **[変更]** コールバック キャンセル | キャンセル時は結果が来ない（クラッシュしない） | API 31, 34, 35, 36 |
| **[追加]** Receiver 蓄積なし | キャンセル→再共有→選択で `onResult` が 1 回だけ呼ばれる | API 31, 34, 35, 36 |
| **[追加]** リッチプレビュー（タイトル） | Sharesheet 上部にタイトルが表示される | API 31, 35, 36 |
| **[追加]** リッチプレビュー（サムネイル） | Sharesheet 上部に画像サムネイルが表示される | API 31, 35, 36 |
| **[追加]** Direct Share 受信 filter | filter ありで "Sample User" が他アプリの Sharesheet に表示される | API 31, 34 |

---

## リスクと緩和策（v3 差分）

| リスク | 詳細 | 緩和策 |
|---|---|---|
| **ChooserResult API 35 誤用（再発防止）** | 閾値を API 34 にすると API 34 実機で `NoClassDefFoundError` | 閾値を `VANILLA_ICE_CREAM`(35) に固定。レビュー観点に「ChooserResult=35, ChooserAction=34」を明記 |
| **API 35 callback の誤通知（HP1）** | Copy/Edit を選択と誤認し packageName を返す | `ChooserResult.type == SELECTED_COMPONENT` のときだけ通知。Copy/Edit/Unknown は通知しない |
| **Receiver 蓄積・二重発火（HP2）** | キャンセルで Receiver が解除されず、後続選択で過去分まで発火 | application スコープ `ShareCallbackCoordinator` が単一所有（新規開始時に前回解除）。Unity の毎回新 Repository 生成でも成立。+ `cancelPendingCallback` 明示解除 API |
| **stale / queued broadcast 誤通知（第4回 HP1）** | 置換・cancel 前に queue された旧 Receiver が後から callback を通知する | nullable `PendingRegistration` を token + receiver identity で atomic claim し、claim 失敗時は通知しない |
| **callback 結果型の表現不足（HP1 再）** | nullable String では Copy/Edit と「選択だが取得不可」を区別できず `onResult(null)` 誤通知 | 内部 sealed 型 `CallbackResult`（`Selected`/`Ignored`）。`Selected` のみ通知 |
| **chooser 起動失敗で Receiver 残存（HP4 再）** | register 後 `startActivity` 失敗で Receiver が残る | 起動を try/catch し失敗時に `coordinator.cancel()` してから再 throw |
| プレビューサムネイルの URI 権限 | content URI に read 権限を付与し忘れるとプレビュー非表示 | `FLAG_GRANT_READ_URI_PERMISSION` 付与を必須化。`getUriForFile`（既存 `fileToContentUri` 再利用） |
| プレビューサムネイルの不正パス | 存在しないパスを渡すと URI 化失敗 | 既存の `FileNotFound` / `IllegalFileAccess` エラー経路を流用。サムネイルは任意のため、変換失敗時はプレビューなしで送信続行する（共有自体は失敗させない） |
| Direct Share filter 誤削除 | filter を外すと Direct Share が全停止 | filter は必須要素として設計書・サンプルに明記（#3） |

---

## Definition of Done（v3）

- [ ] シェア結果コールバックが **API 31〜34** で `EXTRA_CHOSEN_COMPONENT` を通じて動作する
- [ ] シェア結果コールバックが **API 35+** で `ChooserResult` を通じて動作する
- [ ] **API 34 実機でコールバック発火時にクラッシュしない**（NoClassDefFoundError 解消）
- [ ] **API 35 で Copy/Edit を選択と誤認しない**（内部 `CallbackResult.Selected` 時のみ通知。`onResult(null)` も呼ばない / HP1）
- [ ] **Receiver が蓄積せず二重発火しない**（application スコープ `ShareCallbackCoordinator` で単一所有。Unity 経路でも成立 / HP2）
- [ ] **chooser 起動失敗時に Receiver が解除される**（try/catch → `coordinator.cancel(token)` → 再 throw / HP4）
- [ ] **`cancelPendingCallback` が UseCase 経由で動作する**（`CancelPendingShareCallbackUseCase` + suite 登録 + Unity operation / HP3）
- [ ] **`CallbackResult` / `ShareCallbackResultParser` が `ShareCallbackCoordinator.kt` に `internal` で配置される**（第3回 HP1）
- [ ] **Coordinator が thread-safe**（`synchronized` + token）で、Manager 入口が main looper へ dispatch する（MP1）
- [ ] **置換・cancel 後の stale / queued broadcast が callback を通知しない**（atomic claim / 第4回 HP1）
- [ ] **`clearShareOperationListener()` が保持済み application context を使って pending callback を解除してから listener をクリアする**（MP2 / 第4回 HP2）
- [ ] **main looper 上の `executeOperation` 内で例外捕捉と成功失敗通知が完結する**（第4回 MP3）
- [ ] キャンセル時にクラッシュせず、結果未着が許容される（KDoc / 文言が実挙動と一致）
- [ ] リッチプレビューのタイトルが Sharesheet に表示される（API 31, 35, 36）
- [ ] リッチプレビューのサムネイルが Sharesheet に表示される（API 31, 35, 36）
- [ ] **サムネイルパスが不正でも共有自体は成功する**（プレビューなしで送信続行 / HP4）
- [ ] **Direct Share 登録の quota 事前チェックを撤廃し、上限到達後も同一 ID 更新が成功する**（MP2）
- [ ] Direct Share の `ACTION_SEND` intent-filter がサンプルに維持され、"Sample User" が表示される
- [ ] `UnityShareJsonParser` のプレビュー入力テスト（`previewThumbnailPath`）が passed
- [ ] HP1/HP2/HP4/MP2 を直接検証する単体 or instrumented テストが passed（MP3、API 35/36 含む）
- [ ] `ShareCallbackResultParser` 移設後も既存テストが passed
- [ ] #4 / #6 がスコープ外として設計書に明記されている

---

## 整理フェーズ確定事項（v3 fix 済み）

| # | 論点 | 確定 |
|---|---|---|
| 1 | サムネイルの保持場所・入力形式 | **ファイルパス**で受け取り、`shareText` の別引数として渡す。`previewTitle`(String) のみ `ShareContent` に保持。`shareImage` と同一の FileProvider 変換経路を再利用 |
| 2 | 画像/ファイルシェア時のプレビュー | **設けない**。OS が自動生成するため。リッチプレビューは text/URL シェア限定 |
| 3 | サムネイル cache 命名・クリーンアップ | **不要**（消滅）。パス受け取りにより cache 書き出しが発生しない。サムネイルファイルは呼び出し側の所有 |
| 4 | キャンセル検知の別設計 | **将来課題（スコープ外）**。必要時に Activity result 観測で別設計。本 v3 では「キャンセル時は結果未着」を許容仕様とする |
| 5 | callback parser 移設 | **`ShareCallbackResultParser.parseApi35`** に `@RequiresApi(VANILLA_ICE_CREAM)` を付与し、Coordinator と同じファイルへ配置。既存テストを追従させる |

## レビュー反映

### 第1回（`2026-06-20-android-share-design-review.md`）

| 指摘 | 反映先 |
|---|---|
| HP1 API 35 callback の result type | #1・#2 |
| HP2 Receiver 蓄積・二重発火 | #2 |
| HP4 不正サムネイルパスの fallback | #5（`resolveOptionalPreviewUri`） |
| MP2 quota 事前チェック不具合 | #7（事前チェック撤廃） |
| MP3 テストが修正点を直接検証しない | テスト設計 |

### 第2回再レビュー（`2026-06-20-android-share-design-review-v2.md`）

| 指摘 | 反映先 |
|---|---|
| HP1再 Copy/Edit でも `onResult(null)` を呼ぶ | #1（内部 sealed 型 `CallbackResult`、`Selected` のみ通知） |
| HP2再 単一 Receiver 制御が Unity で不成立 | #2（application スコープ `ShareCallbackCoordinator` に所有を集約） |
| HP3再 cancel に UseCase がなくアーキ規約違反 | #2（`CancelPendingShareCallbackUseCase` + suite + Unity operation） |
| HP4再 chooser 起動失敗時の Receiver 解除なし | #2（try/catch → `coordinator.cancel()` → 再 throw） |
| MP cleanup 呼び出しタイミング曖昧 | #2（サンプル=`DisposableEffect.onDispose` / Unity=teardown） |
| LP 親コード例の日本語コメント | コード例を英語コメントへ修正 |

### 第3回レビュー（`2026-06-20-android-share-design-review-v3.md`）

| 指摘 | 反映先 |
|---|---|
| HP1 `CallbackResult`/parser の配置矛盾 | #1（`ShareCallbackCoordinator.kt` に `internal` 同居、`ShareCallbackResultParser`） |
| MP1 Coordinator の thread safety 未強制 | #2（`synchronized` + 登録 token + Manager の main looper dispatch） |
| MP2 Unity cleanup 実装点が曖昧 | #2（`clearShareOperationListener()` が cancel も実行） |
| MP3 API 36 が確認マトリクスにない | テスト設計・手動確認に API 36 追加 |
| LP1 DoD に旧関数名 | DoD を `ShareCallbackResultParser` 移設表記に統一 |
| LP2 レビュー反映の LP2 重複 | 重複行を削除 |
| HP2 サンプル設計が未反映 | サンプル設計v3へ反映済み（下記） |

**サンプル設計 v3 へ反映済み:**
- 画像受信の Manifest 不整合（`image/*` の `ACTION_SEND` / `ACTION_SEND_MULTIPLE` filter 追加。作成・変更ファイル一覧にも含める）
- `previewThumbnailBase64` / `file.toBase64()` → `previewThumbnailPath = file.absolutePath` 追従、画像受信完了条件と Manifest の整合
- `EXTRA_TEXT` を `getStringExtra` → `getCharSequenceExtra(...)?.toString()` に変更
- コード例の KDoc/コメントを英語化
- `cancelPendingCallback` を `DisposableEffect.onDispose` で配線

### 第4回レビュー（`2026-06-20-android-share-design-review-v4.md`）

| 指摘 | 反映先 |
|---|---|
| HP1 stale / queued broadcastがcallbackを実行 | #2（nullable `PendingRegistration`のatomic claim。claim失敗時は通知しない） |
| HP2 `clearShareOperationListener`からcancel所有へ到達不能 | #2（`pendingCallbackContext`を保持し、clear時にUseCase経由でcancel） |
| HP3 システムBackでreceivedShare未clear | サンプル設計v3（共通`BackHandler`でclear後に遷移） |
| MP3 main dispatchと同期executeOperationの不整合 | #2（`executeOperationOnMain`のrunnable内で処理・例外・通知を完結） |
| MP4 IncomingShareParserの自動テスト不足 | サンプル設計v3（`androidTest`のinstrumented parserテスト） |
| LP1 旧callback関数名 | 整理フェーズ表を`ShareCallbackResultParser.parseApi35`へ統一 |

> 親設計v3とサンプルアプリ設計v3は、第4回レビューまでの指摘を反映済み。
