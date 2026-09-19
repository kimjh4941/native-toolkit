# 実装結果レポート

## 基本情報

- 日付: 2026-07-11
- 機能名: share
- 対象OS: macOS
- 設計書: artifact/designs/share/2026-07-11-macos-share-design.md
- ブランチ: feature/NTKIT-11

## 1. 実装サマリー

### 1.1 設計書由来の実装

- T1 Domain 定義: `ShareItem` / `ShareContent` / `ShareResult`（service 名は raw String、anchor は含めない）
- T2 `ShareError` 全 8 ケース + `errorCode`/`errorMessage`（第 9 章表と一致）+ `LocalizedError`
- T3 `ShareRepository`（Port） + `SharePickerUseCase` / `ShareServiceUseCase` / `ShareServiceQueryUseCase`（入力検証集約、先頭 `Log.d`）
- T4 `ShareItemConverter`（`.text`/`.url`/`.imageFile`/`.file` → AppKit items、URL は http/https/file のみ許可、host 検証）
- T5 `SharePickerPresenter`（`NSSharingServicePickerDelegate` + `NSSharingServiceDelegate` を単独所有、anchor 解決フォールバック、continuation 単一 resume、`didChoose(nil)`=cancel／`didShareItems`=完了／`didFailToShareItems` の `NSUserCancelledError`=cancel）
- T6 `ShareRepositoryImpl`（変換 + Presenter 委譲）
- T7 `MacShareManager`（callback 版 3 種 + `async throws` 版 3 種を最初から併設、`@discardableResult`）
- T8 Unity Bridge（`UnityMacShareManager` Swift facade、`UnityMacShareJsonParser`、`UnityMacShareManagerBridge.h/.m` の C ABI、`shareContent`/`shareViaService`）
- T9 ビルド確認（Xcode 16+ file-system-synchronized groups のため `.pbxproj` への手動ファイル追加は不要。両ターゲットのビルド・成果物生成スクリプトで確認）
- テスト設計に従い UseCase / Manager / Error / Converter / JSON Parser の単体テストを実装（第 10 章の観点を網羅）

### 1.2 実装時の追加判断

- **Actor 分離の設計差分**: 設計書のコード例は `SharePickerPresenter` をクラス全体に `@MainActor` を付与していたが、実装時に `xcrun swiftc -typecheck` でビルドしたところ `SharePickerPresenter()` をデフォルト引数値として持つ `ShareRepositoryImpl.init`（nonisolated）から呼べず `error: call to main actor-isolated initializer 'init()' in a synchronous nonisolated context` になった。また `NSSharingServicePickerDelegate` はシステム側で non-isolated（同期）に定義されているため、クラス全体を `@MainActor` にすると "conformance ... crosses into main actor-isolated code" の警告も出た。
  - 対応: クラス自体は `@MainActor` を外し、AppKit UI を直接操作する 3 つの公開メソッド（`presentPicker` / `performService` / `canPerform`）と `resolveAnchorView()` のみを個別に `@MainActor` にした（`xcrun swiftc -typecheck` で 0 error/warning を確認済みのパターンを採用）。async な protocol requirement は actor-isolated な実装で満たせるため、`SharePickerPresenting` のシグネチャ・呼び出し側（`ShareRepositoryImpl`）には影響しない。
  - Delegate コールバック（`didChoose` 等）と `continuation`/`excludedServiceTitles` は non-isolated のまま。AppKit がこれらを main thread から呼ぶ前提（企画書・設計書の要検証項目と同じ前提）は変わらない。
  - 設計の意図（delegate 単独所有、continuation 単一 resume、anchor フォールバック、mouseDown 前提の明示）は変更していない。ドキュメントコメントに actor 分離の理由を追記した。
