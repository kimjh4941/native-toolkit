# Android の汎用 C ABI

- 記録日: 2026-10-03
- 分類: 横断課題（アーキテクチャ）。機能追加ではない
- 進め方: Windows（`windows-architecture`）と同じ汎用 C ABI を、1 OS ずつ作る。このトピックは Android の分で、最初に行う（D-1）。iOS / macOS は Android が終わってから別のトピックにする
- 対象: `android/android_library`、`android/unity_android_plugin`（新しい C ABI のモジュールに置き換える）、`android/AndroidLibraryExample`、`scripts/build_android_library_aar.sh`、配布物 `android-native-toolkit-*.aar` / `unity-android-native-toolkit-*.aar`
- チケット: NTKIT-17（ブランチ `feature/NTKIT-17` の名前から。中身は未確認）
- 手本: `artifact/topics/windows-architecture/`（1.12.0 で出荷した Windows の C ABI）

## 0. 調べたこと

2026-10-03 に、観点の違う 3 つの調査を行った。この README の事実は、断りがない限りこの 3 つから引いている。

| 観点 | 調べたもの |
|---|---|
| Windows の C ABI のうち引き継ぐもの | C ABI の設計書（全 1,591 行）、段階 5・6 の結果、レビュー 2 回分、公開ヘッダー 4 つ、`check_c_abi_contract.py` / `check_manual_c_examples.py` |
| Android の今の公開面 | `unity_android_plugin` と `android_library` の全公開メソッド、JSON の入力、listener、manifest、テスト、`unity-native-plugin`（別リポジトリ）の C# 側 |
| NDK で C ABI を作る前提 | developer.android.com の JNI Tips、middleware ベンダー向けガイド、16 KB ページ、Prefab、NDK のリリース、Unity 6 / Flutter / Godot の公式文書。出典の URL は 8 章の各行に付けた |

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

ネイティブのサンプル（`AndroidLibraryExample`）が Receiver を 3 つ（`NotificationActionReceiver`、`NotificationDeleteReceiver`、`ShareChooserActionReceiver`）自前で持っているのは、ライブラリに足りない証拠である。

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

- Dialog: ブリッジの KDoc は「キャンセル時の入力は `null`」と書いているが、`AndroidDialogFragment.onCancel` は `""` を返す。Fragment の listener は保持されないので、画面の回転で消える。`showLoginDialog` がパスワードを `Log.d` に出している（`UnityAndroidDialogManager.kt` 406 行）
- Notification: `launchAction` を JSON から読むが使っていない。shown のイベントはスケジュール通知でしか出ない
- Notification: 予約したスケジュール通知は、タップ先の Intent（Unity の `NotificationActionReceiver` のクラス名を含む）を Parcel ごと `SharedPreferences` に保存している（`NotificationSchedulerSupport.kt` 51 行）。Receiver を移すと、更新前に予約した通知のタップ先が無くなる（D-11）
- テスト: Dialog のテストはどのモジュールにも無い。Notification の instrumented テストと UI テストも無い。Android 用のテスト実行スクリプト（Windows の `scripts/test_windows.ps1` に当たるもの）も無い
- `consumer-rules.pro` が 2 つとも空。JNI から名前で引くクラスを R8 から守る設定が無い

## 2. なぜ今やるか

- Windows の C ABI が 1.12.0 で出荷され、規約（名前、エラー、UTF-8、ハンドル、`struct_size`、`user_data` と `release`）が確定した。規約が新しいうちに 2 つ目の OS に広げれば、OS をまたいで同じ作法を保てる
- `unity-native-plugin` は Windows の P/Invoke を書き直したばかりで、C ABI を扱う C# の土台（`[MonoPInvokeCallback]`、ハンドルの `SafeHandle` など）がある。Android も同じ形にすれば、C# 側の 2,395 行の `AndroidJavaObject` の組み立てを P/Invoke に置き換えられる
- 1.2 のロジックの移設は、C ABI と関係なくルール違反の解消である。ネイティブのサンプルの重複も消える

## 3. 目標の構成

段階 5 が終わった時点の形。`(新)` は新しく作るもの、`(移)` は 1.2 のロジックを移して作るもの。クラス名は案で、段階 1・2 の設計書で決める。下の図は今のパッケージ名（`android.library` / `android.capi`）と今の Gradle のルートで描いている。D-15・D-16 の決定により、パッケージは `com.jonghyunkim.nativetoolkit.*` に（段階 0e）、Gradle のルートは `android/` に（段階 0）変わる。

