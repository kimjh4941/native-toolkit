# 段階 2c の申し送り: `unity-native-plugin` の Android を C ABI に移す

- 作成日: 2026-10-10（レビュー v1 を受けて書き直した。`reviews/2026-10-10-android-c-abi-stage2c-handoff-review-v1.md`）
- 対象: `artifact/topics/android-c-abi/README.md` の段階 2c、C ABI の設計書 第 2 部（`designs/2026-10-05-android-c-abi-c-abi-design-part2.md`）13 章の TC-1
- 読み手: `unity-native-plugin`（別リポジトリ）で Android の部分を移す人
- 前提の段: 2b（C ABI の実装）は完了（`results/2026-10-10-android-c-abi-stage2b-result.md`）
- 2c の成功（Unity が C ABI を呼び、Android のテストと Player テストを通す）が、段階 3（`unity_android_plugin` を消す）を始める条件

## 1. 何が変わるか

`unity-native-plugin` の Android は今、`unity-android-native-toolkit`（ブリッジの AAR。`android.unity.*`）を `AndroidJavaClass` と `AndroidJavaProxy` で呼んでいる。2.0.0 では、このブリッジの AAR は無くなり（段階 3）、代わりに C ABI（`libntk.so`）を P/Invoke で呼ぶ。進め方は Windows の C ABI 2.0.0 への移行（`unity-native-plugin` の `artifact/topics/windows-c-abi-2`）に倣える: 各 manager の公開の API は保ち、下の層だけを置き換える。**ただし、Windows の P/Invoke の層の書き方（`user_data` を NULL にして要求の ID の表で照合する、32 ビットの要求の ID、借りるハンドル）は、Android にはそのまま写せない**（4 章）。

| | 今（1.x） | 2.0.0 |
|---|---|---|
| 呼ぶもの | `android.unity.*` の Kotlin のクラス（`AndroidJavaClass` / `AndroidJavaObject`） | `libntk.so` の `ntk_*`（155 関数。`DllImport`） |
| 結果の返り方 | `AndroidJavaProxy` のリスナー、JSON の文字列 | C の関数ポインタのコールバック（`[MonoPInvokeCallback]`）、構造体、所有権ごと渡すハンドル |
| リスナー | `set*Listener` / `clear*Listener`（差し替え） | 足す・外す（`ntk_*_add_*_listener` / `_listener_remove`）。差し替えは包みが保つ（4.5） |
| AAR | `android-native-toolkit` と `unity-android-native-toolkit` | `android-native-toolkit` と `android-native-toolkit-capi`（**両方要る**。capi は Kotlin の API に実行時に依存する） |
| Kotlin のビルド | `PostBuildProcessor` が KGP 2.0.21 を当てる | KGP は要らない（Kotlin のソースをアプリで組まない）。実行時の依存だけを足す（3.3） |

## 2. まず見るもの

| 見るもの | 場所（このリポジトリ） |
|---|---|
| 今のブリッジの 69 メソッドと C ABI の対応表 | 第 2 部 8.3。**「Unity の包みが保つこと」の列**が、包みで今の振る舞いを保つための指示 |
| 包みに渡す事柄の一覧 | 第 2 部 16 章（下の 4 章に、`unity-native-plugin` の今の作りに合わせて書き直した） |
| 公開ヘッダー | `android/android_library_capi/src/main/cpp/include/NativeToolkitC/`（`Common.h`、`Android.h`、`Clipboard.h`、`Dialog.h`、`Notification.h`、`Share.h`）。C99 |
| 関数の一覧と OP ごとの対応 | 第 2 部 8.1（OP-01〜OP-56）と 8.2（155 関数） |
| スレッド、寿命、`release`、Context と前面 | 第 1 部（`designs/2026-10-04-android-c-abi-c-abi-design.md`）1.3、1.4、5.7、5.8 |
| 差し替え型のリスナー | 第 1 部 C-6（9.2） |
| エラーの値 | 第 2 部 11 章。4 つの機能（Clipboard、Dialog、Notification、Share）のエラーは 0〜5 が同じ意味（AP-12）。**`ntk_android_error`（11.5）は別の列挙で、2 = `CLASS_NOT_FOUND`、3 = `JNI_FAILURE`、4 = `IN_PROGRESS`** |
| 同期・非同期と完了のスレッド | 第 2 部 9 章 |

