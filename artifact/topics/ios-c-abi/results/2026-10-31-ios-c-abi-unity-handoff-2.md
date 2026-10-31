# iOS の C ABI: `unity-native-plugin` の agent への申し送り（2 回目）

- 記録日: 2026-10-31
- 宛先: `unity-native-plugin`（別のリポジトリ）の agent
- 出した側: native-toolkit の `artifact/topics/ios-c-abi`（ブランチ `feature/NTKIT-18`。C ABI の設計書の第 1 部は commit `fbb03f70`、Swift の API の設計書は commit `ac83ad3b` で決定）
- 範囲: 設計書の第 1 部 10 章の **U-3・U-4・U-6・U-7**（通知）。1 回目（`2026-10-31-ios-c-abi-unity-handoff-1.md`。U-1・U-2・U-5・U-8・U-9・U-10）とは独立に進めてよい。P1-23 は 2026-10-31 に利用者が決め直し、2 回目も今出す
- 読むもの: 第 1 部（`designs/2026-10-31-ios-c-abi-c-abi-design.md`）の 1.4（入れる関数）と 5.12（通知の delegate）、Swift の API の設計書（`designs/2026-10-31-ios-c-abi-swift-api-design.md`）の 8.3・8.4、`agent-rules/device-testing.md`、1 回目の申し送りの 2 章・3 章（組み込みと C# の約束はそちらと同じ）

## 0. 最初に読むこと: 実機は利用者の私物

実機（iPhone XS、iOS 18.7.2）は試験用の端末ではなく、利用者の私物である。**native-toolkit の `agent-rules/device-testing.md` を読み、そのとおりにする**（あなたのリポジトリの agent にもそのまま当てはまる）。今回は通知を出し、通知センターやロックの画面に私物の通知と並んで出るので、1 回目より注意が要る。

1. **実機で何かを流す・入れる・動かす前は、毎回利用者に次の 4 つを知らせて、はっきり許可を得る**。許可は 1 回限りで、次の実行や別の操作に広げない
   1. 流すもの（この文書の U-n と、その中の手順の一覧）
   2. 端末に起きること（アプリの入れ替え、**通知の許可のダイアログ、通知のバナー、アプリを止めること・起動の繰り返し、Unity の通知パッケージを入れた版への入れ替え**など）
   3. 利用者にしてもらうこと（下の準備と、**バナーのタップ・長押し・アプリの終了など、利用者の手でしかできない操作**）
   4. 時間の見込み
2. **1 回ごとに聞く操作**: アプリの削除・入れ直し（通知の許可を初めからにするため、など）、端末の設定の変更（通知の設定を含む）、再起動、**通知センターや springboard を操作すること**。設定の App の中を操作する手順（`openSettingsFor`）は今回の範囲に入れていない
3. **準備は利用者に頼む**（agent から端末の設定を変えない）:
   - ロックを解除し、自動ロックを「なし」にし、給電する
   - **集中モードを入れ、通知を許すアプリを今回の Unity のテストのアプリだけにする**（私物の通知の割り込みで、バナーのタップがほかの通知に当たったり、テストが落ちたりした）
   - その集中モードの「ホーム画面 > 通知バッジを非表示」を**オフ**にする
   - 流す時間に、予定で始まる別の集中モード（睡眠など）が**重ならない**ようにする（入れ替わると、テストのアプリの通知が出なくなった）
   - 同じ表示名の古いアプリを消しておく
   - 流す直前に、`xcrun devicectl device info details` などの読むだけの操作で開発用の接続が使えることを確かめる
4. **端末を特定する値（ハードウェアの UDID、devicectl の識別子）を、ファイル・コミット・ログの写しに書かない**。伏せ字か環境変数にする
5. **実機の `.xcresult`、スクリーンショット、画面の録画には私物の画面（通知センター、ロックの画面）が入る**。結果を書き写したら消す。画面の階層のダンプを出さない。**ほかのアプリの通知の題・本文・アプリ名を記録に書かない**（テストのアプリの通知だけを書く）。端末のログ（`log stream`、Console）を読むときは、雛形の subsystem（`com.jonghyunkim.nativetoolkit.IosLibraryCApi`）と `[NTK-HANDOFF2]` だけに絞る
6. 雛形の `ntk_probe_raise_uikit_exception_async` は呼ばない（1 回目と同じ）

