# 実装設計書: macOS 通知機能

## 対象企画書

- artifact/plans/notification/2026-05-09-macos-notification-research-v2.md

## 設計目的

- `MacLibrary` と `UnityMacPlugin` に、ローカル通知の権限取得・表示・スケジュール・カテゴリ/アクション・配信済み/保留中管理を追加する。
- 既存の Dialog 機能と同じ層分離（Manager 中心 + Bridge 薄化）を維持したまま、Unity から扱える C ABI を提供する。

## スコープ（in / out）

### in

- 権限取得（request / status / settings open）
- 通知表示（immediate / trigger）
- スケジュール管理（追加、取得、取消）
- 配信済み管理（取得、削除）
- カテゴリ・アクション登録
- デリゲート処理（foreground 表示 / action 応答）
- Unity Bridge（Swift facade + Obj-C/C bridge）

### out

- APNs / remote push
- Notification Service Extension / Content Extension
- Safari Web Push
- PushKit

## 共通実装方針の適用チェック（common.md 準拠）

- Clean Architecture: **適合**
  - `Domain`（モデル/エラー）
  - `Application`（UseCase + Repository Port）
  - `Data`（UNUserNotificationCenter 実装）
  - `Presentation`（Permission helper）
  - `Manager`（Delegate 所有、UseCase 集約）
  - `Unity Bridge`（C ABI 変換のみ）
- 依存方向: **適合**
  - `Manager -> UseCase -> Repository Port -> RepositoryImpl`。
  - `Domain/Application` に `UserNotifications` 依存を持ち込まない。
- Delegate 所有: **適合**
  - `MacNotificationManager` のみ `UNUserNotificationCenterDelegate` を実装。
  - `RepositoryImpl` と Bridge 層には Delegate を実装しない。
- TDD 方針: **適合**
  - UseCase 単位テスト + Repository モック。
- エラー変換: **適合**
  - `RepositoryImpl` がシステムエラーを `NotificationError` に変換。
  - `Manager` が `(Bool, String?)` へ変換。
- Minimum OS Versions: **要補正**
  - 共通ルールは `macOS 15+`。
  - 企画書内の `10.14+ / 12+` 記述は実装条件と矛盾するため、設計では `15+` を採用する（要企画書反映）。

## 個別実装方針の適用チェック（対象OSルール準拠）

- `mac.md` ログ規約: **適合**
  - public/internal/override/@objc 公開関数先頭で `Log.d`。
  - 失敗時 `Log.e`。
- `mac.md` コメント規約: **適合**
  - Swift public API に DocC。
  - Obj-C 公開ヘッダに HeaderDoc。
- 言語ポリシー: **適合**
  - コメントとユーザー向け文言は英語。

## 既存実装差分サマリー

- 現状 `mac` は Dialog 機能のみ。
  - 既存中核: `mac/MacLibrary/MacLibrary/Dialog/MacDialogManager.swift`
  - 既存 Bridge: `mac/UnityMacPlugin/UnityMacPlugin/Dialog/UnityMacDialogManager.swift`
- 通知機能は未実装のため、新規追加中心。
- 破壊的変更: **なし**（既存 Dialog API と独立した新規 API 群を追加）。

## 実装アーキテクチャ

```text
Unity C#
  -> C Bridge (UnityMacNotificationManagerBridge.h/.m)
  -> Swift Bridge Facade (UnityMacNotificationManager.swift)
  -> MacNotificationManager (Delegate owner)
  -> UseCases (Application)
  -> NotificationRepository (Port)
  -> NotificationRepositoryImpl (UNUserNotificationCenter)
```

## サブ機能別詳細設計

### 1. 権限取得

- 変更対象モジュール
  - `MacLibrary/Notification/Presentation/Permission`
  - `MacLibrary/Notification/Manager`
  - `UnityMacPlugin/Notification`
- 追加 API（公開）
  - `requestPermission(options:, completion:)`
  - `authorizationStatus(completion:)`
  - `openNotificationSettings()`
- データ構造
  - `NotificationAuthorizationStatus` enum
- 制御フロー
  - Manager -> UseCase -> RepositoryImpl -> `UNUserNotificationCenter`。
- エラー処理
  - 権限拒否は `NotificationError.permissionDenied`。
- 互換性
  - `macOS 15+` 前提で async API を使用。

### 2. 通知コンテンツ構築/表示

- 変更対象モジュール
  - `MacLibrary/Notification/Domain/Model`
  - `MacLibrary/Notification/Application/UseCase`
  - `MacLibrary/Notification/Data/Repository`
  - `MacLibrary/Notification/Manager`
- 追加 API（公開）
  - `show(content:trigger:completion:)`
  - `update(identifier:content:trigger:completion:)`
- データ構造
  - `NotificationContent`, `NotificationSound`, `NotificationTrigger`
- 制御フロー
  - Manager で入力検証 -> UseCase 実行 -> RepositoryImpl が `UNMutableNotificationContent` / `UNNotificationRequest` を生成。
- エラー処理
  - 添付変換失敗、add 失敗を `NotificationError` へ変換。
