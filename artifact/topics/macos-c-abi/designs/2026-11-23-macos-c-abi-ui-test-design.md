# UI テスト設計書（段階 0）

- 作成日: 2026-11-23
- 改訂: 2026-11-23 にレビュー v1（`reviews/2026-11-23-macos-c-abi-ui-test-design-review-v1.md`。Claude と Codex の 2 者。Claude は A 6・B 17・C 14、Codex は A 11・B 13・C 3）を反映した。主な変更は、コールドスタート NC1〜NC3 を 0c に入れた（U-22 は親が決めた）、片付けを許可を変えない操作だけにした、この Mac の単体テストを監査したものだけにした、返信と `Options` をサンプルのバナーの根の中に限った、変異の章（7 章）を足した、+1 分の予約に秒の待ちを入れた、26 と ja の木の取り方（U-30）、外へ出すものの境界（3.4）、VM の資格を事実で確かめる形（6.3）、宣言 `launchservices` を `coldstart` とランナーの操作の許可に分けた。VM で確かめたこと（戻るボタン、パネル、コールドスタート、通知の根）は 9.0 に書いた
- 改訂: 2026-11-23 にレビュー v2（`reviews/2026-11-23-macos-c-abi-ui-test-design-review-v2.md`。Claude は A 1・B 10・C 6、Codex は A 4・B 7・C 3）を反映した。主な変更は、`Reply` が通知センターの一覧を開くので N24・NC3 をこの Mac では U-30 の後まで選ばない、押す前の確かめを「押す点を覆う最前面の窓の持ち主」と通知センターの窓の枠で行い固定した Clipboard の操作にも通す、この Mac で通知のテストが途中で落ちたら残りを止める、VM の道に通知の UI の立て直しの段、U-29 の監査をコードのハッシュに結ぶ、強制終了の後は残った書き手を止めてから消す、コールドスタートの時間の予算、適格性の確かめの段（U-30）、決まった語彙の段の符号（`NTK-STEP`）、テストごとの時間切れ
- 状態: **下書き**（レビュー v2 を反映した。8 章の U-n は U-22 のほかは決まっていない）
- 対象: 企画（`plans/2026-11-22-macos-c-abi-plan.md`）5 章の段階 0b〜0d、7 章・7.1・7.2・7.5
- 入力:
  - 企画と決定の文書（`plans/2026-11-22-macos-c-abi-decisions.md` の D-14・D-21・D-23 と、その後の経過）、DoD（`plans/2026-11-22-macos-c-abi-dod.md`）
  - 0a の結果（`results/2026-11-22-macos-c-abi-stage0a-working-notes.md`。以下「0a」。章番号はこのファイルの章）と試作 `results/probes/0a-uitest-spike/`
  - 私物の Mac の決まり（`agent-rules/device-testing.md` の macOS の節。以下「決まり」）
  - サンプルのコード（`mac/MacLibraryExample/MacLibraryExample/*.swift`）と今の UI テスト（`MacLibraryExampleUITests/*.swift`）。Dialog・Notification・Share はサンプルアプリの設計書が無いので、確かめる観点はコードから起こした
- 手本: iOS の `artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md`（以下「iOS の設計書」）と、iOS の 0c・0d の結果
- この文書を書く間に VM（`ntk-macos-15-new`、macOS 15.8.3）で確かめたこと: 9.0。どれも VM の中だけで、この Mac では何も動かしていない。リポジトリのサンプルとテストは変えていない（試しのテストは VM の写しにだけ置いた）

用語:

- **この Mac**: 利用者が今使っている私物の Mac（macOS 26.7.3）。**VM**: 決まりの「許可なしで流せる VM の条件」を満たす tart の VM（macOS 15.8.3、Xcode 26.3、en-US）。満たすことはランナーが毎回事実で確かめる（6.3）
- **私物の区分**: 決まりの「テストの区分」の 1〜3（1 私物に触れない、2 私物に触れる、3 画面を使う）。UI テストはどれも 3。この文書の表では、画面だけを使うものを「3」、画面に加えて私物（一般の貼り付け板、通知、ほかのアプリ、ファイルの一覧、設定）にも触れるものを「2・3」と書く
- **宣言の区分**: テストごとに宣言する、触れるものの種類（3.3 の 10 個）。iOS の「許可の区分」に当たる
- **宣言の表**: `Support/DeviceRequirements.json`（U-9）
- **結果の行**: 各画面の上の結果の `Text`。今は `"✅ \nResult: <本文>"` か `"❌ \nResult: <本文>"`。Clipboard だけは `accessibilityValue` が `#<通し番号> <本文>`（`ClipboardSampleView.swift:55`）
- **最後のイベント**: 0b で通知の画面に足す表示（4.3）
- **サンプルのバナーの根**: 通知センターの木の、label が `MacLibraryExample, <題>, ` で始まる group がちょうど 1 つあるときの、その group（U-2）
- 決定の番号 U-n はこの文書のもので、iOS の U-n と同じ番号は同じ事柄を扱う

## 1. 目的と範囲

段階 0e〜0g と 1b の前後で、**ネイティブの利用者（Swift の API を使うアプリ）から見た動作が変わっていないこと**を判定できるよう、サンプルの Clipboard・Dialog・Notification・Share に UI テストをそろえる（企画 5 章の 0c、7 章、7.1）。サンプルは段階 2 以降も **Swift の API（`MacLibrary`）だけ**を使い、C ABI もブリッジ（`UnityMacPlugin`）も通らない。Unity から見た動作はこのテストでは比べない（企画 7.1）。

守るもの:

| 段階 | 変わりうるもの | 守るテスト |
|---|---|---|
| 0e | 完了を main で返す、handler に `@MainActor @Sendable`、strict concurrency complete の直し。**Dialog とパネルが `runModal` に入る経路は変えない**（企画 5 章） | 全件。とくに Notification の結果の行・反映・コールドスタート（NC1〜NC3）、Dialog・Share の結果の行と完了の回数 |
| 0f | Swift 6 の言語モード、`shared` の `@MainActor` | 全件（ただし M1b・M2・C9 は 26 だけなので、VM の区切りでは画面を離れたときの監視の停止を見ない。U-33） |
| 0g | framework の bundle id（D-12）とログの subsystem | 全件（通知の delegate と category が framework の bundle id に依存しないこと） |
| 1b | Dialog の出し方（D-8 の A'）、ヘルプをイベントにする、通知の delegate の転送とイベントの口、category の FIFO、エラーの case | 全件。期待値を変える所は理由を書く（企画 4.1）。A' の配送と起動のきっかけの分類は 5.9 の「1b の後の層」 |

| 範囲 | 内容 |
|---|---|
| 対象 | Dialog・Notification・Share の UI テストの新規作成。Share の今の 17 件の置き換え。Clipboard の今の 17 件の載せ替えと 6 件の追加。コールドスタート 3 件。メニューと識別子の一覧のテスト。テストの基盤（`Support/`）。人の確認の手順書。サンプルへの識別子、結果の行の番号、最後のイベントの追加（0b）。`scripts/test_mac.sh` と基準（0d） |
| 対象外 | 実在の共有のサービスへ送ること（U-13）。位置や時刻を変える操作。通知の音（HC2）。複数の画面・Space・全画面。C ABI と Unity（`MacLibraryCApiUITests` は第 2 部で別に設計する）。**1.x から 2.0.0 への更新のテスト**（DoD の更新のテスト。`scripts/test_mac_upgrade.sh` として 1b の後に別に設計する。iOS の更新のテストの設計書と同じ扱い）。`UnityMacPluginTests` の 1 回の実行（D-22。0d の手順で VM で流す） |

**今の動作を基準にする。** 気になる動作（9.4）を見つけても段階 0 では直さず、今の動作を期待値にする。直すのは 1b 以降で、そのとき期待値を変えた理由を記録する。例外は 0b のサンプルの変更（4.4）で、テストから読めるようにするためと、私物を守るため（返信の placeholder）だけに行う。

## 2. 自動化する項目と人の確認の分担

### 2.1 `common.md` の「自動化しないもの」との関係

`common.md` の UI 自動テストは「OS のシェル UI・システム設定」「権限ダイアログの初回同意」を自動化しないものにしている。企画 7.2 のとおり、**0a とこの文書の VM の確かめで 3 回とも同じに通った項目だけ**を例外として自動化する。0a の通知・`PasteButton` の結果は sandbox の無い試作（`dev.ntkprobe.notif0a`）で得たもので、サンプル（sandbox あり、SwiftUI、`MacLibrary` の delegate）で流したものではない。サンプルで確かめた所は 9.0 に書き、まだのものは表で `自動*` にする。

**この Mac（26）の列は、どれも `自動*`**: 26.7.3 のシステムの UI の木は一度も取っていない。U-30 の適格性の確かめ（階層を出さない形）を許可を得て行うまで、この Mac の例外は決まらない。

| 例外にする項目 | VM での根拠（事実） | VM | この Mac |
|---|---|---|---|
| 通知のバナー（前面・後ろ、本文のクリック） | 0a 4.3（試作で 3/3）。サンプルでもバナーの label が `MacLibraryExample, 10s Notification, MacLibraryExample, Will be shown after 10 seconds`（アプリ名、題、副題、本文）で出た（9.0 の 4） | 自動*（試作で 3/3。サンプルでの 3 回は 0c の最初） | 自動*（U-30） |
| 通知のアクション（サンプルのバナーの根の中の `Options` → メニューの項目）とテキスト入力（根の中の `TextView` に入れて Return） | 0a 4.3（試作で 3/3）。サンプルでは `Options` と `TextView` が根の中にあり、`Send` のボタンは無かった（9.0 の 4） | 自動* | 自動*（U-30） |
| 予約した通知の発火を待つ | 0a 4.3（試作で 3/3） | 自動* | 自動* |
| 通知の許可の問い合わせ（許可。拒否は試していない） | 0a 4.3（試作で 3/3）。M-2 | 自動*（**VM だけ**。U-7） | 流さない |
| 通知からのコールドスタート（本文、`Open`、`Reply`） | 0a 4.3・5.1（試作で 3/3）。サンプルでは 9.0 の 5 | 自動* | 自動*（U-30） |
| 共有のピッカー（表示、Escape で閉じる） | 0a 4.3（試作で 3/3）、今の Share のテストもサンプルで通った（0a 4.2）。15.8.3 には `Copy` が無い（M-3） | 自動 | 自動*。`Copy` は 26 だけで、あるかは U-30 で確かめる |
| `NSAlert`（ボタン、ヘルプ） | 0a 4.3（試作で 3/3） | 自動* | 自動* |
| `NSOpenPanel` / `NSSavePanel` と「フォルダへ移動」 | 0a 4.3（試作で 3/3）。サンプルでも Cmd+Shift+G で fixture に移って選べた（9.0 の 3。2 回のうち 1 回は別の所で止まった） | 自動* | 自動* |
| `PasteButton` と貼り付け板のプライバシーの確認（プレビューの設定を入れたとき） | 0a 4.3（試作で 3/3） | 自動*（**VM だけ**。U-12） | 流さない |
| 通知センターの一覧からの起動 | 0a 4.3（試作で 1/1。M-5） | 5.9 の NC4（VM だけ） | 流さない |
| システム設定が前面に来ること（中身は読まない。N3） | 試していない | 自動* | 自動* |
| Dock のサンプルの項目のバッジ（N19） | 試していない | 自動* | 自動* |

システムの UI の木と文字は OS の版と表示の言語で変わるので、例外にした項目は版を固定した環境（D-21）でだけ流す。版を上げたら、VM では 0a の探りのテスト（`Stage0aDiscover*Tests`。階層を `print` し、画面の添付を残す）で取り直す。**この探りのテストは VM だけで流し、この Mac では使わない**（決まりの「階層のダンプを出さない」）。この Mac は U-30 の形で照らす。

### 2.2 人の確認（computer use）

XCUITest で確かめられない項目は手順書にし、**computer use で VM の画面を見て確かめる**（企画 7.2、iOS の U-19）。判定があいまいなら失敗とする。通知の音は対象外（HC2 は欠番）。

**VM の画面の見せ方（手順）**:

1. 利用者に、computer use でこの Mac の画面を撮ることの許可を得る（VM のウインドウを見るだけでも、この Mac の画面が写る。決まりの区分 3）。始める時刻を決め、利用者には私物のウインドウを閉じるか別の Space に移してもらう
2. VM を止め、`tart run <VM> --no-clipboard` で、ウインドウを出して起動し直す（`--dir` も `--net-bridged` も付けない。資格の条件を保つ）。起動し直した後も 6.3 の資格の確かめを通す
3. VM のウインドウを前に出し、手順書のとおりに操作する。撮ったスクリーンショットは VM のウインドウの範囲だけに切り、この Mac のほかの部分が写ったものは残さない
4. 終わったら VM を `--no-graphics --no-clipboard` で起動し直す

この Mac そのもの（26）で人の確認をするのは、0c の自動の確かめで VM と 26 の振る舞いが違うと分かった項目だけにし、そのたびに許可を得る。

| ID | 対象 | 環境 | 手順の要点 | 合格の条件 |
|---|---|---|---|---|
| HC1 | アラートのアイコンと抑止のチェックボックス（D1） | VM | ShowDialog | アイコンが `info.square.fill`（白と青の palette）で、チェックボックス `Don't show this again`、ヘルプのボタン、3 つのボタンが見える。アイコンが無い・別の絵 → 失敗 |
| HC2 | （欠番）通知の音 | - | **対象外**（iOS・Android と同じ） | - |
| HC3 | Dock のバッジ（N19 を自動にできなかったときだけ） | VM | SetBadgeCount(1) → Dock を見る → SetBadgeCount(0) | 1 のときサンプルのアイコンに `1`、0 のとき無い |
| HC4 | 通知センターからの起動（NC4 が安定しなかったときだけ。1b の後の層） | VM | 5.9 の NC4 | 最後のイベントが NC4 の期待のとおり |
| HC5 | 共有のピッカーの画像の項目（S5・S7） | VM | ShareImage・ShareMultipleImages → ピッカーの見出しの縮小画像を見る → Escape | サンプルの `test-image` が 1 枚・2 枚と見える |
| HC6 | Mail の作成の画面（S11） | **VM だけ**（Mail のアカウントが無い） | ShareViaMail → 出た画面を見る → 送らずに閉じる（保存しない） | 宛先 `test@example.com`、件名 `Sample Subject`、本文 `Body text` の作成の画面が出る。アカウントの設定の画面だけが出るなら、その事実を記録して HC6 は「確かめられない」とする（アカウントの無い Mail で作成の画面が出るかは確かめていない。推測） |
| HC7 | 開くパネルの種類の絞り込み（D9） | VM | ShowFileDialog → fixture のフォルダー | `.txt` と `.png` は選べ、`.md` は灰色（VM のサンプルでは `note.md` の行が `isEnabled == true` と読め、自動では見分けられなかった。9.0 の 3） |

手順書は `mac/MacLibraryExample/ComputerUse/HC-<番号>-<名前>.md` に 1 項目 1 ファイルで置く（テストのターゲットのフォルダーの外。iOS と同じ）。

## 3. 規則

### 3.1 守りの前提

iOS の設計書 2 章の前提をそのまま使う: 守る相手はエージェントと開発者の**うっかりした誤り**で、わざと守りを破るコードは対象外。基底と `Support/` の決まったファイルは「信頼する部分」としてハッシュで固定する。最終の守りは、**この Mac で流すたびの利用者の許可**（1 回限りの ID）。

macOS で違うのは、許可の要らない場所が「シミュレーター」でなく「**資格の条件を満たす VM**」になることである。VM であることと資格は、環境変数でなく**事実**（`kern.hv_vmm_present`、機種、Apple アカウントの無さ、共有の無さ）で毎回確かめる（6.3）。満たさなければ、その VM はこの Mac と同じに扱い、許可なしには流さない（決まり）。**守りは、失敗の経路でも通常と同じ許可と出力の境界を保つ**（片付け・見張り・中断で、許可していない操作をしない。3.4）。

### 3.2 規則の表