## 1. 渡すもの

| もの | 場所（native-toolkit の作業コピーの中。`ios/.gitignore` で無視される所） |
|---|---|
| `IosLibrary` の xcframework | `ios/Build/stage1a-handoff2/ios-native-toolkit-handoff2.xcframework` |
| `IosLibraryCApi` の xcframework（1 回目の関数 + 通知） | `ios/Build/stage1a-handoff2/ios-native-toolkit-capi-handoff2.xcframework` |
| 公開ヘッダー | `ios/Build/stage1a-handoff2/include/NativeToolkitC/`（`Common.h`、`Probe.h`、`ProbeDialog.h`、`ProbeShare.h`、`Notification.h`、`ProbeNotification.h`） |
| 組んだ時の記録 | `ios/Build/stage1a-handoff2/BUILD-INFO.txt` |
| Unity の `.mm` の見本（入れる関数を呼ぶ所） | `artifact/topics/ios-c-abi/results/probes/stage1a/handoff2/unity/NtkHandoff2Installer.mm` |
| 雛形のソースと、組むスクリプト | `artifact/topics/ios-c-abi/results/probes/stage1a/handoff2/`（`build.sh`、`gen_projects.rb`、`capi/`、`tests/`、`smoke/`）。Dialog と Share は `../handoff1/`、`Common.h` と `Probe.h` は `../entry/` のものをそのまま使う |

- **2 回目の xcframework は 1 回目の関数もすべて持つ**。1 回目の確かめも、この版で流し直してよい（名前が `-handoff2` に変わるだけ）。1 回目の版と同じアプリに混ぜない（同じ名前の framework になる）
- `ios/Build/` は git に入らないので、上の xcframework は利用者の Mac の作業コピーにだけある。雛形のソースも、利用者がコミットするまでは作業コピーにだけある
- 作り直し方（Xcode 26.6 が要る。`xcode-select` は変えない）:

```bash
cd <native-toolkit>
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer \
  artifact/topics/ios-c-abi/results/probes/stage1a/handoff2/build.sh
```

  `DEVELOPER_DIR` は手元の Xcode 26.6 の `Contents/Developer`（上は利用者の Mac での例）。Ruby の `xcodeproj` gem が要る。Unity のプロジェクトを組む Xcode は 26.3 以上ならどれでもよい（こちらで 26.3 で C の smoke を組めた。6 章）
- **これは雛形で、製品ではない**。`ntk_notification_install` だけは本番の名前と契約（第 1 部 1.4）で、ほかの `ntk_probe_notification_*` は今回の確かめのためだけの名前と形。本番は第 2 部で決める

## 2. 組み込み方

1 回目の申し送りの 2 章と同じ（Development Build を外した release の書き出し、UnityFramework に Do Not Embed でリンク、アプリに Embed & Sign、`CodeSignOnCopy`）。加えて:

1. **入れる関数を呼ぶ `.mm`**: `unity/NtkHandoff2Installer.mm` を `Assets/Plugins/iOS/` に置く（UnityFramework に入る）か、書き出したプロジェクトの UnityFramework のターゲットに足す。`#include <IosLibraryCApi/NativeToolkitC/Notification.h>` が通るよう、UnityFramework のターゲットが `ios-native-toolkit-capi-handoff2.xcframework` をリンクしていること（Framework Search Paths が付く）
2. 入れる時期は `.mm` の先頭の `NTK_HANDOFF2_INSTALL_AT` で選ぶ（1: `kUnityWillFinishLaunchingWithOptions`、2: `AppDelegateListener` の `didFinishLaunching:`、3: 両方）。値を変えたら組み直す。`AppDelegateListener.h`、`UnityRegisterAppDelegateListener`、`kUnityWillFinishLaunchingWithOptions` は Unity の書き出したプロジェクトの `Classes/PluginBase/` にある見込み（**こちらでは Unity のプロジェクトで組んでいない**。名前が違えば合わせて、結果に書く）
3. `.mm` は各時点で `UNUserNotificationCenter.delegate` のクラス名を `[NTK-HANDOFF2]` で `NSLog` に出す（U-4 で、どの delegate が前に立ったかを見るため）
4. **`ntk_notification_install` は main スレッドから、`UIApplicationMain` の後に呼ぶ**。main 以外では何もせずに 16（`WRONG_THREAD`）を返す。`+load` の中では呼ばない（見本の `+load` は受け手を登録するだけ）
5. U-4 では、Unity の通知パッケージ（`com.unity.mobile.notifications`）を Package Manager で入れた版と、入れない版を作る。パッケージは自分の `.mm` で `kUnityWillFinishLaunchingWithOptions` のときに delegate を上書きする（第 1 部 5.12.8）

## 3. ヘッダーと C# の宣言

雛形の公開シンボルは次の 23 個だけ（`nm -gU`。`BUILD-INFO.txt` にもある）: 1 回目の 17 個に、`ntk_notification_install`、`ntk_probe_notification_add_listener`、`ntk_probe_notification_listener_remove`、`ntk_probe_notification_get_launch_response`、`ntk_probe_notification_request_permission`、`ntk_probe_notification_schedule_marked` を足したもの。

```c
/* Notification.h: errors 0 NONE, 1 INVALID_PARAMETER, 2 NOT_INITIALIZED, 4 UNKNOWN, 8 NOT_FOREGROUND,
   10 PERMISSION_DENIED, 16 WRONG_THREAD (iOS only). Same names and numbers as Android. */
int32_t ntk_notification_install(void);                     /* main only, synchronous: 0 or 16 */

/* ProbeNotification.h */
typedef void (*ntk_probe_notification_event_fn)(void* user_data, int32_t kind,   /* 0 response (tap/action/text), 1 settings */
                                                ntk_string* notification_identifier, ntk_string* action_identifier,
                                                ntk_string* user_text, int32_t is_launch_response);   /* strings owned, may be NULL */
typedef void (*ntk_probe_notification_done_fn)(void* user_data, int32_t error, uint32_t system_code, int32_t granted);
typedef struct ntk_probe_notification_listener ntk_probe_notification_listener;

int32_t ntk_probe_notification_add_listener(ntk_probe_notification_event_fn callback, void* user_data,
                                            ntk_release_fn release, ntk_probe_notification_listener** out_listener);
void    ntk_probe_notification_listener_remove(ntk_probe_notification_listener* listener);
int32_t ntk_probe_notification_get_launch_response(ntk_string** out_identifier, ntk_string** out_action);
int32_t ntk_probe_notification_request_permission(ntk_probe_notification_done_fn callback, void* user_data, ntk_release_fn release);
int32_t ntk_probe_notification_schedule_marked(uint32_t seconds, const char* identifier, const char* title,
                                               ntk_probe_notification_done_fn callback, void* user_data, ntk_release_fn release);
```

約束（第 1 部 1.4、5.12。Swift の API の設計書 8.3・8.4）:

- **入れる関数**: main からだけ。戻る前にライブラリの delegate（proxy）を設定し終え、それまでの delegate を「前の delegate」にする。2 回目は、proxy が前に立っていれば何もせず、誰かに差し替えられていれば、差し替えた delegate を新しい前の delegate にして入れ直す。どちらも 0
- **見分け方**: ライブラリが予約した通知（userInfo にキー `com.jonghyunkim.nativetoolkit`、値 1）はライブラリが受け、前の delegate に見せない。印の無い通知は前の delegate に渡す。前の delegate が無いか、そのメソッドを実装していなければ、ライブラリが受ける（「誰も受けない」）
- **前面の表示**（`willPresent`）: ライブラリの通知は `banner, list, sound, badge` で表示する。イベントは出さない
- **イベント**: タップ・アクション（`BgAct`）・テキスト入力（`Reply`）を受けると、main で受け手のコールバックを呼ぶ。**受け手が 1 つも登録されていない間のイベントは保ち（32 件まで）、次に登録された受け手に、その登録の処理の中で（関数が戻った後に、main で）渡す**。system の completion は、イベントを渡すか保つかした後に呼ぶ
- **起動のきっかけ**（P1-22）: プロセスで最初の `didReceive` が、最初の `didBecomeActive` より前に来て、ライブラリが受けたものなら、それが起動のきっかけ。そのイベントは `is_launch_response = 1` で配られ、`ntk_probe_notification_get_launch_response` も同じ識別子と action を返す。前の delegate に渡したもの、入れたときに既にアプリが active だったときは無し（`NULL`）。値は最初の active の後に決まるので、**`didBecomeActive` の後に読む**（それより前は `NULL` が後で値に変わりうる）
- **起動のきっかけはイベントと取得の両方で届く**。C# で二重に処理しないこと（例: 起動のきっかけはイベントの `is_launch_response` だけで扱い、取得の関数は記録だけに使う）
- **入れる前**: 受け手の登録と起動のきっかけの取得は 2（`NOT_INITIALIZED`）を返す（入れる関数がこのプロセスで一度も成功していないとき）
- **循環**（P1-21）: 前の delegate が、ライブラリから受けた通知をライブラリへ**同期に**転送し直したときだけ止め、「誰も受けない」として扱う。非同期に転送し直す delegate は契約の外（振る舞いを定めない）
- `ntk_probe_notification_schedule_marked` は、印のある通知を `seconds` 秒後（0 はすぐ）に予約する。category に、アプリを前に出さないアクション「BgAct」（`options: []`）とテキスト入力「Reply」を付ける。ホストの category は保つ
- 雛形は proxy の 3 つのメソッドの入口を `os_log`（subsystem `com.jonghyunkim.nativetoolkit.IosLibraryCApi`、category `Notification`、`notice` の水準）に出す: `willPresent id=... library=...`、`didReceive id=... action=... library=...`、`openSettingsFor id=...`。U-7 はこれで見る

C#（1 回目の申し送りの 3 章の `NtkProbe` に足す。コールバックは同じく static、`[MonoPInvokeCallback]`、本体を `try` / `catch` で囲む）:

```csharp
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate void NotificationEventFn(IntPtr userData, int kind, IntPtr identifier, IntPtr action, IntPtr userText, int isLaunchResponse);
[UnmanagedFunctionPointer(CallingConvention.Cdecl)]
public delegate void NotificationDoneFn(IntPtr userData, int error, uint systemCode, int granted);

[DllImport(Lib)] public static extern int ntk_probe_notification_add_listener(NotificationEventFn callback, IntPtr userData, ReleaseFn release, out IntPtr listener);
[DllImport(Lib)] public static extern void ntk_probe_notification_listener_remove(IntPtr listener);
[DllImport(Lib)] public static extern int ntk_probe_notification_get_launch_response(out IntPtr identifier, out IntPtr action);
[DllImport(Lib)] public static extern int ntk_probe_notification_request_permission(NotificationDoneFn callback, IntPtr userData, ReleaseFn release);
[DllImport(Lib)] public static extern int ntk_probe_notification_schedule_marked(uint seconds, byte[] identifier, byte[] title,
                                                                                 NotificationDoneFn callback, IntPtr userData, ReleaseFn release);

public static readonly NotificationEventFn NotificationEvent = OnNotificationEvent;
public static readonly NotificationDoneFn NotificationDone = OnNotificationDone;

[MonoPInvokeCallback(typeof(NotificationEventFn))]
static void OnNotificationEvent(IntPtr userData, int kind, IntPtr identifier, IntPtr action, IntPtr userText, int isLaunchResponse)
{
    try
    {
        Probe.Log($"event kind={kind} id={TakeString(identifier) ?? "null"} action={TakeString(action) ?? "null"} " +
                  $"text-length={(TakeString(userText)?.Length ?? -1)} launch={isLaunchResponse} frame={Time.frameCount}");
    }
    catch (Exception e) { Debug.LogException(e); }
}

[MonoPInvokeCallback(typeof(NotificationDoneFn))]
static void OnNotificationDone(IntPtr userData, int error, uint systemCode, int granted)
{
    try { Probe.Log($"done tag={userData.ToInt64()} error={error} granted={granted}"); }
    catch (Exception e) { Debug.LogException(e); }
}
```

