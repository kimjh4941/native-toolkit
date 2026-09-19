# Android シェア機能 実装設計書

- 対象企画書: artifact/plans/share/2026-05-23-android-share-research-v2.md
- 作成日: 2026-05-24
- 対象OS: Android
- 対象機能: シェア機能（Share）

---

## 設計目的

企画書の Android シェア API 調査結果をもとに、native-toolkit の Clean Architecture に準拠した
実装設計を確定する。Unity Bridge 経由で全サブ機能を呼び出せる形に設計する。

---

## スコープ

### In scope
- テキスト・URL シェア
- 単一・複数画像シェア
- 単一・複数ファイルシェア（FileProvider）
- Direct Share ターゲット登録・削除
- ChooserAction（カスタムアクションボタン、API 34+）
- シェア結果コールバック（API 31〜33: `EXTRA_CHOSEN_COMPONENT` / API 34+: `ChooserResult`）
- Unity Bridge 公開 API

### Out of scope
- iOS / macOS / Windows のシェア API
- 受信側（Intent Filter）実装
- サードパーティ SDK

---

## 共通実装方針の適用チェック（common.md 準拠）

| 項目 | 適用 | 備考 |
|---|---|---|
| Clean Architecture 層・依存方向 | 適用 | Domain → Application → Data → Manager の順 |
| Domain に Android 型を持ち込まない | 適用 | Domain は標準ライブラリ型のみ |
| Port はドメイン型のみ | 適用 | Context は RepositoryImpl コンストラクタで保持 |
| Manager → UseCase → Repository 経路 | 適用 | Manager は直接 Repository を呼ばない |
| Delegate/Listener は Manager が所有 | 適用 | コールバック BroadcastReceiver の登録は RepositoryImpl 内、結果通知は Manager |
| TDD: UseCase 単位でテスト | 適用 | MockShareRepository を DI して各 UseCase をテスト |
| エラー変換: RepositoryImpl → DomainError → Manager | 適用 | DomainError を throw し Manager の executeOperation で変換 |
| Unity Bridge: 薄く保つ | 適用 | Manager の public API を呼ぶだけ |
| 最小 OS バージョン: Android 12（API 31） | 適用 | minSdk = 31 を前提に分岐設計 |

---

## 個別実装方針の適用チェック（android.md 準拠）

| 項目 | 適用 | 備考 |
|---|---|---|
| 全メソッド先頭に `Log.d(TAG, "[methodName] param: $param")` | 適用 | override / operator fun invoke / public / internal / BroadcastReceiver.onReceive |
| エラーは `Log.e` | 適用 | `executeOperation` の catch 節で使用 |
| TAG は `companion object { const val TAG = "FullClassName" }` | 適用 | |
| public 関数・クラスに KDoc コメント | 適用 | `@param` 全引数必須 |

---

## 既存実装差分サマリー

| 項目 | 状況 |
|---|---|
| `android_library` 配下に `share/` パッケージ | 新規作成 |
| `unity_android_plugin` 配下に `share/` パッケージ | 新規作成 |
| `AndroidLibraryExample/app` の `MainMenuScreen.kt` | Share エントリー追加（変更） |
| `AndroidLibraryExample/app` の `MainRouter.kt` | Share ルート追加（変更） |
| `AndroidLibraryExample/app/AndroidManifest.xml` | FileProvider provider 宣言追加（変更） |
| `AndroidLibraryExample/app/res/xml/file_paths.xml` | 新規作成 |
| `AndroidLibraryExample/app/proguard-rules.pro` | keep ルール追加（変更） |
| 破壊的変更 | なし |

---

## 実装アーキテクチャ

```
Unity / Caller
     │
     ▼
UnityAndroidShareManager          (unity_android_plugin / Manager)
  ├── setShareOperationListener()
  ├── shareText()
  ├── shareImage()
  ├── shareImages()
  ├── shareFile()
  ├── shareFiles()
  ├── registerDirectShareTarget()
  ├── removeDirectShareTargets()
  └── shareWithCallback()
     │ (executeOperation)
     ▼
ShareUseCases                     (android_library / Application UseCase)
  ├── ShareTextUseCase
  ├── ShareImageUseCase
  ├── ShareMultipleImagesUseCase
  ├── ShareFileUseCase
  ├── ShareMultipleFilesUseCase
  ├── RegisterDirectShareTargetUseCase
  ├── RemoveDirectShareTargetsUseCase
  └── ShareWithCallbackUseCase
     │
     ▼
ShareRepository (Port)            (android_library / Application Port)
     │
     ▼
ShareRepositoryImpl               (android_library / Data)
  └── FileProvider, ShortcutManagerCompat, Intent, BroadcastReceiver
```

