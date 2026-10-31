# iOS の汎用 C ABI

- 記録日: 2026-10-18
- 改訂: 2026-10-18 に別モデル 2 者のレビュー（`reviews/2026-10-18-ios-c-abi-plan-review-v1.md`）を反映した。事実の誤り 3 つ（署名、Dialog の既定の文言、エラーの型）を直し、通知の delegate を早く入れる入口（D-4・D-7）、`release` の同期の場合（D-6）、bundle id（D-12）、署名（D-18）、ブリッジの扱い（D-22）、`unity-native-plugin` に先に頼むこと（5 章）を決め直した。同日に 2 回目のレビュー（`reviews/2026-10-18-ios-c-abi-plan-review-v2.md`）を反映し、delegate を入れる関数を同期の例外にし（D-4・D-6）、呼ぶ範囲を通知の機能全体に広げ、署名の照らし方、bundle id を変える範囲、リリース版を決める時期を直した。3 回目の確認（`reviews/2026-10-18-ios-c-abi-plan-review-v3.md`。Codex）で区分 A が 0 になり、残った 1 件（D-19 の版を決める時期）を直してレビューを終えた
- 状態: 進行中。D-1〜D-22 は 2026-10-18 に利用者が推奨のとおり決めた（8.1）。段階 0a（UI テストのスパイク）と 0b（サンプルの識別子と最後のイベントの表示）は完了し、UI テストの設計書も決定した（2026-10-18）。段階 0c（UI テスト 99 件）と 0d（`scripts/test_ios.sh` と 2 つの環境の基準）も完了した（2026-10-24）。ただし 0c はシミュレーターで完了したもので、実機は区分の無い 19 件だけを流した。区分の要る 80 件の実機の実行と、人の確認の手順書が残る。0e の前に `UnityIosPluginTests` の 83 件を一度流した（D-22）。段階 0e（設定をそろえ、strict concurrency の警告を 423 件から 0 件にした）もシミュレーターで完了した（2026-10-25）。実機での確かめと `LastUpgradeCheck` の反映は残る。段階 0f（Swift 6 の言語モード。`IosLibrary`・サンプル・2 つのテストのターゲット）もシミュレーターで完了した（2026-10-25）。段階 0g（framework の bundle id を `com.jonghyunkim.nativetoolkit.IosLibrary` に）も完了した（2026-10-31）。0e〜0g の後の区切りとして、シミュレーター（iPhone 17 / 26.2）の全件で基準を取り直し（320 件成功、意図した skip 1 件）、実機（iPhone XS / 18.7.2）でも区分の無いもの・`systemui`・`sharesheet` の 60 件がすべて通り、実機の基準を 19 件から 60 件に広げた（`results/2026-10-24-ios-c-abi-stage0e-working-notes.md` の 10・11 章）。実機の `clipboard`・`files`・`reinstall`・`credentials` の 39 件と、人の確認の手順書は残る。`LastUpgradeCheck` の反映も残る。次は段階 1a
- 分類: 横断課題（アーキテクチャ）。機能追加ではない
- 進め方: Windows（`windows-architecture`、1.12.0）と Android（`android-c-abi`、1.13.0）と同じ汎用 C ABI を、1 OS ずつ作る。このトピックは iOS の分（D-1）。macOS は iOS が終わってから別のトピックにする
- 対象: `ios/IosLibrary`、`ios/UnityIosPlugin`（新しい C ABI のモジュールに置き換える）、`ios/IosLibraryExample`、`scripts/build_ios_library_xcframework.sh`、`ios/generate_docc.sh`、`scripts/publish_docs.sh`、配布物 `ios-native-toolkit-*.xcframework` / `unity-ios-native-toolkit-*.xcframework`
- チケット: NTKIT-18（ブランチ `feature/NTKIT-18` の名前から。中身は未確認）
- 手本: `artifact/topics/android-c-abi/`（直前に出荷した C ABI。段階の分け方、設計書、照合、Unity への申し送り）と `artifact/topics/windows-architecture/`（規約の出典）

## 0. 調べたこと

2026-10-18 に、観点の違う 4 つの調査を行った。あわせて、Android の C ABI を進めたセッションから、artifact/ に書かれていない知見を受け取った。この README の事実は、断りがない限りこれらから引いている。

| 観点 | 調べたもの |
|---|---|
| iOS の今の公開面 | `IosLibrary` と `UnityIosPlugin` の全公開関数、JSON の入力、コールバックとそのスレッド、テスト、サンプル、ビルドのスクリプト、`dist/1.13.0/ios` の実物（`file`、`otool -L`、`nm -gU`、`codesign -dvv`）、`unity-native-plugin`（別リポジトリ）の iOS の C# 側、macOS との重なり |
| Windows・Android から引き継ぐもの | Android の C ABI の設計書 第 1 部・第 2 部、Windows の C ABI の設計書、公開ヘッダー、照合のスクリプト、Unity への申し送り、段階の結果 |
| iOS で C ABI を作る前提 | Swift から C を出す方法（`@_cdecl`、Swift 6.3 の `@c`、Objective-C の入口）、静的と動的の配布、XCFramework の署名とプライバシーマニフェスト、スレッド、通知の delegate、初期化。公式の文書を優先し、手元で試した（出典は 8.5） |
| ツールチェーンの版 | 手元の Xcode・SDK・シミュレーター・実機、プロジェクトの設定、App Store Connect と利用者（Unity、Flutter、React Native、Godot）の要件、Swift 6 への移行の状態 |
| Android から引き継ぐ知見 | `results/2026-10-18-ios-c-abi-android-lessons.md`（やり直した決定、レビューで繰り返し指摘された種類、Unity の包みで分かったこと）。この README の「知見 n 章」はこのファイルの章 |

試したことのうち、記録に残すもの（検証のファイルは scratchpad に置き、リポジトリには入れていない）:

- Xcode 26.3（Swift 6.2.4）では `@c` は使えない（`unknown attribute 'c'`）。`@_cdecl` の宣言は、生成ヘッダーの `#if defined(__OBJC__)` の中にしか出ない
- `IosLibrary` の最小 iOS を下げて組むと、15.0 は `UIPasteControl`（iOS 16 から）の 5 か所で失敗し、16.0 と 17.0 は通る（組めることだけ。動かしてはいない）
- Swift のコードを含む静的ライブラリを、C の `main` に clang だけでリンクすると、最小 iOS 15.x では `swiftCompatibility56` が未定義で失敗し、16.0 以上では何も足さずに通る
- 同じ Swift のモジュール名を持つ 2 つの静的ライブラリをリンクすると、`duplicate symbol '_OBJC_CLASS_$_...'` で失敗する。`ld -r -exported_symbols_list` で先に隠すとリンクは通るが、Objective-C の実行時のクラス名は 2 つ残る
- Swift 5 + `SWIFT_STRICT_CONCURRENCY=complete`（whole-module、clean build）の警告は、`IosLibrary` 104 件（Dialog 63、Notification 27、Share 14）、`UnityIosPlugin` 6 件。Clipboard は 0 件。このブランチで数えたので基準ではない（`migration` の 4.2 の 129 件から、直した Clipboard の 19 件を引いた数と一致する）
- Unity 6000.4.2f1 に同梱のトランポリン（`UnityAppController+Rendering.mm`）で、プレイヤーループは main の run loop の `CADisplayLink` から回る。**iOS の Unity の C# は main スレッドで動く**。`startUnity` は scene が接続した後に呼ばれるので、**C# が始まるのはアプリの起動が終わった後**である（`UnityAppController.mm`）

## 1. 何が問題か

### 1.1 iOS には汎用の C ABI が無い

Android と違い、iOS には C の関数が既にある。`UnityIosPlugin.framework` は Objective-C の `.m` に C の関数を 43 個書き、Swift を呼んでいる。`dist/1.13.0/ios` の実物の `nm -gU` も 43 個で、`unity-native-plugin` の `DllImport("__Internal")` も 43 本ある。しかし、これは Unity 専用の形で、汎用の C ABI ではない。

| 項目 | 今の形 | 汎用の C ABI に足りないこと |
|---|---|---|
| 入力 | Clipboard の 13 関数、Notification の content / trigger / category、Share が JSON の文字列。Dialog は位置引数 | 型が無い。利用者が JSON を組み立てて解析する（`unity-native-plugin` の Builder / Parser / Reader は計 2,544 行） |
| コールバック | C の関数ポインタ。`user_data` も `release` も無い。Notification の 3 つは static の変数に 1 つだけ持つ | 1 つの利用者しか受けられない。どの要求の完了か、いつ片付けてよいかが分からない |
| 文字列の寿命 | `NSString.UTF8String` をコールバックの間だけ貸す | Android の規約（所有権ごと渡し、受け手が `_free`）と逆 |
| ヘッダー | `*Bridge.h` は framework の公開ヘッダーに入っていない（入っているのは umbrella と `-Swift.h` だけ） | 利用者は宣言を自分で書くしかない |
| 名前 | `clipboardCopy`、`showDialog`、`notificationSetup` など。接頭辞が無い | ほかのライブラリとぶつかりうる。`ntk_*` の規約に合わない |

そのため、Unity 以外の C の利用者（Flutter の `dart:ffi`、Rust、Godot、React Native の C++、C / Objective-C のアプリ）は、Swift を書かずに iOS のライブラリを使えない。

dist の 2 つの xcframework はどちらも **dynamic の framework**（`ios-arm64` と `ios-arm64_x86_64-simulator`）で、`UnityIosPlugin.framework` は `@rpath/IosLibrary.framework` に依存する。**xcframework そのものは署名されていないが、`ios-arm64` のスライスの 2 つの framework は、利用者の個人の Apple Development の証明書（`Apple Development: Jong Hyun Kim`、Team `C9KYBZ33LV`）で署名されている**。シミュレーターのスライスは ad-hoc の署名。どの pbxproj も `CODE_SIGN_STYLE = Automatic` で、ビルドのスクリプトは署名の設定を渡していない（D-18）。bundle id は `ios.library.IosLibrary` と `unity.ios.plugin.UnityIosPlugin`（D-12）。

Unity の側は `IosFrameworkPatcher` / `[PostProcessBuild]` が 2 つを UnityFramework にリンクし、アプリに埋め込んでいる。Unity のシンボル（`UnitySendMessage`、`UnityGetGLViewController`）への依存は無い。

### 1.2 ネイティブの利用者に届かないロジックがブリッジにある

Android ほど多くない。イベントの受け口（通知の delegate）、前面の ViewController の探索、Dialog の既定の文言（"OK"、"Cancel" など）、Clipboard のエラーコード（24 個）は既に `IosLibrary` にある。ブリッジにしか無いのは次のものだけである。

| 機能 | ブリッジにしか無いもの |
|---|---|
| 共通 | JSON の形式とその解析・組み立て（Clipboard 396 行、Notification 201 行、Share 58 行）。`common.md` の「複雑なデータは JSON 文字列で渡す」に従った結果で、C ABI では型にするので移さずに捨てる |
| Clipboard | main actor への受け渡し（`IosClipboardManager` は `@MainActor`）。「append は options を受けない」の検査 |
| Dialog | 3 つのコールバック（onButton / onCancel / completion）を 1 つの結果にまとめる処理。キャンセルしたときの入力を `nil` にする正規化。アクションシートの popover の基点（`getRootViewController().view`。ライブラリの `showActionSheet` は `sourceView: UIView` を必須にしている） |
| Notification | 予約済み・表示済みの一覧と日時（ISO 8601）の変換、権限の状態の文字列化、userInfo の変換、sound が無いときに `.default` にする既定値 |
| Share | 要素の種類（text、url、image、file）から `ShareItem` への変換 |

どちらにも無いもの:

- 安定したエラーの番号。`NotificationError` と `ShareError` は enum としてあるが、任意の `Error` を持つ case（`attachmentLoadFailed(Error)`、`presentationFailed(Error)`、`unknown(Error)` など）があり、ブリッジは `localizedDescription` の文字列だけを返している。Dialog にはエラーの型が無い
- 受け手が登録される前に届いた通知のイベントを保つ仕組み。コールドスタートで、利用者がまだ登録していない間のタップは捨てられる
- 通知のイベントの複数の受け手。`IosNotificationManager.onActionReceived` は 1 つしか持てず、ブリッジが上書きする

### 1.3 コールバックを返すスレッドが機能ごとに違う

| 機能 | 今のスレッド |
|---|---|
| Clipboard | main（全経路が `Task { @MainActor }` を通る） |
| Share | main |
| Dialog | main。ただし `showActionSheet` は、呼び出し元のスレッドで ViewController を探し、失敗すると呼び出し元のスレッドで同期的に返す |
| Notification の操作の結果 | **main の保証が無い**（分離していないクラスの `Task {}` から返る）。JSON の解析の失敗と `registerCategory` は呼び出し元のスレッドで同期的に返る |
| Notification のアクション | `UNUserNotificationCenterDelegate.didReceive` から直接。スレッドは文書に書かれていない |

C ABI では 1 つの規則にそろえる（D-6）。

### 1.4 その他、移す前に分かっている不備

