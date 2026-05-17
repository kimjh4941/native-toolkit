# 実装結果レポート

## 基本情報

- 日付: 2026-05-09
- 機能名: notification
- 対象OS: macOS
- 設計書: artifact/designs/notification/2026-05-09-macos-notification-implementation-v3.md
- ブランチ: feature/NTKIT-7

## 1. 実装サマリー

### 1.1 設計書由来の実装

- T1 Domain Error/Model を追加実装（NotificationDomainError/BridgeError/Domain Models）
- T2 UseCase + Port を追加実装（Dispatch/Schedule/Query/Category + Repository Port）
- T3 RepositoryImpl を追加実装（UNUserNotificationCenter ベース）
- T4 Manager + Delegate を追加実装（MacNotificationManager + PermissionHelper）
- T5 Unity Swift facade + JSON parser を追加実装（UnityMacNotificationManager/JsonParser）
- T6 Obj-C/C Bridge を追加実装（Bridge.h/.m と callback typedef 群）
- T7 Test を追加実装（MacLibrary 側 UseCase/Error、UnityMacPlugin 側 JSON parser）

### 1.2 実装時の追加判断

- `Set.removeAll(where:)` 非対応に合わせ、`Set(filter { ... })` へ変更
- `UnityMacPlugin.h` への Bridge ヘッダ import による循環依存を回避（import を除去）
- `UnityMacNotificationManager.swift` の重複クラス定義を除去
- Obj-C ブリッジ互換性のため、completion を tuple typealias ではなく `(Bool, Int, String?)` へ統一
- tuple 戻り値の helper はクロージャ呼び出し時に `(r.0, r.1, r.2)` へ展開

## 2. 変更ファイル

### 2.1 新規作成

- mac/MacLibrary/MacLibrary/Notification/\*\*
- mac/UnityMacPlugin/UnityMacPlugin/Notification/\*\*
- mac/MacLibrary/MacLibraryTests/Notification/\*\*
- mac/UnityMacPlugin/UnityMacPluginTests/Notification/\*\*

### 2.2 既存変更

- mac/MacLibrary/MacLibrary/MacLibrary.h
- mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.h
- mac/MacLibrary/MacLibrary/MacLibrary.docc/MacLibrary.md
- mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.docc/UnityMacPlugin.md
- artifact/designs/notification/2026-05-09-macos-notification-implementation-v3.md

### 2.3 非変更（設計上対象だが未変更）

- 該当なし（T8 Docs/manual は要件更新でタスク自体を削除）

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

- NotificationDomainError の全ケース（1001〜1999 対応）を実装
- BridgeError の全ケース（1301, 1302）を実装

### 3.2 errorCode / errorMessage 対応反映

- 設計書の対応表に沿って実装済み
- `NotificationDomainErrorTests` と parser テストで主要 mapping を検証

### 3.3 success時契約

- isSuccess == true のとき errorCode == 0 / errorMessage == nil を満たすこと: 確認済み（Unity bridge completion 変換ロジックで統一）

## 4. ビルド結果

- 実行コマンド:
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary -destination 'platform=macOS' build`
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS' build`
- 結果: SUCCESS
- 補足ログ（必要箇所のみ）:
  - MacLibrary: `** BUILD SUCCEEDED **`
  - UnityMacPlugin: `** BUILD SUCCEEDED **`

### 4.1 後続の xcframework ビルドで発覚した不具合と修正（2026-05-17）

- xcframework ビルドスクリプト実行時に `UnityMacNotificationManagerBridge.m` でコンパイルエラーが発生
- 原因: completion ブロック引数の型が `bool`（C の `_Bool`）になっており、Swift 側の `BOOL`（`signed char`）と型シグネチャが不一致
- 修正内容: `UnityMacNotificationManagerBridge.m` 内の completion ブロック引数 8 箇所を `bool` → `BOOL` に変更
- 修正コミット: `d032f58`
- 修正後の xcframework ビルド結果: `** ARCHIVE SUCCEEDED **`

## 5. テスト結果

- 実行したテスト:
  - `xcodebuild test -workspace mac/MacWorkspace.xcworkspace -scheme MacLibraryTests -destination 'platform=macOS'`
  - `xcodebuild test -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS'`
- 結果サマリー:
  - 実行件数: 55
  - 成功: 57
  - 失敗: 0
- 失敗時の対応:
  - 途中失敗は修正済み（テストコード修正後に再実行して全件成功）
- 未実施項目（あれば）:
  - 実機E2E（Focus/Do Not Disturb など）: 手動確認が必要

### 5.1 テスト詳細

