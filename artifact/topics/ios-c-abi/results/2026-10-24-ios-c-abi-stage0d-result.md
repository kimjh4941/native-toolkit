# 段階 0d の結果: テストのスクリプトと基準

- 記録日: 2026-10-24
- 実施日: 2026-10-24
- 対象: `artifact/topics/ios-c-abi/README.md` の段階 0d、`designs/2026-10-18-ios-c-abi-ui-test-design.md` の 3.7、6.3〜6.5、7 章、8.2
- ブランチ: `feature/NTKIT-18`
- 判定: **完了**（ランナーができ、2 つの環境で基準を記録した）。ただし、実機の基準は区分の無い 19 件だけ。README の 0d の行にある `UnityIosPluginTests` の 83 件の 1 回の実行（D-22）は、この文書を書いた後に行い、83 件すべてが成功した（`results/2026-10-24-ios-c-abi-bridge-tests-before-0e.md`）
- 作業の記録: `results/2026-10-24-ios-c-abi-stage0d-working-notes.md`
- レビュー: `reviews/2026-10-24-ios-c-abi-stage0d-review-v1.md`〜`v3.md`

## 1. 結論

`scripts/test_ios.sh` と `scripts/ios_ui_runner.py` を作った。単体テストと UI テストを 1 つのシミュレーターか実機で流し、`.xcresult` から結果を読み、基準と比べる。実機は利用者の私物なので、設計の 3 本柱（ランナーが選ぶ、宣言の正しさの照合、毎回の利用者の許可）をランナーに入れた。

ランナーと信頼する部分は、別モデルのレビューを 3 回通して区分 A を 0 にした。その後の実機の 1 回目で見つかった直しも、Codex の確かめを 3 回通して区分 A を 0 にした（4 章）。

今のコードで、基準を 2 つ記録した（5 章）。シミュレーター（iPhone 17、iOS 26.2）は全件の 295 件（294 件が通り、U10b は意図した skip）。実機（iPhone XS、iOS 18.7.2）は区分の無い 19 件で、3 回目に 19/19 が通った（6 章）。

## 2. ランナー

| ファイル | 中身 |
|---|---|
| `scripts/test_ios.sh` | 薄い殻。xcodebuild・simctl・devicectl を呼ぶだけで、決めることは Python に渡す。実機に触れる関数（`device_xcodebuild`、`device_devicectl`）は、許可の消費と片付けの trap の登録が済むまで止まり、呼ぶたびに `device_guard` を通る |
| `scripts/ios_ui_runner.py` | 純粋な関数と小さな CLI。宛先の判定、列挙の読み取りと正規化、宣言の表との照合、クラスの下限、`ClipboardUITests` の固定、閉じた形のソースの規則、信頼する部分のハッシュ、選び方、名指し、許可の一覧と台帳、実機のバイナリの一覧、結果の読み方と skip の分類、押したボタンの照合、基準との比べ方 |
| `scripts/tests/test_ios_ui_runner.py` | 自己テスト 132 件（3 章） |
| `scripts/tests/ios_ui_runner_mutations.py` | 変異を流す仕組み（3 章）。単体テストではない |
| `scripts/tests/fixtures/ios_ui_runner/` | 実物の出力の写し（列挙の JSON、`otool -ov` / `-l`、xcresult の JSON、添付の manifest、simctl の一覧。パスは置き換えた） |
| `ios/.gitignore` | `IosLibraryExample/build/`（ランナーの DerivedData と結果のフォルダー） |
| `scripts/README.md` | `test_ios.sh` と基準のファイルの行 |

**オプション**:

| オプション | 内容 |
|---|---|
| `--udid <id>` | 対象。`xcrun simctl list` にある UDID だけをシミュレーターとし、ほかはすべて実機として扱う（fail-closed） |
| `--enumerate-udid <id>` | 実機のときに必須。ビルドと列挙に使うシミュレーター |
| `--devicectl-id <id>` | 実機で、`--dry-run` でないときに必須。devicectl の識別子（アプリの削除と端末の情報） |
| `--feature <Dialog\|Notification\|Share\|Clipboard>` | その機能の UI テストのクラスと、共通のクラスだけ。単体テストは流さない |
| `--skip-unit` | 単体テストを流さない（単体テストはもともとシミュレーターだけ） |
| `--device-allow <区分,...>` | 実機で許す区分。既定は空 |
| `--dry-run` | シミュレーターでビルドと列挙をし、流すテストの一覧を出す。実機のときは許可の一覧を書いて止まる。実機には触れない |
| `--approved <file>` | 実機で流すときに必須。利用者が許可した一覧。1 つの許可で 1 回だけ流せる |
| `--baseline` | 失敗の無い全件の実行を、D-21 の 2 つの環境のどちらかの基準として保存する |
| `--name-each-test` | シミュレーターでも、実機と同じく 1 件ずつ名指しして流す（レビュー v1 の R-17） |

**流れ**: 対象の判定 → 閉じた形の規則 → シミュレーターの `build-for-testing` → 単体テスト（シミュレーターだけ） → 列挙と照合 → 流すテストの選び方 →（実機）許可の照合と消費 → 一時フォルダーと trap → 端末の情報 → 実機のビルド → 実機のバイナリの一覧 → 権限の段 → クラスごと → CB2 の段 → 結果の読み方 → 基準との比べ方。設計の 6.3 から変えた順は、設計の 8.7 の「段の順」。

**クラスの表**（`UI_CLASSES`）: `NavigationUITests`、`IdentifierInventoryUITests`（Common）、`DialogUITests`、`NotificationUITests`、`NotificationEventUITests`、`NotificationColdStartUITests`、`ShareUITests`、`ClipboardUITests`、`ClipboardPasteUITests`。別の段で流すのは `NotificationPermissionUITests`（NP2 → NP1）と `ClipboardPasteDenyUITests`（CB2）。時間切れは `ClipboardUITests` が 75 分、ほかは 30 分。

### 2.1 3 本柱

| 柱 | 入れたもの |
|---|---|
| 柱 1: ランナーが選ぶ | 宣言の区分がすべて `--device-allow` にあるテストだけを選ぶ。実機では、シミュレーターの列挙の identifier を `-only-testing:` に 1 件ずつ名指しする。名指しが 0 件なら呼ばない。選んだテストが 0 件の計画は拒む。実機では単体テストを流さず、列挙もしない |
| 柱 2: 宣言の正しさの照合 | 列挙と宣言の表の完全一致、クラスの集合、クラスごとの宣言の下限、`ClipboardUITests` の 22 件の名前とファイルのハッシュ、バンドルの中の表の写しのハッシュ、閉じた形のソースの規則（2.4）、実機のバイナリの一覧（2.5）、信頼する部分のハッシュ（2.3。実機では変わっていれば流さない） |
| 柱 3: 毎回の利用者の許可 | `--dry-run` が許可の一覧を書き、エージェントが利用者に見せて許可を得る。`--approved` の一覧を今の選び方と丸ごと照らし、許可の ID を台帳に記録してから実機に触れる（2.2） |

### 2.2 許可の ID と台帳

