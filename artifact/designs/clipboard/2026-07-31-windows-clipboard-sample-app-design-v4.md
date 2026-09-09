# Windows クリップボード サンプルアプリ 実装計画 v4

## 基本情報

- 日付: 2026-07-31
- 機能名: Windows Clipboard Manager
- 対象OS: Windows 11 以降
- 対象サンプルアプリ: `windows/WindowsLibraryExample`（WinUI 3 / C++/WinRT / MSIX パッケージ済み）
- 設計書: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- 実装結果: `artifact/results/clipboard/2026-07-30-windows-clipboard-implementation-feature-result-v4.md`
- 前版: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v3.md`
- 対応レビュー: `artifact/reviews/clipboard/2026-07-31-windows-clipboard-sample-app-design-review-v3.md`
- ブランチ: `feature/NTKIT-13`
- 対応タスク: 機能設計書 T-19（サンプルアプリ対応）

---

## 0. v3 からの変更点（レビュー v3 対応）

| 指摘 | 対応 | 反映箇所 |
|---|---|---|
| H1 private access と weak 型が未確定 | `RunOnWorker` をページの private member に、`CompleteWorkerOperation` を implementation class の public member に確定。weak の実型も確定 | 3.5.4, 5.2 |
| H2 busy 解除が `work()` 以外の例外を覆わない | busy 解除責務を `shared_ptr` の deleter（busy token）に持たせ、UI 側の launch 例外・completion 構築例外・`TryEnqueue` 例外・OOM を全て覆う | 3.5.3, 3.5.4, 5.6 |
| H3 busy 中の UI-affine API 並行実行 | worker busy 中は UI 直呼び API も原則拒否し、例外を `CanDestroy` のみに限定 | 3.5.3, 5.1 |
| M1 pending drain が非決定的 | `Request + Immediate Uninitialize` 専用ボタンを追加し、同一ハンドラ内で受付直後に Uninit を呼ぶ | 5.1, 6.5 |
| M2 Threading ボタンの precondition | `NoStateGuard` -> `ReadyRequired` に変更（`NOT_INITIALIZED` が `WRONG_THREAD` より先に返るため） | 3.5.2, 5.1 |
| M3 Force Initialize の precondition | `ShuttingDownRequired` を追加 | 3.5.2, 5.1 |
| M4 busy テストが操作速度依存 | `Delayed Worker Check` ボタンを追加し、busy 系テストの再現手段を決定的にする | 5.1, 6.5 |
| L1 cleanup の非同期性 | `Uninitialize succeeded; temp cleanup pending` -> cleanup 完了をログへ、の 2 段表示に変更 | 5.1, 5.3 |
| L2 `NOT_INITIALIZED` の補足文言 | `g_managerState` を見て `ShuttingDown` では Uninitialize 再試行を案内する | 1.3, 5.2 |

### 0.1 レビュー指摘の検証結果

反映前に、指摘対象を実装コードで確認した。

| 指摘 | 確認内容 | 結果 |
|---|---|---|
| H1 | `winrt::get_self` は projected object から implementation object を得る手段で、C++ のアクセス制御は回避しない | 指摘は妥当。private メソッドを無名 namespace の lambda から呼ぶ設計は成立しない |
| H3 | `ClipboardWatcher::SelfWriteTransaction` のコンストラクタは `lock_(owner.selfWriteMutex_)` で mutex を取得し、トランザクション破棄まで保持する。`ReserveDeferredFormats` / 各 Copy API はいずれもこのトランザクションを使う | **worker の Copy 実行中に UI スレッドで Reserve を押すと、UI スレッドが `selfWriteMutex_` 待ちでブロックする**。worker 化で避けた UI ブロックが復活する。指摘は妥当 |
| M2 | `AcquireOwnerContext` は `!initialized_` -> `NOT_INITIALIZED` を、`GetCurrentThreadId() != ownerThreadId_` -> `WRONG_THREAD` より**先**に判定する。`ClipboardManager::Uninit` も `!initialized_` -> `TRUE + NONE` を thread 判定より先に返す | `NoStateGuard` では `WRONG_THREAD`(14) を保証できない。指摘は妥当 |
| M3 | `ClipboardManager::InitClipboardManager` は `initialized_ == true` かつ owner thread なら `NONE` を返す（冪等成功）。`Uninitialized` から押せば通常の新規 Init になる | `Force Initialize while shutting down` は `ShuttingDown` でしか意図した結果にならない。指摘は妥当 |

### 0.2 レビュー案から選択・確定した箇所

**H1: 3 案のうち採用したもの**

`RunOnWorker` を `ClipboardPage`（implementation class）の **private member function** にし、`CompleteWorkerOperation` を **implementation class の public member function**（IDL には出さない）にする。

- member function 内で定義した lambda は、その member と同じアクセス権を持つ。したがって completion lambda から implementation の member を呼べる
- そのうえで `CompleteWorkerOperation` を public にしておくのは、`winrt::get_self` が返すのが「implementation class へのポインタ」であり、アクセス経路を lambda のスコープ規則だけに依存させないため。IDL に出さないので projected type には現れず、外部から到達できるわけではない
- 「コンパイルで確認」には残さない。上記を確定仕様とする

**H2: busy 解除の所有権モデル**

RAII scope guard ではなく、**`std::shared_ptr` の deleter による busy token** を採用する。理由は、解除責務が UI スレッド -> worker delegate -> completion lambda と 2 回移動するため、scope guard の `Dismiss()` / 再取得を手で書くより、コピー可能な token が最後に破棄された時点で自動解除される形のほうが漏れる経路を作りにくいこと。詳細は 3.5.3。

**H3: busy 中に許可する UI 直呼び API**

レビュー案どおり `CanDestroy` のみに限定する。v3 が「pending 中 Uninitialize の確認のため」として UI API 全体を許可していたのは、確認対象（history request の pending）と `g_workerBusy`（同期 worker 操作）が無関係であることを見落としていた。M1 の専用ボタン導入により、pending drain の確認は busy とは独立に行える。

---

## 1. 前提情報の抽出（設計書 / 実装結果由来）

### 1.1 in-scope 機能

| No | サブ機能 | サンプルでの確認手段 |
|---|---|---|
| F-01 | プレーンテキスト コピー / ペースト | ボタン + 結果表示 |
| F-02 | HTML コピー / ペースト | ボタン + 結果表示（互換性は他アプリで手動確認） |
| F-03 | ファイル一覧 コピー / ペースト | 一時ファイル生成 + ボタン |
| F-04 | 画像（DIB）コピー / ペースト | コード内生成 DIB + ボタン |
| F-05 | 独自フォーマット コピー / ペースト | 登録フォーマット名 + ボタン |
| F-06 | 複数フォーマット同時配置 | `copyMultipleFormats` ボタン（正常系 + 拒否系） |
| F-07 | 内容確認（有無 / 列挙 / 優先度） | ボタン + 結果表示 |
| F-08 | クリア | ボタン |
| F-09 | 変更監視 | `initClipboardManager` の `onChanged` をログ領域へ追記 |
| F-10 | 遅延レンダリング | 予約ボタン + provider 呼び出しログ（別アプリでの貼り付けが必要） |
| F-11 | 履歴 / 同期からの除外 | write option 付きコピーボタン + Win+V 手動確認 |
| F-12 | 履歴 取得 / 復元 / 削除 / 消去 / イベント / 可用性 | 非同期ボタン + request callback ログ |
| F-13 | Package Identity 対応 | MSIX 構成での動作確認（未パッケージは本サンプルでは確認不可） |
| F-14 | エラー正規化 | エラーケース用ボタン群で `errorCode` を表示 |
| F-17 | スレッドモデル / Bridge ライフサイクル | Init / Uninit / CanDestroy ボタン + ワーカースレッド呼び出しボタン |

### 1.2 公開 API と入力制約

- 同期 API（任意スレッド可）: `copyPlainText` / `pastePlainText` / `copyHtml` / `pasteHtml` / `copyFiles` / `pasteFiles` / `copyImage` / `pasteImage` / `copyCustomFormat` / `pasteCustomFormat` / `copyMultipleFormats` / `hasClipboardFormat` / `getClipboardFormats` / `getPreferredClipboardFormat` / `clearClipboard`
- 同期 API（所有 UI スレッド限定）: `reserveDeferredFormats` / `recoverDeferredState`
- 非同期 API（受付 + request callback）: `getClipboardHistory` / `restoreHistoryItem` / `deleteHistoryItem` / `clearUnpinnedHistory` / `getClipboardHistoryAvailability` / `cancelClipboardRequest`
- ライフサイクル: `initClipboardManager` / `setClipboardHistoryCallbacks` / `uninitClipboardManager` / `canDestroyClipboardManager`

入力制約（サンプル側が守る必要があるもの）:

- `initClipboardManager` の呼び出しスレッドが所有 UI スレッドとして採用される。そのスレッドは STA 済みかつメッセージポンプを回し続けている必要がある
- **`uninitClipboardManager` は未初期化なら thread 判定より先に `TRUE + NONE` を返す。** 非所有スレッドから `WRONG_THREAD` を得るには、初期化済みであることが前提になる
- **`reserveDeferredFormats` / `recoverDeferredState` は未初期化なら thread 判定より先に `NOT_INITIALIZED` を返す。** 非所有スレッドから `WRONG_THREAD` を得るには、初期化済みであることが前提になる
- **`uninitClipboardManager` は pending がある間 `FALSE` + `CLIPBOARD_ERROR_CANCELED` を返し、teardown は完了しない。** メッセージポンプを回して pending の終端コールバックを消化したあと、再度呼んで `TRUE` を得る必要がある
- **所有 UI スレッドから `uninitClipboardManager` を呼んだ時点で、戻り値に関わらず lifecycle gate は閉じる。** それ以降の同期 API はすべて `NOT_INITIALIZED`(2) を返し、`initClipboardManager` を呼んでも gate は再開しない（冪等成功を返すのみ）
- **すべての Copy API と `reserveDeferredFormats` / `recoverDeferredState` は `ClipboardWatcher::SelfWriteTransaction` を使い、操作全体にわたって同一の mutex を保持する。** 複数スレッドから同時に呼ぶと、後発の呼び出しはその mutex を待つ
- バッファ規約: `buffer = nullptr` または不足時に必要サイズが戻り値で返り `pError = CLIPBOARD_ERROR_BUFFER_TOO_SMALL`。呼び出し元は 2 回呼ぶ
- `copyFiles` の `pathsJson` は JSON 配列文字列。空配列 / 空パスは不可
- `copyImage` は DIB バイト列。エンコード / デコードは呼び出し側の責務
- `copyMultipleFormats` の `itemsJson` は `[{"format":"...","text|html|base64":"..."}]`。情報量の多い順に配置する
  - `CF_UNICODETEXT` / `CF_TEXT` は `text`、`HTML Format` は `html`、`CF_DIB` / `CF_HDROP` は `base64`、custom は `base64` のみ
  - `CF_BITMAP` は HBITMAP 所有経路がないため拒否される
  - 同一 format の重複、payload 種別の不一致は `CLIPBOARD_ERROR_INVALID_PARAMETER`
- write option は全コピー API 共通のフラグ（`NONE` / `EXCLUDE_HISTORY` / `EXCLUDE_ROAMING` / `SENSITIVE`）
- 遅延 provider は二相呼び出し。**1 回目の必要サイズと 2 回目の実サイズは完全一致が必須**。provider 内で clipboard API を呼ばない / ブロックしない / throw しない
- request callback の `json` は**コールバック実行中のみ有効**。復帰前にコピーする。失敗時 `json` は必ず `nullptr`
- 受付成功（戻り値が非 0）から終端コールバックまで、関数ポインタを有効に保つのは呼び出し側の責務

### 1.3 エラー契約

`CLIPBOARD_ERROR_NONE`(0) 〜 `CLIPBOARD_ERROR_UNKNOWN`(19) の 20 定数。サンプルでは数値コードをそのまま表示し、特定コードにだけ補足文言を付ける。

| コード | 定数 | サンプルでの補足文言方針 |
|---|---|---|
| 2 | `NOT_INITIALIZED` | **`g_managerState` で分岐する**【L2】。`Uninitialized` なら Initialize を促す。`ShuttingDown` なら「CanDestroy が TRUE になってから Uninitialize を再実行してください」を促す |
| 4 | `EMPTY` | クリップボードが空であることを明示 |
| 5 | `FORMAT_UNAVAILABLE` | 対象形式が現在のクリップボードに無いことを明示 |
| 10 | `HISTORY_DISABLED` | Windows 設定でクリップボード履歴を有効化するよう促す |
| 13 | `PARTIAL_STATE` | Recover Deferred State を押すよう促す |
| 14 | `WRONG_THREAD` | 所有 UI スレッド限定 API であることを明示 |
| 15 | `CANCELED` | Uninitialize の場合は pending 消化後に再実行するよう促す |
| 17 | `NOT_FOREGROUND` | アプリを前面にしてから再実行するよう促す |
| 18 | `WRONG_APARTMENT` | 初期化スレッドが STA でないことを明示 |

その他のコードは `errorCode=<n>` の数値表示のみ。

**サンプル由来のエラーは Domain error と区別する**。`errorCode=<n>` は Bridge が返した値だけに使い、サンプル側の例外・検証失敗は `Sample operation failed: <reason>` の形で別区分として表示する。

### 1.4 テスト観点（設計書由来）

設計書「統合テスト（実機・実クリップボード）」「手動確認項目」がサンプルアプリの確認対象。第 6 章に展開する。

### 1.5 不足前提（本計画で追加判断が必要だった点）

- WinUI 3 の UI スレッドを所有 UI スレッドとして採用してよいか（アパートメント判定を通るか）
- 遅延 provider 内から XAML を触ってよいか
- 同期 Bridge を逃がす worker の所有・完了配送・例外時の busy 解除（v2 で追加、v4 で確定）
- ページ再生成をまたぐ manager 状態と busy 状態（v2 で追加、v3 で 3 状態化）
- ページ離脱中に完了した履歴 callback の扱い（v3 で確定）
- pending drain を決定的に発生させる操作（v4 で追加）
- サンプルが用意する DIB / 独自フォーマット / ファイルの具体値
- ログ表示領域の追加（既存サンプルには結果表示 1 行のみで、ログ領域が存在しない）

---

## 2. 既存サンプルコードの深掘り結果

### 2.1 確認した既存コード

| パス | 確認内容 |
|---|---|
| `windows/WindowsLibraryExample/MainMenuPage.xaml` / `.xaml.cpp` | メニューカード（`Button` + 2 行 `TextBlock`）と `NavigateTo(pageTypeName)` による `Frame().Navigate` |
| `windows/WindowsLibraryExample/NotificationPage.xaml` / `.xaml.h` / `.xaml.cpp` | Back ボタン + タイトル + `ResultTextBlock`、`ScrollViewer` 内のカテゴリ別ボタン群、`EnsureInitialized` / `ShowResult` / `SetResultText`、C コールバックの forwarding hub と `DispatcherQueue().TryEnqueue` |
| `windows/WindowsLibraryExample/DialogPage.xaml` / `.xaml.cpp` | 同一の Back + 結果表示パターン（同期 API のみ） |
| `windows/WindowsLibraryExample/App.xaml` | `DialogButtonStyle` / `NotificationButtonStyle`（同一内容の `Button` テンプレート） |
| `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj` | `Page` / `Midl` / `ClCompile` / `ClInclude` の 4 箇所へページを登録。`/bigobj /utf-8` が全構成に適用済み。`WindowsLibrary` への `ProjectReference` と include パスが既に存在 |
| `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj.filters` | `Assets` フィルタのみ。ページ類はルート直下 |
| `mac/MacLibraryExample/MacLibraryExample/`（主参照ペア） | `ContentView` / `DialogSampleView` / `NotificationSampleView` / `ShareSampleView`。**クリップボードのサンプル画面は存在しない** |
| `android/.../example/ClipboardSampleScreen.kt` | クリップボード機能のセクション分割（Copy / Sensitive / Read / Clear / Observe / Error cases）と、エラーケース専用ボタン群 |

### 2.2 主参照ペアの扱い

- workflow の相互参照ペアは Windows ⇔ macOS だが、**macOS 側にクリップボードのサンプル画面が存在しない**。画面構成は Windows 自身の既存 `NotificationPage` を正本とする
- 機能カテゴリの切り方のみ Android の `ClipboardSampleScreen.kt` を参照し、Windows 固有機能（遅延レンダリング / 複数フォーマット / 履歴 / スレッド）を追加する

### 2.3 再利用する既存コンポーネント

- `MainMenuPage` のメニューカードと `NavigateTo`
- `NotificationPage` の画面骨格: `Grid` 2 行（固定ヘッダ + `ScrollViewer`）、`Width="600"` 中央寄せ、Back ボタン、タイトル `FontSize="28"`、`Border` + `ResultTextBlock`
- `NotificationButtonStyle`（`App.xaml` の既存スタイル）。**Clipboard 用の新スタイルは追加しない**
- `EnsureInitialized` / `ShowResult(method, err)` / `SetResultText(text)` の 3 ヘルパー構成
- C コールバックの forwarding hub パターン（無名 namespace の `std::function` + free function thunk + `winrt::make_weak` + `DispatcherQueue().TryEnqueue`）
- `DLog` / `DFLog`（`common.h`）

### 2.4 追加するコンポーネント

| 追加物 | 配置 | 理由 |
|---|---|---|
| ログ表示領域（`LogTextBlock` + `ScrollViewer`） | XAML | F-09 / F-10 / F-12 は「1 行の結果表示」では時系列が見えない |
| `AppendLog(line)` | ページ private | タイムスタンプ付きで追記し、上限行数で古い行を捨てる |
| `CompleteWorkerOperation(WorkerResult const&)`【v4 / H1】 | **ページ public**（IDL 非公開） | worker 完了時の結果表示・ログ追記を 1 箇所に集約する |
| `RunOnWorker(method, work, busyToken)`【v4 / H1】 | **ページ private member** | 同期 Bridge を worker で実行する task runner。member 内 lambda から implementation member を呼べるようにする |
| `CheckPrecondition(WorkerPrecondition)`【v4 / M2, M3】 | ページ private | 4 種の precondition を判定して案内を表示する |
| `g_managerState`（3 状態） | 無名 namespace | ページ再生成をまたいで manager の利用可否を判定する |
| `g_workerBusy`（`std::atomic<bool>`）+ busy token【v4 / H2】 | 無名 namespace | クリップボード操作の直列化と、例外を含む全経路での解除保証 |
| `WorkerResult` 構造体 | 無名 namespace | 成功 / Bridge error / sample 例外を単一の完了ペイロードへ正規化する |
| `PasteToBuffer` ヘルパー（2 回呼び出し） | 無名 namespace | 5 つの paste API がすべてバッファ 2 回呼び出し規約のため |
| 遅延 provider の payload ストア（静的マップ） | 無名 namespace | provider の `context` はページ寿命と独立に有効でなければならない |
| サンプルデータ生成ヘルパー（DIB / 一時ファイル / base64 エンコード） | 無名 namespace | `copyImage` / `copyFiles` / `copyMultipleFormats` の入力を作るため |

### 2.5 変更するファイルと変更理由

| ファイル | 区分 | 理由 |
|---|---|---|
| `windows/WindowsLibraryExample/ClipboardPage.xaml` | 新規 | クリップボードサンプル画面の XAML |
| `windows/WindowsLibraryExample/ClipboardPage.xaml.h` | 新規 | ページ実装クラス宣言 |
| `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp` | 新規 | ページ実装 |
| `windows/WindowsLibraryExample/ClipboardPage.idl` | 新規 | `runtimeclass` 宣言（既存ページと同形式。`CompleteWorkerOperation` 等は公開しない） |
| `windows/WindowsLibraryExample/MainMenuPage.xaml` | 既存変更 | Clipboard メニューカードの追加 |
| `windows/WindowsLibraryExample/MainMenuPage.xaml.h` | 既存変更 | `ClipboardCard_Click` の宣言 |
| `windows/WindowsLibraryExample/MainMenuPage.xaml.cpp` | 既存変更 | `ClipboardCard_Click` の実装（`NavigateTo`） |
| `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj` | 既存変更 | `Page` / `Midl` / `ClCompile` / `ClInclude` へ 4 エントリ追加 |

---

## 3. 実装方針

### 3.1 共通実装パターン: 維持する点

- メインメニュー -> サンプル画面の導線（`Frame().Navigate` / Back は `Frame().GoBack()`）
- 画面先頭にタイトルと結果表示領域
- 機能カテゴリ単位のボタン群（`TextBlock` のセクション見出し + `NotificationButtonStyle` のボタン）
- 実行前チェックの helper 化
- 公開 API 呼び出しの前後にログを残す（`DLog` / `DFLog`）
- C コールバック -> forwarding hub -> `DispatcherQueue().TryEnqueue` で UI 反映
- 既存の project / solution 構成は変更しない
- 成功 / 失敗マーカー記号（既存 `NotificationPage` と同じ。`/utf-8` 済みのためソースに直接書いてよい）
- **全 UI 文言を英語で書く**。`windows.md`「コメントと言語ポリシー」はログだけでなく UI テキスト・statusText・ダイアログ文言も英語と定めている

### 3.2 共通実装パターン: 拡張する点

| 拡張 | 内容 | 理由 |
|---|---|---|
| 結果表示 + ログ表示の 2 段構成 | ヘッダに `ResultTextBlock`（最新 1 件 + 状態）を残し、その下に固定高さ + `ScrollViewer` の `LogTextBlock` を追加 | 変更監視 / provider 呼び出し / request callback の時系列が確認対象そのもの |
| 同期 Bridge の worker 実行 | 任意スレッド対応の同期 API と同期 I/O は worker で実行 | `ClipboardScope` は `OpenClipboard` を 10 回 + `Sleep(10)` でリトライするため、最大約 100ms UI が止まる |
| process-lifetime の状態管理 | manager 状態（3 状態）と worker busy をページ外に持つ | ページ再生成をまたいで一貫した判定と直列化を行うため |
| **クリップボード操作の全面直列化**【v4 / H3】 | worker busy 中は UI 直呼び API も原則拒否する | すべての Copy API と Reserve / Recover が同一の `selfWriteMutex_` を操作全体にわたって保持するため、並行実行すると UI スレッドが mutex 待ちになる |
| コールバック内での UI 更新の抑制 | 遅延 provider の中では XAML を触らず、ログ行を組み立てて `TryEnqueue` で後から反映 | provider は `WM_RENDERFORMAT` 処理中に呼ばれ、ブロック禁止・clipboard API 呼び出し禁止の契約があるため |
| エラーケース専用セクション | 意図的に失敗させるボタンを分離 | `errorCode` の正規化（F-14）を確認対象にするため |

### 3.3 呼び出し境界

- サンプルは `WindowsLibrary` の C Bridge（`WindowsClipboardManager.h`）のみを直接呼ぶ。内部ヘッダは参照しない
- Unity プラグイン（`windows/UnityWindowsPlugin`）へは依存しない
- 依存方向チェックの結果: **Unity プラグイン経由でしか呼べない API は存在しない**。Bridge 27 関数すべてが `WindowsLibrary.def` からエクスポートされており、サンプルから到達可能
- `WINDOWSLIBRARY_EXPORTS` はサンプル側で未定義のため `__declspec(dllimport)` になり、`ProjectReference` 経由の import ライブラリでリンクされる

### 3.4 所有 UI スレッドの扱い

- `initClipboardManager` は `ClipboardPage` の Initialize ボタンハンドラから呼ぶ。XAML のイベントハンドラは必ず WinUI の UI スレッドで走るため、そのスレッドが所有 UI スレッドになる
- WinUI 3 の UI スレッドはメッセージポンプを回し続けるため、`WM_CLIPBOARDUPDATE` / `WM_RENDERFORMAT` / `WM_APP_*` の配送要件を満たす
- アプリ起動時（`App.xaml.cpp`）では初期化しない
- `OnNavigatedFrom` で `uninitClipboardManager` は呼ばない。forwarding hub のみ解除する

### 3.5 同期 Bridge の実行スレッドと task runner

#### 3.5.1 実行スレッドの分類

**UI スレッドから直接呼ぶ API**

- `initClipboardManager` / `setClipboardHistoryCallbacks` / `uninitClipboardManager`（所有 UI スレッド限定）
- `reserveDeferredFormats` / `recoverDeferredState`（所有 UI スレッド限定）
- `getClipboardHistory` / `restoreHistoryItem` / `deleteHistoryItem` / `clearUnpinnedHistory` / `getClipboardHistoryAvailability` / `cancelClipboardRequest`（受付のみで即時復帰）
- `canDestroyClipboardManager`（状態照会のみ）

**worker で実行する API**

- `copyPlainText` / `copyHtml` / `copyFiles` / `copyImage` / `copyCustomFormat` / `copyMultipleFormats`
- `pastePlainText` / `pasteHtml` / `pasteFiles` / `pasteImage` / `pasteCustomFormat`
- `hasClipboardFormat` / `getClipboardFormats` / `getPreferredClipboardFormat` / `clearClipboard`
- 一時ファイルの生成・削除
- Threading セクションの検証ボタン（意図的に worker から UI 限定 API を呼ぶ）

#### 3.5.2 precondition【M2, M3】

`RunOnWorker` は**状態 guard を持たない**。precondition の判定は `CheckPrecondition()` がボタンハンドラの先頭で行う。

| 種別 | 通過条件 | 適用ボタン |
|---|---|---|
| `ReadyRequired` | `g_managerState == Ready` | 通常の Copy / Paste / Inspect / Clear / Deferred / History、**および Threading の 2 ボタン**【M2】 |
| `AnyState` | 常に通過 | Cleanup Temp Files（Bridge を呼ばない） |
| `ShuttingDownRequired`【M3】 | `g_managerState == ShuttingDown` | Force Initialize while shutting down |
| `NoStateGuard` | 常に通過（状態 guard を意図的に外す） | `CopyPlainText (after Uninitialize)` |

Threading の 2 ボタンを `ReadyRequired` にする理由: `AcquireOwnerContext` は `NOT_INITIALIZED` を `WRONG_THREAD` より先に返し、`Uninit` は未初期化なら thread 判定前に `TRUE` を返す。Ready 状態でなければ期待する `WRONG_THREAD`(14) を観測できない。

通過しなかった場合は API を呼ばず、状態別の案内を表示する（例: `ShuttingDownRequired` が満たされないときは「Request + Immediate Uninitialize を先に実行して shutdown-pending 状態を作ってください」）。

#### 3.5.3 直列化と busy の所有権【H2, H3】

**busy state**

- process-lifetime の `std::atomic<bool> g_workerBusy`
- 解除責務は **busy token**（`std::shared_ptr<void>` にカスタム deleter を付けたもの）が持つ

```
// UI スレッド。取得は atomic 交換のみ（allocation なし）
if (g_workerBusy.exchange(true))
{
    SetResultText(L"Busy: another clipboard operation is running");
    return;
}

