# Windows ライブラリ C ABI 実装設計書（段階 5）

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/windows-architecture/README.md` |
| 対象段階 | 段階 5（段階 3 で分けた DLL を `WindowsLibraryCApi` に改名し、中身を新しい C ABI に置き換える。`UnityWindowsPlugin` を削除する） |
| 対象 OS | Windows 11 以降 |
| 作成日 | 2026-09-21（v2 のレビューを反映した第 3 版。実装中に E-11 と 12.1 のテストの置き場所を直した） |
| ブランチ | `feature/NTKIT-16` |
| 前段階 | 段階 3（C++ API）と段階 4（サンプルの移行）は完了。CU-01 の再実行だけが残っている |
| 反映した決定 | D-4、D-5、D-6（E-5 で見直し）、D-7、D-8（E-17 で例外を明記）、D-9、D-10、E-1〜E-21（4.2） |
| 元にした設計書 | `designs/2026-09-20-windows-architecture-cpp-api-design.md`（C ABI はこの C++ API の上に載る。OP の番号、約束、エラーはそこから引き継ぐ） |
| レビュー | `reviews/2026-09-21-windows-architecture-c-abi-design-review-v1.md`（3 者、R-1〜R-30）、`-v2.md`（3 者、S-1〜S-12） |

- **`PLANNED_SYMBOLS_EXEMPT`**: この設計書は、まだ書かれていない C ABI の名前（`ntk_*`）を定める。実装の前なので、名前が実装に存在するかの照合は T-11 の機械照合が受け持つ

## 0. レビューの反映

3 者（Claude の整合担当、Claude の相互運用担当、Codex）に 2 回レビューしてもらった。

### 0.1 第 2 版での反映（v1 のレビュー）

30 件の指摘の反映先は次のとおり。R-1、R-5、R-25 は利用者が 2026-09-21 に決めた。

| # | 指摘 | 反映 |
|---|---|---|
| R-1 | 通知の `user_data` が close の後も使われうる | 解放のコールバックにする（E-12、7.5） |
| R-2 | 放棄したセッションがコールバックを呼び続ける | 生存フラグで止める（7.5、E-1 の理由を直す） |
| R-3 | 旧ヘッダーを消すと Core がビルドできない | 定数を内部ヘッダーへ移すタスクに分ける（8.5、T-12） |
| R-4 | Dialog の内部入口を消すと C++ API が消える | その行を消す（8.5） |
| R-5 | C++ の Dialog が `owner` などを実装に渡していない | 段階 5 で直す（E-13、T-03） |
| R-6 | provider の `release` の回数と時期が実装と違う | 解放ガードの共有と、実装どおりの時期（7.5） |
| R-7 | `struct_size` の版の見分けに穴がある | 詰め物の明示と読み方の規則（7.8、E-9） |
| R-8 | Runtime を Manager より先に解放できる | C ABI で参照を数える（7.4、10） |
| R-9 | シグネチャが確定していない | 付録 A に全宣言。照合でシグネチャまで見る（12.2） |
| R-10 | Unity Editor のドメインリロード | 1.3.4 |
| R-11 | ハンドルごとのスレッドの約束が無い | 1.3.2 |
| R-12 | スレッドごとのシステムコードの破綻 | 完了には引数で渡す（E-18、7.3） |
| R-13 | COM とメッセージループの前提が無い | 1.3.3 |
| R-14 | コールバックの中の禁止事項が足りない | 1.3.5 |
| R-15 | 未クローズの `_free` の意味がハンドルごとに違う | 7.4 の表 |
| R-16 | 省略できない文字列の `NULL` | `""` とする（E-15、7.6） |
| R-17 | ダイアログのフィルターが並列配列 | 関数の引数の組の配列（8.1、付録 A） |
| R-18 | 借りた文字列の長さと C# の罠 | 長さの出力引数と注記（7.4） |
| R-19 | 履歴の要求まわりの未定義 | 7.5 |
| R-20 | 描画先（target）の約束が未定義 | 7.5 |
| R-21 | 8.3 の漏れと誤り | 8.3 |
| R-22 | UTF-16 → UTF-8 の変換の方針 | U+FFFD に置き換える（E-16、7.6） |
| R-23 | D-8 と `size_t` | 例外を明記（E-17） |
| R-24 | 実際の DLL を通るテストが無い | 小さな C の実行ファイル（CT-21、T-10） |
| R-25 | 履歴の timestamp の単位 | Unix ミリ秒に変換（E-14） |
| R-26 | 列挙の値の `#define` | 無名の `enum`（E-8） |
| R-27 | 出力とシステムコードの文言の矛盾 | 7.3 |
| R-28 | ビルダーの細部、定数 | 付録 A、8.4 |
| R-29 | 件数とタスクの誤り | 13 章、8.5 |
| R-30 | 照合の弱化、C++ の Doxygen、DoD の範囲、空のバイト列 | T-11、T-14、15 章、CT-09 |

### 0.2 第 3 版での反映（v2 のレビュー）

S-4 は利用者が 2026-09-21 に決めた。

| # | 指摘 | 反映 |
|---|---|---|
| S-1 | 通知の `release` の競合と、失敗したときの扱い | 解放ガードにし、`release` を取る関数は戻り値にかかわらずちょうど 1 回呼ぶ（E-12、7.5.1） |
| S-2 | 生存フラグのミューテックスでの自己デッドロック | コールバックの間はロックを持たない（7.5.2） |
| S-3 | provider の `release` の時期と、close の後に残ること | close の成功か `_free` で必ず呼び、それ以後は呼ばない（7.5.3） |
| S-4 | ドメインリロードの中で close を成功させる手段が無い | close が自分の隠しウィンドウ宛てのメッセージを処理する（E-19、T-17） |
| S-5 | 履歴のハンドラの差し替えの順序と、解除の失敗 | C++ を直す（E-20、T-17）。期間は成功した後（7.5.1） |
| S-6 | 付録 A のヘッダーの include ガードと `extern "C"` | 7.2、付録 A |
| S-7 | 構造体の版のテスト、上限、`#pragma pack`、凍結した組 | 7.2、7.8、CT-04、CT-07 |
| S-8 | テストとタスクの割り当て、差し込み口、照合の付け替え | 8.5、12 章、13 章 |
| S-9 | 8.3 の誤り | 8.3 |
| S-10 | 細部（外せる項目、timestamp の 0、Runtime の 2 回目、cold start、登録し直し、`release` の中の禁止、自分の書き込み、Unity の通知の後始末） | 1.3、7.3〜7.5、8.4 |
| S-11 | cffi のマクロ、bindgen の対象、Go、`LPUTF8Str` | 7.2、付録 A、申し送り（T-15） |
| S-12 | 8.5 の `WindowsDialogManager` の書き方 | 8.5 |

## 1. 利用者が最初に知ること

README 5.1 が冒頭に置くよう求める 3 点（名前、受け渡しの方式、スレッド）と、レビューで足りないと分かった寿命とコールバックの前提。

### 1.1 名前の規則

| 対象 | 規則 | 例 |
|---|---|---|
| 関数 | `ntk_<機能>_<動詞>[_<目的語>]`。機能は `dialog` / `notification` / `clipboard`。機能に属さないものは `ntk_<名詞>_<動詞>` | `ntk_clipboard_copy_text`、`ntk_dialog_show_open_file`、`ntk_string_free` |
| ハンドルの操作 | `ntk_<機能>_<ハンドル名>_<動詞>`。作るのは `_create`、閉じるのは `_close`、解放は `_free` | `ntk_clipboard_session_create`、`ntk_notification_content_free` |
| ハンドルの読み取り | `ntk_<型名>_<項目>`。一覧の要素は `_at` または `_<項目>_at` | `ntk_string_list_at`、`ntk_clipboard_history_item_text` |
| 型 | `ntk_<機能>_<名詞>`。ハンドルは不完全型の `typedef struct ntk_x ntk_x;` | `ntk_clipboard_session`、`ntk_dialog_file_request` |
| 列挙の型 | `typedef int32_t ntk_<機能>_<名詞>;`（D-8） | `ntk_clipboard_error`、`ntk_dialog_alert_result` |
| 列挙の値 | `NTK_<機能>_<名詞>_<値>`。無名の `enum` で定義する（E-8） | `NTK_CLIPBOARD_ERROR_BUSY`、`NTK_DIALOG_ALERT_RESULT_OK` |
| コールバックの型 | `ntk_<機能>_<事象>_fn`。共通のものは `ntk_<事象>_fn` | `ntk_clipboard_history_fn`、`ntk_release_fn` |
| ヘッダー | `NativeToolkitC/<機能>.h`。共通の型は `NativeToolkitC/Common.h`（README 3） | `#include <NativeToolkitC/Clipboard.h>` |

- 名前はすべて ASCII の小文字とアンダースコア。今の C ABI の名前（`copyPlainText` など）は 1 つも残さない（D-4。8.3 に対応表）

### 1.2 受け渡しの 3 方式

受け渡しは次の 3 つの方式だけで行う。**どの方式かは向きとデータの形で決まり、利用者が選ぶことはない。**

| 方式 | 使う場面 | 利用者がすること | 手本 |
|---|---|---|---|
| **出力のハンドル** | ライブラリが返すものすべて。文字列 1 つでも一覧でも | 受け取ったハンドルを読み、対応する `_free` を呼ぶ | SQLite、libgit2 |
| **`struct_size` 付きの構造体** | 項目が固定の入力オプション（ダイアログの要求、セッションとマネージャーの設定、進捗の更新、履歴のハンドラ） | 構造体を 0 で埋め、`struct_size = sizeof(...)` を入れ、必要な項目だけ書く | Win32 |
| **ビルダーのハンドル** | 入れ子や可変長を含む入力（通知の内容、複数形式のクリップボード書き込み） | `_create` で作り、`_set_*` / `_add_*` で積み、操作に渡し、`_free` する | 各種 C ライブラリのビルダー |

- **呼び出し側のバッファとサイズの問い合わせは使わない（E-5）。** このライブラリの単純な出力は、ユーザーの操作の結果（ダイアログのパス。出し直せない）か、他のプロセスと共有する状態（クリップボード。2 回の呼び出しの間に変わる）のどちらかしかない
- 入力の配列（`copy_files` のパス、遅延レンダリングの形式名、ダイアログのフィルター）は関数の引数で、呼び出しの間だけ有効なポインタと件数で受け取る。ダイアログのフィルターは、項目を足さないと決めた組の構造体 `ntk_dialog_filter` の配列（R-17）
- 構造体を出力に使わない。項目を足すと ABI が壊れるため（D-6 の理由）

