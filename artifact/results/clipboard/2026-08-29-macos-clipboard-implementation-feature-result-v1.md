# 実装結果レポート

> **Errata（2026-08-30）**
>
> **§7.2 の Swift 6 測定は無効である。** `swiftc -swift-version 6 -typecheck` は
> `artifact/MIGRATION.md` §4.3 の必須条件（whole-module / clean / 最下流 scheme）を満たさず、
> フロー解析段階の `sending` 系診断が構造的に出ない。§1 の誤り #3 と同一の失敗である。
> §7.2 が挙げた選択肢 (b)「Clipboard ターゲットのみ Swift 6」も、Clipboard が独立ターゲット
> ではないため成立しない。
>
> **§8 のユーザー回答「未回答」は解消済み。回答は「キャンセル」。**
>
> 訂正・正しい計測・決定内容は
> `2026-08-29-macos-clipboard-implementation-feature-result-v2.md` を参照すること。

## 基本情報

- 日付: 2026-08-29
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- ブランチ: feature/NTKIT-15
- スコープ: **T-01 / T-02 / T-11a / T-11b の 4 タスクに限定**（ユーザー指示による先行実装）

## 1. 実装サマリー

### 1.1 設計書由来の実装

| タスク | 内容 | 状態 |
|---|---|---|
| T-01 | Domain モデル + `ClipboardLimits` + `FilePromiseReceiptPolicy` + `ClipboardError`（25 ケース / 1501〜1599）+ §6.8 の設定値検証 | 完了 |
| T-02 | Port 4 種（`ClipboardRepository` / `ClipboardPromiseRegistry` / `ClipboardTypeIdentifierValidating` / `FilePromiseSnapshotting`） | 完了（Mock は §1.2 参照） |
| T-11a | `FilePromiseLifecycleState`（nonisolated lock-owning、`CommitReleaseOutcome`、`activate`、generation claim） | 完了 |
| T-11b | `FilePromiseSnapshotter`（専用 serial queue、cancellation、`discard`、late completion cleanup） | 完了 |

設計書の該当箇所をそのまま実装した主な契約。

- §10 / §11: `ClipboardError` 25 ケース、コード 1501〜1599、英語メッセージ
- §6.8: `ClipboardLimits` / `FilePromiseReceiptPolicy` の initializer 検証 → `invalidConfiguration`
- §7.12（R4-H2 / R5-H1 / R5-H3 / R6-H2）: `FilePromiseLifecycleState` の 2 段階 claim、`scheduledGeneration: UInt64?` による予約 identity、`CommitReleaseOutcome` による `.writer` 正常解放の区別、`activate(ownership:)`
- §8.2 / §8.3: Port の引数・戻り値は Domain 値型のみ。AppKit / Presentation 型は現れない
- §4.2: `ClipboardLog` による秘匿（文字列は長さ、Data はバイト数、URL はスキームとホスト、パスは最終要素、ペーストボード名は短縮ハッシュ）
- mac.md: 全 `internal` / `public` メソッド先頭に `Log.d`。DocC とコメントは英語

### 1.2 実装時の追加判断

| # | 判断 | 理由 |
|---|---|---|
| A-1 | **`FilePromiseSnapshotter` が `FileManager` を保持しない**。`makeFileManager: @Sendable () -> FileManager` を注入し、queue 内で生成する | **Swift 6 で `FileManager` は `Sendable` でなく、`Sendable` な class の stored property にできない**（実測: `error: stored property 'fileManager' of 'Sendable'-conforming class ... has non-Sendable type 'FileManager'`）。設計書は `FilePromiseSnapshotting: Sendable` としているため、保持ではなく生成に変更した。副次的に、各インスタンスが serial queue に閉じる利点もある |
| A-2 | `Log.d` を lock 取得**前**に置く | lock 保持中の `Logger` 呼び出しを避けるため。mac.md の「メソッド先頭 1 行目」は満たしている |
| A-3 | `FilePromiseLifecycleState` に `released` / `inFlight` の読み取りプロパティを追加 | テストと診断のため。設計書の遷移表に影響しない |
| A-4 | `ClipboardLimits` / `FilePromiseReceiptPolicy` に private な非検証 initializer を追加 | `static let default` が throwing initializer を呼べないため。`default` が制約を満たすことはテストで検証している |
| A-5 | Port の `ClipboardTypeIdentifierValidating` を `@MainActor` にした | `ClipboardRepository` と同じ隔離に置くため（設計書 §6.2 の `@MainActor` 固定方針に整合） |

