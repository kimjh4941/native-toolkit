# レビュー結果

- 日付: 2026-11-23
- 対象: `artifact/topics/macos-c-abi/designs/2026-11-23-macos-c-abi-ui-test-design.md` の下書き（コミット前）
- トピック名: macos-c-abi（UI テストの設計書）
- 判定: **要修正**（区分 A が残ったので、設計書を直した。直した版の再レビューはまだ）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行。互いの結果は見せていない）。どちらも読むだけで、VM・この Mac・アプリは動かしていない
- 機械照合: 対象外（`check_design_consistency.py` は機能の設計書用）
- 方針（親が推奨案で決めた）: U-22 は「NC1〜NC3 を 0c に入れる」。A はすべて直す。B は直すか直さない理由を書き、VM で確かめられるものは VM で確かめてから書く。C は直す

区分: A = このまま 0b〜0d に進むと作り直しになるか、私物を守れない、B = 確かめの手段の不足、C = 記述だけ。「出典」は指摘したレビュアーと番号。R の番号は 2 者の指摘をまとめ直したもの。

## 件数

| 区分 | Claude | Codex | 統合後 |
|---|---|---|---|
| A | 6 | 11 | 14（3 件は両方が挙げた） |
| B | 17 | 13 | 22（B のうち 5 件は A にまとめた） |
| C | 14 | 3 | 14（2 件は両方が挙げた。1 件は A にまとめた） |

## 強み（両者）

- 0a の事実を出典つきで写し、事実と推測を分けている（両方）
- サンプルのボタン・id・category・結果の文・エラーの番号、識別子の数（新規 64、Clipboard 54）と件数の内訳がコードと数え直しに合う（Claude）
- iOS で何度も直した型（`.element`、錨、本文と番号を 1 つの値、受け手を設定してから `setup()`、何も押さない監視、閉じた形の規則、1 回限りの許可の ID）を最初から入れている（Claude）
- VM を「許可の要らない場所」にして資格を機械で確かめる、通知の許可を戻すのは VM だけ、VM だけの 3 区分、パネルを fixture に移す、`.xcresult` の動画に気づいた点（両方）

## 事実の照合で分かった誤り

| 主張 | 結果 | 出典 |
|---|---|---|
| ShowCalendar(+1m) は「1 分後」 | サンプルは秒を 0 に切るので、押してから 0〜60 秒後に発火する（iOS のサンプルは秒を残す） | Claude A-4、Codex B-04 |
| 0a の通知・`PasteButton` の結果はサンプルにも当たる | 0a は sandbox の無い試作で、サンプル（sandbox、SwiftUI、`MacLibrary` の delegate）では流していない | Claude B-3 |
| U-11 の逃げ道「`directoryURL` を渡す」 | 0a では sandbox のパネルが `directoryURL` を無視した。ただし渡したのはコンテナーの中の道で、今回 VM でコンテナーの外を渡すと効いた（下の「VM で確かめたこと」） | Claude B-4 |
| `mac/MacLibraryExample/build/` は git の外 | どの `.gitignore` にも当たらない | Claude B-13 |
| 「補助を直せば C9 が直る」 | C9 の戻るのクリックはテストの本体にあり、原因はクリックが効かないこと | Claude B-1、Codex B-11 |
| CB6 の `DetectValues` は外の内容を読む | サンプルは押すと先に自分で検出用の文を書き直す | Codex A-09 |
| （こちらの下書きの 8.0 の 3）列挙の後のログに起動の跡が無かった | VM の zsh の組み込みの `log` を呼んでいて何も読めていなかった（直すときにこちらで気づいた） | - |

