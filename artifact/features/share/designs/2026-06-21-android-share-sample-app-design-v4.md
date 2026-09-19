# 実装計画: Share サンプルアプリ（AndroidLibraryExample）v4

- 対象アプリ: `android/AndroidLibraryExample`
- 参照設計書: `artifact/designs/share/2026-06-20-android-share-design-v3.md`
- 前版: `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md`
- 作成日: 2026-06-21
- 改訂: v4（**ライブラリ機能のうちサンプル未デモ分の補完** / 設計レビュー反映済み）
- レビュー: `artifact/reviews/share/2026-06-21-android-share-sample-app-design-review.md`（高優先度2件・中2件・低1件を反映）

---

## 概要

v3 までで送信 9 機能 + 受信デモが整備された。ライブラリ（`android_library`）が提供する
公開 API とサンプルのボタンを突き合わせた結果、以下 5 項目がサンプルで未デモであることが判明した。
v4 ではこれらを `ShareSampleScreen` に追加し、ライブラリの公開 API を全網羅する。

| # | 未デモ項目 | ライブラリ該当箇所 | 種別 |
|---|---|---|---|
| 1 | Custom Chooser Actions（API 34+） | `ShareRepositoryImpl.addChooserActionsIfSupported` / `buildChooserActions` | 主要機能・完全未デモ |
| 2 | shareWithCallback + リッチプレビュー | `ShareWithCallbackUseCase.invoke(content, preview, onResult, onFinished)` | 主要機能・未デモ |
| 3 | `ShareContent.subject` 指定の共有 | `ShareContent.subject` | 補助・未デモ |
| 4 | `ShareContent.title`（chooser title）指定の共有 | `ShareContent.title` → `Intent.createChooser(intent, title)` | 補助・未デモ |
| 5 | cancelPendingCallback の明示呼び出し | `CancelPendingShareCallbackUseCase` | 補助・UI 操作からの呼び出しが無い |

> ライブラリ（`android_library` / `unity_android_plugin`）は変更しない。v4 は
> **サンプルアプリでの利用例の補完**のみを対象とする。
> #3 と #4 は 1 つのボタンに統合してデモする（同一 `ShareContent` で両フィールドを指定）。

---

## v4 追加・変更サマリー

| 項目 | 種別 | 対象ファイル |
|---|---|---|
| カスタムチューザーアクション送信ボタン（#1） | 変更 | `ShareSampleScreen.kt` |
| カスタムアクション受信用 BroadcastReceiver | 新規 | `ShareChooserActionReceiver.kt` |
| カスタムアクション受信 receiver 宣言 | 変更 | `AndroidManifest.xml` |
| コールバック + リッチプレビュー送信ボタン（#2） | 変更 | `ShareSampleScreen.kt` |
| subject + title 付き共有ボタン（#3 + #4） | 変更 | `ShareSampleScreen.kt` |
| pending callback 明示キャンセルボタン（#5） | 変更 | `ShareSampleScreen.kt` |

---

## 入力バリデーション方針（全体）

- 本 v4 ではユーザー入力項目（TextField 等）は追加しない。すべて固定サンプル値を使用する。
- そのため画面側での入力バリデーションは行わない。`ShareContent.text` 等のドメイン入力検証は
  既存 use case（`ShareTextUseCase` / `ShareWithCallbackUseCase`）に委譲する。
- 既存サンプルの実装パターンに合わせ、各操作は `try { ... } catch (e: ShareDomainError) { ... }
  catch (e: Exception) { ... }` で結果を `statusText` に反映する。
- 画像/ファイル準備を伴う操作は IO coroutine 全体を `try/catch` で包み、
  `BitmapFactory.decodeResource()` の null は `?: run { ...; return@launch }` で中断し、
  失敗時は Main dispatcher 上で `statusText` に `File preparation failed` を表示する
  （既存 "Share Text with Rich Preview" と同一パターン）。

---

## 詳細設計

### 1. Custom Chooser Actions（API 34+）

#### 1-1. ライブラリ仕様の確認

`ShareRepositoryImpl.shareText(content, chooserActionsJson, preview)` は、`chooserActionsJson` が
空（`""` / `"[]"`）でなく、かつ API 34（`UPSIDE_DOWN_CAKE`）以上の場合のみ、
`EXTRA_CHOOSER_CUSTOM_ACTIONS` を付与する。JSON 形式は次の配列:

