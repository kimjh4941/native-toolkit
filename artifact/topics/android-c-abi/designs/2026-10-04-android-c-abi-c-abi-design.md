# Android ライブラリ C ABI 実装設計書（第 1 部: スレッド・寿命・Context）

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/android-c-abi/README.md` |
| 対象段階 | 段階 1b の前に第 1 部（この版。スレッド・寿命・Context の章と、D-4・D-6・D-8・D-9・D-10・D-13 の決定）、段階 2b の前に第 2 部（関数の一覧、6 章の振る舞いの集合との対応表、付録 A のヘッダー） |
| 対象 OS | Android 12（API 31）以降、`arm64-v8a` と `x86_64` |
| 作成日 | 2026-10-04（v5 のレビューを反映した第 6 版。**第 1 部は決定**） |
| ブランチ | `feature/NTKIT-17` |
| 前段階 | 段階 0（UI テストと基準、パッケージ名、ツールチェーン）と段階 1a（NDK のスパイク）は完了 |
| 元にした文書 | Windows の C ABI の設計書（`windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md`。以下「Windows の設計書」）、1a の結果（`results/2026-10-04-android-c-abi-stage1a-spike-result.md`。以下「1a」） |
| 後に続く文書 | Kotlin の API の補完の設計書（9.1 の条件を満たすように書く。README 5.1）、第 2 部（9.2 の条件） |
| レビュー | `reviews/2026-10-04-android-c-abi-c-abi-design-review-v1.md`（1 回目。R-C1〜R-C29、R-X1〜R-X15）、`-v2.md`（2 回目。S-C1〜S-C15、S-X1〜S-X7）、`-v3.md`（3 回目。T-C1〜T-C12、T-X1〜T-X10）、`-v4.md`（4 回目。U-C1〜U-C9、U-X1〜U-X2）、`-v5.md`（5 回目。V-C1〜V-C10、V-X） |

- **`PLANNED_SYMBOLS_EXEMPT`**: この設計書は、まだ書かれていない C ABI の名前（`ntk_*`、`NtkInitializer` など）を定める。実装の前なので、名前が実装に存在するかの照合は第 2 部と 2a の機械照合が受け持つ

## 0. レビューの反映

### 0.1 第 2 版での反映（v1 のレビュー）

1 回目の区分 A（21 件）の反映先は `reviews/...-review-v1.md` の表にある。要点: 受け付けの成立点と登録の状態、使い回さない ID、解除の後の配送、コールバックの引数、初期化の状態、手動の経路の前面、`NOT_FOREGROUND` を完了で返す、Clipboard のフォーカス、ちょうど 1 回の完了、プロセスの終わり、U+FFFD と U+0000、コールバックの例外、`system_code` の引数、Share と権限の操作ごとの前面、R8 の規則、C# の版、いつも積む。

### 0.2 第 3 版での反映（v2 のレビュー）

2 回目に、状態機械（登録と初期化）の指摘が 1 回目に続いて出た。手順の決まり（同じ種類の指摘が続いたら仕組みを直す）に従い、**2 つの状態機械を文章ではなく「状態 × 出来事 → 振る舞い」の表で書き直し、`release` を呼ぶのは状態を書き換えられた 1 か所だけにした**（5.3、5.7）。

| # | 指摘 | 反映 |
|---|---|---|
| S-C1、R-C1 | off-main の登録で、C が「有効」にする前に main が挿入と配送を処理しうる | C は登録を「有効」で作ってから受け口を呼ぶ。挿入と操作の開始を 1 つの main のメッセージにする。off-main から呼んだときは、関数が戻る前に完了が来うる、を契約にした（1.3、5.7） |
| S-C2 | 挿入と「外す」の両方が `release` を呼ぶ | `release` を呼ぶのは、状態を「解放済み」に CAS できた 1 か所だけ（5.7 の表） |
| S-C3 | ライブラリの側で終わる登録（差し替え、close、置き換え、取り消し）の契約が無い | 登録を 2 種類に分けた。イベントの登録は利用者が解除するまで生き、ライブラリの側で終わらせない。完了つきの操作はハンドルを持たず、ライブラリの側で終わるときも必ず完了する（5.7、AC-21） |
| S-C4、S-X1 | Share の結果は閉じたときに何も来ないので、完了にできない。ちょうど 1 回の完了の対象が狭い | 「選ばれたアプリ」は完了ではなくイベントにする（今のブリッジの `onShareResult` と同じ）。ちょうど 1 回の完了の対象を、README 6 章の全操作の完了に広げた（AC-22、K-3） |
| S-C5、R-C5、R-X8 | 初期化の中間の状態が無く、`READY` を立てる時点が無い | 状態を `UNINIT` → `NATIVE_READY` → `READY`（と `FAILED`）にし、表にした（5.3） |
| S-C6 | 準備のミューテックスを持ったまま Java を呼ぶので、入り直しと起動時のデッドロックが起きる | ミューテックスで守るのは C の表づくりだけ。どの経路も待たない（取れなければ `IN_PROGRESS`）。手動の経路は `System.loadLibrary` も Startup の部品も呼ばない（5.3） |
| S-C7 | `JNI_OnLoad` の失敗で `FAILED` に固まる | `FAILED` にするのは、アプリのクラスローダーを持つ経路（`ntk_android_init`）での失敗だけ（5.3） |
| S-C8、S-X3 | 設定の画面の開き方が今と違う | 前面の Activity から開く（今のブリッジと同じタスク）に直した（5.8） |
| S-C9 | 権限の「要求できない」は Application の Context では判定できない | Application で判定するのは「API 32 以下」と「許可済み」だけにした（5.8） |
| S-X2 | Share の前面の判定が 1b の「動作を変えない」と食い違う | 前面の判定と `NOT_FOREGROUND` は C ABI の受け口（2b）が行い、1b の `android_library` の既存の API の動作は変えない（5.8） |
| R-X7、S-C14 | README D-6 の本文が古い | README D-6 を直した |

### 0.3 第 4 版での反映（v3 のレビュー）

3 回目には、登録の状態の表は具体的なスレッドの組み合わせを追っても崩れなかった（Claude）。残った A は初期化の表の細部と、**今のブリッジとの互換**だった。互換の指摘は 2 回目から続いたので、仕組みとして原則を 1 つ決めた（AC-23: C ABI はブリッジを写さず、違いは第 2 部の対応表に書き、Unity から見た動作は 2c の包みが保つ）。

| # | 指摘 | 反映 |
|---|---|---|
| T-X1、T-C1 | Kotlin の側が済む前に `READY` が立ちうる。CAS に負けた側が「済んだ」と「途中」を区別できない | Kotlin の側を 3 値にし、`READY` は両方の準備が済んだ後、後に済んだ側が CAS で立てる（5.3） |
| T-X2、T-C2 | やり直しの約束が閉じていない。Kotlin の `init` から C に入る口が無い | やり直しの約束と、Kotlin の `init` の結果の型（`NATIVE_SETUP_REQUIRED` を含む）を決めた（1.4、5.3） |
| T-X3、T-C3 | Share の選ばれたアプリが、README 6 章では完了の扱い。要求との対応付けが無い | イベントに要求の ID を付ける。今と同じく直前の Share の選択だけが届く。README 6 章の分類を直した（AC-22、5.8） |
| T-X5 | K-4（前の待ちを消さない）が 1b の「動作を変えない」と食い違う | K-4 を取り下げ、今の振る舞い（新しい Share が前の待ちを消す）のままにした（AC-22） |
| T-X4、T-X6、T-X7 | 差し替え型の `set*Listener`、設定の画面、Share と設定の前面の判定が今のブリッジと違う | AC-23 の原則。違いは第 2 部の対応表に書き、Unity から見た動作は 2c の包みが保つ（`set` は 1 つのハンドルを外してから足す） |
| T-C4 | 完了つきの操作の取り消しを何で指すかが無い | 使い回さない ID で取り消す。完了の後や知らない ID は何もしない（1.3.1、5.7） |

### 0.4 第 5 版での反映（v4 のレビュー）

4 回目には、2 つの状態の表は具体的な順序を追っても崩れず、AC-23 も README と矛盾しないと 2 者とも判断した。残った A は初期化の合流と失敗の後の遷移、Share の要求の ID の付け方だった。

| # | 指摘 | 反映 |
|---|---|---|
| U-C1、U-X2 | Kotlin の側の初期化が失敗した後の遷移が無く、C と Kotlin の口がやり直すべきかを逆に伝える | 失敗した呼び出しは「途中」を「未着手」に戻す。結果を「やり直せる失敗」と「直らない失敗」にそろえた（5.3） |
| U-X1、U-C3 | Kotlin の側が済んだことを C に知らせる役が決まっていない。`android_library` から呼ぶと依存の向きに反する | `android_library` は知らせない。C ABI の側の 3 つの入口が、Kotlin の側の「済み」を見るたびに知らせる（何度でも安全）（5.3） |
| T-X3（残り）、U-C5 | 今の Share は全要求が同じ PendingIntent なので、古い Chooser の選択が新しい要求の ID に付きうる。取り消しの行き先が無い | 要求ごとの印を broadcast に入れ、今の要求でないものは捨てる。取り消しは要求の ID で行う。1b で直す不具合として README に書いた（AC-22、K-4） |

### 0.5 第 6 版での反映（v5 のレビュー）

5 回目（手順の決まりの上限）には、4 回目の A はすべて直り、2 つの表は具体的な順序で崩れなかった。第 5 版で足した文言から A が 2 件出たので、局所的に直した。

| # | 指摘 | 反映 |
|---|---|---|
| V-C1 | Share を開く操作は Chooser が開いた時点で完了するので、「完了の後の取り消しは何もしない」のとおりだと選択の待ちを取り消せない | Share の要求の ID の取り消しは「選択の待ち」を取り消すもの、と 1.3.1 の例外として書いた（AC-22） |
| V-C2 | `NATIVE_SETUP_REQUIRED` をやり直せるとしたが、`JNI_OnLoad` の失敗の後はやり直しで直らない。R8 で名前が変わった場合に C と Kotlin が逆を返す | `NATIVE_SETUP_REQUIRED` は「C の `ntk_android_init` を呼ぶ」の意味にした。Kotlin の側も `capi.jni` のクラスを確かめ、無ければ `CLASS_NOT_FOUND` を返す（5.3） |
| V-C1（反映の漏れ） | 5.7 の取り消しの規則と 6 章のテストが古い契約のままだった（確かめの Codex） | Share の選択の待ちは C の登録ではなく Kotlin の側の印で、取り消しは C の登録の表を通らない、と 5.7 に書き、6 章を直した |
| V-X（T-X3 の残り）、V-C4 | 印を extra だけに入れると、固定の request code と `FLAG_UPDATE_CURRENT` で上書きされる | 要求ごとに別の PendingIntent（data の URI に印）を作る形に限った（AC-22、K-4） |

### 0.6 第 2 部を受けた直し（2026-10-05）

第 2 部（`designs/2026-10-05-android-c-abi-c-abi-design-part2.md` の 7 章、TB-12）で決めたことに合わせて直した。決定は変えていない。

| 直した所 | 第 2 部の決定 |
|---|---|
| 5.8 の表に Progress の前景サービスの行を足した | AP-14 |
| 5.11 の「通知は `PERMISSION_DENIED`」が受け口の事前の確かめで出る値であることを書き足した | AP-16 |

### 0.7 2b の実装レビューを受けた直し（2026-10-10）

6 章の「`exit` で落ちない」の確かめ方を、別のプロセスで `exit` を呼ぶテストから、配る `libntk.so` の照合に変えた。2b のレビュー（`reviews/2026-10-10-android-c-abi-stage2b-review-v1.md` の K-C5）でテストを足そうとして、端末（Pixel 6a、API 36）で次のことが分かったため。

- ネイティブのメソッドから C の `exit` を呼ぶと、C ABI を使わなくても ART の JIT のスレッドが SIGSEGV で落ちる（3 回とも）。画面を出したプロセスでは、OS の描画のスレッド（`hwuiTask`）も壊された mutex をつかんで落ちる。どちらも C ABI とは関係が無い
- `System.exit` は、読み込んだライブラリの静的なデストラクタを走らせない（デストラクタでログを出す静的な変数を置いて確かめた）。これで終わらせるテストは、5.5 が心配する壊れ方を起こせない

そこで、5.5 の規則（静的なデストラクタを持つ変数を置かない）そのものを、配る `libntk.so` が終わりの登録（`__cxa_atexit`、`atexit`、`thread_local` の `__cxa_thread_atexit(_impl)`）を import していないことで確かめる。デストラクタを持つ静的な変数を 1 つ足すとこの import が現れることを、変異で確かめた。6 章の行の名前も、照合が確かめることに合わせた。

2 回目のレビュー（`reviews/2026-10-10-android-c-abi-stage2b-review-v2.md`）を受けて、次も直した。

- 1 章の表、1.4、AC-3 の「未初期化ではすべての操作が `NOT_INITIALIZED`」に、第 2 部 11 章の例外（入口の検査が先、取り消しは `NONE`）を書いた（R-C1）
- 5.7 の「外す」を積めなかったとき: プロセスの終わりに限らず起きうるので、CANCEL_REQUESTED のまま印を付け、main が次に C に入ったときに外す（R-X1。3 回目のレビューで列から印に変え、遅れに上限が無いことを書いた）

## 1. 利用者が最初に知ること

README 3.1 が冒頭に置くよう求める前提と、Windows の設計書 1 章に当たる名前・受け渡し・スレッドの決まり。

### 1.1 Windows と同じもの

次は Windows の設計書をそのまま引き継ぐ（README 3.2）。この設計書では繰り返さず、違うところだけを書く。

| 項目 | Windows の設計書 |
|---|---|
| 名前の規則（`ntk_<機能>_<動詞>`、ハンドルは不完全型、列挙は `typedef int32_t` と無名の `enum`、コールバックは `_fn`） | 1.1 |
| 受け渡しの 3 方式（出力のハンドル、`struct_size` 付きの構造体、ビルダーのハンドル） | 1.2、E-5 |
| エラーは戻り値（機能ごとの列挙、0 が成功、欠番は詰めない）。出力のハンドルは入口で `NULL` を書く | 7.3 |
| メモリ（`_free` は確保した側、`_free(NULL)` は何もしない、ハンドルの読み取りが返すポインタは元のハンドルを解放するまで有効、長さの出力引数） | 7.4。**ただしコールバックの引数は 5.9 の Android の規則** |
| すべてのコールバックの第 1 引数が `void* user_data`、`release` は受け取ったら戻り値にかかわらずちょうど 1 回 | 7.5.1 の共通の規則 |
| **非同期の完了は、システムコードを引数（`uint32_t system_code`）で渡し、スレッドごとの値を更新しない**。Android では常に 0（AC-10） | E-18、7.3 |
| ライブラリは、コールバックを呼ぶ間、利用者が触れるロックを持たない | 7.5.5 |
| 文字列は NUL で終わる UTF-8、`NULL` と `""` の区別、不正な UTF-8 は `INVALID_PARAMETER`、出力の不正なサロゲートは U+FFFD、出力の途中に NUL は入らない | 7.6、E-15、E-16。**Android の実装は 5.10** |
| 真偽値は `int32_t`、0 で埋めた構造体が既定値、件数は `size_t` | E-8、E-9、E-17 |
| `struct_size` の読み方（先頭 8 バイト、詰め物の明示、最小は 2.0.0 の `sizeof`、上限 4096、未知の部分は 0 なら受け付ける、8 バイトの倍数で増やす） | 7.8 |
| 公開ヘッダーは `<stdint.h>` と `<stddef.h>` だけを include、ASCII だけ、C99 と C++ の両方でコンパイルでき、各ヘッダーが include ガードと `extern "C"` を持ち、構造体を `#pragma pack(push, 8)` で囲む | 7.2 |
| C++ の例外は C ABI の入口を越えない（すべての入口で捕まえる） | 7.7。**利用者のコールバックの例外は 5.11 の Android の規則** |

