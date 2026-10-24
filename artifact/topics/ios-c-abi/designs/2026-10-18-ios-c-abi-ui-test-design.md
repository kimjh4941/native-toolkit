# UI テスト設計書（段階 0）

- 作成日: 2026-10-18
- 改訂: 2026-10-18 にレビュー v1（`reviews/2026-10-18-ios-c-abi-ui-test-design-review-v1.md`。Claude と Codex の 2 者。区分 A 9 件、B 11 件、C 10 件）を反映した。主な変更は、許可の区分をテストごとの宣言と区分ごとの印の型で持つ形（U-9）、識別子の一覧のテストの作り直し（I1）、割り込みの監視の方針（U-8）、最後のイベントの保存の仕方（U-4）、category のテストの順（N23・N24）、実機で流す前の確認（6.5）
- 改訂: 2026-10-18 にレビュー v2（`reviews/2026-10-18-ios-c-abi-ui-test-design-review-v2.md`）を反映した。テストのコードの書き方で実機の許可を守ろうとして穴が続いた（v1 A-1、v2 A-N1・A-N2・A-10）ので、守り方を変えた: **一段目（主）は、ランナー（`test_ios.sh`）が宣言の表と `--device-allow` から流すテストを決め、`-only-testing` で渡したものだけを実機で流す**。テストの中の印と確かめは二段目（宣言の誤りを見つける）、ソースの検査は補助（U-9、6.1、6.3、7 章）。ほかに、区分 `credentials` の追加（B-N4）、割り込みの監視の戻り値（U-8）、I1 を画面ごとに分けた（I1a〜I1d）、D14 を分けた（D15）、category のテストの区切り（N23・N24）、押したボタンの記録の形（3.7）、実機の `.xcresult` から添付を書き出さないこと（6.3）
- 改訂: 2026-10-18 にレビュー v3（`reviews/2026-10-18-ios-c-abi-ui-test-design-review-v3.md`）と、0a の結果の 8 章（Xcode 26.3 の振る舞いをシミュレーターで確かめた事実）を反映した。一段目が前提にしていたこと（宣言の表が正しいこと、名指しが効くこと）をランナーの照合で閉じた: クラスごとの宣言の下限、既存の `ClipboardUITests` の固定、実機では列挙しない、名指しの前後の照合、setUp より前の入口を塞ぐ、シミュレーターか実機かを fail-closed で決める、単体テストはシミュレーターだけ（U-9、6.1、6.3、7 章）。雛形の 2 クラス（3 件）を 0c で消す（全体は 99 件）。印の型は `internal` で初期化子だけ `fileprivate`、印は基底の `token(_:)` で得る。8 章で分かった事実で未確認を置き換えた
- 改訂: 2026-10-18 にレビュー v4（`reviews/2026-10-18-ios-c-abi-ui-test-design-review-v4.md`）を反映した。私物の端末を守る仕組みへの区分 A が v1〜v4 で 4 回続いたので、守りの考え方を変えた（レビュー v4 の「仕組みの直し（2）」）: 守りの本体を 3 本柱（一段目のランナーの選び方、宣言の正しさの照合、毎回の利用者の許可）にし、ソースの検査を許す形だけを決める閉じた規則にし、実機のビルドのテストの一覧をバイナリから読んで照らす。テストの中の確かめ（二段目）だけの穴は以後区分 B とする（U-9、6.1、6.3、7 章）。あわせて、監視が押してよいアラートをサンプルのものに限り（U-8）、実機で `clipboard` を許すときは Handoff を切ることを前提にし、クリップボードの `changeCount` を確かめる（U-10、3.5、6.5）。意図した skip を一覧にした（6.3）
- 改訂: 2026-10-18 にレビュー v5（`reviews/2026-10-18-ios-c-abi-ui-test-design-review-v5.md`）を反映した。私物の端末を守る仕組みへの区分 A が 5 回続いたので、守りの前提（何から守るか）を 2 章の冒頭に書き、基底と `Support/` の決まったファイルを「信頼する部分」としてハッシュで固定した（A-23）。ほかに、権限と貼り付けのテストにも「何も押さない」監視を付けた（A-1v5）、実機のバイナリのテストの selector の読み方を直した（A-22）、許可の一覧を使い回せない形にした（A-24）、`XCTExpectFailure` を禁じた（B-23）、識別子の文字列の例外を `ClipboardID` の範囲にした（C-13）、`Support/` の補助を struct / enum にした（C-14）。8.1・8.2 を見直した。**レビューは v5 で打ち切った（サーキットブレーカー）。v5 の区分 A は直したが、直した後のレビューはしていない**
- 状態: **決定（2026-10-18、利用者）**。U-1〜U-19（2 章）は案のとおり決めた。レビューは v5 で打ち切り、v5 の区分 A を直した後のレビューはせずに決めた（利用者の判断）。8.1・8.2 の「確かめていないこと」は段階 0c の最初に実測で確かめ、違えばこの文書を直す
- 対象: `artifact/topics/ios-c-abi/README.md` の段階 0b〜0d
- 入力:
  - `artifact/topics/ios-c-abi/README.md`（5 章の 0a〜0d、7 章、7.1、7.2、D-21、D-22）
  - `artifact/topics/ios-c-abi/results/2026-10-18-ios-c-abi-stage0a-spike-result.md`（段階 0a。以下「0a」。章番号はこのファイルの章）
  - `artifact/topics/ios-c-abi/results/probes/stage0a/Stage0aProbeTests.swift`（0a で通った操作の書き方。以下「プローブ」）
  - `artifact/ios/share/designs/2026-07-04-ios-share-sample-app-design-v1.md` の 5 章（手動確認観点 15 項目）
  - `artifact/ios/clipboard/designs/2026-08-09-ios-clipboard-sample-app-design-v6.md` の 8 章・9 章（手動確認観点と、自動化しない観点）
  - サンプルのコード（`ios/IosLibraryExample/IosLibraryExample/*.swift`）と今の UI テスト（`IosLibraryExampleUITests/*.swift`）。Dialog と Notification はサンプルアプリの設計書が無いので、確かめる観点はコードから起こした
- 手本: `artifact/topics/android-c-abi/designs/2026-10-03-android-c-abi-ui-test-design.md` と、そのレビュー `reviews/2026-10-03-android-c-abi-ui-test-design-review-v1.md`
- 決定事項: 2 章（U-1〜U-19）

用語:

- **結果の行**: 各画面の上にある結果の `Text`。Dialog・Notification・Share は `updateResult` が `"✅ \nResult: <本文>"` か `"❌ \nResult: <本文>"` を入れる（`DialogSampleView.swift:181-189`、`NotificationSampleView.swift:450-459`、`ShareSampleView.swift:291-300`）。この文書の表では `Result: ` より後ろの本文と、先頭の ✅ / ❌ だけを書く
- **最後のイベント**: 段階 0b で通知の画面に足す表示（0a の R-1。README の 0b の行に既にある。U-4）
- **許可の区分**: 実機（利用者の私物）で流すテストが要る許可の種類（U-9）。`systemui`・`sharesheet`・`clipboard`・`files`・`reinstall`・`credentials`
- **宣言の表**: テストごとの要る区分の表。テストのターゲットの中の 1 ファイル（`Support/DeviceRequirements.json`）で、ランナーとテストの両方が読む（U-9）
- **区分で除く**: 実機で、許されていない区分を宣言したテストを、ランナーが**起動しない**こと（一段目）。基準との比べ方で、失われた件数に数えない（6.3）。テストの中の `XCTSkip("NTK-GATED:...")`（二段目）は、ランナーと表が食い違ったときにしか起きないので、起きたら失敗として扱う
- 既存の Clipboard のテスト U1〜U21（`testU1_`〜`testU21_`。U10 は U10a と U10b の 2 件で、計 22 件）と、この文書の決定 U-1〜U-19 は別のもの。混同を避けるため、決定には必ずハイフンを付ける。Clipboard に足すテストは CB1〜 とする

## 1. 目的と範囲

段階 0e〜0g と 1b の前後で、**ネイティブの利用者（Swift の API を使うアプリ）から見た動作が変わっていないこと**を判定できるよう、サンプルの Dialog / Notification / Share に UI テストをそろえる（README 5 章の 0c、7.1）。Clipboard は今 22 件あるので番号とテストの中身を変えずに残し、0a で自動化できると分かった貼り付けの許可と `UIPasteControl` の 4 件だけを足す。

守るもの（README 7.1、5 章）:

| 段階 | 変わりうるもの | 守るテスト |
|---|---|---|
| 0e | Notification の操作の結果が main で返る。handler に `@Sendable`。strict concurrency complete の直し | Notification の全件（結果の行と、取り消し・削除の反映）、Dialog・Share の結果の行 |
| 0f | Swift 6 の言語モード。`shared` の `@MainActor` | 全件 |
| 0g | framework の bundle id | 全件（通知の delegate と category は bundle id に依存しないことを確かめる） |
| 1b | Dialog の結果の型、通知の delegate の転送と受け手の口、エラーの case、`registerCategory` の完了、ログ | Dialog の全件、通知のイベント（N25〜N33）、コールドスタート（N30〜N33） |

| 範囲 | 内容 |
|---|---|
| 対象 | Dialog・Notification・Share の UI テストの新規作成。Clipboard の 4 件の追加。メニューの移動と識別子の一覧のテスト。テストの基盤（`Support/`）。人の確認の手順書。サンプルへの `accessibilityIdentifier`、結果の行の回数、最後のイベントの追加（段階 0b）。`scripts/test_ios.sh` と基準（段階 0d） |
| 対象外 | 実在のアプリへの共有（U-13）。iPad（試験の環境に無い。Share の手動確認 #14）。位置の予約の発火（位置の権限と移動が要る。N8・N18 は登録まで）。件名が Mail で使われること（シミュレーターに Mail が無く、実機では実在のアプリになる。S11）。通知センターからの操作（環境で効き方が逆になる。0a 7.3。人の確認 HC4）。`IosLibrary` の C ABI と Unity（このテストはサンプルを通すだけ。README 7.1） |

**今の動作を基準にする。** 気になる動作（8.5）を見つけても段階 0 では直さず、今の動作を期待値にする。直すのは 1b 以降で、そのとき期待値を変えた理由を記録する（Android の 2 章と同じ）。

## 2. 決定事項

**守りの前提（何から守るか）**: U-8〜U-10 と 6 章の実機の守りは、次の前提で組む（レビュー v5 の「基準を疑う」。v1〜v5 で、テストのコードを書く人が守りを破る書き方まで静的な検査で防ごうとして、範囲を広げるたびに外側に抜け道が見つかったため）。

| 項目 | 前提 |
|---|---|
| 守る相手 | エージェントと開発者の**うっかりした誤り**（宣言の付け忘れ、区分の書き誤り、補助を使わない直書き、継承や `#if` での思わぬ動き、許可の使い回し）。**わざと守りを破るコードは対象外**とする |
| 信頼する部分 | 基底のファイル（`Support/SampleUITestCase.swift`）と `Support/` の決まったファイル（`SampleApp.swift`、`Springboard.swift`、`ShareSheet.swift`、`RunnerPasteboard.swift`、`UnexpectedAlertGuard.swift`、`NotificationCleanup.swift`、`SystemLabels.swift`。印の発行、アプリの操作、springboard と Share のシートの操作、監視）は「信頼する部分」とし、**中身をハッシュでランナーに固定する**。変わったら、ランナーは実機で流さず、許可を求める一覧（`--dry-run`）に「信頼する部分が変わった」と示す。信頼する部分を変えるときは、別のモデルのレビューを通してからハッシュを更新する（6.3 の 2。レビュー v5 A-23） |
| 最終の守り | 実機で流すたびに、流すテストの名前と区分の一覧を利用者に見せて許可を得る。許可は 1 回かぎりで、使い回せない（U-9 の柱 3。レビュー v5 A-24） |

この前提の下で、閉じた形のソースの規則（6.1）は信頼する部分の外のファイル（テストのクラス）を対象にし、信頼する部分の中身はハッシュの固定とレビューで守る。