| 項目 | 内容 |
|---|---|
| 許可の一覧 | `--dry-run` ごとにランダムな許可の ID。流すテストの順・ID・区分、除いたテスト、`--device-allow`、`git rev-parse HEAD`、テストのフォルダーのハッシュ、信頼する部分のハッシュ、ランナーの 2 つのファイルの SHA-256（`runnerFiles`）、計画全体の正規化した SHA-256（`planDigest`） |
| 照合 | 今の選び方から許可の一覧を作り直し、ID と時刻のほかを丸ごと比べる（知らないキー・欠けたキーも拒む。R-8） |
| 台帳 | `~/Library/Application Support/native-toolkit/test_ios-approvals.log`。アカウントのホーム（`getpwuid`）の決まった場所だけで、環境変数と `$HOME` では動かない（R-6）。自己テストの差し替えは `approve` の隠れた引数だけで、`test_ios.sh` は渡さない |
| 台帳の書き方 | 専用のロックの下で全行を形で照らし、壊れた行・改行の無い最後の行・symlink なら実機を拒む。書き込みは一時ファイル → fsync → rename → フォルダーの fsync（R-7） |
| 消費 | 実機に触れる前に ID を記録する。台帳にある ID は拒む。止まった後の流し直しにも、新しい `--dry-run` と許可が要る |
| 許可の後 | 計画を一時フォルダーの読むだけの写し（`plan.approved.json`、0444）に替え、それだけを使う。実機のどの呼び出し（devicectl、xcodebuild）の前にも `device_guard` → `device-gate` が、計画の digest、台帳の ID、ランナーのファイル、木を照らし、外れれば 97 で止まる（R-19） |
| 木 | `ios/` に、`ios/IosLibraryExample/build/` のほかのコミットしていない変更があれば実機を拒む（R-9）。`scripts/ios_ui_runner.py` と `scripts/test_ios.sh` も、コミット済みで計画のときと同じであることを求める（R-18） |

台帳は、実機の 3 回で 3 行になった。

### 2.3 信頼する部分のハッシュ

`scripts/ios_ui_runner.py` の `TRUSTED_FILES`（ファイルごと）と `FROZEN_CLIPBOARD_SHA256`。今の値は `python3 scripts/ios_ui_runner.py hashes --tests-dir ios/IosLibraryExample/IosLibraryExampleUITests` で出る。

| ファイル | sha256 | 最後に変えた所 |
|---|---|---|
| `Support/SampleUITestCase.swift` | `f9ac9bc5b9aac62afae0499e27bc1ab7b64f5e7361229402b8d34591eb461499` | レビュー v1 の R-4 |
| `Support/SampleApp.swift` | `63edf06e72b7a7e881bf1b85427d16add388d3fe502e69f365e493b7c4d9a3d4` | 実機の 1 回目の後（I1 の戻るボタン） |
| `Support/Springboard.swift` | `d87dee42f805a7d7daaf20cc46bf242fc0c6fab4538e32e97bac3585bc39d785` | 0g の後の実機の後（N5 の手がかり。`2026-10-24-ios-c-abi-stage0e-working-notes.md` の 11.4。レビュー v2 の R-21 の後の値は `427a3b7b…`） |
| `Support/ShareSheet.swift` | `b32c3595080dfca93d415e6e70010373edd8cf9471fa41f4e024ef8893f69329` | 0e の実機の後（S5 の iOS 18 の題名の読み方。`2026-10-24-ios-c-abi-stage0e-working-notes.md` の 10.4。0c の終わりの値は `acbd1a91…`） |
| `Support/RunnerPasteboard.swift` | `003e15590840c3c174f0b181dbacca06b661b476dea0898d7456a3688e4a9bbc` | 0c の終わり |
| `Support/UnexpectedAlertGuard.swift` | `5f94e7b007e037cd9ca1393a512332acb3436a9ff2a19cfcaefcf91ea28c6bfa` | 0c の終わり |
| `Support/NotificationCleanup.swift` | `64a33263710150a505c14adcfeaf0144b8a43172194878ab652182284595f384` | レビュー v1 |
| `Support/SystemLabels.swift` | `f8d3e5807ede8eac4a54384338f4307f2d42a05908cf441c86d3b70a9548c0e7` | レビュー v2 の R-21 |
| `IosLibraryExampleUITests.swift`（`ClipboardUITests`、凍結） | `4612943da3ec0e32562d86d07d7d134521f1db5fed42e7543db742a5b8006cf3` | 0c の終わり |

`SampleApp.swift` の実機の 1 回目の後の変更は、作業の記録の 12.6・12.7 と設計の 8.7 で「別のモデルの再レビューはまだ」となっている。その後の Codex の確かめ（4 章）がこの変更を見たかは、記録に無い（8 章）。