- ログ: `Log` は `print` で、`#if DEBUG` が無いので Release でも出る。ブリッジはユーザー名とパスワード（`UnityIosDialogManagerBridge.m:223`）、テキスト入力の値、通知の返信、通知と Share の内容の全文をログに出している。`agent-rules/coding-rules/ios.md` は「全パラメータを出す」と定め、秘密の値を伏せる例外が無い（Android には `android.md` にある）。Clipboard だけは `ClipboardRedaction` で伏せている
- 通知の delegate: `IosNotificationManager.setup()` は `UNUserNotificationCenter.current().delegate` を無条件に上書きし、前の delegate に転送しない。`willPresent` もすべての通知に自分で応える。delegate は 1 つしか持てず（weak）、起動の終わりまでに入れないと取りこぼす（Apple の文書）。ホスト（Unity の通知パッケージ、Flutter のプラグイン、Firebase）も設定する（D-7）
- Notification: 権限の問い合わせの受け手が static の変数 1 つなので、重ねて呼ぶと前の受け手が上書きされる。`registerCategory` は登録が終わる前に成功を返す。category の登録と削除は、今の一覧を読んで書き戻す形を別々の `Task` で行うので、並行すると片方の変更が失われうる。`cancel` と `cancelScheduled`、`cancelAll` と `cancelAllScheduled` が同じ処理。`content.id` は必須なのに schedule と update で使われない。userInfo を JSON にする前に `isValidJSONObject` で確かめていない（`JSONSerialization` の NSException は `try?` では止まらない）
- Dialog: 完了が 1 回も呼ばれない経路が 2 つある: `showLoginDialog` の失敗（結果は `onLogin` だけで返る）と、UIKit が表示を断ったとき（見つけた ViewController が window に無いなど。0e でシミュレーターで確かめた）。テキスト入力とログインでは、確定ボタンの handler と observer が `alert` を強く持つので、循環参照の見込みがある（測っていない。DocC の「Memory」の記述と合わない見込み）。テキスト入力とログインで足した observer を外していない。失敗の返し方が、ログインは `onLogin`、テキスト入力は `completion` で揃っていない。ブリッジの `.m` はコールバックの `NULL` を確かめずに呼ぶ。必須の引数の `NULL` を `stringWithUTF8String:` に渡しうる
- 規則: `NotificationError` と `ShareError` が任意の `Error` を持っている（`common.md` の「system の `Error` を Domain に保持しない」に反する）
- プライバシーマニフェスト: `PrivacyInfo.xcprivacy` が無い。Clipboard の一時ファイル（`ClipboardTemporaryFileStore.swift`）が `.contentModificationDateKey` を使っており、理由の申告が必要な API（`NSPrivacyAccessedAPICategoryFileTimestamp`）に当たる（D-18）
- 署名と bundle id: 1.1 のとおり、個人の証明書で署名したスライスを配っている。bundle id は持っていない逆 DNS の名前空間（`ios.library.*`、`unity.ios.plugin.*`）で、Android の `android.library` と同じ状況である（D-12、D-18）
- Swift の並行性: 全ターゲットが Swift 5.0 の言語モードで、strict concurrency を設定していない。complete にすると 110 件の警告が出る（0 章）。`migration` のトピックで決めた案 C（ブリッジの handler に `@Sendable`、main への配送を全経路でそろえる）は Clipboard にだけ入っている（D-14）。0e で complete の警告を 0 にし、0f で Swift 6 の言語モードにした（UI テストのターゲットは D-14 の例外）
- テスト: Dialog のテストはどのターゲットにも無い。ブリッジの C 関数を呼ぶテストも 0 件（`bridge-testing`）。iOS のテストのスクリプト（`test_android.sh` / `test_windows.ps1` に当たるもの）と基準が無い。サンプルの UI テストは 25 件で、うち 22 件が Clipboard、3 件が雛形（`testExample`、`testLaunchPerformance`、`testLaunch`）。`accessibilityIdentifier` は Clipboard の画面（5 か所）と一覧（1 か所）にしか無い。テストのターゲットだけ最小 iOS が 18.2 で、本体（18.0）とずれている
- `unity-native-plugin`: iOS の xcframework は `VERSION.txt` で版を固定しておらず、`PreBuildProcessor` が dist の最新版を選ぶ（macOS も同じ）。Windows（1.12.0）と Android（1.13.0）で、新しい dist を置いた時点で向こうのビルドが壊れたのと同じ罠が残っている。さらに、`PreBuildProcessor`・`PostBuildProcessor`・`IosFrameworkPatcher` の 3 か所が `ios-native-toolkit-` の前方一致で xcframework を探すので、`ios-native-toolkit-capi-` の名前を足すと capi の側を `IosLibrary` として選ぶ（並べると `capi-2.0.0` > `2.0.0`）。`PostBuildProcessor` は development ビルドで `-debug.xcframework` しか探さず、見つからないと `LogError` を出すが、ビルドは止めずに埋め込まない。5.2

## 2. なぜ今やるか

- Windows と Android の 2 つで規約（名前、エラー、UTF-8、ハンドル、`struct_size`、`user_data` と `release`、main への非同期の配送）が固まり、OS をまたいで照らす仕組み（`c_abi_contract_common.py`）もできた。Android の記録が新しいうちに 3 つ目を作れば、同じ作法を保てる
- `unity-native-plugin` は Windows と Android を P/Invoke の C ABI に移したばかりで、`user_data` の表と完了の積み方の土台がある。iOS も同じ形にすれば、iOS の C# の JSON の層（Builder / Parser / Reader）を消せる
- iOS の Swift 6 への移行（`migration`）は、公開 API を変える直し（`shared` に `@MainActor` を付けるなど）を含む。破壊的変更の 2.0.0 に入れるのが最も安い（D-14）
- 1.4 のログ、プライバシーマニフェスト、通知の delegate、署名、bundle id は、C ABI と関係なく直す必要がある

## 3. 目標の構成

段階 4 が終わった時点の形。`(新)` は新しく作るもの、`(移)` は 1.2 のロジックを移して作るもの。モジュール名とクラス名は案で、設計書で決める。

```
ios/
  IosWorkspace.xcworkspace                      # 下の各プロジェクトをまとめる
  IosLibrary/                                    # Swift の API（ios-native-toolkit-2.0.0.xcframework。dynamic）
    IosLibrary/                                  # bundle id は com.jonghyunkim.nativetoolkit.IosLibrary（D-12）
      PrivacyInfo.xcprivacy                      # (新) FileTimestamp の理由（D-18）
      Common/Log.swift                           # 秘密の値を伏せる規則（8.6）
      Clipboard/  Dialog/  Notification/  Share/
        Dialog/{Domain,Application,Presentation}/ # (移) 結果を 1 つにまとめた型。ほかの機能と同じ層に分ける
        Notification/Presentation/               # (移) イベントの口（複数の受け手、受け手が登録されるまで保つ）、
                                                 # delegate を起動の終わりまでに入れる口と転送（D-7）
        */Domain/Model/*Error.swift              # 安定した case に直す（任意の Error を持たない。Dialog は新規）
    IosLibraryTests/
  IosLibraryCApi/                                # (新) 汎用の C ABI（ios-native-toolkit-capi-2.0.0.xcframework。dynamic。D-9）
    include/NativeToolkitC/                      # 公開ヘッダー（xcframework の Headers と dist/ に入れる）
      Common.h                                   # OS に依存しない部分（Windows / Android と照らす。3.3）
      Clipboard.h  Dialog.h  Notification.h  Share.h
    IosLibraryCApi/
      Common/                                    # C の入口の土台: ハンドル、struct_size、UTF-8、スレッドごとの ntk_last_system_code、
                                                 # コールバックの登録表と release の状態機械、main への積み方
      Clipboard/  Dialog/  Notification/  Share/ # C の入口（C。Objective-C は使わない）。検査して Swift の受け口を呼ぶだけ（D-10）
      Adapter/                                   # Swift の受け口。IosLibrary を呼んで型を変換するだけ。利用者に見せない（D-10・D-11）
      IosLibraryCApi.exp                         # 公開するシンボル: _ntk_* だけ（D-11）
  IosLibraryCApiTests/                           # (新) C ABI のテスト（C の関数を XCTest から呼ぶ。ASan / TSan でも流す）。
                                                 # 名前は Xcode の作法（<製品名>Tests）で、iOS の今のテストのターゲットにそろえる
                                                 # （Windows の WindowsLibraryCApiTest とは単数と複数が違う。2026-10-18、利用者の了承）
  IosLibraryCApiSmoke/                           # (新) dist の 2 つの xcframework だけを使う C / Objective-C のアプリ。Swift のコードを持たない
  IosLibraryExample/                             # ネイティブのサンプル。Swift の API だけを使う
    IosLibraryExampleUITests/                    # 全機能の UI テスト（段階 0c）
```

無くなるもの:

| 対象 | 時期 |
|---|---|
| `ios/UnityIosPlugin/` のビルドと基準からの除外 | 段階 0e（D-22。ソースは 1b の参照のために残す） |
| `ios/UnityIosPlugin/`（`unity-ios-native-toolkit-*.xcframework`） | 段階 3 |
| `ios/Docs/UnityIosPlugin`、`docs/<版>/ios/UnityIosPlugin` の生成 | 段階 3 |

配布物（`dist/<リリース版>/ios/`。D-9、D-17）:

| ファイル | 中身 | 使う人 |
|---|---|---|
| `ios-native-toolkit-2.0.0.xcframework` | Swift の API（`IosLibrary.framework`、swiftinterface、プライバシーマニフェスト） | Swift のアプリ。C の利用者も一緒に埋め込む |
| `ios-native-toolkit-capi-2.0.0.xcframework` | C ABI（`IosLibraryCApi.framework`。`Headers/NativeToolkitC/*.h`、module map、公開シンボルは `ntk_*` だけ。Swift のモジュールと interface、Swift 向けのヘッダーは配らず、利用者が import できる Swift の API を出さない。実行時の metadata が残るのは許す（D-11）） | C の利用者。`ios-native-toolkit-2.0.0.xcframework` も一緒に埋め込む |
| `include/NativeToolkitC/*.h` | 公開ヘッダー（xcframework の中と同じもの） | ヘッダーからバインディングを作る人（ClangSharp、bindgen、ffigen） |

依存の向きは `IosLibraryCApi` → `IosLibrary`。Windows・Android と同じく、**機能の実装は `IosLibrary` にだけ置き**、`IosLibraryCApi` は型の変換（UTF-8 と `String`、ハンドルと Swift のオブジェクト、関数ポインタと Swift のクロージャ）、検査、スレッドの受け渡しだけを受け持つ。

| 利用者 | 使うもの |
|---|---|
| Swift / Objective-C のアプリ（Swift の API を使う） | `IosLibrary`（今のまま） |
| C の利用者（Unity、Flutter、Rust、Godot、React Native の C++、C / Objective-C のアプリ） | `IosLibraryCApi`（と、それが依存する `IosLibrary`） |

### 3.1 利用者の前提

C ABI の設計書の冒頭に置く。言語ごとの導入の手順（埋め込み、ヘッダー、コールバックの受け方）はマニュアルに書く（段階 4）。Unity の導入の手順は、Android と同じく `unity-native-plugin` のマニュアルに任せる（Android の段階 4 の M-4）。

| 前提 | 理由 | 成り立たない使い方 |
|---|---|---|
| UIKit のアプリのプロセスの中で呼ぶ | UIKit、`UNUserNotificationCenter`、`UIPasteboard` を使う | App Extension、コマンドラインの実行ファイル（確かめない。8.4） |
| 2 つの framework をアプリに埋め込む（Embed & Sign） | どちらも dynamic で、`IosLibraryCApi` は `IosLibrary` に依存する（D-9） | `IosLibraryCApi` だけを入れる使い方 |
| アプリの最小 iOS が 18.0 以上（D-15） | xcframework の最小 iOS | iOS 17 以前の端末 |
| Xcode 26.0 以上で組む（D-16） | App Store Connect の要件（2026-04-28 から）と同じ。Swift の API を使う利用者は swiftinterface を読む | Xcode 16 以前 |
| 自分が作っていないスレッドからのコールバックを受けられる | コールバックは iOS の main キューから非同期に呼ぶ（D-6） | Dart の `NativeCallable.isolateLocal`（バックグラウンドの isolate では abort する）。Unity は `[MonoPInvokeCallback]`、Dart は `NativeCallable.listener` で受ける |
| Dialog・Share・権限の要求は、前面に scene があるときに呼ぶ | 前面の `UIWindowScene` の key window の上に出す | アプリが後ろにいるときの呼び出し（専用のエラーを返す。設計で決める） |
| 通知の機能を使うなら（イベントを受けることと、前面にいるときの表示）、**ホストのネイティブのコードが、起動の終わりまでに main スレッドで `ntk_notification_install`（仮）を呼ぶ**。ホストが後から delegate を無条件に上書きしない | delegate は 1 つしか持てず、起動の後に設定するとコールドスタートのタップを取りこぼす（Apple の文書）。前面にいるときに通知を出すかも delegate の `willPresent` で決まるので、入れないと前面の間は通知が出ない（1.x の Unity はいつも `notificationSetup` を呼んでいた）。Unity の C# も Dart も起動の後に始まるので、C ABI の関数を C# や Dart から呼ぶのでは間に合わない（D-4、D-7） | ネイティブのコードを持たない組み込み（Unity は `unity-native-plugin` の側に `.mm` が要る。2c）。ホストの通知のプラグインが後から delegate を上書きする構成（Unity の通知パッケージなど）。この場合はイベントが届かない |

Swift のアプリは C ABI を使わず、`IosLibrary` を直接呼ぶ。

### 3.2 Windows・Android と同じにするもの、iOS で決め直すもの

Android の C ABI の設計書（第 1 部の AC-n、第 2 部の AP-n）と Windows の設計書（E-n）を、次のとおり扱う。規約の一覧は Android の第 1 部 1.1 の表にある。