| ID | 決めること | 案 | 理由・根拠 |
|---|---|---|---|
| U-1 | 期待値の書き方 | **コードの文字列そのもの**を書き、結果の行は**全文を完全一致**で比べる。全文が環境で変わるもの（エラーの文言が OS の言語に依存するもの）だけ、前の部分を区切りまで（`[marker] ` や `, ` まで）比べる | `common.md` の「部分一致には錨を打つ」。`[showImmediate]` と `[showImmediateWithAttachment]` のように包含関係のある名前がある |
| U-2 | 要素の選び方（表示の言語に依存しない） | **アプリの要素は `accessibilityIdentifier` だけで探す**（5 章。文言では探さない）。**システムの UI は identifier（`NotificationShortLookView`、`PopoverDismissRegion`、`UIActivityContentView` など）で探し、identifier が無いものは en と ja の両方のラベルを 1 か所（`Support/SystemLabels.swift`）の表に持って探す**。アプリが渡す文字列（Dialog の題とボタン、通知の題と本文、category のアクションの `Open` / `Delete` / `Reply` / `Send`）は言語に左右されないので、そのまま使う。**どの要素も `.element`（ちょうど 1 つ）で取り、0 件か 2 件以上なら押さずに失敗する**（私物の通知やショートカットと重なったときに触らないため）。実機（ja-JP）の言語は変えない。基準のシミュレーター（iOS 26.2）は en のまま | 0a R-2、7.3。18.3 のシミュレーターと実機は ja、26.2 は en で、システムの UI のラベルが変わる（0a 1 章、7.1）。レビュー v1 B-5 |
| U-3 | 結果の行の読み方 | 0b で、結果の行に identifier（`<画面>.result`）と、**更新の回数を `accessibilityValue` で付ける**（見た目は変わらない）。回数は画面の `@State` に置き、**`resultText` を変えるのと同じ `DispatchQueue.main.async` の中で増やす**（文言と回数がずれない）。値の形は、Dialog が種類ごとの `completion=<n>,callback=<n>`（画面全体の累計の 2 つ。Dialog ごとの回数ではない。D14 は操作の前からの増分で判定する。0b で実装）（`updateResult` に種類を渡す。`completion` は表示の完了、`callback` はボタンのコールバック）、Notification と Share が `updates=<n>`。テストは押す前の値を読み、増えるのを待ってから全文を比べる | Dialog・Notification・Share の結果の行には Clipboard のような通し番号が無い（`DialogSampleView.swift:184`）。同じボタンを 2 回押すと同じ文言になり、新しい結果か古い結果かを区別できない（`GetDelivered` を繰り返して反映を待つときに要る）。Dialog は「completion とコールバックがそれぞれちょうど 1 回」を確かめる（D14。合計だけだと、コールバック 2 回・completion 0 回でも通る。レビュー v1 B-3、C-10）。代わりの案: 間に別のボタン（`HasPermission`）を挟んで文言を変える。サンプルを変えずに済むが、操作が倍になり、Dialog の回数は確かめられない |
| U-4 | 通知を受けたことの確かめ方 | 0b で、通知の画面に**最後のイベント**（通し番号、種類、通知の id、アクションの id、返信の文字）を出す（5.2。README の 0b の行と 0a R-1 のとおり）。受け手はアプリの起動の処理（`IosLibraryExampleApp.init`）で登録する今の場所のまま、**2 つの受け手を設定してから、最後に `IosNotificationManager.setup()` を呼ぶ**順に入れ替える（今は `setup()` で delegate を入れた後に受け手を設定している。`IosLibraryExampleApp.swift:14-25`。その間に来た応答が入れ物に届かない余地を無くす。レビュー v2 A-12）。**受け手の中で、ロックで守ったアプリ全体の入れ物に同期で書く**（`completionHandler` が呼ばれる前に書き終える。`IosNotificationManager.swift:343-351` は受け手の後に同期で `completionHandler()` を呼ぶ）。画面への知らせだけを main に送り、画面は表示するたびに入れ物の今の値（snapshot）を読む。永続化はしない | 0a R-1。今は `print` だけで読めない（`IosLibraryExampleApp.swift:16-25`）。コールドスタートでは画面ができる前にイベントが来るので、画面の `@State` では受けられない。main に積むだけだと、背景の Delete や返信で `completionHandler` の後にアプリが止められ、積んだ処理が走る前に失われうる（レビュー v1 A-4）。`didReceive` のスレッドは文書に無く（README 1.3）、0e で変わるので、どのスレッドから来ても同じに動く形にする |
| U-5 | 通知の操作の経路 | **バナーだけを使う**（タップ、1.5 秒の長押しで出るアクション、返信）。通知センターを開く経路は自動のテストに使わず、人の確認（HC4）にする。**実機では、バナーを下へドラッグして広げる操作を使わない**（長押しだけ。バナーが先に消えるとホームでの下へのドラッグになり、Spotlight の私物の候補を開きうる） | 0a 7.3（R-3 を改めた）。通知センターのタップ・長押し・右スワイプは実機とシミュレーターで効き方が逆で、18.3 のシミュレーターでは長押しで広がらない。バナーはどの環境でも 3/3（0a 3.3、3.4、7.2）。実機で通知センターを開くと私物の通知が画面に出る。レビュー v1 B-11 |
| U-6 | 予約・表示の状態の確かめ方 | サンプルの `GetScheduled` / `GetDelivered` の結果の行（`count: <n>, ids: [<id>, ...]`）で読む。取り消し・削除はライブラリの中で非同期（`Task`）に行われ、結果の行は呼んだ直後に出る（`NotificationSampleView.swift:180-210`、`IosNotificationManager.swift:180-200`）ので、**反映は 0.5 秒おきに読み直して 10 秒まで待つ**。比べるのは 3 つ: `count:` の値、`ids` の要素の数（`count:` と一致すること）、`ids` に重複が無いこと。そのうえで id を集合で比べる（並びは比べない） | springboard の要素を数える方法は、私物の通知が混ざり、OS の版で構造が変わる。集合だけで比べると、重複や数の食い違いを見逃す（レビュー v1 B-9） |
| U-7 | 権限のダイアログのテスト | **シミュレーターでは毎回アプリを削除してから 1 件ずつ流す**（NP1・NP2）。順は NP2（拒否）→ 削除 → NP1（許可）で、終わると許可の状態が残り、続くテストの前提になる。**実機ではふだんの実行に入れず、基準を取るときだけ、利用者の許可（`reinstall`、`systemui`）を得て、削除して流す**。通常のテストの前提が満たされないとき（実機で権限が `notDetermined`）は、許可を押さずに区分で除く（3.0） | 0a 3.2、R-4。初めの状態に戻す方法はアプリの削除しか無い（`simctl privacy` に通知は無い）。実機は私物で、削除にはその都度の許可が要る（README D-21）。レビュー v1 A-3 |
| U-8 | 割り込みの監視（XCTest の Default interruption handler） | 監視は、UI が現れたときでなく、**次の操作を妨げたときに**呼ばれる（`false` を返すと既定のハンドラに渡り、既定のハンドラは Allow などを押しうる）。そのため次の 3 つを組み合わせる。(1) **明示の確かめ**: 権限のダイアログを確かめるテスト（NP1・NP2）と貼り付けの許可を確かめるテスト（CB1・CB2）は、アプリを操作する前に springboard のダイアログを `waitForExistence` で待って、明示的に押す。システムの UI を起こしうる操作（Login、Share の Copy と Save、貼り付け、通知の権限の要求）の後には、`Support/` の口でアラートが残っていないこと（`springboard.alerts` と `app.alerts` の数。ラベルは読まない）を確かめる。(2) **監視**: すべてのテストに付ける。**NP1・NP2・CB1・CB2 には「何も押さない」監視を付ける**（どの割り込みでも、押さずに `app.terminate()` し、印を「未知の割り込み」にして `true` を返す。期待するダイアログは springboard で明示して待って押すので、監視には来ない見込み。springboard の要素の操作が監視を起こさないことは 8.1。監視を外すと、関係の無い私物のアラートが次の操作を妨げたときに既定のハンドラがそのボタンを押しうる。レビュー v5 A-1v5）。ほかのテストには次の規則の監視を付ける。**監視の中では `XCTFail` を呼ばず、安全な操作と印（割り込みが起きたことを示すテストの中の値）の設定と `true` の返却だけを行う**（レビュー v3 B-17）。(a) **押してよいのは次の両方を満たすときだけ**: アラート（`elementType == .alert`）で、そのラベルにサンプルの表示名 `IosLibraryExample` が入り（ラベルは読むだけでログに書かない）、かつそのテストが `systemui` を宣言している（ペーストの拒否は `clipboard` を宣言している）こと。このとき `SystemLabels` の**既知の否定のボタン**（`許可しない` / `Don’t Allow`、`ペーストを許可しない` / `Don’t Allow Paste`、`今はしない` / `Not Now`、`キャンセル` / `Cancel`）がちょうど 1 つあれば、それだけを押し、印を「既知のアラートを否定した」にして `true` を返す。(b) それ以外（サンプルの名前が入らない私物のシステムのアラート（キャリア設定のアップデート、Apple ID の確かめなど）、宣言の無いテスト、否定のボタンが 0 か 2 以上、アラートでない割り込み）は、**押さずに** `app.terminate()` し、印を「未知の割り込み」にして `true` を返す（テストと関係の無いアラートに答えない。レビュー v4 A-2v4）。シミュレーターでも同じ規則にする。`Support/` の XCUI の操作を包む関数は、操作の直後に印を読み、立っていれば通常の `Error` を throw する（テストはそこで失敗して止まる）。(3) **ログ**: 実機では失敗の文にラベルを書かない。シミュレーターでは書く。通知のバナーが監視に来るか、監視の中の `terminate` と `true` の返却が安全に動くか、システムの権限のダイアログのラベルにアプリの表示名が入るかは、0c の最初に確かめる（8.1）。バナーが来るなら、バナーを扱うテスト（`systemui` を宣言したもの）の監視は、識別子 `NotificationShortLookView` の割り込みに `false` を返す形にする（ラベルは読まない） | 0a 3.2 の注意。ハンドラが処理しないと XCTest が Allow を自動で押し、権限が黙って許可される。拒否の経路が許可で通ってしまう。貼り付けのダイアログにアプリの名前が出ることは 0a 3.7（「would like to paste from …」）と 7.2（出どころの名前がサンプルの名前）にある。権限のダイアログのラベルにアプリの表示名が入るかは 0a に記録が無い（8.1）。レビュー v1 A-5・A-9、v2 A-11・B-N3・C-N5、v3 B-17、v4 A-2v4、v5 A-1v5 |
| U-9 | 実機（私物）での許可の区分と守り方 | 区分は 6 つ: `systemui`（springboard の通知・ダイアログ、ホームへの移動、設定の App を読む・操作する。**通知を出すボタン（Show* / Schedule* / UpdateById）、`RequestPermission`、`OpenNotificationSettings` を押すこと**も含む）、`sharesheet`（Share のシートを開く。連絡先と実在のアプリが画面に出る）、`clipboard`（一般のクリップボードを書き換える・消す・読む）、`files`（Files に保存する）、`reinstall`（サンプルを削除して入れ直す）、`credentials`（ログインのダイアログ。パスワードの保存や AutoFill が私物の資格情報に触れうる）。**既定はどれも許さない**。**宣言の表**: テストごとの区分を 1 か所、テストのターゲットの中の `Support/DeviceRequirements.json` に置く（6.1）。シミュレーターでも宣言は要る（利用者の許可が要らないだけ）。**守りの本体は次の 3 本柱**（レビュー v4 の「仕組みの直し（2）」）。**柱 1: 一段目（ランナーが選ぶ）**: 実機では、表と `--device-allow` から「宣言した区分がすべて許されているテスト」を選び、シミュレーターの列挙の identifier をそのまま `-only-testing:` に 1 件ずつ名指しして渡す。名指しが 0 件なら xcodebuild を呼ばずに止まる。流した後、結果のテストの配列が名指しとちょうど同じ（件数・重複・集合）でなければ、実機の実行全体を止める（存在しない名指しは黙って無視され exit 0 になる。0a 8 章）。シミュレーターか実機かは `xcrun simctl list -j devices` にある UDID だけをシミュレーターとする fail-closed で決める。単体テストはシミュレーターだけで流す（6.3）。**柱 2: 宣言の正しさの照合**（選ぶ前に、表が実際のテストを正しく表していることを照らす。6.3 の 2・4、6.1）: ①シミュレーターの列挙と宣言の表の完全一致（実機では列挙しない）、②クラスごとの宣言の下限（`ClipboardUITests`・`ClipboardPasteUITests` は `clipboard`、`ClipboardPasteDenyUITests` は `clipboard` と `systemui`（0c で削除が要ると分かれば `reinstall` も）、`ShareUITests` は `sharesheet`、`NotificationEventUITests`・`NotificationColdStartUITests` は `systemui`、`NotificationPermissionUITests` は `reinstall` と `systemui`）、③既存の `ClipboardUITests` の固定（メソッドの名前の一覧 22 件とファイルのハッシュ。固定した 22 の名前が別のクラスの下に出ても止まる）、④**閉じた形のソースの規則**（許す形だけを決め、ほかを禁じる。基底のファイルの外のクラスは `final class <名前>: SampleUITestCase` だけ、`override` は `setUpAfterGate()` と `tearDownAfterGate()` だけ、`class func`・`static func` の上書き・`#if` を禁じ、`import` は `XCTest` と `Foundation` だけ、危ない型の名前は `Support/` の決まったファイルだけ。6.1）、⑤**実機のビルドのテストの一覧をバイナリから読み**、端末で起動せずに、シミュレーターの列挙と一致することを照らす（`#if` などで実機にだけあるテスト・無いテストを捕まえる。6.3 の 4）、⑥**信頼する部分（2 章の冒頭）の中身のハッシュ**が固定した値と同じであること（変わっていれば実機で流さない）。**柱 3: 利用者の許可（最終の守り）**: 実機で流す前に毎回、ランナーが流すテストの名前と区分の一覧を出し（`--dry-run`。実機に触れない）、エージェントがそれを利用者に見せて許可を得る。一覧には `--dry-run` ごとにランダムな**許可の ID** を入れる。ランナーは、許可を得た一覧のファイル（`--approved <file>`）を受け取り、今の選び方の結果とちょうど同じでなければ流さない。実機に触れる前に、その ID を**消費済みの台帳**（リポジトリの外の決まった場所）に記録し、台帳にある ID は拒む（同じ許可の使い回しと、失敗の後の流し直しにも新しい許可を求める。レビュー v5 A-24）。流した後、結果が許可した一覧とちょうど同じかを照らす（README D-21、利用者の指示と同じ。6.3、6.4）。**二段目（補助）: テストの中の確かめ**: 宣言の誤り（宣言より多くを触るテスト）をシミュレーターの実行で見つけるためのもの。全テストのクラスは基底クラス `SampleUITestCase` を継承し（`Support/` の補助は struct / enum。6.1）、基底は setUp / tearDown の入口（同期・`async`・completion の形）を `final override` にして決まった口へ渡す。`invokeTest` は上書きしない（子が上書きできないことは④で決まる。レビュー v4 A-19）。基底の確かめは、`continueAfterFailure = false` → `self.name`（`-[<クラス> <メソッド>]`。0a 8 章）の正規化 → 表を引く → 実機で許されていなければ `XCTSkip("NTK-GATED:<区分>")` → `gatePassed = true`。**印**: 区分ごとの型（`SystemUIToken` など 6 つ）は `internal`、初期化子だけ `fileprivate`。印を得る口は基底の `internal` な区分ごとの 6 つの関数（`systemUIToken()`、`shareSheetToken()`、`clipboardToken()`、`filesToken()`、`reinstallToken()`、`credentialsToken()`。どれも `throws`。レビュー v4 B-19）で、呼ばれるたびに `self.name`・表・`NTK_DEVICE_ALLOW` を引き直し、宣言していない・実機で許されていない・`gatePassed == false` のどれでも throw する。新しいテストのクラスは `XCUIApplication` を持たず、`SampleApp` と `Springboard` などの印を取る口だけで操作する。**二段目だけの穴は、守りの本体（3 本柱）の穴ではないので、以後は区分 B として扱う**。スクリプトは `--device-allow <区分,...>` を受け、実機のときだけ `TEST_RUNNER_NTK_DEVICE_ALLOW=<区分,...> xcodebuild ...` の形で環境変数として渡す（xcodebuild の man page の `TEST_RUNNER_<VAR>`）。シミュレーターでは渡さず、外から受け継いだ `TEST_RUNNER_NTK_DEVICE_ALLOW` と `NTK_DEVICE_ALLOW` は消してから呼ぶ | README D-21（実機は私物。危ない操作は 1 回ごとに許可）、0a 6〜8 章。私物の端末を守る仕組みへの区分 A が v1〜v4 で 4 回続き、どれも見つかった抜け道を塞ぐ直しだった（`super` を呼ばない setUp、識別子の直書き、`XCTFail` の後の継続、基底クラスの列挙、別の teardown、`invokeTest`、`#if`、継承）。review-document の「同じ種類の指摘が続いたら、それを生む仕組みを直す」に従い、許す形だけを決める閉じた規則と、実機のバイナリの照合と、毎回の利用者の許可を柱にした（レビュー v4 の「仕組みの直し（2）」、A-18〜A-21、A-1v4） |
| U-10 | クリップボードを書き換えるテスト | `clipboard` を宣言する。シミュレーターでも宣言は要るが、利用者の許可（`--device-allow`）は要らない。**実機では `clipboard` を許したときだけ、ランナーが起動する**（U-9 の一段目）。対象は、既存の `ClipboardUITests` の 22 件（今の範囲は一般のクリップボードが既定で、`Clear` もそれを消す。`ClipboardSampleView.swift:145`、`IosLibraryExampleUITests.swift` の `resetActiveScope`）、Share の Copy（S1・S4・S6・S10）、CB1〜CB4、I1d。U10a はホームへ移る（`IosLibraryExampleUITests.swift:297`）ので `systemui` も宣言する。既存の `ClipboardUITests` は、自分の `setUpWithError` で `super` を呼ばずに `app.launch()` している（`IosLibraryExampleUITests.swift:80-84`）ので、**`final class ClipboardUITests: SampleUITestCase` に替え（6.1 の閉じた形の規則）、`setUpWithError` を `setUpAfterGate()`、`tearDownWithError` を `tearDownAfterGate()` に書き換える**（基底のものは `final` なので、書き換えないとビルドが通らない）。テストの番号と本体は変えない。本体が `app`（`XCUIApplication`）を直接使う形はそのまま残るので、二段目の印の口はこのクラスには及ばない。守りは一段目で、クラスの下限（`clipboard`）と、メソッドの名前の一覧とファイルのハッシュの固定（U-9 の②③）によって、宣言を少なく書いたテストや新しいテストをこのクラスに足すと、ランナーが止まる。**新しい Clipboard のテストは新しいクラス（`ClipboardPasteUITests` など）に書く**（レビュー v3 A-1）。利用者の元のクリップボードは読まず、戻さない（読むこと自体が私物の中身に触れるため）。**実機の一般のクリップボードへの書き込みは、Universal Clipboard で同じ Apple ID のほかの端末（利用者の Mac など）にも届きうる**。流す間に利用者がほかの端末でコピーすると、端末の側が書き換わり、外から来た内容を読むので貼り付けの許可のダイアログが出る（U-8 の監視が否定を押して失敗にする）。そのため、**実機で `clipboard` を許すときは、流す間 Handoff を切ることを前提にする**（尋ねるのではなく、切ってもらえなければ `clipboard` を許さない。6.5）。さらに、ランナーが一般のクリップボードに書くテスト（CB1・CB3・CB4）は、書いた直後と、サンプルで読む操作（Load Text、貼り付けのコントロール）の直前とで `UIPasteboard.general.changeCount` が変わっていないことを確かめ、変わっていたら押さずに失敗にする（ほかの端末の内容を読まないため。CB1 は監視を外して `Allow Paste` を押し、CB3・CB4 はダイアログを出さずに読むので、間にほかの端末でコピーされると利用者の内容を読みうる。レビュー v4 A-3v4） | 0a 6 章（クリップボードが上書きされる）、7.4（実機にテストの文字列が残った）。レビュー v1 A-9、v2 A-N1・C-11、v3 A-1、v4 A-3v4 |
| U-11 | Save to Files | 保存先は**必ず「このiPhone内」（On My iPhone）**。ピッカーが別の場所（実機では iCloud Drive など）で開いたら「ブラウズ」→「このiPhone内」へ移る。選べなければ保存せずにキャンセルして失敗にする。置き換えの確認が出たら**「両方とも残す」（Keep Both）**を押す。実機は `files` の許可が要る。実機で流した後は、Files に残った写しの数を利用者に伝える | 0a 3.6（18.3 では「置き換え」が失敗する。R-6）、7.2（実機は最初の場所が違う）、7.3 |
| U-12 | 貼り付けの拒否のテスト | CB2 は**専用のクラス（1 件だけ）にし、スクリプトが xcodebuild を別に起動して単独で流す**。ただし、アプリを止めて起動し直しても、別の xcodebuild で流しても、OS の貼り付けの許可の状態が初めに戻るとは限らない。**0c の最初に、シミュレーターと実機でダイアログが出る条件を確かめる**（8.1）。アプリの削除が要るなら、CB2 は `reinstall` も宣言し、スクリプトがアプリを削除してから単独で流す。それでも安定しなければ人の確認に移す | 0a 7.2、7.3。許可 → 別のテスト → 拒否と続けて流すと、ダイアログが出なかった（原因は未確認）。レビュー v1 A-6 |
| U-13 | 実在のアプリへ送らない | Share のシートで押してよいのは、Copy、Save to Files、閉じる（Close / `PopoverDismissRegion` / ヘッダーを下へドラッグ）だけ。ほかのセルには触れない。Copy や Save to Files のラベルが私物のショートカットと重なって 2 件以上当たったら、押さずに失敗する（U-2）。**実機ではシートのセルのラベルをログに書かず、階層のダンプも出さない**（プローブの `safeCellLabels`・`dump` と同じ） | 0a 6 章（実在のアプリへの共有は行わない）、README D-21。レビュー v1 B-5 |
| U-14 | 待ち時間 | 0a の実測から決める（6.2 の表）。**固定の待ち時間は使わない**。例外は「出ない」「来ない」ことを確かめるときだけ: 取り消した予約が出ないこと（予約の時刻 + 5 秒）、権限のダイアログが 2 回目に出ないこと（NP2。5 秒）、許可済みで要求したときにダイアログが出ないこと（N2。5 秒）、貼り付けのコントロールでダイアログが出ないこと（CB3。2 秒）、権限が無いときに ShowImmediate のバナーが出ないこと（NP2。5 秒）、Delete の後にアプリが前面に来ないこと（N28。2 秒）、除外した Copy が無いこと・エラーのときにシートが出ないこと（2 秒。0a のプローブと同じ）、イベントやコールバックが余分に来ないこと（N25、D14、D15。2 秒）、category が無いときにアクションが無いこと（N23・N24。広げた印が出てから 3 秒） | 0a 3.3〜3.6、3.5、7.2。レビュー v1 C-5、v2 C-N7 |
| U-15 | テストの独立と順 | **テストごとにアプリを `launch` し直す**（最後のイベントと結果の回数はプロセスごとに 0 から）。`setUpWithError` で端末を縦向きにする（`XCUIDevice.shared.orientation = .portrait`。私物の端末の向きで座標とスクロールが崩れないように。`Support/` の中で行う）。通知のテストの片付けは 2 つに分ける: **アプリの中の片付け**（`RemoveAllDelivered` と `CancelAllScheduled` を押し、`GetDelivered` / `GetScheduled` が `count: 0` になるまで待つ。U-6。区分は要らない）と、**springboard の片付け**（広げたバナーが残っていればホームに戻す。**`gatePassed` が true で、そのテストの中で `SystemUIToken` を実際に受け取ったときだけ**行う。`setUpWithError` で `XCTSkip` を throw しても `tearDownWithError` は走る（0a 8 章）ので、基底の `tearDownWithError` は `gatePassed` が false なら何もしない。レビュー v2 B-N8、v3 B-18）。category が要るテストは自分で `RegisterCategory` を押す。category を外すテスト（N23・N24）は最後に登録し直す（実機は 0a の後、登録された状態で残っている。0a 7.4）。バッジを変えるテストは最後に 0 に戻す。UI テストは直列で流す（scheme の UI テストは並列にしていない。`-parallel-testing-enabled NO` も渡す） | Android の 4 章 `Cleanup` と同じ考え。シミュレーターの一般のクリップボードはプロセスをまたいで共有される（Clipboard v6 9.4）。レビュー v1 A-1、B-10 |
| U-16 | 試験の環境 | **実機 iPhone XS（iOS 18.7.2、ja-JP）と、シミュレーター iPhone 17（iOS 26.2、en）の 2 つで同じテストを流し、それぞれ基準を取る**。iPhone 16（iOS 18.3.1、ja）のシミュレーターは、実機がつながらない間の代わりで、基準にしない。環境で振る舞いが違う所（action sheet と Share のシートの閉じ方、Files の最初の場所）だけ、テストの中で OS の版で分ける。分け方は 0a で確かめた事実に限る | README D-21、7.2。0a 3.1、3.6、7.2 |
| U-17 | `accessibilityIdentifier` の名前 | 形は Clipboard（`ClipboardSampleIdentifiers`）に合わせる: メニューのカードは `menu.<画面>`、結果の行は `<画面>.result`、ボタンは `<画面>.button.<名前>`、節の見出しは `<画面>.section.<名前>`、最後のイベントは `notification.lastEvent.<項目>`。**ボタンの `<名前>` の決め方は Clipboard と違う**: Clipboard は結果の行の印（marker。`loadText` など）をそのまま使う（`ClipboardSampleView.swift:5-8,991-993`）。Dialog・Notification・Share の結果の行の印はボタンと 1 対 1 でない（`UpdateById` の印は `[update]`、`SetBadgeCount(1)` と `(0)` は同じ `[setBadgeCount]`。`NotificationSampleView.swift:174,317,328`）ので、**ボタンの文言の lowerCamelCase（括弧の中は除く）**にする。括弧を除くと同じ名前になる `SetBadgeCount(1)` / `SetBadgeCount(0)` だけ数字を残す（`setBadgeCount1` / `setBadgeCount0`）。識別子は **`Button` そのものに付ける**（`Button(...) { ... }.accessibilityIdentifier(...)`。Clipboard の `actionButton` と同じ。中の `Text` に付けると子の static text に付きうる）。名前は画面ごとの enum（`DialogSampleIdentifiers` など）を唯一の出どころにし、テストの側は Clipboard と同じく文字列の写しを持つ（テストは別のプロセスで、アプリの enum を参照できない。`IosLibraryExampleUITests.swift` の `ClipboardID` の注記） | 既存の Clipboard と同じ形にそろえる。一覧は 5 章。レビュー v1 C-1、C-4 |
| U-18 | 実行の選び方 | **テストプランは作らず**、スクリプトが `build-for-testing` を行い（実機のときは、列挙のためのシミュレーターの分と実機の分の 2 回）、`test-without-building -xctestrun` を**テストのクラスごと**に呼ぶ（0a の `run.sh` と同じ形）。シミュレーターは `-only-testing:IosLibraryExampleUITests/<クラス>`、**実機は宣言の表で選んだテストだけを、シミュレーターの列挙の identifier（`IosLibraryExampleUITests/<クラス>/<メソッド>()`）のまま `-only-testing:` で 1 件ずつ名指しする**（U-9 の一段目。6.3）。**権限のクラス（`NotificationPermissionUITests`）と CB2 のクラスは `UI_CLASSES` に入れず**、アプリの削除を挟む別の段で、メソッドごとに名指しして流す。クラスと機能の対応はスクリプトの表（`UI_CLASSES`）に持ち、許可の区分は宣言の表（`Support/DeviceRequirements.json`）の 1 か所だけに持つ。ランナーもテストもこの表を読む | scheme は自動のテストプラン（`shouldAutocreateTestPlan = "YES"`）で、変えるとプロジェクトの差分が増える。クラスごとに分けると、1 つのクラスが落ちても残りを流せる（Android の 8 章と同じ）。区分を 2 か所に持つと食い違う。レビュー v1 C-2、v2 の「仕組みの直し」 |
| U-19 | 人の確認 | XCUITest で確かめられない項目（画像の中身、音、通知センター、0c の最初に自動化できなかった項目）は手順書にし、**computer use（Claude のデスクトップアプリ）で画面を見て確かめる**（Windows・Android と同じ。2026-10-18、利用者の確認）。シミュレーターは Simulator.app のウィンドウ、実機は Mac の「iPhone ミラーリング」で見る（私物の画面が写るので、実機は 1 回ごとに利用者の許可を得る）。通知の音は、Android と同じく対象外にする（どの手段でも確かめられない。代わりに `NotificationContent` の `sound` の既定値 `.default` を単体テストで確かめる。HC2 は欠番。2026-10-18、利用者の確認）。**判定があいまいなら失敗とする**（4 章）。手順書は `ios/IosLibraryExample/ComputerUse/` に 1 項目 1 ファイルで置く（テストのターゲットのフォルダはファイルシステムと同期するグループなので、その外に置く） | README 7.2、`common.md` の「自動化しないもの」、Android の 7 章 |

### 2.1 `common.md` の「自動化しないもの」との関係

`common.md` の UI 自動テストは「OS のシェル UI・システム設定」「権限ダイアログの初回同意」を自動化しないものにしている。README 7.2 のとおり、0a で 3 回とも安定して扱えた次の項目だけを例外として自動化する。理由は 0a の結果に書いてある。

| 例外にする項目 | 0a の根拠 |
|---|---|
| 通知のバナー（表示、タップ、アクション、返信） | 3.3、3.4、7.2（両方のシミュレーターと実機で通った） |
| 通知の権限のダイアログ（シミュレーターと、許可を得た実機の基準だけ） | 3.2、7.2 |
| 貼り付けの許可のダイアログ | 3.7、7.2 |
| Share のシート（Copy、Save to Files、閉じる、除外） | 3.6、7.2 |
| 設定の App が前面に来ること（中身は読まない。N3） | 0a では試していない。0c の最初に確かめる（未確認） |
| ホームのアイコンのバッジを読むこと（N34） | 0a では試していない。0c の最初に確かめる（未確認） |
| ログインのダイアログ（D11〜D13、D15。パスワードの保存や AutoFill のシステムの UI が出うる） | 0a 7.2 で実機のログインは通ったが、保存の確認が出るかは見ていない。実機では `credentials` を許したときだけ流す。確かめは利用者が見ている前で手で行う（8.1） |

