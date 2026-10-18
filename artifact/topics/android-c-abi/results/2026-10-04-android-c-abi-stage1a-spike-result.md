# 段階 1a スパイク結果: NDK のビルドと C ABI の前提

- 実施日: 2026-10-04
- 対象: `artifact/topics/android-c-abi/README.md` の段階 1a と 8.2
- ブランチ: `feature/NTKIT-17`
- 環境: NDK r30（30.0.16248370）、CMake 3.31.6、AGP 9.3.1、Kotlin 2.4.20。端末は Pixel 6a（API 36）と API 35 のエミュレータ（どちらも arm64-v8a）
- 判定: **完了**（8.2 の 8 項目のうち 7 項目を確かめた。Unity の `DllImport` の 1 項目は 2c に回す。4 章）

## 1. 結論

C ABI の雛形（`libntk.so` と Kotlin の受け口）、利用者のアプリ、テスト用のモジュールを組み、両方の環境で動かした。企画書の前提のうち 3 つは、そのままでは成り立たないことが分かった。どれも直し方を見つけて実物で確かめた。

| 前提（企画書） | 実際 | 直し方（確かめ済み） |
|---|---|---|
| `c++_static` で組み、Prefab で配る（D-9、D-10） | AGP の Prefab は、`c++_static` の共有ライブラリを、STL を使う利用者とも使わない利用者とも組ませない（CXX1211 / CXX1213）。**誰も取り込めない** | `ANDROID_STL=none` で組み、NDK の `libc++_static.a` と `libc++abi.a` を自分でリンクする。Prefab には `"stl": "none"` と書かれ、STL なし・`c++_static`・`c++_shared` の 3 通りの利用者がすべて組めて動いた（3.3） |
| `JNI_OnLoad` は `System.loadLibrary("ntk")` のときに 1 回だけ走る（D-4） | 利用者が自分の `.so`（`libntk.so` に依存し、自分の `JNI_OnLoad` を持たない）を `System.loadLibrary` すると、ART が `dlsym` で依存先の `JNI_OnLoad` を見つけ、**もう一度呼ぶ**。2 回目は利用者のクラスローダーの文脈で、ここで `JNI_ERR` を返すと利用者の `System.loadLibrary` が失敗する | `JNI_OnLoad` を冪等にする（2 回目以降は何もせず `JNI_VERSION_1_6` を返す）。設計で決める（3.2） |
| `languageVersion = apiVersion = 2.2` なら Kotlin 2.1 以上の利用者が使える（8.3） | KGP 2.4.20 は POM に `kotlin-stdlib:2.4.20` と `kotlin-parcelize-runtime:2.4.20` を書く。Kotlin 2.2.21 と 2.1.21 の利用者は、stdlib のメタデータ 2.4 を読めず**組めない** | `coreLibrariesVersion = "2.2.21"` と、Parcelize のランタイムを 2.2.21 に固定して POM に解決後の版を書く（`versionMapping`）。2.2.21・2.1.21 の利用者が組め、実行時の Parcel の往復も動いた（3.6） |

## 2. 雛形の構成

コードは `probes/stage1a/` にある（ビルドには入れない。`settings.gradle.kts` はその場所からの相対パス）。

