# macOS の汎用 C ABI: 企画

- 記録日: 2026-11-22
- 状態: 企画中（調査が済み、レビュー v1〜v3（`reviews/`）を反映し、v3 で区分 A が 0 になった。利用者の決定の前）。決定（D-n）は `2026-11-22-macos-c-abi-decisions.md`、DoD は `2026-11-22-macos-c-abi-dod.md`
- 分類: 横断課題（アーキテクチャ）。機能追加ではない
- 進め方: Windows（`windows-architecture`、1.12.0）、Android（`android-c-abi`、1.13.0）、iOS（`ios-c-abi`、1.14.0）と同じ汎用 C ABI を、1 OS ずつ作る。このトピックは最後の macOS の分
- 対象: `mac/MacLibrary`、`mac/UnityMacPlugin`（新しい C ABI のモジュールに置き換える）、`mac/MacLibraryExample`、`scripts/build_xcode26_library_xcframework.sh`（と前の版の `build_xcode16_library_xcframework.sh`）、`mac/generate_docc.sh`、`scripts/publish_docs.sh`、配布物 `mac-native-toolkit-*.xcframework` / `unity-mac-native-toolkit-*.xcframework`
- チケット: NTKIT-19（ブランチ `feature/NTKIT-19` の名前から。中身は未確認）
- 手本: `artifact/topics/ios-c-abi/`（直前に出荷した C ABI。同じ Apple の OS で、同じ Swift の作り方）。規約の出典は `artifact/topics/android-c-abi/` と `artifact/topics/windows-architecture/`
- 文書の形: `topic-document-size` の案に沿って、README には状態とリンクだけを置き、企画（この文書）・決定・DoD を分けた。章の番号は iOS の README に合わせた（照らしやすくするため）。決定の表と DoD はこの文書に写さない

## 0. 調べたこと

2026-11-22 に、観点の違う 4 つの調査を行った（読むだけ。ビルドと、私物に触れない単体テストだけを流した）。この文書の事実は、断りがない限りこれらから引いている。調査の全文は `results/` にある。

| 観点 | 調べたもの | 全文 |
|---|---|---|
| macOS の今の公開面 | `MacLibrary` と `UnityMacPlugin` の全公開関数、JSON の入力、コールバックとそのスレッド、テスト、サンプル、ビルドのスクリプト、`dist/1.14.0/mac` の実物（`file`、`lipo`、`otool -L`、`nm -gU`、`codesign`）、`unity-native-plugin`（別リポジトリ、読むだけ）の macOS の C# 側 | `results/2026-11-22-macos-c-abi-survey-a-surface.md` |
| iOS から引き継ぐもの | iOS の D-n・P1-n・S-P n・P2-n の振り分け、`IosLibraryCApi` と照合のスクリプトの共有、iOS の 1b の Swift の API が `MacLibrary` にあるか、iOS の手戻り、テストの基盤 | `results/2026-11-22-macos-c-abi-survey-b-ios-carryover.md`、知見は `results/2026-11-22-macos-c-abi-ios-lessons.md` |
| macOS で C ABI を作る前提 | `@c @implementation` の macOS での動き、埋め込みと署名（Hardened Runtime、Library Validation、公証）、Unity の macOS のプレイヤー、通知、貼り付け板のプライバシー、AppKit のスレッド、Flutter・Rust・Godot、プライバシーマニフェスト、Mac App Store と Developer ID。公式の文書を優先し、手元で試した（試作は scratchpad に置き、リポジトリには入れていない） | `results/2026-11-22-macos-c-abi-survey-c-prerequisites.md` |
| ツールチェーンとテストの基盤 | 手元の macOS・Xcode・Unity、pbxproj の設定、strict concurrency と Swift 6 の診断の数、単体テストの実行、ビルドのスクリプト、swiftinterface、DocC・マニュアル | `results/2026-11-22-macos-c-abi-survey-d-toolchain.md` |

試したことのうち、記録に残すもの:

- `@c @implementation` は macOS でも iOS と同じ書き方で使える。Xcode 26.6（Swift 6.3.3）で arm64・x86_64 の universal の dynamic framework を組み、`EXPORTED_SYMBOLS_FILE` で `_ntk_*` だけを出せた（`ntk_` で始まらない public の `@c` 関数と Swift の public の関数は出ない）。Xcode 26.3 の clang で組んだ C の `main` からリンクして呼べた（arm64 と Rosetta の x86_64）。Xcode 26.3（Swift 6.2.4）は `@c` を知らない（`unknown attribute 'c'`）
- macOS の framework は版付きの構成（`Versions/A`）なので、iOS と同じ `PUBLIC_HEADERS_FOLDER_PATH=.../Headers/NativeToolkitC` にすると最上位の `Headers` のリンクが作られず、自分の module map が解けずに止まった。ビルドの段でリンクを作ると通った
- Hardened Runtime を有効にしたアプリを ad-hoc（Sign to Run Locally）で署名すると、同じ ad-hoc で署名し直した framework でも Library Validation が「different Team IDs」で拒み、起動できない。Hardened Runtime を外すか `com.apple.security.cs.disable-library-validation` を付けると動く。署名しない（リンカーの ad-hoc の署名だけの）framework を入れて外側のアプリだけを署名しようとすると、`codesign` が止まる
- framework を `Contents/PlugIns` に置いて `dlopen` すると（Unity が `.bundle` を読む形を真似た）、C ABI の framework の rpath（`@executable_path/../Frameworks`、`@loader_path/../Frameworks`）では兄弟の Swift の framework を解けない。`@loader_path/../../..` を足すと読めた
- bundle の無いプロセス（コマンドラインの実行ファイル）で `UNUserNotificationCenter.current()` を呼ぶと `NSInternalInconsistencyException`（`bundleProxyForCurrentProcess is nil`）で落ちる。ad-hoc の `.app` では `getNotificationSettings` が動いた
- 貼り付け板: macOS 26.3 では `accessBehavior` は既定で `alwaysAllow`（2）で、読むと確認を出す仕組みは有効でない。開発者向けのプレビューの設定（`EnablePasteboardPrivacyDeveloperPreview`、試作のアプリの領域だけに入れて、試した後に消した）を入れると `default`（0）になる。中身の読み書きは名前付きの貼り付け板だけで行い、利用者の一般の貼り付け板は読んでいない
- Unity 6000.4.2f1 の `UnityPlayer.dylib` は UserNotifications をリンクしておらず、通知の delegate を入れない（ライブラリと奪い合わない）。Unity の公式の文書は、macOS のプラグインを `.bundle` か dylib として `DllImport("名前")` で呼ぶ形を書き、`.framework` の Standalone での扱いは書いていない。`__Internal` は、macOS では IL2CPP の C++ のソースのプラグインにだけ記載があり、dynamic の framework をリンクして `__Internal` で探す形は書かれていない（1a で測る）。1.x は「Create Xcode Project」で書き出したプロジェクトに framework をリンクし、`DllImport("__Internal")` で呼んでいる（Mono）
- `unity-native-plugin` の macOS の C# は `#if UNITY_STANDALONE_OSX && !UNITY_EDITOR` で、**エディターではネイティブを呼ばない**。エディターの中のドメインのリロードの問題は、今の形のままなら起きない
- strict concurrency を complete にすると（Swift 5、whole-module、clean build、Xcode 26.3）、警告は 3 つのスキームを合わせて 215 件（`MacLibrary` 165: Dialog 100、Notification 52、Share 13、Clipboard 0。`UnityMacPlugin` 7。テスト・サンプル・UI テストに 43）。Xcode 26.6 では 219 件。Swift 6 の言語モードでは `MacLibrary` が 8 件のエラーで止まる（`shared` の 3 件と `SharePickerPresenter` の 5 件）
- 単体テストは、私物（一般の貼り付け板と通知センター）に触れないと読んで確かめたものだけを流した: `MacLibraryTests` 308 件がすべて成功、`UnityMacPluginTests` の parser 3 つと雛形の 52 件がすべて成功（件数は `@Test` の宣言の数で、`arguments:` の展開前。展開後の数は 0d の基準で取る）。ただし `MacLibraryTests` にも、固定の待ちが外れると本物のメールの作成を開きうるテストがある（`SharePickerPresenterTests`。7.5）。`UnityMacClipboardBridgeTests`（23 件。一般の貼り付け板を消す）と `MacLibraryExampleTests`（20 件。サンプルのアプリが起動し、通知の delegate を設定する）と UI テスト（37 件）は流していない
- 今の `MacLibrary` の swiftinterface を作り、`dist/1.14.0/mac` の 1.3.0 と差が無いことを確かめた（0e で `results/swiftinterface/` に残す）

## 1. 何が問題か

### 1.1 macOS には汎用の C ABI が無い

iOS と同じく、C の関数は既にある。`UnityMacPlugin.framework` は Objective-C の `.m` に C の関数を 44 個書き、Swift を呼んでいる（Clipboard 15、Dialog 6、Notification 21、Share 2）。`dist/1.14.0/mac` の `nm -gU` も 44 個で、`unity-native-plugin` の `DllImport("__Internal")` も 44 本ある。しかし、これは Unity 専用の形で、汎用の C ABI ではない。