std::shared_ptr<void> busyToken;
try
{
    // deleter が唯一の解除経路。token が最後に破棄された時点で必ず解除される
    busyToken = std::shared_ptr<void>(nullptr, [](void*) { g_workerBusy.store(false); });
    RunOnWorker(L"CopyPlainText", std::move(work), busyToken);
}
catch (...)
{
    if (!busyToken) g_workerBusy.store(false);  // token 生成前に失敗した場合のみ手動解除
    // token 生成後に失敗した場合は、スコープ終了時の破棄で解除される
    SetResultText(失敗マーカー + L"[CopyPlainText] Sample operation failed: could not start worker");
}
```

token は worker delegate と completion lambda にコピーされる。**最後のコピーが破棄された時点で必ず解除される**ため、次のすべての経路が覆われる【H2】。

| 経路 | 解除する主体 |
|---|---|
| 正常完了 | completion lambda の破棄 |
| `work()` が例外を投げる | worker delegate の破棄 |
| `RunAsync` の起動・capture 構築が例外を投げる | UI スレッドのローカル `busyToken` の破棄 |
| busy token 自体の生成が例外を投げる | UI スレッドの `catch` での手動 `store(false)` |
| completion lambda の構築 / `WorkerResult` コピーが例外を投げる | worker delegate の破棄 |
| `TryEnqueue` が `false` を返す | 破棄される completion lambda -> 最終的に worker delegate の破棄 |
| `TryEnqueue` が例外を投げる | worker delegate の破棄 |
| ページが破棄済みで UI 更新できない | completion lambda の破棄（UI 更新のみ no-op） |
| catch 節の文字列構築が再度 OOM になる | worker delegate の破棄（解除は `atomic::store` のみで allocation 非依存） |

**busy 中に許可する操作**【H3】

- 許可: `CanDestroy` のみ
- 拒否: Copy / Paste / Inspect / Clear / Reserve / Recover / History request / Cancel / Initialize / SetHistoryCallbacks / Uninitialize / Cleanup
- 理由: すべての Copy API と Reserve / Recover が `ClipboardWatcher::SelfWriteTransaction` を通じて同一の `selfWriteMutex_` を操作全体にわたって保持する。worker の Copy 実行中に UI で Reserve を押すと、UI スレッドが mutex 待ちでブロックし、worker 化で回避した UI ブロックが復活する
- Uninitialize を拒否する理由: worker が lifecycle lease を取る前に teardown が完了すると、予約済み worker が後から `NOT_INITIALIZED` になる。また Uninitialize 成功時の自動 temp cleanup（worker）が busy で開始できなくなる。busy 中は Uninitialize を拒否することで、これらを構造的に排除する
- pending request -> Uninitialize の確認は `g_workerBusy` と無関係（history request は worker を使わない）。M1 の専用ボタンで独立に実施できる

#### 3.5.4 完了配送と単一出口【H1, H2】

```
struct WorkerResult
{
    std::wstring method;        // 呼び出し元ボタン名（英語）
    bool         sampleFailed;  // true = サンプル側の例外・検証失敗
    DWORD        bridgeError;   // sampleFailed == false のときだけ有効
    std::wstring detail;        // 表示用の補足（英語）
    std::wstring logLine;       // ログ用 1 行（英語、空なら追記しない）
};
```

`RunOnWorker` は `ClipboardPage` の **private member function**。completion lambda を member スコープで構築するため、implementation の member へアクセスできる【H1】。

```
// ClipboardPage.xaml.h（implementation class）
public:
    void CompleteWorkerOperation(WorkerResult const& r);   // IDL には出さない
