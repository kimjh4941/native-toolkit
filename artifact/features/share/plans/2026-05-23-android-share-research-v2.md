# Android シェア機能 調査結果

- 作成日: 2026-05-23
- 改訂日: 2026-05-24（v2: レビュー指摘反映）
- 対象OS: Android
- 対象機能: シェア機能（Share）

---

## 目的

Android のネイティブシェア API を全網羅し、native-toolkit への組み込み設計に必要な情報を整理する。

---

## 調査対象範囲

### In scope
- テキスト・URL のシェア
- 画像のシェア
- ファイルのシェア（FileProvider）
- 複数コンテンツのシェア
- Direct Share（ショートカット経由）
- シェア結果コールバック

### Out of scope
- iOS / macOS / Windows のシェア API
- サードパーティ SDK（Firebase Dynamic Links 等）
- 受信側（Intent Filter）の詳細実装

---

## 公式文書一覧

| タイトル | URL |
|---|---|
| Send simple data to other apps | https://developer.android.com/training/sharing/send |
| Receive simple data from other apps | https://developer.android.com/training/sharing/receive |
| Provide Direct Share targets | https://developer.android.com/training/sharing/direct-share-targets |
| Setting up file sharing | https://developer.android.com/training/secure-file-sharing/setup-sharing |
| Intent API Reference | https://developer.android.com/reference/android/content/Intent |
| ShareCompat.IntentBuilder | https://developer.android.com/reference/androidx/core/app/ShareCompat.IntentBuilder |
| FileProvider API Reference | https://developer.android.com/reference/androidx/core/content/FileProvider |
| ChooserAction API Reference | https://developer.android.com/reference/android/service/chooser/ChooserAction |
| Activity Result API | https://developer.android.com/training/basics/intents/result |

---

## 機能マップ（サブ機能分解）

```
シェア機能
├── テキストシェア
│   ├── 単一テキスト
│   └── テキスト + タイトル
├── URLシェア（テキストシェアと同実装）
├── 画像シェア
│   ├── 単一画像
│   └── 複数画像
├── ファイルシェア
│   ├── 単一ファイル（FileProvider）
│   └── 複数ファイル
├── Direct Share（ショートカット）
│   ├── ショートカット登録
│   └── ショートカット削除
├── ChooserAction（カスタムアクションボタン）
└── シェア結果コールバック
    ├── EXTRA_CHOSEN_COMPONENT（API 22〜33）
    └── ChooserResult.selectedComponent（API 34+）
```

---

## API 全網羅表

### テキスト・URLシェア

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `Intent.ACTION_SEND` | テキスト・URLをシェア | `EXTRA_TEXT: String`, `type: "text/plain"` | なし（Activity 起動） | 受信アプリなし | API 1 |
| `Intent.createChooser()` | システム選択 UI を表示 | `intent`, `title` | Intent | なし | API 5 |
| `Intent.EXTRA_TITLE` | Sharesheet タイトル設定 | `String` | なし | なし | API 1 |
| `Intent.EXTRA_PREVIEW_IMAGE_URI` | Sharesheet プレビュー画像 | `Uri` | なし | URI 権限エラー | API 29 |
| `ShareCompat.IntentBuilder.setText()` | テキストをビルダーで設定 | `text: String` | IntentBuilder | なし | AndroidX Core |

### 画像シェア

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `Intent.ACTION_SEND` | 単一画像シェア | `EXTRA_STREAM: Uri`, `type: "image/*"` | なし | URI 権限エラー | API 1 |
| `Intent.ACTION_SEND_MULTIPLE` | 複数画像シェア | `EXTRA_STREAM: ArrayList<Uri>`, `type: "image/*"` | なし | 空リスト、型不一致 | API 1 |
| `FLAG_GRANT_READ_URI_PERMISSION` | URI 読み取り権限付与 | Intent フラグ | なし | なし | API 1（API 16 以降自動） |

### ファイルシェア（FileProvider）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `FileProvider.getUriForFile()` | content:// URI 生成 | `context`, `authority: String`, `file: File` | Uri | ファイル未存在、パス未定義、`IllegalArgumentException` | AndroidX Core |

