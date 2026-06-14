# Windows Notification サンプルアプリ実装計画

## 基本情報

- 作成日: 2026-05-31
- 対象OS: Windows（最小: Windows 11）
- 対象機能: Notification
- 設計書: `artifact/designs/notification/2026-05-30-windows-notification-design-v2.md`
- 実装結果: `artifact/results/notification/2026-05-30-windows-notification-implement-feature-result-v1.md`
- 対象サンプルアプリ: `windows/WindowsLibraryExample`（WinUI 3 / C++/WinRT デスクトップアプリ）

---

## 1. 前提情報（設計書・実装結果由来）

### 1.1 対象 Bridge API（C 関数、`WindowsNotificationManager.h`）

| 関数 | 役割 |
|------|------|
| `initNotificationManager(callback, isPackaged, clsid, launchUri, pError)` | 初期化・コールバック登録 |
| `uninitNotificationManager()` | 終了 |
| `showNotification(jsonPayload, pError)` | Toast 表示 |
| `scheduleNotification(jsonPayload, scheduledTimeUnixMs, pError)` | スケジュール通知 |
| `cancelScheduledNotification(tag, group, pError)` | スケジュールキャンセル |
| `updateNotificationProgress(tag, group, value, valueStr, status, seq, pError)` | 進捗更新 |
| `setBadge(value, pError)` | バッジ（正=数値 / 負=グリフ / 0=クリア） |
| `removeNotificationById(id, pError)` | ID 指定削除 |
| `removeNotificationsByTag(tag, group, pError)` | タグ/グループ削除 |
| `removeAllNotifications(pError)` | 全削除 |
| `getAllNotifications(outJson, bufferSize, pError)` | 一覧取得（JSON 文字列） |
| `getNotificationSetting()` | 設定状態（0〜4、pError なし） |
| `NotificationInvokedCallback(const wchar_t* argsJson)` | クリック/アクション時に呼ばれる関数ポインタ |

### 1.2 エラー契約

- 成功時 `pError == 0`（`NOTIFICATION_SUCCESS`）。
- 失敗時 `1〜7`：`NOT_INITIALIZED(1)` / `DISABLED(2)` / `INVALID_PAYLOAD(3)` / `PROGRESS_NOT_FOUND(4)` / `HRESULT_FAILURE(5)` / `BADGE_FAILED(6)` / `INVALID_PARAMETER(7)`。
- `getNotificationSetting()` のみ返却値（0〜4）がエラーコード体系と独立。

### 1.3 JSON ペイロード仕様（`showNotification` / `scheduleNotification`）

`title` / `body` / `tag` / `group` / `scenario` / `duration` / `expiration` / `expiresOnReboot` / `attribution` / `appLogo` / `heroImage` / `inlineImage` / `buttons[]` / `textBoxes[]` / `comboBoxes[]` / `progress` / `audio`。
画像は `ms-appx:///` または `ms-appdata:///` URI。バリデーション: ボタン最大5 / `audio.loop` は `duration:"long"` 必須 / ボタンの `args` と `invokeUri` 排他 / `audio.type:"uri"` は `uri` 必須 / `setBadge value < -6` 不正。

### 1.4 不足前提（設計書に明示がない事項 — 要検証）

- サンプルアプリは **パッケージ済み（MSIX）アプリ**（`AppxPackage=true`）。`initNotificationManager(callback, TRUE, nullptr, nullptr, &err)` の **パッケージ済みパス**を使用する（未パッケージ COM 登録は対象外）。
- コールバックからの UI 更新は `DispatcherQueue` でメインスレッドへマーシャリングする（WinUI 3 のスレッド契約）。

---

## 2. 既存サンプルコードの深掘り

### 2.1 現状（`windows/WindowsLibraryExample`）

- **フラットな単一ウィンドウ**構成。`MainWindow.xaml` に DialogManager 用のボタン群（`ShowAlertDialog` ほか）と結果表示 `ResultTextBlock`、ヘルパー `SetResultText(const std::wstring&)`。
- ボタンスタイル `DialogButtonStyle`（`App.xaml` 定義）を共通利用。
- iOS/Android のような「メインメニュー → サンプル画面」の導線は**未導入**。

