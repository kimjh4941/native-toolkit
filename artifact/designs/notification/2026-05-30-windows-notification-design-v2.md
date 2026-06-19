# Windows Notification 実装設計書

- 作成日: 2026-05-30
- 改訂日: 2026-05-30（v2 — レビュー反映）
- 対象OS: Windows（最小: Windows 11）
- 対象企画書: `artifact/plans/notification/2026-05-30-windows-notification-research-v2.md`
- 言語: VC++（C++/WinRT）

> **v1 からの主な変更点**
> - `AppNotificationActivatedEventArgs.UserInput` による返信入力取得を OnNotificationInvoked に追加
> - コンボボックス（AddComboBox）・通知一覧取得・スケジュールキャンセル・有効期限設定を In Scope に追加
> - `NOTIFICATION_ERROR_INVALID_PARAMETER`（バリデーション系）を新設し、バリデーション系エラーの集約方針を明記
> - `getNotificationSetting()` の返却仕様をエラーコード体系と分離、統一 API 返却仕様表を追加
> - 最小 OS を Windows 11 に修正（レビュー指摘反映）
> - 未パッケージアプリの COM サーバー登録手順を追加
> - ArgsToJson の JSON エスケープ方針を明記
> - Task 2 / Task 4 の依存逆転を修正
> - HRESULT_FAILURE / BADGE_FAILED / reply 取得の異常系テストを追加
> - BuildFromJson のサブ関数分割方針を追加

---

## 設計目的

Windows App SDK の `AppNotificationManager` を使用した Toast 通知機能を `WindowsLibrary` MFC DLL に追加し、Unity Bridge（C API）経由で Unity から呼び出せる形で提供する。

---

## スコープ

### In Scope

- Toast 通知（基本表示 / アクション付き / 画像付き / 進捗バー付き）
- 音声制御（カスタム音声 / システム音声 / ミュート / ループ）
- スケジュール通知（指定時刻 / Reminder・Alarm シナリオ）
- スケジュール通知キャンセル（`RemoveFromSchedule`）
- グループ・タグ管理
- バッジ通知
- 通知クリック・アクションのコールバック（C 関数ポインタ）
- テキスト入力（`textBoxes`）およびコンボボックス（`comboBoxes`）
- 通知履歴管理（削除・全削除）
- 通知一覧取得（`GetAllAsync`）
- 通知有効期限設定（`Expiration` / `ExpiresOnReboot`）
- フォールバック判定（`Setting()` プロパティ）
- パッケージ済み / 未パッケージアプリの初期化分岐

### Out of Scope

- プッシュ通知（WNS）
- Tile 通知
- Windows 11 未満の対応
- ToastCollection（コレクション単位管理）— 将来拡張
- UserNotificationListener（全アプリ通知取得）— 将来拡張

---

## 共通実装方針の適用チェック（common.md 準拠）

| 項目 | 対応 | 備考 |
|-----|------|------|
| Clean Architecture 層分離 | 適合（変形） | Windows 既存実装は Manager + C Bridge のフラット構造。UseCase/Repository は Manager 内に統合する |
| Domain エラー型 | 適合 | エラー定数として `WindowsNotificationManager.h` に定義（`NOTIFICATION_ERROR_*`） |
| Manager がシステム Delegate を所有 | 適合 | `NotificationInvoked` イベントは `WindowsNotificationManager` シングルトンのみが所有 |
| Manager → UseCase → Repository 経路 | 変形 | UseCase 相当のロジックを Manager 内メソッドに統合（既存 Dialog パターンに合わせる） |
| Bridge は薄く保つ | 適合 | `extern "C"` 関数は Manager メソッドの呼び出しのみ |
| 複雑なデータは JSON 文字列で渡す | 適合 | 通知ペイロードは JSON 文字列で Bridge に渡す |
| 最小 OS: Windows 11 | 適合 | Windows 11 以上を対象とする |

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
| `pch.h` | `framework.h` のみ（afxwin.h / afxext.h を包含） | WinRT ヘッダを MFC の後に追加 |
| `WindowsLibrary.vcxproj` | C++ 標準未指定、`/await` なし | `/std:c++17`・`/await`・`/EHsc` を全構成に追加 |
| NuGet パッケージ | なし | `Microsoft.Windows.AppSDK` 1.4.x 追加（x64 対応確認済み） |
| `CWindowsLibraryApp::InitInstance()` | MFC 初期化のみ | WinRT アパートメント初期化を追加 |
| 新規ファイル | - | `WindowsNotificationManager.h` / `.cpp` |
| `WindowsLibrary.def` | 既存 export のみ | 新規 Bridge 関数を追加 |
| 破壊的変更 | なし | 既存 DialogManager API は変更しない |

