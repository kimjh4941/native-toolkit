# 実装設計書: macOS 通知機能（改善版 v3）

## 対象企画書

- artifact/plans/notification/2026-05-09-macos-notification-research-v2.md

## 設計目的

- MacLibrary と UnityMacPlugin にローカル通知機能を追加する。
- 既存 Dialog 実装と同じ層分離を維持し、Unity 向け C ABI を安全に提供する。

## スコープ（in / out）

### in

- 権限取得（request, status, settings open）
- 通知表示（immediate, trigger）
- 通知更新（identifier 指定）
- スケジュール管理（追加、取得、取消）
- 配信済み管理（取得、削除）
- カテゴリ/アクション登録
- デリゲート処理（foreground 表示、action 応答）
- Unity Bridge（Swift facade + Obj-C/C bridge）
- バッジ更新

### out

- APNs/remote push
- Notification Service Extension
- Notification Content Extension
- Safari Web Push
- PushKit

## 企画書トレーサビリティ

| 要件ID | 企画書要件           | 設計セクション       | 実装タスク | テスト観点                    |
| ------ | -------------------- | -------------------- | ---------- | ----------------------------- |
| R-01   | 権限取得             | サブ機能 1           | T2, T3, T4 | P-STATUS, P-DENY              |
| R-02   | 通知表示/更新        | サブ機能 2           | T2, T3, T4 | SHOW-OK, SHOW-ERR, UPDATE-ERR |
| R-03   | スケジュール管理     | サブ機能 3           | T2, T3, T4 | SCH-ADD, SCH-CANCEL           |
| R-04   | 配信済み管理         | サブ機能 4           | T2, T3, T4 | DEL-GET, DEL-REMOVE           |
| R-05   | カテゴリ/アクション  | サブ機能 5, 6        | T3, T4, T6 | ACT-BTN, ACT-TEXT             |
| R-06   | Focus/Do Not Disturb | リスクと緩和策       | T7, T8     | FOCUS-MANUAL                  |
| R-07   | 最小OS               | 共通方針適用チェック | T8         | OS-GATE                       |

## 共通実装方針の適用チェック（common.md 準拠）

- Clean Architecture: 適合
- 依存方向: 適合
- Delegate 所有: 適合（Manager 単独）
- TDD 方針: 適合（UseCase 単位）
- エラー変換: 適合（RepositoryImpl -> DomainError -> PublicError）
- Minimum OS Versions: 要件確定済み
  - 本設計のサポート対象は macOS 15+ 固定
  - 非対応OSでは `unsupportedOS` を返し機能実行しない

## 個別実装方針の適用チェック（mac.md 準拠）

- ログ: public/internal/override/@objc の先頭に Log.d、異常系は Log.e
- コメント: Swift public API は DocC、Obj-C 公開ヘッダは HeaderDoc
- 言語: コメント・ユーザー向け文言とも英語

## 既存実装差分サマリー

- 現状 mac は Dialog 機能のみ（通知機能は未実装）
- 追加区分: API 追加、C ABI 追加、DocC 追加
- 互換性評価
  - 既存 API の変更/削除: なし
  - シンボル追加による ABI 影響: 追加のみ（非破壊）
  - 名前衝突リスク: Notification 名前空間を新規ディレクトリ配下に限定して回避

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

## スレッド/メモリ契約（公開API契約）

### スレッド契約

- 公開 callback はすべて main queue で実行する。
- `UNUserNotificationCenterDelegate` 受信後、Bridge callback 呼び出し前に main queue へ正規化する。

### C Bridge メモリ契約

- 文字列ポインタは callback 実行中のみ有効。
- Unity 側は callback 内で即時コピーする。
- JSON 返却は UTF-8 NUL 終端。
- 所有権は callee 側保持。caller は free しない。
- 将来の安全化案として caller-provided buffer 方式を候補にする（本リリースは現行契約）。

## API 契約表（公開）

