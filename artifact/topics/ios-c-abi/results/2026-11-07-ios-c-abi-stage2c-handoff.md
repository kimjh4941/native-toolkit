# 段階 2c の申し送り: `unity-native-plugin` の iOS を C ABI に移す

- 作成日: 2026-11-07（レビュー待ち）
- 対象: `artifact/topics/ios-c-abi/README.md` の段階 2c、C ABI の設計書 第 2 部（`designs/2026-11-03-ios-c-abi-c-abi-design-part2.md`。以下「第 2 部」）13 章の TC-1
- 読み手: `unity-native-plugin`（別リポジトリ）で iOS の部分を移す人と agent（C# の P/Invoke の包み、`.mm`、Unity の iOS のビルドを扱う。このリポジトリの設計書は読んでいない前提で書いた）
- 前提の段: 2b（C ABI の実装）は、シミュレーターでの実装とテスト（TB-0〜TB-12）まで済んだ。**実機の区切りと、版と `dist/<リリース版>` を決める 2b の締めはまだ**（7 章）
- 照らした実物: このリポジトリの `c7f2702f`（`feature/NTKIT-18`）の公開ヘッダー `ios/IosLibraryCApi/include/NativeToolkitC/*.h`（134 関数）、`scripts/build_ios_library_xcframework.sh`、`scripts/check_ios_dist.py`。`unity-native-plugin` は `1c246a3`（`feature/UNT-14`、2026-10-31）を読むだけで見た
- 2c の成功（Unity が C ABI を呼び、EditMode・PlayMode・実機のテストを通す）が、2.0.0 を出す条件（README 5 章。Android と同じ）

## 1. 何が変わるか

`unity-native-plugin` の iOS は今、`unity-ios-native-toolkit-1.3.0.xcframework`（ブリッジ。`UnityIosPlugin`。C の関数は `*ManagerBridge.h` / `.m` の Objective-C が出す）を `[DllImport("__Internal")]` で呼び、JSON の文字列でやりとりしている。2.0.0 ではこのブリッジは無くなり（段階 3）、代わりに C ABI（`IosLibraryCApi.framework` の `ntk_*`）を同じく `__Internal` の P/Invoke で呼ぶ。各 manager の公開の API は保ち、下の層だけを置き換える（Android の 2c と同じ進め方）。**4 機能（Clipboard、Dialog、Notification、Share）を一度に移す**（README D-20。1.x の `IosLibrary.framework` と 2.0.0 の `IosLibrary.framework` は同じ名前なので、同じアプリに入れられない。D-12）。

| | 今（1.x） | 2.0.0 |
|---|---|---|
| 呼ぶもの | ブリッジの 43 関数（`showDialog`、`clipboardCopy`、`notificationSetup` など。`DllImport("__Internal")`。iOS の 4 つの manager の `DllImport` の宣言は 43 本で、8.3 と一致する） | `ntk_*`（134 関数。同じく `DllImport("__Internal")`） |
| 結果の返り方 | `const char*`（JSON か文言）。コールバックの間だけ有効。`user_data` は無い | C の関数ポインタのコールバック（`[MonoPInvokeCallback]`）、構造体、**所有権ごと渡すハンドル**（`ntk_*_free` で解放）。すべてのコールバックに `void* user_data` と `ntk_release_fn release` |
| JSON の層 | C# とブリッジの間は JSON（`IosClipboardJsonBuilder` / `Parser` / `Reader`、`IosShareJsonBuilder`、`IosNotificationJsonBuilder`） | C の関数は構造体・ビルダー・ハンドルで受け渡す。**JSON が残るのは、Notification の公開の API、userInfo の JSON の文字列、Clipboard の `ntk_clipboard_detect_values_async` の結果（`ntk_clipboard_values_fn` の `ntk_string* values_json`。8.3 の CL-10）の 3 つ**（4.7） |
| リスナー | `setNotificationActionReceivedCallback` などの差し替え（static の上書き） | 足す・外す（`ntk_*_add_*_listener` / `ntk_*_listener_remove`）。差し替えは包みが保つ（4.4） |
| 通知の delegate | C# の `IosNotificationManager.Initialize()`（`Awake` から）が `notificationSetup` を呼ぶ | **`.mm` が起動の中（`didFinishLaunching`）で `ntk_notification_install` を呼ぶ**。C# からは呼ばない（例外は 4.5 の H2-3 の入れ直し） |
| xcframework | `ios-native-toolkit-1.3.0` と `unity-ios-native-toolkit-1.3.0` | `ios-native-toolkit-2.0.0` と `ios-native-toolkit-capi-2.0.0`（**両方を Embed & Sign**。capi は `IosLibrary` に実行時に依存する。D-9） |
| ヘッダー | 無い（C# の宣言だけ） | 公開ヘッダー（C99）。C# の宣言はこのヘッダーから書き、照らす |

## 2. まず見るもの

上から順に見る。

| 順 | 見るもの | 場所（このリポジトリ） |
|---|---|---|
| 1 | この文書の 4 章（包みで気をつけること） | - |
| 2 | 今のブリッジの 43 関数と C ABI の対応表。**「Unity の包みが保つこと」の列**が、包みで今の振る舞いを保つための指示。表の前の「どの行にも共通する違い」も読む | 第 2 部 8.3 |
| 3 | 包みに渡す事柄の一覧 | 第 2 部 16 章（この文書の 4 章に、`unity-native-plugin` の今の作りに合わせて書き直した。対応は 4.8） |
| 4 | 公開ヘッダー。C99、`<stdint.h>` と `<stddef.h>` だけ。関数ごとのコメント（どのスレッド、前面が要るか、何を返すか）がある | `ios/IosLibraryCApi/include/NativeToolkitC/`（`Common.h`、`Clipboard.h`、`Dialog.h`、`Notification.h`、`Share.h`）。配布物では `include/NativeToolkitC/` と capi の framework の `Headers/NativeToolkitC/` に同じものが入る |
| 5 | スレッド、完了の時刻、`release`、入口で拒んだとき、言語ごとの受け方 | 第 1 部（`designs/2026-10-31-ios-c-abi-c-abi-design.md`）1.3（とくに 1.3.4 の C# / Unity の行）、5.7 |
| 6 | 通知の delegate を入れる関数と、Unity の通知パッケージとの共存 | 第 1 部 1.4、5.12（5.12.7 コールドスタート、5.12.8 共存）。Unity での確かめの結果は `results/2026-10-31-ios-c-abi-unity-handoff-2-results.md`（H2-1〜H2-3） |
| 7 | 関数の一覧と OP ごとの対応 | 第 2 部 8.1（46 操作）と 8.2（134 関数） |
| 8 | 同期・非同期と完了のスレッド | 第 2 部 9 章 |
| 9 | エラーの値と、`IosLibrary` のエラーからの写し | 第 2 部 11 章。4 つの機能のエラーは 0〜5 が同じ意味（`NONE`、`INVALID_PARAMETER`、`NOT_INITIALIZED`、`NOT_SUPPORTED`、`UNKNOWN`、`OUT_OF_MEMORY`）。6 から上は機能ごとに違う（例: `NTK_DIALOG_ERROR_NOT_FOREGROUND` は 8、`NTK_SHARE_ERROR_NOT_FOREGROUND` は 6。どちらも Android と同じ値）。**iOS だけの名前がある**（Notification の 16〜20、`NTK_CLIPBOARD_ERROR_CANCELED` など）。**Android にあって iOS に無い名前もある**（Notification の 6・7・9・11〜14）。**Windows とは同じ名前で値が違うものがある**（4.3） |
| 10 | 構造体の配置の正（`sizeof` と `offsetof`） | `ios/IosLibraryCApiTests/StructLayoutTests.m`（すべての構造体とフィールド。`_Static_assert` で、3 つのスライスで組むときに確かめている） |
| 11 | C から呼ぶ手本 | `ios/IosLibraryCApiSmoke/IosLibraryCApiSmoke/Smoke.c`（`ntk_version` の確かめ、Clipboard（名前付きのペーストボードの作成・書き込み・読み取り・削除）、Dialog（表示して `ntk_dialog_cancel`）、Notification（受け手を登録してすぐ外す。イベントは 0 回、`release` は 1 回）を C から呼び、完了と `release` が main で 1 回ずつ来ることを数える。**Share は呼ばない**）。雛形の `.mm` は `results/probes/stage1a/handoff2/unity/NtkHandoff2Installer.mm`（3.4 の注意を読んでから使う） |

