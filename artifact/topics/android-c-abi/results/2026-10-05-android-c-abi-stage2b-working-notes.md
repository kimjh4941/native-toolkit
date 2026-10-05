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