| ID | 決めること | 案 | iOS と | 理由・根拠 |
|---|---|---|---|---|
| U-1 | 期待値の書き方 | 結果の行は `#<n> ` を外した本文の**全文を完全一致**で比べる。全文が環境で変わるものだけ、決まった形に直して比べる: ShowImmediate の id は `mac-sample-notification-<数字>` の正規表現、パネルのパスは fixture（U-11）を `<fixture>` に置き換える。userInfo の JSON はキーの順に依らず意味で比べる。**この Mac ではパスも本文も外へ出さない**（3.4） | 同じ（直し方を足した） | `common.md` の「部分一致には錨を打つ」。今の Share のテストは `value CONTAINS` で錨が無い |
| U-2 | 要素の選び方 | **アプリの要素は `accessibilityIdentifier` だけで探す**。システムの UI は identifier があればそれで（`action-button-<n>`、`open-panel`、`save-panel`、パネルの `OKButton` / `CancelButton`、`chevron.backward`）、無ければ en と ja のラベルを `Support/SystemLabels.swift` の 1 か所に持って探す。**どの要素も `.element`（ちょうど 1 つ）で取り、0 件か 2 件以上なら押さずに失敗する**。通知はまず**サンプルのバナーの根**（label が `MacLibraryExample, <題>, ` で始まる group がちょうど 1 つ）を取り、`Options`・テキストの欄はその**子孫だけ**から取る（U-5）。この Mac の表示の言語は変えない | 同じ（根を足した） | VM で、今の Clipboard の補助が文字 `Clipboard Example` で別の要素（ツールバーの題）を押していた（9.0 の 2）。通知センターには「Tips」の通知と、その `Options` が同時にあり、`nc.menuButtons["Options"].firstMatch` はサンプルのものと限らなかった（9.0 の 4）。前の回の広がったサンプルの通知が一覧に残り、`label CONTAINS <題>` の `firstMatch` がそれを掴んだ（9.0 の 5） |
| U-3 | 結果の行の読み方 | 0b で、3 つの画面の結果の行に identifier（`<画面>.result`）を付け、**`accessibilityValue` を `#<通し番号> <本文>` の 1 つの値にする**（Clipboard と同じ）。番号は本文を変えるのと同じ処理で 1 増やす（積み方は今のまま変えない。4.2）。待ち方は画面ごとの**印**で決める: Notification・Share は本文の `[<label>]`、Dialog は `ShowDialog - result:` などの決まった前置き。モーダル・パネル・ピッカーを出すボタンは**2 段の口**（`begin` で番号を記録 → システムの UI を操作 → 記録した番号より新しい結果を待つ）で扱う。どの完了も、期待の結果が出た後 **2 秒待って番号が 1 つ先から増えないこと**（余分な完了が無いこと）を確かめる（共通の補助。U-14 の固定の待ちの例外） | **決め直す** | 本文と番号を別に読むと食い違いうる（Clipboard の R-SA24）。0e は Share と通知の完了の道を変えるので、二重の完了を全文だけでは捕まえられない（レビュー v1 Claude B-8、Codex B-06・B-07） |
| U-4 | 通知を受けたことの確かめ方 | 0b で、通知の画面に**最後のイベント**（4.3）を出す。受け手は**アプリの起動の処理（`MacLibraryExampleApp.init`）の 1 か所だけ**で設定し、**受け手を設定してから `setup()` を呼ぶ**。`MacLibrary` が main に積んで呼ぶ受け手の中で、ロックで守ったアプリ全体の入れ物に同期で書く（今の `MacNotificationManager` は、受け手を `DispatchQueue.main.async` で main に積み、`completionHandler()` は `defer` で `didReceive` から戻るときに呼ぶ。受け手が走るのはその後。`MacNotificationManager.swift:354-368`。0e で受け手の型が変わっても、受け手の中で同期に書く形を保つ）。**通知の画面の `onAppear` で受け手を設定し直すのをやめる**（今は受け手を 1 つしか持たず、画面を開くと起動の処理の受け手が上書きされる。`NotificationSampleView.swift:291-301`）。結果の行の今の文（`[actionReceived] ...`）は、画面が入れ物の合図を受けて同じ文で出す | 同じ（macOS の上書きの穴を足した） | 0a の M-7。コールドスタートでは画面ができる前にイベントが来る。macOS ではプロセスが背景で止められないので、iOS の「`completionHandler` の前に保存する」心配は当たらない（レビュー v1 Claude C-5） |
| U-5 | 通知の操作の経路 | **バナーだけを使う**。本文のクリック、根の中の `Options` → メニューの項目（`Open` / `Reply`）、根の中の `TextView` に入力 → Return。**操作のたびに（`Options` の前、項目の前、入力の前、Return の前）根を取り直し**、ちょうど 1 つで label が期待の錨に合い、`TextView` がその子孫でキーボードの焦点を持つことを確かめ、外れたら押さずに失敗する。メニューの項目は根の外のメニューに出るので、**根の `Options` を押した直後に開いたメニューの中で、identifier か title が期待のものがちょうど 1 つ**のときだけ押す（label は空なので使わない。ほかは Escape で閉じて失敗）。0b で返信の placeholder をサンプルにしか無い `MacLibraryExample reply` に変え、`TextView` をその placeholder でも絞る。**通知センターの一覧は、この Mac では開かない**（VM で 1 件だけ。5.9 の NC4）。`TextView` と焦点の確かめは入力と Return の段だけに当てる（`Options` と `Open` の段では `TextView` はまだ無い）。**VM で、`Reply` を選ぶと通知は通知センターの一覧（`AXNotificationListItems`）の中で広がった**（9.0 の 4）。この Mac で一覧を開くと私物の通知が画面に出るので、**N24・NC3 は、U-30 で「この Mac では一覧を開かずにバナーの中で入力できる」と分かるまで、この Mac では選ばない**（ランナーの `MAC_DEFERRED_TESTS`。`OS_ONLY_TESTS` とは別の表で、理由つきで一覧と基準に出す）。一覧が開く形だと分かったら、利用者に「一覧が開き私物の通知が画面に出る」ことを 6.5 で別に示して許可を得たときだけ流す | 同じ（根を足した） | VM のサンプルで、`Options` は根の子、メニューの項目は根の外（項目の総数 141、ほとんど label が無い）、`Reply` を選ぶと根の中に焦点を持つ `TextView` が出て、`Send` のボタンはどこにも無かった（9.0 の 4）。iOS の 0d の R-21（返信の欄と Send の根を、押す前・入力の前・Send の前に取り直す） |
| U-6 | 予約・表示の状態の確かめ方 | `GetScheduled` / `GetDelivered` の結果の行（`count=<n>, ids=[<id>, ...]`）で読む。反映を待つときは、**ボタンを押し直して新しい番号の結果を読み**、10 秒まで待つ（古い文を読み直すのではない）。押し直しは前の押下の結果（番号がちょうど 1 増えた結果）を読んでから次を押す直列にし、押した回数と番号の増分が等しいことを確かめる（間は 0.5 秒あける）。こうすると次の押下の結果を「余分な完了」と取り違えない（自己テストで確かめる）。`count=` と `ids` の要素の数が一致、重複なし、id の集合を比べる | 同じ | 結果の行は処理を待たずに出る（`NotificationSampleView.swift:143-165`） |
| U-7 | 通知の許可のテスト | **VM だけで流す**。各テストの前に、VM の中で `com.apple.ncprefs` の `apps` からサンプルの項目を消し、通知の daemon を立て直す（0a の `ncreset.sh`）。戻した後に AuthorizationStatus が `notDetermined` であることを読み、違えば権限の段を止める（0a の 5 回はどれも試作の id で、サンプルの id では確かめていない）。順は「戻す → NP2」「戻す → NP3」「戻す → NP1」で、許可で終える。問い合わせに答えるまでアプリを止めない（M-2）。権限の段のテストは普段の片付けをせず、段の終わりに VM で戻す。**この Mac では流さず、許可を変えない**。この Mac で `notification` のテストを流す前提（`authorized`）は、**何も押す前に** AuthorizationStatus だけを押して読み、`authorized` でなければほかを押さずに `NTK-PRECONDITION:notAuthorized` で止める | **決め直す** | 0a 4.4（VM の中でこの戻し方で 5 回とも未決に戻った）。サンプルの SetBadgeCount・Show* は未決なら問い合わせを出し（`runWithPermission`）、答える前にアプリが終わると拒否になる（M-2）。この文書の確かめでも、VM のサンプルは初めの状態が `notDetermined` だった（9.0 の 5） |
| U-8 | 割り込みの監視 | すべてのテストに、**何も押さない監視**を付ける: 割り込みが来たら押さずに `app.terminate()` し、印を「未知の割り込み」にして `true` を返す。ラベルは読まない。期待するシステムの UI は操作の前に明示して待って押す。XCUI の操作を包む関数は、操作の後に印を読み、立っていれば throw する。印が立った後は普通の片付け（`tearDownAfterGate`）を呼ばない。**監視が実際にテストを止めるかは VM で確かめてから採る**（`true` は「処理したので続けてよい」という契約で、止める命令ではない。9.1）。確かめるまでは、この Mac で流す入口の条件にする | **決め直す**（押す枝を外した） | 0a 4.3: macOS の XCTest は許可の問い合わせを勝手に押さなかった。Apple の「Handling UI Interruptions」の `true` の意味（レビュー v1 Codex B-01） |
| U-9 | 私物の Mac での宣言の区分と守り方 | 宣言の区分は 3.3 の 10 個。**既定はどれも許さない**。iOS の 3 本柱を写す。**柱 1**: この Mac では、宣言と `--allow` から「宣言した区分がすべて許されているテスト」を選び、1 件ずつ名指しする。VM だけの区分（`ncsettings`・`pasteprivacy`・`realservice`）のテスト、`VM_ONLY_TESTS`、OS の合わない `OS_ONLY_TESTS`、この Mac で保留する `MAC_DEFERRED_TESTS`、適格性の段だけの `QUALIFICATION_ONLY_TESTS` は選ばない（どの表のキーも宣言の表に無ければ止まる）。名指しが 0 件なら呼ばない。結果が名指しとちょうど同じでなければ止まる。**柱 2**: ①VM の列挙と宣言の表の完全一致、②クラスごとの宣言の下限、③固定した Clipboard のファイル、④閉じた形のソースの規則、⑤この Mac で組んだテストのバンドルの一覧をバイナリから読んで VM の列挙と照らす、⑥信頼する部分のハッシュ。**柱 3**: この Mac で流す前に毎回 `--dry-run` の一覧を見せて許可を得て、`--approved` で流す。許可の ID は台帳で 1 回限り。**VM の道**は柱 1・2 をそのまま、柱 3 の代わりに VM の資格の確かめ（6.3）。二段目（テストの中）は、基底が `TEST_RUNNER_NTK_HOST` と `TEST_RUNNER_NTK_ALLOW` を読み、**`vm` と申告されたら基底自身も `sysctl kern.hv_vmm_present` が 1 であることを確かめ**、違えば throw する（環境変数を写した取り違えで全区分が許されないように）。`vm` ちょうどでない値は、この Mac として扱う | 同じ（VM を事実で見る形を足した） | D-23。レビュー v1 Claude B-5 |
| U-10 | 一般の貼り付け板を使うテスト | `clipboard` を宣言する。ランナーからの書き込みは `Support/RunnerPasteboard.swift` だけが行い、書いた直後とサンプルで読む操作の直前とで `changeCount` が変わっていないことを確かめる。**利用者の元の内容は読まず、退避も戻しもしない**。共有の `Copy` の後に貼り付け板を読むのは、テストが先に合成の内容を書いて私物を置き換えた後だけ（読むのはテストが書いた後の内容で、失敗のときも元の私物を読まない）。この Mac で `clipboard` を許す条件は、流す間 Handoff とユニバーサルクリップボードを切ってもらうこと。固定した Clipboard のクラス（`RunnerPasteboard` を通らない）は例外として明示し、そこで新しい読み取りを増やさない | 同じ | 決まりの「Mac のクリップボード」。レビュー v1 Codex B-03 |
| U-11 | パネルの保存先と開く場所 | ランナーが流す前に `/private/tmp/ntk-uitest-<実行の ID>/`（fixture）を作り、`a.txt`・`b.txt`・`note.md`・`pic.png`・`dirA/`・`dirB/`・`default.txt` を置き、場所を `TEST_RUNNER_NTK_FIXTURE_DIR` で渡す。パネルが開いたら、**どこで開いても** Cmd+Shift+G で fixture に移り、**移った先の今の場所が fixture であることを確かめてから**選ぶ。fixture の外の項目には触れない。保存のパネルは `MacLibrary` がファイルを書かない（パスを返すだけ）ので、ランナーは流した後に fixture の中身（名前・種類・ハッシュ）が変わっていないことを照らす。fixture を作る・照らす・消すときは symlink を辿らない。終わったら消す | **決め直す** | サンプルは `directoryURL: nil` で開く。VM のサンプルで、Cmd+Shift+G で `/private/tmp/...` に移り、`a.txt` を選んで `OKButton` で開け、保存のパネルは `Replace` を経てパスだけを返し、fixture は変わらなかった（9.0 の 3）。逃げ道の `directoryURL`: sandbox ありの試作で、コンテナーの外（`/private/tmp`）を渡すと、そこで開いた（9.0 の 3。0a で無視されたのはコンテナーの中の道だった） |
| U-12 | 貼り付け板のプライバシーの確認のテスト | **VM だけ**（`pasteprivacy`）。その段の前に VM の中でサンプルの設定の領域（sandbox のコンテナー）に `EnablePasteboardPrivacyDeveloperPreview` を入れ、段の後に**元の値に戻す**（無かったなら消す）。確認は同じ中身では 2 回目に出ないので、ランナーは毎回新しい中身を書く。確認はアプリの木の `Dialog` の identifier（`action-button--999` が許可、`--998` が拒否）で押す | **決め直す** | 0a 4.3（試作で 3/3）。この Mac は企画 0 章の測り（macOS 26.3 のとき）で `accessBehavior` の既定が `alwaysAllow` だった。26.7.3 では測っていない |
| U-13 | 実在のサービスへ送らない | ピッカーで押してよいのは、**Escape と、26 の `Copy` だけ**。`Copy` はピッカーの中で `.element` で取る。サービスを名指しする 3 つ（ShareViaMail・CanPerformMail・ShareUnknownService）は **VM だけ**（`realservice`。CanPerformMail と ShareUnknownService は今は画面を開かないが、壊れると Mail の作成を開きうる道を通るため）。流した後に VM の Mail を止める。**この Mac ではピッカーのサービスの名前を読まず書かず、階層を出さない** | 同じ（Mail を足した） | 決まりの「実のサービスへ送らない」。0a 4.2 |
| U-14 | 待ち時間 | **固定の待ちは使わない**（期限つきで読み直す）。例外は (a)「出ない」「来ない」ことの確かめ（取り消した予約が出ない: 予約の時刻 + 5 秒、問い合わせが出ない: 5 秒、ピッカーが出ない: 2 秒、余分な完了やイベントが来ない: 2 秒、確認が出ない: 2 秒、category の無い通知に `Options` が無い: 根が出てから 2 秒）、(b) **バナーが出てから 1 秒待って押す**（0a 4.3 の相関による暫定の策で、原因は分かっていない）、(c) **+1 分の予約を押す前に、時計の秒が 5〜30 秒の間になるまで待つ**（今の時刻から次の窓の始まりまでを計算して待つ。最大は秒 30.x から次の分の 5 秒までの約 35 秒なので、期限は 40 秒。サンプルは秒を 0 に切るので、発火は押してから 30〜55 秒後になり、予約を読む余裕ができる。窓の計算は純粋な関数にし、秒 30.0・30.5・31・59・4.9 の入力で自己テストする。U-14c）。(a) の「余分な完了が 2 秒来ない」は、反映を待つ押し直し（U-6）の途中の結果には当てず、**期待の値を読んだ最後の 1 回の後だけ**に当てる | 同じ（(b)(c) を足した） | `NotificationSampleView.swift:329-334`（`components.second = 0`。iOS のサンプルは秒を残す）。レビュー v1 Claude A-4、Codex B-04 |
| U-15 | テストの独立と順 | テストごとにアプリを `launch` し直す。起動の引数に `-ApplePersistenceIgnoreState YES` を付ける（窓の位置と大きさを固定するものではない。窓は起動の後に、画面の中に収まることだけを確かめる）。**通知のクラスの setUp** で、アプリの中の片付け（`RemoveAllDelivered`・`CancelAllScheduled`。どちらも問い合わせを出さない）をし、サンプルのバナーの根が 0 件になるまで最大 15 秒待つ。0 件にならなければ押さずに失敗する。**片付けは、そのテストが `NotificationToken` を受け取ったときだけ**、同じ 2 つのボタンで行う。`SetBadgeCount(0)` は `badge` を宣言したテストが、AuthorizationStatus が `authorized` と読めたときだけ押す。category を外すテスト（N20）は最後に登録し直す。後ろにするときは Finder を前に出す（0a で確かめた手段。サンプルを Cmd+H で隠す案は、隠した後の前面のアプリが決まらないので採らない）。終わりに、テストが前に出したアプリを、流す前に動いていなかったものだけ止める。直列で流す | 同じ（片付けを許可の中に収めた） | レビュー v1 Claude A-1・B-16、Codex A-01。VM で、前の回の広がったサンプルの通知が一覧に残り、`RemoveAllDelivered` の後 15 秒たっても消えなかった（9.0 の 5） |
| U-16 | 試験の環境 | **VM（15.8.3、Xcode 26.3、en-US）と、この Mac（26.7.3）の 2 つで流し、それぞれ基準を取る**（D-21）。版で振る舞いが違う所だけ `OS_ONLY_TESTS` で分ける。分かっているのは「15 のピッカーに `Copy` が無い」（M-3）と「15.8.3 のサンプルで戻るボタンを押せない」（9.0 の 2）。26 の振る舞いは U-30 で確かめてから表に入れる | 同じ | D-21 |
| U-17 | 識別子の名前 | Clipboard に合わせる: `menu.<画面>`、`<画面>.result`、`<画面>.button.<名前>`、`<画面>.section.<名前>`。ボタンの `<名前>` はボタンの文字から括弧の中を除いたもの（大文字で始まるまま）。`SetBadgeCount1` / `SetBadgeCount0` だけ数字を残す。名前は画面ごとの enum を唯一の出どころにし、テストの側の写しが enum と同じであることを I1 と 5.7 の照合で確かめる | **決め直す** | 今の Clipboard は `clipboard.button.CopyText` の形 |
| U-18 | 実行の選び方 | テストプランは作らない。`build-for-testing` の後、`test-without-building -xctestrun` を呼ぶ。**VM でもこの Mac でも、計画から導いたメソッドの集合を名指しする**（`--feature`、VM だけ・OS だけの除外を当てた後の集合。VM の既定はクラスごとの呼び出しに分けるが、名指しはメソッド）。権限の段（`NotificationPermissionUITests`）は `--feature` が無いときと `Notification` のときだけ、貼り付けの確認の段（`ClipboardPrivacyUITests`）は無いときと `Clipboard` のときだけ行う | 同じ | レビュー v1 Codex B-10 |
| U-19 | 人の確認 | 2.2 のとおり、computer use で **VM のウインドウ**を見る（この Mac の画面が写るので毎回許可） | **決め直す**（見る画面） | 企画 7.2、決まりの区分 3 |
| U-20 | 画面の共有中の通知の設定 | **VM**: ランナーが毎回 `dnd_prefs.dndMirrored` を `false` にする。**この Mac**: 利用者に「画面のミラーリング中または共有中に通知を許可」をオンにしてもらう。ランナーはこの Mac の通知の設定を読まず変えない。**見張り（N4）は、`notification` のテストを選んだ回だけ**、許可の一覧に「見張り」と書いて最初に流す。見張りが落ちたら、その回の残りの `notification` のテストを流さず「前提か表示の経路が成り立たない」と報告し、流さなかったテストは失敗に数える（成功にしない）。設定が原因と決めつけない | 新しい | 0a 4.1・M-1。レビュー v1 Codex A-02 |
| U-21 | LaunchServices のコピー | 宣言 `coldstart`（止まっているサンプルを通知から起こすテスト）と、ランナーの操作「余分なコピーを外す」を分ける。**VM**: ランナーが流す前に、`lsregister -dump` からサンプルとランナーの bundle id の行だけを取り出し、今の実行の DerivedData の外のものを外す。**この Mac**: `coldstart` のテストを選んだ回だけ数え、余分があれば流さない。外すのは、`--dry-run` の一覧に「外すコピー」を**不透明な印**（実体のパス（`realpath`）の SHA-256 の先頭 12 文字）と**置き場所の種類**（`DerivedData の下`、`リポジトリの下`、`/Applications の下`、`そのほか`。パスそのものは出さない）で固定し、許可を得たときだけ（`--allow-lsregister`）。種類だけで決められないときのために、利用者が自分の端末で一覧を見る命令（`lsregister -dump` をサンプルの bundle id で絞るもの）を示す。エージェントはその出力を読まない。流す直前に集合を照らし直し、新しいコピーが見つかれば外さずに止まる。ランナーが組んだ一時のコピーは、消す前に自分の登録を外す（その回の許可の一覧に書く）。0b で、サンプルに**起動したコピーの印**（`notification.launchCopy`）を出し、コールドスタートでは、ランナーが今の実行の実体のパス（`realpath`）から計算して渡した値（`TEST_RUNNER_NTK_EXPECTED_COPY`）と同じであることを確かめる（サンプルの `bundlePath` が実体のパスかは 9.1）。印はコピーの場所の検出で、同じビルドの証明ではないので、ビルドの同一性はランナーのハッシュの照合で別に保つ | 新しい | 決まりの「1 回ごとに聞く操作」。0a 4.5。レビュー v1 Claude B-6、Codex A-11 |

