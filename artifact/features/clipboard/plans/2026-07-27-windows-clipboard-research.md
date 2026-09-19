# Windows クリップボード機能 調査結果

- 作成日: 2026-07-27
- 改訂日: 2026-07-28（v2〜v11: レビュー指摘を順次反映 / v11: Win32 のウィンドウ所有・メッセージポンプ要件を明記）
- 対象OS: Windows（Windows 11 以降）
- 対象機能: クリップボード（Clipboard: コピー / ペースト / 監視）
- 使用言語: VC++（Visual C++ / Win32 コアは C++17、WinRT コルーチン版は C++20 / C++/WinRT）
- 対象プロジェクト: `windows/WindowsLibrary`（MFC DLL）+ `windows/UnityWindowsPlugin`

---

## 目的

Windows のネイティブクリップボード API を、native-toolkit の対象範囲について網羅し、組み込み設計に必要な情報を整理する。Windows には系統の異なる 2 つの API 群（Win32 クリップボード API / WinRT `Windows.ApplicationModel.DataTransfer`）が存在するため、両者の責務・制約・使い分けを明確にすることを主眼とする。あわせて Android 版クリップボード（`artifact/plans/clipboard/2026-07-25-android-clipboard-research.md`）との公開 API 対応関係を整理する。

用語の定義（レビュー指摘反映）: 本書の「全網羅」は **native-toolkit の対象範囲（In scope）を網羅する**という意味で用いる。Out of scope の API についても、範囲外である旨を明記したうえで存在のみ一覧化する。

---

## 調査対象範囲

### In scope

| No | サブ機能 | DoD 対応 |
|---|---|---|
| S-01 | プレーンテキスト（Unicode）のコピー / ペースト | D-01, D-02 |
| S-02 | HTML（`CF_HTML`）のコピー / ペースト | D-03, D-04 |
| S-03 | ファイル一覧（`CF_HDROP`）のコピー / ペースト | D-05, D-06 |
| S-04 | 画像（`CF_DIB` / `CF_DIBV5` / `CF_BITMAP`）のコピー / ペースト | D-07, D-08 |
| S-05 | 独自フォーマット（`RegisterClipboardFormat`）のコピー / ペースト | D-09, D-10 |
| S-06 | 複数フォーマットの同時配置（情報量の多い順） | D-11 |
| S-07 | 内容確認（フォーマット有無・列挙・優先フォーマット判定・名前取得） | D-12 |
| S-08 | クリップボードのクリア | D-13 |
| S-09 | 変更監視（フォーマットリスナー / シーケンス番号） | D-14, D-15, D-16, D-34 |
| S-10 | 遅延レンダリング（`WM_RENDERFORMAT` / `WM_RENDERALLFORMATS`） | D-17, D-32 |
| S-11 | 履歴・クラウド同期からの除外 | D-18 |
| S-12 | 履歴の取得 / 復元 | D-19 |
| S-13 | 履歴項目の削除 / 未固定履歴の消去（`ClearHistory` は pinned item を消さない） | D-20 |
| S-14 | 履歴・設定変更イベント（`HistoryChanged` 等） | D-21, D-34 |
| S-15 | 履歴・同期の有効状態判定とフォールバック | D-22 |
| S-16 | Package Identity（MSIX / 未パッケージ）別の利用可否 | D-23, D-24 |
| S-17 | エラー正規化（Win32 / WinRT → Domain エラー） | D-25, D-26, D-35 |
| S-18 | 外部入力としてのクリップボード内容の境界検証 | D-27, D-28 |
| S-19 | MFC × C++/WinRT 共存でのビルド | D-29 |
| S-20 | WinRT 履歴 API のスレッドモデル（開始スレッド・待機方法・アパートメント・コールバックスレッド契約・Bridge ライフサイクル） | D-31, D-33, D-34 |

### Out of scope

| 項目 | 除外理由 |
|---|---|
| Android / iOS / macOS のクリップボード API | 別 OS の調査範囲 |
| OLE ドラッグ&ドロップ（`IDropSource` / `IDropTarget`）、`OleSetClipboard` / `OleGetClipboard` による `IDataObject` 共有 | クリップボード機能の公開 API に不要。ドラッグ&ドロップは別機能 |
| OLE 埋め込み / リンクオブジェクト（複合ドキュメント） | 対象アプリ種別に不要 |
| `CF_OWNERDISPLAY` と関連通知の**実運用** | クリップボードビューア UI を提供しないため。存在のみ API 表に記載 |
| 旧来フォーマット（`CF_PENDATA` / `CF_SYLK` / `CF_DIF` / `CF_TIFF` / `CF_RIFF` / `CF_WAVE` / `CF_DSP*`）の**実装** | 現行アプリでの相互運用需要がないため。存在のみ API 表に記載 |
| 旧クリップボードビューアチェーン（`SetClipboardViewer` 系）の**実運用** | 公式が後方互換専用と位置づけ、フォーマットリスナーを推奨しているため。存在のみ API 表に記載 |
| Enterprise Data Protection（`DataPackageView.RequestAccessAsync` / `UnlockAndAssumeEnterpriseIdentity`） | 企業ポリシー連携は対象外 |
| 共有（Share）機能（`DataTransferManager`） | 別機能 `artifact/plans/share/` の範囲 |
| `DataPackage.SetDataProvider`（WinRT 遅延提供） | Package Identity 必須のため未パッケージで使えない。Win32 の遅延レンダリング（S-10）で代替 |

---

## 公式文書一覧（最優先ソース）

### Win32 クリップボード API

| タイトル | URL |
|---|---|
| Clipboard（概説・関数/メッセージ一覧） | https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard |
| Clipboard Operations（所有権・操作） | https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-operations |
| Using the Clipboard（実装手順・サンプル） | https://learn.microsoft.com/en-us/windows/win32/dataxchg/using-the-clipboard |
| Clipboard Formats（登録/私用/合成/履歴・クラウド） | https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats |
| Standard Clipboard Formats（CF_* 定数） | https://learn.microsoft.com/en-us/windows/win32/dataxchg/standard-clipboard-formats |
| HTML Clipboard Format（CF_HTML 仕様） | https://learn.microsoft.com/en-us/windows/win32/dataxchg/html-clipboard-format |
| OpenClipboard | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-openclipboard |
| EmptyClipboard | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-emptyclipboard |
| SetClipboardData | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setclipboarddata |
| GetClipboardData | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclipboarddata |
| AddClipboardFormatListener | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-addclipboardformatlistener |
| WM_CLIPBOARDUPDATE | https://learn.microsoft.com/en-us/windows/win32/dataxchg/wm-clipboardupdate |
| GetClipboardSequenceNumber | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getclipboardsequencenumber |
| GetUpdatedClipboardFormats | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-getupdatedclipboardformats |
| EnumClipboardFormats（0 の多義性と `ERROR_SUCCESS`） | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-enumclipboardformats |
| CountClipboardFormats（失敗時も 0） | https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-countclipboardformats |
| WM_RENDERFORMAT | https://learn.microsoft.com/en-us/windows/win32/dataxchg/wm-renderformat |
| WM_RENDERALLFORMATS | https://learn.microsoft.com/en-us/windows/win32/dataxchg/wm-renderallformats |
| Clipboard Operations – Delayed Rendering | https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-operations |

### WinRT DataTransfer API

| タイトル | URL |
|---|---|
| Clipboard クラス | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboard |
| DataPackage クラス | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.datapackage |
| DataPackageView クラス | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.datapackageview |
| ClipboardContentOptions クラス | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboardcontentoptions |
| ClipboardHistoryItem / ClipboardHistoryItemsResult | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboardhistoryitem |
| ClipboardHistoryItemsResultStatus | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboardhistoryitemsresultstatus |
| SetHistoryItemAsContentStatus | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.sethistoryitemascontentstatus |
| Clipboard.ClearHistory（pinned item の制約） | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboard.clearhistory |
| Clipboard.HistoryChanged（発火条件） | https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboard.historychanged |
| Copy and Paste in WinUI and UWP Apps | https://learn.microsoft.com/en-us/windows/apps/develop/communication/copy-and-paste |
| Advanced concurrency and asynchrony with C++/WinRT（get / wait_for / apartment） | https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/concurrency-2 |
| Error handling with C++/WinRT（例外変換・`noexcept` 境界・`std::bad_alloc`） | https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/error-handling |
| winrt::event_revoker（`void revoke() noexcept`） | https://learn.microsoft.com/en-us/uwp/cpp-ref-for-winrt/event-revoker |
| Handle events by using delegates in C++/WinRT（解除と in-flight イベント） | https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/handle-events |

### デスクトップアプリ制約・プロジェクト設定・リリース情報

| タイトル | URL |
|---|---|
| WinRT APIs not supported in desktop apps（Package Identity 必須 API 一覧） | https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-api-desktop-app-support |
| Call Windows Runtime APIs in desktop apps（C++ プロジェクト設定） | https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-apis-desktop-apps |
| Windows 11 release information | https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information |

---

## 補助ソース一覧（必要時のみ）

| 内容 | 情報源 | 信頼度 |
|---|---|---|
| `OpenClipboard` 失敗時のリトライ実装パターン（回数・間隔） | 公式は「他ウィンドウが開いていると失敗する」「`GetLastError` で詳細取得」までしか規定しない。具体的なリトライ方針は実装側の判断 | medium |

補足: 本調査書の API 仕様・制約は全て公式文書で裏付け済み。補助ソースは実装パターンの参考としてのみ扱い、設計根拠には使用しない。公式文書と矛盾する記述は採用しない。

---

## API 系統の選択（設計の前提）

Windows には 2 系統のクリップボード API がある。

| 観点 | Win32 クリップボード API | WinRT `DataTransfer.Clipboard` |
|---|---|---|
| 名前空間 / ヘッダ | `winuser.h`（`Windows.h`） | `winrt/Windows.ApplicationModel.DataTransfer.h` |
| Package Identity | 不要（MSIX / 未パッケージ両対応） | Clipboard / DataPackage / DataPackageView は不要。`DataProviderHandler`・`DataTransferManager` 系は**必須** |
| フォアグラウンド要件 | 明示要件なし（`OpenClipboard` の排他制御のみ） | 公式 Remarks に「呼び出し元アプリが UI スレッドでフォーカスを持つ時のみアクセス可能」 |
| 監視 | `AddClipboardFormatListener` + `WM_CLIPBOARDUPDATE`（HWND 必須） | `Clipboard::ContentChanged`（HWND 不要） |
| 履歴 / クラウド同期 | 登録フォーマットによる除外制御のみ | 履歴の取得・復元・削除まで可能（Windows 10 1809+） |
| 同期 / 非同期 | 同期のみ | 同期 API と `IAsyncOperation` が混在（STA で非同期 API のブロッキング待機は不可） |
| フォーマット粒度 | `CF_*` 単位で完全制御 | `StandardDataFormats` 中心（生フォーマット名も可） |

推奨（設計段階で確定する事項）:

- **コア（S-01〜S-11）は Win32 API を主実装とする。** 未パッケージ・非フォアグラウンドでも動作し、`WindowsLibrary` が MFC DLL（`CWinApp`）で HWND を確保できるため。
- **履歴機能（S-12〜S-15）のみ WinRT を使う。** Win32 に同等 API が存在しないため。
- WinRT 側の失敗（履歴無効・アクセス拒否）は Domain エラー定数へ正規化し、Win32 コア機能はそれに影響されない構成にする。

参照: [WinRT APIs not supported in desktop apps](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-api-desktop-app-support) / [Clipboard クラス Remarks](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboard)

---

## WinRT 履歴 API のスレッドモデル（設計の前提）

前節までに、相反する 2 つの制約が存在する。

1. WinRT `Clipboard` は「呼び出し元アプリが**UI スレッドでフォーカスを持つ**時のみアクセス可能」（公式 Remarks）
2. `IAsyncOperation::get()` は**無期限ブロックする**ため STA（UI スレッド）で呼ぶと C++/WinRT が assert する（`agent-rules/coding-rules/windows.md` に既出）

「バックグラウンドスレッドで `get()` する」だけでは 1 を満たせない可能性がある。両立させるには**開始スレッドと待機方法を分離**する。

### 採用方針（確定）: UI スレッドで開始し、非ブロッキングで完了を受け取る

```
[UI スレッド（STA / フォアグラウンド）]
  1. IsHistoryEnabled() でフォールバック判定
  2. Clipboard::GetHistoryItemsAsync() を呼び、IAsyncOperation を取得（ここまで同期・非ブロッキング）
  3. co_await（または Completed ハンドラ）で待機 — UI スレッドは塞がない
  4. C++/WinRT は co_await 後に呼び出し元コンテキスト（STA）へ復帰する（公式明記）
  5. 結果を Domain 型へ変換し、Unity へコールバックで返す
```

- 待機は `co_await` を用いる（`winrt::fire_and_forget` / `IAsyncAction` を返す関数にする）。C++/WinRT は WinRT の `IAsyncXxx` を `co_await` した場合、**呼び出し元のアパートメントコンテキストへ復帰することを保証する**（公式明記）ため、STA で開始すれば STA で再開する。
- 履歴 API の公開 Bridge は **非同期（コールバック方式）で確定**する。UI スレッド + フォアグラウンド要件があるため、MTA ワーカーで待機して同期 Bridge を維持する方式は採用しない。
- コルーチンを採用する場合は `/std:c++20` を選ぶ（`/std:c++17` + `/await` の組み合わせは非推奨）。コルーチンを使わない場合は `IAsyncOperation::Completed` ハンドラで同じ構成が組める。

### 非 UI スレッドからの呼び出しをどう扱うか（Bridge 入口の契約）

Unity / ネイティブの**任意のスレッド**から Bridge が呼ばれ得る。「UI スレッドで開始する」ことを保証するのは Bridge 入口の責務であり、コルーチンだけでは保証できない。

```
[任意の呼び出しスレッド]                [所有 UI スレッド（STA / メッセージポンプあり）]
  Bridge C API 呼び出し
    │  すでに UI スレッド？ ── Yes ──────► 直接開始
    │  No
    └─ PostMessage(ownerHwnd, WM_APP_xxx, ...) ─► WndProc が受信
                                                    │
                                                    ├─ フォーカス確認（GetForegroundWindow 等）
                                                    ├─ IsHistoryEnabled() 判定
                                                    ├─ 非同期操作を開始し co_await
                                                    └─ 完了 → 結果を Domain 型へ変換 → コールバック
```

Bridge 入口の契約として次を定義する（詳細は設計工程で確定）。

| 項目 | 契約 |
|---|---|
| 呼び出しスレッド | 任意。Bridge が UI スレッド判定（`GetCurrentThreadId() == uiThreadId`）を行う |
| UI スレッドへの配送 | 所有ウィンドウへ `PostMessage`（`SendMessage` は呼び出し元をブロックしデッドロックし得るため使わない）。要求データはヒープに確保して `lParam` で渡し、受信側が所有権を取る |
| フォアグラウンド判定 | 開始前に自プロセスのウィンドウが前面かを確認する。UI スレッドからの直接開始経路では受付成立前に判定し、不成立なら同期戻り値で `ACCESS_DENIED` 相当を返してコールバックを呼ばない。非 UI スレッドから UI キューへ投入済みの経路では受付成立後の判定になるため、不成立をコールバックで `ACCESS_DENIED` 相当としてちょうど 1 回通知する。要求は保留しない |
| 完了コールバックのスレッド | 既定は **UI スレッド**（`co_await` 後に復帰した文脈）。Unity 側が別スレッドを要求する場合は Bridge が明示的に切り替える。**どちらであるかを公開 API のドキュメントに明記する** |
| キャンセル | 保留中の要求と実行中の `IAsyncOperation` を `Cancel()` できる識別子（リクエスト ID）を返す。`Uninit` 時は保留要求を全て破棄する |
| メッセージポンプがない場合 | 所有ウィンドウのスレッドがポンプを回していない場合は `PostMessage` が処理されない。監視用ウィンドウを toolkit 側で作る場合は**専用スレッド + メッセージループ**を持たせるかを設計で決める（**要判断**） |

**要求オブジェクトの所有権と pending 管理**

`PostMessage` はキューへの投入が失敗し得るため、所有権の移転タイミングを厳密に定義する。

| 段階 | 所有者 | 失敗時の扱い |
|---|---|---|
| 要求オブジェクト生成 | 呼び出しスレッド | - |
| pending テーブルへ登録（リクエスト ID 採番） | Manager（テーブル） | 登録失敗なら即座に破棄しエラー返却 |
| `PostMessage` 実行 | **成功した瞬間に受信側（UI スレッド）へ移る** | **失敗した場合は投入されていないので、呼び出しスレッドが pending テーブルから取り出して即座に解放**し、エラーを返す（コールバックは呼ばない） |
| UI スレッド上で直接開始 | Manager（pending テーブル） | 引数・フォアグラウンド等の受付前検証後、実行開始への引き渡しが成立した時点で受付成立。成立前の失敗は pending から取り出して同期エラーを返し、コールバックを呼ばない |
| WndProc 受信 | UI スレッド | 受信側が必ず解放責任を持つ |
| 完了 / キャンセル | pending テーブルから取り出した側 | 取り出せた側だけがコールバックを 1 回呼ぶ |

- **`Uninit` との競合**: `Uninit` は pending テーブルをドレインし、未処理要求へキャンセル通知を出してから破棄する。その後にメッセージが処理された場合、pending テーブルから取り出せないため何もせず破棄する。
- **ウィンドウ破棄との競合**: pending 要求が残っている状態で `DestroyWindow` してはならない（後述の shutdown gate）。
- **キャンセルと完了の競合**: 両者とも pending テーブルからの取り出しで排他する。取り出せた側のみが処理を進めるため、コールバックは必ずちょうど 1 回になる。

**終了シーケンス（shutdown gate）**

監視・所有ウィンドウの破棄は次の順序を守る。いずれかが失敗した状態で `DestroyWindow` を呼ばない。

```
Uninit
  1. 新規要求の受付を停止（gate を閉じる）
  2. pending 要求をドレイン（各コールバックへキャンセル通知 → 破棄）
  3. ClipboardWatcher::Stop() が成功するまで実行（失敗ならリトライ、上限超過ならログ + MONITOR_REGISTER_FAILED）
  4. HistoryWatcher::Stop() が全件 revoke 成功するまで実行
     （未完了の間は revokePending_ 状態を保持し、Start() を拒否する）
  5. DeferredClipboard が PARTIAL_STATE なら RecoverFromPartialState() を試行
  6. 3・4 の成功を確認してから DestroyWindow()
  7. ワーカースレッドを使っている場合のみ uninit_apartment()
```

### 不採用案（比較記録）

| 案 | 内容 | 懸念 |
|---|---|---|
| B: MTA ワーカーで開始〜待機まで完結 | ワーカースレッドで `winrt::init_apartment(winrt::apartment_type::multi_threaded)` → 履歴 API 呼び出し → `wait_for()` → `winrt::uninit_apartment()` | **不採用**。`Clipboard` の UI スレッド + フォアグラウンド要件を満たさない。`wait_for` はスレッドアフィニティ要件のない WinRT 非同期 API に同期 Bridge を提供する場合だけの方式 |
| C: UI スレッドで開始し、UI スレッドをブロックして待機 | `get()` を STA で呼ぶ | **採用不可**。cppwinrt が assert し、完了ディスパッチとデッドロックする恐れ |

案 B / C は設計候補ではなく、採用しない理由を残すための比較記録である。`Clipboard` 履歴 API の実装と DoD は、上記の確定方針（UI スレッド開始 + 非同期 callback Bridge）のみを対象とする。

参照: [Clipboard クラス Remarks](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboard) / [Advanced concurrency and asynchrony with C++/WinRT](https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/concurrency-2)

---

## Android 版との公開 API 対応表

Android 版の公開 API（`ClipboardRepository`: copy / read / hasClip / getDescription / clear + `ClipboardChangeMonitor`）と Windows の対応関係。