| 項目 | 今の形 | 汎用の C ABI に足りないこと |
|---|---|---|
| 入力 | Clipboard の全関数、Notification の content / trigger / category、Share、Dialog の alert の buttons と options が JSON の文字列。ファイルのパネルは位置引数と `const char**` | 型が無い。利用者が JSON を組み立てて解析する（`unity-native-plugin` の macOS の Builder / Parser / Reader は計 1,946 行） |
| コールバック | C の関数ポインタ。`user_data` も `release` も無い。通知のアクションの 2 つ、`NotificationHasPermission`（static の変数）、Clipboard の監視、Dialog のヘルプは受け手を 1 つしか持てない | 1 つの利用者しか受けられない。どの要求の完了か、いつ片付けてよいかが分からない |
| 文字列の寿命 | `NSString.UTF8String` をコールバックの間だけ貸す。Dialog のファイルの配列は `malloc` した `const char**` をコールバックの後に `free` する | 所有権ごと渡し、受け手が `_free` する規約と逆 |
| ヘッダー | `*Bridge.h` の 4 つは framework の公開ヘッダーに入っていない（入っているのは umbrella と `-Swift.h` だけ） | 利用者は宣言を自分で書くしかない |
| 名前 | 接頭辞が無く、大文字小文字も機能でそろっていない（`clipboard*`、`show*`、`share*` と `Notification*`） | ほかのライブラリとぶつかりうる。`ntk_*` の規約に合わない |

そのため、Unity 以外の C の利用者（Flutter の `dart:ffi`、Rust、Godot、C / Objective-C のアプリ）は、Swift を書かずに macOS のライブラリを使えない。

dist の 2 つの xcframework はどちらも dynamic の版付きの framework で、スライスは `macos-arm64_x86_64` の 1 つ、最小 macOS は 15.0。`unity-native-plugin` は `unity-mac-native-toolkit-*` だけをコピーし、書き出した `Mac.xcodeproj` に link と embed を足す。Unity のシンボル（`UnitySendMessage` など）への依存は無い。

### 1.2 ネイティブの利用者に届かないロジックがブリッジにある

iOS と同じく、多くは既に `MacLibrary` にある（通知の delegate、Clipboard の 20 のエラー、Share の 9 のエラー、Notification の 13 のエラー、Share のアンカーの解決、Dialog の既定のボタンの検証）。ブリッジにしか無いのは次のものだけである。

| 機能 | ブリッジにしか無いもの |
|---|---|
| 共通 | JSON の形式とその解析・組み立て（Clipboard 479 行、Notification 211 行、Share 59 行、Dialog は façade の中の 52 行）。C ABI では型にするので移さずに捨てる |
| Clipboard | main actor への受け渡し（`MacClipboardManager` は `@MainActor`）。引数の欠落と不正の分け方。結果を JSON にできなかったときの `unknown` への置き換え |
| Dialog | `alertStyle` の文字列から `NSAlert.Style` への変換。結果の正規化（ヘルプを押したら `buttonTitle = NULL`・`buttonIndex = -1`、ファイルのパネルのキャンセルで `fileCount = -1`。ヘッダーの文書は「0 if cancelled」で食い違う）。エラーを文字列 1 つにすること |
| Notification | 予約済み・表示済みの一覧の JSON 化（予約済みは trigger を落とす）、日時の ISO 8601 化、権限の状態の文字列化、`hasPermission`（authorized か provisional なら真）、`cancel` / `cancelAll` を `cancelScheduled` / `cancelAllScheduled` の別名にすること |
| Share | 要素の種類（text、url、image、file）から `ShareItem` への変換。知らない種類と値の無い要素を黙って捨てること |

逆に、ブリッジのためのものが `MacLibrary` の公開面に漏れている: `BridgeError`（Notification の Domain に public で置かれ、Clipboard のブリッジも使う）、Dialog のアイコンの JSON の解析 `IconConfiguration.from(json:)`、`Log`（`@objcMembers public class`）、`ClipboardLog`（`public enum`）。iOS は `ClipboardRedaction` を消せずに 2.0.0 に入れた（`ios-c-abi` の終わりの記録 3 章の 5）ので、1b で洗い出して扱いを決める（4 章）。

どちらにも無いもの:

- Dialog の安定したエラーの番号（`DialogError` は 3 つの case があるが番号が無く、ブリッジは文字列だけを返す）
- 任意の `Error` を持たないエラーの case。`NotificationDomainError` の 7 つ（`underlying: Error`）と `ShareError.presentationFailed(Error)`・`unknown(Error)` が `common.md` の「system の `Error` を Domain に保持しない」に反する
- 受け手が登録される前に届いた通知のイベントを保つ仕組みと、起動のきっかけになった通知の取得
- 通知のイベントと Clipboard の監視の複数の受け手

### 1.3 コールバックを返すスレッドが機能ごとに違う

iOS よりはそろっている（結果はおおむね main）が、同期で返る経路がある。

| 機能 | 今のスレッド |
|---|---|
| Clipboard | main（全経路が `Task { @MainActor }` を通る。監視のイベントも main） |
| Share | main |
| Dialog | 表示と結果は main（`DispatchQueue.main.async` の中で `runModal`）。**検証の失敗は呼び出し元のスレッドで同期的に返る**（空のタイトル、ボタンなし、既定のボタンが 2 つ以上、アイコンの検証の失敗、ファイルのパネルの空のタイトル。保存のパネルは空のタイトルを確かめない） |
| Notification の操作の結果 | main。**ブリッジの JSON の解析の失敗は呼び出し元のスレッドで同期的に返る**（show、update、schedule、registerCategory） |
| Notification のアクション | `didReceive` から main に移して呼ぶ |
| 戻り値の無い Notification の操作 | `cancelScheduled`・`cancelAllScheduled`・`removeDelivered`・`removeAllDelivered`・`cancel`・`cancelAll` は完了が無い |

C ABI では 1 つの規則にそろえる（D-6）。

### 1.4 その他、移す前に分かっている不備

