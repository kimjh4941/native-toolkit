# 調査 A: macOS の今の公開面（`macos-c-abi` の企画の 1 章の材料）

> この記録は、企画（`../plans/2026-11-22-macos-c-abi-plan.md`）のための調査の全文を、scratchpad から写したもの（2026-11-22）。写すときに、利用者の氏名・証明書の ID・Team ID を `<氏名>`・`<証明書の ID>`・`<Team ID>` に、scratchpad の道を `<scratchpad>` に置き換えた。試作と生成物は scratchpad に残し、リポジトリには入れていない。日付の記録として本文は直さない

- 調べた日: 2026-11-22
- 対象: `native-toolkit` の `feature/NTKIT-19`（HEAD `1bd0f118`）と `unity-native-plugin`（HEAD `e16a76c`）。どちらも読むだけ。ビルドは 1 回だけ、DerivedData を scratchpad に向けて行った（6.3）
- 粒度の手本: `artifact/topics/ios-c-abi/README.md` の 0 章・1 章（13〜97 行目）
- 表記: **[事実]** はコードを読んだか、コマンドで確かめたもの。**[推測]** は確かめていないもの（理由を添える）。断りのない表の中身は [事実]
- 数え方の道具（scratchpad の `survey/tools/`）: `pbx.py`（pbxproj の設定をターゲットに対応させる）、`nm_unity_mac.txt`（dist の C 関数の一覧）、`strict-build.log` / `strict-warnings.txt`（6.3 のビルド）

---

## 0. 要点

1. macOS にも C の関数は既にある。`UnityMacPlugin.framework` の Objective-C の `.m` に **44 個**（Clipboard 15、Dialog 6、Notification 21、Share 2）。dist の `nm -gU` も 44 個、`unity-native-plugin` の `DllImport("__Internal")` も 44 本で一致する。Unity 専用の形で、`user_data`・`release` が無く、接頭辞が無く、公開ヘッダーに入っていない（iOS の 1.1 と同じ状況）
2. migration の README の「UnityMacPlugin に Clipboard が存在しない」（`artifact/topics/migration/README.md:243`）は**古い**。今は Clipboard のブリッジ（15 関数、JSON 解析 479 行）がある
3. スレッドは iOS より揃っている: Clipboard・Share・Notification の結果は main。ただし Dialog は検証の失敗を**呼び出し元のスレッドで同期的に**返し、Notification も JSON の解析の失敗を同期的に返す
4. Dialog に大きめの不備: ヘルプボタンを押すと**完了が 2 回**呼ばれる経路、ヘルプの受け手が共有の 1 つ、ブリッジが `message` などの `NULL` を確かめずに `stringWithUTF8String:` に渡す（C# は `message` に null を渡しうる）、コールバックの `NULL` も確かめない
5. dist の 2 つの xcframework は **dynamic の versioned framework だが、symlink が全部実体に置き換わっている**（ビルドのスクリプトの `rsync -aL`）。そのため `codesign --verify` が両方とも失敗する。さらに `UnityMacPlugin.framework` は自分の中に `MacLibrary.framework` を**埋め込んで**いて、それは単体の `MacLibrary` と別のバイナリ（ハッシュが違う）
6. 署名は個人の Apple Development の証明書（Team `<Team ID>`）、hardened runtime なし、bundle id は `mac.library.MacLibrary.MacLibrary` と `unity.mac.plugin.UnityMacPlugin`（持っていない逆 DNS）。プライバシーマニフェストは無い
7. strict concurrency を complete にすると警告 172 件（`MacLibrary` 165: Dialog 100、Notification 52、Share 13。`UnityMacPlugin` 7）。Clipboard は 0 件。全ターゲットが Swift 5.0 の言語モード
8. テスト: Dialog のテストはどのターゲットにも 0 件。Notification の UI テストも 0 件。ブリッジの C 関数を呼ぶテストは 0 件（Clipboard のブリッジのテストはソースの文字列を照らすだけ）。macOS のテストのスクリプトと基準は無い
9. `unity-native-plugin` の macOS は `VERSION.txt` で固定しておらず、dist の最新版を選び、xcframework は `unity-mac-native-toolkit-` の前方一致と**序数の文字列比較**で選ぶ（`capi` を足すとそちらが選ばれる）。Mac.xcodeproj の書き出しを前提にしている

---

## 1. `UnityMacPlugin` の C 関数

### 1.1 一覧と数

数え方: `grep -cE '^(void|bool|BOOL|const char|int|char) [a-zA-Z]+\(' */*Bridge.m`（複数行の宣言も先頭行で数える）と、dist の `nm -gU -arch arm64|x86_64` の `T` から Swift・Objective-C の記号を除いたもの。両方 44。

| 機能 | 数 | 名前（宣言の場所） | 入力の形 |
|---|---|---|---|
| Clipboard | 15 | `clipboardCopy`、`clipboardAppend`、`clipboardRead`、`clipboardReadData`、`clipboardSnapshot`、`clipboardClear`、`clipboardCreatePasteboard`、`clipboardDetectPatterns`、`clipboardDetectValues`、`clipboardDetectMetadata`、`clipboardAccessBehavior`、`clipboardCheckForegroundChange`、`clipboardRemovePasteboard`、`clipboardStartObserving`、`clipboardStopObserving`（`Clipboard/UnityMacClipboardManagerBridge.m:40〜238`） | ほぼ全部 JSON（content / options / scope / ownership / request / patterns / matchingTypes）。`readData` の `utType` は文字列、`startObserving` の `intervalSeconds` は `double` |
| Dialog | 6 | `showDialog`、`showFileDialog`、`showMultiFileDialog`、`showFolderDialog`、`showMultiFolderDialog`、`showSaveFileDialog`（`Dialog/UnityMacDialogManagerBridge.m:32〜374`） | `showDialog` は buttons と options が JSON（iOS の Dialog は位置引数だった）。ファイル系は位置引数と `const char**` + 個数 |
| Notification | 21 | `NotificationSetup`、`NotificationRequestPermission`、`NotificationGetAuthorizationStatus`、`NotificationOpenSettings`、`NotificationShow`、`NotificationUpdate`、`NotificationSchedule`、`NotificationCancelScheduled`、`NotificationCancelAllScheduled`、`NotificationGetScheduled`、`NotificationGetDelivered`、`NotificationRemoveDelivered`、`NotificationRemoveAllDelivered`、`NotificationRegisterCategory`、`NotificationRemoveCategory`、`NotificationSetActionReceivedCallback`、`NotificationSetTextInputActionReceivedCallback`、`NotificationHasPermission`、`NotificationCancel`、`NotificationCancelAll`、`NotificationSetBadgeCount`（`Notification/UnityMacNotificationManagerBridge.m:13〜263`） | content / trigger / category が JSON。結果の一覧と権限の状態も JSON の文字列で返す |
| Share | 2 | `shareContent`、`shareViaService`（`Share/UnityMacShareManagerBridge.m:20, 42`） | content が JSON。`serviceName` は文字列 |

