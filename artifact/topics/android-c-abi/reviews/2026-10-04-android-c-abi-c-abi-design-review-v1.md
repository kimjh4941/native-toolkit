# レビュー結果（C ABI の設計書 第 1 部・1 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-c-abi-design.md`（第 1 版）
- トピック名: android-c-abi（C ABI の設計書 第 1 部: スレッド・寿命・Context）
- 対象 OS: Android 12（API 31）以降、`arm64-v8a` と `x86_64`
- 判定: **要修正**（区分 A が 21 件。第 2 版で全件を反映した。2 回目のレビューで確かめる）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェント（JNI・スレッド・寿命の観点）と Codex（企画書・1a・Windows との整合の観点）の 2 者で並行）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0（表の列数と見出しの順が OK。ほかは対象外で SKIP）

区分は README のレビューと同じ（A = このまま作ると動作・API・契約が変わる。B = 中心の契約の確かめ方の抜け。C = 記述）。ID の `R-C` は Claude、`R-X` は Codex。

## 強み

- スレッドの規則を「どのスレッドからでも呼べる」「main を待たない」「完了・イベント・`release` は main」「開始した関数の中では呼ばない」にまとめ、Flutter と Unity での理由まで書いている。README 1.3 の機能ごとのばらつきを 1 つの規則で消す方針は正しい（両方）
- 登録の帳簿を main スレッドだけで触る形は、Windows の解放ガードと生存フラグより単純に競合を消せる（Claude）
- C が Kotlin のオブジェクトをグローバル参照で持たないので、GC と C の解放の 2 つの寿命が混ざらない（Claude）
- 1a の 3 つの発見（`ANDROID_STL=none` と手でリンクする libc++、`JNI_OnLoad` の冪等、stdlib 2.2.21）と Prefab の名前を取り込んでいる（両方）
- Modified UTF-8 を通らない（両方）。AC-13 の `:ntk` と Maven の `artifactId` の併存は実現できる（Codex）

## 区分 A

