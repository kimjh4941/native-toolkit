# Windows Notification 機能調査企画書

- 作成日: 2026-05-30
- 対象OS: Windows
- 対象機能: Notification（Toast通知）

---

## 目的

native-toolkit ライブラリへの Windows ネイティブ通知機能の追加実装に向けて、  
利用可能な公式 API を全網羅し、実装設計の基礎情報を整備する。

---

## 調査対象範囲

### In Scope
- Toast 通知（基本表示）
- Toast 通知（アクション付き：ボタン・テキストボックス・コンボボックス）
- Toast 通知（画像付き）
- Toast 通知（進捗バー付き）
- スケジュール通知
- 通知グループ / コレクション管理
- バッジ通知
- 通知クリック・アクションのハンドリング
- 通知履歴管理（削除・一覧）
- フォアグラウンド / バックグラウンド対応

### Out of Scope
- プッシュ通知（WNS）
- Tile 通知
- Windows 10 Build 19041 未満の対応

---

## 公式文書一覧（最優先ソース）

| タイトル | URL |
|---------|-----|
| App Notifications Overview | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/toast-notifications-overview |
| Quickstart: Send and Handle App Notifications | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-quickstart |
| App notification content | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/adaptive-interactive-toasts |
| App notification content schema | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-schema |
| AppNotificationManager Class | https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.appnotifications.appnotificationmanager |
| AppNotificationBuilder Class | https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.appnotifications.builder.appnotificationbuilder |
| AppNotification Class | https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.appnotifications.appnotification |
| Microsoft.Windows.AppNotifications Namespace | https://learn.microsoft.com/en-us/windows/windows-app-sdk/api/winrt/microsoft.windows.appnotifications |
| Schedule an app notification | https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/scheduled-toast |
| App notification collections | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-collections |
| App notification progress bar | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-progress-bar |
| App notification headers | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-headers |
| Remove app notifications | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/manage-app-notifications |
| Notification listener | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/notification-listener |
| Badge notifications | https://learn.microsoft.com/th-th/windows/apps/design/shell/tiles-and-notifications/badges |
| BadgeUpdateManager Class | https://learn.microsoft.com/en-us/uwp/api/windows.ui.notifications.badgeupdatemanager |
| App notifications UWP to WinUI migration | https://learn.microsoft.com/en-us/windows/apps/windows-app-sdk/migrate-to-windows-app-sdk/guides/toast-notifications |
| App notifications UX guidance | https://learn.microsoft.com/en-us/windows/apps/develop/notifications/app-notifications/app-notifications-ux-guidance |

---

## 補助ソース一覧

| 情報 | 信頼度 | 内容 |
|-----|-------|------|
| 通知表示位置 | low | 右下コーナーまたは Notification Center（設定依存） |
| テキスト長推奨 | medium | 1行40文字程度（レイアウト依存） |
| 画像サイズ推奨 | medium | AppLogo: 40x40px、HeroImage: 364x180px、InlineImage: 全幅最大364px |

---

## 機能マップ（サブ機能分解）

```
Windows Notification
├── Toast 通知
│   ├── 基本表示（テキスト・画像）
│   ├── アクション付き（ボタン・テキストボックス・コンボボックス）
│   ├── 画像付き（AppLogo・HeroImage・InlineImage）
│   └── 進捗バー付き（静的・データバインディング更新）
├── スケジュール通知
│   ├── 指定時刻の表示
│   └── スヌーズ機能
├── グループ / コレクション管理
│   ├── Tag / Group 設定
│   └── ToastCollection（コレクション単位管理）
├── バッジ通知
│   ├── 数値バッジ
│   └── グリフバッジ
├── 通知ハンドリング
│   ├── NotificationInvoked イベント（フォアグラウンド）
│   └── AppInstance.GetActivatedEventArgs（バックグラウンド起動）
└── 通知履歴管理
    ├── 一覧取得
    ├── ID / Tag / Group 指定削除
    └── 全削除
```

---

## API 全網羅表