### 1.2 汎用の C ABI に足りないこと（iOS の 1.1 の表に合わせた）

| 項目 | 今の形 | 足りないこと |
|---|---|---|
| 入力 | Clipboard・Notification・Share・Dialog の alert が JSON | 型が無い。`unity-native-plugin` の macOS の Builder / Parser / Reader は計 1,946 行（8.2） |
| コールバック | C の関数ポインタ。`user_data` も `release` も無い。Notification のアクション 2 つ（`MacNotificationManager.onActionReceived` / `onTextInputActionReceived`、`MacNotificationManager.swift:52, 56`）は 1 つずつしか持てず、上書きされる。`NotificationHasPermission` は static の変数 `s_hasPermissionCallback` 1 つ（`UnityMacNotificationManagerBridge.m:225〜236`）で、重ねて呼ぶと前の受け手が上書きされる（iOS の 1.4 と同じ不備）。Clipboard の監視の受け手も 1 つ（`ClipboardChangeMonitor` の `onEvent`、`ClipboardChangeMonitor.swift:39`） | どの要求の完了か、いつ片付けてよいかが分からない |
| 文字列の寿命 | `NSString.UTF8String` をコールバックの間だけ貸す。ヘッダーに「Valid only during the callback invocation — copy immediately」（`UnityMacNotificationManagerBridge.h:22` ほか）、Dialog は「Valid only during the call」（`UnityMacDialogManagerBridge.h:23, 33`）。Dialog のファイルの配列は `malloc` した `const char**` をコールバックの後に `free`（`UnityMacDialogManagerBridge.m:125〜137`） | 所有権ごと渡し、受け手が `_free` する規約と逆 |
| ヘッダー | `*Bridge.h` 4 つは framework の公開ヘッダーに入っていない。pbxproj の `publicHeaders` は `UnityMacPlugin.h` だけ（`UnityMacPlugin.xcodeproj/project.pbxproj:48〜49`）。dist の `Headers/` も `UnityMacPlugin.h` と `UnityMacPlugin-Swift.h` だけ | 利用者は宣言を自分で書くしかない |
| 名前 | 接頭辞なし。しかも**大文字小文字が機能で揃っていない**: Clipboard は `clipboard*`、Dialog は `show*`、Share は `share*`（小文字始まり）、Notification だけ `Notification*`（大文字始まり）。iOS の旧ブリッジの名前（`clipboardCopy`、`showDialog` など）とも重なる | `ntk_*` に合わない。同じプロセスに iOS の旧ブリッジは載らないので衝突は起きない（[推測]: macOS と iOS のバイナリは別） |
| 引数の `NULL` | Clipboard は `NTStr` で `NULL` を `nil` に直す（`...ClipboardManagerBridge.m:13〜15`）。Notification は `NULL` を `""` か `"{}"` に直す。**Dialog と Share は確かめずに `stringWithUTF8String:` に渡す**（Dialog: `m:39〜42, 95〜96, 101, 158〜159, 164, 217〜218, 268〜269, 331〜333, 338`、Share: `m:24, 46〜47`） | 必須でない引数（C# の `string? message` など）で例外になりうる（3.4） |
| コールバックの `NULL` | Clipboard と Share は確かめて呼ぶ。Notification は操作ごとに `NULL` なら何もせず戻る（`m:22〜25` ほか）。**Dialog は確かめずに呼ぶ**（`m:58, 60, 65, 132, 135, 141` ほか） | |

Unity のシンボル（`UnitySendMessage`、`UnityGet*`）への依存は 0（`grep -rcE 'UnitySendMessage|UnityGet' UnityMacPlugin/UnityMacPlugin` の合計 0）。**[事実]**

`MacLibrary` そのものは C の関数を出していない（dist の `MacLibrary` の `nm -gU` の `T` から Swift・Objective-C の記号を除くと 0）。

### 1.3 Swift の側の形

| 機能 | Swift の façade | 形 |
|---|---|---|
| Clipboard | `UnityMacClipboardManager`（`@objcMembers`、`@unchecked Sendable`、`UnityMacClipboardManager.swift:32`） | handler は `@Sendable`。すべて `Task { @MainActor }` を通す（`:53〜104`）。migration の案 C が入っている |
| Dialog | `UnityMacDialogManager`（`UnityMacDialogManager.swift:29`） | `(NSDictionary?, NSError?)` の completion。`NSError` の code は操作の種類で 0〜3 の固定、domain は `"DialogError"`（`:154, 193, 268, 347`） |
| Notification | `UnityMacNotificationManager` | `(Bool, Int, String?)` などの completion |
| Share | `UnityMacShareManager`（`UnityMacShareManager.swift:29`） | `(Bool, Bool, String?, String?)` |

---

## 2. ブリッジにしか無いロジック（ネイティブの利用者に届かないもの）

iOS と同じく、多くは既に `MacLibrary` にある（通知の delegate、Clipboard の 20 のエラー、Share の 9 のエラーと番号、Notification の 13 のエラーと番号、Share のアンカーの解決、Dialog の既定のボタンの検証）。ブリッジにしか無いのは次のもの。

