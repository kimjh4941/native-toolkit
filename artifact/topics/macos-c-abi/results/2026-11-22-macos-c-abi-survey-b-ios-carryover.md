# B. iOS から macOS へ持ち込めるもの・決め直すもの・関係しないもの

> この記録は、企画（`../plans/2026-11-22-macos-c-abi-plan.md`）のための調査の全文を、scratchpad から写したもの（2026-11-22）。写すときに、利用者の氏名・証明書の ID・Team ID を `<氏名>`・`<証明書の ID>`・`<Team ID>` に、scratchpad の道を `<scratchpad>` に置き換えた。試作と生成物は scratchpad に残し、リポジトリには入れていない。日付の記録として本文は直さない

- 調査日: 2026-11-22（読むだけ。リポジトリのファイルは変えていない）
- 観点: `artifact/topics/ios-c-abi/`（1.14.0 / iOS 2.0.0）で作ったもの・決めたこと・学んだことのうち、macOS の C ABI（`mac/MacLibrary`、`mac/UnityMacPlugin`）にどう効くか
- 凡例: **[事実]** = ファイルを読んで、またはコマンドで確かめた。**[推測]** = AppKit・Unity などの一般の知識からの見込みで、このリポジトリでは確かめていない（企画か 1a に当たる段で確かめる）
- 出典の書き方: `README` = `artifact/topics/ios-c-abi/README.md`、`P1` = `designs/2026-10-31-ios-c-abi-c-abi-design.md`、`SAPI` = `designs/2026-10-31-ios-c-abi-swift-api-design.md`、`P2` = `designs/2026-11-03-ios-c-abi-c-abi-design-part2.md`、`S2N` = `results/2026-11-03-ios-c-abi-stage2-working-notes.md`、`1bN` = `results/2026-10-31-ios-c-abi-stage1b-working-notes.md`、`CL` = `results/2026-11-22-ios-c-abi-closing.md`、`AL` = `results/2026-10-18-ios-c-abi-android-lessons.md`

## 0. 要約

1. **規約（名前・エラー・UTF-8・ハンドル・`struct_size`・`user_data` と `release`・main への非同期の配送・`Common.h`）と、作り方（`@c @implementation`、`EXPORTED_SYMBOLS_FILE`、Objective-C を持たない、2 つの dynamic の xcframework、`check_*` の機械照合と変異の自己テスト）は、そのまま持ち込める。** iOS がそもそも「macOS にも同じ形を写せる」ように選んでいる（README:446 D-1、README:455 D-10）
2. **決め直しの中心は「表示」と「起動」と「配布」**: (a) Dialog が `NSAlert.runModal()` で main を塞ぐ（[事実] `MacDialogManager.swift:666`）ので D-6/D-8 の「待たない」と衝突する、(b) Share の `NSSharingServicePicker` が mouseDown の文脈を要る（[事実] コードのコメント `MacShareManager.swift:19-35`、未検証と明記）ので「いつも main に積む」と衝突する、(c) 通知の delegate を「起動の終わりまでに」入れる口が Unity の macOS の Player / Editor にあるか分からない（[推測]）、(d) macOS の framework は版付きの bundle で、署名・quarantine・notarization の事情が iOS と違う
3. **`MacLibrary` は iOS の 1b の前の `IosLibrary` とほぼ同じ状態**（[事実]）: Swift 5、delegate を `setup()` で上書き・公開の準拠、受け手は 1 つずつ、要求の箱も presenter も無い、エラーに任意の `Error`、プライバシーマニフェストが無い、ログは全部 `.public`。Clipboard だけは 1.10.0 の作り直しで構造が新しい
4. **`IosLibraryCApi/Common` は UIKit に依存しない**（[事実] 10 ファイル 1,019 行。import は Foundation / os / Dispatch / Synchronization と `IosLibrary`）。ただし `Registry.swift` と `VersionCheck.swift` が `IosLibrary.RequestBox` に依存する。推奨は「Swift は写して、写しが崩れていないことを照合で守る。Python は OS ごとの定数を外へ出して共通化する」
5. **テスト**: macOS には「シミュレーター」が無く、UI テストもクリップボードのテストも**利用者が今使っているこの Mac**で動く。`device-testing.md` の「Mac のクリップボードを読み書きしない」（:66）と正面からぶつかるので、macOS の分の規則を企画の最初に決める必要がある

---

## 1. iOS の決定の振り分け

### 1.1 README の D-1〜D-22（README:444-467）