### 1. Toast 通知（基本表示）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `AppNotificationBuilder()` | 通知内容の構築開始 | なし | AppNotificationBuilder | - | Windows App SDK 1.0+ |
| `AddText(string)` | テキスト追加 | text | AppNotificationBuilder | - | - |
| `AddText(string, AppNotificationTextProperties)` | プロパティ付きテキスト追加 | text, properties | AppNotificationBuilder | - | - |
| `SetAttributionText(string)` | 属性テキスト設定 | text | AppNotificationBuilder | - | - |
| `SetDuration(AppNotificationDuration)` | 表示期間設定 | Short(3秒) / Long(7秒) | AppNotificationBuilder | - | - |
| `SetScenario(AppNotificationScenario)` | 通知シナリオ設定 | Default/Reminder/Alarm/Urgent/IncomingCall | AppNotificationBuilder | - | Urgent は Win10 19041+ |
| `BuildNotification()` | AppNotification オブジェクト生成 | なし | AppNotification | - | - |
| `AppNotificationManager.Default.Show(AppNotification)` | 通知を表示 | notification | void | 管理者権限で実行中は失敗（例外なし） | Register() 呼出済み |
| `AppNotificationManager.Default.IsSupported()` | 通知サポート確認 | なし | bool | - | - |

### 2. Toast 通知（アクション付き）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `AppNotificationButton(string)` | ボタン要素生成 | content（ラベル文字列） | AppNotificationButton | - | - |
| `AppNotificationButton.AddArgument(string, string)` | ボタン引数追加 | key, value | AppNotificationButton | SetInvokeUri() と併用不可 | - |
| `AppNotificationButton.SetInvokeUri(Uri)` | URI 起動設定 | uri | AppNotificationButton | AddArgument() と併用不可 | - |
| `AppNotificationButton.SetIcon(Uri)` | ボタンアイコン設定 | iconUri | AppNotificationButton | - | - |
| `AppNotificationBuilder.AddButton(AppNotificationButton)` | ボタンを通知に追加 | button | AppNotificationBuilder | 最大5個 | - |
| `AppNotificationBuilder.AddTextBox(string)` | テキスト入力ボックス追加 | placeholderText | AppNotificationBuilder | - | - |
| `AppNotificationBuilder.AddTextBox(string, string, string)` | ID・タイトル付きテキストボックス | inputId, placeholderText, title | AppNotificationBuilder | - | - |
| `AppNotificationBuilder.AddComboBox(AppNotificationComboBox)` | コンボボックス追加 | comboBox | AppNotificationBuilder | - | - |
| `AppNotificationComboBox.Items` | 選択肢の設定 | Dictionary<string, string> | - | - | - |
| `AppNotificationComboBox.SetSelectedItem(string)` | デフォルト選択項目設定 | itemId | AppNotificationComboBox | - | - |

### 3. Toast 通知（画像付き）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `SetAppLogoOverride(Uri)` | ロゴ画像設定 | imageUri | AppNotificationBuilder | - | - |
| `SetAppLogoOverride(Uri, AppNotificationImageCrop)` | クロップ指定ロゴ画像設定 | imageUri, crop(Circle/Square) | AppNotificationBuilder | - | - |
| `SetHeroImage(Uri)` | ヒーロー画像（全幅）設定 | imageUri | AppNotificationBuilder | - | - |
| `SetInlineImage(Uri)` | インライン画像設定 | imageUri | AppNotificationBuilder | - | - |

### 4. Toast 通知（進捗バー付き）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `AppNotificationProgressBar` | 進捗バー要素 | - | - | - | - |
| `.Value` | 進捗値設定 | double (0〜1) | - | - | - |
| `.ValueStringOverride` | 進捗値の表示文字列 | string | - | - | - |
| `.Title` | 進捗バータイトル | string | - | - | - |
| `.Status` | ステータス説明文 | string | - | - | - |
| `AppNotificationBuilder.AddProgressBar(AppNotificationProgressBar)` | 進捗バーを通知に追加 | progressBar | AppNotificationBuilder | - | - |
| `AppNotificationProgressData` | 実行時進捗更新データ | - | - | - | - |
| `AppNotificationManager.UpdateAsync(AppNotificationProgressData, string)` | タグ指定で進捗更新 | data, tag | IAsyncOperation | 通知が存在しない場合エラー | - |
| `AppNotificationManager.UpdateAsync(AppNotificationProgressData, string, string)` | タグ+グループ指定で進捗更新 | data, tag, group | IAsyncOperation | - | - |