> **注意:** `framework.h` は `afxwin.h`・`afxext.h` を包含していることを実ファイルで確認してから pch.h を変更すること。

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
    │       ├── GetAllAsync()
    │       ├── UpdateAsync()
    │       ├── RemoveByXxx()
    │       └── NotificationInvoked event
    │
    ├── ToastNotificationManager            [Windows.UI.Notifications]
    │       ├── AddToSchedule()
    │       ├── RemoveFromSchedule()
    │       └── GetScheduledToastNotifications()
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
4. `isPackaged == FALSE`: COM サーバー登録確認後、`Register(toastActivatorCLSID, Uri(launchUri))`
5. `Setting()` を確認し、結果をログ出力
6. `m_initialized = true`

**未パッケージアプリの COM サーバー登録:**

未パッケージアプリが Toast 通知のコールバック（COM アクティベーション）を受け取るには、アプリのインストール時または起動時にレジストリへの COM サーバー登録が必要。

```
HKEY_CLASSES_ROOT\CLSID\{<toastActivatorCLSID>}
    LocalServer32 = "<アプリ実行ファイルのフルパス>"
```

Windows App SDK の `Register(CLSID, launchUri)` はこのレジストリ登録を内部で行う設計だが、環境依存のため Task 4 で動作確認を必須とする。COM 登録に失敗した場合は `NOTIFICATION_ERROR_HRESULT_FAILURE` を pError に設定してリターンする。

**エラーケース:**
- 管理者権限で実行中: `Register()` は成功するが後続の `Show()` がサイレント失敗 → `NOTIFICATION_WARNING_ADMIN_ELEVATION` をログ出力

---

### 2. Toast 通知表示

**責務:** JSON ペイロードを解析して `AppNotificationBuilder` を構築し、`Show()` する

**内部メソッド:**
```cpp
void WindowsNotificationManager::Show(const wchar_t* jsonPayload, DWORD* pError);

// BuildFromJson は責務単位でサブ関数に分割する
AppNotificationBuilder WindowsNotificationManager::BuildFromJson(
    const winrt::Windows::Data::Json::JsonObject& json, DWORD* pError);

// サブビルダー（内部ヘルパー）
void WindowsNotificationManager::ApplyButtons(
    AppNotificationBuilder& builder,
    const winrt::Windows::Data::Json::JsonArray& buttons, DWORD* pError);
void WindowsNotificationManager::ApplyComboBoxes(
    AppNotificationBuilder& builder,
    const winrt::Windows::Data::Json::JsonArray& combos, DWORD* pError);
void WindowsNotificationManager::ApplyImages(
    AppNotificationBuilder& builder,
    const winrt::Windows::Data::Json::JsonObject& json);
void WindowsNotificationManager::ApplyAudio(
    AppNotificationBuilder& builder,
    const winrt::Windows::Data::Json::JsonObject& audioObj, DWORD* pError);
void WindowsNotificationManager::ApplyProgress(
    AppNotificationBuilder& builder,
    const winrt::Windows::Data::Json::JsonObject& progressObj);
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
  "expiration": 3600,
  "expiresOnReboot": false,
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
  "comboBoxes": [
    {
      "id": "string",
      "title": "string",
      "defaultSelection": "string",
      "items": [{ "id": "string", "label": "string" }]
    }
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

**バリデーション規則（BuildFromJson 内で検証）:**

| 規則 | 違反時のエラー |
|-----|-------------|
| `buttons` は最大5個 | `NOTIFICATION_ERROR_INVALID_PARAMETER` |
| `audio.loop == true` の場合 `duration` は `"long"` 必須 | `NOTIFICATION_ERROR_INVALID_PARAMETER` |
| ボタンに `args` と `invokeUri` の同時指定不可 | `NOTIFICATION_ERROR_INVALID_PARAMETER` |
| `audio.type == "uri"` の場合 `uri` 必須 | `NOTIFICATION_ERROR_INVALID_PARAMETER` |
| `setBadge` の `value < -6` は不正 | `NOTIFICATION_ERROR_INVALID_PARAMETER` |

**制御フロー:**
1. `m_initialized` チェック → 未初期化なら `NOTIFICATION_ERROR_NOT_INITIALIZED`
2. `Setting()` チェック → `Enabled` でなければ `NOTIFICATION_ERROR_DISABLED`
3. `JsonObject::Parse()` で JSON 解析 → 失敗なら `NOTIFICATION_ERROR_INVALID_PAYLOAD`
4. `BuildFromJson()` で `AppNotificationBuilder` 構築（バリデーションエラーは内部で pError に設定し return）
5. `expiration` があれば `SetExpirationTime()` を設定
6. `expiresOnReboot == true` なら `SetExpiresOnReboot(true)` を設定
7. `AppNotificationManager::Default().Show(notification)`

---

### 3. スケジュール通知

**責務:** 指定時刻に Toast 通知を表示登録する

**内部メソッド:**
```cpp
void WindowsNotificationManager::Schedule(
    const wchar_t* jsonPayload,
    int64_t scheduledTimeUnixMs,
    DWORD* pError);

