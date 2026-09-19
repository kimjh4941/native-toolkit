# Android Clipboard 実装レビュー v1

- 日付: 2026-07-25
- 対象ブランチ: `feature/NTKIT-12`
- 対象差分: `develop...HEAD` は空。未追跡の Android Clipboard 実装ファイルをレビュー対象として確認
- 設計書: `artifact/designs/clipboard/2026-07-25-android-clipboard-design.md`
- 実装結果: `artifact/results/clipboard/2026-07-25-android-clipboard-implementation-feature-result-v1.md`
- 対象 OS: Android
- 総合評価: 要修正（重大）

---

## レビュー概要

Android Clipboard 機能として、`android_library` に Domain/Application/Data、`unity_android_plugin` に Manager/Bridge/Monitor が新規追加されています。設計レビューで確定した Intent 除外、Manager 層の system Listener 所有、空 clipboard の正常 `null` 扱い、`SecurityException` 限定の `ReadNotAllowed` は概ね実装へ反映されています。

ただし、Clipboard 本文を raw JSON / Domain model として `Log.d` に出力している点と、同期 `read()` が `ReadNotAllowed` を含む例外を `"null"` に潰してしまう点は、機微情報・エラー契約の観点で修正必須です。

## 重大な問題（high）

1. **Clipboard の本文・HTML・URI が Logcat にそのまま出力されます。**
   - 該当箇所:
     - `android/unity_android_plugin/src/main/java/android/unity/clipboard/UnityAndroidClipboardManager.kt:115-166`
     - `android/unity_android_plugin/src/main/java/android/unity/clipboard/UnityClipboardJsonParser.kt:11-43`
     - `android/android_library/src/main/java/android/library/clipboard/application/usecase/CopyPlainTextUseCase.kt:18-23`
     - 同様に `CopyHtmlTextUseCase` / `CopyUriUseCase` / `CopyMultipleTextUseCase`
   - `copyPlainText` / `copyHtmlText` / `copyUri` / `copyMultipleText` は `clipboardJson` を丸ごと、UseCase は `ClipContent` を丸ごとログ出力しています。Clipboard はパスワード・トークン・個人情報を扱う可能性が高く、設計でも `isSensitive` を扱う機能です。Android のコピー確認 UI でプレビューを抑止しても、アプリ側 Logcat に本文が残ると機微情報対策が破綻します。
   - `android.md` は全パラメータの `Log.d` を要求していますが、本機能では raw value ではなく `text.length`、`htmlText.length`、`uri.scheme`、`texts.size`、`isSensitive` などのメタ情報にマスクして、ルール側の意図（メソッド入口の追跡）とセキュリティを両立してください。

2. **同期 `read()` が `ReadNotAllowed` を `"null"` に変換してしまい、設計の唯一の失敗ケースが Bridge で失われます。**
   - 該当箇所:
     - 設計書: `artifact/designs/clipboard/2026-07-25-android-clipboard-design.md:370-387`
     - Repository: `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardRepositoryImpl.kt:30-38`
     - Manager: `android/unity_android_plugin/src/main/java/android/unity/clipboard/UnityAndroidClipboardManager.kt:181-189`
   - Repository は `SecurityException` を `ClipboardDomainError.ReadNotAllowed` に変換していますが、Manager の `read(context)` は `catch (Exception)` で全例外を捕捉し、常に `"null"` を返します。そのため、設計が「唯一の失敗ケース」とした `SecurityException -> ReadNotAllowed` と、空 clipboard / 黙示的 `null` が Bridge では区別不能になります。
   - 設計のエラーコード / メッセージ対応表では `ReadNotAllowed` の Bridge 返却メッセージも定義されています。同期戻り値 API でこのエラーをどう返すかを実装に反映してください。例: error JSON を返す、read 用 listener を用意する、または同期 read は例外を握り潰さず呼び出し側へ識別可能な形式で返す。

## 改善提案（medium）

1. **URI の不正値検証が設計より弱く、`InvalidUri` が blank 以外でほぼ発生しません。**
   - 該当箇所:
     - 設計書: `artifact/designs/clipboard/2026-07-25-android-clipboard-design.md:231-233`
     - UseCase: `android/android_library/src/main/java/android/library/clipboard/application/usecase/CopyUriUseCase.kt:21-24`
     - Mapper: `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardMappers.kt:18-23`
   - UseCase は blank のみを `InvalidUri` にしており、Data 層は `Uri.parse(uri)` をそのまま `ClipData.newUri` に渡しています。`Uri.parse` は多くの文字列を構文的に受け入れるため、設計にある「パース失敗」やテスト設計の「不正 URI」が実質的に検証されません。許容 scheme（少なくとも `content://` / `file://`）や `scheme != null` など、設計上の不正 URI 条件を明確化してテストしてください。