| ID | 中身（iOS） | macOS | 理由・何が違うか |
|---|---|---|---|
| D-1 | iOS だけ。`Common/` は macOS で写せる形にしておく | 関係しない（macOS の課題そのもの） | iOS 側の範囲の決定 |
| D-2 | C ABI と同じ版でブリッジを消す | **そのまま** | `UnityMacPlugin` も同じ扱い。2c の成功をリリースの条件にする形も同じ |
| D-3 | Android の D-3（`Common.h` を OS ごとに写して 4 つの扱いで照らす） | **そのまま** | `common_header_problems` はもう N 個の OS を扱える（[事実] `scripts/c_abi_contract_common.py:596-655`） |
| D-4 | 一般の初期化は無い。通知を使うときだけ、ホストのネイティブのコードが起動の終わりまでに `ntk_notification_install` | **決め直す** | 形（A）は持ち込めるが、「誰がいつ呼ぶか」が違う。iOS は Unity の `.mm`（`AppDelegateListener` / `didFinishLaunching`）で解いた（README:270, 512）。**macOS の Unity Player には iOS の `UnityAppController` 相当の差し込み口が無い見込みで、プラグインは最初の `DllImport` で読み込まれる（起動の後）**[推測]。Unity Editor の中で動くときは、Editor の起動のはるか後になる[推測]。macOS の期限は `applicationDidFinishLaunching(_:)` から戻るまで（Apple の文書が iOS と同じく「起動を終える前に」delegate を設定せよと言う）[推測]。D-4 の C（constructor / `+load`）を iOS は退けたが、macOS ではそれしか間に合わない場合がありうる。1a に当たる段で `unity-native-plugin` に確かめてもらう項目 |
| D-5 | C ABI の範囲はブリッジの振る舞いと、受け手の解除・起動のきっかけ・取り消し | **そのまま**（数え直す） | macOS のブリッジは 44 関数（[事実] Clipboard 15、Dialog 6、Notification 21、Share 2。`mac/UnityMacPlugin/UnityMacPlugin/*/*Bridge.h`）。iOS は 43→134 関数になった（README:350-372, P2 8.2） |
| D-6 | 完了・イベント・`release` は main に非同期。どの関数も main を待たない。例外は install だけ | **形はそのまま、Dialog と Share で決め直す** | (1) `runModal` は main のブロックの中で入れ子の run loop を回して戻らない（[事実] `MacDialogManager.swift:325,666`）。C ABI の受け口が `DispatchQueue.main.async` で積んだブロックの中で `runModal` を呼ぶと、そのブロックは Dialog が閉じるまで戻らず、その間に積んだほかの完了が入れ子の run loop の中で走りうる[推測: main キューは common modes で回り、モーダルの mode もそこに入る]。(2) Share は mouseDown の文脈を要る（下の P1-11・P2-1 の行）。「必ず積む」と両立しない |
| D-7 | delegate は起動の終わりまでに入れ、前の delegate へ転送 | **そのまま**（UNUserNotificationCenter は macOS も同じ API） | 転送・印・`CompletionOnce`・循環の防止・router は UserNotifications の型だけで書けている（[事実] `NotificationDelegateRouter.swift:89` は UserNotifications を import しない）。違うのは installer と proxy の UIKit の部分（`UIApplication.shared`、`applicationState`、`didBecomeActiveNotification`。[事実] `NotificationDelegateInstaller.swift:9,72,81-84`、`NotificationDelegateProxy.swift:9,208`）。macOS には `applicationState` が無く `NSApp.isActive` と `NSApplication.didBecomeActiveNotification` になる[事実: API の存在。振る舞いの同等は推測]。共存の相手（Unity の通知パッケージ）は macOS には無い見込み[推測]で、2c の確かめが軽くなる |
| D-8 | Dialog は非同期だけ | **そのまま。ただし実装の前提を決め直す** | 公開の形は非同期のまま。実装を `runModal`（app-modal、main を塞ぐ）から `beginSheetModal(for:)`（window に付く、塞がない）に替えるか、`runModal` を「完了で返すが main は止まる」と契約に書くかを決める。Windows の Dialog はモーダルで塞ぐ形（AL:46）で、macOS はその中間 |
| D-9 | 2 つの dynamic の xcframework | **そのまま**（中身の形は違う） | macOS の framework は版付きの bundle（`Versions/A`、`Resources/Info.plist`、install name `@rpath/MacLibrary.framework/Versions/A/MacLibrary`。[事実] `dist/1.13.0/mac` を `otool -D` で確かめた）。スライスは `macos-arm64_x86_64` の 1 つ（[事実]） |
| D-10 | `@c @implementation`、Objective-C を使わない | **そのまま** | 今の `UnityMacPlugin` は `.h/.m`（[事実]）。`agent-rules/coding-rules/mac.md` に Objective-C の節がある（[事実] :30-36, :58-80, :127）ので、iOS の段階 3 と同じく書き換える |
| D-11 | `EXPORTED_SYMBOLS_FILE` で `_ntk_*` だけ、`@objc` の名前を固定したクラスを置かない | **そのまま** | macOS のプロセスは Unity Editor・他のプラグインと同居するので、Objective-C のクラス名の衝突を避ける意味は iOS より大きい[推測] |
| D-12 | bundle id を `com.jonghyunkim.nativetoolkit.*` に、モジュール名は保つ | **そのまま** | 今は `mac.library.MacLibrary.MacLibrary`（[事実] pbxproj:256,290）。ログの subsystem も `com.unity.native.toolkit`（[事実] `Common/Log.swift:27`）で持っていない名前空間 |
| D-13 | `ntk_last_system_code` は常に 0 | **そのまま** | 同じ理由（`NSError` の domain が要る） |
| D-14 | Swift 6 への移行を統合。UI テストのターゲットだけ Swift 5 + minimal | **そのまま** | `MacLibrary` は Swift 5.0（[事実] pbxproj:261,295）。`migration` の README が「残りは macOS」と書いている（[事実] `artifact/topics/migration/README.md:12,51-52`）。Swift 5 + complete の警告は Dialog 100、Notification 52、Share 13、Clipboard 0（[事実] 同 :223-229） |
| D-15 | 最小 iOS 18.0（`Synchronization` が使える） | **決め直す（値だけ）** | `MacLibrary` は macOS 15.0、テストのターゲットは 15.1（[事実] pbxproj:252,286,353,413。iOS の 0e と同じずれ）。macOS 15 で `Synchronization` の `Mutex`/`Atomic` が使える[推測: macOS 15 からの API]ので、15.0 のままで iOS の土台が組める見込み |
| D-16 | ビルドは Xcode 26.6、利用者は 26.3 以上 | **そのまま** | `@c @implementation` は Swift 6.3 の機能で OS を問わない。26.3 で 26.6 の swiftinterface を読めるかは macOS のスライスでも確かめ直す（iOS では確かめた。README:455） |
| D-17 | `dist/` に xcframework とヘッダー | **そのまま** | |
| D-18 | マニフェストを入れる。配る framework に署名しない | **決め直す** | (1) 今の mac の xcframework は個人の Apple Development の証明書で署名されている（[事実] `codesign -dvv` で Authority と TeamIdentifier が出る。iOS の D-18 の B の状態）。(2) macOS の arm64 は署名の無いコードを動かせず、リンカーの ad-hoc の署名が付く[推測]。(3) Unity Editor が読み込むプラグインや、ダウンロードして quarantine の付いた framework は Gatekeeper に止められうる[推測]。Developer ID と notarization の要否は iOS に無い論点。(4) プライバシーマニフェストは macOS では `Resources/PrivacyInfo.xcprivacy` に入る[推測]。macOS の SDK に理由の申告が要るかは Apple の文書で確かめる[推測]。今の `MacLibrary` には理由の申告が要る API の呼び出しが見当たらない（[事実] `grep` で `contentModificationDate`・`UserDefaults`・`systemUptime` などが 0 件。iOS は `ClipboardTemporaryFileStore.swift:116-121` の FileTimestamp） |
| D-19 | どちらも 2.0.0 | **そのまま** | `MacLibrary` も 1.3.0（[事実] pbxproj:253,287） |
| D-20 | `unity-native-plugin` は 4 機能を一度に移す | **そのまま** | 同じ名前の `MacLibrary.framework` を 2 つの版で入れられないのは同じ |
| D-21 | 実機の iPhone XS と iOS 26.2 のシミュレーターの 2 つで基準 | **決め直す** | macOS は「この Mac（macOS 26.3、README:518）」1 つ。最小の macOS 15 で流す環境が無い。macOS 15 の VM を用意するか、15 は組めることだけを確かめるかを決める（5 章） |
| D-22 | 0e でブリッジをビルドと基準から外し、ソースは参照に残す | **そのまま** | |

### 1.2 第 1 部の P1-1〜P1-24（P1:235-258）と DF-n（P1:260-281）

