# Android クリップボード機能 調査結果

- 作成日: 2026-07-25
- 改訂日: 2026-07-25（v2〜v5: レビュー指摘を順次反映 / v5: 4回目レビュー指摘反映）
- 対象OS: Android（Android 12 / API 31 以降）
- 対象機能: クリップボード（Clipboard: コピー / ペースト）
- 使用言語: Kotlin

---

## 目的

Android のネイティブクリップボード API を全網羅し、native-toolkit への組み込み設計に必要な情報を整理する。テキスト・URI・Intent・HTML など各データ型のコピー / ペースト、クリップボード変更監視、Android 12 / 13 のプライバシー仕様（アクセス通知・機微情報フラグ）を対象とする。

---

## 調査対象範囲

### In scope
- プレーンテキストのコピー / ペースト
- HTML テキストのコピー / ペースト
- URI（content://）のコピー / ペースト（画像・ファイル参照を含む。画像はビットマップ直接ではなく content:// URI 経由で扱う）
- Intent のコピー / ペースト
- 複数 Item（`ClipData.Item`）のコピー
- クリップボードの内容確認（`hasPrimaryClip` / `ClipDescription`）
- クリップボードのクリア（`clearPrimaryClip`）
- クリップボード変更監視（`OnPrimaryClipChangedListener`）
- 機微情報フラグ（`EXTRA_IS_SENSITIVE`、Android 13+）
- Android 12+ のスタイル付きテキスト判定・信頼度スコア

### Out of scope
- iOS / macOS / Windows のクリップボード API
- リッチコンテンツ受信（`OnReceiveContentListener` / ドラッグ&ドロップ経由の貼り付け UI）
- サードパーティ SDK
- ドラッグ&ドロップ（`ClipData` を共有するが本調査対象外）
- API 35+ 追加の `ClipData.Item.Builder` / `getIntentSender()` / `Builder.setIntentSender()` を用いた IntentSender クリップの**実運用**（native-toolkit の Clipboard 公開 API では対象外とする。最小サポート API 31〜Android 14 では利用できず、通常のコピー / ペースト用途に不要なため。存在のみ下記 API 表に記載＝「全網羅」の担保）

---

## 公式文書一覧（最優先ソース）

| タイトル | URL |
|---|---|
| Copy and paste（概説） | https://developer.android.com/develop/ui/views/touch-and-input/copy-paste |
| ClipboardManager | https://developer.android.com/reference/android/content/ClipboardManager |
| ClipData | https://developer.android.com/reference/android/content/ClipData |
| ClipData.Item（coerceToText / coerceToHtmlText / coerceToStyledText） | https://developer.android.com/reference/android/content/ClipData.Item |
| ClipData.Item.Builder（API 35、参考） | https://developer.android.com/reference/android/content/ClipData.Item.Builder |
| ClipDescription（getClassificationStatus / getConfidenceScore） | https://developer.android.com/reference/android/content/ClipDescription |
| ClipboardManager.OnPrimaryClipChangedListener | https://developer.android.com/reference/android/content/ClipboardManager.OnPrimaryClipChangedListener |
| Copy and paste – Sensitive content（機微情報） | https://developer.android.com/develop/ui/views/touch-and-input/copy-paste#sensitive-content |
| ContextCompat.getSystemService | https://developer.android.com/reference/androidx/core/content/ContextCompat#getSystemService(android.content.Context,java.lang.Class%3CT%3E) |

---

## 補助ソース一覧（必要時のみ）

| 内容 | 情報源 | 信頼度 |
|---|---|---|
| Android 13 のクリップボードエディタ / 機微情報プレビュー抑止の実挙動 | Android Developers Blog（公式ブログ） | medium |

補足: 本調査書の設計根拠は全て公式 Copy and paste ドキュメントと API reference で裏付け済み。補助ソースは実機挙動の参考としてのみ利用し、設計根拠には使用しない。公式文書と矛盾する記述は採用しない。低信頼度（技術ブログ等）ソースは今回不要のため掲載しない。

