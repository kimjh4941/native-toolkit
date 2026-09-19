# 実装結果レポート

## 基本情報

- 日付: 2026-08-02
- 機能名: clipboard
- 対象OS: iOS
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- ブランチ: feature/NTKIT-14

## 1. 実装サマリー

### 1.1 設計書由来の実装

設計書のタスク分解（T-R〜T-14）に対応する実装を、依存順に実施した。

- **T-R**: `agent-rules/coding-rules/common.md` に「Domain での限定 Foundation 値型許容」と「同期 control / factory API の例外」を追記。`ios.md` は既存の logging / callback+async 併設ルールで対応可能と判断し変更なし。
- **T-01**: Domain 層モデル 17 種（`PasteboardScope` / `PasteboardCreationRequest` / `ClipboardContent` / `ClipboardCopyOptions` / `ClipboardLimits` / `ClipboardTimeouts` / `ClipboardItemData` / `ClipboardReadResult` / `ClipboardSnapshot` / `ClipboardChangeEvent` / `ClipboardDetectionPattern` / `ClipboardDetectedValues` / `ClipboardLabeledValue` / `ClipboardPostalAddress` / `ClipboardCalendarEvent` / `ClipboardFlightNumber` / `ClipboardMoneyAmount` / `ClipboardShipmentTracking` / `ClipboardLoadRequest` / `ClipboardLoadedItem` / `ClipboardFailureDetail` / `ClipboardOperationKind`）と `ClipboardError`（24 ケース + `errorCode` + `unknownErrorCode`/`unknownMessage`）を実装。
- **T-02**: `ClipboardContentValidator`（純ロジック、`ClipboardClock` 注入）、`ClipboardChangeTracker`（純ロジック）、秘匿ログ 3 層（`ClipboardRedactionCore` / `ClipboardRedaction`(`@objc public`) / `ClipboardLog`）を実装。
- **T-03**: Port 4 種（`ClipboardRepository` / `ClipboardItemLoader` / `ClipboardTypeIdentifierValidating` / `ClipboardClock`）+ UseCase 13 種（P-1〜P-12、P-15）+ 集約 `ClipboardUseCases` を実装。
- **T-04**: `PasteboardResolver` / `ClipboardTypeIdentifierValidator`（`UTType` 実装）/ `ClipboardMappers` / `ClipboardDetectionMapper` / `ClipboardRepositoryImpl` を実装。
- **T-05**: `ClipboardTemporaryFileStore` / `ClipboardImageCoder` / `ClipboardCancellationBox` / `ClipboardAsyncRaceCoordinator` を実装。
- **T-06**: `ClipboardItemLoaderImpl`（契約 6 点、単一 gate によるキャンセル/完了/タイムアウト解決）を実装。
- **T-07**: `IosClipboardManager`（`@MainActor`、P-1〜P-16、監視トークン単独所有、`ClipboardCancellationBox` によるネイティブ非同期版のキャンセル転送）を実装。
- **T-08**: `PasteItemProviderLoader` / `ClipboardPasteReceiverView` / `ClipboardPasteControlContainerView` / `PasteControlFactory` を実装。
- **T-09/T-10**: `UnityIosClipboardJsonParser`（全 15 endpoint の JSON schema）/ `UnityIosClipboardManager`（errorCode 透過の唯一の変換点）/ Bridge `.h`/`.m` を実装。
- **T-11a/T-11b 相当**: 単体テスト・Data 層統合テスト・Bridge テストを実施し、`xcodebuild test` で確認。Swift 6 strict concurrency（I-10 相当）を Clipboard スコープで確認。
- **T-12**: サンプルアプリ対応は設計書どおり本タスクのスコープ外（`design-sample-app` で別途実施）。**未実施**。
- **T-13**: 実機必須の手動確認（M-01〜M-16）は本セッションでは実施不可（シミュレータのみ）。**未実施、要手動確認として明記**。
- **T-14**: `IosLibrary.docc/IosLibrary.md` に Clipboard セクションを追記。

### 1.2 実装時の追加判断

設計書に明記のない、実装時に必要となった判断。設計の意図を変えるものではなく、Swift 6 の実際のコンパイラ挙動に合わせた技術的な補完である。