void WindowsNotificationManager::CancelScheduled(
    const wchar_t* tag,
    const wchar_t* group,
    DWORD* pError);
```

**制御フロー（Schedule）:**
1. `Show()` と同じ初期化・JSON 解析・バリデーション
2. `BuildNotification().Payload()` で XML 取得
3. `XmlDocument::LoadXml()` で読み込み
4. `scheduledTimeUnixMs` を `winrt::Windows::Foundation::DateTime` に変換
5. `ScheduledToastNotification(doc, scheduledTime)` 生成
6. `ToastNotificationManager::CreateToastNotifier().AddToSchedule()`

**制御フロー（CancelScheduled）:**
1. `GetScheduledToastNotifications()` で予約済み通知一覧を取得
2. `tag` / `group` が一致するものを `RemoveFromSchedule()` で削除

**注意:**
- スヌーズは `Schedule()` では実装しない。Reminder/Alarm シナリオのボタン経由で `OnNotificationInvoked` から再 `Schedule()` するパターンを推奨
- スケジュール通知のデリバリーウィンドウは5分。5分を超えた場合は OS により自動削除される。制御フローにこの制約を注記として記載し、ログ出力で警告する

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

**非同期処理:** `co_await` を使用。Bridge 関数は `IAsyncOperation::get()` でブロッキング呼び出しに変換する（Unity 呼び出し元スレッドが非 UI スレッドのため可。UI スレッドからの呼び出しは禁止）。

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
- `value < -6`: 不正値 → `NOTIFICATION_ERROR_INVALID_PARAMETER`

**制御フロー:**
1. `value < -6`: `NOTIFICATION_ERROR_INVALID_PARAMETER` を pError に設定してリターン
2. `value == 0`: `BadgeUpdater.Clear()`
3. `value > 0`: `BadgeTemplateType::BadgeNumber` XML 構築 → `Update()`
4. `value < 0 && value >= -6`: `BadgeTemplateType::BadgeGlyph` XML 構築 → `Update()`

---

### 6. 通知ハンドリング

**責務:** 通知クリック・ボタン押下・テキスト入力を C コールバックで呼び出し元へ通知する

**コールバック型:**
```cpp
typedef void (*NotificationInvokedCallback)(const wchar_t* argsJson);
```

**argsJson 仕様:**
```json
{
  "action": "approve",
  "id": "123",
  "reply": "input text from textBox",
  "combo_selection_id": "selected item id"
}
```

**内部メソッド:**
```cpp
void WindowsNotificationManager::OnNotificationInvoked(
    winrt::Microsoft::Windows::AppNotifications::AppNotificationManager const&,
    winrt::Microsoft::Windows::AppNotifications::AppNotificationActivatedEventArgs const& args);