- テキスト入力の本文（`userText`）は利用者が打った文字なので、記録には長さだけを書く（P1-18 の秘密の値と同じ扱い）
- アプリが背景にいる間やコールドスタートの直後のログを後で読めるよう、`Probe.Log` は `Application.persistentDataPath` のファイルにも時刻つきで追記し、画面にも出す形にすると U-3・U-6 が楽になる

## 4. 確かめること

すべて Release の構成で組んだアプリで、実機で行う。**毎回 0 章の許可を得る**。最初に 1 回、`ntk_probe_notification_request_permission` を呼んで通知を許可する（許可のダイアログが出る。利用者が「許可」を押す）。

### U-3: 入れる時期と、コールドスタートのタップ（D-4・P1-22・1a-13）

| 項目 | 内容 |
|---|---|
| 手順 | Unity の通知パッケージを**入れない**版で、`NTK_HANDOFF2_INSTALL_AT` を 1 と 2 のそれぞれで組んで行う。C# の最初のシーンの `Start()` で `ntk_probe_notification_add_listener` を登録し、`OnApplicationFocus(true)` の 1 秒後に `ntk_probe_notification_get_launch_response` を呼んで記録する。(1) アプリを起動し、ボタンから `ntk_probe_notification_schedule_marked(10, "u3-cold", "U-3 cold", ...)` を呼ぶ。(2) **利用者に**アプリを終了してもらう（App スイッチャーで上に払う）。(3) 10 秒後に出るバナーを、**利用者に**タップしてもらう（アプリがコールドスタートする）。(4) 起動した画面のログを見る |
| 合格の条件 | どちらかの時期で: `install at ... -> 0`、`event kind=0 id=u3-cold action=com.apple.UNNotificationDefaultActionIdentifier launch=1` が 1 回だけ（`Start()` の登録の後に）届く。起動のきっかけの取得が `u3-cold` を返す |
| 記録すること | 時期ごとの結果（届いたか、`launch` の値、取得の値）。`[NTK-HANDOFF2]` の delegate のクラス名の並び（どの時点で何が前の delegate か）。可能なら、Unity 6000.4 の起動の順（`kUnityWillFinishLaunchingWithOptions`、`didFinishLaunching`、scene の `willConnectTo` の前後。`.mm` に `NSLog` を足して見てよい） |
| 結果で変わる決定 | 間に合わなければ 1a-13 を決め直し、ホストから応答を渡してもらう関数を足す。D-4 の期限の書き方。P1-22 |

シミュレーターの雛形のアプリでは、`willFinishLaunching` で入れ、2 秒後に受け手を登録して、`launch=1` のイベントと取得の値が来た（6 章）。

### U-4: Unity の通知パッケージとの共存（D-7・P1-21）

