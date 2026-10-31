# iOS の C ABI: `unity-native-plugin` の agent への申し送り（1 回目）

- 記録日: 2026-10-31
- 宛先: `unity-native-plugin`（別のリポジトリ）の agent
- 出した側: native-toolkit の `artifact/topics/ios-c-abi`（ブランチ `feature/NTKIT-18`。C ABI の設計書の第 1 部は commit `fbb03f70` で決定）
- 範囲: 設計書の第 1 部 10 章の **U-1・U-2・U-5・U-8・U-9・U-10**（P1-23 の 1 回目）。通知の U-3・U-4・U-6・U-7 は 2 回目の申し送りで頼む（通知の雛形がまだ無い）
- 読むもの: `artifact/topics/ios-c-abi/designs/2026-10-31-ios-c-abi-c-abi-design.md` の 1 章（スレッドと完了の規則）と 10 章、`agent-rules/device-testing.md`

## 0. 最初に読むこと: 実機は利用者の私物

実機（iPhone XS、iOS 18.7.2）は試験用の端末ではなく、利用者の私物である。**native-toolkit の `agent-rules/device-testing.md` を読み、そのとおりにする**。あなたのリポジトリの agent にも、この決まりがそのまま当てはまる（同じ文書の冒頭）。要点:

1. **実機で何かを流す・入れる・動かす前は、毎回利用者に次の 4 つを知らせて、はっきり許可を得る**。許可は 1 回限りで、次の実行や別の操作に広げない
   1. 流すもの（この文書の U-n と、その中の手順の一覧）
   2. 端末に起きること（アプリの入れ替え、アラート・共有のシートの表示、起動と終了の繰り返し、ASan の版の入れ替えなど）
   3. 利用者に事前にしてもらうこと（下の準備）
   4. 時間の見込み
2. **1 回ごとに聞く操作**: アプリの削除・入れ直し、端末の設定の変更、再起動。**共有のシートから実在のアプリ（メッセージ、メール、SNS など）へ送りうる操作はしない**（U-5 では、シートを出して閉じるだけにする）。写真・「ファイル」への保存もしない
3. **準備は利用者に頼む**（agent から端末の設定を変えない）: ロックを解除し、自動ロックを「なし」にし、給電する。**集中モードを入れ、通知を許すアプリを試すアプリだけにする**（私物の通知の割り込みでテストが落ちたことがある）。その集中モードの「通知バッジを非表示」をオフにする。流す時間に、予定で始まる別の集中モード（睡眠など）が重ならないようにする。同じ表示名の古いアプリを消しておく。流す直前に、`xcrun devicectl device info details` などの読むだけの操作で開発用の接続が使えることを確かめる
4. **端末を特定する値（ハードウェアの UDID、devicectl の識別子）を、ファイル・コミット・ログの写しに書かない**（両方のリポジトリとも公開している）。伏せ字か環境変数にする
5. **実機の `.xcresult` とスクリーンショットには私物の画面が入る**。結果を書き写したら消す。画面の階層のダンプを出さない。共有のシートの共有先の名前（私物のアプリや連絡先）を記録に書かない
6. この雛形の `ntk_probe_raise_uikit_exception_async` はアプリをわざと落とす関数で、今回の確かめには使わない。実機では呼ばない
7. `ntk_probe_clipboard_read_text_async` は、雛形の名前付きの pasteboard（`com.jonghyunkim.nativetoolkit.stage1a.probe`）だけを読み、利用者の普通のクリップボードには触れない。その pasteboard を作らずに呼ぶと、すぐに `NTK_PROBE_ERROR_READ_FAILED`（6）で完了する。U-1 ではこの使い方をする（クリップボードの中身に触れずに、コールバックと `release` を確かめられる）。それでも許可を得るときの一覧には書く

## 1. 渡すもの

| もの | 場所（native-toolkit のリポジトリの中。`ios/.gitignore` で無視される所） |
|---|---|
| `IosLibrary` の xcframework（Swift の API。今のリポジトリの `ios/IosLibrary` をそのまま組んだもの） | `ios/Build/stage1a-handoff1/ios-native-toolkit-handoff1.xcframework` |
| `IosLibraryCApi` の xcframework（C ABI の雛形） | `ios/Build/stage1a-handoff1/ios-native-toolkit-capi-handoff1.xcframework` |
| 公開ヘッダー（xcframework の `Headers/NativeToolkitC/` と同じもの） | `ios/Build/stage1a-handoff1/include/NativeToolkitC/` |
| 組んだ時の記録（Xcode の版、commit、公開シンボルの一覧） | `ios/Build/stage1a-handoff1/BUILD-INFO.txt` |
| ASan で組んだ同じ 2 つ（U-10 だけで使う） | `ios/Build/stage1a-handoff1/asan/` |
| 雛形のソースと、組むスクリプト | `artifact/topics/ios-c-abi/results/probes/stage1a/handoff1/`（`build.sh`、`gen_projects.rb`、`capi/`、`tests/`、`smoke/`）。`Common.h` と `Probe.h` は `../entry/capi/include/NativeToolkitC/` |

