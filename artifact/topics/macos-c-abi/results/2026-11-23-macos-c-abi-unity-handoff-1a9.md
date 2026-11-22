# macOS の C ABI: `unity-native-plugin` の agent への申し送り（1a-9）

- 記録日: 2026-11-23（下書き。レビュー v1〜v3 を反映: `../reviews/2026-11-23-macos-c-abi-unity-handoff-1a9-review-v1.md`、`-v2.md`、`-v3.md`）
- 宛先: `unity-native-plugin`（別のリポジトリ）の agent
- 出した側: native-toolkit の `artifact/topics/macos-c-abi`（ブランチ `feature/NTKIT-19`。雛形のソースはこのブランチにコミット済み・push 済み）
- 範囲: 決定の文書（`plans/2026-11-22-macos-c-abi-decisions.md`）8.2 の **1a-9**（「前」の印。0e の前に終える）。下の 4 章で M-1〜M-12 に分けた
- 読むもの: 決定の文書の D-4・D-6・D-7・D-8・D-9〜D-11・D-18・D-24 と 8.2 の 1a-9、作業の記録（`results/2026-11-22-macos-c-abi-stage0a-working-notes.md`）の 2 章（1a-6）・3 章（1a-7）・5 章（1a-8: 通知の起動の順）、`agent-rules/device-testing.md` の macOS の節、iOS の 1 回目の申し送り（`artifact/topics/ios-c-abi/results/2026-10-31-ios-c-abi-unity-handoff-1.md`）の 3 章（C# の約束は同じ）
- 前提: あなたのリポジトリの `artifact/topics/macos-c-abi-handoff/README.md` の直し（`VERSION.txt` で名前を固定、`ditto` のコピー、書き出しの後の symlink の作り直し、`.xcodeproj` とターゲットの探し方）が入っていること
- この確かめで決まらないもの: **D-6 の「別のスレッドから呼んだときの完了と、呼び出し元のその後の処理との順」は確かめない**（契約は 3 章のとおり、並んで走りうる）。**D-7（ホストの delegate との共存と `launch_response` の定義）は 1a-9 では決まらない**。雛形の proxy は iOS の `NotificationDelegateRouter` と同じ転送（`CompletionOnce`、`nil` の設定の転送、循環の防止）にしたが、ホストの delegate を置いた転送の確かめは M-n に無い。M-7 の起動の順は 1a-8 の材料として記録するだけ。**D-8 も 1a-9 だけでは確定しない**（M-8 は Unity での A' の判断材料。要求ごとの取り消し・ホストのモーダルを閉じないこと・同じ回の 2 つ目・ファイルのパネルは、第 1 部の前に native-toolkit で測る）

## 0. 最初に読むこと: この Mac は利用者の私物

確かめに使う Mac は試験用の機械ではなく、利用者が今使っている私物の Mac である（macOS 26）。個人のデータ（クリップボード、通知、ファイル、ほかのアプリ、設定）が入っている。**native-toolkit の `agent-rules/device-testing.md` の「利用者の私物の Mac で流すテスト（macOS）」の節を読み、そのとおりにする**。この節は native-toolkit から頼まれた agent にも当てはまる。あなたも同じ Mac で動くので、そのまま当てはまる。要点:

1. **許可なしにしてよいのは、組み立てと読むだけの操作**: `build.sh`、Unity の書き出し（batchmode）、`xcodebuild` の組み立て、`otool`・`nm`・`codesign -dv`・`codesign --verify`・`plutil`・`find`・`pgrep`（試すアプリの名前に絞る）で調べること
2. **組んだアプリを起動する確かめはすべて、利用者に次の 4 つを知らせてはっきり許可を得る**（アプリが前面に出て画面を使う。区分 2・3）。許可は 1 回限りで、次の実行や別の操作に広げない。**1 つの M-n の中の複数の起動（M-5 の 3 つの形など）は、一覧にして 1 回の許可を得てよい。一覧に無い起動はしない**
   1. 流すもの（この文書の M-n と、その中の起動の一覧）
   2. この Mac に起きること（アプリが前面に出る、全画面になる、アラート・共有のピッカーが出る、**通知の許可のダイアログ・バナー・通知センターに項目が増える**、アプリの終了と起動の繰り返し）
   3. 利用者にしてもらうこと（下の準備と、各 M-n の「利用者の操作」の欄。**アラートのボタン・通知のバナーのクリック・アプリの終了・ほかのアプリを前に出すことなど、手でしかできない操作**）
   4. 時間の見込みと始める時刻（その間この Mac は使えない）
3. **1 回ごとに聞く操作**: 通知の許可の変更・リセット（`tccutil` を含む）、システム設定の変更、アプリの削除と LaunchServices の登録の掃除、通知センターの操作、computer use でこの Mac の画面を見ること
4. **共有のピッカーではサービスを選ばない**（メール・メッセージ・AirDrop などの実在のサービスへ送りうる）。雛形の `auto_close_ms` で自分で閉じる。閉じなければ利用者に Esc で閉じてもらう
5. **準備は利用者に頼む**（agent からこの Mac の設定を変えない）: 画面のロックとスクリーンセーバーが始まらないようにする、確かめの間はマウスとキーボードに触れない（各 M-n の「利用者の操作」のときだけ触れる）。通知を出す M-7 では集中モードを入れ、通知を許すアプリを試すアプリだけにする（M-7 の準備）
6. **書かないもの**: この Mac の名前、ユーザー名、ホームのパス、Team ID と証明書の名前（「アプリと同じ / 違う」だけ書く）、ほかのアプリの通知の文字。雛形は describe とログのパスを、`<名前>.app/…`（`.app` で終わる道も）、`…/<名前>.framework/…`、ログインの利用者のホーム（利用者の台帳から取る。sandbox の container を指す `HOME` ではない）の下は `~/…`、ほかは `…/<最後の要素>` の形にしてから返す。C# の例外の行（`exception …`）も、文とスタックの中の絶対パスを同じ形に伏せてから出す。それでも書き写す前に、ユーザー名やホームのパスが無いかを、例外の行も含めて目で確かめる。スクリーンショットと画面の録画は書き写した後に消す。**試すアプリのログのファイル（2 章 6、sandbox の container の中）も、書き写した後に利用者に知らせて消す**。端末のログを読むときは雛形の subsystem（`com.jonghyunkim.nativetoolkit.probe1a9`）と C# の印 `[NTK-1A9]` に絞る
7. **VM を使う場合**: native-toolkit の tart の VM（macOS 15.8.3。`device-testing.md` の「許可なしで流せる VM の条件」を満たす）では、区分 2・3 を許可なしに流してよい。VM の中では XCUITest で通知の許可・バナー・コールドスタート・ピッカー・`NSAlert` を操作できることが分かっている（作業の記録の 4 章）。ただし VM に Unity は入っていないので、この Mac で組んだ `.app` を `ssh` に `tar` を流して写す（`scp -r` は framework の symlink を実体にして署名を壊す）。VM の起動・複製・更新は 1 回ごとに許可が要る。VM を使うかどうかは利用者に尋ねる

## 1. 渡すもの

| もの | 中身 |
|---|---|
| `ntk-probe-mac-1.0.0.xcframework` | `NtkProbeMac.framework`。**`MacLibrary`（Swift の API）の代わり**。決定で `MacLibrary` に置くもの（D-8 の A' の Dialog、main に積む Share、通知の delegate の proxy と起動の記録）を最小の形で持つ |
| `ntk-probe-mac-capi-1.0.0.xcframework` | `NtkProbeMacCApi.framework`。**C ABI の代わり**。`@c @implementation`（Objective-C なし）。`_ntk_*` の 20 個だけを出す。`@rpath/NtkProbeMac.framework/Versions/A/NtkProbeMac` に依存する |
| `include/NativeToolkitC/*.h` | 公開ヘッダー 6 つ（`Common.h`、`Probe.h`、`Dialog.h`、`Share.h`、`Notification.h`、`ProbeNotification.h`）。framework の `Headers/NativeToolkitC/` と同じもの |
| `BUILD-INFO.txt` | 組んだ時刻と commit、Xcode の版、アーキテクチャ、symlink、install name、依存、rpath、署名、書き出しのシンボル |
| `Main.cpp` の見本 | native-toolkit の `artifact/topics/macos-c-abi/results/probes/1a9-unity-handoff/unity/Main.cpp` |
| C# の宣言 | 同じフォルダーの `unity/NtkProbeMac.cs` |
| 雛形のソースと組むスクリプト | 同じフォルダーの `build.sh`、`gen_projects.rb`、`core/`、`capi/`、`smoke/` |

