# Android クリップボード サンプルアプリ 実装計画 v3

## 基本情報

- 作成日: 2026-07-25
- 改訂: v3（監視を `android_library` の native API 経由に変更。Unity plugin への依存を撤回）
- 機能名: clipboard
- 対象OS: Android（Android 12 / API 31 以降）
- 対象サンプルアプリ: `android/AndroidLibraryExample`
- 設計書: `artifact/designs/clipboard/2026-07-25-android-clipboard-design.md`（**v5**）
- 実装結果: `artifact/results/clipboard/2026-07-25-android-clipboard-implementation-feature-result-v3.md`
- レビュー: `artifact/reviews/clipboard/2026-07-25-android-clipboard-sample-app-design-review.md`
- 前版: 同ディレクトリ `...-sample-app-design-v1.md` / `-v2.md`
- 使用言語: Kotlin（Jetpack Compose）

設計書・実装結果由来の前提は「【実装済み】」、本計画での追加判断は「【計画判断】」として区別する。

---

## 0. v2 からの変更点と、その前提となった機能側の修正

### 0.1 判明した問題

v2 では、レビュー指摘（監視を実装済み API で検証すべき）に応えるため、監視を `UnityAndroidClipboardManager`（`unity_android_plugin`）経由とし、`app/build.gradle.kts` に `implementation(project(":unity_android_plugin"))` を追加する計画とした。

しかしこれは **native サンプルが Unity Bridge 層に依存する**ことを意味し、層構造として不適切だった。根本原因は機能側にあり、`agent-rules/coding-rules/common.md:103` の規約違反だった:

> Unity Bridge 専用クラスにも Delegate を実装しない（iOS-native など**別用途での利用ができなくなるため**）

- v4 時点の実装は system `OnPrimaryClipChangedListener` を所有する `ClipboardChangeMonitor` を `unity_android_plugin`（Unity Bridge 専用モジュール）に配置していた
- そのため native サンプル等、非 Unity の呼び出し元から監視機能を利用できなかった
- iOS は `IosLibrary/.../IosShareManager.swift`（native）と `UnityIosPlugin/.../UnityIosShareManager.swift`（Bridge）の2層構造になっており、Android のみ native 側の受け皿が欠けていた

### 0.2 機能側の修正（設計書 v5 / 実施済み）

本計画の前提として、以下を機能側で修正済み:

| 項目 | 内容 |
|---|---|
| 移動 | `ClipboardChangeMonitor` を `unity_android_plugin` から `android/android_library/src/main/java/android/library/clipboard/presentation/ClipboardChangeMonitor.kt` へ移動し `public` 化 |
| 委譲 | `UnityAndroidClipboardManager` は自身の system listener を持たず、上記クラスへ委譲 |
| テスト移動 | `ClipboardChangeMonitorTest`（instrumented）を `android_library/src/androidTest/java/android/library/clipboard/presentation/` へ移動 |
| 検証 | 両モジュールのコンパイル・単体テスト・instrumented テストのコンパイル・Lint・AAR 生成がすべて成功。既存テスト回帰なし |

### 0.3 本計画（v3）での変更点

| # | v2 | v3 |
|---|---|---|
| 1 | 監視を `UnityAndroidClipboardManager` 経由で実装 | **`android_library` の `ClipboardChangeMonitor` を直接利用** |
| 2 | `app/build.gradle.kts` に `:unity_android_plugin` を追加 | **依存追加は不要**（変更ファイルから除外） |
| 3 | Manager の operation listener / change listener を登録 | 不要。`start(context) { ... }` / `stop()` のみ |
| 4 | シングルトン `object` の listener リーク対策が必須 | `ClipboardChangeMonitor` は通常のクラスで画面がインスタンスを保持するため、`DisposableEffect` での `stop()` のみで足りる |

v2 のレビュー指摘 2 件（監視は実装済み API で検証 / URI は実 FileProvider URI）は、いずれも v3 でも満たしている。前者は「実装済み API」の所在が Unity Bridge から native library へ移った形で解決した。

---

## 1. 前提情報の抽出

### 1.1 in-scope 機能【実装済み】

- プレーンテキストのコピー
- HTML テキストのコピー
- URI（content:// / file://）のコピー
- 複数テキストのコピー（同一形式）
- クリップボードの読み取り（ペースト）
- データ有無確認（`hasClip`）
- メタデータ取得（`getDescription`）
- クリップボードのクリア
- 機微情報フラグ付きコピー（`isSensitive`、Android 13+ でプレビュー抑止）
- クリップボード変更監視（開始/停止）