2. **機微フラグの instrumented テストが `EXTRA_IS_SENSITIVE` を検証できていません。**
   - 該当箇所:
     - Mapper: `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardMappers.kt:33-36`
     - Test: `android/android_library/src/androidTest/java/android/library/clipboard/data/ClipboardRepositoryImplTest.kt:106-115`
   - 実装は `ClipDescription.EXTRA_IS_SENSITIVE` をセットしていますが、テストは `description != null` のみを確認しています。DoD と設計の意図は「機微フラグが extras に入る」ことなので、instrumented test では実 `ClipboardManager.primaryClipDescription.extras?.getBoolean(ClipDescription.EXTRA_IS_SENSITIVE)` まで検証してください。

## 軽微な指摘（low）

1. **新規クラスの `TAG` が android.md の「フルクラス名」指定と一致していません。**
   - ルール: `agent-rules/coding-rules/android.md:34-36`
   - 例:
     - `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardRepositoryImpl.kt:56`
     - `android/unity_android_plugin/src/main/java/android/unity/clipboard/UnityClipboardJsonParser.kt:9`
     - `android/android_library/src/main/java/android/library/clipboard/application/usecase/CopyPlainTextUseCase.kt:23`
   - `ClipboardRepositoryImpl` ではなく `android.library.clipboard.data.repository.ClipboardRepositoryImpl` のように、フルクラス名へそろえてください。

2. **`coercedText` が KDoc の説明ほど Android の `coerceToText` 相当になっていません。**
   - 該当箇所:
     - `android/android_library/src/main/java/android/library/clipboard/domain/model/ClipItemData.kt:3-10`
     - `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardMappers.kt:42-50`
   - KDoc は `ClipData.Item.coerceToText` 由来の値を期待させますが、実装は `text ?: uri.toString()` です。Context を伴う `coerceToText` を使わない方針なら、KDoc と JSON フィールド名を「fallbackText」相当に寄せるか、実際に `coerceToText(context)` を使う設計に合わせてください。

## 設計書整合性チェック

- 企画書との整合性: △（主要 API は反映済み。ただし raw log と read error contract が要修正）
- Clean Architecture 準拠: ○（Port はドメイン型のみ、Manager は UseCase 経由、Listener は Manager 層）
- 既存実装との差分分析の正確性: ○（既存ファイル変更なし、追加ファイル中心）
- テスト設計の網羅性: △（JVM unit は通過。instrumented 未実行、機微フラグ検証が不足）
- ドメインエラー全ケース実装: ○（5 ケースは定義済み）
- エラーコード/メッセージ対応表との整合: △（copy/clear は整合。read の `ReadNotAllowed` が Bridge で失われる）

## プロジェクトルール適合チェック

- common.md 準拠: ○（層・依存方向・Manager 経由は概ね準拠）
- android.md 準拠: △（Log.d は入っているが、TAG がフルクラス名ではない）
- エラー契約反映: △（`ReadNotAllowed` の同期 read 返却契約が未反映）
- 既存 API 互換性: ○（既存 API 変更なし）

## テストカバレッジ

- カバー済み:
  - UseCase の正常系・異常系・境界値
  - Unity JSON Parser の正常系・欠落キー・不正 JSON
  - JVM unit test の回帰
- 不足:
  - `UnityAndroidClipboardManager.read()` が `ReadNotAllowed` を識別可能に返すテスト
  - raw clipboard 本文をログに出さないことの確認
  - `InvalidUri` の blank 以外の不正値テスト
  - `EXTRA_IS_SENSITIVE` の extras 値そのものの instrumented 検証
  - 実機/エミュレータでの `ClipboardRepositoryImplTest` / `ClipboardChangeMonitorTest`

## 実行確認

- `git diff --check`: 成功
- `JAVA_HOME='/Applications/Android Studio Panda 1 .app/Contents/jbr/Contents/Home' ./gradlew :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest`
  - 実行場所: `android/AndroidLibraryExample`
  - 結果: `BUILD SUCCESSFUL`
  - 補足: 初回は workspace sandbox が `~/.gradle` の lock file にアクセスできず失敗したため、同一コマンドを権限付きで再実行

## 総合評価

要修正（重大）。

層構造と主要 API の実装はよくまとまっていますが、Clipboard 機能として raw content logging はリリース前に必ず潰す必要があります。また、設計レビューで最後まで詰めた `ReadNotAllowed` 契約が Bridge の同期 `read()` で消えているため、エラー返却形式を明確にして実装・テストを合わせてください。