| 扱い | 対象 |
|---|---|
| そのまま引き継ぐ | 名前の規則（`ntk_<機能>_<動詞>`）、エラーは戻り値（機能ごとの `int32_t` の列挙、0 が成功、欠番は詰めない、0〜5 の共通の番号。AP-12）、UTF-8 だけと厳密な検査（E-7、Android 第 1 部 5.10）、U+FFFD への置き換え（E-16、AC-19）、真偽値は `int32_t`（E-8）、0 で埋めた構造体が既定値（E-9）、出力はすべてハンドル（E-5）、`struct_size` の読み方（Windows の設計書 7.8）、件数は `size_t`、すべてのコールバックの `void* user_data`、`release` は `release != NULL` ならちょうど 1 回（入口で拒んだときは呼び出し元のスレッドで関数が戻る前に、受け付けた後は main で。E-12、AC-6）。ただし通知の delegate を入れる関数は、AC-5（main から呼ばれても積む）の例外にする（D-6）、`_free(NULL)` は何もしない、`NULL` の入力の扱い（E-15）、非同期の完了はシステムコードを引数で渡す（E-18）、`ntk_version()` とリテラルの版のマクロ、公開ヘッダーの形（`<stdint.h>` と `<stddef.h>` だけ、ASCII、C99 と C++）、64 ビットの要求の ID（AC-17）、コールバックのハンドルは所有権ごと渡す（AC-18）、スレッドの規則（AC-4〜AC-6。D-6）、Dialog は非同期だけ（AC-7。D-8）、`release` の状態機械の形（AC-6、AC-21）、ブリッジを 1 つずつ写さない（AC-23）、値の補正をせずエラーで返す（AP-8） |
| iOS で決め直す | C の入口の書き方（JNI → C と Swift の受け口。Objective-C は使わない。D-10）、公開の方法（version script → `EXPORTED_SYMBOLS_FILE`。D-11）、配布の形（AAR と m2 → 2 つの dynamic の xcframework。D-9、D-17）、初期化（JNI と Context → 通知の delegate だけ。D-4）、`ntk_last_system_code()` に入れる値（D-13）、通知の delegate とホストの共存（D-7）、前面の扱い（前面の Activity → 前面の scene と key window）、利用者のコールバックの例外と UIKit の例外（D-10）、文字列の変換（`NSString` は対になっていないサロゲートを持てる。8.6） |
| Android 専用で関係しない | `ntk_android_*`、Startup と 4 つの初期化の状態、JNI の Modified UTF-8、`RegisterNatives`、Prefab、`ANDROID_STL`、R8 の keep の規則、32 ビット、16 KB のページ、チャンネルのビルダー、前景サービス、Direct Share と Chooser Action |

### 3.3 OS をまたいだヘッダーの扱い

Android の D-3 と AC-11 をそのまま使う。`Common.h` は OS ごとに写して持ち、OS 間で 4 つの扱い（一致させる / OS ごとの展開 / 名前と計算だけ一致 / OS ごとに許す）で照らす。`NTK_VERSION` は、その OS のライブラリの版（iOS は 2.0.0）。機能のヘッダーは OS ごとに持ち、**同じ意味の操作には同じ名前を付ける**。

- Dialog と Share の名前は、Android が OS に依存しない形で選んだもの（`ntk_dialog_show_*_async`、`ntk_dialog_cancel`、`ntk_share_*`、`ntk_<機能>_add_*_listener` と `ntk_<機能>_listener_remove`）に合わせられるかを、第 2 部の最初に確かめる。iOS だけの種類（destructive、アクションシート）は同じ形で足す
- 同じ名前でも、引数・列挙の値・構造体の配置は OS ごとに違ってよい（C# のバインディングは `Common.h` のほかは OS ごとに宣言する。Android 第 2 部 RP-5）
- 通知の delegate を入れる関数（D-7）は Notification の機能に属するので `Notification.h` に置く（`ntk_notification_*`）。ほかに OS 専用の関数が要る場合だけ `Ios.h`（接頭辞 `ntk_ios_`）を作る

照合（`c_abi_contract_common.common_header_problems`）は、今は Windows と Android の 2 つを決め打ちしている。N 個の OS と、OS ごとに許す定数の表を扱えるように直す（段階 2a）。どの OS の `Common.h` を変えても、全 OS の照合を流す。

## 4. Swift の API の方針

C ABI の前に、1.2 のロジックを `IosLibrary` へ移し、ネイティブの利用者が Swift だけで全機能を使えるようにする。Android の段階 1b に当たる。足す API の形（イベントの口、Dialog の結果、エラーの分類、スレッド）は C ABI の要求で決まるので、**C ABI の設計書の第 1 部（スレッド・寿命・通知の delegate）を先に決めてから、Swift の API の設計書を書く**（5.1）。

| 足すもの・直すもの | 置き場所（案） |
|---|---|
| Dialog の結果を 1 つの型にまとめる（押したボタン・キャンセル・入力）。キャンセルしたときの入力の扱い、アクションシートの基点を省いたときの既定（前面の key window の最前面の ViewController の view）、引数を省いたときの既定の文言（今のライブラリの既定。C ABI では 0 で埋めた構造体のときの既定になる）。observer を外す。失敗の返し方をそろえる | `Dialog/` |
| Dialog を、ほかの機能と同じ層に分ける。今は `IosDialogManager.swift` の 1 ファイル（458 行）。Android の 1b と同じ扱い | `Dialog/{Domain,Application,Presentation}/` |
| 通知のイベントの口: 複数の受け手、受け手が登録されるまでイベントを保つ（件数・期限・重複は設計で決める。Android は 32 件）、起動のきっかけになった通知を取る口 | `Notification/Presentation/` |
| 通知の delegate を、起動の終わりまでに入れる口と、前の delegate へ転送する形にする（D-7） | `Notification/Presentation/` |
| 権限の状態を列挙にする。権限の問い合わせを、重ねて呼んでも受け手が上書きされない形にする | `Notification/` |
| `registerCategory` を登録の完了で返す。category の読み書きを直列にする | `Notification/Data/` |
| エラー: 今の `NotificationError` と `ShareError` を基にし、任意の `Error` を持つ case を安定した case に直す（2.0.0 の破壊的変更）。Dialog のエラーの型を作る。各 case と C ABI のエラーの番号の対応表を設計書に置く | 各機能の `Domain/Model/` |
| Notification・Dialog・Share の完了を main で返し、handler を `@Sendable` にする（公開 API が変わる。段階 0e。D-14） | 各機能 |
| `Log` の規則: 秘密の値を伏せる。Release での出力の扱い（8.6） | `Common/` |
| プライバシーマニフェスト（D-18） | `IosLibrary/` |

Android と同じく、**ブリッジには手を入れない**（段階 3 で消すので）。0e・0f・1b で `IosLibrary` の公開 API が変わるので、ブリッジは 0e でビルドと基準から外す（D-22）。ソースは段階 3 まで残し、1b で移すロジックとそのテストを読むための参照にする。

### 4.1 2.0.0 で Swift の利用者に見える変更（段階ごとに足す）

移行の手引き（段階 4）の元にする。詳しい差分は `results/swiftinterface/`。

| 段階 | 変更 | 種類 |
|---|---|---|
| 0e | `ShareRepository` と `NotificationRepository` が `Sendable` を要求する（自分で適合させた型に `Sendable` が要る） | 破壊的 |
| 0e | 完了と handler の型が `@MainActor @Sendable` になる（Share 1、Notification の完了 9 と handler の typealias 2、Dialog の完了 7 とボタンの callback 10 と `textFields`）。Swift 5 の minimal では警告も出ない | 破壊的 |
| 0e | Notification の `show`・`update`・`schedule` の `content` が `sending` になる（complete / Swift 6 の利用者だけに効く） | 破壊的 |
| 0e | `NotificationRepositoryImpl.init(center:)` が `init()` になる（渡せる値はもともと `.current()` だけ） | 破壊的 |
| 0e | `IosDialogManager.getRootViewController()` が `@MainActor` になる（nonisolated の同期の文脈からは呼べない） | 破壊的 |
| 0e | `NotificationCategoryOptions.allowAnnouncement` が deprecated になり、category に写さない（iOS 15 から OS が無視している） | 非推奨 |
| 0f | `IosLibrary` を Swift 6 の言語モードで組む。`swift-module-flags` が `-swift-version 6` になり、`StrictConcurrency` と `bare-slash-regex` の指定が消える（Swift 6 で必ず入る）。宣言の差分は無い | 追加 |
| 0f | `shared` に `@MainActor` は付けない（manager は `Sendable` で、どのスレッドからも呼べる。1b で C ABI の受け口と合わせて確かめる） | 変更なし（記録） |
| 0f | `IosClipboardManager(timeouts:limits:)` で作った manager を main 以外で手放してもよい（後始末は main で 1 回走る） | 動作 |
| 0e | Notification の操作の完了が main で返る（前は保証が無かった） | 動作 |
| 0e | 値型・use case・manager に `Sendable` が付く。`IosDialogManager` に `final`。interface に `import Synchronization` と `-enable-upcoming-feature StrictConcurrency` が増える | 追加 |

## 5. 段階

1 段階 = 1 PR を基本にする。Android と同じく、段階 0a〜0d でテストをそろえてから着手する。

| 段階 | 内容 | 動作の変更 |
|---|---|---|
| 0a | スパイク: サンプルの UI テストで扱える項目を確定する（7.2）。XCUITest で、通知のバナーと通知センター（`springboard` の要素）、通知のアクションのボタン、テキスト入力のアクション、**通知からのコールドスタート**（アプリを止め、springboard でタップして起動する）、権限のダイアログ（`addUIInterruptionMonitor` か springboard）、Share のシート（`UIActivityViewController`）、アプリ内の Dialog（`UIAlertController`）、貼り付けの許可のダイアログ、`UIPasteControl` を扱えるか。予約した通知の発火を待てるか。シミュレーターと実機で違うか。scene のある構成と無い構成で、前面の key window の探し方が動くか | 無し |
| 0b | サンプルの画面に `accessibilityIdentifier` を付ける（Dialog・Notification・Share は 0 個。見た目も動作も変えない）。あわせて、通知の画面に「最後に受けたイベント」（タップ・アクション・返信の文字）の表示を足す。今のサンプルは受けても `print` するだけで、UI テストから受け取りを確かめられないため（0a の結果 R-1。サンプルだけの変更で、ライブラリは変えない）。結果の行に更新の回数（`accessibilityValue`。見た目は変わらない）を付け、サンプルの起動の処理で受け手を設定してから `setup()` を呼ぶ順に入れ替える（UI テストの設計書 U-3・U-4）。**完了**（`results/2026-10-18-ios-c-abi-stage0b-result.md`。識別子の数は設計書の 5.1 と一致し、シミュレーターで最後のイベントとコールドスタートを確かめた） | サンプルの通知の画面に表示が 1 つ増える |
| 0c | Dialog / Notification / Share の UI テストを足す（Clipboard は 22 件ある）。XCUITest で扱えない項目は、人の確認の手順書にする。**完了（シミュレーター）**（`results/2026-10-24-ios-c-abi-stage0c-result.md`。99 件をシミュレーターで通し、人の確認に移したケースは無い。**実機では区分の無い 19 件だけを流した。区分の要る 80 件の実機の実行と、人の確認の手順書（HC1・HC4・HC7・HC8）は残っている**） | 無し |
| 0d | `scripts/test_ios.sh` を作り（unit・UI テストをまとめて実行。`xcodebuild test` の結果を `.xcresult` から読む）、**今のコードで全件通ることを確かめ、結果を基準として記録する**。基準は 2 つの環境で取り（D-21）、件数はターゲット全体・機能ごと・雛形に分けて持つ。`UnityIosPluginTests` は `test_ios.sh` の基準に入れないが、0e でビルドから外す前に 83 件を一度流し、結果を `results/` に保存する（D-22）。**完了**（`results/2026-10-24-ios-c-abi-stage0d-result.md`。ランナーは別モデルのレビューを 3 回通して区分 A を 0 にした。基準はシミュレーター（iPhone 17 / 26.2）の 295 件と、実機（iPhone XS / 18.7.2）の区分の無い 19 件。`UnityIosPluginTests` の 83 件は 0e の前に流し、すべて成功した。`results/2026-10-24-ios-c-abi-bridge-tests-before-0e.md`） | 無し |
| 0e | 設定をそろえる: `UnityIosPlugin` をワークスペースのビルドと `test_ios.sh` から外す（D-22）。テストのターゲットの最小 iOS を 18.0 に。Xcode 26 の推奨設定（`LastUpgradeCheck`）を反映するが、変わる build setting の差分を全部記録し、`SWIFT_DEFAULT_ACTOR_ISOLATION` と upcoming feature を明示的に固定する。`SWIFT_STRICT_CONCURRENCY=complete` で `IosLibrary` とサンプルの警告を 0 にする（Notification・Dialog・Share の完了を main で返し、handler を `@Sendable` にする）。公開 API の差分（swiftinterface）を保存する。直した所に関係するテストを両方の環境で流す。**完了（シミュレーター、2026-10-25）**（`results/2026-10-24-ios-c-abi-stage0e-working-notes.md`）。`UnityIosPlugin` をワークスペースから外し、テストのターゲットの最小 iOS を 18.0 にした。`SWIFT_STRICT_CONCURRENCY=complete`、`SWIFT_DEFAULT_ACTOR_ISOLATION=nonisolated`、upcoming feature 18 個をプロジェクトの階層で固定した。警告は 423 件から 0 件（UI テストのターゲットは D-14 の例外で minimal）。Notification・Dialog・Share の完了と handler を `@MainActor @Sendable` にし、全経路で main に返す。公開 API の差分は `results/swiftinterface/`、2.0.0 の変更は 4.1。**実機での確かめと `LastUpgradeCheck` の反映は残っている**。`UnityIosPlugin` は Dialog の `getRootViewController()` の `@MainActor` で組めなくなった（D-22 の範囲。ビルドスクリプトの既定は `IosLibrary` だけなので影響しない。`-m UnityIosPlugin` と `generate_docc.sh` のブリッジの部分は段階 3 で外す） | Notification の操作の結果が main で返る（1.3）。完了と handler の型に `@MainActor @Sendable` が付く（2.0.0）。`allowAnnouncement` を category に写さない（iOS 15 から OS が無視している）。Dialog の便利なメソッドは `UIAlertAction` を main で作る。ログが 2 か所変わる（作業の記録 8.4・9.4） |
| 0f | Swift 6 の言語モードにする（`IosLibrary`、サンプル、テスト。UI テストのターゲットは除く。D-14 の例外）。公開 API が変わる所（`shared` の `@MainActor` など）は 2.0.0 の変更として記録する。直した所に関係するテストを流す。**完了（シミュレーター、2026-10-25）**（`results/2026-10-25-ios-c-abi-stage0f-working-notes.md`）。4 つのターゲットの `SWIFT_VERSION` を 6.0 にした（UI テストのターゲットは D-14 の例外で Swift 5 + minimal のまま）。エラー・警告は 0 件。0e で固定した設定は、Swift 6 の 4 つのターゲットでは 14 個（upcoming feature 13 個と `SWIFT_STRICT_CONCURRENCY`）が効かなくなるが、Swift 5 の UI テストのターゲットが継ぐので外していない。公開 API の宣言の差分は無く（`swift-module-flags` だけ）、`shared` に `@MainActor` は付けない（作業の記録 5 章）。Swift 6 の実行時の隔離の検査で、`IosClipboardManager` を main 以外で手放すと止まることが分かり、後始末を Swift のクラスの `isolated deinit` に移して直した（作業の記録 4.3） | Swift の利用者から見た並行性の注釈は変わらない（宣言の差分は無い）。`IosClipboardManager` を main 以外で手放しても止まらない（直さないと、Swift 6 で組んだ `IosLibrary` では止まった） |
| 0g | `IosLibrary` の framework の bundle id を `com.jonghyunkim.nativetoolkit.IosLibrary` に変える（D-12）。サンプルのアプリとテストのターゲットの bundle id は変えない（7 章の更新のテストで、2.0.0 のサンプルが 1.x のサンプルを上書きするため）。`IosLibraryCApi` の bundle id は 2b で作るときに付ける。**0e〜0g の後に全件を両方の環境で流し、0d の基準と同じ結果になることを確かめる**（7 章の区切り）。**完了（2026-10-31）**。シミュレーター（iPhone 17 / 26.2）の全件は 320 件成功・意図した skip 1 件で、0d の基準との差は 0e・0f で足した単体テスト 25 件だけ（基準を取り直した）。実機（iPhone XS / 18.7.2）は区分の無いもの・`systemui`・`sharesheet` の 60 件がすべて通り、0d の 19 件は同じ結果で、基準を 60 件に広げた。途中で見つけて直した UI テストの不備（S5 の iOS 18 の見出し、N5 の画像付きのバナー）と、端末の状態による失敗（古い同名のアプリ、集中モードのバッジの非表示、予定の睡眠の集中モード、N4 の起動の一時的な失敗）は作業の記録の 10・11 章 | framework の bundle id が変わる（2.0.0） |
| 1a | スパイク（8.2）。結果で D-4・D-7・D-9・D-10・D-11・D-13・D-16・D-18 を確かめ、C ABI の設計書の第 1 部（スレッド・寿命・通知の delegate・`release` の状態機械）を書く。**本物の Unity のビルド（6000.4.2f1 の Xcode プロジェクト、release ビルド）に雛形の C ABI を入れて、実機で呼ぶ。コールドスタートのタップと、Unity の通知パッケージとの共存も確かめる**（Android で smoke だけで確かめて申し送りを誤った反省。知見 1 章）。今の `unity-native-plugin` のビルドの処理は `unity-ios-native-toolkit-` を必須にし、前方一致で capi を選ぶので、1a では書き出した Xcode プロジェクトに手で入れる（Unity と同じく UnityFramework にリンクし、アプリに Embed & Sign する。`CodeSignOnCopy` を付ける） | 無し |
| 1b | Swift の API を補完する（4 章）。1.2 のロジックを `IosLibrary` へ移し、イベントの口、delegate を入れる口と転送、エラーの直し、プライバシーマニフェスト、ログの規則を入れる。1.4 の不備を直す。新しい API を使う画面をサンプルに足す | 1.4 の不備の直し（`registerCategory` の完了など）。通知の delegate を転送する形にする。エラーの case が変わる。それ以外の、ネイティブの利用者から見た動作は変えない |
| 2a | `check_c_abi_contract_ios.py`、`check_manual_c_examples_ios.py` を足す。`common_header_problems` を N 個の OS に直す。照合の対象に、イベントと完了のコールバック（6 章の振る舞いの集合）を入れる。照合の自己テストで、規則を 1 つずつ壊すと落ちることを確かめる | 無し |
| 2b | `IosLibraryCApi` を作り、C ABI を実装する。C ABI のテスト（`IosLibraryCApiTests`）と smoke（`IosLibraryCApiSmoke`）、`check_ios_dist.py`（7.3）。ビルドスクリプトに capi の xcframework と `include/` を足し、署名の扱い（D-18）を入れる。**完了の条件に 2a の機械照合を入れる**。**2b の終わりにリリース版を決めて `dist/<リリース版>` を作る**（Android が 2c の前に `dist/1.13.0` を作ったのと同じ。2c はこの dist で検証する）。**dist を置く前に、`unity-native-plugin` に下の 3 つを頼み、済んだことを確かめる**。dist にはいつも全 OS の成果物をそろえる（Android の dist/1.13.0 と同じ） | C ABI が増える（新しい配布物） |
| 2c | `unity-native-plugin`（別リポジトリ）の iOS を C ABI に移す: P/Invoke、JSON の層の削除、通知の delegate を起動の終わりまでに入れる `.mm`（`AppDelegateListener` / `kUnityWillFinishLaunchingWithOptions` など。1a で、Unity の通知パッケージより必ず後に入る形も比べる。入れるかどうかを利用者が選べる設定を持つ。通知を使わないアプリの delegate を奪わないため）、4 機能を一度に移す（D-20）、EditMode / PlayMode / 実機のテスト。こちらは対応表と申し送りを出し、書き換えは向こうで行う。2c の成功をリリースの条件にする（Android と同じ） | Unity が C ABI を呼ぶ |
| 3 | `UnityIosPlugin` を削除する。ビルドスクリプト、`generate_docc.sh`、`publish_docs.sh`、`scripts/check_design_consistency.py`、`scripts/README.md`、README、`agent-rules/coding-rules/{ios,common}.md`、`agent-rules/workflows/` から外す | `unity-ios-native-toolkit-*.xcframework` が無くなる（D-2） |
| 4 | ドキュメント: マニュアルの iOS の章に C ABI の節を足す（3 言語）。2.0.0 の移行ガイド（ブリッジの廃止、Swift 6 の注釈、エラーの case、通知の delegate を入れる関数と転送、bundle id、プライバシーマニフェスト）、言語ごとの導入の手順を書く。C ABI の Doxygen と、DocC の `IosLibrary` を合わせる。見出しのアンカーのずれ（知見 4 章）を防ぐ見出しの付け方を決める。マニュアルの版は 2b で決めたリリース版にする | - |

