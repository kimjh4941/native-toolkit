# 段階 0a と 1a-前: 作業の記録

- 記録日: 2026-11-22（書き足していく）
- 対象: 企画 5 章の 0a（UI テストのスパイク、VM）と、決定の文書 8.2 の 1a-前（1a-6〜1a-9）
- 進め方: 利用者の指示（2026-11-22 夜）で自律で進める。判断は推奨案、push は可。私物に触れるテストと画面を使うテストは、この Mac では流さず、`agent-rules/device-testing.md` の条件を満たす VM で流す

## 1. VM の準備（D-21）

### 1.1 したこと

| 時刻 | したこと | 結果 |
|---|---|---|
| 20:30 | 取り込み済みのイメージを消した（`tart prune --entries caches --older-than 0`。利用者の許可済み） | `~/.tart` が 48 GB → 25 GB |
| 20:31 | VM 専用の ssh の鍵を作った（`~/.tart/ntk-ssh/`。利用者の `~/.ssh` は使わない。known_hosts も同じフォルダー）。入り口のスクリプト `~/.tart/ntk-ssh/vmssh` | Cirrus Labs のイメージの既定のアカウント `admin` に鍵を登録した |
| 20:32 | 今の VM（`sequoia-15.4.1-probe`、macOS 15.4.1）を `tart run --no-graphics --no-clipboard` で起動（フォルダーの共有なし） | 起動した。自動ログインは `admin` |
| 20:35 | VM のディスクを 50 GB → 80 GB に広げ、中の APFS の領域も広げた（`diskutil repairDisk disk0` の後でないと全部は広がらなかった） | VM の中の空きが 18 GiB → 50 GiB |
| 20:36 | VM の名前を `ntk-macos-15` に変えた（更新すると 15.4.1 の名前と中身が合わなくなるため） | |
| 20:37〜21:05 | VM の中で 15.8.3 への更新を 4 通り試した（下の 1.2） | **どれも当たらなかった** |
| 21:06 | Cirrus Labs の作り済みのイメージの版を調べた（`ghcr.io/cirruslabs/macos-sequoia-vanilla` のタグ） | 15 の最新は **15.7.7**。15.8.x のイメージは無い |
| 21:08〜22:56 | 15.7.7 のイメージを新しい VM `ntk-macos-15-new` として取り込んだ（`tart clone`）。古い VM は止めて残した | 約 1 時間 50 分。この Mac の回線は下り約 89 Mbps（`networkQuality`）だが、取り込みは約 3 MB/s（約 25 Mbps）で、「The network connection was lost」の取り直しが 10 回ほどあった。tart の `--concurrency` を上げれば速くなる見込み（確かめていない） |
| 22:57 | 新しい VM を `--no-graphics --no-clipboard` で起動し、VM 専用の鍵を登録した（起動の直後は「Too many authentication failures」で切られ、少し後に通った）。ディスクを 80 GB にしたが、このイメージは本体の領域の後ろに復旧用の領域（5.4 GB）があり、中の領域は広がらなかった（空き 18 GiB） | 復旧用の領域は、15 の更新のために残した |
| 22:57〜23:35 | VM の中で 15.8.3 への更新（root のシェルから `softwareupdate -i ... --restart --user admin --stdinpass`） | **当たった**。ダウンロード（約 3 GB）と組み立てが実際に進み、再起動の後に **15.8.3（24H241）**。組み立ての間、中の空きは 6.4 GiB まで減った |
| 23:36〜23:45 | この Mac の Xcode 26.3 を `tar` と `ssh` で VM に写し、`xcode-select`・ライセンス・`-runFirstLaunch` | VM の中で `xcodebuild -version` が 26.3（17C529）、`-checkFirstLaunchStatus` が 0 |
| 23:45〜23:50 | この Mac の Xcode 26.6 も写して、macOS 15.8.3 の上で動くかを試した | **コマンドラインでは動いた**: `xcodebuild -version` が 26.6（17F113）、`swift --version` が 6.3.3、`@c` の関数を組んで `_ntk_` のシンボルが出た。Apple の表では 26.6 は macOS 26.2 以上なので、支えられた使い方ではない（Xcode のアプリとして開けるか、UI テストを流せるかは確かめていない）。Cirrus Labs も `macos-sequoia-xcode:26.6` を出している |
| 23:50 | 古い VM（`ntk-macos-15`、15.4.1）を消し、取り込んだ元の型を `tart prune` で消した | `~/.tart` は 33 GB（新しい VM だけ）、この Mac の空きは 165 GiB |

### 1.2 15.8.3 への更新が当たらなかった

| やり方 | 結果 |
|---|---|
| `sudo softwareupdate -i "macOS Sequoia 15.8.3-24H241" --restart --user admin --stdinpass`（パスワードを `sudo -S` と同じ標準入力で渡した） | 「Downloading: 100.00%」の後、再起動せずに終わった |
| root のシェルの中から `softwareupdate` にパスワードを渡して同じ命令 | 同じ |
| `softwareupdate --fetch-full-installer --full-installer-version 15.8.3`（root と `admin` の両方） | 「Update not found」。`--list-full-installers` には 15.8.3 が出る |
| `softwareupdate --download "macOS Sequoia 15.8.3-24H241"` | ダウンロードの途中で黙って終わった |

`softwareupdated` のログには `ANOMALY: CallCompletion, reason=No SUMacControllerClientRequest was provided` が出ていた。仮想の Mac（Virtualization の VM）で macOS の更新が当たらないのは、この VM と 15.4.1 → 15.8.3 の組み合わせでは確かな事実で、原因は分からない。

### 1.3 イメージの出どころと既定のパスワード