| ID | 中身（iOS） | macOS | 違い |
|---|---|---|---|
| P1-1 | `<機能>Entry.swift` と `<機能>Receiver.swift`。`public` は入口だけ | **そのまま** | 照合（H = E = P）もそのまま |
| P1-2 | 受け口は `IosLibrary` の公開 API だけを呼ぶ | **そのまま** | |
| P1-3 | nullability を付けない | **そのまま** | |
| P1-4 | `DispatchQueue.main.async` + `MainActor.assumeIsolated` | **そのまま（Share だけ要検討）** | mouseDown の文脈は積んだ時点で失われる[推測]。今の mac の Share も `Task { @MainActor }` を挟んでいて同じ問題を抱え、実機で確かめていない（[事実] `MacShareManager.swift:24-35`） |
| P1-5 | 出力引数は積む前に書く、契約は Android と同じ | **そのまま** | |
| P1-6 | `NOT_INITIALIZED` は通知のイベントの登録と起動のきっかけだけ | **そのまま** | |
| P1-7 | `WRONG_THREAD = 16`。`c_abi_error_numbers.json` で OS をまたいで番号を固定 | **そのまま** | macOS だけの名前（Clipboard の検出の拒否、ファイルのパネルなど）を足すときも表を通す |
| P1-8 | `ntk_notification_install(void)`、外す関数は無い | **そのまま** | |
| P1-9 | userInfo の印 `com.jonghyunkim.nativetoolkit` | **そのまま** | 1.x の macOS の通知（印が無い）の扱いも S-P17 と同じ論点 |
| P1-10 | `openSettingsFor` をイベントで渡す | **そのまま** | delegate のメソッドは macOS にもある[推測: macOS 10.14+]。今の mac は `x-apple.systempreferences:` で設定を開く（[事実] `NotificationPermissionHelper.swift:64-65`）が、それは別の口（自分から設定を開く）で、iOS の 1.x のような「意味が逆」の実装ではない |
| P1-11 | 前面 = 前面の `UIWindowScene` の key window。判定は `IosLibrary` の表示の手順に置く。C は表示元を渡さない | **決め直す** | macOS は scene が無い。候補は `NSApp.keyWindow ?? NSApp.mainWindow`（今の Share はこれ。[事実] `SharePickerPresenter.swift:139-141`）。**「前面にいる」の意味も違う**: macOS のアプリは非アクティブでも window を出せ、`runModal` はアプリが後ろでも出る[推測]。`NOT_FOREGROUND` を `NSApp.isActive` で返すか、window が無いときだけにするかを決める。全画面の Unity Player、メニューバーだけのアプリ（window 無し）、Editor の Game ビューも想定に入る[推測] |
| P1-12 | 同じ回の 2 つ目は 1 回だけ待って重ねる | **決め直す** | `runModal` なら 2 つ目は 1 つ目の中に入れ子になる。sheet なら 1 つの window に同時に 1 枚[推測]。Share の SH-13（同じ回の 2 つ目の完了が来ない）と同じ種類の穴を、最初から状態機械の表に入れる（S2N:3195-） |
| P1-13 | 基点の矩形を受けない（中央） | **決め直す** | iPad だけの論点だった基点が、macOS では**いつも**要る（`show(relativeTo:of:preferredEdge:)`。[事実] `SharePickerPresenter.swift:91`）。アクションシートは macOS に無い |
| P1-14 | 完了をちょうど 1 回: ライブラリの終わり方と、UIKit が知らせる終わり方（解放の見張り） | **形はそのまま、中身を測り直す** | `ReleaseWatch` は ObjectiveC の関連オブジェクトだけで UIKit を使わない（[事実] `ReleaseWatch.swift:6-8`）。NSAlert の sheet の完了、window が閉じたときの sheet、`NSSharingServicePicker` の `didChoose(nil)`、サービスが結果を返さない場合を測る[推測] |
| P1-15 | 後ろに回っても取り消さない。scene が切れたら見張り | **決め直す** | macOS は「非アクティブ」で、scene の切断は無い。代わりに window が閉じる・アプリが隠れる |
| P1-16 | 利用者のコールバックの例外は定めない | **そのまま** | |
| P1-17 | `@unchecked Sendable` の一覧 | **そのまま** | mac には今 `@unchecked`/`nonisolated(unsafe)`/`Sendable` の記述が 51 か所ある（[事実] `grep`）ので、Swift 6 化のときに一覧に照らす |
| P1-18 | C ABI のログは `os.Logger`、subsystem は capi の bundle id | **そのまま**（名前だけ） | |
| P1-19 | 同じ版の組だけを支える。capi は `BUILD_LIBRARY_FOR_DISTRIBUTION=NO` | **そのまま** | |
| P1-20 | C ABI のテストをシミュレーターで通常・ASan・TSan、実機の ASan は区切りで許可 | **決め直す** | macOS ではテストがこの Mac の上で直接動く。TSan も Mac の上で動く[推測: macOS は TSan の対象]。x86_64 は Rosetta で流せる[推測]。「実機の許可」は 5 章の規則に置き換わる |
| P1-21 | 循環の防止の範囲 | **そのまま** | |
| P1-22 | 起動のきっかけ: 最初の `didReceive` が最初の `didBecomeActive` より前 | **決め直す（材料を替える）** | `NSApplication.didBecomeActiveNotification` で同じ規則を組めるかを測る。通知のクリックで起動したアプリが必ず active になるか、`didReceive` が `applicationDidFinishLaunching` の後に来るかは測っていない[推測] |
| P1-23 | `unity-native-plugin` への申し送りを 2 回に分ける | **そのまま**（形） | 確かめる中身が変わる（Editor・Player の起動の口、プラグインの読み込みの時期、ドメインのリロードの後のコールバック[推測]） |
| P1-24 | Dialog と Clipboard の読み込みは要求ごとに取り消す。Share と権限は取り消さない | **そのまま（Dialog は要検討）** | `runModal` は外から終わらせるのに `NSApp.abortModal`/`stopModal` が要る[推測]。sheet なら `endSheet` で閉じられる。Clipboard の貼り付けの読み込みは今は世代で一括に取り消す形（[事実] `ClipboardPasteLoader.swift:120-132`） |
| DF-7 / DF-8 | ヘッダーの `__has_include(<IosLibraryCApi/...>)`、利用者の include の書き方 | **そのまま**（名前を `MacLibraryCApi` に） | |
| DF-10 | 「積めない」経路が無い | **そのまま** | |
| DF-12 | UIKit の例外は捕まえられないので起こさない検査を入口で | **そのまま** | AppKit も同じ。基点の無いピッカー、window の無い sheet を入口で止める |
| DF-13 | 前面 | 決め直す（P1-11） | |
| DF-15 | Clipboard も多くが完了で返す | **そのまま** | `MacClipboardManager` はクラス全体が `@MainActor`（[事実] `MacClipboardManager.swift:61`）で、iOS と同じく P2-12 の `nonisolated static cancelLoad` の形が要る |
| DF-18 | 取り消しは Dialog と Clipboard だけ | **そのまま**（P1-24） | |

### 1.3 Swift の API の設計書の S-P1〜S-P28（SAPI:92-119）

