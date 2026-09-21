# Windows ライブラリ C ABI 実装設計書（段階 5）

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/windows-architecture/README.md` |
| 対象段階 | 段階 5（段階 3 で分けた DLL を `WindowsLibraryCApi` に改名し、中身を新しい C ABI に置き換える。`UnityWindowsPlugin` を削除する） |
| 対象 OS | Windows 11 以降 |
| 作成日 | 2026-09-21（第 1 版。レビュー前） |
| ブランチ | `feature/NTKIT-16` |
| 前段階 | 段階 3（C++ API）と段階 4（サンプルの移行）は完了。CU-01 の再実行だけが残っている |
| 反映した決定 | D-4（2.0.0 で一括切替）、D-5（公開は `.def` だけ）、D-6（受け渡し方式。E-5 で見直し）、D-7（UTF-8）、D-8（固定幅の型）、D-9（`void* user_data`）、D-10（戻り値でエラー）、E-1〜E-11（この設計書で決めたこと。4.2） |
| 元にした設計書 | `designs/2026-09-20-windows-architecture-cpp-api-design.md`（C ABI はこの C++ API の上に載る。OP の番号、約束、エラーはそこから引き継ぐ） |

- **`PLANNED_SYMBOLS_EXEMPT`**: この設計書は、まだ書かれていない C ABI の名前（`ntk_*`）を定める。実装の前なので、名前が実装に存在するかの照合は T-09 の機械照合が受け持つ

## 1. 利用者が最初に知ること

README 5.1 が冒頭に置くよう求める 3 点。D-6〜D-10 はどれも C ライブラリの定番の作法に沿っているが、組み合わせると利用者が迷う点が残るため、最初に示す。

### 1.1 名前の規則

| 対象 | 規則 | 例 |
|---|---|---|
| 関数 | `ntk_<機能>_<動詞>[_<目的語>]`。機能は `dialog` / `notification` / `clipboard`。機能に属さないものは `ntk_<名詞>_<動詞>` | `ntk_clipboard_copy_text`、`ntk_dialog_show_open_file`、`ntk_string_free` |
| ハンドルの操作 | `ntk_<機能>_<ハンドル名>_<動詞>`。作るのは `_create`、閉じるのは `_close`、解放は `_free` | `ntk_clipboard_session_create`、`ntk_notification_content_free` |
| ハンドルの読み取り | `ntk_<型名>_<項目>`。一覧の要素は `_at` または `_<項目>_at` | `ntk_string_list_at`、`ntk_clipboard_history_item_text` |
| 型 | `ntk_<機能>_<名詞>`。ハンドルは不完全型の `typedef struct ntk_x ntk_x;` | `ntk_clipboard_session`、`ntk_dialog_file_request` |
| 列挙の型 | `typedef int32_t ntk_<機能>_<名詞>;`。C の `enum` は大きさが処理系依存なので使わない（D-8） | `ntk_clipboard_error`、`ntk_dialog_alert_result` |
| 列挙の値 | `NTK_<機能>_<名詞>_<値>` の `#define` | `NTK_CLIPBOARD_ERROR_BUSY`、`NTK_DIALOG_ALERT_RESULT_OK` |
| コールバックの型 | `ntk_<機能>_<事象>_fn` | `ntk_clipboard_history_fn`、`ntk_notification_invoked_fn` |
| ヘッダー | `NativeToolkitC/<機能>.h`。共通の型は `NativeToolkitC/Common.h`（README 3） | `#include <NativeToolkitC/Clipboard.h>` |

- 名前はすべて ASCII の小文字とアンダースコア。C++ API の `NativeToolkit::` と衝突しない
- 今の C ABI の名前（`copyPlainText` など）は 1 つも残さない（D-4。8.3 に対応表）

### 1.2 受け渡しの 3 方式

受け渡しは次の 3 つの方式だけで行う。**どの方式かは向きとデータの形で決まり、利用者が選ぶことはない。**

| 方式 | 使う場面 | 利用者がすること | 手本 |
|---|---|---|---|
| **出力のハンドル** | ライブラリが返すものすべて。文字列 1 つでも一覧でも | 受け取ったハンドルを読み、対応する `_free` を呼ぶ | SQLite、libgit2 |
| **`struct_size` 付きの構造体** | 項目が固定の入力オプション（ダイアログの要求、セッションの設定、進捗の更新） | 構造体を 0 で埋め、`struct_size = sizeof(...)` を入れ、必要な項目だけ書く | Win32 |
| **ビルダーのハンドル** | 入れ子や可変長を含む入力（通知の内容、複数形式のクリップボード書き込み） | `_create` で作り、`_set_*` / `_add_*` で積み、操作に渡し、`_free` する | 各種 C ライブラリのビルダー |

選んだ理由と、D-6 からの変更:

- **呼び出し側のバッファとサイズの問い合わせは使わない（E-5）。** D-6 は「単純な文字列・バイト列はバッファ + サイズの問い合わせ」としていたが、このライブラリの単純な出力は、ユーザーの操作の結果（ダイアログのパス。出し直せない）か、他のプロセスと共有する状態（クリップボード。2 回の呼び出しの間に変わる）のどちらかしかない。サイズの問い合わせが成り立つ「同じ答えを何度でも取れるデータ」が無いため、出力は 1 回の呼び出しで完結するハンドルにそろえた
- 入力の配列（`copy_files` のパス、ダイアログのフィルター）は、呼び出しの間だけ有効な `const char* const*` と件数で受け取る。ライブラリは呼び出しの中で複製する
- 構造体を出力に使わない。項目を足すと ABI が壊れるため（D-6 の理由）

**3 方式の使い分けの例**:

```c
/* 1. struct_size 付きの構造体 (入力) */
ntk_dialog_file_request req = {0};
req.struct_size = sizeof(req);
req.title = "Open";

/* 2. 出力のハンドル */
ntk_string* path = NULL;
if (ntk_dialog_show_open_file(&req, &path) == NTK_DIALOG_ERROR_NONE) {
    use(ntk_string_data(path));
    ntk_string_free(path);
}

/* 3. ビルダーのハンドル (入れ子の入力) */
ntk_notification_content* c = NULL;
ntk_notification_content_create(&c);
ntk_notification_content_set_title(c, "Hello");
ntk_notification_show(manager, c);
ntk_notification_content_free(c);
```

### 1.3 機能ごとのスレッドの前提

**汎用の C ABI だが、スレッドとメッセージの前提は Windows の UI のものである。** コンソールのスクリプトから Clipboard の履歴や遅延レンダリングを使う形は成立しない。

| 機能 | 呼べるスレッド | 必要なもの | 成立しない使い方 |
|---|---|---|---|
| Dialog | 呼び出しスレッドを塞ぐ（モーダル）。UI スレッドから呼ぶ前提 | フォルダのダイアログはライブラリが STA で COM を初期化する | 別のアパートメントの MTA スレッドから呼ぶと、フォルダのダイアログは続行するが親子関係が崩れうる |
| Notification | 任意のスレッド。非同期の OS 操作はライブラリの中で待つので、呼び出しを塞ぐ | unpackaged のときだけ、`ntk_notification_manager_create` より前に `ntk_notification_runtime_initialize` を呼ぶ。Windows App Runtime の導入 | 活性化のコールバックが UI スレッドで来ると思い込むこと。**OS が選んだスレッドで来る**（cold start の 1 回だけは `_create` の中で呼び出しスレッド） |
| Clipboard（読み書き） | 任意のスレッド | セッションが開いていること | - |
| Clipboard（セッション、遅延レンダリング、履歴のハンドラ） | **オーナースレッドだけ**。`ntk_clipboard_session_create` を呼んだスレッドがオーナーになる | オーナーは **STA で、メッセージループを回し続ける**。閉じるのもオーナー | メッセージループを持たないスレッドをオーナーにすること。コールバックも完了も届かない |
| Clipboard（履歴の要求） | 受付は任意のスレッド。**完了はオーナースレッドで**、受け付けた要求 1 件につきちょうど 1 回 | 自プロセスが前面にあること（無ければ完了が `NOT_FOREGROUND` で来る） | コンソールや非表示のプロセスから履歴を読むこと |

- コールバックの中から、そのコールバックを持つハンドルを閉じたり解放したりしない（Clipboard のセッション、Notification のマネージャー）
- コールバックの中で例外を投げない（7.7）

## 2. 設計目的

- 段階 3 で DLL ブリッジとして残した今の C ABI（52 関数）を捨て、D-6〜D-10 に沿った新しい C ABI を `WindowsLibraryCApi` として作る
- 新しい C ABI は **C++ API（OP-01〜OP-47）の薄い包み**にする。振る舞いは C++ API が決め、C ABI は型の変換だけを受け持つ（E-2）
- `unity-native-plugin` が P/Invoke を書き直せる粒度で、今の 52 関数との対応表を出す（README 5.1）
- 利用者（C#、Rust、Python、Go など）が、ヘッダーからバインディングを自動生成できる形にする

## 3. スコープ

### 3.1 In scope

- `windows/WindowsLibraryCApi/`（新規）: プロジェクト、公開ヘッダー `include/NativeToolkitC/`、実装 `src/`、`.def`
- 全関数のシグネチャ、型、エラー、メモリの決まり、スレッドの前提
- 今の DLL（`windows/WindowsLibrary/WindowsLibrary.vcxproj`）と `src/Bridge/` の削除、`UnityWindowsPlugin` の削除
- 今の C ABI のためだけに C++ API に残した項目の整理（E-10）
- C ABI の単体テストと機械照合
- ビルドスクリプトと配布物の名前（`windows-native-toolkit-capi`、2.0.0）
- `agent-rules/coding-rules/windows.md` の修正（C++ API の設計書 5.2。README 5.1 が同じ PR を求めている）

### 3.2 Out of scope

- C++ API の振る舞いの変更。C ABI は C++ API に合わせる。E-10 は C ABI のためだけに置いた項目の削除で、振る舞いは変えない
- `unity-native-plugin` の P/Invoke の書き換え（別リポジトリ。README 5.1）。こちらは対応表（8.3）を出すまで
- `windows/WindowsLibrary/` を `windows/WindowsLibraryCore/` に改名すること（README 3 の目標の構成）。段階 6 の配布物の作り直しと一緒に行う（E-11）
- NuGet、マニュアル、Doxygen の生成（段階 6）、CI（段階 7）
- UTF-16 版の関数（D-7 の「後で決める」。この段階では足さない。E-7）
- COM の初期化と解除の不均衡（C++ API の設計書の N-8、RK-09）。C++ API の振る舞いなので、C ABI はそのまま引き継ぐ
- CU-01 の再実行（段階 3・4 の残り。develop へのマージ前に行う）

## 4. 前提と決定

### 4.1 企画書（README）由来の前提