```c
/* 1. struct_size 付きの構造体 (入力) */
ntk_dialog_file_request req = {0};
req.struct_size = sizeof(req);
req.title = "Open";
ntk_dialog_filter filters[] = { { "Text files", "*.txt;*.log" } };

/* 2. 出力のハンドル */
ntk_string* path = NULL;
if (ntk_dialog_show_open_file(&req, filters, 1, &path) == NTK_DIALOG_ERROR_NONE) {
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

### 1.3 スレッドとメッセージの前提

**汎用の C ABI だが、スレッドとメッセージの前提は Windows の UI のものである。** コンソールのスクリプトから Clipboard の履歴や遅延レンダリングを使う形は成立しない。

#### 1.3.1 機能ごとの前提

| 機能 | 呼べるスレッド | 必要なもの | 成立しない使い方 |
|---|---|---|---|
| Dialog | 呼び出しスレッドを塞ぐ（モーダル）。UI スレッドから呼ぶ前提 | フォルダのダイアログはライブラリが STA で COM を初期化する | - |
| Notification | 任意のスレッド。非同期の OS 操作はライブラリの中で待つので、呼び出しを塞ぐ | unpackaged のときだけ、`ntk_notification_manager_create` より前に `ntk_notification_runtime_initialize` を呼ぶ | 活性化のコールバックが UI スレッドで来ると思い込むこと。**OS が選んだスレッドで来る**（cold start の 1 回だけは `_create` の中で呼び出しスレッド） |
| Clipboard（読み書き） | 任意のスレッド | セッションが開いていること。**自分の遅延予約が残っている間、オーナー以外のスレッドの読み書きは、オーナーがメッセージを処理するまで待つ**（書き込みの `WM_DESTROYCLIPBOARD`、読み取りの `WM_RENDERFORMAT` がオーナーへ送られるため） | オーナーが、読み書きしているスレッドの終わりを待つこと（互いに待って止まる） |
| Clipboard（セッション、遅延レンダリング、履歴のハンドラ） | **オーナースレッドだけ**。`ntk_clipboard_session_create` を呼んだスレッドがオーナーになる | オーナーは **STA で、メッセージループを回し続ける**（1.3.3）。閉じるのもオーナー | メッセージループを持たないスレッドをオーナーにすること。コールバックも完了も届かない |
| Clipboard（履歴の要求） | 受付は任意のスレッド。**完了はオーナースレッドで**、受け付けた要求 1 件につきちょうど 1 回 | 自プロセスが前面にあること（無ければ完了が `NOT_FOREGROUND` で来る） | コンソールや非表示のプロセスから履歴を読むこと |

#### 1.3.2 ハンドルごとの約束（R-11）

| ハンドル | 作る | 操作 | close | `_free` | 同時の呼び出し |
|---|---|---|---|---|---|
| `ntk_notification_runtime` | 任意 | - | - | 任意（7.4） | - |
| `ntk_notification_manager` | 任意 | 任意 | 任意 | 任意 | 操作どうしは同時に呼んでよい。**close と `_free` は、同じハンドルのほかの呼び出しと同時に呼ばない** |
| `ntk_clipboard_session` | STA（オーナーになる） | 読み書きと履歴の受付は任意、それ以外はオーナー | オーナー | 任意（未クローズなら放棄。7.4） | 同上 |
| `ntk_notification_content`、`ntk_clipboard_items`（ビルダー） | 任意 | 任意 | - | 任意 | **スレッドセーフでない**。1 つのスレッドで作って渡す |
| `ntk_string`、`ntk_bytes`、`ntk_string_list`、`ntk_notification_list` | ライブラリ | 読み取りは任意 | - | 任意 | 不変。どのスレッドから読んでも解放してもよい |

Rust のバインディングでは、manager と session は `Send + Sync`（close と drop は `&mut self`）、ビルダーは `Send` のみ、出力のハンドルは `Send + Sync` にできる。

#### 1.3.3 COM とメッセージループ（R-13）

- **`ntk_notification_manager_create` は、呼び出しスレッドを MTA で COM に初期化し、解除しない**（C++ API の N-8 の現状）。同じスレッドで後から `ntk_clipboard_session_create` を呼ぶと `WRONG_APARTMENT` になる。Clipboard のオーナーにするスレッドでは、先に STA で初期化するか、通知を別のスレッドで作る
- Clipboard のオーナーは、次の 2 つを自分で行う（`<windows.h>` を使えない言語は OS の関数を直接呼ぶ）
  1. `CoInitializeEx(NULL, COINIT_APARTMENTTHREADED)`
  2. `GetMessageW` / `TranslateMessage` / `DispatchMessageW` のループ
- `ntk_clipboard_session_close` は、**自分の隠しウィンドウ宛てのメッセージ（取り消した要求の完了の配送）を自分で処理してから判定する**（E-19）。取り消した要求の完了（`CANCELED`）は close の中で届く。利用者がループを回す必要は無い
- close が `BUSY` を返すのは、ほかのスレッドの読み書きが終わっていないとき。そのスレッドの終わりを待ってから再試行する
- 言語ごとの注記:
  - Go: オーナーの goroutine で `runtime.LockOSThread()` を呼ぶ
  - Python: ctypes で `GetMessageW` のループを回すスレッドをオーナーにする
  - C#（WinForms / WPF）: UI スレッドをオーナーにすれば、フレームワークのループがそのまま使える
  - Unity: メインスレッドが STA かどうかを `CoGetApartmentType` で確かめてからオーナーにする。メッセージはフレームごとに処理されるので、完了はフレームの境目で届く

#### 1.3.4 Unity（R-10）

Unity Editor はネイティブの DLL を下ろさない。ドメインリロードやプレイモードの出入りの後も、DLL の中のセッションとマネージャーは残る。一方で C# の static に置いたハンドルは消え、登録した関数ポインタは下ろされたドメインを指す。

- `AssemblyReloadEvents.beforeAssemblyReload`、`EditorApplication.playModeStateChanged`（`ExitingPlayMode`）、`Application.quitting` で、次を行う
  - Clipboard: **オーナーのスレッドから** close を呼び（E-19 により、処理中の要求があってもループを回さずに閉じられる。`BUSY` ならほかのスレッドの読み書きを終わらせて再試行する）、`_free` する。provider の `release` は close の中で呼ばれる（7.5.3）
  - Notification: close と `_free` の後、**すべての登録の `release` が呼ばれるのを期限付きで待つ**（`release` の中でイベントを立てる）。活性化のコールバックは受け取ったものをキューに積むだけにし、メインスレッドへ同期で戻らない（戻ると、この待ちと互いに待って止まる）
- **close が成功しなければ、`_free` をしても、その Editor では以後セッションを作れない**（放棄。7.4）。`_free` で止まるのはコールバックだけである。`_free` もしないままリロードすると、コールバックも止まらず、古いドメインを呼んで落ちる
- この内容は `unity-native-plugin` への申し送り（T-15）に入れる

#### 1.3.5 コールバックの中で呼ばないもの（R-14）

| コールバック | 呼ばないもの |
|---|---|
| セッションのコールバック（変化、履歴の 3 つ、履歴の完了） | そのセッションの close、`_free`、`ntk_clipboard_set_history_handlers` |
| 遅延レンダリングの provider | `ntk_clipboard_render_target_set` 以外のクリップボードの関数すべて。ブロックする処理 |
| 通知の活性化 | そのマネージャーの close、`_free`、`set_invoked_handler`。cold start の活性化は `ntk_notification_manager_create` の中、`*out_manager` が書かれる前に来るので、マネージャーのハンドルを前提にしない。`user_data` は `_create` の前に完成させておく |
| `release`（通知、provider） | ブロックする処理、クリップボードの関数、利用者のロックを取ること。**`release` は、自分の書き込み、close、`_free` の中から同期で呼ばれることがある** |
| すべて | 例外を投げること（7.7） |

コールバックの中でモーダルなループ（ダイアログなど）を回したり、自分で書き込んだりすると、同じセッションのコールバックが同じスレッドで入れ子で来ることがある。ライブラリはこれを許す（7.5.2）。

## 2. 設計目的

- 段階 3 で DLL ブリッジとして残した今の C ABI（52 関数）を捨て、D-6〜D-10 に沿った新しい C ABI を `WindowsLibraryCApi` として作る
- 新しい C ABI は **C++ API（OP-01〜OP-47）の薄い包み**にする。振る舞いは C++ API が決め、C ABI は型の変換、寿命の管理、例外の捕捉だけを受け持つ（E-2）
- `unity-native-plugin` が P/Invoke を書き直せる粒度で、今の 52 関数との対応表を出す（README 5.1）
- 利用者（C#、Rust、Python、Go など）が、ヘッダーからバインディングを自動生成できる形にする

## 3. スコープ

### 3.1 In scope

- `windows/WindowsLibraryCApi/`（新規）: プロジェクト、公開ヘッダー `include/NativeToolkitC/`、実装 `src/`、`.def`
- 全関数のシグネチャ（付録 A）、型、エラー、メモリの決まり、スレッドの前提
- 今の DLL（`windows/WindowsLibrary/WindowsLibrary.vcxproj`）と `src/Bridge/` の削除、`UnityWindowsPlugin` の削除
- 今の C ABI のためだけに C++ API に残した項目の整理（E-10）
- **C++ の Dialog が約束しながら実装に渡していない 4 項目の修正（E-13）**
- **C++ の Clipboard の 3 つの修正**: close が自分宛てのメッセージを処理する（E-19）、ハンドラの差し替えの順序（E-20）、隠しウィンドウのクラスをモジュールごとに登録する（E-21）。E-19 に合わせたサンプルと UI テストの修正
- C ABI の単体テスト、実際の DLL を通す確認、機械照合
- ビルドスクリプトと配布物の名前（`windows-native-toolkit-capi`、2.0.0）
- `agent-rules/coding-rules/windows.md` の修正（C++ API の設計書 5.2。README 5.1 が同じ PR を求めている）

### 3.2 Out of scope

- E-10、E-13、E-19、E-20 を除く C++ API の振る舞いの変更。E-10 は読み手のいない項目の削除、E-13 と E-20 は約束に実装を合わせる修正、E-19 は close の再試行の条件を緩める変更で、C++ の利用者が今している再試行のループはそのまま動く
- `unity-native-plugin` の P/Invoke の書き換え（別リポジトリ。README 5.1）。こちらは対応表（8.3）と申し送りを出すまで
- `windows/WindowsLibrary/` を `windows/WindowsLibraryCore/` に改名すること。改名しない（E-11）
- NuGet、マニュアル、Doxygen の生成（段階 6）、CI（段階 7）
- UTF-16 版の関数（E-7）
- COM の初期化と解除の不均衡（C++ API の設計書の N-8、RK-09）。1.3.3 に前提として書くだけ
- C++ の Dialog の固定長バッファ（1024 文字、複数選択は 32768 文字）を伸ばすこと。8.3 に上限として書く
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
| E-1 | 寿命は**不透明ハンドル**で表す。C++ の `Session` / `Manager` / `Runtime` と 1 対 1 | 2026-09-21 利用者 | C++ API と対応がつく。状態がプロセス全体に隠れない。**ただしセッションは、Dispose をオーナーのスレッドで呼び、close が成功するまで再試行する必要がある。ファイナライザ（別のスレッド）での後始末は最後の手段で、放棄になる**（R-2） |
| E-2 | C ABI が包むのは **C++ API の 47 操作だけ**。段階 3 のブリッジが使った内部層への抜け道は持たない | 2026-09-21 利用者 | 2 つの API の振る舞いが常に一致する |
| E-3 | 通知の内容は**ビルダーのハンドル**で渡す | 2026-09-21 利用者 | 項目を足しても ABI が壊れない。入れ子の配列を C の構造体で表さずに済む |
| E-4 | 同期の関数のエラーの詳細は、**スレッドごとの最後の値**を `ntk_last_system_code()` で読む | 2026-09-21 利用者 | 関数の引数が増えない。libgit2 の `git_error_last` と同じ形。非同期の完了は E-18 |
| E-5 | **出力はすべてハンドル**にする。D-6 の「単純な文字列・バイト列はバッファ + サイズの問い合わせ」を見直す | 2026-09-21 利用者 | 1.2 の理由 |
| E-6 | `Common` の 5 関数（`DLog`、`DFLog`、`DFLLog`、`ToWString`、`ConcatWStrings`）の公開をやめる | 推奨。v1 のレビューで異論なし | 内部の補助関数が漏れていたもの。`ToWString` は `extern "C"` の境界で `std::wstring` を値で返し、`ConcatWStrings` は呼び出し側に `delete[]` を求める |
| E-7 | 文字列は UTF-8 だけ。UTF-16 版は足さない | 推奨。異論なし | C# は `UnmanagedType.LPUTF8Str` で扱え、主要な言語は UTF-8 の C 文字列を直接扱える |
| E-8 | 真偽値は `int32_t`（0 が偽、0 以外が真）。列挙の型は `typedef int32_t`、**値は無名の `enum`** で定義する | 推奨。R-26 で値の定義を直した | C の `bool` と C# の既定のマーシャリング（4 バイトの `BOOL`）の食い違いを避ける。無名の `enum` にすると bindgen が値を整数の定数として出し、型として `enum` の大きさには依存しない |
| E-9 | **0 で埋めた構造体が既定値**になるようにする。C++ で既定が真の項目は、C では名前を反転する（`fileMustExist` → `allow_missing_file`）。構造体の詰め物は明示の `reserved` 項目にする | 推奨。R-7 で詰め物を足した | 項目を書き忘れても C++ の既定と同じ振る舞いになる。詰め物を明示すると、版の見分けが確実になる（7.8） |
| E-10 | 今の C ABI のためだけに C++ API に置いた項目を消す: `AlertRequest::extraFlags`、`NotificationContent::unknownKeys`。列挙の値 `InvalidPayload`（3）、`DialogError::BufferTooSmall`（3）、`ClipboardError::BufferTooSmall`（7）は**番号を欠番として残し、返さない** | 推奨。R-4 で範囲を直した | 抜け道を持たない（E-2）ので読み手がいない。C++ API はまだ配布していない（段階 6） |
| E-11 | フォルダ `windows/WindowsLibrary/` は **`WindowsLibraryCore/` に改名しない**（v3 までは段階 6 に回すとしていた） | 2026-09-21 利用者 | フォルダは `WindowsLibrary.sln` とビルドの出力先も兼ねており、改名すると sln、サンプル、テスト、`.props` の import、スクリプト、規約、各機能の文書の参照を付け替えることになる。得られるのは名前の一致だけで、プロジェクト、`.lib`、`.props` の名前が `WindowsLibraryCore` なので中身の区別は付く |
| E-12 | **通知の活性化のハンドラに解放のコールバックを付ける**。包みは `shared_ptr` の解放ガードを共有し、最後の参照が消えたとき（配送中の呼び出しがすべて戻った後）に `release(user_data)` をちょうど 1 回呼ぶ。close と差し替えは待たない | 2026-09-21 利用者（R-1）。S-1 で数え方を解放ガードに直した | C++ の配送はロックの外でハンドラを呼ぶので、close や差し替えの後も古いハンドラが走りうる。close の中で待つと、コールバックが UI スレッドへ同期的に戻る作りで行き詰まる |
| E-13 | **C++ の Dialog の実装を直す**。`owner`、ファイルのダイアログの `title`、`fileMustExist`、`overwritePrompt` を Win32 に渡す | 2026-09-21 利用者（R-5） | `Dialog.h` が既に約束している機能で、実装が追いついていない。C の項目を置いても効かないのでは意味が無い |
| E-14 | **履歴の timestamp は Unix ミリ秒に変換して返す**（`ntk_clipboard_history_item_timestamp_unix_ms`）。C++ API は WinRT の tick のまま | 2026-09-21 利用者（R-25） | 通知の時刻（Unix ミリ秒）と単位がそろい、各言語でそのまま日時にできる |
| E-15 | C++ で素の `std::wstring` の項目（`tag`、`group`、`value_string`、`status`、`plain_text` など）は、**`NULL` を `""` とする**。`INVALID_PARAMETER` にするのは意味の上で必須な値（コピーする本文、形式名、項目の ID、ボタンのラベル）だけ | 推奨（R-16） | 0 で埋めた構造体（E-9）がそのまま使える。今の C ABI も `NULL` を `""` として扱っている |
| E-16 | 出力の UTF-16 → UTF-8 の変換で、対になっていないサロゲートは **U+FFFD に置き換えて成功を返す** | 推奨（R-22） | ほかのアプリが置いた不正な文字列で、貼り付け、履歴、パスがまるごと失敗するのを避ける。置き換えは損失を伴うので 7.6 と 8.3 に書く |
| E-17 | 件数、大きさ、添字は **`size_t`** を使う。D-8 の「固定幅の型だけ」の例外とし、対象が x64 だけであることを契約にする | 推奨（R-23） | C の配列の長さの慣習どおりで、各言語のバインディングが `usize` / `UIntPtr` / `c_size_t` に写せる |
| E-18 | **非同期の完了は、システムコードをコールバックの引数で渡す**。スレッドごとの値には書かない | 推奨（R-12） | 完了はオーナーのスレッドの値を任意の時点で上書きしてしまう。Go では goroutine が OS スレッドを移るので、スレッドごとの値を後から読めない |
| E-19 | **C++ の `Session::Close` が、自分の隠しウィンドウ宛てのメッセージ（取り消した要求の完了の配送）を内部で処理してから判定する**。`CANCELED` を返すのは、処理しても配送が終わらないときだけになる | 2026-09-21 利用者（S-4） | 利用者が close の再試行の間にループを回す必要が無くなる。Unity のドメインリロードの中のように、ループを安全に回せない場面でも閉じられる。C++ と C の両方に効く。取り消した要求の完了は close の中で届く（受付の呼び出しの中では来ない、という CLP-02 は変わらない）。**サンプルの「Request + Immediate Uninitialize」は失敗しなくなる**。サンプルから close を確実に失敗させる手段は残らないので、それを使って「Shutting down」の状態を作る UI テスト 5 件は削除し、close の失敗は単体テスト（C-5〜C-8、CT-22）に任せる（2026-09-21 利用者が決定。T-17） |
| E-20 | **C++ の `Session::SetHistoryHandlers` が、オーナーのスレッドかどうかを確かめてからハンドラを差し替える** | 推奨（S-5） | 今は先に差し替えるので、`WRONG_THREAD` が返っても新しいハンドラが入っている。C++ の不具合で、約束（オーナーのスレッドだけ）を変えない |
| E-21 | **Clipboard の隠しウィンドウのクラスを、exe ではなく Core が入ったモジュール（`__ImageBase`）で登録する** | T-07 の実装中に発見 | 静的な Core が 1 つのプロセスに 2 つ入ると（exe と C ABI の DLL、2 つのプラグイン、2 つのテストの DLL）、2 つ目のクラスの登録が `ERROR_CLASS_ALREADY_EXISTS` で失敗し、セッションを作れなかった。`CS_GLOBALCLASS` の無いクラスは名前とモジュールの組で区別されるので、Core の写しごとに自分のクラスとウィンドウプロシージャを持つ。Core が exe に入る場合（サンプル）は今と同じ値になり、振る舞いは変わらない |

### 4.3 不足前提

| ID | 不足している前提 | この設計書での扱い |
|---|---|---|
| G-1 | `unity-native-plugin` がどの関数をどう使っているかは、このリポジトリから見えない | 8.3 の対応表を全 52 関数について出す。使われていない関数も落とさない |
| G-2 | C の利用者は C++ の例外を受け取れない | すべての入口とコールバックの包みで例外を捕まえる（7.7） |
| G-3 | コールバックの `user_data` をいつまで生かせばよいかが、C++ の `std::function` の捕捉のようには自明でない | コールバックごとに期間を決め（7.5）、期間の終わりが呼び出し側から分からないものには解放のコールバックを付ける |
| G-4 | C++ の Clipboard と Notification の `Failure::systemCode` には、OS の値ではなくエラーの値そのものか 0 が入っている | 7.3 に機能ごとに何が入るかを書く |

## 5. 実装方針の適用

### 5.1 common.md

| 方針 | 適用 |
|---|---|
| Bridge 層は薄く保つ | 適用する。C ABI は型の変換、ハンドルの管理、例外の捕捉だけを行い、判断は C++ API に任せる |
| エラーを型付きのまま伝播する | 適用する。機能ごとのエラーの型を分け、値は C++ API の `enum class` と同じにする（11 章） |
| 検査は両辺をソースから導出する | 適用する。`.def`、ヘッダー、C++ の列挙、この設計書の付録 A を突き合わせる（T-11） |
| コメントは英語、公開ヘッダーは ASCII だけ | 適用する |

### 5.2 windows.md の修正（この段階の PR で行う）

C++ API の設計書 5.2 で段階 5 に送った 6 か所を直す（T-14）。

| 節 | 今の記述 | 直した後 |
|---|---|---|
| アーキテクチャ / Bridge の配置 | C Bridge は `WindowsLibrary` に実装し `WindowsLibrary.dll` からエクスポートする。中継用の別 DLL を足さない | C ABI は `WindowsLibraryCApi`（DLL）に置き、機能の実装は `WindowsLibraryCore`（静的）に置く |
| アーキテクチャ / 基本構造 | `XxxManager (singleton)` が公開 API | 公開面は所有するオブジェクト（C++ は `Session` など、C はハンドル）。内部の singleton は残る |
| 原則 | C Bridge は薄く保つ（複雑なデータは JSON 文字列で渡す） | JSON をやめ、1.2 の 3 方式で渡す。薄く保つ原則は残す |
| 文字列・API 取り扱い方針 | `extern "C"` + `__declspec(dllexport/dllimport)` で公開する | C ABI の公開は `.def` だけ（D-5）。C++ API は名前空間付きの通常の宣言 |
| 文字列・API 取り扱い方針 | エラー情報は `DWORD* pError` などの出力引数 | C++ は `Result`、C ABI は戻り値のエラーコード、`ntk_last_system_code()`、完了の引数 |
| 文字列・API 取り扱い方針 / Bridge の配置 | 文字列は `wchar_t*` を優先。`UnityWindowsPlugin` は残す | C++ は `std::wstring`、C ABI は UTF-8。`UnityWindowsPlugin` は削除した |

## 6. 既存実装差分サマリー（段階 4 完了時点の実測）

| 項目 | 今 | この段階の後 |
|---|---|---|
| DLL | `windows/WindowsLibrary/WindowsLibrary.vcxproj`（`src/Bridge/` の 8 ファイル + `.def`） | `windows/WindowsLibraryCApi/WindowsLibraryCApi.vcxproj`。今の DLL と `src/Bridge/` は削除 |
| export | 52（機能 47 + `Common` 5） | 105（8.2） |
| 文字列 | `wchar_t*`（UTF-16）。複合データは JSON | UTF-8 の `const char*`。複合データはハンドルとビルダー |
| 型 | `DWORD` / `BOOL` / `BYTE`。ヘッダーの 2 つは `<windows.h>` を先に要求する | `<stdint.h>` / `<stddef.h>` の型だけ |
| エラー | 最後の引数 `DWORD* pError` | 戻り値。詳細は `ntk_last_system_code()` と完了の引数 |
| コールバック | 6 種。文脈ポインタを持つのは `ClipboardRenderCallback` だけ | すべてが先頭に `void* user_data` を持つ |
| 寿命 | `init*` / `uninit*` のプロセス全体の状態 | ハンドル（`_create` / `_close` / `_free`） |
| 旧ヘッダーへの内部の依存 | Core の内部（`WindowsClipboardManagerInternal.h`、`WindowsNotificationManagerInternal.h`、Clipboard の Core / HistoryCoordinator / DeferredProvider / HistoryWinRt、両機能の `*Api.cpp`）とテスト約 10 ファイルが、旧ヘッダーの `#define` とコールバックの typedef を使っている | 定数と typedef を内部ヘッダーへ移す（8.5） |
| `extern "C"` | `src/Bridge/` のほか、`src/Common/CommonInternal.h` の `DLog` などの宣言 | Core に `extern "C"` の関数宣言を残さない |
| `UnityWindowsPlugin` | `.sln` から外れた MFC の雛形。README などに 15 ファイル・91 か所の参照（README 6） | 削除。運用の参照を `WindowsLibraryCApi` に直す |
| テスト | `ClipboardBridgeTest`（20）、`NotificationBridgeTest`（5）、`NotificationPayloadTest`（13） | 今の C ABI とともに削除し、12.1 の C ABI のテストに置き換える |