### 2.4 閉じた形のソースの規則

swift-syntax は使わず、Python で字句に分けて照らす（コメントと文字列を外し、文字列の補間の中のコードは残す。利用者の決定）。設計の 6.1 の表に加えて、次も許すものだけにした（作業の記録の 5 章）:

- 属性は `@MainActor`、`@discardableResult`、`@escaping`、`@Sendable`、`@autoclosure`、`@unknown` だけ。`#` の名前（マクロを含む）も許すものだけ
- テストのファイルでは `extension`・`protocol`・`actor`・`deinit`・`required`・`convenience`・`dynamic` を禁じる
- テストのフォルダーには `.swift` と `Support/DeviceRequirements.json` のほかを置けない。`Support/` に信頼する部分の一覧に無いファイルを足すと、テストのファイルと同じ規則がかかる

### 2.5 実機のバイナリの一覧

実機のビルドの `.xctest` を、端末で起動せずに読む。テストのバンドルの `otool -ov` は相対のメソッドの一覧に selector を出さないので、`otool -l` で `__objc_selrefs` の番地を読み、番地から selector を引く（設計の 8.7）。`test<名前>` と `test<名前>AndReturnError:` を `test<名前>()` に正規化する。子のクラスは親のテストも子の名前で数え、ivar の名前はテストに数えない。シミュレーターの列挙とちょうど同じ集合でなければ止まる。実機のバンドルの中の `DeviceRequirements.json` と `Info.plist` も照らす（R-14）。

### 2.6 ちょうど同じ集合の照合

| 所 | 照らすこと |
|---|---|
| 列挙 | 配列の件数と一意の件数、宣言の表のキーとの集合、クラスの集合（`UI_CLASSES` と別の段の 2 クラス）、表の区分の名前、キーの重複 |
| 名指しの呼び出しごと | 結果のテストの配列（`nodeIdentifier` を正規化したもの）が、名指しとちょうど同じ（件数・重複・集合）。許可した一覧の和とも照らす。実機では、xcresult の `devices[].deviceId` が名指しした宛先であること |
| シミュレーターのクラスの呼び出し | 結果の配列が、列挙のそのクラスのテストとちょうど同じ |
| 結果の形 | Test Case の子は `Failure Message` だけを許す（R-20）。名前を読めない、繰り返し・引数・端末・構成の子、別のバンドル、宛先の食い違い、時間切れ、summary の食い違い、読めた件数が全件と違う、のどれかで実機の実行全体を止める（exit 3。R-11） |

**skip の分類**:

| 結果 | 扱い |
|---|---|
| skip の理由に `NTK-GATED:` | 失敗（ランナーと表の食い違い） |
| Expected Failure | 失敗（`XCTExpectFailure` は禁じている） |
| skip の理由に `NTK-PRECONDITION:` | 失敗 |
| 意図した skip の一覧（U10b の `M-08 could not be decided here`、U21 の `whole-content detection patterns were not all reported`） | `skipped` として基準に記録する |
| それ以外の skip | 失敗 |

### 2.7 DerivedData と結果の置き場所