| モジュール | 中身 |
|---|---|
| `spike1a/capi` | `libntk.so`（C++20、`-fvisibility=hidden`、version script で `ntk_*` と `JNI_OnLoad` だけを公開、16 KB のページ、`libnativehelper` にリンク）と、Kotlin の受け口 `NtkNative`（`RegisterNatives` で結ぶ `nativeHello`、C から呼ばれる `onNativeCallback`）、`androidx.startup` の `NtkInitializer`（`System.loadLibrary("ntk")`）。`prefabPublishing` でヘッダーを配る |
| `spike1a/consumer` | 利用者のアプリ。R8 を有効にした release で組む。Prefab で `libntk.so` のヘッダーを使う C のコードと、`std::string` を使う C++ のコード。`-Pstl=` で利用者の STL を、`-PnoStartup=true` で Startup を無効にした `dlopen` だけの読み込み（`dart:ffi` と同じ）を切り替える |
| `spike1a/capitest` | テスト用のモジュール。GoogleTest v1.18.0 をソースから取り込み（`FetchContent`、SHA-256 で固定）、`libntk.so` を Prefab で使う `libntk_test.so` を組む。instrumented テストから GoogleTest を走らせる |
| `kc22` | Kotlin でコンパイルする利用者。AGP 8.10.0、Gradle 8.13、KGP を `-Pkgp=` で切り替える（2.2.21、2.1.21）。`android_library` を POM 付きのファイルの Maven リポジトリから使う |

## 3. 項目ごとの結果（README 8.2）

### 3.1 `JNI_GetCreatedJavaVMs` で JavaVM を取れるか（D-4）

取れる。minSdk 31 では NDK の `jni.h` が宣言し、`libnativehelper.so` にある。両方の環境で VM が 1 つ返り、`JNI_OnLoad` で受け取った VM と同じだった。Startup を無効にして `dlopen` だけで開いたとき（`JNI_OnLoad` は走らない）も、VM は取れた。

ただし、そのときアプリのクラス（`NtkNative`）は引けない。native のスレッドの `FindClass` はシステムのクラスローダーを使うので、アプリのクラスを引くには、アプリのクラスローダー（Context から取る）が要る。雛形では「未初期化」として扱えた（`call_kotlin=-1`）。

→ D-4 の「Initializer と `ntk_android_init` の両方」が実物で裏付けられた。Startup を無効にした利用者には、Context を渡す明示の初期化が要る。JavaVM は `JNI_GetCreatedJavaVMs` で取れるので、`ntk_android_init` の引数に JavaVM は要らない。

### 3.2 `RegisterNatives` と公開シンボル、R8 を有効にした利用者

| 確認 | 結果（両方の環境、R8 を有効にした release） |
|---|---|
| `JNI_OnLoad` での `RegisterNatives` | `nativeHello` を `Java_` のシンボル無しで結べ、呼べた |
| R8 との組み合わせ | AAR の consumer の規則（`-keep class ...NtkNative { *; }`）で、名前で引くクラスとメソッドが残った |
| C から Kotlin を呼ぶ | 呼び出し元のスレッドからも、新しく作ったスレッド（`AttachCurrentThread` / `DetachCurrentThread`）からも呼べた |
| 公開シンボル（`llvm-nm -D --defined-only`） | arm64-v8a・x86_64 とも `JNI_OnLoad` と `ntk_*` の 6 つだけ。libc++ のシンボルは出ていない |
| 16 KB のページ（`llvm-readelf -l`） | すべての LOAD が `0x4000` |
| 依存（`DT_NEEDED`） | `liblog`、`libnativehelper`、`libm`、`libdl`、`libc` だけ。`libc++_shared.so` は要らない |
| 大きさ | 約 0.9 MB（arm64-v8a、strip 前。libc++ を含む） |

**`JNI_OnLoad` が 2 回呼ばれる:** 利用者のアプリの起動時に、`NtkInitializer` の `System.loadLibrary("ntk")` で 1 回、その後に利用者が `System.loadLibrary("consumer")` を呼んだときにもう 1 回、同じプロセス・同じスレッドで呼ばれた（logcat で確認）。ART は読み込んだライブラリの `JNI_OnLoad` を `dlsym` で探し、`dlsym` はライブラリの依存先も探すので、自分の `JNI_OnLoad` を持たない `libconsumer.so` から `libntk.so` のものが見つかる。雛形は毎回 `FindClass` と `RegisterNatives` をやり直し、グローバル参照も漏れていた。2 回目は利用者のクラスローダーの文脈なので、`FindClass` が失敗して `JNI_ERR` を返すと、利用者の `System.loadLibrary` が `UnsatisfiedLinkError` になる。

