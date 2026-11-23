# レビュー結果

- 日付: 2026-11-23
- 対象: 段階 0d のランナー（`036dc083`）。`scripts/test_mac.sh`、`scripts/mac_ui_runner.py`、`scripts/mac_unit_audit.json`、自己テスト、変異のハーネス、fixture。作業の記録 `results/2026-11-23-macos-c-abi-stage0d-working-notes.md`
- トピック名: macos-c-abi（段階 0d のランナー）
- 判定: **要修正 → 直した**（区分 A をすべて直した。再レビューは親が決める）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者。どちらも読むだけで、スクリプト・自己テスト・変異は流していない）
- 全文: scratchpad の `review/runner-claude-v1.md`（Claude。A 4、B 16、C 11）、`review/runner-codex-v1.md`（Codex。A 10、B 6、C 1。親への知らせでは B 5）

区分: A = 私物の Mac を壊す・汚す・私物を漏らしうる、または基準が誤る / B = 確かめの不足 / C = 記述。「出典」は指摘したレビュアー。R は統合後の番号。

## 件数

| 区分 | Claude | Codex | 統合後 |
|---|---|---|---|
| A | 4 | 10 | 11（重なり 3） |
| B | 16 | 6 | 19（重なり 3） |
| C | 11 | 1 | 11（重なり 1） |

## 直す間と直した後の決まり（親の指示）

- この Mac では、変異のハーネスと、本物の `os.kill`・`rm -rf`・`pkill`・`killall`・`defaults write`・`lsregister`・ssh を通りうる自己テストを流さない。流してよいのは、それらを偽の口に差し替えて本物に届かないことを確かめた自己テストだけ
- 変異のハーネスは VM の中で流す。`--in-vm` もこの Mac で呼ばない