`ghcr.io/cirruslabs/macos-*` は、tart の開発元の Cirrus Labs が出しているイメージで、tart の文書の始め方でも使う（Apple の公式ではない）。Apple の復元イメージ（IPSW）から、公開の Packer のひな形（`macos-image-templates`）で組み立てている。種類は `vanilla`（素の macOS に `admin` の利用者・自動ログイン・ssh だけ）、`base`（開発の道具を足したもの）、`xcode`（Xcode を足したもの）で、ここでは `vanilla` を使う。前の VM（15.4.1）も `macos-sequoia-vanilla` から作ったもの。

`vanilla` の `admin` のパスワードは `admin` で、広く知られている値である。VM は tart の内側のネットワーク（この Mac からしか届かない）にしかつながず、クリップボードとフォルダーを共有せず、ログインには VM 専用の鍵（`~/.tart/ntk-ssh/`）を使うので、外から入られる経路は無い。VM を外のネットワークに橋渡しする設定（`--net-bridged` など）は使わない。

**結果（23:35）**: 作り直した 15.7.7 の VM では 15.8.3 への更新が当たったので、D-21 のとおり **15.8.3** の VM になった。下の判断の「当たらなければ 15.7.7」は使わなかった。

**判断（推奨案。利用者の「推奨案でいい」の指示による）**: Cirrus Labs の 15.7.7 のイメージで VM を作り直し、その VM で 15.8.3 への更新をもう一度だけ試す。当たらなければ、15.7.7 を「VM で使える 15 の最新」として使い、D-21 の「15 の最新（15.8.3）」との差をここと決定の文書に書く。15.7.7 でも Xcode 26.3（15.6 以上）は動くので、D-21 の目的（15 の上での単体テストと UI テスト）は変わらない。

## 2. 1a-6: Dialog の下での main への積み方と取り消し

- 日時と環境: 2026-11-23 0 時ごろ、VM `ntk-macos-15-new`（macOS 15.8.3、24H241）。この Mac では流していない（区分 3）
- 試作: `results/probes/1a6-dialog-main-queue/main.swift`（Xcode 26.3 で組み、ad-hoc の署名の `.app` を VM に写して `open -W` で起動）。アラートは自分で閉じ、人の操作は無い。安全のために、モーダルのモードの Timer で 6 秒後に必ず閉じる
- 測り方: アラートを開いて 0.5 秒後に、別のスレッドから 5 つの積み方で main に仕事を積み、開いている間に走ったかを記録する。2 秒後に、別のスレッドから GCD か run loop で `NSApp.abortModal()` を積む

| 入り方 | `DispatchQueue.main.async` | `Task { @MainActor }` | `CFRunLoopPerformBlock`（common） | `RunLoop.main.perform`（common） | `performSelector(onMainThread:modes: common)` | 取り消し |
|---|---|---|---|---|---|---|
| A: `DispatchQueue.main.async` の中から `runModal`（今の `MacDialogManager`） | 走らない（閉じた後） | 走らない（閉じた後） | 走る | 走る | 走る | GCD で積んだ取り消しは届かず、6 秒の安全の Timer で閉じた。run loop で積んだ取り消しは届いた |
| T: `Task { @MainActor }` の中から（0e・0f の書き方） | 走らない | 走らない | 走る | 走る | 走る | run loop で積んだ取り消しは届いた |
| A': `CFRunLoopPerformBlock`（common）の中から | 走る | 走る | 走る | 走る | 走る | GCD で積んだ取り消しが届いた |
| A': main の run loop の Timer（default）から | 走る | 走る | 走る | 走る | 走る | GCD で積んだ取り消しが届いた |

**分かったこと**:

1. レビュー v1 の RA-1 の心配は当たっていた。今の形（A）と、Swift の main actor から入る形（T）では、アラートが開いている間、main キューと main actor に積んだもの（C ABI の全機能の完了・イベント・`release`、Clipboard の `Task { @MainActor }` を含む）が閉じるまで止まり、GCD で積んだ取り消しも届かない
2. GCD のブロックの外（run loop のブロックか Timer）から `runModal` に入ると（D-8 の A'）、開いている間も main キューと main actor の仕事が走り、GCD で積んだ取り消しも届く。アラートの見た目は今と同じ
3. D-8 の判定の基準: (1) ほかの完了が届く → A' で満たした。(2) その要求の Dialog だけを閉じ、ホストのモーダルを閉じない → `abortModal` は今のモーダルを閉じるので、閉じる前に `NSApp.modalWindow` が自分のアラートの window かを確かめる形を第 1 部で設計する（測っていない）。(3) 同じ回の 2 つ目 → A' では開いている間に main キューが捌かれるので、2 つ目の要求が 1 つ目の中で入れ子に `runModal` を始める見込みがある。1 つ目が閉じるまで 2 つ目を待たせる形を第 1 部で設計し、試作で測る（測っていない）
4. ファイルのパネル（`NSOpenPanel` / `NSSavePanel` の `runModal`）は測っていない。同じ仕組みの見込みだが、第 1 部の前に同じ試作で確かめる

### 2.1 残りの基準とファイルのパネル（1a-6 の続き）

- 日時と環境: 2026-11-23 2 時ごろ、VM `ntk-macos-15-new`（macOS 15.8.3）。試作は `results/probes/1a6b-panels-nesting-cancel/main.swift`（自分で閉じ、人の操作は無い）

