# Windows クリップボード機能 実装設計書

- 作成日: 2026-07-28
- 改訂日: 2026-07-29（v2〜v5: レビュー指摘を順次反映 / v5: リクエスト状態機械と層境界を確定）

> **文書の正本規則**: 本設計書と企画書が食い違う場合、**下記「企画書へ反映が必要な差分」に列挙した項目については本設計書を正本とする**。それ以外は企画書を正本とする。列挙項目は実装開始前に企画書へ反映する。
- 対象OS: Windows 11 以降
- 対象機能: クリップボード（Clipboard）
- 使用言語: VC++（Win32 コア = C++17 / WinRT 履歴 = C++20）
- 対象企画書: `artifact/plans/clipboard/2026-07-27-windows-clipboard-research.md`

---

## 設計目的

企画書で確定した方針（Win32 をコア、WinRT を履歴に限定、履歴 Bridge は非同期コールバック）を、`windows/WindowsLibrary` の既存構成へ落とし込み、実装に着手できる粒度まで分解する。

企画書由来の前提と、本設計で新たに決めた事項を明確に分離して記載する。

---

## スコープ

### In scope

企画書の S-01〜S-20 を実装対象とする。本設計での実装単位は以下。

| No | サブ機能 | 企画書 | 実装単位 |
|---|---|---|---|
| F-01 | プレーンテキストのコピー / ペースト | S-01 | Win32 |
| F-02 | HTML のコピー / ペースト | S-02 | Win32 |
| F-03 | ファイル一覧のコピー / ペースト | S-03 | Win32 |
| F-04 | 画像（DIB）のコピー / ペースト | S-04 | Win32 |
| F-05 | 独自フォーマットのコピー / ペースト | S-05 | Win32 |
| F-06 | 複数フォーマットの同時配置 | S-06 | Win32 |
| F-07 | 内容確認（有無 / 列挙 / 優先度 / 名前） | S-07 | Win32 |
| F-08 | クリア | S-08 | Win32 |
| F-09 | 変更監視 | S-09 | Win32 + toolkit 所有の配送用ウィンドウ |
| F-10 | 遅延レンダリング | S-10 | Win32 + 予約テーブル |
| F-11 | 履歴 / 同期からの除外 | S-11 | Win32 登録フォーマット |
| F-12 | 履歴の取得 / 復元 / 削除 / 消去 / イベント / 可用性 | S-12〜S-15 | WinRT + 非同期 Bridge |
| F-13 | Package Identity 対応 | S-16 | 分岐なしで両対応 |
| F-14 | エラー正規化 | S-17 | Domain エラー |
| F-15 | 境界検証 | S-18 | 純ロジック |
| F-16 | MFC × C++/WinRT 共存ビルド | S-19 | プロジェクト設定 |
| F-17 | スレッドモデル / Bridge ライフサイクル | S-20 | UI 配送基盤 |

### Out of scope

- 企画書の Out of scope をそのまま引き継ぐ（OLE ドラッグ&ドロップ、`CF_OWNERDISPLAY` 実運用、旧来フォーマット実装、旧ビューアチェーン、EDP、Share 機能、`SetDataProvider`）
- **サンプルアプリの実装**（`windows/WindowsLibraryExample`）は `design-sample-app` の範囲。本設計ではタスクの完了条件のみ定義し、ファイルパスは記載しない
- `docs/` 配下（固定で対象外）
- Unity C# 側の実装（`unity-native-plugin` プロジェクト側の責務）

---

## 共通実装方針の適用チェック（common.md 準拠）

| 項目 | 適用 | 本設計での対応 |
|---|---|---|
| Clean Architecture の層と依存方向 | 適合 | Domain → Application → Data → Manager → Unity Bridge。`windows.md` の VC++ 対応表に従う |
| 層とモジュールの対応 | 適合 | **Manager 層までは `windows/WindowsLibrary`**。`windows/UnityWindowsPlugin` には Bridge 層のみ |
| system Delegate / Listener の所有 | 適合 | 変更監視ウィンドウ（`ClipboardWatcher`）と履歴イベント（`HistoryWatcher`）は **`WindowsLibrary` 側の Manager が所有**。Unity プラグインには置かない |
| Manager → UseCase → Repository | 条件付き適合 | `windows.md` の段階適用に従い、既定はフラット構造。**境界検証と CF_HTML 変換は純ロジックとして分離**し、Repository 境界は F-12（WinRT 隔離）にのみ導入する（下記「層の適用判断」参照） |
| Port の型制約 | 適合 | Repository 境界を作る F-12 で、Port は Domain 型のみを使う（`winrt::` 型を出さない） |
| エラー変換フロー | 適合 | システムエラー → Repository/Manager → `CLIPBOARD_ERROR_*` → Bridge の `DWORD* pError` / コールバック引数 |
| TDD | 適合 | 純ロジック（境界検証・CF_HTML・DROPFILES・DIB）を WinRT / Win32 非依存にして `WindowsLibraryTest` で先にテスト |
| テストフレームワーク | 適合 | 既存 `WindowsLibraryTest` と同じ MSTest（`Microsoft::VisualStudio::CppUnitTestFramework`） |
| Unity Bridge は薄く保つ | 適合 | `UnityWindowsClipboardManager` は Manager 呼び出しのみ。複雑なデータは JSON 文字列 |
| サンプルアプリの依存方向 | 適合 | `WindowsLibraryExample` は `WindowsLibrary` のみに依存。全サブ機能をネイティブから利用可能にする |
| 最小 OS バージョン | 適合 | Windows 11 以降 |

### 層の適用判断（新規設計判断）

`windows.md`「段階適用のトリガー（ROI 順）」に従い、次のとおり判断する。

| トリガー | 判断 | 理由 |
|---|---|---|
| 1. 純ロジックの抽出（必須） | **適用する** | CF_HTML ヘッダ生成/解析、DROPFILES 構築/検証、DIB 検証、checked 演算、フォーマット優先度判定を WinRT/Win32 非依存にして単体テストする |
| 2. Manager の機能単位ファイル分割 | **適用する** | Win32 コア・監視・遅延レンダリング・WinRT 履歴で関心が分かれ、1 ファイルでは肥大化が確実なため最初から分割する |
| 3. Repository 境界の導入 | **F-12 のみ適用する** | WinRT 履歴は実機依存が強く、Manager のロジック（ステータス変換・pending 管理）を WinRT 抜きでテストしたい。Win32 コアは薄いラッパで非自明なロジックがないため導入しない |
| 4. UseCase の導入 | **F-12 のみ coordinator を導入する** | Win32 コア（F-01〜F-11）は素通しなので作らない（`windows.md` の「素通しの操作には作らない」）。一方 **F-12 は pending / キャンセル / shutdown / エラー変換を持つ非自明な状態機械**であり、`windows.md` のトリガー 4（状態機械・調整を持つ操作）に該当する（レビュー指摘 M7） |

**F-12 の coordinator（新規設計判断）**: 操作ごとの UseCase クラスを 6 個作るのではなく、**リクエストのライフサイクルを担う 1 クラス `ClipboardHistoryCoordinator` を Application 層相当として置く**。非自明なロジック（受付・pending・キャンセル・ドレイン・エラー変換）が操作横断で共通であり、操作ごとに分割すると同じ状態機械が重複するため。

```
Manager（公開 API・dispatchHwnd 所有）
   └→ ClipboardHistoryCoordinator（受付 / pending / キャンセル / ドレイン / エラー変換）
        └→ IClipboardHistoryBackend（Port）
             └→ ClipboardHistoryWinRt（Data / WinRT 隔離）
```

Manager は Repository（backend）を直接呼ばず coordinator を経由するため、`common.md` の「Manager は UseCase 経由で Data 層にアクセスする」を満たす。Win32 コアは Manager から `WindowsClipboardCore` を直接呼ぶが、これは非自明なロジックを持たない薄いラッパであり `windows.md` の段階適用に従った意図的な選択である。

---

## 個別実装方針の適用チェック（windows.md 準拠）

| 項目 | 適用 | 本設計での対応 |
|---|---|---|
| 基本構造（Manager + C Bridge のフラット） | 適合 | `WindowsClipboardManager` を単一の公開窓口とし、Bridge は委譲のみ |
| ログ（全メソッド先頭に DLog / DFLog） | 適合 | 公開関数・Manager の公開/内部メソッドに TAG 付きで入れる。data model / 前方宣言は除外 |
| Doxygen コメント | 適合 | 公開ヘッダの関数・typedef・エラー定数に付与 |
| コメント / メッセージは英語 | 適合 | コード内コメントは英語。設計書（本書）は日本語 |
| 文字列は `wchar_t*` / `std::wstring` | 適合 | 公開 API は `const wchar_t*` / 出力バッファ + `buffer_size` |
| `extern "C"` + `dllexport` | 適合 | `WINDOWSCLIPBOARDMANAGER_API` マクロを定義し `.def` にエクスポート追記 |
| バッファ受け取り API は `buffer_size` 必須 + 境界チェック | 適合 | 全読み取り API が `buffer_size`（wchar_t 要素数 / バイト数）を取る |
| エラーは `DWORD* pError` で返す | 適合 | 同期 API は `pError`、非同期 API はコールバック引数 |
| **同期 / 非同期の方針** | 適合 | 下表で判断（本設計の中核） |
| 実装の落とし穴（文字コード / STA / ポンプ / DFLog バッファ） | 適合 | `/utf-8` 適用、STA で `get()` 禁止、監視ウィンドウのポンプ要件を明記 |

### 同期 / 非同期の判断（windows.md の判断表への当てはめ）

| 本機能のサブ機能 | システム API の性質 | 公開 Bridge の形 | 根拠 |
|---|---|---|---|
| F-01〜F-08, F-10, F-11 | 同期・呼び出しスレッドのアフィニティ要件なし（Win32） | **同期**（`DWORD* pError`） | 判断表 1 行目 |
| F-09 変更監視 | 同期登録 + メッセージ通知 | **同期登録 + 変更コールバック** | 登録自体は同期。通知は所有ウィンドウのポンプ経由 |
| F-12 履歴（同期 WinRT: `SetHistoryItemAsContent` / `ClearHistory` / `IsHistoryEnabled`） | 同期・UI スレッド + フォアグラウンド要件あり | **UI 配送 + 完了コールバック** | 判断表 2 行目（任意スレッド対応のため） |
| F-12 履歴（非同期 WinRT: `GetHistoryItemsAsync`） | 非同期・UI スレッド + フォアグラウンド要件あり | **非同期コールバック** | 判断表 4 行目 |
| （不採用）MTA ワーカー + `wait_for` | 非同期・アフィニティ要件なしの場合の方式 | — | `Clipboard` は要件があるため該当しない |

---

## 既存実装差分サマリー

### 既存構成（変更前）

```
windows/
├── WindowsLibrary/            ネイティブライブラリ（Manager 層まで）
│   ├── WindowsDialogManager.{h,cpp}
│   ├── WindowsNotificationManager.{h,cpp}
│   ├── WindowsNotificationManagerInternal.h
│   ├── WindowsNotificationBackend.h        ← Repository 境界の既存例（抽象基底クラス）
│   ├── WindowsClassicActivator.{h,cpp}
│   ├── WindowsAppSdkBootstrap.cpp
│   ├── common.{h,cpp}                      ← DLog / DFLog / ToWString
│   ├── pch.h                               ← MFC → WinRT のヘッダ順序
│   └── WindowsLibrary.def                  ← エクスポート一覧
├── UnityWindowsPlugin/        Unity Bridge 層のみ
│   └── UnityWindowsDialogManager.{h,cpp}
├── WindowsLibraryTest/        MSTest
│   └── NotificationManagerTest.cpp
└── WindowsLibraryExample/     WinUI 3 サンプル（design-sample-app の範囲）
```

### 追加ファイル（本設計）

| パス | 層 | 内容 |
|---|---|---|
| `windows/WindowsLibrary/WindowsClipboardManager.h` | Manager / Bridge 宣言 | 公開 C API、エラー定数、コールバック typedef |
| `windows/WindowsLibrary/WindowsClipboardManager.cpp` | Manager | Bridge 実装 + Manager 本体（初期化 / 破棄 / ディスパッチ） |
| `windows/WindowsLibrary/WindowsClipboardManagerInternal.h` | Manager 内部 | Manager クラス定義、pending テーブル、内部型（テストから参照） |
| `windows/WindowsLibrary/WindowsClipboardCore.{h,cpp}` | Data 相当 | Win32 クリップボード操作（RAII、コピー / ペースト / 列挙 / クリア） |
| `windows/WindowsLibrary/WindowsClipboardFormats.{h,cpp}` | Domain 純ロジック | CF_HTML 生成/解析、DROPFILES 構築/検証、DIB 検証、checked 演算 |
| `windows/WindowsLibrary/WindowsClipboardWindow.{h,cpp}` | Presentation 相当 | `dispatchHwnd`（自前 WndProc）、監視、遅延レンダリング、UI 配送 |
| `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.{h,cpp}` | Application | 履歴リクエストの状態機械（受付 / pending / キャンセル / ドレイン / エラー変換） |
| `windows/WindowsLibrary/WindowsClipboardHistoryBackend.h` | Application Port | WinRT 履歴の抽象基底クラス（純粋仮想） |
| `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.{h,cpp}` | Data | WinRT 実装（`Clipboard` 呼び出しを隔離） |
| `windows/WindowsLibraryTest/ClipboardFormatsTest.cpp` | Test | 純ロジックの単体テスト |
| `windows/WindowsLibraryTest/ClipboardManagerTest.cpp` | Test | Manager のオーケストレーション（Mock backend） |
| `windows/UnityWindowsPlugin/UnityWindowsClipboardManager.{h,cpp}` | Unity Bridge | Manager への委譲のみ |

### 変更ファイル

| パス | 変更内容 |
|---|---|
| `windows/WindowsLibrary/WindowsLibrary.def` | クリップボード Bridge 関数のエクスポート追加 |
| `windows/WindowsLibrary/WindowsLibrary.vcxproj`（+ `.filters`） | 追加 `.cpp` の登録、`/std:c++20` 設定（下記の要検証） |
| `windows/WindowsLibrary/pch.h` | `winrt/Windows.ApplicationModel.DataTransfer.h` の追加 |
| `windows/WindowsLibraryTest/WindowsLibraryTest.vcxproj` | 追加テストファイルの登録 |
| `windows/UnityWindowsPlugin/UnityWindowsPlugin.def` / `.vcxproj` | Bridge 関数のエクスポート追加 |

### 破壊的変更

**なし。** 既存の Dialog / Notification の公開 API・シグネチャ・エラー定数に変更を加えない。追加のみ。