**すべて `android_library` のみで確認できる**【v5 で解消】。サンプルアプリは Unity plugin に依存しない。

### 1.2 公開 API と入力制約【実装済み】

**(A) copy / read / clear 系 → `ClipboardUseCases`（`android.library.clipboard.data.repository`）**

既存 `ShareSampleScreen` が `ShareUseCases(activity)` を直接呼ぶのと同じ方式。

| API | 引数 | 戻り値 | 入力制約 |
|---|---|---|---|
| `copyPlainText(ClipContent.PlainText)` | `text`, `label`, `isSensitive` | Unit | `text` は空文字許容 |
| `copyHtmlText(ClipContent.HtmlText)` | `plainText`, `htmlText`, `label`, `isSensitive` | Unit | `htmlText` が空なら `EmptyContent` |
| `copyUri(ClipContent.UriContent)` | `uri`, `label`, `isSensitive` | Unit | blank および `content`/`file` 以外の scheme は `InvalidUri` |
| `copyMultipleText(ClipContent.MultipleText)` | `texts`, `label`, `isSensitive` | Unit | 空リストは `EmptyItemList` |
| `read()` | なし | `ClipReadResult?` | 空クリップボードは `null`（正常系） |
| `hasClip()` | なし | `Boolean` | - |
| `getDescription()` | なし | `ClipDescriptionInfo?` | 空クリップボードは `null`（正常系） |
| `clear()` | なし | Unit | - |

**(B) 変更監視 → `ClipboardChangeMonitor`（`android.library.clipboard.presentation`）**【v5】

| API | 引数 | 戻り値 | 備考 |
|---|---|---|---|
| `start(context, onChange)` | `Context`, `() -> Unit` | Unit | 二重呼び出しは no-op。`onChange` は system listener のコールバックスレッドで呼ばれる |
| `stop()` | なし | Unit | 未監視時は no-op |
| `isObserving()` | なし | `Boolean` | 監視状態 |

`ClipboardChangeMonitor` は通常のクラス（シングルトンではない）ため、画面側で `remember { ClipboardChangeMonitor() }` として保持し、`DisposableEffect` で `stop()` する。

### 1.3 エラー契約【実装済み】

サンプルはネイティブ層を直接呼ぶため、`ClipboardDomainError` を直接 catch する。

| DomainError | サンプル表示文言（計画） | 発生条件 |
|---|---|---|
| `EmptyContent` | `❌ EmptyContent: HTML body is empty` | `copyHtmlText` で `htmlText` が空 |
| `EmptyItemList` | `❌ EmptyItemList: no items to copy` | `copyMultipleText` で空リスト |
| `InvalidUri` | `❌ InvalidUri: {uri}` | `copyUri` で blank / 未対応 scheme |
| `ClipboardUnavailable` | `❌ ClipboardUnavailable` | クリップボードサービス取得失敗 |
| `ReadNotAllowed` | `❌ ReadNotAllowed: app must be in foreground` | `read()` 中に `SecurityException` |

`ClipboardDomainError` は `data object` / `data class` のため `e.message` が null になりうる【計画判断】。`when (e)` で型ごとに固定文言を返す helper を用意する。

監視は例外を投げず、失敗時は内部で警告ログのみ（`ClipboardManager` 取得失敗時など）。サンプルは `isObserving()` の戻り値で開始成否を判定する【計画判断】。

### 1.4 テスト観点【実装済み】

- 正常系: 各 copy → 他アプリへ貼り付け成功、read で往復確認
- 異常系: 空 HTML / 空リスト / 不正 URI scheme のエラー表示
- 境界値: 空文字コピー（許容）、空クリップボードの read/getDescription が `null`（正常系）
- API 境界: API 33+ の機微フラグによるプレビュー抑止、API 32 以下は自前トースト
- リーク: 監視の start/stop 後に発火しないこと、画面離脱で解除されること

---

## 2. 既存サンプルコードの深掘り結果