## 7. 実装アーキテクチャ

### 7.1 成果物とフォルダ

```
windows/
  WindowsLibrary/                           # 改名しない（E-11）
    WindowsLibraryCore.vcxproj              # C++ API（静的）
    include/NativeToolkit/                  # C++ API のヘッダー。E-10 の整理
    src/                                    # Bridge/ を削除。*Codes.h を追加（8.5）
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
  WindowsLibraryCApiSmoke/                  # 新規。公開ヘッダーと import ライブラリだけで組む C の実行ファイル（CT-21）
  WindowsLibraryCApiTest/                   # 新規。12.1 のテスト（Common/、Dialog/ など機能ごと）
```

- 依存の向きは CApi → Core だけ。DLL の CRT は `/MD`。C ABI の境界では C++ の型も CRT の資源も受け渡さないので、利用者の CRT と一致しなくてよい
- 配布物の名前は `windows-native-toolkit-capi-<版>.dll`（README 3.1）、版は 2.0.0（D-4）
- x64 のみ（C++ API の設計書 7.5.1 と同じ）

### 7.2 公開ヘッダー

- **C99 としても C++ としてもコンパイルできる**。`#ifdef __cplusplus` で `extern "C"` を付ける
- include するのは `<stdint.h>` と `<stddef.h>` だけ。`<windows.h>`、`<stdbool.h>` は使わない（E-8）
- **ASCII だけで書く**（C++ API の設計書 7.1 と同じ理由）
- 各機能のヘッダーは `NativeToolkitC/Common.h` を include し、単独で include してコンパイルできる
- 宣言に `__declspec(dllimport)` を付けない。公開は `.def` だけ（D-5）
- 呼び出し規約は `NTK_CALL`（MSVC では `__cdecl`、それ以外は空）を関数とコールバックの型に付ける
- ウィンドウハンドルは `void*`（`HWND` と同じ表現）
- **各ヘッダーが自分の include ガードと `extern "C"` を持つ**。何度 include してもよい
- **構造体の宣言は `#pragma pack(push, 8)` / `#pragma pack(pop)` で囲む**。利用者が外側で `#pragma pack(1)` などを指定していても、配置は付録 A のとおりになる
- マクロは、cffi の `cdef` が読めるよう、式や接尾辞の無い整数のリテラルにする（`NTK_VERSION 0x020000`。MAJOR / MINOR / PATCH と同じ値であることは T-11 で照合する）
- 対応する ABI は MSVC の x64（bindgen なら `x86_64-pc-windows-msvc`）。`x86_64-pc-windows-gnu` では無名の `enum` の型が `c_uint` になるので、比べるときに型を合わせる
- 全宣言は付録 A

### 7.3 エラー（R-12、R-27）

- **失敗しうる関数は、機能のエラーの型（`ntk_<機能>_error`）を戻り値で返す**（D-10）。0 が成功。値は C++ API の `enum class` と同じ（11 章）
- 失敗しない関数（ハンドルの読み取り、`_free`、`ntk_notification_manager_close`、`ntk_clipboard_session_can_close`、`ntk_version`、`ntk_last_system_code`）は値をそのまま返し、**システムコードを更新しない**。範囲外の添字や `NULL` のハンドルには `NULL` か 0 を返す。**0 が正しい値でもありうる読み取り（`ntk_notification_list_id_at` など）は、先に件数を確かめる**
- 出力引数:
  - **ハンドルの出力は、入口で必ず `NULL` を書いてから処理する**。成功したときだけハンドルが入る
  - 値の出力（列挙、真偽値、要求 ID、添字）は、成功したときだけ書く
- 同期の関数のシステムコード（E-4）:
  - 失敗しうる関数は、戻る直前に**呼び出しスレッドの** `ntk_last_system_code()` を更新する。成功なら 0、失敗なら `Failure::systemCode`
  - 値は、次に失敗しうる関数が戻るまで残る。**読むなら失敗の直後に、同じスレッドで読む**
  - Go は `runtime.LockOSThread()` を使うか、C の小さな補助関数で 2 回の呼び出しを 1 回にまとめる
- 非同期の完了のシステムコード（E-18）: コールバックの引数 `system_code` で渡す。スレッドごとの値は更新しない
- システムコードに入るもの（G-4）:

| 機能 | 入るもの |
|---|---|
| Dialog | OS の値（`GetLastError`、`CommDlgExtendedError`、HRESULT）。無ければ 0 |
| Notification | 多くはエラーの値そのものか 0（C++ の実装どおり）。C ABI が捕まえたメモリ不足は `NTK_SYSTEM_CODE_E_OUTOFMEMORY`（`0x8007000E`） |
| Clipboard | エラーの値そのものか 0（C++ の実装どおり） |

### 7.4 メモリと寿命

| 規則 | 内容 |
|---|---|
| 解放は確保した側の関数で | ライブラリが渡したハンドルは、対応する `_free` でだけ解放する。利用者の `free` / `delete` を使わない。ライブラリは利用者のメモリを解放しない |
| `_free(NULL)` | 何もしない |
| 所有するハンドル | `_create` で作ったもの、出力引数で受け取ったもの。利用者が 1 回だけ `_free` する |
| 借りるポインタ | ハンドルの読み取りが返す `const char*` / `const uint8_t*`。**元のハンドルを解放するまで**有効。コールバックに渡されたハンドルとそこから読んだポインタは、**コールバックから戻るまで**有効 |
| 借りる文字列の長さ | 文字列を返す読み取りは、長さ（終端を含まないバイト数）を返す出力引数 `size_t* out_size` を持つ。`NULL` でよい（R-18） |
| C# での受け方 | **借りた `const char*` の戻り値は `IntPtr` で受けて複製する**。`[return: MarshalAs(UnmanagedType.LPUTF8Str)] string` と宣言すると、マーシャラーが戻りのポインタを `CoTaskMemFree` で解放し、ヒープが壊れる |
| 入力 | 引数の文字列、配列、構造体は**呼び出しの間だけ**有効であればよい。ライブラリは必要なものを呼び出しの中で複製する |
| 文字列の終端 | 出力の文字列は必ず NUL で終わる |
| バイト列 | `ntk_bytes_data` は、長さ 0 のときも `NULL` でないポインタを返す |

**閉じていないハンドルの `_free`**（R-15、R-8）:

| ハンドル | `_free` の振る舞い |
|---|---|
| `ntk_notification_manager` | 閉じていなければ閉じる。その後、配送中の活性化が終わった時点で `release` が呼ばれる（7.5） |
| `ntk_notification_runtime` | **生きているマネージャーが無ければ**、`MddBootstrapShutdown` を呼ぶ。あれば印を付けるだけで、最後のマネージャーが閉じたときに呼ぶ（C ABI で数える）。Runtime は同時に 1 つだけで、生きている間（印を付けて Shutdown を待つ間を含む）の 2 回目の `ntk_notification_runtime_initialize` は `NOT_SUPPORTED` |
| `ntk_clipboard_session` | 閉じていれば解放するだけ。**閉じていなければ放棄**する（C++ の N-5）。放棄の後、そのプロセスではセッションを作れない（同じスレッドから `NOT_SUPPORTED`、別のスレッドから `WRONG_THREAD`）。どちらの場合も、`_free` が戻った後にこのセッションのコールバックは呼ばれない（7.5） |
| ビルダー、出力のハンドル | 解放するだけ |

### 7.5 コールバックと `user_data`

すべてのコールバックの**第 1 引数が `void* user_data`**（D-9）。ライブラリは `user_data` を読まず、渡されたまま返す。

#### 7.5.1 期間

| コールバック | 登録 | `user_data` を解放してよい時点 |
|---|---|---|
| クリップボードの変化 | セッションの設定 | close が成功した後、または `_free` が戻った後 |
| 履歴の 3 つのハンドラ | `ntk_clipboard_set_history_handlers` | 差し替えか外す呼び出しが**成功して**戻った後（オーナーのスレッドで呼ぶので、配送と重ならない）。**失敗したとき（`WRONG_THREAD`、`MONITOR_REGISTER_FAILED`）は古い登録がそのまま使われ、新しい `user_data` は登録されない**。ほかに、close が成功した後、または `_free` が戻った後 |
| 履歴の要求の完了 | `ntk_clipboard_get_history` など | 完了が呼ばれた後。**受け付けなかった要求（エラーが返った）では呼ばれない**ので、すぐ片付けてよい。セッションを `_free` した場合は、`_free` が戻った後（完了は来ない） |
| 遅延レンダリングの provider | `ntk_clipboard_reserve_deferred` | **`release` が呼ばれた後**（7.5.3） |
| 通知の活性化 | マネージャーの設定、`ntk_notification_manager_set_invoked_handler` | **`release` が呼ばれた後**（E-12）。C ABI のハンドルが解放ガードへの参照を 1 つ持ち、差し替えか close が戻る前に、C++ のロックの外で手放す。最後の参照が消えた時点でちょうど 1 回呼ばれる。スレッドは、最後の配送を終えたスレッドか、配送中が無ければ差し替えか close を呼んだスレッド |

**`release` の共通の規則**（S-1）:

- `release` を引数や構造体の項目で受け取る関数は、`release != NULL` なら**戻り値にかかわらず、ちょうど 1 回**呼ぶ。失敗したときは、呼び出しスレッドで関数が戻る前に呼ぶ。利用者はエラーが返っても `user_data` を自分で片付けない
- 例外は `release` を受け取れなかった場合（`options == NULL` など）だけ
- 閉じたマネージャーへの `set_invoked_handler` は、登録せずに `NOT_INITIALIZED` を返し、その場で `release` を呼ぶ
- `release` は登録ごと。同じポインタの値で登録し直すときも、登録のたびに別の所有権（C# なら新しい `GCHandle`）を渡す。前の登録の `release` が後から来る
- 履歴の要求の完了は `release` を持たない。受け付けなかった要求では呼ばれないので、エラーのときは呼び出し側が片付ける（`release` と逆。Doxygen に明記する）

#### 7.5.2 生存フラグ（R-2、S-2）

セッションの C ABI の包みは、コールバックを C++ API に渡すときに、**生存フラグと呼び出し中の件数を共有する小さな状態**を捕捉させる。

- C のコールバック（変化、履歴のハンドラ、履歴の完了、provider、provider の `release`）を呼ぶときは、ロックの下でフラグを確かめて**呼び出し中の件数**を増やし、**ロックを外してから**呼び、戻ったら減らす。コールバックの間はロックを持たない
- 同じスレッドで入れ子になった呼び出し（コールバックの中の書き込みやモーダルなループで来る provider、`release`、完了）は件数を増やすだけで、止まらない
- `ntk_clipboard_session_free` は、フラグを倒した後、**ほかのスレッドの呼び出し中の件数**が 0 になるまで待つ。**`_free` が戻った後、C の関数ポインタは 2 度と呼ばれない**
- コールバックの中からの `_free` は 1.3.5 で禁じている。Debug ではスレッド ID を記録して assert する
- 放棄したセッションの C++ 側の資源（ウィンドウ、リスナー、処理中の要求）はプロセスが終わるまで残る。しかし利用者のコードには届かない

#### 7.5.3 遅延レンダリング（R-6、R-20、S-3）

- provider は形式ごとにコピーされる（C++ の実装）。C ABI の包みは解放ガードを `shared_ptr` で共有する。ガードは「呼んだ」の印を持ち、**`release(user_data)` はちょうど 1 回**だけ呼ぶ
- 手放す時期:

| 場面 | `release` |
|---|---|
| 次の `ntk_clipboard_reserve_deferred` が `EmptyClipboard` に達した（その後で予約が失敗しても、前の分は戻らない） | 前の予約の分を、オーナーのスレッドで呼ぶ |
| このセッションの書き込みか消去（`copy_*`、`copy_multiple`、`clear`。どのスレッドからでも） | オーナーのスレッドで、書き込みの呼び出しが戻る前に呼ぶ（`WM_DESTROYCLIPBOARD` が同期で送られる） |
| ほかのアプリがクリップボードを消去した | オーナーのスレッドで呼ぶ |
| `ntk_clipboard_recover_deferred_state` が成功した | オーナーのスレッドで呼ぶ |
| 予約が失敗した（`PARTIAL_STATE` 以外） | 呼び出しスレッドで、関数が戻る前に呼ぶ |
| **C ABI の入口の検査で拒んだ**（`NULL`、件数 0、不正な UTF-8 など） | **呼び出しスレッドで、関数が戻る前に呼ぶ** |
| 予約が `PARTIAL_STATE` で失敗した | 保持したまま。後の上の場面のどれかか、下の close / `_free` で呼ぶ |
| **セッションの close が成功した** | **close が戻る前に、オーナーのスレッドで呼ぶ**。close の中の `WM_RENDERALLFORMATS` で provider が呼ばれた後になる。ウィンドウが無くなるので、以後 provider は呼ばれない |
| **`ntk_clipboard_session_free`（放棄を含む）** | **まだ呼んでいなければ、`_free` の中で呼ぶ** |
| `_free` が戻った後 | **呼ばない**。C++ に残ったコピーが後で消えても（DLL のアンロードを含む）、印があるので何もしない |

- `release != NULL` なら、**戻り値にかかわらず**上の規則でちょうど 1 回呼ぶ（7.5.1 の共通の規則）
- provider は要求された形式のバイト列を `ntk_clipboard_render_target_set` で渡し、`NTK_CLIPBOARD_ERROR_NONE` を返す
  - `set` は 1 回だけ。2 回目は `INVALID_PARAMETER`
  - `set` はデータを呼び出しの中で複製する
  - `set` を呼ばずに `NONE` を返したら何も描画しない。0 以外を返したら、`set` を呼んでいても描画しない
  - `target` は provider の呼び出しの間だけ有効
- provider は、close の中（`WM_RENDERALLFORMATS`）と、自分や他のスレッドの読み取り（`WM_RENDERFORMAT`）の中からも呼ばれる

#### 7.5.4 履歴の要求（R-19）

- コールバックは必須。`NULL` なら受付の前に `INVALID_PARAMETER` を返し、コールバックは呼ばれない
- `out_request_id` は `NULL` でよい
- 完了はオーナーのスレッドで来る。**オーナー以外のスレッドから受け付けた場合、完了が受付の戻りより先に来うる**。要求と完了の対応付けには、要求 ID ではなく `user_data` を使う
- 可否の完了（availability）は、失敗したときは 2 つの真偽値がどちらも 0 で、意味を持たない

#### 7.5.5 そのほか

- ライブラリはコールバックを呼ぶ間、利用者が触れるロックを持たない。1.3.5 の禁止事項を除き、コールバックからほかの `ntk_*` を呼んでよい

### 7.6 文字列（R-16、R-22）

- 入力の文字列は **NUL で終わる UTF-8**。不正な UTF-8 は `INVALID_PARAMETER`
- 省略できる入力（C++ で `std::optional` の項目）は、**`NULL` が「無い」、`""` が「空で在る」**。この区別は入力一覧（`designs/2026-09-20-windows-architecture-c-abi-input-inventory.md`）§1.10 の「キーが有って空」の表と同じ意味を持つ
- 省略できない入力のうち、C++ で素の `std::wstring` の項目は **`NULL` を `""` とする**（E-15）。意味の上で必須な値（コピーする本文、形式名、項目の ID、ボタンのラベル、ビルダーやハンドルそのもの）の `NULL` は `INVALID_PARAMETER`
- 出力の文字列は NUL で終わる UTF-8。途中に NUL は入らない
- 出力の変換で、対になっていないサロゲートは **U+FFFD に置き換える**（E-16）。置き換えたパスは元のファイルを指さないことがある

### 7.7 例外と異常終了

- **すべての入口で例外を捕まえる。** `std::bad_alloc` は Clipboard が `OUT_OF_MEMORY`、Dialog が `UNKNOWN`、Notification が `HRESULT_FAILURE`（システムコードは `NTK_SYSTEM_CODE_E_OUTOFMEMORY`）。それ以外の例外は `UNKNOWN`（Notification は `HRESULT_FAILURE`）
- 利用者のコールバックは例外を投げてはならない。C++ で書いたコールバックが投げた場合は、C ABI の包みが捕まえて捨てる。SEH の例外は捕まえない

### 7.8 版と構造体（R-7、S-7）

- `ntk_version()` は DLL の版を返す。ヘッダーの `NTK_VERSION` と比べれば、ヘッダーと DLL の組み合わせの違いを実行時に検出できる
- 次の規則は、**`ntk_dialog_filter` を除く、入力オプションの構造体**に適用する。`ntk_dialog_filter` は項目を足さないと決めた組で、`struct_size` を持たない
  1. 構造体は `uint32_t struct_size; uint32_t reserved0;` で始まる。途中と末尾の詰め物も `reserved` 項目として明示し、**`reserved` が 0 でなければ `INVALID_PARAMETER`**
  2. **最小の大きさは 2.0.0 の `sizeof` に固定**し、それより小さい `struct_size` は `INVALID_PARAMETER`。**上限は 4096 バイト**で、超えたら `INVALID_PARAMETER`（初期化を忘れた値で、呼び出し側のメモリの範囲外まで読みに行かないため）
  3. 項目は `offsetof(項目) + sizeof(項目) <= struct_size` のときだけ読む。足りない項目は既定値（0）とする。**新しい DLL は古い大きさの構造体をそのまま受け付ける**
  4. 知っている大きさを超える部分は、**すべて 0 なら受け付け、0 以外が 1 バイトでもあれば `NOT_SUPPORTED`**（Dialog には `NOT_SUPPORTED` が無いので `INVALID_PARAMETER`）。新しいヘッダーで組んだ利用者が、古い DLL に新しい項目の意味を黙って捨てられないようにする（Linux の `copy_struct_from_user` と同じ規則）
  5. 項目を足すときは、`sizeof` が必ず増える形（8 バイトの倍数で増やす）にする
