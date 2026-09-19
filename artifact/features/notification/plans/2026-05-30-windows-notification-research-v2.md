# Windows Notification 機能調査企画書

- バージョン: v2
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
- 音声制御（カスタム音声 / システム音声 / ミュート / ループ）
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
- XML ペイロードの運用制約（ペイロードサイズ上限・引数文字列サイズ上限などの運用上の制約は本企画書では扱わない）

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
| Badge notifications | https://learn.microsoft.com/en-us/windows/apps/design/shell/tiles-and-notifications/badges |
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
│   ├── 進捗バー付き（静的・データバインディング更新）
│   └── 音声制御（カスタム音声 / ミュート / ループ）
├── スケジュール通知
│   ├── 指定時刻の表示
│   └── Reminder/Alarm シナリオ（ボタン方式）
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
| `SetTimeStamp(DateTimeOffset)` | カスタムタイムスタンプ設定 | dateTime | AppNotificationBuilder | - | - |
| `SetDuration(AppNotificationDuration)` | 表示期間設定 | Short(3秒) / Long(7秒) | AppNotificationBuilder | - | - |
| `SetScenario(AppNotificationScenario)` | 通知シナリオ設定 | Default/Reminder/Alarm/Urgent/IncomingCall | AppNotificationBuilder | - | Urgent は Win10 19041+ |
| `BuildNotification()` | AppNotification オブジェクト生成 | なし | AppNotification | - | - |
| `AppNotificationManager::Default().Show(AppNotification)` | 通知を表示 | notification | void | 管理者権限で実行中は失敗（例外なし） | Register() 呼出済み |
| `AppNotificationManager::Default().Setting()` | 通知設定状態の確認 | なし | AppNotificationSetting | - | - |

> 注: 通知サポート可否やフォールバックの判定には、静的メソッド `IsSupported()`（PushNotifications API のサポート可否を返す）ではなく、`AppNotificationManager::Default().Setting()`（`AppNotificationSetting` 列挙体）を使用する。詳細は「フォールバック判定」セクションを参照。

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
| `SetAppLogoOverride(Uri, AppNotificationImageCrop)` | クロップ指定ロゴ画像設定 | imageUri, crop(Default/Circle) | AppNotificationBuilder | - | - |
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
| `AppNotificationManager.UpdateAsync(AppNotificationProgressData, string)` | タグ指定で進捗更新 | data, tag | IAsyncOperation<AppNotificationProgressResult> | 通知が存在しない場合エラー | - |
| `AppNotificationManager.UpdateAsync(AppNotificationProgressData, string, string)` | タグ+グループ指定で進捗更新 | data, tag, group | IAsyncOperation<AppNotificationProgressResult> | - | - |

### 5. スケジュール通知

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `ScheduledToastNotification(XmlDocument, DateTimeOffset)` | スケジュール通知生成 | content, scheduledTime | ScheduledToastNotification | - | Windows.UI.Notifications |
| `ToastNotifier.AddToSchedule(ScheduledToastNotification)` | 通知をスケジュール登録 | notification | void | デリバリーウィンドウ5分超で自動削除 | - |
| `ToastNotifier.GetScheduledToastNotifications()` | スケジュール済み通知一覧取得 | なし | IReadOnlyList<ScheduledToastNotification> | - | - |
| `ToastNotifier.RemoveFromSchedule(ScheduledToastNotification)` | スケジュール通知キャンセル | notification | void | - | - |