### 2.1 確認した既存コード

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/`
  - `MainRouter.kt`: `MainScreen` enum + `when` 分岐、`BackHandler`
  - `MainMenuScreen.kt`: `LazyColumn` + `MainMenuListItem`（Card）
  - `ShareSampleScreen.kt`（775行）: 主参照。`ShareUseCases` 直呼び、`statusText` 状態、カテゴリ別見出し + Button 群、`cacheDir` へのサンプルファイル生成
  - `NotificationSampleScreen.kt`: 権限チェック helper パターン
- 主参照ペア（モバイル）: `ios/IosLibraryExample/IosLibraryExample/`
  - `ContentView.swift`: `NavigationStack` + `menuCard`
  - `ShareSampleView.swift`: `sectionView(title:)`、`updateResult(isSuccess:result:)` で ✅/❌ 統一

**確認結果【計画判断】**: 既存サンプル（Dialog / Notification / Share）はいずれも `android_library` のみを参照し、`android.unity.*` の import は 0 件。v3 はこの規約を維持する。

**iOS/macOS に clipboard サンプルは未実装**。Android が clipboard サンプルの初実装となる。UI 構成は iOS `ShareSampleView` のセクション構造を踏襲しつつ、Android 既存 `ShareSampleScreen` の Compose 実装規約を優先する。

### 2.2 再利用する既存コンポーネント

| コンポーネント | 出所 | 再利用方法 |
|---|---|---|
| 画面骨格（Back → タイトル → 結果表示 → `LazyColumn`） | `ShareSampleScreen.kt` | 同一構造を踏襲 |
| カテゴリ見出し + ボタン群 | `ShareSampleScreen.kt` | `item { Text(見出し) }` + `item { Button }` を踏襲 |
| `statusText` による結果表示（✅/❌/ℹ️） | `ShareSampleScreen.kt` | 同一パターン。clipboard 用に型別 helper を追加 |
| `cacheDir` へのサンプルファイル生成 | `ShareSampleScreen.kt`（`File(context.cacheDir, "share_sample.txt")` 等） | 同方式で URI コピー用ファイルを生成 |
| `DisposableEffect` によるクリーンアップ | `ShareSampleScreen.kt`（`onDispose { shareUseCases.cancelPendingCallback() }`） | 監視の `stop()` に同パターンを適用 |
| スクロールバー | `ShareSampleScreen.kt` の `ShareSampleScrollbar` | コピーせず再利用しない【計画判断】。private かつ Share 専用命名のため。clipboard は標準スクロールのみとし、必要なら implement 時に共通化を検討（要検証） |
| `MainMenuListItem`（Card） | `MainMenuScreen.kt` | private のため、`MainMenuScreen` にメニュー項目を1件追加する形で再利用 |
| テーマ | `ui/theme/` | 変更なし |

### 2.3 追加するコンポーネント

`ClipboardSampleScreen.kt`（新規）内の private helper:

- `clipboardErrorMessage(e: ClipboardDomainError): String` — 型別固定文言
- `formatReadResult(result: ClipReadResult?): String` — read 結果の可読整形
- `formatDescription(info: ClipDescriptionInfo?): String` — メタデータ整形
- `prepareSampleUri(context: Context): String` — `cacheDir` に実ファイルを作り FileProvider で `content://` URI を生成

### 2.4 変更するファイルと変更理由

| ファイル | 変更理由 |
|---|---|
| `MainRouter.kt` | `MainScreen` enum に `CLIPBOARD_TEST` を追加、`when` 分岐と callback を追加 |
| `MainMenuScreen.kt` | `onSelectClipboardTest` パラメータとメニュー項目「Clipboard Example」を追加。`MainMenuPreview` も更新 |

**`app/build.gradle.kts` は変更しない**【v3 で撤回】。監視が `android_library` に移ったため、既存の `implementation(project(":android_library"))` のみで全機能を確認できる。

---

## 3. 実装方針

### 3.1 共通実装パターン: 維持する点

- メインメニュー → サンプル画面の導線（`MainRouter` の enum 分岐）
- 画面先頭に「← Back to Main」→ タイトル → 結果表示領域
- 機能カテゴリ単位のボタン群グルーピング（iOS `sectionView` 相当を見出し `Text` + `Button` 群で表現）
- 実行結果は ✅ / ❌ / ℹ️ で判別
- 公開 API 呼び出し前後に `Log.d`
- コールバック結果の UI 反映はメインスレッドで行う
- **`android_library` のみを参照する**（既存サンプル規約の維持）【v3 で回復】

### 3.2 共通実装パターン: 拡張する点

【計画判断】clipboard 固有の事情による拡張:

