# Windows Clipboard 実装再レビュー v3

- 日付: 2026-07-30
- 対象ブランチ: `feature/NTKIT-13`
- レビュー範囲: `develop...HEAD` は他機能を大量に含むため、Clipboard 関連の作業ツリー差分に限定
- 設計書: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- 実装結果: `artifact/results/clipboard/2026-07-29-windows-clipboard-implementation-feature-result-v3.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-07-29-windows-clipboard-implementation-feature-review-v2.md`
- 対象 OS: Windows 11
- 総合評価: **要修正（重大）**

## レビュー概要

前回 v2 の指摘に対し、次は改善されている。

- `CanDestroy()` が Win32 listener の登録状態を判定する
- WndProc と遅延描画 provider の外側に例外境界を置く
- Core の通常 Copy 系に mutation flag を追加する
- 履歴 event を `PostMessage` で owner UI thread へ配送する
- WinRT watcher 状態を mutex で保護する
- `base64` decode、重複 format 拒否、timestamp の設計更新を追加する
- Clipboard 新規ソースの C4819/C4828 を解消する

Debug x64 のテスト build、Release x64 の library build は成功し、自動テストも 92/92 件成功した。

一方、WinRT event handler 内の Clipboard API 呼び出し、event 世代の識別、deferred mutation 通知、遅延 provider の実サイズ処理、任意 thread 書き込みの self-write 競合が未解消である。実装結果 v3 が「対応済み」とした項目にも未反映箇所があり、現時点では完了扱いにできない。

## 重大な問題（high）