std::wstring WindowsNotificationManager::ArgsToJson(
    const winrt::Windows::Foundation::Collections::IMap<winrt::hstring, winrt::hstring>& args,
    const winrt::Windows::Foundation::Collections::IMap<winrt::hstring, winrt::hstring>& userInput);
```

**制御フロー:**
1. `args.Arguments()` から `IMap<hstring, hstring>` 取得
2. `args.UserInput()` から `IMap<hstring, hstring>` 取得（テキスト入力・コンボボックスの選択値）
3. `ArgsToJson(arguments, userInput)` で JSON 文字列を生成
4. `m_callback(argsJson.c_str())` 呼び出し
5. COM アクティベーション経由での起動時（`Kind == Launch`）も `NotificationInvoked` 経由で引数が届くため、上記ハンドラで統一処理

**ArgsToJson の実装方針:**
- `JsonObject` / `JsonValue` を WinRT JSON API（`winrt::Windows::Data::Json`）で構築し、文字列連結による手組みは禁止
- `JsonValue::CreateStringValue()` を使用することで、ダブルクォート・バックスラッシュ・制御文字が自動エスケープされる
- `Arguments()` のキーバリューをそのままオブジェクトに追加し、`UserInput()` のキーバリューも同一オブジェクトにマージする

---

### 7. 通知削除 / 通知一覧取得

**責務:** ID / タグ / グループ / 全削除 / 一覧取得を提供する

**内部メソッド:**
```cpp
void WindowsNotificationManager::RemoveById(uint32_t notificationId, DWORD* pError);
void WindowsNotificationManager::RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError);
void WindowsNotificationManager::RemoveAll(DWORD* pError);
void WindowsNotificationManager::GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError);
```

**GetAll の outJson 仕様:**
```json
[
  { "id": 1, "tag": "tag1", "group": "group1" },
  { "id": 2, "tag": "tag2", "group": "" }
]
```

**制御フロー（GetAll）:**
1. `AppNotificationManager::Default().GetAllAsync().get()` で通知一覧を取得
2. 各通知の `id`, `tag`, `group` を JSON 配列に変換（WinRT JSON API を使用）
3. `wcsncpy_s(outJson, bufferSize, ...)` で出力バッファに書き込み

---

### 8. 設定状態取得

**責務:** `Setting()` の結果を int として返す（フォールバック判定用）

**内部メソッド:**
```cpp
int WindowsNotificationManager::GetSetting();
```

**返却値マッピング（`AppNotificationSetting` 列挙）:**

> この返却値はエラーコード（`NOTIFICATION_ERROR_*`）とは独立した別体系である。pError 引数は持たない。

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
#define NOTIFICATION_ERROR_INVALID_PARAMETER    7  // validation failures

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
void cancelScheduledNotification(
    const wchar_t* tag,
    const wchar_t* group,
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
void getAllNotifications(
    wchar_t* outJson,
    uint32_t bufferSize,
    DWORD* pError
);

extern "C" WINDOWSNOTIFICATIONMANAGER_API
int getNotificationSetting();
```

---

## 公開 API 返却仕様（統一対応表）

| Bridge 関数 | 返却型 | pError | 成功時 | 失敗時 |
|------------|-------|--------|-------|-------|
| `initNotificationManager` | `void` | あり | pError = 0 | pError = 1〜7 |
| `uninitNotificationManager` | `void` | なし | — | — |
| `showNotification` | `void` | あり | pError = 0 | pError = 1〜7 |
| `scheduleNotification` | `void` | あり | pError = 0 | pError = 1〜7 |
| `cancelScheduledNotification` | `void` | あり | pError = 0 | pError = 5 |
| `updateNotificationProgress` | `void` | あり | pError = 0 | pError = 1, 4, 5 |
| `setBadge` | `void` | あり | pError = 0 | pError = 6, 7 |
| `removeNotificationById` | `void` | あり | pError = 0 | pError = 5 |
| `removeNotificationsByTag` | `void` | あり | pError = 0 | pError = 5 |
| `removeAllNotifications` | `void` | あり | pError = 0 | pError = 5 |
| `getAllNotifications` | `void` | あり | pError = 0, outJson に JSON | pError = 5 |
| `getNotificationSetting` | `int` | なし | 0〜4（AppNotificationSetting 値） | -1（エラー） |