**2b の前に `unity-native-plugin` に頼むこと**（レビュー v1 の A-4。Windows・Android で、新しい dist を置いた時点で向こうのビルドが壊れた反省）:

1. iOS と macOS の xcframework を `VERSION.txt` で完全なファイル名に固定する（Windows・Android は固定済み）
2. `PreBuildProcessor`・`PostBuildProcessor`・`IosFrameworkPatcher` の 3 か所の探索を完全一致にする（`ios-native-toolkit-` の前方一致は `ios-native-toolkit-capi-` にも当たる）
3. `PostBuildProcessor` の development ビルドで、`-debug` が無ければ release の xcframework を使う（`PreBuildProcessor` と同じ）

**順番の理由**:

- 0e〜0g は、0d の基準と同じ UI テストが通ることで、動作が変わっていないことを確かめる。分けるのは、差が出たときに原因を切り分けるため（Android の 0e〜0h と同じ）
- 1a を 1b の前に置くのは、1b で足す Swift の API の形が C ABI の要求で決まるため
- 1b を 2b の前に置くのは、逆にすると C ABI の受け口がブリッジの中のロジックに依存するか、同じロジックをもう 1 つ書くことになるため
- 2a を 2b の前に置くのは、C ABI の完了を機械照合で判定するため
- 段階の番号は依存の順ではない。2c と 3 はどちらも 2b の後で、互いに依存しない。リリースは 2c・3・4 のすべてに依存する
- 3 は、Android と同じく 2c を待たずに進めてよい。`unity-native-plugin` が使うのは `dist/1.13.0/ios` の出し済みの xcframework で、リポジトリからブリッジを消しても影響しない。戻り先はタグ `1.13.0` と `dist/1.13.0` で、2.0.0 は 2c が成功するまで出さない（D-2）。Android も同じ順で問題なく進んだ（知見 1 章）。レビュー v1 で Codex は「2c の前に消してはいけない」と指摘したが、この理由で採らなかった

**2.0.0 を出す条件と戻り先**: 9 章の DoD がすべて満たされ、`unity-native-plugin` が `dist/<リリース版>` の xcframework で通しの検証を通したこと。`unity-native-plugin` は native-toolkit のリリースの後に自分の版を出す（Android の 1.13.0 と同じ順）。2.0.0 に問題が出たときの戻り先は、`dist/1.13.0/ios`（1.3.0）とタグ `1.13.0`。

### 5.1 設計書

この README は企画書の役割を持つ。設計書は公開 API を決める段階とテストの段階だけに書く。

| 設計書 | 書く時期 | 書くこと |
|---|---|---|
| UI テスト（**決定**: `designs/2026-10-18-ios-c-abi-ui-test-design.md`。別モデル 2 者のレビューを 5 回通し、v5 で打ち切って利用者が決めた。2026-10-18） | 0a の後、0b の前 | 機能ごとのテストケースの一覧と、確かめる内容。XCUITest で扱う項目と人が確かめる項目の分担（0a の結果に基づく）。私物の実機を守る仕組み（3 本柱: ランナーが選ぶ、宣言の正しさの照合、毎回の利用者の許可） |
| C ABI 第 1 部 | 1a の後、1b の前 | 利用者の前提（3.1）、スレッド、寿命、`release` の状態機械（受け付けた / 拒んだ / 取り消した / 終わった、と失敗の経路を最初から表に入れる。知見 1 章）、通知の delegate とイベントの保ち方（D-7 の項目）、前面の扱い、例外、D-4・D-7・D-10・D-11・D-13 の決定 |
| Swift の API の補完 | C ABI の第 1 部の後、1b の前 | ネイティブの利用者に公開する Swift の API が変わる。**今のブリッジの約束が新しい API のどこで守られるかの対応表**と、エラーの case の対応表を含める |
| C ABI 第 2 部 | 1b の後、2b の前 | 全関数の一覧、**今のブリッジの 43 関数と 6 章の振る舞いの集合から新しい関数への対応表**（System API → Repository → UseCase → Manager → Swift の受け口 → C の入口の各行に、actor、コールバックの回数、取り消し、寿命、エラーの対応）、エラーの表、付録 A のヘッダー。章番号は Windows・Android と同じにする（照合が見出しで読むため） |

スパイク（0a、1a）の結果は設計書にせず `results/` に記録する。段階 0d〜0g・2a・2c・3・4 は設計書を書かない（2c は対応表と申し送りを渡す）。公開 API の 3 本（C ABI の 2 部と Swift の API）は、これまでと同じく別のモデルにレビューしてもらってから着手する。

**決めたら、この README の表（8.1 の D-n、5 章、9 章）をその場で直す**。Android では、設計書で決めた後も README の表が「設計で決める」のまま古くなり、リリースの直前に見つかった（知見 4 章）。

置き場所:

```
artifact/topics/ios-c-abi/
  README.md                                          # この文書
  designs/
    YYYY-MM-DD-ios-c-abi-ui-test-design.md           # 段階 0
    YYYY-MM-DD-ios-c-abi-c-abi-design.md             # 1a の後（第 1 部）
    YYYY-MM-DD-ios-c-abi-swift-api-design.md         # 1b の前
    YYYY-MM-DD-ios-c-abi-c-abi-design-part2.md       # 2b の前
  reviews/
  results/
    2026-10-18-ios-c-abi-android-lessons.md          # Android から引き継ぐ知見
```

### 5.2 段階ごとに壊れる場所

| 場所 | 内容 | 影響する段階 |
|---|---|---|
| `scripts/build_ios_library_xcframework.sh` | `IosLibrary` と `UnityIosPlugin` を作り、release で pbxproj の版を書き換える。署名の設定を渡していない。capi の xcframework と `include/` は作らない | 0e（ブリッジを外す）・2b（capi と署名の扱いを足す）・3 |
| `ios/generate_docc.sh`、`scripts/publish_docs.sh` | `UnityIosPlugin` の DocC を作る。C のヘッダーの Doxygen は iOS に無い | 0e・3・4 |
| `agent-rules/workflows/release/workflow.md` | iOS の配置の手順は無く、dist に全 OS がそろっているかを確かめるだけ。capi とヘッダーの確認が加わる | 2b |
| `agent-rules/coding-rules/{ios,common}.md`、`scripts/check_design_consistency.py`、`scripts/README.md`、`agent-rules/workflows/`（write-manual、implement-sample-app など） | ブリッジ（`UnityIosPlugin`）を参照している。`ios.md` にログの例外が無い。`common.md` の UI テストの「自動化しないもの」（7.2） | 1b（ログの規則）・3 |
| `scripts/c_abi_contract_common.py` の `common_header_problems` | Windows と Android の 2 つを決め打ちしている | 2a |
| `IosLibrary` の公開 API | 0e（`@Sendable`）、0f（宣言の変更は無かった。`swift-module-flags` だけ）、0g（bundle id）、1b（Dialog の結果の型、イベントの口、エラーの case）で変わる。サンプルが追従する。ブリッジは 0e で外す（D-22） | 0e・0f・0g・1b |
| `unity-native-plugin` の `PreBuildProcessor` | iOS と macOS の xcframework を dist の最新版から選ぶ（`VERSION.txt` が無い）。`ios-native-toolkit-` の前方一致（`:477,704`）で capi を選ぶ | 2b で dist を置く前（向こうに固定を頼む） |
| `unity-native-plugin` の `PostBuildProcessor`・`IosFrameworkPatcher` | 同じ前方一致（`PostBuildProcessor.cs:48,225`、`Tools/iOS/IosFrameworkPatcher.cs:40,130`）。development ビルドで `-debug` が無いと `LogError` を出し、ビルドは止めずに埋め込まない（`PostBuildProcessor.cs:42-53,258-262`） | 2b の前（向こうに直しを頼む）・2c |
| `unity-native-plugin` の iOS のテスト | EditMode 212 件（Clipboard と Share だけ）のうち、JSON の組み立てと解析のテスト 126 件は C ABI では意味を失う。作り直しになる。PlayMode は 36 件（Clipboard 31、Share 5。Editor で動き、ネイティブは呼ばない）。Dialog と Notification のテストは 0 件 | 2c |
| マニュアル（`manual/<版>/*.md` の iOS の章） | C ABI の節を足すと、同じページの Windows・Android の `### C ABI` のアンカーがずれる（`verify_manual.sh` は検出しない） | 4 |

## 6. 公開面の規模