→ 設計で決めること: `JNI_OnLoad` を冪等にする（1 回目だけ初期化し、2 回目以降はそのまま `JNI_VERSION_1_6` を返す。初期化は `std::call_once` などで 1 回に限る）。

### 3.3 STL と Prefab（D-9、D-10）

| `libntk.so` の組み方 | `abi.json` の `stl` | 利用者が STL なし | 利用者が `c++_static` | 利用者が `c++_shared` |
|---|---|---|---|---|
| `ANDROID_STL=c++_static`（企画書の案） | `c++_static` | 失敗（CXX1213: User requested no STL but library requires libc++） | 失敗（CXX1211: Library is a shared library with a statically linked STL and cannot be used with any library using the STL） | 失敗（CXX1211） |
| `ANDROID_STL=none` + `libc++_static.a` と `libc++abi.a` を手でリンク | `none` | 組めて動いた | 組めて動いた | 組めて動いた |

3 通りの利用者のアプリを、両方の環境で動かして確かめた。`c++_static`・`c++_shared` の利用者は自分の C++ のコードで `std::string` を使い、`libntk.so` の中の libc++ とぶつからなかった。STL なしの利用者は自分の C++ のコードで `<string>` を使えない（利用者の側の当然の制約で、C だけで組んだ）。

手でリンクする形は、CMake で NDK の sysroot（`${ANDROID_TOOLCHAIN_ROOT}/sysroot`）の `usr/include/c++/v1` を include に足し、`usr/lib/<triple>/libc++_static.a` と `libc++abi.a` をリンクする。triple は `ANDROID_ABI` から決める（NDK の新しい toolchain では `ANDROID_TOOLCHAIN_NAME` が定まらないため）。公式の文書（Prefab、Android の「ネイティブの依存」）には、この規則と回避の手段の説明が無かった。

**Prefab のパッケージの名前:** Prefab のパッケージ名は、AAR を作る Gradle のプロジェクトの名前になる（雛形では `capi`。`ntk` はその中のモジュール名）。利用者は `find_package(capi)` と `capi::ntk` と書く。本番ではプロジェクト名 `android_library_capi` がそのまま利用者の書く名前になるので、設計で決める。

### 3.4 テスト用の `.so` を別のモジュールに置けるか（7 章）

置ける。`:capi` の AAR に入るのは `libntk.so`（`jni/` と `prefab/`）、ヘッダー、Prefab の情報、`classes.jar` だけで、テスト用のものは入らなかった。`libntk_test.so` は `:capitest` のテストの APK にだけ入る。

### 3.5 GoogleTest の入れ方

Prefab で配られているのは企画書のとおり 1.11.0-beta-1（Google の Maven）だけで、GoogleTest の最新は v1.18.0（2026-08）。v1.18.0 を `FetchContent` でソースから取り込み（GitHub のタグの tarball、SHA-256 `6e3191c1455468b3fc35a417fb565c1c5071aee1b7e7f85e30cf48a98d37d8b5`）、`c++_static` で組めた。4 件のケースが両方の環境で通った。

→ 設計で決めること:
- 取り込み方（ビルドのたびに取りに行く `FetchContent` か、リポジトリに置くか。置くなら BSD-3-Clause の LICENSE を同梱する）
- ケースごとの結果の見せ方。今は JUnit の 1 件にまとまり、ケースごとの結果は logcat にしか出ない。`test_android.sh` でケースごとに数えられるよう、ケースを JUnit に 1 件ずつ見せる形にする

### 3.6 Kotlin 2.2 の利用者が組めるか（8.3。段階 0g で発見）

