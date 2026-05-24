# 実装計画: Share サンプルアプリ（AndroidLibraryExample）

- 対象アプリ: `android/AndroidLibraryExample`
- 参照設計書: `artifact/designs/share/2026-05-24-android-share-implementation-v2.md`
- 参照実装結果: `artifact/results/share/2026-05-24-android-share-implementation-result-v1.md`
- 作成日: 2026-05-24

---

## 概要

AndroidLibraryExample に Share サンプル画面を追加する。
既存の Notification サンプル画面（`NotificationSampleScreen.kt`）と同じ UI パターンを踏襲し、
全 8 種類のシェア操作を手動確認できる画面を実装する。

---

## 作成・変更ファイル一覧

| ファイル | 種別 | 内容 |
|---|---|---|
| `app/src/main/java/.../ShareSampleScreen.kt` | 新規 | Share サンプル画面 Composable |
| `app/src/main/java/.../MainRouter.kt` | 変更 | `SHARE_TEST` 追加、ShareSampleScreen ルーティング追加 |
| `app/src/main/java/.../MainMenuScreen.kt` | 変更 | "Share Example" メニュー項目追加 |
| `app/src/main/AndroidManifest.xml` | 変更 | FileProvider 追加 |
| `app/src/main/res/xml/file_paths.xml` | 新規 | FileProvider パス定義 |
| `app/proguard-rules.pro` | 変更 | FileProvider・ShareCompat keep ルール追加 |

---

## 詳細実装

### 1. `file_paths.xml`（新規）

パス: `app/src/main/res/xml/file_paths.xml`

```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <files-path name="files" path="." />
    <cache-path name="cache" path="." />
    <external-files-path name="external_files" path="." />
</paths>
```

---

### 2. `AndroidManifest.xml`（変更）

`</application>` タグ閉じる直前に以下を追加する:

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

---

### 3. `proguard-rules.pro`（変更）

ファイル末尾に追加する:

```
-keep class androidx.core.content.FileProvider { *; }
-keep class androidx.core.app.ShareCompat$IntentBuilder { *; }
-keep class androidx.core.content.pm.ShortcutInfoCompat { *; }
-keep class androidx.core.graphics.drawable.IconCompat { *; }
```

---

### 4. `MainRouter.kt`（変更）

#### 変更点 1: `MainScreen` enum に `SHARE_TEST` を追加

```kotlin
private enum class MainScreen {
    MAIN_MENU,
    ANDROID_DIALOG_TEST,
    NOTIFICATION_TEST,
    SHARE_TEST
}
```

#### 変更点 2: `AppRouter` composable に `ShareSampleScreen` のルーティングを追加

`when (currentScreen)` ブロックに追記:

```kotlin
MainScreen.SHARE_TEST -> {
    ShareSampleScreen(
        modifier = Modifier.padding(innerPadding),
        activity = activity,
        onBack = { currentScreen = MainScreen.MAIN_MENU }
    )
}
```

`AppRouter` のシグネチャは変更しない。`activity: AppCompatActivity` は Context として `ShareSampleScreen` に渡す。

---

### 5. `MainMenuScreen.kt`（変更）

既存の "Notification Example" ボタンの下に以下を追加する。

シグネチャ変更:
```kotlin
fun MainMenuScreen(
    modifier: Modifier = Modifier,
    onSelectDialogTest: () -> Unit,
    onSelectNotificationTest: () -> Unit,
    onSelectShareTest: () -> Unit      // 追加
)
```

LazyColumn 内に `MainMenuListItem` を1件追加:
```kotlin
MainMenuListItem(title = "Share Example", onClick = onSelectShareTest)
```

---

### 6. `ShareSampleScreen.kt`（新規）

パス: `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ShareSampleScreen.kt`

#### 構成概要

`NotificationSampleScreen.kt` の UI パターンを踏襲する:
- `statusText by remember { mutableStateOf("待機中") }` で操作結果を1行表示
- `LazyColumn` + `AlwaysVisibleLazyColumnScrollbar` でスクロール
- Back ボタン（左上）+ タイトル "Share"（28sp, Bold）
- セクションヘッダ: `Text(fontSize = 20.sp, fontWeight = FontWeight.SemiBold)`
- 各ボタン: `Button(modifier = Modifier.fillMaxWidth())`
- 成功: `"✅ ..."`, エラー: `"❌ ..."`, 情報: `"ℹ️ ..."`

#### コーディングルール適用

- `ShareSampleScreen` 関数先頭に `Log.d(TAG, "[ShareSampleScreen] activity: $activity")`
- TAG: `companion object { private const val TAG = "ShareSampleScreen" }`
- `import android.util.Log`
- public composable に KDoc（概要1行 + @param）

#### 依存 import

```kotlin
import android.library.share.data.repository.ShareUseCases
import android.library.share.domain.model.ShareContent
import android.library.share.domain.model.DirectShareTarget
import android.library.share.domain.error.ShareDomainError
```

`ShareUseCases` は `remember(activity) { ShareUseCases(activity) }` で画面ローカルに生成する。

