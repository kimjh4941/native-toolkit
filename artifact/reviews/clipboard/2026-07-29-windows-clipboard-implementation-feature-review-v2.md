# Windows Clipboard 実装再レビュー v2

- 日付: 2026-07-29
- 対象ブランチ: `feature/NTKIT-13`
- レビュー範囲: Clipboard 関連の作業ツリー差分
- 設計書: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- 実装結果: `artifact/results/clipboard/2026-07-29-windows-clipboard-implementation-feature-result-v2.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-07-29-windows-clipboard-implementation-feature-review-v1.md`
- 総合評価: **要修正（重大）**

## 概要

前回の重大指摘のうち、Manager 状態の snapshot と lifecycle lease の原子化、C ABI 外周の例外正規化、WinRT event token 登録失敗時の保持と再解除、write option 配置失敗時の rollback、成功時の自書き込み記録、全構成の export 定義は改善されている。Debug/Release x64 のビルドは成功し、自動テストも 83/83 件成功した。

一方、終了可否判定が Win32 listener を見ていない、WinRT watcher の停止・再登録・callback 配送契約が完結していない、WndProc と遅延描画 provider の例外境界がない、失敗後にクリップボードが変更された経路を自書き込みとして記録しない、という重大な問題が残る。現時点では実装完了として引き渡せない。

## 前回指摘の反映状況

| 前回項目 | 状況 | 判定 |
|---|---|---|
| H1 Manager と `uninit` の競合 | `AcquireSyncLease` / `AcquireHistoryCoordinator` で主要競合を解消 | 改善。ただし `CanDestroy` と backend 状態には残件あり |
| H2 C ABI / `noexcept` 例外境界 | `SafeBridgeCall` と completion encode の捕捉を追加 | Bridge は解消。WndProc/provider は未解消 |
| H3 token 登録途中失敗 | 残存 token と `revokePending_` を保持 | 解消 |
| H4 watcher callback drain | retired state で破棄前の寿命は保護 | 一部改善。停止完了・再登録・配送 thread 契約は未解消 |
| H5 自書き込み抑止 | 正常終了経路で `NoteSelfWrite` を追加 | 一部改善。変更後エラー経路は未解消 |
| H6 write option marker 失敗 | rollback と部分失敗エラーを追加 | 解消 |
| M2 複数 format | checked 演算は改善 | `base64` と payload 整合性が未実装 |
| M3 成功時 `pError` | `NONE` を設定 | 解消 |
| M4 timestamp 精度 | decimal string に変更 | 精度は改善したが設計契約と不一致 |
| M6 failure seam tests | Core の seam test を追加 | 改善。ただし Manager/WinRT の主要契約は未テスト |
| M7 project settings | export 定義は全構成へ追加 | `/utf-8` は未解消 |

## 重大な問題（High）

### H1. `canDestroyClipboardManager` が Win32 listener の残存を判定しない

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:229`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:261`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:269`
  - `windows/WindowsLibrary/WindowsClipboardCore.h:185`
- `Uninit()` で `RemoveClipboardFormatListener` が失敗すると watcher は登録されたままになり、`Uninit()` は失敗を返す。
- しかし `CanDestroy()` は lifecycle と history coordinator しか確認せず、`watcher_.IsRegistered()` を見ていない。そのため listener が残っていても `TRUE` を返し得る。
- 公開 API と設計書は「listener / event token / in-flight callback が残らない場合だけ破棄可能」と規定しており、終了再試行の判断 API が誤った結果を返す。

対応:

- `CanDestroy()` の同じ同期区間で `!watcher_.IsRegistered()` を必須条件にする。
- listener 解除失敗 → `canDestroy == FALSE` → 再試行成功 → `TRUE` の Manager-level test を追加する。

### H2. WinRT watcher の stop / drain / 再登録 / callback thread 契約が完結していない

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:94`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:374`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:449`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:479`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:489`
- `StopWatch()` は gate を閉じて token を解除し、旧 state を `retiredStates_` に移すが、旧 callback の `inFlight == 0` を確認せず成功を返す。
- 破棄前の use-after-free は `CanDestroy()` で抑えられるようになったが、stop 成功後すぐ再登録すると、gate の二重確認を通過済みの旧 callback と新世代 callback が重なり得る。設計の「停止後に旧世代は配送されず、新世代だけが有効」という契約を満たさない。
- event handler は `RaiseEvent()` から公開 callback を直接呼ぶ。owner UI thread へ配送する処理がなく、設計が要求する callback thread を実装として保証していない。`HistoryEnabledChanged` 等の handler 内で UI thread 要件のある WinRT API も直接呼んでいる。
- `CanDestroy()` は `watching_`、`revokePending_`、`retiredStates_` を同期なしで読む一方、公開 header は `canDestroyClipboardManager` を UI thread 限定としていない。任意 thread からの終了監視と UI thread の start/stop が競合すると data race になる。

