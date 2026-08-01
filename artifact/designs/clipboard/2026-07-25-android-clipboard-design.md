# Android クリップボード機能 実装設計書

- 作成日: 2026-07-25
- 改訂日: 2026-07-25（v2: Intent を Out of scope 化・system Listener を Manager 層へ集約 / v3: 空 read を null 正常系に統一・監視テストを Monitor 側へ分離・compileSdk 35 明記 / v4: ReadNotAllowed の判定条件を SecurityException 限定に明文化 / v5: ClipboardChangeMonitor を android_library の presentation 層へ移動し、native からの監視利用を可能に）
- 対象OS: Android（Android 12 / API 31 以降）
- 対象機能: クリップボード（Clipboard: コピー / ペースト / 監視）
- 使用言語: Kotlin

---

## 対象企画書

- artifact/plans/clipboard/2026-07-25-android-clipboard-research.md（v5）

企画書由来の前提と本設計での新規判断は、各セクションで「【企画書由来】」「【設計判断】」として分離する。

---

## 設計目的

企画書で全網羅した Android クリップボード API を、既存 native-toolkit の Clean Architecture（`android_library` = Domain/Application/Data/Presentation、`unity_android_plugin` = Unity Bridge）に厳密準拠する形で組み込み、実装着手可能な粒度まで分解する。既存の `share` / `notification` モジュールの構成・命名・エラー変換方式を踏襲する。

---

## スコープ（in / out）

### In scope 【企画書由来】

- プレーンテキストのコピー / ペースト
- HTML テキストのコピー / ペースト
- URI（content://、画像・ファイル参照を含む）のコピー / ペースト
- 複数 Item のコピー（同一形式）
- クリップボード内容確認（`hasPrimaryClip` / `ClipDescription`）
- クリップボードのクリア（`clearPrimaryClip`）
- クリップボード変更監視（`OnPrimaryClipChangedListener`）
- 機微情報フラグ（`EXTRA_IS_SENSITIVE`、Android 13+）
- スタイル付きテキスト判定・分類ステータス

### Out of scope 【設計判断】

- iOS / macOS / Windows 実装（本設計は Android のみ）
- Intent のコピー / ペースト（`android.content.Intent` は Android の複合プラットフォーム型で、Domain/Application 層へ持ち込むと common.md の「Port はドメイン型のみ」に反する。Unity C# 側でも消費不可。ドメイン型化してまで提供する需要が薄いため、本機能セットから除外する。将来必要になれば直列化可能なドメイン型 `IntentClipData` を定義して再設計する）
- 画像のデコード・実体化（`content://` URI を返すところまで。読み込みはアプリ側 `ContentResolver.openInputStream`）
- テキスト分類詳細（`getTextLinks` / `getConfidenceScore` の entity 抽出）の Bridge 公開（ネイティブ層に判定 API のみ用意、詳細抽出は対象外）
- API 35+ の `ClipData.Item.Builder` / `getIntentSender()`（企画書で対象外確定）
- サンプルアプリ実装（`design-sample-app` で別途）
- `docs/` 配下（固定で変更対象外）

---

## 共通実装方針の適用チェック（common.md 準拠）

| 方針 | 適用 | 本設計での反映 |
|---|---|---|
| Clean Architecture 層・依存方向 | ○ | `clipboard/{domain,application,data}` を新設。Domain は `android.*` 非依存 |
| Port はドメイン型のみ | ○ | `ClipboardRepository` の引数・戻り値はドメイン型（`ClipContent` / `ClipReadResult` 等）のみ。`ClipData` / `Uri` は Data 層に閉じる |
| Manager は UseCase 経由 | ○ | `UnityAndroidClipboardManager` は `ClipboardUseCases` 経由で Data にアクセス。Repository 直呼び禁止 |
| UseCase は 1 操作 1 クラス + `invoke` | ○ | `CopyPlainTextUseCase` 等、各操作を分離 |
| Delegate/Listener は Manager 層が所有 | ○ | 変更監視の system `OnPrimaryClipChangedListener` は `ClipboardChangeMonitor` が 1 クラスで所有・登録・解除。RepositoryImpl は Listener を持たない。【v5】common.md「Unity Bridge 専用クラスにも Delegate を実装しない（native など別用途での利用ができなくなるため）」に従い、本クラスは **`android_library` の presentation 層**に配置し、Unity Bridge は委譲のみ行う |
| TDD（UseCase 単位、Mock は Port 実装） | ○ | `MockClipboardRepository` を Port 実装として DI |
| エラー変換（System → DomainError → Bridge 文字列） | ○ | RepositoryImpl で `ClipboardDomainError` に変換、Manager で `errorMessage` 化 |
| callback 版 + ネイティブ版の併設 | ○ | Manager に Listener 版（Bridge）を用意。UseCase は例外送出のネイティブ版として利用可能 |
| Unity Bridge は薄く | ○ | Manager は JSON 解析 → UseCase 呼び出し → Listener 通知のみ |
| 最小 OS: Android 12 | ○ | 全 API が API 31 で利用可。`clearPrimaryClip`(API 28) 問題なし |