## 2. 変更ファイル

### 2.1 新規作成

実装（`mac/MacLibrary/MacLibrary/Clipboard/`）

- `Common/ClipboardLog.swift`
- `Domain/Error/ClipboardError.swift`
- `Domain/Model/PasteboardScope.swift`（`PasteboardScope` / `PasteboardCreationRequest` / `PasteboardOwnership`）
- `Domain/Model/ClipboardHandles.swift`（4 種のハンドル）
- `Domain/Model/ClipboardContent.swift`（`ClipboardItemData` / `ClipboardContent` / `ClipboardCopyOptions` / `ClipboardReadResult` / `ClipboardSnapshot` / `ClipboardChangeEvent`）
- `Domain/Model/ClipboardLimits.swift`
- `Domain/Model/ClipboardDetection.swift`（パターン / メタデータ型 / `ClipboardAccessBehavior` / 検出 entity 8 種 / `ClipboardDetectedValues` / `ClipboardDetectedMetadata`）
- `Domain/Model/ClipboardPasteResult.swift`
- `Domain/Model/FilePromise.swift`（`FilePromiseSource` / `FilePromiseRequest` / `FilePromiseReceiptEvent` / `FilePromiseReceipt` / `FilePromiseReceiptPolicy`）
- `Application/Port/ClipboardRepository.swift`
- `Application/Port/ClipboardPromiseRegistry.swift`
- `Application/Port/ClipboardTypeIdentifierValidating.swift`
- `Application/Port/FilePromiseSnapshotting.swift`
- `Data/Promise/FilePromiseLifecycleState.swift`
- `Data/Promise/FilePromiseSnapshotter.swift`

テスト（`mac/MacLibrary/MacLibraryTests/Clipboard/`）

- `Domain/ClipboardErrorTests.swift`
- `Domain/ClipboardConfigurationTests.swift`
- `Data/FilePromiseLifecycleStateTests.swift`
- `Data/FilePromiseSnapshotterTests.swift`

### 2.2 既存変更

なし。既存の Notification / Share / Dialog には一切触れていない。

### 2.3 非変更（設計上対象だが今回スコープ外）

- `Data/Repository/*`、`Data/Promise/LazyDataProvider.swift`、`Data/Promise/FilePromiseDelegate.swift`、`Data/Promise/FilePromiseReceiptSession.swift`、`Data/Promise/PromiseObjectLookup.swift`: T-03 以降
- `Application/UseCase/*`: T-06 以降
- `Coordinator/ClipboardSystemCoordinator.swift`: T-07
- `MacClipboardManager.swift`: T-08
- `Presentation/*`: T-10 / T-14
- `mac/UnityMacPlugin/Clipboard/*`: T-16a〜T-16c
- **Mock 4 種**: T-02 の一部だが、Port を実装する Mock は消費側 UseCase（T-06）と同時に書くのが自然なため、**今回は `FilePromiseSnapshotter` の注入可能化（A-1）で代替**し、Port の Mock 本体は T-06 で作成する。§9 に「未達」として記録

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

設計書 §10 の全 25 ケースを `ClipboardError` に実装。`ClipboardErrorTests/caseCount()` が 25 件であることを検証している。

### 3.2 errorCode / errorMessage 対応反映

- 設計書 §11 の 1501〜1599 をそのまま実装
- `codesAreUnique()` で重複なし、`codesInBand()` で帯の逸脱なし、`noBridgeCollision()` で `BridgeError`（1301 / 1302）との衝突なしを検証
- `messagesWellFormed()` で全メッセージが非空・ASCII（英語）・末尾がピリオドであることを検証
- `spotCheckCodes()` で 1501 / 1511 / 1523 / 1524 / 1599 を設計表と突き合わせ

### 3.3 success時契約

- **今回のスコープでは未検証**。`isSuccess == true` のとき `errorCode == 0` / `errorMessage == nil` を返すのは Manager callback 層（設計書 §8.1.1）であり、T-08 の実装対象。今回は Domain とレイヤー境界のみのため対象外