| 場面 | 結果 |
|---|---|
| P-A: `NSOpenPanel.runModal()` を `DispatchQueue.main.async` の中から | アラートと同じ。開いている間に GCD と `Task { @MainActor }` は走らず、GCD で積んだ取り消しも届かず、安全の Timer で閉じた |
| P-A': `NSOpenPanel.runModal()` を run loop のブロックから | 開いている間に GCD と `Task { @MainActor }` が走り、GCD で積んだ取り消しが届いた |
| N1: 同じ回に run loop のブロックで 2 つのアラートを積む（何もしない） | 入れ子にならなかった。1 つ目が閉じてから 2 つ目が開いた（同じ回に積んだブロックは順に走る） |
| N2: 「開いている間は次を待たせる」形で 2 つ | 順に開いて閉じた |
| H1: ホストのアラートが開いている間に、自分のアラートの要求が届く | **自分のアラートはホストの上に入れ子に開いた**（A' では開いている間に要求が走るため）。「`NSApp.modalWindow` が自分のアラートの window か」を確かめてから `abortModal` すると、自分だけが閉じ、ホストのアラートは残った |
| H2: 自分のアラートの上にホストのアラートが開いている | 取り消しは「前面が自分ではない」として断り、ホストのアラートを閉じなかった（安全側）。断った取り消しはそのままでは失われる |

**分かったこと**: ファイルのパネルもアラートと同じで、A' で基準 (1) を満たす。基準 (2) は、取り消しの前に前面のモーダルが自分のものかを確かめれば守れる（H1・H2）。自分のものでないときの取り消しを、後で効かせるか「今は取り消せない」と返すかは第 1 部で決める。基準 (3) は、開いている間に届いた要求が入れ子に開くので（H1）、ライブラリが「開いている間は次を待たせる」形を持つ（N2）。同じ回に積んだ要求は入れ子にならない（N1）。

**D-8 への反映**: 推奨は A'（`MacLibrary` の Dialog とパネルの表示の手順を、GCD のブロックの外から `runModal` に入る形に直し、開いている間は次の要求を待たせ、取り消しは前面のモーダルが自分のものかを確かめてから行う）。基準 (1)〜(3) とパネルは A' で満たせる見込みが立った（2.1）。確定は、Unity で開いている間に描画とプレイヤーのループが止まるか（1a-9）を見てから、0e の前に行う。

## 3. 1a-7: 共有のピッカーを mouseDown の外で出せるか

- 日時と環境: 2026-11-23 0 時ごろ、VM `ntk-macos-15-new`（macOS 15.8.3）。この Mac では流していない（区分 3）
- 試作: `results/probes/1a7-share-picker-context/main.swift`。window を 1 つ開き、5 つの文脈から `NSSharingServicePicker(items: ["ntk probe text"]).show(relativeTo:of:preferredEdge:)` を呼び、1.5 秒後に自分以外の見える window を数え、`close()` で閉じる。サービスは選ばない（何も送らない）

| 文脈 | `currentEvent` の種類 | ピッカーの popover（`_NSPopoverWindow`）が出たか | `close()` の後の `didChoose(nil)` |
|---|---|---|---|
| S1: `DispatchQueue.main.async` | 13（mouseDown ではない） | 出た | 約 0.5 秒後に来た |
| S2: `Task { @MainActor }` | 21 | 出た | 来た |
| S3: 合成の mouseDown（`NSApp.postEvent`）の中 | 1（leftMouseDown） | 出た | 来た |
| S4: 合成の keyDown の中 | 10（keyDown） | 出た | 来た |
| S5: 別のスレッドから GCD で main に積む | 21 | 出た | 来た |

**分かったこと**: macOS 15.8.3 では、Apple のヘッダーの「mouseDown で呼ぶ」に反しても、ピッカーは出た。D-6 の「いつも main に積んで出す」のまま Share を出せる見込みで、Share を D-6 の例外にする必要は今のところ無い。`close()` で閉じると完了（`didChoose(nil)`）が来る。

**確かめていないこと**: 出たピッカーの中身（サービスの一覧）が正しく並び、選べるか（ここでは window が出たことだけを見た。実の選ぶ操作は 0a の UI テストで見る）。macOS 26 での振る舞い（この Mac の画面を使うので流していない。区切りで許可を得て見るか、0a の UI テストで見る）。Unity の `Update` の中からの呼び出し（1a-9 で見る）。

## 4. 0a: XCUITest で扱える項目（VM の 15.8.3）

- 日時と環境: 2026-11-22 23:50〜11-23 0:35（日本時間。VM の時計は UTC で、下の時刻は VM の時刻）。VM `ntk-macos-15-new`（macOS 15.8.3、24H241、`--no-graphics --no-clipboard`、フォルダーの共有なし、個人のアカウントなし）。この Mac では何も流していない（区分 2・3）
- ソース: `git archive HEAD mac`（`0ddef5d0`）を VM に写して組んだ。サンプルとランナーは ad-hoc の署名（`CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`）。チームの署名は使っていない
- 試作: `results/probes/0a-uitest-spike/`。試作のアプリ（`app/`。bundle id `dev.ntkprobe.notif0a`、サンドボックスなし。パネルを見るためにサンドボックスありの `dev.ntkprobe.sbx0a` も組む）と、それを動かす UI テスト（`uitest/`。VM の中のサンプルの写しの `MacLibraryExampleUITests` のフォルダーに置いて流した。リポジトリのサンプルには入れていない）。UI テストのランナーはサンドボックスの中なので、試作のアプリの記録（`~/ntk/probe-events.log`）は ssh で読んだ

### 4.1 VM でしたこと（VM の状態を変えたもの）

