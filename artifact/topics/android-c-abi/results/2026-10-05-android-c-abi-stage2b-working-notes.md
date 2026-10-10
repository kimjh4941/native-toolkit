# 段階 2b の作業メモ（2b の実装結果の文書の材料）

実装の途中で、決めたこと・設計から外れたこと・確かめたことを、起きたときに書きためる。2b の実装結果の文書にまとめる。

## TB-1（2026-10-05）

### 作ったもの

- `android/android_library_capi`（Gradle のプロジェクト `:ntk`）: `build.gradle.kts`、`consumer-rules.pro`、manifest（`NtkInitializer`）、`libntk.map`、`CMakeLists.txt`
- 6 つの公開ヘッダー（付録 A から作った。`check_c_abi_contract_android.py` は `--design-only` なしで通る）
- `src/Common/`: `Log.h`、`Export.h`、`Jni`（JavaVM、`JNIEnv` の取得と attach・スレッドの終わりでの detach、例外の分類とログ、`LocalFrame`）、`Runtime`（C の状態、2 つの印、表づくりの try-lock、`JNI_OnLoad`、`ntk_android_init`、`ntk_android_is_initialized`、`onKotlinReady`・`nativeState` の native）、`Handles`（`Common.h` の 11 関数と、TB-2 以降が使う作る関数）
- Kotlin: `capi/jni/NtkRuntime`（`internal object`。C から名前で引く）、`capi/NativeToolkitCApi`（`init`、`isAvailable`、`isInitialized`、`InitResult`）、`capi/NtkInitializer`
- `android/android_library_capi_test`（`:android_library_capi_test`）: GoogleTest v1.18.0（`FetchContent`）、`libntk_test.so`（JNI の手助け、GoogleTest をケースごとに走らせる口、自分の `JNI_OnLoad`）、`libntk_second.so`（`JNI_OnLoad` を持たない）。flavor 3 つ（`startup`、`noStartup`、`noNtkInitializer`）。Orchestrator でテストごとに別のプロセス
- `gradle/libs.versions.toml`: `androidx.test` の runner 1.7.0、orchestrator 1.6.1、test-services 1.6.0

### 実装の判断（設計に書いていないこと、設計と違うこと）

| 判断 | 理由 |
|---|---|
| `NativeToolkitCApi.init` で Kotlin の `IN_PROGRESS` を `InitResult.IN_PROGRESS` に、`ERROR` を `RETRYABLE_ERROR` にした | 第 1 部 5.3 の表は 2 か所で書き方が違う（状態の表は「`IN_PROGRESS`、`ERROR` なら `RETRYABLE_ERROR`」、`InitResult` の表は `IN_PROGRESS` を「ほかのスレッドが準備している」とする）。意味の合う後者に合わせた。どちらもやり直せる |
| Kotlin の「クラスがあるか」の確かめで、`NtkRuntime` のメンバー（`ensureInitialized`、`onKotlinReady`、`nativeState`）も名前で引く | 既定の `proguard-android-optimize.txt` は native メソッドを持つクラスの名前を残す。keep の規則が無いと、クラスの名前は残り `ensureInitialized` だけが消えるか名前が変わる。C は `NoSuchMethodError` で `CLASS_NOT_FOUND` になるのに、クラスだけを見る Kotlin は見つけてしまい、第 1 部 6 章の「C と Kotlin が同じ失敗に同じ値」が崩れる |
| `JNI_OnLoad` を失敗させる仕掛けを、debug ビルドだけに置いた（環境変数 `NTK_TEST_FAIL_JNI_ONLOAD`。`#ifndef NDEBUG`） | 第 1 部 6 章の「`JNI_OnLoad` が失敗した後」の経路は、クラスがあるプロセスでは起こせない。release の `libntk.so` に文字列が無いことを確かめた（debug には 2 つ、release には 0） |
| 表づくりの try-lock は `std::atomic<bool>` の CAS にした | try だけで取り、待たない（AC-16）。静的なデストラクタも持たない（5.5） |
| `ntk_android_init` で表づくりに負けた側は、表を使わずに `NtkRuntime.ensureInitialized` を呼ぶ（`EnsureInitializedWithoutTable`） | 第 1 部 5.3 の「負けた側も前面の初期値を積む」。`LibraryRuntime.ensureInitialized` が Activity を積む。結果は勝った側が知らせる |
| `libntk_test.so` に自分の `JNI_OnLoad` を置いた | 無いと ART が依存先の `libntk.so` の `JNI_OnLoad` を呼ぶ（1a 3.2）。置くことで、`libntk.so` がリンカーだけで開かれた状態（`dlopen` と同じ）を作れる。2 回目の `JNI_OnLoad` は `libntk_second.so` で起こす |
| 待たせる・壊すための Context（`LatchedContext`、`BrokenContext`）でテストした | `LibraryRuntime` は途中で `getApplicationContext()` を呼ぶので、そこで止めると Kotlin の側を「途中」に、Application でない Context を返すと「失敗」にできる。ライブラリにテストのための口を足さずに済む |

### 後のタスクへ移した第 1 部 6 章の項目

| 項目 | 移した先 | 理由 |
|---|---|---|
| R8 で名前が変わった版で、C と Kotlin がどちらも `CLASS_NOT_FOUND`。keep の規則を外した版で、表づくりが失敗し、アプリが落ちず、`System.loadLibrary` が投げず、`is_initialized` が 0、`ntk_android_init` が `CLASS_NOT_FOUND` | TB-10（smoke） | AGP の `optimization.keepRules.ignoreFrom` はプロジェクトの依存（`:ntk`）には効かなかった（`:ntk`、`native-toolkit-android:ntk`、`ntk` のどれでも R8 の設定に規則が残った）。外部の依存（`m2/` の Maven の座標）なら効くはずなので、`m2/` から組む smoke で確かめる |
| 未初期化のとき、操作が `NOT_INITIALIZED` を返す | TB-3 | TB-1 には操作が無い。`ntk_android_is_initialized` が 0 であることは確かめた |
| 手動の経路の後に Dialog が出る。Activity を渡して後ろへ回すと `NOT_FOREGROUND` | TB-4 | Dialog が要る |

### 確かめたこと

- `:ntk:assembleRelease` が警告なしで通る。AAR: 公開シンボルは `JNI_OnLoad` と、今ある 13 関数（`Common.h` 11、`Android.h` 2）だけ（arm64-v8a・x86_64）。LOAD の整列は `0x4000`。`DT_NEEDED` は `liblog`、`libnativehelper`、`libm`、`libdl`、`libc`。Prefab の `abi.json` は `"stl": "none"`
- `check_c_abi_contract_android.py`（`--design-only` なし）: symbols の SKIP のほかは OK
- 初期化のテスト 19 件（startup 8、noStartup 9、noNtkInitializer 2）が Pixel 6a（API 36）とエミュレータ（API 35）で通る。startup の 2 回目の `JNI_OnLoad` のテストは始めの回数が 1 であることを確かめるので、Orchestrator がテストごとにプロセスを分けていることも確かめられた

### 変異（Pixel 6a、noStartup）

| 変異 | 落ちたテスト |
|---|---|
| M1: Kotlin の側が途中のとき「済んだら知らせる」を登録しない | `ntkInitializerReachesReadyWhenLibraryInitializerIsStillInProgress` |
| M2: Kotlin の側が途中なのに C が `NONE` を返す | `theStateIsNotReadyWhileTheKotlinSideIsInProgress` |
| M3: native が無いのを Kotlin が `IN_PROGRESS` と読む | `afterAFailedJniOnLoadKotlinNeedsTheCInit` |
| M4: Kotlin の側の失敗を C が `IN_PROGRESS` と返す | `aFailedKotlinSideCanBeRetried` |
| M5: `JNI_OnLoad` が失敗で `JNI_ERR` を返す | `afterAFailedJniOnLoadKotlinNeedsTheCInit`（`UNAVAILABLE`） |

- **記録**: 1 回目の M4（`return NTK_ANDROID_ERROR_IN_PROGRESS;`）は、`kKotlinInProgress` が使われなくなり `-Werror` でコンパイルに失敗した。APK は入れ替わらず、前の回（M3）の結果の XML を読んで「落ちた」と数えていた。変異の回し方を、流す前に結果の XML を消し、組み立ての失敗を「流れていない」と出す形に直し、M4 を通る形（三項演算子の両方を `IN_PROGRESS`）で流し直した
- 落ちなかった変異は無い。`MarkNativeDone` の中の「Kotlin の印が先に立っていたら `READY` にする」は、`RegisterNatives` と `MarkNativeDone` の間に `onKotlinReady` が来る競合でしか通らず、決まった順で起こすテストは無い（第 1 部 6 章の「競合を決まった順で再現する」は TB-9）

## TB-2（2026-10-05）

### 作ったもの