## 区分 A

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| RA-1 | Codex A-1、Claude B-1 | `--in-vm` の入口の確かめが PATH の `sysctl` の出力 1 つだけで、偽の `sysctl` や同名の関数で通れる。通ると `pkill -x Mail`・`rm -rf ~/ntk/runs/*`・通知の設定の書き換えに届く | `--in-vm` は最初の文で `env -i`（PATH・関数・BASH_ENV を持ち込まない）と `bash --noprofile --norc` で自分を起動し直す。`in_vm_main` の最初の 3 行で、`/usr/sbin/sysctl` の `kern.hv_vmm_present` が 1、`hw.model` が `VirtualMac`、`/usr/sbin/ioreg` の `IOPlatformUUID` が引数の UUID（資格を確かめた VM のもの）であることを、`command` と絶対パスで確かめ、1 つでも外れれば 96 で止まる。この Mac は UUID が違うので、`sysctl` を偽っても止まる。自己テストは本文を読んで、最初の文とこの 3 行と、入口より前に破壊的な命令が無いことを確かめる（実行しない） |
| RA-2 | Codex A-2 | `$(runner only-testing ...)` を xcodebuild の引数に直接展開しており、名指しの取得が失敗・空なら全件の実行になる | この Mac では名指しを別に読んで配列にし、失敗・空なら止まる（`read_only_testing`）。xcodebuild の直前に `check-call` が、`-only-testing:` の並びが計画のその呼び出しとちょうど同じことを照らす（空も拒む）。VM の中も別の代入にして失敗・空なら止まる。単体テストは、この Mac では監査した suite（計画の `auditSuites`）の `MacLibraryTests/<suite>` だけを許す（Claude B-10） |
| RA-3 | Codex A-3 | `XCODE_XCCONFIG_FILE`・`TOOLCHAINS`・`TEST_RUNNER_*` を受け継ぎ、承認の外の設定で組める | 先頭で `XCODE_XCCONFIG_FILE`・`TOOLCHAINS`・`DEVELOPER_DIR` と、すべての `TEST_RUNNER_*`・`SIMCTL_CHILD_*` を消す。この Mac の xcodebuild は `env -u XCODE_XCCONFIG_FILE -u TOOLCHAINS DEVELOPER_DIR=<26.6>` で、Xcode 26.6 の xcodebuild を絶対パスで呼ぶ。テストに渡す `TEST_RUNNER_NTK_*` はランナーが付けたものだけになる |
| RA-4 | Claude A-1、Codex B-2 | この Mac の `test-without-building` に `-derivedDataPath` が無く、iOS の `require_own_paths` に当たる検査が無い。結果のバンドルの置き場の照合は何も確かめていない。`--dry-run` は「収録は消す」と言い切っている | `check-call`（純粋な `call_problems` と `path_symlink_problems`）を写した: 動作の語はちょうど 1 つ（組むなら `build-for-testing`、流すなら `test-without-building`）、`-derivedDataPath`・`-resultBundlePath`（流すとき）・`-workspace`（組むとき）・`-xctestrun`（流すとき）はちょうど 1 回ずつ 2 つの引数の形で、ランナーの私的な一時フォルダーの中の素直なパス（空・`.`・`..` の段なし）、どの段にも symlink が無い。外れれば 97。流す呼び出しに `-derivedDataPath "${MAC_TMP}/dd-test"` を足した。意味の無かった照合は消し、結果のバンドルの宛先が 1 台でなければ `destination` で止まる形にした。`--dry-run` の文を「一時フォルダーに置いて終わりに消す。Xcode がほかに何も残さないことはまだ確かめていない」に直した |
| RA-5 | Codex A-9、Claude A-2 | この Mac の `ps -axo args=` の全体と VM の生の事実を、リポジトリの中の `OUT` に書き、失敗の道では消さない | `ps` は標準入力で Python に渡し、どこにも書かない（`--ps -` しか受けない）。VM の事実・`lsregister` の dump は、リポジトリの外の私的な一時フォルダー（`umask 077`、`ntk-test-mac-private.*`）に置き、どの終わり方でも 1 つの EXIT の trap（`on_exit`）が消す。自己テストは本文を読んで、`.ps.txt` が無いこと、資格の関数が `OUT` に隠しファイルを書かないこと、trap が何かを作る前にあることを確かめる |
| RA-6 | Codex A-7、Claude A-4 | VM の呼び出しが結果を返さない（ssh の切断、96、途中の失敗）と、0 件を成功として受けて次へ進む。要約は計画の全件が記録にあるかを照らさず、基準は `executed == eligible` を求めない。見張りは「失敗の行があるか」だけを見る | VM の UI の呼び出しが 0 でない終了か記録 0 件なら、その呼び出しから後を `runStopped`（`NTK-STOP:noResult`）の失敗として記録して止まる。96 はすぐ止まる。単体の呼び出しも記録が無ければ `noResult` の失敗を足す。見張りは「ちょうど 1 件の成功で失敗 0」のときだけ通す。要約に `completeness_problems` を足した: UI の記録が計画の全件ちょうど 1 件ずつ、計画の単体テストのターゲットに記録がある、fixture・押したボタン（全件の VM）・プライバシーの戻しの結果がある。外れれば失敗。基準は `executed == eligible`（重複なし）と、前の基準からの欠けが無いことを求める。`--save-baseline` でも欠けを失敗に数える |
| RA-7 | Codex A-8、Claude B-16 | 単体テストの結果を、計画・監査した suite・期待する集合と照らさない。名前の正規化の後の重複を見ない。`Arguments` のほかの子の形も見ない | VM で `MacLibrary` のスキームも列挙し（`unit-enumeration.json`）、計画の単体の呼び出しに期待するテストの集合（`expected`）を持たせた。記録はその集合とちょうど同じでなければ `namedSet` の失敗、正規化の後の重複は `readable`、`Failure Message` と `Arguments` のほかの子は `unknownShape`、別のターゲットのバンドルは `otherBundle` |
| RA-8 | Codex A-4、Claude B-3、C-9 | この Mac の片付けが、pid のファイルの番号の group へ 3 つの一致を確かめずに TERM・KILL を送り、`pkill -f` は引数の一致で止める。KILL の後に止まったかを確かめずに消す | 片付けを `runner stop-current` 1 つにした: 今の回の印の書き手を、`stale_plan` と同じ 3 つの一致（と、今の回のフォルダーの下で印の後に起きたプロセス）で選び、TERM → 待つ → KILL → 待つ、止まったことを確かめてから、登録を外し、fixture とフォルダーを消す。止まらなければ何も消さずに失敗する（場所は出さない）。`pkill -f` は使わない。pid のファイルは xcodebuild が終わるたびに消す |
| RA-9 | Codex A-5 | 前の回の片付けで、最初に作った PID の一覧を待った後の KILL にも使う。待つ間に番号が再利用されると別のプロセスに届く | `stop_writers` は TERM と KILL のそれぞれの直前に、その時のプロセスの一覧から計画を作り直す（group の構成も）。偽の口で「待つ間にサンプルが終わり、その番号を Mail が使う」場面を作り、Mail に何も送らないことを自己テストで確かめた |
| RA-10 | Codex A-6、Claude B-5 | 印が無い・壊れたフォルダーを「書き手なし」として消す。印の `root` をそのフォルダーと照らさない（`/` なら全プロセスが書き手になる）。`stale` は `--list` を付け忘れると止めて消す | 印が無い・読めないフォルダーは消さずに止まる（`NTK-STALE:refused`）。`stale_plan` は印の `root` がそのフォルダーの実体のパスで、名前が `ntk-test-mac.` で始まることを求める。`stale` は `--list` か `--stop` のどちらか 1 つを必須にし、`--stop` は承認した計画の `stale` の一覧が今と同じときだけ動く。止めた後は、そのフォルダーの登録と fixture も外す |
| RA-11 | Codex A-10、Claude B-6 | fixture を `mkdir -p` と `>` で作り、先にある symlink を辿って書きうる。中断のとき fixture を消さない | `fixture_create` で作る: 根は `mkdir`（あれば使わずに止まる）、自分の持ち物の symlink でないフォルダーであることを `lstat` で確かめ、ファイルは `O_CREAT | O_EXCL | O_NOFOLLOW`。`fixture_manifest` も根を確かめる。fixture は印の `runId` から道を決め、今の回の終わりと前の回の片付けの両方で、持ち主と形を確かめてから消す |