| Android のサブ機能 | Windows での対応 | 分類 | 備考 |
|---|---|---|---|
| プレーンテキスト copy / read | `CF_UNICODETEXT` | 共通 | そのまま対応可能 |
| HTML copy / read | `CF_HTML` | 共通 | Windows 側は UTF-8 とバイトオフセットヘッダが必要。ペイロード形式が異なるため変換層が要る |
| URI（`content://`）copy / read | 直接の対応なし。ファイル参照は `CF_HDROP`（実パス）、Web リンクは `CF_UNICODETEXT` または WinRT `SetWebLink` | 差異あり | Android の `content://` は provider 経由の抽象参照、Windows の `CF_HDROP` は実ファイルパス。**公開 API を共通化するか OS 別に分けるかは設計段階で判断（要判断）** |
| Intent copy / read | 対応なし | Windows 非対応 | Windows に等価概念がない。公開 API はエラー（`NOT_SUPPORTED` 相当）を返す方針を推奨 |
| 複数 Item（`ClipData.addItem`） | 対応なし（Windows の「複数フォーマット」は同一データの別表現であり別概念） | Windows 非対応 | 複数テキストは改行連結で代替。**代替方針は設計段階で判断（要判断）** |
| `hasPrimaryClip` | `CountClipboardFormats()` / `IsClipboardFormatAvailable` | 共通 | |
| `getPrimaryClipDescription` | `GetUpdatedClipboardFormats` + `GetClipboardFormatName` | 共通 | Android の label 相当は Windows になし |
| `clearPrimaryClip` | `EmptyClipboard`（`OpenClipboard` 必須） | 共通 | |
| 変更監視 | `AddClipboardFormatListener` + `WM_CLIPBOARDUPDATE` | 共通 | Windows は監視用 HWND が必要 |
| `EXTRA_IS_SENSITIVE`（プレビュー抑止） | `CanIncludeInClipboardHistory` = 0 / `CanUploadToCloudClipboard` = 0 | 共通（意味は近いが同一ではない） | Android はコピー確認 UI のプレビュー抑止、Windows は履歴・クラウド同期からの除外 |
| （Android になし） | 画像（`CF_DIB`）の copy / paste | Windows 固有 | Android は `content://` URI 経由 |
| （Android になし） | ファイル一覧（`CF_HDROP`） | Windows 固有 | |
| （Android になし） | 遅延レンダリング | Windows 固有 | |
| （Android になし） | クリップボード履歴の取得 / 復元 / 削除 | Windows 固有 | |
| （Android になし） | 独自フォーマット（`RegisterClipboardFormat`） | Windows 固有 | |

結論: **共通化できるのはテキスト / HTML / 内容確認 / クリア / 変更監視 / 機微情報除外**。URI と複数 Item は意味論が異なり、Intent は Windows 非対応。公開 API は「共通コア + OS 固有拡張」の構成を推奨する（最終的な API 形は設計工程で確定）。

---

## 機能マップ（サブ機能分解）

```
クリップボード機能（Windows）
├── 基本操作（Win32）
│   ├── オープン / クローズ / 排他（OpenClipboard / CloseClipboard）
│   ├── クリア（EmptyClipboard）
│   └── 所有者・状態取得（GetClipboardOwner / GetOpenClipboardWindow）
├── コピー（書き込み・Win32）
│   ├── プレーンテキスト（CF_UNICODETEXT）
│   ├── HTML（CF_HTML / "HTML Format"）
│   ├── ファイル一覧（CF_HDROP / DROPFILES）
│   ├── 画像（CF_DIB / CF_DIBV5 / CF_BITMAP）
│   ├── 独自フォーマット（RegisterClipboardFormat）
│   ├── 複数フォーマットの同時配置
│   └── 遅延レンダリング（SetClipboardData(fmt, NULL)）
├── ペースト（読み取り・Win32）
│   ├── フォーマット有無判定（IsClipboardFormatAvailable）
│   ├── フォーマット列挙（EnumClipboardFormats / CountClipboardFormats / GetUpdatedClipboardFormats）
│   ├── 優先フォーマット選択（GetPriorityClipboardFormat）
│   ├── フォーマット名取得（GetClipboardFormatName）
│   ├── データ取得（GetClipboardData）
│   └── 境界検証（GlobalSize / 終端 / オフセット / オーバーフロー）
├── 変更監視
│   ├── フォーマットリスナー（AddClipboardFormatListener / WM_CLIPBOARDUPDATE）※推奨
│   ├── シーケンス番号（GetClipboardSequenceNumber）※キャッシュ検証・自己起因判定用
│   └── ビューアチェーン（SetClipboardViewer / WM_DRAWCLIPBOARD）※後方互換のみ・対象外
├── 履歴 / クラウド（WinRT）
│   ├── 履歴取得（GetHistoryItemsAsync）
│   ├── 履歴からの復元（SetHistoryItemAsContent）
│   ├── 履歴削除（DeleteItemFromHistory / ClearHistory）
│   ├── 有効状態（IsHistoryEnabled / IsRoamingEnabled）
│   └── 状態変化通知（HistoryChanged / HistoryEnabledChanged / RoamingEnabledChanged）
└── プライバシー / 除外制御
    ├── 履歴除外（CanIncludeInClipboardHistory = 0）
    ├── クラウド同期除外（CanUploadToCloudClipboard = 0）
    ├── 一括除外（ExcludeClipboardContentFromMonitorProcessing）
    └── WinRT 版（ClipboardContentOptions.IsAllowedInHistory / IsRoamable）
```

---

## API 一覧（サブ機能別 / In scope 網羅 + 対象外 API の記載）

### 基本操作 / 排他制御（Win32）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `OpenClipboard(hWndNewOwner)` | クリップボードを開き他プロセスの変更を排他 | `HWND`（`NULL` 可＝現タスクに関連付け） | `BOOL` | **他ウィンドウが開いていると失敗**（公式明記）。失敗理由は `GetLastError` で取得する。特定のエラーコードは公式に規定がないため、値を断定せず保持・正規化する | Windows 2000 |
| `CloseClipboard()` | クリップボードを閉じる | なし | `BOOL` | 未オープンで失敗。`OpenClipboard` 成功のたびに必ず呼ぶ（公式明記） | Windows 2000 |
| `EmptyClipboard()` | 内容を全消去し、開いているウィンドウへ所有権を移す | なし | `BOOL` | `OpenClipboard` 前に呼ぶと失敗。**`OpenClipboard(NULL)` の後に呼ぶと成功はするが所有者が `NULL` になり、以降の `SetClipboardData` が失敗する**（公式明記） | Windows 2000 |
| `GetClipboardOwner()` | 現在の所有ウィンドウ取得 | なし | `HWND`（無所有で `NULL`） | なし | Windows 2000 |
| `GetOpenClipboardWindow()` | 現在クリップボードを開いているウィンドウ取得 | なし | `HWND` | なし | Windows 2000 |

**owner HWND の API 契約（レビュー指摘反映）**

| 操作 | owner HWND | 根拠 |
|---|---|---|
| 書き込み（`EmptyClipboard` + `SetClipboardData`） | **有効な HWND 必須。`NULL` は拒否する** | `OpenClipboard(NULL)` → `EmptyClipboard` で所有者が `NULL` になり `SetClipboardData` が失敗する（公式明記） |
| 遅延レンダリング | **有効な HWND 必須**（`WM_RENDERFORMAT` の受信先が必要） | 同上 + メッセージ受信の必要性 |
| 読み取り（`GetClipboardData`） | `NULL` 可（所有権を取らないため） | `EmptyClipboard` を呼ばないので所有者は変化しない |
| 変更監視 | **有効な HWND 必須** | `AddClipboardFormatListener` の引数 |

実装方針: Manager が所有するウィンドウ（メッセージ専用ウィンドウ）を保持し、書き込み・遅延レンダリング・監視ではこれを使う。`NULL` が渡された場合は `INVALID_ARGUMENT` 相当の Domain エラーで即座に失敗させる。

参照: [OpenClipboard](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-openclipboard) / [EmptyClipboard](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-emptyclipboard)

### コピー（書き込み・Win32）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `SetClipboardData(uFormat, hMem)` | 指定フォーマットでデータを配置 | `UINT uFormat`, `HANDLE hMem`（`NULL` で遅延レンダリング） | `HANDLE`（失敗時 `NULL`） | 呼び出し元が所有者でない / `OpenClipboard` 未実施で失敗。成功後は**ハンドル所有権がシステムに移る**ため `GlobalFree` してはならない。**遅延レンダリング時は成功でも `NULL` を返すため、戻り値のみでは成否を判定できない** | Windows 2000 |
| `GlobalAlloc(GMEM_MOVEABLE, size)` | クリップボード用メモリ確保 | フラグ, サイズ | `HGLOBAL`（失敗時 `NULL`） | 確保失敗。**必ず戻り値を確認する** | Windows 2000 |
| `GlobalLock` / `GlobalUnlock` | メモリのロック / 解除 | `HGLOBAL` | ポインタ（失敗時 `NULL`） / `BOOL` | **ロック失敗時は `NULL`。戻り値を確認せず参照すると null 参照になる** | Windows 2000 |
| `GlobalSize(hMem)` | ブロックのバイト長取得 | `HGLOBAL` | `SIZE_T`（失敗時 0） | 読み取り時の境界検証に必須 | Windows 2000 |
| `RegisterClipboardFormat(lpszFormat)` | 登録フォーマット ID の取得（`"HTML Format"` 等） | フォーマット名 | `UINT`（**失敗時 0**） | 名前重複時は同一 ID を返す（仕様どおり）。**0 は失敗であり必ず判定する** | Windows 2000 |
| `CF_UNICODETEXT` | Unicode テキスト。`CF_TEXT` / `CF_OEMTEXT` はシステムが自動合成 | - | - | 終端 `L'\0'` 必須 | Windows 2000 |
| `CF_HTML`（`RegisterClipboardFormat(L"HTML Format")`） | HTML フラグメント。**UTF-8** でヘッダ + フラグメントを格納 | - | - | オフセット値（`StartHTML` 等）の計算誤りで貼り付け先が解釈不能 | Windows 2000 |
| `CF_HDROP` + `DROPFILES` | ファイル / フォルダ一覧 | `DROPFILES` ヘッダ + ダブル NUL 終端のパス列 | - | `fWide` 不一致・終端不足で受け側が誤読 | Windows 2000 |
| `CF_DIB` / `CF_DIBV5` | 画像（`BITMAPINFO` / `BITMAPV5HEADER` + ビット列）。画像コピー時に公式推奨 | - | - | ヘッダサイズ / パレット計算誤り | Windows 2000 |
| `CF_BITMAP` | `HBITMAP`。システムが `CF_DIB` / `CF_DIBV5` を合成 | - | - | 貼り付け時のシステムパレット依存 | Windows 2000 |
| `CF_LOCALE` | テキストのロケール（`LCID`）。`CF_TEXT` ↔ `CF_UNICODETEXT` 変換のコードページに使われる | - | - | 未設定時は入力言語が自動設定 | Windows 2000 |
| `CF_PRIVATEFIRST` 〜 `CF_PRIVATELAST` | 私用フォーマット。**システムが自動解放しない**ため `WM_DESTROYCLIPBOARD` で解放 | - | - | 解放漏れによるリーク | Windows 2000 |
| `CF_GDIOBJFIRST` 〜 `CF_GDIOBJLAST` | アプリ定義 GDI オブジェクト用範囲（`GlobalAlloc(GMEM_MOVEABLE)` ハンドル） | - | - | 用途誤り | Windows 2000 |
| `CF_METAFILEPICT` / `CF_ENHMETAFILE` | メタファイル（相互に合成される） | - | - | `METAFILEPICT` の解放責務 | Windows 2000 |
| `CF_OWNERDISPLAY` | オーナー描画（**Out of scope・参考**） | `hMem` は `NULL` 必須 | - | 関連メッセージ未処理で表示不能 | Windows 2000 |
| `CF_DIF` / `CF_SYLK` / `CF_TIFF` / `CF_RIFF` / `CF_WAVE` / `CF_PENDATA` | 旧来フォーマット（**Out of scope・参考**） | - | - | - | Windows 2000 |
| `CF_DSPTEXT` / `CF_DSPBITMAP` / `CF_DSPMETAFILEPICT` / `CF_DSPENHMETAFILE` | 私用フォーマットの表示代替（**Out of scope・参考**） | - | - | - | Windows 2000 |

補足（複数フォーマット / S-06）: 1 回の `OpenClipboard` 〜 `CloseClipboard` の間に `SetClipboardData` を複数回呼び、**情報量の多いフォーマットから先に**配置する。貼り付け側は最初に認識したフォーマットを採用するため、順序が優先度になる（公式明記）。

参照: [SetClipboardData](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setclipboarddata) / [Clipboard Formats](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats)

### ペースト（読み取り・Win32）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `IsClipboardFormatAvailable(format)` | フォーマット有無の判定（`OpenClipboard` 不要） | `UINT` | `BOOL` | なし | Windows 2000 |
| `GetClipboardData(uFormat)` | データ取得 | `UINT` | `HANDLE`（失敗時 `NULL`） | 未オープンで失敗。**返却ハンドルはクリップボード所有のまま**。解放・ロック放置は不可 | Windows 2000 |
| `EnumClipboardFormats(format)` | フォーマット列挙（0 から開始、0 で終了） | `UINT` | `UINT` | 未オープンで失敗。合成フォーマットは実体の後に列挙される | Windows 2000 |
| `CountClipboardFormats()` | フォーマット数 | なし | `int` | なし | Windows 2000 |
| `GetPriorityClipboardFormat(paFormats, cFormats)` | 優先順リストから最初に利用可能なものを返す | `UINT*`, `int` | `int`（該当なし `0` / 空 `-1`） | なし | Windows 2000 |
| `GetUpdatedClipboardFormats(lpuiFormats, cFormats, pcFormatsOut)` | 現在のフォーマット一覧を一括取得（`OpenClipboard` 不要） | 配列, 個数, 出力個数 | `BOOL` | バッファ不足で `ERROR_INSUFFICIENT_BUFFER` | Windows Vista |
| `GetClipboardFormatName(format, lpszBuffer, cch)` | 登録フォーマット名の取得 | ID, バッファ, 長さ | `int`（失敗時 0） | 標準フォーマットには使えない | Windows 2000 |
| `DragQueryFile(hDrop, iFile, buf, cch)` | `CF_HDROP` からファイル数 / パス取得 | `HDROP`, index（`0xFFFFFFFF` で個数）, バッファ | `UINT` | 範囲外 index。**バッファ長は「NUL を除く長さ + 1」を確保する** | `shellapi.h` |

**外部入力としての境界検証規則（S-18・レビュー指摘反映）**

クリップボードの内容は**他プロセスが供給した信頼できない入力**として扱う。全フォーマット共通で以下を解析前に検証する。

| 検証項目 | 内容 | 対象フォーマット |
|---|---|---|
| ブロックサイズ | `GlobalSize(hMem)` が期待する最小サイズ以上か | 全て |
| ロック成否 | `GlobalLock` の戻り値が非 `NULL` か | 全て |
| 終端 NUL | ブロック内に終端 NUL が存在するか（`wcsnlen(src, maxChars) < maxChars`） | `CF_UNICODETEXT` / `CF_HTML` |
| 文字幅整合 | `GlobalSize` が `sizeof(wchar_t)` の倍数か | `CF_UNICODETEXT` |
| 構造体サイズ | `GlobalSize >= sizeof(DROPFILES)`、`pFiles` がブロック内を指すか | `CF_HDROP` |
| ヘッダサイズ | `BITMAPINFOHEADER.biSize` が既知の値か、ヘッダ + パレット + ビット列がブロック内に収まるか | `CF_DIB` / `CF_DIBV5` |
| オフセット | `StartHTML` / `EndHTML` / `StartFragment` / `EndFragment` が 0 以上かつブロック長以内、start <= end か | `CF_HTML` |
| 加算オーバーフロー | オフセット + 長さの加算が `SIZE_T` を超えないか（加算前に減算形で比較する） | 全て |
| 上限サイズ | 想定を超える巨大データの拒否（DoS 防止） | 全て |

検証失敗時は例外を投げず `INVALID_DATA` 相当の Domain エラーを返す。上記は**失敗系の単体テスト対象**とする（D-28）。

**書き込み側のサイズ計算にも同じ規則を適用する。** 読み取りだけでなく、`(size + 1) * sizeof(wchar_t)`（テキスト）、パス長の総和（`CF_HDROP`）、`size_t` → `int` 変換（`CF_HTML` のオフセット）でも桁あふれが起こり得る。共通の checked 演算ユーティリティを用意し、全ての確保サイズ計算を通す。

```cpp
// Common checked arithmetic used by every size computation, read and write alike.
// Compare in subtracted form so the check itself cannot overflow.
inline bool CheckedAdd(size_t a, size_t b, size_t& out)
{
    if (a > SIZE_MAX - b) return false;
    out = a + b;
    return true;
}

inline bool CheckedMul(size_t a, size_t b, size_t& out)
{
    if (a != 0 && b > SIZE_MAX / a) return false;
    out = a * b;
    return true;
}

// Narrowing used when building the CF_HTML header, whose offsets are int-formatted.
inline bool CheckedToInt(size_t v, int& out)
{
    if (v > static_cast<size_t>(INT_MAX)) return false;
    out = static_cast<int>(v);
    return true;
}

// Narrowing used when passing buffer element counts to Win32 APIs that take UINT.
inline bool CheckedToUInt(size_t v, UINT& out)
{
    if (v > static_cast<size_t>(UINT_MAX)) return false;
    out = static_cast<UINT>(v);
    return true;
}
```

構造検証は形式ごとの関数（`ValidateDropFiles` / `ValidateDib` / `ParseCfHtmlHeader` 等）へ分離し、WinRT / Win32 非依存の純ロジックとして単体テストする（D-30）。

**サンプルコードの位置づけ**: 後述のサンプルは各サブ機能の**最小例**であり、checked 演算・構造検証をすべて展開したものではない（紙面上の可読性を優先）。D-27 / D-28 の対象は**実装コード**であり、実装時には全ての確保・解析パスで上記ユーティリティと検証関数を通す。

### クリア

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `EmptyClipboard()`（`OpenClipboard` 後） | クリップボードを空にする | なし | `BOOL` | 未オープンで失敗 | Windows 2000 |
| `Clipboard::Clear()`（WinRT） | 同上（WinRT 経由） | なし | `void` | フォアグラウンド要件 | Windows 10 1507 |

### 変更監視

| API / メッセージ | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `AddClipboardFormatListener(hwnd)` | リスナー登録（**推奨方式**） | `HWND` | `BOOL` | 同一 HWND の二重登録は失敗。**戻り値を必ず確認する** | Windows Vista |
| `RemoveClipboardFormatListener(hwnd)` | 解除 | `HWND` | `BOOL` | 未登録 HWND で失敗。**戻り値を必ず確認する** | Windows Vista |
| `WM_CLIPBOARDUPDATE` | 内容変更の通知（post される） | - | - | 自プロセスの変更でも発火するため無限ループに注意 | Windows Vista |
| `GetClipboardSequenceNumber()` | 変更検知用の連番取得 | なし | `DWORD` | **通知機構ではない。ポーリングループに使わない**（公式明記） | Windows 2000 |
| `SetClipboardViewer(hwnd)` / `ChangeClipboardChain` / `GetClipboardViewer` | 旧ビューアチェーン（**Out of scope・参考**） | `HWND` | `HWND` / `BOOL` | チェーン維持を誤ると通知断絶 | Windows 2000 |
| `WM_DRAWCLIPBOARD` / `WM_CHANGECBCHAIN` | 旧ビューアチェーン用メッセージ（**Out of scope・参考**） | - | - | 次ウィンドウへの転送漏れ | Windows 2000 |

### 遅延レンダリング

| API / メッセージ | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `SetClipboardData(fmt, NULL)` | 遅延レンダリングの予約 | フォーマット | `HANDLE` | 所有者でないと失敗。**成功時も `NULL` を返すため戻り値だけで成否判定できない**（後述の判定方法を使う） | Windows 2000 |
| `WM_RENDERFORMAT` | 要求時の実データ生成 | `wParam` = フォーマット | - | **応答内で `OpenClipboard` を呼んではならない**（公式明記）。未予約フォーマットが来た場合の扱いを定義しておく | Windows 2000 |
| `WM_RENDERALLFORMATS` | ウィンドウ破棄前の一括生成 | - | - | **「生成可能な全フォーマット」を配置する必要がある**（公式明記）。`OpenClipboard` し `GetClipboardOwner() == hwnd` を確認してから `SetClipboardData`、最後に `CloseClipboard`。**`EmptyClipboard` は呼んではならない**（既にレンダリング済みの形式が消えるため／公式明記）。**復帰後、未レンダリングの形式はシステムが一覧から削除する**（公式明記） | Windows 2000 |
| `WM_DESTROYCLIPBOARD` | 所有権喪失時の資源解放通知 | - | - | 私用フォーマットの解放漏れ | Windows 2000 |

**遅延レンダリングの状態管理（レビュー指摘反映）**

`WM_RENDERALLFORMATS` が「全ての遅延形式」を配置する契約であるため、**予約した形式と生成関数を Manager のインスタンス状態として保持する**。単一形式決め打ちの実装は契約違反になる。

- 予約時: `{ format, renderer }` を予約テーブルへ登録し、`SetClipboardData(format, NULL)` を発行
- `WM_RENDERFORMAT`: `wParam` の形式を予約テーブルから引く。**未登録なら何もしない**（他アプリの形式を誤って配置しない）。生成失敗・`SetClipboardData` 失敗はログとエラーカウンタへ反映
- `WM_RENDERALLFORMATS`: `OpenClipboard` → 所有者確認 → **予約テーブルの未生成分を全て走査して配置** → `CloseClipboard`。`EmptyClipboard` は呼ばない
- `WM_DESTROYCLIPBOARD`: 予約テーブルと生成用キャッシュを破棄（所有権喪失）
- 所有者喪失（`GetClipboardOwner() != hwnd`）を検知した場合は上書きせず終了する

**遅延レンダリング予約の成否判定（レビュー指摘反映）**

