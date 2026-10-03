# Android の汎用 C ABI

- 記録日: 2026-10-03
- 改訂: 2026-10-03 に別モデル 2 者のレビュー（`reviews/2026-10-03-android-c-abi-plan-review-v1.md`）を反映した。決定を 4 つ決め直した（D-7、D-10 の ABI、D-11、D-17）。同日に 2 回目のレビュー（`reviews/2026-10-03-android-c-abi-plan-review-v2.md`）を反映し、D-2 の代わりの経路を消し、D-18（minSdk）を足し、D-11 と D-17 を具体にした。3 回目の確認（`reviews/2026-10-03-android-c-abi-plan-review-v3.md`）で残った 2 件を直し、レビューを終えた
- 分類: 横断課題（アーキテクチャ）。機能追加ではない
- 進め方: Windows（`windows-architecture`）と同じ汎用 C ABI を、1 OS ずつ作る。このトピックは Android の分で、最初に行う（D-1）。iOS / macOS は Android が終わってから別のトピックにする
- 対象: `android/android_library`、`android/unity_android_plugin`（新しい C ABI のモジュールに置き換える）、`android/AndroidLibraryExample`、`scripts/build_android_library_aar.sh`、`scripts/publish_docs.sh`、配布物 `android-native-toolkit-*.aar` / `unity-android-native-toolkit-*.aar`
- チケット: NTKIT-17（ブランチ `feature/NTKIT-17` の名前から。中身は未確認）
- 手本: `artifact/topics/windows-architecture/`（1.12.0 で出荷した Windows の C ABI）

## 0. 調べたこと

2026-10-03 に、観点の違う 3 つの調査と、ツールチェーンの版の調査を行った。外部の版情報は、レビューのときに公式の出典と Google Maven の AAR の実物でもう一度確かめた（レビュー v1 の事実の照合）。この README の事実は、断りがない限りこれらから引いている。

| 観点 | 調べたもの |
|---|---|
| Windows の C ABI のうち引き継ぐもの | C ABI の設計書（全 1,591 行）、段階 5・6 の結果、レビュー 2 回分、公開ヘッダー 4 つ、`check_c_abi_contract.py` / `check_manual_c_examples.py` |
| Android の今の公開面 | `unity_android_plugin` と `android_library` の全公開メソッド、JSON の入力、listener、manifest、テスト、`unity-native-plugin`（別リポジトリ）の C# 側 |
| NDK で C ABI を作る前提 | developer.android.com の JNI Tips、middleware ベンダー向けガイド、16 KB ページ、Prefab、NDK のリリース、Unity 6 / Flutter / Godot の公式文書（出典は 8.5） |
| ツールチェーンの版 | AGP、Gradle、Kotlin、androidx の最新の版と、利用者（Unity、Flutter）の上限（8.3） |

## 1. 何が問題か

### 1.1 Android には C ABI が無い

Windows の README（`windows-architecture/README.md` 1.1）は Android の構成を「`unity_android_plugin`: C ABI / JNI ブリッジ」と書いたが、実際には **Android に C / C++ のコードは 1 行も無い**（`externalNativeBuild`、CMake、`.so` はどれも無い）。

| 層 | 実体 |
|---|---|
| `android_library` | Kotlin の API（UseCase の集まり、`AndroidDialogFragment` など） |
| `unity_android_plugin` | Kotlin の `object` 4 つ（`UnityAndroid{Clipboard,Dialog,Notification,Share}Manager`）。Unity の C# が `AndroidJavaObject` で呼び、入力は JSON 文字列、結果は `AndroidJavaProxy` の listener で返す |

そのため、Unity 以外の C の利用者（Flutter の `dart:ffi`、Rust、Godot、React Native の C++、NDK のアプリ）は Android のライブラリを使えない。Unity も JNI の呼び出しを毎回 C# 側で組み立てている（`unity-native-plugin` の `Android*Manager.cs`、合計 2,395 行）。

### 1.2 ネイティブの利用者に届かないロジックが Unity のブリッジにある

`agent-rules/coding-rules/android.md` は「ネイティブ利用者に必要な機能を `unity_android_plugin` に置かない」と定めているが、次のものはブリッジにしか無い。C ABI はブリッジではなく `android_library` の上に載せるので、**これらを先に `android_library` へ移さないと C ABI から届かない**。

| 機能 | ブリッジにしか無いもの |
|---|---|
| Notification | 本文のタップ・アクションのボタン・dismiss を受ける `NotificationActionReceiver`（manifest に宣言）と、そのイベントの配送。リソース名から drawable / layout / id を引く処理（`getIdentifier`）。PendingIntent の request code の体系。`canScheduleExactAlarms` と設定画面を開く処理のフォールバック（ライブラリでは `ComponentActivity` が要る `NotificationPermissionHelper` の中にしか無い） |
| Share | カスタムの Chooser Action を受ける動的 Receiver の一式（`ShareChooserActionReceiverRegistry`、世代 token、`RECEIVER_NOT_EXPORTED`）。アイコンの Base64 のデコード |
| Clipboard | エラーコードの表（`CLIPBOARD_EMPTY_CONTENT` など 7 つ） |
| Dialog | `FragmentActivity` への変換と `show`。結果の値の正規化（単一選択の `null` → `-1`） |
| 共通 | main スレッドへの受け渡し |

ネイティブのサンプル（`AndroidLibraryExample`）も、通知のアクション・dismiss と Chooser Action を受ける Receiver を 3 つ自前で持っている。中身は Toast や画面内の broadcast などサンプル固有の表示だが、イベントを受ける仕組みがライブラリに無いので、利用者が自分で書く必要がある。

### 1.3 コールバックを返すスレッドが機能ごとに違う

| 機能 | 今の listener のスレッド |
|---|---|
| Clipboard | main |
| Share | main |
| Dialog | UI スレッド（Fragment から）。ただし内部のエラーは呼び出し元のスレッドで同期的に返る |
| Notification の操作の結果 | **呼び出し元のスレッドで同期的に**返る |
| Notification のアクション | main（`BroadcastReceiver.onReceive`） |

C ABI では 1 つの規則にそろえる必要がある（D-6）。

### 1.4 その他、移す前に分かっている不備

- Dialog: ブリッジの KDoc は「キャンセル時の入力は `null`」と書いているが、`AndroidDialogFragment.onCancel` は `""` を返す。Fragment の listener は保持されないので、画面の回転で消える。`showLoginDialog` がパスワードを `Log.d` に出している（`UnityAndroidDialogManager.kt` 406 行）。これは `agent-rules/coding-rules/android.md` の「全メソッドの先頭で全パラメータを `Log.d`」に従った結果で、規則どおりに受け口を書くと、パスワードやクリップボードの本文がまたログに出る（8.6）
- Notification: `launchAction` を JSON から読むが使っていない。shown のイベントはスケジュール通知でしか出ない
- Notification: 予約したスケジュール通知は、`AndroidNotificationCommandPayload` を Parcel ごと Base64 にして `SharedPreferences` に保存している（`NotificationSchedulerSupport.kt` 51-52 行）。Parcel には Parcelable のクラス名が入り、`platformOptions` は旧 `NotificationActionReceiver` を指す Intent を含む。`AlarmManager` に登録した PendingIntent も `ScheduledNotificationReceiver` のクラス名を明示している。そのため、**パッケージ名を変える（D-15）と、更新前に予約した通知は表示されず、`loadAll` の `runCatching` で黙って捨てられるので `restoreScheduled` でも作り直せない**。R8 でクラス名を難読化したアプリでも、更新のたびに同じ形で壊れうる（D-11）
- テスト: Dialog のテストはどのモジュールにも無い。Notification の instrumented テストと UI テストも無い。Android 用のテスト実行スクリプト（Windows の `scripts/test_windows.ps1` に当たるもの）も無い
- `consumer-rules.pro` が 2 つとも空。JNI から名前で引くクラスを R8 から守る設定が無い
- 依存: `android_library` は `material` を宣言しているが、コードで 1 度も import していない。`appcompat` は `AppCompatResources` の 1 か所だけで、`AndroidDialogFragment` が使う `fragment` は宣言せず `appcompat` 経由で入っている

## 2. なぜ今やるか

- Windows の C ABI が 1.12.0 で出荷され、規約（名前、エラー、UTF-8、ハンドル、`struct_size`、`user_data` と `release`）が確定した。規約が新しいうちに 2 つ目の OS に広げれば、OS をまたいで同じ作法を保てる
- `unity-native-plugin` は Windows の P/Invoke を書き直したばかりで、C ABI を扱う C# の土台（`[MonoPInvokeCallback]`、ハンドルの `SafeHandle` など）がある。Android も同じ形にすれば、C# 側の 2,395 行の `AndroidJavaObject` の組み立てを P/Invoke に置き換えられる
- 1.2 のロジックの移設は、C ABI と関係なくルール違反の解消である

## 3. 目標の構成

段階 4 が終わった時点の形（D-15・D-16 の決定を反映した後の名前で描く）。`(新)` は新しく作るもの、`(移)` は 1.2 のロジックを移して作るもの。クラス名は案で、設計書で決める。

