# 実装設計書: macOS 通知機能（改善版 v2）

## 対象企画書

- artifact/plans/notification/2026-05-09-macos-notification-research-v2.md

## 設計目的

- MacLibrary と UnityMacPlugin にローカル通知機能を追加する。
- 既存 Dialog 実装と同じ層分離を維持し、Unity 向け C ABI を安全に提供する。

## スコープ（in / out）

### in

- 権限取得（request, status, settings open）
- 通知表示（immediate, trigger）
- スケジュール管理（追加、取得、取消）
- 配信済み管理（取得、削除）
- カテゴリ/アクション登録
- デリゲート処理（foreground 表示、action 応答）
- Unity Bridge（Swift facade + Obj-C/C bridge）

### out

- APNs/remote push
- Notification Service Extension
- Notification Content Extension
- Safari Web Push
- PushKit

## 企画書トレーサビリティ

| 要件ID | 企画書要件           | 設計セクション       | 実装タスク | テスト観点          |
| ------ | -------------------- | -------------------- | ---------- | ------------------- |
| R-01   | 権限取得             | サブ機能 1           | T2, T3, T4 | P-STATUS, P-DENY    |
| R-02   | 通知表示             | サブ機能 2           | T2, T3, T4 | SHOW-OK, SHOW-ERR   |
| R-03   | スケジュール管理     | サブ機能 3           | T2, T3, T4 | SCH-ADD, SCH-CANCEL |
| R-04   | 配信済み管理         | サブ機能 4           | T2, T3, T4 | DEL-GET, DEL-REMOVE |
| R-05   | カテゴリ/アクション  | サブ機能 5, 6        | T3, T4, T6 | ACT-BTN, ACT-TEXT   |
| R-06   | Focus/Do Not Disturb | リスクと緩和策       | T7, T8     | FOCUS-MANUAL        |
| R-07   | 最小OS               | 共通方針適用チェック | T8         | OS-GATE             |

## 共通実装方針の適用チェック（common.md 準拠）

- Clean Architecture: 適合
- 依存方向: 適合
- Delegate 所有: 適合（Manager 単独）
- TDD 方針: 適合（UseCase 単位）
- エラー変換: 適合（RepositoryImpl -> NotificationError -> Manager）
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

| API               | 目的            | 失敗条件                    | 副作用            | idempotency |
| ----------------- | --------------- | --------------------------- | ----------------- | ----------- |
| requestPermission | 権限要求        | denied, system error        | OS 権限ダイアログ | N/A         |
| show              | 即時/トリガ表示 | content invalid, add failed | 通知センター登録  | no          |
| update            | 既存通知更新    | id not found, add failed    | pending 置換      | no          |
| schedule          | 将来通知登録    | trigger invalid, add failed | pending 追加      | no          |
| cancel            | pending 取消    | なし                        | pending 削除      | yes         |
| getScheduled      | pending 一覧    | なし                        | なし              | yes         |
| getDelivered      | delivered 一覧  | なし                        | なし              | yes         |
| registerCategory  | category 登録   | invalid category            | category set 更新 | overwrite   |

## NotificationError 定義（全ケース）

`NotificationError` は Domain 層で定義し、RepositoryImpl がシステムエラーを変換する。

```swift
public enum NotificationError: Error {
  case unsupportedOS(minimum: String)
  case permissionDenied
  case invalidContent(reason: String)
  case invalidTrigger(reason: String)
  case invalidCategory(reason: String)
  case addFailed(underlying: Error)
  case removeFailed(underlying: Error)
  case queryFailed(underlying: Error)
  case setBadgeFailed(underlying: Error)
  case openSettingsFailed(underlying: Error)
  case parseFailed(reason: String)
  case bridgeContractViolation(reason: String)
  case unknown(underlying: Error)
}
```

補足:

- `removeFailed` / `queryFailed` は将来 API 拡張を見据えた定義で、現在の Apple API が非throwでも統一的に扱う。
- `bridgeContractViolation` は C callback 契約違反（NULL 不正、文字列寿命違反の検知など）に使用する。

## エラーコード/メッセージ対応表（Bridge 返却仕様）

Bridge の公開 API は `(isSuccess: Bool, errorCode: Int, errorMessage: String?)` へ正規化する。
`isSuccess == true` の場合は `errorCode = 0`, `errorMessage = nil`。

| Domain Error                    | errorCode | errorMessage テンプレート                      | 主な発生箇所              |
| ------------------------------- | --------: | ---------------------------------------------- | ------------------------- |
| unsupportedOS(minimum)          |      1001 | `Unsupported OS. Requires {minimum} or later.` | Manager 起動時ガード      |
| permissionDenied                |      1002 | `Notification permission denied.`              | requestPermission         |
| invalidContent(reason)          |      1101 | `Invalid notification content: {reason}`       | UseCase 検証              |
| invalidTrigger(reason)          |      1102 | `Invalid notification trigger: {reason}`       | UseCase 検証              |
| invalidCategory(reason)         |      1103 | `Invalid notification category: {reason}`      | category 登録             |
| addFailed(\_)                   |      1201 | `Failed to add notification request.`          | show/update/schedule      |
| removeFailed(\_)                |      1202 | `Failed to remove notification.`               | remove/cancel 系          |
| queryFailed(\_)                 |      1203 | `Failed to query notifications.`               | getScheduled/getDelivered |
| setBadgeFailed(\_)              |      1204 | `Failed to set badge count.`                   | setBadgeCount             |
| openSettingsFailed(\_)          |      1205 | `Failed to open notification settings.`        | openNotificationSettings  |
| parseFailed(reason)             |      1301 | `Failed to parse JSON: {reason}`               | Unity JSON parser         |
| bridgeContractViolation(reason) |      1302 | `Bridge contract violation: {reason}`          | C Bridge                  |
| unknown(\_)                     |      1999 | `Unknown notification error.`                  | 例外フォールバック        |