- この規則は C ABI の共通の読み取り関数 1 つにまとめ、すべての構造体で使う（T-02）
- C# の利用者は `sizeof` ではなく `Marshal.SizeOf<T>()` を `struct_size` に入れる
- 構造体に項目を足すこと、関数を足すことは互換の変更。既存の関数のシグネチャや意味を変えるのは 3.0.0

## 8. API 設計

**公開 OP**: OP-01〜OP-47 の **47 件**。C++ API の設計書の OP をそのまま使う。

### 8.1 OP ごとの C 関数

戻り値の型は機能のエラー（`ntk_dialog_error` / `ntk_notification_error` / `ntk_clipboard_error`）。引数の `s` はセッション、`m` はマネージャー。完全な宣言は付録 A。

| OP | C++ API | C 関数 | 変換 |
|---|---|---|---|
| OP-01 | `ShowAlert` | `ntk_dialog_show_alert(request, out_result)` | 構造体 → `AlertRequest`。`request == NULL` は既定値 |
| OP-02 | `ShowOpenFile` | `ntk_dialog_show_open_file(request, filters, filter_count, out_path)` | フィルターの組 → `FileFilter`。パスをハンドルで返す |
| OP-03 | `ShowOpenFiles` | `ntk_dialog_show_open_files(request, filters, filter_count, out_paths)` | 各要素はフルパス |
| OP-04 | `ShowSaveFile` | `ntk_dialog_show_save_file(request, filters, filter_count, out_path)` | 同 OP-02 |
| OP-05 | `ShowPickFolder` | `ntk_dialog_show_pick_folder(request, out_path)` | 同 OP-02 |
| OP-06 | `ShowPickFolders` | `ntk_dialog_show_pick_folders(request, out_paths)` | 同 OP-03 |
| OP-07 | `Runtime::Initialize` | `ntk_notification_runtime_initialize(major_minor, out_runtime)` | トークンをハンドルにする。`_free` は 7.4 |
| OP-08 | `Manager::Create` | `ntk_notification_manager_create(options, out_manager)` | 構造体 → `ManagerOptions`。`is_unpackaged`（E-9）、`release`（E-12） |
| OP-09 | `Manager::Close` | `ntk_notification_manager_close(m)`（戻り値 `void`） | C ABI のハンドルが持つ解放ガードの参照を、C++ のロックの外で手放す |
| OP-10 | `Manager::Show` | `ntk_notification_show(m, content)` | ビルダー → `NotificationContent` |
| OP-11 | `Manager::Schedule` | `ntk_notification_schedule(m, content, unix_ms)` | Unix ミリ秒 → `time_point` |
| OP-12 | `Manager::CancelScheduled` | `ntk_notification_cancel_scheduled(m, tag, group)` | `NULL` は `""` |
| OP-13 | `Manager::UpdateProgress` | `ntk_notification_update_progress(m, update)` | 構造体 → `ProgressUpdate` |
| OP-14 | `Manager::SetBadge` | `ntk_notification_set_badge(m, value)` | - |
| OP-15 | `Manager::RemoveById` | `ntk_notification_remove_by_id(m, id)` | - |
| OP-16 | `Manager::RemoveByTag` | `ntk_notification_remove_by_tag(m, tag, group)` | `NULL` は `""` |
| OP-17 | `Manager::RemoveAll` | `ntk_notification_remove_all(m)` | - |
| OP-18 | `Manager::GetAll` | `ntk_notification_get_all(m, out_list)` | `vector<NotificationRef>` → ハンドル |
| OP-19 | `Manager::GetSetting` | `ntk_notification_get_setting(m, out_setting)` | - |
| OP-20 | `Manager::OpenSettings` | `ntk_notification_open_settings(m)` | - |
| OP-21 | `Session::Create` | `ntk_clipboard_session_create(options, out_session)` | 構造体（`NULL` 可）→ `SessionOptions`。生存フラグを作る |
| OP-22 | `Session::SetHistoryHandlers` | `ntk_clipboard_set_history_handlers(s, handlers)` | `NULL` か 3 つとも `NULL` で外す |
| OP-23 | `Session::Close` | `ntk_clipboard_session_close(s)` | 5 通りのエラーをそのまま返す |
| OP-24 | `Session::CanClose` | `ntk_clipboard_session_can_close(s)`（戻り値 `int32_t`） | `NULL` は真（閉じるものが無い） |
| OP-25 | `Session::CopyText` | `ntk_clipboard_copy_text(s, text, flags)` | `flags` → `WriteOptions` |
| OP-26 | `Session::PasteText` | `ntk_clipboard_paste_text(s, out_text)` | - |
| OP-27 | `Session::CopyHtml` | `ntk_clipboard_copy_html(s, fragment, plain_text, flags)` | `plain_text` の `NULL` は `""` |
| OP-28 | `Session::PasteHtml` | `ntk_clipboard_paste_html(s, out_html)` | - |
| OP-29 | `Session::CopyFiles` | `ntk_clipboard_copy_files(s, paths, count, flags)` | - |
| OP-30 | `Session::PasteFiles` | `ntk_clipboard_paste_files(s, out_paths)` | - |
| OP-31 | `Session::CopyDib` | `ntk_clipboard_copy_dib(s, dib, size, flags)` | - |
| OP-32 | `Session::PasteDib` | `ntk_clipboard_paste_dib(s, out_dib)` | - |
| OP-33 | `Session::CopyCustom` | `ntk_clipboard_copy_custom(s, format_name, data, size, flags)` | - |
| OP-34 | `Session::PasteCustom` | `ntk_clipboard_paste_custom(s, format_name, out_data)` | - |
| OP-35 | `Session::CopyMultiple` | `ntk_clipboard_copy_multiple(s, items, flags)` | ビルダー → `vector<FormatPayload>`。並びは積んだ順 |
| OP-36 | `Session::HasFormat` | `ntk_clipboard_has_format(s, format_name, out_present)` | - |
| OP-37 | `Session::GetFormats` | `ntk_clipboard_get_formats(s, out_formats)` | - |
| OP-38 | `Session::GetPreferredFormat` | `ntk_clipboard_get_preferred_format(s, out_format)` | 候補が無ければ空文字列（C++ と同じ） |
| OP-39 | `Session::Clear` | `ntk_clipboard_clear(s)` | - |
| OP-40 | `Session::ReserveDeferred` | `ntk_clipboard_reserve_deferred(s, formats, count, provider, user_data, release)` | provider を `RenderProvider` に包む。`release` は 7.5.3 |
| OP-41 | `Session::RecoverDeferredState` | `ntk_clipboard_recover_deferred_state(s)` | - |
| OP-42 | `Session::GetHistory` | `ntk_clipboard_get_history(s, callback, user_data, out_request_id)` | 完了に借りの `ntk_clipboard_history*` とシステムコードを渡す |
| OP-43 | `Session::RestoreHistoryItem` | `ntk_clipboard_restore_history_item(s, item_id, callback, user_data, out_request_id)` | - |
| OP-44 | `Session::DeleteHistoryItem` | `ntk_clipboard_delete_history_item(s, item_id, callback, user_data, out_request_id)` | - |
| OP-45 | `Session::ClearUnpinnedHistory` | `ntk_clipboard_clear_unpinned_history(s, callback, user_data, out_request_id)` | - |
| OP-46 | `Session::GetHistoryAvailability` | `ntk_clipboard_get_history_availability(s, callback, user_data, out_request_id)` | 完了に 2 つの真偽値を渡す |
| OP-47 | `Session::CancelRequest` | `ntk_clipboard_cancel_request(s, request_id)` | 未知・完了済みは `INVALID_PARAMETER` |

### 8.2 公開する関数の全体（105）

8.1 の 47 操作のほかに、ハンドルの寿命と読み取り、ビルダーの関数を公開する。**`.def`、ヘッダー、付録 A はこの表と一致させる**（T-11 の機械照合）。

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
| `Clipboard.h` | 履歴（OP-42 の完了の引数） | `ntk_clipboard_history_count`、`ntk_clipboard_history_item_id`、`ntk_clipboard_history_item_text`、`ntk_clipboard_history_item_content_type_count`、`ntk_clipboard_history_item_content_type_at`、`ntk_clipboard_history_item_timestamp_unix_ms` | 6 |
| 合計 | | | **105** |

公開関数は今の 52 から 105 に増える。D-6 が短所として挙げた「項目 1 つにつき取得関数が 1 つ」の結果で、名前の規則（1.1）で見分けがつくようにした。

### 8.3 今の 52 関数との対応表

`unity-native-plugin` の P/Invoke を書き直すための表（README 5.1）。**すべての関数でシグネチャが変わる**（UTF-8、`user_data`、戻り値のエラー）。`変わる振る舞い` 列は、シグネチャの変更のほかに意味が変わる点。

**すべての関数に共通の変化**:

- `pError` の値は戻り値になる。OS の生の値が要るときは `ntk_last_system_code()`（同期）か完了の `system_code` 引数（非同期）
- 文字列は UTF-8。UTF-16 に戻せない文字は U+FFFD になる（E-16）
- 省略できない文字列の `NULL` は、今と同じく `""` として扱う（E-15）

| 今の関数 | 新しい関数 | 変わる振る舞い |
|---|---|---|
| `showAlertDialog` | `ntk_dialog_show_alert` | `MB_*` の 4 つのフラグ語は列挙になり、それ以外の `MB_*` は渡せない（E-2）。戻り値は `IDOK` などの整数ではなく `ntk_dialog_alert_result`。`owner` を渡せるようになる（E-13） |
| `showFileDialog` | `ntk_dialog_show_open_file` | キャンセルは `*pError == -1` ではなく `NTK_DIALOG_ERROR_CANCELED`。失敗は OS の生の値ではなく `SYSTEM_ERROR` と `ntk_last_system_code()`。フィルターは NUL 区切りの 1 文字列ではなく、名前とパターンの組の配列。`title`、`allow_missing_file`、`owner` が効く（E-13）。**パスの上限は終端を含めて 1024 文字（パスは 1023 文字まで）**で、超えると `SYSTEM_ERROR`。今は呼び出し側がバッファの大きさを決めていた |
| `showMultiFileDialog` | `ntk_dialog_show_open_files` | 先頭のフォルダ名と名前の並びではなく、**フルパスの一覧**。件数にフォルダを数えない（C++ API の OP-03）。上限は合計 32768 文字 |
| `showSaveFileDialog` | `ntk_dialog_show_save_file` | 上書きの確認を `skip_overwrite_prompt` で外せる（今は常に確認）。`title`、`owner` が効く。上限は終端を含めて 1024 文字 |
| `showFolderDialog` | `ntk_dialog_show_pick_folder` | キャンセルは `TRUE` + `pError == -1` ではなく `CANCELED`。上限は終端を含めて 1024 文字 |
| `showMultiFolderDialog` | `ntk_dialog_show_pick_folders` | キャンセルは件数 0 や `-1` ではなく `CANCELED`。成功して 0 件のときとキャンセルが区別できる。上限は合計 32768 文字 |
| `initWinAppSdk` | `ntk_notification_runtime_initialize` | ハンドルを解放すると、マネージャーがすべて閉じた後に `MddBootstrapShutdown` が呼ばれる（7.4）。今は呼ばれない |
| `initNotificationManager` | `ntk_notification_manager_create` | 2 回目は成功（コールバックの差し替え）ではなく `NOT_SUPPORTED`。差し替えは `ntk_notification_manager_set_invoked_handler`。`user_data` の解放は `release` で知らされる（E-12） |
| `uninitNotificationManager` | `ntk_notification_manager_close` / `_free` | 戻った後も、配送中の活性化が 1 回走りうる。`user_data` は `release` の後に解放する |
| `showNotification` | `ntk_notification_show` | JSON ではなくビルダー。JSON の解析の失敗（`INVALID_PAYLOAD`）は起きなくなり、意味の検証の失敗は今と同じ `INVALID_PARAMETER`。**`timestamp` は Unix 秒から Unix ミリ秒になる**。scenario、音声の種別（`audio.type`）、ロゴの crop は、未知の文字列が黙って既定になっていたのが、列挙の範囲外の値なら `INVALID_PARAMETER` になる。ボタンのラベルや入力欄の ID が無いときは、`HRESULT_FAILURE` から `INVALID_PARAMETER` になる |
| `scheduleNotification` | `ntk_notification_schedule` | 同上 |
| `cancelScheduledNotification` | `ntk_notification_cancel_scheduled` | - |
| `updateNotificationProgress` | `ntk_notification_update_progress` | 6 引数が構造体になる |
| `setBadge` | `ntk_notification_set_badge` | - |
| `removeNotificationById` | `ntk_notification_remove_by_id` | - |
| `removeNotificationsByTag` | `ntk_notification_remove_by_tag` | - |
| `removeAllNotifications` | `ntk_notification_remove_all` | - |
| `getAllNotifications` | `ntk_notification_get_all` | JSON とバッファではなく一覧のハンドル。バッファが足りずに切れることが無くなる |
| `getNotificationSetting` | `ntk_notification_get_setting` | `-1` ではなくエラー。閉じたマネージャーは `NOT_INITIALIZED`、`NULL` のハンドルは `INVALID_PARAMETER` |
| `openNotificationSettings` | `ntk_notification_open_settings` | - |
| （コールバック）`NotificationInvokedCallback` | `ntk_notification_invoked_fn` | 引数が JSON の文字列から、活性化のハンドルになる。`ntk_notification_activation_raw_arguments` は今と同じ JSON を返す |
| `initClipboardManager` | `ntk_clipboard_session_create` | 同じスレッドからの 2 回目は成功ではなく `NOT_SUPPORTED`（C++ API の OP-21。段階 4 のサンプルで確かめた差） |
| `setClipboardHistoryCallbacks` | `ntk_clipboard_set_history_handlers` | 3 つのコールバックが 1 つの構造体と `user_data` になる |
| `uninitClipboardManager` | `ntk_clipboard_session_close` | `BOOL` + `pError` ではなくエラーだけ。成功した後に `_free` する。**処理中の要求があっても、メッセージを回さずに閉じられる**（E-19）。`BUSY` のときだけ再試行する |
| `canDestroyClipboardManager` | `ntk_clipboard_session_can_close` | - |
| `copyPlainText` | `ntk_clipboard_copy_text` | 未知のオプションのビットは、今と同じく `INVALID_PARAMETER`（1.11.0 のコアも拒んでいた。捨てていたのは配布していない段階 3 のブリッジだけ）。`SENSITIVE`（3）は同じ値で残す |
| `pastePlainText` | `ntk_clipboard_paste_text` | 2 回の呼び出しが 1 回になる |
| `copyHtml` | `ntk_clipboard_copy_html` | 未知のビット（同上） |
| `pasteHtml` | `ntk_clipboard_paste_html` | 同 `pastePlainText` |
| `copyFiles` | `ntk_clipboard_copy_files` | JSON の配列ではなく文字列の配列。未知のビット（同上） |
| `pasteFiles` | `ntk_clipboard_paste_files` | JSON ではなく一覧のハンドル |
| `copyImage` | `ntk_clipboard_copy_dib` | 名前が中身（DIB）を表すようになる。未知のビット（同上） |
| `pasteImage` | `ntk_clipboard_paste_dib` | 同 `pastePlainText` |
| `copyCustomFormat` | `ntk_clipboard_copy_custom` | 未知のビット（同上） |
| `pasteCustomFormat` | `ntk_clipboard_paste_custom` | 同 `pastePlainText` |
| `copyMultipleFormats` | `ntk_clipboard_copy_multiple` | JSON（バイト列は base64）ではなくビルダー（バイト列はそのまま）。未知のビット（同上） |
| `hasClipboardFormat` | `ntk_clipboard_has_format` | `BOOL` の戻り値ではなく出力引数 |
| `getClipboardFormats` | `ntk_clipboard_get_formats` | JSON ではなく一覧のハンドル |
| `getPreferredClipboardFormat` | `ntk_clipboard_get_preferred_format` | - |
| `clearClipboard` | `ntk_clipboard_clear` | - |
| `reserveDeferredFormats` | `ntk_clipboard_reserve_deferred` | provider は 2 相（サイズの問い合わせと書き込み）ではなく 1 回。`void* context` が `user_data` になり、`release` が付く。**エラーが返っても `user_data` を自分で片付けない**（`release` が呼ばれる） |
| `recoverDeferredState` | `ntk_clipboard_recover_deferred_state` | - |
| `getClipboardHistory` | `ntk_clipboard_get_history` | 完了に JSON ではなく履歴のハンドル（コールバックの間だけ有効）。**timestamp は 10 進の文字列（WinRT の tick）から Unix ミリ秒の `int64_t` になる**（E-14）。コールバックの `NULL` は `INVALID_PARAMETER` |
| `restoreHistoryItem` | `ntk_clipboard_restore_history_item` | 完了にシステムコードが付く |
| `deleteHistoryItem` | `ntk_clipboard_delete_history_item` | 同上 |
| `clearUnpinnedHistory` | `ntk_clipboard_clear_unpinned_history` | 同上 |
| `getClipboardHistoryAvailability` | `ntk_clipboard_get_history_availability` | 完了に JSON ではなく 2 つの真偽値 |
| `cancelClipboardRequest` | `ntk_clipboard_cancel_request` | `BOOL` + `pError` ではなくエラーだけ |
| `DLog` | 無し | 公開をやめる（E-6） |
| `DFLog` | 無し | 同上 |
| `DFLLog` | 無し | 同上 |
| `ToWString` | 無し | 同上 |
| `ConcatWStrings` | 無し | 同上 |