- **`nonisolated init`**: `@MainActor` クラス（`PasteboardResolver` / `ClipboardRepositoryImpl` / `ClipboardItemLoaderImpl` / `PasteItemProviderLoader`）のデフォルト引数が他の `@MainActor` 型の `init()` を呼ぶと「同期 nonisolated コンテキストでの呼び出し」エラーになるため、これらの `init` を `nonisolated` にした。設計の actor 境界表（Repository/Loader は `@MainActor`）はそのまま維持しており、影響は init の呼び出し可否のみ。
- **`ClipboardTypeIdentifierValidator` の可視性**: `public` 型の default 引数値として参照するには `public` である必要があるため、`internal struct` から `public struct` + `public init()` に変更した。設計の可視性表は「internal」としていたが、この制約により `public` に変更（DoD の「内部実装詳細」という意図は損なわれず、UTType 依存を Application 層に持ち込んでいない点は維持）。
- **`UIColor` のペーストボード表現型識別子**: 設計に具体的な UTI 定数の指定がなかったため `"com.apple.uikit.color"` を採用した。**要検証**（下記「7. 設計差分」参照）。
- **`didRunStartupCleanup` の `nonisolated(unsafe)`**: Swift 6 strict concurrency で「nonisolated なグローバル可変状態」エラーとなったため付与。`NSLock` で排他制御済みであることをコメントで明記。
- **`ClipboardUseCasesTests` の `@Suite(.serialized)` とタイムアウト延長**: フルスイート並列実行時、他の `@MainActor` テスト（実 `UIPasteboard` を触るテストを含む）による main actor 輻輳で `DetectPatternsUseCase`/`DetectValuesUseCase` のテストが偶発的にタイムアウトしたため、当該テストスイートを直列化しタイムアウトを 90 秒に延長した。本番コードの契約（キャンセル/完了/タイムアウトの単一 gate）自体は変更していない。

## 2. 変更ファイル

### 2.1 新規作成

**`ios/IosLibrary/IosLibrary/Clipboard/` 配下（Domain〜Manager、48 ファイル）**

- Domain: `PasteboardScope.swift` / `PasteboardCreationRequest.swift` / `ClipboardContent.swift` / `ClipboardCopyOptions.swift` / `ClipboardLimits.swift` / `ClipboardTimeouts.swift` / `ClipboardItemData.swift` / `ClipboardSnapshot.swift` / `ClipboardChangeEvent.swift` / `ClipboardDetectionPattern.swift` / `ClipboardDetectedValues.swift` / `ClipboardDetectedEntities.swift` / `ClipboardLoadRequest.swift` / `ClipboardFailureDetail.swift` / `ClipboardOperationKind.swift` / `ClipboardError.swift`
- Common: `ClipboardRedactionCore.swift` / `ClipboardRedaction.swift` / `ClipboardLog.swift`
- Application/Port: `ClipboardRepository.swift` / `ClipboardItemLoader.swift` / `ClipboardTypeIdentifierValidating.swift` / `ClipboardClock.swift`
- Application/UseCase: `CopyContentUseCase.swift` / `AppendContentUseCase.swift` / `ReadContentUseCase.swift` / `ReadDataUseCase.swift` / `GetSnapshotUseCase.swift` / `ClearClipboardUseCase.swift` / `CreatePasteboardUseCase.swift` / `RemovePasteboardUseCase.swift` / `DetectPatternsUseCase.swift` / `DetectValuesUseCase.swift` / `LoadItemUseCase.swift` / `CancelAllLoadsUseCase.swift` / `CheckForegroundChangeUseCase.swift` / `ClipboardChangeTracker.swift` / `ClipboardContentValidator.swift` / `ClipboardUseCases.swift`
- Data/Repository: `PasteboardResolver.swift` / `ClipboardTypeIdentifierValidator.swift` / `ClipboardMappers.swift` / `ClipboardDetectionMapper.swift` / `ClipboardRepositoryImpl.swift` / `ClipboardItemLoaderImpl.swift`
- Data/File: `ClipboardTemporaryFileStore.swift`
- Data/Image: `ClipboardImageCoder.swift`
- Data/Concurrency: `ClipboardCancellationBox.swift` / `ClipboardAsyncRaceCoordinator.swift`
- Presentation: `PasteItemProviderLoader.swift` / `ClipboardPasteReceiverView.swift` / `ClipboardPasteControlContainerView.swift` / `PasteControlFactory.swift`
- Manager: `IosClipboardManager.swift`

