# レビュー結果（段階 2b の実装・2 回目）

- 日付: 2026-10-10
- レビュー対象: `372ba3d6`（1 回目のレビューの対処。`git diff e4d8fcd8 372ba3d6`）
- 1 回目: `reviews/2026-10-10-android-c-abi-stage2b-review-v1.md`
- レビュアー: 3 本。直したところが 1 回目と同じ 3 つの観点にまたがるので、同じ 3 本にした
  - Claude のサブエージェント 1（設計との一致）
  - Claude のサブエージェント 2（メモリとスレッド、寿命）
  - Codex（不具合と、確かめずに通るテストや照合）
- 総合評価: **要修正（重大）**（A が 3 件）

ID の `R-C` は Claude 1、`R-M` は Claude 2、`R-X` は Codex。区分は 1 回目と同じ。

## 確かめて合っていたこと

- release がちょうど 1 回であること（受け付けた後に呼ぶのは `TryRelease` だけ）、Cancel が解放済みの登録に触れないこと、取り消しの種類（8 つの呼び手）（R-M）
- 入口の順（引数が先、初期化が後）は 4 機能のすべての入口でそろっている。OP-19/39/51 は初期化の前に `NONE`。AP-16 の追記は実装と合う。付録 A の 12 の構造体の欄は `offsetof` の集合と一致する（R-C）
- `LocalFrame` の確かめの数（33）と、確かめない 12 か所がローカル参照を作らないこと。`TakeException`、`BuildTable`、Dialog の `ReadText`、`unique_ptr` への置き換え、`MainTasks`、`ThreadTest` の JNI（R-M）
- `test_android.sh` の `FULL_RUN` と消えたケースの扱い、`capi-dist-selftest` の終了の値（R-X）

## 区分 A

| ID | 問題 | 対処 |
|---|---|---|
| R-X1（R-M1、R-M2、R-M3、R-M4、R-M5、R-C4、R-C5 と同じ根） | K-M2 の「解除を積めなかったら ACTIVE に戻す」は、main と競うと `release` が呼ばれない道を作る。main の完了が CANCEL_REQUESTED を見て取り消しの完了を出した後に ACTIVE に戻ると、解放されない（直す前より悪い。R-M1）。結果を渡した後に戻っても同じ（R-M2）。挿入が CANCEL_REQUESTED を見て開始を見送った後に戻ると、完了が永久に来ない（R-M3）。戻すまでの間の 2 本目の取り消しが黙って失われる（R-M4）。OP-19/39 は積めなかったときも `NONE` を返す（R-C4）。実際の経路で確かめるテストが無い（R-M5） | ACTIVE に戻すのをやめる。CANCEL_REQUESTED のまま「積めなかった解除」の列に入れ、main が次に C に入ったとき（解除、完了、配送、挿入の確かめ）にその列を流して外す。取り消しはどの場合も受け付けたことになる（OP-19/39 の `NONE` は正しくなる）。デバッグのプローブに「次の解除の post を失敗させる」口を足し、取り消し → 完了、解除 → イベントの順で、完了と `release` がちょうど 1 回であることを確かめる |
| R-X2（R-C7） | `check_android_dist.py` の `imports()` が readelf の終了の値を見ない。読めなければ空の集合になり、「終わりの登録が無い」を確かめずに通す | 終了の値が 0 でなければ失敗にする。必ずある import（`__android_log_print`）が無ければ失敗にする。自己テストに、`--dyn-syms` だけ失敗する readelf と、`__cxa_atexit` の名前そのものの import を足す |
| R-X3 | `module_dependencies()` が依存の無い variant を落とす。capi の API の variant から `kotlin-stdlib` を消して空にしても、ほかの variant があれば通る | 依存の無い variant も返し、すべての variant に `kotlin-stdlib` を求める。capi の API の variant だけを空にする自己テストを足す |

## 区分 B

