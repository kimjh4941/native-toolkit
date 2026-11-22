# レビュー結果

- 日付: 2026-11-22
- 対象: `artifact/topics/macos-c-abi/` の企画の初版（コミット前）。`README.md`、`plans/2026-11-22-macos-c-abi-{plan,decisions,dod}.md`、根拠の調査
- トピック名: macos-c-abi（企画）
- 判定: **要修正**（区分 A が残るので、企画を直して再レビューする）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行。互いの結果は見せていない。照らす先が違うため 2 者にした: Claude は実物との照合と iOS の決定との食い違い、Codex は macOS・署名・Unity の外からの見方）
- 機械照合: 対象外（`check_design_consistency.py` は設計書用）

区分: A = このまま進むと後の成果物の動作・API・契約が変わる、B = 検証の手段が変わる、C = 記述の整合だけ。「出典」は指摘したレビュアー。番号は両者の番号をまとめ直したもの（R は統合後の番号）。

## 件数

| 区分 | Claude | Codex | 統合後 |
|---|---|---|---|
| A | 1 | 6 | 6（1 件は両方が挙げた） |
| B | 7 | 6 | 13 |
| C | 10 | 3 | 12（1 件は両方が挙げた） |

## 強み（両者）

- 推奨の根拠の事実の大半が実物と合う（44 関数、C# の 44 本と JSON の層 1,946 行、symlink が無く `codesign` が失敗、埋め込みの `MacLibrary` が別のビルド、署名・bundle id・Swift 5・`LastUpgradeCheck`）（Claude）
- 0 章で、macOS にしか無い落とし穴（版付きのヘッダー、Library Validation、`PlugIns` の rpath、bundle の無いプロセス）を試作で先に踏んでいる（Claude）
- 機能のロジックを `MacLibrary` に集める境界、44 関数に加えてイベント・登録・解除を照らす方針、2 つの framework と公開シンボルの制約、2c をリリースの条件にしている点（Codex）
- D-1 の A（写して照合で守る）は、出し済みの iOS 2.0.0 を動かさない判断として合理的（両方）
- 私物の一般の貼り付け板を退避・復元しない方針と、Developer ID と公証を確かめないことを DoD に明示した点（Codex）

## 事実の照合で分かった誤り（Claude）

| 主張 | 結果 |
|---|---|
| 「`-capi-` の名前を足すと capi の側が選ばれる」 | 今の名前では起きない。前方一致は `unity-mac-native-toolkit-` で、`mac-native-toolkit-capi-` に当たらない。今起きるのは、新しい `dist/<版>` が 1 つでもできると `FindLatestVersionInDist` がそれを選び、`unity-mac-*` が無いのでエラーのログを出して古い 1.3.0 のまま進むこと（こちらで `grep` して確かめた）。capi を選ぶ罠は、2c で前方一致を `mac-native-toolkit-` に変えたときに起きる |
| 「`PreBuildProcessor` は `-debug` の戻りを持つ」 | 正しいが、`PostBuildProcessor` は development で `-debug` が無いと埋め込まずに戻り、`MacFrameworkPatcher` は debug を区別しない。頼むことの 3 は「確かめる」でなく「直す」 |
| 「`MacLibraryTests` 308 件（展開後）」 | 308 は `@Test` の宣言の数で、`arguments:` の展開前。75・52 も同じ |
| 「テストのターゲットだけ最小 macOS が 15.1」 | 15.1 は 3 つのプロジェクトのプロジェクトの階層の設定で、テストと UI テストのターゲットが継いでいる |
| 「`generate_docc.sh` が `mac/Build` を消す」 | 消すのは `mac/Build/MacLibrary` と `mac/Build/UnityMacPlugin`（ビルドのスクリプトの archive と同じ場所なのは正しい） |

