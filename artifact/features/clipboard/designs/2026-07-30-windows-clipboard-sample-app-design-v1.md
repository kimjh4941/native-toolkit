# Windows クリップボード サンプルアプリ 実装計画 v1

## 基本情報

- 日付: 2026-07-30
- 機能名: Windows Clipboard Manager
- 対象OS: Windows 11 以降
- 対象サンプルアプリ: `windows/WindowsLibraryExample`（WinUI 3 / C++/WinRT / MSIX パッケージ済み）
- 設計書: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- 実装結果: `artifact/results/clipboard/2026-07-30-windows-clipboard-implementation-feature-result-v4.md`
- ブランチ: `feature/NTKIT-13`
- 対応タスク: 機能設計書 T-19（サンプルアプリ対応）

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

サンプルで補足文言を付けるコード:

| コード | 定数 | サンプルでの補足文言方針 |
|---|---|---|
| 2 | `NOT_INITIALIZED` | Initialize を先に押すよう促す |
| 4 | `EMPTY` | クリップボードが空であることを明示 |
| 5 | `FORMAT_UNAVAILABLE` | 対象形式が現在のクリップボードに無いことを明示 |
| 10 | `HISTORY_DISABLED` | Windows 設定でクリップボード履歴を有効化するよう促す |
| 13 | `PARTIAL_STATE` | Recover Deferred State を押すよう促す |
| 14 | `WRONG_THREAD` | 所有 UI スレッド限定 API であることを明示 |
| 17 | `NOT_FOREGROUND` | アプリを前面にしてから再実行するよう促す |
| 18 | `WRONG_APARTMENT` | 初期化スレッドが STA でないことを明示 |

その他のコードは `errorCode=<n>` の数値表示のみ（設計書の「文字列化は呼び出し側が行う」に従い、全 20 種の日本語化は行わない。ログメッセージは英語）。

### 1.4 テスト観点（設計書由来）

設計書「統合テスト（実機・実クリップボード）」「手動確認項目」がサンプルアプリの確認対象。第 6 章の手動確認観点に展開する。

### 1.5 不足前提（本計画で追加判断が必要だった点）

以下は設計書・実装結果に記載がなく、本計画で決めた事項。断定できないものは第 7 章に要検証として残す。

- WinUI 3 の UI スレッドを所有 UI スレッドとして採用してよいか（アパートメント判定を通るか）
- 遅延 provider 内から XAML を触ってよいか
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

- `MainMenuPage` のメニューカード（`Button` + `StackPanel` + 2 行 `TextBlock`）と `NavigateTo`
- `NotificationPage` の画面骨格: `Grid` 2 行（固定ヘッダ + `ScrollViewer`）、`Width="600"` 中央寄せ、Back ボタン、タイトル `FontSize="28"`、`Border` + `ResultTextBlock`
- `NotificationButtonStyle`（`App.xaml` の既存スタイル）をそのまま使う。**Clipboard 用の新スタイルは追加しない**（既存 2 スタイルが同一内容で、3 つ目を増やす価値がない）
- `EnsureInitialized` / `ShowResult(method, err)` / `SetResultText(text)` の 3 ヘルパー構成
- C コールバックの forwarding hub パターン（無名 namespace の `std::function` + free function thunk + `winrt::make_weak` + `DispatcherQueue().TryEnqueue`）
- `DLog` / `DFLog`（`common.h`）

### 2.4 追加するコンポーネント

| 追加物 | 理由 |
|---|---|
| ログ表示領域（`LogTextBlock` + `ScrollViewer`） | F-09 変更監視・F-10 provider 呼び出し・F-12 request callback は「1 行の結果表示」では時系列が見えない。既存パターンの**拡張** |
| `AppendLog(line)` ヘルパー | タイムスタンプ付きで追記し、上限行数で古い行を捨てる |
| `PasteToBuffer` ヘルパー（2 回呼び出し） | 5 つの paste API すべてがバッファ 2 回呼び出し規約のため、重複を避ける |
| 遅延 provider の payload ストア（無名 namespace の静的マップ） | provider の `context` はページ寿命と独立に有効でなければならない |
| サンプルデータ生成ヘルパー（DIB / 一時ファイル / base64 エンコード） | `copyImage` / `copyFiles` / `copyMultipleFormats` の入力を作るため |

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
| `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj` | 既存変更 | `Page` / `Midl` / `ClCompile` / `ClInclude` へ 4 エントリ追加（既存ページと同じ `DependentUpon` 付き） |