- **テスト用共有スキーム追加**: `mac/MacLibrary/MacLibrary.xcodeproj` に `MacLibraryTests` を実行する共有スキーム（`.xcscheme`）が存在せず `xcodebuild test` が `Scheme MacLibrary is not currently configured for the test action` で失敗した。`UnityMacPlugin.xcscheme` の構成を踏襲し `mac/MacLibrary/MacLibrary.xcodeproj/xcshareddata/xcschemes/MacLibrary.xcscheme` を新規追加した（Share 機能の実装ではなく、既存リポジトリのテスト実行基盤の欠落を補うインフラ変更）。
- **verify ビルドでの意図しない version bump を revert**: `scripts/build_xcode26_library_xcframework.sh -v 1.6.0` を成果物生成確認のため実行したところ、スクリプトの仕様で `project.pbxproj` の `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` が実際に書き換えられた。任意のバージョン番号だったため、確認後に `git checkout` で両 `.pbxproj` の当該変更のみ破棄した（ソースコード変更は含まれていないことを diff で確認済み）。

## 2. 変更ファイル

### 2.1 新規作成

- `mac/MacLibrary/MacLibrary/Share/Domain/Model/ShareItem.swift`
- `mac/MacLibrary/MacLibrary/Share/Domain/Model/ShareContent.swift`
- `mac/MacLibrary/MacLibrary/Share/Domain/Model/ShareResult.swift`
- `mac/MacLibrary/MacLibrary/Share/Domain/Error/ShareError.swift`
- `mac/MacLibrary/MacLibrary/Share/Application/Port/ShareRepository.swift`
- `mac/MacLibrary/MacLibrary/Share/Application/UseCase/ShareUseCases.swift`
- `mac/MacLibrary/MacLibrary/Share/Data/Converter/ShareItemConverter.swift`
- `mac/MacLibrary/MacLibrary/Share/Data/Repository/ShareRepositoryImpl.swift`
- `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift`
- `mac/MacLibrary/MacLibrary/Share/MacShareManager.swift`
- `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareJsonParser.swift`
- `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareManager.swift`
- `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareManagerBridge.h`
- `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareManagerBridge.m`
- `mac/MacLibrary/MacLibraryTests/Share/Mock/MockShareRepository.swift`
- `mac/MacLibrary/MacLibraryTests/Share/ShareErrorTests.swift`
- `mac/MacLibrary/MacLibraryTests/Share/ShareItemConverterTests.swift`
- `mac/MacLibrary/MacLibraryTests/Share/ShareUseCasesTests.swift`
- `mac/MacLibrary/MacLibraryTests/Share/MacShareManagerTests.swift`
- `mac/UnityMacPlugin/UnityMacPluginTests/Share/UnityMacShareJsonParserTests.swift`
- `mac/MacLibrary/MacLibrary.xcodeproj/xcshareddata/xcschemes/MacLibrary.xcscheme`（実装時追加判断。既存テスト実行基盤の欠落を補うインフラファイル）

### 2.2 既存変更

- なし（Share モジュールは既存ファイルを変更せず新規追加のみ。`agent-rules/coding-rules/mac.md` は本タスク以前の別作業での変更で、今回のコード実装では変更していない）

### 2.3 非変更（設計上対象だが未変更）

- `mac/MacLibrary/MacLibrary.xcodeproj/project.pbxproj` / `mac/UnityMacPlugin/UnityMacPlugin.xcodeproj/project.pbxproj`: Xcode 16+ の file-system-synchronized groups（`PBXFileSystemSynchronizedRootGroup`）を両プロジェクトが採用しているため、`Share/` 配下へのファイル追加は自動的にビルド対象へ含まれる。手動編集は不要と確認した。

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

- `ShareError` の全 8 ケース（`noValidItems` / `invalidURL` / `imageLoadFailed` / `fileNotFound` / `noAnchorView` / `serviceUnavailable` / `presentationFailed` / `unknown`）を実装し、設計書第 8 章と一致。`ShareErrorTests` で全ケースの `errorCode` と `errorMessage` を検証済み。

