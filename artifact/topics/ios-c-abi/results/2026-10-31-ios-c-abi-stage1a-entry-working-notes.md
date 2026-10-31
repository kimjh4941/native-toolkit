# 段階 1a の作業の記録（C の入口の層・配布の形・小さな振る舞い）

- 記録日: 2026-10-31
- 段階: 1a（`README.md` の 8.2 の表のうち、入口・配布・例外・`ntk_last_system_code`・UTF-8・サニタイザーの行。D-9、D-10、D-11、D-13、D-16、D-18）
- ブランチ: `feature/NTKIT-18`（HEAD `5f1172fd` の上の未コミットの変更）
- 環境: ビルドする側は Xcode 26.6（17F113、Swift 6.3.3、iOS 26.5 SDK）、利用者の側は Xcode 26.3（17C529、Swift 6.2.4、iOS 26.2 SDK）。どちらも `DEVELOPER_DIR` でコマンドごとに選び、`xcode-select` は変えていない。macOS 26.3（25D125）。シミュレーターは iPhone 17（iOS 26.2）、iPad (A16)（iOS 26.2）、iPad Pro 11-inch (M4)（iOS 18.3）だけ。**実機には触れていない**
- 受け持ち: 入口の層（A）、配布の形（B）、小さな振る舞い（D）。通知の delegate の転送と、delegate を入れる関数のスレッドは別のエージェント（`probes/stage1a/delegate/`）。本物の Unity のビルドは `unity-native-plugin` の agent が後で行う
- 状態: `@c @implementation` で雛形の `IosLibraryCApi` を組み、D-10 の 2 つの条件はシミュレーターで成り立った。代替案（C の入口と関数ポインタの表）も組んで比べた。実機の署名つきの archive だけは、利用者の provisioning profile（証明書）が要るので止めた（4.6）。コミットはしていない

## 1. 雛形と動かし方

雛形は `results/probes/stage1a/entry/` に置いた（使い捨て。ビルドには入れない）。Xcode のプロジェクトは `gen_projects.rb`（`xcodeproj` gem）が作業用のフォルダに作り、リポジトリにはソースとスクリプトだけを残す。`ios/IosLibrary` のプロジェクトは変えていない（コマンド行で `BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO` を渡して archive しただけ）。

| ファイル | 中身 |
|---|---|
| `capi/include/NativeToolkitC/Common.h` | Android の `Common.h` の写し（宣言は同じ。コメントの 2 か所だけ iOS に直した） |
| `capi/include/NativeToolkitC/Probe.h` | 雛形だけの関数: `struct_size` のある構造体を取る同期の関数（`ntk_probe_echo`）、コールバック・`user_data`・`release`・64 ビットの要求の ID を取る非同期の関数（`ntk_probe_clipboard_read_text_async`。`IosLibrary` の `IosClipboardManager.read` を呼ぶ）、main に積んだブロックの中で UIKit に例外を投げさせる関数。エラーは `int32_t`（0〜5 は共通の番号） |
| `capi/Sources/Entry.swift` | 14 個の `ntk_*` を `@c @implementation` で書いた入口（42 行。1 関数 1〜3 行） |
| `capi/Sources/Support.swift`、`ProbeImpl.swift` | Swift の受け口（ハンドル、UTF-8 の出入り、要求の ID、`release` をちょうど 1 回、`IosLibrary` の呼び出し）。代替案と共有する |
| `capi/Sources/ThreadLocal.c`、`capi/internal/` | `_Thread_local` の `ntk_last_system_code` と、Swift から見るためのビルドのときだけの module map（`NTKCApiInternal`。framework には入らない） |
| `capi/module.modulemap`、`capi/IosLibraryCApi.exp` | framework の module map（`NativeToolkitC/*.h`）と、公開するシンボル（`_ntk_*`） |
| `fallback/` | 代替案。C の入口（`Entry.c`）、表（`internal/Table.h`）、表を埋める Swift（`Table.swift`） |
| `tests/` | C ABI の XCTest（10 件）と、そのホストのアプリ |
| `smoke/` | C の利用者の smoke。C の関数の呼び出しは `Scenarios.c`（純粋な C）、UIKit の殻だけ `main.m` |
| `swiftapp/` | `import IosLibrary` と `import IosLibraryCApi` の両方を使う Swift のアプリ |
| `run.sh` | 手順（`ioslib`、`capi`、`inspect`、`test`、`consumers`、`exception`、`archive`、`fallback`、`clean`）。`STAGE1A_WORK`、`STAGE1A_SIM`、`STAGE1A_BUILD_XCODE`、`STAGE1A_CONSUMER_XCODE` を渡す |

