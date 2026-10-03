# レビュー結果

- 日付: 2026-09-20
- 対象ファイル: `artifact/topics/windows-architecture/designs/2026-09-20-windows-architecture-cpp-api-design.md`
- トピック名: windows-architecture（段階 3: C++ API）
- 対象 OS: Windows 11 以降
- 対象版: v1（初版。700 行）
- 判定: **要修正**（実装へ進まず改版する）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行）
- 機械照合: `python scripts/check_design_consistency.py` → 12 OK / 0 FAIL / 14 SKIP

---

## 強み

- 47 関数すべての置き換え先（8.1）と、同期・非同期の縦断（9 章）を両方に置き、機械照合で突き合わせている。
- 既存の約束（Clipboard / Notification）の継承表（10 章）を設けた。番号は設計書が振ったもので、内容の抜き取り確認では CLP-86、CLP-112、CLP-119、CLP-123、CLP-125、NTF-33、NTF-41、NTF-44、NTF-50 がヘッダーおよび元の設計書と一致した。
- エラーの列挙を機能ごとに分け、3 つの番号空間を統合しない判断は妥当。11.1 の 20 値と 11.2 の 9 値はヘッダーと 1 対 1 で一致する。
- 6.1 の実測値（`.def` 39 / `__declspec` のみ 13 / 合計 52）、6.4 の行数と再試行ループ 4 か所、6.3 のプロジェクト構成はいずれも正確。
- タスクの依存は解決し、見積の合計も宣言と一致する。

## 改善点

### 高優先度

1. **段階 3 の成果物のままでは C++ API をリンクできない**（両者が指摘）
   - `WindowsLibrary` は全構成 `DynamicLibrary` で、新しい C++ API は `__declspec(dllexport)` も `.def` の記載も持たない。サンプルの include パスもビルドスクリプトのヘッダー一覧も更新するタスクが無い。
   - 段階 4（サンプルの移行）が着手できない。静的な C++ コアと、既存 47 関数を持つ DLL ブリッジに段階 3 で分ける。

2. **`Session` の寿命が破綻している**（両者）
   - 参照カウント付きの共有ハンドルとしたが、最終破棄が任意スレッドで起こりうる一方、`RemoveClipboardFormatListener` と `DestroyWindow` はオーナースレッド限定。ポンプ停止後、コールバック実行中の破棄、ハンドラが `Session` を捕捉した場合の循環が未定義。
   - `Close()` が全ハンドルを無効化するなら共有の意味が無く、N-1 の根拠（2 つの部品が共有できる）と矛盾する。

3. **`Close()` のエラーを `Busy` に潰しており、C ABI の動作を変える**（両者）
   - 実装（`ClipboardManager::Uninit`）は `WrongThread` / `MonitorRegisterFailed` / `Canceled` / `Busy` / 回復失敗の 5 通りを返し分けている。
   - さらに「`Close()` 後は残りのハンドルが `NotInitialized`」と書いたため、完了後に `TRUE` + `NONE` を返す今の実装と食い違い、サンプルの再試行ループが無限ループになる。

4. **10 章に Dialog の表が無い**（Claude）
   - 3.2 の G-1 で「コードから起こして 10 章に書く」としながら実施していない。Dialog は元の設計書が存在しないため、10 章が唯一の記録になる。
   - 失われる契約: キャンセルでも `TRUE` を返す、複数選択は `0` / `-1`、失敗時の `buffer[0] = L'\0'`、フォルダ選択が自前で `CoInitializeEx` する、既定タイトル `Select Folder`、`FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM`。

5. **`AlertRequest` が `MB_*` の 4 引数を落としている**（Claude）
   - `showAlertDialog` は `buttons` / `icon` / `defbutton` / `options` の 4 つの `UINT` を受ける。8.2 の型定義にこれが無く、`<windows.h>` を公開しない方針とも両立していない。

6. **`Result<T, E>` は `std::expected` に差し替えられない**（Codex が高、Claude が低）
   - `std::expected` はエラーからの暗黙変換を持たず `std::unexpected` 経由。`value()` は `bad_expected_access` を投げる。特殊メンバ、`Result<void>` の実体、`T == E` の曖昧さも未定義。
   - RK-06 の緩和策（同名の最小集合に絞る）が目的を果たしていない。

7. **8.2 の型が実装できる粒度で書かれていない**（両者）
   - 型名の列挙にとどまり、`FormatPayload` の判別、`NotificationContent` の項目、`SessionOptions` / `ManagerOptions` / `RuntimeVersion` の宣言が無い。1 章の「段階 4 をこの設計書だけで書き換えられる」を満たさない。