## 3. 配布物と組み込み

### 3.1 ネイティブのライブラリ

- `libntk.so`。`DllImport` の名前は `"ntk"`
- **ABI は `arm64-v8a` と `x86_64` だけ**（README D-10）。`armeabi-v7a`（32 ビット）では `libntk.so` が無く、`DllImport` は `DllNotFoundException` になる。Windows の `EnsureNativeAvailable()` と同じく捕まえて「使えない」とする（2b の smoke で、32 ビットでもアプリが落ちず、Kotlin の API は動くことを確かめた）
- 版: `ntk_version()` が `NTK_VERSION`（`0x020000`）を返す。Windows と同じく、メジャーの 2 を確かめる（第 1 部 AC-11。期待値は OS ごとに持つ）。この値はヘッダーの定数なので、どの版の AAR から組んでも同じになる。取り込んだ AAR の版は、ファイル名か座標で確かめる
- 公開しているのは `ntk_*` と `JNI_OnLoad` だけ。libc++ は中に隠してあるので、Unity の同梱の NDK（r27c）や IL2CPP の libc++ とぶつからない

### 3.2 配布物

配布物は `dist/<リリース版>/android/` に置く（リリースの段で作る。2c の作業用の作り方は 7 章）。

| ファイル | 中身 |
|---|---|
| `android-native-toolkit-2.0.0.aar` | Kotlin の API |
| `android-native-toolkit-capi-2.0.0.aar` | C ABI。`jni/<ABI>/libntk.so`、Prefab、`capi` の Kotlin（`NativeToolkitCApi`、`NtkInitializer`）と `capi.jni` の受け口、R8 の keep の規則、`NtkInitializer` を登録する manifest |
| `m2/` | 上の 2 つの AAR と POM・Gradle Module Metadata（座標は `io.github.kimjh4941:android-native-toolkit(-capi):2.0.0`。README D-17） |
| `include/NativeToolkitC/` | 公開ヘッダー |

### 3.3 Gradle への組み込み

**AAR のファイルを `Plugins/Android` に写すだけでは、依存のライブラリが入らない**（AAR には依存が書かれていない）。Unity が書き出す Gradle は `PREFER_SETTINGS` と flatDir なので、`mainTemplate.gradle` に Maven のリポジトリを足しても使われない。そこで README（3 章の配布物の表）のとおり、**`m2/` は使わず、AAR を写して依存を明示的に足す**。

実行時の依存（`m2/` の Module Metadata の runtime の variant から。2b の時点の版）:

| 依存 | 版 | 求めるもの |
|---|---|---|
| `org.jetbrains.kotlin:kotlin-stdlib` | 2.2.21 | 両方。**2.2 以上**（Kotlin の `apiVersion` 2.2） |
| `org.jetbrains.kotlin:kotlin-parcelize-runtime` | 2.2.21 | `android-native-toolkit` |
| `androidx.startup:startup-runtime` | 1.2.0 | 両方（自動の初期化。4.1） |
| `androidx.fragment:fragment` | 1.9.1 | `android-native-toolkit` |
| `androidx.core:core-ktx` | 1.18.0 | `android-native-toolkit` |
| `androidx.media:media` | 1.8.0 | `android-native-toolkit` |
| `org.jetbrains.kotlinx:kotlinx-coroutines-core` | 1.9.0 | `android-native-toolkit` |