`ios/Build/` は git に入らないので、上の xcframework は**利用者の Mac の native-toolkit の作業コピーにだけある**（同じ Mac から読む）。無ければ下の手順で作り直す。雛形のソースも、利用者がコミットするまではブランチ `feature/NTKIT-18` の作業コピーにだけある。

どちらの xcframework も `ios-arm64` と `ios-arm64_x86_64-simulator` のスライスを持ち、**署名していない**（D-18。アプリに埋め込むときに、あなたの側の証明書で署名し直される。それを U-2 で確かめる）。最小 iOS は 18.0。`IosLibraryCApi` は `@rpath/IosLibrary.framework` に依存するので、**2 つとも同じ組で埋め込む**（P1-19）。

**作り直し方**（native-toolkit のリポジトリで。Xcode 26.6 が要る。`xcode-select` は変えない）:

```bash
cd <native-toolkit>
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer \
  artifact/topics/ios-c-abi/results/probes/stage1a/handoff1/build.sh          # 普通の版
DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer \
  artifact/topics/ios-c-abi/results/probes/stage1a/handoff1/build.sh --asan   # ASan の版（asan/ に出る）
```

- `DEVELOPER_DIR` は、手元の Xcode 26.6 の `Contents/Developer` のパスにする（上は利用者の Mac での置き場所の例）。スクリプトは Swift 6.3 でなければ止まる（雛形は `@c @implementation` を使い、Swift 6.2 では組めない）
- Ruby の `xcodeproj` gem が要る（プロジェクトを作るため）
- 出力の名前は毎回同じで、上書きする。`BUILD-INFO.txt` の commit で、どの版を使ったかを結果に書く
- **Unity のプロジェクトを組む側の Xcode は 26.3 以上ならどれでもよい**（C ABI だけを使うので。D-16）。こちらで Xcode 26.3 で C の smoke を組めることを確かめた（6 章）

**これは雛形で、製品ではない**。関数の名前（`ntk_probe_*`）、引数、エラーの番号は、設計書の第 2 部で本番の形に決め直す。C# の包みを本番のつもりで作り込まない。

## 2. 組み込み方（Unity 6000.4.2f1 の書き出した Xcode プロジェクトに、手で入れる）

今の `unity-native-plugin` のビルドの処理（`PreBuildProcessor` / `PostBuildProcessor`）は `unity-ios-native-toolkit-` で始まる 1.x の xcframework を前提にし、development ビルドでは埋め込まないので、今回は使わない。

1. Unity 6000.4.2f1 で、**Development Build を外した**（release の）iOS ビルドを書き出す。C# の宣言（3 章）と、確かめに使う小さなシーン（4 章）を入れておく。1.x の `unity-ios-native-toolkit-*.xcframework` と `ios-native-toolkit-1.*.xcframework` は入れない（同じ名前の `IosLibrary.framework` を 2 つの版で埋め込めない。D-12）
2. 書き出した `Unity-iPhone.xcodeproj` を Xcode で開き、2 つの xcframework をプロジェクトに足す（コピーしてよい）
3. **UnityFramework のターゲット**: General の「Frameworks and Libraries」に `ios-native-toolkit-capi-handoff1.xcframework` を足し、**Do Not Embed** にする（`DllImport("__Internal")` の関数は、IL2CPP のコードと一緒に UnityFramework にリンクされる）。`ios-native-toolkit-handoff1.xcframework` も Do Not Embed で足してよい（無くてもリンクは通る見込み）
4. **Unity-iPhone（アプリ）のターゲット**: 2 つとも「Frameworks, Libraries, and Embedded Content」に足し、**Embed & Sign** にする。Build Phases の「Embed Frameworks」に 2 つが入り、`Code Sign On Copy` に印があることを確かめる（`project.pbxproj` で `ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, )`）
5. アプリの `Runpath Search Paths` に `@executable_path/Frameworks` があることを確かめる（Unity の既定にある見込み）。`IosLibraryCApi` 自身の rpath は `/usr/lib/swift`、`@executable_path/Frameworks`、`@loader_path/Frameworks`
6. 署名はあなたの側の Team（Automatic でよい）。Release の構成で組む