### 2.2 参照パターン（**macOS 構成を参照** — `MacLibraryExample`）

UI 構成は **macOS サンプル（`MacLibraryExample`）を参照**する（デスクトップアプリで Windows に最も近い）。

- `ContentView.swift`（メインメニュー）: `NavigationStack` + `ScrollView` 内に **メニューカード**（`menuCard(title, subtitle)`）を並べ、`NavigationLink` で `DialogSampleView` / `NotificationSampleView` へ遷移。`navigationTitle("Main Menu")`。
  - メニューカード = タイトル（headline）+ サブタイトル（説明）をカード（背景 + 角丸）で表示。
- `NotificationSampleView.swift`（サンプル画面）: タイトル + 結果表示（✅/❌）+ `ScrollView` 内に**機能カテゴリ別セクション**（Show / Schedule / Badge / …）。
- ヘルパー: `updateResult(isSuccess, result)`（`[methodName] ... error: ...` 形式）。

### 2.3 差分方針（先に確定 — macOS 構成準拠）

- macOS と同じ **メインメニュー（メニューカード）→ サンプル画面** の導線を Windows に導入する。`NavigationView`（サイドペイン）ではなく、**`Frame` によるページ遷移 + メニューカード**で macOS の `NavigationStack` 体験に揃える。
  - `MainWindow` は **`Frame` をホスト**し、初期ページに **`MainMenuPage`** を表示。
  - `MainMenuPage`: タイトル `Native Toolkit Windows Example` + **メニューカード**（`Dialog Example` / `Notification Example`）→ `Frame.Navigate` で各ページへ。各ページに戻る導線（Back ボタン or `Frame.GoBack`）。
  - 既存 Dialog サンプルは **`DialogPage`** へ移設（ボタン・ハンドラ・`SetResultText` をそのまま移動。機能は無変更）。
  - 新規 **`NotificationPage`** に通知サンプルを実装。
- メニューカードは WinUI の `Button`（カードスタイル）または `Grid`+`Border` で表現（macOS `menuCard` 相当）。
- 既存の結果表示パターン（`ResultTextBlock` + ✅/❌）と `DialogButtonStyle` を**再利用/踏襲**する。

---

## 3. 画面要件（NotificationPage）

### 3.1 機能一覧（セクション構成）

| セクション | ボタン（操作） |
|-----------|--------------|
| Init / Setting | `InitializeManager` / `Uninitialize` / `GetSetting` |
| Show | `ShowBasic` / `ShowWithButtons` / `ShowWithImage` / `ShowWithInput`(textBox+comboBox) / `ShowWithProgress` / `ShowWithExpiration(10s)` / `ShowWithAudio(reminder)` |
| Schedule | `Schedule(+1m)` / `CancelScheduled(tag)` |
| Progress | `UpdateProgress(0.6)` |
| Badge | `SetBadge(5)` / `SetBadgeGlyph(alert)` / `ClearBadge` |
| Remove / Query | `RemoveByTag` / `RemoveAll` / `GetAllNotifications` |

### 3.2 操作導線

- ページ先頭にタイトル `WindowsNotificationManager Example` と結果表示 `ResultTextBlock`。
- 各ボタン押下 → JSON ペイロード生成 → Bridge 関数呼び出し → `pError` 判定 → 結果表示更新。
- 通知クリック/アクション → 登録済みコールバック → `DispatcherQueue` で結果表示に `argsJson` を反映。

### 3.3 エラー表示

- `pError == 0` を成功（✅）、`1〜7` を失敗（❌）とし、`[method] errorCode=<n>` を表示。
- `GetSetting` は返却値を `Enabled/Disabled/...` のラベルで表示（エラーコードと分離）。

### 3.4 ログ表示

- 各操作で `OutputDebugString` 相当のログ（`DLog`/`DFLog` は WindowsLibrary 内。サンプル側は WinRT/標準ログで可）を残し、再現手順を追えるようにする。

---

## 4. 変更ファイル一覧

