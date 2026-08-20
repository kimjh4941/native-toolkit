# Windows クリップボード サンプルアプリ 実装計画 v5

## 基本情報

- 日付: 2026-07-31
- 機能名: Windows Clipboard Manager
- 対象 OS: Windows 11 以降
- 対象サンプル: `windows/WindowsLibraryExample`（WinUI 3 / C++/WinRT / MSIX）
- 機能設計: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- 実装結果: `artifact/results/clipboard/2026-07-30-windows-clipboard-implementation-feature-result-v4.md`
- 前版: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v4.md`
- 対応レビュー: `artifact/reviews/clipboard/2026-07-31-windows-clipboard-sample-app-design-review-v4.md`
- ブランチ: `feature/NTKIT-13`
- 対応タスク: 機能設計 T-19

---

## 0. v4 からの変更点

| 指摘 | v5 の対応 |
|---|---|
| H1: anonymous namespace の型を `.xaml.h` で参照できない | `WorkerResult` / `WorkerOutcome` / `WorkerPrecondition` を `ClipboardPage` implementation class の private nested type にする |
| H2: `get_weak()` の型が誤っている | `auto weakPage = get_weak()` とし、`weakPage.get()` が返す implementation strong referenceから private completion を直接呼ぶ。`get_self` は使わない |
| H3: null-managed `shared_ptr` の真偽判定が誤っている | 非 null の `std::shared_ptr<BusyLease>` を作り、header 境界では `std::shared_ptr<void>` として渡す。生成成否は token の真偽値で正しく判定できる |
| M1: OOM catch 内で文字列 allocation が起こる | worker exception は allocation 不要の `WorkerOutcome` へ変換する。busy 解除は結果表示と独立して保証する |
| M2: 二重 Init を実際に確認していない | InitializeManager は `Uninitialized` と `Ready` で Bridge を呼び、`ShuttingDown` のみ拒否する |
| M3: 「全面直列化」が pending WinRT request を含むように読める | 相互排他の範囲を「同期 worker と新規 UI API の開始」に限定。依存操作は request callback を待ってから実行する |
| L1: busy 中 CanDestroy の期待が曖昧 | `Ready` + worker in-flight では `FALSE + NONE` と明記 |

### 0.1 v5 で確定する実装判断

- `ClipboardPage::get_weak()` は `winrt::weak_ref<implementation::ClipboardPage>` を返す。型は `auto` で受け、promotion 後は implementation memberを直接呼ぶ
- page helper の引数・戻り値に使う独自型は `.xaml.h` の implementation class 内へ置く
- busy の解除責務は `BusyLease` の destructorだけが持つ
- OOM 時に UI エラー文言を必ず表示することは保証しない。ページが生存していれば表示を試みるが、必須保証は busy 解除である
- pending の履歴 request は `g_workerBusy` の対象外。Restore / Delete / Clear / Availability などの結果に依存する次操作は callback 後に行う

---

## 1. 対象機能と公開 API

### 1.1 サンプルで確認する機能

| No | 機能 | 確認方法 |
|---|---|---|
| F-01 | text copy / paste | ボタン + 結果 |
| F-02 | HTML copy / paste | ボタン + Word / browser / Notepad |
| F-03 | file list copy / paste | temp file + Explorer |
| F-04 | DIB copy / paste | 8x8 DIB + Paint |
| F-05 | custom format | 固定 payload |
| F-06 | multiple formats | 正常系 + validation error |
| F-07 | has / enumerate / preferred | ボタン + 結果 |
| F-08 | clear | ボタン |
| F-09 | change monitoring | callback log |
| F-10 | deferred rendering | provider log + external paste |
| F-11 | history / roaming exclusion | Win+V + 別 device |
| F-12 | history API / events | asynchronous callback log |
| F-13 | Package Identity | MSIX 実行 |
| F-14 | normalized errors | error-case buttons |
| F-17 | thread / lifecycle | state、worker、shutdown buttons |

### 1.2 API の実行区分

UI thread から直接呼ぶ:

- `initClipboardManager`
- `setClipboardHistoryCallbacks`
- `uninitClipboardManager`
- `canDestroyClipboardManager`
- `reserveDeferredFormats`
- `recoverDeferredState`
- `getClipboardHistory`
- `restoreHistoryItem`
- `deleteHistoryItem`
- `clearUnpinnedHistory`
- `getClipboardHistoryAvailability`
- `cancelClipboardRequest`

worker から呼ぶ:

- `copyPlainText` / `pastePlainText`
- `copyHtml` / `pasteHtml`
- `copyFiles` / `pasteFiles`
- `copyImage` / `pasteImage`
- `copyCustomFormat` / `pasteCustomFormat`
- `copyMultipleFormats`
- `hasClipboardFormat`
- `getClipboardFormats`
- `getPreferredClipboardFormat`
- `clearClipboard`
- temp file I/O
- Threading 検証用の owner-thread API

### 1.3 主要な公開契約

- Init を呼んだ STA UI thread が owner thread になる。その thread は message pump を継続する
- owner UI thread の Uninit が `FALSE` を返した場合も lifecycle gate は閉じる
- pending がある最初の Uninit は `FALSE + CANCELED`。callback 配送後に再度 Uninit して `TRUE` を得る
- worker thread の Uninit は Ready の場合に `FALSE + WRONG_THREAD`
- buffer API は size query と fill の2回呼び出し
- request callback の JSON は callback 中だけ有効なので thunk 内でコピーする
- deferred provider の query size と fill size は完全一致させる
- provider 内で clipboard API、XAML、blocking operation、例外送出を行わない
- callback function pointer と provider context は契約期間中有効に保つ

### 1.4 エラー表示

- Bridge error は `errorCode=<n>` として表示する
- sample-side validation / exception は `Sample operation failed: <reason>` として別区分にする
- `NOT_INITIALIZED` は manager state で文言を分ける
  - `Uninitialized`: `Press InitializeManager first.`
  - `ShuttingDown`: `Press CanDestroy, then Uninitialize again.`
- `CANCELED`、`WRONG_THREAD`、`HISTORY_DISABLED`、`NOT_FOREGROUND`、`WRONG_APARTMENT` には英語の補足を付ける
- 全 UI 文言、ログ、コメントは英語にする

---

## 2. 既存サンプルとの整合

### 2.1 再利用

- `MainMenuPage` の card と `NavigateTo`
- `NotificationPage` の Back、title、result、category buttons、callback forwarding hub
- `NotificationButtonStyle`
- `DLog` / `DFLog`
- `DispatcherQueue::TryEnqueue`
- weak UI reference と `OnNavigatedTo` / `OnNavigatedFrom`

macOS sample に Clipboard 画面がないため、画面構成は Windows の `NotificationPage` を正本とする。カテゴリ分割のみ Android Clipboard sampleを参考にする。

### 2.2 変更ファイル

新規:

- `windows/WindowsLibraryExample/ClipboardPage.xaml`
- `windows/WindowsLibraryExample/ClipboardPage.xaml.h`
- `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp`
- `windows/WindowsLibraryExample/ClipboardPage.idl`
- `artifact/results/clipboard/YYYY-MM-DD-windows-clipboard-implement-sample-app-result-v1.md`

既存変更:

- `windows/WindowsLibraryExample/MainMenuPage.xaml`
- `windows/WindowsLibraryExample/MainMenuPage.xaml.h`
- `windows/WindowsLibraryExample/MainMenuPage.xaml.cpp`
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj`