8. **9 章の OP-43 / OP-44 が実装と違う**（Claude）
   - `SetHistoryItemAsContentAsync` は存在しない。実装は `GetHistoryItemsAsync` で項目を引き当ててから同期の `SetHistoryItemAsContent` / `DeleteItemFromHistory` を呼ぶ。OP-44 の「Repository = 同期」も誤り。

9. **`HWND__` の前方宣言だけでは `HWND` を公開宣言に書けない**（Codex が高、Claude が低）
   - 宣言が無い翻訳単位で名前が解決しない。`NO_STRICT` の利用者では暗黙変換も成立しない。

10. **静的ライブラリの依存伝播を段階 5 に送るのは遅い**（Codex）
    - 静的ライブラリは MSBuild の設定を伝播しない。C++/WinRT と Windows App SDK の `.props` / `.targets`、`Microsoft.WindowsAppRuntime.Bootstrap.dll` の配置が利用者側に必要になる。`MddBootstrapShutdown` も呼ばれていない。

### 中優先度

- **`CLP-xx` / `NTF-xx` の ID が元の設計書に存在しない**（Claude）。「各設計書の記述に対応する」という記述は検証できない。出典の行番号を併記するか、表現を改める。
- **履歴の完了コールバックが `RequestId` を落としている**（Codex）。今の C ABI は `(requestId, error, json)` を渡しており、情報量が減る。
- **「公開 API は例外を投げない」は成立しない**（Codex）。`std::function` への変換は本体に入る前に投げうる。
- **`wstring_view` / `span` の寿命と NUL 終端の規則が無い**（Codex）。`ReserveDeferred` は形式名と provider を保持するため深いコピーが要る。
- **`Manager` の所有と COM の釣り合いが未定義**（Codex）。`CoInitializeEx` に対する `CoUninitialize` が無い。
- **`setBadge` の unpackaged `NotSupported` が 3 か所で欠落**（両者）。
- **11.4 の表が実装の分岐から導出されていない**（Codex）。`OP-08` の範囲指定、`OP-21` の `Unknown` 欠落など。
- **`copyMultipleFormats` の payload 種別の事前検証が 10 章に無い**（Claude）。`FormatPayload` を素朴な構造体にすると CF_HTML の構築と検証が落ちる。
- **遅延レンダリングの 2 相を 1 回に畳むと既存の単体テスト 2 件が変わる**（Claude）。12.1 の「そのまま通る」と矛盾する。
- **ユニットテストの件数が誤り**（Claude）。88 ではなく baseline の 85（合計 106）。
- **`/GL` が Release 構成で有効なまま**（Claude）。D-3 の「配る `.lib` では `/GL` を使わない」に反する。`/MT` 構成を作るタスクも無い。
- **公開ヘッダーの include 許可リストが不足**（両者）。`<cstddef>`、`<string_view>` などが列挙されていない。

### 低優先度

- **N-6 が事実誤認**（Claude）。`setClipboardHistoryCallbacks` は既に 3 つの関数ポインタを取り、受け手は種別を区別できる。型が共用されているだけ。
- **`CanClose` のスレッド制限が実装より厳しい**（Codex）。今は任意スレッドから呼べる。
- **cold start のコールバックは `Manager::Create` の中から呼び出しスレッドで発火する**（Codex）。「OS が選んだスレッド」だけでは不正確。
- **9.1 が `windows.md` の誤った行を参照**（Claude）。OP-44〜46 は表の 2 行目に該当する。
- **`Common/common.h` の 5 関数の扱いが未決**（Claude）。`ToWString` の `std::wstring` 値返しと `ConcatWStrings` の `delete[]` 契約は申し送りが要る。
- **12.1 のヘッダー数の記述ゆれ**（3 と 5）、**`RequestId` の 0 の扱いの書き方**（Claude）。

## 不足項目

- 利用者の前提（ビルド、リンク、実行、呼び出し方）をまとめた節。v1 には途中で追加したが、静的ライブラリの変種（`/MD` / `/MT`）と `/GL` の扱いが欠けていた。
- Dialog の契約の記録（上記 高 4）。
- 段階 3 の成果物の構成（上記 高 1）。

## 総合評価

**要修正。** 実装に進める状態ではない。カテゴリ A（動作・API・契約を変える、または後続段階を塞ぐ）が 9 件あり、うち 3 件（成果物の構成、`Session` の寿命、`Close()` のエラー）は設計判断のやり直しを伴う。

一方で、47 関数の対応表・同期非同期表・エラー列挙・機械照合の骨格は妥当であり、改版は全面的な書き直しではなく、上記の穴を塞ぐ作業になる。