## 区分 A

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| RA-1 | 両方（Claude A-1、Codex A-1） | Dialog の `runModal` を `DispatchQueue.main.async` のブロックの中で呼ぶと、入れ子の run loop の間 main キューが捌かれない見込みがある（libdispatch は main キューの再帰的な drain を抑える）。そうなら Dialog が開いている間、C ABI の全機能の完了・イベント・`release`（`Task { @MainActor }` を含む）が止まり、main に積む形の `ntk_dialog_cancel` も届かない。`stopModal` / `abortModal` は要求を区別せず、ホストのモーダルを閉じうる。企画は逆向き（「走りうる」）にだけ書いていた。直すと macOS の `MainQueue.swift` が iOS と違う中身になりうるが、D-1 の A に差を許す口が無い | 企画 1.4 の記述を両方向の未確認に直した。1a-6 を「どの積み方なら走るか（GCD の中・外から入った場合、`CFRunLoopPerformBlock`、`perform(…inModes:)`）、別のスレッドからの取り消しが届くか、別の要求の取り消しが今の Dialog を閉じないか、ホストのモーダルを閉じないか、Unity のループが止まるか」に広げた。D-8 に A'（GCD のブロックの外から `runModal` に入る）と modal session を足し、**推奨を「1a-6 の結果で 0e の前に決める」に変えた**（成り立たなければ sheet も含めて 2.0.0 の前に決め直す）。D-1 に OS ごとに中身が違うファイルを表で許す口を足した。D-5・D-6 に、取り消しと完了の届き方が D-8 に依存することを書いた |
| RA-2 | Codex A-2 | Share が mouseDown の文脈を要ると分かった場合の出口が未決のまま。いつも main に積む形では呼び手が条件を満たせない | D-6 に「表示を始める同期性と、完了を非同期で返す契約は分けて決められる」と書き、1a-7 で成り立たないときは「main の実のイベントの中から同期に表示を始める入口」「条件に反したときのエラー」「基点の指定」を第 1 部で決め直すと明記した。1a-7 にキーボード操作と Unity の `Update` からの呼び出しを足した |
| RA-3 | Codex A-3 | iOS の起動のきっかけの判定は、custom action が前面をもたらすかも見ている。`NSApp.isActive` に置き換えるだけでは同じ意味にならない（macOS の inactive は background ではない） | 1a-8 を、本文のクリック・前面の custom action・後ろの action とテキスト入力・普通に起動した後の最初のクリック、に分けて測る形にした。D-7 と 8.6 に「イベントの配送と起動のきっかけの分類を分け、分類のために応答を失わない」を書いた |
| RA-4 | Codex A-4 | sandbox のホストで、パネルで選んだファイルを C / C# が後から読めるかが、パスの文字列の設計から抜けている。Share の非同期の間に誰がアクセスの権利を持つか | 8.6 に「パネルの結果と Share のファイルの、sandbox のアクセスの権利（security scope）、使える期間、終える責任、再起動の後」を足し、1a-4 に sandbox のホストでパネルの結果を読めるかを足した。パスだけで足りなければ結果のハンドルか bookmark を第 1 部で設計の対象にする |
| RA-5 | Codex A-5 | `detect*` を一括して「内容を読まない」と扱っている。`detectValues` は値を読み、拒まれると完了にエラーを返す（SDK の `NSPasteboard.h`） | 企画 3.2 と 8.6 を、`detectPatterns`・`detectMetadata`（内容を読まない）、`detectValues`・通常の読み出し（内容を読む。確認と拒否がありうる）に分けた。`accessBehavior` だけから個々の読み出しの結果を決めないことを書いた。調査 C の記述は日付の記録として残し、知見に注を足した |
| RA-6 | Codex A-6 | `unity-native-plugin` のコピーの経路（`PreBuildProcessor`・`PostBuildProcessor`・`MacFrameworkPatcher`）も、ディレクトリの列挙と普通のファイルのコピーで、dist が正しくても取り込みの後に symlink を実体にしうる | 「2b の前に頼むこと」に 4 として「全てのコピーの経路で symlink を保つ」を足し、dist → Unity のパッケージ → 書き出し → 最後の `.app` の各段で確かめることと、最後の `.app` の framework の署名し直しと `codesign --verify` を DoD に足した |