- C（`src/Common/`）: `Classes`（機能ごとのクラス・static メソッド・native の表の項目。`Runtime` が全部を作るか、何も作らない）、`Registry`（ID → 登録の表、`TryRelease`、`Cancel`、`CompleteOnMain`、`DeliverOnMain`、帳簿の native）、`Accept`（受け付けの 4 つの手順）、`Utf8`（厳密な UTF-8 の検査、Java のバイト列との往復）、`StructSize`（`struct_size` の規則）、`Errors`（共通の 0〜5）、`Main`（main の判定）。`jni::Failure` に `kOutOfMemory` を足した
- Kotlin（`capi.jni`）: `Ledger`（帳簿。main だけ）、`Foreground`（前面の判定）、`Utf8`（C へ渡す前に孤立したサロゲートと U+0000 を U+FFFD に）、`Errors`（共通の値と、表に無い例外の写し）
- debug ビルドだけ: C の `src/Debug/Probe.cpp`（`ntk_debug_probe_*` を公開。CMake は `CMAKE_BUILD_TYPE` が Debug のときだけ組み、`Classes.cpp` は `NDEBUG` で外す）と Kotlin の `src/debug/.../ProbeBridge.kt`
- テスト: GoogleTest 32 件を足した（`Utf8` 7、`StructSize` 7、`Registry` 5、`Probe` 13）。noStartup に未初期化の 1 件。capi の JVM の単体テスト `Utf8Test` 4 件

### 実装の判断

| 判断 | 理由 |
|---|---|
| 試験用の操作とイベント（`ntk_debug_probe_*`、`ProbeBridge`）を debug ビルドだけに置いた | TB-2 にはまだ機能の関数が無いが、完了の条件は第 1 部 6 章の「`release` と完了のテスト」。機能と同じ部品（`Accept`、登録の表、帳簿、main）を通る操作で、受け付け・完了・取り消し・配送・外すのすべてを確かめた。第 1 部 6 章の「テスト専用の口（帳簿の件数、`release` の回数）」もこれで持つ。release の AAR には関数もクラスも無いことを確かめた（`ntk_*` は 13、`ntk_debug` は 0、`ProbeBridge` は 0。debug は 21・8・1） |
| capi の純粋な部品（`Utf8.cpp`、`Registry.cpp`、`Jni.cpp`、`StructSize.h`）をテスト用の `.so` に直接コンパイルして単体で確かめた | JNI の公開の口を足さずに、境目の値（過長、サロゲート、U+10FFFF の上、`struct_size` の各規則、競合する解放）を直接突ける。テスト用の `.so` は `-fvisibility=hidden` なので、`libntk.so` と名前はぶつからない |
| 帳簿の操作は `android_library` の `MainPoster`（main の Handler 1 つ）で積む | 第 1 部 5.7 の「1 つの Handler の同期メッセージ」 |
| 「完了済み」の印は、利用者の完了を呼ぶ前に立てる | コールバックの中から同じ ID を取り消しても、2 回目の完了が起きない |
| `FindOnMain` は main 以外から呼ばれたら `nullptr` を返してログを出す | 受け付けた後の登録は main だけが解放するので、main 以外から指すと解放済みを触りうる |
| 表づくりは、全部のクラスを作ってからグローバル参照を公開し、途中の失敗では作ったものを消す | 一部だけの表で `NATIVE_READY` にならない |
| イベントの登録のハンドルは、TB-3 以降で登録の ID をそのまま使う（試験用の操作では `uint64_t`） | 第 1 部 AC-17 の使い回さない ID。解放した後に古いハンドルで呼ばれても、解放済みの番地を触らない |

### 確かめたこと

- capi の全テストが Pixel 6a とエミュレータで通る（startup 40、noStartup 10、noNtkInitializer 2）。capi の JVM の単体テスト 4 件
- `check_c_abi_contract_android.py` は symbols の SKIP のほかは OK

### 変異（Pixel 6a、startup。組み立てに失敗した回は「流れていない」と出す回し方で）

| 変異 | 落ちたテスト |
|---|---|
| N1: `TryRelease` が状態の CAS を省く | `Registry.TryReleaseCallsReleaseOnceAndOnlyFromTheExpectedState`、`Registry.CancelMovesActiveToCancelRequestedOnce` |
| N2: 取り消しの要求の後も結果で完了する | `Probe.AResultAndACancelQueuedTogetherCompleteCanceledOnceInEitherOrder` |
| N3: 配送で ACTIVE を確かめない | `Probe.ARemovalInsideTheCallbackStopsTheDeliveriesAtOnce` |
| N4: 積めなかったときに `release` しない | `Probe.AFailedPostReleasesOnTheCallingThreadAndNeverCompletes` |
| N6: 低位のサロゲートだけを拒む（1 回目の形は `-Werror` で流れず、形を変えた） | `Utf8.RejectsSurrogates`、`Utf8.TheEntryRejectsWhatIsNotStrictAndNull` |
| N7: 知らない部分の 0 以外を見逃す | `StructSize.ANewerStructWithAValueInItsNewPartIsNotSupported` |
| N8: Kotlin の `Utf8` が孤立したサロゲートを残す（JVM） | `Utf8Test.anUnpairedSurrogateBecomesTheReplacementCharacter` |
| N9: 外すときに取り消しの完了を呼ばない | `Probe.ACancelRightAfterAccepting...`、`Probe.ACancelBeforeTheInsertion...`、`Probe.AResultAndACancelQueued...` |

- 落ちなかった変異: N5（帳簿への挿入で ACTIVE を確かめない）。試験用の操作は挿入のほかに何も始めないので、取り消しの後に挿入しても、外す処理が帳簿から消して取り消しの完了を出し、結果が同じになる。「取り消しの後に操作を始めない」は、始めると見える機能（Dialog が出ない。TB-4）で確かめる

## TB-3（2026-10-05）

### 作ったもの

- C: `src/Clipboard/Clipboard.cpp`（OP-01〜OP-12 と、読み取りの結果・説明の読み取り 15 関数。合わせて 27 関数）。クラスの表に `ClipboardBridge` を足した
- Kotlin: `capi.jni.ClipboardBridge`（書き込み・読み取り・問い合わせは呼び出しスレッドで、監視の開始と停止と受け手の挿入は main に積む。例外は 11.3 の値に写す）。`NtkRuntime` に Application の Context を持たせた（受け口が Manager を得るため）
- テスト: GoogleTest `Clipboard` 13 件。noStartup に「未初期化の Clipboard の操作」1 件（第 1 部 6 章の未初期化の項目。TB-1 から移したもの）。テスト用のモジュールに `FocusActivity`（読み取りと変更のイベントには窓のフォーカスが要る）と `ClipboardControl`（Kotlin からクリップを置く）。GoogleTest の runner は、各ケースの前に `FocusActivity` を開いてフォーカスを待つ

### 実装の判断

| 判断 | 理由 |
|---|---|
| 読み取りと説明の結果は、受け口が `Array<Any?>`（UTF-8 のバイト列と配列）で返し、C がヒープに写す | JNI で引くフィールドや型を増やさずに済む。JNI の参照は持たない（第 1 部 5.7） |
| `NtkRuntime` が持つ Context は、`LibraryRuntime` が DONE を返した後（途中なら済んだときの関数の中）で、`applicationContext` が `Application` のときだけ持つ | 最初は呼ぶ前に持たせたが、(1) 初期化に失敗する Context を持ち続けうる、(2) `LibraryRuntime` より先に `getApplicationContext()` を呼ぶと、初期化のテスト（Kotlin の側が途中の間は READY でない）がそこで止まり、`LibraryRuntime` の外で待つ形になって落ちた。READY になる経路はどれも `NtkRuntime` を通るので、READY の後は Context がある |
| 監視の開始・停止の main での失敗（`ClipboardManager` が取れない）は logcat に出すだけ | 第 2 部 6.1（戻り値は main への受け付け） |
| 受け手のハンドルは登録の ID（`reinterpret_cast`） | TB-2 のとおり |

### テストで分かったこと

- **1 回のコピーで変更のイベントが 2 回届くことがある**: 監視の登録は 1 つ（2 回目の開始は「already observing」で無視されている）なのに、テキストのコピーで OS が `onChange` を 8 ms 空けて 2 回呼んだ（Pixel 6a、API 36）。Android 12 以降、テキストの分類（`ClipDescription` の classification）が済むと、変更としてもう一度知らせる。テストは「少なくとも 1 回」と「外した後・止めた後は増えない」（遅れて来る分を待ってから数える）で確かめる形にした。分類の無い URI のクリップでは 1 回なので、「受け手ごとにちょうど 1 回」は URI のコピーで確かめた（`AUriCopyReachesEachListenerExactlyOnce`。`EventHub` の受け手を登録のたびに足す誤りは、これでだけ捕まる）
- **一度きりの事象**: 3 つの flavor を続けて流した 1 回目、Pixel 6a で 8 分 47 秒かかって startup と noStartup の結果が 0 件になった（ログは残っていなかった）。その後、両方の端末で 3 つを続けて流して全件が通った。TB-11 の全体の実行で再び出ないかを見る
- libntk の debug のログが多く、logcat の領域から GoogleTest の失敗の行が押し出された。端末の logcat の領域を 16 MB にして読んだ（TB-11 で `test_android.sh` に入れるかを決める）