### 1.2 Android の前提（README 3.1）

**汎用の C ABI だが、中身は JNI で Kotlin（`android_library`）を呼ぶ。** そのため次の前提がある。

| 前提 | 成り立たない使い方 |
|---|---|
| Android アプリのプロセスの中で呼び、アプリが Kotlin / Java のコードを持つ（`android:hasCode="true"`） | `adb shell` で動かす実行ファイル。`hasCode="false"` の NativeActivity だけのアプリ |
| 2 つの AAR（`android-native-toolkit`、`android-native-toolkit-capi`）とその依存をアプリの Gradle のビルドに入れる（D-17 の `m2/`） | `.so` だけを写して `dlopen` すること。初期化（1.4）に要る Kotlin のクラスが無い |
| 64 ビット（`arm64-v8a` / `x86_64`）で動くときだけ C の関数がある（D-10） | 32 ビットで入ったアプリ。アプリは落ちないが（5.3）、`.so` が無いので `DllImport` / `DynamicLibrary.open` が失敗する |
| 初期化が済んでから呼ぶ（1.4）。既定では Startup が済ませる | Startup を無効にし、手動の初期化も呼ばない使い方。操作は `NOT_INITIALIZED` を返す（引数の誤りが先、取り消しは `NONE`。第 2 部 11 章） |
| 自分が作っていないスレッド（Android の main スレッド）からのコールバックを受けられる（1.3） | 呼び出し元のスレッドでしか関数ポインタを受けられない仕組み（Dart の `NativeCallable.isolateLocal`） |
| Dialog・権限のダイアログ・Share の Chooser・設定の画面は、アプリが前面にいるときに使う（5.8） | アプリが後ろにいるときの呼び出し。完了が `NOT_FOREGROUND` で来る |

Kotlin / Java のアプリは C ABI を使わず、`android_library` を直接呼ぶ。

### 1.3 スレッドと完了の規則（D-6、AC-4〜AC-6）

**Windows の「UI スレッドとメッセージループ」に当たるのは、Android の main スレッド（`Looper.getMainLooper()`）である。** 利用者は main のループを回す必要は無い（Android のフレームワークが回している）。

| 規則 | 内容 |
|---|---|
| 呼べるスレッド | **すべての関数は、どのスレッドからでも呼べる**（main を含む）。ハンドルごとの同時の呼び出しの約束は 1.3.1 |
| main を待たない | **どの関数も、main スレッドの処理が終わるのを待たない**（AC-5）。main で動かす必要がある処理は main に積み、結果は完了のコールバックで返す |
| いつも積む | main で動かす処理は、**main から呼ばれた場合も**その場では動かさず積む（README D-6 を改めた。AC-5） |
| コールバックのスレッド | **完了・イベント・受け付けた後の `release` は、すべて main スレッドで呼ぶ**（AC-4） |
| 完了の時刻 | 受け付けた操作の完了と `release` は、呼び出しスレッドの上で関数の中から呼ぶことはない。**main から呼んだ場合は、関数が戻った後に来る。main 以外から呼んだ場合は、関数が戻る前に（main の上で）来うる**（Windows の設計書 7.5.4 と同じ考え方）。完了と要求の対応付けは `user_data` で行い、関数の出力（要求の ID など）が書かれる前に完了が来うると考える |
| 入口で拒んだとき | 入口の検査（`NULL`、不正な UTF-8、長さ、`struct_size`、未初期化、受け付けの失敗。5.7）で拒んだときは、エラーを戻り値で返し、完了のコールバックを**呼ばず**、`release` を呼び出しスレッドで関数が戻る前に呼ぶ（Windows の設計書 7.5.1 と同じ） |
| 受け付けた後の失敗 | 受け付けた後に分かった失敗（`NOT_FOREGROUND`、ユーザーの取り消し、途中で画面が消えた、など）は、**すべて完了のコールバックの引数で返す**。戻り値は受け付けたことだけを表す（AC-15） |
| ちょうど 1 回の完了 | **受け付けた完了つきの操作（README 6 章の「操作の完了」のすべてと、通知の権限の要求）は、プロセスが生きている限り、ちょうど 1 回完了する。** 表示できなかった、途中で消えた（画面の回転、透明な Activity の破棄など）、同時の要求に置き換えられた場合は、`CANCELED` などの値で完了する（AC-22、K-3） |
| 順序 | 1 つの登録への配送は、main に積んだ順に呼ぶ。イベントが起きた時刻の順ではない |
| 解除とイベント | **main から呼んだ解除は、その場で以後の配送を止める**（解除が戻った後、その登録のコールバックは呼ばれない）。**main 以外から呼んだ解除は、`release` が呼ばれるまで配送が来うる**。どちらも、`user_data` を片付けてよいのは `release` の後（5.7） |
| プロセスの終わり | プロセスが終わるとき（`exit`、OS による終了）は、**完了も `release` も呼ばない** |

**なぜ main を待たないか:** Flutter は 3.29 から Android で Dart を main スレッドで動かし、無効にする選択肢も無い（README D-8）。Unity のスクリプトは UnityMain スレッドで動くが、main の処理が Unity のスレッドを待つ場面がある。どちらも、ライブラリが main を待つと互いに待って止まる。**同じ理由で、利用者もどのスレッドからも完了や `release` を同期で待たない**（Windows の設計書 1.3.4 の「期限付きで待つ」は Android に持ち込まない）。

**なぜ main から呼ばれても積むか:** その場で動かすと、main から呼んだときと別のスレッドから呼んだときで、画面の動きと状態の変わる順序が変わる。いつも積めば、どのスレッドから呼んでも同じ順序になる。

**言語ごとの受け方:**

| 言語 | コールバックの受け方 |
|---|---|
| C# / Unity | `[MonoPInvokeCallback]` の static メソッドで受け、自分のメインスレッド（UnityMain）へ渡す。**本体を `try` / `catch` で囲む**（例外がネイティブの枠へ抜けるとプロセスが終わる。5.11。Windows では包みが捕まえるので、同じ C# のコードでも OS で結果が違う）。Android の実機には Editor のドメインリロードは無い |
| Dart / Flutter | `NativeCallable.listener`（呼び出し元はコールバックが動く前に戻るが、5.9 の規則で引数は後から読める）。コールバックの戻り値はすべて `void` |
| Rust | `extern "C" fn`。`user_data` で受けた状態を `Send` にする。`catch_unwind` で panic を止める |
| Go | cgo の `//export`。Go が作っていないスレッドからの呼び出しになる |
| C / C++（NDK のアプリ） | 普通の関数ポインタ。main は UI のスレッドなので、重い処理は自分のスレッドへ渡す |

#### 1.3.1 ハンドルごとの約束

| ハンドル | 作る・操作・解放 | 同時の呼び出し |
|---|---|---|
| イベントの登録のハンドル（第 2 部で決める） | どのスレッドでもよい | 操作どうしは同時に呼んでよい。**解除は、同じハンドルのほかの呼び出しと同時に呼ばない。解除の後、そのハンドルは無効**（`_free` と同じ。2 回目の解除は未定義。AC-17）。**ライブラリの側で解除することは無い**（AC-21） |
| 完了つきの操作 | ハンドルを持たない（関数に完了のコールバック、`user_data`、`release` を渡す）。取り消せる操作は、出力引数で**使い回さない 64 ビットの要求の ID**を返し、取り消しの関数はその ID を取る | 取り消しはどのスレッドからでもよい。**完了の後の取り消しと、知らない ID の取り消しは何もしない**（main 以外から呼ぶと、関数が戻る前に完了しうるので、利用者は完了の後の取り消しを避けられないため）。ID を持たない一括の取り消しは作らない。**例外: Share の要求の ID の取り消しは、開く操作の完了ではなく「選択の待ち」を取り消す**（開く操作は Chooser が開いた時点で完了するので。AC-22） |
| ビルダー（通知の内容など） | どのスレッドでもよい | **スレッドセーフでない**。1 つのスレッドで作って渡す |
| 出力のハンドル（`ntk_string` など）と、コールバックで受け取ったハンドル | 読み取りと解放はどのスレッドでもよい | 不変。どのスレッドから読んでも解放してもよい |

#### 1.3.2 コールバックの中と、`release` のロック