| したこと | 理由 |
|---|---|
| `sudo automationmodetool enable-automationmode-without-authentication`、`sudo DevToolsSecurity -enable`、`admin` を `_developer` に入れた | XCUITest の自動化を、人の認証なしに始めるため。これだけで UI テストが走った（アクセシビリティの許可の画面は出なかった） |
| 通知の設定の `com.apple.ncprefs` の `dnd_prefs` の `dndMirrored` を `false` にし、`cfprefsd`・`usernoted`・`NotificationCenter` を立て直した（`scripts/nc-allow-when-shared.sh`） | **既定のままでは、XCUITest の実行中は通知のバナーが出ない**。テストの間、通知センターのログに `isScreenShared=1`・`mutedByDisplayState=true` が出て、通知は `muted` として一覧にだけ入った。XCTest が画面を取り込むのを「画面の共有」と見なしている（推測。スクリーンショットを 1 枚取っただけでも同じログが出た）。システム設定の「画面の共有中も通知を許可」に当たる値 |
| 通知の許可を戻すために、`com.apple.ncprefs` の `apps` から試作の項目を消して同じ daemon を立て直した（`scripts/ncreset.sh`）。各回の前に 1 回 | 4.4 |
| 試作のアプリに `defaults write dev.ntkprobe.notif0a EnablePasteboardPrivacyDeveloperPreview -bool yes` | 貼り付け板のプライバシーの確認（macOS 15.4 からのプレビュー）を出すため |

### 4.2 既存の UI テスト（サンプル、Xcode 26.3）

`MacLibraryExampleUITests` の全件を 1 回流した。実行は 38 件（Clipboard 11、Clipboard の待ちの規則 6、Share 17、`MacLibraryExampleUITests` 2、起動の画面 1 件を見た目の 2 通りで 2）。1 回に約 6 分（343 秒）。

| 結果 | 件数 | 落ちたテストと理由 |
|---|---|---|
| 通った | 34 | Share のメール（`testShareViaMailCompletesWithMailService`）も通った。VM はメールのアカウントが無く、何も送られていない。メールのアプリが起動して通知の許可を求めた（通知センターに問い合わせが残った） |
| 落ちた | 4 | **Share の 3 件**（`testShareTextPickerAppearsAndCancelResolves`・`testShareTextPickerCopyServiceCompletes`・`testShareExcludingServicesPickerResolves`）: どれも共有のピッカーの「Copy」のボタンを待って落ちた。**macOS 15.8.3 のピッカー（テキスト）には「Copy」が無い**（並ぶのは Mail・Messages・Notes・Freeform・Reminders・Edit Extensions…。4.3 の S20）。ほかのピッカーのテスト（URL・画像・ファイルなど 7 件）は、Copy が無いと Escape で閉じる作りなので通ったが、15 では「選んで完了する」経路を確かめていない。**Clipboard の 1 件**（`testObservationStopsWhenTheScreenIsLeft`）: 画面を離れて戻っても状態が「Observing」のまま（期待は「Not observing」）。2 回流して 2 回とも同じ。原因は調べていない（macOS 26 のこの Mac で通るかも確かめていない） |

**Xcode 26.6（`DEVELOPER_DIR=/Applications/Xcode26.6.app/Contents/Developer`）では流せなかった**: `xcodebuild -version` は通るが、ワークスペースを開く段階で `IDESimulatorFoundation` のプラグインを読めずに止まった（`/Library/Developer/PrivateFrameworks/DVTDownloads.framework` の版が合わない）。`-checkFirstLaunchStatus` は 69（初回の準備が要る）。`-runFirstLaunch` は VM の `/Library/Developer` の共有の部品を 26.6 の版に替え、主に使う 26.3 を壊すおそれがあるので行っていない。26.6 の部品が macOS 15 に入るかも分からない（Apple の表では 26.6 は 26.2 以上）。

### 4.3 項目ごとの結果

スパイクの本体（`Stage0aSpikeTests` の 17 件）は、許可の状態を戻してから **3 回流して 3 回とも 17 件すべて通った**（1 回に約 3 分 40 秒）。通知センターの一覧と本文のクリックのコールドスタートの変形（`Stage0aSpike2Tests`）は 1 回。