| 所 | 内容 |
|---|---|
| 結果のフォルダー | `ios/IosLibraryExample/build/test_ios/<日時>-<機種>-<OS>/`。実機は `<日時>-device`。git の外（`ios/.gitignore`） |
| シミュレーター | その実行のフォルダーの中だけを使う: `dd-build`（ビルド）、`dd-enumerate` と `enumerate.xcresult`（列挙）、`dd-test`（クラスの実行）、`dd-unit`（`IosLibraryExampleTests`）。前の実行のビルドは使い回さない |
| 実機 | `mktemp -d` の一時フォルダー（実体のパス）の中だけ: `dd-build`、`dd-test`、実機の `.xcresult`。trap が `EXIT` で消す。`INT` / `TERM` / `HUP` は 130 / 143 / 129 で `exit` して `EXIT` の trap を走らせる。実機の test-without-building には `-collect-test-diagnostics never` も付ける |
| 名指しの規則 | `-version` のほかの xcodebuild の呼び出しは、`-derivedDataPath` を（テストの呼び出しは `-resultBundlePath` も）ちょうど 1 回、`-option <値>` の 2 つの引数の形で渡す。値は、根（シミュレーターは実行のフォルダー、実機は一時フォルダー）の真下より深い絶対パスで、空・`.`・`..` の段と改行が無く、どの段にも symlink（壊れたものを含む）が無く、実体のパスと同じときだけ受ける。xcodebuild の動作の言葉はちょうど 1 つで、`build-for-testing`・`test`・`test-without-building` のどれか。外れれば 97 |
| 実機の結果 | 実機の `.xcresult` からは添付を書き出さず、`get test-results tests` と `get test-results summary` の JSON だけを読む。シミュレーターでは押したボタンの添付（3.7）を `xcresulttool export attachments` で取り出す |

実機の 1 回目までは、シミュレーターの列挙が `-derivedDataPath` を渡しておらず、列挙の xcresult が Xcode の既定の DerivedData にできていた。この名指しの規則は、そのときに足した（6 章）。

## 3. 自己テストと変異

**自己テスト**: `python3 -m unittest scripts/tests/test_ios_ui_runner.py` で 132 件。すべて通った。実物の出力の fixture で正規化と照合を確かめるほか、`cmd_*` を subprocess で呼ぶテストと、xcodebuild・xcrun・otool・git を記録するだけの差し替えで `test_ios.sh` を最後まで流すテストを持つ（実機の dry-run は devicectl も実機の宛先も呼ばない、使用済みの許可は devicectl の前に止まる、読めない名前の結果で exit 3 になり一時フォルダーが消える、どの xcodebuild の呼び出しも自分のフォルダーを名指す、など）。

**変異**: `python3 scripts/tests/ios_ui_runner_mutations.py`。ランナーの写し（スクリプト、UI テストのフォルダー、サンプルのソース、pbxproj）で 1 つずつ壊して自己テストを流す。写しの台帳の場所と `HOME` を一時フォルダーに替え（替えられなければ流す前に止まる）、流す前と後に本物の台帳のフォルダーを比べる。

| 時点 | 結果 |
|---|---|
| 最初の実装 | 32 個とも捕まった |
| レビュー v1 の後 | 61 個とも捕まった（レビューで通ってしまった 11 個と、R-6〜R-15・R-17 の 18 個を足した） |
| レビュー v2 の後 | 75 個とも捕まった |
| 実機の 1 回目の後（DerivedData の置き場所） | 81 個、その後の Codex の確かめ（A-1・A-2）の直しで 89 個とも捕まった |
| A-3 の直しの後 | 変異なしの基準が通り、すべて捕まった。A-3 の変異はまだ一覧に足していない |

今の一覧は 90 項目で、そのうち 1 つは変異なしの基準（生き残るべきもの）なので、変異は 89 個。作業の記録の 12.9 は「90 個すべてが捕まった」と書いている（8 章）。

ほかに、シェルの上で、テストのファイルに `#if` を足すと規則で止まり、宣言の表から D1 を消すと列挙の照合で止まることを確かめた（どちらも戻した）。テストの側の変異は 0c の結果の 6 章。

## 4. レビュー

