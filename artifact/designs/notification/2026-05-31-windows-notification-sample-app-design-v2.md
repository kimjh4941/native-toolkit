# Windows Notification サンプルアプリ実装計画

## 基本情報

- 作成日: 2026-05-31
- 改訂日: 2026-05-31（v2 — レビュー反映）
- 対象OS: Windows（最小: Windows 11 を想定。実プロジェクト設定との整合は 1.4 / 4.2 参照）
- 対象機能: Notification
- 設計書: `artifact/designs/notification/2026-05-30-windows-notification-design-v2.md`
- 実装結果: `artifact/results/notification/2026-05-30-windows-notification-implement-feature-result-v1.md`
- 対象サンプルアプリ: `windows/WindowsLibraryExample`（WinUI 3 / C++/WinRT デスクトップアプリ）

> **v1 からの主な変更点（レビュー反映）**
> - `removeNotificationById(id)` を UI セクション・実装詳細・手動確認に追加（公開API 12関数を全カバー）
> - Package.appxmanifest の toast activation（COM/ToastActivatorCLSID）拡張の要否を要検証として追加し、変更ファイル一覧へ計上
> - 最小 Windows 11 方針と実 appxmanifest `MinVersion`(10.0.17763.0) の不一致を明記し整合方針を追加
> - 手動確認に `getNotificationSetting` の -1、`getAllNotifications` のバッファ境界、`HRESULT_FAILURE(5)` / `BADGE_FAILED(6)` を追加
> - コールバック橋渡しの所有者・購読/解除ライフサイクル・ページ非表示時の取り扱いを確定（「必要に応じて」を解消）
> - 各ページの `.idl` 要否の判断基準と vcxproj 登録項目を明記
> - 通知用画像アセット（Assets）の新規追加を変更ファイル一覧へ計上

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
| `getAllNotifications(outJson, bufferSize, pError)` | 一覧取得（JSON 文字列。各要素に `id`/`tag`/`group`） |
| `getNotificationSetting()` | 設定状態（0〜4、pError なし。WinRT 例外時は -1） |
| `NotificationInvokedCallback(const wchar_t* argsJson)` | クリック/アクション時に呼ばれる関数ポインタ |

### 1.2 エラー契約

- 成功時 `pError == 0`（`NOTIFICATION_SUCCESS`）。
- 失敗時 `1〜7`：`NOT_INITIALIZED(1)` / `DISABLED(2)` / `INVALID_PAYLOAD(3)` / `PROGRESS_NOT_FOUND(4)` / `HRESULT_FAILURE(5)` / `BADGE_FAILED(6)` / `INVALID_PARAMETER(7)`。
- `getNotificationSetting()` のみ返却値が独立体系：`0〜4`（設定状態）、WinRT 例外時 `-1`。

### 1.3 JSON ペイロード仕様（`showNotification` / `scheduleNotification`）

`title` / `body` / `tag` / `group` / `scenario` / `duration` / `expiration` / `expiresOnReboot` / `attribution` / `appLogo` / `heroImage` / `inlineImage` / `buttons[]` / `textBoxes[]` / `comboBoxes[]` / `progress` / `audio`。
画像は `ms-appx:///` または `ms-appdata:///` URI。バリデーション: ボタン最大5 / `audio.loop` は `duration:"long"` 必須 / ボタンの `args` と `invokeUri` 排他 / `audio.type:"uri"` は `uri` 必須 / `setBadge value < -6` 不正。

### 1.4 不足前提・要検証（設計書に明示がない事項）

- サンプルアプリは **パッケージ済み（MSIX）アプリ**（`AppxPackage=true`）。`initNotificationManager(callback, TRUE, nullptr, nullptr, &err)` の **パッケージ済みパス**を使用する（未パッケージ COM 登録は対象外）。
- **【要検証 / high】toast activation 拡張の要否**: パッケージ済みでもアプリ未起動状態でのアクション受信（設計書 T-21: COM アクティベーション起動）でコールバックを受けるには、`Package.appxmanifest` に `windows.toastNotificationActivation`（`ToastActivatorCLSID`）拡張の登録が必要となる可能性が高い。実機の `Package.appxmanifest` には当該拡張が未登録。実装着手時に「パッケージ済み + AppNotificationManager の `Register()` のみでアクティベーションコールバックが届くか」を最優先で検証し、必要なら拡張を追加する。
  - アプリ起動中のフォアグラウンドコールバックは `NotificationInvoked` イベントで受けられる見込み（拡張は未起動時アクティベーション用）。
