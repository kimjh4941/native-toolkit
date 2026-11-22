# 段階 0c の作業の記録

- 記録日: 2026-11-23（書き足していく）
- 段階: 0c（UI テストの実装。企画 5 章、UI テストの設計書 `designs/2026-11-23-macos-c-abi-ui-test-design.md`）
- 状態: 1 章（共通・Dialog・Share）と 2 章（Notification）が終わった。3 章（Clipboard）はこれから。段階の結果は 0c の終わりに別に書く
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

### 2.1 作ったもの（`mac/MacLibraryExample/MacLibraryExampleUITests/`）

| ファイル | 中身 |
|---|---|
| `Support/NotificationRules.swift`（新規） | 純粋な規則: 根の錨 `BannerAnchor`（`<app>, <題>, <app>, <本文>` の全文の一致。サンプルの 6 つの通知の錨）、最後のイベントの読み方 `LastEvent` と照らし方 `ExpectedEvent`（全項目の一致。ShowImmediate の id は `mac-sample-notification-<数字>`、userInfo は同じ id から導く）、コピーの印 `LaunchCopy`、`GetScheduled` / `GetDelivered` の一覧 `NotificationIDList`（形・数・重複の照らし）、秒の窓 `SecondsWindow`（U-14c）、通知センターを押す前の確かめ `NotificationOverlayRule`（根の本文・`Options` と、メニューの項目の 2 種） |
| `Support/NotificationCenterUI.swift`（新規） | `NotificationToken` が要る。根を錨と `.element` で取り（2 つ以上は押さずに失敗）、最初に取った group の identifier を覚えて、以後の段ごとに取り直して同じ identifier であることを確かめる（差し替えで失敗）。本文のクリック（出てから 1 秒。U-14b）、hover、根の中の `Options`、`Options` が開いた 1 つのメニューの中の項目（title で 1 つ、メニューの枠の中）、Escape、根の中の返信の欄（`TextView` 1 つ、焦点あり、通知センターが前面）への入力と Return、許可の問い合わせ（`NCSettingsToken` も要る）。押す前に、サンプルの状態が筋書きの状態（前面・後ろ・`notRunning`）であることと `NotificationOverlayRule` を確かめる。読むだけの口 `NotificationCenterRead`（サンプルの根の数、問い合わせの数、開いたメニューの枠） |
| `Support/NotificationScreen.swift`（新規） | 通知の画面の段: 1 回押して次の番号の結果を待ち、2 秒の余分な完了を見る（`run`）、すぐ出るバナーの押下（結果 → 根 → 2 秒。`runShowing`）、一覧の押し直し（U-6。直列、0.5 秒おき、10 秒まで、最後の 1 回だけ 2 秒）、秒の窓の待ち、最後のイベントの待ちと 2 秒、押した時刻 |
| `Support/NotificationCleanup.swift`（新規） | U-7・U-15: 読むだけの「根が 0 件」の待ち（15 秒）、AuthorizationStatus が `authorized` でなければ `NTK-PRECONDITION:notAuthorized`、片付けは RemoveAllDelivered と CancelAllScheduled だけ、バッジ 0 は `BadgeToken` があり `authorized` と読めたときだけ |
| `Support/SampleApp.swift`（足した） | 印を取る押し口 3 つ（`notification`、`settings`、`badge` と `notification`）、結果の印の 4 つの例外（`[removeDelivered]`、`[cancelScheduled]`、`[setBadgeCount(1)]`、`[setBadgeCount(0)]`）と許可が無いときの文、最後のイベントとコピーの印の読み取り、`activate`、状態の待ち、コールドスタートの止め方と起こされたプロセスの引き取り（`launch()` を呼ばない）、結果の行の上への hover、最後のクリックの時刻。押す前の確かめに**通知の一覧の枠**（2.3 の 2）を足した |
| `Support/OtherApps.swift`（足した） | Finder を前に出す（`NotificationToken`）、システム設定の前面の待ちと、前に動いていなかったときだけ止める（`SettingsToken`） |
| `Support/SampleUITestCase.swift`（足した） | 宣言を読むだけの `declares`、ランナーの `NTK_EXPECTED_COPY` の読み取り（`ColdStartToken`） |
| `Support/SystemLabels.swift`、`StepCode.swift`（足した） | 通知センターの表（label の区切り、一覧の identifier、`Options`、問い合わせの label の前置き、`Allow` / `Don’t Allow`、Finder とシステム設定の bundle id）、段の符号 13 個（`precondition`、`notificationRoot`、`notificationAction`、`notificationReply`、`notificationState`、`permissionPrompt`、`notificationList`、`secondsWindow`、`settings`、`coldStart`、`lastEvent`、`launchCopy`、`finder`） |
| `NotificationPermissionUITests.swift`（3）、`NotificationUITests.swift`（19）、`NotificationEventUITests.swift`（5）、`NotificationColdStartUITests.swift`（3） | テスト（2.2） |
| `SupportRuleTests.swift`（8 件足した）、`Support/DeviceRequirements.json`（38 行足した） | 規則の自己テスト（通知センターの押す前の確かめ、通知の一覧の枠、根の錨、最後のイベント、一覧、秒の窓、コピーの印）と宣言（2.2） |

