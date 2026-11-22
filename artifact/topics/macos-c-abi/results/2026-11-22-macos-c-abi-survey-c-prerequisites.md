# 観点 C: macOS で C ABI を作る前提（公式の文書と手元の試し）

> この記録は、企画（`../plans/2026-11-22-macos-c-abi-plan.md`）のための調査の全文を、scratchpad から写したもの（2026-11-22）。写すときに、利用者の氏名・証明書の ID・Team ID を `<氏名>`・`<証明書の ID>`・`<Team ID>` に、scratchpad の道を `<scratchpad>` に置き換えた。試作と生成物は scratchpad に残し、リポジトリには入れていない。日付の記録として本文は直さない

調べた日: 2026-11-22。リポジトリのファイルは変えていない。試したものは `scratchpad/survey/probe-c/` に置いた。

印の意味:

- **[公式]**: 公式の文書で確かめたこと（出典の URL を付ける）
- **[手元]**: このマシンで試したこと（コマンドと出力の要点を書く）
- **[推測]**: 公式にも手元にも裏付けが無いこと。設計の前に確かめる

## 0. 環境と試作

| 項目 | 値 |
|---|---|
| macOS | 26.3（25D125）、arm64。Rosetta あり |
| Xcode | 26.3（17C529、Swift 6.2.4、MacOSX26.2 SDK。`xcode-select` の既定）と 26.6（17F113、Swift 6.3.3、MacOSX26.5 SDK） |
| Unity | 6000.0.44f1、6000.4.2f1（どちらも Mac Standalone の Mono。6000.0.44f1 には IL2CPP もある） |
| 署名の ID | Apple Development が 1 つだけ（Developer ID は無い）。試しには使わず、ad-hoc（`-`）だけで署名した |

試作の構成（`probe-c/`。iOS の段階 1a の雛形 `results/probes/stage1a/entry` を macOS 向けに縮めたもの）:

- `core/Core.swift`: `MacLibrary` の代わり（`MacProbeCore.framework`。AppKit・UserNotifications を使う。`BUILD_LIBRARY_FOR_DISTRIBUTION=YES`）
- `capi/`: C ABI（`MacProbeCApi.framework`）。`include/NativeToolkitC/{Common,Probe}.h`、`module.modulemap`、`MacProbeCApi.exp`（`_ntk_*`）、`Sources/Entry.swift`（`@c @implementation`）。わざと書き出さないもの（`ntk_` で始まらない public の `@c` 関数 `probe_internal_helper` と public の Swift 関数）も入れた
- `smoke/main.c`: C の利用者（版、名前付きの貼り付け板の往復、`accessBehavior`、`dlsym` で隠れているかの確認、通知の設定を非同期で読み main で受ける）
- `gen.rb`: xcodeproj gem で使い捨ての Xcode プロジェクトを作る（`lib` と `consumer`）
- `checks/`: Swift 6 の隔離、Xcode 26.3 の `@c`、bundle の無いプロセスの通知、Unity と同じ `PlugIns` からの `dlopen`
- `docs/`: Apple の文書の JSON（`https://developer.apple.com/tutorials/data/documentation/<path>.json`）を本文にしたもの。Apple の文書のページは JS で描かれ、WebFetch では本文が取れないため。`tools/get.sh` と `tools/adoc.py` で取った

---

## 1. `@c`（SE-0495）と `@c @implementation` は macOS でも使えるか

**結論: 使える。iOS と同じ書き方で、macOS の universal（arm64・x86_64）の dynamic framework を組め、`_ntk_*` だけを書き出せた。ただし macOS の framework は版付きの構成なので、ヘッダーを `Headers/NativeToolkitC/` に置くには手当てが要る。**

### [公式]

- SE-0495 は「Implemented (Swift 6.3)」。プラットフォームの制限は書かれていない。`@implementation` は「imported C or Objective-C header」で宣言された関数に Swift の本体を与え、名前と型が一致しないとコンパイラが止める。型は C で表せるものだけ（Swift の struct、`@c` でない enum、ポインタでない Optional は不可）。public / internal の可視性には触れていない
  - https://github.com/swiftlang/swift-evolution/blob/main/proposals/0495-cdecl.md
- Swift 6.3 のリリース（2026-03-24）。`@c` と `@c @implementation` の説明があり、プラットフォームの制限は書かれていない
  - https://swift.org/blog/swift-6.3-released/
- `EXPORTED_SYMBOLS_FILE` などのビルドの設定: https://developer.apple.com/documentation/xcode/build-settings-reference （iOS の 8.5 と同じ出典）
- XCFramework の作り方（macOS も同じ `-create-xcframework`）: https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle

### [手元]

