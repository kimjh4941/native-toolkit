# Windows Clipboard 実装レビュー v1

- 日付: 2026-07-29
- 対象ブランチ: `feature/NTKIT-13`
- 対象差分: `develop...HEAD` は Clipboard 以外の大量差分を含み、Clipboard 実装の大半が未追跡であるため、作業ツリー上の Clipboard 関連ファイルに限定してレビュー
- 設計書: `artifact/designs/clipboard/2026-07-28-windows-clipboard-design-v2.md`
- 実装結果: `artifact/results/clipboard/2026-07-29-windows-clipboard-implementation-feature-result-v1.md`
- 対象 OS: Windows 11
- 総合評価: **要修正（重大）**

---

## レビュー概要

Win32 同期コア、WinRT 履歴の非同期 Bridge、C++17/C++20 のファイル単位分離、公開 API と `.def` の追加は、設計の大枠に沿っている。Debug/Release x64 はビルドでき、既存の自動テストも 73/73 成功した。

一方、設計で重点化した shutdown gate、WinRT イベント解除、C ABI の例外正規化、自書き込み抑止に未達がある。特に、任意スレッド API と `uninit` の競合、WinRT watcher の token/in-flight 管理、`noexcept` 完了処理内の JSON 生成は、use-after-free、未解除ハンドラ、`std::terminate` につながる。現状のまま実装完了とは判断できない。

## 重大な問題（High）

### H1. 任意スレッド API と `uninit` の状態確認が原子的でなく、破棄済み資源へアクセスできる

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:81`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:93`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:162`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:186`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:514`
- `initialized_`、`dispatchHwnd_`、`coordinator_` は `initMutex_` の保護下で変更されるが、`CheckInitialized`、同期 API、履歴 API、`CanDestroy` は同じ mutex を使わず読み取っている。これは C++ 上の data race である。
- 例えば履歴 API が `initialized_ == true` を確認した直後に UI スレッドが `coordinator_.reset()` すると、null または破棄済み coordinator を参照できる。同期 API も同様に、破棄済み `dispatchHwnd_` を利用できる。
- `Uninit` 成功時の `lifecycle_.Reopen()`（同ファイル 193 行）により、状態確認と `TryEnter()` の間に終了処理が完了すると、未初期化状態なのに lease を再取得できる窓もある。
- 対応:
  - Manager 状態の snapshot 取得と lifecycle 入場を、`uninit` の close/破棄と同じ同期規約で原子的にする。
  - `coordinator_` はロック下で `shared_ptr` をローカルへコピーしてから使う。
  - 終了成功後に lifecycle を open 状態へ戻さず、次回 `init` の commit 時にだけ reopen する。
  - `init` / `uninit` / 同期 API / 履歴受付の競合テストを追加する。

### H2. C ABI 境界と `noexcept` 完了処理で例外を正規化できず、プロセス終了または ABI 越境が起きる

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:574`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:301`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:407`
  - `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.cpp:107`
  - `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.cpp:119`
  - `windows/WindowsLibrary/WindowsClipboardHistoryCoordinator.cpp:136`
- 全 Bridge 関数が Manager を直接呼ぶだけで、最外周の `try/catch` がない。`std::vector`、`std::wstring`、`std::make_shared`、WinRT JSON 生成などの例外が C ABI を越え得る。`init` 中の確保失敗では、作成済み HWND の cleanup も保証されない。
- `CompleteItems` / `CompleteAvailability` は JSON を生成するが例外を捕捉せず、それらを呼ぶ completion lambda は `noexcept` である。確保失敗や WinRT JSON 例外が起きると、外側の backend の `try/catch` へ届く前に `std::terminate` する。
- 設計 855 行および `windows.md` 191 行の「確保失敗を `OUT_OF_MEMORY` に置換」「Bridge 境界で例外正規化」を満たさない。
- 対応:
  - 全 C Bridge を共通の例外変換 wrapper に通し、戻り型別の安全な失敗値と `pError` を設定する。
  - payload 生成を `try/catch` で囲み、`std::bad_alloc` は `OUT_OF_MEMORY`、その他は `UNKNOWN` として pending を必ず 1 回完了させる。
  - `init` は段階的 commit または scope guard で HWND、watcher、backend を巻き戻す。

