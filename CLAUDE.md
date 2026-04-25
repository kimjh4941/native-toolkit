# CLAUDE.md — native-toolkit コーディングガイドライン

## Android コーディングルール

### ログ（Log.d）

全メソッドの先頭1行目に、全パラメータを含む `Log.d` を必ず入れる。

**フォーマット:**

```kotlin
Log.d(TAG, "[methodName] param1: $param1, param2: $param2")
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

### Dokka コメント（KDoc）

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

- コメント本文（KDoc、行コメント、ブロックコメント）は英語で記述する
- ユーザー向けメッセージ文言（UIテキスト、statusText、Toast、Dialog文言）は英語で記述する
- 1行目は体言止めまたは動詞で始める簡潔な概要
- `@param` は非自明なパラメータのみ記載（名前から明らかなものは省略可）
- `@return` は戻り値が非自明な場合のみ記載
- `@throws` は checked exception 相当の場合に記載