1. **エラー文言の型別 helper 化**: `ClipboardDomainError` は `message` が null になりうるため、`when (e)` による型別固定文言 helper を追加。
2. **「空は正常系」の明示表示**: `read()` / `getDescription()` の `null` は空クリップボードの正常系【実装済み】。❌ ではなく `ℹ️ Clipboard is empty (normal)` と表示する。
3. **API バージョン別の期待挙動を画面に明記**: 機微フラグは runtime API 33+ でのみ効果があるため注記テキストを置き、API 32 以下では自前 Toast を表示する。
4. **監視コールバックのスレッド marshal**: `ClipboardChangeMonitor.start` の `onChange` は system listener のコールバックスレッドで呼ばれる（KDoc 明記）。Compose state 更新の安全性のため、サンプル側でメインスレッドへ marshal する。

### 3.3 呼び出し境界

- copy/read 入口: `ClipboardUseCases(activity)` を `remember(activity)` で生成
- 監視入口: `remember { ClipboardChangeMonitor() }` で画面がインスタンスを保持
- 戻り値: copy/clear は Unit（例外で失敗）、read/getDescription は nullable、hasClip は Boolean、監視は `isObserving()` で状態確認
- 例外: `ClipboardDomainError` を catch → 型別文言、その他 `Exception` は `❌ Unexpected: ...`
- 監視解除: `DisposableEffect(monitor) { onDispose { monitor.stop() } }`

---

## 4. 変更ファイル一覧

