# レビュー結果

- 日付: 2026-09-21
- 対象ファイル: `artifact/topics/windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md`
- トピック名: windows-architecture（段階 5: C ABI）
- 対象 OS: Windows 11 以降
- 対象版: v1（初版。コミット `b2c0f1be`）
- 判定: **要修正**（3 者とも。実装へ進まず改版する）
- 別モデルによる独立レビュー: 実施済み。3 者で並行した
  - Claude ①: C++ API の設計書と実装との整合
  - Claude ②: C#（Unity）、Rust、Python、Go のバインディングから見た相互運用
  - Codex: 観点を指定しない独立レビュー
- 機械照合: `python scripts/check_design_consistency.py` → 13 OK / 0 FAIL（v1 の時点）

---

## 強み

- 列挙とエラーの値は、11 章と 8.4 のすべてが `Error.h`、`Dialog.h`、`Notification.h` と一致する（Claude ①）
- 105 関数の内訳は 8.2 の合計と合う。52 export の一覧は `.def` と一致し、削除するテストの件数（20 / 5 / 13）も合う（Claude ①）
- E-10 の削除（`extraFlags`、`unknownKeys`）は、サンプルが使っていないので安全（Claude ①が grep で確認）

## 指摘と反映方針

`指摘者` の略号: ①＝Claude ①、②＝Claude ②、C＝Codex。

### 高優先度

| # | 指摘 | 指摘者 | 反映方針 |
|---|---|---|---|
| R-1 | **通知の活性化の `user_data` は、`close` や差し替えが戻った後も使われうる**。C++ の `ForwardActivation` は、ハンドラをロックの中でコピーし、ロックの外で呼ぶ | ① ② C | **解放のコールバック方式にそろえる**。マネージャーの設定と `set_invoked_handler` に `ntk_release_fn release` を足す。C ABI の包みは、登録ごとに配送中の件数を数え、差し替えか close の後に件数が 0 になった時点で `release` を 1 回呼ぶ。close の中で待つ方式は採らない。UI スレッドで close を呼び、コールバックが UI スレッドへ同期的に戻ると行き詰まるため |
| R-2 | **閉じずに `_free` したセッションは、その後もコールバックを呼び続ける**。C# の `SafeHandle` は、ファイナライザのスレッドで `close` が `WRONG_THREAD` になり、この経路を通る | ① ② | C ABI の包みに**生存フラグ**を持たせる。`_free` で倒し、以後は C の関数ポインタを呼ばない。`_free` とコールバックは同じミューテックスで直列にする。7.5 に放棄の行を足す。E-1 の理由から「`SafeHandle` に包みやすい」を外し、「Dispose はオーナーのスレッドで呼び、close が成功するまで再試行する」と書く |
| R-3 | **今の C ABI のヘッダー 4 つを消すと、Core とテストがビルドできない**。内部が `CLIPBOARD_ERROR_*` とコールバックの typedef に依存している。`CommonInternal.h` の `extern "C"` も残る | ① | T-10 を分ける。定数と typedef を内部ヘッダー（`src/<機能>/*Codes.h`）へ移し、旧ヘッダーを消す。`CommonInternal.h` の `extern "C"` を外す。DoD は「公開用の `extern "C"` の関数宣言が Core に無い」とする |
| R-4 | **「Dialog の内部入口を削除する」と、C++ API の Dialog が消える**。C++ API はその入口の上に実装されている | ① | 8.5 のその行を消す。E-10 の Dialog の作業は、`ToMessageBoxType` から `extraFlags` を外すことだけにする |
| R-5 | **C++ の Dialog は `owner`、`title`、`fileMustExist`、`overwritePrompt` を実装に渡していない**。C の項目を置いても効き目が無い | ① | **C++ の実装を直すタスクを T-03 の前に足す**。`Dialog.h` が既に約束している機能で、今は実装が追いついていないだけ。UI テストで上書きの確認とタイトルを確かめる |
| R-6 | **provider の `release` を包みのデストラクタで呼ぶと、形式の数だけ呼ばれる**。また、手放す時期が実装と違う。全形式の描画でも close でも手放さず、`WM_DESTROYCLIPBOARD`、次の予約、復旧で手放す。`PARTIAL_STATE` のときは保持したまま | ① ② | 包みは `shared_ptr` の解放ガードを捕捉し、最後のコピーが消えたときに 1 回呼ぶ。時期は実装どおりに書き直す。「close では呼ばれない。次の予約か、ほかのアプリの消去か、プロセスの終了まで残りうる」と明記する。**C ABI の入口の検査で拒んだときも、呼び出しスレッドで、戻る前に 1 回呼ぶ**。`PARTIAL_STATE` のときは保持中で、後で呼ぶ |
| R-7 | **`struct_size` による版の見分けに穴がある**。`struct_size` の後ろに暗黙の詰め物がある。`progress_update` は末尾にも詰め物があり、項目を足しても sizeof が変わらない。最小の大きさと項目ごとの読み方も決まっていない | ② C | 詰め物を明示の `reserved` 項目にし、0 以外なら `INVALID_PARAMETER`。最小の大きさは 2.0.0 の sizeof に固定する。項目は `offsetof + sizeof <= struct_size` のときだけ読み、足りない項目は既定値にする。知っている大きさを超える部分は、すべて 0 なら受け付け、0 以外なら `NOT_SUPPORTED`。テストは「新しい DLL が古い大きさを受け付ける」と「古い DLL が新しい大きさを受け付ける」の両方向で行う |
| R-8 | **Runtime を Manager より先に解放できる**。解放すると `MddBootstrapShutdown` が走る | ② C | C ABI の Runtime を参照カウントにする。Manager が生きている間の `runtime_free` は印を付けるだけにし、最後の Manager が閉じたときに Shutdown する |
| R-9 | **105 関数の正確なシグネチャが確定していない**。照合もシンボルの集合しか見ない | C | 付録 A に**公開ヘッダーの完全な宣言**を置く。機械照合で、戻り値、引数の型と順、`NTK_CALL`、構造体の項目をヘッダーと突き合わせる |
| R-10 | **Unity Editor のドメインリロードとプレイモードの出入り**。ネイティブ側の状態は残り、関数ポインタは古いドメインを指したまま、C# のハンドルは消える | ② | 1.3 に Unity の行を足す（`beforeAssemblyReload`、`playModeStateChanged`、`quitting` で、オーナーのスレッドから close する）。R-2 の生存フラグで、閉じ損ねても落ちないようにする。`unity-native-plugin` への申し送りに入れる |