変更しない:

- `windows/WindowsLibrary`
- `windows/UnityWindowsPlugin`
- `windows/WindowsLibraryExample/App.xaml*`
- `windows/WindowsLibraryExample/MainWindow.xaml*`
- `windows/WindowsLibraryExample/Package.appxmanifest`
- `windows/WindowsLibraryExample/WindowsLibraryExample.vcxproj.filters`
- `windows/WindowsLibraryExample/WindowsLibraryExample.sln`

---

## 3. 画面要件

### 3.1 画面骨格

```text
MainMenuPage
  Clipboard Example

ClipboardPage
  Back
  WindowsClipboardManager Example
  ResultTextBlock: latest result + manager state
  LogTextBlock: callback/provider/worker log, max 200 lines
  ScrollViewer
    Init / Lifecycle
    Copy
    Write Options
    Paste
    Inspect / Clear
    Deferred Rendering
    History
    Threading
    Error cases
```

### 3.2 ボタン一覧

Init / Lifecycle:

- InitializeManager
- SetHistoryCallbacks
- Uninitialize
- CanDestroy

Copy / Write Options:

- CopyPlainText
- CopyPlainText (empty)
- CopyHtml
- CopyFiles
- CopyImage
- CopyCustomFormat
- CopyMultipleFormats
- CopyMultipleFormats (with image)
- CopyPlainText (SENSITIVE)
- CopyPlainText (EXCLUDE_HISTORY)
- CopyPlainText (EXCLUDE_ROAMING)
- Cleanup Temp Files