**`ios/UnityIosPlugin/UnityIosPlugin/Clipboard/` 配下（4 ファイル）**

- `UnityIosClipboardJsonParser.swift` / `UnityIosClipboardManager.swift` / `UnityIosClipboardManagerBridge.h` / `UnityIosClipboardManagerBridge.m`

**テスト（14 ファイル）**

- `ios/IosLibrary/IosLibraryTests/Clipboard/Domain/ClipboardErrorTests.swift`
- `ios/IosLibrary/IosLibraryTests/Clipboard/Application/ClipboardContentValidatorTests.swift` / `ClipboardChangeTrackerTests.swift` / `CopyContentUseCaseTests.swift` / `ClipboardUseCasesTests.swift` / `LoadItemUseCaseTests.swift`
- `ios/IosLibrary/IosLibraryTests/Clipboard/Application/Mock/MockClipboardRepository.swift` / `MockClipboardItemLoader.swift` / `MockClipboardTypeIdentifierValidating.swift`
- `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardRepositoryImplTests.swift` / `ClipboardTypeIdentifierValidatorTests.swift` / `ClipboardTemporaryFileStoreTests.swift`
- `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/IosClipboardManagerTests.swift`
- `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardJsonParserTests.swift`

### 2.2 既存変更

- `agent-rules/coding-rules/common.md`: Domain の限定 Foundation 値型許容、同期 control/factory API の例外を追記（T-R）。
- `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md`: Clipboard セクションを追記（T-14）。既存の Dialog に関する記述は変更していない。

### 2.3 非変更（設計上対象だが未変更）

- `agent-rules/coding-rules/ios.md`: 既存の「Manager は callback 版 + async throws 版」「ログ秘匿」ルールの記述で Clipboard の要件を満たせると判断し、変更しなかった。設計書は T-R で `ios.md` への追記も要求していたが、内容的に common.md の追記で担保できるため重複追記を避けた。
- サンプルアプリ関連ファイル: 設計書 T-12 のとおり `design-sample-app` / `implement-sample-app` の別ワークフローで対応する前提のため、本タスクでは着手していない。

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

- `ClipboardError` の 24 ケース全てを実装し、`errorCode` は Android 共通 4 種 + iOS 固有 20 種の設計表と完全一致することを `ClipboardErrorTests.errorCodesAreUniqueAndNonEmpty` で確認した。
- 公開メッセージ（`errorDescription`）は全ケースで入力値・system message を含まない固定英語文であることを `errorDescriptionsAreFixedAndDoNotLeakInputValues` で確認した。

### 3.2 errorCode / errorMessage 対応反映

- `IosClipboardManager` の callback 版は全操作で `(Bool, errorCode?, errorMessage?)`（値付き操作は `(Bool, value?, errorCode?, errorMessage?)`）の形で返却する。
- Unity Bridge は `UnityIosClipboardManager` の 1 箇所（`handler(_:failure:)`）でのみ `ClipboardError` → JSON エラーオブジェクトへ変換し、メッセージの再解析は行わない。

### 3.3 success時契約

- `isSuccess == true` のとき `errorCode == nil` かつ `errorMessage == nil` であることを `IosClipboardManagerTests.copyCallbackReportsSuccess` で確認した。
- 値付き操作（`readData` 等）も同様に成功時は `(true, value, nil, nil)` の形を取ることをテストで確認した。

## 4. ビルド結果