capi の framework の主な設定（`gen_projects.rb`）: `DEFINES_MODULE=YES`、`MODULEMAP_FILE`、`PUBLIC_HEADERS_FOLDER_PATH=$(CONTENTS_FOLDER_PATH)/Headers/NativeToolkitC`、`EXPORTED_SYMBOLS_FILE`、`SWIFT_INCLUDE_PATHS`（内部の module map）、`SWIFT_INSTALL_OBJC_HEADER=NO`、**`SWIFT_INSTALL_MODULE=NO`**、`BUILD_LIBRARY_FOR_DISTRIBUTION=NO`、`ENABLE_MODULE_VERIFIER=YES`（C / C++ 系の 4 言語）、`SWIFT_VERSION=6.0`（strict concurrency は Swift 6 の既定の complete）、最小 iOS 18.0、bundle id `com.jonghyunkim.nativetoolkit.IosLibraryCApi`、署名なし。

クリップボードはシミュレーターの Mac への同期を避けるため、名前付きの pasteboard（`com.jonghyunkim.nativetoolkit.stage1a.probe`）だけを使った。

## 2. A: `@c @implementation` の入口

### 2.1 組めるか・振る舞い

- Xcode 26.6 で、`IosLibrary` に依存する dynamic の framework として組めた。device と simulator の archive で、警告もエラーも 0 件
- XCTest の 10 件が、iPhone 17（iOS 26.2）で通常・ASan・TSan のどれでもすべて通った（5.4）

| テスト | 確かめたこと |
|---|---|
| `testVersionAndLastSystemCode` | `ntk_version() == NTK_VERSION == 0x020000` |
| `testStructSize` | `sizeof == 24`、`offsetof` が 8 と 16。`struct_size` が 0・23 なら `INVALID_PARAMETER`。64 バイトの構造体（後ろを 0xAB で埋めたもの）は受け付け、知っている先頭だけを読む。`NULL` の text は空文字列 |
| `testInvalidUTF8IsRejected` | `C3 28`、`ED A0 80`（UTF-8 にしたサロゲート）、`C0 AF`（冗長な形）、`FF` を `INVALID_PARAMETER` で拒む（Swift の `String(validatingCString:)`） |
| `testCallbackIsQueuedOnMainAndReleasedOnce` | main からも別のスレッドからも、コールバックは関数が戻った後に main で 1 回、`release` はその後に main で 1 回 |
| `testRejectedCallReleasesOnCallingThreadBeforeReturning` | コールバックが `NULL` なら、`release` は呼び出し元のスレッドで、関数が戻る前に 1 回。`release == NULL` も受け付ける |
| `testConcurrentRequests` | 8 スレッド × 25 回。200 件すべてがコールバック 1 回・`release` 1 回・main。要求の ID は 200 個とも別 |
| `testLastSystemCodeIsPerThread` | 5.2 |
| `testUnpairedSurrogatesAndNulBecomeReplacementCharacters` | 5.3 |
| `testNullHandlesAreSafe` | `_free(NULL)` は何もしない、`NULL` のハンドルの読み出しは `NULL` / 0 |
| `testObjectiveCClassesOfTheImage` | 4.3 |

smoke（C。Xcode 26.3 で組み、iPhone 17 / 26.2 で動かした）の出力:

```
SMOKE ntk_version via @import = 0x020000
SMOKE ntk_version=0x020000 NTK_VERSION=0x020000 last_system_code=0
SMOKE echo=HÉLLO size=6 sizeof(request)=24
SMOKE release rejected main=0 before_return=1
SMOKE callback main id=1 error=0 system_code=0 text=smoke main=1
SMOKE release main main=1 before_return=0
SMOKE callback thread id=2 error=0 system_code=0 text=smoke main=1
SMOKE release thread main=1 before_return=0
SMOKE RESULT failures=0
```

### 2.2 書き方で分かったこと

