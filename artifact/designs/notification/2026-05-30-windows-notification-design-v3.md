# Windows Notification 実装設計書

- 作成日: 2026-05-30
- 改訂日: 2026-06-13（v3 — packaged/unpackaged のAPI分離 / 別エージェントレビュー反映）
- 対象OS: Windows（最小: Windows 11）
- 対象企画書: `artifact/plans/notification/2026-05-30-windows-notification-research-v2.md`
- 言語: VC++（C++/WinRT）

> **v2 からの主な変更点**
> - **配信方式を packaged / unpackaged で完全分離**:
>   - packaged（MSIX）→ 新API `AppNotificationManager`（WinAppSDK）。v2 実装をそのまま維持
>   - unpackaged（Unity Win32 exe）→ 旧API `Windows.UI.Notifications`（classic Win32 toast）に全面移行
> - 実機検証で判明した「WinAppSDK の `Register()` 登録形式と旧OSスケジューラ（wpnapps.dll）の
>   配信パスが構造的に不一致」を解消するための設計変更
> - **アーキテクチャに案C（backend 分離）を採用**: 共通の前処理は `WindowsNotificationManager` に集約し、
>   API依存の末端操作だけを `INotificationBackend`（`PackagedBackend` / `UnpackagedBackend`）へ委譲。
>   メソッド内の `if (packaged)` 分岐を排除し、形態分岐を Init の backend 生成1箇所に収束
> - unpackaged 向けに **classic activator（`INotificationActivationCallback` COMサーバー）+
>   スタートメニューショートカット + レジストリ登録**（DesktopNotificationManagerCompat 相当）を新設
> - classic で実装不可な `RemoveById`（数値ID）/ `GetAll`（数値ID列挙）は unpackaged で明示エラーを返す
> - `initWinAppSdk()`（MddBootstrap）を Bridge に追加（unpackaged の WinAppSDK ランタイム読込用）
> - Init シグネチャを `displayName` / `iconUri` に変更（旧 `toastActivatorCLSID` / `launchUri` を廃止）
> - **公開 C Bridge API のシグネチャは変更しない。** ただし unpackaged では
>   `removeNotificationById` / `getAllNotifications` の戻り値の意味が変わる（`pError=8`=非対応）ため、
>   シグネチャ互換だが**動作互換性の変更**として扱う（後述「互換性への影響」参照）
>
> **別エージェントレビュー（v3 第2版）反映:**
> - 非対応コードを `INVALID_PARAMETER`(7) と分離し `NOTIFICATION_ERROR_NOT_SUPPORTED`(8) を新設
> - `INotificationBackend` から `json` と classic 具象型（`ToastNotifier`/`BadgeUpdater`）を排除。
>   JSON 解釈は Manager で完結させ backend には完成 payload を渡す
> - ClassicRegister 手順（CLSID 決定的生成 / ショートカット / レジストリ）を実装可能レベルに詳細化
> - cold-start 方針B に起動引数 `-ToastActivated` フォールバックを追加。CLSID は AUMID から導出
> - classic COM 実装方式（`winrt::implements` vs WRL）を着手前決定事項に格上げ（`::IUnknown` 衝突）
> - `m_callback` のスレッド安全（mutex / revoke→null 化順序）、Setting() の新旧 enum 明示変換、
>   backend モック注入 seam、`CancelScheduled`/`OpenSettings` の `CheckInitialized` を追加

---

## 実装着手前に必ず確定すべき事項（Task 0）

| # | 決定事項 | 既定 / 推奨 | 根拠指摘 |
|---|---------|------------|---------|
| 1 | cold-start 方針 A（早期Init）/ B（起動引数フォールバック） | **方針B で確定（2026-06-13）**。終了中クリックは LocalServer32 で確実に起動し、起動引数 `-ToastActivated` の自前パースでクリック情報を復元（ユーザー入力は best-effort）。Unity 側の追加実装は不要 | 1,4 |
| 2 | classic COM サーバー実装方式 | WRL もしくは生 `IUnknown`（`winrt::implements` は `::IUnknown` 衝突リスク）。最小 PoC で確認 | 5 |
| 3 | activator CLSID の生成方式 | AUMID からの決定的生成（固定値は複数アプリ衝突） | 4 |
| 4 | 非対応エラーコード | `NOTIFICATION_ERROR_NOT_SUPPORTED`(8) を新設 | 9 |
| 5 | `INotificationBackend` の抽象境界 | json/classic 型を晒さず完成 payload を渡す | 2,3 |
| 6 | packaged の Schedule | 新API にスケジュール API が無いため classic 例外として許容 | 3 |

---

## 設計目的

Windows の Toast 通知機能を `WindowsLibrary` MFC DLL に追加し、Unity Bridge（C API）経由で
Unity から呼び出せる形で提供する。アプリ形態（packaged / unpackaged）に応じて、各形態で
確実に動作する通知 API を内部で自動選択する。

---

## 背景（v3 で分離に至った経緯）

v2 は全形態で `AppNotificationManager`（新API）を主軸とし、新APIに存在しない
**スケジュール機能・バッジ機能だけを旧API `Windows.UI.Notifications` で補う**混在構成だった。

unpackaged(Unity) の実機検証で以下が判明:

| 機能 | 症状 |
|------|------|
| `scheduleNotification` | キュー投入は成功（`pending=1`）するが**配信されない** |
| `setBadge` | 旧API がパッケージID を要求し動作しない |

**根本原因:** 旧OSスケジューラ（wpnapps.dll）が unpackaged アプリへ配信するには、
`AppUserModelID` + `ToastActivatorCLSID` を埋め込んだスタートメニューショートカット +
COM activator 登録（classic 方式）が必須。WinAppSDK の `Register()` は COM activator ベースの
独自登録を作るが、これは旧スケジューラが参照するショートカット形式とは別物のため、
キューに入っても配信時に破棄される。

→ **「新APIで Show しつつ旧APIで Schedule」という組み合わせは構造的に成立しない。**
unpackaged は旧API一式（classic）へ、packaged は新API一式（WinAppSDK）へ、それぞれ統一する。

---

## スコープ

### In Scope

- Toast 通知（基本表示 / アクション付き / 画像付き / 進捗バー付き）
- 音声制御（カスタム音声 / システム音声 / ミュート / ループ）
- スケジュール通知（指定時刻 / Reminder・Alarm シナリオ）
- スケジュール通知キャンセル
- グループ・タグ管理
- バッジ通知
- 通知クリック・アクションのコールバック（C 関数ポインタ）— **両形態で対応**
- テキスト入力（`textBoxes`）およびコンボボックス（`comboBoxes`）
- 通知履歴管理（削除・全削除）
- 通知一覧取得（packaged のみ）
- 通知有効期限設定（`Expiration` / `ExpiresOnReboot`）
- フォールバック判定（`Setting()`）
- **packaged / unpackaged の初期化分岐と配信API分離**

### Out of Scope

- プッシュ通知（WNS）
- Tile 通知
- Windows 11 未満の対応
- unpackaged での `RemoveById`（数値ID）/ `GetAll`（数値ID列挙）— classic API 非対応のため明示エラー
- ToastCollection / UserNotificationListener — 将来拡張

---

## 配布要件（指摘3対応 / Medium）

**unpackaged を「classic 化」と称するが、実体は WinAppSDK ランタイムへの依存が残る。**
XML 生成に `AppNotificationBuilder`（WinAppSDK）を共用し、`initWinAppSdk()`
（`MddBootstrapInitialize`）の成功を `showNotification` 等の前提とするため。これは
low-risk note ではなく、**unpackaged 配布の必須要件**として扱う。