### 確かめたこと

- capi のテスト 66 件（startup 53、noStartup 11、noNtkInitializer 2）が Pixel 6a とエミュレータで通る
- release の `libntk.so` の公開は `ntk_*` 40（Common 11、Android 2、Clipboard 27）と `JNI_OnLoad`
- `check_c_abi_contract_android.py` は symbols の SKIP のほかは OK

### 変異（Pixel 6a、startup の GoogleTest）

| 変異 | 落ちたテスト |
|---|---|
| C1: `reserved1` を見逃す | `Clipboard.TheOptionsFollowTheStructSizeRules` |
| C2: 0 件を `INVALID_PARAMETER` で返す（1 回目の形は `-Werror` で流れず、形を変えた） | `Clipboard.NullAndInvalidUtf8AreRejectedAtTheEntry` |
| C3: Kotlin の `INVALID_URI` を `UNKNOWN` に写す | `Clipboard.KotlinFailuresMapToTheTable` |
| C4: 読み取りで text と html を取り違える | `TextRoundTripsWithItsLabel`、`HtmlUriAndSeveralTextsRoundTrip`、`WhatCCannotHoldIsReadAsTheReplacementCharacter` |
| C5: 受け手を外しても取り消さない | `EveryListenerGetsAChangeUntilItIsRemoved`、`AUriCopyReachesEachListenerExactlyOnce` |
| C6: 読み取りで U+FFFD に置き換えない | `WhatCCannotHoldIsReadAsTheReplacementCharacter` |
| C7: `EventHub` の受け手を登録のたびに足す | `AUriCopyReachesEachListenerExactlyOnce` |

## TB-4（2026-10-05）

### 作ったもの

- C: `src/Dialog/Dialog.cpp`（OP-13〜OP-19 と結果の読み取り 10 関数。合わせて 17 関数）。クラスの表に `DialogBridge` を足した
- Kotlin: `capi.jni.DialogBridge`（main の 1 つのメッセージで、帳簿への挿入（取り消し済みなら何もしない）、前面の判定、`show`。C の要求の ID と Kotlin の要求の ID を main だけで対にする。結果を 11.1 の値に写す。取り消しは登録の表の取り消しの後に、Kotlin の Dialog も閉じる）
- 表づくりの失敗のログに、クラスとメンバーと JNI の型を出すようにした
- テスト: GoogleTest `Dialog` 13 件（入口の検査、6 種の結果、`DISMISSED`、取り消し、挿入の前の取り消し、宿主の破棄、後ろから）。noStartup に 2 件（TB-1 から移した「手動の経路の後に Dialog が出る」「Activity を渡して後ろへ回すと `NOT_FOREGROUND`」）。テスト用のモジュールに `UiDriver`（UiAutomator で押す。作られた Activity の数を数える）

### 実装の判断

| 判断 | 理由 |
|---|---|
| 要求が `NULL` なら `INVALID_PARAMETER`（`NULL` を既定の Dialog としない） | 単一選択と複数選択は項目が要り、要求そのものが要る。6 種でそろえた |
| 単一選択の添字は -1（なし）か項目の範囲。項目が 0 個、項目に `NULL` は `INVALID_PARAMETER`（入口） | Kotlin の `require` と同じ条件を入口で見る（AP-19）。Dialog には件数 0 の専用の値が無い |
| 取り消しは、`registry::Cancel` で CANCEL_REQUESTED と外す処理を積んだ後に、`DialogBridge.cancel` で Kotlin の Dialog を閉じる | 完了は外す処理が `CANCELED` で出す（第 1 部 5.7）。Kotlin の Dialog の結果が後から来ても、登録はもう無いので何も起きない。画面からも消える |
| 文字列の既定値（`NULL` の title・message・hint は `""`、ボタンと login のヒントは Kotlin の既定の文言）は受け口で当てる | 第 2 部 6.2。Kotlin の既定値は受け口で Kotlin の型から読む（文言を写して持たない） |
| 結果のハンドルの読み取りは、ハンドルの中の文字列を指す（三項演算子で `optional` の写しを作らない） | 最初の形は `result == nullptr ? std::nullopt : result->text` で、型の違う 2 つの枝から一時的な写しができ、消えたものを指すポインタを返していた。組み立ての前に読んで気づき、`if` で分けた |

### テストで分かったこと

- **JNI の型の 1 文字の誤りで、C ABI 全体が `NOT_INITIALIZED` になった**: `nativeAnswered` の型に `I` が 1 つ多く、`RegisterNatives` が `NoSuchMethodError` で失敗し、表づくりが全部失敗した（全部か何も無いかの作りのとおり）。GoogleTest がほぼ全件落ちて分かった。ログに「RegisterNatives」としか出ず、どのメソッドか分からなかったので、クラス・メンバー・型を出すようにした
- **D1（取り消した要求でも Dialog を出す）が最初は捕まらなかった**: Dialog は出るが、直後に main で取り消しが来て数 ms で閉じるので、画面の文字を間隔を空けて見るテストでは見逃した。作られた Activity の数を数え、取り消した要求では透明な宿主が 1 度も作られないことを確かめる形にして捕まえた（TB-2 の N5 の確かめ）
- **変異の回で端末が止まった**: D9（添字の範囲を見逃す）の回で、入口のテストの `ASSERT` が落ちて関数が途中で抜けた後、通ってしまった要求の完了がスタックの消えた記録の置き場を触り、main が 30 分止まった（端末は `FocusActivity` の白い画面のまま。利用者が気づいて知らせた）。テストのプロセスを止めて残りのケースを流させ、回し方が元のソースに戻したことを確かめた。テストの記録の置き場をヒープに置いて解放しない形（`Leaked<T>()`。テストごとに別のプロセスなので溜まらない）にして、D9 が止まらずに 104 秒で落ちることを確かめた

### 確かめたこと

- capi のテスト 81 件（startup 66、noStartup 13、noNtkInitializer 2）が Pixel 6a とエミュレータで通る
- `check_c_abi_contract_android.py` は symbols の SKIP のほかは OK

### 変異（Pixel 6a、startup の GoogleTest）

| 変異 | 落ちたテスト |
|---|---|
| D1: 帳簿への挿入の結果を見ずに Dialog を出す | `Dialog.ARequestCanceledBeforeItsInsertionIsNeverShown`（Activity の数で。最初の形では捕まらなかった） |
| D3: 宿主の破棄を `CANCELED` に写す | `Dialog.ADestroyedHostCompletesCanceledBySystem` |
| D4: 取り消しで Kotlin の Dialog を閉じない | `Dialog.CancelCompletesCanceledAndClosesTheDialog` |
| D6: 複数選択の初期の真偽を渡さない | `Dialog.AMultiChoiceAnswersWithEveryItem` |
| D7: 「閉じられない」の旗を反転しない | `Dialog.BackDismissesWithNoValues` |
| D8: 入力の文字とユーザー名を取り違える | `Dialog.ATextInputAnswersWithTheText`、`Dialog.ALoginAnswersWithTheUsernameAndPassword` |
| D9: 単一選択の添字の範囲を見逃す | `Dialog.InvalidRequestsAreRejectedAtTheEntryAndReleasedHere` |

- 流さなかった変異: D2（受け口の前面の判定を省く）。Kotlin の `UiHost` も前面でなければ同じ `NOT_FOREGROUND` で完了する（Kotlin の設計書 KA-17）ので、結果が変わらない同値の変異

## TB-5（2026-10-05）

### 作ったもの

- C: `src/Notification/Builders.h`（ビルダーのデータの形。設定しなかった項目は `optional` の空で、Kotlin の既定値になる）と `Builders.cpp`（内容のビルダー 40 関数、チャンネルのビルダー 11 関数）
- テスト: GoogleTest `NotificationBuilder` 10 件、`NotificationContent` 1 件、`NotificationChannel` 2 件。noStartup に「初期化の前にビルダーが使える」1 件

### 実装の判断

