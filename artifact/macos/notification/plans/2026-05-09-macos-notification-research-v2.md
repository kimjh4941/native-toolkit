# 企画書: macOS 通知機能（改善版 v2）

作成日: 2026-05-09  
改善日: 2026-05-09  
対象機能: 通知機能
対象 OS: macOS

## 公式文書一覧（最優先ソース）

- UserNotifications フレームワーク概要
  - https://developer.apple.com/documentation/usernotifications
- UNUserNotificationCenter
  - https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- UNNotificationTrigger プロトコル
  - https://developer.apple.com/documentation/usernotifications/unnotificationtrigger
- UNNotificationRequest
  - https://developer.apple.com/documentation/usernotifications/unnotificationrequest
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
- Do Not Disturb と Focus Mode
  - https://developer.apple.com/documentation/usernotifications

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
  - サウンド設定（システムサウンド / カスタムサウンド）
  - バッジカウント設定
  - 添付ファイル（UNNotificationAttachment）
  - グループ化（threadIdentifier）
  - 割り込みレベル設定（interruptionLevel）
- 3. トリガー設定
  - 時間間隔トリガー（UNTimeIntervalNotificationTrigger）
  - カレンダートリガー（UNCalendarNotificationTrigger）
  - ロケーショントリガー（UNLocationNotificationTrigger）
- 4. スケジューリング管理
  - 通知追加（add）
  - 保留中通知の取得、削除
  - 配信済み通知の取得、削除
  - 大量通知時のパフォーマンス管理
- 5. カテゴリ、アクション定義
  - アクションボタン（UNNotificationAction）
  - テキスト入力アクション（UNTextInputNotificationAction）
  - カテゴリ登録（UNNotificationCategory）
- 6. デリゲート処理
  - フォアグラウンド受信（willPresent）
  - アクション応答（didReceive）
  - 応答時間制限とスレッド安全性

## API 全網羅表（サブ機能別）

### サブ機能 1: 権限取得

| API                                              | 目的               | 主要引数                        | 返却値                   | エラーケース           | 最小利用条件 |
| ------------------------------------------------ | ------------------ | ------------------------------- | ------------------------ | ---------------------- | ------------ |
| UNUserNotificationCenter.current()               | シングルトン取得   | なし                            | UNUserNotificationCenter | なし                   | macOS 10.14+ |
| requestAuthorization(options:completionHandler:) | 通知権限リクエスト | options: UNAuthorizationOptions | (Bool, Error?)           | 権限拒否、設定無効など | macOS 10.14+ |
| getNotificationSettings(completionHandler:)      | 現在の権限状態取得 | なし                            | UNNotificationSettings   | なし                   | macOS 10.14+ |

### サブ機能 2: 通知コンテンツ構築

| API / プロパティ             | 目的               | 主要要素・詳細                                                                                              |
| ---------------------------- | ------------------ | ----------------------------------------------------------------------------------------------------------- |
| UNMutableNotificationContent | 通知内容定義       | title, subtitle, body, sound, badge, attachments, userInfo                                                  |
| sound                        | サウンド設定       | .default（システムデフォルト）または soundName（カスタムファイル名、.aiff / .wav / .caf。拡張子不要）       |
| soundName                    | カスタムサウンド   | バンドルに含まれるファイル名。無効なファイル名は無音にフォールバック                                        |
| categoryIdentifier           | カテゴリ紐付け     | 事前登録カテゴリ ID と一致必須                                                                              |
| threadIdentifier             | 通知グループ化     | 同じ threadIdentifier の複数通知は自動的にまとめられ、最新通知が表示される。既存通知は自動削除されない      |
| interruptionLevel            | 割り込みレベル設定 | passive（無音、バッジのみ）/ active（バナー + サウンド）/ timeSensitive（時間に敏感）/ critical（重大度高） |
| summaryArgument              | サマリー優先度用   | 通知サマリーで使用される文字列（複数通知の概要表示時）                                                      |
| summaryArgumentCount         | サマリー数値       | サマリー表示時の個数（例: "5 messages"）                                                                    |
| userInfo                     | カスタムデータ     | 任意の辞書データ。デリゲートコールバックで取得可能。必ず propertyList-compatible 型を使用                   |
| relevanceScore               | サマリー優先度     | 0.0 から 1.0。通知の重要度（macOS 12+）                                                                     |

### サブ機能 3: トリガー設定

| API                               | 目的           | 主要引数              | 注意点                                                            |
| --------------------------------- | -------------- | --------------------- | ----------------------------------------------------------------- |
| UNTimeIntervalNotificationTrigger | 指定秒後に配信 | timeInterval, repeats | timeInterval >= 1; repeats で定期配信可能                         |
| UNCalendarNotificationTrigger     | 指定日時に配信 | dateMatching, repeats | DateComponents の整合性必須。repeats で毎日・毎週など定期配信可能 |
| UNLocationNotificationTrigger     | 位置条件で配信 | region, repeats       | Core Location 権限が必要。macOS での動作検証は重要                |

### サブ機能 4: スケジューリング管理