- **【要検証 / medium】最小OSと実 MinVersion の整合**: 計画は最小 Windows 11 を想定するが、実 `Package.appxmanifest` の `TargetDeviceFamily MinVersion` は `10.0.17763.0`（Windows 10 1809）。最小 Windows 11 を担保するなら `MinVersion` 引き上げ要否を判断し、引き上げない場合は「サンプルは Windows 10 でも起動するが通知 API は Windows 11 を前提」と注記する。
- コールバックからの UI 更新は `DispatcherQueue` でメインスレッドへマーシャリングする（WinUI 3 のスレッド契約）。

---

## 2. 既存サンプルコードの深掘り

### 2.1 現状（`windows/WindowsLibraryExample`）

- **フラットな単一ウィンドウ**構成。`MainWindow.xaml` に DialogManager 用のボタン群（`ShowAlertDialog` ほか）と結果表示 `ResultTextBlock`、ヘルパー `SetResultText(const std::wstring&)`。
- ボタンスタイル `DialogButtonStyle`（`App.xaml` 定義）を共通利用。
- 「メインメニュー → サンプル画面」の導線は**未導入**。
- `MainWindow.idl` は最小（`MyProperty` のみ）。`Package.appxmanifest` の `MinVersion` は `10.0.17763.0`、toast activation 拡張は未登録。

### 2.2 参照パターン（**macOS 構成を参照** — `MacLibraryExample`）

UI 構成は **macOS サンプル（`MacLibraryExample`）を参照**する（デスクトップアプリで Windows に最も近い）。

- `ContentView.swift`（メインメニュー）: `NavigationStack` + `ScrollView` 内に **メニューカード**（`menuCard(title, subtitle)`）を並べ、`NavigationLink` で `DialogSampleView` / `NotificationSampleView` へ遷移。`navigationTitle("Main Menu")`。
  - メニューカード = タイトル（headline）+ サブタイトル（説明）をカード（背景 + 角丸）で表示。
- `NotificationSampleView.swift`（サンプル画面）: タイトル + 結果表示（✅/❌）+ `ScrollView` 内に**機能カテゴリ別セクション**（Show / Schedule / Badge / …）。
- ヘルパー: `updateResult(isSuccess, result)`（`[methodName] ... error: ...` 形式）。

### 2.3 差分方針（先に確定 — macOS 構成準拠）

- macOS と同じ **メインメニュー（メニューカード）→ サンプル画面** の導線を Windows に導入する。`NavigationView`（サイドペイン）ではなく、**`Frame` によるページ遷移 + メニューカード**で macOS の `NavigationStack` 体験に揃える。
  - `MainWindow` は **`Frame` をホスト**し、初期ページに **`MainMenuPage`** を表示。
  - `MainMenuPage`: タイトル `Native Toolkit Windows Example` + **メニューカード**（`Dialog Example` / `Notification Example`）→ `Frame.Navigate` で各ページへ。`MainMenuPage` はルートのため戻る導線なし。
  - **戻る導線（メインメニューへ戻る）**: 各サンプルページ（`DialogPage` / `NotificationPage`）の先頭に `Back` ボタン（`←` / Content="Back"）を配置し、`Click` で `Frame().CanGoBack()` を確認のうえ `Frame().GoBack()` を呼ぶ。macOS `NavigationStack` の自動戻るボタンに相当する体験を WinUI では明示的な Back ボタンで再現する。
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
| Remove / Query | `GetAllNotifications` / `RemoveById`（GetAll の id を流用） / `RemoveByTag` / `RemoveAll` |

### 3.2 操作導線

- ページ先頭に **`Back` ボタン**（`Frame().GoBack()` でメインメニューへ戻る）、タイトル `WindowsNotificationManager Example`、結果表示 `ResultTextBlock` を配置。
- 各ボタン押下 → JSON ペイロード生成 → Bridge 関数呼び出し → `pError` 判定 → 結果表示更新。
- `GetAllNotifications` で取得した一覧（`id` 群）を結果表示し、直近の `id` を `RemoveById` のデモに流用する（保持した最後の id を使う／一覧先頭を使う）。
- 通知クリック/アクション → 登録済みコールバック → `DispatcherQueue` で結果表示に `argsJson` を反映。