| 判断 | 理由 |
|---|---|
| ビルダーを Kotlin の値に変える処理と名前の解決を TB-6 に移した（第 2 部 13 章の TB-5・TB-6 の行を直した） | ビルダーには読み出しの口が無く、写した中身・既定値・名前は、通知を出して確かめるしかない。名前は表示の時点で引く（第 2 部 6.3） |
| 範囲は入口で見て、補正しない（AP-8）: priority -2〜2、visibility -1〜1、group_alert_behavior 0〜2、timestamp・timeout_after は 0 以上、progress は不定でなければ 0 ≦ current ≦ max、importance 0〜4、ロック画面の見え方 -1〜1、振動の長さは 0 以上、semantic action は 0〜12（API 31 までの `SEMANTIC_ACTION_*`）、`_set_tap` は 0〜2、group_conversation は -1〜1 | 第 2 部 6.3 の表に無い 3 つ（振動の長さ、semantic action、group_conversation）は、Android と Kotlin が受ける値の範囲で決めた |
| Kotlin が必須の項目は `NULL` を `INVALID_PARAMETER`: BigText の本文、Messaging の利用者の名前、メッセージの本文、custom view の layout、view のクリックの view と action の ID、アクションの title と action の ID、`_add_data` の鍵と値、チャンネルの ID（空も不可）と名前、グループの ID を付けるときの名前 | 第 2 部 6.3 の「`NULL` は設定しない（既定に戻す）」は、任意の項目に当てる。必須の項目は戻す既定値が無い |
| Inbox の行は 0 行を受ける（`NULL` と 0） | Android の InboxStyle は行が無くても出せる |
| アクションの `no_user_interface` は、Kotlin の `showsUserInterface`（既定は真）を反転した名前 | 0 で埋めた構造体が既定値になるように（E-9） |
| `_add_data` で同じ鍵をもう一度足すと、値を置き換える | Kotlin の `data` は Map |
| setter は C++ の例外を外へ出さない（`Guard`。`bad_alloc` は `OUT_OF_MEMORY`） | 第 1 部 1.1 |

### 確かめたこと

- capi のテスト 94 件（startup 78、noStartup 14、noNtkInitializer 2）が Pixel 6a とエミュレータで通る
- release の `libntk.so` の公開は `ntk_*` 108（Common 11、Android 2、Clipboard 27、Dialog 17、内容のビルダー 40、チャンネルのビルダー 11）

### 変異（Pixel 6a、startup の GoogleTest）

| 変異 | 落ちたテスト |
|---|---|
| B1: priority の上限を 3 まで許す | `NotificationBuilder.NumbersOutOfRangeAreRejectedNotCorrected` |
| B2: Messaging の style が無くてもメッセージを足せる | `NotificationBuilder.AMessageOrAViewClickNeedsItsStyle` |
| B3: custom view の style を設定しても種類が変わらない（後から設定したものが勝たない） | `NotificationBuilder.AMessageOrAViewClickNeedsItsStyle` |
| B4: importance 5 を受ける | `NotificationChannel.CreateChecksTheIdNameAndImportance` |
| B5: アクションの `reserved1` を見逃す | `NotificationBuilder.AnActionFollowsTheStructSizeRules` |
| B6: 不定の進み具合でも範囲を見る | `NotificationBuilder.ProgressNeedsCurrentWithinMaxUnlessIndeterminate` |
| B7: semantic action の上限を 13 まで許す | `NotificationBuilder.AnActionFollowsTheStructSizeRules` |

- 確かめていないこと: チャンネルのビルダーを深く写すこと（ビルダーを解放した後も内容が持つこと）は、解放しても落ちないことまで。写した値が通知に表れることは TB-6 で確かめる

## TB-6（2026-10-05）

### 作ったもの

- C: `src/Notification/Encoder.h`（ビルダーの中身を little-endian のバイト列にする。設定しなかった項目は「無し」の印で、Kotlin の既定値になる）と `Notification.{h,cpp}`（OP-20〜OP-39 の 20 関数。表示、更新、削除、チャンネル、予約、Progress、問い合わせ、設定を開く、権限の要求とその取り消し）
- Kotlin: `capi/jni/NotificationBridge.kt`（バイト列を読み、名前を引いて `AndroidNotificationCommand` を作る。イベントの Intent を付ける。Kotlin の例外を C のエラーの値にする）
- テスト:
  - GoogleTest `Notification` 18 件、`Clipboard` の 1 件に `ntk_clipboard_description_mime_type_at` を足した
  - noStartup に「権限の無い状態」1 件、noNtkInitializer に「権限のダイアログを押す」1 件（UiAutomator。前面でないときの要求、取り消し、共有、拒否、許可、許可済み）
  - JVM の `NotificationBridgeTest` 3 件（例外とエラーの値の写し）
  - 試験用のリソース（`ntk_test_icon`、`ntk_test_custom` の layout）と、表示中の通知とチャンネルを読む `NotificationInspector`

### 実装の判断

| 判断 | 理由 |
|---|---|
| ビルダーの中身は、C でバイト列にして 1 回の JNI 呼び出しで渡し、Kotlin で読む | 多くの項目を JNI で 1 つずつ渡すと、呼び出しの数と JNI の署名の誤りが増える |
| 名前（アイコン、絵、layout、view の ID）は表示の時点で Kotlin が引く。引けなければ `RESOURCE_NOT_FOUND` | 第 2 部 6.3 |
| Kotlin の例外の写し: リソースが無い → 12、`IOException` → 13、`ForegroundServiceStartNotAllowedException` → `SERVICE_START_NOT_ALLOWED`（14）、ほかは共通の写し（`Errors.common`） | 11 章の表 |
| AP-16 の事前の確かめ: `show` と `update` は「権限があり、通知が有効」のときだけ。`schedule` は、過ぎた時刻なら権限、未来の正確な予約なら正確なアラームの許可を求め、未来の不正確な予約はどちらも求めない | 過ぎた時刻はすぐ表示されるので権限が要る。未来の正確な予約は Kotlin が黙って不正確にしない |
| 予約の構造体: `trigger_at_millis` は 1 以上、`alarm_type` は 0 か 1（Unix 時刻）。反転した名前の 3 つの真偽値を Kotlin の exact・allowWhileIdle・persist に戻す | AP-22、E-9 |
| 権限の要求: 許可済みなら前面かどうかに関わらず `GRANTED`、前面でなければ `NOT_FOREGROUND`、それ以外は Kotlin の要求に渡す。取り消しは `CANCELED` | 12.1 の前面の行 |
| 完了のエラーが `NONE` でないときも結果の引数に値を渡す（権限は `DENIED`、設定は `OPENED`） | 結果の引数は未定義にしない。呼び出し側はエラーを先に見る |

### テストで分かったこと

- **チャンネルのロック画面の見え方**: 読み返すと -1000 になる。Android が値を上書きするので、確かめる行を外した
- **Progress の通知**: フォアグラウンドサービスの通知は、表示が最大 10 秒遅れる。待ちを 15 秒にした
- **後ろからのフォアグラウンドサービスの開始**: 計装の下では許されてしまい、端末のテストでは `SERVICE_START_NOT_ALLOWED` を起こせない。例外の写しは JVM のテストで確かめ、通しの確かめは TB-10 の smoke に移した
- **権限のダイアログは要求どうしで共有される**（Kotlin の作り）: 前のダイアログが閉じきる前の要求は、そのダイアログの答えを受け取る（エミュレーターで起きた）。テストは共有を確かめる手順にし、次の要求はダイアログが消えてから出す
- **チャンネルの振動**: 振動の装置が無いエミュレーターでは、振動を有効にしても読み返すと無効になる。lights と vibration は Kotlin の既定が有効なので、テストは無効にして値が届くことを確かめる
- **silent**: AndroidX は silent の通知を「silent」というグループに入れるが、Android 16 はまとめの無いグループを組み替え、グループが消える。テストは `groupAlertBehavior`（`GROUP_ALERT_SUMMARY`）で確かめる
- **通知を無効にした状態の `show`**（12.1 の AP-16 の行）: API 33 以降は、設定で通知をオフにすると権限が外れる。「権限はあるのにオフ」の状態は API 32 以下でしか作れず、今の 2 台（API 35、36）では確かめられない
- **テストが呼んでいない関数**: 公開の 128 関数とテストが呼ぶ関数を突き合わせると、13 関数（Clipboard 1、チャンネル 4、内容 8）がどのテストからも呼ばれていなかった。TB-3 と TB-5 で似た setter を代表だけで済ませたため。すべてテストを足した
- **利用者の決定**: 「公開の各関数をテストが呼んでいること」の機械の照合は足さない（元の計画どおり。12.1 の入口の行が全関数を求めている）

### 後のタスクへ移したこと

- 後ろからの Progress の 4 つの操作が `SERVICE_START_NOT_ALLOWED`（12.1 の Progress の行）→ TB-10 の smoke
- タップでアプリが開くことと、イベントが C に届くこと（AP-18）→ TB-7

### 確かめたこと

- capi のテスト 114 件（startup 96、noStartup 15、noNtkInitializer 3） が Pixel 6a とエミュレータで通る
- JVM のテスト（`:ntk:testDebugUnitTest`）が通る
- release の `libntk.so` の公開は `ntk_*` 128（TB-5 の 108 に通知の操作 20）

### 変異（Pixel 6a。C と並びは startup の GoogleTest、権限の無い状態は noStartup）