要検証: `/std:c++20` への切り替えがプロジェクト全体設定になるか、ファイル単位設定にできるか。全体切り替えの場合、既存の Notification / Dialog コードが C++20 でビルドできることを先行タスク T-01 で確認する。

---

## 実装アーキテクチャ

```
Unity C# (P/Invoke)                     WindowsLibraryExample (WinUI 3)
        │                                        │
        ▼                                        │
UnityWindowsClipboardManager                     │  ネイティブから直接
（UnityWindowsPlugin / Bridge 層）                │  Manager の公開 API を利用
        │                                        │
        ▼                                        ▼
┌──────────────────────────────────────────────────────────┐
│ WindowsClipboardManager.h / .cpp                          │
│  extern "C" C Bridge API（薄いファサード）                 │
│        │                                                  │
│        ▼                                                  │
│  ClipboardManager (singleton)                             │
│   - 初期化 / 破棄、shutdown gate、CanDestroy               │
│   - pending テーブル（リクエスト ID / コールバック）        │
│   - UI スレッド判定と dispatchHwnd への PostMessage 配送    │
└───────┬──────────────────────┬───────────────────────────┘
        │                      │
        ▼                      ▼
WindowsClipboardCore    WindowsClipboardWindow
（Win32 同期操作）        （toolkit 所有の dispatchHwnd + 自前 WndProc）
        │                  - ClipboardWatcher（変更監視）
        │                  - DeferredClipboard（遅延レンダリング）
        │                  - UI 配送メッセージ受信
        ▼                      │
IClipboardWin32Api             ▼
（失敗注入 seam）        IClipboardHistoryBackend（抽象基底 / 非同期 Port）
        │                      │
        ▼                      ▼
WindowsClipboardFormats  ClipboardHistoryWinRt
（純ロジック / テスト対象）（WinRT Clipboard 呼び出しを隔離）
```

### Win32 API の失敗注入 seam（レビュー指摘 M4 反映）

`SetClipboardData` / `EmptyClipboard` / `RemoveClipboardFormatListener` の失敗は実クリップボードでは再現困難なため、関数テーブルを抽象化して注入可能にする。

```cpp
// WindowsClipboardCore.h — thin function table over the Win32 clipboard API.
// Production uses the real API; tests inject a stub that can fail on demand.
class IClipboardWin32Api
{
public:
    virtual ~IClipboardWin32Api() = default;
    virtual BOOL    OpenClipboard(HWND owner) = 0;
    virtual BOOL    CloseClipboard() = 0;
    virtual BOOL    EmptyClipboard() = 0;
    virtual HANDLE  SetClipboardData(UINT format, HANDLE hMem) = 0;
    virtual HANDLE  GetClipboardData(UINT format) = 0;
    virtual HWND    GetClipboardOwner() = 0;
    virtual BOOL    IsClipboardFormatAvailable(UINT format) = 0;
    virtual BOOL    AddClipboardFormatListener(HWND hwnd) = 0;
    virtual BOOL    RemoveClipboardFormatListener(HWND hwnd) = 0;
    virtual DWORD   GetClipboardSequenceNumber() = 0;
};

IClipboardWin32Api& DefaultWin32Api();                 // production singleton
void SetWin32ApiForTest(IClipboardWin32Api* api);      // test-only injection point
```

`ClipboardScope` / `DeferredClipboard` / `ClipboardWatcher` はこのインターフェース経由で呼ぶ。純粋な `GlobalAlloc` / `GlobalLock` は `GlobalMem` / `GlobalLockScope` の RAII 内に閉じ込め、確保失敗のテストはサイズ上限注入で行う。

### HWND の役割分離（レビュー指摘 H2 反映）

**ホストの HWND と toolkit の配送用 HWND は別物であり、混同してはならない。** ホストのウィンドウに `AddClipboardFormatListener` を掛けたり `PostMessage` を送っても、そのウィンドウの WndProc はホストのものであり、toolkit のハンドラは呼ばれない。

| HWND | 生成者 | 用途 |
|---|---|---|
| `dispatchHwnd`（toolkit 所有） | **toolkit が所有 UI スレッド上で生成**（自前 WndProc） | `WM_CLIPBOARDUPDATE` / `WM_RENDERFORMAT` / `WM_RENDERALLFORMATS` / `WM_DESTROYCLIPBOARD` の受信、`WM_APP_CLIPBOARD_REQUEST` による UI 配送、`SetClipboardData` の owner、`AddClipboardFormatListener` の登録先 |
| `foregroundHwnd`（ホスト所有） | ホスト | **フォアグラウンド判定にのみ使う参照**（`GetForegroundWindow()` との比較）。listener 登録・`PostMessage`・clipboard owner には使わない |

**`dispatchHwnd` の生成契約（新規設計判断）**

- **`initClipboardManager` を最初に呼んだスレッドを所有 UI スレッドとして採用する（adopt 方式）。** 「そのスレッドがメッセージポンプを回していること」は**呼び出し側の事前条件**であり、Win32 では一般に検出できないため実行時に判定しない（レビュー指摘 M1）。事前条件は Doxygen とマニュアルに明記する
- 初期化後は所有スレッド ID が確定するため、**UI スレッド限定 API（`uninitClipboardManager` / `setClipboardHistoryCallbacks`）は `GetCurrentThreadId()` との比較で `CLIPBOARD_ERROR_WRONG_THREAD` を返せる**
- 二重 `init` は、同一スレッドからなら成功（冪等）、別スレッドからなら `WRONG_THREAD` を返す

**アパートメントの事前条件（レビュー指摘 H6 反映）**

WinRT `Clipboard` を開始するスレッドは、メッセージポンプに加えて**適切なアパートメント初期化**が必要。adopt 方式では toolkit がホストのスレッドを初期化しないため、事前条件として要求する。

| 項目 | 契約 |
|---|---|
| 事前条件 | 呼び出しスレッドが **STA として初期化済み**であること（`CoInitializeEx(COINIT_APARTMENTTHREADED)` / `winrt::init_apartment(apartment_type::single_threaded)` 相当） |
| 検査 | `init` で `CoGetApartmentType()` を呼び、`APTTYPE_STA` / `APTTYPE_MAINSTA` 以外なら `CLIPBOARD_ERROR_WRONG_APARTMENT` を返して初期化しない |
| 未初期化 / MTA の扱い | 上記エラーで失敗させる。toolkit 側で勝手に初期化しない（ホストのアパートメントを固定すると `RPC_E_CHANGED_MODE` を誘発するため。`windows.md` の既存方針） |
| 解除 | **toolkit は `uninit_apartment` を呼ばない**（初期化していないため）。ホストの責務 |
| 将来の代替案 | toolkit が専用 UI スレッドを持つ構成に切り替える場合のみ、そのスレッド内で `init_apartment` / `uninit_apartment` を対で呼ぶ（現行の adopt 方式では使用しない） |
- toolkit は自前のウィンドウクラス（`NativeToolkitClipboardWindow`）を登録し、そのスレッド上に非表示のトップレベルウィンドウを生成する
- **メッセージ専用ウィンドウ（`HWND_MESSAGE`）は使わない。** `WM_CLIPBOARDUPDATE` が届くかが未検証（企画書の要検証事項）であり、確実性を優先して非表示トップレベルウィンドウとする。T-05 の実機確認で `HWND_MESSAGE` でも届くと判明した場合に切り替える
- ホストのウィンドウをサブクラス化する方式は採らない（ホストの WndProc 契約を壊すため）

### スレッド構成

| スレッド | 役割 |
|---|---|
| 呼び出しスレッド（任意） | Bridge 入口。同期 Win32 API はここで完結。UI 要件のある操作は `dispatchHwnd` へ `PostMessage` して配送のみ行う |
| 所有 UI スレッド | `dispatchHwnd` を所有し、メッセージポンプを回す。WinRT 履歴の開始と `co_await` 再開、クリップボードメッセージの受信、**全ての完了コールバックの呼び出し** |

**コールバック実行スレッドの契約（レビュー指摘 M2 反映）**

- **全ての完了コールバック（`ClipboardRequestCallback` / `ClipboardChangedCallback` / 履歴イベント）は所有 UI スレッド上で呼ばれる。** キャンセル・`Uninit` によるドレイン・フォアグラウンド判定失敗の通知も同じ
- **全てのコールバックは公開 API から復帰した後に発火する。** UI スレッドから呼ばれた場合も必ず `PostMessage` を経由し、Bridge 関数の内部からコールバックを呼ばない（再入防止）
- 呼び出し元スレッドへ戻す処理は行わない。呼び出し側（Unity C# / サンプルアプリ）が必要に応じて自身のスレッドへマーシャリングする
- コールバック内から `uninitClipboardManager` / `setClipboardHistoryCallbacks` を呼んではならない（再入により shutdown gate が壊れるため）。Doxygen に明記し、デバッグビルドで `WINRT_ASSERT` を置く

---

## 同時実行とライフサイクル契約（レビュー指摘 H1 / H2 / H3 / H5 反映）

本設計で最も事故が起きやすい領域であり、実装前に確定させる。

### 統一ライフサイクル状態（`ClipboardLifecycle`）

request コルーチン・イベントコールバック・任意スレッドの同期 API を**同一の状態で管理する**。`CanDestroy` の判定と入場を同じロックで行うことで、「判定直後に入場する」競合をなくす。

```cpp
// Owned by the Manager via shared_ptr. Coroutines and event handlers capture a
// weak_ptr, never `this`. Destruction of the backend/window is gated on this state.
class ClipboardLifecycle
{
public:
    class Lease;                        // RAII: decrements inFlight_ on destruction

    // Atomically: fails when already closed, otherwise takes a lease.
    // A lease covers request coroutines, event callbacks AND any-thread sync APIs.
    std::optional<Lease> TryEnter();

    // Closes the gate AND reserves closing work in one atomic step, so queued drain
    // callbacks keep CanDestroy() false even though TryEnter() now fails.
    void CloseAndReserveDrainWork(size_t drainCount);
    void ReleaseDrainWork();            // once per delivered drain callback

    bool IsClosed() const;
    bool CanDestroy() const;            // closed_ && inFlight_ == 0 && drainWork_ == 0

private:
    mutable std::mutex mutex_;
    bool   closed_ = false;
    int    inFlight_ = 0;               // requests + event callbacks + sync calls
    size_t drainWork_ = 0;              // queued cancellation callbacks not yet delivered
};
```

| 対象 | lease の取得タイミング | 解放タイミング |
|---|---|---|
| request（`Queued`） | 受付成立時 | **開始前キャンセル / ドレインでエントリが破棄された時** |
| request（`Running`） | 受付時の lease をコルーチンフレームへ move | **コルーチンが完全に終了した時**（キャンセル後・例外終端も含む） |
| イベントコールバック | ハンドラ入場時 | ハンドラ退場時 |
| 任意スレッドの同期 API | Bridge 関数の入口 | Bridge 関数の出口 |
| ドレイン済みコールバック | `CloseAndReserveDrainWork` で件数を予約（lease ではない） | 各コールバック発火後の `ReleaseDrainWork()` |

`Close` 後は `TryEnter` が失敗するため、キューに積んだドレインコールバックは lease を取れない。そのため closing-work カウンタで別途数え、`CanDestroy` の判定に含める（レビュー指摘 H5）。

**キャンセルはコルーチンを即座に終わらせない。** `cancelClipboardRequest` は完了権を take してコールバックを 1 回発火するだけで、開始済みの WinRT operation は（可能なら `Cancel()` を呼びつつ）完了まで走り切る。lease はコルーチン終了まで保持されるため、backend / Manager はその間破棄されない。

### 状態所有スレッドの規約（レビュー指摘 H2）

| 状態 | 所有スレッド | 任意スレッドからのアクセス |
|---|---|---|
| `DeferredClipboard::renderers_` / `rendered_` / `partial_` / `owner_` | **所有 UI スレッドのみ** | 不可。`reserveDeferredFormats` / `recoverDeferredState` を **UI スレッド限定 API** にして構造的に防ぐ |
| `ClipboardWatcher::registered_` / `hwnd_` / `lastSeq_` | **所有 UI スレッドのみ** | 不可 |
| `ClipboardWatcher::selfWriteSeq_`（自書き込み履歴） | 任意スレッドから追加、UI スレッドから参照 | **小さな mutex で保護したリングバッファ**（後述） |
| pending テーブル | 任意スレッドから登録 / 取り出し | **mutex で保護**。取り出しはアトミック |
| `ClipboardLifecycle` | 任意スレッド | **mutex で保護** |
| OS クリップボード本体 | — | `ClipboardScope` の `OpenClipboard` が OS レベルで排他する |

**ロック方針**

- `ClipboardLifecycle` と pending テーブルはそれぞれ独立した mutex を持ち、**同時に 2 つを保持しない**（デッドロック防止）
- **provider コールバック（`ClipboardRenderCallback`）と公開コールバックを呼ぶ間は、いかなる mutex も保持しない。** 呼び出し側コードからの再入を許容するため
- Win32 の同期 API 実行中はロックを取らない（`OpenClipboard` の排他に任せる）

### `uninit` との競合（レビュー指摘 H1 / H5）

**ドレインもコールバック非再入契約を守る**（レビュー指摘 H2 反映）。`uninitClipboardManager` の内部から pending コールバックを直接呼ぶと「全コールバックは公開 API 復帰後」の契約に違反するため、**ドレインはキャンセル完了メッセージを UI キューへ積むだけ**にし、実際の発火は `uninit` から復帰した後のメッセージ処理で行う。

```
uninitClipboardManager(pError)   ← 所有 UI スレッド / コールバック外
  1. pending をロックし、全エントリの完了権を取り出して drain キューへ移す（pending は空になる）
     同じ操作内で lifecycle.CloseAndReserveDrainWork(取り出した件数) を呼ぶ
     ※ Queued のエントリはここで入力値と lease も破棄される
     ※ 以降にコルーチンが完走しても完了権がないため take に失敗し、結果を捨てる
  2. drain キューの各項目へ CANCELED の完了メッセージを UI キューへ PostMessage
     （この時点ではコールバックを呼ばない。発火は uninit 復帰後のメッセージ処理）
  3. ClipboardWatcher::Stop()       失敗なら FALSE（gate は閉じたまま。再呼び出しで再試行）
  4. backend->StopWatch()           失敗なら FALSE（revokePending_ を保持し Start を拒否）
  5. lifecycle.CanDestroy()         false なら FALSE
     （in-flight コルーチン / 同期 API、または未配送のドレインコールバックが残っている）
  6. DeferredClipboard が PARTIAL_STATE なら RecoverFromPartialState()
  7. 3〜5 が全て成立してから dispatchHwnd を DestroyWindow、backend を破棄
  → 全て完了で TRUE
```

