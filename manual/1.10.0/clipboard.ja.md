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
- [iOS](#ios)
  - [IosClipboardManager](#iosclipboardmanager)
  - [セットアップ](#セットアップ-1)
    - [スレッド](#スレッド)
    - [2 つの呼び出し方式](#2-つの呼び出し方式)
    - [既定値](#既定値)
  - [スコープ](#スコープ)
    - [一般ペーストボードを使う](#一般ペーストボードを使う)
    - [名前付きペーストボードを作成](#名前付きペーストボードを作成)
    - [名前付きスコープを参照（作成しない）](#名前付きスコープを参照作成しない)
    - [ユニークペーストボードを作成](#ユニークペーストボードを作成)
    - [アクティブなペーストボードを削除](#アクティブなペーストボードを削除)
    - [名前付き / ユニークペーストボードは永続ストアではありません](#名前付き--ユニークペーストボードは永続ストアではありません)
  - [コピー](#コピー-1)
    - [プレーンテキストをコピー](#プレーンテキストをコピー-1)
    - [プレーンテキストをコピー（空文字）](#プレーンテキストをコピー空文字-1)
    - [HTML テキストをコピー](#html-テキストをコピー-1)
    - [URL をコピー](#url-をコピー)
    - [画像ファイルをコピー](#画像ファイルをコピー)
    - [画像データをコピー](#画像データをコピー)
    - [色をコピー](#色をコピー)
    - [カスタムデータをコピー](#カスタムデータをコピー)
    - [複数テキストをコピー](#複数テキストをコピー-1)
    - [複数表現をコピー](#複数表現をコピー)
  - [コピーオプション](#コピーオプション)
    - [localOnly を指定してコピー](#localonly-を指定してコピー)
    - [expirationDate を指定してコピー](#expirationdate-を指定してコピー)
  - [追記](#追記)
    - [プレーンテキストを追記](#プレーンテキストを追記)
    - [URL を追記](#url-を追記)
    - [追記はプライバシーオプションを引き継ぎません](#追記はプライバシーオプションを引き継ぎません)
  - [読み取り / 確認](#読み取り--確認-1)
    - [読み取り](#読み取り)
    - [データを読み取り](#データを読み取り)
    - [スナップショット](#スナップショット)
    - [スナップショット（型を指定）](#スナップショット型を指定)
    - [プライバシー: 確認ダイアログと通知](#プライバシー-確認ダイアログと通知)
  - [非同期ロード](#非同期ロード)
    - [テキストをロード](#テキストをロード)
    - [URL をロード](#url-をロード)
    - [画像をロード](#画像をロード)
    - [ファイルをロード](#ファイルをロード)
    - [すべてのロードをキャンセル](#すべてのロードをキャンセル)
  - [検出](#検出)
    - [パターンを検出](#パターンを検出)
    - [値を検出](#値を検出)
    - [number と probableWebSearch はクリップボード全体を分類します](#number-と-probablewebsearch-はクリップボード全体を分類します)
    - [検出にキャンセルトークンはありません](#検出にキャンセルトークンはありません)
  - [変更監視](#変更監視-1)
    - [監視を開始](#監視を開始-1)
    - [監視を停止](#監視を停止-1)
    - [フォアグラウンド復帰時の変更確認](#フォアグラウンド復帰時の変更確認)
  - [ペーストコントロール](#ペーストコントロール)
    - [ペーストコントロールを作成](#ペーストコントロールを作成)
  - [クリア](#クリア-1)
  - [エラー処理](#エラー処理-1)
- [macOS](#macos)
  - [MacClipboardManager](#macclipboardmanager)
    - [2 つの呼び出し形式](#2-つの呼び出し形式)
    - [コンテンツは型識別子とバイト列の辞書です](#コンテンツは型識別子とバイト列の辞書です)
    - [名前付きペーストボードの作成](#名前付きペーストボードの作成)
    - [ユニークペーストボードの作成](#ユニークペーストボードの作成)
    - [現在のペーストボードの削除](#現在のペーストボードの削除)
    - [general の削除（エラー 1508）](#general-の削除エラー-1508)
    - [空の名前でのペーストボード作成（エラー 1505）](#空の名前でのペーストボード作成エラー-1505)
    - [テキストのコピー](#テキストのコピー)
    - [URL のコピー](#url-のコピー)
    - [画像のコピー](#画像のコピー)
    - [複数 item のコピー](#複数-item-のコピー)
    - [複数 representation のコピー](#複数-representation-のコピー)
    - [空のコピー（エラー 1501）](#空のコピーエラー-1501)
    - [representation が空の item のコピー（エラー 1502）](#representation-が空の-item-のコピーエラー-1502)
    - [localOnly の既定値は true です](#localonly-の既定値は-true-です)
    - [コピーしてから追記する](#コピーしてから追記する)
    - [append は追記先のプライバシー設定を引き継ぎます](#append-は追記先のプライバシー設定を引き継ぎます)
    - [所有権を失った状態での追記（エラー 1511）](#所有権を失った状態での追記エラー-1511)
  - [読み取り / 検査](#読み取り--検査)
    - [Read](#read)
    - [特定の型の読み取り](#特定の型の読み取り)
    - [Snapshot](#snapshot)
    - [型フィルタ付きの Snapshot](#型フィルタ付きの-snapshot)
    - [空フィルタでの Snapshot（エラー 1512）](#空フィルタでの-snapshotエラー-1512)
    - [Access Behavior](#access-behavior)
    - [パターンの検出](#パターンの検出)
    - [値の検出](#値の検出)
    - [メタデータの検出](#メタデータの検出)
    - [パターンを指定しない検出（エラー 1503）](#パターンを指定しない検出エラー-1503)
  - [監視](#監視)
    - [監視の開始](#監視の開始)
    - [不正な間隔（エラー 1523）](#不正な間隔エラー-1523)
    - [監視の停止](#監視の停止)
    - [前面復帰時の変更確認](#前面復帰時の変更確認)
    - [不正な型識別子（エラー 1504）](#不正な型識別子エラー-1504)
    - [1514 について](#1514-について)
    - [通常の利用では発生しないエラーコード](#通常の利用では発生しないエラーコード)

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

---

## iOS

- ライブラリ: `ios-native-toolkit-1.3.0.xcframework`
- 最小デプロイメントターゲット: iOS 18
- 対応範囲: コピー / 追記、同期読み取り、メタデータのスナップショット、名前付き・ユニークペーストボードのライフサイクル、`NSItemProvider` による非同期ロード、パターン検出、変更監視、そして配置するだけで使える `UIPasteControl` ペーストボタンを提供します。

### IosClipboardManager

`IosClipboardManager` は、`UIPasteboard` をラップするシングルトンクラスです。

### セットアップ

1. `ios-native-toolkit-1.3.0.xcframework` を Xcode プロジェクトに追加します（プロジェクトにドラッグし、ターゲットの Frameworks, Libraries, and Embedded Content で "Embed & Sign" に設定します）。
2. クリップボードを使用するファイルでライブラリをインポートします。

```swift
import IosLibrary
```

追加の初期化も `Info.plist` への記載も不要です。

#### スレッド

`IosClipboardManager` は `@MainActor` に隔離されています。メインアクター上（SwiftUI / UIKit のコードは既にメインアクター上です）から呼び出してください。メインアクター以外から呼び出す場合は `await MainActor.run { ... }` を使用します。

#### 2 つの呼び出し方式

値を扱うすべての操作に、次の 2 つの形式があります。

- `async throws`（ネイティブ Swift 呼び出し元に推奨）: 型付きの値を返し、失敗時は `ClipboardError` を throw します。
- コールバック: `(isSuccess, value?, errorCode?, errorMessage?)`。戻り値のない操作は `(isSuccess, errorCode?, errorMessage?)` です。

```swift
// async throws（Swift 呼び出し元に推奨）
Task {
    do {
        try await IosClipboardManager.shared.copy(.plainText("Hello"))
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorDescription ?? "nil")
    }
}

// コールバック（同等）
IosClipboardManager.shared.copy(.plainText("Hello")) { isSuccess, errorCode, errorMessage in
    print(isSuccess, errorCode ?? "nil", errorMessage ?? "nil")
}
```

`cancelAllLoads` / `startObserving` / `stopObserving` / `checkForegroundChange` / `makePasteControl` は同期的に完了するため、同期形式のみを提供します。

以降の例は `async throws` 形式を使用します。SwiftUI の `Button` アクションは同期のため、各呼び出しを `Task { ... }` で包んでいます。

#### 既定値

| 設定 | 既定値 |
|---|---|
| コピーの最大サイズ | 64 MiB |
| ロードの最大サイズ | 64 MiB |
| 画像の最大ピクセル数 | 100,000,000 |
| 検出のタイムアウト | 5 秒 |
| プロバイダロードのタイムアウト | 15 秒 |
| 画像エンコードのタイムアウト | 10 秒 |

別の値を使う場合は `IosClipboardManager(timeouts:limits:)` でインスタンスを生成します。通常は `shared` を使用してください。

---

### スコープ

すべての操作は `scope: PasteboardScope` パラメータを受け取り、既定値は `.general` です。一般ペーストボードはすべてのアプリと共有され、起動をまたいで保持されます。名前付き・ユニークペーストボードは、起動中のアプリ同士でデータを受け渡すためのものです。

```swift
public enum PasteboardScope {
    case general
    case named(String)   // 同一 Team ID のアプリと共有
    case unique(String)  // withUniqueName() で作成。名前は出力値
}
```

#### 一般ペーストボードを使う

`.general` は既定値のため、省略もできます。

```swift
let scope: PasteboardScope = .general
```

#### 名前付きペーストボードを作成

`createPasteboard(.named(_:))` は、その名前のペーストボードが存在すれば解決し、なければ作成します。戻り値の `PasteboardScope` を以降の呼び出しに渡してください。

```swift
Task {
    let scope = try await IosClipboardManager.shared.createPasteboard(
        .named("com.jonghyunkim.nativetoolkit.example.sample")
    )
    // scope == .named("com.jonghyunkim.nativetoolkit.example.sample")
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CreateNamedPasteboard.png" alt="Example_IosClipboardManager_CreateNamedPasteboard" width="400" />
</p>

#### 名前付きスコープを参照（作成しない）

作成せずに名前を参照することもできますが、何かが作成するまでは、その名前に対する操作はすべて `CLIPBOARD_UNAVAILABLE` で失敗します。

```swift
let scope = PasteboardScope.named("com.jonghyunkim.nativetoolkit.example.sample")
```

#### ユニークペーストボードを作成

`.unique` は名前の生成をシステムに任せます。生成された名前は戻り値のスコープに含まれるため、そのペーストボードを再度使う場合は保持しておく必要があります。

```swift
Task {
    let scope = try await IosClipboardManager.shared.createPasteboard(.unique)
    // scope == .unique("<システムが生成した名前>")
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CreateUniquePasteboard.png" alt="Example_IosClipboardManager_CreateUniquePasteboard" width="400" />
</p>

#### アクティブなペーストボードを削除

```swift
Task {
    try await IosClipboardManager.shared.removePasteboard(scope)
}
```

`.general` を削除しようとすると `ClipboardError.cannotRemoveGeneralPasteboard` を throw します。

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_RemovePasteboard.png" alt="Example_IosClipboardManager_RemovePasteboard" width="400" />
</p>

#### 名前付き / ユニークペーストボードは永続ストアではありません

`createPasteboard(.named(_:))` や `.unique` で作成したペーストボードは永続化を意図したものではありませんが、**作成したアプリの終了時に内容が破棄される保証もありません**。iOS 18.7.2 での実測では、アプリを強制終了して再起動した後も、終了前に書き込んだ名前付きペーストボードを読み取れました。システムは、そうしたペーストボードがいつ回収されるかを規定していません。

これらのスコープは起動中のアプリ同士でデータを受け渡す用途にのみ使用し、**機微データは `removePasteboard(_:)` で明示的に削除してください**。アプリの終了に破棄を期待しないでください。強制終了では `deinit` が実行されないため、ライブラリが終了時にクリーンアップを行っても、この状況には対処できません。

設計上、作成元アプリより長く存続させる必要がある共有には、App Group の共有コンテナを使用してください。これは本ライブラリの対応範囲外です。

---

### コピー

`copy` はペーストボードの内容を置き換えます。`ClipboardContent` が、対応するすべての形式を表します。

#### プレーンテキストをコピー

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .plainText("Hello from IosLibraryExample"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyPlainText.png" alt="Example_IosClipboardManager_CopyPlainText" width="400" />
</p>

#### プレーンテキストをコピー（空文字）

空文字も許容され、throw しません。

```swift
Task {
    try await IosClipboardManager.shared.copy(.plainText(""), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyPlainTextEmpty.png" alt="Example_IosClipboardManager_CopyPlainTextEmpty" width="400" />
</p>

#### HTML テキストをコピー

2 つの表現を持つ 1 つのアイテムとして書き込まれるため、HTML を扱えないアプリでもプレーンテキストのフォールバックを取得できます。

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .htmlText(plain: "plain body", html: "<b>html body</b>"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyHtmlText.png" alt="Example_IosClipboardManager_CopyHtmlText" width="400" />
</p>

#### URL をコピー

URL は文字列として渡し、ライブラリ内で検証します。`http` / `https` / `file` スキームのみを受け付け、それ以外は `ClipboardError.invalidURL` を throw します。

```swift
Task {
    try await IosClipboardManager.shared.copy(.url("https://www.apple.com"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyURL.png" alt="Example_IosClipboardManager_CopyURL" width="400" />
</p>

#### 画像ファイルをコピー

ファイルパスから画像を読み込みます。パスが存在しない場合は `ClipboardError.fileNotFound`、画像としてデコードできない場合は `ClipboardError.imageLoadFailed` を throw します。

```swift
Task {
    guard let path = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path else { return }
    try await IosClipboardManager.shared.copy(.imageFile(path: path), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyImageFile.png" alt="Example_IosClipboardManager_CopyImageFile" width="400" />
</p>

#### 画像データをコピー

画像のバイト列を、既知の画像 UTI を明示して書き込みます。画像としてデコードできないデータは `ClipboardError.invalidImageData` を throw します。

```swift
Task {
    guard let url = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png"),
          let data = try? Data(contentsOf: url) else { return }
    try await IosClipboardManager.shared.copy(
        .imageData(data, utType: "public.png"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyImageData.png" alt="Example_IosClipboardManager_CopyImageData" width="400" />
</p>

#### 色をコピー

RGBA の各成分は有限値かつ `0.0...1.0` の範囲である必要があります。範囲外の場合は `ClipboardError.invalidColor` を throw します。

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyColor.png" alt="Example_IosClipboardManager_CopyColor" width="400" />
</p>

#### カスタムデータをコピー

アプリ定義の UTI で任意のバイト列を書き込みます。UTI は構文が検証され、不正な場合は `ClipboardError.invalidTypeIdentifier` を throw します。

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .customData(Data([0xCA, 0xFE]), utType: "com.jonghyunkim.nativetoolkit.example.custom"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyCustomData.png" alt="Example_IosClipboardManager_CopyCustomData" width="400" />
</p>

アプリの `Info.plist` に宣言していないカスタム UTI は `public.data` に適合しないため、`public.data` としてのファイルロードでは見つかりません。汎用ファイルとしてロードさせたい場合は、`public.data` 自体を指定してください。

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .customData(Data(repeating: 0x41, count: 64), utType: "public.data"),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyFileFixture.png" alt="Example_IosClipboardManager_CopyFileFixture" width="400" />
</p>

#### 複数テキストをコピー

同じ形式のプレーンテキストを複数書き込みます。空配列は `ClipboardError.emptyItemList` を throw します。

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .multipleText(["first", "second", "third"]),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyMultipleText.png" alt="Example_IosClipboardManager_CopyMultipleText" width="400" />
</p>

#### 複数表現をコピー

1 つのアイテムに複数の表現を UTI をキーとして持たせます。受け取る側のアプリが解釈できる表現を選びます。空の辞書は `ClipboardError.emptyItemList` を throw します。

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .multiRepresentation([
            "public.plain-text": Data("multi representation".utf8),
            "public.utf8-plain-text": Data("multi representation".utf8)
        ]),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyMultiRepresentation.png" alt="Example_IosClipboardManager_CopyMultiRepresentation" width="400" />
</p>

---

### コピーオプション

`ClipboardCopyOptions` は `copy` のプライバシー設定を表します。既定値は `localOnly: true`、有効期限なしです。

```swift
public struct ClipboardCopyOptions {
    public let localOnly: Bool       // 近くのデバイスへ転送しない（ユニバーサルクリップボード）
    public let expirationDate: Date? // この時刻を過ぎるとシステムがアイテムを破棄する
    public static let `default` = ClipboardCopyOptions(localOnly: true, expirationDate: nil)
}
```

#### localOnly を指定してコピー

`localOnly: true` は、ユニバーサルクリップボードで近くのデバイスへアイテムを渡さないようシステムに要求します。デバイス間の転送を意図する場合にのみ `false` を指定してください。

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .plainText("LOCALONLY-BODY"),
        options: ClipboardCopyOptions(localOnly: true, expirationDate: nil),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyLocalOnly.png" alt="Example_IosClipboardManager_CopyLocalOnly" width="400" />
</p>

#### expirationDate を指定してコピー

指定する日時は未来である必要があります。過去の日時は `ClipboardError.invalidExpirationDate` を throw します。

```swift
Task {
    try await IosClipboardManager.shared.copy(
        .plainText("expiring body"),
        options: ClipboardCopyOptions(
            localOnly: true,
            expirationDate: Date().addingTimeInterval(30)
        ),
        scope: scope
    )
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_CopyExpiring.png" alt="Example_IosClipboardManager_CopyExpiring" width="400" />
</p>

---

### 追記

`append` は、既にペーストボードにある内容を置き換えずにアイテムを追加します。

#### プレーンテキストを追記

```swift
Task {
    try await IosClipboardManager.shared.append(.plainText("appended item"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_AppendPlainText.png" alt="Example_IosClipboardManager_AppendPlainText" width="400" />
</p>

#### URL を追記

```swift
Task {
    try await IosClipboardManager.shared.append(.url("https://developer.apple.com"), scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_AppendURL.png" alt="Example_IosClipboardManager_AppendURL" width="400" />
</p>

#### 追記はプライバシーオプションを引き継ぎません

`append` は `ClipboardCopyOptions` を受け取れず、直前の `copy` で指定した `localOnly` / `expirationDate` が追記したアイテムに適用される保証もありません。**機微データには必ず `copy(_:options:)` を使用してください。**

---

### 読み取り / 確認

#### 読み取り

ペーストボードを同期的に読み取ります。大きなペイロード（画像のバイト列）は結果に含まれず、UTI のみが報告されます。空のペーストボードはエラーではなく**正常な状態**で、`numberOfItems` が `0` になります。

```swift
Task {
    let result = try await IosClipboardManager.shared.read(scope: scope)
    print(result.numberOfItems)
    for item in result.items {
        // item.typeIdentifiers, item.text, item.urlString, item.imageDataUTType
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_Read.png" alt="Example_IosClipboardManager_Read" width="400" />
</p>

#### データを読み取り

指定した UTI で登録されたバイト列を返します。一致するアイテムがない場合は `nil` を返します。

```swift
Task {
    let data = try await IosClipboardManager.shared.readData(utType: "public.png", scope: scope)
    print(data?.count ?? 0)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_ReadData.png" alt="Example_IosClipboardManager_ReadData" width="400" />
</p>

#### スナップショット

本文に触れず、メタデータのみを読み取ります。事前確認にはこちらを使用してください。iOS 16 以降の許可ダイアログと iOS 14 以降のアクセス通知のいずれも発生させないと Apple が明記している API のみで構成しています。

```swift
Task {
    let snapshot = try await IosClipboardManager.shared.snapshot(scope: scope)
    // snapshot.hasStrings, snapshot.hasURLs, snapshot.hasImages, snapshot.hasColors
    // snapshot.numberOfItems, snapshot.typeIdentifiers, snapshot.allTypeIdentifiers
    if snapshot.hasStrings {
        // ペースト用の UI を表示する
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_Snapshot.png" alt="Example_IosClipboardManager_Snapshot" width="400" />
</p>

`hasStrings` では、特定の型としてのペーストが成功するかどうかは判断できません。たとえば `public.vcard` は `public.plain-text` のサブタイプではなく兄弟型のため、`hasStrings` を満たしていてもプレーンテキストとしてはロードできません。受け付ける型は明示的に宣言してください（[ペーストコントロール](#ペーストコントロール)を参照）。

#### スナップショット（型を指定）

`matchingTypes` を渡すと、指定した型を持つアイテムのインデックスも取得できます。`matchingTypes` を指定しなかった場合、`matchingItemIndexes` は `nil` になります。

```swift
Task {
    let snapshot = try await IosClipboardManager.shared.snapshot(
        matchingTypes: ["public.plain-text"],
        scope: scope
    )
    print(snapshot.matchingItemIndexes ?? [])
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_SnapshotMatching.png" alt="Example_IosClipboardManager_SnapshotMatching" width="400" />
</p>

#### プライバシー: 確認ダイアログと通知

`read` / `readData` / `loadItem` はペーストボードからデータを取得するため、システムの判断により iOS 16 以降の許可ダイアログや iOS 14 以降のアクセス通知が表示されることがあります。事前確認には `snapshot` を使用してください。

`UIPasteControl`（`makePasteControl` 経由）は iOS 16 以降の許可ダイアログを回避しますが、iOS 14 以降のアクセス通知も回避すると Apple は明記していません。いずれかが表示されないことを前提にする場合は、対象 OS バージョンの実機で確認してください。

---

### 非同期ロード

`loadItem` は `NSItemProvider` 経由でアイテムを解決します。表現の変換や、メインスレッド外での画像デコードが可能です。`read` だけでは足りない場合に使用してください。

#### テキストをロード

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(.text, scope: scope)
    if case .text(let value) = item {
        print(value.count)
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadText.png" alt="Example_IosClipboardManager_LoadText" width="400" />
</p>

#### URL をロード

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(.url, scope: scope)
    if case .url(let value) = item {
        print(value)
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadURL.png" alt="Example_IosClipboardManager_LoadURL" width="400" />
</p>

#### 画像をロード

画像はバックグラウンドの executor 上で PNG に再エンコードされるため、戻り値の UTI は常に `public.png` になります。

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(.image, scope: scope)
    if case .imageData(let data, let utType) = item {
        print(data.count, utType)
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadImage.png" alt="Example_IosClipboardManager_LoadImage" width="400" />
</p>

#### ファイルをロード

アイテムを一時ファイルにコピーし、その URL を引き渡します。**戻り値の URL とその親ディレクトリの所有権は呼び出し元に移る**ため、使い終わったら削除してください。引き渡されなかったファイル（失敗・キャンセル・タイムアウト）は、ライブラリ内部でクリーンアップします。

```swift
Task {
    let item = try await IosClipboardManager.shared.loadItem(
        .file(utType: "public.data"),
        scope: scope
    )
    if case .file(let url) = item {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
        print(size)
        // ファイル単体ではなく、ライブラリが引き渡したディレクトリを削除します。
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_LoadFile.png" alt="Example_IosClipboardManager_LoadFile" width="400" />
</p>

#### すべてのロードをキャンセル

保留中のロードをすべてキャンセルします。キャンセルされたロードは、`async throws` 形式では `ClipboardError.cancelled`（`CLIPBOARD_CANCELLED`）を throw し、コールバック形式では同じコードとともに `isSuccess == false` を報告します。呼び出し元は、これを無視してよい正常な結果として扱えます。

```swift
IosClipboardManager.shared.cancelAllLoads()
```

コールバック形式は `ClipboardLoadToken` を返すため、個別のロードだけをキャンセルすることもできます。

```swift
let token = IosClipboardManager.shared.loadItem(.image, scope: scope) { isSuccess, item, errorCode, errorMessage in
    print(isSuccess, errorCode ?? "nil")
}
token.cancel()
```

---

### 検出

データ検出は、本文を読み取らずに（したがって許可ダイアログを出さずに）、ペーストボードが何を含むかを報告します。

```swift
public enum ClipboardDetectionPattern: String, CaseIterable {
    case probableWebURL, probableWebSearch, number, link, emailAddress, phoneNumber
    case postalAddress, calendarEvent, flightNumber, moneyAmount, shipmentTrackingNumber
}
```

#### パターンを検出

要求したパターンのうち、検出されたものを返します。空のパターン集合を渡すと `ClipboardError.emptyDetectionPatterns` を throw します。

```swift
Task {
    let patterns = try await IosClipboardManager.shared.detectPatterns(
        Set(ClipboardDetectionPattern.allCases),
        scope: scope
    )
    print(patterns.map(\.rawValue).sorted())
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_DetectPatterns.png" alt="Example_IosClipboardManager_DetectPatterns" width="400" />
</p>

#### 値を検出

検出された値そのものを返します。この操作は内容を読み取るため、プライバシー上は `read` と同じ扱いにしてください。

```swift
Task {
    let values = try await IosClipboardManager.shared.detectValues(
        Set(ClipboardDetectionPattern.allCases),
        scope: scope
    )
    print(values.detectedPatterns.count)
    // values.links, values.emailAddresses, values.phoneNumbers, values.postalAddresses,
    // values.calendarEvents, values.flightNumbers, values.moneyAmounts,
    // values.shipmentTrackingNumbers, values.number, values.probableWebURL, values.probableWebSearch
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_DetectValues.png" alt="Example_IosClipboardManager_DetectValues" width="400" />
</p>

#### number と probableWebSearch はクリップボード全体を分類します

`number` と `probableWebSearch` は、内容から出現箇所を抽出するのではなく、クリップボード**全体**を分類します。数値に言及しているだけの文章は、数値でも検索語句でもありません。そのため、混在した内容ではこの 2 つのパターンは検出されません。これらを確認する場合は、値だけを単独でコピーしてください。

```swift
try await IosClipboardManager.shared.copy(.plainText("42"), scope: scope)                 // number
try await IosClipboardManager.shared.copy(.plainText("swift concurrency"), scope: scope)  // probableWebSearch
```

#### 検出にキャンセルトークンはありません

`detectPatterns` / `detectValues` は `UIPasteboard` の `async` 検出 API をラップしていますが、この API はキャンセルに対応していません。Task のキャンセルや内部の 5 秒タイムアウトは直ちに呼び出し元へ制御を返しますが、その裏でシステム呼び出しが動き続ける可能性があります。その結果は破棄されます。

---

### 変更監視

#### 監視を開始

1 つのスコープについて変更の監視を開始します。2 回目の呼び出し（同じスコープでも別のスコープでも）は、まず直前の監視を停止するため、同時に有効な購読は常に 1 つだけです。

イベントはメインスレッド上で配信されます。

```swift
do {
    try IosClipboardManager.shared.startObserving(scope: scope) { event in
        switch event.kind {
        case .changed(let typesAdded, let typesRemoved):
            print(typesAdded, typesRemoved)
        case .changedDetectedOnForeground:
            // フォアグラウンド復帰時の changeCount 比較で検出された変更
            break
        case .removed:
            // 名前付きペーストボード自体が削除された
            break
        }
    }
} catch let error as ClipboardError {
    // pasteboardUnavailable: スコープを解決できず、監視は開始されていません
    print(error.errorCode)
}
```

`UIPasteboard.changedNotification` は、**このアプリがフォアグラウンドにある間にこのアプリが行った変更**に対してのみ通知されます。他のアプリによる変更や、バックグラウンド中の変更では通知が発生しません。その場合は `checkForegroundChange` を使用してください。

#### 監視を停止

```swift
IosClipboardManager.shared.stopObserving()
```

監視を行っている画面を破棄するときに呼び出してください。

```swift
.onDisappear {
    IosClipboardManager.shared.stopObserving()
}
```

#### フォアグラウンド復帰時の変更確認

ペーストボードの `changeCount` を、このマネージャーが最後に記録した値と比較し、変化したかどうかを返します。通知が発生しない変更を拾うため、アプリがフォアグラウンドへ復帰したときに呼び出してください。

```swift
let changed = IosClipboardManager.shared.checkForegroundChange(scope: scope)
```

あるスコープに対する最初の呼び出しは基準値を確立するため、必ず `false` を返します。基準値は `startObserving` や変更通知の受信によっても更新されます。戻り値の `Bool` では「解決できて変化がない」と「解決できない」を区別できません。その違いが必要な場合は `snapshot` を使用してください。

---

### ペーストコントロール

`UIPasteControl` はシステムのペーストボタンです。ユーザーのタップ自体が同意にあたるため、iOS 16 以降の許可ダイアログを回避できます。

#### ペーストコントロールを作成

`makePasteControl` は、配置するだけで使える 1 つのビューを返します。内部のレシーバーは自動的にレスポンダチェーンへ加わるため、返されたビューをそのままビュー階層に追加してください。

`acceptedTypes` は空にできず（`ClipboardError.invalidRequest`）、各要素は有効な UTI である必要があります（`ClipboardError.invalidTypeIdentifier`）。

```swift
let pasteView = try IosClipboardManager.shared.makePasteControl(
    acceptedTypes: ["public.plain-text", "public.url", "public.image"],
    onPaste: { items in
        print(items.count)
    },
    onPartialFailure: { errors in
        // ペーストされたアイテムの一部をロードできなかった場合
        print(errors.map(\.errorCode))
    },
    onPasteFailure: { error in
        // ペースト自体が失敗した場合
        print(error.errorCode)
    }
)
```

`displayMode` の既定値は `.iconAndLabel` です。ボタンの見た目を変える場合は `.iconOnly` / `.labelOnly` / `.arrowAndLabel` を指定します。ペーストの動作はどのモードでも同じです。

SwiftUI では `UIViewRepresentable` でラップします。

```swift
struct ClipboardPasteControlView: UIViewRepresentable {
    let acceptedTypes: [String]
    let onPaste: ([ClipboardLoadedItem]) -> Void
    let onPartialFailure: ([ClipboardError]) -> Void
    let onPasteFailure: (ClipboardError) -> Void
    let onCreationFailure: (ClipboardError) -> Void

    func makeUIView(context: Context) -> UIView {
        do {
            return try IosClipboardManager.shared.makePasteControl(
                acceptedTypes: acceptedTypes,
                onPaste: onPaste,
                onPartialFailure: onPartialFailure,
                onPasteFailure: onPasteFailure
            )
        } catch let error as ClipboardError {
            // makeUIView 内で同期的に報告すると "Modifying state during view update" が発生する
            // ため、次のメインアクターのターンへ遅延させます。
            Task { @MainActor in onCreationFailure(error) }
            return UIView()
        } catch {
            Task { @MainActor in onCreationFailure(.unknown(ClipboardFailureDetail(systemError: error))) }
            return UIView()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_PasteControl.png" alt="Example_IosClipboardManager_PasteControl" width="400" />
</p>

ペーストボタンは、他の箇所で使用している `scope` とは無関係に、常にシステムの一般ペーストボードを対象とします。

保留中のペーストがキャンセルされた場合（新しいペーストが発生した場合や、ビューが破棄された場合）、`onPaste` / `onPartialFailure` / `onPasteFailure` は**呼び出されません**。キャンセルは呼び出し元が起点であり、ペースト結果としては通知しません。

ボタンとレシーバーを個別に配置する必要がある高度なケースには `PasteControlFactory.makeComponents` を使用できます。その場合、レシーバーの保持と配置は**呼び出し元の責任**になります。

---

### クリア

スコープからすべてのアイテムを削除します。ペーストボード自体は残ります。

```swift
Task {
    try await IosClipboardManager.shared.clear(scope: scope)
}
```

<p align="center">
    <img src="images/ios/clipboard/Example_IosClipboardManager_Clear.png" alt="Example_IosClipboardManager_Clear" width="400" />
</p>

---

### エラー処理

`async throws` 形式は `ClipboardError` を throw します。コールバック形式は同じ失敗を `errorCode` / `errorMessage` で報告し、成功時はいずれも `nil` になります。

`errorMessage` はケースごとに固定の英語文字列で、**入力値を埋め込みません**。そのままログに出力しても安全です。

| `errorCode` | ケース | 原因 | エラーメッセージ |
|---|---|---|---|
| `CLIPBOARD_EMPTY_CONTENT` | `emptyContent` | テキストも HTML も含まない内容 | `"Clipboard content is empty. Please provide text or HTML."` |
| `CLIPBOARD_EMPTY_ITEMS` | `emptyItemList` | `.multipleText([])` または `.multiRepresentation([:])` | `"No items provided for clipboard copy."` |
| `CLIPBOARD_EMPTY_PATTERNS` | `emptyDetectionPatterns` | 空のパターン集合で検出を呼び出した | `"No detection patterns were specified."` |
| `CLIPBOARD_INVALID_URL` | `invalidURL` | URL が空、またはスキームが `http` / `https` / `file` 以外 | `"The URL is invalid."` |
| `CLIPBOARD_INVALID_TYPE` | `invalidTypeIdentifier` | UTI の構文が不正 | `"The uniform type identifier is invalid."` |
| `CLIPBOARD_INVALID_NAME` | `invalidPasteboardName` | ペーストボード名が空、または使用できない | `"The pasteboard name is invalid."` |
| `CLIPBOARD_INVALID_COLOR` | `invalidColor` | RGBA の成分が有限値でない、または `0.0...1.0` の範囲外 | `"Color components must be finite and within 0.0...1.0."` |
| `CLIPBOARD_INVALID_IMAGE_DATA` | `invalidImageData` | 渡されたバイト列を画像としてデコードできない | `"The provided image data could not be decoded."` |
| `CLIPBOARD_INVALID_EXPIRATION` | `invalidExpirationDate` | `expirationDate` が未来ではない | `"expirationDate must be in the future."` |
| `CLIPBOARD_INVALID_REQUEST` | `invalidRequest` | リクエストが不正（`acceptedTypes` が空など） | `"The request is invalid."` |
| `CLIPBOARD_CONTENT_TOO_LARGE` | `contentTooLarge` | ペイロードが上限（既定 64 MiB）を超えた | `"The clipboard content exceeds the configured size limit."` |
| `CLIPBOARD_FILE_NOT_FOUND` | `fileNotFound` | `.imageFile(path:)` のパスが存在しない | `"The requested file was not found."` |
| `CLIPBOARD_IMAGE_LOAD_FAILED` | `imageLoadFailed` | ファイルは存在するが画像としてデコードできない | `"Failed to load the image."` |
| `CLIPBOARD_IMAGE_ENCODE_FAILED` | `imageEncodingFailed` | ペーストされた画像を PNG に再エンコードできない | `"Failed to encode the pasted image."` |
| `CLIPBOARD_UNAVAILABLE` | `pasteboardUnavailable` | 名前付き / ユニークペーストボードを解決できない | `"The requested pasteboard is unavailable."` |
| `CLIPBOARD_CANNOT_REMOVE_GENERAL` | `cannotRemoveGeneralPasteboard` | `removePasteboard(.general)` を呼び出した | `"The general pasteboard cannot be removed."` |
| `CLIPBOARD_NO_MATCHING_ITEM` | `noMatchingItem` | 要求した型を持つアイテムがない | `"No clipboard item matches the requested type."` |
| `CLIPBOARD_LOAD_FAILED` | `providerLoadFailed` | `NSItemProvider` がアイテムのロードに失敗した | `"Failed to load the clipboard item."` |
| `CLIPBOARD_UNEXPECTED_TYPE` | `unexpectedType` | アイテムを要求した型へ変換できない | `"The clipboard item could not be converted to the requested type."` |
| `CLIPBOARD_FILE_COPY_FAILED` | `fileCopyFailed` | ペーストされたファイルの一時領域へのコピーに失敗した | `"Failed to copy the pasted file."` |
| `CLIPBOARD_CANCELLED` | `cancelled` | 呼び出し元がロードをキャンセルした | `"The clipboard load was cancelled."` |
| `CLIPBOARD_TIMED_OUT` | `timedOut` | 操作がタイムアウトした | `"The clipboard operation timed out."` |
| `CLIPBOARD_DETECTION_FAILED` | `detectionFailed` | データ検出システムが失敗を報告した | `"Pattern detection failed."` |
| `CLIPBOARD_UNKNOWN` | `unknown` | 分類できないシステムエラー | `"An unknown error occurred."` |

空のクリップボードは、これらのエラーには**該当しません**。`read` は `numberOfItems == 0` を返し、`readData` は `nil` を返します。いずれも正常な状態です。

```swift
Task {
    do {
        try await IosClipboardManager.shared.copy(.url("example.com"), scope: scope)
    } catch ClipboardError.invalidURL {
        // スキームがない
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorDescription ?? "nil")
    }
}
```

---

## macOS

- ライブラリ: `mac-native-toolkit-1.3.0.xcframework`
- 最小デプロイメントターゲット: macOS 15
- 対応範囲: コピー / 追記、読み取りとスナップショット、名前付き・ユニークペーストボードのライフサイクル、パターン検出（macOS 15.4 以降）、変更監視、そして配置するだけで使える `PasteButton` を提供します。

### MacClipboardManager

`MacClipboardManager` は、`NSPasteboard` をラップするシングルトンクラスです。

本節のスクリーンショットは `MacLibraryExample` のものです。同アプリの Clipboard 画面は、以下の節と同じ順序で操作をまとめています。

<p align="center">
    <img src="images/mac/clipboard/Example_MacClipboardManager_Overview.png" alt="Example_MacClipboardManager_Overview" width="400" />
</p>

### セットアップ

1. `mac-native-toolkit-1.3.0.xcframework` を Xcode プロジェクトに追加します（プロジェクトにドラッグし、ターゲットの Frameworks, Libraries, and Embedded Content で "Embed & Sign" に設定します）。
2. クリップボードを使用するファイルでライブラリをインポートします。

```swift
import MacLibrary
```

追加の初期化や entitlement は不要です。

#### スレッド

すべての操作はメインアクター上で `NSPasteboard` に到達します。非同期メソッドは `async throws` なので、`Task` から呼び出してください。即座に完了する 4 つの操作は同期メソッドです: `accessBehavior(scope:)`、`startObserving(scope:interval:onEvent:)`、`stopObserving()`、`checkForegroundChange(scope:)`、および `makePasteButton` ファクトリです。

#### 2 つの呼び出し形式

各非同期操作には 2 つの形式があります。`async throws` 形式は Swift の呼び出し側向けです。`completion:` 形式は Unity ブリッジ向けで、C ABI をまたいで Swift のエラー処理を運べないため、`(isSuccess, value, errorCode, errorMessage)` として結果を返します。

```swift
// Swift
let ownership = try await MacClipboardManager.shared.copy(content)

// コールバック
MacClipboardManager.shared.copy(content) { isSuccess, ownership, errorCode, errorMessage in
    // メインアクター上でちょうど 1 回だけ実行されます
}
```

#### コンテンツは型識別子とバイト列の辞書です

`ClipboardContent` は item の順序付きリストを持ち、各 item は uniform type identifier からバイト列への辞書を持ちます。`.plainText` のような便宜的な case はありません。**書いたものがそのままペーストボードに載ります。**

```swift
let content = ClipboardContent(items: [
    ClipboardItemData(representations: [
        "public.utf8-plain-text": Data("Copied from MacLibraryExample.".utf8)
    ])
])
```

#### 既定値

| パラメータ | 既定値 | 意味 |
|---|---|---|
| `scope` | `.general` | システムのペーストボード |
| `options` | `.default` | `localOnly: true` |
| `interval`（監視） | `0.5` 秒 | ポーリング間隔。0 より大きく 60 秒以下 |
| `timeout`（ペーストボタン） | `15` 秒 | 貼り付けた item をロードする期限 |

### スコープ

スコープは `.general`、`.named(String)`、`.unique(String)` のいずれかです。general ペーストボードは常に存在します。名前付き・ユニークペーストボードは作成が必要で、**アプリを終了しても解放されません**。`removePasteboard(_:)` で解放してください。

#### 名前付きペーストボードの作成

`createPasteboard` はペーストボードを作成しますが、**同じ名前が既にある場合はそれを取得します**。そのため同じ名前で 2 回呼んでも、内容を保ったまま同じペーストボードが返ります。

```swift
Task {
    let scope = try await MacClipboardManager.shared.createPasteboard(.named("nt-sample"))
}
```

#### ユニークペーストボードの作成

ユニークペーストボードには毎回新しいシステム名が割り当てられます。2 つ目を作成すると 1 つ目を指す名前が失われるため、新しく作る前に前のものを解放してください。

```swift
Task {
    let scope = try await MacClipboardManager.shared.createPasteboard(.unique)
}
```

#### 現在のペーストボードの削除

```swift
Task {
    try await MacClipboardManager.shared.removePasteboard(scope)
}
```

#### general の削除（エラー 1508）

標準ペーストボードは解放できません。

```swift
Task {
    do {
        try await MacClipboardManager.shared.removePasteboard(.general)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1508
    }
}
```

#### 空の名前でのペーストボード作成（エラー 1505）

空の名前は拒否されます。

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.createPasteboard(.named(""))
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1505
    }
}
```

### コピー

`copy` はペーストボードの所有権を取得して内容を置き換え、後で `append` が必要とする `PasteboardOwnership` を返します。

#### テキストのコピー

```swift
Task {
    let ownership = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: [
                "public.utf8-plain-text": Data("Copied from MacLibraryExample.".utf8)
            ])
        ]),
        scope: scope
    )
}
```

#### URL のコピー

```swift
Task {
    _ = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: [
                "public.url": Data("https://www.apple.com".utf8)
            ])
        ]),
        scope: scope
    )
}
```

#### 画像のコピー

```swift
Task {
    _ = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: ["public.png": pngData])
        ]),
        scope: scope
    )
}
```

#### 複数 item のコピー

すべての item がペーストボードに載ります。**そのうちどれを使うかは、受け取る側のアプリが決めます。** 例えば TextEdit はすべてを貼り付けます。

```swift
Task {
    _ = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: ["public.utf8-plain-text": Data("first".utf8)]),
            ClipboardItemData(representations: ["public.utf8-plain-text": Data("second".utf8)]),
        ]),
        scope: scope
    )
}
```

#### 複数 representation のコピー

1 つの item が同じ内容を 2 つの形式で持ちます。片方を読めないアプリでも、もう片方を見つけられます。

```swift
Task {
    _ = try await MacClipboardManager.shared.copy(
        ClipboardContent(items: [
            ClipboardItemData(representations: [
                "public.utf8-plain-text": Data(text.utf8),
                "public.rtf": Data(rtf.utf8),
            ])
        ]),
        scope: scope
    )
}
```

#### 空のコピー（エラー 1501）

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.copy(ClipboardContent(items: []), scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1501
    }
}
```

#### representation が空の item のコピー（エラー 1502）

representation を持たない item は拒否されます。

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.copy(
            ClipboardContent(items: [ClipboardItemData(representations: [:])]),
            scope: scope
        )
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1502
    }
}
```

### コピーオプション

`ClipboardCopyOptions(localOnly:)` は、内容を Universal Clipboard で他のデバイスへ提供するかどうかを決めます。

#### localOnly の既定値は true です

**明示的に指定しない限り、コピーした内容は他のデバイスへ共有されません。** `ClipboardCopyOptions.default` は `localOnly: true` であり、options を渡さない `copy` はこれを使用します。内容を他のデバイスへ渡したい場合は、`localOnly: false` を明示的に指定してください。

```swift
Task {
    let ownership = try await MacClipboardManager.shared.copy(
        content,
        options: ClipboardCopyOptions(localOnly: false),   // 他のデバイスへ共有する
        scope: scope
    )
}
```

2026-09-03 に macOS 26.3 と iOS 18.7.2 の間で Handoff 経由で計測しました。`localOnly: false` では約 1 秒で相手のデバイスに到達し、`localOnly: true` では到達せず、相手のデバイスは自身のクリップボードを保持し続けました。これは 1 組のデバイスでの計測であるため、すべてのデバイスと OS での保証ではなく、その組み合わせでの根拠として扱ってください。

### 追記

`append` は **ownership が指すペーストボード**に item を追加します。`append` 自体は scope を取りません。ownership が scope を運びます。

#### コピーしてから追記する

```swift
Task {
    let ownership = try await MacClipboardManager.shared.copy(content, scope: scope)
    let appended = try await MacClipboardManager.shared.append(more, ownership: ownership)
}
```

#### append は追記先のプライバシー設定を引き継ぎます

`localOnly: true` でコピーした内容に追記しても、ペーストボードが再公開されることはありません。元の内容も追記した item も、他のデバイスには届きません。上記と同じデバイスの組み合わせで 2026-09-03 に計測しました。

#### 所有権を失った状態での追記（エラー 1511）

他のアプリを含め、何かがペーストボードに書き込んだ時点で所有権は失われます。`append` は先に changeCount を照合し、書き込まずに throw します。

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.append(late, ownership: stale)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1511
    }
}
```

自分のアプリが所有権を奪った場合も、他のアプリが奪った場合も、エラーは同じです。ライブラリは「所有権がもう成立しない」ことを報告するのであって、誰が奪ったかは報告しません。

### 読み取り / 検査

#### Read

`read` はすべての item を、その全 representation とともに返します。

```swift
Task {
    let result = try await MacClipboardManager.shared.read(scope: scope)
    for (index, item) in result.items.enumerated() {
        print(index, item.totalBytes, item.representations.keys.sorted())
    }
}
```

返ってくる内容について、コードを書く前に知っておくべきことが 2 つあります。

**item は、書いた側が指定した数より多くの representation を持ちます。** AppKit が独自にテキスト形式を追加するためです。TextEdit からリッチテキストをコピーすると、`public.rtf`、`public.utf8-plain-text`、`public.utf16-external-plain-text` が同時に載ります。必要な型を照合してください。型の集合を完全一致で比較しないでください。

**`totalBytes` は全 item・全 representation の合計であり、コピーした対象の大きさではありません。** Finder でテキストファイルを 1 つコピーすると約 850 KB になりました。ペーストボードがファイルのアイコンを `com.apple.icns` として一緒に運ぶためです。

#### 特定の型の読み取り

`readData` は 1 つの型のバイト列を返し、その型が無い場合は `nil` を返します。**型が無いことは通常の結果であり、エラーではありません。**

```swift
Task {
    let data = try await MacClipboardManager.shared.readData(
        utType: "public.utf8-plain-text",
        scope: scope
    )
    print(data?.count ?? -1)   // 平文が無い場合は nil
}
```

Finder でコピーしたファイルは `public.utf8-plain-text` を持っており、そのバイト列は一般にファイルの完全パスです。読み取った内容は、利用者が渡すつもりでなかった情報を含みうるものとして扱ってください。

#### Snapshot

`snapshot` は内容を読まずに、型と changeCount を報告します。

```swift
Task {
    let snapshot = try await MacClipboardManager.shared.snapshot(scope: scope)
    print(snapshot.itemTypes.count, snapshot.changeCount)
}
```

#### 型フィルタ付きの Snapshot

```swift
Task {
    let snapshot = try await MacClipboardManager.shared.snapshot(
        matchingTypes: ["public.utf8-plain-text"],
        scope: scope
    )
    print(snapshot.matchingItemIndexes)
}
```

#### 空フィルタでの Snapshot（エラー 1512）

空のフィルタは何にも一致しません。それは呼び出し側から見ると「ペーストボードが空」と区別がつかないため、拒否されます。

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.snapshot(matchingTypes: [], scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1512
    }
}
```

#### Access Behavior

同期メソッドです。システムがこのペーストボードのプログラムからの読み取りをどう扱うかを報告します。

```swift
let behavior = try MacClipboardManager.shared.accessBehavior(scope: scope)
```

### 検出

検出には **macOS 15.4 以降**が必要です。それ未満では、内容を読まずに `detectionUnavailable`（1513）を throw します。

#### パターンの検出

内容を読まずに、どのパターンが一致するかを報告します。

```swift
Task {
    let found = try await MacClipboardManager.shared.detectPatterns(
        [.probableWebURL, .links, .emailAddresses],
        scope: scope
    )
}
```

#### 値の検出

一致した値を返します。**この操作は内容を読み取ります**ので、利用者の操作を起点に呼び出してください。

```swift
Task {
    let values = try await MacClipboardManager.shared.detectValues(
        [.probableWebURL, .links, .emailAddresses],
        scope: scope
    )
    print(values.links.count, values.emailAddresses.count)
}
```

#### メタデータの検出

```swift
Task {
    let metadata = try await MacClipboardManager.shared.detectMetadata(scope: scope)
}
```

#### パターンを指定しない検出（エラー 1503）

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.detectPatterns([], scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode)   // 1503
    }
}
```

### 監視

#### 監視の開始

同期メソッドです。`onEvent` は、ペーストボードが変化するたびにメインアクター上で実行されます。

```swift
try MacClipboardManager.shared.startObserving(scope: scope) { event in
    print(event.changeCount)
}
```

アプリが非アクティブの間、監視は停止し、復帰時に照合します。**バックグラウンドの間に 3 回変化があっても、届くイベントは 1 回です。** ペーストボードは過去に保持していた内容の履歴を持たないためです。

#### 不正な間隔（エラー 1523）

間隔は 0 より大きく、60 秒以下である必要があります。

```swift
do {
    try MacClipboardManager.shared.startObserving(scope: scope, interval: 0) { _ in }
} catch let error as ClipboardError {
    print(error.errorCode)   // 1523
}
```

#### 監視の停止

冪等で、throw しません。画面が破棄されるときに呼び出してください。マネージャは共有されているため、呼ばないとポーリングが続きます。

```swift
MacClipboardManager.shared.stopObserving()
```

#### 前面復帰時の変更確認

同期メソッドです。このアプリが最後に見た時点からペーストボードが変化したかを報告し、そのスコープでの初回呼び出しでは `true` を返します。

```swift
let changed = try MacClipboardManager.shared.checkForegroundChange(scope: scope)
```

**監視と併用せず、監視の代わりに使用してください。** 両者は同じ基準を共有するため、監視が動作している間は、この呼び出しはほぼ常に `false` を返します。ポーリングが既に変化を検出し、`onEvent` で報告済みだからです。

### ペーストコントロール

`makePasteButton` は、システムのペーストボタンを `NSView` として返します。同期メソッドです。ビューの生成は即座に完了するファクトリ操作であり、押下時に始まるロードは `onPaste` で報告されます。

```swift
let button = try MacClipboardManager.shared.makePasteButton(
    acceptedTypes: ["public.utf8-plain-text", "public.png"],
    timeout: 5
) { result in
    print(result.items.count, result.failures.count, result.isPartial)
}
```

SwiftUI では `NSViewRepresentable` でホストし、**生成は 1 回だけ**にしてください。呼び出すたびにローダーが登録されます。

```swift
struct PasteButtonHost: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

<p align="center">
    <img src="images/mac/clipboard/Example_MacClipboardManager_PasteControl.png" alt="Example_MacClipboardManager_PasteControl" width="400" />
</p>

システムのコントロールの挙動から、次の 3 点が導かれます。

**このボタンは general スコープ専用です。** 他の呼び出しがどのスコープを使っていても、システムのペーストボードから貼り付けます。

**システムは `acceptedTypes` に一致するものだけをローダーに渡します。** 受け入れていない型の item は届きません。受け入れる item と受け入れない item を 1 つずつ持つペーストボードを貼り付けても、結果は item 1 件であり、部分失敗にはなりません。

**ボタンは常に押せる状態です。** 受け入れる型がペーストボードに無くても無効化されません。

#### 不正な型識別子（エラー 1504）

システムが解決できない型識別子は、押下時ではなくボタンの生成時に拒否されます。

```swift
do {
    _ = try MacClipboardManager.shared.makePasteButton(acceptedTypes: ["not a uti"]) { _ in }
} catch let error as ClipboardError {
    print(error.errorCode)   // 1504
}
```

### クリア

`clear` はペーストボードを空にし、**ペーストボードの新しい changeCount** を返します。これは `clearContents()` が返す値であり、削除した item の数ではありません。

```swift
Task {
    let changeCount = try await MacClipboardManager.shared.clear(scope: scope)
}
```

### エラー処理

すべての操作は `ClipboardError` を throw します。このエラーは `errorCode` と `errorMessage` を持ちます。

```swift
Task {
    do {
        _ = try await MacClipboardManager.shared.copy(content, scope: scope)
    } catch let error as ClipboardError {
        print(error.errorCode, error.errorMessage)
    }
}
```

| コード | ケース | 発生条件 |
|---|---|---|
| 1501 | `emptyContent` | item が 0 件の `copy` / `append` |
| 1502 | `emptyRepresentations` | representation を持たない item |
| 1503 | `emptyDetectionPatterns` | パターン集合が空の検出 |
| 1504 | `invalidTypeIdentifier` | システムが解決できない型識別子 |
| 1505 | `invalidPasteboardName` | 空、または不正なペーストボード名 |
| 1506 | `contentTooLarge` | 内容がサイズ上限を超えた |
| 1507 | `pasteboardUnavailable` | 名前付きペーストボードを解決できない |
| 1508 | `cannotReleaseStandardPasteboard` | 標準ペーストボードへの `removePasteboard` |
| 1509 | `writeRejected` | ペーストボードが書き込みを拒否した |
| 1510 | `appendRejected` | 所有権は成立しているが、ペーストボードが追記を拒否した |
| 1511 | `ownershipLost` | コピー以降に他の何かがペーストボードに書き込んだ |
| 1512 | `emptyTypeFilter` | フィルタが空の `snapshot` |
| 1513 | `detectionUnavailable` | macOS 15.4 未満での検出 |
| 1514 | `detectionDenied` | 検出中に利用者がアクセスを拒否した（後述） |
| 1515 | `detectionFailed` | それ以外の理由で検出が失敗した |
| 1521 | `pasteLoadFailed` | 貼り付け後に item をロードできなかった |
| 1522 | `pasteLoadTimedOut` | 貼り付けのロードが期限を超えた |
| 1523 | `invalidConfiguration` | 監視間隔が 0〜60 秒の範囲外 |
| 1524 | `cancelled` | 操作がキャンセルされた |
| 1599 | `unknown` | それ以外 |

#### 1514 について

1514 は、検出中に利用者がペーストボードの内容へのアクセスを拒否したことを表します。**ただし macOS でこの経路が発生することは未確認です。** 検証時に検出のプロンプトは一度も表示されておらず、拒否は 1515 として届く可能性があります。

**1514 だけで分岐しないでください。** 拒否と通常の検出失敗を同じ扱いにし、どちらも「内容を検出できなかった」として処理してください。この扱いであれば、どちらに転んでも正しく動作します。

#### 通常の利用では発生しないエラーコード

1506、1507、1509、1510、1521、1522、1524 は、API が報告しうるものの、アプリケーションから意図的に発生させることが難しい条件を表します。受け取ったコードを調べられるように一覧に載せているだけであり、それぞれに分岐を書く必要はありません。