### 5. スケジュール通知

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `ScheduledToastNotification(XmlDocument, DateTimeOffset)` | スケジュール通知生成 | content, scheduledTime | ScheduledToastNotification | - | Windows.UI.Notifications |
| `ScheduledToastNotification(XmlDocument, DateTimeOffset, TimeSpan, uint)` | スヌーズ付きスケジュール通知 | content, scheduledTime, snoozeInterval(60秒〜60分), maxSnoozes(1〜5) | ScheduledToastNotification | - | - |
| `ToastNotifier.AddToSchedule(ScheduledToastNotification)` | 通知をスケジュール登録 | notification | void | デリバリーウィンドウ5分超で自動削除 | - |
| `ToastNotifier.GetScheduledToastNotifications()` | スケジュール済み通知一覧取得 | なし | IReadOnlyList<ScheduledToastNotification> | - | - |
| `ToastNotifier.RemoveFromSchedule(ScheduledToastNotification)` | スケジュール通知キャンセル | notification | void | - | - |

### 6. グループ / コレクション管理

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `AppNotificationBuilder.SetTag(string)` | 通知タグ設定 | tag | AppNotificationBuilder | - | - |
| `AppNotificationBuilder.SetGroup(string)` | 通知グループ設定 | group | AppNotificationBuilder | - | - |
| `ToastCollection(string, string, string, Uri)` | コレクション生成 | id, displayName, launchArgs, logo | ToastCollection | - | Windows.UI.Notifications |
| `ToastCollectionManager.SaveToastCollectionAsync(ToastCollection)` | コレクション作成・更新 | collection | IAsyncAction | - | - |
| `ToastCollectionManager.FindAllToastCollectionsAsync()` | 全コレクション取得 | なし | IAsyncOperation<IReadOnlyList<ToastCollection>> | - | - |
| `ToastCollectionManager.RemoveToastCollectionAsync(string)` | コレクション削除 | collectionId | IAsyncAction | - | - |

### 7. バッジ通知

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `BadgeUpdateManager.CreateBadgeUpdaterForApplication()` | バッジアップデータ取得 | なし | BadgeUpdater | - | Windows.UI.Notifications |
| `BadgeUpdateManager.GetTemplateContent(BadgeTemplateType)` | バッジテンプレートXML取得 | type | XmlDocument | - | - |
| `BadgeUpdater.Update(BadgeNotification)` | バッジ更新 | notification | void | - | - |
| `BadgeUpdater.Clear()` | バッジクリア | なし | void | - | - |
| `BadgeNotification(XmlDocument)` | バッジ通知オブジェクト生成 | content | BadgeNotification | - | - |

### 8. 通知ハンドリング

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `AppNotificationManager.Default.Register()` | 通知アクティベーション登録 | なし | void | 管理者権限で実行中は失敗 | - |
| `AppNotificationManager.Default.Unregister()` | 通知アクティベーション登録解除 | なし | void | - | - |
| `AppNotificationManager.NotificationInvoked` | 通知クリック・アクションイベント | AppNotificationActivatedEventArgs | - | - | Register() 呼出済み |
| `AppNotificationActivatedEventArgs.Arguments` | アクション引数取得 | なし | IDictionary<string, string> | - | - |
| `AppInstance.GetActivatedEventArgs()` | アプリ起動理由の判定 | なし | AppActivationArguments | - | - |
| `AppActivationArguments.Kind` | 起動種別確認 | なし | ExtendedActivationKind | - | - |
| `ExtendedActivationKind.AppNotification` | 通知による起動を示す値 | - | - | - | - |

### 9. 通知履歴管理

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `AppNotificationManager.GetAllAsync()` | 表示中の全通知取得 | なし | IAsyncOperation<IReadOnlyList<AppNotification>> | - | - |
| `AppNotificationManager.RemoveByIdAsync(uint)` | ID 指定削除 | notificationId | IAsyncAction | - | - |
| `AppNotificationManager.RemoveByTagAsync(string)` | タグ指定削除 | tag | IAsyncAction | - | - |
| `AppNotificationManager.RemoveByGroupAsync(string)` | グループ指定削除 | group | IAsyncAction | - | - |
| `AppNotificationManager.RemoveByTagAndGroupAsync(string, string)` | タグ+グループ指定削除 | tag, group | IAsyncAction | - | - |
| `AppNotificationManager.RemoveAllAsync()` | 全通知削除 | なし | IAsyncAction | - | - |
| `UserNotificationListener.GetNotificationsAsync(NotificationKinds)` | 全アプリの通知取得 | kinds(Toast のみサポート) | IAsyncOperation<IReadOnlyList<UserNotification>> | 権限なしは空リスト | UserNotificationListener キャパビリティ必須 |
| `UserNotificationListener.RemoveNotification(uint)` | 特定通知削除 | notificationId | void | - | 権限必須 |
| `UserNotificationListener.ClearNotifications()` | 全通知クリア | なし | void | 全アプリ対象 | 権限必須 |
| `UserNotificationListener.RequestAccessAsync()` | 通知アクセス権限リクエスト | なし | IAsyncOperation<UserNotificationListenerAccessStatus> | - | - |