```
android/                                         # Gradle のルート（D-16）
  settings.gradle.kts                            # 各モジュールを相対パスで include する
  gradle/libs.versions.toml                      # 8.3 の版。NDK、androidx.startup、UiAutomator を足す
  android_library/                               # Kotlin の API（android-native-toolkit-2.0.0.aar）
    consumer-rules.pro                           # (新) manifest と Parcel / JSON の保存で名前を使うクラスを R8 から守る
    src/main/AndroidManifest.xml                 # 今の Receiver / Service に、移した Receiver と透明な Activity が加わる
    src/main/java/com/jonghyunkim/nativetoolkit/ # パッケージ名（D-15）
      clipboard/{domain,application,data,presentation}/
        domain/error/ClipboardDomainError.kt     # (移) ブリッジのエラーの分類（7 つ）をここで表す
      notification/{domain,application,data,presentation}/
        data/ResourceNameResolver.kt             # (移) リソース名 → drawable / layout / id
        data/PendingIntentRequestCodes.kt        # (移) request code の体系（衝突と桁あふれを直す）
        data/ScheduledNotificationStore.kt       # (新) 予約の保存。ライブラリのデータは JSON、利用者の Intent は Intent.toUri。1.x の保存データと Alarm を破棄する（D-11）
        presentation/NotificationEventReceiver.kt # (移) 本文のタップ・アクション・dismiss を受ける
        presentation/NotificationEvents.kt       # (移) イベントを受け取る口。受け手が登録されるまでイベントを保つ（4 章）
        presentation/settings/                   # (移) Activity の要らない canScheduleExactAlarms と設定画面を開く処理
      share/{domain,application,data,presentation}/
        presentation/ChooserActionReceiverRegistry.kt # (移) Chooser Action の動的 Receiver の一式
      dialog/
        AndroidDialogFragment.kt                 # 今のまま
        presentation/                            # (新) 前面の Activity の上に出す口（D-7）
      common/presentation/
        LibraryInitializer.kt                    # (新) androidx.startup。ForegroundActivityTracker を登録する（Kotlin だけの利用者にも効く）
        ForegroundActivityTracker.kt             # (新) ActivityLifecycleCallbacks で前面の Activity を追う。遅い初期化では明示的に渡された Activity から始める
        HostActivity.kt                          # (新) 透明な FragmentActivity。前面が FragmentActivity でないときだけ使う（D-7）
    src/test/  src/androidTest/

  android_library_capi/                          # (新) 汎用の C ABI（android-native-toolkit-capi-2.0.0.aar）
    build.gradle.kts                             # ndkVersion（r30）、externalNativeBuild、prefabPublishing、abiFilters（arm64-v8a / x86_64）
    consumer-rules.pro                           # JNI から名前で引く Kotlin のクラスと native メソッドを R8 から守る
    src/main/AndroidManifest.xml                 # androidx.startup の Initializer の登録
    src/main/cpp/
      CMakeLists.txt                             # c++_static、-fvisibility=hidden、16 KB のページ
      libntk.map                                 # 公開するシンボル: ntk_* と JNI_OnLoad だけ（Windows の .def に当たる）
      include/NativeToolkitC/                    # 公開ヘッダー（Prefab と dist/ に入れる）
        Common.h                                 # OS に依存しない部分（Windows と共通。分け方は 3.3）
        Android.h                                # ntk_android_init など Android だけの関数と定数
        Clipboard.h  Dialog.h  Notification.h  Share.h
      src/
        Common/                                  # JNI_OnLoad と RegisterNatives、JNIEnv の取得と attach / detach、
                                                 # jclass / jmethodID のキャッシュ、ハンドル、UTF-8 と Modified UTF-8、
                                                 # エラー、struct_size の読み取り、コールバックの登録表と release
        Clipboard/  Dialog/  Notification/  Share/   # C の入口。検査して Kotlin の受け口を JNI で呼ぶだけ
    src/main/java/com/jonghyunkim/nativetoolkit/capi/  # Kotlin の受け口。android_library を呼んで型を変換するだけ
      NtkInitializer.kt                          # androidx.startup（LibraryInitializer に依存）: Context を保存して System.loadLibrary("ntk")。
                                                 # UnsatisfiedLinkError（32 ビットで入れたアプリ）は捕まえて「C ABI は使えない」状態にし、アプリを落とさない
      clipboard/  dialog/  notification/  share/ # 機能ごとの受け口と、ネイティブへ戻す native メソッド

  android_library_capi_test/                     # (新) C ABI のテスト。テスト用の .so（GoogleTest とテストの入口）を持つ。
                                                 # 配る AAR にテスト用のものが混ざらないよう、モジュールを分ける
  android_library_capi_smoke/                    # (新) 配布物だけを使う C のアプリ（Windows の CT-21 に当たる）。
                                                 # ビルドが作った Maven リポジトリ（リリースでは dist の m2/）から 2 つの AAR を解決し、
                                                 # Prefab でヘッダーを使う。R8 を有効にして組む
  AndroidLibraryExample/app/                     # ネイティブのサンプル。Kotlin の API だけを使う
    src/androidTest/                             # (新) 全機能の UI テスト（段階 0c）
```

無くなるもの:

| 対象 | 時期 |
|---|---|
| `android/unity_android_plugin/`（`unity-android-native-toolkit-*.aar`） | 段階 3 |
| `android/AndroidLibraryExample/` の Gradle のルートとしての役割（`settings.gradle.kts`、`gradlew`、`gradle/`） | 段階 0（D-16） |
| `android/AndroidLibraryExample/android_library/` と `android/AndroidLibraryExample/unity_android_plugin/`（どこからも使っていない古い雛形。Git の管理下にある） | 段階 0 |
| `android_library` の `material` の依存（使っていない） | 段階 0g |

配布物（`dist/<リリース版>/android/`。D-9、D-17）:

| ファイル | 中身 | 使う人 |
|---|---|---|
| `android-native-toolkit-2.0.0.aar` | Kotlin の API | Kotlin / Java のアプリ |
| `android-native-toolkit-capi-2.0.0.aar` | Kotlin の受け口、`jni/<abi>/libntk.so`、`prefab/`（ヘッダー） | C の利用者。`android-native-toolkit-2.0.0.aar` も一緒に入れる |
| `m2/`（ファイルの Maven リポジトリ） | 上の 2 つの AAR と、POM・Gradle Module Metadata。座標は `io.github.kimjh4941:android-native-toolkit:2.0.0` と `io.github.kimjh4941:android-native-toolkit-capi:2.0.0`（D-17） | Gradle で組む利用者。リポジトリを足せば androidx などの依存も解決される。ただし足す場所はホストによって違う（Flutter はプラグインではなくアプリのプロジェクトに足す。Unity が書き出す Gradle は `PREFER_SETTINGS` と flatDir なので、`unity-native-plugin` は m2 を使わず依存を明示的に足す。2c） |
| `include/NativeToolkitC/*.h` | 公開ヘッダー（AAR の中と同じもの） | ヘッダーからバインディングを作る人（ClangSharp、bindgen、ffigen） |

依存の向きは `android_library_capi` → `android_library`。Windows と同じく、**機能の実装は `android_library` にだけ置き**、`android_library_capi` は型の変換（UTF-8 のバイト列と `String`、ハンドルと Kotlin のオブジェクト、関数ポインタと Kotlin のラムダ）だけを受け持つ。

| 利用者 | 使うもの |
|---|---|
| Kotlin / Java のアプリ | `android_library`（今のまま） |
| C の利用者（Unity、Flutter、Rust、Godot、React Native の C++、NDK のアプリ） | `android_library_capi` |

### 3.1 利用者の前提

`android_library_capi` は汎用の C ABI で、C の関数を呼べる言語（C#、Dart、Rust、C / C++、Go、Python の cffi など）から使える。ただし Windows の DLL と違い、次の前提がある。C ABI の設計書では、Windows のスレッドの前提と同じく冒頭に置く。言語ごとの導入の手順（AAR の置き場所、Gradle の依存、`.so` の名前、Prefab、初期化、コールバックの受け方、R8）はマニュアルに書く（段階 4）。

| 前提 | 理由 | 成り立たない使い方 |
|---|---|---|
| Android アプリのプロセスの中で呼び、アプリが Kotlin / Java のコードを持つ（`android:hasCode="true"`） | 中身は JNI で Kotlin を呼ぶので、ART（JavaVM）と Context と AAR のクラスが要る | `adb shell` で動かす単体の実行ファイル。`hasCode="false"` の NativeActivity だけのアプリ |
| アプリの既定のプロセスから呼ぶ | androidx.startup の Initializer は既定のプロセスでしか動かない | 別のプロセス（`android:process`）から呼ぶ場合は、`ntk_android_init` を先に呼ぶ必要がある（D-4） |
| 2 つの AAR と、それが依存するライブラリをアプリの Gradle のビルドに入れる | Kotlin の受け口、manifest の Receiver と Activity、Initializer が AAR に入っている。依存（androidx の core、fragment、startup など）は `m2/` の POM から解決するか、マニュアルの一覧のとおり足す（D-17） | `.so` だけをコピーして `dlopen` する使い方。なお Kotlin だけの利用者にも、2.0.0 から androidx.startup の依存と `InitializationProvider` が入る（`LibraryInitializer`） |
| 自分が作っていないスレッドからのコールバックを受けられる | コールバックは Android の main スレッドから呼ぶ（D-6） | 呼び出し元のスレッドでしか関数ポインタを受けられない仕組み（Dart の `NativeCallable.isolateLocal` など）。Unity は `[MonoPInvokeCallback]`、Dart は `NativeCallable.listener` で受ける |
| Dialog と権限の要求は、アプリが前面にいるときに呼ぶ | 前面の Activity の上に出す。前面が `FragmentActivity` でなければ透明な Activity を起動するが、Android 10 以降はバックグラウンドから Activity を起動できない（D-7） | アプリが後ろにいるときの呼び出し（専用のエラーを返す） |
| アプリの minSdk が 31 以上（D-18） | AAR の minSdk | Android 11 以前の端末 |
| C ABI を使えるのは 64 ビット（`arm64-v8a` か `x86_64`）で動くときだけ | 出荷する `.so` は 64 ビットだけ（D-10） | 32 ビットで入ったアプリ（32 ビットだけの端末、32 ビットの ABI だけを組んだアプリ）。この場合もアプリは落ちないが（`NtkInitializer` が捕まえる）、`.so` が無いので、C# の `DllImport` は `DllNotFoundException`、Dart の `DynamicLibrary.open` は例外になる。利用者はこれを扱うか、`abiFilters` で 64 ビットだけを組む（マニュアルに書く） |
| manifest の merge で、通知の権限とコンポーネントがアプリに入る | `android_library` が通知の機能のために宣言している（`USE_FULL_SCREEN_INTENT`、`SCHEDULE_EXACT_ALARM`、前景サービスの権限、`RECEIVE_BOOT_COMPLETED`、BootReceiver、前景サービス 2 つ） | 要らない権限は、利用者が `tools:node="remove"` で外す（手順をマニュアルに書く。8.6） |

Kotlin / Java のアプリは C ABI を使わず、`android_library` を直接呼ぶ。C ABI を通すと JNI を往復するだけになる。

### 3.2 Windows と同じにするもの、Android で決め直すもの

Windows の C ABI の設計書の決定 E-1〜E-21 と、前提の D-4〜D-10 を次のとおり扱う。