private:
    void RunOnWorker(std::wstring method,
                     std::function<WorkerResult()> work,
                     std::shared_ptr<void> busyToken);

// ClipboardPage.xaml.cpp
void ClipboardPage::RunOnWorker(std::wstring method,
                                std::function<WorkerResult()> work,
                                std::shared_ptr<void> busyToken)
{
    winrt::weak_ref<WindowsLibraryExample::ClipboardPage> weakPage = get_weak();
    auto dq = DispatcherQueue();

    winrt::Windows::System::ThreadPool::RunAsync(
        [weakPage, dq, method, work = std::move(work), busyToken](auto&&)
    {
        // OOM 時に追加 allocation を必要としないよう、失敗用の結果を先に作る
        WorkerResult result{ method, true, CLIPBOARD_ERROR_NONE,
                             L"Unexpected sample-side failure", L"" };
        try
        {
            result = work();
        }
        catch (const std::bad_alloc&)   { result.detail = L"Out of memory in sample code"; }
        catch (const winrt::hresult_error&) { result.detail = L"WinRT error in sample code"; }
        catch (...)                     { /* 既定の result をそのまま使う */ }

        try
        {
            // busyToken を completion へ渡す。queue 失敗時は lambda ごと破棄され、
            // delegate 側の token 破棄で解除される
            dq.TryEnqueue([weakPage, result, busyToken]()
            {
                if (auto page = weakPage.get())
                {
                    winrt::get_self<implementation::ClipboardPage>(page)
                        ->CompleteWorkerOperation(result);
                }
            });
        }
        catch (...)
        {
            // allocation を伴う処理を行わない。busyToken の破棄が解除する
        }
    });
}
```

要点:

- `get_weak()` は implementation class の基底が提供し、**`winrt::weak_ref<WindowsLibraryExample::ClipboardPage>`（projected 型の weak_ref）** を返す。`get()` は projected 型を返し、`winrt::get_self<implementation::ClipboardPage>()` で implementation へ降りる【H1】
- `CompleteWorkerOperation` は implementation class の public member。IDL に出さないため projected type には現れず、外部からは到達できない【H1】
- **busy 解除は token の deleter だけが行う。** コード上に `g_workerBusy.store(false)` を書くのは、token 生成自体が失敗した UI 側の catch 節のみ【H2】
- 失敗用の `WorkerResult` を try の**前**に構築し、catch 節では文字列リテラルの代入しか行わない。OOM 時に catch 内で再 allocation しない【H2】
- `RunAsync` の戻り値（`IAsyncAction`）は保持しない
- worker 内では XAML を一切触らない

### 3.6 manager 状態の管理

#### 3.6.1 状態定義

```
enum class ManagerState { Uninitialized, Ready, ShuttingDown };
std::atomic<ManagerState> g_managerState{ ManagerState::Uninitialized };
```

| 状態 | 意味 | 許可する操作 |
|---|---|---|
| `Uninitialized` | Init 前、または Uninit が `TRUE` で完了 | InitializeManager、Cleanup Temp Files、`NoStateGuard` のエラーケース |
| `Ready` | Init 成功後で、lifecycle gate が開いている | 全操作（busy 制約は別途） |
| `ShuttingDown` | 所有 UI スレッドの Uninit が `FALSE` を返し、gate が閉じている | CanDestroy、Uninitialize の再試行、Force Initialize テスト、Cleanup Temp Files |

#### 3.6.2 遷移条件

実装コードの確認結果に基づき、**呼び出し経路とエラーコード**で遷移させる。

| 契機 | 条件 | 遷移先 |
|---|---|---|
| `initClipboardManager`（UI ボタン） | `pError == NONE` かつ遷移前が `Uninitialized` | `Ready` |
| `initClipboardManager`（Force Initialize テスト） | 遷移前が `ShuttingDown` | **変化なし**（gate は再開しないため） |
| `initClipboardManager` | `pError != NONE` | 変化なし |
| `uninitClipboardManager`（UI スレッド） | 戻り値 `TRUE` | `Uninitialized` |
| `uninitClipboardManager`（UI スレッド） | 戻り値 `FALSE`（`CANCELED` / `BUSY` / `MONITOR_REGISTER_FAILED` / その他） | `ShuttingDown` |
| `uninitClipboardManager`（worker、Threading 検証ボタン） | 戻り値 `FALSE` かつ `pError == WRONG_THREAD`(14) | **変化なし**。`CloseAndDrain` に到達しないため gate は閉じていない |

`ShuttingDown` では通常の InitializeManager ボタンを押しても API を呼ばず、「CanDestroy が TRUE になってから Uninitialize を再実行してください」と表示する。gate が再開しない挙動そのものの確認は、Error cases の Force Initialize ボタン（`ShuttingDownRequired`）で行う。

#### 3.6.3 状態の表示

- `OnNavigatedTo` で現在の状態を結果表示へ反映する。表示は `Uninitialized` / `Ready` / `Shutting down` の 3 値
- `CheckPrecondition()` は `g_managerState` を判定し、状態別の案内文を出す
- ログ行はページメンバなので再入場でクリアされる。これは仕様として手動確認手順に明記する

### 3.7 ページ離脱中のコールバックの扱い

- **仕様として確定**: ページ離脱中に届いた callback（変更監視・履歴イベント・request 完了）は UI では破棄し、再入場後に復元しない
- 根拠: forwarding hub は `OnNavigatedFrom` で `nullptr` になり、`m_pendingRequests` / `m_lastRequestId` / `m_lastHistoryItemId` はページメンバのため再生成で失われる
- Bridge 側の安全性には影響しない。thunk は常に有効な free function で、hub が null なら何もしない
- 再入場後に届いた「未知の requestId」の callback は、ログへ `unknown request id` として出し、結果表示は変更しない
- 再入場後は `m_lastHistoryItemId` が空になるため、RestoreHistoryItem / DeleteHistoryItem は「GetClipboardHistory を先に押してください」を表示する

---

## 4. 変更ファイル一覧

### 4.1 新規作成

- `windows/WindowsLibraryExample/ClipboardPage.xaml`
- `windows/WindowsLibraryExample/ClipboardPage.xaml.h`
- `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp`
- `windows/WindowsLibraryExample/ClipboardPage.idl`
- `artifact/results/clipboard/YYYY-MM-DD-windows-clipboard-implement-sample-app-result-v1.md`（implement-sample-app で作成）

### 4.2 既存変更

- `windows/WindowsLibraryExample/MainMenuPage.xaml`
- `windows/WindowsLibraryExample/MainMenuPage.xaml.h`
- `windows/WindowsLibraryExample/MainMenuPage.xaml.cpp`
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj`