`swiftc -typecheck` と `-emit-library`（Swift 6.3.3）で 1 つずつ確かめた。

| 事実 | 意味 |
|---|---|
| 関数を `internal` にすると、C のシンボルは「private external」（hidden）になり、dylib から出ない。ヘッダーに `__attribute__((visibility("default")))` を付けても同じ | 入口の関数は `public` にする。capi の Swift のモジュールを配らないので、`public` でも利用者には見えない（4.2） |
| Swift の関数名は C の名前と同じにする。`@c(ntk_version) @implementation func swiftyVersion()` は「一致する関数が無い」で誤り | 入口は snake_case の Swift の関数になる。受け口（`ProbeImpl` など）は普通の Swift の名前でよい |
| 型が 1 つでも違うと誤り（`Int32` と `UInt32`、`UnsafePointer` と `UnsafeMutablePointer`）。nullability も厳密: `_Nonnull` には非 Optional、注釈の無いポインタには Optional | ヘッダーと実装の食い違いをコンパイラーが止める（D-10 の狙いどおり）。公開ヘッダーに nullability を付けるかで Swift の側の書き方が変わる |
| ヘッダーに無い名前の `@c @implementation` は誤り。**逆に、ヘッダーにあって実装が無い関数は何も言われない**（リンクの時に利用者の側で初めて分かる） | 照合（`check_c_abi_contract_ios.py`）で、ヘッダーの関数の一覧と `nm -gU` の一覧が一致することを見る |
| framework 自身の clang module（underlying module）の宣言を実装できる。ビルドのときだけの別の module（`internal import`）にある宣言も実装できた | 内部の C の関数（`ntkc_*`）を Swift から呼ぶのにも、同じ module map の形が使える |
| 名前の無い `enum` の定数は `Int` として取り込まれる | `ntk_probe_error(NTK_PROBE_ERROR_NONE)` のように変換が要る |
| Swift 6.2.4 は `@c` を知らない（`unknown attribute 'c'`） | capi を組むのは Xcode 26.4 以降。利用者の側には capi の Swift は届かないので、利用者の Xcode には効かない（3 章） |
| 受け口の `@unchecked Sendable` の箱と `MainActor.assumeIsolated` で、Swift 6 の complete で警告 0 件 | 関数ポインタと `user_data` を main へ渡す形に、言語モードの壁は無い |

### 2.3 `@c @implementation` で書けないもの

| ヘッダーの形 | 結果 |
|---|---|
| 構造体・union・ビットフィールド・固定長の配列を値で渡す / 返す、関数ポインタを返す、`bool`、型付きの `enum`、配列の引数（`const int32_t v[]`）、`noreturn` | 書ける |
| 可変長引数（`...`） | 誤り（`cannot be marked '@c' because it has a variadic parameter`） |
| `va_list` の引数 | 誤り（`cannot be represented in C`） |
| 変数（`extern const`、`_Thread_local`） | 誤り（`@c` は関数だけ） |

Android・Windows の公開ヘッダーは、可変長引数・`va_list`・公開の変数を使っていない（関数だけ）ので、今の C ABI の形はすべて書ける。書けない形が要るようになったら、その関数だけ C のファイルにしてよい（同じ framework で C と `@c` を混ぜられることは `ThreadLocal.c` で確かめた）。

### 2.4 代替案: C の入口と関数ポインタの表

`@c` が使えないときの形を、Xcode 26.3（Swift 6.2.4）で組んで同じ smoke を流した。

- C の `Entry.c` が `ntk_*` を定義し、表の関数ポインタを呼ぶだけにする。表の型は内部のヘッダー（`Table.h`）
- Swift は `@_cdecl` も `@c` も無いと main の前にも C からも呼べないので、**最初の `ntk_*` の呼び出しで、`dispatch_once_f` の中から Objective-C の実行時でクラスを名前で引き（`objc_getClass("NTKCApiFallbackInstaller")`）、`install` を送る**。Swift の `@objc(NTKCApiFallbackInstaller)` のクラスが、ヒープに置いた表を `ntkc_register` で渡す。Objective-C のソースは無い
- 結果: 組めた（警告 0 件）。公開シンボルは同じ 14 個。smoke の出力は 2.1 と同じ（`failures=0`）。Objective-C のクラスが 1 つ増える（`NTKCApiFallbackInstaller`。4.3）