- 版の正は、取り込む版の `m2/` の Module Metadata（`.module`）。上の表は 2b の時点の写しなので、版ごとに `.module` から読むか照らす仕組みを作る
- **足す時期**: 今の `PostBuildProcessor` は、ビルドが終わった後（`OnPostProcessBuild`）に Gradle を書き換えるので、APK / AAB の依存の解決に間に合わない。Unity の書き出しの後、Gradle を走らせる前に呼ばれる口（`IPostGenerateGradleAndroidProject`）か、Gradle のテンプレートで足す
- **足す先**: `IPostGenerateGradleAndroidProject.OnPostGenerateGradleAndroidProject(path)` の `path` は、Gradle のルートではなく `unityLibrary` のルート。上の表の依存は `path/build.gradle`（`unityLibrary`）の `dependencies` に、何度流しても 1 回だけになるように足す。`launcher` はすでに `implementation project(':unityLibrary')` なので、外部の依存を重ねて足す必要は無い。リポジトリは、書き出された `settings.gradle` の `google()` と `mavenCentral()` がそのまま使える。今の `AndroidGradlePatcher` は Gradle のルートを受けて `launcher/` と `unityLibrary/` を探す作りなので、`path` をそのまま渡さない（Gradle のルートは `path` の親）
- **有効にする条件**: 今のビルドの処理の asmdef（`NativeToolkit.BuildProcessors.Editor.asmdef`）は `NATIVETOOLKIT_ENABLE_BUILD_STEPS` を定義したときだけ組まれる。依存を足す処理は、UPM で入れたふつうの利用者のビルドでも動く必要があるので、この条件の外に置くか、利用者が有効にする手順を書く
- KGP の適用（`PostBuildProcessor` と `AndroidGradlePatcher` の `org.jetbrains.kotlin.android` 2.0.21、`kotlinOptions`）はやめる。AGP 9 の Unity では、KGP を当てるとビルドが失敗しうる（README 2c の行）。`kotlin-stdlib` / `kotlin-reflect` 2.0.21 の固定も外すか 2.2 以上に上げる（2.0.21 に固定すると、2.2 の API を呼んだところで実行時に落ちる）

**AAR の選び方（`PreBuildProcessor`）**:

- 今の選び方は、名前の前方一致（`android-native-toolkit-`）と辞書順の最大で選ぶ。2.0.0 では `android-native-toolkit-capi-*` もこの前方一致に入るので、Kotlin の API の AAR の枠に capi が選ばれうる。Windows と同じく `VERSION.txt` に 2 つの AAR の完全なファイル名を書いて一致で選ぶか、少なくとも Kotlin の API の枠から `-capi-` を外す
- 2 つ目の必須の AAR を、ブリッジ（`unity-android-native-toolkit-`）から capi に替える。`Plugins/Android` の古いブリッジの AAR と `.meta` を消す

### 3.4 Unity の版と Player Settings

- **Minimum API Level は 31 以上**（ライブラリの minSdk が 31。低いと manifest の merge で止まる）。今の Player Settings は 25 だが、Android の Build Profile（`Android™ Profile.asset`、`Test Android™ Profile.asset`）が 31 で上書きしている（1a の結果 3.7）。Player Settings も 31 にそろえるか、Build Profile を必須にする
- **Unity の版**: 依存が AGP 8.9.1 以上を求めるので、Unity 6000.0.61f1 以降、6000.3.1f1 以降、6000.4.1f1 以降（README 8.3）。今の 6000.4.2f1（Gradle 8.13 / AGP 8.10.0）は対象に入る
- compileSdk は 36 以上（AAR の `minCompileSdk` が 36）。Unity 6000.4 は 36 まで扱える
- R8: 自動の初期化（4.1）で使うものの keep の規則は、capi の AAR の `consumer-rules.pro` に入っている（`capi.jni` の全体と `NtkInitializer`）。2b の smoke で、R8 を有効にした release と、規則を外すと初期化が `CLASS_NOT_FOUND` で失敗することを確かめた。**手動の初期化（4.1）で `NativeToolkitCApi` を名前で引く場合は、この規則に入っていない**。Minify を有効にするなら、Player Settings の Custom Proguard File を有効にして（今の `unity-native-plugin` では無効。Unity は `proguard-user.txt` をこの設定のときだけ取り込む）、次を足す:

```
-keep class com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi { *; }
-keep class com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi$InitResult { *; }
```

## 4. C# の包みで気をつけること

### 4.1 初期化

- 既定では、アプリの起動時に androidx.startup の `NtkInitializer` が初期化する（`NativeToolkitCApi.init` を通して `System.loadLibrary("ntk")` を含む）。Unity の側で呼ぶものは無い。最初の呼び出しの前に `ntk_android_is_initialized()` を見て、0 なら「まだ使えない」と扱える
- 未初期化の操作は `NOT_INITIALIZED` を返す。ただし、入口の検査（引数の誤り、AP-19 の入口の値）が先に効き、取り消しの 3 つ（`ntk_dialog_cancel`、`ntk_notification_cancel_permission_request`、`ntk_share_cancel_selection`）は何もせずに `NONE` を返す（第 2 部 11 章）
- **確かめていないこと（2c で最初に確かめる）**: Unity が `DllImport` で読む `libntk.so` が、`NtkInitializer` が読んだものと同じ実体であること。2b のテストで確かめたのは、`libntk.so` に依存して組んだ別の `.so`（`libntk_test.so`）を `System.loadLibrary` で読んだ場合に同じ実体になることで、明示の `dlopen` や Unity の `DllImport` の読み方ではない（Unity の文書に記述が無い。1a の結果 4 章）。実機で `ntk_android_is_initialized()` が 1 を返すことを確かめる
- androidx.startup を外すアプリでは、Kotlin の `com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi.init(context)` を呼ぶ（`ntk_android_init` は `JNIEnv*` が要るので C# からは呼びにくい）。`NativeToolkitCApi` は Kotlin の `object` で、`init` は static ではない。`new AndroidJavaClass("com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi").GetStatic<AndroidJavaObject>("INSTANCE").Call<AndroidJavaObject>("init", activity)` のように呼ぶ。Activity（`UnityPlayer.currentActivity`）を渡す（前面の初期値になる。第 1 部 1.4）。戻り値の `InitResult` の扱い:

| 値 | 意味 | 扱い |
|---|---|---|
| `INITIALIZED` | 使える | そのまま使う |
| `IN_PROGRESS`、`RETRYABLE_ERROR` | まだ、または一時的な失敗 | 後でやり直す |
| `NATIVE_SETUP_REQUIRED` | C の側のクラスの表がまだ無い（`JNI_OnLoad` の表づくりが失敗したか、ほかのスレッドが作っている最中） | 後でやり直す。作っている最中なら、やり直すと `INITIALIZED` になる（第 1 部 5.3）。やり直しても直らなければ、C の `ntk_android_init` が要り、C# からは直せないので、使えないと扱う |
| `CLASS_NOT_FOUND`、`UNAVAILABLE` | R8 の規則が無い、32 ビットなど | 直らない。使えないと扱う |

### 4.2 スレッド

- **完了、イベント、受け付けた後の `release` は、Android の main スレッド（UI スレッド）で来る**。これは Unity のスクリプトのスレッド（UnityMain）ではない
- **コールバックの中では、受け取った値と所有権ごと渡されたハンドルの中身を写し、ハンドルを `_free` し、スレッドの安全な列に積むことだけをする**。manager の状態（要求の表、待っているコールバック、リスナーの今のハンドルの印、イベントの列）を変えるのは、すべて UnityMain に積んだ処理の中にする。今の `AndroidJavaProxy` のリスナーは、Clipboard と Share で、コールバックのスレッドで待っている表を引いて消してから積んでいる（`AndroidClipboardManager`、`AndroidShareManager`）。この形を写すと、UnityMain で新しい要求を足している最中の表とぶつかる
- dispatcher（`UnityMainThreadDispatcher`）は、UnityMain で前もって作っておく。コールバックから Unity のオブジェクトを作らない
- C の関数はどのスレッドから呼んでもよく、**決して待たない**。非同期の操作は受け付けて戻り、完了は後で main に来る。**UnityMain は Android の main ではないので、UnityMain から呼ぶと、関数が戻る前に完了が来ることがある**（第 1 部 1.3 の「完了の時刻」）
- **どのスレッドでも、完了や `release` を同期で待たない**（第 1 部 1.3「なぜ main を待たないか」）。Windows の包みの「`release` を期限付きで待つ」形を写すと、UnityMain と Android の main が互いに待って止まりうる。コールバックの中で main を長く塞がない（ANR。第 1 部 1.3.2）

