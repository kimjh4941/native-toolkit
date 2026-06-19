# Windows Notification 実装設計書

- 作成日: 2026-05-30
- 対象OS: Windows
- 対象企画書: `artifact/plans/notification/2026-05-30-windows-notification-research-v2.md`
- 言語: VC++（C++/WinRT）

---

## 設計目的

Windows App SDK の `AppNotificationManager` を使用した Toast 通知機能を `WindowsLibrary` MFC DLL に追加し、Unity Bridge（C API）経由で Unity から呼び出せる形で提供する。

---

## スコープ

### In Scope

- Toast 通知（基本表示 / アクション付き / 画像付き / 進捗バー付き）
- 音声制御（カスタム音声 / システム音声 / ミュート / ループ）
- スケジュール通知（指定時刻 / Reminder・Alarm シナリオ）
- グループ・タグ管理
- バッジ通知
- 通知クリック・アクションのコールバック（C 関数ポインタ）
- 通知履歴管理（削除・全削除）
- フォールバック判定（`Setting()` プロパティ）
- パッケージ済み / 未パッケージアプリの初期化分岐

### Out of Scope

- プッシュ通知（WNS）
- Tile 通知
- Windows 10 Build 19041 未満の対応
- ToastCollection（コレクション単位管理）— 将来拡張
- UserNotificationListener（全アプリ通知取得）— 将来拡張

---

## 共通実装方針の適用チェック（common.md 準拠）

| 項目 | 対応 | 備考 |
|-----|------|------|
| Clean Architecture 層分離 | 適合（変形） | Windows 既存実装は Manager + C Bridge のフラット構造。UseCase/Repository は Manager 内に統合する |
| Domain エラー型 | 適合 | `WindowsNotificationError` 定数として `WindowsNotificationManager.h` に定義 |
| Manager がシステム Delegate を所有 | 適合 | `NotificationInvoked` イベントは `WindowsNotificationManager` シングルトンのみが所有 |
| Manager → UseCase → Repository 経路 | 変形 | UseCase 相当のロジックを Manager 内メソッドに統合（既存 Dialog パターンに合わせる） |
| Bridge は薄く保つ | 適合 | `extern "C"` 関数は Manager メソッドの呼び出しのみ |
| 複雑なデータは JSON 文字列で渡す | 適合 | 通知ペイロードは JSON 文字列で Bridge に渡す |
| 最小 OS: Windows 11 | 適合 | Build 22000 以降を前提。Win10 対応は Out of Scope |

---

## 個別実装方針の適用チェック（windows.md 準拠）

| 項目 | 対応 | 備考 |
|-----|------|------|
| 全メソッド先頭に DFLog | 適合 | TAG は `L"WindowsNotificationManager"` |
| 公開ヘッダに Doxygen コメント | 適合 | `extern "C"` 関数全てに `@brief / @param / @return` |
| コメント・メッセージは英語 | 適合 | |
| `wchar_t*` / `std::wstring` 優先 | 適合 | |
| `extern "C"` + `__declspec(dllexport/dllimport)` | 適合 | |
| バッファを受け取る API に `buffer_size` 必須 | 適合 | 引数 JSON 文字列を返す API で適用 |
| エラーは `DWORD* pError` out 引数 | 適合 | |

---

## 既存実装差分サマリー

| 項目 | 現状 | 変更内容 |
|-----|------|---------|
| `pch.h` | `framework.h` のみ | WinRT ヘッダを MFC の後に追加 |
| `WindowsLibrary.vcxproj` | C++ 標準未指定、`/await` なし | `/std:c++17`・`/await`・`/EHsc` を全構成に追加 |
| NuGet パッケージ | なし | `Microsoft.Windows.AppSDK` 1.4.x 追加 |
| `CWindowsLibraryApp::InitInstance()` | MFC 初期化のみ | WinRT アパートメント初期化を追加 |
| 新規ファイル | - | `WindowsNotificationManager.h` / `.cpp` |
| 破壊的変更 | なし | 既存 DialogManager API は変更しない |

---

## 実装アーキテクチャ