### 3.3 宣言の区分（U-9）

| 区分 | 中身 | この Mac で |
|---|---|---|
| `notification` | 通知を出す・予約する・更新する、バナーを押す・`Options` を開く、問い合わせを出しうるボタン（Show*・Schedule*・UpdateById・RequestPermission・SetBadgeCount。`runWithPermission`。`NotificationSampleView.swift:336-365`） | 許可で流す。集中モード、U-20 の設定、`authorized` が前提 |
| `ncsettings` | 通知の許可の状態を変える（問い合わせに答える、許可を戻す） | **流さない**（VM だけ） |
| `settings` | システム設定を開く（OpenNotificationSettings） | 許可で流す。中は読まず押さない |
| `badge` | Dock のサンプルのバッジを変える・読む | 許可で流す |
| `clipboard` | 一般の貼り付け板を書く・読む・消す（共有の `Copy`、`PasteButton` を含む） | 許可で流す。Handoff とユニバーサルクリップボードを切る前提（U-10） |
| `pasteprivacy` | 貼り付け板のプライバシーのプレビューの設定を入れて確認を出す | **流さない**（VM だけ） |
| `sharepicker` | 共有のピッカーを開く・開きうる（エラーの経路を含む） | 許可で流す。押すのは Escape と 26 の `Copy` だけ |
| `realservice` | サービスを名指しして直接使う道（Mail の作成を開きうる） | **流さない**（VM だけ） |
| `panels` | 開く・保存のパネルを出す（ファイルの一覧が画面に出る） | 許可で流す。fixture の外に触れない（U-11） |
| `coldstart` | 止まっているサンプルを通知から起こす（LaunchServices の登録に依る） | 許可で流す。余分なコピーがあれば流さない（U-21） |

ランナーの操作のうち、許可の一覧に別に書くもの: 余分なコピーを外す（`--allow-lsregister`）、組んだ一時のコピーの登録を外す、fixture を作って消す。

### 3.4 外へ出すものの境界（この Mac）

この Mac の道で、生のものは**一時フォルダー（`umask 077`、所有者だけが読める）の中にだけ**置き、会話・端末・リポジトリへは出さない: xcodebuild の標準出力と標準エラー、`.xcresult`（スクリーンショットと画面の動画が入りうる）、`xcresulttool` の JSON（失敗の文、assert の場所の `#filePath` にホームのパスが入る）、LaunchServices の dump。

外へ出してよいのは、ランナーが**許す形だけを決めた一覧**（純粋な関数で作り、自己テストつき）に通したものだけ:

| 種類 | 値 |
|---|---|
| テスト | キー（`<クラス>/<メソッド>`）、結果の種類（passed / failed / skipped / 区分で除いた / VM だけ / OS だけ / この Mac で保留 / 見張りで止めた / 通知の UI で止めた）、数、時間（秒） |
| 理由の符号 | `NTK-GATED:<区分>`、`NTK-PRECONDITION:<名前>`、`NTK-INTERRUPTED`、`NTK-STOP:<名前>`、`NTK-STALE:<名前>`、**`NTK-STEP:<段>`**（テストが投げる失敗に付ける段の符号。語彙は `Support/StepCode.swift` の enum に限り、ランナーは失敗の文から `NTK-STEP:[A-Za-z0-9_-]+` に合う部分だけを取り出し、enum の写しにある値だけを通す。ほかの文字は捨てる） |
| 環境 | `where`、OS の版とビルド、arch、言語、Xcode の版、署名の形（`team` / `adhoc` の 2 値。ID は出さない） |
| ソース | `HEAD`、`mac/` の木のハッシュ、宣言の表・除外の表・監査の表のハッシュ、`allowed` |
| VM の資格 | 項目ごとの合否と、出どころの符号（例 `cirrus-vanilla-15.7.7+15.8.3`）。生の `IOPlatformUUID`・IP・known_hosts の鍵・ユーザーのパスは出さない（照らすのは実行の中だけ） |
| LaunchServices | 数、不透明な印、置き場所の種類 |
| ビルド | 成否 |

失敗の文そのものは出さない。この Mac でしか流れないテスト（M1b・M2・C9・S2・S4 と、U-30 で 26 にしか無いと分かる振る舞い）の失敗は、`NTK-STEP` の段の符号でどの段かを知り、それでも足りなければ、利用者の許可を得て利用者が自分の端末で `.xcresult` を見る（エージェントは読まない）。基準のファイルもこの一覧の値だけで作る。

VM の道の生のものは合成のデータだけなので VM に残してよいが、この Mac に持ち帰るのは同じ一覧の値と、押したボタンの記録の添付（5.7）だけにする。持ち帰り先 `mac/MacLibraryExample/build/test_mac/` は 0d で `mac/.gitignore` に足し、木の照合と受け渡しの両方から除く（今は git の外になっていない。レビュー v1 Claude B-13）。

## 4. 段階 0b で足す識別子と表示

### 4.1 一覧

| 画面 | 要素 | 識別子 |
|---|---|---|
| メニュー（`ContentView.swift`） | 4 つのカード（今はどれも識別子が無い） | `menu.dialog`、`menu.notification`、`menu.share`、`menu.clipboard` |
| Dialog | 結果の行（`#<n> <本文>`） | `dialog.result` |
| Dialog | 結果の履歴（直近 3 件を番号つきでつないだ値 `#5 <本文> / #4 <本文> / #3 <本文>`。D5 でヘルプの中間の結果を読むため。番号と本文を 1 つの値で読む。U-3） | `dialog.resultHistory` |
| Dialog | ボタン 6 | `dialog.button.` の後ろに `ShowDialog`、`ShowFileDialog`、`ShowMultiFileDialog`、`ShowFolderDialog`、`ShowMultiFolderDialog`、`ShowSaveFileDialog` |
| Notification | 結果の行 | `notification.result` |
| Notification | 最後のイベント（4.3） | `notification.lastEvent` |
| Notification | 起動したコピーの印（U-21） | `notification.launchCopy` |
| Notification | 節 7 | `notification.section.` の後ろに `permission`、`show`、`updateCancelRemove`、`schedule`、`query`、`badge`、`category` |
| Notification | ボタン 22 | `notification.button.` の後ろに `RequestPermission`、`HasPermission`、`AuthorizationStatus`、`OpenNotificationSettings`、`ShowImmediate`、`ShowTimeInterval`、`ShowCalendar`、`UpdateById`、`CancelById`、`CancelAll`、`RemoveDeliveredById`、`RemoveAllDelivered`、`ScheduleTimeInterval`、`ScheduleCalendar`、`CancelScheduledById`、`CancelAllScheduled`、`GetScheduled`、`GetDelivered`、`SetBadgeCount1`、`SetBadgeCount0`、`RegisterCategory`、`RemoveCategory` |
| Share | 結果の行 | `share.result` |
| Share | 節 5 | `share.section.` の後ろに `pickerBasic`、`pickerMultiple`、`pickerFilter`、`directService`、`error` |
| Share | ボタン 15 | `share.button.` の後ろに `ShareText`、`ShareURL`、`ShareImage`、`ShareFile`、`ShareMultipleImages`、`ShareMultipleFiles`、`ShareTextAndURL`、`ShareExcludingServices`、`ShareViaMail`、`CanPerformMail`、`ShareEmpty`、`ShareInvalidURL`、`ShareMissingFile`、`ShareMissingImage`、`ShareUnknownService` |
| Clipboard（既存。変えない） | 固定の表示 7、貼り付けのボタンの入れ物 1、節 10、ボタン 36 | `clipboard.result`、`.scopePicker`、`.activeScope`、`.resultSequence`、`.observeStatus`、`.reachedCodes`、`.toggle.localOnly`、`clipboard.pasteButton`、`clipboard.section.<10 個>`、`clipboard.button.<名前>`（`sampleButton("<名前>")` の 36 個） |

数: メニュー 4、Dialog 8、Notification 32、Share 21。新規は計 65。Clipboard は今の 54 を変えない。I1a〜I1d（5.1）は画面ごとにこの数と完全に一致することを確かめる。

### 4.2 結果の行の番号（U-3）

- 3 つの画面の `updateResult` は、本文を変えるのと同じ処理の中で `resultSequence += 1` を行い、結果の行に `.accessibilityIdentifier("<画面>.result")` と `.accessibilityValue("#\(resultSequence) \(resultText)")` を付ける（Clipboard の 51〜55 行と同じ）。見た目は変わらない
- **積み方は変えない**: Notification・Share は今のまま `DispatchQueue.main.async` の中、Dialog は今のまま同期で `@State` を変える。Dialog を main に積む形に変えると、今の出し方（A）ではアラートが開いている間 main キューが捌かれず（1a-6）、D5 のヘルプの結果の表示が閉じるまで遅れる形に変わるため（レビュー v1 Claude B-12）。積み方をそろえるのは 0e でまとめて行い、D5 の見え方が変わるかをそこで確かめる
- Dialog は `dialog.resultHistory` に直近 3 件の本文を持つ（D5）

### 4.3 最後のイベント（通知の画面）

| 項目 | 表示と `accessibilityValue` | 初め |
|---|---|---|
| `notification.lastEvent` | `#<通し番号> kind=<action\|textInput> notificationId=<id> actionId=<id> userText=<文字\|-> userInfo=<キーの順に並べた key:value をカンマでつないだもの\|->`（1 つの値） | `#0 kind=none notificationId=- actionId=- userText=- userInfo=-` |
| `notification.launchCopy` | `copy=<Bundle.main.bundlePath の SHA-256 の先頭 12 文字>` | 起動のたびに同じ値 |

- 入れ物: アプリ全体で 1 つの `final class`（例 `NotificationEventLog.shared`）。中身は `Synchronization` の `Mutex`（macOS 15 から）か `NSLock` で守り、`record(...)` は呼ばれたスレッドで同期に書いて戻る。永続化しない
- userInfo は受け手に渡る JSON の文字列を読み、文字列の値だけを `key:value` にしてキーの順に並べる（今のサンプルは `source` と `id` を送る。`NotificationSampleView.swift:317-327`）。読めなければ `userInfo=?`
- 受け手は `MacLibraryExampleApp.init` で設定し、`Log.d` を残したまま `record` を呼ぶ。その後に `setup()` を呼ぶ（U-4）
- 画面: iOS と同じく `@MainActor final class NotificationEventViewModel: ObservableObject`、`@Published private(set) var snapshot`、画面は `@StateObject` で持ち、`onAppear` で入れ物から取り直す。`record` は書いた後に `DispatchQueue.main.async` で「取り直せ」の合図だけを送る（値は運ばない）。合図で結果の行にも今と同じ文を出す
- 置き場所: 結果の行のすぐ下（スクロールの外）

### 4.4 0b のサンプルの変更の一覧

| 所 | 変更 | 見た目・動作 |
|---|---|---|
| `ContentView.swift` | 4 つのカードに識別子 | 変わらない |
| `DialogSampleView.swift` | 識別子、結果の行の番号、結果の履歴 | 履歴の行が 1 つ増える |
| `NotificationSampleView.swift` | 識別子、結果の行の番号、最後のイベントとコピーの印の表示、`onAppear` の受け手の設定をやめて入れ物を読む形にする、**返信の placeholder を `Type message` から `MacLibraryExample reply` に変える**（U-5）、節の入れ物に `.accessibilityElement(children: .contain)` を付ける（`ClipboardSampleView.swift:843-846` と同じ。付けないと節の識別子が中のボタンに押し付けられる） | 表示が 2 行増える。返信の欄の薄い文字が変わる。結果の行のイベントの文は今と同じ |
| `ShareSampleView.swift` | 識別子、結果の行の番号、節の入れ物に `.contain` | 変わらない |
| `MacLibraryExampleApp.swift` | 受け手を設定してから `setup()`、入れ物に書く | 変わらない |

`MacLibrary` は変えない。0b の後、VM で今の UI テストを流し、**0a の既知の失敗（Share の 3 件と C9）からの差が増えないこと**を確かめる（Share の置き換えは 0c。レビュー v1 Codex C-02）。

## 5. テストケース

### 5.0 共通

- 表の列: **宣言**（宣言の区分。`-` は無し）、**私物**（「3」「2・3」「1 相当」）、**流す所**（`VM・Mac` は VM と、許可を得たこの Mac の両方。`VM だけ`、`Mac だけ（26）`）、**自動か人か**（`自動*` は、サンプルで 3 回通ったことをまだ確かめていない項目で、0c の最初に VM で 3 回流して期待値を確定する。だめなら人の確認に移す）
- 期待値の結果の行は全文の完全一致（U-1）。「番号」は `#<n>` の増分（U-3）。完了を返すボタンは、期待の結果の後 2 秒で番号が増えないことも見る（U-3）
- **押す前の確かめ**（`SampleApp` の包む関数。**新しいテストも、固定した Clipboard のテストも、すべての押下・スクロール・キー入力がこの口を通る**。レビュー v2 Codex A-01・A-02、Claude A-1）: (1) サンプルが `runningForeground`。(2) **押す点を覆う最前面の窓の持ち主**が、その操作に許した持ち主（サンプルのプロセス。パネルは sandbox の view service、通知の操作は `com.apple.notificationcenterui`）であること。`CGWindowListCopyWindowInfo`（画面にある窓だけ、前から順）で、点を含む最初の窓の持ち主の PID・枠・層だけを読み、名前・題・階層は読まない。持ち主が分からない・読めない・ほかのプロセスなら押さない（読めることは 9.1 で VM で確かめる。読めなければこの Mac では UI テストを流さない）。(3) 通知の操作でない押下では、**`com.apple.notificationcenterui` のすべての窓の枠**と重ならないこと（枠だけを読み、label は読まない）。重なるなら最大 10 秒待ち、消えなければ押さずに失敗する。(2)・(3) を読む口は印を要らない**読むだけの口**（`SampleApp.overlayCheck`。iOS の `remainingAlertCount` と同じ読むだけの例外）で、信頼する部分に入れる。印の無いテスト（N1・N17、Dialog・Share・Clipboard・I1）もこの口で確かめる
- **通知のテストの前提**（U-7）: 何も押す前に AuthorizationStatus を読む。VM は権限の段が許可で終えている。通知のクラスの setUp の「根が 0 件の待ち」も読むだけの口で行い、N1・N17 では待つだけで何も押さない
- **この Mac で通知のテストが途中で落ちたら**（setUp の根の待ち、または操作の途中）、通知のテストだけでなく**その回の残りの UI テストをすべて流さない**（`NTK-STOP:notificationUI`。流さなかったテストは失敗に数える）。「通知センターが開いたままかもしれない。閉じてから新しい許可で流し直す」と知らせる。この Mac には VM の daemon の立て直しに当たる戻し方が無いため
- **時間切れ**: すべての呼び出しに `-test-timeouts-enabled YES`、`-default-test-execution-time-allowance 120`、`-maximum-test-execution-time-allowance 240` を付ける（Xcode 26.3 の `xcodebuild -help` にある。事実）。+1 分の予約を待つテストは `executionTimeAllowance` を 240 秒にする。ランナーも呼び出しごとの時間切れを持ち、時間切れの後は 6.3 の中断の順で止める（パネルやピッカーが私物を出したまま残らないように）
- **+1 分の予約**は、押す前に秒の窓を待つ（U-14c）
- この Mac では、失敗の文・パス・システムの UI のラベル・ほかのアプリの文字を外へ出さない（3.4）

### 5.1 メニューと識別子（`NavigationUITests`、`IdentifierInventoryUITests`）