```
android/
  android_library/                               # Kotlin の API（AAR: android-native-toolkit-2.0.0.aar）
    build.gradle.kts
    consumer-rules.pro                           # (新) JNI と manifest から名前で引くクラスを R8 から守る
    src/main/AndroidManifest.xml                 # 今の Receiver / Service に、移した Receiver と透明な Activity が加わる
    src/main/java/android/library/
      clipboard/{domain,application,data,presentation}/
        domain/error/ClipboardDomainError.kt     # (移) ブリッジのエラーの分類（7 つ）をここで表す
      notification/{domain,application,data,presentation}/
        data/ResourceNameResolver.kt             # (移) リソース名 → drawable / layout / id
        data/PendingIntentRequestCodes.kt        # (移) request code の体系（衝突と桁あふれを直す）
        presentation/NotificationEventReceiver.kt # (移) 本文のタップ・アクション・dismiss を受ける
        presentation/NotificationEvents.kt       # (移) イベントを受け取る口（今のグローバルな listener の置き換え）
        presentation/settings/                   # (移) Activity の要らない canScheduleExactAlarms と設定画面を開く処理
      share/{domain,application,data,presentation}/
        presentation/ChooserActionReceiverRegistry.kt # (移) Chooser Action の動的 Receiver の一式
      dialog/
        AndroidDialogFragment.kt                 # 今のまま
        presentation/                            # (新) ホストに FragmentActivity が無くても出せる口
      common/presentation/HostActivity.kt        # (新) 透明な FragmentActivity。Dialog と通知の権限の要求をここで出す（D-7）
    src/test/  src/androidTest/

  android_library_capi/                          # (新) 汎用の C ABI（AAR: android-native-toolkit-capi-2.0.0.aar）
    build.gradle.kts                             # ndkVersion（r30）、externalNativeBuild、prefabPublishing、abiFilters（3 つ）
    consumer-rules.pro                           # JNI から名前で引く Kotlin のクラスを R8 から守る
    src/main/AndroidManifest.xml                 # androidx.startup の Initializer の登録
    src/main/cpp/
      CMakeLists.txt                             # c++_static、-fvisibility=hidden、16 KB のページ
      libntk.map                                 # 公開するシンボル: ntk_* と JNI_OnLoad だけ（Windows の .def に当たる）
      include/NativeToolkitC/                    # 公開ヘッダー（Prefab と dist/ に入れる）
        Common.h                                 # Windows と同じ中身（違うのは版の値だけ）
        Android.h                                # ntk_android_init(void* java_vm, void* context) など Android だけの関数
        Clipboard.h  Dialog.h  Notification.h  Share.h
      src/
        Common/                                  # JNI_OnLoad、JNIEnv の取得と attach、jclass / jmethodID のキャッシュ、
                                                 # ハンドル、UTF-8、エラー、struct_size の読み取り、コールバックの登録表と release
        Clipboard/  Dialog/  Notification/  Share/   # C の入口。検査して Kotlin の受け口を JNI で呼ぶだけ
      test/                                      # C ABI の単体テスト（GoogleTest）。debug の androidTest のときだけ組む
    src/main/java/android/capi/                  # Kotlin の受け口。android_library を呼んで型を変換するだけ
      NtkInitializer.kt                          # androidx.startup: Context を保存して System.loadLibrary("ntk")
      clipboard/  dialog/  notification/  share/ # 機能ごとの受け口と、ネイティブへ戻す external fun
    src/androidTest/                             # C ABI のテストを端末で動かす入口（JavaVM と Context が要るため）

  android_library_capi_smoke/                    # (新) 公開ヘッダーと AAR だけを Prefab で使う C のアプリ（Windows の CT-21 に当たる）
    src/main/cpp/smoke.c
    src/androidTest/                             # smoke.c を端末で動かす

  AndroidLibraryExample/                         # Gradle のルート（ここから全モジュールを組む）
    settings.gradle.kts                          # 各モジュールを相対パスで include する（今は絶対パス）
    gradle/libs.versions.toml                    # NDK、androidx.startup、GoogleTest、UiAutomator を足す
    app/                                         # ネイティブのサンプル。Kotlin の API だけを使う
      src/androidTest/                           # (新) 全機能の UI テスト（段階 0）。自前の Receiver 3 つは消える（段階 1）
```

無くなるもの:

| 対象 | 時期 |
|---|---|
| `android/unity_android_plugin/`（`unity-android-native-toolkit-*.aar`） | 段階 4 |
| `android/AndroidLibraryExample/android_library/` と `android/AndroidLibraryExample/unity_android_plugin/`（どこからも使っていない古い雛形。Git の管理下にある） | 段階 0（D-16） |

配布物（`dist/<リリース版>/android/`）:

| ファイル | 中身 | 使う人 |
|---|---|---|
| `android-native-toolkit-2.0.0.aar` | Kotlin の API | Kotlin / Java のアプリ |
| `android-native-toolkit-capi-2.0.0.aar` | Kotlin の受け口、`jni/<abi>/libntk.so`、`prefab/`（ヘッダー） | C の利用者。`android-native-toolkit-2.0.0.aar` も一緒に入れる |
| `include/NativeToolkitC/*.h` | 公開ヘッダー（AAR の中と同じもの） | ヘッダーからバインディングを作る人（ClangSharp、bindgen、ffigen） |

`ntk_android_init` を `Common.h` ではなく `Android.h` に置くのは、`Common.h` を Windows と同じ中身に保ち、照合スクリプトで差分が版の値だけであることを確かめられるようにするためである（3.3）。

依存の向きは `android_library_capi` → `android_library`。Windows と同じく、**機能の実装は `android_library` にだけ置き**、`android_library_capi` は型の変換（UTF-8 のバイト列と `String`、ハンドルと Kotlin のオブジェクト、関数ポインタと Kotlin のラムダ）だけを受け持つ。

| 利用者 | 使うもの |
|---|---|
| Kotlin / Java のアプリ | `android_library`（今のまま） |
| C の利用者（Unity、Flutter、Rust、Godot、React Native の C++、NDK のアプリ） | `android_library_capi` |

### 3.1 利用者の前提

`android_library_capi` は汎用の C ABI で、C の関数を呼べる言語（C#、Dart、Rust、C / C++、Go、Python の cffi など）から使える。ただし Windows の DLL と違い、次の前提がある。C ABI の設計書では、Windows のスレッドの前提と同じく冒頭に置く。

| 前提 | 理由 | 成り立たない使い方 |
|---|---|---|
| Android アプリのプロセスの中で呼ぶ | 中身は JNI で Kotlin を呼ぶので、ART（JavaVM）と Context が要る | `adb shell` で動かす単体の実行ファイル。NativeActivity だけのアプリは JavaVM を持つので使える |
| AAR ごとアプリの Gradle のビルドに入れる | Kotlin の受け口、manifest の Receiver、androidx.startup の Initializer が AAR に入っている | `.so` だけをコピーして `dlopen` する使い方。Unity / Flutter / Godot / React Native はどれも最後に Gradle でビルドするので問題ない |
| 自分が作っていないスレッドからのコールバックを受けられる | コールバックは Android の main スレッドから呼ぶ（D-6） | 呼び出し元のスレッドでしか関数ポインタを受けられない言語の仕組み（Dart の `NativeCallable.isolateLocal` など）。Unity は `[MonoPInvokeCallback]`、Dart は `NativeCallable.listener` で受ける |
| アプリの minSdk が 31 以上、ABI が `arm64-v8a` / `armeabi-v7a` / `x86_64` のどれか | AAR の minSdk と、出荷する `.so`（D-10） | - |

Kotlin / Java のアプリは C ABI を使わず、`android_library` を直接呼ぶ。C ABI を通すと JNI を往復するだけになる。

### 3.2 Windows と同じにするもの、Android で決め直すもの

Windows の C ABI の設計書の決定 E-1〜E-21 と、前提の D-4〜D-10 を次のとおり扱う。