---

## 3. 実装方針

### 3.1 共通実装パターン: 維持する点

- メインメニュー -> サンプル画面の導線（`Frame().Navigate` / Back は `Frame().GoBack()`）
- 画面先頭にタイトルと結果表示領域
- 機能カテゴリ単位のボタン群（`TextBlock` のセクション見出し + `NotificationButtonStyle` のボタン）
- 成功 / 失敗が一目で分かる結果文言（既存 `NotificationPage` と同じ成功 / 失敗マーカー記号を使う。`WindowsLibraryExample.vcxproj` は全構成で `/utf-8` 済みのため、ソースに直接書いてよい）
- 実行前チェックの helper 化（`EnsureInitialized`）
- 公開 API 呼び出しの前後にログを残す（`DLog` / `DFLog`）
- C コールバック -> forwarding hub -> `DispatcherQueue().TryEnqueue` で UI 反映
- 既存の project / solution 構成は変更しない（`ProjectReference` / include パス / `/utf-8` 設定は既存のまま）

### 3.2 共通実装パターン: 拡張する点

| 拡張 | 内容 | 理由 |
|---|---|---|
| 結果表示 + ログ表示の 2 段構成 | ヘッダに `ResultTextBlock`（最新 1 件）を残し、その下に固定高さ + `ScrollViewer` の `LogTextBlock` を追加 | 変更監視 / provider 呼び出し / request callback の時系列が確認対象そのものであるため |
| コールバック内での UI 更新の抑制 | 遅延 provider の中では XAML を触らず、ログ行を組み立てて `TryEnqueue` で後から反映する | provider は `WM_RENDERFORMAT` 処理中に呼ばれ、ブロック禁止・clipboard API 呼び出し禁止の契約があるため |
| ワーカースレッドからの呼び出しボタン | 同期 API が任意スレッドで動くこと、遅延レンダリング API が UI スレッド限定であることを対比して見せる | 設計書のスレッド契約が本機能の主要な設計判断であるため |
| エラーケース専用セクション | Android の `ClipboardSampleScreen` と同じく、意図的に失敗させるボタンを分離 | `errorCode` の正規化（F-14）を確認対象にするため |

### 3.3 呼び出し境界

- サンプルは `WindowsLibrary` の C Bridge（`WindowsClipboardManager.h`）のみを直接呼ぶ。`WindowsClipboardManagerInternal.h` などの内部ヘッダは参照しない
- Unity プラグイン（`windows/UnityWindowsPlugin`）へは依存しない
- 依存方向チェックの結果: **クリップボード機能に、Unity プラグイン経由でしか呼べない API は存在しない**。Bridge 27 関数すべてが `WindowsLibrary.def` からエクスポートされており、サンプルから到達可能。機能側の設計不備は検出されなかった
- `WINDOWSLIBRARY_EXPORTS` はサンプル側で未定義のため `__declspec(dllimport)` になり、`ProjectReference` 経由の import ライブラリでリンクされる（既存 Notification / Dialog と同じ）

### 3.4 所有 UI スレッドの扱い

- `initClipboardManager` は `ClipboardPage` の Initialize ボタンハンドラから呼ぶ。XAML のイベントハンドラは必ず WinUI の UI スレッドで走るため、そのスレッドが所有 UI スレッドになる
- WinUI 3 の UI スレッドはメッセージポンプを回し続けるため、`WM_CLIPBOARDUPDATE` / `WM_RENDERFORMAT` / `WM_APP_*` の配送要件を満たす
- 既存 `NotificationPage` と同じく、アプリ起動時（`App.xaml.cpp`）では初期化しない。ボタンによる明示初期化とする
- ページから離れる（`OnNavigatedFrom`）ときに `uninitClipboardManager` は呼ばない。forwarding hub のみ解除する
  - 理由: 遅延予約や履歴 pending が生きたまま manager を落とすと、確認したい挙動（別アプリでの貼り付け）が壊れる。破棄は Uninitialize ボタンで明示的に行う

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

