# 段階 0d の作業の記録

- 記録日: 2026-11-23
- 段階: 0d（テストのランナー `scripts/test_mac.sh` と基準。企画 5 章、UI テストの設計書 `designs/2026-11-23-macos-c-abi-ui-test-design.md` の 3 章・6 章・7 章・8 章）
- 状態: ランナーを作り、VM の道で全件を 1 回流して VM の基準を取った。この Mac の道は `--dry-run` の出力までを確かめた（流していない）。`036dc083` でコミットした。ランナーのレビュー v1（`reviews/2026-11-23-macos-c-abi-runner-review-v1.md`）の直しを `da6889a5` でコミットした（10 章）。レビュー v2（`reviews/2026-11-23-macos-c-abi-runner-review-v2.md`）の直しを `d89f9d46` でコミットした（11 章）。レビュー v3（`reviews/2026-11-23-macos-c-abi-runner-review-v3.md`）の直しと取り直した VM の基準を `1473c7ca` でコミットした（12 章）。レビュー v4（`reviews/2026-11-23-macos-c-abi-runner-review-v4.md`）の直しを `92b984ee` でコミットした（13 章）。レビュー v5（`reviews/2026-11-23-macos-c-abi-runner-review-v5.md`）の直しを `8834eb6f` でコミットした（14 章）。レビュー v6（`reviews/2026-11-23-macos-c-abi-runner-review-v6.md`。致命的な A は 0 で、利用者の指示によりランナーのレビューはこれで閉じる）の直しは 15 章で、コミットしていない
- 元にした版: `623a919b`（feature/NTKIT-19、0c の終わり）
- 環境: この Mac では UI・通知・クリップボードを使うものを何も動かしていない（組むのも VM の中だけ。この Mac で動かしたのはランナーの自己テスト、`--dry-run` の読むだけの操作と、レビュー v1 の前に限り変異のハーネス。設計書 7 章は変異を VM だけとしているので差。10 章のとおり、レビュー v1 の後は変異を VM の中だけで流し、この Mac の自己テストは本物の OS の操作に届かない形にした）。動かす確かめは VM `ntk-macos-15-new`（macOS 15.8.3、Xcode 26.3、en-US、`--no-graphics --no-clipboard`）だけ。区分 1 の単体テストもこの Mac では流していない

## 1. 作ったもの

| ファイル | 中身 |
|---|---|
| `scripts/test_mac.sh` | 薄い殻（bash 3.2。この Mac と VM の両方の `/bin/bash`）。`--where vm\|mac` で道を選ぶ。VM の中の半分（`--in-vm <op>`。clean・build・enumerate・check-build・prepare・unit・ui・privacy-begin/end・coverage・finish）も同じファイルにあり、tar で VM に渡して ssh で呼ぶ。`--in-vm` は最初に `kern.hv_vmm_present` が 1 でなければ 96 で止まる |
| `scripts/mac_ui_runner.py` | 判定のすべて（純粋な関数と小さな CLI）。VM の `/usr/bin/python3`（3.9）でも動く形 |
| `scripts/mac_unit_audit.json` | U-29 の監査の表（この Mac で流してよい `MacLibraryTests` の suite。2 章の 2.6） |
| `scripts/tests/test_mac_ui_runner.py` | 自己テスト（4 章） |
| `scripts/tests/mac_ui_runner_mutations.py` | 変異を流す仕組み（4 章。単体テストではない） |
| `scripts/tests/fixtures/mac_ui_runner/` | VM で取った実物（列挙の JSON、`otool -ov` / `-l`、`xcresulttool` の JSON。VM のホームは `<home>` に置き換えた） |
| `scripts/test_mac.baseline.vm-15.8.3.json` | VM の基準（5 章） |
| `mac/.gitignore` | `/MacLibraryExample/build/`（ランナーの出力。3.4） |
| `scripts/README.md` | `test_mac.sh` と基準のファイルの行、使い方、`tests/` の説明に `test_mac.sh` を足した |

U-24（共通化）は**写して始めた**: 共通のモジュールにするには「iOS の信頼する部分の変更として別のモデルのレビューを通す」ことが条件で、この作業の中では満たせないため（設計書の推奨の「満たせなければ写して始め、0d の後に共通化を別の作業にする」）。iOS のファイルは変えていない。iOS の自己テスト（`scripts/tests/test_ios_ui_runner.py`）は 228 件が通った（変えていないことの確かめ）。iOS の変異は、iOS のファイルを変えていないので流していない。

### 1.1 オプション

| オプション | 内容 |
|---|---|
| `--where vm\|mac` | 必須。ほかの値と省略は拒む。VM の資格が成り立たないとき、この Mac の道に切り替えずに止まる |
| `--vm <名前>` | 既定は `ntk-macos-15-new`。この Mac の道も列挙をこの VM で行う |
| `--feature` | その機能の UI テストと共通のクラスだけ。単体テストは流さない |
| `--skip-unit` | 単体テストを流さない |
| `--allow <区分,...>` | `mac` だけ。VM だけの 3 区分は拒む |
| `--allow-lsregister` | `mac` だけ。**今は実装しておらず、渡すと止まる**（9 章） |
| `--dry-run` / `--approved <file>` | `mac` だけ。どちらか一方が必須 |
| `--baseline` | 6.3 の基準の条件を満たすときだけ保存する。前の基準は日付つきの名前に移して残す |
| `--name-each-test` | `vm` だけ。1 件ずつ呼ぶ（この Mac はいつも 1 件ずつ） |
| `--qualification <mac26\|mac26-reply\|vm-ja>` | 選び方の口だけある。探りのテスト（`MacQualificationProbeTests`）はまだ無いので、選ばれるテストは 0 件（この Mac では「選ぶテストが無い」で止まる） |
| `--keep-vm-run` | `vm` だけ。VM の実行のフォルダー（ソース・DerivedData・結果のバンドル・ログ）を残す（調べるため。設計書に無いオプション） |

## 2. ランナーの中身

### 2.1 VM の道（6.3）

1. この Mac で閉じた形の規則（6.1）を照らす
2. **資格の確かめ**（純粋な関数 `vm_qualification` と `tart_run_problems`）: この Mac の `ps` から tart の実行ファイル自身の `tart run <VM>` がちょうど 1 つで `--no-clipboard` があり `--dir`・`--net-bridged` が無い。VM の中（VM 専用の鍵、固定した known_hosts、`StrictHostKeyChecking=yes`、`BatchMode`）で `kern.hv_vmm_present` が 1、`hw.model` が `VirtualMac` で始まる、15.8.3（24H241）、`MobileMeAccounts` が無い、`Accounts4.sqlite` のアカウントが許した種類（`HolidayCalendar`・`OnMyDevice`・`iTunesStore`）だけで、認証済みは `HolidayCalendar` だけ、`virtiofs` の mount が 0、Xcode 26.3（17C529）、`IOPlatformUUID` が読める。読めない・欠けた事実は不合格。言語は資格と別に en-US を求める（`vm-ja` のときだけ ja）。生の値は一時ファイルに置いて読んだ後に消し、出すのは項目ごとの合否と出どころの符号（`cirrus-vanilla-15.7.7+15.8.3`）だけ
3. **同一性の束ね**: 以後のどの ssh の命令も、先頭で VM の `IOPlatformUUID` が資格を確かめたときと同じかを照らし、違えば 96 で止まる
4. **受け渡し**: `git ls-files -co --exclude-standard -- mac`（`mac/MacLibraryExample/build/` を除く）を `tar --null -T` で ssh に流し、ランナーの 2 ファイルも渡す（`~/ntk/runs/<実行の ID>/`）
5. **前の回の片付け**（VM の中）: 前の回の xcodebuild・サンプル・Mail・前の回のフォルダーから起きたプロセスを止め、プレビューの設定が残っていれば戻し、前の回のフォルダーと fixture を消す
6. **組む**: Xcode 26.3、ad-hoc。`MacLibraryExample` のスキーム（サンプル・`MacLibraryExampleTests`・UI テスト）と `MacLibrary` のスキーム（`MacLibraryTests`）を別の DerivedData に組み、それぞれ `.xctestrun` がちょうど 1 つかを照らす
7. **列挙と照合**: `-enumerate-tests -test-enumeration-style flat -test-enumeration-format json`。宣言の表との完全一致、クラスの集合、クラスの下限、ランナーの表のキーがすべて宣言にあること、固定したクラスのメソッド。バンドルの中の表のハッシュと `Info.plist`、**組んだテストのバンドルを `otool` で読み列挙と照らす**（設計書は柱 2 の⑤をこの Mac の道にだけ置くが、読み方の確かめとして VM でも行う）
8. **VM の準備**: `dndMirrored=false` と通知の UI の立て直し、今の実行の外の LaunchServices の登録を外す、fixture を作って中身を記録、`TEST_RUNNER_NTK_EXPECTED_COPY` を計算
9. **単体テスト**: `MacLibraryTests` と `MacLibraryExampleTests` を丸ごと
10. **権限の段**: NP2 → NP3 → NP1 の各前に許可を戻す（サンプルが止まるのを待つ → `com.apple.ncprefs` から消す → 消えたことを確かめ、3 回まで繰り返す。0c 2.6 の 16）
11. **UI テスト**: 共通 → Dialog → Notification（見張り N4 が先）→ Event → ColdStart → Clipboard → Share の順。通知の 3 クラスは 1 件ずつ別の呼び出しで、クラスの先頭の前に通知の UI を立て直し、落ちたテストの後にも立て直す（立て直しの回数を環境に記録する）。ほかはクラスごとに 1 回の呼び出しで、選んだメソッドを名指しする。Share の後に Mail を止める。時間切れの 3 つの指定と `-parallel-testing-enabled NO`。**見張りが落ちたら残りの UI テストを流さず失敗に数える**（U-20）
12. **貼り付けの確認の段**: 前の値（無い）を `~/ntk/state/` に記録 → プレビューを入れる → CB2〜CB6 → 消して無いことを確かめる。途中で止まった回の値は次の回の片付けで戻す
13. **押したボタンの照合**（5.7。`--feature` なしのときだけ）: VM で添付を書き出し、VM の中で照らして判定だけを持ち帰る
14. **終わり**: fixture の照合（`.DS_Store` を除く）、サンプルと Mail を止め、今の実行の登録を外し、fixture と実行のフォルダーを消す。止まったときも trap で同じ終わりを呼ぶ

VM の中の結果の読み取り（`xcresulttool`）と 3.4 の一覧への変換は VM の中の `mac_ui_runner.py` が行い、この Mac に戻るのは公開の記録（1 行 1 件の JSON）だけ。この Mac の側でも、戻った行をもう一度 `public_record` に通し、外れた行があれば止まる。

### 2.2 この Mac の道（6.3）