1. **Xcode 26.6 で macOS 向けに archive**（`generic/platform=macOS`、Release、`CODE_SIGNING_ALLOWED=NO`、`MACOSX_DEPLOYMENT_TARGET=15.0`、Swift 6）。`MacProbeCore` と `MacProbeCApi` の両方が通った（`logs/archive-*.log`）
2. **最初は失敗した**: `PUBLIC_HEADERS_FOLDER_PATH=$(CONTENTS_FOLDER_PATH)/Headers/NativeToolkitC`（iOS と同じ設定）にすると、macOS では `CONTENTS_FOLDER_PATH = MacProbeCApi.framework/Versions/A` になり、ヘッダーは `Versions/A/Headers/NativeToolkitC/` に入るのに、**最上位の `Headers` のリンクが作られない**（`Modules` と `Resources` のリンクはある）。そのため自分の module map（`header "NativeToolkitC/Common.h"`）が解けず、Swift の依存の走査が止まった:
   ```
   module.modulemap:2:12: error: header 'NativeToolkitC/Common.h' not found
   error: Unable to resolve module dependency: 'MacProbeCApi'
   ```
   最初のビルドの段に `ln -sfh Versions/Current/Headers Headers` を足すと通った（`gen.rb` の `Link top-level Headers`）。iOS は浅い構成なので起きない。**macOS では設計で扱いを決める**（例: スクリプトの段でリンクを作る、`Headers/` 直下に置いて module map とインクルードの形を変える。どちらにするかは要検討）
3. **xcframework**: `xcodebuild -create-xcframework -framework <archive の framework>` で、スライスは `macos-arm64_x86_64` が 1 つ。`Info.plist` は `SupportedPlatform = macos`、`SupportedArchitectures = [arm64, x86_64]`、`BinaryPath = MacProbeCApi.framework/Versions/A/MacProbeCApi`
4. **書き出し**（`nm -gU -arch arm64|x86_64`）: どちらのアーキテクチャも次の 4 つだけ。`probe_internal_helper`（public の `@c` だが `ntk_` で始まらない）と Swift の public の関数は出ない
   ```
   _ntk_probe_general_access_behavior
   _ntk_probe_notification_status_async
   _ntk_probe_pasteboard_roundtrip
   _ntk_version
   ```
   `MacProbeCore`（Swift の API の側）は 10 個を書き出す（Swift の記号。iOS の `IosLibrary` と同じ扱い）
5. **依存**（`otool -L`）: `@rpath/MacProbeCApi.framework/Versions/A/MacProbeCApi`（install name に `Versions/A` が入る）、`@rpath/MacProbeCore.framework/Versions/A/MacProbeCore`、Cocoa、`/usr/lib/swift/*`（OS の Swift ランタイム。最小 macOS 15 なので同梱しない）。`LC_RPATH` は `/usr/lib/swift`、`@executable_path/../Frameworks`、`@loader_path/../Frameworks`
6. **C の `main` からリンクして呼ぶ**（Xcode 26.3 の clang、`-arch arm64 -arch x86_64`、`-F <スライス> -framework MacProbeCApi`）。arm64 と、Rosetta での x86_64 の両方で同じ結果:
   ```
   SMOKE version=0x00020000
   SMOKE roundtrip rc=0 text=héllo ✓
   SMOKE general accessBehavior=2
   SMOKE dlsym(probe_internal_helper)=0x0
   SMOKE notification async rc=3     ← bundle の無いプロセス。下の 4 章
   ```
   26.6 で組んだ framework を 26.3 で組んだ利用者が使える（C だけなので Swift の版は関係しない）
7. **Xcode 26.3（Swift 6.2.4）では `@c` が使えない**（`checks/c26.swift`）:
   ```
   error: '@implementation' used without specifying the language being implemented
   error: unknown attribute 'c'
   ```
   26.6（Swift 6.3.3）では通る。iOS と同じく、**C ABI を組む側は Xcode 26.6 以上**が要る（利用者の下限とは別）
8. **Swift 6 での AppKit の隔離**（`checks/isolation.swift`、nonisolated の関数の中で作る）: `NSAlert()` は「main actor-isolated initializer」の**警告**（エラーではない）。`NSSharingServicePicker(items:)` と `NSPasteboard.general` は何も出ない（Swift の型では main actor に縛られていない）。6 章も参照

---

## 2. アプリへの埋め込みと署名

**結論: 置き場は `Contents/Frameworks`、rpath は `@executable_path/../Frameworks`。Xcode の Embed & Sign は framework をアプリの ID で署名し直す。重要なのは、Hardened Runtime を有効にしたアプリを ad-hoc（Sign to Run Locally）で署名すると、同じ ad-hoc で署名し直した framework でも Library Validation で読み込めないこと。署名しない（linker-signed のままの）framework を配ると、利用者は必ず署名し直す必要がある。**

### [公式]

- 置き場: macOS のアプリでは framework と dylib は `Contents/Frameworks/`、plug-in は `Contents/PlugIns/`、プライバシーマニフェストは `Contents/Resources/`。macOS の framework の中では `Versions/A/Resources/`
  - https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle
- rpath: `@rpath` を使った参照にするのがよい（`install_name_tool -id "@rpath/…"`、実行ファイルに相対の rpath）
  - https://developer.apple.com/documentation/xcode/embedding-nonstandard-code-structures-in-a-bundle
- 署名: 内側から署名する。`--deep` は使わない（同じオプションと entitlement をすべてに付け、データの場所にあるコードは署名しない）。framework をコピーするときは `cp` でなく `ditto`（版付きの構成のリンクを保つ）。Developer ID のときは `--timestamp`、main executable には `-o runtime`
  - https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac
- Hardened Runtime: 公証には必須。entitlement は実行ファイルにだけ付け、「Shared libraries, frameworks, and in-process plug-ins inherit the entitlements of their host executable」
  - https://developer.apple.com/documentation/security/hardened-runtime
