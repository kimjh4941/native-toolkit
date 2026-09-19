# Android クリップボード サンプルアプリ 実装計画 v2

## 基本情報

- 作成日: 2026-07-25
- 改訂: v2（レビュー指摘反映: 監視を実装済み Manager API 経由へ変更、URI コピーを実 FileProvider URI へ変更）
- 機能名: clipboard
- 対象OS: Android（Android 12 / API 31 以降）
- 対象サンプルアプリ: `android/AndroidLibraryExample`
- 設計書: `artifact/designs/clipboard/2026-07-25-android-clipboard-design.md`（v4）
- 実装結果: `artifact/results/clipboard/2026-07-25-android-clipboard-implementation-feature-result-v3.md`
- レビュー: `artifact/reviews/clipboard/2026-07-25-android-clipboard-sample-app-design-review.md`（総合評価: 要修正）
- 前版: `artifact/designs/clipboard/2026-07-25-android-clipboard-sample-app-design-v1.md`
- 使用言語: Kotlin（Jetpack Compose）

設計書・実装結果由来の前提は「【実装済み】」、本計画での追加判断は「【計画判断】」として区別する。

---

## 0. v1 からの変更点（レビュー反映）

| # | 重大度 | 指摘 | 反映内容 |
|---|---|---|---|
| 1 | 高 | 変更監視が platform `ClipboardManager` 直呼びで、実装済み API の検証にならない | 監視を `UnityAndroidClipboardManager`（public）経由に変更。`app/build.gradle.kts` に `implementation(project(":unity_android_plugin"))` を追加し、変更ファイル一覧に含めた |
| 2 | 中 | URI コピーのサンプル値が実体のない `content://.../sample` | `cacheDir` に実ファイルを作成し `FileProvider.getUriForFile(...)` で実 URI を生成する helper 方針を明記。手動確認も貼り付け確認まで含めた |

反映にあたり、以下を事前検証済み【計画判断】:

- `UnityAndroidClipboardManager` の `setClipboardChangeListener` / `clearClipboardChangeListener` / `startObserving(context)` / `stopObserving()` および nested `interface ClipboardChangeListener` はいずれも public → app モジュールから呼び出し可能
- app モジュールの現依存は `implementation(project(":android_library"))` のみ → unity plugin の追加が必要
- `SHARE_FILE_PROVIDER_AUTHORITY_SUFFIX` は `internal` → app モジュールからは参照不可。authority 文字列をサンプル側で組み立てる必要がある
- `android_library` の `res/xml/native_toolkit_share_file_paths.xml` に `<cache-path name="cache" path="." />` があり、`cacheDir` 配下のファイルは FileProvider で URI 化できる

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

### 1.2 公開 API と入力制約【実装済み】

サンプルアプリは 2 系統の実装済み API を使い分ける【計画判断】。

**(A) copy / read / clear 系 → `android_library` の `ClipboardUseCases`**

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

**(B) 変更監視 → `unity_android_plugin` の `UnityAndroidClipboardManager`**【レビュー反映】

変更監視は設計上 UseCase / Port を経由せず、Manager 層の `ClipboardChangeMonitor`（internal）が system Listener を所有する【実装済み】。監視の実装済み経路は Manager の public API のみのため、サンプルもここを通す。

| API | 引数 | 備考 |
|---|---|---|
| `setClipboardChangeListener(listener)` | `ClipboardChangeListener` | 登録のみ。監視は開始しない |
| `startObserving(context)` | `Context` | system listener 登録。二重呼び出しは no-op |
| `stopObserving()` | なし | 監視停止。`ClipboardOperationListener` に `stopObserving` 成功を通知 |
| `clearClipboardChangeListener()` | なし | 監視停止 + listener 解除 |
| `setClipboardOperationListener(listener)` | `ClipboardOperationListener` | `stopObserving` の結果通知受信に使用 |
| `clearClipboardOperationListener()` | なし | listener 解除 |