**`unity-native-plugin` の中の手本**（README D-20: Android の包みをそのまま使えることを示す）:

| 手本 | 写せる所 | iOS で違う所 |
|---|---|---|
| `Runtime/Android/Common/AndroidNativeToolkitCApi.cs` | `Common.h` の宣言（`ntk_version`、`ntk_string_*` など）を 1 か所に置き、機能ごとの宣言は各機能が持つ形。UTF-8 の出し入れ。版の確かめ | ライブラリの名前は `"__Internal"`（Android は `"ntk"`）。初期化の確かめ（`ntk_android_is_initialized`、`DllNotFoundException` を「使えない」にする 32 ビットの扱い）は iOS に無い。代わりに `.mm` の `ntk_notification_install`（3.4） |
| `Runtime/Android/Common/AndroidNativeCallbackQueue.cs` | `user_data` の表と、ロックを持たずに次の `Update` で動かす列。例外を投げた処理が残りを止めない作り | Android はコールバックが Android の main（UnityMain ではない）で来るので列が必須。iOS はコールバックが Unity と同じ main で来る（4.1）ので必須ではないが、「入口で拒んだときに次の `Update` で今のコールバックを呼ぶ」（4.5）には同じ列が使える |
| `Tests/Runtime/Android*CApiTests.cs`（Clipboard、Dialog、Notification、Share） | `Marshal.SizeOf` / `Marshal.OffsetOf` で構造体の配置を照らすテストの形 | 期待値は iOS の `ios/IosLibraryCApiTests/StructLayoutTests.m` から取る（構造体もフィールドも Android と違う） |

**ID の凡例**（この文書が引く ID の出典。どれもこのリポジトリの `artifact/topics/` の下）:

| ID | 出典 |
|---|---|
| D-n | `ios-c-abi/README.md` の 8.1（決めること）。1a-n は 8.2.1 |
| P1-n | 第 1 部（`ios-c-abi/designs/2026-10-31-ios-c-abi-c-abi-design.md`）4.2。G-n は 4.4、R-n は 7 章 |
| C-n | 第 1 部 9.2（第 2 部と 2b に任せる条件） |
| U-n | 第 1 部 10 章（`unity-native-plugin` に任せた確かめ）。結果は `ios-c-abi/results/2026-10-31-ios-c-abi-unity-handoff-1-results.md` と `-handoff-2-results.md` |
| H2-n | `ios-c-abi/results/2026-10-31-ios-c-abi-unity-handoff-2-results.md` の「決めたこと」 |
| P2-n | 第 2 部 0 章の表。G2-n は 3.2 |
| OP-n | 第 2 部 8.1 |
| CL-n、DL-n、NT-n、SH-n | 第 2 部 8.3 |
| RP-n | 第 2 部 14 章 |
| AC-n | Android の C ABI の第 1 部（`android-c-abi/designs/2026-10-04-android-c-abi-c-abi-design.md`） |
| AP-n | Android の C ABI の第 2 部（`android-c-abi/designs/2026-10-05-android-c-abi-c-abi-design-part2.md`） |
| E-n | Windows の C ABI の設計書（`windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md`） |
| 知見 | `ios-c-abi/results/2026-10-18-ios-c-abi-android-lessons.md`（Android の移行から学んだこと） |

## 3. 配布物と組み込み

### 3.1 framework とヘッダー

- **dynamic の framework が 2 つ**: `IosLibrary.framework`（Swift の API）と `IosLibraryCApi.framework`（C ABI）。capi は `@rpath/IosLibrary.framework/IosLibrary` を読むので、**capi だけを入れると起動で止まる**（README 3.1、D-9）
- 公開しているのは `_ntk_*` だけ（D-11）。Swift のモジュールと `-Swift.h` は capi の配布物に入らない
- **2 つの xcframework は同じ版の組で入れる**（第 1 部 P1-19）。版の違う組は支えない。capi は最初の呼び出しで `IosLibrary` の版を読み、違えばログに出す（止めない。C-9）
- 版: `ntk_version()` は `NTK_VERSION`（`0x020000`）を返す。Windows・Android と同じく、メジャーの 2 を確かめる。**期待値は OS ごとに持つ**（RP-1）。この値はヘッダーの定数なので、取り込んだ xcframework の版はファイル名で確かめる
- スライス（`check_ios_dist.py` が照らす）: `ios-arm64`（arm64）と `ios-arm64_x86_64-simulator`（arm64、x86_64）。どちらの xcframework も同じ

### 3.2 配布物

`scripts/build_ios_library_xcframework.sh -m IosLibrary -m IosLibraryCApi -v <ライブラリの版> ...` が作る（capi は Release だけ。`--configuration debug` を渡すと止まる。Debug の配布物（`-debug.xcframework`）は capi には無い）。

| ファイル | 中身 |
|---|---|
| `ios-native-toolkit-2.0.0.xcframework` | `IosLibrary.framework`（Swift の API、swiftinterface、`PrivacyInfo.xcprivacy`） |
| `ios-native-toolkit-capi-2.0.0.xcframework` | `IosLibraryCApi.framework`（`Headers/NativeToolkitC/*.h`、`Modules/module.modulemap`。プライバシーマニフェストは持たない: 理由の申告が要る API を使わない。D-18） |
| `include/NativeToolkitC/` | 公開ヘッダー（framework の中と同じもの。バイト単位で同じことを `check_ios_dist.py` が照らす） |

- bundle id は `com.jonghyunkim.nativetoolkit.IosLibrary` と `com.jonghyunkim.nativetoolkit.IosLibraryCApi`（D-12。1.x の `ios.library.IosLibrary` から変わった）
- **署名**: 配る framework には署名しない（D-18 の A。archive で `CODE_SIGNING_ALLOWED=NO`。実機のスライスは署名なし、シミュレーターのスライスはリンカーの ad-hoc だけ）。**利用者のアプリが Embed & Sign で自分の証明書で署名し直す**。1.x の配布物は中の framework に個人の証明書の署名が入っていたので、ここが変わる。1a の 1 回目の確かめ（U-2）で、開発用の署名で 2 つの framework がアプリと同じ Team で署名し直されることは確かめた。配布用の署名（Distribution のアーカイブ、Validate App）はまだ（7 章）
- 置き場所は `dist/<リリース版>/ios/`。**2c で使う `dist/<リリース版>` はまだ無い**（7 章）

### 3.3 Unity の Xcode のプロジェクトへの入れ方

1a の確かめ（使い捨ての Unity のプロジェクト、PostProcessBuild の PBXProject の API で入れた。`results/2026-10-31-ios-c-abi-unity-handoff-1-results.md`）で動いた形:

| 対象 | 入れ方 |
|---|---|
| `ios-native-toolkit-capi-2.0.0.xcframework`（`IosLibraryCApi.framework`）と `ios-native-toolkit-2.0.0.xcframework`（`IosLibrary.framework`） | **UnityFramework** のターゲットにリンクする（Do Not Embed）。C# の `DllImport("__Internal")` は UnityFramework にリンクしたシンボルを引く |
| 同じ 2 つ | **アプリ（Unity-iPhone）** のターゲットに **Embed & Sign**（`CodeSignOnCopy`） |
| `UserNotifications.framework` | **UnityFramework に足す**。足さないと `.mm` がリンクで止まる（`_OBJC_CLASS_$_UNUserNotificationCenter` が無い。1 回目の結果の「申し送りとの違い」2） |
| `.mm` | 3.4 |