| 変異 | 落ちたテスト |
|---|---|
| N1: `alarm_type` 2 を受ける | `Notification.InvalidArgumentsAreRejectedAtTheEntry` |
| N2: `inexact` を反転しない | `Notification.AnInexactFutureScheduleIsKeptUntilCanceled`、`Notification.AFutureExactScheduleNeedsExactAlarms` |
| N3: `trigger_at_millis` 0 を受ける | なし。Kotlin も `triggerAtMillis > 0` を求めて同じ `INVALID_PARAMETER` を返すので、外から区別できない（等価な変異） |
| E1: sub text の欄に ticker を書く | `Notification.TheContentAndItsChannelReachTheNotification` |
| E2: auto_cancel と ongoing の順を入れ替える | `Notification.TheContentAndItsChannelReachTheNotification` |
| E3: チャンネルの説明を落とす | `Notification.TheContentAndItsChannelReachTheNotification` |
| K1: `show` の権限の確かめを外す | `ManualInitTest.withoutThePermissionNotificationsAreRefusedNotDroppedSilently` |
| K2: 過ぎた時刻の予約の権限の確かめを外す | 同上 |
| K3: 未来の正確な予約の正確なアラームの確かめを外す | 同上 |
| K4: 引けない drawable を 0 にする | `Notification.NamesThatDoNotResolveAreResourceNotFound` |
| K5: dismiss の Intent を常に付ける | `Notification.TheTapAndDismissEventsCanBeTurnedOff` |
| K6: 後ろから開いた設定を `NONE` にする | `Notification.SettingsOpenFromTheForegroundOnly` |
| K7: `complete_progress` が完了にしない | `Notification.ProgressIsCorrectedForTheForegroundService` |
| E4: silent を落とす | `Notification.TheRemainingContentSettersReachTheNotification` |
| E5: チャンネルの lights を落とす | `Notification.TheChannelAlertSettersReachTheChannel` |
| K8: 前面でないときの権限の要求を C の側で止めず Kotlin に渡す | なし。Kotlin も `Failed(NOT_FOREGROUND)` を返し、C には同じ `(NOT_FOREGROUND, DENIED)` が届く（等価な変異）。C の側の分岐は、Kotlin の前面の判定が変わっても 12.1 の値を返す保険として残す |

## TB-7（2026-10-05）

### 作ったもの

- C: `Notification.cpp` に OP-40〜OP-42（操作と表示の受け手の追加、受け手の解除）と、イベントの読み取り 12 関数。イベントは登録ごとに複製して渡し、受け取った側が free する
- Kotlin: `NotificationBridge` に受け口（`addInteractionListener`、`addShownListener`）と、操作のイベントの保持
- テスト:
  - GoogleTest `NotificationEvent` 9 件（イベントは表示中の通知の `PendingIntent` を送って起こす。シェードの 1 件は UiAutomator で押して払う）
  - noStartup に「初期化の前の全操作」1 件（Clipboard、Dialog、通知の操作を全部呼ぶ）
  - 試験の土台: `NotificationInspector.fire`、`UiDriver` のシェードの操作と前面の Activity、試験アプリの起動用の `LaunchTargetActivity`、`Record.detail`

### 実装の判断

| 判断 | 理由 |
|---|---|
| 受け口は種類ごとに、最初の C の登録で `EventHub` に受け手を 1 つ足し、外さない。操作のイベントは受け口の列に入れ、ACTIVE な登録へ古い順に配る。ACTIVE な登録が無ければ列に残し（32 件を超えたら古いものから捨てる）、次の登録の挿入の中で配る | AP-21。コールバックの中で唯一の登録を外して足し直しても、残りは列に残って新しい登録へ届く（Y-X2） |
| 配る先は帳簿の登録のうち C で ACTIVE なものだけ（`Ledger.nativeIsActive`） | 外した登録は解除のメッセージが動くまで帳簿に残る。それを数えると、配っても C が捨てるので、列から消えてイベントを失う |
| 配っている間に届いたイベントは列の後ろに足し、同じループが配る（再入しない） | 届いた順を保つ |
| 表示のイベントは保たない | Kotlin の設計書 8.4 と AP-21 |
| イベントの種類は Kotlin の列挙から明示の写しで C の値にする（`ordinal` を使わない） | Kotlin の並びが変わっても C の値が変わらない |
| 初期化の前の取り消し（`ntk_dialog_cancel`、`ntk_notification_cancel_permission_request`）は `NONE` | 初期化の前に有効な ID は無いので、「知らない ID は何もしない」（6.2、6.3）に当たる |

### テストで分かったこと

- **JNI の署名の書き間違い**（`nativeInteraction` の int を 3 つと書いた）で、クラスの表づくりが失敗し、全部が `NOT_INITIALIZED` になった。TB-4 と同じ種類の誤り。表づくりは全部か無しかなので、1 か所の誤りで全テストが落ちて見つかる
- **ランチャーと同じ起動**: タップでアプリを開くと、アプリのタスクが既にあれば、新しい Activity を作らずにそのタスクを前に出す。テストは「後ろにいたアプリが前面に来た」を確かめる
- **12.1 の未初期化の行の抜け**: TB-4 と TB-6 で、Dialog と通知の操作の「初期化の前は `NOT_INITIALIZED`」のテストが無かった（Clipboard も代表の 3 つだけ）。全部を呼ぶテストを足した
- **変異が見つけたテストの穴**: 準備の「登録して、すぐ外す」で、登録の挿入が main で動く前に外していた。挿入は行われず受け口の `EventHub` の受け手も足されないので、2 件のテストは受け口ではなく Kotlin の `EventHub` の保持（同じく 32 件）を確かめていた。保持の上限を 33 にする変異（T1）が通って分かった。登録の後に main が追いつくのを待ってから外すように直した（`UsedOnce`）
- **シェードで払う操作**: タイトルの文字の上を遅く払うと、エミュレーターで閉じる操作として受け取られないことがあった（前の回は通った）。通知の行を画面の端から端まで速く払い、残れば 1 度だけやり直す形にした。直した後、両方の端末で計 7 回流して通った
- **ブロードキャストの完了を待つ**: `PendingIntent.send` に完了の通知を渡すと順序付きで送られ、受け手（`onReceive` の中で `EventHub` に流す）が終わってから返る。イベントが受け口に着いたことを、時間を待たずに確かめられる

### 後のタスクへ移したこと、確かめていないこと

- 「再入で配っている途中も 32 件を超えない」（12.1 のイベントの行）は、配っている間に届いたイベントも同じ列と同じ上限に入る作りで満たす。端末で再入の最中にイベントを起こすテストは作っていない
- 通知の権限が無い状態でのイベント（表示できないので起きない）は対象外

### 確かめたこと

- capi のテスト 125 件（startup 106、noStartup 16、noNtkInitializer 3）が Pixel 6a とエミュレータで通る
- release の `libntk.so` の公開は `ntk_*` 143（TB-6 の 128 に OP-40〜OP-42 の 3 と読み取りの 12）。残りの 12 は TB-8 の Share
- 公開の 143 関数は、すべてどれかのテストが呼ぶ。契約の照合は FAIL 0

### 変異（Pixel 6a。startup の GoogleTest、初期化の前は noStartup）

| 変異 | 落ちたテスト |
|---|---|
| T1: 33 件まで保つ | `NotificationEvent.AtMost32AreKeptAndTheOldestIsDropped`（テストの準備を直した後。直す前は通った） |
| T2: ACTIVE でない登録にも配る | `NotificationEvent.RemovingAndAddingInTheCallbackKeepsTheRest` |
| T3: ACTIVE な登録が無いとき保持を捨てる | `AnEventWithNoActiveListenerWaitsForTheNext`、`RemovingAndAddingInTheCallbackKeepsTheRest`、`AtMost32AreKeptAndTheOldestIsDropped` |
| T4: ACTION と DISMISS の値を入れ替える | `EveryListenerGetsTheEventOnMainUntilRemoved`、`RemovingAndAddingInTheCallbackKeepsTheRest` |
| T5: 表示の受け手を `EventHub` に足さない | `AShownEventReachesTheListener` |
| T6: データの値を鍵から読む | `EveryListenerGetsTheEventOnMainUntilRemoved` ほか 4 件 |
| T7: `listener_remove` が何もしない | `EveryListenerGetsTheEventOnMainUntilRemoved` ほか 3 件 |
| T8: `EventHub` が保っていたイベントを最初の登録に渡さない | `EventsBeforeTheFirstListenerArriveInItsInsertion` ほか 7 件 |
| U1: 通知の入口で初期化を確かめない | `ManualInitTest.everyOperationIsNotInitializedBeforeInit` |

## TB-8（2026-10-05）

### 作ったもの

- C: `src/Share/Share.{h,cpp}`（OP-43〜OP-54 の 12 関数）。クラスの表と CMake に登録した
- Kotlin: `capi/jni/ShareBridge.kt`（開く操作、選択の待ちの対、Direct Share、2 つの受け口）
- テスト:
  - GoogleTest `Share` 13 件（Sharesheet は UiAutomator で操作し、試験アプリの `ShareTargetActivity`（「NTK target」）を選ぶ）
  - noStartup の「初期化の前の全操作」に Share の 10 関数と取り消しを足した
  - 試験の土台: `ShareInspector`（PNG、共有するファイル、Direct Share のショートカット、Kotlin から直接開く Share）、`UiDriver.pick`・`sharesheetShown`・`backToApp`