Paste / Inspect:

- PastePlainText
- PasteHtml
- PasteFiles
- PasteImage
- PasteCustomFormat
- HasFormat (CF_UNICODETEXT)
- GetClipboardFormats
- GetPreferredFormat
- ClearClipboard

Deferred / History:

- ReserveDeferredFormats
- RecoverDeferredState
- GetHistoryAvailability
- GetClipboardHistory
- RestoreHistoryItem (last id)
- DeleteHistoryItem (last id)
- ClearUnpinnedHistory
- CancelLastRequest
- Request + Immediate Uninitialize

Threading / Error:

- ReserveDeferred (worker thread)
- Uninitialize (worker thread)
- Delayed Worker Check
- CopyPlainText (null)
- PastePlainText (after Clear)
- PasteHtml (text only)
- PasteImage (size query only)
- CopyMultipleFormats (CF_BITMAP)
- CopyMultipleFormats (duplicate format)
- CopyMultipleFormats (CF_DIB + text)
- CopyFiles (empty array)
- CopyPlainText (after Uninitialize)
- Force Initialize while shutting down
- CancelClipboardRequest (unknown id)

---

## 4. Manager state と precondition

### 4.1 状態

```cpp
enum class ManagerState
{
    Uninitialized,
    Ready,
    ShuttingDown,
};

std::atomic<ManagerState> g_managerState{ ManagerState::Uninitialized };
std::atomic<bool> g_workerBusy{ false };
```

| 状態 | 意味 | 主な許可操作 |
|---|---|---|
| `Uninitialized` | Init 前または Uninit 完了後 | Initialize、Cleanup、未初期化 error test |
| `Ready` | gate open | 通常操作 |
| `ShuttingDown` | owner UI Uninit 後、teardown 未完了 | CanDestroy、Uninitialize retry、Force Initialize、Cleanup |

### 4.2 遷移

| 契機 | 条件 | 遷移 |
|---|---|---|
| Initialize | state = Uninitialized、error = NONE | Ready |
| Initialize | state = Ready、error = NONE | Ready（Bridge の冪等性確認） |
| Initialize | state = ShuttingDown | 通常ボタンでは Bridge を呼ばず維持 |
| Force Initialize | state = ShuttingDown | Bridge は NONE、state は維持 |
| Uninitialize (UI) | return TRUE | Uninitialized |
| Uninitialize (UI) | return FALSE | ShuttingDown |
| Uninitialize (worker) | FALSE + WRONG_THREAD | Ready のまま |

### 4.3 precondition

`WorkerPrecondition` は `ClipboardPage` の private nested enum とする。

```cpp
enum class WorkerPrecondition
{
    ReadyRequired,
    AnyState,
    ShuttingDownRequired,
    NoStateGuard,
};
```

