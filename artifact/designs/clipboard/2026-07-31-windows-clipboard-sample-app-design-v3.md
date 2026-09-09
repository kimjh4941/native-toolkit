# Windows クリップボード サンプルアプリ 実装計画 v3

## 基本情報

- 日付: 2026-07-31
- 機能名: Windows Clipboard Manager
- 対象OS: Windows 11 以降
- 対象サンプルアプリ: `windows/WindowsLibraryExample`（WinUI 3 / C++/WinRT / MSIX パッケージ済み）
- 設計書: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- 実装結果: `artifact/results/clipboard/2026-07-30-windows-clipboard-implementation-feature-result-v4.md`
- 前版: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v2.md`
- 対応レビュー: `artifact/reviews/clipboard/2026-07-31-windows-clipboard-sample-app-design-review-v2.md`
- ブランチ: `feature/NTKIT-13`
- 対応タスク: 機能設計書 T-19（サンプルアプリ対応）

---

## 0. v2 からの変更点（レビュー v2 対応）

| 指摘 | 対応 | 反映箇所 |
|---|---|---|
| H1 boolean では shutdown 中を区別できない | process-lifetime 状態を `Uninitialized` / `Ready` / `ShuttingDown` の 3 状態にし、遷移条件を呼び出し経路とエラーコードで定義 | 3.6, 5.1, 5.2, 6.5 |
| H2 worker 完了処理が page member へ到達できない | ページの weak reference を completion に渡し、`CompleteWorkerOperation` へ集約。busy 解除はページ生存に依存しない process-lifetime state へ移動 | 3.5, 5.2, 5.6 |
| M1 page-local `m_busy` ではページ再入場をまたげない | busy state を process-lifetime（`g_workerBusy`）へ移動。guard 対象を worker 実行 API のみと明記 | 3.5, 5.6 |
| M2 worker 内例外時の完了配送 / busy 解除 | worker delegate 全体を try/catch で囲み、単一出口の `WorkerResult` に集約。sample 由来エラーは Domain error と区別 | 3.5, 5.2, 5.6 |
| M3 task runner の precondition | `RunOnWorker` は状態 guard を持たず、呼び出し側が precondition を明示的に渡す形へ変更 | 3.5, 5.2 |
| M4 ページ離脱中の callback の扱い | 「UI では破棄し、再入場後に復元しない」を仕様として確定。手動確認を追加 | 3.7, 6.5 |
| L1 pending 中の誤 Initialize の復旧手順 | `ShuttingDown` では Initialize を拒否する仕様にし、挙動確認は専用 error case として分離。復旧手順を手動確認へ追加 | 5.1, 6.5 |
| L2 一時ファイル削除結果の分離 | 主結果と後処理結果を分けて表示する方針を明記 | 5.1, 5.3 |

### 0.1 レビュー指摘の検証結果

反映前に、指摘対象を実装コードで確認した。

| 指摘 | 確認内容 | 結果 |
|---|---|---|
| H1 | `ClipboardHistoryCoordinator::CloseAndDrain` は `table_` が空でも `lifecycle_.CloseAndReserveDrainWork(0)` を無条件に呼ぶ。`ClipboardManager::Uninit` は `WRONG_THREAD` 判定を `CloseAndDrain` より**前**に行う | **owner UI スレッドから Uninit を呼んだ時点で、戻り値に関わらず lifecycle gate は閉じる**。非所有スレッドからの `WRONG_THREAD` では閉じない。指摘は妥当で、遷移条件を厳密に定義できる |
| H1（続き） | `AcquireSyncLease` は `lifecycle_.TryEnter()` 失敗時に `CLIPBOARD_ERROR_NOT_INITIALIZED` を設定する | gate が閉じた後の同期 API はすべて `NOT_INITIALIZED`(2) になる。boolean guard では通してしまう。指摘は妥当 |
| H2 | v2 の疑似コードが捕捉するのは `weakResult` / `weakLog` / `err` のみ | `m_busy`・`AppendLog`・`ShowResult` に到達できない。指摘は妥当 |
| M2 | Bridge は `SafeBridgeCall` で例外を Domain error に変換するが、サンプル側の DIB / base64 / JSON / `std::vector` / ファイル生成は worker delegate 内で throw し得る | `RunAsync` の `IAsyncAction` を保持しないため観測できない。指摘は妥当 |

### 0.2 レビュー案から選択・変更した箇所

**M1: busy state の置き場所（レビューは 2 案を提示）**

process-lifetime の共有状態（`g_workerBusy`）を採用する。理由は 2 つ。

- 「クリップボード操作は 1 度に 1 つ」という方針をページ再生成に依存せず保てる
- H2 の busy 解除がページ生存に依存しなくなる。ページメンバのままだと、worker 実行中にページが破棄された場合に busy が解除されないまま残る経路ができる

**M4: pending callback の扱い（レビューは 2 案を提示）**

「ページ離脱中の callback は UI では破棄し、再入場後に復元しない」を採用する。request table を process-lifetime へ移すと、UI に紐づかない完了結果を保持する仕組みがサンプルに増え、確認対象（Bridge の挙動）から離れるため。破棄仕様であることを手動確認で明示的に踏む。

---

## 1. 前提情報の抽出（設計書 / 実装結果由来）

### 1.1 in-scope 機能

サンプルアプリで確認対象とするのは、Bridge から呼べる F-01〜F-12 の全サブ機能。

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
- 同期 API（所有 UI スレッド限定）: `reserveDeferredFormats` / `recoverDeferredState`。他スレッドからは `CLIPBOARD_ERROR_WRONG_THREAD`
- 非同期 API（受付 + request callback）: `getClipboardHistory` / `restoreHistoryItem` / `deleteHistoryItem` / `clearUnpinnedHistory` / `getClipboardHistoryAvailability` / `cancelClipboardRequest`
- ライフサイクル: `initClipboardManager` / `setClipboardHistoryCallbacks` / `uninitClipboardManager` / `canDestroyClipboardManager`

入力制約（サンプル側が守る必要があるもの）:

- `initClipboardManager` の呼び出しスレッドが所有 UI スレッドとして採用される。そのスレッドは STA 済みかつメッセージポンプを回し続けている必要がある
- `uninitClipboardManager` は所有 UI スレッドからのみ成功する。他スレッドからは `WRONG_THREAD`
- **`uninitClipboardManager` は pending がある間 `FALSE` + `CLIPBOARD_ERROR_CANCELED` を返し、teardown は完了しない。** メッセージポンプを回して pending の終端コールバックを消化したあと、再度呼んで `TRUE` を得る必要がある
- **所有 UI スレッドから `uninitClipboardManager` を呼んだ時点で、戻り値に関わらず lifecycle gate は閉じる。** それ以降の同期 API はすべて `NOT_INITIALIZED`(2) を返し、`initClipboardManager` を呼んでも gate は再開しない（冪等成功を返すのみ）
- バッファ規約: `buffer = nullptr` または不足時に必要サイズが戻り値で返り `pError = CLIPBOARD_ERROR_BUFFER_TOO_SMALL`。呼び出し側は 2 回呼ぶ
- `copyFiles` の `pathsJson` は JSON 配列文字列。空配列 / 空パスは不可
- `copyImage` は DIB バイト列。エンコード / デコードは呼び出し側の責務
- `copyMultipleFormats` の `itemsJson` は `[{"format":"...","text|html|base64":"..."}]`。情報量の多い順に配置する
  - `CF_UNICODETEXT` / `CF_TEXT` は `text`、`HTML Format` は `html`、`CF_DIB` / `CF_HDROP` は `base64`、custom は `base64` のみ
  - `CF_BITMAP` は HBITMAP 所有経路がないため拒否される
  - 同一 format の重複、payload 種別の不一致は `CLIPBOARD_ERROR_INVALID_PARAMETER`
- write option は全コピー API 共通のフラグ（`NONE` / `EXCLUDE_HISTORY` / `EXCLUDE_ROAMING` / `SENSITIVE`）
- 遅延 provider は二相呼び出し。**1 回目の必要サイズと 2 回目の実サイズは完全一致が必須**（実装結果 v4 の H4）。provider 内で clipboard API を呼ばない / ブロックしない / throw しない
- request callback の `json` は**コールバック実行中のみ有効**。復帰前にコピーする。失敗時 `json` は必ず `nullptr`
- 受付成功（戻り値が非 0）から終端コールバックまで、関数ポインタを有効に保つのは呼び出し側の責務

### 1.3 エラー契約

`CLIPBOARD_ERROR_NONE`(0) 〜 `CLIPBOARD_ERROR_UNKNOWN`(19) の 20 定数。サンプルでは数値コードをそのまま表示し、既存 `NotificationPage` と同じく特定コードにだけ補足文言を付ける。

| コード | 定数 | サンプルでの補足文言方針 |
|---|---|---|
| 2 | `NOT_INITIALIZED` | Initialize を先に押すよう促す |
| 4 | `EMPTY` | クリップボードが空であることを明示 |
| 5 | `FORMAT_UNAVAILABLE` | 対象形式が現在のクリップボードに無いことを明示 |
| 10 | `HISTORY_DISABLED` | Windows 設定でクリップボード履歴を有効化するよう促す |
| 13 | `PARTIAL_STATE` | Recover Deferred State を押すよう促す |
| 14 | `WRONG_THREAD` | 所有 UI スレッド限定 API であることを明示 |
| 15 | `CANCELED` | Uninitialize の場合は pending 消化後に再実行するよう促す |
| 17 | `NOT_FOREGROUND` | アプリを前面にしてから再実行するよう促す |
| 18 | `WRONG_APARTMENT` | 初期化スレッドが STA でないことを明示 |

その他のコードは `errorCode=<n>` の数値表示のみ。

**サンプル由来のエラーは Domain error と区別する**【M2】。`errorCode=<n>` は必ず Bridge が返した値だけに使い、サンプル側の例外・検証失敗は `Sample operation failed: <reason>` の形で別区分として表示する。

### 1.4 テスト観点（設計書由来）

設計書「統合テスト（実機・実クリップボード）」「手動確認項目」がサンプルアプリの確認対象。第 6 章の手動確認観点に展開する。

### 1.5 不足前提（本計画で追加判断が必要だった点）

- WinUI 3 の UI スレッドを所有 UI スレッドとして採用してよいか（アパートメント判定を通るか）
- 遅延 provider 内から XAML を触ってよいか
- 同期 Bridge を逃がす worker の所有方法と完了配送方法（v2 で追加、v3 で確定）
- ページ再生成をまたぐ初期化状態と busy 状態の保持方法（v2 で追加、v3 で 3 状態化）
- ページ離脱中に完了した履歴 callback の扱い（v3 で確定）
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

- workflow の相互参照ペアは Windows ⇔ macOS だが、**macOS 側にクリップボードのサンプル画面が存在しない**。そのため画面構成（Back + タイトル + 結果表示 + カテゴリ別ボタン群）は Windows 自身の既存 `NotificationPage` を正本とする
- 機能カテゴリの切り方（Copy / Sensitive / Read / Clear / Observe / Error cases）のみ Android の `ClipboardSampleScreen.kt` を参照し、Windows 固有機能（遅延レンダリング / 複数フォーマット / 履歴 / スレッド）を追加する

### 2.3 再利用する既存コンポーネント

- `MainMenuPage` のメニューカードと `NavigateTo`
- `NotificationPage` の画面骨格: `Grid` 2 行（固定ヘッダ + `ScrollViewer`）、`Width="600"` 中央寄せ、Back ボタン、タイトル `FontSize="28"`、`Border` + `ResultTextBlock`
- `NotificationButtonStyle`（`App.xaml` の既存スタイル）。**Clipboard 用の新スタイルは追加しない**
- `EnsureInitialized` / `ShowResult(method, err)` / `SetResultText(text)` の 3 ヘルパー構成
- C コールバックの forwarding hub パターン（無名 namespace の `std::function` + free function thunk + `winrt::make_weak` + `DispatcherQueue().TryEnqueue`）
- `DLog` / `DFLog`（`common.h`）

### 2.4 追加するコンポーネント

| 追加物 | 種別 | 理由 |
|---|---|---|
| ログ表示領域（`LogTextBlock` + `ScrollViewer`） | ページ | F-09 / F-10 / F-12 は「1 行の結果表示」では時系列が見えない |
| `AppendLog(line)` | ページ | タイムスタンプ付きで追記し、上限行数で古い行を捨てる |
| `CompleteWorkerOperation(WorkerResult)`【v3 / H2】 | ページ | worker 完了時の busy 反映・結果表示・ログ追記を 1 箇所に集約する |
| `RunOnWorker(precondition, method, work)`【v3 / M3】 | 無名 namespace | 同期 Bridge を worker で実行する task runner。状態 guard は持たない |
| `g_managerState`（3 状態）【v3 / H1】 | 無名 namespace | ページ再生成をまたいで manager の利用可否を判定する |
| `g_workerBusy`（`std::atomic<bool>`）【v3 / M1】 | 無名 namespace | クリップボード操作の直列化をページ寿命に依存させない |
| `WorkerResult` 構造体【v3 / M2】 | 無名 namespace | 成功 / Bridge error / sample 例外を単一の完了ペイロードへ正規化する |
| `PasteToBuffer` ヘルパー（2 回呼び出し） | 無名 namespace | 5 つの paste API がすべてバッファ 2 回呼び出し規約のため |
| 遅延 provider の payload ストア（無名 namespace の静的マップ） | 無名 namespace | provider の `context` はページ寿命と独立に有効でなければならない |
| サンプルデータ生成ヘルパー（DIB / 一時ファイル / base64 エンコード） | 無名 namespace | `copyImage` / `copyFiles` / `copyMultipleFormats` の入力を作るため |

### 2.5 変更するファイルと変更理由

| ファイル | 区分 | 理由 |
|---|---|---|
| `windows/WindowsLibraryExample/ClipboardPage.xaml` | 新規 | クリップボードサンプル画面の XAML |
| `windows/WindowsLibraryExample/ClipboardPage.xaml.h` | 新規 | ページ実装クラス宣言 |
| `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp` | 新規 | ページ実装 |
| `windows/WindowsLibraryExample/ClipboardPage.idl` | 新規 | `runtimeclass` 宣言（既存ページと同形式） |
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
- 成功 / 失敗が一目で分かる結果文言（既存 `NotificationPage` と同じマーカー記号。`WindowsLibraryExample.vcxproj` は全構成で `/utf-8` 済みのためソースに直接書いてよい）
- 実行前チェックの helper 化
- 公開 API 呼び出しの前後にログを残す（`DLog` / `DFLog`）
- C コールバック -> forwarding hub -> `DispatcherQueue().TryEnqueue` で UI 反映
- 既存の project / solution 構成は変更しない
- **全 UI 文言を英語で書く**。`windows.md`「コメントと言語ポリシー」はログだけでなく UI テキスト・statusText・ダイアログ文言も英語と定めている

### 3.2 共通実装パターン: 拡張する点

| 拡張 | 内容 | 理由 |
|---|---|---|
| 結果表示 + ログ表示の 2 段構成 | ヘッダに `ResultTextBlock`（最新 1 件）を残し、その下に固定高さ + `ScrollViewer` の `LogTextBlock` を追加 | 変更監視 / provider 呼び出し / request callback の時系列が確認対象そのもの |
| 同期 Bridge の worker 実行 | 任意スレッド対応の同期 API と同期 I/O は worker で実行し、結果を `TryEnqueue` で UI へ返す | `ClipboardScope` は `OpenClipboard` を 10 回 + `Sleep(10)` でリトライするため、最大約 100ms UI が止まる |
| process-lifetime の状態管理【v3】 | manager 状態（3 状態）と worker busy をページ外に持つ | ページ再生成をまたいで一貫した判定と直列化を行うため |
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
- 既存 `NotificationPage` と同じく、アプリ起動時（`App.xaml.cpp`）では初期化しない
- `OnNavigatedFrom` で `uninitClipboardManager` は呼ばない。forwarding hub のみ解除する

### 3.5 同期 Bridge の実行スレッドと task runner【v3 / H2, M1, M2, M3】

#### 3.5.1 実行スレッドの分類

**UI スレッドから直接呼ぶ API**（即座に戻る。所有 UI スレッド要件があるか、受付のみを行う）

- `initClipboardManager` / `setClipboardHistoryCallbacks` / `uninitClipboardManager`（所有 UI スレッド限定）
- `reserveDeferredFormats` / `recoverDeferredState`（所有 UI スレッド限定）
- `getClipboardHistory` / `restoreHistoryItem` / `deleteHistoryItem` / `clearUnpinnedHistory` / `getClipboardHistoryAvailability` / `cancelClipboardRequest`（受付のみで即時復帰）
- `canDestroyClipboardManager`（状態照会のみ）

**worker で実行する API**（クリップボードを開くため最大約 100ms ブロックし得る、または同期 I/O を伴う）

- `copyPlainText` / `copyHtml` / `copyFiles` / `copyImage` / `copyCustomFormat` / `copyMultipleFormats`
- `pastePlainText` / `pasteHtml` / `pasteFiles` / `pasteImage` / `pasteCustomFormat`
- `hasClipboardFormat` / `getClipboardFormats` / `getPreferredClipboardFormat` / `clearClipboard`
- 一時ファイルの生成・削除

#### 3.5.2 task runner の契約【M3】

`RunOnWorker` は**状態 guard を持たない**。precondition の判定は呼び出し側（ボタンハンドラ）が行い、runner には「実行すると決まった作業」だけを渡す。

precondition の種別:

| 種別 | 意味 | 適用ボタン |
|---|---|---|
| `ReadyRequired` | `g_managerState == Ready` のときだけ実行。それ以外は API を呼ばず理由を表示 | 通常の Copy / Paste / Inspect / Clear |
| `AnyState` | manager 状態に関わらず実行 | Cleanup Temp Files（ファイル操作のみで Bridge を呼ばない） |
| `NoStateGuard` | 状態 guard を意図的に外し、Bridge のエラーを実際に受け取る | Error cases の `CopyPlainText (after Uninitialize)`、Threading の worker 版 Uninitialize |

#### 3.5.3 直列化（busy）【M1】

- busy state は process-lifetime の `std::atomic<bool> g_workerBusy` とする。ページメンバにしない
  - ページ再入場をまたいでも「クリップボード操作は 1 度に 1 つ」を保てる
  - busy 解除がページ生存に依存しない（ページ破棄中に worker が終わっても解除される）
- **guard の対象は worker 実行 API のみ**。UI スレッド直呼びの API（Init / Uninit / CanDestroy / 遅延レンダリング / 履歴受付）は busy 中でも押せる
  - 理由: 6.5 の「pending 中の破棄」など、worker 実行中に Uninitialize を押す確認手順が必要なため
- busy 中に worker ボタンを押した場合は API を呼ばず `Busy: another clipboard operation is running` を表示する

#### 3.5.4 完了配送と単一出口【H2, M2】

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

worker delegate の構造:

```
ThreadPool::RunAsync([weakPage, dq, method, work](auto&&)
{
    WorkerResult result{ method, false, CLIPBOARD_ERROR_NONE, L"", L"" };
    try
    {
        result = work();                        // Bridge 呼び出しとペイロード構築
    }
    catch (const std::bad_alloc&)
    {
        result = MakeSampleFailure(method, L"Out of memory in sample code");
    }
    catch (const winrt::hresult_error& e)
    {
        result = MakeSampleFailure(method, L"WinRT error in sample code");
    }
    catch (...)
    {
        result = MakeSampleFailure(method, L"Unexpected sample-side failure");
    }

    // 単一出口: ここを必ず通る
    const bool queued = dq.TryEnqueue([weakPage, result]()
    {
        g_workerBusy.store(false);
        if (auto page = weakPage.get())
        {
            winrt::get_self<implementation::ClipboardPage>(page)->CompleteWorkerOperation(result);
        }
    });
    if (!queued)
    {
        // ページ終了中などで UI へ戻せない。UI 更新は破棄してよいが、
        // busy はここで必ず解除する
        g_workerBusy.store(false);
    }
});
```

要点:

- **worker delegate 全体を try/catch で囲む**。Bridge の失敗（`bridgeError`）とサンプル側の例外（`sampleFailed`）を同じ `WorkerResult` に正規化する【M2】
- **完了の enqueue と busy 解除は単一出口**。`TryEnqueue` が `false` の場合は UI 更新を破棄し、busy をその場で解除する【M2】
- worker は `winrt::weak_ref<WindowsLibraryExample::ClipboardPage>`（`get_weak()` で取得）を捕捉し、UI 継続で `weakPage.get()` が有効なときだけ `CompleteWorkerOperation` を呼ぶ【H2】
  - v2 の「worker へページ参照を一切渡さない」は**「strong reference / raw `this` を渡さない。weak reference のみ許可」に修正する**。weak reference はページ寿命を延長しないため安全性は保たれる
- `CompleteWorkerOperation` に結果表示（`ShowResult` / `SetResultText`）と `AppendLog` を集約する。TextBlock を直接更新しない（200 行上限のログ設計と一致させるため）【H2】
- `RunAsync` の戻り値（`IAsyncAction`）は保持しない。例外は delegate 内で処理済みのため、観測できないまま失われる経路が無くなる
- worker 内では XAML を一切触らない

### 3.6 manager 状態の管理【v3 / H1】

#### 3.6.1 状態定義

```
enum class ManagerState { Uninitialized, Ready, ShuttingDown };
std::atomic<ManagerState> g_managerState{ ManagerState::Uninitialized };
```

| 状態 | 意味 | 許可する操作 |
|---|---|---|
| `Uninitialized` | Init 前、または Uninit が `TRUE` で完了 | InitializeManager のみ（他は理由を表示して API を呼ばない） |
| `Ready` | Init 成功後で、lifecycle gate が開いている | 全操作 |
| `ShuttingDown` | 所有 UI スレッドの Uninit が `FALSE` を返し、gate が閉じている | CanDestroy / Uninitialize の再試行のみ。**InitializeManager と新規操作は拒否する** |

#### 3.6.2 遷移条件

実装コードの確認結果（0.1 参照）に基づき、**呼び出し経路とエラーコード**で遷移させる。単に `FALSE` かどうかでは判定しない。

| 契機 | 条件 | 遷移先 |
|---|---|---|
| `initClipboardManager` | `pError == CLIPBOARD_ERROR_NONE`、かつ遷移前が `Uninitialized` | `Ready` |
| `initClipboardManager` | `pError != NONE` | 変化なし |
| `uninitClipboardManager`（UI スレッド、UI ボタン） | 戻り値 `TRUE` | `Uninitialized` |
| `uninitClipboardManager`（UI スレッド、UI ボタン） | 戻り値 `FALSE`（`CANCELED` / `BUSY` / `MONITOR_REGISTER_FAILED` / その他） | `ShuttingDown` |
| `uninitClipboardManager`（worker、Threading 検証ボタン） | 戻り値 `FALSE` かつ `pError == WRONG_THREAD`(14) | **変化なし**。`CloseAndDrain` に到達しないため gate は閉じていない |

`ShuttingDown` では `initClipboardManager` を押しても Bridge は冪等成功を返すが gate は再開しない。そのためサンプル側で **Initialize を拒否し**、「CanDestroy が TRUE になってから Uninitialize を再実行してください」と表示する【L1】。この挙動そのものを確認したい場合は、Error cases の専用ボタンから行う。

#### 3.6.3 状態の表示

- `OnNavigatedTo` で現在の状態を結果表示へ反映する。表示は `Uninitialized` / `Ready` / `Shutting down` の 3 値とし、二値表示にしない
- `EnsureReady()`（旧 `EnsureInitialized`）は `g_managerState == Ready` を判定する。`Uninitialized` と `ShuttingDown` で異なる案内文を出す
- ログ行はページメンバなので再入場でクリアされる。これは仕様として手動確認手順に明記する

### 3.7 ページ離脱中のコールバックの扱い【v3 / M4】

- **仕様として確定**: ページ離脱中に届いた callback（変更監視・履歴イベント・request 完了）は UI では破棄し、再入場後に復元しない
- 根拠: forwarding hub は `OnNavigatedFrom` で `nullptr` になり、`m_pendingRequests` / `m_lastRequestId` / `m_lastHistoryItemId` はページメンバのため再生成で失われる
- Bridge 側の安全性には影響しない。thunk は常に有効な free function で、hub が null なら何もしない
- 再入場後に届いた「未知の requestId」の callback は、`m_pendingRequests` に無いものとしてログへ `unknown request id` として出し、結果表示は変更しない
- 再入場後は `m_lastHistoryItemId` が空になるため、RestoreHistoryItem / DeleteHistoryItem は「GetClipboardHistory を先に押してください」を表示する
- 6.5 に「pending 中の Back -> 再入場 -> Uninitialize」の確認手順を追加し、この破棄仕様を実際に踏む

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

- `windows/WindowsLibrary` 配下すべて（機能側は実装済み。M2 の `HTML Format` 優先順は第 8 章の報告事項として扱い、本計画では変更しない）
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

「実行」列は 3.5.1 の分類、「Pre」列は 3.5.2 の precondition を示す。

**Init / Lifecycle**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| InitializeManager | `initClipboardManager(&OnClipboardChangedThunk, &err)`。`ShuttingDown` では API を呼ばず案内を表示【L1】 | UI | 状態別 |
| SetHistoryCallbacks | `setClipboardHistoryCallbacks(thunk, thunk, thunk, &err)` | UI | Ready |
| Uninitialize | `uninitClipboardManager(&err)`。**戻り値と `pError` の両方を表示**し、3.6.2 に従って状態遷移 | UI | Ready / ShuttingDown |
| CanDestroy | `canDestroyClipboardManager(&err)`。戻り値を表示 | UI | Ready / ShuttingDown |

Uninitialize の表示方針:

- `TRUE` + `NONE`: `Uninitialize succeeded` -> `Uninitialized` へ遷移。一時ファイル削除も実行し、**主結果と分けて表示**する【L2】
  - 例: `Uninitialize succeeded; temp cleanup failed (2 files)` のように後処理結果を後段に付ける。削除失敗で主結果を失敗表示にしない
- `FALSE` + `CANCELED`(15): `Uninitialize pending: waiting for callbacks. Press CanDestroy, then Uninitialize again` -> `ShuttingDown`
- `FALSE` + `BUSY`(3): 同上（in-flight あり）-> `ShuttingDown`
- `FALSE` + `MONITOR_REGISTER_FAILED`(12) / その他: エラーコードを表示 -> `ShuttingDown`
- **UI をブロックして待たない**。リトライはユーザーのボタン操作で行う

**Copy**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| CopyPlainText | `copyPlainText(L"Hello from native-toolkit", NONE, &err)` | Worker | Ready |
| CopyPlainText (empty) | 空文字列。仕様どおり成功することを確認 | Worker | Ready |
| CopyHtml | `copyHtml(L"<b>Hello</b> from native-toolkit", L"Hello from native-toolkit", NONE, &err)` | Worker | Ready |
| CopyFiles | 一時ファイル 2 件を生成して JSON 配列で渡す（生成も worker 内） | Worker | Ready |
| CopyImage | 生成した 8x8 32bpp DIB を渡す | Worker | Ready |
| CopyCustomFormat | `copyCustomFormat(L"NativeToolkitSample", blob, size, NONE, &err)` | Worker | Ready |
| CopyMultipleFormats | `HTML Format`(html) -> `CF_UNICODETEXT`(text) の順に 2 件 | Worker | Ready |
| CopyMultipleFormats (with image) | 上記 + `CF_DIB`(base64) の 3 件 | Worker | Ready |
| Cleanup Temp Files | 生成済みの一時ファイルを削除する。Bridge を呼ばない | Worker | AnyState |

**Write Options（F-11）**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| CopyPlainText (SENSITIVE) | `CLIPBOARD_WRITE_OPTION_SENSITIVE` | Worker | Ready |
| CopyPlainText (EXCLUDE_HISTORY) | `EXCLUDE_HISTORY` のみ | Worker | Ready |
| CopyPlainText (EXCLUDE_ROAMING) | `EXCLUDE_ROAMING` のみ | Worker | Ready |

**Paste**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| PastePlainText | 2 回呼び出しで取得し、先頭 100 文字を表示 | Worker | Ready |
| PasteHtml | 同上。CF_HTML fragment の先頭を表示 | Worker | Ready |
| PasteFiles | JSON 配列をそのまま表示 | Worker | Ready |
| PasteImage | 取得バイト数と、サイズ検証を通った場合のみ `BITMAPINFOHEADER` の width / height / bitCount を表示 | Worker | Ready |
| PasteCustomFormat | `NativeToolkitSample` のバイト数と先頭バイトを表示 | Worker | Ready |

**Inspect / Clear**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| HasFormat (CF_UNICODETEXT) | `hasClipboardFormat` | Worker | Ready |
| GetClipboardFormats | JSON 配列を表示 | Worker | Ready |
| GetPreferredFormat | 形式名を表示（空なら該当なし） | Worker | Ready |
| ClearClipboard | `clearClipboard` | Worker | Ready |

**Deferred Rendering（UI スレッド限定）**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| ReserveDeferredFormats | `["HTML Format","CF_UNICODETEXT"]` を予約。payload は予約時に確定してストアへ保存 | UI | Ready |
| RecoverDeferredState | `recoverDeferredState` | UI | Ready |

ログに残す行:

- 予約直後: `[Reserve] OK formats=[...] (provider not called yet)`
- provider 1 相目: `[Provider] format=... phase=size required=<n>`
- provider 2 相目: `[Provider] format=... phase=fill size=<n> result=<code>`

**History（非同期 / F-12）**

| ボタン | 呼び出し | 実行 | Pre |
|---|---|---|---|
| GetHistoryAvailability | `getClipboardHistoryAvailability` | UI | Ready |
| GetClipboardHistory | `getClipboardHistory`。先頭項目の `id` を捕捉して保持 | UI | Ready |
| RestoreHistoryItem (last id) | 捕捉済み `id` を使う。未捕捉なら GetClipboardHistory を促す | UI | Ready |
| DeleteHistoryItem (last id) | 同上。成功時に捕捉済み `id` を破棄する | UI | Ready |
| ClearUnpinnedHistory | `clearUnpinnedHistory` | UI | Ready |
| CancelLastRequest | 直前に発行した `requestId` を `cancelClipboardRequest` | UI | Ready |

**Threading**

| ボタン | 呼び出し | 期待 | 実行 | Pre |
|---|---|---|---|---|
| ReserveDeferred (worker thread) | `reserveDeferredFormats` を worker から呼ぶ | `WRONG_THREAD`(14) | Worker | NoStateGuard |
| Uninitialize (worker thread) | `uninitClipboardManager` を worker から呼ぶ。**状態は遷移させない**（3.6.2） | `WRONG_THREAD`(14) | Worker | NoStateGuard |

**Error cases**

| ボタン | 期待 | Pre |
|---|---|---|
| CopyPlainText (null) | `INVALID_PARAMETER`(1) | Ready |
| PastePlainText (after Clear) | `FORMAT_UNAVAILABLE`(5) | Ready |
| PasteHtml (text only) | `FORMAT_UNAVAILABLE`(5) | Ready |
| PasteImage (size query only) | `BUFFER_TOO_SMALL`(7) と必要サイズ（1 回目だけを実行） | Ready |
| CopyMultipleFormats (CF_BITMAP) | `INVALID_PARAMETER`(1) | Ready |
| CopyMultipleFormats (duplicate format) | `INVALID_PARAMETER`(1) | Ready |
| CopyMultipleFormats (type mismatch: CF_DIB + text) | `INVALID_PARAMETER`(1) | Ready |
| CopyFiles (empty array) | `INVALID_PARAMETER`(1) | Ready |
| CopyPlainText (after Uninitialize) | `NOT_INITIALIZED`(2) | NoStateGuard |
| **Force Initialize while shutting down**【L1】 | `initClipboardManager` が `NONE`（冪等成功）を返すが gate は再開せず、続く CopyPlainText が `NOT_INITIALIZED`(2) になる | NoStateGuard |
| CancelClipboardRequest (unknown id) | 戻り値 `FALSE` かつ `INVALID_PARAMETER`(1) | Ready |

`CLIPBOARD_ERROR_EMPTY`(4) は、format が available なのに `GetClipboardData` が null を返す状態でしか発生せず、サンプルから安定して再現できない。**手動確認ケースには含めない**。

### 5.2 各 API の呼び出し方針とコールバック処理

**worker 実行の同期 API**（3.5 の task runner を使う）

ボタンハンドラ側:

```
（UI スレッド）
if (!CheckPrecondition(WorkerPrecondition::ReadyRequired)) return;   // 状態別の案内を表示
if (g_workerBusy.exchange(true)) { SetResultText(L"Busy: another clipboard operation is running"); return; }