## 区分 B

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| RB-1 | Codex B-1 | 0e で完了と handler の actor の契約を変えた後に、1a でモーダル・Share・Unity の起動が成り立たないと分かると、移行と基準をやり直す | 1a のうち契約を左右するもの（1a-6〜1a-9）を「1a-前」として 0e の前に終える形にした（0a〜0d と並行してよい）。決定は「条件付き（1a で確かめて確定）」と書き分けた |
| RB-2 | 両方（Claude B-2、Codex B-2） | macOS 15 の VM では Xcode 26.6（macOS 26.2 以上）も 26.3（15.6 以上）も動かない（こちらで `LSMinimumSystemVersion` を確かめた）。VM で組むと ad-hoc になり、Hardened Runtime のサンプルは起動しない。C の案は最小 OS の実行の確かめにならない | D-21 を「ホストで組み、VM で `test-without-building` する」形にし、VM の Xcode・ランナー・テストの製品の互換と署名を 0a（1a-10）で確かめる、とした。15.0〜15.5 は Xcode が動かないので、15.x の実行の実績と 15.0〜15.3 の availability の分岐を区別し、確かめない範囲をリリースの受け入れの判断として書く |
| RB-3 | Codex B-3 | VM という名前だけでは隔離にならない（共有のクリップボード、共有のホーム、個人のアカウント、実のサービスへの送信） | D-23 に VM の資格の条件（個人のアカウントなし、ホストとのクリップボードとフォルダーの共有なし、合成のデータだけ、送らない）を書き、満たす VM の中だけを許可なしにした |
| RB-4 | Codex B-4 | 貼り付け板の確認のテストで、確認が本当に出たかの正の対照が無い。出なかった結果から「main は止まらない」と結論すると危ない | 1a-11 を、別の試験用のアプリが合成の値を書き、対象のアプリが貼り付けの UI の文脈なしで読む経路にし、確認が実際に出たことを成立の条件にした。許可・拒否・保留の間の main の応答・遅い完了を分けて記録する |
| RB-5 | Codex B-5 | 2c の最後の dist での Unity の確かめが、backend とロードの方式ごとに固定されていない | DoD と 2c に、backend・Unity の版・アーキテクチャごとの表で、コールバック・`release`・GC を挟んだ寿命・通知の起動を確かめることを足した。Clipboard だけを使うホストでも framework が残って読まれることを 1a-9 に足した |
| RB-6 | Codex B-6 | `LSMinimumSystemVersion` と起動の成功だけでは、両方のアーキテクチャの最小 OS、実効の entitlement、Library Validation の有効を示せない | 7.3 に各アーキテクチャの `LC_BUILD_VERSION` を足した。1a-4 と smoke を、同じ Team＋検証有効を正の例、ad-hoc＋検証有効を失敗を期待する例に分け、最後の `.app` の実効の entitlement と署名を記録する形にした |
| RB-7 | Claude B-1 | C ABI のテストの私物の区分と、テストのホスト（iOS の TestHost・UITestApp・UITests に当たるもの）が無い | 構成図に `MacLibraryCApiTestHost`・`MacLibraryCApiUITestApp`・`MacLibraryCApiUITests`（案）を足し、7.5 に C ABI のテストの行を足した（純粋な検査は bundle の無い xctest で許可なし、通知・Dialog・Share・一般の貼り付け板はホストで区分 2 か 3） |
| RB-8 | Claude B-3 | 通知のクリックと `open -b` は LaunchServices に登録された同じ bundle id のどのコピーでも起動しうる。通知の許可は bundle id ごとに残り、最初の問い合わせに戻せない | 0a・1a-8・更新のテストの前提に「起動したコピーの道を記録する」「余分なコピーを外す手順（D-23 の許可の対象）」「許可の状態を戻す手段（VM のスナップショットか利用者の手）」を足した |
| RB-9 | Claude B-4 | Unity の書き出しの `Main.cpp` は `PlayerMain` を呼ぶだけなので、`PlayerMain` の前に入れられる見込みがある（D-4 の A の裏付け）。ただしその時期は `NSApp` が無い | 8.6 の通知の行に `NSApp` が無い時期の扱いを足し、1a-9 に「`Main.cpp` で `PlayerMain` の前に受け手を登録する形と、直接呼ぶ形」「書き出し直しで足したコードが残るか」を足した。D-4 に裏付けを書いた |
| RB-10 | Claude B-5 | IL2CPP では P/Invoke が `GameAssembly.xcodeproj` の側に入るが、今の `PostBuildProcessor` は main のターゲットにしかリンクしない | 1a-9 と 2c に「GameAssembly のターゲットにリンクが要るか」を足した |
| RB-11 | Claude B-6 | DoD に、同じ回の 2 つ目の表示の完了が 1 回（SH-13）、dist の swiftinterface を 26.3 で読めること、最小の macOS で動くこと、が無い | DoD に 3 行を足した |
| RB-12 | Claude B-7 | `SharePickerPresenterTests` は 50 ms の固定の待ちに頼り、外れるとこの Mac で本物のメールの作成を開きうる。「私物に触れない」は宣言だけでは守れない | 7.5 と D-23 に「0d で区分を宣言する前に、`MacLibraryTests` を本物の `NSSharingService`・一般の貼り付け板・通知センターに届きうる経路で洗い、固定の待ちのテストは直すか区分 2 にする」と書いた |
| RB-13 | Claude C-2（B として扱った） | `FindLatestVersionInDist` は macOS 以外のリリースで作った新しい dist でも外れるので、固定は macOS の 2b の前より早く頼むのがよい | 「頼むこと」の時期を「次にどの OS でも `dist/` を作る前」に早めた |