## 個別実装方針の適用チェック（android.md 準拠）

| 方針 | 適用 | 反映 |
|---|---|---|
| 全メソッド先頭に全パラメータ `Log.d` | ○ | `override fun` / `operator fun invoke` / public・internal fun / `onPrimaryClipChanged` に付与。TAG はフルクラス名 |
| エラーは `Log.e` | ○ | Manager の失敗通知で `Log.e` |
| public 要素に KDoc | ○ | public Repository/UseCase/model/Manager に付与 |
| private/override は KDoc 除外 | ○ | 準拠 |

---

## 既存実装差分サマリー

- 新規モジュール `clipboard` を `android_library` と `unity_android_plugin` に追加する。既存モジュール（notification / share / dialog）への **破壊的変更はなし**。
- `AndroidManifest.xml` の変更は **不要**（クリップボードは権限不要、FileProvider 追加も不要）。
- 既存 `share` の `ClipData.newUri` 利用実績があり、URI コピーの実装参照が可能。
- 命名規約: パッケージ `android.library.clipboard.*` / `android.unity.clipboard.*`。クラス名は既存 `Share*` に倣い `Clipboard*` プレフィックス。

### 追加ファイル一覧（具体パス）

android_library（コア）:

```
android/android_library/src/main/java/android/library/clipboard/
├── domain/
│   ├── error/ClipboardDomainError.kt
│   └── model/
│       ├── ClipContent.kt          # コピー入力（sealed）
│       ├── ClipItemData.kt         # ペースト item（フラット・直列化可能）
│       ├── ClipReadResult.kt       # ペースト結果
│       └── ClipDescriptionInfo.kt  # メタデータ
├── application/
│   ├── port/ClipboardRepository.kt
│   └── usecase/
│       ├── CopyPlainTextUseCase.kt
│       ├── CopyHtmlTextUseCase.kt
│       ├── CopyUriUseCase.kt
│       ├── CopyMultipleTextUseCase.kt
│       ├── ReadClipboardUseCase.kt     # ペースト（全体）
│       ├── HasClipUseCase.kt
│       ├── GetClipDescriptionUseCase.kt
│       ├── ClearClipboardUseCase.kt
│       └── ClipboardUseCases.kt        # suite
├── data/repository/
│   ├── ClipboardRepositoryImpl.kt
│   ├── ClipboardMappers.kt             # ClipData ↔ ドメイン型 変換
│   └── ClipboardUseCases.kt            # factory
└── presentation/
    └── ClipboardChangeMonitor.kt       # 【v5】OnPrimaryClipChangedListener 所有（native 公開）
```

unity_android_plugin（Unity Bridge）:

```
android/unity_android_plugin/src/main/java/android/unity/clipboard/
├── UnityAndroidClipboardManager.kt    # 監視は ClipboardChangeMonitor へ委譲（listener を持たない）
├── UnityClipboardJsonParser.kt
└── UnityClipboardSpecs.kt
```

テスト:

```
# コア（android_library）
android/android_library/src/test/java/android/library/clipboard/
└── application/ClipboardUseCasesTest.kt

android/android_library/src/androidTest/java/android/library/clipboard/
├── data/ClipboardRepositoryImplTest.kt
└── presentation/ClipboardChangeMonitorTest.kt   # 【v5】unity plugin から移動

# Unity plugin（unity_android_plugin）: Parser / Manager
android/unity_android_plugin/src/test/java/android/unity/clipboard/
├── UnityClipboardJsonParserTest.kt
└── UnityAndroidClipboardManagerTest.kt
```

---

## 実装アーキテクチャ