RunOnWorker(get_weak(), DispatcherQueue(), L"CopyPlainText",
            [text = std::wstring(L"Hello from native-toolkit"), options]() -> WorkerResult
            {
                DWORD err = 0;
                copyPlainText(text.c_str(), options, &err);
                return MakeBridgeResult(L"CopyPlainText", err, L"");
            });
```

- `work` ラムダは値コピーした入力のみを捕捉する。`this` を捕捉しない
- ページの weak reference と `DispatcherQueue` は runner に渡す
- 完了は 3.5.4 の単一出口を通り、`CompleteWorkerOperation` が結果表示・ログ追記・（ページ生存時の）UI 反映を行う
- `g_workerBusy` の解除は UI 継続の先頭で無条件に行う。ページ生存に依存しない

**`CompleteWorkerOperation(WorkerResult const& r)`**（ページメソッド、UI スレッド）

```
if (r.sampleFailed)  SetResultText(失敗マーカー + L"[" + r.method + L"] Sample operation failed: " + r.detail);
else                 ShowResult(r.method, r.bridgeError, r.detail);
if (!r.logLine.empty()) AppendLog(r.logLine);
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

`pasteImage` の返却バッファを `BITMAPINFOHEADER` として読む前に、サンプル側で次を確認する。

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
- `m_pendingRequests` に無い requestId が来たら、ログへ `unknown request id`（ページ離脱中に発行されたもの）として出し、結果表示は変更しない【M4】
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
| 一時ファイルの後始末【L1, L2】 | Cleanup Temp Files ボタン（`AnyState`）で削除する。加えて Uninitialize が `TRUE` を返したときにも削除する。**削除結果は主結果と分けて表示**し、削除失敗で Uninitialize の成功表示を上書きしない。削除失敗の詳細はログへ出す |
| 独自フォーマット | フォーマット名 `NativeToolkitSample`、payload は ASCII の短いバイト列 |
| base64 payload | 生成した DIB を base64 エンコードして埋め込む。エンコーダはサンプル側に小さな関数を持つ（`ClipboardFormats::Base64Decode` は decode 専用かつライブラリ内部 API のため） |
| 遅延 payload | `CF_UNICODETEXT` は NUL 終端 UTF-16 文字列、`HTML Format` は CF_HTML 形式で組み立てたもの |