| 機能 | ブリッジにしか無いもの |
|---|---|
| 共通 | JSON の形式と解析・組み立て: Clipboard 479 行（`UnityMacClipboardJsonParser.swift`）、Notification 211 行（`UnityMacNotificationJsonParser.swift`）、Share 59 行（`UnityMacShareJsonParser.swift`）、Dialog は façade の中の 52 行（`UnityMacDialogManager.swift:85〜136`）。数え方: `grep -c ''`（空行・コメント込み）。C ABI では型にするので移さずに捨てる見込み。なお Dialog のアイコンの JSON の解析 `IconConfiguration.from(json:)`（`MacLibrary/Dialog/IconConfiguration.swift:94〜147`）は **`MacLibrary` の public API に入っている**（ブリッジ用のものがライブラリに漏れている） |
| 共通 | `BridgeError`（1301 / 1302）は `MacLibrary` の `Notification/Domain/Error/BridgeError.swift` に public で置かれ、Clipboard のブリッジも使う。ブリッジの規約がライブラリの公開面にある |
| Clipboard | main actor への受け渡し（`MacClipboardManager` は `@MainActor`）。引数の欠落（1302）と不正（1301）の分類（`UnityMacClipboardManager.swift:83〜88`）。結果を JSON にできなかったときの `unknown` への置き換え（`:61〜69`）。`createPasteboard` のコールバックが `NULL` なら何もしない規則（`...Bridge.m:126〜129`） |
| Dialog | `alertStyle` の文字列から `NSAlert.Style` への変換（知らない値は informational）。結果の正規化: ヘルプを押したら `buttonTitle = NULL`・`buttonIndex = -1`（`...Bridge.m:56〜58`）、ファイル系のキャンセルで `fileCount = -1`（`:132`。ヘッダーの文書は「0 if cancelled」と書いており食い違う。`...Bridge.m:80`）。エラーを `localizedDescription` の文字列 1 つにする |
| Notification | 予約済み・表示済みの一覧の JSON 化（予約済みは trigger を落とす。`UnityMacNotificationJsonParser.swift:158〜173`）、表示済みの日時の ISO 8601 化（`:182`）、権限の状態の文字列化（`:195〜210`）、`hasPermission`（authorized か provisional なら true。`UnityMacNotificationManager.swift:299〜310`）、`cancel` / `cancelAll` を `cancelScheduled` / `cancelAllScheduled` の別名にすること（`:189〜199`） |
| Share | 要素の種類（text / url / image / file）から `ShareItem` への変換。知らない種類と `value` の無い要素は黙って捨てる（`UnityMacShareJsonParser.swift:37〜48`） |

どちらにも無いもの:

- 安定したエラーの番号のうち、**Dialog は型はあるが番号が無い**: `DialogError` は `noButtons`・`invalidConfiguration(String)`・`executionFailed(String)` の 3 つ（`MacDialogManager.swift:15〜18`）。`errorCode` が無く、ブリッジは文字列しか返さない
- 任意の `Error` を持つ case: `ShareError.presentationFailed(Error)`・`unknown(Error)`（`ShareError.swift:34, 37`）、`NotificationDomainError` の 8 つ（`permissionRequestFailed`・`addFailed`・`removeFailed`・`queryFailed`・`setBadgeFailed`・`openSettingsFailed`・`unknown` が `underlying: Error`。`NotificationDomainError.swift:20, 30〜40`）。`common.md` の「system の `Error` を Domain に保持しない」に反する（iOS の 1.4 と同じ）。`ClipboardError`（20 case）と `DialogError` は `String` だけで、この不備は無い
- 受け手が登録される前に届いた通知のイベントを保つ仕組み（`didReceive` は受け手が無ければ捨てる。`MacNotificationManager.swift:362〜368`）。コールドスタートのタップの扱いも無い（iOS 2.0.0 の `get_launch_response` に当たるもの）
- 通知のイベントの複数の受け手、Clipboard の監視の複数の受け手

---

## 3. コールバックを返すスレッド

| 機能 | 今のスレッド | 根拠 |
|---|---|---|
| Clipboard | main（全経路が `Task { @MainActor }`。引数の誤りも同じ）。監視のイベントも main（`ClipboardChangeMonitor` は `@MainActor`） | `UnityMacClipboardManager.swift:53〜104`、`ClipboardChangeMonitor.swift:16` |
| Share | main（`MacShareManager` が `Task { @MainActor }`、ブリッジの JSON の失敗も `DispatchQueue.main.async`） | `MacShareManager.swift:99, 123`、`UnityMacShareManager.swift:57, 80` |
| Dialog | 表示と結果は main（`DispatchQueue.main.async` の中で `runModal`）。**ただし検証の失敗は呼び出し元のスレッドで同期的に返る**: `showDialog` の空のタイトル・ボタンなし・既定のボタンが 2 つ以上・アイコンの検証の失敗、`showOpenDialog`（ファイル・フォルダー系 4 つ）の空のタイトル。`showSaveFileDialog` は空のタイトルを確かめない | `MacDialogManager.swift:310〜318, 320, 355〜358, 361, 507, 790〜817` |
| Notification の操作の結果 | main（`MacNotificationManager` がすべて `DispatchQueue.main.async` で包む。古い OS の失敗も main）。**ただしブリッジの JSON の解析の失敗は呼び出し元のスレッドで同期的に返る**（`show`・`update`・`schedule`・`registerCategory`） | `MacNotificationManager.swift:104, 164, 184, 204, 231, 246, 277, 292, 328`、`NotificationPermissionHelper.swift:36, 50, 63`、`UnityMacNotificationManager.swift:105〜107, 133〜135, 165〜167, 267〜269` |
| Notification のアクション | `didReceive` から `DispatchQueue.main.async` で main に移して呼ぶ | `MacNotificationManager.swift:362, 366` |
| 戻り値の無い Notification の操作 | `cancelScheduled`・`cancelAllScheduled`・`removeDelivered`・`removeAllDelivered`・`cancel`・`cancelAll` は完了が無い（呼んだら終わり） | `UnityMacNotificationManagerBridge.m:117〜126, 154〜163, 240〜249` |

iOS（1.3）との違い: iOS は Notification の結果に main の保証が無かったが、macOS は main に揃っている。同期で返る経路は macOS にもある（Dialog の検証、Notification の解析の失敗）。

[推測] Dialog は `runModal`（アプリモーダル）なので、表示の間は main の run loop が modal のモードで回り、Unity のプレイヤーループ（default モードで回る見込み）が止まる。Unity の macOS で確かめていない。

---

## 4. `MacLibrary` の公開 API の形

### 4.1 機能ごと