| ID | 中身（iOS） | macOS | 違い |
|---|---|---|---|
| S-P1 | `PresenterSelection`（`.firstActiveScene`、`.foreground`、`.viewController(_:)`） | **決め直す** | `.window(_:)`（`@MainActor @Sendable () -> NSWindow?`）など。Domain の型が UIKit を見ないようにする作り（[事実] `PresenterSelection.swift` と `PresenterSelection+UIKit.swift` に分けてある）は写せる |
| S-P2 | `RequestBox`（`init()` と `isClosed` だけ公開。取り消しは Manager から） | **そのまま** | `RequestBox.swift` は Foundation / os / Synchronization だけ（[事実]） |
| S-P3 | `foregroundViewController()` | **決め直す** | `foregroundWindow()` に当たるもの |
| S-P4 | `DialogRequest`（6 種）と `show(_:presenter:requestBox:completion:)` | **決め直す** | macOS の Dialog の種類は違う: `NSAlert`（任意のボタン、抑止のチェック、ヘルプ、アイコン、アクセサリの view）とファイルのパネル（ファイル・複数・フォルダ・複数フォルダ・保存）。テキスト入力・ログインは無い（[事実] `MacDialogManager.swift:303-532`）。Android/iOS の名前（alert/confirm/destructive/text_input/login）にどこまで合わせ、macOS だけの種類をどう足すかを第 2 部の最初に決める（P2-4 と同じ問い） |
| S-P5 | 今の口は形を保ち、新しい芯に載せ直す | **そのまま** | 今の mac の口は 7 つ（`showDialog` と 6 つのパネル。[事実]） |
| S-P6 | アクションシートの基点 | **関係しない** | アクションシートが無い |
| S-P7 | 任意の `Error` を持つ case を `FailureDetail` の case に | **そのまま** | mac にも任意の `Error` を持つ case がある（[事実] `NotificationDomainError.permissionRequestFailed(underlying:)` ほか 6 つ、`ShareError.presentationFailed(Error)`・`unknown(Error)`）。さらに **ライブラリの Domain に `BridgeError` がある**（[事実] `Notification/Domain/Error/BridgeError.swift`）。ライブラリが C ABI を知らない形（README:156）に直す |
| S-P8 | 今の受け手と `setup()` を deprecated に | **そのまま** | mac の `setup()` は delegate を上書きするだけ（[事実] `MacNotificationManager.swift:91-94`） |
| S-P9 | manager の公開の `UNUserNotificationCenterDelegate` 準拠を外す | **そのまま** | mac も公開で準拠している（[事実] :335）。ファイルの頭に「唯一の delegate の持ち主」と書いてある（:11-12） |
| S-P10 | `NotificationEventHub`（32 件、受けた順） | **そのまま** | mac は受け手 1 つずつの closure（[事実] :52,56） |
| S-P11 | userInfo を `Sendable` の値の木に | **そのまま** | mac は `JSONSerialization` の文字列で、失敗は黙って `"{}"`（[事実] :356-358） |
| S-P12 | 起動のきっかけ（`isLaunchResponse` と `launchResponse()`） | **そのまま（判定の材料は P1-22）** | |
| S-P13 | 通知の操作に `async throws` 版 | **そのまま** | mac の通知には `async` 版が無い（[事実] `async` の出現は `DispatchQueue.main.async` だけ） |
| S-P14 / S-P28 | category の登録を 1 つの FIFO で直列に、完了は反映の後 | **決め直す（直し方）** | mac は登録した category をメモリに持ち、全体を `setNotificationCategories` で置き換える（[事実] `NotificationCategoryUseCases.swift:38-39`、`NotificationRepositoryImpl.swift:136-140`）。OS に残った前の category を読まないので、再起動の後に登録すると前のものが消える。直列の仕組みは写せるが、読み直しを入れるかを決める |
| S-P15 | userInfo を property list で検査 | **そのまま** | |
| S-P16 | `cancel` と `cancelScheduled` の重なり | **そのまま**（mac にも `NotificationCancel` と `NotificationCancelScheduled` がある。[事実] ブリッジのヘッダー） | |
| S-P17 | 1.x の通知は何もしない | **そのまま** | |
| S-P18 | Share の `presenter` を取る口と `Result` の完了 | **そのまま（presenter の型は S-P1）** | mac には `shareViaService`（サービスを名指し）と `canPerform` がある（[事実] `MacShareManager.swift:158,169`）。iOS に無い口 |
| S-P19 / S-P27 | 権限の要求と設定の画面の口、`NotificationPermissionHelper` を deprecated | **そのまま** | mac にも公開の `NotificationPermissionHelper` がある（[事実]） |
| S-P20 | router を純粋な型に分けて全組み合わせを単体テスト | **そのまま** | router は UIKit も UserNotifications も見ない（[事実]）。写せばテストごと使える |
| S-P21 | `os.Logger` を直に呼び、補間ごとに `privacy:` | **そのまま** | mac の `Log` は `os.Logger` だが全部 `.public`（[事実] `Log.swift:27-44`）。`mac.md` に秘密を伏せる規則が無い（[事実] :12-28）。Clipboard だけ `ClipboardLog` で伏せている（[事実]） |
| S-P22 | Clipboard の `loadItem(…requestBox:)` と `cancelLoad(_:)` | **決め直す（対象）** | mac の Clipboard の口は iOS と違う（`detectPatterns`・`detectValues`・`detectMetadata`・`accessBehavior`・`makePasteButton`。[事実] `MacClipboardManager.swift:398-560`）。どの読み込みに箱を付けるかは mac の口で数え直す |
| S-P23 | サンプルは今のボタンを残し、新しい口のボタンを足す | **そのまま** | |
| S-P24 | 機能ごとのコミット（共通 → Dialog → Share → Clipboard → 通知） | **そのまま** | |
| S-P25 | 一覧の型を `Sendable` に | **そのまま** | |
| S-P26 | 同じ名前の `async` 版（ソースの破壊的変更） | **そのまま** | |

### 1.4 第 2 部の P2-1〜P2-29（P2:29-57）

| ID | macOS | メモ |
|---|---|---|
| P2-1（受け口は Manager だけ。表示は `.foreground`、C から表示元を渡さない） | **決め直す（表示元）** | macOS では基点の矩形・window を C から渡したい場面が増える（Share は毎回基点が要る）。P1-13 と一緒に決める |
| P2-2（main が要る操作はすべて完了で返す） | **そのまま** | NSPasteboard は main 以外でも使えるかもしれない[推測]が、iOS と形をそろえるほうが C# の包みを共有できる |
| P2-3（`_async` の付け方） | **そのまま** | |
| P2-4（Dialog は Android の名前、Share は `ntk_share_content_async` 1 つ） | **決め直す（Dialog）** | macOS のパネルの種類（open/save）は Android にも iOS にも無い名前になる。Share は mac も種類の混ざった項目を 1 回で渡す（[事実] `ShareContent(items:)`）ので `ntk_share_content_async` の形をそのまま使える見込み |
| P2-5（ビルダーと `struct_size` の構造体） | **そのまま** | |
| P2-6（戻り値の無い通知の操作も `_async`） | **そのまま** | mac も `cancelScheduled`・`removeDelivered` などは戻り値なし（[事実] :211-260） |
| P2-7（userInfo は JSON） | **そのまま** | |
| P2-8（`detectValues` は JSON 1 つ） | **そのまま** | mac にも `detectValues` がある |
| P2-9 / P2-10 / P2-11（エラーの番号） | **そのまま（規則）** | mac の Clipboard は `errorCode` が Int（1501〜）、Notification は 1001〜、Share は 1401〜（[事実] 各 `*Error.swift`）。C の番号は `c_abi_error_numbers.json` の名前で付け直す |
| P2-12（`nonisolated static cancelLoad`） | **そのまま** | `MacClipboardManager` も `@MainActor` |
| P2-13 / P2-14 | **そのまま（中身は mac の case で）** | |
| P2-15（値の補正をせずエラー） | **そのまま** | |
| P2-16 / P2-17（監視の開始・停止と受け手の分離） | **そのまま** | mac の監視も同時に 1 つ（[事実] `startObserving` / `stopObserving`） |
| P2-18 / P2-19（通知のイベント名、起動のきっかけ） | **そのまま** | |
| P2-20 / P2-21 / P2-22 / P2-23 / P2-25 / P2-28 / P2-29 | **そのまま** | |
| P2-24（読み込みの時間切れに利用者が答える時間が入る、同期の読み出しは main を止める） | **決め直す** | iOS の貼り付けの許可のダイアログ（MS-08、実機で 44 秒止まった。README:175）は macOS では別の仕組み（macOS 15.4 以降の pasteboard のプライバシー。mac の `accessBehavior` と `detectionDenied`。[事実] `ClipboardError.swift:46-48`）。macOS で読み出しが答えるまで main を止めるかは測っていない[推測] |
| P2-26（落ちる trigger を `IosLibrary` で守る） | **そのまま（測り直す）** | `timeInterval` の 60 秒の制約などが macOS でも同じかは測る |
| P2-27（権限の選択肢） | **そのまま** | |

### 1.5 決め直すものの具体（AppKit と macOS の違い）