### 5.4 入力バリデーション方針

- サンプルは固定値ボタン方式（入力欄なし）とし、既存 `NotificationPage` / `DialogPage` と揃える
- 例外は「捕捉済み ID を使うボタン」（RestoreHistoryItem / DeleteHistoryItem / CancelLastRequest）。未捕捉時は API を呼ばず、先に押すべきボタンを結果表示で促す
- precondition（3.5.2）に従い、`ReadyRequired` のボタンは `g_managerState != Ready` のとき API を呼ばずに状態別の案内を表示する
- 数値・文字列の妥当性検証はライブラリ側の責務なので、サンプル側で先回りして弾かない（`errorCode` の確認が目的）
- ただし**呼び出し側の構造体参照条件**（PasteImage の `BITMAPINFOHEADER`、JSON parse、バッファサイズ）はサンプル側の責務として必ず確認し、失敗時は `sampleFailed` として Domain error と区別して表示する

### 5.5 ログ表示の実装方針

- `LogTextBlock` は `Border` + `ScrollViewer`（`Height="160"`, `VerticalScrollBarVisibility="Auto"`）内の `TextBlock`
- `AppendLog(line)`: `HH:MM:SS` + 内容を追記。保持行数の上限（200 行）を超えたら先頭から捨てる
- ページは行を `std::deque<std::wstring>` で保持し、更新時に連結して `Text` に設定する
- ログの追記は必ず UI スレッド上で行う（worker 経路・コールバック経路とも `TryEnqueue` を通し、`CompleteWorkerOperation` / hub lambda から `AppendLog` を呼ぶ）
- ログ内容も英語で書く