- `windows/WindowsLibrary` 配下すべて（機能側は実装済み。サンプル都合で公開 API を変更しない）
- `windows/UnityWindowsPlugin`（`windows.md` の方針どおり触らない）
- `windows/WindowsLibraryExample/App.xaml`（既存 `NotificationButtonStyle` を再利用するためスタイル追加なし）
- `windows/WindowsLibraryExample/App.xaml.cpp` / `MainWindow.xaml*`（起動時初期化を行わないため変更不要）
- `windows/WindowsLibraryExample/Package.appxmanifest`（クリップボード API に追加の capability は不要）
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj.filters`（既存ページもルート直下に置かれており、`windows.md` の Filter ルールは `WindowsLibrary` 対象）
- `windows/WindowsLibraryExample/WindowsLibraryExample.sln`（プロジェクト追加なし）

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
  | ResultTextBlock (最新 1 件)            |
  +----------------------------------------+
  +----------------------------------------+
  | LogTextBlock (ScrollViewer, 高さ固定)  |
  |  10:23:05 [Reserve] OK                 |
  |  10:23:19 [Provider] phase=size ...    |
  +----------------------------------------+
  (以下 ScrollViewer 内)
```

セクションとボタン:

**Init / Lifecycle**

| ボタン | 呼び出し |
|---|---|
| InitializeManager | `initClipboardManager(&OnClipboardChangedThunk, &err)` |
| SetHistoryCallbacks | `setClipboardHistoryCallbacks(thunk, thunk, thunk, &err)` |
| Uninitialize | `uninitClipboardManager(&err)` |
| CanDestroy | `canDestroyClipboardManager(&err)` |

**Copy**

| ボタン | 呼び出し |
|---|---|
| CopyPlainText | `copyPlainText(L"Hello from native-toolkit", NONE, &err)` |
| CopyPlainText (empty) | 空文字列。仕様どおり成功することを確認 |
| CopyHtml | `copyHtml(L"<b>Hello</b> from native-toolkit", L"Hello from native-toolkit", NONE, &err)` |
| CopyFiles | 一時ファイル 2 件を生成して JSON 配列で渡す |
| CopyImage | 生成した 8x8 32bpp DIB を渡す |
| CopyCustomFormat | `copyCustomFormat(L"NativeToolkitSample", blob, size, NONE, &err)` |
| CopyMultipleFormats | `HTML Format`(html) -> `CF_UNICODETEXT`(text) の順に 2 件 |
| CopyMultipleFormats (with image) | 上記 + `CF_DIB`(base64) の 3 件 |

**Write Options（F-11）**

| ボタン | 呼び出し |
|---|---|
| CopyPlainText (SENSITIVE) | `CLIPBOARD_WRITE_OPTION_SENSITIVE`。Win+V に残らないことを手動確認 |
| CopyPlainText (EXCLUDE_HISTORY) | `EXCLUDE_HISTORY` のみ |
| CopyPlainText (EXCLUDE_ROAMING) | `EXCLUDE_ROAMING` のみ |

**Paste**

| ボタン | 呼び出し |
|---|---|
| PastePlainText | 2 回呼び出しで取得し、先頭 100 文字を表示 |
| PasteHtml | 同上。CF_HTML fragment の先頭を表示 |
| PasteFiles | JSON 配列をそのまま表示 |
| PasteImage | 取得バイト数と `BITMAPINFOHEADER` の width / height / bitCount を表示 |
| PasteCustomFormat | `NativeToolkitSample` のバイト数と先頭バイトを表示 |

**Inspect / Clear**

| ボタン | 呼び出し |
|---|---|
| HasFormat (CF_UNICODETEXT) | `hasClipboardFormat` |
| GetClipboardFormats | JSON 配列を表示 |
| GetPreferredFormat | 形式名を表示（空なら該当なし） |
| ClearClipboard | `clearClipboard` |

**Deferred Rendering（UI スレッド限定）**

| ボタン | 呼び出し |
|---|---|
| ReserveDeferredFormats | `["HTML Format","CF_UNICODETEXT"]` を予約。payload は予約時に確定してストアへ保存 |
| RecoverDeferredState | `recoverDeferredState` |

ログに残す行:

- 予約直後: `[Reserve] OK formats=[...] (provider not called yet)`
- provider 1 相目: `[Provider] format=... phase=size required=<n>`
- provider 2 相目: `[Provider] format=... phase=fill size=<n> result=<code>`
- `WM_DESTROYCLIPBOARD` 相当（他アプリのコピーで予約が破棄された場合）は `onChanged` ログから間接的に確認する

