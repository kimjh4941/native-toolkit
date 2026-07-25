# 実装結果レポート

## 基本情報

- 日付: 2026-07-25
- 機能名: clipboard
- 対象OS: Android
- 設計書: artifact/designs/clipboard/2026-07-25-android-clipboard-design.md（v4）
- ブランチ: feature/NTKIT-12

## 1. 実装サマリー

### 1.1 設計書由来の実装

- T1: Domain 層（`ClipboardDomainError`, `ClipContent`, `ClipItemData`, `ClipReadResult`, `ClipDescriptionInfo`）を設計書どおり作成。
- T2: Port（`ClipboardRepository`）と UseCase 群（`CopyPlainTextUseCase` / `CopyHtmlTextUseCase` / `CopyUriUseCase` / `CopyMultipleTextUseCase` / `ReadClipboardUseCase` / `HasClipUseCase` / `GetClipDescriptionUseCase` / `ClearClipboardUseCase`）+ suite `ClipboardUseCases` を作成。検証ロジック（`EmptyContent` / `EmptyItemList` / `InvalidUri`）を設計どおり実装。
- T3: UseCase 単体テスト（`ClipboardUseCasesTest`、22ケース）と `MockClipboardRepository`（`copyCallCount` 等の call counter、`shouldFail` 相当の `readThrows` パターン）を common.md の Mock パターンに準拠して作成。
- T4: `ClipboardMappers`（`ClipContent.toClipData` / `ClipData.toReadResult` / `ClipDescription.toDescriptionInfo` / `applySensitiveFlag`）を作成。`EXTRA_IS_SENSITIVE` は設計どおり定数直参照（compileSdk 35 前提）。
- T5: `ClipboardRepositoryImpl`（copy/read/hasClip/getDescription/clear のみ、Listener を持たない）と factory `ClipboardUseCases(context)` を作成。`read()` は `SecurityException` のみ `ReadNotAllowed` に正規化し、null はすべて空の正常系として返す設計方針を実装。
- T6: `ClipboardRepositoryImplTest`（instrumented、9ケース）を作成。copy→read 往復、clear 後の空正常系、機微フラグ（API 33+ ガード）を検証。
- T7: `UnityClipboardSpecs` / `UnityClipboardJsonParser` + `UnityClipboardJsonParserTest`（12ケース）を既存 `UnityShareJsonParser` パターンに準拠して作成。
- T8/T9: `UnityAndroidClipboardManager` を作成。copy/clear は Listener 版（`ClipboardOperationListener`）、read/hasClip/getDescription は設計どおり同期 JSON 戻り値。ドメインエラー→errorMessage 変換を全ケース実装。
- T10: `ClipboardChangeMonitor`（Manager 層、`unity_android_plugin` 配下）が system `OnPrimaryClipChangedListener` を単独所有。二重登録 no-op、`stop()` の冪等性を実装。`ClipboardChangeMonitorTest`（instrumented、6ケース）を作成。
- T11: 全体ビルド・既存テスト回帰・Lint・Dokka を確認（詳細は 4節・5節）。

### 1.2 実装時の追加判断

- **Mapper の単体テスト配置を instrumented へ変更**（設計差分）: 設計書は `ClipboardMappersTest` を `android_library/src/test`（JVM ローカル単体テスト）に置く想定だったが、`android_library/build.gradle.kts` の `testOptions.unitTests.isReturnDefaultValues = true` により、ローカル単体テストで `ClipData.newPlainText()` 等の Android フレームワーク static メソッドはスタブの既定値（null 等）を返すのみで、Mapper のロジックを意味のある形で検証できないことが実装時に判明した。そのため Mapper の変換ロジックは `ClipboardRepositoryImplTest`（instrumented、copy→read 往復）で間接的に検証する方針に変更し、独立した `ClipboardMappersTest.kt` は作成していない。
- **`ClipboardChangeMonitorTest` の配置を instrumented へ変更**（設計差分）: 設計書のファイル一覧は `unity_android_plugin/src/test/.../ClipboardChangeMonitorTest.kt`（JVM 単体テスト）だったが、実際の `ClipboardManager.OnPrimaryClipChangedListener` 登録・発火・解除は実 Android フレームワークの挙動検証が必要なため、`unity_android_plugin/src/androidTest/.../ClipboardChangeMonitorTest.kt`（instrumented）として作成した。テスト設計セクションの「`ClipboardChangeMonitor` の instrumented テスト」という記述とは整合しているが、ファイル一覧の記載パスとは異なる。
- `ClipboardRepositoryImpl` に public KDoc を追加（既存 `ShareRepositoryImpl` は無docだが、android.md の「public class には KDoc」を優先）。