- **置き場**: 上の 4 つ（xcframework 2 つ、`include/`、`BUILD-INFO.txt`）は渡さない。iOS の申し送りと同じく、**そちらで下の手順で組む**（組み立ての物は scratchpad に置くと再起動で消えるため）。雛形のソースは native-toolkit のブランチ `feature/NTKIT-19` にコミット済み（push 済み。`git -C <native-toolkit> log -1 -- artifact/topics/macos-c-abi/results/probes/1a9-unity-handoff` で版を確かめる）
- **形**: スライスは `macos-arm64_x86_64` の 1 つ、最小 macOS 15.0。**署名していない**（D-18。リンカーの ad-hoc の署名だけが本体にある。アプリに埋め込むときに、あなたの側で署名し直される）。どちらも**版付きの framework で、symlink を 5 本ずつ持つ**（`Versions/Current → A`、最上位の本体・`Resources`・`Headers`・`Modules`）。コピーは `ditto` で行う（`cp -R`・`rsync -L` は使わない）
- **install name と rpath**: `@rpath/<名前>.framework/Versions/A/<名前>`。C ABI の rpath は `/usr/lib/swift`、`@executable_path/../Frameworks`、`@loader_path/../../..`（兄弟の framework。D-11）
- **2 つとも同じ組で埋め込む**。C ABI だけでは `NtkProbeMac` が見つからず起動で落ちる
- **これは雛形で、製品ではない**。framework の名前、`ntk_probe_*` の名前と引数、エラーの番号は確かめのためだけのもの。本番は C ABI の設計書の第 2 部で決める。`ntk_notification_install`・`ntk_dialog_show_alert_async`・`ntk_share_show_async` は本番に近い名前だが、引数は雛形のもの
- **組み方**（native-toolkit の作業コピーで。読むだけで、native-toolkit の中には何も書かない。Xcode 26.6 と Ruby の `xcodeproj` gem が要る。`xcode-select` は変えない）:

```bash
cd <native-toolkit>
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer \
  artifact/topics/macos-c-abi/results/probes/1a9-unity-handoff/build.sh <出力のフォルダー>   # native-toolkit の外
artifact/topics/macos-c-abi/results/probes/1a9-unity-handoff/smoke/run.sh <出力のフォルダー>  # 画面を使わない確かめ（区分 1）
```

  `<出力のフォルダー>` にこの 4 つができ、作業の物は `<出力のフォルダー>-work/` に出る（渡さない）。`smoke/run.sh` の最後が `SMOKE PASS` 4 回と `DLOPEN PASS` 2 回であることを確かめる。`BUILD-INFO.txt` の `built` と `commit` を結果に書く。**Unity のプロジェクトを組む側の Xcode は 26.3 以上ならどれでもよい**（C だけを使うので。こちらで 26.3 の clang で C の利用者を組めた。6 章）

## 2. 組み込み方（Unity 6000.4.2f1 の「Create Xcode Project」の書き出し）

あなたの `macos-c-abi-handoff` の直しの形をそのまま使う。M-2（IL2CPP）だけは別のやり方（M-2 の欄）。

1. **試しの dist を作る**: あなたの `probe/stage_a.sh` と同じく、プロジェクトの写しと試しの dist を使い、`<試しの dist>/9.9.9/mac/` に 2 つの xcframework を `ditto` で置く。**native-toolkit の作業コピーの `dist/` には置かない**（本物の配布物の場所）
2. **`Packages/com.jonghyunkim.nativetoolkit/Plugins/macOS/VERSION.txt`**（写しの中）を次にする。`PreBuildProcessor` がほかの xcframework（1.x の `unity-mac-native-toolkit-1.3.0.xcframework`）を消すので、1.x の framework と同じアプリに混ざらない

   ```
   dist_version: 9.9.9
   xcframeworks: ntk-probe-mac-1.0.0.xcframework, ntk-probe-mac-capi-1.0.0.xcframework
   ```

3. **試しの dist を読ませる**（どちらかの経路）:
   - **ビルドの段の経路**: Unity を起こすときの環境に `NATIVE_TOOLKIT_DIST_ROOT=<試しの dist>` を入れる（`PreBuildProcessor` は無ければ隣の `native-toolkit/dist` を読み、`9.9.9` が無くて止まる）。build steps の define（`NATIVETOOLKIT_ENABLE_BUILD_STEPS`）を入れて、`PreBuildProcessor` / `PostBuildProcessor` を走らせる
   - **メニューの経路**（`MacFrameworkPatcher`）: このメニューは dist を読まず、`Plugins/macOS` にある物だけを写す。書き出しの前に 2 つの xcframework を `Plugins/macOS/` に `ditto` で置いてから、書き出しの後にメニューを使う

   この準備が足りずに止まったものは、D-24 の失敗に数えない（`blocked` に書く）
4. Unity 6000.4.2f1 で、Mac Standalone、**Create Xcode Project を入れ、Development Build を外す**（release）、scripting backend は Mono。**書き出すシーンは確かめのシーンだけにする**（写しの `EditorBuildSettings` を書き換えるか、`BuildPlayerOptions.scenes` に 1 つだけ渡す。サンプルのシーンが先に来ると、1.x の `Mac*Manager` が 1.x の `__Internal` を呼んで `EntryPointNotFoundException` になる）。**bundle id は確かめ専用の `com.jonghyunkim.nativetoolkit.probe1a9` にする**（既存の書き出しの `com.jonghyunkim.nativetoolkit.mac` の通知の許可などを引き継がないため）
5. 書き出した `.xcodeproj` で、`PostBuildProcessor`（かメニュー）が 2 つをアプリのターゲット（product name のターゲット）にリンクして埋め込み（Embed & Sign、`CodeSignOnCopy`）、`FRAMEWORK_SEARCH_PATHS` と `LD_RUNPATH_SEARCH_PATHS`（`@executable_path/../Frameworks`）を足し、symlink を作り直したことを確かめる
6. **`Main.cpp`**: 書き出しの `<product name>/Main.cpp`（`main()` が `PlayerMain(argc, argv)` を呼ぶだけ）を、見本の `unity/Main.cpp` に置き換える（または `--- native-toolkit 1a-9 probe ---` の行だけを足す）。形は `NTK_1A9_INSTALL_AT` で選ぶ（ファイルの `#define` か、product name のターゲットの `GCC_PREPROCESSOR_DEFINITIONS` に `$(inherited)` を残して `NTK_1A9_INSTALL_AT=n`）:
   - `0`: 何もしない（通知の install のネイティブの参照が無いホスト。M-4）
   - `1`: `PlayerMain` の前に `ntk_probe_notification_install_at(1)` を呼ぶ。これは起動の記録を始め、`NSApplicationWillFinishLaunchingNotification` の受け手を登録し、通知が来たときに `ntk_notification_install` を呼ぶ（**確かめたい本命の形**）
   - `2`: `PlayerMain` の前に `ntk_notification_install()` を直接呼ぶ（`NSApp` がまだ無い時期。雛形は `NSApp` を作らない）
   - `3`: `1` と同じで `NSApplicationDidFinishLaunchingNotification`（比べるため。1a-8 では `didReceive` は `didFinishLaunching` の約 40 ms 後に来たので、間に合う見込みはある）

   見本は 2 つの関数を `extern "C"` で宣言するだけの素の C++ なので、ヘッダーの検索パスも、システムの framework の追加も要らない