### 3.2 errorCode / errorMessage 対応反映

- 設計書第 9 章の対応表（1401〜1499、"Invalid share content JSON." 含む）と実装（`ShareError.errorCode`/`errorMessage`、`UnityMacShareManager` の JSON 不正時メッセージ）が一致することを確認。

### 3.3 success時契約

- `isSuccess == true` のとき `errorMessage == nil` であることを `MacShareManagerTests`（`shareCompletionSucceedsWithChosenService` / `shareCompletionReflectsCancellation`）で確認。
- 注: 本設計の Bridge callback 契約は数値 `errorCode` を返却しない方式（iOS Share と統一、文字列メッセージのみ）のため、`errorCode == 0` の検証は対象外（設計書第 9 章の注記どおり）。`isSuccess == false` のとき `errorMessage` が非 nil であることは各失敗系テストで確認済み。

## 4. ビルド結果

- 実行コマンド:
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary -configuration Debug build`
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -configuration Debug build`
  - `./scripts/build_xcode26_library_xcframework.sh -c release -m MacLibrary -v 1.6.0 -o /tmp/MacLibrary-verify.xcframework --minimum-macos 15.0`
  - `./scripts/build_xcode26_library_xcframework.sh -c release -m UnityMacPlugin -v 1.6.0 -o /tmp/UnityMacPlugin-verify.xcframework --minimum-macos 15.0`
- 結果: SUCCESS（4 件とも）
- 補足ログ（必要箇所のみ）:
  - MacLibrary / UnityMacPlugin 通常ビルド: `** BUILD SUCCEEDED **`
  - xcframework 生成スクリプト: `** ARCHIVE SUCCEEDED **` + `[done] [MacLibrary] Created /tmp/MacLibrary-verify.xcframework` / `[done] [UnityMacPlugin] Created /tmp/UnityMacPlugin-verify.xcframework`
  - 生成物確認後、検証用 xcframework は `/tmp` から削除済み。スクリプトが `project.pbxproj` の version フィールドを書き換えたため、確認後に該当差分のみ `git checkout` で revert 済み（1.2 節参照）
  - UnityMacPlugin ビルド時の警告 1 件（`UnityMacNotificationJsonParser.swift:198` の switch 網羅性、Notification 機能の既存コード。Share 実装とは無関係で本タスクでは対応していない）

## 5. テスト結果

- 実行したテスト:
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary -destination 'platform=macOS' test`
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS' test`
- 結果サマリー:
  - MacLibrary: `** TEST SUCCEEDED **`（既存 Notification/Dialog テスト含め全件 passed。Share 関連新規テスト 38 件すべて passed）
  - UnityMacPlugin: `** TEST SUCCEEDED **`（既存 Notification テスト含め全件 passed。`UnityMacShareJsonParserTests` 12 件すべて passed）
  - 失敗: 0 件
- 失敗時の対応:
  - 該当なし（1 件のみ実装時に修正が必要だった: `SharePickerPresenter` の actor 分離、1.2 節参照。テスト実行前にビルドエラーとして検出・修正済み）
- 未実施項目（あれば）:
  - 実機での UI 手動確認（ピッカー表示、各共有先への送信、`mouseDown` 制約下での安定性、`excludedServiceTitles` の実際の非表示挙動、`recipients`/`subject` の反映、entitlement 依存箇所）: 理由は 6 章参照

### 5.1 テスト詳細