```json
[
  { "label": "...", "iconBase64": "...", "intentAction": "..." }
]
```

各要素から `ChooserAction` を生成する際、ライブラリは次の `PendingIntent` を組む:

```kotlin
PendingIntent.getBroadcast(
    context,
    label.hashCode(),
    Intent(intentAction).setPackage(context.packageName),
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
)
```

→ ユーザーがカスタムアクションをタップすると、`intentAction` を action に持つ
**アプリ内 broadcast** が飛ぶ。サンプル側でこれを受ける `BroadcastReceiver` を用意することで、
タップ → 実際の挙動までを end-to-end でデモできる。

- `label` / `iconBase64` のいずれかが空の要素はライブラリ側でスキップされる
- `intentAction` 省略時は `Intent.ACTION_SEND` が使われる（本サンプルでは明示指定する）
- API 34 未満では `chooserActionsJson` を渡しても無視される（通常共有として動作）

#### 1-2. カスタムアクション受信 receiver（`ShareChooserActionReceiver.kt`、新規）

パス: `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ShareChooserActionReceiver.kt`

アプリ独自の action を受け取り、Toast とログでタップを可視化する最小実装。
`NotificationActionReceiver` 等、既存 receiver と同じ書式・Log.d 規約に合わせる。

```kotlin
/**
 * Receives taps on the custom chooser action added to the Sharesheet.
 *
 * The action string must match the intentAction passed in chooserActionsJson.
 */
class ShareChooserActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "[onReceive] context: $context, intent: $intent, action: ${intent?.action}")
        if (context != null) {
            Toast.makeText(context, "Custom chooser action tapped", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        private const val TAG = "ShareChooserActionReceiver"
        const val ACTION_CUSTOM_CHOOSER =
            "com.jonghyunkim.android.nativetoolkit.example.CUSTOM_CHOOSER_ACTION"
    }
}
```

> アクション文字列はハードコードせず `ShareChooserActionReceiver.ACTION_CUSTOM_CHOOSER` を
> 送信側（`ShareSampleScreen`）からも参照し、一致を保証する。

#### 1-3. receiver 宣言（`AndroidManifest.xml`、変更）

既存の `NotificationActionReceiver` と並べて宣言する。`exported="false"`（アプリ内 broadcast のみ）。

```xml
<receiver
    android:name=".ShareChooserActionReceiver"
    android:exported="false" />
```

#### 1-4. 送信ボタン（`ShareSampleScreen.kt`、変更）

「Text Share」セクションに **"Share Text with Custom Action"** を追加する。
アイコン PNG を Base64 エンコードして `chooserActionsJson` を組み立てる。
**既存 rich preview と同じエラー処理パターン**（null 分岐 + IO 全体 try/catch + Main の失敗表示）を採用する。

```kotlin
Button(
    onClick = {
        Log.d(SHARE_TAG, "[onClick] Share Text with Custom Action")
        statusText = "ℹ️ Preparing custom action icon..."
        scope.launch(Dispatchers.IO) {
            try {
                val bmp = BitmapFactory.decodeResource(
                    context.resources,
                    android.R.drawable.ic_menu_edit
                ) ?: run {
                    withContext(Dispatchers.Main) { statusText = "❌ Bitmap decode failed" }
                    return@launch
                }
                val iconBase64 = ByteArrayOutputStream().use { baos ->
                    bmp.compress(Bitmap.CompressFormat.PNG, 100, baos)
                    Base64.encodeToString(baos.toByteArray(), Base64.NO_WRAP)
                }
                val chooserActionsJson = JSONArray().put(
                    JSONObject().apply {
                        put("label", "Custom")
                        put("iconBase64", iconBase64)
                        put("intentAction", ShareChooserActionReceiver.ACTION_CUSTOM_CHOOSER)
                    }
                ).toString()
                Log.d(SHARE_TAG, "[onClick] chooserActionsJson length: ${chooserActionsJson.length}")
                withContext(Dispatchers.Main) {
                    try {
                        shareUseCases.shareText(
                            ShareContent(
                                text = "Shared with a custom chooser action",
                                mimeType = "text/plain"
                            ),
                            chooserActionsJson = chooserActionsJson
                        )
                        statusText = "✅ shareText (custom action) called"
                    } catch (e: ShareDomainError) {
                        statusText = "❌ ${e.message}"
                    } catch (e: Exception) {
                        statusText = "❌ Unexpected: ${e.message}"
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    statusText = "❌ File preparation failed: ${e.message}"
                }
            }
        }
    },
    modifier = Modifier.fillMaxWidth()
) {
    Text(text = "Share Text with Custom Action")
}
```