## 2. 変更ファイル

### 2.1 新規作成

android_library:
- `android/android_library/src/main/java/android/library/clipboard/domain/error/ClipboardDomainError.kt`
- `android/android_library/src/main/java/android/library/clipboard/domain/model/ClipContent.kt`
- `android/android_library/src/main/java/android/library/clipboard/domain/model/ClipItemData.kt`
- `android/android_library/src/main/java/android/library/clipboard/domain/model/ClipReadResult.kt`
- `android/android_library/src/main/java/android/library/clipboard/domain/model/ClipDescriptionInfo.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/port/ClipboardRepository.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/CopyPlainTextUseCase.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/CopyHtmlTextUseCase.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/CopyUriUseCase.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/CopyMultipleTextUseCase.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/ReadClipboardUseCase.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/HasClipUseCase.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/GetClipDescriptionUseCase.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/ClearClipboardUseCase.kt`
- `android/android_library/src/main/java/android/library/clipboard/application/usecase/ClipboardUseCases.kt`
- `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardMappers.kt`
- `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardRepositoryImpl.kt`
- `android/android_library/src/main/java/android/library/clipboard/data/repository/ClipboardUseCases.kt`
- `android/android_library/src/test/java/android/library/clipboard/application/ClipboardUseCasesTest.kt`
- `android/android_library/src/androidTest/java/android/library/clipboard/data/ClipboardRepositoryImplTest.kt`

unity_android_plugin:
- `android/unity_android_plugin/src/main/java/android/unity/clipboard/UnityClipboardSpecs.kt`
- `android/unity_android_plugin/src/main/java/android/unity/clipboard/UnityClipboardJsonParser.kt`
- `android/unity_android_plugin/src/main/java/android/unity/clipboard/UnityAndroidClipboardManager.kt`
- `android/unity_android_plugin/src/main/java/android/unity/clipboard/ClipboardChangeMonitor.kt`
- `android/unity_android_plugin/src/test/java/android/unity/clipboard/UnityClipboardJsonParserTest.kt`
- `android/unity_android_plugin/src/androidTest/java/android/unity/clipboard/ClipboardChangeMonitorTest.kt`

### 2.2 既存変更

- なし（`AndroidManifest.xml` を含め、既存ファイルへの変更は行っていない）。

### 2.3 非変更（設計上対象だが未変更）

- `android/android_library/src/test/java/android/library/clipboard/data/ClipboardMappersTest.kt`: 1.2節記載のとおり、`isReturnDefaultValues=true` の JVM 単体テストでは `ClipData` 系 API が意味のある値を返さずロジック検証にならないため作成せず、instrumented の `ClipboardRepositoryImplTest` に統合。
- `android/unity_android_plugin/src/test/java/android/unity/clipboard/ClipboardChangeMonitorTest.kt`: 実 `ClipboardManager` の listener 登録検証が必要なため `src/androidTest` 側へ配置変更。

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

設計書の全 5 ケースを `ClipboardDomainError.kt` にそのまま実装:

| DomainError | 実装 | 発生元 |
|---|---|---|
| `EmptyContent` | ○ | `CopyHtmlTextUseCase`（htmlText 空） |
| `EmptyItemList` | ○ | `CopyMultipleTextUseCase`（texts 空） |
| `InvalidUri` | ○ | `CopyUriUseCase`（uri blank） |
| `ClipboardUnavailable` | ○ | `ClipboardRepositoryImpl`（`ClipboardManager` 取得失敗） |
| `ReadNotAllowed` | ○ | `ClipboardRepositoryImpl.read()`（`SecurityException` 捕捉時のみ。null は空正常系） |