### 3.3 エラー表示

- `pError == 0` を成功（✅）、`1〜7` を失敗（❌）とし、`[method] errorCode=<n>` を表示。
- `GetSetting` は返却値を `Enabled/Disabled/...` のラベルで表示（`-1` は `Error(-1)` 表示。エラーコード体系とは分離）。

### 3.4 ログ表示

- 各操作で **`DLog` / `DFLog` を使用**してログを残し、再現手順を追えるようにする。これらは `WindowsLibrary` が `common.h`（`COMMON_API` で `__declspec(dllexport)`）として公開しており、サンプルは `common.h` をインクルードして直接呼び出せる（import lib 経由でリンク）。サンプル独自の標準/ WinRT ログは使わず、ライブラリと同じ `DLog`/`DFLog` に統一する。
- 各操作・コールバックの先頭で `DFLog(TAG, L"[<method>] ...")` を出し、TAG は `static const wchar_t* TAG = L"NotificationPage";` 等を用いる（windows.md のログ規約に準拠）。

---

## 4. 変更ファイル一覧

### 4.1 新規作成

- `windows/WindowsLibraryExample/MainMenuPage.xaml` / `.xaml.h` / `.xaml.cpp`（+ 必要なら `MainMenuPage.idl`）— メニューカード（Dialog / Notification）+ `Frame.Navigate`
- `windows/WindowsLibraryExample/NotificationPage.xaml` / `.xaml.h` / `.xaml.cpp`（+ 必要なら `NotificationPage.idl`）
- `windows/WindowsLibraryExample/DialogPage.xaml` / `.xaml.h` / `.xaml.cpp`（+ 必要なら `DialogPage.idl`）
- `windows/WindowsLibraryExample/Assets/` — 通知用画像（`heroImage`/`inlineImage`/`appLogo` 用）。既存 `Assets`（StoreLogo 等）の流用で済むなら新規追加は不要（着手時に判断）。

> **`.idl` 要否の判断基準**: ナビゲーション専用ページ（外部から `x:Bind` / runtimeclass として参照しない）は `.idl` なし（コードビハインド直結、`x:Class` のみ）で実装可。`Frame.Navigate(xaml_typename<...>())` の型解決にはコードビハインド型で足りる。`.idl` を付ける場合のみ `<Midl>` 登録 + runtimeclass 宣言 + Generated Files 連携が必要になるため、**原則 `.idl` なしで実装**し、必要が生じた場合のみ追加する。

### 4.2 既存変更

- `MainWindow.xaml` / `.xaml.h` / `.xaml.cpp` / `MainWindow.idl` — `Frame` をホストし初期ページに `MainMenuPage` を表示（macOS `NavigationStack` 相当）。既存 Dialog ボタン群は `DialogPage` へ移設。
- `App.xaml.cpp` — 通知コールバックの受け皿を実装（5.2 / 6.2 で確定したライフサイクルに従う）。
- `Package.appxmanifest` —【要検証】toast activation（`Extensions` > `com.windows.toast`/`windows.toastNotificationActivation` + `ToastActivatorCLSID`）登録の要否。最小 Windows 11 を担保する場合は `MinVersion` 引き上げの要否も併せて判断。
- `WindowsLibraryExample.vcxproj`（+`.filters`） — 新規ページの `<Page>`（XAML）・`<ClInclude>`/`<ClCompile>`・`DependentUpon` を登録（`.idl` 採用時は `<Midl>` も）。VS の追加で自動整備されるが、CLI ビルド整合のため最終的に手動確認する。
- `App.xaml` — 通知用ボタンスタイルが必要なら `DialogButtonStyle` を汎用名（例: `SampleButtonStyle`）へ拡張、または流用。

### 4.3 非変更

- `WindowsLibrary`（ライブラリ本体）・Bridge API は無変更（サンプルからの利用のみ）。
- `pch.h` 等のビルド構成は原則無変更（`WindowsNotificationManager.h` と `common.h`（`DLog`/`DFLog` 用）のインクルード追加のみ）。

---

## 5. 実装方針

### 5.1 再利用する既存コンポーネント