### 5.6 worker 実行と UI 反映のまとめ【v3】

| 項目 | 方針 |
|---|---|
| 実行基盤 | `winrt::Windows::System::ThreadPool::RunAsync` |
| 所有 | サンプル側でスレッドを所有しない。`join` / `get()` / `wait` を書かない。`IAsyncAction` も保持しない |
| 状態 guard | `RunOnWorker` は持たない。ボタンハンドラが `ReadyRequired` / `AnyState` / `NoStateGuard` を選ぶ【M3】 |
| 直列化 | process-lifetime の `g_workerBusy`。**worker 実行 API のみ**が対象で、UI 直呼び API は busy 中でも実行できる【M1】 |
| 入力の受け渡し | すべて値コピー。`this` を捕捉しない |
| ページ参照 | `get_weak()` の weak reference のみ渡す。strong reference / raw `this` は渡さない【H2】 |
| 例外 | delegate 全体を try/catch。`std::bad_alloc` / `winrt::hresult_error` / その他を `sampleFailed` として正規化【M2】 |
| 完了配送 | `DispatcherQueue().TryEnqueue` -> busy 解除 -> ページ生存時のみ `CompleteWorkerOperation`【H2】 |
| 単一出口 | 成功・Bridge error・sample 例外・`TryEnqueue` 失敗のすべてで busy が解除される【M2】 |
| ページ破棄時 | worker は最後まで走り、busy は解除され、UI 反映のみ no-op になる |
| worker 内の禁止事項 | XAML の参照・更新、`reserveDeferredFormats` / `recoverDeferredState` の呼び出し（Threading 検証ボタンを除く） |