```
Unity C# (P/Invoke)
    │
    ▼
extern "C" C Bridge API       ← WindowsNotificationManager.h
    │
    ▼
WindowsNotificationManager    ← WindowsNotificationManager.cpp
（singleton class）
    │
    ├── AppNotificationManager::Default()   [Windows App SDK]
    │       ├── Register() / Unregister()
    │       ├── Show()
    │       ├── UpdateAsync()
    │       ├── RemoveByXxx()
    │       └── NotificationInvoked event
    │
    ├── ToastNotificationManager            [Windows.UI.Notifications]
    │       └── AddToSchedule()
    │
    └── BadgeUpdateManager                 [Windows.UI.Notifications]
            └── Update() / Clear()
```

---

## サブ機能別詳細設計

### 1. 初期化 / 終了

**責務:** AppNotificationManager の Register と NotificationInvoked ハンドラの登録

**内部メソッド:**
```cpp
void WindowsNotificationManager::Init(
    NotificationInvokedCallback callback,
    BOOL isPackaged,
    const wchar_t* toastActivatorCLSID,
    const wchar_t* launchUri,
    DWORD* pError);

void WindowsNotificationManager::Uninit();
```

**制御フロー:**
1. `winrt::init_apartment()` が未実行であれば初期化（`InitInstance()` で実行済みのため通常スキップ）
2. `NotificationInvoked` イベントに `OnNotificationInvoked` を登録
3. `isPackaged == TRUE`: `Register()`（引数なし）
4. `isPackaged == FALSE`: `Register(toastActivatorCLSID, Uri(launchUri))`
5. `Setting()` を確認し、結果をログ出力
6. `m_initialized = true`

**エラーケース:**
- 管理者権限で実行中: `Register()` は成功するが後続の `Show()` がサイレント失敗 → `NOTIFICATION_WARNING_ADMIN_ELEVATION` をログ出力

---

### 2. Toast 通知表示

**責務:** JSON ペイロードを解析して `AppNotificationBuilder` を構築し、`Show()` する

**内部メソッド:**
```cpp
void WindowsNotificationManager::Show(const wchar_t* jsonPayload, DWORD* pError);

AppNotificationBuilder WindowsNotificationManager::BuildFromJson(
    const winrt::Windows::Data::Json::JsonObject& json);
```

**JSON ペイロード仕様:**
```json
{
  "title": "string",
  "body": "string",
  "tag": "string",
  "group": "string",
  "scenario": "default|reminder|alarm|urgent|incomingCall",
  "duration": "short|long",
  "timestamp": 1234567890,
  "attribution": "string",
  "appLogo": { "uri": "ms-appx:///...", "crop": "default|circle" },
  "heroImage": "ms-appx:///...",
  "inlineImage": "ms-appx:///...",
  "buttons": [
    { "label": "string", "args": { "key": "value" } }
  ],
  "textBoxes": [
    { "id": "string", "placeholder": "string", "title": "string" }
  ],
  "progress": {
    "title": "string", "value": 0.5, "valueStr": "50%", "status": "string"
  },
  "audio": {
    "type": "uri|event|mute",
    "uri": "ms-appx:///...",
    "event": "default|reminder|alarm|loopingAlarm|loopingCall",
    "loop": false
  }
}
```

**制御フロー:**
1. `m_initialized` チェック → 未初期化なら `NOTIFICATION_ERROR_NOT_INITIALIZED`
2. `Setting()` チェック → `Enabled` でなければ `NOTIFICATION_ERROR_DISABLED`
3. `JsonObject::Parse()` で JSON 解析 → 失敗なら `NOTIFICATION_ERROR_INVALID_PAYLOAD`
4. `BuildFromJson()` で `AppNotificationBuilder` 構築
5. `AppNotificationManager::Default().Show(notification)`

---

### 3. スケジュール通知

**責務:** 指定時刻に Toast 通知を表示登録する

**内部メソッド:**
```cpp
void WindowsNotificationManager::Schedule(
    const wchar_t* jsonPayload,
    int64_t scheduledTimeUnixMs,
    DWORD* pError);
```