| API                      | 目的               | 失敗条件                                                        | 副作用             | idempotency |
| ------------------------ | ------------------ | --------------------------------------------------------------- | ------------------ | ----------- |
| requestPermission        | 権限要求           | permissionDenied, permissionRequestFailed                       | OS 権限ダイアログ  | N/A         |
| getAuthorizationStatus   | 現在権限状態取得   | unsupportedOS                                                   | なし               | yes         |
| openNotificationSettings | 設定画面遷移       | openSettingsFailed                                              | システム設定を開く | N/A         |
| show                     | 即時/トリガ表示    | invalidContent, invalidTrigger, addFailed                       | 通知登録           | no          |
| update                   | 既存通知更新       | notificationNotFound, invalidContent, invalidTrigger, addFailed | pending 置換       | no          |
| schedule                 | 将来通知登録       | invalidContent, invalidTrigger, addFailed                       | pending 追加       | no          |
| cancel                   | pending 取消       | removeFailed                                                    | pending 削除       | yes         |
| cancelAllScheduled       | 全 pending 取消    | removeFailed                                                    | pending 削除       | yes         |
| getScheduled             | pending 一覧取得   | queryFailed                                                     | なし               | yes         |
| getDelivered             | delivered 一覧取得 | queryFailed                                                     | なし               | yes         |
| removeDelivered          | delivered 単体削除 | removeFailed                                                    | delivered 削除     | yes         |
| removeAllDelivered       | delivered 全削除   | removeFailed                                                    | delivered 削除     | yes         |
| registerCategory         | category 登録      | invalidCategory                                                 | category set 更新  | overwrite   |
| removeCategory           | category 削除      | invalidCategory                                                 | category set 更新  | overwrite   |
| setBadgeCount            | バッジ更新         | setBadgeFailed                                                  | バッジ値更新       | overwrite   |

## API 入力スキーマ（公開）

| API              | 入力          | 必須/任意 | 制約                           |
| ---------------- | ------------- | --------- | ------------------------------ |
| show             | content.id    | 必須      | 1..128, 英数字+`-_`            |
| show             | content.title | 必須      | 1..128                         |
| show             | content.body  | 任意      | 0..1024                        |
| schedule         | trigger.type  | 必須      | timeInterval/calendar/location |
| schedule         | timeInterval  | 条件必須  | `>= 1` 秒                      |
| update           | identifier    | 必須      | 1..128                         |
| registerCategory | category.id   | 必須      | 1..64                          |
| setBadgeCount    | count         | 必須      | `0..9999`                      |

## ドメインエラー一覧（全ケース）

```swift
public enum NotificationDomainError: Error {
  case unsupportedOS(minimum: String)
  case permissionDenied
  case permissionRequestFailed(underlying: Error)
  case invalidContent(reason: String)
  case invalidTrigger(reason: String)
  case invalidCategory(reason: String)
  case notificationNotFound(identifier: String)
  case addFailed(underlying: Error)
  case removeFailed(underlying: Error)
  case queryFailed(underlying: Error)
  case setBadgeFailed(underlying: Error)
  case openSettingsFailed(underlying: Error)
  case unknown(underlying: Error)
}

public enum BridgeError: Error {
  case parseFailed(reason: String)
  case contractViolation(reason: String)
}
```

## エラーコード/メッセージ対応表

公開返却形式は `(isSuccess: Bool, errorCode: Int, errorMessage: String?)`。
`isSuccess == true` の場合は `errorCode = 0`, `errorMessage = nil`。

### 採番規約

- 1000 台: OS/権限
- 1100 台: 入力検証
- 1200 台: 実行失敗
- 1300 台: Bridge/JSON
- 1900 台: フォールバック

