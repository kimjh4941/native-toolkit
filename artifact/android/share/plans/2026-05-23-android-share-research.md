# Android シェア機能 調査結果

- 作成日: 2026-05-23
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
├── URLシェア
├── 画像シェア
│   ├── 単一画像
│   └── 複数画像
├── ファイルシェア
│   ├── 単一ファイル（FileProvider）
│   └── 複数ファイル
├── Direct Share（ショートカット）
│   ├── ショートカット登録
│   └── ショートカット削除
└── シェア結果コールバック（Android 10+）
```

---

## API 全網羅表

### テキスト・URLシェア

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `Intent.ACTION_SEND` | テキスト・URLをシェア | `EXTRA_TEXT: String`, `type: "text/plain"` | なし（Activity 起動） | 受信アプリなし | API 1 |
| `Intent.createChooser()` | システム選択 UI を表示 | `intent`, `title` | Intent | なし | API 5 |
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
| `FileProvider.getUriForFile()` | content:// URI 生成 | `context`, `authority: String`, `file: File` | Uri | ファイル未存在、パス未定義 | AndroidX Core |

### Direct Share

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ShortcutManagerCompat.setDynamicShortcuts()` | Direct Share ターゲット登録 | `context`, `List<ShortcutInfoCompat>` | void | ID 未設定、必須フィールド欠如 | API 25 / AndroidX |
| `ShortcutManagerCompat.pushDynamicShortcut()` | 単一ショートカット追加・更新 | `context`, `ShortcutInfoCompat` | void | 同上 | API 25 / AndroidX |
| `ShortcutManagerCompat.removeLongLivedShortcuts()` | ショートカット削除 | `context`, `List<String>` shortcutIds | void | 存在しない ID | API 25 / AndroidX |

### シェア結果コールバック

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `Intent.createChooser(intent, title, sender)` | コールバック付き Chooser | `IntentSender` | Intent | 無効な PendingIntent | API 29 |
| `ChooserResult.selectedComponent` | 選択されたアプリ取得 | なし | ComponentName | ユーザーキャンセル時 null | API 34 |

---

## 実装リスク

| リスク | 詳細 | 対策 |
|---|---|---|
| ファイル URI エラー | file:// URI は API 24 以降の他アプリから拒否される | FileProvider で content:// URI に変換 |
| 権限エラー | EXTRA_STREAM URI に読み取り権限がない | `FLAG_GRANT_READ_URI_PERMISSION` を必ず付与 |
| MIME 型の不一致 | MIME 型を誤ると受信アプリが表示されない | 適切な MIME 型を設定、`*/*` は非推奨 |
| Direct Share 廃止 API | `ChooserTargetService` は廃止済み | `ShortcutManagerCompat` を使用 |
| コールバック API バージョン | `ChooserResult` は API 34 以降 | API バージョン分岐で対応 |

---

## サンプルコード集

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

### 単一画像シェア

```kotlin
fun shareImage(context: Context, imageUri: Uri) {
    val shareIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_STREAM, imageUri)
        type = "image/jpeg"
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

### Direct Share ターゲット登録

```kotlin
fun registerDirectShareTarget(
    context: Context,
    id: String,
    label: String,
    icon: Bitmap,
    category: String,
    intent: Intent
) {
    val shortcut = ShortcutInfoCompat.Builder(context, id)
        .setShortLabel(label)
        .setLongLabel(label)
        .setIcon(IconCompat.createWithAdaptiveBitmap(icon))
        .setIntent(intent)
        .setCategories(setOf(category))
        .setLongLived(true)
        .build()
    ShortcutManagerCompat.pushDynamicShortcut(context, shortcut)
}
```

### シェア結果コールバック（API 29+）

```kotlin
fun shareWithCallback(context: Context, text: String, onResult: (String?) -> Unit) {
    val sendIntent = Intent().apply {
        action = Intent.ACTION_SEND
        putExtra(Intent.EXTRA_TEXT, text)
        type = "text/plain"
    }

    val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            val result = IntentCompat.getParcelableExtra(
                intent ?: return,
                Intent.EXTRA_CHOOSER_RESULT,
                ChooserResult::class.java
            )
            onResult(result?.selectedComponent?.packageName)
        }
    }
    context.registerReceiver(receiver, IntentFilter("${context.packageName}.SHARE_RESULT"))

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

| 項目 | 内容 |
|---|---|
| ChooserAction の上限数 | カスタムアクションの最大数がドキュメント未記載 |
| API 30 での ChooserTargetService 挙動 | 廃止のみで動作するか不明 |
| FLAG_GRANT_READ_URI_PERMISSION の revoke タイミング | Activity 終了後の正確な失効タイミング |

---

## Definition of Done

- [ ] テキスト・URL シェアが Android Sharesheet 経由で動作する
- [ ] 単一・複数画像シェアが動作する
- [ ] FileProvider 経由のファイルシェアが動作する
- [ ] Direct Share ターゲットが Sharesheet に表示される
- [ ] シェア結果コールバックが API 29+ で動作する
- [ ] API バージョン分岐が適切に実装されている
- [ ] サンプルアプリで全サブ機能が確認できる