- Library Validation: Hardened Runtime で既定で有効。「prevents a program from loading frameworks, plug-ins, or libraries unless they're either signed by Apple or signed with the same Team ID as the main executable」。外すと Gatekeeper が追加の検査をする
  - https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation
- 公証（notarization）の要件: 配るすべての実行コードに有効な署名、Developer ID の証明書（ad-hoc・Apple Development は不可）、Hardened Runtime、secure timestamp、`get-task-allow` を付けない、macOS 10.9 以降の SDK。Mac App Store で配るものは公証が要らない。plug-in はホストの entitlement を継ぐので、ホストが必要な entitlement を持つ
  - https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
  - https://developer.apple.com/documentation/security/resolving-common-notarization-issues
- XCFramework の署名の検証（Xcode 15 以降。macOS も同じ）: https://developer.apple.com/documentation/xcode/verifying-the-origin-of-your-xcframeworks

### [手元]

1. **署名しない設定（`CODE_SIGNING_ALLOWED=NO`）で組んだ framework**も、arm64 のリンカーが ad-hoc で署名する:
   `flags=0x20002(adhoc,linker-signed)`、`Info.plist=not bound`、`Sealed Resources=none`、`TeamIdentifier=not set`
2. **Xcode で埋め込む**（`consumer`。C のアプリ、xcframework 2 つを Embed（`CodeSignOnCopy`、`RemoveHeadersOnCopy`）、`CODE_SIGN_IDENTITY=-`、`ENABLE_HARDENED_RUNTIME=YES`、`LD_RUNPATH_SEARCH_PATHS=@executable_path/../Frameworks`）:
   - `SmokeApp.app/Contents/Frameworks/{MacProbeCApi,MacProbeCore}.framework` に入り、ヘッダーは外された
   - framework は署名し直された: `Identifier=com.example.ntkprobe.MacProbeCApi`、`flags=0x10002(adhoc,runtime)`、`Sealed Resources version=2`。`codesign --verify --deep --strict` は valid
3. **Hardened Runtime ＋ ad-hoc では起動できない**（arm64 も x86_64 も、`open` でも同じ）:
   ```
   dyld: Library not loaded: @rpath/MacProbeCore.framework/Versions/A/MacProbeCore
     Reason: ... code signature ... not valid for use in process:
     mapping process and mapped file (non-platform) have different Team IDs
   ```
   ad-hoc には Team ID が無く、Library Validation は同じアプリの中で ad-hoc で署名し直した framework も拒む
4. 比べた形（`work/variants/`）:

   | 形 | 結果 |
   |---|---|
   | Hardened Runtime なし（ad-hoc） | 起動でき、すべて成功（通知の設定 `status=0`、`on_main=1`） |
   | Hardened Runtime ＋ `com.apple.security.cs.disable-library-validation`（ad-hoc） | 起動でき、すべて成功 |
   | Hardened Runtime ＋ ad-hoc（Xcode の既定の組み合わせ） | 上の 3 のとおり拒まれる |
   | linker-signed の framework をそのまま入れ、外側のアプリだけ署名 | `codesign` が「code object is not signed at all / In subcomponent: …MacProbeCApi.framework」で止まる。framework を署名し直さないとアプリを署名できない |

   本物の Team の証明書（Apple Development / Developer ID）で同じ Team で署名した場合は試していない（個人の証明書を使わないため）。公式の文書では同じ Team ID なら通る
5. 1.x の Unity の Xcode の書き出し（`unity-native-plugin/Build/Mac/Mac.xcodeproj`。読むだけ）は `ENABLE_APP_SANDBOX = YES`、`ARCHS = arm64`。Unity のプレイヤーのひな形（`UnityPlayer.app`）は `flags=0x2(adhoc)`（Hardened Runtime なし）

### 設計への含み

- iOS の D-18（配る framework は署名しない）は macOS でもそのまま使えそう。利用者が Embed & Sign で自分の ID で署名し直すため。ただし **署名し直さない取り込み方（Unity の `.bundle` を `PlugIns` に置く、Godot、Rust の手での組み込み）では、利用者が framework を内側から署名する手順が要る**。マニュアルに書く
- **開発中に ad-hoc ＋ Hardened Runtime で試す利用者は必ずつまずく**。マニュアルに「Sign to Run Locally では Hardened Runtime を外すか Disable Library Validation を付ける。配るときは同じ Team で署名する」を書く。サンプルとスモークのアプリの設定もここで決める
- 公証は利用者のアプリの責任。ライブラリは公証の要件（Hardened Runtime と両立、`get-task-allow` を持たない、10.9 以降の SDK）に引っかからない形で配れば足りる [推測: 署名しない framework を利用者が Developer ID で署名し直せば公証は通るはず。Developer ID が無いので試していない]

---

## 3. Unity の macOS のプレイヤー

**結論: Unity の公式の手順は `.bundle`（または dylib）を `DllImport("名前")` で呼ぶ形で、`.framework` を Standalone で使う手順は書かれていない。1.x は「Create Xcode Project」で書き出した Xcode プロジェクトに framework をリンクし `DllImport("__Internal")` で呼んでいる。プレイヤーは通知の delegate を持たない。**

### [公式]