今のブリッジの公開面（調査の結果。数え方は第 2 部で確定する）:

| 機能 | C の関数 | うち操作・問い合わせ | 制御・登録 | 入力 | コールバックの型 |
|---|---|---|---|---|---|
| Clipboard | 15 | 12 | 3（読み込みの取り消し、監視の開始と停止） | 13 関数が JSON | 3 |
| Dialog | 6 | 6 | 0 | 位置引数 | 6 |
| Notification | 21 | 18 | 3（`notificationSetup`、アクションとテキスト入力の受け手の登録） | JSON 3 種と位置引数 | 6 |
| Share | 1 | 1 | 0 | JSON 1 種 | 1 |
| 計 | 43 | 37 | 6 | | 16 |

Android と同じく、C ABI が置き換えるのは操作だけでなく、**次の振る舞いの集合**である。これを C ABI の設計書 第 2 部の対応表と 2a の機械照合の対象にする（ID は Android と同じく BH / EV / RG / PR を付ける）。

| 種類 | 中身 |
|---|---|
| 操作・問い合わせ | 37（上の表）。戻り値の無い Notification の操作（`cancel*`、`remove*`、`openNotificationSettings`、`removeCategory`）を、完了とエラーを返す形にするかは第 2 部で決める |
| 操作の完了 | Clipboard / Notification / Share の操作の結果、Dialog の 6 種の結果 |
| 自発のイベント | Clipboard の変更、通知のアクション、通知のテキスト入力のアクション |
| 登録と解除 | 上のイベントの受け手の登録（今は解除が無い）、Clipboard の監視の開始と停止、`notificationSetup`（D-7 の、起動の終わりまでに delegate を入れる関数に置き換わる） |
| 追加 | 受け手の解除、起動のきっかけになった通知の取得（D-7） |

`IosLibrary` にあるがブリッジが公開していないものは、Android の D-5 と同じく 2.0.0 の C ABI に入れない。後から関数を足せば互換を保てる。Windows は 47 の操作から 105 の関数、Android は 155 の関数になった（ハンドルの読み取り関数とビルダーで増える）。

## 7. 検証方法

| 層 | 手段 | 守るもの |
|---|---|---|
| Swift の単体テスト | `IosLibraryTests`（今 186 件。`@Test` の数で、`arguments:` の展開前） | ライブラリの内部 |
| C ABI のテスト | `IosLibraryCApiTests`: C の関数を XCTest から呼ぶ。サニタイザーでも流す（7.4） | NULL と不正な入力の拒否、`struct_size`、UTF-8（対になっていないサロゲート、U+0000）、構造体の `sizeof` / `offsetof`。**全コールバックの型について、main で来ること、入口の中で呼ばれないこと、`release` がちょうど 1 回であること、入口で拒んだときは戻る前に呼ばれること、取り消しと再入**。main を止めた状態で、delegate を入れる関数（同期の例外。D-6）のほかの全関数が待たずに戻ること。`IosLibraryCApi` の Objective-C のクラスがすべて決めた接頭辞を持つこと（`objc_copyClassList` と `class_getImageName` で挙げる。D-11） |
| ヘッダー | C99・C11・C++・Objective-C でヘッダーだけをコンパイルする（`-Wall -Wextra -Werror`）。2a の照合 | 公開ヘッダーの形（3.3） |
| smoke | `IosLibraryCApiSmoke`: dist の 2 つの xcframework だけを使う C / Objective-C のアプリ。Swift のコードを持たない。Xcode 26.3 と、利用者の下限の Xcode 26.0 の両方で組む（D-16） | 配布物だけで組めて動くこと。Swift の実行環境を足さずに動くこと |
| 配布物の照合 | `check_ios_dist.py`（7.3） | 公開シンボル、依存、署名、マニフェスト、版 |
| 本物のホスト | Unity 6000.4.2f1 の書き出した Xcode プロジェクト（release ビルド）に入れて実機で呼ぶ（1a で雛形、2c で本番）。コールドスタートのタップと、Unity の通知パッケージとの共存も確かめる | Unity の組み込み方（UnityFramework へのリンク、埋め込み、`__Internal`、起動の終わりまでの delegate）で動くこと |
| サンプルの UI テスト | `IosLibraryExampleUITests`（99 件。段階 0c で全機能に広げ、雛形の 3 件を消した。もとは 25 件: Clipboard 22 件、雛形 3 件。UI テストの設計書） | 0e〜0g と 1b の前後で、ネイティブの利用者から見た動作が変わらないこと |
| 更新のテスト | 1.13.0 のサンプル（`IosLibrary` 1.3.0）で通知を予約し、category を登録し、通知を表示しておく → 2.0.0 のサンプルを上から入れる → 予約の一覧・取り消し・発火・タップ・アクションを確かめる | 1.x が OS に保存したもの（8.6）が 2.0.0 で壊れないこと |
| Unity | `unity-native-plugin` の iOS のテスト（作り直す）と実機 | Unity から C ABI を通した動作。別リポジトリで行う（段階 2c） |

件数は、ランナーが報告する展開後の件数で記録する（`test_ios.sh` の基準も同じ）。新しく足すテストは、守る対象を壊すと落ちることを確かめる（`common.md` の「検査の書き方」、知見 4 章）。

**全体の実行の時期**: Android（1 回約 65 分）と同じく、各段を直した直後は、ビルドと単体テスト、直した所に関係するテストだけを流す。全体を流して 0d の基準と比べるのは区切り（0g の後と 1b の後）とする。各段は別のコミットにするので、区切りで落ちたら段ごとに遡って原因を探す。iOS の全体の実行（シミュレーターで単体テストと UI テストの全件）は約 94 分かかった（2026-10-24、0d の基準を取った実行。Clipboard の既存の 22 件が約 52 分）。

### 7.1 サンプルの UI テストで守れる範囲

Android と同じく、サンプルはブリッジを通らず `IosLibrary` を直接呼んでいる。サンプルの UI テストで守れるのは、ネイティブの利用者から見た動作だけである。Unity から見た動作は前後で比べない（ブリッジは 0e でビルドから外して段階 3 で消し、Unity は C ABI を呼ぶ形に書き換わる）。変わる振る舞いは、C ABI の設計書の対応表に書く。サンプルは段階 2 以降も Swift の API だけを使い、C ABI は使わない。

### 7.2 XCUITest と人の確認の使い分け

`common.md` の UI 自動テストの規則は、OS のシェルの UI・システム設定・権限の初回の同意を「自動化しないもの」にしている。Android の段階 0a は、スパイクで確かめたうえで通知のシェードと権限のダイアログを自動化した。iOS も、**段階 0a で確かめて安定して扱えた項目だけを自動化し、`common.md` の例外として理由を 0a の結果に書く**（例外にした項目の一覧は UI テストの設計書の 2.1）。扱えない項目は、Windows・Android と同じく **computer use（Claude のデスクトップアプリ）で画面を見て確かめ**、手順書を用意する（判定があいまいなら失敗とする。2026-10-18、利用者の確認）。シミュレーターは Simulator.app のウィンドウを見る。実機は Mac の「iPhone ミラーリング」で画面を見るので、私物の画面が写る。実機の項目は 1 回ごとに利用者の許可を得てから行う。通知の音は、Android と同じく対象外にする（どの手段でも確かめられない。`sound` の既定値を単体テストで確かめる）。画像の中身は、Android と同じく自動化せず computer use で見る。

システムの UI は OS の版で見た目と構造が変わるので、UI テストは版を固定した 2 つの環境で流す（D-21）。

| 環境 | 機種と版 | 使い道 |
|---|---|---|
| 実機 | iPhone XS、iOS 18.7.2（ペアリング済み。今はつながっていない） | 最小 iOS（18）の基準。iOS 26 に上げられない機種なので、18 の実機はこれで固定できる。実機でしか確かめられない項目（通知の配信、権限の移り変わり、バックグラウンドや終了した状態での配信）は、シミュレーターの結果と分けて記録する |
| シミュレーター | iOS 26.2 のランタイム（機種は 0a で決める） | 今の iOS の基準 |

**実機で UI テストを流すときの運用**（2026-10-18、利用者と決めた）: XCUITest は端末のロックが外れている間しか動かない（始めるときにロックされていると起動できず、途中で自動ロックがかかると以降の操作がすべて失敗する。テストのコードからパスコードのロックは外せない）。そのため、実機で流す間は、利用者が自分で「設定 → 画面表示と明るさ → 自動ロック」を「なし」にし、電源につないでおく。私物の端末の設定なので、こちらからは変えない。流す前に知らせ、終わったら戻してもらう。

iOS 26 の実機は無い。通知の配信やシステムのシートのうち、シミュレーターで再現しないもの（0a で確かめる）は、iOS 26 では確かめられないと結果に書く。実機がつながらない間は、iOS 18.3 のシミュレーターで代わりに流せるが、基準にはしない。

### 7.3 配布物の照合（`check_ios_dist.py`）

Android の `check_android_dist.py` に当たる。2b で作り、リリースの前に流す。

| 項目 | 確かめ方 |
|---|---|
| 公開シンボル | 各スライスの `nm -gU` の `_ntk_*` が第 2 部の関数の一覧と一致し、ほかの外部シンボルを出していない |
| capi が Swift の API を出さない | capi の `Headers/` に `-Swift.h` が無く、`Modules/` に swiftmodule / swiftinterface が無い（D-10・D-11。実行時の metadata は照らさない。クラス名の接頭辞は 7 章の C ABI のテストで照らす） |
| 依存 | `otool -L`: capi は `@rpath/IosLibrary.framework` と OS の framework と `/usr/lib/swift/*` だけ。`@rpath/libswift*` に依存しない（Swift を持たないアプリは Swift の dylib を埋め込まないので） |
| 終わるときの処理 | `__cxa_atexit` などを import していない（知見 1 章） |
| install name | `LC_ID_DYLIB` が `@rpath/<名前>.framework/<名前>` |
| 版と最小 iOS | `MinimumOSVersion` が 18.0、`CFBundleShortVersionString` が 2.0.0、bundle id が D-12 のとおり |
| プライバシーマニフェスト | `IosLibrary` の両方のスライスに `PrivacyInfo.xcprivacy` があり、`plutil -lint` が通り、宣言した理由がソースで使っている API と一致する |
| 署名 | D-18 のとおり。`ios-arm64` のスライスは署名が無い。シミュレーターのスライスは、リンカーが付ける ad-hoc の署名（`linker-signed`）だけを許し、Authority と TeamIdentifier が無い（シミュレーターの arm64 はリンカーが必ず署名するので、署名の無い状態にはできない） |
| ヘッダー | `include/NativeToolkitC/` と capi の `Headers/NativeToolkitC/` が同じ |
| スライス | `ios-arm64` と `ios-arm64_x86_64-simulator` |

### 7.4 スライスとサニタイザーで確かめられる範囲

| スライス | 環境 | 確かめられること |
|---|---|---|
| `ios-arm64` | 実機（iPhone XS、iOS 18.7.2） | C ABI のテスト（ASan）、UI テスト、smoke、Unity |
| `ios-arm64_x86_64-simulator` の arm64 | シミュレーター（iOS 26.2 / 18.3、Apple Silicon の Mac） | C ABI のテスト（ASan、TSan。同時には使えないので別に流す）、UI テスト、smoke |
| `ios-arm64_x86_64-simulator` の x86_64 | iOS 18.3 のシミュレーターで Rosetta を使って動かす。iOS 26.2 のランタイムは x86_64 のアプリを受け付けない（0a の結果 3.9） | 組めること、公開シンボル、smoke のリンクと、iOS 18.3 での smoke の実行 |

TSan が実機で動かないことは、Xcode の文書で確かめる（未確認）。

## 8. 未決事項

### 8.1 決めること

**決定（2026-10-18、利用者）: D-1〜D-22 はすべて下の推奨のとおり**。D-1（iOS だけ）、D-12（bundle id だけを変える）、D-14（Swift 6 への移行を統合する）、D-18（配る framework に署名しない）は個別に尋ねて推奨を選んでもらい、残りの 18 個も推奨のとおりとした。レビュー（v1〜v3）で区分 A が 0 になった後に決めた。