**制御フロー:**
1. `Show()` と同じ初期化・JSON 解析
2. `BuildNotification().Payload()` で XML 取得
3. `XmlDocument::LoadXml()` で読み込み
4. `scheduledTimeUnixMs` を `winrt::Windows::Foundation::DateTime` に変換
5. `ScheduledToastNotification(doc, scheduledTime)` 生成
6. `ToastNotificationManager::CreateToastNotifier().AddToSchedule()`

**注意:** スヌーズは `Schedule()` では実装しない。Reminder/Alarm シナリオのボタン経由で `OnNotificationInvoked` から再 `Schedule()` するパターンを推奨。

---

### 4. 進捗バー更新

**責務:** 既存の進捗バー通知を `UpdateAsync()` で更新する

**内部メソッド:**
```cpp
void WindowsNotificationManager::UpdateProgress(
    const wchar_t* tag,
    const wchar_t* group,
    double value,
    const wchar_t* valueStr,
    const wchar_t* status,
    uint32_t sequenceNumber,
    DWORD* pError);
```

**制御フロー:**
1. `AppNotificationProgressData(sequenceNumber)` 構築
2. `Value`, `ValueStringOverride`, `Status` 設定
3. `group` が空なら `UpdateAsync(data, tag)`、非空なら `UpdateAsync(data, tag, group)`
4. 結果が `AppNotificationProgressResult::Succeeded` 以外なら `NOTIFICATION_ERROR_PROGRESS_NOT_FOUND`

**非同期処理:** `co_await` を使用。Bridge 関数は `winrt::get<>` または `IAsyncOperation::get()` でブロッキング呼び出しに変換する（Unity 呼び出し元スレッドが非 UI スレッドのため可）。

---

### 5. バッジ通知

**責務:** タスクバーアイコンのバッジを数値またはグリフで更新する

**内部メソッド:**
```cpp
void WindowsNotificationManager::SetBadge(int value, DWORD* pError);
```

**パラメータ仕様:**
- `value > 0`: 数値バッジ（表示値）
- `value == 0`: バッジクリア
- `value == -1`: グリフバッジ `alert`
- `value == -2`: グリフバッジ `activity`
- `value == -3`: グリフバッジ `newMessage`
- `value == -4`: グリフバッジ `available`
- `value == -5`: グリフバッジ `busy`
- `value == -6`: グリフバッジ `away`

**制御フロー:**
1. `value == 0`: `BadgeUpdater.Clear()`
2. `value > 0`: `BadgeTemplateType::BadgeNumber` XML 構築 → `Update()`
3. `value < 0`: `BadgeTemplateType::BadgeGlyph` XML 構築 → `Update()`

---

### 6. 通知ハンドリング

**責務:** 通知クリック・ボタン押下を C コールバックで呼び出し元へ通知する

**コールバック型:**
```cpp
typedef void (*NotificationInvokedCallback)(const wchar_t* argsJson);
```

**argsJson 仕様:**
```json
{ "action": "approve", "id": "123", "reply": "input text" }
```

**内部メソッド:**
```cpp
void WindowsNotificationManager::OnNotificationInvoked(
    winrt::Microsoft::Windows::AppNotifications::AppNotificationManager const&,
    winrt::Microsoft::Windows::AppNotifications::AppNotificationActivatedEventArgs const& args);
```

**制御フロー:**
1. `args.Arguments()` から `IMap<hstring, hstring>` 取得
2. キーバリューを JSON 文字列に変換
3. `m_callback(argsJson.c_str())` 呼び出し
4. COM アクティベーション経由での起動時（`Kind == Launch`）も `NotificationInvoked` 経由で引数が届くため、上記ハンドラで統一処理

---

### 7. 通知削除

**責務:** ID / タグ / グループ / 全削除を提供する

**内部メソッド:**
```cpp
void WindowsNotificationManager::RemoveById(uint32_t notificationId, DWORD* pError);
void WindowsNotificationManager::RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError);
void WindowsNotificationManager::RemoveAll(DWORD* pError);
```

**制御フロー:** 各 `RemoveByXxxAsync()` を `get()` でブロッキング呼び出し。

---

### 8. 設定状態取得

**責務:** `Setting()` の結果を int として返す（フォールバック判定用）