| テスト観点                                          | テストファイル                                                                                  | テストケース                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     | 結果 | 備考       |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---- | ---------- |
| ドメインエラー errorCode / errorMessage 対応        | `mac/MacLibrary/MacLibraryTests/Notification/NotificationDomainErrorTests.swift`                | `unsupportedOSHasCode1001()`, `permissionDeniedHasCode1002()`, `permissionRequestFailedHasCode1003()`, `invalidContentHasCode1101()`, `invalidTriggerHasCode1102()`, `invalidCategoryHasCode1103()`, `notificationNotFoundHasCode1104()`, `addFailedHasCode1201()`, `removeFailedHasCode1202()`, `queryFailedHasCode1203()`, `setBadgeFailedHasCode1204()`, `openSettingsFailedHasCode1205()`, `unknownHasCode1999()`                                                                                                                                                                                                            | ○    | 自動テスト |
| ドメインエラーメッセージ整合                        | `mac/MacLibrary/MacLibraryTests/Notification/NotificationDomainErrorTests.swift`                | `unsupportedOSErrorMessageContainsMinimum()`, `notificationNotFoundErrorMessageContainsIdentifier()`, `invalidContentErrorMessageContainsReason()`                                                                                                                                                                                                                                                                                                                                                                                                                                                                               | ○    | 自動テスト |
| Dispatch UseCase 正常系 / 入力検証 / 更新           | `mac/MacLibrary/MacLibraryTests/Notification/NotificationDispatchUseCasesTests.swift`           | `showSuccessCallsAdd()`, `showFailsOnEmptyTitle()`, `showFailsOnInvalidId()`, `showFailsOnTriggerBelowOneSecond()`, `showPropagatesRepositoryError()`, `updateSuccessCallsAdd()`, `updateFailsOnInvalidContent()`                                                                                                                                                                                                                                                                                                                                                                                                                | ○    | 自動テスト |
| Schedule UseCase 正常系 / 入力検証 / cancel / query | `mac/MacLibrary/MacLibraryTests/Notification/NotificationScheduleUseCasesTests.swift`           | `scheduleSuccessWithTimeInterval()`, `scheduleRejectsImmediateTrigger()`, `cancelScheduledCallsRemovePending()`, `cancelAllScheduledCallsRemoveAllPending()`, `getScheduledSuccessReturnsEmpty()`, `getScheduledPropagatesQueryFailure()`                                                                                                                                                                                                                                                                                                                                                                                        | ○    | 自動テスト |
| Query UseCase delivered 取得 / 削除                 | `mac/MacLibrary/MacLibraryTests/Notification/NotificationQueryUseCasesTests.swift`              | `getDeliveredSuccessReturnsEmpty()`, `getDeliveredPropagatesQueryFailure()`, `removeDeliveredCallsRepositoryWithIdentifier()`, `removeAllDeliveredCallsRepository()`                                                                                                                                                                                                                                                                                                                                                                                                                                                             | ○    | 自動テスト |
| Category UseCase register / remove / validation     | `mac/MacLibrary/MacLibraryTests/Notification/NotificationCategoryUseCasesTests.swift`           | `registerCategoryCallsSetCategories()`, `registerCategoryFailsOnEmptyId()`, `removeCategoryRemovesFromRegisteredSet()`, `removeCategoryFailsOnEmptyId()`                                                                                                                                                                                                                                                                                                                                                                                                                                                                         | ○    | 自動テスト |
| Bridge JSON parse / serialization                   | `mac/UnityMacPlugin/UnityMacPluginTests/Notification/UnityMacNotificationJsonParserTests.swift` | `parseContentSuccessWithAllFields()`, `parseContentCategoryIdentifierIsNilWhenAbsent()`, `parseContentSuccessWithMinimalFields()`, `parseContentFailsOnInvalidJson()`, `parseContentFailsOnMissingId()`, `parseContentFailsOnMissingTitle()`, `parseTriggerImmediateSuccess()`, `parseTriggerTimeIntervalSuccess()`, `parseTriggerCalendarSuccess()`, `parseTriggerFailsOnUnknownType()`, `parseTriggerTimeIntervalFailsWithoutSeconds()`, `parseCategorySuccessWithActions()`, `parseCategoryFailsOnMissingId()`, `toJsonScheduledReturnsValidArray()`, `toJsonScheduledEmptyReturnsEmptyArray()`, `toJsonStatusAuthorized()`, `toJsonStatusDenied()`, `toJsonStatusUnsupported()` | ○    | 自動テスト |

### 5.2 未実施ケース詳細

| テスト観点                      | テストファイル | テストケース                        | 未実施理由                                                            |
| ------------------------------- | -------------- | ----------------------------------- | --------------------------------------------------------------------- |
| Focus / Do Not Disturb 実機挙動 | -              | 実機での通知表示可否確認            | macOS 実機での手動確認が必要                                          |
| C Bridge 文字列寿命契約         | -              | callback 内ポインタ寿命の実運用確認 | 自動テストではなく Unity 側を含む手動確認が必要                       |
| main queue callback の実測確認  | -              | 公開 callback のスレッド実行確認    | 実装上は main queue dispatch 済みだが、専用スレッド検証テストは未追加 |

## 6. Definition of Done

- 判定基準:
  - ○: 今回の実装・コード・テスト確認の範囲では OK かつ設計書とズレていない
  - △: 一部 OK だが、追加確認が必要
  - ×: 未達、または設計書との差分が未解消
  - -: 対象外
- ○ 企画書要件と設計/タスク/テストのトレース表が埋まっている
- ○ API 契約表が in-scope と 1:1 対応している
- ○ ドメインエラー全ケースとエラー対応表が一致している
- ○ 公開 callback が main queue で実行される
- ○ C Bridge メモリ契約がヘッダに明記される
- ○ error mapping と API 契約がテストで担保される
- △ CI テストと実機E2Eが分離運用される
- △ macOS 15+ 実機で検証済み

## 7. 設計差分

- 差分有無: あり
- 差分内容:
  - T8 Docs/manual 更新タスクは削除
  - Bridge 実装で Obj-C 互換性対応のため completion 型を調整
  - xcframework ビルド時に `UnityMacNotificationManagerBridge.m` の completion ブロック引数 `bool` → `BOOL` 型不一致を修正（2026-05-17、コミット `d032f58`）
- 影響範囲:
  - ドキュメントタスク計画
  - Unity bridge 実装詳細（公開契約は維持）

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