- `ReadyRequired`: 通常 APIと Threading 検証
- `AnyState`: Cleanup
- `ShuttingDownRequired`: Force Initialize
- `NoStateGuard`: CopyPlainText after Uninitialize

Initialize は専用 guard を使い、Uninitialized / Ready では Bridge を呼び、ShuttingDown では拒否する。

### 4.4 busy 中の操作

- 許可: CanDestroy
- 拒否: Initialize、Uninitialize、SetHistoryCallbacks、Copy、Paste、Inspect、Clear、Reserve、Recover、History request、Cancel、Cleanup
- busy 判定は UI button handler の先頭で行う
- `Ready + worker in-flight` で CanDestroy は `FALSE + NONE`

この相互排他は「同期 worker の実行中に新しい UI API を開始しない」ためのもの。すでに受付済みの WinRT history request の完了までは管理しない。

---

## 5. Worker task runner

### 5.1 helper 型の配置

`WorkerOutcome`、`WorkerResult`、`WorkerPrecondition` は `.xaml.h` の implementation class 内に private nested type として定義する。anonymous namespace には置かない。

```cpp
struct ClipboardPage : ClipboardPageT<ClipboardPage>
{
    ClipboardPage();

private:
    enum class WorkerOutcome
    {
        BridgeResult,
        SampleFailure,
        SampleOutOfMemory,
        SampleWinRtFailure,
    };

    struct WorkerResult
    {
        WorkerOutcome outcome{ WorkerOutcome::SampleFailure };
        DWORD bridgeError{ 0 };
        HRESULT sampleHresult{ S_OK };
        std::wstring detail;
        std::wstring logLine;
    };

    enum class WorkerPrecondition
    {
        ReadyRequired,
        AnyState,
        ShuttingDownRequired,
        NoStateGuard,
    };

    bool CheckPrecondition(WorkerPrecondition value);
    void RunOnWorker(
        std::wstring method,
        std::function<WorkerResult()> work,
        std::shared_ptr<void> busyToken);
    void CompleteWorkerOperation(
        std::wstring const& method,
        WorkerResult const& result);
};
```

`WorkerResult` を使う anonymous helper は作らない。Bridge result の生成は private static member、または各 member handler の work lambda 内で行う。

### 5.2 busy ownership

`.cpp` の anonymous namespace に `BusyLease` を置く。

```cpp
class BusyLease final
{
public:
    ~BusyLease() noexcept
    {
        g_workerBusy.store(false);
    }
};
```

button handler:

```cpp
if (g_workerBusy.exchange(true))
{
    SetResultText(L"Busy: another clipboard operation is running");
    return;
}

std::shared_ptr<void> busyToken;
try
{
    auto lease = std::make_shared<BusyLease>(); // non-null
    busyToken = lease;

    RunOnWorker(
        L"CopyPlainText",
        [text = std::wstring(L"Hello from native-toolkit")]() -> WorkerResult
        {
            DWORD err = CLIPBOARD_ERROR_NONE;
            copyPlainText(text.c_str(), CLIPBOARD_WRITE_OPTION_NONE, &err);

            WorkerResult result;
            result.outcome = WorkerOutcome::BridgeResult;
            result.bridgeError = err;
            return result;
        },
        busyToken);
}
catch (...)
{
    if (!busyToken)
    {
        // BusyLease の生成前に失敗した場合だけ手動解除する。
        g_workerBusy.store(false);
    }
    SetResultText(L"Sample operation failed: could not start worker");
}
```

`busyToken` は non-null の `BusyLease` を所有するため、`operator bool` で control block の生成成否を判定できる。最後の token copy が破棄されると busy が解除される。

### 5.3 implementation weak reference

`RunOnWorker` は `ClipboardPage` の private member。`get_weak()` の型は明示せず `auto` で受ける。