**History（非同期 / F-12）**

| ボタン | 呼び出し |
|---|---|
| GetHistoryAvailability | `getClipboardHistoryAvailability` |
| GetClipboardHistory | `getClipboardHistory`。先頭項目の `id` を捕捉して保持 |
| RestoreHistoryItem (last id) | 捕捉済み `id` を使う。未捕捉なら GetClipboardHistory を促す |
| DeleteHistoryItem (last id) | 同上。成功時に捕捉済み `id` を破棄する |
| ClearUnpinnedHistory | `clearUnpinnedHistory` |
| CancelLastRequest | 直前に発行した `requestId` を `cancelClipboardRequest` |

**Threading**

| ボタン | 呼び出し |
|---|---|
| CopyPlainText (worker thread) | `std::thread` から `copyPlainText`。成功する（任意スレッド可）ことを確認 |
| ReserveDeferred (worker thread) | `std::thread` から `reserveDeferredFormats`。`WRONG_THREAD`(14) になることを確認 |

**Error cases**

| ボタン | 期待コード |
|---|---|
| CopyPlainText (null) | `INVALID_PARAMETER`(1) |
| PastePlainText (after Clear) | `EMPTY`(4) |
| PasteHtml (text only) | `FORMAT_UNAVAILABLE`(5) |
| PasteImage (buffer too small, 1 回目のみ) | `BUFFER_TOO_SMALL`(7) と必要サイズ |
| CopyMultipleFormats (CF_BITMAP) | `INVALID_PARAMETER`(1) |
| CopyMultipleFormats (duplicate format) | `INVALID_PARAMETER`(1) |
| CopyMultipleFormats (type mismatch: CF_DIB + text) | `INVALID_PARAMETER`(1) |
| CopyFiles (empty array) | `INVALID_PARAMETER`(1) |
| CopyPlainText (after Uninitialize) | `NOT_INITIALIZED`(2) |
| CancelClipboardRequest (unknown id) | 戻り値 `FALSE` |

### 5.2 各 API の呼び出し方針とコールバック処理

**同期 API（void 系）**

```
DWORD err = 0;
copyPlainText(text, options, &err);
ShowResult(L"CopyPlainText", err);
```

**同期 API（バッファ 2 回呼び出し）**

`PasteToBuffer` ヘルパーで共通化する。

- 1 回目: `buffer = nullptr`, `buffer_size = 0` で必要サイズを取得
- 戻り値 0 かつ `err != 0` なら失敗として返す
- 必要サイズで `std::vector` を確保して 2 回目を呼ぶ
- 2 回目も `BUFFER_TOO_SMALL` なら（他アプリの書き込みでサイズが増えた場合）失敗として返し、無限リトライしない

`wchar_t` 系（`pastePlainText` / `pasteHtml` / `pasteFiles` / `getClipboardFormats` / `getPreferredClipboardFormat`）と `BYTE` 系（`pasteImage` / `pasteCustomFormat`）でヘルパーを 2 つ用意する。

**変更監視コールバック（F-09）**

- `ClipboardChangedCallback` は引数なし。free function thunk が無名 namespace の `g_clipboardChangedHandler` へ転送
- ページは `OnNavigatedTo` で `ResultTextBlock` / `LogTextBlock` の weak ref と `DispatcherQueue` を捕捉した lambda を登録し、`OnNavigatedFrom` で `nullptr` を代入して解除
- コールバックは所有 UI スレッド（= WinUI の UI スレッド）で来る契約だが、既存 Notification と同じく `TryEnqueue` 経由で反映する
  - 理由: コールバックは toolkit の `dispatchHwnd` の `WndProc` 処理中に呼ばれる。その場で XAML を触るより、キューに載せて WndProc から抜けたあとに反映するほうが再入の心配がない

**履歴イベントコールバック（F-12）**

- `onHistoryChanged` は引数なし、`onHistoryEnabledChanged` / `onRoamingEnabledChanged` は `BOOL enabled`
- 3 つとも同じ forwarding hub 方式でログへ追記する

**request callback（F-12 非同期）**