- **Dialog が main を塞ぐ**: アラートもファイルのパネルも `runModal()`（アプリ全体のモーダル）で出す。`DispatchQueue.main.async` で積んだブロックの中で入れ子の run loop を回し、閉じるまで戻らない。その間にゲームの描画（Unity のプレイヤーのループ）が止まる見込み。さらに、**main キューのブロックの中にいる間は、入れ子の run loop でも main キューが捌かれない見込みがある**（CFRunLoop と libdispatch のどちらの仕組みによるかも含めて確かめていない）。そうなら、Dialog が開いている間、`DispatchQueue.main.async` と `Task { @MainActor }` で積んだもの（C ABI の全機能の完了・イベント・`release`、main に積む形の取り消し）がすべて閉じるまで止まる。逆に積み方によっては入れ子の中で走って再入する。どちらも測っていない（決定の文書の 1a-6、D-8。レビュー v1 の RA-1）。`stopModal` / `abortModal` は要求を区別しないので、取り消しがホストのモーダルを閉じる危険もある
- **Dialog の不備**: ヘルプのボタンを押すと、同じ完了が 2 回呼ばれる経路がある（`alertShowHelp` で 1 回、閉じた後の `runModal` の戻りでもう 1 回。コードを読んだだけで、動かしていない）。ヘルプの受け手はシングルトンの 1 つのプロパティで、片付けない。ブリッジの `.m` は `message` などの引数の `NULL` を確かめずに `stringWithUTF8String:` に渡し（C# は `message` に null を渡しうる）、コールバックの `NULL` も確かめない。4 つ目以降のボタンの番号を `rawValue` の差で出している
- **Share**: `NSSharingServicePicker` の表示は、Apple のヘッダーが「mouseDown で呼ぶ」と書き、`MacShareManager` 自身の文書も「`Task { @MainActor }` を挟むので保証されない」と書く。ネイティブの Swift の経路は実のクリックで確かめたが、Unity のブリッジの経路は確かめていない。基点は key window の contentView 全体の固定で、利用者が渡せない。サービスが delegate を呼ばない場合、以後の Share がすべて `alreadyInProgress` になる経路がありうる（どのサービスで起きるかは確かめていない）。結果の `serviceName` は表示名（地域化される）
- **通知の delegate**: `MacNotificationManager.setup()` は `UNUserNotificationCenter.current().delegate` を無条件に上書きし、前の delegate に転送しない。`willPresent` はすべての通知に自分で応える。manager が公開で delegate に準拠している。userInfo を JSON にする前に `isValidJSONObject` で確かめていない（ほかの発行元の通知で落ちうる）
- **Notification**: category をメモリの配列に持ち、`setNotificationCategories` で全体を置き換える（ホストが登録した category と、再起動の前に登録した category を消す）。配列に排他が無い。`registerCategory` は登録が終わる前に成功を返す。`update` は `identifier` を使わず `content.id` で追加する。`cancel` と `cancelScheduled`、`cancelAll` と `cancelAllScheduled` が同じ処理
- **bundle の無いプロセス**: 通知の関数をコマンドラインのツールから呼ぶと、`UNUserNotificationCenter.current()` が例外で落ちる（0 章）。今のブリッジは Unity のアプリの中でしか呼ばれないので表に出ていないが、C ABI の利用者は呼びうる
- **ログ**: `Log` は `os.Logger` だが、すべて `privacy: .public` で、`#if DEBUG` も無い。subsystem は `com.unity.native.toolkit`（持っていない名前空間）。通知のテキスト入力の返信、通知と Share の content の全文、Dialog のファイルのパス・タイトル・本文を出している。Clipboard だけは伏せている。`agent-rules/coding-rules/mac.md` は「全パラメータを出す」と定め、秘密の値を伏せる例外が無い（`ios.md` と `android.md` にはある）
- **配布物**: `dist/1.14.0/mac`（1.10.0 から同じバイナリ）は、ビルドのスクリプトの `rsync -aL` で symlink がすべて実体に置き換わっており、`codesign --verify` が 2 つとも失敗する。`UnityMacPlugin.framework` は自分の中に `MacLibrary.framework` を埋め込み、それは単体の `MacLibrary` と別のビルド（ハッシュも `CFBundleVersion` も違う）。2 つを同じアプリに入れたときの振る舞いは確かめていない
- **署名と bundle id**: 2 つの framework は利用者の個人の Apple Development の証明書で署名されている（Hardened Runtime なし。xcframework そのものは署名なし）。bundle id は持っていない逆 DNS の名前空間（`mac.library.MacLibrary.MacLibrary`、`unity.mac.plugin.UnityMacPlugin`）で、iOS の D-12・D-18 と同じ状況である
- **ビルドのスクリプト**: release でリポジトリの pbxproj の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を書き換える（テストのターゲットも含めて全部同じ値にする）。Xcode を選ばず `xcode-select` に従う。署名の設定を渡していない。`mac/generate_docc.sh` は始めに `mac/Build/MacLibrary` と `mac/Build/UnityMacPlugin` を消すが、そこはビルドのスクリプトの archive と同じ場所
- **Swift の並行性**: 全 7 ターゲットが Swift 5.0 の言語モードで、並行性の設定はどの階層にも無い。complete にすると 215 件の警告、Swift 6 では 8 件のエラー（0 章）。`migration` の README の「UnityMacPlugin に Clipboard が存在しない」は古く、今は Clipboard のブリッジがあり、案 C が効いて警告は 0 件
- **テスト**: Dialog のテストはどのターゲットにも無い。Notification の UI テストも無い（UI テストは Clipboard 17 件、Share 17 件、雛形 3 件）。ブリッジの C 関数を呼ぶテストは 0 件（Clipboard のブリッジのテストはソースの文字列を照らすだけ）。`accessibilityIdentifier` は Clipboard の画面にだけある。macOS のテストのスクリプトと基準が無い。最小 macOS は 3 つのプロジェクトのプロジェクトの階層が 15.1 で、本体とサンプルのアプリだけがターゲットで 15.0 に上書きしている。テストと UI テストのターゲットは 15.1 を継ぎ、`MacLibraryExampleTests` はターゲットにも 15.1 を直に書いている。`CURRENT_PROJECT_VERSION` が `MacLibrary` と `UnityMacPlugin` でずれている
- **私物に触れるテスト**: `UnityMacClipboardBridgeTests` は利用者の一般の貼り付け板を消す（`clear` の `general`）。`MacLibraryExampleTests` はサンプルのアプリを起動し、通知の delegate を設定する。UI テストはこの Mac の画面・マウス・キーボードを使う。macOS にはシミュレーターが無いので、iOS のように「許可の要らない場所で流す」ことができない（7 章、D-21・D-23）
- **`unity-native-plugin`**: macOS の xcframework は `VERSION.txt` で版を固定しておらず、`PreBuildProcessor` が dist の最新版を選ぶ（`ios-c-abi` の終わりの記録 3 章の 14 で、macOS の固定はこの課題に回した）。xcframework は `unity-mac-native-toolkit-` の前方一致と序数の文字列比較で選ぶ（`PreBuildProcessor`・`PostBuildProcessor`・`Tools/macOS/MacFrameworkPatcher` の 3 か所）。この前方一致は新しい名前（`mac-native-toolkit-2.0.0`、`mac-native-toolkit-capi-2.0.0`）に当たらないので、**今起きる罠は、どの OS のリリースでも新しい `dist/<版>` が 1 つできると、それを最新として選び、`unity-mac-*` が無いのでエラーのログを出して古い 1.3.0 のまま黙って進むこと**。capi を選ぶ罠（iOS の 1.4 と同じ）は、2c で前方一致を `mac-native-toolkit-` に変えたときに起きる。`PostBuildProcessor` は development ビルドで `-debug` が無いと埋め込まずに戻り、`MacFrameworkPatcher` は debug を区別しない。3 か所のコピーはディレクトリの列挙と普通のファイルのコピーで、版付きの framework の symlink を実体にしうる（レビュー v1 の RA-6）。Dialog の C# はインスタンスの閉包をコールバックに渡しており、`MonoPInvokeCallback` が無い（IL2CPP では関数ポインタにできない見込み。確かめていない）
- **マニュアル**: index の導入の手順が「Xcode 26.2」と書き、配布物を組んだ 26.3 とずれている。Unity の導入の手順はマニュアルに無い（Unity のマニュアルは `unity-native-plugin` が持つ）

## 2. なぜ今やるか

- Windows・Android・iOS の 3 つで規約が固まり、OS をまたいで照らす仕組み（`c_abi_contract_common.py`、`c_abi_error_numbers.json`）もできた。iOS の記録（同じ Apple の OS、同じ `@c @implementation`）が新しいうちに作れば、同じ作法を保てる。iOS は D-1 で「`Common/` は macOS で写して使える形にしておく」と決めており、`IosLibraryCApi/Common`（10 ファイル、1,019 行）は UIKit に依存しない
- `unity-native-plugin` は iOS を C ABI に移したばかりで、`user_data` の表と完了の積み方の土台がある。macOS も同じ形にすれば、macOS の C# の JSON の層（Builder / Parser / Reader 1,946 行）を消せる
- macOS の Swift 6 への移行（`migration`）は、公開 API を変える直し（`shared` の `@MainActor` など）を含む。破壊的変更の 2.0.0 に入れるのが最も安い
- 1.4 のログ、通知の delegate、配布物の symlink と署名、bundle id は、C ABI と関係なく直す必要がある
- `feature-split-distribution`（機能ごとの配布物）と `feature-scoped-testing` の iOS / macOS の分は「全 OS の C ABI の後」に着手すると決めてあり、macOS がその前提になっている

## 3. 目標の構成

段階 4 が終わった時点の形。`(新)` は新しく作るもの、`(移)` は 1.2 のロジックを移して作るもの。モジュール名とクラス名は案で、設計書で決める。

```
mac/
  MacWorkspace.xcworkspace                       # 下の各プロジェクトをまとめる
  MacLibrary/                                    # Swift の API（mac-native-toolkit-2.0.0.xcframework。dynamic、版付き）
    MacLibrary/                                  # bundle id は com.jonghyunkim.nativetoolkit.MacLibrary（D-12）
      Common/                                    # ログの規則（秘密の値を伏せる）、presenter と要求の箱（iOS の 1b の形）
      Clipboard/  Dialog/  Notification/  Share/
        Dialog/{Domain,Application,Presentation}/ # (移) 結果を 1 つにまとめた型、エラーの番号。ほかの機能と同じ層に分ける
        Notification/Presentation/               # (移) イベントの口（複数の受け手、受け手が登録されるまで保つ）、
                                                 # delegate を起動の終わりまでに入れる口と転送（D-7。iOS の router を写す）
        */Domain/Model/*Error.swift              # 安定した case に直す（任意の Error を持たない。Dialog は番号を足す）
    MacLibraryTests/
  MacLibraryCApi/                                # (新) 汎用の C ABI（mac-native-toolkit-capi-2.0.0.xcframework。dynamic、版付き。D-9）
    include/NativeToolkitC/                      # 公開ヘッダー（xcframework の Headers と dist/ に入れる。版付きの構成での置き方は 1a）
      Common.h                                   # OS に依存しない部分（Windows / Android / iOS と照らす）
      Clipboard.h  Dialog.h  Notification.h  Share.h
    MacLibraryCApi/
      Common/                                    # 土台（Swift）: IosLibraryCApi/Common を写す（D-1）。写しの一致を照合で守る
      Clipboard/  Dialog/  Notification/  Share/ # <機能>Entry.swift（@c @implementation の入口だけ）と <機能>Receiver.swift
      MacLibraryCApi.exp                         # 公開するシンボル: _ntk_* だけ（D-11）
  MacLibraryCApiTests/                           # (新) C ABI のテスト（C の関数を XCTest から呼ぶ。ASan / TSan でも流す）。
                                                 # 純粋な検査（NULL、struct_size、UTF-8、ハンドル）と、ホストが要るもの（通知・Dialog・Share・
                                                 # 一般の貼り付け板）を分ける（7.5）
  MacLibraryCApiTestHost/                        # (新) C ABI のテストのホストのアプリ（iOS の IosLibraryCApiTestHost に当たる。名前は案）
  MacLibraryCApiUITestApp/  MacLibraryCApiUITests/ # (新) C を呼ぶ UI テスト（起動の中の install など。iOS の --capi-ui に当たる）
  MacLibraryCApiSmoke/                           # (新) dist の 2 つの xcframework だけを使う C / Objective-C のアプリ。Swift のコードを持たない
  MacLibraryExample/                             # ネイティブのサンプル。Swift の API だけを使う
    MacLibraryExampleUITests/                    # 全機能の UI テスト（段階 0c）
```

無くなるもの:

| 対象 | 時期 |
|---|---|
| `mac/UnityMacPlugin/` のビルドと基準からの除外 | 段階 0e（D-22。ソースは 1b の参照のために残す） |
| `mac/UnityMacPlugin/`（`unity-mac-native-toolkit-*.xcframework`） | 段階 3 |
| `mac/Docs/UnityMacPlugin`、`docs/<版>/mac/UnityMacPlugin` の生成 | 段階 3（過去の版の `docs/` は残す） |

配布物（`dist/<リリース版>/mac/`。D-9、D-17）:

| ファイル | 中身 | 使う人 |
|---|---|---|
| `mac-native-toolkit-2.0.0.xcframework` | Swift の API（`MacLibrary.framework`、swiftinterface） | Swift のアプリ。C の利用者も一緒に埋め込む |
| `mac-native-toolkit-capi-2.0.0.xcframework` | C ABI（`MacLibraryCApi.framework`。公開ヘッダー（置き場は 1a-1 で確定する。第一の案は `Headers/NativeToolkitC/*.h`）、module map、公開シンボルは `ntk_*` だけ。Swift のモジュールと interface、Swift 向けのヘッダーは配らない。`MacLibrary.framework` を中に埋め込まない（1.x の二重の埋め込みをやめる）） | C の利用者。`mac-native-toolkit-2.0.0.xcframework` も一緒に埋め込む |
| `include/NativeToolkitC/*.h` | 公開ヘッダー（xcframework の中と同じもの） | ヘッダーからバインディングを作る人（ClangSharp、bindgen、ffigen） |

どちらの framework も版付きの構成の symlink を保つ（1.4 の `rsync -aL` を直す。D-9）。

依存の向きは `MacLibraryCApi` → `MacLibrary`。ほかの OS と同じく、**機能の実装は `MacLibrary` にだけ置き**、`MacLibraryCApi` は型の変換、検査、スレッドの受け渡しだけを受け持つ。

| 利用者 | 使うもの |
|---|---|
| Swift / Objective-C のアプリ（Swift の API を使う） | `MacLibrary`（今のまま） |
| C の利用者（Unity、Flutter、Rust、Godot、C / Objective-C のアプリ） | `MacLibraryCApi`（と、それが依存する `MacLibrary`） |

### 3.1 利用者の前提

C ABI の設計書の冒頭に置く。言語ごとの導入の手順はマニュアルに書く（段階 4）。Unity の導入の手順は、iOS・Android と同じく `unity-native-plugin` のマニュアルに任せる。

| 前提 | 理由 | 成り立たない使い方 |
|---|---|---|
| AppKit のアプリ（`NSApplication` が動き、bundle id を持つ `.app`）のプロセスの中で呼ぶ | `NSAlert`、パネル、`NSSharingServicePicker` は動いている `NSApplication` と window が要る。`UNUserNotificationCenter.current()` は bundle の無いプロセスで例外で落ちる（0 章） | コマンドラインのツール、デーモン、App Extension。通知の関数は入口で bundle を確かめてエラーで返す（落とさない。番号は第 1 部）。ほかの機能をコマンドラインのツールから呼ぶ使い方は確かめない（決定の文書の 8.4） |
| 2 つの framework をアプリの `Contents/Frameworks` に埋め込み、アプリの ID で署名する（Embed & Sign） | どちらも dynamic で、`MacLibraryCApi` は `MacLibrary` に依存する。配る framework は署名しない（D-18）ので、利用者が署名し直す | `MacLibraryCApi` だけを入れる使い方。署名し直さない組み込み（`Contents/PlugIns` に置くだけなど）。この場合は利用者が内側から `codesign` する手順をマニュアルに書く |
| Hardened Runtime を有効にするなら、アプリと framework を同じ Team の証明書で署名する | Library Validation は、Apple か同じ Team ID の署名の framework しか読まない。ad-hoc（Sign to Run Locally）には Team ID が無いので、ad-hoc＋Hardened Runtime では起動できない（0 章） | 開発中の ad-hoc＋Hardened Runtime（Hardened Runtime を外すか `disable-library-validation` を付ける、とマニュアルに書く） |
| アプリの最小 macOS が 15.0 以上（D-15） | xcframework の最小 macOS | macOS 14 以前 |
| Xcode 26.3 以上で組む（D-16。C ABI だけを使う利用者は Xcode 26 のどの版でもよい） | Swift の API を使う利用者は swiftinterface を読む | Xcode 26.2 以前（Swift の API を使うとき） |
| 自分が作っていないスレッドからのコールバックを受けられる | コールバックは macOS の main キューから非同期に呼ぶ（D-6） | Dart の `NativeCallable.isolateLocal`（Flutter 3.35 で macOS の UI と platform のスレッドが統合されたが、手元で確かめられないので `NativeCallable.listener` を前提にする）。Unity は `[MonoPInvokeCallback]` で受ける |
| Dialog・Share・権限の要求は、window のあるアプリから呼ぶ | 表示の基点に key window（無ければ main window）を使う。macOS のアプリは後ろにいても window を持てるので、「前面」の意味を第 1 部で決め直す（iOS の `NOT_FOREGROUND` を何で返すか） | window の無いアプリ（メニューバーだけ）からの Share。全画面の Unity のプレイヤーの上に Dialog が出るかは 1a で確かめる |
| Dialog の出し方による制約（D-8 で決める。1a-6 の前は未定） | `runModal` を保つなら、閉じるまで main の描画のループが止まり、ほかの完了も閉じるまで遅れうる（1.4） | D-8 の結果で書き直す |
| 通知の機能を使うなら、ホストのネイティブのコードが起動の終わり（`applicationWillFinishLaunching` か `applicationDidFinishLaunching` から戻るまで）に main スレッドで `ntk_notification_install` を呼ぶ（D-4。Swift の同じ口で入れてもよい） | delegate は 1 つしか持てず、起動の後に設定するとコールドスタートのクリックを取りこぼす（Apple の文書）。前面にいるときに通知を出すかも delegate の `willPresent` で決まる。Unity の C# は起動の後に始まり、`.bundle` は最初の `DllImport` まで読まれない | ネイティブのコードを持たない組み込み。Unity での入れ方は 1a で決める（D-4、D-24） |

Swift のアプリは C ABI を使わず、`MacLibrary` を直接呼ぶ。

### 3.2 iOS と同じにするもの、macOS で決め直すもの

iOS の README の 3.2（Windows・Android から引き継いだ規約）は、すべてそのまま使う。iOS の決定の振り分けの全文は `results/2026-11-22-macos-c-abi-survey-b-ios-carryover.md` の 1 章にある。

| 扱い | 対象 |
|---|---|
| そのまま引き継ぐ | iOS の 3.2 の「そのまま引き継ぐ」のすべて（名前、エラーの番号の規則、UTF-8、U+FFFD、真偽値、0 で埋めた既定値、ハンドル、`struct_size`、`user_data` と `release` の規則、`_free(NULL)`、`ntk_version()`、公開ヘッダーの形、64 ビットの要求の ID、スレッドの規則、Dialog は非同期だけ、`release` の状態機械、ブリッジを 1 つずつ写さない、値の補正をしない）。iOS で決めた形: `@c @implementation` の入口（Objective-C を持たない）、`EXPORTED_SYMBOLS_FILE`、2 つの dynamic の xcframework、`ntk_last_system_code()` は常に 0、`ntk_notification_install` の契約（main からの同期の例外、冪等、`WRONG_THREAD`）、通知の delegate の転送の形（第 1 部 5.12。router・印・1 回だけ通す包み・循環の防止・入れ直し）、エラーの番号の OS をまたいだ表（`scripts/c_abi_error_numbers.json`）、`os.Logger` の subsystem とカテゴリの決め方 |
| macOS で決め直す | 前面の扱い（scene と key window → `NSApp.keyWindow` / `mainWindow`、`NSApp.isActive`。後ろにいても window がある）、Dialog の出し方と種類（`runModal` / sheet、アクションシート・テキスト入力・ログインが無くファイルのパネルがある。D-8）、Share の基点と mouseDown の文脈（基点は iPad だけでなく毎回要る）、通知の delegate を入れる時期とホスト（Unity の macOS のプレイヤーに iOS の `UnityAppController` に当たる口があるか。D-4）、起動のきっかけの判定の材料（`NSApplication.didBecomeActiveNotification`）、貼り付け板のプライバシー（iOS の貼り付けのダイアログ → macOS 15.4 以降の `accessBehavior` と `detect*`。`detectPatterns`・`detectMetadata` は内容を読まないが、`detectValues` と通常の読み出しは内容を読み、確認と拒否がありうる。`accessBehavior` だけから個々の読み出しの結果を決めない）、sandbox のホストでのファイルのアクセスの権利（パネルの結果と Share のファイル。決定の文書の 8.6）、配布の形（版付きの framework、1 つのスライス、symlink、ヘッダーの置き方、rpath）、署名（Hardened Runtime と Library Validation、公証）、プライバシーマニフェスト（macOS は理由の申告が要らない。D-18）、テストの環境（シミュレーターが無い。D-21・D-23）、Unity の取り込み方（D-24） |
| iOS 専用で関係しない | アクションシートと iPad の基点、`UIPasteControl` と `ntk_clipboard_load_item_async`、`UIScene` の切断、`springboard`、実機の `devicectl`、`--capi-device` |

### 3.3 OS をまたいだヘッダーの扱い

iOS の 3.3 をそのまま使う。`Common.h` は OS ごとに写して持ち、4 つの扱いで照らす。`NTK_VERSION` は macOS のライブラリの版（2.0.0）。機能のヘッダーは OS ごとに持ち、**同じ意味の操作には同じ名前を付ける**。

- Clipboard は iOS と同じ名前にできる見込みが大きい（copy、append、read、readData、snapshot、clear、create / remove pasteboard、detectPatterns / Values、監視、checkForegroundChange は両方にある）。macOS だけの `detectMetadata`・`accessBehavior` は同じ形で足す
- Share は iOS と同じく `ntk_share_content_async` の 1 つにできる見込み（`MacLibrary` も種類の混ざった項目を 1 回で渡す）。macOS だけの「サービスを名指しする」は第 2 部で名前を決める（`canPerform` は D-5 で 2.0.0 の範囲の外）
- Dialog は種類が違う（ファイルのパネルがあり、テキスト入力・ログイン・アクションシートが無い）。alert と confirm を Android / iOS の名前に合わせられるか、パネルをどう名付けるかを第 2 部の最初に決める
- 照合（`c_abi_contract_common.common_header_problems`）はもう N 個の OS を扱える。macOS の `Common.h` を足したら全 OS の照合を流す

