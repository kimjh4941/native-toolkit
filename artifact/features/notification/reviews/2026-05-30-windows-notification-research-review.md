# レビュー結果

- 日付: 2026-05-30
- 対象ファイル: artifact/plans/notification/2026-05-30-windows-notification-research.md
- 機能名: notification
- 対象OS: Windows

---

## 強み

- Windows App SDK / UWP の API を名前空間ごとに区別して体系整理している
- In Scope / Out of Scope の境界が明確
- 機能マップ（ツリー）と API 表（9 カテゴリ）の二段構え構成で参照しやすい
- 管理者権限でのサイレント失敗を High リスクとして正しく捕捉
- 削除系 API（RemoveByTag/Group/Id/All）と UpdateAsync の 2 オーバーロードを網羅
- `AddArgument` と `SetInvokeUri` の併用不可制約を明示

---

## 改善点

### 高優先度

**[基本表示 / 実装リスク / DoD] `IsSupported()` の用途が誤り**
- 問題: `IsSupported()` は PushNotifications API のサポート可否を返す静的メソッドであり、Toast 通知のフォールバック判定 API ではない。また `Default.IsSupported()` という呼び出し形式も誤り（静的メソッドのため `AppNotificationManager.IsSupported()`）
- 改善: フォールバック判定には `Setting` プロパティ（`AppNotificationSetting`）を使用する設計に変更。DoD の記述も修正

**[スケジュール通知 / 機能マップ] スヌーズ付きコンストラクタが Deprecated**
- 問題: `ScheduledToastNotification(XmlDocument, DateTimeOffset, TimeSpan, uint)` は Windows 10 以降で Deprecated（単発と等価）。対象 OS（Win10 19041+）ではスヌーズが機能しない
- 改善: スヌーズは Reminder/Alarm シナリオのトーストボタン方式に変更。機能マップと DoD のスヌーズ項目も書き換え

### 中優先度

**[通知ハンドリング] 未起動時の起動経路の記述が不完全**
- 問題: COM アクティベーション経由の場合は Kind が `Launch` として報告され、引数は `NotificationInvoked` 経由で届くケースがある。`Register()` を `GetActivatedEventArgs()` より前に呼ぶ順序制約も未記載
- 改善: 起動経路を (a) Kind==AppNotification と (b) NotificationInvoked 経由の双方で処理する設計を明記

**[画像付き] `AppNotificationImageCrop` のクロップ値が誤り**
- 問題: 「Circle/Square」と記載しているが、実際は `Default` と `Circle` のみ。`Square` は存在しない
- 改善: 「Default / Circle」に修正

**[API 網羅表] 音声制御 API が未記載**
- 問題: `SetAudioUri` / `SetAudioEvent` / `MuteAudio`（Alarm/Reminder シナリオで必須級）と `SetTimeStamp` が欠落
- 改善: 音声制御 API を網羅表・機能マップに追加

**[サンプルコード / DoD] サンプルと DoD のトレーサビリティ未確立**
- 問題: サンプルと DoD 項目の対応が不明。elevated 非対応前提・パッケージ済み/未パッケージの違いがサンプルに反映されていない
- 改善: 各サンプルに DoD 参照 ID を付与し、ビルド可能な最小コードとして提示

### 低優先度

**[API 網羅表] AppNotificationManager の管理系 API 欠落**
- `Register(String, Uri)`（未パッケージアプリ向け）、`UnregisterAll()`、`Setting` プロパティを追加

**[公式文書一覧] Badge URL のロケール不整合**
- `/th-th/` になっている URL を `/en-us/` に統一

**[DoD] マニフェスト設定の検証粒度が粗い**
- com/desktop 名前空間、GUID 一致、`Arguments="----AppNotificationActivated:"` 指定をチェックリスト化

---

## 不足項目

- `AppNotificationManager.Setting` プロパティ（正しいフォールバック判定）
- 音声制御 API（`SetAudioUri` / `SetAudioEvent` / `MuteAudio` / `AppNotificationAudioLooping`）
- `SetTimeStamp`（タイムスタンプ上書き）
- `Register(String, Uri)` オーバーロードおよび `UnregisterAll()`
- パッケージ済み / 未パッケージアプリでの登録・マニフェスト手順の差異
- `AppNotificationProgressResult`（`UpdateAsync` の結果ステータス判定）
- `SetExpirationTime` / `SetExpiresOnReboot`（通知の有効期限管理）
- 引数サイズ上限・XML ペイロード最大サイズなどの運用制約
- ローカライズ対応（`AddText` の言語属性）
- テスト / 検証方法（Notification Center 表示確認手順）

---

## 総合評価

公式ドキュメントの体系整理と API カテゴリ分けの網羅性は高く、骨格は良好です。ただし技術的に誤った記述が 2 件（High）あり、設計フェーズに進む前に是正が必要です。

1. `IsSupported()` は PushNotifications 用であり Toast 通知のフォールバック判定には使えない
2. スヌーズ付き `ScheduledToastNotification` コンストラクタは Win10 以降で Deprecated

`AppNotificationImageCrop` の Square 誤記、音声制御 API の欠落、未パッケージ対応手順の欠如なども中位の課題です。High 2 件と medium 4 件を修正すれば、実装設計の基礎情報として十分な品質に達します。
