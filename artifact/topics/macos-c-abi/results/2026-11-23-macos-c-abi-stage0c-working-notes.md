# 段階 0c の作業の記録

- 記録日: 2026-11-23（書き足していく）
- 段階: 0c（UI テストの実装。企画 5 章、UI テストの設計書 `designs/2026-11-23-macos-c-abi-ui-test-design.md`）
- 状態: 1 章（共通・Dialog・Share）が終わった。2 章（Notification）と 3 章（Clipboard）はこれから。段階の結果は 0c の終わりに別に書く
- 元にした版: `bab34db1`（feature/NTKIT-19、0b）。コミットはしていない
- 環境: この Mac では組むだけ（Xcode 26.3 と 26.6）。動かす確かめは VM `ntk-macos-15-new`（macOS 15.8.3、Xcode 26.3、en-US、`--no-graphics --no-clipboard`）だけ。この Mac では UI・通知・クリップボードを使うものを何も動かしていない

## 1. 共通・Dialog・Share

### 1.1 作ったもの（`mac/MacLibraryExample/MacLibraryExampleUITests/`）

| ファイル | 中身 |
|---|---|
| `Support/SampleUITestCase.swift`（基底） | 入口の `final override`（async の形は上書きしない。iOS の 0c と同じ）、宣言の区分 10 個と印の型 10 個（初期化子は `fileprivate`）、`self.name` の正規化（`-[MacLibraryExampleUITests.C m]` と `-[C m]` → `C/m`。ほかは throw）、宣言の表の読み込み（キーの重複・知らない区分・区分の重複を throw）、ホストの判定（`NTK_HOST` が `vm` ちょうどで、かつ `sysctl kern.hv_vmm_present` が 1 のときだけ VM。`vm` なのに 1 でなければ throw。ほかの値はこの Mac）、`NTK_ALLOW` の読み取り（知らない区分は throw、この Mac で VM だけの区分を渡されたら throw）、許されない区分は `XCTSkip("NTK-GATED:<区分>")`、監視の取り付け、押したボタンの記録の添付（5.7）。監視の印が立ったら `tearDownAfterGate` を呼ばない。終わりにサンプルを止める（アラート・パネル・ピッカーを画面に残さない） |
| `Support/SampleApp.swift` | `XCUIApplication` を持つ。識別子の写し（画面、Dialog 6、Notification 22、Share 15、Clipboard 36、ボタンでない識別子）、ボタンごとの要る区分（印の要らない押し口と、印を取る押し口）、結果の行の読み方（`#<n> <本文>` を 1 つの値で読む `ResultLine.parse`、2 段の口 `resultSequence` → `waitForNextResult(after:marker:)`、余分な完了の 2 秒 `expectNoFurtherResult`）、押す前の確かめ（下の 1.3）、スクロールで見える範囲に入れる口、キーの前の確かめ、1 回の snapshot での識別子の集め方、`SampleAlert` |
| `Support/Panels.swift` | `PanelsToken` が要る。fixture のパスを `NTK_FIXTURE_DIR` から読み、`/private/tmp/ntk-uitest-<id>` の形でなければ throw。パネルを待つ、Cmd+Shift+G（Cmd+A で前の道を消してから入れる）で fixture に移り、場所のポップアップ（`where popup`）が fixture の名前になるまで待つ、**列の中身がちょうど fixture の 7 項目である列 1 つの中だけ**から項目を取って押す（Cmd を押しながらの追加も）、保存の名前、`Replace`、`OKButton`・`CancelButton` |
| `Support/SharePicker.swift` | `SharePickerToken` が要る。ピッカー（アプリの木の `Popover` ちょうど 1 つ）を待つ、サービスの数を数える（名前は読まない）、名前を決めた 1 つのサービスの数（S10）、Escape（開いたメニューが無いときだけ）、出ないことを 2 秒見る、`Copy`（`ClipboardToken` も要る。無ければ押さずに `NTK-STEP:copyMissing`） |
| `Support/RunnerPasteboard.swift` | `ClipboardToken` が要る。一般の貼り付け板に合成の文を書く、`changeCount` の照合、書いた後だけ読む（S2・S4） |
| `Support/OtherApps.swift` | `RealServiceToken` が要る。S11 の前に Mail が動いていたかを読み、動いていなかったときだけ後で止める |
| `Support/UnexpectedInterruptionGuard.swift` | U-8: 何も押さず、ラベルを読まず、サンプルを止めて印を立て `true` を返す |
| `Support/SystemLabels.swift` | システムの UI の識別子とラベルの表（en は VM で取った。ja は U-30 で取るまで推測の値）。押す前の確かめで素通しする全画面の窓の持ち主 3 つ |
| `Support/StepCode.swift` | `NTK-STEP:<段>` の語彙（24 個）。Support が投げる失敗はすべて `NTK-STEP:<段>` で始まる |
| `Support/DeviceRequirements.json` | 宣言の表。56 件（下の 1.2 の 41 件と `SupportRuleTests` の 15 件） |
| `NavigationUITests.swift`、`IdentifierInventoryUITests.swift`、`DialogUITests.swift`、`ShareUITests.swift`、`SupportRuleTests.swift` | テスト（1.2） |

