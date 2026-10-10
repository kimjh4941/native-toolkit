# レビュー結果（段階 2b の実装・1 回目）

- 日付: 2026-10-10
- レビュー対象: `4178b7de..e4d8fcd8`（段階 2b の 14 コミット。`android/android_library_capi`、`android/android_library_capi_test`、`android/android_library_capi_smoke`、`android/android_library_kotlin_consumer`、`scripts/` の変更）
- 設計書: `designs/2026-10-04-android-c-abi-c-abi-design.md`（第 1 部）、`designs/2026-10-05-android-c-abi-c-abi-design-part2.md`（第 2 部）
- 結果の文書: `results/2026-10-10-android-c-abi-stage2b-result.md`（レビューの前の版）
- レビュアー: 3 本。観点が 3 つに分かれるので 3 本にした
  - Claude のサブエージェント 1（設計との一致: AP-*、6 章、9 章、11 章、12.1 の各行のテスト）
  - Claude のサブエージェント 2（C++ / JNI / Kotlin のメモリとスレッドの安全、寿命）
  - Codex（不具合と、確かめずに通るテストや照合）
- 総合評価: **要修正（重大）**（A が 6 件）

ID の `K-C` は Claude 1（設計との一致）、`K-M` は Claude 2（メモリとスレッド）、`K-X` は Codex。区分は止める基準（A: 契約が壊れている、必須の項目の欠け、利用者や CI が当たる誤り、大事な性質を確かめずに通るテストや照合。B: 潜んだ誤りか確かめの穴、記録の要るもの。C: 小さなもの）。

## 確かめて合っていたこと

- 登録の表と `release` がちょうど 1 回であること、取り消しと完了の競合、初期化の状態の移り（2 つの印、try-lock、`JNI_OnLoad` の冪等）は、どの順で動いても合っていた（K-M）
- `RegisterNatives` と `GetStaticMethodID` の署名は、すべて Kotlin の宣言と一致した（K-M。TB-4 と TB-7 で 2 回間違えた所）
- AP-2/3、7、8、9、11、12、13、14、16、17、18、19、21、22 は設計のとおりに実装されている。9 章の非同期の開始は main からも必ず積み、完了・イベント・受け付けた後の `release` は main で来る（K-C）
- Kotlin の側の main だけの状態は main でしか触っていない。再入は安全（K-M）

## 区分 A

| ID | 問題 | 対処 |
|---|---|---|
| K-C1 | 12.1 の「構造体の配置」（付録 A の各構造体の `sizeof` と各欄の `offsetof` を両 ABI で `static_assert`）が実装されていない。結果の文書の「12.1〜12.4 を満たす」は誤り | 付録 A のすべての構造体について、両 ABI で `static_assert` するテストの翻訳単位を足す |
| K-X1 | テストのケースが丸ごと消えても失敗にならない。`listCases` から消えたケースは XML にも logcat にも出ず、基準の `REMOVED` は表示だけで終了の値に効かない | 全件の実行（`--filter` なし）では、基準から消えたもの（`REMOVED`）と、通っていたものが SKIP に変わったものを失敗にする。`--baseline` で取り直すときは表示だけにする |
| K-X2 | `Share.ALaterOpeningReplacesTheWait` は、イベントが 1 件も届かなくても通る（イベントの数が 0 なら何も確かめない）。受け手の追加も `EXPECT` で、失敗しても進む | 出ている Sharesheet の本文（「Earlier」か「Later」）を見て、どちらで選んだかを決め、それぞれで結果を確かめる（新しい方なら新しい ID の 1 件、古い方なら 0 件）。受け手の追加は致命の確かめにする |
| K-X3 | 配布物の照合が、jni/ の余分な ABI（`jni/armeabi-v7a/libntk.so` など）を見逃す。ABI の組は Prefab の側だけ見ている | jni/ の `libntk.so` の ABI の組も `{arm64-v8a, x86_64}` と照らす。自己テストを足す |
| K-X4 | 配布物の照合が、Kotlin の依存が無い POM と Module Metadata を「版が正しい」と通す | POM と Module Metadata の各 variant に `kotlin-stdlib` があることを求めてから版を照らす。自己テストを足す |
| K-X5 | 照合の自己テストは、`android/build/m2` が無いと全部 SKIP になり、成功で終わる | `test_android.sh` の C ABI の部分（`m2/` に発行した後）で、この自己テストを SKIP を許さない形（環境変数）で流し、結果に入れる |

