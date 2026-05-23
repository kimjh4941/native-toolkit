# 企画書: macOS 通知機能

作成日: 2026-05-09
対象機能: 通知機能
対象 OS: macOS

## 公式文書一覧（最優先ソース）

- UserNotifications フレームワーク概要
  - https://developer.apple.com/documentation/usernotifications
- UNUserNotificationCenter
  - https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- 権限取得ガイド
  - https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
- UNMutableNotificationContent
  - https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent
- ローカル通知スケジューリング
  - https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app
- カテゴリ・アクション定義
  - https://developer.apple.com/documentation/usernotifications/declaring-your-actionable-notification-types
- 通知処理ガイド
  - https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions
- macOS APNs エンタイトルメント
  - https://developer.apple.com/documentation/BundleResources/Entitlements/com.apple.developer.aps-environment

## 目的

macOS アプリケーションに通知機能を追加する。ローカル通知の送信、管理、応答処理を網羅し、native-toolkit への実装基盤を提供する。

## 調査対象範囲（in / out）

### in

- ローカル通知の権限取得
- 通知コンテンツの構築（タイトル、本文、サウンド、バッジ、添付ファイル）
- トリガー設定（時間間隔、カレンダー日時、ロケーション）
- 通知のスケジューリングとキャンセル
- 配信済み通知の取得、削除
- カテゴリとアクションボタンの定義
- デリゲートによるフォアグラウンド受信、アクション応答処理

### out

- リモート通知（APNs、Push）
- Notification Service Extension
- Notification Content Extension（カスタム UI）
- Safari Web Push
- PushKit（VoIP 専用）

## 補助ソース一覧（必要時のみ）

- なし（公式文書のみで網羅可能）

## 機能マップ（サブ機能分解）

- 1. 権限取得
  - 明示的権限リクエスト
  - 仮権限（Provisional）リクエスト
- 2. 通知コンテンツ構築
  - 基本テキスト（title / subtitle / body）
  - サウンド設定
  - バッジカウント設定
  - 添付ファイル（UNNotificationAttachment）
  - グループ化（threadIdentifier）
- 3. トリガー設定
  - 時間間隔トリガー（UNTimeIntervalNotificationTrigger）
  - カレンダートリガー（UNCalendarNotificationTrigger）
  - ロケーショントリガー（UNLocationNotificationTrigger）
- 4. スケジューリング管理
  - 通知追加（add）
  - 保留中通知の取得、削除
  - 配信済み通知の取得、削除
- 5. カテゴリ、アクション定義
  - アクションボタン（UNNotificationAction）
  - テキスト入力アクション（UNTextInputNotificationAction）
  - カテゴリ登録（UNNotificationCategory）
- 6. デリゲート処理
  - フォアグラウンド受信（willPresent）
  - アクション応答（didReceive）

## API 全網羅表（サブ機能別）

### サブ機能 1: 権限取得

| API                                              | 目的               | 主要引数                        | 返却値                   | エラーケース           | 最小利用条件 |
| ------------------------------------------------ | ------------------ | ------------------------------- | ------------------------ | ---------------------- | ------------ |
| UNUserNotificationCenter.current()               | シングルトン取得   | なし                            | UNUserNotificationCenter | なし                   | macOS 10.14+ |
| requestAuthorization(options:completionHandler:) | 通知権限リクエスト | options: UNAuthorizationOptions | (Bool, Error?)           | 権限拒否、設定無効など | macOS 10.14+ |
| getNotificationSettings(completionHandler:)      | 現在の権限状態取得 | なし                            | UNNotificationSettings   | なし                   | macOS 10.14+ |

### サブ機能 2: 通知コンテンツ構築

| API / プロパティ             | 目的               | 主要要素                                                   |
| ---------------------------- | ------------------ | ---------------------------------------------------------- |
| UNMutableNotificationContent | 通知内容定義       | title, subtitle, body, sound, badge, attachments, userInfo |
| categoryIdentifier           | カテゴリ紐付け     | 事前登録カテゴリ ID と一致必須                             |
| threadIdentifier             | 通知グループ化     | 関連通知を束ねる                                           |
| interruptionLevel            | 割り込みレベル設定 | passive, active, timeSensitive, critical                   |
| relevanceScore               | サマリー優先度     | 0.0 から 1.0                                               |

### サブ機能 3: トリガー設定