サンプルと `MacLibrary` は変えていない。1 回目の Support の口はそのまま使い、変えたのは押す前の確かめに通知の一覧の枠を足したこと（Dialog・Share のテストにも当たる）だけ。

### 2.2 テストの数と区分

| クラス | ケース | 宣言 | VM で流す | 流さない（理由） |
|---|---|---|---|---|
| `NotificationPermissionUITests` | NP1〜NP3 | `notification`・`ncsettings` | 3（権限の段。各テストの前に VM で許可を戻す） | - |
| `NotificationUITests` | N1〜N18、N14b | N1・N17 は `-`、N3 は `settings`、N18 は `badge`・`notification`、ほかは `notification` | 19 | **N19 は書いていない**（Dock のバッジが木から読めない。2.6 の 1。HC3 に移す） |
| `NotificationEventUITests` | N20〜N24 | `notification` | 5 | - |
| `NotificationColdStartUITests` | NC1〜NC3 | `notification`・`coldstart` | 3 | - |
| 計 | **30**（設計書 5.8 の 31 から N19 を除いた） | | **30** | 1 |
| `SupportRuleTests`（足した分） | 8 | `-` | 8 | - |

宣言の表は 94 件（1 回目の 56、Notification 30、規則の自己テスト 8）。5.8 の宣言の区分の数（N19 を除く）とは、`notification` 27、`ncsettings` 3、`settings` 1、`badge` 1、`coldstart` 3 で一致する（`badge` と `notification` は N19 の分だけ少ない）。

この Mac で保留する N20・N23・N24・NC2・NC3（`MAC_DEFERRED_TESTS`）は、ランナー（0d）の表で除く。テストのコードには環境の分岐を入れていない。

### 2.3 VM で確かめた事実（設計書 9.1 のうちこの段の分）

探りのテスト（`Stage0cNDiscoverTests` など）は VM の写しにだけ置き、リポジトリには入れていない。階層は VM の中でだけ出した。