- **読むだけの確かめ**: `sw_vers` が 26、Xcode 26.6 がある、閉じた形の規則
- **列挙は VM で**（2.1 の 1〜7）。終わったら VM の実行のフォルダーは消す
- 前の回の残り（`NTK-STALE:alive`。2.4）を読むだけで数える。`coldstart` を許すときだけ、この Mac の `lsregister -dump` を私的な一時フォルダーに書いて読み、不透明な印と置き場所の種類だけを出してすぐ消す
- `--dry-run`: 流すテスト・除くテストと理由（`ExclusionReason`）・単体テストの名指し・この Mac に起きること・準備・時間の見込み・余分なコピーの印・許可の ID を出し、許可の一覧（`mac/MacLibraryExample/build/test_mac/<ID>-mac/approval.json`）を書いて止まる
- `--approved`: 計画を作り直して許可の一覧と丸ごと照らし（ID と時刻のほか）、ランナーの 3 ファイル（`mac_ui_runner.py`・`test_mac.sh`・`mac_unit_audit.json`）がコミット済みで同じ、`mac/` にコミットしていない変更が無い、`HEAD` と `mac/` の木のハッシュが同じ、を確かめてから台帳（`~/Library/Application Support/native-toolkit/test_mac-approvals.log`）に ID を記録する。その後、私的な一時フォルダー（`umask 077`、`$TMPDIR/ntk-test-mac.XXXXXX`）と印のファイルを作り、**最初の xcodebuild の前に** trap（EXIT と INT・TERM・HUP）を登録する。計画と許可は一時フォルダーの読むだけの写し（0444）に替え、**どの xcodebuild の前にも** `gate`（計画の digest・台帳・ランナー・木）を通す（R-19）。xcodebuild は自分の process group で動かし、その PID・開始時刻・実体のパスを印に記録する
- 組む（Xcode 26.6、プロジェクトのチームの署名。U-23・U-31）→ `otool` の照合 → `coldstart` なら登録の数え直し（1 つでもあれば止まる）→ fixture → 監査した単体テスト → UI テストを 1 件ずつ（見張りが先。見張りか通知のテストが落ちたら残りを流さず失敗に数える。結果のバンドルが一時フォルダーのものかを照らす）→ fixture の照合 → 残したものの表示 → 要約
- 中断の順（`mac_cleanup`）: xcodebuild の group に TERM → 30 秒待つ → KILL、一時フォルダーの道から起きたプロセスを止める、今の実行の登録を外す、その後に一時フォルダーを消す。消せなければ場所を出さずに知らせて 0 でない終了

### 2.3 選び方（柱 1）と表

| 表 | 中身 |
|---|---|
| `VM_ONLY_CATEGORIES` | `ncsettings`・`pasteprivacy`・`realservice` |
| `VM_ONLY_TESTS` | 空（VM だけのテストはどれも区分で VM だけになる）。表は残し、キーは宣言の表に無ければ止まる |
| `OS_ONLY_TESTS` | M1b・M2・C9・S2・S4 → 26 |
| `MAC_DEFERRED_TESTS` | N20・N23・NC2（`notificationMenuItem`、理由 `ownerUnverified`）、N24・NC3（`notificationMenuItem` と `replyInBanner`、理由 `macDeferred`）、CB1（`pasteButton`）、S2・S4（`pickerCopy`）。押す相手がすべて `MAC_VERIFIED_TARGETS`（U-30 の結果を写す表。今は空）にあるときだけ選ぶ |
| `QUALIFICATION_ONLY_TESTS` | 3 つの段とも空（探りのテストがまだ無い） |
| `ENVIRONMENT_EXCLUSIONS` | 空（U-33 で 26 でも戻れなければ M1b・M2・C9 をここに入れる） |
| クラスの下限 | Clipboard の 2 クラスに `clipboard`、`ClipboardPrivacyUITests` に `clipboard`・`pasteprivacy`、Event に `notification`、ColdStart に `notification`・`coldstart`、権限に `notification`・`ncsettings`。`ShareUITests` は `sharepicker` か `realservice` のどちらか（設計書に無い形。S11・S12・S17 は `realservice` だけのため） |

`SupportRuleTests`（規則の自己テスト 24 件）は共通のクラスとして、どの `--feature` でも流す。

### 2.4 3.4 の境界、強制終了の後、LaunchServices

- 公開の記録の形は `test`（テストのキー、または `<ターゲット>#<ランナーの問題の名前>`）・`result`・`kind`（passed / failed / skipped / watchStopped / notificationStopped）・`codes`・`seconds`・`runs`・`invocation` だけ。`codes` は失敗の文から `NTK-STEP:`（`Support/StepCode.swift` の enum の値だけ。38 個）・`NTK-GATED:<区分>`・`NTK-PRECONDITION:<名前>`・`NTK-INTERRUPTED` を取り出したものと、ランナー自身の `NTK-RUNNER:`・`NTK-STOP:` だけ。失敗の文そのものは出さない
- 強制終了の後（`stale_plan`）: 印の起動の時刻が前なら止めずに消すだけ、後なら（時計の食い違い）止まる。同じ起動なら、PID・開始時刻・実体のパスの 3 つが一致するプロセスと、前の回のフォルダーの下の実行ファイルで印の後に起きたプロセスを書き手とする。group へ送るのは leader が書き手で、group の全員が Xcode の中か前の回のフォルダーの下のときだけ。`--dry-run` は数だけを出し（`NTK-STALE:alive`）、許可を得た実行で TERM → 30 秒 → KILL → 消えたことを確かめてから消す
- LaunchServices（`lsregister_copies`）: サンプルとランナーの bundle id の登録のうち今の実行の外のもの。印は実体のパスの SHA-256 の先頭 12 文字、置き場所は `derivedData`・`repository`・`applications`・`other`

### 2.5 U-30 の `classify_reply_state`

設計書のとおり、`Reply` の前の根の枠・前と後の通知センターの窓の枠・後の返信の欄から「一覧」「バナーの中」「分からない」を返す純粋な関数を作り、判定表を自己テストにした。余白の値は VM で決めることになっている（9.1）が、まだ測っていないので引数のまま（呼ぶ所は `--qualification mac26-reply` の段で、まだ無い）。

### 2.6 U-29 の監査（`scripts/mac_unit_audit.json`）

`MacLibraryTests`（Swift Testing、ホストなし、31 suite）を読み、私物に届かないと読めた **20 suite** を載せた。語の照らし（`AUDIT_WORDS`）の数は suite ごとに「許した出現」として理由つきで書いた（`.general` は mock や追跡の鍵に渡す値だけ）。載せなかった 10 suite と理由も `notListed` に書いた（本物の `NSPasteboard` を使う `ClipboardRepositoryImplTests`、`.general` の `accessBehavior` を読む `ClipboardDetectionMapperTests`、`resolve(.general)` の `PasteboardResolverTests`、本物の coordinator や既定の manager を作るもの、`SharePickerPresenterTests`）。読み切っていない suite は載せていない。

監査は `mac/MacLibrary/MacLibrary`・`MacLibraryTests`・`project.pbxproj` の木のハッシュに結んだ。**`review` が空のあいだは失効と同じに扱い、この Mac では単体テストを 1 件も選ばない**（`unitExcluded` に `auditExpired`）。別のモデルのレビューを通したら `review` を書き、表のハッシュは許可の一覧に入る。

## 3. 0c から移すと書かれたものの扱い

| 0c の申し送り | 0d でしたこと |
|---|---|
| 固定するファイルのハッシュとメソッド（3.1） | `FROZEN_FILES`・`FROZEN_METHODS` に入れた。`XCUIApplication` 9 回、識別子の文字列 10 か所も回数で照らす |
| 押す相手の表 | `MAC_DEFERRED_TESTS` と `MAC_VERIFIED_TARGETS`（2.3） |
| 閉じた形の規則（`supportRoot` を Support の外で禁じる） | 危ない名前に `supportRoot` を足した |
| 許可の戻し方と立て直しの決めごと（2.6 の 12・16・17） | VM の道の段にした（2.1 の 8・10・11） |
| プレビューの設定の出し入れ（3.5） | 2.1 の 12 |
| fixture の照合で `.DS_Store` を扱う（1.7 の 3） | 照合から除く（名前・種類・ハッシュは 7 項目と dirA・dirB の中で比べる） |
| 押したボタンの和集合の照合（5.7） | 2.1 の 13 |
| 宣言の表 `DeviceRequirements.json` | 柱 2 の照合のすべて |
| 信頼する部分のハッシュ | Support の 15 ファイルを `623a919b` の値で固定した。**別のモデルのレビューはまだ**。ハッシュが変われば、この Mac では許可の一覧を作っても流せない |

## 4. 自己テストと変異

**自己テスト**: `python3 -m unittest scripts/tests/test_mac_ui_runner.py` で **102 件、すべて通った**。VM もこの Mac の UI も使わない（例外は「強制終了の後」の 1 件で、一時フォルダーに `clang` で組んだ 60 秒眠るだけの実行ファイルを置いて起こし、印から見つけて止めてフォルダーを消すことを確かめる。`/bin/sleep` の写しは署名で殺されたので使わない）。シェルを呼ぶ 1 件は、`dirname`・`basename`・`python3` だけを置いた PATH で引数の検査だけを呼ぶ（壊れた検査がその先へ進んでも ssh・tart・xcodebuild・pkill・defaults に届かない）。

| まとまり | 確かめること |
|---|---|
| 名前・列挙と宣言（13） | 実物の列挙が宣言の表と完全一致（118 件）、単体テストと基底の行を落とす、別のクラスの行・errors・disabled・2 つの構成・読めない名前で止まる、重複・宣言の欠け・余分・新しいクラス・下限・`ShareUITests` の「どちらか」・表の改名・固定したメソッドの欠け、表の重複キー・知らない区分・区分の重複 |
| 選び方（16） | この Mac で VM だけと保留のテストを選ばない（99 件）、「すべて」で選ぶ（N18 は `badge` だけでは選ばない）、許さないときは宣言の無いテストだけ、VM だけの区分を `--allow` に渡すと止まる、VM は `--allow` を拒み 113 件、押す相手の表で保留が解ける形（`replyInBanner` が無ければ N24 は保留のまま）、`--feature` と共通のクラス、見張りが先で `notification` が無ければ見張りも無い、`notification` のテストを見張りなしで選べない、空の計画、VM の呼び出しの形（権限の順と戻し、通知は 1 件ずつ、立て直しの位置、Mail、プライバシーの段）、名指しが空・クラスでは呼ばない、xcodebuild の直前の二度目の確かめ、適格性の段 |
| 許可と台帳（9） | 同じ計画は通る、テスト・`--allow`・`HEAD`・知らないキー・欠けたキー・ID の形・順のどれを変えても拒む、別の計画、信頼する部分が変わった計画、VM には許可が無い、digest が呼び出しを覆う、ID は 1 回、壊れた台帳、台帳の場所 |
| VM の資格（5） | 今の VM は通る、各事実が違う・欠けると項目が落ちる、アカウント（Mail の種類・Apple アカウント・認証済みの `iTunesStore`・空・読めない）、`tart run` の引数（`--no-clipboard` なし・`--dir`・`--net-bridged`・2 つ・別の VM・zsh の行・`run <VM>` と読める別のプログラム）、言語 |
| 出力の境界（3） | 符号だけが通り文は落ちる（語彙の外の `NTK-STEP`、知らない区分）、記録のキー・値の形（パス・文・知らない種類・数でない秒と回数）、語彙は信頼する部分の enum から読む |
| 結果（9） | 正常な回、名指しとちょうど同じでない（欠け・重複）、知らない子・読めない名前・別のバンドルで止まる、バンドル無し・時間切れ・要約の食い違い、分類（gated・precondition・Expected Failure・一覧に無い skip は失敗）、**実物の Dialog の結果 17 件**、**実物の `MacLibraryTests` の 308 件（入れ子の suite、展開の後 352 回）**、引数の値を出さない、流さなかったテストは失敗 |
| 強制終了の後（8） | 書き手と group を止める、(a) 実行ファイル違い、(b) 開始時刻違い、(c) 前の起動の印と後の時刻の印、(d) 知らないプロセスの混ざった group、(e) 通知から起きたサンプル、壊れた印、本物のプロセス |
| 監査（5） | 語の数え方、許した出現との一致（`resolve(.general)`・`MacClipboardManager.shared`・数の違い・`NSPasteboard.general` を拒む）、理由の無い出現、失効と未レビューで何も選ばない（計画の `unitExcluded`）、リポジトリの表の形 |
| `classify_reply_state`（7） | バナーの中、余白のちょうど境界と 1 pt 外、窓の増加と広がり、欄 0・2・焦点なし・根の外、大きい 1 つの窓（前提が崩れる）、値の欠け、根を失った窓 |
| 基準（7）・押したボタン（2）・fixture（3）・LaunchServices（2） | changed / added / removed と除外の変化、skip による欠け、名前、基準の条件（VM・この Mac）、eligible / executed / excluded、見積もりが基準の秒を読む。ボタン 43 個がサンプルから出る、1 件 1 つの添付と全ボタン。`.DS_Store` を除いて変化を見つける、symlink、fixture の場所だけ。今の実行の外の登録だけを印で出す |
| 閉じた形の規則（6） | 今のフォルダーが通る、テストのファイルに `#if`・`final` なし・`import AppKit`・`supportRoot`・`typeText`・識別子の文字列・`XCTExpectFailure`・`extension`・`async` のテスト、固定したファイルの 1 行、信頼する部分の 1 行と新しい Support のファイル、正規表現の literal と割り算、バンドルの中の表 |
| 組んだバンドル（1） | 実物の `otool` で 118 件が列挙と一致、1 件欠け・重複で落ちる |
| シェルの順（6） | trap（EXIT・INT・TERM・HUP）が最初の xcodebuild より前で許可の消費より後、片付けが止めてから消す、この Mac の xcodebuild はすべて `mac_gate` を通る、ssh の命令がすべて同一性を照らす、`--in-vm` の最初の行が VM の確かめ、引数の検査 |

