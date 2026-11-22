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

**D-8 への反映**: 推奨は A'（`MacLibrary` の Dialog とパネルの表示の手順を、GCD のブロックの外から `runModal` に入る形に直す）。確定は、Unity で開いている間に描画とプレイヤーのループが止まるか（1a-9）を見てから、0e の前に行う。

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