| 機能 | 入口 | `@MainActor` | 完了の型 | エラーの型 |
|---|---|---|---|---|
| Clipboard | `MacClipboardManager.shared`（`MacClipboardManager.swift:61〜67`） | **付いている**（クラスごと） | 操作ごとに `async throws` と callback の 2 形（callback は `@MainActor (Bool, T?, Int, String?)`、`:15, 19`）。16 操作: copy、append、read、readData、snapshot、clear、createPasteboard、removePasteboard、detectPatterns、detectValues、detectMetadata、accessBehavior（同期 throws）、startObserving（同期 throws + イベント）、stopObserving、checkForegroundChange（同期 throws）、makePasteButton（SwiftUI の `PasteButton`。ブリッジには無い） | `ClipboardError` 20 case（1501〜1599）。任意の `Error` なし |
| Dialog | `MacDialogManager.shared`（`NSObject`、`MacDialogManager.swift:282`） | 付いていない | `Result<DialogResult / OpenDialogResult / SaveDialogResult, DialogError>` の callback（任意。`nil` 可）。`async` 形は無い。7 操作: `showDialog`、`showOpenDialog`（`OpenDialogOptions` 14 項目。ブリッジには無い）、`showFileDialog`、`showMultiFileDialog`、`showFolderDialog`、`showMultiFolderDialog`、`showSaveFileDialog` | `DialogError` 3 case、番号なし |
| Notification | `MacNotificationManager.shared`（`NSObject`、`MacNotificationManager.swift:36`） | 付いていない | `Result<T, NotificationDomainError>` の callback。`async` 形は無い | `NotificationDomainError` 13 case（1001〜1999）。うち 7 case が任意の `Error` を持つ |
| Share | `MacShareManager.shared`（`MacShareManager.swift:49`） | 付いていない（内部の `SharePickerPresenter` の 3 つの入口が `@MainActor`） | `async throws -> ShareResult`（`share(content:)`・`shareViaService`・`canPerform`）と、ブリッジ向けの callback `(Bool, Bool, String?, String?)` の 2 形 | `ShareError` 9 case（1401〜1499）。2 case が任意の `Error` |

`NotificationPermissionHelper`・`NotificationRepositoryImpl`・各 UseCase のクラスも `public`（Clean Architecture の内側が公開面に出ている。`NotificationRepositoryImpl.swift:18`、`NotificationCategoryUseCases.swift:9` など）。

### 4.2 通知の delegate

- `setup()` は `UNUserNotificationCenter.current().delegate = self` を**無条件に上書き**し、前の delegate を保たず転送もしない（`MacNotificationManager.swift:91〜94`）
- `willPresent` は**すべての通知**に `[.list, .banner, .sound, .badge]` で応える（`:338〜345`）。ホスト（Unity の通知パッケージ、Firebase など）の通知も含む
- `didReceive` は userInfo を `JSONSerialization.data(withJSONObject:)` に `try?` で渡す（`:358`）。`isValidJSONObject` で先に確かめていない（iOS の 1.4 と同じ。NSException は `try?` で止まらない）。[推測] ライブラリ自身の通知は `[String: String]` なので落ちないが、他の発行元の通知では落ちうる
- 受け手は 1 つずつ（4.1）。サンプルのアプリは `init` で `setup()` と 2 つの受け手を入れている（`MacLibraryExampleApp.swift`）

### 4.3 Dialog の結果の返し方と完了の不備

- 結果: `DialogResult`（buttonIndex、buttonTitle、suppressionButtonState、helpButtonPressed、isSuccess）。`OpenDialogResult` / `SaveDialogResult` は `fileCount`・`directoryURL`（文字列）・`isCancelled`・`isSuccess` を持つ。キャンセルは成功（`isSuccess = true`、`isCancelled = true`）として返る（`MacDialogManager.swift:772〜782`）
- **ヘルプのボタンで完了が 2 回呼ばれる**: `showsHelp` のとき `alert.delegate = self` にし（`:624〜630`）、`alertShowHelp` が `helpButtonHandler`（= completion）を `helpButtonPressed = true` で呼んで `true` を返す（`:820〜835`）。アラートは閉じないので、利用者が後でボタンを押すと `runModal` が返り、同じ completion がもう一度呼ばれる（`:666, 328`）。コードを読んだ結果で、実機では確かめていない
- `helpButtonHandler` はシングルトンの 1 つのプロパティで、片付けない（`:289, 327`）。重ねて表示すると前の受け手が上書きされる [推測: `runModal` が入れ子になれば起きる]
- 完了が来ない経路: コードの上では見つからなかった（`[weak self]` は `shared` なので解放されない）。ただし completion は任意（`nil` 可）
- ボタンが 4 つ以上のときの番号は `rawValue` の差で出す（`:687〜699`）。[推測] `NSAlert` の 4 つ目以降の戻り値が連番である前提
- `DialogOptions.accessoryView: NSView?`（`:77`）は C に出せない

### 4.4 Share のピッカーの完了

- `didChoose(nil)` でキャンセル、`didShareItems` で完了、`didFailToShareItems` の `NSUserCancelledError` でキャンセル、それ以外は `presentationFailed(error)`（`SharePickerPresenter.swift:172〜202`）
- continuation は 1 つで、使用中は `alreadyInProgress` を投げる（`:77〜80, 99〜102`）
- アンカーは `NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView` の `bounds` 全体、辺は `.minY` 固定（`:91, 141`）。利用者が基点（ビュー・矩形）を渡す口が無い
- `show(...)` は mouseDown の中で呼ぶ必要があり、`Task { @MainActor }` を挟むので保証されない、と自身の文書が書いている（`MacShareManager.swift:24〜34`）。ネイティブの Swift の経路は実クリックで確かめ済み、Unity のブリッジ経由は範囲外として残っている（`artifact/macos/share/results/2026-07-11-macos-share-implement-sample-app-result-v1.md:154`）
- [推測] サービスを選んだ後、そのサービスが `NSSharingServiceDelegate` の `didShareItems` も `didFailToShareItems` も呼ばない場合、continuation が戻らず、以後の Share がすべて `alreadyInProgress` になる。どのサービスでそうなるかは確かめていない
- `serviceName` は `NSSharingService.title`（表示名で、地域化されうる）。除外も title の一致（best-effort。`:163〜170`）

### 4.5 Notification のその他の不備