通知センターは例外にしない（U-5）。

## 3. テストケース

### 3.0 共通

- 表の「環境」は `両方`（シミュレーターと実機）・`sim`・`実機` のどれか。括弧の中は、そのテストが宣言する許可の区分（U-9）。区分の無いテストは実機でもいつも流れる。区分は宣言の表（`Support/DeviceRequirements.json`）に写す。表とビルドしたテストが一致しなければランナーが止まる（U-9）
- 「自動か人か」の `自動*` は、0a で試していないか結果が出ていない項目で、**0c の最初に両方の環境で確かめてから期待値を確定する**（だめなら人の確認に移し、理由を 0c の結果に書く）。確かめる項目は 8.1 の表にまとめた
- 期待値の結果の行は ✅ / ❌ と本文。全文を完全一致で比べる（U-1）。「回数」は結果の行の `accessibilityValue`（U-3）
- 通知のバナーは、springboard の identifier `NotificationShortLookView`、**ラベルが `IosLibraryExample, ` で始まること（`BEGINSWITH[c]`）**、`", <題>, "` を含み `", <本文>"` で終わることの 3 つで選び、**`.element`（ちょうど 1 つ）**で取る。複数当たれば触らずに失敗する（プローブの `notificationView` は `CONTAINS[c]` だったが、私物の通知の本文にアプリの名前が入りうるので、先頭に錨を打つ。レビュー v1 B-5）。ラベルの形（`IOSLIBRARYEXAMPLE, now, <題>, <本文>`、ja では `今`）は 26.2 と 18.3 で確かめた（0a 3.3）。実機のラベルの区切りは未確認（8.1）
- 広げたバナーのアクションのボタン（`Open` / `Delete` / `Reply`）と返信の `Send` は、**広げたサンプルの通知の中に範囲を限って**探し、`.element` で取る。広げた通知を表す要素（範囲の根）は 0c の最初に両方の OS で確かめる（8.1。プローブは `springboard.buttons["Open"]` を springboard 全体から探していた）。確かめられなければ springboard 全体で `.element` を取り、2 件以上なら押さずに失敗する
- 通知のテストの前提: 通知の権限が `authorized`。`setUp` で `AuthorizationStatus` を読み、`notDetermined` なら、**`systemui` を宣言したテストだけ** `RequestPermission` → 許可を押す（シミュレーターでは 6.3 の権限の段が先に許可の状態にしているので、ふつうは起きない）。`systemui` を宣言していないテストは、実機では `XCTSkip("NTK-PRECONDITION:notDetermined")` で飛ばし、シミュレーターでは失敗にする。`NTK-PRECONDITION:` は区分で除いたもの（`NTK-GATED`）と分けて数え、基準と比べるときは失敗にする（実機で通知のテストが 1 件も流れないまま合格になるのを防ぐ。レビュー v2 B-N9）。`denied` なら「アプリの削除が要る」と書いて失敗する（プローブの `ensureNotificationPermission` を改めた。レビュー v1 A-3）

### 3.1 メニューと識別子（`NavigationUITests`、`IdentifierInventoryUITests`）

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| M1 | メニュー → Dialog / Notification / Share の画面（`menu.dialog` / `menu.notification` / `menu.share`）→ ナビゲーションバーの戻る | 各画面の結果の行（`<画面>.result`）が出る。戻るとメニューのカードがまた出る。Clipboard の画面は `clipboard` の区分が要るので、ここでは開かない（U1〜U21 が開く） | 両方 | 自動 | 3.1（メニューのカードを開けた） |
| M2 | Dialog で ShowAlert → OK → メニューに戻る → Dialog を開き直す。Notification は `HasPermission` で同じ | 開き直すと結果の行が `Result will be displayed here`、回数が初めの値に戻る（各画面の `@State`）。Share は `share.button.*` に `sharesheet` の印が要るので入れない | 両方 | 自動 | 無し（アプリの中だけ） |
| I1a | Dialog の画面で、画面の**ボタンをすべて**集める（下の集め方）。ナビゲーションバーの戻るのボタンは明示して除く | (1) 残ったボタンが**すべて** `dialog.button.` で始まる識別子を持つ（識別子の無いボタンがあれば落ちる）。(2) その識別子の集合が 5 章の一覧と完全に一致し、件数も一致し、重複が無い。(3) ボタンでない識別子（`dialog.result`）が在る | 両方 | 自動* | 無し |
| I1b | Notification の画面で同じ | I1a と同じ（`notification.button.`）。ボタンでない識別子は結果の行、節 7、最後のイベント 5 | 両方 | 自動* | 無し |
| I1c | Share の画面で同じ。ボタンは押さない | I1a と同じ（`share.button.`）。ボタンでない識別子は結果の行と節 6 | 両方 | 自動* | 無し |
| I1d | Clipboard の画面で同じ。貼り付けのコントロール（`clipboard.pasteControl`。マウントした後だけ在る）も明示して除く。ボタンは押さない | I1a と同じ（`clipboard.button.`）。ボタンでない識別子は `result`・`status`・`pasteSummary` と節 11。Clipboard の画面を開くので `clipboard` を宣言する | 両方（`clipboard`） | 自動* | 無し |

I1a〜I1d は、画面の側を実行中の UI から集め、一覧の側を 5 章（0b で作る画面ごとの enum と同じもの）から取る。識別子を付けずにボタンを足したとき、一覧に無い識別子を足したとき、同じ識別子を 2 つ付けたときのどれでも落ちる（`common.md` の「両辺を導出する」「件数の一致」。レビュー v1 A-2）。画面ごとに分けたのは、`clipboard` を許さない実機でも Dialog・Notification・Share の識別子の検査を流すため（レビュー v2 B-N6）。

**集め方**: 各画面のボタンは `ScrollView` の中の遅延でない `VStack` にあるので、まず**スクロールせずに 1 回の snapshot** で集める。画面の外のボタンが snapshot に入る保証は無いので、0c の最初に両方の OS で、画面ごとに入る件数を測る（8.1）。入らない画面は、**上から下へ慣性の無いドラッグで 1 段ずつ動かし、位置ごとの snapshot の和集合**を取る。そのときは、同じボタンが 2 つの位置で見えることがあるので、要素の識別子と画面の中の位置（スクロールの量を足した縦の位置）の組で同じものを 1 つにまとめ、そのうえで識別子の重複・件数・集合を照らす（レビュー v2 B-12）。

### 3.2 Dialog（`DialogUITests`）

サンプルのボタン 6 つ（`DialogSampleView.swift:25-173`）。Dialog は `app.alerts["<題>"]`（action sheet は選択肢のボタン）で探す。回数は U-3 の `completion=<n>,callback=<n>`。**Dialog が出ている間に後ろの結果の行を読めるか**は 0a で試していないので、D1・D2・D6 の「出ている間」の確かめは 0c の最初に確かめる（8.1。読めなければ、閉じた後の回数の増分で completion を確かめる形にする）。

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| D1 | ShowAlert → OK | 題 `Hello from iOS`、本文 `This is a native iOS dialog!`、ボタンは `OK` の 1 つだけ。出ている間の結果の行が ✅ `[showAlert][completion] isSuccess: true, errorMessage: nil`（`completion=1,callback=0`）。OK の後 ✅ `[showAlert][onButton] buttonText: OK, isSuccess: true, errorMessage: nil`（`completion=1,callback=1`）。Dialog が消える | 両方 | 自動（出ている間は自動*） | 3.1、7.2 |
| D2 | ShowConfirmDialog → Yes | 題 `Confirm Action`、本文 `Are you sure you want to proceed?`、ボタン `Yes` / `No`。出ている間 ✅ `[showConfirmDialog][completion] isSuccess: true, errorMessage: nil`。押した後 ✅ `[showConfirmDialog][onConfirm] confirmButtonText: Yes, isSuccess: true, errorMessage: nil`（`completion=1,callback=1`） | 両方 | 自動（出ている間は自動*） | 3.1、7.2 |
| D3 | ShowConfirmDialog → No | ✅ `[showConfirmDialog][onCancel] cancelButtonText: No, isSuccess: true, errorMessage: nil`（`completion=1,callback=1`） | 両方 | 自動 | 3.1、7.2 |
| D4 | ShowDestructiveDialog → Delete | 題 `Delete File`、本文 `This action cannot be undone. Are you sure?`、ボタン `Delete` / `Cancel`。✅ `[showDestructiveDialog][onDestructive] destructiveButtonText: Delete, isSuccess: true, errorMessage: nil`（`completion=1,callback=1`） | 両方 | 自動 | 3.1、7.2 |
| D5 | ShowDestructiveDialog → Cancel | ✅ `[showDestructiveDialog][onCancel] cancelButtonText: Cancel, isSuccess: true, errorMessage: nil`（`completion=1,callback=1`） | 両方 | 自動 | 3.1、7.2 |
| D6 | ShowActionSheet → `Camera`、`Photo Library`、`Documents` を 1 回ずつ（3 回出す） | 題 `Please select`、本文 `Please choose an option`、選択肢 3 つ。出ている間 ✅ `[showActionSheet][completion] isSuccess: true, errorMessage: nil`。押した後 ✅ `[showActionSheet][onAction] action: <選んだもの>, isSuccess: true, errorMessage: nil` | 両方 | 自動（出ている間は自動*） | 3.1、7.2 |
| D7 | ShowActionSheet → 取り消し | **iOS 18（実機、18.3）**: Sheet で `Cancel` のボタンがあり、押す。**iOS 26.2**: Popover で `Cancel` が押せず、`PopoverDismissRegion` を押す。どちらも ✅ `[showActionSheet][onAction] action: Cancel, isSuccess: true, errorMessage: nil`。形（Cancel があるか）も OS の版ごとに確かめる | 両方 | 自動 | 3.1、7.2（R-5） |
| D8 | ShowTextInputDialog（何も入れない）→ 1 文字入れる → 消す | 題 `Enter Name`、本文 `Please enter your name`、入力欄のヒント `Your name here`。空の間は OK が無効（`isEnabled == false`）、入れると有効、消すとまた無効 | 両方 | 自動（消した後は自動*） | 3.1、7.2 |
| D9 | ShowTextInputDialog → `Taro 太郎` → OK | ✅ `[showTextInputDialog][onConfirm] confirmButtonText: OK, inputText: Taro 太郎, isSuccess: true, errorMessage: nil`（`completion=1,callback=1`） | 両方 | 自動 | 3.1（日本語の入力も通った）、7.2 |
| D10 | ShowTextInputDialog → `abc` → Cancel | ✅ `[showTextInputDialog][onCancel] cancelButtonText: Cancel, isSuccess: true, errorMessage: nil`（入力は報告されない） | 両方 | 自動 | 3.1 |
| D11 | ShowLoginDialog（何も入れない）→ ユーザー名だけ → パスワードも | 題 `Login Required`、本文 `Please enter your credentials`、ヒント `Username` / `Password`。パスワードは `secureTextFields`。空と、ユーザー名だけの間は Login が無効、両方入れると有効 | 両方（`credentials`） | 自動 | 3.1、7.2 |
| D12 | ShowLoginDialog → `taro` / `secret1` → Login | ✅ `[showLoginDialog][onLogin] loginButtonText: Login, username: taro, password: secret1, isSuccess: true, errorMessage: nil`（`completion=1,callback=1`）。**パスワードが結果の行に平文で出るのは今の動作**（README 1.4）で、そのまま期待値にする。1b で直すなら期待値を変えて理由を書く | 両方（`credentials`） | 自動 | 3.1、7.2 |
| D13 | ShowLoginDialog → Cancel | ✅ `[showLoginDialog][onCancel] cancelButtonText: Cancel, isSuccess: true, errorMessage: nil` | 両方（`credentials`） | 自動 | 3.1 |
| D14 | ログインのほかの 5 種（Alert、Confirm、Destructive、ActionSheet、TextInput）のそれぞれで、出す前に回数を読み、出してボタンを押し、2 秒待つ（固定の待ち。U-14） | 出す前からの**増分が `completion` +1、`callback` +1 ちょうど**（表示の完了と、押した後のコールバックが 1 回ずつ）。どちらかが 0 や 2 以上なら落ちる | 両方 | 自動 | 無し |
| D15 | ShowLoginDialog で D14 と同じ（`taro` / `secret1` → Login） | D14 と同じ増分。宣言はテストごとなので、区分の違うログインの分を D14 から分けた（レビュー v2 C-N4） | 両方（`credentials`） | 自動 | 無し |

テストに入れないもの: ルートの ViewController が取れないときの失敗（`Failed to get root view controller`）。サンプルの画面から起こせない（scene はいつも前面で、0a 3.8 で scene の無い構成でも取れた）。

### 3.3 Notification

サンプルのボタン 25（`NotificationSampleView.swift:31-374`）。通知の id は `sample-notification`（Show と Update と Cancel / RemoveDelivered）と `scheduled-notification`（Schedule と CancelScheduled）、category は `sample-category`（`NotificationSampleView.swift:8-10`）。**通知を出すテストは、取り消しを確かめるものも含めて `systemui` を宣言する**（取り消しが壊れていると、私物の端末の画面にバナーが出る）。通知を出すボタン（Show* / Schedule* / UpdateById）と、システムの UI を出す `RequestPermission`・`OpenNotificationSettings` を押す `SampleApp` の口は `SystemUIToken` を要る形にする（二段目。一段目はランナーが宣言で選ぶこと。レビュー v2 B-N2、v3 B-3）。`RegisterCategory`・`RemoveCategory`・`SetBadgeCount` は区分を要らない（サンプル自身の状態だけを変え、システムの UI を出さない。6.1）。

#### 権限（`NotificationPermissionUITests`。スクリプトがアプリを削除してから 1 件ずつ流す。U-7、U-18）

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| NP2 | 削除の直後: AuthorizationStatus、HasPermission → RequestPermission → springboard のダイアログで拒否（`Don’t Allow` / `許可しない`）→ AuthorizationStatus、HasPermission → RequestPermission をもう一度 → ShowImmediate | 初めは ✅ `[authorizationStatus] notDetermined`、✅ `[hasPermission] false`。ダイアログは**アプリを操作する前に**springboard で待って押す（U-8）。拒否の後 ❌ `[requestPermission] denied. Permission dialog will not appear again. Please enable notifications in Settings.`、✅ `[authorizationStatus] denied`、✅ `[hasPermission] false`。2 回目の要求ではダイアログが 5 秒出ず（固定の待ち。U-14）、結果は同じ ❌ の文言。ShowImmediate は ❌ `Notification permission is not granted. Please request permission first.` で、バナーが 5 秒出ない（固定の待ち） | sim（実機は基準のときだけ。`reinstall`、`systemui`） | 自動 | 3.2、7.2（拒否の経路） |
| NP1 | 削除の直後: RequestPermission → 許可（`Allow` / `許可`）→ AuthorizationStatus、HasPermission | ✅ `[requestPermission] granted`、✅ `[authorizationStatus] authorized`、✅ `[hasPermission] true` | sim（実機は基準のときだけ。`reinstall`、`systemui`） | 自動 | 3.2、7.2 |

#### 権限の状態と設定（`NotificationUITests`）

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| N1 | HasPermission、AuthorizationStatus | ✅ `[hasPermission] true`、✅ `[authorizationStatus] authorized` | 両方 | 自動 | 3.2 |
| N2 | RequestPermission（許可済み） | システムのダイアログが 5 秒出ない（固定の待ち。springboard を読む）。✅ `[requestPermission] granted` | 両方（`systemui`） | 自動* | 無し |
| N3 | OpenNotificationSettings → 設定の App が前面に来るのを待つ → `app.activate()` | ✅ `[openNotificationSettings] called`。設定の App（`com.apple.Preferences`）が `runningForeground` になる（10 秒まで）。設定の画面の中は読まず、押さない | 両方（`systemui`） | 自動* | 無し |

#### 表示（`NotificationUITests`）

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| N4 | ShowImmediate（前面のまま）→ GetDelivered | ✅ `[showImmediate] error: nil`。前面でもバナー（題 `Immediate Notification`、本文 `Displayed now`）が 10 秒までに出る（`foregroundPresentationOptions` の `.banner`。`IosNotificationManager.swift:79`）。✅ `[getDelivered] count: 1, ids: [sample-notification]`（`.list` で一覧に残る） | 両方（`systemui`） | 自動 | 3.3、7.2 |
| N5 | ShowImmediateWithAttachment(AppIcon) を 2 回（間に RemoveAllDelivered） | 2 回とも ✅ `[showImmediateWithAttachment] error: nil` で、バナー（題 `Immediate Notification with Attachment`、本文 `Displayed with app icon attachment`）が出る。2 回目も添付で失敗しない（同じバンドルのファイルを添付に使い回す。`UNNotificationAttachment` がファイルを移すか写すかは未確認）。画像の中身は HC1 | 両方（`systemui`） | 自動* | 無し |
| N6 | ShowTimeInterval(5s) → GetScheduled → ホームに戻る | ✅ `[showTimeInterval] error: nil`。発火の前は ✅ `[getScheduled] count: 1, ids: [sample-notification]`。ホームでバナー（題 `5s Notification`、本文 `Will be shown after 5 seconds`）が 20 秒までに出る。その間アプリは前面にいない | 両方（`systemui`） | 自動 | 3.3、7.2 |
| N7 | ShowCalendar(+1m)（前面のまま）→ GetScheduled | ✅ `[showCalendar] error: nil`。✅ `[getScheduled] count: 1, ids: [sample-notification]`。バナー（題 `Calendar Notification`、本文 `Will be shown in one minute`）が 90 秒までに出る | 両方（`systemui`） | 自動* | 3.5（カレンダーは試していない） |
| N8 | ShowLocation(Tokyo Station, onEntry) → GetScheduled | 成功なら ✅ `[showLocation] Registered. Notification will fire when entering Tokyo Station (radius: 100m).`、失敗なら ❌ `[showLocation] error: ` で始まる（`NotificationSampleView.swift:148-153`。エラーの文言は OS の言語で変わる。3.3 の対象外の表）。どちらになるか、予約の一覧に `sample-notification` が入るかを、0c の最初に両方の環境で記録して期待値にする。サンプルは位置の権限を求めず、Info.plist に位置の利用目的の文言も無い（pbxproj に `NSLocation` の設定が無い）。**発火は確かめない** | 両方（`systemui`。予約を作り、通知を出すボタンを押すため。レビュー v2 C-N6） | 自動* | 無し |

#### 更新・取り消し・削除（`NotificationUITests`）

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| N9 | ShowTimeInterval(5s) → すぐ UpdateById → GetScheduled、GetDelivered | ✅ `[update] id: sample-notification, error: nil`。更新した通知（題 `Updated Notification`、本文 `This content was updated`）がすぐバナーで出る（trigger が nil）。予約の時刻 + 5 秒（10 秒）まで `5s Notification` のバナーが出ない（固定の待ち）。✅ `[getScheduled] count: 0, ids: []`、✅ `[getDelivered] count: 1, ids: [sample-notification]`（`update` は予約を消してから同じ id で足す。`NotificationRepositoryImpl.update`） | 両方（`systemui`） | 自動* | 3.3、3.5 |
| N10 | ShowImmediate → UpdateById → GetDelivered | 表示済みの同じ id を更新すると、表示中の通知が置き換わり、`count: 1` のまま（OS の振る舞い。未確認なので 0c の最初に記録して期待値にする） | 両方（`systemui`） | 自動* | 無し |
| N11 | ShowTimeInterval(5s) → CancelById → GetScheduled | ✅ `[cancel] id: sample-notification`。予約が 10 秒までに `count: 0, ids: []` になる（U-6）。予約の時刻 + 5 秒までバナーが出ない（固定の待ち） | 両方（`systemui`） | 自動 | 3.5 |
| N12 | ShowImmediate → CancelById → GetDelivered | 表示済みの通知は消えず ✅ `[getDelivered] count: 1, ids: [sample-notification]`（`cancel` は予約だけを消す。今の動作。README 1.4 で `cancel` と `cancelScheduled` が同じ処理と記録済み。1b で意味を変えるなら期待値を変える） | 両方（`systemui`） | 自動 | 無し |
| N13 | ShowTimeInterval(5s) → ScheduleTimeInterval(10s) → CancelAll → GetScheduled | ✅ `[cancelAll] called`。予約が 2 件から `count: 0, ids: []` になる | 両方（`systemui`） | 自動 | 無し |
| N14 | ShowImmediate → RemoveDeliveredById → GetDelivered | ✅ `[removeDelivered] id: sample-notification`。`count: 0, ids: []` になる（10 秒まで） | 両方（`systemui`） | 自動 | 無し |
| N15 | ShowImmediate → ScheduleTimeInterval(10s) のバナーを待つ → GetDelivered → RemoveAllDelivered → GetDelivered | 2 件（`sample-notification` と `scheduled-notification`。U-6 の 3 つを照らす）から、✅ `[removeAllDelivered] called` の後 `count: 0, ids: []` になる | 両方（`systemui`） | 自動 | 3.5 |