- 1a で確かめたのは開発用の署名で、`-allowProvisioningUpdates` を付けない自動の署名
- **今の `unity-native-plugin` のビルドの処理は 2.0.0 の名前を扱えない**（`1c246a3` を読んだ範囲）:
  - `PreBuildProcessor`・`PostBuildProcessor`・`IosFrameworkPatcher` は `ios-native-toolkit-` と `unity-ios-native-toolkit-` の前方一致と辞書順の最大で選ぶ。`ios-native-toolkit-capi-2.0.0` は `ios-native-toolkit-2.0.0` より辞書順で後（`c` > `2`）なので、**両方を置くと `IosLibrary` の枠に capi が必ず選ばれる**
  - `Plugins/iOS/` に `VERSION.txt` は無い（Android と Windows にはある）
  - `PostBuildProcessor` の development ビルドは `-debug.xcframework` だけを受け、capi には `-debug` が無い
  - `PostBuildProcessor` と `PreBuildProcessor` の asmdef（`Editor/Build/NativeToolkit.BuildProcessors.Editor.asmdef`）は `defineConstraints: ["NATIVETOOLKIT_ENABLE_BUILD_STEPS"]` で、この定義が無いと組まれない。UPM で入れたふつうの利用者のビルドでは動かない
  - `PostBuildProcessor` は xcframework を `Packages/com.jonghyunkim.nativetoolkit/Plugins/iOS`（プロジェクトの中に埋め込んだパッケージの道）から決め打ちで読み、書き出した Xcode のプロジェクトの `Frameworks/com.jonghyunkim.nativetoolkit/Plugins/iOS` に写す
  - ほかの口は手動のメニュー `Tools/Native Toolkit/iOS/Configure Xcode Project`（`IosConfigureProjectWindow` から `IosFrameworkPatcher`）
  - `Plugins/iOS/*.xcframework.meta` の `PluginImporter` は iOS を有効にするだけで、埋め込み（Embed & Sign）の設定は持たない
- **README 5 章で「2b の前に `unity-native-plugin` に頼むこと」とした 3 つ**（iOS と macOS の xcframework を `VERSION.txt` で完全なファイル名に固定する、3 か所の探索を完全一致にする、`PostBuildProcessor` の development ビルドで `-debug` が無ければ release を使う）は、このコミットでは入っていないように見える。2c の最初に、済んだかを確かめる（済んでいなければ 2c で入れる）
- 2 つ目の必須の xcframework を、ブリッジ（`unity-ios-native-toolkit-`）から capi に替える。`Plugins/iOS/` の 1.3.0 の 2 つと `.meta` を消す
- **推奨: 3.3 の表の形（PBXProject の API で、2 つをリンクして Embed & Sign し、`UserNotifications.framework` を足す）を、条件の付いた asmdef の外（ふつうの利用者のビルドで必ず動く所）に置く**。どの口（PostProcessBuild の PBXProject、`PluginImporter` の設定）で行うかは**決まっていない**（5 章）

### 3.4 `.mm`（通知の delegate を入れる）

- **`.mm` は `AppDelegateListener` の `didFinishLaunching:` で `ntk_notification_install()` を呼ぶ**（H2-2。Unity の名前 `AppDelegateListener.h`、`UnityRegisterAppDelegateListener`、`didFinishLaunching:` は 6000.4.2f1 にある）。`kUnityWillFinishLaunchingWithOptions` は、リンクの順しだいで Unity の通知パッケージ（`com.unity.mobile.notifications`）より前になり、パッケージに delegate を取られる（U-4）。`didFinishLaunching` ならリンクの順に関わらずパッケージの後に入り、コールドスタートのタップにも間に合った（U-3。実機 iPhone XS / 18.7.2）
- `ntk_notification_install` の契約（第 1 部 1.4）: main スレッドだけ（main 以外は `NTK_NOTIFICATION_ERROR_WRONG_THREAD` を返して何もしない）。同期で、待たない。戻り値は `NONE` か `WRONG_THREAD` だけ。冪等（今の delegate がライブラリの proxy なら何もしない）。差し替えられた後に呼ぶと入れ直す。起動の後に呼ぶと `NONE` を返してログを出す（コールドスタートのタップは失う）。外す関数は無い
- **呼ばないと**: 前面にいる間は通知が表示されない（`willPresent` が呼ばれない）。通知のイベントの受け手の登録（`ntk_notification_add_interaction_listener`、`ntk_notification_add_settings_request_listener`）と `ntk_notification_get_launch_response_async` は `NTK_NOTIFICATION_ERROR_NOT_INITIALIZED` を返す。表示・予約・取り消しなどの操作は動く
- **`.mm` を入れるかを利用者が選べる設定を持つ**（README の 2c の行。通知を使わないアプリの delegate を奪わないため）。設定の形は 5 章
- 雛形 `results/probes/stage1a/handoff2/unity/NtkHandoff2Installer.mm` は下調べ用で、**既定が `NTK_HANDOFF2_INSTALL_AT 1`（`kUnityWillFinishLaunching`）のまま**。写すなら `didFinishLaunching` だけにし、ログの仕掛け（delegate のクラスを出す行）は外す。include は `<IosLibraryCApi/NativeToolkitC/Notification.h>`
- 置き場所: 雛形のコメントのとおり `Plugins/iOS/` に置けば UnityFramework に組まれる。パッケージの中のどこに置き、設定で外すときにどう除くか（`PluginImporter` の有効・無効、ビルドの処理で消す）は**決まっていない**（5 章）

### 3.5 版と設定

- **アプリの最小 iOS は 18.0 以上**（D-15。xcframework の `MinimumOSVersion` と `LC_BUILD_VERSION` の minos が 18.0）。1.x と同じ。Player Settings の Target minimum iOS Version を 18.0 以上にする（18.0 より低いときにどこで止まるかは確かめていない）
- Xcode: C ABI だけを使う Unity の利用者は Xcode 26 のどの版でもよい（D-16。Swift の API を `import` しないため）。このリポジトリは Xcode 26.6 で組む。1a の Unity の確かめは Unity 6000.4.2f1 と Xcode 26.3
- 64 ビットだけ（`size_t` とポインタは 8 バイト）
- IL2CPP（iOS の Unity は IL2CPP だけ）

## 4. C# の包みで気をつけること

### 4.1 スレッド

- **完了、イベント、受け付けた後の `release` は、すべて iOS の main スレッドで来る**（main キューに積んだブロックの中。第 1 部 1.3）
- **iOS の Unity の C# は main スレッドで動く**（`CADisplayLink`。README 0 章）。Android（UnityMain と Android の main が別）と違い、**受けたスレッドがそのまま Unity のスレッドで、受け渡しは要らない**（第 1 部 1.3.4）。ただし、コールバックは Unity のフレームの外（main の run loop の別のブロック）で来る。Android と同じ「受けて積む」形のままでも動くので、Android と共通の作りにするなら、そのままでよい
- C の関数はどのスレッドから呼んでもよく、**決して main を待たない**。例外は `ntk_notification_install`（main だけ）
- **main から呼ぶと、完了と `release` は必ず関数が戻った後に来る**（main から呼ばれても積むため。第 1 部 1.3）。Unity の C# は main から呼ぶので、Unity では「戻った後」になる。**ただし契約は Android と同じで、出力引数（要求の ID など）が見える前に完了が来うると考える**（main 以外のスレッド、たとえば `Task.Run` の中から呼ぶと、戻る前に来うる。R-11）。対応付けは `user_data` で行う（4.2）
- **どのスレッドでも、完了や `release` を同期で待たない**。main で待つと、main に積まれた完了が来ないので必ず止まる（第 1 部 1.3「なぜ main を待たないか」）
- **コールバックの中で main を長く塞がない**（ネットワーク、大きなファイル。起動の間なら OS の watchdog に止められうる。第 1 部 1.3.2）
- **`ntk_clipboard_read_async`・`ntk_clipboard_read_data_async` は非同期の名前だが、貼り付けの許可を待つ間 main を止める**（`Clipboard.h` のコメント。ほかのアプリが置いた内容なら OS が貼り付けの許可のダイアログを出し、答えるまで main が止まる。実機 iOS 18.7.2 で 44 秒。README 3.1、RP-4）。今のブリッジの `clipboardRead` も同じなので、包みが今の `Read` を保つ限り、止まる場面は今と同じ。止めたくない利用者には `LoadItem`（`ntk_clipboard_load_item_async`）を案内する
- Dialog と Share を出している間もゲームのフレームは進む（U-5。今と同じ）

### 4.2 `user_data`、要求の ID、`release`

**完了と要求の対応付けは `user_data` で行う**（第 1 部 1.3 の「完了の時刻」）。Windows の包みの「`user_data` を NULL にし、出力の要求の ID と表で照合する」形は使わない。理由:

- 出力の要求の ID が見える前に完了が来うる（4.1。Unity の main から呼ぶ限りは来ないが、約束しない）
- 要求の ID を持たない操作がほとんど: 要求の ID を返すのは Dialog の 6 つ（`ntk_dialog_show_*_async` の `uint64_t* out_request_id`。完了の `ntk_dialog_result_fn` も `request_id` を持つ）と `ntk_clipboard_load_item_async`（完了の `ntk_clipboard_load_fn` も `request_id` を持つ）だけ。ほかの完了（Share、Notification のすべて、Clipboard のほか）とイベント（`ntk_clipboard_change_fn`、`ntk_notification_interaction_fn`、`ntk_notification_settings_request_fn`）は `user_data` しか持たない

そこで:

- **登録ごとに別の `user_data` を渡す**。包みが作る整数のキー（連番を `IntPtr` にしたもの）を、**呼ぶ前に**表へ入れて渡すか、`GCHandle` を渡す
- コールバックの中で、`user_data` から要求の物を引く。**完了つきの操作では、完了を呼んだ直後に同じ main のブロックの中で `release` が来る**（第 1 部 5.7）ので、キーのまま後のフレームに積んで後で引くと、もう消えている。後に回すなら、引いた物を積む
- `user_data` の片付け（表から消す、`GCHandle.Free`）は **`release` の中だけ**で行う。`release` は `release != NULL` なら登録ごとに**ちょうど 1 回**、次のどれかで来る:
  - 完了つきの操作を受け付けた後: 完了の直後に main で
  - イベントの登録を受け付けた後: `_listener_remove` の後に main で（外さなければ来ない）。main から外すと、その場で以後の配送が止まり、`release` はその後に来る。main 以外から外すと、`release` が来るまで配送が来うる（第 1 部 1.3）
  - **入口で拒んだとき**（`NULL`、不正な UTF-8、`struct_size`、範囲、未初期化など）: 完了は**来ず**、`release` が**呼び出しスレッドで関数が戻る前に**来る（4.5 の「入口で拒むと完了は来ない」）
  - **プロセスが終わるときは、完了も `release` も来ない**
- `release` の後は、その `user_data` で配送は来ない
- **入口で拒んだときの `release` は呼び出しの中で同期に来る**ので、`release` が取るロックを持ったまま `ntk_*` を呼ばない（第 1 部 1.3.2）
- **要求の ID は 64 ビット（`uint64_t`）**。C# では、コールバックの引数（`ntk_dialog_result_fn` と `ntk_clipboard_load_fn` の `request_id`）、出力（`out ulong`）、取り消しの引数（`ntk_dialog_cancel`、`ntk_clipboard_cancel_load`）、表のキーをすべて `ulong` にする。Windows の宣言（`uint`）を写さない。`out_request_id` は NULL でもよい（取り消せなくなるだけ）。完了の後の取り消しと、知らない ID の取り消しは何もしない
- **Share は取り消せない**。ホストが表示中に window や root の ViewController を差し替えると、完了も `release` も来ないことがあり、その `user_data` は漏れうる（第 1 部 1.3 の「ちょうど 1 回の完了」、0.1 の契約）。Unity が表示中に window や root を差し替えるかは、このリポジトリでは確かめていない（1a の U-5 では Dialog と Share の完了と `release` が 1 回ずつ来た）
- **コールバックが受け取ったハンドル（`ntk_dialog_result*`、`ntk_share_result*`、`ntk_clipboard_change*`、`ntk_notification_interaction*`、`ntk_notification_list*`、`ntk_string*` など）は、所有権ごと渡される**。使い終わったら、対応する `ntk_*_free` で解放する（第 1 部 5.8、AC-18）。**ブリッジの「コールバックの間だけ有効な `const char*`」とも、Windows の「借りるポインタ」とも逆**。読み取りの関数が返す `const char*` は、元のハンドルを解放するまで有効（`size_t* out_size` で長さも取れる）
- **`callback` に `NULL` を渡すと `INVALID_PARAMETER`**（P2-28）。今のブリッジは Clipboard・Notification・Share で `NULL` を受けて結果を捨てていたので、結果が要らない呼び出しには包みが空の受け手を渡す
- **利用者のコールバックの例外**: C ABI は例外の振る舞いを定めない（第 1 部 P1-16）。Unity の IL2CPP の iOS では、C# のコールバックが例外を投げると `libc++abi: terminating due to uncaught exception of type Il2CppExceptionWrapper` でプロセスが止まり、`release` は来ない（U-9。実機とシミュレーター）。**すべての `[MonoPInvokeCallback]` の本体を `try` / `catch` で囲む**（`release` の受け手も）
- デリゲートは `static readonly` に置いてプロセスの間保ち、`[MonoPInvokeCallback]` の static のメソッドにする（今の iOS の包みと同じ）

### 4.3 C# の宣言

- **共通なのは `Common.h` の宣言だけ**（`ntk_version`、`ntk_last_system_code`、`ntk_string_*`、`ntk_bytes_*`、`ntk_string_list_*`、`ntk_release_fn`）。**機能の関数・列挙・構造体は iOS 用に別に宣言する**（RP-1、README 3.3）。ヘッダーを照らした結果（iOS・Android・Windows の公開ヘッダー）:
  - **iOS だけの名前がある**: `NTK_DIALOG_BUTTON_DESTRUCTIVE` = 2 と `NTK_DIALOG_BUTTON_OPTION` = 3（Android は 0 と 1 だけ）、Notification のエラーの 16〜20（`WRONG_THREAD`、`ATTACHMENT_LOAD_FAILED` など）、`NTK_NOTIFICATION_EVENT_KIND_TEXT_INPUT` = 3（Android は 0〜2 だけ）
  - **Android にあって iOS に無い名前もある**: Notification のエラーの 6（`CANCELED`）、7（`CANCELED_BY_SYSTEM`）、9（`HOST_START_FAILED`）、11〜14（`EXACT_ALARM_NOT_ALLOWED`、`RESOURCE_NOT_FOUND`、`STORAGE_FAILED`、`SERVICE_START_NOT_ALLOWED`）。Android と共通の名前（0〜5、8、10、15、`NTK_SHARE_ERROR_NOT_FOREGROUND` = 6 など）は同じ値
  - **Windows とは同じ名前で値が違うものがある**: `NTK_DIALOG_ERROR_CANCELED`（Windows 2、iOS 6）、`NTK_NOTIFICATION_ERROR_INVALID_PARAMETER`（Windows 7、iOS 1）、`NTK_CLIPBOARD_ERROR_CANCELED`（Windows 15、iOS 27）
  - Android の `Runtime/Android/` と Windows の `Runtime/Windows/` の宣言を流用しない
- `DllImport("__Internal", CallingConvention = CallingConvention.Cdecl)`（今の iOS の包みと同じ。`NTK_CALL` は iOS では空）
- 列挙は `typedef int32_t` と無名の `enum`。C# では `int` か `enum : int`。**列挙は増えうる**ので、`switch` に既定の枝を書く（ヘッダーの冒頭のコメント）。ビットの組（`ntk_clipboard_patterns`（`typedef uint32_t`。`NTK_CLIPBOARD_PATTERN_*`）、`NTK_NOTIFICATION_AUTH_*`、`NTK_NOTIFICATION_CALENDAR_*`、`NTK_NOTIFICATION_ACTION_*`、`NTK_NOTIFICATION_CATEGORY_*`）は `uint`
- 真偽値は `int32_t`（C# の `bool` にしない。`int` で受けて 0 / 非 0）
- 構造体は `#pragma pack(push, 8)` の LP64 の配置。先頭は `uint32_t struct_size` と `uint32_t reserved0`。**`struct_size` には `Marshal.SizeOf<T>()` を入れ、ほかは 0 で埋める**（0 で埋めた構造体が既定値。E-9）。`reserved*` が 0 でなければ `INVALID_PARAMETER`。配列の要素（`ntk_share_item`、`ntk_notification_action` など）も各自の `struct_size` を持ち、同じ配列の要素は同じ大きさ（P2-5）
- **C# の `Marshal.SizeOf` と `Marshal.OffsetOf` を、`ios/IosLibraryCApiTests/StructLayoutTests.m` の値と EditMode のテストで照らす**（Android の 2c と同じ）。この値は手で付録 A から求め、C のコンパイラーが 3 つのスライスで `_Static_assert` で確かめている
- 文字列は NUL で終わる UTF-8。不正な UTF-8 は `INVALID_PARAMETER`。`NULL` と `""` は区別される（Dialog の文言の `NULL` は既定の文言、`title` などの `NULL` は「無い」。P2-22）。出力の不正なサロゲートと U+0000 は U+FFFD
- **版の確かめ**: 最初の呼び出しの前に `ntk_version()` を iOS の期待値と比べる（`(v >> 16) == 2`）

