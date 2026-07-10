# 実装結果レポート

## 基本情報

- 日付: 2026-07-04
- 機能名: share
- 対象OS: iOS
- 設計書: artifact/designs/share/2026-07-04-ios-share-design.md
- ブランチ: feature/NTKIT-10

## 1. 実装サマリー

### 1.1 設計書由来の実装

- T1: Domain 定義（`ShareItem` / `ShareContent` / `ShareResult`）を設計どおり実装
- T2: `ShareError`（全 7 ケース）+ `LocalizedError` 準拠を設計どおり実装
- T3: Port（`ShareRepository`）+ `ShareContentUseCase`（items 空チェック → `noValidItems`）を設計どおり実装
- T4: `ShareSheetPresenter`（root VC 解決、iPad popover 中央フォールバック、continuation の単一 resume ガード、提示前失敗判定）を設計どおり実装
- T5: `ShareRepositoryImpl`（URL/file/image 変換、URL scheme 検証、primary item 置き換えルール）+ `ShareItemSource` を設計どおり実装
- T6: `IosShareManager`（公開API、`(Bool, Bool, String?, String?)` コールバック）を設計どおり実装
- T7: Unity Bridge（`UnityIosShareManager` facade、`UnityIosShareJsonParser`、`UnityIosShareManagerBridge.h/.m`）を設計どおり実装
- T8: Xcode プロジェクトへのファイル追加（`PBXFileSystemSynchronizedRootGroup` により自動認識、pbxproj 手動編集は不要と判明）、両ターゲットのビルド確認

### 1.2 実装時の追加判断

- **`ShareRepositoryImpl` のアクセスレベルを `public` から internal（デフォルト）へ変更**（設計差分。詳細は第7章）。設計書は `public final class ShareRepositoryImpl` かつ `public init(presenter: ShareSheetPresenting = ShareSheetPresenter(), ...)` としていたが、`ShareSheetPresenting` / `ShareSheetPresenter` が internal のため、public init のデフォルト引数に internal 型を使えずビルドエラーとなった。Presentation 層（UIKit 依存）を internal に留める設計意図を優先し、`ShareRepositoryImpl` 自体を internal にした。`IosShareManager`（public）が `ShareRepository`（public protocol）型のプロパティとして internal な実装を保持する形は同一モジュール内で問題なく成立する。
- `ShareSheetPresenter` の popover 設定は `sourceView`/`sourceRect` を root view 中央に固定するシンプルな実装とした（`IosDialogManager.showActionSheet` 同様の外部指定オプションは Share の設計スコープに含まれないため省略）。

## 2. 変更ファイル

### 2.1 新規作成

- `ios/IosLibrary/IosLibrary/Share/Domain/Model/ShareItem.swift`
- `ios/IosLibrary/IosLibrary/Share/Domain/Model/ShareContent.swift`
- `ios/IosLibrary/IosLibrary/Share/Domain/Model/ShareResult.swift`
- `ios/IosLibrary/IosLibrary/Share/Domain/Model/ShareError.swift`
- `ios/IosLibrary/IosLibrary/Share/Application/Port/ShareRepository.swift`
- `ios/IosLibrary/IosLibrary/Share/Application/UseCase/ShareUseCases.swift`
- `ios/IosLibrary/IosLibrary/Share/Presentation/ShareSheetPresenter.swift`
- `ios/IosLibrary/IosLibrary/Share/Data/ItemSource/ShareItemSource.swift`
- `ios/IosLibrary/IosLibrary/Share/Data/Repository/ShareRepositoryImpl.swift`
- `ios/IosLibrary/IosLibrary/Share/IosShareManager.swift`
- `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareJsonParser.swift`
- `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManager.swift`
- `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManagerBridge.h`
- `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManagerBridge.m`
- `ios/IosLibrary/IosLibraryTests/Share/Application/Mock/MockShareRepository.swift`
- `ios/IosLibrary/IosLibraryTests/Share/Application/ShareContentUseCaseTests.swift`
- `ios/IosLibrary/IosLibraryTests/Share/Domain/ShareErrorTests.swift`
- `ios/IosLibrary/IosLibraryTests/Share/Presentation/IosShareManagerTests.swift`
- `ios/IosLibrary/IosLibraryTests/Share/Data/Mock/MockShareSheetPresenter.swift`
- `ios/IosLibrary/IosLibraryTests/Share/Data/ShareRepositoryImplTests.swift`
- `ios/UnityIosPlugin/UnityIosPluginTests/Share/UnityIosShareJsonParserTests.swift`