| 扱い | 対象 |
|---|---|
| そのまま引き継ぐ | 名前の規則（`ntk_<機能>_<動詞>`）、エラーは戻り値（機能ごとの `int32_t` の列挙、0 が成功、欠番は詰めない）、UTF-8 だけ（E-7）、真偽値は `int32_t`（E-8）、0 で埋めた構造体が既定値（E-9）、出力はすべてハンドル（E-5）、`struct_size` の読み方（先頭 8 バイト、8 バイト単位で増やす、上限 4096。64 ビットだけを出すので Windows と同じ配置になる。D-10）、すべてのコールバックの `void* user_data` と、ちょうど 1 回呼ぶ `release`（E-12 の形）、`_free(NULL)` は何もしない、`NULL` の入力の扱い（E-15）、U+FFFD への置き換え（E-16）、件数は `size_t`（E-17）、非同期の完了はシステムコードを引数で渡す（E-18）、`ntk_version()` とリテラルの版のマクロ、公開ヘッダーは `<stdint.h>` と `<stddef.h>` だけ・ASCII だけ・C99 と C++ の両方でコンパイルできる |
| Android で決め直す | 寿命の対応先（C++ のオブジェクト → JNI のグローバル参照、E-1）、`ntk_last_system_code()` に入れる値（E-4、D-13）、公開の方法（`.def` → リンカーの version script と `RegisterNatives`、D-5・D-10）、対象の ABI（x64 だけ → `arm64-v8a` と `x86_64`、E-17）、スレッドの規則（STA とメッセージループ → Android の main スレッド。D-6）、`release` を呼ぶスレッド（D-6）、`HWND` の代わりに使うもの（Context と前面の Activity。D-4、D-7）、文字列の変換（JNI の Modified UTF-8 を通さない。8.6） |
| Windows 専用で関係しない | E-6、E-10 の中身、E-11、E-13、E-19、E-20 の中身、E-21 |

### 3.3 OS をまたいだヘッダーの扱い

規約と、OS に依存しない部分のヘッダーは OS 間で共通にし、機能のヘッダーは OS ごとに持つ（D-3）。機能の中身が OS ごとに違うためである（Windows の Clipboard には履歴と遅延レンダリングがあり、Android には URI と sensitive がある。通知の作り方はまったく違う）。**同じ意味の操作には同じ名前を付ける**（たとえば `ntk_clipboard_read` 系）が、OS をまたいで同じヘッダーで書ける 1 つの API にはしない。それは `unity-native-plugin` の C# の層が受け持つ。

ただし、今の Windows の `Common.h` には Windows 専用のもの（`NTK_SYSTEM_CODE_E_OUTOFMEMORY` = HRESULT の値）と「DLL の版」という説明があり、そのままでは共通にできない。C ABI の設計で次の 2 つを決める（8.6）。

- `Common.h` を「OS に依存しない部分」と「OS ごとの定数（`Windows.h` / `Android.h`）」にどう分けるか。共通の部分をリポジトリの 1 か所に置いて両方のビルドから使うか、OS ごとに写して照合スクリプトで一致を確かめるか。Windows の側を直すなら、Windows の C ABI の互換を保つ形（定数を移すだけで値と名前は変えない）にし、ヘッダー・`check_c_abi_contract.py`・Windows のマニュアルを段階 2a で一緒に直す
- `NTK_VERSION` が OS ごとのライブラリの版か、OS をまたいだ規約の版か。C# の 1 つのバインディングで定数を共有できるかに関わる

Share のヘッダーは Windows に無い。Android で初めて作るので、名前は OS に依存しない形にしておく（後で Windows / iOS / macOS に足せるように）。

## 4. Kotlin の API の方針

C ABI の前に、1.2 のロジックを `android_library` へ移し、ネイティブの利用者が Kotlin だけで全機能を使えるようにする。Windows の段階 3（C++ API）に当たるが、Windows のように API を全部書き直すのではなく、**足りない部分を足す**作業になる。

足す API の形（イベントの口、前面の Activity、権限の要求、Context の扱い）は、C ABI の要求（main からの非同期のコールバック、ちょうど 1 回の `release`、複数の登録）で決まる。そのため、**C ABI の設計書のスレッド・寿命・Context の章を先に決めてから、Kotlin の API の設計書を書く**（5.1）。

| 足すもの | 置き場所（案） |
|---|---|
| 通知のタップ・アクション・dismiss を受ける Receiver と、イベントを受け取る口（今はグローバルの listener 1 つ）。**受け手が登録されるまでイベントを保ち、登録したときに 1 回だけ渡す**。プロセスが死んだ後やコールドスタートで、利用者の関数ポインタがまだ登録されていない間に届いたイベントを捨てないため（今のブリッジは捨てている）。保つ件数・期限・順序・重複の扱いは設計書で決める | `notification/presentation/` |
| リソース名からの解決 | `notification/data/` |
| PendingIntent の request code の体系（今は `id + Int.MAX_VALUE/4` などで、衝突と桁あふれの余地がある） | `notification/data/` |
| 予約の保存形式を変える: ライブラリのデータは JSON、利用者が渡した `Intent` は `Intent.toUri` で保存する（Parcel は永続化に使わない）。1.x で保存したデータと Alarm は、2.0.0 への更新の後に一度だけ破棄する（D-11） | `notification/data/` |
| Activity の要らない `canScheduleExactAlarms` と、設定画面を開く処理 | `notification/presentation/` |
| 前面の Activity を追う仕組みと、その上に Dialog と通知の権限の要求を出す口。前面が `FragmentActivity` でなければ透明な `FragmentActivity` を起動する（D-7）。追う仕組みは `android_library` の Initializer（androidx.startup）が登録するので、Kotlin だけの利用者にも効く。Startup を無効にしたアプリや遅い初期化では、明示的な初期化で今の Activity を受け取れるようにする | `common/presentation/`、`dialog/`、`notification/presentation/permission/` |
| Chooser Action の動的 Receiver の一式 | `share/presentation/` |
| Clipboard のエラーの分類（今のブリッジの 7 つのコード） | `clipboard/domain/error/`（`ClipboardDomainError` との対応を決める） |

`shareText` が Chooser Action を JSON 文字列で受け取っている（`ShareTextUseCase.kt` 22 行）のは、Kotlin の API としては型にする。

ブリッジには手を入れない（段階 3 で消すので、委譲の形に作り替えても出荷されない）。そのため段階 1b から 3 までは、移したロジックがブリッジと `android_library` の 2 か所にある。この間に見つけた不具合は `android_library` の側だけを直し、ブリッジの側は直さない。

## 5. 段階

1 段階 = 1 PR を基本にする。Windows と同じく、段階 0a〜0d でテストをそろえてから着手する。

| 段階 | 内容 | 動作の変更 |
|---|---|---|
| 0 | Gradle のルートを `android/` に移す（D-16）。サンプルを `android/AndroidLibraryExample/app` のままモジュールの 1 つにし、全モジュールを相対パスで include する。どこからも使っていない古い雛形もここで消す。`scripts/build_android_library_aar.sh`、`scripts/publish_docs.sh`、`agent-rules/workflows/` の Gradle の呼び出しを直す | 無し |
| 0a | スパイク: サンプルの UI テストで扱える項目を確定する（7.2）。UiAutomator で、通知のシェードのタイトル・本文・アクションのボタン・入力欄・dismiss、POST_NOTIFICATIONS のダイアログ、Chooser と Chooser Action、Direct Share、スケジュール通知、前景サービスの通知を扱えるか。アプリ内の Dialog は Espresso / Compose のテストで扱えるか。予約の復元を、2 段の手順（予約 → プロセスの終了か再起動 → 確認）で自動化できるか。アプリの更新で `AlarmManager` の Alarm が残るか（D-11） | 無し |
| 0b | サンプルの画面に testTag を付ける（今は全画面で 0 個。Windows の AutomationId に当たる。見た目も動作も変えない） | 無し |
| 0c | Dialog / Notification / Share の UI テストを足す（Clipboard は 14 件ある）。UiAutomator で扱えない項目は、人の確認の手順書にする。テストの依存（UiAutomator 2.4.0 など）は、今のツールチェーンで入る版を使う（8.3 で確かめた範囲では AGP 8.1.1 / compileSdk 34 で入る） | 無し |
| 0d | `scripts/test_android.sh` を作り（unit・instrumented・UI テストをまとめて実行）、**今のコードで全件通ることを確かめ、結果を基準として記録する**。基準は API 35 と API 36 の 2 つのエミュレータで取る（0h で targetSdk 36 にしたときの変化を見るため） | 無し |
| 0e | パッケージ名を `com.jonghyunkim.nativetoolkit.*` に変える（D-15）。機械的な改名だけを行い、0d の基準と同じ結果になることを確かめる。ブリッジ（`android.unity.*`）は改名しない（段階 3 で消すので）。改名の前の名前と作り方（`SharedPreferences` の名前、Alarm のコンポーネント名、action の文字列、request code の式（`"tag::id".hashCode()`）、data の URI の scheme、PendingIntent の flags）を結果に記録する（1b で 1.x の Alarm を取り消すときに使う） | Kotlin の利用者から見たパッケージ名が変わる（2.0.0） |
| 0f | ビルドの道具を上げる: AGP 9.3.1、Gradle 9.7.0、Kotlin 2.4.20（`languageVersion = apiVersion = 2.2`）、AGP 9 の新しい DSL と組み込みの Kotlin、Dokka 2.2.0（`publish_docs.sh` の `dokkaHtml` も直す）、JVM 17。**SDK と依存の版は変えない**。0d の基準と同じ結果になることを確かめる | 無し |
| 0g | 依存と compileSdk を上げる: compileSdk 36、androidx（8.3）、`aarMetadata.minCompileSdk = 36`。使っていない `material` を外し、`fragment` を明示の依存にする。`appcompat` を外せるかも確かめる。0d の基準と同じ結果になることを確かめる | 利用者の最低条件が 8.3 のとおり上がる |
| 0h | サンプルの targetSdk を 36 にする。UI テストを直してよいのはこの段だけで、直した理由を結果に記録する | サンプルの targetSdk が 36 になる |
| 1a | スパイク: NDK のビルド（8.2）。結果で D-4・D-6・D-9・D-10・D-13 を決め、C ABI の設計書を書く | 無し |
| 1b | Kotlin の API を補完する（4 章）。1.2 のロジックを `android_library` へ移し、イベントを保つ口、予約の保存形式と 1.x のデータの破棄、前面の Activity と透明な Activity を足す。サンプルの Receiver を、移したライブラリの仕組みに置き換える。新しい API（Activity の要らない Dialog と権限の要求、イベントの口）を使う画面をサンプルに足す | 1.x で予約した通知を破棄する（D-11）。それ以外の、ネイティブの利用者から見た動作は変えない。Kotlin の利用者に androidx.startup の依存が入る |
| 2a | `check_c_abi_contract.py` と `check_manual_c_examples.py` を OS ごとに動くようにする（パス、機能名、操作の数、公開シンボルの読み方、コンパイラを OS ごとの設定にする）。照合の対象に、イベントと完了のコールバック（6 章の振る舞いの集合）を入れる。C ABI の設計で `Common.h` を分けると決めた場合は、Windows の側（ヘッダー、照合、マニュアル）もここで直す（3.3） | 無し（`Common.h` を分ける場合も、Windows の C ABI の名前と値は変えない） |
| 2b | `android_library_capi` を作り、C ABI を実装する。C ABI のテスト（`android_library_capi_test`）と smoke（`android_library_capi_smoke`）。ビルドスクリプトに capi の AAR と `maven-publish` の Maven リポジトリの生成を足し、smoke はその一時的なリポジトリから解決する（リリースのときに `dist/<版>/android/m2/` へ写す）。**完了の条件に 2a の機械照合を入れる** | C ABI が増える（新しい配布物） |
| 2c | `unity-native-plugin`（別リポジトリ）を C ABI に移す: AAR のコピー（`PreBuildProcessor` は今、古い 2 つの AAR を必須にしている）、P/Invoke、KGP の適用をやめて実行時の `kotlin-stdlib` 2.2 以上と androidx の依存だけを足す（`PostBuildProcessor` は KGP 2.0.21 を当てており、AGP 9 の Unity ではビルドの失敗の原因になりうる）、Runtime / PlayMode / Player テスト。こちらは対応表を出し、書き換えは向こうで行う。**2c の成功を段階 3 を始める条件にする** | Unity が C ABI を呼ぶ |
| 3 | `unity_android_plugin` を削除する。ビルドスクリプト、`publish_docs.sh`、`scripts/check_design_consistency.py`、`scripts/README.md`、`dist/`、Dokka、README、`agent-rules/coding-rules/{android,common}.md`、`agent-rules/workflows/`（write-manual、implement-sample-app など）から外す | `unity-android-native-toolkit-*.aar` が無くなる（D-2） |
| 4 | ドキュメント: マニュアルの Android の章に C ABI の節を足す（3 言語）。既存の Android の章の `android.library.*` を新しいパッケージ名に書き換える（dialog と notification の 3 言語で計 75 か所）。2.0.0 の移行ガイド（パッケージ名、ブリッジの AAR の廃止、1.x で予約した通知の破棄、Unity の動作環境）、言語ごとの導入の手順、依存の一覧、権限の外し方を書く。Doxygen と `docs/` を合わせる | - |