運用ルール:

- ログには詳細（underlying エラー）を出すが、Bridge 返却 `errorMessage` は安定した英語テンプレートを返す。
- `errorCode` は後方互換のためリリース後に再利用しない。
- manual と DocC には公開 API で返る代表コード（1001, 1002, 1101, 1201, 1301）を記載する。

## サブ機能別詳細設計

### 1. 権限取得

- 変更対象
  - MacLibrary/Notification/Presentation/Permission
  - MacLibrary/Notification/Manager
  - UnityMacPlugin/Notification
- 追加API
  - requestPermission(options:, completion:)
  - authorizationStatus(completion:)
  - openNotificationSettings()
- エラー
  - denied -> NotificationError.permissionDenied
  - unsupported OS -> NotificationError.unsupportedOS

### 2. 通知表示/更新

- 変更対象
  - MacLibrary/Notification/Domain/Model
  - MacLibrary/Notification/Application/UseCase
  - MacLibrary/Notification/Data/Repository
  - MacLibrary/Notification/Manager
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
- 補足
  - identifier 重複時の挙動を API 契約に明記する

### 4. 配信済み管理

- 追加API
  - removeDelivered(identifier:)
  - removeAllDelivered()
  - getDelivered(completion:)

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
- mac/MacLibrary/MacLibrary/Notification/Domain/Error/NotificationError.swift
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
- 公開ヘッダの visibility を Public に設定
- Build Phases の Headers/Compile Sources 反映
- Module export の反映（umbrella header 経由）
- DocC カタログへの新章追加確認

## テスト設計

### 単体テスト

- UseCase（Dispatch/Schedule/Query/Category）
- NotificationPermissionHelper
- UnityMacNotificationJsonParser
- NotificationRepository モック（shouldFail, callCount, stubbedXxx）

### テストマトリクス（最小）

| 分類          | ケース                                                  |
| ------------- | ------------------------------------------------------- |
| 権限          | notDetermined, denied, authorized                       |
| Trigger       | immediate, timeInterval, calendar, location             |
| Action        | button, textInput                                       |
| Error mapping | addFailed, permissionDenied, unsupportedOS, parseFailed |
| Callback      | main queue 保証, completion 呼び忘れなし                |

### エラー対応表テスト（必須）

- `NotificationError` の全ケースについて `errorCode` と `errorMessage` を検証する。
- unknown は常に 1999 へフォールバックすることを検証する。
- `isSuccess == true` 時は `errorCode == 0` かつ `errorMessage == nil` を検証する。

### 統合テスト

- Manager + RepositoryImpl
  - setup で delegate 登録
  - pending/delivered の整合
  - action callback 到達
- Bridge
  - C callback の成功/失敗正規化
  - UTF-8 JSON 返却

### 実行戦略

- CI: モック中心の deterministic テスト
- 実機E2E: 通知表示、Focus/Do Not Disturb、権限ダイアログ

### 手動確認

- request -> denied/authorized
- foreground presentation option 切替
- category action/text input callback
- pending/delivered 取得/削除
- Focus/Do Not Disturb 状態での挙動
- macOS 15 実機確認

## 実装タスク分解（依存関係付き）

1. T1 基盤モデル/エラー定義（1.0日）

- 依存: なし
- 完了条件: Domain モデル、NotificationError、unsupportedOS 追加
- テスト: モデル検証テスト

2. T2 Port + UseCase 実装（1.0日）

- 依存: T1
- 完了条件: UseCase 実装、責務分離（検証は UseCase）
- テスト: UseCase 単体（必須）

3. T3 RepositoryImpl 実装（1.5日）

- 依存: T1, T2
- 完了条件: show/schedule/query/category 実装
- テスト: error mapping 単体（必須）

4. T4 Manager + Delegate 実装（1.0日）

- 依存: T2, T3
- 完了条件: setup, callback, main queue 正規化
- テスト: delegate 経路テスト（必須）

5. T5 Unity Swift facade + JSON parser（1.0日）

- 依存: T4
- 完了条件: JSON 入出力と manager 接続
- テスト: parse 成功/失敗

6. T6 Obj-C/C Bridge 実装（1.0日）

- 依存: T5
- 完了条件: C API, typedef, HeaderDoc, lifetime 契約明文化
- テスト: callback 契約テスト

7. T7 統合/実機テスト（1.5日）

- 依存: T2-T6
- 完了条件: CI + 実機確認完了

8. T8 ドキュメント更新（0.5日）

- 依存: T4-T6
- 完了条件: DocC 更新、OS要件整合

## リスクと緩和策

- 最小OS要件不整合
  - 緩和: macOS 15+ を仕様確定し、research/design 同期
- Delegate 多重設定
  - 緩和: setup 一元化、他層で delegate 設定禁止
- C Bridge ポインタ寿命誤用
  - 緩和: 契約明記、Unity 側即時コピー、誤用テスト
- Focus/Do Not Disturb 差異
  - 緩和: 実機E2E必須、結果モデルで「要求受理」と「表示可否」を分離
- completion 呼び漏れ
  - 緩和: defer で保証、テストで強制検証

## Definition of Done

- [ ] 企画書要件と設計/タスク/テストのトレース表が埋まっている
- [ ] MacNotificationManager が delegate を単独所有する
- [ ] 公開 callback が main queue で実行される
- [ ] C Bridge メモリ契約がヘッダに明記される
- [ ] 権限/表示/スケジュール/配信済み/カテゴリが実装される
- [ ] error mapping と API 契約がテストで担保される
- [ ] CI テストと実機E2Eが分離運用される
- [ ] macOS 15+ 実機で検証済み