---

## サブ機能別詳細設計

### 1. テキスト・URL シェア

**制御フロー:**
1. Manager が JSON / 引数をパース → `ShareContent` 生成
2. `ShareUseCases(context).shareText(content)` 呼び出し
3. `ShareTextUseCase.invoke(content)` → `repository.shareText(content)`
4. `ShareRepositoryImpl` が `Intent.ACTION_SEND` を組み立て `createChooser` 経由で `startActivity`

**ファイル:**
- `domain/model/ShareContent.kt`
- `application/usecase/ShareTextUseCase.kt`
- `application/port/ShareRepository.kt`（`shareText` メソッド）
- `data/repository/ShareRepositoryImpl.kt`（`shareText` 実装）

### 2. 画像シェア（単一・複数）

**制御フロー:**
1. Manager が画像パス文字列（1件または List）を受け取る
2. `ShareImageUseCase.invoke(filePath, mimeType)` または `ShareMultipleImagesUseCase.invoke(filePaths)`
3. RepositoryImpl が各パスを `File` → `FileProvider.getUriForFile` で `content://` URI に変換
4. `FLAG_GRANT_READ_URI_PERMISSION` を付与して `startActivity`

**ファイル:**
- `application/usecase/ShareImageUseCase.kt`
- `application/usecase/ShareMultipleImagesUseCase.kt`
- `application/port/ShareRepository.kt`（`shareImage`, `shareImages`）
- `data/repository/ShareRepositoryImpl.kt`
- `data/repository/ShareMimeTypeHelper.kt`

### 3. ファイルシェア（単一・複数）

単一 / 複数で `ACTION_SEND` / `ACTION_SEND_MULTIPLE` を使い分ける。画像シェアと同実装パス。

**ファイル:**
- `application/usecase/ShareFileUseCase.kt`
- `application/usecase/ShareMultipleFilesUseCase.kt`
- `application/port/ShareRepository.kt`（`shareFile`, `shareFiles`）
- `data/repository/ShareRepositoryImpl.kt`

### 4. Direct Share ターゲット登録・削除

**制御フロー:**
1. Manager が JSON をパース → `DirectShareTarget` + `iconBytes` 生成
2. `RegisterDirectShareTargetUseCase.invoke(target, iconBytes)` → RepositoryImpl
3. RepositoryImpl が `Bitmap` 復元 → `ShortcutInfoCompat` 構築 → `ShortcutManagerCompat.pushDynamicShortcut`

**削除:**
1. `RemoveDirectShareTargetsUseCase.invoke(ids)` → `ShortcutManagerCompat.removeLongLivedShortcuts`

**ファイル:**
- `domain/model/DirectShareTarget.kt`
- `application/usecase/RegisterDirectShareTargetUseCase.kt`
- `application/usecase/RemoveDirectShareTargetsUseCase.kt`
- `application/port/ShareRepository.kt`（`registerDirectShareTarget`, `removeDirectShareTargets`）
- `data/repository/ShareRepositoryImpl.kt`

### 5. ChooserAction（API 34+）

Manager の `shareText` / `shareFile` に `ChooserAction` リストを追加できる拡張として設計。
API 34 未満では無視する。`ShareContent` に `chooserActions: List<ChooserActionSpec>` を持たせる。

### 6. シェア結果コールバック

**制御フロー:**
1. Manager が `shareWithCallback(context, json)` を呼び出す
2. `ShareWithCallbackUseCase.invoke(content)` → RepositoryImpl
3. RepositoryImpl が BroadcastReceiver を `ContextCompat.registerReceiver` で登録（`RECEIVER_NOT_EXPORTED`）
4. `onReceive` でワンショット解除 → API バージョン分岐でパッケージ名を取得
5. Manager の `ShareOperationListener.onShareResult(packageName)` を呼ぶ