### 4.3 `user_data`、要求の ID、`release`

**Windows の包みの「`user_data` を NULL にし、出力の要求の ID と表で照合する」形は、Android では成り立たない**:

- UnityMain から呼ぶと、関数が戻って要求の ID が書かれる前に、完了が来ることがある（4.2）。ID を戻った後に表へ入れると、その完了は表に無いので捨てられ、二度と来ない
- 要求の ID を持たないコールバックがある: Share を開く 6 つの関数（`ntk_share_text_for_selection` を含む）の完了（`ntk_share_done_fn`）、通知の設定の画面の完了（`ntk_notification_settings_fn`）、Clipboard の変更（`ntk_clipboard_change_fn`。`user_data` だけ）
- 第 1 部 1.3 は、完了と要求の対応付けを `user_data` で行うと決めている

そこで:

- **登録ごとに別の `user_data` を渡す**。包みが作る整数のキー（連番を `IntPtr` にしたもの）を、スレッドの安全な表に**呼ぶ前に**入れて渡すか、`GCHandle` を渡す
- **表は 2 つに分ける**:
  - 「`user_data` の表」（キーから要求の物を引く）: 呼ぶスレッドが入れ、コールバック（main）が読み、`release`（main か呼び出しスレッド）が消す。スレッドの安全な表にする
  - 「manager の表」（待っている要求、リスナーの今のハンドルの印など）: UnityMain だけが触る（4.2）
- **コールバック（main）の中で、`user_data` から要求の物を引いて（読むだけ）、引いた物を UnityMain に積む**。キーや `IntPtr` のまま積んで後で引かない。完了つきの操作では、完了を呼んだ直後に、同じ main のメッセージの中で `release` が来る（第 1 部 5.7）ので、後で引くと、もう表から消えている。`GCHandle` なら、コールバックの中で `Target` を引いてから積む
- `user_data` の片付け（「`user_data` の表」から消す、`GCHandle.Free`）は、**`release` の中だけ**で行う。`release` は登録ごとにちょうど 1 回、次のどれかで来る:
  - 完了つきの操作を受け付けた後: 完了の直後に main で
  - イベントの登録を受け付けた後: `_listener_remove` の後に main で（外さなければ来ない。外した解除を main に積めなかったときは、main が次に C に入るまで遅れ、その遅れに上限は無い。第 1 部 5.7）
  - 入口で拒んだとき（引数の誤り、未初期化）と、受け付けの失敗（main に積めなかった。第 1 部 5.7 の手順 3）: 呼び出しスレッドで、関数が戻る前に
  - **プロセスが終わるときは、完了も `release` も来ない**（第 1 部 1.3）