- `Base64.NO_WRAP` を使う（改行混入による JSON 破損を避ける）
- `ByteArrayOutputStream` は `use` で閉じる
- API 34 未満では通常共有として開く（ライブラリ仕様、サンプルでは特別な分岐をしない）

---

### 2. shareWithCallback + リッチプレビュー

「Share with Callback」セクションに **"Share with Callback + Rich Preview"** を追加する。
`ShareWithCallbackUseCase` の preview/onFinished 付きオーバーロードをデモする。
画像準備は rich preview と同じエラー処理パターンを使う。

```kotlin
Button(
    onClick = {
        Log.d(SHARE_TAG, "[onClick] Share with Callback + Rich Preview")
        statusText = "ℹ️ Preparing callback preview thumbnail..."
        scope.launch(Dispatchers.IO) {
            try {
                val bmp = BitmapFactory.decodeResource(
                    context.resources,
                    android.R.mipmap.sym_def_app_icon
                ) ?: run {
                    withContext(Dispatchers.Main) { statusText = "❌ Bitmap decode failed" }
                    return@launch
                }
                val file = File(context.cacheDir, "callback_preview.png")
                file.outputStream().use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                withContext(Dispatchers.Main) {
                    try {
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
                                Log.d(SHARE_TAG, "[onResult] pkg: $pkg")
                                statusText = if (pkg != null) {
                                    "✅ Selected: $pkg"
                                } else {
                                    "ℹ️ Shared (package unavailable)"
                                }
                            },
                            onFinished = { Log.d(SHARE_TAG, "[onFinished] callback + preview") }
                        )
                        statusText = "ℹ️ Sharesheet (callback + preview) opened..."
                    } catch (e: ShareDomainError) {
                        statusText = "❌ ${e.message}"
                    } catch (e: Exception) {
                        statusText = "❌ Unexpected: ${e.message}"
                    }
                }
            } catch (e: Exception) {
                withContext(Dispatchers.Main) {
                    statusText = "❌ File preparation failed: ${e.message}"
                }
            }
        }
    },
    modifier = Modifier.fillMaxWidth()
) {
    Text(text = "Share with Callback + Rich Preview")
}
```

- `onResult` は選択時のみ発火（v3 の文言方針を踏襲：null は「選択されたがパッケージ不明」）
- `onFinished` はチューザーのコールバック処理完了後に呼ばれる。ログ出力でデモ
- サムネイルは `cacheDir` 配下のファイルパスで渡す（既存 FileProvider `<cache-path>` でカバー）

---

### 3 + 4. subject + title 指定の共有

「Text Share」セクションに **"Share with Subject & Title"** を 1 ボタン追加し、
`ShareContent.subject`（メール件名）と `ShareContent.title`（chooser title）を同時に指定する。

```kotlin
Button(
    onClick = {
        Log.d(SHARE_TAG, "[onClick] Share with Subject & Title")
        try {
            shareUseCases.shareText(
                ShareContent(
                    text = "Body text shared from native-toolkit",
                    title = "Choose an app",          // -> Intent.createChooser(intent, title)
                    subject = "Sample subject line",  // -> Intent.EXTRA_SUBJECT
                    mimeType = "text/plain"
                ),
                chooserActionsJson = "[]"
            )
            statusText = "✅ shareText (subject & title) called"
        } catch (e: ShareDomainError) {
            statusText = "❌ ${e.message}"
        } catch (e: Exception) {
            statusText = "❌ Unexpected: ${e.message}"
        }
    },
    modifier = Modifier.fillMaxWidth()
) {
    Text(text = "Share with Subject & Title")
}
```

- `subject` は `Intent.EXTRA_SUBJECT` として付与され、メール系アプリ（Gmail 等）の件名欄に反映される
- `title` は `Intent.createChooser(intent, title)` の title 引数に渡される