- `update(identifier:...)` は `identifier` を使わず `content.id` で追加する（`NotificationDispatchUseCases.swift:78〜91`）。iOS の「`content.id` が schedule と update で使われない」と逆向きの不整合
- category はメモリの配列 `registeredCategories` に持ち、`setNotificationCategories` で**全体を置き換える**（`NotificationCategoryUseCases.swift:13, 38〜41, 60〜61`、`NotificationRepositoryImpl.swift:136〜140`）。ホストが登録した category を消す。今の一覧を読まない。配列に排他が無く、並行に呼ぶと競合しうる [推測: 呼び出し元のスレッドで走るので]
- `registerCategory` は登録が終わる前に成功を返す（`setNotificationCategories` は戻り値なし）
- `cancel` と `cancelScheduled`、`cancelAll` と `cancelAllScheduled` が同じ処理（ブリッジ）
- 古い OS の確かめ（`guardOS`）が無い操作: `cancelScheduled`・`cancelAllScheduled`・`removeDelivered`・`removeAllDelivered`・`registerCategory`・`removeCategory`。最小 macOS が 15.0 なので実害は無い。`setBadgeCount` の 15 未満の分岐（Dock のバッジ）は届かないコード（`NotificationRepositoryImpl.swift:160〜165`）
- `NotificationRepositoryImpl` の各 completion は `[weak self] guard let self else { return }` で、解放されていれば completion を呼ばない（`:36` ほか）。[推測] UseCase が強く持つので実際には起きない

### 4.6 ログ

- `Log` は `os.Logger`（subsystem `com.unity.native.toolkit`、category `NativeToolkit`）で、**すべて `privacy: .public`**（`Common/Log.swift:27, 39〜43`）。`#if DEBUG` が無いので Release でも出る（`.debug` は既定では保存されないが、`log stream --level debug` などで見える [推測: OS の既定の挙動]）。`print` ではない
- `Log` は `@objcMembers public class` で、**`MacLibrary` の公開 API に入っている**
- 秘密の値を出している箇所: Notification のテキスト入力の返信（`UnityMacNotificationManagerBridge.m:218`）、通知の content の JSON の全文（`UnityMacNotificationManager.swift:101, 161`）、Share の content の JSON の全文（`UnityMacShareManagerBridge.m:21, 43〜44`、`UnityMacShareManager.swift:54, 77`、`UnityMacShareJsonParser.swift:28`）、Dialog のファイルのパス（`UnityMacDialogManagerBridge.m:122, 185, 236, 287, 360`、`MacDialogManager.swift:587`）、Dialog のタイトル・本文・buttons と options の JSON（`...Bridge.m:37`）、アイコンの JSON（`IconConfiguration.swift:95`）
- Clipboard だけは伏せている（`ClipboardLog`、ブリッジの `NTLen`・`NTScope`。`...ClipboardManagerBridge.m:17〜38`）。`ClipboardLogAuditTests`（3 件）がある
- `agent-rules/coding-rules/mac.md:14` は「全パラメータを含むログを必ず入れる」で、秘密の値を伏せる例外が無い（`ios.md:18, 44` にはある）

### 4.7 プライバシーマニフェストと required reason API

- `PrivacyInfo.xcprivacy` は `mac/` のどこにも無い（`find . -name '*.xcprivacy' -not -path '*/Build/*'` が 0 件）。dist の framework にも無い
- required reason API の使用: `grep -rnE 'contentModificationDate|creationDate|fileModificationDate|systemUptime|mach_absolute_time|UserDefaults|volumeAvailableCapacity|activeKeyboards|attributesOfItem|\.modificationDate|ProcessInfo'` が `MacLibrary`・`UnityMacPlugin` の両方で 0 件。iOS の Clipboard にあった一時ファイル（`ClipboardTemporaryFileStore`）は macOS には無い。`FileManager` は Share の `fileExists(atPath:)` だけ（`ShareItemConverter.swift:39`）。[推測] `fileExists` は required reason API に当たらない。macOS のアプリでプライバシーマニフェストが要るかは別に確かめる（App Store の要件は iOS が中心）

### 4.8 イベントの受け手の数

| イベント | 受け手 |
|---|---|
| 通知のアクション | 1（`onActionReceived`） |
| 通知のテキスト入力 | 1（`onTextInputActionReceived`） |
| Clipboard の変化 | 1（監視は 1 セッション。`startObserving` を呼び直すと置き換わる） |
| Dialog のヘルプ | 1（`helpButtonHandler`） |

---

## 5. `dist/1.14.0/mac` の実物

`dist/1.14.0/mac` は `dist/1.13.0/mac` と中身が同じ（`diff -rq` で差なし）。git には 108 ファイルが全部 `100644` で入っている（`git ls-files -s`）。最後に入れたコミットは `3aeeaf3c`。

| 項目 | `mac-native-toolkit-1.3.0.xcframework` | `unity-mac-native-toolkit-1.3.0.xcframework` |
|---|---|---|
| スライス | `macos-arm64_x86_64` の 1 つ（Info.plist） | 同じ |
| `file` / `lipo -info` | Mach-O universal（x86_64、arm64）、dynamically linked shared library | 同じ |
| static / dynamic | dynamic の versioned framework（`Versions/A`） | 同じ |
| `otool -L` | `@rpath/MacLibrary.framework/Versions/A/MacLibrary`。Foundation、AppKit、**SwiftUI**、UserNotifications、Swift の標準の dylib | `@rpath/UnityMacPlugin...` と **`@rpath/MacLibrary.framework/Versions/A/MacLibrary`**、Foundation、CoreFoundation、Swift の dylib |
| C 関数（`nm -gU`） | 0 | 44（arm64・x86_64 とも） |
| `codesign -dvv` | `Apple Development: <氏名> (<証明書の ID>)`、TeamIdentifier `<Team ID>`、`flags=0x0(none)`（**hardened runtime なし**）、2026-09-03 署名 | 同じ証明書・Team、`flags=0x0(none)` |
| `codesign --verify --deep --strict` | **失敗**: `a sealed resource is missing or invalid` | **失敗**: `bundle format is ambiguous (could be app or framework)`（中の MacLibrary） |
| xcframework そのもの | 署名なし（`code object is not signed at all`） | 同じ |
| bundle id | `mac.library.MacLibrary.MacLibrary` | `unity.mac.plugin.UnityMacPlugin` |
| 版 | `CFBundleShortVersionString` 1.3.0、`CFBundleVersion` 11 | 1.3.0、10 |
| 最小 macOS | `LSMinimumSystemVersion` 15.0 | 15.0 |
| SDK / Xcode | macosx26.2、DTXcode 2630 | 同じ |
| 中身 | Headers（umbrella と `-Swift.h`）、Modules（swiftinterface を含む。`BUILD_LIBRARY_FOR_DISTRIBUTION=YES`） | 同じ形に加えて **`Frameworks/MacLibrary.framework` を埋め込む** |