| Error                   | errorCode | errorMessage                                 |
| ----------------------- | --------: | -------------------------------------------- |
| unsupportedOS           |      1001 | Unsupported OS. Requires {minimum} or later. |
| permissionDenied        |      1002 | Notification permission denied.              |
| permissionRequestFailed |      1003 | Failed to request notification permission.   |
| invalidContent          |      1101 | Invalid notification content: {reason}       |
| invalidTrigger          |      1102 | Invalid notification trigger: {reason}       |
| invalidCategory         |      1103 | Invalid notification category: {reason}      |
| notificationNotFound    |      1104 | Notification not found: {identifier}         |
| addFailed               |      1201 | Failed to add notification request.          |
| removeFailed            |      1202 | Failed to remove notification.               |
| queryFailed             |      1203 | Failed to query notifications.               |
| setBadgeFailed          |      1204 | Failed to set badge count.                   |
| openSettingsFailed      |      1205 | Failed to open notification settings.        |
| parseFailed             |      1301 | Failed to parse JSON: {reason}               |
| contractViolation       |      1302 | Bridge contract violation: {reason}          |
| unknown                 |      1999 | Unknown notification error.                  |

## サブ機能別詳細設計

### 1. 権限取得

- 追加API
  - requestPermission(options:, completion:)
  - getAuthorizationStatus(completion:)
  - openNotificationSettings()
- エラー
  - permissionDenied
  - permissionRequestFailed
  - unsupportedOS
  - openSettingsFailed

### 2. 通知表示/更新

- 追加API
  - show(content:trigger:completion:)
  - update(identifier:content:trigger:completion:)
- 設計方針
  - ドメイン制約検証は UseCase 層で実施
  - Manager は変換/オーケストレーションのみ

### 3. スケジュール管理

- 追加API
  - schedule(content:trigger:identifier:completion:)
  - cancelScheduled(identifier:)
  - cancelAllScheduled()
  - getScheduled(completion:)

### 4. 配信済み管理

- 追加API
  - getDelivered(completion:)
  - removeDelivered(identifier:)
  - removeAllDelivered()

### 5. カテゴリ/アクション

- 追加API
  - registerCategory(\_:)
  - removeCategory(identifier:)
  - setActionReceivedHandler(\_:)
  - setTextInputActionReceivedHandler(\_:)

### 6. デリゲート処理

- Manager が `UNUserNotificationCenterDelegate` を単独実装
- `willPresent`/`didReceive` は completion を必ず呼ぶ
- callback 前に main queue 正規化

## 変更対象ファイル（具体パス）

### 新規（MacLibrary）

- mac/MacLibrary/MacLibrary/Notification/MacNotificationManager.swift
- mac/MacLibrary/MacLibrary/Notification/Presentation/Permission/NotificationPermissionHelper.swift
- mac/MacLibrary/MacLibrary/Notification/Application/Port/NotificationRepository.swift
- mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationDispatchUseCases.swift
- mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationScheduleUseCases.swift
- mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationQueryUseCases.swift
- mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationCategoryUseCases.swift
- mac/MacLibrary/MacLibrary/Notification/Data/Repository/NotificationRepositoryImpl.swift
- mac/MacLibrary/MacLibrary/Notification/Domain/Error/NotificationDomainError.swift
- mac/MacLibrary/MacLibrary/Notification/Domain/Error/BridgeError.swift
- mac/MacLibrary/MacLibrary/Notification/Domain/Model/NotificationContent.swift
- mac/MacLibrary/MacLibrary/Notification/Domain/Model/NotificationTrigger.swift
- mac/MacLibrary/MacLibrary/Notification/Domain/Model/ActiveNotification.swift
- mac/MacLibrary/MacLibrary/Notification/Domain/Model/ScheduledNotification.swift
- mac/MacLibrary/MacLibrary/Notification/Domain/Model/NotificationCategory.swift
- mac/MacLibrary/MacLibrary/Notification/Domain/Model/NotificationAuthorizationStatus.swift

### 新規（UnityMacPlugin）