- 署名は `(uint32_t requestId, DWORD error, const wchar_t* json)`
- **`json` はコールバック実行中のみ有効**。thunk の内部で即座に `winrt::hstring` へコピーし、コピー後の値を `TryEnqueue` に渡す
- ページは `m_pendingRequests`（`std::map<uint32_t, std::wstring>`: requestId -> ボタン名）を持ち、コールバックで引いて表示に使い、引いたら消す
- `m_lastRequestId` を保持し、CancelLastRequest ボタンで使う
- 受付戻り値が 0 のときはコールバックが呼ばれないので、`m_pendingRequests` へ登録しない
- `GetClipboardHistory` 成功時は JSON を `JsonArray::Parse` で読み、先頭項目の `id` を `m_lastHistoryItemId` に捕捉する（既存 `GetAllNotifications` と同じ try/catch 方式）

**遅延 provider（F-10）**

- `ClipboardRenderCallback` は free function。無名 namespace に置く
- payload は**予約時に確定**して無名 namespace の静的マップ（`std::map<std::wstring, std::vector<BYTE>>`）へ格納する。provider は 2 相ともこのマップから同じサイズを返す
  - 二相のサイズ完全一致契約（実装結果 v4 の H4）を満たすため、provider 内でデータを作り直さない
- provider 内では XAML を触らない。ログ行を無名 namespace のキューに積み、`TryEnqueue` で後から `LogTextBlock` へ反映する
- provider は `try { ... } catch (...) { return CLIPBOARD_ERROR_UNKNOWN; }` で囲み、throw を境界外へ出さない
- `buffer == nullptr` のとき `*pRequiredSize` を設定して `CLIPBOARD_ERROR_BUFFER_TOO_SMALL` を返す

**ワーカースレッド呼び出し**

- `std::thread` を起動して `detach` せず、`join` はハンドラ内で行う（`copyPlainText` は即時完了するため UI を長く止めない）
- 結果表示は UI スレッドへ戻ってから行う（`join` 後にハンドラ内で `ShowResult`）

### 5.3 サンプルデータの生成方針

| データ | 生成方針 |
|---|---|
| DIB | 8x8 / 32bpp / `BI_RGB` の `BITMAPINFOHEADER` + 8*8*4 バイトの単色ピクセル。コード内で組み立てる（外部アセット不要） |
| ファイル一覧 | `%TEMP%` 配下に `native-toolkit-clipboard-sample-1.txt` / `-2.txt` を書き出し、その絶対パスを JSON 配列にする。ボタン押下時に毎回書き直す |
| 独自フォーマット | フォーマット名 `NativeToolkitSample`、payload は ASCII の短いバイト列 |
| base64 payload | `copyMultipleFormats` 用に、生成した DIB を base64 エンコードして埋め込む。エンコーダはサンプル側に小さな関数を持つ（`ClipboardFormats::Base64Decode` は decode 専用かつライブラリ内部 API のため） |
| 遅延 payload | `CF_UNICODETEXT` は NUL 終端 UTF-16 文字列、`HTML Format` は `copyHtml` と同じ内容を CF_HTML 形式で組み立てたもの |

### 5.4 入力バリデーション方針

- サンプルは固定値ボタン方式（入力欄なし）とし、既存 `NotificationPage` / `DialogPage` と揃える
  - 理由: 既存 2 ページがどちらも入力欄を持たず、固定ペイロードのボタンのみで構成されている。クリップボードの入力は JSON / バイト列で自由入力に向かない
- 例外は「捕捉済み ID を使うボタン」（RestoreHistoryItem / DeleteHistoryItem / CancelLastRequest）。未捕捉時は API を呼ばず、先に押すべきボタンを結果表示で促す（既存 `RemoveById` と同じ方式）
- `EnsureInitialized()` で未初期化時は API を呼ばずに結果表示のみ行う。ただし Error cases の「CopyPlainText (after Uninitialize)」だけは意図的にガードを通さず、`NOT_INITIALIZED` を実際に受け取る
- 数値・文字列の妥当性検証はライブラリ側の責務なので、サンプル側で先回りして弾かない（`errorCode` の確認が目的）

### 5.5 ログ表示の実装方針

