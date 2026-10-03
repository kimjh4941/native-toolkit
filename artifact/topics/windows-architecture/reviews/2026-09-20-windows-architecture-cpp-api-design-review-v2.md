# 再レビュー結果

- 日付: 2026-09-20
- 対象ファイル: `artifact/topics/windows-architecture/designs/2026-09-20-windows-architecture-cpp-api-design.md`
- トピック名: windows-architecture（段階 3: C++ API）
- 対象 OS: Windows 11 以降
- 対象版: v2（v1 のレビューを反映した第 2 版。980 行）
- 判定: **要修正**（もう 1 周。ただし v1 より範囲は小さい）
- 別モデルによる独立レビュー: 実施済み（v1 と同じ 2 者に、前回指摘の反映状況を含めて依頼）
- 機械照合: 12 OK / 0 FAIL / 14 SKIP

---

## 強み

- v1 の構造的な欠陥（決めていない事項、自己矛盾する所有モデル、着手できない段階 4）は解消した。残る指摘はすべて「正しい仕組みを挙げたが、コードと突き合わせていない」という同じ性質のものに変わった。
- `Close()` の 5 通りの返し分けと冪等性が `ClipboardManager::Uninit` の分岐と一致することを、2 者ともコードで確認した。
- 9 章の OP-43 / OP-44 が実装（`RunSetItemAsContentAsync` / `RunDeleteItemAsync`）と一致する形に直った。
- 10 章の ID の出典（行番号）の併記は有効な改善。抜き取り 18 件のうち 16 件が正しい位置を指していた。
- `wstring_view` / `span` の寿命規則、`RequestId` をコールバックに渡す変更、`CanClose` の任意スレッド、cold start の配送位置、`/FAILIFMISMATCH` の限定、`/await` を伝播させない判断は、いずれも技術的に妥当と確認された。

## 改善点

### 高優先度

1. **成果物の分割が今のソース構成では成り立たない**（両者）
   - Claude: 静的ライブラリのオブジェクトは参照されないとリンクされない。Dialog の 6 関数と `initWinAppSdk` は `.def` に無く、ライブラリ内からも呼ばれないため、分割すると **DLL から 7 つの export が消える**。サンプルと 13 件の Dialog UI テストが壊れる。
   - Codex: C ブリッジが実装と同じ翻訳単位にあり、`WINDOWSLIBRARY_EXPORTS` を静的コアで定義するかどうかで、コンパイル不能・export 欠落・静的コアに export 指令が混入のいずれかになる。`Common` の 5 関数の扱いも未処理。
   - 対処: C ブリッジを **T-02 の時点で** DLL 側の翻訳単位へ移す。export マクロを 7.6 で明示する。47 関数 + `Common` 5 関数を `.def` に列挙する。T-02 の完了条件を `dumpbin /exports` の差分ゼロという機械的な形にする。

2. **`WindowHandle` のコードがコンパイルできない**（両者）
   - `namespace NativeToolkit` の中で `struct HWND__;` を宣言し、`::HWND__*` を別名にしている。`<windows.h>` が無ければ大域の `HWND__` は未宣言で、あれば名前空間内の宣言が別の未使用型になる。
   - U-D（ヘッダー単独 include）が定義上通らない。v1 より悪化している箇所。
   - 対処: `struct HWND__;` を大域に置き、別名だけを名前空間内に置く。`STRICT` 前提の注記は維持する。

3. **C++ の型が今の C ABI の情報を表せない**（両者）
   - Dialog: `showAlertDialog` は 4 つの `UINT` を OR して `MessageBoxW` に渡す。`AlertRequest` は `topMost` のみで、`MB_SYSTEMMODAL` / `MB_SETFOREGROUND` / `MB_HELP` などが表せない。`AlertResult` に `IDHELP` が無い。
   - Notification: `scenario`、`timestamp`、`inlineImage`、appLogo の crop、進捗のタイトル、音声のプリセット名、ボタンの `args`（任意のキー値）が欠落。`AudioSpec::Preset` にプリセット名のフィールドが無く実装不能。**`expiration` は相対秒（`now() + seconds`）であり、`expiresAt`（絶対時刻）は誤り**。`arguments` と `invokeUri` の排他は**ボタン単位**の規則。`ActivationArgs` も任意のキー値を保持できない。
   - Dialog（続き）: 複数ファイルの戻り値は件数ではなく **N+1**（フォルダ名を含む）。`OFN_OVERWRITEPROMPT` など `OFN_*` の記録が無い。既定フィルター `L"All Files\0*.*\0"` の記録も無い。ファイル系 3 API には今タイトル引数が無い。
   - 重大な点: これらは**サンプルが使っていないため UI テストが通ってしまう**。T-14 の完了条件「baseline と一致」では検出できない。
   - 対処: DTO を実装のパーサから導出し直す。Win32 のフラグ語と生のフィルター文字列は、ブリッジが内部層を直接呼ぶ逃げ道を用意する。T-14 の完了条件を「C ABI が受け付ける入力の一覧を実装から導出して突き合わせる」に変える。