---

## 実装リスク

| リスク | 深刻度 | 発生条件 | 対応策 |
|-------|-------|---------|-------|
| 管理者権限での通知失敗 | 高 | アプリが管理者で実行中 | `IsSupported()` で確認、非管理者プロセスに通知処理を委譲 |
| Singleton パッケージ不在 | 中 | 自己完結型展開で初期化失敗 | `IsSupported()` の結果で条件分岐 |
| マニフェスト設定不備 | 中 | ToastActivatorCLSID 未設定 | 一意 GUID 生成、com/desktop Namespace を追加 |
| NotificationListener 権限拒否 | 低 | ユーザが初回ダイアログを拒否 | `GetAccessStatus()` で定期確認、機能を無効化してフォールバック |
| スケジュール通知のデリバリー失敗 | 低 | PC がオフの状態でスケジュール到来（5分超） | 重要通知には BackgroundTask + TimerTrigger を使用 |
| SetInvokeUri と AddArgument の競合 | 低 | ボタンに両方設定 | URI 起動か引数起動かを事前に決定 |
| Urgent シナリオの非対応端末 | 低 | Windows 10 Build 19041 未満 | `IsUrgentScenarioSupported()` で事前確認 |

### マニフェスト設定要件

```xml
<Package xmlns:com="http://schemas.microsoft.com/appx/manifest/com/windows10"
         xmlns:desktop="http://schemas.microsoft.com/appx/manifest/desktop/windows10">
  <Applications>
    <Application>
      <Extensions>
        <desktop:Extension Category="windows.toastNotificationActivation">
          <desktop:ToastNotificationActivation ToastActivatorCLSID="{YOUR-UNIQUE-GUID}" />
        </desktop:Extension>
        <com:Extension Category="windows.comServer">
          <com:ComServer>
            <com:ExeServer Executable="App.exe" DisplayName="AppName"
              Arguments="----AppNotificationActivated:">
              <com:Class Id="{YOUR-UNIQUE-GUID}" />
            </com:ExeServer>
          </com:ComServer>
        </com:Extension>
      </Extensions>
    </Application>
  </Applications>
</Package>
```

---

## サンプルコード集

### 1. 初期化

```csharp
// App.xaml.cs - アプリ起動時に必ず実行
AppNotificationManager.Default.NotificationInvoked += OnNotificationInvoked;
AppNotificationManager.Default.Register();

// 通知起動かどうかを判定
var activatedArgs = AppInstance.GetActivatedEventArgs();
if (activatedArgs.Kind == ExtendedActivationKind.AppNotification)
{
    var notificationArgs = activatedArgs.Data as AppNotificationActivatedEventArgs;
    HandleNotificationActivation(notificationArgs);
}
```

### 2. 基本 Toast 通知

```csharp
var notification = new AppNotificationBuilder()
    .AddText("タイトル")
    .AddText("本文テキスト")
    .BuildNotification();

AppNotificationManager.Default.Show(notification);
```

### 3. 画像付き Toast 通知

```csharp
var notification = new AppNotificationBuilder()
    .AddText("画像付き通知")
    .SetAppLogoOverride(new Uri("ms-appx:///Assets/Logo.png"), AppNotificationImageCrop.Circle)
    .SetHeroImage(new Uri("ms-appx:///Assets/Hero.png"))
    .SetInlineImage(new Uri("ms-appx:///Assets/Inline.png"))
    .BuildNotification();

AppNotificationManager.Default.Show(notification);
```

### 4. ボタン付き Toast 通知

```csharp
var notification = new AppNotificationBuilder()
    .AddText("確認が必要です")
    .AddButton(new AppNotificationButton("承認")
        .AddArgument("action", "approve")
        .AddArgument("id", "123"))
    .AddButton(new AppNotificationButton("拒否")
        .AddArgument("action", "reject")
        .AddArgument("id", "123"))
    .BuildNotification();

AppNotificationManager.Default.Show(notification);
```