#### 予約（`NotificationUITests`）

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| N16 | ScheduleTimeInterval(10s) → GetScheduled → 発火を待つ → GetScheduled、GetDelivered | ✅ `[scheduleTimeInterval] id: scheduled-notification, error: nil`。発火の前は `count: 1, ids: [scheduled-notification]`。バナー（題 `Scheduled Notification`、本文 `Scheduled in 10 seconds`）が 25 秒までに出る。出た後は予約が `count: 0, ids: []`、表示中に `scheduled-notification` | 両方（`systemui`） | 自動 | 3.5、7.2 |
| N17 | ScheduleCalendar(+1m) → GetScheduled → CancelScheduledById → GetScheduled | ✅ `[scheduleCalendar] id: scheduled-notification, error: nil`、予約に `scheduled-notification`。取り消すと ✅ `[cancelScheduled] id: scheduled-notification`、`count: 0, ids: []`。カレンダーの発火は N7 で確かめるので、ここでは待たない | 両方（`systemui`） | 自動 | 無し |
| N18 | ScheduleLocation(Tokyo Station, onEntry) → GetScheduled | 成功なら ✅ `[scheduleLocation] Registered. Notification will fire when entering Tokyo Station (radius: 100m).`、失敗なら ❌ `[scheduleLocation] error: ` で始まる（`NotificationSampleView.swift:262-267`）。N8 と同じく、どちらになるかを 0c の最初に記録して期待値にする。発火は確かめない | 両方（`systemui`。予約を作り、通知を出すボタンを押すため。レビュー v2 C-N6） | 自動* | 無し |
| N19 | ScheduleTimeInterval(10s) → CancelScheduledById → GetScheduled | ✅ `[cancelScheduled] id: scheduled-notification`。`count: 0, ids: []`。予約の時刻 + 5 秒（15 秒）までバナーが出ない（固定の待ち） | 両方（`systemui`） | 自動 | 3.5 |
| N20 | ShowTimeInterval(5s) → ScheduleTimeInterval(10s) → CancelAllScheduled → GetScheduled | ✅ `[cancelAllScheduled] called`。Show で作った予約（`sample-notification`）も消え、`count: 0, ids: []`（今は `cancelAll` と同じ処理。README 1.4） | 両方（`systemui`） | 自動 | 無し |

#### 問い合わせとバッジ（`NotificationUITests`）

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| N21 | アプリの中の片付けの後に GetScheduled、GetDelivered | ✅ `[getScheduled] count: 0, ids: []`、✅ `[getDelivered] count: 0, ids: []` | 両方 | 自動 | 3.8 の後始末（プローブの `testZ_sampleState`） |
| N22 | SetBadgeCount(1) → SetBadgeCount(0) | ✅ `[setBadgeCount] 1, error: nil`、✅ `[setBadgeCount] 0, error: nil`。結果の行だけを確かめる（ホームは読まない） | 両方 | 自動 | 無し |
| N34 | SetBadgeCount(1) → ホーム → アイコンのバッジを読む → アプリに戻って SetBadgeCount(0) → ホーム → 読む | springboard のアイコンの `value`（または label）で、1 のときバッジが `1`、0 のとき無い。読み方は 0c の最初に確かめる。読めなければ HC3 に移す | 両方（`systemui`） | 自動* | 無し |

N34 は、ホームのアイコンを読むのが springboard の操作なので N22 から分けた（レビュー v1 A-8）。番号は表の並びでなく、足した順で付けた。

#### category とイベント（`NotificationEventUITests`。最後のイベントは 5.2）

category の登録と削除は、ライブラリがそれぞれ別の `Task` で非同期に行い、呼んだ直後に結果の行を出す（`IosNotificationManager.swift:306-316`）。2 つの `Task` の順は保証されず、5 秒の予約は通知を遅らせるだけで順を作らない（レビュー v2 B-N7）。そこで、category を確かめるテストは、**登録・削除の効果を通知で観測してから次の操作をする**形にし、前後の両側を観測で区切る。通知には 5 秒の予約（ShowTimeInterval(5s)）を使う（即時の通知より、`Task` が終わるまでの余裕がある。余裕で足りない場合は残る。8.1）。「アクションが無い」ことは、**広げたことを示す要素**（範囲の根。3.0）が出たのを確かめてから判定する。その要素が両方の OS で確かめられなければ、「無い」側の判定は人の確認に移す（レビュー v1 B-1）。

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| N23 | RemoveCategory → ShowTimeInterval(5s) → ホーム → バナーを長押し → 広げた印を待つ（**無いことを観測**）→ ホームに戻り、アプリを前面へ → RegisterCategory → ShowTimeInterval(5s) → ホーム → バナーを長押し（**有ることを観測**）→ 片付け | 1 回目は広げた印が出て 3 秒、`Open`・`Delete`・`Reply` が無い。✅ `[registerCategory] Registered. Send a notification and long-press to see the actions (Open, Delete, Reply).` の後の 2 回目は、`Open`・`Delete`・`Reply` が 5 秒までに出る（前後の差で登録の効果を確かめる。category は OS に残るので、登録だけを見ると登録が効いていなくても通る） | 両方（`systemui`） | 自動（「無い」側は自動*） | 3.3、7.2 |
| N24 | RemoveCategory → ShowTimeInterval(5s) → ホーム → バナーを長押し（**無いことを観測**）→ アプリを前面へ → RegisterCategory → ShowTimeInterval(5s) → 長押し（**有ることを観測**）→ アプリを前面へ → RemoveCategory → ShowTimeInterval(5s)（別の通知）→ 長押し（**無いことを観測**）→ 最後に RegisterCategory | 1 回目と 3 回目は広げた印が出て 3 秒、`Open`・`Delete`・`Reply` が無い。2 回目は 5 秒までに出る。✅ `[removeCategory] id: sample-category`。category は前のテストや 0a から OS に残っているので、初めに RemoveCategory で消えたことを観測してから始める（「登録を観測してから削除するので順は逆にならない」は、前から残っている category で登録を観測しうるので成り立たなかった。レビュー v3 C-4）。削除の効果は 3 回目で観測する | 両方（`systemui`） | 自動* | 無し |
| N25 | ShowTimeInterval(5s) → ホーム → バナーをタップ | アプリが 10 秒までに前面に戻り、通知の画面のまま。最後のイベントが `sequence=1`、`kind=action`、`notificationId=sample-notification`、`actionId=com.apple.UNNotificationDefaultActionIdentifier`、`userText=nil`。2 秒待っても `sequence=1` のまま（ちょうど 1 回） | 両方（`systemui`） | 自動（イベントは 0b の後） | 3.3、7.2 |
| N26 | ShowImmediate（前面のまま）→ 前面のバナーをタップ | 最後のイベントが N25 と同じ内容 | 両方（`systemui`） | 自動* | 無し |
| N27 | RegisterCategory → ShowTimeInterval(5s) → ホーム → バナーを長押し → `Open` | アプリが前面に戻る。`kind=action`、`actionId=open`、`notificationId=sample-notification` | 両方（`systemui`） | 自動 | 3.3、7.2 |
| N28 | RegisterCategory → ShowTimeInterval(5s) → ホーム → バナーを長押し（シミュレーターでは、長押しで広がらなければ下へドラッグ。**実機は長押しだけ**。U-5）→ `Delete` → 2 秒待つ（固定の待ち）→ `app.activate()` | Delete の後 2 秒、アプリは前面に来ない（`.destructive` だけで `.foreground` が無い）。`activate` の後、`kind=action`、`actionId=delete` | 両方（`systemui`） | 自動 | 3.3、7.2 |
| N29 | RegisterCategory → ShowTimeInterval(5s) → ホーム → バナーを長押し → `Reply` → 入力欄（TextView、placeholder `Type a message`）に `hello reply` → `Send` → `app.activate()` | `kind=textInput`、`actionId=reply`、`notificationId=sample-notification`、`userText=hello reply` | 両方（`systemui`） | 自動 | 3.3（TextView であること）、7.2 |

N27〜N29 も、category の反映を待つため 5 秒の予約を使う（0a のプローブは即時の通知で 3/3 通ったが、反映の順は保証されない）。

#### コールドスタート（`NotificationColdStartUITests`。D-7 の、起動の終わりまでに delegate を入れることを守る）

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| N30 | ShowTimeInterval(5s) → `app.terminate()`（`notRunning` を待つ）→ バナーが出たらタップ | アプリが 15 秒までに前面に来る。メニューが出る。`menu.notification` で通知の画面を開くと、最後のイベントが `sequence=1`、`kind=action`、`notificationId=sample-notification`、`actionId=com.apple.UNNotificationDefaultActionIdentifier`、`userText=nil`（画面は入れ物に保存済みの snapshot を読む。U-4） | 両方（`systemui`） | 自動（イベントは 0b の後） | 3.4（バナーのタップ 3/3）、7.2 |
| N31 | RegisterCategory → ShowTimeInterval(5s) → terminate → バナーを長押し → `Open` | 前面に来る。通知の画面で `actionId=open` | 両方（`systemui`） | 自動 | 3.4、7.2 |
| N32 | RegisterCategory → ShowTimeInterval(5s) → terminate → バナー → `Reply` → `cold reply` → `Send` → `app.activate()` | `kind=textInput`、`actionId=reply`、`userText=cold reply`。受け手は `completionHandler` の前に同期で保存する（U-4）が、**システムが背景で起動したプロセスが `activate` まで残るか**は未確認（残らなければイベントは消える。永続化はしない）。0c の最初に 3 回確かめ、安定しなければ人の確認（HC5）に移す | 両方（`systemui`） | 自動* | 無し |
| N33 | 同じく terminate の後に `Delete` → `app.activate()` | `kind=action`、`actionId=delete`。N32 と同じ未確認 | 両方（`systemui`） | 自動* | 無し |

テストに入れないもの:

| 対象 | 理由 |
|---|---|
| 位置の予約の発火（N8、N18） | 位置の権限と、領域に入ることが要る。サンプルは位置の権限を求めない |
| `customDismissAction` による消したときのイベント（`com.apple.UNNotificationDismissActionIdentifier`） | 通知センターで消す操作が要る（U-5）。HC4 |
| 通知の音 | HC2 |
| `openSettingsFor`（通知の設定から開く経路） | 設定の App の中を操作する必要がある（`common.md` の自動化しないもの） |
| 通知の操作のエラーの文言 | `NotificationError` は `LocalizedError` に従っておらず、`localizedDescription` が OS の言語の汎用の文になる（`NotificationError.swift:9-27`）。en と ja で全文が違うので、エラーの経路（N5 の 2 回目が失敗したとき、N8・N18 の失敗など）は `❌` と `[marker] error: ` までを比べる |
| 添付の画像がバンドルに無いときの経路 | `makeContentWithAppIconAttachment` は画像が見つからないと、添付の無い内容を黙って返す（`NotificationSampleView.swift:409-411`）。結果の行は ✅ のままで、自動では見分けられない。添付が付いていることは HC1 で確かめる |

### 3.4 Share（`ShareUITests`）

サンプルのボタン 14（`ShareSampleView.swift:26-189`）。Share の手動確認 15 項目（`2026-07-04-ios-share-sample-app-design-v1.md` 5 章）のうち、#1 は M1、#2〜#13 と #15 は下の表、#14（iPad）は対象外。`share.button.*` を押すには `sharesheet` の印が要る（U-9）ので、Share のテストはすべて `sharesheet` を宣言する。

シートの技法（0a 3.6、プローブの `Stage0aShareProbeTests`）: シートが出たことは Copy（`Copy` / `コピー`）か `UIActivityContentView` のナビゲーションバーで待つ。閉じるのは、iOS 18 は `Close` / `閉じる`、iOS 26.2 は `PopoverDismissRegion`（U-16）。ヘッダーを下へドラッグする方法は両方で通る。Copy と Save to Files は `.element` で取り、2 件以上なら押さない（U-13）。

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| S1 | ShareText → Copy | ✅ `[shareText] completed=true, activityType=com.apple.UIKit.activity.CopyToPasteboard` | 両方（`sharesheet`、`clipboard`） | 自動 | 3.6、7.2 |
| S2 | ShareText → 閉じる（版で分ける） | ✅ `[shareText] completed=false (cancelled)`。`errorMessage` が無い（手動確認 #15） | 両方（`sharesheet`） | 自動 | 3.6、7.2 |
| S3 | ShareURL → ヘッダーを下へドラッグ | ✅ `[shareURL] completed=false (cancelled)` | 両方（`sharesheet`） | 自動 | 3.6（`testS3_swipeDownDismiss`）、7.2 |
| S4 | ShareURL → Copy | ✅ `[shareURL] completed=true, activityType=com.apple.UIKit.activity.CopyToPasteboard` | 両方（`sharesheet`、`clipboard`） | 自動 | 3.6 |
| S5 | ShareURLWithPreview → シートのヘッダーを読む → 閉じる | ヘッダーに `Apple` が、シートが出てから 2 秒までに出る（ネットワークを待たない。手動確認 #4）。✅ `[shareURLWithPreview] completed=false (cancelled)`。ヘッダーの文字を要素として読めるかは未確認（読めなければ HC6） | 両方（`sharesheet`） | 自動* | 無し |
| S6 | ShareImage → Copy | ✅ `[shareImage] completed=true, activityType=com.apple.UIKit.activity.CopyToPasteboard`。画像の中身は HC7 | 両方（`sharesheet`、`clipboard`） | 自動* | 無し（Copy の技法は 3.6） |
| S7 | ShareMultipleImages → 閉じる | シートが出る。✅ `[shareMultipleImages] completed=false (cancelled)`。2 枚が渡ることは HC7 | 両方（`sharesheet`） | 自動 | 3.6 |
| S8 | ShareFile → Save to Files（`Save to Files` / `“ファイル”に保存` / `"ファイル"に保存`）→「このiPhone内」を選び直す → Save → 置き換えの確認が出たら Keep Both | ✅ `[shareFile] completed=true, activityType=com.apple.DocumentManagerUICore.SaveToFiles`。保存先を選べなければ保存せずにキャンセルし、失敗にする（U-11） | 両方（`sharesheet`、`files`） | 自動 | 3.6、7.2、7.3 |
| S9 | ShareMultipleFiles → Save to Files（S8 と同じ手順） | ✅ `[shareMultipleFiles] completed=true, activityType=com.apple.DocumentManagerUICore.SaveToFiles`。2 件の保存でピッカーの形が変わるかは未確認。**0c の最初に、成功の経路（2 件とも「このiPhone内」に保存される）を確かめられた環境だけ自動にし、ほかの環境では人の確認（HC9）に移す**（閉じて `completed=false` を見るだけでは、2 件を渡せることも保存の成功も確かめないため。レビュー v1 B-2） | 両方（`sharesheet`、`files`） | 自動* | 無し |
| S10 | ShareMultiple → Copy | ✅ `[shareMultiple] completed=true, activityType=com.apple.UIKit.activity.CopyToPasteboard`。テキストと URL の両方が渡ることは HC8 | 両方（`sharesheet`、`clipboard`） | 自動* | 無し |
| S11 | ShareWithSubject → 閉じる | シートが出る。✅ `[shareWithSubject] completed=false (cancelled)`。件名が使われることは確かめない（1 章の対象外。`ShareItemSource` の単体テストに任せる） | 両方（`sharesheet`） | 自動 | 3.6 |
| S12 | ShareExcludingActivities → 2 秒待つ → 閉じる | `UIActivityContentView` が出た後 2 秒（固定の待ち）、Copy が無い（手動確認 #9 の主確認。Facebook は確かめない）。✅ `[shareExcludingActivities] completed=false (cancelled)` | 両方（`sharesheet`） | 自動 | 3.6（`testS4_excludedCopyIsAbsent`）、7.2 |
| S13 | ShareEmpty | ❌ `[shareEmpty] errorMessage=No shareable items were provided.`。2 秒たってもシートが無い | 両方（`sharesheet`） | 自動 | 無し（文言は `ShareError.swift:32-48`） |
| S14 | ShareInvalidURL | ❌ `[shareInvalidURL] errorMessage=Invalid URL: not a valid url.`。シートが無い | 両方（`sharesheet`） | 自動 | 無し |
| S15 | ShareMissingFile | ❌ `[shareMissingFile] errorMessage=File not found at path: /nonexistent/share-missing.txt.`。シートが無い | 両方（`sharesheet`） | 自動 | 無し |
| S16 | ShareMissingImage | ❌ `[shareMissingImage] errorMessage=Failed to load image at path: /nonexistent/share-missing.png.`。シートが無い | 両方（`sharesheet`） | 自動 | 無し |

`ShareError` は `LocalizedError` で文言が英語の固定なので（`ShareError.swift:30-49`）、S13〜S16 は全文を比べる。S13〜S16 はシートを開かないボタンだが、壊れたときにシートが開くので `sharesheet` を宣言する（U-9）。

テストに入れないもの:

| 対象 | 理由 |
|---|---|
| サンプルの準備の失敗（❌ `[shareImage] Sample image not found in bundle`、❌ `[shareMultipleImages] Sample image preparation failed`、❌ `[shareFile] Sample file preparation failed`、❌ `[shareMultipleFiles] Sample file preparation failed`。`ShareSampleView.swift:64,77,92,105`） | バンドルの画像が無いときと一時フォルダーに書けないときだけの経路で、テストの環境で起こせない。ライブラリを通らない |
| 件名（S11）、iPad | 1 章の対象外 |

### 3.5 Clipboard（既存 22 件 + 追加 4 件）

既存の `ClipboardUITests`（U1〜U21、U10 は U10a と U10b）は番号と本体を変えずに使う。変えるのは、`final class ClipboardUITests: SampleUITestCase` に替えること（6.1 の閉じた形の規則）、`setUpWithError` / `tearDownWithError` を `setUpAfterGate()` / `tearDownAfterGate()` に書き換えること（基底のものは `final`）、宣言の表で 22 件すべてを `clipboard`、U10a を `clipboard` と `systemui` にすること、U-8 の監視が基底で付くことだけ（U-10）。本体は `app` を直接使い、`openClipboardScreen` は `menu.clipboard` のカードを `app.buttons[ClipboardID.menuCard]` で直接押す（`IosLibraryExampleUITests.swift:637`）。これらは印の口を通らないので、二段目は及ばず、一段目（ランナーが `clipboard` を許したときだけ起動する）で守る。閉じた形のソースの規則では、ハッシュで固定したこのファイルの既知の出現だけを例外として回数で照らす（6.1。レビュー v2 C-N8）。このクラスは、メソッドの名前の一覧（22 件）とファイルの中身のハッシュをランナーが固定し、変わったら止まる。**新しい Clipboard のテスト（CB1〜CB4）は新しいクラスに書く**（U-9 の③、U-10。レビュー v3 A-1）。U10b と U21 は意図した skip がありうる（0a 3.7）ので、基準には `skipped` として記録する。

足すもの（0a で自動化できると分かった、外のアプリのコピーに当たるもの。Clipboard v6 の 8.1 #18・#19 と、貼り付けの許可）。テストのランナーは別のアプリなので、ランナーが書いた内容をサンプルが読むと、外のアプリのコピーと同じ扱いになる（0a 3.7）:

| ID | 操作 | 確かめる内容 | 環境 | 自動か人か | 0a の根拠 |
|---|---|---|---|---|---|
| CB1 | ランナーが一般のクリップボードに `ntk-cb1-<時刻>` を書く → useGeneral →（`changeCount` が書いた直後から変わっていないことを確かめる。U-10）→ Load Text → springboard の `Allow Paste` / `ペーストを許可` | 貼り付けの許可のダイアログが 10 秒までに出る。押した後 `✅ #<n> [loadText] textLength=<書いた文字数>` | 両方（`clipboard`、`systemui`） | 自動 | 3.7、7.2 |
| CB2 | 単独で流す（U-12）→ ランナーが書く → Load Text → `Don’t Allow Paste` / `ペーストを許可しない` | `❌ #<n> [loadText] errorCode=CLIPBOARD_LOAD_FAILED, ` で始まる。ダイアログが出る条件は 0c の最初に確かめ、アプリの削除が要るなら `reinstall` を足す | 両方（`clipboard`、`systemui`。要るなら `reinstall`） | 自動* | 7.2（実機で単独なら通った。シミュレーターでは試していない） |
| CB3 | ランナーがテキストを書く → Mount Paste Control →（`changeCount` を確かめる）→ 貼り付けのコントロール（`clipboard.pasteControl`）をタップ | `Paste result: items=1, failures=0`（`ClipboardSampleView.swift:184,589`）。システムのダイアログが出ない（2 秒） | 両方（`clipboard`） | 自動 | 3.7、7.2 |
| CB4 | ランナーが画像だけを書く（`UIPasteboard.general.image`）→ Mount Paste Control →（`changeCount` を確かめる）→ タップ | `Paste result: items=1, failures=0`（受ける型に `public.image` がある。`ClipboardSampleView.swift:122`）。Clipboard v6 の 8.1 #19 | 両方（`clipboard`） | 自動* | 無し |

Clipboard v6 の 8.1 #20（対応外の型だけのとき）、#23〜#25、8.2 の M-06〜M-14 は今のまま自動化しない（2 台の端末、時刻の操作、Instruments が要る。Clipboard v6 9.3）。