```
Unity C#
  │ JSON in / Listener out（copy 系）, JSON return（read/has/description 系）
  ▼
UnityAndroidClipboardManager (object)          … Unity Bridge
  │ copy/read/clear は UseCase 呼び出し（Repository 直呼び禁止）
  │ 監視は ClipboardChangeMonitor へ委譲（自身は system listener を持たない）
  ▼
ClipboardUseCases                              … Application
  │
  ▼
ClipboardRepository (port, ドメイン型のみ)      … Application
  ▲ 実装
ClipboardRepositoryImpl                        … Data（copy/read/hasClip/getDescription/clear のみ）
  ├─ ClipboardManager(system) アクセス
  └─ ClipboardMappers（ClipData ↔ domain）

ClipboardChangeMonitor                         … Presentation（android_library）
  └─ system OnPrimaryClipChangedListener を単独所有
     native サンプル / 他 native 呼び出し元 / Unity Bridge の共通利用先
```

【v5】監視クラスの配置根拠: common.md は「システム Delegate / Listener は 1 クラスのみが所有」「Unity Bridge 専用クラスにも Delegate を実装しない（native など別用途での利用ができなくなるため）」と定める。v4 までは `unity_android_plugin`（Unity Bridge 専用モジュール）に置いていたため、native サンプルなど非 Unity の呼び出し元から監視機能を利用できなかった。iOS が `IosLibrary/.../IosShareManager.swift`（native）と `UnityIosPlugin/.../UnityIosShareManager.swift`（Bridge）の 2 層に分けている前例に合わせ、`android_library` の presentation 層へ移動する。

- **copy/clear 系**: 副作用のみ。結果は `ClipboardOperationListener.onClipboardOperation(op, ok, err)` で通知（share 準拠）。
- **read/has/description 系**: 同期読み取り。Manager の JNI 関数が JSON 文字列を戻り値で返す【設計判断】（クリップボード読み取りは同期・前面前提のため、Listener 往復より戻り値が自然）。
- **監視系**: `ClipboardChangeListener.onClipboardChanged()` を Unity へ通知。

---

## サブ機能別詳細設計

### 共通: ドメインモデル

```kotlin
// domain/model/ClipContent.kt
/** クリップボードへ書き込むコンテンツ。 */
sealed class ClipContent {
    /** 機微情報プレビュー抑止フラグ（Android 13+ の表示ヒント）。 */
    abstract val isSensitive: Boolean
    abstract val label: String

    data class PlainText(val text: String, override val label: String = "", override val isSensitive: Boolean = false) : ClipContent()
    data class HtmlText(val plainText: String, val htmlText: String, override val label: String = "", override val isSensitive: Boolean = false) : ClipContent()
    data class UriContent(val uri: String, override val label: String = "", override val isSensitive: Boolean = false) : ClipContent()
    data class MultipleText(val texts: List<String>, override val label: String = "", override val isSensitive: Boolean = false) : ClipContent()
}
```

```kotlin
// domain/model/ClipItemData.kt … ペースト item（直列化可能なフラット表現）
data class ClipItemData(
    val text: String? = null,
    val htmlText: String? = null,
    val uri: String? = null,
    val coercedText: String? = null
)

// domain/model/ClipReadResult.kt
data class ClipReadResult(
    val label: String?,
    val mimeTypes: List<String>,
    val items: List<ClipItemData>
)

// domain/model/ClipDescriptionInfo.kt
data class ClipDescriptionInfo(
    val label: String?,
    val mimeTypes: List<String>,
    val isStyledText: Boolean,
    val classificationStatus: Int?   // API 31: CLASSIFICATION_* 値。取得不可時 null
)
```

- Intent コピー / ペーストは Out of scope（`android.content.Intent` を Domain/Application 層に持ち込まないため）。`ClipContent` は Text/Html/Uri/MultipleText の 4 種のみ。

### 1. プレーンテキストのコピー

- 変更対象: `CopyPlainTextUseCase`, `ClipboardRepositoryImpl`, `ClipboardMappers`
- API: `ClipData.newPlainText(label, text)` + `setPrimaryClip`
- 制御フロー: UseCase が入力検証 → `repository.copy(ClipContent.PlainText)`
- 検証: `text` は空文字許容（クリア用途と区別しないため空許容だが、`MultipleText` の空リストは不可）。【設計判断】空文字コピーは許容
- 機微フラグ: `isSensitive` 時 `description.extras` に `ClipDescription.EXTRA_IS_SENSITIVE` を設定（runtime API 33+ のみ効果）。**現行プロジェクトは compileSdk 35** のため定数を直接参照する（生キー分岐は不要）