### 5.1 symlink が無い

- `find dist/1.14.0/mac -type l` が 0 件。`MacLibrary.framework/MacLibrary`、`Versions/Current/...`、`Headers` などが全部実体のコピーになっている（同じハッシュのファイルが 3 か所。`shasum`）
- 原因: `scripts/build_xcode26_library_xcframework.sh:376` の `rsync -aL`（`-L` は symlink をたどって実体をコピーする）。xcode16 の版は `xcodebuild -create-xcframework -output` で直接書く（`build_xcode16_library_xcframework.sh:388`）ので symlink は残る見込み [推測: 走らせていない]
- 結果として `codesign --verify` が失敗する（上の表）。[推測] macOS の versioned framework は `Versions/Current` が symlink であることを前提にしており、アプリに埋め込んで署名し直すとき、または Gatekeeper / notarization で問題になりうる。Unity の書き出した Xcode プロジェクトでの再署名は確かめていない

### 5.2 `MacLibrary` が 2 つ

- `UnityMacPlugin.framework/Frameworks/MacLibrary.framework` のバイナリのハッシュは `ae003c6d...`、単体の `MacLibrary.framework` は `b760814c...` で、**別のビルド**（`CFBundleVersion` も 10 と 11 で違う。署名の時刻も 13:50:26 と 13:51:08）
- 埋め込みは `build_xcode26_library_xcframework.sh:284〜295` が MacLibrary の archive の framework を UnityMacPlugin の archive に `ditto` で置き、UnityMacPlugin の pbxproj の「Embed Frameworks」（`CodeSignOnCopy, RemoveHeadersOnCopy`。`project.pbxproj:11`）が中に入れる
- `unity-native-plugin` は `unity-mac-...` だけをコピーする（8.3）ので、Unity のアプリは埋め込まれた方を使う。[推測] 両方を同じアプリに入れると `@rpath` の解決順でどちらかが選ばれ、Objective-C のクラスが重複する

### 5.3 プロジェクトの設定（`survey/tools/pbx.py` で target ごとに読んだ）

| ターゲット | 最小 macOS | Swift | strict concurrency | bundle id | 署名 |
|---|---|---|---|---|---|
| MacLibrary | 15.0（project 既定は 15.1） | 5.0 | 未設定 | `mac.library.MacLibrary.MacLibrary` | Automatic、Team `<Team ID>` |
| MacLibraryTests | 15.1（project 既定） | 5.0 | 未設定 | `mac.library.MacLibrary.MacLibraryTests` | 同 |
| UnityMacPlugin | 15.0（project 既定は 15.1） | 5.0 | 未設定 | `unity.mac.plugin.UnityMacPlugin` | 同 |
| UnityMacPluginTests | 15.1 | 5.0 | 未設定 | `unity.mac.plugin.UnityMacPluginTests` | 同 |
| MacLibraryExample | 15.0 | 5.0 | 未設定 | `com.jonghyunkim.mac.nativetoolkit.example` | 同、hardened runtime YES、App Sandbox（downloads の読み取り、利用者が選んだファイルの読み書き） |
| MacLibraryExampleTests | 15.1 | 5.0 | 未設定 | `mac.library.example.MacLibraryExampleTests` | 同 |
| MacLibraryExampleUITests | 15.1（project 既定） | 5.0 | 未設定 | `mac.library.example.MacLibraryExampleUITests` | 同 |

`LastUpgradeCheck = 1620`（3 つとも）。`MARKETING_VERSION` はライブラリ 2 つが 1.3.0。テストのターゲットだけ最小が 15.1 で本体（15.0）とずれている（iOS の 1.4 の「18.2 と 18.0」と同じ形）。

---

## 6. テスト

### 6.1 件数（ソースの数え上げ）

数え方: Swift Testing は `^\s*@Test\b`、XCTest は `^\s*(@MainActor\s+)?(final\s+)?func test...\(` の行数。`@Test(arguments:)` のパラメーター化が 12 か所あるので、実行される件数はこれより多い。

| ターゲット | Clipboard | Dialog | Notification | Share | 雛形 | 計 |
|---|---|---|---|---|---|---|
| `MacLibraryTests`（Swift Testing） | 222（ファイル 18） | **0** | 37（UseCase 21、エラー 16） | 48（Manager 8、エラー 17、Converter 13、Presenter 2、UseCase 8） | 1 | 308 |
| `UnityMacPluginTests`（Swift Testing） | 47（ブリッジ 23、Parser 24） | **0** | 18（Parser） | 9（Parser） | 1 | 75 |
| `MacLibraryExampleTests`（Swift Testing） | 19 | 0 | 0 | 0 | 1 | 20 |
| `MacLibraryExampleUITests`（XCTest） | 17（UI 11、待ちの規則 6） | **0** | **0** | 17 | 3（`testExample`、`testLaunchPerformance`、`testLaunch`） | 37 |

- **Dialog のテストはどのターゲットにも無い**（`grep -rl Dialog` が 0 件）。iOS は 0e で 9 件を足した
- **ブリッジの C 関数を呼ぶテストは 0 件**。`UnityMacClipboardBridgeTests` は「C 層は Unity のホストなしで Swift から動かせない」として、ブリッジのソースの文字列（関数の一覧、`NULL` の確かめ、`@Sendable`、ブロックが関数ポインタしか捕まえないこと）を照らし、Swift の façade を呼ぶだけ（`UnityMacClipboardBridgeTests.swift:8〜20, 34`）
- `accessibilityIdentifier` はサンプルの Clipboard の画面にだけ 10 か所（`ClipboardSampleView.swift`）。Dialog・Notification・Share・ContentView は 0。Share の UI テスト 17 件は識別子なしで動いている（[推測] ラベルで探している）
- xctestplan は無い。スキームは `MacLibraryExample.xcscheme` のみ共有

### 6.2 スクリプトと基準