- `LogTextBlock` は `Border` + `ScrollViewer`（`Height="160"`, `VerticalScrollBarVisibility="Auto"`）内の `TextBlock`
- `AppendLog(line)`: `HH:MM:SS` + 内容を追記。保持行数の上限（200 行）を超えたら先頭から捨てる
- ページは行を `std::deque<std::wstring>` で保持し、更新時に連結して `Text` に設定する
- ログの追記は必ず UI スレッド上で行う（コールバック経路は `TryEnqueue` を通す）

---

## 6. 手動確認観点

設計書「統合テスト（実機・実クリップボード）」「手動確認項目」に対応する。MSIX 配置（Visual Studio から F5）で実施する。

### 6.1 他アプリとの相互運用

| 観点 | 手順 | 期待 |
|---|---|---|
| プレーンテキスト | CopyPlainText -> メモ帳で Ctrl+V | 同一文字列 |
| HTML 互換性 | CopyHtml -> Word / ブラウザで Ctrl+V | 太字が保持される |
| HTML フォールバック | CopyHtml -> メモ帳で Ctrl+V | plainText 側が貼られる |
| CF_HDROP 双方向 | CopyFiles -> エクスプローラーで Ctrl+V / エクスプローラーでファイルをコピー -> PasteFiles | 双方向でパスが一致 |
| 画像 | CopyImage -> ペイントで Ctrl+V / ペイントでコピー -> PasteImage | 8x8 の単色画像 / 取得サイズが妥当 |
| 複数フォーマット | CopyMultipleFormats -> Word（HTML）とメモ帳（テキスト）で Ctrl+V | 貼り付け先が対応する最良の形式を選ぶ |
| 優先度 | 上記の直後に GetPreferredFormat | 最も情報量の多い形式名 |

### 6.2 変更監視（F-09）

| 観点 | 手順 | 期待 |
|---|---|---|
| 他アプリのコピーで通知 | InitializeManager -> メモ帳で任意の文字列をコピー | ログに変更通知が 1 行出る |
| 自書き込みでループしない | CopyPlainText を連続で押す | 自分の書き込みでは変更通知が出ない |
| 監視解除 | Uninitialize -> メモ帳でコピー | 通知が出ない |
| 管理者権限（UIPI） | サンプルを管理者として実行し、非管理者アプリでコピー | 通知が届くかを記録する（設計書のリスク項目） |

### 6.3 遅延レンダリング（F-10）

| 観点 | 手順 | 期待 |
|---|---|---|
| 貼り付け時に provider が呼ばれる | ReserveDeferredFormats -> ログに provider 行が無いことを確認 -> メモ帳で Ctrl+V | 貼り付けた時刻に provider の size / fill 行が出る。メモ帳に予約した内容が入る |
| 複数形式の個別レンダリング | 予約後に Word で Ctrl+V | `HTML Format` の provider だけが呼ばれる |
| 予約後の形式列挙 | 予約直後に GetClipboardFormats / HasFormat | 予約した形式が列挙される（設計書のリスク項目: `CloseClipboard` 前後の挙動を記録） |
| アプリ終了時の実体化 | 予約 -> 貼り付けずにアプリ終了 -> メモ帳で Ctrl+V | 内容が残っている（`WM_RENDERALLFORMATS`） |
| 予約の破棄 | 予約 -> 他アプリでコピー -> メモ帳で Ctrl+V | 他アプリの内容が貼られ、provider は呼ばれない |
| ワーカースレッドからの予約 | ReserveDeferred (worker thread) | `WRONG_THREAD`(14) |
| PARTIAL_STATE | 発生条件を探し、発生したら RecoverDeferredState で回復するか記録する | 設計書のリスク項目。意図的な再現手段がないため観察のみ |

### 6.4 履歴（F-12 / F-11）