| 対象 | 規則 |
|---|---|
| すべてのコールバック | **main を長く塞ぐ処理**（ネットワーク、大きなファイルの読み書き、ほかのスレッドを待つこと）をしない。コールバックは main で呼ぶので、塞ぐとアプリ全体が止まる（ANR）。**例外を外へ出さない**（5.11） |
| コールバックの中から `ntk_*` | 呼んでよい（ライブラリの関数は main を待たないので止まらない）。解除も呼んでよい（main からの解除なので、その場で以後の配送が止まる） |
| `release` が取るロック | 受け付けた後の `release` は main の上で呼ぶ。**入口で拒んだときの `release` は、登録・開始の関数の中で同期に呼ぶので、`release` が取るロックを持ったまま登録・開始の関数を呼ばない** |

### 1.4 初期化（D-4、AC-1〜AC-3）

C の関数が動くには、JavaVM、アプリのクラスローダーで引いたクラス、Application の Context、前面の Activity を追う仕組みが要る。これを次の経路で用意する。**どの経路も待たない。初期化はプロセスで 1 回だけ成功し、成功した後の呼び出しは何もしない。**

| 経路 | 誰が | いつ | 使う場面 |
|---|---|---|---|
| 自動（既定） | `android-native-toolkit-capi` の `NtkInitializer`（androidx.startup）。`android_library` の `LibraryInitializer`（前面の Activity を追う）に依存する | アプリの起動時、`Application.onCreate` の前 | 普通のアプリ（Unity、Flutter、NDK のアプリ） |
| 手動（C） | 利用者が `ntk_android_init(env, context)` を呼ぶ | 最初の `ntk_*` の操作より前 | Startup を無効にしたアプリ、既定でないプロセス（Startup は既定のプロセスでしか動かない）、`dlopen` だけで読み込む使い方 |
| 手動（Kotlin） | 利用者が `NativeToolkitCApi.init(context)` を呼ぶ | 同上 | Kotlin のコードを持つ利用者（Flutter のプラグインの Android の側など） |

- 手動の経路は、Startup を通らずに、`LibraryInitializer` と `NtkInitializer` が使うのと同じ「1 回だけ動く」初期化の関数を直接呼ぶ（Startup の `AppInitializer` は中でロックを取るので、起動中の main を待つことになる。5.3）。前面の Activity を追う仕組みも登録される
- **`context` が Activity なら、それを前面の Activity の初期値として追う仕組みに渡す**（遅く初期化すると、すでに表示中の Activity の通知を見逃すため。README D-4。5.8）
- **未初期化のまま呼ぶと、操作は機能のエラーの `NOT_INITIALIZED` を戻り値で返す**（入口で拒むので `release` は呼び出しスレッドで呼ぶ）。読み取りと `_free` は初期化に関係なく動く。例外は第 2 部 11 章: 入口の検査（引数の誤り、AP-19 の入口の値）が初期化の確かめより先で、取り消しの 3 つは何もせずに `NONE` を返す
- Startup は利用者のほかの ContentProvider より後に動くことがある（ContentProvider の順序は決まっていない）。**利用者が自分の ContentProvider の中から呼ぶなら、手動の経路を使う**

```c
/* Android.h */
typedef int32_t ntk_android_error;
enum {
    NTK_ANDROID_ERROR_NONE = 0,
    NTK_ANDROID_ERROR_INVALID_PARAMETER = 1,  /* env or context is NULL */
    NTK_ANDROID_ERROR_CLASS_NOT_FOUND = 2,    /* the AAR's classes or members are missing or renamed (R8); permanent */
    NTK_ANDROID_ERROR_JNI_FAILURE = 3,        /* a transient failure; call again later. logcat (tag ntk) has the detail */
    NTK_ANDROID_ERROR_IN_PROGRESS = 4         /* another thread is initializing; call again later */
};
/* env: JNIEnv* of the calling thread. context: any Context (jobject). Its application context
   is kept; an Activity is also taken as the current foreground Activity. Never waits. Safe to
   call more than once and from any thread; returns NONE once initialized. */
ntk_android_error NTK_CALL ntk_android_init(void* env, void* context);
int32_t           NTK_CALL ntk_android_is_initialized(void);
```

- 引数の型は `void*`（`JNIEnv*` と `jobject`）。公開ヘッダーに `<jni.h>` を持ち込まない（1.1）
- **`env` は呼び出しスレッドのもの**を渡す。`env` か `context` が `NULL` なら `INVALID_PARAMETER`
- 戻り値と状態の関係は 5.3 の表。`IN_PROGRESS` と `JNI_FAILURE` は、後でもう一度呼べばよい（待たない。main から呼んでも止まらない）。`CLASS_NOT_FOUND`（AAR のクラスかメンバーが無い）だけはやり直しても直らない（5.3 の「やり直しの約束」）
- Kotlin の `NativeToolkitCApi.init(context)` は結果の型（`InitResult`）を返す（5.3）

## 2. 設計目的

- `unity_android_plugin`（JSON と `AndroidJavaProxy` のブリッジ）に代わる、汎用の C ABI（`android_library_capi`）を作る（README 1.1）
- C ABI は **`android_library` の Kotlin の API の薄い包み**にする。振る舞いは Kotlin の API が決め、C ABI は型の変換、寿命の管理、スレッドの受け渡し、前面の判定、例外の捕捉だけを受け持つ（Windows の E-2 と同じ）
- Windows の C ABI と同じ規約にし、同じ意味の操作には同じ名前を付ける（README 3.3、D-3）。ただし Android の前提（JNI、main スレッド、Activity）から来る違いは、無理にそろえない（Dialog は非同期だけ。D-8。コールバックの引数。5.9）

## 3. スコープ

### 3.1 第 1 部（この版）

- 1 章の利用者の前提、スレッドと完了の規則、初期化
- 5 章の実装アーキテクチャ（成果物、ヘッダー、初期化、ビルドと R8、JNI、スレッド、寿命と `release`、Context と前面、コールバックの引数、文字列、エラーと例外、ログ）
- D-4・D-6・D-8・D-9・D-10・D-13 の決定（4.2）
- README 8.6 のうち C ABI の設計書の項目（`Common.h` と `NTK_VERSION`、`consumer-rules.pro` を含む）
- テストの方針（6 章）と、後に続く文書に任せる条件（9 章）

### 3.2 第 2 部（2b の前）

- 機能ごとの関数の一覧と型、エラーの値（`NOT_INITIALIZED`、`NOT_FOREGROUND`、`CANCELED` などの値）、同期・非同期の別
- README 6 章の振る舞いの集合（45 の操作、完了、自発のイベント、登録と解除、権限の要求）との対応表。2a の機械照合の対象
- 付録 A の公開ヘッダーの全宣言
- `unity-native-plugin` に渡す対応表の範囲（README 8.6）

### 3.3 対象外

- Kotlin の API の補完の中身（イベントを保つ口、前面の Activity と透明な Activity、予約の保存形式）。別の設計書で決める。この設計書は、それらが C ABI に対して満たすべき条件（9.1）だけを書く
- `android_library` にあるがブリッジが公開していない機能（CallStyle、`getActive` など。D-5）
- iOS / macOS の C ABI

## 4. 前提と決定

### 4.1 企画書（README）由来の前提

| 前提 | 出典 |
|---|---|
| C ABI の範囲は、今のブリッジの振る舞いの集合と通知の権限の要求 | D-5、6 章 |
| ABI は `arm64-v8a` と `x86_64` だけ | D-10 |
| 1.x で予約した通知は 2.0.0 への更新の後に一度だけ破棄する | D-11 |
| 版は 2.0.0、配布は `m2/` の Maven リポジトリと AAR | D-12、D-17 |
| minSdk 31 | D-18 |
| Activity が要る機能は、前面が `FragmentActivity` ならその上に、違えば透明な Activity で出す | D-7 |
| 規約と OS に依存しないヘッダーは OS 間で共通、機能のヘッダーは OS ごと | D-3 |
| Windows の E-1〜E-21 のうち、引き継ぐもの・決め直すもの | README 3.2 |
| 1b は、ネイティブの利用者から見た動作を変えない（1.x の予約の破棄を除く）。**この設計書が足す前面の判定と `NOT_FOREGROUND` は C ABI の受け口（2b）の振る舞いで、1b の `android_library` の既存の API の動作は変えない**（5.8） | README 5 章の 1b の行 |

### 4.2 この設計書で決めること

ID は `AC-n`（Android の C ABI）。**決定（2026-10-04）**: 5 回のレビューと、直した所の確かめ（`reviews/...-review-v5.md` の末尾）で区分 A が 0 になった。