| `android_library` の設定 | POM の `kotlin-stdlib` | POM の `kotlin-parcelize-runtime` | KGP 2.2.21 の利用者 | KGP 2.1.21 の利用者 |
|---|---|---|---|---|
| 今（KGP 2.4.20 の既定） | 2.4.20 | 2.4.20 | 組めない（`The binary version of its metadata is 2.4.0, expected version is 2.2.0`） | 組めない |
| `coreLibrariesVersion = "2.2.21"` だけ | 2.2.21 | 2.4.20（これが stdlib 2.4.20 を引き込む） | - | - |
| 上に加え、Parcelize のランタイムを 2.2.21 に固定（`resolutionStrategy.force`）し、POM に解決後の版を書く（`versionMapping` の `fromResolutionOf("releaseCompileClasspath")` / `("releaseRuntimeClasspath")`） | 2.2.21 | 2.2.21 | 組めた | 組めた |

最後の形で、利用者のアプリが実行時に受け取る Kotlin は 2.2.21 だった。通知の予約を作り、保存（Parcel を Base64 で保存）と読み戻し（`parcelableCreator`）の往復が両方の環境で動いた（Kotlin 2.4.20 の Parcelize のプラグインが作ったコードと、2.2.21 のランタイムの組み合わせ）。`versionMapping` の `fromResolutionResult()` は Android の構成を見ないので、POM に反映されなかった。

androidx の依存が求める stdlib は 2.1.20 まで。POM を作るのは段階 2b なので、本番の設定はそこで入れる。

### 3.7 Unity の利用者の minSdk（3.1）

`unity-native-plugin` の Player Settings は `AndroidMinSdkVersion: 25` だが、Android の Build Profile（`Assets/Settings/Build Profiles/Android™ Profile.asset` と `Test Android™ Profile.asset`）が `AndroidMinSdkVersion: 31` で上書きしていた。書き出し（`Build/Android/gradle.properties` の `unity.minSdkVersion=31`）はそこから来る。Unity がプラグインに合わせて自動で上げているのではない（Unity 6000.4.2f1 の Android のビルドのコードに、その処理は見当たらなかった）。

→ マニュアルの動作環境に、Unity の利用者は Minimum API Level を 31 以上にすると書く（ライブラリの minSdk が 31 なので、低いと manifest の merge で止まる）。

## 4. 確かめなかったもの

| 項目 | 理由 | 扱い |
|---|---|---|
| Unity 6 で `DllImport` した `.so` に `JNI_OnLoad` が呼ばれるか（8.2） | Unity の公式の文書に、Unity が `.so` を `System.loadLibrary` と `dlopen` のどちらで、いつ読むかの記述が無く、Unity で組んで実機で動かす必要がある。ただし企画書の形では、`NtkInitializer` がアプリの起動時に `System.loadLibrary("ntk")` を呼ぶので、Unity が読む前に `JNI_OnLoad` は済んでいる。2 回呼ばれる場合への備え（冪等にする）は、3.2 の発見で Unity と関係なく必須になった | 段階 2c（Unity の側を C ABI に移し、Unity のテストを流す段）で確かめる |
| x86_64 で動かすこと | 試験環境は 2 つとも arm64 で、x86_64 は動かせない（README 7 章） | 組めること、公開シンボル、16 KB の整列は確かめた |

## 5. README と設計への反映

| 対象 | 反映 |
|---|---|
| D-4 | 3.1 と 3.2（`JNI_OnLoad` の冪等、`dlopen` だけのときの未初期化、JavaVM は自動で取れる） |
| D-9 | 3.3 の Prefab のパッケージ名を設計で決める |
| D-10 | libc++ の組み方を「`ANDROID_STL=none` + 手でリンク」に改める（3.3） |
| 8.3 の Kotlin の行 | 3.6 の 2 つの設定を 2b で入れる |
| 8.2 | 各項目の結果へのリンク |
| C ABI の設計書 | D-6（コールバックのスレッド）・D-13 は、このスパイクの対象外（設計で決める）。3.2 の冪等、3.5 のテストの見せ方を設計に入れる |