| 観点 | `@c @implementation` | 代替案 |
|---|---|---|
| 1 関数で書く所 | 1 か所（`Entry.swift`） | 3 か所（`Entry.c`、`Table.h` の欄、`Table.swift` の closure） |
| 入口の行数（14 関数） | 42 | 115（53 + 29 + 33） |
| ヘッダーと実装の照合 | Swift のコンパイラー（2.2） | C のコンパイラー（`Entry.c` がヘッダーを include する）と Swift のコンパイラー（表の型）。表の欄と C の入口の対応は人が保つ |
| 起動 | 何も要らない | 最初の呼び出しで実行時の名前引き。クラス名が見つからないと `NULL` の表を呼ぶ（雛形は検査していない） |
| Objective-C の実行時のクラス | Swift のクラスだけ（モジュール名で mangling） | 固有の名前のクラスが 1 つ（D-11 (2) の接頭辞が要る） |
| ビルドの Xcode | 26.4 以降（26.6） | 26.3 のまま |

推奨: **`@c @implementation`**（D-10 の第一の案）。条件がどちらも成り立ち（3 章）、代替案は 1 関数 3 か所と実行時の名前引きが増えるだけで、利点はビルドの Xcode を上げずに済むことだけ。D-16 はすでに 26.6 に決め直してある。

## 3. D-10 の条件 (1)・D-16: 26.6 で組み、26.3 で使う

| 確かめたこと | 結果 |
|---|---|
| 26.6 で組んだ `IosLibrary` の swiftinterface（`swift-compiler-version: 6.3.3`、`-swift-version 6`） | 26.3 の `swift-frontend -typecheck-module-from-interface` で、3 つのスライス（`arm64-apple-ios`、`arm64-apple-ios-simulator`、`x86_64-apple-ios-simulator`）× public と private の 6 つとも、エラーも警告も 0 件 |
| 中身の違い（26.3 で組んだ 0f の swiftinterface と比べて） | 6.3.3 は `#if compiler(>=5.3) && $Feature` の囲いを 1 つも出さない（0f は `$NonescapableTypes`、`$IsolatedDeinit`、`$SendingArgsAndResults` で囲っていた）。`sending` と `isolated deinit` を囲わずに書く。6.2.4 はどちらも知っているので読める。宣言の違いは、0f の後のコードの変更（`dec84652`）による `deinit` の 1 か所だけ |
| C / Objective-C の smoke を 26.3 で組んで動かす | 組めた（警告 0 件）。2.1 の出力 |
| Swift のアプリ（`import IosLibrary` と `import IosLibraryCApi`）を 26.3 で組んで動かす | 組めた（警告 0 件）。`IosClipboardManager.copy`（Swift の API）の後に、C の関数を Swift から呼べた: `SWIFTAPP C ABI callback id=1 error=0 text=swift-app main=true`、`SWIFTAPP release main=true` |
| capi の Swift のモジュールを入れた場合（比べるために組んだ） | `SWIFT_INSTALL_MODULE=YES` で library evolution なし（Xcode の既定）だと、26.3 の `import IosLibraryCApi` は **`module compiled with Swift 6.3.3 cannot be imported by the Swift 6.2.4 compiler` で止まる**。library evolution ありなら swiftinterface に戻って読めたが、中身は `import IosLibrary` と `@_exported import IosLibraryCApi` だけで、`@c` の関数は出ない |

意味: D-10 の条件 (1) は成り立つ（Swift の API の利用者に Xcode 26.4 以降を求めなくてよい）。D-16（ビルドは 26.6、利用者は 26.3 以上）を支える。ただし **capi の Swift のモジュールを配らないこと（`SWIFT_INSTALL_MODULE=NO`）が、下限を 26.3 にする条件**になる（D-9 の配布物の行のとおり）。確かめていないもの: Xcode 26.0〜26.2、実機での実行。

## 4. B: 配布の形

### 4.1 公開シンボル（D-11 (1)）

