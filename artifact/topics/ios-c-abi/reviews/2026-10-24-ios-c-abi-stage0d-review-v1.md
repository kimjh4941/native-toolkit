# レビュー結果

- 日付: 2026-10-24
- 対象: 段階 0d のランナー（`scripts/test_ios.sh`、`scripts/ios_ui_runner.py`、`scripts/tests/test_ios_ui_runner.py` と fixture）と、UI テストの信頼する部分（`Support/` の 8 ファイルと `DeviceRequirements.json`）。コミット前
- 判定: **要修正**（実機で流す前に、下の A と B を直し、直した所を再レビューする）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex（`gpt-5.6-sol`）の 2 者で並行）。読むだけで、実機には触れていない
- 判定の分かれ: Codex は A 5 件で「実機は不可」。Claude は A 0 件で「手順の上では進めてよい」としたうえで、B 10 件を実機の前に直すよう勧めた。私物の端末を守る仕組みの本体なので、両方の指摘を実機の前に直す

区分: A = 実機の前に必ず直す（安全か正しさの欠陥）、B = 直す、C = 軽い。

## 指摘と対応

### 私物の画面を押しうる所（信頼する部分）

| ID | 出典 | 所 | 指摘 | 対応 |
|---|---|---|---|---|
| R-1 | Codex（A） | `Springboard.swift:112,145,173` | `expandedScope()` は、広げた通知の根が 0 件か複数件のとき、springboard 全体に戻って Open・Delete・Reply・返信の欄・Send を探す。OS の差で根の型が変わると、私物の通知の同じ名前の要素を押しうる | `expandedScope()` を `throws` にし、根がちょうど 1 件でなければ押す前に失敗させる。返信の欄と Send もその根の中に限る（0c の実測で外にあったなら、根を返信の画面の根に替えるか、押さずに失敗にする）。全体へ戻る道は消す |
| R-2 | Claude（B1） | `Springboard.swift:204 tapAlertButton` | アラートにサンプルの名前があるかを自分で確かめず、テストの側の確かめに任せている。確かめてから押すまでの間に別のアラートが出る隙もある | `exactlyOne(springboard.alerts)` の中で `“IosLibraryExample”` を含むことを確かめてから押す |
| R-3 | Claude（B2） | `ClipboardPasteUITests.swift:41-43`（CB1） | 貼り付けのアラートがサンプルの名前を含むことしか確かめない。Universal Clipboard から来た内容（`from “<Mac の名前>”`）でも Allow Paste を押しうる | Springboard に「出どころがランナー（`from “IosLibraryExampleUITests-Runner”`）」を確かめる口を足し、CB1 はそれを満たすときだけ押す（ja のラベルは実機で確かめ、合わなければ押さずに失敗） |
| R-4 | Claude（B3） | `SampleUITestCase.swift:286-292` | 監視が未知の割り込み（私物のアラートが出たまま押さずに止めた）を記録した後も、tearDown の springboard の片付けがホームボタンを押す。ホームで私物のシステムアラートが閉じうる | 実機で `session.interruption != .none` なら、springboard の片付けを飛ばす |
| R-5 | Codex（B） | `Springboard.swift:82 waitForNoSampleBanner()` | 待った後に `session.checkInterruption()` を呼ばない。片付けの間に監視が未知の割り込みを処理しても、印を報告せずに成功しうる | `throws` にし、待った直後に `checkInterruption()` を呼ぶ |

### 許可を使い回せる所（ランナー）

| ID | 出典 | 所 | 指摘 | 対応 |
|---|---|---|---|---|
| R-6 | 両方（Codex A、Claude B5） | `ios_ui_runner.py:1032` | `NTK_TEST_IOS_APPROVAL_LEDGER` が本番の実行でも効く。`/dev/null` などにすると、同じ許可を何度でも使える | 本番は決まった場所だけを使う。差し替えは自己テストの専用の口（テストだけが渡す引数）に限り、`test_ios.sh` からは届かないようにする |
| R-7 | Codex（A） | `ios_ui_runner.py:1043` | 台帳の行の形を検証しない。途中で切れた行が残ると、同じ ID を使っていないと判定しうる。新しく作ったときに親のフォルダーを同期しない | 専用のロックの下で、全行を `ID<TAB>時刻<TAB>udid` の形として検証し、壊れた行があれば実機を拒む（fail-closed）。書き込みは一時ファイル → `fsync` → rename → 親のフォルダーの `fsync` |
| R-8 | Codex（A） | `ios_ui_runner.py:1010` | 許可の照合がテストの ID だけを比べ、各テストの区分と除いたものを比べない。区分を書き換えた一覧でも通る | 今の選び方から、時刻と ID のほかの期待値を作り直し、テストの順・ID・区分、除いたもの、信頼する部分のハッシュを構造ごとに比べる。知らないキーは拒む |
| R-9 | Claude（B6） | `ios_ui_runner.py:1017`、`cmd_verify_tree` | 許可がコミットとテストのフォルダーしか縛らない。サンプル・ライブラリ・pbxproj・scheme のコミットしていない変更が、そのまま実機に入る | `ios/`（`build/` を除く）にコミットしていない変更があれば、実機を拒む |