## 区分 B

| ID | 問題 | 対処 |
|---|---|---|
| K-C2 / K-M1 | 記憶が足りないとき（`bad_alloc`）、C++ の例外が C の入口を越える。`ntk_dialog_show_multi_choice_async` の `vector`、`ntk_share_text` の `CheckActions` の `set`、`ntk_android_init` と `JNI_OnLoad` の表づくり | 入口で捕まえ、`OUT_OF_MEMORY`（`release` は呼び出しスレッドで 1 回）にする。初期化は `JNI_FAILURE` にし、ロックを外す |
| K-C3 | `NOT_INITIALIZED` と引数の誤りの順が機能ごとに違う（Clipboard は UTF-8 を初期化の後に見る。通知の `remove`・`cancel_scheduled`・`is_scheduled` は tag の UTF-8 を初期化の後に見る） | 第 1 部 1.3 の順（引数の確かめが先、初期化が後）にそろえ、第 2 部 11 章に書く |
| K-C4 | 3 つの取り消し（OP-19、OP-39、OP-51）が初期化の前に `NONE` を返すことが、12.1 の未初期化の行と 11 章に例外として書かれていない | 第 2 部 11 章と 12.1 に、名前を挙げて例外として書く |
| K-C5 | 第 1 部 6 章の 3 つの行にテストが無く、記録も無い。「`exit` で落ちない」、「スレッドが終わったときの detach」、前面の行の Clipboard（後ろでは「空」、前面に戻ると読める） | 3 つともテストを足す |
| K-C10 | 12.1 の「完了の `system_code` が 0」を、Dialog のほかは確かめていない | Share と通知（権限、設定）の完了でも確かめる |
| K-M2 | 解除のメッセージを main に積めなかったとき、登録が `CANCEL_REQUESTED` のまま残り、`release` が呼ばれない。積めないのは looper が終わったときに限らない（JNI の失敗、OOM） | 積めなかったら `ACTIVE` に戻して `false` を返す |
| K-M3 | main に積んだ Kotlin のラムダのいくつかが例外を捕まえない（受け手の追加、Dialog の取り消しなど）。投げるとアプリが落ちる | 捕まえてログに出す |
| K-X6 | 正確なアラームが許されている端末では、未来の正確な予約の結果を何も確かめない | 許されているときは `NONE` を求め、予約を消す |
| K-X7 | Dialog の結果の文字列を読めなかったとき（OOM、JNI の失敗）、成功（`NONE`）のまま値が欠けて届く | 読めなかったら `OUT_OF_MEMORY` などで完了し、結果を渡さない |
| K-X8 | `NtkGoogleTest` の後片づけの結果（設定の画面や Sharesheet が消えたか）を確かめていない | 確かめる。テストの本体の失敗があればそれを優先する |

## 区分 C

