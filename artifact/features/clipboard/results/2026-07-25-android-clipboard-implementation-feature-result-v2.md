# 実装結果レポート v2（レビュー指摘反映）

## 基本情報

- 日付: 2026-07-25
- 機能名: clipboard
- 対象OS: Android
- 設計書: artifact/designs/clipboard/2026-07-25-android-clipboard-design.md（v4）
- 実装結果 v1: artifact/results/clipboard/2026-07-25-android-clipboard-implementation-feature-result-v1.md
- 実装レビュー: artifact/reviews/clipboard/2026-07-25-android-clipboard-implementation-feature-review-v1.md（総合評価: 要修正（重大））
- ブランチ: feature/NTKIT-12

本レポートは v1 実装に対する実装レビュー v1 の指摘（重大2件・改善提案2件・軽微2件）を反映した差分をまとめる。v1 のサマリー・エラー契約全体像は本レポートに再掲せず、変更点に絞る。

---

## 1. レビュー指摘の反映内容

### 1.1 重大（high）— 反映済み

**1. Clipboard 本文が Logcat にそのまま出力される問題**

- 対象: `UnityAndroidClipboardManager.kt`（copyPlainText/copyHtmlText/copyUri/copyMultipleText）、`UnityClipboardJsonParser.kt`（全 parse 関数）、`CopyPlainTextUseCase` / `CopyHtmlTextUseCase` / `CopyUriUseCase` / `CopyMultipleTextUseCase`
- 対応:
  - Manager の copy 系メソッドは `clipboardJson` を `maskJson()` でマスク（`<redacted, length=N>`）してログ出力するよう変更。
  - Parser の各 `parse*` メソッドは `json: $json` ではなく `jsonLength: ${json.length}` のみ出力するよう変更。
  - UseCase 各 `invoke` のログを、raw content ではなく `textLength` / `htmlTextLength` / `plainTextLength` / `uriScheme` / `itemCount` / `label` / `isSensitive` などのメタ情報のみに変更。`uriScheme` は `android.net.Uri` を使わず文字列操作（`substringBefore("://")`）で抽出し、Application 層のプラットフォーム非依存を維持。
  - android.md の「メソッド入口で全パラメータを Log.d」という意図は、値そのものではなく「パラメータの存在とサイズ」を記録する形で両立。

**2. 同期 `read()` が `ReadNotAllowed` を含む全例外を `"null"` に握り潰す問題**

- 対象: `UnityAndroidClipboardManager.kt` の `read()` / `getDescription()`
- 対応:
  - `executeOperation()` の個別 catch チェーン（7 ブロック）を、共有の `errorInfoOf(exception): Pair<code, message>` 関数に統合（`EmptyContent` / `EmptyItemList` / `InvalidUri` / `ClipboardUnavailable` / `ReadNotAllowed` / `SecurityException` / その他 を設計のエラーコード表どおりに一元マッピング）。Listener 経路（`executeOperation`）と同期 JSON 経路（`read`/`getDescription`）の両方がこの単一の変換関数を使うため、エラー分類の乖離が構造的に発生しない。
  - `read()` / `getDescription()` の戻り値契約を明確化:
    - 成功・非空: 従来どおり JSON オブジェクト文字列
    - 成功・空クリップボード（正常系）: 文字列 `"null"`
    - 失敗（`ReadNotAllowed` 等）: JSON `{"error": "CLIPBOARD_READ_NOT_ALLOWED", "message": "..."}` — 空正常系の `"null"` と型的に区別可能
  - `hasClip()` は例外時 `"false"` を返す安全側フォールバックとし、KDoc に明記（Bridge の `hasClip` 契約は boolean 文字列のみでエラーチャネルを持たないための設計判断）。

### 1.2 改善提案（medium）— 反映済み

**1. URI 不正値検証が blank のみで実質機能していなかった問題**

- 対象: `CopyUriUseCase.kt`
- 対応: `ALLOWED_URI_SCHEMES = setOf("content", "file")` を追加し、blank チェックに加えて scheme が許可リストに含まれない場合も `ClipboardDomainError.InvalidUri` を throw するよう変更。`android.net.Uri` は使わず文字列操作でスキームを抽出し、Application 層のプラットフォーム非依存を維持。
- テスト追加: `copyUri_unsupportedScheme_throwsInvalidUri`（`http://...`）、`copyUri_noScheme_throwsInvalidUri`（`not-a-uri`）を `ClipboardUseCasesTest` に追加。

**2. 機微フラグ instrumented テストが `extras` の実値を検証していなかった問題**

- 対象: `ClipboardRepositoryImplTest.kt`（`copySensitiveContent_onApi33Plus_setsExtraIsSensitive`）
- 対応: `repository.getDescription() != null` の弱い確認をやめ、実 `ClipboardManager.primaryClipDescription?.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE)` を直接検証するよう変更（ドメイン `ClipDescriptionInfo` が `extras` を持たないため、テストでは実システムサービスを直接参照）。

### 1.3 軽微（low）— 反映済み

**1. TAG がフルクラス名になっていない問題**

- 対象: `ClipboardRepositoryImpl` / `CopyPlainTextUseCase` / `CopyHtmlTextUseCase` / `CopyUriUseCase` / `CopyMultipleTextUseCase` / `ReadClipboardUseCase` / `HasClipUseCase` / `GetClipDescriptionUseCase` / `ClearClipboardUseCase` / `UnityClipboardJsonParser` / `ClipboardChangeMonitor`
- 対応: 全 TAG を `android.library.clipboard.*.ClassName` / `android.unity.clipboard.ClassName` 形式のフルクラス名に統一（`UnityAndroidClipboardManager` は元々フルクラス名で問題なし）。

