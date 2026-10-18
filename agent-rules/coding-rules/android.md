# Android コーディングルール

## モジュール配置（必須）

共通ルール `./common.md` の「層とモジュールの対応」「サンプルアプリの依存方向」を Android に適用した具体マッピング。

| モジュール | 置くもの | 置いてはいけないもの |
|---|---|---|
| `android/android_library` | Domain / Application / Data / Presentation / **Manager**。system Delegate・Listener の所有クラス | C ABI の型の変換・寿命の管理、特定の利用者（Unity など）向けの JSON 変換 |
| `android/android_library_capi` | **C ABI の受け口のみ**（`capi.jni` の `*Bridge`、C の関数、帳簿、前面の判定、例外の捕捉。C ABI の設計書 第 1 部 2 章「C ABI は Kotlin の API の薄い包み」） | 機能のロジック、system Delegate・Listener の所有。Kotlin の利用者にも必要な機能 |
| `android/AndroidLibraryExample` | ネイティブサンプル。`implementation(project(":android_library"))` のみ | `android_library_capi` への依存（C ABI は `android_library_capi_test` と smoke で確かめる） |

Unity 向けの Android の Bridge（`unity_android_plugin`）は 2.0.0 で無くなった。Unity は Windows と同じく C ABI（`android_library_capi`）を P/Invoke で呼ぶ。

**C ABI の受け口は Manager 層ではない。** Manager 層（`Android*Manager`）は `android_library` の機能のパッケージの直下に置く（`common.md` の「Manager の置き場所」）。C ABI の受け口は Manager を呼ぶだけで、Manager 層のものや、system Listener など Manager から使う部品を `android_library_capi` に置いてはならない。それらは `android_library` の `presentation/` などに配置する。

**具体例:** Clipboard の変更監視 `ClipboardChangeMonitor`（`ClipboardManager.OnPrimaryClipChangedListener` を所有）は `android/android_library/src/main/java/com/jonghyunkim/nativetoolkit/clipboard/presentation/` に置き、C ABI の受け口（`ClipboardBridge`）は `AndroidClipboardManager` を呼ぶだけにする。

**実装前チェック:** 追加するクラスを `android_library_capi` に置こうとしたら、「Kotlin の利用者（`AndroidLibraryExample`）からこの機能を使う必要があるか」を必ず自問する。必要なら `android_library` へ置く。

### Manager（`android_library`）

ほかの OS（`Ios*Manager`、`Mac*Manager`、`Windows*Manager`）とそろえ、機能ごとの入口 `AndroidClipboardManager`、`AndroidDialogManager`、`AndroidNotificationManager`、`AndroidShareManager` を `android_library` に置く（`artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md` 6.3）。

- 置き場所は機能のパッケージの直下（`<機能>/Android*Manager.kt`、パッケージ `com.jonghyunkim.nativetoolkit.<機能>`）。`presentation/` などの層のパッケージには入れない（`common.md` の「Manager の置き場所」）
- 入口だけの薄い層にする。UseCase と、イベント・監視の持ち主に委ね、ロジックを持たない
- `class Android*Manager internal constructor(依存)` と `companion object { @JvmStatic fun getInstance(context: Context) }`。持つのは Application の Context だけ（Activity を持ち続けない）
- テストは internal の constructor で UseCase と port を差し替える
- C ABI の受け口は、機能ごとにこの Manager を呼ぶ。C 特有の処理（文字列の変換、ハンドル、`release`）は受け口に残す
- 既存の `*UseCases`（`ClipboardUseCases(context)` など）は既存の入口として残す。data の組み立ての根（`*UseCases(context)`、`NotificationUseCasesFactory`）は、presentation から使ってよい

**UseCase を置かない口の条件:** `common.md` の「Manager は必ず UseCase 経由で Data 層にアクセスする」は、Data 層に届く操作の規則である。次の口は Data 層に届かないので UseCase を置かない。

1. presentation の Delegate の持ち主への受け手の登録・解除と、監視の開始・停止
2. presentation の PendingIntent の要求の factory
3. Context の資源の即時の問い合わせ（リソース名の解決など）
4. 状態を持たない純粋な関数（エラーの分類など）
5. ライブラリの初期化

**既存の例外:** `NotificationUseCases.isScheduled(context, id, tag)` は、application から data の保存を直接読む（2.0.0 で既存の口の動作を変えないため。`artifact/topics/android-c-abi/README.md` 4 章）。新しく足す口でこの形をまねしない。

---

## ログ（Log.d）

全メソッドの先頭1行目に、全パラメータを含む `Log.d` を必ず入れる。

**フォーマット:**

```kotlin
Log.d(TAG, "[methodName] param1: $param1, param2: $param2")
```

エラーは `Log.e` を使ってログ出力する。

```kotlin
Log.e(TAG, "[methodName] param1: $param1, param2: $param2")
```

**対象:**

- `override fun`
- `operator fun invoke`
- public / internal 関数
- `BroadcastReceiver.onReceive`
- ローカル `fun`（通知機能コード内）

**除外:**

- data class / enum / interface 宣言
- private utility extension 関数（`JSONObject` 拡張等の軽量ヘルパー）
- 純粋 UI ユーティリティ（`AlwaysVisibleLazyColumnScrollbar` 等）
- 既にログがある箇所（重複追加しない）