**順番の理由**:

- 0e〜0h は、0d の基準と同じ UI テストが通ることで、動作が変わっていないことを確かめる。0f〜0h を 3 つに分けるのは、差が出たときに原因を切り分けるため（Windows の段階 1 で C++20 にしたのと同じ考え方）
- 1a（NDK のスパイク）を 1b の前に置くのは、1b で足す Kotlin の API の形が C ABI の要求で決まるため。1a は 1b に依存しない（NDK の雛形だけで試せる）
- 1b を 2b の前に置くのは、逆にすると C ABI の受け口がブリッジの中のロジックに依存するか、ブリッジのロジックを C ABI 用にもう 1 つ書くことになるため
- 2a を 2b の前に置くのは、C ABI の完了を機械照合で判定するため
- 3（ブリッジの削除）は 2c の後。先に消すと `unity-native-plugin` が組めなくなる

**段階 3 は段階 2 と同じリリースで出す**（D-2）。Unity は、このリリースから `android_library_capi` の C ABI を P/Invoke で呼ぶ。2c が終わらなければ、2.0.0 のリリースを待つ（ブリッジをもう 1 リリース配る経路は作らない）。

### 5.1 設計書

この README は企画書の役割を持つ。設計書は公開 API を決める段階とテストの段階だけに書く。

| 設計書 | 書く時期 | 書くこと |
|---|---|---|
| UI テスト | 0a の後、0b の前 | 機能ごとのテストケースの一覧と、確かめる内容。UiAutomator で扱う項目と人が確かめる項目の分担（0a の結果に基づく）。出発点は既存のサンプルアプリの設計書にある手動確認の観点 |
| C ABI | 1a の後。1b の前に、スレッド・寿命・Context の章と D-4・D-6・D-8・D-9・D-10・D-13 の決定を終える。関数の一覧と付録 A のヘッダーまで含めた全体は 2b の前に終える | 公開 API。Windows の設計書と同じ構成（名前の規則、3 つの受け渡し方式、スレッドの前提、エラー、メモリ、`struct_size`、全関数の一覧、付録 A のヘッダー）。**今のブリッジの 69 メソッドと新しい関数の対応表**と、6 章の振る舞いの集合。8.6 の項目 |
| Kotlin の API の補完 | C ABI の設計書のスレッド・寿命・Context の章と残りの決定を終えた後、1b の前（C ABI の設計書の全体を待たない） | ネイティブの利用者に公開する Kotlin の API が増える。**今のブリッジの約束が新しい API のどこで守られるかの対応表**を含める |

スパイク（0a、1a）の結果は設計書にせず `results/` に記録する。0b・0c は UI テストの設計書に従う。段階 0・0d・0e〜0h・2a・2c・3・4 は設計書を書かない（この README の表で足りる。2c は対応表を渡す）。

C ABI の設計書は、Windows の設計書を手本に、3.2 の「Android で決め直す」項目と 8.6 を新しく書く。公開 API の 2 本（Kotlin の API の追加分と C ABI）は、これまでと同じく別のモデルにレビューしてもらってから着手する。

置き場所:

```
artifact/topics/android-c-abi/
  README.md                                          # この文書
  designs/
    YYYY-MM-DD-android-c-abi-ui-test-design.md       # 段階 0
    YYYY-MM-DD-android-c-abi-design.md               # 1a の後に書く。スレッド・寿命・Context の章は 1b の前、全体は 2b の前に終える
    YYYY-MM-DD-android-c-abi-kotlin-api-design.md    # 段階 1b
  reviews/
  results/
```

ファイル名に OS 名を入れるのは、`artifact/README.md` の決まり（ファイル名だけで引用されても OS が分かる）に合わせるためである。

### 5.2 段階ごとに壊れる場所

| 場所 | 内容 | 影響する段階 |
|---|---|---|
| `android/AndroidLibraryExample/settings.gradle.kts` | ライブラリを絶対パスで include している。ルートを移すと消える | 0 |
| `scripts/build_android_library_aar.sh` | `android/AndroidLibraryExample` の gradlew を呼び、`gradle.properties` の `libraryVersion` を書き換える。ブリッジの AAR も作る。capi の AAR と Maven リポジトリは作らない | 0・2b（capi と m2 を足す）・3 |
| `agent-rules/workflows/release/workflow.md` | Android の配布物を `dist/` に置く手順。m2 とヘッダーが加わる | 2b |
| `scripts/publish_docs.sh` | `android/AndroidLibraryExample` の gradlew と、`:android_library:dokkaHtml` / `:unity_android_plugin:dokkaHtml` を呼ぶ | 0・0f（Dokka v2 で `dokkaHtml` が無くなる）・3 |
| `agent-rules/workflows/implement-feature/workflow.md` など | Android の Gradle の呼び出しの手順。write-manual・implement-sample-app などはブリッジを参照している | 0・3 |
| `agent-rules/coding-rules/{android,common}.md`、`scripts/check_design_consistency.py`、`scripts/README.md` | ブリッジ（`unity_android_plugin`）を参照している | 3 |
| 予約した通知の保存データと Alarm | クラス名とパッケージ名が入っている（1.4） | 0e（壊れる）・1b（破棄して新しい形式にする） |
| `unity-native-plugin` の `PreBuildProcessor` / `PostBuildProcessor` | 古い 2 つの AAR を必須にし、KGP 2.0.21 を当てている | 2c（直す）・3（直していないと組めない） |
| マニュアル（`manual/<版>/{dialog,notification}.*.md`） | `android.library.*` を 3 言語で計 75 か所参照している | 0e・4 |
| `unity-native-plugin` の Runtime テスト | 約 60 件は JSON の組み立てと解析のテストで、C ABI では意味を失う。書き換えではなく作り直しになる | 2c |

## 6. 公開面の規模

今のブリッジの公開面（調査の結果）:

| 機能 | 公開メソッド | うち操作・問い合わせ | 入力 JSON | listener |
|---|---|---|---|---|
| Clipboard | 15 | 10 | 4 種 | 2 |
| Dialog | 13 | 6 | 無し（位置引数） | 6 |
| Notification | 27 | 20 | 3 種（style 6 種、action、view action、リソース参照などが入れ子） | 3 |
| Share | 14 | 9 | 6 種 | 2（メソッドは 3） |
| 計 | 69 | 45 | | 13（メソッドは 14） |

C ABI が置き換えるのは、45 の操作だけでなく、**次の振る舞いの集合**である（D-5）。これを C ABI の設計書の対応表と 2a の機械照合の対象にする。操作だけを数えると、イベントを置き換えないまま段階 3 でブリッジを消せてしまう。

| 種類 | 中身 |
|---|---|
| 操作・問い合わせ | 45（上の表） |
| 操作の完了 | Clipboard / Notification / Share の操作の結果（今の `on*Operation`）、Share の結果（`onShareResult`）、Dialog の 6 種の結果 |
| 自発のイベント | Clipboard の変更、通知のタップ・アクション・dismiss、通知の shown、Chooser Action |
| 登録と解除 | 上のイベントの受け手の登録と解除（今の `set*Listener` / `clear*Listener`）、Clipboard の監視の開始と停止 |
| 追加 | 通知の権限の要求（今は C# が Unity の `Permission.RequestUserPermission` で済ませている） |

Windows では 47 の操作が 105 の C 関数になった（ハンドルの読み取り関数とビルダーで増える）。Android も 100 前後になる見込みで、Notification のビルダー（通知の項目 30 と style の入れ子）がその半分ほどを占める。

`android_library` にあるがブリッジが公開していないもの（CallStyle、`getActive`、`createChannels`、`restoreScheduled`、Media の style）は 2.0.0 の C ABI に入れない（D-5）。後から関数を足せば互換を保てる。

## 7. 検証方法