組んだ後、端末に入れる前に（許可は要らない。Mac の上の操作）: アプリの `.app/Frameworks/` に `IosLibrary.framework` と `IosLibraryCApi.framework` があり、どちらにも `Headers/` と `Modules/` が無い（`RemoveHeadersOnCopy`）こと。

## 3. ヘッダーと C# の宣言

雛形の公開シンボルは次の 17 個だけ（`nm -gU`。`BUILD-INFO.txt` にもある）:

```
ntk_version  ntk_last_system_code
ntk_string_data  ntk_string_size  ntk_string_free
ntk_bytes_data  ntk_bytes_size  ntk_bytes_free
ntk_string_list_count  ntk_string_list_at  ntk_string_list_free
ntk_probe_echo  ntk_probe_clipboard_read_text_async  ntk_probe_raise_uikit_exception_async
ntk_probe_dialog_show_alert  ntk_probe_dialog_cancel  ntk_probe_share_text
```

ヘッダーは `include/NativeToolkitC/` の `Common.h`（Android の `Common.h` と宣言が同じ）、`Probe.h`、`ProbeDialog.h`、`ProbeShare.h`。今回使う関数の C の形:

```c
uint32_t ntk_version(void);                                   /* 0x020000 */
const char* ntk_string_data(const ntk_string* s);
void ntk_string_free(ntk_string* s);
typedef void (*ntk_release_fn)(void* user_data);

/* Probe.h: the callback test of U-1 (READ_FAILED = 6 when the probe pasteboard does not exist) */
typedef void (*ntk_probe_text_fn)(void* user_data, uint64_t request_id, int32_t error,
                                  uint32_t system_code, ntk_string* text);   /* text is owned by the receiver */
int32_t ntk_probe_clipboard_read_text_async(ntk_probe_text_fn callback, void* user_data,
                                            ntk_release_fn release, uint64_t* out_request_id);

/* ProbeDialog.h: errors 0 NONE, 1 INVALID_PARAMETER, 6 CANCELED, 7 CANCELED_BY_SYSTEM, 8 NOT_FOREGROUND, 10 SHOW_FAILED;
   button 0 POSITIVE, 1 NEGATIVE, -1 none (error is not NONE) */
typedef void (*ntk_probe_dialog_done_fn)(void* user_data, uint64_t request_id, int32_t error,
                                         uint32_t system_code, int32_t button);
int32_t ntk_probe_dialog_show_alert(const char* title, const char* message,
                                    const char* positive_text, const char* negative_text,  /* NULL: "OK" / no button */
                                    ntk_probe_dialog_done_fn callback, void* user_data,
                                    ntk_release_fn release, uint64_t* out_request_id);
int32_t ntk_probe_dialog_cancel(uint64_t request_id);         /* always 0; completion CANCELED, then release */

/* ProbeShare.h: errors 0 NONE, 1 INVALID_PARAMETER, 4 UNKNOWN, 6 NOT_FOREGROUND, 7 EMPTY_CONTENT. Not cancellable. */
typedef void (*ntk_probe_share_done_fn)(void* user_data, int32_t error, uint32_t system_code,
                                        int32_t completed, ntk_string* activity_type);   /* activity_type owned, may be NULL */
int32_t ntk_probe_share_text(const char* text, ntk_probe_share_done_fn callback, void* user_data, ntk_release_fn release);
```

約束（設計書の第 1 部 1.3。Android と同じ）:

- どの関数もどのスレッドから呼んでもよく、main を待たない。Unity の C# は main で動くので、**完了と `release` は必ず関数が戻った後に**、main で来る
- 受け付けた（戻り値 0）要求は、完了がちょうど 1 回、その後に `release`（`NULL` でなければ）がちょうど 1 回来る。入口で拒んだ（戻り値が 0 でない）ときは、完了は来ず、`release` が**関数が戻る前に**呼ばれる
- 完了と要求の対応付けは `user_data` で行う（出力の要求の ID が書かれる前に完了が来うる契約。Unity では起きないが、Android と同じ C# にするため）
- コールバックで渡す `ntk_string*` は所有権ごと渡す。受け手が `ntk_string_free` する
- 文字列は NUL で終わる UTF-8。不正な UTF-8 は `INVALID_PARAMETER`
- **コールバックの本体は必ず `try` / `catch` で囲む**（例外を C に出したときの振る舞いは定めない。P1-16。U-9 で実際を記録する）
- Dialog の前面: アプリの key window を持つ前面の scene（active か inactive）の、最上位の ViewController の上に出す（P1-11）。移り変わりの途中なら 1 回だけ待って出し直す（P1-12）。同じフレームで 2 つ呼べば 2 つとも出る（2 つ目が上）
- Share の前面: 雛形は `IosLibrary` の `IosShareManager` を呼ぶ。こちらは今の `IosLibrary` の探し方（`foregroundActive` だけ）なので、scene が inactive の間は `NOT_FOREGROUND` になる。**外から閉じられた Share の完了は来ない**（6 章。1b で直す）