| ID | 問題 | 出典 | 対処（第 2 版） |
|---|---|---|---|
| R-C1 | 受け付けの成立点が無い。JNI の呼び出しが例外つきで戻ると `post` が済んだか分からず、`release` が 2 回か 0 回になる。帳簿の操作が同じ Handler の同期メッセージで積まれる前提が書かれていない | Claude | 受け付けの成立点を「受け口が正常に戻った時点」とし、受け口は `post` を最後に行う。C の登録に原子的な状態（受け付け中・有効・解除の要求・解放済み）を持たせ、帳簿への挿入のときに解除の要求を見たらその場で `release`。帳簿の操作は 1 つの Handler の同期メッセージだけ（5.7、AC-6、K-1、K-4） |
| R-C2 | Kotlin が C の登録を生のポインタで指すので、ABA と 2 回目の解除の use-after-free が起きる | Claude | Kotlin には使い回さない 64 ビットの ID を渡し、C は ID → 登録の表で引く。利用者のハンドルは解除で無効（AC-17、5.7） |
| R-C3 | 解除の後に配送が来るかが 3 か所で食い違い、状態図が FIFO と逆 | Claude | main から呼んだ解除はその場で以後の配送を止め、main 以外からの解除は `release` まで来うる、に統一。状態図を直した（1.3、5.7） |
| R-X2 | 同上と、2 回目の解除が解放済みの登録に触れる | Codex | 同上。2 回目の解除は呼ばない契約にした（1.3.1、AC-17） |
| R-C4 | 引き継いだ「借りるポインタ」が、Dart の `NativeCallable.listener`（呼び出し元が先に戻る）と両立しない | Claude | コールバックの引数は値か、所有権ごと渡すハンドルだけ。戻り値は `void`（5.9、AC-18） |
| R-C5 | 初期化の失敗の後（やり直せるか）、`PREPARING` と失敗の状態での `ntk_android_init` の戻り値、`JNI_OnLoad` と手動の同時、`<clinit>` からの入り直しのデッドロック、`JNI_OnLoad` に残った例外、`RegisterNatives` の失敗の後の `nativeInit` による落ち、終わるときの解放が決まっていない | Claude | 状態（`UNINIT`・`PREPARING`・`READY`・`FAILED`）と戻り値の表、クラスローダーを引数に取る 1 つの準備の関数とミューテックス、入り直しの `REENTERED`、例外の消去、`LinkageError` の捕捉、`<clinit>` の禁止、解放しないこと（5.3、AC-16） |
| R-X8 | `call_once` の対象と失敗の後の状態が矛盾 | Codex | 同上 |
| R-C6 | 手動の経路では前面の Activity を追う仕組みが動かず、渡された Activity も使われない（README D-4 の決定が抜けた） | Claude | 手動の経路も `AppInitializer.initializeComponent` で Startup の部品を動かし、Activity を前面の初期値にする（1.4、5.3、K-5） |
| R-C7 | `NOT_FOREGROUND` を戻り値で返すか完了で返すかと、「前面」の定義が無い | Claude | 前面が要る操作の `NOT_FOREGROUND` は main で判定して必ず完了で返す。「前面」を定義した（1.3、5.8、AC-15） |
| R-C8 | フォーカスの無い Clipboard の読み取りは例外ではなく `null`（`ClipboardRepositoryImpl.kt:30-39`） | Claude | 「空」と同じ結果、変更の監視はフォーカスが無い間は届かない、を契約にした（5.8） |
| R-C9 | 受け付けた操作が必ず 1 回完了する保証が無い（画面の回転で Fragment の listener が消える。README 1.4） | Claude | 生きている間はちょうど 1 回完了し、途中で消えたら `CANCELED`（1.3、K-3） |
| R-C10 | プロセスの終わりと静的なデストラクタが決まっていない | Claude | プロセスが終わるときは完了も `release` も呼ばない。共有の状態は解放しないシングルトン（1.3、5.5） |
| R-C11 | Android の `String.encodeToByteArray()` は対になっていないサロゲートを `?` に置き換える（`String.java:1188-1197`、android-34） | Claude | 受け口で明示的に U+FFFD に置き換える（5.10、K-8） |
| R-C12 | 出力の途中に U+0000 が入りうるので、引き継いだ「途中に NUL は入らない」が破れる | Claude | U+0000 を U+FFFD に置き換える（AC-19、5.10） |
| R-C13 | 利用者のコールバックの C++ の例外は、libc++ の写しが別なので捕まえられない | Claude | コールバックは例外を投げてはならず、包みは `noexcept`（投げたら `std::terminate`）。Windows の「捕まえて捨てる」は採らない（5.11） |
| R-X1 | 非同期の完了の `system_code` の引数（Windows の E-18）が引き継ぎに無い | Codex | 引き継ぎの表に入れ、Android では常に 0（1.1、AC-10） |
| R-X3 | Share の画面を出さない操作（Direct Share の登録・削除、取り消し）まで前面が必須。Chooser の起動の Context が今と変わる | Codex | 操作ごとに分け、Chooser は今の起動の形（Application と `NEW_TASK`）を保つ（5.8） |
| R-X4 | 通知の権限の要求も、画面の要らない経路まで前面が必須。Activity Result の登録の時期の制約 | Codex | 状態を先に見て、画面が要るときだけ前面を求める。登録の時期は Kotlin の API の設計書の条件にした（5.8、K-6） |
| R-X5 | `consumer-rules.pro` の中身が決まっていない | Codex | JNI から引くものを 1 つのパッケージにまとめて keep する（AC-20、5.4） |
| R-X6 | 1 つの C# のバインディングで、OS ごとの版の定数をどう表すかが無い | Codex | バインディングは OS ごとの期待値と `ntk_version()` を比べる（AC-11） |
| R-X7 | main から呼ばれたとき、README D-6 は「その場で実行」、設計書は「積む」 | Codex | いつも積む、に決め、D-6 を改めたことを書いた（1.3、AC-5） |

