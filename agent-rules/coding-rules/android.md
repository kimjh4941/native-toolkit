# Android コーディングルール

## モジュール配置（必須）

共通ルール `./common.md` の「層とモジュールの対応」「サンプルアプリの依存方向」を Android に適用した具体マッピング。

| モジュール | 置くもの | 置いてはいけないもの |
|---|---|---|
| `android/android_library` | Domain / Application / Data / Presentation / **Manager**。system Delegate・Listener の所有クラス | Unity 固有の JSON 変換・Unity 向け listener |
| `android/unity_android_plugin` | **Unity Bridge のみ**（`Unity*Manager`、JSON parser、Unity 向け spec） | system Delegate・Listener の所有。ネイティブ利用者に必要な機能 |
| `android/AndroidLibraryExample` | ネイティブサンプル。`implementation(project(":android_library"))` のみ | `unity_android_plugin` への依存、`android.unity.*` の import |

**`Unity*Manager` は Unity Bridge 層であって Manager 層ではない。**
`android_library` には現状 `manager/` パッケージが無いが、それは「Manager 層のものを `unity_android_plugin` に置いてよい」という意味ではない。system Listener など、ネイティブ利用者にも必要なクラスは `android_library` の `presentation/` などに配置する。

**具体例:** Clipboard の変更監視 `ClipboardChangeMonitor`（`ClipboardManager.OnPrimaryClipChangedListener` を所有）は `android/android_library/src/main/java/android/library/clipboard/presentation/` に置き、`UnityAndroidClipboardManager` はそこへ委譲するだけにする。

**実装前チェック:** 追加するクラスを `unity_android_plugin` に置こうとしたら、「`AndroidLibraryExample` からこの機能を使う必要があるか」を必ず自問する。必要なら `android_library` へ置く。

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

- システム API / UseCase が実際に非同期で、呼び出し元のスレッドをブロックせず完了を待つもの。Manager のネイティブ版も UseCase の非同期性を維持した薄いラッパーとして `suspend fun` + 例外送出にする
- 呼び出し元で中断・再開が必要な、実質的に非同期な処理（ネットワーク I/O、長時間かかるディスク I/O など）
- Main thread 要件がある同期 API を任意の Coroutine context から呼べる契約にするもの。`withContext(Dispatchers.Main.immediate)` で配送するため `suspend fun` にする

**`suspend fun` にしなくてよいもの:**

- `ClipboardManager` / `NotificationManagerCompat` 等、システムサービスへの同期 API 呼び出しのみで完結する UseCase・Repository（例: clipboard の `ClipboardUseCases` は全メソッド非 suspend。設計判断の理由は `artifact/designs/clipboard/*-design.md` を参照）
- 単発の軽量なファイル書き込み・読み込みなど、呼び出し元で `launch(Dispatchers.IO) { ... }` に包めば足りる処理（下記サンプルアプリの扱いを参照）

同期 API に Main thread 要件がある場合、公開 API を Main thread 限定にするなら `@MainThread` を付けた通常関数のままにする。任意の Coroutine context に対応する場合だけ `suspend fun` + `withContext(Dispatchers.Main.immediate)` とし、単なる形式統一のためには非同期化しない。

**サンプルアプリ（`AndroidLibraryExample`）での非同期処理:**

- `@Composable` の `Button` の `onClick` は同期ラムダのため、非同期処理が必要な場合は `rememberCoroutineScope()` で得た `scope` を使い `scope.launch(Dispatchers.IO) { ... }` で橋渡しする（iOS の `Task { await ... }` に相当）
- 呼び出し先の関数自体を `suspend fun` にする必要はない。既存の `ShareSampleScreen.kt` の慣例に倣い、`launch(Dispatchers.IO) { ... }` のブロック内で通常の同期関数を呼び、UI 状態の更新は `withContext(Dispatchers.Main) { ... }` に包む
- ディスク I/O（ファイル書き込み等）を `onClick` 内で同期実行しない（メインスレッドブロッキングになるため）。既存パターン（`ShareSampleScreen.kt` の `writeText` 呼び出し等）を確認し、同じ形で `Dispatchers.IO` に逃がす