| 論点 | iOS で決めたこと | macOS で違うこと | 確かさ |
|---|---|---|---|
| 前面の探し方 | 前面の `UIWindowScene` の key window（P1-11、DF-13） | `NSApp.keyWindow` / `mainWindow`。scene は無い。アプリが非アクティブでも window はある。全画面の Unity Player、window の無いアプリ（メニューバーだけ）、Editor の中 | API は事実、振る舞いは推測 |
| Dialog の出し方 | `UIAlertController` を present（main を塞がない） | 今は `NSAlert.runModal()`・`NSOpenPanel.runModal()`・`NSSavePanel.runModal()`（[事実] :572,666,756）。app-modal で、戻るまで main のブロックが終わらない。`beginSheetModal(for:)` に替えると window が要る | 事実（今の実装）。入れ子の run loop の振る舞いは推測 |
| Dialog の種類 | alert / confirm / destructive / action sheet / text input / login | アクションシートは無い。ファイルのパネル（open / save）がある。destructive は `NSButton.hasDestructiveAction`[推測] で表せる | 種類は事実 |
| ファイルのパネルの結果 | -（iOS に無い） | サンドボックスのホストでは、パネルで選んだ URL の security scope がパスの文字列にすると失われうる[推測]。サンプルはサンドボックス（[事実] `MacLibraryExample.entitlements:5`） | 推測 |
| 貼り付けの許可 | `UIPasteboard` のダイアログが main を止める（MS-08）、`UIPasteControl` | macOS 15.4 以降の `accessBehavior`（ask / always allow / always deny）と `detect*` の API、`makePasteButton`（[事実] mac のコード）。読み出しで警告が出る条件と main が止まるかは測っていない | 口は事実、振る舞いは推測 |
| Share | `UIActivityViewController` を present。SH-13（同じ回の 2 つ目） | `NSSharingServicePicker` を view と矩形に付ける。mouseDown の文脈が要る（[事実] コードのコメント、未検証）。同時は 1 つだけで `alreadyInProgress`（[事実] `SharePickerPresenter.swift:79,101`）。サービスを名指しする口がある | 口は事実、mouseDown の要否は未検証 |
| 通知の delegate の入れ時 | `didFinishLaunching` から戻るまで。Unity は `.mm` の `didFinishLaunching` で（H2-2） | macOS の Unity Player / Editor に起動の中の差し込み口があるか。プラグインの読み込みの時期 | 推測 |
| 起動のきっかけ | `UIApplication.didBecomeActiveNotification` と `applicationState`。SwiftUI の `App.init` で `sharedApplication` が nil のとき（1bN:1271- の B-4） | `NSApplication.didBecomeActiveNotification`、`NSApp.isActive`。`NSApp` が無い時期の扱いは同じ問題がある見込み | 推測 |
| 権限の要求が後ろから | 未決で後ろにいると、ホーム画面の上にダイアログが出て答えるまで完了しない（MS-04。README:174） | macOS の許可の問い合わせは通知として出る[推測]。`NOT_FOREGROUND` を権限の要求に返すかを決め直す | 推測 |
| 例外 | iPad の基点の無い popover（`SIGABRT`） | 基点の無いピッカー、window の無い sheet | 推測 |
| 配布の形 | `ios-arm64` と `ios-arm64_x86_64-simulator` の 2 スライス、平らな framework | `macos-arm64_x86_64` の 1 スライス、版付きの bundle、`Resources/Info.plist`（[事実]）。`check_ios_dist.py` の `SLICES`・`PLATFORM`・`MINIMUM_IOS`・install name の形はそのままでは使えない | 事実 |
| 署名 | 署名しない（ios-arm64）・リンカーの ad-hoc（シミュレーター） | 今は個人の証明書で署名済み（[事実]）。Gatekeeper、quarantine、Hardened Runtime のライブラリの検証、notarization | 状態は事実、影響は推測 |
| Unity Editor | iOS は Editor でネイティブを呼ばない（README:333 の PlayMode は Editor で動きネイティブを呼ばない） | macOS は Editor のプロセスの中で本物の C ABI が呼ばれうる。ドメインのリロードの後に、古い C# の関数ポインタが受け手の表に残る危険[推測]。通知の権限は Unity.app の bundle id に付く[推測] | 推測（`unity-native-plugin` に確かめてもらう） |

---

## 2. `IosLibraryCApi` と照合のスクリプトの共有

### 2.1 Common の土台（[事実]。`ios/IosLibraryCApi/IosLibraryCApi/Common/`）

| ファイル | 行 | import | iOS / `IosLibrary` への依存 |
|---|---|---|---|
| `CApiLog.swift` | 18 | os | subsystem の文字列 `com.jonghyunkim.nativetoolkit.IosLibraryCApi`（:11） |
| `MainQueue.swift` | 19 | Dispatch | なし |
| `CApiBytes.swift` | 25 | Foundation | なし |
| `EntryError.swift` | 34 | - | なし |
| `VersionCheck.swift` | 63 | Foundation, IosLibrary, Synchronization | `Bundle(for: RequestBox.self)` で `IosLibrary` の版を読む（:56）、ログの文言に `IosLibrary` |
| `CommonEntry.swift` | 64 | - | コメントの「on iOS」（:14） |
| `CApiString.swift` | 84 | - | なし |
| `StructReader.swift` | 123 | - | なし |
| `Handle.swift` | 129 | - | なし |
| `Registry.swift` | 460 | Foundation, IosLibrary, Synchronization | `IosLibrary.RequestBox` を作り閉じる（:34,73,77,95,117,140,305） |
| 計 | 1,019 | **UIKit は 0** | `IosLibrary` に依存するのは 2 ファイル、型は `RequestBox` だけ |

- 機能の受け口で UIKit を import するものも無い（[事実] capi 全体の import は Foundation / os / Dispatch / Synchronization / IosLibrary / UserNotifications）。iOS らしさは `IosLibrary` の側（`PresentationProcedure.swift` 455 行、`ForegroundLocator.swift` 118 行など）に閉じている
- `module.modulemap`（5 つのヘッダー）と `IosLibraryCApi.exp`（`_ntk_*` の 1 行）は名前を替えれば写せる

### 2.2 ヘッダー（[事実]。`ios/IosLibraryCApi/include/NativeToolkitC/`）

| ヘッダー | iOS 専用の部分 |
|---|---|
| `Common.h`（80 行） | 宣言は OS 共通（照合が空白とコメントを除いて比べる。`c_abi_contract_common.py:596-655`）。iOS の部分はコメントだけ（:4「always 0 on iOS」、:7-8「except ntk_notification_install」、:47）と、版のマクロの値（2.0.0） |
| 機能のヘッダー 4 本 | `#include` の形（`__has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)`。DF-7）、説明の文（scene、iPad の複数 window、`UIActivityViewController`、iOS の貼り付けの許可）。宣言では `NTK_*_NOT_FOREGROUND`、Dialog の `action_sheet`、Clipboard の `UIPasteboard` 由来の型（named / unique の pasteboard、`check_foreground_change`）、Notification の `ntk_notification_install` |
| 機能のヘッダー 4 本の macOS | 機能のヘッダーは OS ごとに持つ決まり（README:192-197）なので、写して作り直す。同じ意味の操作は同じ名前（README:192） |

### 2.3 照合のスクリプト（[事実]）

| スクリプト | 行 | OS に依存しない部分 | iOS 専用 |
|---|---|---|---|
| `c_abi_contract_common.py` | 655 | 全部（モジュールの冒頭 :1-17 が「OS を知らない」と書く）。N 個の OS の `Common.h`（:596） | `OS_ONLY_CONSTANTS`（Windows だけ） |
| `c_abi_error_numbers.json` | 94 | 機能ごとの名前 → 番号の表 | なし（mac の名前を足す） |
| `check_c_abi_contract_ios.py` | 1,149 | 検査の大半（functions / signatures / shape / operations / behaviours / values / names / ascii / common / entries / complete / public / csources）は設計書と同じ章番号を読めば mac でも同じ | 道の定数（:125-141）、`NOT_ERROR_CASES = {"success","firstActiveScene"}`（:168）、`CLANG_TARGET = "arm64-apple-ios18.0"`、`LAYOUT_SLICES`（iphoneos / iphonesimulator。:199-201）、`FRAMEWORK_SETTINGS`、Android のヘッダーとの番号の照らし（:603）、`INSTALL_RESULT` |
| `check_ios_dist.py` | 760 | `nm`・`otool`・`plutil` の読み方、exit の登録（`__cxa_atexit`）、依存、ヘッダーの一致、`@c` の検査 | `SLICES`・`PLATFORM`・`MINIMUM_IOS`・bundle id・平らな framework の道（:72-116）、署名の規則（ios-arm64 は署名なし）、プライバシーの置き場所 |
| `ios_capi_runner.py` | 843 | 段の並べ方・要約 | `devicectl` 10 か所 |
| `run_ios_capi_smoke.sh` | 319 | 手順 | `simctl` 17 か所 |
| `test_ios.sh` | 1,043 | `capped_group`・`path_inside`・DerivedData を閉じ込める作法 | `simctl` 27、`devicectl` 30 か所 |
| `ios_ui_runner.py` | 2,939 | 許可の台帳、宣言の照合、`TRUSTED_FILES` のハッシュ | `simctl`・`devicectl`・springboard |

