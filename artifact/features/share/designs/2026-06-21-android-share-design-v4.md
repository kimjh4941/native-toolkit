# 実装設計: Android Share v4 — Unity 向けカスタムチューザーアクション受信経路

- 対象モジュール: `android/unity_android_plugin`
- 対象 OS: Android 12 以降（minSdk 31。カスタムチューザーアクションは API 34 以降）
- 作成日: 2026-06-21
- 種別: 機能追加（Unity Bridge への新規コールバック経路）
- 改訂: v4（設計レビュー反映済み — 高 4 / 中 5 / 低 1）
- レビュー: `artifact/reviews/share/2026-06-21-android-share-design-review.md`
- 関連: `artifact/designs/share/2026-06-20-android-share-design-v3.md`, `artifact/plans/share/2026-05-23-android-share-research-v2.md`

---

## 対象企画書 / 前提の出所

- 専用の企画書ファイルは無い。本設計の前提は会話で確定した方針に基づく。
- 確定方針（ユーザー合意済み）:
  - **ライブラリ（`android_library`）は変更しない**
  - カスタムアクションの識別は **`intentAction` 文字列**で行う（ライブラリは識別用 extra を付与しないため）
  - 受信は **動的 `registerReceiver`**（manifest 宣言を避け、Unity が渡す任意 action に対応）
- 既存の通知側パターン（`NotificationActionReceiver` + listener interface）を踏襲する。

---

## 設計目的