**重複投入の防止**: 手順 1 で pending は空になるため、`uninit` を再度呼んでも取り出す完了権がなく、同じキャンセルメッセージが二重に積まれることはない（`CloseAndReserveDrainWork(0)` は何も予約しない）。

**必ず 2 回以上呼ぶ設計**: pending が 1 件でもあれば初回は必ず `FALSE` を返す。呼び出し側はメッセージポンプを回して積んだ完了を処理させ、その後に再度 `uninit` を呼ぶ。**キューに積んだコールバックが発火する前に `dispatchHwnd` を破棄しない**ため、コールバックが失われることも、破棄済みウィンドウへ配送されることもない。

**再試行の契約**: `FALSE` が返った場合、gate は閉じたままなので新規要求は受け付けない。呼び出し側は `canDestroyClipboardManager()` で状態を確認しながら `uninitClipboardManager()` を再度呼ぶ。**メッセージポンプを回し続ける必要がある**（積んだ完了の処理と in-flight コルーチンの再開に必要）ため、UI スレッドをブロックするループで再試行してはならない。

### リクエストの状態機械と所有権（レビュー指摘 H1 / H4 反映）

受付からコルーチン開始までの間（Bridge 復帰 〜 WndProc 受信）にも入力値と lease の所有者が必要なため、**pending エントリが `Queued` 状態の実行データを保持する**構造にする。

```
                 [任意スレッド]                    [所有 UI スレッド]
Accepted ──────────────────────────────────────────────────────────────
  RequestEntry を生成し pending へ登録            WndProc が ID を受信
  { id, callback, inputs(コピー), lease,          → Queued の inputs/lease を
    state = Queued }                                コルーチンフレームへ move
  PostMessage(id)                                 → state = Running
                                                  → 開始（下記 allocation 失敗に注意）
                                                          │
                                          コルーチン完走 → 完了権を take
                                                          → 取れたら callback、
                                                            取れなければ結果を破棄
                                                          → state = Finished、entry 削除
```

| 状態 | 保持する場所 | 内容 |
|---|---|---|
| `Queued` | **pending エントリ** | ID、コールバック関数ポインタ（＝完了権）、**入力値のコピー**、**lease** |
| `Running` | 完了権とオペレーションハンドルは pending エントリ、**入力値と lease はコルーチンフレーム** | 実行中 |
| `Finished` | — | エントリ削除 |

- **開始前のキャンセル / ドレイン**: エントリを take した側が `Queued` の入力値と lease を破棄する（lease はここで解放される）。コルーチンは開始されない
- **実行中のキャンセル**: 完了権のみを take してコールバックを発火。可能なら保持している WinRT operation の `Cancel()` を呼ぶ（best-effort）。コルーチンは完走し、take に失敗して結果を捨てる
- lease は `Queued` ではエントリが、`Running` ではコルーチンフレームが持つため、**受付からコルーチン終了まで途切れない**

### コルーチン生成失敗の扱い（レビュー指摘 H3 反映）

コルーチンフレームの確保と引数の move は、本体の `try` に入る**前**に失敗し得る。エントリ関数を `noexcept` にすると、この失敗が `OUT_OF_MEMORY` へ変換されず `std::terminate` する。

- **コルーチンのエントリ関数に `noexcept` を付けない**
- **WndProc 側の開始呼び出しを `try/catch` で囲み**、例外時は pending エントリを `OUT_OF_MEMORY` で終端する（受付後なのでコールバックはちょうど 1 回発火する）
- 完了ヘルパ（`CompletePendingRequest` 系）は引き続き `noexcept`

```cpp
// WndProc side: the start call is the last place where a failure can still be
// converted into a normal completion.
case WM_APP_CLIPBOARD_REQUEST:
{
    const uint32_t id = static_cast<uint32_t>(wParam);
    try            { manager->StartQueuedRequest(id); }   // may throw on frame allocation
    catch (...)    { manager->CompleteWithError(id, ClassifyStartFailure()); }
    return 0;
}
```

### shutdown 時のドレイン（レビュー指摘 H4 / H5 反映）

`Close()` 後もエントリを pending に残すと、キャンセルメッセージより先にコルーチンが通常完了して完了権を take し、**失効させたはずの要求へ成功コールバックが出る**。これを防ぐため、**Close と同時に全ての完了権を一括 take する**。

```cpp
class ClipboardLifecycle
{
public:
    class Lease;
    std::optional<Lease> TryEnter();

    // Closes the gate AND reserves closing work in one atomic step, so that queued
    // drain callbacks keep CanDestroy() false even though TryEnter() now fails.
    void CloseAndReserveDrainWork(size_t drainCount);
    void ReleaseDrainWork();            // called once per delivered drain callback

    bool IsClosed() const;
    bool CanDestroy() const;            // closed_ && inFlight_ == 0 && drainWork_ == 0

private:
    mutable std::mutex mutex_;
    bool   closed_ = false;
    int    inFlight_ = 0;               // requests + event callbacks + sync calls
    size_t drainWork_ = 0;              // queued cancellation callbacks not yet delivered
};
```

ドレイン手順:

1. pending テーブルをロックし、**全エントリの完了権を取り出して専用の drain キューへ移す**（この時点で pending は空になる）
2. 同じ操作の中で `CloseAndReserveDrainWork(取り出した件数)` を呼ぶ
3. drain キューの各項目について `PostMessage` でキャンセル完了を積む
4. 以降にコルーチンが完走しても完了権は既にないため take に失敗し、結果を捨てる（**誤った成功コールバックが出ない**）
5. 各ドレインコールバックの発火後に `ReleaseDrainWork()` を呼ぶ
6. `uninit` の再呼び出しでは pending が空なので**同じキャンセルメッセージを重複投入しない**

`Queued` のまま取り出されたエントリは、入力値と lease もここで破棄される。

### pending request の所有権（レビュー指摘 H5）

| 項目 | 契約 |
|---|---|
| 完了権の所有者 | **pending テーブル**（コールバック関数ポインタとリクエスト ID のみ） |
| 実行状態の所有者 | **コルーチンフレーム**（入力コピー・WinRT operation・lease） |
| メッセージが運ぶもの | **リクエスト ID のみ**（`WPARAM`）。ポインタは渡さない |
| 取り出し | ID による atomic take。取り出せた者だけが完了処理を行う（完了 / キャンセル / ドレインの三者を排他） |
| `cancelClipboardRequest` の呼び出しスレッド | 任意。内部で UI スレッドへ配送し、UI スレッド上で take → コールバック発火 |
| 二重完了 | atomic take により構造的に不可能 |
| 再入 | 呼び出しスレッドを問わず必ず `PostMessage` を経由するため、公開 API 復帰前にコールバックが呼ばれることはない |

**受付成立点の統一（企画書からの絞り込み）**: 企画書は「非 UI スレッド経路 = `PostMessage` 投入」「UI スレッド経路 = 直接開始への引き渡し」の 2 経路を許容しているが、**本設計では経路を統一し、常に `PostMessage` を経由する**。企画書の受付契約（受付前 0 回 / 受付後ちょうど 1 回）はそのまま満たしつつ、UI スレッドからの同期完了による再入を構造的に排除する。企画書の 2 経路記述は本設計では使用しない。

---

## サブ機能別詳細設計

### F-01〜F-08, F-11: Win32 同期コア

**変更対象モジュール**: `WindowsClipboardCore.{h,cpp}`, `WindowsClipboardFormats.{h,cpp}`

**制御フロー（共通）**

```
Bridge 関数
  1. 引数検証（null / サイズ 0 / 未初期化）→ CLIPBOARD_ERROR_INVALID_PARAMETER
  2. ClipboardScope でオープン（リトライ 10 回 / 10ms）→ 失敗なら BUSY
  3. 書き込み: EmptyClipboard → GlobalMem 構築 → PutFormat（成功時のみ Release）
     読み取り: GetClipboardData → GlobalSize/GlobalLock → 境界検証 → コピー
  4. ClipboardScope のデストラクタで CloseClipboard
  5. pError に結果を格納
```

**内部 API（`WindowsClipboardCore.h`）**

```cpp
class ClipboardScope;                                  // RAII: OpenClipboard/CloseClipboard
class GlobalMem;                                       // RAII: GlobalAlloc/GlobalFree, Release()
class GlobalLockScope;                                 // RAII: GlobalLock/GlobalUnlock
bool PutFormat(UINT format, GlobalMem& mem);           // 成功時のみ所有権を移す

DWORD CopyPlainText(HWND owner, const std::wstring& text);
DWORD PastePlainText(HWND owner, std::wstring& out);
DWORD CopyHtml(HWND owner, const std::string& utf8Fragment);
DWORD PasteHtmlFragment(HWND owner, std::string& out);
DWORD CopyFiles(HWND owner, const std::vector<std::wstring>& paths);
DWORD PasteFiles(HWND owner, std::vector<std::wstring>& out);
DWORD CopyDib(HWND owner, const std::vector<BYTE>& dib);
DWORD PasteDib(HWND owner, std::vector<BYTE>& out);
DWORD CopyCustom(HWND owner, const std::wstring& formatName, const std::vector<BYTE>& blob);
DWORD PasteCustom(HWND owner, const std::wstring& formatName, std::vector<BYTE>& out);
DWORD CopyTextWithHtml(HWND owner, const std::wstring& plain, const std::string& utf8Fragment);
DWORD ListFormats(HWND owner, std::vector<UINT>& out);
DWORD FormatName(UINT format, std::wstring& out);
int   PickPreferredFormat();
DWORD ClearClipboard(HWND owner);
DWORD MarkAsSensitive();                               // 同一 Open/Close 内で呼ぶ
```

**純ロジック（`WindowsClipboardFormats.h` / テスト対象）**

```cpp
bool CheckedAdd(size_t a, size_t b, size_t& out);
bool CheckedMul(size_t a, size_t b, size_t& out);
bool CheckedToInt(size_t v, int& out);
bool CheckedToUInt(size_t v, UINT& out);

std::string BuildCfHtml(const std::string& utf8Fragment);
struct CfHtmlOffsets { size_t startHtml, endHtml, startFragment, endFragment;
                       bool hasSelection; size_t startSelection, endSelection; };
bool ParseCfHtmlHeader(const std::string& payload, CfHtmlOffsets& out);

bool BuildDropFiles(const std::vector<std::wstring>& paths, std::vector<BYTE>& out);
bool ValidateDropFiles(const BYTE* data, size_t totalBytes);
bool ValidateDib(const BYTE* data, size_t totalBytes);
bool ValidateUnicodeTextBlock(const BYTE* data, size_t totalBytes, size_t& outChars);
```

**互換性**: 新規追加のみ。既存 API に影響なし。

### F-06: 複数フォーマットの同時配置

**契約（企画書 v7 準拠）**: best-effort rollback。全ペイロードを `EmptyClipboard` 前に構築・確保し、配置失敗時に再 `EmptyClipboard`。ロールバックも失敗したら `PARTIAL_STATE` を返す。

### F-07: 内容確認

- `CountClipboardFormats` は失敗時も 0 のため、呼び出し前に `SetLastError(ERROR_SUCCESS)` して弁別
- `GetUpdatedClipboardFormats` 失敗時は `EnumClipboardFormats` へフォールバック。列挙終了は `GetLastError() == ERROR_SUCCESS` で判定し、途中失敗なら部分結果を破棄
- 標準フォーマット名は自前解決、登録フォーマットのみ `GetClipboardFormatName`

### F-09: 変更監視

**変更対象モジュール**: `WindowsClipboardWindow.{h,cpp}`

**データ構造**

```cpp
class ClipboardWatcher                 // インスタンス状態（static を使わない）
{
    // UI-thread-only state
    HWND  hwnd_ = nullptr;
    bool  registered_ = false;
    DWORD lastSeq_ = 0;

    // Cross-thread state: several copies can complete on different threads before the
    // UI thread drains WM_CLIPBOARDUPDATE, so a single "latest" value would make older
    // self-writes look like external changes. A small ring of recent sequence numbers
    // is kept instead, guarded by its own mutex.
    static constexpr size_t kSelfWriteRingSize = 8;
    mutable std::mutex          selfWriteMutex_;
    std::array<DWORD, kSelfWriteRingSize> selfWriteSeq_{};
    size_t                      selfWriteNext_ = 0;

public:
    bool Start(HWND hwnd);             // AddClipboardFormatListener（UI スレッド）
    bool Stop();                       // 成功時のみ状態をクリア（失敗時は再試行可能）
    bool IsRegistered() const;
    void NoteSelfWrite();              // 任意スレッド: リングへ現在の sequence を追加
    bool TakeSelfWrite(DWORD seq);     // UI スレッド: 一致すれば取り除いて true
    void OnClipboardUpdate();          // WM_CLIPBOARDUPDATE（UI スレッド）
};
```

`OnClipboardUpdate` は `GetClipboardSequenceNumber()` を読み、`TakeSelfWrite(seq)` が `true` を返した場合のみ通知を抑止する（消費するので、同じ番号で二重に抑止されない）。リングが溢れた場合は最古を捨てる。連続コピーで抑止が漏れても外部変更として 1 回多く通知されるだけで、誤動作にはならない。

**制御フロー**

```
initClipboardManager(changedCallback, pError)   ← 所有 UI スレッドから呼ぶ
  → toolkit が dispatchHwnd を生成
  → ClipboardWatcher::Start(dispatchHwnd)
外部アプリがコピー
  → 所有 UI スレッドへ WM_CLIPBOARDUPDATE
  → シーケンス番号比較 → 自書き込みなら抑止 → changedCallback を呼ぶ
uninitClipboardManager()
  → shutdown gate（後述）
```

**注意**: 所有ウィンドウのスレッドがメッセージポンプを回していないと通知は届かない（`windows.md` の記載どおり）。同期 Bridge であってもこの要件は残る。

### F-10: 遅延レンダリング

**データ構造**

```cpp
class DeferredClipboard
{
    using Renderer = std::function<GlobalMem()>;   // HGLOBAL 形式に限定
    HWND owner_ = nullptr;
    bool partial_ = false;
    std::map<UINT, Renderer> renderers_;
    std::set<UINT> rendered_;
public:
    DWORD Reserve(HWND owner, std::map<UINT, Renderer> renderers);
    DWORD RecoverFromPartialState();               // 引数なし（保存済み owner_ のみ）
    bool  IsPartial() const;
    void  OnRenderFormat(UINT format);             // OpenClipboard を呼ばない
    void  OnRenderAllFormats(HWND hwnd);           // EmptyClipboard を呼ばない
    void  OnDestroyClipboard();
};
```