7. **ビルドの印**: product name のターゲットの `Info.plist` に、文字列のキー `NTKProbeBuildToken`（例: `at1-<組んだ時刻>`。形と時刻が分かるもの）を足す。`ntk_probe_describe` が `build-token=` で返すので、どの `.app` が起動したかが分かる（M-5・M-7）
8. **C#**: `unity/NtkProbeMac.cs` を `Assets/` のどこかに置く（`#if UNITY_STANDALONE_OSX && !UNITY_EDITOR` で囲んである。**シーンの側のスクリプトも同じ `#if` で囲む**）。確かめのシーンは自由に作る。要るもの:
   - `Awake` で `NtkProbeMac.RememberMainThread()`、`NtkProbeMac.LogFile = Path.Combine(Application.persistentDataPath, "ntk-1a9.log")`、`NtkProbeMac.Sink` に画面へ 1 行足す関数を入れる。`Update` で毎回 `NtkProbeMac.Pump()` を呼ぶ
   - **`NtkProbeMac.Log` はどのスレッドからでも呼べる**（Unity の API を呼ばない。時刻は `Stopwatch`、フレームは `Pump` が最後に写した値、ファイルへの追記は lock の中、画面へは `Pump` が main で渡す）。シーンの側も、main 以外で `Time`・画面・`Debug.Log` を触らない
   - **ファイルが記録の正**: `PreBuildProcessor` は macOS で `PlayerSettings.usePlayerLog = false` にするので、`Debug.Log` は `Player.log` に残らない。sandbox ではファイルは `~/Library/Containers/com.jonghyunkim.nativetoolkit.probe1a9/Data/…` の中にできる
   - **手順は起動からの時刻で自動に始める**（agent は画面のボタンを押せない）。例: コマンドラインの引数 `-ntkStep M-8` を `Environment.GetCommandLineArgs()` で読み、`Update` で起動から 3 秒たったら 1 回だけその手順を始める。起動は `open -n <.app> --args -ntkStep M-8`。通知のクリックで起動したとき（引数なし）は M-7 の受け手の手順を既定にする。**各 M-n の終わりにアプリを終了し、次に起動する前に `pgrep -f <product name>.app/Contents/MacOS` で試すアプリのプロセスが無いことを確かめる**（`open -n` は動いているものと別にもう 1 つ起動するので、同じ bundle id のプロセスが 2 つになると、通知のクリックがどちらに届くかが曖昧になる）。クリックそのものを見る手順（M-3 の `OnGUI`、M-10 (2)）だけボタンにし、「利用者の操作」に書く
   - `Update` でフレーム番号を画面に出し続け、動くもの（回る立方体など）を置く。`Application.runInBackground` と `Application.isFocused` を手順の始めと終わりに `Log` に出し、`OnApplicationFocus` も `Log` に出す（M-8）
   - 呼ぶ直前に `NtkProbeMac.BeginCall(<tag>)`、直後に `NtkProbeMac.MarkReturned(<tag>)` を呼ぶ。完了と `release` の行に `after-return=1` が出れば、完了が戻った後に来た印。`BeginCall` を呼んでいない tag は `after-return=n/a` になる（見ない）。**tag は 1 つのプロセスで 1 回だけ使う**（下の M-n の tag はすべて別にしてある）
   - C# の `catch` は `NtkProbeMac.LogException` を使う（どのスレッドからでもよい。`Debug.LogException` は `Pump` が main で呼ぶ）
9. **署名と sandbox**: 署名はあなたの側の Team（Automatic、Apple Development）でよい。Release で組む。**product name のターゲットで `ENABLE_APP_SANDBOX = YES` を明示する**（Unity の書き出しの既定に頼らない。`Build/Mac` の値は手で足した見込み）。起動前に `codesign -d --entitlements - <.app>` で `com.apple.security.app-sandbox` が `true` であることを確かめる。Hardened Runtime は M-11 だけで入れる

組んだ後、起動する前に（許可は要らない）: `.app/Contents/Frameworks/` に `NtkProbeMac.framework` と `NtkProbeMacCApi.framework` があること、`Headers` が外れ、残りの symlink が 4 本ずつ（`Versions/Current`・本体・`Resources`・`Modules`）あること（`find <.app>/Contents/Frameworks -type l`。違えば記録する）、`otool -L <.app>/Contents/MacOS/<実行ファイル>` に 2 つの `@rpath/…/Versions/A/…` があること、`codesign --verify --deep --strict --verbose=2 <.app>` が通ること。

## 3. ヘッダーと C# の宣言

雛形の公開シンボルは次の 20 個だけ（`nm -gU`。arm64 と x86_64 で同じ。`BUILD-INFO.txt` にもある）:

```
ntk_version  ntk_string_data  ntk_string_size  ntk_string_free
ntk_probe_thread_info  ntk_probe_echo_async  ntk_probe_describe  ntk_probe_redact_path
ntk_dialog_show_alert_async  ntk_probe_dialog_show_alert_gcd_async  ntk_share_show_async
ntk_notification_install  ntk_probe_notification_install_at
ntk_probe_notification_add_listener  ntk_probe_notification_listener_remove
ntk_probe_notification_get_launch_response  ntk_probe_notification_get_authorization_status
ntk_probe_notification_request_permission  ntk_probe_notification_schedule_marked  ntk_probe_notification_describe
```

今回使う関数の C の形（詳しくはヘッダーのコメント）:

```c
uint32_t ntk_version(void);                                     /* 0x020000 */
/* Probe.h */
int32_t ntk_probe_thread_info(int32_t* out_is_main, uint64_t* out_thread_id, int32_t* out_has_nsapp);
typedef void (*ntk_probe_echo_fn)(void* user_data, int32_t value, int32_t is_main);
int32_t ntk_probe_echo_async(int32_t value, uint32_t delay_ms, ntk_probe_echo_fn callback, void* user_data, ntk_release_fn release);
ntk_string* ntk_probe_describe(void);   /* bundle, build-token, pid, sandbox, NSApp class, active, key window,
                                           fullScreen, the paths of the two frameworks (paths redacted) */
ntk_string* ntk_probe_redact_path(const char* path);   /* the redaction describe uses; for the smoke */
/* Dialog.h: errors 0 NONE, 1 INVALID_PARAMETER, 6 CANCELED (auto close), 10 SHOW_FAILED; button 0 / 1 / -1 */
typedef void (*ntk_dialog_done_fn)(void* user_data, uint64_t request_id, int32_t error, int32_t button);
int32_t ntk_dialog_show_alert_async(const char* title, const char* message, const char* positive_text, const char* negative_text,
                                    uint32_t auto_close_ms, ntk_dialog_done_fn callback, void* user_data,
                                    ntk_release_fn release, uint64_t* out_request_id);           /* A' */
int32_t ntk_probe_dialog_show_alert_gcd_async(/* same arguments */);                            /* A (control of M-8) */
/* Share.h: errors 0 NONE, 1 INVALID_PARAMETER, 6 NOT_FOREGROUND, 7 EMPTY_CONTENT */
typedef void (*ntk_share_done_fn)(void* user_data, int32_t error, int32_t chosen, ntk_string* service_title);
int32_t ntk_share_show_async(const char* text, uint32_t auto_close_ms, ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
/* Notification.h: 0 NONE, 1 INVALID_PARAMETER, 2 NOT_INITIALIZED, 3 NOT_SUPPORTED (no app bundle), 4 UNKNOWN,
   10 PERMISSION_DENIED, 16 WRONG_THREAD */
int32_t ntk_notification_install(void);                         /* main only, synchronous */
/* ProbeNotification.h */
int32_t ntk_probe_notification_install_at(int32_t when);        /* 1 willFinish observer, 2 now, 3 didFinish observer */
int32_t ntk_probe_notification_add_listener(ntk_probe_notification_event_fn callback, void* user_data,
                                            ntk_release_fn release, ntk_probe_notification_listener** out_listener);
void    ntk_probe_notification_listener_remove(ntk_probe_notification_listener* listener);
int32_t ntk_probe_notification_get_launch_response(ntk_string** out_identifier, ntk_string** out_action);
int32_t ntk_probe_notification_get_authorization_status(ntk_probe_notification_done_fn callback, void* user_data,
                                                        ntk_release_fn release);   /* granted = 0 notDetermined, 1 denied, 2 authorized, 3 provisional */
int32_t ntk_probe_notification_request_permission(ntk_probe_notification_done_fn callback, void* user_data, ntk_release_fn release);
int32_t ntk_probe_notification_schedule_marked(uint32_t seconds, const char* identifier, const char* title,
                                               ntk_probe_notification_done_fn callback, void* user_data, ntk_release_fn release);
ntk_string* ntk_probe_notification_describe(void);  /* install calls, launch notifications, delegate calls, in order */
```

約束（iOS の第 1 部 1 章と同じ。決定の D-6）:

- どの関数もどのスレッドから呼んでもよく、main を待たない（例外は `ntk_notification_install` と `ntk_probe_notification_install_at`: main からの同期。main 以外は 16）
- 受け付けた（戻り値 0）要求は、完了がちょうど 1 回、その後に `release`（`NULL` でなければ）がちょうど 1 回、**どちらも main で**来る。**完了は、その要求を始めた関数の中で同期に呼ばれることはない**。main から呼んだ場合は、関数が戻った後に来る。**別のスレッドから呼んだ場合は、呼び出し元のその後の処理と並んで main で走りうる**（iOS・Android の AC-5 と同じ。呼び出し元のスレッドで戻った後に来ることは保証しない）。入口の中で同期に呼ばないことを守っているのは、完了を main に積むこと。雛形には、別のスレッドからの呼び出しで入口の最後の文が終わるまで配送を遅らせる `ReturnGate` もあるが、これは雛形だけの仕組みで、契約に含めず、smoke の合否にも入れていない。**別のスレッドから呼んだときは、出力の引数（`out_request_id`、C# の `out var id`、`out_listener`）が呼び出し元に見える前に完了やイベントが来うる。完了と要求の対応付けは `user_data` で行う**（iOS の第 1 部と同じ。下の M-n はどれも tag で対応付けている）。入口で拒んだ（0 以外）ときは、完了は来ず、`release` が**関数が戻る前に**呼び出し元のスレッドで呼ばれる
- **受け手の登録（`add_listener`）は完了を持たない**。`release` は `listener_remove` の後に main で 1 回来る
- 渡された `ntk_string*` は受け手のもの。`NtkProbeMac.Take` が読んで `ntk_string_free` する
- **Dialog**（D-8 の A'）: 関数は main の run loop に `CFRunLoopPerformBlock`（common modes）でブロックを積んで戻り、そのブロックが `NSAlert.runModal()` を呼ぶ。GCD のブロックの外から入るので、開いている間も main キューが捌かれる見込み（1a-6 の VM の試作では捌かれた）。`auto_close_ms` が 0 より大きければ、その時間の後、前のモーダルが自分のアラートのときだけ `abortModal` で閉じる（完了は `error=6 button=-1`）。`ntk_probe_dialog_show_alert_gcd_async` は比べるための A の形（`DispatchQueue.main.async` の中から `runModal`）。入るときに、main の run loop の mode と呼び出し元の関数名（パスとアドレスなし）を記録に出す
- **Share**: main キューに積んで、key window（無ければ main window）の content view の中央に `NSSharingServicePicker` を出す。ピッカーは完了まで雛形が強く保つ。完了は delegate の `didChoose`（サービスを選ばずに閉じれば `chosen=0`）。`auto_close_ms` が 0 より大きければ、その時間の後に `close()` で閉じる。window が無ければ完了で `NOT_FOREGROUND`
- **通知**: `ntk_notification_install` は戻る前に `UNUserNotificationCenter` の delegate（前の delegate に転送する最小の proxy）を入れる。冪等。bundle の無いプロセスでは `UNUserNotificationCenter.current()` を呼ばずに 3。雛形が予約した通知（userInfo に `com.jonghyunkim.nativetoolkit` = 1）のクリックはライブラリが受け、受け手へ main で渡す。**受け手が 1 つも無い間（最初の登録の前と、全部外した後）のイベントは 32 件まで保ち、次に登録された受け手に渡す**。**起動のきっかけ**（`is_launch_response` と取得）は iOS の決まり（プロセスで最初の `didReceive` が、最初の `NSApplicationDidBecomeActive` の通知より前で、ライブラリが受けたもの）。`NSApp.isActive` は `willFinishLaunching` で既に true なので使わない（1a-8）。iOS の後の絞り込み（H2-1）は入れていない（M-7 の本文のクリックでは結果は同じ）。macOS の定義は 1a-8 の材料で D-7 で決める。記録には `didFinishLaunching` の `NSApplicationLaunchUserNotificationKey` の有無も出す

C#: `unity/NtkProbeMac.cs`（Mono で `[MonoPInvokeCallback]` の static のメソッド、デリゲートは static の欄に保つ、本体を `try` / `catch` で囲み、`catch` は `LogException`、`Log` と `LogException` はどのスレッドからでも安全、after-return の印は `BeginCall` と `MarkReturned`）。こちらでは Unity 6000.4.2f1 の Roslyn と `UnityEngine.CoreModule.dll` でコンパイルが通ることだけを確かめた（動かしていない）。`user_data` は整数の印（`new IntPtr(1)` など、0〜255。1 つのプロセスで同じ印を使い回さない）でよい。出力の行は `欄=値` を空白で並べた形なので、合格の条件は欄ごとに一致を見る。

## 4. 確かめること

すべて Release の構成で組んだアプリで行う。**「起動」と書いた手順の前には、0 章の許可を得る**。各項目の「許可」の欄は、その項目で起動・画面・通知を使うか、「利用者の操作」は手でしかできない操作を示す。

### M-1: 組み込みと `__Internal` の呼び出し（Mono）— D-9、D-11、D-24

| 項目 | 内容 |
|---|---|
| 手順 | 2 章のとおりに組み（`NTK_1A9_INSTALL_AT=1`）、2 章の最後の起動前の確かめをする。起動し（`-ntkStep M-1`）、順に: (1) `ntk_version()`、(2) `Take(ntk_probe_describe())`、(3) `BeginCall(new IntPtr(11))`、`ntk_probe_echo_async(11, 0, Echo, new IntPtr(11), Release)`、直後に `MarkReturned(new IntPtr(11))`（main からの呼び出し） |
| 合格の条件 | 起動前の確かめがすべて通る。(1) が `0x020000`（131072）。(2) の `capi=` と `core=` が `<名前>.app/Contents/Frameworks/` の中の 2 つの framework を指し、`sandbox=1`。(3) 戻り値 0、続いて `echo tag=11 value=11 … after-return=1 … managed-main=1` が 1 回、その後に `release tag=11 after-return=1` が 1 回（main から呼んだので、入口の中で同期に呼ばれていなければ必ず 1）。**同じフレームで届いてもよい**（`last-frame` は記録だけ）。起動で落ちない（`dyld: Library not loaded` などが無い） |
| 記録すること | 上の値、`.app` の framework の symlink の一覧、`otool -L` の 2 行、`codesign --verify` の結果、組み込みで手間取ったこと |
| 許可 | 起動の前に要る。利用者の操作は無い |
| 結果で変わる決定 | 失敗なら D-9（2 つの dynamic の xcframework）と D-24（書き出しにリンクして `__Internal`）を見直す |

### M-2: IL2CPP（できれば）— D-24

| 項目 | 内容 |
|---|---|
| 手順 | **両方のリポジトリの外に、6000.0.44f1 で新しく作った使い捨てのプロジェクト**（パッケージを入れない。`NtkProbeMac.cs` と確かめのシーンだけ）で行う（このリポジトリの写しを 6000.0.44f1 で開くと版が下がり、1.x の `__Internal` の記号が `GameAssembly` のリンクに紛れる）。IL2CPP、Create Xcode Project、release で書き出し、2 つの framework のリンクと埋め込みは手か小さな PostProcessBuild で行う。書き出しに `GameAssembly.xcodeproj` がどこにできるか、`GameAssembly` のリンクで `_ntk_*` が未定義になるか、なるなら `GameAssembly` にも C ABI の framework をリンクして（埋め込みはアプリの側だけ）通るかを見て、M-1 をする |
| 合格の条件 | M-1 と同じ値が出る。`GameAssembly` へのリンクが要るかどうかが分かる |
| 記録すること | エディターの版、`GameAssembly.xcodeproj` の置き場（書き出しのフォルダーの直下だと、あなたの `MacXcodeProjectFrameworks.FindPbxprojPath` が「more than one Xcode project」で止まる）、リンクの要否、足した設定、`MonoPInvokeCallback` と `byte[]` の受け渡しで困ったこと |
| 許可 | 起動の前に要る |
| 結果で変わる決定 | D-24 と 2c の `PostBuildProcessor`（`GameAssembly` にもリンクするか、プロジェクトの探し方） |

できなければ、理由（エディターに IL2CPP が無いなど）を `blocked` に書く。そのとき D-24 の確かめた範囲は Mono だけになる。

### M-3: C# が main スレッドで動くか — D-6

| 項目 | 内容 |
|---|---|
| 手順 | `NtkProbeMac.LogThread(...)` を `Awake`・`Start`・`Update`（最初の 1 回）・コルーチン・`OnApplicationFocus`・`OnGUI` のボタンのクリックから呼ぶ。比べるために `Task.Run` の中からも呼び、そこから `BeginCall(new IntPtr(31))`、`ntk_probe_echo_async(31, 0, Echo, new IntPtr(31), Release)`、直後の `MarkReturned(new IntPtr(31))` も呼ぶ（`Task.Run` の中では `Log` 以外の Unity の API を呼ばない） |
| 合格の条件 | `Task.Run` 以外はすべて `pthread-main=1` と `nsapp=1`。`Task.Run` は `pthread-main=0`、例外の行が無い。`Task.Run` から呼んだ echo の完了と `release` は `managed-main=1` で 1 回ずつ（完了が先）来て、echo の `called-on-main=0`（`Task.Run` から呼んだ印）。完了と `release` が `managed-main=1` なので、呼んだスレッドの入口の中で同期に呼ばれていない |
| 記録すること | 場所ごとの `pthread-main`・`tid`・`managed-main`。`Task.Run` の echo の `after-return`（別のスレッドからの呼び出しでは、呼び出し元のその後の処理と並んで走りうる契約なので、0 でも不合格にしない。値を書くだけで、D-6 の材料にもしない） |
| 許可 | 起動の前に要る（M-1 と同じ起動でまとめてよい）。利用者の操作: `OnGUI` のボタンを 1 回押す |
| 結果で変わる決定 | D-6（完了は main へ非同期）。main でなければ契約の書き方を変える |