---

## 機能マップ（サブ機能分解）

```
クリップボード機能
├── コピー（書き込み）
│   ├── プレーンテキスト（newPlainText）
│   ├── HTMLテキスト（newHtmlText）
│   ├── URI（newUri / newRawUri）
│   ├── Intent（newIntent）
│   └── 複数Item（ClipData.addItem）
├── ペースト（読み取り）
│   ├── テキスト取得（getText / coerceToText）
│   ├── URI取得（getUri）
│   ├── Intent取得（getIntent）
│   └── MIMEタイプ判定（ClipDescription.hasMimeType）
├── 内容確認 / メタデータ
│   ├── hasPrimaryClip
│   ├── getPrimaryClipDescription（データ本体に触れない）
│   ├── isStyledText（API 31+）
│   ├── getClassificationStatus（API 31+）
│   └── getConfidenceScore（entity type / API 31+）
├── クリア（clearPrimaryClip）
├── 変更監視（OnPrimaryClipChangedListener）
└── プライバシー
    ├── 機微情報フラグ（EXTRA_IS_SENSITIVE, API 33+）
    └── アクセス通知（Android 12+, システム自動）
```

---

## API 全網羅表（サブ機能別）

### 取得 / 初期化

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `Context.getSystemService(CLIPBOARD_SERVICE)` | ClipboardManager 取得 | サービス名定数 | `ClipboardManager` | null（稀） | API 1 |
| `ContextCompat.getSystemService(ctx, ClipboardManager::class.java)` | 型安全な取得（推奨） | context, class | `ClipboardManager?` | null | AndroidX Core |

### コピー（書き込み）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ClipData.newPlainText(label, text)` | プレーンテキスト clip 生成 | `label: CharSequence`, `text: CharSequence` | `ClipData` | なし | API 11 |
| `ClipData.newHtmlText(label, text, htmlText)` | HTML テキスト clip 生成 | `label`, `text`, `htmlText: String` | `ClipData` | なし | API 16 |
| `ClipData.newUri(resolver, label, uri)` | URI clip 生成（provider に MIME 問い合わせ） | `ContentResolver`, `label`, `uri: Uri` | `ClipData` | provider 未応答時は URI リスト型 | API 11 |
| `ClipData.newRawUri(label, uri)` | MIME 問い合わせなしの URI clip | `label`, `uri: Uri` | `ClipData` | なし | API 11 |
| `ClipData.newIntent(label, intent)` | Intent clip 生成 | `label`, `intent: Intent` | `ClipData` | なし | API 11 |
| `ClipData.addItem(Item)` | 複数 Item 追加（同一形式想定） | `ClipData.Item` | void | 通常なし。`ClipDescription` の MIME type リストは更新されないため、異種形式の混在は設計上避ける | API 11 |
| `ClipData.addItem(ContentResolver, Item)` | Item 追加時に `ClipDescription` の MIME type リストも更新する overload。URI 等で新しい MIME type が増える場合はこちらを使う | `ContentResolver`, `ClipData.Item` | void | 通常なし | API 26（最小 API 31 で利用可） |
| `ClipboardManager.setPrimaryClip(clip)` | クリップボードへ書き込み | `clip: ClipData` | void | null clip で例外 | API 11 |
| `ClipData.Item.Builder`（`setText` / `setHtmlText` / `setUri` / `setIntent` / `setIntentSender`） | Item をビルダーで構築（IntentSender を含む新しい Item を生成可能） | 各 setter | `ClipData.Item` | なし | **API 35**（公開 API では対象外・参考） |