| 項目 | 自動化 | 方法 | 3 回 |
|---|---|---|---|
| 通知の許可の問い合わせ（許可） | **できる** | 問い合わせは `com.apple.notificationcenterui` の木に、label「“<アプリ名>” Notifications, Notifications may include alerts, sounds, and icon badges.」の group として約 1.1 秒で出る（ログでは `com.apple.notificationcenter.askpermissions` が出す通知）。hover すると「Options」の `MenuButton` が出て、押すとメニューに「Allow」「Don’t Allow」が並ぶ。「Allow」で `granted=true`。**答える前にアプリが終わると問い合わせは消え、状態は拒否（`authorizationStatus=1`）になった**（最初の探りで、テストの終わりの片付けがアプリを止めた）。XCTest が問い合わせを勝手に押すこと（iOS の Default interruption handler）は無かった（20 秒以上そのまま残った） | 3/3 |
| 許可の問い合わせ（拒否） | 試していない | 同じメニューの「Don’t Allow」で押せる見込み | - |
| 通知のバナー（前面。`willPresent` で `.banner`） | **できる** | 4.1 の `dndMirrored` の変更が要る。バナーは `com.apple.notificationcenterui` の group で、label は「<アプリ名>, <題>, <本文>」。約 1.06 秒で出る。押すと `didReceive`（既定のアクション） | 3/3 |
| 通知のバナー（後ろ。Finder を前に出す） | **できる** | 同じ。バナーは約 5 秒で消える（6 秒後には無い） | 3/3 |
| 通知センターの一覧 | **できる（1 回）** | メニューバーの時計（`com.apple.controlcenter` の status item、identifier `com.apple.menuextra.clock`）を押すと一覧が開く。**同じアプリの通知は重なり（label の末尾に「, stacked」）、1 回目のクリックで広がり、2 回目で開いた**（コールドスタートした）。`removeAllDeliveredNotifications` の後も、前の回の通知が一覧に残っていた（原因は調べていない） | 1/1 |
| アクションのボタン | **できる** | バナーを hover → 「Options」の `MenuButton` → アクションの題（「Open FG」「Mark BG」「Reply」）のメニューの項目を押す | 3/3 |
| テキスト入力のアクション | **できる** | 「Reply」を選ぶとバナーが広がり、`TextView` と「Send」のボタンが出る。`typeText` で入れて Send。`UNTextInputNotificationResponse.userText` に届いた | 3/3 |
| 予約した通知の発火を待つ | **できる** | 10 秒の予約を `waitForExistence(timeout: 25)` で待てた。予約の後 9.1〜10.1 秒で見つかった | 3/3 |
| コールドスタート（本文のクリック） | **できる** | `terminate()` の後に 8 秒の予約が発火したバナーを押す。**最初の版では 1 回起動しなかった**（要素を `descendants(matching: .any)` で探し、出た直後に押した。どちらが原因かは分けていない）。`groups` で探し、出てから 1 秒待って押す形では 3/3、hover の後に題を押す・座標で押す形も 1/1 ずつ | 3/3（1 秒待つ形） |
| コールドスタート（前面のアクション・後ろのアクション・テキスト入力） | **できる** | 上と同じに止めてから、「Options」から選ぶ | 各 3/3 |
| 共有のピッカー | **できる（表示・一覧・閉じる）** | ピッカーはアプリ自身の木の `Popover` に出る（システムの別のアプリではない）。サービスはボタンの label で並ぶ。Escape で閉じると `didChoose(nil)`。サービスを選ぶことはしていない（15 には副作用の無い「Copy」が無い。Notes・Reminders はデータを書く） | 3/3 |
| `NSAlert`（ボタン、ヘルプ） | **できる** | アプリの木の `Dialog`（label「alert」）。ボタンの identifier は `action-button-1`（最初のボタン）・`action-button-2`、ヘルプは label「Help」のボタンで、押すと `alertShowHelp(_:)` が呼ばれた | 3/3 |
| `NSOpenPanel` / `NSSavePanel` | **できる** | サンドボックスなし・ありの両方で、パネルはアプリの木の `Dialog`（identifier `save-panel` / `open-panel`）に出た。サンドボックスありのパネルは別プロセスの view service だが、`XCUIApplication(bundleIdentifier: "com.apple.appkit.xpc.openAndSavePanelService")` では「見つからない」となり、アプリの木から触る。保存は VM の `~/ntk/paneltmp`。サンドボックスありは `directoryURL` にコンテナーの中の道を渡したが、パネルは前に使った `~/ntk/paneltmp` で開き、そこに user-selected の権限で書けた | 各 3/3 |
| `PasteButton`（SwiftUI） | **できる** | label「Paste」のボタン。**プレビューを有効にした試作では、`PasteButton` を押しても「Allow Paste」「Don’t Allow Paste」の確認が出た**（Apple の説明の「PasteButton は確認なし」と違う。15.8.3 のプレビューの振る舞い）。確認はアプリの木の `Dialog`（label「alert」、identifier `action-button--999` / `--998`。runningboard のログでは `com.apple.appkit.xpc.TrustedUIService`）で、押せる。Allow で中身が届いた。プレビュー無しの `PasteButton` は試作では試していない | 3/3 |
| 貼り付け板のプライバシーの確認（プログラムで読む） | **できる** | ランナーが一般の貼り付け板（VM の中のもの）に書き、試作が `NSPasteboard.general.string` を読むと確認が出る。「Don’t Allow Paste」で `nil`。同じ中身を一度許した後は、もう一度読んでも確認は出なかった | 3/3 |

**`common.md` の例外にする理由（案）**: 上の「できる」の項目は、版を固定した VM（D-21）で 3 回とも同じに通り、要素は identifier か題の文字で選べた。システムの UI の木の形と文字は OS の版と表示の言語で変わる（VM は英語）ので、テストは版を固定した VM でだけ流し、版を上げたら探りのテスト（`Stage0aDiscover*Tests`）で木を取り直す。

### 4.4 許可の状態を戻すこと

- **VM の中だけで戻せた**: `com.apple.ncprefs` の `apps` の配列から試作の項目を消し、`cfprefsd`・`usernoted`・`NotificationCenter` を立て直すと、`authorizationStatus` が 0（未決）に戻り、`requestAuthorization` で問い合わせがもう一度出た（5 回戻して 5 回とも出た。うち 4 回は続けて「Allow」が通った）。戻す前は 1（拒否）か 2（許可）だった
- 私物の Mac で同じことをすると、利用者の通知の設定を書き換えることになる（D-23 の「通知の許可の変更」で毎回の許可）。VM の中だけで使う
- **`tart clone` で複製を取っておく形は試していない**: `device-testing.md` は tart の VM の複製・削除を「1 回ごとに利用者に聞く操作」にしている。こちら（親の agent から頼まれた agent）は利用者に聞けないので、行っていない。上の戻し方で通知の許可は足りるので、複製は「VM の状態をまるごと戻したいとき」の手段として、利用者の許可を得て測る（ディスクの増え方を含む。今の VM は `tart list` で Disk 80 GB、SizeOnDisk 35 GB）

### 4.5 LaunchServices と起動したコピー

- 試作（`dev.ntkprobe.notif0a`）の起動 109 回（XCUITest の `launch()` と、通知からのコールドスタート）は、記録した `Bundle.main.bundlePath` がすべて `/Users/admin/ntk/probe/NtkProbe0a.app` だった
- VM の `lsregister -dump` で、各 bundle id の登録は 1 つずつ（サンプルは `~/ntk/dd263/Build/Products/Debug/MacLibraryExample.app`、ランナーも同じフォルダー）。Xcode 26.6 の DerivedData（`~/ntk/dd266`）は組む前に止まったので消した
- 通知からのコールドスタートは、`didFinishLaunching` の `userInfo` に `NSApplicationLaunchUserNotificationKey` が入った（5 章）