### 2.4 共有の仕方の案

| 案 | 中身 | 危うさ |
|---|---|---|
| **A. 写す（照合つき）** | `IosLibraryCApi/Common` を `MacLibraryCApi/Common` に写し、`Ios`→`Mac` だけを替える。写しが崩れていないことを、正規化した差分で照らす小さな照合（例: `check_capi_common_twins.py`）を足す。`Common.h` を OS ごとに写して照らすのと同じ考え（D-3） | 直しを片方だけに入れて分かれる（照合が止める）。同じバグを 2 度直す手間。iOS の 2.0.0 は出し済みなので、iOS の側を触らずに済むのが利点 |
| B. 共通のパッケージ / framework（例: `apple/NativeToolkitCApiCore` を SwiftPM か第 3 の framework にする） | 土台を 1 か所に置き、両方の capi がリンクする | (1) `RequestBox` が `IosLibrary` の公開の型なので、土台を `IosLibrary` から切り離すには `RequestBox` を土台へ移すか protocol で抽象にする必要があり、**出し済みの iOS 2.0.0 の公開面か内部を変える**（iOS の 474 件の C ABI のテスト、全件約 128 分（CL:25）、dist の作り直し、`unity-native-plugin` の取り込み直し）。(2) 第 3 の dynamic framework を配ると配布物と D-9 の契約が変わる。static にして capi に閉じ込めると `EXPORTED_SYMBOLS_FILE` で隠せるが、ビルドの構成が増える。(3) `feature-split-distribution`（機能ごとの配布物。`artifact/README.md:36`）と重なり、そちらで決めるべき形を先取りする |
| C. 同じソースを両方の Xcode のターゲットにファイル参照で入れる | 新しい成果物は増えない | subsystem・`RequestBox` の型・コメントの OS 名の違いを `#if os(iOS)` で分けることになり、iOS のファイルを触る。iOS のビルドとテストが macOS の作業で壊れうる。どちらの課題の PR で何が変わったか追いにくい |

### 2.5 推奨（1 つ）

**A: Swift の土台は写し、写しの一致を照合で守る。Python は iOS の照合から OS の定数（道、スライス、clang の target、許す case）を外へ出し、`check_c_abi_contract_mac.py`・`check_mac_dist.py` はその表を渡すだけの薄いファイルにする。** 理由: iOS 2.0.0 は出し済みで、Swift の土台を共通にすると iOS の再検証と dist の作り直しが要る。一方 Python は iOS の配布物を変えず、`scripts/tests` の自己テスト（859 件。CL と S2N 17.16）で iOS の照合が変わっていないことを機械で確かめられる。Swift の本当の共通化は `feature-split-distribution` で配布物の形と一緒に決める。

- 注意: `c_abi_error_numbers.json` は「どちらかの OS のヘッダーかこの表を変えたら両方を流す」（P1-7）。mac の名前を足すと iOS と Android の照合も流すことになる（iOS の照合のファイルも触る）

---

## 3. 1b で `IosLibrary` に足した Swift の API が `MacLibrary` にあるか（[事実]、2026-11-22 の `mac/MacLibrary`）

| 足したもの（iOS 1b。README:250、SAPI 付録 A） | Clipboard | Dialog | Notification | Share | 共通 |
|---|---|---|---|---|---|
| 要求の箱（`RequestBox`）と要求ごとの取り消し | 無い（貼り付けの読み込みは世代で一括に取り消す。`ClipboardPasteLoader.swift:120-132`。読み込みの view を手放すと取り消す） | 無い（`runModal`。取り消しの口が無い） | -（取り消しを出さない機能） | -（同上） | `RequestBox` 型が無い |
| presenter（`PresenterSelection`）と前面を返す口 | - | 無い（`runModal` は app-modal で表示元を取らない） | 無い（権限の要求・設定の画面） | 無い（`keyWindow ?? mainWindow` の固定。`SharePickerPresenter.swift:139-141`） | 型が無い |
| 表示の手順（同じ回の 2 つ目、待ち、判定し直し）と解放の見張り | - | 無い | - | 無い（同時は `alreadyInProgress` で断る。:79,101） | 無い |
| 通知の delegate の転送（proxy・router・印・`CompletionOnce`・循環の防止・入れ直し） | - | - | **無い**（`setup()` で上書き、manager が公開で準拠。`MacNotificationManager.swift:91-94,335`） | - | - |
| イベントの口（複数の受け手、32 件を保つ、起動のきっかけ、設定の要求） | 変更の監視は `onEvent` 1 つ（`startObserving`） | - | **無い**（`onActionReceived` と `onTextInputActionReceived` の 1 つずつ。:52,56） | - | - |
| `async throws` 版 | ある | 無い（completion だけ） | **無い** | ある（`share(content:) async throws`。:144） | - |
| エラーの case の整理（任意の `Error` を持たない、`FailureDetail`） | 文字列を持つ case（`detectionFailed(String)`、`unknown(String)`）。任意の `Error` は無い | `DialogError`（`invalidConfiguration(String)`、`executionFailed(String)`）。型はある | 任意の `Error` を持つ case 6 つ。Domain に `BridgeError` | `presentationFailed(Error)`、`unknown(Error)` | `FailureDetail` が無い |
| Swift 6 / `@MainActor @Sendable` の完了 | 完了は `@MainActor`（:15,19）、クラスは `@MainActor` | 無い（`Result` の closure、`@Sendable` 無し） | 無い（完了は main で呼ぶが型に注釈が無い） | 一部 | Swift 5.0 |
| category の直列と完了 | - | - | 完了はあるが、メモリの集合を丸ごと置き換える（`NotificationCategoryUseCases.swift:38-39`） | - | - |
| userInfo の検査と値の木 | - | - | 無い（JSON にできなければ `"{}"`。:356-358） | - | - |
| プライバシーマニフェスト | - | - | - | - | **無い**（`find` で 0）。理由の申告が要る API の呼び出しも見当たらない |
| ログの規則（`os.Logger` を直に、`privacy:`） | 伏せる道具はある（`ClipboardLog`。値でなく形と長さ） | 無い（題と本文を `.public` で出す。`MacDialogManager.swift:309`） | 無い | 無い | `Log` は `os.Logger` だが全部 `.public`、subsystem は `com.unity.native.toolkit`（`Log.swift:27`）。`mac.md` に伏せる規則が無い |
| bundle id | | | | | `mac.library.MacLibrary.MacLibrary`（D-12 の前の形） |

まとめ: **Notification と Dialog は iOS の 1b と同じ量の仕事が要る。Share は presenter・基点・完了の約束、Clipboard は要求の箱と取り消しの形が中心。** 0e/0f（Swift 6 と complete）で Dialog 100 件・Notification 52 件の警告を直す量（`migration` の README:223-229）も入る。

---

## 4. 知見（iOS で手戻り・時間がかかったことのうち、macOS で先に手を打てるもの）

`AL`（Android から iOS への知見）と同じ形。「iOS で起きたこと」は記録の事実、「macOS で最初にすること」は提案。