| 層 | 手段 | 守るもの |
|---|---|---|
| Kotlin の単体テスト | `android_library` の unit テスト（今 83 件） | ライブラリの内部 |
| instrumented テスト | `android_library` の androidTest（今 20 件）。1b で、移すロジックに当たるブリッジのテストを書き直して足す | Android の API を通した動作 |
| C ABI のテスト | `android_library_capi_test`: テスト用の `.so`（GoogleTest とテストの入口）を instrumented テストから動かす。C ABI は JavaVM と Context が要るので、端末かエミュレータの上でしか試せない | NULL と不正な入力の拒否、`struct_size`、`release` の回数と競合、スレッド、attach / detach、UTF-8 と Modified UTF-8、JNI の例外、初期化（自動・明示・Startup の無効・`dlopen` だけ・別の provider が先） |
| smoke | `android_library_capi_smoke`: ビルドが作った Maven リポジトリから 2 つの AAR だけを解決し、Prefab のヘッダーで組む C のアプリ。R8 を有効にした release で組み、`arm64-v8a` と `x86_64` の両方でリンクする | 配布物だけで使えること。R8 を有効にした利用者で JNI の名前が壊れないこと |
| サンプルの UI テスト | `AndroidLibraryExample` の androidTest（今 23 件: Clipboard 14 件、受け取った共有の解析 8 件、雛形 1 件。段階 0c で全機能に広げる）。API 35 と API 36 のエミュレータ | 0e〜0h と 1b の前後で、ネイティブの利用者から見た動作が変わらないこと |
| 更新のテスト | 1.x のサンプルで予約した後に 2.0.0 へ更新する（0a で確かめる 2 段の手順を使う）。保存した予約（`persistAcrossBoot=true`）は Alarm が取り消され保存データが消えること、保存しなかった予約は発火しても何も表示されずアプリが落ちないこと、新しく予約できることを確かめる | D-11 |
| 32 ビットのテスト | 64 ビットの端末に `adb install --abi armeabi-v7a` でサンプル（32 ビットの ABI も組んだもの）を入れ、起動して Kotlin の機能が使えることを確かめる（`.so` が無いので C ABI の関数そのものが存在しない。C ABI の利用者の側の扱いは 3.1 のとおりマニュアルの契約にする） | D-10 |
| Unity | `unity-native-plugin` の Android のテスト（今の Runtime はメソッド 97・展開後 116 ケース、PlayMode はメソッド 12（`[UnityTest]` 11 + `[Test]` 1）。C ABI に合わせて作り直す）と Player テスト | Unity から C ABI を通した動作。別リポジトリで行う（段階 2c） |

件数は、ランナーが報告する展開後の件数で記録する（`test_android.sh` の基準も同じ）。

1b は「動作を変えない」移設なので、Windows の段階 3 と同じく、**移す前後で同じサンプルの UI テストが通ること**を根拠にする。ただし、移すロジックの多く（リソース名の解決、request code、Clipboard のエラー、Activity の要らない Dialog と権限の要求）はサンプルの UI テストを通らない。そこで 1b の完了の条件に、次の 2 つを足す。

- 移すロジックに当たるブリッジのテスト（unit 77 件・instrumented 10 件のうちの該当分）を `android_library` のテストに書き直し、すべて通ること
- 新しい API を使う画面をサンプルに足し、UI テストで通すこと

今のブリッジのテストそのものは基準にしない。ブリッジは段階 3 で消え、Unity は C ABI を呼ぶ形に書き換わるので、ブリッジの動作を前後で比べる場面が無い。

### 7.1 サンプルの UI テストで守れる範囲

Windows では、移行前のサンプルが C ABI を呼んでいたので、サンプルの UI テストがそのまま C ABI の動作の基準になった。**Android のサンプルはブリッジを通らず、`android_library` を直接呼んでいる**（`AndroidLibraryExample` は `unity_android_plugin` に依存しない決まり）。そのため、サンプルの UI テストで守れるのは、ネイティブの利用者から見た動作だけである。

| 守るもの | 基準 | 1b で変わる所 |
|---|---|---|
| ネイティブの利用者から見た動作 | サンプルの UI テスト（段階 0c） | サンプルが自前で持つ Receiver 3 つを、`android_library` に移した仕組みに置き換える。**通知のタップ・アクション・dismiss と Chooser Action がこれまでどおり届くこと**を UI テストで確かめる。ここが 1b でいちばん壊れやすい |
| Unity から見た動作 | 前後の比較はしない。Unity は `android_library_capi` を呼ぶ形に書き換わり、ブリッジは 1b で手を入れずに段階 3 で消す | 無し。変わる振る舞いは、C ABI の設計書の対応表（今のブリッジの 69 メソッドと 6 章の振る舞いの集合 → 新しい関数）に書く |
| C ABI | C ABI のテストと smoke（段階 2b）、`unity-native-plugin` の C ABI 版のテスト（段階 2c） | 新規なので前後の比較は無い |

サンプルは段階 2 以降も Kotlin の API だけを使い、C ABI は使わない（Windows でもサンプルは C++ API だけを使う）。

### 7.2 UiAutomator と人の確認の使い分け

基本は自動化する。アプリ内の画面と Dialog は Compose / Espresso のテストで、通知のシェード・権限のダイアログ・Chooser などのシステムの UI は UiAutomator で扱う。**扱えないと段階 0a で確かめた項目だけ**を人の確認にし、手順書を用意する（Windows の computer use の決まり（`windows-architecture/README.md` 7.3）に合わせ、判定があいまいなら失敗とする）。

システムの UI は OS の版で見た目と構造が変わるので、UI テストはエミュレータの版を固定して流す（API 35 の `Pixel_8_Android_15` と、API 36 のエミュレータ。API 36 は作る必要がある）。

目標はサンプルの全機能を自動化することだが、次の項目は自動化が難しい見込みである（段階 0a で確定する）。

| 項目 | 難しい理由 | 扱いの案 |
|---|---|---|
| 画像の中身（BigPicture、大きいアイコン、カスタムビューの画像） | 画像の要素があることは分かるが、どの画像かは分からない（Windows と同じ） | 人の確認（Claude のデスクトップアプリの computer use でエミュレータの画面を見る） |
| 音・振動 | UI からは確かめられない | 対象外。チャンネルの設定値は API で確かめる |
| Direct Share の共有先が Chooser に並ぶこと | 並ぶかどうかと順番を OS が決める | 登録は `ShortcutManager` の API で確かめ、Chooser に並ぶことは人の確認 |
| Media の style | Android 13 以降はシェードではなくメディアのプレーヤーの枠に出る | 段階 0a で確かめる |

再起動の後の予約の復元は、`test_android.sh` から 2 段の手順（予約 → プロセスの終了か再起動 → 再接続して確認）で自動化する見込みで、0a で確かめる。

自動化できる見込みのもの: アプリ内の画面と Dialog（Compose / Espresso）、通知のシェードのタイトル・本文・展開・アクションのボタン・入力欄（RemoteInput）・dismiss・進捗・グループ・CallStyle・スケジュール通知、通知の権限のダイアログ（権限の取り消しはシェルのコマンドで行う）、Chooser と Chooser Action（サンプル自身が `SEND */*` を受けるので、共有先にサンプルを選べる）、設定画面を開く 3 つの操作（開いた画面のパッケージで確かめる）。

## 8. 未決事項

### 8.1 決めること