### M-4: 通知の install の参照が無いホスト（Clipboard だけを使うホストの代わり）— D-24

| 項目 | 内容 |
|---|---|
| 手順 | `NTK_1A9_INSTALL_AT=0` で組む（または書き出しの `Main.cpp` をそのまま使う）。実行ファイルのどこからも `_ntk_*` を直に参照しない。product name のターゲットの `OTHER_LDFLAGS` に `-dead_strip_dylibs` が無いかを見る。起動前に `otool -L` で 2 つの framework が残っているかを見る。起動し、C# から `ntk_version()` と `ntk_probe_describe()` だけを呼ぶ |
| 合格の条件 | `otool -L` に 2 つが残り、C# の呼び出しが M-1 と同じ値を返す（Mono の `__Internal` が、実行ファイルが参照しない framework の記号を見つける） |
| 記録すること | `otool -L` の結果、`OTHER_LDFLAGS` と `DEAD_CODE_STRIPPING` の値、C# の結果 |
| 許可 | 起動の前に要る |
| 結果で変わる決定 | D-24。落ちる・見つからないなら、ホストに C ABI の記号を 1 つ参照させる手順（2c の `PostBuildProcessor`）か、リンカーの設定を案内に書く |

雛形には Clipboard の関数が無いので、通知に触れない `ntk_version` と `ntk_probe_describe` で代える。

### M-5: `Main.cpp` で `PlayerMain` の前に install を呼べるか — D-4

| 項目 | 内容 |
|---|---|
| 手順 | `NTK_1A9_INSTALL_AT` を 1・2・3 のそれぞれで組み（`NTKProbeBuildToken` を形ごとに変える）、普通に起動する（通知は出さない）。起動から 3 秒後に `ntk_probe_notification_add_listener(NotificationEvent, new IntPtr(51), Release, out var listener)` を呼び（`listener` は保ち、終わりに `listener_remove` して `release tag=51` を見る）、`ntk_probe_notification_describe()` と `ntk_probe_describe()` を記録する。ウインドウ・入力・描画がいつもどおりかを見る |
| 合格の条件 | 1 と 2 のどちらか（できれば両方）で: アプリがいつもどおり動き、`add_listener` が 0、`ntk_probe_notification_describe` が `installed=1 delegate=NtkProbeNotificationProxy` で、記録の `install main=1 ... -> installed` が `didFinishLaunching` と `didBecomeActive` より前にある。2 では `install main=1 nsapp=0` で、その後の `ntk_probe_describe` の `nsapp=` が Unity の `NSApplication` の子のクラス（`PlayerApplication` の見込み）のまま（雛形が `NSApp` を先に作っていない） |
| 記録すること | 形ごとの 2 つの describe の全文（`build-token=` を含む）。Unity の `NSApp` のクラス名。`recording starts`・`willFinishLaunching`・install・`didFinishLaunching`・`didBecomeActive` の順と時刻。2 で何か壊れたか（メニュー、ウインドウ、全画面、終了） |
| 許可 | 起動の前に要る（3 つの形の起動を一覧にして 1 回の許可でよい）。利用者の操作は無い |
| 結果で変わる決定 | D-4（install の時期と、`NSApp` が無い時期に呼んだときの扱い。決定の文書 8.6）。どちらもだめなら、D-4 の C 案（framework の読み込みで受け手を登録）を利用者に尋ねる |

### M-6: 書き出し直しで足したコードが残るか — D-4、D-24

| 項目 | 内容 |
|---|---|
| 手順 | M-5 で `Main.cpp` を置き換え、`GCC_PREPROCESSOR_DEFINITIONS` と `Info.plist` のキーを足した書き出しのフォルダーに、batchmode で同じ設定でもう一度書き出す。GUI で書き出すときに Unity が置き換えか追記かを尋ねる形を見たい場合は、利用者に頼む（agent は GUI を操作しない） |
| 合格の条件 | 合否ではない。結果を記録する |
| 記録すること | `Main.cpp`・足した設定・`Info.plist` のキーが残ったか、消えたか。`PostBuildProcessor` が 2 つの framework を二重に足さないか。残らないなら、`PostBuildProcessor` で毎回 `Main.cpp` に足す形（2c）で通せそうか（試さなくてよい） |
| 許可 | 要らない（起動しない） |
| 結果で変わる決定 | 2c の `PostBuildProcessor` の役目（`Main.cpp` を毎回直すか） |

### M-7: 通知のクリックでのコールドスタート — D-4（配送）、1a-8・D-7（分類の材料）

| 項目 | 内容 |
|---|---|
| 準備 | (a) 利用者に集中モードを入れてもらい、通知を許すアプリに試すアプリ（`com.jonghyunkim.nativetoolkit.probe1a9`）を入れられたかを確かめてもらう。入れられなければ、集中モードなしで流すか（ほかのアプリの通知が出うる。画面を記録しない）を利用者に尋ねる。(b) M-5 で通った形（1 が通れば 1）で組み、`NTKProbeBuildToken` を新しくする。(c) 同じ bundle id のほかの形の `.app` がこの Mac に残っていれば、通知のクリックで別のコピーが起動しうる。下の合格の条件の `build-token` で見分け、別のものが起動したら、ほかのコピーを消してよいかを利用者に尋ねる（LaunchServices の掃除は 1 回ごとの許可） |
| 手順 | (1) 起動し（`-ntkStep M-7`）、`ntk_probe_notification_get_authorization_status(NotificationDone, new IntPtr(70), Release)` で今の許可の状態を記録する。`0`（notDetermined）なら `ntk_probe_notification_request_permission(NotificationDone, new IntPtr(71), Release)` を呼び、**利用者に**出た許可の求めで「許可」を押してもらう。**求めの完了が `notification-done tag=71 error=0 granted-or-status=1` で来て、続けて `get_authorization_status` を tag 77 で呼んで `granted-or-status=2`（authorized）になったことを確かめてから (2) へ進む**（最初から `2` なら求めずに進む）。`1`（denied）か、求めで拒まれたか、求めから 60 秒で完了が来ない（答えが無い）とき、`3`（provisional。macOS はバナーを出さず通知センターに静かに入れる）のとき、バナーを利用者が操作できないときは、**止めて `blocked` に書く（D-4 の失敗に数えない）**。許可を変えてよいかは利用者に尋ねる（通知の許可の変更は 1 回ごとの許可）。(2) `ntk_probe_notification_schedule_marked(20, Utf8("m7-cold"), Utf8("M-7 cold"), NotificationDone, new IntPtr(72), Release)` を呼び、**`notification-done tag=72 error=0` と `release tag=72` が来るまで待つ**。来たら画面に「終了してよい」と出す。**予約の前提が成り立たないときは止めて `blocked` に書き、D-4 の判定から外す**: 戻り値が 0 でない、完了の `error` が 0 でない（`4` UNKNOWN の原因は環境と決めつけず、値と記録をそのまま書く）、10 秒たっても完了か `release` が来ない。(3) **利用者に**アプリを終了してもらい（Cmd-Q）、`pgrep` でプロセスが無くなったこと（前の pid）を確かめる。予約から 20 秒たつ前に終わっていること。**終われなかった（20 秒の内にプロセスが残った、終わる前にバナーが出た）回は、コールドスタートでないので D-4 の判定から外し、利用者に知らせて許可を得てから (1) からやり直す**。(4) バナーが出たら、**利用者に**本文をクリックしてもらう（アプリがコールドスタートする）。(5) 起動したアプリ（引数なしなので既定の手順。**既定の手順は最初に `Application.runInBackground = true` にする**。後ろにいる間も `Update` と下の (7)・(8) の段が回るように）で、`Start()` で受け手を `ntk_probe_notification_add_listener(NotificationEvent, new IntPtr(74), Release, out listener)` で登録し（`listener` は保つ）、**最大 10 秒、イベントが来るのを待つ**。来たら（または 10 秒たったら）`get_launch_response` と 2 つの describe を記録する |
| 合格の条件（D-4 の材料） | 起動したプロセスの `ntk_probe_describe` が、(b) の `build-token` で、前と違う `pid`。そのプロセスに `event kind=0 id=m7-cold action=com.apple.UNNotificationDefaultActionIdentifier` の欄を持つ行がちょうど 1 回来る（**`launch` の値は問わない**）。`ntk_probe_notification_describe` の記録で、install が `didReceive id=m7-cold` より前にある |
| 記録すること（1a-8・D-7 の材料。合否ではない） | `launch` の値、取得の値、記録の `recording starts`・`willFinishLaunching`・install・`didFinishLaunching`（`launchUserNotificationKey`）・`didReceive`（`active=`）・`didBecomeActive` の順と時刻、許可の状態と許可の求めが出たか（利用者の目）、バナーが出たか。1a-8 の VM の測りでは、止まった状態からのクリックは `willFinishLaunching` → `didFinishLaunching` → 約 40〜50 ms 後に `didReceive` → `didBecomeActive` の順だった（作業の記録の 5 章）。macOS の通知の設定に増えた項目（試すアプリの名前）は、終わったら利用者に知らせる（消すのは利用者の判断） |
| 続き | (6) 1 の形で `m7-cold` が届かなければ、2 の形で (1)〜(5) をもう一度行う。**(7)・(8) は (5) と同じプロセスの既定の手順の中で、時刻でなく出来事で次へ進む**（新しく起動すると意味が変わる。agent は画面を押せない）: (7) 温かい起動: (5) の記録が済んだら `schedule_marked(20, Utf8("m7-warm"), …, new IntPtr(73), …)` を呼び、画面に「ほかのアプリを前に出し、バナーを押す」と出す。**利用者に**ほかのアプリを前に出してもらい、バナーをクリックしてもらう。**受け手 74 に `event … id=m7-warm` が届いたら (8) へ進む**（120 秒で来なければ (7) を「確かめられない」として (8) へ進まない）。`m7-warm` が受け手 74 に 1 回届く（`launch` は記録だけ。1a-8 では 0 の見込み）。(8) できれば、全部外した後の保持: (i) 受け手 74 を `listener_remove` で外し、**`release tag=74` が来たら**（外し終えた）、(ii) `schedule_marked(20, Utf8("m7-held"), …, new IntPtr(75), …)` を呼び、画面に「バナーを押す」と出して利用者にクリックしてもらう。(iii) `Update` で 1 秒ごとに `ntk_probe_notification_describe` を読み、**記録に `didReceive id=m7-held` が出たのを見つけてから 2 秒後に**、受け手を `new IntPtr(76)` で登録し直す（120 秒で出なければ (8) を「確かめられない」）。**合格の条件**: `m7-held` が受け手 76 に 1 回届き、順が「`release tag=74`（外し終えた）→ 記録の `didReceive id=m7-held` → 受け手 76 の登録」である（登録は `didReceive` を見つけてから行うので、順は手順で決まる。その 3 つの行と時刻を記録する）。`m7-held` が受け手 74 に届いた、`didReceive` より前に 76 を登録してしまった、など保持を通らずに届いた回は「保持は確かめられない」と書き、合格にしない。`m7-held` が届かなければ不合格 |
| 許可 | 要る（通知の許可の求め、バナー、アプリの終了と起動、通知センターに項目が増える）。利用者の操作: 許可の求めのクリック、Cmd-Q、バナーのクリック、ほかのアプリを前に出す |
| 結果で変わる決定 | D-4（install の時期で間に合うか）。`launch` と順は D-7 と 1a-8（`launch_response` の定義）の材料 |