## 4. Swift の API の方針

`MacLibrary` は、iOS の 1b の前の `IosLibrary` とほぼ同じ状態である（Clipboard だけは 1.10.0 で作り直したので、`async` 版と `@MainActor` があり、構造が新しい）。iOS の 1b で `IosLibrary` に足した Swift の API を、`MacLibrary` にも同じ考えで足す。

| iOS の 1b で足したもの | macOS の今 | 1b ですること（案。Swift の API の設計書で決める） |
|---|---|---|
| 要求の箱（`RequestBox`）と要求ごとの取り消し | 無い（Clipboard の貼り付けの読み込みは世代で一括に取り消す） | 同じ型を足し、Dialog と Clipboard の読み込みを要求ごとに取り消せるようにする |
| presenter（表示元の選び方）と前面を返す口 | 無い（Share は key window の固定、Dialog は app-modal） | `NSWindow` を表示元にする形で足す（S-P1 の macOS 版）。Share の基点（view と矩形）を渡す口もここで決める |
| 表示の手順（同じ回の 2 つ目、待ち、判定し直し）と解放の見張り | 無い（Share は同時に 1 つで、2 つ目は `alreadyInProgress` で断る） | iOS の SH-13（同じ回の 2 つ目の Share の完了が来ない）と同じ種類の穴を、Dialog・パネル・ピッカーのそれぞれで最初の表に入れて測る |
| 通知の delegate の転送（proxy・router・印・1 回だけ通す包み・循環の防止・入れ直し） | 無い（上書き、公開で準拠） | iOS の router を写す（UIKit を見ないので写せる）。installer と proxy の UIKit の部分（`applicationState`、`didBecomeActive`）を AppKit に置き換える。manager の公開の準拠を外す |
| イベントの口（複数の受け手、32 件を保つ、起動のきっかけ、設定の要求） | 無い（受け手は 1 つずつ） | 同じ形で足す |
| 通知の操作の `async throws` 版 | 無い | 同じ形で足す |
| エラーの case の整理（任意の `Error` を持たない、`FailureDetail`） | 任意の `Error` が 9 つ。Dialog は番号なし。Domain に `BridgeError` | 同じ形に直す。Dialog に番号を足す。`BridgeError` を Domain から出す |
| category の登録を 1 つの FIFO で直列に、完了は反映の後 | メモリの集合で全体を置き換える | iOS の FIFO を写し、OS の今の一覧を読んでから書く形にする |
| userInfo の検査と値の木 | 無い（JSON にできなければ `"{}"`） | 同じ形で足す |
| プライバシーマニフェスト | 無い。理由の申告が要る API の呼び出しも見当たらない | D-18（macOS では要らない見込み） |
| ログの規則（`os.Logger` を直に呼び、補間ごとに `privacy:`） | すべて `.public`、subsystem が持っていない名前空間 | 同じ規則にし、`mac.md` に秘密の値を伏せる例外を書いてから 1b に入る |
| Swift 6 / `@MainActor @Sendable` の完了 | Swift 5.0、complete で 215 件 | 0e・0f で行う（D-14） |
| Dialog とパネルの表示の手順（D-8） | `DispatchQueue.main.async` の中で `runModal`。開いている間、ほかの完了が止まりうる | D-8 で確定した方式に 1b で変える（A のままなら変えない）。Swift の利用者から見た動作が変わるので 4.1 に書く |
| bundle id | 持っていない名前空間 | 0g で行う（D-12） |

ブリッジのためだけに公開しているもの（`BridgeError`、`IconConfiguration.from(json:)`、`Log`、`ClipboardLog`、`NotificationPermissionHelper`、各 UseCase と `NotificationRepositoryImpl` の public）は、1b で洗い出し、消すか残すかを決める（iOS は `ClipboardRedaction` を残す形で 2.0.0 に入れた）。Dialog の `accessoryView: NSView?` のように C に出せないものは、Swift の API にだけ残す。

### 4.1 2.0.0 で Swift の利用者に見える変更（段階ごとに足す）

iOS の 4.1 と同じく、段階ごとにこの節に書き足す（0e の `@Sendable`、0f の言語モード、0g の bundle id、1b の型とエラーの case と、D-8 で出し方を変えるなら Dialog とパネルの表示の手順）。今は空。

## 5. 段階

1 段階 = 1 PR を基本にする。iOS と同じく、段階 0a〜0d でテストをそろえてから着手する。**macOS ではテストがこの Mac の上で動くので、私物を守る規則（D-23）を 0a の前に決めて `agent-rules/device-testing.md` に書く。**