**API バージョン分岐:**
```
minSdk = 31
├── API 31〜33: EXTRA_CHOSEN_COMPONENT (ComponentName)
└── API 34+  : EXTRA_CHOOSER_RESULT (ChooserResult.selectedComponent)
```

**ファイル:**
- `application/usecase/ShareWithCallbackUseCase.kt`
- `application/port/ShareRepository.kt`（`shareWithCallback`）
- `data/repository/ShareRepositoryImpl.kt`

---

## API 設計

### 公開 API（Unity Bridge 向け）

**`UnityAndroidShareManager`**

```kotlin
// コールバック登録
fun setShareOperationListener(listener: ShareOperationListener)
fun clearShareOperationListener()

// テキスト・URLシェア
fun shareText(context: Context, shareJson: String)
// shareJson: { "text": "...", "title": "..." }

// 単一画像シェア
fun shareImage(context: Context, shareJson: String)
// shareJson: { "filePath": "...", "mimeType": "image/jpeg" }

// 複数画像シェア
fun shareImages(context: Context, shareJson: String)
// shareJson: { "filePaths": ["...", "..."], "mimeType": "image/*" }

// 単一ファイルシェア
fun shareFile(context: Context, shareJson: String)
// shareJson: { "filePath": "..." }

// 複数ファイルシェア
fun shareFiles(context: Context, shareJson: String)
// shareJson: { "filePaths": ["...", "..."] }

// Direct Share ターゲット登録
fun registerDirectShareTarget(context: Context, shareJson: String)
// shareJson: { "id": "...", "label": "...", "iconBase64": "...", "category": "..." }

// Direct Share ターゲット削除
fun removeDirectShareTargets(context: Context, shareJson: String)
// shareJson: { "ids": ["...", "..."] }

// コールバック付きシェア
fun shareWithCallback(context: Context, shareJson: String)
// shareJson: { "text": "...", "title": "..." }

interface ShareOperationListener {
    fun onShareOperation(operation: String, isSuccessful: Boolean, errorMessage: String?)
    fun onShareResult(operation: String, selectedPackageName: String?)
}
```

**操作名定数（Manager 内）:**

```kotlin
const val OPERATION_SHARE_TEXT = "shareText"
const val OPERATION_SHARE_IMAGE = "shareImage"
const val OPERATION_SHARE_IMAGES = "shareImages"
const val OPERATION_SHARE_FILE = "shareFile"
const val OPERATION_SHARE_FILES = "shareFiles"
const val OPERATION_REGISTER_DIRECT_SHARE_TARGET = "registerDirectShareTarget"
const val OPERATION_REMOVE_DIRECT_SHARE_TARGETS = "removeDirectShareTargets"
const val OPERATION_SHARE_WITH_CALLBACK = "shareWithCallback"
```

### 内部 API（Application Port）

```kotlin
interface ShareRepository {
    fun shareText(content: ShareContent)
    fun shareImage(filePath: String, mimeType: String)
    fun shareImages(filePaths: List<String>)
    fun shareFile(filePath: String)
    fun shareFiles(filePaths: List<String>)
    fun registerDirectShareTarget(target: DirectShareTarget, iconBytes: ByteArray)
    fun removeDirectShareTargets(ids: List<String>)
    fun shareWithCallback(content: ShareContent, onResult: (String?) -> Unit)
}
```

---

## ドメインエラー一覧（全ケース）

```kotlin
// android_library/share/domain/error/ShareDomainError.kt
sealed class ShareDomainError : Exception() {
    data object EmptyContent : ShareDomainError()
    data object NoShareTarget : ShareDomainError()
    data class FileNotFound(val path: String) : ShareDomainError()
    data class IllegalFileAccess(val path: String) : ShareDomainError()
    data class InvalidMimeType(val mimeType: String) : ShareDomainError()
    data class DirectShareRegistrationFailed(val reason: String) : ShareDomainError()
    data object EmptyIdList : ShareDomainError()
    data object EmptyFileList : ShareDomainError()
    data class InvalidBase64Icon(val id: String) : ShareDomainError()
}
```

---

## エラーコード / メッセージ対応表