> 注: スヌーズ機能を持つコンストラクタ `ScheduledToastNotification(XmlDocument, DateTimeOffset, TimeSpan, uint)` は Windows 10 以降では Deprecated であり、単発のスケジュール通知と等価に扱われる。対象 OS（Win10 19041+）では、スヌーズは Reminder/Alarm シナリオのトーストボタン（スヌーズ/解除ボタン）で実現する。

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
| `AppNotificationManager::Default().Register()` | 通知アクティベーション登録 | なし | void | 管理者権限で実行中は失敗 | - |
| `AppNotificationManager::Default().Register(string toastActivatorCLSID, Uri launchUri)` | 未パッケージアプリ向け登録オーバーロード | toastActivatorCLSID, launchUri | void | - | 未パッケージアプリ |
| `AppNotificationManager::Default().Unregister()` | 通知アクティベーション登録解除 | なし | void | - | - |
| `AppNotificationManager::Default().UnregisterAll()` | 全登録解除 | なし | void | - | - |
| `AppNotificationManager::Default().Setting()` | 通知設定状態の確認 | なし | AppNotificationSetting | - | - |
| `AppNotificationManager.NotificationInvoked` | 通知クリック・アクションイベント | AppNotificationActivatedEventArgs | - | - | Register() 呼出済み |
| `AppNotificationActivatedEventArgs.Arguments()` | アクション引数取得 | なし | IMap<hstring, hstring> | - | - |
| `AppInstance::GetCurrent().GetActivatedEventArgs()` | アプリ起動理由の判定 | なし | AppActivationArguments | - | - |
| `AppActivationArguments.Kind()` | 起動種別確認 | なし | ExtendedActivationKind | - | - |
| `ExtendedActivationKind::AppNotification` | 通知による起動を示す値 | - | - | - | - |

#### 実装上の注意（未起動時の起動経路）

- アプリ未起動時に通知から起動される場合、COM アクティベーション経由では `Kind()` が `ExtendedActivationKind::AppNotification` ではなく `Launch` として報告され、引数が `NotificationInvoked` イベント経由で届くケースがある。
- このため、`GetActivatedEventArgs()` による分岐のみに依存せず、`NotificationInvoked` ハンドラ側でも引数を受け取れるよう実装する。
- `Register()` は `GetActivatedEventArgs()` を呼ぶ前に呼び出す必要がある（順序制約）。`NotificationInvoked` の購読と `Register()` をアプリ起動の最初期に完了させること。

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

### 10. 音声制御

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小利用条件 |
|-----|------|---------|-------|------------|------------|
| `AppNotificationBuilder.SetAudioUri(Uri)` | カスタム音声 URI 設定 | audioUri | AppNotificationBuilder | 非対応 URI スキームは無視 | - |
| `AppNotificationBuilder.SetAudioUri(Uri, AppNotificationAudioLooping)` | ループ設定付きカスタム音声設定 | audioUri, loop(None/Loop) | AppNotificationBuilder | ループは Long Duration が必要 | - |
| `AppNotificationBuilder.SetAudioEvent(AppNotificationSoundEvent)` | システム音声設定 | soundEvent | AppNotificationBuilder | - | - |
| `AppNotificationBuilder.SetAudioEvent(AppNotificationSoundEvent, AppNotificationAudioLooping)` | ループ設定付きシステム音声設定 | soundEvent, loop | AppNotificationBuilder | ループは Long Duration が必要 | - |
| `AppNotificationBuilder.MuteAudio()` | 音声ミュート | なし | AppNotificationBuilder | - | - |

> 注: 音声のループ再生は通常 `SetScenario(Alarm/Reminder)` または `SetDuration(Long)` と組み合わせて利用する。

---

## フォールバック判定

通知の表示可否を実行前に判定し、無効時はフォールバック処理（例: アプリ内バナー、ログ記録）に切り替える。

- 判定には `AppNotificationManager::Default().Setting()`（`AppNotificationSetting` 列挙体）を使用する。
- `AppNotificationSetting` の値:
  - `Enabled` — 通知が有効
  - `DisabledForApplication` — アプリ単位で無効
  - `DisabledForUser` — ユーザー単位で無効
  - `DisabledByGroupPolicy` — グループポリシーで無効
  - `DisabledByManifest` — マニフェスト設定により無効
- 呼び出し例:

```cpp
if (AppNotificationManager::Default().Setting() != AppNotificationSetting::Enabled)
{
    // 通知が無効 → フォールバック処理（アプリ内バナー表示・ログ記録など）
    return;
}
AppNotificationManager::Default().Show(notification);
```

---

## 実装リスク