### 4.3 非変更（対象だが変更しない）

- `windows/WindowsLibrary` 配下すべて（機能側は実装済み。第 8 章の報告事項は本計画では変更しない）
- `windows/UnityWindowsPlugin`
- `windows/WindowsLibraryExample/App.xaml`（既存 `NotificationButtonStyle` を再利用）
- `windows/WindowsLibraryExample/App.xaml.cpp` / `MainWindow.xaml*`（起動時初期化を行わない）
- `windows/WindowsLibraryExample/Package.appxmanifest`（追加 capability 不要）
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj.filters`
- `windows/WindowsLibraryExample/WindowsLibraryExample.sln`

---

## 5. 実装詳細（implement-sample-app ステップ3で行う内容）

### 5.1 画面構成

```
MainMenuPage
  [Dialog Example]        (既存)
  [Notification Example]  (既存)
  [Clipboard Example]     (追加) "Test Win32 clipboard and WinRT history features"

ClipboardPage
  [<- Back]
  WindowsClipboardManager Example
  +----------------------------------------+
  | ResultTextBlock (最新 1 件 + 状態表示) |
  +----------------------------------------+
  +----------------------------------------+
  | LogTextBlock (ScrollViewer, 高さ固定)  |
  +----------------------------------------+
  (以下 ScrollViewer 内)