**注意点【計画判断】**: `UnityAndroidClipboardManager` は Kotlin `object`（シングルトン）で listener を static に保持する。Compose の state や Activity を捕捉した listener を登録したまま画面を離れるとリークするため、`DisposableEffect` で `clearClipboardChangeListener()` と `clearClipboardOperationListener()` を必ず呼ぶ。

**方針の記録【計画判断】**: 既存サンプル（Dialog / Notification / Share）はいずれも `android_library` のみを使い、`unity_android_plugin` を参照していない。本計画で初めて app モジュールが unity plugin に依存する。これは「監視の実装済み経路が Manager にしか存在しない」ためのやむを得ない選択であり、copy/read 系は従来どおり `android_library` 直呼びを維持して既存サンプル規約との整合を保つ。

### 1.3 エラー契約【実装済み】

copy/read 系はネイティブ層を直接呼ぶため、`ClipboardDomainError` を直接 catch する。

| DomainError | サンプル表示文言（計画） | 発生条件 |
|---|---|---|
| `EmptyContent` | `❌ EmptyContent: HTML body is empty` | `copyHtmlText` で `htmlText` が空 |
| `EmptyItemList` | `❌ EmptyItemList: no items to copy` | `copyMultipleText` で空リスト |
| `InvalidUri` | `❌ InvalidUri: {uri}` | `copyUri` で blank / 未対応 scheme |
| `ClipboardUnavailable` | `❌ ClipboardUnavailable` | クリップボードサービス取得失敗 |
| `ReadNotAllowed` | `❌ ReadNotAllowed: app must be in foreground` | `read()` 中に `SecurityException` |

`ClipboardDomainError` は `data object` / `data class` のため `e.message` が null になりうる【計画判断】。`when (e)` で型ごとに固定文言を返す helper を用意する。

監視系は Manager 経由のため、`ClipboardOperationListener.onClipboardOperation(operation, isSuccessful, errorMessage)` の `errorMessage`（Bridge 文字列）を受け取る。

### 1.4 テスト観点【実装済み】

- 正常系: 各 copy → 他アプリへ貼り付け成功、read で往復確認
- 異常系: 空 HTML / 空リスト / 不正 URI scheme のエラー表示
- 境界値: 空文字コピー（許容）、空クリップボードの read/getDescription が `null`（正常系）
- API 境界: API 33+ の機微フラグによるプレビュー抑止、API 32 以下は自前トースト
- リーク: 監視の start/stop 後に発火しないこと、画面離脱で listener が解除されること

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

**iOS/macOS に clipboard サンプルは未実装**。Android が clipboard サンプルの初実装となる【計画判断】。UI 構成は iOS `ShareSampleView` のセクション構造を踏襲しつつ、Android 既存 `ShareSampleScreen` の Compose 実装規約を優先する。

### 2.2 再利用する既存コンポーネント

| コンポーネント | 出所 | 再利用方法 |
|---|---|---|
| 画面骨格（Back → タイトル → 結果表示 → `LazyColumn`） | `ShareSampleScreen.kt` | 同一構造を踏襲 |
| カテゴリ見出し + ボタン群 | `ShareSampleScreen.kt` | `item { Text(見出し) }` + `item { Button }` を踏襲 |
| `statusText` による結果表示（✅/❌/ℹ️） | `ShareSampleScreen.kt` | 同一パターン。clipboard 用に型別 helper を追加 |
| `cacheDir` へのサンプルファイル生成 | `ShareSampleScreen.kt`（`File(context.cacheDir, "share_sample.txt")` 等） | 同方式で URI コピー用ファイルを生成【レビュー反映】 |
| スクロールバー | `ShareSampleScreen.kt` の `ShareSampleScrollbar` | コピーせず再利用しない【計画判断】。private かつ Share 専用命名のため。clipboard は標準スクロールのみとし、必要なら implement 時に共通化を検討（要検証） |
| `MainMenuListItem`（Card） | `MainMenuScreen.kt` | private のため、`MainMenuScreen` にメニュー項目を1件追加する形で再利用 |
| テーマ | `ui/theme/` | 変更なし |

### 2.3 追加するコンポーネント

`ClipboardSampleScreen.kt`（新規）内の private helper:

- `clipboardErrorMessage(e: ClipboardDomainError): String` — 型別固定文言
- `formatReadResult(result: ClipReadResult?): String` — read 結果の可読整形
- `formatDescription(info: ClipDescriptionInfo?): String` — メタデータ整形
- `prepareSampleUri(context: Context): String`【レビュー反映】 — `cacheDir` に実ファイルを作り FileProvider で `content://` URI を生成

### 2.4 変更するファイルと変更理由

| ファイル | 変更理由 |
|---|---|
| `MainRouter.kt` | `MainScreen` enum に `CLIPBOARD_TEST` を追加、`when` 分岐と callback を追加 |
| `MainMenuScreen.kt` | `onSelectClipboardTest` パラメータとメニュー項目「Clipboard Example」を追加。`MainMenuPreview` も更新 |
| `app/build.gradle.kts`【レビュー反映】 | 監視を Manager 経由で確認するため `implementation(project(":unity_android_plugin"))` を追加 |

---

## 3. 実装方針

### 3.1 共通実装パターン: 維持する点

- メインメニュー → サンプル画面の導線（`MainRouter` の enum 分岐）
- 画面先頭に「← Back to Main」→ タイトル → 結果表示領域
- 機能カテゴリ単位のボタン群グルーピング（iOS `sectionView` 相当を見出し `Text` + `Button` 群で表現）
- 実行結果は ✅ / ❌ / ℹ️ で判別
- 公開 API 呼び出し前後に `Log.d`
- コールバック結果の UI 反映はメインスレッドで行う
- copy/read 系は `android_library` 直呼び（既存サンプル規約の維持）

### 3.2 共通実装パターン: 拡張する点

【計画判断】clipboard 固有の事情による拡張:

1. **エラー文言の型別 helper 化**: `ClipboardDomainError` は `message` が null になりうるため、`when (e)` による型別固定文言 helper を追加。
2. **「空は正常系」の明示表示**: `read()` / `getDescription()` の `null` は空クリップボードの正常系【実装済み】。❌ ではなく `ℹ️ Clipboard is empty (normal)` と表示する。
3. **API バージョン別の期待挙動を画面に明記**: 機微フラグは runtime API 33+ でのみ効果があるため注記テキストを置き、API 32 以下では自前 Toast を表示する。
4. **監視のみ Manager 経由**【レビュー反映】: copy/read は `android_library`、監視は `UnityAndroidClipboardManager`。画面上に「監視は Manager/Bridge 経由」と注記し、確認対象の層が異なることを明示する。
5. **シングルトン listener の解除**【レビュー反映】: `UnityAndroidClipboardManager` は `object` で listener を static 保持するため、`DisposableEffect` で `clearClipboardChangeListener()` + `clearClipboardOperationListener()` を必ず実行する。

### 3.3 呼び出し境界

- copy/read 入口: `ClipboardUseCases(activity)` を `remember(activity)` で生成
- 監視入口: `UnityAndroidClipboardManager`（object、直接参照）
- 戻り値: copy/clear は Unit（例外で失敗）、read/getDescription は nullable、hasClip は Boolean
- 例外: `ClipboardDomainError` を catch → 型別文言、その他 `Exception` は `❌ Unexpected: ...`
- 監視解除: `DisposableEffect(Unit) { onDispose { clearClipboardChangeListener(); clearClipboardOperationListener() } }`

---

## 4. 変更ファイル一覧