| リスク | 深刻度 | 発生条件 | 対応策 |
|-------|-------|---------|-------|
| 管理者権限での通知失敗 | 高 | アプリが管理者で実行中 | `Setting()` プロパティで確認、非管理者プロセスに通知処理を委譲 |
| Singleton パッケージ不在 | 中 | 自己完結型展開で初期化失敗 | `Setting()` の結果で条件分岐 |
| マニフェスト設定不備 | 中 | ToastActivatorCLSID 未設定 | 一意 GUID 生成、com/desktop Namespace を追加 |
| パッケージ済み / 未パッケージアプリの手順差異 | 中 | 配布形態により登録手順・マニフェスト要否が異なる | 未パッケージは `Register(toastActivatorCLSID, launchUri)` を使用し、配布形態ごとに初期化分岐を実装 |
| NotificationListener 権限拒否 | 低 | ユーザが初回ダイアログを拒否 | `RequestAccessAsync()` の結果を定期確認、機能を無効化してフォールバック |
| スケジュール通知のデリバリー失敗 | 低 | PC がオフの状態でスケジュール到来（5分超） | 重要通知には BackgroundTask + TimerTrigger を使用 |
| SetInvokeUri と AddArgument の競合 | 低 | ボタンに両方設定 | URI 起動か引数起動かを事前に決定 |
| Urgent シナリオの非対応端末 | 低 | Windows 10 Build 19041 未満 | `IsUrgentScenarioSupported()` で事前確認 |
| `AppNotificationProgressResult` の判定漏れ | 低 | `UpdateAsync` の結果を未確認 | 戻り値 `AppNotificationProgressResult` を確認し、`Succeeded` 以外（通知未存在など）を処理 |
| 通知有効期限の未設定による無期限残存 | 低 | `Expiration` 未設定で Notification Center に無期限残存 | `AppNotification.Expiration` / `ExpiresOnReboot` を適切に設定 |

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

## プロジェクト設定要件

### NuGet パッケージ

| パッケージ | 推奨バージョン | 用途 |
|-----------|-------------|------|
| `Microsoft.Windows.AppSDK` | 1.4.x 以降 | AppNotificationManager / AppNotificationBuilder |

NuGet パッケージ追加後、`.vcxproj` の `<PackageReference>` または `packages.config` に自動追加される。

### コンパイラフラグ

`.vcxproj` の `<ClCompile>` セクションに以下を設定する:

```xml
<LanguageStandard>stdcpp17</LanguageStandard>
<AdditionalOptions>/await /EHsc %(AdditionalOptions)</AdditionalOptions>
```

Visual Studio のプロジェクトプロパティでの設定箇所:
- C/C++ > 言語 > C++ 言語標準: `ISO C++17 標準 (/std:c++17)`
- C/C++ > コマンドライン > 追加オプション: `/await`
- C/C++ > コード生成 > C++ の例外を有効にする: `はい (/EHsc)`

### ヘッダ追加手順

```cpp
#include <winrt/Microsoft.Windows.AppNotifications.h>
#include <winrt/Microsoft.Windows.AppNotifications.Builder.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.h>
```

> 注: MFC DLL と組み合わせる場合は「MFC × C++/WinRT 共存時の注意点」のインクルード順序を先に確認すること。

---

## Package Identity 別の対応方針

| 配布形態 | Package Identity | Register() 呼び出し | マニフェスト要件 |
|---------|----------------|-------------------|--------------|
| MSIX パッケージ済み | あり（フル） | `Register()` (引数なし) | Package.appxmanifest に com / desktop 拡張定義が必要 |
| Sparse Package | あり（部分） | `Register()` (引数なし) | External location manifest に拡張定義が必要 |
| 未パッケージ（.exe 直実行） | なし | `Register(toastActivatorCLSID, launchUri)` | マニフェスト不要、CLSID を引数で直接指定 |
| 管理者権限実行 | 任意 | 呼び出し可能だが通知送信が**サイレント失敗** | `Setting()` で事前確認が必須 |

### 未パッケージアプリの注意点

- `Register(toastActivatorCLSID, launchUri)` の `toastActivatorCLSID` は COM サーバー CLSID の文字列（`{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}` 形式）
- 未パッケージアプリでは `Package.appxmanifest` への拡張定義は不要だが、レジストリへの COM サーバー登録が必要
- 環境によっては `Setting()` が `DisabledByManifest` を返すケースがある（要検証）

---

## MFC × C++/WinRT 共存時の注意点

MFC DLL（`CWinApp` 継承）と C++/WinRT を同一プロジェクトで使用する場合、以下の制約がある。

### ヘッダインクルード順序

MFC と WinRT のヘッダは順序依存のコンフリクトが発生しやすい。以下の順序を守ること:

```cpp
// pch.h / stdafx.h の先頭に MFC ヘッダを配置する
#include <afxwin.h>    // MFC コアと標準コンポーネント
#include <afxext.h>    // MFC 拡張

// MFC の後に WinRT ベースヘッダを続ける
#include <winrt/base.h>

// WinRT API ヘッダ
#include <winrt/Microsoft.Windows.AppNotifications.h>
#include <winrt/Microsoft.Windows.AppNotifications.Builder.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>
```

`windows.h` が MFC 経由でインクルードされる前に WinRT ヘッダが読み込まれると、`WIN32_LEAN_AND_MEAN` 等の定義有無で競合が発生する場合がある。

### 既知の制約事項

- WinRT の初期化（`winrt::init_apartment()`）は `DllMain` 内では行わない。最初の API 呼び出し前の適切なタイミング（MFC の `InitInstance()` 内など）で実行する
- `co_await` を MFC のメッセージポンプと併用する場合、コルーチンがメインスレッド以外で再開される可能性があるため、UI 操作は `DispatcherQueue` 経由で行う
- `/await` フラグと MFC の例外処理の競合を避けるため、`/EHsc` を明示的に指定すること

### 推奨コンパイラフラグ（まとめ）

```
/std:c++17 /await /EHsc
```

---

## サンプルコード集

使用言語: VC++（C++/WinRT）

必要なインクルード・名前空間:

```cpp
#include <winrt/Microsoft.Windows.AppNotifications.h>
#include <winrt/Microsoft.Windows.AppNotifications.Builder.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.Data.Xml.Dom.h>
#include <winrt/Windows.Foundation.h>

using namespace winrt::Microsoft::Windows::AppNotifications;
using namespace winrt::Microsoft::Windows::AppNotifications::Builder;
using namespace winrt::Microsoft::Windows::AppLifecycle;
using namespace winrt::Windows::UI::Notifications;
using namespace winrt::Windows::Data::Xml::Dom;
using namespace winrt::Windows::Foundation;
```

### 1. 初期化

```cpp
// アプリ起動時に必ず実行
// Register() は GetActivatedEventArgs() より前に呼ぶ（順序制約）
AppNotificationManager::Default().NotificationInvoked({ this, &App::OnNotificationInvoked });
AppNotificationManager::Default().Register();

// 通知起動かどうかを判定
auto activatedArgs = AppInstance::GetCurrent().GetActivatedEventArgs();
if (activatedArgs.Kind() == ExtendedActivationKind::AppNotification)
{
    auto notificationArgs = activatedArgs.Data().as<AppNotificationActivatedEventArgs>();
    HandleNotificationActivation(notificationArgs);
}
// 注: COM アクティベーション経由では Kind() が Launch として報告され、
// 引数が NotificationInvoked 経由で届くケースがあるため、
// ハンドラ側でも引数を受け取れるようにしておく。
```

### 1-B. 未パッケージアプリ向け初期化

```cpp
// 未パッケージアプリ（MSIX なし）では Register(toastActivatorCLSID, launchUri) を使用する
// CLSID はプロジェクト固有の一意な GUID を生成して使用すること
constexpr wchar_t kToastActivatorCLSID[] = L"{XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX}";

AppNotificationManager::Default().NotificationInvoked({ this, &App::OnNotificationInvoked });
AppNotificationManager::Default().Register(
    kToastActivatorCLSID,
    Uri(L"myapp://notification")  // 通知クリック時のアプリ起動 URI
);

// 通知起動かどうかを判定（パッケージ済みと同じ処理）
auto activatedArgs = AppInstance::GetCurrent().GetActivatedEventArgs();
if (activatedArgs.Kind() == ExtendedActivationKind::AppNotification)
{
    auto notificationArgs = activatedArgs.Data().as<AppNotificationActivatedEventArgs>();
    HandleNotificationActivation(notificationArgs);
}
```

> 注: 未パッケージアプリでは Package.appxmanifest の拡張定義は不要だが、レジストリへの COM サーバー登録が別途必要。CLSID は `{XXXXXXXX-...}` 形式の一意な GUID を事前に生成すること。

### 2. 基本 Toast 通知