| ID | 決めること | 案 | 理由 |
|---|---|---|---|
| AC-1 | 初期化の経路（D-4） | **自動（`NtkInitializer`）と手動（`ntk_android_init` / `NativeToolkitCApi.init`）の両方**。手動の経路は、Startup を通らずに同じ「1 回だけ動く」初期化の関数を直接呼ぶ | 1.4。1a 3.1 で、`dlopen` だけで開かれるとアプリのクラスを引けないことを確かめた。手動の経路で前面の Activity を追えないと、Dialog などが使えない（R-C6）。Startup の `AppInitializer` はロックを取るので、起動中の main を待つ（S-C6） |
| AC-2 | `ntk_android_init` の引数と戻り値 | **`(void* env, void* context)`**。JavaVM は `env` から取る。**決して待たない**。戻り値は 5.3 の状態の表に従う（`READY` なら `NONE`、ほかのスレッドが準備中なら `IN_PROGRESS`、失敗なら理由）。`IN_PROGRESS` と `JNI_FAILURE` はやり直せる。`context` が Activity なら前面の初期値にする（`READY` の後の呼び出しでは使わない） | JavaVM はライブラリの中で `env` か `JNI_GetCreatedJavaVMs` から取れる（1a 3.1）。待つ形は、main と互いに待つ経路を作る（S-C6） |
| AC-3 | 未初期化の扱い | 操作は機能のエラーの **`NOT_INITIALIZED`** を戻り値で返す（各機能のエラーに値を持たせる。値と例外は第 2 部 11 章: 入口の検査が先、取り消しは `NONE`）。読み取りと `_free` は動く | 自動の初期化が利用者より後に動く場合と、手動を忘れた場合を、落ちずに知らせる |
| AC-4 | コールバックと `release` のスレッド（D-6） | **main スレッド**。入口で拒んだときの `release` だけは呼び出しスレッドで同期 | 1.3。Android の API の多くが main に結び付いており、今の機能ごとのばらつき（README 1.3）を 1 つにできる |
| AC-5 | main を待たない、いつも積む（D-6 を改める） | **どの関数も main を待たない**。main で動かす処理は、**main から呼ばれた場合も**積んで、完了で返す。README D-6 の「main から呼ばれたときはその場で実行」を改めた（README も直した） | 1.3 の理由（Flutter・Unity でのデッドロック、どのスレッドから呼んでも同じ順序） |
| AC-6 | 登録と `release` の状態機械（D-6） | 5.7 の表。**C は登録を「有効」で作ってから受け口を呼ぶ。挿入と操作の開始は 1 つの main のメッセージ。`release` は 1 つの関数 `TryRelease` だけが呼び、状態を「解放済み」に CAS できたときだけ動く**。帳簿（ID → 登録）は main スレッドだけが、1 つの Handler の同期メッセージで触る | 受け付けの成否が C の側で分からないと `release` が 2 回か 0 回になる（R-C1）。呼ぶ場所が 2 つあると 2 回になる（S-C2） |
| AC-7 | Dialog の同期性（D-8） | **非同期だけ**（完了のコールバック）。Windows の Dialog（モーダルで呼び出しを塞ぐ）とは別の名前・形にする | AC-5。Dialog は main で出すので、塞ぐ形は main を待つことになる |
| AC-8 | 文字列の受け渡し | **Kotlin と C の間は UTF-8 の `ByteArray`（`jbyteArray`）で渡す**。JNI の `NewStringUTF` / `GetStringUTFChars`（Modified UTF-8）は使わない。変換の規則は 5.10 | Modified UTF-8 は NUL を 2 バイトで表し、BMP の外の文字をサロゲートの対で表すので、標準の UTF-8 と食い違う（README 8.6） |
| AC-9 | JNI の作法 | 5.6 の形 | README 8.6 |
| AC-10 | システムコード（D-13） | **`ntk_last_system_code()` も、非同期の完了の `system_code` の引数も、Android では常に 0**。失敗の詳細（Kotlin の例外のクラス名と、秘密を含まないメッセージ）は logcat（タグ `ntk`）に出す | Android の失敗は数値ではなく例外で来る。引数と関数の形は Windows と同じに持つ（R-X1）ので、後から値を入れても互換は保てる |
| AC-11 | `Common.h` の分け方と `NTK_VERSION`（README 3.3） | **`Common.h` は OS ごとに持ち、共通の宣言が一致することを 2a の照合で確かめる**（5.2）。`NTK_VERSION` は**その OS のライブラリの版**。Windows の側は変えない。**1 つの C# のバインディングは、`NTK_VERSION` を OS をまたいだ定数として持たず、OS ごとの期待値と実行時の `ntk_version()` を比べる** | 1 か所に置く形は、Windows の `.vcxproj`・ビルドスクリプト・Prefab の 3 つの取り込み方を変えることになる。`ntk_version()` はヘッダーとライブラリの組み合わせの食い違いを見つけるためのもの（R-X6） |
| AC-12 | ネイティブのビルド（D-10） | NDK r30（30.0.16248370）、CMake 3.31.6（`cmake_minimum_required(VERSION 3.22.1)`）、C++20、**`ANDROID_STL=none` で組み、NDK の `libc++_static.a` と `libc++abi.a` を手でリンク**、`-fvisibility=hidden`、version script で `ntk_*` と `JNI_OnLoad` だけを公開、native メソッドは `RegisterNatives` だけで結ぶ、16 KB のページ。**内部の関数・変数に `ntk_` で始まる名前を付けない**（version script の `ntk_*` で外に出るため） | 1a 3.2、3.3。`c++_static` のままでは Prefab で誰も取り込めない |
| AC-13 | 配布物と Prefab（D-9） | **1 つの AAR**（Kotlin の受け口、`jni/<abi>/libntk.so`、Prefab）。Prefab のパッケージ名とモジュール名は **`ntk`**（利用者は `find_package(ntk REQUIRED CONFIG)` と `ntk::ntk`）。パッケージ名は Gradle のプロジェクト名で決まるので、フォルダは `android_library_capi` のまま、プロジェクト名を `ntk` にする。AAR と Maven の名前は、ビルドスクリプトと `maven-publish` の publication で `android-native-toolkit-capi` にする | 1a 3.3。Maven の `artifactId` はプロジェクト名と別に決められる |
| AC-14 | GoogleTest | **v1.18.0 を `FetchContent` で取り込み（URL と SHA-256 で固定）**、テスト用の `.so` は `android_library_capi_test` に置く。**ケースごとに JUnit の 1 件として見せる**（ケースの一覧を native から受け取る Parameterized のランナー）。オフラインのビルドは `FETCHCONTENT_SOURCE_DIR_GOOGLETEST` で手元のソースを指す | 1a 3.4、3.5 |
| AC-15 | 機能ごとの Context と前面（README 8.6、D-7） | 5.8 の表。**操作ごとに**、Context と前面が要るかを決める。前面が要る操作の `NOT_FOREGROUND` は**必ず完了で返す**。前面の判定は C ABI の受け口で行う | 後ろからの Activity の起動は Android 10 以降で止められる。前面かどうかは main の上で変わるので、main で判定したものは完了でしか返せない（R-C7） |
| AC-16 | `JNI_OnLoad` | **冪等で、決して待たない**。C の表づくりのミューテックスを `try_lock` で取れたときだけ表を作り、取れなければ（ほかのスレッドが作っている）何もしない。成功した後の呼び出しは何もしない。失敗しても `JNI_ERR` は返さず、**例外を消してから** `JNI_VERSION_1_6` を返す。`JNI_OnLoad` の失敗は `FAILED` に数えない | 1a 3.2。利用者が自分の `.so` を `System.loadLibrary` すると、依存先の `JNI_OnLoad` がもう一度呼ばれる。待つと、起動中の main（`Runtime` のロックを持つ）と互いに待つ（S-C6） |
| AC-17 | 登録の ID | **Kotlin には使い回さない 64 ビットの ID（単調に増やす）を渡す**。C の登録は ID → 登録の表（ミューテックスで守る）で引く。利用者のハンドルは、解除を呼んだ時点で無効になる | 生のポインタを Kotlin に渡すと、番地の使い回し（ABA）と解放後の参照が起きる（R-C2） |
| AC-18 | コールバックの引数 | **値（整数、真偽値、列挙）か、所有権ごと渡すハンドル（利用者が `_free` する）だけ**を渡す。借りるポインタは渡さない。コールバックの戻り値はすべて `void` | Dart の `NativeCallable.listener` と Unity の UnityMain への受け渡しは、コールバックが戻った後に引数を読む（R-C4） |
| AC-19 | 出力の文字列の U+0000 | **U+FFFD に置き換える**（Windows の「途中に NUL は入らない」を保つ）。置き換えは損失を伴うのでヘッダーとマニュアルに書く | C の文字列として読む利用者と、`LPUTF8Str` のような既定のマーシャリングが途中で切れないようにする（R-C12） |
| AC-20 | R8 と `consumer-rules.pro`（README 8.6） | **JNI から名前で引くクラス（受け口、C から呼ぶメソッド、`RegisterNatives` の対象）を 1 つのパッケージ `com.jonghyunkim.nativetoolkit.capi.jni` にまとめ、`-keep class com.jonghyunkim.nativetoolkit.capi.jni.** { *; }` で守る**。JNI のシグネチャに出る型は、プラットフォームの型か `capi.jni` の中の型だけにする。C から static で引くメンバーは `@JvmStatic`。JNI から引くメンバーは Kotlin の `internal` にしない（JVM の名前が `name$<モジュール名>` に変わるため）。`NtkInitializer` は個別に keep する | 名前で引く対象をパッケージで閉じれば、足し忘れが起きにくい（R-X5、R-C26、S-C12） |
| AC-21 | 登録の種類 | **イベントの登録**（Clipboard の変更、通知のタップ・アクション・dismiss・shown、Chooser Action、Share の選ばれたアプリ）は、利用者が解除するまで生き、**ライブラリの側で解除・差し替えをしない**（同じ種類に複数を登録でき、それぞれに配る）。**完了つきの操作**（README 6 章の「操作の完了」と権限の要求）はハンドルを持たず、ライブラリの側で終わるときも必ず完了してから `release` する | ライブラリの側で登録を終わらせると、利用者の手元のハンドルが解放済みを指し、完了も抜ける（S-C3）。今のブリッジの `set*Listener`（1 つを差し替える）は、C ABI では足す・外す形にする |
| AC-22 | Share の結果 | **Share の「選ばれたアプリ」（今の `onShareResult`）はイベントの登録にし、イベントに要求の ID（Share を開く関数が出力引数で返す、使い回さない 64 ビットの ID）を付ける。** 今と同じく、届くのは直前に開いた Share の選択だけ（新しい Share は前の待ちを消す）。**どの Chooser から来た選択かを確かめるため、要求ごとに別の PendingIntent を作り（Intent の data の URI に要求の印を入れる。`filterEquals` が要求ごとに違うので、`FLAG_UPDATE_CURRENT` が前の要求の PendingIntent を上書きしない。extra だけに印を入れると上書きされて古い Chooser の結果にも新しい印が付くので、extra だけには頼らない）、受け取った broadcast の印が今の要求の印でなければ捨てる。** 待っている Share の取り消し（今の `cancelPendingShareCallback`）は要求の ID を取り、**その要求の「選択の待ち」**を取り消す（開く操作の完了とは別。今の要求でなければ何もしない。取り消した後、その要求の選択は届かない）。前面でなくて開かなかった Share（`NOT_FOREGROUND`）は、前の要求の待ちを消さない。Chooser を閉じたときは何も来ない。Share を開く操作の完了は「開けた／`NOT_FOREGROUND`／失敗」まで | Chooser を閉じたときは何も来ない（`ShareCallbackResultParser`）ので、完了にすると `release` が来ず `user_data` が漏れる（S-C4）。今の `ShareRepositoryImpl.shareWithCallback` は全要求で同じ action・request code・`FLAG_UPDATE_CURRENT` の PendingIntent を使うので、古い Chooser の選択が新しい要求に付いて届きうる（T-X3）。印で捨てるのは今の不具合の修正で、1b で行う（README の 1b の行に書いた） |
| AC-23 | 今のブリッジとの互換の原則 | **C ABI は 2.0.0 の新しい契約で、今のブリッジの振る舞いを 1 つずつ写さない。** 守るのは README 6 章の振る舞いの集合（操作、完了、自発のイベント、登録と解除、権限の要求）。ブリッジと違う点（イベントの登録は足す・外す形で差し替えが無い、前面が要る操作は後ろから呼ぶと `NOT_FOREGROUND` で完了する、など）は、第 2 部の対応表に「ブリッジ／C ABI／違いと理由」の列で書く。**Unity から見た動作は、2c で Unity の側の包みが保てるものは保ち（例: `set*Listener` の差し替え。C-6）、保てない違い（`NOT_FOREGROUND` など）は対応表と移行ガイドに書く** | 利用者の決定（2026-10-03）「Unity は C ABI を呼ぶので、Unity の側をそれに合わせて変える」（README 7.1 と 2c の行）。ブリッジの振る舞いを C ABI に写そうとすると、操作ごとに互換を決め直すことになり、レビューで同じ種類の指摘が続いた（T-X4、T-X6、T-X7）。1b の `android_library` の動作は変えない（4.1） |

### 4.3 不足前提

| ID | 不足している前提 | この設計書での扱い |
|---|---|---|
| G-1 | Kotlin の API の補完（イベントを保つ口、前面の Activity、予約の保存形式、Dialog と権限の要求の完了の契約）がまだ無い | この設計書は C ABI が求める条件を 9.1 に書き、中身は Kotlin の API の設計書に任せる |
| G-2 | Unity が `DllImport` した `.so` に `JNI_OnLoad` を呼ぶかは確かめていない（1a 4 章）。Startup が読み込んだ後に Unity・Flutter が `dlopen` で同じ `.so` を開いたとき、同じ実体になるかも確かめていない | 自動の初期化は Unity の読み込みより先に済むので、`JNI_OnLoad` が呼ばれても呼ばれなくても動く（AC-16）。同じ実体になることは、6 章のテスト（別の `.so` から `dlopen`）で確かめ、Unity の分は 2c で確かめる |
| G-3 | x86_64 は手元で動かせない（README 7 章） | 組めること、公開シンボル、16 KB の整列を確かめる。動かす確認は x86_64 のエミュレータを動かせる環境で行い、それまでは結果に「実行していない」と書く |

## 5. 実装アーキテクチャ

### 5.1 成果物とフォルダ

```
android/
  android_library/                      # Kotlin の API。C ABI のモジュールからは変えない（1b で、別の設計書に従って補完する）
  android_library_capi/                 # Gradle のプロジェクト名は :ntk（AC-13）
    build.gradle.kts                    # ndkVersion、externalNativeBuild、prefabPublishing、abiFilters、maven-publish
    consumer-rules.pro                  # AC-20
    src/main/AndroidManifest.xml        # InitializationProvider に NtkInitializer を足す
    src/main/cpp/
      CMakeLists.txt                    # AC-12
      libntk.map                        # global: ntk_*; JNI_OnLoad;  local: *;
      include/NativeToolkitC/
        Common.h  Android.h  Clipboard.h  Dialog.h  Notification.h  Share.h
      src/
        Common/                         # JNI_OnLoad と初期化、JNIEnv、クラスとメソッドの表、文字列とバイト列、
                                        # エラー、struct_size、登録の表（ID → 登録）
        Clipboard/  Dialog/  Notification/  Share/
    src/main/java/com/jonghyunkim/nativetoolkit/capi/
      NtkInitializer.kt                 # androidx.startup。LibraryInitializer に依存
      NativeToolkitCApi.kt              # 利用者の Kotlin が触る唯一の面
      jni/                              # JNI から名前で引くもの（AC-20）: 機能ごとの受け口、C へ戻す native メソッド、帳簿、前面の判定
  android_library_capi_test/            # GoogleTest のテスト用の .so と、ケースごとの JUnit のランナー（AC-14）
  android_library_capi_smoke/           # 配布物（m2/）だけで組む C のアプリ。R8 を有効にした release（6 章）
```

- 依存の向きは `android_library_capi` → `android_library` だけ。`android_library` は C ABI を知らない
- 公開シンボルは `JNI_OnLoad` と `ntk_*` だけ（`llvm-nm -D` で確かめる。README 9 章）