消したもの: `ShareSampleViewUITests.swift`（17 件。S1〜S17 に置き換えた）、雛形の `MacLibraryExampleUITests.swift`（2 件）と `MacLibraryExampleUITestsLaunchTests.swift`（1 件）。Clipboard の 2 クラス（17 件）はこの段では触れていない（今も `XCTestCase` のまま）。サンプルと `MacLibrary` は変えていない。

### 1.2 テストの数と区分

| 機能 | ケース | クラス | 宣言 | VM で流す | 流さない（理由） |
|---|---|---|---|---|---|
| 共通 | 7（M1a、M1b、M2、I1a〜I1d） | `NavigationUITests`（3）、`IdentifierInventoryUITests`（4） | すべて `-` | 5 | M1b・M2（26 だけ。U-33） |
| Dialog | 17（D1〜D17） | `DialogUITests` | D7〜D15・D17 が `panels`、ほかは `-` | 17 | - |
| Share | 17（S1〜S17） | `ShareUITests` | S1・S3・S5〜S10・S13〜S16 が `sharepicker`、S2・S4 が `sharepicker`・`clipboard`、S11・S12・S17 が `realservice` | 15 | S2・S4（26 だけで、この Mac でも `Copy` の持ち主を U-30 で確かめるまで保留） |
| 設計書の外 | 15（規則の自己テスト） | `SupportRuleTests` | すべて `-` | 15 | - |
| 計 | 56 | 6 クラス | | **52** | 4 |

設計書の 5.8 の数（共通 7、Dialog 17、Share 17）とは一致する。`SupportRuleTests` は設計書の 95 件の外で、押す前の確かめ・結果の行・ゲート・fixture の純粋な規則を、何も起動せずに直接確かめる（`common.md` の「判定規則そのものが対象なら、規則を純関数に切り出して直接壊す」。1.6 で壊した）。

### 1.3 押す前の確かめ（5.0 のうちサンプルの窓とパネル）