### 4.4 差し替え型の受け手（第 1 部 C-7）

- 今のブリッジの `setNotificationActionReceivedCallback`、`setNotificationTextInputActionReceivedCallback`、`clipboardStartObserving` の `changeCallback` は差し替え（static の上書き）。C ABI は足す・外す形で、受け手を複数持てる
- 包みは**種類ごとに 1 つのハンドルと「今のハンドル」の印**を持つ。差し替えでは、古いハンドルを `_listener_remove` で外してから新しいものを足し、印を新しいものにする。**配送を受けたら、それが今のハンドルへの配送でなければ捨てる**。判定のために、登録ごとに別の `user_data`（4.2）が要る。iOS の Unity は main で受けるので、判定は受けたその場でよい（C-7）
- Notification: 今の 2 つの受け手（アクションとテキスト入力）は、C では **1 つの `ntk_notification_add_interaction_listener`** にまとまり、`ntk_notification_interaction_kind` が返す `ntk_notification_event_kind` で分かれる（`NTK_NOTIFICATION_EVENT_KIND_BODY_TAP` = 0、`_ACTION` = 1、`_DISMISS` = 2、`_TEXT_INPUT` = 3。NULL には -1。P2-18）。`TEXT_INPUT` でないものを今の `NotificationActionReceived` へ、`TEXT_INPUT` を `NotificationTextInputActionReceived` へ写す（8.3 の NT-20・NT-21）。今の `IosNotificationManager.Initialize()` は公開で「やり直すときに呼ぶ」とあるので、2 回目の `Initialize()` は差し替えとして扱う
- Clipboard: 開始（`ntk_clipboard_start_observing_async`）と受け手（`ntk_clipboard_add_change_listener`）が分かれた（P2-16）。今の `StartObserving` は「登録して開始する。前の登録を外す」（8.3 の CL-13）
- 2 回目の差し替えの後に前の受け手へ届かないことを、Unity のテストで確かめる

### 4.5 振る舞いを保つための包みの仕事（第 2 部 16 章、8.3）

| 事柄 | 包みがすること |
|---|---|
| 解除の副作用（P2-17） | `ntk_*_listener_remove` は登録を外すだけで、監視は止めない。今の `clipboardStopObserving` の振る舞いは `ntk_clipboard_stop_observing_async`（CL-14）で保つ。受け手を外すだけの場面（差し替え、`OnDestroy` など）で監視も止めたいなら、包みが続けて止める |
| `NOT_FOREGROUND` | **Dialog（DL-01〜DL-06）・Share（SH-01）・通知の設定の画面（NT-15）・未決の権限の要求（NT-13）を、アプリが後ろにいるときに呼ぶと、完了が `NOT_FOREGROUND` で来る**。今は Dialog と Share は `.firstActiveScene` で探して失敗の文言、設定の画面は OS が黙って止める。今の失敗のコールバックに写すか、新しいエラーとして出すかは 5 章。起動の途中（`didFinishLaunching` まで）は scene が前面に無いので、ここで呼んでも `NOT_FOREGROUND` になりうる |
| 値の補正と代わりの値（P2-15） | **C ABI も包みも補正を持たない**。エラーを今の失敗のコールバックに写し、2.0.0 の破壊的変更として移行ガイドに書く。今は通って C ではエラーになる値は 8.3 の NT-02 の一覧（不正な trigger、空の `id`、負の `badge`、0〜1 の外の `relevanceScore`、`file://` でない添付、項目の無い calendar、範囲外の location と空の識別子、入ると出るの両方が知らせない組、オブジェクトでない `userInfo`。範囲外の `timeInterval` は今はプロセスが落ち、C では `INVALID_PARAMETER`）。Base64 と文字列の列挙（Clipboard のパターンの文字列 → `NTK_CLIPBOARD_PATTERN_*` のビット、認可の状態の列挙 → 今の文字列など）は包みが写す |
| 回数が変わるコールバック | Dialog は外から閉じたとき（scene が切れて ViewController が解放された）に `CANCELED_BY_SYSTEM` で来る（今は 0 回）。`registerNotificationCategory`（NT-17）は書き込みと 1 回の読み返しの後に来る（今は入口の中で成功）。`hasNotificationPermission`（NT-19）は重ねても要求ごとに 1 回来る（今は static の上書きで前の受け手に来ない）。**入口で拒むと完了は来ない**: 今のブリッジは不正な要求も必ずコールバックに返していた。包みは戻り値が `NONE` でなければ、**main に積んで（今と同じく次の `Update` で）今のコールバックを失敗で呼ぶ**（8.3 の「どの行にも共通する違い」。そのときも `release` は呼び出しの中で来る） |
| 文言のエラー | C ABI は整数の値だけを返し、文言はログに出す。今の文言（Clipboard は `errorCode` の文字列も）は包みが値から写す。Clipboard は第 2 部 11.3 の表を逆に使う（`CANCELED` → `CLIPBOARD_CANCELLED`、`INVALID_URI` → `CLIPBOARD_INVALID_URL`、`INVALID_PARAMETER` → `CLIPBOARD_INVALID_REQUEST`）。今の Clipboard の JSON の失敗の `error.details`（domain と code）は保てない（`system_code` は常に 0。D-13） |
| コールドスタート | `.mm` が起動の中で `ntk_notification_install` を呼ぶ（3.4）。**受け手を登録する前の通知のタップ（コールドスタートを含む）が、登録した時点で最大 32 件まとめて届く**（今は失う。NT-20、第 1 部 5.12.7）。U-3 では、C# の `Start()` で登録した約 0.44 秒後（最初のフレームの後）に届いた。起動のきっかけの通知は `ntk_notification_interaction_is_launch` が非 0（H2-1: 通知の本体のタップと前面に出すアクションだけで、背景のアクションで起動したときは付かない。**ただし `Notification.h` のコメントのとおり、背景のアクションのすぐ後にアプリを前面に出した場合も数えられることがある**）。`ntk_notification_get_launch_response_async` でも取れる（8.4 で足した）。保った分を今の公開の API で出すか捨てるかは 5 章 |
| 通知パッケージとの共存（H2-3） | Unity の通知パッケージの `AuthorizationRequest` を呼ぶと、パッケージが delegate を入れ直し、その後のライブラリの通知が失われる（U-4）。**包みは、パッケージの `AuthorizationRequest` を呼んだ後に `ntk_notification_install` をもう一度呼ぶ**（C# は main で動くので呼べる。入れ直して `NONE`）。パッケージの既定の起動の時の要求（`RequestAuthorizationOnAppLaunch`）は入れ直さない。マニュアルにも書く |
| 権限が無いときの通知（P2-10、P2-27） | `ntk_notification_show_async`・`update_async`・`schedule_async` は、権限が `authorized`・`provisional`・`ephemeral` のどれでもなければ、追加せずに `PERMISSION_DENIED` で完了する（今は黙って成功し、pending に残らない）。今の成功に写すかを 5 章で決める（今は `notDetermined` の即時の分だけ配信済みに載るので、完全には同じにならない）。権限の要求は、拒否されても `NONE` で `granted == 0`（NT-13: 今の `(false, "Notification permission was denied.")` に写す）。既に決まった状態では OS に求めず今の状態で答える。**既に権限を決めたアプリ（1.x から上げたアプリを含む）は、`ntk_notification_request_permission_async` で `NTK_NOTIFICATION_AUTH_PROVIDES_APP_SETTINGS` を足せない**ので、設定の要求のイベント（`ntk_notification_add_settings_request_listener`）が要るなら `.mm` が `requestAuthorization` を呼ぶ。`PROVISIONAL` の選択肢は 2.0.0 では無い |
| 通知のビルダー | `ntk_notification_content_create` で作り、`ntk_notification_content_set_*` で値を入れる。**setter も戻り値でエラーを返す**: `ntk_notification_content_set_user_info_json`（`null` を含む JSON、予約のトップレベルのキー `"com.jonghyunkim.nativetoolkit"`）、`ntk_notification_content_set_badge`（-1 より小さい値。-1 は「設定しない」）、`ntk_notification_content_set_relevance_score`（0.0〜1.0 の外）。**setter の戻り値も今の失敗のコールバックに写す**。添付（`ntk_notification_content_add_attachment`）のファイルは通知を足すときに OS が動かすので、**同じビルダーを 2 回使うと `NTK_NOTIFICATION_ERROR_ATTACHMENT_LOAD_FAILED` になる**（`Notification.h` のコメント）。**ビルダーは呼ぶたびに作り、使った後に `ntk_notification_content_free` で解放する** |
| Dialog の値 | 結果の値（`ntk_dialog_result_button` と各文字列）を今の `(buttonText, isSuccess, errorMessage)` に写す（DL-01〜DL-06）。テキスト入力とログインの「空なら押せない」は、**ブリッジの `enableConfirmWhenEmpty` / `enableLoginWhenEmpty` の真偽を反転して、C の `confirm_disabled_when_empty` / `login_disabled_when_empty` に渡す**（P2-22。非 0 で入力が要る）。アクションシートの文言の `NULL` は既定か「無い」で、今の空文字の見た目は保たない（DL-04） |
| 一括の取り消し（CL-12） | C に一括の取り消しは無い。包みが未完了の読み込みの ID を覚えて `ntk_clipboard_cancel_load` で 1 つずつ取り消し、**main に積んで（今と同じく次の `Update` で）今のコールバックを成功で呼ぶ**。今の順序（一括の完了が先）は約束しない |
| ログ | C ABI はパスワード・入力・クリップボードの本文などを伏せる（P1-18）。包みの C# のログも、今の規則のまま秘密の値を出さない |