**利用者の Kotlin が触る面**（`NativeToolkitCApi`。これ以外は公開しない）:

| メンバー | 内容 |
|---|---|
| `init(context: Context): InitResult` | 手動の初期化（1.4）。待たない。結果は 5.3 の `InitResult` |
| `isAvailable: Boolean` | `libntk.so` を読み込めたか（32 ビットで入ったときは偽。5.3） |
| `isInitialized: Boolean` | `ntk_android_is_initialized` と同じ |

### 5.2 公開ヘッダー（AC-11）

| ヘッダー | 中身 |
|---|---|
| `Common.h` | Windows と共通の宣言（下の表）。Android の `NTK_VERSION_*` の値。`NTK_SYSTEM_CODE_*` は置かない（AC-10。Android では 0 しか返さない） |
| `Android.h` | `ntk_android_init`、`ntk_android_is_initialized`、`ntk_android_error`（1.4） |
| `Clipboard.h`、`Notification.h`、`Dialog.h`、`Share.h` | 機能ごと（第 2 部）。同じ意味の操作は Windows と同じ名前（`ntk_clipboard_copy_text` など）。Dialog は非同期だけで、Windows と名前を分ける（AC-7）。Share は Android が初めて作るので、OS に依存しない名前にする（README 3.3） |

**`Common.h` の OS 間の照合**（2a で `check_c_abi_contract.py` を OS ごとの一覧と OS 間の比べ合わせに分けるときの入力の決まり）:

| 区分 | 対象 | 照合 |
|---|---|---|
| 一致させる | 不完全型の宣言（`ntk_string`、`ntk_bytes`、`ntk_string_list`）、`ntk_release_fn`、`ntk_version`、`ntk_last_system_code`、`ntk_string_*`、`ntk_bytes_*`、`ntk_string_list_*` の宣言 | 空白とコメントを除いて同じ |
| OS ごとの展開 | `NTK_CALL` | Windows は MSVC で `__cdecl`、それ以外は空。Android は空 |
| 名前と計算だけ一致 | `NTK_VERSION_MAJOR` / `_MINOR` / `_PATCH` / `NTK_VERSION` | 名前があり、`NTK_VERSION` が 3 つから計算した値と同じ（値は OS ごと） |
| OS ごとに許す | `NTK_SYSTEM_CODE_*` | Windows だけに置いてよい（許す名前の一覧を照合スクリプトに持つ） |

照合スクリプトは、各 OS で宣言・不完全型・版・許す外の定数を 1 つずつ壊すと落ちることを、自分のテストで確かめる（2a）。

### 5.3 初期化の実装（AC-1、AC-2、AC-16）

**2 つの準備と 1 つの状態**:

| 準備 | 中身 | 守り方 |
|---|---|---|
| C の表 | JavaVM の保存、クラスを引く、`GetMethodID`、`RegisterNatives` | **C の表づくりだけを守るミューテックス**（`try_lock` だけで取る。取れたら状態を読み直してから作る）。ミューテックスを持ったまま Java の初期化を呼ばない |
| Kotlin の側 | Application の Context の保存、前面の Activity を追う仕組みの登録（`LibraryInitializer` と同じ関数）、`context` が Activity なら前面の初期値を main に積む | `android_library` の `LibraryRuntime.ensureInitialized(context)`（C を知らない）。`AtomicInteger` で **未着手 → 途中 → 済み** の 3 値を持ち、未着手を途中に CAS できた呼び出しだけが動かす。**途中で例外が起きたら、行った登録を戻してから「途中」を「未着手」に戻す**（やり直せる）。結果を `DONE` / `IN_PROGRESS` / `ERROR`（今回の呼び出しが失敗した。やり直せる）で返す。待たない。`LibraryInitializer.create` もこの関数を呼ぶ（Startup が後から動いても 2 回にならない） |

C の状態は `std::atomic<int>` で、遷移はすべて CAS で行う（戻る向きの遷移は無い。`READY` から下がらない）:

| 状態 | 意味 | 操作の戻り値 |
|---|---|---|
| `UNINIT` | C の表がまだ無い（やり直せる失敗の後を含む） | `NOT_INITIALIZED` |
| `NATIVE_READY` | C の表と `RegisterNatives` まで済んだ。Kotlin の側がまだ済んでいない | `NOT_INITIALIZED` |
| `READY` | 両方の準備が済んだ。使える | 通常どおり |
| `FAILED` | アプリのクラスローダーでもクラスが引けない（R8 の設定の誤りなど）。やり直しても直らない | `NOT_INITIALIZED` |

**`READY` を立てる規則**: Kotlin の側が済んだことを C に知らせるのは、**C ABI の側の 3 つの入口（`NtkInitializer.create`、`ntk_android_init`、`NativeToolkitCApi.init`）だけ**で、`ensureInitialized` が `DONE` を返すたびに（自分が済ませたか、すでに済んでいたかを問わず）native の `onKotlinReady()` を呼ぶ。`android_library` は知らせない（C を知らないため。`LibraryInitializer` が先に済ませた場合も、後から来る C ABI の側の入口が知らせる）。`onKotlinReady()` は何度呼んでもよく、呼んだ後の C の状態を返す（`READY` か、まだか）。`RegisterNatives` の前に呼ぶと `LinkageError` になるので、呼ぶ側が捕まえる。**C ABI の側の入口が `ensureInitialized` で `IN_PROGRESS` か `ERROR` を見たときは、`LibraryRuntime` に「済んだら呼ぶ」 Kotlin の関数を登録しておき（`android_library` は C を知らないまま、渡された Kotlin の関数を呼ぶだけ）、その関数が `onKotlinReady()` を呼ぶ**（既定の経路で、`LibraryInitializer` が途中のときに `NtkInitializer` が来ても `READY` に届くため）。C の 2 つの印と状態は `std::atomic` の既定（`seq_cst`）で読み書きする。C ABI の側から `ensureInitialized` を呼ぶのは `capi.jni` の受け口を通す（AC-20）。C は「C の表が済んだ」と「Kotlin の側が済んだ」の 2 つの印を持ち、**後から印を立てた側が `NATIVE_READY` → `READY` を CAS する**。どちらの順でも `READY` は 1 回だけ、両方が済んだ後にだけ立つ。

| 出来事 \ 状態 | `UNINIT` | `NATIVE_READY` | `READY` | `FAILED` |
|---|---|---|---|---|
| `JNI_OnLoad`（`System.loadLibrary` から。利用者の `.so` の読み込みで 2 回目も来る） | `try_lock`。取れたら状態を読み直し、`UNINIT` なら `FindClass` で表を作る。成功で `NATIVE_READY`（Kotlin の側の印が立っていれば `READY`）、失敗で例外を消して `UNINIT` のまま。取れなければ何もしない。どれも `JNI_VERSION_1_6` を返す | 何もしない | 何もしない | 何もしない |
| `ntk_android_init(env, context)` | `try_lock`。取れなければ `IN_PROGRESS`（`context` が Activity なら前面の初期値は積む）。取れたら状態を読み直し、`context.getClassLoader().loadClass(...)` で表を作る。クラスかメンバーが無い（`ClassNotFoundException`、`NoSuchMethodError`、`RegisterNatives` の名前の不一致）なら `FAILED` にして `CLASS_NOT_FOUND`。そのほかの JNI の失敗（メモリ不足など）なら `UNINIT` のまま `JNI_FAILURE`（やり直せる）。成功で `NATIVE_READY` にし、ミューテックスを外してから右の列へ | ミューテックスの外で `ensureInitialized(context)` を JNI で呼ぶ。`DONE` なら `onKotlinReady()` を呼んで（`READY` になる）`NONE`。`IN_PROGRESS` なら `IN_PROGRESS`。`ERROR` なら `JNI_FAILURE`（やり直せる） | `NONE`（何もしない。`context` も使わない） | `CLASS_NOT_FOUND` |
| `NtkInitializer.create(context)`（Startup） | `System.loadLibrary("ntk")`（→ `JNI_OnLoad`）。`UnsatisfiedLinkError` なら `isAvailable = false` で戻る。続けて `ensureInitialized(context)`。`DONE` なら `onKotlinReady()` を呼ぶ（`LinkageError` を捕まえる。捕まえたら、表がまだ無いとログを出して戻る） | `ensureInitialized(context)`。`DONE` なら `onKotlinReady()`（`READY` になる） | 何もしない | ログを出して戻る |
| `NativeToolkitCApi.init(context)`（Kotlin） | `NtkInitializer.create` と同じ。まず `Class.forName` で `capi.jni` のクラスがあるかを確かめ、無ければ `CLASS_NOT_FOUND`（R8 の規則の誤り。C と同じく直らない）。クラスはあるのに `onKotlinReady()` が `LinkageError` になったら（表がまだ無い）、`NATIVE_SETUP_REQUIRED` を返す。**Kotlin から C の表を作る口は無い**（`RegisterNatives` の前で、`Java_*` を公開していないため。`JNI_OnLoad` は ART が呼び直さない）ので、利用者は C の `ntk_android_init` を呼ぶ（ほかのスレッドがそれをしている最中なら、後で Kotlin の `init` を呼び直しても `INITIALIZED` になる） | `ensureInitialized` の結果に応じて、`DONE` なら `onKotlinReady()` を呼び、その戻り値（C の状態）が `READY` なら `INITIALIZED`、まだなら `IN_PROGRESS`。`IN_PROGRESS`、`ERROR` なら `RETRYABLE_ERROR` | `INITIALIZED` | `CLASS_NOT_FOUND` |

**`NativeToolkitCApi.init` の結果**（`enum class InitResult`）と C の戻り値の対応:

| `InitResult` | やり直せるか | C の `ntk_android_init` の同じ意味の値 |
|---|---|---|
| `INITIALIZED` | - | `NONE` |
| `IN_PROGRESS` | やり直せる（後でもう一度呼ぶ） | `IN_PROGRESS` |
| `RETRYABLE_ERROR` | やり直せる | `JNI_FAILURE` |
| `NATIVE_SETUP_REQUIRED` | Kotlin の `init` のやり直しだけでは直らない。C の `ntk_android_init` を呼ぶ | （C には無い。C は自分で表を作れる） |
| `CLASS_NOT_FOUND` | 直らない（AAR の組み込みか R8 の規則を直す） | `CLASS_NOT_FOUND` |
| `UNAVAILABLE` | 直らない（`libntk.so` が無い。32 ビットで入ったなど） | （C の関数そのものが無い） |


- **どの出来事も待たない**。`JNI_OnLoad` は `try_lock` に失敗しても待たない（起動中の main は `Runtime.loadLibrary` のロックを持って `JNI_OnLoad` に入るので、ここで待つとほかのスレッドと互いに待つ）
- **やり直しの約束**: `IN_PROGRESS` は「ほかのスレッドが準備している」なので、後でもう一度呼べばいずれ `NONE` になる（ほかのスレッドの準備が済むか、失敗して C の表が `UNINIT`・Kotlin の側が「未着手」に戻ったときに自分が準備するため。どの失敗も「途中」に残らない）。`JNI_FAILURE` / `RETRYABLE_ERROR` もやり直せる。`CLASS_NOT_FOUND` はやり直しても直らない（C の口も Kotlin の口も同じ値を返す）。`NATIVE_SETUP_REQUIRED` は C の `ntk_android_init` を呼べば直る。状態は `ntk_android_is_initialized()` でも確かめられる
- 手動の初期化が 2 つ同時に走っても、`context` が Activity なら、ミューテックスや Kotlin の側の CAS に負けた側も前面の初期値を積む（勝った側だけに任せると、Activity を渡した側の値が失われるため）
- 手動（C）の経路は `System.loadLibrary` も Startup の `AppInitializer` も呼ばない。`dlopen` だけで開かれた `libntk.so` は ART の読み込み済みの一覧に無いので、`System.loadLibrary` を呼ぶと `JNI_OnLoad` が入り直す。`RegisterNatives` は C の側から直接行えるので、`System.loadLibrary` は要らない
- `FAILED` にするのは、アプリのクラスローダーを持つ経路（`ntk_android_init` の `context.getClassLoader()`）でクラスが無いときだけ。`JNI_OnLoad` の失敗と、JNI の一時的な失敗は数えない
- **受け口のクラスには、`System.loadLibrary` を呼ぶ static 初期化子を置かない**（`GetStaticMethodID` がクラスを初期化するので、表づくりの中から入り直してしまう）
- 32 ビットで入ったアプリ: `libntk.so` が無いので `System.loadLibrary` が `UnsatisfiedLinkError` を投げる。`NtkInitializer` が捕まえてアプリを落とさない（`NativeToolkitCApi.isAvailable` が偽）
- `NtkInitializer` だけを外して `LibraryInitializer` を残したアプリでは、Kotlin の側は `LibraryInitializer` が `DONE` にしているが、C に知らせる入口が動かないので `READY` にならない。利用者は手動の初期化を呼ぶ（`ntk_android_init` は C の表を作り、`ensureInitialized` の `DONE` を見て `onKotlinReady()` を呼び、`NONE` を返す）
- **終わるときの解放**: JavaVM、グローバル参照、`pthread_key`、登録の表は、**プロセスが終わるまで持ち、解放しない**（5.5）

