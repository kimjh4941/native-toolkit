# レビュー結果

- 日付: 2026-07-31
- 対象ファイル: `artifact/designs/clipboard/2026-07-30-windows-clipboard-sample-app-design-v1.md`
- 文書種別: サンプルアプリ設計
- 機能名: clipboard
- 対象 OS: Windows
- 参照:
  - `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
  - `artifact/results/clipboard/2026-07-30-windows-clipboard-implementation-feature-result-v4.md`
  - `windows/WindowsLibrary/WindowsClipboardManager.h`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp`
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp`
  - `windows/WindowsLibraryExample`
  - `agent-rules/coding-rules/windows.md`

---

## 強み

- Bridge 27 API を Copy / Paste / Inspect / Deferred Rendering / History / Lifecycle / Threading / Error cases に分け、機能設計の F-01〜F-14、F-17 と対応付けている。
- `WindowsClipboardManager.h` の公開 C Bridge だけを利用し、`WindowsClipboardManagerInternal.h` や `windows/UnityWindowsPlugin` に依存しない方針は、Windows の依存方向ルールと一致している。
- WinUI 3 の UI スレッドを owner UI thread として採用し、STA、メッセージポンプ、コールバックの非再入、request callback の JSON 寿命、遅延 provider の二相呼び出しを明記している。
- `NotificationPage` の画面骨格、forwarding hub、weak reference、`DispatcherQueue`、既存ボタンスタイルを再利用するため、既存 Windows サンプルとの一貫性が高い。
- DIB、CF_HTML、CF_HDROP、custom format、複数形式、write option、履歴、遅延レンダリングまで、サンプル固有データの生成方針が具体的である。
- MSIX 実機、他アプリとの相互運用、Win+V、設定変更、メッセージ配送など、CLI ビルドだけでは確認できない項目を手動確認として分離している。
- 新規・既存変更・非変更ファイルが分類され、`App.xaml`、manifest、filters、solution を変更しない理由も説明されている。

## 改善点

### 高優先度

#### H1. 任意スレッド対応の同期 Bridge を UI ボタンハンドラで直接実行する方針が Windows ルールと矛盾する

対象:

- 42 行: 同期 API を任意スレッド可として分類
- 342〜359 行: 同期 API をボタンハンドラから直接呼ぶ例
- 391〜394 行: `std::thread` を起動して同じ UI ハンドラ内で `join`

`agent-rules/coding-rules/windows.md` の「サンプルアプリ（VC++ / MFC）での非同期処理」は、UI スレッドで待機処理を行わず、同期 Bridge はサンプル側でワーカースレッドへ逃がし、結果を UI スレッドへ戻すよう定めている。現在の設計では通常の copy / paste / inspect / clear が UI スレッドで実行される。また、worker thread の検証ボタンも UI ハンドラ内で `join` するため、実行中はメッセージポンプを停止する。

修正案:

- 任意スレッド対応の同期 APIと、一時ファイル作成などの同期 I/O は worker thread で実行する。
- 完了結果は `DispatcherQueue::TryEnqueue` で UI へ返す。
- UI ハンドラ内の `join` は禁止する。ページ寿命は weak reference で保護し、worker の所有方法と終了処理を設計に追加する。
- `initClipboardManager`、`setClipboardHistoryCallbacks`、`uninitClipboardManager`、`reserveDeferredFormats`、`recoverDeferredState` など owner UI thread 限定 API、および受付だけを行う履歴非同期 APIは UI スレッドから直接呼ぶ。

#### H2. pending 中の `Uninitialize` が「再試行して初めて完了する」契約を反映できていない

対象:

- 250 行: Uninitialize ボタン
- 485 行: `GetClipboardHistory -> 即 Uninitialize -> CanDestroy`

`WindowsClipboardManager.h` と機能設計では、pending request がある最初の `uninitClipboardManager` はキャンセル完了を UI queue に積み、`FALSE` + `CLIPBOARD_ERROR_CANCELED` を返す。その後メッセージポンプを回し、`canDestroyClipboardManager` が `TRUE` になっても、それは状態照会であって teardown 完了ではない。`uninitClipboardManager` を再度呼び、`TRUE` を得る必要がある。

現在の手順のまま再初期化すると、manager の `initialized_` は true のままでも lifecycle gate は closed のため、owner thread からの再 Init は冪等成功し、その後の API が `NOT_INITIALIZED` になる可能性がある。

修正案:

- Uninitialize ボタンは戻り値と `pError` の両方を表示する。
- `FALSE` の場合は初期化済み表示を維持し、UI をブロックせずに callback 配送を待つ。
- `CanDestroy == TRUE` を確認後、Uninitialize を再実行して `TRUE` + `NONE` を得る手順を追加する。
- sample 側の初期化状態は `uninitClipboardManager` が `TRUE` を返した場合だけ false にする。
- 6.5 の pending 中の破棄と再初期化の手順にも、2 回目の Uninitialize を追加する。

#### H3. manager をページ離脱後も維持する方針と、ページローカルな初期化状態が両立していない

対象:

- 121 行: `EnsureInitialized` の再利用
- 184〜185 行: `OnNavigatedFrom` で manager を uninit しない
- 489 行: 再入場後も初期化状態が保たれ、そのまま Copy できることを期待

既存 `NotificationPage` の `m_initialized` はページインスタンスのメンバーで、初期値は false である。`ClipboardPage` でも同じ構成にすると、Back 後に新しいページインスタンスへ再遷移した際、manager は生きていても `EnsureInitialized` が未初期化として API 呼び出しを止める。Bridge には初期化状態の query API がないため、現在の記載だけでは 489 行の期待を実現できない。

修正案:

- sample process 内で manager 状態を保持する process-lifetime state を設け、ページ再生成後の `EnsureInitialized` と同期する。状態更新は Init 成功時、および Uninit が `TRUE` で完了した時だけ行う。
- または、再入場時は InitializeManager を再度押す仕様へ変更し、489 行の手順と期待を修正する。
- manager をページ外でも生存させる現方針を維持するなら、前者が設計意図に合う。

### 中優先度

#### M1. Clear 直後の PastePlainText の期待エラーが実装と異なる

対象:

- 330 行: `PastePlainText (after Clear)` の期待を `EMPTY(4)` としている

`WindowsClipboardCore.cpp` の `PastePlainText` は、最初に `IsClipboardFormatAvailable(CF_UNICODETEXT)` を確認し、存在しなければ `CLIPBOARD_ERROR_FORMAT_UNAVAILABLE(5)` を返す。`EMPTY(4)` は format が available なのに `GetClipboardData` が null を返した場合である。`clearClipboard` の直後は通常 `FORMAT_UNAVAILABLE(5)` になる。

修正案:

- 期待値を `FORMAT_UNAVAILABLE(5)` に修正する。
- `EMPTY(4)` を確認したい場合は再現手段を別途用意できる場合だけ独立ケースにする。安定した再現ができなければ手動テストから外す。

#### M2. GetPreferredFormat の期待が現在の実装アルゴリズムと一致していない

対象:

- 53 行: 複数形式を「情報量の多い順」と説明
- 263〜264 行: HTML / text / DIB の複数形式
- 437 行: GetPreferredFormat が「最も情報量の多い形式名」を返すと期待

現在の `PickPreferredFormat` は `{ CF_UNICODETEXT, CF_HDROP, CF_DIB, CF_BITMAP }` の固定順で `GetPriorityClipboardFormat` を呼び、`HTML Format` を候補に含めていない。したがって HTML + text、または HTML + text + DIB の直後は `CF_UNICODETEXT` が返る。設計書の「最も情報量の多い形式」という表現だけでは、実装結果を誤判定する。

修正案:

- sample の期待値を現行アルゴリズムに合わせて具体化する。
- HTML を優先候補に含めることが機能要件なら、サンプル側で吸収せず機能実装側の未解決事項として報告する。
- 「copyMultipleFormats の配置順」と「getPreferredClipboardFormat の固定優先順」は別の契約として記載する。

#### M3. Word が遅延 HTML だけを要求するという期待は外部アプリ依存で固定できない

対象:

- 453 行: Word で貼り付けると `HTML Format` provider だけが呼ばれると期待

貼り付け先は利用可能形式を複数問い合わせたり、フォールバック形式も取得したりできるため、Word が HTML だけをレンダリング要求することは sample の契約にできない。

修正案:

- 「貼り付けが成功し、要求された各形式について size / fill が正しい組で記録される」に期待を変更する。
- HTML が要求されたか、他形式も要求されたかは環境依存の観察結果として記録する。

#### M4. PasteImage の構造体参照前チェックが明記されていない

対象:

- 281 行: 返却バッファを `BITMAPINFOHEADER` として読み width / height / bitCount を表示
- 406〜412 行: 数値・文字列の妥当性検証をライブラリ責務としている

sample 側で `BITMAPINFOHEADER` のフィールドを読む前に、少なくとも返却サイズが `sizeof(BITMAPINFOHEADER)` 以上であることを確認する必要がある。ライブラリが DIB を検証する契約でも、呼び出し側の構造体参照条件は別である。

修正案:

- サイズ不足時は `INVALID_DATA` 相当の sample 表示にして構造体を参照しない。
- `biSize` がバッファ内に収まることも確認してからフィールドを表示する。

#### M5. 2 回呼び出し helper が 1 回目の正常な契約値を十分に検証していない

対象:

- 354〜357 行: 1 回目の判定

正常な size query は、必要サイズが非 0で `pError == BUFFER_TOO_SMALL` になる。現在の記載は「戻り値 0 かつ err != 0」だけを失敗条件にするため、非 0の必要サイズと想定外エラーの組み合わせも受理する。

修正案:

- 1 回目は `needed > 0 && err == CLIPBOARD_ERROR_BUFFER_TOO_SMALL` の組だけを size query 成功として扱う。
- 2 回目は戻り値、`err == NONE`、返却サイズが確保サイズ以下であることを確認する。
- `CancelClipboardRequest (unknown id)` も戻り値 `FALSE` だけでなく `INVALID_PARAMETER(1)` を期待値に加える。

### 低優先度

#### L1. 一時ファイルの後始末方針がない

対象:

- 401 行: `%TEMP%` に固定名のファイル 2 件を作成

固定名のため無制限には増えないが、sample 終了後も残る。Uninitialize 成功時または明示 Cleanup ボタンで削除するか、残置することを結果ファイルに記録する方針を追加するとよい。

#### L2. UI 文言を英語に統一するルールを実装条件として明記すると安全

対象:

- 79 行: ログメッセージのみ英語と明記

`windows.md` はログだけでなく UI text、status text、dialog 文言も英語としている。ボタン例は英語だが、結果・補足文言も含めて全 UI 文言を英語にすることを実装条件へ明記すると取りこぼしを防げる。

## 不足項目

- 任意スレッド対応同期 Bridge を非同期に実行する sample 側 task runner の所有・完了配送・ページ破棄時の扱い。
- `uninitClipboardManager` が `FALSE` を返した後の非ブロッキング再試行手順と、sample 初期化状態の更新条件。
- ページ再生成をまたいで manager 初期化状態を保持する方法。
- PasteImage の構造体参照前チェック。
- GetPreferredFormat の現行固定優先順に対する具体的な期待値。

## 総合評価

機能網羅、公開 API 境界、既存 Windows sample との UI 一貫性、実機確認観点は十分に整理されている。一方、同期 Bridge の実行スレッド、shutdown gate の再試行、ページ再入場時の状態管理は実装構造に直接影響するため、このまま実装 agent へ渡すと UI ブロックまたは再初期化不能を作り込む可能性がある。

また、Clear 後のエラーコードと GetPreferredFormat の期待は現行実装に合っておらず、手動確認が必ず失敗または曖昧になる。

総合評価: **要修正**。H1〜H3 と M1〜M2 を反映後に実装へ進めることを推奨する。