**秘密の値を伏せる（例外）:**

全パラメータを出す規則の例外として、秘密になりうる値はログに出さない。

| 項目 | 規則 |
|---|---|
| 伏せる値 | Clipboard の本文（テキスト、HTML、URI）、Dialog の入力（テキスト、ユーザー名、パスワード）、Share の本文（`text`、`subject`）、通知の `data` の値（キーは出す）、`Intent` の extra の値 |
| 書き方 | `LogRedaction.redact(value)` で `<redacted, length=N>`（`null` は `null`）にするか、長さ・件数・種類だけを出す。既存の公開の型の `toString()` は変えず、ログの箇所で伏せる。新しい型は `toString()` で伏せてよい |
| 出してよい値 | 長さ、件数、ID、種類、真偽値、通知のタイトルとメッセージ |
| 先頭の `Log.d` | 残す。伏せる値を持つ引数は `redact` を通すか、長さだけを出す |
| C / C++ | `__android_log_print`、タグ `ntk`。同じ値を伏せる |

```kotlin
fun copyPlainText(content: ClipContent.PlainText) {
    Log.d(TAG, "[copyPlainText] textLength: ${content.text.length}, label: ${content.label}")
}
```

**TAG の定義:**

```kotlin
companion object {
    private const val TAG = "FullClassName"  // クラスのフルネームを使う（省略不可）
}
```

**import:**

```kotlin
import android.util.Log
```

**例:**

```kotlin
override fun onReceive(context: Context, intent: Intent?) {
    Log.d(TAG, "[onReceive] context: $context, intent: $intent")
    // 既存処理...
}

operator fun invoke(command: AndroidNotificationCommand): Result<Unit> {
    Log.d(TAG, "[invoke] command: $command")
    return runCatching { repository.send(command) }
}
```

---

## Dokka コメント（KDoc）

`public` な関数・クラス・インターフェース・プロパティには KDoc コメントを付ける。  
コードと同時に書く（後からまとめて書くと設計意図を忘れるため）。

**対象（必須）:**

- `public fun`
- `public class` / `interface` / `data class` / `sealed class`
- `public` プロパティ（非自明なもの）

**除外:**

- `private fun` / `internal fun`（コードと関数名で表現する）
- `override fun`（親の KDoc を継承するため不要）
- 自明な getter / setter

**フォーマット:**

```kotlin
/**
 * 概要を1行で書く。
 *
 * 必要であれば補足説明を追加する。
 *
 * @param channelId 削除対象のチャンネルID
 * @return 処理結果。失敗時は [Result.failure] に例外が入る
 */
fun deleteChannel(channelId: String): Result<Unit>
```

**ルール:**

- コメント言語とユーザー向け文言の言語は共通方針（`./common.md`）に従う
- 1行目は体言止めまたは動詞で始める簡潔な概要
- `@param` は全パラメータを省略せず記載する
- `@return` は戻り値が非自明な場合のみ記載
- `@throws` は checked exception 相当の場合に記載

---

## Coroutine（suspend fun の要否）

方針は `common.md`「Manager の公開 API 方式」を参照。iOS の `async throws` / macOS の `async throws` に対応する Kotlin 側の判断基準を以下に定める。

**`suspend fun` にすべきもの:**

- Manager 層のネイティブ版公開 API（`common.md` の「callback 版 + ネイティブ版の併設」でいうネイティブ版）。UseCase をそのまま公開する薄いラッパーとして `suspend fun` + 例外送出にする
- 呼び出し元で中断・再開が必要な、実質的に非同期な処理（ネットワーク I/O、長時間かかるディスク I/O など）

**`suspend fun` にしなくてよいもの:**

- `ClipboardManager` / `NotificationManagerCompat` 等、システムサービスへの同期 API 呼び出しのみで完結する UseCase・Repository（例: clipboard の `ClipboardUseCases` は全メソッド非 suspend。設計判断の理由は `artifact/android/clipboard/designs/*-design.md` を参照）
- 単発の軽量なファイル書き込み・読み込みなど、呼び出し元で `launch(Dispatchers.IO) { ... }` に包めば足りる処理（下記サンプルアプリの扱いを参照）

**サンプルアプリ（`AndroidLibraryExample`）での非同期処理:**

- `@Composable` の `Button` の `onClick` は同期ラムダのため、非同期処理が必要な場合は `rememberCoroutineScope()` で得た `scope` を使い `scope.launch(Dispatchers.IO) { ... }` で橋渡しする（iOS の `Task { await ... }` に相当）
- 呼び出し先の関数自体を `suspend fun` にする必要はない。既存の `ShareSampleScreen.kt` の慣例に倣い、`launch(Dispatchers.IO) { ... }` のブロック内で通常の同期関数を呼び、UI 状態の更新は `withContext(Dispatchers.Main) { ... }` に包む
- ディスク I/O（ファイル書き込み等）を `onClick` 内で同期実行しない（メインスレッドブロッキングになるため）。既存パターン（`ShareSampleScreen.kt` の `writeText` 呼び出し等）を確認し、同じ形で `Dispatchers.IO` に逃がす