- API 34+ の Sharesheet カスタムチューザーアクションが**タップされたこと**を、Unity(C#) 側へ通知できるようにする。
- 現状、Unity 側にはカスタムアクションのタップを受け取る経路が無い（`ShareOperationListener` は操作成否と `shareWithCallback` の選択パッケージ名のみ）。
- ネイティブ側（`AndroidLibraryExample`）は `BroadcastReceiver` を自前登録すれば受信できるが、Unity 側には同等の手段が無いギャップを埋める。

---

## スコープ

### in

- `unity_android_plugin` に share カスタムアクション受信用の**動的 BroadcastReceiver** を追加する。
- Unity へ通知する **`ShareChooserActionListener`** インターフェースと、その登録/解除 API を `UnityAndroidShareManager` に追加する。
- `shareText` 実行時、API 34+ かつ `chooserActions` が非空のとき、当該 `intentAction` 群を対象に受信登録する。
- 受信登録の**世代（session）管理**: 失敗時 cleanup、再登録による置換、解除。
- listener/register/unregister の **main looper 上での直列化**と **callback 境界の例外封じ込め**。

### out

- `android_library` の変更（ライブラリは不変）。
- ライブラリ側 PendingIntent への識別 extra 追加（破壊的変更回避のため行わない）。
- カスタムアクションの生成数や上限の変更（Android 仕様の最大 5 個に従う）。
- iOS / macOS / Windows 側の対応。
- サンプルアプリ（`AndroidLibraryExample`）の UI 実装詳細（別途 design-sample-app で扱う。本設計ではタスクのみ定義）。
- `docs/` 配下。

---

## 共通実装方針の適用チェック（common.md 準拠）

| 項目 | 適合 | 補足 |
|---|---|---|
| Clean Architecture 層・依存方向 | 適合 | 本機能は OS ブロードキャストの受信（Presentation/Manager 相当の関心事）。ドメイン操作ではないため UseCase を経由しない。既存 `NotificationActionReceiver` と同一の扱い |
| Manager → UseCase → Repository 経路 | 該当なし | 受信経路はライブラリの share 操作を呼ばない。ライブラリ API は一切経由しない |
| Delegate/Listener の所有権 | 適合 | listener は `UnityAndroidShareManager`（Manager 層）の 1 オブジェクトのみが保持する。RepositoryImpl・他 Bridge クラスには実装しない |
| エラー変換方針 | 適合（限定的） | 新規ドメインエラーは無い。受信登録の失敗は Bridge 内で try/catch + ログ、Unity へは伝播しない（ベストエフォート。公開契約で明記） |
| Unity Bridge は薄く保つ | 適合 | receiver は `intent.action` を Manager 経由で listener へ素通し。ビジネスロジックを持たない |
| Minimum OS（Android 12+） | 適合 | 受信登録は API 34+ のみ有効化（カスタムアクション自体が API 34+ 限定のため） |

## 個別実装方針の適用チェック（android.md 準拠）

| 項目 | 適合 | 補足 |
|---|---|---|
| 全メソッド先頭の `Log.d`（全パラメータ） | 適合 | 新規 `onReceive` / public・internal 関数すべてに付与 |
| エラーは `Log.e` | 適合（1 例外を明記） | 登録失敗・listener 例外は `Log.e`。**未登録 receiver の二重解除（`IllegalArgumentException`）は想定内の良性事象のため `Log.w`** とする（規約への明示的な例外。理由を下記詳細設計に記載） |
| `TAG = "FullClassName"` | 適合 | `android.unity.share.ShareChooserActionReceiver` / `android.unity.share.AndroidShareChooserActionReceiverRegistry`（full class name） |
| public 要素の KDoc | 適合 | 新規 interface / public 関数に付与（コメントは英語、common.md 準拠） |
| `override fun` は KDoc 不要 | 適合 | `onReceive` には付けない |

---

## 既存実装差分サマリー

| ファイル | 種別 | 内容 |
|---|---|---|
| `unity_android_plugin/.../share/ShareChooserActionReceiver.kt` | 新規 | 動的登録用 BroadcastReceiver。`intent.action` を `onAction` ラムダへ転送 |
| `unity_android_plugin/.../share/ShareChooserActionReceiverRegistry.kt` | 新規 | 受信登録の世代管理を担う internal interface + Android 実装（SDK ゲート・`RECEIVER_NOT_EXPORTED`・置換・解除をカプセル化、テスト時は差し替え可能） |
| `unity_android_plugin/.../share/ShareChooserActionInputs.kt` | 新規 | `intentAction` の正規化（非空・distinct 抽出）を行う internal オブジェクト（reflection 不要で単体テスト可能） |
| `unity_android_plugin/.../share/UnityAndroidShareManager.kt` | 変更 | `ShareChooserActionListener` 追加、set/clear API 追加、`shareText` での session 登録＋失敗 cleanup、main 直列化、callback 例外封じ込め |
| `unity_android_plugin/src/main/AndroidManifest.xml` | 変更なし | **動的登録のため宣言不要**（方針通り manifest に追加しない） |
| `unity_android_plugin/.../share/ShareChooserActionReceiverTest.kt` | 新規 | receiver 転送・null 無視・listener 例外封じ込めの単体テスト |
| `unity_android_plugin/.../share/ShareChooserActionInputsTest.kt` | 新規 | action 正規化（空除去・重複除去・default SEND 警告）の単体テスト |
| `unity_android_plugin/.../share/UnityAndroidShareManagerTest.kt` | 変更 | fake registry 注入で register/replace/失敗 cleanup/clear/listener 転送・例外を検証 |
| `unity_android_plugin/src/androidTest/.../ShareChooserActionInstrumentedTest.kt` | 新規（**必須**） | API 34+ 実登録・broadcast 受信・複数 action・clear・action 無し・連続 share・失敗 cleanup を検証 |

- 破壊的変更: **なし**（既存 API のシグネチャ・挙動は不変。追加のみ）。
- 既存 `UnityChooserActionSpec` / `UnityShareJsonParser` は変更不要（`intentAction` は既にパース済み）。

---

## 実装アーキテクチャ

```
Unity(C#) --AndroidJavaProxy 実装--> ShareChooserActionListener (interface)
                                          ▲ onChooserAction(actionId)  [main thread]
                                          │  ※ Manager が try/catch で例外封じ込め
UnityAndroidShareManager (Manager 層, object)
  - shareChooserActionListener: ShareChooserActionListener?
  - chooserActionRegistry: ShareChooserActionReceiverRegistry?   （遅延生成）
  - chooserActionToken: Long                                     （現在 session の世代）
  - chooserActionRegistryFactory: (Context) -> Registry          （テスト差し替え seam, internal）
  - set/clear（main 直列化） / shareText 内 session 登録 + 失敗 cleanup
        │
        ▼
ShareChooserActionReceiverRegistry (internal interface)
  └ AndroidShareChooserActionReceiverRegistry (実装)
       - register(actionIds, onAction): Long   世代 token を返す（API<34 / 空 は 0）
       - unregister(token)                      token == 現世代 のときのみ解除
       - ContextCompat.registerReceiver(appContext, ShareChooserActionReceiver,
             IntentFilter(各 actionId), RECEIVER_NOT_EXPORTED)
        │
        ▼
ShareChooserActionReceiver (動的登録, exported 不要)
  - onReceive: intent.action を onAction ラムダへ転送（null は無視）

[ライブラリ側・不変]
ShareRepositoryImpl.buildChooserActions
  - 不正 Base64 / Bitmap decode 失敗の action は黙って除外
  - PendingIntent.getBroadcast(ctx, label.hashCode(),
        Intent(intentAction).setPackage(packageName), FLAG_IMMUTABLE)
```

- 識別子は `intent.action`（= Unity が渡した `intentAction`）。ライブラリは識別 extra を付けないため、これが唯一の判別材料。
- 受信登録は **動的**。manifest 宣言不要のため、Unity が任意の action 文字列を使える。
- `ContextCompat.registerReceiver(..., RECEIVER_NOT_EXPORTED)` を使用（API 34+ で context-registered receiver はエクスポート指定が必須。ライブラリの callback registry `ShareCallbackCoordinator.kt` と同一作法）。
- SDK ゲート・登録の副作用は **registry 実装に閉じ込め**、Manager 側ロジック（正規化・世代・失敗 cleanup・置換）は fake registry で JVM 単体テスト可能にする（レビュー高#4 / 中#5）。

---

## サブ機能別詳細設計

### A. ShareChooserActionReceiver（新規）

パス: `unity_android_plugin/src/main/java/android/unity/share/ShareChooserActionReceiver.kt`

```kotlin
package android.unity.share

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Dynamically-registered receiver for custom chooser action taps (API 34+).
 *
 * Forwards the tapped action string (Intent.action) to [onAction].
 * Registered/unregistered by [ShareChooserActionReceiverRegistry]; never declared in the
 * manifest, so Unity may use arbitrary intentAction strings.
 */
internal class ShareChooserActionReceiver(
    private val onAction: (String) -> Unit
) : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "[onReceive] context: $context, intent: $intent, action: ${intent?.action}")
        val action = intent?.action ?: return
        onAction(action)
    }

    companion object {
        private const val TAG = "android.unity.share.ShareChooserActionReceiver"
    }
}
```

- 動的登録のため listener はコンストラクタ注入（静的フィールド不要）。通知側 receiver が静的フィールドを使うのは manifest 宣言（システムが no-arg で生成）だからで、動的登録では注入が適切。
- `intent.action` が null の broadcast は無視。**例外封じ込めは `onAction`（= Manager の dispatch）側で行う**（B/C 参照）。

### B. ShareChooserActionReceiverRegistry（新規・世代管理）

パス: `unity_android_plugin/src/main/java/android/unity/share/ShareChooserActionReceiverRegistry.kt`

責務: SDK ゲート・実登録・置換・世代別解除をカプセル化。Manager から副作用を隠蔽し、テスト差し替え可能にする。

```kotlin
package android.unity.share

import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Registers/unregisters the dynamic chooser-action receiver with generation tracking.
 *
 * Implementations isolate the SDK gate and registration side effects so the manager logic
 * (normalization, generation, failure cleanup, replacement) is testable without a device.
 */
internal interface ShareChooserActionReceiverRegistry {
    /**
     * Registers a receiver for [actionIds], replacing any previous registration.
     *
     * @param actionIds Distinct, non-blank action strings to listen for.
     * @param onAction Invoked with the tapped action string.
     * @return A positive generation token, or 0 if nothing was registered (below API 34, empty, or failure).
     */
    fun register(actionIds: List<String>, onAction: (String) -> Unit): Long

    /**
     * Unregisters the current receiver only if [token] matches the current generation.
     *
     * @param token Generation token returned by [register].
     */
    fun unregister(token: Long)
}

internal class AndroidShareChooserActionReceiverRegistry(
    private val appContext: Context
) : ShareChooserActionReceiverRegistry {

    private val lock = Any()
    private var currentToken = 0L
    private var currentReceiver: BroadcastReceiver? = null

    override fun register(actionIds: List<String>, onAction: (String) -> Unit): Long {
        Log.d(TAG, "[register] actionIds: $actionIds")
        // Custom actions only appear on API 34+. Below that the library ignores them.
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return 0L
        synchronized(lock) {
            unregisterCurrentLocked()
            if (actionIds.isEmpty()) return 0L
            val receiver = ShareChooserActionReceiver(onAction)
            val filter = IntentFilter().apply { actionIds.forEach { addAction(it) } }
            return try {
                ContextCompat.registerReceiver(
                    appContext, receiver, filter, ContextCompat.RECEIVER_NOT_EXPORTED
                )
                currentReceiver = receiver
                currentToken += 1
                currentToken
            } catch (e: Exception) {
                Log.e(TAG, "[register] failed to register receiver", e)
                currentReceiver = null
                0L
            }
        }
    }

    override fun unregister(token: Long) {
        Log.d(TAG, "[unregister] token: $token, currentToken: $currentToken")
        synchronized(lock) {
            if (token == 0L || token != currentToken) return
            unregisterCurrentLocked()
        }
    }

    private fun unregisterCurrentLocked() {
        val receiver = currentReceiver ?: return
        try {
            appContext.unregisterReceiver(receiver)
        } catch (e: IllegalArgumentException) {
            // Benign: receiver was already unregistered. Documented exception to the Log.e rule.
            Log.w(TAG, "[unregisterCurrentLocked] receiver not registered", e)
        } finally {
            currentReceiver = null
        }
    }

    private companion object {
        private const val TAG = "android.unity.share.AndroidShareChooserActionReceiverRegistry"
    }
}
```

- **世代 token**: `register` のたびに前世代を解除して `currentToken` をインクリメント。`unregister(token)` は `token == currentToken` のときだけ解除するため、**新しい登録を古い token の解除で誤って消さない**（レビュー高#1/#2）。
- SDK<34 / 空集合 / 登録失敗は `0L` を返す（= 未登録）。`unregister(0L)` は no-op。
- 二重解除の `IllegalArgumentException` は想定内のため `Log.w`（規約例外として明記）。

### C. ShareChooserActionInputs（新規・正規化）

パス: `unity_android_plugin/src/main/java/android/unity/share/ShareChooserActionInputs.kt`

```kotlin
package android.unity.share

import android.util.Log

/** Normalizes chooser action inputs into the set of action strings to register. */
internal object ShareChooserActionInputs {

    private const val TAG = "android.unity.share.ShareChooserActionInputs"
    private const val DEFAULT_SEND_ACTION = "android.intent.action.SEND"

    /**
     * Returns distinct, non-blank action strings. Warns on the default SEND action,
     * which is unsuitable as a callback identifier.
     */
    fun normalizeActionIds(actions: List<UnityChooserActionSpec>): List<String> {
        Log.d(TAG, "[normalizeActionIds] actions.size: ${actions.size}")
        val ids = actions.map { it.intentAction }.filter { it.isNotBlank() }
        if (ids.any { it == DEFAULT_SEND_ACTION }) {
            Log.w(TAG, "[normalizeActionIds] default SEND action is not a reliable callback identifier")
        }
        return ids.distinct()
    }
}
```

- internal object のため reflection 不要で直接テスト可能（レビュー中#5）。

### D. UnityAndroidShareManager（変更）

#### 追加フィールド

```kotlin
private var shareChooserActionListener: ShareChooserActionListener? = null
private var chooserActionRegistry: ShareChooserActionReceiverRegistry? = null
private var chooserActionToken: Long = 0L

// Test seam: swap in a fake registry without a device.
internal var chooserActionRegistryFactory: (Context) -> ShareChooserActionReceiverRegistry =
    { ctx -> AndroidShareChooserActionReceiverRegistry(ctx.applicationContext) }
```

#### 追加 public API（main 直列化）

```kotlin
/**
 * Registers the listener for custom chooser action taps. The callback is delivered on the main thread.
 *
 * @param listener Listener to register.
 */
fun setShareChooserActionListener(listener: ShareChooserActionListener) {
    Log.d(TAG, "[setShareChooserActionListener] listener: $listener")
    runOnMain { shareChooserActionListener = listener }
}

/**
 * Clears the chooser action listener and unregisters the current dynamic receiver.
 */
fun clearShareChooserActionListener() {
    Log.d(TAG, "[clearShareChooserActionListener]")
    runOnMain {
        chooserActionRegistry?.unregister(chooserActionToken)
        chooserActionToken = 0L
        shareChooserActionListener = null
    }
}
```

- `set` も `runOnMain` で直列化。`set`/`clear`/`shareText`（`executeOperationOnMain` 経由）の状態変更がすべて main looper 上で順序保証される（レビュー高#2）。
- callback 実行スレッド: context-registered receiver を Handler 無しで登録するため `onReceive` は **main thread**。listener へも main thread で届く（公開仕様に明記）。

#### `shareText` への組み込み（失敗 cleanup 付き）

```kotlin
fun shareText(context: Context, shareJson: String) {
    Log.d(TAG, "[shareText] context: $context, shareJson: $shareJson")
    executeOperationOnMain(OPERATION_SHARE_TEXT) {
        val spec = UnityShareJsonParser.parseShareText(shareJson)
        val content = ShareContent(
            text = spec.text, title = spec.title, subject = spec.subject, mimeType = spec.mimeType
        )
        val chooserActionsJson = buildChooserActionsJson(spec.chooserActions)
        val preview = SharePreviewOptions(spec.previewTitle, spec.previewThumbnailPath)

        val actionIds = ShareChooserActionInputs.normalizeActionIds(spec.chooserActions)
        val registry = chooserActionRegistry
            ?: chooserActionRegistryFactory(context).also { chooserActionRegistry = it }
        val token = registry.register(actionIds) { actionId -> dispatchChooserAction(actionId) }
        chooserActionToken = token
        try {
            ShareUseCases(context).shareText(content, chooserActionsJson, preview)
        } catch (error: Throwable) {
            // Share launch failed: drop this registration only (generation-guarded).
            registry.unregister(token)
            if (chooserActionToken == token) chooserActionToken = 0L
            throw error
        }
    }
}
```

- 登録は `ShareUseCases.shareText` の**前**（PendingIntent 発火前に receiver を用意）。
- 起動失敗時は **今回の token だけ**を解除して re-throw（`executeOperation` の既存 try/catch が失敗通知）。世代ガードにより後続登録は誤解除しない（レビュー高#1）。
- `actionIds` が空なら `register` 内で前世代を解除し `0L` を返す（chooserActions 無し share で stale receiver を残さない）。

#### callback dispatch（例外封じ込め）

```kotlin
private fun dispatchChooserAction(actionId: String) {
    Log.d(TAG, "[dispatchChooserAction] actionId: $actionId")
    val listener = shareChooserActionListener
    if (listener == null) {
        Log.w(TAG, "[dispatchChooserAction] listener is null, actionId=$actionId")
        return
    }
    try {
        listener.onChooserAction(actionId)
    } catch (e: Exception) {
        // Never let a Unity-side exception escape the BroadcastReceiver thread.
        Log.e(TAG, "[dispatchChooserAction] listener threw for actionId=$actionId", e)
    }
}
```

- listener（Unity proxy）の例外を `try/catch` で封じ込め、`Log.e`。receiver スレッドへ漏らさずクラッシュを防ぐ（レビュー高#3）。

- 追加 import: `android.content.Context`（既存）, registry/inputs は同一パッケージ。

---

## 制御フロー

### 受信成立パス

1. Unity が `setShareChooserActionListener(proxy)` を呼ぶ（main で代入）。
2. Unity が `chooserActions` 付き JSON で `shareText` を呼ぶ。
3. Manager（main thread）が action を正規化 → registry.register（API 34+ なら実登録、token 採番）→ ライブラリ `shareText` を呼ぶ。
4. ライブラリが有効な action（icon decode 成功分）に `EXTRA_CHOOSER_CUSTOM_ACTIONS` を付けて Sharesheet を開く。
5. ユーザーがカスタムアクションをタップ → ライブラリの PendingIntent がアプリ内 broadcast を送出。
6. 動的 receiver の `onReceive`（main）→ `dispatchChooserAction` → `listener.onChooserAction(actionId)`（例外封じ込め）。
7. Unity(C#) が `actionId` を解釈して処理。

### ライフサイクル / 解除（公開契約）

- **同時に有効な chooser session は最新 1 件のみ**。次回 `shareText`（chooserActions 付き）で前世代を解除して置換する。複数 Sharesheet を同時に残した場合、最新以外の action は受信できない。
- chooserActions 無しの `shareText` では前世代を解除（不要 receiver を残さない）。
- 起動失敗時は今回の登録のみ解除（世代ガード）。
- `clearShareChooserActionListener()` で現世代を解除 + listener クリア（Unity のシーン破棄時に必須）。
- **保証範囲はアプリプロセス存続中のみ**。context-registered receiver はプロセス終了で失われる。プロセスが落ちた後のタップは受信できない。
- カスタムアクション**未タップ**（アプリ選択 or キャンセル）の場合、終端シグナルは来ない。receiver は次回登録 or 明示 clear まで残る（プロセス存続中のみ・最新 1 件のみのため累積はしない）。

---

## 入力契約（Unity 側の前提・レビュー中#1/#3 反映）

`chooserActions` を callback 付きで使う場合、Unity は次を満たす入力を渡すこと:

| 項目 | 契約 |
|---|---|
| `intentAction` | **必須・一意・非空**。識別子として使うため省略不可。`android.intent.action.SEND` 既定値は識別に使わない（Manager は warning ログを出す） |
| namespace | アプリ固有を推奨: `${applicationId}.share.action.*`（同一アプリ内の別 broadcast との衝突回避） |
| `label` / `iconBase64` | 非空・**decode 可能**な画像。1〜5 件、label/action は一意 |
| 件数 | Android 仕様上 Sharesheet 表示は最大 5 件。6 件以上は超過分が表示されない |

- **重要（表示集合と登録集合の不一致）**: ライブラリは不正 Base64 / Bitmap decode 失敗の action を黙って除外する。Manager は parser が返した全 `intentAction`（distinct・非空）を登録するため、**icon が壊れた action は receiver だけ生き残りボタンは出ない**（その action は発火しないので実害は無いが、Unity からは「ボタンが出なかった」ことを判別できない）。
- 本機能の callback 登録は**ベストエフォート**。`shareText` の成否（`onShareOperation`）は共有起動の結果であり、**callback 登録の成否とは別物**。Unity が「表示される action」と「callback 受信可能な action」を一致させたい場合は、**Unity 側で icon decode・件数・一意性を事前検証**してから渡すこと（公開契約として明記）。

---

## API 設計

### 公開（Unity 向け）

| API | シグネチャ | 説明 |
|---|---|---|
| listener | `interface ShareChooserActionListener { fun onChooserAction(actionId: String) }` | タップされた action 文字列を **main thread** で通知。実装（Unity proxy）の例外は Bridge 側で封じ込め |
| 登録 | `fun setShareChooserActionListener(listener)` | listener 登録（main で直列化） |
| 解除 | `fun clearShareChooserActionListener()` | listener 解除 + 現世代 receiver 解除（main で直列化） |

- 既存 `shareText(context, shareJson)` のシグネチャは不変。`chooserActions` を含む JSON を渡すだけで受信登録が有効化される（追加引数なし）。
- callback 実行スレッド: main thread。各 set/clear は main looper post 完了時点で反映。

### 内部

| 要素 | 種別 | 説明 |
|---|---|---|
| `ShareChooserActionReceiver(onAction)` | internal class | 動的 receiver（action 転送のみ） |
| `ShareChooserActionReceiverRegistry` / `AndroidShareChooserActionReceiverRegistry` | internal interface / class | SDK ゲート・世代管理・置換・解除 |
| `ShareChooserActionInputs.normalizeActionIds(actions)` | internal object fun | 非空・distinct 抽出 + default SEND 警告 |
| `dispatchChooserAction(actionId)` | private | listener 転送 + 例外封じ込め |
| `chooserActionRegistryFactory` | internal var | テスト差し替え seam |

---

## ドメインエラー一覧（全ケース）

本機能は **新規ドメインエラーを導入しない**。受信経路はライブラリの share 操作（`ShareDomainError` を投げる経路）を呼ばないため。

既存 `shareText` 経由のドメインエラー（参考・本機能で挙動変化なし）:

| ドメインエラー | 発生契機 |
|---|---|
| `ShareDomainError.EmptyContent` | `text` が空 |
| `ShareDomainError.InvalidMimeType` | `mimeType` 不正 |
| `ShareDomainError.NoShareTarget` | 共有先アプリ無し |

## エラーコード / メッセージ対応表

本機能固有の Bridge 返却エラーは無い（受信はイベント通知であり成否を返さない）。発生し得る内部失敗の扱い:

| 事象 | 扱い | Unity への通知 |
|---|---|---|
| `registerReceiver` 失敗（例外） | `Log.e` で記録、token=0 を返す（未登録） | なし（ベストエフォート。共有起動自体は継続） |
| 共有起動失敗（`shareText` throw） | 今回 token を解除し re-throw → `onShareOperation(false, ...)` | あり（共有起動の失敗として既存経路で通知。callback 登録解除は内部処理） |
| 二重 `unregisterReceiver`（未登録解除） | `Log.w` で記録、無視（規約例外） | なし |
| `onReceive` 時に listener 未登録 | `Log.w` で記録、破棄 | なし |
| listener（Unity proxy）が例外 | `Log.e` で記録、封じ込め | なし（クラッシュ防止） |
| `intent.action == null` | 無視 | なし |
| icon decode 失敗で action がライブラリに除外 | ボタン非表示・receiver は残存（発火しない） | なし（入力契約で Unity 事前検証を要求） |

- 既存 `shareText` の成否は従来通り `ShareOperationListener.onShareOperation` で通知される（callback 登録成否とは別契約）。

---

## テスト設計

### 単体テスト（JVM, fake registry 注入）

`ShareChooserActionInputsTest.kt`（新規）:

| ケース | 種別 | 期待 |
|---|---|---|
| 空 action 除去 | 正常 | blank を除外 |
| 重複 action 除去 | 正常 | distinct |
| default SEND 含む | 境界 | 警告ログ・値は保持して distinct |
| 空リスト | 境界 | 空を返す |

`ShareChooserActionReceiverTest.kt`（新規）:

| ケース | 種別 | 期待 |
|---|---|---|
| action 付き Intent | 正常 | `onAction` が当該 action で 1 回 |
| action=null | 異常 | `onAction` 未呼び出し |
| intent=null | 境界 | 例外なく無視 |

`UnityAndroidShareManagerTest.kt`（変更・fake registry を `chooserActionRegistryFactory` で注入）:

| ケース | 種別 | 期待 |
|---|---|---|
| chooserActions 付き shareText | 正常 | fake registry.register が正規化済み actionIds で呼ばれる |
| 連続 shareText | 正常 | 前 token が unregister され新 token に置換 |
| chooserActions 無し shareText | 境界 | register が空集合で呼ばれ token=0（未登録） |
| 共有起動失敗（fake ShareUseCases or context で例外） | 異常 | **今回 token のみ** unregister、`onShareOperation(false)` も発火 |
| set→fake register の onAction 発火 | 正常 | `onChooserAction` 転送 |
| listener 未登録で onAction 発火 | 異常 | 例外なく `Log.w` |
| listener が例外を投げる | 異常 | 封じ込め、クラッシュしない、`Log.e` |
| clear 後に onAction 発火 | 正常 | 転送されない |
| clear が現 token を unregister | 正常 | fake registry.unregister(token) |

- fake registry は `register`/`unregister` の引数・回数を記録し、`onAction` を任意発火できるものとする。
- 世代管理の検証は fake registry を**本物の `AndroidShareChooserActionReceiverRegistry` のロジック相当**にせず、Manager 側の token 受け渡し（register 戻り値→失敗時 unregister）に限定する。registry 内部の世代/解除は計装テストで担保。

### 計装テスト（API 34+ 実機/エミュレータ・**必須**, レビュー高#4）

`ShareChooserActionInstrumentedTest.kt`（新規）:

| ケース | 期待 |
|---|---|
| chooserActions 付き shareText 後、対象 action を broadcast | listener の `onChooserAction` が当該 action で発火 |
| 複数 action | 各 action で別 actionId が届く（識別可能） |
| `RECEIVER_NOT_EXPORTED` で PendingIntent 由来 broadcast を受信できる | 受信成立（要・実機確認） |
| 連続 shareText | 旧 receiver 解除・新 receiver のみ受信 |
| chooserActions 無し shareText | 旧 receiver 解除（旧 action 受信しない） |
| 共有起動失敗 | 今回 receiver が解除される |
| clear 後 | broadcast が届かない |

### 手動確認（API 34+ 実機）

1. Unity サンプルで `setShareChooserActionListener` を登録。
2. `chooserActions`（一意な `${applicationId}.share.action.*`）付き `shareText` を実行 → Sharesheet にカスタムアクション表示。
3. カスタムアクションをタップ → Unity 側ハンドラに `actionId` が届く（ログ/トースト）。
4. 複数アクションで各々別 `actionId` が届くこと（識別）を確認。
5. `clearShareChooserActionListener` 後はタップが届かないこと。
6. 共有を起動できない状況（共有先無し等）で receiver が残らないこと（次回 share で重複通知が無い）。

### リスク対応の検証ケース

| リスク | 検証 |
|---|---|
| 起動失敗時の receiver 残留 | 失敗 → 同 action broadcast で発火しない（計装） |
| receiver リーク / 累積 | 連続 share で常に最新 1 件のみ（計装） |
| listener 例外でクラッシュ | 例外を投げる listener で onReceive がクラッシュしない（単体） |
| set/clear 順序競合 | clear 直後 set が main で直列化され、新 listener が消えない（単体・main looper 検証） |

---

## 実装タスク分解（依存関係付き・レビュー低#1 反映）

| # | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T1 | `ShareChooserActionReceiver` + `ShareChooserActionInputs` + 各単体テスト | 0.5日 | なし | action 転送・null 無視・正規化（空/重複/SEND 警告）green | full-class TAG / null 安全 / reflection 不使用 |
| T2 | `ShareChooserActionListener` + set/clear（main 直列化）+ 単体テスト | 0.5日 | なし | listener 登録/解除が main で直列化。clear で現世代解除 | Delegate 所有が Manager 1 箇所 / 順序保証 |
| T3 | `ShareChooserActionReceiverRegistry`（世代管理・SDK ゲート・置換・解除） | 0.5〜1日 | T1 | register が token 採番・置換、unregister が世代ガード、登録失敗で token=0 | `RECEIVER_NOT_EXPORTED` / 二重解除 Log.w / 例外握り |
| T4 | `shareText` への session 組み込み + 失敗 cleanup + dispatch 例外封じ込め + Manager 単体テスト（fake registry） | 0.5〜1日 | T1,T2,T3 | 正規化→register→失敗時 token のみ解除、listener 例外封じ込め。Manager テスト green・既存不破壊 | 失敗 cleanup / 例外境界 / 既存回帰 |
| T5 | API 34+ 計装テスト（実登録・受信・複数 action・clear・action 無し・連続・失敗 cleanup） | 0.5〜1日 | T3,T4 | 主要登録/受信経路が自動検証 green（実機/エミュ） | 実登録確認 / session 置換 |
| T6 | サンプルデモ（Unity 受信の動作確認用） | 別途 design-sample-app | T4 | カスタムアクションタップが受信側に届くことを end-to-end で確認できる（具体ファイルは sample 設計で定義） | 受信表示・複数アクション識別 |

- 先行（基盤）: T1, T2, T3。
- 後続（拡張/検証）: T4, T5, T6。

---

## リスクと緩和策

| リスク | 影響 | 緩和策 |
|---|---|---|
| 共有起動失敗時の receiver 残留 | 後続の同一 action 誤通知 | register 戻り token を保持し、起動失敗時に**今回 token のみ**世代ガード解除（高#1） |
| set/clear の順序競合 | 新 listener が遅延 clear で消える | set/clear/shareText の状態変更を **main looper 上で直列化**。callback も main（高#2） |
| listener 例外の伝播 | アプリクラッシュ | `dispatchChooserAction` の `try/catch` で封じ込め `Log.e`（高#3） |
| 登録経路の自動テスト不足 | 主要要件が未検証 | registry/inputs を internal 分離し JVM テスト、実登録は **計装テスト必須**（高#4） |
| 表示 action と登録 action の不一致 | icon 壊れた action は receiver 残るが発火せず | 入力契約で Unity 事前検証を要求。callback 登録は best-effort と公開明記（中#1） |
| 動的 receiver の保証範囲 | プロセス終了/複数 session で受信不可 | 「プロセス存続中のみ」「最新 1 session のみ」を公開仕様・手動確認に明記（中#2） |
| `intentAction` 既定値/衝突 | 識別不能・別 broadcast 衝突 | callback 利用時は `intentAction` 必須・一意、`${applicationId}.share.action.*` namespace を入力契約化（中#3） |
| ログ規約不整合 | 規約違反 | TAG を full class name 化、二重解除 `Log.w` は規約例外として理由明記（中#4） |
| private テスト方法未確定 | 実装時の手戻り | registry interface + inputs object に分離、reflection 不要で直接テスト（中#5） |
| `RECEIVER_NOT_EXPORTED` で PendingIntent broadcast を受信できるか | 受信不成立の可能性 | API 34 実機で受信成立を計装/手動確認（要検証として明記） |
| ライブラリが将来識別 extra を追加 | 前提変化 | 現状は `intent.action` 依存と明記。extra 追加時は receiver で extra 優先利用に拡張可能 |

---

## Definition of Done

- [ ] `ShareChooserActionReceiver`（動的・internal）が `intent.action` を `onAction` へ転送し、null を無視する
- [ ] `ShareChooserActionReceiverRegistry` が SDK ゲート・`RECEIVER_NOT_EXPORTED`・**世代管理**（register で token 採番/置換、unregister は世代ガード）を担う
- [ ] `ShareChooserActionInputs.normalizeActionIds` が非空・distinct 抽出と default SEND 警告を行う
- [ ] `setShareChooserActionListener` / `clearShareChooserActionListener` が **main looper で直列化**され、callback が main thread で届くことを公開仕様に明記
- [ ] `shareText` が登録→ライブラリ呼び出しの順で動作し、**起動失敗時は今回 token のみ解除**して re-throw
- [ ] `dispatchChooserAction` が listener 例外を `try/catch` で封じ込め `Log.e`
- [ ] `chooserActions` 無し share / clear で現世代を解除（stale receiver を残さない）
- [ ] 入力契約（`intentAction` 必須・一意・namespace、icon の Unity 事前検証、callback 登録 best-effort）を公開仕様に明記
- [ ] 「プロセス存続中のみ・最新 1 session のみ」を公開仕様・リスク・手動確認に明記
- [ ] `android_library` を変更していない / manifest に receiver を宣言していない
- [ ] 新規 `onReceive`/public・internal 関数に `Log.d`、失敗・listener 例外は `Log.e`、TAG は full class name
- [ ] public interface / 関数に KDoc（英語）
- [ ] 単体テスト（inputs 正規化・receiver 転送・Manager の register/置換/失敗 cleanup/listener 転送・例外・clear）が green、既存不破壊
- [ ] **API 34+ 計装テスト（実登録・受信・複数 action・clear・action 無し・連続・失敗 cleanup）が green**（実機未確認なら理由明記）
- [ ] 破壊的変更なし（既存 API シグネチャ・挙動不変）