- `release` の後は、その `user_data` で配送は来ない（第 1 部 1.3、5.7）
- **要求の ID は 64 ビット（`uint64_t`）**。C# では、コールバックの引数、出力（`out ulong`）、取り消しの引数、表のキーをすべて `ulong` にする。Windows の宣言（`uint`）を写すと、C が 8 バイトを書いて ID を読み違えるか、メモリを壊す
- 要求の ID は、取り消し（`ntk_dialog_cancel` など）と、Share の選ばれたアプリのイベント（`ntk_share_selection_fn` の `request_id`）との照合に使う。**ID は「manager の表」（UnityMain）に置く**。`user_data` の物に書き足さない: UnityMain から呼ぶと、関数が戻る前に完了と `release` が来うるので、書き足す先がもう無いことがある。とくに Share を開く要求は、Sharesheet が開いた時点で完了して `release` されるので、選択のイベントと、直前の要求の ID での取り消し（8.3 の SH-14）は、必ずその後になる。manager が「直前の Share の要求の ID」を持ち、選択のイベントは UnityMain に積んだ後でこれと照らす。Dialog と権限の要求で、ID を置く時点で完了がもう済んでいても害は無い（完了の後の取り消しは何もしない）
- `release` は NULL でもよい（呼ばれないだけ）が、上のとおり `user_data` の片付けに要る
- **利用者のコールバックで例外が C へ抜けると、Android ではプロセスが終わる**（第 1 部 5.11）。すべての `[MonoPInvokeCallback]` の本体を `try` / `catch` で囲む（Windows の包みと同じ）
- デリゲートは `static readonly` に置いてプロセスの間保ち、IL2CPP では `[MonoPInvokeCallback]` の static のメソッドにする（Windows の包みと同じ）
- **コールバックが受け取ったハンドル（`ntk_string*`、通知の操作のハンドルなど）は、所有権ごと渡される**。使い終わったら、対応する `ntk_*_free` で解放する（第 1 部 AC-18、5.9）。**Windows の「コールバックから戻るまで有効（借りるポインタ）」とは逆**。出力引数で受け取ったハンドルも同じく `_free` する

### 4.4 C# の宣言

- **共通なのは `Common.h` の宣言だけ**。機能の関数、列挙、構造体は、Android 用に別に宣言する（第 2 部 16 章、AP-5、RP-5）。同じ名前で、引数、値、配置が Windows と違うものがある（例: `ntk_clipboard_copy_text`、`ntk_dialog_alert_request`、`NTK_DIALOG_ERROR_CANCELED`、`NTK_NOTIFICATION_ERROR_INVALID_PARAMETER`）。Windows の `DllImport` や列挙を流用しない
- 構造体の配置は 64 ビット（LP64）の値。`struct_size` には `Marshal.SizeOf<T>()` を入れ、0 で埋める。2b のテスト（`StructLayoutTest.cpp`）の `sizeof` と `offsetof` の値と、C# の `Marshal.SizeOf` と `Marshal.OffsetOf` を EditMode のテストで照らす
- `ntk_android_error` は機能のエラーと別の型にする（2 章）

### 4.5 差し替え型のリスナー（第 1 部 C-6）

- 種類ごとに 1 つのハンドルと「今のハンドル」の印を持つ。`set` では、古いハンドルを外してから新しいものを足し、印を新しいものにする
- **配送を受けたら、それが今のハンドルへの配送でなければ捨てる。この判定は UnityMain で行う**。UnityMain からの解除は main 以外からの解除なので、`release` が来るまで古い登録への配送が来うる（第 1 部 1.3）。判定のために、登録ごとに別の `user_data`（4.3）が要る
- 2 回目の `set` の後に、前の受け手へ届かないことを Unity のテストで確かめる

### 4.6 振る舞いを保つための包みの仕事（第 2 部 16 章）