### 5.4 ビルドと R8（AC-12、AC-13、AC-20）

1a の雛形（`results/probes/stage1a/spike1a/capi/`）の形を本番に移す。

- `externalNativeBuild.cmake.arguments += "-DANDROID_STL=none"`
- `CMakeLists.txt` で `${ANDROID_TOOLCHAIN_ROOT}/sysroot/usr/include/c++/v1` を `SYSTEM PRIVATE` の include に足し、`usr/lib/<triple>/libc++_static.a` と `libc++abi.a` をリンクする。triple は `ANDROID_ABI` から決める（`arm64-v8a` → `aarch64-linux-android`、`x86_64` → `x86_64-linux-android`）
- `target_link_libraries(ntk PRIVATE ... log nativehelper)`（`JNI_GetCreatedJavaVMs` のため）
- `-Wl,--version-script=libntk.map`、`-Wl,-z,max-page-size=16384`
- Prefab の `abi.json` が `"stl": "none"` になることを、ビルドの確かめ（2b の DoD）に入れる
- `aarMetadata.minCompileSdk = 36`（0g と同じ）
- Kotlin の stdlib と Parcelize のランタイムの版は、`android_library` と同じく 2.2.21 にそろえる（1a 3.6。2b で `android_library` と一緒に入れる）
- `consumer-rules.pro`（AC-20）:
  ```
  -keep class com.jonghyunkim.nativetoolkit.capi.jni.** { *; }
  -keep class com.jonghyunkim.nativetoolkit.capi.NtkInitializer { <init>(); }
  ```

### 5.5 共有の状態とプロセスの終わり（R-C10）

- JavaVM、クラスとメソッドの表、初期化の状態、登録の表、`pthread_key` は、**`new` したまま解放しないシングルトン**にする。**静的なデストラクタを持つ変数を置かない**（`exit()` の中で静的なデストラクタが走ると、まだ動いている main や attach したスレッドが壊れた表を触って落ちる）。デストラクタを持つ `thread_local` も置かない（`exit()` を呼んだスレッドのぶんが走る）
- プロセスが終わるとき、完了も `release` も呼ばない（1.3）

### 5.6 JNI の作法（AC-9）

| 項目 | 規則 |
|---|---|
| `JNIEnv` の取得 | `vm->GetEnv`。取れなければ `AttachCurrentThread` し、そのスレッドを「自分で attach した」と `pthread_key` に記録する。**detach は、そのスレッドが終わるときに `pthread_key` のデストラクタで行う**。デストラクタの中では、まだ attach しているかを `GetEnv` で確かめてから detach する（利用者が自分で detach した場合）。利用者が attach したスレッドは detach しない |
| Go など OS のスレッドを渡る呼び出し元 | 呼び出しのたびに上の規則で `JNIEnv` を取るので、どのスレッドから呼ばれてもよい。attach したスレッドは、そのスレッドが終わるまで attach したまま |
| attach したスレッドのクラスローダー | ライブラリが attach したスレッドの context class loader はシステムのクラスローダーになる。Kotlin の受け口は `ServiceLoader` や context class loader に頼るリフレクションを使わない |
| クラスとメソッド | 初期化のときに `jclass` のグローバル参照と `jmethodID` を表に持ち、以後は引き直さない |
| 例外 | **例外を投げうる JNI の関数（メソッドの呼び出し、`FindClass`、`New*Array`、`Get*MethodID`、`RegisterNatives` など）を呼ぶたびに `ExceptionCheck` する**。例外があれば `ExceptionClear` し、クラス名を logcat に出して、機能のエラーの値（5.11）を返す。例外が残ったまま次の JNI を呼ばない |
| ローカル参照 | ライブラリが attach して Java に戻らないスレッド（Go、Dart の worker など）では、ローカル参照が溜まり続ける。**入口ごとに `PushLocalFrame` / `PopLocalFrame`（または RAII）で囲む** |
| 長さ | C の `size_t` の長さを `jsize` に変えるときは、`INT32_MAX` を超えたら入口で `INVALID_PARAMETER` にする |
| JNI から引くメンバー | AC-20 |

### 5.7 寿命と `release`（AC-6、AC-17、AC-21、AC-22）

**ハンドルの実体**:

| 種類 | 実体 |
|---|---|
| 出力のハンドル（`ntk_string`、`ntk_bytes`、`ntk_string_list` など） | C のヒープ。JNI の参照を持たない |
| ビルダー | C のヒープ。操作に渡すときに Kotlin の値（`ByteArray` と整数）へ変える |
| 登録（イベントの登録と、完了つきの操作の受け付け） | C のヒープの登録（関数ポインタ、`user_data`、`release`、原子的な状態、ID）と、Kotlin の側の帳簿（ID → 登録）の項目。**Kotlin には ID だけを渡し、C の登録はプロセスで唯一の表（ID → 登録。ミューテックスで守る）から引く**（AC-17）。Kotlin のオブジェクトを C がグローバル参照で持たない |

**登録の状態**（C の登録の `std::atomic<int>`）: `ACTIVE`（有効）、`CANCEL_REQUESTED`（解除の要求）、`RELEASED`（解放済み）。**`release` を呼び、C の表から外して解放するのは、1 つの関数 `TryRelease(登録, 期待する状態)` だけ。** この関数は、表のミューテックスの中で状態を `RELEASED` に CAS し、成功したときだけ表から外し、ミューテックスの外で `release(user_data)` を呼び、登録を解放する。下の表で「`TryRelease`」と書いた所は、すべてこの関数を呼ぶ。 完了つきの操作は、これとは別に **main だけが読み書きする「完了済み」の印**を持ち、完了を呼ぶのは印が立っていないときだけ（完了を呼んだら印を立てる）。

**受け付け**:

1. C の入口が検査を済ませ、登録を `ACTIVE` で作り、ID を付けて表に入れる
2. Kotlin の受け口を呼ぶ。受け口は例外を外へ出さず、**「挿入と操作の開始」を 1 つの Runnable にして main に `post` し、`post` したかどうかを戻り値で返す**（`post` の後には何もしない）
3. `post` した → 受け付けた（戻り値で受け付けを返す。要求の ID などの出力は、受け付けの前に取っておいた局所の写しから書く）。`post` していない（`post` が `false`、受け口の中の例外、JNI の失敗） → `TryRelease(ACTIVE)` を呼び出しスレッドで呼び、エラーを返す（入口で拒んだのと同じ。1.3）。このとき登録の ID はまだ利用者に渡っていないので、取り消しと重なることは無い
4. **受け付けに成功した後、呼び出しスレッドは登録に触れない**（main が完了して解放しているかもしれないため）。ID で登録を引くこと、状態の CAS、表から外すことは、すべて表のミューテックスの中で行う

**main の上の出来事**（すべて 1 つの `Handler(Looper.getMainLooper())` の同期メッセージ）:

| 出来事 \ 登録の状態 | `ACTIVE` | `CANCEL_REQUESTED` | `RELEASED` / 表に無い |
|---|---|---|---|
| 挿入と操作の開始（受け付けで積んだもの） | 帳簿に入れる。イベントの登録なら、保っていたイベント（K-7）をこのメッセージの中で配送する。完了つきの操作なら処理を始める（前面の判定、Dialog を出す、など） | 帳簿に入れず、操作も始めない（後から来る「外す」に任せる） | 何もしない |
| イベントの配送 | 呼ぶ直前に状態を確かめ、`ACTIVE` なら利用者の関数を呼ぶ | 呼ばない | 何もしない |
| 完了（完了つきの操作が結果を得た） | 完了を呼んで印を立てる → 帳簿から外す → `TryRelease(ACTIVE)`。失敗したら（完了を呼ぶ間に main 以外から取り消された）何もしない（後から来る「外す」が `TryRelease` する） | 印が無ければ完了を `CANCELED` で呼んで印を立てる（得た結果は捨てる）→ 帳簿から外す → `TryRelease(CANCEL_REQUESTED)` | 何もしない |
| 外す（解除・取り消しで積んだもの） | （起きない。解除は先に状態を `CANCEL_REQUESTED` にしてから積む） | 完了つきの操作で印が無ければ、完了を `CANCELED` で呼んで印を立てる → 帳簿から外す → `TryRelease(CANCEL_REQUESTED)` | 何もしない |

**解除**（イベントの登録の利用者の解除、完了つきの操作の取り消しの関数。どのスレッドからでも）:

- 表のミューテックスの中で ID（取り消し）かハンドル（解除）から登録を引き、`ACTIVE` → `CANCEL_REQUESTED` を CAS し、成功したら「外す」を main に積んで戻る（待たない）。登録が無い（完了の後、知らない ID）か CAS に失敗したら何もしない
- 「外す」を積む `post` は、Looper が終わったとき（プロセスの終わり）のほか、attach や Kotlin の呼び出しの失敗（記憶が足りないなど）でも失敗しうる。**失敗したら、状態は CANCEL_REQUESTED のまま登録に「積めなかった」の印を付け、main が次に C に入ったとき（外す、完了、配送、挿入の確かめ）に、印の付いた登録が無くなるまで外す**（印なので確保は要らない）。ACTIVE には戻さない（main がすでに CANCEL_REQUESTED を見て、完了や開始を見送っているかもしれないため。2b のレビュー v2 の R-X1）。**遅れに上限は無い**: どの登録についても main が C に入らなければ（受け手だけのアプリで何も起きないなど）、その間 `release` は来ない（レビュー v3 の S-M1）。プロセスが終わるときは外さず、`release` を呼ばない（1.3 の「プロセスの終わり」）。外すときには取り消しの完了と `release`（アプリのコード）が走るので、main の入口の中でアプリのコードが走りうる
- main から呼んだ場合も同じ。状態が `CANCEL_REQUESTED` になった時点で、以後の配送は呼ばれない（配送は呼ぶ直前に状態を確かめる）。これが 1.3 の「main から呼んだ解除は、その場で以後の配送を止める」
- main 以外から呼んだ場合、CAS より前に main で始まっていた配送は呼ばれる（1.3 の「`release` まで配送が来うる」）

**Share の選択の待ちの取り消し**（AC-22、1.3.1 の例外）: Share の「選択の待ち」は C の登録ではなく、Kotlin の側の `ShareCallbackCoordinator` が持つ「今の要求の印」である（開く操作の完了つきの登録は、開けた時点で完了して表から外れる）。選ばれたアプリはイベントの登録（ここまでの表のとおり）へ配る。待ちの取り消しは、要求の ID を受け口に渡し、受け口が main に「印が今の要求の印なら待ちを消す」を積んで戻る（待たない）。C の登録の表は引かないので、上の「取り消し」の規則（完了の後は何もしない）とは別である。印が今の要求でなければ何もしない。

**ライブラリの側で終わるもの**（AC-21）:

- イベントの登録は、ライブラリの側で解除・差し替えをしない。今のブリッジの `set*Listener`（1 つを差し替える）は、C ABI では足す・外す形にする（第 2 部）
- 完了つきの操作がライブラリの側で終わる（同時の要求で置き換えられた、Activity が破棄された、など）ときは、「完了」の行の処理を `CANCELED`（または決めた値）で行う。Kotlin の API の設計書は、終わるすべての場面で完了を出す（K-3）