- 互換性
  - 既存 API 追加のみ、既存 Dialog と非干渉。

### 3. スケジュール管理

- 変更対象モジュール
  - `Application/UseCase/NotificationScheduleUseCases.swift`
  - `Domain/Model/ScheduledNotification.swift`
- 追加 API（公開）
  - `schedule(content:trigger:identifier:completion:)`
  - `cancelScheduled(identifier:)`
  - `cancelAllScheduled()`
  - `getScheduled(completion:)`
- データ構造
  - `ScheduledNotification`
- 制御フロー
  - RepositoryImpl で pending requests をモデルへ変換。
- エラー処理
  - schedule 時のみ throwing。

### 4. 配信済み管理

- 変更対象モジュール
  - `Application/UseCase/NotificationQueryUseCases.swift`
  - `Domain/Model/ActiveNotification.swift`
- 追加 API（公開）
  - `removeDelivered(identifier:)`
  - `removeAllDelivered()`
  - `getDelivered(completion:)`
- データ構造
  - `ActiveNotification`
- 制御フロー
  - delivered notifications を JSON 変換可能な軽量モデルに正規化。

### 5. カテゴリ/アクション

- 変更対象モジュール
  - `Domain/Model/NotificationCategory.swift`
  - `Application/UseCase/NotificationCategoryUseCases.swift`
- 追加 API（公開）
  - `registerCategory(_:)`
  - `removeCategory(identifier:)`
  - `setActionReceivedHandler(...)`
  - `setTextInputActionReceivedHandler(...)`
- データ構造
  - `NotificationCategory`, `NotificationAction`, `NotificationTextInputAction`
- 制御フロー
  - Manager が delegate `didReceive` で action を受信し、登録済みハンドラへ配信。

### 6. デリゲート処理

- 変更対象モジュール
  - `MacNotificationManager`（`UNUserNotificationCenterDelegate` 実装）
- 追加 API（公開）
  - `setup()`（delegate 登録）
  - `foregroundPresentationOptions`
- 制御フロー
  - `willPresent`: 現在設定の presentation options を返す。
  - `didReceive`: action/text-input を正規化してハンドラ実行。
- エラーハンドリング
  - callback 内は fail-safe（JSON 変換失敗でも completion は必ず呼ぶ）。

## API 設計（公開 / 内部）

### 公開 API（MacLibrary）

- `MacNotificationManager.shared`
- `MacNotificationManager.setup()`
- `show / update / schedule / cancel / cancelAll / removeDelivered / removeAllDelivered`
- `cancelScheduled / cancelAllScheduled / getScheduled / getDelivered`
- `requestPermission / hasPermission / authorizationStatus / openNotificationSettings / setBadgeCount`
- `registerCategory / removeCategory`
- `onActionReceived / onTextInputActionReceived`

### 公開 API（UnityMacPlugin: C Bridge）

- `notificationSetup()`
- `showNotification(...)`
- `scheduleNotification(...)`
- `updateNotification(...)`
- `cancelNotification(...)`, `cancelAllNotifications()`
- `removeDeliveredNotification(...)`, `removeAllDeliveredNotifications()`
- `cancelScheduledNotification(...)`, `cancelAllScheduledNotifications()`
- `getScheduledNotifications(...)`, `getDeliveredNotifications(...)`
- `requestNotificationPermission(...)`, `getNotificationAuthorizationStatus(...)`, `hasNotificationPermission(...)`
- `openNotificationSettings()`
- `setNotificationBadgeCount(...)`
- `registerNotificationCategory(...)`, `removeNotificationCategory(...)`
- `setNotificationActionReceivedCallback(...)`, `setNotificationTextInputActionReceivedCallback(...)`

### 内部 API

- `NotificationRepository` Port
- `NotificationRepositoryImpl.makeUNContent / makeTrigger / makeUNCategory`
- `UnityMacNotificationJsonParser`（Bridge JSON 入出力専用）

## 変更対象ファイル（具体パス）

### 新規（MacLibrary）

- `mac/MacLibrary/MacLibrary/Notification/IosLikeNaming/` は作らない（mac 命名で統一）。
- `mac/MacLibrary/MacLibrary/Notification/MacNotificationManager.swift`
- `mac/MacLibrary/MacLibrary/Notification/Presentation/Permission/NotificationPermissionHelper.swift`
- `mac/MacLibrary/MacLibrary/Notification/Application/Port/NotificationRepository.swift`
- `mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationDispatchUseCases.swift`
- `mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationScheduleUseCases.swift`
- `mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationQueryUseCases.swift`
- `mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationCategoryUseCases.swift`
- `mac/MacLibrary/MacLibrary/Notification/Data/Repository/NotificationRepositoryImpl.swift`
- `mac/MacLibrary/MacLibrary/Notification/Domain/Error/NotificationError.swift`
- `mac/MacLibrary/MacLibrary/Notification/Domain/Model/NotificationContent.swift`
- `mac/MacLibrary/MacLibrary/Notification/Domain/Model/NotificationTrigger.swift`
- `mac/MacLibrary/MacLibrary/Notification/Domain/Model/ActiveNotification.swift`
- `mac/MacLibrary/MacLibrary/Notification/Domain/Model/ScheduledNotification.swift`
- `mac/MacLibrary/MacLibrary/Notification/Domain/Model/NotificationCategory.swift`
- `mac/MacLibrary/MacLibrary/Notification/Domain/Model/NotificationAuthorizationStatus.swift`