### 実装の判断

| 判断 | 理由 |
|---|---|
| 開く操作は種類 400 で受け付け、main で前面を確かめてから Kotlin を呼び、すぐ帳簿から外す。完了は「開けた（`NONE`）」か失敗の値 | 6.4。Share には取り消しが無い（`CANCELED` が無い） |
| `ntk_share_text` はアクションが 0 個でも `shareTextWithActions` を呼ぶ | AP-7。前の Share のアクションを止める |
| 選択の要求の ID は受け付けの登録の ID。Kotlin の印が返ったら、前の対を全部消してから新しい対を入れる。開く処理が失敗したら対は変えない | AP-17。Kotlin は新しい印で前の待ちを置き換える |
| 取り消しは常に main に積み、main で対を引いて `cancelShareSelection` を呼ぶ。初期化の前は `NONE` | AP-17。開く処理が必ず先に動く。初期化の前に有効な ID は無い |
| 対の無い印の選択（Kotlin から直接開いた Share、取り消した要求）は捨てる | AP-17 |
| 入口の検査: 空文字列の本文は `EMPTY_CONTENT`、ファイルと ID の 0 件は `EMPTY_FILE_LIST`・`EMPTY_ID_LIST`（`NULL` で 0 件も）、Chooser Action の空・重複・`NULL` の ID とアイコンの無いものは `INVALID_CHOOSER_ACTION`、Direct Share のアイコンが無いものは `INVALID_ICON` | AP-19、6.4 |
| Chooser Action の `label` の `NULL` は `""`、Direct Share の `category` の `NULL` は `"android.shortcut.conversation"`、画像の MIME の `NULL` は `"image/*"` | 6.4、8.1 |
| Share のイベントは保たない | 6.4（`EventHub` も保たない） |

### テストで分かったこと

- **Sharesheet は前面を奪わない**: Android 14 以降の Sharesheet は、半透明の下からのシートで別のタスクにある。下のアプリの Activity は started のままなので、第 1 部 5.8 の判定ではアプリは前面にいる。「Sharesheet が出ている間の要求は `NOT_FOREGROUND`」というテストの前提が誤りだった。前面でない状態は、Sharesheet を残したままアプリの Activity を閉じて作る
- **続けて 2 つ開くと、Sharesheet は 1 つしか出ない**: 2 つ目の起動が 1 つ目を前に出すことがあり、出るのは古い方だった。古い方での選択は届かない（AP-17 のとおり）。テストは「届いた選択は新しい ID だけ」を確かめる
- **試験の共有先は一覧の下の方に出る**: Pixel ではアプリが多く、試験アプリの共有先は 16 番目だった。サンプルの UI テストの `Sharesheet` と同じく、待ってからシートを広げて送る。画面の下の端から送るとタスクバーに当たって送れず、上の端で下へ引くとシートが閉じる
- **Dialog のテストの不安定**: エミュレーターで 1 回、Dialog が出る途中のクリックが落ちた。`UiDriver.click` が画面が落ち着くのを待ってから押すようにした
- **起こせない失敗**: `NO_SHARE_TARGET` は Chooser の起動が `ActivityNotFoundException` になったときだけで、端末では起こせない（写しは表のとおり）

### 確かめたこと

- capi のテスト 138 件（startup 119、noStartup 16、noNtkInitializer 3）が Pixel 6a とエミュレータで通る
- release の `libntk.so` の公開は `ntk_*` 155（8.2 と同じ）。`check_c_abi_contract_android.py --library` が symbols まで含めて通る
- 公開の 155 関数は、すべてどれかのテストが呼ぶ

### 変異（Pixel 6a、startup の Share の GoogleTest）

| 変異 | 落ちたテスト |
|---|---|
| S1: アクションが 0 個の Share で `shareText` を呼ぶ（前のアクションを止めない） | `ChooserActionsReachTheListenerAndEndWithTheNextShare` |
| S2: 前面を確かめない | `FromTheBackEveryOpeningIsNotForeground`、`ANotForegroundRequestLeavesTheEarlierWait` |
| S3: 新しい印のときに前の対を消さない | なし。Kotlin が古い印の選択を出さない（`ShareCallbackCoordinator.deliver`）ので、残った対は使われない（等価な変異。AP-17 の「害は無い」のとおり） |
| S4: 対の無い印の選択も配る | `APickOfAShareKotlinOpenedIsNotDelivered` |
| S5: 取り消しが対も Kotlin の待ちも消さない | `ACanceledWaitGetsNoPick` |
| S6: 空文字列の本文を入口で通す | `TheEntryChecksReturnAndReleaseOnTheCallingThread` |
| S7: 重複した Chooser Action の ID を入口で通す | `TheEntryChecksReturnAndReleaseOnTheCallingThread` |
| S8: `FileNotFound` を `ILLEGAL_FILE_ACCESS` に写す | `FailuresFoundByKotlinComeInTheCompletion` |
| S9: 選択に C の要求の ID ではなく Kotlin の印を付ける | `ThePickedAppArrivesWithTheRequestId` ほか 3 件 |
| S10: Chooser Action の受け口を `EventHub` に足さない | `ChooserActionsReachTheListenerAndEndWithTheNextShare` |
| S11: Direct Share の削除が何もしない | `DirectShareTargetsAreRegisteredAndRemoved` |
| S12: `ntk_share_listener_remove` が何もしない | `RemovingAListenerKeepsTheWaitAndTheActions` |

## TB-9（2026-10-10）

### 作ったもの

- テスト:
  - GoogleTest `NoWait.EveryPublicFunctionReturnsWhileTheMainThreadIsHeld`: main を止めた状態で、公開の 155 関数を全部、別のスレッドから 1 回ずつ呼び、20 秒の期限内に戻ることを確かめる。Kotlin まで届く引数で呼び、main を放した後に開いた Dialog・Sharesheet・通知などを片づける
  - noStartup の `theKotlinMarkArrivingBeforeTheNativeMarkStillMakesItReady`: `JNI_OnLoad` の中で、表づくりと `MarkNativeDone` の間に Kotlin の完了の印（`onKotlinReady`）が来る順番を起こし、状態が `READY` になることを確かめる
- デバッグ専用のフック `ntk_debug_runtime_before_native_done`（`Runtime.cpp`。release には無い）: `JNI_OnLoad` と `ntk_android_init` の、表づくりと `MarkNativeDone` の間で呼ぶ
- HWASan の試験用ビルド `-Pntk.hwasan=true`: arm64 だけ、libntk と試験のライブラリを `c++_shared` と `-fsanitize=hwaddress` で組み、試験の APK に `wrap.sh`（`LD_HWASAN=1`）を入れる。通常のビルドは変わらない

### 実装の判断

| 判断 | 理由 |
|---|---|
| 「main を待たない」は、公開の 155 関数を 1 つのテストで全部呼ぶ。関数の一覧は、release の `libntk.so` の公開とテストの中の呼び出しを突き合わせて確かめた | 第 1 部 6 章（第 2 部の関数の一覧から作る）。待つ関数が 1 つでもあると、main を止めている間は戻らないので期限で分かる |
| 初期化の競合は `JNI_OnLoad` の経路で起こす | `ntk_android_init` の経路は、`MarkNativeDone` の後に自分で Kotlin を呼んで `READY` に届くので、`MarkNativeDone` の確かめを外しても結果が変わらない（変異で分かった）。`JNI_OnLoad` の後は誰も Kotlin を呼ばないので、ここだけが確かめになる |
| HWASan のビルドは `c++_shared` を使う、試験だけのビルドにする | HWASan は静的な libc++ に対応しない（NDK の toolchain が拒む）。配る `libntk.so` は `STL=none` と手でリンクした libc++ のまま（AC-12）。このビルドは配らない |
| CheckJNI は追加の設定をしない | 試験の APK は debuggable なので、ART が自動で `-Xcheck:jni` を有効にする（logcat の `Late-enabling -Xcheck:jni`）。これまでの実行はすべて CheckJNI の下で流れている |

### テストで分かったこと