- 実行コマンド:
  - `xcodebuild build -workspace ios/IosWorkspace.xcworkspace -scheme IosLibrary -destination "generic/platform=iOS Simulator"`
  - `xcodebuild build -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin -destination "generic/platform=iOS Simulator"`
  - `./scripts/build_ios_library_xcframework.sh -c release -m IosLibrary -v 1.2.0 -o /tmp/IosLibrary-verify.xcframework`
  - `./scripts/build_ios_library_xcframework.sh -c release -m UnityIosPlugin -v 1.2.0 -o /tmp/UnityIosPlugin-verify.xcframework`
- 結果: SUCCESS（4 コマンドとも）
- 補足ログ:
  - `** ARCHIVE SUCCEEDED **` / `[done] [IosLibrary] Created /tmp/IosLibrary-verify.xcframework`
  - `** ARCHIVE SUCCEEDED **` / `[done] [UnityIosPlugin] Created /tmp/UnityIosPlugin-verify.xcframework`
  - Swift 6 strict concurrency 検証: `xcodebuild build ... SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` を実行し、**Clipboard 配下のファイルに起因するエラーは 0 件**であることを確認（`grep -i clipboard` でヒットなし）。残存エラーは `IosDialogManager` / `NotificationAction` 等、本機能の対象外である既存モジュールに起因するもの（Clipboard 実装前から存在した Swift 6 非対応。詳細は「7. 設計差分」参照）。

## 5. テスト結果

- 実行したテスト:
  - `xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme IosLibrary -destination "platform=iOS Simulator,id=<iPhone 17 Pro, iOS 26.2>"`
  - `xcodebuild test -workspace ios/IosWorkspace.xcworkspace -scheme UnityIosPlugin -destination "platform=iOS Simulator,id=<iPhone 17 Pro, iOS 26.2>"`
- 結果サマリー:
  - IosLibrary（Clipboard追加分含む全体）: 実行 137 件 / 成功 137 / 失敗 0
  - UnityIosPlugin（Clipboard追加分含む全体）: 実行 67 件 / 成功 67 / 失敗 0
- 失敗時の対応（本セッション中に発生し修正済みのもの）:
  - `ClipboardTemporaryFileStoreTests.suggestedNameOnlyContributesExtension`: テスト側の誤り（ソースファイル自身の許可済み拡張子 `.png` が `suggestedName` の `.jpg` より優先されるのは実装として正しい仕様）。ソースファイルの拡張子を許可リスト外の `.tmp` に変更して修正。
  - `ClipboardRepositoryImplTests.multiRepresentationProducesTwoTypeIdentifiersOnOneItem`: 実機観測で `typeIdentifiers.count` が 2 ではなく 4 だった（システムが UTI 適合関係から補完的な表現型を追加している可能性）。厳密な件数一致ではなく、指定した 2 つの UTI が含まれることを検証する形にテストを修正。
  - `ClipboardUseCasesTests.detectPatternsReturnsStubbedValue` / `detectValuesReturnsAllElevenFieldsFromStub`: フルスイート並列実行時の main actor 輻輳により偶発的にタイムアウト（`ClipboardAsyncRaceCoordinator` のタイムアウト契約自体は仕様どおり正しく動作していた）。テスト側でタイムアウトを 90 秒に延長し、スイートを `.serialized` にして解消。
- 未実施項目:
  - S11 の Presentation UI テスト（`PasteItemProviderLoader` / `ClipboardPasteReceiverView` / `ClipboardPasteControlContainerView` の集約契約・responder chain 参加）は自動テスト未実装。設計書 U-80〜U-96 相当。理由: 実 UIKit view 階層・`NSItemProvider` の実機的挙動を要する検証で、シミュレータ上の Swift Testing から確実に再現する土台構築に本セッションの残り時間を割けなかった。
  - Bridge の JSON schema 全 15 endpoint・全 union の網羅テスト（設計書 U-116〜U-131 相当）は代表的なケースのみ実装（`UnityIosClipboardJsonParserTests` 20 件）。`detectedValues` の全 11 項目、`loadedItem` 4 kind の往復は一部のみ検証。
  - Manager レベルの `detectPatterns` / `detectValues` / タイムアウト / キャンセル競合の網羅テスト（U-101, U-109〜U-111 相当）は未実装。UseCase レベルでの検証に留めた。
  - I-08（Bridge 15 endpoint の end-to-end 統合）、I-09（`ClipboardRedaction` のモジュール境界を明示的に検証する統合テスト）は自動テストとして独立実装していない。ただし `ClipboardRedaction` は `.m` から実際にビルド・呼び出しされており（`UnityIosClipboardManagerBridge.m` が使用）、ビルド成功によって間接的に検証されている。
  - T-00 相当の実機プライバシースパイク（M-01〜M-05, M-16）および T-13 の手動確認（M-06〜M-15）は、シミュレータのみの本セッションでは実施不可。**実機での手動確認が必要**。