> `getNotificationSetting()` の返却値（0〜4）はエラーコード体系（0〜7）とは独立。エラー時のみ -1 を返す。

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
    void CancelScheduled(const wchar_t* tag, const wchar_t* group, DWORD* pError);
    void UpdateProgress(const wchar_t* tag, const wchar_t* group,
                        double value, const wchar_t* valueStr,
                        const wchar_t* status, uint32_t seq, DWORD* pError);
    void SetBadge(int value, DWORD* pError);
    void RemoveById(uint32_t id, DWORD* pError);
    void RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError);
    void RemoveAll(DWORD* pError);
    void GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError);
    int  GetSetting();

private:
    WindowsNotificationManager() = default;

    void OnNotificationInvoked(
        winrt::Microsoft::Windows::AppNotifications::AppNotificationManager const&,
        winrt::Microsoft::Windows::AppNotifications::AppNotificationActivatedEventArgs const& args);

    winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder
        BuildFromJson(const winrt::Windows::Data::Json::JsonObject& json, DWORD* pError);

    void ApplyButtons(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonArray& buttons, DWORD* pError);
    void ApplyComboBoxes(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonArray& combos, DWORD* pError);
    void ApplyImages(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonObject& json);
    void ApplyAudio(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonObject& audioObj, DWORD* pError);
    void ApplyProgress(
        winrt::Microsoft::Windows::AppNotifications::Builder::AppNotificationBuilder& builder,
        const winrt::Windows::Data::Json::JsonObject& progressObj);

    std::wstring ArgsToJson(
        const winrt::Windows::Foundation::Collections::IMap<winrt::hstring, winrt::hstring>& args,
        const winrt::Windows::Foundation::Collections::IMap<winrt::hstring, winrt::hstring>& userInput);

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
| `NOTIFICATION_ERROR_INVALID_PARAMETER` | 7 | バリデーション失敗（ボタン数超過・音声ループ制約・不正 badge value 等） |

---

## エラーコード / メッセージ対応表

| エラー定数 | pError 値 | ログメッセージ例 |
|-----------|----------|---------------|
| `NOTIFICATION_SUCCESS` | 0 | — |
| `NOTIFICATION_ERROR_NOT_INITIALIZED` | 1 | `[Show] not initialized` |
| `NOTIFICATION_ERROR_DISABLED` | 2 | `[Show] notification disabled. setting=%d` |
| `NOTIFICATION_ERROR_INVALID_PAYLOAD` | 3 | `[Show] invalid JSON payload` |
| `NOTIFICATION_ERROR_PROGRESS_NOT_FOUND` | 4 | `[UpdateProgress] notification not found. tag=%ls` |
| `NOTIFICATION_ERROR_HRESULT_FAILURE` | 5 | `[Show] WinRT exception. hr=0x%08lx` |
| `NOTIFICATION_ERROR_BADGE_FAILED` | 6 | `[SetBadge] badge update failed. value=%d` |
| `NOTIFICATION_ERROR_INVALID_PARAMETER` | 7 | `[BuildFromJson] validation failed. reason=%ls` |

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

// JSON parsing / building
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

`<PackageReference>` を追加（`<ItemGroup>` 内）:

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

### 単体テスト

**フレームワーク:** CppUnitTestFramework（Visual Studio 標準内蔵、VSTest.Console.exe で CI 実行可）

**テストプロジェクト:** `windows/WindowsLibraryTest/WindowsLibraryTest.vcxproj`（新規作成）
- プロジェクト種別: Native Unit Test Project
- `WindowsLibrary.vcxproj` を参照し、内部クラス・関数を直接テスト
- `WindowsLibrary.sln` に追加する

**自動化対象（WinRT 不要な純粋ロジック）:**

| テスト対象 | 確認内容 |
|-----------|---------|
| `BuildFromJson()` バリデーション | ボタン数超過・音声ループ制約・invokeUri 排他 |
| `ArgsToJson()` | 特殊文字エスケープ、UserInput マージ結果 |
| JSON パース失敗 | 不正 JSON・必須キー不足 で INVALID_PAYLOAD が返る |
| `SetBadge` バリデーション | `value < -6` で INVALID_PARAMETER が返る |