| 段階 | 内容 | 動作の変更 |
|---|---|---|
| 0a | スパイク: サンプルの UI テストで扱える項目を確定する（7.2）。XCUITest で、通知のバナーと通知センター、通知のアクションのボタン、テキスト入力のアクション、**通知のクリックからのコールドスタート**、通知の許可の問い合わせ、Share のピッカーと選んだ後のサービスの画面、アラート（`NSAlert`）とファイルのパネル（`NSOpenPanel` / `NSSavePanel`）、ヘルプのボタン、貼り付けのボタン（`PasteButton`）と、貼り付け板のプライバシーの確認（プレビューの設定で有効にした場合）を扱えるか。予約した通知の発火を待てるか。**macOS の VM（D-21）で同じことが動くか**（ホストで組んで VM で流す形、VM の Xcode とランナー、署名。1a-10）。通知のクリックと `open -b` は LaunchServices に登録された同じ bundle id のどのコピーでも起動しうるので、**起動したコピーの道を記録し、余分なコピーを外す手順**を決める（登録を変えるので D-23 の許可の対象）。通知の許可は bundle id ごとにシステムに残り最初の問い合わせに戻せないので、**許可の状態を戻す手段**（VM のスナップショットか利用者の手）を決める。この Mac で流すので、回ごとに利用者の許可を得る（D-23） | 無し |
| 0b | サンプルの画面に `accessibilityIdentifier` を付ける（Dialog・Notification・Share・一覧は 0 個）。通知の画面に「最後に受けたイベント」の表示と更新の回数を足す（iOS の 0b と同じ。UI テストから受け取りを確かめるため） | サンプルの通知の画面に表示が 1 つ増える |
| 0c | Dialog / Notification の UI テストを足し、Clipboard / Share を設計に合わせて広げる。XCUITest で扱えない項目は人の確認の手順書にする。UI テストの設計書を先に書く | 無し |
| 0d | `scripts/test_mac.sh` を作り（unit・UI テストをまとめて実行。`.xcresult` から読む）、**今のコードで全件通ることを確かめ、結果を基準として記録する**。私物に触れるテストの区分と許可の仕組みを入れる（D-23）。基準を取る環境は D-21。`UnityMacPluginTests` は基準に入れないが、0e でビルドから外す前に 75 件を一度流し（一般の貼り付け板を消すテストを含むので許可を得て）、結果を `results/` に保存する（D-22） | 無し |
| 0e | **1a-前（下）が済んでから入る**。設定をそろえる: `UnityMacPlugin` をワークスペースのビルドと `test_mac.sh` から外す（D-22）。最小 macOS を 15.0 に（プロジェクトの階層の 15.1 と、`MacLibraryExampleTests` のターゲットの 15.1。直した後に全ターゲット・全構成の実効の値を `-showBuildSettings` で確かめる）。**Dialog とパネルが `runModal` に入る経路は変えない**（出し方は今の A のまま。D-8 で決めた形に変えるのは 1b。`Task { @MainActor }` や `@MainActor async` から入るように書き換えると、Swift の main actor の仕事も main キューに積まれ、D-8 の判断の前提が変わるため）。`CURRENT_PROJECT_VERSION` のずれを直す。`SWIFT_STRICT_CONCURRENCY=complete`、`SWIFT_DEFAULT_ACTOR_ISOLATION`、upcoming feature をプロジェクトの階層で固定し、`MacLibrary` とサンプルの警告を 0 にする（Dialog・Notification・Share の完了を main で返し、handler を `@MainActor @Sendable` にする）。公開 API の差分（swiftinterface）を `results/swiftinterface/` に保存する。`LastUpgradeCheck` は扱いを先に決める（知見の 10） | 完了と handler の型に `@MainActor @Sendable` が付く（2.0.0） |
| 0f | Swift 6 の言語モードにする（`MacLibrary`、サンプル、テスト。UI テストのターゲットは D-14 の例外）。0e と同じく、`runModal` に入る経路は変えない。0e・0f の後に 1a-6 の測り（出し方 A のまま）を流し直し、Dialog の間のほかの完了と取り消しの振る舞いが 0e の前と変わっていないことを確かめる（D-8 の契約のとおりに届くかは、出し方を変える 1b の後と、C の入口ができる 2b の後に確かめる）。`@MainActor` のクラスを main 以外で手放す経路を最初に探す（iOS の `isolated deinit` の件。知見の 8） | Swift の利用者から見た並行性の注釈（iOS は宣言の差分が無かった） |
| 0g | `MacLibrary` の framework の bundle id を `com.jonghyunkim.nativetoolkit.MacLibrary` に変える（D-12）。ログの subsystem も同じ名前空間にする。サンプルのアプリとテストのターゲットの bundle id は変えない（7 章の更新のテストで、2.0.0 のサンプルが 1.x のサンプルを上書きするため）。**0e〜0g の後に全件を流し、0d の基準と同じ結果になることを確かめる**（7 章の区切り） | framework の bundle id が変わる（2.0.0） |
| 1a | スパイク（決定の文書の 8.2）。結果で D-4・D-8・D-9・D-10・D-11・D-18・D-24 を確かめ、C ABI の設計書の第 1 部を書く。**契約を左右する項目（1a-6〜1a-9。Dialog の下での main への積み方と取り消し、Share の呼び出しの文脈、通知の起動の判定、Unity のロードと install）は「1a-前」として 0e の前に終える**（0a〜0d と並行してよい。0e で完了と handler の actor の契約を変えた後に成り立たないと分かると、移行と基準をやり直すため。レビュー v1 の RB-1）。1a-10（VM）は 0a の完了の条件にする（D-21）。残り（1a-1〜1a-5、1a-11）は 1b の前まででよい。関わる決定は D-6・D-7・D-16・D-21 も含む。**本物の Unity の macOS のビルド（6000.4.2f1、「Create Xcode Project」の書き出し、release）に雛形の C ABI を入れて呼ぶ**。確かめは iOS と同じく `unity-native-plugin`（別リポジトリ）の agent が行い、こちらは雛形の 2 つの xcframework・ヘッダー・申し送りを `results/` に出す。確かめること: プラグインがいつ読み込まれるか、起動の中で `ntk_notification_install` を呼べる口（書き出したプロジェクトの `main` や app delegate に足せるか）、通知のクリックでの起動、C# が main スレッドで動くか、Dialog の間にゲームが止まるか、全画面の上に Dialog と Share が出るか、Share を main に積んで出せるか（mouseDown の文脈）、Hardened Runtime と署名し直し | 無し |
| 1b | Swift の API を補完する（4 章）。Dialog の出し方は D-8 で確定した方式に従う（A' / A'' / B なら、`MacLibrary` の表示の手順が変わり、Swift の利用者から見た動作も変わるので 4.1 に書く）。1.2 のロジックを `MacLibrary` へ移し、イベントの口、delegate を入れる口と転送、エラーの直し、ログの規則を入れる。1.4 の不備を直す。新しい API を使う画面をサンプルに足す。iOS と同じく機能ごとのコミットにする（共通 → Dialog → Share → Clipboard → 通知の delegate とイベント → 通知の操作 → 測りの記録と全体の実行） | 1.4 の不備の直し（ヘルプの完了が 1 回に、category が全体を置き換えない、`registerCategory` の完了など）。通知の delegate を転送する形にする。エラーの case が変わる。presenter と取り消しの口を足す（既定は変えない。ただし Dialog の出し方は D-8 に従う） |
| 2a | `check_c_abi_contract_mac.py`、`check_manual_c_examples_mac.py` を足す。iOS の照合から OS ごとの定数（道、スライス、clang の target、許す case）を外へ出し、macOS の照合は表を渡すだけの薄いファイルにする（D-1）。iOS の照合が変わらないことを `scripts/tests` で確かめる。`IosLibraryCApi/Common` と `MacLibraryCApi/Common` の写しの一致を照らす。照合の自己テストで、規則を 1 つずつ壊すと落ちることを確かめる | 無し |
| 2b | `MacLibraryCApi` を作り、C ABI を実装する。C ABI のテスト（`MacLibraryCApiTests`）と smoke（`MacLibraryCApiSmoke`）、`check_mac_dist.py`（7.3）。ビルドのスクリプトに capi の xcframework と `include/` を足し、symlink を保ち、署名の扱い（D-18）と Xcode の選び方（D-16）を入れ、pbxproj の版の書き換えをやめるか範囲を絞る。**完了の条件に 2a の機械照合を入れる**。**2b の終わりにリリース版を決めて `dist/<リリース版>` を作る**。dist にはいつも全 OS の成果物をそろえる（iOS の dist/1.14.0 と同じ。リリースのチェックリストの全 OS の照合を流せるように）。**dist を置く前に、`unity-native-plugin` に下の 4 つが済んでいることを確かめる** | C ABI が増える（新しい配布物） |
| 2c | `unity-native-plugin` の macOS を C ABI に移す: P/Invoke、JSON の層の削除、通知の delegate を起動の終わりまでに入れるネイティブのコード（1a で決めた形）、4 機能を一度に移す（D-20）、Dialog の C# のコールバックを static と `MonoPInvokeCallback` に直す、IL2CPP なら `GameAssembly` のターゲットへのリンク（1a-9 で要ると分かれば）。最後の dist で、backend（Mono / IL2CPP）・Unity の版・アーキテクチャごとの表を作り、コールバック・`release`・GC を挟んだ寿命・通知の起動を確かめる。こちらは対応表と申し送りを出し、書き換えは向こうで行う。2c の成功をリリースの条件にする | Unity が C ABI を呼ぶ |
| 3 | `UnityMacPlugin` を削除する。ビルドのスクリプト、`generate_docc.sh`、`publish_docs.sh`、`scripts/check_design_consistency.py`、`scripts/README.md`、README、`agent-rules/coding-rules/{mac,common}.md`、`agent-rules/workflows/` から外す | `unity-mac-native-toolkit-*.xcframework` が無くなる（D-2） |
| 4 | ドキュメント: マニュアルの macOS の節に C ABI を足す（3 言語）。2.0.0 の移行ガイド（ブリッジの廃止、Swift 6 の注釈、エラーの case、通知の delegate を入れる関数と転送、bundle id、署名と Hardened Runtime の注意）、言語ごとの導入の手順を書く。C ABI の Doxygen を `publish_docs.sh` に足し、DocC の `MacLibrary` を合わせる。マニュアルの版は 2b で決めたリリース版にする | - |

**`unity-native-plugin` に頼むこと**（iOS の 5 章と同じ。新しい dist を置いた時点で向こうのビルドが壊れないように）。1 は**次にどの OS でも `dist/` を作る前**に頼む（`FindLatestVersionInDist` はどの OS のリリースの dist でも選ぶので、macOS の 2b を待つと間に合わない。レビュー v1 の RB-13）。2〜4 は 2b で dist を置く前に:

1. macOS の xcframework を `VERSION.txt` で完全なファイル名に固定する（iOS・Windows・Android は固定済み）
2. `PreBuildProcessor`・`PostBuildProcessor`・`Tools/macOS/MacFrameworkPatcher` の 3 か所の探索を完全一致にする（2c で前方一致を `mac-native-toolkit-` に変えると、序数の比較で `-capi-` を選ぶ）
3. `PostBuildProcessor` と `MacFrameworkPatcher` を、`PreBuildProcessor` と同じく development ビルドで `-debug` が無ければ release の xcframework を使う形に直す
4. 3 か所のコピーの経路で、版付きの framework の symlink を保つ（`ditto` か symlink を作り直すコピー）。dist → Unity のパッケージ（symlink を commit する。今の `Plugins/macOS` は git に symlink を持たない）→ git の URL で入れた `PackageCache` → AssetDatabase の取り込み → 書き出し → 最後の `.app` の各段で、警告や二重の取り込みなしに symlink が残り、最後の `.app` の framework の `codesign --verify` が通ることを確かめる（レビュー v1 の RA-6）

**順番の理由**:

- 0e〜0g は、0d の基準と同じ UI テストが通ることで、動作が変わっていないことを確かめる（4.1 に書いた意図した変更は除き、差は理由と期待値を記録する）。分けるのは、差が出たときに原因を切り分けるため（iOS と同じ）
- 1a を 1b の前に置くのは、1b で足す Swift の API の形（presenter、Dialog の出し方、delegate を入れる口）が C ABI と Unity の要求で決まるため。うち契約を左右する 1a-前は 0e の前に置く（0e で完了の型を変える前に、Dialog の下で main への積み方が成り立つかを知るため）。iOS は 1a を 0g の後に置いたが、iOS には `runModal` に当たる問題が無かった
- 1b を 2b の前に置くのは、逆にすると C ABI の受け口がブリッジの中のロジックに依存するか、同じロジックをもう 1 つ書くことになるため
- 2a を 2b の前に置くのは、C ABI の完了を機械照合で判定するため
- 段階の番号は依存の順ではない。2c と 3 はどちらも 2b の後で、互いに依存しない。リリースは 2c・3・4 のすべてに依存する
- 3 は、iOS・Android と同じく 2c を待たずに進めてよい。`unity-native-plugin` が使うのは出し済みの `dist/1.14.0/mac` の xcframework で、リポジトリからブリッジを消しても影響しない

**2.0.0 を出す条件と戻り先**: DoD がすべて満たされ、`unity-native-plugin` が `dist/<リリース版>` の xcframework で通しの検証を通したこと。`unity-native-plugin` は native-toolkit のリリースの後に自分の版を出す。2.0.0 に問題が出たときの戻り先は、`dist/1.14.0/mac`（1.3.0）とタグ `1.14.0`。

### 5.1 設計書

この企画が企画書の役割を持つ。設計書は公開 API を決める段階とテストの段階だけに書く（iOS と同じ）。

| 設計書 | 書く時期 | 書くこと |
|---|---|---|
| UI テスト | 0a の後、0b の前 | 機能ごとのテストケースの一覧と、確かめる内容。XCUITest で扱う項目と人が確かめる項目の分担（0a の結果に基づく）。私物の Mac を守る仕組み（D-23） |
| C ABI 第 1 部 | 1a の後、1b の前 | 利用者の前提（3.1）、スレッド、寿命、`release` の状態機械（失敗の経路を最初から表に入れる）、通知の delegate とイベントの保ち方、前面の扱い、Dialog の出し方と取り消し（D-8）、Share の基点と呼び出しの文脈、貼り付け板の読み出しの種類ごとの確認と拒否、sandbox のファイルのアクセスの権利、例外、bundle の無いプロセス、D-4・D-10・D-11・D-24 の決定 |
| Swift の API の補完 | C ABI の第 1 部の後、1b の前 | ネイティブの利用者に公開する Swift の API が変わる。**今のブリッジの約束が新しい API のどこで守られるかの対応表**と、エラーの case の対応表を含める |
| C ABI 第 2 部 | 1b の後、2b の前 | 全関数の一覧、**今のブリッジの 44 関数と 6 章の振る舞いの集合から新しい関数への対応表**、エラーの表、付録 A のヘッダー。章番号は iOS と同じにする（照合が見出しで読むため） |