| # | 項目 | iOS で起きたこと | macOS で最初にすること |
|---|---|---|---|
| 1 | 本物のホストでの確かめを先に | Android は smoke だけで確かめて申し送りを誤った（AL:15）。iOS は 1a で `unity-native-plugin` の agent に 2 回の申し送り（U-1〜U-10）を出し、`didFinishLaunching` で入れる形（H2-2）、パッケージの入れ直し（H2-3）、P1-22 の絞り（H2-1）が決まった（README:510-512） | **企画の段で、Unity の macOS Player と Editor の両方で、(a) プラグインがいつ読み込まれるか、(b) 起動の中で delegate を入れられる口があるか、(c) 通知のクリックでの起動、(d) ドメインのリロードの後のコールバック、(e) `runModal` の間にゲームが止まるか、を確かめる申し送りを出す**。結果で D-4・D-8・Dialog の形が変わる |
| 2 | 表示の同時の要求と完了の 1 回 | P1-12/P1-14 はレビューで 4 版（v1〜v4。`reviews/2026-10-31-*-c-abi-design-review-v1〜v4`）。リリースの直前に SH-13（同じ回の 2 つ目の Share の完了が来ない）が `unity-native-plugin` から報告され、設計メモ 3 版・レビュー 3 本・dist の作り直しになった（S2N:3195-3258） | **「同じ main の回に同じ表示を 2 回」「表示の途中にもう 1 つ」「外から閉じる」を、Dialog（`runModal`/sheet）・ファイルのパネル・Share のピッカーのそれぞれで最初の設計の表に入れ、測ってから決める** |
| 3 | 循環の防止は範囲を絞る | P1-21 は v3 の形が 3 回のレビューのたびに穴を見つけられ、「最初の転送の同期の戻りだけを止め、ほかは契約の外」に絞った（P1:255） | iOS の router と範囲をそのまま写す（作り直さない） |
| 4 | 1 秒ごとの階層の見張りは入れない | v3 の見張りは本当の結果を上書きする危険のほうが大きく外した（P1:248） | 解放の見張り（`ReleaseWatch`）の形を写し、AppKit で解放の時期を測る |
| 5 | category の読み書きの競合 | actor の再入で 2 つの要求が同じ古い集合を読み、後の書き戻しが前を消した。`nonisolated(nonsending)` が無いと 300 回のうち 257 回順が入れ替わった（SAPI:105,119） | mac はメモリの集合を丸ごと置き換える形（3 章）。iOS の FIFO（`NotificationCategoryQueue`）を写し、最初から直列にする |
| 6 | SwiftUI の `App.init` から入れると `UIApplication.shared` が無い | C5 のレビューの B-4 で、`sharedApplication` が nil なら「まだ active でない」とする形にした（1bN:1271-） | `NSApp` が無い時期（`App.init`、`NSApplicationMain` の前）を最初の表に入れる |
| 7 | install の中の順番 | Codex の P2（C-7）: `center.delegate = proxy` の後に前の delegate と初回の印を設定していて、その間の呼び出しが古い状態を見た（1bN:1275） | install の順（前の delegate → 初回の印・KVO → 代入 → 印）を写し、テスト（`aCallDuringTheAssignmentSeesThePreparedState`）ごと持ち込む |
| 8 | Swift 6 の実行時の隔離の検査 | `IosClipboardManager` を main 以外で手放すと止まり、`isolated deinit` で直した（README:264） | 0f の段で、`@MainActor` のクラスを main 以外で手放す経路を最初に探す（`MacClipboardManager` も `@MainActor`） |
| 9 | UI テストのターゲットの Swift 6 | complete にすると 316 件の警告がランナーの信頼する部分に出て、D-14 の例外にした（README:459） | 最初から UI テストのターゲットを例外にする |
| 10 | `LastUpgradeCheck` の推奨設定 | 推奨の一覧は Xcode の画面でしか見られず、2.0.0 でも未反映のまま（CL:42） | 着手の前に、利用者に Xcode の画面で見てもらうか、扱わないと決める |
| 11 | テストのターゲットの最小 OS のずれ | iOS は 18.2 と 18.0 で、0e で直した（README:546） | mac も 15.1 と 15.0（[事実]）。0e に当たる段で直す |
| 12 | 決めたら README の表をその場で直す | Android で「設計で決める」のままリリースの直前に見つかった。iOS は守ったが、終わりの記録で古い記述の対応の表が要った（CL 2 章） | 同じ規則を企画の冒頭に書く |
| 13 | 揺れるテスト | `settle()` の 150 ms、D8、貼り付けのアラートの後始末が揺れた。テストは変えずに流し直した（CL:49） | 固定の待ちを使わない（U-14）を最初から。macOS の Dialog と Share のピッカーは出るまでの時間を先に測る |
| 14 | 実機で自動の操作が通らないもの | CB1・CB3・CB4（貼り付けのコントロール）は実機で合成のタップを受け付けず、人の確認 HC11〜HC13 に回した（S2N:3095-3112） | macOS の貼り付けのボタン、`accessBehavior` の警告、Share のピッカーが XCUITest の合成の操作を受け付けるかを、段階 0a に当たるスパイクで先に確かめる |
| 15 | dist の探索の前方一致 | `unity-native-plugin` が `ios-native-toolkit-` の前方一致で capi を選ぶので、iOS は dist を置く前に 3 つ（`VERSION.txt`、完全一致、`-debug`）を頼んだ。**macOS の固定は入れていない**（S2N:3165-3185、CL:54） | macOS の dist を置く前に、`unity-native-plugin` の macOS の道（`FindXcframeworkName` の前方一致、Build Settings での development の判定）を直してもらう。`mac-native-toolkit-capi-` も `mac-native-toolkit-` に当たる |
| 16 | 署名の確かめは早めに決める | 配布用の署名は Program の登録が無く、最後に「行わない」と決めた（README:609、CL:41） | macOS は Gatekeeper と notarization が利用者の体験に直に効く[推測]。企画の段で「署名しない / Developer ID」を決め、Program の要否を先に利用者に聞く |
| 17 | 区切りの全件の時間 | 全件はシミュレーターで約 94 分（0d）→ 約 128 分（2026-11-22。CL:25）。各段は関係するテストだけにした（README:390） | 同じ運用。macOS は UI テストの間この Mac を使えないので、全件の時刻を利用者と決めてから流す |
| 18 | ブリッジのために公開した口が残る | `ClipboardRedaction`（`@objc public`）を消せずに 2.0.0 に入った（CL:45） | mac にも `ClipboardLog`（`public enum`。[事実] `ClipboardLog.swift:13`）がある。ブリッジのためだけの公開を 1b に当たる段で洗い出し、消すか決める |
| 19 | 申し送りの数え違い | Android は JSON のテストを約 60 件と書いて実物は約 79 件だった。iOS は実物を数えてから書いた（AL:74、README:604） | `unity-native-plugin` の macOS のテストを実物で数えてから対応表を書く |
| 20 | マニュアルの見出しのアンカー | 同じページの `### C ABI` が増えるとずれ、段階 4 で検査 8 を足した（README:605） | 検査 8 はもうある。macOS の節を足しても通ることを段階 4 で見る。1.13.0 から残る macOS の通知の画像 30 件（CL:53）は `manual-integrity` の範囲 |

---

## 5. テストの基盤

### 5.1 iOS の基盤と macOS で要るか