### Direct Share

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ShortcutManagerCompat.setDynamicShortcuts()` | Direct Share ターゲット登録 | `context`, `List<ShortcutInfoCompat>` | void | ID 未設定、必須フィールド欠如 | API 25 / AndroidX |
| `ShortcutManagerCompat.pushDynamicShortcut()` | 単一ショートカット追加・更新 | `context`, `ShortcutInfoCompat` | void | 同上 | API 25 / AndroidX |
| `ShortcutManagerCompat.removeLongLivedShortcuts()` | ショートカット削除 | `context`, `List<String>` shortcutIds | void | 存在しない ID | API 25 / AndroidX |

### ChooserAction

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ChooserAction.Builder` | カスタムアクションボタン生成 | `icon: Icon`, `label: String`, `action: PendingIntent` | ChooserAction | PendingIntent が無効 | API 34 |
| `Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS` | Chooser にアクション追加 | `Array<ChooserAction>` | なし | 上限数超過（未公開） | API 34 |

### シェア結果コールバック

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `Intent.createChooser(intent, title, sender)` | コールバック付き Chooser | `IntentSender` | Intent | 無効な PendingIntent | API 29 |
| `Intent.EXTRA_CHOSEN_COMPONENT` | 選択されたアプリ取得（API 22〜33） | なし（BroadcastReceiver で受信） | ComponentName | ユーザーキャンセル時 null | API 22 |
| `ChooserResult.selectedComponent` | 選択されたアプリ取得（API 34+） | なし | ComponentName | ユーザーキャンセル時 null | API 34 |

---

## 実装リスク

| リスク | 詳細 | 対策 |
|---|---|---|
| ファイル URI エラー | file:// URI は API 24 以降の他アプリから拒否される | FileProvider で content:// URI に変換 |
| 権限エラー | EXTRA_STREAM URI に読み取り権限がない | `FLAG_GRANT_READ_URI_PERMISSION` を必ず付与 |
| MIME 型の不一致 | MIME 型を誤ると受信アプリが表示されない | 適切な MIME 型を設定、`*/*` は非推奨 |
| Direct Share 廃止 API | `ChooserTargetService` は廃止済み | `ShortcutManagerCompat` を使用 |
| コールバック API バージョン分岐 | `ChooserResult` は API 34 以降、`EXTRA_CHOSEN_COMPONENT` は API 22〜33 | API バージョン分岐で対応 |
| BroadcastReceiver リーク | `registerReceiver` を `unregisterReceiver` しないとリークが発生 | ワンショット実装または呼び出し元でライフサイクル管理 |
| Android 14 registerReceiver フラグ | API 34 以降は `RECEIVER_NOT_EXPORTED` または `RECEIVER_EXPORTED` が必須 | API バージョン分岐でフラグを付与 |
| Direct Share カテゴリ不正 | 任意文字列を `setCategories` に渡すと Sharesheet に表示されない | `android.shortcut.conversation` など定義済み定数を使用 |
| Predictive Back（API 33+） | Android 13 以降で Chooser UI の戻る動作が変化 | Chooser 側の制御のため `enableOnBackInvokedCallback` の設定は不要 |
| ProGuard / R8 難読化 | `ShortcutInfoCompat` や `FileProvider` が難読化されると動作しなくなる | ProGuard ルールで keep 設定を追加 |

---

## サンプルコード集

### getMimeType ユーティリティ

```kotlin
fun getMimeType(file: File): String {
    val extension = file.extension.lowercase()
    return MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension) ?: "*/*"
}

fun getMimeTypeFromUri(context: Context, uri: Uri): String {
    return context.contentResolver.getType(uri) ?: "*/*"
}
```

### テキストシェア

```kotlin
fun shareText(context: Context, text: String, title: String? = null) {
    val sendIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_TEXT, text)
        title?.let { putExtra(Intent.EXTRA_TITLE, it) }
        type = "text/plain"
    }
    context.startActivity(Intent.createChooser(sendIntent, null))
}
```

### URL シェア