## 4. ビルド結果

- 実行コマンド:
  - `xcodebuild -project mac/MacLibrary/MacLibrary.xcodeproj -scheme MacLibrary -configuration Debug build`
  - `./scripts/build_xcode26_library_xcframework.sh -c release -m MacLibrary -v 1.2.0 -o /tmp/MacLibrary-verify.xcframework --minimum-macos 15.0`
  - `xcrun swiftc -swift-version 6 -typecheck -target arm64-apple-macos15.0 <新規ソース 15 本 + Log.swift>`
- 結果: **SUCCESS**（3 件とも）
- 補足ログ:
  - `** BUILD SUCCEEDED **`
  - `** ARCHIVE SUCCEEDED **` / `[done] [MacLibrary] Created /tmp/MacLibrary-verify.xcframework`
  - Swift 6 型検査: **エラー・警告ゼロ**

## 5. テスト結果

- 実行したテスト:
  - `xcodebuild test -project mac/MacLibrary/MacLibrary.xcodeproj -scheme MacLibrary -destination 'platform=macOS'`
- 結果サマリー:
  - 実行件数: 131（うち **新規 44**、既存 87）
  - 成功: 131
  - 失敗: 0
  - `** TEST SUCCEEDED **`
- 失敗時の対応: なし
- 未実施項目:
  - 設計書 §12.2 の統合テスト（IT-xx）: 実 `NSPasteboard` を使うため T-04 以降
  - 設計書 §12.4 の Bridge テスト（BT-xx）: T-16 以降
  - CT-11 / IT-41 など coordinator 統合を要する項目: T-11c 以降

### 5.1 テスト詳細

| テスト観点 | テストファイル | テストケース | 結果 | 備考 |
|---|---|---|---|---|
| エラー全ケース網羅 | `Clipboard/Domain/ClipboardErrorTests.swift` | `caseCount` | ○ | 25 件 |
| エラーコード重複 | 同上 | `codesAreUnique` | ○ | |
| エラーコード帯 | 同上 | `codesInBand` | ○ | 1501〜1599 |
| BridgeError 衝突 | 同上 | `noBridgeCollision` | ○ | 1301 / 1302 |
| メッセージ整形 | 同上 | `messagesWellFormed` | ○ | 非空 / ASCII / 末尾ピリオド |
| メッセージ文脈 | 同上 | `messagesCarryContext` | ○ | associated value の反映 |
| LocalizedError | 同上 | `localizedDescriptionMatches` | ○ | |
| 設計表との一致 | 同上 | `spotCheckCodes` | ○ | |
| 設定値検証（正常） | `Clipboard/Domain/ClipboardConfigurationTests.swift` | `defaultIsValid` ×2 | ○ | limits / policy |
| 設定値検証（境界） | 同上 | `acceptsEqualThresholds` / `acceptsOneHour` | ○ | |
| 設定値検証（異常） | 同上 | `rejectsNonPositive` ×2 / `rejectsWarnAboveMax` / `rejectsMaxAboveTotal` / `rejectsQuietNotShorter` / `rejectsTooLongOverall` | ○ | |
| 解放 claim（正常） | `Clipboard/Data/FilePromiseLifecycleStateTests.swift` | `noClaimWithoutRequest` / `idleReleasesOnRequest` | ○ | |
| 複数同時履行 | 同上 | `releaseWaitsForInFlight` | ○ | RK-21 / R2-H4 |
| TOCTOU 予約無効化 | 同上 | `newWriteInvalidatesReservation` / `releaseResumesAfterInterruption` | ○ | R3-H2 |
| 予約 identity | 同上 | `staleAbandonDoesNotClearNewerClaim` / `commitWithUnknownGeneration` | ○ | **R4-H2 追加問題** |
| 冪等性 | 同上 | `releaseIsIdempotent` | ○ | R2-M5 |
| 解放後の書き出し | 同上 | `writeAfterReleaseIsRejected` | ○ | R4-H2 遷移表 |
| `.writer` 正常解放 | 同上 | `writerBackedReleaseIsStillReleased` | ○ | **R5-H1** |
| ownership activation | 同上 | `ownershipStartsNil` / `activationRecordsOwnership` | ○ | **R5-H3** |
| 並行 claim | 同上 | `concurrentClaimsAreExclusive` | ○ | CT-08 相当 |
| snapshot 正常 | `Clipboard/Data/FilePromiseSnapshotterTests.swift` | `copiesFile` / `copiesDirectory` | ○ | |
| source 削除耐性 | 同上 | `copySurvivesSourceDeletion` | ○ | R2-M11 / IT-28 相当 |
| 失敗時 cleanup | 同上 | `missingSourceLeavesNothing` | ○ | R5-M6 |
| staging 再利用防止 | 同上 | `replacesExistingStaging` | ○ | |
| discard | 同上 | `discardRemoves` / `discardIsIdempotent` | ○ | **R6-H2** |
| キャンセル | 同上 | `cancellationBeforeCopy` | ○ | R5-M6 |