| 扱い | 対象 |
|---|---|
| そのまま引き継ぐ | 名前の規則（`ntk_<機能>_<動詞>`）、エラーは戻り値（機能ごとの `int32_t` の列挙、0 が成功、欠番は詰めない）、UTF-8 だけ（E-7）、真偽値は `int32_t`（E-8）、0 で埋めた構造体が既定値（E-9）、出力はすべてハンドル（E-5）、`struct_size` の読み方（先頭 8 バイト、8 バイト単位で増やす、上限 4096）、すべてのコールバックの `void* user_data` と、ちょうど 1 回呼ぶ `release`（E-12 の形）、`_free(NULL)` は何もしない、`NULL` の入力の扱い（E-15）、U+FFFD への置き換え（E-16）、件数は `size_t`（E-17 のうち型だけ）、非同期の完了はシステムコードを引数で渡す（E-18）、`ntk_version()` とリテラルの版のマクロ、公開ヘッダーは `<stdint.h>` と `<stddef.h>` だけ・ASCII だけ・C99 と C++ の両方でコンパイルできる |
| Android で決め直す | 寿命の対応先（C++ のオブジェクト → JNI のグローバル参照、E-1）、`ntk_last_system_code()` に入れる値（E-4）、公開の方法（`.def` → リンカーの version script、D-5）、対応する ABI（x64 だけ → 3 つの ABI、E-17）、スレッドの規則（STA とメッセージループ → Android の main スレッド）、`HWND` の代わりに渡すもの（Context / Activity） |
| Windows 専用で関係しない | E-6、E-10 の中身、E-11、E-13、E-19、E-20 の中身、E-21 |

### 3.3 OS をまたいだヘッダーの扱い

`Common.h` は Windows と同じ中身にする（違うのは版の値だけ）。Android だけの関数（`ntk_android_init` など）は `Android.h` に置く。機能のヘッダーは OS ごとに持つ。機能の中身が OS ごとに違うためである（Windows の Clipboard には履歴と遅延レンダリングがあり、Android には URI と sensitive がある。通知の作り方はまったく違う）。**同じ意味の操作には同じ名前を付ける**（たとえば `ntk_clipboard_read` 系）が、OS をまたいで同じヘッダーで書ける 1 つの API にはしない。それは `unity-native-plugin` の C# の層が受け持つ（D-3）。

Share のヘッダーは Windows に無い。Android で初めて作るので、名前は OS に依存しない形にしておく（後で Windows / iOS / macOS に足せるように）。

## 4. Kotlin の API の方針

C ABI の前に、1.2 のロジックを `android_library` へ移し、ネイティブの利用者が Kotlin だけで全機能を使えるようにする。Windows の段階 3（C++ API）に当たるが、Windows のように API を全部書き直すのではなく、**足りない部分を足す**作業になる。

| 足すもの | 置き場所（案） |
|---|---|
| 通知のタップ・アクション・dismiss を受ける Receiver と、イベントを受け取る口（今はグローバルの listener 1 つ） | `notification/presentation/` |
| リソース名からの解決 | `notification/data/` |
| PendingIntent の request code の体系（今は `id + Int.MAX_VALUE/4` などで、衝突と桁あふれの余地がある） | `notification/data/` |
| Activity の要らない `canScheduleExactAlarms` と、設定画面を開く処理 | `notification/presentation/` |
| Activity を持たない呼び出し元からの通知の権限の要求（D-7） | `notification/presentation/permission/` |
| Chooser Action の動的 Receiver の一式 | `share/presentation/` |
| Clipboard のエラーの分類（今のブリッジの 7 つのコード） | `clipboard/domain/error/`（`ClipboardDomainError` との対応を決める） |
| Activity を持たない呼び出し元からの Dialog の表示（D-7） | `dialog/` |

`shareText` が Chooser Action を JSON 文字列で受け取っている（`ShareTextUseCase.kt` 22 行）のは、Kotlin の API としては型にする。

足すだけで既存の Kotlin の API は壊さない方針だが、request code の体系を変えると、更新前に出した通知の PendingIntent と一致しなくなる。これは D-11 で扱う。

## 5. 段階

1 段階 = 1 PR を基本にする。Windows と同じく、段階 0 でテストをそろえてから着手する。

| 段階 | 内容 | 動作の変更 |
|---|---|---|
| 0 | Gradle のルートを `android/` に移す（D-16）。サンプルを `android/AndroidLibraryExample/app` のままモジュールの 1 つにし、全モジュールを相対パスで include する。どこからも使っていない古い雛形（`AndroidLibraryExample/android_library/` と `AndroidLibraryExample/unity_android_plugin/`）もここで消す。`scripts/build_android_library_aar.sh` と `agent-rules/workflows/` の Gradle の呼び出しを直す | 無し |
| 0a | スパイク: サンプルの UI テストで扱える項目を確定する（7.2）。UiAutomator で、通知のシェードのタイトル・本文・アクションのボタン・入力欄・dismiss、POST_NOTIFICATIONS のダイアログ、Chooser と Chooser Action、Direct Share、スケジュール通知、前景サービスの通知を扱えるか。アプリ内の Dialog は Espresso / Compose のテストで扱えるか | 無し |
| 0b | サンプルの画面に testTag を付ける（今は全画面で 0 個。Windows の AutomationId に当たる。見た目も動作も変えない） | 無し |
| 0c | Dialog / Notification / Share の UI テストを足す（Clipboard は 14 件ある）。UiAutomator で扱えない項目は、人の確認の手順書にする | 無し |
| 0d | `scripts/test_android.sh` を作り（unit・instrumented・UI テストをまとめて実行）、**今のコードで全件通ることを確かめ、結果を基準として記録する** | 無し |
| 0e | パッケージ名を `com.jonghyunkim.nativetoolkit.*` に変える（D-15）。機械的な改名だけを行い、段階 0d の基準と同じ結果になることを確かめる | Kotlin の利用者から見たパッケージ名が変わる（2.0.0） |
| 0f | ツールチェーンの版を上げる（D-14、8.3）。AGP 9 の新しい DSL と組み込みの Kotlin への移行を含む。段階 0d の基準と同じ結果になることを確かめる。targetSdk 36 で意図して変わる振る舞いがあれば、UI テストを直した理由とともに結果に記録する | サンプルの targetSdk が 36 になる。利用者の最低条件が 8.3 のとおり上がる |
| 1 | 1.2 のロジックを `android_library` へ移す（4 章）。ネイティブのサンプルの重複した Receiver を消す。**ブリッジには手を入れない**（段階 4 で消すので、委譲の形に作り替えても出荷されない） | 無し（ネイティブの利用者から見た動作は変えない） |
| 2a | スパイク: NDK のビルド（AGP の `externalNativeBuild` + Prefab の公開、`c++_static` + version script、16 KB のページ）、androidx.startup からの `System.loadLibrary`、Unity 6 の `DllImport` から呼べるか、`JNI_OnLoad` が 2 回呼ばれても壊れないか、Unity の `minSdk 25` と AAR の `minSdk 31` の関係（8.2） | 無し |
| 2b | `android_library_capi` を作り、C ABI を実装する。C ABI のテスト（テスト専用の JNI の入口 + GoogleTest を instrumented テストで動かす）と、公開ヘッダーだけで組む C の smoke テスト | C ABI が増える（新しい配布物） |
| 3 | `check_c_abi_contract.py` と `check_manual_c_examples.py` を OS ごとに動くようにする（パス、機能名、操作の数、公開シンボルの読み方、コンパイラを OS ごとの設定にする） | 無し |
| 4 | `unity_android_plugin` を削除する。ビルドスクリプト、`dist/`、Dokka、README、`agent-rules/coding-rules/android.md` から外す | `unity-android-native-toolkit-*.aar` が無くなる（D-2） |
| 5 | マニュアル（Android の C ABI の節、3 言語）、Doxygen、`docs/` を合わせる | - |