Claude A-3（変異のハーネスをこの Mac で流し、自己テストの 1 件が本物のプロセスを起こして本物の停止の道を通す）は、下の RB-1 で直した。

## 区分 B

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| RB-1 | Claude A-3、Codex B-4 | 変異のハーネスと自己テストが、この Mac で本物の OS の操作に届く形 | 自己テストは、ランナーを読み込む前に `os.kill`・`os.killpg` と、`git` と「PATH に害の無い 3 つの道具しかない `/bin/bash`」のほかのすべての subprocess を、テストを落とす偽物に差し替える（差し替えが効いていることも確かめる）。本物のプロセスを起こす 1 件は消し、止める処理は `OsPort` を差し替えた偽の口で確かめる。ハーネスは最初に `/usr/sbin/sysctl` で VM であることを確かめ、VM のほかでは何もせずに止まる |
| RB-2 | Claude B-2、Codex B-1 | 同一性の束ねが UUID だけ。VM が `--no-clipboard` なしで立て直されても通る。ssh の設定が利用者の `~/.ssh/config` に左右される | どの ssh の命令の前にも、この Mac の `ps`（標準入力で渡す）で `tart run` の引数を照らし直す。VM の中では UUID に加えて起動の時刻（`kern.boottime`）を照らす（立て直すと変わる）。ssh に `-F /dev/null`。`tart` の側の VM の固有の値と UUID の対応付けは、`tart` が UUID を出さないので行っていない（既知の鍵・固定した known_hosts・UUID・起動の時刻・tart の引数の照らし直しで代える） |
| RB-3 | Codex B-3 | 監査の suite と読んだファイルの対応を照らさない。`review` が真偽だけ | suite はそのファイルが `struct/class/enum/actor <名前>` で宣言していること、表に 1 回だけで `notListed` に無いことを求める。`review` は `by`・`date`・`treeHash`（表と同じ木）を持つ形だけを受ける |
| RB-4 | Claude B-4 | 書き手を fork の直後に記録し、実行ファイルが perl や shim のままのことがある。記録の失敗を黙って続ける | xcodebuild を Xcode 26.6 の絶対パスで呼び、印には実体のパスが `MAC_XCODE_DIR` の下になってから記録する（最大 10 秒。`writer_entry`）。記録できなければその呼び出しを止めて失敗する |
| RB-5 | Claude B-7 | `lsregister -dump` の一時フォルダーが失敗の道で残る | dump は私的な一時フォルダー（RA-5）に置き、EXIT の trap が消す |
| RB-6 | Claude B-8 | R-19 の gate と `approve` のつなぎに自己テストも変異も無い | 一時の git リポジトリと一時の台帳で、gate が通る形と、計画の digest・台帳・ランナー・木のそれぞれの変化で止まることを確かめる自己テストを足した。変異「gate が digest／台帳／ランナー／木を見ない」を足した |
| RB-7 | Claude B-9 | 許可に期限が無い。計画に OS のビルド・Xcode の版・`--baseline` が入らない | 許可は書かれてから 12 時間（`APPROVAL_HOURS`）で使えない。計画と許可に `environment`（OS の版とビルド、Xcode の版）と `baseline` を入れた |
| RB-8 | Claude B-10 | この Mac の単体テストに二度目の確かめが無い | RA-2 のとおり |
| RB-9 | Claude B-11 | 語の照らしが前置に弱い（`NSSharingServicePicker`）。別の書き方の語が無い。mock を数えない。監査の木に scheme と workspace が無い。表のハッシュを照らす自己テストが無い | 語を正規表現の表（`AUDIT_PATTERNS`）にし、`NSSharingService\w*`・`NSWorkspace\w*`、`NSGeneralPboard`・`Apple CFPasteboard general`・`NSPasteboard(name:` を足した。mock（`**/Mock*.swift`）を `helpers` として数え、表に無い mock に語があれば何も選ばない。監査の木に `xcshareddata/xcschemes` と workspace を足した。自己テストで今の木のハッシュと表の `treeHash` を照らす。表は作り直した（`review` は null のまま） |
| RB-10 | Claude B-12 | この Mac は作業ツリーをそのまま組み、git が無視する `xcuserdata` の scheme などが入りうる | この Mac も、VM に渡すのと同じ `git ls-files` の一覧を私的な一時フォルダーに写して組む。写しの木のハッシュが承認した `macTree` と同じでなければ止まる |
| RB-11 | Claude B-13 | `RunnerError` のほかの例外で traceback がこの Mac のパスを出す | `main` で全ての例外を受け、種類の名前と `NTK-RUNNER:internal` だけを出す |
| RB-12 | Claude B-14、Codex B-5 | この Mac で流す前の確かめ（U-8 の監視、収録の途中の KILL、26 の窓の持ち主）がランナーに無い | `MAC_RUN_PREREQUISITES`（3 項目。確かめた記録の場所を書く）を置き、空の項目があれば許可を拒む。`--dry-run` にも「NOT READY」と出す。今は 3 つとも空なので、この Mac の `--approved` はまだ通らない |
| RB-13 | Claude B-15 | 危ない名前の例外を回数だけで許し、受け手を見ない | `DialogUITests.swift` の `typeKey` は `alert.typeKey(` の形だけを許す |
| RB-14 | Codex B-6 | 監査の失効を基準の除外の差に反映しない | 保存と比べ合わせの両方で `excluded_map`（単体のターゲットの除外を含む）を使う |
| RB-15 | Codex B-1 | ssh の行き先と tart の VM の対応 | RB-2 |
| RB-16 | Codex B-2 | 出力先の guard | RA-4 |
| RB-17 | Codex B-5 | 本物の収録の途中の KILL と割り込みの停止の実証が残る | RB-12 の前提の表で機械的に止める。実証そのものは残した（下の「残したこと」） |
| RB-18 | Claude B-16 | 正規化の後の重複 | RA-7 |
| RB-19 | Codex B-3 | （RB-3 と同じ） | RB-3 |