### H1. WinRT event handler が owner UI thread 外で `Clipboard` API を呼び得る

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:392`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:395`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:401`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:404`
- `HistoryEnabledChanged` / `RoamingEnabledChanged` の handler は、event 発火 thread 上で `Clipboard::IsHistoryEnabled()` / `Clipboard::IsRoamingEnabled()` を呼び、その結果だけを UI thread へ post する。
- Microsoft の `Clipboard` class Remarks は、Clipboard へのアクセスを「application が focus を持つ UI thread」に限定している。event handler の実行 thread はこの実装で保証されていないため、呼び出し自体が契約違反になる。
- 実装結果 v3 の 2.4 節でも未解消と認識されている。これは実機確認だけの残件ではなく、設計書の同期/非同期方針と公式 API 契約に反する実装上の問題である。
- 参考: [Microsoft Learn - Clipboard class Remarks](https://learn.microsoft.com/en-us/uwp/api/windows.applicationmodel.datatransfer.clipboard)

対応:

- event handler では kind だけを owner UI thread へ post する。
- owner UI thread 側から Data/backend の専用 query API を呼び、そこで `IsHistoryEnabled()` / `IsRoamingEnabled()` を実行してから公開 callback を配送する。
- coordinator が WinRT 型を持つ必要はない。Port に Domain の bool を返す同期 query、または UI event 解決用の backend method を追加すれば層境界を維持できる。

### H2. queued された旧世代 event が stop/re-register 後の新 callback を誤って呼ぶ

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.cpp:315`
  - `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.cpp:325`
  - `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.cpp:346`
  - `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.cpp:360`
- post する message には event kind と bool しかなく、watch generation がない。
- `OnHistoryEventMessage()` は配送時点の `historyChangedCb_` 等を参照する。そのため次の順序で旧 event が新 subscriber へ誤配送される。
  1. 旧 watcher の event が message queue へ post される
  2. 同じ UI call stack 内で全 null にして stop する
  3. 新 callback を再登録する
  4. queue に残った旧 event が処理され、新 callback が呼ばれる
- 設計書 `:858`、`:867` は stop で世代を無効化し、無効化後の旧 callback を no-op にする。`:1031`、`:1046`、`:1275` は snapshot/generation の契約を定めている。現在の「配送時の callback を呼ぶ」方式はこれと一致しない。
- 追加された `Test_OnHistoryEventMessage_AfterStop_DoesNotInvokeClearedCallback` は、stop 後に callback が null のままのケースだけで、stop 後の再登録を検証していない。

対応:

- event message に watch generation を含め、owner UI thread で現在世代と一致する場合だけ配送する。
- stop → re-register → 旧 message 配送で、新 callback が呼ばれない test を追加する。
- callback 置換時に旧 snapshot を使い切るのか、配送時 callback を使うのかを設計書と header で一つに統一する。

### H3. deferred 書き込みの mutation 通知が Manager へ接続されていない

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp:604`
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp:647`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:670`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:680`
- Core の `DeferredClipboard::Reserve` / `RecoverFromPartialState` には `bool* outMutated` が追加された。
- しかし公開 `ReserveDeferredFormats()` は `Reserve(..., &mutated)` を渡さず、成功時だけ `NoteSelfWrite()` を呼ぶ。`EmptyClipboard()` 後に予約配置が失敗した経路は、依然として外部変更として通知される。
- 公開 `RecoverDeferredState()` も mutation flag を受け取らず、回復で clipboard を空にしても `NoteSelfWrite()` を呼ばない。
- `Uninit()` 内の recovery だけは mutation flag を利用している。
- 実装結果 v3 の H4「全 Copy 系 API・Reserve・Recover を修正」は実コードと一致しない。

対応:

- `ReserveDeferredFormats()` と `RecoverDeferredState()` の両方で mutation flag を受け取り、戻り値ではなく実 mutation を基準に `NoteSelfWrite()` する。
- 予約途中失敗、rollback 失敗、公開 recovery 成功の test を追加する。

### H4. 遅延 provider が query より小さい実サイズを返すと未初期化 heap を clipboard へ公開する

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:641`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:648`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:653`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:657`
- query phase の `queriedSize` で `GlobalAlloc(GMEM_MOVEABLE, queriedSize)` するが、このメモリは zero-initialize されない。
- fill phase で `actualSize < queriedSize` でも、そのまま元の大きさの `HGLOBAL` を `SetClipboardData` へ渡す。
- provider が実際に `actualSize` bytes だけを書いた場合、残りの未初期化 heap 内容が別 process から取得可能な clipboard data になる。
- 現在は `actualSize > queriedSize` だけを拒否しており、情報漏えいを防げない。

対応:

- 最も単純には `actualSize == queriedSize` を成功条件にする。
- 可変長を許容するなら、fill 後に安全に実サイズへ縮小した `HGLOBAL` を作り直す。
- `actualSize < queriedSize`、`==`、`>` の provider test を追加する。

### H5. 任意 thread の自己書き込みと UI の `WM_CLIPBOARDUPDATE` 処理に順序保証がない

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:332`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:335`
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp:770`
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp:791`
- 同期 Copy API は任意 thread から実行できる。Core が clipboard を変更して復帰した後、Manager が `NoteSelfWrite()` で sequence を set に追加する。
- worker thread が Core から復帰して `NoteSelfWrite()` を呼ぶまでの間に owner UI thread が `WM_CLIPBOARDUPDATE` を処理すると、`TakeSelfWrite(seq)` は false になり、toolkit 自身の書き込みが外部変更として callback される。
- mutation flag は「失敗後にも記録する」問題を解決するが、この cross-thread ordering race は解決しない。
- 設計書 `:1269` は複数 thread の連続 copy と UI 処理の境界 test を要求しているが、該当 test はない。

対応:

- watcher に self-write transaction/RAII を設け、書き込み開始から sequence 登録まで self-write mutex を保持する。UI の `OnClipboardUpdate()` は同じ mutex を通して判定する。
- worker copy と UI update を barrier で競合させる test を追加する。

### H6. UI-thread限定 API の wrong-thread 判定自体が Manager 状態と data race になる

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:83`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:89`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:277`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:611`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:675`
- `CheckInitialized()` と `CheckOwnerThread()` は `initialized_` / `ownerThreadId_` を `initMutex_` なしで読む。
- `setClipboardHistoryCallbacks`、`reserveDeferredFormats`、`recoverDeferredState` は「非 owner thread なら `WRONG_THREAD` を返す」公開契約なので、wrong thread から呼ばれること自体を安全に処理しなければならない。
- owner thread の `Uninit()` が同時に状態を書き換えると、wrong-thread caller の read と競合し C++ data race になる。

対応:

- initialized check、owner thread check、必要な `coordinator_` / `dispatchHwnd_` snapshot を `initMutex_` の同じ臨界区間で行う helper を追加する。
- wrong-thread call と owner-thread uninit の競合 test を追加する。

## 改善提案（medium）

### M1. `copyMultipleFormats` の format/payload 型検証がまだ不完全

- 該当: `windows/WindowsLibrary/WindowsClipboardManager.cpp:471`
- `CF_HDROP` / DIB / `CF_BITMAP` に text/html を拒否するだけで、次を受理する。
  - `CF_TEXT` に UTF-16LE の `text` payload
  - `CF_UNICODETEXT` に CF_HTML の `html` payload
  - `HTML Format` に UTF-16LE の `text` payload
  - `CF_BITMAP` に base64 decode した `HGLOBAL`
- `CF_BITMAP` の `SetClipboardData` は `HBITMAP` を要求し、現在の共通 `GlobalMem` 経路では扱えない。

対応:

- 標準 format ごとに許可 payload とエンコードを明示した table で検証する。
- `CF_BITMAP` は複数 format API から拒否するか、専用 handle 所有経路を実装する。
- custom registered format のみ generic base64 を許可する方針が安全。

### M2. `ReserveDeferredFormats` の `std::bad_alloc` がまだ `INVALID_PARAMETER` になる

- 該当: `windows/WindowsLibrary/WindowsClipboardManager.cpp:619`〜`:625`
- v2 の M3 は `ReserveDeferredFormats` も対象だったが、この JSON parse block は現在も `catch (...)` のみである。
- `names.emplace_back` 等の `std::bad_alloc` が外側の `SafeBridgeCall` へ届かず、`INVALID_PARAMETER` に誤分類される。

対応:

- CopyFiles/CopyMultipleFormats と同様に `catch (const std::bad_alloc&) { throw; }` を先に置く。

### M3. `Init()` の lifecycle reopen が fallible setup より前のまま

- 該当: `windows/WindowsLibrary/WindowsClipboardManager.cpp:160`〜`:185`
- lifecycle は「commit point」とコメントされているが、backend/coordinator construction と watcher start より前に `Reopen()` している。
- construction または watcher start 失敗時に lifecycle を再度 close しないため、`initialized_ == false` なのに lifecycle が open の状態が残る。
- 前回 v2 の M6 は未対応だが、実装結果 v3 の対応表では別の指摘番号に置き換わり、残件として扱われていない。

対応:

- `Reopen()` を全 fallible setup 成功後の commit へ移すか、全 rollback path で `Close()` する。

### M4. 履歴 callback の実装方式が設計の immutable snapshot 契約と一致しない

- 設計書 `:741`、`:1031`、`:1046` は handler 入場時の immutable snapshot を使う。
- 実装結果 v3 とコードは配送時点の current callback を使う方式へ変更した。
- H2 の generation 問題を解消した上で、どちらを正式契約とするか設計・header・test を統一する必要がある。

### M5. source encoding 方針の設計差分が残る

- `windows.md` は非 ASCII source に UTF-8 BOM または `/utf-8` を求めるため、新規 Clipboard source を ASCII-only にした対応自体は許容できる。
- 一方、設計書 `:110` と T-01 は `/utf-8` 適用を明示したままで、実装結果 v3 の「適用しない」判断が反映されていない。

対応:

- 設計書を「既存 Shift-JIS source への project-wide `/utf-8` は別 task。Clipboard source は ASCII-only、非ASCIIが必要な個別 fileだけ UTF-8 BOMまたはfile単位 `/utf-8`」へ更新する。

### M6. DIB validation が無効な圧縮形式の組合せを受理する

- 該当: `windows/WindowsLibrary/WindowsClipboardFormats.cpp:269`〜`:347`
- `biWidth == 0` を拒否しない。
- `BI_RLE8` と 8bpp、`BI_RLE4` と 4bpp の対応を検証しない。
- RLE の場合は幅・高さ・`biSizeImage` / 圧縮 payload の範囲を確認せず `true` を返す。

対応:

- compression と bit count の有効な組合せ、正の width、許容 height、圧縮 payload 範囲を検証する。
- 不正組合せと切断 RLE の test を追加する。

### M7. 実装結果 v3 の自動テスト記載が自己矛盾している

- 2.2 節は H1〜H4 を「対応コードに加えて自動テストで確認済み」とする。
- 4.1 節は H1 を「Manager 統合テスト対象外のため自動テストなし」とする。
- H3 の provider、H4 の Manager mutation 連携、WinRT backend の stop/generation も自動テストされていない。

対応:

- 「実装済み」「単体テスト済み」「コードレビューのみ」「実機未確認」を指摘ごとに正確に分ける。

## 軽微な指摘（low）

### L1. 実装結果の「リポジトリはクリーン」は現在の状態と異なる

- Clipboard 実装、設計、結果、レビューを含む多数の未追跡/変更 file が存在する。
- resource compiler の一時変更を復元した意味なら、「`WindowsLibrary.rc` の副作用は復元済み」と限定して記載する。

## 設計書整合性チェック

- 企画書との整合性: △ — 基本方針は一致するが実機確認項目が未完了
- Clean Architecture 準拠: ○ — coordinator / backend Port の依存方向は維持
- 既存実装との差分分析の正確性: △ — event方式とencoding方針が設計へ未反映
- テスト設計の網羅性: × — Manager/WinRT/deferred provider/競合testが不足
- ドメインエラー全ケース実装: △ — 主な定数はあるが allocation failure の誤分類が残る
- エラーコード/メッセージ対応表との整合: △ — deferred parse の `bad_alloc` が不一致

## プロジェクトルール適合チェック

- `common.md` 準拠: △ — 非同期/UI配送の大枠は適合するが callback 世代契約が未完了
- `windows.md` 準拠: × — Clipboard API の owner UI thread 要件を event handler 内で破る
- エラー契約反映: △ — Bridge 外周は改善したが内側の誤分類が残る
- 既存 API 互換性: ○ — 既存 Dialog/Notification API の破壊的変更は確認されない

## テストカバレッジ

カバー済み:

- checked演算、CF_HTML、DROPFILES、基本DIB、UTF変換、base64 decode
- Core write failure、write option rollback、複数 format rollback
- coordinator request/cancel/drain/重複完了
- callback 初回登録/置換/停止失敗
- Win32 listener 登録/解除失敗

不足:

- Manager init/uninit/CanDestroy の統合test
- owner thread API と uninit の競合
- WinRT event callback thread と UI marshal
- stop/re-register後の旧世代event
- deferred providerの例外/二相size不一致
- deferred予約/回復失敗時のmutation通知
- worker writeと`WM_CLIPBOARDUPDATE`の競合
- format/payloadの全組合せ
- DIB圧縮形式の異常系
- Windows 11実機、MSIX/未パッケージ、他applicationとの相互運用

## 実行確認

- `git diff --check -- windows/WindowsLibrary windows/WindowsLibraryTest artifact/designs/clipboard artifact/results/clipboard artifact/reviews/clipboard`: エラーなし
- Debug|x64 `WindowsLibraryTest`: rebuild成功
- `vstest.console.exe windows\WindowsLibraryTest\x64\Debug\WindowsLibraryTest.dll`: **92/92成功**
- Release|x64 `WindowsLibrary`: rebuild成功
- Clipboard新規sourceのC4819/C4828: 検出なし
- 既存Notification/common系のC4190/C4819とMSB3106: 残存

## 総合評価

**要修正（重大）**

前回より改善しているが、公式UI-thread契約違反、旧世代eventの誤配送、deferred経路のmutation未接続、provider bufferの未初期化領域公開、任意thread self-write競合、wrong-thread判定のdata raceが残る。これらを修正し、Manager/WinRT/deferredの専用testを追加してから再レビューが必要である。