### 3.6 件数

| 機能 | 新しいケース | テストのクラス |
|---|---|---|
| 共通（メニュー、識別子） | 6（M1、M2、I1a〜I1d） | `NavigationUITests`、`IdentifierInventoryUITests` |
| Dialog | 15（D1〜D15） | `DialogUITests` |
| Notification | 36（NP1、NP2、N1〜N34） | `NotificationPermissionUITests`（2）、`NotificationUITests`（23。N1〜N22 と N34）、`NotificationEventUITests`（7）、`NotificationColdStartUITests`（4） |
| Share | 16（S1〜S16） | `ShareUITests` |
| Clipboard | 4（CB1〜CB4） | `ClipboardPasteUITests`（CB1、CB3、CB4）、`ClipboardPasteDenyUITests`（CB2） |
| 計 | 77 | |

今の 25 件のうち、雛形の 3 件（`testExample`、`testLaunchPerformance`、`testLaunch`）は 0c で消す（6.1。レビュー v3 B-7）ので、残る Clipboard の 22 件と合わせて **99 件**。消す `testLaunch` は `runsForEachTargetApplicationUIConfiguration` で UI の構成ごとに展開されるものだったが、列挙では展開されず 1 件だった（0a 8 章）。雛形を消すので、展開の扱いは要らなくなった。

### 3.7 全ボタンが押されることの確かめ

`common.md` の「全ボタンが報告する」に当たる（レビュー v1 B-8、v2 B-14）。

- `SampleApp` は、そのテストで押したボタンの識別子を記録し、テストの終わり（`tearDown`）に、**名前 `ntk-button-coverage-v1.json`、中身は重複の無い文字列の JSON の配列**（例: `["dialog.button.showAlert"]`。押さなかったテストは `[]`）のテキストの添付（`XCTAttachment`、`lifetime = .keepAlways`。スクリーンショットではない）を、**ちょうど 1 つ**残す
- スクリプトは**シミュレーターの全件の実行**のときだけ、この添付を取り出す。`SampleApp` を使うクラスのテストで、添付が欠ける・2 つ以上ある・JSON の配列として読めない・重複がある、のどれかならそのクラスを失敗にする
- 全テストの添付の和集合を、5 章の一覧の Dialog・Notification・Share のボタン（0b で作る画面ごとの enum から数える）と照らし、押されていないボタンがあれば失敗にする
- **実機では添付を一切書き出さない**（6.3。レビュー v2 A-14）
- **Clipboard の画面は照らす対象から外す**。既存の 22 件は `SampleApp` を通らず自分の補助関数（`tapAndWait` など）で押すので記録が無く、記録に繋ぐには本体を書き換えることになる（U-10 で本体は変えないとした）。Clipboard の全ボタンを押すことは、既存の U13〜U20 の設計（`IosLibraryExampleUITests.swift` の U-13〜U-20 の注記「every button in the sample is executed at least once」）に任せる。これは機械で照らしていない残りとして記録する
- 添付を xcresult から取り出す方法は 0d の最初に確かめる（8.2）

## 4. 人の確認の手順書

`ios/IosLibraryExample/ComputerUse/HC-<番号>-<名前>.md` に 1 項目 1 ファイルで置く（U-19）。**判定があいまいなら失敗とする**。結果は段階の結果のファイルに、環境・日付・合否・見たものを書く。

スクリーンショットはシミュレーターのものだけを残してよい。実機は私物なので、撮るならサンプルの通知・画面の範囲だけに切り取り、ほかの通知・連絡先・ホーム画面が写ったものは残さない。実機で行う項目は、6.5 の確認を済ませてから行う。

| ID | 対象 | 環境 | 手順の要点 | 合格の条件 |
|---|---|---|---|---|
| HC1 | 通知の添付の画像（N5） | 両方 | ShowImmediateWithAttachment(AppIcon) → ホームでバナーを長押しして広げる | 広げた通知に画像が出ていて、それがサンプルの `app-icon-attachment.png`（アプリのアイコン）である。画像が無い、別の画像、判別できない大きさ → 失敗 |
| HC2 | （欠番）通知の音 | - | **対象外**（Android と同じ。どの手段でも確かめられない。U-19） | `NotificationContent` の `sound` の既定値 `.default` を単体テストで確かめる |
| HC3 | アイコンのバッジ（N34 で自動化できなかったときだけ） | 両方 | SetBadgeCount(1) → ホーム → SetBadgeCount(0) → ホーム | 1 のときアイコンに `1` が出て、0 のとき消える |
| HC4 | 通知センターからの起動と、消したときのイベント | 両方（区切りのときだけ。0g の後と 1b の後） | RegisterCategory → ShowImmediate → ホーム → バナーが消えるのを待つ → 通知センターを開く → サンプルの通知で起動する（実機はタップ、シミュレーターは右スワイプ。0a 7.2）→ 通知の画面の最後のイベントを見る。次に、もう一度通知を出し、通知センターで左へスワイプして「消去」 → アプリを開いて最後のイベントを見る | 起動の後 `actionId=com.apple.UNNotificationDefaultActionIdentifier`。消去の後 `actionId=com.apple.UNNotificationDismissActionIdentifier`（`customDismissAction`）。どちらも `notificationId=sample-notification`、`sequence` が 1 だけ増える |
| HC5 | コールドスタートの返信と Delete（N32・N33 が安定しなかったときだけ） | 両方 | N32・N33 の操作の後、ランチャーからアプリを開き、通知の画面を見る | 最後のイベントが N32・N33 の期待のとおり。イベントが無い場合は、プロセスが入れ替わったのかライブラリが落としたのかを区別できないので失敗とし、原因を調べる |
| HC6 | Share のプレビューの題（S5 で読めなかったときだけ） | 両方 | ShareURLWithPreview | シートが出た時点（1 秒以内）でヘッダーの題が `Apple`。`apple.com` が出てから変わる、読み込み中の表示が出る → 失敗 |
| HC7 | Share の画像の中身 | sim だけ（実機は私物の写真に保存することになる） | ShareImage → 画像を保存（`Save Image` / `画像を保存`。写真の権限のダイアログで許可）→ 写真の App で見る。ShareMultipleImages も同じ | 保存された画像がサンプルのアイコン。複数のときは 2 枚とも保存される |
| HC8 | ShareMultiple の中身 | sim だけ | ShareMultiple → Copy → 貼り付けられる受け手で確かめる | テキスト `Check this out` と URL `https://www.apple.com` の両方が渡る。**シミュレーターに入っている受け手で確かめられるかは未確認**。受け手が無ければこの項目は対象外にし、`ShareRepositoryImpl.buildActivityItems` の単体テストに任せる |
| HC9 | 複数のファイルの Save to Files（S9 を自動にできなかった環境だけ） | その環境 | ShareMultipleFiles → Save to Files →「このiPhone内」→ Save | 結果の行が ✅ `[shareMultipleFiles] completed=true, activityType=com.apple.DocumentManagerUICore.SaveToFiles` で、Files の「このiPhone内」に `share-sample-file-0.txt` と `share-sample-file-1.txt`（`ShareSampleView.swift:277`）の両方がある（同じ名前があれば「両方とも残す」の写し） |

## 5. 段階 0b で足す `accessibilityIdentifier`

U-17 の名前の付け方。識別子は `Button` そのものに付ける（C-1）。見た目は変えない（`accessibilityIdentifier` と結果の行の `accessibilityValue` は見た目に影響しない）。通知の画面の最後のイベント（5.2）は表示が増えるが、README の 0b の行に既に書いてある（0a R-1）。README に足す必要があるのは、結果の行の回数（U-3）だけ（8.3）。

### 5.1 一覧

| 画面 | 要素 | 識別子 |
|---|---|---|
| メニュー（`ContentView.swift:14-53`） | 4 つのカード | `menu.dialog`、`menu.notification`、`menu.share`、`menu.clipboard`（既存） |
| Dialog | 結果の行（`accessibilityValue` に `completion=<n>,callback=<n>`） | `dialog.result` |
| Dialog | ボタン 6 | `dialog.button.showAlert`、`dialog.button.showConfirmDialog`、`dialog.button.showDestructiveDialog`、`dialog.button.showActionSheet`、`dialog.button.showTextInputDialog`、`dialog.button.showLoginDialog` |
| Notification | 結果の行（`accessibilityValue` に `updates=<n>`） | `notification.result` |
| Notification | 節 7 | `notification.section.permission`、`.show`、`.updateCancelRemove`、`.schedule`、`.query`、`.badge`、`.category`（すべて `notification.section.` の後ろ） |
| Notification | Permission の 4 | `notification.button.requestPermission`、`notification.button.hasPermission`、`notification.button.authorizationStatus`、`notification.button.openNotificationSettings` |
| Notification | Show の 5 | `notification.button.showImmediate`、`notification.button.showImmediateWithAttachment`、`notification.button.showTimeInterval`、`notification.button.showCalendar`、`notification.button.showLocation` |
| Notification | Update / Cancel / Remove の 5 | `notification.button.updateById`、`notification.button.cancelById`、`notification.button.cancelAll`、`notification.button.removeDeliveredById`、`notification.button.removeAllDelivered` |
| Notification | Schedule の 5 | `notification.button.scheduleTimeInterval`、`notification.button.scheduleCalendar`、`notification.button.scheduleLocation`、`notification.button.cancelScheduledById`、`notification.button.cancelAllScheduled` |
| Notification | Query の 2 | `notification.button.getScheduled`、`notification.button.getDelivered` |
| Notification | Badge の 2 | `notification.button.setBadgeCount1`、`notification.button.setBadgeCount0` |
| Notification | Category の 2 | `notification.button.registerCategory`、`notification.button.removeCategory` |
| Notification | 最後のイベント 5 | `notification.lastEvent.sequence`、`notification.lastEvent.kind`、`notification.lastEvent.notificationId`、`notification.lastEvent.actionId`、`notification.lastEvent.userText` |
| Share | 結果の行（`accessibilityValue` に `updates=<n>`） | `share.result` |
| Share | 節 6 | `share.section.text`、`.url`、`.image`、`.file`、`.combination`、`.error`（すべて `share.section.` の後ろ） |
| Share | ボタン 14 | `share.button.shareText`、`shareURL`、`shareURLWithPreview`、`shareImage`、`shareMultipleImages`、`shareFile`、`shareMultipleFiles`、`shareMultiple`、`shareWithSubject`、`shareExcludingActivities`、`shareEmpty`、`shareInvalidURL`、`shareMissingFile`、`shareMissingImage`（すべて `share.button.` の後ろ） |
| Clipboard（既存） | 固定の 3 | `clipboard.result`、`clipboard.status`、`clipboard.pasteSummary`（`ClipboardSampleView.swift:11-13`） |
| Clipboard（既存） | 節 11 | `clipboard.section.` の後ろに `scope`、`copy`、`copyOptions`、`append`、`read`、`load`、`detect`、`observe`、`pasteControl`、`clear`、`errorCases`（`ClipboardSampleView.swift:221-634`） |
| Clipboard（既存） | ボタン 54 | `clipboard.button.` の後ろに、`ClipboardSampleIdentifiers.Action` の 52 個と `ControlAction` の 2 個（`cancelLoads`、`mountPasteControl`）（`ClipboardSampleView.swift:19-90`。`actionButton` の呼び出しも 54 で、重複は無い） |
| Clipboard（新規） | 貼り付けのコントロール | `clipboard.pasteControl`（CB3・CB4 のため。`ClipboardSampleIdentifiers` に足す。`UIViewRepresentable` に付けた識別子は外側のコンテナに付き、中の `UIPasteControl` に届かなかったので（0b の結果 3 章）、`makeUIView` で `UIPasteControl` に直接付けた。I1 では明示して除く） |

数: メニュー 4（うち新規 3）、Dialog 7（結果 1 + ボタン 6）、Notification 38（結果 1 + 節 7 + ボタン 25 + 最後のイベント 5）、Share 21（結果 1 + 節 6 + ボタン 14）、Clipboard 68（既存。固定 3 + 節 11 + ボタン 54）と新規 1。新規は計 70。I1a〜I1d は画面ごとにこの数と完全に一致することを確かめる。

`ClipboardSampleIdentifiers.Action` の注記は「50 entries」だが、実物は 52 個ある（`ClipboardSampleView.swift:18`）。既存の UI テストの注記（`IosLibraryExampleUITests.swift` の「50 result markers」）も同じ。I1d は実物の 52 で照らし、注記は段階 0 では直さない（8.5）。

### 5.2 最後のイベント（通知の画面）

| 項目 | 表示（ラベル） | 初め | 中身 |
|---|---|---|---|
| `notification.lastEvent.sequence` | `sequence=<n>` | `sequence=0` | 受けたイベントの数。1 つ受けるごとに 1 増える |
| `notification.lastEvent.kind` | `kind=<種類>` | `kind=none` | `action`（`onActionReceived`）か `textInput`（`onTextInputActionReceived`） |
| `notification.lastEvent.notificationId` | `notificationId=<id>` | `notificationId=-` | 受けた通知の id |
| `notification.lastEvent.actionId` | `actionId=<id>` | `actionId=-` | アクションの id（タップは `com.apple.UNNotificationDefaultActionIdentifier`） |
| `notification.lastEvent.userText` | `userText=<文字>` | `userText=-` | 返信の文字。`action` のときは `nil` |

- テストはラベルを完全一致で比べる（`kind=action` など。U-1）
- 置き場所: 通知の画面の結果の行のすぐ下（スクロールの外）。結果の行と同じく、スクロールせずに読める
- 入れ物（U-4）: アプリ全体で 1 つの `final class`（例: `NotificationEventLog.shared`）。中身（通し番号と最後のイベント）は `NSLock` か `Synchronization` の `Mutex`（最小 iOS 18 で使える。README D-15）で守り、`record(...)` は**呼ばれたスレッドで同期に**書いて戻る。`IosLibraryExampleApp.init` の 2 つの受け手（`IosLibraryExampleApp.swift:16-25`）は、`Log.d` を残したまま `record` を呼ぶ。`init` の中の順は、2 つの受け手を設定してから最後に `IosNotificationManager.setup()` を呼ぶ形に入れ替える（今は `setup()` が先。`IosLibraryExampleApp.swift:14`。レビュー v2 A-12）。`didReceive` は受け手の後に `completionHandler()` を呼ぶ（`IosNotificationManager.swift:343-351`）ので、`completionHandler` の前に保存が終わる
- 画面への知らせ（方式を 1 つに固定する。レビュー v2 C-12）: 画面用に `@MainActor final class NotificationEventViewModel: ObservableObject` を置き、`@Published private(set) var snapshot` に入れ物の今の値を持つ。通知の画面はこれを `@StateObject` で持ち、`onAppear` で入れ物から snapshot を取り直す。`record` は書いた後に `DispatchQueue.main.async` で知らせ（例: `NotificationCenter` の名前付きの通知）を送り、`NotificationEventViewModel` はそれを受けて snapshot を取り直す。知らせは「取り直せ」という合図だけで、値は運ばない（値はいつも入れ物から読む）。これで、画面ができる前に来たイベント（コールドスタート）も、画面を開いたときに出る
- 永続化しない（テストはプロセスごとに 0 から始める。U-15）。背景で起動されたプロセスが止められると消える（N32・N33 の未確認）
- 返信の文字は画面に出る。サンプルだけの表示で、テストの入力は秘密の値ではない。ライブラリのログの規則（README 8.6）とは別

## 6. テストの基盤（段階 0c）と実行（段階 0d）

### 6.1 基盤（`IosLibraryExampleUITests/Support/`）

実機の許可を守る本体は U-9 の 3 本柱（ランナーが選ぶこと、宣言の正しさの照合、利用者の許可）。ここの基盤のうち、閉じた形のソースの規則（下）は柱 2 の一部で、印と基底の確かめは二段目（宣言の誤りをシミュレーターの実行で見つける補助）。新しいテストのクラスは画面ごとのクラスを使い、springboard・ホーム・設定の App・Share のシート・ランナーからのクリップボードの読み書き・割り込みの監視を直接使うのは `Support/` だけにする。

| 足すもの | 役割 |
|---|---|
| `DeviceRequirements.json` | **宣言の表**（1 か所）。形は `{"schema": 1, "tests": {"<クラス>/<メソッド>": ["<区分>", ...], ...}}`。区分の無いテストは `[]`。キーと列挙・結果・`self.name` の対応は、0a 8 章で確かめた形に合わせた正規化の関数で取る: 列挙の identifier は `IosLibraryExampleUITests/<クラス>/<メソッド>()`、`.xcresult` の `nodeIdentifier` は `<クラス>/<メソッド>()`、`self.name` は `-[<クラス> <メソッド>]`。テストのターゲットのフォルダーはファイルシステムと同期するグループなので、JSON は置くだけでテストのバンドルに入り、`Bundle(for:)` で読める（0a 8 章）。ランナーはソースのファイルを読むので、**ビルドの後に、ソースとバンドルの中の写しのハッシュが一致することを照らす**（6.3 の 2。レビュー v3 C-6）。キーの重複は JSON として読めても失敗にする |
| `SampleUITestCase.swift` | 全テストのクラスの基底（**基底のファイル**）。setUp と tearDown の入口（`setUp()`、`setUp(completion:)`、`setUpWithError()`、`tearDown()`、`tearDown(completion:)`、`tearDownWithError()`）を `final override` にし、**async の形（`setUp() async throws`、`tearDown() async throws`）は上書きしない**（0c で、基底で async の形を上書きすると、`continueAfterFailure = false` の下で XCTest の中の失敗が起きるたびにランナーが落ちて起動し直した。`@MainActor` を付けても同じ。0c の作業の記録 2 章。子が async の形を上書きするとゲートより前に走るので、それは 6.1 の閉じた形の規則（`override` は決まった 2 つの口だけ）で止める）。`setUpWithError` と `tearDownWithError` から決まった口（子の `setUpAfterGate()` / `tearDownAfterGate()`）へ渡す。ほかの入口は `super` を呼ぶだけ。**`invokeTest` は上書きしない**（子は 6.1 の規則で上書きできない。レビュー v4 A-19）。`setUpWithError` で、`gatePassed = false` → `continueAfterFailure = false` → `self.name` を正規化（できなければ通常の `Error` を throw。レビュー v3 B-16）→ 表を引く（無ければ throw）→ 実機で宣言の区分が `NTK_DEVICE_ALLOW` に無ければ `XCTSkip("NTK-GATED:<区分>")` を throw → 縦向きにする（U-15）→ U-8 の監視を付ける（NP1・NP2・CB1・CB2 は「何も押さない」形）→ `gatePassed = true` → 子の `setUpAfterGate()`。`tearDownWithError` は、**`gatePassed` が true のときだけ**子の `tearDownAfterGate()` と片付けを呼ぶ（`setUpWithError` で `XCTSkip` を throw しても tearDown は走る。0a 8 章。レビュー v3 B-18）。区分ごとの印の型 6 つ（`SystemUIToken`、`ShareSheetToken`、`ClipboardToken`、`FilesToken`、`ReinstallToken`、`CredentialsToken`）は `internal`、**初期化子だけこのファイルの `fileprivate`**。印を得る口は基底の `internal` な区分ごとの 6 つの関数（`systemUIToken()` など。どれも `throws`。1 つの関数では 6 つの型を返せないため。レビュー v4 B-19）だけで、呼ばれるたびに `self.name`・表・`NTK_DEVICE_ALLOW` を引き直し、宣言していない・実機で許されていない・`gatePassed == false` のどれでも throw する（U-9） |
| `SampleApp` | `XCUIApplication` を private に持つ（テストのクラスは持たない）。起動、`menu.*` で画面を開く（Clipboard の画面は `ClipboardToken` が要る）、`<画面>.button.*` をスクロールして押す（Clipboard の `scrollStep` と同じ、慣性の無いドラッグ）。**印が要るボタンは、印を取る口だけで押せる**: `share.button.*`（`ShareSheetToken`）、通知を出すボタン Show* / Schedule* / UpdateById と `RequestPermission`・`OpenNotificationSettings`（`SystemUIToken`。レビュー v3 B-3）、ShowLoginDialog（`CredentialsToken`）。印の無い口にこれらの識別子を渡すと失敗する。`RegisterCategory`・`RemoveCategory`・`SetBadgeCount(1)`・`SetBadgeCount(0)`・`HasPermission`・`AuthorizationStatus`・`GetScheduled`・`GetDelivered`・取り消しと削除のボタンは印を要らない（サンプル自身の状態（category の定義、バッジの数、予約と表示中の一覧）を読み書きするだけで、システムの UI を出さず、私物の内容に触れない。バッジの数はホームのアイコンに出るが、テストの後に 0 に戻す。U-15）。結果の行の回数を読んで次の結果を待ち、全文を比べる（U-3）。押した識別子を記録する（3.7）。システムの UI を起こしうる操作の後に、アラートが残っていないことを数で確かめる口を持つ（U-8）。XCUI の操作の直後に U-8 の監視の印を読み、立っていれば通常の `Error` を throw する |
| `Springboard` | 初期化に `SystemUIToken` が要る。通知のバナーを 3.0 の条件と `.element` で探す、長押しで広げる、広げた通知の中で `Open` / `Delete` / `Reply` / `Send` を押す、返信の TextView に入力する、権限と貼り付けのダイアログを押す、ホームへ移る、設定の App の前面を待つ、アイコンのバッジを読む。**実機では階層のダンプを出さず、失敗の文に springboard のラベルを書かない** |
| `ShareSheet` | 開いたのを待つ、閉じる（版で分ける。U-16）、ヘッダーのドラッグ（`ShareSheetToken`）。Copy（`ShareSheetToken` と `ClipboardToken`）。Save to Files（`ShareSheetToken` と `FilesToken`。U-11 の手順）。実機ではセルのラベルを書かない（U-13） |
| `RunnerPasteboard` | `ClipboardToken` が要る。ランナーから一般のクリップボードに書く（CB1〜CB4） |
| `SystemLabels` | システムの UI の en / ja のラベルの表（U-2）: 許可 `Allow` / `許可`、拒否 `Don’t Allow` / `許可しない`、貼り付けの許可 `Allow Paste` / `ペーストを許可`、拒否 `Don’t Allow Paste` / `ペーストを許可しない`、`Not Now` / `今はしない`、`Copy` / `コピー`、`Save to Files` / `“ファイル”に保存` / `"ファイル"に保存`、`Save` / `保存`、`Close` / `閉じる`、`Cancel` / `キャンセル`、`Keep Both` / `両方とも残す`、`On My iPhone` / `このiPhone内`、`Browse` / `ブラウズ`（プローブの値。`’` は U+2019。`今はしない` / `Not Now` はプローブに無く、実機で確かめる。8.1） |
| `UnexpectedAlertGuard` | U-8 の監視。中では `XCTFail` を呼ばず、安全な操作・印の設定・`true` の返却だけを行う |
| `NotificationCleanup` | U-15 の 2 つの片付け: アプリの中（区分なし）と springboard（`gatePassed` が true で、そのテストで `SystemUIToken` を受け取ったときだけ） |