```

「実行」列は 3.5.1、「Pre」列は 3.5.2、「Busy」列は busy 中に押せるかを示す。

**Init / Lifecycle**

| ボタン | 呼び出し | 実行 | Pre | Busy |
|---|---|---|---|---|
| InitializeManager | `initClipboardManager(&OnClipboardChangedThunk, &err)` | UI | `Uninitialized` のみ通過 | 拒否 |
| SetHistoryCallbacks | `setClipboardHistoryCallbacks(thunk, thunk, thunk, &err)` | UI | ReadyRequired | 拒否 |
| Uninitialize | `uninitClipboardManager(&err)`。戻り値と `pError` の両方を表示し、3.6.2 に従って遷移 | UI | Ready / ShuttingDown | 拒否 |
| CanDestroy | `canDestroyClipboardManager(&err)` | UI | Ready / ShuttingDown | **許可** |

Uninitialize の表示方針:

- `TRUE` + `NONE`: `Uninitialize succeeded; temp cleanup pending` を表示 -> `Uninitialized` へ遷移。続けて cleanup worker を起動し、**完了時に `Temp cleanup succeeded` / `Temp cleanup failed (<n> files)` をログへ追記**する【L1】。cleanup の結果で主結果の表示を上書きしない
- `FALSE` + `CANCELED`(15): `Uninitialize pending: waiting for callbacks. Press CanDestroy, then Uninitialize again` -> `ShuttingDown`
- `FALSE` + `BUSY`(3): 同上 -> `ShuttingDown`
- `FALSE` + `MONITOR_REGISTER_FAILED`(12) / その他: エラーコードを表示 -> `ShuttingDown`
- **UI をブロックして待たない**。リトライはユーザーのボタン操作で行う

**Copy**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| CopyPlainText | `copyPlainText(L"Hello from native-toolkit", NONE, &err)` | Worker | ReadyRequired |
| CopyPlainText (empty) | 空文字列。仕様どおり成功することを確認 | Worker | ReadyRequired |
| CopyHtml | `copyHtml(L"<b>Hello</b> from native-toolkit", L"Hello from native-toolkit", NONE, &err)` | Worker | ReadyRequired |
| CopyFiles | 一時ファイル 2 件を生成して JSON 配列で渡す（生成も worker 内） | Worker | ReadyRequired |
| CopyImage | 生成した 8x8 32bpp DIB を渡す | Worker | ReadyRequired |
| CopyCustomFormat | `copyCustomFormat(L"NativeToolkitSample", blob, size, NONE, &err)` | Worker | ReadyRequired |
| CopyMultipleFormats | `HTML Format`(html) -> `CF_UNICODETEXT`(text) の順に 2 件 | Worker | ReadyRequired |
| CopyMultipleFormats (with image) | 上記 + `CF_DIB`(base64) の 3 件 | Worker | ReadyRequired |
| Cleanup Temp Files | 生成済みの一時ファイルを削除する。Bridge を呼ばない | Worker | AnyState |

**Write Options（F-11）**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| CopyPlainText (SENSITIVE) | `CLIPBOARD_WRITE_OPTION_SENSITIVE` | Worker | ReadyRequired |
| CopyPlainText (EXCLUDE_HISTORY) | `EXCLUDE_HISTORY` のみ | Worker | ReadyRequired |
| CopyPlainText (EXCLUDE_ROAMING) | `EXCLUDE_ROAMING` のみ | Worker | ReadyRequired |

**Paste**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| PastePlainText | 2 回呼び出しで取得し、先頭 100 文字を表示 | Worker | ReadyRequired |
| PasteHtml | 同上。CF_HTML fragment の先頭を表示 | Worker | ReadyRequired |
| PasteFiles | JSON 配列をそのまま表示 | Worker | ReadyRequired |
| PasteImage | 取得バイト数と、サイズ検証を通った場合のみ `BITMAPINFOHEADER` の width / height / bitCount を表示 | Worker | ReadyRequired |
| PasteCustomFormat | `NativeToolkitSample` のバイト数と先頭バイトを表示 | Worker | ReadyRequired |

**Inspect / Clear**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| HasFormat (CF_UNICODETEXT) | `hasClipboardFormat` | Worker | ReadyRequired |
| GetClipboardFormats | JSON 配列を表示 | Worker | ReadyRequired |
| GetPreferredFormat | 形式名を表示（空なら該当なし） | Worker | ReadyRequired |
| ClearClipboard | `clearClipboard` | Worker | ReadyRequired |

**Deferred Rendering（UI スレッド限定）**

| ボタン | 呼び出し | 実行 | Pre | Busy |
|---|---|---|---|---|
| ReserveDeferredFormats | `["HTML Format","CF_UNICODETEXT"]` を予約。payload は予約時に確定してストアへ保存 | UI | ReadyRequired | 拒否 |
| RecoverDeferredState | `recoverDeferredState` | UI | ReadyRequired | 拒否 |

ログに残す行:

- 予約直後: `[Reserve] OK formats=[...] (provider not called yet)`
- provider 1 相目: `[Provider] format=... phase=size required=<n>`
- provider 2 相目: `[Provider] format=... phase=fill size=<n> result=<code>`

**History（非同期 / F-12）**

| ボタン | 呼び出し | 実行 | Pre | Busy |
|---|---|---|---|---|
| GetHistoryAvailability | `getClipboardHistoryAvailability` | UI | ReadyRequired | 拒否 |
| GetClipboardHistory | `getClipboardHistory`。先頭項目の `id` を捕捉して保持 | UI | ReadyRequired | 拒否 |
| RestoreHistoryItem (last id) | 捕捉済み `id` を使う。未捕捉なら GetClipboardHistory を促す | UI | ReadyRequired | 拒否 |
| DeleteHistoryItem (last id) | 同上。成功時に捕捉済み `id` を破棄する | UI | ReadyRequired | 拒否 |
| ClearUnpinnedHistory | `clearUnpinnedHistory` | UI | ReadyRequired | 拒否 |
| CancelLastRequest | 直前に発行した `requestId` を `cancelClipboardRequest` | UI | ReadyRequired | 拒否 |
| **Request + Immediate Uninitialize**【v4 / M1】 | 同一ハンドラ内で `getClipboardHistory` の受付直後に `uninitClipboardManager` を呼ぶ | UI | ReadyRequired | 拒否 |

`Request + Immediate Uninitialize` の意図: `getClipboardHistory` は受付時に `WM_APP_CLIPBOARD_REQUEST` を post するだけで、実処理は次のメッセージポンプ周回で始まる。同一ハンドラ内で続けて `uninitClipboardManager` を呼べば、request がまだ Queued のまま `CloseAndDrain` に入るため、**`FALSE` + `CANCELED`(15) と drain 経路を決定的に再現できる**。ボタンを 2 回に分けると、クリック間にポンプが回って request が完了し、Uninit が最初から `TRUE` になり得る。

**Threading**

| ボタン | 呼び出し | 期待 | 実行 | Pre |
|---|---|---|---|---|
| ReserveDeferred (worker thread) | `reserveDeferredFormats` を worker から呼ぶ | `WRONG_THREAD`(14) | Worker | **ReadyRequired**【M2】 |
| Uninitialize (worker thread) | `uninitClipboardManager` を worker から呼ぶ。**状態は遷移させない** | `WRONG_THREAD`(14) | Worker | **ReadyRequired**【M2】 |
| **Delayed Worker Check**【v4 / M4】 | worker で 5 秒待機してから `hasClipboardFormat(CF_UNICODETEXT)` を呼ぶ（read-only で副作用なし） | 5 秒後に成功。その間 busy 系の挙動を確認できる | Worker | ReadyRequired |

**Error cases**

| ボタン | 期待 | Pre |
|---|---|---|
| CopyPlainText (null) | `INVALID_PARAMETER`(1) | ReadyRequired |
| PastePlainText (after Clear) | `FORMAT_UNAVAILABLE`(5) | ReadyRequired |
| PasteHtml (text only) | `FORMAT_UNAVAILABLE`(5) | ReadyRequired |
| PasteImage (size query only) | `BUFFER_TOO_SMALL`(7) と必要サイズ（1 回目だけを実行） | ReadyRequired |
| CopyMultipleFormats (CF_BITMAP) | `INVALID_PARAMETER`(1) | ReadyRequired |
| CopyMultipleFormats (duplicate format) | `INVALID_PARAMETER`(1) | ReadyRequired |
| CopyMultipleFormats (type mismatch: CF_DIB + text) | `INVALID_PARAMETER`(1) | ReadyRequired |
| CopyFiles (empty array) | `INVALID_PARAMETER`(1) | ReadyRequired |
| CopyPlainText (after Uninitialize) | `NOT_INITIALIZED`(2) | NoStateGuard |
| **Force Initialize while shutting down** | `initClipboardManager` が `NONE`（冪等成功）を返すが gate は再開せず、続く CopyPlainText が `NOT_INITIALIZED`(2) になる。**状態は `ShuttingDown` のまま** | **ShuttingDownRequired**【M3】 |
| CancelClipboardRequest (unknown id) | 戻り値 `FALSE` かつ `INVALID_PARAMETER`(1) | ReadyRequired |

`CLIPBOARD_ERROR_EMPTY`(4) は、format が available なのに `GetClipboardData` が null を返す状態でしか発生せず、サンプルから安定して再現できない。**手動確認ケースには含めない**。

### 5.2 各 API の呼び出し方針とコールバック処理

**worker 実行の同期 API**

ボタンハンドラ側:

```
（UI スレッド）
if (!CheckPrecondition(WorkerPrecondition::ReadyRequired)) return;   // 状態別の案内を表示