| ID | 問題 | 対処 |
|---|---|---|
| K-C6 | デストラクタを持つ静的な変数（`static const std::vector<std::string> kNone`）があり、第 1 部 5.5 に反する | 空のときは直接 `NULL` を返す形にして、静的な変数を無くす |
| K-C7 | 設定の画面の種類を Kotlin の列挙の並び（`entries[target]`）で写している（TB-7 で「`ordinal` を使わない」と決めた） | 明示の写し（`when`）にする |
| K-C8 / K-M6 | `LocalFrame` の結果（`ok()`）を見ていない。容量が `jint` を越えうる（`16 + 3 * action_count`、`8 + count`） | 容量を小さな固定値にし（要素は 1 つずつ消している）、積めなかったら `OUT_OF_MEMORY` にする |
| K-C9 | AP-16 の「過ぎた時刻か」を受け口と Kotlin が別々に決めるので、数 ms 先の時刻は、権限が無くても受け口を通り、Kotlin がすぐ表示しようとして黙って捨てうる | 第 2 部の AP-16 の限界に 1 行書く |
| K-M4 | `new` の後に `bad_alloc` が起きると漏れる（Clipboard の読み取りと説明、出力のハンドル、ビルダー） | `std::unique_ptr` にする |
| K-M5 | `TakeException` が、`GetStringUTFChars` が null を返したときに例外を残したまま戻る | 戻る前に消す |
| K-M7 | 取り消しと解除の関数が、ほかの種類の登録の ID も受ける（`ntk_dialog_cancel` に Share の要求の ID を渡すと、完了なしで解放される） | 取り消しと解除は、その関数の種類の登録だけを動かす |
| K-M8 | 初期化の待ちの受け手が、`ntk_android_init` に渡された Activity をつかんだままになりうる | Application の Context をつかむ |
| K-M9 | デバッグ専用のプローブが、初期化の前に呼ぶと落ちる | 初期化を確かめる |

## 対処の結果

すべて対処した。表の「対処」と違う形にしたものと、対処で分かったことだけを書く（細目は作業記録の「レビュー（v1）の対処」）。

| ID | 結果 |
|---|---|
| K-C1 | `StructLayoutTest.cpp` に、付録 A の 12 の構造体の `sizeof` と各欄の `offsetof` を `static_assert` で書いた（LP64 の値。arm64-v8a と x86_64 の両方で組む）。値を 1 つ変えると組めないことを確かめた |
| K-X1 | `test_android.sh` の全件の実行（`--include-host` あり、`--filter` と `--skip-unit` なし）で、基準から消えたケースと、通っていたのが SKIP になったケースを失敗にした（`--baseline` では表示だけ）。作った結果で確かめた |
| K-X2 | 表のとおり。Pixel では新しい方の Sharesheet が出た |
| K-X3、K-X4、K-X5 | 表のとおり。照合の自己テストに 3 件足した（jni/ の余分な ABI、Kotlin の無い POM、Kotlin の無い Module Metadata）。`test_android.sh` は `m2/` に発行した後、自己テストを `NTK_REQUIRE_DIST_FIXTURE=1`（SKIP を許さない）で流し、`capi-dist-selftest` として結果に入れる |
| K-C2 / K-M1 | 入口で捕まえる形ではなく、入口で例外が起きる場所を無くした（Share の重複の確かめと Dialog の複数選択から `std::set` と `std::vector` を外した）。表づくりは `try` / `catch` で囲み、`JNI_FAILURE` にした |
| K-C3 | 4 機能とも、引数の確かめを初期化の確かめより先にそろえた（Clipboard の書き込み 4 つ、通知の `remove`・`delete_channel`・`cancel_scheduled`・`is_scheduled`）。第 2 部 11 章に書いた |
| K-C4 | 第 2 部 11 章の `NOT_INITIALIZED` の行と 12.1 の未初期化の行に、OP-19、OP-39、OP-51 を例外として書いた |
| K-C5 | 3 行のうち 2 行はテストを足した。detach は `Thread` の 2 件（ライブラリが attach したスレッドが終わると `Thread.getAllStackTraces()` に残らない。利用者が先に detach しても静かに終わる）。前面の Clipboard は `Clipboard.FromTheBackAReadIsEmptyAndInFrontItReadsAgain`。**`exit` は、テストではなく配布物の照合にした**。別のプロセスを終わらせるテストを試したところ、C の `exit` は C ABI と関係なく ART の JIT のスレッドを落とし、`System.exit` は静的なデストラクタを走らせない（変異が生き残る）ので、5.5 の壊れ方を起こせなかった。代わりに、配る `libntk.so` が `__cxa_atexit` と `atexit` を import していないことを `check_android_dist.py` で確かめ、デストラクタを持つ静的な変数の変異で import が現れることを確かめた。第 1 部 6 章の行と 0.7 に書いた。照合の自己テストにも 1 件足した（`malloc` を `atexit` に書き換えたライブラリが落ちる） |
| K-C10 | Share の `OnDone`、通知の `OnPermission` と `OnSettings` で `system_code` が 0 であることを確かめる |
| K-M2 | 「積めなかったら ACTIVE に戻して `false` を返す」形にしたが、2 回目のレビューで main と競うと `release` が呼ばれない道を作ると分かった（v2 の R-X1）。**v2 で、CANCEL_REQUESTED のまま「積めなかった解除」の列に入れ、main が次に C に入ったときに流す形に作り直した** |
| K-M3 | Kotlin の側の `MainTasks.post` で、積んだラムダの例外を捕まえてログに出す |
| K-X6 | 許されているときは `NONE` を求める。予約はテストの口が後で消す |
| K-X7 | 表のとおり |
| K-X8 | `NtkGoogleTest` の後片づけで、アプリが前に戻ったことと、設定の画面と Sharesheet が消えたことを確かめる。Home で後ろに回したケースの後は Back では戻らないので、アプリの Context から `FocusActivity` を前に出す口（`UiDriver.toFront`）を足した |
| K-C6、K-C7、K-M4、K-M5、K-M8、K-M9 | 表のとおり |
| K-C8 / K-M6 | `LocalFrame` は容量を 1〜64 に収める（Share は固定の 16）。フレームを積めなかったとき、文字列や配列を Java に渡す 33 か所（いくつかの入口を受け持つ共通の関数を含む）は `OUT_OF_MEMORY` を返す（`Enter` の失敗と同じ形。非同期の入口は `release` を呼び出しスレッドで 1 回）。v2 の R-C11 で、受け付ける（`Accept` を呼ぶ）入口の残り 6 か所（受け手の追加、設定の画面、権限の要求、プローブ）も確かめる形にそろえた。確かめないのは、プリミティブだけを渡す 6 か所（取り消し 2、`cancel_selection`、プローブの finish と emit、`PostRemove`）。初期化の 2 か所はもとから確かめている。記憶が足りない場面は端末で起こせないので、文法とビルドまでの確かめ |
| K-C9 | 第 2 部の AP-16 の限りに 1 行書いた |
| K-M7 | `Registry::Cancel` が種類を受け、違う種類の登録は動かさない。`Registry.ACancelOfAnotherKindChangesNothing` で確かめる |