**内部メソッド:**
```cpp
int WindowsNotificationManager::GetSetting();
```

**返却値マッピング:**
```
0: Enabled
1: DisabledForApplication
2: DisabledForUser
3: DisabledByGroupPolicy
4: DisabledByManifest
```

---

## API 設計（公開 C Bridge）

```cpp
// WindowsNotificationManager.h

#ifdef WINDOWSLIBRARY_EXPORTS
#define WINDOWSNOTIFICATIONMANAGER_API __declspec(dllexport)
#else
#define WINDOWSNOTIFICATIONMANAGER_API __declspec(dllimport)
#endif

// Error codes
#define NOTIFICATION_SUCCESS                    0
#define NOTIFICATION_ERROR_NOT_INITIALIZED      1
#define NOTIFICATION_ERROR_DISABLED             2
#define NOTIFICATION_ERROR_INVALID_PAYLOAD      3
#define NOTIFICATION_ERROR_PROGRESS_NOT_FOUND   4
#define NOTIFICATION_ERROR_HRESULT_FAILURE      5
#define NOTIFICATION_ERROR_BADGE_FAILED         6

// Callback type
typedef void (*NotificationInvokedCallback)(const wchar_t* argsJson);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void initNotificationManager(
    NotificationInvokedCallback callback,
    BOOL isPackaged,
    const wchar_t* toastActivatorCLSID,
    const wchar_t* launchUri,
    DWORD* pError
);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void uninitNotificationManager();

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void showNotification(
    const wchar_t* jsonPayload,
    DWORD* pError
);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void scheduleNotification(
    const wchar_t* jsonPayload,
    int64_t scheduledTimeUnixMs,
    DWORD* pError
);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void updateNotificationProgress(
    const wchar_t* tag,
    const wchar_t* group,
    double value,
    const wchar_t* valueStr,
    const wchar_t* status,
    uint32_t sequenceNumber,
    DWORD* pError
);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void setBadge(int value, DWORD* pError);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void removeNotificationById(uint32_t notificationId, DWORD* pError);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void removeNotificationsByTag(
    const wchar_t* tag,
    const wchar_t* group,
    DWORD* pError
);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
void removeAllNotifications(DWORD* pError);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
int getNotificationSetting();
```

---

## 内部クラス設計

```cpp
// WindowsNotificationManager.cpp（内部）

class WindowsNotificationManager
{
public:
    static WindowsNotificationManager& GetInstance();

    void Init(NotificationInvokedCallback callback, BOOL isPackaged,
              const wchar_t* clsid, const wchar_t* launchUri, DWORD* pError);
    void Uninit();
    void Show(const wchar_t* jsonPayload, DWORD* pError);
    void Schedule(const wchar_t* jsonPayload, int64_t scheduledTimeMs, DWORD* pError);
    void UpdateProgress(const wchar_t* tag, const wchar_t* group,
                        double value, const wchar_t* valueStr,
                        const wchar_t* status, uint32_t seq, DWORD* pError);
    void SetBadge(int value, DWORD* pError);
    void RemoveById(uint32_t id, DWORD* pError);
    void RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError);
    void RemoveAll(DWORD* pError);
    int  GetSetting();

private:
    WindowsNotificationManager() = default;

    void OnNotificationInvoked(
        winrt::Microsoft::Windows::AppNotifications::AppNotificationManager const&,
        winrt::Microsoft::Windows::AppNotifications::AppNotificationActivatedEventArgs const& args);

    winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder
        BuildFromJson(const winrt::Windows::Data::Json::JsonObject& json);

    std::wstring ArgsToJson(
        const winrt::Windows::Foundation::Collections::IMap<
            winrt::hstring, winrt::hstring>& args);

    NotificationInvokedCallback m_callback = nullptr;
    bool m_initialized = false;
    winrt::event_token m_invokedToken{};
};
```

---

## ドメインエラー一覧（全ケース）