#### セクション構成とボタン

**セクション 1: テキスト共有**

| ボタンラベル | 呼び出し |
|---|---|
| Share Text | `shareUseCases.shareText(ShareContent(text = "Hello from native-toolkit"), "[]")` |

**セクション 2: 画像共有**

操作前に `context.cacheDir` に PNG ファイルを生成する:
```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_share)
val file = File(context.cacheDir, "share_sample.png")
file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
```

| ボタンラベル | 呼び出し |
|---|---|
| Share Image | `shareUseCases.shareImage(file.absolutePath, "image/png")` |

**セクション 3: 複数画像共有**

2 枚の PNG を `cacheDir` に生成（`share_sample_1.png`, `share_sample_2.png`）。

| ボタンラベル | 呼び出し |
|---|---|
| Share Multiple Images | `shareUseCases.shareImages(listOf(file1.absolutePath, file2.absolutePath))` |

**セクション 4: ファイル共有**

テキストファイルを `cacheDir` に生成:
```kotlin
val file = File(context.cacheDir, "share_sample.txt").apply { writeText("Share sample") }
```

| ボタンラベル | 呼び出し |
|---|---|
| Share File | `shareUseCases.shareFile(file.absolutePath)` |

**セクション 5: 複数ファイル共有**

2 ファイルを `cacheDir` に生成。

| ボタンラベル | 呼び出し |
|---|---|
| Share Multiple Files | `shareUseCases.shareFiles(listOf(file1.absolutePath, file2.absolutePath))` |

**セクション 6: Direct Share Target**

アイコンバイトは launcher アイコン drawable を PNG エンコードして取得する:
```kotlin
val bmp = BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
val baos = java.io.ByteArrayOutputStream()
bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
val iconBytes = baos.toByteArray()
```

| ボタンラベル | 呼び出し |
|---|---|
| Register Direct Share Target | `shareUseCases.registerDirectShareTarget(DirectShareTarget(id = "sample_1", label = "Sample User"), iconBytes)` |
| Remove Direct Share Target | `shareUseCases.removeDirectShareTargets(listOf("sample_1"))` |

**セクション 7: Share with Callback**

`shareWithCallback` は `onResult` コールバックで `statusText` を更新する。
`onResult` は UI スレッドから呼ばれる想定だが、`withContext(Dispatchers.Main)` でガードする。

| ボタンラベル | 呼び出し |
|---|---|
| Share with Callback | `shareUseCases.shareWithCallback(ShareContent(text = "Hello with callback")) { pkg -> statusText = if (pkg != null) "✅ Selected: $pkg" else "ℹ️ Cancelled" }` |

#### エラーハンドリング

全ボタンの onClick は `try-catch` で `ShareDomainError` を捕捉し `statusText` に `"❌ ${e.message}"` を表示する。
`ShareDomainError` 以外の `Exception` も同様に捕捉して `"❌ Unexpected: ${e.message}"` を表示する。

```kotlin
try {
    shareUseCases.shareText(...)
    statusText = "✅ shareText called"
} catch (e: ShareDomainError) {
    statusText = "❌ ${e.message}"
} catch (e: Exception) {
    statusText = "❌ Unexpected: ${e.message}"
}
```

#### coroutineScope

ボタン onClick はメインスレッドで実行される。ファイル生成・圧縮処理は `LaunchedEffect` ではなく
onClick 内で `lifecycleScope.launch(Dispatchers.IO)` で実行し、完了後に `Dispatchers.Main` で `statusText` を更新する。

`activity` の `lifecycleScope` を使用: `import androidx.lifecycle.lifecycleScope`

---

## 完了条件

- [ ] 全 8 種類のシェア操作ボタンが `ShareSampleScreen` に配置されている
- [ ] "Share Example" がメインメニューに表示され、タップで `ShareSampleScreen` に遷移する
- [ ] Back ボタンでメインメニューに戻る
- [ ] FileProvider 設定（`AndroidManifest.xml` + `file_paths.xml`）が正しく追加されている
- [ ] `proguard-rules.pro` に keep ルールが追加されている
- [ ] 実機で "Share Text" を実行するとシェアシートが表示される
- [ ] 実機で "Share File" を実行するとシェアシートが表示される
- [ ] 実機で "Share with Callback" を実行してアプリ選択後、選択パッケージ名が statusText に表示される
- [ ] 全メソッドに Log.d がある（android.md ルール遵守）
- [ ] public composable に KDoc がある（android.md ルール遵守）

---

## 注意事項

- `cacheDir` に生成するファイルは `FileProvider` の `<cache-path>` でカバーされるため `IllegalArgumentException` は発生しない
- `shareWithCallback` の `onResult` コールバックは Sharesheet が閉じるまで呼ばれない（UI ブロックしない）
- `registerDirectShareTarget` は API 25 以上で動作する（`ShortcutManagerCompat` 経由）
- Direct Share Target のアイコンは `R.mipmap.ic_launcher` で代用する（実際のアプリでは連絡先アイコン等を使用）