### 2.2 既存変更

- なし（既存ファイルへの変更はない。`IosLibrary.xcodeproj` / `UnityIosPlugin.xcodeproj` は `PBXFileSystemSynchronizedRootGroup` のため、新規ファイル追加に伴う pbxproj への手動追記は不要）

### 2.3 非変更（設計上対象だが未変更）

- なし

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

全 7 ケースを `ShareError.swift` に実装済み（設計書 第8章と一致）:

- `noValidItems`
- `invalidURL(String)`
- `imageLoadFailed(path:)`
- `fileNotFound(path:)`
- `noRootViewController`
- `presentationFailed(Error)`
- `unknown(Error)`

`LocalizedError.errorDescription` を全ケースで実装し、`ShareErrorTests`（7件）で英語メッセージを検証済み。

### 3.2 errorCode / errorMessage 対応反映

設計書は数値エラーコードを採用せず `(isSuccess, completed, activityType, errorMessage)` の文字列メッセージ方式（既存 Notification/Dialog Bridge と同一方式）。第9章の対応表と実装（`IosShareManager.share`, `UnityIosShareManagerBridge.m`）が一致することを `IosShareManagerTests` で確認済み。

| ケース | 実装確認 |
| --- | --- |
| 共有完了 | `IosShareManagerTests/shareReturnsSuccessAndCompletedOnHappyPath` で確認 |
| ユーザーキャンセル | `IosShareManagerTests/shareReturnsSuccessWithNotCompletedOnCancel` で確認 |
| items 空/全無効 | `ShareContentUseCaseTests/executeThrowsNoValidItemsWhenEmpty` で確認 |
| URL 不正 | `ShareRepositoryImplTests/buildActivityItemsRejectsInvalidURLs` で確認 |
| 画像読込失敗 | `ShareRepositoryImplTests/buildActivityItemsThrowsImageLoadFailedForInvalidImage` で確認 |
| ファイル不在 | `ShareRepositoryImplTests/buildActivityItemsThrowsFileNotFoundForMissingFile` で確認 |
| root VC なし / 提示失敗 | Presenter 実装のみ（実機依存のため自動テスト対象外、手動確認が必要） |
| JSON 不正（Bridge） | `UnityIosShareJsonParserTests/parseContentInvalidJsonReturnsNil` で確認（`nil` 返却は確認済み。Bridge 側の `"Invalid share content JSON."` 文言分岐は `UnityIosShareManager.share` のコードレビューで確認、専用ユニットテストは未追加） |

### 3.3 success時契約

- `isSuccess == true` のとき `errorMessage == nil` であることを `IosShareManagerTests` の完了・キャンセルケースで確認済み（本設計は数値 `errorCode` を持たないため、`errorCode == 0` 契約は対象外）。

## 4. ビルド結果

- 実行コマンド:
  - `xcodebuild -project ios/IosLibrary/IosLibrary.xcodeproj -scheme IosLibrary -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - `xcodebuild -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17' build`
  - `./scripts/build_ios_library_xcframework.sh -c release -m IosLibrary -v 1.1.0 -o /tmp/IosLibrary-share-verify.xcframework`
  - `./scripts/build_ios_library_xcframework.sh -c release -m UnityIosPlugin -v 1.1.0 -o /tmp/UnityIosPlugin-share-verify.xcframework`
- 結果: SUCCESS（4件とも）
- 補足ログ:
  - `IosLibrary` 単体プロジェクトビルド: `** BUILD SUCCEEDED **`
  - `UnityIosPlugin` は単体プロジェクトビルドで `Unable to find module dependency: 'IosLibrary'` エラーが発生（`IosLibrary.framework` がワークスペース経由の依存参照のため）。`IosWorkspace.xcworkspace` 経由のビルドに切り替えて解消し `** BUILD SUCCEEDED **`
  - xcframework 生成（両モジュール）: `** ARCHIVE SUCCEEDED **` および `[done] ... Created ...xcframework` を確認
  - 検証用生成物（`/tmp/IosLibrary-share-verify.xcframework` 等）はレポート作成前に削除済み

## 5. テスト結果