- `EXPORTED_SYMBOLS_FILE`（中身は `_ntk_*` の 1 行）で、`nm -gU` は 3 つのアーキテクチャ（`ios-arm64`、シミュレーターの `arm64` と `x86_64`）とも 14 個で、`_ntk_` 以外は 0 個
- 外すと 18 個: `_IosLibraryCApiVersionNumber`、`_IosLibraryCApiVersionString`（Xcode の版の記号）と、内部の C の関数 `_ntkc_tls_get` / `_ntkc_tls_set` が増える。Swift の内部の記号は、外しても出なかった（`internal` は hidden）
- 内部の C の関数の名前は `ntk_` で始めない（`_ntk_*` の wildcard に入る）。雛形は `ntkc_` にした
- 代替案も同じ 14 個

### 4.2 `Headers/` と `Modules/`（D-9、D-10 の隠し方 (a)）

xcframework の中の `IosLibraryCApi.framework` は、スライスごとに次だけ:

```
Headers/NativeToolkitC/Common.h
Headers/NativeToolkitC/Probe.h
Info.plist
IosLibraryCApi
Modules/module.modulemap
```

- `SWIFT_INSTALL_MODULE=NO` で `Modules/IosLibraryCApi.swiftmodule` が、`SWIFT_INSTALL_OBJC_HEADER=NO` で `IosLibraryCApi-Swift.h` が無くなる。後で消す手順は要らない（両方の Xcode の xcspec にある設定）
- module map は `framework module IosLibraryCApi { header "NativeToolkitC/Common.h" header "NativeToolkitC/Probe.h" export * }`。`@c @implementation` はこれを underlying module として使う
- 使えた形: Objective-C の `@import IosLibraryCApi;`、C の `#include <IosLibraryCApi/NativeToolkitC/Probe.h>`、Swift の `import IosLibraryCApi`。Windows・Android と同じ `#include <NativeToolkitC/Common.h>`（`Headers` をヘッダーの検索パスに足す形）は確かめていない
- **モジュールの検証（`ENABLE_MODULE_VERIFIER`）が、framework のヘッダーの `#include "Common.h"`（Android・Windows の機能のヘッダーと同じ書き方）を誤りにする**（`double-quoted include "Common.h" in framework header, expected angle-bracketed instead`）。`OTHER_MODULE_VERIFIER_FLAGS` に `-Wno-quoted-include-in-framework-header` や `-Wno-error=...` を渡しても止まらない（ほかの警告は「discarded」になるが、これは誤りのまま）。次の形なら、C・C++・Objective-C・Objective-C++ × c99・gnu11・c++11・gnu++17 で通った:

```c
#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif
```

  `else` の側は、`dist/include` に置く写し（ClangSharp などがヘッダーだけで読むとき）のため。機能のヘッダーは OS ごとに持つ（3.3）ので、iOS だけこの形にしてよい。`Common.h` は `<stddef.h>` と `<stdint.h>` しか include しないので影響が無い
- 利用者のアプリに Embed & Sign すると、`Headers/` と `Modules/` は外される（`RemoveHeadersOnCopy`）。`.app/Frameworks` に残るのは `Info.plist`、本体、`_CodeSignature` だけ

### 4.3 Objective-C の実行時のクラス（D-11 (2)）

`objc_copyClassNamesForImage` と `nm` で数えた。

| 形 | `IosLibraryCApi` が登録するクラス |
|---|---|
| `@c @implementation` | `IosLibraryCApi.NTKBuffer`、`IosLibraryCApi.NTKStringList`（Swift のクラス。実行時の名前は `_TtC14IosLibraryCApi9NTKBuffer` などで、モジュール名が入る） |
| 代替案 | 上の 2 つと `NTKCApiFallbackInstaller`（`@objc(...)` で名前を固定したもの） |

`@c` の形では `@objc` のクラスが無く、名前はモジュール名で区切られる。ほかの framework とぶつかるのは、同じモジュール名を持つときだけ。代替案では固有の接頭辞（`NTKCApi`）が要る。

### 4.4 依存と Info.plist

- `otool -L`: `@rpath/IosLibrary.framework/IosLibrary`、OS の framework、`/usr/lib/swift/*` だけ。Swift の互換ライブラリ（`libswiftCompatibility*`）や `@rpath` の Swift のライブラリには依存しない（最小 iOS 18 の OS の Swift の実行環境で足りる）
- `DTXcode` 2660、`DTXcodeBuild` 17F113、`DTSDKName` iphoneos26.5、`MinimumOSVersion` 18.0
- スライスは `ios-arm64` と `ios-arm64_x86_64-simulator`（D-11 のとおり）。`IosLibrary` の公開シンボルは 1195 個（Swift の API なので、絞らない）