### 中優先度

| # | 指摘 | 指摘者 | 反映方針 |
|---|---|---|---|
| R-11 | **ハンドルごとのスレッドの約束が無い**。「任意のスレッド」が同時に呼んでよいという意味に読める。C++ の `held_` は同期の無い `bool` | ② C | 1.3 にハンドルごとの表を足す。作成、操作、close、`_free`、同時に呼べるかを書く。例: 同じハンドルの操作と close / `_free` は利用者が直列にする。ビルダーはスレッドセーフでない。string、bytes、list は不変 |
| R-12 | **スレッドごとの `ntk_last_system_code()` は、Go（goroutine が OS スレッドを移る）と、非同期の完了（オーナーの値を上書きする）で破綻する**。また、Clipboard と Notification の `systemCode` に入っているのは OS の値ではない | ① ② | 完了のコールバックには `uint32_t system_code` を**引数で**渡し、スレッドごとの値には書かない。7.3 に機能ごとに何が入るかを書く（Dialog は OS の値、Clipboard と Notification はエラーの値か 0）。Go には `LockOSThread` を注記する |
| R-13 | **COM とメッセージループの前提が 1.3 に無い**。`Manager::Create` は呼び出しスレッドを MTA にするので、同じスレッドで `session_create` を呼ぶと `WRONG_APARTMENT` になる。close の再試行ではメッセージを処理する必要がある | ② | 1.3 に行を足す。STA の初期化とメッセージループの最小の手順、close の再試行の仕方、言語ごとの注記を書く |
| R-14 | **コールバックの中で呼んではいけない関数が足りない**。`set_history_handlers` を呼ぶと、Debug では assert になる | ② | 禁止の一覧を直す。セッションのコールバックの中では、close、`_free`、`set_history_handlers` を呼ばない。provider の中では、`render_target_set` 以外のクリップボードの関数を呼ばない |
| R-15 | **閉じていないハンドルの `_free` の意味が、ハンドルごとに違う** | ② | 7.4 にハンドルごとの表を置く。manager は閉じる。runtime は R-8 に従う。session は放棄する（R-2） |
| R-16 | **省略できない文字列の `NULL` の扱いが、E-9 と今の ABI の両方と食い違う**。0 で埋めた進捗の構造体がエラーになる | ① | C++ で素の `std::wstring` の項目は、`NULL` を `""` とする。`INVALID_PARAMETER` にするのは、意味の上で必須な値（コピーする本文、形式名、項目の ID）だけ |
| R-17 | **ダイアログのフィルターが、構造体の中の 2 本の配列になっている**。C# のマーシャラーが扱えず、長さの食い違いも検出できない | ② | 関数の引数に、凍結した組の配列（`ntk_dialog_filter { name; patterns; }`）と件数を取る |
| R-18 | **借りた `const char*` の戻り値に、C# の罠と長さの欠如がある** | ② | 7.4 に「C# は戻りを `IntPtr` で受ける」と書く。文字列の読み取りに、長さを返す出力引数（`NULL` 可）を足す |
| R-19 | **履歴の要求まわりが未定義**。`out_request_id` の扱い、完了と受付の順序、コールバックが `NULL` の場合、availability の失敗時の引数 | ② C | `out_request_id` は `NULL` でよい。オーナー以外のスレッドからの受付では、完了が受付の戻りより先に来うるので、対応付けは `user_data` で行う。コールバックは必須で、`NULL` なら受付前に `INVALID_PARAMETER`。availability は失敗時に両方 0 |
| R-20 | **遅延レンダリングの target の約束が未定義** | ② C | 次のように定める。`set` は 1 回だけで、2 回目は `INVALID_PARAMETER`。`set` を呼ばずに `NONE` を返したら何も描画しない。`target` はコールバックの間だけ有効。データは `set` の中で複製する |
| R-21 | **8.3 の対応表に漏れと誤りがある** | ① | 次を足す。未知の書き込みのビットがエラーになる。`timestamp` は秒からミリ秒になる。scenario や音声の未知の名前は範囲外のエラーになる。活性化は文字列からハンドルになる（`raw_arguments` は同じ JSON）。Dialog の `pError` は `SYSTEM_ERROR` と `system_code` になる。フォルダのダイアログのキャンセルの返し方。履歴の timestamp の形。`getNotificationSetting` の `NULL` の扱い。「バッファが足りずに選択を失うことが無くなる」は誤り（C++ も 1024 / 32768 文字の固定バッファ）なので、上限を書く |
| R-22 | **UTF-16 から UTF-8 への変換の方針が無い**。対になっていないサロゲートを含むと、貼り付け、履歴、パスが失敗する | ① | U+FFFD に置き換えて成功を返す。置き換えは損失を伴うことを 7.6 と 8.3 に書く |
| R-23 | **D-8（固定幅の型だけ）と `size_t` が食い違う** | C | D-8 の例外として「件数、大きさ、添字は `size_t`。対象は x64 だけ」と明記する |
| R-24 | **実際の DLL の境界を通るテストが無い** | C | 公開ヘッダーと import ライブラリだけでリンクする小さな C の実行ファイル（`WindowsLibraryCApiSmoke`）を足し、版、構造体、ハンドル、コールバックを実際の DLL で通す |