C#（IL2CPP。雛形の確かめのための最小の形。名前は自由に変えてよい）:

```csharp
using System;
using System.Runtime.InteropServices;
using System.Text;
using AOT;
using UnityEngine;

public static class NtkProbe
{
    const string Lib = "__Internal";

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void ReleaseFn(IntPtr userData);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void TextFn(IntPtr userData, ulong requestId, int error, uint systemCode, IntPtr text);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void DialogDoneFn(IntPtr userData, ulong requestId, int error, uint systemCode, int button);
    [UnmanagedFunctionPointer(CallingConvention.Cdecl)] public delegate void ShareDoneFn(IntPtr userData, int error, uint systemCode, int completed, IntPtr activityType);

    [DllImport(Lib)] public static extern uint ntk_version();
    [DllImport(Lib)] public static extern uint ntk_last_system_code();
    [DllImport(Lib)] public static extern IntPtr ntk_string_data(IntPtr s);
    [DllImport(Lib)] public static extern UIntPtr ntk_string_size(IntPtr s);
    [DllImport(Lib)] public static extern void ntk_string_free(IntPtr s);
    [DllImport(Lib)] public static extern int ntk_probe_clipboard_read_text_async(TextFn callback, IntPtr userData, ReleaseFn release, out ulong requestId);
    [DllImport(Lib)] public static extern int ntk_probe_dialog_show_alert(byte[] title, byte[] message, byte[] positiveText, byte[] negativeText,
                                                                         DialogDoneFn callback, IntPtr userData, ReleaseFn release, out ulong requestId);
    [DllImport(Lib)] public static extern int ntk_probe_dialog_cancel(ulong requestId);
    [DllImport(Lib)] public static extern int ntk_probe_share_text(byte[] text, ShareDoneFn callback, IntPtr userData, ReleaseFn release);

    /// NUL-terminated UTF-8; null stays NULL.
    public static byte[] Utf8(string s) => s == null ? null : Encoding.UTF8.GetBytes(s + "\0");

    public static string TakeString(IntPtr handle)   // reads and frees an owned ntk_string*
    {
        if (handle == IntPtr.Zero) return null;
        try { return Marshal.PtrToStringUTF8(ntk_string_data(handle)); }
        finally { ntk_string_free(handle); }
    }

    // The delegates are static fields so that IL2CPP keeps them; the bodies are static methods.
    public static readonly ReleaseFn Release = OnRelease;
    public static readonly TextFn Text = OnText;
    public static readonly DialogDoneFn DialogDone = OnDialogDone;
    public static readonly ShareDoneFn ShareDone = OnShareDone;

    [MonoPInvokeCallback(typeof(ReleaseFn))]
    static void OnRelease(IntPtr userData)
    {
        try { Probe.Log($"release tag={userData.ToInt64()} frame={Time.frameCount}"); }
        catch (Exception e) { Debug.LogException(e); }
    }

    [MonoPInvokeCallback(typeof(TextFn))]
    static void OnText(IntPtr userData, ulong requestId, int error, uint systemCode, IntPtr text)
    {
        try { Probe.Log($"text tag={userData.ToInt64()} id={requestId} error={error} system={systemCode} text={TakeString(text) ?? "null"} frame={Time.frameCount}"); }
        catch (Exception e) { Debug.LogException(e); }
    }

    [MonoPInvokeCallback(typeof(DialogDoneFn))]
    static void OnDialogDone(IntPtr userData, ulong requestId, int error, uint systemCode, int button)
    {
        try { Probe.Log($"dialog tag={userData.ToInt64()} id={requestId} error={error} button={button} frame={Time.frameCount}"); }
        catch (Exception e) { Debug.LogException(e); }
    }

    [MonoPInvokeCallback(typeof(ShareDoneFn))]
    static void OnShareDone(IntPtr userData, int error, uint systemCode, int completed, IntPtr activityType)
    {
        try { TakeString(activityType); Probe.Log($"share tag={userData.ToInt64()} error={error} completed={completed} frame={Time.frameCount}"); }
        catch (Exception e) { Debug.LogException(e); }
    }
}
```