- 帳簿の操作（挿入、配送、完了、外す）は、すべて 1 つの Handler の同期メッセージで積む。非同期メッセージ（`Handler.createAsync`）や `postAtFrontOfQueue` を混ぜない（積んだ順の前提が崩れる）
- 保っていたイベント（README 4、K-7）は、挿入と同じメッセージの中で配送するので、その後に積まれた新しいイベントより先に届く

### 5.8 Context と前面（AC-15、D-7）

**前面の定義**: `android_library` の前面の Activity を追う仕組みが、`ActivityLifecycleCallbacks` で追った次の Activity。**`onActivityStarted` の後で、`onActivityStopped` と `onActivitySaveInstanceState` のどちらもまだ来ておらず、`isFinishing` でない**もの。複数あれば最後に started になったもの。手動の初期化で渡された Activity は、main に積んで初期値にし、その Activity についてコールバックですでに状態を受け取っていればそちらを優先する（K-5）。判定は main の上で行う。透明な Activity を起動できるのも、この状態のとき（アプリに見えている画面があるとき）である。

| 操作 | 使う Context | 前面が要るか | 前面でないとき |
|---|---|---|---|
| Clipboard の書き込み・消去・問い合わせ（`hasClip` など） | Application | 要らない | - |
| Clipboard の読み取り | Application | **入力のフォーカス**が要る（Android 10 以降。既定の IME を除く） | 例外にならず、**「空」と同じ結果**になる（OS が `null` を返すため。空のクリップボードと区別できない）。契約に書く |
| Clipboard の変更の監視 | Application | 入力のフォーカスが要る | フォーカスが無い間の変更は届かない（OS が通知しない）。契約に書く |
| 通知の表示・更新・消去・予約・チャンネル | Application | 要らない | - |
| 通知の Progress の前景サービス（開始・更新・完了・停止） | Application | 要らない。ただし後ろからの前景サービスの起動は OS が止めることがある（Android 12 以降） | OS が止めたら `SERVICE_START_NOT_ALLOWED` を戻り値で返す（第 2 部 AP-14） |
| 通知の権限の問い合わせ | Application | 要らない | - |
| 通知の権限の要求 | まず Application で「API 32 以下」と「許可済み」を見る | **それ以外（未許可）のときは要る**（もう尋ねられない状態かどうかは、要求を出すまで分からないため） | API 32 以下か許可済みなら、main の上で結果つきで完了する（前面に関係なく）。未許可で前面でないなら `NOT_FOREGROUND` で完了する |
| Dialog | 前面の Activity（`FragmentActivity` でなければ透明な Activity。D-7） | 要る | `NOT_FOREGROUND` で完了する |
| Share の Chooser を開く操作 | **今と同じ形**（Application の Context と `FLAG_ACTIVITY_NEW_TASK`。`ShareUseCases` が `applicationContext` に変え、`ShareRepositoryImpl` が `NEW_TASK` を付ける） | 要る（後ろからの Activity の起動は止められるため） | `NOT_FOREGROUND` で完了する |
| Share の選ばれたアプリ | - | - | イベントの登録で受ける。イベントには要求の ID が付く。届くのは直前に開いた Share の選択だけ。Chooser を閉じたときは何も来ない（AC-22） |
| Direct Share の共有先の登録・削除 | Application | 要らない | - |
| 設定の画面を開く | **前面の Activity**（`FLAG_ACTIVITY_NEW_TASK` を付けない。今のブリッジは Unity から `currentActivity` を受け取り、Activity から開いている） | 要る | `NOT_FOREGROUND` で完了する |

- 前面が要る操作の `NOT_FOREGROUND` は、**呼び出しスレッドでは判定せず、main の上で判定して完了で返す**。戻り値は受け付けたことだけを表す（1.3）
- **前面の判定と `NOT_FOREGROUND` は、C ABI の受け口（`capi.jni`、2b で作る）が行う。** 1b の `android_library` の既存の API（Share の起動、設定の画面を開く処理など）の動作は変えない。前面の判定のために 1b が `android_library` に足すのは、前面の Activity を返す新しい口だけである（1b のほかの補完は README 4 章のとおり）。これで README の「1b はネイティブの利用者から見た動作を変えない」と両立する
- Chooser を今の形のまま開くのは、今のブリッジと 0c の UI テストの基準（Chooser は別のタスクで開く）に合わせるためである。設定の画面を前面の Activity から開くのは、Unity が今 `currentActivity` を渡していて、ゲームのタスクの中で開いているためである
- **今のブリッジとの違い**（AC-23。第 2 部の対応表に書く）: 今のブリッジは、Share と設定の画面で前面かどうかを確かめず、後ろから呼ぶと OS が起動を黙って止める。設定の画面は、渡された Context が Activity でなければ `NEW_TASK` で開く。C ABI は、どちらも前面が要る操作として `NOT_FOREGROUND` で完了する
- 前面の Activity を追う仕組みと透明な Activity の中身、権限の要求の Activity Result の登録（登録の時期の制約）は、Kotlin の API の設計書で決める（9.1）

### 5.9 コールバックの引数（AC-18）

- コールバックに渡すのは、**値（整数、真偽値、列挙、`system_code`）か、所有権ごと渡すハンドル（利用者が対応する `_free` を呼ぶ）だけ**。コールバックから戻った後も、ハンドルは利用者が解放するまで有効
- Windows の設計書 7.4 の「コールバックに渡されたハンドルは、コールバックから戻るまで有効」（借りるポインタ）は、Android では使わない
- コールバックの戻り値はすべて `void`（Dart の `NativeCallable.listener` は戻り値を持てない）
- 利用者がハンドルを解放し忘れた場合はメモリが漏れる。マニュアルの言語ごとの例に解放を書く

### 5.10 文字列とバイト列（AC-8、AC-19）

- C → Kotlin: C の入口で、**RFC 3629 の厳密な UTF-8** かを検査する（サロゲートを UTF-8 にした列 `ED A0 80`〜`ED BF BF`、過長の表現、U+10FFFF を超える値を拒む）。不正なら `INVALID_PARAMETER`。長さも検査して（5.6）、`jbyteArray` にして渡す。Kotlin の受け口で `ByteArray.decodeToString()`（検査済みなので置き換えは起きない）
- Kotlin → C: **受け口で明示的に変換する**。Android の `String.encodeToByteArray()`（`String.getBytes(UTF_8)`）は、対になっていないサロゲートを U+FFFD ではなく `?` に置き換えるので使わない。受け口の変換関数で、(1) 対になっていないサロゲートを U+FFFD に、(2) U+0000 を U+FFFD に置き換えてから UTF-8 にする（AC-19）。C で `ntk_string` に写す
- バイト列（画像など）は `jbyteArray` のまま渡す。大きなデータは `GetByteArrayRegion` で 1 回で写す
- `NewStringUTF` / `GetStringUTFChars` は使わない（Modified UTF-8）。JNI の `jstring` を使うのは、クラス名などライブラリの中の ASCII の名前だけ

### 5.11 エラーと例外（AC-10）

- 失敗しうる関数は、機能のエラーを戻り値で返す（1.1）。受け付けた後の失敗は完了の引数で返す（1.3）
- `ntk_last_system_code()` は、失敗しうる関数が戻るとき 0 にする。完了の `system_code` も 0（AC-10）
- 各機能のエラーに、少なくとも次の意味の値を持たせる（値は第 2 部）: `NONE`、`INVALID_PARAMETER`、`NOT_INITIALIZED`（AC-3）、`NOT_SUPPORTED`、`UNKNOWN`。完了つきの操作は `CANCELED`。Activity が要る操作は `NOT_FOREGROUND`、通知は `PERMISSION_DENIED`（表示・更新・過ぎた時刻の予約で、Kotlin は権限が無いか通知が無効でも黙って成功で戻るので、受け口が Kotlin を呼ぶ前に確かめて出す値。呼び出し時点の最善の努力。第 2 部 AP-16）
- C++ の例外はライブラリの入口で捕まえる（`std::bad_alloc` は `OUT_OF_MEMORY` か `UNKNOWN`）。Kotlin の例外は 5.6 のとおり JNI の境界で捕まえる
- **利用者のコールバックが例外を外へ出すと、プロセスが終わる。** `libntk.so` は libc++abi と unwinder の写しを中に持ち、利用者は別の写しを持つ。NDK はランタイムの写しをまたぐ例外を支えないので、ライブラリは捕まえない。コールバックを呼ぶ包みを `noexcept` にし、例外が届いたら `std::terminate` で確実に止める（壊れたまま走り続けない）。利用者は、コールバックの本体で例外を止める（1.3 の言語ごとの受け方）。Windows の設計書 7.7 の「包みが捕まえて捨てる」は Android では採らない（OS の違いとして `unity-native-plugin` に渡す対応表に書く）

### 5.12 ログ

- C / C++ のログは `__android_log_print`、タグは `ntk`。**引数の値のうち、秘密になりうるもの（クリップボードの本文、Dialog の入力、パスワード）は出さない**（README 8.6。`agent-rules/coding-rules/android.md` の「全パラメータの Log.d」の例外として、1b の前に規則を直す）
- 失敗したときは、関数名、機能のエラーの値、Kotlin の例外のクラス名を出す（AC-10）

## 6. テストの方針