4. **`Session` のデストラクタの方針が実装できない**（Codex。Claude は解消と判定したが、Codex の指摘のほうが妥当）
   - 「オーナースレッドなら `Close()` を 1 回」「ポンプ停止後は投稿して戻る」は文脈が重なり、**ポンプが今後回るかを判定する確実な Win32 の手段は無い**。`PostMessage` の成功は実行を保証しない。
   - pending がある場合、最初の `Close()` は `Canceled` を返す。`Session` が消えた後に誰が後続の `Close()` を完遂するのかが未定義。コールバック深度の再入ガードも無い。
   - 対処: どちらかに一本化する。(a) `Close()` の成功を必須とし、デストラクタは放棄 + デバッグ時 assert（非同期に片付くという約束を取り下げる）。(b) `Session` より長生きする、マネージャ所有の終了状態機械を定義する。ポンプ停止とプロセス終了は回復不能な場合として明示する。

5. **通知の 2 回目の init は今コールバックを差し替えている**（Claude）
   - `Init` は早期 return の前に `m_callback` を更新するため、2 回目は冪等な成功かつハンドラの差し替えになる。7.4.2 の「Clipboard と同じ」という前提は通知には当てはまらない。
   - `ManagerOptions::onInvoked` は `Create` でしか渡せないため、DLL ブリッジが今の動作を再現できない。
   - 対処: `Manager::SetInvokedHandler` を足すか、ブリッジが自前の thunk を保持して差し替える旨を記す。10.2 に差し替えの約束を追加する。

6. **通知の COM の扱いが誤っている**（両者）
   - `CoInitializeEx(nullptr, COINIT_MULTITHREADED)`（MTA）であり、7.4.2 は mode を書いていない。MTA で初期化されたスレッドでは、その後の `Session::Create` が `WrongApartment` になる。
   - `S_FALSE` も成功であり解除が要る。`Manager::Close()` は `void` で、別スレッドからの解除拒否を報告できない。N-8 の `CoUninitialize` 追加は `uninitNotificationManager` の動作変更になり、T-14 の「動作を変えない」に反する。
   - 対処: mode と `RPC_E_CHANGED_MODE` の許容を明記する。段階 3 では N-7 と同じく現状維持にするか、C++ API 側だけに閉じる。

### 中優先度

- **`Runtime` の後始末を段階 5 に送る境界が誤り**（Codex）。`InitializeRuntime` は段階 3 で公開 API になるため、ムーブのみの `Runtime` トークンを今作るべき。加えて **`initWinAppSdk` は本来 unpackaged 専用**（ヘッダーに明記）であり、7.5.4 が全利用者の前提としたのは誤り。packaged では `MddBootstrapInitialize2` の no-op オプションを使う。
- **T-03 をブロッキングのスパイクに格上げすべき**（Codex）。`/MT` の成否と伝播するライブラリが決まらないと 7.5 を確定できない。C++/WinRT のマクロは「利用者への助言」ではなく、1 つの EXE / DLL を構成する全ファイルで一致が必要。
- **`Result<T, E>` の制約が未定義**（Codex、Claude）。コピー・ムーブを `T` / `E` の性質から条件付きで有効化・削除しないと、`Result<Session>` / `Result<Manager>` が成立しない。`value_or` も同様。`error() &&` が無い。無検査の `value()` に `noexcept` が無い。`<new>` / `<memory>` が include 許可リストに無い。
- **8.2 の宣言が不完全**（Codex）。`Manager` の宣言が無い。`Session` が空。`Result<void, E>` が前方宣言のみ。エラー列挙は表であって宣言ではない。
- **公開の集約型が不定・矛盾した状態を許す**（Codex）。`FormatPayload::kind`、`ProgressUpdate` の数値、`NotificationRef::id`、`HistoryAvailability` の bool に既定値が無い。`FormatPayload` は `std::variant` にすべき。
- **11.4 が実装から導出されていない箇所が残る**（両者）。`OP-21` に `Unknown`（ウィンドウ生成失敗、backend 生成時の例外）が無い。`OP-08` に `CoInitializeEx` 失敗の `HResultFailure` が無い。通知の意味検証は `InvalidPayload` ではなく `InvalidParameter` を返している。
- **`SessionOptions::foregroundWindow` は誰も読まない**（Claude）。フォアグラウンド判定は `GetForegroundWindow` + PID 比較であり、CLP-58 の「変更なし」と矛盾する。
- **T-02 が `WindowsLibraryTest` の対象を変えてしまう**（Claude）。今はライブラリの 8 つの翻訳単位だけを選んでコンパイルし、`WINDOWSLIBRARY_EXPORTS` を定義している。静的コア全体をリンクすると WinRT の実背面と singleton が入る。
- **サンプルの `ProjectReference` の付け替えが未記載**（Claude）。段階 4 では `WindowsLibraryCore.vcxproj` を参照する必要がある。T-03 の完了条件にサンプルが含まれていない。
- **C ABI のフィルター文字列の往復が未定義**（Claude）。`L"desc\0*.txt\0"` を `FileFilter` に解析して再構成する規則が無い。