| 要件 | 内容 |
|------|------|
| Windows App Runtime（WinAppSDK 1.7 系）が対象PCにインストール済み | unpackaged では MSIX による自動プロビジョニングが効かないため、`WindowsAppRuntimeInstall.exe` 等で**事前インストールが必要**。未インストールだと `initWinAppSdk` が失敗し通知機能全体が無効 |
| `Microsoft.WindowsAppRuntime.Bootstrap.dll` を exe と同梱配置 | Unity の `Plugins\Windows\` に配置。DllNotFound 回避 |
| `initWinAppSdk(0x00010007 等)` を `initNotificationManager` の前に呼ぶ | 呼び出し順を Unity 側 API ドキュメントに明記 |

> **設計判断:** classic 配信経路でも XML 生成のために WinAppSDK を残す
> （`AppNotificationBuilder` を捨てて classic XML を手組みすれば依存を切れるが、検証済みの
> `BuildFromJson` を再実装するコストと不具合リスクが高いため採用しない）。代わりに
> **配布要件として明文化**する。

> **`InitWinAppSdk` の分岐（指摘11）:** `DeploymentManager::Initialize()` は package identity を
> 要求するため **unpackaged では呼ばない**（`APPMODEL_ERROR_NO_PACKAGE` を例外で握る現行実装は、
> `PackageInstallRequired` 等の他 status を pError=5 で誤って弾く穴がある）。`InitWinAppSdk` に
> `isPackaged` を伝え、unpackaged では `MddBootstrapInitialize` のみ行い `DeploymentManager` を
> スキップする。Main/Singleton パッケージは事前導入の Windows App Runtime に委ねる。

---

## 互換性への影響（指摘2対応 / Medium）

公開 C Bridge API の**シグネチャは不変**だが、unpackaged では一部 API の**動作（戻り値の意味）が変わる**。
Unity 側コードの無改修でビルドは通るが、呼び出し側の期待値が変わるため**動作互換性の変更**として扱う。

| API | packaged | unpackaged（v3 での変更） | Unity 側で必要な対応 |
|-----|----------|---------------------------|----------------------|
| `removeNotificationById` | 従来どおり成功 | **`pError=8`（NOT_SUPPORTED）** | 非対応を結果表示／呼び出し抑止。Tag ベース削除へ誘導 |
| `getAllNotifications` | 従来どおり一覧返却 | **`pError=8`（NOT_SUPPORTED）、`outJson` 未設定** | 一覧取得不可を結果表示。機能ガード |

> サンプル（`WindowsNotificationManagerExampleController.cs`）の該当ボタンは、unpackaged では
> 非対応メッセージを表示する（`pError==8` をハンドリング）。これは Unity 側の**表示・ガードの変更**を伴う。

---

## アプリ形態別 API マトリクス

| 機能 | packaged（新API / 既存維持） | unpackaged（旧API / 新規 classic） |
|------|------------------------------|-------------------------------------|
| 初期化 | `AppNotificationManager::Register()` | `ClassicRegister()`（ショートカット+COM登録） |
| Show | `AppNotificationManager::Show()` | `ToastNotificationManager::CreateToastNotifier(aumid).Show()` |
| Schedule | `ScheduledToastNotification` + 既定通知器 | `CreateToastNotifier(aumid).AddToSchedule()` |
| CancelScheduled | 同上 | 同上 |
| UpdateProgress | `AppNotificationManager::UpdateAsync()` | `CreateToastNotifier(aumid).Update(NotificationData)` |
| SetBadge | `BadgeUpdateManager::CreateBadgeUpdaterForApplication()` | `...ForApplication(aumid)` |
| RemoveByTag / RemoveAll | `RemoveBy*Async` | `ToastNotificationManager::History().Remove/Clear(... aumid)` |
| RemoveById | `RemoveByIdAsync` | **非対応 → `NOTIFICATION_ERROR_INVALID_PARAMETER`** |
| GetAll | `GetAllAsync` | **非対応 → `NOTIFICATION_ERROR_INVALID_PARAMETER`** |
| GetSetting | `AppNotificationManager::Default().Setting()` | `CreateToastNotifier(aumid).Setting()` |
| 通知クリック | `NotificationInvoked` イベント | `INotificationActivationCallback::Activate()` |
| OpenSettings | `Launcher`（共通） | `Launcher`（共通） |

> **XML生成は両形態で共用**: `AppNotificationBuilder` で JSON→ToastGeneric XML を生成し
> （`BuildNotification().Payload()`）、classic 側は得た XML を `XmlDocument` に load して
> `ToastNotification` / `ScheduledToastNotification` に渡す。`AppNotificationBuilder` は
> 登録不要で XML 生成のみに使えるため、unpackaged でも builder のランタイム読込のために
> `initWinAppSdk()`（MddBootstrap）は引き続き必要。

---

## 実装アーキテクチャ

**採用方針（案C: 共通処理は Manager / 分岐する末端だけ backend に委譲）**

新旧で実際に異なるのは「末端の配信呼び出し」だけ。共通の前処理（JSON解析・`BuildFromJson`・
バリデーション・Setting確認・エラー変換）は全メソッドで共通のため、それらは Manager に集約し、
**API依存の末端操作だけを `INotificationBackend` 仮想メソッドへ委譲**する。これにより
各メソッド本体から `if (packaged) … else …` が消え、新旧APIがクラス単位で物理分離される。

```
Unity C# (P/Invoke)
    │
    ▼
extern "C" C Bridge API          ← WindowsNotificationManager.h（シグネチャ不変）
    │
    ▼
WindowsNotificationManager       ← WindowsNotificationManager.cpp
（singleton / 共通 orchestration を保持）
    │   - JSON解析 / BuildFromJson / バリデーション / Setting確認 / エラー変換 / ArgsToJson
    │   - Init 時に backend を1つ生成して m_backend に保持（以降メソッド内分岐なし）
    │
    └─ m_backend : INotificationBackend*        ← 末端の API 依存操作のみを委譲
          │   Deliver(payload) / Schedule(payload,when) / CancelSchedule() / SetBadge(value)
          │   UpdateProgress(...) / RemoveByTag() / RemoveAll()
          │   RemoveById() / GetAll() / Setting() / RegisterActivation() / UnregisterActivation()
          │   ※ json も classic 具象型(ToastNotifier/BadgeUpdater)もインターフェースに晒さない
          │
          ├─ PackagedBackend            ← WindowsNotificationManager.cpp（同TUで可）
          │     [Windows App SDK / 新API]
          │     ├── AppNotificationManager::Register/Unregister/Show/UpdateAsync
          │     ├── GetAllAsync / RemoveByXxxAsync
          │     ├── NotificationInvoked event → Manager.OnNotificationInvoked
          │     └── RemoveById / GetAll は実装あり
          │
          └─ UnpackagedBackend          ← WindowsClassicActivator.cpp（新規TU / classic 隔離）
                [Windows.UI.Notifications / 旧API]
                ├── ClassicRegister: Start Menu ショートカット（AUMID + ToastActivatorCLSID）
                │      + レジストリ（CLSID\LocalServer32, AppUserModelId\ApplicationName）
                │      + INotificationActivationCallback COMサーバー + IClassFactory
                │      （CoRegisterClassObject / CoRevokeClassObject）
                │      Activate() → Manager.GetInstance() 経由で m_callback へ中継
                ├── CreateToastNotifier(aumid).Show / AddToSchedule / RemoveFromSchedule
                ├── Update(NotificationData) / History().Remove()/Clear()
                └── RemoveById / GetAll は pError=8（NOT_SUPPORTED）

共通基盤（両 backend が利用）:
    AppNotificationBuilder   [XML生成専用 / 両形態で共用]
    WindowsAppSdkBootstrap   ← WindowsAppSdkBootstrap.cpp（新規TU / MddBootstrap 隔離）
```

**backend の所有とライフサイクル:**
- `m_backend` は `WindowsNotificationManager` が **所有**（`std::unique_ptr`）。Init で形態に応じて
  `PackagedBackend` / `UnpackagedBackend` を生成、Uninit で破棄。**独立した寿命は持たない**。
- `UnpackagedBackend` の COM activator が OS から `Activate()` される際は、
  `WindowsNotificationManager::GetInstance()` 経由で `m_callback` / `ArgsToJson` に到達する
  （状態は Manager に一元化。activator は「OS入口」のみを担う）。

**TU 分離方針（依存隔離）:**
- `WindowsAppSdkBootstrap.cpp` … `Microsoft.WindowsAppRuntime.Bootstrap.dll` 依存を隔離
- `WindowsClassicActivator.cpp` … `UnpackagedBackend` 実装 + classic activator を収め、
  shell / COM サーバー系ヘッダ（`<NotificationActivationCallback.h>` `<propkey.h>`
  `<propvarutil.h>` `<ShObjIdl.h>` `<propsys.h>` `<shlobj.h>`）を隔離。
  pch.h には追加しない（MFC の `::IUnknown` と WinRT の衝突回避のため）
- `PackagedBackend` … WinAppSDK のみ使用のため `WindowsNotificationManager.cpp` 同TUで可

---

## サブ機能別詳細設計

### 1. 初期化 / 終了

**責務:** アプリ形態に応じた通知登録と、クリックコールバック経路の確立

**Bridge:**
```cpp
// WinAppSDK ランタイム読込（unpackaged で initNotificationManager の前に呼ぶ）
void initWinAppSdk(uint32_t majorMinorVersion, DWORD* pError);