---

## 6. 手動確認観点

設計書「統合テスト（実機・実クリップボード）」「手動確認項目」に対応する。MSIX 配置（Visual Studio から F5）で実施する。

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
| ワーカースレッドからの予約 | ReserveDeferred (worker thread) | `WRONG_THREAD`(14) |
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
| 二重初期化 | InitializeManager を 2 回 | 2 回目も成功（冪等）。状態は `Ready` のまま |
| 未初期化呼び出し | Uninitialize を `TRUE` まで完了 -> CopyPlainText (after Uninitialize) | `NOT_INITIALIZED`(2) |
| 破棄可否 | Uninitialize が `TRUE` -> CanDestroy | `TRUE` |
| **pending 中の破棄【H2 v1】** | GetClipboardHistory -> 即 Uninitialize | 1 回目は `FALSE` + `CANCELED`(15)。状態表示が `Shutting down` になる |
| **`ShuttingDown` での操作拒否【H1】** | 上の状態で CopyPlainText を押す | API を呼ばず「Shutting down. Press CanDestroy, then Uninitialize again」を表示する |
| **`ShuttingDown` での Initialize 拒否【L1】** | 上の状態で InitializeManager を押す | API を呼ばず同じ案内を表示する。状態は `Shutting down` のまま |
| **pending 消化の確認** | ログに pending の `CANCELED`(15) コールバックが出るのを待つ -> CanDestroy | `TRUE` |
| **2 回目の Uninitialize** | CanDestroy が `TRUE` になってから Uninitialize | `TRUE` + `NONE`。状態が `Uninitialized` になる。一時ファイル削除結果が主結果と分けて表示される |
| 再初期化 | 上の完了後に InitializeManager -> CopyPlainText | 再度動作する。状態が `Ready` になる |
| **gate 再開しないことの確認【L1】** | Error cases の Force Initialize while shutting down を押す | `initClipboardManager` は `NONE` を返すが、続く CopyPlainText は `NOT_INITIALIZED`(2)。**確認後は「pending 消化 -> CanDestroy -> Uninitialize が `TRUE` -> InitializeManager」で `Ready` へ復旧してから次のテストに進む** |
| 非所有スレッドからの Uninit【H1】 | Uninitialize (worker thread) | `WRONG_THREAD`(14)。**状態は `Ready` のまま変わらない**。続けて CopyPlainText が成功する |
| アパートメント | 通常起動で InitializeManager | `WRONG_APARTMENT`(18) にならない（要検証 7.1） |
| ページ離脱と再入場【H3 v1】 | Initialize -> Back -> 再入場 -> CopyPlainText | 状態が `Ready` のまま保たれ、そのまま成功する。ログ表示だけは再入場でクリアされる |
| **離脱中の callback 破棄【M4】** | GetClipboardHistory -> 即 Back -> 再入場 | 再入場後のログに完了行が出ない（離脱中に配送され破棄された）。`m_lastHistoryItemId` が空なので RestoreHistoryItem は「GetClipboardHistory を先に押してください」を表示する |
| **離脱中 pending からの Uninitialize【M4】** | GetClipboardHistory -> 即 Back -> 再入場 -> Uninitialize | `TRUE`（離脱中に pending が消化済み）または `FALSE` + `CANCELED`。いずれもクラッシュせず、unknown request id のログが出ても安全に無視される |
| UI 応答性【H1 v1】 | 他アプリがクリップボードを掴んだ状態で Copy / Paste を連打 | UI が固まらない。実行中は Busy 表示になる |
| **busy のページ横断【M1】** | 時間のかかる Copy を実行中に Back -> 再入場 -> Copy を押す | 前の worker が終わるまで Busy 表示になる（ページを再生成しても直列化が維持される） |
| **busy の解除保証【M2】** | 上の手順で worker 完了を待つ | Busy が解除され、次の操作ができる。ページ破棄中に完了した場合も再入場後に Busy が残らない |

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
| 7.10【v3】 | `winrt::get_self<implementation::ClipboardPage>(weakPage.get())` で private メソッドを呼べるか | 呼べる見込み。C++/WinRT の標準的な実装型アクセス手段で、`ClipboardPage.g.h` が friend 関係を提供する | 実装時のコンパイルで確認する。不可なら `CompleteWorkerOperation` を public にするか、ページ内の `std::function` へ差し替える |
| 7.11【v3】 | `ShuttingDown` から `Ready` へ戻す唯一の経路が「Uninitialize `TRUE` -> Initialize」で足りるか | 足りる見込み。`Uninit` が `TRUE` を返した時点で `initialized_ = false` になり、次の `Init` が `lifecycle_.Reopen()` を含めて全て再構築する | 6.5 の「再初期化」で確認する。`MONITOR_REGISTER_FAILED` で `ShuttingDown` に入った場合に復旧できるかは実測して記録する |