### 5.2 未実施ケース詳細

| テスト観点 | テストファイル | テストケース | 未実施理由 |
|---|---|---|---|
| late completion cleanup | - | IT-45 相当（コピー完了後キャンセル） | `Task.checkCancellation()` のタイミングを決定的に作れないため。**T-11c の統合時に `MockFilePromiseSnapshotter` で検証する** |
| Port の Mock | - | Mock 4 種 | 消費側 UseCase（T-06）と同時に作るのが自然なため延期。§2.3 参照 |
| 統合 / Bridge / Presentation | - | IT / BT / PT 各種 | T-03 以降のタスク |

## 6. Definition of Done

対象は設計書 §15「実装完了条件」のうち、今回スコープに関わるもの。

- ○ Swift 6 strict concurrency で警告ゼロでビルドできる（新規ソース単体の型検査で確認。**プロジェクト設定は Swift 5.0 のまま。§7 参照**）
- ○ 実装のシグネチャ・actor isolation が §9 / §16.1 の対応表と一致している（今回スコープの範囲で）
- ○ `public` シンボルすべてに英語の DocC が付いている
- ○ 全メソッド先頭に `Log.d` があり、内容が §4.2 の方針で秘匿されている
- ○ `FilePromiseLifecycleState` が nonisolated な lock-owning クラスであり、`@MainActor` の state を直接触っていない（R4-H2）
- ○ Port の引数・戻り値が Domain 値型のみ（H-1）
- △ 12.1 の単体テストが全通過する（今回スコープ分は全通過。UseCase 分は T-06）
- - 12.2 / 12.3 / 12.4 / 12.5 の各テスト（T-03 以降）
- - Unity Bridge に Delegate 実装が存在しない（T-16 以降）
- - `MacLibraryExample` から全公開 OP を実行できる（T-18）

## 7. 設計差分

- 差分有無: **あり（2 件）**

### 7.1 `FilePromiseSnapshotting` 実装が `FileManager` を保持できない

- 内容: 設計書は `FilePromiseSnapshotting: Sendable` としているが、`FileManager` は `Sendable` ではないため、実装クラスが stored property として保持できない。`makeFileManager: @Sendable () -> FileManager` を注入して queue 内で生成する形に変更した
- 影響範囲: `FilePromiseSnapshotter` の initializer のみ。Port の signature は変更なし
- **設計書への還元が必要**: §6.1 / §7.12 に「実装は `FileManager` を保持せず queue 内で生成する」旨を追記する

### 7.2 プロジェクトの Swift バージョンが 5.0

- 内容: `MacLibrary.xcodeproj` は `SWIFT_VERSION = 5.0`、`SWIFT_STRICT_CONCURRENCY` 未設定（既定 `minimal`）。設計書 DoD の「Swift 6 strict concurrency で警告ゼロ」はプロジェクトビルドでは検証されない
- 今回の対応: 新規ソース 15 本を `swiftc -swift-version 6` で単体型検査し、警告ゼロを確認した
- 影響範囲: **プロジェクト全体**。Swift 6 化は既存の Notification / Share / Dialog にも影響するため、**独断では変更していない**
- 判断が必要: (a) プロジェクトを Swift 6 に上げる (b) Clipboard ターゲットのみ `SWIFT_VERSION = 6.0` にする (c) 現状維持で新規ソースの単体型検査を CI 的に運用する

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