| ID | 決めること | 選択肢 | 推奨（すべて決定） |
|---|---|---|---|
| D-1 | 範囲 | A: iOS だけ / B: iOS と macOS を一緒に | **A**（利用者の依頼は iOS）。Android の D-1 は「iOS と macOS は `@_cdecl` でほぼ同じ形になるので、まとめて行える」と書いたが、調べると、コードは共有しておらず（同じパスのファイルで一致する行は約 26%）、C の関数名も 43 と 44 のうち 14 しか同じでなく、エラーの型も違う（macOS の Clipboard は `Int`、iOS は文字列）。まとめても作業は減らず、段階とテストの環境が倍になる。C の入口の土台（`Common/`）は macOS で写して使える形にしておく |
| D-2 | 破壊的変更の扱い | A: C ABI を足すのと同じリリースで `UnityIosPlugin` を消す / B: 1 リリースは両方を配る | **A**（Windows の D-4、Android の D-2 と同じ）。2 つの公開面を並行して保守しない。古い xcframework は `dist/1.13.0/ios` に残る。**2c が終わらなければ 2.0.0 のリリースを待つ** |
| D-3 | OS をまたいだ C ABI の形 | Android の D-3 | **Android の D-3 の A を引き継ぐ**（3.3） |
| D-4 | 初期化 | A: 一般の初期化の関数は作らない。通知の機能（イベントと、前面にいるときの表示）を使うときだけ、ホストのネイティブのコードが起動の終わりまでに `ntk_notification_install`（仮）を呼ぶ / B: `ntk_ios_init` をいつも呼んでもらう / C: `+load` や constructor で自動に入れる | **A**。iOS には JNI も Context も無く、`UIApplication.shared` も `UNUserNotificationCenter` も main から遅れて取れる。ただし通知の delegate は起動の終わりまでに入れないとコールドスタートのタップを取りこぼし、前面にいるときの表示も delegate の `willPresent` で決まる。Unity の C# も Dart も起動の後に始まる（0 章）ので、C# や Dart から呼ぶのでは間に合わない。そのため、入れる関数はホストのネイティブのコード（Unity は `unity-native-plugin` の `.mm`、Flutter はプラグインのクラスが `register(with:)` か `addApplicationDelegate` で受ける起動の通知、C / Objective-C のアプリは `application(_:willFinishLaunchingWithOptions:)`）から呼ぶ契約にする。**入れる関数は D-6 の例外で、同期にする**: 呼べるのは main だけで、戻る前に proxy を強く持ち `UNUserNotificationCenter.delegate` を設定し終える。main 以外から呼ばれたら、積まずに同期のエラーを返す（`dispatch_sync` で main を待たない）。冪等にし、2 回目以降の呼び出しで前の delegate を proxy 自身で上書きしない。入れない C の利用者は、前面の間の通知が出なくなる（1.x の Unity はいつも `notificationSetup` を呼んでいたので、移行ガイドに書く）。B は通知を使わない利用者にも呼ばせることになる。C は Apple が main の前に走るコードを減らすよう勧めており、通知を使わないアプリの delegate も奪う。`NOT_INITIALIZED`（共通の番号の 2）は欠番にせず残し、通知の delegate を入れていないときのイベントの登録に返すかを第 1 部で決める |
| D-5 | C ABI に入れる範囲 | A: 今のブリッジの振る舞い（6 章の集合）と、受け手の解除・起動の通知の取得 / B: `IosLibrary` の全機能 | **A**（Android の D-5 と同じ）。`unity-native-plugin` が使っている範囲を先に固める。後から関数を足せば互換を保てる |
| D-6 | コールバックと `release` を呼ぶスレッド | A: 受け付けた後の完了・イベント・`release` は常に main キューへ非同期に（開始した関数の中では呼ばない。main から呼ばれても積む）。入口で受け付けなかったときの `release` は、呼び出し元のスレッドで関数が戻る前に呼ぶ / B: 呼び出し元のスレッド | **A**（Android の AC-4〜AC-6、Windows の E-12 と同じ）。UIKit は main で使う決まりで、1.3 のばらつきを 1 つにできる。Unity の C#（0 章で確かめた）も Flutter の Dart（3.29 から統合）も iOS の main で動くので、**どの関数も main を待たない**（`dispatch_sync`、セマフォでの待ち合わせを作らない）。`UNUserNotificationCenter` の完了はバックグラウンドで来うる（Apple の文書）ので、ライブラリが main に移す。iOS の `dispatch_async` は失敗しないので、Android の「main に積めない」経路は無くなるが、状態機械の表には「受け付けた / 拒んだ / 取り消した / 終わった」と「積んだ後の解除・再入」を最初から入れる。**例外は通知の delegate を入れる関数だけ**で、起動の処理から戻る前に delegate を設定し終える必要があるので、main からの同期の呼び出しにする（D-4） |
| D-7 | 通知の delegate | A: 今のまま無条件に上書きする / B: 起動の終わりまでに入れ、前の delegate を覚え、ライブラリの通知でないものは前の delegate に転送する / C: delegate を持たず、ホストの delegate から渡してもらう関数（`ntk_notification_handle_*`）を出す | **B**。A はホストの通知の機能を黙って壊す。C は Flutter（`FlutterAppDelegate` がプラグインへ配る）では自然だが、利用者がネイティブのコードを書く必要がある。B でも、ホストが後から無条件に上書きすると届かない（Unity の通知パッケージも `kUnityWillFinishLaunchingWithOptions` で上書きするので、同じ時期に入れるとどちらが後になるかはリンクの順で決まる）ので、マニュアルの契約にする。C を足すかは第 1 部で決める。**第 1 部で決めること**: 入れる関数の契約（D-4。冪等、後から delegate が差し替えられたときの検出とエラー）、proxy を誰が強く持つか（delegate は weak）、前の delegate を weak で持つか、3 つの任意のメソッド（`willPresent`、`didReceive`、`openSettingsFor`）すべての転送と `responds(to:)`、ライブラリの通知の見分け方（userInfo の印）、ライブラリの通知も前の delegate に見せるか、前の delegate が実装しないときの `willPresent` の表示の選択肢、`didReceive` の completionHandler をちょうど 1 回呼ぶこと（前の delegate が呼ばない場合を含む）、受け手が登録されるまでイベントを保つ件数、起動のきっかけの通知の取り方、1.x で予約した通知（印が無い）の扱い。1a で、本物の Unity の通知パッケージと、起動の順を入れ替えて確かめる。成り立たない組み合わせはマニュアルに書く |
| D-8 | Dialog の同期性 | A: 非同期（完了のコールバック）だけ | **A**（Android の D-8 と同じ）。Unity も Flutter も main で動くので、待つ形は必ず固まる。Windows とは名前と形が違う |
| D-9 | 配布物の形 | A: 2 つの dynamic の xcframework（`IosLibrary` と、それに依存する `IosLibraryCApi`）/ B: `IosLibrary` を中に含めた 1 つの static の framework / C: A と B の両方 | **A**。今の 1.x と同じ形で、Unity の `__Internal` で動くことは 1.x で分かっている。Flutter の推奨の経路（build hook の `DynamicLoadingBundled`）は動的を前提にし、Dart は静的なリンクにまだ対応していない（公式）。B は Unity・Godot・Rust には自然で、Sentry も静的を推奨しているが、Swift の API を使う利用者と C の利用者が同じアプリにいると `IosLibrary` が 2 つ入り、モジュール名とクラス名がぶつかる（0 章で試した）。プライバシーマニフェストも static の framework に入れる手順が要る。static が要る利用者が出たら C を足す（後からでも互換は壊れない）。1a で、dynamic のまま `ntk_*` だけを出せること、Unity と C のアプリで動くことを確かめる |
| D-10 | C の入口の書き方 | A: Swift の `@_cdecl` / B: Swift 6.3 の `@c`（Xcode 26.4 以降）/ C: C と Objective-C の `.m` が入口を持ち、モジュールの内側の Swift の受け口を呼ぶ | **決め直した（2026-10-24、利用者）: Objective-C は使わず、C と Swift だけで入口を作る**。理由: 運用で読む言語を減らす（`UnityIosPlugin` の `.m` も段階 3 で消えるので、iOS のライブラリから Objective-C が無くなる）。Objective-C を選んだ一番の理由（UIKit の例外を入口で止める）はレビュー v1 の A-8 で成り立たないと分かり、残りの理由（手書きのヘッダー、`_Thread_local`、`struct_size`）は C で足りる。macOS の C ABI にも同じ形を写せる。**第一の案は `@c @implementation`**（SE-0495、Swift 6.3）: 手で書いた C のヘッダーの関数を Swift で直接実装し、ヘッダーと実装の型の食い違いをコンパイラーが止める。関数ごとに C の入口と Swift の実装を 2 か所に書かずに済み（Android は 155 関数）、今の手書きのヘッダーの照合とも重なる、正式な機能なので、長期の運用に向く（2026-10-24、利用者と決めた）。Xcode 26.4 以降が要るので、採るなら D-16 を「ビルドは Xcode 26.4 以降」に決め直す（今の Mac の macOS 26.3 で入る）。**1a で確かめる条件**: (1) Xcode 26.4 以降で組んだ `IosLibrary` の swiftinterface を、Xcode 26.0〜26.3 で組む利用者が読めるか。読めないなら、Swift の API の利用者に Xcode 26.4 以降を求めてよいかを利用者に尋ねる。(2) `@convention(c)` のコールバックと `void* user_data`、`struct_size` のある構造体、不透明なハンドルを `@c @implementation` で書けるか。Swift で書きにくい所（スレッドごとの `ntk_last_system_code` など）は小さな C のファイルに残してよい。**条件が成り立たなければ**、Swift が起動のときに C の関数ポインタの表に登録する形（今の Xcode のままでよい）にする。内側の `@_cdecl` と非公開のヘッダーの形は、下線付きの機能に頼るので採らない。C ABI の利用者はヘッダーと `ntk_*` のシンボルしか見ないので、どの形でも利用者の側は変わらない。`agent-rules/coding-rules/ios.md` の Objective-C の部分は段階 3 で外す。**以下は決め直す前の推奨（C）の記録**: ヘッダーを手で書き、Windows・Android と同じ照合にかけられる。スレッドごとの `ntk_last_system_code` は C11 の `_Thread_local` で書け、`struct_size` とハンドルの表も C の方が素直。今の Xcode のまま始められる。A は正式でなく、宣言が生成ヘッダーの Objective-C の部分にしか出ない。B は Xcode 26.4 が要り、ビルドする側の Xcode を上げることになる（D-16）。Android の C++ の入口 → Kotlin の受け口 → `android_library` と同じ形になる。後で純粋な関数を `@c @implementation` に移しても、C のシンボルの名前と形を保てば C の利用者の ABI は変わらない（消えるのは `@_cdecl` が出す Swift の名前のシンボルで、照合で確かめる）。**例外**: 入口の `@try` は同期の部分しか守れず、main に積んだ後に UIKit が投げる例外は止められない。そのため、例外は「起こさない検査（popover の基点を必ず設定するなど）をし、起きたら落ちる」を基本にする（Android の `std::terminate` と同じ）。**Swift の受け口の隠し方**: framework のターゲットでは、`.m` から Swift を呼ぶには受け口を `public @objc` にする必要があり、swiftinterface と `-Swift.h` に出る。1a で、(a) capi の swiftmodule と `-Swift.h` を配らない、(b) Swift の側が C の関数ポインタの表に登録する、(c) 内側の `@_cdecl` と非公開のヘッダー、を比べて決める |
| D-11 | 公開シンボルと ABI | 公開の方法、スライス、実行時の名前 | **`EXPORTED_SYMBOLS_FILE` で `_ntk_*` だけを公開する**（Windows の `.def`、Android の version script に当たる）。要件を 3 つに分ける: (1) リンクできる公開の ABI は `ntk_*` だけ、(2) Objective-C の実行時のクラス名はほかとぶつからない（受け口のクラスに固有の接頭辞を付ける。付け方は D-10 の隠し方で変わり、`@objc(NTKCApi...)` は `@objc` のクラスを使う案のとき。`nm` では確かめられないので、`objc_copyClassList` で `IosLibraryCApi` のクラスを全部挙げて照らす）、(3) 内側の Swift の metadata が残るのは許す。スライスは `ios-arm64` と `ios-arm64_x86_64-simulator`（今と同じ）。iOS は 64 ビットだけなので、`struct_size` の規則とヘッダーの `/* sizeof N */` はそのまま成り立つ。C++ の静的オブジェクトを持つなら、Android と同じく `__cxa_atexit` を使わない形にする（知見 1 章） |
| D-12 | モジュール名・bundle id と 1.x との同居 | A: `IosLibrary` の名前も bundle id も今のまま / B: モジュール名を変え、1.x と同じアプリに入れられるようにする / C: モジュール名は保ち、bundle id を `com.jonghyunkim.nativetoolkit.*` にする | **C**。今の bundle id（`ios.library.IosLibrary`、`unity.ios.plugin.*`）は持っていない逆 DNS の名前空間で、Android の D-15 で `android.library` を変えたのと同じ理由がある。2.0.0 を逃すともう一度破壊的変更が要る。モジュール名を保てば、Swift の利用者の `import IosLibrary` は変わらない。ライブラリのコードは bundle id を使っていない（grep で 0 件）ので、1.x が保存したものに影響しない見込み（8.6 で確かめる）。案は `com.jonghyunkim.nativetoolkit.IosLibrary`（段階 0g）と `com.jonghyunkim.nativetoolkit.IosLibraryCApi`（2b で作るとき）。サンプルのアプリ（`com.jonghyunkim.ios.nativetoolkit.example`）とテストのターゲットは変えない（7 章の更新のテストで、2.0.0 のサンプルが 1.x のサンプルを上書きするため）。B はモジュール名がぶつかる危険（`IosLibrary` は一般的な名前）を除けるが、Swift の利用者の `import` がすべて変わる。モジュール名を変えない理由と、ぶつかる危険はマニュアルに書く。どの案でも、1.x の `IosLibrary.framework` と 2.0.0 は同じアプリに入れられない（同じ名前の framework を 2 つの版で埋め込めない）ので、`unity-native-plugin` は 4 機能を一度に移す（D-20） |
| D-13 | `ntk_last_system_code()` に入れる値 | A: 常に 0。詳細は `os_log` に出す / B: `NSError` の code を入れる | **A**（Android の D-13 と同じ）。`NSError` の code は domain が無いと意味が一意にならず、domain を返す関数を足すと OS ごとの差が増える。完了の `system_code` も 0。設計で、`os_log` の subsystem とカテゴリを決める |
| D-14 | Swift 6 への移行（`migration` の `swift6-migration`）との関係 | 統合する / 分ける | **iOS の分を統合する**（Android の D-14、Windows の D-1 と同じ）。公開 API を変える直し（handler の `@Sendable`、`shared` の `@MainActor`、Share の Port の isolation）は破壊的変更の 2.0.0 で入れるのが安い。ブリッジは 0e でビルドから外す（D-22）ので、`migration` の案 C をブリッジに一括で当てる作業は無くなる。C ABI の新しいコード（スレッドをまたぐ登録の表）は最初から Swift 6 / complete で書く。macOS は `migration` に残し、macOS の C ABI のときに同じ扱いにする。段階 0e・0f で行う。**例外（2026-10-24、利用者）: UI テストのターゲット（`IosLibraryExampleUITests`）は strict concurrency を minimal、言語モードを Swift 5 のまま残す**。complete では 316 件の警告が出て、全部がランナーの信頼する部分にあるため（`results/2026-10-24-ios-c-abi-stage0e-working-notes.md` の 4 章） |
| D-15 | 最小 iOS | A: 18.0 のまま / B: 下げる（コードは 16.0 まで下げられる） | **A**（Android の D-18 と同じ扱い）。下げると配布の契約、試験の OS、版による分岐が増える。18 なら `Synchronization` の `Mutex` / `Atomic` が使え、手元の実機も 18 で、Swift の実行環境を足さずに C のアプリにリンクできる（0 章）。Unity（13〜15）と Flutter（15）の利用者に 18 を求めるのは 1.x と同じ |
| D-16 | Xcode と Swift の版 | ビルドする側と、利用者に求める版 | **ビルドは Xcode 26.3（Swift 6.2.4、iOS 26.2 SDK）のまま。利用者に求めるのは Xcode 26.0 以上**。27 にしない（macOS 26.6 が要り、Unity の Build Automation に無く、Swift 6.4 の swiftinterface を Xcode 26 の利用者が読める保証が無い）。26.4 以降にすると `@c` が使えるが、D-10 で使わないので上げる理由にならない。**26.0 の利用者が読めることは確かめていない**ので、1a で Xcode 26.0 を入れ（Apple の表では macOS 15.6 以上で動くとあり、今の macOS 26.3 で動くかは未確認）、smoke と `import IosLibrary` を通す。通らなければ利用者に求める版を 26.3 に上げる。ビルドする Xcode を上げるときも、同じ確かめをしてから上げる（Android の Gradle 8.13 の consumer と同じ役。知見 1 章） |
| D-17 | 配布の経路 | A: `dist/` に xcframework とヘッダーを置く / B: A に加え、`dist/` に path の `binaryTarget` を持つ `Package.swift` を置く / C: SwiftPM の URL や CocoaPods で公開する | **A**。iOS の依存は OS の framework だけなので、Android の D-17（AAR だけでは androidx の依存が伝わらない）の問題は起きない。`IosLibraryCApi` が `IosLibrary` を要ることはマニュアルに書く。選択肢 C は別のトピックにする（CocoaPods の trunk は 2026-12-02 に読み取り専用になり、Flutter は 3.44 から SwiftPM が既定）。選択肢 B は段階 4 で、利用者の手順が短くなるなら足す |
| D-18 | プライバシーマニフェストと署名 | マニフェスト / 署名: A 配る framework に署名しない（archive で `CODE_SIGNING_ALLOWED=NO`。利用者がアプリに埋め込むときに自分の証明書で署名する）/ B 今のまま（実機のスライスは個人の Apple Development の証明書、シミュレーターは ad-hoc）/ C 配布用の証明書で xcframework に `codesign --timestamp` する | **マニフェストは入れる**（`IosLibrary` に `PrivacyInfo.xcprivacy`。FileTimestamp の理由は C617.1 の見込みで、アプリのコンテナの中のファイルであることと、アーカイブのプライバシーのレポートで 1b に確かめる。`IosLibraryCApi` は理由の申告が要る API を使わない見込みで、2b で確かめる）。Apple は、理由の申告が要る API を使う SDK はマニフェストを持つよう求めている。**署名は A**。B は配布物に個人の氏名と Team ID を載せ続け、証明書が切れると利用者のビルドが失敗しうる（Apple の文書）。署名が必須なのは「commonly used SDKs」の一覧に入る SDK だけで、このライブラリは入らない。1.x の xcframework そのものも署名していないので、Xcode 15 以降の署名者の検証で、利用者の側に変化は出ない見込み（1a で確かめる）。`check_ios_dist.py` で、実機のスライスに署名が無く、シミュレーターのスライスはリンカーの ad-hoc の署名だけであることを照らす（7.3）。1a で、利用者のアプリの Release のアーカイブの中で 2 つの framework がアプリの証明書で署名し直されていることを確かめる |
| D-19 | 版 | `IosLibrary` と C ABI の版 | **どちらも 2.0.0**。`UnityIosPlugin` を消すのは破壊的変更で、Swift 6 の注釈・エラーの case・bundle id で `IosLibrary` の公開 API も変わる。Windows・Android も 2.0.0 にした。製品のリリース版は 2b の終わりに決め、`dist/<リリース版>` を作る（2c がその dist で検証するため。5 章） |
| D-20 | `unity-native-plugin` の移し方 | A: 4 機能を一度に移す / B: 1 機能ずつ | **A**（D-12 の帰結）。1.x の `IosLibrary.framework` と 2.0.0 を同じアプリに入れられないため。2c の申し送りで、Android の包み（`user_data` の表、所有権ごと渡すハンドル、例外の try / catch、構造体の配置のテスト）をそのまま使えることと、通知の `.mm` が要ること（D-4）を示す |
| D-21 | 試験の環境 | 基準を取る環境 | **実機の iPhone XS（iOS 18.7.2）と、シミュレーターの iOS 26.2 の 2 つ**（Android の Pixel とエミュレータに当たる）。実機は 0d の前につなぐ必要がある。**実機は利用者の私物**なので、危ない操作（アプリの削除・再インストール、権限のリセット、設定の変更、再起動、クリップボードを書き換える・読むテスト、Share のシートから実在のアプリへ送りうる操作、通知センターや springboard を操作する UI テスト、写真・ファイルへの保存）は、1 回ごとに利用者の許可を得てから行う（2026-10-18、利用者の指示）。システムの自動更新を切るかも利用者に尋ねる。版が変わったら基準を取り直す。実機がつながらない間は iOS 18.3 のシミュレーターで代わりに流せるが、基準にはしない |
| D-22 | 段階 3 までのブリッジの扱い | A: 0e でワークスペースのビルドと `test_ios.sh` の基準から外し、ソースは 1b の参照のために段階 3 まで残す / B: 段階 3 まで、組めるようにする最小の直しを続ける | **A**。0e〜1b で `IosLibrary` の公開 API が何度も変わり、Swift 5 のままのブリッジを追従させると、直し方によってスレッドなどの動作が変わり、出荷もしない（Unity は `dist/1.13.0` を使う）。外す前（0d の後、0e の前）に、ブリッジのテスト（`UnityIosPluginTests` 83 件）を一度流し、結果を `results/` に保存する（`test_ios.sh` の基準には入れない）。1.x の直しが要るときは、タグ `1.13.0` から別のブランチで行う |