URL シェアはテキストシェアと同実装。`EXTRA_TEXT` に URL 文字列を渡し、`type = "text/plain"` を設定する。

```kotlin
fun shareUrl(context: Context, url: String) = shareText(context, url)
```

### ShareCompat.IntentBuilder によるテキストシェア（推奨）

従来の `Intent` 直接生成に比べ、ビルダーパターンでミスが起きにくい。`Activity` コンテキストが必要。

```kotlin
fun shareTextCompat(activity: Activity, text: String, subject: String? = null) {
    ShareCompat.IntentBuilder(activity)
        .setText(text)
        .setType("text/plain")
        .apply { subject?.let { setSubject(it) } }
        .startChooser()
}
```

### 単一画像シェア

```kotlin
fun shareImage(context: Context, imageUri: Uri, mimeType: String = "image/*") {
    val shareIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_STREAM, imageUri)
        type = mimeType
        flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
    }
    context.startActivity(Intent.createChooser(shareIntent, null))
}
```

### 複数画像シェア

```kotlin
fun shareMultipleImages(context: Context, imageUris: ArrayList<Uri>) {
    val shareIntent = Intent().apply {
        action = Intent.ACTION_SEND_MULTIPLE
        putParcelableArrayListExtra(Intent.EXTRA_STREAM, imageUris)
        type = "image/*"
        flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
    }
    context.startActivity(Intent.createChooser(shareIntent, null))
}
```

### ファイルシェア（FileProvider）

FileProvider を使用するには `AndroidManifest.xml` と `res/xml/file_paths.xml` の設定が必要（後述）。

```kotlin
fun shareFile(context: Context, file: File) {
    val contentUri = FileProvider.getUriForFile(
        context,
        "${context.packageName}.fileprovider",
        file
    )
    val shareIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_STREAM, contentUri)
        type = getMimeType(file)
        flags = Intent.FLAG_GRANT_READ_URI_PERMISSION
    }
    context.startActivity(Intent.createChooser(shareIntent, null))
}
```

#### AndroidManifest.xml への FileProvider 宣言

```xml
<manifest>
    <application>
        <provider
            android:name="androidx.core.content.FileProvider"
            android:authorities="${applicationId}.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/file_paths" />
        </provider>
    </application>
</manifest>
```

#### res/xml/file_paths.xml

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <!-- 内部ストレージ: filesDir -->
    <files-path name="files" path="." />
    <!-- 内部ストレージ: cacheDir -->
    <cache-path name="cache" path="." />
    <!-- 外部ストレージ: getExternalFilesDir() -->
    <external-files-path name="external_files" path="." />