| 前提 | 出典 |
|---|---|
| 目標の構成は `WindowsLibraryCApi/include/NativeToolkitC/` と `src/<機能>/` と `WindowsLibraryCApi.def` | README 3 |
| 依存の向きは `WindowsLibraryCApi` → `WindowsLibraryCore`。C ABI は型の変換だけ | README 3 |
| 配布物の接頭辞は `windows-native-toolkit-capi` | README 3.1 |
| 2.0.0 で一度に切り替える。今の DLL は `dist/1.11.0/` に残る | D-4 |
| 公開は `.def` だけ | D-5 |
| JSON をやめる。受け渡しは種類ごとに使い分ける | D-6 |
| UTF-8、`<stdint.h>` の型だけ、`<windows.h>` を include しない、すべてのコールバックに `void* user_data`、エラーは戻り値 | D-7〜D-10 |
| 設計書に関数名の規則、3 方式の使い分け、スレッドの前提、52 関数との対応表を置く | README 5.1 |

### 4.2 この設計書で決めたこと

| ID | 決定 | 決めた日・経緯 | 理由 |
|---|---|---|---|
| E-1 | 寿命は**不透明ハンドル**で表す。C++ の `Session` / `Manager` / `Runtime` と 1 対 1 | 2026-09-21 利用者が決定 | C++ API と対応がつく。C# の `SafeHandle`、Rust の `Drop` に包みやすい。状態がプロセス全体に隠れない |
| E-2 | C ABI が包むのは **C++ API の 47 操作だけ**。段階 3 のブリッジが使った内部層への抜け道（`MB_*` の生のフラグ、NUL 区切りのフィルター文字列、2 相の `void*` provider、履歴の JSON）は持たない | 2026-09-21 利用者が決定 | 2 つの API の振る舞いが常に一致する。C ABI だけが持つ振る舞いを作らない |
| E-3 | 通知の内容は**ビルダーのハンドル**で渡す | 2026-09-21 利用者が決定 | 項目を足しても ABI が壊れない。入れ子の配列（ボタン、入力欄、選択肢）を C の構造体で表さずに済む |
| E-4 | エラーの詳細（`Failure::systemCode`）は**スレッドごとの最後の値**を `ntk_last_system_code()` で読む | 2026-09-21 利用者が決定 | 関数の引数が増えない。libgit2 の `git_error_last` と同じ形 |
| E-5 | **出力はすべてハンドル**にする。D-6 の「単純な文字列・バイト列はバッファ + サイズの問い合わせ」を見直す | 2026-09-21 利用者が決定 | 1.2 の理由。サイズの問い合わせが成り立つ出力が無い |
| E-6 | `Common` の 5 関数（`DLog`、`DFLog`、`DFLLog`、`ToWString`、`ConcatWStrings`）の公開をやめる | この設計書の推奨。レビューで確かめる | 内部の補助関数が漏れていたもの。`ToWString` は `extern "C"` の境界で `std::wstring` を値で返しており、C からは呼べない。`ConcatWStrings` は呼び出し側に `delete[]` を求める（C++ API の設計書 2.2 の申し送り） |
| E-7 | 文字列は UTF-8 だけ。UTF-16 版は足さない | この設計書の推奨 | D-7 の「後で決める」への答え。C# は `UnmanagedType.LPUTF8Str` で扱え、主要な言語は UTF-8 の C 文字列を直接扱える。関数の数を倍にしない |
| E-8 | 真偽値は `int32_t`（0 が偽、0 以外が真）。列挙は `typedef int32_t` と `#define` | この設計書の推奨 | C の `bool` の大きさと、C# の既定のマーシャリング（`bool` は 4 バイトの `BOOL`）の食い違いを避ける。C の `enum` の大きさは処理系依存（D-8） |
| E-9 | **0 で埋めた構造体が既定値**になるようにする。C++ で既定が真の項目は、C では名前を反転する（`fileMustExist` → `allow_missing_file`） | この設計書の推奨 | 利用者が項目を書き忘れても、C++ の既定と同じ振る舞いになる。構造体に項目を足したときも、古い利用者は 0 を渡すことになる |
| E-10 | 今の C ABI のためだけに C++ API に置いた項目を消す: `AlertRequest::extraFlags`、`NotificationContent::unknownKeys`。列挙の値 `NotificationError::InvalidPayload`（3）、`DialogError::BufferTooSmall`（3）、`ClipboardError::BufferTooSmall`（7）は**番号を欠番として残し、返さない**ことを Doxygen に書く | この設計書の推奨 | 抜け道を持たない（E-2）ので読み手がいなくなる。C++ API はまだ配布していない（段階 6）ので、消しても利用者はいない。番号は今の利用者の記憶と対応表のために詰めない |
| E-11 | フォルダ `windows/WindowsLibrary/` の `WindowsLibraryCore/` への改名は段階 6 に回す | この設計書の推奨 | 段階 5 の差分を C ABI に集中させる。改名はサンプル、テスト、スクリプトのパスに広く触るので、配布物を作り直す段階 6 で行う |

### 4.3 不足前提

| ID | 不足している前提 | この設計書での扱い |
|---|---|---|
| G-1 | `unity-native-plugin` がどの関数をどう使っているかは、このリポジトリから見えない | 8.3 の対応表を全 52 関数について出す。使われていない関数も落とさない |
| G-2 | C の利用者は C++ の例外を受け取れない | すべての入口で例外を捕まえてエラーに変える（7.7） |
| G-3 | コールバックの `user_data` をいつまで生かせばよいかが、C++ の `std::function` の捕捉のようには自明でない | ハンドルと要求ごとに期限を決め（7.5）、遅延レンダリングの provider には解放のコールバックを付ける |

## 5. 実装方針の適用

### 5.1 common.md

| 方針 | 適用 |
|---|---|
| Bridge 層は薄く保つ | 適用する。C ABI は型の変換、ハンドルの管理、例外の捕捉だけを行い、判断は C++ API に任せる |
| エラーを型付きのまま伝播する | 適用する。機能ごとのエラーの型を分け、値は C++ API の `enum class` と同じにする（11 章） |
| 検査は両辺をソースから導出する | 適用する。`.def`、ヘッダー、C++ の列挙、この設計書の表を突き合わせる（T-09） |
| コメントは英語、公開ヘッダーは ASCII だけ | 適用する |

### 5.2 windows.md の修正（この段階の PR で行う）

C++ API の設計書 5.2 で段階 5 に送った 6 か所を直す（T-12）。

| 節 | 今の記述 | 直した後 |
|---|---|---|
| アーキテクチャ / Bridge の配置 | C Bridge は `WindowsLibrary` に実装し `WindowsLibrary.dll` からエクスポートする。中継用の別 DLL を足さない | C ABI は `WindowsLibraryCApi`（DLL）に置き、機能の実装は `WindowsLibraryCore`（静的）に置く |
| アーキテクチャ / 基本構造 | `XxxManager (singleton)` が公開 API | 公開面は所有するオブジェクト（C++ は `Session` など、C はハンドル）。内部の singleton は残る |
| 原則 | C Bridge は薄く保つ（複雑なデータは JSON 文字列で渡す） | JSON をやめ、1.2 の 3 方式で渡す。薄く保つ原則は残す |
| 文字列・API 取り扱い方針 | `extern "C"` + `__declspec(dllexport/dllimport)` で公開する | C ABI の公開は `.def` だけ（D-5）。C++ API は名前空間付きの通常の宣言 |
| 文字列・API 取り扱い方針 | エラー情報は `DWORD* pError` などの出力引数 | C++ は `Result`、C ABI は戻り値のエラーコードと `ntk_last_system_code()` |
| 文字列・API 取り扱い方針 / Bridge の配置 | 文字列は `wchar_t*` を優先。`UnityWindowsPlugin` は残す | C++ は `std::wstring`、C ABI は UTF-8。`UnityWindowsPlugin` は削除した |

## 6. 既存実装差分サマリー（段階 4 完了時点の実測）

| 項目 | 今 | この段階の後 |
|---|---|---|
| DLL | `windows/WindowsLibrary/WindowsLibrary.vcxproj`（`src/Bridge/` の 8 ファイル + `.def`） | `windows/WindowsLibraryCApi/WindowsLibraryCApi.vcxproj`。今の DLL と `src/Bridge/` は削除 |
| export | 52（機能 47 + `Common` 5） | 105（8.2。機能の操作 47 を含む） |
| 文字列 | `wchar_t*`（UTF-16）。複合データは JSON | UTF-8 の `const char*`。複合データはハンドルとビルダー |
| 型 | `DWORD` / `BOOL` / `BYTE`。ヘッダーの 2 つは `<windows.h>` を先に要求する | `<stdint.h>` / `<stddef.h>` の型だけ。`<windows.h>` を include しない |
| エラー | 最後の引数 `DWORD* pError` | 戻り値。詳細は `ntk_last_system_code()` |
| コールバック | 6 種。文脈ポインタを持つのは `ClipboardRenderCallback` だけ | すべてが先頭に `void* user_data` を持つ |
| 寿命 | `init*` / `uninit*` のプロセス全体の状態 | ハンドル（`_create` / `_close` / `_free`） |
| `UnityWindowsPlugin` | `.sln` から外れた MFC の雛形。README などに 15 ファイル・91 か所の参照（README 6） | 削除。参照を `WindowsLibraryCApi` に直す |
| テスト | `ClipboardBridgeTest`（20）、`NotificationBridgeTest`（5）、`NotificationPayloadTest`（13） | 今の C ABI とともに削除し、12.1 の C ABI のテストに置き換える。C++ API のテストはそのまま |

## 7. 実装アーキテクチャ

### 7.1 成果物とフォルダ

```
windows/
  WindowsLibrary/                           # 段階 6 で WindowsLibraryCore/ に改名（E-11）
    WindowsLibraryCore.vcxproj              # C++ API（静的）。変わらない
    include/NativeToolkit/                  # C++ API のヘッダー。E-10 の整理だけ
    src/                                    # Bridge/ を削除
  WindowsLibraryCApi/                       # 新規
    WindowsLibraryCApi.vcxproj              # DynamicLibrary。WindowsLibraryCore を参照
    WindowsLibraryCApi.def                  # 105 関数（8.2）
    include/NativeToolkitC/
      Common.h  Dialog.h  Notification.h  Clipboard.h
    src/
      Common/        Handles.h/.cpp、LastError.h/.cpp、Utf8.h/.cpp、Guard.h
      Dialog/        DialogCApi.cpp
      Notification/  NotificationCApi.cpp、NotificationContentCApi.cpp
      Clipboard/     ClipboardCApi.cpp、ClipboardItemsCApi.cpp、ClipboardHistoryCApi.cpp
  WindowsLibraryTest/
    CApi/                                   # 新規。12.1 のテスト
```

- `WindowsLibraryCApi` は `WindowsLibraryCore` を静的にリンクする。依存の向きは CApi → Core だけ
- DLL の CRT は `/MD`（今の DLL と同じ）。C ABI の境界では C++ の型も CRT の資源も受け渡さないので、利用者の CRT と一致しなくてよい
- 配布物の名前は `windows-native-toolkit-capi-<版>.dll`（README 3.1）、版は 2.0.0（D-4）。ファイル名はビルドスクリプトが付ける（T-11）
- x64 のみ（C++ API の設計書 7.5.1 と同じ）

### 7.2 公開ヘッダー