### 4.5 署名の無い xcframework（D-18）

- archive に `CODE_SIGNING_ALLOWED=NO` を渡すと、`ios-arm64` は `code object is not signed at all`、シミュレーターのスライスはリンカーの ad-hoc の署名だけになる（7.3 で照らす形のとおり）
- Xcode 26.3 で利用者のアプリに組み込んでも、xcframework の署名に関する警告もエラーも出なかった

### 4.6 Embed & Sign と archive（D-18）

- シミュレーター向けのビルド（Smoke.app）で、2 つの framework は Xcode が署名し直した（ログに `replacing existing signature`）。`codesign --verify --deep --strict` は 2 つの framework とアプリのどれも `valid on disk` / `satisfies its Designated Requirement`。署名は `adhoc`（Sign to Run Locally）で、TeamIdentifier は無い
- 実機向けの archive は、`CODE_SIGN_IDENTITY=-`、`CODE_SIGN_STYLE=Manual`、`CODE_SIGNING_REQUIRED=NO`、`AD_HOC_CODE_SIGNING_ALLOWED=YES` でも **`"Smoke" requires a provisioning profile` で止まった**。アプリの証明書で署名し直されることと Team ID の確かめには、利用者の Team の provisioning profile が要る。指示どおりここで止めた（実機での実行はしない）

## 5. D: 小さな振る舞い

### 5.1 main に積んだブロックの中の UIKit の例外（D-10）

`ntk_probe_raise_uikit_exception_async` を smoke から呼んだ。すべて意図して落とした実行で、Mac に crash report（`Smoke-2026-10-31-*.ips` が 5 つ）ができた。中身を下に写してから消した。

| 種類 | 端末 | 結果 |
|---|---|---|
| 1: アクションシートに `addTextField` | iPhone 17 / 26.2（2 回）、iPad (A16) / 26.2、iPad Pro 11-inch (M4) / 18.3 | 関数は 0（受け付けた）を返す。main のブロックの中で `NSInternalInconsistencyException`。`NSSetUncaughtExceptionHandler` は呼ばれ、`SIGABRT` で終わる。コールバックも `release` も呼ばれない。呼び出し側の `@try` は届かない（ブロックは後で動く） |
| 2: 基点の無いアクションシートを `present` | iPad (A16) / 26.2 | **例外にならない**。コールバックと `release` が返り、3 秒後も動いていた |
| 2 | iPad Pro 11-inch (M4) / 18.3 | `NSGenericException`（`You must provide either a sourceView and sourceRect or a barButtonItem`）。**こちらのブロックが終わり、コールバックと `release` を返した後に**、UIKit の表示の処理（`-[UIPopoverPresentationController presentationTransitionWillBegin]`）で投げられる。例外のスタックに `IosLibraryCApi` のフレームは無い |

crash report の事実:

- iOS 26.2 の 3 件: 落ちたスレッドのスタックは `__cxa_throw` → `failed_throw` → `std::__terminate` → `_objc_terminate` → `abort` で、その下に `-[UIAlertController addTextFieldWithConfigurationHandler:]` と `IosLibraryCApi` のフレームが残る。受け手が無いと分かった時点で、巻き戻さずに終わる
- iOS 18.3 の種類 1: `std::terminate` を呼ぶのは libdispatch の `_dispatch_client_callout`（main キューの drain の中）。ここまで巻き戻ってから終わる
- iOS 18.3 の種類 2: `__cxa_rethrow` から `_objc_terminate`。例外のスタックは UIKit の popover の表示だけ
- どれも `EXC_CRASH (SIGABRT)`、`Abort trap: 6`

意味: D-10 の「例外は起こさない検査をし、起きたら落ちる」を支える。入口で捕まえる方法は無く、`release` も呼ばれないので、利用者の `user_data` の片付けもされない（プロセスが終わるので問題にならない）。popover の基点の誤りは iOS 26 では起きず、iOS 18 では完了を返した後に落ちるので、**基点の検査は入口で前もって行い、テストは iOS 18 の iPad でも流す**必要がある。

### 5.2 `_Thread_local` と `ntk_last_system_code`（D-13）