**状態遷移**

| 遷移 | 結果 | テーブル |
|---|---|---|
| 全形式の予約成功 | `NONE` | 保持 |
| 途中失敗 → ロールバック成功 | `UNKNOWN` | 破棄 |
| 途中失敗 → ロールバック失敗 | `PARTIAL_STATE` | **保持**（残存形式に応答するため） |
| 所有権喪失 | — | `WM_DESTROYCLIPBOARD` で破棄 |

**制約**: Renderer は `GlobalAlloc(GMEM_MOVEABLE)` の `HGLOBAL` 形式のみ。`CF_BITMAP` / メタファイル / GDI オブジェクトは解放方法が異なるため受け付けない。

**公開 API からの provider 供給（レビュー指摘 H4 反映）**

形式名だけを渡す `reserveDeferredFormats(formatsJson)` では `WM_RENDERFORMAT` 時にペイロードを生成できない。C ABI の provider コールバックを受け取る形にする。

```cpp
/**
 * @brief Produces the payload for a deferred clipboard format on demand.
 * @param formatName    Registered or standard format name being requested.
 * @param context       Opaque pointer supplied at reservation time.
 * @param buffer        Destination buffer, or nullptr to query the required size.
 * @param buffer_size   Size of buffer in bytes (0 when querying).
 * @param pRequiredSize Out: required size in bytes. Must be set in both phases.
 * @return CLIPBOARD_ERROR_NONE on success, CLIPBOARD_ERROR_BUFFER_TOO_SMALL when
 *         buffer is null or too small (with *pRequiredSize set), otherwise an error.
 * @note Invoked on the owner UI thread, inside WM_RENDERFORMAT handling.
 *       Must not call any clipboard API, must not block, and must not throw.
 */
typedef DWORD (*ClipboardRenderCallback)(const wchar_t* formatName,
                                         void* context,
                                         BYTE* buffer,
                                         DWORD buffer_size,
                                         DWORD* pRequiredSize);

extern "C" WINDOWSCLIPBOARDMANAGER_API
void reserveDeferredFormats(const wchar_t* formatNamesJson,
                            ClipboardRenderCallback provider,
                            void* context,
                            DWORD* pError);
```

| 項目 | 契約 |
|---|---|
| 呼び出しスレッド | 所有 UI スレッド（`WM_RENDERFORMAT` / `WM_RENDERALLFORMATS` の処理中） |
| 二相呼び出し | 1 回目は `buffer = nullptr` でサイズ問い合わせ、2 回目に実データ。toolkit が `GlobalAlloc` してから 2 回目を呼ぶ |
| `context` の寿命 | 予約時から、**`WM_DESTROYCLIPBOARD` 受信または `uninitClipboardManager` 完了まで**呼び出し側が有効に保つ責務。toolkit は所有しない |
| 禁止事項 | provider 内でクリップボード API を呼ばない（`WM_RENDERFORMAT` 中の `OpenClipboard` は不正）、ブロックしない、例外を投げない |
| 失敗時 | provider が `NONE` 以外を返した形式は配置をスキップし、ログに残す。他の形式の配置は継続する |
| 代替案 | 予約時に実ペイロードを保持する方式も可能だが、遅延レンダリングの目的（生成コストの先送り）を失うため採らない |

### F-12: 履歴（WinRT）

**Port（`WindowsClipboardHistoryBackend.h`）**

Port はドメイン型のみを使う（`common.md` の型制約）。`winrt::` 型を出さない。

**Port は非同期にする（レビュー指摘 H1 反映）。** 実装が `co_await` する以上、同期の `DWORD` 戻り値では UI をブロックせずに結果を返せず、Mock からも完了を模擬できない。Domain 型のコールバックで完了を返す形にし、`winrt` / コルーチンをインターフェースに露出させない。

```cpp
struct ClipboardHistoryEntry            // Domain 型
{
    std::wstring                id;
    std::optional<std::wstring> text;         // nullopt when the item carries no text
    std::vector<std::wstring>   contentTypes; // format names available on the item
    int64_t                     timestampUtc; // FILETIME 相当
};

struct ClipboardHistoryAvailability     // Domain 型
{
    bool historyEnabled = false;
    bool roamingEnabled = false;
};

// Completion callbacks are platform-independent and are always invoked on the
// owner UI thread, exactly once per request.
using HistoryItemsCallback        = std::function<void(DWORD error, std::vector<ClipboardHistoryEntry>)>;
using HistoryStatusCallback       = std::function<void(DWORD error)>;
using HistoryAvailabilityCallback = std::function<void(DWORD error, ClipboardHistoryAvailability)>;

// Event callbacks raised by the backend while watching.
struct ClipboardHistoryEvents
{
    std::function<void()>            onHistoryChanged;         // a NEW ITEM was added
    std::function<void(bool)>        onHistoryEnabledChanged;
    std::function<void(bool)>        onRoamingEnabledChanged;
};

class IClipboardHistoryBackend          // 抽象基底クラス（純粋仮想 / Port）
{
public:
    virtual ~IClipboardHistoryBackend() = default;

    // All of these must be called on the owner UI thread. They return immediately;
    // completion is delivered through the callback on the same thread.
    virtual void GetAvailabilityAsync(HistoryAvailabilityCallback done) = 0;
    virtual void GetItemsAsync(HistoryItemsCallback done) = 0;
    virtual void SetItemAsContentAsync(const std::wstring& id, HistoryStatusCallback done) = 0;
    virtual void DeleteItemAsync(const std::wstring& id, HistoryStatusCallback done) = 0;
    virtual void ClearUnpinnedAsync(HistoryStatusCallback done) = 0;

    // Event subscription. Internal handlers are registered ONCE and stay stable;
    // the user-facing callbacks live in an immutable snapshot that is swapped
    // atomically, so replacement never re-registers WinRT events.
    virtual DWORD StartWatch(std::shared_ptr<const ClipboardHistoryEvents> events) = 0;
    virtual void  ReplaceEvents(std::shared_ptr<const ClipboardHistoryEvents> events) = 0;
    virtual bool  StopWatch() = 0;      // true only when every token was revoked
    virtual bool  CanDestroy() const = 0; // false while a token remains or a callback is in flight
};
```

`GetAvailabilityAsync` は WinRT 側では同期 API（`IsHistoryEnabled` / `IsRoamingEnabled`）だが、**UI スレッド要件があるため公開形は他と揃える**（レビュー指摘 M1 の統一）。Port を非同期に揃えることで、Mock が完了タイミングを制御でき、pending / キャンセル / ドレインのテストが可能になる。

**実装（`WindowsClipboardHistoryWinRt.cpp`）**

- `Clipboard::GetHistoryItemsAsync()` を UI スレッドで開始し `co_await`
- 同期 WinRT（`SetHistoryItemAsContent` / `DeleteItemFromHistory` / `ClearHistory` / `IsHistoryEnabled`）も UI スレッド上で実行
- ステータス変換は共通関数 `MapHistoryStatus` / `MapSetHistoryItemStatus` に集約
- 例外は**同期境界を `InvokeWinRt`、非同期境界を具象コルーチン内の `try/catch`** で正規化する（汎用の `InvokeWinRtAsync` テンプレートは不採用）。分類は共通の `ClassifyWinRtException()`、完了は共通の `Complete*` ヘルパに集約。`std::bad_alloc` を明示捕捉

**前提判定の 3 段階（レビュー指摘 M2 反映）**

`IsHistoryEnabled()` は履歴設定の判定であってフォアグラウンド状態は判定できない。3 つを別々の手順として扱い、エラーを混同しない。

| 順序 | 判定 | 方法 | 失敗時のエラー |
|---|---|---|---|
| 1 | フォアグラウンド | `GetForegroundWindow()` のプロセス ID が自プロセスと一致するか | `CLIPBOARD_ERROR_NOT_FOREGROUND` |
| 2 | 履歴の有効状態 | `Clipboard::IsHistoryEnabled()` | `CLIPBOARD_ERROR_HISTORY_DISABLED` |
| 3 | WinRT 呼び出し結果 | `ClipboardHistoryItemsResultStatus` / `SetHistoryItemAsContentStatus` | `ACCESS_DENIED` / `HISTORY_DISABLED` / `ITEM_DELETED` / `UNKNOWN` |

`IsHistoryEnabled() == false` は `HISTORY_DISABLED` であり、`ACCESS_DENIED` にしない。

**非テキスト履歴項目の扱い（レビュー指摘 M3 反映）**

| 項目 | 契約 |
|---|---|
| テキストを含まない項目 | **除外せず含める**。`"text": null` とし、`"contentTypes"` に利用可能な形式名を入れる |
| 項目単位の取得失敗 | その項目のみ `"text": null` にしてログへ残す。**要求全体は失敗させない** |
| 順序 | WinRT が返した順序を維持する（新しい順） |
| 取得方法 | 各項目の `Content.GetTextAsync()` を順次 `co_await`。全項目の完了後に 1 回だけコールバックする |
| JSON スキーマ | `[{"id":"...","text":"..."\|null,"contentTypes":["Text","Bitmap"],"timestamp":<int64>}]` |

**非同期境界の例外処理（汎用テンプレートは不採用）**

`ClipboardResult<T>` はネイティブ struct であり、WinRT ABI の `IAsyncOperation<T>` の結果型にはできない。**`IAsyncOperation<ClipboardResult<T>>` を生成しない。**

**汎用テンプレートは作らない。** `co_await body()` がネイティブの `ClipboardResult<T>` を返す awaitable は存在せず（WinRT の `IAsyncOperation<U>` を `co_await` した結果は `U`）、そのままではコンパイルできない。**各操作ごとに具象コルーチンを書き、その中で `try/catch` と変換を行う**方式に確定する。

**層の分離（レビュー指摘 H2 反映）**: 具象コルーチンは **Data 層（backend）に属し、Manager の関心（リクエスト ID・lease・pending）を一切参照しない**。Data 層は WinRT → Domain 変換を終えたら `done(error, items)` を呼ぶだけ。ID・lease・pending の接続は **Manager 側がラムダのキャプチャで閉じ込める**。

```cpp
// ---- Data 層（ClipboardHistoryWinRt.cpp）------------------------------------
// Knows only WinRT and Domain types. No request id, no lease, no pending table.
// Not marked noexcept: the coroutine frame allocation must be able to throw so the
// caller can convert it into a normal completion (see below).
winrt::fire_and_forget ClipboardHistoryWinRt::GetItemsAsync(HistoryItemsCallback done)
{
    DWORD error = CLIPBOARD_ERROR_NONE;
    std::vector<ClipboardHistoryEntry> items;
    try
    {
        if (!IsSelfForeground())                 // checked here, after acceptance
            error = CLIPBOARD_ERROR_NOT_FOREGROUND;
        else if (!Clipboard::IsHistoryEnabled())
            error = CLIPBOARD_ERROR_HISTORY_DISABLED;
        else
        {
            ClipboardHistoryItemsResult result = co_await Clipboard::GetHistoryItemsAsync();
            error = MapHistoryStatus(result.Status());
            if (error == CLIPBOARD_ERROR_NONE)
                items = co_await ToDomainEntries(result.Items());  // per-item, never throws out
        }
    }
    catch (...)
    {
        error = ClassifyWinRtException();        // includes std::bad_alloc -> OUT_OF_MEMORY
        items.clear();
    }

    done(error, std::move(items));               // the callback itself is noexcept
}

// ---- Manager 層（WindowsClipboardManager.cpp）--------------------------------
// Owns the request id, the lease and the pending table; the backend never sees them.
void ClipboardManager::StartQueuedRequest(uint32_t id)
{
    auto exec = pending_.TakeQueuedExecution(id);       // inputs + lease, leaves the entry
    if (!exec) return;                                  // already cancelled or drained

    backend_->GetItemsAsync(
        [this, id, lease = std::move(exec->lease)](DWORD error,
                                                   std::vector<ClipboardHistoryEntry> items) noexcept
        {
            // Runs on the owner UI thread. Takes the completion right exactly once;
            // the lease is released when this lambda (and its coroutine frame) dies.
            CompleteHistoryItemsRequest(id, error, std::move(items));
        });
}
```

- `ClassifyWinRtException()` は `winrt::hresult_error` / `std::bad_alloc` / その他を Domain エラーへ分類する共通関数（v2 から継続）
- `CompletePendingRequest` 系ヘルパは `noexcept`。ペイロードの確保を take の**前**に行い、確保失敗時は `OUT_OF_MEMORY` に置き換えて完了させる（未完了で終わる経路を作らない）
- 例外の終端はコルーチン内。`fire_and_forget::unhandled_exception` へ到達させない。**ただしフレーム確保の失敗はコルーチン開始前に起きるため、上記のとおり `StartQueuedRequest` の呼び出し側で捕捉する**
- イベント購読は **`event_token` の明示解除**（`auto_revoke` は `void revoke() noexcept` で失敗を観測できないため不採用）
- ハンドラは `this` を直接捕捉せず世代番号 / weak reference 経由。`Stop` で世代を無効化し in-flight コールバックを no-op 化

**履歴イベントの寿命契約（レビュー指摘 H3 反映）**

| 項目 | 契約 |
|---|---|
| token の保持 | 各 `event_token` は**取得直後に即座にメンバへ保持**する。3 件まとめて代入しない（途中失敗時に取得済みトークンを失うため） |
| 登録の巻き戻し | 途中失敗時は `catch` 内で取得済みトークンを明示解除する。解除にも失敗した場合は `StartWatch` が `MONITOR_REGISTER_FAILED` を返し、`revokePending_` 状態に入る |
| atomic gate | 購読状態（`watching_` / `revokePending_`）は単一の gate で排他する。`revokePending_` の間は `StartWatch` を拒否する |
| in-flight drain | `StopWatch` は世代を無効化してから解除する。無効化後に到着したコールバックは何もしない |
| コールバック内からの `Stop` 禁止 | イベントハンドラ内で `StopWatch` / `uninitClipboardManager` を呼んではならない（再入で gate が壊れる）。Doxygen に明記し、デバッグビルドで `WINRT_ASSERT` を置く |
| `CanDestroy` | トークンが残っている、または in-flight コールバックがある間は `false`。shutdown gate はこれが `true` になるまでウィンドウ資源を解放しない |

**結果型**

```cpp
template <typename T> struct ClipboardResult { DWORD error; T value; };
using ClipboardStatus = ClipboardResult<std::monostate>;
```

### F-17: スレッドモデルと Bridge ライフサイクル

**受付（acceptance）契約**