| 項目 | 結果 |
|---|---|
| `Options` と `Show Details`（0b の 5 章） | hover すると根の中に、**title が `Options`（label は空）の `MenuButton`** と、`Show Details`（identifier `chevron.forward`）の両方が出る。0b で `Options` が 0 個と読めたのは label で探したため。設計書どおり `Options` を title で取る形にした。`Show Details` は押さない |
| `Options` のメニュー（9.1） | 押すと通知センターの木に、枠のあるメニューがちょうど 1 つ増える（ほかの 18 個はメニューバーのもので枠が 0）。項目は 2 つで、title が `Open` / `Reply`、**identifier はどちらも `menuAction:`**（identifier では選べない）。label は空 |
| 窓の持ち主（9.1、5.0） | **バナーは自分の窓を持たない**: 根は通知センターの全画面の窓（層 23。1 回目の 1.4 で素通しにした窓）の中に描かれる。`Options` のメニューは通知センターの別の窓（層 101、枠はメニューと同じ）。許可の問い合わせも同じ形 |
| hover の後の前面 | hover・メニュー・返信の間、前面のアプリは通知センターになる |
| category の無い通知（9.1、N20） | hover しても根の中に `Options` も `Show Details` も出ない |
| 返信（9.1、N24・NC3） | `Reply` を選ぶと根が広がり（label は同じ、identifier も同じ）、根の中に焦点を持つ `TextView` がちょうど 1 つ出る。`Send` は無い。`typeText` と Return で送れた。placeholder は空で読めない（0b と同じ）。Return の後、根は消え、サンプルは後ろのまま（N24） |
| hover したバナー | ポインターが上にある間は消えない（N20 の「消えるのを待つ」の前に、ポインターをサンプルの結果の行へ移す） |
| すぐ出るバナーの見え方 | 前面のサンプルで ShowImmediate を押すと、約 0.7 秒で根が出て約 5 秒で消えた（探りのテスト）。ところが N11 では、2 秒の余分な完了の確かめの後に根を探すと 4 回とも根が無かった（N12 の同じ並びは通った。原因は分からない）。根を結果の直後に待つ形（`runShowing`）にして通った |
| 要素の一つずつの読み出し | 通知の一覧の枠を `allElementsBoundByIndex` で読むと、数えた後にバナーが消えて XCTest が失敗を記録した。1 回の snapshot で読む形にした |
| システム設定（N3） | `com.apple.systempreferences` が 10 秒以内に前面に来た。止めると 10 秒以内に止まった |
| Dock のバッジ（9.1、N19） | Dock の木のサンプルの項目は `DockItem`（title `MacLibraryExample`、label は空）で、バッジ 1 のときも 0 のときも `value` は空、ほかの属性にも数が無かった。**XCUITest では読めない** |
| 許可の戻し方（U-7） | サンプルの id で `ncreset.sh` の形（`com.apple.ncprefs` の `apps` から消して daemon を立て直す）をこの段で 22 回行い、21 回は `notDetermined` に戻った。戻らなかった 1 回は 2.4 の 3 回目の NP1 |
| 2 回目の RequestPermission（NP2） | 拒否の後は問い合わせが出ず、結果は 1 回目と同じ `❌ [requestPermission] denied. ...`（設計書に書かれていなかった。今の動作として期待値にした） |
| コールドスタートの時間（9.1） | 2.4 の表。T0 から `notRunning` まで最長 4.1 秒（予算 6 秒） |
| `Bundle.main.bundlePath`（9.1、U-21） | VM の DerivedData（`~/ntk/...`、symlink なし）で、ランナーが `realpath` から計算した印とサンプルの印が一致した |
| LaunchServices | VM に前の段の DerivedData（`~/ntk/dd263`）のサンプルとランナーの登録が残っていたので、流す前に外した（U-21 の VM の道。DerivedData は消していない） |

### 2.4 VM の 3 回

流したのは 30 件すべて。手の台本（0d のランナーの代わり。VM の写しにだけ置いた）で、**1 件ずつ別の xcodebuild の呼び出し**にし（設計書 6.3 の 7）、順は「権限の段（許可を戻す → NP2、戻す → NP3、戻す → NP1）→ 通知の UI の立て直し → N4（見張り）→ N1〜N18 → 立て直し → N20〜N24 → 立て直し → NC1〜NC3」。立て直しは `NotificationCenter` と `usernoted` を止め、両方が起き直ってから 5 秒置く。落ちたテストの後にも立て直す。環境は 1 回目と同じ（`TEST_RUNNER_NTK_HOST=vm`、10 区分、時間切れの 3 つの指定、`-parallel-testing-enabled NO`）に、`TEST_RUNNER_NTK_EXPECTED_COPY`（組んだサンプルの `realpath` の SHA-256 の先頭 12 文字）を足した。ソースは `mac/` を `tar` で写し、VM の中で Xcode 26.3・ad-hoc で組んだ（コンパイラーの警告 0）。流す前に、VM の LaunchServices から前の段のサンプルとランナーの登録を外した（2.3）。