- **C99 としても C++ としてもコンパイルできる**。`#ifdef __cplusplus` で `extern "C"` を付ける
- include するのは `<stdint.h>` と `<stddef.h>` だけ。`<windows.h>`、`<stdbool.h>` は使わない（E-8）
- **ASCII だけで書く**（C++ API の設計書 7.1 と同じ理由）
- 各機能のヘッダーは `NativeToolkitC/Common.h` を include する。単独で include してコンパイルできる
- 宣言に `__declspec(dllimport)` を付けない。公開は `.def` だけで（D-5）、利用者は import ライブラリのサンクを通して呼ぶ
- 呼び出し規約は `NTK_CALL`（MSVC では `__cdecl`、それ以外は空）を関数とコールバックの型に付ける。x64 では規約は 1 つだが、バインディングの生成器に明示するため
- ウィンドウハンドルは `void*`（`HWND` と同じ表現）

```c
/* NativeToolkitC/Common.h (excerpt) */
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_MSC_VER)
#define NTK_CALL __cdecl
#else
#define NTK_CALL
#endif

#define NTK_VERSION_MAJOR 2
#define NTK_VERSION_MINOR 0
#define NTK_VERSION_PATCH 0
#define NTK_VERSION ((NTK_VERSION_MAJOR << 16) | (NTK_VERSION_MINOR << 8) | NTK_VERSION_PATCH)

typedef void (NTK_CALL *ntk_release_fn)(void* user_data);

uint32_t NTK_CALL ntk_version(void);
uint32_t NTK_CALL ntk_last_system_code(void);

typedef struct ntk_string ntk_string;
const char* NTK_CALL ntk_string_data(const ntk_string* s);
size_t      NTK_CALL ntk_string_size(const ntk_string* s);
void        NTK_CALL ntk_string_free(ntk_string* s);

typedef struct ntk_bytes ntk_bytes;
const uint8_t* NTK_CALL ntk_bytes_data(const ntk_bytes* b);
size_t         NTK_CALL ntk_bytes_size(const ntk_bytes* b);
void           NTK_CALL ntk_bytes_free(ntk_bytes* b);

typedef struct ntk_string_list ntk_string_list;
size_t      NTK_CALL ntk_string_list_count(const ntk_string_list* list);
const char* NTK_CALL ntk_string_list_at(const ntk_string_list* list, size_t index);
void        NTK_CALL ntk_string_list_free(ntk_string_list* list);

#ifdef __cplusplus
}
#endif
```

### 7.3 エラー

- **失敗しうる関数は、機能のエラーの型（`ntk_<機能>_error`）を戻り値で返す**（D-10）。0 が成功。値は C++ API の `enum class` と同じ（11 章）
- 失敗しない関数（ハンドルの読み取り、`_free`、`ntk_clipboard_session_can_close`、`ntk_version`）は値をそのまま返す。読み取りに範囲外の添字や `NULL` を渡すと `NULL` か 0 を返し、エラーは返さない
- **出力引数は、成功したときだけ書く。** 失敗したときは `NULL` を書く（出力がハンドルの場合）か、触らない（値の場合）
- **エラーの詳細は `ntk_last_system_code()`**（E-4）
  - 失敗しうる関数は、戻る直前に**呼び出しスレッドの**値を書く。成功なら 0、失敗なら `Failure::systemCode`（`GetLastError`、HRESULT、`CommDlgExtendedError`。無ければ 0）
  - エラーを渡すコールバック（履歴の完了）は、呼ぶ直前に**コールバックを呼ぶスレッドの**値を書く。コールバックの中で読める
  - 読み取り関数、`_free`、`ntk_version` は値を変えない
  - 値は次に失敗しうる関数を呼ぶまで残る。**読むなら失敗の直後に読む**

### 7.4 メモリの確保と解放

| 規則 | 内容 |
|---|---|
| 解放は確保した側の関数で | ライブラリが渡したハンドルは、対応する `_free` でだけ解放する。利用者の `free` / `delete` を使わない。ライブラリは利用者のメモリを解放しない |
| `_free(NULL)` | 何もしない |
| 所有するハンドル | `_create` で作ったもの、出力引数で受け取ったもの。利用者が 1 回だけ `_free` する |
| 借りるポインタ | ハンドルの読み取りが返す `const char*` / `const uint8_t*` と、下位のハンドル（履歴の項目など）。**元のハンドルを解放するまで**有効。コールバックに渡されたハンドルとそこから読んだポインタは、**コールバックから戻るまで**有効。保持したいものは利用者が複製する |
| 入力 | 引数の文字列、配列、構造体は**呼び出しの間だけ**有効であればよい。ライブラリは必要なものを呼び出しの中で複製する |
| 文字列の終端 | 出力の文字列は必ず NUL で終わる。`ntk_string_size` は終端を含まないバイト数 |
| バイト列 | `ntk_bytes_data` は、長さ 0 のときも `NULL` でないポインタを返す |

### 7.5 コールバックと `user_data`

すべてのコールバックの**第 1 引数が `void* user_data`**（D-9）。ライブラリは `user_data` を読まず、渡されたまま返す。**いつまで生かせばよいか**を次の表で決める。

| コールバック | 登録 | `user_data` が使われうる期間 |
|---|---|---|
| クリップボードの変化（`ntk_clipboard_changed_fn`） | セッションの設定 | セッションの `close` が成功するまで |
| 履歴の 3 つのハンドラ | `ntk_clipboard_set_history_handlers` | 差し替えるか外すか、セッションの `close` が成功するまで |
| 遅延レンダリングの provider | `ntk_clipboard_reserve_deferred` | **`release` が呼ばれるまで**。ライブラリは provider を手放すとき（予約が置き換わった、全形式を描画した、セッションを閉じた）にちょうど 1 回 `release(user_data)` を呼ぶ。予約が失敗したときも呼ぶ。`release` は `NULL` でもよい |
| 履歴の要求の完了 | `ntk_clipboard_get_history` など | **受け付けた要求は完了がちょうど 1 回来るまで**。受け付けなかった要求（エラーが返った）では呼ばれないので、呼び出し側がすぐ片付けてよい |
| 通知の活性化（`ntk_notification_invoked_fn`） | マネージャーの設定、`ntk_notification_manager_set_invoked_handler` | 差し替えるか、マネージャーの `close` が戻るまで |

- ライブラリはコールバックの戻りを待つ間、呼び出しスレッドのロックを持たない。コールバックからほかの `ntk_*` を呼んでよい。ただし 1.3 の禁止事項（持ち主のハンドルを閉じる・解放する）は守る
- 遅延レンダリングの provider は、要求された形式のバイト列を `ntk_clipboard_render_target_set` で渡し、0（`NTK_CLIPBOARD_ERROR_NONE`）を返す。0 以外を返すと何も描画しない。provider の中でクリップボードの関数を呼ばない。ブロックしない（C++ API の約束 CLP-28 を引き継ぐ）

### 7.6 文字列

- 入力の文字列は **NUL で終わる UTF-8**。不正な UTF-8 は `INVALID_PARAMETER`
- 省略できる入力（C++ で `std::optional` の項目）は、**`NULL` が「無い」、`""` が「空で在る」**。この区別は入力一覧（`designs/2026-09-20-windows-architecture-c-abi-input-inventory.md`）§1.10 の「キーが有って空」の表と同じ意味を持つ
- 省略できない入力の `NULL` は `INVALID_PARAMETER`
- 出力の文字列は NUL で終わる UTF-8。途中に NUL は入らない（C++ API が埋め込み NUL を拒むため）

### 7.7 例外と異常終了

- **すべての入口で例外を捕まえる。** `std::bad_alloc` はその機能の「メモリ不足」に当たる値（Clipboard は `OUT_OF_MEMORY`、Dialog は `UNKNOWN`、Notification は `HRESULT_FAILURE` + `ntk_last_system_code() == E_OUTOFMEMORY`）、それ以外は `UNKNOWN`（Notification は `HRESULT_FAILURE`）にする
- 利用者のコールバックは例外を投げてはならない。C のコールバックは投げられないが、C++ で書いたコールバックが投げた場合は、ライブラリが捕まえて捨てる（C++ API の `ForwardRequestCompletion` と同じ）。SEH の例外は捕まえない

### 7.8 版

- `ntk_version()` は DLL の版を返す。ヘッダーの `NTK_VERSION` と比べれば、ヘッダーと DLL の組み合わせの違いを実行時に検出できる
- **構造体に項目を足すのは互換の変更**（`struct_size` で見分ける）。関数を足すのも互換の変更。既存の関数のシグネチャや意味を変えるのは 3.0.0

## 8. API 設計

**公開 OP**: OP-01〜OP-47 の **47 件**。C++ API の設計書の OP をそのまま使う。

### 8.1 OP ごとの C 関数

戻り値の型は機能のエラー（`ntk_dialog_error` / `ntk_notification_error` / `ntk_clipboard_error`）。引数の `s` はセッション、`m` はマネージャーを表す。

