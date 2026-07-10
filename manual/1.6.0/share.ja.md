# Share 機能

Language:

- 日本語（このページ）
- English: [share.md](share.md)
- 한국어: [share.ko.md](share.ko.md)

← [マニュアルトップへ戻る](index.ja.md)

---

## 目次

- [Android](#android)
  - [セットアップ](#セットアップ)
  - [テキスト共有](#テキスト共有)
    - [テキストを共有](#テキストを共有)
    - [URL を共有](#url-を共有)
    - [リッチプレビュー付きテキスト共有](#リッチプレビュー付きテキスト共有)
    - [カスタムチューザーアクション付きテキスト共有](#カスタムチューザーアクション付きテキスト共有)
    - [チューザーアクションコールバック](#チューザーアクションコールバック)
    - [件名・タイトル付き共有](#件名タイトル付き共有)
  - [画像共有](#画像共有)
  - [複数画像の共有](#複数画像の共有)
  - [ファイル共有](#ファイル共有)
  - [複数ファイルの共有](#複数ファイルの共有)
  - [Direct Share Target](#direct-share-target)
    - [Direct Share Target を登録](#direct-share-target-を登録)
    - [Direct Share Target を削除](#direct-share-target-を削除)
  - [コールバック付き共有](#コールバック付き共有)
    - [基本コールバック](#基本コールバック)
    - [リッチプレビュー付きコールバック](#リッチプレビュー付きコールバック)
    - [保留中のコールバックをキャンセル](#保留中のコールバックをキャンセル)
  - [受信した共有コンテンツの処理](#受信した共有コンテンツの処理)
  - [エラー処理](#エラー処理)
- [iOS](#ios)
  - [IosShareManager](#iossharemanager)
  - [セットアップ](#セットアップ-1)
  - [テキスト共有](#テキスト共有-1)
    - [テキストを共有](#テキストを共有-1)
    - [URL を共有](#url-を共有-1)
    - [プレビュー付き URL 共有](#プレビュー付き-url-共有)
  - [画像共有](#画像共有-1)
    - [画像を共有](#画像を共有)
    - [複数画像を共有](#複数画像を共有)
  - [ファイル共有](#ファイル共有-1)
    - [ファイルを共有](#ファイルを共有)
    - [複数ファイルを共有](#複数ファイルを共有)
  - [組み合わせコンテンツ](#組み合わせコンテンツ)
    - [複数アイテムを共有](#複数アイテムを共有)
    - [件名付き共有](#件名付き共有)
    - [アクティビティタイプの除外](#アクティビティタイプの除外)
  - [エラー処理](#エラー処理-1)

---

## Android

- ライブラリ: `android-native-toolkit-1.2.0.aar`
- 最小 SDK: Android 12 (API 31)
- カスタムチューザーアクション: Android 14 (API 34) 以上

### セットアップ

#### Android ネイティブ（AAR）

1. `android-native-toolkit-1.2.0.aar` を `app/libs` に配置する。
2. `app/build.gradle.kts` に依存関係を追加する:

```kotlin
dependencies {
    implementation(files("libs/android-native-toolkit-1.2.0.aar"))
}
```

3. ファイル・画像共有のために `AndroidManifest.xml` に `FileProvider` を宣言する:

```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths" />
</provider>
```

4. `res/xml/file_paths.xml` を作成する:

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <cache-path name="share_cache" path="." />
    <external-cache-path name="share_external_cache" path="." />
    <files-path name="share_files" path="." />
</paths>
```

---

### テキスト共有

#### テキストを共有

```kotlin
val shareUseCases = ShareUseCases(activity)

try {
    shareUseCases.shareText(
        ShareContent(text = "Hello from native-toolkit"),
        chooserActionsJson = "[]"
    )
} catch (e: ShareDomainError) {
    // エラー処理
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareText.png" alt="Example_ShareSampleScreen_ShareText" width="400" />
</p>

#### URL を共有

```kotlin
shareUseCases.shareText(
    ShareContent(
        text = "https://developer.android.com/",
        mimeType = "text/plain"
    ),
    chooserActionsJson = "[]"
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareURL.png" alt="Example_ShareSampleScreen_ShareURL" width="400" />
</p>

#### リッチプレビュー付きテキスト共有

リッチプレビューには Android 31 以上と有効なサムネイルファイルパスが必要です。

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val file = File(context.cacheDir, "share_preview.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareUseCases.shareText(
    ShareContent(
        text = "https://developer.android.com/",
        mimeType = "text/plain"
    ),
    chooserActionsJson = "[]",
    SharePreviewOptions(
        title = "Introducing content previews",
        thumbnailPath = file.absolutePath
    )
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareTextWithRichPreview.png" alt="Example_ShareSampleScreen_ShareTextWithRichPreview" width="400" />
</p>

#### カスタムチューザーアクション付きテキスト共有

カスタムチューザーアクションは Android 14 (API 34) 以上でのみ有効です。それ以前のデバイスでは `chooserActionsJson` パラメータは無視されます。

- `intentAction` は**一意・非空**であり、`android.intent.action.SEND` は使用できません。
- 推奨 namespace: `${applicationId}.share.action.<name>`

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_edit)
val iconBase64 = ByteArrayOutputStream().use { baos ->
    bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
    Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
}

val chooserActionsJson = JSONArray().put(
    JSONObject().apply {
        put("label", "Custom")
        put("iconBase64", iconBase64)
        put("intentAction", "com.example.myapp.share.action.CUSTOM")
    }
).toString()

shareUseCases.shareText(
    ShareContent(
        text = "Shared with a custom chooser action",
        mimeType = "text/plain"
    ),
    chooserActionsJson = chooserActionsJson
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareTextWithCustomAction.png" alt="Example_ShareSampleScreen_ShareTextWithCustomAction" width="400" />
</p>

カスタムアクションがタップされたときにコールバックを受け取るには、[チューザーアクションコールバック](#チューザーアクションコールバック) を参照してください。

#### チューザーアクションコールバック

`AndroidManifest.xml` に `BroadcastReceiver` を宣言します。`<action>` の `android:name` は `chooserActionsJson` に渡した `intentAction` と一致させる必要があります。

```xml
<receiver
    android:name=".ShareChooserActionReceiver"
    android:exported="false">
    <intent-filter>
        <action android:name="com.example.myapp.share.action.CUSTOM" />
    </intent-filter>
</receiver>
```

レシーバーを実装します:

```kotlin
class ShareChooserActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        if (context != null) {
            Toast.makeText(context, "Custom chooser action tapped", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        const val ACTION_CUSTOM_CHOOSER = "com.example.myapp.share.action.CUSTOM"
    }
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ChooserActionCallback.png" alt="Example_ShareSampleScreen_ChooserActionCallback" width="400" />
</p>

#### 件名・タイトル付き共有

`subject` はメールの件名を設定します。`title` は Sharesheet のタイトルを設定します。

```kotlin
shareUseCases.shareText(
    ShareContent(
        text = "Body text shared from native-toolkit",
        title = "Choose an app",
        subject = "Sample subject line",
        mimeType = "text/plain"
    ),
    chooserActionsJson = "[]"
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithSubjectAndTitle.png" alt="Example_ShareSampleScreen_ShareWithSubjectAndTitle" width="400" />
</p>

---

### 画像共有

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_share)
val file = File(context.cacheDir, "share_sample.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareUseCases.shareImage(file.absolutePath, "image/png")
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareImage.png" alt="Example_ShareSampleScreen_ShareImage" width="400" />
</p>

---

### 複数画像の共有

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_share)
val file1 = File(context.cacheDir, "share_sample_1.png")
val file2 = File(context.cacheDir, "share_sample_2.png")
file1.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
file2.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareUseCases.shareImages(listOf(file1.absolutePath, file2.absolutePath))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareMultipleImages.png" alt="Example_ShareSampleScreen_ShareMultipleImages" width="400" />
</p>

---

### ファイル共有

```kotlin
val file = File(context.cacheDir, "share_sample.txt")
    .apply { writeText("Share sample from native-toolkit") }

shareUseCases.shareFile(file.absolutePath)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareFile.png" alt="Example_ShareSampleScreen_ShareFile" width="400" />
</p>

---

### 複数ファイルの共有

```kotlin
val file1 = File(context.cacheDir, "share_sample_1.txt")
    .apply { writeText("Share sample 1 from native-toolkit") }
val file2 = File(context.cacheDir, "share_sample_2.txt")
    .apply { writeText("Share sample 2 from native-toolkit") }

shareUseCases.shareFiles(listOf(file1.absolutePath, file2.absolutePath))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareMultipleFiles.png" alt="Example_ShareSampleScreen_ShareMultipleFiles" width="400" />
</p>

---

### Direct Share Target

Direct Share Target は、ユーザーがアプリを選択しなくても Sharesheet に候補として表示されるショートカットです。

#### Direct Share Target を登録

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val baos = ByteArrayOutputStream()
bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
val iconBytes = baos.toByteArray()

shareUseCases.registerDirectShareTarget(
    DirectShareTarget(
        id = "sample_1",
        label = "Sample User",
        category = "android.shortcut.conversation"
    ),
    iconBytes
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_RegisterDirectShareTarget.png" alt="Example_ShareSampleScreen_RegisterDirectShareTarget" width="400" />
</p>

#### Direct Share Target を削除

```kotlin
shareUseCases.removeDirectShareTargets(listOf("sample_1"))
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_RemoveDirectShareTarget.png" alt="Example_ShareSampleScreen_RemoveDirectShareTarget" width="400" />
</p>

---

### コールバック付き共有

`shareWithCallback` は Sharesheet を開き、ユーザーが選択したアプリのパッケージ名を `onResult` で通知します。`onFinished` は選択の有無にかかわらず Sharesheet が閉じられたときに呼ばれます。

#### 基本コールバック

```kotlin
shareUseCases.shareWithCallback(
    ShareContent(text = "Hello with callback from native-toolkit")
) { pkg ->
    // pkg == null の場合、選択されたがパッケージ名が取得できなかった
    val status = if (pkg != null) "Selected: $pkg" else "Shared (package unavailable)"
}
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallback.png" alt="Example_ShareSampleScreen_ShareWithCallback" width="400" />
</p>

ユーザーが選択する前にキャンセルする場合は `cancelPendingCallback()` を呼びます。

#### リッチプレビュー付きコールバック

```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.mipmap.sym_def_app_icon)
val file = File(context.cacheDir, "callback_preview.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }

shareUseCases.shareWithCallback(
    ShareContent(
        text = "https://developer.android.com/",
        mimeType = "text/plain"
    ),
    SharePreviewOptions(
        title = "Callback with rich preview",
        thumbnailPath = file.absolutePath
    ),
    onResult = { pkg ->
        val status = if (pkg != null) "Selected: $pkg" else "Shared (package unavailable)"
    },
    onFinished = {
        // Sharesheet が閉じられた
    }
)
```

<p align="center">
    <img src="images/android/share/Example_ShareSampleScreen_ShareWithCallbackRichPreview.png" alt="Example_ShareSampleScreen_ShareWithCallbackRichPreview" width="400" />
</p>

#### 保留中のコールバックをキャンセル

保留中の `shareWithCallback` BroadcastReceiver をキャンセルします。画面終了時に呼び出してレシーバーのリークを防いでください。

```kotlin
shareUseCases.cancelPendingCallback()
```

Composable 画面が破棄されたときに自動でキャンセルする場合:

```kotlin
DisposableEffect(shareUseCases) {
    onDispose { shareUseCases.cancelPendingCallback() }
}
```

---

### 受信した共有コンテンツの処理

サンプルアプリでは、他アプリから `ACTION_SEND` / `ACTION_SEND_MULTIPLE` で送られた共有コンテンツの受信も示しています。

受信するには `AndroidManifest.xml` の Activity に intent-filter を追加し、`onCreate` / `onNewIntent` で処理します:

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTop">
    <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="text/*" />
    </intent-filter>
    <intent-filter>
        <action android:name="android.intent.action.SEND" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="image/*" />
    </intent-filter>
    <intent-filter>
        <action android:name="android.intent.action.SEND_MULTIPLE" />
        <category android:name="android.intent.category.DEFAULT" />
        <data android:mimeType="image/*" />
    </intent-filter>
</activity>
```

---

### エラー処理

`ShareUseCases` は `ShareDomainError` のサブタイプをスローします。

| エラー | 原因 | エラーメッセージ |
|---|---|---|
| `EmptyContent` | `text` が空白 | `"Share content is empty. Please provide text or a file path."` |
| `FileNotFound` | ファイルパスが存在しない | `"File not found: <path>"` |
| `IllegalFileAccess` | アクセス可能なディレクトリ外のファイル | `"File cannot be shared: <path>. Ensure the file is in a supported directory."` |
| `InvalidMimeType` | 未対応の MIME タイプ | `"Invalid MIME type: <mimeType>"` |
| `NoShareTarget` | 共有 Intent を処理できるアプリがない | `"No app available to handle this share request."` |
| `DirectShareRegistrationFailed` | ショートカット登録失敗 | `"Failed to register Direct Share target: <reason>"` |
| `EmptyIdList` | `removeDirectShareTargets` の `ids` が空 | `"No shortcut IDs provided for removal."` |
| `EmptyFileList` | `shareFiles` / `shareImages` の `filePaths` が空 | `"No file paths provided for share."` |
| `InvalidBase64Icon` | アイコンの Base64 デコード失敗 | `"Invalid icon data for Direct Share target: <id>"` |

```kotlin
try {
    shareUseCases.shareText(ShareContent(text = "Hello"), chooserActionsJson = "[]")
} catch (e: ShareDomainError.NoShareTarget) {
    // 共有できるアプリがない
} catch (e: ShareDomainError.EmptyContent) {
    // テキストが空白
} catch (e: ShareDomainError) {
    // その他のドメインエラー
}
```

---

## iOS

- ライブラリ: `ios-native-toolkit-1.2.0.xcframework`
- 最小デプロイメントターゲット: iOS 18
- 対応範囲: 送信のみ（`UIActivityViewController` によるシステム共有シートの表示）。受信（Share Extension）は対象外です。

### IosShareManager

`IosShareManager` は、iOS でシステム共有シートを表示するシングルトンクラスです。

<p align="center">
    <img src="images/ios/share/Example_IosShareManager.png" alt="Example_IosShareManager" width="400" />
</p>

### セットアップ

1. `ios-native-toolkit-1.2.0.xcframework` を Xcode プロジェクトに追加します（プロジェクトにドラッグし、ターゲットの Frameworks, Libraries, and Embedded Content で "Embed & Sign" に設定します）。
2. 共有シートを表示するファイルでライブラリをインポートします。

```swift
import IosLibrary
```

追加の初期化は不要です。

`IosShareManager.share` には 2 つの呼び出し方式があります。

- `async throws`（ネイティブ Swift 呼び出し元に推奨）: 型付きの `ShareResult` を返し、失敗時は `ShareError` を throw します。
- コールバック（Unity Bridge が使用。Swift でも利用可）: `(isSuccess, completed, activityType, errorMessage)`。

```swift
// async throws（Swift 呼び出し元に推奨）
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.text("Hello")])
        )
        // result.completed == false はユーザーがキャンセルしたことを示します（エラーではありません）
        print(result.completed, result.activityType ?? "nil")
    } catch {
        print(error.localizedDescription)
    }
}

// コールバック（同等）
IosShareManager.shared.share(
    content: ShareContent(items: [.text("Hello")])
) { isSuccess, completed, activityType, errorMessage in
    print(isSuccess, completed, activityType ?? "nil", errorMessage ?? "nil")
}
```

以降の例では `async throws` 方式を使用します。SwiftUI の `Button` アクションは同期クロージャのため、各呼び出しは `Task { ... }` で囲みます。

### テキスト共有

#### テキストを共有

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.text("Shared from IosLibraryExample")])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareText.png" alt="Example_IosShareManager_ShareText" width="400" />
</p>

#### URL を共有

URL は文字列として渡します。ライブラリ側で検証され、`http` / `https` / `file` スキームかつ有効なホストを持つ URL のみ受け付けます（それ以外は `ShareError.invalidURL` が throw されます）。

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.url("https://www.apple.com")])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareURL.png" alt="Example_IosShareManager_ShareURL" width="400" />
</p>

#### プレビュー付き URL 共有

`previewTitle` を指定すると、ネットワーク取得を待たずに共有シートのヘッダにリッチリンクプレビューを即時表示できます。

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(
            items: [.url("https://www.apple.com")],
            previewTitle: "Apple"
        )
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareURLWithPreview.png" alt="Example_IosShareManager_ShareURLWithPreview" width="400" />
</p>

### 画像共有

#### 画像を共有

`.imageFile(path:)` にローカル画像のファイルパスを渡します。ライブラリは `UIImage` として読み込みます（読み込めない場合は `ShareError.imageLoadFailed` を throw します）。

```swift
guard let imagePath = Bundle.main.url(forResource: "app-icon-attachment", withExtension: "png")?.path else {
    return
}

Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.imageFile(path: imagePath)])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareImage.png" alt="Example_IosShareManager_ShareImage" width="400" />
</p>

#### 複数画像を共有

`ShareContent.items` は複数の要素を受け付けるため、複数の画像を一度に共有できます。

```swift
let imagePaths: [String] = /* ローカル画像のファイルパス */

Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: imagePaths.map { .imageFile(path: $0) })
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultipleImages.png" alt="Example_IosShareManager_ShareMultipleImages" width="400" />
</p>

### ファイル共有

#### ファイルを共有

`.file(path:)` にローカルファイルのパスを渡します。ライブラリはファイルの存在を確認します（存在しない場合は `ShareError.fileNotFound` を throw します）。

```swift
let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("share-sample.txt")
try "Shared from IosLibraryExample.".write(to: fileURL, atomically: true, encoding: .utf8)

Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [.file(path: fileURL.path)])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareFile.png" alt="Example_IosShareManager_ShareFile" width="400" />
</p>

#### 複数ファイルを共有

```swift
let fileURLs: [URL] = /* ローカルファイルの URL */

Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: fileURLs.map { .file(path: $0.path) })
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultipleFiles.png" alt="Example_IosShareManager_ShareMultipleFiles" width="400" />
</p>

### 組み合わせコンテンツ

#### 複数アイテムを共有

テキスト・URL・画像・ファイルなど、異なる種類のアイテムを 1 回の共有に混在させられます。

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(items: [
            .text("Check this out"),
            .url("https://www.apple.com")
        ])
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareMultiple.png" alt="Example_IosShareManager_ShareMultiple" width="400" />
</p>

#### 件名付き共有

`subject` は、それに対応するアクティビティ（例: Mail の件名欄）で使用されます。

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(
            items: [.text("Body text")],
            subject: "Sample Subject"
        )
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareWithSubject.png" alt="Example_IosShareManager_ShareWithSubject" width="400" />
</p>

#### アクティビティタイプの除外

`excludedActivityTypes` に生のアクティビティタイプ識別子を渡すと、共有シートから非表示にできます。

```swift
Task {
    let result = try await IosShareManager.shared.share(
        content: ShareContent(
            items: [.url("https://www.apple.com")],
            excludedActivityTypes: [
                "com.apple.UIKit.activity.CopyToPasteboard",
                "com.apple.UIKit.activity.PostToFacebook"
            ]
        )
    )
    print(result.completed, result.activityType ?? "nil")
}
```

<p align="center">
    <img src="images/ios/share/Example_IosShareManager_ShareExcludingActivities.png" alt="Example_IosShareManager_ShareExcludingActivities" width="400" />
</p>

### エラー処理

`async throws` API は失敗時に `ShareError` を throw します。ユーザーのキャンセルはエラーではなく、`ShareResult.completed == false` として通知されます。

| エラー | 原因 | エラーメッセージ |
|---|---|---|
| `noValidItems` | `items` が空 | `"No shareable items were provided."` |
| `invalidURL(String)` | URL 文字列が有効な `http`/`https`/`file` URL でない | `"Invalid URL: <value>."` |
| `imageLoadFailed(path:)` | 指定パスの画像を読み込めない | `"Failed to load image at path: <path>."` |
| `fileNotFound(path:)` | 指定パスのファイルが存在しない | `"File not found at path: <path>."` |
| `noRootViewController` | 表示に使うルートビューコントローラがない | `"No root view controller available to present the share sheet."` |
| `presentationFailed(Error)` | 表示に失敗、またはシステムがエラーを報告 | `"Failed to present the share sheet: <detail>."` |
| `unknown(Error)` | 予期しないエラー | `"An unknown error occurred: <detail>."` |

```swift
Task {
    do {
        let result = try await IosShareManager.shared.share(
            content: ShareContent(items: [.text("Hello")])
        )
        if result.completed {
            // result.activityType 経由で共有成功
        } else {
            // ユーザーがキャンセル
        }
    } catch let error as ShareError {
        // 型付きエラー（例: .noValidItems, .invalidURL, .fileNotFound）
        print(error.localizedDescription)
    } catch {
        // その他のエラー
    }
}
```

コールバック API を使う場合、失敗は `isSuccess == false` と非 nil の `errorMessage` で通知されます。

```swift
IosShareManager.shared.share(
    content: ShareContent(items: [])
) { isSuccess, completed, activityType, errorMessage in
    // isSuccess == false, errorMessage == "No shareable items were provided."
}
```