**段階 1 を段階 2 より前に行う理由**: 逆にすると、C ABI の受け口がブリッジの中のロジックに依存するか、ブリッジのロジックを C ABI 用にもう 1 つ書くことになる。

**段階 4 は段階 2 と同じリリースで出す**（D-2）。Unity は、このリリースから `android_library_capi` の C ABI を P/Invoke で呼ぶ。`unity-native-plugin` 側の書き換え（`AndroidJavaObject` → P/Invoke）は、Windows と同じく向こうの作業とし、こちらは対応表を出す。

### 5.1 設計書

この README は企画書の役割を持つ。設計書は公開 API を決める段階とテストの段階だけに書く。

| 段階 | 設計書 | 理由 |
|---|---|---|
| 0a / 2a スパイク | 書かない（結果を `results/` に記録する） | 調べる項目はこの README の表で足りる |
| 0 UI テスト | 書く | 機能ごとのテストケースの一覧と、確かめる内容。UiAutomator で扱う項目と人が確かめる項目の分担（0a の結果に基づく）。出発点は既存のサンプルアプリの設計書にある手動確認の観点 |
| 1 Kotlin の API の補完 | 書く | ネイティブの利用者に公開する Kotlin の API が増える。**今のブリッジの約束が新しい API のどこで守られるかの対応表**を含める |
| 2 C ABI | 書く | 公開 API。Windows の設計書と同じ構成（名前の規則、3 つの受け渡し方式、スレッドの前提、エラー、メモリ、`struct_size`、全関数の一覧、付録 A のヘッダー）にし、**今のブリッジの 69 メソッドと新しい関数の対応表**を含める |
| 3〜5 | 書かない | この README の表で足りる |

C ABI の設計書は、Windows の設計書を手本に、3.2 の「Android で決め直す」項目だけを新しく書く。公開 API の 2 本（Kotlin の API の追加分と C ABI）は、これまでと同じく別のモデルにレビューしてもらってから着手する。

置き場所:

```
artifact/topics/android-c-abi/
  README.md                                          # この文書
  designs/
    YYYY-MM-DD-android-c-abi-ui-test-design.md       # 段階 0
    YYYY-MM-DD-android-c-abi-kotlin-api-design.md    # 段階 1
    YYYY-MM-DD-android-c-abi-design.md               # 段階 2
  reviews/
  results/
```

ファイル名に OS 名を入れるのは、`artifact/README.md` の決まり（ファイル名だけで引用されても OS が分かる）に合わせるためである。

## 6. 公開面の規模

今のブリッジの公開面（調査の結果）:

| 機能 | 公開メソッド | うち操作・問い合わせ | 入力 JSON | listener |
|---|---|---|---|---|
| Clipboard | 15 | 10 | 4 種 | 2 |
| Dialog | 13 | 6 | 無し（位置引数） | 6 |
| Notification | 27 | 20 | 3 種（style 6 種、action、view action、リソース参照などが入れ子） | 3 |
| Share | 14 | 9 | 6 種 | 2（メソッドは 3） |
| 計 | 69 | 45 | | |

Windows では 47 の操作が 105 の C 関数になった（ハンドルの読み取り関数とビルダーで増える）。Android も操作 45 に対して 100 前後になる見込みで、Notification のビルダー（通知の項目 30 と style の入れ子）がその半分ほどを占める。

`android_library` にあるがブリッジが公開していないもの（CallStyle、`getActive`、`createChannels`、`restoreScheduled`、Media の style）を C ABI に入れるかは D-5 で決める。

## 7. 検証方法

| 層 | 手段 | 守るもの |
|---|---|---|
| Kotlin の単体テスト | `android_library` の unit テスト（今 83 件） | ライブラリの内部 |
| instrumented テスト | `android_library` と `android_library_capi` の androidTest | Android の API を通した動作。C ABI は JavaVM と Context が要るので、端末かエミュレータの上でしか試せない |
| C ABI のテスト | テスト専用の JNI の入口から GoogleTest を動かす（instrumented テストの 1 件として） | NULL と不正な入力の拒否、`struct_size`、`release` の回数、スレッド、UTF-8 |
| smoke | `android_library_capi_smoke`: 公開ヘッダーと AAR だけを Prefab で使う C のアプリ | 配布物だけで使えること |
| サンプルの UI テスト | `AndroidLibraryExample` の androidTest（今 23 件で、Clipboard 14 件と、受け取った共有の解析だけ。段階 0c で全機能に広げる） | 段階 1 の前後で、ネイティブの利用者から見た動作が変わらないこと |
| Unity | `unity-native-plugin` の Android のテスト（今の Runtime 97 件と PlayMode 12 件を、C ABI を呼ぶ形に書き換えたもの）と Player テスト | Unity から C ABI を通した動作。別リポジトリで行う |

段階 1 は「動作を変えない」移設なので、Windows の段階 3 と同じく、**移す前後で同じサンプルの UI テストが通ること**を根拠にする。

今のブリッジのテスト（unit 77 件、instrumented 10 件）は基準にしない。ブリッジは段階 4 で消え、Unity は C ABI を呼ぶ形に書き換わるので、ブリッジの動作を前後で比べる場面が無い。ただし、移すロジックを確かめているテスト（Chooser Action の Receiver の instrumented テスト 9 件など）は、段階 1 で `android_library` のテストに書き直すときの仕様として使う。

### 7.1 サンプルの UI テストで守れる範囲

Windows では、移行前のサンプルが C ABI を呼んでいたので、サンプルの UI テストがそのまま C ABI の動作の基準になった。**Android のサンプルはブリッジを通らず、`android_library` を直接呼んでいる**（`AndroidLibraryExample` は `unity_android_plugin` に依存しない決まり）。そのため、サンプルの UI テストで守れるのは、ネイティブの利用者から見た動作だけである。