- mac/UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationManager.swift
- mac/UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationJsonParser.swift
- mac/UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationManagerBridge.h
- mac/UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationManagerBridge.m

### 変更

- mac/MacLibrary/MacLibrary/MacLibrary.h
- mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.h
- mac/MacLibrary/MacLibrary/MacLibrary.docc/MacLibrary.md
- mac/UnityMacPlugin/UnityMacPlugin/UnityMacPlugin.docc/UnityMacPlugin.md

### Xcode プロジェクト設定チェックリスト

- 追加ファイルの target membership 設定
- 公開ヘッダ visibility を Public に設定
- Build Phases の Headers/Compile Sources 反映
- Module export の反映（umbrella header 経由）
- DocC カタログへの新章追加確認

## テスト設計

### 単体テスト

- UseCase（Dispatch/Schedule/Query/Category）
- NotificationPermissionHelper
- UnityMacNotificationJsonParser
- Repository モック（shouldFail, callCount, stubbedXxx）

### テストマトリクス

| 分類          | ケース                                                                     |
| ------------- | -------------------------------------------------------------------------- |
| 権限          | notDetermined, denied, authorized                                          |
| Trigger       | immediate, timeInterval, calendar, location                                |
| Action        | button, textInput                                                          |
| Error mapping | 1001,1002,1003,1101,1102,1103,1104,1201,1202,1203,1204,1205,1301,1302,1999 |
| Callback      | main queue 保証, completion 呼び忘れなし                                   |
| Concurrency   | 同時 show/update 競合、cancel と getScheduled 競合                         |

### エラー対応表テスト（必須）

- 全エラーケースについて errorCode/errorMessage を検証
- unknown は常に 1999 へフォールバック
- success 時は `errorCode == 0` かつ `errorMessage == nil`

### 統合テスト

- Manager + RepositoryImpl
  - setup で delegate 登録
  - pending/delivered 整合
  - action callback 到達
- Bridge
  - C callback の成功/失敗正規化
  - UTF-8 JSON 返却
  - callback 内文字列寿命契約

### 実行戦略

- CI: モック中心の deterministic テスト
- 実機E2E: 通知表示、Focus/Do Not Disturb、権限ダイアログ

## 実装タスク分解（依存関係付き）

- T1 Domain Error/Model 定義（1.0日）
  - 依存: なし
- T2 UseCase + 入力検証（1.0日）
  - 依存: T1
- T3 RepositoryImpl（1.5日）
  - 依存: T1,T2
- T4 Manager + Delegate（1.0日）
  - 依存: T2,T3
- T5 Unity Swift facade + JSON parser（1.0日）
  - 依存: T4
- T6 Obj-C/C Bridge（1.0日）
  - 依存: T5
- T7 Test 実装（1.5日）
  - 依存: T2-T6
- T8 Docs/manual 更新（0.5日）
  - 依存: T4-T6

## リスクと緩和策

- 最小OS要件不整合
  - 緩和: macOS 15+ を仕様確定し、research/design 同期
- Delegate 多重設定
  - 緩和: setup 一元化、他層で delegate 設定禁止
- C Bridge ポインタ寿命誤用
  - 緩和: 契約明記、Unity 側即時コピー、誤用テスト
- Focus/Do Not Disturb 差異
  - 緩和: 実機E2E必須、要求受理と表示可否を分離
- completion 呼び漏れ
  - 緩和: defer で保証、テストで検証

## Definition of Done

- [ ] 企画書要件と設計/タスク/テストのトレース表が埋まっている
- [ ] API 契約表が in-scope と 1:1 対応している
- [ ] ドメインエラー全ケースとエラー対応表が一致している
- [ ] 公開 callback が main queue で実行される
- [ ] C Bridge メモリ契約がヘッダに明記される
- [ ] error mapping と API 契約がテストで担保される
- [ ] CI テストと実機E2Eが分離運用される
- [ ] macOS 15+ 実機で検証済み
