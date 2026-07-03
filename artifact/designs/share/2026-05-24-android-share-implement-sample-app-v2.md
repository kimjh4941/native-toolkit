# 実装計画: Share サンプルアプリ（AndroidLibraryExample）v2

- 対象アプリ: `android/AndroidLibraryExample`
- 参照設計書: `artifact/designs/share/2026-05-24-android-share-implementation-v2.md`
- 参照実装結果: `artifact/results/share/2026-05-24-android-share-implementation-result-v1.md`
- 作成日: 2026-05-24
- 改訂: v1 レビュー指摘反映（artifact/reviews/share/2026-05-24-android-share-sample-app-review.md）

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
| `app/src/main/java/.../MainRouter.kt` | 変更 | `SHARE_TEST` 追加、ShareSampleScreen ルーティング追加、MainMenuScreen 呼び出しに `onSelectShareTest` 追加 |
| `app/src/main/java/.../MainMenuScreen.kt` | 変更 | "Share Example" メニュー項目追加、`onSelectShareTest` 引数追加 |
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

#### 変更点 3: `MainMenuScreen` 呼び出しに `onSelectShareTest` を追加

既存の `MainMenuScreen(...)` 呼び出しに引数を追加する:

```kotlin
MainScreen.MAIN_MENU -> {
    MainMenuScreen(
        modifier = Modifier.padding(innerPadding),
        onSelectDialogTest = { currentScreen = MainScreen.ANDROID_DIALOG_TEST },
        onSelectNotificationTest = { currentScreen = MainScreen.NOTIFICATION_TEST },
        onSelectShareTest = { currentScreen = MainScreen.SHARE_TEST }   // 追加
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

#### 入力バリデーション方針

サンプル画面はすべての操作に固定値を使用する。入力フォームは不要。空文字・不正 MIME 等のエラー系は domain エラー catch によって `statusText` に表示する形で確認する。

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

`ShareUseCases` は `rememberCoroutineScope` と同じスコープで `remember(activity) { ShareUseCases(activity) }` で画面ローカルに生成する。

**coroutine スコープ**: `rememberCoroutineScope()` を使用する。Composable の再コンポーズ時にキャンセルされないよう Activity ライフサイクルに紐付けたい場合は `activity.lifecycleScope` を使用してもよいが、基本は `rememberCoroutineScope` を優先する。

#### UseCase シグネチャ確認

実装結果 v1 の `ShareTextUseCase.invoke` は以下のシグネチャを持つ:

```kotlin
operator fun invoke(content: ShareContent, chooserActionsJson: String = "[]")
```

`ShareUseCases.shareText` は同シグネチャを委譲するため、サンプル呼び出しは以下を使用する:

```kotlin
shareUseCases.shareText(ShareContent(text = "Hello from native-toolkit"), chooserActionsJson = "[]")
```

#### セクション構成とボタン

**セクション 1: テキスト共有**

| ボタンラベル | 呼び出し |
|---|---|
| Share Text | `shareUseCases.shareText(ShareContent(text = "Hello from native-toolkit"), chooserActionsJson = "[]")` |
| Share URL | `shareUseCases.shareText(ShareContent(text = "https://example.com", mimeType = "text/plain"), chooserActionsJson = "[]")` |

> Share URL ボタンは Sharesheet がリンクプレビューを表示するかを手動確認するために追加する。

**セクション 2: 画像共有**

ファイル生成（IO）→ shareImage 呼び出し（Main）のスレッド境界を以下の擬似コードで実装する:

```kotlin
scope.launch(Dispatchers.IO) {
    val bmp = BitmapFactory.decodeResource(context.resources, android.R.drawable.ic_menu_share)
    val file = File(context.cacheDir, "share_sample.png")
    file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
    withContext(Dispatchers.Main) {
        try {
            shareUseCases.shareImage(file.absolutePath, "image/png")
            statusText = "✅ shareImage called"
        } catch (e: ShareDomainError) {
            statusText = "❌ ${e.message}"
        } catch (e: Exception) {
            statusText = "❌ Unexpected: ${e.message}"
        }
    }
}
```

| ボタンラベル | 呼び出し |
|---|---|
| Share Image | 上記擬似コードに準じて実行 |

**セクション 3: 複数画像共有**

2 枚の PNG を `cacheDir` に生成（`share_sample_1.png`, `share_sample_2.png`）。スレッドパターンはセクション 2 と同様:

```kotlin
scope.launch(Dispatchers.IO) {
    // file1, file2 を生成
    withContext(Dispatchers.Main) {
        shareUseCases.shareImages(listOf(file1.absolutePath, file2.absolutePath))
        statusText = "✅ shareImages called"
    }
}
```

| ボタンラベル | 呼び出し |
|---|---|
| Share Multiple Images | 上記擬似コードに準じて実行 |

**セクション 4: ファイル共有**

```kotlin
scope.launch(Dispatchers.IO) {
    val file = File(context.cacheDir, "share_sample.txt").apply { writeText("Share sample") }
    withContext(Dispatchers.Main) {
        shareUseCases.shareFile(file.absolutePath)
        statusText = "✅ shareFile called"
    }
}
```

| ボタンラベル | 呼び出し |
|---|---|
| Share File | 上記擬似コードに準じて実行 |

**セクション 5: 複数ファイル共有**

2 ファイルを `cacheDir` に生成（`share_sample_1.txt`, `share_sample_2.txt`）。スレッドパターンはセクション 4 と同様。

| ボタンラベル | 呼び出し |
|---|---|
| Share Multiple Files | `shareUseCases.shareFiles(listOf(file1.absolutePath, file2.absolutePath))` |

**セクション 6: Direct Share Target**

アイコンバイトは IO スレッドで launcher アイコン drawable を PNG エンコードして取得する:

```kotlin
scope.launch(Dispatchers.IO) {
    val bmp = BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher)
    val baos = java.io.ByteArrayOutputStream()
    bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
    val iconBytes = baos.toByteArray()
    withContext(Dispatchers.Main) {
        shareUseCases.registerDirectShareTarget(
            DirectShareTarget(id = "sample_1", label = "Sample User"),
            iconBytes
        )
        statusText = "✅ registerDirectShareTarget called"
    }
}
```

`shareUseCases.registerDirectShareTarget` のシグネチャ: `RegisterDirectShareTargetUseCase.invoke(target: DirectShareTarget, iconBytes: ByteArray)`

| ボタンラベル | 呼び出し |
|---|---|
| Register Direct Share Target | 上記擬似コードに準じて実行 |
| Remove Direct Share Target | `shareUseCases.removeDirectShareTargets(listOf("sample_1"))` |

**セクション 7: Share with Callback**

`shareWithCallback` の `onResult` コールバックは BroadcastReceiver の `onReceive` から呼ばれる。コールバック内では `activity.runOnUiThread { }` でメインスレッドへの切り替えをガードする:

```kotlin
shareUseCases.shareWithCallback(ShareContent(text = "Hello with callback")) { pkg ->
    activity.runOnUiThread {
        statusText = if (pkg != null) "✅ Selected: $pkg" else "ℹ️ Cancelled"
    }
}
```

| ボタンラベル | 呼び出し |
|---|---|
| Share with Callback | 上記擬似コードに準じて実行 |

#### エラーハンドリング

全ボタンの onClick は `try-catch` で `ShareDomainError` を捕捉し `statusText` に表示する。`ShareDomainError` 以外の `Exception` も同様に捕捉する:

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

ファイル生成を伴うセクション（2〜6）は `withContext(Dispatchers.Main)` ブロック内で上記を実行する。

---

## 完了条件

- [ ] 全ボタンが `ShareSampleScreen` に配置されている（テキスト2・画像1・複数画像1・ファイル1・複数ファイル1・Direct Share 2・With Callback 1 = 計 9 ボタン）
- [ ] "Share Example" がメインメニューに表示され、タップで `ShareSampleScreen` に遷移する
- [ ] Back ボタンでメインメニューに戻る
- [ ] FileProvider 設定（`AndroidManifest.xml` + `file_paths.xml`）が正しく追加されている
- [ ] `proguard-rules.pro` に keep ルールが追加されている
- [ ] 実機で "Share Text" を実行するとシェアシートが表示される
- [ ] 実機で "Share URL" を実行するとシェアシートにリンクプレビューが表示される
- [ ] 実機で "Share File" を実行するとシェアシートが表示される
- [ ] 実機で "Share Multiple Images" を実行するとシェアシートが表示される
- [ ] 実機で "Share Multiple Files" を実行するとシェアシートが表示される
- [ ] 実機で "Register Direct Share Target" を実行後、シェアシートにショートカットが表示される（API 25+）
- [ ] 実機で "Remove Direct Share Target" を実行後、シェアシートからショートカットが消える
- [ ] 実機で "Share with Callback" を実行してアプリ選択後、選択パッケージ名が statusText に表示される
- [ ] 実機で "Share with Callback" 実行後 Sharesheet を外タップでキャンセルすると `"ℹ️ Cancelled"` が表示される
- [ ] 再度 "Share with Callback" を実行しても古い receiver が誤発火しない（ワンショット解除確認）
- [ ] 全メソッドに Log.d がある（android.md ルール遵守）
- [ ] public composable に KDoc がある（android.md ルール遵守）

---

## 注意事項

- `cacheDir` に生成するファイルは `FileProvider` の `<cache-path>` でカバーされるため `IllegalArgumentException` は発生しない
- `FileProvider` の meta-data 名は AndroidX 移行後も `android.support.FILE_PROVIDER_PATHS` のまま変更しない（AndroidX 内部で同名定数が維持されている）
- `shareWithCallback` の `onResult` コールバックは Sharesheet が閉じるまで呼ばれない（UI ブロックしない）
- `registerDirectShareTarget` は API 25 以上で動作する（`ShortcutManagerCompat` 経由）
- Direct Share Target のアイコンは `R.mipmap.ic_launcher` で代用する（実際のアプリでは連絡先アイコン等を使用）
- ChooserAction（API 34+ カスタムアクション）はこのサンプル画面では固定の空配列を渡すため確認できない。ChooserAction の動作確認は Unity Bridge 経由で別途実施すること