| 守るもの | 基準 | 段階 1 で変わる所 |
|---|---|---|
| ネイティブの利用者から見た動作 | サンプルの UI テスト（段階 0c） | サンプルが自前で持つ Receiver 3 つを、`android_library` に移した Receiver に置き換える。**通知のタップ・アクション・dismiss と Chooser Action がこれまでどおり届くこと**を UI テストで確かめる。ここが段階 1 でいちばん壊れやすい |
| Unity から見た動作 | 前後の比較はしない。Unity は `android_library_capi` を呼ぶ形に書き換わり、ブリッジは段階 1 で手を入れずに段階 4 で消す | 無し。変わる振る舞いは、C ABI の設計書の対応表（今のブリッジの 69 メソッド → 新しい関数）に書く |
| C ABI | C ABI のテストと smoke（段階 2b）、`unity-native-plugin` の C ABI 版のテスト | 新規なので前後の比較は無い |

サンプルは段階 2 以降も Kotlin の API だけを使い、C ABI は使わない（Windows でもサンプルは C++ API だけを使う）。

### 7.2 UiAutomator と人の確認の使い分け

基本は自動化する。アプリ内の画面と Dialog は Compose / Espresso のテストで、通知のシェード・権限のダイアログ・Chooser などのシステムの UI は UiAutomator で扱う。**扱えないと段階 0a で確かめた項目だけ**を人の確認にし、手順書を用意する（Windows の computer use の決まり（`windows-architecture/README.md` 7.3）に合わせ、判定があいまいなら失敗とする）。

システムの UI は OS の版で見た目と構造が変わるので、UI テストはエミュレータの版を固定して流す（候補は手元にある `Pixel_8_Android_15`）。

目標はサンプルの全機能を自動化することだが、次の項目は自動化が難しい見込みである（2026-10-03 時点の見込み。段階 0a で確定する）。

| 項目 | 難しい理由 | 扱いの案 |
|---|---|---|
| 画像の中身（BigPicture、大きいアイコン、カスタムビューの画像） | 画像の要素があることは分かるが、どの画像かは分からない（Windows と同じ） | 人の確認（Claude のデスクトップアプリの computer use でエミュレータの画面を見る） |
| 音・振動 | UI からは確かめられない | 対象外。チャンネルの設定値は API で確かめる |
| 再起動の後の予約の復元 | テストのプロセスが再起動をまたげない | `BOOT_COMPLETED` をシェルから送って代わりにするか、人の確認 |
| Direct Share の共有先が Chooser に並ぶこと | 並ぶかどうかと順番を OS が決める | 登録は `ShortcutManager` の API で確かめ、Chooser に並ぶことは人の確認 |
| Media の style | Android 13 以降はシェードではなくメディアのプレーヤーの枠に出る | 段階 0a で確かめる |

自動化できる見込みのもの: アプリ内の画面と Dialog（Compose / Espresso）、通知のシェードのタイトル・本文・展開・アクションのボタン・入力欄（RemoteInput）・dismiss・進捗・グループ・CallStyle・スケジュール通知、通知の権限のダイアログ（権限の取り消しはシェルのコマンドで行う）、Chooser と Chooser Action（サンプル自身が `SEND */*` を受けるので、共有先にサンプルを選べる）、設定画面を開く 3 つの操作（開いた画面のパッケージで確かめる）。

## 8. 未決事項

### 8.1 決めること