### 4.6 後の段階に効くこと

| ID | こと | 扱い |
|---|---|---|
| M-1 | XCUITest の間は「画面の共有中」と見なされ、既定では通知のバナーが出ない | 通知の UI テストを流す VM（とこの Mac で流すとき）は `dndMirrored=false` にしておく。この Mac では利用者の設定を変えることになるので、準備として利用者に頼む（D-23 の準備に足す） |
| M-2 | 許可の問い合わせは、答える前にアプリが終わると消えて拒否になる | 許可のテストは、問い合わせを押すまでアプリを止めない。各回の前に `ncreset.sh` で未決に戻す |
| M-3 | 15 の共有のピッカーには「Copy」が無く、サンプルの Share の 3 件が落ち、7 件は選ぶ経路を確かめていない | UI テストの設計書（0a の後）で、版ごとの期待（15 は一覧と閉じるだけ、26 は Copy まで）を決める |
| M-4 | サンプルの `testObservationStopsWhenTheScreenIsLeft` が VM で 2/2 落ちた | 0b の前に原因を見る（macOS 15 の振る舞いか、テストかサンプルか） |
| M-5 | 通知センターの一覧は重なりを広げる 2 回のクリックが要り、古い通知が残っていた | 一覧を使うテストは 1 件に絞り、バナーを主にする（iOS の R-3 と同じ向き） |
| M-6 | Xcode 26.6 は VM の中でコマンドラインの組み立てまでで、ワークスペースの UI テストは開けない | D-21 のとおり VM の UI テストは 26.3 で流す。26.6 の `-runFirstLaunch` を試すなら、先に利用者の許可を得て VM の複製を取ってから |
| M-7 | 試作のアプリでは、受け取ったことを画面の文字（`lastReceive`）で読めた | サンプルにも「最後に受けたイベント」の表示を足す（iOS の R-1 と同じ。0b） |

## 5. 1a-8: 通知の起動の判定

- 日時と環境: 4 章と同じ（VM の 15.8.3）。この Mac では流していない
- 試作: `results/probes/0a-uitest-spike/app/main.swift`。通知の delegate を `applicationWillFinishLaunching` の中で入れ、`main` の先頭・`willFinishLaunching`・`didFinishLaunching`・`didBecomeActiveNotification`・`didResignActiveNotification`・`didReceive`（と、そこから `DispatchQueue.main.async` で積んだもの）を、時刻・`NSApp.isActive`・プロセスで何回目かとともに記録した
- 動かし方: 4 章の UI テスト（S02〜S12）。「止まっている」は `XCUIApplication.terminate()` の後に発火した通知から、「動いている」は `launch()` で普通に起動した後（Finder を前に出して後ろにした状態と、前面のままの状態）。3 回流して、3 回とも下の順と値だった。時刻の差は 3 回の幅

### 5.1 結果

| 場合 | 状態 | 順（左から） | `didReceive` の時点の `NSApp.isActive` | 最初の `didBecomeActive` との前後 | その後 |
|---|---|---|---|---|---|
| (a) 本文のクリック | 止まっている | `willFinishLaunching`（isActive=true）→ `didFinishLaunching`（userInfo に `NSApplicationLaunchUserNotificationKey`）→ 約 40〜50 ms 後に `didReceive` #1 → 約 25 ms 後に `didBecomeActive` #1 | true | **前** | 前面 |
| (b) 前面をもたらすアクション（`.foreground`） | 止まっている | 同じ | true | **前** | 前面 |
| (c) 前面をもたらさないアクション | 止まっている | 同じ | true | **前** | **前面に出た**（`didBecomeActive` が来て、XCUITest の状態も runningForeground） |
| (c) テキスト入力（options なし） | 止まっている | 同じ | true | **前** | **前面に出た** |
| (a) 本文のクリック | 動いている（後ろ） | `didReceive` #1 → 約 5〜15 ms 後に `didBecomeActive` #2 | false | 後（#1 は起動のとき） | 前面 |
| (a) 本文のクリック | 動いている（前面） | バナーを押すと `didResignActive` → `didReceive` #1 → 約 5 ms 後に `didBecomeActive` #2 | false | 後 | 前面 |
| (b) 前面をもたらすアクション | 動いている（後ろ） | `didReceive` #1 → 約 10 ms 後に `didBecomeActive` #2 | false | 後 | 前面 |
| (c) 前面をもたらさないアクション・テキスト入力 | 動いている（後ろ） | `didReceive` #1 だけ | false | 後 | 後ろのまま |
| (d) 普通に起動した後の最初のクリック | 動いている | 上の「動いている」の各行が、どれも起動後の最初のクリック（`launch()` ごとに新しいプロセス） | - | 後 | - |

ほかに分かったこと:

- **`NSApp.isActive` は、どの起動でも `willFinishLaunching` の時点で既に true だった**（XCUITest の `launch()` でも、通知からのコールドスタートでも。`main` の先頭では `NSApp` がまだ無いので false と記録された）。`didBecomeActiveNotification` はその後（`didFinishLaunching` の後）に来る
- コールドスタートでは、`didReceive` の中から `DispatchQueue.main.async` で積んだものは、`didBecomeActive` #1 の後に走った（iOS 18.3 の G-7 の記録と同じ向き）
- `NSApplicationLaunchUserNotificationKey` は、通知からのコールドスタートの 4 つの場合すべてで `didFinishLaunching` の `userInfo` に入り、普通の起動（XCUITest の `launch()`）では入らなかった。`NSApplicationLaunchIsDefaultLaunchKey` は XCUITest の起動で true の回と false の回があり、当てにならない
- 通知センターの一覧からのコールドスタート（4.3、1 回）も、`didReceive` #1（それまでの `didBecomeActive` 0 回）→ `didBecomeActive` #1 の順だった