**受付成立の定義（単一経路）**: 呼び出しスレッドを問わず、**「引数検証の通過 → lease 取得 → pending 登録 → `PostMessage` 投入」がすべて成功した時点**を受付成立とする。UI スレッドからの呼び出しも同じ経路を通る。

| 段階 | 該当する失敗 | 通知 | コールバック回数 |
|---|---|---|---|
| 受付成立**前** | 引数不正 / 未初期化 / gate が閉じている（lease 取得失敗）/ pending 登録失敗 / `PostMessage` 失敗 | Bridge の同期戻り値のみ。リクエスト ID は無効値 `0` | **0 回** |
| 受付成立**後** | **フォアグラウンド不成立**、履歴無効、WinRT 失敗、成功、キャンセル、`Uninit` 失効 | コールバック | **ちょうど 1 回** |

**フォアグラウンド判定は受付後に行う**（レビュー指摘 H1 反映）。判定は UI スレッド上でしか意味を持たないため、`PostMessage` 受信後に実施し、不成立なら `NOT_FOREGROUND` を**コールバックで**通知する。同期戻り値では返さない。

**共通完了ヘルパ**

```cpp
// noexcept: every terminal path (success, failure, cancel, drain) must complete the
// pending entry exactly once. Allocation for the payload happens BEFORE the take, so
// an allocation failure cannot leave the entry un-completed.
template <typename... Payload>
void CompletePendingRequest(uint32_t requestId, DWORD error, Payload&&... payload) noexcept;
// 1. build the payload buffer (may fail -> error becomes OUT_OF_MEMORY)
// 2. atomic take from the pending table (only one of complete/cancel/drain wins)
// 3. invoke the C ABI callback inside try/catch, holding no lock
// 4. free the payload buffer
```

**終了シーケンス（shutdown gate）**: 「同時実行とライフサイクル契約」の `uninit` フローを参照。`ClipboardLifecycle` の lease が request コルーチン・イベントコールバック・任意スレッドの同期 API を一括で待つ。

---

## API 設計

### 公開 API（`WindowsClipboardManager.h` / Bridge）

命名は既存 Bridge（`initNotificationManager` 等）の lowerCamelCase に揃える。

#### 初期化 / 破棄

```cpp
typedef void (*ClipboardChangedCallback)(void);
typedef void (*ClipboardHistoryChangedCallback)(void);          // a NEW ITEM was added
typedef void (*ClipboardFlagChangedCallback)(BOOL enabled);      // history / roaming toggled

/**
 * @param requestId The id returned by the originating call.
 * @param error     CLIPBOARD_ERROR_* value.
 * @param json      Result payload, or nullptr on failure.
 *                  VALID ONLY DURING THIS CALLBACK — the caller must copy it before
 *                  returning. The buffer is freed by the toolkit afterwards.
 */
typedef void (*ClipboardRequestCallback)(uint32_t requestId, DWORD error, const wchar_t* json);

/**
 * @brief Initializes the clipboard manager.
 * @param onChanged Invoked when the clipboard contents change (nullable).
 * @param pError    Out error code.
 * @note PRECONDITIONS for the calling thread, which is adopted as the owner UI thread:
 *       1) It must run a message pump for the lifetime of the manager. This cannot be
 *          verified at runtime, so it is a caller contract, not a checked error.
 *       2) It must already be initialized as an STA (CoInitializeEx with
 *          COINIT_APARTMENTTHREADED, or winrt::init_apartment(single_threaded)).
 *          This IS checked: an uninitialized or MTA thread returns
 *          CLIPBOARD_ERROR_WRONG_APARTMENT and the manager is not initialized.
 *       The toolkit never initializes or uninitializes the apartment: it belongs to
 *       the host. Calling init again from a different thread returns
 *       CLIPBOARD_ERROR_WRONG_THREAD.
 *       The function pointer must stay valid until uninitClipboardManager returns TRUE.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void initClipboardManager(ClipboardChangedCallback onChanged, DWORD* pError);

/**
 * @brief Registers (or clears) history event callbacks and starts/stops watching.
 * @note Synchronous, and MUST be called from the owner UI thread; otherwise
 *       CLIPBOARD_ERROR_WRONG_THREAD. Not callable from inside a callback.
 *       Passing all three as nullptr stops watching and clears the registration.
 *       Replacing an existing registration only swaps an internal snapshot and
 *       therefore cannot fail. Partial failure — and the "previous registration is
 *       kept" rule — applies only to the FIRST registration, where the underlying
 *       event tokens are acquired. If a previous stop failed to revoke every token,
 *       re-registration is refused until a later call succeeds in stopping.
 *       The function pointers must stay valid until they are replaced or until
 *       uninitClipboardManager returns TRUE.
 *       onHistoryChanged fires only when a NEW ITEM is added; deletions and
 *       ClearHistory are not guaranteed to raise it. Re-query after your own
 *       delete/clear calls.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
void setClipboardHistoryCallbacks(ClipboardHistoryChangedCallback onHistoryChanged,
                                  ClipboardFlagChangedCallback onHistoryEnabledChanged,
                                  ClipboardFlagChangedCallback onRoamingEnabledChanged,
                                  DWORD* pError);

/**
 * @brief Shuts the manager down. Expects to be called more than once.
 * @return TRUE when shutdown completed and all resources were released.
 *         FALSE when any of the following is still outstanding — call again after
 *         pumping messages:
 *           - a clipboard listener or history event token could not be revoked
 *           - queued cancellation completions have not been delivered yet
 *           - a request coroutine is still running (even after cancellation)
 *           - an any-thread synchronous API call is still in flight
 * @note MUST be called from the owner UI thread, and never from inside a callback.
 *       The first call always returns FALSE when any request is pending, because
 *       cancellations are queued rather than fired inline. Keep the message pump
 *       running between retries; do not spin while blocking the UI thread.
 *       The toolkit never calls uninit_apartment: the apartment belongs to the host.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
BOOL uninitClipboardManager(DWORD* pError);

/**
 * @brief Non-blocking query of whether shutdown can complete.
 * @return TRUE when no listener, event token, queued drain callback, request
 *         coroutine or in-flight synchronous call remains. This is a state query
 *         only: it does NOT promise that the next uninit succeeds, because that
 *         call can still fail on partial-state recovery or an OS API error.
 *         Judge the final result by the uninit return value.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API
BOOL canDestroyClipboardManager(DWORD* pError);
```

`uninitClipboardManager` を `BOOL` + `pError` にしたのは、shutdown gate が「`Stop()` 成功まで資源を保持する」契約である以上、解除失敗と再試行要否を呼び出し側へ伝える必要があるため（レビュー指摘 H5）。

**`setClipboardHistoryCallbacks` の契約（レビュー指摘 H4 / M4 反映）**

| 項目 | 契約 |
|---|---|
| 同期性 | **同期**。戻り時点で登録 / 解除が完了している |
| スレッド | **所有 UI スレッド限定**。他スレッドは `WRONG_THREAD`。コールバック内からの呼び出しは禁止 |
| 責務 | コールバックの保存に加え、**`backend->StartWatch()` / `StopWatch()` まで行う**（保存だけではない） |
| 全て `nullptr` | 購読を停止し登録を解除する |
| 多重呼び出し | 既存の登録を**まとめて置換**する（原子的に差し替え） |
| 部分登録失敗 | 取得済みトークンを巻き戻し、**旧設定をそのまま維持**する。`MONITOR_REGISTER_FAILED` を返す |

**原子的置換の実現手順（レビュー指摘 M1 反映）**

WinRT のトークンを毎回張り替える方式では「旧設定を維持したままステージし、成功時のみコミット」が表現できない。**内部ハンドラとユーザーコールバックを分離する。**

```
初回の非 null 登録
  1. 安定した内部ハンドラを WinRT へ 1 回だけ登録し、token を即座に保持
     （途中失敗時は取得済み token を明示解除して巻き戻し、旧状態＝未購読を維持）
  2. ユーザーコールバックの immutable snapshot（shared_ptr<const ClipboardHistoryEvents>）を格納

2 回目以降の置換（ReplaceEvents）
  - WinRT の token は張り替えない（再登録による重複通知が起きない）
  - snapshot ポインタを差し替えるだけ。差し替えは原子的で失敗しない
  - in-flight ハンドラは入場時に取得した古い snapshot を使い切る（安全）

全 null での解除
  - snapshot を空にしてから StopWatch() で token を明示解除
  - 解除に失敗した token は保持し、revokePending_ 状態で再試行可能にする
```

この方式では**置換が失敗しない**ため、「部分登録失敗で旧設定を維持」が必要になるのは**初回の `StartWatch`（トークン登録）時のみ**となり、契約が単純化する。

**コールバック値の寿命（レビュー指摘 M4 反映）**

| 項目 | 契約 |
|---|---|
| 関数ポインタの寿命 | 置換されるか `uninitClipboardManager` が `TRUE` を返すまで、呼び出し側が有効に保つ |
| in-flight との競合 | 登録値はハンドラ入場時に**スナップショット**され、実行中の置換は次回呼び出しから反映される |
| 全 null 後の再登録 | `StopWatch()` が成功していれば通常どおり再登録できる。**解除に失敗した（`revokePending_`）状態では再登録を拒否**し、`Stop` の再試行を促す |

同期 API にできるのは UI スレッド限定にしたためで、任意スレッドから `PostMessage` する方式では登録結果を `DWORD* pError` で返せない（レビュー指摘のとおり）。

#### 同期 API（F-01〜F-08, F-10, F-11）

**書き込みオプション（レビュー指摘 M5 反映）**: 機微情報の除外はテキスト / HTML だけでなく全ての書き込みに必要なため、`isSensitive` の個別引数をやめ、全書き込み API 共通のフラグにする。

```cpp
// Write options shared by every copy API.
#define CLIPBOARD_WRITE_OPTION_NONE               0x00000000u
#define CLIPBOARD_WRITE_OPTION_EXCLUDE_HISTORY    0x00000001u  // CanIncludeInClipboardHistory = 0
#define CLIPBOARD_WRITE_OPTION_EXCLUDE_ROAMING    0x00000002u  // CanUploadToCloudClipboard = 0
#define CLIPBOARD_WRITE_OPTION_SENSITIVE          0x00000003u  // both of the above
```

| 関数 | 引数 | 戻り値 |
|---|---|---|
| `copyPlainText` | `const wchar_t* text`, `DWORD options`, `DWORD* pError` | void |
| `pastePlainText` | `wchar_t* buffer`, `DWORD buffer_size`, `DWORD* pError` | `DWORD`（必要要素数） |
| `copyHtml` | `const wchar_t* htmlFragment`, `const wchar_t* plainText`, `DWORD options`, `DWORD* pError` | void |
| `pasteHtml` | `wchar_t* buffer`, `DWORD buffer_size`, `DWORD* pError` | `DWORD` |
| `copyFiles` | `const wchar_t* pathsJson`, `DWORD options`, `DWORD* pError` | void |
| `pasteFiles` | `wchar_t* buffer`, `DWORD buffer_size`, `DWORD* pError` | `DWORD` |
| `copyImage` | `const BYTE* dib`, `DWORD dibSize`, `DWORD options`, `DWORD* pError` | void |
| `pasteImage` | `BYTE* buffer`, `DWORD buffer_size`, `DWORD* pError` | `DWORD`（必要バイト数） |
| `copyCustomFormat` | `const wchar_t* formatName`, `const BYTE* data`, `DWORD size`, `DWORD options`, `DWORD* pError` | void |
| `pasteCustomFormat` | `const wchar_t* formatName`, `BYTE* buffer`, `DWORD buffer_size`, `DWORD* pError` | `DWORD` |
| **`copyMultipleFormats`** | `const wchar_t* itemsJson`, `DWORD options`, `DWORD* pError` | void |
| `hasClipboardFormat` | `const wchar_t* formatName`, `DWORD* pError` | `BOOL` |
| `getClipboardFormats` | `wchar_t* buffer`, `DWORD buffer_size`, `DWORD* pError` | `DWORD`（JSON 配列） |
| **`getPreferredClipboardFormat`** | `wchar_t* buffer`, `DWORD buffer_size`, `DWORD* pError` | `DWORD`（形式名。空なら該当なし） |
| `clearClipboard` | `DWORD* pError` | void |
| `reserveDeferredFormats` **（UI スレッド限定）** | `const wchar_t* formatNamesJson`, `ClipboardRenderCallback provider`, `void* context`, `DWORD* pError` | void |
| `recoverDeferredState` **（UI スレッド限定）** | `DWORD* pError` | void |

**遅延レンダリング API のスレッド契約（レビュー指摘 H3 反映）**: この 2 つは `DeferredClipboard` の UI スレッド専有状態を直接操作するため、**所有 UI スレッド限定の同期 API** とする。他スレッドから呼ばれた場合は `CLIPBOARD_ERROR_WRONG_THREAD` を返す。任意スレッドから `PostMessage` で配送する方式は、結果を同期の `pError` で返せないため採らない（リクエスト ID + コールバック形式にする案も、予約は即時完了する操作なので不採用）。

**追加した 2 API（レビュー指摘 M6 反映）**

- `copyMultipleFormats`: F-06（複数フォーマットの同時配置）の公開窓口。`itemsJson` は `[{"format":"CF_UNICODETEXT","text":"..."},{"format":"HTML Format","html":"..."}]` の形で、**情報量の多い順に配置**する。部分成功を残さない契約（失敗時は best-effort rollback、ロールバックも失敗なら `PARTIAL_STATE`）
- `getPreferredClipboardFormat`: F-07 の優先フォーマット判定（`GetPriorityClipboardFormat`）の公開窓口。貼り付け側が「認識できる最も情報量の多い形式」を選ぶために必要

**バッファ規約（既存 `showFileDialog` に準拠）**: `buffer` が `nullptr` または `buffer_size` が不足の場合、必要サイズを戻り値で返し `pError` に `BUFFER_TOO_SMALL` を設定する。呼び出し元は 2 回呼ぶ。

#### 非同期 API（F-12 履歴）

```cpp
extern "C" WINDOWSCLIPBOARDMANAGER_API uint32_t getClipboardHistory(ClipboardRequestCallback cb, DWORD* pError);
extern "C" WINDOWSCLIPBOARDMANAGER_API uint32_t restoreHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError);
extern "C" WINDOWSCLIPBOARDMANAGER_API uint32_t deleteHistoryItem(const wchar_t* itemId, ClipboardRequestCallback cb, DWORD* pError);
extern "C" WINDOWSCLIPBOARDMANAGER_API uint32_t clearUnpinnedHistory(ClipboardRequestCallback cb, DWORD* pError);
extern "C" WINDOWSCLIPBOARDMANAGER_API uint32_t getClipboardHistoryAvailability(ClipboardRequestCallback cb, DWORD* pError);

/**
 * @brief Requests cancellation of a pending request.
 * @return TRUE when the cancellation was queued to the owner UI thread.
 *         FALSE when the id is unknown, already completed, or the post failed
 *         (see pError). A FALSE return does NOT suppress a completion that is
 *         already on its way.
 * @note Callable from any thread. The callback still fires exactly once, on the
 *       owner UI thread, with CLIPBOARD_ERROR_CANCELED when cancellation wins.
 */
extern "C" WINDOWSCLIPBOARDMANAGER_API BOOL cancelClipboardRequest(uint32_t requestId, DWORD* pError);
```