`EmptyClipboard` / `AlreadyObserving` は設計どおり定義していない（v3/v4 レビューで削除確定済み）。

### 3.2 errorCode / errorMessage 対応反映

`UnityAndroidClipboardManager.executeOperation()` で設計のエラーコード/メッセージ対応表と一致する catch チェーンを実装（`EmptyContent` → `EmptyItemList` → `InvalidUri` → `ClipboardUnavailable` → `ReadNotAllowed` → `SecurityException` → 汎用 `Exception` の順）。数値コードは既存 repo の方式（share/notification）に合わせて未使用、errorMessage 文字列のみ Bridge へ返却。

### 3.3 success時契約

- `isSuccess == true` のとき `errorMessage == null` を返す契約は `notifyOperationResult(operation, true, null)` で担保（`ClipboardUseCasesTest` の正常系テストで UseCase レベルの例外非送出を確認）。
- Bridge レベルの `isSuccess`/`errorMessage` 契約は既存 `ShareOperationListener` と同一パターンのため、Manager 実装のコードレビューで確認（instrumented/実機での Unity 側 E2E 確認は未実施、要手動確認）。

## 4. ビルド結果

- 実行コマンド:
  - `JAVA_HOME="/Applications/Android Studio Panda 1 .app/Contents/jbr/Contents/Home" ./gradlew :android_library:compileReleaseKotlin :unity_android_plugin:compileReleaseKotlin`
  - `./scripts/build_android_library_aar.sh -b release -m android_library -v 1.2.0 -o /tmp/android_library-verify.aar`
  - `./scripts/build_android_library_aar.sh -b release -m unity_android_plugin -v 1.2.0 -o /tmp/unity_android_plugin-verify.aar`
- 結果: SUCCESS（両モジュールともコンパイル成功、`[done] Created ...aar` を確認）
- 補足ログ:
  - `[done] Created /tmp/android_library-verify.aar`
  - `[done] Created /tmp/unity_android_plugin-verify.aar`

## 5. テスト結果

- 実行したテスト:
  - `./gradlew :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest`
  - `./gradlew :android_library:lintRelease :unity_android_plugin:lintRelease`
  - `./gradlew :android_library:dokkaHtml`
- 結果サマリー（clipboard 新規分）:
  - 実行件数: 34（`ClipboardUseCasesTest` 22 + `UnityClipboardJsonParserTest` 12）
  - 成功: 34
  - 失敗: 0
- 結果サマリー（既存回帰、notification/share 等）:
  - 全 suite（android_library 12 ファイル、unity_android_plugin 8 ファイル）失敗ゼロ、既存テスト回帰なし
- 失敗時の対応: 該当なし（失敗ゼロ）
- 未実施項目:
  - `ClipboardRepositoryImplTest`（instrumented, 9ケース）: 実機/エミュレータ未接続のため未実行
  - `ClipboardChangeMonitorTest`（instrumented, 6ケース）: 同上
  - 設計書「手動確認項目」（API 31/32/33/34 実機でのコピー確認 UI・機微プレビュー抑止・貼り付け通知）: 実機確認が必要なため未実施

### 5.1 テスト詳細

| テスト観点 | テストファイル | テストケース | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| copy 系 UseCase 正常/異常/境界 | `ClipboardUseCasesTest.kt` | 22ケース | ○ | JVM 単体、全 passed |
| Unity JSON パース 正常/異常/境界 | `UnityClipboardJsonParserTest.kt` | 12ケース | ○ | JVM 単体、全 passed |
| RepositoryImpl copy→read 往復・clear・機微フラグ | `ClipboardRepositoryImplTest.kt` | 9ケース | △ | instrumented、実機/エミュ未接続のため未実行（コード作成・ビルド確認のみ済） |
| Monitor start/stop/二重登録no-op/リーク防止 | `ClipboardChangeMonitorTest.kt` | 6ケース | △ | instrumented、同上 |
| 既存 notification/share 回帰 | 各既存テストファイル | 計約90ケース | ○ | 全 passed、回帰なし |
| Lint (android_library / unity_android_plugin) | - | - | ○ | `lintRelease` 成功 |
| Dokka (android_library) | - | - | ○ | `dokkaHtml` 成功 |