### 2. HTML テキストのコピー

- 変更対象: `CopyHtmlTextUseCase`, RepositoryImpl
- API: `ClipData.newHtmlText(label, plainText, htmlText)`（API 16）
- 検証: `htmlText` が空なら `ClipboardDomainError.EmptyContent`

### 3. URI（画像・ファイル）のコピー / ペースト

- 変更対象: `CopyUriUseCase`, RepositoryImpl, Mappers
- コピー API: `ClipData.newUri(contentResolver, label, Uri.parse(uri))`
- 検証: `uri` blank / パース失敗 → `ClipboardDomainError.InvalidUri`
- ペースト: `ReadClipboardUseCase` 経由で `ClipItemData.uri` を返す。画像実体化はアプリ側【企画書由来: 責務境界】

### 4. 複数 Item のコピー（同一形式テキスト）

- 変更対象: `CopyMultipleTextUseCase`, RepositoryImpl
- API: `newPlainText` + `addItem(ClipData.Item(text))`
- 検証: 空リスト → `ClipboardDomainError.EmptyItemList`
- 【企画書由来】異種形式混在は不可（テキストのみ）

### 5. 内容確認 / メタデータ

- 変更対象: `HasClipUseCase`, `GetClipDescriptionUseCase`, RepositoryImpl, Mappers
- API: `hasPrimaryClip()`, `getPrimaryClipDescription()`（本体に触れずアクセス通知回避）
- `ClipDescriptionInfo` に `isStyledText`(API 31)・`classificationStatus`(API 31) を格納
- `getConfidenceScore` は詳細抽出のため Bridge 非公開（判定は `classificationStatus` のみ提供）

### 6. クリップボードのクリア

- 変更対象: `ClearClipboardUseCase`, RepositoryImpl
- API: `clearPrimaryClip()`（API 28、最小 31 で利用可）
- 機微情報コピー後のセキュリティ用途を想定

### 7. クリップボード変更監視

- 変更対象: `ClipboardChangeMonitor`（**android_library / presentation 層**）, `UnityAndroidClipboardManager`（委譲のみ）
- API: `addPrimaryClipChangedListener` / `removePrimaryClipChangedListener`
- 【v5】system `OnPrimaryClipChangedListener` の所有・登録・解除は `android/android_library/src/main/java/android/library/clipboard/presentation/ClipboardChangeMonitor.kt` が 1 クラスで担う（public）。native サンプルを含む非 Unity の呼び出し元からも直接利用できる
- 公開シグネチャ: `start(context: Context, onChange: () -> Unit)` / `stop()` / `isObserving(): Boolean`
- RepositoryImpl / Data 層は copy / read / hasClip / getDescription / clear のみを担い、Listener を保持しない（監視は UseCase / Port を経由しない）
- 二重登録は `start` 内で no-op として吸収。`onChange` は system listener のコールバックスレッドで呼ばれるため、UI 更新する呼び出し元がメインスレッドへの marshal を行う（KDoc に明記）
- `UnityAndroidClipboardManager` は自身の system listener を持たず、`ClipboardChangeMonitor` に委譲したうえで Unity 向け `ClipboardChangeListener` へ転送する
- 【企画書由来リスク】Android 10+ のバックグラウンド読み取り制限のため、監視は前面時のみ有効。KDoc に明記
- リーク防止: `stopObserving` / `clearClipboardChangeListener` で `removePrimaryClipChangedListener` を確実に実行

### 8. 機微情報フラグ

- 全 copy 系 UseCase の `isSensitive` で共通適用（Mappers に `applySensitiveFlag(ClipData, Boolean)` を実装、`ClipDescription.EXTRA_IS_SENSITIVE` 定数直参照）
- 【企画書由来】runtime Android 13+ のみ効果・表示ヒント（追加セキュリティではない）を KDoc 明記
- 【レビュー反映】compileSdk 35 のため定数を直接参照し、生キー分岐は実装しない

---

## API 設計（公開 / 内部）

### Port（`ClipboardRepository`、ドメイン型のみ）