**既存のクラス**: 雛形の 2 クラス（`IosLibraryExampleUITests` の `testExample`・`testLaunchPerformance`、`IosLibraryExampleUITestsLaunchTests` の `testLaunch`）は 0c で消す。役目が無く、`testLaunch` は `runsForEachTargetApplicationUIConfiguration` で UI の構成（外観など）を切り替えて起動するので、私物の端末の設定に触れうる（`IosLibraryExampleUITestsLaunchTests.swift:12-14`。レビュー v3 B-7）。残る既存のクラスは `ClipboardUITests` だけで、基底を `SampleUITestCase` に替え、setUp と tearDown を `setUpAfterGate()` / `tearDownAfterGate()` に書き換える。本体は `app` を直接使う形のまま残るので、二段目の印の口は及ばず、一段目（クラスの下限と、名前の一覧とハッシュの固定）で守る（U-10）。

**閉じた形のソースの規則**（U-9 の柱 2 の④。許す形だけを決め、ほかを禁じる。レビュー v4 の「仕組みの直し（2）」1）: `test_ios.sh` は、テストのターゲットのフォルダーのすべての `.swift` について次を確かめ、1 つでも外れれば止まる（シミュレーターでも）。ソースは Swift の構文で読む（`swift-syntax` などの構文の木。文字列の grep では `#if` や継承の書き方の違いを取りこぼすため。読み方は 0d の最初に決める。8.2）。

| 規則 | 内容 |
|---|---|
| クラス | 信頼する部分の外のファイル（テストのクラスのファイル）のクラスは、どれも `final class <名前>: SampleUITestCase` だけ。`final` でないクラス、`SampleUITestCase` のほかのクラス（`XCTestCase` や、ほかのテストのクラス）を継承するクラスは禁じる。`extension` で既存のテストのクラスにメソッドを足すことも禁じる（レビュー v4 A-1v4）。`Support/` の補助は struct / enum にする。class が要るなら信頼する部分の中だけで、そこでも基底のほかに `XCTestCase` の系統のクラスは作らない（レビュー v5 C-14） |
| テストのメソッドの形 | テストのメソッドは `func test<名前>()` と `func test<名前>() throws`（同期）だけ（属性 `@MainActor` は許す）。`async` のテストは禁じる。6.3 の 4 で、実機のバイナリの selector（`test<名前>` と `test<名前>AndReturnError:`）を `test<名前>()` に正規化して照らすため（レビュー v5 A-22） |
| 失敗を期待する口 | `XCTExpectFailure` を禁じる（結果に Expected Failure が出たら失敗にする。6.3。レビュー v5 B-23） |
| `override` | 基底のファイルの外では、`setUpAfterGate()` と `tearDownAfterGate()` の 2 つだけ（レビュー v4 A-18） |
| `class func` / `static` の上書き | 基底のファイルの外では、`class func`・`class var`・`static` の `override` を禁じる（`class func setUp()` / `tearDown()`、`defaultTestSuite` などの入口を塞ぐ）。上書きでない `static func`（今の `ClipboardUITests` の `parseSequence` など）は許す |
| `#if` | テストのターゲットのすべてのファイルで禁じる（実機とシミュレーターでテストの集合や中身が変わるのを防ぐ。シミュレーターか実機かの分岐は、基底のファイルの 1 か所だけで `#if targetEnvironment(simulator)` を許し、ほかでは基底の `isDevice` を読む。レビュー v4 A-20） |
| `import` | `XCTest` と `Foundation` だけ（`import Testing` も禁じる。Swift Testing のテストは列挙と名指しの形が違うため）。`Support/` の決まったファイルは、要るなら `UIKit` も許す |
| 危ない型の名前 | `XCUIApplication`、`XCUIDevice`、`UIPasteboard`、`addUIInterruptionMonitor` は、`Support/` の決まったファイル（`SampleApp.swift`、`Springboard.swift`、`ShareSheet.swift`、`RunnerPasteboard.swift`、`UnexpectedAlertGuard.swift`、`SampleUITestCase.swift`）の中だけ。例外は、ハッシュで固定した `IosLibraryExampleUITests.swift`（`ClipboardUITests`）の中の今の出現（`XCUIApplication` が 2 回、`XCUIDevice` が 1 回。雛形を消した後の数）だけで、ファイル・回数で照らす |
| 識別子の文字列 | 信頼する部分の外で、`"share.button.`・`"menu.`・`"clipboard.` などの識別子の文字列を書かない。例外は、ハッシュで固定した `IosLibraryExampleUITests.swift` の中の `ClipboardID` の範囲全体（雛形を消した後の 16〜24 行。`"menu.clipboard"`、`"clipboard.result"` など。ファイルをハッシュで固定するので、範囲を広げても中身は変わらない。レビュー v5 C-13） |
| バンドルを読み込んだ時点で走るもの | `NSPrincipalClass`（ソースと、テストのターゲットの Info.plist と build setting）、`XCTestObservationCenter`、`+load` を禁じる。テストのターゲットのフォルダーに `.m` / `.c` / `.mm` を置かせない |

今の `ClipboardUITests` は 0c で `final class ClipboardUITests: SampleUITestCase` に替え、setUp と tearDown を決まった口に書き換えた後の中身でハッシュを固定する。この規則から外れる形に戻すと、規則とハッシュの両方で止まる。

### 6.2 待ち時間（U-14）

| 待つもの | 0a の実測 | 待ち時間 |
|---|---|---|
| アプリの起動、画面、結果の行 | - | 10 秒 |
| Dialog の表示 | - | 5 秒 |
| 権限のダイアログ | 約 1.1 秒（両方のシミュレーターと実機） | 10 秒 |
| 前面のバナー | 約 1.1 秒、実機 1.2 秒 | 10 秒 |
| 5 秒の予約の背景のバナー | ホームの 4.5 秒後、実機 4.7 秒後 | 20 秒 |
| 10 秒の予約 | 10.1〜11.2 秒、実機 10.3 秒 | 25 秒 |
| +1 分のカレンダー | 測っていない | 90 秒 |
| アクションのボタン（1.5 秒の長押しの後） | - | 5 秒 |
| コールドスタートで前面に来る | 26.2 約 3.1 秒、18.3 0.7〜0.8 秒、実機 1.3 秒 | 15 秒 |
| Share のシート（Copy の出現） | 約 1.1 秒 | 10 秒 |
| Files のピッカー | - | 10 秒 |
| 貼り付けの許可のダイアログ | - | 10 秒 |
| 取り消し・削除の反映（U-6） | - | 10 秒（0.5 秒おき） |
| 「出ない」「来ない」ことの確かめ（固定） | - | U-14 の例外のとおり |

1 件の時間は、Dialog と Share が 9〜16 秒、権限が 10〜13 秒、通知が 26〜57 秒（0a 4 章）。既存の Clipboard の 22 件だけで 51〜53 分（0a 3.7）。全体の時間は 0d で測って README 7 章に書く。見積もり（未確認）: 新しい 77 件で 40〜60 分、全体で 1 時間半前後。category のテストを 5 秒の予約に替えた分、通知は少し長くなる。

### 6.3 `scripts/test_ios.sh`（段階 0d）

Android の `scripts/test_android.sh` の形に合わせる。**実機で流すテストはこのスクリプトが決める**（U-9 の一段目）。

| オプション | 内容 |
|---|---|
| `--udid <id>` | 対象。必須。**`xcrun simctl list -j devices` にある UDID だけをシミュレーターとし、それ以外はすべて実機として扱う**（fail-closed。レビュー v3 B-5）。実機は xcodebuild が受け付けるハードウェアの UDID（`<実機のハードウェアの UDID>`。0a 7.1） |
| `--enumerate-udid <id>` | 実機のときは必須。列挙に使うシミュレーターの UDID（`simctl list` にあることを確かめる）。実機では列挙しない（下の 2） |
| `--devicectl-id <id>` | 実機だけ。アプリの削除（`xcrun devicectl device uninstall app --device <id> ...`）と端末の情報の取得に使う devicectl の識別子（`<実機の devicectl の識別子>`）。xcodebuild はこの識別子を受け付けず、devicectl がハードウェアの UDID を受け付けるかは分からない（0a 7.1、8.2）ので、2 つを別に受ける |
| `--feature <Dialog\|Notification\|Share\|Clipboard>` | UI テストを、その機能のクラスに絞る（`UI_CLASSES` の表。共通の `NavigationUITests` と `IdentifierInventoryUITests` はいつも入れる）。単体テストは流さない。`feature-scoped-testing` の「機能の名前で絞る口」の iOS の分 |
| `--skip-unit` | 単体テストを飛ばす |
| `--device-allow <区分,...>` | 実機で許す区分（U-9 の 6 つ）。既定は空。流すテストの選び方に使い、あわせて `TEST_RUNNER_NTK_DEVICE_ALLOW=<区分,...> xcodebuild ...` の形で環境変数としてランナーに渡す（二段目のため）。シミュレーターでは受け付けず、`TEST_RUNNER_NTK_DEVICE_ALLOW` と `NTK_DEVICE_ALLOW` を環境から消してから xcodebuild を呼ぶ（外から受け継いだ値で二段目が変わらないように） |
| `--dry-run` | **実機に触れない**（実機のためのビルド、devicectl、xcodebuild の実機の宛先を使わない）。`--enumerate-udid` のシミュレーターで 2 の照合を行い、宣言の表と `--device-allow` から、流すテストと除くテストの一覧（テストの名前と宣言の区分）を表示し、**許可を求める一覧のファイル**（流すテストの identifier の配列、`--device-allow`、`git rev-parse HEAD`、テストのフォルダーのハッシュ）を書いて止まる（レビュー v3 A-15、B-6）。一覧のファイルには、`--dry-run` ごとにランダムな許可の ID と、信頼する部分のハッシュが固定した値と同じかを入れ、違えば「信頼する部分が変わった」と表示する（そのときは実機で流せない）。エージェントはこの一覧を利用者に見せて許可を得る（U-9 の柱 3） |
| `--approved <file>` | 実機で流すときは必須（`--dry-run` のときは使わない）。利用者が許可した一覧のファイル。3 で、今の選び方の結果・`--device-allow`・コミット・フォルダーのハッシュがこのファイルとちょうど同じでなければ流さない。**実機に触れる前に**、一覧の許可の ID を消費済みの台帳（リポジトリの外の決まった場所。例: `~/Library/Application Support/native-toolkit/test_ios-approvals.log`）に記録する。台帳にある ID は拒む（同じ許可で 2 回流せない。失敗の後の流し直しにも、新しい `--dry-run` と許可が要る。レビュー v5 A-24）。流した後、結果の集合がこの一覧とちょうど同じかを照らす（レビュー v4 の「仕組みの直し（2）」3） |
| `--baseline` | 結果を基準として保存する。全件（`--feature` と `--skip-unit` なし）で、失敗が無いときだけ。D-21 の 2 つの環境（機種と OS の版で照らす）のほかでは受け付けない（18.3 のシミュレーターは基準にしない。U-16）。実機では、許した区分を基準に記録する（`allowed`）。利用者が許さなかった区分のテストは基準に入らず、そのことを表示する |

順に行うこと:

0. 対象を確かめる（上の `--udid` の決め方）。機種・OS の版とビルド番号・表示の言語・Xcode の版を記録する（実機は `--dry-run` でないときだけ）。基準のビルド番号と違えば警告する（基準を取り直す合図。README D-21）。シミュレーターが en でない、実機が ja でないときも警告する。6.1 の閉じた形のソースの規則を照らし、外れれば止まる（U-9 の柱 2 の④。シミュレーターでも）
1. 単体テスト（`IosLibraryTests`、`IosLibraryExampleTests`）。**シミュレーターのときだけ**流す。実機を対象にしたときは流さない（`--feature`・`--skip-unit`・`--dry-run` のときも流さない）。今の単体テストは、クリップボードを `UIPasteboard.withUniqueName()` で扱い一般のクリップボードに触れず（`ClipboardRepositoryImplTests.swift:5,16`）、`IosClipboardManagerTests` は一般のクリップボードの変更の通知を投げるだけで中身を書かず（同 `:85` など）、通知と Share はモックの repository を使う（`Notification/Application/Mock/`、`Share/Application/Mock/`）ので、実機で流しても私物に触れない見込みだが、一段目の外にあるので実機では流さない（レビュー v3 B-4、「仕組みの直し」7）。`UnityIosPluginTests` は流さない（D-22）
2. **列挙と照合**（シミュレーターで行う）: `--enumerate-udid`（シミュレーターのときは `--udid`）のシミュレーターに向けて `xcodebuild build-for-testing` を行い、**その直後に** `xcodebuild test-without-building -xctestrun <...> -destination <そのシミュレーター> -enumerate-tests -test-enumeration-style flat -test-enumeration-format json -test-enumeration-output-path <file>` で全テストを導く。0a 8 章のとおり、出力は `values[].enabledTests[].identifier` で、`-only-testing` を付けても単体テストを含む全件が出るので、`IosLibraryExampleUITests/` で始まるものだけを取る。メソッドを持たない基底クラスも `<ターゲット>/<クラス>` の 1 件として出るので、`/` が 2 つでないものは除く（除くクラスの名前は `SampleUITestCase` だけと決め、ほかが出たら止まる）。シミュレーターの列挙は端末を起動しなかった（0a 8 章）。実機は試していないので、**実機では列挙しない**。実機の実行は、同じ作業ツリーから作ったこのシミュレーターの列挙を使う（列挙のファイルに、`git rev-parse HEAD` とテストのターゲットのフォルダーの中身のハッシュを記録し、実機のビルドの直前に同じであることを照らす。レビュー v3 A-15、「仕組みの直し」3）。次のどれかなら止まる（シミュレーターでも）:
   - 列挙のテストの集合（正規化した `<クラス>/<メソッド>`）と、宣言の表のキーの集合が一致しない
   - 列挙のクラスの集合と、`UI_CLASSES` と別の段で流す 2 クラス（`NotificationPermissionUITests`、`ClipboardPasteDenyUITests`）の集合が一致しない
   - 表の区分の名前が 6 つのどれでもない、キーが重複している
   - **クラスごとの宣言の下限**（U-9 の②）を満たさないテストがある（レビュー v3 の「仕組みの直し」1）
   - `ClipboardUITests` のメソッドの名前の一覧が固定した 22 件と違う、または `IosLibraryExampleUITests.swift` の中身のハッシュが固定した値と違う（U-9 の③。ハッシュは 0c の終わりに、雛形を消し基底を替えた後の中身で決める）
   - 固定した 22 のメソッドの名前のどれかが、`ClipboardUITests` のほかのクラスの下に出る（継承や `extension` で写したとき。レビュー v4 A-1v4）
   - 列挙の identifier の配列に重複がある（集合にする前に、配列の件数と一意の件数を比べる。レビュー v4 B-20）
   - ソースの `Support/DeviceRequirements.json` と、ビルドしたテストのバンドルの中の写しのハッシュが違う（レビュー v3 C-6）
   - 信頼する部分（2 章の冒頭）のファイルのハッシュが、ランナーに固定した値と違う（シミュレーターでは警告だけにして流す。実機では流さない。レビュー v5 A-23）
3. **流すテストを決める**（一段目）: シミュレーターでは全テスト。実機では、宣言の区分がすべて `--device-allow` に含まれるテストだけ。区分で除いたテストの一覧を結果に書く。`--dry-run` はここで一覧を表示し、許可を求める一覧のファイルを書いて止まる。実機で流すときは、選んだ結果を `--approved` のファイルと照らし、ちょうど同じでなければ止まる（柱 3）
4. 実機のときは、まず一時フォルダー（`mktemp -d`。実機の `.xcresult` を置く）を作り、**その直後、最初の実機の xcodebuild より前に** trap を登録する（`EXIT` で一時フォルダーを消す。`INT` / `TERM` / `HUP` では、対応する終了コード（130 / 143 / 129）で `exit` して `EXIT` の trap を走らせる。消せなかったときは場所を表示する。レビュー v4 A-21）。次に、実機に向けて `build-for-testing`（`-allowProvisioningUpdates`）を行う（2 の作業ツリーのハッシュを照らしてから）。**その後、実機のビルドの `.xctest` のテストの一覧を、端末で起動せずにバイナリから読み**（`otool -ov` で Objective-C のメタデータのクラスとメソッドの selector を読む。`func testU1_...() throws` は `testU1_...AndReturnError:` の selector で現れる（Xcode 26.3 で確かめた。レビュー v5 A-22）。テストのメソッドの形は 6.1 で `func test...()` と `func test...() throws` に限っているので、selector の `test<名前>` と `test<名前>AndReturnError:` をどちらも `test<名前>()` に正規化する。正規化は純粋な関数にし、実物の `otool -ov` の出力を写した fixture で単体テストを書く）、2 のシミュレーターの列挙と同じ集合でなければ止まる（`#if` などで実機にだけあるテスト・無いテストを捕まえる。U-9 の柱 2 の⑤。レビュー v4 A-20）
5. **権限の段**（U-7、U-18）: 権限のクラスは `UI_CLASSES` に入れず、ここでメソッドごとに名指しして流す。シミュレーターでは `simctl uninstall` → NP2 → `simctl uninstall` → NP1。実機では、3 で選ばれたとき（`reinstall` と `systemui` を許したとき）だけ、`devicectl` で同じ順に行う。どちらも、1 件ずつ名指しして流し、結果がその 1 件ちょうどであることを照らす（6 と同じ照合。レビュー v4 B-21）。この段は、`--feature` を付けないときと `--feature Notification` のときだけ行う
6. `UI_CLASSES` のクラスごとに流す。シミュレーターは `-only-testing:IosLibraryExampleUITests/<クラス>`。**実機は、3 で選ばれたテストの列挙の identifier をそのまま `-only-testing:` に 1 件ずつ名指しする**（加工して組み立て直さない。レビュー v3 B-15）。どちらも `TEST_RUNNER_NTK_DEVICE_ALLOW`（実機だけ）を付けて `xcodebuild test-without-building -xctestrun <...> -parallel-testing-enabled NO -resultBundlePath <bundle>`。1 つのクラスが落ちても残りを流す（ただし下の名指しの照合で止まったときは、実機の実行全体を止める）。時間切れはクラスごと（Clipboard は 75 分、ほかは 30 分）。**実機の名指しの照合**（レビュー v3 A-17、B-1、「仕組みの直し」4）:
   - 呼ぶ直前に、名指しが 1 つ以上あることを確かめる。0 件のクラスは呼ばない（`-only-testing` を 1 つも渡さずに呼ぶと全件が流れるので、名指しが空のまま xcodebuild を組み立てる経路を作らない）
   - 流した後、結果のテストの配列（`nodeIdentifier` を正規化したもの）が、名指しとちょうど同じであることを照らす。集合にする前に配列の件数と一意の件数を比べ（重複を消さないため。レビュー v4 B-20）、欠ける・多い・重なるのどれかなら、**実機の実行全体を止める**（存在しない名指しは黙って無視され exit 0 になる。0a 8 章）。あわせて、許可した一覧（`--approved`）の和とも照らす
   - **シミュレーターでも同じ照合をかける**: クラスを名指ししたときは、結果の配列が、2 の列挙のそのクラスのテストとちょうど同じであること（レビュー v4 B-21）