- すべての押下・スクロール・キーが `SampleApp` の口を通る。押す前に、サンプルが `runningForeground`、要素の枠が空でない、要素がスクロールの中にあれば見える範囲に入れる（0b の申し送りの「見える範囲の外のボタンの空振り」）、そのうえで要素の中心の点で窓を読む
- 窓は `CGWindowListCopyWindowInfo`（画面にあるもの、デスクトップの要素を除く、前から順）の持ち主の PID・層・透明度・枠だけを読む。名前は読まない。持ち主の bundle id は PID から `NSRunningApplication` で引く
- 判定は純粋な関数 `OverlayRule.verdict`: 「何も受けない窓」を除いた中で点を含む最初の窓の持ち主が、許した PID（サンプル。パネルではパネルの view service も）か。違えば `blocked`（通知センターなら `notificationCenter`）。許した窓でも、その前に通知センターの窓が要素の枠に重なれば `notificationCenter`。`blocked` は 5 秒、`notificationCenter` は 10 秒まで読み直し、だめなら押さずに `NTK-STEP:overlay` / `notificationOverlay`
- 「何も受けない窓」: 透明度 0、カーソルの層（2147483630）以上、**持ち主が `com.apple.dt.AutomationModeUI`・`com.apple.notificationcenterui`・`com.apple.dock` のどれかで、枠がディスプレイ全体とちょうど同じ窓**。VM では、この 3 つの全画面の窓（層 1000・23・20）がいつもサンプルの前にあり、クリックは素通りした（1.4）。ほかの持ち主の全画面の窓、持ち主の無い窓、この 3 つの持ち主でもディスプレイより小さい窓（通知のバナーなど）は素通ししない
- キーの前: サンプルが前面のアプリ（`NSWorkspace.frontmostApplication` の PID）で、入力の欄には `hasKeyboardFocus`（KVC。VM で読めた）が true。アラートのキーはアラートがちょうど 1 つ、ピッカーの Escape はピッカーがちょうど 1 つで開いたメニューが無いとき

### 1.4 VM で確かめた事実（設計書 9.1 のうちこの段の分）

| 項目 | 結果 |
|---|---|
| `TEST_RUNNER_` の環境変数（9.3） | `test-without-building` に `TEST_RUNNER_NTK_HOST` などを渡すと、ランナーに `NTK_HOST`・`NTK_ALLOW`・`NTK_FIXTURE_DIR` で届いた |
| ランナーから `sysctl kern.hv_vmm_present` | 読めた（1） |
| ランナー（sandbox）から `CGWindowListCopyWindowInfo` | 読めた。PID・層・透明度・枠が取れ、画面の収録の許可は要らなかった（名前は読んでいない） |
| サンプルの前にいつもある窓 | `com.apple.dt.AutomationModeUI`（層 1000、全画面）、`com.apple.notificationcenterui`（層 23、全画面）、`com.apple.dock`（層 20、全画面）、メニューバー（層 24、高さ 24、持ち主の bundle id なし）、メニューバーの項目（層 25）、カーソル（層 2147483630、持ち主の bundle id なし）。サンプルの窓の点を押すと、前の 3 つの全画面の窓を素通りしてサンプルに届いた |
| アラート・パネル・ピッカーの窓の持ち主 | どれも**サンプルのプロセス**（アラートとパネルは層 8、ピッカーは層 101）。パネルの view service は窓を持たなかった。パネル・アラート・ピッカーが開いている間もサンプルは `runningForeground` で前面のアプリだった |
| アラートの部品（9.1） | ボタンは `action-button-1`（OK）・`-2`（Cancel）・`-3`（Delete。画面では 2 番目）、ヘルプは identifier が `_NS:<n>` で label `Help`、チェックボックスは `CheckBox` で identifier `supression-checkbox`（Apple の綴り）、title `Don't show this again`、値 0/1。Return は既定の OK、Escape は Cancel、`d` は Delete |
| アラートの結果の全文（9.1） | `ShowDialog - result: DialogResult(buttonIndex: <n>, buttonTitle: "<題>", suppressionButtonState: <b>, helpButtonPressed: <b>, isSuccess: true)`。ヘルプは `buttonIndex: -1, buttonTitle: ""`、`helpButtonPressed: true`。ヘルプの後もアラートは開いたまま |
| パネルの場所の読み方（9.1） | 場所のポップアップ（identifier `where popup`）の値が今のフォルダーの名前。開く・保存のどちらにもある。前に使った場所で開く（開くパネルは初回 `Documents`、保存のパネルは前の回の fixture） |
| Cmd+Shift+G | `GoToWindow` の sheet と、焦点を持つ `PathTextField`（前の道が入っている）が出る。保存のパネルの小さい形でも使えた |
| パネルの項目 | 列の表示（`ColumnView`）の各列は `ScrollView` で、項目は `Group` の中の `TextField`（値がファイル名）。fixture の列は 7 項目だけを並べた |
| フォルダーのパネル | `dirA` を押すと場所が `dirA` に移る（ポップアップの値が `dirA`）。そのまま `OKButton` で `filePaths: ["<fixture>/dirA"]`、`directoryURL: "<fixture>/dirA"`。2 つ選ぶ（`dirA`、Cmd を押して `dirB`）と `directoryURL: "<fixture>"` |
| 保存のパネル | 既定の名前で保存すると `Replace` の確認（ボタンの title `Replace`）が出る。名前を `new-file` にすると確認は出ず、`<fixture>/new-file.txt` を返した。ファイルは作られなかった |
| パネルの「アプリの idle を待つ」止まり（9.0 の 3） | この段の 3 回と途中の確かめでは一度も起きなかった（原因は分からないまま） |
| fixture の中身 | 7 項目の名前・種類・ハッシュはどの回も変わらなかったが、**パネルが fixture に `.DS_Store` を書いた**（1 回目の全件の後に見つけた。1.7） |
| Share のピッカー（9.1） | `Popover` ちょうど 1 つ。ShareText は 6 つ、ShareURL は 9 つのボタン。**除外しない ShareURL のピッカーに `Add to Reading List` があり、ShareExcludingServices のピッカーには無かった**（S10 は 15.8.3 で除外が効いたことを確かめられる）。`Copy` は無い（M-3） |
| Share のエラーの文（9.1） | 1401 `No shareable items were provided.`、1402 `Invalid URL: not a valid url.`、1404 `File not found at path: /nonexistent/share-missing.txt.`、1403 `Failed to load image at path: /nonexistent/share-missing.png.`、1406 `Sharing service unavailable: invalid.service.` |
| CanPerformMail・ShareViaMail（9.1） | `canPerform=true`。ShareViaMail は `completed=true, service=Mail` |
| Mail を止める | ランナーからの `NSRunningApplication.terminate()` では止まらなかった（sandbox の見込み）。`XCUIApplication(bundleIdentifier:).terminate()` で止まった |
| I1 の除き方（9.1） | 識別子の無いボタンは、スクロールバー（`ScrollBar`）の子の 2 つ（ページの領域と見ている）、ツールバーの `chevron.backward`（1 つ）、窓の `_XCUI:` の 3 つ、Clipboard の画面では `PasteButton`（identifier なし、label `Paste`）。1 回の snapshot で画面の外のボタンも取れた（スクロールせずに全部一致） |