## 区分 A

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| RA-1 | 両方（Claude A-1、Codex A-01） | 片付けの `SetBadgeCount(0)` は `runWithPermission` を通るので、未決なら問い合わせを出し、アプリが止まると拒否に変わる。宣言の無い N1・N17 でも走り、`badge` を許していないテストが Dock のバッジを書く | 片付けを `RemoveAllDelivered`・`CancelAllScheduled`（問い合わせを出さない）だけにし、`NotificationToken` を受け取ったテストだけで行う形にした。`SetBadgeCount(0)` は `badge` を宣言し、`authorized` と読めたときだけ。この Mac の前提は「何も押す前に AuthorizationStatus だけを読む」と書いた（U-7、U-15）。権限の段は普段の片付けをせず VM で戻す。変異の表に足した |
| RA-2 | 両方（Claude A-2、Codex A-04） | この Mac の道に単体テストの扱いが無い。`MacLibraryExampleTests`（サンプルをホストにする）と `SharePickerPresenterTests`（固定の待ちで本物の Mail を開きうる）が宣言の表の外にある | U-29 を足した: この Mac では `scripts/mac_unit_audit.json` に載せた hostless の suite だけを名指しし、`MacLibraryExampleTests` と未修正の `SharePickerPresenterTests` は VM だけ。単体の名指しも許可の一覧に入れる |
| RA-3 | Claude A-3（Codex B-09 も） | iOS の 7 章に当たる変異の章が無い | 7 章「変異で確かめること」を足した（テストの側、片付け、根、柱 1〜3、二段目、VM の資格、出力の境界、中断、監視）。変異は VM だけで流す |
| RA-4 | Claude A-4 | +1 分の予約は秒を切るので、2 件を読む前に発火しうる | U-14 に (c) 秒の窓（5〜30 秒になるまで最大 30 秒待ってから押す）を足し、N6・N9・N14・N16 に当てた。9.4 に書いた |
| RA-5 | Claude A-5（Codex B-02 も） | 26.7.3 の木は一度も取っておらず、取り直しの手段の探りのテストは階層を出すので、この Mac では決まりに反する。ja のラベルの取り方も無い | U-30 を足した: ja は VM の言語を一時的に ja にして取る。26 は許可を得た区切りに、サンプルの部分木の中だけで候補がちょうど 1 つあるかを真偽と件数だけで出す適格性の確かめ（`MacQualificationProbeTests`）。それまで 2.1 のこの Mac の列はすべて `自動*`。探りのテストは VM だけと書いた |
| RA-6 | 両方（Claude A-6、Codex A-06） | `Options`・メニューの項目・`TextView`・`Send` をサンプルのバナーの中に限っていない。私物の通知に入力して送るおそれ | VM で確かめてから書いた（下）。U-5 を、根の中の `Options` と `TextView` だけを使い、操作のたびに根を取り直し、メニューの項目は開いたメニューの中でちょうど 1 つのときだけ押す形にした。`Send` は無く Return で送る。0b で返信の placeholder を `MacLibraryExample reply` に変える |
| RA-7 | Codex A-02 | この Mac の道の「最初に N4」が、通知を選ばない回にも通知を出す | 見張りは `notification` を選んだ回だけ、許可の一覧に書いて流す。落ちたら残りの `notification` のテストを流さず失敗に数える（U-20） |
| RA-8 | Codex A-03（Claude B-14 も） | M2 が宣言なしで ShareEmpty を押す（壊れるとピッカーを開く） | M2 から Share を外した（何も起こさない Share のボタンが無いため） |
| RA-9 | Codex A-05（Claude B-15 も） | U-24 の共通のモジュールが許可の固定から漏れる。iOS の守りの確かめに触れていない | 許可の一覧と照合に共通のモジュールのハッシュを入れた。U-24 の推奨に条件（iOS の自己テストと変異を前後で流して同じ、両 OS のランナーのファイルに入れる、別のモデルのレビュー）を付け、満たせなければ写して始める案にした |
| RA-10 | Codex A-07（Claude B-13 も） | `.xcresult` を消しても、xcodebuild の出力・結果の JSON・失敗の文・探りのテストから私物が漏れる | 3.4「外へ出すものの境界」を足した: 生のものは一時フォルダー（`umask 077`）の中だけ、外へ出すのは許す形を決めた一覧の値だけ（失敗の文は出さない）。LaunchServices は数と不透明な印だけ。`build/` を 0d で `.gitignore` に足す |
| RA-11 | Codex A-08（Claude C-1 も） | 決まった U-22 がケース・件数・実行の契約に入っていない | `NotificationColdStartUITests`（NC1〜NC3）を 5.3 に入れ、契約（予約を読んでから `terminate`、`notRunning` の確かめ、起動の待ち、`launch()` を呼ばない、分類を使わない全文の期待値、起動したコピーの印）を書いた。件数を 95 に数え直した |
| RA-12 | Codex A-09 | CB6 は、サンプルが先に自分で書き直すので外の内容を読む経路にならない | CB6 を「自分で書いた内容の検出では確認が出ない」ことと全文だけを見る形に直し、外の内容の `detectValues` は 1a-11 と C ABI のテストに任せると書いた |
| RA-13 | Codex A-10（Claude B-5 も） | VM の資格の確かめが個人アカウントの無さと合成のデータを担保せず、確かめた VM と後の `ssh` の先を束ねていない | 6.3 の 0 を、事実（`kern.hv_vmm_present`、`hw.model`、`MobileMeAccounts`、`Accounts4.sqlite` の認証済みのアカウント、`virtiofs` の mount、`tart run` の引数）で確かめ、読めなければ不合格にする形にした。`IOPlatformUUID` で束ね、出どころの記録を資格の一部にした。基底も `kern.hv_vmm_present` を読む（U-9） |
| RA-14 | Codex A-11（Claude B-6 も） | `launchservices` がコールドスタートと登録を外すことを兼ね、外す対象を許可に固定していない | 宣言 `coldstart` と、ランナーの操作 `--allow-lsregister`（外すコピーを印で許可の一覧に固定し、直前に照らし直す）に分けた。組んだ一時のコピーの登録は消す前に外す。数えるのは `coldstart` を選んだ回だけ（U-21） |