- macOS の plug-in は `.bundle` で配る。IL2CPP なら C++ のソースを `DllImport("__Internal")` で呼べる。Xcode の「Framework & Library > Bundle」で作る。universal にするか、dylib を分けて配る。C# からは `[DllImport("PluginName")]`（接頭辞と拡張子を付けない）
  - https://docs.unity.com/en-us/engine/6000.0/manual/programming-environment/plug-ins/for-desktop （旧 https://docs.unity3d.com/6000.0/Documentation/Manual/plug-ins-for-desktop.html から転送）
- `DllImport` の名前の解き方（POSIX。macOS を含む）: `.so`、`.dll`、`.dylib`、`.bundle` を付け、`lib` の有無の両方を試す。`.bundle` を名前に書くのは macOS と Apple のモバイルだけ。静的なリンク（`__Internal`）は「Android and Apple mobile platforms」だけ。**`.framework` には触れていない**
  - https://docs.unity.com/en-us/engine/6000.5/manual/scripting/compilation-and-code-reload/plug-ins/native/dllimport
- plug-in の取り込み: `.bundle` と `.framework` のフォルダーを 1 つの plug-in として扱う。`.framework` の記述は iOS / tvOS の「Add to Embedded Binaries」だけ
  - https://docs.unity3d.com/6000.2/Documentation/Manual/plug-in-inspector.html
- macOS のビルド: アーキテクチャは Intel 64-bit / Apple silicon / 両方。「Create Xcode Project」がある。「If your application uses plug-ins that perform macOS platform-specific actions, you might need to add entitlements」。Mac App Store のアプリは事前の公証が要らない
  - https://docs.unity.com/en-us/engine/6000.0/manual/platform-specific/apple-mac/macos-delivery/macos-building
- 署名: Hardened Runtime の最低限の entitlement として `com.apple.security.cs.disable-library-validation` と `disable-executable-page-protection` を挙げ、`codesign --deep --force ... --options runtime` の例を示しつつ `--deep` の問題も書いている（6000.6 の版）
  - https://docs.unity.com/en-us/engine/current/manual/platform-specific/apple-mac/macos-delivery/macos-building-notarization/macoscodesigning

### [手元]

- `MacStandaloneSupport/Variations/*/UnityPlayer.app/Contents/Frameworks/UnityPlayer.dylib`（6000.4.2f1、universal）の文字列に `Contents/PlugIns`、`.bundle`、`.dylib`、`lib%s.dylib`、`%s.dylib` がある（文書の名前の解き方と合う）。`.framework` は system の framework の絶対パスだけ
- **UnityPlayer.dylib は UserNotifications をリンクしておらず、`UNUserNotification` の文字列も無い**（`otool -L`、`strings`）。`PlayerAppDelegate` と `applicationWillFinishLaunching:` はある。つまり**プレイヤーは通知の delegate を入れない**ので、ライブラリが入れても奪い合わない
- プレイヤーの入口（`Source/Player/MacPlayer/MacPlayerEntryPoint/Main.cpp`）は `PlayerMain(argc, argv)` を呼ぶだけ。`Info.plist` は `NSPrincipalClass = PlayerApplication`、`NSMainNibFile = MainMenu`、`LSMinimumSystemVersion = 12.0`。app delegate のソースは配られていない（dylib の中）
- 6000.4.2f1 の Mac Standalone には Mono の Variations だけがある（IL2CPP のモジュールは入っていない）。6000.0.44f1 には IL2CPP もある
- 1.x の取り込み（`unity-native-plugin`。読むだけ）: `MacNotificationManager.cs` は `DllImport("__Internal")`。`Editor/Build/PostBuildProcessor.cs` が「Create Xcode Project」の書き出しの `Mac.xcodeproj` に `unity-mac-native-toolkit-*.xcframework` を link と Embed で足す。scripting backend は Standalone の指定が無く Mono（既定）。Mono の `__Internal` は実行中のプロセスの記号を探すので、リンクした framework の記号が見える [推測: Mono の挙動。公式の文書は `__Internal` を Apple のモバイルと Android に限っている]
- **`PlugIns` に 2 つの framework を置いて `dlopen` する試し**（`checks/host.c`、Unity が `.bundle` を `Contents/PlugIns` から読むのを真似た）:
  - そのままでは `Library not loaded: @rpath/MacProbeCore.framework/...`。C ABI の framework の rpath（`@executable_path/../Frameworks`、`@loader_path/../Frameworks`）では、`PlugIns` にある兄弟の framework を見つけられない（`@loader_path` は `…/MacProbeCApi.framework/Versions/A`）
  - `install_name_tool -add_rpath @loader_path/../../..` を足して ad-hoc で署名し直すと、arm64 も x86_64 も `ntk_version=0x00020000` で読めた
  - → **C ABI の framework に `@loader_path/../../..`（自分の兄弟）を rpath に足しておくと、`Frameworks` 以外に置かれても依存を解ける**

### [推測]（確かめていない）