- 雛形は C の `_Thread_local` に値を持ち、`ntk_probe_echo` が不正な UTF-8 のときだけ調べるための値（0xE0F）を入れる。8 本のスレッドで、失敗したスレッドだけが 0xE0F、成功したスレッドは 0、main は前のテストが入れた値のまま（`testLastSystemCodeIsPerThread`、ASan・TSan でも通った）
- Swift は `_Thread_local` の変数を取り込むが、Swift 6 では読むだけで `reference to var ... is not concurrency-safe` の誤りになる。`@c` は変数を定義できない（2.3）。持つなら C のファイルに置き、関数で読む形になる
- D-13 は「常に 0」と決めてある。**それなら `_Thread_local` は要らない**: `@c @implementation public func ntk_last_system_code() -> UInt32 { 0 }` の 1 行にし、`ThreadLocal.c` と内部の module map を無くせる。0 以外を入れることにしたときだけ、雛形の形（C の `_Thread_local` と、Swift から呼ぶ関数）を使う

### 5.3 `NSString` の対になっていないサロゲートと U+0000（8.6 の UTF-8）

UTF-16 で `0041 D800 0042 0000 0043 DC00 0044` の `NSString` を作って測った。

| 方法 | 結果 |
|---|---|
| `-[NSString UTF8String]` | **`NULL`** |
| `lengthOfBytesUsingEncoding:` UTF-8 | 0 |
| `dataUsingEncoding:` UTF-8 | `nil` |
| Swift の `String(ns).utf8` | `41 EF BF BD 42 00 43 EF BF BD 44`（サロゲートは U+FFFD に直るが、U+0000 は残る） |
| 雛形の出力（`CApiString.outputUTF8`: Swift の `String` にしてから U+0000 を U+FFFD に） | `41 EF BF BD 42 EF BF BD 43 EF BF BD 44` |

クリップボードに置いて読む（8.2 の確かめ方）:

| 置き方 | `UIPasteboard.string` | `pasteboard.items` の値 | C ABI の出力（`IosLibrary` の `read` 経由） |
|---|---|---|---|
| `UIPasteboard.string = ns` | 保存に失敗（`Cannot represent object of class __NSCFString as representation of type public.utf8-plain-text`）。何も置かれない | - | - |
| `public.utf16-external-plain-text`（BOM 付き） | `nil` | `__NSCFString`、UTF-16 は置いたとおり | `41 EF BF BD 42 EF BF BD 43 EF BF BD 44` |
| `public.utf16-plain-text`（BOM 無し） | 文字ごとに上下が入れ替わった UTF-16（`4100 00D8 ...`） | `OS_dispatch_data` | 空文字列（`IosLibrary` は `items` の値を `String` として取るので、文字列にならない） |
| `public.utf8-plain-text`（不正な UTF-8） | `nil` | `OS_dispatch_data` | 空文字列 |

意味: 出力の変換で `UTF8String` などの Foundation の UTF-8 の変換を使うと、`NULL` や空になる。Swift の `String` の UTF-8 への変換と、U+0000 の置き換えの 2 段にする（AC-19 / E-16 の U+FFFD の規則を守れる）。ほかのアプリが置いたクリップボードからは、BOM 付きの UTF-16 のときに対になっていないサロゲートを持つ文字列が届きうる。BOM 無しの UTF-16 や UTF-8 のデータは `IosLibrary` が文字列として扱わない（今の振る舞い。C ABI の第 2 部で、文字列として読むかを決める）。

### 5.4 ASan と TSan（7.4）

- `xcodebuild test -enableAddressSanitizer YES` / `-enableThreadSanitizer YES` で、10 件がシミュレーター（iPhone 17 / 26.2）で通った。capi の framework にも `libclang_rt.asan_iossim_dynamic.dylib` / `libclang_rt.tsan_iossim_dynamic.dylib` がリンクされており、テストだけでなく framework も計測されている（同じプロジェクトでソースから組むため）
- TSan が本当に報告するかを、一時的なテスト（`user_data` の箱を、main のコールバックと別のスレッドから書く）で確かめた: `WARNING: ThreadSanitizer: Swift access race` が出てテストは失敗した。Xcode の TSan は報告の後にテストのホストを止め（`SIGABRT`、XCTest は「Restarting after unexpected exit」）、Mac に crash report（`CApiTestHost-2026-10-31-*.ips`）が 1 つできたので消した。一時的なテストは元に戻した
- 実機の TSan は確かめていない（実機は使わない）