### 8.2 段階 1a で確かめること

| 項目 | 確かめ方 | 影響する決定 |
|---|---|---|
| dynamic の framework で、`EXPORTED_SYMBOLS_FILE` によって `ntk_*` だけを出せるか。Swift の受け口を隠す 3 つの案（D-10）のどれが成り立つか | 雛形の `IosLibraryCApi` を組み、`nm -gU`、`Headers/`、`Modules/` を確かめる | D-9・D-10・D-11 |
| Objective-C の実行時のクラス名に固有の接頭辞を付けられ、ほかの framework の同じ名前のクラスとぶつからないか | `objc_copyClassList` と `class_getImageName` で `IosLibraryCApi` のクラスを全部挙げる | D-11 |
| xcframework の `Headers/NativeToolkitC/*.h` と module map で、C / Objective-C / Swift の利用者がヘッダーを使えるか | 雛形の smoke | D-9 |
| 本物の Unity（6000.4.2f1）の Xcode プロジェクト（release ビルド）に 2 つの xcframework を入れ、`DllImport("__Internal")` で `ntk_version()` とコールバック付きの関数を呼べるか | 書き出した Xcode プロジェクトに手で入れ（5 章の 1a の行）、実機（iPhone XS）で動かす。`PostBuildProcessor` は development ビルドで埋め込まないので release で行う | D-9（知見 1 章の D-10 の反省） |
| Unity で、`.mm`（`AppDelegateListener` / `kUnityWillFinishLaunchingWithOptions`）から delegate を入れると、コールドスタートのタップと起動のきっかけの通知を受けられるか。Unity の通知パッケージ（`com.unity.mobile.notifications`）を入れたときに、どちらが後に入るか。こちらが必ず後に入る形（`didFinishLaunching` の受け手など）でも、コールドスタートのタップを受けられるか | 実機で、アプリを止めてから通知をタップする。リンクの順を入れ替える | D-4・D-7 |
| Unity の root の ViewController の上に `UIAlertController` や Share のシートを出したときに、ゲームが止まるか（知見 1 章の D-7） | 実機で、Dialog を出したままフレームが進むかを見る | 第 1 部の前面の扱い |
| `UNUserNotificationCenter` の delegate の転送。組み合わせの軸: メソッド 3 つ（`willPresent`、`didReceive`、`openSettingsFor`）× 前の delegate の振る舞い（実装しない、同期で completion、非同期で completion、2 回 completion、completion を呼ばない）× 通知の種類（ライブラリの通知、ホストの通知、印の無い 1.x の通知）× 時期（入れる前、入れた後、ホストが後から差し替え）× `responds(to:)` の真偽。completionHandler がちょうど 1 回か。delegate のメソッドが呼ばれるスレッド | 雛形の delegate と、前の delegate を持つ小さなアプリ。組み合わせの表は第 1 部に置き、1b のテストにする | D-7 |
| 入れる関数を main 以外から呼んだときに同期のエラーになり、main から呼んだときは戻る前に delegate が設定されているか | 雛形の関数 | D-4・D-6 |
| UIKit の例外（iPad で基点の無い popover など）が、main に積んだブロックの中で起きたときの振る舞い | 雛形で、main に積んだブロックの中で例外を起こす | D-10 |
| `_Thread_local` の `ntk_last_system_code` | 複数のスレッドから呼ぶ | D-13 |
| `NSString` の対になっていないサロゲートと U+0000 の `UTF8String` での振る舞い | クリップボードに置いて読む | 8.6 の UTF-8 |
| Xcode 26.0 で、2.0.0 の雛形の xcframework を使う smoke と `import IosLibrary` を組めるか | Xcode 26.0 を入れて組む | D-16 |
| 署名の無い framework の xcframework を、Xcode の署名者の検証で問題なく使えるか。利用者のアプリで Embed & Sign できるか。Release のアーカイブの `.app/Frameworks` の 2 つの framework が、アプリの証明書で署名し直されているか | 雛形の smoke と Unity。アーカイブに `codesign --verify --deep --strict` と Team ID の確認を流す。可能なら Organizer の Validate App も行う | D-18 |
| C ABI のテストを XCTest から ASan / TSan で流せるか。TSan が実機で動くか | 雛形のテスト | 7.4 |

### 8.3 ツールチェーンの版（D-14・D-15・D-16）

2026-10-18 に調べた。利用者が組めなくなる版は使わない、を基準にする。

**手元の環境**: Xcode 26.3（17C529）が 1 本だけ（`/Applications/Xcode26.3.app`）、Swift 6.2.4、iOS 26.2 SDK、macOS 26.3（25D125）。シミュレーターのランタイムは iOS 16.4 / 17.4 / 18.3 / 26.2。実機は iPhone XS（iOS 18.7.2）。今の 1.3.0 の配布物も Xcode 26.3 で作られている（`DTXcode` 2630、swiftinterface の `swiftc` は 6.2.4、`-swift-version 5`）。2.0.0 の配布物でも、`swiftc --version` と `DTXcodeBuild` を段階の結果に記録する。手元の Flutter は 3.7.0（fvm）で、`NativeCallable.listener` も build hook も無い。

**利用者の側の上限**:

| 利用者 | Xcode（Swift） | 最小 iOS | ネイティブの組み込み方 |
|---|---|---|---|
| App Store Connect（全員） | 26.0 以上が必須（2026-04-28 から） | 13 以上（2026-09-09 から） | - |
| Unity 6000.0 LTS | 15 以上を推奨 | 13 以上 | `DllImport("__Internal")`。プラグインは UnityFramework にリンクされる |
| Unity 6000.3 LTS / 6000.4 / 6000.5 | 16 以上を推奨 | 15 以上 | 同上 |
| Unity Build Automation | 最大 26.5.0、既定 26.3.0。27 は無い | - | - |
| Flutter stable 3.47.7 | 15 が必須、16 を推奨 | ひな形は 15.0 | `dart:ffi`。推奨は build hook の `DynamicLoadingBundled` |
| React Native（main） | 16.1 以上 | 15.1 以上 | 未確認 |
| Godot 4.7.2 | 未確認 | 既定 15.0 | GDExtension の xcframework（静的なら埋め込まず、dylib なら framework にして埋め込む） |

ここから、**利用者に求めてよいのは Xcode 26.0（Swift 6.2）まで**とする（26.0 で読めることは 1a で確かめる。D-16）。最小 iOS は、どの利用者も既定（13〜15）から 18 に上げる必要がある（1.x と同じ）。

Unity の iOS は、iOS 27 SDK で組むアプリに scene のライフサイクルを求める TN3187 に、6000.0.68f1・6000.3.8f1・6000.4.0b8・6000.5.0a3 以降で対応している。ライブラリは前面の scene から key window を探す（今も `connectedScenes` を使っている）ので、scene の有無の両方で動くことを 0a で確かめる。

**上げる版**:

| 対象 | 今 | 上げる先 | 段 | 理由・注意 |
|---|---|---|---|---|
| Xcode（ビルドする側） | 26.3 | 26.3 のまま | - | D-16 |
| Xcode（利用者の下限の確かめ） | - | 26.0 を入れる | 1a | D-16 |
| Swift の言語モード | 5.0 | 6 | 0f | D-14。ブリッジは 0e でビルドから外す（D-22）。**済み（0f）**。`IosLibrary`、`IosLibraryTests`、サンプル、`IosLibraryExampleTests`。`IosLibraryExampleUITests` は Swift 5（D-14 の例外） |
| `SWIFT_STRICT_CONCURRENCY` | 未設定（minimal） | complete | 0e | **済み（0e）**。プロジェクトの階層で固定。`IosLibraryExampleUITests` だけ minimal（D-14 の例外）。警告は 0e の前の 423 件（うち `IosLibrary` 104 件）から 0 件 |
| `SWIFT_DEFAULT_ACTOR_ISOLATION`、upcoming feature | 未設定 | 明示的に固定する | 0e | Xcode 26 の推奨設定で変わると、公開 API の意味が変わりうる。**済み（0e）**。`nonisolated`、`SWIFT_APPROACHABLE_CONCURRENCY=NO`、upcoming feature 18 個を `NO`（作業の記録 2.4）。0f で見直した。Swift 6 の 4 つのターゲットでは 13 個と `SWIFT_STRICT_CONCURRENCY` が効かないが、Swift 5 の UI テストのターゲットのために残した（0f の作業の記録 2.4） |
| 最小 iOS（framework、サンプル） | 18.0 | 18.0 のまま | - | D-15 |
| 最小 iOS（テストのターゲット） | 18.2 | 18.0 | 0e | 本体とのずれを直す。**済み（0e）** |
| `MACH_O_TYPE` | dynamic | dynamic のまま | - | D-9 |
| `BUILD_LIBRARY_FOR_DISTRIBUTION` | YES | YES（`IosLibrary`）。`IosLibraryCApi` は Swift の公開面を配らないので要否を 1a で決める | - | D-10 |
| 署名 | Automatic（実機は個人の証明書） | 配る framework は署名しない | 2b | D-18 |
| bundle id | `ios.library.*`、`unity.ios.plugin.*` | `com.jonghyunkim.nativetoolkit.*` | 0g | D-12 |
| `objectVersion` / `LastUpgradeCheck` | 77 / 1620（Xcode 16.2） | 77 / Xcode 26 の推奨設定を反映 | 0e | 変わる build setting の差分を全部記録する。**未反映**（作業の記録 2.3。推奨設定の一覧は Xcode の画面でしか見られないので、利用者が見て決める） |
| C の入口 | `.m` の `extern "C"` | C と Swift（`ntk_*`、手書きのヘッダー。Objective-C は使わない。形は 1a で決める） | 2b | D-10 |