### 4.1 新規作成

- `windows/WindowsLibraryExample/MainMenuPage.xaml` / `.xaml.h` / `.xaml.cpp` / `MainMenuPage.idl` — メニューカード（Dialog / Notification）+ `Frame.Navigate`
- `windows/WindowsLibraryExample/NotificationPage.xaml` / `.xaml.h` / `.xaml.cpp` / `NotificationPage.idl`
- `windows/WindowsLibraryExample/DialogPage.xaml` / `.xaml.h` / `.xaml.cpp` / `DialogPage.idl`

### 4.2 既存変更

- `MainWindow.xaml` / `.xaml.h` / `.xaml.cpp` / `MainWindow.idl` — `Frame` をホストし初期ページに `MainMenuPage` を表示（macOS `NavigationStack` 相当）。既存 Dialog ボタン群は `DialogPage` へ移設。
- `App.xaml.cpp` — 起動時に通知コールバックの受け皿（静的関数 + UI 反映用の弱参照/イベント）を用意（必要に応じて）。
- `WindowsLibraryExample.vcxproj`（+`.filters`） — 新規ページの登録（VS が自動追加。手動整備が必要なら追記）。
- `App.xaml` — 通知用ボタンスタイルが必要なら `DialogButtonStyle` を汎用名へ拡張、または流用。

### 4.3 非変更

- `WindowsLibrary`（ライブラリ本体）・Bridge API は無変更（サンプルからの利用のみ）。
- `pch.h` 等のビルド構成は原則無変更（`WindowsNotificationManager.h` のインクルード追加のみ）。

---

## 5. 実装方針

### 5.1 再利用する既存コンポーネント

- 結果表示パターン（`ResultTextBlock` + `SetResultText` + ✅/❌）。
- `DialogButtonStyle`（フル幅ボタン）。
- WinUI 3 / C++/WinRT のページ・コードビハインド構成（`MainWindow` の既存実装に倣う）。

### 5.2 追加するコンポーネント

- `MainWindow` の `Frame` ホスト + `MainMenuPage`（メニューカード）による画面遷移（macOS `NavigationStack` + `menuCard` 相当）。
- `DialogPage`（既存 Dialog の受け皿）/ `NotificationPage`（新規）。各ページに戻る導線（`Frame.GoBack`）。
- 通知サンプル用ヘルパー（`NotificationPage` 内）:
  - `ShowResult(method, err)` — `pError` を ✅/❌ 付きで結果表示へ反映。
  - `BuildPayload(...)` 系 — 各デモの JSON ペイロード文字列を組み立てる（`winrt::Windows::Data::Json` または手組み文字列）。
  - `EnsureInitialized()` — 未初期化なら警告表示（iOS の `requirePermission` 相当の前提チェック）。
  - コールバック → `DispatcherQueue().TryEnqueue([...]{ ... })` で UI 反映。

### 5.3 共通実装パターンの維持/拡張

- 維持: タイトル+結果表示、機能カテゴリ別ボタン群、成功/失敗の一目判別、メインスレッド反映。
- 拡張: Windows へ「メインメニュー（メニューカード）→ サンプル画面」導線を新規導入（**macOS `MacLibraryExample` 構成に整合**）。

---

## 6. 実装詳細（implement-sample-app ステップ3 で行う内容）

### 6.1 各セクションの UI 要素と API 呼び出し方針