```cpp
auto notification = AppNotificationBuilder()
    .AddText(L"タイトル")
    .AddText(L"本文テキスト")
    .SetTimeStamp(winrt::clock::now())
    .BuildNotification();

AppNotificationManager::Default().Show(notification);
```

### 3. 画像付き Toast 通知

```cpp
auto notification = AppNotificationBuilder()
    .AddText(L"画像付き通知")
    .SetAppLogoOverride(Uri(L"ms-appx:///Assets/Logo.png"), AppNotificationImageCrop::Circle)
    .SetHeroImage(Uri(L"ms-appx:///Assets/Hero.png"))
    .SetInlineImage(Uri(L"ms-appx:///Assets/Inline.png"))
    .BuildNotification();

AppNotificationManager::Default().Show(notification);
```

### 4. ボタン付き Toast 通知

```cpp
auto notification = AppNotificationBuilder()
    .AddText(L"確認が必要です")
    .AddButton(AppNotificationButton(L"承認")
        .AddArgument(L"action", L"approve")
        .AddArgument(L"id", L"123"))
    .AddButton(AppNotificationButton(L"拒否")
        .AddArgument(L"action", L"reject")
        .AddArgument(L"id", L"123"))
    .BuildNotification();

AppNotificationManager::Default().Show(notification);
```

### 5. テキスト入力付き Toast 通知

```cpp
auto notification = AppNotificationBuilder()
    .AddText(L"返信を入力してください")
    .AddTextBox(L"reply", L"返信内容を入力...", L"返信")
    .AddButton(AppNotificationButton(L"送信")
        .AddArgument(L"action", L"reply"))
    .BuildNotification();

AppNotificationManager::Default().Show(notification);
```

### 6. 進捗バー付き Toast 通知

```cpp
// 初期表示
AppNotificationProgressBar progressBar;
progressBar.Title(L"ファイル名.zip");
progressBar.Value(0.0);
progressBar.ValueStringOverride(L"0%");
progressBar.Status(L"開始中...");

auto notification = AppNotificationBuilder()
    .AddText(L"ダウンロード中...")
    .SetTag(L"download-1")
    .AddProgressBar(progressBar)
    .BuildNotification();

AppNotificationManager::Default().Show(notification);

// 進捗更新（結果を確認する）
AppNotificationProgressData progressData(1); // sequenceNumber
progressData.Value(0.5);
progressData.ValueStringOverride(L"50%");
progressData.Status(L"ダウンロード中...");

auto result = co_await AppNotificationManager::Default().UpdateAsync(progressData, L"download-1");
if (result != AppNotificationProgressResult::Succeeded)
{
    // 通知が存在しない等のケースを処理
}
```

### 7. スケジュール通知

```cpp
auto payload = AppNotificationBuilder()
    .AddText(L"リマインダー")
    .AddText(L"会議まで10分です")
    .BuildNotification()
    .Payload();

XmlDocument doc;
doc.LoadXml(payload);

auto scheduled = ScheduledToastNotification(
    doc,
    winrt::clock::now() + std::chrono::minutes(10)
);
scheduled.Tag(L"meeting-reminder");

ToastNotificationManager::CreateToastNotifier().AddToSchedule(scheduled);
```

### 8. Reminder/Alarm シナリオ（スヌーズをボタンで実現）

```cpp
// スヌーズ専用コンストラクタは Win10 以降 Deprecated のため、
// Reminder/Alarm シナリオ + ボタンでスヌーズ/解除を実現する。
auto notification = AppNotificationBuilder()
    .AddText(L"会議リマインダー")
    .SetScenario(AppNotificationScenario::Reminder)
    .AddButton(AppNotificationButton(L"スヌーズ")
        .AddArgument(L"action", L"snooze"))
    .AddButton(AppNotificationButton(L"解除")
        .AddArgument(L"action", L"dismiss"))
    .BuildNotification();

AppNotificationManager::Default().Show(notification);
// "snooze" 受信時にアプリ側で指定分後に再表示をスケジュールする
```

### 9. グループ / タグ管理

```cpp
// タグ・グループ付きで通知
auto notification = AppNotificationBuilder()
    .SetGroup(L"messages")
    .SetTag(L"msg-456")
    .AddText(L"新しいメッセージ")
    .BuildNotification();

AppNotificationManager::Default().Show(notification);

// グループ単位で削除
co_await AppNotificationManager::Default().RemoveByGroupAsync(L"messages");
```