```kotlin
interface ClipboardRepository {
    /** [content] をクリップボードへ書き込む（PlainText/HtmlText/UriContent/MultipleText）。 */
    fun copy(content: ClipContent)
    /** クリップボード内容を読む。空なら null。 */
    fun read(): ClipReadResult?
    /** データ有無を返す。 */
    fun hasClip(): Boolean
    /** メタデータのみ取得（本体に触れない）。空なら null。 */
    fun getDescription(): ClipDescriptionInfo?
    /** クリップボードを空にする。 */
    fun clear()
}
```

- 【レビュー反映 / v5】変更監視（`OnPrimaryClipChangedListener` の登録/解除）は Port に含めない。system Listener の所有は `android_library` presentation 層の `ClipboardChangeMonitor` に集約し、Data 層は同期的な read/write/metadata/clear のみを担う（common.md 準拠）。

### Application（`ClipboardUseCases` suite）

```kotlin
class ClipboardUseCases(repository: ClipboardRepository) {
    val copyPlainText = CopyPlainTextUseCase(repository)
    val copyHtmlText = CopyHtmlTextUseCase(repository)
    val copyUri = CopyUriUseCase(repository)
    val copyMultipleText = CopyMultipleTextUseCase(repository)
    val read = ReadClipboardUseCase(repository)
    val hasClip = HasClipUseCase(repository)
    val getDescription = GetClipDescriptionUseCase(repository)
    val clear = ClearClipboardUseCase(repository)
}
// 変更監視は UseCase suite に含めない（Manager 層の ClipboardChangeMonitor が担う）。
// factory: fun ClipboardUseCases(context: Context): ClipboardUseCases
```

UseCase 例（検証を含む）:

```kotlin
class CopyMultipleTextUseCase(private val repository: ClipboardRepository) {
    operator fun invoke(content: ClipContent.MultipleText) {
        Log.d(TAG, "[invoke] content: $content")
        if (content.texts.isEmpty()) throw ClipboardDomainError.EmptyItemList
        repository.copy(content)
    }
    companion object { private const val TAG = "CopyMultipleTextUseCase" }
}
```

### Bridge（`UnityAndroidClipboardManager`、public 関数）

| 関数 | 入力 | 出力 | 種別 |
|---|---|---|---|
| `copyPlainText(ctx, json)` | `{text,label,isSensitive}` | Listener | copy |
| `copyHtmlText(ctx, json)` | `{plainText,htmlText,label,isSensitive}` | Listener | copy |
| `copyUri(ctx, json)` | `{uri,label,isSensitive}` | Listener | copy |
| `copyMultipleText(ctx, json)` | `{texts:[...],label,isSensitive}` | Listener | copy |
| `read(ctx)` | なし | JSON `ClipReadResult`（空は `"null"`） | read（同期戻り値） |
| `hasClip(ctx)` | なし | `"true"`/`"false"` | read |
| `getDescription(ctx)` | なし | JSON `ClipDescriptionInfo`（空は `"null"`） | read |
| `clear(ctx)` | なし | Listener | copy |
| `startObserving(ctx)` | なし | 以後 `onClipboardChanged` | observe |
| `stopObserving(ctx)` | なし | Listener | observe |
| `setClipboardOperationListener(l)` | listener | - | 登録 |
| `setClipboardChangeListener(l)` | listener | - | 登録 |
| `clearClipboardChangeListener()` | なし | listener 解除・監視停止 | 解除 |

- Intent copy/paste は本機能セットから除外（Out of scope）。Bridge にも公開しない。
- `startObserving` / `stopObserving` / change listener 系は `android_library` presentation 層の `ClipboardChangeMonitor` が処理し、UseCase / Port を経由しない。Bridge は委譲のみ。

---

## ドメインエラー一覧（全ケース）

```kotlin
sealed class ClipboardDomainError : Exception() {
    /** コピー対象の内容が空（HTML本文・必須テキストが空）。 */
    data object EmptyContent : ClipboardDomainError()
    /** 複数コピーの item リストが空。 */
    data object EmptyItemList : ClipboardDomainError()
    /** URI が空、またはパース不能。 */
    data class InvalidUri(val uri: String) : ClipboardDomainError()
    /** ClipboardManager をシステムから取得できない。 */
    data object ClipboardUnavailable : ClipboardDomainError()
    /**
     * 読み取りが明示的に拒否された（システムが SecurityException を送出）。
     * 単なる null（空クリップボード / バックグラウンド制限による黙示の null）はこのエラーにせず、空の正常系として扱う。
     */
    data object ReadNotAllowed : ClipboardDomainError()
}
```