## 区分 B

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| RB-1 | 両方（Claude B-1、Codex B-11） | 戻るのクリックは本体にあり、補助を直しても C9 は通らない見込み。26 の戻るボタンの形も分からない | VM で 6 通り押して、どれも戻らないことを確かめた（下）。U-33 を足し、M1b・M2・C9 を 26 だけにし、15 は M1a（起動し直して開く）にした。C9 の戻るの 1 行は `SampleApp.goBack()` に替えると書いた（U-26 を改めた） |
| RB-2 | Claude B-2 | 重なったほかの窓やサンプルのバナーを合成のクリックが押しうる | 押す前に、前面・窓の中・根の枠と重ならないことを確かめる形を 5.0 と `SampleApp` に足した |
| RB-3 | Claude B-3 | 0a は試作の結果で、サンプルでは流していない | 2.1 に断りを書き、サンプルで 3 回通っていないものを `自動*` にした。サンプルで確かめた分は 9.0 に書いた |
| RB-4 | Claude B-4 | 逃げ道の `directoryURL` は 0a で sandbox に無視された | VM で、sandbox の試作にコンテナーの外（`/private/tmp`）を渡すと効くことを確かめ、逃げ道として残した（U-11） |
| RB-5 | Claude B-5 | iOS の R-19・R-20・結果の宛先・`-collect-test-diagnostics` が無い。二段目が環境変数だけで VM と判断する | 6.3 と 6.4 に足した。`-collect-test-diagnostics` は VM の `xcodebuild -help` で sysdiagnose のような診断の設定と分かったので、付けるが動画は止まらない前提にした |
| RB-6 | Claude B-7 | ad-hoc の署名は組むたびに TCC の許し直しが要りうる | U-31 を足した（この Mac はチームの署名、ID を出さない、最初の区切りで確かめる） |
| RB-7 | 両方（Claude B-8、Codex B-07） | Share と通知の完了に「余分が来ない」の確かめが無い。userInfo を見ていない。D5 の中間の結果 | U-3 に「2 秒で番号が増えない」をすべての完了に当てた。最後のイベントに `userInfo` を足した（キーの順に依らない）。Dialog に `dialog.resultHistory` を足して D5 の 2 つの結果を読む |
| RB-8 | Claude B-9 | 固定するファイルに Swift の正規表現の literal があり、iOS の字句の分け方が扱わない | 6.1 に、字句の分け方に literal を足し、今のファイルの写しを fixture にした自己テストで確かめてから固定すると書いた |
| RB-9 | Claude B-10 | 待ちの規則を `SampleApp` に写すと、写しを誰も検査しない | 本体を `Support/WaitRule.swift` の 1 か所に移し、固定するファイルの関数はそれを呼ぶだけ、C12〜C17 はその本体を検査する形にした |
| RB-10 | Claude B-11 | 全ボタンの確かめ（iOS の 3.7）の章が無い | 5.7 を足した（enum から導く、Clipboard は C1 がソースから導くので除く、照合は VM だけ） |
| RB-11 | Claude B-12 | Dialog の `updateResult` を main に積むと、今の出し方では D5 の表示が閉じるまで遅れる | 積み方は変えず、番号を足すだけにした（4.2）。そろえるのは 0e |
| RB-12 | Claude B-13 | `build/` が git の外でない。この Mac の失敗の文にホームのパスが入る | RA-10 と一緒に直した |
| RB-13 | 両方（Claude B-16、Codex B-05） | 前のテストのバナーや残りの通知が次のテストと重なる。category の切り替えで新しい通知を見た保証が弱い | 通知のクラスの setUp で、根が 0 件になるまで待つ形にした（U-15）。N20 は 1 回目の根が消えたのを確かめてから 2 回目を出す。N5 は押した直後から待つ。VM で、広がった通知が残り `firstMatch` がそれを掴んだことを確かめた（下） |
| RB-14 | 両方（Claude B-17、Codex B-08） | この Mac の基準の範囲と、除外の変化の扱いが無い | U-32 を足した（7 区分をすべて許した回だけ）。基準のファイルに `eligible`・`executed`・`excluded`・`source` を足し、除外の変化を差として出す |
| RB-15 | Codex B-01 | 監視の `true` は止める命令ではない | U-8 に、VM で止まることを確かめてから採り、それまでこの Mac で流す入口の条件にすると書いた。印が立った後は片付けを呼ばない |
| RB-16 | Codex B-03 | 26 の `Copy` の有無・完了・実際のコピーが確かめられていない | S2・S4 を、先に合成の内容を書いてから `Copy` し、テストが書いた後の内容だけを読む形にした。`Copy` が無ければ成功にしない。有無は U-30 |
| RB-17 | Codex B-04 | ScheduleCalendar の発火を確かめるケースが無い | N14b を足した |
| RB-18 | Codex B-06 | 待ちの印が Dialog の文と合わない。モーダルには 2 段の口が要る | U-3 に画面ごとの印と 2 段の口（`begin` → システムの UI → 新しい結果）を書いた |
| RB-19 | Codex B-09 | macOS の実物の fixture が無い | 6.4 に、VM で取った列挙・`xcresulttool`・`otool` の実物を fixture にすると書いた |
| RB-20 | Codex B-10 | `--feature` が権限の段・貼り付けの段・VM の照合に当たらない | U-18 と 6.3 に、すべての段を 1 つの計画から導き、VM でもメソッドを名指しすると書いた |
| RB-21 | Codex B-12 | 中断のときに録画の元を止めてから消す順が無い | 6.3 のこの Mac の道の 4 に、子を止める → 待つ → 消す、消せなければ失敗、次の回の始めに前の残りを片付ける順を書いた |
| RB-22 | Codex B-13 | 1b の後の層に、パネル・Share の同じ回の 2 つ目とホストのモーダルの上下が無い | 5.9 に DA2（パネル）、DA3（ホストの上下と断った取り消し）、DS1（Share）を足した |