- 結果表示パターン（`ResultTextBlock` + `SetResultText` + ✅/❌）。
- `DialogButtonStyle`（フル幅ボタン）。
- WinUI 3 / C++/WinRT のページ・コードビハインド構成（`MainWindow` の既存実装に倣う）。
- **`WindowsLibrary` が公開するログ関数 `DLog` / `DFLog`**（`common.h`）をサンプルでもそのまま使用する。

### 5.2 追加するコンポーネント

- `MainWindow` の `Frame` ホスト + `MainMenuPage`（メニューカード）による画面遷移（macOS `NavigationStack` + `menuCard` 相当）。
- `DialogPage`（既存 Dialog の受け皿）/ `NotificationPage`（新規）。各ページ先頭の `Back` ボタンで `Frame().GoBack()`（メインメニューへ戻る）。
- 通知サンプル用ヘルパー（`NotificationPage` 内）:
  - `ShowResult(method, err)` — `pError` を ✅/❌ 付きで結果表示へ反映。
  - `BuildPayload(...)` 系 — 各デモの JSON ペイロード文字列を組み立てる（`winrt::Windows::Data::Json` または手組み文字列）。
  - `EnsureInitialized()` — 未初期化なら警告表示（前提チェック）。
- **コールバック橋渡しの所有とライフサイクル（確定）**:
  - 受け皿は **`App`（アプリ単一）が所有**する静的な転送ハブとする（`std::function<void(std::wstring)>` を1つ保持）。`initNotificationManager` には `App` の静的関数 `static void OnNotificationInvoked(const wchar_t*)` を渡す。
  - `NotificationPage` は `OnNavigatedTo` で自身のハンドラをハブに登録し、`OnNavigatedFrom` で登録解除（弱参照 or トークン解除）する。
  - ページ非表示中に来た `argsJson` は **破棄**（サンプル用途。保留は行わない）。null 安全のため、ハンドラ未登録時は no-op。
  - ハブ → ページのハンドラは `DispatcherQueue().TryEnqueue([...]{ SetResultText(...) })` で UI スレッドへマーシャリング。

### 5.3 共通実装パターンの維持/拡張

- 維持: タイトル+結果表示、機能カテゴリ別ボタン群、成功/失敗の一目判別、メインスレッド反映。
- 拡張: Windows へ「メインメニュー（メニューカード）→ サンプル画面」導線を新規導入（**macOS `MacLibraryExample` 構成に整合**）。

---

## 6. 実装詳細（implement-sample-app ステップ3 で行う内容）

### 6.1 各セクションの UI 要素と API 呼び出し方針

- **InitializeManager**: `initNotificationManager(&App::OnNotificationInvoked, TRUE, nullptr, nullptr, &err)`。成功で「initialized」、`GetSetting` 併記。
- **GetSetting**: `getNotificationSetting()` の戻り値を `Enabled/Disabled/NotSupported/...`（`-1` は `Error`）ラベル化。
- **ShowBasic**: `{ "title":"Hello", "body":"Basic toast", "tag":"sample" }`。
- **ShowWithButtons**: `buttons:[{label:"Open",args:{action:"open"}},{label:"Dismiss",args:{action:"dismiss"}}]`。
- **ShowWithImage**: `heroImage`/`inlineImage` に `ms-appx:///Assets/...png`（4.1 で確定する同梱画像）。
- **ShowWithInput**: `textBoxes:[{id:"reply",placeholder:"Type..."}]` + `comboBoxes:[{id:"opt",items:[...],defaultSelection:...}]`。コールバックで `argsJson` に入力値が入ることを確認。
- **ShowWithProgress**: `progress:{title,value:0.3,valueStr:"30%",status:"Downloading"}` + `tag:"progress-sample"`。
- **ShowWithExpiration**: `expiration:10`（10秒で消える）。
- **ShowWithAudio**: `audio:{type:"event",event:"reminder"}`。
- **Schedule(+1m)**: 現在時刻 +60秒の Unix ミリ秒を計算し `scheduleNotification(payload, ms, &err)`（`tag:"scheduled"`）。5分超は OS が破棄する旨を注記。
- **CancelScheduled**: `cancelScheduledNotification(L"scheduled", L"", &err)`。
- **UpdateProgress**: `updateNotificationProgress(L"progress-sample", L"", 0.6, L"60%", L"Downloading", seq++, &err)`（事前に ShowWithProgress 必要 → 未表示なら `PROGRESS_NOT_FOUND(4)`）。
- **SetBadge(5) / Glyph / Clear**: `setBadge(5,&err)` / `setBadge(-1,&err)`（alert グリフ）/ `setBadge(0,&err)`。
- **GetAllNotifications**: `getAllNotifications(buf, size, &err)`（固定長 `wchar_t buf[4096]`、`bufferSize` 渡しで境界チェック）。返却 JSON をパースし `id` 群を結果表示。直近 `id` を保持。
- **RemoveById**: 保持した直近 `id`（なければ `GetAll` の先頭）で `removeNotificationById(id, &err)`。id 未取得時は警告表示。
- **RemoveByTag / RemoveAll**: `removeNotificationsByTag(L"sample", L"", &err)` / `removeAllNotifications(&err)`。