### 5.2 未実施ケース詳細

| テスト観点 | テストファイル | テストケース | 未実施理由 |
| --- | --- | --- | --- |
| copy→read 往復等 | `android/android_library/src/androidTest/.../ClipboardRepositoryImplTest.kt` | 9ケース全て | 実機/エミュレータ未接続（`adb devices` が空）。ローカル環境の制約 |
| 監視の発火/非発火 | `android/unity_android_plugin/src/androidTest/.../ClipboardChangeMonitorTest.kt` | 6ケース全て | 同上 |
| API 31/32/33/34 実機手動確認 | - | 設計書「手動確認項目」全て | 実機/複数APIレベルのエミュレータが必要。設計書でも「手動確認が必要」と明記された項目 |

## 6. Definition of Done

- 判定基準:
  - ○: 今回の実装・コード・テスト確認の範囲では OK かつ設計書とズレていない
  - △: 一部 OK だが、追加確認が必要
  - ×: 未達、または設計書との差分が未解消
  - -: 対象外
- ○ Domain/Application/Data/Bridge の全ファイルが追加され、既存モジュールに破壊的変更がない（既存ファイル変更ゼロを確認済み）
- △ プレーンテキスト/HTML/URI/複数テキストの copy が動作（API 31,32,33,34）— コード実装・JVM単体テストは完了。実機でのマルチAPI確認は未実施
- △ read / hasClip / getDescription が正しい JSON を返す（空は `"null"`）— 実装済み、instrumented/実機確認は未実施
- △ clear 後に `hasClip == false` — 実装・instrumentedテストコードは完成、実機実行は未実施
- △ 変更監視が start で発火・stop/clear で非発火（リークなし）、system Listener は Manager 層のみが所有 — 設計・実装は反映済み、instrumented実行は未実施
- △ 機微フラグが API 33+ でプレビュー抑止（instrumented 確認）— 実装済み、実機確認は未実施
- ○ 全 DomainError が errorMessage に正しく変換される（コードレビューで catch チェーンを確認）
- ○ UseCase 単体テスト・Parser テストが全 passed（34/34）
- △ RepositoryImpl の instrumented テストが API 31/33 で passed（API 32/34 は手動確認）— テストコードは作成済みだが実行未了
- ○ android.md 準拠（全メソッド Log.d、public KDoc）
- ○ common.md 準拠（Port ドメイン型のみ、Manager は UseCase 経由、system Listener は Manager 所有）
- ○ Intent copy/paste が Domain/Application/Port に含まれない（Out of scope 徹底、grep で残存参照なしを確認）
- ○ 既存テスト回帰なし、Lint/Dokka 通過

## 7. 設計差分

- 差分有無: あり
- 差分内容:
  1. `ClipboardMappersTest.kt`（JVM 単体テスト）を作成せず、Mapper ロジックの検証を instrumented の `ClipboardRepositoryImplTest` に統合した。
  2. `ClipboardChangeMonitorTest.kt` の配置を設計書記載の `unity_android_plugin/src/test/...`（JVM 単体）から `unity_android_plugin/src/androidTest/...`（instrumented）に変更した。
- 影響範囲:
  - いずれも「テスト実行環境の技術的制約（`isReturnDefaultValues=true` による Android フレームワーク API のスタブ化、実 `ClipboardManager` 挙動の検証必要性）」に起因する配置変更であり、テスト対象・カバレッジの縮小はない（instrumented テストとして同等以上の検証を実施する設計に変更）。
  - DoD・実装タスクの完了条件には影響しない。CI/リリースプロセスで instrumented テストが実行される場合はそのまま検証可能。

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
