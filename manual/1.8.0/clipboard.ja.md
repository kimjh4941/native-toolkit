# Clipboard 機能

Language:

- 日本語（このページ）
- English: [clipboard.md](clipboard.md)
- 한국어: [clipboard.ko.md](clipboard.ko.md)

← [マニュアルトップへ戻る](index.ja.md)

---

## 目次

- [Android](#android)
  - [セットアップ](#セットアップ)
  - [コピー](#コピー)
    - [プレーンテキストをコピー](#プレーンテキストをコピー)
    - [プレーンテキストをコピー（空文字）](#プレーンテキストをコピー空文字)
    - [HTML テキストをコピー](#html-テキストをコピー)
    - [URI をコピー](#uri-をコピー)
    - [複数テキストをコピー](#複数テキストをコピー)
  - [コピー - 機微情報](#コピー---機微情報)
    - [機微情報テキストをコピー](#機微情報テキストをコピー)
  - [読み取り / 確認](#読み取り--確認)
    - [クリップボードを読み取る](#クリップボードを読み取る)
    - [データ有無を確認](#データ有無を確認)
    - [メタデータを取得](#メタデータを取得)
  - [クリア](#クリア)
    - [クリップボードをクリア](#クリップボードをクリア)
  - [変更監視](#変更監視)
    - [監視を開始](#監視を開始)
    - [監視を停止](#監視を停止)
  - [エラー処理](#エラー処理)

---

## Android

- ライブラリ: `android-native-toolkit-1.3.0.aar`
- 最小 SDK: Android 12 (API 31)
- 機微情報プレビュー抑止: Android 13 (API 33) 以上
- 対応範囲: コピー・読み取り・メタデータ確認・クリア・クリップボード変更監視を `android_library`（ネイティブ）経由で提供します。いずれの操作も Unity Bridge への依存は不要です。

### セットアップ

#### Android ネイティブ（AAR）

1. `android-native-toolkit-1.3.0.aar` を `app/libs` に配置します。
2. `app/build.gradle.kts` に依存関係を追加します:

```kotlin
dependencies {
    implementation(files("libs/android-native-toolkit-1.3.0.aar"))
}
```

クリップボード操作に追加のマニフェスト設定は不要です。`content://` URI をコピーする場合（[URI をコピー](#uri-をコピー)参照）は、共有したいファイルの URI を解決できる `FileProvider` が別途必要です。AAR 自体は汎用目的の `FileProvider` を宣言していません。

---

### コピー

`ClipboardUseCases` は `Context` を受け取るファクトリ関数で取得します:

```kotlin
val clipboardUseCases = ClipboardUseCases(context)
```

#### プレーンテキストをコピー

```kotlin
try {
    clipboardUseCases.copyPlainText(
        ClipContent.PlainText(text = "Hello from native-toolkit", label = "sample")
    )
} catch (e: ClipboardDomainError) {
    // エラー処理
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyPlainText.png" alt="Example_ClipboardSampleScreen_CopyPlainText" width="400" />
</p>

#### プレーンテキストをコピー（空文字）

空文字は許容され、例外は発生しません。

```kotlin
clipboardUseCases.copyPlainText(ClipContent.PlainText(text = ""))
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyPlainTextEmpty.png" alt="Example_ClipboardSampleScreen_CopyPlainTextEmpty" width="400" />
</p>

#### HTML テキストをコピー

```kotlin
clipboardUseCases.copyHtmlText(
    ClipContent.HtmlText(plainText = "Hello", htmlText = "<b>Hello</b>")
)
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyHtmlText.png" alt="Example_ClipboardSampleScreen_CopyHtmlText" width="400" />
</p>

#### URI をコピー

`content://`（または `file://`）URI をコピーします。`content` / `file` スキームのみが許容され、それ以外のスキームは `ClipboardDomainError.InvalidUri` を送出します。

```kotlin
val file = File(context.cacheDir, "clipboard_sample.txt")
file.writeText("Clipboard sample file content")
val uri = FileProvider.getUriForFile(
    context,
    "${context.packageName}.native_toolkit.share.fileprovider",
    file
)

clipboardUseCases.copyUri(ClipContent.UriContent(uri = uri.toString()))
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyUri.png" alt="Example_ClipboardSampleScreen_CopyUri" width="400" />
</p>

#### 複数テキストをコピー

同一形式の複数プレーンテキストアイテムです（1つの `ClipData` に複数アイテムを格納します）。

```kotlin
clipboardUseCases.copyMultipleText(
    ClipContent.MultipleText(texts = listOf("first", "second", "third"))
)
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopyMultipleText.png" alt="Example_ClipboardSampleScreen_CopyMultipleText" width="400" />
</p>

---

### コピー - 機微情報

`isSensitive = true` を指定すると、コピーした内容が機微情報（パスワード・ワンタイムコードなど）であることをシステムに示唆できます。

- Android 13 (API 33) 以上では、システム標準のコピー確認 UI が内容のプレビュー表示を抑止します。
- Android 12L (API 32) 以下ではシステム確認 UI 自体が存在しないため、コピー後に自前でフィードバック（`Toast` など）を表示してください。

#### 機微情報テキストをコピー

```kotlin
clipboardUseCases.copyPlainText(
    ClipContent.PlainText(text = "P@ssw0rd-sample", isSensitive = true)
)

if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2) {
    Toast.makeText(context, "Copied (sensitive)", Toast.LENGTH_SHORT).show()
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_CopySensitiveText.png" alt="Example_ClipboardSampleScreen_CopySensitiveText" width="400" />
</p>

---

### 読み取り / 確認

#### クリップボードを読み取る

空のクリップボードは**正常系**であり、エラーではありません。`read()` は `null` を返します。

```kotlin
val result = clipboardUseCases.read()
if (result != null) {
    // result.label, result.mimeTypes, result.items（各アイテムの text / htmlText / uri / coercedText）
} else {
    // クリップボードは空（正常系）
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_ReadClipboard.png" alt="Example_ClipboardSampleScreen_ReadClipboard" width="400" />
</p>

#### データ有無を確認

```kotlin
val hasClip: Boolean = clipboardUseCases.hasClip()
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_HasClip.png" alt="Example_ClipboardSampleScreen_HasClip" width="400" />
</p>

#### メタデータを取得

本体データに触れずメタデータのみ取得します（Android 12+ の「クリップボードから貼り付けました」アクセス通知を回避できます）。こちらもクリップボードが空の場合は `null`（正常系）を返します。

```kotlin
val info = clipboardUseCases.getDescription()
if (info != null) {
    // info.label, info.mimeTypes
    // info.isStyledText: 書式付き（リッチ）テキストかどうか
    // info.classificationStatus: ClipDescription.CLASSIFICATION_* の生値。取得不可時は null
}
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_GetDescription.png" alt="Example_ClipboardSampleScreen_GetDescription" width="400" />
</p>

---

### クリア

#### クリップボードをクリア

```kotlin
clipboardUseCases.clear()
```

<p align="center">
    <img src="images/android/clipboard/Example_ClipboardSampleScreen_ClearClipboard.png" alt="Example_ClipboardSampleScreen_ClearClipboard" width="400" />
</p>

---

### 変更監視

`ClipboardChangeMonitor` はシステムのクリップボード変更リスナーを所有するクラスで、`android_library`（Unity Bridge ではなくネイティブ側）に配置されているため、ネイティブコードから直接利用できます。

監視はアプリが前面にある間のみ確実に動作します（Android 10+ はバックグラウンドでのクリップボード読み取りを制限するためです）。

```kotlin
val monitor = ClipboardChangeMonitor()
```

#### 監視を開始

`onChange` はシステムリスナーのコールバックスレッドで呼び出されます。UI 状態を更新する場合は自分でメインスレッドへ橋渡ししてください。

```kotlin
monitor.start(context) {
    // システムリスナーのコールバックスレッドで呼ばれる
    mainHandler.post {
        // ここで UI 状態を更新
    }
}

val isObserving: Boolean = monitor.isObserving()
```

監視中に `start` を再度呼んでも no-op です（system listener の二重登録は発生しません）。

#### 監視を停止

```kotlin
monitor.stop()
```

監視中の画面・コンポーネントが破棄されるタイミングで `stop()` を呼び、system listener のリークを防いでください:

```kotlin
DisposableEffect(monitor) {
    onDispose { monitor.stop() }
}
```

---

### エラー処理

`ClipboardUseCases` は `ClipboardDomainError` のサブタイプを送出します。

| エラー | 原因 | エラーメッセージ |
|---|---|---|
| `EmptyContent` | `copyHtmlText` で `htmlText` が空 | `"Clipboard content is empty. Please provide text or HTML."` |
| `EmptyItemList` | `copyMultipleText` で `texts` リストが空 | `"No items provided for clipboard copy."` |
| `InvalidUri` | `uri` が空、または scheme が `content`/`file` 以外 | `"Invalid URI: <uri>"` |
| `ClipboardUnavailable` | システムの `ClipboardManager` を取得できない | `"Clipboard service is unavailable."` |
| `ReadNotAllowed` | `read()` がシステムに拒否された（`SecurityException`）。アプリが前面にない可能性が高い | `"Clipboard read is not allowed. The app must be in the foreground."` |

空のクリップボードはこれらのエラーに**含まれません**: `read()` / `getDescription()` は正常系として `null` を返します。

```kotlin
try {
    clipboardUseCases.copyUri(ClipContent.UriContent(uri = ""))
} catch (e: ClipboardDomainError.InvalidUri) {
    // URI が空、または未対応の scheme
} catch (e: ClipboardDomainError) {
    // その他のドメインエラー
}
```