### 1.5 VM の 3 回

選んだのは設計書のとおり、VM で流す 52 件（M1a、I1a〜I1d、D1〜D17、S1・S3・S5〜S17、`SupportRuleTests` の 15 件）。M1b・M2（26 だけ）と S2・S4（26 だけ・保留）は名指しから外した。`TEST_RUNNER_NTK_HOST=vm`、`TEST_RUNNER_NTK_ALLOW` に 10 区分、`TEST_RUNNER_NTK_FIXTURE_DIR=/private/tmp/ntk-uitest-s0c`、`-parallel-testing-enabled NO`、`-test-timeouts-enabled YES`、`-default-test-execution-time-allowance 120`、`-maximum-test-execution-time-allowance 240`。各回の前に fixture を作り直し、Mail を止めた。ソースは未コミットの変更を含むので `mac/`（`Build`・`Docs`・`xcuserdata` を除く）を `tar` で写し、VM の中で Xcode 26.3・ad-hoc で組んだ（コンパイラーの警告 0）。

| 回 | 結果 | 時間 | fixture |
|---|---|---|---|
| 1 | 52/52 passed | 490 秒 | 7 項目は変わらず。`.DS_Store` が増えた |
| 2 | 52/52 passed | 432 秒 | 同じ |
| 3 | 52/52 passed | 438 秒 | 同じ |