| 回 | 結果 | 時間（台本の全体） |
|---|---|---|
| 1 | 30/30 passed | 1024 秒 |
| 2 | 30/30 passed | 1019 秒 |
| 3 | **29/30**（NP1 が `NTK-PRECONDITION:notNotDetermined` で、何も押さずに止まった） | 1019 秒 |

3 回目の NP1: 許可を戻した直後に AuthorizationStatus が `notDetermined` でなかった（U-7 の確かめのとおり、問い合わせを出すボタンを押す前に止まった）。台本の戻し方（`ncreset.sh` を 1 回呼ぶだけ）が、サンプルが止まり切る前に走ったか、設定の書き換えが daemon に届かなかったと見ている（推測。値は記録していない）。台本を「サンプルのプロセスが無くなるのを待つ → 戻す → `com.apple.ncprefs` にサンプルの項目が無いことを確かめ、残っていれば 3 回まで繰り返す」に直し、権限の段だけを 2 回流し直した（2.4 の末尾）。0d のランナーの戻し方にも同じ確かめが要る。

クラスごとの 1 件の時間（3 回の幅）: 権限 11〜34 秒、`NotificationUITests` 8〜102 秒（+1 分の N6 は 53〜64 秒、N14b は 102 秒前後）、イベント 19〜63 秒（N20 が最長）、コールドスタート 35〜37 秒。

コールドスタートの時間（T0 は ShowTimeInterval のクリック。3 回 × 3 件）:

| | `notRunning` まで | 根が見えるまで | 操作まで | 前面まで |
|---|---|---|---|---|
| NC1（本文） | 3.9〜4.0 秒 | 10.6〜10.7 秒 | 12.2 秒 | 13.4〜13.5 秒 |
| NC2（`Open`） | 3.7〜3.8 秒 | 10.6〜10.7 秒 | 14.0 秒 | 15.2 秒 |
| NC3（`Reply`） | 3.8〜4.1 秒 | 10.7 秒 | 14.6 秒 | 15.8〜15.9 秒 |

`notRunning` までは予算 6 秒に収まった（最長 4.1 秒）。操作から前面までは 1.2〜1.3 秒（期限 15 秒）。

3 回の前に直したこと（どれも固定の待ちは足していない。2.6 に差として書いた）:

- 根を 2 秒の確かめの後に探すと見つからない（N11）→ 結果の直後に根を待つ `runShowing`
- 通知の一覧の枠を要素ごとに読むと、消えたバナーで XCTest が失敗を記録した → 1 回の snapshot で読む
- コールドスタートの T0 を押す前に取り、`notRunning` まで 6.6 秒で予算を超えた → T0 をクリックの時刻にした
- N20: hover したバナーが消えない → ポインターをサンプルの結果の行へ移す
- 秒の窓の終わり（29.9 秒台）で読んで押すと窓の外になった（N14b。最初の通しの 1 回）→ 終わりの 1 秒前から次の窓を待つ
- 最初の通しの N4 は、立て直しの 3 秒後に流すと根が出なかった（1 回。同じ並びの流し直し 2 回では出た。原因は分からない）→ 立て直しの後に daemon が起き直るのを待ってから 5 秒置く形にした。3 回とも N4 は通った

**1 回目の 52 件の流し直し**: 1 回目（1.5）と同じ 52 件を 1 回流し、**52/52 passed（429 秒）**。fixture の 7 項目は変わらず、`.DS_Store` は 1.7 の 3 と同じに増えた。押す前の確かめに足した通知の一覧の枠の読み取り（2.6 の 3）で、1 回目より遅くはならなかった（1 回目は 432〜490 秒）。

権限の段の流し直し（台本を直した後）: 2 回とも 3/3 passed（戻し方の確かめはどれも 1 回目で通った）。

### 2.5 変異

壊すのは VM の写しだけで、1 つずつ置き換え（置き換える文がちょうど 1 回現れることを確かめてから）、組み直して流し、戻した。確かめた後は写しごと消した（リポジトリには残していない）。