| ID | 決めること | 選択肢 | 推奨 |
|---|---|---|---|
| D-1 | 進める順番 | Android → iOS → macOS / 3 OS を並行 | **決定（2026-10-03）: Android から 1 OS ずつ**。Android だけが「C のコードが 0 からの新規」で、JNI の寿命とスレッドの規則が他の 2 OS と違う。iOS と macOS は Swift の `@_cdecl` でほぼ同じ形になるので、後でまとめて行える |
| D-2 | 破壊的変更の扱い | A: C ABI を足すのと同じリリースで `unity_android_plugin` を消す / B: 1 リリースは両方を配り、次で消す | **決定（2026-10-03）: A**。Windows の D-4 と同じ理由で、2 つの公開面を並行して保守しない。古い AAR は `dist/1.12.0/android` に残るので、既存の利用者はその版を使い続けられる。段階 2c（`unity-native-plugin` の移行）の成功を段階 3（削除）の条件にする。**2c が終わらなければ 2.0.0 のリリースを待つ**（2026-10-03 に決定。B に切り替える経路は作らない。そのためブリッジは改名せず、段階 3 で消す） |
| D-3 | OS をまたいだ C ABI の形 | A: 規約と OS に依存しないヘッダーを共通にし、機能のヘッダーは OS ごと / B: 全 OS で 1 つのヘッダー | **決定（2026-10-03）: A**（3.3）。機能の中身が OS ごとに違うので、B は最小公倍数か、OS ごとに失敗するだけの関数だらけになる。`Common.h` の分け方と `NTK_VERSION` の意味は C ABI の設計で決める（8.6） |
| D-4 | Context と JavaVM の受け取り方 | A: androidx.startup の Initializer で自動 / B: `ntk_android_init` を呼んでもらう / A と B の両方 | **両方（1a の後に C ABI の設計で決める）**。A の Initializer の中で `System.loadLibrary("ntk")` を呼べば、`JNI_OnLoad` がアプリの ClassLoader で走り、クラスと `RegisterNatives` を用意できる（Flutter の `DynamicLibrary.open` は `dlopen` なので `JNI_OnLoad` を呼ばない）。ただし Startup が**利用者より先に走る保証は無い**（ContentProvider の順序は決まっておらず、利用者は manifest で Startup を無効にできる）ので、すべての入口で初期化の状態を確かめ、まだなら専用のエラーを返す。B は Startup を無効にしたアプリと、既定でないプロセス用。B では `context.getClassLoader()` からクラスを引く。Context は Application の Context にしてグローバル参照で持つ。2 回目の呼び出し、途中の失敗、終わるときの解放の契約を設計で決める。minSdk 31 の端末では `JNI_GetCreatedJavaVMs` で JavaVM を取れる見込み（NDK の `jni.h` に宣言がある）なので、`ntk_android_init(void* context)` にできるかを 1a で確かめる。B で渡す Context が Activity なら、それを前面の Activity として `ForegroundActivityTracker` に渡す（Startup を無効にしたアプリでは、Callbacks を登録した時点で既に前面にある Activity を知る方法が無いため）。`System.loadLibrary` の `UnsatisfiedLinkError`（32 ビットで入ったアプリ）は捕まえ、アプリを落とさず「C ABI は使えない」状態にする。引数を `void*` にするのは、公開ヘッダーに `<jni.h>` を入れないため（ARCore の `ArSession_create(void* env, void* context, ...)` と同じ）。リフレクションで Context を取る方法は非 SDK インターフェースなので使わない。Google の C API（`Pgs_initialize(JavaVM*, jobject)`、ARCore など）はどれも明示的な初期化だけで、自動の初期化を主にする点は違うが、B も用意するので Google と同じ使い方もできる |
| D-5 | C ABI に入れる範囲 | A: 今のブリッジの振る舞い（6 章の集合）+ 通知の権限の要求 / B: `android_library` の全機能 | **決定（2026-10-03）: A**。`unity-native-plugin` が使っている範囲を先に固める。範囲は 45 の操作だけでなく、完了・イベント・登録と解除を含む 6 章の振る舞いの集合（レビュー v1 の A-1 で明記した）。権限の要求を足すのは、Unity 以外の利用者には手段が無いため。B の残り（CallStyle、`getActive` など）は後から関数を足せば互換を保てる |
| D-6 | コールバックと `release` を呼ぶスレッド | A: 常に Android の main スレッド、非同期に（開始した関数の中では呼ばない）/ B: 呼び出し元のスレッド | **A（C ABI の設計で決める）**。Android の API の多くが main に結び付いており、1.3 のばらつきを 1 つにできる。Unity は `[MonoPInvokeCallback]` の static メソッドで受けて Unity のメインスレッドへ渡す（Unity のスクリプトは Activity の種類によらず UnityMain スレッドで動き、Android の main ではない）。Dart は `NativeCallable.listener` で受ける。あわせて次の 2 つを規則にする。(1) **どの関数も main スレッドを待たない**。main で動かす必要がある処理は main に投げて結果をコールバックで返し、main から呼ばれたときはその場で実行する。Flutter は Dart が main で動くので、main に投げて待つとデッドロックする。(2) `release` の規則をコールバックと分けて書く。入口で受け付けなかった失敗は、Windows と同じく呼び出し元のスレッドで関数が戻る前に呼ぶ。受け付けた後は、main に積んだコールバックと解除・close・再入・差し替えが重なってもちょうど 1 回になる状態機械を設計書で決め、競合のテストを書く |
| D-7 | Activity が要る機能（Dialog、通知の権限の要求）の出し方 | A: いつもライブラリの透明な `FragmentActivity` を前面に起動し、その上で出す / B: 前面の Activity が `FragmentActivity` ならその上に出し、違えば A | **決定（2026-10-03）: B**（レビュー v1 の A-4 を受けて A から変更）。`unity-native-plugin` が使う GameActivity は `AppCompatActivity` の派生で `FragmentActivity` なので、今のブリッジはゲームの上にそのまま Dialog を出している。A に統一すると、Dialog のたびにゲームが止まる（`onPause`）ようになる。Flutter の `FlutterActivity` と Unity の `UnityPlayerActivity` は `android.app.Activity` の派生なので、透明な Activity が要る。前面の Activity は `ActivityLifecycleCallbacks` で追い、追う仕組みは `android_library` の Initializer が登録する（Kotlin だけの利用者にも効くように。遅い初期化は D-4）。前面が `FragmentActivity` のときの権限の要求は、後から足す Fragment か `ActivityResultRegistry.register` で行える（どちらを使うかは設計書で決める）。設計書で決めること: アプリが前面にいないときのエラー（Android 10 以降はバックグラウンドから Activity を起動できない）、同時の要求（待たせるか断るか）、透明な Activity のタスクと `excludeFromRecents`・`configChanges`、終わる条件、画面の回転とプロセスの死のときの結果の契約 |
| D-8 | Dialog の同期性 | A: 非同期（完了コールバック）だけ / B: Windows と同じく呼び出し元をブロックする | **A（C ABI の設計で決める）**。Flutter は 3.29 から Android で Dart が main スレッドで動き、無効にする選択肢も削除された（flutter/flutter#174408）ので、main をブロックするとデッドロックする。Windows の Dialog はモーダルで呼び出し元をブロックするので、**Dialog の関数は Windows と同じ名前・同じ形にはならない**（D-3 の A でなければ成り立たない理由の 1 つ） |
| D-9 | C ABI の配布物 | A: 1 つの AAR（Kotlin の受け口 + `jni/<abi>/libntk.so` + Prefab のヘッダー）/ B: AAR と、`.so` とヘッダーを別に配る | **A（C ABI の設計で決める）**。Kotlin の受け口と `.so` は必ず一緒に要る。Prefab に入れれば NDK・React Native・Godot は `find_package` で使える。名前は `android-native-toolkit-capi-<版>.aar`（Windows の `windows-native-toolkit-capi-<版>` に合わせる）。`android-native-toolkit-<版>.aar` への依存は D-17 の Maven リポジトリの POM で伝える |
| D-10 | ネイティブのビルドの設定 | NDK の版、libc++、公開シンボル、ABI | **ABI は決定（2026-10-03）: `arm64-v8a` と `x86_64` だけ**（レビュー v1 の A-2 を受けて `armeabi-v7a` を外した）。Windows の `struct_size` の規則（sizeof を 8 バイトの倍数で増やす、最小の大きさを 2.0.0 の sizeof に固定）とヘッダーの `/* sizeof N */` は 64 ビットが前提で、32 ビットでは構造体の大きさが変わり、照合スクリプトと 1 つのヘッダーから作るバインディングが成り立たない（Windows も E-17 で x64 だけにした）。32 ビットの端末（安価な端末、Android TV、Wear OS）は残っており、そこで 32 ビットの ABI を組んだアプリが入ると `.so` が無い。そのため `NtkInitializer` は `UnsatisfiedLinkError` を捕まえてアプリを落とさず、Kotlin の受け口は「`.so` が無い」状態として扱う。C ABI の関数そのものは存在しないので、利用者の側の扱いは 3.1 のとおり（7 章の 32 ビットのテスト）。**残り（C ABI の設計で決める）**: NDK r30（LTS、30.0.16248370）を `ndkVersion` で固定、`c++_static`、version script で `ntk_*` と `JNI_OnLoad` だけを公開、native メソッドはすべて `JNI_OnLoad` の `RegisterNatives` で登録する（JNI の命名規則の `Java_*` を公開しないため）。`c++_static` と version script は middleware ベンダー向けガイドの推奨で、Unity や Flutter が持つ `libc++_shared.so` と衝突しない。r28 以降は 16 KB のページに既定で合う。C ABI の境界を C++ の例外が越えないことは Windows と同じ |
| D-11 | 1.x で予約・表示した通知 | A: 古いクラス名を残して移行する / B: 2.0.0 への更新の後に一度だけ破棄し、保存形式をクラス名に依存しない JSON にする | **決定（2026-10-03）: B**（レビュー v1 の A-3 を受けて決め直し、v2 を受けて具体にした。前の決定は「互換を捨てて `restoreScheduled` で作り直す」だったが、改名の後は `restoreScheduled` でも作り直せない）。**破棄**: 既存の BootReceiver が受ける `MY_PACKAGE_REPLACED` と、ライブラリを初めて使うときに、印を付けて一度だけ行う。保存した予約（`persistAcrossBoot=true`）は、保存データの平文の `tag::id` から 0e で記録した式で PendingIntent を作り直して Alarm を取り消し（`filterEquals` はコンポーネント名を文字列で比べるので、クラスが無くても一致する）、保存データを消す。保存しなかった予約（`persistAcrossBoot=false`）は列挙できないので取り消せないが、発火しても受け手のクラスが無いので何も表示されない（更新テストで確かめる）。**保存形式**: ライブラリのデータは JSON、利用者が Kotlin の API で渡した `Intent`（タップ先など）は `Intent.toUri` で保存する（2026-10-03 に決定）。Parcel は公式に永続化に使うべきでないとされ、今後の改名や R8 の難読化でも壊れる。`toUri` では、再起動をまたぐ予約の `Intent` の extra は基本型と文字列だけが残る（Kotlin の API の設計書の対応表と、マニュアルに書く。C ABI からは `Intent` を渡さないので影響しない）。A は古いクラス名（`android.*`）を移行のためだけに残し続けることになる（B も取り消しのために古い名前を文字列で持つが、クラスは残さない）。利用者は更新の後に予約し直す（移行ガイドに書く）。1.x で表示中の通知のタップは、旧 Receiver が無くなるので反応しない（同じく書く） |
| D-12 | 版 | `android_library` と C ABI の版 | **決定（2026-10-03）: どちらも 2.0.0**。`unity_android_plugin` を消すのは破壊的変更で、Windows も 2.0.0 にした。`android_library` もパッケージ名が変わる（D-15） |
| D-13 | `ntk_last_system_code()` に入れる値（E-4） | 0 のまま / Android のシステムのエラーを数値にして入れる | **C ABI の設計で決める**。Android の失敗は数値ではなく例外で来ることが多い。例外のクラス名を返す関数を足すか、Windows の HRESULT の定数を `Common.h` から分けるか（3.3）も含めて決める |
| D-14 | `android-toolchain-migration`（`migration/README.md`）との関係 | 統合する / 分ける | **決定（2026-10-03）: 統合する**。版は AGP 9.3.1 + Gradle 9.7.0 + Kotlin 2.4.20（8.3。レビュー v1 の A-12 を受けて、KGP 2.4.20 が確かめている範囲に合わせた）。2.0.0 は破壊的変更なので、版を上げるならここが最も安い。Google Play が 2026-08-31 から targetSdk 36 を求めており、サンプルの targetSdk 35 は上げる必要がある。Windows も D-1 で同じ理由から統合した |
| D-15 | パッケージ名（`namespace` と Kotlin の package） | A: 今のまま（`android.library`）/ B: 2.0.0 で `com.jonghyunkim.nativetoolkit.*` に変える | **決定（2026-10-03）: B**。`android.*` は OS の名前空間で、OS が同じ名前のクラスを足すと、親の ClassLoader が先に引かれてライブラリのクラスが隠れる危険がある。慣習も逆ドメインである（サンプルの `com.jonghyunkim.android.nativetoolkit.example` と、`unity-native-plugin` の `com.jonghyunkim.nativetoolkit.androidlib` は既にその形）。改名で 1.x の予約が壊れる件は D-11 で扱う。段階 0e で機械的な改名だけを 1 PR で行う。ブリッジ（`android.unity.*`）は改名せず、段階 3 で消す（D-2） |
| D-16 | Gradle のルート | A: 今のまま（`AndroidLibraryExample/` がルートで、ライブラリを絶対パスで include）/ B: `android/` をルートにし、サンプルをモジュールの 1 つにする | **決定（2026-10-03）: B**。ライブラリのプロジェクトはライブラリの側をルートにするのが普通で（Oboe など）、今の絶対パス（`/Users/jonghyunkim/...`）はほかの Mac や CI では組めない。Windows の段階 7（CI）と同じものを Android に作るときにも要る。段階 0 で行う |
| D-17 | 配布の方法 | A: `dist/` に AAR のファイルだけを置く / B: A に加え、`maven-publish` で作るファイルの Maven リポジトリ（POM と Gradle Module Metadata 付き）を `dist/<版>/android/m2/` に置く / C: Maven Central などで公開する | **決定（2026-10-03）: B**（レビュー v1 の A-5 を受けて A から変更）。A では依存が利用者に伝わらず、Gradle は利用者が宣言した古い androidx を選んで `NoSuchMethodError` になりうる。`unity-native-plugin` が依存を補っているという前の根拠は誤りで、androidx は Unity の GameActivity のテンプレートにたまたま乗っているだけだった（`UnityPlayerActivity` を選ぶと入らない）。B は登録も署名も要らない。C は別のトピックにする（着手時に作る）。**座標は `io.github.kimjh4941:android-native-toolkit` と `io.github.kimjh4941:android-native-toolkit-capi`**（2026-10-03 に決定。GitHub のアカウントで Maven Central の namespace を確かめられるので、後で C にしても変わらない。artifactId は AAR の名前と同じ）。依存の一覧はビルド（`releaseRuntimeClasspath`）から機械的に作ってマニュアルに載せ、DoD で照合する。`material` を外し、`appcompat` を外せるか確かめて、利用者の依存を減らす（0g） |
| D-18 | minSdk | A: 31 のまま / B: 下げて、古い OS では関数が `NOT_SUPPORTED` を返す形にする | **決定（2026-10-03）: A**（レビュー v2 を受けて、設計の細目から決定に上げた）。下げると AAR の minSdk（配布の契約）、通知などの API の版の分岐、試験の端末、8.3 の表が変わり、2.0.0 の作業が大きく増える。Unity（25）と Flutter（24）の利用者に 31 を求めるのは今と同じ。下げる必要が出たら別のトピックで行う |