### 低優先度

| # | 指摘 | 指摘者 | 反映方針 |
|---|---|---|---|
| R-25 | 履歴の timestamp の単位（WinRT の tick、1601 年起点）が C ABI から分からない | ① ② C | Unix ミリ秒に変換して、`ntk_clipboard_history_item_timestamp_unix_ms` にする。通知と単位をそろえる |
| R-26 | 列挙の値を `#define` にすると、bindgen が `u32` の定数を出す | ② | 値は無名の `enum { ... };` で定義し、型は `typedef int32_t` のまま残す |
| R-27 | 7.3 の出力引数と `ntk_last_system_code()` の文言が自己矛盾している | ① ② C | 出力のハンドルは入口で `NULL` を書く。値の出力は成功したときだけ書く。システムコードは失敗しうる関数が戻るたびに更新し、成功なら 0 |
| R-28 | ビルダーで項目を外せない、`_set_audio` の `NULL`、履歴の text の `NULL` の二義、`items` の宣言が無い、`E_OUTOFMEMORY` の値を参照できない | ① ② | 付録 A で宣言を確定し、意味を書く。「無い」に戻したいビルダーは作り直す、と明記する。定数 `NTK_SYSTEM_CODE_E_OUTOFMEMORY` を置く |
| R-29 | 件数とタスクの割り当ての誤り（T-04 は 12 操作、CT-10 は T-07 の後、入力一覧 §1.10 は 14 行）。E-10 の影響の一覧が足りない。放棄の後の `create` は `WRONG_THREAD` もありうる | ① | 直す |
| R-30 | 機械照合が黙って弱くなる（`check_cpp_api_contract.py` が旧 `.def` と旧ヘッダーを読み、無ければ skip）。旧 C ABI に触れる C++ の Doxygen が残る。「`UnityWindowsPlugin` の参照 0 件」は文字どおりには達成できない。空の `ntk_bytes` のテストが無い | ① C | T-09 で参照先を付け替える。T-12 で C++ の Doxygen を全件検索する。DoD の検索の範囲を定める（履歴を書いた文書は除く）。CT-09 に足す |

## 利用者の決定（2026-09-21）

| 点 | 決定 | 設計書 |
|---|---|---|
| R-1 通知の `user_data` の期間 | 解放のコールバックで知らせる（close の中で待たない） | E-12、7.5.1 |
| R-5 C++ の Dialog の 4 項目 | 段階 5 で C++ の実装を直す | E-13、T-03 |
| R-25 履歴の timestamp | Unix ミリ秒に変換する | E-14 |

ほかの 27 件は反映方針のとおり第 2 版に入れた。反映先は設計書の 0 章。