| OP | C++ API | C 関数 | 変換 |
|---|---|---|---|
| OP-01 | `ShowAlert` | `ntk_dialog_show_alert(const ntk_dialog_alert_request*, ntk_dialog_alert_result* out)` | 構造体 → `AlertRequest`。`extraFlags` は持たない（E-10） |
| OP-02 | `ShowOpenFile` | `ntk_dialog_show_open_file(const ntk_dialog_file_request*, ntk_string** out)` | パスをハンドルで返す |
| OP-03 | `ShowOpenFiles` | `ntk_dialog_show_open_files(const ntk_dialog_file_request*, ntk_string_list** out)` | 各要素はフルパス |
| OP-04 | `ShowSaveFile` | `ntk_dialog_show_save_file(const ntk_dialog_save_file_request*, ntk_string** out)` | 同 OP-02 |
| OP-05 | `ShowPickFolder` | `ntk_dialog_show_pick_folder(const ntk_dialog_folder_request*, ntk_string** out)` | 同 OP-02 |
| OP-06 | `ShowPickFolders` | `ntk_dialog_show_pick_folders(const ntk_dialog_folder_request*, ntk_string_list** out)` | 同 OP-03 |
| OP-07 | `Runtime::Initialize` | `ntk_notification_runtime_initialize(uint32_t major_minor, ntk_notification_runtime** out)` | トークンをハンドルにする。`ntk_notification_runtime_free` が `Close` |
| OP-08 | `Manager::Create` | `ntk_notification_manager_create(const ntk_notification_manager_options*, ntk_notification_manager** out)` | 構造体 → `ManagerOptions`。`is_unpackaged`（E-9） |
| OP-09 | `Manager::Close` | `ntk_notification_manager_close(ntk_notification_manager* m)`（戻り値 `void`） | `_free` も未クローズなら閉じる |
| OP-10 | `Manager::Show` | `ntk_notification_show(m, const ntk_notification_content*)` | ビルダー → `NotificationContent` |
| OP-11 | `Manager::Schedule` | `ntk_notification_schedule(m, const ntk_notification_content*, int64_t unix_ms)` | Unix ミリ秒 → `time_point` |
| OP-12 | `Manager::CancelScheduled` | `ntk_notification_cancel_scheduled(m, const char* tag, const char* group)` | - |
| OP-13 | `Manager::UpdateProgress` | `ntk_notification_update_progress(m, const ntk_notification_progress_update*)` | 構造体 → `ProgressUpdate` |
| OP-14 | `Manager::SetBadge` | `ntk_notification_set_badge(m, int32_t value)` | - |
| OP-15 | `Manager::RemoveById` | `ntk_notification_remove_by_id(m, uint32_t id)` | - |
| OP-16 | `Manager::RemoveByTag` | `ntk_notification_remove_by_tag(m, const char* tag, const char* group)` | - |
| OP-17 | `Manager::RemoveAll` | `ntk_notification_remove_all(m)` | - |
| OP-18 | `Manager::GetAll` | `ntk_notification_get_all(m, ntk_notification_list** out)` | `vector<NotificationRef>` → ハンドル |
| OP-19 | `Manager::GetSetting` | `ntk_notification_get_setting(m, ntk_notification_setting* out)` | - |
| OP-20 | `Manager::OpenSettings` | `ntk_notification_open_settings(m)` | - |
| OP-21 | `Session::Create` | `ntk_clipboard_session_create(const ntk_clipboard_session_options*, ntk_clipboard_session** out)` | 構造体（`NULL` 可）→ `SessionOptions` |
| OP-22 | `Session::SetHistoryHandlers` | `ntk_clipboard_set_history_handlers(s, const ntk_clipboard_history_handlers*)` | `NULL` か 3 つとも `NULL` で外す |
| OP-23 | `Session::Close` | `ntk_clipboard_session_close(s)` | 5 通りのエラーをそのまま返す |
| OP-24 | `Session::CanClose` | `ntk_clipboard_session_can_close(const ntk_clipboard_session*)`（戻り値 `int32_t`） | `NULL` は真（閉じるものが無い） |
| OP-25 | `Session::CopyText` | `ntk_clipboard_copy_text(s, const char* text, uint32_t flags)` | `flags` → `WriteOptions` |
| OP-26 | `Session::PasteText` | `ntk_clipboard_paste_text(s, ntk_string** out)` | - |
| OP-27 | `Session::CopyHtml` | `ntk_clipboard_copy_html(s, const char* fragment, const char* plain_text, uint32_t flags)` | - |
| OP-28 | `Session::PasteHtml` | `ntk_clipboard_paste_html(s, ntk_string** out)` | - |
| OP-29 | `Session::CopyFiles` | `ntk_clipboard_copy_files(s, const char* const* paths, size_t count, uint32_t flags)` | - |
| OP-30 | `Session::PasteFiles` | `ntk_clipboard_paste_files(s, ntk_string_list** out)` | - |
| OP-31 | `Session::CopyDib` | `ntk_clipboard_copy_dib(s, const uint8_t* dib, size_t size, uint32_t flags)` | - |
| OP-32 | `Session::PasteDib` | `ntk_clipboard_paste_dib(s, ntk_bytes** out)` | - |
| OP-33 | `Session::CopyCustom` | `ntk_clipboard_copy_custom(s, const char* format_name, const uint8_t* data, size_t size, uint32_t flags)` | - |
| OP-34 | `Session::PasteCustom` | `ntk_clipboard_paste_custom(s, const char* format_name, ntk_bytes** out)` | - |
| OP-35 | `Session::CopyMultiple` | `ntk_clipboard_copy_multiple(s, const ntk_clipboard_items*, uint32_t flags)` | ビルダー → `vector<FormatPayload>`。並びは積んだ順 |
| OP-36 | `Session::HasFormat` | `ntk_clipboard_has_format(s, const char* format_name, int32_t* out)` | - |
| OP-37 | `Session::GetFormats` | `ntk_clipboard_get_formats(s, ntk_string_list** out)` | - |
| OP-38 | `Session::GetPreferredFormat` | `ntk_clipboard_get_preferred_format(s, ntk_string** out)` | 候補が無ければ空文字列（C++ と同じ） |
| OP-39 | `Session::Clear` | `ntk_clipboard_clear(s)` | - |
| OP-40 | `Session::ReserveDeferred` | `ntk_clipboard_reserve_deferred(s, const char* const* formats, size_t count, ntk_clipboard_render_fn provider, void* user_data, ntk_release_fn release)` | provider を `RenderProvider` に包む。`release` は包みの破棄で呼ぶ |
| OP-41 | `Session::RecoverDeferredState` | `ntk_clipboard_recover_deferred_state(s)` | - |
| OP-42 | `Session::GetHistory` | `ntk_clipboard_get_history(s, ntk_clipboard_history_fn cb, void* user_data, uint32_t* out_request_id)` | 完了に借りの `ntk_clipboard_history*` を渡す |
| OP-43 | `Session::RestoreHistoryItem` | `ntk_clipboard_restore_history_item(s, const char* item_id, ntk_clipboard_completion_fn cb, void* user_data, uint32_t* out_request_id)` | - |
| OP-44 | `Session::DeleteHistoryItem` | `ntk_clipboard_delete_history_item(s, const char* item_id, ntk_clipboard_completion_fn cb, void* user_data, uint32_t* out_request_id)` | - |
| OP-45 | `Session::ClearUnpinnedHistory` | `ntk_clipboard_clear_unpinned_history(s, ntk_clipboard_completion_fn cb, void* user_data, uint32_t* out_request_id)` | - |
| OP-46 | `Session::GetHistoryAvailability` | `ntk_clipboard_get_history_availability(s, ntk_clipboard_availability_fn cb, void* user_data, uint32_t* out_request_id)` | 完了に 2 つの真偽値を渡す |
| OP-47 | `Session::CancelRequest` | `ntk_clipboard_cancel_request(s, uint32_t request_id)` | 未知・完了済みは `INVALID_PARAMETER` |

### 8.2 公開する関数の全体（105）

8.1 の 47 操作のほかに、ハンドルの寿命と読み取り、ビルダーの関数を公開する。**`.def` とヘッダーはこの表と一致させる**（T-09 の機械照合）。

| ヘッダー | 群 | 関数 | 数 |
|---|---|---|---|
| `Common.h` | 版とエラー | `ntk_version`、`ntk_last_system_code` | 2 |
| `Common.h` | `ntk_string` | `ntk_string_data`、`ntk_string_size`、`ntk_string_free` | 3 |
| `Common.h` | `ntk_bytes` | `ntk_bytes_data`、`ntk_bytes_size`、`ntk_bytes_free` | 3 |
| `Common.h` | `ntk_string_list` | `ntk_string_list_count`、`ntk_string_list_at`、`ntk_string_list_free` | 3 |
| `Dialog.h` | 操作（OP-01〜OP-06） | 8.1 の 6 関数 | 6 |
| `Notification.h` | ランタイム | `ntk_notification_runtime_initialize`、`ntk_notification_runtime_free` | 2 |
| `Notification.h` | マネージャー | `ntk_notification_manager_create`、`ntk_notification_manager_set_invoked_handler`、`ntk_notification_manager_close`、`ntk_notification_manager_free` | 4 |
| `Notification.h` | 操作（OP-10〜OP-20） | 8.1 の 11 関数 | 11 |
| `Notification.h` | 一覧（OP-18 の出力） | `ntk_notification_list_count`、`ntk_notification_list_id_at`、`ntk_notification_list_tag_at`、`ntk_notification_list_group_at`、`ntk_notification_list_free` | 5 |
| `Notification.h` | 活性化（コールバックの引数） | `ntk_notification_activation_raw_arguments`、`ntk_notification_activation_value_count`、`ntk_notification_activation_key_at`、`ntk_notification_activation_value_at` | 4 |
| `Notification.h` | 内容のビルダー | `_create`、`_free`、`_set_title`、`_set_body`、`_set_tag`、`_set_group`、`_set_scenario`、`_set_hero_image`、`_set_inline_image`、`_set_app_logo`、`_set_attribution`、`_set_duration`、`_set_audio`、`_add_button`、`_add_button_argument`、`_add_text_input`、`_add_combo`、`_add_combo_item`、`_set_progress`、`_set_timestamp`、`_set_expiration`、`_set_expires_on_reboot`（いずれも `ntk_notification_content` の後に続く） | 22 |
| `Clipboard.h` | セッション | `ntk_clipboard_session_create`、`ntk_clipboard_session_close`、`ntk_clipboard_session_can_close`、`ntk_clipboard_session_free` | 4 |
| `Clipboard.h` | 履歴のハンドラ（OP-22） | `ntk_clipboard_set_history_handlers` | 1 |
| `Clipboard.h` | 読み書き（OP-25〜OP-39） | 8.1 の 15 関数 | 15 |
| `Clipboard.h` | 複数形式のビルダー | `ntk_clipboard_items_create`、`ntk_clipboard_items_add_text`、`ntk_clipboard_items_add_html`、`ntk_clipboard_items_add_bytes`、`ntk_clipboard_items_free` | 5 |
| `Clipboard.h` | 遅延レンダリング（OP-40、OP-41） | `ntk_clipboard_reserve_deferred`、`ntk_clipboard_recover_deferred_state`、`ntk_clipboard_render_target_set` | 3 |
| `Clipboard.h` | 履歴の要求（OP-42〜OP-47） | 8.1 の 6 関数 | 6 |
| `Clipboard.h` | 履歴（OP-42 の完了の引数） | `ntk_clipboard_history_count`、`ntk_clipboard_history_item_id`、`ntk_clipboard_history_item_text`、`ntk_clipboard_history_item_content_type_count`、`ntk_clipboard_history_item_content_type_at`、`ntk_clipboard_history_item_timestamp` | 6 |
| 合計 | | | **105** |

公開関数は今の 52 から 105 に増える。D-6 が短所として挙げた「項目 1 つにつき取得関数が 1 つ」の結果で、名前の規則（1.1）で見分けがつくようにした。

### 8.3 今の 52 関数との対応表

`unity-native-plugin` の P/Invoke を書き直すための表（README 5.1）。**すべての関数でシグネチャが変わる**（UTF-8、`user_data`、戻り値のエラー）。`変わる振る舞い` 列は、シグネチャの変更のほかに意味が変わる点。