対応:

- stop の完了条件を明確化し、旧 state の callback が drain するまで再登録を拒否するか、owner UI thread 上の drain 完了処理を導入する。
- 全 event callback を `dispatchHwnd` へ post し、owner UI thread で gate と世代を再確認してから配送する。
- backend の watcher 状態を同期するか、`canDestroyClipboardManager` を owner UI thread 限定契約へ変更して設計・header・実装を一致させる。
- stop 中 callback、stop 直後の再登録、旧世代遅延 callback、任意 thread の `CanDestroy` を seam test で検証する。

### H3. WndProc と遅延描画 provider に例外境界がない

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardWindow.cpp:12`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:589`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:676`
- C Bridge は `SafeBridgeCall` で保護されたが、WndProc は Manager の message handler を直接呼ぶ。
- 遅延描画の `ClipboardRenderCallback` も `try/catch` なしで呼ばれ、provider の例外、内部 allocation 失敗、`rendered_` 更新時の例外が Win32 の window procedure 境界を越え得る。
- provider の 2 回目呼び出しが初回提示サイズを超える `required` を返した場合の検証もなく、不正な provider 契約を安全に終端できない。

対応:

- provider 呼び出しを例外捕捉し、戻り値・必要サイズ・実書き込みサイズを検証する。
- WndProc dispatch 全体に最後の例外 guard を置き、例外を Win32 callback 境界から漏らさない。
- throwing provider、2 回の size query が不整合な provider、allocation 失敗の test を追加する。

### H4. 自書き込み抑止が「成功した API」に限定され、変更後エラーを外部変更として配送する

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:297`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:496`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:610`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:613`
- 現在は core の最終エラーが `NONE` の場合だけ `NoteSelfWrite()` を呼ぶ。
- しかし `EmptyClipboard` 成功後の payload 配置失敗、複数 format の途中失敗、option marker 配置失敗と rollback 失敗などは、API がエラーを返しても OS clipboard を変更している。
- `RecoverDeferredState()` が clipboard を空にした場合も自書き込み記録がない。
- 変更 callback 内で再コピーする利用形態では、これらが外部変更として再配送され、失敗時だけ再帰ループを起こし得る。

対応:

- Core の結果に「clipboard sequence を変更したか」を表す情報を持たせ、成功/失敗ではなく実際の変更を基準に `NoteSelfWrite()` する。
- 部分失敗、rollback、deferred recovery を含む自書き込み抑止 test を追加する。

## 改善事項（Medium）

### M1. `copyMultipleFormats` が設計 JSON schema を満たさず、format と payload の組合せも不正にできる

- 設計書 `:1506` は `[{"format":"...","text|html|base64":"..."}]` を要求する。
- 実装は `text` / `html` のみで `base64` を処理しない。実装結果 v2 の「設計で明示されていない」という説明は事実と異なる。
- binary format に text/html を拒否するだけでは不十分で、`CF_UNICODETEXT` に `html`、`HTML Format` に `text` なども受理できる。

対応:

- base64 decode、重複 format、既知 format ごとの payload 種別・構造検証を実装する。
- 対応範囲を縮小するなら、先に設計・公開契約を変更する。

### M2. 履歴 `timestamp` の型を設計変更なしに number から string へ変えている

- 設計書 `:779` と `:1117` は `timestamp:<int64>` を規定する。
- 実装と header は `"timestamp":"<int64>"` に変更されている。
- 64-bit 値を `double` にすると精度が失われるという修正理由は妥当だが、consumer が読む JSON 契約を実装だけで変更してはならない。

対応:

- decimal string を正式仕様にするなら設計書、header、manual、consumer test を同時に更新する。
- number を維持するなら安全な単位と範囲を設計し直す。

### M3. 内側の `catch (...)` が `std::bad_alloc` も `INVALID_PARAMETER` に変換する

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:355`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:492`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:579`
- JSON parse error と allocation failure を同じ catch で処理するため、外側の `SafeBridgeCall` が `OUT_OF_MEMORY` に正規化できない。