- 【レビュー反映】変更監視の二重登録は `ClipboardChangeMonitor` が内部で **no-op** として吸収する（DomainError にも errorMessage にも出さない）。監視は Manager 層完結のため、監視固有のドメインエラーは定義しない。
- 【レビュー反映】空クリップボードは **正常系**として扱う。`read()` / `getDescription()` は空時 `null` を返し、Bridge は `"null"` を返す（`EmptyClipboard` エラーは定義しない）。`hasClip()` で事前判定できるため、空を例外にしない。
- 【レビュー反映】`read()` の null 判定方針（空とバックグラウンド制限を識別しない）:
  - `getPrimaryClip()` が **`SecurityException` を送出** → `ReadNotAllowed` に正規化（唯一の失敗ケース）
  - `getPrimaryClip()` が **null を返す**（空・権限なしのいずれも区別不能）→ **空の正常系**として `null`（Bridge `"null"`）を返す
  - バックグラウンド読み取り制限で黙示的に null になる場合も、`getPrimaryClip()` が例外を投げない限り空扱い。呼び出し側は前面で `read()` する前提（KDoc 明記）

---

## エラーコード / メッセージ対応表

- 【設計判断】既存 repo は数値コードを持たず `DomainError → errorMessage(String)` に変換する方式。本設計もこれに準拠し、下表の「コード」は Bridge 消費側の安定識別子として **文字列** を新規採用（任意利用）。メッセージ言語は common.md 準拠（英語基準）。

| DomainError | 提案コード | errorMessage（Bridge 返却） |
|---|---|---|
| `EmptyContent` | `CLIPBOARD_EMPTY_CONTENT` | `Clipboard content is empty. Please provide text or HTML.` |
| `EmptyItemList` | `CLIPBOARD_EMPTY_ITEMS` | `No items provided for clipboard copy.` |
| `InvalidUri` | `CLIPBOARD_INVALID_URI` | `Invalid URI: {uri}` |
| `ClipboardUnavailable` | `CLIPBOARD_UNAVAILABLE` | `Clipboard service is unavailable.` |
| `ReadNotAllowed` | `CLIPBOARD_READ_NOT_ALLOWED` | `Clipboard read is not allowed. The app must be in the foreground.`（SecurityException 時のみ。null は空正常系で返す） |
| `SecurityException`(system) | `CLIPBOARD_SECURITY` | `Security restriction while accessing clipboard: {message}` |
| その他 `Exception` | `CLIPBOARD_UNKNOWN` | `Failed to {operation}: {message}` |

---

## テスト設計

### 単体テスト（UseCase / Mapper / Parser）

| 対象 | 正常系 | 異常系 | 境界値 |
|---|---|---|---|
| `CopyPlainTextUseCase` | 通常テキストで `copy` 呼び出し | - | 空文字（許容・呼び出しされる） |
| `CopyHtmlTextUseCase` | HTML コピー | 空 html で `EmptyContent` | 空 plain + 非空 html |
| `CopyUriUseCase` | 正常 URI | blank / 不正 URI で `InvalidUri` | `content://` と `file://` |
| `CopyMultipleTextUseCase` | 複数行 | 空リストで `EmptyItemList` | 1 要素 |
| `ReadClipboardUseCase` | 各型を `ClipReadResult` 化 | `SecurityException` → `ReadNotAllowed` | 空クリップボードで null（正常系）、複数 item |
| `HasClipUseCase` | true/false | - | - |
| `GetClipDescriptionUseCase` | メタデータ変換 | 空で null | styledText true/false |
| `ClearClipboardUseCase` | clear 呼び出し | - | - |
| `ClipboardMappers` | ClipData ↔ domain 変換、機微フラグ付与（`EXTRA_IS_SENSITIVE`） | - | mimeType 複数 |
| `UnityClipboardJsonParser`（unity plugin） | 各 JSON → spec | 不正 JSON / 欠落キー | 空配列 texts |
| `ClipboardChangeMonitor`（unity plugin） | start/stop・onChange 転送 | 二重 start が no-op、listener 未設定 | stop 後の非発火 |

