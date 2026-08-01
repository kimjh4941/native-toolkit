# Android Clipboard 実装再レビュー v2

- 日付: 2026-07-25
- 対象ブランチ: `feature/NTKIT-12`
- 対象差分: `develop...HEAD` は空。未追跡の Android Clipboard 実装ファイルをレビュー対象として確認
- 前回レビュー: `artifact/reviews/clipboard/2026-07-25-android-clipboard-implementation-feature-review-v1.md`
- 設計書: `artifact/designs/clipboard/2026-07-25-android-clipboard-design.md`
- 実装結果: `artifact/results/clipboard/2026-07-25-android-clipboard-implementation-feature-result-v1.md`
- 対象 OS: Android
- 総合評価: 要修正（重大）

---

## レビュー概要

v1 の指摘に対して、Manager / Parser / UseCase 側の raw clipboard log、同期 `read()` のエラー契約、URI 検証、機微フラグ検証、TAG フルクラス名、`coercedText` KDoc は概ね反映済みです。

ただし、Data 層の `ClipboardRepositoryImpl.copy()` がまだ `ClipContent` を丸ごと `Log.d` に出力しており、Clipboard 本文・HTML・URI・複数テキストが Logcat に残る問題が継続しています。Clipboard 機能のセキュリティ境界としてはリリース前に修正必須です。

## 前回指摘の反映状況

- High: Manager / Parser / UseCase の raw clipboard log: **一部解消**。`UnityAndroidClipboardManager` は `maskJson()`、`UnityClipboardJsonParser` は `jsonLength`、各 copy UseCase は length / scheme / count ログに変更されています。ただし `ClipboardRepositoryImpl.copy()` に raw `ClipContent` ログが残っています。
- High: 同期 `read()` が `ReadNotAllowed` を `"null"` に潰す: **解消済み**。`read()` は例外時に `{ "error": "...", "message": "..." }` を返し、空 clipboard の `"null"` と区別できます。
- Medium: URI 不正値検証が blank 以外で弱い: **解消済み**。`CopyUriUseCase` が `content` / `file` scheme のみを許可し、unsupported scheme / no scheme の unit test が追加されています。
- Medium: `EXTRA_IS_SENSITIVE` の instrumented 検証不足: **解消済み**。`ClipboardRepositoryImplTest` が `ClipDescription.EXTRA_IS_SENSITIVE` の extras 値を直接確認しています。
- Low: TAG がフルクラス名ではない: **解消済み**。新規 clipboard クラスの TAG はフルクラス名へそろっています。
- Low: `coercedText` の KDoc と実装のズレ: **解消済み**。`coercedText` は best-effort fallback であり `ClipData.Item.coerceToText(Context)` ではないことが KDoc に明記されています。

## 重大な問題（high）

1. **`ClipboardRepositoryImpl.copy()` が `ClipContent` を raw 出力しており、Clipboard 本文がまだ Logcat に漏れます。**
   - 該当箇所: `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardRepositoryImpl.kt:24-27`
   - 現在の実装は `Log.d(TAG, "[copy] content: $content")` です。`ClipContent.PlainText` / `HtmlText` / `UriContent` / `MultipleText` は data class なので、`toString()` に本文・HTML・URI・複数テキストがそのまま含まれます。
   - v1 の High は Bridge / UseCase だけでなく「Clipboard 本文が Logcat に残る」こと自体が問題でした。UseCase 側でマスクしても Data 層で raw content を出すと同じ漏えいが残ります。
   - `android.md` の「全パラメータ Log.d」は、Clipboard では raw 値ではなく `contentType`、`textLength`、`htmlTextLength`、`uriScheme`、`itemCount`、`label`、`isSensitive` などのメタ情報ログに置き換えてください。

## 改善提案（medium）

- なし。

## 軽微な指摘（low）

- なし。

## 設計書整合性チェック

- 企画書との整合性: △（主要 API とエラー契約は反映済み。raw clipboard log が残る）
- Clean Architecture 準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △（unit test は通過。instrumented / 実機は未実行）
- ドメインエラー全ケース実装: ○
- エラーコード/メッセージ対応表との整合: ○

## プロジェクトルール適合チェック

- common.md 準拠: ○
- android.md 準拠: △（Log.d はあるが、Clipboard 本文を raw 出力しているためセキュリティ上マスクが必要）
- エラー契約反映: ○
- 既存 API 互換性: ○

## テストカバレッジ

- カバー済み:
  - UseCase の正常系・異常系・境界値
  - URI の unsupported scheme / no scheme
  - Unity JSON Parser
  - Manager の同期 `read()` / `getDescription()` failure JSON
  - 機微フラグ extras の instrumented test コード
- 不足:
  - `ClipboardRepositoryImpl.copy()` が raw clipboard content をログ出力しないことのレビューまたはテスト確認
  - 実機/エミュレータでの `ClipboardRepositoryImplTest` / `ClipboardChangeMonitorTest`

## 実行確認

- `git diff --check`: 成功
- `JAVA_HOME='/Applications/Android Studio Panda 1 .app/Contents/jbr/Contents/Home' ./gradlew :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest`
  - 実行場所: `android/AndroidLibraryExample`
  - 結果: `BUILD SUCCESSFUL`
  - 補足: workspace sandbox では `~/.gradle` の lock file にアクセスできず失敗したため、同一コマンドを権限付きで再実行

## 総合評価

要修正（重大）。

v1 から大きく改善していますが、Clipboard 本文の raw log が Data 層に残っているため、まだ LGTM にはできません。`ClipboardRepositoryImpl.copy()` のログをマスクすれば、前回レビュー由来の重大指摘は解消できる見込みです。