クラスごとの目安（1 回）: Dialog 255〜301 秒、Share 141〜157 秒、I1 14〜17 秒、M1a 17 秒、`SupportRuleTests` 1〜2 秒。

3 回の前に直したこと（どれも固定の待ちは足していない）:

- D11: 結果の `directoryURL` が `<fixture>` でなく `<fixture>/dirA` だった（今の動作。期待値を実物に合わせた）
- D12: `dirA` を押すと場所が `dirA` に移るので、2 つ目の `dirB` を選ぶ前の「場所が fixture」の確かめで落ちた。Cmd を押して足す選択に限り、場所が fixture のフォルダー（`dirA`・`dirB`）でもよいとした。項目はいつも「中身がちょうど fixture の 7 項目の列」の中だけから取るので、fixture の外は押せない（1.7 の 2）
- S11: Mail を止められなかった（ランナーの `NSRunningApplication.terminate()` が効かない）。`XCUIApplication(bundleIdentifier:).terminate()` に替えた
- 確かめのとき、ShareUITests をクラスごと流して S2・S4 も 1 回動いた。どちらも `Copy` を押さずに `NTK-STEP:copyMissing` で落ちた（15 に `Copy` は無い。15 で成功の経路を確かめないまま通ることはない）

0b で揺れたメールの 2 件（S11・S12）は、待ちを 30 秒にして 3 回とも通った（どちらも 7〜18 秒で終わった）。0a・0b で 2 回のうち 1 回止まったパネルの「アプリの idle を待つ」は起きなかった。

### 1.6 変異

壊すのは VM の写しだけで、確かめた後は写しごと消した（リポジトリには残していない）。壊し方は `python` で写しの文を 1 か所ずつ置き換えた（置き換える文がちょうど 1 回現れることを確かめてから）。

| 設計書 7 章の行 | 壊したもの | 流したテスト | 結果 |
|---|---|---|---|
| Dialog | `showDialog` の完了を 2 回呼ぶ（`MacDialogManager`） | D1、D16 | 両方落ちた（`NTK-STEP:extraResult`、#1 の後に #2） |
| Dialog | ヘルプの完了を呼ばない（`alertShowHelp` の中で受け手を nil にした） | D5 | 落ちた（`resultTimeout`、#0 のまま） |
| Dialog | 3 つ目のボタンの番号を 0 に固定（`getButtonIndex`） | D3、D6（と対照の D1） | D3・D6 が落ち、D1 は通った |
| Dialog | 保存のパネルで、返す前にファイルを書く | D13、D15 と fixture の照合 | D13・D15 は通り（設計書どおりテストは結果の文だけを見る）、**fixture の照合で `default.txt` のハッシュの変化と `new-file.txt` の増加が見つかった**（照合は 0d のランナーの役目。ここでは VM の手の照合） |
| Share | 完了をいつも `completed=true` で返す（`MacShareManager.share` の async 版） | S1、S3 | 両方落ちた（全文の不一致） |
| Share | 完了を 2 回届ける | S1、S13 | 両方落ちた（`extraResult`）。async の API は 2 回返せないので、サンプルの `runShare` で結果の表示を 2 回にして「2 回届いた」を作った |
| Share | サンプルの除外のリストを空にする | S10 | 落ちた（`Add to Reading List` が 1 つ）。15.8.3 では除外しないと出るので、除外が効いたことの確かめになっている |
| Share | `ShareError.noValidItems` の文を変える | S13 | 落ちた |
| 識別子 | Dialog に識別子の無いボタンを足す | I1a | 落ちた（識別子の無いボタン 1） |
| 識別子 | Share に、間接の補助（`extraID()`）で一覧に無い識別子のボタンを足す | I1c | 落ちた（ボタン 16、一覧 15） |
| 識別子 | Notification の 2 つのボタンに同じ識別子（`RemoveCategory` に `RegisterCategory` の識別子） | I1b | 落ちた（重複） |
| 押す前の確かめ | VM で、合成のアプリ（`NSPanel`、浮く層、クリックを数えてファイルに書く）の窓を ShowDialog の上に置いて押す（一時のテスト。写しにだけ置いた） | 一時のテスト | **確かめあり**: 押さずに `NTK-STEP:overlay ... (blocked)` で止まり、合成の窓のクリックは 0。合成のアプリを止めると同じ押下が通った。**確かめを外した版**: 押下の前に XCTest 自身がその窓を「別のアプリの Dialog」と見て割り込みの監視を呼び、監視（U-8）がサンプルを止めて印を立てた。XCTest はその後サンプルを起動し直し、`Failed to click ... ` で落ちた。クリックは 0 のまま（確かめと監視の二重の守り。確かめを外した版でクリックが合成の窓に届く形は作れなかった） |
| （規則） | `OverlayRule`: 決まった持ち主の窓なら大きさを見ずに素通しする | `SupportRuleTests` | 「ディスプレイより小さい窓は止める」と「要素に重なる通知の窓」の 2 件が落ちた |
| （規則） | `OverlayRule`: サンプルの窓の前の通知の窓の重なりを見ない | 同 | 「要素に重なる通知の窓」が落ちた |
| （規則） | `ResultLine.judge`: 錨を外して `contains` にする | 同 | 「次の結果だけを受ける」（細部の語）が落ちた |
| （規則） | Share の結果の印から `] ` を外す（`[shareText`） | 同 | 「長い名前が短い名前の代わりにならない」が落ちた（`shareTextAndURL` が `shareText` の代わりになった） |
| （規則） | この Mac で VM だけの区分を許す | 同 | 「許す区分」が落ちた |
| 二段目 | `NTK_HOST=vm` のとき `kern.hv_vmm_present` を見ない | 同 | 「VM は事実で決める」が落ちた（設計書の「判定の関数に 0 を渡して確かめる」の形） |
| 柱 2 の一部 | 宣言の表に無いテスト | 一時のテスト（表に足し忘れた回） | setUp で `NTK-STEP:gate ... has no entry` で落ちた（意図した変異ではないが、同じ事実） |