### 8.4 型と関数の補足

完全な宣言は付録 A。ここには宣言だけでは分からない意味を書く。

#### 8.4.1 Dialog

- `request == NULL` はすべて既定値の要求として扱う
- `ntk_dialog_filter` は**項目を足さない**と決めた組（`struct_size` を持たない）。`patterns` は `;` で区切ったパターンで、C++ の `FileFilter::patterns` に分けて渡す。`filters == NULL` かつ `filter_count == 0` はすべてのファイル
- 列挙の値の順は C++ API の `enum class` の宣言順と同じ（T-11 で照合）

#### 8.4.2 Notification の内容のビルダー

いずれも `ntk_notification_content* c` を第 1 引数に取り、`ntk_notification_error` を返す（`_free` を除く）。

| 関数 | C++ の項目 | `NULL` の意味 |
|---|---|---|
| `_set_title` / `_set_body` / `_set_attribution` / `_set_hero_image` / `_set_inline_image` | 同名の `std::optional<std::wstring>` | 無い（在るが空は `""`） |
| `_set_tag` / `_set_group` | `tag` / `group` | `""`（E-15） |
| `_set_scenario` / `_set_duration` | `scenario` / `duration` | - |
| `_set_app_logo(c, uri, crop)` | `appLogo` | `uri == NULL` で外す |
| `_set_audio(c, kind, event_name, uri, loop)` | `audio` | `event_name` の `NULL` は `""`。`uri` の `NULL` は無い |
| `_add_button(c, label, invoke_uri, with_arguments, out_index)` | `buttons` に追加。`with_arguments` が真なら `args` を空で在るにする | `label` は必須。`invoke_uri` の `NULL` は無い。`out_index` は `NULL` 可 |
| `_add_button_argument(c, button_index, key, value)` | `buttons[i].args` に追加（在るにする） | `key` は必須。`value` の `NULL` は `""` |
| `_add_text_input(c, id, placeholder, title)` | `textInputs` に追加 | `id` は必須。`placeholder` / `title` の `NULL` は無い |
| `_add_combo(c, id, title, default_selection, out_index)` | `comboInputs` に追加 | `id` は必須。`title` / `default_selection` の `NULL` は `""` |
| `_add_combo_item(c, combo_index, id, label)` | `comboInputs[i].items` に追加 | `id` と `label` は必須 |
| `_set_progress(c, title, value, value_string, status)` | `progress` | 各文字列の `NULL` は無い |
| `_set_timestamp(c, unix_ms)` | `timestamp` | - |
| `_set_expiration(c, seconds)` | `expiration` | - |
| `_set_expires_on_reboot(c, value)` | `expiresOnReboot` | - |

- **ビルダーは検証しない**。6 個目のボタンや短い表示時間でのループ音は、C++ API と同じく `ntk_notification_show` / `_schedule` が `INVALID_PARAMETER` で拒む
- 範囲外の添字、範囲外の列挙の値は `INVALID_PARAMETER`
- 「無い」に戻せるのは、省略できる文字列の項目（`NULL` を渡す）とアプリのロゴ（`uri == NULL`）だけ。音声、進捗、timestamp、expiration を戻す関数は持たない。**戻したいときはビルダーを作り直す**。ビルダーは使い回してよく、`show` はビルダーを変えない

#### 8.4.3 Clipboard

- 書き込みのオプションは構造体ではなくビットの組。未知のビットは `INVALID_PARAMETER`。`SENSITIVE` は今の C ABI の定数の値（3）を残す
- 複数形式のビルダーの 3 つの `_add_*` は、C++ の `TextPayload` / `HtmlPayload` / `BytesPayload` に 1 対 1。形式名と種別の組み合わせの検証は、C++ API と同じく `ntk_clipboard_copy_multiple` が行う
- 履歴のハンドルは C++ の `HistoryItem` を読む。`ntk_clipboard_history_item_text` は、テキストを持たない項目と範囲外の添字のどちらにも `NULL` を返すので、先に件数を確かめる。README の D-6 の例にある `is_pinned` は C++ API に無いので持たない
- timestamp を読めなかった項目（C++ で tick が 0）は 0 を返す。1601 年を表す負の値にはしない

### 8.5 C++ API と Core の整理（E-10、R-3、R-4）

| 対象 | 変更 | 影響 |
|---|---|---|
| `AlertRequest::extraFlags` | 削除。`ToMessageBoxType` の `\| request.extraFlags` を外す | `Data/WindowsDialogFlags.h`、`WindowsDialogApi.cpp`、`Dialog.h` の説明、`DialogMappingTest` の 1 件。サンプルは使っていない |
| `NotificationContent::unknownKeys` | 削除 | `Notification.h` の説明と JSON のパーサ（`src/Bridge/` とともに消える） |
| `NotificationError::InvalidPayload`（3） | 欠番。Doxygen に「返さない。1.x の C ABI の JSON の解析失敗」と書く（今の「content failed validation」は誤り） | 値は詰めない |
| `DialogError::BufferTooSmall`（3）、`ClipboardError::BufferTooSmall`（7） | 同上 | 同上 |
| 旧 C ABI のヘッダー 4 つ（`common.h`、`WindowsDialogManager.h`、`WindowsNotificationManager.h`、`WindowsClipboardManager.h`） | **定数（`CLIPBOARD_ERROR_*`、`NOTIFICATION_*` など）とコールバックの typedef を、内部ヘッダー `src/<機能>/<機能>Codes.h` へ移してから削除する** | Core の内部と、テスト約 10 ファイルの include |
| `src/Common/CommonInternal.h` の `extern "C"` | 外す（`DLog` などは C++ のリンケージの内部関数にする） | Core 全体。名前は変えない |
| `src/Bridge/` | 削除 | JSON の読み書き（`ClipboardPayloadJson`、`NotificationPayloadJson`）を含む |
| Dialog の内部入口（`src/Dialog/Data/WindowsDialogWin32.h` のクラス `WindowsDialogManager` の `Show*Dialog`。削除する旧ヘッダー `src/Dialog/WindowsDialogManager.h` とは別のもの） | **残す**。C++ API はこの上に実装されている。T-03 で `owner`、`title`、フラグを受け取るようにシグネチャを変える | - |
| C++ の公開ヘッダーの Doxygen のうち、旧 C ABI に触れるもの（`Runtime` の「C ABI は解放しない」、Dialog の「旧 C ABI は owner / title を渡さない」など） | 新しい C ABI に合わせて書き直す | T-14 で全件検索する |

`check_cpp_api_contract.py` は旧 `.def` と旧ヘッダーを読み、無ければ黙って skip する。次のように付け替え、**読めなければ失敗にする**。

| 照合 | 今 | 付け替え先 | タスク |
|---|---|---|---|
| C++ の設計書 8.1 の C の名前が export されているか | 旧名（`copyPlainText` など）と旧 `.def` | **削除**。この設計書の 8.1 と新しい `.def` の照合（12.3）に置き換える | T-11 |
| 列挙と `#define` の 1 対 1 | 旧ヘッダーの `#define` | C ABI のヘッダーの無名 `enum`（パーサを `enum` に対応させる） | T-11 |
| C++ の内部が使う定数の出どころ | 旧ヘッダー | `src/<機能>/<機能>Codes.h` | T-12 |

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
| OP-07 | `ntk_notification_runtime_initialize` | 同期 | 呼び出しスレッド | 任意 | トークン → 参照を数えるハンドル |
| OP-08 | `ntk_notification_manager_create` | 同期 | 呼び出しスレッド | 任意 | 関数ポインタ + `user_data` + `release` → 解放ガード付きの包み |
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
| OP-21 | `ntk_clipboard_session_create` | 同期 | 呼び出しスレッド（オーナーになる） | STA | 関数ポインタ + `user_data` → 生存フラグと呼び出し中の件数を持つ包み |
| OP-22 | `ntk_clipboard_set_history_handlers` | 同期 | オーナー | オーナーだけ | 同上 |
| OP-23 | `ntk_clipboard_session_close` | 同期（`BUSY` のときだけ再試行） | オーナー | オーナーだけ | 自分宛てのメッセージの処理は C++ が行う（E-19）。成功したら provider の `release` を呼ぶ |
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
| OP-40 | `ntk_clipboard_reserve_deferred` | 同期。provider はオーナーで後から呼ばれる | オーナー | オーナーだけ | provider → `RenderProvider`、`release` を共有の解放ガードに結ぶ |
| OP-41 | `ntk_clipboard_recover_deferred_state` | 同期 | オーナー | オーナーだけ | - |
| OP-42 | `ntk_clipboard_get_history` | 非同期（コールバック） | オーナー | 任意 | 完了に借りの履歴ハンドルとシステムコード |
| OP-43 | `ntk_clipboard_restore_history_item` | 非同期（コールバック） | オーナー | 任意 | 完了にシステムコード |
| OP-44 | `ntk_clipboard_delete_history_item` | 非同期（コールバック） | オーナー | 任意 | 同上 |
| OP-45 | `ntk_clipboard_clear_unpinned_history` | 非同期（コールバック） | オーナー | 任意 | 同上 |
| OP-46 | `ntk_clipboard_get_history_availability` | 非同期（コールバック） | オーナー | 任意 | 完了に 2 つの真偽値とシステムコード |
| OP-47 | `ntk_clipboard_cancel_request` | 同期 | 呼び出しスレッド | 任意 | - |

### 9.1 C ABI で加わる変換

- 文字列は入口で UTF-8 → UTF-16、出口で UTF-16 → UTF-8 に変換する。入口の不正な UTF-8 は `INVALID_PARAMETER`、出口の不正な UTF-16 は U+FFFD に置き換える（E-16）
- コールバックは、関数ポインタと `user_data` を捕捉した `std::function` に包んで C++ API に渡す。セッションの包みは生存フラグと呼び出し中の件数（7.5.2）を、通知の包みと provider の包みは解放ガード（E-12、7.5.3）を共有する
- 同期性は変えない。`std::future` やスレッドを C ABI で足さない

## 10. 既存の約束の対応表

C++ API の設計書 10 章の約束は、C++ API が守る。C ABI は包むだけなので、**C ABI が壊しうる約束**と、**C ABI で新しく生まれる約束**だけを挙げる。

| 約束 | 出典 | C ABI で守る方法 |
|---|---|---|
| 受け付けた履歴の要求の完了はちょうど 1 回、受け付けなかった要求は 0 回 | C++ 設計書 CLP-06 | 包みを C++ API に渡すだけで、C ABI は回数を足さない。**例外は放棄した後で、生存フラグにより 0 回になる**。CT-12 で確かめる |
| 完了は受付の呼び出しの中では来ない | CLP-02 | 同上。ただしオーナー以外のスレッドからの受付では、受付の戻りより先に来うる（7.5.4） |
| キャンセルは論理。配送中の完了は取り消さない | CLP-16、CLP-17 | 同上 |
| `close` は成功するまで呼ぶ。5 通りのエラーを返し分ける | C++ 設計書 7.4.1 | `Session::Close` の結果をそのまま返す。E-19 で、取り消した要求の配送は close の中で終わるので、`CANCELED` のための再試行は要らなくなる |
| 閉じていないセッションの破棄は放棄 | C++ 設計書 N-5 | `ntk_clipboard_session_free` が放棄する。以後の `create` は同じスレッドから `NOT_SUPPORTED`、別のスレッドから `WRONG_THREAD`。Debug ビルドの DLL では assert する |
| 通知の解除は、登録の取り消しを先に、コールバックの解除を後に | NTF-40 | `Manager::Close` を呼ぶだけ。`release` は解放ガードの最後の参照が消えてから |
| 通知の活性化は OS が選んだスレッドで来る | C++ 設計書 7.5.4 | 1.3.1 と Doxygen に書く |
| Runtime はマネージャーを使う間ずっと保持する | C++ 設計書 N-7、`Notification.h` の `Runtime` | C ABI で生きているマネージャーを数え、`runtime_free` の Shutdown を最後のマネージャーの close まで遅らせる |
| **新**: 借りたポインタはハンドルかコールバックの期間だけ有効 | 7.4 | ハンドルの中に UTF-8 の複製を持ち、読み取りはそれを指す |
| **新**: `release` はちょうど 1 回。失敗しても呼ぶ | 7.5.1、7.5.3 | provider も通知も `shared_ptr` の解放ガード。「呼んだ」の印で 2 回目を防ぐ |
| **新**: `_free` の後、セッションのコールバックは呼ばれない | 7.5.2 | 生存フラグと、ほかのスレッドの呼び出し中の件数を待つこと |
| **新**: 同期のシステムコードはスレッドごと、非同期は引数 | 7.3 | `thread_local` と完了の引数 |
| **新**: 例外は境界を越えない | 7.7 | すべての入口とコールバックの包みで捕まえる |

## 11. エラー

値はすべて C++ API の `enum class` と同じ。名前は `NTK_<機能>_ERROR_<名前>`。返す場面は C++ API の設計書 11.4 に従い、**C ABI だけが返す場面**を最後の列に書く。

### 11.1 `ntk_dialog_error`

| 値 | 名前 | C ABI だけが返す場面 |
|---|---|---|
| 0 | `NONE` | - |
| 1 | `INVALID_PARAMETER` | 出力引数が `NULL`、`struct_size` が小さすぎる、`reserved` が 0 でない、不正な UTF-8、範囲外の列挙の値、`filters == NULL` かつ `filter_count > 0` |
| 2 | `CANCELED` | - |
| 3 | `BUFFER_TOO_SMALL` | 欠番。返さない（E-10） |
| 4 | `SYSTEM_ERROR` | - |
| 5 | `UNKNOWN` | 捕まえた例外（7.7） |

構造体の知らない部分が 0 でないとき（7.8 の 4）は、Dialog には `NOT_SUPPORTED` が無いので `INVALID_PARAMETER` を返す。

### 11.2 `ntk_notification_error`

| 値 | 名前 | C ABI だけが返す場面 |
|---|---|---|
| 0 | `NONE` | - |
| 1 | `NOT_INITIALIZED` | - |
| 2 | `DISABLED` | - |
| 3 | `INVALID_PAYLOAD` | 欠番。返さない（E-10） |
| 4 | `PROGRESS_NOT_FOUND` | - |
| 5 | `HRESULT_FAILURE` | 捕まえた例外（7.7） |
| 6 | `BADGE_FAILED` | - |
| 7 | `INVALID_PARAMETER` | ハンドルや出力引数が `NULL`、`struct_size` が小さすぎる、`reserved` が 0 でない、不正な UTF-8、範囲外の添字や列挙の値、必須の文字列の `NULL` |
| 8 | `NOT_SUPPORTED` | 構造体の知らない部分が 0 でない（7.8） |

### 11.3 `ntk_clipboard_error`

| 値 | 名前 | C ABI だけが返す場面 |
|---|---|---|
| 0 | `NONE` | - |
| 1 | `INVALID_PARAMETER` | ハンドルや出力引数が `NULL`、`struct_size` が小さすぎる、`reserved` が 0 でない、不正な UTF-8、未知の書き込みのビット、`data == NULL` かつ `size > 0`、コールバックの `NULL`、`render_target_set` の 2 回目 |
| 2 | `NOT_INITIALIZED` | - |
| 3 | `BUSY` | - |
| 4 | `EMPTY` | - |
| 5 | `FORMAT_UNAVAILABLE` | - |
| 6 | `INVALID_DATA` | - |
| 7 | `BUFFER_TOO_SMALL` | 欠番。返さない（E-10） |
| 8 | `OUT_OF_MEMORY` | 捕まえた `std::bad_alloc` |
| 9 | `ACCESS_DENIED` | - |
| 10 | `HISTORY_DISABLED` | - |
| 11 | `ITEM_DELETED` | - |
| 12 | `MONITOR_REGISTER_FAILED` | - |
| 13 | `PARTIAL_STATE` | - |
| 14 | `WRONG_THREAD` | - |
| 15 | `CANCELED` | - |
| 16 | `NOT_SUPPORTED` | 構造体の知らない部分が 0 でない（7.8） |
| 17 | `NOT_FOREGROUND` | - |
| 18 | `WRONG_APARTMENT` | - |
| 19 | `UNKNOWN` | 捕まえた例外 |

`NULL` のハンドルは `INVALID_PARAMETER` を返す（閉じたハンドルの `NOT_INITIALIZED` と区別する）。

## 12. テスト設計

### 12.1 単体テスト（`WindowsLibraryCApiTest/`）

C ABI のテストは、C++ API のテスト（`WindowsLibraryTest`）とは別のプロジェクトに置く。成果物とテストプロジェクトを 1 対 1 にし、T-12 で今の C ABI のテストを消すときに取り違えないためである。