### M-8: Dialog の間に描画とプレイヤーのループが止まるか — D-8（Unity での A' の判断材料）

| 項目 | 内容 |
|---|---|
| 手順 | `Update` でフレーム番号・時刻（`Stopwatch`）を出し、回る物を動かすシーンで、起動の 3 秒後に（`-ntkStep M-8`）同じフレームの中で: (1) `ntk_dialog_show_alert_async(Utf8("M-8"), Utf8("Wait"), Utf8("Yes"), Utf8("No"), 8000, DialogDone, new IntPtr(81), Release, out var id)`、(2) `ntk_probe_echo_async(82, 2000, Echo, new IntPtr(82), Release)`、(3) `ntk_probe_echo_async(83, 4000, Echo, new IntPtr(83), Release)` を呼ぶ。アラートは押さずに 8 秒の自動で閉じるのを待つ。**比べる形**: (4) 同じことを `ntk_probe_dialog_show_alert_gcd_async`（A。今の 1.x の入り方）で tag 84〜86 として行う。(5) できれば (1)〜(3) を `Application.runInBackground = true` にして、tag 87〜89 でもう一度行う（フォーカスが外れて止まるのか、モーダルのループで止まるのかを分ける）。(6) もう 1 回、(1) を `auto_close_ms=0`、tag 80 で出し、5 秒ほど待ってから**利用者に**「No」を押してもらう |
| 合格の条件 | A'（(1)〜(3)）で、echo の 82 と 83 が、アラートが開いている間（`ntk_probe_notification_describe` の記録の `dialog runModal enter` と `return` の間）に main で 1 回ずつ届き、`release` が続く。アラートの完了は自動のとき `error=6 button=-1`、押したとき `error=0 button=1`、`release` が 1 回。**フレームが進むかは合否ではない**（記録する）。A（(4)）は比べるためで合否ではない（1a-6 では echo は閉じた後に届いた） |
| 記録すること | 形ごとに: 開いている間に `last-frame` が増え続けたか（前・間・後の値と `ms`）、回る物と音が止まったか、echo の届いた `ms`、記録の `dialog runModal enter`（`entry=`・`mode=`・`stack=` の全文）と `return`、`echo 82 delivered`、`dialog auto-close ours=`。`Application.runInBackground`・`Application.isFocused`・`OnApplicationFocus` の値と時刻 |
| 許可 | 要る（アラートが出る）。利用者の操作: (6) の「No」だけ |
| 結果で変わる決定 | D-8 の A' を推す材料（フレームが止まるなら、A'' か B を 2.0.0 の前に比べるかを利用者に尋ねる材料）。D-8 の残りの基準（要求ごとの取り消し、ホストのモーダルを閉じない、同じ回の 2 つ目、ファイルのパネル）は native-toolkit で第 1 部の前に測る |

### M-9: 全画面の上に Dialog と Share が出るか — D-8、D-6

| 項目 | 内容 |
|---|---|
| 手順 | `Screen.fullScreenMode` を `FullScreenWindow` にして（もう 1 回 `MaximizedWindow` で。macOS には `ExclusiveFullScreen` は無い）、(1) `ntk_dialog_show_alert_async(..., 5000, ..., new IntPtr(91), ...)`、(2) `ntk_share_show_async(Utf8("M-9 text"), 5000, ShareDone, new IntPtr(92), Release)` をそれぞれ時刻の引き金で出す |
| 合格の条件 | 合否ではない。結果を記録する |
| 記録すること | 全画面の形ごとに、アラートとピッカーがゲームの上に見えたか（利用者の目）、全画面が解けたか・別の Space に移ったか、完了の値（アラートは `error=6`、Share は `error=0 chosen=0`）と `release`、記録の `fullScreen=` と `share auto-close open=` |
| 許可 | 要る（全画面、アラート、ピッカー）。利用者の操作: 見えたかを答える |
| 結果で変わる決定 | D-8 と D-6、第 1 部の前面の扱い（決定の文書 8.6）、マニュアルの注意 |

### M-10: Share を出す文脈（1a-7 の Unity の部分）— D-6

| 項目 | 内容 |
|---|---|
| 手順 | (1) 起動の 3 秒後の `Update` の中から（クリックの外）、`ntk_share_show_async(Utf8("M-10 update"), 5000, ShareDone, new IntPtr(101), Release)`。(2) `OnGUI` のボタンのクリックから同じものを `new IntPtr(102)` で。(3) **`Application.runInBackground = true` にして**（後ろにいる間も `Update` が回るように）、**利用者に**ほかのアプリを前に出してもらい、その 5 秒後に時刻の引き金で同じものを `new IntPtr(103)` で。呼んだときの `Application.isFocused` と時刻を `Log` に出す。後ろにいる間に呼べなかった（`isFocused=True` で呼んだ、か呼ばれなかった）ときは、(3) を「確かめられない」と書く。どれもサービスを選ばない（5 秒で自分で閉じる）。雛形はどれも main キューに積んだ先でピッカーを出すので、(1)・(2) の違いは記録の `share show event=`（その時の `NSApp.currentEvent` の種類）だけ。Unity でしか見られないのは (3) |
| 合格の条件 | (1)・(2) でピッカーが出て、`error=0 chosen=0` の完了と `release` が 1 回ずつ main で来る。(3) は合否ではない |
| 記録すること | 出たか（どの window に）、記録の `share show event= key= active=` と `share auto-close open=`、`share no window`、完了の値（(3) は `NOT_FOREGROUND`（6）か、出たか） |
| 許可 | 要る（ピッカーが出る）。利用者の操作: (2) のボタン、(3) でほかのアプリを前に出す |
| 結果で変わる決定 | D-6（Share を例外にしなくてよいか）、第 1 部の前面の扱い |

### M-11: Hardened Runtime と sandbox を入れた書き出しで起動するか — D-18、D-24