### ペースト（読み取り）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ClipboardManager.getPrimaryClip()` | クリップボード内容取得 | なし | `ClipData?` | 空時 null / フォーカスなしで取得不可（Android 10+） | API 11 |
| `ClipData.getItemAt(index)` | Item 取得 | `index: Int` | `ClipData.Item` | `IndexOutOfBounds` | API 11 |
| `ClipData.getItemCount()` | Item 数取得 | なし | `Int` | なし | API 11 |
| `ClipData.Item.getText()` | テキスト取得 | なし | `CharSequence?` | テキスト型でなければ null | API 11 |
| `ClipData.Item.getHtmlText()` | HTML テキスト取得 | なし | `String?` | HTML 型でなければ null | API 16 |
| `ClipData.Item.getUri()` | URI 取得 | なし | `Uri?` | URI 型でなければ null | API 11 |
| `ClipData.Item.getIntent()` | Intent 取得 | なし | `Intent?` | Intent 型でなければ null | API 11 |
| `ClipData.Item.getTextLinks()` | 分類済みテキストに含まれる entity 詳細（`getConfidenceScore` の関連 API） | なし | `TextLinks?` | 分類未実施・entity 未検出で null。分類は通常 first item の短い raw text に対して実施 | API 31（公開 API で分類詳細を扱う場合のみ・参考） |
| `ClipData.Item.getIntentSender()` | Item の IntentSender 取得 | なし | `IntentSender?` | IntentSender 型でなければ null | **API 35**（公開 API では対象外・参考） |
| `ClipData.Item.coerceToText(ctx)` | 任意型をプレーンテキスト化 | `Context` | `CharSequence` | なし（URI は解決を試行） | API 11 |
| `ClipData.Item.coerceToHtmlText(ctx)` | 任意型を HTML テキスト化 | `Context` | `String` | HTML 化不可時はエスケープ済みテキスト | API 16 |
| `ClipData.Item.coerceToStyledText(ctx)` | 任意型をスタイル付きテキスト化 | `Context` | `CharSequence`（Spanned） | なし | API 16 |

### 内容確認 / メタデータ

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ClipboardManager.hasPrimaryClip()` | データ有無確認 | なし | `Boolean` | なし | API 11 |
| `ClipboardManager.getPrimaryClipDescription()` | メタデータのみ取得（本体に触れない） | なし | `ClipDescription?` | 空時 null | API 11 |
| `ClipDescription.hasMimeType(mimeType)` | MIME 対応確認 | `mimeType: String` | `Boolean` | なし | API 11 |
| `ClipDescription.getLabel()` | ラベル取得 | なし | `CharSequence` | なし | API 11 |
| `ClipDescription.getMimeType(index)` / `getMimeTypeCount()` | MIME 一覧 | index | `String` / `Int` | 範囲外 | API 11 |
| `ClipDescription.isStyledText()` | スタイル付きテキスト判定 | なし | `Boolean` | なし | API 31 |
| `ClipDescription.getClassificationStatus()` | テキスト分類の完了状態を取得 | なし | `Int`（下記定数） | なし | API 31 |
| `ClipDescription.getConfidenceScore(entity)` | エンティティ種別の信頼度（引数は **entity type**：`TextClassifier.TYPE_URL` / `TYPE_EMAIL` / `TYPE_PHONE` など。MIME type ではない） | `entity: String` | `Float`（0.0〜1.0） | 分類未完了（`getClassificationStatus() != CLASSIFICATION_COMPLETE`）で呼ぶと `IllegalStateException` | API 31 |

MIME 定数（`ClipDescription`）: `MIMETYPE_TEXT_PLAIN` / `MIMETYPE_TEXT_HTML` / `MIMETYPE_TEXT_URILIST` / `MIMETYPE_TEXT_INTENT`

分類ステータス定数（`ClipDescription`, API 31）: `CLASSIFICATION_COMPLETE` / `CLASSIFICATION_NOT_COMPLETE` / `CLASSIFICATION_NOT_PERFORMED`。`getConfidenceScore(entity)` は `getClassificationStatus() == CLASSIFICATION_COMPLETE` を確認してから呼ぶ。

テキスト分類系 API の使い分け: `ClipDescription.getConfidenceScore(entity)` は「entity 種別の信頼度スコア（Float）」を返すのに対し、`ClipData.Item.getTextLinks()` は「テキスト内の entity 位置・種別の詳細（`TextLinks`）」を返す。native-toolkit の Clipboard 公開 API として分類詳細（entity 抽出）を提供するか、コピー/ペーストの型判定のみに留めるかは設計段階で決定する（要判断）。

HTML / スタイル付きテキストの取得方針: 元データが HTML の場合は `getHtmlText()`、任意型を HTML / スタイル付きに正規化したい場合は `coerceToHtmlText()` / `coerceToStyledText()` を使う。native-toolkit の公開 API として HTML / スタイル付きペーストを提供するか、プレーンテキスト（`coerceToText`）のみに絞るかは設計段階で決定する（要判断）。

### クリア

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ClipboardManager.clearPrimaryClip()` | クリップボードを空にする | なし | void | なし | **API 28**（Android 12 では利用可） |