**手動確認が残る範囲（WinRT API 依存）:**

| 項目 | 理由 |
|------|------|
| `Show()` 実際の通知表示 | `AppNotificationManager` のモック困難 |
| スケジュール通知・コールバック発火 | OS イベントハンドラ依存 |
| バッジ表示・削除 | `BadgeUpdateManager` / `AppNotificationManager` 依存 |

### 統合テスト項目（WindowsLibraryExample での手動確認）

| No | テスト内容 | 正常系/異常系 | 確認観点 |
|---|-----------|------------|---------|
| T-01 | `initNotificationManager()` → `showNotification()` 基本 Toast | 正常 | Notification Center に表示される |
| T-02 | `showNotification()` — ボタン付き | 正常 | ボタンが2つ表示される |
| T-03 | `showNotification()` — 画像付き（AppLogo/Hero/Inline） | 正常 | 各画像が正しく表示される |
| T-04 | `showNotification()` — 進捗バー → `updateNotificationProgress()` | 正常 | 進捗値が通知上で更新される |
| T-05 | `showNotification()` — Alarm シナリオ + カスタム音声ループ | 正常 | 音声がループ再生される |
| T-06 | `scheduleNotification()` — 60秒後 | 正常 | 60秒後に通知が表示される |
| T-07 | `cancelScheduledNotification()` — スケジュール通知のキャンセル | 正常 | キャンセルした通知が届かない |
| T-08 | `setBadge(5)` | 正常 | タスクバーに「5」が表示される |
| T-09 | `setBadge(0)` | 正常 | バッジがクリアされる |
| T-10 | `removeNotificationsByTag()` | 正常 | 指定タグの通知が Notification Center から消える |
| T-11 | `removeAllNotifications()` | 正常 | 全通知が消える |
| T-12 | `getAllNotifications()` — 通知が複数ある状態 | 正常 | outJson に通知一覧が返される |
| T-13 | `uninitNotificationManager()` → `showNotification()` | 異常 | `pError == NOTIFICATION_ERROR_NOT_INITIALIZED` |
| T-14 | 通知を OS 設定で無効化 → `showNotification()` | 異常 | `pError == NOTIFICATION_ERROR_DISABLED` |
| T-15 | 不正 JSON → `showNotification()` | 異常 | `pError == NOTIFICATION_ERROR_INVALID_PAYLOAD` |
| T-16 | `updateNotificationProgress()` — 存在しないタグ指定 | 異常 | `pError == NOTIFICATION_ERROR_PROGRESS_NOT_FOUND` |
| T-17 | 管理者権限で実行 → `showNotification()` | 異常 | サイレント失敗、ログに warning が出力される |
| T-18 | 未パッケージ (`isPackaged=FALSE`) で Init → Show | 正常 | 通知が表示される（要検証: COM 登録環境依存） |
| T-19 | `getNotificationSetting()` — 通知有効時 | 正常 | 戻り値 0（Enabled） |
| T-20 | 通知クリック（フォアグラウンド） | 正常 | コールバックに argsJson が渡される |
| T-21 | 通知クリック（アプリ未起動 → 再起動） | 正常 | 起動後にコールバックが発火する（COM アクティベーション経由も含む） |
| T-22 | テキスト入力付き通知 → 返信入力 → ボタンクリック | 正常 | argsJson に `reply` フィールドが含まれる |
| T-23 | コンボボックス付き通知 → 項目選択 → ボタンクリック | 正常 | argsJson に `combo_selection_id` フィールドが含まれる |
| T-24 | 有効期限付き通知（expiration=60秒）→ 60秒後確認 | 正常 | 60秒後に Notification Center から自動削除される |
| T-25 | ボタン数 6個 → `showNotification()` | 異常 | `pError == NOTIFICATION_ERROR_INVALID_PARAMETER` |
| T-26 | `audio.loop=true` かつ `duration=short` → `showNotification()` | 異常 | `pError == NOTIFICATION_ERROR_INVALID_PARAMETER` |
| T-27 | `setBadge(-7)` | 異常 | `pError == NOTIFICATION_ERROR_INVALID_PARAMETER` |
| T-28 | WinRT 例外発生ケース（CLSID 不正など） | 異常 | `pError == NOTIFICATION_ERROR_HRESULT_FAILURE` |
| T-29 | バッジ XML が構築できない環境での `setBadge()` | 異常 | `pError == NOTIFICATION_ERROR_BADGE_FAILED` |

