# Android クリップボード サンプルアプリ 実装計画 v1

## 基本情報

- 作成日: 2026-07-25
- 機能名: clipboard
- 対象OS: Android（Android 12 / API 31 以降）
- 対象サンプルアプリ: `android/AndroidLibraryExample`
- 設計書: `artifact/designs/clipboard/2026-07-25-android-clipboard-design.md`（v4）
- 実装結果: `artifact/results/clipboard/2026-07-25-android-clipboard-implementation-feature-result-v3.md`
- 使用言語: Kotlin（Jetpack Compose）

設計書・実装結果由来の前提は「【実装済み】」、本計画での追加判断は「【計画判断】」として区別する。

---

## 1. 前提情報の抽出

### 1.1 in-scope 機能【実装済み】

サンプルアプリで確認対象とする、実装済みの公開機能:

- プレーンテキストのコピー
- HTML テキストのコピー
- URI（content:// / file://）のコピー
- 複数テキストのコピー（同一形式）
- クリップボードの読み取り（ペースト）
- クリップボードのデータ有無確認（`hasClip`）
- クリップボードのメタデータ取得（`getDescription`）
- クリップボードのクリア
- 機微情報フラグ付きコピー（`isSensitive`、Android 13+ でプレビュー抑止）
- クリップボード変更監視（開始/停止）

### 1.2 公開 API と入力制約【実装済み】

サンプルアプリはネイティブ層（`android_library`）を直接利用する。既存の `ShareSampleScreen` が `ShareUseCases(activity)` を直接呼ぶのと同じ方式。

`ClipboardUseCases(context)`（`android.library.clipboard.data.repository`）:

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

変更監視は UseCase suite に含まれない【実装済み】。Manager 層 `ClipboardChangeMonitor`（`unity_android_plugin`、`internal`）が system Listener を所有する。

**不足前提【計画判断】**: `ClipboardChangeMonitor` は `unity_android_plugin` モジュールの `internal` クラスであり、サンプルアプリ（`app` モジュール）からは直接参照できない。サンプルアプリで変更監視を確認するには、`android.content.ClipboardManager.addPrimaryClipChangedListener` を画面内で直接使う必要がある。これは「ライブラリ API の確認」ではなく「監視の挙動確認」に留まる点を画面上に明記する。設計書側の API 追加は本計画では行わない（勝手な要件追加をしない）。

### 1.3 エラー契約【実装済み】

サンプルアプリはネイティブ層を直接呼ぶため、Bridge の `errorMessage` 文字列ではなく `ClipboardDomainError` を直接 catch する（既存 `ShareSampleScreen` が `ShareDomainError` を catch するのと同じ方式）。

| DomainError | サンプル表示文言（計画） | 発生条件 |
|---|---|---|
| `EmptyContent` | `❌ EmptyContent: HTML body is empty` | `copyHtmlText` で `htmlText` が空 |
| `EmptyItemList` | `❌ EmptyItemList: no items to copy` | `copyMultipleText` で空リスト |
| `InvalidUri` | `❌ InvalidUri: {uri}` | `copyUri` で blank / 未対応 scheme |
| `ClipboardUnavailable` | `❌ ClipboardUnavailable` | クリップボードサービス取得失敗 |
| `ReadNotAllowed` | `❌ ReadNotAllowed: app must be in foreground` | `read()` 中に `SecurityException` |

`ClipboardDomainError` は `data object` / `data class` のため `e.message` が null になりうる【計画判断】。既存 `ShareSampleScreen` は `"❌ ${e.message}"` 形式だが、clipboard では `when (e)` で型ごとに固定文言を出す helper を用意する（下記 3.2）。

### 1.4 テスト観点【実装済み】

設計書のテスト設計・手動確認項目から、サンプルアプリで確認すべき観点:

- 正常系: 各 copy → 他アプリ（メモ等）へ貼り付け成功、read で往復確認
- 異常系: 空 HTML / 空リスト / 不正 URI scheme のエラー表示
- 境界値: 空文字コピー（許容）、空クリップボードの read/getDescription が `null`（正常系でありエラーではない）
- API 境界: API 33+ で機微フラグによるコピー確認 UI のプレビュー抑止、API 32 以下では自前トースト
- リーク: 変更監視の start/stop 後に発火しないこと