出典: Xcode の対応表（https://developer.apple.com/support/xcode/ ）、App Store Connect の要件（https://developer.apple.com/news/upcoming-requirements/ ）、Unity の iOS の要件（https://docs.unity3d.com/6000.0/Documentation/Manual/ios-requirements-and-compatibility.html と 6000.3 / 6000.4 / 6000.5 の同じページ）、Unity Build Automation の Xcode（https://docs.unity.com/en-us/build-automation/reference/available-xcode-versions ）、Unity の UIScene の対応（https://discussions.unity.com/t/info-apple-update-your-editor-to-receive-uiscene-lifecycle-support/1709065 ）、TN3187（https://developer.apple.com/documentation/technotes/tn3187-migrating-to-the-uikit-scene-based-life-cycle ）、Flutter の対応（https://docs.flutter.dev/reference/supported-platforms ）。

### 8.4 決めないこと

- macOS の C ABI（D-1）。iOS の後に別のトピックにする
- SwiftPM の URL や CocoaPods での公開（D-17 の選択肢 C）。別のトピックにする
- static の framework の配布物（D-9 の選択肢 C）。要る利用者が出たら足す
- `IosLibrary` にあってブリッジに無い機能の C ABI（D-5 の B）。2.0.0 の後に関数を足す
- iOS の CI。Windows の段階 7 と同じく、別に行う
- App Extension からの利用
- Flutter・Rust・Godot・React Native での動作の確認。2.0.0 で確かめる利用者は Unity（1a と 2c）と smoke の C / Objective-C のアプリだけで、ほかはマニュアルに「確かめていない」と書く。手元の Flutter は 3.7.0 で、Dart が main で動く 3.29 より古く、`NativeCallable.listener` も無い。Flutter の delegate の共存（`FlutterAppDelegate`）も確かめない
- 機能ごとの配布物（`feature-split-distribution`）。全 OS の C ABI の後に決める。ただし C の入口とヘッダーは機能ごとに分けておく

### 8.5 出典（調査で使った公式の文書）

- Swift の `@c`（SE-0495）: https://github.com/swiftlang/swift-evolution/blob/main/proposals/0495-cdecl.md 、Swift 6.3 のリリース: https://swift.org/blog/swift-6.3-released/
- Objective-C の例外と Swift: https://developer.apple.com/documentation/swift/handling-cocoa-errors-in-swift
- XCFramework の作り方: https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle 、署名の検証: https://developer.apple.com/documentation/xcode/verifying-the-origin-of-your-xcframeworks
- 第三者の SDK の要件: https://developer.apple.com/support/third-party-SDK-requirements/ 、プライバシーマニフェスト: https://developer.apple.com/documentation/bundleresources/privacy-manifest-files 、理由の申告が要る API: https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api
- ビルドの設定（`EXPORTED_SYMBOLS_FILE`、`GENERATE_PRELINK_OBJECT_FILE`）: https://developer.apple.com/documentation/xcode/build-settings-reference
- 起動の時間（main の前に走るコード）: https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time
- UIKit の main スレッド: https://developer.apple.com/documentation/uikit 、`UNUserNotificationCenter`: https://developer.apple.com/documentation/usernotifications/unusernotificationcenter 、delegate（起動の終わりまでに設定する）: https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate
- `UIWindowScene.keyWindow`: https://developer.apple.com/documentation/uikit/uiwindowscene/keywindow 、起動のときの通知（scene）: https://developer.apple.com/documentation/uikit/uiscene/connectionoptions/notificationresponse
- Unity の iOS のネイティブのプラグイン: https://docs.unity3d.com/6/Documentation/Manual/ios-native-plugin-create.html 、コールバック: https://docs.unity3d.com/6000.3/Documentation/Manual/ios-native-plugin-call-back.html
- Unity の通知パッケージ（delegate の上書き）: `Unity-Technologies/com.unity.mobile.notifications` の `Runtime/iOS/Plugins/UnityNotificationLifeCycleManager.mm`
- Flutter の iOS の C の呼び出し: https://docs.flutter.dev/platform-integration/ios/c-interop 、ネイティブのコードの組み込み（build hook）: https://docs.flutter.dev/platform-integration/bind-native-code 、スレッドの統合: https://docs.flutter.dev/release/breaking-changes/macos-windows-merged-threads
- Dart の `NativeCallable.listener`: https://api.dart.dev/dart-ffi/NativeCallable/NativeCallable.listener.html 、`StaticLinking`: https://pub.dev/documentation/code_assets/latest/code_assets/StaticLinking-class.html
- Flutter の SwiftPM: https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-plugin-authors 、CocoaPods の trunk: https://blog.cocoapods.org/CocoaPods-Specs-Repo/
- Godot の iOS のプラグイン: https://docs.godotengine.org/en/stable/tutorials/platform/ios/ios_plugin.html

### 8.6 設計で決めること

決定（D-n）ではないが、設計書で必ず決める項目。

| 項目 | 設計書 |
|---|---|
| 前面の扱い: 前面の scene と key window の探し方、アプリが後ろにいるときのエラー、同時の要求（待たせるか断るか）、取り消し、バックグラウンドへの移り変わり、アクションシートと Share の iPad の基点（C ABI から矩形を渡すか） | C ABI 第 1 部 |
| `release` の状態機械（D-6）。受け付けた / 拒んだ / 取り消した / 終わった、と失敗の経路（入口での拒否、積んだ後の解除、コールバックの中での解除）を最初から表に入れる | C ABI 第 1 部 |
| 利用者のコールバックの例外と、Objective-C・UIKit の例外の扱い（D-10） | C ABI 第 1 部 |
| 通知の delegate（D-4・D-7 の「第 1 部で決めること」） | C ABI 第 1 部 |
| 文字列の変換: `NSString` は対になっていないサロゲートを持てる（ほかのアプリが置いたクリップボードなど）。出力で U+FFFD に置き換え、U+0000 も U+FFFD にする（AC-19 / E-16）方法 | C ABI 第 1 部 |
| Swift の受け口の隠し方（D-10）と、Objective-C の実行時のクラス名の接頭辞（D-11） | C ABI 第 1 部 |
| イベントを保つ件数・期限・順序・重複（4 章） | Swift の API |
| 1.x が OS に保存したもの（予約した通知の identifier と userInfo、登録した category、表示中の通知）が 2.0.0 でどう扱われるか。印の無い 1.x の通知のタップを、どの受け手に渡すか。bundle id の変更（D-12）が影響しないこと | Swift の API |
| エラーの case の直し方と、C ABI のエラーの番号への対応表 | Swift の API・C ABI 第 2 部 |
| ログの規則: 秘密の値（パスワード、入力欄、通知の返信、クリップボードの本文、通知と Share の内容）を伏せる。`print` を `os_log` にするか、Release で出すか。C のコードのログの規則。`agent-rules/coding-rules/ios.md` を直してから 1b に入る | Swift の API |
| プライバシーマニフェストの理由の申告の一覧（使っている API の棚卸し）と、アーカイブのプライバシーのレポートでの確かめ | Swift の API |
| 戻り値の無い Notification の操作を、完了とエラーを返す形にするか（6 章） | C ABI 第 2 部 |
| `unity-native-plugin` に渡す対応表の範囲: EditMode の JSON のテスト 126 件は意味を失うので、何を基準に作り直すか（実物を数えてから書く。知見 3 章） | C ABI 第 2 部 |
| マニュアルの見出しのアンカーが、ほかの OS の節とぶつからない付け方 | 段階 4 |

## 9. DoD

- [x] D-1 〜 D-22 を決める（2026-10-18。すべて推奨のとおり）
- [x] この README のレビューで区分 A が 0 になっている（3 回。`reviews/` の v1〜v3）
- [x] 段階 0a のスパイクで、XCUITest と人の確認の分担を確定する（`common.md` の例外にした項目は理由を記録している）（`results/2026-10-18-ios-c-abi-stage0a-spike-result.md`。シミュレーター 2 台と実機。分担は UI テストの設計書）
- [x] Clipboard / Notification / Share / Dialog のすべてにサンプルの UI テストがあり、通知からのコールドスタート（UI テストの設計書の N30〜N33）を含む（段階 0c）（`results/2026-10-24-ios-c-abi-stage0c-result.md`。99 件。シミュレーターで全件が通った。実機は区分の無い 19 件だけ）
- [x] `scripts/test_ios.sh` があり、今のコードの結果を 2 つの環境で基準として記録している（段階 0d）（`results/2026-10-24-ios-c-abi-stage0d-result.md`。シミュレーターは全件。**実機の基準は区分の無い 19 件だけ**）
- [x] `IosLibrary` とサンプルが Swift 6 の言語モードと strict concurrency complete で、警告が 0（段階 0e・0f）。公開 API の差分を記録している（`results/2026-10-25-ios-c-abi-stage0f-working-notes.md`。UI テストのターゲットは D-14 の例外で Swift 5 + minimal）
- [ ] 0e〜0g と 1b の前後で、サンプルの UI テストの結果が変わらない（変えたテストは理由を記録している）
- [ ] 段階 1a のスパイクで 8.2 を確かめる。本物の Unity の release ビルドで、雛形を実機で呼び、コールドスタートのタップを受けている
- [ ] UI テスト・C ABI（2 部）・Swift の API の設計書を書き、別のモデルのレビューを通す
- [ ] 1.2 のロジックがすべて `IosLibrary` にあり、ブリッジのテストのうち移すロジックに当たるものを書き直して通している（段階 1b）
- [ ] ログに秘密の値が出ない（`ios.md` に規則があり、テストで確かめる）
- [ ] `IosLibrary` にプライバシーマニフェストがあり、使っている理由の申告が要る API と一致する（アーカイブのプライバシーのレポートで確かめる）
- [ ] 通知の delegate が前の delegate に転送し、ホストの通知が壊れない。起動の終わりまでに入れる関数でコールドスタートのタップが届く（段階 1b のテストと 1a / 2c の Unity）
- [ ] 1.x（1.13.0 のサンプル）から 2.0.0 への更新のテストで、予約した通知・category・表示中の通知が壊れない
- [ ] `IosLibraryCApi` が 6 章の振る舞いの集合をすべて公開している（2a の機械照合）
- [ ] `check_ios_dist.py` の全項目（7.3）が通る。公開シンボルが `ntk_*` だけで、capi が Swift のモジュール・interface・ヘッダーを配らず、署名とマニフェストが D-18 のとおり
- [ ] 通知の delegate を入れる関数が、main から呼ぶと戻る前に delegate を設定し終え、main 以外からは同期のエラーを返す（D-4・D-6）
- [ ] smoke が dist の 2 つの xcframework だけで組めて、実機とシミュレーターで動く。Xcode 26.0 でも組める（D-16）
- [ ] 照合のスクリプト（`check_c_abi_contract_ios.py`、`check_manual_c_examples_ios.py`、`check_ios_dist.py`）が通り、Windows・Android の照合も通る。照合の自己テストが、規則を 1 つずつ壊すと落ちる
- [ ] C ABI のテストが 7.4 の組み合わせ（ASan は実機とシミュレーター、TSan はシミュレーター）で通る。足したテストは、守る対象を壊すと落ちることを確かめている
- [ ] `unity-native-plugin` が 2b で dist を置く前に、版の固定・完全一致の探索・development ビルドの埋め込みの 3 つを入れ、2c で C ABI を呼ぶ形に移り、iOS のテストと実機の確認を通している（別リポジトリ）
- [ ] `UnityIosPlugin` がリポジトリに残っていない（プロジェクト、スクリプト、README、ルール、`dist/` の新しい版）（段階 3）
- [ ] マニュアルの iOS の章に C ABI の節と 2.0.0 の移行ガイドがあり、3 言語で一致している（段階 4）

## 10. 関連

- `artifact/topics/android-c-abi/README.md`（手本。段階の分け方、D-n、5.2、7 章）と設計書 第 1 部・第 2 部（引き継ぐ規約と状態機械）、`results/2026-10-10-android-c-abi-stage2c-handoff.md`（Unity の包み）
- `artifact/topics/windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md`（規約の出典）
- `results/2026-10-18-ios-c-abi-android-lessons.md`（Android から引き継ぐ知見）
- `reviews/2026-10-18-ios-c-abi-plan-review-v1.md`（この README のレビュー）
- `artifact/topics/migration/README.md`（`swift6-migration` と Bridge callback actor-boundary の案 C。D-14）
- `artifact/topics/bridge-testing/README.md`（ブリッジの層のテストの穴。ブリッジを消すので、C ABI のテストで置き換える）
- `artifact/topics/memory-sanitizers/README.md`（iOS は ASan / TSan）
- `artifact/topics/feature-split-distribution/README.md`、`artifact/topics/feature-scoped-testing/README.md`（iOS は C ABI 化と合わせる）
- `agent-rules/coding-rules/ios.md`（ログの規則の例外を 1b の前に足す。段階 3 で、ブリッジの記述を `IosLibraryCApi` に書き換える）
- `agent-rules/coding-rules/common.md`（UI 自動テストの「自動化しないもの」。7.2）