### 4.6 雛形との違い（1a の 2 回目の申し送りの雛形を触った人へ）

- `ntk_probe_*` は無い。名前は `ntk_notification_*` になった（例: `ntk_probe_notification_add_listener` → `ntk_notification_add_interaction_listener` と `ntk_notification_add_settings_request_listener` の 2 つ、`ntk_probe_notification_listener_remove` → `ntk_notification_listener_remove`、`ntk_probe_notification_get_launch_response` → `ntk_notification_get_launch_response_async`、`ntk_probe_notification_request_permission` → `ntk_notification_request_permission_async(options, ...)`）
- 雛形の 1 つの受け手を `event_kind` で分けていたものは、本体のタップ・アクション・dismiss・返信（`ntk_notification_interaction_fn`、種類は `ntk_notification_interaction_kind`）と、設定の要求（`ntk_notification_settings_request_fn`）の 2 つの受け手に分かれた
- `Notification.h` のエラーの 6（`CANCELED`）と 7（`CANCELED_BY_SYSTEM`）は無い（欠番。P2-10）。`WRONG_THREAD` は 16 のまま
- `ntk_notification_install` の名前と契約は雛形と同じ

### 4.7 JSON（機能ごとに違う）

今の公開の API を読んだ結果（`1c246a3`）:

| 機能 | 今の公開の API | 2.0.0 |
|---|---|---|
| Notification | `ShowNotification(string contentJson, string? triggerJson, ...)`、`ScheduleNotification`、`UpdateNotification`、`RegisterCategory(string categoryJson, ...)` が JSON の文字列を受け、`GetScheduledNotifications` / `GetDeliveredNotifications` が JSON の文字列を返す。`IosNotificationJsonBuilder` は payload から JSON を作る補助 | **公開の JSON を解く処理は包みに残り**、解いた値をビルダー（`ntk_notification_content_create` と `_set_*`）と構造体（`ntk_notification_trigger`、`ntk_notification_category`）に写す。一覧はハンドル（`ntk_notification_list_*`）から今の JSON を作る（NT-11・NT-12。日時は Unix ミリ秒から小数秒なしの ISO 8601）。userInfo だけは C でも JSON の文字列（`ntk_notification_content_set_user_info_json`、`ntk_notification_interaction_user_info_json`） |
| Clipboard | `Copy(IosClipboardContent, IosPasteboardScope?, IosClipboardCopyOptions?, ...)` など型のある payload を受け、型のある結果（`IosClipboardReadResult` など）を返す。JSON はブリッジとの内部のやりとり（`IosClipboardJsonBuilder` で作り、`IosClipboardJsonParser` / `IosClipboardJsonReader` で解く） | 書き込みは payload から C の構造体（`ntk_clipboard_write_content` など）へ直接写す。読み取りの JSON の解析は、C のハンドルの読み取り（`ntk_clipboard_read_result_*`、`ntk_clipboard_snapshot_*`、`ntk_clipboard_loaded_item_*`、`ntk_clipboard_change_*`）に置き換わる。**例外は `DetectValues`**: `ntk_clipboard_detect_values_async` の完了（`ntk_clipboard_values_fn`）は JSON の文字列（`ntk_string* values_json`。封筒の無いオブジェクト。8.3 の CL-10、P2-8）を返すので、**JSON から `IosClipboardDetectedValues` への解析は残る**（今の `IosClipboardJsonParser.ParseDetectedValuesResult` の中身。封筒を付けるか、封筒なしで解くように直す）。受けた `ntk_string*` は `ntk_string_free` で解放する。ほかに包みが写すもの: **CL-02**（`Append` に `options` が無い。C の `ntk_clipboard_append_async` は `options` の引数を持たない）、**CL-08**（`RemovePasteboard` の scope は省けない。C も省略を受けない）、**CL-09**（パターンの列挙を `ntk_clipboard_patterns` のビットに写す。未知の値は `INVALID_REQUEST`） |
| Share | `Share(IosShareContentPayload?, ...)`。`IosShareJsonBuilder` で JSON にしてブリッジに渡す | payload から `ntk_share_request` と `ntk_share_item` の配列へ直接写す |
| Dialog | 引数そのまま（JSON は無い） | 構造体（`ntk_dialog_*_request`）に写す |

**第 2 部の 8.3（CL-01・CL-03〜CL-05・CL-07・CL-10・CL-11・CL-15・SH-01 の「JSON を解いて」「今の JSON を作る」）と 16 章の JSON の文言は、ブリッジの JSON の形を包みの中で保つ前提で書いた。Clipboard と Share の公開の API は JSON を受けない（型のある payload を受け、型のある結果を返す）ので、この 2 つでは上の表を優先する**（Android の 2c の申し送りのレビュー H2-C3 と同じ）。ただし Clipboard の `DetectValues`（CL-10）だけは C でも JSON なので、8.3 の文言がそのまま当たる。保つのは、今の公開の API の振る舞い（どの値が返るか、どの失敗の文字列になるか）で、8.3 の列のとおり。

**型の公開の範囲**（`1c246a3`）: `IosClipboardJsonBuilder`、`IosShareJsonBuilder`、`IosNotificationJsonBuilder` は `public`。`IosClipboardJsonParser` と `IosClipboardJsonReader` は `internal`。**公開の Builder を互換のために残すか**（利用者のコードが呼んでいるかもしれない）と、**内部の Parser / Reader をどこまで残すか**（`DetectValues` の解析と、Notification の公開の JSON を解くのに JSON の読み手が要る）は別の判断（5 章）。

### 4.8 第 2 部 16 章の各行の受け先

| 16 章の行 | この文書 |
|---|---|
| 対応表 | 2 章（8.3）、4.5、4.7 |
| EditMode の JSON のテスト | 6 章 |
| コールバックの例外 | 4.2 |
| 差し替え型の受け手 | 4.4 |
| 解除の副作用 | 4.5 |
| `NOT_FOREGROUND` | 4.5 |
| 値の補正と代わりの値 | 4.5 |
| 回数が変わるコールバック | 4.5 |
| コールドスタート | 3.4、4.5 |
| 2 回目の申し送りの雛形との違い | 4.6 |
| 権限が無いときの通知 | 4.5 |
| C# のバインディング | 4.3 |

## 5. 2c で決めること