- Unity 6 で `.framework` を `DllImport("MacProbeCApi")` で読めるか。文書の名前の候補に `.framework` は無いので、そのままでは読めない見込み。選択肢は (a) 1.x と同じ Xcode の書き出し＋`__Internal`、(b) C ABI を `.bundle`（または dylib）でも配る、(c) C# から絶対パスで `NativeLibrary`/`dlopen` する。`.bundle` は Swift の依存（`MacLibrary.framework`）をどこに置くか、rpath をどうするかを決める必要がある
- **macOS のプレイヤーで C# が main スレッドで動くか**: プレイヤーは NSApplication の main スレッドで動いている（`Main.cpp`→`PlayerMain`、`NSPrincipalClass`）ので、C# の `Update` も AppKit の main スレッドで動く見込みだが、文書では確かめられなかった。プラグインの中で `pthread_main_np()` を記録すれば確かめられる（`unity-native-plugin` への申し送りの候補）
- **通知の delegate を入れる時期**: `DllImport` の `.bundle` は C# が最初に呼んだときに読まれるので、起動の終わりに間に合わない（コールドスタートのタップを取りこぼす）見込み。Xcode の書き出しでリンクする形なら起動時に読まれるので、`NSApplicationWillFinishLaunchingNotification` を受けて入れる口（あるいはホストのネイティブのコード）で間に合わせられる見込み。iOS の D-7 と同じく、ホストのネイティブのコードが入れる関数を呼ぶ前提にするかを決める

---

## 4. `UNUserNotificationCenter` の macOS での扱い

### [公式]

- delegate は「before your app finishes launching」に入れる。例は iOS の `willFinishLaunching` / `didFinishLaunching`。後で入れると届く通知を取りこぼしうる
  - https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate
- 共有の center は「simultaneously from any of your app's threads」使える。delegate は、delegate と関わる処理の前に入れる
  - https://developer.apple.com/documentation/usernotifications/unusernotificationcenter
- `applicationWillFinishLaunching(_:)` は `@MainActor`（macOS で delegate を入れる一番早い app delegate の時点）
  - https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationwillfinishlaunching(_:)
- 許可の求め方（最初の 1 回だけ OS が尋ねる）: https://developer.apple.com/documentation/usernotifications/asking-permission-to-use-notifications
- App Sandbox は Mac App Store の要件（9 章）。通知のために sandbox や entitlement が要るという記述は見つからなかった

### [手元]

- **bundle の無いプロセス**（コマンドラインの実行ファイル）で `UNUserNotificationCenter.current()` を呼ぶと、例外で落ちる（`checks/nobundle.out`）:
  ```
  *** Terminating app due to uncaught exception 'NSInternalInconsistencyException',
  reason: 'bundleProxyForCurrentProcess is nil: mainBundle.bundleURL file:///…/checks/'
  ```
  → C ABI は `Bundle.main.bundleIdentifier == nil` を入口で調べ、`current()` を呼ばずにエラーで返す必要がある（試作は `3`＝NOT_SUPPORTED で返し、落ちなかった）。iOS の 3.1 の「コマンドラインの実行ファイル（確かめない）」に当たり、macOS では実際に起こりうる（C の利用者がコマンドラインのツールから呼ぶ）
  - 落ちた後、プロセスが終わらずに残った（クラッシュの報告の処理と思われる）。テストで流すときは時間の上限を付ける
- **ad-hoc で署名した `.app`**（Hardened Runtime なし、`LSUIElement`）では `getNotificationSettings` が動き、`authorizationStatus = 0`（notDetermined）。完了は別のスレッドから来て、`DispatchQueue.main.async` で積むと C の側で `on_main=1`、`pthread_main_np()=1`（C の `main` が `CFRunLoopRunInMode` で main の run loop を回しているとき）
- `requestAuthorization`（許可のダイアログ）は**試していない**。利用者の Mac の通知の設定に項目が増え、ダイアログが出るため（許可を得てから行う）

### [推測]

- ad-hoc や署名なしのアプリで、許可や通知の表示が拒まれるか（`UNErrorCodeNotificationsNotAllowed` など）は、公式の記述が見つからなかった。Apple の forum には helper や launch agent で失敗する例がある（https://developer.apple.com/forums/thread/718777 など）。bundle id と署名が安定していることが前提になる見込み。許可を得て ad-hoc の `.app` で `requestAuthorization` を試すのが確実
- `NSApplication` の delegate との関係: UN の delegate は NSApplication の delegate とは別のオブジェクト。ホスト（Flutter の `FlutterAppDelegate` など）が UN の delegate を入れる場合は iOS の D-7 と同じ共存の問題になる

---

## 5. NSPasteboard のプライバシー

**結論: macOS 15.4 から API（`accessBehavior`、`detect*`）があり、「ほかのアプリが置いた内容をプログラムから読むと確認が出る」機能が予告されている。macOS 26.3 では既定では有効でなく、開発者向けのプレビューの鍵で有効にできることを手元で確かめた。**

### [公式]

- AppKit の更新（April 2025「macOS pasteboard privacy」）: 一般の貼り付け板をプログラムから読むと確認を出す機能が今後の macOS に入る。貼り付けに関わる UI の操作の結果なら出ない。`detect` 系で内容を読まずに種類を調べられる。`accessBehavior` で常に許可・常に拒否・確認のどれかが分かる。`defaults write <bundle id> EnablePasteboardPrivacyDeveloperPreview -bool yes` で試せる
  - https://developer.apple.com/documentation/updates/appkit
- `accessBehavior`: 「The user can customize this behavior per-app in System Settings for any app that has triggered a pasteboard access alert in the past」
  - https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-86972
  - https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum/ask