| エラー | 発生箇所 | Manager エラーメッセージ |
|---|---|---|
| `EmptyContent` | text が blank | `"Share content is empty. Please provide text or a file path."` |
| `NoShareTarget` | 受信アプリなし（`ActivityNotFoundException`） | `"No app available to handle this share request."` |
| `FileNotFound` | `File.exists()` が false | `"File not found: ${path}"` |
| `IllegalFileAccess` | `FileProvider.getUriForFile` が `IllegalArgumentException` | `"File cannot be shared: ${path}. Ensure the file is in a supported directory."` |
| `InvalidMimeType` | mimeType が blank | `"Invalid MIME type: ${mimeType}"` |
| `DirectShareRegistrationFailed` | `pushDynamicShortcut` 失敗 | `"Failed to register Direct Share target: ${reason}"` |
| `EmptyIdList` | ids が空 | `"No shortcut IDs provided for removal."` |
| `EmptyFileList` | filePaths が空 | `"No file paths provided for share."` |
| `InvalidBase64Icon` | Base64デコード失敗 | `"Invalid icon data for Direct Share target: ${id}"` |
| `SecurityException` | FileProvider 権限エラー | `"Security restriction while executing ${operation}: ${message}"` |
| その他 `Exception` | 予期しない例外 | `"Failed to ${operation}: ${message}"` |

---

## データ構造

### `ShareContent`（Domain）

```kotlin
data class ShareContent(
    val text: String,
    val title: String? = null,
    val subject: String? = null,
    val mimeType: String = "text/plain"
)
```

### `DirectShareTarget`（Domain）

```kotlin
data class DirectShareTarget(
    val id: String,
    val label: String,
    val category: String = "android.shortcut.conversation"
)
```

### `UnityShareTextSpec`（Application Model / JSON解析結果）

```kotlin
data class UnityShareTextSpec(
    val text: String,
    val title: String? = null,
    val subject: String? = null,
    val mimeType: String = "text/plain"
)
```

### `UnityShareFileSpec`

```kotlin
data class UnityShareFileSpec(
    val filePath: String? = null,
    val filePaths: List<String> = emptyList(),
    val mimeType: String? = null
)
```

### `UnityDirectShareTargetSpec`

```kotlin
data class UnityDirectShareTargetSpec(
    val id: String,
    val label: String,
    val iconBase64: String,
    val category: String = "android.shortcut.conversation"
)
```

### `UnityRemoveDirectShareTargetsSpec`

```kotlin
data class UnityRemoveDirectShareTargetsSpec(
    val ids: List<String>
)
```

---

## テスト設計

### 単体テスト（`android_library`）

**対象: 各 UseCase（MockShareRepository を DI）**

| テストケース | UseCase | 確認内容 |
|---|---|---|
| テキストシェア正常系 | `ShareTextUseCase` | `repository.shareText` が1回呼ばれる |
| テキスト空文字 | `ShareTextUseCase` | `ShareDomainError.EmptyContent` が throw される |
| 単一画像シェア正常系 | `ShareImageUseCase` | `repository.shareImage` が1回呼ばれる |
| 複数画像シェア空リスト | `ShareMultipleImagesUseCase` | `ShareDomainError.EmptyFileList` |
| ファイルシェア正常系 | `ShareFileUseCase` | `repository.shareFile` が1回呼ばれる |
| Direct Share 登録正常系 | `RegisterDirectShareTargetUseCase` | `repository.registerDirectShareTarget` が1回呼ばれる |
| Direct Share 登録: ID 空文字 | `RegisterDirectShareTargetUseCase` | `ShareDomainError.DirectShareRegistrationFailed` |
| Direct Share 削除: 空 ID リスト | `RemoveDirectShareTargetsUseCase` | `ShareDomainError.EmptyIdList` |
| コールバック正常系 | `ShareWithCallbackUseCase` | `repository.shareWithCallback` が1回呼ばれ onResult が呼ばれる |

**対象: `ShareMimeTypeHelper`**

| テストケース | 確認内容 |
|---|---|
| .jpg → "image/jpeg" | 正しい MIME 型が返る |
| .png → "image/png" | 正しい MIME 型が返る |
| 不明拡張子 → "*/*" | フォールバック |
| 拡張子なし → "*/*" | フォールバック |

**対象: `UnityShareJsonParser`**

| テストケース | 確認内容 |
|---|---|
| text フィールドのパース | `text` が正しくマッピングされる |
| title が null のパース | null が正しく処理される |
| filePaths 配列のパース | List が正しく返る |
| ids 配列のパース | List が正しく返る |
| JSON 不正形式 | JSONException が throw される |