| ID | 問題 | 対処 |
|---|---|---|
| R-X4 | jni/ の ABI の組を `libntk.so` からだけ作るので、`jni/armeabi-v7a/libother.so` を見逃す | jni/ の下のすべての `.so` から ABI の組を作る。自己テストを足す |
| R-M6（R-C6） | `ntk_android_init` → `EnsureInitializedWithoutTable` → `LoadClass` の `std::string` が try の外で、`bad_alloc` が C の入口を越える | `EnsureInitializedWithoutTable` を try / catch で囲む |
| R-C1 | 第 1 部の 1 章の表・初期化の節・AC-3、第 2 部 3.1 に「未初期化ではすべての操作が `NOT_INITIALIZED`」が残り、11 章の例外（取り消しの `NONE`、引数が先）と食い違う | 4 か所に 11 章の例外を書く |
| R-C2 | 「初期化の前に不正な引数なら `INVALID_PARAMETER`」を確かめるテストが無い | 初期化の前の操作のテストに、機能ごとの不正な引数を足す。12.1 の未初期化の行に書く |

## 区分 C

| ID | 問題 | 対処 |
|---|---|---|
| R-C3 | 11 章が、初期化より先に確かめるものを `INVALID_PARAMETER` の種類だけに書いている。AP-19 の入口の値（件数 0、Chooser Action、アイコン、`NOT_SUPPORTED`）も先 | 「AP-19 の入口の検査すべて」と書く |
| R-C8 | `thread_local` のデストラクタは `__cxa_thread_atexit_impl` で登録され、照合の外 | 照合の名前に足す。第 1 部 5.5 に書く |
| R-C9 | 第 1 部 6 章の行の名前「`exit` で落ちない」は、照合が確かめること（libntk が終わりに何も走らせない）より広い | 行の名前を直す |
| R-C10 | K-X1 の失敗は `--include-host` ありで `--filter` と `--skip-unit` が無いときだけ効くことが、文書に無い | 2 つの文書に書く |
| R-C11、R-M8 | 受け手の追加のフレームの確かめが、Share だけにあってそろっていない。確かめない 12 か所の分け方が文書で違う | 受け付ける（`Accept` を呼ぶ）入口はすべて確かめる。確かめないのは取り消し、プローブの finish と emit、`PostRemove` だけにして、文書を直す |
| R-C12 | 自己テストを足した件数（exit の 1 件）がレビューの文書に無い | 書く |
| R-C13 | `Thread.AThreadDetachedByHand...` は、`DetachOnThreadExit` の `GetEnv` の確かめを消しても通るかもしれない | 変異で確かめる。生き残れば主張を弱める |
| R-M7 | `NtkRuntime` で `applicationContext` が null だと、後で NPE になり `notifyKotlinReady` が呼ばれない | null を許し、`notifyKotlinReady` を必ず呼ぶ |
| R-M9 | CANCEL_REQUESTED の間のイベントは捨てられる。ACTIVE に戻すと失われたまま | R-X1 の対処で戻さなくなるので、取り消した受け手には届かないことになり、問題でなくなる |
| R-M10 | `Ledger.kt` と `Registry.h` の注記が古い（積めないのは looper の終わりだけ、など） | 直す |
| R-M11 | Share の Chooser Action の重複の確かめは件数の 2 乗 | 記録する（かかるのは CPU だけ） |
| R-M12 | テストの補助（`CurrentJavaThreadId`、`JavaThreadAlive`）が JNI の失敗を見ない | null を見る |

## 対処の結果

すべて対処した。表の「対処」と違う形にしたものと、対処で分かったことだけを書く。