**変異**: `python3 scripts/tests/mac_ui_runner_mutations.py`。ランナーの写し（スクリプト、自己テスト、fixture、UI テストのフォルダー、サンプルのソース、pbxproj）で 1 つずつ壊して自己テストを流す。設計書 7 章のうちランナーに当たる行（柱 1〜3、二段目は 0c で済み、VM の資格、出力の境界、中断、強制終了の後、止める相手の取り違え、監査の照らし、段の符号）と、`classify_reply_state`・基準・押したボタン・fixture の判定を壊す **84 個**。

| 回 | 結果 |
|---|---|
| 1 回目 | 80 個が捕まり 4 個が生き残った: `#if` を許す（同じ所を 2 つの枝が見ていて、片方を壊しても捕まる形だった。判定を 1 つにまとめ、変異を `ALLOWED_POUND` に `if` を足す形にした）、tart の実行ファイルの絞り込みを外す（`run <VM>` と読める別のプログラムの行の自己テストを足した）、ssh の同一性の照合を外す（シェルの本文を読む自己テストを足した）、fixture の symlink の照合を外す（どちらにも同じ symlink がある場合の自己テストを足した） |
| 直した後 | 84 個すべて捕まり、変異なしの写しは通った |

試した変異は写しの中だけで、リポジトリには残していない（変異の一覧はハーネスのファイルに残る。iOS と同じ）。ハーネスは本物の台帳のフォルダーを前後で比べ、変わっていなかった。

**変異で見つけた危険と直したこと**: 最初の自己テストは「`--in-vm` はこの Mac では 96 で止まる」をこの Mac で実際に呼んで確かめていた。変異「`--in-vm` の VM の確かめを外す」の下では、この Mac で VM の片付け（xcodebuild・サンプル・**Mail** を止める、`~/ntk/runs` を消すなど）が走りうる形だった。1 回目のハーネスを流し始めてすぐに気づいて止めた（その変異は一覧の 60 番目あたりで、止めたときは 3〜4 番目までしか進んでいなかった。出力はまだ空で、この Mac では何も起きていない）。自己テストからこの Mac で `--in-vm` を呼ぶ形を消し、本文を読む確かめだけにし、ほかのシェルの呼び出しも道具の無い PATH で呼ぶ形にしてから、ハーネスを流し直した。

ここで試していない 7 章の行: テストの側の変異（0c で済み）、「根（動き）」と「おとりの通知」（6c を作っていない。8 章）、「監視」の押す枝（U-8。0c からの残り）、「押す前の確かめ」の合成の窓（0c で済み）、「setUp の失敗の立て直し」（VM の基準の 1 回目で、N21 が落ちた後に立て直して続く NC1〜NC3 が通った。意図した変異ではない）。

## 5. VM の基準

`scripts/test_mac.sh --where vm --baseline` を 3 回呼んだ（`mac/` はコミットと同じ状態にした。`mac/.gitignore` の変更は回の間だけ退けて戻した）。

| 回 | 結果 | 時間 |
|---|---|---|
| 1 | 単体テストの記録で止まった。`MacLibraryTests` に入れ子の suite（`ClipboardPasteLoaderTests/ItemProviderSourceTests/...`）があり、記録の形（2 段まで）から外れて `accept` が拒んだ（境界が働いた）。3 段まで許し、引数で展開された回数を `runs` として記録する形にした | - |
| 2 | **443/444**。`NotificationEventUITests/testN21_bodyClickInTheBackground` が `NTK-STEP:finder` で落ちた（Finder を前に出した直後にサンプルがまだ前面と読めた。Support の `OtherApps` の待ちの揺れで、0c の 3 回では起きていない。直していない）。基準は条件（失敗なし）で保存されなかった。通知の UI の立て直しは 4 回（決まった 3 回と N21 の後） | 33 分 |
| 3 | **444/444**。基準を保存した | 33 分（01:27〜02:00 UTC） |

基準 `scripts/test_mac.baseline.vm-15.8.3.json`:

| 項目 | 値 |
|---|---|
| 環境 | VM、macOS 15.8.3（24H241）、arm64、en-US、Xcode 26.3、ad-hoc。資格の 9 項目すべて合格、出どころ `cirrus-vanilla-15.7.7+15.8.3`、通知の UI の立て直し 3 回 |
| source | `HEAD` 623a919b、`mac/` の木のハッシュ（コミットと同じ）、宣言の表・ランナーの表のハッシュ（監査は VM では使わないので null） |
| eligible / executed | UI テスト 113 件（列挙 118 件から 26 だけの 5 件を除く）、すべて流した |
| excluded | M1b・M2・C9・S2・S4（`osOnly`） |
| 単体テスト | `MacLibraryTests` 308 件（展開の後 352 回）、`MacLibraryExampleTests` 20 件（21 回） |
| UI テスト | 共通 29（規則の自己テスト 24 を含む）、Dialog 17、Notification 30、Clipboard 22、Share 15。すべて passed |
| ランナーの確かめ | 押したボタンの照合（43 個）と fixture の照合（`.DS_Store` を除き 7 項目が同じ）、プレビューの設定を戻したこと、どれも passed |
| 時間 | UI テストの秒の和は 1749 秒（通知 968、Dialog 264、Clipboard 345、Share 141 など）。全体の 33 分は組み立て約 2 分と呼び出しごとの起動を含む |

0c の手の台本の 1 回（1821 秒、113 件）とほぼ同じ時間で、単体テストと照合を足して流せた。

## 6. この Mac の道（`--dry-run` まで）と、基準を取る回の案

`scripts/test_mac.sh --where mac --dry-run --allow notification,settings,badge,clipboard,sharepicker,panels,coldstart`（基準の条件の 7 区分）を 1 回呼んだ。この Mac で起動したのは読むだけの操作（`sw_vers`、`ps`、`lsregister -dump` を私的な一時フォルダーに書いて読みすぐ消す、`sysctl`）だけで、組み立ては VM の中。出力に、この Mac の名前・ユーザー名・ホームのパスは出なかった（確かめた）。この回で、列挙だけに使った VM の終わり方の不具合（fixture の照合を、fixture を作っていない回にも呼んだ）が出たので直した。

出力の要点:

- 流すテスト **99 件**（1 件ずつ 99 回の呼び出し。見張り N4 が先頭）、除くテスト 19 件: `vmOnly` 11（NP1〜NP3、S11・S12・S17、CB2〜CB6）、`ownerUnverified` 6（N20・N23・NC2・CB1・S2・S4）、`macDeferred` 2（N24・NC3）。M1b・M2・C9 は 26 なので流す側に入る
- 単体テスト: なし（監査の表にまだ別のモデルのレビューが無いため。`auditExpired`）
- 余分な登録のコピー: **11**（`derivedData` 2、`other` 9。印だけを出した）。`coldstart` を許すと、このままでは流す回が止まる
- 時間の見込み: 最初は基準が無く 1 件 60 秒の仮の値で 124 分と出た。見積もりの関数が基準の秒を読めない不具合を直し、VM の基準の秒で計算し直すと **約 51 分**（テストの秒の和 26 分、呼び出しごとの 12 秒、組み立て 5 分。26 だけの 3 件は 60 秒の仮の値）
- 許可の一覧（ID つき）を書いた。この回の一覧は、ランナーがコミットされていないので使えない（使うつもりも無く、書いたフォルダーは消した）

**この Mac の基準を取る回に、利用者へ示す案**（決まりの 4 つ）:

| 事柄 | 案 |
|---|---|
| 1. 流すテスト | 上の 99 件と 19 件の除外（その回の `--dry-run` の出力と許可の ID をそのまま示す）。監査のレビューを通していれば `MacLibraryTests` の 20 suite も |
| 2. この Mac に起きること | `--dry-run` の「what happens」: サンプルが何度も前面に出る、画面が収録される（私的な一時フォルダーの中で消す）、サンプルの通知が音つきで出る、Finder とシステム設定が前に出る、Dock のバッジ 1 と 0、一般の貼り付け板がテストの文字に書き換わり戻らない、共有のピッカーが開き Escape だけ押す、開く・保存のパネルが前に使ったフォルダーで開いてから `/private/tmp` の fixture に移る、サンプルが止められ通知から起こされる |
| 3. 準備 | ロック解除・スリープなし・給電、私物のウインドウを閉じるか別の Space へ、サンプルだけを通す集中モードと「画面の共有中も通知を許す」、サンプルの通知を許しておく、Handoff とユニバーサルクリップボードを切る、XCUITest のアクセシビリティなどの許可（U-31。最初は許し直しが要る見込み）、**余分な登録のコピー 11 個を利用者が外す**（`--allow-lsregister` はまだ無い）。始める前にこちらで済ませること: ランナーと `mac/.gitignore` のコミット、監査の表の別のモデルのレビュー、U-8 の監視が止めることの VM での確かめ（9.2 の最後の条件） |
| 4. 時間 | 約 50〜60 分（見込み。この Mac での呼び出しの起動の重さと 26 の通知の待ちは測っていない）。その間この Mac は使えない |

区切りの順は、U-30 の適格性の段（`mac26`、別の許可）を先にし、押す相手の持ち主が確かめられたら `MAC_VERIFIED_TARGETS` に写してから基準の回を取るのがよい（S2・S4・CB1・N20・N23・NC2 が基準に入る）。適格性の段の探りのテストはまだ書いていない（8 章）。

## 7. 設計書との差

設計書は直していない。親が反映を決める。