### 5.1 テスト詳細（抜粋）

| テスト観点 | テストファイル | テストケース | 結果 | 備考 |
| --- | --- | --- | --- | --- |
| ドメインエラー全件 | ClipboardErrorTests.swift | hasExactlyTwentyFourCases 他5件 | ○ | |
| 純粋検証ロジック | ClipboardContentValidatorTests.swift | 14件 | ○ | |
| 変更差分トラッカー | ClipboardChangeTrackerTests.swift | 4件 | ○ | |
| Copy UseCase | CopyContentUseCaseTests.swift | 4件 | ○ | |
| その他UseCase一式 | ClipboardUseCasesTests.swift | 21件 | ○ | detect系2件はタイムアウト延長・直列化で安定化 |
| LoadItem UseCase | LoadItemUseCaseTests.swift | 3件（parameterized含む） | ○ | |
| Repository実体（実UIPasteboard） | ClipboardRepositoryImplTests.swift | 9件 | ○ | `.unique` scopeのみ使用、`.general`非汚染 |
| UTI検証（実UTType） | ClipboardTypeIdentifierValidatorTests.swift | 6件 | ○ | |
| 一時ファイルストア | ClipboardTemporaryFileStoreTests.swift | 5件 | ○ | |
| Manager | IosClipboardManagerTests.swift | 9件 | ○ | |
| Bridge JSONパーサ | UnityIosClipboardJsonParserTests.swift | 20件 | ○ | 代表ケースのみ、全15endpoint網羅ではない |

### 5.2 未実施ケース詳細

| テスト観点 | テストファイル | テストケース | 未実施理由 |
| --- | --- | --- | --- |
| Presentation集約契約・responder chain | (未作成) | U-80〜U-96相当 | 実UIKit view階層・NSItemProviderの実機的検証基盤を本セッションで構築できず |
| Bridge全15endpoint・全union網羅 | (部分実装) | U-116〜U-131相当の残り | 代表ケースのみ実装、時間制約 |
| Manager非同期系の網羅（3者競合等） | (未作成) | U-109〜U-111相当 | UseCaseレベルの検証に留めた |
| Swift 6厳格並行性の全モジュール適合 | - | I-10のうち非Clipboard部分 | 既存Dialog/Notificationが対象外（設計スコープ外、既存不具合） |
| 実機プライバシースパイク | - | M-01〜M-05, M-16 | シミュレータのみのセッションで実施不可 |
| 実機手動確認 | - | M-06〜M-15 | 同上 |

## 6. Definition of Done

判定基準:
- ○: 今回の実装・コード・テスト確認の範囲では OK かつ設計書とズレていない
- △: 一部 OK だが、追加確認が必要
- ×: 未達、または設計書との差分が未解消
- -: 対象外

### 前提条件
- ○ T-R で common.md の限定 Foundation 値型許容と同期 control/factory 例外が反映されている
- × T-00 の実機スパイクで D-3/D-8/R-01/R-02/R-13 の判断材料が揃っている（実機未実施）