| 設計書 7 章の行 | 壊したもの | 流したテスト | 結果 |
|---|---|---|---|
| Notification | `willPresent` の表示の options を空にする | N4、N22 | 両方落ちた（`notificationRoot`。根が出ない） |
| Notification | `cancelScheduled` を何もしない形（Repository の `removePending` を空に） | N8 | 落ちた（予約の時刻に根が出た。`notificationRoot`） |
| Notification | `removeDelivered` を何もしない形 | N10 | 落ちた（10 秒たっても `count=1`。`notificationList`） |
| Notification | `didReceive` で action の id の代わりに通知の id を渡す | N21、N22、N23、NC1、NC2 | 5 件とも落ちた（`lastEvent`。`actionId=mac-sample-notification-<数字>` など） |
| Notification | テキスト入力の応答を見分けず、ふつうのアクションとして渡す | N24、NC3 | 両方落ちた（`kind=action`） |
| Notification | `setNotificationCategories` を呼ばない | N20 | 落ちた。ただし落ちた所は 1 回目の「`Options` が出ない」の確かめ: 前の回に登録した category が残り、RemoveCategory が効かなかったため（2 回目の「`Options` が出る」まで届いていない） |
| Notification | サンプルの受け手の設定を通知の画面の `onAppear` に戻す（`App.init` で設定しない） | NC1〜NC3 | 3 件とも落ちた（最後のイベントが `#0` のまま） |
| Notification | 受け手を 2 回呼ぶ | N21〜N24、NC1〜NC3 | 7 件とも落ちた（`the last event passed #1: #2`） |
| Notification | サンプルの `ScheduleTimeInterval` を 30 秒にする | N13 | 落ちた（25 秒までに根が出ない） |
| 片付け | 通知の片付けで `SetBadgeCount(0)` を押す形にする | N4、N1、N17 | N4 は片付けの口が `badge` の印を持たないので押す前に throw（`gate`）。印を受け取らない N1・N17 は片付けが走らず通った |
| コピーの印 | `TEST_RUNNER_NTK_EXPECTED_COPY` を別の値にする | NC1 | 落ちた（段 1 で、予約も止める操作もせずに止まった） |
| 押す相手ごとの条件 | N21 と NC1 の本文のクリックを、前面を求める条件で押す形にする | N21、NC1 | 両方とも押す前に止まった（`notificationState`。N21 はサンプルが後ろ、NC1 は `notRunning`）。クリックは 0 回で、最後のイベントは `#0` のまま。正しい版では 3 回とも押せた（2.4） |
| 同じ持ち主の別の窓（規則） | `NotificationOverlayRule` の「根を含む窓がちょうど 1 つ」を「根を含む窓のどれか」にする | `SupportRuleTests` の 1 件 | 落ちた（設計書の (3) 根を含む窓が 2 つ） |
| （規則。2.6 の 3） | サンプルの窓の押下で、通知の一覧の枠を見ない | `SupportRuleTests` の 1 件 | 落ちた |
| setUp の失敗の立て直し | （意図した変異ではない） | - | 最初の通しで N4 が根を見つけられずに落ちた後、台本が立て直し、続く N1〜N3・N5 は通った |

ここで試していない 7 章の行（理由）:

- 根（信頼の境界）: 信頼する部分のハッシュの照合は 0d のランナーの役目
- 根（動き）、根（焦点と placeholder）、メニューの項目と問い合わせの合成の場合（根の差し替え・別のメニュー・メニューの消失・別のアプリの問い合わせ・候補 2 つ）: おとりの通知（6c）と、それを守りの直前に差し込む仕組みを作っていない。試作のアプリ（`dev.ntkprobe.notif0a`）の通知は label が `NtkProbe0a, ` で始まり、全文の錨には初めから当たらないので、サンプルと同じ錨のおとりには試作を直す必要がある
- setUp の根の待ちを外す: 前の回の根を残す状態を決まって作れなかった（バナーは約 5 秒で消え、片付けが表示中の通知を消す）。0b の「広がったまま一覧に残る」状態の作り方を決めてから行う
- 監視（U-8）の押す枝: 0d の前に無害な試験用のアラートで確かめる（1.8 と同じ）