### H3. `StartWatch` の登録途中失敗で token を失い、解除再試行も購読 gate も成立しない

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:355`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:357`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:387`
- `state->alive` を全 3 イベントの登録完了前に `true` にしているため、登録途中の callback が公開コールバックへ到達できる。
- rollback の解除が例外を投げても、各 `has*Token_` を無条件に `false` にする。残存 token を失い、`revokePending_` にも遷移しないため、`StopWatch` で解除を再試行できない。
- `StartWatch` は `watching_` しか確認せず、`revokePending_` 中の再登録拒否も実装されていない。
- 設計 864〜869 行および D-21/D-34 に反する。
- 対応:
  - callback gate は 3 登録の commit 後にだけ開く。
  - rollback は解除に成功した token だけをクリアし、失敗分を保持して `revokePending_ = true` にする。
  - `revokePending_` 中の `StartWatch` を拒否し、`StopWatch` で再試行できる状態機械にする。

### H4. `StopWatch` が in-flight callback をドレインせず、`CanDestroy` が実行中でも true になる

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:408`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:432`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:435`
  - `windows/WindowsLibrary/WindowsClipboardHistoryWinRt.cpp:444`
- 設計では gate を閉じてから token を解除し、入場済み callback が終了するまで `CanDestroy == false` を維持する必要がある。
- 実装は token 解除後に `alive = false` とし、直後に `watchState_.reset()` する。既に callback が `inFlight` を増加させていても、`CanDestroy` は `watchState_ == nullptr` を理由に true を返す。
- その結果、callback が公開関数ポインタを呼んでいる最中に backend、Manager、ホスト側 delegate の寿命終了を許し得る。
- 対応:
  - 最初に gate を閉じ、旧 state を retired state として `inFlight == 0` まで保持する。
  - token 残存、revoke pending、retired callback のいずれかがあれば `CanDestroy` を false にする。
  - stop と callback 入場の競合テストを追加する。