### 統合テスト（Instrumented Test）

| テストケース | 確認内容 |
|---|---|
| `FileProvider.getUriForFile` 正常動作 | `content://` URI が返る（実機/エミュレータ） |
| `ShortcutManagerCompat.pushDynamicShortcut` 正常動作 | 例外が発生しない |

### 手動確認項目

| 項目 | 確認内容 | 確認 API バージョン |
|---|---|---|
| テキストシェア | Android Sharesheet が表示される | API 31, 34 |
| URL シェア | URL がテキストとして共有される | API 31, 34 |
| 単一画像シェア | 画像が共有される | API 31, 34 |
| 複数画像シェア | 複数枚が共有される | API 31, 34 |
| ファイルシェア | ファイルが共有される | API 31, 34 |
| Direct Share 登録 | Sharesheet にショートカットが表示される | API 31, 34 |
| ChooserAction 表示 | カスタムボタンが Sharesheet に表示される | API 34 のみ |
| コールバック（API 31〜33） | 選択アプリのパッケージ名が返る | API 31 |
| コールバック（API 34+） | ChooserResult 経由でパッケージ名が返る | API 34 |
| BroadcastReceiver リークなし | onReceive 後に受信しなくなる（ワンショット確認） | API 31, 34 |
| キャンセル時のコールバック | onShareResult(null) が呼ばれる | API 31, 34 |

---

## 実装タスク分解

### Task 1: Domain 層（0.5日）

**ファイル:**
- `android_library/src/main/java/android/library/share/domain/model/ShareContent.kt`（新規）
- `android_library/src/main/java/android/library/share/domain/model/DirectShareTarget.kt`（新規）
- `android_library/src/main/java/android/library/share/domain/error/ShareDomainError.kt`（新規）

**完了条件:** KDoc 付き、Android 型なし、コンパイル通過

**依存:** なし

---

### Task 2: Application 層 - Port（0.5日）

**ファイル:**
- `android_library/src/main/java/android/library/share/application/port/ShareRepository.kt`（新規）

**完了条件:** Domain 型のみ、KDoc 付き、コンパイル通過

**依存:** Task 1

---

### Task 3: Application 層 - UseCase（1日）

**ファイル:**
- `android_library/src/main/java/android/library/share/application/usecase/ShareTextUseCase.kt`（新規）
- `android_library/src/main/java/android/library/share/application/usecase/ShareImageUseCase.kt`（新規）
- `android_library/src/main/java/android/library/share/application/usecase/ShareMultipleImagesUseCase.kt`（新規）
- `android_library/src/main/java/android/library/share/application/usecase/ShareFileUseCase.kt`（新規）
- `android_library/src/main/java/android/library/share/application/usecase/ShareMultipleFilesUseCase.kt`（新規）
- `android_library/src/main/java/android/library/share/application/usecase/RegisterDirectShareTargetUseCase.kt`（新規）
- `android_library/src/main/java/android/library/share/application/usecase/RemoveDirectShareTargetsUseCase.kt`（新規）
- `android_library/src/main/java/android/library/share/application/usecase/ShareWithCallbackUseCase.kt`（新規）
- `android_library/src/main/java/android/library/share/application/usecase/ShareUseCases.kt`（新規）

**完了条件:** 各 UseCase が `operator fun invoke` を持ち、MockShareRepository で単体テスト通過

**依存:** Task 1, 2

---

### Task 4: Data 層（1日）

**ファイル:**
- `android_library/src/main/java/android/library/share/data/repository/ShareMimeTypeHelper.kt`（新規）
- `android_library/src/main/java/android/library/share/data/repository/ShareRepositoryImpl.kt`（新規）
- `android_library/src/main/java/android/library/share/data/repository/ShareUseCases.kt`（factory 関数、新規）

**完了条件:** FileProvider URI 生成・Intent 組み立て・BroadcastReceiver ワンショット登録が実装され、
Instrumented Test で FileProvider が動作する

**依存:** Task 1, 2, 3

---

### Task 5: Manifest / FileProvider 設定（0.5日）

**ファイル:**
- `AndroidLibraryExample/app/src/main/AndroidManifest.xml`（`<provider>` 追加）
- `AndroidLibraryExample/app/src/main/res/xml/file_paths.xml`（新規）
- `AndroidLibraryExample/app/proguard-rules.pro`（keep ルール追加）

