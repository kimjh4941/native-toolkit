# レビュー結果レポート

## 基本情報

- 日付: 2026-05-10
- 機能名: macos-notification
- 対象OS: macOS
- ブランチ: feature/NTKIT-7（develop との差分）
- 設計書: artifact/designs/notification/2026-05-09-macos-notification-implementation-v3.md
- 実装結果: artifact/results/notification/2026-05-09-macos-notification-implementation-result-v1.md

---

## レビュー概要

ブランチ `feature/NTKIT-7` の macOS 通知機能実装をレビュー。
設計書 v3 をベースに、Domain/Application/Data/Manager/Bridge 層が一通り実装されている。全体の構成・命名・DocC コメント・ログ挿入は高品質。ただし Clean Architecture の層境界に構造的な違反が2件ある。

---

## 重大な問題（high）

なし

---

## 改善提案（medium）

### M-1: Port（Application層）にプラットフォーム型が混入している

- ファイル: `mac/MacLibrary/MacLibrary/Notification/Application/Port/NotificationRepository.swift`
- Port は Application 層のインターフェースだが、以下の UserNotifications フレームワーク型を直接使用している:
  - `UNNotificationSettings`（`getAuthorizationStatus` の戻り型）
  - `UNNotificationRequest`（`add` の引数・`getPendingRequests` の戻り型）
  - `UNNotification`（`getDeliveredNotifications` の戻り型）
  - `UNNotificationCategory`（`setNotificationCategories` の引数）
- common.md: 「プラットフォーム固有の型を Domain / Application 層に持ち込まない」に違反
- UseCase 層（`NotificationDispatchUseCases.swift`）も `import UserNotifications` して `UNNotificationRequest` 等を直接生成しており、同様の問題がある
- 対応方針（要検討）: `UNNotification` 系型を Domain モデルにラップするコストが高いため、プロジェクトとしてトレードオフを判断する

### M-2: `setBadgeCount` が UseCase を経由せず Repository を直接呼び出している

- ファイル: `mac/MacLibrary/MacLibrary/Notification/MacNotificationManager.swift` L327
- `repository.setBadgeCount(count)` を Manager から直接呼び出している
- 他のすべての API は UseCase 経由。`setBadgeCount` だけが Manager → Repository の直接呼び出しになっている
- common.md: 「Manager は UseCase 経由で Data 層にアクセスし、直接 Repository を呼ばない」に違反
- 対応: `NotificationBadgeUseCases`（または既存 UseCase への追加）を作成し、Manager から UseCase 経由で呼ぶよう修正する

---

## 軽微な指摘（low）

### L-1: 複数メソッドでログの全パラメータ記録が不足

mac.md: 「全パラメータを含むログを必ず入れる」

| ファイル | メソッド | 不足パラメータ |
|---------|---------|-------------|
| MacNotificationManager.swift L121 | `requestPermission` | `options` |
| MacNotificationManager.swift L161 | `show` | `trigger` |
| MacNotificationManager.swift L181 | `update` | `content`, `trigger` |
| MacNotificationManager.swift L201 | `schedule` | `trigger` |
| UnityMacNotificationManager.swift L101 | `show` | `contentJson`, `triggerJson` |
| UnityMacNotificationManager.swift L159 | `schedule` | `contentJson`, `triggerJson` |

### L-2: `NotificationRepositoryImpl.setBadgeCount` の `else` 分岐が到達不能

- ファイル: `mac/MacLibrary/MacLibrary/Notification/Data/Repository/NotificationRepositoryImpl.swift` L140-144
- Manager の `guardOS` が macOS 15 未満を早期リターンするため、Repository の `else` 分岐（`dockTile.badgeLabel` フォールバック）は到達不能なデッドコード

### L-3: `update` のコメントが実装意図と一致していない

- ファイル: `mac/MacLibrary/MacLibrary/Notification/Application/UseCase/NotificationDispatchUseCases.swift` L103
- コメントに "removing it" と記述があるが、実装では明示的な `removePending` は呼ばず、同一 identifier での `add` による UNUserNotificationCenter の上書き挙動に依存している
- 動作は正しいが、コメントが誤解を招く

---

## 設計書整合性チェック

| 項目 | 結果 |
|------|------|
| 企画書との整合性 | ○ |
| Clean Architecture 準拠 | △（M-1, M-2） |
| 既存実装との差分分析の正確性 | ○ |
| テスト設計の網羅性 | △（main queue スレッド検証・C Bridge 寿命テスト未実施） |
| ドメインエラー全ケース実装 | ○ |
| エラーコード/メッセージ対応表との整合 | ○ |

## プロジェクトルール適合チェック

| 項目 | 結果 |
|------|------|
| common.md 準拠 | △（M-1, M-2） |
| mac.md 準拠 | △（L-1） |
| エラー契約反映 | ○ |
| 既存 API 互換性 | ○ |

## テストカバレッジ

- カバーできている:
  - ドメインエラー全 errorCode/errorMessage 対応（57件 全パス）
  - UseCase 正常系・異常系・入力検証
  - Bridge JSON parse/serialize
- 不足:
  - main queue での callback 実行スレッド検証（実装結果に「未実施」記載あり）
  - C Bridge 文字列ポインタ寿命の自動テスト（同上）

## 総合評価

**要修正（軽微）**

- M-2（setBadgeCount の UseCase バイパス）: 修正推奨
- M-1（Port へのプラットフォーム型混入）: トレードオフを判断の上、方針を確定する
- L-1（ログ補完）: mac.md ルール準拠のため対応すること