- `user_data` は今回は整数の印（`new IntPtr(1)` など）でよい。本番の包み（2c）は、登録ごとに別の `user_data` を表に入れる形にする（Android の知見 3 章）
- `Probe.Log` は、画面の文字と `Debug.Log` の両方に出す小さな関数（自由に作る）。**どのスレッドで来たか**は、`Thread.CurrentThread.ManagedThreadId` を起動の時に覚えた値と比べて書く（Unity の C# は main で動くので、同じ値なら main）
- `byte[]` は呼び出しの間だけ固定され、`NULL` は `null` で渡せる。`[MarshalAs(UnmanagedType.LPUTF8Str)] string` を使ってもよい（IL2CPP での動きを確かめていないので、上の形を勧める）

## 4. 確かめること

すべて **Release の構成**で組んだアプリで行う。実機で行う手順の前には、0 章の許可を毎回得る。

### U-1: 組み込みと、`ntk_version()`・コールバック（D-9）

| 項目 | 内容 |
|---|---|
| 手順 | 2 章のとおりに入れて組み、実機で起動する。ボタンなどから順に: (1) `ntk_version()` を表示する。(2) `ntk_probe_clipboard_read_text_async(Text, new IntPtr(1), Release, out id)` を呼び、戻り値・`id`・呼んだ時の `Time.frameCount` を記録する（pasteboard は作らない。0 章の 7）。(3) `ntk_probe_dialog_show_alert(Utf8("U-1"), Utf8("Tap Yes"), Utf8("Yes"), Utf8("No"), DialogDone, new IntPtr(2), Release, out id)` を呼び、出たアラートの「Yes」を押す |
| 合格の条件 | (1) が `0x020000`（131072）。(2) 戻り値 0、続いて `error=6`（READ_FAILED）の完了が 1 回、その後に `release tag=1` が 1 回。(3) `error=0 button=0` の完了が 1 回、その後に `release tag=2` が 1 回。どれも main で、呼んだフレームより後（関数が戻った後）に来る。起動や呼び出しでアプリが落ちない（`dyld: Library not loaded` などが無い） |
| 記録すること | 上の値と、来た順。組み込みで手間取ったこと（Xcode の設定の名前、警告） |
| 結果で変わる決定 | 失敗したら D-9（2 つの dynamic の xcframework）を見直す（static を足す C 案など） |

### U-2: Release のアーカイブの署名（D-18）

| 項目 | 内容 |
|---|---|
| 手順 | Xcode の Product > Archive（Release）。端末には入れなくてよい（Mac の上の操作なので許可は要らない）。アーカイブの `Products/Applications/<アプリ>.app` で、`codesign --verify --deep --strict --verbose=2` を `Frameworks/IosLibrary.framework`、`Frameworks/IosLibraryCApi.framework`、`.app` に流し、`codesign -dv --verbose=4` の `Authority` と `TeamIdentifier` を見る。できれば Organizer の「Validate App」（App Store Connect に送る「Distribute」はしない） |
| 合格の条件 | 3 つとも `valid on disk` と `satisfies its Designated Requirement`。2 つの framework の `TeamIdentifier` がアプリと同じ |
| 記録すること | 上の結果。**Team ID・証明書の名前（個人の氏名を含む）は書かず**、「アプリと同じ / 違う」だけを書く。Validate App の結果（警告とエラーの文、ただし Team や氏名を含む部分は伏せる） |
| 結果で変わる決定 | 失敗したら D-18（配る framework に署名しない）を見直す |

### U-5: Dialog と Share を出したまま、ゲームのフレームが進むか

| 項目 | 内容 |
|---|---|
| 手順 | `Update()` で `Time.frameCount` と時刻を画面に出し続けるシーンで: (1) `ntk_probe_dialog_show_alert` でアラートを出し、5 秒ほど押さずに待ってから「No」を押す。(2) `ntk_probe_share_text(Utf8("U-5 test text"), ShareDone, new IntPtr(5), Release)` でシートを出し、5 秒ほど待ってから**共有先を選ばずに閉じる**（iOS 18 は「閉じる」/ Close、シートの外を押してもよい）。共有先は押さない |
| 合格の条件 | 合否ではない。結果を記録する |
| 記録すること | 表示の間に `Time.frameCount` が増え続けたか（表示の前・間・後の値と時刻）、音や動きが止まったか。完了の値（(1) は `error=0 button=1`、(2) は `error=0 completed=0` の見込み）と `release` が 1 回ずつ来たか |
| 結果で変わる決定 | C ABI は変えない。マニュアルと `unity-native-plugin` の案内（知見 1 章の D-7 と同じ観点） |

### U-8: 起動の直後と `Start()` からの Dialog、同じフレームで 2 つ（P1-11・P1-12）