### リスク項目に対応する検証ケース

| リスク | 対応テスト |
|-------|----------|
| 管理者権限でのサイレント失敗 | T-17 |
| マニフェスト設定不備 | T-01（マニフェスト未設定では通知が届かないことで検出） |
| パッケージ済み/未パッケージの手順差異 | T-18 |
| `UpdateAsync` の結果判定漏れ | T-16 |
| `Setting()` によるフォールバック | T-14 / T-19 |
| ボタン数超過・音声ループ制約違反 | T-25 / T-26 |
| テキスト入力 reply 取得漏れ | T-22 |
| WinRT 例外の HRESULT_FAILURE | T-28 |
| バッジ更新失敗 | T-29 |

---

## 実装タスク分解

```
[Task 1] プロジェクト設定
  依存: なし
  工数: 0.5日
  作業:
    - vcxproj に /std:c++17 / /await / /EHsc を追加
    - Microsoft.Windows.AppSDK NuGet 追加（x64 対応確認）
    - pch.h に WinRT ヘッダ追加（MFC 後）。framework.h の include 内容を確認してから変更
    - InitInstance() に winrt::init_apartment() 追加
    - WindowsLibrary.def に全 Bridge 関数を追加（新規関数分）
    - WindowsLibraryTest.vcxproj（Native Unit Test Project）を新規作成し WindowsLibrary.sln に追加
    - ビルドエラー0件を確認
  完了条件: Debug|x64 / Release|x64 の両構成でビルドが通る。テストプロジェクトが Test Explorer に表示される
  レビュー観点: MFC / WinRT ヘッダ順序、/EHsc の明示指定

[Task 2] WindowsNotificationManager コア実装（Init / Show / OnNotificationInvoked）
  依存: Task 1
  工数: 1日
  作業:
    - WindowsNotificationManager.h 作成（エラー定数・コールバック型・Bridge C API 宣言）
    - WindowsNotificationManager.cpp 作成（シングルトン・Init・Uninit）
    - BuildFromJson() とサブビルダー（ApplyButtons / ApplyComboBoxes / ApplyImages / ApplyAudio / ApplyProgress）実装
    - バリデーション（ボタン数・音声ループ制約・引数排他）実装
    - Show() 実装（Setting チェック → BuildFromJson → SetExpiration → Show）
    - OnNotificationInvoked() 実装（Arguments + UserInput を JSON 化、コールバック呼び出し）
    - ArgsToJson() 実装（WinRT JSON API でエスケープ安全に生成）
    - 全メソッドに DFLog 追加
    - Doxygen コメント付与
    - vcxproj に .h/.cpp を追加
  完了条件: T-01〜T-05 / T-20〜T-24 / T-25〜T-26 が手動確認で通る
  レビュー観点: JSON ペイロード仕様の網羅性、エラーコード返却の一貫性、UserInput マージ

[Task 3] スケジュール / 進捗 / バッジ / 削除 / 一覧取得実装
  依存: Task 2
  工数: 1日
  作業:
    - Schedule() / CancelScheduled() 実装
    - UpdateProgress() 実装（非同期ブロッキング変換）
    - SetBadge() 実装（数値・グリフ・クリア・不正値バリデーション）
    - RemoveById / RemoveByTag / RemoveAll 実装
    - GetAll() 実装（WinRT JSON API で配列生成）
  完了条件: T-06〜T-12 / T-27〜T-29 が手動確認で通る
  レビュー観点: AppNotificationProgressResult の判定漏れなし、非同期のブロッキング安全性

[Task 4] 未パッケージ対応 / GetSetting 実装
  依存: Task 2
  工数: 0.5日
  作業:
    - 未パッケージ初期化分岐の実装と COM サーバー登録の動作確認
    - GetSetting() Bridge 関数実装
  完了条件: T-18 / T-19 が手動確認で通る
  レビュー観点: COM サーバー登録の実行確認、GetSetting の返却値がエラーコードと衝突しないこと

[Task 5] 統合確認・ドキュメント整備
  依存: Task 1〜4
  工数: 0.5日
  作業:
    - 全テスト項目（T-01〜T-29）の手動確認
    - 管理者権限実行でのサイレント失敗確認（T-17）
    - WindowsLibrary.def の export 漏れがないことを最終確認
  完了条件: 全テスト項目が確認済みになる
  レビュー観点: .def ファイルの輸出漏れなし
```