| 今の関数 | 新しい関数 | 変わる振る舞い |
|---|---|---|
| `showAlertDialog` | `ntk_dialog_show_alert` | `MB_*` の 4 つのフラグ語は列挙になり、それ以外の `MB_*` は渡せない（E-2）。戻り値は `IDOK` などの整数ではなく `ntk_dialog_alert_result` |
| `showFileDialog` | `ntk_dialog_show_open_file` | バッファが足りずに選択を失うことが無くなる。キャンセルは `*pError == -1` ではなく `NTK_DIALOG_ERROR_CANCELED`。フィルターは NUL 区切りの 1 文字列ではなく、名前とパターンの配列 |
| `showMultiFileDialog` | `ntk_dialog_show_open_files` | 先頭のフォルダ名と名前の並びではなく、**フルパスの一覧**。件数にフォルダを数えない（C++ API の OP-03） |
| `showSaveFileDialog` | `ntk_dialog_show_save_file` | 上書きの確認を `skip_overwrite_prompt` で外せる（今は常に確認） |
| `showFolderDialog` | `ntk_dialog_show_pick_folder` | - |
| `showMultiFolderDialog` | `ntk_dialog_show_pick_folders` | - |
| `initWinAppSdk` | `ntk_notification_runtime_initialize` | ハンドルを解放すると `MddBootstrapShutdown` が呼ばれる。**解放するまで Runtime を使い続ける** |
| `initNotificationManager` | `ntk_notification_manager_create` | 2 回目は成功（コールバックの差し替え）ではなく `NOT_SUPPORTED`。コールバックの差し替えは `ntk_notification_manager_set_invoked_handler` |
| `uninitNotificationManager` | `ntk_notification_manager_close` / `_free` | - |
| `showNotification` | `ntk_notification_show` | JSON ではなくビルダー。JSON の解析の失敗（`INVALID_PAYLOAD`）は起きなくなり、意味の検証の失敗は今と同じ `INVALID_PARAMETER` |
| `scheduleNotification` | `ntk_notification_schedule` | 同上 |
| `cancelScheduledNotification` | `ntk_notification_cancel_scheduled` | - |
| `updateNotificationProgress` | `ntk_notification_update_progress` | 6 引数が構造体になる |
| `setBadge` | `ntk_notification_set_badge` | - |
| `removeNotificationById` | `ntk_notification_remove_by_id` | - |
| `removeNotificationsByTag` | `ntk_notification_remove_by_tag` | - |
| `removeAllNotifications` | `ntk_notification_remove_all` | - |
| `getAllNotifications` | `ntk_notification_get_all` | JSON とバッファではなく一覧のハンドル。バッファが足りずに切れることが無くなる |
| `getNotificationSetting` | `ntk_notification_get_setting` | `-1` ではなくエラー。マネージャーが無いときは `NOT_INITIALIZED` |
| `openNotificationSettings` | `ntk_notification_open_settings` | - |
| `initClipboardManager` | `ntk_clipboard_session_create` | 同じスレッドからの 2 回目は成功ではなく `NOT_SUPPORTED`（C++ API の OP-21。段階 4 のサンプルで確かめた差） |
| `setClipboardHistoryCallbacks` | `ntk_clipboard_set_history_handlers` | 3 つのコールバックが 1 つの構造体と `user_data` になる |
| `uninitClipboardManager` | `ntk_clipboard_session_close` | `BOOL` + `pError` ではなくエラーだけ。成功するまで呼ぶ契約は同じ。成功した後に `_free` する |
| `canDestroyClipboardManager` | `ntk_clipboard_session_can_close` | - |
| `copyPlainText` | `ntk_clipboard_copy_text` | オプションのビット `SENSITIVE`（3）は `EXCLUDE_HISTORY` と `EXCLUDE_ROAMING` の両方を立てた値として残す |
| `pastePlainText` | `ntk_clipboard_paste_text` | 2 回の呼び出しが 1 回になる |
| `copyHtml` | `ntk_clipboard_copy_html` | - |
| `pasteHtml` | `ntk_clipboard_paste_html` | 同 `pastePlainText` |
| `copyFiles` | `ntk_clipboard_copy_files` | JSON の配列ではなく文字列の配列 |
| `pasteFiles` | `ntk_clipboard_paste_files` | JSON ではなく一覧のハンドル |
| `copyImage` | `ntk_clipboard_copy_dib` | 名前が中身（DIB）を表すようになる |
| `pasteImage` | `ntk_clipboard_paste_dib` | 同 `pastePlainText` |
| `copyCustomFormat` | `ntk_clipboard_copy_custom` | - |
| `pasteCustomFormat` | `ntk_clipboard_paste_custom` | 同 `pastePlainText` |
| `copyMultipleFormats` | `ntk_clipboard_copy_multiple` | JSON（バイト列は base64）ではなくビルダー（バイト列はそのまま） |
| `hasClipboardFormat` | `ntk_clipboard_has_format` | `BOOL` の戻り値ではなく出力引数 |
| `getClipboardFormats` | `ntk_clipboard_get_formats` | JSON ではなく一覧のハンドル |
| `getPreferredClipboardFormat` | `ntk_clipboard_get_preferred_format` | - |
| `clearClipboard` | `ntk_clipboard_clear` | - |
| `reserveDeferredFormats` | `ntk_clipboard_reserve_deferred` | provider は 2 相（サイズの問い合わせと書き込み）ではなく 1 回。`void* context` が `user_data` になり、`release` が付く |
| `recoverDeferredState` | `ntk_clipboard_recover_deferred_state` | - |
| `getClipboardHistory` | `ntk_clipboard_get_history` | 完了に JSON ではなく履歴のハンドル（コールバックの間だけ有効） |
| `restoreHistoryItem` | `ntk_clipboard_restore_history_item` | - |
| `deleteHistoryItem` | `ntk_clipboard_delete_history_item` | - |
| `clearUnpinnedHistory` | `ntk_clipboard_clear_unpinned_history` | - |
| `getClipboardHistoryAvailability` | `ntk_clipboard_get_history_availability` | 完了に JSON ではなく 2 つの真偽値 |
| `cancelClipboardRequest` | `ntk_clipboard_cancel_request` | `BOOL` + `pError` ではなくエラーだけ |
| `DLog` | 無し | 公開をやめる（E-6） |
| `DFLog` | 無し | 同上 |
| `DFLLog` | 無し | 同上 |
| `ToWString` | 無し | 同上 |
| `ConcatWStrings` | 無し | 同上 |

### 8.4 型の宣言

#### 8.4.1 Dialog

```c
typedef int32_t ntk_dialog_error;           /* 11.1 */
typedef int32_t ntk_dialog_alert_buttons;   /* OK=0, OK_CANCEL, YES_NO, YES_NO_CANCEL, RETRY_CANCEL,
                                               ABORT_RETRY_IGNORE, CANCEL_TRY_CONTINUE */
typedef int32_t ntk_dialog_alert_icon;      /* NONE=0, INFORMATION, WARNING, ERROR, QUESTION */
typedef int32_t ntk_dialog_alert_default_button; /* FIRST=0, SECOND, THIRD, FOURTH */
typedef int32_t ntk_dialog_alert_result;    /* OK=0, CANCEL, YES, NO, RETRY, ABORT, IGNORE,
                                               TRY_AGAIN, CONTINUE, CLOSE, HELP */

typedef struct ntk_dialog_alert_request {
    uint32_t    struct_size;
    const char* title;                      /* NULL is "" */
    const char* message;                    /* NULL is "" */
    ntk_dialog_alert_buttons        buttons;
    ntk_dialog_alert_icon           icon;
    ntk_dialog_alert_default_button default_button;
    int32_t     top_most;                   /* MB_TOPMOST */
    int32_t     show_help_button;           /* MB_HELP */
    void*       owner;                      /* HWND, may be NULL */
} ntk_dialog_alert_request;

typedef struct ntk_dialog_file_request {
    uint32_t           struct_size;
    const char*        title;               /* NULL: the system title */
    const char* const* filter_names;        /* filter_count entries, e.g. "Text files" */
    const char* const* filter_patterns;     /* filter_count entries, e.g. "*.txt;*.log" */
    size_t             filter_count;        /* 0: all files */
    int32_t            allow_missing_file;  /* C++ fileMustExist = !allow_missing_file (E-9) */
    void*              owner;
} ntk_dialog_file_request;

typedef struct ntk_dialog_save_file_request {
    uint32_t           struct_size;
    const char*        title;
    const char* const* filter_names;
    const char* const* filter_patterns;
    size_t             filter_count;
    const char*        default_extension;   /* NULL or "": none */
    int32_t            skip_overwrite_prompt; /* C++ overwritePrompt = !skip_overwrite_prompt */
    void*              owner;
} ntk_dialog_save_file_request;

typedef struct ntk_dialog_folder_request {
    uint32_t    struct_size;
    const char* title;
    void*       owner;
} ntk_dialog_folder_request;
```

- `filter_patterns` の各要素は `;` で区切ったパターン。C++ の `FileFilter::patterns` に分けて渡す
- 列挙の値の順は C++ API の `enum class` の宣言順と同じ（T-09 で照合）

#### 8.4.2 Notification

```c
typedef int32_t ntk_notification_error;     /* 11.2 */
typedef int32_t ntk_notification_setting;   /* ENABLED=0 .. DISABLED_BY_MANIFEST=4 */
typedef int32_t ntk_notification_scenario;  /* DEFAULT=0, REMINDER, ALARM, URGENT, INCOMING_CALL */
typedef int32_t ntk_notification_audio_kind;/* EVENT=0, MUTE, URI */
typedef int32_t ntk_notification_duration;  /* SHORT=0, LONG */
typedef int32_t ntk_notification_logo_crop; /* NONE=0, CIRCLE */

typedef struct ntk_notification_runtime ntk_notification_runtime;
typedef struct ntk_notification_manager ntk_notification_manager;
typedef struct ntk_notification_content ntk_notification_content;
typedef struct ntk_notification_list ntk_notification_list;
typedef struct ntk_notification_activation ntk_notification_activation;

typedef void (NTK_CALL *ntk_notification_invoked_fn)(
    void* user_data, const ntk_notification_activation* activation);

typedef struct ntk_notification_manager_options {
    uint32_t                    struct_size;
    ntk_notification_invoked_fn on_invoked;   /* NULL: activations are dropped */
    void*                       user_data;
    int32_t                     is_unpackaged;/* C++ isPackaged = !is_unpackaged (E-9) */
    const char*                 display_name; /* required when is_unpackaged */
    const char*                 icon_uri;     /* required when is_unpackaged */
} ntk_notification_manager_options;

typedef struct ntk_notification_progress_update {
    uint32_t    struct_size;
    const char* tag;
    const char* group;
    double      value;
    const char* value_string;
    const char* status;
    uint32_t    sequence_number;
} ntk_notification_progress_update;
```

内容のビルダーの関数（いずれも `ntk_notification_content* c` を第 1 引数に取り、`ntk_notification_error` を返す。`_create` と `_free` を除く）:

| 関数 | 引数 | C++ の項目 | `NULL` の意味 |
|---|---|---|---|
| `_create` | `ntk_notification_content** out` | 空の `NotificationContent` | - |
| `_free` | `c`（戻り値 `void`） | - | 何もしない |
| `_set_title` / `_set_body` / `_set_attribution` / `_set_hero_image` / `_set_inline_image` | `const char* value` | 同名の `std::optional<std::wstring>` | 無い（在るが空は `""`） |
| `_set_tag` / `_set_group` | `const char* value` | `tag` / `group` | `INVALID_PARAMETER` |
| `_set_scenario` / `_set_duration` | 列挙 | `scenario` / `duration` | - |
| `_set_app_logo` | `const char* uri, ntk_notification_logo_crop crop` | `appLogo` | `uri == NULL` で外す |
| `_set_audio` | `ntk_notification_audio_kind kind, const char* event_name, const char* uri, int32_t loop` | `audio` | `event_name` は `""` 可。`uri` は無い |
| `_add_button` | `const char* label, const char* invoke_uri, int32_t with_arguments, size_t* out_index` | `buttons` に追加。`with_arguments` が真なら `args` を空で在るにする | `invoke_uri == NULL` は無い |
| `_add_button_argument` | `size_t button_index, const char* key, const char* value` | `buttons[i].args` に追加（在るにする） | `INVALID_PARAMETER` |
| `_add_text_input` | `const char* id, const char* placeholder, const char* title` | `textInputs` に追加 | `placeholder` / `title` は無い |
| `_add_combo` | `const char* id, const char* title, const char* default_selection, size_t* out_index` | `comboInputs` に追加 | `title` / `default_selection` は `""` と同じ |
| `_add_combo_item` | `size_t combo_index, const char* id, const char* label` | `comboInputs[i].items` に追加 | `INVALID_PARAMETER` |
| `_set_progress` | `const char* title, double value, const char* value_string, const char* status` | `progress` | 各文字列は無い |
| `_set_timestamp` | `int64_t unix_ms` | `timestamp` | - |
| `_set_expiration` | `int64_t seconds` | `expiration` | - |
| `_set_expires_on_reboot` | `int32_t value` | `expiresOnReboot` | - |

- **ビルダーは検証しない**。6 個目のボタンや短い表示時間でのループ音は、C++ API と同じく `ntk_notification_show` / `_schedule` が `INVALID_PARAMETER` で拒む
- 範囲外の添字、範囲外の列挙の値は `INVALID_PARAMETER`

一覧と活性化の読み取り:

```c
size_t      NTK_CALL ntk_notification_list_count(const ntk_notification_list* list);
uint32_t    NTK_CALL ntk_notification_list_id_at(const ntk_notification_list* list, size_t index);
const char* NTK_CALL ntk_notification_list_tag_at(const ntk_notification_list* list, size_t index);
const char* NTK_CALL ntk_notification_list_group_at(const ntk_notification_list* list, size_t index);

/* Valid only while the ntk_notification_invoked_fn that received it runs. */
const char* NTK_CALL ntk_notification_activation_raw_arguments(const ntk_notification_activation* a);
size_t      NTK_CALL ntk_notification_activation_value_count(const ntk_notification_activation* a);
const char* NTK_CALL ntk_notification_activation_key_at(const ntk_notification_activation* a, size_t index);
const char* NTK_CALL ntk_notification_activation_value_at(const ntk_notification_activation* a, size_t index);
```

#### 8.4.3 Clipboard

```c
typedef int32_t ntk_clipboard_error;        /* 11.3 */

#define NTK_CLIPBOARD_WRITE_DEFAULT          0u
#define NTK_CLIPBOARD_WRITE_EXCLUDE_HISTORY  1u
#define NTK_CLIPBOARD_WRITE_EXCLUDE_ROAMING  2u
#define NTK_CLIPBOARD_WRITE_SENSITIVE        3u  /* both of the above */

typedef struct ntk_clipboard_session ntk_clipboard_session;
typedef struct ntk_clipboard_items ntk_clipboard_items;
typedef struct ntk_clipboard_history ntk_clipboard_history;
typedef struct ntk_clipboard_render_target ntk_clipboard_render_target;

typedef void (NTK_CALL *ntk_clipboard_changed_fn)(void* user_data);
typedef void (NTK_CALL *ntk_clipboard_history_changed_fn)(void* user_data);
typedef void (NTK_CALL *ntk_clipboard_flag_changed_fn)(void* user_data, int32_t enabled);

typedef ntk_clipboard_error (NTK_CALL *ntk_clipboard_render_fn)(
    void* user_data, const char* format_name, ntk_clipboard_render_target* target);

typedef void (NTK_CALL *ntk_clipboard_history_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error,
    const ntk_clipboard_history* history);          /* NULL on failure; valid during the call */
typedef void (NTK_CALL *ntk_clipboard_completion_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error);
typedef void (NTK_CALL *ntk_clipboard_availability_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error,
    int32_t history_enabled, int32_t roaming_enabled);

typedef struct ntk_clipboard_session_options {
    uint32_t                 struct_size;
    ntk_clipboard_changed_fn on_clipboard_changed;  /* NULL: no listener */
    void*                    user_data;
} ntk_clipboard_session_options;

typedef struct ntk_clipboard_history_handlers {
    uint32_t                        struct_size;
    ntk_clipboard_history_changed_fn on_history_changed;
    ntk_clipboard_flag_changed_fn    on_history_enabled_changed;
    ntk_clipboard_flag_changed_fn    on_roaming_enabled_changed;
    void*                            user_data;     /* passed to all three */
} ntk_clipboard_history_handlers;

ntk_clipboard_error NTK_CALL ntk_clipboard_render_target_set(
    ntk_clipboard_render_target* target, const uint8_t* data, size_t size);

size_t      NTK_CALL ntk_clipboard_history_count(const ntk_clipboard_history* h);
const char* NTK_CALL ntk_clipboard_history_item_id(const ntk_clipboard_history* h, size_t index);
const char* NTK_CALL ntk_clipboard_history_item_text(const ntk_clipboard_history* h, size_t index); /* NULL: no text */
size_t      NTK_CALL ntk_clipboard_history_item_content_type_count(const ntk_clipboard_history* h, size_t index);
const char* NTK_CALL ntk_clipboard_history_item_content_type_at(const ntk_clipboard_history* h, size_t index, size_t type_index);
int64_t     NTK_CALL ntk_clipboard_history_item_timestamp(const ntk_clipboard_history* h, size_t index);
```

- 書き込みのオプションは構造体ではなくビットの組。未知のビットは `INVALID_PARAMETER`。`SENSITIVE` は今の C ABI の定数の値（3）を残す
- 複数形式のビルダー: `ntk_clipboard_items_add_text(items, format_name, text)`、`_add_html(items, format_name, html)`、`_add_bytes(items, format_name, data, size)`。C++ の `TextPayload` / `HtmlPayload` / `BytesPayload` に 1 対 1。形式名と種別の組み合わせの検証は C++ API と同じく `ntk_clipboard_copy_multiple` が行う
- 履歴のハンドルは C++ の `HistoryItem` をそのまま読む。README の D-6 の例にある `is_pinned` は C++ API に無いので持たない

### 8.5 C++ API の整理（E-10）

| 対象 | 変更 | 影響 |
|---|---|---|
| `AlertRequest::extraFlags` | 削除 | ブリッジだけが使っていた。サンプルは使っていない |
| `NotificationContent::unknownKeys` | 削除 | JSON のパーサだけが書いていた |
| `NotificationError::InvalidPayload`（3） | 欠番。Doxygen に「返さない。1.x の C ABI の JSON の解析失敗」と書く | 値は詰めない |
| `DialogError::BufferTooSmall`（3）、`ClipboardError::BufferTooSmall`（7） | 同上 | 同上 |
| Dialog の内部入口（生の `MB_*` とフィルター文字列を受けるもの）、`src/Bridge/` の JSON の読み書き | 削除 | ブリッジと一緒に消える |

`check_cpp_api_contract.py` の照合（列挙と `#define` の 1 対 1）は、今の C ABI の `#define` が消えるため、**C ABI のヘッダーの `#define` との照合に置き換える**（T-09）。

## 9. 同期・非同期レイヤー対応表

C++ API の設計書 9 章の表を C ABI から見たもの。同期性は C++ API と同じで、C ABI では変えない。`スレッド` 列は完了が届くスレッド。

| OP | C 関数 | 同期性 | スレッド | 受付を呼べるスレッド | C ABI での変換 |
|---|---|---|---|---|---|
| OP-01 | `ntk_dialog_show_alert` | 同期・モーダル | 呼び出しスレッド | UI スレッド | 構造体 → 要求 |
| OP-02 | `ntk_dialog_show_open_file` | 同期・モーダル | 呼び出しスレッド | UI スレッド | 同上、文字列 → ハンドル |
| OP-03 | `ntk_dialog_show_open_files` | 同期・モーダル | 呼び出しスレッド | UI スレッド | 同上、一覧 → ハンドル |
| OP-04 | `ntk_dialog_show_save_file` | 同期・モーダル | 呼び出しスレッド | UI スレッド | 同 OP-02 |
| OP-05 | `ntk_dialog_show_pick_folder` | 同期・モーダル | 呼び出しスレッド | UI スレッド | 同 OP-02 |
| OP-06 | `ntk_dialog_show_pick_folders` | 同期・モーダル | 呼び出しスレッド | UI スレッド | 同 OP-03 |
| OP-07 | `ntk_notification_runtime_initialize` | 同期 | 呼び出しスレッド | 任意 | トークン → ハンドル |
| OP-08 | `ntk_notification_manager_create` | 同期 | 呼び出しスレッド | 任意 | 関数ポインタ + `user_data` → `std::function` |
| OP-09 | `ntk_notification_manager_close` | 同期 | 呼び出しスレッド | 任意 | - |
| OP-10 | `ntk_notification_show` | 同期 | 呼び出しスレッド | 任意 | ビルダー → 内容 |
| OP-11 | `ntk_notification_schedule` | 同期 | 呼び出しスレッド | 任意 | 同上 |
| OP-12 | `ntk_notification_cancel_scheduled` | 同期 | 呼び出しスレッド | 任意 | - |
| OP-13 | `ntk_notification_update_progress` | 同期（中で非同期を待つ） | 呼び出しスレッド | 任意 | 構造体 → 更新 |
| OP-14 | `ntk_notification_set_badge` | 同期 | 呼び出しスレッド | 任意 | - |
| OP-15 | `ntk_notification_remove_by_id` | 同期（中で非同期を待つ） | 呼び出しスレッド | 任意 | - |
| OP-16 | `ntk_notification_remove_by_tag` | 同期（中で非同期を待つ） | 呼び出しスレッド | 任意 | - |
| OP-17 | `ntk_notification_remove_all` | 同期（中で非同期を待つ） | 呼び出しスレッド | 任意 | - |
| OP-18 | `ntk_notification_get_all` | 同期（中で非同期を待つ） | 呼び出しスレッド | 任意 | 一覧 → ハンドル |
| OP-19 | `ntk_notification_get_setting` | 同期 | 呼び出しスレッド | 任意 | - |
| OP-20 | `ntk_notification_open_settings` | 同期（中で非同期を待つ） | 呼び出しスレッド | 任意 | - |
| OP-21 | `ntk_clipboard_session_create` | 同期 | 呼び出しスレッド（オーナーになる） | STA | 関数ポインタ + `user_data` → `std::function` |
| OP-22 | `ntk_clipboard_set_history_handlers` | 同期 | オーナー | オーナーだけ | 同上 |
| OP-23 | `ntk_clipboard_session_close` | 同期（再試行あり） | オーナー | オーナーだけ | - |
| OP-24 | `ntk_clipboard_session_can_close` | 同期 | 呼び出しスレッド | 任意 | - |
| OP-25 | `ntk_clipboard_copy_text` | 同期 | 呼び出しスレッド | 任意 | UTF-8 → `wstring`、ビット → `WriteOptions` |
| OP-26 | `ntk_clipboard_paste_text` | 同期 | 呼び出しスレッド | 任意 | `wstring` → UTF-8 のハンドル |
| OP-27 | `ntk_clipboard_copy_html` | 同期 | 呼び出しスレッド | 任意 | 同 OP-25 |
| OP-28 | `ntk_clipboard_paste_html` | 同期 | 呼び出しスレッド | 任意 | 同 OP-26 |
| OP-29 | `ntk_clipboard_copy_files` | 同期 | 呼び出しスレッド | 任意 | 配列 → `vector<wstring>` |
| OP-30 | `ntk_clipboard_paste_files` | 同期 | 呼び出しスレッド | 任意 | 一覧 → ハンドル |
| OP-31 | `ntk_clipboard_copy_dib` | 同期 | 呼び出しスレッド | 任意 | バイト列 → `span` |
| OP-32 | `ntk_clipboard_paste_dib` | 同期 | 呼び出しスレッド | 任意 | バイト列 → ハンドル |
| OP-33 | `ntk_clipboard_copy_custom` | 同期 | 呼び出しスレッド | 任意 | 同 OP-31 |
| OP-34 | `ntk_clipboard_paste_custom` | 同期 | 呼び出しスレッド | 任意 | 同 OP-32 |
| OP-35 | `ntk_clipboard_copy_multiple` | 同期 | 呼び出しスレッド | 任意 | ビルダー → `vector<FormatPayload>` |
| OP-36 | `ntk_clipboard_has_format` | 同期 | 呼び出しスレッド | 任意 | - |
| OP-37 | `ntk_clipboard_get_formats` | 同期 | 呼び出しスレッド | 任意 | 一覧 → ハンドル |
| OP-38 | `ntk_clipboard_get_preferred_format` | 同期 | 呼び出しスレッド | 任意 | 文字列 → ハンドル |
| OP-39 | `ntk_clipboard_clear` | 同期 | 呼び出しスレッド | 任意 | - |
| OP-40 | `ntk_clipboard_reserve_deferred` | 同期。provider はオーナーで後から呼ばれる | オーナー | オーナーだけ | provider → `RenderProvider`、`release` を包みの破棄に結ぶ |
| OP-41 | `ntk_clipboard_recover_deferred_state` | 同期 | オーナー | オーナーだけ | - |
| OP-42 | `ntk_clipboard_get_history` | 非同期（コールバック） | オーナー | 任意 | 完了に借りの履歴ハンドル |
| OP-43 | `ntk_clipboard_restore_history_item` | 非同期（コールバック） | オーナー | 任意 | - |
| OP-44 | `ntk_clipboard_delete_history_item` | 非同期（コールバック） | オーナー | 任意 | - |
| OP-45 | `ntk_clipboard_clear_unpinned_history` | 非同期（コールバック） | オーナー | 任意 | - |
| OP-46 | `ntk_clipboard_get_history_availability` | 非同期（コールバック） | オーナー | 任意 | 完了に 2 つの真偽値 |
| OP-47 | `ntk_clipboard_cancel_request` | 同期 | 呼び出しスレッド | 任意 | - |