| ID | 決めること | 選択肢 | 推奨 |
|---|---|---|---|
| D-1 | 進める順番 | Android → iOS → macOS / 3 OS を並行 | **決定（2026-10-03）: Android から 1 OS ずつ**。Android だけが「C のコードが 0 からの新規」で、JNI の寿命とスレッドの規則が他の 2 OS と違う。iOS と macOS は Swift の `@_cdecl` でほぼ同じ形になるので、後でまとめて行える |
| D-2 | 破壊的変更の扱い | A: C ABI を足すのと同じリリースで `unity_android_plugin` を消す / B: 1 リリースは両方を配り、次で消す | **決定（2026-10-03）: A**。Windows の D-4 と同じ理由で、2 つの公開面を並行して保守しない。古い AAR は `dist/1.12.0/android` に残るので、既存の利用者はその版を使い続けられる。`unity-native-plugin` の書き換えが同じリリースに間に合うことが前提で、間に合わなければ B に切り替える |
| D-3 | OS をまたいだ C ABI の形 | A: 規約と `Common.h` を共通にし、機能のヘッダーは OS ごと / B: 全 OS で 1 つのヘッダー | **決定（2026-10-03）: A**（3.3）。機能の中身が OS ごとに違うので、B は最小公倍数か、OS ごとに失敗するだけの関数だらけになる |
| D-4 | Context の受け取り方 | A: androidx.startup の Initializer で自動 / B: `ntk_android_init(void* java_vm, void* context)` を呼んでもらう / A と B の両方 | **両方**。A を主にし、Initializer の中で `System.loadLibrary("ntk")` を呼べば、`JNI_OnLoad` がアプリの ClassLoader で、どの利用者より先に必ず走る（Flutter の `DynamicLibrary.open` は `dlopen` なので `JNI_OnLoad` を呼ばない）。B は startup を無効にしたアプリ用。引数を `void*` にするのは、公開ヘッダーに `<jni.h>` を入れないため（ARCore の `ArSession_create(void* env, void* context, ...)` と同じ）。リフレクションで Context を取る方法は非 SDK インターフェースなので使わない。なお Google の C API（Play Games Services v2 の `Pgs_initialize(JavaVM*, jobject)`、ARCore など）はどれも明示的な初期化だけで、自動の初期化を主にする点は違う。Unity の C# からは JavaVM* を取り出しにくいので自動を主にするが、B も用意するので Google と同じ使い方もできる |
| D-5 | C ABI に入れる範囲 | A: 今のブリッジの 45 操作 + 通知の権限の要求 / B: `android_library` の全機能 | **決定（2026-10-03）: A**。`unity-native-plugin` が使っている範囲を先に固める。権限の要求を足すのは、今は C# が Unity の `Permission.RequestUserPermission` で済ませていて、Unity 以外の利用者には手段が無いため。B の残り（CallStyle、`getActive` など）は後から関数を足せば互換を保てる |
| D-6 | コールバックを返すスレッド | A: 常に Android の main スレッド、非同期に（開始した関数の中では呼ばない）/ B: 呼び出し元のスレッド | **A**。Android の API の多くが main に結び付いており、1.3 のばらつきを 1 つにできる。Unity は `[MonoPInvokeCallback]` の static メソッドで受けて Unity のメインスレッドへ渡す（Unity 6 の GameActivity では Unity のメインスレッドは Android の main ではない）。Dart は `NativeCallable.listener` で受ける。ただし入口で受け付けなかった失敗は、Windows と同じく呼び出し元のスレッドで、関数が戻る前に `release` を呼ぶ |
| D-7 | Activity が要る機能（Dialog、通知の権限の要求）の出し方 | A: ライブラリの透明な `FragmentActivity` を前面に起動し、その上で出す / B: ホストが `FragmentActivity` ならその上に出し、違えば A | **決定（2026-10-03）: A に統一**。ホストが `FragmentActivity` である保証が無い（Flutter の `FlutterActivity` は `Activity` の派生。Unity の `UnityPlayerActivity` も `android.app.Activity` の派生であることを 8.2 で確かめた）。`registerForActivityResult` はホストの生成前に登録する必要があり、後から入るライブラリでは使えない。経路を 1 本にすればテストも 1 本で済み、画面の回転でも listener が消えない（1.4）。代わりにホストの `onPause` が走る（Unity ではゲームが止まる）ことを仕様として書く |
| D-8 | Dialog の同期性 | A: 非同期（完了コールバック）だけ / B: Windows と同じく呼び出し元をブロックする | **A**。Flutter は 3.29 から Android で Dart が main スレッドで動くので、main をブロックするとデッドロックする。Windows の Dialog はモーダルで呼び出し元をブロックするので、**Dialog の関数は Windows と同じ名前・同じ形にはならない**（D-3 の A でなければ成り立たない理由の 1 つ） |
| D-9 | 配布物 | A: 1 つの AAR（Kotlin の受け口 + `jni/<abi>/libntk.so` + Prefab のヘッダー）/ B: AAR と、`.so` とヘッダーを別に配る | **A**。Kotlin の受け口と `.so` は必ず一緒に要る。Prefab に入れれば NDK・React Native・Godot は `find_package` で使える。名前は `android-native-toolkit-capi-<版>.aar`（Windows の `windows-native-toolkit-capi-<版>` に合わせる） |
| D-10 | ネイティブのビルドの設定 | NDK の版、libc++、公開シンボル、ABI | **NDK r30（LTS、30.0.16248370）を `ndkVersion` で固定、`c++_static`、version script で `ntk_*` と `JNI_OnLoad` だけを公開、ABI は `arm64-v8a` / `armeabi-v7a` / `x86_64`**。`c++_static` と version script は middleware ベンダー向けガイドの推奨で、Unity や Flutter が持つ `libc++_shared.so` と衝突しない。r28 以降は 16 KB のページに既定で合う（Play の期限は公式の記載で 2027-02-01）。C ABI の境界を C++ の例外が越えないことは Windows と同じ |
| D-11 | 移す前に予約・表示した通知 | A: 古いクラス名の Receiver を `android_library` に残して新しい Receiver へ渡す / B: 互換を捨て、マニュアルに書く | **決定（2026-10-03）: B**。古いクラス名は `android.unity.*` で、残すと削除するモジュールの名前がライブラリに残り続ける。影響は「更新前に予約した通知と、表示中の通知をタップしても反応しない」に限られ、`restoreScheduled` で予約を作り直せば消える。段階 1 の設計書で、更新時に作り直す手順を書く |
| D-12 | 版 | `android_library` と C ABI の版 | **決定（2026-10-03）: どちらも 2.0.0**。`unity_android_plugin` を消すのは破壊的変更で、Windows も 2.0.0 にした。`android_library` 自体は足すだけだが、Receiver の移設で manifest が変わる（利用者の manifest の merge に影響する）ので、同じ版に合わせる |
| D-13 | `ntk_last_system_code()` に入れる値（E-4） | 0 のまま / Android のシステムのエラーを数値にして入れる | **C ABI の設計書で決める**。Android の失敗は数値ではなく例外で来ることが多い。例外のクラス名を返す関数を足すかも含めて、設計書で決める |
| D-14 | `android-toolchain-migration`（`migration/README.md`）との関係 | 統合する / 分ける | **決定（2026-10-03）: 統合する**（「分ける」の推奨から変更）。版は AGP 9.3.3 + Kotlin 2.4.20（8.3）。2.0.0 は破壊的変更なので、版を上げるならここが最も安い。Google Play が 2026-08-31 から targetSdk 36 を求めており、サンプルの targetSdk 35 は上げる必要がある。Windows も D-1 で同じ理由から統合した。上げる版は 8.3 |
| D-15 | パッケージ名（`namespace` と Kotlin の package） | A: 今のまま（`android.library` / `android.capi`）/ B: 2.0.0 で `com.jonghyunkim.nativetoolkit.*` に変える | **決定（2026-10-03）: B**。`android.*` は OS の名前空間で、OS が同じ名前のクラスを足すと、親の ClassLoader が先に引かれてライブラリのクラスが隠れる危険がある。慣習も逆ドメインである（サンプルの `com.jonghyunkim.android.nativetoolkit.example` と、`unity-native-plugin` の `com.jonghyunkim.nativetoolkit.androidlib` は既にその形）。Kotlin の利用者には破壊的変更だが、2.0.0 は D-2 で破壊的変更と決まっており、予約済みの通知のクラス名が変わる影響は D-11 で受け入れている。変えるなら段階 1 の前（段階 0 の後）に機械的な改名だけを 1 PR で行う |
| D-16 | Gradle のルート | A: 今のまま（`AndroidLibraryExample/` がルートで、ライブラリを絶対パスで include）/ B: `android/` をルートにし、サンプルをモジュールの 1 つにする | **決定（2026-10-03）: B**。ライブラリのプロジェクトはライブラリの側をルートにするのが普通で（Oboe など）、今の絶対パス（`/Users/jonghyunkim/...`）はほかの Mac や CI では組めない。段階 7 に当たる CI を作るときにも要る。段階 0 の前に行う |
| D-17 | 配布の方法 | A: 今のまま `dist/` に AAR のファイルを置く / B: Maven（POM 付き）で配る | **決定（2026-10-03）: 2.0.0 は A**、B は別のトピックにする（着手時に作る）。AAR のファイルだけでは依存するライブラリ（androidx の core / appcompat / fragment / startup など）が利用者に伝わらず、手で足す必要がある（`unity-native-plugin` は `PostBuildProcessor` で補っている）。同じ種類のライブラリは Maven で配るのが普通で、Windows の NuGet に当たる。ただし公開先（Maven Central など）の登録と署名が要り、C ABI とは独立に進められるので、2.0.0 ではマニュアルに依存の一覧を書くに留める |