| API / 考慮事項                                      | 目的・詳細                                                                                                              |
| --------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------- |
| UNNotificationRequest(identifier:content:trigger:)  | 通知要求を生成。identifier は unique（重複時は上書き）                                                                  |
| add(\_:withCompletionHandler:)                      | 通知をスケジュール登録。completionHandler は数秒以内に呼び出される                                                      |
| getPendingNotificationRequests(completionHandler:)  | 保留中通知を取得。返却順は登録順序（時系列保証なし）。フィルタリングは手動実装必要                                      |
| removePendingNotificationRequests(withIdentifiers:) | 指定保留通知を削除。大量削除時はバッチ実行推奨                                                                          |
| removeAllPendingNotificationRequests()              | 全保留通知を削除                                                                                                        |
| getDeliveredNotifications(completionHandler:)       | 配信済み通知を取得。completionHandler 応答期限は数秒以内。大量通知時のパフォーマンス低下に注意                          |
| removeDeliveredNotifications(withIdentifiers:)      | 指定配信済み通知を削除。Notification Center から削除される                                                              |
| removeAllDeliveredNotifications()                   | 全配信済み通知を削除                                                                                                    |
| setBadgeCount(\_:withCompletionHandler:)            | バッジ数を更新（0 で消去）                                                                                              |
| パフォーマンス考慮                                  | 100+ 件の通知を処理する場合、getPending / getDelivered は複数回に分割呼び出しを検討。completionHandler ブロッキング注意 |

### サブ機能 5: カテゴリ、アクション定義

| API                                           | 目的                   |
| --------------------------------------------- | ---------------------- |
| UNNotificationAction                          | アクションボタン定義   |
| UNTextInputNotificationAction                 | 入力付きアクション定義 |
| UNNotificationCategory                        | カテゴリ定義           |
| setNotificationCategories(\_:)                | カテゴリ登録           |
| getNotificationCategories(completionHandler:) | カテゴリ取得           |

### サブ機能 6: デリゲート処理

| メソッド・考慮事項                                            | 目的・詳細                                                                                                       |
| ------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| userNotificationCenter(\_:willPresent:withCompletionHandler:) | フォアグラウンド表示制御。completionHandler は数秒以内に呼び出し必須。メインスレッドから呼び出される             |
| userNotificationCenter(\_:didReceive:withCompletionHandler:)  | アクション応答処理。completionHandler 呼び出し期限は数秒（明確な制限時間は未定）。メインスレッドから呼び出される |
| userNotificationCenter(\_:openSettingsFor:)                   | 通知設定遷移補助。macOS のシステム通知設定を開く                                                                 |
| スレッド安全性                                                | デリゲートコールバックはメインスレッドで実行。非同期処理は DispatchQueue.main で実行                             |
| completionHandler 応答期限                                    | 通常数秒以内に呼び出し。期限内に呼び出さないと OS が強制終了。willPresent / didReceive 両方で適用                |

## 実装リスク（権限、制約、互換性）

- 権限未取得だと通知が届かない
- provisional は静かな通知のみで、バナー、サウンド、バッジに制限がある
- delegate を早期設定しないと受信ハンドリングを取りこぼす
- location trigger は macOS 上の挙動検証が必要
- critical alert や time sensitive は追加エンタイトルメントが必要
- 一部 API は OS バージョン差異や deprecation があるため要検証
- threadIdentifier グループ化: 同じ ID の新規通知追加時、既存通知は自動削除されず、新規のみ表示される。既存通知の明示的削除が必要な場合がある
- interruptionLevel UX 影響: passive は完全無音・バッジのみで、active はバナー + サウンド。timeSensitive / critical は Do Not Disturb を貫通。ユーザー UX に大きく影響
- completionHandler 応答期限: willPresent / didReceive の completionHandler は数秒以内に呼び出す必須。期限内未呼び出しでアプリが強制終了可能
- Do Not Disturb / Focus Mode: これらが有効時、通知動作が制限される。timeSensitive / critical は貫通可能だが、その他は延期される
- soundName フォールバック: 指定したカスタムサウンドファイルが存在しない場合、無音にフォールバック。ログ出力なし。ファイル形式（.aiff / .wav / .caf）を確認必須
- デリゲート delegate identity: manager が delegate を設定するため、複数クラスでの delegate 設定は避ける（最後の設定が有効）

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
        // フォアグラウンド時の表示を制御
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // アクション応答を処理。completionHandler は必ず呼び出す
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

### 5) 保留中通知の取得と削除

```swift
func managePendingNotifications() async {
    let center = UNUserNotificationCenter.current()

    // 保留中通知を取得
    let pending = await center.pendingNotificationRequests()
    print("Pending notifications: \(pending.count)")

    // 特定の通知を削除
    if let firstRequest = pending.first {
        center.removePendingNotificationRequests(withIdentifiers: [firstRequest.identifier])
    }

    // 全保留通知を削除
    center.removeAllPendingNotificationRequests()
}
```

### 6) 配信済み通知の削除

```swift
func manageDeliveredNotifications() async {
    let center = UNUserNotificationCenter.current()

    // 配信済み通知を取得
    let delivered = await center.deliveredNotifications()
    print("Delivered notifications: \(delivered.count)")

    // 特定の通知を削除（Notification Center から消去）
    if let firstNotification = delivered.first {
        center.removeDeliveredNotifications(withIdentifiers: [firstNotification.request.identifier])
    }

    // 全配信済み通知を削除
    center.removeAllDeliveredNotifications()
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
- [ ] interruptionLevel の各値（passive / active / timeSensitive）での動作を検証できる
- [ ] threadIdentifier によるグループ化が意図通り機能することを検証できる
- [ ] カスタムサウンド（soundName）の指定と無効時フォールバックを検証できる
- [ ] completionHandler の応答期限内呼び出しを実装・検証できる
- [ ] macOS 12.0（Monterey）以上での実機検証済み
- [ ] Do Not Disturb / Focus Mode 状態での通知動作を検証できる