### 4.1 新規作成

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ClipboardSampleScreen.kt`

### 4.2 既存変更

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainRouter.kt`
- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainMenuScreen.kt`

### 4.3 非変更（対象だが変更しない）

| ファイル | 理由 |
|---|---|
| `app/build.gradle.kts`【v3 で撤回】 | 監視が `android_library` に移ったため Unity plugin 依存は不要。既存依存のみで全機能を確認できる |
| `MainActivity.kt` | clipboard は権限不要・Intent 受信不要 |
| `AndroidManifest.xml`（app / android_library 双方） | クリップボードは権限宣言・Provider 追加が不要【実装済み】。URI コピーは既存の share FileProvider を流用するため追加宣言も不要 |
| `ShareSampleScreen.kt` / `NotificationSampleScreen.kt` | clipboard 追加による影響なし |
| `android_library` / `unity_android_plugin` 配下 | 機能側の修正は設計書 v5 の対応として実施済み。本計画ではこれ以上変更しない |
| `settings.gradle.kts` | 変更不要 |
| `docs/` 配下 | 固定で変更対象外 |

---

## 5. 実装詳細（implement-sample-app ステップ3で行う内容）

### 5.1 画面構成

```
ClipboardSampleScreen
├── [Button] ← Back to Main
├── [Text] Clipboard Example（タイトル）
├── [Text] statusText（結果表示領域）
└── LazyColumn
    ├── "Copy" セクション
    │   ├── [Button] Copy Plain Text
    │   ├── [Button] Copy Plain Text (empty, allowed)
    │   ├── [Button] Copy HTML Text
    │   ├── [Button] Copy URI (content:// via FileProvider)
    │   └── [Button] Copy Multiple Text
    ├── "Copy - Sensitive" セクション
    │   ├── [Text] 注記: Android 13+ でのみプレビュー抑止
    │   └── [Button] Copy Sensitive Text
    ├── "Read / Inspect" セクション
    │   ├── [Button] Read Clipboard
    │   ├── [Button] Has Clip
    │   └── [Button] Get Description
    ├── "Clear" セクション
    │   └── [Button] Clear Clipboard
    ├── "Observe" セクション
    │   ├── [Text] 注記: 前面時のみ有効（Android 10+ の読み取り制限）
    │   ├── [Button] Start Observing
    │   └── [Button] Stop Observing
    └── "Error Cases" セクション
        ├── [Button] Copy HTML (empty) → EmptyContent
        ├── [Button] Copy Multiple (empty list) → EmptyItemList
        ├── [Button] Copy URI (blank) → InvalidUri
        └── [Button] Copy URI (http scheme) → InvalidUri
```

【計画判断】入力欄は設けず固定サンプル値を用いる。既存 `ShareSampleScreen` も固定値方式であり、UI 規約を揃えるため。

### 5.2 各 API の呼び出し方針

| ボタン | 呼び出し | 結果表示 |
|---|---|---|
| Copy Plain Text | `copyPlainText(PlainText(text = "Hello from native-toolkit", label = "sample"))` | `✅ copyPlainText called` |
| Copy Plain Text (empty) | `copyPlainText(PlainText(text = ""))` | `✅ copyPlainText (empty) called` |
| Copy HTML Text | `copyHtmlText(HtmlText(plainText = "Hello", htmlText = "<b>Hello</b>"))` | `✅ copyHtmlText called` |
| Copy URI | `prepareSampleUri(context)` で実 URI 生成 → `copyUri(UriContent(uri = uri))` | `✅ copyUri called: {uri}` |
| Copy Multiple Text | `copyMultipleText(MultipleText(texts = listOf("first", "second", "third")))` | `✅ copyMultipleText called (3 items)` |
| Copy Sensitive Text | `copyPlainText(PlainText(text = "P@ssw0rd-sample", isSensitive = true))` + API 32 以下は Toast | `✅ copySensitive called (preview suppressed on API 33+)` |
| Read Clipboard | `read()` | 非 null: `✅ Read: {整形結果}` / null: `ℹ️ Clipboard is empty (normal)` |
| Has Clip | `hasClip()` | `✅ hasClip = true/false` |
| Get Description | `getDescription()` | 非 null: `✅ {label, mimeTypes, isStyledText, classificationStatus}` / null: `ℹ️ Clipboard is empty (normal)` |
| Clear Clipboard | `clear()` | `✅ clear called` |
| Start Observing【v3】 | `monitor.start(context) { ... }` → `monitor.isObserving()` で確認 | `✅ observing started`、発火時 `ℹ️ Clipboard changed (n)` |
| Stop Observing【v3】 | `monitor.stop()` | `✅ observing stopped` |
| Error Cases 各種 | 上記 copy API に不正値 | `❌ {型別文言}` |

### 5.3 URI コピー用の実 URI 生成

```
prepareSampleUri(context):
  1. File(context.cacheDir, "clipboard_sample.txt") を作成し、サンプル文字列を書き込む
  2. FileProvider.getUriForFile(
       context,
       "${context.packageName}.native_toolkit.share.fileprovider",
       file
     ) で content:// URI を取得
  3. uri.toString() を返す
```

- authority 文字列はハードコードする【計画判断】。`android_library` の `SHARE_FILE_PROVIDER_AUTHORITY_SUFFIX` は `internal` で app モジュールから参照できないため（確認済み）。
- `android_library` の `native_toolkit_share_file_paths.xml` に `<cache-path name="cache" path="." />` があるため、`cacheDir` 配下は FileProvider で URI 化できる（確認済み）。
- FileProvider の `<provider>` 宣言は `android_library` の manifest から merge されるため、app 側の manifest 変更は不要。
- 他アプリでの貼り付けを確認する場合、URI 読み取り権限の付与はクリップボード経由では制約がある【実装済み: 企画書の要検証事項】。手動確認では「文字列としての URI が貼り付く」ことを主目的とし、実体参照の可否は要検証扱いとする。

### 5.4 監視の実装方針【v3】

```
val monitor = remember { ClipboardChangeMonitor() }
var changeCount by remember { mutableIntStateOf(0) }

Start Observing ボタン:
  monitor.start(context) {
    // system listener のコールバックスレッドで呼ばれるため main へ marshal
    mainHandler.post {
      changeCount++
      statusText = "ℹ️ Clipboard changed ($changeCount)"
    }
  }
  statusText = if (monitor.isObserving()) "✅ observing started" else "❌ failed to start observing"

Stop Observing ボタン:
  monitor.stop()
  statusText = "✅ observing stopped"

DisposableEffect(monitor) {
  onDispose { monitor.stop() }   // 画面離脱時に確実解除（リーク防止）
}
```

- `ClipboardChangeMonitor` はシングルトンではないため、画面インスタンスが監視状態を保持する。v2 で懸念した static listener リークは発生しない。
- 二重 start は Monitor 内部で no-op【実装済み】。サンプルは Start を2回押しても発火が重複しないことを確認できる。
- 発火回数カウンタを持ち、stop 後に増えないことを目視確認できるようにする。
- main への marshal 方法（`Handler(Looper.getMainLooper())` か Compose の `rememberCoroutineScope` + `withContext(Dispatchers.Main)`）は実装時に既存サンプルの流儀へ合わせる。

### 5.5 入力バリデーション方針

- サンプルは固定値のため UI 側バリデーションは行わない。
- 「Error Cases」セクションで意図的に不正値を渡し、**ライブラリ側の検証（`ClipboardDomainError`）が正しく発火することを確認する**のが目的。
- したがってサンプル側で事前チェックして呼び出しを抑止しない（ライブラリの検証を殺さない）。

---

## 6. 手動確認観点

| # | 観点 | 手順 | 期待結果 |
|---|---|---|---|
| 1 | プレーンテキストのコピー | Copy Plain Text → メモアプリで貼り付け | 文字列が貼り付けられる |
| 2 | 空文字コピー（境界値） | Copy Plain Text (empty) | ✅ 表示、例外にならない |
| 3 | HTML コピー | Copy HTML Text → HTML 対応アプリで貼り付け | 書式付きで貼り付く（対応アプリのみ） |
| 4 | URI コピー（実 URI） | Copy URI → Read Clipboard | items に `content://...` URI が入る |
| 5 | URI の他アプリ貼り付け | Copy URI → メモアプリで貼り付け | URI 文字列が貼り付く（実体参照可否は要検証） |
| 6 | 複数テキストコピー | Copy Multiple Text → Read Clipboard | items が3件 |
| 7 | 読み取り往復 | 各 copy → Read Clipboard | コピーした内容が読める |
| 8 | 空クリップボードの読み取り | Clear → Read / Get Description | ℹ️ 表示（❌ にならない） |
| 9 | hasClip | Copy → Has Clip / Clear → Has Clip | true / false |
| 10 | クリア | Copy → Clear → Has Clip | false |
| 11 | 機微フラグ（API 33+） | Copy Sensitive Text | システムのコピー確認 UI に内容が表示されない |
| 12 | コピー確認 UI 境界（API 32 以下） | Copy Sensitive Text | システム確認 UI が出ず、自前 Toast が表示される |
| 13 | 貼り付けアクセス通知（API 31+） | 他アプリでコピー → 本アプリで Read | 「クリップボードから貼り付けました」トーストが出る |
| 14 | 監視の発火【v3】 | Start Observing → 他アプリでコピー | ℹ️ Clipboard changed (n) が増える |
| 15 | 監視の二重開始 no-op | Start Observing を2回 → 他アプリでコピー | カウンタが1回分のみ増える |
| 16 | 監視停止 | Stop Observing → 他アプリでコピー | カウンタが増えず、✅ observing stopped が表示される |
| 17 | 画面離脱時の解除 | Start Observing → Back → 他アプリでコピー → 再入場 | 監視解除済みでカウンタが増えていない |
| 18 | エラー: 空 HTML | Copy HTML (empty) | ❌ EmptyContent |
| 19 | エラー: 空リスト | Copy Multiple (empty list) | ❌ EmptyItemList |
| 20 | エラー: blank URI | Copy URI (blank) | ❌ InvalidUri |
| 21 | エラー: 未対応 scheme | Copy URI (http scheme) | ❌ InvalidUri |
| 22 | ログに本文が出ないこと | 各 copy 実行中に Logcat 確認 | 本文が出力されず length/scheme のみ（実装レビュー v2/v3 対応の確認） |
| 23 | Unity 非依存の確認【v3】 | `app/build.gradle.kts` と import を確認 | `unity_android_plugin` への依存・`android.unity.*` の import が存在しない |

### 確認対象 API バージョン

| API | 理由 |
|---|---|
| API 31（Android 12） | 最小サポート、貼り付けアクセス通知 |
| API 32（Android 12L） | コピー確認 UI 境界の直前（自前 Toast が必要な上限） |
| API 33（Android 13） | コピー確認 UI 導入・機微フラグ有効 |
| API 34（Android 14） | 回帰確認 |

---

## 7. 要検証事項

| 項目 | 内容 |
|---|---|
| 監視コールバックのスレッド | `ClipboardChangeMonitor.start` の `onChange` が実際にどのスレッドで呼ばれるか実機確認。KDoc は「コールバックスレッド」と明記しており、サンプルは main へ marshal する前提だが、実測して過剰／不足がないか確認する |
| クリップボード経由の URI 権限 | `content://` URI を他アプリが実体参照できるか（企画書の要検証事項と同じ）。手動確認 #5 の期待値を実機結果で確定する |
| スクロールバーの要否 | clipboard の項目数（6セクション + ボタン約17個）で標準スクロールに収まるか。収まらない場合は `ShareSampleScrollbar` 相当の共通化を検討 |
| iOS/macOS への横展開 | 現時点で clipboard サンプルは Android のみ。他 OS 実装時に本画面構成を主参照とするか要判断。あわせて iOS/macOS 側でも監視 API が native library に置かれているか確認する |

---

## 8. 実行確認

- 提示文: 「この実装計画で進めますか？」
- 選択肢:
  - 承認する: 計画を確定、次のレビュー workflow（review-document）へ進む
  - 修正する: 指摘内容を反映して計画ファイルを更新
  - キャンセル: 計画ファイルは保持したまま終了
- ユーザー回答: 未回答