- 戻り値の `uint32_t` は**リクエスト ID**。受付失敗時は `0`（無効値）を返し、コールバックは呼ばれない
- `getClipboardHistoryAvailability` は WinRT 側が同期 API でも**他の履歴 API と同じ非同期形に統一する**（レビュー指摘 M1）。同期の `isClipboardHistoryEnabled` / `isClipboardRoamingEnabled` は廃止し、UI スレッド限定の同期 API を残さない
- JSON スキーマ（Domain 型 `ClipboardHistoryEntry` と 1 対 1 に対応する）
  - `getClipboardHistory`: `[{"id":"...","text":"..."|null,"contentTypes":["Text","Bitmap"],"timestamp":<int64>}]`
  - `getClipboardHistoryAvailability`: `{"historyEnabled":true,"roamingEnabled":false}`
  - その他: `null`

**コールバックペイロードの寿命契約（レビュー指摘 H6 反映）**

| 項目 | 契約 |
|---|---|
| 所有者 | toolkit。呼び出し側は解放しない |
| 有効期間 | **コールバックの実行中のみ。** 呼び出し側は復帰前にコピーする。復帰後にバッファは解放される |
| 失敗時 | `error != CLIPBOARD_ERROR_NONE` のとき `json` は必ず `nullptr` |
| ペイロードなしの成功 | `restoreHistoryItem` 等は成功時も `nullptr` |
| 呼び出しスレッド | 所有 UI スレッド（前述の統一契約） |

この契約は Doxygen コメントに明記し、単体テストで「コールバック復帰後にポインタを保持しても参照しない」ことを Mock 側で検証する。

#### 内部 API

Manager クラス（`WindowsClipboardManagerInternal.h`）はテストから参照するため公開ヘッダとは分離する。既存の `WindowsNotificationManagerInternal.h` と同じ方式。

---

## ドメインエラー一覧（全ケース）

`WindowsClipboardManager.h` に定数として定義する。既存の `NOTIFICATION_ERROR_*` と同じ形式。

| 定数 | 値 | 発生源 | 意味 |
|---|---|---|---|
| `CLIPBOARD_ERROR_NONE` | 0 | — | 成功 |
| `CLIPBOARD_ERROR_INVALID_PARAMETER` | 1 | 自実装 | 引数 null / サイズ 0 / owner HWND 不正 / JSON 解析失敗 |
| `CLIPBOARD_ERROR_NOT_INITIALIZED` | 2 | 自実装 | `initClipboardManager` 未実行、または `uninit` 後の呼び出し |
| `CLIPBOARD_ERROR_BUSY` | 3 | Win32 | `OpenClipboard` がリトライ上限まで失敗（他プロセスが排他保持） |
| `CLIPBOARD_ERROR_EMPTY` | 4 | Win32 / WinRT | クリップボードが空 / 履歴が空 |
| `CLIPBOARD_ERROR_FORMAT_UNAVAILABLE` | 5 | Win32 / WinRT | 要求フォーマットが存在しない |
| `CLIPBOARD_ERROR_INVALID_DATA` | 6 | 自実装 | 境界検証失敗（終端 NUL / サイズ / オフセット / オーバーフロー / DIB 構造） |
| `CLIPBOARD_ERROR_BUFFER_TOO_SMALL` | 7 | 自実装 | 出力バッファ不足（戻り値が必要サイズ） |
| `CLIPBOARD_ERROR_OUT_OF_MEMORY` | 8 | Win32 / WinRT | `GlobalAlloc` / `GlobalLock` 失敗、`std::bad_alloc` |
| `CLIPBOARD_ERROR_ACCESS_DENIED` | 9 | WinRT | `ClipboardHistoryItemsResultStatus::AccessDenied` / `SetHistoryItemAsContentStatus::AccessDenied` / `E_ACCESSDENIED` |
| `CLIPBOARD_ERROR_HISTORY_DISABLED` | 10 | WinRT | `ClipboardHistoryDisabled` / `IsHistoryEnabled() == false` |
| `CLIPBOARD_ERROR_ITEM_DELETED` | 11 | WinRT | `SetHistoryItemAsContentStatus::ItemDeleted` |
| `CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED` | 12 | Win32 | `AddClipboardFormatListener` / `RemoveClipboardFormatListener` 失敗、監視ウィンドウ生成失敗 |
| `CLIPBOARD_ERROR_PARTIAL_STATE` | 13 | Win32 | 配置失敗後のロールバック用 `EmptyClipboard` も失敗（一部形式が残存し得る） |
| `CLIPBOARD_ERROR_WRONG_THREAD` | 14 | 自実装 | UI スレッド限定 API を非 UI スレッドから呼んだ |
| `CLIPBOARD_ERROR_CANCELED` | 15 | 自実装 | `cancelClipboardRequest` / `Uninit` のドレインによる失効 |
| `CLIPBOARD_ERROR_NOT_SUPPORTED` | 16 | 自実装 | Windows に等価概念がない操作（Android の Intent クリップ等） |
| `CLIPBOARD_ERROR_NOT_FOREGROUND` | 17 | 自実装 | WinRT `Clipboard` のフォアグラウンド要件を満たさない（自プロセスが前面でない）。**受付後にコールバックで返す** |
| `CLIPBOARD_ERROR_WRONG_APARTMENT` | 18 | 自実装 | `init` の呼び出しスレッドが STA として初期化されていない（`CoGetApartmentType` が STA 以外） |
| `CLIPBOARD_ERROR_UNKNOWN` | 19 | Win32 / WinRT | 上記以外。**`DeleteItemFromHistory` / `ClearHistory` の `false` を含む**（公式が理由を規定していないため） |

**成功を含めて 20 定数、非成功のエラーは 19 種**（企画書は非成功 17 種）。以降の記述はすべて「非成功 19 種」で数える。追加分は `NOT_FOREGROUND` と `WRONG_APARTMENT`。名称の正本は本設計書とし、企画書の `INVALID_ARGUMENT` は `INVALID_PARAMETER` に統一する（既存の `NOTIFICATION_ERROR_INVALID_PARAMETER` と揃えるため）。

**`SetContentWithOptions` を使わない設計判断（レビュー指摘 M6 反映）**

企画書は履歴 / 同期の除外手段として Win32 の登録フォーマットと WinRT の `ClipboardContentOptions` の両方を挙げているが、**本設計では Win32 の登録フォーマット（`CanIncludeInClipboardHistory` / `CanUploadToCloudClipboard`）のみを採用する。**

| 観点 | 判断 |
|---|---|
| 理由 | 書き込みのコア（F-01〜F-06）が Win32 経路であり、そこに WinRT の書き込み経路を混ぜると 2 系統になる。Win32 登録フォーマットは同一 Open/Close 内で完結し、UI スレッド要件もない |
| 影響 | `Clipboard::SetContentWithOptions` は公開経路に存在しない。企画書 DoD の該当記述とエラー表の `SetContentWithOptions` 由来 `false` は本設計では適用外 |
| 対応 | 企画書側の DoD / エラー表から `SetContentWithOptions` を外すか「WinRT 経路を採る場合のみ」と限定する（要反映） |

---

## エラーコード / メッセージ対応表

Bridge は数値コードを返し、文字列化は呼び出し側（Unity C# / サンプルアプリ）が行う。ログ用の英語メッセージを Manager 内に持つ。

| コード | ログメッセージ（英語 / `agent-rules` 準拠） | Unity 側の想定表示 |
|---|---|---|
| 0 | — | — |
| 1 | `Invalid parameter` | 引数が不正です |
| 2 | `Clipboard manager is not initialized` | 初期化されていません |
| 3 | `Clipboard is held by another process` | 他のアプリが使用中です |
| 4 | `Clipboard is empty` | クリップボードが空です |
| 5 | `Requested format is not available` | 対応する形式がありません |
| 6 | `Clipboard data failed validation` | データが不正です |
| 7 | `Buffer too small; required size returned` | バッファ不足 |
| 8 | `Out of memory` | メモリ不足です |
| 9 | `Access to clipboard history is denied` | 履歴へのアクセスが拒否されました |
| 10 | `Clipboard history is disabled` | 履歴機能が無効です |
| 11 | `History item was already deleted` | 項目は既に削除されています |
| 12 | `Failed to register or unregister the clipboard listener` | 監視の登録に失敗しました |
| 13 | `Rollback failed; clipboard may hold partial content` | 一部データが残っている可能性があります |
| 14 | `API must be called from the owner UI thread` | 呼び出しスレッドが不正です |
| 15 | `Request was canceled` | キャンセルされました |
| 16 | `Operation is not supported on Windows` | この操作は未対応です |
| 17 | `App is not in the foreground` | アプリが前面にありません |
| 18 | `Calling thread is not an initialized STA` | 初期化条件が満たされていません |
| 19 | `Unexpected failure (raw code logged)` | 不明なエラー |

**規約**: `UNKNOWN` を返す場合、生の `GetLastError()` / `HRESULT` を必ず `DFLog` に残す（握り潰さない）。

---

## テスト設計

### 単体テスト（`WindowsLibraryTest` / MSTest）

WinRT / Win32 ランタイム非依存で実行できるものに限定する。

#### `ClipboardFormatsTest.cpp`（純ロジック）

| ケース | 種別 | 内容 |
|---|---|---|
| CheckedAdd / Mul / ToInt / ToUInt | 境界値 | `SIZE_MAX` 近傍、`INT_MAX` / `UINT_MAX` 超過で false |
| BuildCfHtml 正常 | 正常 | オフセット 4 値がヘッダ長 + 固定 prefix から正しく算出される |
| BuildCfHtml マーカー混入 | 異常 | 入力フラグメントが `<!--EndFragment-->` を含んでも切れない |
| ParseCfHtmlHeader 正常 | 正常 | フラグメントのみを返す |
| ParseCfHtmlHeader 必須キー欠落 | 異常 | `StartFragment` / `EndFragment` 欠落で false |
| ParseCfHtmlHeader 既知キー重複 | 異常 | 同一キー 2 回で false |
| ParseCfHtmlHeader 不正値 | 異常 | `-10` / `123x` / 空値で false |
| ParseCfHtmlHeader Version | 異常 | 空値 / 不明値で false、`0.9` / `1.0` で true |
| ParseCfHtmlHeader ヘッダ終端 | 異常 | `StartHTML` がヘッダ内を指す入力、キー順入れ替えで false |
| ParseCfHtmlHeader 範囲外の既知キー | 正常 | HTML 本文中の同名文字列を拾わない |
| ParseCfHtmlHeader Selection | 異常 | 片側のみ / 逆順 / フラグメント範囲外で false |
| BuildDropFiles / ValidateDropFiles | 正常・異常 | 二重 NUL 終端、`pFiles` 範囲外、サイズ不足 |
| ValidateDib | 異常 | 不正な `biPlanes` / `biBitCount` / `biCompression` / stride 超過 / パレット範囲外 |
| ValidateUnicodeTextBlock | 異常 | 終端 NUL なし、`sizeof(wchar_t)` の倍数でないサイズ |

#### `ClipboardManagerTest.cpp`（オーケストレーション / Mock backend）

既存 `NotificationManagerTest.cpp` の `MockBackend` パターンに倣う。