スパイク（0a、1a）の結果は設計書にせず `results/` に記録する。公開 API の 3 本（C ABI の 2 部と Swift の API）は、これまでと同じく別のモデルにレビューしてもらってから着手する。

**決めたら、決定の文書（D-n、8.6）と DoD をその場で直す**。この企画の表に「設計で決める」が古いまま残らないようにする（iOS の知見の 12）。

置き場所:

```
artifact/topics/macos-c-abi/
  README.md                                          # 状態・要約・次にすること・リンク
  plans/
    2026-11-22-macos-c-abi-plan.md                   # この文書
    2026-11-22-macos-c-abi-decisions.md              # 決定（D-n）、1a で確かめること、ツールチェーン、決めないこと、出典、設計で決めること
    2026-11-22-macos-c-abi-dod.md                    # DoD
  designs/
    YYYY-MM-DD-macos-c-abi-ui-test-design.md         # 段階 0
    YYYY-MM-DD-macos-c-abi-c-abi-design.md           # 1a の後（第 1 部）
    YYYY-MM-DD-macos-c-abi-swift-api-design.md       # 1b の前
    YYYY-MM-DD-macos-c-abi-c-abi-design-part2.md     # 2b の前
  reviews/
  results/
    2026-11-22-macos-c-abi-ios-lessons.md            # iOS から引き継ぐ知見
    2026-11-22-macos-c-abi-survey-*.md               # 企画の調査の全文（4 つ）
```

段階の経過（何をいつ確かめたか）は、この文書の段階の表に書き足さず、README の状態の行と `results/` の作業の記録に書く（`topic-document-size` の案）。

### 5.2 段階ごとに壊れる場所

| 場所 | 内容 | 影響する段階 |
|---|---|---|
| `scripts/build_xcode26_library_xcframework.sh` | `MacLibrary` と `UnityMacPlugin` を作り、`UnityMacPlugin` の中に `MacLibrary` を埋め込む。`rsync -aL` で symlink を壊す。release でリポジトリの pbxproj の版を書き換える。Xcode を選ばない。署名の設定を渡していない。capi の xcframework と `include/` は作らない | 0e（ブリッジを外す）・2b（capi、symlink、署名、Xcode）・3 |
| `scripts/build_xcode16_library_xcframework.sh` | 前の版。今は使っていない（`scripts/README.md`） | 3（消すかを決める） |
| `mac/generate_docc.sh`、`scripts/publish_docs.sh` | `UnityMacPlugin` の DocC を作る。`mac/Build/MacLibrary` と `mac/Build/UnityMacPlugin` を消す（ビルドのスクリプトの archive と同じ場所）。C のヘッダーの Doxygen は macOS に無い | 0e・3・4 |
| `agent-rules/workflows/release/workflow.md` | `check_mac_dist.py` が加わる | 2b |
| `agent-rules/coding-rules/{mac,common}.md`、`scripts/check_design_consistency.py`、`scripts/README.md`、`agent-rules/workflows/`（write-manual、implement-sample-app、design-sample-app など） | ブリッジ（`UnityMacPlugin`）と Objective-C を参照している。`mac.md` にログの例外が無い | 1b（ログの規則）・3 |
| `agent-rules/device-testing.md` | iOS の実機と、シミュレーターの間の Mac のクリップボードだけを扱う。「Mac のクリップボードを読み書きしない」が macOS の Clipboard のテストとぶつかる | 0a の前（D-23） |
| `scripts/c_abi_contract_common.py`、`scripts/c_abi_error_numbers.json`、`scripts/check_c_abi_contract_ios.py`、`scripts/check_ios_dist.py` | OS ごとの定数を外へ出す（D-1）。macOS の名前を表に足すと iOS と Android の照合も流す | 2a |
| `MacLibrary` の公開 API | 0e（`@Sendable`）、0f（言語モード）、0g（bundle id）、1b（Dialog の結果の型、イベントの口、エラーの case、ブリッジのための公開の整理）で変わる。サンプルが追従する。ブリッジは 0e で外す（D-22） | 0e・0f・0g・1b |
| `unity-native-plugin` の `PreBuildProcessor`・`PostBuildProcessor`・`Tools/macOS/MacFrameworkPatcher` | 版の固定が無い（新しい dist を選んで古い 1.3.0 のまま黙って進む）、前方一致と序数の比較、development の `-debug` の戻りが無い（2 か所）、コピーで symlink を壊しうる、`Mac.xcodeproj` の書き出しが前提、main のターゲットにだけリンクする（IL2CPP の `GameAssembly`） | 次の dist の前（版の固定）・2b で dist を置く前（残りの直し）・2c |
| `artifact/topics/migration/README.md` | macOS の Swift 6 の行と「UnityMacPlugin に Clipboard が存在しない」の記述 | 0f（済んだら書き足す） |

## 6. 公開面の規模

今のブリッジの公開面（調査の結果。数え方は第 2 部で確定する）:

| 機能 | C の関数 | 入力 | 受け手が 1 つだけのもの |
|---|---|---|---|
| Clipboard | 15 | ほぼ全部 JSON。`readData` の型は文字列、監視の間隔は `double` | 監視 |
| Dialog | 6 | alert の buttons と options が JSON。ファイルのパネルは位置引数と `const char**` | ヘルプ |
| Notification | 21 | content / trigger / category が JSON。一覧と権限の状態も JSON で返す | アクション、テキスト入力、`NotificationHasPermission` |
| Share | 2 | content が JSON、`serviceName` は文字列 | - |
| 計 | 44 | | |

iOS と同じく、C ABI が置き換えるのは操作だけでなく、**次の振る舞いの集合**である。ID を付けた表は第 2 部に書き、2a の機械照合の対象にする（ID は BH / EV / RG / PR）。

| 種類 | 中身 |
|---|---|
| 操作・問い合わせ | 上の表の操作。戻り値の無い Notification の操作を完了とエラーを返す形にするか（iOS は P2-6 で完了を持つ `_async` にした）は第 2 部で決める |
| 操作の完了 | Clipboard / Notification / Share の操作の結果、Dialog のアラートと 5 種のパネルの結果 |
| 自発のイベント | Clipboard の変化、通知のアクション、通知のテキスト入力のアクション、Dialog のヘルプ |
| 登録と解除 | 上のイベントの受け手の登録（今は解除が無い）、Clipboard の監視の開始と停止、`NotificationSetup`（起動の終わりまでに delegate を入れる関数に置き換わる） |
| 追加（iOS と同じ） | 受け手の解除、起動のきっかけになった通知の取得、Dialog の取り消しと Clipboard の読み込みの要求ごとの取り消し、`openSettingsFor` のイベント |

`MacLibrary` にあるがブリッジが公開していないもの（`showOpenDialog` の 14 項目の汎用の形、Clipboard の `makePasteButton`、Share の `canPerform` など）は、iOS の D-5 と同じく 2.0.0 の C ABI に入れない（D-5）。iOS は 43 の関数から 134 の関数になった（ハンドルの読み取り関数とビルダーで増える）。

## 7. 検証方法

| 層 | 手段 | 守るもの |
|---|---|---|
| Swift の単体テスト | `MacLibraryTests`（今 308 件。`@Test` の数で、`arguments:` の展開前。Dialog は 0 件） | ライブラリの内部 |
| C ABI のテスト | `MacLibraryCApiTests`: C の関数を XCTest から呼ぶ。ASan と TSan でも流す（7.4） | iOS の 7 章と同じ（NULL と不正な入力の拒否、`struct_size`、UTF-8、全コールバックの型の main・入口の中で呼ばれない・`release` がちょうど 1 回・取り消しと再入、main を止めた状態で install のほかの全関数が待たずに戻ること、Objective-C の実行時のクラスがモジュール名で区切られていること）。加えて bundle の無いプロセスで通知の関数が落ちずにエラーを返すこと |
| ヘッダー | C99・C11・C++・Objective-C でヘッダーだけをコンパイルする。2a の照合 | 公開ヘッダーの形 |
| smoke | `MacLibraryCApiSmoke`: dist の 2 つの xcframework だけを使う C / Objective-C のアプリ。Swift のコードを持たない。ビルドする Xcode（26.6）と、利用者の下限の Xcode 26.3 で組む。arm64 と Rosetta の x86_64 で動かす。Hardened Runtime の有無と sandbox の有無の組み合わせで起動する。sandbox の C のホストで、ファイルのパネルの結果のパスを後から読めること、そのファイルを非同期の Share に渡せることを、最後の dist で確かめる（決定の文書の 8.6 で決めた契約のとおり）。**同じ Team＋Library Validation 有効を正の例、ad-hoc＋Library Validation 有効を失敗を期待する例**に分け、最後の `.app` の実効の entitlement（`disable-library-validation` が付いていないこと）と、framework とホストの署名を記録する（起動の成功だけでは検証が効いていたかが分からないため） | 配布物だけで組めて動くこと。署名し直しと Library Validation の契約（3.1）が成り立つこと |
| 配布物の照合 | `check_mac_dist.py`（7.3） | 公開シンボル、依存、symlink、署名、版 |
| 本物のホスト | Unity 6000.4.2f1 の macOS の書き出し（release ビルド）に入れて呼ぶ（1a で雛形、2c で本番）。通知のクリックでの起動も確かめる | Unity の組み込み方で動くこと |
| サンプルの UI テスト | `MacLibraryExampleUITests`（今 37 件。段階 0c で全機能に広げる） | 0e〜0g と 1b の前後で、ネイティブの利用者から見た動作が変わらないこと（D-8 などで決めて 4.1 に書いた意図した変更は除き、差は理由と期待値を記録する） |
| Dialog の間の配送 | Swift の単体テストか UI テスト（1b の後）と C ABI のテスト（2b の後）で、Dialog とパネルが開いている間に、ほかの機能の完了・イベント・取り消しが D-8 の契約のとおりに届くこと、同じ回の 2 つ目の完了がちょうど 1 回来ること | D-8 で決めた表示の契約（Swift の経路と C の入口の両方） |
| 更新のテスト | 1.14.0 のサンプル（`MacLibrary` 1.3.0）で通知を予約し、category を登録し、通知を表示しておく → 2.0.0 のサンプルを上から入れる → 予約の一覧・取り消し・発火・クリック・アクションを確かめる（`scripts/test_mac_upgrade.sh`。D-21 の環境で。起動したコピーの道を記録し、余分なコピーを外してから流す（5 章の 0a）） | 1.x が OS に保存したものが 2.0.0 で壊れないこと |
| Unity | `unity-native-plugin` の macOS のテスト（作り直す） | Unity から C ABI を通した動作。別リポジトリで行う（段階 2c） |