| 項目 | 内容 |
|---|---|
| 手順 | Unity の通知パッケージを**入れた**版で行う。(a) `.mm` の `+load` と `didFinishLaunching` の `[NTK-HANDOFF2]` のログで、各時点の delegate のクラス名を記録し、どちらが後に入ったか（どちらが前に立っているか）を見る。(b) `NTK_HANDOFF2_INSTALL_AT` を 1・2・3 で組み、それぞれで: パッケージの C# の API で予約した通知と、`ntk_probe_notification_schedule_marked` で予約した通知を出し、どちらも、アプリが前面のとき（バナーが出るか）と、ホームに戻ってタップしたとき（どちらの受け手に届くか）を見る。(c) ライブラリが後に入る形（2 か 3）で、U-3 のコールドスタートをもう一度行う。(d) リンクの順（UnityFramework の Link Binary With Libraries の並び、`.mm` の並び）を入れ替えて、(a) の結果が変わるかを見る。(e) パッケージ無しの版で、Unity の本体が delegate を設定するか（(a) のログで `nil` 以外が出るか）も記録する |
| 合格の条件 | 両方の通知が自分の受け手に届く順が 1 つ以上あり、その順をホストの側で固定できる（例: 2 の時期なら必ずライブラリが後）。入れ直し（3）を使う順なら、**パッケージの delegate が前の delegate へ同期に転送していること**（ログで、パッケージの通知のタップが proxy の `didReceive` → パッケージの順に、同じ時刻に出る）。非同期なら、その順は契約の外 |
| 記録すること | 順ごとの (a)〜(c) の結果、`os_log` の proxy の行（`library=` の値）、パッケージの通知がパッケージに、ライブラリの通知がライブラリに届いたか。アプリが落ちたり固まったりしたか（循環の兆し） |
| 結果で変わる決定 | 成り立たなければ、マニュアルに「共存できない」と書くか、1a-13 の関数を足す。第 1 部 5.12.8 の表。P1-21 の契約の書き方 |

### U-6: 背景のアクション（BgAct）と completion の時期（1a-12・1a-8）

| 項目 | 内容 |
|---|---|
| 手順 | パッケージ無しの版で。(1) 受け手を登録したままの状態で、`ntk_probe_notification_schedule_marked(8, "u6-a", "U-6 A", ...)` を呼び、ホームに戻る。バナーを**利用者に**長押ししてもらい、「BgAct」を押してもらう（アプリは前に出ない）。30 秒ほど待ってからアプリを開き、ログを見る。(2) アプリを終了した状態から同じことをする（アプリは背景で起動する。C# の `Start()` は動かない見込みなので、イベントは保たれ、次に前面に来たときに届くかを見る）。(3) 可能なら、テキスト入力「Reply」でも (1) を行う（本文は記録に書かない） |
| 合格の条件 | (1) `event kind=0 id=u6-a action=ntk.probe.bg` が C# に 1 回届く（アプリが背景のまま）。(2) 次に前面に来て受け手が登録されたときに 1 回届く。どちらも、アプリが途中で止められない |
| 記録すること | 届いた時刻とフレーム、アプリの状態（`Application.isFocused` など）、`persistentDataPath` のファイルの記録。(2) で、背景で起動したプロセスがどのくらい生きていたか（分かれば）。前の delegate が completion を呼ばない・遅れて呼ぶ場合（パッケージの delegate など）に実機で止められる時期は、分かる範囲で書く（このためだけに新しい delegate は作らなくてよい） |
| 結果で変わる決定 | 1a-12（completion を呼ぶ時期）、1a-8（watchdog を入れない） |

### U-7: 後ろに移った直後の `willPresent`（第 1 部 5.12.3）

| 項目 | 内容 |
|---|---|
| 手順 | Mac で `log stream --style compact --level debug --predicate 'subsystem == "com.jonghyunkim.nativetoolkit.IosLibraryCApi"'`（端末を選ぶ。端末の識別子は記録に書かない）を見ながら、`ntk_probe_notification_schedule_marked(2, "u7-a", "U-7 A", ...)` を呼んで、**すぐに**ホームに戻る。予約の秒数を 1・2・3・5 秒で繰り返す |
| 合格の条件 | 合否ではない。結果を記録する |
| 記録すること | 秒数ごとに、`willPresent id=u7-... library=true` の行が出たか（出たなら、ホームに戻ってから何秒後に出た通知まで呼ばれたか）、バナーが出たか。シミュレーターでは、後ろに移ってから約 3 秒の間 `willPresent` が呼ばれた（1a delegate の記録） |
| 結果で変わる決定 | 第 1 部 5.12.3 の `willPresent` の説明 |

## 5. 結果の返し方

1 回目と同じ。あなたのリポジトリに結果のファイルを書き、次の要約をこちらへの返事（利用者を通す）に貼る。実機の `.xcresult`、スクリーンショット、録画、端末のログの写しは、書き写した後に消す。