`SetClipboardData(fmt, NULL)` は成功時も `NULL` を返し、公式リファレンスにこのケースの成功値の定義がない。したがって戻り値のみでの判定は不可能である。次の組み合わせで判定する（実機での確認を要検証事項に含める）。

1. 呼び出し直前に `SetLastError(ERROR_SUCCESS)` を置き、呼び出し後の `GetLastError()` が `ERROR_SUCCESS` であること（直前の別 API の残存エラーに左右されないようにするため）
2. `GetClipboardOwner()` が自分の owner HWND と一致すること
3. `IsClipboardFormatAvailable(fmt)` が真であること

### 履歴 / クラウドクリップボード（WinRT）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `Clipboard::SetContent(dataPackage)` | 内容の設定 | `DataPackage` | `void` | フォアグラウンド要件 | Windows 10 1507 |
| `Clipboard::SetContentWithOptions(dataPackage, options)` | オプション付き設定（履歴 / 同期の可否） | `DataPackage`, `ClipboardContentOptions` | `bool` | 同上 | Windows 10 1809 |
| `Clipboard::GetContent()` | 内容の取得 | なし | `DataPackageView` | 同上 | Windows 10 1507 |
| `Clipboard::Clear()` | 全消去 | なし | `void` | 同上 | Windows 10 1507 |
| `Clipboard::Flush()` | アプリ終了後も内容を残す（`DataPackage` をソースから解放） | なし | `void` | 同上 | Windows 10 1507 |
| `Clipboard::ContentChanged` | 内容変更イベント | ハンドラ | `event_token` | 解除漏れでリーク | Windows 10 1507 |
| `Clipboard::IsHistoryEnabled()` | 履歴機能の有効判定 | なし | `bool` | なし | Windows 10 1809 |
| `Clipboard::IsRoamingEnabled()` | デバイス間同期の有効判定 | なし | `bool` | なし | Windows 10 1809 |
| `Clipboard::GetHistoryItemsAsync()` | 履歴一覧取得 | なし | `IAsyncOperation<ClipboardHistoryItemsResult>` | `Status` が `AccessDenied` / `ClipboardHistoryDisabled` | Windows 10 1809 |
| `Clipboard::SetHistoryItemAsContent(item)` | 履歴項目を現在の内容へ復元 | `ClipboardHistoryItem` | `SetHistoryItemAsContentStatus` | `AccessDenied` / `ItemDeleted` | Windows 10 1809 |
| `Clipboard::DeleteItemFromHistory(item)` | 履歴から 1 件削除 | `ClipboardHistoryItem` | `bool` | **公式は「成功時 `true`、それ以外 `false`」としか規定していない。`false` の原因は特定できない**ため、アクセス拒否と断定せず `UNKNOWN` として扱う | Windows 10 1809 |
| `Clipboard::ClearHistory()` | 履歴の消去。**pinned（固定）item は消去されない**（公式明記）ため「全消去」ではない | なし | `bool` | 同上。`false` の原因は特定できない | Windows 10 1809 |
| `Clipboard::HistoryChanged` | **履歴に新しい項目が追加された時**に発生（公式の定義）。削除・消去も通知される保証はない | ハンドラ | `event_token` | 解除漏れでリーク | Windows 10 1809 |
| `Clipboard::HistoryEnabledChanged` / `RoamingEnabledChanged` | 履歴 / 同期の OS 設定が変化した時に発生 | ハンドラ | `event_token` | 解除漏れでリーク | Windows 10 1809 |
| `ClipboardHistoryItem.Id` / `.Content` / `.Timestamp` | 履歴項目の ID / 内容（`DataPackageView`）/ 追加日時 | - | `hstring` / `DataPackageView` / `DateTime` | なし | Windows 10 1809 |
| `ClipboardHistoryItemsResult.Status` / `.Items` | 取得結果ステータス / 項目一覧 | - | enum / `IVectorView` | - | Windows 10 1809 |

列挙値:

- `ClipboardHistoryItemsResultStatus`: `Success`(0) / `AccessDenied`(1) / `ClipboardHistoryDisabled`(2)
- `SetHistoryItemAsContentStatus`: `Success`(0) / `AccessDenied`(1) / `ItemDeleted`(2)

### DataPackage / DataPackageView（WinRT）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `DataPackage()` | 生成 | なし | `DataPackage` | なし | Windows 10 1507 |
| `DataPackage.SetText(text)` | テキスト設定 | `hstring` | `void` | なし | Windows 10 1507 |
| `DataPackage.SetHtmlFormat(html)` | HTML 設定（`CF_HTML` 相当のヘッダ付き文字列） | `hstring` | `void` | ヘッダ不正で貼り付け先が解釈不能 | Windows 10 1507 |
| `DataPackage.SetRtf(rtf)` | RTF 設定 | `hstring` | `void` | なし | Windows 10 1507 |
| `DataPackage.SetBitmap(streamRef)` | 画像設定 | `RandomAccessStreamReference` | `void` | ストリーム不正 | Windows 10 1507 |
| `DataPackage.SetStorageItems(items[, readOnly])` | ファイル / フォルダ設定 | `IIterable<IStorageItem>`[, `bool`] | `void` | 権限なしのパス | Windows 10 1507 |
| `DataPackage.SetWebLink(uri)` / `SetApplicationLink(uri)` | リンク設定 | `Uri` | `void` | なし | Windows 10 1507 |
| `DataPackage.SetUri(uri)` | 旧 URI 設定（**非推奨**。`SetWebLink` / `SetApplicationLink` を使う） | `Uri` | `void` | - | Windows 10 1507 |
| `DataPackage.SetData(formatId, value)` | 任意フォーマット設定 | `hstring`, `IInspectable` | `void` | 受け側と形式合意が必要 | Windows 10 1507 |
| `DataPackage.SetDataProvider(formatId, handler)` | 遅延提供（**Out of scope**） | `hstring`, `DataProviderHandler` | `void` | **`DataProviderHandler` は Package Identity 必須**（未パッケージ不可） | Windows 10 1507 / MSIX |
| `DataPackage.RequestedOperation` | `Copy` / `Move`（カット）の指定 | `DataPackageOperation` | - | 未設定時は `None` | Windows 10 1507 |
| `DataPackage.Properties` | タイトル・説明等のメタデータ | - | `DataPackagePropertySet` | なし | Windows 10 1507 |
| `DataPackage.ResourceMap` | HTML 内参照リソース（画像等）の対応付け | - | `IMap` | なし | Windows 10 1507 |
| `DataPackage.GetView()` | 読み取り専用ビュー取得 | なし | `DataPackageView` | なし | Windows 10 1507 |
| `DataPackageView.Contains(formatId)` | フォーマット有無判定 | `hstring` | `bool` | なし | Windows 10 1507 |
| `DataPackageView.AvailableFormats` | 利用可能フォーマット一覧 | - | `IVectorView<hstring>` | なし | Windows 10 1507 |
| `DataPackageView.GetTextAsync()` / `GetHtmlFormatAsync()` / `GetRtfAsync()` / `GetBitmapAsync()` / `GetStorageItemsAsync()` / `GetWebLinkAsync()` / `GetApplicationLinkAsync()` / `GetDataAsync(formatId)` / `GetResourceMapAsync()` | 各形式の取得 | なし / `hstring` | `IAsyncOperation<...>` | 該当形式がないと例外。**STA でのブロッキング `get()` 不可** | Windows 10 1507 |
| `DataPackageView.GetUriAsync()` | 旧 URI 取得（**非推奨**） | なし | `IAsyncOperation<Uri>` | - | Windows 10 1507 |
| `DataPackageView.RequestedOperation` | 要求操作（`Copy` / `Move`）の取得 | - | `DataPackageOperation` | なし | Windows 10 1507 |
| `DataPackageView.ReportOperationCompleted(op)` | カット（`Move`）完了の通知 | `DataPackageOperation` | `void` | 未通知だとソース側が元データを削除できない | Windows 10 1507 |
| `DataPackageView.SetAcceptedFormatId(formatId)` | 受理フォーマットの指定 | `hstring` | `void` | なし | Windows 10 1511 |
| `DataPackageView.RequestAccessAsync()` / `UnlockAndAssumeEnterpriseIdentity()` | EDP 保護データの解錠（**Out of scope**） | - | - | - | Windows 10 1507 |
| `StandardDataFormats::Text()` / `Html()` / `Rtf()` / `Bitmap()` / `StorageItems()` / `WebLink()` / `ApplicationLink()` / `UserActivityJsonArray()` | 標準フォーマット ID | - | `hstring` | なし | Windows 10 1507 |
| `HtmlFormatHelper::CreateHtmlFormat(htmlFragment)` / `GetStaticFragment(htmlFormat)` | `CF_HTML` ヘッダの生成 / フラグメント抽出 | `hstring` | `hstring` | 不正な HTML 文字列 | Windows 10 1507 |

### プライバシー / 履歴・同期の除外

| API / フォーマット | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `ExcludeClipboardContentFromMonitorProcessing`（登録フォーマット） | **全フォーマット**を履歴・デバイス間同期の対象外にする | 任意データ（存在自体が指示） | - | 登録名の綴り誤りで無効 | Windows 10 1809 |
| `CanIncludeInClipboardHistory`（登録フォーマット） | 履歴への包含可否。`DWORD` 0 = 除外 / 1 = 明示的に含める。同期には影響しない | シリアライズ済み `DWORD` | - | サイズ / 型誤りで無効 | Windows 10 1809 |
| `CanUploadToCloudClipboard`（登録フォーマット） | クラウド同期の可否。`DWORD` 0 = 除外 / 1 = 明示的に同期。履歴には影響しない | シリアライズ済み `DWORD` | - | 同上 | Windows 10 1809 |
| `ClipboardContentOptions.IsAllowedInHistory` | WinRT 版の履歴包含可否 | `bool` | - | - | Windows 10 1809 |
| `ClipboardContentOptions.IsRoamable` | WinRT 版の同期可否 | `bool` | - | - | Windows 10 1809 |
| `ClipboardContentOptions.HistoryFormats` / `RoamingFormats` | 履歴 / 同期の対象フォーマットを個別指定 | `IVector<hstring>` | - | - | Windows 10 1809 |

参照: [Clipboard Formats – Cloud Clipboard and Clipboard History Formats](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard-formats)

### Out of scope の通知メッセージ（存在のみ記載）

`CF_OWNERDISPLAY` を採用する場合にのみ必要となる通知。native-toolkit では実装対象外。

| メッセージ | 目的 |
|---|---|
| `WM_ASKCBFORMATNAME` | ビューアがオーナー表示フォーマット名を問い合わせる |
| `WM_PAINTCLIPBOARD` | ビューアのクライアント領域の再描画要求 |
| `WM_SIZECLIPBOARD` | ビューアのサイズ変更 / 内容変更の通知 |
| `WM_HSCROLLCLIPBOARD` / `WM_VSCROLLCLIPBOARD` | ビューアのスクロールバーイベント |
| `WM_CLEAR` / `WM_COPY` / `WM_CUT` / `WM_PASTE` | エディットコントロール / コンボボックス向けの標準編集メッセージ |