- macOS のテストのスクリプト（`test_ios.sh` / `test_android.sh` / `test_windows.ps1` に当たるもの）は無い（`scripts/` に `test_mac*` も `*mac*` の基準も無い）
- C ABI の照合（`check_c_abi_contract_*.py`）、dist の照合（`check_*_dist.py`）、マニュアルの C の例の照合も macOS の分は無い

### 6.3 strict concurrency の警告（試したこと）

`xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -configuration Debug -destination 'generic/platform=macOS' -derivedDataPath <scratchpad> clean build SWIFT_STRICT_CONCURRENCY=complete SWIFT_COMPILATION_MODE=wholemodule CODE_SIGNING_ALLOWED=NO`（Xcode 26.3）。BUILD SUCCEEDED。警告の行を `sort -u` で数えた（2 つのアーキテクチャの重複を除く）。

| ターゲット | Clipboard | Dialog | Notification | Share | 計 |
|---|---|---|---|---|---|
| MacLibrary | 0 | 100 | 52 | 13 | 165 |
| UnityMacPlugin | 0 | 1 | 1 | 5 | 7 |

並行性以外の警告が 1 件（`UnityMacNotificationJsonParser.swift:198` の `switch` の `@unknown default`）。計 173。このブランチの作業ツリーで数えたので基準ではない。iOS の 0 章（Swift 5 + complete で `IosLibrary` 104、`UnityIosPlugin` 6）と同じ測り方（whole-module、clean build）。

---

## 7. ビルドとドキュメント

| スクリプト | macOS の扱い |
|---|---|
| `scripts/build_xcode26_library_xcframework.sh`（382 行） | **macOS を作る方（今使う方）**。`scripts/README.md:24` が「implement-feature の流れが使う。`--minimum-macos`（既定 15.0）を取る」と書く。`xcodebuild archive`（`SKIP_INSTALL=NO`、`BUILD_LIBRARY_FOR_DISTRIBUTION=YES`、`ENABLE_MODULE_VERIFIER=NO`、`MACOSX_DEPLOYMENT_TARGET`）→ 一時のフォルダーで `-create-xcframework` → `rsync -aL` で dist に書く（`:300〜376`）。署名の設定は渡していない（pbxproj の Automatic のまま）。UnityMacPlugin を頼むと MacLibrary を先に暗黙で作る（`:187〜207`） |
| `scripts/build_xcode16_library_xcframework.sh`（393 行） | 前の版（`scripts/README.md:25`「`--minimum-macos` が無い」）。macOS 専用で、`-create-xcframework -output` で直接書く。どちらも iOS は作らない（iOS は `build_ios_library_xcframework.sh`） |
| `mac/generate_docc.sh`（107 行） | `MacLibrary` と `UnityMacPlugin` の DocC を `mac/Docs/MacLibrary`・`mac/Docs/UnityMacPlugin` に出す。UnityMacPlugin の前に MacLibrary を `xcodebuild build` する。始めに `clean_docc` で `mac/Build/MacLibrary`・`mac/Build/UnityMacPlugin` を消す（`:100, 104`。ビルドのスクリプトの archive と同じ場所） |
| `scripts/publish_docs.sh`（365 行） | `--os mac` で `mac/generate_docc.sh` を走らせ（`:275〜283`）、`mac/Docs/MacLibrary` と `mac/Docs/UnityMacPlugin` を `<version>/mac/` にコピーする（`:343〜344`）。macOS には C ABI の Doxygen の段が無い（iOS・Android にはある） |

`mac/Build` は DerivedData で git の外（`mac/.gitignore:1`）。

---

## 8. `unity-native-plugin` の macOS の C# 側（読むだけ）

### 8.1 `DllImport`

| ファイル | 本数 | ライブラリ名 | コールバックの形 |
|---|---|---|---|
| `Runtime/Clipboard/MacClipboardManager.cs`（2,846 行） | 15 | `"__Internal"` | static + `[MonoPInvokeCallback]` 17 か所 |
| `Runtime/Dialog/MacDialogManager.cs`（878 行） | 6 | `"__Internal"` | **ラムダ（インスタンスの閉包）を渡す**。`MonoPInvokeCallback` 0（`:433〜447`） |
| `Runtime/Notification/MacNotificationManager.cs`（708 行） | 21（`grep -c DllImport` は 22 だがうち 1 つはコメント `:82`） | `"__Internal"` | static + `[MonoPInvokeCallback]` 14 か所 |
| `Runtime/Share/MacShareManager.cs`（261 行） | 2 | `"__Internal"` | static + `[MonoPInvokeCallback]` 2 か所 |

計 44 本で、ネイティブの 44 個と一致する。条件は `#if UNITY_STANDALONE_OSX && !UNITY_EDITOR`（エディターではネイティブを呼ばない。`MacClipboardManager.cs:3, 10`）。

[推測] Dialog のラムダは IL2CPP では関数ポインタにできず（AOT の制約）、Mono でもデリゲートを保持していないので GC で回収されうる。確かめていない。

### 8.2 JSON の層の行数（`wc -l`）

| 機能 | Builder | Parser | Reader | 計 | ほか |
|---|---|---|---|---|---|
| Clipboard | 238 | 506 | 813 | 1,557 | Payloads 502 |
| Notification | 219 | — | — | 219 | Payloads 44、結果の型 5 つ |
| Share | 170 | — | — | 170 | Payloads 87 |
| Dialog | — | — | — | — | Newtonsoft.Json でマネージャーの中で直列化（`MacDialogManager.cs:9〜11, 167, 427〜428`） |

Builder / Parser / Reader の計 1,946 行（Payloads を足すと 2,579 行）。

### 8.3 xcframework の選び方と入れ方