| テスト | 置き場所 | 中身 |
|---|---|---|
| C ABI のテスト | `android_library_capi_test`（GoogleTest、AC-14） | 入口の検査（`NULL`、厳密な UTF-8 の 3 種の拒否、長さ、`struct_size` の規則）。`release` のちょうど 1 回: 入口で拒んだとき、受け口が `post` しなかったとき、受け付けた後、**main で登録して同じ回に main から解除したとき**、**off-main で登録した直後に main が完了を処理するとき（main をラッチで止めない）**、受け付けの直後に main 以外から解除したとき、解除と配送が重なるとき、コールバックの中の解除。完了のちょうど 1 回（取り消し、ライブラリの側で終わるときの `CANCELED`）。コールバック・完了・受け付けた後の `release` が main で来ること、main から呼んだときは戻った後に来ること（受け付けのスレッドごとに記録する）。文字列（NUL、BMP の外の文字、対になっていないサロゲートが EF BF BD になる、U+0000 が EF BF BD になる）。別のスレッドからの呼び出しと、スレッドが終わったときの detach（`Thread.getAllStackTraces()` に残らない） |
| 競合を決まった順で再現する | 同上 | main に「ラッチで止める Runnable」を積んで main を止め、その間に配送・解除・完了を積んでから放す。テスト専用の口（帳簿の件数、`release` の回数）を持つ。HWASan（arm64）と CheckJNI を有効にして流す |
| main を待たない | 同上 | main をラッチで止めた状態で、すべての公開の関数（`ntk_android_init` を含む）を別のスレッドから呼び、期限内に戻ることを確かめる（第 2 部の関数の一覧から作る） |
| 初期化の経路 | 経路ごとに別のプロセス（テストの APK を経路ごとに分けるか、AndroidX Test Orchestrator でテストごとにプロセスを分ける） | 未初期化の `NOT_INITIALIZED`、自動、手動（C）、手動（Kotlin）、**Startup を無効にして `dlopen` で開き `ntk_android_init` で初期化する経路**（`JNI_OnLoad` が入り直さないこと）、自動と手動の同時（バリアで競わせ、どちらも待たずに戻り、最後に `READY`）、**Kotlin の側の初期化をラッチで止めた間は `is_initialized` が 0 で操作が `NOT_INITIALIZED` になり、放すと `READY` になる**（早すぎる `READY` が無いこと）、`IN_PROGRESS` を受けた後にやり直すと `NONE` になる、**`NtkInitializer` だけを外して `LibraryInitializer` を残した構成**で `ntk_android_init` が `NONE` になる、`JNI_OnLoad` が失敗したときの Kotlin の `init` が `NATIVE_SETUP_REQUIRED` を返す、**Kotlin の側の初期化を途中で失敗させると「未着手」に戻り、やり直すと `NONE` / `INITIALIZED` になる**、C と Kotlin の口が同じ失敗に同じやり直しの可否を返す（R8 で名前を変えた版で、どちらも `CLASS_NOT_FOUND`）、`JNI_OnLoad` が失敗した後に Kotlin の `init` が `NATIVE_SETUP_REQUIRED` を返し、C の `ntk_android_init` で直る、既定の経路で `LibraryInitializer` が途中のときに `NtkInitializer` が来ても `READY` に届く、表づくりの失敗（keep の規則を外した版で、`System.loadLibrary` が投げないこと、アプリが落ちないこと、`is_initialized` が 0、`ntk_android_init` が `CLASS_NOT_FOUND`）、`JNI_OnLoad` が先に失敗した後に `ntk_android_init` で成功すること、手動の経路の後に Dialog が出ること、**Activity を渡した後で後ろへ回すと `NOT_FOREGROUND` になること** |
| 2 回目の `JNI_OnLoad` | 同上 | **自分の `JNI_OnLoad` を持たない小さな `.so`**（`libntk.so` に依存する）をテストの APK に入れて `System.loadLibrary` し、読み込みが成功し、状態が変わらないこと（1a 3.2） |
| 同じ実体 | 同上 | Startup が読み込んだ後に、別の `.so` から `dlopen("libntk.so")` で得た関数の `ntk_android_is_initialized` が 1 を返すこと（G-2） |
| イベントの登録と Share の結果 | C ABI のテストと UI テスト（2b） | 同じ種類に 2 つ登録すると両方に届き、片方を外すと残りにだけ届く。Share の選ばれたアプリのイベントに、開いた要求の ID が付く。2 回続けて開くと、前の要求の選択は届かない（**前の Chooser で後から選んでも、新しい要求の ID では届かない**）。前の要求の ID で取り消しても、新しい要求の待ちは消えない。今の要求の ID で取り消すと、その要求の選択は届かない（開く操作の完了はすでに来ている）。前面でなくて開かなかった Share は、前の要求の待ちを消さない。Chooser を閉じたときはイベントが来ず、開く操作の完了は 1 回だけ来る。完了つきの操作の、完了の後の取り消しと知らない ID の取り消しは何もしない（Share の選択の待ちの取り消しは除く。上のとおり、開く操作の完了の後でも、今の要求の ID なら待ちを消す） |
| 前面 | UI テスト（サンプル、2b） | 5.8 の表の操作を、前面と後ろの両方で呼び、表のとおりになること。後ろで呼ぶために、テスト専用の口（`exported="false"` の Receiver か Service、または instrumentation から呼ぶ口）でアプリを後ろに回したまま操作を起こし、結果を保存する。Clipboard は読み取りの前に値を入れておき、後ろでは「空」と同じになること、前面に戻すと読めることを確かめる |
| smoke | `android_library_capi_smoke` | `m2/` の AAR だけで組む C のアプリを、R8 を有効にした release で、STL なし・`c++_static`・`c++_shared` の 3 通りで組んで動かす（1a 3.3）。**自動の経路と、Startup を無効にして `ntk_android_init` で初期化する経路の両方**（AC-20）。CMake は `find_package(ntk REQUIRED CONFIG)` と `ntk::ntk` で書く |
| 配布物の名前 | 2b のビルドの確かめ | AAR の `prefab/prefab.json` の名前が `ntk`、モジュールが `ntk`、`abi.json` が `stl: none`、Maven のパスと POM の `artifactId` が `android-native-toolkit-capi`、直接配る AAR のファイル名 |
| R8 の規則を壊すと落ちる | 2b | `consumer-rules.pro` の keep を外した版で、smoke の初期化が失敗することを確かめる（規則が効いていることの確かめ） |
| Kotlin でコンパイルする利用者 | 2b | KGP 2.1.x と 2.2.x の小さなアプリが `m2/` から組めること（1a 3.6） |
| 32 ビット | README 7 章 | 32 ビットで入れたサンプルが落ちないこと |
| 公開面 | 2a の照合 | 公開シンボル、ヘッダー、付録 A、6 章の振る舞いの集合との対応表、`Common.h` の OS 間の照合（5.2。壊すと落ちることを含む）、`ntk_last_system_code()` と完了の `system_code` が 0 であること |
| `exit` の中で libntk が何も壊さない（終わりの登録を持たない） | 配布物の照合（`check_android_dist.py`。0.7） | 配る `libntk.so` が終わりの登録（`__cxa_atexit`、`atexit`、`__cxa_thread_atexit(_impl)`）を import していないこと。デストラクタを持つ静的な変数や `thread_local` が無ければ、`exit` の中で壊れた表を、まだ動いているスレッドが触ることは無い（5.5）。プロセスそのものが落ちないことは約束しない（C の `exit` は ART の JIT のスレッドを落としうる。0.7） |

**`test_android.sh` への接続**（2b の成果物）: `android_library_capi_test` と smoke のビルド・導入・実行、GoogleTest のケースを JUnit の 1 件ずつ結果の JSON の行に入れること、経路ごとのプロセスのテスト、前面のテストを、`test_android.sh` に足す。基準（`--baseline`）にもケースごとに入れる。

## 7. リスクと緩和策

| リスク | 緩和策 |
|---|---|
| `ANDROID_STL=none` で手でリンクする形が、NDK の版を上げたときに sysroot の配置の変化で壊れる | NDK の版を `ndkVersion` で固定する（AC-12）。上げるときは 2b の DoD（`abi.json` の `stl: none`、公開シンボル、3 通りの smoke）を流す |
| 利用者のアプリにも libc++ があり、例外や RTTI が `.so` の境界を越えると型が食い違う | C ABI の境界を C++ の型・例外が越えないことは Windows と同じ規則（1.1）。利用者のコールバックの例外は外へ出させない（5.11） |
| main のループが塞がれている（利用者が main で長い処理をしている）と、完了と `release` が遅れる | 規則として書く（1.3.2）。ライブラリが main を待たないので、止まりはしない |
| off-main から呼んだ操作の完了が、関数が戻る前に来うる（1.3）ことを利用者が読み落とす | ヘッダーの Doxygen とマニュアルの言語ごとの例に書く（対応付けは `user_data`）。C ABI のテストで確かめる |
| main 以外からの解除の後も `release` までは配送が来うる、という約束を利用者が読み落とす | 同上 |
| コールバックで受け取ったハンドルの解放を、利用者が忘れる（5.9） | マニュアルの言語ごとの例に書く |
| `IN_PROGRESS` を受けた利用者が、待つための仕組みを自分で作る | 自動の経路を既定にし、手動の経路は「`IN_PROGRESS` なら後でもう一度呼ぶ」をマニュアルの例に書く |
| R8 で Kotlin の受け口の名前が変わり、初期化でクラスを引けない | JNI から引くものを 1 つのパッケージにまとめて keep する（AC-20）。smoke を R8 を有効にした release で、両方の経路で組む |
| 後に続く文書が、この設計書の条件を満たさない | 9 章の条件を、Kotlin の API の設計書と第 2 部のレビューの観点にする |
| `FetchContent` がビルドのときにネットワークに取りに行く | SHA-256 で固定する。オフラインと CI は `FETCHCONTENT_SOURCE_DIR_GOOGLETEST` で手元のソースを指す（AC-14） |

## 8. 第 2 部に送るもの

- 機能ごとの関数、型、エラーの値（`NOT_INITIALIZED`、`NOT_FOREGROUND`、`CANCELED` などの値を含む）、同期・非同期の別（main を要しない処理は同期の関数で返してよい。common.md の「システム API に合わせた同期・非同期設計」）
- README 6 章の振る舞いの集合との対応表（操作 45、完了、自発のイベント、登録と解除、権限の要求）と、今のブリッジのメソッド 69 との対応。各操作を「同期の結果」「受け付けた後の完了」「イベントの登録」のどれにするかを、同じ ID で示す。**列に「ブリッジの振る舞い」「C ABI の振る舞い」「違いと理由」「Unity の包みが保つこと」を持たせる**（AC-23）。2a の機械照合は、この表から操作・完了・イベントの数と種類を導き、ヘッダーと照らす
- 付録 A の全宣言（`Common.h` は 5.2 の照合の形で）
- `unity-native-plugin` に渡す対応表の範囲（Runtime テストの約 60 件の JSON のテストの扱い、コールバックの例外の OS の違い）

## 9. 後に続く文書に任せる条件

### 9.1 Kotlin の API の補完の設計書（1b の前）

`android_library` に足す口が満たすこと。この設計書のレビューの観点にもする。

| # | 条件 | この設計書の節 |
|---|---|---|
| K-1 | イベントの元（Receiver、監視）は、イベントを main に積める形で C ABI の受け口へ渡せる（受け口が帳簿を引いて配送する。5.7） | 5.7 |
| K-2 | 配送の間、利用者のコールバックから届きうるロックを持たない | 1.1 |
| K-3 | **README 6 章の「操作の完了」のすべてと通知の権限の要求**は、プロセスが生きている限りちょうど 1 回完了できる。画面の回転、透明な Activity の破棄、権限のダイアログの消滅、同時の要求による置き換えなど、ライブラリの側で終わるすべての場面で完了（`CANCELED` などの値）を出す。同時の要求を待たせるか断るか（README D-7）も決める | 1.3、5.7 |
| K-4 | Share の選ばれたアプリを、要求の ID と一緒に C ABI の受け口へ渡せる形にする。新しい Share が前の待ちを消す今の振る舞いは変えない。要求ごとに別の PendingIntent（data の URI に要求の印）を作り、受け取った broadcast の印が今の要求でなければ捨てる（今の不具合の修正。extra だけでは `FLAG_UPDATE_CURRENT` に上書きされる）。待っている Share の取り消しは要求の印を取り、今の要求でなければ何もしない | AC-22 |
| K-5 | 前面の Activity を追う仕組みが、5.8 の「前面」の定義の Activity を返し、無ければ無いと返す。手動の初期化で渡された Activity を main に積んで初期値にでき、コールバックで受け取った状態を優先する | 1.4、5.8 |
| K-6 | 通知の権限の要求は、「API 32 以下」と「許可済み」だけを Application の Context で判定する。画面が要るときの Activity Result の登録は、登録の時期の制約（Activity / Fragment の作成の前）を満たす形にする（前面が `FragmentActivity` なら後から足す Fragment、違えば透明な Activity） | 5.8 |
| K-7 | 保っていたイベント（README 4）は、C ABI の受け口が挿入のメッセージの中で受け取れる形にする。複数の登録があるときに誰に渡すかを決める | 5.7 |
| K-8 | `LibraryInitializer` の初期化は、手動の経路からも呼べる「1 回だけ動き、待たない」関数（`LibraryRuntime.ensureInitialized`）にし、未着手・途中・済みの 3 値を持ち、結果（`DONE` / `IN_PROGRESS` / `ERROR`）を返す。失敗したら行った登録を戻して「未着手」に戻す。C を知らない（C に知らせるのは C ABI の側） | 1.4、5.3 |
| K-9 | 1b で `android_library` の既存の API の動作を変えない（前面の判定は C ABI の受け口が行う） | 4.1、5.8 |

### 9.2 第 2 部と 2b（C ABI の受け口）

`android_library_capi` の Kotlin の受け口（`capi.jni`）と C の実装が満たすこと。

| # | 条件 | この設計書の節 |
|---|---|---|
| C-1 | 受け口は例外を外へ出さず、「挿入と操作の開始」を 1 つの Runnable にして `post` し、`post` したかどうかを返す | 5.7 |
| C-2 | Kotlin → C の文字列は 5.10 の変換関数（対になっていないサロゲートと U+0000 を U+FFFD に）を通す | 5.10 |
| C-3 | JNI から名前で引くクラスとメソッドは `capi.jni` に置き、シグネチャの型・`@JvmStatic`・`internal` の規則を守る | AC-20 |
| C-4 | 前面の判定と `NOT_FOREGROUND` の完了は受け口が main の上で行う | 5.8 |
| C-5 | `test_android.sh` に C ABI のテスト・smoke・経路ごとのプロセス・前面のテストをつなぐ | 6 章 |
| C-6 | 2c の Unity の包みは、今の `set*Listener` / `clear*Listener` の差し替えの振る舞いを、種類ごとに 1 つのハンドルと「今のハンドル」の印で表す。差し替えでは今のハンドルを外してから新しく足し、**配送を受けたときに、そのハンドルが今のハンドルでなければ捨てる**（main 以外からの解除の後も `release` までは前の受け手に配送が来うるため）。この判定は、包みが受け取った配送を UnityMain へ渡した後に、UnityMain で行う（「今のハンドル」を書き換えるのも UnityMain なので）。Unity のテストで、2 回目の `set` の後は前の受け手に届かないことを確かめる | AC-23 |