| エラー定数 | 値 | 発生条件 |
|-----------|---|---------|
| `NOTIFICATION_SUCCESS` | 0 | 成功 |
| `NOTIFICATION_ERROR_NOT_INITIALIZED` | 1 | `initNotificationManager()` 未呼び出し |
| `NOTIFICATION_ERROR_DISABLED` | 2 | `Setting()` が `Enabled` 以外 |
| `NOTIFICATION_ERROR_INVALID_PAYLOAD` | 3 | JSON パース失敗、必須キー不足 |
| `NOTIFICATION_ERROR_PROGRESS_NOT_FOUND` | 4 | `UpdateAsync` が `Succeeded` 以外を返した |
| `NOTIFICATION_ERROR_HRESULT_FAILURE` | 5 | WinRT 例外 / HRESULT エラー |
| `NOTIFICATION_ERROR_BADGE_FAILED` | 6 | バッジ XML 構築またはアップデート失敗 |

---

## エラーコード / メッセージ対応表

| エラー定数 | pError 値 | Bridge 戻り値 | ログメッセージ例 |
|-----------|----------|--------------|---------------|
| `NOTIFICATION_SUCCESS` | 0 | - | - |
| `NOTIFICATION_ERROR_NOT_INITIALIZED` | 1 | `pError` に設定 | `[Show] not initialized` |
| `NOTIFICATION_ERROR_DISABLED` | 2 | `pError` に設定 | `[Show] notification disabled. setting=%d` |
| `NOTIFICATION_ERROR_INVALID_PAYLOAD` | 3 | `pError` に設定 | `[Show] invalid JSON payload` |
| `NOTIFICATION_ERROR_PROGRESS_NOT_FOUND` | 4 | `pError` に設定 | `[UpdateProgress] notification not found. tag=%ls` |
| `NOTIFICATION_ERROR_HRESULT_FAILURE` | 5 | `pError` に HRESULT 格納 | `[Show] WinRT exception. hr=0x%08lx` |
| `NOTIFICATION_ERROR_BADGE_FAILED` | 6 | `pError` に設定 | `[SetBadge] badge update failed. value=%d` |

---

## pch.h 変更設計

```cpp
// pch.h — 変更後（MFC → WinRT の順序を厳守）
#ifndef PCH_H
#define PCH_H

#include "framework.h"          // MFC: afxwin.h, afxext.h を包含

// WinRT base（MFC の後に配置）
#include <winrt/base.h>

// Windows App SDK — Notification
#include <winrt/Microsoft.Windows.AppNotifications.h>
#include <winrt/Microsoft.Windows.AppNotifications.Builder.h>
#include <winrt/Microsoft.Windows.AppLifecycle.h>

// Windows.UI.Notifications — Schedule / Badge
#include <winrt/Windows.UI.Notifications.h>
#include <winrt/Windows.Data.Xml.Dom.h>

// JSON parsing
#include <winrt/Windows.Data.Json.h>

// C++ standard
#include <string>
#include <chrono>

#endif // PCH_H
```

---

## vcxproj 変更設計

全 `<ItemDefinitionGroup>` の `<ClCompile>` に以下を追加：

```xml
<LanguageStandard>stdcpp17</LanguageStandard>
<AdditionalOptions>/await /EHsc %(AdditionalOptions)</AdditionalOptions>
```

`<PackageReference>` を追加（ `<ItemGroup>` 内）:

```xml
<PackageReference Include="Microsoft.Windows.AppSDK">
  <Version>1.4.*</Version>
</PackageReference>
```

---

## CWindowsLibraryApp::InitInstance() 変更設計

```cpp
BOOL CWindowsLibraryApp::InitInstance()
{
    CWinApp::InitInstance();

    // WinRT apartment initialization (after MFC init, not in DllMain)
    winrt::init_apartment();

    return TRUE;
}
```

---

## テスト設計

### 単体テスト（要検証: 現プロジェクトにテストプロジェクト未存在）

WindowsLibrary に対するテストプロジェクトは現状存在しないため、手動確認を中心とする。将来的には `WindowsLibraryTest.vcxproj`（Google Test / MSTest）を追加することを推奨。

### 統合テスト項目（WindowsLibraryExample での手動確認）