### 変更監視

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ClipboardManager.addPrimaryClipChangedListener(listener)` | 変更監視登録 | `OnPrimaryClipChangedListener` | void | 多重登録の重複通知 | API 11 |
| `ClipboardManager.removePrimaryClipChangedListener(listener)` | 監視解除 | 同一 listener 参照 | void | 参照不一致で未解除 | API 11 |
| `OnPrimaryClipChangedListener.onPrimaryClipChanged()` | 変更コールバック | なし | void | フォアグラウンド外では通知されない場合あり | API 11 |

### プライバシー（Android 12 / 13）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ClipDescription.EXTRA_IS_SENSITIVE` | Android 13+ のコピー確認 UI プレビューへの内容表示を抑止する**表示ヒント**（暗号化等の追加セキュリティではない） | `PersistableBundle` の boolean | - | フラグ未設定でプレビュー露出（runtime API 33+ のみ効果） | **API 33** |
| `"android.content.extra.IS_SENSITIVE"`（文字列キー） | 上記と同一の効果。**compileSdk が 33 未満**で `EXTRA_IS_SENSITIVE` 定数を参照できない場合に使う生キー | 同上 | - | - | 効果自体は runtime Android 13+ のみ |

---

## 実装リスク（権限・制約・互換性）

| リスク | 詳細 | 対策 |
|---|---|---|
| バックグラウンド読み取り制限 | Android 10（API 29）以降、フォアグラウンド or デフォルト IME 以外は `getPrimaryClip()` が取得できない | コピー / ペーストは前面 Activity から実行する。UI を持つ操作に限定 |
| 貼り付けアクセス通知トースト | Android 12（API 31）以降、他アプリのクリップボード**読み取り**時に「〇〇がクリップボードから貼り付けました」を自動表示 | 自アプリデータの読み取りは対象外。不要な `getPrimaryClip()` を避け `getPrimaryClipDescription()` で事前判定 |
| コピー確認 UI のバージョン境界 | コピー時の標準確認 UI（プレビュー表示）は Android **13（API 33）** 以降。Android 12L（API 32）以下ではアプリ側フィードバックが必要 | API 32 以下は自前 Toast / Snackbar。貼り付け通知（12+）とコピー確認 UI（13+）を混同しない |
| 機微情報の露出 | Android 13 のクリップボードプレビューにパスワード等が表示される | `EXTRA_IS_SENSITIVE` を設定。compileSdk 33 未満では文字列キーを使う。runtime API 33 未満ではプレビュー抑止効果は対象外だが、設定自体は無害 |
| clearPrimaryClip の API 差 | `clearPrimaryClip()` は API 28 追加 | 最小サポートが Android 12（API 31）なら問題なし。それ未満対応時は空 clip で代替 |
| リスナーリーク | `addPrimaryClipChangedListener` を解除しないとリーク | Activity/Service ライフサイクルで必ず `remove` する |
| getPrimaryClip の null | 空・権限なしで null | null チェックと `hasPrimaryClip()` の併用 |
| URI 権限 | `newUri` でコピーした content:// を他アプリが読むには権限付与が必要 | 受け渡し先に応じて `FLAG_GRANT_READ_URI_PERMISSION` 相当の設計を検討（クリップボード経由では制約あり、要検証） |
| 画像の責務境界 | 画像はツールキットが `content://` URI を返すところまで。デコード・表示・保存はアプリ側 | `content://` は実ファイルパスに変換せず（Scoped Storage 以降は非推奨・取得不可が多い）、アプリ側が `ContentResolver.openInputStream(uri)` で読み込む前提とする |
| coerceToText のコスト | URI 型は content 解決で I/O が発生しうる | メインスレッドでの大量処理を避ける |
| newHtmlText の API | API 16 追加（※「Android 16」ではない） | 最小 API 31 で問題なし |