| 観点 | 手順 | 期待 |
|---|---|---|
| 可用性 | GetHistoryAvailability | `historyEnabled` / `roamingEnabled` が Windows 設定と一致 |
| 履歴無効時 | Windows 設定で履歴を切って GetClipboardHistory | `HISTORY_DISABLED`(10) |
| 取得 | いくつかコピーしてから GetClipboardHistory | 項目が新しい順に並び、`timestamp` が 10 進文字列 |
| `contentTypes` | 画像をコピーしてから GetClipboardHistory | `Bitmap` などの形式名が入る |
| 復元 | GetClipboardHistory -> RestoreHistoryItem -> PastePlainText | 復元した項目の内容 |
| フォアグラウンド要件 | RestoreHistoryItem 実行時に別アプリを前面にする | `NOT_FOREGROUND`(17) が返るか、実挙動を記録する（設計書のリスク項目） |
| 削除 | DeleteHistoryItem -> GetClipboardHistory | 対象が消えている |
| 消去と pinned | Win+V で 1 件を固定 -> ClearUnpinnedHistory -> GetClipboardHistory | **固定した項目だけが残る** |
| 履歴イベント | SetHistoryCallbacks -> メモ帳でコピー | ログに履歴変更が出る |
| 設定変更イベント | SetHistoryCallbacks -> Windows 設定で履歴を切り替え | ログに enabled 変更が出て、値が設定と一致 |
| 履歴除外 | CopyPlainText (SENSITIVE) -> Win+V | 一覧に出ない |
| 同期除外 | CopyPlainText (EXCLUDE_ROAMING) -> 別デバイスの Win+V | 同期されない（サインイン環境がある場合のみ） |
| キャンセル | GetClipboardHistory -> 直後に CancelLastRequest | `CANCELED`(15) か、間に合わず成功のいずれか 1 回だけコールバックが来る |

### 6.5 ライフサイクル / スレッド（F-17）

| 観点 | 手順 | 期待 |
|---|---|---|
| 二重初期化 | InitializeManager を 2 回 | 2 回目も成功（冪等） |
| 未初期化呼び出し | Uninitialize -> CopyPlainText (after Uninitialize) | `NOT_INITIALIZED`(2) |
| 破棄可否 | Uninitialize -> CanDestroy | `TRUE` |
| pending 中の破棄 | GetClipboardHistory -> 即 Uninitialize -> CanDestroy | pending が `CANCELED`(15) で 1 回来て、その後 `CanDestroy` が `TRUE` |
| 再初期化 | Uninitialize -> InitializeManager -> CopyPlainText | 再度動作する |
| 任意スレッド | CopyPlainText (worker thread) | 成功する |
| アパートメント | 通常起動で InitializeManager | `WRONG_APARTMENT`(18) にならない（要検証 7.1） |
| ページ離脱 | Initialize -> Back -> 再入場 -> CopyPlainText | 初期化状態が保たれる。ログは再入場でクリアされる |

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
| 7.2 | `dispatchHwnd`（非表示トップレベルウィンドウ）が WinUI 3 のウィンドウ管理と干渉しないか | 干渉しない見込み。表示されず、`WS_VISIBLE` を持たない | 起動 -> Initialize -> タスクバー / Alt+Tab に余計なウィンドウが出ないことを確認する |
| 7.3 | 遅延 provider が `WM_RENDERFORMAT` 処理中に呼ばれる間、XAML 更新をキューに載せるだけで足りるか | 足りる見込み。`TryEnqueue` は即座に返る | Reserve -> 別アプリで貼り付け、ログが遅延なく出てハングしないことを確認する |
| 7.4 | `NOT_FOREGROUND`(17) が実際に返るか | 設計書は `GetForegroundWindow()` のプロセス ID 比較と定義。WinRT の実挙動が異なる可能性がある | 6.4 のフォアグラウンド要件で実測する。契約と異なる場合は仕様を勝手に変えず報告する |
| 7.5 | 履歴の `id` が復元 / 削除の両方で受理されるか | 受理される見込み | 6.4 の復元 / 削除で確認する |
| 7.6 | 予約中に `getClipboardFormats` を呼んだときの挙動 | 予約形式が列挙される見込み | 6.3 の「予約後の形式列挙」で実測して記録する |
| 7.7 | 既存 `NotificationPage` の成功 / 失敗マーカー記号が実際に正しく表示されているか | `WindowsLibraryExample.vcxproj` は全構成で `/utf-8` 済みのため正しく表示される見込み | Notification 画面で確認する。文字化けしていた場合は本計画の範囲外の既存不具合として報告する（サンプル側で `\uXXXX` 表記へ変える判断は別途） |

---

## 8. 実行確認

この実装計画で進めますか？

- 承認する: 計画を確定し、次のレビュー workflow（`review-document`）へ進む
- 修正する: 指摘内容を反映して計画ファイルを更新する
- キャンセル: 計画ファイルは保持したまま終了する