## 区分 C

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| RC-1 | Codex C-1 | `canPerform` が D-5 で範囲外なのに、3.3 で第 2 部で名前を決める対象に入っている | 3.3 から外した |
| RC-2 | Codex C-2 | `__Internal` の公式の説明が広すぎる。macOS の IL2CPP の C++ のソースのプラグインには記載がある | D-24 と 0 章を「macOS の IL2CPP のソースのプラグインには記載がある。dynamic の framework のリンクと探索は別に測る」に限った |
| RC-3 | 両方（Codex C-3、Claude C-9） | 一般の貼り付け板の許可を得たテストと、「agent は Mac のクリップボードを読み書きしない」の境目 | D-23 に「agent が直接読み書きしない（`pbcopy`・`pbpaste` など）。許可を得たランナーを通したテストの実行だけが例外。私物の退避はしない」と書いた |
| RC-4 | Claude C-1 | 308・75・52 は宣言の数 | 「`@Test` の数で、`arguments:` の展開前」に直した |
| RC-5 | Claude C-2 | `unity-native-plugin` の罠の説明が今の名前に合わない | 1.4 と 5 章と知見の 15 を書き直した |
| RC-6 | Claude C-3 | 頼むことの 3 は「直す」 | 直した |
| RC-7 | Claude C-4 | 2b に「dist には全 OS の成果物をそろえる」が無い | 足した |
| RC-8 | Claude C-5 | D-8 も iOS と意味が違う | 決定の文書の頭の注を直した |
| RC-9 | Claude C-6 | 15.1 の置き場所 | プロジェクトの階層の設定と書いた（1.4、0e、D-15、8.3、知見の 11） |
| RC-10 | Claude C-7 | `generate_docc.sh` が消す道 | 正確な道に直した |
| RC-11 | Claude C-8 | 企画 3.1 の「（8.4）」が企画の中に無い章 | 「決定の文書の 8.4」に直した |
| RC-12 | Claude C-10 | 知見の 6 の扱う場所が 8.6 に無い | RB-9 で 8.6 に行を足して解いた |

## 次

直した版を 2 回目のレビュー（v2）に出し、区分 A が 0 になるまで続ける。