### 4.1 新規作成

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ClipboardSampleScreen.kt`

### 4.2 既存変更

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainRouter.kt`
- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainMenuScreen.kt`
- `android/AndroidLibraryExample/app/build.gradle.kts`【レビュー反映】

### 4.3 非変更（対象だが変更しない）

| ファイル | 理由 |
|---|---|
| `MainActivity.kt` | clipboard は権限不要・Intent 受信不要 |
| `AndroidManifest.xml`（app / android_library 双方） | クリップボードは権限宣言・Provider 追加が不要【実装済み】。URI コピーは既存の share FileProvider を流用するため追加宣言も不要 |
| `ShareSampleScreen.kt` / `NotificationSampleScreen.kt` | clipboard 追加による影響なし |
| `android_library` / `unity_android_plugin` 配下 | 本計画はサンプルアプリのみが対象。ライブラリ側の API 追加・可視性変更は行わない |
| `settings.gradle.kts` | `:unity_android_plugin` は既に include 済みのため変更不要 |
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
    ├── "Observe (via UnityAndroidClipboardManager)" セクション
    │   ├── [Text] 注記: 監視は Manager/Bridge 層経由。前面時のみ有効
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
| Copy URI【レビュー反映】 | `prepareSampleUri(context)` で実 URI 生成 → `copyUri(UriContent(uri = uri))` | `✅ copyUri called: {uri}` |
| Copy Multiple Text | `copyMultipleText(MultipleText(texts = listOf("first", "second", "third")))` | `✅ copyMultipleText called (3 items)` |
| Copy Sensitive Text | `copyPlainText(PlainText(text = "P@ssw0rd-sample", isSensitive = true))` + API 32 以下は Toast | `✅ copySensitive called (preview suppressed on API 33+)` |
| Read Clipboard | `read()` | 非 null: `✅ Read: {整形結果}` / null: `ℹ️ Clipboard is empty (normal)` |
| Has Clip | `hasClip()` | `✅ hasClip = true/false` |
| Get Description | `getDescription()` | 非 null: `✅ {label, mimeTypes, isStyledText, classificationStatus}` / null: `ℹ️ Clipboard is empty (normal)` |
| Clear Clipboard | `clear()` | `✅ clear called` |
| Start Observing【レビュー反映】 | `UnityAndroidClipboardManager.startObserving(context)` | `✅ observing started`、発火時 `ℹ️ Clipboard changed (n)` |
| Stop Observing【レビュー反映】 | `UnityAndroidClipboardManager.stopObserving()` | operation listener 経由で `✅ stopObserving` |
| Error Cases 各種 | 上記 copy API に不正値 | `❌ {型別文言}` |

### 5.3 URI コピー用の実 URI 生成【レビュー反映】

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

- authority 文字列はハードコードする【計画判断】。`android_library` の `SHARE_FILE_PROVIDER_AUTHORITY_SUFFIX` は `internal` で app モジュールから参照できないため。
- `android_library` の `native_toolkit_share_file_paths.xml` に `<cache-path name="cache" path="." />` があるため、`cacheDir` 配下は FileProvider で URI 化できる（確認済み）。
- FileProvider の `<provider>` 宣言は `android_library` の manifest から merge されるため、app 側の manifest 変更は不要。
- 他アプリでの貼り付けを確認する場合、URI 読み取り権限の付与はクリップボード経由では制約がある【実装済み: 企画書の要検証事項】。手動確認では「文字列としての URI が貼り付く」ことを主目的とし、実体参照の可否は要検証扱いとする。

### 5.4 監視の実装方針【レビュー反映】

```
起動時（LaunchedEffect または初期化時）:
  UnityAndroidClipboardManager.setClipboardOperationListener(operationListener)
  UnityAndroidClipboardManager.setClipboardChangeListener(changeListener)

changeListener.onClipboardChanged():
  changeCount++
  statusText = "ℹ️ Clipboard changed ($changeCount)"   // main スレッドで反映

operationListener.onClipboardOperation(op, ok, err):
  statusText = if (ok) "✅ $op" else "❌ $op: $err"      // main スレッドで反映

Start Observing ボタン:
  UnityAndroidClipboardManager.startObserving(context)

Stop Observing ボタン:
  UnityAndroidClipboardManager.stopObserving()