| # | 所 | 設計書 | 実際・したこと |
|---|---|---|---|
| 1 | U-24 | 共通のモジュールに純粋な関数を出す（条件つき） | 写して始めた（1 章）。0d の後に共通化を別の作業にする |
| 2 | 6.1 の import | Support は `AppKit` と `Darwin` も | `CoreGraphics` も許した（`NotificationRules.swift` が使う） |
| 3 | 6.1 の危ない名前 | Support の決まったファイルの中だけ | `DialogUITests.swift` の `alert.typeKey`（Support の `SampleAlert.typeKey`。押す前の確かめを通す口）を「ファイルと名前と回数」の例外として 1 回だけ許した。`supportRoot` を危ない名前に足した（0c 1.7 の 9） |
| 4 | 6.1 のテストのメソッドの形 | `test` で始まる関数はテストの形 | 信頼する部分では、値を返す `test` で始まる補助（基底の `testHost() throws -> TestHost`）を許した（XCTest はテストとして拾わない） |
| 5 | 6.1 の識別子の文字列 | 固定したファイルの `clipboard.` は例外 | 回数（10）で照らす形にした（0c 3.1） |
| 6 | U-11 の fixture の照合 | 中身が変わっていない | `.DS_Store` を除いて照らす（0c 1.7 の 3） |
| 7 | 6.3 step 0 のアカウント | 認証済みが許す種類のほかに無い、Mail の種類が無い | アカウントの種類を閉じた一覧（`HolidayCalendar`・`OnMyDevice`・`iTunesStore`）にし、ほかの種類は 1 つでもあれば不合格、認証済みは `HolidayCalendar` だけ。Mail の種類は自然に入らない（9.3 の「Mail のアカウントの確かな方法」はこれで代える案） |
| 8 | 6.3 step 0 の Xcode | `xcode-select -p` が 26.3 | `xcodebuild -version` の版とビルド（26.3、17C529）で見る |
| 9 | 6.3 VM の道の 3 | 柱 2 の⑤（`otool`）はこの Mac の道 | VM でも行う（読み方の確かめ） |
| 10 | 6.3 VM の道の 9 | `.xcresult` を VM に残し次の回の前に消す | 回の終わりに消す。調べるときは `--keep-vm-run`（設計書に無いオプション） |
| 11 | 6.3 の VM の道の 6c | おとりの通知 | 作っていない（8 章） |
| 12 | 6.3 の `--allow-lsregister` | 固定した集合を外す | 作っていない。渡すと止まる |
| 13 | 6.3 の `--qualification` | 適格性の段の計画 | 選び方の口だけ。探りのテストが無いので選ぶテストは 0 件 |
| 14 | U-20 の見張り | 落ちたら残りの UI テストを流さない | VM の道にも同じく当てた（VM では落ちたテストの後に立て直す決まりもあるが、見張りが落ちた回は止める方を取った） |
| 15 | クラスの下限 | クラスごとの集合 | `ShareUITests` に「`sharepicker` か `realservice` のどちらか」の形を足した |
| 16 | U-29 | 監査した suite を表に | 表に `review`（別のモデルのレビュー）を足し、空のあいだは失効と同じにした。監査の木は `MacLibrary`・`MacLibraryTests`・`project.pbxproj` |
| 17 | 6.3 の基準の `counts` | 展開の後の数 | 単体テストは Test Case ごとに 1 件の記録で、展開の回数は `runs` と基準の `expandedRuns` に記録した（引数の値は出さない） |
| 18 | 基準のファイル名 | `test_mac.baseline.<vm\|mac>-<OS の版>.json` | そのとおり。前の基準は `createdAt` の日付をつけた名前に移して残す |
| 19 | 3.4 の記録 | テスト・結果の種類・理由・数・時間 | `runs` と `invocation`（呼び出しの名前）を足した |
| 20 | `SupportRuleTests` | 設計書の外（0c 1.7 の 8） | 共通のクラスに入れ、どの `--feature` でも流す |
| 21 | 7 章「変異は VM だけで流す」 | VM だけ | レビュー v1 の前は、変異のハーネスと、本物のプロセスを起こして本物の停止の道を通す自己テスト 1 件を、この Mac で流していた（レビュー v1 Claude A-3）。v1 の後は VM の中だけ（10 章） |
| 22 | 6.4 の置き場の検査（iOS 8.7） | 持ち込む | 0d の最初の版では写し漏れていた（`-derivedDataPath` の無い呼び出しがあった。レビュー v1 Claude A-1）。v1 の後に `check-call` として写した |
| 23 | 6.3 のこの Mac の 4（書き手） | xcodebuild・サンプル・ランナーの 3 つ | 記録するのは xcodebuild だけで、サンプルとランナーは「今の回のフォルダーの下で印の後に起きたプロセス」で拾う。xcodebuild は実体が Xcode 26.6 になってから記録する |
| 24 | 3.3「組んだ一時のコピーの登録を外す」を許可の一覧に書く | 書く | 0d の最初の版は書いていなかった。v1 の後、`--dry-run` の「what happens」に書いた |
| 25 | 6.3「`--dry-run` は `NTK-STALE:alive` だけを出して止まり」 | 止まる | 一覧に書いて続け、許可の一覧に前の回のフォルダーと残ったプロセスの数を入れる。許可を得た回が止めて消す |
| 26 | 6.3 VM の 4「Finder 以外の前面のアプリを止める」 | 止める | サンプルと Mail だけを止める（VM では前面に出るアプリがほかに無い） |
| 27 | 6.3 VM の 0「VM の名前・ip・known_hosts の鍵も記録する」 | 記録する | UUID と起動の時刻を束ね、tart の引数を命令のたびに照らし直す。名前・ip・鍵は私的な一時フォルダーの外に書かない |
| 28 | 6.3 の単体テストの名指し | 監査した一覧 | VM でも `MacLibrary` のスキームを列挙し、単体の呼び出しごとに期待するテストの集合を計画に入れる（レビュー v1 Codex A-8） |
| 29 | 許可の有効な期間・前提の確かめ | （設計書に無い） | 許可は 12 時間で切れる。この Mac で流す前の VM での確かめ（U-8、収録の途中の KILL、26 の窓の持ち主）を `MAC_RUN_PREREQUISITES` に持ち、空の項目があれば許可を拒む（レビュー v1 Claude B-9・B-14） |

## 8. 残したこと

- **この Mac の道の `--approved` は一度も通していない**（この Mac で流さない約束のため）。確かめたのは純粋な関数、シェルの順の静的な確かめ、強制終了の後の本物のプロセスの 1 件、`--dry-run` まで。最初の区切りで許可を得て流すときに、組み立て（チームの署名）・`otool` の照合・単体テストの組み立て・1 件ずつの呼び出し・trap の片付けを初めて通す。そのときの不具合は止まる側に倒れるはずだが、確かめていない
- 設計書 6.3 の「VM で本物の XCUITest の収録の途中に親だけを `KILL` する」確かめ（9.1）はしていない
- 信頼する部分のハッシュ（Support の 15 ファイル）と固定したファイルのハッシュの固定は、別のモデルのレビューを通していない。ランナー自身（`mac_ui_runner.py`・`test_mac.sh`）のレビューもまだ
- U-29 の監査の表は別のモデルのレビュー待ち（それまでこの Mac では単体テストを選ばない）
- U-30: 探りのテスト `MacQualificationProbeTests`、`MAC_VERIFIED_TARGETS` への写し、`classify_reply_state` の余白の値（9.1 で VM の一覧の形を「一覧」と判定することの確かめ）
- 6c のおとりの通知（試作の通知の label が `NtkProbe0a, ` で始まり錨に当たらないので、試作を直す必要がある。0c 2.5 と同じ）
- `--allow-lsregister`（この Mac に余分な登録が 11 ある）
- N21 の揺れ（`NTK-STEP:finder`、2 回のうち 1 回）。Support の `OtherApps` の前面の待ちの形で、信頼する部分の変更になる
- `UnityMacPluginTests` の 1 回の実行（企画 0d の行、D-22）はこの作業の範囲の外として行っていない。VM の道に段を足すか、手で 1 回流す
- この Mac で流した単体テストは無い（区分 1 も含め。親が区切りで許可を得て流す）

## 9. 片付け

- VM: 実行のフォルダー（ソース・DerivedData・結果のバンドル・ログ）、fixture、プレビューの設定、今の実行の LaunchServices の登録、xcodebuild・サンプル・Mail のプロセスは、どれも残っていないことを確かめた。VM の空きは 8.6 GiB（始めと同じ）。VM のサンプルの通知は許可のまま（NP1 で終える）、category は登録したまま、`dndMirrored` は false のまま
- この Mac: 組み立ても DerivedData も作っていない。`lsregister` の dump の一時フォルダーと自己テストの一時フォルダーは消えている。許可の台帳（`test_mac-approvals.log`）は作られていない。公開の結果は `mac/MacLibraryExample/build/test_mac/`（git の外）に、VM の 4 回分（Dialog の 1 回、止まった 1 回、N21 の 1 回、基準の 1 回）を残した。`--dry-run` の許可の一覧のフォルダーは消した
- 背景の待ちと監視はすべて終わっている

## 10. ランナーのレビュー v1 の後（2026-11-23）

Claude（A 4、B 16、C 11）と Codex（A 10、B 6、C 1）の静的なレビューを受けて直した。指摘ごとの直し方は `reviews/2026-11-23-macos-c-abi-runner-review-v1.md`。要点:

- **VM の半分の入口**: `--in-vm` は最初の文で空の環境（`env -i`、`bash --noprofile --norc`）に起動し直し、`/usr/sbin/sysctl` の `kern.hv_vmm_present`、`hw.model`、`/usr/sbin/ioreg` の `IOPlatformUUID`（資格を確かめた VM のものを引数で渡す）の 3 つが合わなければ 96 で止まる。ssh の命令はどれも、この Mac で tart の引数を照らし直し、VM の中で UUID と起動の時刻を照らす。ssh は `-F /dev/null`
- **この Mac の xcodebuild**: gate の後に `check-call`（動作の語・`-derivedDataPath`・`-resultBundlePath`・`-workspace`・`-xctestrun` が 1 回ずつで私的な一時フォルダーの中、symlink なし、`-only-testing:` が計画とちょうど同じ）。外の設定（`XCODE_XCCONFIG_FILE`・`TOOLCHAINS`・`TEST_RUNNER_*`）を消し、Xcode 26.6 の xcodebuild を絶対パスで呼ぶ。組む入力は VM と同じ一覧の写しで、写しの木のハッシュが承認した木と同じでなければ止まる
- **私的な一時フォルダー**: VM の事実と `lsregister` の dump はリポジトリの外の `ntk-test-mac-private.*` に置き、1 つの EXIT の trap がどの終わり方でも消す。`ps` の全体はどこにも書かない
- **結果の欠け**: VM の呼び出しが結果を返さなければ、そこから後を失敗として止まる。要約は計画の全件がちょうど 1 件ずつ記録にあること、単体のターゲットとランナーの確かめ（fixture、押したボタン、プライバシーの戻し）の結果があることを求める。基準は `executed == eligible` と欠けが無いことを求める。単体テストは列挙した集合とちょうど同じことを求める（VM で `MacLibrary` のスキームも列挙する）
- **止める・消す**: 今の回も前の回も、3 つの一致で選んだ書き手に、その都度作り直した計画で TERM・KILL を送り、止まったことを確かめてから登録・fixture・フォルダーを外す。印が無い・壊れた・別のフォルダーを名指すフォルダーは消さない。`stale` は `--list` か `--stop` が必須
- **fixture**: 新しく作るだけ（あれば止まる）、`O_NOFOLLOW`、根の `lstat`
- **監査**: suite とファイルの宣言の対応、mock（`helpers`）の語、語の前置、`review` の形（`by`・`date`・同じ `treeHash`）、監査の木に scheme と workspace。表を作り直した（`review` は null のまま）
- **許可**: 12 時間で切れる。計画に OS のビルド・Xcode の版・`--baseline` を入れた。`MAC_RUN_PREREQUISITES`（U-8 の監視、収録の途中の KILL、26 の窓の持ち主）が空のあいだは許可を拒む（今は 3 つとも空なので、この Mac の `--approved` は通らない）
- そのほか: `NTK-PRECONDITION:`・`NTK-RUNNER:` の名前を閉じた一覧に、`main` が traceback を出さない、`typeKey` の例外を受け手で固定、基準の比べ合わせで単体の除外と、同じ種類の最新の基準を使う、基準の `source` にランナーのハッシュ（次の基準から）、`--allow-lsregister` は渡すと最初に止まる