### 新規（UnityMacPlugin）

- `mac/UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationManager.swift`
- `mac/UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationJsonParser.swift`
- `mac/UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationManagerBridge.h`
- `mac/UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationManagerBridge.m`

### 変更

- `mac/MacLibrary/MacLibrary/MacLibrary.h`（公開ヘッダ export 追加）
- `mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.h`（bridge ヘッダ export 追加）
- `mac/MacLibrary/MacLibrary/MacLibrary.docc/MacLibrary.md`（通知章追加）
- `mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.docc/UnityMacPlugin.md`（通知章追加）

## テスト設計

### 単体テスト

- 対象
  - UseCase 群（Dispatch/Schedule/Query/Category）
  - `NotificationPermissionHelper`
  - `UnityMacNotificationJsonParser`
- ケース
  - 正常系: show/schedule/query/category 登録
  - 異常系: add 失敗、JSON パース失敗、権限拒否
  - 境界値: 空 title/body、badge 0、attachments 0件/複数件
- モック方針
  - `NotificationRepository` モックに `shouldFail` + `xxxCallCount` + `stubbedXxx`。

### 統合テスト

- `MacNotificationManager` と `NotificationRepositoryImpl` を結合して以下を検証
  - `setup()` で delegate 登録される
  - pending / delivered 取得整合
  - category/action callback が Bridge へ到達
- Bridge 統合
  - C API の callback が `(isSuccess, errorMessage)` に正規化される
  - JSON 結果が UTF-8 で返る

### 手動確認

- 権限 request -> denied/authorized の分岐
- foreground 表示オプション切替
- category action / text input action 受信
- pending / delivered 一覧と削除
- Focus / Do Not Disturb 有効時の挙動
- `macOS 15` 実機での確認

## 実装タスク分解（依存関係付き）

1. 基盤モデル/エラー定義（1.0日）

- 依存: なし
- 完了条件: Domain モデルと `NotificationError` がコンパイル通過
- レビュー観点: Domain のプラットフォーム非依存性

2. Repository Port + UseCase 実装（1.0日）

- 依存: タスク1
- 完了条件: UseCase が Port 経由で動作、単体テスト追加
- レビュー観点: 依存方向、throw/非throw の分離

3. RepositoryImpl 実装（1.5日）

- 依存: タスク1,2
- 完了条件: show/schedule/query/category API 実装
- レビュー観点: エラー変換、UserNotifications API 使用妥当性

4. Manager + Delegate 実装（1.0日）

- 依存: タスク2,3
- 完了条件: `setup`、public API、action handler 完成
- レビュー観点: Delegate 所有の一元化、completion 呼び出し保証

5. Unity Swift facade + JSON parser（1.0日）

- 依存: タスク4
- 完了条件: JSON 入出力、manager 呼び出し接続
- レビュー観点: パース失敗時のエラー整形

6. Obj-C/C Bridge 実装（1.0日）

- 依存: タスク5
- 完了条件: C API と callback typedef 公開
- レビュー観点: メモリ境界、UTF-8 ポインタ寿命、HeaderDoc

7. テスト実装（1.5日）

- 依存: タスク2-6
- 完了条件: 単体/統合テスト追加・通過
- レビュー観点: リスク項目対応、異常系網羅

8. ドキュメント/マニュアル更新（0.5日）

- 依存: タスク4-6
- 完了条件: DocC 更新
- レビュー観点: API 例と実装一致

## リスクと緩和策

- 企画書と最小OS要件の不整合
  - 緩和: 本設計は `macOS 15+` 固定。企画書と同値を維持する。
- Delegate 多重設定で callback 取りこぼし
  - 緩和: `MacNotificationManager.setup()` のみで delegate 登録、他層禁止。
- Bridge 文字列ポインタ寿命
  - 緩和: callback 内有効であることを明記し、Unity 側で即時コピー。
- Focus/Do Not Disturb 差異
  - 緩和: 手動テストケースに強制追加。
- completionHandler 呼び出し漏れ
  - 緩和: `defer` で呼び出し保証、テストで検証。

## Definition of Done

- [ ] `MacNotificationManager` の公開 API が追加され、ビルドが通る
- [ ] `UNUserNotificationCenterDelegate` 所有が Manager 単独である
- [ ] 権限 request/status/settings open が動作する
- [ ] show/update/schedule/cancel/query が動作する
- [ ] delivered/pending の取得・削除が動作する
- [ ] category/action/text-input callback が動作する
- [ ] Unity C Bridge API が公開され、callback で結果を返せる
- [ ] UseCase 単体テストと Bridge 主要経路テストが通る
- [ ] Focus/Do Not Disturb 含む手動確認を完了する
- [ ] `macOS 15+` で実機検証済み