| 回 | レビュアー | 判定 | 主な指摘と対応 |
|---|---|---|---|
| v1 | Claude のサブエージェントと Codex（`gpt-5.6-sol`）の 2 者 | 要修正（Codex は区分 A 5 件、Claude は A 0 件・B 10 件） | R-1〜R-17。springboard の全体に戻る道を消す（R-1）、アラートと貼り付けの出どころの確かめ（R-2・R-3）、台帳を動かせない・壊れた行を拒む（R-6・R-7）、許可を丸ごと比べる（R-8）、コミットしていない変更を拒む（R-9）、結果の形の止め方（R-11）、通しのテスト（R-16）、1 件ずつ名指し（R-17） |
| v2 | 同じ 2 者。Codex は `--model gpt-5.6-sol`（設定の `gpt-6.1-sol` が `model_not_found` で拒まれたため。利用者の決定で、その回だけ指定した） | 要修正（Codex は区分 A 4 件、Claude は A 0 件・B 1 件） | R-18〜R-21。ランナーのファイルのコミット（R-18）、計画の digest と読むだけの写し（R-19）、Test Case の子の閉じた一覧（R-20）、サンプルにしか無い返信の placeholder（R-21）。C のうち 3 つ（`NTK_TEST_IOS_SOURCE_ONLY`、偽の xcrun、変異の仕組み）もあわせて直した |
| v3 | Codex の 1 者（`--model gpt-5.6-sol`） | 区分 A が 0。レビューを終えた | v2 の R-18〜R-21 が直ったことを確かめた |

**実機の 1 回目の後の Codex の確かめ**（レビューのファイルは無い。作業の記録の 12.8・12.9）:

| 確かめ | モデル | 結果 |
|---|---|---|
| I1 の直しと DerivedData の置き場所（12.4） | `--model gpt-5.6-sol` | A-1（`BUILD_ROOT` の下ならどこでも受けた）、A-2（重ねた書き方や似た形を拒まなかった）。12.8 で直した |
| 12.8 の直し | `--model gpt-5.6-sol` | A-1・A-2 は直った。A-3（動作を 2 つ並べると `-resultBundlePath` の確かめをすり抜ける）。動作の言葉を数える形に直した |
| A-3 の直し | `gpt-6.1-sol`（設定のまま） | **A=0**。複数の動作の 30 通りが拒まれ、xcodebuild の呼び出し 7 か所に抜け道は無かった |

Codex のプラグインが使う `codex-cli` が 0.151.0 で、設定のモデル `gpt-6.1-sol` が拒まれていた。利用者の許可で 0.164.0 に更新し、`gpt-6.1-sol` で呼べることを確かめた。それまでの Codex のレビューとは、モデルが違う。

## 5. 基準

| 対象 | シミュレーター | 実機 |
|---|---|---|
| 基準のファイル | `scripts/test_ios.baseline.iPhone_17-26.2.json` | `scripts/test_ios.baseline.iPhone_XS-18.7.2.json` |
| 機種・OS（ビルド） | iPhone 17、iOS 26.2（23C54） | iPhone XS、iOS 18.7.2（22H124） |
| 言語 | en-JP | `unknown`（下） |
| Xcode | 26.3（17C529） | 26.3（17C529） |
| 許した区分（`allowed`） | 6 つすべて | なし |
| `IosLibraryTests` | 186 | 流していない（単体テストはシミュレーターだけ） |
| `IosLibraryExampleTests` | 10 | 流していない |
| UI テスト Common | 6 | 5（M1、M2、I1a〜I1c） |
| UI テスト Dialog | 15 | 11（D1〜D10、D14） |
| UI テスト Notification | 36 | 3（N1、N21、N22） |
| UI テスト Share | 16 | 0 |
| UI テスト Clipboard | 26（25 が通り、U10b は意図した skip） | 0 |
| 合計 | 295（294 が通り、1 が意図した skip） | 19（すべて通った） |
| 流したときのコミット | `8b0f906b` | `9c69b6eb` |
| 時間 | 約 94 分 | 約 7 分 |

**シミュレーターの基準**: 失敗の無い全件の実行（`--baseline`）で保存した。結果の行（`results.jsonl`）は 296 行で、295 件のテストと、押したボタンの照合（3.7）の 1 行。押したボタンの照合も通った。時間は、結果のフォルダーのファイルの時刻から読んだ（ビルド・列挙・単体テスト 約 2 分、権限の段 約 1 分、Navigation 約 0.7 分、識別子 約 0.5 分、Dialog 約 3.4 分、Notification 約 17.8 分、Event 約 8 分、ColdStart 約 3.5 分、Share 約 3.2 分、Clipboard の既存 22 件 約 52 分、ClipboardPaste 約 1.5 分、CB2 約 0.5 分）。