## 区分 C

| # | 出典 | 直したこと |
|---|---|---|
| RC-1 | 両方（Claude C-2、Codex C-01） | `--where` は「`vm` と `mac` のほかと省略を拒む。資格が無ければ切り替えずに止まる」にした |
| RC-2 | 両方（Claude C-3、Codex C-03） | U-12 の `alwaysAllow` を「macOS 26.3 のときの測り。26.7.3 は測っていない」と OS の版で書いた |
| RC-3 | Claude C-4 | 4.4 に節の入れ物の `.accessibilityElement(children: .contain)` を足した |
| RC-4 | Claude C-5 | U-4 を、`MacLibrary` が main に積んで呼ぶ受け手の中で書く、と実際に合わせた |
| RC-5 | Claude C-6 | 6.5 に通知の音が鳴ることを足した |
| RC-6 | Claude C-7 | 4.3 に `ObservableObject`・`@Published private(set)`・`@StateObject` を書いた |
| RC-7 | Claude C-8 | S12・S17 は `realservice` のまま、理由（壊れると Mail を開きうる道）を U-13 に書いた |
| RC-8 | Claude C-9 | Share と通知の節に「テストに入れないもの」を足した |
| RC-9 | Claude C-10 | D6 に `d` のキーを足した |
| RC-10 | Claude C-11 | `--baseline` のときはコミットしていない変更を拒むと書いた |
| RC-11 | Claude C-12 | Finder の窓が前に出ることを 6.5 に書き、Cmd+H と比べた理由を U-15 に書いた |
| RC-12 | Claude C-13 | 通知のケースを `自動*` にした |
| RC-13 | Claude C-14 | 範囲の「対象外」に更新のテストを書いた |
| RC-14 | Codex C-02 | 0b の後の確かめを「0a の既知の失敗からの差が増えないこと」にした |