### 10.1 この Mac の自己テスト

`python3 -m unittest scripts/tests/test_mac_ui_runner.py`: **138 件、すべて通った**。ランナーを読み込む前に、`os.kill`・`os.killpg` と、`git` と「PATH に害の無い 3 つの道具しかない `/bin/bash`」のほかのすべての subprocess を、テストを落とす偽物に差し替える（差し替えが効いていることも 1 件で確かめる）。止める処理は偽の `OsPort` で確かめる（待つ間の番号の再利用、止まらない書き手、印の無いフォルダー、消す順）。`--in-vm` は本文を読むだけで呼ばない。前の版の「`clang` で組んだ実行ファイルを起こして本物の停止の道を通す」1 件は消した。

iOS の自己テスト（`scripts/tests/test_ios_ui_runner.py`）も 1 回流し、通った（iOS のファイルは変えていない。このテストは道具を差し替えた `test_ios.sh` を自分の一時フォルダーの中で動かす）。

### 10.2 VM の中の自己テストと変異

ランナー・自己テスト・fixture・UI テストのフォルダー・サンプルのソース・pbxproj を VM の `~/ntk/selftest` に写し、VM の `/usr/bin/python3`（3.9）で流した。ハーネスは最初に VM であること（`kern.hv_vmm_present` と `hw.model`）を確かめ、ほかでは止まる。

- 自己テスト: 137 件が通り、1 件（リポジトリの木と監査の表のハッシュの照合）は写しが git のチェックアウトでないので skip
- 変異: **140 個**（レビュー v1 の指摘ごとの変異を足した）。1 回目は 136 個が捕まり、4 個が生き残った（空の名指しを両側で許す、gate がランナーのハッシュを見ない、gate が木のハッシュを見ない、VM の呼び出しが結果を返さなくても続ける）。どれも、その確かめだけを切り出す自己テストが無かった（git の状態の照合が先に捕まえていた、など）ので、その形の自己テストを足した。2 回目は変異なしの写しが落ちた（PATH を絞った引数の検査のテストで、VM の `/usr/bin/python3` が Xcode を探す shim だった。同じ時に `--dry-run` の組み立てが VM で動いていた）ので結果を使わず、実体のインタープリター（`sys.executable`）を置く形に直した。**3 回目は 140 個すべて捕まり、変異なしの写しは通った**
- 片付け: VM の `~/ntk/selftest`、ハーネスと自己テストの一時フォルダー、途中で止めた 2 回目のハーネスのプロセスを消した

### 10.3 VM の 1 回（判定を変えたので）

- `--where vm --feature Dialog`: 1 回目は資格の `identity` で止まった（VM の起動の時刻を `sed` の欲張りな形で読み、`usec` の値を拾った。形の照合で止まる側に倒れた）。`^\{ sec = ` に固定して直し（自己テストで本文を照らす）、2 回目は 47/47、基準と差なし
- `--where vm`（全件。`--baseline` なし）: **444/444**（UI 113、`MacLibraryTests` 308、`MacLibraryExampleTests` 20、ランナーの確かめ 3）、33 分（02:50〜03:23 UTC）。基準 `test_mac.baseline.vm-15.8.3.json` と比べて changed・added・removed・除外の差がどれも 0。単体テストは列挙した集合とちょうど同じだった。通知の UI の立て直し 3 回。VM の実行のフォルダーと、この Mac の私的な一時フォルダーは消えていた
- 基準は取り直していない（判定は変えたが結果は同じだった）

### 10.4 この Mac の `--dry-run`（7 区分）

流すテスト 99 件・除くテスト 19 件・単体テストなし（監査が未レビュー）は前と同じ。「what happens」に収録の扱いの正しい文と登録を外すことの 1 行、`--allow-lsregister` が未実装であること、「NOT READY」（`MAC_RUN_PREREQUISITES` の 3 項目が空なので、この一覧の許可は拒まれる）が出た。時間の見込みは約 51 分。出力にこの Mac の名前・ユーザー名・ホームのパスは出なかった。私的な一時フォルダーは消え、許可の一覧のフォルダーは使わないので消した

## 11. ランナーのレビュー v2 の後（2026-11-23）

Claude（A 0、B 3、C 10）と Codex（A 3、B 6、C 1）の静的なレビューを受けて直した。指摘ごとの直し方は `reviews/2026-11-23-macos-c-abi-runner-review-v2.md`。要点:

- **VM の半分の入口**（Codex A-1）: `NTK_IN_VM_CLEAN` を消した。`--in-vm` は 3 つの事実を照らした後、いつも空の環境の特権の bash（`-p`）で `--in-vm-clean` として起動し直す。起動し直した側は 3 つの事実をもう一度照らし、特権の印・関数が無いこと・決まった PATH と変数だけであることを確かめる
- **signal の道**（Codex A-2、Claude B-1・C-1）: perl は自分の子の leader を刈り取る前だけ group に送る。この Mac では perl そのものを背景に置き、印に書けなかったときの TERM が perl に届く。Python は個々の送信の直前ごとに計画を作り直す。leader が終わった後の group は、道具とこの回のビルドだけのときに止める
- **片付けの許可**（Codex A-3）: 前の回の片付けを、フォルダー・印・プロセスの中身で許可に結び、`stale --stop` に gate と許可の照らしを入れた。今の回のフォルダーは、消費した許可の ID を書いた印と一緒に作り、`stop-current` はその許可が消費済みのときだけ片付ける
- **残骸**（Claude B-3）: 私的なフォルダーに持ち主を書き、次の回が持ち主の居ないものを消す。`NTK-STALE:refused` に探し方を出す
- **単体テスト**（Codex B-1）: 宛先・要約・展開の子の結果・未知のバンドル・列挙の disabled を照らし、要約で計画の集合とちょうど同じことを求める
- **tart と ssh の相手**（Codex B-2）: tart の VM の設定の MAC アドレスと VM の `en0` が同じことを資格の 10 項目めにした
- **前提の表**（Codex B-3、Claude C-5）: おとりの通知を足して 4 項目。値は `artifact/` の下の実在する記録の道のときだけ数える
- **自己テスト**（Claude B-2、Codex B-4）: 偽の口は `--in-vm` を持つ bash を、前置きだけを切り出した写しにしか通さない。入口の振る舞いはその写し（事実の読み手を偽物にしたもの）で確かめる。`approve` のつなぎ（失敗では消費しない、成功で 1 回だけ）を確かめる
- **基準の形**（Codex B-5）: `executed` を `eligible` と同じ `<クラス>/<メソッド>` にし、記録済みの VM の基準の `executed` も同じ形に直した（113 件、中身は同じ）
- **出す文**（Codex B-6、Claude C-9）: 絶対パスを `<path>` に置き換えてから出す
- そのほか（Claude C-2〜C-4・C-7・C-10）: この Mac の xcodebuild を `env -i` で、組む・流すの呼び出しのオプションと値を表で、宛先の機種と arch を照らす、ハーネスの docstring、`--expect-under` の実体のパス

### 11.1 確かめ

| 何を | どこで | 結果 |
|---|---|---|
| 自己テスト（偽の口。`--in-vm` は前置きだけを切り出した写しで、事実の読み手を偽物にして確かめる） | この Mac | 154 件、すべて通った |
| 同じ自己テスト | VM | 153 件が通り、1 件 skip（写しが git のチェックアウトでない） |
| 変異 168 個（v2 の指摘ごとの変異を足した） | VM だけ | 1 回目は 166 個が捕まり 3 個が生き残った（`-skip-testing` の個別の確かめは、許すオプションの表でも拒むので同じ形になり、個別の分岐と変異を外した。`in_vm_main` の 2 つめの UUID の確かめと、同じフォルダーで印だけ変わった場合は、それを切り出す自己テストを足した）。直した後の通しで **168 個すべて捕まり**、変異なしの写しは通った |
| `--where vm`（全件） | VM | 443/444。資格の 10 項目（`tartIsThePeer` を足した）はすべて合格し、VM の中の段はすべて新しい前置きを通った。単体テストは新しい照合（宛先・要約・展開・集合）を通った。落ちたのは N21（`NTK-STEP:finder`）だけで、基準との差もこの 1 件だけ。N21 は全件の 5 回のうち 2 回落ちた（Support の待ちの揺れ。0c から変えていない） |
| `--where vm --feature Notification` | VM | 60/60（共通 29 と Notification 30 と fixture の照合）。N21 を含め、基準との差は 0 |
| `--where mac --dry-run`（7 区分） | この Mac（読むだけ）と VM | 99 件・除外 19 件。「NOT READY」に前提の 4 項目。私物のパスは出ず、私的な一時フォルダーは残らなかった。許可の一覧のフォルダーは使わないので消した |

この Mac では、変異のハーネス、本物の kill・rm・pkill・killall・defaults・lsregister・ssh に届く自己テスト、`--in-vm` を流していない。

## 12. ランナーのレビュー v3 の後（2026-11-23）

Claude（A 0、B 1、C 8）と Codex（A 5、B 6、C 2）の静的なレビューを受けて直した。指摘ごとの直し方は `reviews/2026-11-23-macos-c-abi-runner-review-v3.md`。照らせない道では止めない側に倒した。要点:

- **印に書けなかったときの止め方**（Codex A-1、Claude C-1〜C-3）: 背景の perl に送るのは `stop_waiter` だけで、送る直前に、その番号がこのシェルの子の perl であること（`own-child`）を照らす。照らせなければ何も送らずに知らせる。trap の片付けも先に通す。perl は group に送る前ごとに `waitpid` の WNOHANG で leader が刈り取る前の自分の子かを聞き直す
- **leader の居ない group**（Codex A-2）: 採用しない。3 つの一致の writer と、フォルダーの下で印の後に起きたものにだけ送り、残りは数えて、送らずにフォルダーを残して知らせる
- **展開したテストの数**（Codex A-3）: 基準にテストごとの展開後の回数（`runs`）と、`counts` に宣言の数と展開後の数の両方を入れた。減れば `RUNS` の差と lost になる
- **VM の木**（Codex A-4）: VM の写しの木のハッシュを、組む前に計画の `macTree` と照らす。基準の保存の直前にも木と `HEAD` を照らす
- **出す文**（Codex A-5）: 一部を削るのをやめ、場所を含む文は丸ごと決まった符号（`NTK-RUNNER:withheld`）にする
- **片付けの許可**（Codex B-1・B-5、Claude C-4）: 承認した印の digest と writers を止める口まで渡し、外のものがあれば送らずに止まる。承認した回は許可にある残骸の一覧で計画を作る
- **宛先**（Codex B-2）: `platform`・`architecture`・`deviceId` が欠ければ通さない。要約の機器とも照らす
- **回のフォルダー**（Codex B-3）: 別の名前の頭の一時フォルダーで印・写し・`tmp/` をそろえてから rename 1 回で作る。止まった回の staging は次の回が消す
- **この Mac の `TMPDIR`**（Claude B-1）: xcodebuild の `TMPDIR` を回のフォルダーの `tmp/` にした。xcodebuild の前と最後に `$TMPDIR` の名前の一覧を比べ、増えた数を出す（名前だけ）
- **自己テスト**（Codex B-4、Claude C-6）: 事実の読み手を呼ばれた回数で値を変える偽物にし、起動し直した後だけ違う 3 例を足した。偽の口は、破壊的な命令の語を持つ写しを通さない
- **記述**（Codex C-1・C-2、Claude C-5）: `--dry-run` も始めに、前の回が残したランナー自身の私的な一時フォルダーを消すことを「what happens」と README に書いた（10.4・11.1 の「読むだけ」は、このことを除いての意味）