- SDK のヘッダー（MacOSX26.5.sdk の `NSPasteboard.h`。`API_AVAILABLE(macos(15.4))`）の説明:
  - `Default`: 一般の貼り付け板は読むと確認。**一般以外の貼り付け板（名前付き）は常に許可**。一度も確認を出していないアプリは `.default` を返し、設定の画面に出ない
  - `Ask`: 確認を出す。ただし「user originated and paste related」の読み出しは常に許可
  - `AlwaysAllow` / `AlwaysDeny`: 利用者が設定で選ぶ。AlwaysDeny でも利用者の貼り付けの操作は許可
  - `detectPatternsForPatterns:completionHandler:`、`detectValuesForPatterns:`、`detectMetadataForTypes:`（`NSPasteboardDetectionPattern*`、`NSPasteboardMetadataTypeContentType`）
- macOS 15.4 と 26 のリリースノート（https://developer.apple.com/documentation/macos-release-notes/macos-15_4-release-notes 、https://developer.apple.com/documentation/macos-release-notes/macos-26-release-notes ）には貼り付け板の項目が無かった。有効になる版は公式に書かれていない

### [手元]（macOS 26.3）

- 一般の貼り付け板の**中身は読まず**、`accessBehavior` だけを見た（利用者の貼り付け板の内容を読まない、書き換えないため。書き込みと読み出しは名前付きの貼り付け板 `com.example.ntk.probe` だけで行った）

  | 条件 | `accessBehavior` |
  |---|---|
  | コマンドラインの実行ファイル（bundle なし） | 2（alwaysAllow） |
  | ad-hoc の `.app`（`com.example.ntkprobe.smokeapp`） | 2（alwaysAllow） |
  | 同じアプリに `EnablePasteboardPrivacyDeveloperPreview = YES` | 0（default＝読むと確認が出る状態） |
  | 鍵を消した後 | 2 |

  → macOS 26.3 では既定で強制されていない。プレビューの鍵を入れても名前付きの貼り付け板の往復は確認なしで成功した。鍵は試した後に `defaults delete` で消した
- 一般の貼り付け板を読んだときに確認が出るか（とその間 main が止まるか）は**試していない**（利用者の貼り付け板を読むため。許可を得て、自分で置いた内容で試すのが確実）

### 設計への含み

- iOS の 3.1 の「読み出しが利用者が答えるまで main を止める」が macOS でも将来起こりうる。C ABI の読み出しは非同期だけにする、`detect` 系を足す、`accessBehavior` を返す関数を足す、を検討する
- 名前付きの貼り付け板は対象外なので、テストは名前付きで書ける

---

## 6. スレッドの要件と、表示の基点

### [公式]

- `NSAlert` は `@MainActor class`（文書の宣言）。`beginSheetModal(for:completionHandler:)` はウインドウにシートとして付ける（critical はほかのシートの上にも出る。そうでなければ順に並ぶ）。`runModal()` はアプリ全体のモーダル（app-modal）で、押されたボタンを返すまで戻らない。プログラムから取り消すとボタン以外の値を返しうる
  - https://developer.apple.com/documentation/appkit/nsalert
  - https://developer.apple.com/documentation/appkit/nsalert/runmodal()
  - https://developer.apple.com/documentation/appkit/nsalert/beginsheetmodal(for:completionhandler:)
- `NSSharingServicePicker` は Swift の宣言では main actor の印が無い（`class NSSharingServicePicker`）。`show(relativeTo:of:preferredEdge:)` は `NSRect` と `NSView` が要る。macOS 13 以降はポップオーバーで出す。ヘッダーには「Note that this method must be called on mouseDown」。`close()`（macOS 13 以降）で閉じると delegate に `nil` の service が渡る
  - https://developer.apple.com/documentation/appkit/nssharingservicepicker
  - https://developer.apple.com/documentation/appkit/nssharingservicepicker/show(relativeto:of:preferrededge:)
- `NSPasteboard`: 文書にもヘッダーにもスレッドの制限の記述が無い（main actor の印も無い）
  - https://developer.apple.com/documentation/appkit/nspasteboard
- AppKit のスレッドの安全性（古い文書）: `NSView` とその子孫、`NSCell` は main スレッドだけ。イベントは main で受ける。ウインドウは別スレッドで作れるが勧めない
  - https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/Multithreading/ThreadSafetySummary/ThreadSafetySummary.html

### [手元]

- Swift 6 で nonisolated の文脈から `NSAlert()` を作ると main actor の警告、`NSSharingServicePicker(items:)` と `NSPasteboard.general` は何も出ない（1 章の 8）
- 名前付きの貼り付け板の書き込みと読み出しを、C の `main`（main スレッド）から呼んで成功した。別スレッドからは試していない

### [推測]

- ウインドウが無いとき: `runModal()` はウインドウが無くても app-modal のパネルとして出せる（シートは親のウインドウが要る）。ただし `NSApplication` が動いていないプロセス（コマンドラインのツール）や、`LSUIElement` / 後ろにいるアプリでは前に出ない、出ても入力を受けないことがある。Unity のフルスクリーンの上に出るかも未確認
- Share はウインドウの中の `NSView` と矩形が要るので、C ABI では「key window の contentView の中心」などの既定を決めるか、基点を渡す口（`NSView*` か座標）を設ける必要がある。iOS の「表示元を渡す口を設けない」（1b の 21 章の 6）を macOS でそのまま使えるかを決める
- `runModal()` は呼んだ main を止めるので、iOS と同じ「Dialog は非同期だけ」（AC-7）を守るなら `beginSheetModal` か、main に積んだ `runModal` で完了をコールバックする形になる。`runModal` を main に積む形でも、モーダルの間は run loop がモーダルのモードで回り、ゲームの描画（Unity の main のループ）が止まる見込み