---

## 8. 機能側へ報告する事項

サンプル側で吸収せず、機能側の判断が必要な事項。

| 事項 | 内容 | 現状の扱い |
|---|---|---|
| `getPreferredClipboardFormat` が `HTML Format` を候補に含まない | `PickPreferredFormat` の優先順は `{ CF_UNICODETEXT, CF_HDROP, CF_DIB, CF_BITMAP }` の固定 4 種。`copyMultipleFormats` で HTML + text を配置しても `CF_UNICODETEXT` が返る。設計書 F-07 の「認識できる最も情報量の多い形式を選ぶ」という意図に対し、HTML が候補外であることは要件と実装のずれになり得る | 本計画では**現行実装に合わせた期待値**を手動確認に記載する（6.1）。サンプル側で補正しない。要件として HTML を含めるべきかは機能設計側で判断する |
| 初期化状態を照会する Bridge API が無い【v3】 | サンプルは `g_managerState` を自前で持つ必要がある。特に「所有 UI スレッドから Uninit を呼んだ時点で gate が閉じる」ことは公開ヘッダから読み取れず、実装コードを読んで初めて分かる | 本計画ではサンプル側の 3 状態管理で対処する（3.6）。Unity など他の利用者も同じ状態管理を自前で実装する必要があるため、`getClipboardManagerState` 相当の照会 API、または `uninitClipboardManager` の Doxygen への gate 挙動明記を機能設計側で検討する余地がある |

---

## 9. 実行確認

この実装計画で進めますか？

- 承認する: 計画を確定し、次のレビュー workflow（`review-document`）へ進む
- 修正する: 指摘内容を反映して計画ファイルを更新する
- キャンセル: 計画ファイルは保持したまま終了する