---

## 簡単なサンプルコード集（サブ機能別）

### ClipboardManager 取得（共通）

```kotlin
fun clipboard(context: Context): ClipboardManager =
    ContextCompat.getSystemService(context, ClipboardManager::class.java)
        ?: context.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
```

### プレーンテキストのコピー

```kotlin
fun copyPlainText(context: Context, label: String, text: CharSequence) {
    val clip = ClipData.newPlainText(label, text)
    clipboard(context).setPrimaryClip(clip)
    // コピー時の標準確認 UI は Android 13(API 33) 以降。
    // Android 12L(API 32) 以下は自前で Toast / Snackbar を表示する。
    if (Build.VERSION.SDK_INT <= Build.VERSION_CODES.S_V2) {
        Toast.makeText(context, "コピーしました", Toast.LENGTH_SHORT).show()
    }
}
```

### HTML テキストのコピー

```kotlin
fun copyHtml(context: Context, label: String, plain: CharSequence, html: String) {
    val clip = ClipData.newHtmlText(label, plain, html)
    clipboard(context).setPrimaryClip(clip)
}
```

### URI のコピー

```kotlin
fun copyUri(context: Context, label: String, uri: Uri) {
    val clip = ClipData.newUri(context.contentResolver, label, uri)
    clipboard(context).setPrimaryClip(clip)
}
```

### Intent のコピー

```kotlin
fun copyIntent(context: Context, label: String, intent: Intent) {
    val clip = ClipData.newIntent(label, intent)
    clipboard(context).setPrimaryClip(clip)
}
```

### 複数 Item のコピー

前提: 複数 Item は「同一形式の複数選択」（例: 複数のテキスト行）を表すための機能。`ClipDescription`（MIME 情報）は最初の Item を元に作られ、`addItem` では更新されないため、テキスト・URI・Intent など**異なる形式を混在させない**。

```kotlin
fun copyMultiple(context: Context, label: String, texts: List<CharSequence>) {
    require(texts.isNotEmpty())
    val clip = ClipData.newPlainText(label, texts.first())
    texts.drop(1).forEach { clip.addItem(ClipData.Item(it)) }
    clipboard(context).setPrimaryClip(clip)
}
```

### プレーンテキストのペースト

```kotlin
fun pasteText(context: Context): CharSequence? {
    val cm = clipboard(context)
    if (!cm.hasPrimaryClip()) return null
    val desc = cm.primaryClipDescription ?: return null
    if (!desc.hasMimeType(ClipDescription.MIMETYPE_TEXT_PLAIN)) return null
    return cm.primaryClip?.getItemAt(0)?.text
}
```

### 任意データをテキスト化してペースト（coerceToText）

```kotlin
fun pasteAsText(context: Context): CharSequence? {
    val item = clipboard(context).primaryClip?.getItemAt(0) ?: return null
    return item.coerceToText(context) // text/uri/intent いずれもテキスト化
}
```

### クリップボードのクリア

```kotlin
fun clearClipboard(context: Context) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) { // API 28+
        clipboard(context).clearPrimaryClip()
    } else {
        clipboard(context).setPrimaryClip(ClipData.newPlainText("", ""))
    }
}
```

### 変更監視の登録・解除