---

## 2. 既存サンプルコードの深掘り結果

### 2.1 確認した既存コード

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/`
  - `MainRouter.kt`: `MainScreen` enum + `when` による画面遷移、`BackHandler` で戻る
  - `MainMenuScreen.kt`: `LazyColumn` + `MainMenuListItem`（Card）でメニュー
  - `ShareSampleScreen.kt`（775行）: 本機能の主参照。`ShareUseCases` 直接呼び出し、`statusText` 状態、カテゴリ別 `item { Text(...) }` 見出し + `Button` 群、独自スクロールバー
  - `NotificationSampleScreen.kt`: 権限チェック helper パターン
- 主参照ペア（モバイル）: `ios/IosLibraryExample/IosLibraryExample/`
  - `ContentView.swift`: `NavigationStack` + `menuCard` でメインメニュー
  - `ShareSampleView.swift`: `sectionView(title:)` によるカテゴリ別グルーピング、`updateResult(isSuccess:result:)` で ✅/❌ 統一

**iOS/macOS に clipboard サンプルは未実装**（`find` で該当なし）。したがって Android が clipboard サンプルの初実装となる【計画判断】。UI 構成は iOS `ShareSampleView` のセクション構造を踏襲しつつ、Android 既存の `ShareSampleScreen` の Compose 実装規約を優先する。

### 2.2 再利用する既存コンポーネント

| コンポーネント | 出所 | 再利用方法 |
|---|---|---|
| 画面骨格（Back ボタン → タイトル → 結果表示 → `LazyColumn`） | `ShareSampleScreen.kt` | 同一構造をそのまま踏襲 |
| カテゴリ見出し + ボタン群パターン | `ShareSampleScreen.kt` | `item { Text(見出し) }` + `item { Button }` 形式を踏襲 |
| `statusText` による結果表示（✅/❌/ℹ️） | `ShareSampleScreen.kt` | 同一パターン。clipboard 用に型別 helper を追加 |
| スクロールバー | `ShareSampleScreen.kt` の `ShareSampleScrollbar` | **コピーせず再利用しない**【計画判断】。private かつ Share 専用命名のため、Clipboard 側に同等の private 実装を置くと重複が増える。clipboard は項目数が Share より少ない見込みのため、標準スクロールのみとし、必要なら implement 時に共通化を検討（要検証） |
| `MainMenuListItem`（Card） | `MainMenuScreen.kt` | private のため、`MainMenuScreen` にメニュー項目を1件追加する形で再利用 |
| テーマ | `ui/theme/` | 変更なし |

### 2.3 追加するコンポーネント

- `ClipboardSampleScreen.kt`（新規）: clipboard 機能の全操作を確認する画面
  - private helper: `clipboardErrorMessage(e: ClipboardDomainError): String`（型別固定文言）
  - private helper: `formatReadResult(result: ClipReadResult?): String`（read 結果の可読整形）
  - private helper: `formatDescription(info: ClipDescriptionInfo?): String`

### 2.4 変更するファイルと変更理由

| ファイル | 変更理由 |
|---|---|
| `MainRouter.kt` | `MainScreen` enum に `CLIPBOARD_TEST` を追加し、`when` 分岐と `MainMenuScreen` への callback を追加 |
| `MainMenuScreen.kt` | `onSelectClipboardTest` パラメータとメニュー項目「Clipboard Example」を追加。`MainMenuPreview` も更新 |

---

## 3. 実装方針

### 3.1 共通実装パターン: 維持する点

Android ⇔ iOS 共通パターンのうち、以下はそのまま維持する:

- メインメニュー → サンプル画面の導線（`MainRouter` の enum 分岐）
- 画面先頭に「← Back to Main」ボタン → タイトル → 結果表示領域
- 機能カテゴリ単位のボタン群グルーピング（iOS `sectionView` 相当を Compose の見出し `Text` + `Button` 群で表現）
- 実行結果は ✅ / ❌ / ℹ️ で成功・失敗・情報を一目で判別
- 公開 API 呼び出し前後に `Log.d` を残し再現手順を追える
- コールバック結果の UI 反映はメインスレッドで行う

### 3.2 共通実装パターン: 拡張する点

【計画判断】clipboard 固有の事情による拡張:

1. **エラー文言の型別 helper 化**: 既存 Share は `"❌ ${e.message}"` だが、`ClipboardDomainError` は `data object`/`data class` で `message` が null になりうる。`when (e)` による型別固定文言 helper を追加する。
2. **「空は正常系」の明示表示**: `read()` / `getDescription()` が `null` を返すのは空クリップボードの正常系【実装済み】。誤って ❌ 表示しないよう、`null` は `ℹ️ Clipboard is empty (normal)` として表示する。
3. **API バージョン別の期待挙動を画面に明記**: 機微フラグは runtime API 33+ でのみ効果があるため、ボタン近傍に注記テキストを置き、API 32 以下では自前 Toast を表示する（設計書の手動確認項目に対応）。
4. **変更監視のスコープ注記**: 2.2 の不足前提のとおり、監視は `unity_android_plugin` の `internal` クラスで提供されるためサンプルからは直接呼べない。サンプル画面では `ClipboardManager` を直接使った監視デモとし、その旨を注記する。

### 3.3 呼び出し境界

- 入口: `ClipboardUseCases(activity)` を `remember(activity)` で生成（`ShareSampleScreen` の `ShareUseCases(activity)` と同一方式）
- 戻り値: 同期呼び出し。`copy`/`clear` は Unit（例外で失敗）、`read`/`getDescription` は nullable、`hasClip` は Boolean
- 例外: `ClipboardDomainError` を catch → 型別文言、その他 `Exception` は `❌ Unexpected: ...`
- 監視: `DisposableEffect` で `addPrimaryClipChangedListener` / `removePrimaryClipChangedListener` を対にし、画面離脱時に確実解除（リーク防止）

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
| `MainActivity.kt` | clipboard は権限不要・Intent 受信不要のため Activity 側の変更は発生しない |
| `AndroidManifest.xml`（app / android_library 双方） | クリップボードは権限宣言・Provider 追加が不要【実装済み】 |
| `ShareSampleScreen.kt` / `NotificationSampleScreen.kt` | clipboard 追加による影響なし。既存画面には手を入れない |
| `android_library` / `unity_android_plugin` 配下 | 本計画はサンプルアプリのみが対象。ライブラリ側の API 追加は行わない |
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
    │   ├── [Button] Copy URI (content://)
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
    │   ├── [Text] 注記: サンプル内で ClipboardManager を直接使用
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
| Copy Plain Text (empty) | `copyPlainText(PlainText(text = ""))` | `✅ copyPlainText (empty) called`（空は許容） |
| Copy HTML Text | `copyHtmlText(HtmlText(plainText = "Hello", htmlText = "<b>Hello</b>"))` | `✅ copyHtmlText called` |
| Copy URI | `copyUri(UriContent(uri = "content://<pkg>.native_toolkit.share.fileprovider/sample"))` | `✅ copyUri called` |
| Copy Multiple Text | `copyMultipleText(MultipleText(texts = listOf("first", "second", "third")))` | `✅ copyMultipleText called (3 items)` |
| Copy Sensitive Text | `copyPlainText(PlainText(text = "P@ssw0rd-sample", isSensitive = true))` + API 32 以下は Toast | `✅ copySensitive called (preview suppressed on API 33+)` |
| Read Clipboard | `read()` | 非 null: `✅ Read: {整形結果}` / null: `ℹ️ Clipboard is empty (normal)` |
| Has Clip | `hasClip()` | `✅ hasClip = true/false` |
| Get Description | `getDescription()` | 非 null: `✅ {label, mimeTypes, isStyledText, classificationStatus}` / null: `ℹ️ Clipboard is empty (normal)` |
| Clear Clipboard | `clear()` | `✅ clear called` |
| Start/Stop Observing | `ClipboardManager.add/removePrimaryClipChangedListener` | `✅ observing started/stopped`、発火時 `ℹ️ Clipboard changed (n)` |
| Error Cases 各種 | 上記 copy API に不正値 | `❌ {型別文言}` |

### 5.3 コールバック処理方法

- clipboard の copy/read 系は**同期呼び出し**のため、コールバックは変更監視のみ。
- 変更監視リスナーは system 側から呼ばれるため、`statusText` 更新はメインスレッドで行う（Compose の state 更新は main 前提。リスナーが main で呼ばれる想定だが、確実性のため実装時に確認する — 要検証）。
- 発火回数カウンタを持ち、`ℹ️ Clipboard changed (n)` と表示して stop 後に増えないことを目視確認できるようにする。
- `DisposableEffect(Unit) { onDispose { removePrimaryClipChangedListener(...) } }` で画面離脱時に必ず解除する。

### 5.4 入力バリデーション方針

- サンプルは固定値のため UI 側バリデーションは行わない。
- 「Error Cases」セクションで意図的に不正値を渡し、**ライブラリ側の検証（`ClipboardDomainError`）が正しく発火することを確認する**のが目的。
- したがってサンプル側で事前チェックして呼び出しを抑止することはしない（ライブラリの検証を殺さない）。

---

## 6. 手動確認観点

| # | 観点 | 手順 | 期待結果 |
|---|---|---|---|
| 1 | プレーンテキストのコピー | Copy Plain Text → メモアプリで貼り付け | 文字列が貼り付けられる |
| 2 | 空文字コピー（境界値） | Copy Plain Text (empty) | ✅ 表示、例外にならない |
| 3 | HTML コピー | Copy HTML Text → HTML 対応アプリで貼り付け | 書式付きで貼り付く（対応アプリのみ） |
| 4 | URI コピー | Copy URI → Read Clipboard | items に uri が入る |
| 5 | 複数テキストコピー | Copy Multiple Text → Read Clipboard | items が3件 |
| 6 | 読み取り往復 | 各 copy → Read Clipboard | コピーした内容が読める |
| 7 | 空クリップボードの読み取り | Clear → Read / Get Description | ℹ️ 表示（❌ にならない） |
| 8 | hasClip | Copy → Has Clip / Clear → Has Clip | true / false |
| 9 | クリア | Copy → Clear → Has Clip | false |
| 10 | 機微フラグ（API 33+） | Copy Sensitive Text | システムのコピー確認 UI に内容が表示されない |
| 11 | コピー確認 UI 境界（API 32 以下） | Copy Sensitive Text | システム確認 UI が出ず、自前 Toast が表示される |
| 12 | 貼り付けアクセス通知（API 31+） | 他アプリでコピー → 本アプリで Read | 「クリップボードから貼り付けました」トーストが出る |
| 13 | 変更監視の発火 | Start Observing → 他アプリでコピー | ℹ️ Clipboard changed (n) が増える |
| 14 | 監視停止・リーク防止 | Stop Observing → 他アプリでコピー | カウンタが増えない |
| 15 | 画面離脱時の解除 | Start Observing → Back → 再入場 | 二重発火しない |
| 16 | エラー: 空 HTML | Copy HTML (empty) | ❌ EmptyContent |
| 17 | エラー: 空リスト | Copy Multiple (empty list) | ❌ EmptyItemList |
| 18 | エラー: blank URI | Copy URI (blank) | ❌ InvalidUri |
| 19 | エラー: 未対応 scheme | Copy URI (http scheme) | ❌ InvalidUri |
| 20 | ログに本文が出ないこと | 各 copy 実行中に Logcat 確認 | 本文が出力されず length/scheme のみ（実装レビュー v2/v3 対応の確認） |

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
| 変更監視リスナーのスレッド | `OnPrimaryClipChangedListener` が main で呼ばれるか実機確認。異なる場合は明示的に main へ post する |
| URI コピーの実 URI | サンプル用 `content://` URI をどう用意するか（FileProvider 経由の実ファイル生成が必要か、ダミー文字列で足りるか）を実装時に確認 |
| スクロールバーの要否 | clipboard の項目数で標準スクロールに収まるか。収まらない場合は `ShareSampleScrollbar` 相当の共通化を検討 |
| iOS/macOS への横展開 | 現時点で clipboard サンプルは Android のみ。他 OS 実装時に本画面構成を主参照とするか要判断 |

---

## 8. 実行確認

- 提示文: 「この実装計画で進めますか？」
- 選択肢:
  - 承認する: 計画を確定、次のレビュー workflow（review-document）へ進む
  - 修正する: 指摘内容を反映して計画ファイルを更新
  - キャンセル: 計画ファイルは保持したまま終了
- ユーザー回答: 未回答