### 12.1 確かめ

| 何を | どこで | 結果 |
|---|---|---|
| 自己テスト（偽の口） | この Mac | 166 件、すべて通った |
| 同じ自己テスト | VM | 165 件が通り、1 件 skip（写しが git のチェックアウトでない） |
| 変異 193 個（ほかに変異なしの基準の 1 項目。v3 の指摘ごとの変異を足し、変わった文の 9 個を新しい形に合わせた） | VM だけ | 1 回目で **193 個すべて捕まり**、変異なしの写しは通った。本物の台帳は変わらなかった |
| `--where vm --baseline`（全件。判定を変えたので） | VM | **444/444**（N21 も通った）。資格の 10 項目はすべて合格し、VM の写しの木は計画の `macTree` と一致した。古い基準とは `expandedRuns` の合計で比べ、`changed=0, added=0, removed=0, excluded changed=0, fewer runs=0`。新しい基準を保存した（`runs` にテストごとの展開後の回数 328 件・計 373 回、`counts` に宣言の数と展開後の数の両方（MacLibraryTests は passed 308・runs 352、MacLibraryExampleTests は passed 20・runs 21）、`source.runnerFiles` が入った。`eligible` と `executed` は 113 件で一致）。前の基準はランナーの決まりどおり `test_mac.baseline.vm-15.8.3.2026-11-23.json` に移されたが、中身がコミット済みのもの（`d89f9d46`）と同じで git の履歴にあるので消した。基準の `source.head` は `d89f9d46` だが、`source.runnerFiles` は保存したときのコミットしていないランナー（後の `1473c7ca` のもの）のハッシュである（`mac/` はその間に変わっていない。レビュー v4 の Claude C-2）。次からはランナーをコミットしてから基準を取る |
| 片付け | VM とこの Mac | VM の `~/ntk/runs` は空、自己テストの写しは消した。この Mac の一時フォルダーに `ntk-` で始まるものは残っていない |

この Mac では、変異のハーネス、本物の kill・rm・pkill・killall・defaults・lsregister・ssh に届く自己テスト、`--in-vm` を流していない。

## 13. ランナーのレビュー v4 の後（2026-11-23）

Claude（A 0、B 0、C 6）と Codex（A 3、B 3、C 1）の静的なレビューを受けて直した。指摘ごとの直し方は `reviews/2026-11-23-macos-c-abi-runner-review-v4.md`。要点:

- **許可のファイルの読み取り**（Codex A-1）: シェルの `python3 -c` をやめ、ランナーの `approval-stale` で読む。読めないときは決まった文だけを出す（場所も traceback も出さない）。オプションを読んだ直後に、ファイルがあって読めることも確かめる（文に場所を入れない）
- **止めたことを示せない回**（Codex A-2、Claude C-5）: perl は signal の処理を fork の前に置き、PID のファイルも fork の前に開く（開けなければ何も起こさない。書けなければ子を止めてから終わる）。xcodebuild を起こす前に印に「起こしている」を書き、記録したら消す。この印が残るフォルダーは、その起動のあいだは消さない（再起動の後に消える）。印に書けなかった回と、`own-child` が照らせなかった回は、シェルも `stop-current` に進まずフォルダーを残して知らせる
- **VM のランナーの写し**（Codex A-3）: ランナーの 3 ファイルを私的なフォルダーに一度写し（snapshot）、そのハッシュを計画の `runnerFiles` にし、VM にはその写しから渡す。VM の中の 2 つのスクリプトのハッシュを組む前に照らす。基準の `runnerFiles` は計画の値で、保存の時にリポジトリのランナーが違えば保存しない。この Mac の道は、計画を作るときに写しとリポジトリのランナーが同じことを照らす
- **`own-child`**（Codex B-1、Claude C-6）: 実行ファイルの実体のパスが `/usr/bin/perl` か `/usr/bin/perl5.<n>` と完全に一致するときだけ（VM で、背景の perl の実体のパスが `/usr/bin/perl` であることを確かめた）
- **展開の回数の増え**（Codex B-2）: 増えても `RUNS` に出し、見出しに `more runs=` を足した（lost にはしない）
- **本物の振る舞い**（Codex B-3）: VM の中だけで動く自己テスト（`RealProcessesInTheVM`。この Mac では事実を読んで skip）で、PID のファイルを作れないと子が起きないこと、TERM で leader が自分の子の間に group が止まること、leader が終わった後は残りに何も送らないこと、`own-child` が動いている perl だけを認め、bash が刈り取った後は認めないことを、テスト自身の子のプロセスで確かめる
- **記述**（Codex C-1、Claude C-1〜C-4）: leader の居ない group の説明、12.1 の前の基準の扱い、`head` と `runnerFiles` のずれ、fixture の文から道を外した、残った group の数と種類を出し、止まり続けるときの手順（再起動か、利用者が見る）を `STALE_HINT` に足した

### 13.1 確かめ

| 何を | どこで | 結果 |
|---|---|---|
| 自己テスト（偽の口。本物のプロセスの 4 件は skip） | この Mac | 181 件、177 件が通り 4 件 skip |
| 同じ自己テスト（本物のプロセスの 4 件も） | VM | 181 件、180 件が通り 1 件 skip（写しが git のチェックアウトでない） |
| 変異 210 個（ほかに変異なしの基準の 1 項目。v4 の指摘ごとの変異を足し、変わった文の 5 個を新しい形に合わせた） | VM だけ | 1 回目は 207 個が捕まり 3 個が生き残った（記録したら `launching` を消すこと、VM のランナーの写しの照合の行、基準の `runnerFiles` が計画の値であること。どれも切り出す自己テストが無かったので、`record_writer` と `make_baseline` の形にして自己テストを足し、シェルの照合の行の形も確かめた）。直した後の通しで **210 個すべて捕まり**、変異なしの写しは通った。本物の台帳は変わらなかった |
| `--where vm`（全件。判定を変えたので。ランナーがコミットされていないので基準は取らない） | VM | **444/444**。資格の 10 項目、VM の写しの木、VM のランナーの写しの照合（新しい段）を通った。基準（v3 で取ったもの。テストごとの展開の回数入り）との差は `changed=0, added=0, removed=0, excluded changed=0, fewer runs=0, more runs=0` |
| `--where mac --dry-run`（区分なし） | この Mac（読むだけ。ランナー自身の残りを消すことを除く）と VM | 計画を作るときのランナーの写しとリポジトリの照合を通った。「what happens」に TMPDIR と残りの片付けの行が出た。「NOT READY」に前提の 4 項目。私物のパスは出なかった。許可の一覧のフォルダーは使わないので消した |
| 片付け | VM とこの Mac | VM の `~/ntk/runs` は空、自己テストの写しは消し、テストの sleep も残っていない。この Mac の一時フォルダーに `ntk-` で始まるものは残っていない |

この Mac では、変異のハーネス、本物の kill・rm・pkill・killall・defaults・lsregister・ssh に届く自己テスト、`--in-vm` を流していない。

## 14. ランナーのレビュー v5 の後（2026-11-23）

Claude（A 0、B 1、C 4）と Codex（A 3、B 1、C 1）の静的なレビューを受け、親の決めた方針で、この Mac での止め方を変えた。指摘ごとの直し方は `reviews/2026-11-23-macos-c-abi-runner-review-v5.md`。要点:

- **この Mac で signal を送るのは、xcodebuild を見張る perl だけ**。送る相手は、まだ刈り取っていない自分の子が leader の group だけ。シェルは止めのファイルを作って `wait` するだけで、Python の片付けには送る口が無い。`own-child` と 3 つの一致による送りは消した（Codex A-3）
- **前の回の残骸は止めない**。`NTK-STALE:alive`（種類ごとの数）か `NTK-STALE:refused` で知らせ、その回のものが何も動いていないと示せたフォルダーだけを消す。残れば許可を得た回は組む前に止まる。`--dry-run` も一覧に `STALE` の行を出す
- **動いているかの見方**（Codex A-1・A-2、Claude C-3）: 記録した writer は PID と開始時刻で、その回の group はすべて（`groups`）、フォルダーの下の実行ファイル、この利用者の印の後の読めないプロセスを数える。一覧が読めなければ残す。`launching` の印は、PID のファイルの番号で追う
- **次の xcodebuild の前に `settle`**（Codex A-2）: その回の group に何も残っていないことを確かめてから次を起こす
- **perl**（Claude C-1）: fork の前後で signal を止め、時間切れ・止めのファイル・親のシェルが居なくなったとき・HUP/INT/TERM で group を止める。`alarm` はやめて 0.2 秒ごとに見る
- **スクリプトの終わり**（Claude B-1）: この Mac の上の文を `main()` に入れ、最後の 2 行（VM の半分の入口と `main "$@"; exit $?`）がそれぞれ 1 行で終わる形にした
- **そのほか**: VM の写しのハッシュは `shasum` で（Claude C-2）、変異の数え方（Claude C-4。12.1・13.1 を直した）、自己テストの冒頭と README（Codex C-1）、`agent-rules/device-testing.md` の macOS の節に 1 文

### 14.1 確かめ

| 何を | どこで | 結果 |
|---|---|---|
| 自己テスト（偽の口。本物のプロセスの 6 件は skip） | この Mac | 182 件、176 件が通り 6 件 skip |
| 同じ自己テスト（本物のプロセスの 6 件も。時間切れ・止めのファイル・TERM・親のシェルが居なくなったとき・刈り取った後に送らないこと・PID のファイルを作れないとき） | VM | 182 件、181 件が通り 1 件 skip（写しが git のチェックアウトでない） |
| 変異 209 個（ほかに変異なしの基準 1 項目。signal と 3 つの一致の変異 24 個を外し、v5 の変異を足した） | VM だけ | 1 回目は 203 個が捕まり 6 個が生き残った（`launching` の印を書くこと・消すこと、一覧の失敗、group の一覧だけの印、残った残骸で止まること、VM の写しのハッシュをランナーで計算すること。どれもその形の自己テストが無かったので足し、`clean_stale` を切り出した）。6 個と基準を流し直してすべて捕まり、その後の通しで **209 個すべて捕まり**、変異なしの写しは通った |
| `--where vm`（全件。VM の xcodebuild も同じ perl で見張るので） | VM | **444/444**。VM の写しのハッシュ（`shasum`）の照合を通った。基準との差は `changed=0, added=0, removed=0, excluded changed=0, fewer runs=0, more runs=0`。ランナーがコミットされていないので基準は取らない |
| `--where mac --dry-run` | この Mac（読むだけ。ランナー自身の残りを消すことを除く）と VM | `main()` の形で動き、前の回の残骸は無く `STALE` の行は出なかった。「NOT READY」に前提の 4 項目。私物のパスは出なかった。許可の一覧のフォルダーは消した |
| 片付け | VM とこの Mac | VM の `~/ntk/runs` は空、自己テストの写しは消し、テストの sleep も残っていない。この Mac の一時フォルダーに `ntk-` で始まるものは残っていない |