### 8.2 段階 2a で確かめること

調査では、次の 3 つを公式の文書から確かめられなかった。

| 項目 | 確かめ方 | 影響する決定 |
|---|---|---|
| Unity 6 で `DllImport` した `.so` に `JNI_OnLoad` が呼ばれるか | 実機で `JNI_OnLoad` にログを出す | D-4（呼ばれなくても A の Initializer で足りるが、2 回呼ばれる場合に備えて冪等にする） |
| `UnityPlayerActivity` の基底クラス | **確認済み（2026-10-03）**: Unity 6000.4.2f1（`unity-native-plugin` の版）の `PlaybackEngines/AndroidPlayer/Source/com/unity3d/player/` で、`UnityPlayerActivity extends android.app.Activity`（`FragmentActivity` ではない）、`UnityPlayerGameActivity extends com.google.androidgamesdk.GameActivity`。`unity-native-plugin` は GameActivity（`androidApplicationEntry: 2`）を使っているが、利用者は `UnityPlayerActivity` も選べるので、D-7 の透明な Activity が要る | D-7 |
| `c++_static` で作ったモジュールを、`c++_shared` の利用者が Prefab で取り込んだときに、STL の不一致として止められるか | NDK のサンプルのアプリで取り込む | D-10 |

Unity 6000.4.2f1 が同梱している NDK は r27c（27.2.12479018）である。C ABI の AAR を r30 で作っても、`c++_static` と version script で libc++ を隠すので、Unity の側の NDK の版とは関係しない（これも 3 つ目の項目で確かめる）。

あわせて、`unity-native-plugin` の `AndroidMinSdkVersion` が 25 で、AAR の `minSdk` は 31 である点も確かめる。C ABI の AAR も `minSdk 31` で、利用者のアプリはこれより下げられない。

### 8.3 ツールチェーンの版（D-14）

2026-10-03 に調べた。利用者が組めなくなる版は使わない、を基準にする。

**利用者の側の上限**:

| 利用者 | Gradle / AGP | compileSdk | Kotlin |
|---|---|---|---|
| Unity 6000.4.2f1（`unity-native-plugin` の版。手元のインストールで確認） | Gradle 8.13 / AGP 8.10.0 | 36 まで（SDK に入っているのは 34〜36） | Unity は持たない。`unity-native-plugin` の `PostBuildProcessor` が KGP と `kotlin-stdlib` を 2.0.21 で足している |
| Unity 6000.4.4f1 以降・6000.5 | Gradle 9.1.0 / AGP 9.0.0 | 36 まで | 同上 |
| Flutter stable 3.47.6 | 既定は AGP 9.1.0。AGP 8.11.1 未満はエラー | 既定 36 | 既定 2.4.0。2.2.20 未満はエラー |

ここから、**利用者に求めてよいのは compileSdk 36、AGP 8.10.0、Kotlin 2.2 まで**とする。

**上げる版**:

| 対象 | 今 | 上げる先 | 理由・注意 |
|---|---|---|---|
| AGP | 8.9.1 | 9.3.3 | 最新は 9.4.1 だが、KGP 2.4.20 が確かめている AGP は 9.3.1 まで。AGP 9 は新しい DSL と組み込みの Kotlin が既定になる（`org.jetbrains.kotlin.android` プラグインは使わない）。consumer の ProGuard の規則に `-dontoptimize` などがあると公開時にエラーになる |
| Gradle | 8.11.1 | 9.7.1 | AGP 9.3 の下限 9.5.0 以上で、KGP 2.4.20 が確かめている 9.7.0 に近いもの |
| Kotlin | 2.0.21 | 2.4.20、`languageVersion = apiVersion = 2.2` | 既定（2.4）のままだと、Kotlin でコンパイルする利用者に 2.3 以上を求める。2.2 に下げれば 2.1 以上で使える。`apiVersion` 2.2 は実行時に `kotlin-stdlib` 2.2 以上を求める。AAR はファイルで配る（D-17）ので依存の版は伝わらず、**`unity-native-plugin` が足している stdlib 2.0.21 は 2.2 以上に上げてもらう必要がある** |
| Dokka | 2.0.0 | 2.2.0 | 2.1.0 から Dokka Gradle Plugin v2 が既定 |
| compileSdk | 35 | 36 | **37 にしない**。AGP 9 は既定で利用者に同じ compileSdk 以上を求める（AAR の `minCompileSdk`）。37 は Flutter の既定と Unity 6000.4 の上限を超える。`aarMetadata.minCompileSdk = 36` を明示する |
| targetSdk（サンプル） | 35 | 36 | Google Play は 2026-08-31 から、新規アプリと更新に API 36 以上を求めている |
| minSdk | 31 | 31 のまま | Unity（25 以上）と Flutter（24 以上）の利用者は 31 に上げる必要がある（今と同じ） |
| Java / JVM の target | 11 | 17 | 公式の例は 17。Unity 6 も Flutter も JDK 17 が前提で、D8 が変換するので利用者への影響はほぼ無い |
| NDK | - | r30（30.0.16248370、LTS） | `ndkVersion` を明示する（AGP 9.3 の既定は r28.2） |
| CMake | - | 3.31.6、`cmake_minimum_required(VERSION 3.22.1)` | AGP の既定の CMake の版は文書が古い可能性があるので、`externalNativeBuild.cmake.version` を明示する。CMake 4 は古い `cmake_minimum_required` を拒む |
| core-ktx | 1.15.0 | 1.18.0 | **1.19 にしない**（利用者に compileSdk 37 と AGP 9.1.0 を求める） |
| appcompat | 1.7.0 と 1.6.1 | 1.8.0 にそろえる | |
| fragment-ktx | 1.8.6 | 1.9.1 | |
| activity-compose | 1.8.0 | 1.13.0 | compileSdk 36 と AGP 8.9.1 を求める（上限の内） |
| lifecycle-runtime-ktx | 2.6.1 | 2.10.0 | **2.11 にしない**。2.11 は Compose の lifecycle も 2.11 にそろえさせ、利用者に compileSdk 37 と AGP 9.1.0 を求める |
| Compose BOM（サンプルだけ） | 2024.09.00 | 2026.06.01 | **2026.08.00 以降にしない**（compileSdk 37 と AGP 9.1 以上が要る） |
| material | 1.12.0 | 1.14.0 | |
| androidx.media | 1.7.0 | 1.8.0 | androidx.media は 1.8.0 で非推奨になった。Media3 への移行は Media の style を C ABI に入れるとき（D-5 の残り）に検討する |
| androidx.startup | - | 1.2.0 | |
| UiAutomator | - | 2.4.0 | テストだけ |
| espresso / ext.junit | 3.6.1 / 1.2.1 | 3.7.0 / 1.3.0 | テストだけ |
| GoogleTest | - | 段階 2a で決める | Prefab で配られているのは 1.11.0-beta-1（2021 年）だけ。古さが問題なら、ソースを取り込んで組む |