対応:

- `std::bad_alloc` は再送出するか、その場で `OUT_OF_MEMORY` にする。
- 入力 parse/型エラーだけを `INVALID_PARAMETER` に分類する。

### M4. 実装結果の「自動検証済み」判定が実際の test coverage より強い

- 実装結果 v2 は H1-H6 / M1-M6 を自動テスト済みとしているが、同じ文書で Manager/WinRT 実体は test 対象外としている。
- 追加された Core seam test では Manager lifecycle、WinRT token rollback/in-flight、`NoteSelfWrite` の Manager 連携を検証していない。

対応:

- 「コード修正済み」「自動テスト済み」「実機未確認」を項目ごとに分ける。
- H1、H2、H4 の再現 test が入るまで DoD を完了扱いにしない。

### M5. 設計で要求された `/utf-8` が project に設定されていない

- `WindowsLibrary.vcxproj` には `/utf-8` の compiler option がない。
- Debug の test build では `ClipboardFormatsTest.cpp` と `ClipboardHistoryCoordinatorTest.cpp` に C4819 が残る。
- em dash の置換は個別警告の回避であり、source encoding 方針の実装ではない。

対応:

- 関連 project の全構成へ `/utf-8` を共通設定し、Debug/Release と Win32/x64 で確認する。

### M6. `Init()` が fallible setup の前に lifecycle を reopen する

- 該当: `windows/WindowsLibrary/WindowsClipboardManager.cpp:163`
- backend/coordinator construction や watcher start が失敗すると `initialized_` は false のままだが lifecycle は open のまま残る。
- 公開 API は initialized check で拒否されるため直ちに破壊にはつながらないが、状態機械の invariant と「次回 init commit 時に reopen」というコメントに一致しない。

対応:

- `Reopen()` を全 setup 成功後の commit へ移すか、rollback で必ず `Close()` する。

## 軽微な問題（Low）

### L1. `retiredStates_` が drain 後も削除されない

- `StopWatch()` ごとに state を追加するが、`inFlight == 0` になった要素を prune しない。
- 長時間の callback 再登録で vector と state が増え続ける。

対応:

- owner UI thread 上で stop/start/CanDestroy の節目に drain 済み state を削除する。

## 設計・ルール整合性

- 同期 / 非同期方針と C++17 / C++20 のファイル単位分離: **適合**
- `UnityWindowsPlugin` を変更しない方針: **適合**
- C ABI の外周例外正規化: **概ね適合**
- shutdown gate / watcher drain / `CanDestroy`: **不適合**
- owner UI thread callback 契約: **不適合**
- 複数 format JSON schema: **不適合**
- timestamp JSON contract: **不一致**
- source encoding `/utf-8`: **不適合**

## テストと実行結果

- `git diff --check -- windows/WindowsLibrary windows/WindowsLibraryTest`: 成功
- Debug|x64 `WindowsLibrary`: ビルド成功
- Debug|x64 `WindowsLibraryTest`: ビルド成功
- `WindowsLibraryTest`: **83/83 成功**
- Release|x64 `WindowsLibrary`: ビルド成功
- Clipboard の Release C4273/C4819: 検出なし
- Debug test build: Clipboard test 2 ファイルに C4819 が残存

不足している主なテスト:

- Manager の init/uninit/CanDestroy と任意 thread API の競合
- Win32 listener 解除失敗と終了再試行
- WinRT token 登録・解除失敗、callback in-flight、stop/restart 世代競合
- callback の owner UI thread 配送
- WndProc/provider 例外
- 変更後エラー経路の self-write suppression
- `base64` と format/payload schema

## 総合評価

**要修正（重大）**

前回の危険な寿命・例外・rollback 問題は相当数改善されたが、終了可否判定、watcher の世代と thread 契約、WndProc/provider の例外境界、自書き込みの失敗経路が未完了である。これらは use-after-free の再発防止、終了処理の正しさ、callback 再入、ABI 安全性に直接関わるため、修正と専用テストを行ってから再レビューする必要がある。