### 10. バッジ通知

```cpp
auto badgeUpdater = BadgeUpdateManager::CreateBadgeUpdaterForApplication();

// 数値バッジ
auto badgeDoc = BadgeUpdateManager::GetTemplateContent(BadgeTemplateType::BadgeNumber);
auto badgeNode = badgeDoc.SelectSingleNode(L"//badge");
badgeNode.Attributes().GetNamedItem(L"value").NodeValue(winrt::box_value(L"5"));
badgeUpdater.Update(BadgeNotification(badgeDoc));

// バッジクリア
badgeUpdater.Clear();
```

### 11. 音声制御

```cpp
// カスタム音声をループ再生（Alarm シナリオと併用）
auto notification = AppNotificationBuilder()
    .AddText(L"アラーム")
    .SetScenario(AppNotificationScenario::Alarm)
    .SetAudioUri(Uri(L"ms-appx:///Assets/alarm.wav"), AppNotificationAudioLooping::Loop)
    .BuildNotification();

AppNotificationManager::Default().Show(notification);

// システム音声を指定
auto soundNotification = AppNotificationBuilder()
    .AddText(L"リマインダー")
    .SetAudioEvent(AppNotificationSoundEvent::Reminder)
    .BuildNotification();

// 音声ミュート
auto silentNotification = AppNotificationBuilder()
    .AddText(L"サイレント通知")
    .MuteAudio()
    .BuildNotification();
```

### 12. アクティベーションハンドラ

```cpp
void App::OnNotificationInvoked(
    AppNotificationManager const&,
    AppNotificationActivatedEventArgs const& args)
{
    auto arguments = args.Arguments();
    winrt::hstring action{};
    if (arguments.HasKey(L"action"))
    {
        action = arguments.Lookup(L"action");
    }

    if (action == L"approve")
    {
        auto id = arguments.Lookup(L"id");
        // 承認処理
    }
    else if (action == L"reply")
    {
        auto replyText = arguments.Lookup(L"reply");
        // 返信処理
    }
    else if (action == L"snooze")
    {
        // 指定分後に再表示をスケジュール
    }
    else
    {
        // 通知本体クリック → メインウィンドウを表示
        m_dispatcherQueue.TryEnqueue([this]()
        {
            m_window.Activate();
        });
    }
}
```

### 13. 通知サポート判定（フォールバック）

```cpp
if (AppNotificationManager::Default().Setting() != AppNotificationSetting::Enabled)
{
    // 通知が無効・未対応環境のフォールバック処理
    return;
}
AppNotificationManager::Default().Show(notification);
```

---

## Definition of Done

- [ ] `AppNotificationManager` による基本 Toast 通知の送信が動作する
- [ ] テキスト / 画像 / ボタン / テキスト入力 / コンボボックス / 進捗バー の各要素が表示できる
- [ ] ボタンクリック・入力値が `NotificationInvoked` イベントで正しく取得できる
- [ ] アプリ停止中の通知クリックでアプリが起動し、引数を受け取れる（COM アクティベーション経由で Kind=Launch のケースを含む）
- [ ] スケジュール通知の登録・一覧取得・キャンセルが動作する
- [ ] Reminder/Alarm シナリオのボタン方式でスヌーズ/解除が動作する
- [ ] タグ / グループ指定の通知削除が動作する
- [ ] バッジ通知の設定・クリアが動作する
- [ ] Alarm/Reminder シナリオで音声（カスタム音声 / システム音声 / ミュート / ループ）が動作する
- [ ] `AppNotificationManager::Default().Setting()`（AppNotificationSetting）によるフォールバック処理が実装されている
- [ ] マニフェストが正しく設定されている
  - [ ] com / desktop 名前空間が Package タグに追加されている
  - [ ] windows.toastNotificationActivation 拡張に ToastActivatorCLSID が設定されている
  - [ ] windows.comServer の ExeServer に `Arguments="----AppNotificationActivated:"` が指定されている
  - [ ] ToastActivatorCLSID と com:Class Id の GUID が一致している
- [ ] `IsUrgentScenarioSupported()` による互換性チェックが実装されている