この Mac では、変異のハーネス、本物の kill・rm・pkill・killall・defaults・lsregister・ssh に届く自己テスト、`--in-vm` を流していない。

## 15. ランナーのレビュー v6 の後（2026-11-23。レビューはこれで閉じる）

Claude（A 1（致命的でない）、B 1、C 2）と Codex（A 0、B 2、C 2）の静的なレビューを受けて直した。致命的な A が 0 なので、利用者の 11-23 の指示によりランナーのレビューは v6 で閉じる（v7 は無い）。指摘ごとの直し方は `reviews/2026-11-23-macos-c-abi-runner-review-v6.md`。要点:

- **プロセスの表**（Claude A-1）: `ps` をやめて `libproc` から読む。読めない実行ファイルはもう一度見て、まだ居るものだけを数える
- **`settle`**（Claude B-1、Codex B-2）: 一覧・時計・sleep を渡す形に切り出して戻り値で確かめ、VM の道でも各 xcodebuild の後に同じ判定を知らせるだけ走らせる（`NTK-VM settle`）。空と確かめた group は閉じる（Claude C-1）
- **表示と記述**（Claude C-2、Codex C-1・C-2）: `STALE_HINT` の種類ごとの探し方、`--dry-run` と終わりの表示、コメントと設計書を今の方針に合わせた

### 15.1 確かめ

| 何を | どこで | 結果 |
|---|---|---|
| 自己テスト（偽の口。プロセスの表も偽物。本物のプロセスと本物の表の 8 件は skip） | この Mac | 189 件、181 件が通り 8 件 skip（単体の監査の直しの分を含む） |
| 同じ自己テスト（本物のプロセスの 6 件と、本物の表で片付けを判定する 2 件も） | VM | 189 件、188 件が通り 1 件 skip（写しが git のチェックアウトでない）。印だけの回のフォルダーは「消せる」と判定され、leader が終わって helper が残ると `settle` が失敗して後続が起きずフォルダーが残り、helper を終わらせた後は `settle` が通って group が閉じた |
| 変異 226 個（ほかに変異なしの基準 1 項目。v6 の 11 個と単体の監査の 6 個を足し、ps の 1 個と監査の 1 個を新しい形に合わせた） | VM だけ | v6 までの 220 個の通しで 219 個が捕まり、1 個（VM が残りを書き留めない）が生き残った。シェルの行の形の自己テストを強めて流し直し、捕まった。単体の監査の 6 個と、形を合わせた監査の 2 個も流してすべて捕まった。変異なしの写しは通った（監査の直しはランナーの別の判定に触れないので、通しの流し直しはしていない） |
| `--where vm`（全件。判定を変えたので）を 2 回と `--feature Notification` を 1 回 | VM | 3 回とも、ランナーの段（資格・写しの照合・組み立て・列挙・単体）はすべて通り、`NTK-VM settle calls=45 left-after-15s=0 most=0`（Notification は calls=37）で、どの xcodebuild の後も group は残らなかった。結果は 443/444・59/60・443/444 で、**基準との差は毎回 1 件、しかも毎回違う通知の UI テスト**（N14b `NTK-STEP:secondsWindow`、N23 `NTK-STEP:notificationRoot`、N24 `NTK-STEP:finder`）。v3〜v5 の全件 3 回は差 0 だった。v6 で VM の道に足したのは各 xcodebuild の後の `settle-report`（VM で 0.12 秒）だけで、テストの中の時間の測り方に触れないので、ランナーの直しが原因とは見ていないが、原因は突き止めていない（VM は 23 時間動き続けている）。基準は取り直していない |
| `--where mac --dry-run` | この Mac（読むだけ。ランナー自身の残りを消すことを除く）と VM | 本物の列挙で、単体の監査の表との突き合わせに漏れは無く、`[audit]` は review が無いことだけを出した。「NOT READY」に前提の 4 項目。私物のパスは出なかった。許可の一覧のフォルダーは消した |
| 片付け | VM とこの Mac | VM の `~/ntk/runs` は空、自己テストの写しは消し、テストの sleep も残っていない。この Mac の一時フォルダーに `ntk-` で始まるものは残っていない |

この Mac では、変異のハーネス、本物の kill・rm・pkill・killall・defaults・lsregister・ssh に届く自己テスト、本物のプロセスの表を読む自己テスト、`--in-vm` を流していない。

### 15.2 単体テストの監査（U-29）の Codex のレビュー v1 と直し

Codex のレビュー（A 0、B 4、C 2）の直しと、treeHash を shell で別に計算して一致したことは `reviews/2026-11-23-macos-c-abi-unit-audit-review-v1.md`。要点: 入れ子の suite を完全名で表に足し、列挙と表を突き合わせる照合を入れた（B-1）。plugin の Clipboard を監査のハッシュに入れた（B-2）。`review` を表の digest・記録・モデルに結び、監査者と同じモデルでは通さない（B-3）。新しい treeHash は `50c3fda0…9259` で、ランナーの関数と shell の計算が一致した（B-4）。理由の文を 2 つ直した（C-1・C-2）。`review` はまだ null（直した表を Codex に短く確かめてもらってから埋める）。

## 16. 通知の UI テストの揺れの調べ（2026-11-24。2 時間で止めた。原因は突き止めていない）

| 回 | 条件 | 結果 |
|---|---|---|
| n1 | `--feature Notification`、settle の判定あり、VM は 23 時間動き続けた後 | 59/60。N24 `NTK-STEP:finder` |
| a1・a2 | settle の判定を一時的に外した（調べの間だけ。元に戻した） | 60/60、60/60 |
| n2 | settle の判定あり（待った時間と、残ったものの名前も書くようにした） | 60/60。37 回の判定はどれも 0.0〜0.1 秒で、group は最初から空 |
| r1 | VM のゲストを再起動した後、settle の判定あり | 59/60。N23 `NTK-STEP:finder` |

- settle の判定（v6 で足した VM の道の `settle-report`）は、待ちが毎回 0.0〜0.1 秒で何にも触れないので、原因ではないと見る（外した 2 回が通ったのは偶然の範囲）。libproc は VM の道ではこの判定でしか使わないので、(b) も同じ。VM のゲストの再起動でも落ちたので、(c) の長く動いたことの溜まりでもない
- 中を読めた 2 件（n1 の N24、r1 の N23）は同じ型だった: `OtherApps.swift:67`、`FinderFront.bringToFront` の 20 秒の待ちの終わりに「Finder did not come to the front with the sample behind (front com.apple.finder, sample 4)」。Finder は前面にいるのに、`XCUIApplication` のサンプルの `state` が `runningForeground`（4）のまま変わらない。0c の頃から続く N21 の揺れと同じ `NTK-STEP:finder` で、v6 の全件の N24 もこれ。残る 2 件（N14b `secondsWindow`、v6 の Notification の回の N23 `notificationRoot`）は別の型で、結果のバンドルを残していなかったので中は読めていない
- 0c の揺れ（NP1 の `notNotDetermined`、許可の戻し方）とは別の型
- 直すならテストの側（`FinderFront` が前面を `XCUIApplication.state` でなく前面のアプリの PID と、サンプルの窓が前面でないことで見る、など）。信頼する部分（Support）の変更でハッシュの固定の取り直しと別のモデルのレビューが要るので、この回では変えていない。基準も取り直していない
- 調べのために `settle-report` の記録に、待った秒数と、最初に見た group の実行ファイルの名前（VM の中のファイルだけ）を足し、`finish` の要約に `longest-wait` を足した（コミットしていない）

## 17. `FinderFront` の前面の確かめを直した（2026-11-24。コミットしていない）

- **変えたテスト**（DoD「変えたテストは理由を記録」）: `MacLibraryExampleUITests/Support/OtherApps.swift` の `FinderFront.bringToFront`（55〜81 行）。理由: 16 章で読めた 2 件（N23・N24）は、Finder が前面にいるのにサンプルの `XCUIApplication.state` が 20 秒の間ずっと `runningForeground`（4）のままで落ちていた。前面の確かめに `XCUIApplication.state` を使うのをやめた
- **選んだ形**: ウインドウサーバーの切り替えを見る。`NSWorkspace.shared.frontmostApplication` の PID が Finder のもので、サンプル（`NSRunningApplication.runningApplications(withBundleIdentifier:)` で毎回取り直す）が動いていて、どれも `isActive` でなく前面の PID でもないときに通す。待ちは `Thread.sleep` でなく `RunLoop.current.run(until:)` にして、workspace の見る前面が古いままにならないようにした。理由: 続く押下（通知のバナーを押してサンプルが前に来るか）が前提にするのは、XCTest の状態の写しではなくウインドウサーバーの前面と、サンプルが active でないことだから。窓が key でないことを accessibility で見る案は、サンプルの窓を読む口が増えて、押す前の確かめ（5.0）の範囲が広がるので採らなかった。落ちたときの文に、サンプルの active・inactive と、比べのために XCUITest の state も入れた
- **0c の N21 の揺れ**: 同じ `FinderFront.bringToFront` を通る（N21・N23・N24、`NotificationUITests` の 1 か所）ので、この直しで同じに扱う
- **VM の落ちた結果のバンドル**: VM の回で落ちた UI テストの結果のバンドルとログを `~/ntk/failed/<run id>/` に写して残し、`finish` がその数を `NTK-VM kept … failed result bundle(s)` で知らせる。回は消さない。書き写した後に手で消す（中に VM の画面のスクリーンショットがある）
- **信頼する部分のハッシュ**: 固定は取り直していない（Codex のレビューの後に親が頼む）。そのため自己テストの `SourceRules` の 2 件（`test_the_real_folder_passes`、`test_breaking_the_trusted_part`）は、固定を取り直すまで落ちる。VM の回は `Warning: the trusted part changed: Support/OtherApps.swift` を出すだけで止まらないので、一時的な扱いは要らなかった

### 17.1 確かめ

| 回 | 結果 |
|---|---|
| `--where vm --feature Notification` 1 回目 | 60/60 |
| 2 回目 | 60/60 |
| 3 回目 | 60/60 |

3 回とも落ちたものは無く、N14b `secondsWindow` と N23 `notificationRoot` の別の型も出なかった（出たら `~/ntk/failed` で読む）。VM の `~/ntk/runs` と `~/ntk/failed` は空。この Mac の自己テストは 190 件のうち上の 2 件が落ち、180 件が通り、8 件が skip。

### 17.2 Codex のレビュー v1（`FinderFront`。A 0、B 1、C 2）の後