if (g_workerBusy.exchange(true)) { SetResultText(L"Busy: another clipboard operation is running"); return; }
std::shared_ptr<void> busyToken;
try
{
    busyToken = std::shared_ptr<void>(nullptr, [](void*) { g_workerBusy.store(false); });
    RunOnWorker(L"CopyPlainText",
                [text = std::wstring(L"Hello from native-toolkit"), options]() -> WorkerResult
                {
                    DWORD err = 0;
                    copyPlainText(text.c_str(), options, &err);
                    return MakeBridgeResult(L"CopyPlainText", err, L"");
                },
                busyToken);
}
catch (...)
{
    if (!busyToken) g_workerBusy.store(false);
    SetResultText(失敗マーカー + L"[CopyPlainText] Sample operation failed: could not start worker");
}
```

- `work` ラムダは値コピーした入力のみを捕捉する。`this` を捕捉しない
- 完了は 3.5.4 の経路を通り、`CompleteWorkerOperation` が結果表示・ログ追記を行う
- busy 解除は token の deleter が行う。ハンドラ内に `store(false)` を書くのは token 生成失敗時のみ

**UI 直呼び API のボタンハンドラ**

```
if (g_workerBusy.load()) { SetResultText(L"Busy: wait for the current clipboard operation"); return; }  // CanDestroy を除く
if (!CheckPrecondition(...)) return;
DWORD err = 0;
reserveDeferredFormats(json.c_str(), &ProviderThunk, nullptr, &err);
ShowResult(L"ReserveDeferredFormats", err);
```

**`CompleteWorkerOperation(WorkerResult const& r)`**（ページ public、UI スレッド）

```
if (r.sampleFailed)  SetResultText(失敗マーカー + L"[" + r.method + L"] Sample operation failed: " + r.detail);
else                 ShowResult(r.method, r.bridgeError, r.detail);
if (!r.logLine.empty()) AppendLog(r.logLine);
```

**`ShowResult(method, err, detail)` の `NOT_INITIALIZED` 分岐**【L2】

```
if (err == CLIPBOARD_ERROR_NOT_INITIALIZED)
{
    if (g_managerState.load() == ManagerState::ShuttingDown)
        -> "Shutting down. Press CanDestroy, then Uninitialize again."
    else
        -> "Not initialized. Press InitializeManager first."
}
```

**同期 API（バッファ 2 回呼び出し）**

`PasteToBuffer` ヘルパーで共通化する。`wchar_t` 系（`pastePlainText` / `pasteHtml` / `pasteFiles` / `getClipboardFormats` / `getPreferredClipboardFormat`）と `BYTE` 系（`pasteImage` / `pasteCustomFormat`）で 2 つ用意する。worker スレッド上で動く。

1 回目（size query、`buffer = nullptr` / `buffer_size = 0`）の判定:

- `err == CLIPBOARD_ERROR_BUFFER_TOO_SMALL` のときだけ size query 成功として扱う
- そのうち `needed == 0` は**空ペイロード**として、2 回目を呼ばずに成功（空）として返す
  - `WriteBytesToBuffer` は空データのとき `needed = 0` かつ `BUFFER_TOO_SMALL` を返すため、`needed > 0` を成功条件にすると正常系を誤判定する
- それ以外の `err`（`NONE` を含む）は想定外として、そのエラーコードで失敗を返す

2 回目（`needed` サイズを確保して実行）の判定:

- `err == CLIPBOARD_ERROR_NONE` であること
- 戻り値（実サイズ）が確保サイズ以下であること。超えていたらサンプル側の検証失敗（`sampleFailed`）として扱う
- `err == BUFFER_TOO_SMALL` が再度返った場合は失敗として返し、**無限リトライしない**

**PasteImage の構造体参照前チェック**

1. 返却サイズが `sizeof(BITMAPINFOHEADER)` 以上であること
2. 先頭の `biSize` を読み、`biSize >= sizeof(BITMAPINFOHEADER)` かつ `biSize <= 返却サイズ` であること

いずれかを満たさない場合はフィールドを参照せず、`sampleFailed` として `Invalid DIB header` を表示し、バイト数だけを出す。

**変更監視コールバック（F-09）**

- `ClipboardChangedCallback` は引数なし。free function thunk が無名 namespace の `g_clipboardChangedHandler` へ転送
- ページは `OnNavigatedTo` で `ResultTextBlock` / `LogTextBlock` の weak ref と `DispatcherQueue` を捕捉した lambda を登録し、`OnNavigatedFrom` で `nullptr` を代入して解除
- コールバックは所有 UI スレッドで来る契約だが、既存 Notification と同じく `TryEnqueue` 経由で反映する
  - 理由: コールバックは toolkit の `dispatchHwnd` の `WndProc` 処理中に呼ばれる。キューに載せて WndProc から抜けたあとに反映するほうが再入の心配がない

**履歴イベントコールバック（F-12）**

- `onHistoryChanged` は引数なし、`onHistoryEnabledChanged` / `onRoamingEnabledChanged` は `BOOL enabled`
- 3 つとも同じ forwarding hub 方式でログへ追記する

**request callback（F-12 非同期）**

- 署名は `(uint32_t requestId, DWORD error, const wchar_t* json)`
- **`json` はコールバック実行中のみ有効**。thunk の内部で即座に `winrt::hstring` へコピーし、コピー後の値を `TryEnqueue` に渡す
- ページは `m_pendingRequests`（`std::map<uint32_t, std::wstring>`）を持ち、コールバックで引いて表示に使い、引いたら消す
- `m_lastRequestId` を保持し、CancelLastRequest ボタンで使う
- 受付戻り値が 0 のときはコールバックが呼ばれないので、`m_pendingRequests` へ登録しない
- `m_pendingRequests` に無い requestId が来たら、ログへ `unknown request id` として出し、結果表示は変更しない
- `GetClipboardHistory` 成功時は JSON を `JsonArray::Parse` で読み、先頭項目の `id` を `m_lastHistoryItemId` に捕捉する（try/catch で囲む）
- Uninitialize によるキャンセルで来る `CANCELED`(15) も同じ経路でログへ出す。これが `ShuttingDown` から抜ける目安になる

**遅延 provider（F-10）**

- `ClipboardRenderCallback` は free function。無名 namespace に置く
- payload は**予約時に確定**して無名 namespace の静的マップ（`std::map<std::wstring, std::vector<BYTE>>`）へ格納する。provider は 2 相ともこのマップから同じサイズを返す
- provider 内では XAML を触らない。ログ行を無名 namespace のキューに積み、`TryEnqueue` で後から `LogTextBlock` へ反映する
- provider は `try { ... } catch (...) { return CLIPBOARD_ERROR_UNKNOWN; }` で囲み、throw を境界外へ出さない
- `buffer == nullptr` のとき `*pRequiredSize` を設定して `CLIPBOARD_ERROR_BUFFER_TOO_SMALL` を返す

### 5.3 サンプルデータの生成方針

| データ | 生成方針 |
|---|---|
| DIB | 8x8 / 32bpp / `BI_RGB` の `BITMAPINFOHEADER` + 8*8*4 バイトの単色ピクセル。コード内で組み立てる |
| ファイル一覧 | `%TEMP%` 配下に `native-toolkit-clipboard-sample-1.txt` / `-2.txt` を書き出し、その絶対パスを JSON 配列にする |
| 一時ファイルの後始末【L1】 | Cleanup Temp Files ボタン（`AnyState`）で削除する。加えて Uninitialize が `TRUE` を返した直後に cleanup worker を起動する。**cleanup は非同期に完了するため、Uninitialize の結果表示は `temp cleanup pending` とし、削除結果はログへ別行で追記する**。cleanup の成否で Uninitialize の主結果を上書きしない |
| 独自フォーマット | フォーマット名 `NativeToolkitSample`、payload は ASCII の短いバイト列 |
| base64 payload | 生成した DIB を base64 エンコードして埋め込む。エンコーダはサンプル側に小さな関数を持つ（`ClipboardFormats::Base64Decode` は decode 専用かつライブラリ内部 API のため） |
| 遅延 payload | `CF_UNICODETEXT` は NUL 終端 UTF-16 文字列、`HTML Format` は CF_HTML 形式で組み立てたもの |

### 5.4 入力バリデーション方針

- サンプルは固定値ボタン方式（入力欄なし）とし、既存 `NotificationPage` / `DialogPage` と揃える
- 例外は「捕捉済み ID を使うボタン」（RestoreHistoryItem / DeleteHistoryItem / CancelLastRequest）。未捕捉時は API を呼ばず、先に押すべきボタンを結果表示で促す
- precondition（3.5.2）と busy 判定（3.5.3）はボタンハンドラの先頭で行い、通らなければ API を呼ばない
- 数値・文字列の妥当性検証はライブラリ側の責務なので、サンプル側で先回りして弾かない（`errorCode` の確認が目的）
- ただし**呼び出し側の構造体参照条件**（PasteImage の `BITMAPINFOHEADER`、JSON parse、バッファサイズ）はサンプル側の責務として必ず確認し、失敗時は `sampleFailed` として Domain error と区別して表示する

### 5.5 ログ表示の実装方針

- `LogTextBlock` は `Border` + `ScrollViewer`（`Height="160"`, `VerticalScrollBarVisibility="Auto"`）内の `TextBlock`
- `AppendLog(line)`: `HH:MM:SS` + 内容を追記。保持行数の上限（200 行）を超えたら先頭から捨てる
- ページは行を `std::deque<std::wstring>` で保持し、更新時に連結して `Text` に設定する
- ログの追記は必ず UI スレッド上で行う（worker 経路・コールバック経路とも `TryEnqueue` を通し、`CompleteWorkerOperation` / hub lambda から `AppendLog` を呼ぶ）
- ログ内容も英語で書く

### 5.6 worker 実行と UI 反映のまとめ

| 項目 | 方針 |
|---|---|
| 実行基盤 | `winrt::Windows::System::ThreadPool::RunAsync` |
| 所有 | サンプル側でスレッドを所有しない。`join` / `get()` / `wait` を書かない。`IAsyncAction` も保持しない |
| runner の配置 | `ClipboardPage` の private member function。completion lambda を member スコープで構築する |
| 完了ハンドラ | `CompleteWorkerOperation` は implementation class の public member（IDL 非公開） |
| weak 参照 | `winrt::weak_ref<WindowsLibraryExample::ClipboardPage>`（`get_weak()`）。UI 継続で `get()` -> `winrt::get_self<implementation::ClipboardPage>()` |
| 状態 guard | `RunOnWorker` は持たない。`CheckPrecondition` が `ReadyRequired` / `AnyState` / `ShuttingDownRequired` / `NoStateGuard` を判定 |
| 直列化 | process-lifetime の `g_workerBusy`。busy 中は `CanDestroy` 以外のすべてのクリップボード操作を拒否する |
| busy 解除 | busy token（`shared_ptr` の deleter）が唯一の解除経路。例外・queue 失敗・ページ破棄・OOM を含む全経路を覆う |
| 入力の受け渡し | すべて値コピー。`this` を捕捉しない |
| 例外 | 失敗用 `WorkerResult` を try の前に構築し、catch 節では文字列リテラル代入のみ（OOM 時に再 allocation しない） |
| ページ破棄時 | worker は最後まで走り、busy は解除され、UI 反映のみ no-op になる |
| worker 内の禁止事項 | XAML の参照・更新。UI 限定 API の呼び出し（Threading 検証ボタンを除く） |

---

## 6. 手動確認観点

MSIX 配置（Visual Studio から F5）で実施する。

### 6.1 他アプリとの相互運用

| 観点 | 手順 | 期待 |
|---|---|---|
| プレーンテキスト | CopyPlainText -> メモ帳で Ctrl+V | 同一文字列 |
| HTML 互換性 | CopyHtml -> Word / ブラウザで Ctrl+V | 太字が保持される |
| HTML フォールバック | CopyHtml -> メモ帳で Ctrl+V | plainText 側が貼られる |
| CF_HDROP 双方向 | CopyFiles -> エクスプローラーで Ctrl+V / エクスプローラーでコピー -> PasteFiles | 双方向でパスが一致 |
| 画像 | CopyImage -> ペイントで Ctrl+V / ペイントでコピー -> PasteImage | 8x8 の単色画像 / 取得サイズが妥当 |
| 複数フォーマット | CopyMultipleFormats -> Word とメモ帳で Ctrl+V | 貼り付け先が対応する最良の形式を選ぶ |
| 優先度（text + HTML） | CopyMultipleFormats の直後に GetPreferredFormat | **`CF_UNICODETEXT`**。現行 `PickPreferredFormat` の優先順は `{ CF_UNICODETEXT, CF_HDROP, CF_DIB, CF_BITMAP }` で `HTML Format` を候補に含めないため |
| 優先度（files のみ） | CopyFiles の直後に GetPreferredFormat | `CF_HDROP` |
| 優先度（image のみ） | CopyImage の直後に GetPreferredFormat | `CF_DIB` |
| 優先度（custom のみ） | ClearClipboard -> CopyCustomFormat -> GetPreferredFormat | 候補に無いため該当なし（空） |

`copyMultipleFormats` の「情報量の多い順に配置する」（書き込み順の契約）と、`getPreferredClipboardFormat` の固定優先順（読み出し側の契約）は**別の契約**である。

### 6.2 変更監視（F-09）

| 観点 | 手順 | 期待 |
|---|---|---|
| 他アプリのコピーで通知 | InitializeManager -> メモ帳で任意の文字列をコピー | ログに変更通知が 1 行出る |
| 自書き込みでループしない | CopyPlainText を連続で押す | 自分の書き込みでは変更通知が出ない |
| 監視解除 | Uninitialize を `TRUE` まで完了 -> メモ帳でコピー | 通知が出ない |
| 管理者権限（UIPI） | サンプルを管理者として実行し、非管理者アプリでコピー | 通知が届くかを記録する（設計書のリスク項目） |

### 6.3 遅延レンダリング（F-10）

| 観点 | 手順 | 期待 |
|---|---|---|
| 貼り付け時に provider が呼ばれる | ReserveDeferredFormats -> ログに provider 行が無いことを確認 -> メモ帳で Ctrl+V | 貼り付けた時刻に provider の size / fill 行が出る。メモ帳に予約した内容が入る |
| 複数形式のレンダリング | 予約後に Word で Ctrl+V | 貼り付けが成功し、**要求された各形式について size / fill が正しい組で記録される**。どの形式が要求されるかは貼り付け先アプリの実装依存のため、環境依存の観察結果として記録する |
| 予約後の形式列挙 | 予約直後に GetClipboardFormats / HasFormat | 予約した形式が列挙される（`CloseClipboard` 前後の挙動を記録） |
| アプリ終了時の実体化 | 予約 -> 貼り付けずにアプリ終了 -> メモ帳で Ctrl+V | 内容が残っている（`WM_RENDERALLFORMATS`） |
| 予約の破棄 | 予約 -> 他アプリでコピー -> メモ帳で Ctrl+V | 他アプリの内容が貼られ、provider は呼ばれない |
| ワーカースレッドからの予約 | Ready 状態で ReserveDeferred (worker thread) | `WRONG_THREAD`(14) |
| PARTIAL_STATE | 発生条件を探し、発生したら RecoverDeferredState で回復するか記録する | 意図的な再現手段がないため観察のみ |

### 6.4 履歴（F-12 / F-11）

| 観点 | 手順 | 期待 |
|---|---|---|
| 可用性 | GetHistoryAvailability | `historyEnabled` / `roamingEnabled` が Windows 設定と一致 |
| 履歴無効時 | Windows 設定で履歴を切って GetClipboardHistory | `HISTORY_DISABLED`(10) |
| 取得 | いくつかコピーしてから GetClipboardHistory | 項目が新しい順に並び、`timestamp` が 10 進文字列 |
| `contentTypes` | 画像をコピーしてから GetClipboardHistory | `Bitmap` などの形式名が入る |
| 復元 | GetClipboardHistory -> RestoreHistoryItem -> PastePlainText | 復元した項目の内容 |
| フォアグラウンド要件 | RestoreHistoryItem 実行時に別アプリを前面にする | `NOT_FOREGROUND`(17) が返るか、実挙動を記録する |
| 削除 | DeleteHistoryItem -> GetClipboardHistory | 対象が消えている |
| 消去と pinned | Win+V で 1 件を固定 -> ClearUnpinnedHistory -> GetClipboardHistory | **固定した項目だけが残る** |
| 履歴イベント | SetHistoryCallbacks -> メモ帳でコピー | ログに履歴変更が出る |
| 設定変更イベント | SetHistoryCallbacks -> Windows 設定で履歴を切り替え | ログに enabled 変更が出て、値が設定と一致 |
| 履歴除外 | CopyPlainText (SENSITIVE) -> Win+V | 一覧に出ない |
| 同期除外 | CopyPlainText (EXCLUDE_ROAMING) -> 別デバイスの Win+V | 同期されない（サインイン環境がある場合のみ） |
| キャンセル | GetClipboardHistory -> 直後に CancelLastRequest | `CANCELED`(15) か、間に合わず成功のいずれか 1 回だけコールバックが来る |

### 6.5 ライフサイクル / スレッド / 状態管理（F-17）

| 観点 | 手順 | 期待 |
|---|---|---|
| 二重初期化 | InitializeManager を 2 回 | 2 回目は `Uninitialized` でないため API を呼ばず案内を表示する。状態は `Ready` のまま |
| 未初期化呼び出し | Uninitialize を `TRUE` まで完了 -> CopyPlainText (after Uninitialize) | `NOT_INITIALIZED`(2)。補足文言は「Initialize を押してください」【L2】 |
| 破棄可否 | Uninitialize が `TRUE` -> CanDestroy | `TRUE` |
| **pending 中の破棄（決定的）【M1】** | **Request + Immediate Uninitialize** を 1 回押す | `FALSE` + `CANCELED`(15)。状態表示が `Shutting down` になる。ボタンを 2 回に分けないため、drain 経路を確実に踏む |
| **`ShuttingDown` での操作拒否** | 上の状態で CopyPlainText を押す | API を呼ばず「Shutting down. Press CanDestroy, then Uninitialize again」を表示する |
| **`ShuttingDown` での Initialize 拒否** | 上の状態で InitializeManager を押す | API を呼ばず同じ案内を表示する。状態は `Shutting down` のまま |
| **`ShuttingDown` の `NOT_INITIALIZED` 文言【L2】** | Force Initialize while shutting down -> CopyPlainText (after Uninitialize) | `NOT_INITIALIZED`(2) の補足が「Initialize を押してください」ではなく「Uninitialize を再実行してください」になる |
| **pending 消化の確認** | ログに pending の `CANCELED`(15) コールバックが出るのを待つ -> CanDestroy | `TRUE` |
| **2 回目の Uninitialize** | CanDestroy が `TRUE` になってから Uninitialize | `TRUE` + `NONE` かつ `temp cleanup pending`。状態が `Uninitialized` になる。少し遅れて `Temp cleanup succeeded` がログに出る【L1】 |
| 再初期化 | 上の完了後に InitializeManager -> CopyPlainText | 再度動作する。状態が `Ready` になる |
| **gate 再開しないことの確認** | Request + Immediate Uninitialize で `ShuttingDown` を作る -> Force Initialize while shutting down | `initClipboardManager` は `NONE` を返すが、続く CopyPlainText は `NOT_INITIALIZED`(2)。**確認後は「pending 消化 -> CanDestroy -> Uninitialize が `TRUE` -> InitializeManager」で `Ready` へ復旧してから次のテストに進む** |
| 非所有スレッドからの Uninit | Ready 状態で Uninitialize (worker thread) | `WRONG_THREAD`(14)。**状態は `Ready` のまま**。続けて CopyPlainText が成功する |
| アパートメント | 通常起動で InitializeManager | `WRONG_APARTMENT`(18) にならない（要検証 7.1） |
| ページ離脱と再入場 | Initialize -> Back -> 再入場 -> CopyPlainText | 状態が `Ready` のまま保たれ、そのまま成功する。ログ表示だけは再入場でクリアされる |
| 離脱中の callback 破棄 | GetClipboardHistory -> 即 Back -> 再入場 | 再入場後のログに完了行が出ない。`m_lastHistoryItemId` が空なので RestoreHistoryItem は「GetClipboardHistory を先に押してください」を表示する |
| 離脱中 pending からの Uninitialize | GetClipboardHistory -> 即 Back -> 再入場 -> Uninitialize | `TRUE`（離脱中に pending が消化済み）または `FALSE` + `CANCELED`。いずれもクラッシュせず、unknown request id のログが出ても安全に無視される |
| UI 応答性 | 他アプリがクリップボードを掴んだ状態で Copy / Paste を連打 | UI が固まらない。実行中は Busy 表示になる |
| **busy 中の操作拒否（決定的）【H3, M4】** | **Delayed Worker Check** を押し、5 秒の待機中に CopyPlainText / ReserveDeferredFormats / GetClipboardHistory / Uninitialize を押す | いずれも API を呼ばず Busy 表示。**UI が固まらない**（特に Reserve で `selfWriteMutex_` 待ちが起きない） |
| **busy 中の CanDestroy 許可【H3】** | Delayed Worker Check の待機中に CanDestroy を押す | 実行され、結果が表示される |
| **busy のページ横断（決定的）【M1, M4】** | Delayed Worker Check を押し、待機中に Back -> 再入場 -> CopyPlainText | Busy 表示になる（ページを再生成しても直列化が維持される） |
| **busy の解除保証【H2】** | 上の手順で 5 秒待つ | Busy が解除され、次の操作ができる。ページ破棄中に完了した場合も再入場後に Busy が残らない |

### 6.6 パッケージ構成

| 観点 | 期待 |
|---|---|
| MSIX（本サンプル） | 全機能が動作する |
| 未パッケージ | **本サンプルでは確認できない**（`WindowsLibraryExample` は MSIX 前提）。設計書の「未パッケージでの履歴 API」は未確認のまま残る |

---

## 7. 要検証事項

| No | 事項 | 現状の見立て | 検証方法 |
|---|---|---|---|
| 7.1 | WinUI 3 の UI スレッドが `initClipboardManager` のアパートメント判定を通るか | 通る見込み。実装は `CoGetApartmentType` が `APTTYPE_STA` / `APTTYPE_MAINSTA` を返せば受理し、WinUI 3 の UI スレッドは application STA として `APTTYPE_STA` を返す | InitializeManager を押して `WRONG_APARTMENT`(18) にならないことを確認する。失敗した場合はサンプル側で回避せず、機能側の判定条件を再検討する |
| 7.2 | `dispatchHwnd`（非表示トップレベルウィンドウ）が WinUI 3 のウィンドウ管理と干渉しないか | 干渉しない見込み | 起動 -> Initialize -> タスクバー / Alt+Tab に余計なウィンドウが出ないことを確認する |
| 7.3 | 遅延 provider が `WM_RENDERFORMAT` 処理中に呼ばれる間、XAML 更新をキューに載せるだけで足りるか | 足りる見込み。`TryEnqueue` は即座に返る | Reserve -> 別アプリで貼り付け、ログが遅延なく出てハングしないことを確認する |
| 7.4 | `NOT_FOREGROUND`(17) が実際に返るか | 設計書は `GetForegroundWindow()` のプロセス ID 比較と定義。WinRT の実挙動が異なる可能性がある | 6.4 のフォアグラウンド要件で実測する。契約と異なる場合は仕様を勝手に変えず報告する |
| 7.5 | 履歴の `id` が復元 / 削除の両方で受理されるか | 受理される見込み | 6.4 の復元 / 削除で確認する |
| 7.6 | 予約中に `getClipboardFormats` を呼んだときの挙動 | 予約形式が列挙される見込み | 6.3 の「予約後の形式列挙」で実測して記録する |
| 7.7 | 既存 `NotificationPage` のマーカー記号が正しく表示されているか | `WindowsLibraryExample.vcxproj` は全構成で `/utf-8` 済みのため正しく表示される見込み | Notification 画面で確認する。文字化けしていた場合は本計画の範囲外の既存不具合として報告する |
| 7.8 | `ThreadPool::RunAsync` の worker から Win32 clipboard API を呼んで問題ないか | 問題ない見込み。Win32 clipboard API にアパートメント要件はなく、`AcquireSyncLease` も任意スレッド想定。`OpenClipboard(owner)` は他スレッドからでも有効 | 6.5 の「UI 応答性」と各 Copy / Paste で実測する |
| 7.9 | 1 回目の Uninitialize が `FALSE` のあと、pending の終端コールバックが実際に届くか | 届く見込み。`CloseAndDrain` が drain キューへ移して `WM_APP_CLIPBOARD_DRAIN` を投げ、UI ポンプで配送される | 6.5 の「pending 消化の確認」で `CANCELED`(15) がログに出ることを確認する |
| 7.10 | `ShuttingDown` から `Ready` へ戻す唯一の経路が「Uninitialize `TRUE` -> Initialize」で足りるか | 足りる見込み。`Uninit` が `TRUE` を返した時点で `initialized_ = false` になり、次の `Init` が `lifecycle_.Reopen()` を含めて全て再構築する | 6.5 の「再初期化」で確認する。`MONITOR_REGISTER_FAILED` で `ShuttingDown` に入った場合に復旧できるかは実測して記録する |
| 7.11【v4】 | `Request + Immediate Uninitialize` で必ず `FALSE` + `CANCELED` になるか | なる見込み。`getClipboardHistory` は `WM_APP_CLIPBOARD_REQUEST` を post するだけで、同一ハンドラ内では処理されない。したがって `CloseAndDrain` 時点で request は Queued のまま | 6.5 の「pending 中の破棄（決定的）」で確認する。`TRUE` が返る場合は前提が崩れているので、原因を記録して手順を再設計する |

v3 にあった「`get_self` で private メソッドを呼べるか」の要検証項目は、3.5.4 で設計として確定したため削除した。

---

## 8. 機能側へ報告する事項

サンプル側で吸収せず、機能側の判断が必要な事項。

| 事項 | 内容 | 現状の扱い |
|---|---|---|
| `getPreferredClipboardFormat` が `HTML Format` を候補に含まない | `PickPreferredFormat` の優先順は `{ CF_UNICODETEXT, CF_HDROP, CF_DIB, CF_BITMAP }` の固定 4 種。`copyMultipleFormats` で HTML + text を配置しても `CF_UNICODETEXT` が返る。設計書 F-07 の「認識できる最も情報量の多い形式を選ぶ」という意図に対し、HTML が候補外であることは要件と実装のずれになり得る | 本計画では**現行実装に合わせた期待値**を手動確認に記載する（6.1）。要件として HTML を含めるべきかは機能設計側で判断する |
| 初期化状態を照会する Bridge API が無い | サンプルは `g_managerState` を自前で持つ必要がある。特に「所有 UI スレッドから Uninit を呼んだ時点で gate が閉じる」ことは公開ヘッダから読み取れず、実装コードを読んで初めて分かる | 本計画ではサンプル側の 3 状態管理で対処する（3.6）。Unity など他の利用者も同じ状態管理を自前で実装する必要があるため、状態照会 API または `uninitClipboardManager` の Doxygen への gate 挙動明記を機能設計側で検討する余地がある |
| **書き込み系 API の相互排他が公開契約に無い**【v4】 | すべての Copy API と `reserveDeferredFormats` / `recoverDeferredState` は `ClipboardWatcher::SelfWriteTransaction` を通じて同一 mutex を操作全体にわたって保持する。任意スレッドから並行に呼ぶと、後発の呼び出しは最大でクリップボードのリトライ時間（約 100ms）待たされる。この直列化は公開ヘッダに記載がない | 本計画ではサンプル側の busy guard で全面直列化して回避する（3.5.3）。UI スレッドから UI 限定 API を呼ぶ利用者が worker からの書き込みと競合するとブロックし得るため、Doxygen への明記を機能設計側で検討する余地がある |

---

## 9. 実行確認

この実装計画で進めますか？

- 承認する: 計画を確定し、次のレビュー workflow（`review-document`）へ進む
- 修正する: 指摘内容を反映して計画ファイルを更新する
- キャンセル: 計画ファイルは保持したまま終了する