### 9.1 C ABI で加わる変換

- 文字列は入口で UTF-8 → UTF-16、出口で UTF-16 → UTF-8 に変換する。変換の失敗は入口では `INVALID_PARAMETER`、出口では Clipboard が `INVALID_DATA`、ほかは `UNKNOWN`（Notification は `HRESULT_FAILURE`）
- コールバックは、関数ポインタと `user_data` を捕捉した `std::function` に包んで C++ API に渡す。包みは C++ API が持つ期間だけ生きる。これが 7.5 の期間になる
- 同期性は変えない。`std::future` やスレッドを C ABI で足さない

## 10. 既存の約束の対応表

C++ API の設計書 10 章の約束は、C++ API が守る。C ABI は包むだけなので、**C ABI が壊しうる約束**と、**C ABI で新しく生まれる約束**だけを挙げる。

| 約束 | 出典 | C ABI で守る方法 |
|---|---|---|
| 受け付けた履歴の要求の完了はちょうど 1 回、受け付けなかった要求は 0 回 | C++ 設計書 CLP-06 | 包みの `std::function` を C++ API に渡すだけで、C ABI は呼び出し回数を足さない。12.1 の CT-12 で確かめる |
| 完了は受付の呼び出しの中では来ない | CLP-02 | 同上 |
| キャンセルは論理。配送中の完了は取り消さない | CLP-16、CLP-17 | 同上 |
| `close` は成功するまで呼ぶ。5 通りのエラーを返し分ける | C++ 設計書 7.4.1 | `Session::Close` の結果をそのまま返す |
| 閉じていないセッションの破棄は放棄 | C++ 設計書 N-5 | `ntk_clipboard_session_free` はセッションを破棄する。**未クローズなら放棄になり、以後の `create` は `NOT_SUPPORTED`**。Debug ビルドの DLL では assert する |
| 通知の解除は、登録の取り消しを先に、コールバックの解除を後に | NTF-40 | `Manager::Close` を呼ぶだけ。C ABI の包みはその後に破棄する |
| 通知の活性化は OS が選んだスレッドで来る | C++ 設計書 7.5.4 | 1.3 と Doxygen に書く |
| **新**: 借りたポインタはハンドルかコールバックの期間だけ有効 | 7.4 | ハンドルの中に UTF-8 の複製を持ち、読み取りはそれを指す |
| **新**: provider の `release` はちょうど 1 回 | 7.5 | 包みのデストラクタで呼ぶ。予約が失敗した場合も包みは破棄されるので呼ばれる |
| **新**: `ntk_last_system_code()` はスレッドごと | 7.3 | `thread_local` に置く |
| **新**: 例外は境界を越えない | 7.7 | すべての入口とコールバックの包みで捕まえる |

## 11. エラー

値はすべて C++ API の `enum class` と同じ。名前は `NTK_<機能>_ERROR_<名前>`。`返す場面` は C++ API の設計書 11.4 に従う。**C ABI だけが返す場面**を最後の列に書く。

### 11.1 `ntk_dialog_error`

| 値 | 名前 | C ABI だけが返す場面 |
|---|---|---|
| 0 | `NONE` | - |
| 1 | `INVALID_PARAMETER` | 要求や出力引数が `NULL`、`struct_size` が小さすぎる、不正な UTF-8、範囲外の列挙の値 |
| 2 | `CANCELED` | - |
| 3 | `BUFFER_TOO_SMALL` | 欠番。返さない（E-10） |
| 4 | `SYSTEM_ERROR` | - |
| 5 | `UNKNOWN` | 捕まえた例外（7.7） |

### 11.2 `ntk_notification_error`

| 値 | 名前 | C ABI だけが返す場面 |
|---|---|---|
| 0 | `NONE` | - |
| 1 | `NOT_INITIALIZED` | - |
| 2 | `DISABLED` | - |
| 3 | `INVALID_PAYLOAD` | 欠番。返さない（E-10） |
| 4 | `PROGRESS_NOT_FOUND` | - |
| 5 | `HRESULT_FAILURE` | 捕まえた例外（7.7）。メモリ不足は `ntk_last_system_code()` が `E_OUTOFMEMORY` |
| 6 | `BADGE_FAILED` | - |
| 7 | `INVALID_PARAMETER` | ハンドルや出力引数が `NULL`、`struct_size` が小さすぎる、不正な UTF-8、範囲外の添字や列挙の値 |
| 8 | `NOT_SUPPORTED` | - |

### 11.3 `ntk_clipboard_error`

| 値 | 名前 | C ABI だけが返す場面 |
|---|---|---|
| 0 | `NONE` | - |
| 1 | `INVALID_PARAMETER` | ハンドルや出力引数が `NULL`、`struct_size` が小さすぎる、不正な UTF-8、未知の書き込みのビット、`data == NULL` かつ `size > 0` |
| 2 | `NOT_INITIALIZED` | - |
| 3 | `BUSY` | - |
| 4 | `EMPTY` | - |
| 5 | `FORMAT_UNAVAILABLE` | - |
| 6 | `INVALID_DATA` | 出力の UTF-16 → UTF-8 の変換に失敗した |
| 7 | `BUFFER_TOO_SMALL` | 欠番。返さない（E-10） |
| 8 | `OUT_OF_MEMORY` | 捕まえた `std::bad_alloc` |
| 9 | `ACCESS_DENIED` | - |
| 10 | `HISTORY_DISABLED` | - |
| 11 | `ITEM_DELETED` | - |
| 12 | `MONITOR_REGISTER_FAILED` | - |
| 13 | `PARTIAL_STATE` | - |
| 14 | `WRONG_THREAD` | - |
| 15 | `CANCELED` | - |
| 16 | `NOT_SUPPORTED` | - |
| 17 | `NOT_FOREGROUND` | - |
| 18 | `WRONG_APARTMENT` | - |
| 19 | `UNKNOWN` | 捕まえた例外 |

`NULL` のハンドルは、`INVALID_PARAMETER` を返す（閉じたハンドルの `NOT_INITIALIZED` と区別する）。

## 12. テスト設計

### 12.1 単体テスト（`WindowsLibraryTest/CApi/`）

C ABI の `.cpp` をテストプロジェクトに直接コンパイルし、C++ API のテストと同じ偽物（`StoringClipboard`、偽の通知 backend、STA の harness）を使う。

| ID | 確かめること | 方法 |
|---|---|---|
| CT-01 | 公開ヘッダーが C としてコンパイルできる | `.c` の翻訳単位で 4 つのヘッダーをそれぞれ単独に include し、`/TC /W4 /WX` でコンパイルする。PCH を使わない |
| CT-02 | 公開ヘッダーが C++ として単独でコンパイルでき、`<windows.h>` と一緒でも衝突しない | C++ API の U-D と同じ |
| CT-03 | 公開ヘッダーが ASCII だけ | 機械照合（T-09） |
| CT-04 | 構造体の配置が宣言どおり | `static_assert(offsetof(...))` と `sizeof` を x64 の値で固定する |
| CT-05 | すべての関数で `NULL` のハンドルと出力引数が `INVALID_PARAMETER` になり、落ちない | 表で全関数を回す |
| CT-06 | 不正な UTF-8、小さすぎる `struct_size`、未知のビット、範囲外の添字と列挙が `INVALID_PARAMETER` | 同上 |
| CT-07 | 大きい `struct_size`（将来の版の構造体）を受け付ける | 末尾に未知の項目を足した構造体を渡す |
| CT-08 | `ntk_last_system_code()` が失敗で書かれ、成功で 0 になり、スレッドごとに独立している | 2 スレッドで交互に失敗させる |
| CT-09 | `_free(NULL)` が何もしない。読み取りの範囲外は `NULL` / 0 | 全ハンドルの型で |
| CT-10 | Clipboard の読み書きが往復する（テキスト、HTML、ファイル、DIB、独自形式、複数形式、UTF-8 の多言語） | 偽のクリップボードで、C ABI で書いて C ABI で読む。C++ API で読んだ結果とも比べる |
| CT-11 | 通知の内容のビルダーが C++ の `NotificationContent` と同じペイロードを作る。「無い」と「在るが空」の区別を含む | 同じ内容を C++ と C ABI で作り、`BuildPayload` の結果を比べる。入力一覧 §1.10 の 11 項目を網羅する |
| CT-12 | コールバックに `user_data` が届く。履歴の完了が受付後ちょうど 1 回で、受付前の失敗では 0 回。完了のスレッドがオーナー | C++ API の C-1〜C-4 と同じ偽 backend |
| CT-13 | provider の `release` がちょうど 1 回。置き換え、閉じる、予約の失敗のそれぞれで | 呼び出しを数える |
| CT-14 | 例外が境界を越えない | 例外を投げる偽物を差し込み、エラーが返ることを確かめる |
| CT-15 | Dialog の要求の変換。0 で埋めた構造体が C++ の既定と一致する（E-9）。`;` 区切りのパターンが分かれる | 変換関数を直接呼ぶ。ダイアログは出さない |
| CT-16 | ハンドルのライフサイクル。閉じた後の操作が `NOT_INITIALIZED`。2 回目の `create` の返し分け | C++ API の C-5〜C-8 と同じ harness |