| テスト観点 | テストファイル | テストケース | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| ShareError 全ケースの errorCode | ShareErrorTests.swift | noValidItemsHasCode1401 ほか7件 | ○ | 第9章表と一致 |
| ShareError 全ケースの errorMessage | ShareErrorTests.swift | noValidItemsMessage ほか6件 | ○ | 英語メッセージ |
| ShareItemConverter .text/.url/.file/.imageFile 変換 | ShareItemConverterTests.swift | textConvertsToString ほか | ○ | 正常系 |
| ShareItemConverter URL 検証(scheme/host) | ShareItemConverterTests.swift | emptyURLThrowsInvalidURL / schemelessURLThrowsInvalidURL / httpsURLWithoutHostThrowsInvalidURL / ftpURLThrowsInvalidURL | ○ | 異常系境界値 |
| ShareItemConverter 順序保持 | ShareItemConverterTests.swift | conversionPreservesInputOrder | ○ | - |
| SharePickerUseCase 正常/異常/境界 | ShareUseCasesTests.swift | pickerExecuteReturnsStubbedResultAndCallsRepositoryOnce ほか | ○ | items空でnoValidItems |
| ShareServiceUseCase 正常/異常/境界 | ShareUseCasesTests.swift | serviceExecuteReturnsStubbedResult ほか | ○ | serviceName空でserviceUnavailable |
| ShareServiceQueryUseCase | ShareUseCasesTests.swift | canPerformReturnsStubbedValue ほか | ○ | - |
| MacShareManager callback版(picker) 完了/キャンセル/失敗 | MacShareManagerTests.swift | shareCompletionSucceedsWithChosenService / shareCompletionReflectsCancellation / shareCompletionReturnsFailureMessageOnError | ○ | isSuccess/completed/errorMessage契約 |
| MacShareManager callback版(direct service) | MacShareManagerTests.swift | shareViaServiceCompletionSucceeds / shareViaServiceCompletionReturnsFailureMessageOnError | ○ | - |
| MacShareManager async throws版 | MacShareManagerTests.swift | shareAsyncReturnsResult / shareAsyncThrowsTypedError / canPerformReturnsStubbedValue | ○ | 型付きShareError伝播 |
| UnityMacShareJsonParser 4種type/未知type/欠落無視 | UnityMacShareJsonParserTests.swift | parsesAllFourItemTypes / unknownTypeIsIgnored / missingValueEntryIsIgnored / allIgnoredResultsInEmptyItems | ○ | - |
| UnityMacShareJsonParser recipients/subject/excludedServiceTitles | UnityMacShareJsonParserTests.swift | recipientsSubjectAndExcludedServiceTitlesAreReflected / recipientsSubjectExcludedServiceTitlesDefaultWhenAbsent | ○ | - |
| UnityMacShareJsonParser 構文不正 | UnityMacShareJsonParserTests.swift | malformedJsonReturnsNil / missingItemsKeyReturnsNil | ○ | - |

### 5.2 未実施ケース詳細

| テスト観点 | テストファイル | テストケース | 未実施理由 |
| --- | --- | --- | --- |
| `SharePickerPresenter` の delegate 挙動（実 UI・システム delegate 依存） | - | ピッカー表示・選択・完了/キャンセルのシステム連動 | 設計書第10章の方針どおり、`SharePickerPresenting` を Mock 化して上位層で検証する対象外設計。実 AppKit UI 依存のため自動テスト不可、手動確認が必要 |
| ボタン押下起点での `mouseDown` 制約下のピッカー安定表示 | - | 設計書 T5/T8 完了条件・分岐A/B/C判断 | 実機・実UIでのユーザー操作起点呼び出しが必要。自動テストで再現不可 |
| Mail/メッセージ/AirDrop/メモ/コピー等、実際の共有先への送信内容確認 | - | - | 実 macOS 環境・実サービスとの連携が必要 |
| `excludedServiceTitles` の実UIでの非表示確認（ローカライズ依存の限界含む） | - | - | 表示名ベースのbest-effort挙動は実UIでのみ検証可能 |
| entitlement/サンドボックス依存（ファイル共有・AirDrop） | - | - | 配布形態別の実機検証が必要。設計書第14章の要検証項目 |
| `didFailToShareItems` の cancel error 判定（`NSUserCancelledError`）の実挙動確認 | - | - | 設計書第14章の要検証項目。実サービスでのキャンセル操作が必要 |