```cpp
void ClipboardPage::RunOnWorker(
    std::wstring method,
    std::function<WorkerResult()> work,
    std::shared_ptr<void> busyToken)
{
    auto weakPage = get_weak(); // weak_ref<implementation::ClipboardPage>
    auto dispatcher = DispatcherQueue();

    winrt::Windows::System::Threading::ThreadPool::RunAsync(
        [weakPage,
         dispatcher,
         method = std::move(method),
         work = std::move(work),
         busyToken](auto&&)
        {
            WorkerResult result;
            try
            {
                result = work();
            }
            catch (std::bad_alloc const&)
            {
                result.outcome = WorkerOutcome::SampleOutOfMemory;
            }
            catch (winrt::hresult_error const& e)
            {
                result.outcome = WorkerOutcome::SampleWinRtFailure;
                result.sampleHresult = e.code();
            }
            catch (...)
            {
                result.outcome = WorkerOutcome::SampleFailure;
            }

            try
            {
                dispatcher.TryEnqueue(
                    [weakPage,
                     method = std::move(method),
                     result = std::move(result),
                     busyToken]() mutable
                    {
                        if (auto page = weakPage.get())
                        {
                            page->CompleteWorkerOperation(method, result);
                        }
                    });
            }
            catch (...)
            {
                // token destruction releases busy; no allocation or UI access.
            }
        });
}
```

保証:

- page の raw pointer / strong referenceを worker に渡さない
- `get_self` は使わない
- work、completion capture、RunAsync、TryEnqueue の失敗でも token destructionにより busy を解除する
- OOM 時は enum だけを更新し、worker catch 内で文字列を構築しない
- page が破棄済みなら UI 更新だけを捨てる
- UI failure message の表示は best effort。busy 解除は必須保証

### 5.4 completion

`CompleteWorkerOperation` は private memberで UI thread からだけ呼ぶ。

- `BridgeResult`: `ShowResult(method, bridgeError, detail)`
- `SampleFailure`: generic sample failure
- `SampleOutOfMemory`: sample OOM
- `SampleWinRtFailure`: HRESULT を表示
- `logLine` があれば `AppendLog`

UI message 構築自体が失敗しても、completion lambda の破棄で busy は解除される。

---

## 6. Buffer・provider・callback

### 6.1 二相 buffer helper

1回目:

- `buffer = nullptr`, `size = 0`
- `err == BUFFER_TOO_SMALL` の場合だけ query 成功
- `needed == 0` は empty byte payload として成功し、2回目を呼ばない

2回目:

- `needed` 分を確保
- `err == NONE`
- 戻り値が確保サイズ以下
- 再度 `BUFFER_TOO_SMALL` なら失敗。無限 retry しない

wide string用と byte用を分ける。

### 6.2 PasteImage

`BITMAPINFOHEADER` を読む前に確認する。

- returned size >= `sizeof(BITMAPINFOHEADER)`
- `biSize >= sizeof(BITMAPINFOHEADER)`
- `biSize <= returned size`

失敗時は構造体 fieldを読まず sample validation failure とする。

### 6.3 Deferred provider

- static payload mapへ予約時に完成済み bytesを格納
- `CF_UNICODETEXT`: NUL terminated UTF-16
- `HTML Format`: 完成済み CF_HTML bytes
- query / fillで同じ payloadを使用
- provider は catch-all し、例外を C boundary 外へ出さない
- provider log は UI queueへ送り、XAMLを直接触らない

### 6.4 Callback forwarding

- thunk は process lifetime の free function
- `OnNavigatedTo` で page handlerを登録
- `OnNavigatedFrom` で handlerを null
- page 離脱中の callback は UI では破棄し、復元しない
- JSON は thunk 内で `winrt::hstring` へコピーしてから queueへ渡す
- unknown request IDはログだけに出し、latest resultは変更しない

### 6.5 History request の順序