```
handoff-2 results (unity-native-plugin, <commit of your repo>)
probe: built <built>, commit <commit>   Unity 6000.4.2f1   Xcode <version>   iPhone XS / iOS <version>
U-3: at=1 -> install=<code> cold-tap event=<launch=1 once|none|...> getter=<id|null>   at=2 -> ...   startup-order=<...>
U-4: front-delegate(no reinstall)=<class>  at=1/2/3: package-notif=<to package|to library|lost>  library-notif=<...>  cold-tap(at=2)=<ok|...>  link-order-changes=<yes|no>  unity-sets-delegate=<yes|no>  package-forwards=<sync|async|no>
U-6: (1) bg action event=<once|none> state=<bg|...>  (2) from terminated=<delivered on next foreground|lost>  killed=<no|yes after s>
U-7: 1s=<willPresent yes/no, banner yes/no>  2s=<...>  3s=<...>  5s=<...>
blocked: <anything that could not be done, and why>
```

## 6. こちらで確かめたこと（シミュレーターだけ）

確かめた雛形は 1 章の場所のもの（commit `ac83ad3b` の上の、まだコミットしていない雛形のソースから組んだ）。実機には触れていない。手順は `results/probes/stage1a/handoff2/run.sh`。

| 確かめたこと | 結果 |
|---|---|
| 公開シンボル | 3 つのアーキテクチャとも 3 章の 23 個だけ。`_ntk_` 以外は 0 |
| 中身 | capi の framework は `Headers/NativeToolkitC/` の 6 つのヘッダーと `Modules/module.modulemap` だけ。Swift のモジュールと `-Swift.h` は無い。署名は 1 回目と同じ（実機のスライスは無し、シミュレーターはリンカーの ad-hoc だけ） |
| 警告 | capi の archive で 0 件 |
| C の smoke（`smoke/`。`willFinishLaunching` で入れる C / Objective-C のアプリ） | Xcode 26.6 と **26.3** の両方で警告 0 件で組めた。26.3 で組んだものを iPhone 17 / iOS 26.2 で動かし `failures=0`: 別のスレッドからの入れる関数は 16、main からは 0、2 回目も 0。受け手の登録と解除（`release` は main で 1 回、関数が戻った後）。起動のきっかけは `NULL` |
| XCTest（8 件） | iPhone 17 / iOS 26.2 で通常と TSan で通った（下の表）。保ちを一時的に壊すと 2 件が落ちることを確かめ、元に戻した |
| UI テスト（7 件。実際の通知をバナーからタップする） | 同じ 2 通りで通った（下の表） |

| 場面 | 結果 |
|---|---|
| 入れる前の受け手の登録と取得 | どちらも 2（`NOT_INITIALIZED`）。登録のハンドルの出力は `NULL`、`release` は戻る前に 1 回。引数の誤り（コールバックが `NULL`）は 1（`INVALID_PARAMETER`）が先 |
| 別のスレッドからの入れる関数 | 5 回とも 16（`WRONG_THREAD`）ですぐ返り（0.05〜6 ms）、delegate は変わらない。main からは 0 で、戻った時点で delegate が proxy。2 回目も 0 |
| 差し替えの後の入れ直し | ホストの delegate に差し替えた後に入れ直すと、proxy が前に立ち、`openSettingsFor(nil)` はホストの delegate に渡った（ライブラリのイベントにはならない） |
| 循環（`openSettingsFor`。単体テスト） | ホストが proxy を前の delegate にして差し替え、入れ直した（proxy → ホスト → proxy）。ホストは 1 回だけ呼ばれ、ライブラリのイベントが 1 回出た。再帰しない |
| 循環（実際の通知。UI テスト） | 前面: ホストの `willPresent` が 1 回呼ばれ、バナーは出た（ライブラリの表示の選択肢）。タップ: ホストの `didReceive` が 1 回、ライブラリのイベントが 1 回（`launch=0`）。アプリは落ちない |
| 受け手が登録される前のタップ | 受け手を 12 秒後に登録するアプリで、ホームからバナーをタップ。イベントは保たれ、受け手の登録の後に 1 回届いた（`launch=0`。アプリは既に active だったので起動のきっかけではない） |
| 受け手を外した後のイベント | 外した後のイベント 2 つは保たれ、次の受け手の登録の後に 2 つとも届いた。関数の中では呼ばれない |
| 保つ件数 | 受け手の無い間に 40 件来ると、次の受け手が受け取ったのは最後の 32 件 |
| ホストの通知 | ホストの delegate があるとき、印の無い通知のタップはホストに渡り、ライブラリのイベントにはならない。ホストの delegate が無いときは、ライブラリが受けてイベントになった（誰も受けない） |
| コールドスタート | アプリを止めてからバナーをタップ。`willFinishLaunching`（scene は inactive）で入れ、2 秒後に受け手を登録した。起動のきっかけの取得は `cold1` と既定のアクション、イベントは `launch=1` で 1 回 |
| 別のスレッドからの受け手の解除 | `release` は main で 1 回 |