- **B-1**（変えたテスト）: 通知を押す前の「サンプルが背景」の確かめも、同じ AppKit の見方にそろえた。`Support/NotificationCenterUI.swift` に `SampleStateAtPress.sampleIsBehind()`（98 行。main の run loop を一度回してから、サンプルが動いていて、どれも active でなく前面の PID でもない）を足し、`checkBeforePress`（452 行〜）は `.background` のときだけこれで照らす（`.foreground`・`.notRunning` は XCUITest の state のまま）。N24 の後条件（`NotificationEventUITests.swift` 149 行）も `sampleIsBehind()` にした。窓の持ち主・通知の根・入力の焦点の検査は変えていない。理由: Finder の待ちを抜けても、押す前の確かめが同じ食い違い（XCUITest の state が 4 のまま）で `notificationState` に移って落ちうるため
- **C-1**: `FinderFront.bringToFront` を `@MainActor` にし、最初に見る前にも run loop を 0.05 秒回す。コメントは「見る前ごとに run loop を回して AppKit に更新の機会を与える。見たものはその瞬間のもので、押す直前の確かめが境界」と、実装どおりにした
- **C-2**: 自己テストで、`finish` が残した数を知らせる行と、`vm_finish` の消すものが `"${FX}"` と `"${RUN_DIR}"` だけであること（残したバンドルを消さない）を確かめる
- **N14b の `secondsWindow`**（変えたテスト）: 1 回目の 3 回の 3 回目で出たので、`~/ntk/failed` に残したバンドルを読んだ。`NotificationScreen.swift:142`「the clock is not in the window after waiting」。手順の時刻では、待ちに入ったのが 29 秒台で、約 33.6 秒後の 35 分 04.998 秒に「窓の外」と判定していた。待ちは窓の始まり（5.000 秒）ちょうどを狙っており、sleep が数える時計（単調）と壁の時計のずれで 2 ms 手前に起きた。`Support/NotificationRules.swift` の `SecondsWindow` に `aimInside = 0.5` を足し、待ちは窓の始まりから 0.5 秒中を狙う（171〜181 行。最長の待ちは 36.5 秒で、期限 40 秒の内）。`SupportRuleTests.swift`（347 行〜）の期待値を直し、壁の時計が 10 ms 遅れても窓の中に着くことを足した。読んだバンドルは消した
- N23 の `notificationRoot` は、この間に出なかったので、まだ読めていない（出たら `~/ntk/failed` で読む）
- ハッシュの固定はまだ取り直していない（`SourceRules` の 2 件は取り直すまで落ちる。VM の回は警告だけで止まらない）

| 回 | 直し | 結果 |
|---|---|---|
| 1〜3 回目 | B-1・C-1・C-2 | 60/60、60/60、59/60（N14b `secondsWindow`） |
| 4〜6 回目 | ＋ `SecondsWindow.aimInside` | 60/60、60/60、60/60 |

### 17.3 Codex の確かめ v2（A 1）の後

- **A-1**（変えたテスト）: 押す前を AppKit で見るようにしたので、押した後の「前面に来た」が XCUITest の古い `runningForeground` で通りうる。`Support/NotificationCenterUI.swift` に、`sampleIsBehind` の逆の `sampleIsInFront`（110 行。main の run loop を回してから、サンプルがちょうど 1 つのプロセスで、active で、`frontmostApplication` の PID であること）と、それを待つ `waitForSampleInFront`（122 行。`@MainActor`。待つ間も run loop を回す。前面に出す操作はしない）を足し、N21（`NotificationEventUITests.swift` 107 行）と N23（135 行）の押した後に、XCUITest の待ちに続けて呼ぶ。`sample.activate()` はその前に呼ばない
- 押す前に XCUITest と AppKit が食い違ったら、`noteDisagreement`（134 行。`checkBeforePress` の 494 行から）が、テストの手順に `NTK-NOTE sample state: XCUITest <n>, AppKit behind|not behind at before <name>` を書く（結果のバンドルの手順で読める）
- 後処理の押下: N21・N23 の `assertEvent` は読み取りと待ちだけで、押下は無い（`NotificationScreen.waitForEvent`、`SampleApp.waitForNextResult` など）。押下があるのは別の経路の後始末（`NotificationCleanup`）で、サンプルが背景なら前面に出し（`activate`）、押す前の窓の持ち主の検査（`SampleApp.swift` の `overlayVerdict`）を通る。どちらも新しい後条件（`waitForSampleInFront`）より後なので、前面化が確かめの不足を覆う順にはなっていない（Codex の確かめ v3 C-1 で直した）
- **回帰の確かめ**（VM だけ。確かめた後にすぐ元に戻した）: サンプルの Open を `isForeground: false` にした回では、N23 は XCUITest の待ち（`SampleApp.swift:506`「did not become 4 in 10.0s (now 3)」）で落ちた。さらに N23 の XCUITest の待ちも外した回では、新しい確かめが「the sample did not come to the front for AppKit in 10.0s after Open」（`NotificationCenterUI.swift:126`）で落とした
- **VM の負荷の急な上がり**（2 回目の回帰の回）: N14b の途中から、ゲストで `AXVisualSupportAgent`（99%）と `spindump`（95%）が回り、load average が 150 に上がり、ssh が一度時間切れになった。xcodebuild やサンプルの増殖は無かった。`AXVisualSupportAgent` を VM の中で止めると数分で下がった。その回の N14b（`notificationRoot`、根を 57 秒待って無し。3 分 52 秒）と N15（2 分の時間切れ）はこの負荷による。この Mac には何もしていない
- その後の 2 回（ゲストの再起動の前）は、どちらも NP2 の許可の戻しが効かず（`NTK-RUNNER:permissionReset` と `notNotDetermined`）、ほかの 59 件は通った。負荷の後の VM の状態によると見て、ゲストを再起動して流し直した

| 回 | 条件 | 結果 |
|---|---|---|
| 回帰 1 | Open を `isForeground: false`（一時） | 59/60。N23 が XCUITest の待ちで落ちた |
| 回帰 2 | ＋ N23 の XCUITest の待ちを外した（一時） | 57/60。N23 が新しい AppKit の確かめで落ちた。N14b・N15 は VM の負荷による |
| 確かめ 1・2 | 直した形。ゲストの再起動の前 | 59/61、59/61（どちらも NP2 の許可の戻しだけ） |
| 確かめ 3・4 | 直した形。ゲストを再起動した後 | **60/60、60/60** |

`git diff` で、サンプルと N23 の一時の変更が残っていないことを確かめた。VM の `~/ntk/runs` と `~/ntk/failed` は空。

- `FinderFront` の一連のレビュー（Codex v1〜v3）は、v3 で致命的な A が 0 になって閉じた。記録は `reviews/2026-11-23-macos-c-abi-finderfront-review-v1.md`。信頼する部分のハッシュ（`NotificationCenterUI`・`NotificationRules`・`OtherApps`）を取り直し、この Mac の自己テストは 190 件のうち 182 件が通り 8 件が skip（VM の本物の分）

## 18. VM の全件と基準の取り直し（2026-11-24。`4ceaec17` の木）

- `scripts/test_mac.sh --where vm --baseline` を 1 回（run id `20261123T211442Z-49bcad`、06:14〜06:47、約 33 分）。ゲストは前の再起動から 49 分、load average は 0.5〜1.7 で始めた
- **444/444 passed**。資格の 10 項目、VM の写しの木とランナーの写しの照合、組み立て（警告 0）、列挙（UI 118・選ぶ 113・除く 5）、単体を通った。通知の UI の立て直しは 3 回。`NTK-VM settle calls=45 left-after-15s=0 most=0 longest-wait=0.1s`
- 前の基準との差: `changed=0, added=0, removed=0, excluded changed=0, fewer runs=0, more runs=0`
- **基準を取り直した**（コミットしていない）: `source.head` は `4ceaec17`、`runnerFiles` の 3 つはそのコミットのファイルと一致した。前の基準（`d89f9d46` の木）からの変化は `macTree`（Support とテストの直し）と、テストごとの秒（合計 1742 → 1700 秒。最も延びたのは N6 の +4.1 秒）だけで、`results`・`runs`・`counts`・`eligible`/`executed`（113）・宣言・表・監査のハッシュは同じ。ランナーが前の基準を日付つきの名前に移したが、中身はコミット済みのものと同じで git の履歴にあるので消した

## 19. この Mac で流す前に要る 4 項目（`MAC_RUN_PREREQUISITES`）の段取り

どれも、確かめた記録を `artifact/topics/macos-c-abi/results/` に置き、その道を `MAC_RUN_PREREQUISITES` の値に書いて初めて数える（`prerequisite_status`）。一時の試験の道具は VM の写しにだけ置き、コミットしない（0c の合成の窓と同じ扱い）。

| 項目 | どこで | 段取り | 通る条件 |
|---|---|---|---|
| `u8MonitorStopsTheTest`（U-8） | VM | 写しだけに一時の試験のクラスを置く。サンプルを前面にした後、別の合成のアプリ（押されたボタンをファイルに書く `NSAlert` だけのアプリ）に無害なアラートを出させ、続けてサンプルのボタンを押す手順にする。7 章の「監視」の変異（監視が押す枝を持つ形）も同じ場面で流す | 監視が来て何も押さず（合成のアプリのクリックの記録が 0）、サンプルを止め、テストが `NTK-STEP:interrupted` / `NTK-INTERRUPTED` で落ちる。押す枝を持つ変異では、合成のアプリにクリックが記録されて区別できる。3 回 |
| `killDuringRecording`（9.1） | VM | VM の中で、この Mac の道と同じ形（`CAPPED_PERL` に PID のファイル、`settle`、`stop-current` の判定）で本物の UI テスト（長めの Dialog の 1 件）を流し、収録の途中（テストの開始から 5〜10 秒）で親のシェルを `KILL` する。その後、perl が親の居なくなったことで group を止めるか、group の外の書き手（UI テストのランナーのアプリ、サンプル、`testmanagerd`、`VTEncoderXPCService` など）が残るかを libproc の一覧で 30 秒追い、回のフォルダーの判定（`run_processes`）が「動いている」→「消せる」に移る時刻を記録する。消した後 30 秒、結果のバンドルや収録が作り直されないかを見る | 親の KILL の後、30 秒以内に回のものが何も動かなくなり、判定が「消せる」になる。消した後に作り直されない。捉えられない書き手があれば、その名前と止まり方を記録し、片付けの条件に足す（ランナーを直す）。2 回 |
| `decoyNotificationRoot`（6c、7 章「根（動き）」） | VM | おとりのアプリを作る（別の bundle id。サンプルと同じ題・本文・category と `Open`・`Reply` を持つ通知を出し、`didReceive` と返信の文字をファイルに書く。0a の試作は label が `NtkProbe0a, ` で始まり錨に当たらないので作り直す）。通知のイベントとコールドスタートのクラスの前に、おとりの通知をサンプルの通知より前に並ぶ形と後に並ぶ形の両方で置いて、N20〜N24・NC1〜NC3 を流す。7 章の「根（動き）」「根（焦点と placeholder）」の変異（合成で根の差し替え・焦点の移動を入れる）もここで | おとりへのクリック・`Options` の展開・文字の入力・Return・`didReceive` がすべて 0 で、サンプルのテストは通る。変異ではおとりへの到達が記録されるか、テストが押す前に止まる。前と後の並びをそれぞれ 2 回 |
| `windowOwnersReadableOn26`（U-30 mac26） | **この Mac**（VM は 15 なので確かめられない） | 許可の要る項目として計画に回す: `--where mac --qualification mac26 --dry-run` で一覧（U-30 の適格性の段）を作り、利用者に 4 つ（一覧、起きること、準備、時刻）を示して許可を得て、区切りの回に 1 回流す。窓の持ち主の PID・枠・層を `CGWindowListCopyWindowInfo` で読めるか、画面の収録の許可が要るか、署名と TCC の引き継ぎ（U-31）を見る | 26 で持ち主と枠が読め、押す前の確かめが働く。読めなければこの Mac では UI テストを流さない（設計 9.1 の 2 行目） |

順は、VM の 3 つ（U-8 → KILL → おとり。どれも合成の道具を先に作る）を先にし、記録がそろってから、この Mac の `mac26` の許可を利用者に頼む。