### 実機に届きうる・黙って続きうる所（ランナー）

| ID | 出典 | 所 | 指摘 | 対応 |
|---|---|---|---|---|
| R-10 | Claude（B4） | `test_ios.sh:51-54 sim_xcodebuild` | 宛先を確かめないので、続きの行に実機の `-destination` を書けばガードを通らずに実機へ届く。自己テストの静的な検査も `-destination` の行を除いているので捕まえない（変異 2 つがすり抜けた） | `sim_xcodebuild` の引数に `platform=iOS Simulator,id=` 以外の `-destination` があれば 97 で止める。静的な検査は続きの行をつないでから判定する |
| R-11 | 両方（Codex A、Claude B7・C） | `ios_ui_runner.py:1306-1328` | 名前を読めなかった結果は問題に足すだけで止める条件に入らず、`zip(cases, keys)` で組がずれる・抜ける。実機で宛先が食い違っても、時間切れでも止まらない | 結果の 1 件ごとに正規化の結果を組で持つ。正規化できない、知らない繰り返しの形、宛先の食い違い、時間切れを、実機の即時の停止の条件にする。全件の数と正規化できた数の一致も照らす |
| R-12 | Claude（B8） | `test_ios.sh:312` | 実機の test-without-building に `-derivedDataPath` が無く、副産物や端末の診断が、trap で消える一時フォルダーの外に残りうる | `-derivedDataPath "${DEVICE_TMP}/dd-test"` と `-collect-test-diagnostics never` を足す（効く範囲は実機で確かめる） |
| R-13 | Claude（C） | `test_ios.sh:48 capped` | perl の exec が失敗すると exit 0 になる | `exec @ARGV or die` |
| R-14 | Claude（C） | check-binary | 実機のバンドルの中の `DeviceRequirements.json` と `Info.plist` を照らしていない | 実機のビルドにも同じ確かめをかける |
| R-15 | Claude（C） | `make_plan` | 実機で選んだテストが 0 件の計画を拒む口が無い | 拒む |

### 確かめの穴

| ID | 出典 | 指摘 | 対応 |
|---|---|---|---|
| R-16 | 両方（Codex C、Claude B9） | 自己テストが CLI のつなぎ（`cmd_approve`、`cmd_record`、`cmd_may_uninstall`、`cmd_verify_tree`、preflight、summary など）とシェル全体を確かめていない。11 個の変異が 93 件を通った。許可の区分の改変、壊れた台帳の行、正しい結果に正規化できない名前を足したもの、のテストも無い | 各 `cmd_*` を subprocess で呼ぶテストを足す。`xcrun`・`xcodebuild`・`otool`・`git` の差し替えで `test_ios.sh` を最後まで流すテストを 1 本足す（実機の dry-run で実機を呼ばない、使用済みの許可で devicectl の前に止まる、正規化できない結果で exit 3）。11 個の変異と R-6〜R-15 の変異が捕まることを確かめる |
| R-17 | Claude（B10） | 実機が使う「1 件ずつ名前を指定する」経路（`()` 付きの名前 → xcresult → 照合）を、通しで流したことがない | シミュレーターでも 1 件ずつ名前を指定する形を選べるようにし、実機の前にシミュレーターで一度通しで流す |

### 直さないもの（記録）

- `UnexpectedAlertGuard.swift:70`: `systemui` のテストで `NotificationShortLookView` に `false` を返すので、私物のバナーも既定のハンドラに渡る。既定のハンドラはアラートでない要素を押さずにバナーが消えるのを待つ（0c の実測）。設計の U-8 が受け入れた範囲で、実機で動きを見る
- 印の `.session` から割り込みの記録を書き換えられる。脅威の範囲（うっかりした誤り）の外
- 実機の xcresult の `deviceId` の形と devicectl の `hardwareProperties.udid` は確かめていない。合わなければ fail-closed になる

## 実機の最初の実行（Claude の勧め）

実機の最初の実行は `--device-allow` を空にし、区分の無いテストだけで、設計書の 8.2 の確かめていない項目（`TEST_RUNNER_` が実機のランナーに届くか、devicectl の UDID の形、名指しの数）を確かめる。流す前に利用者に知らせて許可を得る。