## 区分 C

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| RC-1 | Claude C-1 | 設計書との差の表に足りないもの 8 つ | 作業の記録 7 章に足した（変異をこの Mac で流したこと、本物のプロセスの 1 件、置き場の検査の写し漏れ、書き手の記録、登録の外しを知らせていなかったこと、`NTK-STALE` の出し方、Finder 以外の前面のアプリを止めない、VM の名前・ip・鍵を記録しない） |
| RC-2 | Claude C-2 | 作業の記録の状態の行が「コミットしていない」 | 直した |
| RC-3 | Claude C-3 | 自己テストの docstring が `/bin/sleep` と書く | 書き直した |
| RC-4 | Claude C-4 | `cmd_stale` の説明の `--stop` が無い | RA-10 |
| RC-5 | Claude C-5 | 基準の `source` にランナーのハッシュが無い | 次の基準から `source.runnerFiles` を入れる |
| RC-6 | Claude C-6 | この Mac の `xcrun otool`・`xcresulttool` に `DEVELOPER_DIR` が無い | 付けた |
| RC-7 | Claude C-7 | ssh が利用者の設定に左右される | `-F /dev/null` |
| RC-8 | Claude C-8 | `NTK-PRECONDITION:` の後ろが閉じた語彙でない | `PRECONDITION_NAMES`（今の 4 つ）に閉じ、記録の側でも照らす。`NTK-RUNNER:` も `RUNNER_PROBLEMS` に閉じた |
| RC-9 | Claude C-9 | `pkill -f` が正規表現 | RA-8 で使わなくなった |
| RC-10 | Claude C-10 | 基準をちょうど同じ OS の版でしか探さない | 無ければ同じ `where` の最新の基準と比べ、版が違うと出す（`latest_baseline`） |
| RC-11 | Claude C-11、Codex C-1 | 出ない問題の名前、`--allow-lsregister` を使えるように案内する | 使わない名前を外し、`permissionReset`・`destination` を実際に出す形にした。`--allow-lsregister` はヘッダー・`--dry-run`・引数の検査で「未実装、利用者が外してから計画し直す」にそろえた（渡すと最初に止まる） |