| ケース | 種別 | 内容 |
|---|---|---|
| 未初期化での呼び出し | 異常 | `NOT_INITIALIZED` |
| 履歴ステータス変換 | 正常・異常 | `Success` / `AccessDenied` / `ClipboardHistoryDisabled` / `ItemDeleted` が個別のコードへ変換される |
| `bool` 戻り値の変換 | 異常 | `DeleteItem` / `ClearUnpinned` の false が `UNKNOWN`（`ACCESS_DENIED` にしない） |
| pending の一回限り | 正常 | 完了 → コールバック 1 回。二重完了で 2 回目は呼ばれない |
| キャンセルと完了の競合 | 境界 | 取り出せた側だけが処理する |
| `Uninit` のドレイン | 異常 | 未処理要求へキャンセル通知 1 回、以降の完了で呼ばれない |
| コールバックの例外 | 異常 | 投げてもプロセスが落ちない |
| 受付失敗 | 異常 | リクエスト ID が 0、コールバック 0 回 |
| `DeferredClipboard` の状態遷移 | 異常 | 予約途中失敗 → ロールバック成功 / 失敗（`PARTIAL_STATE` でテーブル保持）。`IClipboardWin32Api` の stub で `SetClipboardData` / `EmptyClipboard` を失敗させる |
| listener 解除失敗 | 異常 | stub で `RemoveClipboardFormatListener` を失敗させ、`Stop()` が false を返し状態を保持する |
| `StartWatch` の途中失敗 | 異常 | 2 件目の登録で失敗させ、1 件目が解除される。解除も失敗した場合は `revokePending_` になり `Start` が拒否される |
| `CanDestroy` | 境界 | トークン残存 / in-flight ありで false、解除完了で true |
| `uninit` の失敗と再試行 | 異常 | `Stop` 失敗で `FALSE` + gate 維持。再呼び出しで成功したら `TRUE` |
| コールバック payload の寿命 | 境界 | Mock が復帰後にポインタを保持しても参照しない（復帰時点で解放済みであることを検証） |
| 非同期 Port の完了制御 | 正常 | Mock backend が完了タイミングを任意に遅延させ、pending が正しく待つ |
| 履歴イベントの配送 | 正常 | `onHistoryChanged` / `onHistoryEnabledChanged` / `onRoamingEnabledChanged` が公開コールバックへ届く |
| 書き込みオプション | 正常 | 全ての copy API で `EXCLUDE_HISTORY` / `EXCLUDE_ROAMING` が同じ登録フォーマットを配置する |
| バッファ不足 | 境界 | `buffer_size` 不足で必要サイズを返し `BUFFER_TOO_SMALL` |
| 遅延 provider の二相呼び出し | 正常・異常 | 1 回目でサイズ、2 回目で実データ。provider がエラーを返した形式はスキップされ他は継続する |
| **lease と shutdown の競合** | 境界 | 開始済みコルーチンが未完了の間は `CanDestroy` が false、`uninit` が `FALSE`。コルーチン完了後に `TRUE` |
| **キャンセル後のコルーチン継続** | 境界 | `cancel` 後もコルーチンは完走し、その間 backend が破棄されない（use-after-free なし） |
| **`TryEnter` と `Close` の原子性** | 境界 | `Close` 後の `TryEnter` は必ず失敗する。`CanDestroy == true` の直後に lease が取れないこと |
| **コールバックの非再入** | 境界 | UI スレッドから呼んでも、公開 API から復帰する前にコールバックが呼ばれない |
| **cancel の配送** | 正常 | 非 UI スレッドからの `cancel` が UI スレッドで処理され、コールバックが UI スレッドで 1 回発火する |
| **`setClipboardHistoryCallbacks`** | 正常・異常 | 非 UI スレッドで `WRONG_THREAD`。全 `nullptr` で購読停止。多重呼び出しで置換。部分失敗で旧設定が維持される |
| **非テキスト履歴項目** | 境界 | テキストなし項目が `"text": null` で含まれ、要求全体は成功する |
| **フォアグラウンド判定** | 異常 | 前面でない場合 `NOT_FOREGROUND`（`HISTORY_DISABLED` や `ACCESS_DENIED` にしない） |
| **自書き込み履歴の並行更新** | 境界 | 複数スレッドからの連続コピーが UI スレッド処理前に積まれても、それぞれの通知が抑止される。リング溢れ時は最古が捨てられるだけで誤動作しない |
| **ドレインの非再入** | 境界 | `uninit` の内部からコールバックが呼ばれない。初回 `uninit` は pending があれば `FALSE`。ポンプを回して再呼び出しで `TRUE` |
| **キャンセル後の完了権** | 境界 | キャンセルで完了権が取られた後、コルーチンが完走して take に失敗し結果を捨てる（コールバックは 1 回のみ） |
| **`cancelClipboardRequest` の戻り値** | 異常 | 未知 ID / 完了済み / 投入失敗で `FALSE` と `pError` |
| **`reserveDeferredFormats` のスレッド** | 異常 | 非 UI スレッドから呼ぶと `WRONG_THREAD` |
| **アパートメント検査** | 異常 | MTA / 未初期化スレッドからの `init` が `WRONG_APARTMENT` |
| **履歴コールバックの置換** | 正常 | 置換で WinRT トークンが張り替わらず、重複通知が起きない。in-flight ハンドラは古いスナップショットを使い切る |
| **Domain 型と JSON の対応** | 正常 | `text` が `nullopt` の項目が `"text":null` として出力され、`contentTypes` が列挙される |
| **`Queued` 状態の所有権** | 境界 | 受付後・開始前にキャンセル / ドレインされた場合、入力値と lease がその場で破棄される（リークなし） |
| **`Queued`→`Running` の move** | 正常 | WndProc 受信で入力値と lease がコルーチンフレームへ移り、エントリには完了権だけが残る |
| **コルーチン生成失敗** | 異常 | フレーム確保を失敗させ、開始側の `try/catch` が `OUT_OF_MEMORY` で pending を終端する（terminate しない） |
| **ドレイン後の通常完了** | 境界 | `uninit` 後にコルーチンが完走しても完了権が取れず、成功コールバックが出ない（`CANCELED` のみ 1 回） |
| **`uninit` の重複投入** | 境界 | `uninit` を 2 回以上呼んでも同じキャンセルメッセージが二重に積まれない |
| **closing-work の計上** | 境界 | `Close` 後、未配送のドレインコールバックが残る間は `CanDestroy` が false |
| **層境界** | 正常 | Data 層の Mock backend が request ID / lease / pending を一切知らずに完了を返せる |

### 統合テスト（実機・実クリップボード）

自動化が難しいため、`WindowsLibraryExample` での手動確認と組み合わせる。

| ケース | 内容 |
|---|---|
| 他アプリとの相互運用 | メモ帳 / Word / ブラウザ / エクスプローラー / ペイントとのコピー・貼り付け |
| `CF_HTML` 互換性 | Word・ブラウザで書式が保持される |
| `CF_HDROP` 互換性 | エクスプローラーとの双方向 |
| 変更監視 | 他アプリのコピーで通知、自書き込みでループしない |
| 遅延レンダリング | 予約 → 他アプリ貼り付けで `WM_RENDERFORMAT` 発火 |
| 履歴除外 | Win+V に残らない |
| 履歴 API | 取得 / 復元 / 削除 / 消去。**pinned item が `ClearHistory` 後も残る** |
| 未パッケージ / MSIX | 両構成で同一挙動 |

### 手動確認項目（企画書のリスク対応）

| リスク | 確認内容 |
|---|---|
| メッセージポンプ不在 | 監視・遅延レンダリング・UI 配送が所有スレッドのポンプ停止時に動かないことを確認し、要件をマニュアルに記載 |
| 管理者権限実行 | UIPI 下で `WM_CLIPBOARDUPDATE` が届くか |
| 未パッケージでの履歴 API | `AccessDenied` を返さないか |
| フォアグラウンド要件 | 非フォアグラウンド時の履歴 API の挙動（例外 / 無視 / 失敗） |
| `OpenClipboard` 失敗 | 実際に返る `GetLastError` 値（`ERROR_ACCESS_DENIED` と断定しない） |
| `PARTIAL_STATE` | 発生条件と `RecoverFromPartialState()` での回復可否 |
| 遅延予約後の形式列挙 | `CloseClipboard` 前後の `IsClipboardFormatAvailable` |

---

## 実装タスク分解

### 先行タスク（基盤）

| ID | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T-01 | プロジェクト設定（`/std:c++20` 適用範囲の確定、`/utf-8`、pch.h への DataTransfer 追加、vcxproj 登録） | 0.5日 | — | 既存 Notification / Dialog を含めて全体がビルドできる。C++20 が全体設定で問題ないか、ファイル単位に留めるかを判断し記録 | 既存コードの破壊がないこと |
| T-02 | エラー定数・公開ヘッダの骨格（`WindowsClipboardManager.h`、typedef、Doxygen コメント） | 0.5日 | T-01 | ヘッダのみでコンパイルが通る。`.def` にエクスポート追加 | 命名が既存 Bridge と揃っているか。エラー定数が全 20 個（`NONE` + 非成功 19 種）そろっているか（`NOT_FOREGROUND` / `WRONG_APARTMENT` を含む） |
| T-03 | 純ロジック実装 + 単体テスト（`WindowsClipboardFormats`、checked 演算、CF_HTML、DROPFILES、DIB 検証） | 1.5日 | T-02 | `ClipboardFormatsTest.cpp` の全ケースが passed | TDD で書かれているか。WinRT / Win32 非依存か |
| T-04 | RAII 基盤 + Win32 失敗注入 seam（`ClipboardScope` / `GlobalMem` / `GlobalLockScope` / `PutFormat` / `IClipboardWin32Api`） | 1.0日 | T-02 | 所有権移譲が成功時のみ行われる。リーク・二重解放なし。stub 差し替えで `SetClipboardData` / `EmptyClipboard` を失敗させられる | `windows.md` のハンドル所有権規約。seam が本番経路にオーバーヘッドを持ち込まないこと |
| T-05 | `ClipboardLifecycle`（lease / `CloseAndReserveDrainWork` / `ReleaseDrainWork` / `CanDestroy` の原子性）と pending テーブル（`Queued`→`Running`→`Finished` の状態機械、完了権の atomic take、drain キュー） | 2.0日 | T-02 | 状態遷移と所有権移動が単体テストで確認できる。ドレイン後に通常完了が勝てない。closing-work が `CanDestroy` に反映される | ロックを 2 つ同時に保持していないこと。コールバック呼び出し中にロックを持たないこと。`Queued` の入力値と lease の破棄漏れがないこと |
| T-05b | `dispatchHwnd` と Manager 骨格（ウィンドウクラス登録 / 生成 / 破棄 / shutdown gate / UI 配送 / コールバックスレッド契約） | 2.0日 | T-04, T-05 | 初回 `init` の呼び出しスレッドを所有スレッドとして採用。`uninit` が失敗を `FALSE` で返し再試行できる。全コールバックが公開 API 復帰後に UI スレッドで発火する | ホスト HWND と `dispatchHwnd` を混同していないこと。`SendMessage` を使っていないこと。UI スレッド経路でも `PostMessage` を経由していること |

### 後続タスク（機能）

| ID | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T-06 | F-01 テキスト コピー / ペースト | 0.5日 | T-03, T-04 | メモ帳と双方向で動作。境界検証が効く | checked 演算の適用 |
| T-07 | F-02 HTML コピー / ペースト | 1.0日 | T-03, T-04 | Word / ブラウザで書式保持。フラグメントのみ取得 | UTF-8 とバイトオフセット |
| T-08 | F-03 ファイル一覧 | 1.0日 | T-03, T-04 | エクスプローラーと双方向 | `fWide` 固定、`DragQueryFile` のバッファ長 |
| T-09 | F-04 画像（DIB） | 1.0日 | T-03, T-04 | ペイントと双方向。`CF_BITMAP` からの合成取得 | `ValidateDib` 経由であること |
| T-10 | F-05 独自フォーマット + F-07 内容確認（`getPreferredClipboardFormat` を含む） | 1.0日 | T-04 | 登録・列挙・名前解決・優先度判定。0 の多義性を弁別 | `SetLastError` 前置とフォールバック |
| T-11 | F-06 複数フォーマット（`copyMultipleFormats`）+ F-08 クリア | 1.0日 | T-06, T-07 | 情報量の多い順に配置され優先順で貼り付けられる。失敗時に部分状態を残さない | best-effort rollback の契約。JSON スキーマ |
| T-12 | F-09 変更監視 | 1.0日 | T-05b | 登録・解除・自書き込み抑止。解除失敗時に状態を保持して再試行可能 | 状態が `static` でないこと。`dispatchHwnd` に登録していること |
| T-13 | F-10 遅延レンダリング（provider コールバック + 二相呼び出し + `context` 寿命） | 2.0日 | T-05b | 3 状態遷移。全形式が `WM_RENDERALLFORMATS` で配置される。provider 経由でペイロードを生成できる | `EmptyClipboard` を呼んでいないこと。Renderer が HGLOBAL 限定。provider 内でクリップボード API を呼ばせない設計になっているか |
| T-14 | F-11 書き込みオプション（全 copy API 共通の `options`） | 0.5日 | T-06 | 全ての copy API で Win+V に残らない | オプションが一部 API に欠けていないこと |
| T-15 | F-12a `ClipboardHistoryCoordinator` + 非同期 Port + WinRT 実装（可用性 / 取得 / 復元） | 2.5日 | T-05b | Port が非同期コールバック形。UI スレッドで開始し `co_await`。Mock で完了タイミングを制御できる。**Data 層のコルーチンが request ID / lease / pending を参照していない** | Port に `winrt::` / コルーチン型が出ていないこと。Manager が backend を直接呼ばず coordinator を経由していること |
| T-16 | F-12b 履歴の削除 / 消去 / イベント公開 / 寿命契約 | 1.5日 | T-15 | `event_token` の即時保持と明示解除。登録途中失敗の巻き戻し、`CanDestroy`、in-flight 保護。3 イベントが公開コールバックへ届く | `auto_revoke` を使っていないこと。pinned item の扱い。コールバック内 `Stop` の禁止が明記されているか |
| T-17 | F-14 エラー正規化の総仕上げ（未知値のログ保持） | 0.5日 | T-15, T-16 | 同期 WinRT 境界が `InvokeWinRt` 経由。非同期は各具象コルーチンが `try/catch` を持ち、分類は `ClassifyWinRtException()`、完了は共通 `Complete*` ヘルパに集約されている | `std::bad_alloc` の捕捉。汎用テンプレートを復活させていないこと |
| T-18 | Unity Bridge（`UnityWindowsClipboardManager`） | 1.0日 | T-06〜T-17 | Manager への委譲のみ。JSON 受け渡し | ロジックを持っていないこと。Delegate を所有していないこと |
| T-19 | Doxygen コメント / ログの網羅、`.def` 最終確認 | 0.5日 | T-18 | 全公開 API にコメントとログ | `agent-rules` のログ規約 |
| T-20 | サンプルアプリ対応（`design-sample-app` で設計） | — | T-18 | 全サブ機能をネイティブライブラリのみで確認できる。Unity プラグインに依存しない | 依存方向 |

**合計見積**: 約 23.5 日（T-20 を除く）

### 依存関係

```
T-01 → T-02 →┬→ T-03 →┬→ T-06 →┬→ T-11
             │         ├→ T-07 ─┘
             ├→ T-04 ──┼→ T-08
             │         ├→ T-09
             │         ├→ T-10
             │         └→ T-05b
             └→ T-05 ───→ T-05b ─┬→ T-12
                                  ├→ T-13
                                  └→ T-15 → T-16
T-06 → T-14
T-15, T-16 → T-17
(T-06..T-17) → T-18 → T-19 → T-20
```

T-05（ライフサイクル / pending）を T-05b（ウィンドウ / Manager 骨格）より先に置いたのは、lease と atomic take が並行性契約の土台であり、これが確定しないと監視・遅延レンダリング・履歴のいずれも破棄安全性を満たせないため。

T-17 は WinRT 境界の総仕上げであり、履歴イベント（T-16）まで揃ってから行う（レビュー指摘 L1: 表と依存図の不一致を解消）。

---

## リスクと緩和策

企画書のリスク表を実装単位へ写像したもの。詳細な根拠は企画書を参照。