### H5. 自書き込み抑止用 `NoteSelfWrite` が一度も呼ばれず、全 toolkit 書き込みが外部変更として通知される

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp:740`
  - `windows/WindowsLibrary/WindowsClipboardManager.cpp:223`
- `ClipboardWatcher::NoteSelfWrite()` は実装されているが、呼び出し箇所が存在しない。copy、clear、複数形式、遅延予約の成功後に sequence が記録されないため、`TakeSelfWrite` は常に false となる。
- 設計 F-09、T-12、D-16 の自書き込み抑止を満たさず、変更 callback 内で再コピーする利用形態では通知ループを起こし得る。
- 対応:
  - クリップボード内容を変更した各成功経路で、Close 後の最新 sequence を `NoteSelfWrite` へ記録する。
  - 複数スレッド連続書き込み、message coalescing、外部書き込みの混在をテストする。

### H6. 機微情報の除外 marker 配置失敗を成功扱いし、要求と異なり履歴・同期へ残り得る

- 該当:
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp:120`
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp:170`
  - `windows/WindowsLibrary/WindowsClipboardCore.cpp:481`
- `ApplyWriteOptions` は失敗を返せるが、全 copy API が戻り値を無視して `CLIPBOARD_ERROR_NONE` を返す。main payload 配置後に exclusion format の `GlobalAlloc` / `SetClipboardData` が失敗すると、caller は除外成功と認識する一方、データは Win+V やクラウド同期へ残り得る。
- `SENSITIVE` はプライバシー指定であり、best-effort に弱めてよい契約は設計にない。
- 対応:
  - option marker を main payload と同じ transaction の必須項目として扱う。
  - 失敗時は rollback を行い、rollback 失敗は `PARTIAL_STATE` にする。
  - 未定義 option bit も `INVALID_PARAMETER` として拒否する。

## 改善提案（Medium）

### M1. WinRT 履歴イベント callback の例外が event ABI へ漏れる

- `WindowsClipboardHistoryWinRt.cpp:93` の `RaiseEvent` は `fn(*events)` を捕捉しない。
- `HistoryEnabledChanged` / `RoamingEnabledChanged` の handler は 371/378 行で WinRT API を例外保護なしに呼ぶ。
- `ClipboardHistoryCoordinator.cpp:288` で生成する公開 callback wrapper も例外を捕捉しない。
- `windows.md` 199 行の C ABI callback 契約に従い、WinRT 呼び出しと公開 callback の両方を捕捉し、ログ後に state guard を必ず解放すること。

### M2. `copyMultipleFormats` が確定 JSON スキーマと境界検証を満たさない

- `WindowsClipboardManager.cpp:348` は `text` / `html` のみで、設計 1506 行の `base64` を処理しない。
- 372 行の `(text.size() + 1) * sizeof(wchar_t)` は checked 演算を使っていない。
- `format` と payload 種別の整合も確認しないため、例えば `CF_HDROP` に UTF-16 text block を配置できる。
- base64 decode、checked size、重複 format、標準 format ごとの構造検証を追加すること。

### M3. `hasClipboardFormat` の成功時に `pError` が更新されない

- `WindowsClipboardManager.cpp:398` は正常終了時に `CLIPBOARD_ERROR_NONE` を設定しない。
- caller が以前のエラー値を再利用すると、戻り値が有効でも `pError` が失敗のまま残り、「返り値が有効 ⇔ error == NONE」の公開契約を破る。

### M4. 履歴 timestamp を `double` の JSON number に変換し、`int64` 精度を失う

- `WindowsClipboardHistoryCoordinator.cpp:25` は FILETIME 相当の 64-bit tick を `double` に変換する。
- 現在の FILETIME 値は `2^53` を超えるため、下位 bit が失われ、公開スキーマの `<int64>` と一致しない。
- 文字列で返す、単位を安全な整数範囲へ落とす、または schema を明示的に変更する必要がある。

### M5. 変更監視の登録失敗を `init` 成功として隠している

- `WindowsClipboardManager.cpp:149` は `ClipboardWatcher::Start` 失敗時も `CLIPBOARD_ERROR_NONE` で初期化を完了する。
- `onChanged` を指定した caller は監視不能を検知できず、定義済みの `MONITOR_REGISTER_FAILED` も返らない。
- callback が非 null の場合は初期化を rollback して失敗させるか、監視開始を独立 API にして成否を返すこと。

### M6. 設計で要求した失敗注入・Manager・watcher テストが未実装

- `WindowsLibraryTest.vcxproj:107` は Core、Manager、Window、WinRT watcher をテスト対象から除外している。
- `IClipboardWin32Api` seam は Core 単体で利用でき、STA/WinRT を必要とせず `SetClipboardData`、`EmptyClipboard`、listener 解除失敗を検証できる。実装結果の「Manager/WinRT 依存のため不可」という理由は Core seam テストには当てはまらない。
- H1〜H6 の多くが、設計 1242〜1269 行で明示された未実装テスト領域にある。DoD の seam 再現を「○」とするのではなく未達として扱うこと。

### M7. Release/Win32 構成に export 定義と UTF-8 設定がなく、新規 Clipboard 警告が発生する

- `WindowsLibrary.vcxproj:120` の `WINDOWSLIBRARY_EXPORTS` は Debug|x64 にしかなく、Release|x64 の 208 行などにはない。そのため Release ビルドで Clipboard 公開関数に C4273 が発生する。
- 設計で明記した `/utf-8` も各構成に設定されておらず、新規 Clipboard header/source で C4819 が発生する。
- 全構成の共通 Property Sheet または各 `ItemDefinitionGroup` へ設定を統一すること。

## 軽微な指摘（Low）

### L1. Bridge 関数自体に entry log がない

- `WindowsClipboardManager.cpp:574` 以降の Bridge は Manager へ委譲するだけで、Bridge entry のログを持たない。
- `windows.md` の「全ての Bridge API のメソッド冒頭でログ」に合わせ、例外 wrapper と合わせて Bridge 名を記録すること。

### L2. 実装結果の検証済み表現が実態より強い

- 実装結果 165 行は Win32 failure seam を「○」としているが、テストコードも実行結果もない。
- 172 行のエラー正規化も実 WinRT 例外だけでなく C ABI の非 WinRT 例外が未処理である。
- 修正後は「実装済み」「自動テスト済み」「実機確認済み」を分けて記載すること。

## 設計書整合性チェック

- 企画書との整合性: △ — 同期/非同期の大枠は一致するが、D-16、D-18、D-21、D-25、D-33、D-34 が未達
- Clean Architecture 準拠: ○ — 履歴 coordinator / backend Port の分離は維持
- 既存実装との差分分析・正確性: △ — UnityWindowsPlugin 非変更とファイル単位 C++20 は適切。全構成設定と working tree の整理が未完
- テスト設計の網羅性: × — 設計で要求した Manager、Win32 failure seam、WinRT watcher 状態遷移が未実装
- ドメインエラー全ケース実装: × — C ABI 例外、payload 確保失敗、監視登録失敗、option marker 失敗に穴がある
- エラーコード・メッセージ対応表との整合: △ — 主な WinRT status は変換済みだが、成功時 `pError` と例外経路に不整合

## プロジェクトルール適合チェック

- `common.md` 準拠: △ — 公開境界の失敗正規化とテスト完了条件が未達
- `windows.md` 準拠: × — C ABI 例外捕捉、callback 例外捕捉、Bridge entry log、`/utf-8` が未達
- エラー契約反映: × — 例外越境、`std::terminate`、stale `pError` がある
- 既存 API 互換性: ○ — 既存 export の破壊的変更と UnityWindowsPlugin の変更はない

## テストカバレッジ

- カバー済み:
  - checked 演算、CF_HTML、DROPFILES、DIB、Unicode text、UTF 変換
  - coordinator の受付、完了、cancel、drain、mock backend の基本契約
  - 既存 Notification 回帰
- 不足:
  - Manager init/uninit と任意スレッド API の競合
  - C ABI / JSON payload 確保失敗
  - Win32 failure seam と rollback
  - 自書き込み sequence 抑止
  - write option marker 失敗
  - WinRT token 登録途中失敗、rollback 解除失敗、in-flight drain
  - 実クリップボード、WinRT 履歴、packaged/unpackaged の実機確認

## 実行確認

- `git diff --check -- windows/WindowsLibrary windows/WindowsLibraryTest`: 成功
- Debug|x64 `WindowsLibrary`: ビルド成功
- Debug|x64 `WindowsLibraryTest`: ビルド成功
- Release|x64 `WindowsLibrary`: ビルド成功（既存警告に加え、新規 Clipboard の C4273/C4819 を確認）
- `vstest.console.exe windows\WindowsLibraryTest\x64\Debug\WindowsLibraryTest.dll`: **73/73 成功**

## 総合評価

**要修正（重大）**

同期/非同期の公開方式と C++17/C++20 の分離は適切だが、設計の中心である shutdown gate、event token の再試行可能性、C ABI 例外安全、自書き込み抑止、機微情報除外の保証が成立していない。H1〜H6 を修正し、少なくとも Manager/Win32 seam/watcher の失敗系テストを追加してから再レビューする必要がある。