## 6. 決定への意味

| 決定 | この記録から言えること |
|---|---|
| D-9 | 2 つの dynamic の xcframework で、capi は `Headers/NativeToolkitC/*.h` と module map だけを持ち、Swift のモジュールと `-Swift.h` を持たない形にできる（4.2）。C / Objective-C / Swift の利用者が使えた（2.1、3 章） |
| D-10 | 第一の案 `@c @implementation` の 2 つの条件（26.3 で読める、コールバック・`user_data`・`struct_size`・ハンドルを書ける）はどちらも成り立つ。書けないのは可変長引数・`va_list`・変数だけ（2.3）。隠し方は (a)（Swift のモジュールを配らない）で足り、`@objc` の受け口は要らない。UIKit の例外は入口で止められない（5.1） |
| D-11 | (1) `_ntk_*` だけを出せる（4.1）。(2) `@c` の形では `@objc` のクラスが無い（4.3）。(3) Swift の metadata（`NTKBuffer` などのクラス）は残る |
| D-13 | 常に 0 なら `_Thread_local` は要らない（5.2） |
| D-16 | 26.6 で組み、26.3 の利用者が swiftinterface を読めて、smoke と Swift のアプリも組めて動いた。条件は capi の Swift のモジュールを配らないこと（3 章） |
| D-18 | 署名の無い xcframework を利用者のアプリで Embed & Sign でき、シミュレーターでは署名し直されて `--verify --deep --strict` が通る。実機の archive の Team ID の確かめは残る（4.6） |

## 7. 利用者に決めてもらうこと

| 項目 | 推奨と理由 |
|---|---|
| D-10 の入口の書き方 | **`@c @implementation` を採る**。条件が成り立ち、1 関数 1 か所で書け、代替案より起動の仕掛けが要らない（2.4） |
| framework のヘッダーの include | **機能のヘッダーで `__has_include` の形を使い、モジュールの検証は有効のままにする**。検証を切ると module map の誤りを組むときに見つけられなくなる（4.2） |
| D-13 と `_Thread_local` | **常に 0 のまま、`_Thread_local` の C のファイルを持たない**。持つ理由が無く、Swift 6 では読み書きに C の関数が要る（5.2） |
| 実機の archive の署名の確かめ（D-18） | **`unity-native-plugin` の agent の Release の archive（1a の Unity の行）で行う**。どのみち利用者の Team で署名するので、こちらで同じ証明書の archive を別に作る意味が薄い。こちらで行うなら、利用者の Team で `Smoke` を archive してよいか（実機には入れない）の許可が要る |

## 8. 残っていること

- 実機の Release の archive で、2 つの framework がアプリの証明書で署名し直されていることと Team ID（4.6）。Organizer の Validate App
- 実機での TSan（5.4）
- Xcode 26.0〜26.2 で swiftinterface を読めるか（下限は 26.3 にしたので、確かめない見込み）
- `#include <NativeToolkitC/Common.h>`（Windows・Android と同じ書き方）で使えるか（4.2）
- 照合（2a）に、ヘッダーの関数の一覧と `nm -gU` の一致（2.2）、内部の C の名前が `ntk_` で始まらないこと（4.1）、Swift のモジュールと `-Swift.h` が無いこと（4.2）を入れる
- 本物の Unity での `__Internal` の呼び出し（`unity-native-plugin` の agent）

## 9. 片付け

- 大きなビルドの結果（DerivedData、archive、xcframework、生成したプロジェクト）は scratchpad に置き、終わりに消した。リポジトリには 128 KB のソースとスクリプトだけ
- 意図して落とした実行は 6 回（5.1 の Smoke が 5 回、5.4 の TSan の確かめが 1 回）。できた crash report（`Smoke-2026-10-31-*.ips` 5 つ、`CApiTestHost-2026-10-31-*.ips` 1 つ）は、事実を写してから消した。ほかのアプリの report には触れていない
- 使ったシミュレーター（iPhone 17 / 26.2、iPad (A16) / 26.2、iPad Pro 11-inch (M4) / 18.3）は止めた。別のエージェントの iPhone 16 / 18.3 は使っていない