**戻るボタン**: VM のサンプル（15.8.3）では、ツールバーの戻るボタン（identifier `chevron.backward`、label `Back`）を、クリック、Cmd+[、ボタンの中の座標、1 秒待ってからのクリック、0.2 秒の長押し、hover の後のクリックの 6 通りで押しても、Clipboard と Dialog のどちらの画面からもメニューに戻らなかった（9.0 の 2）。原因は分からない。そのため、戻る操作を使うテストは **26 だけ**（`OS_ONLY_TESTS`）にし、15 では画面を開くところまでを確かめる（U-33）。26 で戻れるかは U-30 で確かめる。

| ID | 操作 | 確かめる内容 | 宣言 | 私物 | 流す所 | 自動か人か |
|---|---|---|---|---|---|---|
| M1a | 起動し直しながら、`menu.dialog` / `menu.notification` / `menu.share` / `menu.clipboard` で各画面を開く | 各画面の `<画面>.result` が出る（Clipboard の画面を開くだけでは貼り付け板に触れない: 開くと `makePasteButton` で受け手を登録するだけ） | - | 3 | VM・Mac | 自動* |
| M1b | 各画面を開き、戻るボタン（`chevron.backward` がちょうど 1 つ）で戻る | メニューのカードが出る | - | 3 | Mac だけ（26） | 自動*（15 では押せない） |
| M2 | Dialog で ShowDialog → `OK` → 戻る → 開き直す。Notification は HasPermission で同じ | 開き直すと結果の行が `#0 Result will be displayed here` に戻る（`@State`）。Share は、何も起こさないボタンが無いので入れない（ShareEmpty は壊れるとピッカーを開きうる。レビュー v1 Codex A-03） | - | 3 | Mac だけ（26） | 自動* |
| I1a | Dialog の画面のボタンをすべて集める（ウインドウのボタン `_XCUI:*`、ツールバーの戻るボタン、スクロールバーの部品は明示して除く） | 残ったボタンがすべて `dialog.button.` の識別子を持ち、集合が 4.1 と完全に一致し、件数が一致し、重複が無い。`dialog.result`・`dialog.resultHistory` がある | - | 3 | VM・Mac | 自動* |
| I1b | Notification の画面で同じ（押さない） | 同じ。ボタンでない識別子は結果、最後のイベント、コピーの印、節 7 | - | 3 | VM・Mac | 自動* |
| I1c | Share の画面で同じ | 同じ。ボタンでない識別子は結果と節 5 | - | 3 | VM・Mac | 自動* |
| I1d | Clipboard の画面で同じ。`clipboard.pasteButton` の中の `PasteButton` と範囲のピッカーの部品は除く | 同じ（`clipboard.button.` の 36 個）。ボタンでない識別子は固定の表示 7、入れ物 1、節 10 | - | 3 | VM・Mac | 自動* |

I1 の集め方は iOS の 3.1 と同じ。VM の Clipboard の画面の階層には、識別子の無い `Button` がスクロールの縦の端に 2 つあった（9.0 の 2。スクロールバーの部品と見ている。推測）ので、除き方は 0c の最初に決める。戻るボタンの除き方は「`chevron.backward` か、26 で見つかった形のボタンがちょうど 1 つ」にする（U-30 で 26 の形を確かめる）。

### 5.2 Dialog（`DialogUITests`）

サンプルのボタン 6 つ。アラートはアプリの木の `Dialog`（label `alert`）、パネルは `open-panel` / `save-panel`、パネルの確定は `OKButton`、取り消しは `CancelButton`（9.0 の 3）。結果の行は `ShowDialog - result: DialogResult(...)` の形。開くパネルの結果は VM で `ShowFileDialog - result: OpenDialogResult(filePaths: ["<fixture>/a.txt"], fileCount: 1, directoryURL: "<fixture>", isCancelled: false, isSuccess: true)`、保存のパネルは `ShowSaveFileDialog - result: SaveDialogResult(filePath: "<fixture>/default.txt", fileCount: 1, directoryURL: "<fixture>", isCancelled: false, isSuccess: true)` だった（9.0 の 3）。アラートの全文は 0c の最初に VM の実物から写す。

| ID | 操作 | 確かめる内容 | 宣言 | 私物 | 流す所 | 自動か人か |
|---|---|---|---|---|---|---|
| D1 | ShowDialog → `OK` | 題 `Hello from macOS`、本文 `This is a native macOS dialog!`、ボタン `OK`・`Cancel`・`Delete`（`action-button-1`〜`-3`）、`Help`、チェックボックス `Don't show this again`。押した後、buttonIndex 0・`OK`・suppression false・help false の全文。番号 +1、余分なし | - | 3 | VM・Mac | 自動* |
| D2 | ShowDialog → `Cancel` | buttonIndex 1 | - | 3 | VM・Mac | 自動* |
| D3 | ShowDialog → `Delete` | buttonIndex 2（`alertThirdButtonReturn`） | - | 3 | VM・Mac | 自動* |
| D4 | ShowDialog → チェックボックスを入れる → `OK` | suppression true | - | 3 | VM・Mac | 自動* |
| D5 | ShowDialog → `Help` → `OK` | **今の動作**: 完了が 2 回来る（ヘルプで buttonIndex -1・help true、`OK` でもう 1 回。`MacDialogManager.swift:821-835`、`:325-327`）。`dialog.resultHistory` だけを読み、押す前の番号 n に続く `#n+2 <OK の全文> / #n+1 <ヘルプの全文>` であること（番号が続き、2 つの全文が順に合う）。2 秒待っても増えない。1b でヘルプをイベントにしたら DH1 に替える | - | 3 | VM・Mac | 自動* |
| D6 | ShowDialog を 3 回出し、Return・Escape・`d` のキーで閉じる | Return で `OK`（既定）、Escape で `Cancel`（`\u{1b}`）、`d` で `Delete`（`keyEquivalent` が `d`。`DialogSampleView.swift:36`） | - | 3 | VM・Mac | 自動* |
| D7 | ShowFileDialog → `CancelButton` | 取り消しの結果（`isCancelled: true`、`directoryURL: ""`）。番号 +1 | `panels` | 2・3 | VM・Mac | 自動* |
| D8 | ShowFileDialog → fixture へ移る（U-11）→ `a.txt` → `OKButton` | 上の全文（`<fixture>` に置き換え） | `panels` | 2・3 | VM・Mac | 自動*（VM で 2 回のうち 1 回通り、1 回は `a.txt` を押す所で「アプリの idle を待つ」まま止まった。9.0 の 3） |
| D9 | ShowFileDialog → fixture → `note.md` | 選べないことは自動では読めない（VM で `isEnabled == true`）。**HC7 に移す**。自動では fixture に移れることだけを見て `CancelButton` | `panels` | 2・3 | VM・Mac | 自動*（絞り込みは人） |
| D10 | ShowMultiFileDialog → fixture → `a.txt` と `pic.png` → `OKButton` | 2 件のパスが集合で一致 | `panels` | 2・3 | VM・Mac | 自動* |
| D11 | ShowFolderDialog → fixture → `dirA` → `OKButton` | `<fixture>/dirA` | `panels` | 2・3 | VM・Mac | 自動* |
| D12 | ShowMultiFolderDialog → fixture → `dirA` と `dirB` → `OKButton` | 2 件 | `panels` | 2・3 | VM・Mac | 自動* |
| D13 | ShowSaveFileDialog → fixture → 既定の名前 → `Save` → `Replace` | 上の全文。fixture の中身が変わらない（ランナーが照らす） | `panels` | 2・3 | VM・Mac | 自動*（VM で 1 回通った） |
| D14 | ShowSaveFileDialog → `CancelButton` | 取り消しの結果 | `panels` | 2・3 | VM・Mac | 自動* |
| D15 | ShowSaveFileDialog → fixture → 名前を `new-file` → `Save` | 置き換えの確認が 2 秒出ない。`<fixture>/new-file.txt`。fixture は変わらない | `panels` | 2・3 | VM・Mac | 自動* |
| D16 | ShowDialog を 3 回（`OK`・`Cancel`・`Delete`） | どの回も増分がちょうど 1 | - | 3 | VM・Mac | 自動* |
| D17 | 5 つのパネルを 1 回ずつ出して `CancelButton` | どの回も増分がちょうど 1 | `panels` | 2・3 | VM・Mac | 自動* |

テストに入れないもの: 検証の失敗（空の題、ボタンなし、既定のボタン 2 つ以上、アイコンの不正）。サンプルから起こせない。単体テスト（今は Dialog の単体テストが 0 件。企画 7 章）は Swift の API の設計で扱う。

### 5.3 Notification

サンプルのボタン 22。id は `mac-sample-notification`、`mac-sample-notification-<秒>`（ShowImmediate）、`mac-sample-scheduled`。category は `mac-sample-category`（`open`（前面）と `reply`（テキスト入力））。バナーの label は `MacLibraryExample, <題>, MacLibraryExample, <本文>`（副題が入る。9.0 の 4）なので、根の錨は `MacLibraryExample, <題>, MacLibraryExample, ` で始まり `, <本文>` で終わるものにする。

#### 権限（`NotificationPermissionUITests`。VM の権限の段。U-7）

| ID | 操作 | 確かめる内容 | 宣言 | 私物 | 流す所 | 自動か人か |
|---|---|---|---|---|---|---|
| NP2 | AuthorizationStatus、HasPermission → RequestPermission → 問い合わせの根の `Options` → `Don’t Allow` → AuthorizationStatus → RequestPermission → ShowImmediate | 初めは ✅ `[authorizationStatus] notDetermined`、✅ `[hasPermission] false`。拒否の後 ❌ `[requestPermission] denied. Permission dialog will not appear again. Please enable notifications in Settings.`、✅ `[authorizationStatus] denied`。2 回目は問い合わせが 5 秒出ない。ShowImmediate は ❌ `Notification permission is not granted. Please request permission first.` で、バナーが 5 秒出ない | `notification`、`ncsettings` | 2・3 | VM だけ | 自動* |
| NP3 | ShowImmediate（未決のまま）→ 問い合わせで `Allow` | 許可の後にバナー `Immediate Notification` が出る。✅ `[showImmediate] success` | `notification`、`ncsettings` | 2・3 | VM だけ | 自動* |
| NP1 | RequestPermission → `Allow` → AuthorizationStatus、HasPermission | ✅ `[requestPermission] granted`、✅ `authorized`、✅ `true` | `notification`、`ncsettings` | 2・3 | VM だけ | 自動*（試作で 3/3、サンプルでも許可が通った。9.0 の 5） |

#### 状態・表示・更新と取り消し・予約・問い合わせとバッジ（`NotificationUITests`）

| ID | 操作 | 確かめる内容 | 宣言 | 私物 | 流す所 | 自動か人か |
|---|---|---|---|---|---|---|
| N1 | HasPermission、AuthorizationStatus | ✅ `[hasPermission] true`、✅ `[authorizationStatus] authorized`。片付けをしない | - | 3 | VM・Mac | 自動* |
| N2 | RequestPermission（許可済み） | 問い合わせが 5 秒出ない。✅ `[requestPermission] granted` | `notification` | 2・3 | VM・Mac | 自動* |
| N3 | OpenNotificationSettings → システム設定の前面を待つ → サンプルを `activate` | ✅ `[openNotificationSettings] success`。システム設定が 10 秒までに `runningForeground`。中は読まず押さない。流す前に動いていなければ止める | `settings` | 2・3 | VM・Mac | 自動* |
| N4 | ShowImmediate（前面）→ GetDelivered | ✅ `[showImmediate] success`。根（`Immediate Notification`、`Displayed now`）が 10 秒までに出る。`count=1, ids=[mac-sample-notification-<数字>]`。**`notification` を選んだ回の見張り**（U-20） | `notification` | 2・3 | VM・Mac | 自動* |
| N5 | ShowTimeInterval(10s) → GetScheduled → Finder を前に → 発火を待つ → GetDelivered | 発火の前は `count=1, ids=[mac-sample-notification]`。根（`10s Notification`）を、押した直後から待ち始め 25 秒までに見る（バナーは約 5 秒で消えるので、間に別の操作を挟まない） | `notification` | 2・3 | VM・Mac | 自動* |
| N6 | 秒の窓を待つ → ShowCalendar(+1m) → GetScheduled → 発火を待つ | 予約に `mac-sample-notification`。根（`Calendar Notification`）が、押してから 65 秒までに出る | `notification` | 2・3 | VM・Mac | 自動* |
| N7 | ShowTimeInterval(10s) → すぐ UpdateById → GetScheduled、GetDelivered | ✅ `[updateById] success`。`Updated Notification` の根がすぐ出る。予約の時刻 + 5 秒まで `10s Notification` が出ない。予約 `count=0`、表示中に `mac-sample-notification` | `notification` | 2・3 | VM・Mac | 自動* |
| N8 | ShowTimeInterval(10s) → CancelById → GetScheduled | ✅ `[cancelById] id=mac-sample-notification`。予約が 10 秒までに `count=0, ids=[]`。予約の時刻 + 5 秒まで根が出ない。その後 GetDelivered も空 | `notification` | 2・3 | VM・Mac | 自動* |
| N9 | 秒の窓を待つ → ShowCalendar(+1m) → ScheduleCalendar(+1m) → 2 件を読む → CancelAll | ✅ `[cancelAll] called`。2 件から `count=0` | `notification` | 2・3 | VM・Mac | 自動* |
| N10 | ShowTimeInterval(10s) の発火を待つ → RemoveDeliveredById → GetDelivered | ✅ `[removeDelivered] id=mac-sample-notification`。10 秒までに `count=0` | `notification` | 2・3 | VM・Mac | 自動* |
| N11 | ShowImmediate → RemoveDeliveredById → GetDelivered | **今の動作**: `mac-sample-notification-<数字>` は消えず `count=1` のまま（id が違う。9.4） | `notification` | 2・3 | VM・Mac | 自動* |
| N12 | ShowImmediate → ScheduleTimeInterval(10s) の発火を待つ → GetDelivered → RemoveAllDelivered → GetDelivered | 2 件から ✅ `[removeAllDelivered] called` の後 `count=0` | `notification` | 2・3 | VM・Mac | 自動* |
| N13 | ScheduleTimeInterval(10s) → GetScheduled → 発火を待つ → GetScheduled、GetDelivered | 発火の前 `count=1, ids=[mac-sample-scheduled]`。根（`Scheduled Notification`）が 25 秒までに出る。出た後は予約 `count=0`、表示中に `mac-sample-scheduled` | `notification` | 2・3 | VM・Mac | 自動* |
| N14 | 秒の窓を待つ → ScheduleCalendar(+1m) → GetScheduled → CancelScheduledById → GetScheduled | 予約に `mac-sample-scheduled`。✅ `[cancelScheduled] id=mac-sample-scheduled` の後 `count=0` | `notification` | 2・3 | VM・Mac | 自動* |
| N14b | 秒の窓を待つ → ScheduleCalendar(+1m) → GetScheduled → 発火を待つ → GetScheduled、GetDelivered | 発火の前に予約 `count=1`。根（`Scheduled Calendar`）が 65 秒までに出る。出た後は予約 `count=0`、表示中に `mac-sample-scheduled`（レビュー v1 Codex B-04） | `notification` | 2・3 | VM・Mac | 自動* |
| N15 | ScheduleTimeInterval(10s) → CancelScheduledById | 予約 `count=0`。予約の時刻 + 5 秒まで根が出ない | `notification` | 2・3 | VM・Mac | 自動* |
| N16 | 秒の窓を待つ → ShowCalendar(+1m) → ScheduleCalendar(+1m) → CancelAllScheduled | ✅ `[cancelAllScheduled] called`。`count=0`（今は CancelAll と同じ処理。企画 1.4） | `notification` | 2・3 | VM・Mac | 自動* |
| N17 | RemoveAllDelivered、CancelAllScheduled → GetScheduled、GetDelivered | `count=0, ids=[]` が 2 つ。押すのは問い合わせを出さない 4 つだけ（サンプル自身の予約と表示を消すだけ） | - | 3 | VM・Mac | 自動* |
| N18 | SetBadgeCount(1) → SetBadgeCount(0) | ✅ `[setBadgeCount(1)] success`、✅ `[setBadgeCount(0)] success` | `badge`、`notification` | 2・3 | VM・Mac | 自動* |
| N19 | SetBadgeCount(1) → Dock のサンプルの項目を読む → SetBadgeCount(0) → 読む | Dock の、題がサンプルの項目がちょうど 1 つで、1 のときバッジ `1`、0 のとき無い。ほかの項目は読まない | `badge`、`notification` | 2・3 | VM・Mac | 自動*（だめなら HC3） |

#### category とイベント（`NotificationEventUITests`）

category の登録・削除は結果の行が先に出て反映は後なので、効果を通知で観測して区切る。**前の通知が残っていないこと**（setUp で根が 0 件）と、**1 回目の根が消えたこと**を確かめてから 2 回目を出す（同じ題を使うので。レビュー v1 Codex B-05）。

| ID | 操作 | 確かめる内容 | 宣言 | 私物 | 流す所 | 自動か人か |
|---|---|---|---|---|---|---|
| N20 | RemoveCategory → ShowTimeInterval(10s) → 根を hover（**無いことを観測**）→ 根が消えるのを待ち、RemoveAllDelivered → RegisterCategory → ShowTimeInterval(10s) → 根を hover → 根の `Options`（**有ることを観測**）→ Escape → 最後に RegisterCategory | 1 回目は根の中に `Options` が 2 秒出ない。2 回目は根の中に `Options` が出て、開いたメニューに `Open` と `Reply`（identifier か title）がちょうど 1 つずつある | `notification` | 2・3 | VM・Mac | 自動* |
| N21 | ShowImmediate → Finder を前に → 根が出てから 1 秒待って本文をクリック | サンプルが 10 秒までに前面に来る。最後のイベントが `#1 kind=action notificationId=mac-sample-notification-<数字> actionId=com.apple.UNNotificationDefaultActionIdentifier userText=- userInfo=id:mac-sample-notification-<数字>,source:MacLibraryExample`。2 秒待っても `#1` | `notification` | 2・3 | VM・Mac | 自動* |
| N22 | ShowImmediate（前面のまま）→ 根をクリック | N21 と同じ最後のイベント。2 秒待っても `#1` | `notification` | 2・3 | VM・Mac | 自動* |
| N23 | RegisterCategory → ShowImmediate → Finder を前に → 根の `Options` → `Open` | 前面に来る。`#1 kind=action ... actionId=open ...`。2 秒待っても `#1` | `notification` | 2・3 | VM・Mac | 自動* |
| N24 | RegisterCategory → ShowImmediate → Finder を前に → 根の `Options` → `Reply` → 根の中の `TextView`（placeholder `MacLibraryExample reply`、焦点あり）に `hello reply` → Return → サンプルの状態を見る → `activate` | Return の後、サンプルは後ろのまま（0a 5.1）。`#1 kind=textInput ... actionId=reply userText=hello reply ...`。2 秒待っても `#1` | `notification` | 2・3 | VM（この Mac は U-30 まで保留。U-5） | 自動* |

#### コールドスタート（`NotificationColdStartUITests`。U-22 で 0c に入れた）

実行の契約（3 件とも）:

1. `launch()` → `menu.notification` → 前提（U-7）→ アプリの中の片付け → RegisterCategory → **`notification.launchCopy` を読んで V1 とし、ランナーの `TEST_RUNNER_NTK_EXPECTED_COPY` と同じであることを確かめる**
2. ShowTimeInterval(10s) を押した時刻を T0 とする → GetScheduled を押し、`count=1, ids=[mac-sample-notification]` を読む（予約が入ったのを確かめてから止める。押し直しは 1 回まで）
3. `app.terminate()` → `state == .notRunning` を待つ。**T0 から `notRunning` までの絶対の予算を 6 秒**にし、超えたら操作をせずに `NTK-PRECONDITION:coldStartTiming` で止める（バナーは予約から約 10 秒で出て約 5 秒で消えるので、予算を使い切ると根を見失う。イベントの欠落と分けて数える）。T0 からの `notRunning`・根が見えた時刻・操作の時刻を 3.4 の「時間」として出し、0c の最初の 3 回で分布を記録する
4. 根（`10s Notification`。錨は 5.3 の冒頭のとおり、ちょうど 1 つ）を、予約を押した時刻から 25 秒まで待つ → 1 秒待つ → 操作（下の表）
5. `state == .runningForeground` を 15 秒まで待つ。**読むために `launch()` を呼ばない**（`launch()` は起こされたプロセスを止めて新しく起こすため）。`activate()` も、前面に来なかったと判定するまで呼ばない
6. 通知から起こされたプロセスは XCUITest の起動の引数を受けない（`-ApplePersistenceIgnoreState` が効かない）ので、窓が画面の中にあることを確かめ（U-15）、押す前の確かめ（5.0）に任せる → `menu.notification` を押して通知の画面を開く（新しいプロセスにしない）→ 最後のイベントを読む → `notification.launchCopy` が V1 と同じ → 2 秒待っても番号が増えない
7. 起動のきっかけの分類（`launch_response`）は見ない（5.9 の NC5）

| ID | 操作（4 の後） | 確かめる内容（6） | 宣言 | 私物 | 流す所 | 自動か人か |
|---|---|---|---|---|---|---|
| NC1 | 根の本文をクリック | `#1 kind=action notificationId=mac-sample-notification actionId=com.apple.UNNotificationDefaultActionIdentifier userText=- userInfo=id:mac-sample-notification,source:MacLibraryExample` | `notification`、`coldstart` | 2・3 | VM・Mac | 自動*（9.0 の 5。サンプルで 1〜2 回） |
| NC2 | 根の `Options` → `Open` | 同じ形で `actionId=open` | `notification`、`coldstart` | 2・3 | VM・Mac | 自動*（9.0 の 5。サンプルで 1〜2 回） |
| NC3 | 根の `Options` → `Reply` → 根の中の `TextView` に `cold reply` → Return | `kind=textInput actionId=reply userText=cold reply`。止まっている状態からは前面に出る（0a 5.1 の事実。試作） | `notification`、`coldstart` | 2・3 | VM（この Mac は U-30 まで保留。U-5） | 自動*（9.0 の 5。サンプルで 1〜2 回） |

テストに入れないもの: 通知センターでの消去（サンプルは `customDismissAction` を持たない）、通知の音（HC2）、題や本文が空などの検証の失敗（サンプルから起こせない。単体テストか 1b で扱う）、通知の操作のエラーの文（`NotificationDomainError` の文は 1b で変わる）。

### 5.4 Share（`ShareUITests`）

サンプルのボタン 15。ピッカーはアプリの木の `Popover`（0a 4.3）。押すのは Escape と 26 の `Copy` だけ（U-13）。

| ID | 操作 | 確かめる内容 | 宣言 | 私物 | 流す所 | 自動か人か |
|---|---|---|---|---|---|---|
| S1 | ShareText → ピッカーを待つ → Escape | ピッカーにサービスのボタンが 1 つ以上ある（名前は読まない）。✅ `[shareText] completed=false (cancelled)`。余分な完了なし | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S2 | ランナーが合成の内容 `ntk-s2-<時刻>` を書く → ShareText → `Copy` → 貼り付け板を読む | ✅ `[shareText] completed=true, service=<Copy の表示名>`。貼り付け板が `Shared from MacLibraryExample` になり、`changeCount` が上がった（読むのはテストが書いた後の内容だけ。U-10）。`Copy` が無ければ「26 で `Copy` が無い」と記録して失敗（成功の経路を確かめていないことを隠さない） | `sharepicker`、`clipboard` | 2・3 | Mac だけ（26） | 自動*（U-30） |
| S3 | ShareURL → Escape | ✅ `[shareURL] completed=false (cancelled)` | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S4 | S2 と同じ形で ShareURL → `Copy` | ✅ `[shareURL] completed=true, service=<Copy の表示名>`。貼り付け板が `https://www.apple.com` | `sharepicker`、`clipboard` | 2・3 | Mac だけ（26） | 自動* |
| S5 | ShareImage → Escape | ✅ `[shareImage] completed=false (cancelled)`。画像は HC5 | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S6 | ShareFile → Escape | ✅ `[shareFile] completed=false (cancelled)` | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S7 | ShareMultipleImages → Escape | ✅ `[shareMultipleImages] completed=false (cancelled)` | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S8 | ShareMultipleFiles → Escape | ✅ `[shareMultipleFiles] completed=false (cancelled)` | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S9 | ShareTextAndURL → Escape | ✅ `[shareTextAndURL] completed=false (cancelled)` | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S10 | ShareExcludingServices → `Add to Reading List` が無いことを 2 秒見る → Escape | ✅ `[shareExcludingServices] completed=false (cancelled)`。除外が効いたことの証明にはならない（除外しなくても出ない環境がある）。除外しないピッカーに出るかを 0c の最初に記録する | `sharepicker` | 2・3 | VM・Mac | 自動* |
| S11 | ShareViaMail → VM の Mail を止める | ✅ `[shareViaMail] completed=true, service=<Mail の表示名>`（0a 4.2 で通った。全文は 0c で写す）。画面は HC6 | `realservice` | 2・3 | VM だけ | 自動 |
| S12 | CanPerformMail | ✅ `[canPerformMail] canPerform=<true\|false>`（VM の値を写す） | `realservice` | 2・3 | VM だけ | 自動* |
| S13 | ShareEmpty | ❌ `[shareEmpty] errorCode=1401, errorMessage=<文>`。ピッカーが 2 秒出ない | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S14 | ShareInvalidURL | ❌ `errorCode=1402`。ピッカーが出ない | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S15 | ShareMissingFile | ❌ `errorCode=1404`。ピッカーが出ない | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S16 | ShareMissingImage | ❌ `errorCode=1403`。ピッカーが出ない | `sharepicker` | 2・3 | VM・Mac | 自動 |
| S17 | ShareUnknownService | ❌ `[shareUnknownService] errorCode=1406, errorMessage=<文>` | `realservice` | 2・3 | VM だけ | 自動 |

エラーの文（`errorMessage=` の後ろ）は 0c の最初に VM の実物から写して全文を比べる。

テストに入れないもの: `noAnchorView`（1405）・`presentationFailed`（1407）・`alreadyInProgress`（1408）。サンプルから起こせない（1408 は popover が外のクリックを食べるので UI では作れない。今のテストの注記）。単体テスト（`SharePickerPresenterTests`）と 1b で扱う。同じ回の 2 つ目の Share は 5.9 の層。

### 5.5 Clipboard（今の 17 件 + 追加 6 件）

今の `ClipboardSampleViewUITests`（11 件、C1〜C11）と `ClipboardSampleWaitRuleTests`（6 件、C12〜C17）は、テストの名前と検査の中身を残す。変えるのは次だけ:

- `final class ...: SampleUITestCase` に替え、`setUpWithError` を `setUpAfterGate()` に書き換える
- ナビの補助を `SampleApp` の口に替える: `openMenuCard` は `menu.clipboard` を押すだけ（文字で探す 2 つの道を消す）。**C9（`testObservationStopsWhenTheScreenIsLeft`）の本体にある戻るのクリック（`ClipboardSampleViewUITests.swift:376`）も、`SampleApp.goBack()` の 1 行に替える**（本体を 1 行変える。U-26）
- 待ちの規則（`isResultOfThisClick`）の本体を `Support/` の 1 か所に移し、固定するファイルの関数はそれを呼ぶだけにする。C12〜C17 は移した本体を検査する（写しを 2 つ持たない。レビュー v1 Claude B-10）
- **固定するファイルの操作の補助も守りの口に通す**（レビュー v2 Codex A-01）: `tap` の中の `button.click()`、範囲のピッカーの `option.click()`、`scrollIntoView` のスクロールを、`SampleApp` の守りの口（5.0 の押す前の確かめと、操作の後に割り込みの印を読んで throw する口）の呼び出しに替える。検査の中身（何を押して何を確かめるか）は変えない。替えた後に、危ない名前の出現の数とハッシュを取る
- 固定のハッシュとメソッドの名前の一覧（17）は、**C9 の扱いが決まった後**に取る
- VM で、固定したテストの途中に試験用の割り込みを入れ、以後のクリック・スクロール・普通の片付けが 0 回になることを確かめる（7 章）

| ID | テスト | 宣言 | 私物 | 流す所 | 0a の結果 |
|---|---|---|---|---|---|
| C1〜C8、C10、C11 | `ClipboardSampleViewUITests` の 10 件 | `clipboard`（クラスの下限） | 2・3 | VM・Mac | 通った |
| C9 | `testObservationStopsWhenTheScreenIsLeft` | `clipboard` | 2・3 | Mac だけ（26） | 2/2 落ちた。15.8.3 では戻るボタンを押せない（9.0 の 2）ので VM では流さない（`OS_ONLY_TESTS`。理由つきで基準に記録する） |
| C12〜C17 | `ClipboardSampleWaitRuleTests` の 6 件 | - | 1 相当 | VM・Mac | 通った |

C1（`testEveryButtonReportsAResult`）は範囲 general のまま全ボタンを押し、C3 は general を `Clear` するので、`clipboard` の下限は外せない。

足すもの（`ClipboardPasteUITests` と、VM の段の `ClipboardPrivacyUITests`）:

| ID | 操作 | 確かめる内容 | 宣言 | 私物 | 流す所 | 自動か人か |
|---|---|---|---|---|---|---|
| CB1 | ランナーが一般の貼り付け板に `ntk-cb1-<時刻>` を書く → `changeCount` を確かめる → `clipboard.pasteButton` の中の `PasteButton` を押す | ✅ `[onPaste] items=1, failures=0, partial=false`。確認が 2 秒出ない | `clipboard` | 2・3 | VM・Mac | 自動* |
| CB2 | プレビューの段: ランナーが書く → `PasteButton` → `Allow Paste`（`--999`） | 確認が 5 秒までに出て、押した後 ✅ `[onPaste] items=1, failures=0, partial=false` | `clipboard`、`pasteprivacy` | 2・3 | VM だけ | 自動* |
| CB3 | 同じ段: ランナーが書く → `PasteButton` → `Don’t Allow Paste`（`--998`） | 今の動作を写す | `clipboard`、`pasteprivacy` | 2・3 | VM だけ | 自動* |
| CB4 | 同じ段: ランナーが書く → 範囲 general のまま `Read` → `Don’t Allow Paste` | ❌ で始まる結果（エラーの番号を写す）。`Read` は読む前に書き直さない（`ClipboardSampleView.swift:340-355`）ので、ランナーの書いた外の内容を読む経路になる | `clipboard`、`pasteprivacy` | 2・3 | VM だけ | 自動* |
| CB5 | 同じ段: ランナーが書く → `Read` → `Allow Paste` → もう一度 `Read` | 1 回目 `items=1`。2 回目は確認が 2 秒出ない（0a 4.3） | `clipboard`、`pasteprivacy` | 2・3 | VM だけ | 自動* |
| CB6 | 同じ段: `AccessBehavior` → `DetectPatterns` → `DetectValues` | `AccessBehavior` がプレビューの下の値を示す（全文を写す）。**`DetectPatterns` と `DetectValues` は、押すとサンプル自身が先に検出用の文を書き直す**（`arrangeDetectionText`。`ClipboardSampleView.swift:410-445, 655-658`）ので、外の内容を読む経路にならない。ここでは「自分で書いた内容の検出では確認が 2 秒出ない」ことと結果の全文だけを見る。外から来た内容の `detectValues` の確認と拒否は、サンプルを変えずには作れないので、1a-11 と C ABI のテストに任せる（レビュー v1 Codex A-09） | `clipboard`、`pasteprivacy` | 2・3 | VM だけ | 自動* |

### 5.6 今の 37 件の扱い

| 今のテスト | 件数 | 扱い | 理由 |
|---|---|---|---|
| `ClipboardSampleViewUITests` | 11 | 残す（C1〜C11）。基底を替え、ナビの補助と C9 の戻るの 1 行を `SampleApp` の口に替え、C9 の扱いを決めてから固定する | 本体は識別子で探し、番号つきの錨で待つ |
| `ClipboardSampleWaitRuleTests` | 6 | 残す（C12〜C17）。規則の本体を `Support/` に移した後、その本体を検査する | 待ちの規則の純粋な検査 |
| `ShareSampleViewUITests` | 17 | 消して S1〜S17 に置き換える | 文字で探し、`CONTAINS` で比べ、`Copy` の有無で分岐して 15 では成功の経路を確かめないまま通っていた。ShareViaMail がこの Mac で Mail を開く |
| 雛形の 2 クラス | 3（実行は 4） | 消す | 役目が無い。`testLaunch` はスクリーンショットを `keepAlways` で残す |

置き換えの対応: `testShareExampleCardNavigatesToShareScreen` → M1a、`testShareTextPickerAppearsAndCancelResolves` → S1、`testShareTextPickerCopyServiceCompletes` → S2、`testShareURLPickerResolves` → S3・S4、`testShareImagePickerResolves` → S5、`testShareFilePickerResolves` → S6、`testShareMultipleImagesPickerResolves` → S7、`testShareMultipleFilesPickerResolves` → S8、`testShareTextAndURLPickerResolves` → S9、`testShareExcludingServicesPickerResolves` → S10、`testShareViaMailCompletesWithMailService` → S11、`testCanPerformMailReturnsResult` → S12、`testShareEmptyReturnsNoValidItemsError` → S13、`testShareInvalidURLReturnsInvalidURLError` → S14、`testShareMissingFileReturnsFileNotFoundError` → S15、`testShareMissingImageReturnsImageLoadFailedError` → S16、`testShareUnknownServiceReturnsServiceUnavailableError` → S17。

**0a で落ちた 4 件**: Share の 3 件（`Copy` を待って落ちた）は、置き換え後は 15 で Escape で閉じる S1・S10 になり、`Copy` は 26 だけの S2・S4 になる。15 の「選んで完了する」経路は、副作用の無いサービスが無いので自動では確かめない。C9 は 15 では戻るボタンを押せない（9.0 の 2）ので、26 だけにする。

### 5.7 全ボタンが押されることの確かめ（iOS の 3.7）

- 全ボタンの集合は、0b の画面ごとの識別子の enum（U-17 の唯一の出どころ）から導く。照らす側は、`SampleApp` が押した識別子をテストの終わりに 1 つの添付（`ntk-button-coverage-v1.json`、重複の無い文字列の配列）に残したものの和集合
- Clipboard の 36 個は照合から除く: 固定する C1〜C11 は `SampleApp` を通らずに押し、C1（`testEveryButtonReportsAResult`）がサンプルのソースからボタンの名前を導いて全部押す（両辺をソースから導く形は既にある）
- **照合は VM の道の全件の実行だけ**で行う（この Mac では添付を書き出さない。3.4）
- Dialog・Notification・Share の 43 個のうち、VM だけのテストでしか押さないもの（ShareViaMail・CanPerformMail・ShareUnknownService）も VM の全件で押される。この Mac の実行では照らさない

### 5.8 件数と区分の内訳

| 機能 | ケース | クラス |
|---|---|---|
| 共通 | 7（M1a、M1b、M2、I1a〜I1d） | `NavigationUITests`（3）、`IdentifierInventoryUITests`（4） |
| Dialog | 17（D1〜D17） | `DialogUITests` |
| Notification | 31（NP1〜NP3、N1〜N19 と N14b、N20〜N24、NC1〜NC3） | `NotificationPermissionUITests`（3）、`NotificationUITests`（20）、`NotificationEventUITests`（5）、`NotificationColdStartUITests`（3） |
| Share | 17（S1〜S17） | `ShareUITests` |
| Clipboard | 23（C1〜C17、CB1〜CB6） | `ClipboardSampleViewUITests`（11）、`ClipboardSampleWaitRuleTests`（6）、`ClipboardPasteUITests`（1）、`ClipboardPrivacyUITests`（5） |
| 計 | **95**（新しく書くもの 78、今のまま残すもの 17） | 12 クラス |

| 内訳 | 件数 | テスト |
|---|---|---|
| 私物の区分「3」 | 16 | M1a、M1b、M2、I1a〜I1d、D1〜D6、D16、N1、N17 |
| 私物の区分「2・3」 | 73 | 上と下のほかすべて |
| 「1 相当」 | 6 | C12〜C17 |
| 流す所: VM・Mac | 77 | 下の 18 件のほか |
| 流す所: VM だけ | 11 | NP1〜NP3、S11、S12、S17、CB2〜CB6 |
| 流す所: Mac だけ（26） | 5 | M1b、M2、C9、S2、S4 |
| 流す所: VM（この Mac は U-30 まで保留） | 2 | N24、NC3 |

宣言の区分ごと（重なりあり）: `notification` 28（NP1〜NP3、N2、N4〜N16 と N14b、N18〜N24、NC1〜NC3）、`ncsettings` 3、`settings` 1、`badge` 2、`clipboard` 19（C1〜C11、CB1〜CB6、S2、S4）、`pasteprivacy` 5、`sharepicker` 14（S1〜S10、S13〜S16）、`realservice` 3、`panels` 10（D7〜D15、D17）、`coldstart` 3。0c で宣言の表から機械で数え直す。

### 5.9 1b の後の層（別に書く。0c の件数に入れない）

次は、D-7（delegate の転送と起動のきっかけの分類）と D-8（A' の表示の手順）で 1b に動作が変わるので、1b の後に設計を書き足す（この文書の改訂か、Swift の API の設計書の 13 章に当たる所）。DoD の「Dialog・ファイルのパネル・Share の同じ回の 2 つ目の完了がちょうど 1 回」もここで対応させる。

| ID（案） | 内容 | 根拠 |
|---|---|---|
| NC4 | 通知センターの一覧から起こす（VM だけ） | 0a 4.3（1/1）、M-5 |
| NC5 | 起動のきっかけの分類を、止まっている・動いている（後ろ・前面）の場合ごとに | 0a 5.2、D-7 |
| DA1 | アラートとパネルが開いている間に、ほかの機能の完了が結果の行に届く | D-8 の基準 (1)、1a-6 |
| DA2 | 開いている間に来た 2 つ目の表示の要求（アラート・パネル）が、1 つ目が閉じた後に開き、完了がちょうど 1 回 | D-8 の基準 (3)、1a-6 の続き、DoD |
| DA3 | 取り消しが自分のアラート・パネルだけを閉じる。ホストのモーダルが上にあるときは断り、断った取り消しの後の扱いを確かめる。下にあるときは自分だけを閉じる | D-8 の基準 (2)、1a-6 の H1・H2 |
| DS1 | 同じ回の 2 つ目の Share の完了がちょうど 1 回 | DoD、iOS の SH-13 |
| DH1 | ヘルプがイベントになり、完了は 1 回（D5 の期待値を変える） | 企画 1.4 |

DA・DS・DH は、1b でサンプルに要求を出すボタンを足してから書く。C ABI の入口からの同じ確かめは C ABI のテスト（2b）と `MacLibraryCApiUITests` で行う。

## 6. テストの基盤（0c）とランナー（0d）

### 6.1 基盤（`MacLibraryExampleUITests/Support/`）

| ファイル | 役割 |
|---|---|
| `DeviceRequirements.json` | 宣言の表。`{"schema": 1, "tests": {"<クラス>/<メソッド>": ["<区分>", ...]}}`。ビルドの後に、ソースとバンドルの中の写しのハッシュを照らす |
| `SampleUITestCase.swift`（基底） | setUp / tearDown の入口を `final override` にし、async の形は上書きしない（iOS の 8.6）。`setUpWithError`: `continueAfterFailure = false` → `self.name` の正規化 → 表を引く → 環境の判定（`TEST_RUNNER_NTK_HOST` と、`vm` のときは `sysctl kern.hv_vmm_present`）→ この Mac で許されていない区分なら `XCTSkip("NTK-GATED:<区分>")` → 監視を付ける → `gatePassed = true` → 子の `setUpAfterGate()`。`tearDownWithError` は `gatePassed` のときだけ、監視の印が立っていなければ片付ける。区分ごとの印（10 個の型。初期化子は `fileprivate`）を出す口 |
| `SampleApp.swift` | `XCUIApplication` を private に持つ。起動、`menu.*` で開く、`goBack()`、識別子のボタンをスクロールして押す（今の Clipboard の `scrollIntoView` を移す）、押す前の確かめ（5.0）、結果の待ち（U-3 の印と 2 段の口、余分な完了の 2 秒）、最後のイベントとコピーの印を読む、押した識別子を記録する（5.7）。印が要るボタンは印を取る口だけで押せる |
| `WaitRule.swift` | 待ちの規則の本体（今の `isResultOfThisClick` と、ボタンの名前の前方一致の扱い）。C12〜C17 が検査する |
| `NotificationCenterUI.swift` | 初期化に `NotificationToken` が要る。サンプルのバナーの根を U-2 の錨と `.element` で取る、1 秒待って押す、根の中の `Options` → 開いたメニューのちょうど 1 つの項目、根の中の `TextView` に入れて Return（U-5 の取り直し）。問い合わせへの答えは `NCSettingsToken` も要る |
| `SharePicker.swift` | `SharePickerToken` が要る。ピッカーを待つ、サービスのボタンの数を数える（名前は読まない）、Escape、名前を指定して無いことを見る（S10）。`Copy` は `ClipboardToken` も要り、26 のときだけ |
| `Panels.swift` | `PanelsToken` が要る。パネルを待つ、Cmd+Shift+G で fixture に移り今の場所を確かめる、fixture の中の項目だけを選ぶ、`OKButton` / `CancelButton` / `Save` / `Replace` |
| `OtherApps.swift` | Finder を前に出す、システム設定の前面を待つ（`SettingsToken`）、Dock のサンプルの項目を読む（`BadgeToken`）、VM の Mail を止める（`RealServiceToken`）。流す前に動いていなかったものだけを止める |
| `RunnerPasteboard.swift` | `ClipboardToken` が要る。一般の貼り付け板に書く、`changeCount` を照らす、テストが書いた後の内容を読む（S2・S4） |
| `PrivacyPrompt.swift` | `PastePrivacyToken` が要る。貼り付けの確認を identifier で待って押す |
| `UnexpectedInterruptionGuard.swift` | U-8 の何も押さない監視 |
| `NotificationCleanup.swift` | アプリの中の片付け（`RemoveAllDelivered`・`CancelAllScheduled` だけ。`NotificationToken` を受け取ったテストだけ）と、setUp の根が 0 件の待ち（U-15） |
| `SystemLabels.swift` | U-2 の en / ja のラベルの表（ja は U-30 で取る）。根の label の区切り（en は `, `）もこの表の項目にする |
| `StepCode.swift` | `NTK-STEP:<段>` の語彙の enum（`goBack`、`copyMissing`、`rootNotUnique`、`panelLocation` など）。テストが投げる失敗はここの値だけを段の符号として付ける（3.4） |
| `OverlayCheck`（`SampleApp` の中） | 印の要らない読むだけの口: 押す点を覆う最前面の窓の持ち主（PID・枠・層だけ）と、`com.apple.notificationcenterui` の窓の枠と数を読む。label・題・名前は読まない（5.0） |

**閉じた形のソースの規則**（iOS の 6.1 と 8.7 を写す。Python で字句に分けて照らす）: テストのクラスは `final class <名前>: SampleUITestCase` だけ、`override` は `setUpAfterGate()` と `tearDownAfterGate()` だけ、`class func`・`static` の上書き・`#if`・`extension`・`XCTExpectFailure`・`async` のテストを禁じる。`import` は `XCTest` と `Foundation`（`Support/` は `AppKit` と `Darwin` も）。危ない名前（`XCUIApplication`、`NSPasteboard`、`NSWorkspace`、`NSRunningApplication`、`Process`、`addUIInterruptionMonitor`、`typeKey`、`typeText`、`coordinate`）は `Support/` の決まったファイルの中だけ。例外は固定した `ClipboardSampleViewUITests.swift` の今の出現だけで、ファイルと回数で照らす。識別子の文字列は信頼する部分の外に書かない（固定したファイルの `clipboard.` は例外）。**固定するファイルには Swift の正規表現の literal（`/let sampleName = "([^"]+)"/` など。431・442 行）がある**ので、字句の分け方に `/.../` と `#/.../#` を足し、今のファイルの写しを fixture にした自己テストで確かめてから固定する（レビュー v1 Claude B-9）。

D-14 のとおり、UI テストのターゲットは Swift 5・strict concurrency minimal のまま残す。

### 6.2 待ち時間（U-14）

| 待つもの | 実測（VM） | 待ち時間 |
|---|---|---|
| アプリの起動、画面、結果の行 | - | 10 秒 |
| アラート・パネル・ピッカーの表示 | - | 5 秒 |
| 許可の問い合わせ | 約 1.1 秒（試作） | 10 秒 |
| 前面のバナー | 約 1.06 秒（試作） | 10 秒 |
| 10 秒の予約のバナー | 予約の後 9.1〜10.1 秒（試作） | 予約から 25 秒 |
| +1 分のカレンダー（秒の窓の後） | 測っていない（押してから 30〜55 秒の見込み。U-14c） | 押してから 65 秒 |
| 秒の窓 | - | 最大 30 秒 |
| `Options` とメニュー | - | 5 秒 |
| アクションの後に前面に来る、コールドスタート | - | 15 秒 |
| `terminate` の後の `notRunning` | - | 10 秒 |
| setUp の根が 0 件 | - | 15 秒 |
| 取り消し・削除の反映（U-6） | - | 10 秒（0.5 秒おきに押し直す） |
| 「出ない」「来ない」・余分な完了・バナーの前の 1 秒 | - | U-14 の例外のとおり |

1 回の時間（0a の実測）: 今の UI テスト 38 件（実行の数）で約 343 秒。見積もり（推測）: 95 件で VM は 60〜80 分（通知の待ち、秒の窓、余分な完了の 2 秒が多い）。この Mac は区分で絞るので、許可の一覧ごとに見積もりを出す。0d で測る。

### 6.3 `scripts/test_mac.sh`（0d）

シェルは薄くし、判定は `scripts/mac_ui_runner.py` の純粋な関数に置く。**流す道は 2 つ**で、`--where` で選ぶ。

| オプション | 内容 |
|---|---|
| `--where vm\|mac` | 必須。`vm` と `mac` のほかの値と省略は拒む。VM の資格が成り立たないとき、この Mac の道に切り替えずに止まる |
| `--vm <名前>` | `vm` のとき。既定は `ntk-macos-15-new` |
| `--feature <Dialog\|Notification\|Share\|Clipboard>` | UI テストをその機能に絞る（共通の 2 クラスはいつも入れる）。権限の段・貼り付けの確認の段・見張りにも当てる（U-18、U-20）。単体テストは流さない |
| `--skip-unit` | 単体テストを飛ばす |
| `--allow <区分,...>` | `mac` のときだけ。この Mac で許す区分。既定は空。VM だけの区分を渡すと止まる |
| `--allow-lsregister` | `mac` のときだけ。`--dry-run` の一覧に固定した余分なコピーを外すことを許す（U-21） |
| `--dry-run` | `mac` のとき。この Mac で何も起動しない（ビルドもしない）。VM で列挙と照合を行い、流すテストと除くテスト（理由: 区分、VM だけ、OS だけ）、単体テストの名指しの一覧（U-29）、この Mac に起きること、準備、時間の見込み、外すコピーの印を表示し、**許可を求める一覧のファイル**（流すテストの配列、`--allow`、`HEAD`、`mac/` の木のハッシュ、ランナーと共通のモジュール（U-24）のハッシュ、信頼する部分のハッシュ、許可の ID）を書いて止まる。一覧にはこの Mac の名前・ホームのパスを入れない |
| `--approved <file>` | `mac` で流すときは必須。今の選び方・コミット・木・ランナーと共通のモジュールと完全に同じでなければ流さない。触れる前に許可の ID を台帳（`~/Library/Application Support/native-toolkit/test_mac-approvals.log`）に記録し、台帳にある ID は拒む。**許可を使った後は、読むだけの計画の写しだけを使い、この Mac のどの xcodebuild の前にも、計画の digest・台帳・木・ランナーのファイルを照らす**（iOS の 0d の R-19） |
| `--baseline` | 基準として保存する（下の「基準」の条件を満たすときだけ） |
| `--name-each-test` | VM でも 1 回の呼び出しで 1 件ずつ名指しする |
| `--qualification <mac26\|vm-ja>` | U-30 の適格性の段だけを流す計画を作る。`mac26` はこの Mac で `--dry-run` と `--approved` が要る。`vm-ja` は VM の言語を ja にして流し、終わりに en-US に戻したことを確かめる。どちらも普段の実行と基準には入らない |

**VM の道**（許可なし。資格を満たすときだけ）:

0. **資格の確かめ**（事実で確かめ、読めない・分からないものは不合格。レビュー v1 Codex A-10）:
   - この Mac の側: その VM の `tart run` の引数に `--no-clipboard` があり、`--dir`・`--net-bridged` が無い（今は `--no-graphics --no-clipboard`。事実）
   - VM の中（VM 専用の鍵と、固定した known_hosts で入る）: `sysctl -n kern.hv_vmm_present` が `1`、`hw.model` が `VirtualMac` で始まる（事実: `VirtualMac2,1`。この Mac は `0`）、`sw_vers` が 15.8.3（24H241）、`defaults read MobileMeAccounts Accounts` が無い、`~/Library/Accounts/Accounts4.sqlite` に認証済みのアカウントが許す種類（`HolidayCalendar` など、システムのもの）のほかに無い（事実: 今は `HolidayCalendar`・`OnMyDevice`・認証していない `iTunesStore` の 3 つ）、Mail のアカウントが無い（暫定の照らし方: `Accounts4.sqlite` に Mail の種類（IMAP・POP・Exchange・Google・iCloud など）のアカウントが無いこと。`Accounts4.sqlite` が Mail だけで作ったアカウントまで覆うかは確かめていないので、確かな方法は 9.3。決まるまでこの暫定の照らし方を資格に入れる）、共有のフォルダーが付いていない（`virtiofs` の mount が無い。事実）、`xcode-select -p` が Xcode 26.3。**言語は資格でなく測りの環境**として別に見る: 普段の実行と基準は en-US を求め、U-30 の ja の段だけ ja を許す（隔離の項目は省かない）。ja の段の後は en-US に戻ったことを確かめてから普段の実行に戻す
   - **同一性の束ね**: 資格を確かめたときの VM の `IOPlatformUUID` を記録し、以後のどの `ssh` の命令の前にも同じであることを照らす（違えば止まって確かめ直す）。`tart` の VM の名前・ip・known_hosts の鍵も記録する
   - **出どころ**: VM は Cirrus Labs の `macos-sequoia-vanilla` の 15.7.7 から作り、15.8.3 に上げた（0a 1 章）。入れたのはリポジトリのソース、0a の試作、fixture の合成のデータだけ。この出どころの記録（`results/` の VM の記録）を資格の一部にする
1. **ソースを渡す**: `git ls-files -co --exclude-standard mac`（`build/` を除く）を `tar` で `ssh` に流し、VM の `~/ntk/runs/<実行の ID>/src` に置く。`HEAD` と作業ツリーのハッシュを記録する。`--baseline` のときは `mac/` にコミットしていない変更があれば拒む
2. **VM の中で組む**: Xcode 26.3 で `build-for-testing`（ad-hoc の署名。U-25）。`.xctestrun` の名前は決め打ちせず、1 つだけあることを確かめる
3. **列挙と照合**（柱 2）: `-enumerate-tests`（9.0 の 6 の形）。列挙と宣言の表、クラスの下限、固定したファイル、閉じた形の規則、表のハッシュ、信頼する部分のハッシュを照らす
4. **VM の準備**: `dndMirrored=false`（U-20）、余分なコピーを外す（U-21）、fixture を作る（U-11）、Finder 以外の前面のアプリを止める
5. **単体テスト**: `MacLibraryTests` 全部と `MacLibraryExampleTests`（決まりの区分 2 も VM では許可なし）
6. **権限の段**（`--feature` が無いか `Notification`）: 戻す → NP2、戻す → NP3、戻す → NP1
6b. **通知の UI の立て直し**: 通知のクラスの前とクラスの間、および setUp の根が 0 件にならずに落ちたとき、VM の中で `NotificationCenter` と `usernoted` を立て直し（9.0 の 5 で戻った方法）、立て直したことと回数を結果に記録する（隠さない）。この Mac ではこの段を持たない（5.0 の `NTK-STOP:notificationUI`）
6c. **おとりの通知**（VM だけ）: 通知のイベントとコールドスタートのクラスの前に、0a の試作（`dev.ntkprobe.notif0a`）で `Options` を持つ通知を、サンプルと同じ題（`Immediate Notification` など）で出しておく。根で絞る形が働いていれば、サンプルの操作はおとりに 1 回も届かない（試作の記録の `didReceive` が 0 回）。終わりにおとりを消す（7 章の「根」の変異の土台）
7. **UI テスト**（`-parallel-testing-enabled NO`、`TEST_RUNNER_NTK_HOST=vm`、`TEST_RUNNER_NTK_ALLOW=<10 個>`、`TEST_RUNNER_NTK_FIXTURE_DIR`、`TEST_RUNNER_NTK_EXPECTED_COPY`）: 計画から導いたメソッドを名指しし、結果の配列が名指しとちょうど同じかを照らす。順は共通 → Dialog → Notification（見張りが先）→ ColdStart → Clipboard → Share（S11 の後に Mail を止める）
8. **貼り付けの確認の段**（`--feature` が無いか `Clipboard`）: プレビューを入れる → `ClipboardPrivacyUITests` → 元の値に戻す
9. **結果**: VM の中で `xcresulttool get test-results tests` / `summary` を読み、3.4 の一覧の値と押したボタンの記録の添付だけを持ち帰る。fixture の中身を照らす。`.xcresult` は VM に残し、次の実行の前に消す

**この Mac の道**（毎回の許可。柱 1〜3）:

0. 読むだけの確かめ: `sw_vers`、Xcode の版、`mac/` にコミットしていない変更が無いこと、閉じた形の規則、ランナーと共通のモジュールがコミット済み
1. **列挙は VM で行う**（同じコミットで VM の道の 0〜3）。VM の資格が成り立たなければ `--dry-run` は止まる
2. **選ぶ**（柱 1）: 宣言の区分がすべて `--allow` に入るテスト。VM だけの区分、`VM_ONLY_TESTS`、OS の合わない `OS_ONLY_TESTS` を除く。`notification` を選べば見張り（N4）を先頭に足す。単体テストは U-29 の監査した一覧だけ
3. `--dry-run` は一覧を書いて止まる。`--approved` は照らして台帳に記録する
4. 一時フォルダー（`mktemp -d`、`umask 077`、所有者の印のファイルを置く）を作り、**最初の xcodebuild の前に** trap を登録する。**中断の順**（レビュー v1 Codex B-12）: 時間切れ・`INT`・`TERM`・`HUP` では、その実行の xcodebuild の process group に `TERM` を送り、30 秒まで終わるのを待ち、残れば `KILL`、今の実行のパスから起こしたサンプルとランナーを止め、その後に一時フォルダーを消す。消せなければ 0 でない終了で場所を伏せて知らせる。一時フォルダーの印のファイルには、実行の ID、xcodebuild の process group と PID、組んだサンプルとランナーの実体のパスを書く。親だけが `KILL` されたときや、この Mac の再起動で trap が走らなかったときのために、**次の実行の始めに**前の回の印のファイルを探し、(i) 書き手（その process group、そのパスのサンプルとランナー、xcodebuild）がまだ動いているかを確かめる。動いていれば、`--dry-run` は `NTK-STALE:alive` だけを出して止まり、止めることを許可の一覧に「前の回の残りを止める」として書く。許可を得た実行で、`TERM` → 終わるのを待つ → 残れば `KILL` → 終わったことを確かめてから、(ii) 所有者と形を確かめて一時フォルダーを消す。止められなければ片付けは終わっていないとして止まる（成功にしない）。使った許可の ID は使い回さない。この順は VM の合成のプロセスとファイルで親だけを `KILL` して確かめる
5. **この Mac で組む**（Xcode は U-23、署名は U-31）。組んだテストのバンドルを `otool` で読み、VM の列挙と同じ集合であることを照らす（柱 2 の⑤）
6. `coldstart` を選んだ回だけ、LaunchServices のコピーを数える（U-21）。余分があり `--allow-lsregister` で固定した集合と違えば止まる
7. fixture を作る（`panels` のとき）
8. **単体テスト**（`--skip-unit` でなければ）: U-29 の監査した一覧だけを名指しして流す（`-collect-test-diagnostics never`）
9. **UI テスト**: 1 件ずつ名指しして流す（`TEST_RUNNER_NTK_HOST=mac`、`TEST_RUNNER_NTK_ALLOW=<--allow>`、`-collect-test-diagnostics never`、5.0 の時間切れ）。通知のテストが途中で落ちたら残りを流さない（5.0）。`MAC_DEFERRED_TESTS`（N24・NC3）は選ばない。結果の配列が名指しと許可の一覧とちょうど同じでなければ止まる。**結果のバンドルが今の実行の一時フォルダーのものであること**（宛先の取り違えが無いこと）も照らす
10. 結果は `get test-results tests` / `summary` の JSON を一時フォルダーの中で読み、3.4 の一覧に通した値だけを出す。xcresult の Test Case の子は `Failure Message` だけを許し、ほかの種類があれば止まる（iOS の 0d の R-20）。添付を書き出さない。trap で消す。残したもの（貼り付け板がテストの文字のまま、category が登録されたまま、バッジ 0、システム設定・Finder を前に出したこと、組んだコピーの登録を外したこと）を表示する

`-collect-test-diagnostics` は Xcode 26.3 の `xcodebuild -help` で「失敗のときに sysdiagnose のような詳しい診断を集めるか」と説明されている（事実）。画面の動画を止めるものとは書かれていないので、動画は止まらない前提で 3.4 の境界を守る。動画を止める方法は 9.3。

**結果の読み方と skip**（iOS の 6.3 と同じ）: `NTK-GATED:` は失敗、`NTK-PRECONDITION:` は失敗として数える、`NTK-INTERRUPTED` は失敗、Expected Failure は失敗、意図した skip の一覧（今は無い）のほかの skip は失敗。ランナーが除いたテストは「区分で除いた」「VM だけ」「OS だけ」「見張りで止めた（失敗に数える）」として数える。

**基準のファイル**: `scripts/test_mac.baseline.<vm|mac>-<OS の版>.json`。

| キー | 中身 |
|---|---|
| `where`、`os`、`osBuild`、`arch`、`language`、`xcode` | 環境 |
| `vm` | VM のときだけ: 出どころと資格の確かめの結果 |
| `allowed` | 許した区分 |
| `source` | `HEAD`、`mac/` の木のハッシュ、宣言の表のハッシュ、`VM_ONLY_TESTS`・`OS_ONLY_TESTS` の表のハッシュ |
| `eligible` / `executed` / `excluded` | その環境で流せる全体の集合、流した集合、除いた集合と理由（区分・VM だけ・OS だけ） |
| `counts` | ターゲットごと（UI テストは機能ごと）。件数は展開の後の数。Swift Testing の単体テストの識別子は UI テストと別に扱う |
| `results` | `<ターゲット>/<クラス>/<テスト>` → `passed` / `failed` / `skipped` |

**基準の条件**（U-32）: VM は「`--feature`・`--skip-unit` なし、`mac/` にコミットしていない変更なし、失敗なし」。この Mac は「VM だけの 3 区分を除く 7 区分をすべて許し、U-29 の単体テストを含め、`eligible` をすべて流して失敗なし」。区分を絞った回は基準にせず、基準と比べるだけ。比べるときは、`excluded` の集合と理由が変わったこと（除外の追加・対象の消失）も差として出し、レビューの対象にする（失敗に数えずに隠さない）。前の基準は上書きせず、日付つきで残す。

### 6.4 iOS から持ち込むもの・持ち込まないもの

| 持ち込む（純粋な関数と自己テスト） | 持ち込まない |
|---|---|
| 列挙・`nodeIdentifier`・`self.name` の正規化、列挙の JSON、宣言の表と照合、クラスの下限、固定したファイルの照合、信頼する部分のハッシュ、閉じた形の字句の規則（正規表現の literal を足す）、選び方、名指しの組み立て（空なら組み立てない）、結果と名指しの照合（配列の件数と一意の件数）、許可の一覧と台帳、**R-19**（許可の後は計画の写しを使い、どの xcodebuild の前にも照らす guard）、**R-20**（Test Case の子は `Failure Message` だけ）、skip と Expected Failure の分類、押したボタンの添付の照合、基準との比べ方、trap の順、`-derivedDataPath` と `-resultBundlePath` の置き場の検査（iOS の 8.7） | `simctl`・`devicectl`、シミュレーターか実機かの判定、`--enumerate-udid`、`SIMULATOR_ONLY_TESTS`、アプリの削除の段、`--capi`・`--capi-ui`・`--capi-device` |

足すもの: 押す前の確かめの読むだけの口（窓の持ち主と通知センターの枠）、`NTK-STEP` の語彙の照合、前の回の残りの書き手を止めてから消す片付け、監査の表とコードのハッシュの照合（U-29）、`MAC_DEFERRED_TESTS` と `QUALIFICATION_ONLY_TESTS` の表、VM の通知の UI の立て直しとおとりの通知、VM の資格の確かめと同一性の束ね、`tar` と `ssh` の受け渡し、VM の中の組み立てと列挙、`ncreset`・`dndMirrored`・`lsregister`、プレビューの設定の出し入れ、fixture とその照合、`otool` での macOS のテストのバンドルの読み取り、3.4 の出力の一覧（ホームのパスを `~` に、fixture を `<fixture>` に置き換えても外へ出さない値を決める関数）、中断の順、前の回の一時フォルダーの片付け、単体テストの監査の一覧（U-29）。

macOS の自己テストの fixture は、VM で取った実物（列挙の JSON、`xcresulttool` の JSON、`otool` の出力）を写す。unknown・空・重複・`throws` のテスト・基底クラスの行を含める（レビュー v1 Codex B-09）。共通化の形は U-24。

### 6.5 この Mac で流す前の知らせ

決まりの 4 つ（テストの一覧と区分、この Mac に起きること、準備、時間と始める時刻）を `--dry-run` の出力から作る。準備は決まりの「準備」に、この設計の次を足す:

| 事柄 | 内容 |
|---|---|
| 通知（`notification`） | 「画面のミラーリング中または共有中に通知を許可」をオン（U-20）。サンプルの通知が許可されていること（されていなければ利用者が自分で許す。U-7）。**サンプルの通知の音が鳴る**（`willPresent` は `.sound` を含む）。終わったら戻してもらう |
| Handoff とユニバーサルクリップボード（`clipboard`） | 切ってもらう。切れなければ `clipboard` を許さない。一般の貼り付け板の内容は戻らない |
| コールドスタート（`coldstart`） | 余分なサンプルのコピーの数と印。外すなら `--allow-lsregister` を別に聞く（U-21） |
| パネル（`panels`） | パネルが前に使ったフォルダーで開き、ファイルの名前が画面に出る。テストは fixture に移ってから選ぶ |
| ピッカー（`sharepicker`） | サービスの一覧が画面に出る。押すのは Escape と `Copy` だけ |
| 前に出るアプリ | **Finder（私物の Finder の窓とファイルの名前が前に出る）**、システム設定（`settings`） |
| アクセシビリティと自動化の許可 | U-31 の署名の形で、組むたびに許し直しが要るか（最初の区切りで確かめる） |

## 7. 変異で確かめること（`common.md` の「検査の書き方」）

テストを足したら、守る対象を壊して落ちることを確かめる。**変異は VM だけで流す**（この Mac で壊れたコードを動かさない）。ランナーの選び方と許可は、`--dry-run` と純粋な関数の自己テストで、この Mac で何も起動せずに確かめる。壊すのは確かめる間だけで、確かめたら戻す。結果は 0c・0d の結果のファイルに書く。守りの本体（柱 1〜3 と 3.4）の変異と、テストの側の変異を分けて書く。

| グループ | 壊すもの | 落ちるはずのもの |
|---|---|---|
| Dialog | `showDialog` の完了を 2 回呼ぶ | D1、D16（増分 2） |
| Dialog | ヘルプの完了を呼ばない | D5（増分 1、履歴が違う） |
| Dialog | 3 つ目のボタンの番号を `rawValue` の差でなく 0 に固定する | D3、D6 |
| Dialog | 保存のパネルで、返す前にファイルを書く | D13・D15 の後のランナーの fixture の照合 |
| Notification | `willPresent` の表示の options を空にする | N4、N22 |
| Notification | `cancelScheduled` を何もしない形にする | N8 |
| Notification | `removeDelivered` を何もしない形にする | N10 |
| Notification | `didReceive` で action の id の代わりに通知の id を渡す | N21〜N23、NC1・NC2 |
| Notification | テキスト入力の応答を見分けず、ふつうのアクションとして渡す | N24、NC3 |
| Notification | `setNotificationCategories` を呼ばない | N20 |
| Notification | サンプルの受け手の設定を `onAppear` に戻す | NC1〜NC3（画面ができる前のイベントを入れ物に書けない） |
| Notification | 受け手を 2 回呼ぶ | N21〜N24、NC1〜NC3（2 秒の余分なイベント） |
| Notification | サンプルの `ScheduleTimeInterval` を 30 秒にする | N13（時間切れ） |
| Share | 完了をいつも `completed=true` で返す | S1、S3 |
| Share | 完了を 2 回呼ぶ | S1〜S17 の余分な完了の 2 秒 |
| Share | サンプルの除外のリストを空にする | S10（出る環境だけ。出ない環境では落ちないことを記録する） |
| Share | `ShareError.noValidItems` の文を変える | S13 |
| Clipboard | `onPaste` で結果を変えない | CB1 |
| Clipboard | 読み込みの失敗を ✅ で表示する | CB4 |
| 識別子 | 識別子の無いボタンを足す、一覧に無い識別子を間接の補助で付ける、同じ識別子を 2 つに付ける | その画面の I1 |
| 全ボタン | 1 つのボタンを押すテストを外す。添付を 2 つにする・壊れた JSON にする | 5.7 の照合 |
| 片付け | 通知の片付けで `SetBadgeCount(0)` を押す形にする | 片付けの口が `badge` の印を持たないので throw する（`NotificationToken` を受け取らない N1・N17 では片付け自体が走らないことも確かめる） |
| 根（信頼の境界） | `NotificationCenterUI` の根の取得を、通知センター全体の `Options` の `firstMatch` に替える | 信頼する部分のハッシュの照合で止まる（これは「替えたことを見つけた」記録で、補助が誤りを捕まえたことの記録とは分けて書く） |
| 根（動き） | ハッシュの照合を外した VM の試しで、上と同じ変異を入れ、6c のおとりの通知（`Options` を持ち、サンプルと同じ題）を、サンプルの通知より前に並ぶ形と後に並ぶ形の両方で置く。根が途中で消える・差し替わる、返信の欄が 2 つになる、焦点が移る、もそれぞれ合成の状態で作る | おとりの `didReceive` が 1 回でもあれば変異が見えたとする（決まって落ちる形で確かめ、たまたま正しい通知を押して通る試しにしない）。戻すとおとりへの配送は 0 回 |
| 根（焦点と placeholder） | U-5 の焦点と placeholder の確かめを外す | おとりの横で N24 が落ちる（おとりに入力が届く） |
| setUp の根の待ち | setUp の「根が 0 件」の待ちを外す | 前の回の根を掴んで N21〜N23 が落ちる（9.0 の 5 の形） |
| コピーの印 | `TEST_RUNNER_NTK_EXPECTED_COPY` を別の値にする | NC1〜NC3 が落ちる |
| 押す前の確かめ | VM で、合成の別のアプリの窓をサンプルのボタンの上に置く | 押さずに失敗し、合成の窓のアプリにクリックが 1 回も届かない（そのアプリの記録で数える） |
| 固定したテストの割り込み | VM で、C1 の途中に試験用の割り込みを入れる | 以後のクリック・スクロール・片付けが 0 回 |
| 柱 1 | 選ぶ関数で「すべて」を「どれか」にする。空の名指しで xcodebuild を呼ぶ。VM だけの区分のテストを選ぶ | 自己テスト。`--dry-run --allow notification` の一覧に S2 や NP1 が入ることでも分かる |
| 柱 1 | 見張りを、`notification` を選ばない回にも入れる | 自己テスト（`--feature Dialog --allow ''` の計画に N4 が無い） |
| 柱 2 | 宣言の表から 1 行消す、無いキーを足す、区分を綴り違える、クラスを足して表に書かない、`#if` を足す、固定したファイルを 1 行変える、バンドルの中の表だけを書き換える | 6.3 の照合（VM の道の 3） |
| 柱 3 | 許可の一覧から 1 件を消す、`--allow` を変える、使った ID で流す、共通のモジュールを 1 行変える | 6.3 の照合（`--dry-run` と同じく何も起動せずに） |
| 二段目 | `TEST_RUNNER_NTK_HOST=vm` をこの Mac の環境から渡す | 基底が `kern.hv_vmm_present` を読んで throw（この確かめは、VM の中で値を偽れないので、自己テストでは判定の関数に 0 を渡して確かめる） |
| VM の資格 | 資格の確かめの 1 項目を外す（`--no-clipboard` の照合、アカウントの照合、`IOPlatformUUID` の束ね） | 自己テスト（それぞれを満たさない入力で不合格） |
| 出力の境界 | 失敗の文をそのまま表示する形にする | 自己テスト（3.4 の一覧に無い値を拒む） |
| 中断 | trap の登録を最初の xcodebuild の後に移す。`HUP` を外す。子を止める前に消す | 自己テスト（順の検査） |
| 強制終了の後 | VM の合成のプロセスとファイルで、親だけを `KILL` して書き手を残す | 次の実行の始めに `NTK-STALE:alive` で止まり、許可の後に止めてから消す。止めずに消す形に壊すと自己テストで落ちる |
| 監査 | U-29 の監査した suite の本文・依存する実装・`TEST_HOST` のどれか 1 つだけを変える | 監査のハッシュが合わず、この Mac ではその suite を選ばない（起動する前に止まる） |
| 段の符号 | 失敗の文に語彙の外の `NTK-STEP:` を入れる | 3.4 の一覧の関数が通さない |
| 監視 | 監視が押す枝を持つ形に戻し、VM で無害な試験用のアラートを出す | 押さずに止まる形に戻すと答えない（U-8 の VM の確かめ） |

## 8. 決めること

推奨を 1 つずつ書く。U-22 は決まった（2026-11-23、親が推奨案で決めた）。

| ID | 決めること | 推奨 | 理由（1 行） |
|---|---|---|---|
| U-9 | 宣言の区分を 3.3 の 10 個にし、`ncsettings`・`pasteprivacy`・`realservice` を VM だけにする | **案のとおり** | この Mac の設定を変えるもの・実のサービスを開くものを、許可の誤りでも選ばれない形にできる |
| U-3 | 結果の行の番号を `#<n> <本文>` の 1 つの値にし、余分な完了の 2 秒をすべての完了に当てる | **案のとおり** | 今の Clipboard と同じ形で、0e の二重の完了を捕まえられる |
| U-4 | 受け手を起動の処理の 1 か所だけにし、`onAppear` の上書きをやめる | **案のとおり** | 今は画面を開くと起動の処理の受け手が消え、コールドスタートのイベントを入れ物に書けない |
| U-5 | `Options`・テキストの欄はサンプルのバナーの根の中だけ、返信の placeholder をサンプルだけの文に | **案のとおり** | VM で通知センターに別の通知の `Options` が同時にあった。根の外のものを押すと私物の通知で返信しうる |
| U-7 | 通知の許可のテストは VM だけ。この Mac では何も押す前に読んで、`authorized` でなければ止める | **案のとおり** | 許可を戻せるのは VM だけで、この Mac で問い合わせを出すと利用者の設定が変わりうる |
| U-11 | パネルは Cmd+Shift+G で `/private/tmp/ntk-uitest-<ID>/` に移り、移った先を確かめてから選ぶ | **案のとおり**（不安定なら、0b でサンプルに試験用の起動の引数で `directoryURL` を渡す形に替える。VM の sandbox の試作で、コンテナーの外の `directoryURL` は効いた） | 開く場所は前に使った私物のフォルダーで、ホームの外なら結果に名前が入らない |
| U-17 | 識別子のボタンの名前を、ボタンの文字から括弧を除いた大文字の始まりのまま | **案のとおり** | macOS の Clipboard の 36 個と同じ規則 |
| U-20 | この Mac の画面の共有中の通知の設定は利用者が入れ、見張りは `notification` を選んだ回だけ | **案のとおり** | 利用者の通知の設定を読まず、許していない通知を出さない |
| U-21 | `coldstart` の宣言と、余分なコピーを外す許可（`--allow-lsregister`、印で固定）を分ける | **案のとおり** | 起こすことを許しただけで、見ていないコピーまで外さないため |
| U-22 | コールドスタート NC1〜NC3 を 0c に入れる | **決まった** | DoD の 0c の行。0e・0g の変更で壊れうる所を基準で守る |
| U-23 | この Mac で組む Xcode | **26.6**（D-21）。UI テストが流せなければ 26.3 で流し、「26.6 での基準ではない」と環境を別に記録する。Xcode の共有の部品を直す操作（`-runFirstLaunch` など）は別に許可を得る | 配る dist と同じ Xcode |
| U-24 | ランナーの共通化 | **共通のモジュール（例 `scripts/apple_ui_runner_common.py`）に純粋な関数だけを出す**。条件: 共通化の前後で iOS の自己テスト（`scripts/tests/test_ios_ui_runner.py`）と変異（`ios_ui_runner_mutations.py`）をすべて流して同じ結果であること、共通のモジュールを iOS と macOS の両方の許可の一覧の「ランナーのファイル」に入れてハッシュで固定すること、iOS の信頼する部分の変更として別のモデルのレビューを通すこと。実行先・ファイル・台帳の adapter は共通にしない。条件を満たせないなら「写して始め、0d の後に共通化を別の作業にする」 | 写すと 2 つの照合が別れて直す所が倍になる。ただし iOS の守りを変えるので、iOS の確かめをやり直すことが前提 |
| U-25 | VM の道で組む場所 | **VM の中で組む**（Xcode 26.3、ad-hoc） | 0a とこの文書の確かめで動いた形。チームの署名を VM に入れない |
| U-26 | 今の Clipboard の 17 件 | **検査の中身を残し、ナビの補助と C9 の戻るの 1 行、`tap`・範囲の選択・スクロールの操作を `SampleApp` の守りの口に替え、待ちの規則の本体を `Support/` に移してから固定する** | 本体は既に識別子と錨で待っている。戻るは補助でなく本体にあった |
| U-27 | 今の Share の 17 件と雛形 3 件 | **Share は S1〜S17 に置き換え、雛形は消す** | 文字で探し部分一致で比べ、15 で 3 件落ち、この Mac で Mail を開く |
| U-28 | ShowDialog のヘルプで完了が 2 回来る今の動作を期待値にする（D5） | **案のとおり**（中間の結果は `dialog.resultHistory` で読む。1b で DH1 に替える） | 「今の動作を基準にする」 |
| U-29 | **この Mac の単体テスト** | **この Mac では、監査した hostless の単体テストだけを名指しで流す**: `MacLibraryTests` のうち、名前付きか unique の貼り付け板と mock だけを使い、通知センターと本物の共有のサービスに届かないと読んで確かめた suite を `scripts/mac_unit_audit.json`（suite、理由、確かめた日）に載せ、ランナーはそこに無い suite を選ばない。**監査はコードに結ぶ**: 監査の表に、監査したときの `mac/MacLibrary/` の木（`MacLibrary` と `MacLibraryTests` のソースと、`MacLibrary.xcodeproj` のビルドの設定）のハッシュを持ち、今の木と違えば、その表は失効したものとしてこの Mac では単体テストを 1 件も選ばない（VM では流す）。まずは木全体のハッシュで始め、suite ごとの依存の範囲に絞るのは後でよい。あわせて、監査した suite のファイルに `NSPasteboard.general`・`UNUserNotificationCenter.current`・`NSSharingService(`・`NSWorkspace`・`TEST_HOST` の設定が無いことを機械で照らす。監査の表自身のハッシュも許可の一覧に入れる。**`MacLibraryExampleTests`（サンプルをホストにして通知の delegate を入れる）と、固定の待ちを直すまでの `SharePickerPresenterTests` は VM だけ**。単体テストの名指しの一覧も許可の一覧に入れる | iOS の「実機では単体テストを流さない」と同じ考えで、宣言の表の外のテストが私物に触れないようにする（決まりの区分 1 の「宣言の前に洗う」） |
| U-30 | **26 と ja のシステムの UI の木の取り方** | **ja は VM で取る**: VM の表示の言語を一時的に ja にして 15 の木のラベルを取り、`SystemLabels` の表に入れて en に戻す（VM なので許可なし）。**26 はこの Mac で、許可を得た区切りに「適格性の確かめ」を 1 回行う**: 別の試験のクラス（`MacQualificationProbeTests`。この Mac だけ）が、サンプルの根・サンプルのピッカー・サンプルのパネルの**中だけ**で、表の候補（identifier とラベル）がちょうど 1 つあるかを、真偽と件数だけで出す（階層・ラベルの文字・ほかのアプリは出さない）。**結果の運び方**: 候補 1 つにつき 1 つのテストのメソッドにし（成功 = ちょうど 1 つあった）、結果の種類（passed / failed）だけで運ぶ（3.4 の一覧の中）。クラスは宣言の表に入れ（`notification`・`sharepicker`・`panels`・`clipboard` のうち使うもの）、VM の列挙にも出す（柱 2 の照合はそのまま）が、ランナーの `QUALIFICATION_ONLY_TESTS` の表で普段の実行と基準から除き、`--qualification` の計画でだけ選ぶ。根は「label が `MacLibraryExample` で始まり、`Immediate Notification` を含む group がちょうど 1 つ」で取り、区切りの形（`, ` など）を候補として照らす。`Reply` が一覧を開かずに入力できるかも候補に入れる（N24・NC3 の保留を解く条件。U-5）。3 回流して同じなら、2.1 のこの Mac の列を確定する。ja の段（`--qualification vm-ja`）の結果は en-US の基準と別に記録する。確かめるまでは 2.1 のこの Mac の列を `自動*` にし、確かめられなければ「26 は確かめない範囲」として記録する | 階層のダンプを出さずに 26 の差を知る方法で、私物の画面の文字を書き出さない |
| U-31 | **この Mac の署名と TCC** | **開発用のチームの署名（Automatic）で組む**。署名の ID・Team ID は 3.4 の一覧に入れず、表示もしない。最初の適格性の確かめ（U-30）で、組み直した後にアクセシビリティ・自動化の許可を許し直す要るか、前に許した通知の許可が引き継がれるかを確かめる。要るなら 6.5 の準備に書く | ad-hoc は組むたびに cdhash が変わり、利用者が毎回システム設定で許し直す見込みがある（測っていない）。VM で ad-hoc にした理由（チームの署名を VM に入れない）はこの Mac には当たらない |
| U-32 | **この Mac の基準の範囲** | **VM だけの 3 区分を除く 7 区分をすべて許し、U-29 の単体テストを含めた回だけを基準にする**。`eligible`・`executed`・`excluded` と理由を記録する。区分を絞った回は比べるだけ | 区分を絞った回を基準にすると、DoD の「基準として記録」を薄く満たしてしまう（iOS の実機の基準は区分なしの 19 件だった） |
| U-33 | **15 で戻るボタンを押せないこと** | **戻る操作を使う M1b・M2・C9 を 26 だけにし、15 では M1a（起動し直して開く）で画面を開けることだけを見る**。26 でも押せなければ、**M1b・M2・C9 の 3 件を同じ規則で**この Mac の環境ごとの除外（理由つき、基準の `excluded` に記録）にする。M1a は画面を作り直すことも `onDisappear` も確かめないので、代わりにはならない。画面を離れたときに監視が止まることは、そのとき人の確認（HC を足す）に移す。**VM の区切り（0e・0f の後）では、画面を離れたときの監視の停止を見ない**。見るのはこの Mac の区切り（0g・1b の後）だけ | VM で 6 通りの押し方がどれも効かなかった。原因が分からないまま待つと 0d の VM の基準が取れない |

## 9. 未確認のこと

### 9.0 VM で確かめたこと（事実）

2026-11-23、VM `ntk-macos-15-new`（15.8.3）。この Mac では何も動かしていない。試しのテスト（`Stage0bProbeTests`）と、sandbox の試作の `directoryURL` を環境変数で変える版は、VM の写しにだけ置いた。VM の設定を変えたのは、サンプルの subsystem（`com.unity.native.toolkit`）の debug のログを保存する設定（確かめた後に既定に戻した）と、通知の UI の daemon の立て直しだけ。試しのテストのファイルは VM の写しから外し、試作の元のソースに戻して組み直し、fixture を消した。

1. **VM の状態**: `tart run` の引数は `--no-graphics --no-clipboard`。VM の中で `kern.hv_vmm_present` が 1、`hw.model` が `VirtualMac2,1`（この Mac は 0）。`MobileMeAccounts` の `Accounts` は無い。`Accounts4.sqlite` のアカウントは `HolidayCalendar`（認証済み）、`OnMyDevice`、`iTunesStore`（有効でなく認証していない）の 3 つ。`virtiofs` の mount は無い。言語は en-US、`dndMirrored` は false、`xcode-select` は Xcode 26.3。`~/Library/Mail/V10` にフォルダーが 1 つある（0a で Mail が起動したため。中身は見ていない）
2. **戻るボタン**: 0a の結果のバンドルの C9 の記録では、戻るのクリックの 3 秒後もまだ Clipboard の画面（`clipboard.observeStatus` が `Observing`）で、補助の `openMenuCard` は文字 `Clipboard Example` のツールバーの題を押していた。このバンドルの添付には画面の動画（`.mp4`）があった。さらにサンプルで、戻るボタン（`chevron.backward`、label `Back`、枠 `{{147, 95}, {38, 40}}`、`isHittable == true`、ちょうど 1 つ）を、クリック、Cmd+[、親の group の中の座標、1 秒待ってからのクリック、0.2 秒の長押し、hover の後のクリックの 6 通りで押し、**どれもメニューに戻らなかった**。Clipboard の画面からも Dialog の画面からも同じ。原因は分からない（枠が幅 8 の group の中にあるように見えるのは推測の手がかりのまま）。同じ階層で、スクロールの右端に識別子の無い `Button` が 2 つあった
3. **パネル**: サンプルの ShowFileDialog で、パネル（`open-panel`）の中で Cmd+Shift+G → `/private/tmp/ntkfx/` → Return で fixture に移り、`a.txt` を選び、確定のボタン（identifier `OKButton`、label は空。取り消しは `CancelButton`）で開けた。結果は `✅ \nResult: ShowFileDialog - result: OpenDialogResult(filePaths: ["/private/tmp/ntkfx/a.txt"], fileCount: 1, directoryURL: "/private/tmp/ntkfx", isCancelled: false, isSuccess: true)`。保存のパネルは `Replace` の確認が出て、押すと `SaveDialogResult(filePath: "/private/tmp/ntkfx/default.txt", fileCount: 1, directoryURL: "/private/tmp/ntkfx", isCancelled: false, isSuccess: true)` を返し、fixture の 4 つのファイルのハッシュは変わらなかった。`note.md` の行は `isEnabled == true` と読めた（`allowedContentTypes` は `txt`・`png`）。同じテストの 2 回目は、`a.txt` を押す所で「アプリの idle を待つ」まま 7 分以上止まり、止めた（原因は調べていない）。sandbox ありの試作で `directoryURL` に `/private/tmp/ntkfx` を渡すと、パネルはそこで開いた（`a.txt` が並んだ）
4. **通知の根**（サンプル、`Options` を持つ category を登録した 10 秒の予約）: バナーの label は `MacLibraryExample, 10s Notification, MacLibraryExample, Will be shown after 10 seconds`（アプリ名、題、副題、本文）。hover すると根の中に `Options` が 1 つ出たが、通知センターの木には別の通知（「Tips」）の `Options` もあり、全体では 2 つだった（2 回とも）。`Options` を押すと開くメニューは根の外にあり、項目は全体で 141〜143（ほとんど label が無い）。`Open` の項目は `menuItems["Open"]`（identifier か title）で取れて押せたが、`label == 'Open'` で数えると 0 だった（label は空）。category を外した通知の根には、hover しても `Options` が無かった（全体の 1 つは「Tips」のもの）`Reply` を選ぶと、通知は一覧（`AXNotificationListItems`）の中で広がり、**根の中に焦点を持つ `TextView` が 1 つ**出て、`Open`・`Reply` のボタンが並び、**`Send` のボタンはどこにも無かった**
5. **コールドスタート**（サンプル。sandbox、SwiftUI、`App.init` で delegate）: 初めの状態は `notDetermined` だった（`com.apple.ncprefs` の `apps` にサンプルの項目があっても未決だった）ので、試しのテストの中で許可した。`terminate` の後に 10 秒の予約の根を押した結果: **本文のクリック**は 2 回のうち 1 回、サンプルが前面に来てメニューのカードが出た（もう 1 回は、予約の後の GetScheduled の結果が 10 秒出ず、根も 25 秒出なかった。原因は調べていない）。**`Options` → `Open`** は 2 回とも前面に来た。**`Options` → `Reply` → 根の中の `TextView` に入力 → Return** は 1 回送れて、前面に来た（`Send` のボタンを探した 1 回目は送れなかった）。サンプルの debug のログを一時的に保存して読むと、起こされたプロセスで `App.init` の受け手に `[ActionReceived] notificationId: mac-sample-notification, actionId: open` と `[TextActionReceived] ... actionId: reply, userText: cold probe` が届いていた。**途中で送れずに広がったままの通知は一覧に残り、`RemoveAllDelivered` の後 15 秒たっても消えず**、次の回の `label CONTAINS "10s Notification"` の `firstMatch` がそれを掴み、本文のクリックでサンプルが起きず、`Options` も見つからず、`ShowImmediate` のバナーも出なかった（通知センターの一覧が開いたままだったと見ている。推測）。通知の UI の daemon（`NotificationCenter`、`usernoted`）を立て直すと戻った
6. **列挙**: 0a のビルドの `.xctestrun` で `-enumerate-tests`（flat、json）が 7 秒で終わり、`MacLibraryExampleUITests/<クラス>/<メソッド>()` の形で、今の 37 件と VM の写しにだけある試作、単体テスト（`MacLibraryExampleTests` 20 件）を出した。`testLaunch` は 1 件。**下書きで「列挙の後のログにサンプルとランナーの起動の跡は無かった」と書いたのは誤り**: その確かめは VM の zsh の組み込みの `log` を呼んでいて（`/usr/bin/log` でなかった）、何も読めていなかった。列挙が何かを起動するかは確かめていない（9.3）

### 9.1 0b・0c の最初に VM で確かめること

| 項目 | 関わるケース |
|---|---|
| サンプルでの、前面・後ろのバナー、根の中の `Options`、コールドスタートの 3 経路が、通知の UI をきれいにした状態から 3 回とも通るか | N4〜N24、NC1〜NC3 |
| sandbox の UI テストのランナーから `CGWindowListCopyWindowInfo` で、画面の窓の持ち主の PID・枠・層を読めるか（名前は読まない。画面の収録の許可が要るか）。読めなければこの Mac では UI テストを流さない | 5.0 の押す前の確かめ |
| サンプルの `Bundle.main.bundlePath` が実体のパス（`/private/var` と `/var`、symlink）か | U-21、NC1〜NC3 |
| おとりの通知（試作）とサンプルの通知の並ぶ順を、前と後の両方に作れるか | 7 章の「根（動き）」 |
| コールドスタートの T0 から `notRunning` までの時間（予算 6 秒に収まるか） | NC1〜NC3 |
| `executionTimeAllowance` の値の扱い（分に切り上げられるか） | 5.0 の時間切れ |
| 根の中の `TextView` に入れて Return で送れるか（`Send` が無い） | N24、NC3 |
| 通知センターの一覧が開いたままになったとき・広がった通知が残ったときの戻し方（VM の daemon の立て直しのほか、テストの中でできる安全な操作） | U-15 |
| 監視が何に来るか、`terminate` と `true` の後にテストが止まるか（VM に無害な試験用のアラートを置く） | U-8 |
| 許可の問い合わせの `Don’t Allow`、サンプルの id での `ncreset` | NP1〜NP3 |
| category の無い通知の根に `Options` が無いこと | N20 |
| アラートの 3 つ目のボタンの identifier、チェックボックスの型、結果の全文 | D1〜D6 |
| パネルの「アプリの idle を待つ」止まり（2 回のうち 1 回）の原因と、移った先の今の場所の読み方 | D8〜D17 |
| システム設定の bundle id と前面の判定、Dock のバッジ | N3、N19 |
| +1 分の発火（秒の窓の後）の時間 | N6、N9、N14、N14b、N16 |
| sandbox のサンプルに `defaults write` でプレビューの設定が効くか、元の値に戻るか | CB2〜CB6 |
| プレビューなしの `PasteButton` で確認が出ないか、`clipboard.pasteButton` の中の `PasteButton` を取れるか | CB1、I1d |
| I1 のスクロールバーの部品の除き方、1 回の snapshot に画面の外のボタンが入るか | I1a〜I1d |
| `ShareError` の文、除外しないピッカーに `Add to Reading List` が出るか、CanPerformMail の値、Mail の問い合わせが通知のテストに重ならないか | S10〜S17 |
| ja のラベル（VM の言語を一時的に ja に） | U-30 |

### 9.2 この Mac で初めて確かめること（区切りで許可を得て、U-30 の形で）

- 26.7.3 のシステムの UI の候補（根、`Options`、パネルの `OKButton`、ピッカーの `Copy`、戻るボタン）がサンプルの部分木の中にちょうど 1 つあるか。この Mac の表示の言語
- 戻るボタンを押せるか（M1b・M2・C9）
- `Reply` で通知センターの一覧が開くか（開かなければ N24・NC3 の保留を解く。U-5）
- Xcode 26.6 で UI テストを流せるか、チームの署名のサンプルとランナーで許し直しが要るか（U-31）
- 26.7.3 の `accessBehavior` の既定と、`PasteButton` で確認が出ないか（CB1）
- 集中モードと画面の共有中の設定の下で、サンプルのバナーが出るか（N4 の見張り）
- LaunchServices のサンプルのコピーの数
- 監視が実際にテストを止めること（U-8）を VM で確かめた後でなければ、この Mac では流さない

### 9.3 0d の最初に確かめること

- `TEST_RUNNER_` の環境変数が macOS の `test-without-building -xctestrun` でランナーに届くか
- macOS のテストのバンドルを `otool` で読み、テストのメソッドの selector を取れるか
- 画面の動画とスクリーンショットを撮らせない方法（`-collect-test-diagnostics` は sysdiagnose のような診断の話で、動画を止めるとは書かれていない）。止められなくても 3.4 の境界は変えない
- VM の Mail のアカウントの有無を機械で確かめる方法（`~/Library/Mail/V10` のフォルダーの中身の意味）
- 作業ツリーを `git ls-files` と `tar` で渡す形で、framework の symlink とファイルのモードが保たれるか
- 字句の分け方で、固定するファイルの正規表現の literal を正しく扱えるか
- 許可の台帳の置き場所と、途中で止まったときの扱い（ID は消費済みのまま）
- `-enumerate-tests` がサンプルやランナーを起動しないこと（`/usr/bin/log` か `ps` の記録で確かめ直す。この Mac では列挙しないので、VM の道の判断に使うだけ）

### 9.4 サンプルとライブラリで気になった動作（段階 0 では直さない）

| 動作 | 扱い |
|---|---|
| ShowImmediate の id が `mac-sample-notification-<秒>` で、RemoveDeliveredById などの `mac-sample-notification` と違う | 今の動作のまま期待値（N11） |
| `calendarComponents(afterMinutes:)` は秒を 0 に切るので、+1 分の予約は押してから 0〜60 秒後に発火する（iOS のサンプルは秒を残す） | U-14c の秒の窓で扱う |
| 通知の受け手を起動の処理と画面の `onAppear` の 2 か所で設定し、画面を開くと上書きされる。`setup()` が受け手の設定より前 | 0b で直す（U-4） |
| ShowDialog のヘルプで完了が 2 回来る | 今の動作のまま期待値（D5）。1b で DH1 |
| Share の結果の `service=` が表示名で、言語で変わる | U-2 の表で引く |
| Show*・Schedule*・SetBadgeCount は、許可が未決なら問い合わせを出す（`runWithPermission`） | 宣言 `notification` に含め、片付けで押さない（U-15） |
| 保存のパネルは結果のパスを返すだけで、ファイルを書かない | 不備ではない。D13・D15 で書かれないことを確かめる |
| `cancel` と `cancelScheduled`、`cancelAll` と `cancelAllScheduled` が同じ処理 | 今の動作のまま期待値（N8、N16） |
| 15.8.3 のサンプルで、XCUITest から戻るボタンを押せない | U-33 |
| 開くパネルの種類の絞り込みで、選べない行も `isEnabled == true` と読める | D9 は HC7 |
| `DetectPatterns`・`DetectValues` は押すと先に検出用の文を書き直す | CB6 で外の内容の経路を作らない理由 |