この実行は、実機の 1 回目の後の I1 の直し（`1e8beb00`。I1 のテストと `SampleApp.swift`）の前のコードで流した。直した後は、26.2 で I1 を名指しして 4/4、`--feature Dialog` で 21/21（Navigation 2、識別子 4、Dialog 15）を確かめたが、全件の基準は取り直していない。2 つの基準で I1 のテストのコードが違う（8 章）。

**実機の基準**: 区分の無い 19 件だけ。区分の要る 80 件は入っていない（`allowed` が空）。端末の識別子は入れていない。実機の言語は、`devicectl device info details` の JSON に言語が無いので `unknown` になり、`Warning: the device's language is unknown, not ja (U-16)` が出る（警告だけで止めない）。

## 6. 実機の 3 回

どの回も、`--dry-run`（`--device-allow` なし）で 19 件を選び 80 件を除いた一覧を利用者に見せ、許可を得て `--approved` で流した。呼び出しは 4 回（Navigation、識別子、Dialog、Notification）。実機の UDID はどこにも書いていない。

| 回 | コミット | 結果 | 落ちたもの | 原因 | 扱い |
|---|---|---|---|---|---|
| 1 | `8b0f906b` | 16/19 | I1a〜I1c | ナビゲーションバーの戻るボタンの identifier が、iOS 18.7.2 では空だった（26.2 では `BackButton`）。I1 は `BackButton` だけで除いていた。サンプルの不具合ではない | I1 を「`BackButton`、または identifier が空でラベルが `Main Menu`」のボタンがちょうど 1 つ、に直した。ラベルを読むため `SampleApp.swift` を変え、ハッシュを更新した。あわせて、列挙の xcresult が既定の DerivedData にできていたので、2.7 の名指しの規則を足した |
| 2 | `9c69b6eb` | 18/19 | M2 | 戻るボタンを押そうとした瞬間に、端末にシステムの何かが割り込んだ。区分の無いテストなので、監視は何も押さずにサンプルを止めた（U-8 の (b)）。何が割り込んだかは、私物の画面のラベルを記録しない決まりなので分からない | **決定（2026-10-24、利用者）: 実機で流す間は、利用者が自分で集中モードを入れ、サンプルの通知だけを許す**（設計の 6.5）。I1a〜I1c はこの回に通り、18.7.2 の戻るボタンのラベルが `Main Menu` であることを確かめた |
| 3 | `9c69b6eb` | 19/19 | なし | 集中モード、自動ロック「なし」、給電で流した。割り込みは無かった | `--baseline` で実機の基準を保存した。dry-run は `--baseline` を付けずに作ったが、許可の照合は通った |

1 回の時間は約 7〜8 分。

実機で分かったこと（設計の 8.2）:

| 項目 | 結果 |
|---|---|
| 名指しの数 | 1 回の呼び出しに最大 11 件を名指しして流せた |
| devicectl の情報と xcresult の宛先 | ランナーは、devicectl の `hardwareProperties.udid` が `--udid` と同じこと、xcresult の `deviceId` が宛先と同じことを求める。3 回とも、ここでは止まらなかった |
| 実機の言語 | devicectl の情報に無い。ほかから読む方法は確かめていない |
| `TEST_RUNNER_` の環境変数が実機のランナーに届くか | 確かめていない（区分の無いテストは印を取らないので、届かなくても結果は変わらない）。区分を許す最初の実行で確かめる |
| devicectl がハードウェアの UDID を受け付けるか | 確かめていない（`--devicectl-id` を別に受ける形のまま） |

## 7. 後始末と事故

**後始末**（実機の 3 回の後）:

- 許可の ID はすべて使用済み（台帳は 3 行）。流し直すには新しい `--dry-run` と許可が要る
- 実機の `.xcresult` とビルドの作業場所は trap で消えた。結果のフォルダーに残るのは、計画・列挙・環境・結果の JSON、シミュレーターのビルドと列挙のログ、シミュレーターの列挙の `enumerate.xcresult`（0 件）だけ
- 端末に残したのは、上書きしたサンプルとテストのランナー、Dialog の文字の入力（D8〜D10）によるキーボードの学習がありうることだけ。通知・クリップボード・Share・権限には触れていない
- xcodebuild・simctl・変異の実行の残りのプロセスは無い。シミュレーターは Shutdown
- シミュレーターには、通知の権限（許可）、登録済みの category、クリップボードのテストの文字列、Files の「このiPhone内」の写しが残っている（0c の後と同じ）
- 既定の DerivedData の、実機の 1 回目までにできた小さなフォルダー（約 336MB）と、`BUILD_ROOT` の下の古い `DerivedData-simulator` / `DerivedData-device` は消していない（消すかを利用者に尋ねる）

**事故と注意**:

| 事 | 扱い |
|---|---|
| レビュー v1 の R-6 の変異（台帳を環境変数と `$HOME` で動かせる形）を入れた写しで自己テストを流したとき、自己テストが本物の台帳に、作り物の UDID の ID を 3 行書いた | この作業だけで作ったものなので、フォルダーごと消した。変異の仕組みを、写しの台帳の場所と `HOME` を一時フォルダーに替えてから流す形にし、流す前と後に本物の台帳を比べる。その後の変異の実行では、本物の台帳は変わっていない |
| 最初の変異の実行で、写しが git のリポジトリでないために preflight のテストが落ち、`&` で起動したために SIGINT が無視されてシグナルのテストが落ちた | 両方を直し、変異なしの基準を足して流し直した |
| 残っていた待ちのループ | 段階 0a のときに止めた（この作業の依頼で伝えられたこと。artifact の記録には無い）。0c・0d の作業の記録では、各作業の後に xcodebuild・simctl・待ちのループの残りが無いことを確かめている |
| 実機の 2 回目の M2（私物の端末への割り込み） | 監視は何も押さずに止めた（安全の側）。集中モードの決定（6 章） |

## 8. 残り

| 項目 | 内容 |
|---|---|
| 実機の区分の要るテスト | 80 件。区分ごとに一覧を見せて許可を得る。前提（集中モード、`clipboard` は Handoff を切る、`credentials` はログインの保存のダイアログを先に手で確かめる）は 0c の結果の 7 章 |
| ~~`UnityIosPluginTests` の 83 件~~ | 済み（2026-10-24。83 件すべてが成功。`results/2026-10-24-ios-c-abi-bridge-tests-before-0e.md`） |
| ~~`SampleApp.swift` の再レビュー~~ | 済み。Codex（`gpt-5.6-sol`）に変わった所を見てもらい、問題が無いことを確かめた（読むだけで何も押さない、ラベルを失敗の文に書かない、ハッシュが一致する）。設計書の 8.7 の「まだ」を直した |
| シミュレーターの基準の取り直し | 今の基準は I1 の直しの前のコードで流した（5 章）。直した後も I1 は通り、結果は変わらない見込みなので、**次の区切り（0g の後）の全件の実行で取り直す**（2026-10-24 に決めた） |
| A-3 の変異 | 変異の一覧にまだ足していない |
| README 7 章の全体の時間 | シミュレーターの全件は約 94 分。README 7 章の「0d で測り、ここに書く」にまだ書いていない |
| 実機の言語の読み方 | devicectl に無い。ほかの方法を確かめていない |
| レビュー v2 の区分 C の残り | 割り込みの後も `tearDownAfterGate` のアプリの中の片付けが動く、ロックのファイルそのものの symlink、実機のキーボードの先頭の大文字で N29・N32 の欄の照合が外れうる（押さずに失敗する）、CB1 で出どころが「サンプル自身」でも許すのは必要より広い |
| 既定の DerivedData と古いフォルダー | 消すかを利用者に尋ねる（7 章） |