---

## 7. Flutter・Rust・Godot

### [公式]

- **Flutter（macOS の C の呼び出し、2026-11-03 更新、Flutter 3.50）**: 「Since Flutter 3.38, we recommend using the `package_ffi` template with build hooks」。dynamic のライブラリは `.framework` で配り、Embed & Sign する。起動時に読み込まれ、記号は `DynamicLibrary.process` で解ける（`DynamicLibrary.open` も使えるが「unclear how Apple's review process handles this」）。スレッドの記述は無い
  - https://docs.flutter.dev/platform-integration/macos/c-interop
- **Flutter のスレッドの統合**: 「Flutter 3.35 merges the UI and platform threads by default on macOS and Windows」（iOS と Android は 3.29）。理由は「The split-thread design prevented … Dart FFI to interoperate with native APIs that must be called on the platform thread」。opt-out は書かれていない
  - https://docs.flutter.dev/release/breaking-changes/macos-windows-merged-threads
- **Flutter の macOS のアプリの既定**: 「configured by default to be signed, and sandboxed with App Sandbox」。App Store の外で配るなら公証のために Hardened Runtime を有効にする
  - https://docs.flutter.dev/platform-integration/macos/building
- **Dart**: `NativeCallable.listener` は「can be invoked from any thread」、非同期で、作った isolate に SendPort で送る。戻り値は void だけ。`NativeCallable.isolateLocal` は「can only be invoked on the mutator (main) thread of the current isolate」で、ほかのスレッドから呼ぶと「will abort the process」
  - https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html
  - https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.isolateLocal.html
- **Rust**: `#[link(name = "...", kind = "framework")]` は「Indicates a macOS framework. This is only valid for macOS targets」。framework の探し場所はこのページに無い（`cargo:rustc-link-search=framework=<dir>`、rustc の `-L framework=` は別の文書）
  - https://doc.rust-lang.org/reference/items/external-blocks.html
- **Godot**: `.gdextension` の macOS のライブラリは `.dylib`（4.4 の例は `.framework`）。依存は `[dependencies]` に書き、`Contents/Frameworks` に入れる（「it is necessary to have shared libraries inside a folder called Frameworks」）。書き出しでは、GDExtension か ad-hoc の署名を使うなら Disable Library Validation を有効にする。公証には Developer ID と、Debugging の entitlement を外すことが要る
  - https://docs.godotengine.org/en/4.6/tutorials/scripting/gdextension/gdextension_file.html
  - https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_macos.html

### [推測]

- Flutter 3.35 以降の macOS では Dart の main isolate が platform（main）スレッドで動くので、C ABI が main から非同期にコールバックすれば `isolateLocal` でも動きうる。ただし手元の Flutter は 3.7.0（iOS の 8.3）で確かめられない。iOS と同じく `NativeCallable.listener` を前提にするのが安全
- Rust・Godot はスレッドを統合しない（Godot のスクリプトは main スレッドで動くが、コールバックは自分で main に戻す必要がある）。C ABI が「main から非同期に呼ぶ」規則なら、Godot は `call_deferred` 等を挟まずに受けられる見込み
- Godot の `[dependencies]` で `Contents/Frameworks` に入れれば `@executable_path/../Frameworks` で解けるので、2 つの framework の構成と合う。GDExtension 本体（dylib）から C ABI を呼ぶ形になる

---

## 8. プライバシーマニフェスト

### [公式]

- 「The types of data collected … You need to provide this information … on all platforms」。「The required reasons APIs … You need to provide this information … on iOS, iPadOS, tvOS, visionOS, and watchOS」。つまり **required reason API の申告は macOS には要らない**。データの収集の申告は macOS も対象
  - https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
- required reason API の文書も対象を「iOS, iPadOS, tvOS, visionOS, or watchOS」と書く。2024-05-01 から申告の無いアプリを App Store Connect が受け付けない（対象の OS について）
  - https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- 第三者の SDK の要件（一覧の SDK はマニフェストと署名が必須）: OS の範囲を書いていない。このライブラリは一覧に無い
  - https://developer.apple.com/support/third-party-SDK-requirements/
- 置き場: macOS のアプリは `Contents/Resources/`。macOS の framework は `Versions/A/Resources/`
  - https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle

### 設計への含み [推測]

- iOS の D-18（FileTimestamp の理由を `IosLibrary` のマニフェストに書く）は macOS では必須でない。データを集めないので、macOS の framework にはマニフェストを入れなくても App Store の要件に触れない見込み。入れる場合は `Versions/A/Resources/PrivacyInfo.xcprivacy`（Xcode のリソースの段で入る）。OS をまたいで同じにするかは方針で決める

---

## 9. Mac App Store と Developer ID の違い

### [公式]