C ABI の `.cpp` はテストプロジェクトに直接コンパイルし、内部の部品（ハンドル、構造体の読み方、`CallbackGate`、変換）も単独で確かめる。Core は C ABI の DLL と同じく、静的ライブラリを `ProjectReference` と `NativeToolkit.WindowsLibraryCore.props` で取り込む。C++ API のテストと同じ偽物（`StoringClipboard`、偽の通知 backend、STA の harness）を使うときは、その差し込み口（`*Internal.h` の `...ForTest`）が Core の `.lib` に入っているので、include パスに `..\WindowsLibrary\src` を足して使う（T-05 以降）。

| ID | 確かめること | 方法 |
|---|---|---|
| CT-01 | 公開ヘッダーが C としてコンパイルできる | `.c` の翻訳単位で 4 つのヘッダーをそれぞれ単独に include し、`/TC /W4 /WX` でコンパイルする。PCH を使わない |
| CT-02 | 公開ヘッダーが C++ として単独でコンパイルでき、`<windows.h>` と一緒でも衝突しない。全ヘッダーを 2 回ずつ include してよい | C++ API の U-D と同じ。C++ から呼んだ関数が C のリンケージであることは CT-21 で確かめる |
| CT-03 | 公開ヘッダーが ASCII だけ | 機械照合（T-11） |
| CT-04 | 構造体の配置が付録 A どおり。`#pragma pack(1)` の下で include しても同じ | `static_assert(offsetof(...))` と `sizeof` を x64 の値で固定する |
| CT-05 | **エラーを返す関数**で、必須のハンドルと必須の出力引数の `NULL` が `INVALID_PARAMETER` になり、落ちない。ハンドルの出力は失敗でも `NULL` になる。失敗しない関数と省略できる出力（`out_size`、`out_request_id`、`out_index`）は CT-09 | 表で該当の関数を回す。機能ごとのタスクで行う |
| CT-06 | 不正な UTF-8、未知のビット、範囲外の添字と列挙、必須の文字列の `NULL`、履歴のコールバックの `NULL` が `INVALID_PARAMETER`。省略できない素の文字列の `NULL` が `""` | 同上。機能ごとのタスクで行う |
| CT-07 | 構造体の版（7.8）: 小さすぎる、上限（4096）を超える、`reserved` が 0 でない、2.0.0 と同じ大きさ、知らない部分が 0 の大きい構造体、知らない部分が 0 でない大きい構造体。**新しい DLL が古い大きさを受け付けること**は、共通の読み取り関数に項目を足した仮の構造体（2.1 の想定）を与え、2.0.0 の大きさを渡すと足した項目が既定値になることで確かめる | 読み取り関数は T-02、各構造体は機能ごとのタスクで |
| CT-08 | `ntk_last_system_code()` が失敗で書かれ、成功で 0 になり、スレッドごとに独立している。完了は値を書かず、引数で渡す | 2 スレッドで交互に失敗させる |
| CT-09 | `_free(NULL)` が何もしない。読み取りの範囲外は `NULL` / 0。**空のバイト列で `size == 0` かつ `data != NULL`**。`out_size`、`out_request_id`、`out_index` が `NULL` でもよい。失敗しない関数がシステムコードを変えない | 全ハンドルの型で |
| CT-10 | Clipboard の読み書きが往復する（テキスト、HTML、ファイル、DIB、独自形式、複数形式、UTF-8 の多言語、対になっていないサロゲートの置き換え） | 偽のクリップボードで、C ABI で書いて C ABI で読む。C++ API で読んだ結果とも比べる |
| CT-11 | 通知の内容のビルダーが C++ の `NotificationContent` と同じペイロードを作る。「無い」と「在るが空」の区別を含む | 同じ内容を C++ と C ABI で作り、**`NotificationContent` を項目ごとに比べる**（違う項目の名前を出す）。ペイロードは `NotificationContent` だけから作られ、その変換は C++ API のテストが受け持つので、内容が同じならペイロードも同じになる。`BuildPayload` は C++ のマネージャーの非公開の関数で、WinRT の投影ヘッダーが要り、C ABI のテストプロジェクトからは呼べない（T-06 で方法を変えた）。入力一覧 §1.10 の 14 行を、`""` と `NULL` の両方で網羅する |
| CT-12 | 履歴の要求: `user_data` が届く。受付後ちょうど 1 回、受付前の失敗では 0 回。完了のスレッドがオーナー。システムコードが引数で届く。availability の失敗時は 0。全 5 操作 | C++ API の C-1〜C-4 と同じ偽 backend |
| CT-13 | provider の `release` がちょうど 1 回。形式が 2 つ以上の予約、次の予約（`EmptyClipboard` に達した時点）、このセッションの書き込みと消去（オーナーと別のスレッドから）、ほかのアプリの消去、復旧、入口の検査での拒否、`PARTIAL_STATE`（保持され、後で呼ばれる）、**close の成功（戻る前に呼ばれ、以後は呼ばれない）**、`_free` のそれぞれ。close の中で provider が呼ばれうること。`render_target_set` の約束 | 呼び出しとスレッドを記録する |
| CT-14 | 例外が境界を越えない | 例外を投げる偽物を差し込み、エラーが返ることを確かめる |
| CT-15 | Dialog の要求の変換。0 で埋めた構造体と `NULL` の要求が C++ の既定と一致する（E-9）。`;` 区切りのパターンが分かれる | 変換関数を直接呼ぶ。ダイアログは出さない |
| CT-16 | セッションのライフサイクル。閉じた後の操作が `NOT_INITIALIZED`。2 回目の `create` の返し分け | C++ API の C-5〜C-8 と同じ harness |
| CT-17 | セッションの `_free`（放棄）の後、変化、履歴のハンドラ、履歴の完了、provider のどれも呼ばれない。provider の `release` は `_free` の中で 1 回だけ呼ばれる。**同じスレッドで入れ子になったコールバック（コールバックの中の書き込み、モーダルなループ）で止まらない**。ほかのスレッドの呼び出しの最中の `_free` は、それが戻るまで待つ | 生存フラグの検査。放棄の後にイベントを送る。入れ子と別スレッドの場面を作る |
| CT-18 | 通知の `release`: 配送中（C++ がハンドラをコピーした後、呼ぶ前を含む）に close と差し替えをしても、最後の配送が戻った後にちょうど 1 回呼ばれる。配送中が無ければ close のスレッドで呼ばれる。**失敗の経路**（`manager_create` の入口の検査と `NOT_SUPPORTED`、閉じたマネージャーへの `set_invoked_handler`）でも戻る前に 1 回呼ばれる | C++ の配送に「コピーの後、呼ぶ前」で止める差し込み口を足し、競合を決定的に作る |
| CT-19 | Runtime とマネージャーの順序: マネージャーが生きている間の `runtime_free` は Shutdown を呼ばず、最後の close で呼ぶ。逆の順序でも正しく呼ぶ。2 回目の `runtime_initialize` は `NOT_SUPPORTED` | C ABI の Runtime の包みに Shutdown の関数の差し込み口を置き、差し替えて数える |
| CT-20 | 履歴の timestamp の変換（WinRT の tick → Unix ミリ秒）。既知の値で。0（読めなかった）は 0 | 1970-01-01、2026-01-01、0 の tick |

- 今の C ABI のテスト（`ClipboardBridgeTest`、`NotificationBridgeTest`、`NotificationPayloadTest`）は今の C ABI とともに削除する。C++ API のテスト（約 260 件）はそのまま通る。E-10 で消す項目を使うテストだけを直す
- テストプロジェクトは Core の `.lib` をリンクするので、Core のソースを個別に足さない（Bootstrap の DLL はテストの隣に複製する）。OS に触れる部分は差し込み口で差し替える
  - Runtime の Bootstrap: C ABI の `SetRuntimeHooksForTest`（CT-19）
  - `Manager::Create`（OS への登録）: C ABI の `SetManagerFactoryForTest`。テストは C++ の `Detail::TestAccess::MakeManager` の上の工場を渡す
  - 活性化の配送: C++ の `TestAccess::Activate`。配送の「ハンドラのコピーの後、呼ぶ前」で止める `TestAccess::SetAfterHandlerCopy`（CT-18）
  - 生きているテスト用のマネージャーの操作は OS に届くので、Notification の操作は入口の検査と閉じたマネージャーの経路で確かめる。成功の経路は C++ API のテストと CT-21 が受け持つ
  - Clipboard: C++ API のテストの `StoringClipboard` と履歴の backend の差し込み口（`WindowsLibraryTest/Support/ClipboardSessionForTest.h`、`SetHistoryBackendFactoryForTest`）を、include パスの最後に置いた `..\WindowsLibraryTest` から使う。各テストは STA のオーナースレッドで C ABI のセッションを作り、終わりに `ClipboardTestAccess::ResetProcessState` で放棄の記録も戻す
  - クリップボードの変化の通知: テストがセッションの隠しウィンドウ（偽のクリップボードを最後に開いたウィンドウ）へ `WM_CLIPBOARDUPDATE` を送って起こす

### 12.2 実際の DLL を通す確認

| ID | 確かめること | 方法 |
|---|---|---|
| CT-21 | 公開ヘッダーと import ライブラリだけで組んだ C の実行ファイルと C++ の実行ファイルが、実際の DLL で動く（C++ はリンケージの確認のため） | `WindowsLibraryCApiSmoke`（C、`/TC`）が次を行う。`ntk_version` がヘッダーの `NTK_VERSION` と一致する。`ntk_string` などの出力を得て解放する。構造体の入力を渡す。Clipboard のセッションを STA で作り、テキストを往復させ、履歴の可否の完了を 1 回受け取って close する（前面でないときは `NOT_FOREGROUND` の完了で可）。Dialog と通知は UI を出さない関数だけ |

### 12.3 機械照合（T-11）

| 照合 | 両辺 |
|---|---|
| 公開する関数の集合 | `.def` の EXPORTS ↔ ヘッダーの宣言 ↔ 8.2 の表 ↔ 付録 A。件数 105 |
| シグネチャ | ヘッダーの宣言 ↔ 付録 A。戻り値、引数の型と順、`NTK_CALL`、コールバックの型、構造体の項目と順 |
| OP の対応 | 8.1 の 47 行 ↔ 9 章の 47 行 ↔ C++ API の設計書 8.1 |
| エラーと列挙の値 | C ABI の無名 `enum` の値 ↔ C++ API の `enum class` ↔ 11 章の表 |
| 名前の規則 | ヘッダーの全関数が 1.1 の形 |
| ASCII | 公開ヘッダー |

- 読むべきファイルが無いときは、skip ではなく失敗にする（R-30）
- `dumpbin /exports` の結果が `.def` と一致することを、ビルドの後に確かめる（T-16）

### 12.4 UI テストと computer use

- サンプルは段階 4 で C++ API に移ったので、**UI テストは C ABI を通らない**。C ABI の振る舞いは 12.1 と 12.2 で確かめる
- UI テストは、E-10 の整理と E-13 の Dialog の修正で C++ API が壊れていないことを確かめるために全件流す。E-13 のために Dialog の UI テストを足す（ファイルのダイアログのタイトル、保存の上書きの確認）
- P/Invoke を通した確認は `unity-native-plugin` で行う（サンプルは VC++ でネイティブの振る舞いを確かめ、Unity からの呼び出しは別リポジトリで確かめる分担）
- E-19 で、サンプルの「Request + Immediate Uninitialize」は失敗しなくなる。サンプルはこのボタンを「取り消した要求の完了が close の中で届く」例に変え、そのテストを書き換える。「Shutting down」の状態を使う UI テスト 5 件は、サンプルから close を確実に失敗させる手段が無くなるので削除する（close の失敗は C-5〜C-8、CT-22 が確かめる。サンプルのガードのコードは残す。T-17）
- computer use は、この段階では新しく行わない

### 12.5 C++ の修正のテスト

| ID | 確かめること | 方法 |
|---|---|---|
| CT-22 | E-19: 処理中の履歴の要求があるとき、ループを回さずに close が成功し、取り消した要求の完了が close の中でちょうど 1 回届く。ほかのスレッドの読み書きの最中は `BUSY` | C++ API の C-5 の harness。ポンプを回さずに close を呼ぶ |
| CT-23 | E-20: オーナー以外のスレッドからの `SetHistoryHandlers` は `WrongThread` で、ハンドラは差し替わらない。解除の失敗（`MonitorRegisterFailed`）の後も古いハンドラが呼ばれる | 偽の backend で `StopWatch` を失敗させる |

## 13. 実装タスク分解

合計見積: 約 18.5 日

| ID | 内容 | 見積 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T-01 | `windows/WindowsLibraryCApi/` を作る（`.vcxproj`、`.filters`、空の `.def`、Core への参照、各 `.sln` への登録）。`UnityWindowsPlugin` を削除する | 1.0日 | 無し | 空の DLL がビルドでき、`UnityWindowsPlugin` がどの `.sln` にも無い | 依存の向きが CApi → Core だけか |
| T-02 | `Common.h` と共通の実装（ハンドル、`ntk_last_system_code`、`ntk_version`、UTF-8 の変換と U+FFFD、例外の捕捉、構造体の共通の読み取り関数、解放ガード、生存フラグと呼び出し中の件数）。CT-01〜CT-04、CT-08、CT-09、CT-07 の読み取り関数の部分 | 1.5日 | T-01 | 挙げたテストが通る | 7.8 の規則が 1 つの関数にまとまっているか。解放ガードの印 |
| T-03 | C++ の Dialog の修正（E-13）: `WindowsDialogWin32.h` の `Show*Dialog` が `owner`、`title`、フラグを受け取り、`fileMustExist`、`overwritePrompt` を Win32 に渡す。Dialog の UI テストを足す | 1.0日 | 無し | 4 項目が効く。Dialog の UI テストが通る | C++ の既定の振る舞いが変わっていないか |
| T-04 | `Dialog.h` と OP-01〜OP-06。CT-15 と、Dialog の CT-05、CT-06、CT-07、CT-14 | 1.0日 | T-02, T-03 | 6 関数が動く。挙げたテストが通る | E-9 の反転。フィルターの組 |
| T-05 | `Notification.h` のランタイム（参照を数える、Shutdown の差し込み口、2 回目の拒否）、マネージャー（解放ガードと `release` の共通の規則）、一覧、活性化と、OP-07〜OP-09、OP-12〜OP-20。CT-18、CT-19 と、Notification の CT-05、CT-06、CT-07、CT-14 | 1.5日 | T-02 | 12 操作が動く。挙げたテストが通る | `release` のスレッドと回数。C++ のロックの中で呼んでいないか |
| T-06 | 通知の内容のビルダーと OP-10、OP-11。CT-11 | 1.5日 | T-05 | CT-11 が入力一覧 §1.10 の 14 行を網羅して通る | `NULL` と `""` の区別 |
| T-07 | Clipboard のセッション（生存フラグ）、履歴のハンドラ、読み書き（OP-21〜OP-34、OP-36〜OP-39）。CT-16 と、Clipboard の CT-05、CT-06、CT-07、CT-14 | 1.5日 | T-02, T-17 | 挙げた操作が動く。挙げたテストが通る | コールバックの間にロックを持っていないか |
| T-08 | 複数形式のビルダー（OP-35）と遅延レンダリング（OP-40、OP-41）。CT-10、CT-13 | 1.0日 | T-07 | CT-10、CT-13 が通る | 解放ガードの印と、close / `_free` で呼ぶこと |
| T-09 | 履歴の要求（OP-42〜OP-47）と履歴のハンドル。CT-12、CT-17、CT-20 | 1.5日 | T-07, T-08 | 挙げたテストが通る | 完了のスレッド、回数、システムコード。放棄の後に呼ばれないこと |
| T-10 | `WindowsLibraryCApiSmoke`（C と C++）。CT-21 | 0.5日 | T-04, T-06, T-09 | 実際の DLL で通る | 公開ヘッダーと import ライブラリだけで組んでいるか |
| T-11 | 機械照合（12.3）を `scripts/` に足し、壊すと落ちることを確かめる。`check_cpp_api_contract.py` の付け替え（8.5 の表の T-11 の行） | 1.0日 | T-04, T-06, T-09 | 照合が通る。壊した入力で落ちる。ファイルが無ければ失敗する | 両辺をソースから導出しているか |
| T-12 | 今の C ABI を削除する。定数と typedef を `*Codes.h` へ移し、旧ヘッダー 4 つ、`src/Bridge/`、旧 DLL、旧 C ABI のテスト 3 群を消す。`CommonInternal.h` の `extern "C"` を外す。E-10 の整理。照合の定数の出どころを付け替える（8.5 の表の T-12 の行） | 1.5日 | T-11 | 単体テストと照合が通る。Core に `extern "C"` の関数宣言が無い | 移した定数の値が変わっていないか。消した項目の参照が残っていないか |
| T-13 | ビルドスクリプトと配布物（対象、名前 `windows-native-toolkit-capi`、版 2.0.0、ヘッダーの配置）。README 6 の `UnityWindowsPlugin` の運用の参照（プロジェクト、ソリューション、スクリプト、現行の README とルール）を直す | 1.0日 | T-12 | スクリプトが DLL とヘッダーを出力する。運用の参照が 0 件 | 配布物の名前と版 |
| T-14 | `windows.md` の修正（5.2）。公開ヘッダーの Doxygen（スレッド、寿命、`user_data` の期間、借りたポインタ、エラー、`release` の共通の規則）。C++ の公開ヘッダーの Doxygen のうち旧 C ABI に触れるものと、E-19 で変わる close の説明を直す | 1.0日 | T-12 | 5.2 の 6 か所が直っている。全公開宣言にコメントがある | 1.3 と 7.3〜7.5 がヘッダーに書かれているか |
| T-15 | 8.3 の対応表をヘッダーと突き合わせ、`unity-native-plugin` への申し送りを結果文書に書く（1.3.4 の Unity の手順、登録ごとの `GCHandle`、`LPUTF8Str` に頼らず `IntPtr` と手作業の UTF-8 変換、Go の `cgo.Handle` は `C.malloc` した領域に置いてその番地を渡す、bindgen の対象） | 0.5日 | T-13 | 52 関数すべてに行がある | 振る舞いの差が漏れていないか |
| T-16 | 回帰の確認: 単体テスト、`scripts/test_windows.ps1`（全件）、`dumpbin /exports` と `.def` の一致 | 0.5日 | T-10, T-14, T-15 | すべて通る。export が 105 | baseline との差が意図どおりか |
| T-17 | C++ の Clipboard の修正: close が自分の隠しウィンドウ宛てのメッセージを処理する（E-19。`PeekMessageW` をそのウィンドウに絞って使う）、`SetHistoryHandlers` の順序（E-20）。サンプルの「Request + Immediate Uninitialize」のテストの書き換えと、「Shutting down」を使う UI テスト 5 件の削除（12.4）。CT-22、CT-23 | 1.0日 | 無し | CT-22、CT-23 と C++ API の既存のテストが通る。Clipboard の UI テストが通る | 取り消した要求の完了がちょうど 1 回か。close の中で他のウィンドウのメッセージを処理していないか |