### 2.6 設計書との差

設計書は直していない。親が反映を決める。

| # | 所 | 設計書 | 実際・したこと |
|---|---|---|---|
| 1 | 5.3 N19、5.8 の件数 | N19 を自動*（だめなら HC3） | Dock のバッジは XCUITest の木から読めない（2.3）。**N19 は書かず HC3 に移す**。Notification は 30 件（宣言の `badge` は 1） |
| 2 | 5.0 の押す前の確かめ（通知のバナーの根） | 押す点の最前面の窓が通知センターで、その窓の枠が根の枠を含むちょうど 1 つの窓 | 15.8.3 ではバナーが自分の窓を持たず、通知センターの全画面の窓（層 23）の中にある。`NotificationOverlayRule` は、通知センターの全画面の窓を素通しせず（ほかの決まった持ち主の全画面の窓は素通し）、「点を含む最前面の窓が通知センターの窓で、根の枠を含む通知センターの窓がその 1 つだけ」で押す。26 で窓の形が違うかは U-30 |
| 3 | 5.0 の押す前の確かめ（サンプルの窓の要素） | `com.apple.notificationcenterui` の窓のうち、サンプルの窓より前のものと重ならない | 2 のとおりバナーは窓ではないので、窓の規則ではバナーがサンプルのボタンの上にあっても見えない。**通知の一覧（identifier `AXNotificationListItems`）の枠に押す点が入るときも `notificationCenter` として待つ**形を足した（label は読まない）。Dialog・Share の押下にも当たる |
| 4 | U-5 のメニューの項目 | identifier か title が期待のものがちょうど 1 つ | identifier はどれも `menuAction:` なので title で選ぶ。開いたメニューがちょうど 1 つで、項目がその枠の中にあることも求める |
| 5 | U-5 の `Options` | 根の中の `Options` | 0b の申し送り（`Show Details` しか無い）は label で探したための読み違いで、`Options` は title で取れる（2.3）。設計書の形のまま |
| 6 | U-5 のキー入力（返信の欄） | 前面のアプリと焦点 | hover の後は通知センターが前面のアプリになる。返信の欄の入力と Return、メニューの Escape は「通知センターが前面、欄が根の中でちょうど 1 つ、焦点あり」で送る。placeholder は木で空なので、空でないときだけ照らす（0b の案のとおり） |
| 7 | U-3 の 2 秒（すぐ出るバナー） | 期待の結果の後に 2 秒 | 2 秒待ってから根を探すと根が無いことがあった（2.3。N11 で 4/4）。ShowImmediate と UpdateById は「結果 → 根 → 2 秒」の順にした（`runShowing`）。イベントのテスト（N21〜N24）は、ShowImmediate の 2 秒を最後に回し、結果の行が「ShowImmediate の結果 → イベントの文」のちょうど 2 つ進んだことと、その後 2 秒増えないことで見る |
| 8 | コールドスタートの段 2 | 予約を押した時刻を T0 | T0 は**クリックの時刻**（スクロールと押す前の確かめの前ではない）。押す前に時刻を取ると、スクロールと確かめの分で `notRunning` まで 6.6 秒になり予算を超えた。段 2 には 2 秒の確かめを入れていない（予算に収めるため。予約の結果は次の GetScheduled の番号で 1 つ進んだことを見る） |
| 9 | U-14c の秒の窓 | 秒が 5〜30 の間で押す | 29.9 秒台で読むと、押すときには 30 秒を過ぎていた（1 回目の通しで N14b が `secondsWindow` で落ちた）。窓の終わりの 1 秒前からは次の窓を待つ（最長 36 秒、期限 40 秒のまま）。自己テストに 28.9・29.0・29.9 を足した |
| 10 | N20 の「根が消えるのを待ち」 | 待つだけ | hover したバナーは消えないので、ポインターをサンプルの結果の行へ移してから待つ（押下ではない。押す前の確かめは通す） |
| 11 | NP2 の 2 回目の RequestPermission | 問い合わせが 5 秒出ない | 結果の文は 1 回目と同じ拒否の文（今の動作として期待値にした） |
| 12 | 6.3 の 6b・6c（VM の道） | 立て直しとおとりの通知 | 0d のランナーの代わりに、VM の中の手の台本で、通知のクラスの前と、落ちたテストの後に `NotificationCenter` と `usernoted` を立て直した（立て直した回は結果に残した）。おとりの通知（6c）は出していない（2.5 の変異でも使っていない） |
| 13 | 5.0 の時間切れ | +1 分のテストは 240 秒 | `executionTimeAllowance = 240` を N6・N9・N14・N14b・N16 の本文で設定した |
| 14 | 3.4 の `NTK-PRECONDITION` | 理由の符号 | 失敗の文は `NTK-STEP:precondition NTK-PRECONDITION:<名前> ...` の形（`notAuthorized`、`notNotDetermined`、`coldStartTiming`） |
| 15 | U-20 の見張り | N4 を最初に流す | 1 回の xcodebuild の中ではクラスの中の順が名前順になる。VM の台本は 1 件ずつ呼ぶので、N4 を通知の UI テストの最初に置けた |
| 16 | U-7 の許可の戻し方（VM） | 戻した後に `notDetermined` を読み、違えば止める | テストの側の確かめは働いた（3 回目の NP1 が押す前に止まった）。戻し方そのものに「サンプルが止まり切るのを待つ」と「`com.apple.ncprefs` から項目が消えたことの確かめと繰り返し」が要った（2.4）。0d のランナーに入れる |
| 17 | 6b の立て直しの後 | 立て直してから次を流す | 立て直しの 3 秒後に流した N4 で根が出なかった（1 回）。daemon が起き直るのを待ってから 5 秒置く形にした（0d のランナーの段の決めごと） |