DisposableEffect(Unit) { onDispose {
  UnityAndroidClipboardManager.clearClipboardChangeListener()   // 監視停止 + listener 解除
  UnityAndroidClipboardManager.clearClipboardOperationListener()
}}
```

- Manager の KDoc は「callbacks are delivered on the main thread」としているが、`notifyClipboardChanged()` は system listener のコールバックスレッドで直接呼ばれる実装【実装済み】。Compose state 更新の安全性のため、実装時にスレッドを確認し、必要なら明示的に main へ post する（要検証）。
- 発火回数カウンタを持ち、stop 後に増えないことを目視確認できるようにする。

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
| 4 | URI コピー（実 URI）【レビュー反映】 | Copy URI → Read Clipboard | items に `content://...` URI が入る |
| 5 | URI の他アプリ貼り付け【レビュー反映】 | Copy URI → メモアプリで貼り付け | URI 文字列が貼り付く（実体参照可否は要検証） |
| 6 | 複数テキストコピー | Copy Multiple Text → Read Clipboard | items が3件 |
| 7 | 読み取り往復 | 各 copy → Read Clipboard | コピーした内容が読める |
| 8 | 空クリップボードの読み取り | Clear → Read / Get Description | ℹ️ 表示（❌ にならない） |
| 9 | hasClip | Copy → Has Clip / Clear → Has Clip | true / false |
| 10 | クリア | Copy → Clear → Has Clip | false |
| 11 | 機微フラグ（API 33+） | Copy Sensitive Text | システムのコピー確認 UI に内容が表示されない |
| 12 | コピー確認 UI 境界（API 32 以下） | Copy Sensitive Text | システム確認 UI が出ず、自前 Toast が表示される |
| 13 | 貼り付けアクセス通知（API 31+） | 他アプリでコピー → 本アプリで Read | 「クリップボードから貼り付けました」トーストが出る |
| 14 | 監視の発火（Manager 経由）【レビュー反映】 | Start Observing → 他アプリでコピー | ℹ️ Clipboard changed (n) が増える。Manager → Monitor 連携の確認になる |
| 15 | 監視の二重開始 no-op【レビュー反映】 | Start Observing を2回 → 他アプリでコピー | カウンタが1回分のみ増える |
| 16 | 監視停止・リーク防止 | Stop Observing → 他アプリでコピー | カウンタが増えず、✅ stopObserving が表示される |
| 17 | 画面離脱時の解除【レビュー反映】 | Start Observing → Back → 他アプリでコピー → 再入場 | listener 解除済みで二重発火しない |
| 18 | エラー: 空 HTML | Copy HTML (empty) | ❌ EmptyContent |
| 19 | エラー: 空リスト | Copy Multiple (empty list) | ❌ EmptyItemList |
| 20 | エラー: blank URI | Copy URI (blank) | ❌ InvalidUri |
| 21 | エラー: 未対応 scheme | Copy URI (http scheme) | ❌ InvalidUri |
| 22 | ログに本文が出ないこと | 各 copy 実行中に Logcat 確認 | 本文が出力されず length/scheme のみ（実装レビュー v2/v3 対応の確認） |

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
| 監視コールバックのスレッド | `UnityAndroidClipboardManager` の `notifyClipboardChanged()` は system listener のコールバックスレッドで直接呼ばれる。Compose state 更新の安全性を実機で確認し、必要なら main へ post する |
| クリップボード経由の URI 権限 | `content://` URI を他アプリが実体参照できるか（企画書の要検証事項と同じ）。手動確認 #5 の期待値を実機結果で確定する |
| unity plugin 依存追加の影響 | app モジュールに `:unity_android_plugin` を追加することで APK サイズ・ビルド時間・既存サンプル動作に影響がないかビルドで確認 |
| スクロールバーの要否 | clipboard の項目数（セクション6 + ボタン約17個）で標準スクロールに収まるか。収まらない場合は `ShareSampleScrollbar` 相当の共通化を検討 |
| iOS/macOS への横展開 | 現時点で clipboard サンプルは Android のみ。他 OS 実装時に本画面構成を主参照とするか要判断 |

---

## 8. 実行確認

- 提示文: 「この実装計画で進めますか？」
- 選択肢:
  - 承認する: 計画を確定、次のレビュー workflow（review-document）へ進む
  - 修正する: 指摘内容を反映して計画ファイルを更新
  - キャンセル: 計画ファイルは保持したまま終了
- ユーザー回答: 未回答