### 13.1 先行と後続

- 先行: T-01、T-02、T-03、T-17（T-03 と T-17 は C++ の修正で、T-01 と並行できる）
- 機能ごとに独立: Dialog（T-04）、Notification（T-05、T-06）、Clipboard（T-07〜T-09）
- 後続: T-10〜T-16
- 今の C ABI の削除（T-12）は、新しい C ABI が揃い、照合が通ってから行う

## 14. リスクと緩和策

| ID | リスク | 影響 | 緩和策 |
|---|---|---|---|
| RK-01 | `unity-native-plugin` が 2.0.0 で壊れる | Unity の利用者が更新できない | 2.0.0 で一度に切り替える（D-4）。今の DLL は `dist/1.11.0/` に残る。8.3 の対応表と申し送りを出す |
| RK-02 | バインディングが構造体の配置や真偽値の大きさを読み違える | 実行時の不正なメモリアクセス | 真偽値を `int32_t` にする（E-8）。詰め物を明示する（E-9）。CT-04 で配置を固定する。構造体は入力だけに使う |
| RK-03 | 利用者が `user_data` を早く解放する | 解放後のアクセス | 期間を 7.5 と Doxygen に書く。期間の終わりが分からないもの（provider、通知）には `release` を付ける。セッションは生存フラグで `_free` の後を止める |
| RK-04 | 借りたポインタを期間の後に使う | 解放後のアクセス | 読み取り関数の Doxygen に期間を書く。コールバックに渡すハンドルは `const` にする |
| RK-05 | 同期のシステムコードを、間に別の呼び出しを挟んでから読む | 違う失敗の値を読む | 7.3 に「失敗の直後に、同じスレッドで読む」と書く。非同期は引数で渡す（E-18） |
| RK-06 | 公開関数が 105 に増え、手で書くバインディングの負担が増える | 利用者の手間 | 名前の規則（1.1）をそろえ、自動生成に向いた形にする。対応表を出す |
| RK-07 | UI テストが C ABI を通らない | C ABI の退行に気づかない | CT-01〜CT-20 で全関数を通し、CT-21 で実際の DLL を通す。P/Invoke は `unity-native-plugin` で確かめる |
| RK-08 | 閉じていないセッションを `_free` する利用者が出る（C# の `SafeHandle` のファイナライザなど） | クリップボードの機能がそのプロセスで使えなくなる | 生存フラグで落ちないようにする。E-1 と 1.3.4 に正しい後始末を書く。Debug の DLL では assert する |
| RK-09 | コンソールのプログラムから履歴や遅延レンダリングを使おうとする | 完了が来ない | 1.3 で「成立しない使い方」として示し、最小のメッセージループの手順を書く |
| RK-10 | E-10 と E-13 で C++ API の利用者（サンプル）が壊れる | 段階 4 の成果の退行 | サンプルは `extraFlags` と `unknownKeys` を使っていない。UI テストを全件流し、Dialog の UI テストを足す |
| RK-11 | Unity Editor のドメインリロードでハンドルを失う | Editor が落ちる、または以後セッションを作れない | 1.3.4 の手順を申し送る。生存フラグで落ちるところまでは行かないようにする |
| RK-12 | 通知の活性化が、利用者のドメインや GC の外のスレッドで来る | C# のコールバックが落ちる | 1.3.1 に書く。C# では `MonoPInvokeCallback` の静的メソッドと `GCHandle` で受け、`release` で `GCHandle` を解放する例を申し送りに入れる |
| RK-13 | E-19 で close の振る舞いが変わり、`CANCELED` の再試行に頼るコードやテストが変わる | サンプルと UI テストの退行 | C++ の利用者の再試行のループはそのまま動く（`CANCELED` が返らなくなるだけ）。サンプルのテストは T-17 で書き換え、close の失敗に頼る UI テスト 5 件は削除する。close の失敗は CT-22 と C-5〜C-8 で確かめる |
| RK-14 | コールバックが同じスレッドで入れ子になる | 利用者のコードの再入の不具合 | 1.3.5 に書く。ライブラリ側は 7.5.2 で止まらないようにし、CT-17 で確かめる |

## 15. Definition of Done

### 15.1 機能

- [ ] `windows/WindowsLibraryCApi/` があり、`WindowsLibraryCore` だけに依存する
- [ ] 8.2 の 105 関数が `.def`、ヘッダー、付録 A、実装にあり、`dumpbin /exports` と一致する
- [ ] 8.1 の 47 操作すべてに C 関数があり、9 章の表と操作の集合が一致する
- [ ] 公開ヘッダーが C と C++ の両方でコンパイルでき、`<windows.h>` を include せず、ASCII だけである
- [ ] エラーと列挙の値が C++ API と一致する
- [ ] 今の C ABI（DLL、`src/Bridge/`、ヘッダー 4 つ）と `UnityWindowsPlugin` が無く、Core に `extern "C"` の関数宣言が無い
- [ ] E-10 の整理、E-13 の Dialog の修正、E-19 と E-20 の Clipboard の修正が済んでいる

### 15.2 品質

- [ ] CT-01〜CT-23 が通る
- [ ] C++ API の単体テストと `scripts/test_windows.ps1`（全件）が通る。Dialog の UI テストを足し、E-19 に合わせて Clipboard の UI テストを書き換え・削除した
- [ ] 機械照合（12.3）が通り、壊すと落ちること、ファイルが無いと失敗することを確かめてある
- [ ] 公開ヘッダーの全宣言に Doxygen があり、スレッド、寿命、`user_data` の期間、借りたポインタの期間、`release` の規則、エラーが書かれている

### 15.3 構成と文書

- [ ] ビルドスクリプトが `windows-native-toolkit-capi` の 2.0.0 を出力する
- [ ] `windows.md` の 5.2 の 6 か所と、C++ の公開ヘッダーの旧 C ABI に触れる Doxygen が直っている
- [ ] `UnityWindowsPlugin` の運用の参照（プロジェクト、ソリューション、ビルドスクリプト、現行の README とルール）が 0 件。履歴を書いた文書（`artifact/`）は対象外
- [ ] 8.3 の対応表が 52 関数すべてを含み、結果文書に `unity-native-plugin` への申し送り（1.3.4 を含む）がある

## 付録 A. 公開ヘッダーの宣言

T-11 の機械照合はこの付録とヘッダーを突き合わせる。コメントは Doxygen の下書きで、実装ではヘッダーに `@brief` などを付けて書き直す。

### A.1 `NativeToolkitC/Common.h`

```c
#ifndef NATIVETOOLKITC_COMMON_H
#define NATIVETOOLKITC_COMMON_H

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
#define NTK_VERSION 0x020000   /* (MAJOR << 16) | (MINOR << 8) | PATCH; checked by T-11 */

/* ntk_last_system_code() after an out-of-memory failure the C ABI caught. */
#define NTK_SYSTEM_CODE_E_OUTOFMEMORY 0x8007000E

typedef void (NTK_CALL *ntk_release_fn)(void* user_data);

uint32_t NTK_CALL ntk_version(void);
uint32_t NTK_CALL ntk_last_system_code(void);

typedef struct ntk_string ntk_string;
const char* NTK_CALL ntk_string_data(const ntk_string* s);
size_t      NTK_CALL ntk_string_size(const ntk_string* s);
void        NTK_CALL ntk_string_free(ntk_string* s);

typedef struct ntk_bytes ntk_bytes;
const uint8_t* NTK_CALL ntk_bytes_data(const ntk_bytes* b);   /* never NULL for a valid handle */
size_t         NTK_CALL ntk_bytes_size(const ntk_bytes* b);
void           NTK_CALL ntk_bytes_free(ntk_bytes* b);

typedef struct ntk_string_list ntk_string_list;
size_t      NTK_CALL ntk_string_list_count(const ntk_string_list* list);
const char* NTK_CALL ntk_string_list_at(const ntk_string_list* list, size_t index, size_t* out_size);
void        NTK_CALL ntk_string_list_free(ntk_string_list* list);

#ifdef __cplusplus
}
#endif
#endif
```

### A.2 `NativeToolkitC/Dialog.h`

```c
#ifndef NATIVETOOLKITC_DIALOG_H
#define NATIVETOOLKITC_DIALOG_H

#include "NativeToolkitC/Common.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

typedef int32_t ntk_dialog_error;
enum {
    NTK_DIALOG_ERROR_NONE = 0,
    NTK_DIALOG_ERROR_INVALID_PARAMETER = 1,
    NTK_DIALOG_ERROR_CANCELED = 2,
    NTK_DIALOG_ERROR_BUFFER_TOO_SMALL = 3,   /* reserved, never returned */
    NTK_DIALOG_ERROR_SYSTEM_ERROR = 4,
    NTK_DIALOG_ERROR_UNKNOWN = 5
};

typedef int32_t ntk_dialog_alert_buttons;
enum {
    NTK_DIALOG_ALERT_BUTTONS_OK = 0,
    NTK_DIALOG_ALERT_BUTTONS_OK_CANCEL = 1,
    NTK_DIALOG_ALERT_BUTTONS_YES_NO = 2,
    NTK_DIALOG_ALERT_BUTTONS_YES_NO_CANCEL = 3,
    NTK_DIALOG_ALERT_BUTTONS_RETRY_CANCEL = 4,
    NTK_DIALOG_ALERT_BUTTONS_ABORT_RETRY_IGNORE = 5,
    NTK_DIALOG_ALERT_BUTTONS_CANCEL_TRY_CONTINUE = 6
};

typedef int32_t ntk_dialog_alert_icon;
enum {
    NTK_DIALOG_ALERT_ICON_NONE = 0,
    NTK_DIALOG_ALERT_ICON_INFORMATION = 1,
    NTK_DIALOG_ALERT_ICON_WARNING = 2,
    NTK_DIALOG_ALERT_ICON_ERROR = 3,
    NTK_DIALOG_ALERT_ICON_QUESTION = 4
};

typedef int32_t ntk_dialog_alert_default_button;
enum {
    NTK_DIALOG_ALERT_DEFAULT_BUTTON_FIRST = 0,
    NTK_DIALOG_ALERT_DEFAULT_BUTTON_SECOND = 1,
    NTK_DIALOG_ALERT_DEFAULT_BUTTON_THIRD = 2,
    NTK_DIALOG_ALERT_DEFAULT_BUTTON_FOURTH = 3
};

typedef int32_t ntk_dialog_alert_result;
enum {
    NTK_DIALOG_ALERT_RESULT_OK = 0,
    NTK_DIALOG_ALERT_RESULT_CANCEL = 1,
    NTK_DIALOG_ALERT_RESULT_YES = 2,
    NTK_DIALOG_ALERT_RESULT_NO = 3,
    NTK_DIALOG_ALERT_RESULT_RETRY = 4,
    NTK_DIALOG_ALERT_RESULT_ABORT = 5,
    NTK_DIALOG_ALERT_RESULT_IGNORE = 6,
    NTK_DIALOG_ALERT_RESULT_TRY_AGAIN = 7,
    NTK_DIALOG_ALERT_RESULT_CONTINUE = 8,
    NTK_DIALOG_ALERT_RESULT_CLOSE = 9,
    NTK_DIALOG_ALERT_RESULT_HELP = 10
};

/* Frozen: never extended. */
typedef struct ntk_dialog_filter {
    const char* name;       /* e.g. "Text files"; NULL is "" */
    const char* patterns;   /* e.g. "*.txt;*.log"; required */
} ntk_dialog_filter;

typedef struct ntk_dialog_alert_request {      /* sizeof 56 */
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;                         /* NULL is "" */
    const char* message;                       /* NULL is "" */
    ntk_dialog_alert_buttons        buttons;
    ntk_dialog_alert_icon           icon;
    ntk_dialog_alert_default_button default_button;
    int32_t     top_most;
    int32_t     show_help_button;
    uint32_t    reserved1;
    void*       owner;                         /* HWND or NULL */
} ntk_dialog_alert_request;

typedef struct ntk_dialog_file_request {       /* sizeof 32 */
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;                         /* NULL: the system title */
    int32_t     allow_missing_file;            /* C++ fileMustExist = !allow_missing_file */
    uint32_t    reserved1;
    void*       owner;
} ntk_dialog_file_request;

typedef struct ntk_dialog_save_file_request {  /* sizeof 40 */
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* default_extension;             /* NULL or "": none */
    int32_t     skip_overwrite_prompt;         /* C++ overwritePrompt = !skip_overwrite_prompt */
    uint32_t    reserved1;
    void*       owner;
} ntk_dialog_save_file_request;

typedef struct ntk_dialog_folder_request {     /* sizeof 24 */
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    void*       owner;
} ntk_dialog_folder_request;

/* A NULL request means all defaults. */
ntk_dialog_error NTK_CALL ntk_dialog_show_alert(
    const ntk_dialog_alert_request* request, ntk_dialog_alert_result* out_result);
ntk_dialog_error NTK_CALL ntk_dialog_show_open_file(
    const ntk_dialog_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string** out_path);
ntk_dialog_error NTK_CALL ntk_dialog_show_open_files(
    const ntk_dialog_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string_list** out_paths);
ntk_dialog_error NTK_CALL ntk_dialog_show_save_file(
    const ntk_dialog_save_file_request* request, const ntk_dialog_filter* filters, size_t filter_count,
    ntk_string** out_path);
ntk_dialog_error NTK_CALL ntk_dialog_show_pick_folder(
    const ntk_dialog_folder_request* request, ntk_string** out_path);
ntk_dialog_error NTK_CALL ntk_dialog_show_pick_folders(
    const ntk_dialog_folder_request* request, ntk_string_list** out_paths);

#pragma pack(pop)

#ifdef __cplusplus
}
#endif
#endif
```

### A.3 `NativeToolkitC/Notification.h`