| 事柄 | 選択肢 | 推奨 |
|---|---|---|
| `.mm` を入れるかを利用者が選べる設定 | Project Settings の項目 / スクリプトの定義シンボル / 既定で入れて外す手順だけを書く | 既定は「入れる」（入れないと前面の通知の表示もコールドスタートのタップも失う）。外す設定を持ち、外したときは `ntk_notification_install` を自分のネイティブのコードで呼ぶ契約（README 3.1）をマニュアルに書く。今のビルドの処理（`PostBuildProcessor`）は `defineConstraints: ["NATIVETOOLKIT_ENABLE_BUILD_STEPS"]` の asmdef にあり、ふつうの利用者のビルドでは動かない（3.3）。**`.mm` を入れる・外す処理と、xcframework を入れる PBXProject の処理は、この条件の付いた asmdef の外に置く**（Android の 2c の 3.3 と同じ注意） |
| Unity の通知パッケージとの順 | `.mm` は `didFinishLaunching`（H2-2。決まり）。パッケージの `AuthorizationRequest` の後の入れ直し（H2-3。決まり）を、包みのどこで行うか | パッケージの API を包む口を持たないなら、マニュアルで利用者に `ntk_notification_install` を呼ぶ包みの関数（例: `IosNotificationManager` の再インストールの口）を案内する |
| xcframework の入れ方 | PostProcessBuild の PBXProject の API（1a の形）/ `PluginImporter` の設定 | 1a で動いた PBXProject の形（3.3 の表）。`UserNotifications.framework` を UnityFramework に足すことを忘れない |
| xcframework の版の固定 | 今の前方一致と辞書順の最大 / `VERSION.txt` で完全なファイル名 | Android と Windows と同じく `Plugins/iOS/VERSION.txt` で、2 つの xcframework の完全なファイル名で固定する（README 5 章の 1・2） |
| `.mm` の置き場所 | パッケージの `Plugins/iOS/` / ビルドの処理が書き出した Xcode のプロジェクトに写す | 設定で外せる形を選ぶ |
| `NOT_FOREGROUND`、`PERMISSION_DENIED` の写し方 | 今の失敗のコールバックに写す / 新しいエラーとして出す / 今の成功に写す（`PERMISSION_DENIED`） | 8.3 の列のとおりに保ち、保てないもの（`NOT_FOREGROUND` が来ること、`PERMISSION_DENIED` の扱い）は移行ガイドに書く（第 1 部 AC-23 の原則） |
| 保ったイベントとコールドスタートのタップ | 今の `NotificationActionReceived` に流す / 捨てる / 新しい口（起動のきっかけ）で出す | 8.3 の NT-20 は「保った分を捨てるかは 2c で決める」 |
| 公開の Builder（`IosClipboardJsonBuilder`、`IosShareJsonBuilder`、`IosNotificationJsonBuilder`） | 残す（互換） / 消す（破壊的変更として移行ガイドに書く） | 4.7。Android の 2c の決め方に合わせる |
| 内部の `IosClipboardJsonParser` / `IosClipboardJsonReader` | `DetectValues` と Notification の JSON の解析に要る分だけ残す / 消す | 残す分を決めてから、6.2 のテストの移し先を決める |
| 名前空間とフォルダ | 今の `Runtime/<Feature>/Ios*.cs` / Android と Windows と同じ `Runtime/Ios/<Feature>/` | Android と Windows に合わせる |
| 1.x の Swift の `IosNotificationManager.setup()` を呼ぶ利用者のネイティブのコード | - | `unity-native-plugin` の側にあれば、`ntk_notification_install` に置き換える |

## 6. テスト

### 6.1 今の iOS の EditMode のテストの数（読むだけで数えた）

数えた所: `unity-native-plugin` の `1c246a3`（`feature/UNT-14`、2026-10-31 のコミット。作業ツリーの未コミットの変更は `Assets/Settings/UniversalRenderPipelineGlobalSettings.asset` と `unity-native-plugin.slnx` の 2 つで、テストのファイルは変わっていない）。EditMode のテストは `Packages/com.jonghyunkim.nativetoolkit/Tests/Runtime/`（asmdef は `NativeToolkit.Runtime.Tests.asmdef`、`includePlatforms: ["Editor"]`）。そのうち `Ios*.cs` の 10 ファイル。

数え方: ファイルごとに `grep -cE '^\s*\[Test(\]|,|\()'`（`[Test]` の属性の行）。iOS のファイルには `[TestCase]`、`[TestCaseSource]`、`[UnityTest]`、`[Ignore]`、`[Explicit]` が 1 つも無いので、メソッドの数とケースの数は同じ。1 行に属性が 2 つ並ぶ所も無い。Unity は動かしていないので、Test Runner に出る数は確かめていない。

| ファイル | 件数 | JSON |
|---|---|---|
| `IosClipboardJsonParserTests.cs` | 46 | ○ |
| `IosClipboardJsonReaderTests.cs` | 34 | ○ |
| `IosClipboardJsonBuilderTests.cs` | 30 | ○ |
| `IosShareJsonBuilderTests.cs` | 16 | ○ |
| `IosClipboardResultTests.cs` | 21 | |
| `IosClipboardManagerDispatchTests.cs` | 17 | |
| `IosClipboardSampleStateTests.cs` | 29 | |
| `IosClipboardSampleSceneWiringTests.cs` | 7 | |
| `IosShareManagerDispatchTests.cs` | 6 | |
| `IosShareResultTests.cs` | 6 | |
| 計 | **212** | **126** |

- **JSON の組み立てと解析のテストは 126 件**（4 ファイル）で、第 1 部の時点の数（README 8.6、知見 3 章）と同じ。4 ファイルを最後に変えたコミットは `163ee30`（2026-08-22）
- **Notification と Dialog の EditMode のテストは無い**（`IosNotificationJsonBuilder` のテストも無い）
- PlayMode（`Tests/PlayMode/`）の iOS は `IosClipboardManagerIntegrationTests.cs` 31 件と `IosShareManagerIntegrationTests.cs` 5 件（`[UnityTest]` の属性の行を数えた。JSON は扱っていない）

### 6.2 2c で何を基準にテストするか

| 種類 | 今 | 2c |
|---|---|---|
| EditMode の JSON（126 件） | ブリッジとの JSON の形を作る・解く | 下の 6.3 のとおり、テストごとに残る・移す・書き直す。**基準は第 2 部 8.3 の「Unity の包みが保つこと」の列**: payload から C の構造体への写し（Clipboard の CL-01〜CL-15、Share の SH-01）、C のハンドルから今の結果の型への写し、`DetectValues` の JSON の解析（CL-10）、エラーの値から今の文字列への写し（4.5 の「文言のエラー」）、入口で拒んだときに今のコールバックが失敗で来ること。Notification は公開の JSON の解析と、解いた値からビルダー・構造体への写し（NT-02〜NT-04、NT-17。setter のエラーを含む）、一覧の JSON（NT-11・NT-12）を新しく足す |
| EditMode のほか（86 件） | 結果の型、dispatch、サンプル | 結果の型と公開の API が変わらなければ残る。dispatch のテストは、`user_data` の表と `release` の 1 回（4.2）、差し替え（4.4）に合わせて直す |
| 足すもの | - | 構造体の配置（`Marshal.SizeOf` / `OffsetOf` と `StructLayoutTests.m`。4.3）、要求の ID が `ulong` であること、`ntk_version()` の期待値、Dialog の真偽の反転（4.5） |
| Editor の PlayMode（36 件） | Clipboard と Share の manager の状態の流れ。ネイティブの呼び出しは Editor では空になり、テストが `Complete*ForTests` の口で結果を渡す（`IosClipboardManagerIntegrationTests` の冒頭のコメント） | C ABI の包みに合わせて直す。Editor では C ABI を通らないので、`user_data` の表、差し替え（4.4）、入口で拒んだとき（完了が来ず `release` だけ）は、同じくネイティブの代わりを差し込める口で確かめる |
| iOS の Player の PlayMode（IL2CPP で C ABI を通す。シミュレーターか実機） | 無い | 4 機能を C ABI を通して呼ぶ。`ntk_version`、差し替え型の受け手、入口で拒んだとき、`release` が 1 回来ること、例外を投げる受け手を try / catch が止めること |
| 実機 | - | **実機は持ち主の私物。流す前に毎回許可を得る**（`agent-rules/device-testing.md`。削除・権限のリセット・設定の変更・クリップボード・Share・通知センターに触れる操作も毎回聞く）。`.mm` の入れ方とコールドスタートのタップ、通知パッケージとの共存（H2-2・H2-3）、Release のアーカイブで 2 つの framework がアプリの証明書で署名し直されていること（D-18。1a-4） |

### 6.3 126 件の行き先（テストの名前から分けた目安）