- Mock: `MockClipboardRepository : ClipboardRepository`（`shouldFail`, `copyCallCount`, `stubbedReadResult` 等、common.md パターン）。
- 配置: UseCase / Mapper テストは `android_library` 側、Parser / Monitor テストは `unity_android_plugin` 側（Gradle module 境界と既存 share テスト配置に準拠）。

### 統合テスト（instrumented）

RepositoryImpl（Data 層、listener を持たない）:

- 実 `ClipboardManager` に対する copy → read の往復（プレーン/HTML/URI/複数）
- `clearPrimaryClip` 後の `hasClip == false`
- 空クリップボードで `read()` / `getDescription()` が null（正常系）
- 機微フラグ: API 33+ で `EXTRA_IS_SENSITIVE` が `description.extras` に入る

`ClipboardChangeMonitor` / Manager 監視 API（Manager 層、別枠）:

- 【レビュー反映】変更監視の実機/エミュ確認は Monitor 側の instrumented テストとして分離。copy 実行で `onClipboardChanged` 発火、`stopObserving` / `clearClipboardChangeListener` 後は非発火（リークなし）。RepositoryImpl instrumented には含めない

共通:

- 【レビュー反映】instrumented の**必須自動化対象は API 31 / 33**（最小サポートと機微フラグ導入の代表境界）。API 32（コピー確認 UI 直前）と API 34（回帰）は**手動確認**に割り当て、二重投資を避ける

### 手動確認項目

- API 31 / 32 / 33 / 34 実機で copy → 他アプリ（メモ等）で貼り付け成功
- API 33+: 機微フラグ付きコピーでシステムプレビューに内容が出ない
- API 32（境界）: コピー確認 UI が出ないこと、および自前トースト表示（アプリ側実装、サンプルで確認）
- Android 12+（API 31+）: 他アプリからの読み取り時の貼り付けアクセス通知（別仕様）を確認
- 監視: バックグラウンド遷移時に読み取り制限の影響を確認（要検証項目）

### 企画書リスク対応の検証ケース

| 企画書リスク | 検証ケース |
|---|---|
| バックグラウンド読み取り制限 | 前面/背面での `read()` 挙動。`SecurityException` → `ReadNotAllowed`、null → 空正常系（`"null"`）の分岐を確認 |
| コピー確認 UI 境界（13+） | API 32 と 33 でのシステム UI 有無 |
| 機微情報露出 | API 33+ プレビュー抑止 |
| リスナーリーク | stop 後の非発火（`ClipboardChangeMonitor` の instrumented テスト、RepositoryImpl とは別枠） |
| 画像責務境界 | URI 往復のみ（デコードしない）を単体で確認 |

---

## 実装タスク分解（依存関係付き）

| ID | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T1 | Domain 層（error/model 全ファイル） | 0.5d | - | `ClipboardDomainError` / `ClipContent` / `ClipReadResult` / `ClipItemData` / `ClipDescriptionInfo` 定義・ビルド通過 | Domain が `android.*` 非依存 |
| T2 | Port + UseCase 群 + suite（検証ロジック含む） | 1.0d | T1 | 全 UseCase の `invoke` 実装、検証で DomainError throw | 1操作1クラス、Log.d 準拠 |
| T3 | UseCase 単体テスト + MockRepository | 1.0d | T2 | 正常/異常/境界を網羅、全 passed | Mock が Port 実装、call counter |
| T4 | `ClipboardMappers`（ClipData ↔ domain、機微フラグ付与） | 0.5d | T1 | 変換関数実装、`EXTRA_IS_SENSITIVE` 定数直参照 | プラットフォーム型が Data 内に閉じる |
| T5 | `ClipboardRepositoryImpl` + factory | 1.0d | T2,T4 | 全 Port メソッド実装、system エラー→DomainError 変換 | Delegate を Impl に持たない |
| T6 | RepositoryImpl / Mapper の instrumented テスト | 1.0d | T5 | copy→read 往復・クリアを実機/エミュで確認 | API 31/33 で確認 |
| T7 | `UnityClipboardSpecs` + `UnityClipboardJsonParser` + テスト | 0.5d | T1 | JSON→spec 変換、不正 JSON 異常系 | 欠落キーの既定値 |
| T8 | `UnityAndroidClipboardManager`（copy/clear：Listener 版） | 1.0d | T2,T7 | copy/clear 実装、DomainError→errorMessage 変換、main スレッド実行 | Bridge 薄型、UseCase 経由 |
| T9 | Manager（read/has/description：同期 JSON 戻り値） | 0.5d | T8 | JSON 戻り値仕様どおり、空は `"null"` | 戻り値契約の一貫性 |
| T10 | `ClipboardChangeMonitor`（android_library / presentation、system listener 所有）+ Bridge 監視 API（委譲）+ テスト | 1.0d | T8 | 単一 listener 保持・二重登録 no-op・start/stop・ChangeListener 転送・clear で解除 | Listener 所有が native 側 1 クラス、Bridge 非依存で native から利用可、リーク防止 |
| T11 | 全体ビルド・既存テスト回帰・Lint/Dokka 確認 | 0.5d | T6,T9,T10 | 既存テスト緑、KDoc/Log.d 準拠 | 破壊的変更なし |
| S1 | サンプルアプリ（design-sample-app で実施） | - | T11 | クリップボード全サブ機能を UI から確認可能 | 具体パスは design-sample-app で定義 |