```c
#ifndef NATIVETOOLKITC_NOTIFICATION_H
#define NATIVETOOLKITC_NOTIFICATION_H

#include "NativeToolkitC/Common.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

typedef int32_t ntk_notification_error;
enum {
    NTK_NOTIFICATION_ERROR_NONE = 0,
    NTK_NOTIFICATION_ERROR_NOT_INITIALIZED = 1,
    NTK_NOTIFICATION_ERROR_DISABLED = 2,
    NTK_NOTIFICATION_ERROR_INVALID_PAYLOAD = 3,   /* reserved, never returned */
    NTK_NOTIFICATION_ERROR_PROGRESS_NOT_FOUND = 4,
    NTK_NOTIFICATION_ERROR_HRESULT_FAILURE = 5,
    NTK_NOTIFICATION_ERROR_BADGE_FAILED = 6,
    NTK_NOTIFICATION_ERROR_INVALID_PARAMETER = 7,
    NTK_NOTIFICATION_ERROR_NOT_SUPPORTED = 8
};

typedef int32_t ntk_notification_setting;
enum {
    NTK_NOTIFICATION_SETTING_ENABLED = 0,
    NTK_NOTIFICATION_SETTING_DISABLED_FOR_APPLICATION = 1,
    NTK_NOTIFICATION_SETTING_DISABLED_FOR_USER = 2,
    NTK_NOTIFICATION_SETTING_DISABLED_BY_GROUP_POLICY = 3,
    NTK_NOTIFICATION_SETTING_DISABLED_BY_MANIFEST = 4
};

typedef int32_t ntk_notification_scenario;
enum {
    NTK_NOTIFICATION_SCENARIO_DEFAULT = 0,
    NTK_NOTIFICATION_SCENARIO_REMINDER = 1,
    NTK_NOTIFICATION_SCENARIO_ALARM = 2,
    NTK_NOTIFICATION_SCENARIO_URGENT = 3,
    NTK_NOTIFICATION_SCENARIO_INCOMING_CALL = 4
};

typedef int32_t ntk_notification_audio_kind;
enum {
    NTK_NOTIFICATION_AUDIO_KIND_EVENT = 0,
    NTK_NOTIFICATION_AUDIO_KIND_MUTE = 1,
    NTK_NOTIFICATION_AUDIO_KIND_URI = 2
};

typedef int32_t ntk_notification_duration;
enum {
    NTK_NOTIFICATION_DURATION_SHORT = 0,
    NTK_NOTIFICATION_DURATION_LONG = 1
};

typedef int32_t ntk_notification_logo_crop;
enum {
    NTK_NOTIFICATION_LOGO_CROP_NONE = 0,
    NTK_NOTIFICATION_LOGO_CROP_CIRCLE = 1
};

typedef struct ntk_notification_runtime ntk_notification_runtime;
typedef struct ntk_notification_manager ntk_notification_manager;
typedef struct ntk_notification_content ntk_notification_content;
typedef struct ntk_notification_list ntk_notification_list;
typedef struct ntk_notification_activation ntk_notification_activation;

/* Runs on a thread the OS picks. The activation is valid only during the call. */
typedef void (NTK_CALL *ntk_notification_invoked_fn)(
    void* user_data, const ntk_notification_activation* activation);

typedef struct ntk_notification_manager_options {   /* sizeof 56 */
    uint32_t                    struct_size;
    uint32_t                    reserved0;
    ntk_notification_invoked_fn on_invoked;          /* NULL: activations are dropped */
    void*                       user_data;
    ntk_release_fn              release;             /* may be NULL; see 7.5.1 */
    int32_t                     is_unpackaged;       /* C++ isPackaged = !is_unpackaged */
    uint32_t                    reserved1;
    const char*                 display_name;        /* required when is_unpackaged */
    const char*                 icon_uri;            /* required when is_unpackaged */
} ntk_notification_manager_options;

typedef struct ntk_notification_progress_update {   /* sizeof 56 */
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* tag;                                 /* NULL is "" */
    const char* group;                               /* NULL is "" */
    double      value;
    const char* value_string;                        /* NULL is "" */
    const char* status;                              /* NULL is "" */
    uint32_t    sequence_number;
    uint32_t    reserved1;
} ntk_notification_progress_update;

/* Runtime (unpackaged apps only) */
ntk_notification_error NTK_CALL ntk_notification_runtime_initialize(
    uint32_t major_minor, ntk_notification_runtime** out_runtime);
void NTK_CALL ntk_notification_runtime_free(ntk_notification_runtime* runtime);

/* Manager */
ntk_notification_error NTK_CALL ntk_notification_manager_create(
    const ntk_notification_manager_options* options, ntk_notification_manager** out_manager);
ntk_notification_error NTK_CALL ntk_notification_manager_set_invoked_handler(
    ntk_notification_manager* manager, ntk_notification_invoked_fn on_invoked, void* user_data,
    ntk_release_fn release);
void NTK_CALL ntk_notification_manager_close(ntk_notification_manager* manager);
void NTK_CALL ntk_notification_manager_free(ntk_notification_manager* manager);

/* Operations */
ntk_notification_error NTK_CALL ntk_notification_show(
    ntk_notification_manager* manager, const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_schedule(
    ntk_notification_manager* manager, const ntk_notification_content* content, int64_t unix_ms);
ntk_notification_error NTK_CALL ntk_notification_cancel_scheduled(
    ntk_notification_manager* manager, const char* tag, const char* group);
ntk_notification_error NTK_CALL ntk_notification_update_progress(
    ntk_notification_manager* manager, const ntk_notification_progress_update* update);
ntk_notification_error NTK_CALL ntk_notification_set_badge(
    ntk_notification_manager* manager, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_remove_by_id(
    ntk_notification_manager* manager, uint32_t id);
ntk_notification_error NTK_CALL ntk_notification_remove_by_tag(
    ntk_notification_manager* manager, const char* tag, const char* group);
ntk_notification_error NTK_CALL ntk_notification_remove_all(ntk_notification_manager* manager);
ntk_notification_error NTK_CALL ntk_notification_get_all(
    ntk_notification_manager* manager, ntk_notification_list** out_list);
ntk_notification_error NTK_CALL ntk_notification_get_setting(
    ntk_notification_manager* manager, ntk_notification_setting* out_setting);
ntk_notification_error NTK_CALL ntk_notification_open_settings(ntk_notification_manager* manager);

/* List (output of get_all) */
size_t      NTK_CALL ntk_notification_list_count(const ntk_notification_list* list);
uint32_t    NTK_CALL ntk_notification_list_id_at(const ntk_notification_list* list, size_t index);
const char* NTK_CALL ntk_notification_list_tag_at(
    const ntk_notification_list* list, size_t index, size_t* out_size);
const char* NTK_CALL ntk_notification_list_group_at(
    const ntk_notification_list* list, size_t index, size_t* out_size);
void        NTK_CALL ntk_notification_list_free(ntk_notification_list* list);

/* Activation (argument of ntk_notification_invoked_fn) */
const char* NTK_CALL ntk_notification_activation_raw_arguments(
    const ntk_notification_activation* activation, size_t* out_size);
size_t      NTK_CALL ntk_notification_activation_value_count(
    const ntk_notification_activation* activation);
const char* NTK_CALL ntk_notification_activation_key_at(
    const ntk_notification_activation* activation, size_t index, size_t* out_size);
const char* NTK_CALL ntk_notification_activation_value_at(
    const ntk_notification_activation* activation, size_t index, size_t* out_size);

/* Content builder */
ntk_notification_error NTK_CALL ntk_notification_content_create(ntk_notification_content** out_content);
void NTK_CALL ntk_notification_content_free(ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_content_set_title(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_body(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_tag(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_group(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_scenario(
    ntk_notification_content* content, ntk_notification_scenario value);
ntk_notification_error NTK_CALL ntk_notification_content_set_hero_image(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_inline_image(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_app_logo(
    ntk_notification_content* content, const char* uri, ntk_notification_logo_crop crop);
ntk_notification_error NTK_CALL ntk_notification_content_set_attribution(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_duration(
    ntk_notification_content* content, ntk_notification_duration value);
ntk_notification_error NTK_CALL ntk_notification_content_set_audio(
    ntk_notification_content* content, ntk_notification_audio_kind kind, const char* event_name,
    const char* uri, int32_t loop);
ntk_notification_error NTK_CALL ntk_notification_content_add_button(
    ntk_notification_content* content, const char* label, const char* invoke_uri,
    int32_t with_arguments, size_t* out_index);
ntk_notification_error NTK_CALL ntk_notification_content_add_button_argument(
    ntk_notification_content* content, size_t button_index, const char* key, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_add_text_input(
    ntk_notification_content* content, const char* id, const char* placeholder, const char* title);
ntk_notification_error NTK_CALL ntk_notification_content_add_combo(
    ntk_notification_content* content, const char* id, const char* title,
    const char* default_selection, size_t* out_index);
ntk_notification_error NTK_CALL ntk_notification_content_add_combo_item(
    ntk_notification_content* content, size_t combo_index, const char* id, const char* label);
ntk_notification_error NTK_CALL ntk_notification_content_set_progress(
    ntk_notification_content* content, const char* title, double value,
    const char* value_string, const char* status);
ntk_notification_error NTK_CALL ntk_notification_content_set_timestamp(
    ntk_notification_content* content, int64_t unix_ms);
ntk_notification_error NTK_CALL ntk_notification_content_set_expiration(
    ntk_notification_content* content, int64_t seconds);
ntk_notification_error NTK_CALL ntk_notification_content_set_expires_on_reboot(
    ntk_notification_content* content, int32_t value);

#pragma pack(pop)

#ifdef __cplusplus
}
#endif
#endif
```

### A.4 `NativeToolkitC/Clipboard.h`

```c
#ifndef NATIVETOOLKITC_CLIPBOARD_H
#define NATIVETOOLKITC_CLIPBOARD_H

#include "NativeToolkitC/Common.h"

#ifdef __cplusplus
extern "C" {
#endif

#pragma pack(push, 8)

typedef int32_t ntk_clipboard_error;
enum {
    NTK_CLIPBOARD_ERROR_NONE = 0,
    NTK_CLIPBOARD_ERROR_INVALID_PARAMETER = 1,
    NTK_CLIPBOARD_ERROR_NOT_INITIALIZED = 2,
    NTK_CLIPBOARD_ERROR_BUSY = 3,
    NTK_CLIPBOARD_ERROR_EMPTY = 4,
    NTK_CLIPBOARD_ERROR_FORMAT_UNAVAILABLE = 5,
    NTK_CLIPBOARD_ERROR_INVALID_DATA = 6,
    NTK_CLIPBOARD_ERROR_BUFFER_TOO_SMALL = 7,     /* reserved, never returned */
    NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY = 8,
    NTK_CLIPBOARD_ERROR_ACCESS_DENIED = 9,
    NTK_CLIPBOARD_ERROR_HISTORY_DISABLED = 10,
    NTK_CLIPBOARD_ERROR_ITEM_DELETED = 11,
    NTK_CLIPBOARD_ERROR_MONITOR_REGISTER_FAILED = 12,
    NTK_CLIPBOARD_ERROR_PARTIAL_STATE = 13,
    NTK_CLIPBOARD_ERROR_WRONG_THREAD = 14,
    NTK_CLIPBOARD_ERROR_CANCELED = 15,
    NTK_CLIPBOARD_ERROR_NOT_SUPPORTED = 16,
    NTK_CLIPBOARD_ERROR_NOT_FOREGROUND = 17,
    NTK_CLIPBOARD_ERROR_WRONG_APARTMENT = 18,
    NTK_CLIPBOARD_ERROR_UNKNOWN = 19
};

enum {
    NTK_CLIPBOARD_WRITE_DEFAULT = 0,
    NTK_CLIPBOARD_WRITE_EXCLUDE_HISTORY = 1,
    NTK_CLIPBOARD_WRITE_EXCLUDE_ROAMING = 2,
    NTK_CLIPBOARD_WRITE_SENSITIVE = 3             /* both of the above */
};

typedef struct ntk_clipboard_session ntk_clipboard_session;
typedef struct ntk_clipboard_items ntk_clipboard_items;
typedef struct ntk_clipboard_history ntk_clipboard_history;
typedef struct ntk_clipboard_render_target ntk_clipboard_render_target;

typedef void (NTK_CALL *ntk_clipboard_changed_fn)(void* user_data);
typedef void (NTK_CALL *ntk_clipboard_history_changed_fn)(void* user_data);
typedef void (NTK_CALL *ntk_clipboard_flag_changed_fn)(void* user_data, int32_t enabled);

/* Owner thread. Call ntk_clipboard_render_target_set at most once, then return NONE. */
typedef ntk_clipboard_error (NTK_CALL *ntk_clipboard_render_fn)(
    void* user_data, const char* format_name, ntk_clipboard_render_target* target);

/* Owner thread, exactly once per accepted request. history is NULL on failure. */
typedef void (NTK_CALL *ntk_clipboard_history_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error, uint32_t system_code,
    const ntk_clipboard_history* history);
typedef void (NTK_CALL *ntk_clipboard_completion_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error, uint32_t system_code);
typedef void (NTK_CALL *ntk_clipboard_availability_fn)(
    void* user_data, uint32_t request_id, ntk_clipboard_error error, uint32_t system_code,
    int32_t history_enabled, int32_t roaming_enabled);   /* both 0 on failure */

typedef struct ntk_clipboard_session_options {     /* sizeof 24 */
    uint32_t                 struct_size;
    uint32_t                 reserved0;
    ntk_clipboard_changed_fn on_clipboard_changed;  /* NULL: no listener */
    void*                    user_data;
} ntk_clipboard_session_options;

typedef struct ntk_clipboard_history_handlers {     /* sizeof 40 */
    uint32_t                         struct_size;
    uint32_t                         reserved0;
    ntk_clipboard_history_changed_fn on_history_changed;
    ntk_clipboard_flag_changed_fn    on_history_enabled_changed;
    ntk_clipboard_flag_changed_fn    on_roaming_enabled_changed;
    void*                            user_data;     /* passed to all three */
} ntk_clipboard_history_handlers;

/* Session */
ntk_clipboard_error NTK_CALL ntk_clipboard_session_create(
    const ntk_clipboard_session_options* options, ntk_clipboard_session** out_session);
ntk_clipboard_error NTK_CALL ntk_clipboard_session_close(ntk_clipboard_session* session);
int32_t NTK_CALL ntk_clipboard_session_can_close(const ntk_clipboard_session* session);
void NTK_CALL ntk_clipboard_session_free(ntk_clipboard_session* session);
ntk_clipboard_error NTK_CALL ntk_clipboard_set_history_handlers(
    ntk_clipboard_session* session, const ntk_clipboard_history_handlers* handlers);

/* Read and write */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_text(
    ntk_clipboard_session* session, const char* text, uint32_t flags);
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_text(
    ntk_clipboard_session* session, ntk_string** out_text);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_html(
    ntk_clipboard_session* session, const char* fragment, const char* plain_text, uint32_t flags);
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_html(
    ntk_clipboard_session* session, ntk_string** out_html);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_files(
    ntk_clipboard_session* session, const char* const* paths, size_t count, uint32_t flags);
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_files(
    ntk_clipboard_session* session, ntk_string_list** out_paths);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_dib(
    ntk_clipboard_session* session, const uint8_t* dib, size_t size, uint32_t flags);
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_dib(
    ntk_clipboard_session* session, ntk_bytes** out_dib);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_custom(
    ntk_clipboard_session* session, const char* format_name, const uint8_t* data, size_t size,
    uint32_t flags);
ntk_clipboard_error NTK_CALL ntk_clipboard_paste_custom(
    ntk_clipboard_session* session, const char* format_name, ntk_bytes** out_data);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_multiple(
    ntk_clipboard_session* session, const ntk_clipboard_items* items, uint32_t flags);
ntk_clipboard_error NTK_CALL ntk_clipboard_has_format(
    ntk_clipboard_session* session, const char* format_name, int32_t* out_present);
ntk_clipboard_error NTK_CALL ntk_clipboard_get_formats(
    ntk_clipboard_session* session, ntk_string_list** out_formats);
ntk_clipboard_error NTK_CALL ntk_clipboard_get_preferred_format(
    ntk_clipboard_session* session, ntk_string** out_format);
ntk_clipboard_error NTK_CALL ntk_clipboard_clear(ntk_clipboard_session* session);

/* Multi-format builder */
ntk_clipboard_error NTK_CALL ntk_clipboard_items_create(ntk_clipboard_items** out_items);
ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_text(
    ntk_clipboard_items* items, const char* format_name, const char* text);
ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_html(
    ntk_clipboard_items* items, const char* format_name, const char* html);
ntk_clipboard_error NTK_CALL ntk_clipboard_items_add_bytes(
    ntk_clipboard_items* items, const char* format_name, const uint8_t* data, size_t size);
void NTK_CALL ntk_clipboard_items_free(ntk_clipboard_items* items);

/* Deferred rendering (owner thread) */
ntk_clipboard_error NTK_CALL ntk_clipboard_reserve_deferred(
    ntk_clipboard_session* session, const char* const* formats, size_t count,
    ntk_clipboard_render_fn provider, void* user_data, ntk_release_fn release);
ntk_clipboard_error NTK_CALL ntk_clipboard_recover_deferred_state(ntk_clipboard_session* session);
ntk_clipboard_error NTK_CALL ntk_clipboard_render_target_set(
    ntk_clipboard_render_target* target, const uint8_t* data, size_t size);

/* History requests */
ntk_clipboard_error NTK_CALL ntk_clipboard_get_history(
    ntk_clipboard_session* session, ntk_clipboard_history_fn callback, void* user_data,
    uint32_t* out_request_id);
ntk_clipboard_error NTK_CALL ntk_clipboard_restore_history_item(
    ntk_clipboard_session* session, const char* item_id, ntk_clipboard_completion_fn callback,
    void* user_data, uint32_t* out_request_id);
ntk_clipboard_error NTK_CALL ntk_clipboard_delete_history_item(
    ntk_clipboard_session* session, const char* item_id, ntk_clipboard_completion_fn callback,
    void* user_data, uint32_t* out_request_id);
ntk_clipboard_error NTK_CALL ntk_clipboard_clear_unpinned_history(
    ntk_clipboard_session* session, ntk_clipboard_completion_fn callback, void* user_data,
    uint32_t* out_request_id);
ntk_clipboard_error NTK_CALL ntk_clipboard_get_history_availability(
    ntk_clipboard_session* session, ntk_clipboard_availability_fn callback, void* user_data,
    uint32_t* out_request_id);
ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_request(
    ntk_clipboard_session* session, uint32_t request_id);

/* History (argument of ntk_clipboard_history_fn; valid during the call) */
size_t      NTK_CALL ntk_clipboard_history_count(const ntk_clipboard_history* history);
const char* NTK_CALL ntk_clipboard_history_item_id(
    const ntk_clipboard_history* history, size_t index, size_t* out_size);
const char* NTK_CALL ntk_clipboard_history_item_text(
    const ntk_clipboard_history* history, size_t index, size_t* out_size);   /* NULL: no text */
size_t      NTK_CALL ntk_clipboard_history_item_content_type_count(
    const ntk_clipboard_history* history, size_t index);
const char* NTK_CALL ntk_clipboard_history_item_content_type_at(
    const ntk_clipboard_history* history, size_t index, size_t type_index, size_t* out_size);
int64_t     NTK_CALL ntk_clipboard_history_item_timestamp_unix_ms(
    const ntk_clipboard_history* history, size_t index);

#pragma pack(pop)

#ifdef __cplusplus
}
#endif
#endif
```