- 今の C ABI のテスト（`ClipboardBridgeTest`、`NotificationBridgeTest`、`NotificationPayloadTest`）は今の C ABI とともに削除する。そこに固定した振る舞いのうち C++ API の振る舞いであるもの（段階 3 の T-17 で入力一覧から導出したもの）は、C++ API のテスト（`NotificationBuilderTest` など）に既にある
- C++ API のテスト（約 260 件）はそのまま通る。E-10 で消す項目を使うテストだけを直す

### 12.2 機械照合（T-09）

| 照合 | 両辺 |
|---|---|
| 公開する関数の集合 | `.def` の EXPORTS ↔ ヘッダーの宣言 ↔ 8.2 の表。件数 105 |
| OP の対応 | 8.1 の 47 行 ↔ 9 章の 47 行 ↔ C++ API の設計書 8.1 |
| エラーの値 | C ABI の `#define NTK_*_ERROR_*` ↔ C++ API の `enum class` ↔ 11 章の表 |
| 列挙の値 | `NTK_DIALOG_ALERT_*` などの `#define` ↔ C++ API の `enum class` の宣言順 |
| 名前の規則 | ヘッダーの全関数が 1.1 の形 |
| ASCII | 公開ヘッダー |

`dumpbin /exports` の結果が `.def` と一致することを、ビルドの後に確かめる（T-14）。

### 12.3 UI テストと computer use

- サンプルは段階 4 で C++ API に移ったので、**UI テストは C ABI を通らない**。C ABI の振る舞いは 12.1 で確かめる。UI テストは、E-10 の整理で C++ API が壊れていないことを確かめるために全件流す
- P/Invoke を通した確認は `unity-native-plugin` で行う（このリポジトリの分担。サンプルは VC++ でネイティブの振る舞いを確かめ、Unity からの呼び出しは別リポジトリで確かめる）
- computer use は、この段階では新しく行わない

## 13. 実装タスク分解

合計見積: 約 15.5 日

| ID | 内容 | 見積 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T-01 | `windows/WindowsLibraryCApi/` を作る（`.vcxproj`、`.filters`、空の `.def`、Core への参照、各 `.sln` への登録）。`UnityWindowsPlugin` を削除する | 1.0日 | 無し | 空の DLL がビルドでき、`UnityWindowsPlugin` がどの `.sln` にも無い | 依存の向きが CApi → Core だけか |
| T-02 | `Common.h` と共通の実装（ハンドル、`ntk_last_system_code`、`ntk_version`、UTF-8 の変換、例外の捕捉）。CT-01〜CT-04、CT-08、CT-09 | 1.5日 | T-01 | 挙げたテストが通る | `thread_local` の置き場所。借りたポインタの期間 |
| T-03 | `Dialog.h` と OP-01〜OP-06。CT-15 | 1.0日 | T-02 | 6 関数が動く。CT-15 が通る | E-9 の反転。フィルターの分割 |
| T-04 | `Notification.h` のランタイム、マネージャー、一覧、活性化と OP-07〜OP-09、OP-12〜OP-20 | 1.5日 | T-02 | 13 操作が動く | 活性化のハンドルがコールバックの期間だけか |
| T-05 | 通知の内容のビルダーと OP-10、OP-11。CT-11 | 1.5日 | T-04 | CT-11 が 11 項目の在る・無い・空を網羅して通る | `NULL` と `""` の区別 |
| T-06 | Clipboard のセッション、履歴のハンドラ、読み書き（OP-21〜OP-34、OP-36〜OP-39）。CT-16 | 1.5日 | T-02 | 挙げた操作が動く。CT-16 が通る | オーナースレッドの制約を C ABI で足していないか |
| T-07 | 複数形式のビルダー（OP-35）と遅延レンダリング（OP-40、OP-41）。CT-13 | 1.0日 | T-06 | CT-13 が通る | `release` がちょうど 1 回か |
| T-08 | 履歴の要求（OP-42〜OP-47）と履歴のハンドル。CT-10、CT-12 | 1.5日 | T-06 | CT-10、CT-12 が通る | 完了のスレッドと回数 |
| T-09 | 機械照合（12.2）を `scripts/` に足し、壊すと落ちることを確かめる。`check_cpp_api_contract.py` の `#define` の照合を C ABI のヘッダーに付け替える | 1.0日 | T-03, T-05, T-07, T-08 | 照合が通る。壊した入力で落ちる | 検査が両辺をソースから導出しているか |
| T-10 | 今の C ABI を削除する（`WindowsLibrary.vcxproj` の DLL、`src/Bridge/`、今の C ABI のヘッダー 4 つ、今の C ABI のテスト 3 群）。E-10 の C++ API の整理 | 1.0日 | T-09 | 単体テストが通る。`src/` に `extern "C"` が無い | 消した項目の参照が残っていないか |
| T-11 | ビルドスクリプトと配布物（`build_windows_library_dll.ps1` の対象、名前 `windows-native-toolkit-capi`、版 2.0.0、ヘッダーの配置）。README 6 の `UnityWindowsPlugin` の参照（15 ファイル）を直す | 1.0日 | T-10 | スクリプトが DLL とヘッダーを出力する。`UnityWindowsPlugin` の参照が 0 件 | 配布物の名前と版 |
| T-12 | `windows.md` の修正（5.2）と、公開ヘッダーの Doxygen（スレッド、寿命、`user_data` の期間、借りたポインタ、エラー） | 1.0日 | T-10 | 5.2 の 6 か所が直っている。全公開宣言にコメントがある | 1.3 と 7.4〜7.5 がヘッダーに書かれているか |
| T-13 | 8.3 の対応表をヘッダーと突き合わせ、`unity-native-plugin` への申し送りを結果文書に書く | 0.5日 | T-11 | 52 関数すべてに行がある | 振る舞いの差が漏れていないか |
| T-14 | 回帰の確認: 単体テスト、`scripts/test_windows.ps1`（全件）、`dumpbin /exports` と `.def` の一致 | 0.5日 | T-12, T-13 | すべて通る。export が 105 | baseline との差が意図どおりか |

### 13.1 先行と後続

- 先行: T-01、T-02
- 機能ごとに独立: Dialog（T-03）、Notification（T-04、T-05）、Clipboard（T-06〜T-08）
- 後続: T-09〜T-14
- 今の C ABI の削除（T-10）は、新しい C ABI が揃い、照合が通ってから行う

## 14. リスクと緩和策

| ID | リスク | 影響 | 緩和策 |
|---|---|---|---|
| RK-01 | `unity-native-plugin` が 2.0.0 で壊れる | Unity の利用者が更新できない | 2.0.0 で一度に切り替える（D-4）。今の DLL は `dist/1.11.0/` に残る。8.3 の対応表を出す |
| RK-02 | バインディングが構造体の配置や真偽値の大きさを読み違える | 実行時の不正なメモリアクセス | 真偽値を `int32_t` にする（E-8）。CT-04 で配置を固定する。構造体は入力だけに使う |
| RK-03 | 利用者が `user_data` を早く解放する | 解放後のアクセス | 期間を 7.5 と Doxygen に書く。provider には `release` を付ける |
| RK-04 | 借りたポインタを期間の後に使う | 解放後のアクセス | 読み取り関数の Doxygen に期間を書く。コールバックに渡すハンドルは `const` にする |
| RK-05 | `ntk_last_system_code()` を、間に別の呼び出しを挟んでから読む | 違う失敗の値を読む | 7.3 に「失敗の直後に読む」と書く |
| RK-06 | 公開関数が 105 に増え、手で書くバインディングの負担が増える | 利用者の手間 | 名前の規則（1.1）をそろえ、自動生成に向いた形にする。対応表を出す |
| RK-07 | UI テストが C ABI を通らない | C ABI の退行に気づかない | CT-01〜CT-16 で全関数を通す。P/Invoke は `unity-native-plugin` で確かめる |
| RK-08 | 閉じていないセッションを `_free` する利用者が出る | クリップボードの機能がそのプロセスで使えなくなる | Doxygen と 1.3 に書く。Debug の DLL では assert する |
| RK-09 | コンソールのプログラムから履歴や遅延レンダリングを使おうとする | 完了が来ない | 1.3 の表で「成立しない使い方」として示す |
| RK-10 | E-10 の整理で、C++ API の利用者（サンプル）が壊れる | 段階 4 の成果の退行 | サンプルは `extraFlags` と `unknownKeys` を使っていない（段階 4 で確認）。UI テストを全件流す |

## 15. Definition of Done

### 15.1 機能

- [ ] `windows/WindowsLibraryCApi/` があり、`WindowsLibraryCore` だけに依存する
- [ ] 8.2 の 105 関数が `.def`、ヘッダー、実装にあり、`dumpbin /exports` と一致する
- [ ] 8.1 の 47 操作すべてに C 関数があり、9 章の表と操作の集合が一致する
- [ ] 公開ヘッダーが C と C++ の両方でコンパイルでき、`<windows.h>` を include せず、ASCII だけである
- [ ] エラーと列挙の値が C++ API と一致する
- [ ] 今の C ABI（DLL、`src/Bridge/`、ヘッダー 4 つ）と `UnityWindowsPlugin` が無い
- [ ] E-10 の整理が済んでいる

### 15.2 品質

- [ ] CT-01〜CT-16 が通る
- [ ] C++ API の単体テストと `scripts/test_windows.ps1`（全件）が通る
- [ ] 機械照合（12.2）が通り、壊すと落ちることを確かめてある
- [ ] 公開ヘッダーの全宣言に Doxygen があり、スレッド、寿命、`user_data` の期間、借りたポインタの期間、エラーが書かれている

### 15.3 構成と文書

- [ ] ビルドスクリプトが `windows-native-toolkit-capi` の 2.0.0 を出力する
- [ ] `windows.md` の 5.2 の 6 か所が直っている
- [ ] `UnityWindowsPlugin` の参照が 0 件
- [ ] 8.3 の対応表が 52 関数すべてを含み、結果文書に `unity-native-plugin` への申し送りがある