7. **CB2 の段**（U-12）: `ClipboardPasteDenyUITests` を独立した呼び出しで流す。`--feature` を付けないときと `--feature Clipboard` のときだけ行う（レビュー v3 C-3）。実機は 3 で選ばれたときだけ、名指しの照合も同じに行う。0c の確かめでアプリの削除が要ると分かったら、CB2 のクラスの下限に `reinstall` を足し、削除の前に、`reinstall` が `--device-allow` と許可した一覧に入っていることを**直接**確かめてから削除する（入っていなければ削除も CB2 もしない。レビュー v4 B-22）。結果の照合は 6 と同じ
8. 結果を読む（下）。**実機の `.xcresult` は、4 で作った一時フォルダーに置き、4 で登録した trap で消す**（レビュー v3 B-8、v4 A-21）。実機の `.xcresult` からは添付を一切書き出さず、`get test-results tests` と `get test-results summary` の JSON だけを読む（0a 7.4）。シミュレーターでは、3.7 の添付を取り出す
9. 結果の一覧を表示し、基準とテストごとに比べる。シミュレーターの全件なら 3.7 の照合を行う。`--baseline` なら保存する。実機で流した後は、残したもの（Files の写しの数、クリップボードにテストの文字列があること、category が登録されたまま、キーボードが学習した語がありうること）を表示する

**結果の読み方**: `xcrun xcresulttool get test-results tests --path <bundle>`（JSON）でテストごとの結果（`Passed` / `Failed` / `Skipped` / `Expected Failure`）と `nodeIdentifier`（`<クラス>/<メソッド>()`）を読み、`get test-results summary` で数を照らす。skip の理由は、テストの節の子の `nodeType: "Failure Message"` の `name`（`Test skipped - <理由>`）にある（0a 8 章）。次のときはそのクラスを失敗にする: xcodebuild が 0 以外で終わり結果が無い、テストが 0 件、時間切れ。skip の理由で分ける:

| skip の理由 | 扱い |
|---|---|
| `NTK-GATED:` を含む | 二段目の確かめが一段目の選び方と食い違った（ランナーか表の誤り）。**失敗** |
| （skip でなく）結果が Expected Failure | **失敗**（`XCTExpectFailure` は 6.1 で禁じている。レビュー v5 B-23） |
| `NTK-PRECONDITION:` を含む | 前提が満たされない（実機で通知の権限が未決定など。3.0）。**失敗**として数え、基準と比べるときも失敗 |
| **意図した skip の一覧**にあるもの（テストのキーと理由の前方一致の組。今は `ClipboardUITests/testU10b_namedPasteboardAfterProcessTermination` と理由 `M-08 could not be decided here`、`ClipboardUITests/testU21_isolatedFixturesForWholeContentPatterns` と理由 `whole-content detection patterns were not all reported`。`IosLibraryExampleUITests.swift:356-363,624-630`） | `skipped` として基準に記録する |
| それ以外の skip | **失敗**（いつも skip するテストが確かめないまま成功と報告されるのを防ぐ。レビュー v4 A-4v4） |

ランナーが 3 で除いたテストは、起動していないので結果に無い。これを「区分で除いた」として数える。

**基準のファイル**: `scripts/test_ios.baseline.<機種>-<OS の版>.json`。機種名の空白は `_` にする。例: `scripts/test_ios.baseline.iPhone_XS-18.7.2.json`、`scripts/test_ios.baseline.iPhone_17-26.2.json`（Android の `test_android.baseline.<機種>-<API>.json` に合わせる）。中身:

| キー | 中身 |
|---|---|
| `model`、`os`、`osBuild`、`language`、`xcode` | 環境（`osBuild` は Android の fingerprint の役） |
| `allowed` | 基準を取ったときに許した区分（シミュレーターは 6 つすべて） |
| `counts` | ターゲットごと（`IosLibraryTests`、`IosLibraryExampleTests`、`IosLibraryExampleUITests`。実機の基準は単体テストを流さないので UI テストだけ）。UI テストは機能ごと（`Common`、`Dialog`、`Notification`、`Share`、`Clipboard`）に分ける（README 0d。雛形は消すので無い） |
| `results` | `<ターゲット>/<クラス>/<テスト>` → `passed` / `failed` / `skipped` |

**基準との比べ方**: 結果が変わったテスト、増えたテスト、無くなったテストを表示する。基準で通っていたテストが、今回 skip か未実行になったら失敗（Android と同じ）。ただし `--feature` で外したもの、ランナーが区分で除いたもの（権限の段と CB2 の段を飛ばしたものを含む）は失敗にしない。`NTK-PRECONDITION:` の skip は失敗にする。

**純粋な関数と自己テスト**: 次は、スクリプトの中の純粋な関数（Python）に切り出し、`scripts/tests/` に単体テストを置く（`common.md` の「判定規則そのものが対象なら、規則を純関数に切り出して直接壊す」。7 章の変異はこれらを壊す）: シミュレーターか実機かの判定、列挙の JSON の読み取りと正規化（列挙・`nodeIdentifier`・`self.name` の 3 つの形）、表と列挙の照合、クラスの下限の照合、流すテストの選び方、名指しの引数の組み立て（空なら組み立てない）、結果と名指しの照合（配列の件数と一意の件数を含む）、許可した一覧との照合（許可の ID と台帳を含む）、実機のバイナリのテストの一覧の読み取りと selector の正規化（`otool -ov` の実物を写した fixture）、skip と Expected Failure の分類（意図した skip の一覧）、信頼する部分のハッシュの照合。正規化と照合の単体テストは、0a 8 章で得た実際の JSON を写した fixture で行う（レビュー v3 B-15）。

結果のフォルダーは `ios/IosLibraryExample/build/test_ios/<日時>-<機種>-<OS>/`（コミットしない。実機の `.xcresult` はここに置かない）。

### 6.4 実機の環境の扱い

- 実機は利用者の私物（README D-21）。流すたびに、6.5 の確認を済ませ、許す区分を利用者に決めてもらう
- 決めた区分で `test_ios.sh --udid <実機> --enumerate-udid <シミュレーター> --dry-run --device-allow <区分>` を流し（実機には触れない）、**流すテストの名前と区分の一覧**を利用者に見せ、許可を得る。許可を得た一覧のファイルを `--approved` に渡して流す。ランナーは、今の選び方と許可した一覧がちょうど同じでなければ流さず、流した後に結果が許可した一覧とちょうど同じかを照らす（U-9 の柱 3。6.3）。**これを毎回行う**（前回の許可を使い回さない）
- 実機の `.xcresult` は、結果を書き写したら消す（0a 7.4 の利用者の決定）

### 6.5 実機で流す前の確認

エージェントは、実機で流す前に、次を利用者に知らせ、尋ねる事柄には答えをもらう。終わったら、戻してもらう設定を知らせる（README 7.2）。

**知らせること**:

| 事柄 | 内容 |
|---|---|
| 自動ロックと給電 | 流す間、「設定 → 画面表示と明るさ → 自動ロック」を「なし」にし、電源につないでおく（README 7.2。こちらからは変えない）。終わったら戻してもらう |
| サンプルとランナーの入れ直し | 毎回、今のコードで組んだサンプル（`com.jonghyunkim.ios.nativetoolkit.example`）とテストのランナーを上書きで入れる。`reinstall` を許すと、サンプルを削除して入れ直す（サンプルのデータが消える） |
| クリップボード（`clipboard`） | 一般のクリップボードがテストの文字列で上書きされ、元の内容は戻らない。**Universal Clipboard で、同じ Apple ID のほかの端末（Mac など）のクリップボードも上書きされうる**（U-10。レビュー v1 A-9） |
| **Handoff を切ること（`clipboard` を許す前提）** | `clipboard` を許すときは、流す間、Handoff（「設定 → 一般 → AirPlay と連係」）を切ってもらう。切ってもらえないときは `clipboard` を許さない（尋ねる事柄ではなく、許す条件。U-10。レビュー v4 A-3v4）。ほかの端末の内容が来ると、ほかの端末のクリップボードもテストの文字列で上書きされ、サンプルがほかの端末の内容を読みうる。ランナーは `changeCount` の確かめでも捕まえるが、それに頼らない。終わったら戻してもらう |
| Files（`files`） | 「このiPhone内」に `share-sample.txt`（と複数のファイルの写し）が、流すたびに増える（「両方とも残す」のため） |
| ログイン（`credentials`） | ログインのダイアログ（D11〜D13、D15）に `taro` / `secret1` を入れる。iOS がパスワードの保存や AutoFill を示すかは確かめていない（8.1）。**確かめるまで `credentials` は許さないでもらい、確かめは利用者が見ている前で手で行う**（レビュー v2 B-N4）。保存を示されても押さない |
| キーボードの学習 | テストが入力した語（`Taro 太郎`、`abc`、`taro`、`secret1`、`hello reply`、`cold reply`）を、キーボードが予測の候補として学習しうる |
| 画面に出るもの | 通知のバナー、Share のシート（連絡先と実在のアプリ）、設定の App が画面に出る。テストは押さず、ログにも書かない。`.xcresult` は書き写した後に消す |
| バッジと category | テストの後、サンプルのバッジは 0、category `sample-category` は登録されたまま（0a の後と同じ） |

**尋ねること**（こちらから利用者に尋ねる）:

| 事柄 | 尋ねる内容 | 理由 |
|---|---|---|
| 集中モード | **決定（2026-10-24、利用者）: 実機で流す間は、利用者が自分で集中モードを入れ、サンプル（IosLibraryExample）の通知だけを許す**（実機の 2 回目で、私物の通知かシステムの割り込みで M2 が落ちたため。0d の作業の記録 13 章）。流す前の知らせで毎回頼む | 集中モードで通知が止まると、バナーのテストが失敗する。私物の通知のバナーが押す対象に重なるのも防げる（レビュー v1 B-4） |
| 通知の表示の設定 | 「設定 → 通知 → プレビューを表示」が「しない」になっていないか。サンプルのバナーのスタイルが「持続的」でなく「一時的」か。「時刻指定要約」にサンプルが入っていないか | プレビューが「しない」だと本文がバナーのラベルに出ず、3.0 の判定が崩れる。持続的だとバナーが消えず次のテストに残る。要約に入るとバナーが出ない |
| システムの自動更新 | 基準を取り終えるまで、iOS の自動更新を切るか | 版が変わると基準を取り直す（README D-21） |

## 7. 変異で確かめること（`common.md` の「検査の書き方」）

テストを足したら、守る対象を壊して落ちることを確かめる。**変異はシミュレーターだけで流す**（私物の端末で壊れたコードを動かさない。レビュー v1 C-9）。実機の選び方（一段目）は、`--dry-run` とスクリプトの純粋な関数の単体テスト（6.3）で、端末をつながずに確かめる。壊すのはテストを流す間だけで、確かめたら戻す。結果は 0c・0d の結果のファイルに書く。 守りの本体（U-9 の 3 本柱）の変異と、二段目（補助）の変異を分けて書く。二段目だけで捕まる変異が捕まらなくても、それは区分 B として扱う（レビュー v4 の「仕組みの直し（2）」4）。

| グループ | 壊すもの | 落ちるはずのもの |
|---|---|---|
| Dialog | `IosDialogManager.showConfirmDialog` の確認のボタンが `onCancel` を呼ぶようにする | D2（D3 は取り消しのボタンが今のまま `onCancel` を呼ぶので落ちない） |
| Dialog | `showTextInputDialog` の `confirmAction.isEnabled = enableConfirmWhenEmpty` を消す | D8 |
| Dialog | `showDialog` の提示の completion で `completion` を 2 回呼ぶ（形を変える変異） | D1、D14（`completion` の増分が 2） |
| Dialog | `showAlert` の OK のハンドラで `onButton` を 2 回呼び、`completion` を呼ばない（合計の回数は変わらない変異） | D1、D14（種類ごとの回数で落ちる。合計だけなら通ってしまう形） |
| Dialog | `showLoginDialog` の Login のハンドラで `onLogin` を 2 回呼ぶ | D15 |
| Dialog | `showActionSheet` の取り消しが `onAction(nil, ...)` を返す | D7 |
| Notification | `foregroundPresentationOptions` を `[]` にする | N4、N26 |
| Notification | サンプルの `IosLibraryExampleApp.init` での 2 つの受け手の登録を、通知の画面の `onAppear` に移す（受け手が起動の後に登録される形） | N30、N31（コールドスタートで、画面ができる前に来たイベントを受けられない） |
| Notification | `IosNotificationManager.setup()` をアプリの起動から外し、通知の画面の `onAppear` で呼ぶ | N30・N31 が落ちるかを記録する（iOS が起動のきっかけの応答を delegate が入った後に渡すことがあり、落ちる保証が無い。レビュー v1 B-6）。落ちなかったら、そのことを 0c の結果に書く |
| Notification | 最後のイベントの入れ物で、`record` が main に積むだけで同期に書かない形にする | N32・N33 が落ちるかを記録する（背景で止められる時期に依存するので、落ちる保証が無い） |
| Notification | `didReceive` で `UNTextInputNotificationResponse` を見分けず、すべて `onActionReceived` に渡す | N29 |
| Notification | `didReceive` で `actionIdentifier` の代わりに通知の id を渡す | N25、N27、N28 |
| Notification | `cancel(identifier:)`、`removeDelivered(identifier:)` を何もしない形にする | N11、N14 |
| Notification | `update` で、渡された id の予約を消した後、別の id（例: id の後ろに `-updated`）で足す | N9。`update` は `removePendingNotificationRequests(withIdentifiers: [identifier])` で予約を消してから足すので、`5s Notification` の予約は残らない。落ちる理由は、表示中の通知の id が `sample-notification` でなくなること（`[getDelivered] count: 1, ids: [sample-notification]` が合わない。レビュー v2 C-N3）。「`update` で予約を消さない」変異は、同じ id で足すと OS が置き換えるので生き残る（レビュー v1 A-7）ので使わない |
| Notification | `registerCategory` で `setNotificationCategories` を呼ばない | N23（先に RemoveCategory で消えたことを観測してから、登録の後に出ることを見るので落ちる） |
| Notification | サンプルの `ScheduleTimeInterval` を 30 秒にする | N16（時間切れ） |
| Share | サンプルの `ShareExcludingActivities` の除外を `[]` にする | S12 |
| Share | `ShareRepositoryImpl.makeURL` の scheme の確かめを外す | S14 |
| Share | `ShareSheetPresenter` で `completed` をいつも `true` で返す | S2、S3 |
| Share | `ShareError.noValidItems` の文言を変える | S13 |
| Clipboard 追加 | サンプルの `onPaste` で `pastedSummary` を変えない | CB3 |
| Clipboard 追加 | 読み込みの失敗を成功として表示する | CB2 |
| 識別子 | 識別子を付けないボタンを 1 つ足す。識別子を付けるヘルパーを 1 つ挟んで、一覧に無い識別子を持つボタンを足す（間接参照を挟む変異）。同じ識別子を 2 つのボタンに付ける | その画面の I1a〜I1d（3 つとも） |
| 全ボタン | 1 つのボタンを押すテストを外す | 3.7 の照合 |
| 全ボタン | 1 つのテストの添付を 2 つにする。壊れた JSON にする | 3.7 のクラスの失敗 |
| 柱 1（選び方） | スクリプトの選ぶ関数で、宣言の区分のうち 1 つだけが許されていれば選ぶ形にする（「すべて」を「どれか」にする） | `scripts/tests/` の単体テスト。`--dry-run --device-allow systemui` の一覧に、`sharesheet` も要る S1 が入ることでも分かる |
| 柱 2（照合） | 宣言の表から 1 つのテストを消す。表に存在しないテストのキーを足す。区分の名前を綴り違いにする | 6.3 の 2 の照合で止まる（シミュレーターでも） |
| 柱 2（照合） | テストのクラスを 1 つ足して `UI_CLASSES` に書かない | 6.3 の 2 の照合で止まる |
| 柱 2（下限） | `ClipboardUITests` に、宣言を `[]` にしたテストを 1 つ足す | 6.3 の 2 で止まる（クラスの下限 `clipboard` を満たさない。名前の一覧とハッシュの固定でも止まる）。レビュー v3 A-1 |
| 柱 2（固定） | `IosLibraryExampleUITests.swift`（`ClipboardUITests`）の本体を 1 行変える | 6.3 の 2 のハッシュの照合で止まる |
| 柱 2（写し） | ビルドの後に、バンドルの中の `DeviceRequirements.json` だけを書き換える | 6.3 の 2 のハッシュの照合で止まる（レビュー v3 C-6） |
| 柱 1（名指し） | 名指しの引数を組み立てる関数が、選ばれたテストが 0 件のときに空の一覧で xcodebuild を呼ぶ形にする | `scripts/tests/` の単体テスト（0 件なら組み立てずに止まる）。レビュー v3 B-1 |
| 柱 1（名指し） | 実機の段で、テストでなくクラスを `-only-testing` に渡す形にする。名指しの 1 つを存在しない名前に変える | `scripts/tests/` の単体テストと、結果と名指しの照合（結果に出ない名指しがあるので止まる。存在しない名指しは黙って無視されるため、照合が無いと通ってしまう。0a 8 章、レビュー v3 A-17） |
| 柱 1（判定） | シミュレーターか実機かの判定を、「`simctl list` に無ければシミュレーター」にする（fail-open） | `scripts/tests/` の単体テスト（知らない UDID を実機として扱う）。レビュー v3 B-5 |
| 柱 1（列挙） | 実機を対象にしたときに、実機を宛先にして列挙する形にする | `scripts/tests/` の単体テスト（列挙の宛先はいつも `simctl list` にある UDID）。`--dry-run` で実機に触れないことも、端末をつながずに確かめる |
| 二段目（補助） | N25 の宣言から `systemui` を消す（表の照合と下限は通る形。`NotificationEventUITests` の下限は `systemui` なので、この変異は下限で止まる。下限の無い `NotificationUITests` の N4 で行う） | N4 がシミュレーターで落ちる（`systemUIToken()` が throw する。U-9） |
| 二段目（補助） | 子のクラスが `setUpWithError` か `setUp()` を override する（評価を外す形） | ビルドが通らない（基底のものは `final`）。`invokeTest` は基底が上書きしないので `final` でなく、子の上書きは柱 2 の閉じた形の規則で止まる（上の行）。レビュー v2 A-N1、v4 A-19 |
| 柱 2（閉じた形の規則） | 子のクラスに `override class func setUp()`、`override func tearDown()`、`override func invokeTest()` のどれかを足す | 6.1 の閉じた形の規則で止まる（`override` は決まった 2 つの口だけ。レビュー v4 A-18・A-19） |
| 二段目（補助） | 基底の表を引く処理で、表に無いときに `XCTFail` だけをして続ける形にする | 宣言の表から 1 つを消すと 6.3 の 2 で止まるので、この変異は表を変えずに、正規化の関数がそのテストだけ別の名前を返す形で作る。シミュレーターでそのテストが印を得て操作を続けることで分かり、throw する形に戻すと落ちる |
| 二段目（補助） | `setUpWithError` で `XCTSkip` を throw した後の `tearDownWithError` で、`gatePassed` を見ずにアプリを起動する片付けを呼ぶ形にする | シミュレーターで `NTK_DEVICE_ALLOW` を空にした実機のふりの確かめ（`#if targetEnvironment(simulator)` を一時的に外したビルド）で、skip したテストの後にアプリが起動することで分かる。`gatePassed` で守る形に戻すと起動しない（レビュー v3 B-18） |
| 柱 2（閉じた形の規則） | テストの中で `XCUIApplication.init(bundleIdentifier: "com.apple.springboard")`、`XCUIDevice.shared.press(.home)`、`UIPasteboard.general`、`"share.button.shareText"` を直接書く。既存の U10a の `press(.home)` の行を 1 つ増やす。`NSPrincipalClass` を足す。テストのフォルダーに `.m` を置く。`import Testing` を足す | 6.1 の閉じた形の規則で止まる（型の名前・識別子の文字列・`import`・ファイルの種類） |
| 柱 2（閉じた形の規則） | `class Foo: ClipboardUITests {}` を足す（22 件を継承して流す形）。`final` を外したテストのクラスを足す。`extension ClipboardUITests` にテストを足す | 6.1 のクラスの規則で止まる。あわせて 6.3 の 2 で、固定した 22 の名前が `ClipboardUITests` のほかのクラスの下に出ることでも止まる（レビュー v4 A-1v4） |
| 柱 2（閉じた形の規則と実機のバイナリ） | 新しいテストのクラスに `#if !targetEnvironment(simulator)` で囲んだテストを足す | 6.1 の `#if` の規則で止まる。規則を一時的に外しても、6.3 の 4 の実機のバイナリの一覧がシミュレーターの列挙と一致しないので止まる（これはシミュレーターと実機のビルドを読むだけで、端末を使わない。レビュー v4 A-20） |
| 柱 1（終わりの片付け） | trap の登録を、最初の実機の xcodebuild の後に移す。`HUP` を trap から外す | `scripts/tests/` の単体テスト（trap を登録してから実機の xcodebuild を呼ぶ順と、`INT` / `TERM` / `HUP` での `exit`）。レビュー v4 A-21 |
| 柱 3（利用者の許可） | `--approved` の一覧から 1 件を消す。`--device-allow` を許可のときと変える | 6.3 の 3 で、今の選び方と許可した一覧が違うので止まる（`--dry-run` と同じく端末を使わずに確かめる） |
| 信頼する部分 | `SampleApp.swift` に、印を取らずに `share.button.*` を押す関数を足す | 6.3 の 2 の信頼する部分のハッシュの照合で、実機では流さず、`--dry-run` の一覧に「信頼する部分が変わった」と出る（レビュー v5 A-23） |
| 柱 3（利用者の許可） | 一度使った `--approved` のファイルで、もう一度流す | 許可の ID が台帳にあるので、実機に触れる前に拒む（レビュー v5 A-24。台帳の場所を一時フォルダーにして、端末を使わずに確かめる） |
| 柱 2（実機のバイナリ） | selector の正規化で `AndReturnError:` を落とさない形にする | `otool -ov` の実物の fixture での単体テスト（`throws` のテストが一覧に合わない）。レビュー v5 A-22 |
| 柱 2（閉じた形の規則） | テストに `XCTExpectFailure` を足す。`async` のテストを足す | 6.1 の規則で止まる（レビュー v5 B-23、A-22） |
| 結果の読み方 | 意図した skip の一覧に無いテスト（例: D1）に `XCTSkip` を足す | 6.3 の skip の分類で失敗になる（レビュー v4 A-4v4） |
| 結果の読み方 | 結果の配列に同じテストを 2 回入れた fixture を与える | 照合の関数が、配列の件数と一意の件数の違いで止まる（レビュー v4 B-20） |
| 割り込みの監視 | 監視の規則を「否定のボタンがあればどのアラートでも押す」に戻し、シミュレーターでサンプルの名前の入らないアラート（別の試験用のアプリが出すもの）を出す | 押さずに terminate して印を立てる形に戻すと、そのアラートに答えない。戻す前の形では答えてしまうことで分かる（レビュー v4 A-2v4） |
| 割り込みの監視 | 監視を外さないテストで `RequestPermission` を押し、シミュレーターでアプリを削除した直後に流す | 黙って許可されず、監視が「許可しない」を押して失敗を記録する（U-8） |