### 5.2 iOS の判定（P1-22）が成り立つか

- **「プロセスで最初の `didReceive` が、プロセスで最初の `didBecomeActive` より前なら起動のきっかけ」は、測った全部の場合で macOS でも正しく分けた**: 止まっている 4 つの場合は前、動いている（後ろ・前面）場合と普通に起動した後の最初のクリックは後
- **iOS と違う点（事実）**:
  1. **前面をもたらさないアクションとテキスト入力でも、止まっている状態からの起動ではアプリが前面に出た**。動いているときは後ろのまま。iOS の U-6 の絞り込み（「起動のきっかけは前面に出す応答だけ。後ろのアクションでの起動はふつうのイベント」）をそのまま写すと、macOS では「前面に出たのに起動のきっかけにならない」場合ができる
  2. **`NSApp.isActive` は `didBecomeActive` より前から true** なので、iOS の「proxy を初めて入れた時点で既に active なら起動のきっかけは無い」を `NSApp.isActive` に置き換えると、`willFinishLaunching` で入れた場合にコールドスタートを全部「無し」と誤る（レビュー v1 の RA-3 の心配が当たっていた）
- **推測（設計で決めること）**: 「入れた時点で既に起動が済んでいたか」は、`NSApp.isActive` でなく、(i) `didFinishLaunchingNotification` が既に来たか（来る前に入れたなら、その userInfo の `NSApplicationLaunchUserNotificationKey` も読める）、か (ii) `didBecomeActive` を一度でも受けたか、で分ける形が使える見込み。(c) の扱い（前面に出るので起動のきっかけにするか、iOS に合わせてふつうのイベントにするか）は D-7 の `launch_response` の定義で決める

### 5.3 確かめていないこと

- `didFinishLaunching` より後に delegate を入れた場合（Unity が後から入れる場合を含む。1a-9 で見る）。`didFinishLaunching` の中で入れた場合（`didReceive` は `didFinishLaunching` の約 40 ms 後に来たので間に合う見込みだが、測っていない）
- Finder や `open` からの普通の起動（測ったのは XCUITest の `launch()` だけ）、ログインの項目からの起動、別の Space・全画面のとき、複数の画面
- 通知のスタイルを「通知パネル」（alerts）にしたとき。VM は既定の「バナー」のまま
- macOS 26（この Mac）での順。区切りで利用者の許可を得て見るか、26 の環境で流す

## 6. 1a-9: Unity での確かめ（途中の知らせ、2026-11-23 未明）

申し送り（`2026-11-23-macos-c-abi-unity-handoff-1a9.md`）を `unity-native-plugin-8f`（利用者が「macOS C ABI対応」と呼ぶ向こうのセッション）に送り、起動しない確かめの結果が届いた。向こうの記録は unity-native-plugin の `artifact/topics/macos-c-abi-handoff/results/2026-11-23-macos-c-abi-1a9-results.md`（向こうで未コミット）。**アプリを起動する確かめ（M-1・M-2・M-3・M-4・M-5・M-7〜M-11）は、向こうの利用者の許可を待っている**（私物の Mac の決まり）。

- 雛形: 向こうが Xcode 26.6 で組んだ（ソースは `90f3bfd1` のもの）。smoke は 4 回、DLOPEN は 2 回とも通った
- 起動の前の確かめ: 組んだ 9 つの `.app`（install の形 x0〜x3、x7、Hardened Runtime の 3 通り、IL2CPP）すべてで、2 つの framework が入り、`otool -L` に 2 行あり、`codesign --verify --deep --strict` が通り、sandbox が true で、Team はアプリと同じ。**`.app` の中の framework の symlink は 5 本でなく 3 本**（`Versions/Current`・本体・`Resources`）。Xcode の `RemoveHeadersOnCopy` が `Headers` と一緒に `Modules` も外すため（`builtin-copy -exclude Modules`）。署名の検証は通る。`check_mac_dist.py` の照らし方（dist の側）とは別の話で、利用者のアプリの中ではこれが正しい形
- M-12（symlink）: **合格**。dist → `Plugins/macOS` → 書き出しで 5 本ずつ残り、`.app` は 3 本ずつ。git の URL の `PackageCache` では 0 本になり、書き出しで作り直した。段 A・B とも `xcodebuild` と `codesign --verify --deep --strict` が通り、取り込みの警告と二重の取り込みは無い
- M-6（書き出し直し）: batchmode で同じフォルダーに書き出し直すと置き換えになり、足した `Main.cpp`・`GCC_PREPROCESSOR_DEFINITIONS`・sandbox・署名・`Info.plist` の鍵はすべて消える。`PostBuildProcessor` は 2 つの framework を 1 回ずつ足し直す（二重にならない）。**2c では、通知の install のための `Main.cpp` の直しを書き出しのたびに入れる形が要る**（D-4・D-24 の材料）
- M-2（IL2CPP、Unity 6000.0.44f1、組み立てまで）: `GameAssembly.xcodeproj` が書き出しの直下にできるので、向こうの `FindPbxprojPath` は「more than one」で止まる。組むには共有の scheme が要る。**C ABI の framework は `GameAssembly` にもリンクが要り**（アプリだけだと `GameAssembly` のリンクが `_ntk_*` の未定義で落ちる）、ターゲットのリンクの段に足しても効かず（il2cpp の `--compile-cpp` が自分でリンクする）、il2cpp の `--linker-flags` に framework の本体のパスを 1 つの値で渡すと通った。`GameAssembly.dylib` には `LC_RPATH` が無く、起動で解けるかは未確認。新しいプロジェクトの最小 macOS は 11.0 で、15.0 向けの framework とのリンクで警告が出る。**D-24 の材料: IL2CPP は 2c で手当てが要る**
- M-4（起動の前）: install の参照の無い形（x0）の実行ファイルは `_ntk_*` を参照しないが、dead strip の設定が無く、`otool -L` に 2 つの framework が残る（起動で読まれるかは起動の確かめで見る）