### 2.7 残したこと

- N19 は書いていない。HC3 の手順書（`mac/MacLibraryExample/ComputerUse/`）も書いていない（手順書は人の確認の段で書く）
- この Mac で保留する N20・N23・N24・NC2・NC3 は 26 で一度も流していない（U-30 の後）。押す相手の持ち主（`com.apple.notificationcenterui`）とバナーが窓を持たない形は 15.8.3 の事実で、26 は U-30 で確かめる
- `classify_reply_state`（U-30）と `--qualification` の段は 0d
- 2.5 の試していない変異（おとりの通知を含む）
- ja のラベル（`オプション`・`許可`・`許可しない`）は推測の値。問い合わせの label の ja の前置きは表に入れていない（en だけ）。U-30 の `vm-ja` で取る
- 許可の戻し方と立て直しの決めごと（2.6 の 12・16・17）は VM の手の台本にだけあり、0d のランナーに移す
- VM の後片付け: 写し・DerivedData・ログ・結果のバンドル・fixture を消し、写しのサンプルとランナーの LaunchServices の登録を外した。VM の空きは 7.9 GiB。前の段の `~/ntk/dd263` のサンプルとランナーは流す前に登録を外したが、終わりにはサンプルの登録が戻っていた（何が登録し直したかは調べていない。0d の VM の道は流す前に外す）。VM のサンプルの通知は許可のまま（NP1 で終えた）、category は登録したまま
- この Mac の DerivedData は scratchpad の `stage0c-n/`（Xcode 26.3 と 26.6 の組み立ての確かめだけ。この Mac では何も起動していない）

### 2.8 組み立て（この Mac）

| Xcode | `build-for-testing` | エラー | コンパイラーの警告 |
|---|---|---|---|
| 26.3（17C529） | 成功 | 0 | 0（`appintentsmetadataprocessor` の分は 1 章と同じ） |
| 26.6（17F113） | 成功 | 0 | 0（同） |

`SupportRuleTests`（23 件）は最終のソースで VM で流し、23/23 passed。

## 3. Clipboard

（後で）