| ID | 結果 |
|---|---|
| R-X1（ほか 7 件） | `Registry::Cancel` は、解除を積めなかったら CANCEL_REQUESTED のまま列に入れて `true` を返す。main の入口（`Ledger.nativeRemove`、`nativeIsActive`、`CompleteOnMain`、`DeliverOnMain`）が先に列を流し、Kotlin の帳簿からも外す（`Ledger.drop`）。列に入れることもできない（記憶が二重に足りない）ときだけ、登録は解放されないまま残る（ログに出す）。プロセスが終わるときは列が流れない（第 1 部 1.3 の「プロセスの終わり」のとおり）。デバッグのプローブに `ntk_debug_probe_fail_next_remove_post` を足し、ProbeTest に 4 件足した。Registry のテスト（ledger の無い写し）は、競合のテストを元の主張（ちょうど 1 回の勝ち）に戻し、積めなかった取り消しが main の次の入口で解放される 1 件に置き換えた |
| R-X2 | 表のとおり。必ずある import は `__cxa_finalize`（crtbegin がどの `.so` にも入れる）にした。ログの関数はログの作りに依るため |
| R-X3、R-X4、R-C8 | 表のとおり。AAR を出す variant は、ファイルに `.aar` を持つもの（API と runtime） |
| R-M6 | 表のとおり |
| R-M7 | null のときは渡された Context そのものを持つ（Application ができる前の Context は Activity ではない）。後で `keepApplication` がその `applicationContext` を読み、`notifyKotlinReady` も必ず呼ぶ |
| R-C1、R-C3 | 第 1 部の 1 章の表、1.4、AC-3 と第 2 部 3.1 に例外を書き、11 章を入口の検査のすべてに広げた |
| R-C2 | `operationsUninitialized` に 7 件足した（Clipboard の不正な UTF-8 と件数 0、通知の不正な tag・channel と出力の `NULL`、Dialog の `struct_size` 0、Share のファイル 0 件）。非同期の 2 件は `release` が呼び出しスレッドで 1 回 |
| R-C9 | 行の名前を「`exit` の中で libntk が何も壊さない（終わりの登録を持たない）」にし、プロセスが落ちないことは約束しないと書いた |
| R-C10 | v1 の文書の K-X1 の行と結果の文書に、効く条件（`--include-host` あり、`--filter` と `--skip-unit` なし）を書いた |
| R-C11、R-M8 | 受け付ける入口はすべてフレームを確かめる（39 か所）。確かめないのは 6 か所（取り消し 2、`cancel_selection`、プローブの finish と emit、`PostRemove`）。v1 の文書の K-C8 の行を直した |
| R-C12 | v1 の文書の K-C5 の行に書いた |
| R-C13 | 変異（`GetEnv` の確かめを外す）でテストは通った。ART は attach していないスレッドの detach に `JNI_ERR` を返すだけなので、区別できない。テストの注記を「静かに終わる」までに弱め、結果の文書にも書いた。確かめそのものは残す（ほかの VM や将来の ART に備える） |
| R-M9 | 戻さなくなったので、取り消した受け手には CANCEL_REQUESTED の間のイベントも届かないのが正しい振る舞いになった |
| R-M10 | `Ledger.kt` と `Registry.h` の注記を直した |
| R-M11 | 結果の文書の 8 章に書いた |
| R-M12 | 1 段ずつ確かめ、途中の失敗は -1 か「生きている」（ケースの失敗）にする |

## 対処の後の確かめ

関係するテストだけを Pixel 6a（API 36）で流した。

- startup の Probe・Registry・Thread の 25 件、noStartup の 17 件、noNtkInitializer の 3 件がすべて通った
- 照合の自己テストは 23 件が通った。足した 4 件のうち 3 件は、直す前の照合では落ちることを確かめた（残りの 1 件は `__cxa_atexit` の名前そのもので、直す前の照合でも捕まる）
- 変異:
  - 積めなかった解除を流さない: 挿入の前の取り消し、受け手の解除、Registry の 1 件が落ちた。結果と完了が先に積まれた 2 件は通った（完了の側が CANCEL_REQUESTED を見て自分で解放する）
  - 前の形（ACTIVE に戻す）: ProbeTest の 4 件のうち 3 件が落ちた。残りの 1 件（結果が先に積まれた形）は、テストの中の 2 回目の取り消しが前の形の穴を埋めていたので、外して流し直し、落ちることを確かめた
  - `GetEnv` の確かめを外す: 生き残った（R-C13）