### 低優先度

- **12.1 の文が自己矛盾**（Claude）。「例外は遅延レンダリングの 2 件」と書いた直後に「こちらも変わらない」と続く。
- **10 章の引用 2 件が誤り**（Claude）。CLP-125 の 1514 行はファイル一覧の行。CLP-133 の 110 行は落とし穴の行で、正しくは 9 行。**引用を検査する仕組みが無いため劣化する**ので、`scripts/check_design_consistency.py` に「引用行の前後 3 行に約束の語が現れること」を検査させるべき。
- **`NotSupported` の意味を広げている**（Claude）。「Windows に無い操作」に「2 個目の `Create`」を足した点を表に明記し、ブリッジ側には現れないことを書く。
- **`CanClose` の任意スレッド化は要検証**（Claude）。`IClipboardHistoryBackend::CanDestroy` の実装がオーナースレッド外で安全かを確認していない。
- **8.2 のフィールド名が JSON のキーとずれている**（Claude）。`content` / `label`、`defaultItemId` / `defaultSelection`、`placeHolder` / `placeholder`、`heroImageUri` / `heroImage`。U-B の比較のために対応表が要る。

## 前回指摘の反映状況

| 反映 | 件数 | 内容 |
|---|---|---|
| 解消 | Claude 16 件 / Codex 7 件 | `Close()` の 5 通りと冪等性、OP-43 / OP-44、テスト件数、`setBadge`、`CancelRequest`、N-6 の削除、受付スレッドの明記、`RequestId` の追加、`wstring_view` の寿命、例外の約束の限定、`/FAILIFMISMATCH` の限定、`CanClose`、cold start ほか |
| 部分解消 | Claude 5 件 / Codex 7 件 | Dialog の表（内容に誤りと欠落）、`MB_*`（ブリッジ方向が落ちる）、リンク可能性（分割に穴）、8.2 の完全性、`Result`（制約が未定義）、静的ライブラリの伝播（未確定）、COM |
| 未対応 | 1 件 | `WindowHandle` の宣言（両者が同じ指摘。v1 より悪化） |

## 不足項目

- 成果物の分割を機械的に確かめる手段（`dumpbin /exports` の差分）。
- C ABI が受け付ける入力の一覧（実装から導出したもの）。UI テストでは代替できない。
- 10 章の引用を検査する仕組み。

## 総合評価

**要修正。** カテゴリ A は Claude が 6 件、Codex が 4 件（重複を除くと 6 件）。ただし v1 と違い、いずれも設計のやり直しではなく、次の 6 点で塞げる。

1. `.def` への 7 関数の追加と、C ブリッジの翻訳単位の分離（T-02 へ前倒し）
2. `HWND__` の宣言位置の修正
3. DTO を実装のパーサから導出し直し、Win32 のフラグ語には逃げ道を用意する
4. `Session` の破棄を 1 つのモデルに一本化する
5. `Result` の特殊メンバを条件付きで定義する
6. `Runtime` トークンの段階 3 での導入と、T-03 のブロッキング化

Claude 側は「v3 のあとは 3 周目の外部レビューを行わず、設計書が定めた検査（U-D、C-10、C-11、T-13、`dumpbin` の差分）で担保すればよい」との意見。Codex 側は上記が残る限り「実装できる状態ではない」との判定。