| API                               | 目的           | 主要引数              | 注意点                   |
| --------------------------------- | -------------- | --------------------- | ------------------------ |
| UNTimeIntervalNotificationTrigger | 指定秒後に配信 | timeInterval, repeats | timeInterval >= 1        |
| UNCalendarNotificationTrigger     | 指定日時に配信 | dateMatching, repeats | DateComponents の整合性  |
| UNLocationNotificationTrigger     | 位置条件で配信 | region, repeats       | Core Location 権限が必要 |

### サブ機能 4: スケジューリング管理

| API                                                 | 目的                   |
| --------------------------------------------------- | ---------------------- |
| UNNotificationRequest(identifier:content:trigger:)  | 通知要求を生成         |
| add(\_:withCompletionHandler:)                      | 通知をスケジュール登録 |
| getPendingNotificationRequests(completionHandler:)  | 保留中通知を取得       |
| removePendingNotificationRequests(withIdentifiers:) | 指定保留通知を削除     |
| removeAllPendingNotificationRequests()              | 全保留通知を削除       |
| getDeliveredNotifications(completionHandler:)       | 配信済み通知を取得     |
| removeDeliveredNotifications(withIdentifiers:)      | 指定配信済み通知を削除 |
| removeAllDeliveredNotifications()                   | 全配信済み通知を削除   |
| setBadgeCount(\_:withCompletionHandler:)            | バッジ数を更新         |

### サブ機能 5: カテゴリ、アクション定義

| API                                           | 目的                   |
| --------------------------------------------- | ---------------------- |
| UNNotificationAction                          | アクションボタン定義   |
| UNTextInputNotificationAction                 | 入力付きアクション定義 |
| UNNotificationCategory                        | カテゴリ定義           |
| setNotificationCategories(\_:)                | カテゴリ登録           |
| getNotificationCategories(completionHandler:) | カテゴリ取得           |

### サブ機能 6: デリゲート処理

| メソッド                                                      | 目的                     |
| ------------------------------------------------------------- | ------------------------ |
| userNotificationCenter(\_:willPresent:withCompletionHandler:) | フォアグラウンド表示制御 |
| userNotificationCenter(\_:didReceive:withCompletionHandler:)  | アクション応答処理       |
| userNotificationCenter(\_:openSettingsFor:)                   | 通知設定遷移補助         |

## 実装リスク（権限、制約、互換性）

- 権限未取得だと通知が届かない
- provisional は静かな通知のみで、バナー、サウンド、バッジに制限がある
- delegate を早期設定しないと受信ハンドリングを取りこぼす
- location trigger は macOS 上の挙動検証が必要
- critical alert や time sensitive は追加エンタイトルメントが必要
- 一部 API は OS バージョン差異や deprecation があるため要検証

## 簡単なサンプルコード集（サブ機能別）

### 1) 権限取得

```swift
import UserNotifications

func requestPermission() async {
    let center = UNUserNotificationCenter.current()
    do {
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        print("granted: \(granted)")
    } catch {
        print("error: \(error)")
    }
}
```

### 2) ローカル通知のスケジュール

```swift
func scheduleNotification() async {
    let content = UNMutableNotificationContent()
    content.title = "Reminder"
    content.body = "5秒後に通知します"
    content.sound = .default

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
    let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)

    do {
        try await UNUserNotificationCenter.current().add(request)
    } catch {
        print("schedule failed: \(error)")
    }
}
```

### 3) カテゴリとアクション登録

```swift
func registerCategories() {
    let accept = UNNotificationAction(identifier: "ACCEPT", title: "承認", options: [.foreground])
    let decline = UNNotificationAction(identifier: "DECLINE", title: "却下", options: [.destructive])
    let category = UNNotificationCategory(
        identifier: "MEETING_INVITE",
        actions: [accept, decline],
        intentIdentifiers: [],
        options: []
    )

    UNUserNotificationCenter.current().setNotificationCategories([category])
}
```

### 4) デリゲートで応答処理

```swift
import UserNotifications

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        switch response.actionIdentifier {
        case "ACCEPT":
            print("accepted")
        case "DECLINE":
            print("declined")
        default:
            break
        }
        completionHandler()
    }
}
```

## Definition of Done

- [ ] requestAuthorization で権限を取得できる
- [ ] title、body、sound を含む通知を作成できる
- [ ] time interval trigger で通知を配信できる
- [ ] calendar trigger で定期通知を配信できる
- [ ] pending と delivered の通知を取得、削除できる
- [ ] カテゴリ、アクションを登録し応答処理できる
- [ ] フォアグラウンド時の表示挙動を制御できる
- [ ] macOS 10.14+ で実機検証済み