| ファイル | 残る・移す | 書き直す（JSON の形が無くなる） |
|---|---|---|
| `IosClipboardJsonParserTests`（46） | **移す 4**: `ParseDetectedValuesResult_*` の 4 件（`DetectValues` の JSON の解析は残る。封筒の扱いだけ直す） | 42: 封筒（E1〜E10、`ErrorEnvelope_*`）、Read・ReadData・Snapshot・PasteboardScope・DetectedPatterns・LoadedItem・ForegroundChange・ChangeEvent の解析。C のハンドルから結果の型への写しのテストとして書き直す（8.3 の CL-03〜CL-05、CL-07、CL-09、CL-11、CL-13、CL-15） |
| `IosClipboardJsonReaderTests`（34） | **残る 20**: JSON の読み手（`Parse_*`、`TryGet*`）。Reader を `DetectValues` と Notification の JSON の解析に残すなら残る | 14: Base64（`TryGetDecodedLength_*` 5、`TryGetBase64Bytes_*` 9）。C は `ntk_bytes` で返すので Base64 の解き方は要らなくなる |
| `IosClipboardJsonBuilderTests`（30） | **残る 4**: payload の型の入口の検査（`Scope_BlankName_ThrowsAtTheCallSite`、`Color_NonFiniteComponent_ThrowsAtTheCallSite`、`ContentFactories_NullArguments_Throw`、`CopyOptions_PrivacyPreservingDefault_KeepsContentOffUniversalClipboard`） | 26: JSON の形。payload から C の構造体への写しのテストとして書き直す（期限の UTC の変換、`localOnly` の既定、`Append` が `options` を持たないこと（CL-02）、パターンのビット（CL-09）など） |
| `IosShareJsonBuilderTests`（16） | 0 | 16: payload から `ntk_share_request` / `ntk_share_item` への写しとして書き直す（`null` の項目を除く、空白だけの件名を省く、など今の振る舞い） |

- 分けたのはテストの名前からの目安で、中身は読んでいない。「残る」は、Builder・Reader をどこまで残すか（5 章）で変わる

- **最初に確かめること**: `ntk_version()` が `0x020000` を返すこと、2 つの framework が Embed & Sign で入って起動すること、`.mm` が `didFinishLaunching` で `NONE` を返すこと
- 移す前の結果を基準として記録しておく（Android・Windows の移行と同じ）

## 7. 2c で使う配布物と、このリポジトリの側で確かめていないこと

### 7.1 配布物

- **`dist/<リリース版>/ios/` はまだ無い**（`dist/` の最新は `1.13.0` で、iOS は 1.3.0）。版と `dist/<リリース版>` は 2b の締めで持ち主が決める（README 5 章の 2b の行。Android が 2c の前に `dist/1.13.0` を作ったのと同じ）。dist を置く前に、3.3 の README 5 章の 3 つが `unity-native-plugin` で済んだことを確かめる
- 2b の締めの前に試すなら、配布物は次で作れる（このリポジトリで。`dist/` にも `ios/` の `project.pbxproj` にも書かない）:

```sh
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer \
scripts/build_ios_library_xcframework.sh -m IosLibrary -m IosLibraryCApi -v 2.0.0 \
    --output-dir <出力先> --build-dir <作業フォルダー> --keep-project-versions
python3 scripts/check_ios_dist.py --dist <出力先>
```

  **capi は `@c @implementation`（Swift 6.3、Xcode 26.4 以上）を使うので、Xcode 26.3 では組めない**。スクリプトは `DEVELOPER_DIR` が無ければ `xcode-select` の Xcode を使い、この手元の既定は 26.3 なので、`DEVELOPER_DIR` で 26.6 を指す（道は手元の置き場所に合わせる）。`--output-dir` には 2 つの xcframework と `include/NativeToolkitC/` ができる。`--output-dir` を付けないと `dist/<-v の版>/ios/`（`dist/2.0.0/ios/`）にでき、`--keep-project-versions` を付けないと `ios/` のプロジェクトの版とビルド番号を書き換える。リリースの形（`dist/<リリース版>/ios/` に出す旗の組）は 2b の締めで決める（作業記録 14.7 の 1。持ち主の確認待ち）

### 7.2 確かめていないこと（2c に効くもの）

| 事柄 | 状態 |
|---|---|
| **実機** | **実機は持ち主の私物で、流す前に毎回許可を得る**（`agent-rules/device-testing.md`）。**段階 2 の C ABI は、実機では何も流していない**。実機の ASan と smoke は 2b の区切りで、持ち主の許可を得て流す（第 2 部 15.2）。実機で通ったのは 1a の雛形（U-1〜U-10、iPhone XS / 18.7.2）だけ |
| 署名 | 実機向けの smoke は署名なしで組んだだけ。署名して入れる手順は 2b の区切りで決める。配布用の署名（Distribution のアーカイブ、Validate App）は 1a でも確かめていない（U-2 は開発用の署名だけ）。Release のアーカイブでの署名し直し（1a-4）は `unity-native-plugin` の agent に任せた確かめ。アーカイブのプライバシーのレポート（MS-10）も未 |
| `dist/<リリース版>` の形 | `check_ios_dist.py` は `--dist`（任意のフォルダー）の形だけを流した。`<release>` の形（`dist/<release>/ios/` を読む）は流していない |
| x86_64 | `IosLibraryCApiTests` は iPhone 16 / 18.3 の x86_64 で 473/474。`OSLogStore` を読む 1 件（`testAMismatchIsLoggedOnceAndStopsNothing`）が x86_64 だけで落ちる（ライブラリはログを出しているが、x86_64 では `OSLogStore` が 0 件を返す。持ち主の判断待ち。作業記録 15.9）。x86_64 の ASan・TSan は流していない。Unity の x86_64 のシミュレーターでの実行は確かめていない |
| シミュレーターの機種 | 第 2 部 15.2 の iPhone 17 / 26.2 は iPhone 17 Pro / 26.2 で代えた（持ち主の確認待ち）。iPad Pro 11-inch (M4) / 18.3 でも流した |
| 通知の `DISMISS` と `openSettingsFor` | UI テストは TB-10 で推奨案で進めた（持ち主の確認待ち）。`openSettingsFor` が設定の App を辿るのは iOS 26.2 のシミュレーターだけ |
| 本物のサニタイザーの報告で落ちること | 見ていない（報告の形を偽って確かめた） |
| smoke の Dialog | 完了が `CANCELED`（表示の 1.5 秒後の取り消し）で来たことまでで、画面に出たことは見ていない |
| 起動の早い時期 | `UIApplicationMain` の前に `ntk_notification_install` を呼んだときは契約の外で、確かめていない（第 1 部 1.3.3）。`.mm` は `+load` で登録だけをし、呼ぶのは `didFinishLaunching` にする |
| Distribution のアーカイブと Validate App | README 9 章の DoD の項目。**誰がいつ行うか（`unity-native-plugin` の agent か、2b の締めか、リリースの前か）は持ち主の決定待ち** |
| 配る `IosLibrary`（と、もう組まない `UnityIosPlugin`）を署名しないこと | 推奨案で進めた。持ち主の確認待ち（作業記録 14.7 の 2）。1.x の配布物の中の framework は署名されていた |
| `unity-native-plugin` の側の事実 | この文書の `unity-native-plugin` の記述（公開の API の形、ビルドの処理、テストの数）は `1c246a3` を読んだもので、向こうの作業中のブランチの先は見ていない。Unity の Test Runner に出る件数は確かめていない（ソースの属性を数えただけ）。3.3 の入れ方は 1a の使い捨てのプロジェクトの写しで、`unity-native-plugin` のパッケージを通した形は誰も確かめていない（作業記録 16.4） |
| 複数の window の iPad | 前面の探し方はどちらかの window を選び、どちらに出るかは決まらない（README 3.1、P1-11 の C）。C ABI に表示元を渡す口は無い |

## 8. 問い合わせ

対応表（第 2 部 8.3）の読み方や、C ABI の振る舞いの疑問は、`native-toolkit` の `artifact/topics/ios-c-abi/` の設計書を見て、足りなければこのリポジトリに課題として返す。C ABI の側を直すときは、2b と同じく設計書を直してから実装する。2c の結果は、1a と同じく `results/` に写しを置き、第 2 部に反映する。