この組み合わせで依存が求める AGP の最大は 8.9.1 なので、**Unity は 6000.0.61f1 以降、6000.3.1f1 以降、6000.4.1f1 以降が対象**になる（それより前のパッチは AGP 8.3.0 / 8.7.2 で、組めない）。マニュアルの動作環境に書く。

**上げる時期**: 段階 0f。段階 0d で今のツールチェーンの基準を記録した後に上げ、同じ UI テストが通ることで、上げたことで動作が変わっていないことを確かめる（Windows の段階 1 で C++20 にしたのと同じ）。

出典: AGP のリリース（https://developer.android.com/build/releases/gradle-plugin ）、AGP 9.0 の変更（https://developer.android.com/build/releases/agp-9-0-0-release-notes ）、KGP と AGP の対応（https://kotlinlang.org/docs/gradle-configure-project.html ）、ライブラリ作者向けの後方互換（https://kotlinlang.org/docs/api-guidelines-backward-compatibility.html ）、Google Play の対象 API（https://support.google.com/googleplay/android-developer/answer/11926878 ）、Unity の Gradle の対応（https://docs.unity3d.com/6000.4/Documentation/Manual/android-gradle-version-compatibility.html ）、androidx の AAR の `aar-metadata.properties`（dl.google.com/android/maven2 から取得して確認）。

### 8.4 出典（調査で使った公式の文書）

- JNI Tips（`JNI_OnLoad`、ClassLoader、`AttachCurrentThread`、Modified UTF-8）: https://developer.android.com/training/articles/perf-jni
- middleware ベンダー向けガイド（1 つの JNI ライブラリ、`c++_static` と version script、Prefab）: https://developer.android.com/ndk/guides/middleware-vendors
- Prefab の公開: https://developer.android.com/build/native-dependencies
- 16 KB のページ: https://developer.android.com/guide/practices/page-sizes
- NDK のリリース: https://developer.android.com/ndk/downloads 、 https://github.com/android/ndk/wiki
- App Startup: https://developer.android.com/topic/libraries/app-startup
- 非 SDK インターフェースの制限: https://developer.android.com/guide/app-compatibility/restrictions-non-sdk-interfaces
- ARCore の C API（`void*` で `JNIEnv` と Context を受ける例）: https://developers.google.com/ar/reference/c/group/ar-session
- Play Games Services v2 の C API（`Pgs_initialize(JavaVM*, jobject)`）: https://developer.android.com/games/services/cpp/v2/api/group/play-games
- Unity 6 の GameActivity（プレイヤーループがネイティブのスレッドで動く）: https://docs.unity3d.com/6000.3/Documentation/Manual/android-application-entries-game-activity-requirements.html
- Unity の `DllImport`: https://docs.unity3d.com/6000.3/Documentation/Manual/plug-ins-native-dllimport.html
- Flutter の main スレッドの統合（3.29）: https://docs.flutter.dev/release/breaking-changes/macos-windows-merged-threads
- Dart の `NativeCallable.listener`: https://api.flutter.dev/flutter/dart-ffi/NativeCallable/NativeCallable.listener.html
- `FlutterActivity` の基底クラス: https://api.flutter.dev/javadoc/io/flutter/embedding/android/FlutterActivity.html

## 9. DoD

- [ ] D-1 〜 D-17 を決める（残りは C ABI の設計で決める D-4・D-6・D-8・D-9・D-10・D-13）
- [ ] 段階 0a のスパイクで、UiAutomator と人の確認の分担を確定する
- [ ] Clipboard / Notification / Share / Dialog のすべてにサンプルの UI テストがある
- [ ] 段階 2a のスパイクで 8.2 の 3 つを確かめる
- [ ] UI テスト・Kotlin の API・C ABI の設計書を書き、別のモデルのレビューを通す
- [ ] Gradle のルートが `android/` で、絶対パスが残っていない（段階 0）
- [ ] パッケージ名に `android.*` が残っていない（段階 0e）
- [ ] ツールチェーンが 8.3 の版で、AAR の `minCompileSdk` が 36、依存の `minAndroidGradlePluginVersion` の最大が 8.10.0 以下（段階 0f。AAR の `aar-metadata.properties` で確かめる）
- [ ] `scripts/test_android.sh` があり、今のコードの結果を基準として記録している（段階 0d）
- [ ] 段階 1 の前後で、サンプルの UI テストの結果が変わらない
- [ ] `unity-native-plugin` が C ABI を呼ぶ形に書き換わり、Android のテストと Player テストを通している（別リポジトリ）
- [ ] 1.2 のロジックがすべて `android_library` にあり、ネイティブのサンプルが自前の Receiver を持っていない
- [ ] `android_library_capi` が今のブリッジの 45 操作と通知の権限の要求を公開している（機械照合）
- [ ] 公開シンボルが `ntk_*` と `JNI_OnLoad` だけで、libc++ のシンボルを出していない（`nm -D` で確かめる）
- [ ] 16 KB のページに合っている（`zipalign -c -P 16` か `llvm-objdump` の LOAD の整列で確かめる）
- [ ] `check_c_abi_contract.py` と `check_manual_c_examples.py` が Android でも通る
- [ ] `unity_android_plugin` がリポジトリに残っていない（モジュール、スクリプト、README、ルール、`dist/` の新しい版）
- [ ] マニュアルの Android の章に C ABI の節があり、3 言語で一致している

## 10. 関連

- `artifact/topics/windows-architecture/README.md`（手本。特に 5 章の段階の分け方と 8 章の D-4〜D-10）
- `artifact/topics/windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md`（引き継ぐ規約の出典）
- `artifact/topics/migration/README.md` 7 章（`android-toolchain-migration`。D-14）
- `artifact/topics/bridge-testing/README.md`（ブリッジの層のテストの穴。C ABI のテストを作るときに参照する）
- `agent-rules/coding-rules/android.md`（段階 4 で、モジュールの配置の表を `android_library_capi` に書き換える）