| 項目 | Mac App Store | Developer ID（App Store の外） |
|---|---|---|
| App Sandbox | **必須**（「To distribute a macOS app through the Mac App Store, you must enable the App Sandbox capability」。App Review 2.4.5 (i)「must be appropriately sandboxed」） | 任意 |
| Hardened Runtime | 要件として書かれていない | 公証に必須 |
| 公証 | 要らない（「you aren't required to notarize software that you distribute through the Mac App Store」） | 必須（macOS 10.15 以降、2019-06-01 以降に作ったもの） |
| 署名 | Xcode の書き出し（Apple Distribution）。App Review 2.4.5 (ii)「packaged and submitted using technologies provided in Xcode」「self-contained」 | Developer ID Application ＋ secure timestamp |
| コードの追加 | 2.4.5 (iv)、2.5.2: 後からコードを落として足すのは不可。バンドルの中に閉じる | 制限は公証と Gatekeeper の検査（Disable Library Validation を付けると追加の検査） |
| required reason API の申告 | macOS は対象外（8 章） | 対象外 |

出典:
- https://developer.apple.com/documentation/security/app-sandbox
- https://developer.apple.com/documentation/xcode/configuring-the-macos-app-sandbox
- https://developer.apple.com/app-store/review/guidelines/ （2.4.5、2.5.1、2.5.2）
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- https://developer.apple.com/documentation/security/hardened-runtime

### 設計への含み [推測]

- ライブラリは sandbox の中で動く必要がある。NSPasteboard、NSAlert、NSSharingServicePicker、UNUserNotificationCenter は sandbox の entitlement を要しない見込み（手元では sandbox を有効にしたアプリで試していない。1.x の Unity の Xcode の書き出しは `ENABLE_APP_SANDBOX = YES` で動いている）。Share で選ばれたサービスによってはファイルの読み出しの権限が要る（共有するファイルの URL を sandbox の外から渡す場合）
- 両方の配り方で動くこと（sandbox あり・なし、Hardened Runtime あり・なし）を、サンプルかスモークで確かめる計画を立てる

---

## 10. まとめ: 設計で決めること（この観点から）

1. macOS の framework の版付きの構成で、公開ヘッダーを `Headers/NativeToolkitC/` に置く方法（最上位の `Headers` のリンクを作る段、または置き場の変更）。install name に `Versions/A` が入ること
2. C ABI の framework の rpath に `@loader_path/../../..` を足し、`Contents/Frameworks` 以外（Unity の `PlugIns` など）に置かれても兄弟の Swift の framework を解けるようにするか
3. Unity の取り込み方: 1.x の「Create Xcode Project ＋ `__Internal`」を続けるか、`.bundle`（または dylib）も配って `DllImport("名前")` にするか。通知の delegate を起動の終わりまでに入れる方法（プレイヤーは UN の delegate を持たないが、C# は間に合わない）
4. bundle の無いプロセスでの通知（`current()` が例外で落ちる）を入口で弾くエラーの番号
5. 貼り付け板のプライバシー（`accessBehavior`、`detect` 系）を C ABI に出すか。読み出しを非同期だけにするか
6. Dialog を `runModal` と `beginSheetModal` のどちらで出すか、ウインドウが無いとき・後ろにいるときの扱い。Share の基点（view と rect）の既定と、渡す口を設けるか
7. 開発用の署名（ad-hoc ＋ Hardened Runtime で読み込めない）の扱いを、サンプル・スモーク・マニュアルでどう書くか。配る framework は署名しない（iOS の D-18）を続けるか
8. プライバシーマニフェストを macOS の framework に入れるか（必須ではない）

## 付録: 試したコマンド（要点）

```bash
P=…/scratchpad/survey/probe-c; W=$P/work
ruby gen.rb $W lib
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer xcodebuild archive \
  -project $W/lib/MacProbe.xcodeproj -scheme MacProbeCApi -configuration Release \
  -destination 'generic/platform=macOS' -archivePath $W/arch/MacProbeCApi.xcarchive \
  SKIP_INSTALL=NO CODE_SIGNING_ALLOWED=NO
xcodebuild -create-xcframework -framework $W/arch/MacProbeCApi.xcarchive/Products/Library/Frameworks/MacProbeCApi.framework \
  -output $W/xcf/mac-probe-capi.xcframework
nm -gU -arch arm64 …/MacProbeCApi; nm -gU -arch x86_64 …/MacProbeCApi; otool -L …; codesign -dv …
DEVELOPER_DIR=/Applications/Xcode26.3.app/Contents/Developer xcrun clang -arch arm64 -arch x86_64 \
  -F<slice> -framework MacProbeCApi -framework CoreFoundation -Wl,-rpath,<slices> smoke/main.c -o smoke
./smoke; arch -x86_64 ./smoke
ruby gen.rb $W consumer   # HR=YES, CODE_SIGN_IDENTITY=-
DEVELOPER_DIR=…Xcode26.3… xcodebuild build -project $W/consumer/Consumer.xcodeproj -scheme SmokeApp -configuration Release
SmokeApp.app/Contents/MacOS/SmokeApp      # → Library Validation で拒まれる
codesign -f -s - NoHR.app                 # → 動く
codesign -f -s - -o runtime --entitlements dlv.entitlements HRdlv.app   # → 動く
defaults write com.example.ntkprobe.smokeapp EnablePasteboardPrivacyDeveloperPreview -bool yes  # 試した後に delete
```

作業の残り: `probe-c/work/`（約 270 MB。ビルドの産物）は scratchpad に残してある。要らなければ消してよい。