## VM で確かめたこと（直す前に）

2026-11-23、VM `ntk-macos-15-new`（15.8.3）で、サンプルを動かす試しのテストを VM の写しにだけ置いて流した。この Mac では何も動かしていない。詳しくは設計書の 9.0。

- **戻るボタン**（RB-1）: 6 通り（クリック、Cmd+[、座標、1 秒後、長押し、hover の後）でどれも戻らなかった。Clipboard と Dialog の両方の画面で同じ
- **パネル**（RB-4、U-11）: Cmd+Shift+G で `/private/tmp/...` に移って選べ、確定は `OKButton`、結果の全文を得た。保存はファイルを書かなかった。2 回のうち 1 回は別の所で止まった。sandbox の試作で、コンテナーの外の `directoryURL` は効いた
- **通知の根**（RA-6）: バナーの label は副題を含む。`Options` は根の中、メニューの項目は根の外（label は空、title で取れる）、`Reply` の `TextView` は根の中で、`Send` のボタンは無く Return で送れた。通知センターには別の通知の `Options` が同時にあった
- **コールドスタート**（RA-11）: `Open` は 2/2、`Reply`（Return）は 1/1、本文のクリックは 1/2 で前面に来た。起こされたプロセスで `App.init` の受け手にイベントが届いた（サンプルの debug のログを一時的に保存して読んだ。後で既定に戻した）。送れずに広がった通知は一覧に残り、`RemoveAllDelivered` で消えず、次の回の `firstMatch` が掴んだ
- **VM の資格の材料**（RA-13）: `kern.hv_vmm_present` が 1、`hw.model` が `VirtualMac2,1`（この Mac は 0）、認証済みのアカウントは `HolidayCalendar` だけ、`virtiofs` の mount なし

## 次

直した版を 2 回目のレビュー（v2）に出し、区分 A が 0 になるまで続ける。VM の確かめのうち 1〜2 回しか流していないもの（コールドスタート、パネル）は、0c の最初に 3 回流す（設計書の 9.1）。