- `m_pendingRequests` で request ID と操作名を保持する
- callback 後に tableから削除する
- Restore / Delete / Clear / Availability の結果に依存する次操作は、対応 callbackを確認してから行う
- Restore callback 前に Pasteを押さない
- Delete / Clear callback 前に再取得しない
- 複数 request の受付自体は許可する
- Cancel と Uninit drain は pending 中に許可する

---

## 7. Sample data

- text: `Hello from native-toolkit`
- HTML fragment: `<b>Hello</b> from native-toolkit`
- files:
  - `%TEMP%\native-toolkit-clipboard-sample-1.txt`
  - `%TEMP%\native-toolkit-clipboard-sample-2.txt`
- DIB: 8x8、32bpp、`BI_RGB`
- custom format: `NativeToolkitSample`
- custom payload: short ASCII bytes
- multiple formats: `HTML Format` -> `CF_UNICODETEXT`、必要に応じて `CF_DIB`
- temp cleanup:
  - manual buttonは AnyState
  - Uninit TRUE後は `Uninitialize succeeded; temp cleanup pending`
  - cleanup completionは logへ `Temp cleanup succeeded/failed`
  - cleanup結果で Uninit結果を上書きしない

---

## 8. 手動確認

### 8.1 Interoperability

| 手順 | 期待 |
|---|---|
| CopyPlainText -> Notepad | 同じ text |
| CopyHtml -> Word / browser | boldを保持 |
| CopyHtml -> Notepad | fallback text |
| CopyFiles <-> Explorer | path一致 |
| CopyImage <-> Paint | 8x8 image / DIB fields |
| CopyMultipleFormats -> Word / Notepad | consumerが対応形式を選ぶ |
| text + HTML -> GetPreferredFormat | `CF_UNICODETEXT` |
| files only -> GetPreferredFormat | `CF_HDROP` |
| image only -> GetPreferredFormat | `CF_DIB` |
| custom only -> GetPreferredFormat | empty |

`getPreferredClipboardFormat` の候補は現行実装の `{CF_UNICODETEXT, CF_HDROP, CF_DIB, CF_BITMAP}` に合わせる。HTML非対応は機能側へ報告する。

### 8.2 Monitoring / Deferred

| 手順 | 期待 |
|---|---|
| Init -> external copy | change log |
| self copy | self notificationなし |
| Uninit TRUE -> external copy | notificationなし |
| Reserve -> external paste | provider query/fill log |
| Reserve -> Word paste | 要求された各形式で size一致 |
| Reserve -> enumerate | 予約形式を列挙 |
| Reserve -> app exit -> paste | `WM_RENDERALLFORMATS` により内容保持 |
| Reserve -> external copy | reservation破棄 |

### 8.3 History

| 手順 | 期待 |
|---|---|
| Availability | Windows settingと一致 |
| disabled -> GetHistory | `HISTORY_DISABLED` |
| GetHistory callback | newest first、timestamp string |
| Restore callback待機 -> Paste | restored content |
| Delete callback待機 -> GetHistory | item消失 |
| Clear callback待機 -> GetHistory | pinnedのみ残る |
| Set callbacks -> copy / setting change | event log |
| SENSITIVE -> Win+V | 表示されない |
| EXCLUDE_ROAMING -> another device | syncされない |
| GetHistory -> Cancel | CANCELEDまたは先行成功のどちらか1回 |

### 8.4 Lifecycle / Thread / Busy