| 項目 | 内容 |
|---|---|
| 手順 | (1) 最初のシーンの `Start()` で、すぐに `ntk_probe_dialog_show_alert` を呼ぶ（アプリを止めた状態から起動して行う）。(2) `[RuntimeInitializeOnLoadMethod(RuntimeInitializeLoadType.BeforeSceneLoad)]` の中からも呼ぶ（できる中でいちばん早い時期）。(3) 同じフレームの中で 2 回続けて呼ぶ（題を `first` と `second` にする） |
| 合格の条件 | 合否ではない。結果を記録する（P1-11・P1-12 は推奨の形で組んである。結果は判断の材料） |
| 記録すること | 出たか、出るまでの時間、完了の値（出なければ `error=8` NOT_FOREGROUND か `10` SHOW_FAILED のどちらか）。(3) で 2 つとも出たか、どちらが上か、押した順の完了。シミュレーターの雛形のアプリでは、`didFinishLaunching` の中（scene が inactive）から呼んでも出て、同じ回の 2 つは 2 つ目が上に出た（6 章） |
| 結果で変わる決定 | P1-11（前面の定義）、P1-12（同時の要求）。利用者が別の案を選んだら、その形で流し直す |

### U-9: C# のコールバックが例外を投げたとき（P1-16）

| 項目 | 内容 |
|---|---|
| 手順 | 3 章の `try` / `catch` を**外した**コールバック（`throw new InvalidOperationException("U-9")` だけのもの）を別に作り、それを渡して `ntk_probe_dialog_show_alert` を呼び、「Yes」を押す。1 回だけ行う（アプリが落ちうるので、許可の「端末に起きること」に書く） |
| 合格の条件 | 合否ではない。結果を記録する |
| 記録すること | アプリが落ちたか（落ちたら、Xcode のコンソールの最後の数行と、例外の種類。端末の crash log の場所は書かない）。落ちなかったら、`release` が来たか、その後に `ntk_probe_dialog_show_alert` をもう一度呼べるか、Unity のログに何が出たか |
| 結果で変わる決定 | P1-16 のマニュアルの書き方（「必ず try / catch」） |

### U-10: 実機の TSan と ASan（P1-20）

| 項目 | 内容 |
|---|---|
| TSan の手順 | **端末では試さない**。Xcode の文書（Thread Sanitizer の対応する実行先）で、iOS の実機で使えるかを確かめ、出典の URL と文を記録する |
| ASan の手順 | 1 章の `asan/` の 2 つの xcframework に入れ替えて組み、Unity-iPhone の scheme の Run の Diagnostics で **Address Sanitizer** を有効にする（ASan で組んだ framework は `@rpath/libclang_rt.asan_ios_dynamic.dylib` を要する。scheme で有効にすると Xcode がアプリに入れる）。Xcode から実機で起動し、U-1 の (1)〜(3) と U-5 の (1)・(2) を行う。**許可を得てから**。終わったら普通の版に戻す |
| 合格の条件 | ASan の報告（`ERROR: AddressSanitizer`）が 0。U-1・U-5 の完了と `release` が同じように来る |
| 記録すること | 報告の有無（あれば報告の要約。端末のパスや識別子は伏せる）。起動できなかった場合はその文 |
| 結果で変わる決定 | P1-20。README 7.4 の DoD の行 |

## 5. 結果の返し方

1. あなたのリポジトリの中に結果のファイルを書く（場所と名前はあなたの決まりでよい。例: `<docs>/results/2026-11-xx-ios-c-abi-handoff-1-results.md`）。各 U-n の手順・結果・記録すべき値と、使った雛形の `BUILD-INFO.txt` の `built` と `commit` の行、Unity の版、Xcode の版、端末の iOS の版（端末の識別子は書かない）
2. 次の要約を、こちらへの返事（利用者を通す）に貼る。こちらは `artifact/topics/ios-c-abi/results/` に写し、設計書の第 1 部と README の決定に反映する

```
handoff-1 results (unity-native-plugin, <commit of your repo>)
probe: built <built>, commit <commit>   Unity 6000.4.2f1   Xcode <version>   iPhone XS / iOS <version>
U-1: pass|fail  version=<value>  read: error=<n> release=<count>  dialog: error=<n> button=<n> release=<count>  main=<yes|no>  after-return=<yes|no>  notes=<...>
U-2: pass|fail  verify(IosLibrary/IosLibraryCApi/app)=<ok|...>  team-same=<yes|no>  validate=<ok|warnings|errors|not run>
U-5: dialog frames advanced=<yes|no> (<before>/<during>/<after>)  share frames advanced=<yes|no>  completions=<...>
U-8: start=<shown|error n>  before-scene-load=<shown|error n>  two-in-one-frame=<both|first only|...> top=<first|second>
U-9: <crashed|survived>  <last console lines / what happened>
U-10: tsan-on-device=<supported|not supported> (<source>)  asan reports=<0|n>  <notes>
blocked: <anything that could not be done, and why>
```