</paths>
```

### Direct Share ターゲット登録

```kotlin
fun registerDirectShareTarget(
    context: Context,
    id: String,
    label: String,
    icon: Bitmap,
    intent: Intent
) {
    // category は android.shortcut.conversation など定義済み定数を使用すること。
    // 任意文字列を渡すと Sharesheet に表示されない。
    val shortcut = ShortcutInfoCompat.Builder(context, id)
        .setShortLabel(label)
        .setLongLabel(label)
        .setIcon(IconCompat.createWithAdaptiveBitmap(icon))
        .setIntent(intent)
        .setCategories(setOf("android.shortcut.conversation"))
        .setLongLived(true)
        .build()
    ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
}
```

### ChooserAction（カスタムアクションボタン、API 34+）

```kotlin
@RequiresApi(Build.VERSION_CODES.UPSIDE_DOWN_CAKE)
fun shareWithChooserAction(context: Context, text: String) {
    val sendIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_TEXT, text)
        type = "text/plain"
    }

    val actionPendingIntent = PendingIntent.getBroadcast(
        context, 0,
        Intent("${context.packageName}.CUSTOM_ACTION"),
        PendingIntent.FLAG_IMMUTABLE
    )
    val customAction = ChooserAction.Builder(
        Icon.createWithResource(context, android.R.drawable.ic_menu_share),
        "Custom Action",
        actionPendingIntent
    ).build()

    val chooserIntent = Intent.createChooser(sendIntent, null).apply {
        putExtra(Intent.EXTRA_CHOOSER_CUSTOM_ACTIONS, arrayOf(customAction))
    }
    context.startActivity(chooserIntent)
}
```

### シェア結果コールバック（API 22+）

```kotlin
fun shareWithCallback(context: Context, text: String, onResult: (String?) -> Unit) {
    val sendIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_TEXT, text)
        type = "text/plain"
    }

    // ワンショット BroadcastReceiver でリークを防ぐ
    val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            ctx?.unregisterReceiver(this)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                // API 34+: ChooserResult を使用
                val result = IntentCompat.getParcelableExtra(
                    intent ?: return,
                    Intent.EXTRA_CHOOSER_RESULT,
                    ChooserResult::class.java
                )
                onResult(result?.selectedComponent?.packageName)
            } else {
                // API 22〜33: EXTRA_CHOSEN_COMPONENT を使用
                val component = IntentCompat.getParcelableExtra(
                    intent ?: return,
                    Intent.EXTRA_CHOSEN_COMPONENT,
                    ComponentName::class.java
                )
                onResult(component?.packageName)
            }
        }
    }

    // API 34 以降は RECEIVER_NOT_EXPORTED フラグが必須
    val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        ContextCompat.RECEIVER_NOT_EXPORTED
    } else {
        0
    }
    ContextCompat.registerReceiver(
        context,
        receiver,
        IntentFilter("${context.packageName}.SHARE_RESULT"),
        flags
    )

    val pendingIntent = PendingIntent.getBroadcast(
        context, 0,
        Intent("${context.packageName}.SHARE_RESULT"),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
    )
    val shareIntent = Intent.createChooser(sendIntent, null, pendingIntent.intentSender)
    context.startActivity(shareIntent)
}
```

---

## 要検証事項

| 項目 | 内容 | 担当 | 期限 |
|---|---|---|---|
| ChooserAction の上限数 | カスタムアクションの最大数がドキュメント未記載 | 実装担当者 | 実装着手前 |
| API 30 での ChooserTargetService 挙動 | 廃止のみで動作するか不明 | 実装担当者 | 実装着手前 |
| FLAG_GRANT_READ_URI_PERMISSION の revoke タイミング | Activity 終了後の正確な失効タイミング | 実装担当者 | 実装着手前 |

---

## ProGuard / R8 設定

`ShortcutInfoCompat` や `FileProvider` を難読化するとクラスが見つからなくなる場合がある。以下のルールを `proguard-rules.pro` に追加すること。

```
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.core.app.ShareCompat$IntentBuilder { *; }
-keep class androidx.core.content.pm.ShortcutInfoCompat { *; }
```

---

## Definition of Done

- [ ] テキスト・URL シェアが Android Sharesheet 経由で動作する（API 26, 29, 33, 34 で確認）
- [ ] 単一・複数画像シェアが動作する（API 26, 29, 33, 34 で確認）
- [ ] FileProvider 経由のファイルシェアが動作する（API 26, 29, 33, 34 で確認）
- [ ] Direct Share ターゲットが Sharesheet に表示される（API 25+）
- [ ] ChooserAction がカスタムボタンとして表示される（API 34+ のみ）
- [ ] シェア結果コールバックが API 22〜33 で EXTRA_CHOSEN_COMPONENT を通じて動作する
- [ ] シェア結果コールバックが API 34+ で ChooserResult を通じて動作する
- [ ] BroadcastReceiver がワンショット解除され、メモリリークが発生しない
- [ ] API バージョン分岐が適切に実装されている
- [ ] FileProvider の Manifest・file_paths.xml 設定が正しく動作する
- [ ] ProGuard / R8 ルールが設定されている
- [ ] サンプルアプリで全サブ機能が確認できる

### テスト確認 API バージョン

| API | 理由 |
|---|---|
| API 26 | 最小サポートバージョン候補、file:// URI 拒否（API 24+）の確認 |
| API 29 | コールバック（IntentSender）追加バージョン |
| API 33 | Predictive Back 追加バージョン |
| API 34 | ChooserResult・ChooserAction・RECEIVER_NOT_EXPORTED 追加バージョン |