| リスク | 影響タスク | 緩和策 |
|---|---|---|
| `/std:c++20` 切り替えで既存コードが壊れる | T-01 | 先行タスクで全体ビルドを確認。壊れる場合は WinRT 履歴のみファイル単位設定にするか、`Completed` ハンドラ版（C++17）へ切り替え |
| 所有 UI スレッドのポンプ不在 | T-05b, T-12, T-13 | `initClipboardManager` を UI スレッド限定にして toolkit が `dispatchHwnd` を生成する。ポンプ要件を Doxygen とマニュアルに明記。専用スレッド案へ切り替え可能な内部構造にする |
| ホスト HWND と `dispatchHwnd` の混同 | T-05b, T-12, T-13 | listener 登録・`PostMessage`・clipboard owner は必ず `dispatchHwnd`。ホスト HWND はフォアグラウンド判定の参照にのみ使う。公開 API から HWND 引数を排除して取り違えを構造的に防ぐ |
| provider `context` の寿命事故 | T-13 | `context` は呼び出し側所有と明記し、有効期間（予約〜`WM_DESTROYCLIPBOARD` / `uninit` 完了）を Doxygen に記載。provider 内でのクリップボード API 呼び出しを禁止 |
| コールバック payload の寿命事故 | T-05b, T-15 | 「コールバック実行中のみ有効・呼び出し側がコピー」を Doxygen に明記し、単体テストで復帰後の解放を検証 |
| 終了失敗の握り潰し | T-05b, T-16 | `uninitClipboardManager` を `BOOL` + `pError` にし、`canDestroyClipboardManager` で状態を問い合わせられるようにする。UI スレッドをブロックする再試行ループを禁止 |
| 非同期 Port の同期化 | T-15 | Port を完了コールバック形にし、`co_await` を Manager 内に閉じ込める。Mock で完了タイミングを制御できることを T-15 の完了条件にする |
| **開始済みコルーチンの use-after-free** | T-05, T-15, T-16 | `ClipboardLifecycle` の lease をコルーチンフレームへムーブし、終了まで backend / Manager を破棄しない。キャンセルはコルーチンを中断せず、完了まで走らせる |
| **UI スレッドと任意スレッドのデータ競合** | T-05, T-12, T-13 | `DeferredClipboard` / `ClipboardWatcher` の可変状態を UI スレッド専有にし、遅延 API は UI スレッド限定にする。自書き込み履歴のみ **専用 mutex で保護したリングバッファ**（直近 8 件）で受け渡す |
| **`CanDestroy` 判定と入場の競合** | T-05 | `TryEnter` / `Close` / `CanDestroy` を同一 mutex で保護し、判定と入場を原子的に接続する |
| **コールバック再入** | T-05b | UI スレッド経路でも必ず `PostMessage` を経由し、公開 API 復帰後にのみコールバックを発火する |
| **ロック順序によるデッドロック** | T-05 | lifecycle と pending の mutex を同時に保持しない。provider / 公開コールバック呼び出し中はロックを持たない。ただし `uninit` の「完了権の一括 take + `CloseAndReserveDrainWork`」だけは原子性が必要なため、pending → lifecycle の順序を固定した唯一の複合操作として明記する |
| **受付後・開始前の宙ぶらりん** | T-05 | `Queued` 状態のエントリが入力値と lease を保持する。開始前キャンセル / ドレインでその場で破棄する |
| **コルーチン生成失敗による terminate** | T-05b, T-15 | コルーチンのエントリ関数に `noexcept` を付けず、開始呼び出しを `try/catch` して `OUT_OF_MEMORY` で終端する |
| **ドレイン後の誤った成功通知** | T-05 | `Close` と同時に完了権を一括 take し、以降のコルーチン完了は take に失敗して結果を捨てる |
| **層境界の侵食** | T-15 | Data 層のコルーチンは Domain 変換と `done` 呼び出しのみ。ID / lease / pending は Manager 側のラムダキャプチャに閉じ込める |
| **フォアグラウンドと履歴無効の混同** | T-15 | 判定を 3 段階に分け、`NOT_FOREGROUND` / `HISTORY_DISABLED` / WinRT ステータス由来を別コードにする |
| WinRT フォアグラウンド要件を満たせない | T-15, T-16 | UI スレッド上で `GetForegroundWindow()` のプロセスを自プロセスと比較して判定し、不成立なら `NOT_FOREGROUND` をコールバックで返す（`IsHistoryEnabled` とは別の判定であり `ACCESS_DENIED` にもしない）。WinRT 呼び出し結果は別途ステータス変換する。非フォアグラウンド時の実挙動の確認を T-15 の完了条件に含める |
| アパートメント不整合 | T-05b, T-15 | `init` で `CoGetApartmentType()` を検査し、STA 以外なら `WRONG_APARTMENT` で初期化しない。toolkit はホストのアパートメントを初期化も解除もしない |
| 未パッケージで履歴 API が拒否される | T-15 | 未パッケージ構成での実機確認を完了条件にする。拒否される場合は履歴機能を「MSIX 限定」として文書化 |
| ハンドル所有権の誤り | T-04 全般 | RAII で強制。`PutFormat` 以外で `SetClipboardData` を直接呼ばない |
| 信頼できない外部入力 | T-03, T-06〜T-10 | 全読み取りパスを検証関数経由にし、失敗系テストを必須にする |
| pending / コールバックの二重呼び出し | T-05 | `CompletePendingRequest` の atomic take に一本化。単体テストで検証 |
| 監視解除失敗後のウィンドウ破棄 | T-05b, T-12 | shutdown gate で `Stop()` 成功を確認するまで破棄しない |
| `PARTIAL_STATE` からの回復不能 | T-13 | Renderer テーブルを保持し `RecoverFromPartialState()` を提供。発生頻度を実機で測定 |

---

## Definition of Done

企画書の D-01〜D-36 を実装単位へ写像する。企画書の DoD が実装完了判定の正本であり、以下はタスク完了時のチェックリストとして使う。

### 機能

- [ ] F-01〜F-08: 各形式のコピー / ペースト / 内容確認 / クリアが他アプリと相互運用できる（企画書 D-01〜D-13）
- [ ] F-09: 変更監視の登録・解除・自書き込み抑止・解除失敗時の再試行（D-14〜D-16）
- [ ] F-10: 遅延レンダリングの全形式配置と 3 状態遷移。**provider コールバックの二相呼び出しでペイロードを生成できる**（D-17, D-32）
- [ ] F-11: 全ての copy API で `options` による履歴 / 同期除外が Win+V に反映される（D-18）
- [ ] F-12: 履歴の取得 / 復元 / 削除 / 消去 / イベント / 可用性。`ClearHistory` 後も pinned item が残ることを確認。**3 イベントが公開コールバックへ届く**（D-19〜D-22）
- [ ] F-06 / F-07: `copyMultipleFormats` と `getPreferredClipboardFormat` が公開 API から利用できる

### 品質

- [ ] F-14: 非成功 19 種のエラーコードが弁別して返る。未知値は生値をログに残す（D-25, D-26）
- [ ] F-15: 境界検証が全読み取りパスと書き込みサイズ計算に適用され、失敗系テストが通る（D-27, D-28）
- [ ] 純ロジックの単体テストが passed（D-30）
- [ ] F-17: 受付契約（0 回 / 1 回）、shutdown gate、in-flight 保護（D-33, D-34）
- [ ] 全 WinRT 境界が共通ラッパ経由（D-35）
- [ ] **全コールバックが所有 UI スレッドで呼ばれ、payload が実行中のみ有効という契約が実装・文書化されている**
- [ ] **`uninitClipboardManager` が解除失敗を `FALSE` で返し、再試行して成功できる**
- [ ] **`IClipboardWin32Api` の stub で `SetClipboardData` / `EmptyClipboard` / listener 解除の失敗を単体テストから再現できる**
- [ ] **履歴 Port が非同期（完了コールバック）形で、Mock から完了タイミングを制御できる**
- [ ] **`ClipboardLifecycle` が request コルーチン・イベントコールバック・任意スレッド同期 API を横断して in-flight を数え、`TryEnter` / `Close` / `CanDestroy` が原子的である**
- [ ] **キャンセル後も開始済みコルーチンが完走し、その間 backend が破棄されない（use-after-free なし）**
- [ ] **UI スレッド専有の状態に任意スレッドから直接アクセスしていない（`DeferredClipboard` / `ClipboardWatcher`）**
- [ ] **UI スレッドから呼んでも公開 API 復帰前にコールバックが発火しない**
- [ ] **`setClipboardHistoryCallbacks` が UI スレッド限定・同期・置換・部分失敗時の旧設定維持を満たす**
- [ ] **フォアグラウンド判定・履歴有効判定・WinRT ステータスが別々のエラーコードに正規化される**
- [ ] **非テキスト履歴項目が `"text": null` で含まれ、要求全体が失敗しない。Domain 型（`std::optional<std::wstring> text` / `contentTypes`）と JSON スキーマが一致している**
- [ ] **受付判定が単一経路（引数検証 → lease → pending 登録 → `PostMessage`）で、フォアグラウンド不成立は受付後コールバックで返る**
- [ ] **`uninit` のドレインがコールバックをキューへ積むだけで、初回は `FALSE` を返し、破棄はコールバック発火後に行われる**
- [ ] **完了権（pending）と実行状態（コルーチン）の所有権が分離され、キャンセル後も operation が完走する**
- [ ] **汎用の非同期ラッパテンプレートを使わず、各具象コルーチンが `try/catch` と変換を持ち、全終端で pending がちょうど 1 回完了する。コルーチンフレーム確保失敗は開始側の `try/catch` で `OUT_OF_MEMORY` として終端される**
- [ ] **`init` が STA 検査を行い、MTA / 未初期化なら `WRONG_APARTMENT` で失敗する。toolkit は `uninit_apartment` を呼ばない**
- [ ] **履歴コールバックの置換が snapshot 差し替えで行われ、WinRT トークンを張り替えない**
- [ ] **`reserveDeferredFormats` / `recoverDeferredState` が UI スレッド限定で、他スレッドは `WRONG_THREAD`**
- [ ] **リクエストが `Queued`→`Running`→`Finished` の状態機械で管理され、各状態で入力値と lease の所有者が存在する（受付〜コルーチン終了まで途切れない）**
- [ ] **`uninit` が完了権を一括 take して drain キューへ移すため、失効後の要求へ成功コールバックが出ない**
- [ ] **`Close` 後の未配送ドレインコールバックが closing-work として計上され、`CanDestroy` に反映される**
- [ ] **Data 層の履歴コルーチンが request ID / lease / pending を参照せず、`done(error, items)` のみを呼ぶ**
- [ ] **Manager が backend を直接呼ばず `ClipboardHistoryCoordinator` を経由する（common.md の Manager → UseCase → Repository）**

### 構成

- [ ] F-13: 未パッケージ / MSIX の両構成で同一挙動（D-23, D-24）
- [ ] F-16: MFC × C++/WinRT のヘッダ順序を守ってビルドが通る（D-29）
- [ ] **Manager 層までが `windows/WindowsLibrary` に配置され、`UnityWindowsPlugin` には Bridge 層のみ**（common.md）
- [ ] **`WindowsLibraryExample` が `WindowsLibrary` のみに依存し、全サブ機能を確認できる**（common.md）
- [ ] 既存の Dialog / Notification API に破壊的変更がない
- [ ] 全公開 API に Doxygen コメント、全メソッド先頭にログ（windows.md）

### テスト確認バージョン

| バージョン | 位置づけ |
|---|---|
| Windows 11 25H2（26200） | 主要ターゲット（必須） |
| Windows 11 24H2（26100） | 回帰確認（必須） |
| Windows 11 26H1（28000） | 新規デバイス向け。製品方針として要判断 |
| Windows 11 23H2（22631） | Enterprise / Education エディションのみ対象 |

---

## 企画書へ反映が必要な差分

本設計で企画書の記述を絞り込んだ / 追加した箇所。企画書側の更新が必要。

| 項目 | 企画書の記述 | 本設計の判断 | 対応 |
|---|---|---|---|
| 受付成立点 | 非 UI スレッド経路と UI スレッド直接開始の 2 経路 | **常に `PostMessage` を経由する 1 経路に統一**（再入の構造的排除） | 企画書の 2 経路記述を「実装は 1 経路に統一してよい」と補足するか、設計側の判断として残す |
| `SetContentWithOptions` | 履歴 / 同期除外の選択肢として記載。DoD・エラー表にも登場 | **不採用**。Win32 の登録フォーマットのみを使う | 企画書 DoD / エラー表から外すか「WinRT 経路を採る場合のみ」と限定する |
| エラー一覧 | 非成功 17 種 | **非成功 19 種**（`NOT_FOREGROUND` / `WRONG_APARTMENT` を追加。`NONE` を含め定数は 20 個） | 企画書のエラー対応表に追加する |
| エラー名称 | `INVALID_ARGUMENT` | **`INVALID_PARAMETER`**（既存 `NOTIFICATION_ERROR_INVALID_PARAMETER` と統一） | 企画書の名称を変更する |
| アパートメント事前条件 | 記載なし | `init` の呼び出しスレッドは STA 初期化済みであること。未初期化 / MTA は `WRONG_APARTMENT` | 企画書の要検証事項へ追加する |
| フォアグラウンド判定 | 「満たさない場合は `ACCESS_DENIED` 相当」 | **`NOT_FOREGROUND` として `ACCESS_DENIED` / `HISTORY_DISABLED` と区別する** | 企画書の該当記述を更新する |

---

## 不足前提（企画書に記載がなく本設計で仮置きした事項）

| 項目 | 仮置き | 確定タイミング |
|---|---|---|
| 所有 UI スレッドの供給元 | 呼び出し元（ホスト）のスレッド。`initClipboardManager` を**そのスレッドから呼ばせ**、toolkit が `dispatchHwnd` を生成する。HWND は公開 API で受け渡さない | T-05b の実機確認 |
| `dispatchHwnd` のウィンドウ種別 | 非表示トップレベルウィンドウ（`HWND_MESSAGE` は `WM_CLIPBOARDUPDATE` の到達が未検証のため使わない） | T-05b の実機確認。届くと確認できれば `HWND_MESSAGE` へ変更 |
| フォアグラウンド判定 | `GetForegroundWindow()` のスレッド / プロセスを自プロセスと比較する。ホスト HWND の受け渡しは行わない | T-15 の実機確認 |
| バッファ規約 | `nullptr` / 不足時に必要サイズを戻り値で返す 2 回呼び出し方式（既存 `showFileDialog` 準拠） | T-02 |
| 履歴項目の JSON スキーマ | `[{"id","text"\|null,"contentTypes":[...],"timestamp"}]` / 可用性は `{"historyEnabled","roamingEnabled"}` | T-15 |
| `contentTypes` の値 | `DataPackageView.AvailableFormats` をそのまま出す。既知の `StandardDataFormats`（`"Text"` / `"Bitmap"` / `"StorageItems"` / `"Html"` / `"Rtf"`）に加え、**カスタムフォーマット ID もそのまま含める**（呼び出し側が判別できるようにするため） | T-15 |
| ファイル一覧の受け渡し | JSON 配列文字列 | T-08 |
| 複数フォーマット配置の JSON スキーマ | `[{"format":"...","text|html|base64":"..."}]`（情報量の多い順） | T-11 |
| 画像の受け渡し | DIB バイト列（`BYTE*` + サイズ）。エンコード / デコードは呼び出し側 | T-09 |
| 遅延 provider の二相呼び出し | 1 回目 `buffer=nullptr` でサイズ、2 回目で実データ | T-13 |
| Unity C# 側の API 形 | 本リポジトリの対象外（`unity-native-plugin` 側） | — |