### 5. テキスト入力付き Toast 通知

```csharp
var notification = new AppNotificationBuilder()
    .AddText("返信を入力してください")
    .AddTextBox("reply", "返信内容を入力...", "返信")
    .AddButton(new AppNotificationButton("送信")
        .AddArgument("action", "reply"))
    .BuildNotification();

AppNotificationManager.Default.Show(notification);
```

### 6. 進捗バー付き Toast 通知

```csharp
// 初期表示
var notification = new AppNotificationBuilder()
    .AddText("ダウンロード中...")
    .SetTag("download-1")
    .AddProgressBar(new AppNotificationProgressBar()
    {
        Title = "ファイル名.zip",
        Value = 0.0,
        ValueStringOverride = "0%",
        Status = "開始中..."
    })
    .BuildNotification();

AppNotificationManager.Default.Show(notification);

// 進捗更新
var progressData = new AppNotificationProgressData(sequenceNumber: 1)
{
    Value = 0.5,
    ValueStringOverride = "50%",
    Status = "ダウンロード中..."
};
await AppNotificationManager.Default.UpdateAsync(progressData, "download-1");
```

### 7. スケジュール通知

```csharp
var payload = new AppNotificationBuilder()
    .AddText("リマインダー")
    .AddText("会議まで10分です")
    .BuildNotification()
    .Payload;

var doc = new Windows.Data.Xml.Dom.XmlDocument();
doc.LoadXml(payload);

var scheduled = new ScheduledToastNotification(
    doc,
    DateTimeOffset.Now.AddMinutes(10)
);
scheduled.Tag = "meeting-reminder";

ToastNotificationManager.CreateToastNotifier().AddToSchedule(scheduled);
```

### 8. グループ / タグ管理

```csharp
// タグ・グループ付きで通知
var notification = new AppNotificationBuilder()
    .SetGroup("messages")
    .SetTag("msg-456")
    .AddText("新しいメッセージ")
    .BuildNotification();

AppNotificationManager.Default.Show(notification);

// グループ単位で削除
await AppNotificationManager.Default.RemoveByGroupAsync("messages");
```

### 9. バッジ通知

```csharp
var badgeUpdater = BadgeUpdateManager.CreateBadgeUpdaterForApplication();

// 数値バッジ
var badgeDoc = BadgeUpdateManager.GetTemplateContent(BadgeTemplateType.BadgeNumber);
badgeDoc.SelectSingleNode("//badge").Attributes.GetNamedItem("value").NodeValue = "5";
badgeUpdater.Update(new BadgeNotification(badgeDoc));

// バッジクリア
badgeUpdater.Clear();
```

### 10. アクティベーションハンドラ

```csharp
private void OnNotificationInvoked(AppNotificationManager sender, AppNotificationActivatedEventArgs args)
{
    var action = args.Arguments.ContainsKey("action") ? args.Arguments["action"] : "";

    switch (action)
    {
        case "approve":
            var id = args.Arguments["id"];
            // 承認処理
            break;
        case "reply":
            var replyText = args.Arguments["reply"];
            // 返信処理
            break;
        default:
            // 通知本体クリック → メインウィンドウを表示
            DispatcherQueue.TryEnqueue(() => mainWindow.Activate());
            break;
    }
}
```

### 11. IsSupported チェック

```csharp
if (!AppNotificationManager.Default.IsSupported())
{
    // 管理者権限・未対応環境のフォールバック処理
    return;
}
AppNotificationManager.Default.Show(notification);
```

---

## Definition of Done

- [ ] `AppNotificationManager` による基本 Toast 通知の送信が動作する
- [ ] テキスト / 画像 / ボタン / テキスト入力 / コンボボックス / 進捗バー の各要素が表示できる
- [ ] ボタンクリック・入力値が `NotificationInvoked` イベントで正しく取得できる
- [ ] アプリ停止中の通知クリックでアプリが起動し、引数を受け取れる
- [ ] スケジュール通知の登録・一覧取得・キャンセルが動作する
- [ ] タグ / グループ指定の通知削除が動作する
- [ ] バッジ通知の設定・クリアが動作する
- [ ] `IsSupported()` によるフォールバック処理が実装されている
- [ ] マニフェスト（ToastActivatorCLSID, ComServer）が正しく設定されている
- [ ] `IsUrgentScenarioSupported()` による互換性チェックが実装されている