**2. `coercedText` の KDoc が実装（`coerceToText` 相当）と乖離していた問題**

- 対象: `ClipItemData.kt`
- 対応: KDoc を実装の実態（`text` → `uri` の文字列フォールバック、`Context` を伴う `ClipData.Item.coerceToText(Context)` は不使用）に合わせて修正。JSON フィールド名・Bridge 契約は変更なし（後方互換維持）。

---

## 2. 追加テスト

- `ClipboardUseCasesTest.kt` に 2 ケース追加（URI scheme 検証）: 22 → 24 ケース
- `unity_android_plugin/src/test/java/android/unity/clipboard/UnityAndroidClipboardManagerTest.kt` を新規作成（6 ケース）:
  - `read_clipboardUnavailable_returnsIdentifiableErrorJson`: 空正常系 `"null"` と失敗時エラー JSON が区別されることを確認
  - `getDescription_clipboardUnavailable_returnsIdentifiableErrorJson`: 同上
  - `hasClip_clipboardUnavailable_returnsFalse`: 安全側フォールバック確認
  - `copyPlainText_clipboardServiceFailure_notifiesFailureWithoutThrowing`: 失敗が例外送出でなく Listener 経由で通知され、かつエラーメッセージに本文（"hello"）が含まれないことを確認
  - `copyPlainText_invalidJson_notifiesFailureAndDoesNotLeakContentInMessage`
  - `copyUri_blankUri_notifiesInvalidUriFailure`
  - JVM 単体テストは `ContextWrapper(null)` ベースの `FakeContext`（既存 `UnityAndroidShareManagerTest` と同一パターン）を使用。`isReturnDefaultValues=true` の性質上、`copyPlainText` は `context.contentResolver` が先に null 化されるため `ClipboardUnavailable` ではなく汎用失敗経路を通ることが判明し、テストは実際の失敗経路（Listener 通知・非スロー・本文非漏洩）を検証する形に調整した。

## 3. ビルド・テスト結果

- 実行コマンド:
  - `JAVA_HOME="/Applications/Android Studio Panda 1 .app/Contents/jbr/Contents/Home" ./gradlew :android_library:compileReleaseKotlin :unity_android_plugin:compileReleaseKotlin :android_library:compileReleaseUnitTestKotlin :unity_android_plugin:compileReleaseUnitTestKotlin` → SUCCESS
  - `./gradlew :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest` → SUCCESS（初回1件失敗を修正後、再実行で全 passed）
  - `./gradlew :android_library:lintRelease :unity_android_plugin:lintRelease :android_library:dokkaHtml` → SUCCESS
  - `./scripts/build_android_library_aar.sh -b release -m android_library -v 1.2.0 -o /tmp/android_library-verify2.aar` → `[done] Created /tmp/android_library-verify2.aar`
  - `./scripts/build_android_library_aar.sh -b release -m unity_android_plugin -v 1.2.0 -o /tmp/unity_android_plugin-verify2.aar` → `[done] Created /tmp/unity_android_plugin-verify2.aar`
- テスト結果サマリー（clipboard 新規分）:
  - `ClipboardUseCasesTest`: 24件 全 passed
  - `UnityClipboardJsonParserTest`: 12件 全 passed
  - `UnityAndroidClipboardManagerTest`（新規）: 6件 全 passed
  - 新規分合計 42件、失敗 0
- 既存回帰: android_library / unity_android_plugin 全 suite で失敗ゼロ（v1 と同様に回帰なし）
- 未実施項目（v1 から変更なし）:
  - `ClipboardRepositoryImplTest`（instrumented, 9ケース）: 実機/エミュレータ未接続のため未実行
  - `ClipboardChangeMonitorTest`（instrumented, 6ケース）: 同上
  - 設計書「手動確認項目」: 実機確認が必要なため未実施

## 4. レビュー指摘の反映状況一覧

| # | 重大度 | 指摘内容 | 反映状況 |
|---|---|---|---|
| 1 | high | Clipboard 本文の raw ログ出力 | 反映済み（マスク化） |
| 2 | high | 同期 read() が ReadNotAllowed を握り潰す | 反映済み（識別可能な error JSON） |
| 3 | medium | InvalidUri がほぼ発火しない | 反映済み（scheme allowlist） |
| 4 | medium | 機微フラグテストが extras を検証せず | 反映済み（extras 直接検証） |
| 5 | low | TAG がフルクラス名でない | 反映済み（全ファイル修正） |
| 6 | low | coercedText の KDoc 乖離 | 反映済み（KDoc 修正） |

不足項目として挙げられていた5点（`read()` の識別可能テスト、raw ログ非出力確認、`InvalidUri` の不正値テスト、`EXTRA_IS_SENSITIVE` extras 検証、instrumented 実行）のうち、JVM 環境で検証可能な4点は本反映でテスト追加済み。instrumented 実行のみ実機/エミュレータ環境の制約により引き続き未実施。

## 5. 設計差分（v1 からの追加分）

- v1 に記載した2点（Mapper テスト配置、Monitor テスト配置）に加えて追加の設計差分はなし。
- `executeOperation()` の catch チェーンを共有関数 `errorInfoOf()` に統合したのは設計書のエラーコード表の実装方法に関する実装時判断であり、エラーコード/メッセージ対応表そのものの変更はない。

## 6. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