### 8.2 段階 1a で確かめること

| 項目 | 確かめ方 | 影響する決定 |
|---|---|---|
| Unity 6 で `DllImport` した `.so` に `JNI_OnLoad` が呼ばれるか | 実機で `JNI_OnLoad` にログを出す | D-4（呼ばれなくても Initializer で足りるが、2 回呼ばれる場合に備えて冪等にする） |
| `JNI_GetCreatedJavaVMs` で JavaVM を取れるか（minSdk 31） | 雛形の `.so` から呼ぶ | D-4（`ntk_android_init` の引数を Context だけにできるか） |
| `RegisterNatives` と version script の組み合わせ、R8 を有効にした利用者で native メソッドが結べるか | 雛形の Kotlin の受け口と smoke | D-10 |
| `c++_static` で作ったモジュールを、`c++_shared` の利用者が Prefab で取り込んだときに、STL の不一致として止められるか | NDK のサンプルのアプリで取り込む | D-10 |
| テスト用の `.so` を別のモジュール（`android_library_capi_test`）に置き、配る AAR に混ざらないか | AAR の中身を確かめる | 7 章 |
| GoogleTest の入れ方 | Prefab で配られているのは 1.11.0-beta-1（2021 年）だけ。古さが問題なら、ソースを取り込んで組む（BSD-3-Clause なので LICENSE を同梱し、置き場所を決める。テストにしか使わず配布物には入らない） | 7 章 |
| 利用者の minSdk | `unity-native-plugin` の設定は `AndroidMinSdkVersion` 25 だが、書き出し済みの `Build/Android` は minSdk 31 になっている。どこで 31 に上がるのか（AAR の manifest の merge か、手で変えたか）を確かめる | 3.1 |

確認済みのもの（2026-10-03）:

- Unity 6000.4.2f1（`unity-native-plugin` の版）の `PlaybackEngines/AndroidPlayer/Source/com/unity3d/player/` で、`UnityPlayerActivity extends android.app.Activity`、`UnityPlayerGameActivity extends com.google.androidgamesdk.GameActivity`。`GameActivity`（games-activity 4.4.0）は `androidx.appcompat.app.AppCompatActivity` の派生なので `FragmentActivity` である（javap で確認）。D-7 の根拠
- Unity 6000.4.2f1 が同梱している NDK は r27c（27.2.12479018）。C ABI の AAR を r30 で作っても、`c++_static` と version script で libc++ を隠すので、Unity の側の NDK の版とは関係しない（上の 4 つ目の項目で確かめる）

### 8.3 ツールチェーンの版（D-14）

2026-10-03 に調べ、レビューのときに公式の出典と AAR の実物でもう一度確かめた。利用者が組めなくなる版は使わない、を基準にする。

**利用者の側の上限**:

| 利用者 | Gradle / AGP | compileSdk | Kotlin |
|---|---|---|---|
| Unity 6000.4.2f1（`unity-native-plugin` の版。手元のインストールで確認） | Gradle 8.13 / AGP 8.10.0 | 36 まで（SDK に入っているのは 34〜36） | Unity は持たない。`unity-native-plugin` の `PostBuildProcessor` が KGP と `kotlin-stdlib` / `kotlin-reflect` を 2.0.21 で足している（2c で直す） |
| Unity 6000.4.4f1 以降・6000.5 | Gradle 9.1.0 / AGP 9.0.0 | 36 まで | 同上 |
| Unity 6000.0.85f1 以降・6000.3.26f1 以降 | Gradle 9.3.1 / AGP 9.1.1 | 36 まで | 同上 |
| Flutter stable 3.47.6 | 既定は AGP 9.1.0。AGP 8.11.1 未満はエラー | 既定 36 | 既定 2.4.0。2.2.20 未満はエラー |

ここから、**利用者に求めてよいのは compileSdk 36、AGP 8.10.0、Kotlin 2.2 まで**とする。

**上げる版**:

| 対象 | 今 | 上げる先 | 段 | 理由・注意 |
|---|---|---|---|---|
| AGP | 8.9.1 | 9.3.1 | 0f | 最新は 9.4.1 だが、KGP 2.4.20 が確かめている AGP は 9.3.1 まで。AGP 9 は新しい DSL と組み込みの Kotlin が既定になる（`org.jetbrains.kotlin.android` プラグインは使わない）。consumer の ProGuard の規則に `-dontoptimize` などがあると公開時にエラーになる |
| Gradle | 8.11.1 | 9.7.0 | 0f | AGP 9.3 の下限 9.5.0 以上で、KGP 2.4.20 が確かめている上限 |
| Kotlin | 2.0.21 | 2.4.20、`languageVersion = apiVersion = 2.2` | 0f | 既定（2.4）のままだと、Kotlin でコンパイルする利用者に 2.3 以上を求める。2.2 に下げれば 2.1 以上で使える。`apiVersion` 2.2 は実行時に `kotlin-stdlib` 2.2 以上を求める。`m2/` の POM で伝わるが、`unity-native-plugin` が固定で足している stdlib 2.0.21 は 2c で外すか 2.2 以上にしてもらう |
| Dokka | 2.0.0 | 2.2.0 | 0f | 2.1.0 から Dokka Gradle Plugin v2 が既定。`publish_docs.sh` の `dokkaHtml` を直す |
| Java / JVM の target | 11 | 17 | 0f | 公式の例は 17。Unity 6 も Flutter も JDK 17 が前提で、D8 が変換するので利用者への影響はほぼ無い |
| compileSdk | 35 | 36 | 0g | **37 にしない**。AGP 9 は既定で利用者に同じ compileSdk 以上を求める（AAR の `minCompileSdk`）。37 は Flutter の既定と Unity 6000.4 の上限を超える。`aarMetadata.minCompileSdk = 36` を明示する |
| core-ktx | 1.15.0 | 1.18.0 | 0g | **1.19 にしない**（利用者に compileSdk 37 と AGP 9.1.0 を求める） |
| appcompat | 1.7.0 と 1.6.1 | 1.8.0 にそろえる（外せるなら外す） | 0g | 使っているのは `AppCompatResources` の 1 か所だけ |
| fragment-ktx | 1.8.6 | 1.9.1（`android_library` で明示の依存にする） | 0g | `AndroidDialogFragment` が使うが、今は `appcompat` 経由で入っている |
| activity-compose | 1.8.0 | 1.13.0 | 0g | compileSdk 36 と AGP 8.9.1 を求める（上限の内） |
| lifecycle-runtime-ktx | 2.6.1 | 2.10.0 | 0g | **2.11 にしない**。2.11 は activity-compose と組むと Compose の lifecycle も 2.11 にそろえさせ、利用者に compileSdk 37 と AGP 9.1.0 を求める |
| Compose BOM（サンプルだけ） | 2024.09.00 | 2026.06.01 | 0g | **2026.08.00 以降にしない**（compileSdk 37 と AGP 9.1 以上が要る） |
| material | 1.12.0 | 外す | 0g | `android_library` のコードで使っていない |
| androidx.media | 1.7.0 | 1.8.0 | 0g | androidx.media は 1.8.0 で非推奨になった。Media3 への移行は Media の style を C ABI に入れるとき（D-5 の残り）に検討する |
| targetSdk（サンプル） | 35 | 36 | 0h | Google Play は 2026-08-31 から、新規アプリと更新に API 36 以上を求めている |
| minSdk | 31 | 31 のまま | - | D-18。Unity（25 以上）と Flutter（24 以上）の利用者は 31 に上げる必要がある（今と同じ） |
| NDK | - | r30（30.0.16248370、LTS） | 1a | `ndkVersion` を明示する（AGP 9.3 の既定は r28.2） |
| CMake | - | 3.31.6、`cmake_minimum_required(VERSION 3.22.1)` | 1a | `externalNativeBuild.cmake.version` を明示する（AGP の既定は 3.22.1。公式の文書は 3.10.2 と書くが古い）。CMake 4 は古い `cmake_minimum_required` を拒む |
| androidx.startup | - | 1.2.0 | 1a | |
| UiAutomator | - | 2.4.0 | 0c | テストだけ。AGP 8.1.1 / compileSdk 34 で入るので、0f より前に足せる |
| espresso / ext.junit | 3.6.1 / 1.2.1 | 3.7.0 / 1.3.0 | 0c | テストだけ。aar-metadata が無いので制約は無い |
| GoogleTest | - | 1a で決める | 1a | 8.2 |