| iOS の基盤 | 中身（出典） | macOS |
|---|---|---|
| UI テストの設計（U-1〜U-19） | 期待値の全文一致、identifier だけで探す、更新の回数、最後のイベント、固定の待ちを使わない、テストごとに launch（`designs/2026-10-18-ios-c-abi-ui-test-design.md:67-85`） | **要る**。今の mac の UI テストは Clipboard と Share だけで 37 件（[事実] Clipboard 11・待ちの規則 6・Share 17・雛形 3）。Dialog と Notification は 0 件。iOS の 0b/0c（識別子と UI テストを全機能に）に当たる段が要る |
| `test_ios.sh` と `ios_ui_runner.py` | `build-for-testing` → クラスごとの `test-without-building`、基準の比べ合わせ（changed/added/removed）、`--feature`、`--baseline`、`TRUSTED_FILES` のハッシュ | **要る**（`test_mac.sh` を新しく作る）。`simctl`/`devicectl` の部分は要らない。基準の形と比べ合わせは写せる |
| 基準 | 2 つの環境（D-21）。件数はターゲット・機能・雛形に分ける | **要る**。環境は 1 つ（この Mac）になる。macOS 15 の基準を取るなら VM が要る[推測] |
| 私物の端末を守る仕組み（U-9 の 3 本柱） | ランナーが区分で選ぶ、宣言の正しさの照合、毎回の許可（`--dry-run` → `--approved`、1 回限りの ID） | **要る。しかも全件に**。5.2 |
| 更新のテスト | 1.13.0 のサンプルで予約・category・表示 → 2.0.0 を上から入れる（`test_ios_upgrade.sh`、シミュレーターだけ） | **要る**（1.x の mac の通知も OS に残る）。ただしシミュレーターが無いので、この Mac の通知センターに 1.x のサンプルの通知を残すことになる。VM か、許可を得た回で行う |
| `--capi` | `IosLibraryCApiTests` を通常・ASan・TSan、dist の組み立て、`check_ios_dist.py`、契約の照合、smoke（`test_ios.sh:30-44`） | **要る**。テストのホスト（アプリ）が要るのは同じ見込み（UserNotifications と AppKit はアプリの bundle で動かす）[推測]。TSan もこの Mac で流せる[推測]。x86_64 は Rosetta で流せる[推測] |
| `--capi-ui` | C を呼ぶ UI テストのアプリ、シミュレーターだけ、起動のたびに再起動 | **要る**（install を起動の中で呼ぶ確かめ `testTheLaunchInstallsTheDelegateThroughC` など）。この Mac で動く |
| `--capi-device` | 実機の ASan と smoke、区切りでだけ許可を得て | **関係しない**（この Mac が実機）。代わりに `--capi` の全体が 5.2 の規則に入る |
| smoke | dist の 2 つの xcframework だけで C / Objective-C のアプリ、26.6 と 26.3 で組む | **要る**。Swift を持たないアプリに Swift の実行環境が要らないことは macOS 15 でも成り立つ見込み[推測] |
| 人の確認（computer use） | Simulator.app のウィンドウか iPhone ミラーリングを見る | **要る**。この Mac の画面そのものを見るので、私物の画面（ほかのアプリ、通知、デスクトップ）が写る |

### 5.2 私物を守る仕組みがどう変わるか（`agent-rules/device-testing.md` を基に）

[事実] 今の規則は「iOS の実機 = 私物の iPhone」と「シミュレーターの間の Mac のクリップボード」を守る。**macOS の UI テストと C ABI のテストは、利用者が今使っているこの Mac で、本物の通知センター、本物の general pasteboard、本物の共有のサービス、本物のファイルシステムに触れる。** 規則の各節の macOS での形（提案）:

| 今の規則（行） | macOS での形（提案） |
|---|---|
| 流す前に毎回許可（:8-17。一覧・起きること・準備・時間の 4 つ、`--dry-run` と `--approved`、1 回限りの ID） | **そのまま全件に**。シミュレーターのような「許可の要らない場所」が無いので、unit を除く全部（UI テスト、`--capi`、`--capi-ui`、smoke、更新のテスト）を許可の対象にする。純粋な単体テスト（AppKit・UserNotifications・NSPasteboard の general に触れないもの）だけを許可なしにするなら、その区分を宣言で照らす |
| simulator only（:19-23） | 「VM だけ」の区分に置き換える（VM を用意する場合）。用意しないなら「人の確認だけ」 |
| 1 回ごとに聞く操作（:25-33） | macOS 版: アプリの削除・入れ直し、`tccutil reset` などの権限のリセット、通知の権限、システム設定の変更、**general pasteboard を読む・書くテスト**、Share のピッカーから実在のサービス（AirDrop、メール、メッセージ、メモ）へ送りうる操作、通知センターの操作、保存のパネルでファイルを書くこと、Dock のバッジ |
| 準備（:37-48。ロックを外す、集中モード、Handoff を切る） | macOS 版: テストの間、利用者はこの Mac のマウスとキーボードに触れない（XCUITest が前面を取り、入力が混ざると落ちる）[推測]。画面のロックとスクリーンセーバーを止める。集中モードでサンプルだけを許す。Handoff・ユニバーサルクリップボードを切る（iPhone のクリップボードと混ざる）。XCUITest のためのアクセシビリティの許可は利用者が与える[推測] |
| 私物を残さない（:50-55） | `.xcresult` のスクリーンショットにデスクトップ・ほかのアプリ・通知が写る。iOS の実機と同じく、結果を書き写したら消し、添付を出さない。画面の階層のダンプを出さない |
| Mac のクリップボード（:57-66。agent は `pbcopy`/`pbpaste` を使わない、Mac のクリップボードを読み書きしない） | **macOS の Clipboard のテストはこの規則とぶつかる**。案: (a) テストは named / unique の pasteboard（`NSPasteboard(name:)`、`withUniqueName()`）を既定にし、general は宣言した区分（`clipboard-general`）だけで、毎回の許可の後、(b) general を書くテストの前後で中身を保存して戻すのは「読む」ことになるので、しない（上書きすると利用者に告げて許可を得る）。iOS のシミュレーターの節（Simulator.app を開かない、`pgrep -x Simulator`）は macOS には関係しない |
| 端末を特定する値を書かない（:52） | この Mac の名前・ユーザー名・ホームのパスを結果とログの写しに書かない（`path_inside` の作法で出力を閉じ込める）。Team ID は書かない（S2N 17.12 のウ） |

**大きな選択肢（推奨を 1 つ）**: **macOS の UI テストと更新のテストは、この Mac の上の macOS の VM（Apple Silicon の Virtualization。macOS 15 と 26 の 2 つ）で流し、VM をシミュレーターの代わりにする。この Mac の上で直接流すのは、許可を得た区切りだけにする。** 理由: iOS の「シミュレーターでいつでも流し、私物の端末は区切りで許可」という分け方をそのまま保て、最小の macOS 15 の基準も取れ、general pasteboard と通知センターを汚さない。危うさ: VM の用意（macOS のイメージ、Xcode の導入、ディスク）の手間、VM の中で通知・Share・アクセシビリティの許可が実機と同じに振る舞うかは確かめていない[推測]、VM の中で XCUITest を動かすための自動ログインと権限の付与が要る[推測]。VM を作らないなら、全件の実行のたびに 5.2 の許可が要る

---

## 6. 企画で先に確かめること（このファイルの推測の一覧）

1. Unity の macOS（Player と Editor）で、プラグインの読み込みの時期と、起動の中で `ntk_notification_install` を呼べる口（D-4、知見 1）
2. Editor の中のドメインのリロードの後、古い関数ポインタが受け手の表に残らないか（5.1 の「Unity Editor」の行）
3. `runModal` の中で main キューに積んだブロックが走るか（入れ子の再入）と、sheet にした場合の同時の要求（D-6、D-8、P1-12）
4. `NSSharingServicePicker` が mouseDown の文脈の外（main に積んだブロック）から出せるか（P1-4、P2-1）
5. 通知のクリックで起動したときの `didReceive` と `didBecomeActive` の順（P1-22）、許可の問い合わせがアプリが後ろでもどう出るか
6. macOS の貼り付けのプライバシー（`accessBehavior` が ask のとき）で、読み出しが main を止めるか（P2-24）
7. 配る framework の署名（なし / ad-hoc / Developer ID）と Gatekeeper・quarantine・Unity Editor の読み込み（D-18）、プライバシーマニフェストの要否と置き場所
8. macOS 15 で `Synchronization` と `@c @implementation` の出力が動くこと（D-15、D-16）
9. XCUITest が macOS のシステムの UI（通知のバナー、許可の問い合わせ、共有のピッカー、ファイルのパネル、貼り付けの警告）を扱えるか（iOS の段階 0a に当たるスパイク）
10. VM で 9 が同じに動くか（5.2 の推奨）