3. 実機の `.xcresult`、スクリーンショット、画面の録画を作ったら、書き写した後に消す（0 章の 5）

## 6. こちらで確かめたこと（シミュレーターだけ）

確かめた雛形は 1 章の場所のもの（`BUILD-INFO.txt` の `built: 2026-10-31T05:25:42Z`。commit `fbb03f70` の上の、まだコミットしていない雛形のソースから組んだ）。実機には触れていない。手順は `results/probes/stage1a/handoff1/run.sh`。

| 確かめたこと | 結果 |
|---|---|
| 公開シンボル（`nm -gU`） | 3 つのアーキテクチャ（`ios-arm64`、シミュレーターの `arm64` と `x86_64`）とも、3 章の 17 個だけ。`_ntk_` 以外は 0 |
| xcframework の中身 | capi の framework はスライスごとに `Headers/NativeToolkitC/` の 4 つのヘッダー、`Modules/module.modulemap`、`Info.plist`、本体だけ。Swift のモジュールと `-Swift.h` は無い（`SWIFT_INSTALL_MODULE=NO`） |
| `Common.h` | Android の `Common.h` と宣言が同じ（違うのはコメントだけ） |
| 署名 | `ios-arm64` は 2 つとも署名なし、シミュレーターのスライスはリンカーの ad-hoc の署名だけ |
| ASan の版 | 2 つの framework とも `@rpath/libclang_rt.asan_ios_dynamic.dylib` に依存する。公開シンボルは同じ 17 個 |
| C の smoke（`smoke/`。dist の 2 つの xcframework だけで組む C / Objective-C のアプリ） | Xcode 26.6 と **26.3** の両方で警告 0 件で組めた。26.3 で組んだものを iPhone 17 / iOS 26.2 で動かし、`failures=0`: 表示したアラートを 1 秒後に main から取り消すと `CANCELED`（6）、別のスレッドで出してすぐに取り消すと `CANCELED`、key window を隠すと `NOT_FOREGROUND`（8）、`ntk_probe_share_text(NULL, NULL, ...)` は `INVALID_PARAMETER` で `release` が呼び出しのスレッドで戻る前。受け付けた 3 件はどれも完了と `release` が 1 回ずつ main で、関数が戻った後 |
| XCTest（11 件。C の関数を Swift から呼ぶ） | iPhone 17 / iOS 26.2 で通常・ASan・TSan、iPad Pro 11-inch (M4) / iOS 18.3 で通常、のすべてで通った（TSan では 1 件を skip。下の表） |
| UI テスト（3 件。テストのホストのアプリが C ABI で出したアラートと Share のシートを押す） | 上と同じ 4 通りで通った |
| テストが守りを確かめていること | 一時的に (1) `release` を状態に関わらず呼ぶ、(2) 表示の前の状態の確かめを外す、の 2 つに壊すと、5 件のテスト（取り消しの前後、完了の中の取り消し、同じ回の 2 つ、同時の 80 件）が落ちた。元に戻してから流し直した |

XCTest と UI テストで測ったこと（U-5・U-8 の結果を読むときの手がかり）:

| 場面 | 結果 |
|---|---|
| `didFinishLaunching` の中から `ntk_probe_dialog_show_alert` | scene は `foregroundInactive`（`activationState` の値 1）だったが、アラートは出た。「No」を押すと `error=0 button=1`、その後に `release`。どちらも main（P1-11 の前面の定義どおり。今の `IosLibrary` の探し方では inactive の間は出せない） |
| 同じ main の回で 2 つ | 2 つとも出て、2 つ目が上（P1-12）。上から押すと、それぞれ `error=0 button=0` と `release` が 1 回ずつ。続けて 2 つとも取り消すと、2 つとも閉じる |
| 表示の前の取り消し（同じ回で出して取り消す） | アラートは出ず、`CANCELED` と `release` が 1 回ずつ。関数の中では何も呼ばれない |
| 表示した後の取り消し（別のスレッドから） | `CANCELED` と `release` が 1 回ずつ。アラートは閉じる。終わった ID と知らない ID の取り消しは何もしない |
| 完了のコールバックの中で、同じ ID を取り消す | 完了 1 回、`release` 1 回 |
| 前面が無い（key window を隠す） | Dialog は `NOT_FOREGROUND`（8）、Share は `NOT_FOREGROUND`（6） |
| 同時に 8 スレッド × 10 回の「出してすぐ取り消す」 | 80 件すべて `CANCELED` と `release` が 1 回ずつ。TSan の報告は 0 |
| アラートを外から `dismiss`（ホストが閉じた場合） | 通常と ASan では約 0.5 秒で解放の見張りが働き、`CANCELED_BY_SYSTEM`（7）と `release` が 1 回ずつ。**TSan では 15 秒たってもアラートが解放されず、完了も `release` も来なかった**（そのため TSan の回だけ skip）。解放の時期に頼る見張りは、環境によって遅れうる（設計書の G-7。1b で確かめる） |
| Share を「閉じる」（共有先を選ばない） | `error=0 completed=0` と `release` が 1 回ずつ main で（iOS 26.2 の iPhone、iOS 18.3 の iPad） |
| Share のシートを外から `dismiss` | **完了も `release` も来なかった**（`IosShareManager` の `completionWithItemsHandler` が呼ばれない。7 章） |
| iPad の Share の基点（P1-13） | iOS 18.3 の iPad で、基点は表示元の view の中央（`{417, 605}`、幅と高さ 0）。落ちない |
| Objective-C のクラス | capi が登録するのは、モジュール名で区切られた Swift のクラス（`IosLibraryCApi.NTKString` など 11 個）だけ。`@objc` で名前を固定したものは無い |

## 7. 渡せなかったもの・注意

| もの | 状態 |
|---|---|
| 通知の関数（`ntk_notification_install` など）と U-3・U-4・U-6・U-7 | 2 回目の申し送り。1 回目の雛形には無い |
| `WRONG_THREAD`（`NTK_NOTIFICATION_ERROR_WRONG_THREAD = 16`） | 返すのは 2 回目の `ntk_notification_install` だけ。1 回目の関数はどのスレッドからでも呼べ、`WRONG_THREAD` を返す経路が無い（こちらのテストでも、main 以外から呼んで受け付けられることだけを確かめた） |
| 本番の関数名・引数・エラーの番号 | 設計書の第 2 部。雛形の `ntk_probe_*` は今回の確かめのためだけのもの |
| Unity での組み込みの手順（2 章） | Unity の書き出すプロジェクトの一般の形から書いた。**こちらでは Unity のプロジェクトを組んでいない**（Unity での確かめは利用者の決定であなたの受け持ち）。設定の名前や手順が違えば、結果に書く |
| C# の宣言（3 章） | IL2CPP で組んで動かしてはいない。`byte[]` の渡し方、`MonoPInvokeCallback`、`Marshal.PtrToStringUTF8` で困ったことがあれば結果に書く |
| 実機の署名つきのアーカイブ、Team ID、Validate App | こちらでは利用者の証明書を使わない取り決めなので、行っていない（U-2） |
| 実機での動き | こちらはシミュレーターだけ。実機は U-1・U-5・U-8・U-9・U-10 で初めて動かす |

雛形が第 1 部と違うところ（1b で `IosLibrary` に足すまでの代わり。こちらの 1b の要件）:

- **Dialog**: `IosDialogManager` には、表示した `UIAlertController` を返す口、表示元（`presenter`）を選ぶ引数、取り消しの口が無い。雛形は、前面の定義（P1-11）・表示の手順（P1-12）・要求の箱・解放の見張り（P1-14）・取り消し（P1-24）を capi の中（`Stand1b/`）に最小の形で持ち、`UIAlertController` を自分で作る。本番は 1b で `IosLibrary` に足し、capi は呼ぶだけにする
- **Share**: 雛形は `IosShareManager.share(content:)`（公開の API）を呼ぶ。そのため、前面の探し方は今の `IosLibrary` のもの（`foregroundActive` だけ。最上位の ViewController が落ち着いていなければ待たずに失敗）で、**要求の箱と解放の見張りが無く、外から閉じられた Share は完了も `release` も来ない**（6 章で測った）。U-5 では、Unity が勝手にシートを閉じることは無い見込みなので影響しない。本番は 1b で見張りを足す
- `struct_size` の読み方は、雛形の `ntk_probe_echo` では最小と上限（4096）だけを見る（Windows の設計書 7.8 の 5 つの規則は 2b で入れる）
- `IosLibrary` の xcframework は今のリポジトリのプロジェクトをそのまま組んだもので、版は 1.3.0 のまま（capi は 2.0.0）。P1-19 の版の照らしは雛形に無い
- ログ（P1-18）は `os.Logger` の debug の水準で、関数名・ID・エラーの値だけを出す（利用者の文字は出さない）