## 7. 渡せなかったもの・注意

| もの | 状態 |
|---|---|
| Unity での `.mm` の組み込み（2 章） | Unity の書き出すプロジェクトの一般の形から書いた。**こちらでは Unity のプロジェクトで組んでいない**。`AppDelegateListener.h` などの名前が違えば合わせて、結果に書く |
| C# の宣言（3 章） | IL2CPP で組んで動かしてはいない |
| 実機での動き | こちらはシミュレーターだけ。背景のアクション（U-6）とコールドスタート（U-3）は、実機の OS の振る舞い（背景で起動したプロセスの寿命、watchdog）がシミュレーターと違いうる |
| `openSettingsFor` の実機での確かめ | 範囲に入れていない（設定の App の中を操作するため。1b でこちらが確かめる） |
| 本番の関数（第 2 部）と、`IosLibrary` の本番の口（1b） | 下の「雛形が本番と違うところ」 |

雛形が本番と違うところ（**1b で `IosLibrary` に正しく作るもの**）:

- proxy・router・イベントの口・起動のきっかけ・`CompletionOnce` を、雛形は capi の中（`capi/Sources/Stand1b/NotificationDelegateProxy.swift`）に 1 つのクラスで持つ。本番は Swift の API の設計書 8.3・8.4 のとおり `IosLibrary` に `NotificationDelegateProxy`（状態は `Mutex`）、値型の `NotificationDelegateRouter`、`NotificationEventHub`、`installDelegate()` / `isDelegateInstalled` として作り、capi の `ntk_notification_install` はそれを呼ぶだけにする。設計書 13.1 の単体テスト（転送の組み合わせの表、包みを背景のキューから呼ぶ、循環の各メソッド）もそこで書く
- イベントの口は、設計書 8.4.2 の「受け手が渡す途中で自分を外した」ときの残りの渡し方を持たない。ログの規則（捨てたときの 1 回目だけ `.info`）も無い
- KVO での差し替えの見張り（ログだけ）、`setup()` の deprecated、今の受け手（S-P8）との関係、`foregroundPresentationOptions` の設定の口は無い（表示の選択肢は既定の固定）
- 印のある通知の予約は雛形の関数（`schedule_marked`）だけで、`show`・`update` の印、利用者の userInfo の予約したキーの検査（P1-9 の `INVALID_PARAMETER`）、イベント・一覧から印を外す処理は無い（イベントは userInfo を渡さない）
- 権限の要求は雛形の形（前面の判定つき）。権限が拒まれたときは 10（`PERMISSION_DENIED`）
- C の受け手は 1 つの関数で 2 種類（タップなどと設定の画面）を受ける。本番の形（種類ごとの登録か、ハンドルの型）は第 2 部で決める
- proxy の `os_log` は確かめのための `notice` の水準で、通知の識別子を public で出す（雛形の通知の識別子だけを想定）。本番は P1-18 の規則（利用者の値は `.private`）にする