### 6.1 1a-9 の結果（起動の確かめまで、2026-11-23）

向こう（`unity-native-plugin-8f`）が、向こうの利用者の許可を組ごとに得て 04:16〜04:41 に流した。記録は unity-native-plugin の `artifact/topics/macos-c-abi-handoff/results/2026-11-23-macos-c-abi-1a9-results.md`（`feature/UNT-15` の `994892d`、向こうは push の前）。環境: Unity 6000.4.2f1（IL2CPP は 6000.0.44f1）、Xcode 26.6（M-12 と smoke の利用者は 26.3）、この Mac の macOS 26.7.3。**M-1〜M-12 はすべて済み、blocked は無し**。

| M | 結果 |
|---|---|
| M-1 | 合格。framework は 2 つとも `Contents/Frameworks`、sandbox=1。echo の完了は 1 回、release 1 回、main、戻った後、同じフレーム。`.app` の symlink は 3 本ずつ |
| M-2 | 合格（IL2CPP）。`GameAssembly.xcodeproj` は書き出しの直下で、向こうの `FindPbxprojPath` は止まる。`GameAssembly` へのリンクが要り、il2cpp の `--linker-flags` に C ABI の framework の本体を渡して通る（ターゲットのリンクの段は使われない）。共有の scheme で組む。`GameAssembly` には `LC_RPATH` が無いが解ける。新しいプロジェクトの最小 macOS 11.0 で警告 |
| M-3 | 合格。Awake・Start・Update・コルーチン・focus・OnGUI はすべて main。`Task.Run` は main でない。`Task.Run` から呼んだ echo の完了は main |
| M-4 | 合格。install の参照の無い形でも 2 つの framework が `otool -L` に残り、dead strip は無く、呼び出しも通る |
| M-5 | install の形 1（`Main.cpp` で `PlayerMain` の前に `willFinishLaunching` の受け手を登録）: `didFinish` より前に入った。形 2（`main` で直接）: `NSApp` が無い時期でも入り、後で `PlayerApplication` になった。形 3（`didFinishLaunching`）: 起動から +113 ms で入った。どれもアプリは正常 |
| M-6 | 書き出し直しで `Main.cpp`・設定・plist の鍵は残らない。framework の二重の追加は無い |
| M-7 | 形 1 で合格（4 回目）。コピーは印で確かめ、新しい pid。コールドスタートの配送は 1 回、install は `didReceive` より前。launch=1、順は willFinish(+94) → install(+94) → didFinish(+185、launchKey あり) → didReceive(+894、active=true) → didBecomeActive(+896)。ウォームの配送は 1 回で launch=0。受け手を外した後のイベントは保持を通って 1 回届いた。**`didReceive` は `didFinishLaunching` の約 710 ms 後**で、VM の試作（40〜50 ms）より遅い。1 回目は許可の答えが遅れて 20 秒の上限を超え、2 回目は通知のクリックで M-11 の別のコピーが起動した（向こうの利用者の許可を得て、余分な 8 つを `lsregister -u` で外し、名前を変えてから流した） |
| M-8 | A' では Dialog の間に echo が届き、フレームが進んだ（mode は `kCFRunLoopDefaultMode`）。**A でもフレームは進んだ**（Unity のプレイヤーのループは `runModal` の間も止まらない）。A で止まるのは main キューの完了だけで、echo は閉じた後に届いた。`runInBackground=true` でも同じ。Dialog の間に focus は変わらない |
| M-9 | 全画面でも最大化でも、Dialog と Share はゲームの上に出た |
| M-10 | `Update` からもクリックからも Share が出て、完了は 1 回ずつ。アプリが後ろにいるときは `NOT_FOREGROUND`（6） |
| M-11 | entitlement が無い Hardened Runtime では、Mono が起動の途中で CPU 98% のまま止まった（落ちない）。`allow-jit` だけを足すと、同じ Team の署名で起動し、sandbox=1、Library Validation は有効のまま。ad-hoc は予想どおり起動しない（dyld の different Team IDs） |
| M-12 | 合格（前の知らせと同じ） |

**条件付きの決定の確定（2026-11-23、利用者の「判断は推奨案で」の指示による）**: D-4 は A、D-6 は A、D-7 は B（転送そのものは 1b で確かめる）、D-8 は A'、D-24 は A。

**2c でする手当て（D-24）**: 書き出しのたびに `Main.cpp` の install の形 1 を入れ直す。IL2CPP は `GameAssembly` へのリンクを il2cpp の `--linker-flags` で渡し、`FindPbxprojPath` を 2 つのプロジェクトで止まらない形にし、共有の scheme で組む。Hardened Runtime の利用者には Mono の `allow-jit` を案内する（`disable-library-validation` は要らない）。

**向こうに残ったもの**: この Mac の通知の設定に試すアプリ（NtkProbe1a9）の項目と、ad-hoc の回の crash の記録が 1 つ。消すかは利用者が決める（向こうが利用者に伝えた）。

（2026-11-23 追記: 向こうが push の前に、前のコミットのスクリプトに残っていたホームのパスを履歴から消したため、向こうのハッシュが変わった。この記録のハッシュは読み替えた後のもの（`b1367a8` → `3a337d8`、`de7448e3` → `994892d`。中身は同じ。`cbdf82c` は変わらない）。）