- **AGP 9 の library モジュールでは `sourceSets` の古い API が使えない**（キャストの失敗）。`wrap.sh` は `androidComponents` の `variant.androidTest.sources.resources` で足した
- **この Mac のエミュレーターは arm64**（Apple Silicon、`sdk_gphone64_arm64`）。これまでのエミュレーターでの実行も arm64 のライブラリで流れていた（x86_64 は組むが流していない）
- **HWASan が有効なことの確かめ**: 試験のプロセスの環境に `LD_HWASAN=1` があり、メモリの地図に `libclang_rt.hwasan-aarch64-android.so` と `[anon:hwasan threads]` がある
- **HWASan のプロセスでは Dialog のボタンが大文字で出る**: `wrap.sh` で起動したプロセスでは、Dialog のボタンが「YES」「NOPE」と表示され、アクセシビリティの文字も大文字になった（通常のビルドでは「Yes」）。`UiDriver` の `waitText`・`click`・`gone`・`staysAway` を、大文字と小文字を区別しない探し方にした。探せなかったときは、画面に出ている文字を logcat に書く
- **結果が Gradle に届かないことが 2 回あった**（原因は分かっていない）:
  - HWASan の 1 回目: startup の 120 件が端末ですべて終わった後、Gradle が受け取った結果が 57 件のまま止まった（オーケストレーターを止めて終えた）。2 回目は 120 件すべてを受け取って終わった
  - 通常のビルドのエミュレーター: 1 件（`Notification.InvalidArgumentsAreRejectedAtTheEntry`）の結果が届かず、119 件で失敗になった。その回の logcat には、そのテストの「開始」と「終了」の 2 行だけがあり、GoogleTest のケースが動いた記録が無い。単独で流すと通り、startup の全体を流し直すと 120 件が届いた
  - どちらも、テストの失敗ではなく、オーケストレーターから Gradle への結果の受け渡しの不具合に見える。TB-11 で `test_android.sh` につなぐときに、結果の件数がケースの数と合わないことを失敗として扱い、logcat の件数と突き合わせる

### 確かめたこと

- 通常のビルド: capi のテスト 140 件（startup 120、noStartup 17、noNtkInitializer 3） が Pixel 6a とエミュレータで通る
- HWASan のビルド（Pixel 6a、API 36）: startup 120 件、noStartup 17 件、noNtkInitializer 3 件が通り、`HWAddressSanitizer` の報告は 0 件
- release の `libntk.so` の公開は `ntk_*` 155 と `JNI_OnLoad` のまま（デバッグ専用のフックは入らない）

### 変異（エミュレータ。main を待たないことは startup、初期化の競合は noStartup）

| 変異 | 落ちたテスト |
|---|---|
| W1: `hasClip` が main を待つ | `NoWait.EveryPublicFunctionReturnsWhileTheMainThreadIsHeld` |
| W2: `hasPermission` が main を待つ | `NoWait.EveryPublicFunctionReturnsWhileTheMainThreadIsHeld` |
| R1: `MarkNativeDone` が先に立った Kotlin の印を見ない | `ManualInitTest.theKotlinMarkArrivingBeforeTheNativeMarkStillMakesItReady`（`JNI_OnLoad` の経路にした後。`ntk_android_init` の経路のテストでは通ってしまった） |

### 確かめていないこと

- **x86_64 のライブラリは一度も動かしていない**: この Mac のエミュレーターは arm64 で、Pixel 6a も arm64。AAR には x86_64 の `libntk.so` も入る（`abiFilters`）が、組むだけで流していない

## TB-10（2026-10-10）

### 作ったもの

- 発行（`7bf7f6ab`）: `android_library` と `android_library_capi` に `maven-publish`。座標は `io.github.kimjh4941:android-native-toolkit` と `:android-native-toolkit-capi`（D-17）。POM と Gradle Module Metadata の Kotlin の版を `kotlinConsumer`（2.2.21）に固定（`coreLibrariesVersion`、Parcelize のランタイムの `force`、`versionMapping`）
- ビルドスクリプト `build_android_library_aar.sh`（同）: `android_library_capi`（Gradle のプロジェクトは `:ntk`）、`dist/<版>/android/include/NativeToolkitC/` へのヘッダーの写し、`--m2`（発行して `dist/<版>/android/m2/` を作り直す）
- 配布物の照合 `scripts/check_android_dist.py` と自己テスト 15 件（同。Module Metadata の照合と 1 件は後から足した）
- smoke `android/android_library_capi_smoke/`: `m2/` だけで組む C のアプリ（`android/` のビルドとは別のビルド）。R8 を有効にした release に対する計装テスト。`-Pstl=`（3 通り）、`auto` / `manual` の 2 つの flavor、`-PnoKeep=true`、`-Pabi32=true`（32 ビットの自前のライブラリを `:stub32` から）
- Kotlin の利用者 `android/android_library_kotlin_consumer/`: AGP 8.10、Gradle 8.13（自分の wrapper）、`-Pkgp=` の KGP で、両方の AAR を使うコードをコンパイルする
- 実行のスクリプト `scripts/run_android_capi_smoke.sh`: 上の全部を 1 台の端末に流し、項目ごとに PASS / FAIL / SKIP を出す

### 実装の判断

| 判断 | 理由 |
|---|---|
| smoke と Kotlin の利用者は、`android/` のビルドに入れない別のビルドにする | 同じビルドにあると、プロジェクトの依存で組めてしまい、配布物（`m2/`）だけで組めることを確かめられない |
| 後ろからの Progress と 32 ビットは、計装の外で adb から起こし、logcat で読む | 計装の下では後ろからのフォアグラウンドサービスの開始が許される（TB-6）。32 ビットはインストールのしかたそのものを変える |
| 32 ビットの自前のライブラリは、Prefab を使わない別のモジュール（`:stub32`）で作り、アプリの CMake は 64 ビットだけにする（`externalNativeBuild.cmake.abiFilters`）。APK に入れる ABI（`ndk.abiFilters`）には armeabi-v7a を入れる | 下の「テストで分かったこと」の CXX1210。Unity のような、32 ビットの自前のライブラリを持つアプリと同じ形 |
| 照合は jni/ と Prefab の `libntk.so` を strip してから比べ、16 KB の整列と依存は両方を見る | AGP は jni/ に入れる方だけを strip する（Prefab の方はリンクとデバッグのために残す） |
| 照合は POM に加えて Gradle Module Metadata の全 variant の Kotlin の版も見る | Gradle の利用者は POM より Module Metadata を先に読む（下の「テストで分かったこと」） |
| `dist/<版>/` は作って確かめた後に消し、コミットしない | `dist/` はリリースのときにコミットする運用。smoke は README のとおり、ビルドが作る一時的なリポジトリ `android/build/m2` から組む |

### テストで分かったこと

- **POM が正しくても Module Metadata が違っていた**: capi の Module Metadata の実行時の variant に `kotlin-stdlib` 2.4.20 が書かれ、Kotlin 2.1 / 2.2 の利用者が組めなかった（`The binary version of its metadata is 2.4.0`）。`android_library` の Parcelize のランタイムの固定は、capi が `android_library` を解決するときには効かない。capi にも同じ固定を入れた。最初の照合は POM だけを見ていて見逃したので、Module Metadata を見るようにし、自己テストを足した
- **capi の POM は `android-native-toolkit` に実行時の依存**: capi の公開の Kotlin の口は `android_library` の型を出さないので正しい。Kotlin の API も使う利用者は、両方を宣言する（README 3 章のとおり。マニュアルに書く）
- **アプリの CMake が 32 ビットも組むと Prefab で止まる**: AGP は CMake が組む ABI ごとに Prefab のパッケージを確かめ、armeabi-v7a が無いと `CXX1210: No compatible library found [//ntk/ntk]` で止まる。C ABI は 64 ビットだけなので（D-10）、32 ビットも組むアプリは、C ABI を使う CMake の ABI を 64 ビットに絞る必要がある（マニュアルに書く）
- **手動の経路では Activity を渡す**: Startup を外すと、前面の Activity を追う仕組みはアプリの起動の時点では動いていない。`ntk_android_init` に Application の Context を渡すと、前面の Activity が分からず Dialog が出なかった。Activity を渡すと、それが最初の前面の Activity になる（第 1 部 1.4、K-5。マニュアルに書く）
- **R8 で縮めた release を計装でテストするとき**: テストはアプリのプロセスで、アプリの側のクラスを使う。androidx.test が使い、アプリが使わない `androidx.tracing` と Kotlin の標準ライブラリの一部が削られて起動で落ちたので、smoke のアプリの規則で残した（C ABI のクラスとは関係しない）
- **別のビルドは SDK の場所を知らない**: `android/local.properties` は `android/` のビルドだけが読む。smoke と Kotlin の利用者は `ANDROID_HOME` で渡す（実行のスクリプトが入れる）
- **ビルドスクリプトは `gradle.properties` の `libraryVersion` を書き換える**（前からの動き）。開発中に試したときは戻した

### 確かめていないこと

- **x86_64 で動かすこと**（第 1 部 G-3）: 手元の 2 台は arm64。x86_64 の `libntk.so` は、組めること、公開関数（155 と `JNI_OnLoad`）、16 KB の整列、`libc++_shared` に依存しないことを、配布物の照合で確かめた
- **`NO_SHARE_TARGET` などの端末で起こせない失敗**（TB-6、TB-8）は smoke でも起こしていない

### 確かめたこと

- `scripts/run_android_capi_smoke.sh`（版 2.0.0、`android/build/m2`）:
  - Pixel 6a（API 36）: 12 項目すべて PASS（smoke 6、keep の規則なし 2、後ろからの Progress、32 ビット、Kotlin 2.2.21 と 2.1.21）
  - エミュレータ（API 35、arm64）: 11 項目が PASS、32 ビットは SKIP（32 ビットの ABI が無い）