## 6. Definition of Done

- 判定基準:
  - ○: 今回の実装・コード・テスト確認の範囲では OK かつ設計書とズレていない
  - △: 一部 OK だが、追加確認が必要
  - ×: 未達、または設計書との差分が未解消
  - -: 対象外

### 実装・テスト

- ○ `Share` モジュールが Clean Architecture 層構成で追加されている（Domain/Application/Data/Presentation/Manager/Bridge）
- ○ Port はドメイン型 + raw String のみ、AppKit 型が Domain/Application に漏れていない
- ○ `NSSharingServicePickerDelegate` / `NSSharingServiceDelegate` は `SharePickerPresenter` の1クラスのみが実装している
- ○ 全 public/internal/@objc/override/Bridge 関数に先頭 `Log.d`/`Log.e` が付与されている
- ○ `ShareError` 全ケースと errorCode/英語メッセージが第9章の表と一致する
- ○ UseCase / Manager / Parser / Error / Converter の単体テストが green（正常・異常・境界）
- ○ 両ターゲット（MacLibrary / UnityMacPlugin）がビルド成功

### 動作（実機）

- △ ボタン押下起点でピッカーを表示でき、テキスト / URL / 画像 / ファイルを共有できる（コード実装・単体テストは完了。実機UI確認は未実施）
- - Mail / メッセージ / AirDrop / メモ / コピー の各共有先で内容が正しい（実機確認が必要、対象外扱いではなく未実施のため△相当だが実施手段が実機のみのため「-」ではなく要実施として明記）
- △ `excludedServiceTitles` でサービスを除外できる（コードロジックはテスト済み。実UIでの非表示・ローカライズ限界の確認は未実施）
- △ 直接実行（`shareViaService`）で `recipients`/`subject` が反映される（コード・単体テストは完了。実サービスでの反映確認は未実施）
- △ ピッカー未選択(cancel)と共有完了、サービス内キャンセルを区別できる（ロジック・delegateマッピングは実装済み。実機でのdelegate発火順・cancel error判定は要検証第14章のまま）
- ○ メインスレッドで表示・コールバックされる（`Task { @MainActor in }` / `DispatchQueue.main.async` で保証、コードレベルで確認）
- △ Unity Bridge経由で共有を起動でき、結果コールバックが返る（C ABI/facade/parserは実装・ビルド確認済み。実Unity環境での起動確認は未実施）

## 7. 設計差分

- 差分有無: あり（軽微、実装ブロッカーではない）
- 差分内容:
  - `SharePickerPresenter` の actor 分離方法: 設計書のコード例はクラス全体に `@MainActor` を付与していたが、`ShareRepositoryImpl.init` のデフォルト引数（nonisolated コンテキスト）からの構築と、AppKit の non-isolated `NSSharingServicePickerDelegate` 適合が両立しないビルドエラー・警告が実装時に判明したため、クラスは非isolatedのまま、AppKitを操作する3メソッド（`presentPicker`/`performService`/`canPerform`）と `resolveAnchorView()` のみを個別に `@MainActor` にする方式へ変更した。
  - `mac/MacLibrary/MacLibrary.xcodeproj/xcshareddata/xcschemes/MacLibrary.xcscheme` を新規追加（設計書に記載のないインフラファイル。既存プロジェクトにテスト実行用の共有スキームが存在しなかったための追加）。
- 影響範囲:
  - actor 分離の変更は `SharePickerPresenting` のシグネチャ・呼び出し側（`ShareRepositoryImpl`、テストの `MockShareRepository`）に影響なし。delegate 単独所有・continuation 単一 resume・anchor フォールバック・mouseDown 前提などの設計意図は保持されている。
  - `.xcscheme` 追加はビルド・テストの実行可否のみに影響し、Share機能のランタイム動作には影響しない。

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