## 区分 B

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| R-X9 | 完了・`release` が main で、開始した関数の中で来ないことを直接確かめていない | Codex | 6 章の C ABI のテストに、受け付けのスレッドごとの記録を足した |
| R-X10 | 5.8 の表の確かめが無い | Codex | 6 章に「前面」の UI テストを足した（1b） |
| R-X11 | `Common.h` の OS 間の照合の決まりが無い | Codex | 5.2 に照合の区分の表を書いた（実装は 2a） |
| R-X12 | Prefab・Maven・AAR の名前を確かめる項目が無い | Codex | 6 章に「配布物の名前」を足した |
| R-X13、R-C14 | 初期化の同時・失敗・やり直しを確かめない。経路ごとにプロセスを分ける必要がある | 両方 | 6 章の「初期化の経路」を経路ごとのプロセスにし、同時・失敗・やり直し・入り直しを足した |
| R-C15 | Startup の後に `dlopen` で同じ実体になるかを確かめていない | Claude | 6 章に「同じ実体」を足し、Unity の分は G-2（2c） |
| R-C16 | 競合を決まった順で再現する手段が無い | Claude | 6 章に、main をラッチで止める手順、HWASan、CheckJNI を書いた |
| R-C17 | 「main から呼んでも戻る」だけでは AC-5 を確かめられない | Claude | 6 章に、main を止めた状態で全関数が戻ることを足した |
| R-C18 | 2 回目の `JNI_OnLoad` は自分の `JNI_OnLoad` を持たない `.so` でしか起きない。失敗の経路のテストが無い | Claude | 6 章に両方を足した |
| R-C19 | R8 の smoke が自動の経路しか通らない | Claude | 6 章の smoke に手動の経路を足した |
| R-C20 | 文字列（サロゲート、U+0000）と detach の確かめが無い | Claude | 6 章の C ABI のテストに足した |

## 区分 C

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| R-X14 | 5.1 の `android_library` の「変えない」と「1b で補完する」 | Codex | 主語を分けた |
| R-X15 | プロセスの終わりでも `release` を保証するように読める | Codex | 1.3 に「呼ばない」と書いた |
| R-C21 | D-6 からの変更が記録されていない | Claude | AC-5 に書いた（R-X7 と同じ） |
| R-C22 | 入口で拒んだときの同期の `release` と、利用者のロックの関係 | Claude | 1.3.2 に書いた |
| R-C23 | `env` の無い呼び出し元と、`env` が別のスレッドのものの扱い | Claude | 1.4 に「呼び出しスレッドの `env`、`NULL` は `INVALID_PARAMETER`」と書いた |
| R-C24 | ローカル参照の枠の理由、`ExceptionCheck` の範囲、`pthread_key` のデストラクタの条件 | Claude | 5.6 を書き直した |
| R-C25 | 公開する Kotlin の面が食い違う | Claude | 5.1 に 1 つの表にした |
| R-C26 | JNI から引くメンバーを `internal` にすると JVM の名前が変わる | Claude | AC-20、5.6 に書いた |
| R-C27 | `size_t` から `jsize` への変換の検査 | Claude | 5.6 に書いた |
| R-C28 | 「起きた順」と「積んだ順」、配送の間のロック | Claude | 1.3 を「積んだ順」に直し、1.1 と K-2 にロックの規則を足した |
| R-C29 | 設定の画面に Activity が要るかが README 4 と食い違う | Claude | Activity は要らない（Application と `NEW_TASK`）が、前面であることは要る、にした（5.8） |

## 不足項目（第 2 版での扱い）

- 終わるときの解放の契約 → 5.3、5.5
- README 4 の「イベントを保つ」と 5.7 の関係 → 5.7、K-7
- 「前面」の定義、Clipboard の入力のフォーカス → 5.8
- Kotlin の API の設計書に任せる条件 → 9 章（K-1〜K-9）
- 利用者がどのスレッドからも完了や `release` を同期で待たないこと → 1.3
- attach したスレッドの context class loader → 5.6
- `Handler.post` の失敗 → 5.7
- `FetchContent` のオフラインのビルド → AC-14、7 章
- 内部の名前に `ntk_` を付けない → AC-12

## 総合評価

スレッドの規則と、帳簿を main だけで触る考え方は正しく、Windows より単純にできる土台である（両方）。ただし第 1 版は、中心の約束である「ちょうど 1 回の `release`」と初期化の状態機械に穴があり、Android では Windows と同じにできない契約（借りるポインタ、U+FFFD、例外の捕捉）をそのまま引き継いでいた。前面の扱いも操作の粒度が粗かった。区分 A は 21 件（Claude 13、Codex 8。重なりを含む）、B は 12 件、C は 11 件。第 2 版で A をすべて反映し、B と C も反映した。2 回目のレビューで、A が 0 になったかを確かめる。