| No | テスト内容 | 正常系/異常系 | 確認観点 |
|---|-----------|------------|---------|
| T-01 | `initNotificationManager()` → `showNotification()` 基本 Toast | 正常 | Notification Center に表示される |
| T-02 | `showNotification()` — ボタン付き | 正常 | ボタンが2つ表示、クリックでコールバック発火 |
| T-03 | `showNotification()` — 画像付き（AppLogo/Hero/Inline） | 正常 | 各画像が正しく表示される |
| T-04 | `showNotification()` — 進捗バー → `updateNotificationProgress()` | 正常 | 進捗値が通知上で更新される |
| T-05 | `showNotification()` — Alarm シナリオ + カスタム音声ループ | 正常 | 音声がループ再生される |
| T-06 | `scheduleNotification()` — 60秒後 | 正常 | 60秒後に通知が表示される |
| T-07 | `setBadge(5)` | 正常 | タスクバーに「5」が表示される |
| T-08 | `setBadge(0)` | 正常 | バッジがクリアされる |
| T-09 | `removeNotificationsByTag()` | 正常 | 指定タグの通知が Notification Center から消える |
| T-10 | `removeAllNotifications()` | 正常 | 全通知が消える |
| T-11 | `uninitNotificationManager()` → `showNotification()` | 異常 | `pError == NOTIFICATION_ERROR_NOT_INITIALIZED` |
| T-12 | 通知を OS 設定で無効化 → `showNotification()` | 異常 | `pError == NOTIFICATION_ERROR_DISABLED` |
| T-13 | 不正 JSON → `showNotification()` | 異常 | `pError == NOTIFICATION_ERROR_INVALID_PAYLOAD` |
| T-14 | `updateNotificationProgress()` — 存在しないタグ指定 | 異常 | `pError == NOTIFICATION_ERROR_PROGRESS_NOT_FOUND` |
| T-15 | 管理者権限で実行 → `showNotification()` | 異常 | サイレント失敗、ログに warning が出力される |
| T-16 | 未パッケージ (`isPackaged=FALSE`) で Init → Show | 正常 | 通知が表示される（要検証: COM 登録環境依存） |
| T-17 | `getNotificationSetting()` — 通知有効時 | 正常 | 戻り値 0（Enabled） |
| T-18 | 通知クリック（フォアグラウンド） | 正常 | コールバックに argsJson が渡される |
| T-19 | 通知クリック（アプリ未起動 → 再起動） | 正常 | 起動後にコールバックが発火する（COM アクティベーション経由も含む） |

### リスク項目に対応する検証ケース

| リスク | 対応テスト |
|-------|----------|
| 管理者権限でのサイレント失敗 | T-15 |
| マニフェスト設定不備 | T-01（マニフェスト未設定では通知が届かないことで検出） |
| パッケージ済み/未パッケージの手順差異 | T-16 |
| `UpdateAsync` の結果判定漏れ | T-14 |
| `Setting()` によるフォールバック | T-12 / T-17 |

---

## 実装タスク分解