**完了条件:** `getUriForFile` が `IllegalArgumentException` を投げずに動作する

**依存:** Task 4

---

### Task 6: Unity Bridge 層（1日）

**ファイル:**
- `unity_android_plugin/src/main/java/android/unity/share/UnityShareSpecs.kt`（新規）
- `unity_android_plugin/src/main/java/android/unity/share/UnityShareJsonParser.kt`（新規）
- `unity_android_plugin/src/main/java/android/unity/share/UnityAndroidShareManager.kt`（新規）

**完了条件:** 全 public API が KDoc 付き、`executeOperation` パターンで例外をハンドルし、
`ShareOperationListener` に結果を通知する。単体テスト（JSON パーサー）が通過する

**依存:** Task 4

---

### Task 7: 単体テスト（1日）

**ファイル:**
- `android_library/src/test/.../share/application/ShareUseCasesTest.kt`（新規）
- `android_library/src/test/.../share/data/ShareMimeTypeHelperTest.kt`（新規）
- `unity_android_plugin/src/test/.../share/UnityShareJsonParserTest.kt`（新規）

**完了条件:** 全テストケースが JUnit 5 + MockK で passed

**依存:** Task 3, 4, 6

---

### Task 8: サンプルアプリ（1日）

**ファイル:**
- `AndroidLibraryExample/app/src/main/java/.../example/ShareSampleScreen.kt`（新規）
- `AndroidLibraryExample/app/src/main/java/.../example/MainMenuScreen.kt`（Share エントリー追加）
- `AndroidLibraryExample/app/src/main/java/.../example/MainRouter.kt`（Share ルート追加）

**完了条件:** 全サブ機能のボタンが配置され、手動確認項目のすべてが実機で確認できる

**依存:** Task 5, 6

---

## リスクと緩和策

| リスク | 詳細 | 緩和策 |
|---|---|---|
| FileProvider パス未定義 | `file_paths.xml` のパスが実際のファイル位置と合わない場合 `IllegalArgumentException` | Task 5 で `files-path` / `cache-path` / `external-files-path` を網羅的に定義し Instrumented Test で検証 |
| BroadcastReceiver リーク | ワンショット解除を忘れた場合 | `onReceive` 先頭で `ctx?.unregisterReceiver(this)` を必ず呼ぶ。単体テストで verify |
| `RECEIVER_NOT_EXPORTED` 未設定（API 34+） | Android OS がクラッシュを引き起こす | `ContextCompat.registerReceiver` に `RECEIVER_NOT_EXPORTED` を指定し API バージョン分岐不要にする |
| ChooserResult API 34 未満誤用 | `ClassNotFoundException` / クラッシュ | `Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE` 分岐を必須とし、レビュー観点に追加 |
| Direct Share カテゴリ不正 | Sharesheet に表示されない | `android.shortcut.conversation` をデフォルト値として定義し、JSON パーサーでも保持 |
| FileProvider 難読化 | ProGuard で FileProvider クラスが消える | Task 5 で keep ルールを追加し、リリースビルドで動作確認 |
| ChooserAction 上限数 | ドキュメント未記載 | 要検証: 実機で 1〜3 件試験し上限を確認する |

---

## Definition of Done

- [ ] テキスト・URL シェアが Android Sharesheet 経由で動作する（API 31, 34 で確認）
- [ ] 単一・複数画像シェアが動作する（API 31, 34 で確認）
- [ ] FileProvider 経由のファイルシェアが動作する（API 31, 34 で確認）
- [ ] Direct Share ターゲットが Sharesheet に表示される
- [ ] ChooserAction がカスタムボタンとして表示される（API 34+ のみ）
- [ ] シェア結果コールバックが API 31〜33 で `EXTRA_CHOSEN_COMPONENT` を通じて動作する
- [ ] シェア結果コールバックが API 34+ で `ChooserResult` を通じて動作する
- [ ] BroadcastReceiver がワンショット解除され、メモリリークが発生しない
- [ ] `FileProvider` Manifest・`file_paths.xml` 設定が正しく動作する
- [ ] ProGuard / R8 ルールが設定されている
- [ ] 全 UseCase テストが passed
- [ ] `UnityShareJsonParser` テストが passed
- [ ] サンプルアプリで全サブ機能が確認できる