- **InitializeManager**: `initNotificationManager(&OnInvoked, TRUE, nullptr, nullptr, &err)`。成功で「initialized」、`GetSetting` 併記。
- **GetSetting**: `getNotificationSetting()` の戻り値を `Enabled/Disabled/NotSupported/...` ラベル化。
- **ShowBasic**: `{ "title":"Hello", "body":"Basic toast", "tag":"sample" }`。
- **ShowWithButtons**: `buttons:[{label:"Open",args:{action:"open"}},{label:"Dismiss",args:{action:"dismiss"}}]`（最大5検証）。
- **ShowWithImage**: `heroImage`/`inlineImage` に `ms-appx:///Assets/...png`（サンプル同梱画像を使用）。
- **ShowWithInput**: `textBoxes:[{id:"reply",placeholder:"Type..."}]` + `comboBoxes:[{id:"opt",items:[...],defaultSelection:...}]`。コールバックで `argsJson` に入力値が入ることを確認。
- **ShowWithProgress**: `progress:{title,value:0.3,valueStr:"30%",status:"Downloading"}` + `tag:"progress-sample"`。
- **ShowWithExpiration**: `expiration:10`（10秒で消える）。
- **ShowWithAudio**: `audio:{type:"event",event:"reminder"}`。
- **Schedule(+1m)**: 現在時刻 +60秒の Unix ミリ秒を計算し `scheduleNotification(payload, ms, &err)`（`tag:"scheduled"`）。5分超は OS が破棄する旨を注記。
- **CancelScheduled**: `cancelScheduledNotification(L"scheduled", L"", &err)`。
- **UpdateProgress**: `updateNotificationProgress(L"progress-sample", L"", 0.6, L"60%", L"Downloading", seq++, &err)`（事前に ShowWithProgress 必要 → `PROGRESS_NOT_FOUND(4)` 検証）。
- **SetBadge(5) / Glyph / Clear**: `setBadge(5,&err)` / `setBadge(-1,&err)`（alert グリフ）/ `setBadge(0,&err)`。`value<-6` で `INVALID_PARAMETER(7)` を確認するデモも追加可。
- **RemoveByTag / RemoveAll / GetAll**: `removeNotificationsByTag` / `removeAllNotifications` / `getAllNotifications(buf, size, &err)`（バッファは固定長 `wchar_t[4096]` 等、境界チェック）。

### 6.2 コールバック処理

- 静的関数 `static void OnNotificationInvoked(const wchar_t* argsJson)` を `initNotificationManager` に渡す。
- C 関数ポインタからインスタンス UI へは、静的なイベント/弱参照経由で `NotificationPage` の `DispatcherQueue` に積み、結果表示へ `argsJson` を表示（reply/combo 選択値の確認）。

### 6.3 入力バリデーション方針

- サンプルはハードコードのデモ JSON を使うため UI 入力バリデーションは最小。
- ライブラリ側バリデーション（ボタン数超過・audio ループ・badge 範囲）を**意図的に踏むデモボタン**を任意で用意し、`INVALID_PARAMETER(7)` 返却を確認できるようにする（手動確認観点に対応）。

---

## 7. 手動確認観点

- `InitializeManager` 後に各 Show 系で Toast がアクションセンターに表示される。
- ボタン付き通知のボタン押下で `argsJson`（`action` 値）が結果表示に反映される。
- 入力付き通知（textBox/comboBox）で入力/選択値が `argsJson` に含まれる。
- 画像付き通知で `ms-appx:///Assets` 画像が表示される。
- 進捗通知表示 → `UpdateProgress` で進捗が更新される。未表示タグへの更新で `PROGRESS_NOT_FOUND(4)`。
- `Schedule(+1m)` で約1分後に通知が届く。`CancelScheduled` で届かなくなる。
- `SetBadge(5)` でタスクバー/タイルにバッジ、`ClearBadge` で消える。
- `RemoveByTag` / `RemoveAll` で表示中通知が消える。`GetAllNotifications` が JSON 一覧を返す。
- 通知無効時（OS 設定で当該アプリの通知 OFF）に Show が `DISABLED(2)` を返す。
- 不正ペイロード/不正パラメータで `INVALID_PAYLOAD(3)` / `INVALID_PARAMETER(7)` を返す。
- アプリ起動時に WinRT 例外（`RPC_E_CHANGED_MODE`）が出ず正常起動する（ライブラリ側修正済みの回帰確認）。

---

## 8. 実装計画の確認（ステップ8）

- 提示文: 「この実装計画で進めますか？」
- 選択肢:
  - 承認する: 計画を確定、次のレビュー workflow（review-document）へ進む
  - 修正する: 指摘内容を反映して計画ファイルを更新
  - キャンセル: 計画ファイルは保持したまま終了