| 項目 | 内容 |
|---|---|
| 手順 | product name のターゲットで `ENABLE_HARDENED_RUNTIME = YES`、`ENABLE_APP_SANDBOX = YES`、あなたの Team で署名（Automatic）して組む。(1) まず entitlement を足さずに起動する。落ちたら、dyld か crash の文の、どの image が何の理由で落ちたか（パスは伏せる）を記録する（`Team IDs` の文なら framework の拒否、Mono の実行時のコード生成なら JIT の制約）。(2) Mono のために `com.apple.security.cs.allow-jit` **だけ**を足して起動する（それでも JIT で落ちるときだけ `com.apple.security.cs.allow-unsigned-executable-memory` を足す）。**`com.apple.security.cs.disable-library-validation` は足さない**（Unity の公証の案内にあっても。足すと Library Validation を確かめないまま通る）。(3) 起動したら M-1 の (1)〜(3) をする。(4) できれば、同じものを「Sign to Run Locally」（ad-hoc）で組み、起動できないこと（Library Validation）を見る |
| 合格の条件 | Team の署名で起動でき、M-1 と同じ値が出て、`ntk_probe_describe` が `sandbox=1`。`codesign -d --entitlements - --xml <.app>` の実効の entitlement に `disable-library-validation` が無く（あれば合否から外す）、`codesign -dv` の flags に `runtime` がある。2 つの framework の Team がアプリと同じ |
| 記録すること | (1) の結果、足した entitlement とその値、flags、Team が「アプリと同じ / 違う」（**Team ID と証明書の名前は書かない**）、(4) の dyld の文（パスは伏せる） |
| 許可 | 起動の前に要る（(1)〜(4) の起動を一覧にして 1 回の許可でよい） |
| 結果で変わる決定 | D-18（配る framework に署名しない）、マニュアルの署名の注意（Mono の Hardened Runtime に要る entitlement） |

### M-12: コピーの経路で symlink が残るか — D-9

| 項目 | 内容 |
|---|---|
| 手順 | あなたの `probe/stage_a.sh`・`stage_b.sh` は `ntk-probe-1.0.0.xcframework`・`NtkProbe.framework` と 1.3.0 を決め打ちしているので、**写しを作り、置く物・`VERSION.txt` の名前・探す名前・照らす名前を、この 2 つ（`ntk-probe-mac-1.0.0`・`ntk-probe-mac-capi-1.0.0`、`NtkProbeMac`・`NtkProbeMacCApi`）に直して**流す（1.3.0 は入れない）。dist → `Plugins/macOS`（`ditto`）→ git の URL の `PackageCache` → 書き出し → `.app` |
| 合格の条件 | 書き出しと `.app` で 2 つの framework の symlink がそろい（`PackageCache` で落ちたものは作り直される）、`xcodebuild` が通り、`.app` と 2 つの framework で `codesign --verify --deep --strict` が通る。AssetDatabase の取り込みで symlink の警告や二重の取り込みが無い。照らした framework の名前と `BUILD-INFO.txt` の `built` を記録に出す（前の `ntk-probe-1.0.0` の成功を流用しない） |
| 記録すること | 段ごとの symlink の本数、警告、`codesign` の結果、照らした framework の名前 |
| 許可 | 要らない（起動しない） |
| 結果で変わる決定 | D-9（symlink を保つ配布物の形） |

## 5. 結果の返し方

1. あなたのリポジトリの中に結果のファイルを書く（場所と名前はあなたの決まりでよい）。各 M-n の手順・結果・記録すべき値と、使った雛形の `BUILD-INFO.txt` の `built` と `commit` の行、`smoke/run.sh` の結果、Unity の版、Xcode の版、macOS の版（この Mac の名前・ユーザー名・Team ID は書かない）
2. 次の要約を、こちらへの返事（利用者を通す）に貼る。こちらは `artifact/topics/macos-c-abi/results/` に写し、決定の文書の D-4・D-6・D-8・D-24 に反映する

```
macos-1a9 results (unity-native-plugin, <commit of your repo>)
probe: built <built>, commit <commit>, smoke <4 SMOKE PASS + 2 DLOPEN PASS|...>   Unity 6000.4.2f1 (+ <IL2CPP editor or none>)   Xcode <version>   macOS <version>
M-1: pass|fail  version=<value>  describe-paths=<Contents/Frameworks both|...> sandbox=<1|0>  echo: once=<yes|no> release=<count> main=<yes|no> after-return=<1|0> same-frame=<yes|no>  links-in-app=<n,n>  verify=<ok|...>
M-2: pass|fail|blocked  gameassembly-project=<where>  gameassembly-link-needed=<yes|no|n/a>  <notes>
M-3: pass|fail  awake/start/update/coroutine/focus/ongui=<1/1/1/1/1/1>  task-run=<0>  echo-from-task: completion main=<yes|no> after-return=<1|0> (info)
M-4: pass|fail  otool-both=<yes|no>  dead_strip_dylibs=<absent|present>  calls=<ok|...>
M-5: at=1 -> install=<installed|...> before didFinish=<yes|no> app-ok=<yes|no>  at=2 -> install nsapp=0 <installed|...> nsapp-class-after=<class> app-ok=<yes|no>  at=3 -> <...>
M-6: main.cpp kept=<yes|no>  settings kept=<yes|no>  plist key kept=<yes|no>  double-add=<yes|no>
M-7: form=<1|2>  copy=<token ok, new pid|other copy>  cold delivered=<once|none|twice> install-before-didReceive=<yes|no>  launch=<0|1> getter=<id|null> order=<...> launchKey=<yes|no>  auth-before=<0|1|2|3> prompt-seen=<yes|no>  warm delivered=<once|...> launch=<0|1>  held-after-remove=<once via hold|not verifiable|none|not run>  blocked=<none|permission|schedule|quit>
M-8: A': echo-during-dialog=<both|none|...> frames advanced=<yes|no> (<before>/<during>/<after>) mode=<...>  A: echo=<after close|during> frames=<...>  runInBackground=true: frames=<...>  focus=<...>
M-9: FullScreenWindow dialog=<over game|behind|space switch>  share=<...>  Maximized: dialog=<...> share=<...>
M-10: update=<shown|not> click=<shown|not> completions=<0/0 once each|...> event-types=<...>  app-behind=<NOT_FOREGROUND|shown on ...>
M-11: no-entitlement=<launched|crash: ...>  added=<allow-jit|+allow-unsigned-executable-memory>  team-signed launch=<ok|fail> sandbox=<1|0> runtime=<yes|no> library-validation-disabled=<no|yes> team-same=<yes|no>  adhoc=<fails as expected|...>
M-12: names=<NtkProbeMac,NtkProbeMacCApi>  links stage A=<n> stage B=<n after repair>  verify=<ok|...>  warnings=<none|...>
blocked: <anything that could not be done, and why>
```

3. スクリーンショット、画面の録画、ログの写し、試すアプリのログのファイルを作ったら、書き写した後に消す（0 章の 6）

## 6. こちらで確かめたこと（組み立てと、画面を使わない確かめだけ）

確かめた雛形は、コミットの直前の作業コピーから組んだもの（`BUILD-INFO.txt` の `built: 2026-11-22T16:05:39Z`。commit `c0aefc7b` の上の、コミット前のソース。ソースはそのままコミットした）。そちらで組むと `BUILD-INFO.txt` の `commit:` に渡した commit が出るので、結果に書く。この Mac（macOS 26.7.3）では、アラート・ピッカー・通知を出すもの、アプリを起動するものは流していない（`device-testing.md` の区分 1 だけ）。Unity のプロジェクトは組んでいない。