ここで試していない 7 章の行: 全ボタン（5.7。照合は 0d の VM の全件で行う）、柱 1〜3・出力の境界・中断・強制終了の後（0d のランナー）、Notification・Clipboard・根・片付け・監視の押す枝（2 章・3 章と 0d）。

### 1.7 設計書との差

設計書は直していない。親が反映を決める。

| # | 所 | 設計書 | 実際・したこと |
|---|---|---|---|
| 1 | 5.0 の押す前の確かめの「何も受けない窓」 | 透明・特別な層の窓を除く条件は 9.1 で確かめる | VM では、自動化のモードの窓（`com.apple.dt.AutomationModeUI`、層 1000）・通知センター（層 23）・Dock（層 20）の**全画面の窓がいつもサンプルの前**にあり、透明度は 1 だった。透明度と層だけでは除けないので、「この 3 つの持ち主で、枠がディスプレイ全体とちょうど同じ窓」とカーソルの層以上を除く規則にした（`OverlayRule.isPassive`、自己テストつき）。とくに通知センターは**全画面の窓をいつもサンプルの前に持つ**ので、5.0 の「サンプルの窓より前にある `com.apple.notificationcenterui` の窓と重ならない」は、全画面の窓を除いた残り（バナーなど）にだけ当てた。26 で同じかは U-30 |
| 2 | U-11「移った先の今の場所が fixture であることを確かめてから選ぶ」 | 場所が fixture | フォルダーのパネルでは 1 つ目のフォルダーを押すと場所がそのフォルダーに移る。Cmd で足す選択に限り場所が fixture のフォルダーでもよいとし、項目は「中身がちょうど fixture の 7 項目の列」1 つの中だけから取る |
| 3 | U-11「fixture の中身（名前・種類・ハッシュ）が変わっていないこと」 | 変わらない | パネルが fixture に `.DS_Store` を書く（3 回とも）。7 項目は変わらない。0d のランナーの照合は `.DS_Store` を除くか、パネルの表示の設定を書かせない手段を決める必要がある |
| 4 | 4.1・I1d の Clipboard の識別子 54 | `clipboard.pasteButton` を数える | 15.8.3 の木に `clipboard.pasteButton` は無い（0b と同じ）。I1d の期待は 15 では 53（入れ物を除く）、26 では 54 のままにした。`PasteButton` 自体は識別子が無く label `Paste` なので、ラベルの表（`SystemLabels.paste`）で 1 つだけ除く |
| 5 | 5.2 D11 の期待 | `<fixture>/dirA`（`directoryURL` は書かれていない） | `directoryURL` は `<fixture>/dirA`。D12（2 つ）は `<fixture>` |
| 6 | 5.0 のパネルの持ち主 | サンプルか view service | VM ではパネルの窓の持ち主はサンプル。view service の PID も許す形は残した |
| 7 | 5.4 S10 | 「除外が効いたことの証明にはならない」 | 15.8.3 では除外しない ShareURL のピッカーに `Add to Reading List` が出るので、S10 は除外が効いたことを確かめている（変異で落ちた） |
| 8 | 5.8 の件数 | 95 件 | 規則の自己テスト `SupportRuleTests`（15 件、宣言 `-`、何も起動しない）を足した。95 件の外 |
| 9 | 6.1 の `SampleApp` が `XCUIApplication` を private に持つ | private | `Panels`・`SharePicker`・`SampleAlert` が別のファイルなので、`supportRoot` として internal で出した。テストのクラスからは使わない（0d の閉じた形の規則で `supportRoot` を Support の外で禁じる必要がある） |
| 10 | U-8 の監視 | 押さずに止めて `true`、包む関数で throw | 1.6 のとおり、監視が止めた後に XCTest がサンプルを起動し直して自分の失敗で止まった（iOS の 0c の (b) と同じ）。テストは止まるが、包む関数の throw までは届かない |
| 11 | 3.4 の「NTK-INTERRUPTED」 | 理由の符号 | 監視の失敗の文は `NTK-STEP:interrupted NTK-INTERRUPTED ...` の形（両方の符号が入る） |