void initNotificationManager(
    NotificationInvokedCallback callback,
    BOOL isPackaged,
    const wchar_t* displayName,  // unpackaged: 必須（AUMID/表示名）。packaged: 無視
    const wchar_t* iconUri,      // unpackaged: 必須（plain path or file:// URI）。packaged: 無視
    DWORD* pError);

void uninitNotificationManager();
```

**制御フロー（Init）— backend を1つ生成して保持する（以降メソッド内分岐なし）:**
1. `m_initialized` なら再登録せず return（プロセス全体で登録は1回）
2. `CoInitializeEx`（`RPC_E_CHANGED_MODE` は許容）
3. **backend 生成（形態分岐はここ1箇所のみ）:**
   - `isPackaged == TRUE`: `m_backend = std::make_unique<PackagedBackend>()`
   - `isPackaged == FALSE`:
     - `displayName` / `iconUri` 必須チェック（欠如→`NOTIFICATION_ERROR_INVALID_PARAMETER`）
     - `iconUri` を `NormalizeIconPath()` で plain path 化
     - `m_backend = std::make_unique<UnpackagedBackend>(displayName /*aumid*/, iconPath)`
4. `m_callback = callback`（**RegisterActivation より前に設定**。cold-start で Activate が
   即来ても中継先がある状態にする / 指摘4・6）
5. `m_backend->RegisterActivation(pError)` を呼ぶ:
   - **PackagedBackend:** `AppNotificationManager::Default().NotificationInvoked` 登録 + `Register()`
   - **UnpackagedBackend（ClassicRegister / 詳細は下記「ClassicRegister 手順」）**
6. `m_backend->Setting()` をログ出力、管理者権限実行を警告ログ
7. `m_initialized = true`

**ClassicRegister 手順（UnpackagedBackend::RegisterActivation の実装可能レベル詳細 / 指摘1）:**

`Show`/`Schedule`/`Setting`/`History` が classic で機能する**前提条件**。これが揃わないと
`CreateToastNotifier(aumid)` は通知を表示できず、スケジュールも配信されない。

1. **CLSID 決定（指摘4: 固定値をやめ AUMID から決定的生成）:**
   `m_activatorClsid = NameToGuid(aumid)`（AUMID を SHA1/MD5 等でハッシュ→GUID 整形）。
   同一マシンに複数の本DLL利用アプリが同居しても衝突しない。
2. **COM サーバー登録（class object 公開）:**
   `CoRegisterClassObject(m_activatorClsid, IClassFactory, CLSCTX_LOCAL_SERVER, REGCLS_MULTIPLEUSE, &m_comRegToken)`
3. **レジストリ（cold-start の exe 起動に必要 / 冪等）:**
   - `HKCU\Software\Classes\CLSID\{m_activatorClsid}\LocalServer32 = "<exeフルパス> -ToastActivated"`
   - `HKCU\Software\Classes\AppUserModelId\{aumid}` に `DisplayName`(=aumid) / `IconUri`(=iconPath)
4. **スタートメニューショートカット（toast 表示・配信の必須要件 / 冪等）:**
   `%APPDATA%\Microsoft\Windows\Start Menu\Programs\<displayName>.lnk` を作成:
   - `CoCreateInstance(CLSID_ShellLink)` → `IShellLinkW::SetPath(<exe>)` / `SetArguments` / `SetIconLocation`
   - `QueryInterface(IPropertyStore)` → `PKEY_AppUserModel_ID`(=aumid, `InitPropVariantFromString`),
     `PKEY_AppUserModel_ToastActivatorCLSID`(=m_activatorClsid, `InitPropVariantFromCLSID`) を `SetValue` → `Commit`
   - `QueryInterface(IPersistFile)::Save(lnkPath, TRUE)`
   - **冪等性:** 既存 lnk が同一 AUMID/CLSID を持つなら再作成スキップ
5. 失敗時は `pError = NOTIFICATION_ERROR_HRESULT_FAILURE`（後続 Show 等は機能しない）

> **前提依存（指摘1）:** `Show`/`Schedule`/`UpdateProgress`/`SetBadge`/`RemoveBy*`/`Setting` の
> 制御フローは、いずれも「ClassicRegister 成功済み（=ショートカット+CLSID+class object 公開済み）」
> を前提とする。`CheckInitialized` がこれを担保する（Init 失敗時は `m_initialized=false`）。

> **形態判定の一本化（指摘4対応）:** 形態分岐は **Init での backend 生成（Step 3）の1箇所のみ**。
> 以降の全メソッドは `m_backend->Xxx()` を呼ぶだけで `if (packaged)` を持たない。
> `m_isPackaged` のような別フラグは設けない（状態の二重化・不整合を回避）。
> AUMID は `UnpackagedBackend` が内部で保持する（Manager は形態を意識しない）。

**制御フロー（Uninit）— revoke を先に、callback の null 化を後に（指摘6）:**
1. `m_backend->UnregisterActivation()`:
   - PackagedBackend: `NotificationInvoked(token)` 解除 + `Unregister()`
   - UnpackagedBackend: `CoRevokeClassObject`（ショートカット/レジストリは残置可）
2. **revoke 完了後**に `m_callbackMutex` 下で `m_callback=nullptr`（以降 Activate は来ないため競合区間が閉じる）
3. `m_backend.reset()`, `m_initialized=false`

**classic activator CLSID（指摘4: 固定値廃止）:** ハードコードせず **AUMID から決定的に生成**
（`NameToGuid(aumid)`）。同一マシンに本DLLを使う複数アプリが同居しても CLSID 衝突しない。
packaged 用 appxmanifest CLSID とは別系統で、両経路は同一プロセスで共存しない。

---

### 2. Toast 通知表示

**責務:** JSON ペイロードを `AppNotificationBuilder` で構築し、形態別に配信する

**内部メソッド:** `Show(const wchar_t* jsonPayload, DWORD* pError)`
（`BuildFromJson` / `ApplyButtons` / `ApplyComboBoxes` / `ApplyImages` / `ApplyAudio` /
`ApplyProgress` は v2 から不変。両形態で共用）

**JSON ペイロード仕様:** v2 と同一（`title` / `body` / `tag` / `group` / `scenario` /
`duration` / `timestamp` / `expiration` / `expiresOnReboot` / `attribution` / `appLogo` /
`heroImage` / `inlineImage` / `buttons` / `textBoxes` / `comboBoxes` / `progress` / `audio`）

**バリデーション規則:** v2 と同一（buttons最大5 / audio.loop は duration=long 必須 /
args・invokeUri 排他 / audio.type=uri は uri 必須 / badge value<-6 不正）

**制御フロー（指摘2: JSON 解釈は Manager で完結し、backend には完成 payload を渡す）:**
1. `m_initialized` チェック → 未初期化なら `NOTIFICATION_ERROR_NOT_INITIALIZED`
2. `m_backend->Setting()` を**1回**取得 → `Enabled` 以外なら `NOTIFICATION_ERROR_DISABLED`
   （取得値は使い回し、Show 内での重複 WinRT 呼び出しを避ける / 指摘3）
3. `JsonObject::TryParse()` → 失敗なら `NOTIFICATION_ERROR_INVALID_PAYLOAD`
4. `BuildPayload(json)` で **Manager が完成 payload を構築**（共通）:
   - `BuildFromJson()` → `BuildNotification()`
   - `expiration` / `expiresOnReboot` / 進捗初期値（`progress`）の **JSON 解釈と適用は Manager 側**
   - 結果を中立構造体 `DeliverPayload` にラップ（packaged=AppNotification / unpackaged=XML+初期ProgressData）
5. `m_backend->Deliver(payload)` へ委譲（**backend は完成物を配信するだけ。json も classic 型も受けない**）:
   - **PackagedBackend:** `AppNotificationManager::Default().Show(payload.notification)`
   - **UnpackagedBackend:** `payload.xml` を `XmlDocument::LoadXml()` → `ToastNotification{doc}` →
     `payload.progress` を `toast.Data()` に設定 → `CreateToastNotifier(aumid).Show(toast)`

> Step 1〜4（前処理 + payload 完成）は Manager に1回だけ実装。expiration/progress の
> JSON 解釈が backend に重複しない（指摘2）。Step 5 のみ backend へ委譲。

---

### 3. スケジュール通知

**責務:** 指定時刻に Toast 通知を表示登録する

**内部メソッド:** `Schedule(jsonPayload, scheduledTimeUnixMs, pError)` /
`CancelScheduled(tag, group, pError)`

**制御フロー（Schedule）— 共通処理は Manager / 配信操作だけ backend:**
1. Show と同じ初期化・JSON 解析・`BuildPayload`（共通）
2. `scheduledTimeUnixMs` を `winrt::clock::from_sys()` で `DateTime` 変換（共通）
3. デリバリーウィンドウ5分超過は警告ログ（共通）
4. `m_backend->Schedule(payload, when)` へ委譲（**ToastNotifier をインターフェースに晒さない / 指摘3**）:
   - UnpackagedBackend: `CreateToastNotifier(aumid).AddToSchedule(ScheduledToastNotification{xml, when})`
   - PackagedBackend: 後述「packaged スケジュールの例外」参照

**制御フロー（CancelScheduled）:**
1. `CheckInitialized` チェック（指摘12: pError=1 を返し得る）
2. `m_backend->CancelSchedule(tag, group)` へ委譲（backend 内で
   `GetScheduledToastNotifications()` → `tag`/`group` 一致を `RemoveFromSchedule()`）

> **packaged スケジュールの例外（指摘3）:** `AppNotificationManager`（新API）には
> **スケジュール API が存在しない**。そのため packaged でも `Schedule` は classic
> `ToastNotificationManager::CreateToastNotifier()` + `ScheduledToastNotification` を使う。
> これは「packaged は新API一式」の唯一の例外であり、プラットフォーム制約として明記する
> （`PackagedBackend::Schedule` 内に閉じ、ToastNotifier 型はインターフェースに漏らさない）。

> **設計のキモ:** unpackaged は `ClassicRegister()` のショートカット + COM登録により、
> 旧スケジューラがアプリを解決できるようになるため、`AddToSchedule` した通知が
> 指定時刻に**実際に配信される**（v2 で破棄されていた問題の解消）。

---

### 4. 進捗バー更新

**責務:** 既存の進捗バー通知を更新する

**内部メソッド:** `UpdateProgress(tag, group, value, valueStr, status, seq, pError)`

**制御フロー:** `m_backend->UpdateProgress(tag, group, value, valueStr, status, seq)` へ委譲:
- **PackagedBackend:** `AppNotificationProgressData{seq}` を構築 → `UpdateAsync(data, tag[, group])`
  を非STAスレッドでブロッキング（`RunSyncOffSta`）→ 結果が `Succeeded` 以外なら
  `NOTIFICATION_ERROR_PROGRESS_NOT_FOUND`
- **UnpackagedBackend:** `NotificationData` を構築（`Values` に `progressValue`/`progressValueString`/
  `progressStatus`、`SequenceNumber=seq`）→ `CreateToastNotifier(aumid).Update(data, tag, group)`
  → 結果が `NotificationUpdateResult::Succeeded` 以外なら `NOTIFICATION_ERROR_PROGRESS_NOT_FOUND`

> classic の進捗更新は ToastGeneric の `<progress>` 要素に `{progressValue}` 等の
> データバインド名を埋め、`NotificationData` で差し替える（XML 生成は `ApplyProgress` の
> `BindValue/BindStatus` 出力をそのまま利用）

---

### 5. バッジ通知

**責務:** タスクバーアイコンのバッジを数値/グリフで更新

**内部メソッド:** `SetBadge(int value, DWORD* pError)`

**パラメータ仕様:** v2 と同一（`>0`=数値, `0`=クリア, `-1`=alert, `-2`=activity,
`-3`=newMessage, `-4`=available, `-5`=busy, `-6`=away, `<-6`=不正）

**制御フロー（指摘3: BadgeUpdater 型をインターフェースに晒さず `SetBadge` 操作として閉じる）:**
1. `value < -6` → `NOTIFICATION_ERROR_INVALID_PARAMETER`（Manager 側の共通バリデーション）
2. `m_backend->SetBadge(value)` へ委譲。backend 内で:
   - updater 取得（UnpackagedBackend: `CreateBadgeUpdaterForApplication(aumid)` /
     PackagedBackend: `CreateBadgeUpdaterForApplication()`）
   - `value==0`→`Clear()` / `>0`→数値XML / `<0`→グリフXML を `Update(BadgeNotification{doc})`
     （XML 構築は共通ヘルパ関数を両 backend で共有）

---

### 6. 通知ハンドリング（クリックコールバック）

**責務:** クリック・ボタン押下・入力を C コールバックで通知する

**コールバック型:** `typedef void (*NotificationInvokedCallback)(const wchar_t* argsJson)`

**argsJson 仕様:** v2 と同一（`action` / `id` / `reply` / `combo_selection_id` 等を
WinRT JSON API で生成）

**制御フロー（入口は backend / 中継先は Manager に一元化）:**
- **PackagedBackend:** `AppNotificationManager::NotificationInvoked` →
  `Manager.OnNotificationInvoked(sender, args)` → `args.Arguments()` + `args.UserInput()` を
  `Manager.ArgsToJson()` で JSON 化 → `Manager.m_callback()`
- **UnpackagedBackend:** OS が登録 CLSID の COM サーバーへ接続 →
  `INotificationActivationCallback::Activate(aumid, invokedArgs, data, count)` →
  `Manager.GetInstance()` 経由で `ClassicArgsToJson(invokedArgs, data, count)` を JSON 化 →
  `Manager.m_callback()`
  - `invokedArgs`: アクションの `arguments`（クエリ文字列 `key=value&...`）をパースして JSON 化
  - `data`(`NOTIFICATION_USER_INPUT_DATA[]`): テキスト入力 / コンボ選択値を同一 JSON にマージ

> **状態は Manager に一元化:** どちらの backend も「OS からの入口」だけを担い、
> `m_callback` と JSON 変換ロジックは `WindowsNotificationManager` が保持する
> （activator が callback を複製保持しない＝不整合回避）。

**二重起動について:** classic では LocalServer32 に exe を登録し、起動中は
`CoRegisterClassObject` 済みのクラスオブジェクトが Activate を受信するため、
**実行中のクリックでアプリは再起動しない**（v2 の WinAppSDK activator で発生していた
二重起動を解消）。

**未起動時アクティベーション（cold-start）の成立条件（指摘1対応 / High）:**

「アプリ未起動時にクリック → OS が exe を起動 → Activate が届く」は、以下の条件が
**すべて満たされた場合にのみ成立する**。本構成（Unity が DLL をロード）では、Unity の
起動シーケンスとの兼ね合いで成立しないケースがあるため、成立条件と未成立時の挙動を明示する。

| 条件 | 内容 | 本構成での担保 |
|------|------|----------------|
| C1 | LocalServer32 に登録された exe が、COM 起動時のコマンドライン（`-ToastActivated` 等）で起動される | OS 仕様（ショートカット+CLSID登録済みが前提） |
| C2 | 起動した exe が **COM の起動タイムアウト内（実測 ~数秒）に `CoRegisterClassObject` を完了**し、class object を公開する | **要設計**: Unity の通常起動（エンジン初期化→シーン→プラグイン Init）はこのタイムアウトに間に合わない可能性が高い |
| C3 | 公開した class object が `INotificationActivationCallback::Activate` を受け、`m_callback` 設定後に呼ぶ | Init で `m_callback` 設定済みであること |

**C2 が本構成の弱点。** Unity native plugin の `initNotificationManager` はシーン/スクリプト
初期化後に呼ばれるため、COM 起動タイムアウトに間に合わず、cold-start の Activate が
**サイレントに失われる**リスクがある。

**対応方針（いずれかを Unity 側と合意の上で選択。本 DLL 単体では C2 を保証できない）:**
- **方針A（推奨 / 別タスク）:** Unity 起動引数を監視し、`-ToastActivated`（または
  起動時に渡る activation 引数）を検出したら、Unity の最初期（`RuntimeInitializeOnLoadMethod`
  with `BeforeSceneLoad`/`SubsystemRegistration`）で `initNotificationManager` を呼び、
  class object を早期公開する。これにより C2 を成立させる。
- **方針B（cold-start を引数フォールバックで best-effort 対応 / 指摘4）:** class object 公開が
  間に合わず `Activate` が届かない場合に備え、**起動コマンドライン `-ToastActivated`（および
  後続の activation 引数）を自前パースして argsJson 化**する経路を設ける:
  - `initNotificationManager`（または専用 Bridge `consumeLaunchActivation`）の中で
    `GetCommandLineW()` を調べ、`-ToastActivated` を検出したら引数を `ClassicArgsToJson` 相当で
    変換して `InvokeCallback` を1回呼ぶ。
  - これにより「class object 経由の `Activate` は取りこぼしても、起動引数からクリック情報を
    復元」できる。ユーザー入力（テキスト/コンボ）は引数に含まれない場合があり best-effort。

> **本設計の確定事項（2026-06-13 / 方針B 確定）:** cold-start は **方針B を採用**する。
> - **「起動」は確実**: レジストリ `LocalServer32` 登録により、終了中クリックでも OS が exe を
>   起動する（アプリ初期化速度に非依存）。
> - **「起動後の引数」も確実に復元**: COM `Activate` の不確実なタイミング競合（C2）には依存せず、
>   起動引数 `-ToastActivated` を自前パースしてクリック情報を argsJson 化する。
>   ユーザー入力（テキスト/コンボ）は引数に含まれない場合があり best-effort。
> - **Unity 側の追加実装は不要**（方針A の早期 Init 統合は採用しない）。
> - 前提: 一度はアプリを起動して `initNotificationManager`（=`RegisterActivation`）を完了し、
>   レジストリ/ショートカットが書き込まれていること（初回起動前は登録が無く起動不可。両方針共通）。

---

### 7. 通知削除 / 通知一覧取得

**責務:** ID / タグ / グループ / 全削除 / 一覧取得

**制御フロー:** Manager は `m_backend->RemoveByTag/RemoveAll/RemoveById/GetAll(...)` へ委譲。
backend 実装が次のとおり分岐する:

| backend メソッド | PackagedBackend | UnpackagedBackend |
|---------|----------|------------|
| `RemoveByTag` | `RemoveByTagAsync` / `RemoveByTagAndGroupAsync` | `ToastNotificationManager::History().Remove(tag[, group], aumid)` |
| `RemoveAll` | `RemoveAllAsync` | `ToastNotificationManager::History().Clear(aumid)` |
| `RemoveById` | `RemoveByIdAsync` | **`NOTIFICATION_ERROR_NOT_SUPPORTED`(=8)**（classic に数値ID無し） |
| `GetAll` | `GetAllAsync` → JSON 配列 | **`NOTIFICATION_ERROR_NOT_SUPPORTED`(=8)**（数値ID列挙不可） |

> **非対応コードの分離（指摘9）:** 「形態的に非対応」を `INVALID_PARAMETER`(=7, 引数不正) と
> 同一コードで表すと、呼び出し側が「引数が悪い」のか「機能が非対応」かを区別できない
> （badge `value<-6` も 7 を返すため二重意味になる）。新コード
> `NOTIFICATION_ERROR_NOT_SUPPORTED`(=8) を新設して非対応を明示する
> （out パラメータの値であり公開シグネチャは不変）。`UnpackagedBackend` が 8 を返し、
> Unity 側結果メッセージに「この形態では非対応」を明示する。

---

### 8. 設定状態取得

**責務:** 通知有効状態を int で返す

**制御フロー（指摘7: 新旧 enum を明示変換し `static_cast` 素通しを禁止）:**
`m_backend->Setting()` が**各 backend で自 enum を共通 int 体系へ変換**して返す。
新旧 enum は値順が一致する保証がないため（特に `DisabledByManifest` 等）、変換テーブルで対応付ける。

| 共通 int | packaged: `AppNotificationSetting` | unpackaged: `NotificationSetting` |
|---|---|---|
| 0 Enabled | `Enabled` | `Enabled` |
| 1 DisabledForApplication | `DisabledForApplication` | `DisabledForApplication` |
| 2 DisabledForUser | `DisabledForUser` | `DisabledForUser` |
| 3 DisabledByGroupPolicy | `DisabledByGroupPolicy` | `DisabledByGroupPolicy` |
| 4 DisabledByManifest | `DisabledByManifest` | `DisabledByManifest` |
| -1 | 例外時 | 例外時 |

> 値は現状一致するが、`static_cast<int>(setting)` の素通しは禁止し、各 backend が
> **明示的な switch/変換関数**で共通 int を返す（将来 enum 定義変更時の値ズレ防止）。
> `Show` / `Schedule` 冒頭の Setting 確認も同じ `m_backend->Setting()` を **1回だけ**呼んで使い回す。

---

### 9. 設定ページを開く（共通）

`OpenSettings()` … `CheckInitialized` の後（指摘12）、`ms-settings:notifications` を
`Launcher::LaunchUriAsync()`（`RunSyncOffSta` で STA セーフ）。形態非依存。

---

## API 設計（公開 C Bridge）

> **v3 で公開関数シグネチャ変更なし**（v2→現行で `initNotificationManager` が
> `displayName`/`iconUri` 化済み、`initWinAppSdk` / `openNotificationSettings` 追加済み）。
> **エラーコードは `NOTIFICATION_ERROR_NOT_SUPPORTED`(=8) を新設**（指摘9。out パラメータの
> 値追加であり公開シグネチャは不変）。

```cpp
// Error codes
#define NOTIFICATION_SUCCESS                    0
#define NOTIFICATION_ERROR_NOT_INITIALIZED      1
#define NOTIFICATION_ERROR_DISABLED             2
#define NOTIFICATION_ERROR_INVALID_PAYLOAD      3
#define NOTIFICATION_ERROR_PROGRESS_NOT_FOUND   4
#define NOTIFICATION_ERROR_HRESULT_FAILURE      5
#define NOTIFICATION_ERROR_BADGE_FAILED         6
#define NOTIFICATION_ERROR_INVALID_PARAMETER    7
#define NOTIFICATION_ERROR_NOT_SUPPORTED        8  // この形態では機能非対応（v3 新設）