| 確かめたこと | 結果 |
|---|---|
| 組み立て | Xcode 26.6（Swift 6.3.3）の `xcodebuild archive`（`generic/platform=macOS`、Release、`CODE_SIGNING_ALLOWED=NO`）と `-create-xcframework`。Swift の警告 0 件 |
| アーキテクチャと形 | どちらも `x86_64 arm64`。スライスは `macos-arm64_x86_64` の 1 つ。symlink は 5 本ずつ（`Versions/Current → A`、最上位の本体・`Resources`・`Headers`・`Modules`）。C ABI の最上位の `Headers` のリンクは、組み立ての最初の段で作った（観点 C の 1 章の問題） |
| 公開シンボル（`nm -gU`） | C ABI は arm64・x86_64 とも 3 章の 20 個だけで、`_ntk_` 以外は 0。`Modules/NtkProbeMacCApi.swiftmodule` と `-Swift.h` は無い。`NtkProbeMac` は Swift の記号を 129 個出す（`MacLibrary` と同じ扱い） |
| 依存と rpath（`otool -L`・`-l`） | C ABI は `@rpath/NtkProbeMac.framework/Versions/A/NtkProbeMac` と Cocoa・Foundation・OS の Swift ランタイムに依存。rpath は `/usr/lib/swift`、`@executable_path/../Frameworks`、`@loader_path/../../..` |
| 署名 | 本体はリンカーの ad-hoc（`flags=0x20002(adhoc,linker-signed)`）。bundle としては署名なし（`codesign --verify` は「not signed at all」。D-18 のとおり）。`ditto` で写して ad-hoc で署名し直したものは、2 つとも `codesign --verify --strict` が通る（symlink が実体になった 1.3.0 の「bundle format is ambiguous」は起きない） |
| C の利用者（`smoke/main.c`、Xcode 26.3 の clang で `-std=c11 -Wall -Wextra -Werror`、bundle も `NSApp` も無いコマンドラインのプロセス。スレッドの間で分ける値はすべて C11 の atomic。`HOME` を偽の container に向けて実行） | arm64・Rosetta の x86_64 のそれぞれで、普通の実行と、遅延のフック（`NTK_PROBE_ENTRY_DELAY_MS=300`。別のスレッドの入口が最後の文の前に眠る）を付けた実行の計 4 回、55 件ずつすべて通った: `ntk_version` = `0x020000`。`ntk_probe_thread_info` は main で 1、別のスレッドで 0。**main から呼んだ echo・Dialog（A' と A）・Share は、完了 1 回 → `release` 1 回、どちらも main で、関数が戻った後**（`release` は完了のコールバックから戻った後で、その中ではない）。**別のスレッドから呼んだ echo と Dialog は、完了 1 回 → `release` 1 回、どちらも main で、呼んだスレッドでは呼ばれない**（入口の中で同期に呼ばれていない）。呼び出し元が戻りを見た時刻との差は記録だけ（フック付きで入口に 304〜310 ms かかり、完了はその後 0〜1.6 ms。契約では並んで走りうるので合否にしない）。拒まれたものは、main でも別のスレッドでも、`release` が呼び出し元のスレッドで戻る前に 1 回だけ来て、その後に完了もイベントも来なかった（通知の完了とイベントのコールバックも数えている）。`delay_ms=200` の echo は 100 ms では来ず、その後に来た。`ntk_notification_install` は別のスレッドで 16、main で 3（`UNUserNotificationCenter` に触れず落ちない）。`ntk_probe_notification_install_at` は別のスレッドで 16、2 で 3、9 で 1、1 で 0。通知の受け手の登録・許可の状態・許可の求め・予約は 3 で、`release` が戻る前に 1 回。Dialog（A' と A）と Share の入力の誤りは 1 か 7 で、`release` が戻る前。`NSApp` が無いときの Dialog は A' も A も `SHOW_FAILED`（10）、Share は `NOT_FOREGROUND`（6）で、どれも画面に何も出さず。雛形は `NSApp` を作らない。**パスの伏せ**: `.app` で終わる道は `<名前>.app`、`.app` の中は `<名前>.app/…`、`.app` の外の framework は `…/<名前>.framework/…`、ほかの利用者のホームのファイルは `…/<名前>`、ログインの利用者の本当のホームの下の container のログは、`HOME` を偽の container に向けても `~/Library/Containers/…` になった。`ntk_probe_describe` にホームのパスが出ない |
| `ReturnGate` の役目 | 雛形だけの仕組み。別のスレッドからの呼び出しで、入口の最後の文が終わるまで main での配送を遅らせる。契約には含めず（入口の中で同期に呼ばないことは、main に積むことが守る）、今の smoke の合否にも入れていない（今の smoke は門を外しても通る）。参考: v1 の時の smoke（時刻を合否にしていた版）で門を一時的に外すと、フック付きの実行で別のスレッドからの完了が入口の最後の文より約 304〜310 ms 前に main で走った。これは v1 の時の結果で、今の smoke では取り直していない |
| 兄弟の置き方（`smoke/dlopen.c`。2 つの framework を `ditto` で同じフォルダーに置き、どちらもリンクしない rpath の無いプログラムから C ABI を `dlopen`） | arm64・x86_64 とも読めた（`NtkProbeMac` は C ABI の `@loader_path/../../..` で、同じフォルダーから読まれた（dyld の読み込みの一覧で確かめた）。`Contents/PlugIns` に置いた場合に当たる） |
| `unity/Main.cpp` | `NTK_1A9_INSTALL_AT` の 0〜3 のそれぞれで、`PlayerMain` を仮に置いて C ABI の framework とリンクできた（arm64・x86_64、`-Wall -Werror`）。動かしていない |
| `unity/NtkProbeMac.cs` | Unity 6000.4.2f1 の Roslyn（`csc.dll`）で、`netstandard.dll` と `UnityEngine.CoreModule.dll` を参照してコンパイルが通った（`AOT.MonoPInvokeCallback` を含む）。動かしていない |

手順は `results/probes/1a9-unity-handoff/smoke/run.sh <出力のフォルダー>`。

## 7. 渡せなかったもの・注意

| もの | 状態 |
|---|---|
| Unity での組み込みと、アプリを起動する確かめ | こちらでは行っていない（Unity での確かめはあなたの受け持ち）。2 章の手順は、あなたの `macos-c-abi-handoff` の記録と、`Build/Mac` の書き出しの形から書いた。設定の名前や手順が違えば、結果に書く |
| 画面・通知を使う雛形の動き | アラート（A'・A）・ピッカー・通知の delegate は、この雛形ではどこでも動かしていない。A' と A の入り方とピッカーの出し方は、1a-6・1a-7 の VM の試作（作業の記録の 2・3 章）と同じ書き方にし、ピッカーは 1a-7 と同じく完了まで強く保つ。`auto_close_ms` での閉じ方（`abortModal`・`close()`）も同じ |
| bundle のあるプロセスでの通知の関数 | 確かめていない（この Mac で通知の許可を求めないため）。M-5・M-7 が初めて。受け手を全部外した後の保持（M-7 の (8)）も、ここでは bundle が無いので流せていない |
| `NSApp` が無い時期の install（M-5 の 2） | `UNUserNotificationCenter.current()` を `NSApplication` より前に呼ぶ。動くかは分からない。雛形は `NSApp` を作らず、`NSApplication.shared` も呼ばない |
| ホストの delegate との共存（D-7） | 雛形の proxy は iOS の `NotificationDelegateRouter` と同じ転送の形（`CompletionOnce`、`nil` の設定の転送、循環の防止）だが、ホストの delegate を置いて転送を確かめる手順は M-n に無い。**1a-9 の結果では D-7 は決まらない** |
| Dialog の取り消し・同じ回の 2 つ目・ホストのモーダルとの区別 | 雛形に無い（1a-6 の基準 (2)・(3)。第 1 部の前に native-toolkit で測る）。`auto_close_ms` は、前のモーダルが自分のアラートのときだけ閉じる |
| Share の完了 | `didChoose` だけで決まる。ピッカーが `didChoose` を呼ばずに消えた場合の見張りは無い（完了も `release` も来ない）。1a-7 では `close()` で `didChoose(nil)` が来た |
| 起動のきっかけの定義 | iOS の P1-22 の元の形（最初の `didReceive` が最初の `didBecomeActive` の通知より前で、ライブラリが受けたもの）。iOS の後の絞り込み（H2-1: 前面をもたらす応答だけを候補にし、main キューの順で決める）は入れていない。M-7 の本文のクリックではどちらも同じ結果。1a-8 の VM の測りでは、この決まりで測った全部の場合を正しく分けた。macOS の定義は D-7 で決める。M-7 の記録がその材料になる |
| 別のスレッドから呼んだときの「戻った後」 | **保証しない**（3 章の約束。iOS・Android の AC-5 と同じ）。雛形は入口の中で同期に呼ばないことだけを守る。D-6 の材料にするのは、main から呼んだ場合の「戻った後」と、どのスレッドからでも「main で、呼んだスレッドの入口の中ではない、1 回、`release` が後」まで（M-1・M-3） |
| 遅延のフック `NTK_PROBE_ENTRY_DELAY_MS` | smoke のためだけのもの。Unity のアプリでは設定しない |
| Clipboard | 雛形に無い。M-4 は通知に触れない関数で代えた |
| 本番の関数名・引数・エラーの番号 | C ABI の設計書の第 2 部。雛形のものは今回の確かめのためだけ |
| ログ | 雛形の Swift は `os.Logger`（subsystem `com.jonghyunkim.nativetoolkit.probe1a9`、`notice`）に、通知の識別子・action・install の結果・起動の通知・Dialog の出入り（run loop の mode と呼び出し元の関数名）を出す。利用者の文字（アラートの文、Share の文、テキスト入力）とパスは出さない。見るときはこの subsystem に絞る |