### 1.8 残したこと

- M1b・M2（26 だけ）と S2・S4（26 だけ・保留）は書いたが、一度も通していない（S2・S4 は 15 で `copyMissing` で止まることだけ見た）。この Mac の区切りで、許可を得て U-30 の後に流す
- ja のラベル（`SystemLabels` の `ヘルプ`・`置き換える`・`コピー` など）は推測の値。U-30 の `vm-ja` で取る
- 押した識別子の記録の添付（`ntk-button-coverage-v1.json`）は各テストに付くが、和集合の照合（5.7）は 0d
- U-8 の監視が「何も押さない」ことは、合成の窓の場面で 1 回見ただけ（無害な試験用のアラートでの確かめは 0d の前に）
- Clipboard の 2 クラスは今も `XCTestCase` のまま（3 章で載せ替える）。宣言の表にはまだ入っていない
- この Mac の DerivedData は scratchpad の `stage0c-ds/` に残した（組み立ての確かめだけ。この Mac では何も起動していない）
- VM の後片付け: 写し・DerivedData・ログ・結果のバンドル・合成のアプリ・fixture を消し、写しのサンプルと合成のアプリの LaunchServices の登録を外した。VM の空きは 8.1 GiB。前の段の `~/ntk/dd263` などには触れていない

### 1.9 組み立て（この Mac）

| Xcode | `build-for-testing` | エラー | コンパイラーの警告 |
|---|---|---|---|
| 26.3（17C529） | 成功 | 0 | 0（`appintentsmetadataprocessor` の 4 は 0b と同じ） |
| 26.6（17F113） | 成功 | 0 | 0（同） |

DerivedData は scratchpad、署名は ad-hoc（0b と同じ）。宣言の表がテストのバンドルの `Resources` に入ったことを確かめた。

## 2. Notification

（後で）

## 3. Clipboard

（後で）