## 8. 未決のことと後回しにすること

### 8.1 0c の最初に確かめること（未確認）

2026-10-18（レビュー v5 の後）に見直した。実機で確かめる項目は、6.5 の確認を済ませ、利用者の許可を得てから行う。結果は 0c の結果のファイルに書き、この表から外す。

| 項目 | 関わるケース |
|---|---|
| 実機のバナーのラベルの区切り（`IosLibraryExample, ` で始まり、`, ` で錨を打てるか） | 通知のすべて |
| 広げたサンプルの通知を表す要素（アクションのボタンの範囲の根、「広げた」ことの印）が両方の OS にあるか | N23、N24、N27〜N29、N31〜N33 |
| 位置の予約の登録の結果（位置の権限なし、利用目的の文言なし） | N8、N18 |
| 表示済みの同じ id を更新したときの件数 | N10 |
| 同じバンドルのファイルを 2 回添付できるか | N5 |
| 前面のバナーのタップでイベントが来るか | N26 |
| 背景で起動されたプロセスが `activate` まで残るか | N32、N33 |
| 設定の App の前面の判定 | N3 |
| カレンダーの +1 分の発火の時間 | N7 |
| ホームのアイコンのバッジを読めるか | N34、HC3 |
| Dialog が出ている間に、後ろの結果の行を読めるか（iOS 26.2 のシミュレーターでは読めた。0b の結果 3 章。実機を確かめる） | D1、D2、D6 |
| 遅延でない `VStack` の画面の外のボタンが、スクロールせずに 1 回の snapshot に入るか（画面ごとに件数を測る。入らなければ位置ごとの和集合にする。3.1） | I1a〜I1d |
| Share のプレビューの題を要素として読めるか | S5 |
| 複数の画像・ファイルの Copy と Save to Files（成功の経路） | S6、S9、S10、HC9 |
| 貼り付けの許可のダイアログが出る条件（アプリを止める・別の xcodebuild で流す・アプリを削除する、のどれで初めに戻るか）。シミュレーターと実機の両方 | CB2（U-12） |
| 画像だけの貼り付け | CB4 |
| ログインのダイアログで、実機の「パスワードを保存」の確認や AutoFill の候補（私物の資格情報）が出るか。出るなら、アラートか、シートか（アラートでなければ U-8 の監視の (a) に来ない）、`今はしない` / `Not Now` のラベル。**利用者が見ている前で、利用者の許可を得て手で確かめる**（自動では確かめない）。確かめるまで `credentials` は許さない（レビュー v2 B-N4） | D11〜D13、D15（実機） |
| 通知のバナーが割り込みの監視に来るか。監視のハンドラの中で `app.terminate()` を呼んで `true` を返し、包む関数が印を読んで throw する形で、その後のテストが止まるか（シミュレーターでわざとアラートを出して確かめる） | U-8、N4〜N34（レビュー v2 A-11・B-N3、v3 B-17） |
| springboard の要素を明示して待って押す操作（権限と貼り付けのダイアログ）が、割り込みの監視を起こさないこと（「何も押さない」監視を付けた NP1・NP2・CB1・CB2 が、期待するダイアログで terminate しないこと） | NP1、NP2、CB1、CB2（レビュー v5 A-1v5） |
| category の登録と削除の `Task` が、5 秒の予約の通知が出るまでに終わるか（観測で区切っても、削除の後の「無い」側は 5 秒の余裕に頼る） | N23、N24（レビュー v2 B-N7） |
| 写真とローカルネットワークの権限のダイアログが、割り込みの監視に来るか | U-8 |
| 通知の権限と貼り付けのダイアログのラベルに、サンプルの表示名 `IosLibraryExample` が入るか（監視が押してよいかの判定に使う。en と ja の両方） | U-8（レビュー v4 A-2v4） |
| ほかの端末（Universal Clipboard）の内容が来たとき、端末の `UIPasteboard.general.changeCount` が上がるか。Handoff を切った状態では来ないこと（利用者の許可を得て、利用者の端末どうしで確かめる。確かめられなければ `changeCount` の確かめは補助とし、Handoff を切る前提に頼る） | CB1、CB3、CB4（レビュー v4 A-3v4） |
| 返信の入力で実機の予測の候補に私物の語が出ないか（スクリーンショットの扱い） | N29、N32 |

### 8.2 0d の最初に確かめること（未確認）

0a の 8 章で、次は事実として分かったので、ここから外した: 列挙の形（`<ターゲット>/<クラス>/<メソッド>()`、基底クラスも 1 件で出る、単体テストも出る、シミュレーターは起動しない）、列挙の identifier を `-only-testing` にそのまま渡せること、存在しない名指しは黙って無視され exit 0、`self.name` の形（`-[<クラス> <メソッド>]`）、`.xcresult` の `nodeIdentifier` の形（`<クラス>/<メソッド>()`）と skip の理由の場所（子の `Failure Message` の `name`）、`final override func setUpWithError()` が通ること、`XCTSkip` の後も `tearDownWithError` が走ること、JSON が同期するグループでバンドルに入り `Bundle(for:)` で読めること。どれもシミュレーター（iPhone 17、iOS 26.2）で確かめたもので、実機では確かめていない。実機では列挙しない（6.3 の 2）ので、列挙の実機での振る舞いは確かめる必要が無くなった。

- `TEST_RUNNER_` の環境変数が、`test-without-building -xctestrun` で実機のランナーに届くか（オプションそのものは手元の man page で確かめた。実機での動きは未確認）
- テキストの添付を xcresult から取り出す方法（`xcresulttool export attachments` など）（3.7）
- 実機のビルドの `.xctest` の `otool -ov` で、`throws` でないテスト（`func test...()`）が `test...` の selector で出ること、`@MainActor` を付けたテストも同じに出ること、`XCTestCase` を継承したクラスの見分け方（`throws` のテストが `test...AndReturnError:` で出ることは Xcode 26.3 で確かめた。レビュー v5 A-22）。fixture にする実物の出力を取る（6.3 の 4）
- 閉じた形のソースの規則を、Swift の構文の木で読む方法（`swift-syntax` を使う小さな道具を `scripts/` に置くか、ほかの方法か。6.1）
- 選ばれなかったクラスの `class func setUp` と `init` が、`-only-testing` で別のクラスを名指ししたときに走らないこと（シミュレーターでログを出して確かめる。レビュー v3 B-2）
- 実機で、メソッドを 1 件ずつ名指しした多くの `-only-testing` を 1 回の呼び出しに渡せるか（引数の数の上限。だめならクラスを分けて呼ぶ）
- devicectl がハードウェアの UDID を受け付けるか（受け付けるなら `--devicectl-id` を省ける）
- 許可の ID の消費済みの台帳の置き場所（リポジトリの外。例の `~/Library/Application Support/native-toolkit/` でよいか）と、台帳を書いた後に実機の実行が途中で止まったときの扱い（ID は消費済みのまま。流し直しは新しい許可）（6.3。レビュー v5 A-24）
- 信頼する部分のハッシュの固定の形（ファイルごとか全体か）と、更新の手順（別のモデルのレビューの結果のファイルを指す）（2 章の冒頭、6.3 の 2。レビュー v5 A-23）
- 実機の `.xcresult` に撮られるスクリーンショットを減らす設定（テストプランの `systemAttachmentLifetime` に当たるもの）が、テストプランを使わない形で使えるか。使えなくても、結果を書き写したら消す運用は変えない

### 8.3 README に反映すること（この設計を決めた後）

この文書は README を変えていない。利用者が U-1〜U-19 を決めたら、README 5.1 の「決めたらその場で直す」に従い、次を直す:

- 5 章の 0b の行: 最後のイベントの表示は既に書いてある。**結果の行の回数（U-3。`accessibilityValue` で、見た目は変わらない）を足すことを書き足す**。あわせて、サンプルの起動の処理で受け手を設定してから `setup()` を呼ぶ順に入れ替えること（U-4。サンプルだけの変更）も書く
- 7 章のサンプルの UI テストの件数（25 件 → 99 件。雛形の 3 件を消すので、7 章の「Clipboard 22 件、雛形 3 件」の内訳も直す）と、全体の実行の時間（0d で測った値）
- 7.2 の「`common.md` の例外として理由を 0a の結果に書く」の対象（2.1 の表）
- 9 章の DoD の「通知からのコールドスタートを含む」に、N30〜N33 を対応させる

### 8.4 後回しにすること

- 通知センターの経路の自動化（U-5）。区切りのときに HC4 で確かめる
- 更新のテスト（1.13.0 のサンプルから 2.0.0 へ。README 7 章）。この文書の範囲外で、1b の後に別に設計する
- iPad、位置の発火、件名、`openSettingsFor`
- ライブラリの単体テストを機能で絞ること（`feature-scoped-testing`）
- iOS の CI（README 8.4）

### 8.5 サンプルとライブラリで気になった動作（段階 0 では直さない）

| 動作 | 扱い |
|---|---|
| Dialog のログインの結果の行にパスワードが平文で出る（`DialogSampleView.swift:157-159`） | 今の動作のまま期待値（D12）。1b のログの規則と合わせて扱う（README 1.4、8.6） |
| Notification の画面の RequestPermission は、失敗の理由に関わらず「denied. Permission dialog will not appear again.」と出す（`errorMessage` を捨てる。`NotificationSampleView.swift:32-42`） | 今の動作のまま期待値（NP2） |
| `NotificationError` が `LocalizedError` に従わず、エラーの文言が OS の言語の汎用の文になる（`NotificationError.swift:9-27`） | 3.3 の対象外の表。1b のエラーの直し（README 4 章）で扱う |
| 取り消し・削除・category の操作は結果の行が先に出て、処理は後で終わる（`cancel`・`removeDelivered`・`registerCategory`・`removeCategory` が `Task` で非同期。`IosNotificationManager.swift:179-231,306-316`。README 1.4） | U-6 のとおり反映を待つ。category は確かめる口が無いので、N23・N24 は 5 秒の予約の通知を使う |
| `cancel` と `cancelScheduled`、`cancelAll` と `cancelAllScheduled` が同じ処理（README 1.4） | 今の動作のまま期待値（N12、N20） |
| ShowActionSheet は、ルートの ViewController が取れないと何も表示しない（`if let` の else が無い。`DialogSampleView.swift:96-114`） | サンプルの画面からは起こせないので対象外 |
| ShowImmediateWithAttachment は、添付の画像が見つからないと黙って添付の無い通知を出す（`NotificationSampleView.swift:409-411`） | 3.3 の対象外の表。HC1 で添付を確かめる |
| 位置の予約のボタンは、サンプルが位置の権限を求めないので発火しない見込み（未確認） | N8・N18 は登録まで |
| サンプルの起動の処理は、`setup()` で delegate を入れてから受け手を設定している（`IosLibraryExampleApp.swift:14-25`） | 0b で順を入れ替える（U-4。レビュー v2 A-12） |
| `ClipboardSampleIdentifiers.Action` と既存の UI テストの注記は「50」だが、実物は 52 | 5.1。I1d は実物で照らす |
| テストのターゲットの最小 iOS が 18.2（本体は 18.0。pbxproj） | 試験の環境（18.7.2、26.2、18.3.1）では影響しない。0e で直す（README 5 章） |

### 8.6 段階 0c で実装に合わせたこと

0c の実装と実測で、この文書と違う形にしたもの。詳しくは `results/2026-10-18-ios-c-abi-stage0c-working-notes.md` の 2 章と 7.4。

| 所 | 実装 |
|---|---|
| 基底の入口（6.1） | async の形（`setUp() async throws` / `tearDown() async throws`）は上書きしない。上書きするとランナーが落ちた。子の上書きは閉じた形の規則で止める |
| 最後のイベントの `userText`（3.3） | テキストの無いアクションでは `-` と表示する（今のサンプルの動作） |
| N6 | 発火の前の `count: 1` の確かめは N7 に任せる（ボタンが離れていて 5 秒以内に読めない） |
| N13・N20 | 5 秒・10 秒の予約ではなく +1 分のカレンダーを使い、取り消す前に 2 件あることを読む |
| N11・N19 | 窓が終わった後に GetDelivered が空であることも確かめる |
| CB2（U-12） | 貼り付けの許可のダイアログは、ランナーが新しい内容を書くたびに出るので、アプリの削除（`reinstall`）は要らない。宣言しない |
| Share（S 系） | 開いた印に `ActivityListView`、Copy はセルだけ、Save は Files のピッカーが落ち着いてから押す |
| springboard のアラートの数（6.1、U-9） | `SampleApp.remainingAlertCount` は、印を取らずに springboard のアラートの数だけを読む。何も押さずラベルも読まないので、信頼する部分の中の読むだけの例外として認める（2026-10-19） |
| 0d のランナー（6.3） | xcodebuild の後はシミュレーターが Shutdown なので、`simctl uninstall` の前に `simctl bootstatus -b` で起動する |

### 8.7 段階 0d で実装に合わせたこと

0d のランナーの実装と実測で、この文書と違う形にしたもの。詳しくは `results/2026-10-24-ios-c-abi-stage0d-working-notes.md` の 3 章と 5 章（実機の最初の実行で分かったことは 12 章）。

| 所 | 実装 |
|---|---|
| `UI_CLASSES`（6.3、3.6） | `NavigationUITests`（M1、M2）は 0c で書かれていなかったので、0d で足した（`UI_CLASSES` の先頭、Common。区分はどちらも `[]`）。全体は 3.6 のとおり 99 件。M2 の `HasPermission` は権限の状態を読むだけで、区分の無いテストは権限を前提にしない（3.0）ので、結果の行は `[hasPermission] true` と `false` のどちらかの全文と比べる |
| 閉じた形の規則の読み方（6.1、8.2） | swift-syntax ではなく、Python で字句に分けて照らす（コメントと文字列を外し、文字列の補間の中は照らす）。属性と `#` の名前も許すものだけにした |
| 実機のバイナリの一覧（6.3 の 4） | テストのバンドルの `otool -ov` は相対のメソッドの一覧に selector を出さないので、`otool -l` の `__objc_selrefs` の番地から引く |
| 信頼する部分のハッシュ（2 章、8.2） | ファイルごとに `scripts/ios_ui_runner.py` に固定した（コミット `8fdb429d` の中身。レビュー v1 の R-1〜R-5 で `Springboard`・`SampleUITestCase`・`NotificationCleanup`・`SystemLabels` を直し、値を更新した） |
| 段の順（6.3 の 0〜4） | 実機の環境（devicectl）は許可を消費して trap を登録した後に読む。単体テストはシミュレーターのビルドの後に流す |
| 添付の取り出し（3.7、8.2） | `xcresulttool export attachments`。名前は `ntk-button-coverage-v1_0_<UUID>.json` になる |
| 返信の欄と Send（6.1 `Springboard`。レビュー v1 R-1、v2 R-21） | 広げた通知の根の外の別の window にある（26.2 のシミュレーターで測った）。根がちょうど 1 つで、その広げた表示がサンプルの題と本文であることを、アクションを押す前・入力の前・Send の前に取り直して確かめる。window は、サンプルにしか無い返信の placeholder（`IosLibraryExample reply`）の欄（入力の後は入力した文字の欄）をちょうど 1 つ持つものに限る。placeholder を変えるため、サンプルの `NotificationSampleView.swift` の 1 か所だけを変えた（0c の「サンプルは変えない」の例外。0b の結果の 5 章）。springboard 全体に戻る道は無い |
| CB1 の Allow Paste（3.5。レビュー v1 R-3） | ラベルの `“…”` の引用がちょうど 2 つで、1 つ目がサンプル、2 つ目（出どころ）がランナー（`IosLibraryExampleUITests-Runner`。26.2 のシミュレーター、en）かサンプル自身（実機、ja。0a 7.2）のときだけ押す（`Springboard.pasteAlertNamesKnownSource`）。Mac の名前などほかの出どころ（Universal Clipboard）、引用の数の違いでは押さずに失敗する |
| 許可（6.3。レビュー v1 R-6〜R-9） | 台帳はアカウントのホームの決まった場所だけ（環境変数と `$HOME` では動かない）。行の形を照らし、壊れていれば実機を拒む。許可の一覧は区分・順・除いたもの・知らないキーまで丸ごと比べる。`ios/` にコミットしていない変更（`build/` を除く）があれば実機を拒む |
| シミュレーターの名指し（6.3 の 6。レビュー v1 R-17） | `--name-each-test` で、実機と同じく 1 件ずつ名指しして流せる |
| 実機の前の照合（6.3。レビュー v2 R-18〜R-20） | 実機では、`scripts/ios_ui_runner.py` と `scripts/test_ios.sh` もコミット済みで、計画を作ったときと同じであることを求める（2 つの SHA-256 を計画と許可の一覧に入れる）。許可の一覧には計画全体の正規化した SHA-256 を入れ、許可を使った後は読むだけの計画の写しだけを使い、実機のどの呼び出しの前にも（`device_guard` → `device-gate`）計画・台帳・ランナー・木を照らす。xcresult の Test Case の子は `Failure Message` だけを許し、ほかの種類があれば止める |
| I1 のナビゲーションバー（3.1。実機の最初の実行） | 戻るボタンの identifier は、iOS 26.2 のシミュレーターでは `BackButton`、iOS 18（実機 18.7.2、シミュレーター 18.3.1）では空で、ラベルは前の画面の題 `Main Menu`（サンプルの文字で、言語で変わらない。18.3.1 の ja のシミュレーターで確かめた）。I1 は、ナビゲーションバーのボタンがちょうど 1 つで、それが `BackButton`、または identifier が空でラベルが `Main Menu` であることを求める（ほかのボタンがあれば失敗）。ラベルを読むために、信頼する部分の `SampleApp.inventorySnapshot` がナビゲーションバーのボタンの identifier とラベルを返す形にした（ハッシュを更新した。Codex（`gpt-5.6-sol`）に変わった所を見てもらい、サンプル自身のナビゲーションバーを読むだけで何も押さないこと、ラベルを失敗の文に書かないこと、ハッシュが一致することを確かめた。0d の作業の記録 12.8 の前の確かめ）。失敗の文には identifier だけを書き、ラベルは書かない |
| xcodebuild の DerivedData と結果のバンドル（6.3。実機の最初の実行、その直しの確認 A-1・A-2） | `-version` のほかの xcodebuild の呼び出しは、`-derivedDataPath` を（テストの呼び出しは `-resultBundlePath` も）ちょうど 1 回、`-option <値>` の 2 つの引数の形で渡す。値は、シミュレーターではその実行の出力のフォルダーの中、実機では実機の一時フォルダー（trap が消す）の中だけ。シミュレーターのビルドもその実行のフォルダーで組む（前の実行のビルドは使い回さない）。実機のビルドも一時フォルダーで組む。`sim_xcodebuild` と `device_xcodebuild` は、無い・2 回以上・値が無い・`=` の形やほかの綴り・外を指す・`.`／`..`／空の段・どの段かに symlink がある（壊れた symlink を含む）・実体のパス（`pwd -P`）と違う値を 97 で拒む。それまでは、列挙の xcresult が Xcode の既定の DerivedData にできていた |
| 実機の言語（U-16、6.3。実機の最初の実行） | `devicectl device info details` の JSON に言語が無いので、実機の環境の言語は `unknown` になり、`Warning: the device's language is unknown, not ja (U-16)` が出る（警告だけで止めない）。devicectl のほかから言語を読む方法は確かめていない |