| 手順 | 期待 |
|---|---|
| Initializeを2回 | 2回とも Bridgeを呼び `NONE`、state Ready |
| Request + Immediate Uninitialize | `FALSE + CANCELED`、state ShuttingDown |
| ShuttingDownで通常操作 | APIを呼ばず retry案内 |
| ShuttingDownで通常 Initialize | APIを呼ばず retry案内 |
| Force Initialize | Initは NONE、続く Copyは NOT_INITIALIZED、state維持 |
| drain callback待機 -> CanDestroy | `TRUE + NONE` |
| Uninitialize retry | `TRUE + NONE`、state Uninitialized、cleanup pending |
| cleanup完了 | logへ結果 |
| Initialize -> Copy | 再度成功 |
| Readyで worker Reserve | WRONG_THREAD |
| Readyで worker Uninit | WRONG_THREAD、state Ready |
| page Back -> re-entry | manager state維持、page logはclear |
| request -> Back -> re-entry | 離脱中 UI callbackは復元しない |
| Delayed Worker Check中に通常操作 | Busy、APIを呼ばない、UIは応答 |
| Delayed Worker Check中に CanDestroy | `FALSE + NONE` |
| Delayed Worker Check -> Back -> re-entry | 5秒間 Busyを維持 |
| Delayed Worker Check完了 | busy解除、次操作可能 |

### 8.5 Error cases

| ケース | 期待 |
|---|---|
| null text | INVALID_PARAMETER |
| Paste after Clear | FORMAT_UNAVAILABLE |
| PasteHtml with text only | FORMAT_UNAVAILABLE |
| image size query | BUFFER_TOO_SMALL + needed |
| CF_BITMAP in multiple | INVALID_PARAMETER |
| duplicate format | INVALID_PARAMETER |
| CF_DIB + text payload | INVALID_PARAMETER |
| empty file array | INVALID_PARAMETER |
| Copy after Uninit | NOT_INITIALIZED |
| unknown cancel ID | FALSE + INVALID_PARAMETER |

`EMPTY` は安定再現できないため必須手動ケースにしない。

### 8.6 Package

- Visual Studio から MSIXを Deployして F5 実行する
- packaged動作を確認する
- unpackaged history APIは本 sample の未確認項目として残す

---

## 9. 要検証事項

| No | 項目 | 確認 |
|---|---|---|
| 9.1 | WinUI UI thread の STA 判定 | Initが WRONG_APARTMENT にならない |
| 9.2 | hidden dispatch HWND | taskbar / Alt+Tabへ出ない |
| 9.3 | deferred provider UI queue | paste時にhangしない |
| 9.4 | NOT_FOREGROUND | 実環境の挙動を記録 |
| 9.5 | history ID | restore / deleteで受理 |
| 9.6 | reserved format enumeration | 実測結果を記録 |
| 9.7 | workerから Win32 clipboard | copy / pasteが成功 |
| 9.8 | deterministic drain | Request + Immediate Uninitializeが FALSE + CANCELED |
| 9.9 | MONITOR_REGISTER_FAILED後の復旧 | CanDestroy -> Uninit retry |

---

## 10. 機能側へ報告する事項

| 項目 | 内容 |
|---|---|
| preferred format | HTMLが候補外。sampleは現行実装に合わせ、機能要件として別判断 |
| manager state query | Bridgeに状態照会 APIがなく、consumerが3状態を保持する必要がある |
| shutdown gate contract | owner UI Uninitの呼び出しで gateが閉じる点を Doxygenへ明記する余地がある |
| write concurrency | Copy / Reserve / Recoverが同一 self-write mutexで直列化され、UI callerが待つ可能性を Doxygenへ明記する余地がある |

---

## 11. 完了条件

- 新規4ファイルと既存4ファイルだけを変更する
- WindowsLibrary / UnityWindowsPlugin / manifest / App / solution / filtersを変更しない
- Debug x64 buildが成功する
- `WorkerResult` / `WorkerPrecondition` が headerから可視である
- `get_weak()` を implementation weak referenceとして使い、`get_self` を使わない
- busy tokenが全 worker終了経路で解除される
- Bridge二重 Initを実際に呼んで確認する
- Request + Immediate Uninitializeで drainを確認する
- manual test結果と未確認項目を implementation resultへ記録する

---

## 12. 実行確認

この改善版をベースに進めますか？

- 実行する: v5 を確定して implement-sample-app へ進む
- 修正する: 追加修正を指定する
- キャンセル: v4 とレビュー結果を保持して終了する