## 対処の後の確かめ

直したところに関係するテストだけを流した（利用者の方針。全件の実行は基準を取り直すときに限る）。端末は Pixel 6a（API 36）。

- `test_android.sh --filter CApi --skip-unit`: startup 125 件のうち 123 件、noStartup 17 件、noNtkInitializer 3 件、契約の照合 2、smoke 12 が通った
- 落ちたのは 3 件で、どれもテストの側の誤りだった
  - `Share.EveryOpeningCompletesNoneOnMainWhenTheSharesheetOpens` の後片づけ: Sharesheet は半透明で、下のアプリの Activity は前面のままなので、`backToApp` が Back を押さずに戻っていた。K-X8 で後片づけの結果を確かめるようにして見つかった。「前にいる」を、操作の対象の窓がアプリのものかで見るようにした
  - `Registry.RacingReleasesReleaseExactlyOnce`: テストの中の Registry の写しは解除を積めないので、K-M2 の後は、勝った取り消しが ACTIVE に戻り、その間に来た直接の解放が負けて、誰も解放しない回が出る。テストをこの振る舞いに合わせた（2 回は解放しない、CANCEL_REQUESTED のまま残らない、後の 1 回でちょうど 1 回）
  - 照合の自己テスト（`test_an_extra_jni_abi_fails_native`）: dist と m2 の AAR を別々に書き直していて、2 秒の区切りをまたぐと zip の時刻が違った。m2 には dist の AAR を写すようにした
- 直した後: startup の関係するケース 22 件（Registry、Share、NoWait、Home を使う 2 件）がすべて通り、照合の自己テスト 19 件が 3 回続けて通った
- 確かめていないこと: エミュレータでの実行と基準の取り直し（2b を閉じるときに、両方の端末の全件の実行で行う）。K-M2 の残りとして書いた競合は、2 回目のレビューで「直す前より悪い」場合もあると分かり、v2 で作り直した（v2 の R-X1）