**合計工数: 3.5日**

**タスク依存関係:**
```
Task 1 → Task 2 → Task 3 → Task 5
                → Task 4 → Task 5
```

---

## リスクと緩和策

| リスク | 深刻度 | 緩和策 |
|-------|-------|-------|
| MFC + WinRT ヘッダ競合でビルドエラー | 高 | pch.h のインクルード順序（MFC → WinRT）を厳守。`/EHsc` 明示 |
| 管理者権限実行でサイレント失敗 | 高 | `Init()` 時に `Setting()` ログ出力。Bridge 呼び出し元に警告通知を検討 |
| 未パッケージアプリでの COM サーバー未登録 | 中 | Task 4 で COM 登録の動作確認を必須とする。登録失敗時は `NOTIFICATION_ERROR_HRESULT_FAILURE` を返す |
| テキスト入力 reply の取得漏れ | 中 | `UserInput()` を `Arguments()` と別途取得し ArgsToJson でマージ（設計に明記済み） |
| `co_await` ブロッキング変換のデッドロック | 中 | Unity 呼び出しは非 UI スレッドのため問題なし。UI スレッドからの呼び出しは禁止とする |
| JSON エスケープ不備によるパース失敗 | 中 | ArgsToJson では WinRT JSON API（JsonValue::CreateStringValue）を使用し手組み文字列連結を禁止 |
| スケジュール通知5分デリバリーウィンドウ超過 | 低 | Schedule() 内でログ警告を出力。UI 側での使用ガイドラインに記載 |
| NuGet パッケージの x86/x64 混在 | 低 | `Microsoft.Windows.AppSDK` は x64 対応を確認してから採用（Task 1 で確認） |
| マニフェスト設定不備（CLSID 未設定） | 低 | Task 5 のテスト T-01 でマニフェストなし環境を検出 |

---

## Definition of Done

- [ ] `initNotificationManager()` の Init/Uninit が正常に動作する
- [ ] `showNotification()` でテキスト / 画像 / ボタン / コンボボックス / テキスト入力 / 進捗バーの Toast が表示できる
- [ ] `showNotification()` の有効期限（expiration / expiresOnReboot）が機能する
- [ ] `scheduleNotification()` で指定時刻の通知が届く
- [ ] `cancelScheduledNotification()` でスケジュール通知がキャンセルされる
- [ ] Reminder/Alarm シナリオでボタン方式のスヌーズが動作する
- [ ] `updateNotificationProgress()` で通知の進捗値が更新される（`AppNotificationProgressResult` を確認）
- [ ] `setBadge()` でタスクバーのバッジが数値・グリフ・クリアで動作する
- [ ] `removeNotificationsByTag()` / `removeAllNotifications()` が動作する
- [ ] `getAllNotifications()` が通知一覧を outJson に返す
- [ ] `getNotificationSetting()` が `AppNotificationSetting` の値を返す（エラーコードとの衝突なし）
- [ ] `NotificationInvokedCallback` が通知クリック時に JSON argsJson で呼び出される
- [ ] argsJson にテキスト入力（reply）・コンボボックス選択値が含まれる
- [ ] 未パッケージアプリ（`isPackaged=FALSE`）での初期化が動作する（要検証: COM 登録環境依存）
- [ ] 管理者権限実行時にサイレント失敗し、ログに警告が出力される
- [ ] `pError` に適切なエラーコードが返される（全エラーケース 1〜7）
- [ ] 全メソッドに DFLog が付与されている
- [ ] 公開 API に Doxygen コメントが付与されている
- [ ] ビルドが Debug|x64 / Release|x64 の両構成で成功する
- [ ] `WindowsLibrary.def` に全 export 関数が記載されている