```kotlin
class ClipboardWatcher(context: Context, private val onChange: () -> Unit) {
    private val cm = context.applicationContext
        .getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    private val listener = ClipboardManager.OnPrimaryClipChangedListener { onChange() }

    fun start() = cm.addPrimaryClipChangedListener(listener)
    fun stop() = cm.removePrimaryClipChangedListener(listener) // リーク防止に必須
}
```

### 機微情報フラグ付きコピー（Android 13+）

`EXTRA_IS_SENSITIVE` は Android 13+ のコピー確認 UI プレビューへの内容表示を抑止する**表示ヒント**であり、暗号化などの追加セキュリティではない。effect は runtime Android 13+ のみ。フラグ設定は下位バージョンでも無害なため常時付与してよい。文字列キーは **compileSdk が 33 未満**で定数を参照できない場合の代替。

```kotlin
// compileSdk 33+ の場合（推奨）: 定数を直接参照。下位 runtime では単に無視される。
fun copySensitive(context: Context, label: String, secret: CharSequence) {
    val clip = ClipData.newPlainText(label, secret).apply {
        description.extras = PersistableBundle().apply {
            putBoolean(ClipDescription.EXTRA_IS_SENSITIVE, true)
        }
    }
    clipboard(context).setPrimaryClip(clip)
}

// compileSdk 33 未満で定数を参照できない場合は生キーを使用する。
// putBoolean("android.content.extra.IS_SENSITIVE", true)
```

---

## 要検証事項

| 項目 | 内容 |
|---|---|
| クリップボード経由の URI 権限 | `newUri` でコピーした content:// を他アプリが読み取る際の権限付与挙動（`FLAG_GRANT_READ_URI_PERMISSION` の有効範囲） |
| OnPrimaryClipChangedListener 発火条件 | バックグラウンド時・自アプリ以外の変更で発火するか（Android 10+ の読み取り制限との関係） |
| getConfidenceScore の分類器可用性 | 端末・言語により分類が未実施（`CLASSIFICATION_NOT_PERFORMED`）となる条件と `getClassificationStatus()` ガードの実効性。引数は entity type（`TYPE_URL` 等）であり MIME type ではない点も実機確認 |
| アクセス通知の抑止可否 | `getPrimaryClipDescription()` のみ使用時にトーストが出ないことの各バージョン確認 |

---

## Definition of Done

- [ ] プレーンテキストのコピー / ペーストが動作する（API 31, 32, 33, 34 で確認）
- [ ] HTML・URI・Intent の各コピー / ペーストが動作する
- [ ] 複数 Item のコピーが動作する
- [ ] `hasPrimaryClip` / `getPrimaryClipDescription` による事前判定が動作する
- [ ] `clearPrimaryClip()` でクリップボードがクリアされる
- [ ] `OnPrimaryClipChangedListener` が登録・解除でき、解除後に通知が来ない（リークなし）
- [ ] Android 13+ で `EXTRA_IS_SENSITIVE` によりプレビューに内容が表示されない
- [ ] Android 13+（API 33+）でシステムのコピー確認 UI が表示され、Android 12L 以下（API 32 以下）では自前トーストが出る
- [ ] Android 12+（API 31+）で他アプリ読み取り時の貼り付けアクセス通知が出る（コピー確認 UI とは別仕様）
- [ ] バックグラウンドからの `getPrimaryClip()` 制限を考慮した実装になっている
- [ ] サンプルアプリで全サブ機能が確認できる

### テスト確認 API バージョン

| API | 理由 |
|---|---|
| API 31（Android 12） | 最小サポート。貼り付けアクセス通知・スタイル付きテキスト判定・信頼度スコアの導入 |
| API 32（Android 12L） | コピー確認 UI 境界の直前バージョン。自前フィードバックが必要な上限を検証 |
| API 33（Android 13） | コピー確認 UI 導入・`EXTRA_IS_SENSITIVE` によるプレビュー抑止の確認 |
| API 34（Android 14） | Android 14 での回帰確認 |