| 事柄 | 包みがすること |
|---|---|
| `clear*Listener` の副作用 | 今のブリッジは、外すときに監視を止めるなどの副作用がある。C ABI は外しても副作用が無い（AP-11）ので、包みが対応する関数（例: `ntk_clipboard_stop_observing`）を続けて呼ぶ。どれに何が要るかは 8.3 の列 |
| `NOT_FOREGROUND` | Dialog、Share、設定の画面を後ろから呼ぶと、完了が `NOT_FOREGROUND` で来る（今は Dialog は同期に失敗し、Share と設定の画面は OS が黙って止める）。今の振る舞いに写すか、新しいエラーとして出すかを決める |
| 値の補正と代わりの値（AP-8） | importance と visibility の丸め、BigPicture や layout が引けないときの Default、Messaging の名前 `"You"` と時刻の既定、**小さいアイコンの既定**（引けないときは既定のアイコン）、引けない大きいアイコンとアクションのアイコンの省略、view の ID や `actionId` の無いクリックを捨てること、`bigText` の空（null を空にする）、Chooser Action の空白と重複の除外、Base64 を包みが行う。読めない Chooser Action のアイコンの除外は保てない |
| リソースの型 | C ABI はリソースの名前だけを受け、型（`{name, type}`）を指定できない。アイコンは drawable と mipmap だけ（AP-8）。移行ガイドに書く |
| 通知のタップと dismiss | `launchAppOnTap` を `ntk_notification_content_set_tap` に写す（既定は今と同じく開く。AP-18）。今の公開の定数 `ActionBodyTap`、`ActionNotificationDismissed` の値（`android.unity.notification.*` の文字列）は、包みが今の値で出し続ける。8.3 の NT-04 の違い: アプリを開く起動の Intent の action が `actionId` ではなくなる（Unity にそれを読むコードがあれば確かめる）。通知の操作のイベント（タップ、アクション、dismiss）は、`ACTIVE` な登録が 1 つも無い間（差し替えの `set` で外してから足すまでの間も含む）32 件まで保ち、次の登録に渡す（今は捨てる。AP-21） |
| Kotlin が黙って成功にしていた場面 | `PERMISSION_DENIED` と `EXACT_ALARM_NOT_ALLOWED`（AP-16）を、今と同じ成功に写す（正確な予約は `inexact` で呼び直す）か、失敗として出すかを決める |
| 問い合わせの失敗 | NT-08〜NT-11 は今は例外が上がる。C ABI はエラーを返す |
| Dialog を閉じたときの値 | `DISMISSED` を今の値（`"Cancel"`、入力は `""`）に写す。選択の状態は来ないので保てない（AP-13） |

### 4.7 JSON（機能ごとに違う）

| 機能 | 今 | 2.0.0 |
|---|---|---|
| Notification | 公開の API が channel・内容・予約を JSON の文字列で受ける | 公開の JSON を解く処理は包みに残し、解いた値を C の構造体とビルダーに写す |
| Clipboard | 公開の API は型のある payload を受け、JSON はブリッジとの内部のやりとり。読み取りの結果を JSON で受けて `AndroidClipboardJsonParser` で解く | 書き込みは payload から C の関数へ直接写す。読み取りの JSON の解析は、C の出力のハンドルの読み取り（`ntk_clipboard_content_*`）に置き換わる |
| Share | 公開の API は型のある payload を受け、`AndroidShareJsonBuilder` で JSON にしてブリッジに渡す | payload から C の構造体へ直接写す |

公開している JsonBuilder / JsonParser の型を互換のために残すかは、2c で決める。

**第 2 部の 8.3（CL-06〜CL-10、CL-12 の「JSON を解いて呼ぶ」「ハンドルから今の JSON を組む」）と 16 章の JSON の文言は、ブリッジの JSON の形を包みの中で保つ前提で書いた。Clipboard と Share の公開の API は JSON を受けない（型のある payload を受ける）ので、この 2 つでは上の表を優先する。** 今の公開の API の振る舞い（どの値が返るか）を保つことは、8.3 の列のとおり。

## 5. 2c で決めること