- 先行（基盤）: T1〜T6（コアライブラリ）
- 後続（拡張）: T7〜T10（Bridge / Manager 監視）、T11（統合）、S1（サンプル）

---

## リスクと緩和策

| リスク | 緩和策 |
|---|---|
| Android 10+ バックグラウンド読み取りで `read()` が null/SecurityException | `SecurityException` のみ `ReadNotAllowed` に正規化。null は空・制限を区別せず空の正常系（`"null"`）に倒す。KDoc とサンプルで前面前提を明示 |
| 変更監視のリーク | `ClipboardChangeMonitor` で単一 listener 管理、`stop()` / `clearClipboardChangeListener` で確実に解除。Monitor の instrumented テストで検証 |
| 機微フラグの runtime 差 | 現行 compileSdk 35 のため `EXTRA_IS_SENSITIVE` 定数を直接参照。runtime API 33+ のみ効果（それ未満は無害な no-op）。生キー分岐は不要 |
| Intent を Domain に持ち込む懸念 | Intent copy/paste を Out of scope に確定。Domain/Application/Port から完全除外 |
| system Listener の所有層 | 【v5】`OnPrimaryClipChangedListener` を `android_library` presentation 層の `ClipboardChangeMonitor` に集約。common.md「Unity Bridge 専用クラスにも Delegate を実装しない」に準拠し、native 呼び出し元からも利用可能。RepositoryImpl は Listener を持たない |
| 同期戻り値方式と既存 Listener 方式の不統一 | read 系のみ同期戻り値とする理由を Manager KDoc に明記。copy/clear は Listener 統一 |
| `getConfidenceScore` の `IllegalStateException`（要検証） | Bridge 非公開。ネイティブで扱う場合は `classificationStatus` ガード必須 |

---

## Definition of Done

- [ ] Domain/Application/Data/Bridge の全ファイルが追加され、既存モジュールに破壊的変更がない
- [ ] プレーンテキスト/HTML/URI/複数テキストの copy が動作（API 31,32,33,34）
- [ ] read / hasClip / getDescription が正しい JSON を返す（空は `"null"`）
- [ ] clear 後に `hasClip == false`
- [ ] 変更監視が start で発火・stop/clear で非発火（リークなし）、system Listener は Manager 層のみが所有
- [ ] 機微フラグが API 33+ でプレビュー抑止（instrumented 確認）
- [ ] 全 DomainError が errorMessage に正しく変換される
- [ ] UseCase 単体テスト・Mapper テスト（android_library）、Parser/Monitor テスト（unity_android_plugin）が全 passed
- [ ] RepositoryImpl の instrumented テストが API 31/33 で passed（API 32/34 は手動確認）
- [ ] android.md 準拠（全メソッド Log.d、public KDoc）
- [ ] common.md 準拠（Port ドメイン型のみ、Bridge は UseCase 経由、system Listener は native 側 1 クラス所有で Unity Bridge 専用クラスに置かない）
- [ ] Intent copy/paste が Domain/Application/Port に含まれない（Out of scope 徹底）
- [ ] 既存テスト回帰なし、Lint/Dokka 通過

### 要検証事項（設計段階で未確定）

| 項目 | 内容 |
|---|---|
| read 系の同期戻り値契約 | Unity 側 JNI で戻り値 String を安定取得できるか（既存 Manager は Listener のみ。要 PoC） |
| バックグラウンド read の実挙動 | API 別に null / SecurityException のどちらになるか実機確認 |