- 配布物の照合（2.0.0 を `dist/` に作って流した）: すべて OK。自己テストは scripts/tests の全 196 件が通る
- `android_library` の単体テスト 166 件が、Kotlin の版の固定の後も通る

## TB-11（2026-10-10）

### 作ったもの

- `scripts/test_android.sh` に「6c. The C ABI」を足した:
  - `android_library_capi_test` の 3 つのフレーバー（経路ごとのプロセス）を Gradle の connected のタスクで流し、ケースを 1 件ずつ結果（`capi-<フレーバー>:<クラス>#<名前>`）にする。Gradle の実行は 3600 秒で打ち切る（`perl` の `alarm`。macOS に `timeout` が無い）
  - release の `libntk.so` を ABI ごとに `check_c_abi_contract_android.py --library` で照らす（`capi-contract:<ABI>`）
  - `m2/` に発行して `run_android_capi_smoke.sh` を流し、項目ごとに結果にする（`capi-smoke:<項目>`）
  - `--hwasan`: HWASan のビルドでも 3 つのフレーバーを流し、`HWAddressSanitizer` の報告が無いことを確かめる（arm64、API 34 以上。基準には入れない）
  - `--filter CApi` で C ABI の分だけを流せる。単体テストに `:ntk:testDebugUnitTest` を足した
- `scripts/android_capi_results.py`: Gradle の結果の XML と logcat から結果の行を作る。logcat があるのに結果の無いケースは `#resultLost` の失敗にする。smoke の PASS / FAIL / SKIP を結果の行にする

### テストで分かったこと

- **TB-9 から続いた「結果が届かない」の正体**: `Notification.InvalidArgumentsAreRejectedAtTheEntry` の結果が届かないのは、2 回とも同じケースだった。logcat を全部取って再現すると、そのテストのプロセスが「タスクの削除」（`Killing ... remove task`）で止められていた。直前の `NoWait` が開いた設定の画面と Sharesheet を Back で閉じる動きが、次のケースのプロセスが同じタスクで始まった後まで続き、タスクごと消された。ライブラリの不具合ではなく、テストの後片づけの重なり
- 直し:
  - `NoWait` の Share は、画面を開かずに Kotlin まで届く引数にした（空白だけの本文は `EMPTY_CONTENT`、無いファイルは `FILE_NOT_FOUND`）。設定の画面は開き、出るのを待ってから Back で閉じ、消えるまで待つ（`UiDriver.closePackage`）
  - `NtkGoogleTest` の各ケースの後に、アプリを前に戻し、設定の画面と Sharesheet が消えるまで待つ
  - 直した後、`NoWait` と次のケースを並べて 4 回流し、4 回とも通った（落ちない）
- **`--filter CApi` の 1 回目（Pixel）**: 上のクラッシュの 1 件のほかは通った（契約の照合 2、smoke 12、noStartup 17、noNtkInitializer 3、startup 119）。`android_capi_results.py` が、届かなかった結果を `#resultLost` として拾えることも確かめた

## レビュー（v1）の対処（2026-10-10）

指摘と対処の一覧は `reviews/2026-10-10-android-c-abi-stage2b-review-v1.md` にある。ここには、対処の中で分かったことと判断を書く。

### 実装の判断

- 取り消しと解除（`Registry::Cancel`）は、その関数の種類の登録だけを動かす（K-M7）。種類が違えば何もせずに `false` を返す。解除のメッセージを main に積めなかったときは、`CANCEL_REQUESTED` を `ACTIVE` に戻して `false` を返す（K-M2）。積めない間に登録が消えていれば（完了が先に来た）、取り消しは済んだものとして `true` を返す
- 記憶が足りないとき（K-C2 / K-M1）は、`std::set` と `std::vector` を使わない形に変えて、入口で例外が起きる場所そのものを無くした（Share の重複の確かめは `strcmp` の二重ループ、Dialog の複数選択は 1 つずつ設定）。表づくりは `try` / `catch` で囲み、`JNI_FAILURE` にしてやり直せるようにした
- Kotlin の側の main に積むラムダは、`MainTasks.post` で例外を捕まえてログに出す（K-M3）
- 後ろに回したアプリを前に戻すときは、シェルの `am start` ではなく、アプリの Context から `FocusActivity` を `REORDER_TO_FRONT` で開く。シェルは公開していない Activity を開けない（`Permission Denial ... not exported`）。アプリ自身の起動は、計装の間は後ろからでも許される（`BAL_ALLOW_PERMISSION`）

### テストで分かったこと

- **`exit` で落ちない（K-C5）は、プロセスを終わらせるテストでは確かめられない**。端末（Pixel 6a、API 36）で、`:ntkexit` という別のプロセスで C ABI を忙しくして（変更の受け手と監視、プローブの受け手、保留中のプローブの操作、C ABI を呼び続ける 4 本のスレッド）から終わらせる形を試した:
  - Activity のプロセスで C の `exit(0)`: OS の描画のスレッド（`hwuiTask0`）が `FORTIFY: pthread_mutex_lock called on a destroyed mutex` で落ちた
  - Receiver のプロセスで C の `exit(0)`: ART の `Jit thread pool` が SIGSEGV で落ちた（5 回とも）。C ABI を使わず、`libntk_test.so` を読むだけでも同じだった（3 回とも）
  - Receiver のプロセスで `System.exit(0)`: 落ちない（ネイティブを読まずに 3 回、読んで 3 回、C ABI を忙しくして 5 回）。ただし、`libntk.so` の `ntk_clipboard_has_clip` に、デストラクタを持つ静的な `std::mutex` を足す変異は、呼ぶスレッドが 1 本で 2 回、4 本で 3 回、どれも生き残った。デストラクタでログを出す静的な変数を置くと、ログは出なかった。`System.exit` は静的なデストラクタを走らせない
  - bionic の libc++ では、`std::mutex` のデストラクタは trivial ではない（`_LIBCPP_HAS_TRIVIAL_MUTEX_DESTRUCTION` は glibc、Fuchsia、Windows だけ）。変異が生き残ったのは、デストラクタが走らなかったため
- そこで、5.5 の規則（静的なデストラクタを持つ変数を置かない）そのものを照合にした。配る `libntk.so` が `__cxa_atexit` と `atexit` を import していないこと（`check_android_dist.py`）。上の変異で release の `libntk.so` にこの import が現れることを確かめた。debug の `libntk.so` は `__cxa_atexit` を import するが、これは crtbegin の `atexit` の包みが残っているだけで（debug は使わない部分を削らない）、呼ぶ所は無い。配るのは release なので、照合は release を見る
- 第 1 部 6 章の「`exit` で落ちない」の行の置き場所を、別のプロセスのテストから配布物の照合に変えた（第 1 部 0.7）
- `Share.ALaterOpeningReplacesTheWait` は、出ている Sharesheet の本文（「Earlier」か「Later」）で場合を分けた（K-X2）。Pixel では新しい方が出た

## レビュー（v2）の対処（2026-10-10）

指摘と対処の一覧は `reviews/2026-10-10-android-c-abi-stage2b-review-v2.md` にある。

### 実装の判断

- **解除を積めなかった取り消しは、ACTIVE に戻さない**。v1 の対処（K-M2）で「戻して `false` を返す」形にしたが、3 本のレビュアーがそれぞれ、main と競うと `release` が呼ばれない道を見つけた。main は CANCEL_REQUESTED を見て完了・開始・配送を見送り、「積まれた解除が解放する」と任せる。そのため、後から ACTIVE に戻すと、誰も解放しなくなる。CANCEL_REQUESTED は「外すことが決まった」印として、一度付けたら外さない。積めなかった解除は列に入れ、main が次に C に入ったとき（`nativeRemove`、`nativeIsActive`、`CompleteOnMain`、`DeliverOnMain`）に流す。流すときは Kotlin の帳簿からも外す（`Ledger.drop`）
- 列を流す入口に `nativeIsActive`（挿入の確かめ）を入れたのは、挿入の前の取り消しで、その登録が開始されないまま残らないようにするため
- `applicationContext` が null の Context（Application ができる前）は、Context そのものを持つ。Activity ではないので、K-M8 の心配（Activity を持ち続ける）は無い
- 照合の「必ずある import」は `__cxa_finalize` にした。crtbegin がどの `.so` にも入れるので、読めたかどうかの印になる

### テストで分かったこと

- 変異「積めなかった解除を流さない」で、結果や完了が先に積まれた 2 件は通った。完了の側（`CompleteOnMain`）が CANCEL_REQUESTED を見て、取り消しの完了と解放を自分でするため。この 2 件が守るのは「ACTIVE に戻さない」ことで、前の形を入れると落ちる
- ProbeTest の 1 件は、テストの中の 2 回目の取り消しが、前の形の穴を埋めていた（1 回目が ACTIVE に戻した後、2 回目は積めて解放される）。外して、前の形で落ちることを確かめた
- `DetachOnThreadExit` の `GetEnv` の確かめを外す変異は生き残った。ART は attach していないスレッドの detach に `JNI_ERR` を返すだけで、落ちない