件数は、ランナーが報告する展開後の件数で記録する。新しく足すテストは、守る対象を壊すと落ちることを確かめる（`common.md` の「検査の書き方」）。

**全体の実行の時期**: iOS と同じく、各段を直した直後は、ビルドと単体テスト、直した所に関係するテストだけを流す。全体を流して 0d の基準と比べるのは区切り（0g の後と 1b の後）とする。macOS の UI テストはこの Mac の画面とマウス・キーボードを使うので、この Mac で流すときは時刻を利用者と決める（D-21・D-23）。

### 7.1 サンプルの UI テストで守れる範囲

iOS の 7.1 と同じ。サンプルはブリッジを通らず `MacLibrary` を直接呼んでいる。サンプルの UI テストで守れるのは、ネイティブの利用者から見た動作だけである。Unity から見た動作は前後で比べない。サンプルは段階 2 以降も Swift の API だけを使い、C ABI は使わない。

### 7.2 XCUITest と人の確認の使い分け

`common.md` の UI 自動テストの規則は、OS のシェルの UI・システム設定・権限の初回の同意を「自動化しないもの」にしている。iOS と同じく、**段階 0a で確かめて安定して扱えた項目だけを自動化し、`common.md` の例外として理由を 0a の結果に書く**。扱えない項目は computer use で画面を見て確かめ、手順書を用意する（判定があいまいなら失敗とする）。macOS では computer use が見るのはこの Mac の画面そのもので、ほかのアプリ・通知・デスクトップが写るので、毎回許可を得る（D-23）。通知の音は対象外にする（iOS・Android と同じ）。

macOS のシステムの UI（通知センター、許可の問い合わせ、共有のピッカー、ファイルのパネル）は OS の版で見た目と構造が変わるので、UI テストは版を固定した環境で流す（D-21）。

### 7.3 配布物の照合（`check_mac_dist.py`）

iOS の `check_ios_dist.py` に当たる。2b で作り、リリースの前に流す。iOS の照合と共通の部分は 2a で外へ出したものを使う。

| 項目 | 確かめ方 |
|---|---|
| 公開シンボル | 両方のアーキテクチャの `nm -gU` の `_ntk_*` が第 2 部の関数の一覧と一致し、ほかの外部シンボルを出していない |
| capi が Swift の API を出さない | capi の `Headers/` に `-Swift.h` が無く、`Modules/` に swiftmodule / swiftinterface が無い |
| 依存 | `otool -L`: capi は `@rpath/MacLibrary.framework/Versions/A/MacLibrary` と OS の framework と `/usr/lib/swift/*` だけ。`@rpath/libswift*` に依存しない。capi の中に `MacLibrary.framework` を埋め込まない |
| 終わるときの処理 | `__cxa_atexit` などを import していない |
| install name と rpath | `LC_ID_DYLIB` が `@rpath/<名前>.framework/Versions/A/<名前>`。rpath は 1a で決めたもの（`@loader_path/../../..` を足すか） |
| 版付きの構成 | `Versions/Current`・最上位の `Headers`・`Modules`・`Resources`・バイナリが symlink（実体のコピーでない）。capi の最上位の `Headers` から、1a-1 で決めた置き場の公開ヘッダーが見える |
| 版と最小 macOS | 両方のアーキテクチャの `LC_BUILD_VERSION` の minos が 15.0（plist だけで判断しない）、`LSMinimumSystemVersion` が 15.0、`CFBundleShortVersionString` が 2.0.0、bundle id が D-12 のとおり。2 つの framework の版が同じ |
| 署名 | D-18 のとおり。Authority と TeamIdentifier が無い。リンカーの ad-hoc の署名（`linker-signed`）だけを許す（arm64 はリンカーが必ず署名する） |
| ヘッダー | `include/NativeToolkitC/` と、capi の中の 1a-1 で決めた置き場（第一の案は `Headers/NativeToolkitC/`）が同じ |
| スライス | `macos-arm64_x86_64` の 1 つで、両方のアーキテクチャを持つ |

### 7.4 アーキテクチャとサニタイザーで確かめられる範囲

| アーキテクチャ | 環境 | 確かめられること |
|---|---|---|
| arm64 | この Mac（macOS 26.3、Apple M1）と、D-21 で決める環境 | C ABI のテスト（ASan、TSan。同時には使えないので別に流す）、UI テスト、smoke、Unity |
| x86_64 | この Mac の Rosetta | 組めること、公開シンボル、smoke の実行、C ABI のテスト（通常。サニタイザーは 1a で試す） |

サニタイザーの回も 7.5 の区分に従う（ホストが要る C ABI のテストを ASan・TSan で流す回は、この Mac では回ごとに許可を得る）。

iOS と違い、macOS は TSan をこの Mac の上で流せる見込み（iOS の実機は TSan に対応していなかった）。1a で確かめる。

### 7.5 テストの環境と私物の Mac

macOS のテストは、利用者が今使っているこの Mac の上で、本物の通知センター、本物の一般の貼り付け板、本物の共有のサービス、本物のファイルシステムに触れる。iOS の「シミュレーターでいつでも流し、私物の端末は区切りで許可」という分け方が、そのままでは成り立たない。D-21（環境）と D-23（規則）で決める。

| 区分 | 例 | 扱い（案。D-23） |
|---|---|---|
| 私物に触れない単体テスト | `MacLibraryTests` のうち、名前付きか unique の貼り付け板だけを使い、通知センターと本物の共有のサービスに届かないもの。C ABI のテストのうち純粋な検査（NULL、`struct_size`、UTF-8、ハンドル。bundle の無い xctest で流す） | 許可なしで流す。触れないことを宣言と照合で守る。ただし宣言の前に、テストの本文とホストのアプリの起動の処理を、本物の `NSSharingService`・一般の貼り付け板・通知センターに届きうる経路で洗う。固定の待ちに頼るもの（`SharePickerPresenterTests` の 50 ms。外れると本物のメールの作成を開きうる）は 0d で直すか、下の区分にする |
| 私物に触れるテスト | 一般の貼り付け板を読む・書く・消す、通知を出す・許可を求める、Share のサービスを開く、保存のパネルでファイルを書く、Dock のバッジ、サンプルのアプリを起動する単体テスト。C ABI のテストのうちホストが要るもの（通知・Dialog・Share・一般の貼り付け板。通常・ASan・TSan の 3 回） | 毎回の許可（`--dry-run` で一覧・起きること・準備・時間を示し、`--approved` で流す。iOS の実機と同じ仕組み）。D-21 の VM のうち、D-23 の資格の条件を満たすものの中では許可なし |
| 画面を使うテスト | UI テスト、`--capi-ui`、人の確認 | この Mac では毎回の許可と時刻の取り決め。テストの間は利用者がマウスとキーボードに触れない。結果のスクリーンショットに私物が写るので、書き写したら消す |

テストのコードは、一般の貼り付け板でなく名前付きか unique の貼り付け板を既定にする（名前付きの貼り付け板は貼り付け板のプライバシーの確認の対象外。Apple の SDK のヘッダー）。一般の貼り付け板を使うテストは区分を宣言し、内容を退避して戻すこと（読むことになる）はしない。agent が `pbcopy`・`pbpaste` などで Mac のクリップボードを直接読み書きしない今の規則は残し、許可を得たランナーを通したテストの実行だけを例外にする（D-23）。

VM の中を許可なしにするのは、VM が隔離されている場合だけである（個人のアカウントでサインインしていない、ホストとのクリップボードとフォルダーの共有が無い、合成のデータだけを使う、実のサービスへ送らない。D-23）。ビルドの Xcode 26.6 は macOS 26.2 以上、利用者の下限の 26.3 は 15.6 以上でしか動かない。macOS 15 の VM の中で Xcode を動かすなら 15.6 以上の 26.3 になり、15.0〜15.5 は Xcode が動かないので、どちらの場合も組むのはホストで、VM では流すだけにする（D-21）。