- 実行したテスト:
  - `xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme IosLibrary -destination 'platform=iOS Simulator,name=iPhone 17'`
  - `xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin -destination 'platform=iOS Simulator,name=iPhone 17'`
- 結果サマリー:
  - IosLibraryTests: 実行 62件 / 成功 62件 / 失敗 0件（うち Share 関連 27件）
  - UnityIosPluginTests: 実行 48件 / 成功 48件 / 失敗 0件（うち Share JSON Parser 7件）
- 失敗時の対応: 失敗なし
- 未実施項目:
  - 実機/シミュレータでの共有シート手動確認（Mail / Messages / Files / AirDrop / コピー への実共有、iPad popover 表示、プレビュー即時表示、キャンセル操作）: UI プレゼンテーションを伴うため自動テスト範囲外。設計書 第10章「統合テスト / 手動確認」に対応する手動確認が必要
  - Unity 側（C#）からの P/Invoke 実呼び出し確認: Unity プロジェクト側の統合作業が別スコープのため未実施

### 5.1 テスト詳細

| テスト観点 | テストファイル | テストケース | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| UseCase 正常系 | ShareContentUseCaseTests.swift | executeCallsRepositoryAndReturnsResult | ○ | |
| UseCase 異常系 | ShareContentUseCaseTests.swift | executePropagatesRepositoryError | ○ | |
| UseCase 境界値 | ShareContentUseCaseTests.swift | executeThrowsNoValidItemsWhenEmpty | ○ | |
| Manager 完了 | IosShareManagerTests.swift | shareReturnsSuccessAndCompletedOnHappyPath | ○ | |
| Manager キャンセル | IosShareManagerTests.swift | shareReturnsSuccessWithNotCompletedOnCancel | ○ | |
| Manager 失敗 | IosShareManagerTests.swift | shareReturnsFailureOnRepositoryError | ○ | |
| Error 全ケース | ShareErrorTests.swift | 7 テストケース | ○ | errorDescription 英語メッセージ確認 |
| URL 検証（成功） | ShareRepositoryImplTests.swift | buildActivityItemsAcceptsValidURLs (3件) | ○ | https/http/file |
| URL 検証（失敗） | ShareRepositoryImplTests.swift | buildActivityItemsRejectsInvalidURLs (5件) | ○ | 空/空白/scheme無/host無/ftp |
| ファイル存在 | ShareRepositoryImplTests.swift | buildActivityItemsAcceptsExistingFile | ○ | |
| ファイル不在 | ShareRepositoryImplTests.swift | buildActivityItemsThrowsFileNotFoundForMissingFile | ○ | |
| 画像読込失敗 | ShareRepositoryImplTests.swift | buildActivityItemsThrowsImageLoadFailedForInvalidImage | ○ | |
| ItemSource置換（subject） | ShareRepositoryImplTests.swift | buildActivityItemsReplacesPrimaryItemWhenSubjectProvided | ○ | 重複しないことを確認 |
| ItemSource置換（preview） | ShareRepositoryImplTests.swift | buildActivityItemsReplacesPrimaryItemWhenPreviewTitleProvided | ○ | |
| ItemSource非置換 | ShareRepositoryImplTests.swift | buildActivityItemsDoesNotWrapWhenNoMetadataProvided | ○ | |
| excluded変換 | ShareRepositoryImplTests.swift | presentConvertsExcludedActivityTypesAndDelegatesToPresenter | ○ | Mock Presenter 経由 |
| JSON Parser 全型 | UnityIosShareJsonParserTests.swift | parseContentParsesAllFourTypes | ○ | |
| JSON Parser URL非検証 | UnityIosShareJsonParserTests.swift | parseContentKeepsUnvalidatedUrlString | ○ | |
| JSON Parser 無視規則 | UnityIosShareJsonParserTests.swift | parseContentIgnoresUnknownTypeAndMissingValue | ○ | |
| JSON Parser 全無視 | UnityIosShareJsonParserTests.swift | parseContentReturnsEmptyItemsWhenAllIgnored | ○ | |
| JSON Parser 不正JSON | UnityIosShareJsonParserTests.swift | parseContentInvalidJsonReturnsNil | ○ | |
| JSON Parser 任意項目 | UnityIosShareJsonParserTests.swift | parseContentWithOptionalFields | ○ | |
| JSON Parser 必須欠落 | UnityIosShareJsonParserTests.swift | parseContentMissingItemsReturnsNil | ○ | |