## 確かめ

| 何を | どこで | 結果 |
|---|---|---|
| 自己テスト（本物の OS の操作を偽物に差し替えたもの） | この Mac | 138 件、すべて通った |
| 同じ自己テスト | VM（`/usr/bin/python3` 3.9） | 137 件が通り、1 件 skip（写しが git のチェックアウトでない） |
| 変異 140 個 | VM だけ（ハーネスが VM であることを確かめてから動く） | 1 回目 136 個が捕まり 4 個が生き残った。その確かめだけを切り出す自己テストを足した。2 回目は変異なしの写しが VM の `python3` の shim で落ちたので使わず、テストを直した。3 回目は 140 個すべて捕まり、変異なしの写しは通った |
| `--where mac --dry-run`（7 区分） | この Mac（読むだけ）と VM（組み立てと列挙） | 99 件・除外 19 件。「NOT READY」が出る。私的なパスは出ない。私的な一時フォルダーは消えた |
| `--where vm --feature Dialog` | VM | 1 回目は資格の `identity` で止まった（VM の起動の時刻の読み方の誤り。`usec` を拾った。止まる側に倒れた）。直して 47/47、基準と差なし。私的な一時フォルダーは消えた |
| `--where vm`（全件、`--baseline` なし） | VM | 444/444、基準と差なし（changed・added・removed・除外の差 0）。33 分。基準は取り直していない |
| iOS の自己テスト | この Mac | 通った（iOS のファイルは変えていない） |

この Mac では、`--in-vm`、変異のハーネス、本物の停止・削除・`lsregister`・ssh に届く自己テストを流していない。

## 残したこと

- `MAC_RUN_PREREQUISITES` の 3 項目（U-8 の監視が止めることの VM での確かめ、本物の XCUITest の収録の途中に親だけを KILL する確かめ、26 の窓の持ち主）は空のまま。そのあいだ、この Mac の `--approved` は許可の照合で止まる
- この Mac の `--approved` の道は一度も通していない（この Mac で流さない約束のため）。確かめたのは純粋な関数、偽の口、シェルの本文の順
- 監査の表の別のモデルのレビュー（`review` は null）
- 信頼する部分のハッシュとランナーの再レビュー（このレビューの直しを含む）
- `tart` の側の VM の固有の値と UUID の対応付け（RB-2）、`--allow-lsregister` の実装
- N21 の揺れ（`NTK-STEP:finder`。Support の待ちの形で、信頼する部分の変更になる）