### 6.2 コールバック処理

- `App::OnNotificationInvoked(const wchar_t* argsJson)`（静的）が、`App` 所有の転送ハブ（`std::function`）へ委譲。
- `NotificationPage` は `OnNavigatedTo` でハブにハンドラ登録、`OnNavigatedFrom` で解除。ハンドラ内で `DispatcherQueue().TryEnqueue` し、`argsJson`（`action` / `reply` / combo 選択値）を結果表示へ反映。
- ページ非表示中の `argsJson` は破棄。ハブにハンドラ未登録なら no-op（null 安全）。

### 6.3 入力バリデーション方針

- サンプルは各デモがハードコードの JSON ペイロードを使い、ユーザー入力欄を持たないため **UI 入力バリデーションは不要**。
- ライブラリ側バリデーション（ボタン数超過・audio ループ・badge 範囲・不正 JSON）の異常系確認は WindowsLibrary の単体テストでカバー済みのため、サンプルでは専用デモを設けない。

---

## 7. 手動確認観点

- `InitializeManager` 後に各 Show 系で Toast がアクションセンターに表示される。
- ボタン付き通知のボタン押下で `argsJson`（`action` 値）が結果表示に反映される（アプリ起動中）。
- **【要検証】アプリ未起動状態でボタン押下/通知クリック時にアクティベーション経由でコールバックが届くか（toast activation 拡張の要否確認。設計書 T-21）。**
- 入力付き通知（textBox/comboBox）で入力/選択値が `argsJson` に含まれる。
- 画像付き通知で `ms-appx:///Assets` 画像が表示される。
- 進捗通知表示 → `UpdateProgress` で進捗が更新される。未表示タグへの更新で `PROGRESS_NOT_FOUND(4)`。
- `Schedule(+1m)` で約1分後に通知が届く。`CancelScheduled` で届かなくなる。
- `SetBadge(5)` でタスクバー/タイルにバッジ、`ClearBadge` で消える。
- `GetAllNotifications` が JSON 一覧（`id`/`tag`/`group`）を返す。**一覧が大きい場合のバッファ境界（4096 固定長）で切り詰め/エラーにならないか確認。**
- `RemoveById`（GetAll の id 流用）で指定 id の通知が消える。
- `RemoveByTag` / `RemoveAll` で表示中通知が消える。
- `GetSetting` が `Enabled/Disabled/...` を返す。**WinRT 例外時に `-1`（Error）になることを確認（環境依存・再現任意）。**
- 通知無効時（OS 設定で当該アプリの通知 OFF）に Show が `DISABLED(2)` を返す。
- `INVALID_PAYLOAD(3)` / `INVALID_PARAMETER(7)`（不正ペイロード/パラメータ）の返却は WindowsLibrary の単体テストで確認済みのため、サンプルの手動確認対象外。
- **`HRESULT_FAILURE(5)` / `BADGE_FAILED(6)` の返却（CLSID 不正・バッジ更新失敗など。環境依存のため再現は任意・注記付き）。**
- メインメニューのメニューカードから `Dialog` / `Notification` 画面へ遷移でき、各画面の `Back` ボタンでメインメニューへ戻れる。
- アプリ起動時に WinRT 例外（`RPC_E_CHANGED_MODE`）が出ず正常起動する（ライブラリ側修正済みの回帰確認）。

---

## 8. 実装計画の確認（ステップ8）

- 提示文: 「この実装計画で進めますか？」
- 選択肢:
  - 承認する: 計画を確定、implement-sample-app workflow へ進む
  - 修正する: 指摘内容を反映して計画ファイルを更新
  - キャンセル: 計画ファイルは保持したまま終了