- **`VERSION.txt` で固定していない**。`PreBuildProcessor` は `FindLatestVersionInDist()`（dist の版のフォルダーを semver で比べて最大）を呼ぶ（`Editor/Build/PreBuildProcessor.cs:263〜274, 349〜376`）。コメントも「macOS still uses the scanning path」（`:50〜51`）。iOS の closing の 14 番は「後の macOS の C ABI の課題に回す」と決めている（`results/2026-11-22-ios-c-abi-closing.md:54`）
- `CopymacOSLibraries` は `unity-mac-native-toolkit-` の前方一致で **1 つだけ**選んでコピーする（`:592〜643`）。`mac-native-toolkit-*`（単体の MacLibrary）はコピーしない（埋め込みの方を使う）
- 選び方は `SelectXcframeworkName` の `string.Compare(..., OrdinalIgnoreCase) > 0`（`:722`）。**序数の文字列比較**なので、`unity-mac-native-toolkit-capi-2.0.0` を dist に足すと `c` > `1` で capi の側が選ばれる（iOS の 1.4 と同じ罠）。同じ関数が `PostBuildProcessor.cs:158` と `Tools/macOS/MacFrameworkPatcher.cs:113` にもある（3 か所）
- development ビルドは `-debug.xcframework` を探し、無ければ release に落とす（`PreBuildProcessor.cs` の `FindXcframeworkNameInDist`）。dist には `-debug` が無い
- コピー先は `Packages/com.jonghyunkim.nativetoolkit/Plugins/macOS/`（今は `unity-mac-native-toolkit-1.3.0.xcframework`）。`PluginImporter` は StandaloneOSX だけ有効、エディター無効（`ConfigureMacXcframeworkImporter`）
- 入れ方は **.framework（xcframework）を Xcode のプロジェクトに入れる形**で、.bundle ではない。`PostBuildProcessor`（`#if UNITY_EDITOR_OSX`、`:40〜113`）が、書き出された `Mac.xcodeproj` の main target に xcframework を `unity-native-plugin/Frameworks/` にコピーして link と embed を足し、`FRAMEWORK_SEARCH_PATHS` と `LD_RUNPATH_SEARCH_PATHS`（`@executable_path/../Frameworks`、`@loader_path/../Frameworks`）を足す。`Mac.xcodeproj` が無ければ `LogError` を出して戻る（`:78〜83`）。手で当てる `MacFrameworkPatcher` と `MacConfigureProjectWindow` もある
- [推測] 「Create Xcode Project」を使わない `.app` の直接のビルドでは、xcframework が app に入るかが分からない（Unity の StandaloneOSX のプラグインの xcframework の扱いを確かめていない）。`"__Internal"` が解決できるのは、framework が main の実行ファイルにリンクされてプロセスに載っているから、と読める
- `PreBuildProcessor` は macOS のビルドで `PlayerSettings.usePlayerLog = false` にする（`:265〜268`）
- Unity のシンボルへの依存: ネイティブ側 0（1.2）

---

## 9. macOS と iOS の機能・API の違い

| 機能 | macOS にあって iOS に無いもの | iOS にあって macOS に無いもの |
|---|---|---|
| Dialog | `NSOpenPanel` の 4 種（ファイル、複数のファイル、フォルダー、複数のフォルダー）と汎用の `showOpenDialog`（14 項目）、`NSSavePanel`、アラートの `alertStyle`（informational / warning / critical）、ヘルプのボタン、抑止のチェックボックス（suppression）、アイコン（SF Symbol、ファイル、名前つき画像、アプリのアイコン、システムの画像。描画の方式・色・大きさ・太さ・縮尺）、`accessoryView`、ボタンの `keyEquivalent`、任意の数のボタン | テキスト入力、ログイン（ユーザー名とパスワード）、アクションシート（popover の基点が要る）、confirm / destructive の既定の形（iOS の C ABI の `ntk_dialog_*` 14 関数） |
| Share | 名前つきサービスの直接の実行（`shareViaService`、`NSSharingService.Name`。recipients と subject を渡せる）、`canPerform`、除外のサービスの title、結果の `serviceName`（表示名） | 結果の `activity_type`（`ntk_share_result_activity_type`）。アンカー: macOS は key window の contentView 全体の固定で、利用者が基点を渡せない。iOS は popover の基点を持つ |
| Clipboard | `PasteboardScope` の `unique`（名前の無い一時の pasteboard）、`detectMetadata`、`accessBehavior`（macOS の pasteboard のアクセスの許可の状態）、遅延の供給（`LazyDataProvider` / promise）、SwiftUI の `PasteButton` | `UIPasteControl` の読み込み（`ntk_clipboard_load_item_async` と loaded item の 5 種）、snapshot の has_strings / urls / images / colors。両方にあるもの: copy（`localOnly`）、append、read、readData、snapshot、clear、create / remove pasteboard、detectPatterns / Values、監視、checkForegroundChange |
| Notification | Dock のバッジ（15 未満の分岐。届かないコード） | content の sound、attachment、thread、interruption level、relevance score、filter criteria、target content id（iOS の content のビルダー 14 関数）。起動のときの応答（`get_launch_response`）、通知の設定の画面の要求（`settings_request_listener`）、表示済みの削除の完了（macOS の `removeDelivered` は完了なし）。macOS の一覧は subtitle・category を返さない |
| 共通 | 最小 macOS 15.0 | — |

[推測] macOS の Dialog は `runModal` のアプリモーダルで、シート（ウィンドウに付く）の形は無い。iOS の Dialog は `UIAlertController` の非同期の表示。C ABI で「main への非同期の配送」に揃えるとき、macOS の Dialog は完了が表示の終わりまで来ない点は同じだが、main の run loop を止める点が違う。

---

## 10. 確かめられなかったこと

- ヘルプのボタンで完了が 2 回来ること（4.3）は、コードを読んだだけで動かしていない
- Share のサービスが delegate を呼ばず continuation が残る経路（4.4）。どのサービスで起きるか
- symlink の無い framework を Unity の書き出した Xcode プロジェクトに埋め込み、再署名・公証・起動したときに何が起きるか（5.1）。xcode16 の版のスクリプトで symlink が残るか
- 2 つの `MacLibrary` を同じアプリに入れたときの挙動（5.2）
- C# が `message = null` を渡したときに `stringWithUTF8String:NULL` で落ちること（1.2）。[推測] Apple の文書は非 NULL を求めており、`NSInvalidArgumentException` になる見込み
- Dialog の C# のラムダのコールバックが IL2CPP・Mono で動くか（8.1）
- Unity の macOS のプレイヤーで C# が main スレッドで動くか、`runModal` の間プレイヤーループが止まるか（3 章）。iOS の 0 章のようにトランポリンを読んでいない
- macOS のアプリにプライバシーマニフェストが要るか（4.7）
- 実行される件数（パラメーター化を展開した数）。テストは流していない
- `NSAlert` の 4 つ目以降のボタンの戻り値の扱い（4.3）