> **重要（title の視覚確認について）:** `Intent.createChooser` の title は、
> Android 10（API 29）以降の標準 Sharesheet では**表示されない**。
> 本プロジェクトは **minSdk 31（Android 12）** であり、title が表示され得る API 28 以下の旧 chooser は
> 対象端末に一切存在しない。よって **対象 OS の全端末で title は視覚表示されない**（環境依存ではなく確定）。
> v4 における #4 の主目的は「`ShareContent.title` が API として正しく渡されること」をコードで示すことであり、
> 完了条件では「title を指定して共有が成功する（例外なく Sharesheet が開く）」ことを必須とし、
> Sharesheet 上での視覚表示は対象 OS では確認できないため完了条件に含めない。

---

### 5. cancelPendingCallback の明示呼び出し

「Share with Callback」セクションに **"Cancel Pending Callback"** を追加する。
画面破棄（`DisposableEffect`）以外に、ユーザー操作で明示的にキャンセルする例。

```kotlin
Button(
    onClick = {
        Log.d(SHARE_TAG, "[onClick] Cancel Pending Callback")
        try {
            shareUseCases.cancelPendingCallback()
            statusText = "✅ cancelPendingCallback called"
        } catch (e: Exception) {
            statusText = "❌ Unexpected: ${e.message}"
        }
    },
    modifier = Modifier.fillMaxWidth()
) {
    Text(text = "Cancel Pending Callback")
}
```

#### 検証方法（レビュー指摘①を反映）

`cancelPendingCallback()` は `ShareCallbackCoordinator.cancel()` 経由で pending receiver を
**unregister** する。そのためキャンセル後の broadcast は receiver に到達せず、
`onReceive` 自体が呼ばれない。よって `[onReceive] stale or cancelled registration; ignoring` は
**出力されない**（このログは register を連続呼び出しした際の「古い receiver」用であり、明示キャンセルの
証跡にはならない）。

明示キャンセルの検証は、キャンセル経路の各層のログで行う:

| 層 | 期待ログ（tag: message） |
|---|---|
| use case | `CancelPendingShareCallbackUseCase: [invoke]` |
| repository | `ShareRepositoryImpl: [cancelPendingCallback]` |
| coordinator | `ShareCallbackCoordinator: [cancel]` |
| receiver registry | `AndroidShareCallbackReceiverRegistry: [unregister] receiver: ...` |

これらが順に出れば、pending receiver が解除されたことを確認できる。
（補強として、coordinator の既存単体テスト `ShareCallbackCoordinatorTest.cancel_thenQueuedBroadcast_doesNotInvokeCallback` が
「キャンセル後の broadcast でコールバックが呼ばれないこと」を保証している。）

---

## 作成・変更ファイル一覧（v4）

| ファイル | 種別 | 内容 |
|---|---|---|
| `app/src/main/java/.../ShareChooserActionReceiver.kt` | 新規 | カスタムチューザーアクション受信 receiver |
| `app/src/main/AndroidManifest.xml` | 変更 | `ShareChooserActionReceiver` を `exported="false"` で宣言 |
| `app/src/main/java/.../ShareSampleScreen.kt` | 変更 | 4 ボタン追加（custom action / callback+preview / subject&title / cancel pending callback） |

> KDoc / コメントは英語で記述する（共通規約）。新規 receiver・全 onClick の主要処理に `Log.d` を入れる。
> ファイルレベル定数 `TAG` は既存と衝突しないよう一意名にする（`ShareSampleScreen` は既存の `SHARE_TAG` を継続使用）。

---

## 完了条件

### #1 Custom Chooser Actions
- [ ] "Share Text with Custom Action" ボタンが配置され、API 34+ で Sharesheet 内にカスタムアクションが表示される
- [ ] カスタムアクションをタップすると `ShareChooserActionReceiver` が発火し Toast が表示される
- [ ] `ShareChooserActionReceiver` が `AndroidManifest.xml` に `exported="false"` で宣言されている
- [ ] 送信側と受信側で同一のアクション文字列（`ACTION_CUSTOM_CHOOSER`）を参照している
- [ ] アイコンは `Base64.NO_WRAP` でエンコードしている

### #2 callback + rich preview
- [ ] "Share with Callback + Rich Preview" ボタンが配置され、Sharesheet 上部にタイトル＋サムネイルが表示される
- [ ] アプリ選択時に `onResult` が発火し、`onFinished` がログ出力される