参照: [Clipboard（関数・メッセージ一覧）](https://learn.microsoft.com/en-us/windows/win32/dataxchg/clipboard)

---

## Domain エラー対応表（設計書へ引き継ぐ）

Win32 / WinRT の失敗をツールキットの公開エラーコードへ正規化する。値は設計工程で確定するが、種別は以下を最低限カバーする。

| Domain エラー（案） | 発生源 | ネイティブの現れ方 | 備考 |
|---|---|---|---|
| `CLIPBOARD_ERROR_NONE` (0) | - | 成功 | |
| `CLIPBOARD_ERROR_BUSY` | Win32 | `OpenClipboard` が `FALSE`（リトライ上限到達） | 他プロセスが排他保持中。**特定の `GetLastError` 値は公式に規定がないため断定せず、生の値をログへ保持する** |
| `CLIPBOARD_ERROR_EMPTY` | Win32 / WinRT | `IsClipboardFormatAvailable` が偽 / `CountClipboardFormats() == 0` / `Contains` が偽 | 空、または要求形式が存在しない |
| `CLIPBOARD_ERROR_FORMAT_UNAVAILABLE` | Win32 / WinRT | `GetClipboardData` が `NULL`（形式不一致） | `EMPTY` と分けるかは設計判断 |
| `CLIPBOARD_ERROR_OUT_OF_MEMORY` | Win32 | `GlobalAlloc` / `GlobalLock` が `NULL` | |
| `CLIPBOARD_ERROR_INVALID_ARGUMENT` | 自実装 | owner HWND が `NULL`、空パス配列、サイズ 0 等 | API 契約違反 |
| `CLIPBOARD_ERROR_INVALID_DATA` | 自実装 | 境界検証（終端 NUL / サイズ / オフセット / オーバーフロー）失敗 | 信頼できない外部入力に対する防御 |
| `CLIPBOARD_ERROR_ACCESS_DENIED` | WinRT | `ClipboardHistoryItemsResultStatus::AccessDenied` / `SetHistoryItemAsContentStatus::AccessDenied` | **明示的に `AccessDenied` を返す API のみ**。`bool` を返す API の `false` はここに含めない |
| `CLIPBOARD_ERROR_HISTORY_DISABLED` | WinRT | `ClipboardHistoryItemsResultStatus::ClipboardHistoryDisabled` / `IsHistoryEnabled() == false` | ユーザー設定で無効 |
| `CLIPBOARD_ERROR_ITEM_DELETED` | WinRT | `SetHistoryItemAsContentStatus::ItemDeleted` | 復元対象が既に削除済み |
| `CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED` | Win32 | `AddClipboardFormatListener` / `RemoveClipboardFormatListener` が `FALSE`、監視ウィンドウ生成失敗 | |
| `CLIPBOARD_ERROR_NOT_SUPPORTED` | 自実装 | Android の Intent クリップ等、Windows に等価概念がない操作 | クロスプラットフォーム API の穴埋め |
| `CLIPBOARD_ERROR_PARTIAL_STATE` | Win32 | 複数形式配置の失敗後、ロールバック用 `EmptyClipboard` も失敗した | **クリップボードに一部の形式が残っている可能性**を呼び出し側へ伝える |
| `CLIPBOARD_ERROR_UNKNOWN` | Win32 / WinRT | 上記に該当しない `GetLastError` / `HRESULT` / `winrt::hresult_error`、および **`DeleteItemFromHistory` / `ClearHistory` / `SetContentWithOptions` の `false`**（公式が原因を規定していないため） | **生の値をログに残し、握り潰さない** |

---

## プロジェクト設定要件（Windows 固有）

### NuGet パッケージ

| パッケージ | 用途 | 要否 | 備考 |
|---|---|---|---|
| `Microsoft.Windows.CppWinRT` | C++/WinRT プロジェクション生成 | WinRT（履歴機能）を使う場合に必須 | 既に `WindowsLibrary` で導入済み |
| `Microsoft.WindowsAppSDK`（1.7.250513003） | 通知機能で導入済み | **クリップボードには不要** | `DataTransfer` は OS 提供の Windows SDK WinRT。App SDK 依存を新たに増やさない |
| （追加不要） | Win32 クリップボード API | - | `winuser.h` / `shellapi.h` は Windows SDK 標準 |

方針: **クリップボード機能で新規 NuGet パッケージの追加は不要**。

### コンパイラ / プロジェクト設定

| 設定 | 値 | 理由 |
|---|---|---|
| C++ 言語標準（Win32 コア） | `/std:c++17` | 同期 Win32 API と純ロジック |
| C++ 言語標準（WinRT 履歴） | `/std:c++20` | UI スレッドで `co_await` する確定方針 |
| 文字セット | Unicode（`UNICODE` / `_UNICODE`） | `CF_UNICODETEXT` / `wchar_t` API 前提 |
| ソース文字コード | UTF-8 BOM 付き または `/utf-8` | 非 ASCII を含む場合の文字化け防止（`agent-rules/coding-rules/windows.md`） |
| 追加ヘッダ（Win32） | `<shellapi.h>`（`DragQueryFile`）, `<shlobj_core.h>`（`DROPFILES`） | pch には入れず、使用 `.cpp` 側で include する |
| 追加ヘッダ（WinRT） | `<winrt/Windows.ApplicationModel.DataTransfer.h>` | 履歴機能を使う場合のみ pch へ追加 |
| `/await` | **使用しない** | 非推奨のコンパイラ拡張。WinRT 履歴は `/std:c++20` の標準コルーチンを使う |

参照: [Call Windows Runtime APIs in desktop apps](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-apis-desktop-apps)

### MFC × C++/WinRT 共存時のヘッダインクルード順序

既存 `windows/WindowsLibrary/pch.h` の方針を踏襲する。

```cpp
#include "framework.h"   // 1. MFC (afxwin.h 等) を必ず最初に
#include <winrt/base.h>  // 2. WinRT base は MFC の後
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
// 3. 機能別 WinRT ヘッダ
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
```

注意点:

- MFC ヘッダより先に `winrt/base.h` を入れると、`new` の再定義（MFC の `DEBUG_NEW`）や `min` / `max` マクロ衝突でコンパイルエラーになる。順序を崩さない。
- Win32 クリップボード API（`winuser.h`）は `framework.h` 経由で入るため追加インクルード不要。
- 単体テストが対象 `.cpp` をコンパイルする構成のため、WinRT 依存を持たない Win32 コア実装ファイルには WinRT ヘッダを持ち込まない（通知機能で Bootstrap ヘッダを pch から外したのと同じ方針）。

---

## Package Identity 別の対応方針

| 機能 | MSIX（パッケージ済み） | 未パッケージ Win32 | 管理者権限実行 |
|---|---|---|---|
| Win32 コピー / ペースト / クリア / 内容確認 | 可 | 可 | 可 |
| Win32 変更監視（`AddClipboardFormatListener`） | 可 | 可 | 要検証（UIPI により低整合性プロセスからの通知が届くか） |
| Win32 遅延レンダリング | 可 | 可 | 可 |
| 履歴 / 同期の除外フォーマット | 可 | 可 | 可 |
| WinRT `Clipboard`（Set/Get/Clear/Flush/ContentChanged） | 可 | 可（Package Identity 不要。公式の identity 必須一覧に含まれない） | 要検証 |
| WinRT 履歴 API（`GetHistoryItemsAsync` 等） | 可 | 可（同上。ユーザー設定で履歴が無効なら `ClipboardHistoryDisabled`） | 要検証 |
| WinRT `DataPackage.SetDataProvider`（`DataProviderHandler`） | 可 | **不可**（Package Identity 必須 API） | - |
| `DataTransferManager` 系（共有 UI） | 可 | 不可（`IDataTransferManagerInterop` が必要） | - |

方針:

- 未パッケージでも全コア機能が動くよう、**遅延提供が必要な場面では WinRT `SetDataProvider` ではなく Win32 の遅延レンダリングを使う。**
- 通知機能のような `initWinAppSdk`（`MddBootstrapInitialize`）相当の初期化は**不要**。クリップボードは Windows App SDK に依存しない。
- パッケージ済み / 未パッケージで分岐する実装は原則不要。

参照: [WinRT APIs not supported in desktop apps – APIs that require package identity](https://learn.microsoft.com/en-us/windows/apps/desktop/modernize/winrt-api-desktop-app-support)

---

## 実装リスク（権限・制約・互換性）

| リスク | 詳細 | 対策 |
|---|---|---|
| クリップボードの排他失敗 | `OpenClipboard` は他ウィンドウが開いている間失敗する。**失敗時のエラーコードは公式に規定がない**（`GetLastError` で確認せよ、とのみ記載） | RAII でオープン / クローズを対にし、短時間リトライしてから `BUSY` へ正規化。`GetLastError` の生値はログに残し、未知の値も保持できる設計にする |
| owner HWND が `NULL` | `OpenClipboard(NULL)` の後 `EmptyClipboard` を呼ぶと所有者が `NULL` になり `SetClipboardData` が失敗する（公式明記） | 書き込み・遅延レンダリング・監視では有効な HWND を必須とし、`NULL` は `INVALID_ARGUMENT` で拒否する。読み取りのみ `NULL` を許容 |
| ハンドル所有権の誤り | `SetClipboardData` 成功後にハンドルを `GlobalFree` するとクラッシュ / 破損。`GetClipboardData` の戻り値を解放・ロック放置するのも不可 | RAII（`GlobalMem` / `GlobalLockScope`）で「成功時のみ `Release()` して所有権を手放す」形に強制する |
| `GlobalAlloc` / `GlobalLock` / `RegisterClipboardFormat` の失敗未確認 | メモリ不足時に `NULL` 参照、フォーマット ID 0 での `SetClipboardData` 失敗 | 全ての確保・ロック・登録 API の戻り値を確認し、失敗を Domain エラーへ正規化する |
| クローズ漏れ | `CloseClipboard` 忘れで他アプリのクリップボード操作を阻害 | RAII（デストラクタで `CloseClipboard`）を必須とする |
| 信頼できない外部入力 | 他プロセスが供給したデータに終端 NUL がない / サイズやオフセットが不正 / 加算オーバーフロー | 上記「境界検証規則」を全読み取りパスに適用し、失敗系の単体テストを用意する |
| 遅延レンダリング予約の成否判定 | `SetClipboardData(fmt, NULL)` は成功時も `NULL` を返し、公式に成功値の定義がない | `SetLastError(ERROR_SUCCESS)` + `GetClipboardOwner` + `IsClipboardFormatAvailable` の組み合わせで判定。実挙動は要検証 |
| WinRT のフォアグラウンド要件と STA 制約の衝突 | `Clipboard` は「UI スレッドでフォーカスがある時のみアクセス可能」（公式 Remarks）だが、`IAsyncOperation::get()` を STA で呼ぶと cppwinrt が assert する。MTA ワーカーへ移すと UI スレッド要件を満たさない | UI スレッドで開始し `co_await` で非ブロッキング待機する。履歴の公開 Bridge は callback 方式に固定し、MTA ワーカー + `wait_for` は採用しない |
| アパートメント初期化の副作用 | `DllMain` / `InitInstance` でアパートメントを固定すると、ホストが後から `init_apartment(single_threaded)` を呼んだ際に `RPC_E_CHANGED_MODE` でクラッシュする（既存コードのコメント参照） | ホスト所有 UI スレッドのアパートメントを変更しない。toolkit が専用 UI スレッドを作る場合だけ、そのスレッド内で `init_apartment(single_threaded)` / `uninit_apartment()` を対にする |
| WinRT 例外の取りこぼし | `co_await` / `get()` / イベント登録は `winrt::hresult_error` を投げる | Bridge 境界の共通ラッパ（`InvokeWinRt`）で捕捉し、既知 HRESULT は Domain エラーへ、未知値は生の HRESULT をログに残して `UNKNOWN` へ正規化する |
| `ClearHistory` の pinned item | **`ClearHistory` は pinned（固定）item を消去しない**（公式明記）。「全消去」と表現すると実挙動と食い違う | 公開 API 名・マニュアル文言を「未固定項目の消去」とする。呼び出し後も履歴が残り得ることを DoD で確認する |
| 履歴 API の `bool` 戻り値 | `DeleteItemFromHistory` / `ClearHistory` の `false` は「成功しなかった」以上の情報を持たない（公式に理由の規定なし） | アクセス拒否と断定せず `UNKNOWN` へ正規化する |
| `HistoryChanged` の発火範囲 | 公式の定義は「**新しい項目が履歴に追加された時**」。削除・消去で発火する保証はない | 自身の削除・消去操作の後は、イベントに頼らず明示的に `GetHistoryItemsAsync` で再取得する |
| イベント購読の多重登録 | `Start` を二重に呼ぶと以前の `event_token` を失い、解除できないハンドラが残る | 開始済みフラグで冪等化する（登録途中の失敗・解除失敗については後述の行を参照） |
| 変更監視に HWND が必要 | `AddClipboardFormatListener` は HWND 必須。DLL 単体では所有ウィンドウがない | 監視用のメッセージ専用ウィンドウ（`HWND_MESSAGE`）を Manager が生成・所有する。届くかは要検証 |
| 監視状態のグローバル共有 | シーケンス番号や登録状態を `static` に持つと複数 Manager / 複数スレッドで競合する | シーケンス番号・登録状態は Manager（ウィンドウ）インスタンスの状態として保持する。インスタンスはメッセージを処理するスレッドに固定する |
| 監視解除失敗時の状態不整合 | `RemoveClipboardFormatListener` 失敗時に登録状態をクリアすると、実際には登録が残ったまま再試行不能になり、破棄後のウィンドウへ通知が来る | 解除成功時のみ状態をクリアし、失敗時は登録状態を保持して再試行可能にする。解除成功を確認するまでウィンドウを破棄しないライフサイクルにする |
| 遅延レンダリングの形式取りこぼし | `WM_RENDERALLFORMATS` は「生成可能な全形式」を配置する契約（公式明記）。単一形式決め打ちの実装では予約した他の形式が失われる | 予約形式と生成関数を Manager のインスタンス状態（予約テーブル）で管理し、未生成分を全て走査して配置する。`WM_RENDERFORMAT` で未登録形式が来た場合は何もしない |
| `WM_RENDERALLFORMATS` 内の `EmptyClipboard` | 呼ぶとレンダリング済みの形式が消える（公式明記） | この応答内では `EmptyClipboard` を呼ばない。復帰後に未レンダリング形式はシステムが一覧から削除する |
| 書き込み時のサイズ計算オーバーフロー | `(size + 1) * sizeof(wchar_t)`、パス長の総和、`size_t` → `int` 変換で桁あふれし得る | 共通の checked 演算（`CheckedAdd` / `CheckedMul` / `CheckedToInt`）を全ての確保サイズ計算に通す |
| 複数フォーマット配置の部分成功 | 途中の形式で失敗すると、既に置いた形式だけがクリップボードに残る。**ロールバック用 `EmptyClipboard` 自体も失敗し得るため原子的保証はできない** | 全ペイロードを `EmptyClipboard` 前に構築・確保し（失敗確率を下げる）、配置失敗時は再度 `EmptyClipboard`。ロールバックも失敗したら `PARTIAL_STATE` を返す。契約を「best-effort rollback」と明記する |
| 遅延予約の途中失敗 | 複数形式の予約途中で失敗すると、そこまでの遅延形式がクリップボードに残る一方、予約テーブルが未保存だと `WM_RENDERFORMAT` に応答できない | 予約テーブルを**先に**インスタンスへ保持する。途中失敗時は同じ Open/Close 区間で `EmptyClipboard` して取り消し、**成功したときのみ**テーブルをクリアする |
| 遅延予約のロールバック失敗 | ロールバック用 `EmptyClipboard` も失敗すると残存形式があり得る。ここでテーブルを破棄すると、残った予約の `WM_RENDERFORMAT` に応答できずデータが失われる | `Reserve` は Domain 結果を返し、ロールバック失敗時は `PARTIAL_STATE` を返して**テーブルを保持**する。`RecoverFromPartialState()`（所有者確認 + 再 `EmptyClipboard`）か `WM_DESTROYCLIPBOARD` で初めて解放する |
| コールバックの例外・二重呼び出し・失効 | `fire_and_forget` の未処理例外はプロセス終了につながる。`Uninit` 後やキャンセル後の完了でコールバックが呼ばれると不正アクセスになる | コールバック呼び出しも `try/catch` で囲む。pending テーブルからの**アトミックな取り出し**で一回限りを保証し、`Uninit` はテーブルをドレインしてから破棄する。C ABI コールバックは例外を投げてはならない契約を公開 API に明記する |
| `PostMessage` 失敗時の要求オブジェクトリーク | 「所有権は受信側へ移る」前提だけでは、投入失敗時に誰も解放しない | 所有権は **`PostMessage` 成功の瞬間**に移るものとし、失敗時は呼び出しスレッドが pending テーブルから取り出して即座に解放する |
| `CF_HTML` の既知キー重複 | 重複検出の戻り値を無視すると「重複キーを拒否する」契約を満たさない | 行のキーを先に識別し、既知キーの解析結果を必ず伝播する。未知キーのみ明示的に無視する |
| `CF_HTML` ヘッダ範囲の推定 | 「`<` で始まる行」等の形状推定では、HTML 本文の先頭形状によって本文をヘッダとして走査し得る | 数値の `StartHTML` が得られた時点で**その位置をヘッダ範囲の上限**として確定する。範囲外に現れた既知キーは無視されることをテストする |
| `BuildCfHtml` のマーカー探索 | 入力フラグメント自身が `<!--EndFragment-->` を含むと、探索が入力内のマーカーに一致してフラグメントが途中で切れる | マーカーを検索せず、**固定 prefix 長と入力サイズから** checked arithmetic で Start / End を直接計算する |
| 遅延 Renderer の解放方法 | `CF_BITMAP` / メタファイル / GDI オブジェクトは `GlobalFree` では解放できない。任意形式を受け入れる Renderer 契約は危険 | 遅延レンダリングの対象を **`HGLOBAL` 形式に限定**し、戻り値型（`GlobalMem`）で強制する。形式別 deleter が必要なら Renderer の戻り値に deleter を持たせる |
| 非同期例外の取りこぼし | `co_await` 後に発生した例外は非同期オブジェクトに格納され、**同期ラッパでは捕捉できない** | 例外は発生し得る非同期処理と**同じコルーチン内**で捕捉する（公式ガイダンス）。非同期用ラッパ（`InvokeWinRtAsync`）を用意し、Bridge の ABI 境界は `noexcept` + `fire_and_forget` にする |
| `std::bad_alloc` の取りこぼし | C++/WinRT では `E_OUTOFMEMORY` が **`std::bad_alloc`** として送出される（公式明記）ため、`hresult_error` だけを捕捉すると `OUT_OF_MEMORY` に分類できない | 共通分類関数で `std::bad_alloc` を明示的に捕捉する。全 WinRT 公開境界で同じ分類関数を通す |
| 履歴ステータスの誤分類 | 呼び出し箇所ごとに `ClipboardHistoryItemsResultStatus` を独自変換すると `AccessDenied` を `HISTORY_DISABLED` に潰す等の不整合が起きる | `MapHistoryStatus` / `MapSetHistoryItemStatus` の共通変換関数を全呼び出し箇所で使う |
| 非 UI スレッドからの Bridge 呼び出し | Unity / ネイティブの任意スレッドから呼ばれるが、WinRT `Clipboard` は UI スレッド + フォーカスを要求する | Bridge 入口で UI スレッド判定を行い、非 UI スレッドなら所有ウィンドウへ `PostMessage`（`SendMessage` はデッドロックし得るため使わない）で配送する。完了コールバックのスレッドを公開 API に明記する |
| メッセージポンプ不在 | WinRT 履歴の `PostMessage` 配送に加え、**Win32 の遅延レンダリング（`WM_RENDERFORMAT` / `WM_RENDERALLFORMATS`）と変更監視（`WM_CLIPBOARDUPDATE`）も所有 `HWND` のスレッドに届く**。Win32 コアの Bridge が同期形式でも、そのスレッドがメッセージポンプを回していないとこれらの機能は動作しない | 監視・所有用ウィンドウを toolkit 側で作る場合は専用スレッド + メッセージループを持たせるかを設計で決める |
| イベント登録の途中失敗 | 3 つのイベント登録の途中で例外が出ると、登録済みトークンが解除されないまま残る。デストラクタから解除する場合、解除例外がデストラクタ境界を越える危険もある | 登録は段階的に行い、途中失敗時は `catch` 内で**取得済みトークンを明示解除**して巻き戻す。`Stop` / デストラクタは `noexcept` を維持し、解除失敗はログに残す |
| イベント解除の途中失敗 | 最初の `revoke()` が例外を投げると後続が実行されず、「`Stop` 完了 = 全解除済み」の契約が崩れる | 各 revoker を**個別に** try/catch して全件の解除を試み、失敗の有無を戻り値で集約して shutdown gate へ伝える |
| 解除失敗後の再登録 | 一部の解除に失敗しているのに停止状態へ遷移すると、生き残ったハンドラの上に新しいハンドラを重ねて登録してしまう | 全件成功時のみ停止状態へ遷移する。未完了の間は `revokePending_` 状態を保持し、**その間の `Start()` を拒否**して `Stop()` の再試行を促す |
| `auto_revoke` では解除失敗を観測できない | `winrt::event_revoker::revoke()` は **`void revoke() noexcept`**（公式シグネチャ）であり、戻り値も例外も返さない。`auto_revoke` を使う限り「解除成功を確認してから破棄する」shutdown gate は実装できない | **`auto_revoke` を採用せず `event_token` を保持**し、`Clipboard::HistoryChanged(token)` 等で明示解除する。明示解除は ABI を越えるため失敗を例外として観測でき、成功したトークンのみクリアして再試行可能にする |
| 解除後の in-flight コールバック | 解除後（デストラクタ実行中を含む）でも進行中のコールバックが到着し得る（公式ガイダンス）。ハンドラが `this` を捕捉していると use-after-free になる | ハンドラは `this` を直接捕捉せず、weak reference / 世代番号 / 共有ライフサイクル状態を経由する。`Stop()` で世代を無効化し、以降のコールバックを no-op にする |
| サンプルの言語規格混在 | Win32 コアは C++17 で足りるが、`co_await` を使う WinRT サンプルは `/std:c++20` が必要 | 前提表で「Win32 コア = C++17 / WinRT コルーチン版 = C++20」と明示する。標準コルーチンを使わない場合も、UI スレッド上の `Completed` handler 版で非同期 Bridge を維持する |
| `RecoverFromPartialState` の引数信頼 | 呼び出し側から任意の HWND を受け取ると、実際の所有者と異なる HWND を渡された際に「他アプリが所有」と誤判定し、残存形式に必要な Renderer テーブルを破棄してしまう | 引数を廃止し、保存済み `owner_` のみを権威とする。テーブルの破棄は `EmptyClipboard` 成功時か `WM_DESTROYCLIPBOARD` による所有権喪失確認後に限る |
| 非同期ヘルパの戻り値型不一致 | 公開 Bridge から到達する非同期ヘルパが `uint32_t` と `ClipboardResult<T>` で混在すると、共通ラッパに渡せずコンパイルできない | 公開 Bridge から到達する全非同期ヘルパを `IAsyncOperation<ClipboardResult<T>>`（ペイロードなしは `ClipboardStatus`）に統一する |
| `CF_HTML` の `Version` 未検証 | 値が空でも任意文字列でも受理すると、CF_HTML でないデータを解析してしまう | 定義済みの `0.9` / `1.0` のみ受理し、空値・不明値は拒否する。将来版を許容する場合は方針とテストを明記する |
| `CF_HTML` ヘッダ終端の未検証 | 数値 `StartHTML` を走査上限に使うだけでは、キー順を変えた入力で `StartHTML` がヘッダ内を指してもオフセット順序だけで通ってしまう | ヘッダ終端位置を追跡し、**数値 `StartHTML` がヘッダ終端と一致する**ことを検証する |
| 監視ウィンドウの破棄順序 | `Stop` が失敗しているのにウィンドウを破棄すると、破棄済み HWND へ通知が届く | 終了シーケンス（shutdown gate）を Manager に実装する。新規受付停止 → pending ドレイン → `Stop` 成功確認 → `PARTIAL_STATE` の回復 → `DestroyWindow` の順を守り、`Stop` 成功前の `DestroyWindow` を禁止する |
| 公開境界のラッパ通過漏れ | 一部の WinRT 関数がラッパを経由しないと、エラー契約に穴ができる | 公開 Bridge から見える WinRT 操作は `ClipboardResult<T>`（Domain エラー + ペイロード）に統一し、同期は `InvokeWinRt`、非同期は `InvokeWinRtAsync` を必ず通す |
| 列挙 API の 0 の多義性 | `CountClipboardFormats` は**失敗時も 0**、`EnumClipboardFormats` の 0 は**列挙終了と失敗の両方**を意味する（終了時のみ `GetLastError` が `ERROR_SUCCESS`／公式明記） | 呼び出し直前に `SetLastError(ERROR_SUCCESS)` を置き、0 返却時は `GetLastError` で空／終了／失敗を弁別する。列挙途中で失敗したら部分結果を破棄して Domain エラーを返す |
| `GetUpdatedClipboardFormats` のバッファ不足時挙動 | 公式は「失敗時 `FALSE`、`GetLastError` を参照」としか規定しておらず、**バッファ不足時に `pcFormatsOut` が必要件数を返すという保証はない** | `CountClipboardFormats` から余裕を持ったサイズを確保し、失敗時は `EnumClipboardFormats` へフォールバックする。実挙動は要検証 |
| 自プロセス変更による通知ループ | 自分の `SetClipboardData` でも `WM_CLIPBOARDUPDATE` が発火する | 書き込み直後の `GetClipboardSequenceNumber` をインスタンスに記録し、一致する通知を抑止する |
| リスナー解放漏れ | `RemoveClipboardFormatListener` を呼ばずにウィンドウ破棄するとリーク | `Uninit` / `WM_DESTROY` で必ず解除し、戻り値をログ・Domain エラーへ反映する |
| シーケンス番号のポーリング誤用 | `GetClipboardSequenceNumber` は通知機構ではない（公式明記） | ポーリングループに使わない。キャッシュ有効性検証と自己起因判定のみに使う |
| 遅延レンダリング中の `OpenClipboard` | `WM_RENDERFORMAT` 応答内で `OpenClipboard` を呼ぶと不正（公式明記） | `WM_RENDERFORMAT` では直接 `SetClipboardData`。`WM_RENDERALLFORMATS` のみ `OpenClipboard` + 所有者確認を行う |
| 私用フォーマットのリーク | `CF_PRIVATEFIRST`〜`CF_PRIVATELAST` はシステムが解放しない | `WM_DESTROYCLIPBOARD` で解放する。可能なら登録フォーマットを使う |
| `CF_HTML` の文字コード | `CF_HTML` は Windows API では例外的に **UTF-8**。UTF-16 で書くと壊れる | UTF-8 変換とバイト単位のオフセット計算を専用ユーティリティに集約し、単体テストを書く |
| `CF_HTML` のオフセット計算 | ヘッダのオフセットはバイト単位。誤ると貼り付け先が解釈不能 | 10 桁ゼロ埋めで書き出してから確定値で上書きする公式推奨手法を採る。`Version:1.0` を使う。オフセット計算は `CheckedAdd` / `CheckedToInt` を通す |
| `CF_HTML` ヘッダ解析の甘さ | ペイロード全体を `find` すると HTML 本文中の同名文字列を拾う。値の完全消費を確認しないと `-10` / `123x` を受理する | ヘッダ行（CRLF / LF / CR 区切り）のみを走査し、キーの完全一致・値全体の完全消費・重複キー拒否を行う。必須キー（`StartFragment` / `EndFragment`）の欠落は拒否する |
| `CF_HDROP` の構造 | `DROPFILES` + ダブル NUL 終端のパス列。`fWide` 不一致で受け側が誤読 | Unicode ビルド前提で `fWide = TRUE` 固定。終端の二重 NUL をユーティリティで保証する |
| `DragQueryFile` のバッファ長 | 「NUL を除く長さ」が返るため、`len` ちょうどのバッファでは溢れる | `len + 1` を確保して呼び、その後に長さを詰める |
| 画像フォーマットの選択 | `CF_BITMAP` はシステムパレット依存。公式は `CF_DIB` / `CF_DIBV5` 推奨 | コピー時は `CF_DIB` または `CF_DIBV5` を配置。合成により `CF_BITMAP` 要求にも応答できる |
| 履歴機能の無効・拒否 | ユーザー設定で履歴 / 同期が無効な場合がある | `IsHistoryEnabled()` / `IsRoamingEnabled()` を事前確認し、`Status` を Domain エラーへ正規化 |
| 機微情報の履歴残存 | パスワード等が履歴 / クラウドに残る | 除外フォーマットを同一の Open〜Close 内で配置。WinRT 経由なら `ClipboardContentOptions` |
| `Flush()` の副作用 | `Clipboard::Flush()` はアプリ終了後も内容を残す | 実データを即時配置する実装ならプロセス終了後も内容は残るため、`Flush` の明示呼び出しは通常不要（要検証） |
| セキュリティ全般 | 公式が「クリップボードを機微データの転送に使うべきでない」と明記 | 機微データのコピー API では除外フォーマット付与を既定にし、マニュアルに注意書きを載せる |
| MFC × WinRT のヘッダ順序 | 順序を崩すとコンパイルエラー | `pch.h` の既存順序を厳守 |

---

## 簡単なサンプルコード集（サブ機能別）

### サンプルコードの前提

| 項目 | 内容 |
|---|---|
| 文字セット | Unicode ビルド（`UNICODE` / `_UNICODE`） |
| 言語規格（Win32 コア） | **C++17**。「RAII ユーティリティ」〜「変更監視」「遅延レンダリング」までの Win32 サンプルは C++17 でビルドできる |
| 言語規格（WinRT コルーチン版） | **`/std:c++20`**。`co_await` / `co_return` を使う WinRT サンプル（`InvokeWinRtAsync`・履歴 API・`fire_and_forget`）は C++20 が必要。標準コルーチンを使わない実装へ変更する場合も、UI スレッド上の `IAsyncOperation::Completed` handler で同じ非同期 callback Bridge を維持する |
| 宣言順 | 掲載順は説明の都合で前後する。`RunHistoryRequest` は後述の `RestoreLatestHistoryItemAsync` を使うため、**実装時は前方宣言するか定義順を入れ替える** |
| ログ | `DLog` / `DFLog` は紙面の都合で一部省略。実装時は `agent-rules/coding-rules/windows.md` に従い全メソッド先頭に入れる |
| ビルド確認 | **本書の掲載コードはコンパイル確認をしていない。** 実装工程で 1 つの検証用翻訳単位としてビルドする（D-29 / 要検証事項） |

必要なヘッダ（掲載コード全体を 1 つの翻訳単位にまとめる場合）:

```cpp
// Win32
#include <windows.h>        // clipboard API, GlobalAlloc/Lock, SetLastError
#include <shellapi.h>       // DragQueryFileW
#include <shlobj_core.h>    // DROPFILES

// C++ standard
#include <string>           // std::string / std::wstring
#include <vector>           // std::vector
#include <map>              // std::map (deferred renderer table)
#include <set>              // std::set (rendered formats)
#include <functional>       // std::function
#include <variant>          // std::monostate (ClipboardStatus)
#include <utility>          // std::forward / std::move
#include <new>              // std::bad_alloc
#include <memory>           // std::shared_ptr / std::weak_ptr (event lifetime state)
#include <atomic>           // atomic gate / in-flight callback counter (C++20 wait/notify)
#include <cstdint>          // uint64_t
#include <climits>          // INT_MAX / UINT_MAX (checked narrowing)
#include <cstdio>           // sprintf_s
#include <cstring>          // memcpy / strnlen / strlen

// C++/WinRT (MFC headers must come first — see pch.h ordering)
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
```

### RAII ユーティリティ（共通）

```cpp
#include <windows.h>
#include <string>
#include <vector>

// Opens the clipboard with a bounded retry: another process may hold it briefly.
// The exact GetLastError value on contention is not specified by the docs, so it is
// only logged, never used as a control-flow condition.
class ClipboardScope
{
public:
    explicit ClipboardScope(HWND owner)
    {
        for (int i = 0; i < 10 && !opened_; ++i)
        {
            opened_ = (::OpenClipboard(owner) != FALSE);
            if (!opened_) ::Sleep(10);
        }
    }
    ~ClipboardScope() { if (opened_) ::CloseClipboard(); }
    ClipboardScope(const ClipboardScope&) = delete;
    ClipboardScope& operator=(const ClipboardScope&) = delete;
    bool IsOpen() const { return opened_; }

private:
    bool opened_ = false;
};

// Owns an HGLOBAL until it is handed to the clipboard. Release() is called only
// after SetClipboardData succeeds, because ownership then moves to the system.
class GlobalMem
{
public:
    explicit GlobalMem(SIZE_T bytes) : h_(::GlobalAlloc(GMEM_MOVEABLE, bytes)) {}
    ~GlobalMem() { if (h_) ::GlobalFree(h_); }
    GlobalMem(const GlobalMem&) = delete;
    GlobalMem& operator=(const GlobalMem&) = delete;
    bool IsValid() const { return h_ != nullptr; }
    HGLOBAL Get() const { return h_; }
    HGLOBAL Release() { HGLOBAL h = h_; h_ = nullptr; return h; }

private:
    HGLOBAL h_;
};

class GlobalLockScope
{
public:
    explicit GlobalLockScope(HGLOBAL h) : h_(h), p_(h ? ::GlobalLock(h) : nullptr) {}
    ~GlobalLockScope() { if (p_) ::GlobalUnlock(h_); }
    GlobalLockScope(const GlobalLockScope&) = delete;
    GlobalLockScope& operator=(const GlobalLockScope&) = delete;
    bool IsValid() const { return p_ != nullptr; }
    void* Get() const { return p_; }

private:
    HGLOBAL h_;
    void* p_;
};

// Places one format and transfers ownership only on success.
static bool PutFormat(UINT format, GlobalMem& mem)
{
    if (format == 0 || !mem.IsValid()) return false;
    if (!::SetClipboardData(format, mem.Get())) return false; // mem frees itself on failure
    mem.Release();                                            // ownership moved to the system
    return true;
}
```

### プレーンテキストのコピー（S-01 / CF_UNICODETEXT）

```cpp
// owner must be a valid HWND: OpenClipboard(NULL) + EmptyClipboard sets the owner to
// NULL, which makes SetClipboardData fail.
bool CopyPlainText(HWND owner, const std::wstring& text)
{
    if (!owner) return false;

    // Checked arithmetic on the write path too, not just when parsing untrusted input.
    size_t bytes = 0;
    if (!CheckedAdd(text.size(), 1, bytes)) return false;          // room for the NUL
    if (!CheckedMul(bytes, sizeof(wchar_t), bytes)) return false;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return false;
    if (!::EmptyClipboard()) return false;

    GlobalMem mem(bytes);
    if (!mem.IsValid()) return false;
    {
        GlobalLockScope lock(mem.Get());
        if (!lock.IsValid()) return false;
        ::memcpy(lock.Get(), text.c_str(), bytes);
    }
    return PutFormat(CF_UNICODETEXT, mem);
}
```

### プレーンテキストのペースト（S-01 / 境界検証つき）

```cpp
// Clipboard content comes from other processes: validate size and termination
// before treating it as a string.
bool PastePlainText(HWND owner, std::wstring& out)
{
    if (!::IsClipboardFormatAvailable(CF_UNICODETEXT)) return false;

    ClipboardScope scope(owner); // owner may be NULL for read-only access
    if (!scope.IsOpen()) return false;

    HANDLE hMem = ::GetClipboardData(CF_UNICODETEXT); // stays owned by the clipboard
    if (!hMem) return false;

    const SIZE_T bytes = ::GlobalSize(hMem);
    if (bytes < sizeof(wchar_t)) return false;
    if (bytes % sizeof(wchar_t) != 0) return false;   // character-width integrity
    const size_t maxChars = bytes / sizeof(wchar_t);

    GlobalLockScope lock(hMem);
    if (!lock.IsValid()) return false;

    const auto* src = static_cast<const wchar_t*>(lock.Get());
    const size_t len = ::wcsnlen(src, maxChars);
    if (len == maxChars) return false; // no NUL inside the block: reject as invalid data
    out.assign(src, len);
    return true;
}
```

### HTML のコピー（S-02 / CF_HTML）

```cpp
static const char kFragStart[] = "<!--StartFragment-->";
static const char kFragEnd[]   = "<!--EndFragment-->";

// CF_HTML is UTF-8 and its offsets are byte offsets. The header length is fixed by the
// 10-digit zero padding, so the offsets can be computed before the final formatting.
static const char kPrefix[] = "<html><body>";
static const char kSuffix[] = "</body></html>";

// Offsets are derived from the fixed prefix lengths and the input size — never by searching
// for the markers, because the caller's fragment may legitimately contain the marker text
// itself and a search would then match the wrong occurrence.
// Every offset uses checked arithmetic; the header is formatted with %010d, so each value
// must also fit in an int.
static std::string BuildCfHtml(const std::string& utf8Fragment)
{
    const std::string body = std::string(kPrefix) + kFragStart + utf8Fragment +
                             kFragEnd + kSuffix;
    char header[160] = {};
    const int headerLen = ::sprintf_s(header, "Version:1.0\r\nStartHTML:%010d\r\nEndHTML:%010d\r\n"
                                      "StartFragment:%010d\r\nEndFragment:%010d\r\n", 0, 0, 0, 0);
    if (headerLen <= 0) return {};

    const size_t base = static_cast<size_t>(headerLen);
    size_t startFragSz = 0, endFragSz = 0, endHtmlSz = 0;

    // StartFragment = header + "<html><body>" + "<!--StartFragment-->"
    if (!CheckedAdd(base, sizeof(kPrefix) - 1, startFragSz)) return {};
    if (!CheckedAdd(startFragSz, sizeof(kFragStart) - 1, startFragSz)) return {};
    // EndFragment = StartFragment + fragment length
    if (!CheckedAdd(startFragSz, utf8Fragment.size(), endFragSz)) return {};
    if (!CheckedAdd(base, body.size(), endHtmlSz)) return {};

    int startHtml = 0, startFrag = 0, endFrag = 0, endHtml = 0;
    if (!CheckedToInt(base, startHtml)) return {};        // header offsets are int-formatted
    if (!CheckedToInt(startFragSz, startFrag)) return {};
    if (!CheckedToInt(endFragSz, endFrag)) return {};
    if (!CheckedToInt(endHtmlSz, endHtml)) return {};

    if (::sprintf_s(header, "Version:1.0\r\nStartHTML:%010d\r\nEndHTML:%010d\r\n"
                    "StartFragment:%010d\r\nEndFragment:%010d\r\n",
                    startHtml, endHtml, startFrag, endFrag) != headerLen) return {};
    return std::string(header) + body;
}

bool CopyHtml(HWND owner, const std::string& utf8Fragment)
{
    if (!owner) return false;
    const UINT cfHtml = ::RegisterClipboardFormatW(L"HTML Format");
    if (cfHtml == 0) return false;

    const std::string payload = BuildCfHtml(utf8Fragment);
    if (payload.empty()) return false;

    size_t bytes = 0;
    if (!CheckedAdd(payload.size(), 1, bytes)) return false; // room for the NUL

    ClipboardScope scope(owner);
    if (!scope.IsOpen() || !::EmptyClipboard()) return false;

    GlobalMem mem(bytes);
    if (!mem.IsValid()) return false;
    {
        GlobalLockScope lock(mem.Get());
        if (!lock.IsValid()) return false;
        ::memcpy(lock.Get(), payload.c_str(), bytes);
    }
    return PutFormat(cfHtml, mem);
}
```

### HTML のペースト（S-02 / オフセット解析と検証）

```cpp
struct CfHtmlOffsets
{
    size_t startHtml = 0;
    size_t endHtml = 0;
    size_t startFragment = 0;
    size_t endFragment = 0;
    // Optional selection range (StartSelection / EndSelection).
    bool   hasSelection = false;
    size_t startSelection = 0;
    size_t endSelection = 0;
};

struct HeaderField
{
    bool present = false;
    bool isMinusOne = false;
    size_t value = 0;
};

// Parses "<value>" for an already-identified key. The value must consume the whole
// remainder of the line, so "-10" and "123x" are rejected. A key seen twice is rejected.
static bool ParseHeaderValue(const std::string& value, HeaderField& out)
{
    if (value.empty()) return false;
    if (out.present) return false;                      // duplicate key: reject

    if (value == "-1") { out = { true, true, 0 }; return true; }

    size_t v = 0;
    for (const char c : value)
    {
        if (c < '0' || c > '9') return false;           // digits only, whole value consumed
        size_t scaled = 0;
        if (!CheckedMul(v, 10, scaled)) return false;   // reject overflow
        if (!CheckedAdd(scaled, static_cast<size_t>(c - '0'), v)) return false;
    }
    out = { true, false, v };
    return true;
}

// Parses the header block and enforces
// 0 <= StartHTML <= StartFragment <= EndFragment <= EndHTML <= payloadSize.
//
// Header scope: the block starts at offset 0 and ends at the first line that is not a
// "Key:value" pair. When StartHTML is a real number it additionally caps the scan — the
// context provably begins there — so a known key appearing inside the HTML body is never
// treated as a header field. Every known key propagates its parse result, so a duplicate
// or malformed known key fails the whole parse; only genuinely unknown keys are skipped.
static bool ParseCfHtmlHeader(const std::string& payload, CfHtmlOffsets& out)
{
    if (payload.compare(0, 8, "Version:") != 0) return false;

    HeaderField version, startHtml, endHtml, startFrag, endFrag, startSel, endSel;
    bool versionPresent = false;
    size_t pos = 0;
    size_t scanLimit = payload.size();
    size_t headerEnd = 0;                               // first byte past the last header line

    while (pos < scanLimit)
    {
        size_t eol = payload.find_first_of("\r\n", pos);
        if (eol == std::string::npos || eol > scanLimit) eol = scanLimit;
        const std::string line = payload.substr(pos, eol - pos);

        const size_t colon = line.find(':');
        if (colon == std::string::npos) break;          // end of the header block
        const std::string key = line.substr(0, colon);
        const std::string value = line.substr(colon + 1);

        if (key == "Version")
        {
            if (versionPresent) return false;           // duplicate
            // Only 0.9 and 1.0 are defined; reject empty and unknown values rather than
            // silently accepting arbitrary text. Widen this list if a new version ships.
            if (value != "1.0" && value != "0.9") return false;
            versionPresent = true;
        }
        else if (key == "StartHTML")
        {
            if (!ParseHeaderValue(value, startHtml)) return false;
            // A numeric StartHTML pins the end of the header block.
            if (!startHtml.isMinusOne)
            {
                if (startHtml.value > payload.size()) return false;
                scanLimit = startHtml.value;
            }
        }
        else if (key == "EndHTML")        { if (!ParseHeaderValue(value, endHtml))   return false; }
        else if (key == "StartFragment")  { if (!ParseHeaderValue(value, startFrag)) return false; }
        else if (key == "EndFragment")    { if (!ParseHeaderValue(value, endFrag))   return false; }
        // StartSelection / EndSelection are optional but ARE known keys: a malformed or
        // duplicated one must fail the parse like any other known key, not be ignored.
        else if (key == "StartSelection") { if (!ParseHeaderValue(value, startSel))  return false; }
        else if (key == "EndSelection")   { if (!ParseHeaderValue(value, endSel))    return false; }
        else { /* unknown key: ignored by design (the format is extensible) */ }

        pos = eol;
        while (pos < scanLimit && (payload[pos] == '\r' || payload[pos] == '\n')) ++pos;
        headerEnd = pos;
    }

    if (!versionPresent) return false;

    // StartFragment / EndFragment are mandatory and must be real numbers.
    if (!startFrag.present || startFrag.isMinusOne) return false;
    if (!endFrag.present || endFrag.isMinusOne) return false;
    if (!startHtml.present || !endHtml.present) return false;

    const size_t size = payload.size();
    out.startFragment = startFrag.value;
    out.endFragment = endFrag.value;
    if (out.startFragment > out.endFragment || out.endFragment > size) return false;

    // StartHTML/EndHTML are -1 together when there is no context.
    if (startHtml.isMinusOne != endHtml.isMinusOne) return false;
    if (!startHtml.isMinusOne)
    {
        out.startHtml = startHtml.value;
        out.endHtml = endHtml.value;
        // The context must begin exactly where the header block ended. Without this check a
        // reordered header could place StartHTML inside the header itself and still satisfy
        // the ordering constraints below.
        if (out.startHtml != headerEnd) return false;
        if (out.startHtml > out.startFragment) return false;
        if (out.endFragment > out.endHtml) return false;
        if (out.endHtml > size) return false;
    }

    // The selection is optional, but if present both keys must be there, be real numbers,
    // be ordered, and lie inside the fragment.
    if (startSel.present != endSel.present) return false;
    if (startSel.present)
    {
        if (startSel.isMinusOne || endSel.isMinusOne) return false;
        if (startSel.value > endSel.value) return false;
        if (startSel.value < out.startFragment || endSel.value > out.endFragment) return false;
        out.startSelection = startSel.value;
        out.endSelection = endSel.value;
        out.hasSelection = true;
    }
    return true;
}

// Returns only the fragment, after validating every offset against the payload length.
bool PasteHtmlFragment(HWND owner, std::string& outFragment)
{
    const UINT cfHtml = ::RegisterClipboardFormatW(L"HTML Format");
    if (cfHtml == 0 || !::IsClipboardFormatAvailable(cfHtml)) return false;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return false;

    HANDLE hMem = ::GetClipboardData(cfHtml);
    if (!hMem) return false;

    const SIZE_T bytes = ::GlobalSize(hMem);
    if (bytes == 0) return false;

    GlobalLockScope lock(hMem);
    if (!lock.IsValid()) return false;

    const auto* src = static_cast<const char*>(lock.Get());
    const size_t len = ::strnlen(src, bytes);
    if (len == bytes) return false;                 // no NUL inside the block
    const std::string payload(src, len);

    CfHtmlOffsets off{};
    if (!ParseCfHtmlHeader(payload, off)) return false;

    outFragment.assign(payload, off.startFragment, off.endFragment - off.startFragment);
    return true;
}
```

### ファイル一覧のコピー（S-03 / CF_HDROP）

```cpp
#include <shlobj_core.h>

bool CopyFiles(HWND owner, const std::vector<std::wstring>& paths)
{
    if (!owner || paths.empty()) return false;

    size_t chars = 1; // trailing extra NUL that terminates the list
    for (const auto& p : paths)
    {
        if (p.empty()) return false;
        size_t withNul = 0;
        if (!CheckedAdd(p.size(), 1, withNul)) return false;
        if (!CheckedAdd(chars, withNul, chars)) return false;
    }

    size_t bytes = 0;
    if (!CheckedMul(chars, sizeof(wchar_t), bytes)) return false;
    if (!CheckedAdd(bytes, sizeof(DROPFILES), bytes)) return false;

    ClipboardScope scope(owner);
    if (!scope.IsOpen() || !::EmptyClipboard()) return false;

    GlobalMem mem(bytes);
    if (!mem.IsValid()) return false;
    {
        GlobalLockScope lock(mem.Get());
        if (!lock.IsValid()) return false;

        auto* df = static_cast<DROPFILES*>(lock.Get());
        ::ZeroMemory(df, sizeof(DROPFILES));
        df->pFiles = sizeof(DROPFILES);
        df->fWide  = TRUE; // Unicode paths

        auto* dst = reinterpret_cast<wchar_t*>(reinterpret_cast<BYTE*>(df) + sizeof(DROPFILES));
        size_t remain = chars;
        for (const auto& p : paths)
        {
            ::wcscpy_s(dst, remain, p.c_str());
            dst += p.size() + 1;
            remain -= p.size() + 1;
        }
        *dst = L'\0'; // double-NUL terminates the list
    }
    return PutFormat(CF_HDROP, mem);
}
```

### ファイル一覧のペースト（S-03）

```cpp
#include <shellapi.h>

bool PasteFiles(HWND owner, std::vector<std::wstring>& out)
{
    if (!::IsClipboardFormatAvailable(CF_HDROP)) return false;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return false;

    auto hDrop = static_cast<HDROP>(::GetClipboardData(CF_HDROP));
    if (!hDrop) return false;
    if (::GlobalSize(hDrop) < sizeof(DROPFILES)) return false;

    const UINT count = ::DragQueryFileW(hDrop, 0xFFFFFFFF, nullptr, 0);
    if (count == 0) return false;

    out.clear();
    for (UINT i = 0; i < count; ++i)
    {
        const UINT len = ::DragQueryFileW(hDrop, i, nullptr, 0); // length without the NUL
        if (len == 0) return false;

        size_t withNul = 0;
        if (!CheckedAdd(static_cast<size_t>(len), 1, withNul)) return false;
        UINT withNulU = 0;
        if (!CheckedToUInt(withNul, withNulU)) return false;

        std::wstring path(withNul, L'\0');                      // room for the NUL
        if (::DragQueryFileW(hDrop, i, path.data(), withNulU) == 0) return false;
        path.resize(len);
        out.push_back(std::move(path));
    }
    return true;
}
```

### 画像のコピー（S-04 / CF_DIB）

```cpp
// dib holds a BITMAPINFOHEADER (+ palette) followed by the pixel bits, as produced by
// GetDIBits. CF_DIB is preferred over CF_BITMAP: the system synthesizes CF_BITMAP from it.
bool CopyDib(HWND owner, const std::vector<BYTE>& dib)
{
    if (!owner || dib.size() < sizeof(BITMAPINFOHEADER)) return false;

    ClipboardScope scope(owner);
    if (!scope.IsOpen() || !::EmptyClipboard()) return false;

    GlobalMem mem(dib.size());
    if (!mem.IsValid()) return false;
    {
        GlobalLockScope lock(mem.Get());
        if (!lock.IsValid()) return false;
        ::memcpy(lock.Get(), dib.data(), dib.size());
    }
    return PutFormat(CF_DIB, mem);
}
```

### 画像のペースト（S-04 / CF_DIB）

DIB の構造検証は `ValidateDib` に集約する。ヘッダサイズだけの確認では不十分で、`biPlanes` / `biBitCount` / `biCompression` / パレット・カラーマスク・stride・ピクセル範囲まで `GlobalSize` 内に収まることを checked arithmetic で確認する（純ロジックとして単体テスト対象・D-30）。

```cpp
// Declared here, implemented as WinRT/Win32-independent pure logic (unit-tested).
// Validates: biSize is a known header size; biPlanes == 1; biBitCount is one of
// 1/4/8/16/24/32; biCompression is supported; palette entries (or BI_BITFIELDS masks)
// fit; stride = ((width * bitCount + 31) / 32) * 4 does not overflow; and
// header + palette + (stride * abs(height)) <= totalBytes.
bool ValidateDib(const BYTE* data, size_t totalBytes);

bool PasteDib(HWND owner, std::vector<BYTE>& out)
{
    if (!::IsClipboardFormatAvailable(CF_DIB)) return false;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return false;

    HANDLE hMem = ::GetClipboardData(CF_DIB);
    if (!hMem) return false;

    const SIZE_T bytes = ::GlobalSize(hMem);
    if (bytes < sizeof(BITMAPINFOHEADER)) return false;

    GlobalLockScope lock(hMem);
    if (!lock.IsValid()) return false;

    const auto* src = static_cast<const BYTE*>(lock.Get());
    if (!ValidateDib(src, bytes)) return false;   // full structural validation

    out.assign(src, src + bytes);
    return true;
}
```

### 独自フォーマットのコピー / ペースト（S-05）

```cpp
static UINT CustomFormat()
{
    static const UINT id = ::RegisterClipboardFormatW(L"NativeToolkit.Custom.v1");
    return id; // 0 means registration failed
}

bool CopyCustom(HWND owner, const std::vector<BYTE>& blob)
{
    if (!owner || blob.empty() || CustomFormat() == 0) return false;

    ClipboardScope scope(owner);
    if (!scope.IsOpen() || !::EmptyClipboard()) return false;

    GlobalMem mem(blob.size());
    if (!mem.IsValid()) return false;
    {
        GlobalLockScope lock(mem.Get());
        if (!lock.IsValid()) return false;
        ::memcpy(lock.Get(), blob.data(), blob.size());
    }
    return PutFormat(CustomFormat(), mem);
}

bool PasteCustom(HWND owner, std::vector<BYTE>& out)
{
    if (CustomFormat() == 0 || !::IsClipboardFormatAvailable(CustomFormat())) return false;

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return false;

    HANDLE hMem = ::GetClipboardData(CustomFormat());
    if (!hMem) return false;
    const SIZE_T bytes = ::GlobalSize(hMem);
    if (bytes == 0) return false;

    GlobalLockScope lock(hMem);
    if (!lock.IsValid()) return false;
    const auto* src = static_cast<const BYTE*>(lock.Get());
    out.assign(src, src + bytes);
    return true;
}
```

### 複数フォーマットの同時配置（S-06 / 部分成功を残さない）

契約: **best-effort rollback**。原子的（atomic）な保証はできない。全ペイロードの構築と確保を `EmptyClipboard` より前に済ませることで失敗確率を大きく下げ、配置段階で失敗した場合は再度 `EmptyClipboard` して一貫した失敗状態へ戻す。**ただしロールバック用の `EmptyClipboard` 自体が失敗する可能性があり、その場合は先に置いた形式が残り得る。** ロールバック失敗は別エラー（または `UNKNOWN`）として返し、部分状態が残っている可能性を呼び出し側へ伝える。

```cpp
// Place the richest format first: pasting apps take the first format they recognize.
// Returns a domain error; PARTIAL_STATE means the rollback itself failed and the clipboard
// may still hold some of the formats.
DWORD CopyTextWithHtml(HWND owner, const std::wstring& plain, const std::string& utf8Fragment)
{
    if (!owner) return CLIPBOARD_ERROR_INVALID_ARGUMENT;
    const UINT cfHtml = ::RegisterClipboardFormatW(L"HTML Format");
    if (cfHtml == 0) return CLIPBOARD_ERROR_UNKNOWN;
    const std::string html = BuildCfHtml(utf8Fragment);
    if (html.empty()) return CLIPBOARD_ERROR_INVALID_ARGUMENT;

    size_t textBytes = 0;
    if (!CheckedAdd(plain.size(), 1, textBytes)) return CLIPBOARD_ERROR_INVALID_ARGUMENT;
    if (!CheckedMul(textBytes, sizeof(wchar_t), textBytes)) return CLIPBOARD_ERROR_INVALID_ARGUMENT;
    size_t htmlBytes = 0;
    if (!CheckedAdd(html.size(), 1, htmlBytes)) return CLIPBOARD_ERROR_INVALID_ARGUMENT;

    // Build and fill every payload BEFORE emptying the clipboard, so a late allocation
    // failure cannot leave a half-populated clipboard behind.
    GlobalMem htmlMem(htmlBytes);
    GlobalMem textMem(textBytes);
    if (!htmlMem.IsValid() || !textMem.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
    { GlobalLockScope l(htmlMem.Get()); if (!l.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
      ::memcpy(l.Get(), html.c_str(), htmlBytes); }
    { GlobalLockScope l(textMem.Get()); if (!l.IsValid()) return CLIPBOARD_ERROR_OUT_OF_MEMORY;
      ::memcpy(l.Get(), plain.c_str(), textBytes); }

    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
    if (!::EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;

    if (!PutFormat(cfHtml, htmlMem) || !PutFormat(CF_UNICODETEXT, textMem))
    {
        // Best-effort rollback: EmptyClipboard can itself fail, leaving partial content.
        if (!::EmptyClipboard())
        {
            DFLog(TAG, L"[CopyTextWithHtml] rollback failed. err=%lu", ::GetLastError());
            return CLIPBOARD_ERROR_PARTIAL_STATE;
        }
        return CLIPBOARD_ERROR_UNKNOWN;
    }
    return CLIPBOARD_ERROR_NONE;
}
```

### 内容確認（S-07）

```cpp
// Two APIs here return 0 for two different reasons, so last-error must disambiguate both:
//   CountClipboardFormats: 0 means "empty" OR "failed"
//   EnumClipboardFormats:  0 means "end of list" (GetLastError == ERROR_SUCCESS) OR "failed"
// The docs also do NOT define pcFormatsOut when GetUpdatedClipboardFormats' buffer is too
// small, so the count is sized with headroom and EnumClipboardFormats is the fallback.
bool ListFormats(HWND owner, std::vector<UINT>& out)
{
    ::SetLastError(ERROR_SUCCESS);
    const int known = ::CountClipboardFormats();
    if (known == 0)
    {
        if (::GetLastError() != ERROR_SUCCESS) return false; // genuine failure, not "empty"
        out.clear();
        return true;
    }

    // Headroom: synthesized formats may be reported in addition to the placed ones.
    size_t capacity = 0;
    if (!CheckedMul(static_cast<size_t>(known), 2, capacity)) return false;
    if (!CheckedAdd(capacity, 8, capacity)) return false;
    out.assign(capacity, 0);

    UINT capacityU = 0;
    if (!CheckedToUInt(out.size(), capacityU)) return false;

    UINT count = 0;
    if (::GetUpdatedClipboardFormats(out.data(), capacityU, &count))
    {
        if (count > out.size()) return false; // defensive: never trust a count past the buffer
        out.resize(count);
        return true;
    }

    // Fallback: enumerate explicitly (requires the clipboard to be open).
    out.clear();
    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return false;

    for (UINT fmt = (::SetLastError(ERROR_SUCCESS), ::EnumClipboardFormats(0));
         fmt != 0;
         fmt = (::SetLastError(ERROR_SUCCESS), ::EnumClipboardFormats(fmt)))
    {
        out.push_back(fmt);
    }
    if (::GetLastError() != ERROR_SUCCESS) { out.clear(); return false; } // partial: discard
    return true;
}

// Standard formats have no registered name: GetClipboardFormatName returns 0 for them.
bool FormatName(UINT format, std::wstring& out)
{
    switch (format) // resolve the standard ones ourselves
    {
    case CF_UNICODETEXT: out = L"CF_UNICODETEXT"; return true;
    case CF_TEXT:        out = L"CF_TEXT";        return true;
    case CF_HDROP:       out = L"CF_HDROP";       return true;
    case CF_DIB:         out = L"CF_DIB";         return true;
    case CF_DIBV5:       out = L"CF_DIBV5";       return true;
    case CF_BITMAP:      out = L"CF_BITMAP";      return true;
    default: break;
    }

    wchar_t buffer[256] = {};
    const int len = ::GetClipboardFormatNameW(format, buffer, ARRAYSIZE(buffer));
    if (len <= 0) return false; // unknown / unnamed format
    out.assign(buffer, static_cast<size_t>(len));
    return true;
}

int PickPreferredFormat()
{
    UINT priority[] = { CF_UNICODETEXT, CF_HDROP, CF_DIB, CF_BITMAP };
    return ::GetPriorityClipboardFormat(priority, ARRAYSIZE(priority)); // 0: none, -1: empty
}
```

### クリップボードのクリア（S-08）

```cpp
bool ClearClipboard(HWND owner)
{
    if (!owner) return false;
    ClipboardScope scope(owner);
    if (!scope.IsOpen()) return false;
    return ::EmptyClipboard() != FALSE;
}
```

### 変更監視（S-09 / インスタンス状態で保持）

```cpp
// State is per-instance, not static: several managers or windows must not share it.
// The instance is owned by the thread that pumps messages for hwnd.
class ClipboardWatcher
{
public:
    bool Start(HWND hwnd)
    {
        if (!hwnd) return false;
        if (registered_) return true;
        if (!::AddClipboardFormatListener(hwnd)) return false; // log GetLastError()
        hwnd_ = hwnd;
        registered_ = true;
        lastSeq_ = ::GetClipboardSequenceNumber();
        return true;
    }

    // Only clear the state when the listener was really removed: otherwise the registration
    // is still live and a "detached" object would keep receiving notifications with no way
    // to retry the removal.
    bool Stop()
    {
        if (!registered_) return true;
        if (!::RemoveClipboardFormatListener(hwnd_)) return false; // stay registered, retryable
        registered_ = false;
        hwnd_ = nullptr;
        return true;
    }

    // Teardown must not proceed while the listener is still registered: the window may not be
    // destroyed until Stop() succeeds (retry, then log and surface MONITOR_REGISTER_FAILED).
    bool IsRegistered() const { return registered_; }

    // Call right after our own SetClipboardData so the resulting notification is suppressed.
    void NoteSelfWrite() { selfWriteSeq_ = ::GetClipboardSequenceNumber(); }

    void OnClipboardUpdate()
    {
        const DWORD seq = ::GetClipboardSequenceNumber();
        if (seq == lastSeq_) return;
        lastSeq_ = seq;
        if (seq == selfWriteSeq_) return; // self-originated: do not re-notify
        // notify listeners here
    }

private:
    HWND  hwnd_ = nullptr;
    bool  registered_ = false;
    DWORD lastSeq_ = 0;
    DWORD selfWriteSeq_ = 0;
};
```

### 遅延レンダリング（S-10 / 全予約形式の状態管理）

**Renderer の所有権契約**: 遅延レンダリングの対象は **`GlobalAlloc(GMEM_MOVEABLE)` で確保する `HGLOBAL` 形式に限定する**（`CF_UNICODETEXT` / `CF_HTML` / `CF_HDROP` / `CF_DIB` / 登録形式など）。`CF_BITMAP`・メタファイル・GDI オブジェクト系は解放方法が形式ごとに異なり（`DeleteObject` / `DeleteEnhMetaFile` 等）、`GlobalFree` で一律に解放すると不正になるため、この API では受け付けない。形式ごとの deleter を持たせる設計にする場合は、Renderer の戻り値を `{ handle, deleter }` の型にする（設計工程で判断）。

```cpp
#include <functional>
#include <map>
#include <set>

// WM_RENDERALLFORMATS requires rendering every format we are capable of generating,
// so the reserved formats and their renderers live in per-manager state.
class DeferredClipboard
{
public:
    // Returns an owned HGLOBAL (GMEM_MOVEABLE), or an invalid GlobalMem on failure.
    // Restricted to HGLOBAL-based formats: CF_BITMAP / metafile / GDI handles must not be
    // used here because they require format-specific deleters, not GlobalFree.
    using Renderer = std::function<GlobalMem()>;

    // Reserves all formats in one Open/Empty/Close sequence.
    // Returns NONE on success, UNKNOWN when the reservation was rolled back cleanly, and
    // PARTIAL_STATE when the rollback ITSELF failed — in which case reserved formats may
    // still be on the clipboard, so the renderer table is deliberately KEPT so that
    // WM_RENDERFORMAT for those leftovers can still be answered. The table is released
    // later by WM_DESTROYCLIPBOARD (i.e. when ownership is actually lost).
    DWORD Reserve(HWND owner, std::map<UINT, Renderer> renderers)
    {
        if (!owner || renderers.empty()) return CLIPBOARD_ERROR_INVALID_ARGUMENT;
        for (const auto& [fmt, fn] : renderers)
        {
            if (fmt == 0 || !fn) return CLIPBOARD_ERROR_INVALID_ARGUMENT;
        }

        ClipboardScope scope(owner);
        if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
        if (!::EmptyClipboard()) return CLIPBOARD_ERROR_UNKNOWN;

        // Store the table BEFORE placing anything: a WM_RENDERFORMAT can only arrive for a
        // format we already reserved, and we must be able to answer it.
        owner_ = owner;
        renderers_ = std::move(renderers);
        rendered_.clear();

        for (const auto& [fmt, fn] : renderers_)
        {
            // SetClipboardData returns NULL on success too when the handle is NULL, and the
            // docs define no distinct success value here. Verify indirectly instead.
            ::SetLastError(ERROR_SUCCESS);      // last-error is only meaningful when pre-cleared
            ::SetClipboardData(fmt, nullptr);
            const bool ok = (::GetLastError() == ERROR_SUCCESS) &&
                            (::GetClipboardOwner() == owner) &&
                            (::IsClipboardFormatAvailable(fmt) != FALSE);
            if (ok) continue;

            // Roll back every format reserved so far, inside the same Open/Close section.
            if (::EmptyClipboard())
            {
                Clear();                        // nothing left on the clipboard: safe to drop
                return CLIPBOARD_ERROR_UNKNOWN;
            }

            // Rollback failed: leftovers may remain, so KEEP the table to stay answerable.
            DFLog(TAG, L"[Reserve] rollback failed. err=%lu", ::GetLastError());
            partial_ = true;
            return CLIPBOARD_ERROR_PARTIAL_STATE;
        }
        partial_ = false;
        return CLIPBOARD_ERROR_NONE;
    }

    // Explicit recovery after PARTIAL_STATE. Takes no HWND argument on purpose: only the
    // stored owner_ is authoritative. A caller-supplied HWND could differ from the window
    // that actually owns the leftovers and would then wrongly look like "someone else owns
    // it", dropping the renderer table that the leftover formats still need.
    // The table is released only on a successful EmptyClipboard, or via WM_DESTROYCLIPBOARD.
    DWORD RecoverFromPartialState()
    {
        if (!partial_) return CLIPBOARD_ERROR_NONE;
        if (!owner_) { Clear(); return CLIPBOARD_ERROR_NONE; }

        ClipboardScope scope(owner_);
        if (!scope.IsOpen()) return CLIPBOARD_ERROR_BUSY;
        if (::GetClipboardOwner() != owner_)
        {
            // Ownership genuinely moved elsewhere: WM_DESTROYCLIPBOARD will have been sent,
            // so nothing of ours can be requested anymore.
            Clear();
            return CLIPBOARD_ERROR_NONE;
        }
        if (!::EmptyClipboard()) return CLIPBOARD_ERROR_PARTIAL_STATE; // still partial, retry later
        Clear();
        return CLIPBOARD_ERROR_NONE;
    }

    bool IsPartial() const { return partial_; }

    // WM_RENDERFORMAT: must NOT call OpenClipboard here.
    void OnRenderFormat(UINT format)
    {
        auto it = renderers_.find(format);
        if (it == renderers_.end()) return;     // not ours: never place data for it
        GlobalMem mem = it->second();
        if (!mem.IsValid()) { DFLog(TAG, L"[OnRenderFormat] renderer failed. fmt=%u", format); return; }
        if (!::SetClipboardData(format, mem.Get()))   // mem frees itself on failure
        {
            DFLog(TAG, L"[OnRenderFormat] SetClipboardData failed. fmt=%u err=%lu", format, ::GetLastError());
            return;
        }
        mem.Release();                          // ownership moved to the system
        rendered_.insert(format);
    }

    // WM_RENDERALLFORMATS: render every format still outstanding.
    void OnRenderAllFormats(HWND hwnd)
    {
        if (!::OpenClipboard(hwnd)) { DFLog(TAG, L"[OnRenderAllFormats] open failed. err=%lu", ::GetLastError()); return; }
        // Another app may have taken ownership between the message and this call.
        if (::GetClipboardOwner() != hwnd)
        {
            DLog(TAG, L"[OnRenderAllFormats] ownership lost; not overwriting");
        }
        else
        {
            // Do NOT call EmptyClipboard: it would erase formats already rendered.
            for (const auto& [fmt, fn] : renderers_)
            {
                if (rendered_.count(fmt)) continue;
                GlobalMem mem = fn();
                if (!mem.IsValid()) { DFLog(TAG, L"[OnRenderAllFormats] renderer failed. fmt=%u", fmt); continue; }
                if (!::SetClipboardData(fmt, mem.Get()))
                {
                    DFLog(TAG, L"[OnRenderAllFormats] set failed. fmt=%u err=%lu", fmt, ::GetLastError());
                    continue;                   // mem frees itself
                }
                mem.Release();
                rendered_.insert(fmt);
            }
        }
        ::CloseClipboard();
        // Formats left unrendered are dropped from the format list by the system.
    }

    // WM_DESTROYCLIPBOARD: ownership lost, release everything held for rendering.
    void OnDestroyClipboard() { Clear(); }

private:
    void Clear() { renderers_.clear(); rendered_.clear(); owner_ = nullptr; partial_ = false; }

    HWND owner_ = nullptr;
    bool partial_ = false;
    std::map<UINT, Renderer> renderers_;
    std::set<UINT> rendered_;
};
```

予約の状態遷移:

| 遷移 | 条件 | 結果 | テーブル |
|---|---|---|---|
| 予約成功 | 全形式で `SetClipboardData` + 所有者確認 + 形式確認が成功 | `NONE` | 保持（`WM_RENDERFORMAT` に応答） |
| ロールバック成功 | 途中失敗 → `EmptyClipboard` 成功 | `UNKNOWN` | 破棄（クリップボードは空） |
| ロールバック失敗 | 途中失敗 → `EmptyClipboard` も失敗 | `PARTIAL_STATE` | **保持**（残存形式に応答するため。`RecoverFromPartialState` か `WM_DESTROYCLIPBOARD` で解放） |
| 所有権喪失 | 他アプリが所有権を取得 | - | `WM_DESTROYCLIPBOARD` で破棄 |

```cpp

LRESULT CALLBACK OwnerWndProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp)
{
    // The instance is attached at window creation (WM_NCCREATE / SetWindowLongPtr), but
    // clipboard messages can still arrive before or after that, so null is checked.
    auto* deferred = GetDeferredForWindow(hwnd);
    if (!deferred) return ::DefWindowProcW(hwnd, msg, wp, lp);

    switch (msg)
    {
    case WM_RENDERFORMAT:     deferred->OnRenderFormat(static_cast<UINT>(wp)); return 0;
    case WM_RENDERALLFORMATS: deferred->OnRenderAllFormats(hwnd);              return 0;
    case WM_DESTROYCLIPBOARD: deferred->OnDestroyClipboard();                  return 0;
    }
    return ::DefWindowProcW(hwnd, msg, wp, lp);
}
```

### 履歴 / クラウド同期からの除外（S-11）

```cpp
// Call inside the same Open/Empty/Close sequence as the actual data.
bool MarkAsSensitive()
{
    const UINT history = ::RegisterClipboardFormatW(L"CanIncludeInClipboardHistory");
    const UINT cloud   = ::RegisterClipboardFormatW(L"CanUploadToCloudClipboard");
    if (history == 0 || cloud == 0) return false;

    for (UINT fmt : { history, cloud })
    {
        GlobalMem mem(sizeof(DWORD));
        if (!mem.IsValid()) return false;
        {
            GlobalLockScope lock(mem.Get());
            if (!lock.IsValid()) return false;
            *static_cast<DWORD*>(lock.Get()) = 0; // 0 = exclude
        }
        if (!PutFormat(fmt, mem)) return false;
    }
    return true;
}
```

### WinRT 例外の共通ラッパ（S-17 / Bridge 境界）

```cpp
#include <winrt/Windows.ApplicationModel.DataTransfer.h>
using namespace winrt::Windows::ApplicationModel::DataTransfer;

// Shared classification. C++/WinRT converts ABI HRESULTs into winrt::hresult_error, EXCEPT
// that E_OUTOFMEMORY surfaces as std::bad_alloc (documented), so that is caught separately.
inline DWORD ClassifyWinRtException()
{
    try { throw; }
    catch (const winrt::hresult_error& e)
    {
        const HRESULT hr = e.code();
        DFLog(TAG, L"[WinRT] hr=0x%08lx msg=%ls", hr, e.message().c_str());
        switch (hr)
        {
        case E_ACCESSDENIED: return CLIPBOARD_ERROR_ACCESS_DENIED;
        case E_OUTOFMEMORY:  return CLIPBOARD_ERROR_OUT_OF_MEMORY;
        case E_INVALIDARG:   return CLIPBOARD_ERROR_INVALID_ARGUMENT;
        default:             return CLIPBOARD_ERROR_UNKNOWN; // raw hr already logged
        }
    }
    catch (const std::bad_alloc&)
    {
        DLog(TAG, L"[WinRT] std::bad_alloc (E_OUTOFMEMORY)");
        return CLIPBOARD_ERROR_OUT_OF_MEMORY;
    }
    catch (const std::exception& e)
    {
        DFLog(TAG, L"[WinRT] std::exception: %hs", e.what());
        return CLIPBOARD_ERROR_UNKNOWN;
    }
    catch (...)
    {
        DLog(TAG, L"[WinRT] unknown exception");
        return CLIPBOARD_ERROR_UNKNOWN;
    }
}

// Synchronous boundary: use for WinRT calls that do not co_await.
template <typename Fn>
DWORD InvokeWinRt(Fn&& fn)
{
    try { return std::forward<Fn>(fn)(); } // returns a CLIPBOARD_ERROR_* value
    catch (...) { return ClassifyWinRtException(); }
}
```

**非同期の例外は同期ラッパでは捕まらない。** `co_await` の後で発生した例外は非同期オブジェクトに格納され、再開時にコルーチン内で再送出される。公式のエラー処理ガイダンスどおり、**例外は発生し得る非同期処理と同じコルーチン内で捕捉する**。そのため非同期用のラッパを別に用意する。

**結果型の統一**: 公開 Bridge から見える WinRT 操作は、`bool` や `hstring` を直接返さず **Domain エラー + ペイロード**の結果型に統一する。これにより全境界が同一のラッパを通る。

```cpp
// Unified result type for every WinRT-backed operation crossing the bridge.
template <typename T>
struct ClipboardResult
{
    DWORD error = CLIPBOARD_ERROR_NONE;
    T value{};
};
using ClipboardStatus = ClipboardResult<std::monostate>; // payload-less operations

// Asynchronous boundary: the try/catch must live INSIDE the coroutine, around the co_await.
// Body is a callable returning IAsyncOperation<ClipboardResult<T>>.
template <typename T, typename Body>
winrt::Windows::Foundation::IAsyncOperation<ClipboardResult<T>> InvokeWinRtAsync(Body body)
{
    try
    {
        co_return co_await body();
    }
    catch (...)
    {
        co_return ClipboardResult<T>{ ClassifyWinRtException(), {} };
    }
}
```

**完了コールバックの契約**: `fire_and_forget` の未処理例外はプロセス終了につながるため、`noexcept` を付けるだけでは足りない。**コールバック呼び出し自体も `try/catch` で囲む**。C ABI コールバックは例外を投げてはならないことを公開 API のドキュメントに明記する。

**受付（acceptance）を境界とする。** 「pending 登録」に加え、非 UI スレッド経路では「UI キューへの投入」、UI スレッド経路では「受付前検証後の直接開始への引き渡し」が成功した時点を**受付成立**とし、これを基準に同期通知と非同期通知を分ける。

| 段階 | 通知方法 | コールバック回数 |
|---|---|---|
| 受付成立**前**の失敗（引数不正、pending 登録失敗、`PostMessage` 失敗、UI 直接開始前のフォアグラウンド不成立・引き渡し失敗） | **Bridge の同期戻り値のみ**でエラーを返す。リクエスト ID は無効値を返す | **0 回** |
| 受付成立**後**の全終端状態（成功・失敗・キャンセル・`Uninit` による失効） | **コールバック** | **ちょうど 1 回** |

| 項目 | 契約 |
|---|---|
| Bridge の戻り値 | 受付成立で `NONE` + 有効なリクエスト ID。受付失敗で Domain エラー + 無効 ID（コールバックは来ない） |
| リクエスト ID の有効条件 | 受付成立時のみ有効。無効 ID に対する `Cancel` は何もしない |
| コールバックの例外 | C ABI 境界なので投げてはならない。万一投げても呼び出し側で捕捉しログのみ（プロセスは落とさない） |
| 呼び出し回数 | 受付成立後は**ちょうど 1 回**。pending テーブルからの取り出しをアトミックに行い二重呼び出しを防ぐ |
| 失効（`Uninit` 後） | `Uninit` で pending テーブルをドレインし、登録済みコールバックへ「キャンセル」を 1 回通知してから破棄する。以降に完了が届いてもコールバックは呼ばずに破棄する |
| キャンセルとの競合 | `Cancel` はリクエスト ID で pending テーブルから取り出せた場合のみ有効。取り出せなければ既に完了済み（＝コールバック呼び出し済み）として何もしない |

```cpp
// Single place that enforces the callback contract for EVERY request kind:
//   - atomic take from the pending table  -> exactly-once, and cancel/Uninit win the race
//   - try/catch around the invocation     -> a throwing C ABI callback cannot kill the process
template <typename... Payload>
void CompletePendingRequest(uint32_t requestId, DWORD error, Payload&&... payload) noexcept
{
    auto callback = g_pending.Take(requestId);
    if (!callback) return;                    // cancelled, or invalidated by Uninit

    try
    {
        callback(requestId, error, std::forward<Payload>(payload)...);
    }
    catch (...)
    {
        DFLog(TAG, L"[CompletePendingRequest] callback threw. id=%u", requestId);
    }
}

// The bridge entry is a noexcept ABI boundary: never let an exception escape it.
// fire_and_forget preserves stowed-exception context for debugging (official guidance).
winrt::fire_and_forget RunHistoryRequest(uint32_t requestId) noexcept
{
    auto result = co_await InvokeWinRtAsync<std::monostate>([] {
        return RestoreLatestHistoryItemAsync();
    });
    CompletePendingRequest(requestId, result.error);
}
```

### WinRT 履歴ステータスの共通変換（S-17）

```cpp
// Used by every history call so the mapping cannot drift between call sites.
inline DWORD MapHistoryStatus(ClipboardHistoryItemsResultStatus status)
{
    switch (status)
    {
    case ClipboardHistoryItemsResultStatus::Success:                  return CLIPBOARD_ERROR_NONE;
    case ClipboardHistoryItemsResultStatus::AccessDenied:             return CLIPBOARD_ERROR_ACCESS_DENIED;
    case ClipboardHistoryItemsResultStatus::ClipboardHistoryDisabled: return CLIPBOARD_ERROR_HISTORY_DISABLED;
    default:                                                          return CLIPBOARD_ERROR_UNKNOWN;
    }
}

inline DWORD MapSetHistoryItemStatus(SetHistoryItemAsContentStatus status)
{
    switch (status)
    {
    case SetHistoryItemAsContentStatus::Success:      return CLIPBOARD_ERROR_NONE;
    case SetHistoryItemAsContentStatus::AccessDenied: return CLIPBOARD_ERROR_ACCESS_DENIED;
    case SetHistoryItemAsContentStatus::ItemDeleted:  return CLIPBOARD_ERROR_ITEM_DELETED;
    default:                                          return CLIPBOARD_ERROR_UNKNOWN;
    }
}
```

### WinRT: テキストのコピー / ペースト（履歴機能と併用する場合）

`WinRtCopyText` は**所有 UI スレッド上だけで呼ぶ内部同期 helper**である。`Clipboard::SetContent` 自体は同期 API なので内部でワーカースレッドへ逃がさないが、公開 Bridge は任意スレッドから呼ばれるため、非 UI スレッドからの要求は履歴 API と同じ pending + `PostMessage` 経路で UI スレッドへ配送し、受付後の結果を callback で返す。`InvokeWinRt` は例外正規化だけを担当し、スレッド配送を代替しない。

```cpp
// Internal UI-thread-only helper. The public arbitrary-thread Bridge dispatches to this.
DWORD WinRtCopyText(const winrt::hstring& text)
{
    return InvokeWinRt([&] {
        DataPackage package;
        package.RequestedOperation(DataPackageOperation::Copy);
        package.SetText(text);
        Clipboard::SetContent(package);
        return CLIPBOARD_ERROR_NONE;
    });
}

// Start on the UI (foreground) thread; co_await keeps that thread unblocked and C++/WinRT
// restores the calling apartment on resumption. Never call get() on an STA thread.
// Returns the unified result type so the caller goes through InvokeWinRtAsync like the rest.
winrt::Windows::Foundation::IAsyncOperation<ClipboardResult<winrt::hstring>> WinRtPasteTextAsync()
{
    DataPackageView view = Clipboard::GetContent();
    if (!view.Contains(StandardDataFormats::Text()))
        co_return ClipboardResult<winrt::hstring>{ CLIPBOARD_ERROR_FORMAT_UNAVAILABLE, {} };

    co_return ClipboardResult<winrt::hstring>{ CLIPBOARD_ERROR_NONE, co_await view.GetTextAsync() };
}

// Call site: exceptions after the co_await are converted by the async wrapper, and the
// result is delivered through the same exactly-once helper as every other request.
winrt::fire_and_forget PasteTextRequest(uint32_t requestId) noexcept
{
    auto result = co_await InvokeWinRtAsync<winrt::hstring>([] { return WinRtPasteTextAsync(); });
    CompletePendingRequest(requestId, result.error, result.value);
}
```

### WinRT: 履歴の取得と復元（S-12）

```cpp
// Started on the UI thread; the wait does not block it. Wrap the call site with
// InvokeWinRtAsync so exceptions raised after the co_await become domain errors.
// Returns ClipboardStatus so the type matches InvokeWinRtAsync<std::monostate>.
winrt::Windows::Foundation::IAsyncOperation<ClipboardStatus> RestoreLatestHistoryItemAsync()
{
    if (!Clipboard::IsHistoryEnabled())
        co_return ClipboardStatus{ CLIPBOARD_ERROR_HISTORY_DISABLED, {} };

    ClipboardHistoryItemsResult result = co_await Clipboard::GetHistoryItemsAsync();
    const DWORD status = MapHistoryStatus(result.Status());
    if (status != CLIPBOARD_ERROR_NONE) co_return ClipboardStatus{ status, {} };

    auto items = result.Items();
    if (items.Size() == 0) co_return ClipboardStatus{ CLIPBOARD_ERROR_EMPTY, {} };

    co_return ClipboardStatus{
        MapSetHistoryItemStatus(Clipboard::SetHistoryItemAsContent(items.GetAt(0))), {} };
}
```

### WinRT: 履歴の削除 / 消去（S-13）

```cpp
winrt::Windows::Foundation::IAsyncOperation<ClipboardStatus> DeleteOldestHistoryItemAsync()
{
    ClipboardHistoryItemsResult result = co_await Clipboard::GetHistoryItemsAsync();
    const DWORD status = MapHistoryStatus(result.Status()); // never collapse AccessDenied here
    if (status != CLIPBOARD_ERROR_NONE) co_return ClipboardStatus{ status, {} };

    auto items = result.Items();
    if (items.Size() == 0) co_return ClipboardStatus{ CLIPBOARD_ERROR_EMPTY, {} };

    // false only means "not successful": the docs give no reason, so do not claim access denied.
    co_return ClipboardStatus{
        Clipboard::DeleteItemFromHistory(items.GetAt(items.Size() - 1))
            ? CLIPBOARD_ERROR_NONE : CLIPBOARD_ERROR_UNKNOWN, {} };
}

// Note: ClearHistory does NOT remove pinned items (documented). Callers must not present
// this as "clear everything" in UI text or manuals.
// Internal UI-thread-only helper. The underlying WinRT call is synchronous, so exception
// normalization uses InvokeWinRt; the public arbitrary-thread Bridge still dispatches to the
// UI thread and completes through the request callback contract.
DWORD ClearUnpinnedHistory()
{
    return InvokeWinRt([] {
        // false only means "not successful": no reason is defined by the docs.
        return Clipboard::ClearHistory() ? CLIPBOARD_ERROR_NONE : CLIPBOARD_ERROR_UNKNOWN;
    });
}
```

### WinRT: 履歴・設定変更イベント（S-14）

**`auto_revoke` は採用しない。** `winrt::event_revoker::revoke()` は公式シグネチャが **`void revoke() noexcept`** であり、**解除の失敗を戻り値でも例外でも観測できない**。本機能は「解除成功を確認してからウィンドウを破棄する」shutdown gate（D-34）を要件にしているため、`event_token` を保持して**明示的に解除**し、失敗を観測・再試行できる構成にする。

参照: [winrt::event_revoker::revoke（`void revoke() noexcept`）](https://learn.microsoft.com/en-us/uwp/cpp-ref-for-winrt/event-revoker)

```cpp
// Shared by the watcher and its callbacks. It starts closed, is opened only after all
// registrations commit, and is never reopened after Stop. Stop closes the gate and drains
// callbacks that had already entered before it returns.
struct EventLifetimeState
{
    static constexpr uint64_t kClosed = uint64_t{ 1 } << 63;
    static constexpr uint64_t kCountMask = ~kClosed;
    std::atomic<uint64_t> gate{ kClosed }; // high bit = closed, low bits = in-flight count

    void Activate() noexcept
    {
        gate.store(0, std::memory_order_release);
    }

    bool TryEnter() noexcept
    {
        uint64_t current = gate.load(std::memory_order_acquire);
        while ((current & kClosed) == 0)
        {
            if ((current & kCountMask) == kCountMask) return false; // defensive saturation
            if (gate.compare_exchange_weak(
                    current, current + 1,
                    std::memory_order_acq_rel, std::memory_order_acquire))
                return true;
        }
        return false;
    }

    void Leave() noexcept
    {
        const uint64_t previous = gate.fetch_sub(1, std::memory_order_acq_rel);
        if ((previous & kCountMask) == 1) gate.notify_all();
    }

    void DeactivateAndDrain() noexcept
    {
        // The closed bit and count share one atomic word: after fetch_or publishes kClosed,
        // TryEnter can no longer increment, so observing count==0 is a stable drain point.
        gate.fetch_or(kClosed, std::memory_order_acq_rel);
        for (uint64_t current = gate.load(std::memory_order_acquire);
             (current & kCountMask) != 0;
             current = gate.load(std::memory_order_acquire))
        {
            gate.wait(current, std::memory_order_acquire);
        }
    }
};

// RAII keeps the in-flight count balanced even if callback work throws.
struct EventCallbackLease
{
    explicit EventCallbackLease(const std::weak_ptr<EventLifetimeState>& weak) noexcept
    {
        auto candidate = weak.lock();
        if (candidate && candidate->TryEnter()) state = std::move(candidate);
    }
    ~EventCallbackLease() { if (state) state->Leave(); }
    EventCallbackLease(const EventCallbackLease&) = delete;
    EventCallbackLease& operator=(const EventCallbackLease&) = delete;
    explicit operator bool() const noexcept { return static_cast<bool>(state); }

    std::shared_ptr<EventLifetimeState> state;
};

class HistoryWatcher
{
public:
    // Idempotent, and staged: if a later registration fails, the earlier ones are revoked
    // explicitly before returning.
    bool Start()
    {
        // A previous Stop() left at least one handler registered. Registering again would
        // stack a second handler on top of the live one, so restarting is refused until
        // Stop() fully succeeds.
        if (revokePending_) { DLog(TAG, L"[Start] refused: revoke still pending"); return false; }
        if (started_) return true;

        std::shared_ptr<EventLifetimeState> lifetime;
        try
        {
            lifetime = std::make_shared<EventLifetimeState>();
            const std::weak_ptr<EventLifetimeState> weakLifetime = lifetime;

            // Store each token in the member immediately. If a later registration fails,
            // rollback failure must leave the token reachable for a subsequent Stop retry.
            history_ = Clipboard::HistoryChanged([weakLifetime](auto const&, auto const&) {
                EventCallbackLease lease{ weakLifetime };
                if (!lease) return;
                // Fires when a NEW ITEM IS ADDED to the history (documented scope).
                // Deletions and ClearHistory are not guaranteed to raise this event, so the
                // caller must re-query GetHistoryItemsAsync after its own delete/clear calls.
            });
            historyEnabled_ = Clipboard::HistoryEnabledChanged(
                [weakLifetime](auto const&, auto const&) {
                    EventCallbackLease lease{ weakLifetime };
                    if (!lease) return;
                    /* Settings toggled clipboard history */
                });
            roaming_ = Clipboard::RoamingEnabledChanged(
                [weakLifetime](auto const&, auto const&) {
                    EventCallbackLease lease{ weakLifetime };
                    if (!lease) return;
                    /* Settings toggled cross-device sync */
                });
        }
        catch (...)
        {
            DFLog(TAG, L"[Start] registration failed. err=%lu", ClassifyWinRtException());
            if (lifetime) lifetime->DeactivateAndDrain();

            // Roll back every registration that succeeded. Removal lambdas select the
            // event-token overload explicitly; taking &Clipboard::HistoryChanged is
            // ambiguous because the projected class exposes multiple overloads.
            bool allRevoked = true;
            allRevoked &= TryRevoke(
                [](winrt::event_token const& token) { Clipboard::HistoryChanged(token); },
                history_, L"HistoryChanged");
            allRevoked &= TryRevoke(
                [](winrt::event_token const& token) { Clipboard::HistoryEnabledChanged(token); },
                historyEnabled_, L"HistoryEnabledChanged");
            allRevoked &= TryRevoke(
                [](winrt::event_token const& token) { Clipboard::RoamingEnabledChanged(token); },
                roaming_, L"RoamingEnabledChanged");

            // If rollback itself failed, the surviving member tokens remain retryable.
            // Their callbacks are harmless because their lifetime state is already inactive.
            started_ = !allRevoked;
            revokePending_ = !allRevoked;
            if (allRevoked) lifetime_.reset();
            else            lifetime_ = std::move(lifetime);
            return false;
        }

        lifetime_ = std::move(lifetime);
        started_ = true;
        lifetime_->Activate(); // publish the fresh generation only after every registration commits
        return true;
    }

    // Each revocation is attempted independently, and a token is cleared ONLY when its own
    // revocation succeeded — so a retry re-attempts exactly the ones that are still live.
    bool Stop() noexcept
    {
        // Disable callbacks and wait for every callback that already entered to leave before
        // the first ABI removal. Stop must be invoked by the owner, never from inside one of
        // these callbacks (a callback requests shutdown by posting back to the owner).
        if (lifetime_) lifetime_->DeactivateAndDrain();

        bool allRevoked = true;
        allRevoked &= TryRevoke(
            [](winrt::event_token const& token) { Clipboard::HistoryChanged(token); },
            history_, L"HistoryChanged");
        allRevoked &= TryRevoke(
            [](winrt::event_token const& token) { Clipboard::HistoryEnabledChanged(token); },
            historyEnabled_, L"HistoryEnabledChanged");
        allRevoked &= TryRevoke(
            [](winrt::event_token const& token) { Clipboard::RoamingEnabledChanged(token); },
            roaming_, L"RoamingEnabledChanged");

        // Only reach the stopped state when EVERY handler is really gone. Otherwise stay in
        // a "revoke pending" state so Stop() can be retried and Start() stays refused.
        if (allRevoked)
        {
            started_ = false;
            revokePending_ = false;
            lifetime_.reset();
        }
        else            { revokePending_ = true; }
        return allRevoked; // false must surface in the log / shutdown gate
    }

    bool CanDestroy() const noexcept
    {
        return !started_ && !revokePending_ &&
               !history_ && !historyEnabled_ && !roaming_;
    }

    // The owning Manager MUST complete its shutdown gate before destroying this object.
    // A destructor cannot preserve retryable tokens after member storage disappears, so it
    // detects a contract violation rather than pretending a failed best-effort Stop succeeded.
    ~HistoryWatcher() noexcept
    {
        if (!CanDestroy())
        {
            DLog(TAG, L"[~HistoryWatcher] destroyed before shutdown gate completed");
            WINRT_ASSERT(false);
        }
    }

private:
    // Explicit revocation CAN fail (it crosses the ABI), unlike event_revoker::revoke().
    // Clears the token on success so the caller can retry only what is still registered.
    template <typename Remover>
    static bool TryRevoke(Remover remover, winrt::event_token& token, const wchar_t* name) noexcept
    {
        if (!token) return true;
        try
        {
            remover(token);       // e.g. Clipboard::HistoryChanged(token)
            token = {};
            return true;
        }
        catch (...)
        {
            DFLog(TAG, L"[Stop] revoke failed: %ls", name);
            return false;         // token kept: Stop() can be retried
        }
    }

    bool started_ = false;
    bool revokePending_ = false;
    winrt::event_token history_{};
    winrt::event_token historyEnabled_{};
    winrt::event_token roaming_{};
    std::shared_ptr<EventLifetimeState> lifetime_;
};
```

**in-flight イベントの寿命保護**

C++/WinRT の公式ガイダンスは、解除後（デストラクタ実行中を含む）でも**進行中のイベントコールバックが到着し得る**と注意している。ハンドラが Manager の `this` を捕捉していると、解除して破棄しただけでは use-after-free になる。

- `Start()` ごとに閉じた `EventLifetimeState` を作り、ハンドラは `this` を直接捕捉せず **`weak_ptr`** を値で捕捉する。全3登録の commit 後にだけ gate を開くため、登録途中の callback は副作用を持たない。
- callback は `EventCallbackLease` で入退場を計数する。`Stop()` と登録途中の rollback は ABI 解除より先に gate を閉じ、すでに入場した callback が全て退出するまで待つ。
- `Stop()` を callback 自身から直接呼ぶと自己待機になるため禁止し、callback からの停止要求は owner へ post して callback 復帰後に処理する。
- 再 `Start()` は新しい state を発行するため、旧世代が再び有効になることはない。
- shutdown gate 完了時に副作用領域へ入場済みの旧 callback が残っておらず、遅延到着した旧 callback は no-op、再 `Start()` 後の新 callback だけが動作することをテストする（D-21 / D-34）。

参照: [Handle events by using delegates in C++/WinRT](https://learn.microsoft.com/en-us/windows/apps/develop/cpp-winrt/handle-events)

### WinRT: 履歴・同期を制御したコピー（S-11 の WinRT 版）

```cpp
// Internal UI-thread-only helper. Public arbitrary-thread callers use the UI-dispatched
// request/callback Bridge; InvokeWinRt only normalizes exceptions from this synchronous call.
DWORD WinRtCopySensitive(const winrt::hstring& secret)
{
    return InvokeWinRt([&] {
        DataPackage package;
        package.SetText(secret);

        ClipboardContentOptions options;
        options.IsAllowedInHistory(false); // keep out of clipboard history
        options.IsRoamable(false);         // do not sync to other devices

        // false only means "not successful": no reason is defined by the docs.
        return Clipboard::SetContentWithOptions(package, options)
            ? CLIPBOARD_ERROR_NONE : CLIPBOARD_ERROR_UNKNOWN;
    });
}
```

---

## 要検証事項

| 項目 | 内容 |
|---|---|
| サンプルコードのビルド確認 | 本書のサンプルはコンパイル確認をしていない。実装工程で **1 つの検証用翻訳単位**として `WindowsLibrary` にてビルドし（前方宣言・ヘッダ・言語規格の整合を含む）、失敗系（メモリ確保失敗・不正データ）の単体テストを追加する |
| WinRT サンプルの言語規格 | 確定方針は `/std:c++20` のコルーチン版。標準コルーチンを使わない構成へ変更する場合も、C++17 の UI `Completed` handler 版で同じ非同期 callback Bridge を維持できること |
| 明示解除の失敗条件 | `Clipboard::HistoryChanged(token)` 等の明示解除が実際に失敗し得るか（失敗する HRESULT があるか）。失敗しないなら shutdown gate の再試行ロジックを簡素化できる |
| in-flight コールバックの到着 | 解除後に実際にコールバックが到着し得るか。世代番号 / weak reference による保護の必要性を実機確認する |
| 履歴イベント登録の rollback 失敗 | 2 件目・3 件目の登録失敗に加えて、それ以前の token 解除も失敗させる。token がメンバーに保持され、`Start()` が拒否され、後続の `Stop()` で再試行できること |
| 履歴イベントの停止後再開 | `Stop()` と競合する旧世代 callback が no-op になり、再 `Start()` で作られた新世代 callback だけが動作すること |
| in-flight callback のドレイン | callback が gate へ入場した直後に別スレッドから `Stop()` を開始し、callback の退出前には `Stop()` が完了せず、完了後の in-flight 数が 0 になること。callback 自身から `Stop()` を直接呼ばない契約も確認する |
| メッセージ専用ウィンドウでの `WM_CLIPBOARDUPDATE` | `HWND_MESSAGE` で作成したウィンドウに `AddClipboardFormatListener` の通知が確実に届くか。届かない場合は非表示のトップレベルウィンドウに切り替える |
| 遅延レンダリング予約の成否判定 | `SetLastError(ERROR_SUCCESS)` + `GetClipboardOwner` + `IsClipboardFormatAvailable` の組み合わせが実機で正しく成否を弁別できるか。特に `CloseClipboard` 前の `IsClipboardFormatAvailable` の挙動 |
| `OpenClipboard` 失敗時のエラーコード | 公式に規定がないため、他プロセス排他時に実際に返る `GetLastError` 値を実測する（`ERROR_ACCESS_DENIED` は代表例であり断定しない） |
| `OpenClipboard` リトライ方針 | 実運用で妥当な回数・間隔。他アプリとの競合頻度を実測して決める |
| 管理者権限実行時の監視 | UIPI により、昇格プロセス / 非昇格プロセス間で `WM_CLIPBOARDUPDATE` の受信可否が変わるか |
| 未パッケージでの WinRT 履歴 API | `GetHistoryItemsAsync` / `SetHistoryItemAsContent` が未パッケージ Win32 で `AccessDenied` を返さないか（公式の identity 必須一覧には含まれないが実機確認する） |
| WinRT `Clipboard` のフォアグラウンド要件の実挙動 | Unity 経由の非 UI スレッド要求を所有 UI スレッドへ配送した場合に、MFC の STA 上で開始した非同期操作が `co_await` 後も正しく再開し、フォアグラウンド喪失時は Domain エラーになること |
| 非同期 Bridge の成立確認 | 履歴 API と、任意スレッド公開が必要な同期 WinRT Clipboard helper の双方が pending + callback 契約を通ること。非 UI スレッド経路では `PostMessage`、UI スレッド経路では受付前検証後の直接開始となり、MTA ワーカー + `wait_for` 経路が存在しないこと |
| Unity へのコールバックスレッド契約 | 結果を既定の UI スレッドで返すか、Unity 用 dispatcher へ切り替えるかを確定し、公開 API に明記する |
| `GetUpdatedClipboardFormats` のバッファ不足時挙動 | バッファが足りない場合に `pcFormatsOut` へ必要件数が入るか、`GetLastError` に何が入るか（公式に規定なし）。`EnumClipboardFormats` フォールバックの必要性を判断する |
| `ClearHistory` の pinned item 挙動 | pinned item を設定した状態で `ClearHistory` を呼び、残存することと戻り値を実機確認する |
| `HistoryChanged` の発火条件 | 追加時のみか、削除・`ClearHistory` でも発火するかを実機確認する（公式定義は「追加時」） |
| 遅延レンダリング予約後の形式列挙 | 予約直後（`CloseClipboard` 前 / 後）に `IsClipboardFormatAvailable` が真になるか。成否判定の前提となる |
| 遅延予約の途中失敗ロールバック | 予約途中で `EmptyClipboard` を呼んだ際に、既に予約済みの形式が確実に取り消されるか（`WM_DESTROYCLIPBOARD` の到達順も含む） |
| ロールバック用 `EmptyClipboard` の失敗条件 | 自分がクリップボードを開いて所有している状態で `EmptyClipboard` が失敗し得るか。`PARTIAL_STATE` の実発生頻度 |
| Bridge 入口の配送方式 | 所有ウィンドウのスレッドがメッセージポンプを回しているか（Unity ホストの場合）。専用スレッド + メッセージループが必要か |
| `PARTIAL_STATE` からの回復可否 | 遅延予約のロールバック失敗後、`RecoverFromPartialState()` の再 `EmptyClipboard` が実際に成功するか。回復不能な条件があるか |
| 残存予約への `WM_RENDERFORMAT` | ロールバック失敗後に残った遅延形式へ実際に `WM_RENDERFORMAT` が届くか（テーブル保持の必要性の裏付け） |
| フォアグラウンド判定の方法 | `GetForegroundWindow` と自プロセスの比較で WinRT `Clipboard` のフォアグラウンド要件を事前判定できるか。満たさない場合の挙動（例外 / 無視 / 失敗） |
| `E_OUTOFMEMORY` の送出形態 | 履歴 API で実際に `std::bad_alloc` として送出されるか、`hresult_error` として届くか |
| `CF_HTML` の受け側互換性 | Word / ブラウザ / メモ帳など主要アプリで貼り付けが崩れないか（`Version:1.0` とオフセット計算の検証） |
| `Flush()` の必要性 | 実データを即時配置する実装で、プロセス終了後にも内容が残ることの確認（残るなら `Flush` は不要） |
| Unity プラグイン層の HWND 取得 | 監視・書き込み用ウィンドウを toolkit 側で生成するか、Unity のメインウィンドウを使うか |
| URI / 複数 Item のクロスプラットフォーム方針 | Android の `content://` URI・複数 Item を Windows でどう表現するか（公開 API を共通化するか OS 別に分けるか） |

---

## Definition of Done

In scope（S-01〜S-20）と相互にトレーサビリティを持つ（1 つの Scope に複数の DoD が対応する場合がある）。

| No | 項目 | 対応 In scope |
|---|---|---|
| D-01 | プレーンテキスト（`CF_UNICODETEXT`）のコピーが動作し、他アプリで貼り付けられる | S-01 |
| D-02 | プレーンテキストのペーストが動作する | S-01 |
| D-03 | HTML（`CF_HTML`）のコピーが動作し、Word・ブラウザで書式が保持される | S-02 |
| D-04 | HTML のペーストが動作し、`StartHTML` / `EndHTML` / `StartFragment` / `EndFragment` を符号・桁・変換オーバーフロー込みで解析し、`0 <= StartHTML <= StartFragment <= EndFragment <= EndHTML <= payloadSize` を検証したうえで**フラグメントのみ**を返す（`StartHTML = EndHTML = -1` のコンテキストなしケースも扱える） | S-02 |
| D-05 | ファイル一覧（`CF_HDROP`）のコピーが動作し、エクスプローラーに貼り付けられる | S-03 |
| D-06 | エクスプローラーでコピーしたファイル一覧のペーストが動作する | S-03 |
| D-07 | 画像（`CF_DIB`）のコピーが動作し、ペイント等に貼り付けられる | S-04 |
| D-08 | 画像（`CF_DIB`）のペーストが動作し、`CF_BITMAP` のみの供給元からも合成経由で取得できる。**`ValidateDib`（ヘッダサイズ / planes / bitCount / compression / パレット・マスク / stride / ピクセル範囲）を通過したデータのみ受け入れる** | S-04 |
| D-09 | 独自フォーマットのコピーが動作する | S-05 |
| D-10 | 独自フォーマットのペーストが動作し、未登録・不一致時にエラーを返す | S-05 |
| D-11 | 複数フォーマットの同時配置が動作し、情報量の多い形式が優先して貼り付けられる。**途中の配置失敗時に best-effort rollback が働き、ロールバック失敗時は `PARTIAL_STATE` を返す**（ロールバック失敗を注入するテストを含む） | S-06 |
| D-12 | `IsClipboardFormatAvailable` / `GetUpdatedClipboardFormats` / `GetPriorityClipboardFormat` / `GetClipboardFormatName` による内容確認が動作する。標準形式と登録形式の名前解決が両方できる。`GetUpdatedClipboardFormats` 失敗時に `EnumClipboardFormats` へフォールバックする。**`CountClipboardFormats` の 0 を空／失敗に、`EnumClipboardFormats` の 0 を終了／失敗に `GetLastError` で弁別し、列挙途中の失敗では部分結果を返さない** | S-07 |
| D-13 | `EmptyClipboard` によるクリアが動作する | S-08 |
| D-14 | `AddClipboardFormatListener` による変更監視が登録・解除でき、解除後に通知が来ない（リークなし） | S-09 |
| D-15 | 監視の登録・解除の失敗が Domain エラーおよびログに反映される。**解除失敗時は登録状態を保持して再試行でき、解除成功を確認するまでウィンドウを破棄しない**（解除失敗を注入するテストを含む） | S-09 |
| D-16 | 自プロセスの書き込みによる通知ループが発生しない（監視状態は `static` でなくインスタンス保持） | S-09 |
| D-17 | 遅延レンダリングが動作し、予約の成否を判定できる。**複数形式・独自形式を予約した場合に `WM_RENDERALLFORMATS` で未生成の全形式が配置される**。`WM_RENDERFORMAT` の未登録形式、Renderer / `SetClipboardData` の失敗、所有者喪失がログとエラーに反映される。Renderer が `HGLOBAL` 形式に限定されている | S-10 |
| D-18 | `CanIncludeInClipboardHistory` = 0 / `CanUploadToCloudClipboard` = 0 で Win+V の履歴に残らない | S-11 |
| D-19 | `GetHistoryItemsAsync` / `SetHistoryItemAsContent` による履歴取得・復元が動作し、**UI スレッドをブロックせずに完了結果を受け取れる**（スレッドモデル節の方針どおり） | S-12 |
| D-20 | `DeleteItemFromHistory` による履歴項目削除と `ClearHistory` による未固定履歴の消去が動作する。**`ClearHistory` 後も pinned item が残ることを確認**し、公開 API 名・マニュアル文言が「未固定項目の消去」になっている | S-13 |
| D-21 | `HistoryChanged` / `HistoryEnabledChanged` / `RoamingEnabledChanged` を **`event_token` による明示解除**で購読・解除でき、解除後に新規通知が来ない。**多重 `Start` でハンドラがリークしない**。**登録途中の失敗で登録済みハンドラが巻き戻り、rollback の解除まで失敗した場合は token をメンバーに保持して `Start` を拒否し、`Stop` で再試行できる**。解除処理・デストラクタが `noexcept` を維持し、解除例外が境界を越えない。callback gate は全登録の commit 後にだけ開き、**`Stop` は gate を閉じて副作用領域へ入場済みの callback をドレインする。遅延到着した旧世代 callback は no-op となり、再 `Start` の新世代 callback だけが動作する**。自身の削除・消去後はイベントに頼らず再取得する | S-14 |
| D-22 | `IsHistoryEnabled()` / `IsRoamingEnabled()` による事前判定とフォールバック（履歴 UI の無効化等）が動作する | S-15 |
| D-23 | **未パッケージ Win32 ビルドで S-01〜S-15 が全て動作する**（Windows App SDK の初期化なしで動くこと） | S-16 |
| D-24 | MSIX パッケージ済みビルドでも同一挙動になる | S-16 |
| D-25 | Domain エラー対応表の全種別が実装され、`OpenClipboard` 失敗・メモリ確保失敗・アクセス拒否・履歴無効・履歴項目削除済み・監視登録失敗を弁別して返す。**同期境界と非同期境界の双方に共通ラッパがあり、`co_await` 後に発生した例外も Domain エラーへ変換される**。`std::bad_alloc` が `OUT_OF_MEMORY` に分類される。全 WinRT 公開境界（`SetContentWithOptions` を含む）がラッパを経由する | S-17 |
| D-26 | 未知の `GetLastError` / `HRESULT` が `UNKNOWN` として保持され、生値がログに残る。**`DeleteItemFromHistory` / `ClearHistory` の `false` を `ACCESS_DENIED` と誤って報告しない**。履歴ステータスの変換が共通関数に集約され、`AccessDenied` を `HISTORY_DISABLED` に潰さない | S-17 |
| D-27 | 全ての確保・ロック・登録 API（`GlobalAlloc` / `GlobalLock` / `RegisterClipboardFormat` / `SetClipboardData`）の戻り値を確認し、所有権移譲前のハンドルが確実に解放される（リーク・二重解放なし） | S-18 |
| D-28 | 境界検証規則（サイズ・終端 NUL・構造体サイズ・オフセット・加算オーバーフロー）が**読み取りパスと書き込み側サイズ計算の双方**に実装され、共通の checked 演算ユーティリティを経由している。**不正データを与える失敗系の単体テストが通る** | S-18 |
| D-29 | MFC × C++/WinRT のヘッダ順序を守った状態でビルドが通り、**本書のサンプルコードがコンパイル確認済みである**（非同期ヘルパの戻り値型が `ClipboardResult<T>` / `ClipboardStatus` に統一され、共通ラッパへ渡せること。コルーチンを採用する場合は `/std:c++20`、しない場合は `/std:c++17`） | S-19 |
| D-30 | 純ロジック（`CF_HTML` ヘッダ生成 / ヘッダ解析、`DROPFILES` 構築・検証、DIB 構造検証、フォーマット優先度判定、checked 演算）に WinRT / Win32 非依存の単体テストがある。**`CF_HTML` は必須キー欠落・既知キー重複・不正値（`-10` / `123x`）・ヘッダ範囲外の既知キー・`Version` の空値／不明値・`StartHTML` がヘッダ内を指す入力・キー順を入れ替えた入力・`StartSelection` / `EndSelection` の片側のみ／不正値／範囲外・フラグメント自身がマーカー文字列を含むケースを個別にテストする。`ValidateDib` も不正な planes / bitCount / compression / stride 超過を個別にテストする** | S-02, S-03, S-04, S-07, S-18 |
| D-31 | **非 UI スレッドから Bridge を呼んでも WinRT Clipboard 操作が正しく動作する**（所有 UI スレッドへ `PostMessage` で配送され、`SendMessage` によるデッドロックがない）。WinRT 履歴の非同期 API は UI スレッドで開始して `co_await` し、MTA ワーカー + `wait_for` 経路が存在しない。同期 WinRT helper も公開 Bridge から直接呼ばず同じ UI 配送を通す。フォーカス確認・キャンセル・完了 callback のスレッドが公開 API に明記されている。ホスト所有 UI スレッドのアパートメントは初期化も解除もせず、toolkit が専用 UI スレッドを作る場合だけそのスレッド内で `init_apartment(single_threaded)` / `uninit_apartment()` を対にする。`DllMain` / `InitInstance` ではアパートメントを固定していない | S-20 |
| D-32 | `Reserve` が Domain 結果を返し、**「成功」「ロールバック成功」「ロールバック失敗（`PARTIAL_STATE`）」の 3 状態遷移**をテストできる。ロールバック失敗時は Renderer テーブルが保持され、残存形式の `WM_RENDERFORMAT` に応答できる。`RecoverFromPartialState()`（**引数を取らず保存済み `owner_` のみを使う**）で回復でき、`WM_DESTROYCLIPBOARD` でも解放される（予約の各段階での失敗注入テストを含む） | S-10 |
| D-33 | **受付成立（pending 登録に加え、非 UI スレッド経路では UI キュー投入、UI スレッド経路では受付前検証後の直接開始への引き渡しが成功）を境界として、受付前の失敗は同期戻り値のみ（コールバック 0 回）、受付後の全終端状態はコールバックちょうど 1 回**という契約が実装され、Bridge の戻り値・リクエスト ID の有効条件と一致している。UI キュー投入後のフォアグラウンド不成立はコールバックで `ACCESS_DENIED` 相当を返し、要求を保留しない。**コールバックが例外を投げてもプロセスが終了しない**。`Uninit` が pending をドレインし、以降の完了でコールバックが呼ばれない。キャンセルと完了の競合が pending テーブルの取り出しで排他される。**全リクエスト種別が共通の `CompletePendingRequest` を経由する** | S-20 |
| D-34 | 終了シーケンス（shutdown gate）が実装され、**`ClipboardWatcher::Stop()` / `HistoryWatcher::Stop()` の成功前に `DestroyWindow` と `HistoryWatcher` の破棄が行われない**。`HistoryWatcher::Stop()` が callback gate を閉じて副作用領域の in-flight 数を 0 までドレインした後、3イベントの**明示解除**を個別に試み、**成功した token のみクリアして失敗分を再試行できる**。一部でも解除に失敗した場合は停止状態へ遷移せず、その間の `Start()` を拒否する（通常停止と登録途中 rollback の双方で解除失敗を注入する状態遷移テストを含む）。callback 自身は `Stop()` を直接呼ばず owner へ停止要求を post する。**shutdown gate 完了後の遅延到着 callback は no-op であり、破棄前に `CanDestroy()` が true である** | S-09, S-14, S-20 |
| D-35 | 公開 Bridge から見える WinRT 操作がすべて `ClipboardResult<T>` に統一されている。UI スレッド上の内部同期 helper は `InvokeWinRt`、`co_await` を含む helper は `InvokeWinRtAsync` で例外を正規化する。**`InvokeWinRt` はスレッド配送を担わず**、任意スレッド公開される `WinRtCopyText` / `ClearUnpinnedHistory` / `SetContentWithOptions` も pending + callback 契約を経由する。非 UI スレッド経路では `PostMessage`、UI スレッド経路では受付前検証後に直接開始する | S-17 |
| D-36 | VC++ サンプルアプリで S-01〜S-15 の全サブ機能を手動確認できる | 全体 |

補足: workflow の「`Setting()` プロパティによるフォールバック判定を DoD に含める」は通知機能（`AppNotificationManager.Setting`）固有のルールであり、クリップボードには該当 API が存在しない。クリップボードにおける等価な可用性判定は `Clipboard::IsHistoryEnabled()` / `IsRoamingEnabled()` と `ClipboardHistoryItemsResultStatus` であり、D-22 に含めている。

### テスト確認 Windows バージョン

2026-07-27 時点の [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information) に基づく。

| バージョン（ビルド） | 位置づけ | サポート状況 | テスト対象 |
|---|---|---|---|
| 25H2（26200） | 既存デバイス向けの最新 GA リリース（2025-09-30 提供開始） | Home/Pro 2027-10-12 まで、Enterprise/Education 2028-10-10 まで | **主要ターゲット（必須）** |
| 24H2（26100） | 前世代。Home/Pro は 2026-10-13 で更新終了 | Home/Pro 2026-10-13 まで、Enterprise/Education 2027-10-12 まで | **必須**（回帰確認） |
| 26H1（28000） | 2026 年初頭以降の**新規デバイス専用**。既存デバイスへの機能更新としては提供されない（24H2 / 25H2 からのインプレース更新なし） | Home/Pro 2028-03-14 まで、Enterprise/Education 2029-03-13 まで（IoT Enterprise は非対応） | **製品方針として要判断**。新規デバイス向け出荷を想定するなら対象に含める |
| 23H2（22631） | Home / Pro / Pro Education / Pro for Workstations は更新終了済み。Enterprise / Education / IoT Enterprise のみ 2026-11-10 まで | エディション依存 | **対象に含める場合は Enterprise / Education エディションに限定**。Home/Pro は対象外 |

Windows 11 22H2 以前（21H2 / 22H2）は更新終了済みのため対象外とする。

### テスト確認 Package Identity

| 構成 | 理由 |
|---|---|
| 未パッケージ Win32（VC++ サンプルアプリ） | 主要ターゲット。Package Identity なしで全コア機能が動くことの確認 |
| MSIX パッケージ済み | 同一挙動であることの確認 |
| 管理者権限実行（未パッケージ） | UIPI 影響下での変更監視の挙動確認（要検証事項） |