この組み合わせで依存が求める AGP の最大は 8.9.1（activity 1.13.0、core 1.18.0、navigationevent 1.0.0 から。Gradle の `.module` を辿って確かめた）なので、**Unity は 6000.0.61f1 以降、6000.3.1f1 以降、6000.4.1f1 以降が対象**になる（6000.0 のそれより前のパッチは AGP 8.3.0 / 8.7.2 で、組めない）。マニュアルの動作環境に書く。

出典: AGP のリリース（https://developer.android.com/build/releases/gradle-plugin ）、AGP 9.0 の変更（https://developer.android.com/build/releases/agp-9-0-0-release-notes ）、KGP と AGP の対応（https://kotlinlang.org/docs/gradle-configure-project.html ）、ライブラリ作者向けの後方互換（https://kotlinlang.org/docs/api-guidelines-backward-compatibility.html ）、Google Play の対象 API（https://support.google.com/googleplay/android-developer/answer/11926878 ）、Unity の Gradle の対応（https://docs.unity3d.com/6000.4/Documentation/Manual/android-gradle-version-compatibility.html ）、Flutter の既定値（flutter/flutter の stable の `gradle_utils.dart`、`FlutterExtension.kt`、`DependencyVersionChecker.kt`）、androidx の AAR の `aar-metadata.properties`（dl.google.com/android/maven2 から取得して確認）、AGP の既定の CMake（AGP のソースの `CmakeLocator.kt`）。

### 8.4 決めないこと

- Maven Central などへの公開（D-17 の C）。別のトピックにする
- `android_library` にあってブリッジに無い機能の C ABI（D-5 の B）。2.0.0 の後に関数を足す
- Android の CI。Windows の段階 7 と同じく、別に行う
- Flutter・Rust・Godot・React Native での動作の確認。2.0.0 で確かめる利用者は Unity（2c）と smoke の C のアプリだけで、ほかはマニュアルに「確かめていない」と書く。手元の Flutter は 3.7.0（fvm）で、Dart が main で動く 3.29 より古い

### 8.5 出典（調査で使った公式の文書）

- JNI Tips（`JNI_OnLoad`、ClassLoader、`RegisterNatives`、`AttachCurrentThread`、Modified UTF-8）: https://developer.android.com/training/articles/perf-jni
- middleware ベンダー向けガイド（1 つの JNI ライブラリ、`c++_static` と version script、Prefab）: https://developer.android.com/ndk/guides/middleware-vendors
- Prefab の公開: https://developer.android.com/build/native-dependencies
- 16 KB のページ: https://developer.android.com/guide/practices/page-sizes
- NDK のリリース: https://developer.android.com/ndk/downloads 、 https://github.com/android/ndk/wiki
- App Startup: https://developer.android.com/topic/libraries/app-startup
- バックグラウンドからの Activity の起動の制限: https://developer.android.com/guide/components/activities/secure-bal
- 非 SDK インターフェースの制限: https://developer.android.com/guide/app-compatibility/restrictions-non-sdk-interfaces
- ARCore の C API（`void*` で `JNIEnv` と Context を受ける例）: https://developers.google.com/ar/reference/c/group/ar-session
- Play Games Services v2 の C API（`Pgs_initialize(JavaVM*, jobject)`）: https://developer.android.com/games/services/cpp/v2/api/group/play-games
- Unity 6 の GameActivity（プレイヤーループがネイティブのスレッドで動く）: https://docs.unity3d.com/6000.4/Documentation/Manual/android-application-entries-game-activity-requirements.html
- Unity の `DllImport`: https://docs.unity3d.com/6000.3/Documentation/Manual/plug-ins-native-dllimport.html
- Flutter の main スレッドの統合（Android / iOS は 3.29）: https://flutter.dev/blog/whats-new-in-flutter-3-29 。無効にする選択肢の削除: https://github.com/flutter/flutter/pull/174408
- Dart の `NativeCallable`: https://api.dart.dev/dart-ffi/NativeCallable-class.html
- `FlutterActivity` の基底クラス: https://api.flutter.dev/javadoc/io/flutter/embedding/android/FlutterActivity.html

### 8.6 設計で決めること（レビュー v1 で挙がったもの）

決定（D-n）ではないが、設計書で必ず決める項目。決める設計書を右に書く。

| 項目 | 設計書 |
|---|---|
| 機能ごとに使う Context（Application / 前面の Activity / 透明な Activity）。Share と設定画面を Application の Context で開くと `FLAG_ACTIVITY_NEW_TASK` が付き、Chooser のタスクの扱いが変わる | C ABI |
| `ntk_android_init` の契約（D-4）と、すべての入口での初期化の確認 | C ABI |
| JNI の作法: `GetEnv` → `AttachCurrentThread`、自分で attach したスレッドだけ `pthread_key` のデストラクタで detach。Go のように OS のスレッドを渡り歩く呼び出し元の扱い。JNI を呼ぶたびの例外の確認と、Kotlin の例外とエラーの値の対応表 | C ABI |
| 文字列の変換: JNI の `NewStringUTF` / `GetStringUTFChars` は Modified UTF-8 なので使わず、Kotlin 側で UTF-8 の `ByteArray` にして受け渡す | C ABI |
| `release` の状態機械（D-6） | C ABI |
| `Common.h` の分け方、共通の部分の置き場所（1 か所か、写して照合か）、`NTK_VERSION` の意味（3.3） | C ABI |
| イベントを保つ件数・期限・順序・重複の扱い（4 章） | Kotlin の API |
| 透明な Activity の契約（D-7） | Kotlin の API |
| `consumer-rules.pro` の中身: JNI から名前で引くクラスと native メソッド、manifest の Receiver と Activity、Initializer、保存に名前を使うクラス | Kotlin の API・C ABI |
| manifest の merge で利用者に入る権限とコンポーネントの扱い。任意の権限を利用者が選んで入れる形にするか、`tools:node="remove"` の手順を書くか | Kotlin の API |
| ログの規則の例外: 秘密の値（パスワード、入力欄、クリップボードの本文）は伏せる。C / C++ のコードのログの規則も決める。`agent-rules/coding-rules/android.md` を直してから 1b に入る | Kotlin の API |
| `unity-native-plugin` に渡す対応表の範囲: Runtime テストの約 60 件は JSON のテストで意味を失うので、何を基準に作り直すか | C ABI |

## 9. DoD

- [ ] D-1 〜 D-18 を決める（残りは C ABI の設計で決める D-4・D-6・D-8・D-9・D-10 の残り・D-13）
- [x] この README のレビューで区分 A が 0 になっている（3 回。`reviews/` の v1〜v3）
- [ ] 段階 0a のスパイクで、UiAutomator と人の確認の分担を確定する
- [ ] Clipboard / Notification / Share / Dialog のすべてにサンプルの UI テストがある
- [ ] 段階 1a のスパイクで 8.2 を確かめる
- [ ] UI テスト・C ABI・Kotlin の API の設計書を書き、別のモデルのレビューを通す
- [ ] Gradle のルートが `android/` で、絶対パスが残っていない（段階 0）
- [ ] `scripts/test_android.sh` があり、今のコードの結果を API 35 と API 36 で基準として記録している（段階 0d）
- [ ] パッケージ名に `android.*` が残っていない（`android_library` は段階 0e、ブリッジの `android.unity.*` は段階 3 で消える）
- [ ] ツールチェーンが 8.3 の版で、依存の `minAndroidGradlePluginVersion` の最大と `minCompileSdk` の最大が 8.3 の表（8.9.1 と 36）と一致する。自分の AAR の `minCompileSdk` が 36 で、`minAgpVersion` を書いていない（段階 0g。AAR の `aar-metadata.properties` で確かめる）
- [ ] 0e〜0h と 1b の前後で、サンプルの UI テストの結果が変わらない（0h で直したテストは理由を記録している）
- [ ] 1.2 のロジックがすべて `android_library` にあり、移すロジックに当たるブリッジのテストを書き直して通している（段階 1b）
- [ ] 1.x から 2.0.0 への更新のテストで、保存した予約は取り消され、保存しなかった予約は発火しても何も起きず、新しく予約できる（段階 1b）
- [ ] 32 ビットで入れたサンプル（capi の AAR を含めて組んだもの）が起動し、Kotlin の機能が使える（段階 2b）
- [ ] `android_library_capi` が 6 章の振る舞いの集合をすべて公開している（2a の機械照合）
- [ ] 公開シンボルが `ntk_*` と `JNI_OnLoad` だけで、libc++ のシンボルを出していない（`nm -D` で確かめる）
- [ ] 16 KB のページに合っている（`zipalign -c -P 16` か `llvm-objdump` の LOAD の整列で確かめる）
- [ ] smoke がビルドの作った Maven リポジトリだけから組め、R8 を有効にした release で動く。POM の座標（`io.github.kimjh4941`）と依存が D-17 と一致する
- [ ] 依存の一覧がビルドから作られ、マニュアルの一覧と一致する
- [ ] `check_c_abi_contract.py` と `check_manual_c_examples.py` が Android でも通る
- [ ] `unity-native-plugin` が C ABI を呼ぶ形に移り、Android のテストと Player テストを通している（段階 2c。別リポジトリ）
- [ ] `unity_android_plugin` がリポジトリに残っていない（モジュール、スクリプト、README、ルール、`dist/` の新しい版）
- [ ] マニュアルの Android の章に C ABI の節と 2.0.0 の移行ガイドがあり、`android.library.*` が残っておらず、3 言語で一致している

## 10. 関連

- `artifact/topics/windows-architecture/README.md`（手本。特に 5 章の段階の分け方、6 章の壊れる場所、8 章の D-4〜D-10）
- `artifact/topics/windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md`（引き継ぐ規約の出典）
- `artifact/topics/migration/README.md` 7 章（`android-toolchain-migration`。D-14）
- `artifact/topics/bridge-testing/README.md`（ブリッジの層のテストの穴。C ABI のテストを作るときに参照する）
- `agent-rules/coding-rules/android.md`（ログの規則の例外を 1b の前に足す。段階 3 で、モジュールの配置の表を `android_library_capi` に書き換える）
- `reviews/2026-10-03-android-c-abi-plan-review-v1.md`、`reviews/2026-10-03-android-c-abi-plan-review-v2.md`、`reviews/2026-10-03-android-c-abi-plan-review-v3.md`（この README のレビュー）