### #3 + #4 subject + title
- [ ] "Share with Subject & Title" ボタンが配置され、例外なく Sharesheet が開く
- [ ] メール系アプリで件名欄に `subject` が反映される
- [ ] `ShareContent.title` を指定している（対象 OS（minSdk 31）では視覚表示されないため、表示確認は完了条件に含めない）

### #5 cancelPendingCallback
- [ ] "Cancel Pending Callback" ボタンが配置され、押下後に上表 4 層の cancel/unregister ログが出力される
- [ ] 期待ログから `stale or cancelled registration` を**除外**している（明示キャンセルでは出ない）

### 共通
- [ ] 画像/ファイル準備を伴う操作で decode の null 分岐・IO 全体 try/catch・Main の `File preparation failed` 表示がある
- [ ] 新規 receiver・全 onClick 主要処理に `Log.d` がある
- [ ] public composable / 関数に KDoc がある（コメント・KDoc は英語）
- [ ] ユーザー入力項目を追加していない（固定サンプル値のみ）
- [ ] サンプルアプリがビルド成功する

---

## 手動確認手順（end-to-end）

### カスタムチューザーアクション（API 34+）
1. ShareSampleScreen で "Share Text with Custom Action" を押す
2. Sharesheet 内に "Custom" アクション（編集アイコン）が表示されることを確認
3. "Custom" をタップ → "Custom chooser action tapped" の Toast が出ることを確認
4. （API 33 以下では通常共有として開くことを確認）

### コールバック + リッチプレビュー
1. "Share with Callback + Rich Preview" を押す
2. Sharesheet 上部にタイトル "Callback with rich preview" とサムネイルが出ることを確認
3. アプリを選択 → `✅ Selected: <pkg>` が表示され、Logcat に `[onFinished] callback + preview` が出ることを確認

### subject + title
1. "Share with Subject & Title" を押す
2. Gmail 等メールアプリを選択 → 件名欄に "Sample subject line" が入ることを確認
3. title は対象 OS（minSdk 31）の標準 Sharesheet では表示されない（視覚確認は対象外。例外なく開けば OK）

### pending callback 明示キャンセル（レビュー指摘①反映）
1. `adb logcat -s CancelPendingShareCallbackUseCase ShareRepositoryImpl ShareCallbackCoordinator AndroidShareCallbackReceiverRegistry` を開いておく
2. "Share with Callback"（または "+ Rich Preview"）を押して Sharesheet を開く
3. Sharesheet を閉じて画面へ戻り、"Cancel Pending Callback" を押す
4. Logcat に次が順に出ることを確認:
   - `CancelPendingShareCallbackUseCase: [invoke]`
   - `ShareRepositoryImpl: [cancelPendingCallback]`
   - `ShareCallbackCoordinator: [cancel]`
   - `AndroidShareCallbackReceiverRegistry: [unregister] receiver: ...`
5. （`stale or cancelled registration` は明示キャンセルでは出ないことに留意）

---

## 注意事項

- ライブラリ（`android_library` / `unity_android_plugin`）は変更しない。v4 はサンプル補完のみ
- カスタムアクションの `iconBase64` は `Base64.NO_WRAP` でエンコードする（改行混入で JSON が壊れるのを防ぐ）
- カスタムアクションの受信 receiver は `exported="false"`。ライブラリが `setPackage(context.packageName)` で
  アプリ内 broadcast として送るため、外部公開は不要かつ非推奨
- カスタムアクションは API 34（UPSIDE_DOWN_CAKE）以上でのみ Sharesheet に表示される。
  下位 API では `chooserActionsJson` は無視され通常共有になる（ライブラリ仕様）
- `Intent.createChooser` の title は Android 10（API 29）以降の標準 Sharesheet では表示されない。
  本プロジェクトは minSdk 31 のため対象 OS の全端末で非表示となる。`ShareContent.title` の指定は
  API 経路の確認が主目的で、視覚確認は対象外とする
- リッチプレビューのサムネイルはファイルパスで渡す（`cacheDir` 配下なら既存 FileProvider でカバー）
- `cancelPendingCallback` の明示ボタンは `DisposableEffect.onDispose` の自動解除とは独立した追加デモ。
  両者は併存して問題ない（`coordinator.cancel()` は冪等）
- 明示キャンセルの証跡は cancel/unregister 経路のログで確認する。`onReceive` 系ログは出ない