```
[Task 1] プロジェクト設定
  依存: なし
  工数: 0.5日
  作業:
    - vcxproj に /std:c++17 / /await / /EHsc を追加
    - Microsoft.Windows.AppSDK NuGet 追加
    - pch.h に WinRT ヘッダ追加（MFC 後）
    - InitInstance() に winrt::init_apartment() 追加
    - ビルドエラー0件を確認
  完了条件: Debug|x64 / Release|x64 の両構成でビルドが通る
  レビュー観点: MFC / WinRT ヘッダ順序、/EHsc の明示指定

[Task 2] WindowsNotificationManager コア実装（Init / Show）
  依存: Task 1
  工数: 1日
  作業:
    - WindowsNotificationManager.h 作成（エラー定数・コールバック型・Bridge C API 宣言）
    - WindowsNotificationManager.cpp 作成（シングルトン・Init・Uninit）
    - BuildFromJson() 実装（基本テキスト・ボタン・画像・音声・シナリオ）
    - Show() 実装（Setting チェック → BuildFromJson → Show）
    - 全メソッドに DFLog 追加
    - Doxygen コメント付与
    - vcxproj に .h/.cpp を追加
  完了条件: T-01〜T-05 が手動確認で通る
  レビュー観点: JSON ペイロード仕様の網羅性、エラーコード返却の一貫性

[Task 3] スケジュール / 進捗 / バッジ / 削除実装
  依存: Task 2
  工数: 1日
  作業:
    - Schedule() 実装
    - UpdateProgress() 実装（非同期ブロッキング変換）
    - SetBadge() 実装（数値・グリフ・クリア）
    - RemoveById / RemoveByTag / RemoveAll 実装
  完了条件: T-06〜T-14 が手動確認で通る
  レビュー観点: AppNotificationProgressResult の判定漏れなし、非同期のブロッキング安全性

[Task 4] 通知ハンドリング / 未パッケージ対応
  依存: Task 2
  工数: 0.5日
  作業:
    - OnNotificationInvoked() 実装（args → JSON 変換 → callback）
    - 未パッケージ初期化分岐の実装と動作確認
    - GetSetting() Bridge 関数実装
  完了条件: T-16〜T-19 が手動確認で通る
  レビュー観点: COM アクティベーション経由の起動経路（Kind==Launch ケース）の処理

[Task 5] 統合確認・ドキュメント整備
  依存: Task 1〜4
  工数: 0.5日
  作業:
    - 全テスト項目（T-01〜T-19）の手動確認
    - 管理者権限実行でのサイレント失敗確認（T-15）
    - WindowsLibrary.def に新規 export 関数を追加
  完了条件: 全テスト項目が確認済みになる
  レビュー観点: .def ファイルの輸出漏れなし
```

**合計工数: 3.5日**

**タスク依存関係:**
```
Task 1 → Task 2 → Task 3
                → Task 4
         Task 3 → Task 5
         Task 4 → Task 5
```

---

## リスクと緩和策

| リスク | 深刻度 | 緩和策 |
|-------|-------|-------|
| MFC + WinRT ヘッダ競合でビルドエラー | 高 | pch.h のインクルード順序（MFC → WinRT）を厳守。`/EHsc` 明示 |
| 管理者権限実行でサイレント失敗 | 高 | `Init()` 時に `Setting()` ログ出力。Bridge 呼び出し元に警告通知を検討 |
| 未パッケージアプリでの COM サーバー未登録 | 中 | Task 4 で動作確認。COM 登録手順をドキュメント化（要検証） |
| `co_await` ブロッキング変換のデッドロック | 中 | Unity 呼び出しは非 UI スレッドのため問題なし。UI スレッドからの呼び出しは禁止とする |
| NuGet パッケージの x86/x64 混在 | 低 | `Microsoft.Windows.AppSDK` は x86/x64 両対応を確認してから採用 |
| マニフェスト設定不備（CLSID 未設定） | 低 | Task 5 のテスト T-01 でマニフェストなし環境を検出 |

---

## Definition of Done

- [ ] `initNotificationManager()` の Init/Uninit が正常に動作する
- [ ] `showNotification()` でテキスト / 画像 / ボタン / テキスト入力 / 進捗バーの Toast が表示できる
- [ ] `scheduleNotification()` で指定時刻の通知が届く
- [ ] Reminder/Alarm シナリオでボタン方式のスヌーズが動作する
- [ ] `updateNotificationProgress()` で通知の進捗値が更新される（`AppNotificationProgressResult` を確認）
- [ ] `setBadge()` でタスクバーのバッジが数値・グリフ・クリアで動作する
- [ ] `removeNotificationsByTag()` / `removeAllNotifications()` が動作する
- [ ] `getNotificationSetting()` が `AppNotificationSetting` の値を返す
- [ ] `NotificationInvokedCallback` が通知クリック時に JSON argsJson で呼び出される
- [ ] 未パッケージアプリ（`isPackaged=FALSE`）での初期化が動作する（要検証）
- [ ] 管理者権限実行時にサイレント失敗し、ログに警告が出力される
- [ ] `pError` に適切なエラーコードが返される（全エラーケース）
- [ ] 全メソッドに DFLog が付与されている
- [ ] 公開 API に Doxygen コメントが付与されている
- [ ] ビルドが Debug|x64 / Release|x64 の両構成で成功する
- [ ] `WindowsLibrary.def` に全 export 関数が記載されている