### 5.2 未実施ケース詳細

| テスト観点 | テストファイル | テストケース | 未実施理由 |
| --- | --- | --- | --- |
| 実共有シート表示・共有先の内容確認 | - | Mail/Messages/Files/AirDrop/コピーへの実共有 | UIActivityViewController の実表示・実共有はUI自動化なしでは検証不可。実機/シミュレータでの手動確認が必要 |
| iPad popover 非クラッシュ確認 | - | iPad実機/シミュレータでの提示 | UIプレゼンテーション依存。手動確認が必要 |
| previewTitle 即時プレビュー | - | 共有シートヘッダの実表示確認 | UI依存。手動確認が必要 |
| root VC なし / 提示失敗の実機確認 | - | ShareSheetPresenterのUIKit分岐 | root VC解決はUIApplication.shared依存のためユニットテストでモック困難。手動確認が必要 |
| Unity C# 側からの呼び出し確認 | - | shareContent(...) のP/Invoke実行 | Unity側プロジェクトの統合はスコープ外 |

## 6. Definition of Done

- 判定基準:
  - ○: 今回の実装・コード・テスト確認の範囲では OK かつ設計書とズレていない
  - △: 一部 OK だが、追加確認が必要
  - ×: 未達、または設計書との差分が未解消
  - -: 対象外

### 実装・テスト

- ○ `Share` モジュールが Clean Architecture 層構成で追加されている（Domain/Application/Data/Presentation/Manager/Bridge）
- ○ Port はドメイン型のみ、UIKit 型が Domain/Application に漏れていない
- ○ 全 public/@objc/Bridge 関数に先頭 `Log.d`/`Log.e` が付与されている
- ○ `ShareError` 全ケースと英語メッセージが第9章の表と一致する
- ○ UseCase / Manager / Parser / Error の単体テストが green（正常・異常・境界）
- ○ `ShareRepositoryImplTests` が green（URL scheme 検証、file/image 変換、excluded activity 変換、primary item 置き換えで item 数が重複しない）
- ○ 両ターゲット（IosLibrary / UnityIosPlugin）がビルド成功

### 動作（実機/シミュレータ）

- △ テキスト / URL / 画像 / ファイルを共有できる（Data層の変換ロジックはテスト済みだが、実共有シートでの動作は手動確認が必要）
- △ Mail / Messages / Files / AirDrop / コピー の各共有先で内容が正しい（手動確認が必要）
- △ iPhone / iPad で表示でき、iPad で popover クラッシュしない（手動確認が必要）
- △ `previewTitle` でヘッダプレビューが即時表示される（手動確認が必要）
- △ `excludedActivityTypes` で共有先を除外できる（変換ロジックはテスト済み、実際の非表示確認は手動確認が必要）
- ○ キャンセル（completed=false）と失敗（errorMessage 非 nil）を区別できる（ユニットテストで確認済み）
- △ Unity Bridge 経由で共有シートを起動でき、結果コールバックが返る（Swift側のBridge実装とJSONパース・Manager連携はテスト済み。Unity C#側からの実呼び出しは未実施）

## 7. 設計差分

- 差分有無: あり
- 差分内容:
  - `ShareRepositoryImpl` のアクセスレベルを設計書の `public` から internal（デフォルト）へ変更した。設計書の `public init(presenter: ShareSheetPresenting = ShareSheetPresenter(), fileManager: FileManager = .default)` は、`ShareSheetPresenting`/`ShareSheetPresenter` が internal であるため「public な初期化子が internal 型をデフォルト引数に使用できない」というSwiftのアクセスレベル制約に抵触し、コンパイルエラーとなった。
- 影響範囲:
  - `ShareRepositoryImpl` を外部モジュールから直接インスタンス化することはできなくなるが、設計上これは意図された利用経路ではない（`IosShareManager` が内部で生成し `ShareRepository` protocol 経由で公開する）。テストコードは `@testable import IosLibrary` で internal 型にアクセスできるため、設計書のテスト設計（`ShareRepositoryImplTests`）は影響なく実施できた。公開 API サーフェス（`ShareRepository`, `ShareContentUseCase`, `IosShareManager`, Domain モデル）には変更がなく、外部（Unity Bridge）への影響はない。

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