| 事柄 | 選択肢 | 推奨 |
|---|---|---|
| 依存を足す口 | `IPostGenerateGradleAndroidProject` / Gradle のテンプレート / EDM4U | ふつうの利用者のビルドで、Gradle の前に動くもの（3.3）。`NATIVETOOLKIT_ENABLE_BUILD_STEPS` の外 |
| 依存の版の持ち方 | 包みに版を書く / 取り込む版の `.module` から読む | `.module` から読むか、`.module` と照らすテストを置く |
| AAR の版の固定 | 今、Android は最新の `dist/` を探して写す | Windows と同じく `VERSION.txt` で、2 つの AAR の完全なファイル名で固定する |
| 名前空間とフォルダ | 今の `Runtime/<Feature>/Android*.cs` | Windows と同じく `Runtime/Android/<Feature>/`（`unity-native-plugin` の Windows の C ABI のトピックが、Android も移すときにそうすると書いている） |
| 32 ビット（`armeabi-v7a`）を含む Unity のプロジェクト | C ABI は使えない | `DllNotFoundException` を「使えない」に写し、manager は失敗を返す。ビルドの設定で ARM64 だけにする案内をマニュアルに書く |
| `NOT_FOREGROUND` と AP-16 の写し方 | 4.6 の表 | 8.3 の列のとおりに保ち、保てないもの（`NOT_FOREGROUND` など）は移行ガイドに書く（第 1 部 AC-23 の原則） |
| 公開の JsonBuilder / JsonParser | 残す / 消す | 4.7 |

## 6. テスト

| 種類 | 今 | 2c |
|---|---|---|
| EditMode（`Tests/Runtime/Android*`） | 約 116 件。うち JSON の組み立てと解析が約 79 件（`AndroidClipboardJsonParserTests` 39、`AndroidShareJsonBuilderTests` 21、`AndroidClipboardJsonBuilderTests` 16、`AndroidNotificationJsonBuilderTests` 3） | 4.7 のとおり機能ごとに書き直す。Notification は公開の JSON の解析と、解いた値から C を呼ぶところ。Clipboard と Share は payload から C への写し。基準は 8.3 の「Unity の包みが保つこと」の列。加えて、構造体の配置（4.4）と、要求の ID が `ulong` であること |
| PlayMode（実機の Player で流す。`Tests/PlayMode/AndroidClipboardManagerIntegrationTests.cs`） | 11 件（`[UnityTest]`。Clipboard の JNI と IL2CPP） | C ABI の包みに合わせて直し、ほかの機能、初期化、差し替え型のリスナー（4.5）、完了が戻る前に来る場合（4.3）を足す |
| スクリプトのバックエンド | 今の Build Profile は 3 つとも IL2CPP だけ | Windows の移行と同じく Mono と IL2CPP の両方で流す。Mono 用の Build Profile か、バックエンドを上書きする手順を足す |

- **最初に確かめること**: 4.1 の「同じ実体」（`ntk_android_is_initialized()` が 1）
- 移す前の結果を基準として記録しておく（Windows の移行と同じ）

## 7. 作業用の配布物の作り方と、このリポジトリの側で確かめていないこと

- 2.0.0 の `dist/` はまだ作っていない（リリースの段で作る）。2c の作業用には、このリポジトリで次を流すと `dist/2.0.0/android/`（2 つの AAR、`m2/`、ヘッダー）ができる:

```sh
scripts/build_android_library_aar.sh -m android_library -m android_library_capi -v 2.0.0 --m2
```

  モジュールを指定しないと Kotlin の API の AAR だけになる。`-v` は必須（無いとエラーで止まる）。**このコマンドは、追跡しているファイル `android/gradle.properties` の `libraryVersion` を 2.0.0 に書き換える**ので、作業用に流したときはコミットせずに元に戻す
- 確かめていないこと:
  - Unity の `DllImport` で読んだ `libntk.so` と `NtkInitializer` の実体が同じこと（4.1）
  - `x86_64` の実機・エミュレータでの実行（手元は arm64 だけ。組めること、公開シンボル、16 KB の整列は照合で確かめた）

## 8. 問い合わせ

対応表（8.3）の読み方や、C ABI の振る舞いの疑問は、`native-toolkit` の `artifact/topics/android-c-abi/` の設計書を見て、足りなければこのリポジトリに課題として返す。C ABI の側を直すときは、2b と同じく設計書を直してから実装する。