typedef void (*NotificationInvokedCallback)(const wchar_t* argsJson);

extern "C" WINDOWSNOTIFICATIONMANAGER_API void initWinAppSdk(uint32_t majorMinorVersion, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void initNotificationManager(NotificationInvokedCallback callback, BOOL isPackaged, const wchar_t* displayName, const wchar_t* iconUri, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void uninitNotificationManager();
extern "C" WINDOWSNOTIFICATIONMANAGER_API void showNotification(const wchar_t* jsonPayload, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void scheduleNotification(const wchar_t* jsonPayload, int64_t scheduledTimeUnixMs, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void cancelScheduledNotification(const wchar_t* tag, const wchar_t* group, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void updateNotificationProgress(const wchar_t* tag, const wchar_t* group, double value, const wchar_t* valueStr, const wchar_t* status, uint32_t sequenceNumber, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void setBadge(int value, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void removeNotificationById(uint32_t notificationId, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void removeNotificationsByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void removeAllNotifications(DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API void getAllNotifications(wchar_t* outJson, uint32_t bufferSize, DWORD* pError);
extern "C" WINDOWSNOTIFICATIONMANAGER_API int  getNotificationSetting();
extern "C" WINDOWSNOTIFICATIONMANAGER_API void openNotificationSettings(DWORD* pError);
```

---

## 公開 API 返却仕様（統一対応表 / unpackaged 差分込み）

| Bridge 関数 | 返却型 | pError | packaged 失敗時 | unpackaged 失敗時（差分） |
|------------|-------|--------|----------------|---------------------------|
| `initWinAppSdk` | `void` | あり | — | pError = 5 |
| `initNotificationManager` | `void` | あり | pError = 1〜7 | 同左（COM/ショートカット失敗で 5/7） |
| `showNotification` | `void` | あり | pError = 1〜7 | 同左 |
| `scheduleNotification` | `void` | あり | pError = 1〜7 | 同左 |
| `cancelScheduledNotification` | `void` | あり | pError = **1**,5 | 同左（指摘12: CheckInitialized で 1 を返し得る） |
| `updateNotificationProgress` | `void` | あり | pError = 1,4,5 | 同左 |
| `setBadge` | `void` | あり | pError = 6,7 | 同左 |
| `removeNotificationById` | `void` | あり | pError = 1,5 | **pError = 8（NOT_SUPPORTED）** |
| `removeNotificationsByTag` | `void` | あり | pError = 1,5 | 同左 |
| `removeAllNotifications` | `void` | あり | pError = 1,5 | 同左 |
| `getAllNotifications` | `void` | あり | pError = 1,5 | **pError = 8（NOT_SUPPORTED）** |
| `getNotificationSetting` | `int` | なし | -1 | -1 |
| `openNotificationSettings` | `void` | あり | pError = **1**,5 | 同左（指摘12: CheckInitialized） |

---

## 内部クラス設計（案C: backend インターフェース分離）

**`INotificationBackend`（末端の API 依存操作のみを抽象化）:**

> **抽象境界の原則（レビュー指摘2/3 反映）:** backend には **`json` を渡さない**。`expiration` /
> `expiresOnReboot` / `progress 初期値` などの **JSON 解釈は Manager の責務**として
> 「完成した配信物」まで Manager で組み立て、backend は**完成物を配信するだけ**にする。
> また `ToastNotifier` / `BadgeUpdater` などの **classic 具象型をインターフェースに晒さない**
> （`Schedule(...)` / `CancelSchedule(...)` / `SetBadge(...)` の操作として閉じる）。

```cpp
// WindowsNotificationBackend.h（新規 / Manager と両 backend が共有）
struct INotificationBackend
{
    virtual ~INotificationBackend() = default;

    // ライフサイクル（activation 登録/解除）
    virtual void RegisterActivation(DWORD* pError) = 0;   // callback は Manager が保持（backend は持たない）
    virtual void UnregisterActivation() = 0;

    // 末端配信（Manager が完成させた payload を受け取り、API固有の配信だけを行う）
    //  payload = Manager が BuildNotification() し expiration/progress 等を適用済みの配信物。
    //  packaged は AppNotification、unpackaged は XML 文字列 + 初期 NotificationData を内包する
    //  中立的な構造体 DeliverPayload にラップして渡す（json も classic 型も晒さない）。
    virtual void Deliver(const DeliverPayload& payload, DWORD* pError) = 0;
    virtual void Schedule(const DeliverPayload& payload, winrt::Windows::Foundation::DateTime when, DWORD* pError) = 0;
    virtual void CancelSchedule(const wchar_t* tag, const wchar_t* group, DWORD* pError) = 0;
    virtual void SetBadge(int value, DWORD* pError) = 0;  // XML 構築は共通ヘルパ、updater 取得だけ backend
    virtual void UpdateProgress(const wchar_t* tag, const wchar_t* group, double value,
                                const wchar_t* valueStr, const wchar_t* status,
                                uint32_t seq, DWORD* pError) = 0;
    virtual void RemoveByTag(const wchar_t* tag, const wchar_t* group, DWORD* pError) = 0;
    virtual void RemoveAll(DWORD* pError) = 0;
    virtual void RemoveById(uint32_t id, DWORD* pError) = 0;            // Unpackaged は pError=8(NOT_SUPPORTED)
    virtual void GetAll(wchar_t* outJson, uint32_t bufferSize, DWORD* pError) = 0; // Unpackaged は pError=8
    virtual int  Setting() = 0;   // 各 backend が自 enum を共通 int 体系へ変換して返す（指摘7）
};
```

**`WindowsNotificationManager`（共通 orchestration を保持。形態は意識しない）:**
```cpp
class WindowsNotificationManager
{
    // ... 公開メソッド群（Init/Show/Schedule/... シグネチャ不変）...
    void InitWinAppSdk(uint32_t majorMinorVersion, DWORD* pError); // 実装は WindowsAppSdkBootstrap.cpp

    // テスト専用: backend を差し替えて Manager の orchestration を WinRT 非依存で検証（指摘8）
    void SetBackendForTest(std::unique_ptr<INotificationBackend> backend);

    // COM activator(RPC スレッド)から呼ばれる callback 中継（指摘6: スレッド安全）
    void InvokeCallback(const std::wstring& argsJson);

private:
    bool CheckInitialized(const wchar_t* caller, DWORD* pError) const;

    // 共通の前処理（両 backend で共有）
    winrt::...::AppNotificationBuilder BuildFromJson(const winrt::...::JsonObject&, DWORD*);
    DeliverPayload BuildPayload(const winrt::...::JsonObject&, DWORD*); // expiration/progress 適用まで Manager で行う
    std::wstring ArgsToJson(const IMap<hstring,hstring>& args, const IMap<hstring,hstring>& userInput);
    void OnNotificationInvoked(...); // PackagedBackend のイベントから呼ばれる

    std::unique_ptr<INotificationBackend> m_backend;  // ★ Init で1つ生成。形態分岐はここだけ
    NotificationInvokedCallback m_callback = nullptr; // 状態は Manager に一元化
    std::mutex   m_callbackMutex;                     // m_callback の読み書きを保護（指摘6）
    bool m_initialized = false;
};
```

**`PackagedBackend`（新API / `WindowsNotificationManager.cpp` 同TU可）:**
```cpp
class PackagedBackend final : public INotificationBackend { /* AppNotificationManager 実装 */ };
```

**`UnpackagedBackend` + classic activator（新規TU `WindowsClassicActivator.cpp`）:**
```cpp
// WindowsClassicActivator.h（抜粋）
class UnpackagedBackend final : public INotificationBackend
{
public:
    UnpackagedBackend(std::wstring aumid, std::wstring iconPath);
    // RegisterActivation: ショートカット生成 + レジストリ + CoRegisterClassObject
    // Deliver/Schedule/SetBadge/...: CreateToastNotifier(m_aumid) ベース（ToastNotifier は内部に閉じる）
    // RemoveById/GetAll: *pError = NOTIFICATION_ERROR_NOT_SUPPORTED (=8)
private:
    std::wstring m_aumid;     // AUMID は backend が保持（Manager は持たない）
    std::wstring m_iconPath;
    CLSID        m_activatorClsid;  // AUMID から決定的に生成（指摘4: 複数アプリ衝突回避）
    DWORD m_comRegToken = 0;  // CoRegisterClassObject のトークン
};

std::wstring ClassicArgsToJson(const wchar_t* invokedArgs,
                               const struct NOTIFICATION_USER_INPUT_DATA* data, unsigned long count);
```
- classic COM サーバー（`INotificationActivationCallback` / `IClassFactory`）の**実装方式は
  着手前に確定**（指摘5）。`winrt::implements` は `winrt/base.h` の ABI `::IUnknown` と
  classic `::IUnknown`・`<shobjidl.h>` の同居で衝突しやすいため、**`Microsoft::WRL::RuntimeClass`
  もしくは生 `IUnknown`/`IClassFactory` 手実装を推奨**。include 順序（`Unknwn.h` →
  `NotificationActivationCallback.h` → 必要な WinRT は XML 生成用に最小限）を明記する。
- `Activate()` は **callback を直接持たず** `WindowsNotificationManager::GetInstance().InvokeCallback(json)`
  を呼ぶ（状態は Manager に一元化）。`InvokeCallback` は `m_callbackMutex` 下で `m_callback` を
  ローカルコピーし、ロック外で呼ぶ（再入回避 / use-after-null 防止、指摘6）。
- `IClassFactory` + `CoRegisterClassObject`（RegisterActivation）/ `CoRevokeClassObject`（UnregisterActivation）
- ショートカット生成（`CLSID_ShellLink` + `IPropertyStore`）/ レジストリ登録（詳細は「1. 初期化」参照）

> **状態二重化の解消（指摘4）:** `m_isPackaged` も Manager 側 `m_aumid` も持たない。
> 形態は「どの backend が `m_backend` に入っているか」で表現され、AUMID は
> `UnpackagedBackend` 内部にのみ存在する。分岐キーが1つに収束する。

> **スレッド安全（指摘6）:** `Uninit` は `UnregisterActivation()`（`CoRevokeClassObject`）を
> **先に完了**してから `m_callback` を null 化する。revoke 後は新たな `Activate` が来ないため、
> Activate↔Uninit の競合区間が閉じる。`m_callback` 自体は `m_callbackMutex` で保護する。

---

## ドメインエラー一覧

v2 の 0〜7 に **8（NOT_SUPPORTED）を新設**（指摘9）。unpackaged 固有の追加意味づけ:

| エラー定数 | 値 | 追加発生条件 |
|-----------|---|---------------------------|
| `NOTIFICATION_ERROR_NOT_SUPPORTED` | **8（新設）** | unpackaged で `RemoveById` / `GetAll`（classic に数値ID概念が無く非対応） |
| `NOTIFICATION_ERROR_HRESULT_FAILURE` | 5 | ショートカット生成失敗 / `CoRegisterClassObject` 失敗 / `initWinAppSdk` 失敗 |

> `INVALID_PARAMETER`(7) は「引数不正」（badge `value<-6` 等）専用に戻し、「形態的に非対応」は
> 8 で表す。7 の二重意味を解消（指摘9）。

---

## ビルド設定変更

| ファイル | 変更 |
|---------|------|
| `WindowsNotificationBackend.h`（新規） | `INotificationBackend` インターフェース宣言（`ClInclude` に追加） |
| `WindowsLibrary.vcxproj` | `WindowsClassicActivator.cpp/.h`・`WindowsNotificationBackend.h` を `ClCompile`/`ClInclude` に追加 |
| `WindowsLibraryTest.vcxproj` | `WindowsClassicActivator.cpp` を追加してリンク解決（Bootstrap.dll のような実行時依存は無く、テストDLLロードは壊れない） |
| `pch.h` | classic 系ヘッダは追加しない（`WindowsClassicActivator.cpp` 内に隔離） |

> `PackagedBackend` は WinAppSDK のみ使用のため `WindowsNotificationManager.cpp` 同TUに置く。
> `UnpackagedBackend` は classic 依存を持つため `WindowsClassicActivator.cpp` に置く。

> `WindowsAppSdkBootstrap.cpp`（`initWinAppSdk` 実装）は既存どおりテスト未コンパイル
> （`Bootstrap.dll` 依存隔離のため）。

---

## テスト設計

### 単体テスト（CppUnitTest / WinRT 非依存ロジック）

v2 と同一（`BuildFromJson` バリデーション / `ArgsToJson` エスケープ / JSON パース失敗 /
`SetBadge` バリデーション）。**11/11 パス維持を回帰確認**。

**案C の追加単体テスト（backend モック注入 / 指摘8）:**
`SetBackendForTest(make_unique<MockBackend>())` で WinRT 実行時依存なしに Manager の
orchestration を検証する（案C 採用の主要な見返り）:

| テスト | 確認内容 |
|--------|---------|
| `Show` → `MockBackend::Deliver` 呼出 | 共通前処理後に backend へ完成 payload が1回渡る |
| `Schedule` → `MockBackend::Schedule` 呼出 | DateTime 変換・payload 構築が Manager 側で完結 |
| unpackaged `RemoveById`/`GetAll` | `MockBackend` が `pError=8`(NOT_SUPPORTED) を返す |
| 未初期化で各 API | `CheckInitialized` が `pError=1` を返す（CancelScheduled/OpenSettings 含む / 指摘12） |
| `InvokeCallback` のスレッド安全 | `m_callbackMutex` 下でローカルコピー→ロック外呼出（指摘6） |

### 統合テスト（手動）

**A. packaged（VC++ サンプル / MSIX）— 回帰確認（新API経路に変更なし）**

| No | 内容 | 期待 |
|---|------|------|
| P-01〜P-29 | v2 の T-01〜T-29 全項目 | v2 と同じ結果（新API経路は不変） |

**B. unpackaged（Unity Standalone / classic 経路）— 新規確認**

| No | 内容 | 正/異 | 期待 |
|---|------|------|------|
| U-01 | `initWinAppSdk` → `initNotificationManager(isPackaged=FALSE)` | 正 | ショートカット/COM登録成功、pError=0 |
| U-02 | `showNotification` 基本 | 正 | 即時表示 |
| U-03 | `showNotification` ボタン/画像/コンボ/テキスト入力 | 正 | 各要素表示 |
| U-04 | 進捗バー → `updateNotificationProgress` | 正 | 進捗値が更新される（**bind名一致を事前検証済みであること** / 指摘10） |
| U-05 | `scheduleNotification`（+30s / +1m） | 正 | **指定時刻に配信される**（本改修の主目的） |
| U-06 | `cancelScheduledNotification` | 正 | 予約が取消され配信されない |
| U-07 | `setBadge(Alert/1/Clear)` | 正 | **タスクバーにバッジ反映**（本改修の主目的） |
| U-08 | `removeNotificationsByTag` / `removeAllNotifications` | 正 | 通知が消える |
| U-09 | 通知/ボタンをクリック | 正 | **`OnNotificationInvoked` が Unity ログに出る**（activation 完全実装） |
| U-10 | テキスト入力 → ボタンクリック | 正 | argsJson に `reply` が含まれる |
| U-11 | コンボ選択 → ボタンクリック | 正 | argsJson に `combo_selection_id` が含まれる |
| U-12 | 実行中に通知クリック | 正 | アプリが二重起動しない |
| U-13 | アプリ未起動時に通知クリック | 正 | **方針B（確定）**: exe が確実に起動し、起動引数 `-ToastActivated` の自前パースでクリック情報を argsJson 化（ユーザー入力は best-effort）。前提: 過去に一度 Init 済みで登録あり |
| U-14 | `removeNotificationById` | 異 | `pError == 8`（NOT_SUPPORTED）、結果メッセージに明示 |
| U-15 | `getAllNotifications` | 異 | `pError == 8`（NOT_SUPPORTED）、結果メッセージに明示 |
| U-16 | `getNotificationSetting` | 正 | 0（Enabled） |
| U-17 | OS 通知無効化 → `showNotification` | 異 | `pError == 2`（DISABLED） |
| U-18 | `initWinAppSdk` 未呼び出しで `showNotification` | 異 | builder ランタイム未読込でエラー |

---

## 実装タスク分解

```
[Task 0] 着手前の設計決定（PoC含む / 指摘4,5）
  依存: なし / 工数: 0.5日
  ※ cold-start 方針は B で確定済み（2026-06-13）。残りは技術判断。
  作業:
    - classic COM サーバー実装方式の確定（winrt::implements vs WRL/生IUnknown）。
      最小 PoC で MFC ::IUnknown × shobjidl × winrt/base.h の同居ビルド可否を検証
    - activator CLSID の AUMID 決定的生成方式（NameToGuid）確定
  完了条件: COM 実装方式・include 順序・CLSID 生成方式が文書化される

[Task 1] backend インターフェース導入 + PackagedBackend 抽出 + テスト seam
  依存: Task 0 / 工数: 1日
  作業:
    - WindowsNotificationBackend.h に INotificationBackend を定義（json/ToastNotifier を晒さない境界 / 指摘2,3）
    - DeliverPayload 構造体定義（packaged=AppNotification / unpackaged=XML+ProgressData）
    - 既存 AppNotificationManager 実装を PackagedBackend へ移設（同TU）
    - Manager に m_backend(unique_ptr) + BuildPayload(json) を導入。expiration/progress の JSON 解釈は Manager に集約
    - 各公開メソッドを m_backend->Xxx() 委譲へ（メソッド内 if 排除）。Setting() は1回取得し使い回し
    - SetBackendForTest(注入 seam) + MockBackend 単体テスト追加（指摘8）
    - m_callbackMutex 導入 + InvokeCallback（指摘6）
  完了条件: packaged 回帰なし。メソッド本体に形態 if が無い。MockBackend テストが通る
  レビュー観点: 抽象境界（json/classic型の非漏出）、状態一元化、スレッド安全

[Task 2] UnpackagedBackend + classic activator（WindowsClassicActivator.cpp/.h）新規実装
  依存: Task 1 / 工数: 1.5日
  作業:
    - UnpackagedBackend クラス（INotificationBackend 実装、m_aumid/m_iconPath/m_activatorClsid 保持）
    - classic COM サーバー（Task 0 で決めた方式）+ IClassFactory + Co(Register/Revoke)ClassObject
    - ClassicRegister 詳細（CLSID 決定的生成 / LocalServer32 / ショートカット IPropertyStore / 冪等）
    - Activate() → Manager.InvokeCallback 中継 / ClassicArgsToJson
    - 方針B採用時: 起動引数 -ToastActivated の自前パース経路（指摘4）
    - Init で UnpackagedBackend 生成分岐 / vcxproj（本体・テスト）へファイル追加
  完了条件: U-01 / U-09〜U-13 が通る
  レビュー観点: COM ライフサイクル、shell プロパティ、二重起動なし、CLSID 衝突なし、状態一元化

[Task 3] UnpackagedBackend 配信メソッド実装
  依存: Task 2 / 工数: 1日
  作業:
    - [事前] AppNotificationBuilder の <progress> 出力 XML をダンプし bind 名を確認（指摘10）
    - Deliver / Schedule / CancelSchedule / SetBadge / UpdateProgress / RemoveByTag /
      RemoveAll / Setting を classic API で実装（ToastNotifier は backend 内に閉じる）
    - RemoveById / GetAll は pError=8(NOT_SUPPORTED)
    - Setting() の新旧 enum 明示変換（static_cast 素通し禁止 / 指摘7）
    - XML 共用（Manager の payload.xml → XmlDocument）
  完了条件: U-02〜U-08 / U-14〜U-18 が通る
  レビュー観点: NotificationData bind 名一致、History API の aumid オーバーロード、配信成功

[Task 4] 回帰・統合確認
  依存: Task 1〜3 / 工数: 0.5日
  作業:
    - packaged（VC++）P-01〜P-29 の回帰確認
    - unpackaged（Unity）U-01〜U-18 の確認
    - CppUnitTest（v2 11件 + 案C 追加分）パス確認
    - Unity サンプルの pError=8 ハンドリング表示確認
  完了条件: 全項目確認済み
```

**合計工数: 4.5日**（Task 0 の設計決定/PoC +0.5日）

**依存関係:** `Task 0 → Task 1 → Task 2 → Task 3 → Task 4`

---

## リスクと緩和策

| リスク | 深刻度 | 緩和策 |
|-------|-------|-------|
| classic ショートカット未生成で配信されない | 高 | Init で生成成否をログ・pError 化。`%APPDATA%\…\Start Menu\Programs` への書込確認 |
| COM サーバー登録（CoRegisterClassObject）漏れでコールバック不達 | 高 | Init/Uninit でライフサイクル管理。登録失敗時は pError=5 |
| MFC `::IUnknown` と classic COM/WinRT ヘッダの衝突（`winrt::implements` 採用時に顕著） | 中 | classic ヘッダを `WindowsClassicActivator.cpp` に隔離。Task 0 で実装方式（WRL/生IUnknown 推奨）と include 順序を PoC 確認（指摘5） |
| COM activator(RPC スレッド) と Unity スレッドの `m_callback` 競合 / use-after-null | 中 | `m_callbackMutex` で保護しローカルコピー後ロック外呼出。Uninit は revoke→null 化順序（指摘6） |
| 複数アプリ同居時の activator CLSID 衝突 | 中 | CLSID を固定値にせず AUMID から決定的生成（指摘4） |
| packaged の Schedule が classic 経由（新API完結の例外） | 低 | 新API にスケジュール API が無いための制約として明記。`PackagedBackend::Schedule` 内に閉じる（指摘3） |
| classic 進捗 bind 名と builder 出力 XML の不一致で更新無反応 | 低 | Task 3 で実 XML をダンプし bind 名一致を事前検証。U-04 合否基準に含める（指摘10） |
| 未起動時クリックの cold-start activation（C2: COM 起動タイムアウト） | 中（方針B確定で緩和） | **方針B 確定**: COM `Activate` に依存せず、確実な exe 起動 + 起動引数 `-ToastActivated` パースで復元。C2 競合を回避。ユーザー入力のみ best-effort |
| アプリ未起動時のクリックで exe 再起動（Unity 想定外動作） | 中 | desktop toast 仕様として明記。Unity 側でシングルインスタンス/起動引数処理を案内 |
| **unpackaged 配布先に Windows App Runtime 未インストール → 通知機能全体が無効** | 中 | 配布要件として明記。`WindowsAppRuntimeInstall.exe` 事前導入＋Bootstrap.dll 同梱を配布手順に組込む |
| **unpackaged で removeById/getAll 非対応（動作互換性変更）** | 中 | Unity サンプルで pError=8 ハンドリング・非対応表示。Tag ベース削除へ誘導 |
| `RemoveById`/`GetAll` 非対応の混乱 | 低 | pError=8(NOT_SUPPORTED) + 結果メッセージで明示。設計表に記載 |
| テストプロジェクトの新ファイルリンク漏れ | 低 | WindowsLibraryTest.vcxproj に WindowsClassicActivator.cpp を追加 |
| unpackaged で initWinAppSdk 未呼び出し | 低 | builder ランタイム未読込を検出しログ。呼び出し順を Doxygen に明記 |

---

## Definition of Done

- [ ] packaged（MSIX）で v2 全機能が回帰なく動作する（新API経路 不変）
- [ ] unpackaged（Unity）で `showNotification` が表示される
- [ ] unpackaged で `scheduleNotification` が**指定時刻に配信される**
- [ ] unpackaged で `cancelScheduledNotification` が予約を取消す
- [ ] unpackaged で `setBadge`（数値/グリフ/クリア）が**タスクバーに反映される**
- [ ] unpackaged で `updateNotificationProgress` が進捗を更新する
- [ ] unpackaged で `removeNotificationsByTag` / `removeAllNotifications` が動作する
- [ ] unpackaged で `removeNotificationById` / `getAllNotifications` が pError=8（NOT_SUPPORTED）を返す
- [ ] Unity サンプルが上記 pError=8 をハンドリングし非対応メッセージを表示する（互換性変更対応）
- [ ] unpackaged で通知/ボタンクリック（**起動中**）が `NotificationInvokedCallback` を発火する
- [ ] argsJson に reply / combo_selection_id が含まれる（両形態）
- [ ] unpackaged 実行中のクリックでアプリが二重起動しない
- [ ] 終了中クリックで exe が確実に起動し、起動引数 `-ToastActivated` パースでクリック情報を復元する（方針B 確定）
- [ ] Task 0 の設計決定6点（cold-start方針 / COM実装方式 / CLSID生成 / NOT_SUPPORTED / 抽象境界 / packaged例外）が確定している
- [ ] `INotificationBackend` が json / classic 具象型を晒さない（抽象境界の検証）
- [ ] `m_callback` のスレッド安全（mutex + revoke→null化順序）が実装されている
- [ ] backend モック注入の単体テストが追加され、WinRT 非依存で orchestration を検証している
- [ ] unpackaged 配布要件（Windows App Runtime 事前導入 + Bootstrap.dll 同梱 + initWinAppSdk 呼出順）が配布手順に記載されている
- [ ] `getNotificationSetting()` が両形態で正しい値を返す（新旧 enum を明示変換）
- [ ] CppUnitTest が（v2 11件 + 案C 追加分）パスする
- [ ] 公開 C Bridge API のシグネチャが v2 から不変（Unity 側無改修でビルド可。動作互換性のみ変化）
- [ ] 全メソッドに DFLog、公開 API に Doxygen コメントが付与されている
- [ ] Debug|x64 / Release|x64 の両構成でビルドが成功する
```