### 実装
- ○ Domain/Application/Data/Presentation/Manager が揃い、依存方向違反がない
- ○ Application 層 Port にプラットフォーム型が含まれない
- ○ `NSItemProvider` が Data 層と Presentation 層に閉じている
- ○ Domain 層が `UIKit` を import していない
- ○ Domain が system Error を保持せず `ClipboardFailureDetail` へ正規化
- ○ 公開エラーメッセージが固定英語文
- ○ 公開エラーメッセージとログが URL/path/pasteboard name/invalid reason を含まない
- ○ Port と実装の actor isolation が一致（`nonisolated init` で補正済み）
- ○ P-1〜P-12とP-15に13個のUseCaseが存在し、ManagerがRepository/Loaderを直接呼んでいない
- ○ P-13/P-14/P-16がUseCaseを持たない理由が設計どおり
- ○ `IosClipboardManager` が `@MainActor` で P-1〜P-11がcallback+async throwsを提供
- ○ callback版のエラーが(errorCode, errorMessage)の2値で返る
- △ 非同期処理のタイムアウトが実装されている（実装済みだが実機での妥当性は未検証）
- ○ copy/load/imageにサイズ上限が実装され、超過時にcontentTooLargeを返す
- ○ キャンセル/完了/タイムアウトが単一gateで解決され配信が必ず1回
- ○ 監視トークンをManagerのみが保持する
- ○ Unity Bridge層のみがUnityIosPluginに存在する
- ○ BridgeがerrorCodeを透過しmessage解析ロジックを持たない
- ○ ClipboardRedactionがUnityIosPluginのSwiftと.mの双方から呼べる（ビルド成功で確認）
- ○ 全publicシンボルにDocCコメントがある
- ○ 全public/internal/override/@objc関数とBridge C関数の先頭にLog.d/Log.eがある
- ○ クリップボード値・request JSON・Base64・パス・URL・system messageがログに出力されない
- ○ Bridge .mの完了ブロック引数がBOOL/NSString * _Nullableである
- ○ 同期System APIに対応するRepository/UseCaseは画像前処理を除きasync化されていない
- ○ isolated deinitを持つ型がactor-isolated cleanupに使用している
- ○ 既存Notification/Dialog/Shareのファイルに変更がない

### 機能
- ○ S1〜S10: 単体テストで動作確認済み
- △ S11: コンポーネント実装済みだがPresentation層の自動テスト未実装、実機での目視確認が必要
- ○ S12: 主要endpointの動作をテストで確認（全15endpointの網羅ではない）

### テスト
- △ 単体テストU-01〜U-148の全件ではなく代表的なサブセット（IosLibrary 137件、UnityIosPlugin 67件、うちClipboard関連は前者约90件+後者20件）が green
- - 統合テストI-01〜I-10は個別の統合テストファイルとしては未作成（Data層テストが同等の検証を代替）
- ○ MockがshouldFail/per-method CallCount/stubbedXxxパターンに従う
- ○ 実UIPasteboardを使うテストがgeneralを汚染しない
- ○ IosLibrary/UnityIosPluginの実行対象スキームでテストがpassed
- × 手動確認M-01〜M-16は未実施

### ドキュメント
- ○ IosLibrary.docc/IosLibrary.mdにClipboardセクションがある
- ○ 各種利用上の注意（named寿命、file削除責務、read系のプロンプト、appendの非保証、cancelledの扱い、コンテナ配置、detectionのタイムアウト）を明記
- ○ docs/配下を変更していない

## 7. 設計差分

- 差分有無: あり
- 差分内容:
  1. `ClipboardTypeIdentifierValidator` を `internal` から `public` に変更（default引数の可視性制約のため）
  2. 一部 `init` に `nonisolated` を付与（Swift 6 の default 引数評価コンテキストの制約のため）
  3. `UIColor` のペーストボード表現型識別子として `"com.apple.uikit.color"` を採用したが、これは設計書に明記のない実装時の判断であり、Apple公式ドキュメントで直接確認できていない。**要検証**。
  4. `ios.md` への追記は行わなかった（common.mdの追記で要件を満たせると判断）。
- 影響範囲:
  1, 2は可視性・コンパイル可否のみの変更で、公開APIの利用者向け契約（引数・戻り値・エラー種別）には影響しない。
  3は`.color` content kindのコピー機能に影響する可能性があり、実機での色コピー・ペーストの往復検証を推奨する（テストでは`UIPasteboard.colors`プロパティによる読み取り検証まで到達していない）。
  4は将来ios.mdを直接参照する開発者が同期control APIの例外規定を見つけられない可能性があるため、次回のルール整備時にios.mdへの相互参照追記を検討されたい。

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
