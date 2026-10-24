# 段階 0d の作業の記録（ランナー）

- 記録日: 2026-10-24
- 段階: 0d（`scripts/test_ios.sh`。UI テストの設計書の 6.3）
- 状態: ランナーと自己テストができた。全件の実行と基準の記録（2 つの環境）はこれから
- 環境: シミュレーター（iPhone 17、iOS 26.2、en-JP、Xcode 26.3）だけ。**実機には触れていない**（実機の UDID は使わず、実機の扱いは `simctl list` に無い作り物の UDID で確かめた）

## 1. 作ったもの

| ファイル | 中身 |
|---|---|
| `scripts/test_ios.sh` | 薄い殻。xcodebuild・simctl・devicectl を呼ぶだけで、決めることは下の Python に渡す。実機に触れる関数（`device_xcodebuild`、`device_devicectl`）は、許可の消費と片付けの trap の登録の両方が済むまで呼んでも止まる |
| `scripts/ios_ui_runner.py` | 純粋な関数と小さな CLI。宛先の判定、列挙の読み取りと正規化、宣言の表との照合、クラスの下限、`ClipboardUITests` の固定、閉じた形のソースの規則、信頼する部分のハッシュ、選び方、名指し、許可の一覧と台帳、実機のバイナリの一覧、結果の読み方と skip の分類、押したボタンの照合、基準との比べ方 |
| `scripts/tests/test_ios_ui_runner.py` | 自己テスト 93 件。7 章のランナーの行の変異を、関数を直接壊して確かめる |
| `scripts/tests/fixtures/ios_ui_runner/` | 実物の出力の写し（列挙の JSON、`otool -ov` / `-l`、xcresult の JSON、添付の manifest、simctl の一覧。パスは置き換えた） |
| `ios/.gitignore` | `IosLibraryExample/build/`（ランナーの DerivedData と結果のフォルダー） |
| `scripts/README.md` | `test_ios.sh` の行 |

## 2. 信頼する部分のハッシュ（0c で残した固定）

置き場所は **`scripts/ios_ui_runner.py` の `TRUSTED_FILES`（ファイルごと）と `FROZEN_CLIPBOARD_SHA256`**（設計の「ランナーに固定する」）。0c の終わりのコミット `8fdb429d` の中身で固定した（今の作業ツリーも同じ）。今の値は `python3 scripts/ios_ui_runner.py hashes --tests-dir ios/IosLibraryExample/IosLibraryExampleUITests` で出る。更新は、別のモデルのレビューを通した後に、この 2 つを書き換える（設計の 2 章の冒頭）。

| ファイル | sha256 |
|---|---|
| `Support/SampleUITestCase.swift` | `1390c36898633873b021346b3821e0fa97510dc4870c4fb13605c8fee7012446` |
| `Support/SampleApp.swift` | `d577bc11105b6a49c9a464c2a0e59c22a9c9e91bf4ae43151f7ff9a97fed749b` |
| `Support/Springboard.swift` | `a6f844a5875397f3f983eba151baa9a429cab38eaf3ec63552de1b6c4fcb004c` |
| `Support/ShareSheet.swift` | `acbd1a912c9a9489f37847036c5642c72492190cef8abbafa3ba588e7f38b6a8` |
| `Support/RunnerPasteboard.swift` | `003e15590840c3c174f0b181dbacca06b661b476dea0898d7456a3688e4a9bbc` |
| `Support/UnexpectedAlertGuard.swift` | `5f94e7b007e037cd9ca1393a512332acb3436a9ff2a19cfcaefcf91ea28c6bfa` |
| `Support/NotificationCleanup.swift` | `6aef2d195de77263e9631c151fe84e8051169ac72fded82766db7559bebe9c22` |
| `Support/SystemLabels.swift` | `cfce7ecbd8b4a615c6097fb6a3af850dc9d152750be4213cf01498410b1ca3d5` |
| `IosLibraryExampleUITests.swift`（`ClipboardUITests`、固定） | `4612943da3ec0e32562d86d07d7d134521f1db5fed42e7543db742a5b8006cf3` |

信頼する部分の中身は、固定の前に別のモデルのレビューを通していない（0c の実装のまま固定した）。

## 3. 8.2 の項目の実測（シミュレーターと、署名しない `generic/platform=iOS` のビルドだけ）

| 項目 | 結果 |
|---|---|
| テキストの添付の取り出し | `xcrun xcresulttool export attachments --path <bundle> --output-path <dir>` で取れる。`manifest.json` の `suggestedHumanReadableName` は `ntk-button-coverage-v1_0_<UUID>.json` に変わるので、ランナーはこの形まで受ける |
| 実機のビルドの `otool -ov` | `generic/platform=iOS`（arm64、`CODE_SIGNING_ALLOWED=NO`。端末は要らない）で組んだ `.xctest` で読めた。**テストのバンドルでは、相対のメソッドの一覧の `name` に selector が出ず、`__objc_selrefs` の中の番地だけが出る**。ランナーは `otool -l` で `__objc_selrefs` の先頭の番地を読み、番地から selector を引く。97 件がシミュレーターの列挙とちょうど一致した（M1、M2 を足した後に組み直して 99 件で一致。9 章） |
| `throws` でないテスト、`@MainActor`、継承 | swiftc で組んだ小さな XCTest の束で確かめた。`func testPlain()` は `testPlain`、`throws` は `testThrowsAndReturnError:`、`@MainActor` も同じ形。子のクラスは親のテストも XCTest に走らされるので、ランナーは親のテストも子の名前で数える。ivar の名前（基底の `testSession`）はテストに数えない |
| 閉じた形のソースの規則の読み方 | swift-syntax は使わず、Python で字句に分けて（コメントと文字列を外し、文字列の補間の中のコードは残す）字句の並びで照らす（利用者の決定） |
| 信頼する部分のハッシュの形 | ファイルごと（変わったファイルを名指しできる） |
| 許可の台帳 | `~/Library/Application Support/native-toolkit/test_ios-approvals.log`（設計の例のまま）。`approve` が ID を書いた後に止まっても ID は消費済みのまま |
| 列挙は端末を起動するか | シミュレーターは列挙の前後とも Shutdown のまま（0a と同じ） |
| 実機の宛先の xcresult | `get test-results tests` に `devices[].deviceId` がある。ランナーは、結果が名指しした宛先で走ったことも照らす |

確かめていない（実機が要る）: `TEST_RUNNER_` の環境変数が実機のランナーに届くか、devicectl がハードウェアの UDID を受け付けるか、名指しの数の上限、`devicectl device info details` の JSON の形（ランナーは `hardwareProperties.udid` が `--udid` と同じことを求める）。

## 4. 確かめたこと（シミュレーターだけ）

| 確かめ | 結果 |
|---|---|
| 自己テスト | 93 件が通った（`scripts/tests` 全体は 301 件が通った） |
| 変異（ランナーの写しで 1 つずつ壊して自己テストを流す） | 32 個とも捕まった（7 章のランナーの行と、結果の読み方・片付け・基準の比べ方） |
| 今の木の閉じた形の規則 | 通った（`ClipboardID` の範囲は 16〜24 行、凍結ファイルの `XCUIApplication` 2 回・`XCUIDevice` 1 回） |
| `--dry-run`（シミュレーター） | 約 53 秒。97 件、呼び出し 11 回（権限 2、クラス 8、CB2 1）。M1、M2 を足した後は 99 件、呼び出し 12 回（9 章） |
| `--dry-run`（`simctl list` に無い作り物の UDID、`--device-allow systemui`） | 実機として扱い、シミュレーターの列挙から 48 件を選び 49 件を除いた。許可の一覧（ランダムな ID）を書いて止まった。xcodebuild と xcrun を記録する差し替えで、呼ばれたのは `simctl list`・`-version`・シミュレーターの build-for-testing と列挙だけ（devicectl と実機の宛先は 0 回） |
| 消費済みの許可で流す（作り物の UDID、一時の台帳） | 列挙の後、`approve` で止まった。devicectl と実機の宛先は 0 回（呼ばれたら止める差し替えも置いた） |
| `--feature Dialog` | 約 330 秒。IdentifierInventoryUITests 4/4、DialogUITests 15/15。名指しの照合と結果の読み方が通った |
| 基準との比べ方（一時の基準のファイル） | 同じ結果なら合格（`outside this run=2` は機能の外）。範囲内の通っていたテストが無いと失敗、`failed -> passed` は表示だけ。`--feature` の実行で `--baseline` は断った |
| シェルでの変異 | テストのファイルに `#if` を足すと規則で止まり（ビルドの前）、宣言の表から D1 を消すと列挙の照合で止まった。どちらも戻した |

## 5. 設計とずれたこと

1. `NavigationUITests`（M1、M2）は 0c で書かれていなかったので、0d で足した（9 章）。全体は設計の 3.6 のとおり 99 件。共通（Common）は `NavigationUITests` と `IdentifierInventoryUITests`
2. 実機の環境（devicectl）は端末に触れるので、段 0 ではなく、許可を消費して trap を登録した後に読む。実機の結果のフォルダーは `<日時>-device`
3. 単体テストは、`IosLibraryExampleTests` が `.xctestrun` を使うので、シミュレーターのビルドの後に流す（段 1 と 2 の順を入れ替えた）
4. `otool -ov` だけでは selector が読めないので、`otool -l` も読む（3 章）
5. 閉じた形の規則は、設計の表に加えて、属性（`@MainActor`、`@discardableResult`、`@escaping`、`@Sendable`、`@autoclosure`、`@unknown` だけ）と `#` の名前（マクロを含む）も許すものだけにした。テストのファイルでは `extension`・`protocol`・`actor`・`deinit`・`required`・`convenience`・`dynamic` を禁じた。テストのフォルダーには `.swift` と `Support/DeviceRequirements.json` のほかを置けない。`Support/` に信頼する部分の一覧に無いファイルを足すと、テストのファイルと同じ規則がかかる
6. 自己テストのために、許可の台帳の場所（`NTK_TEST_IOS_APPROVAL_LEDGER`）と基準のフォルダー（`NTK_TEST_IOS_BASELINE_DIR`）を環境変数で変えられる。`test_ios.sh` は `NTK_TEST_IOS_SOURCE_ONLY=1` で関数だけを読み込める
7. シミュレーターは、始めに Shutdown だったら終わりに Shutdown に戻す（権限の段で起動するため）
8. 基準と比べる範囲: `--feature` の外、実機で区分で除いたもの、単体テストを流していないときの単体テストは失敗にしない。消えたクラスのテストは全件の実行のときだけ範囲に入る

## 6. 見積もり

全件（シミュレーター）: 0c の実測の和で約 95〜100 分（Clipboard の既存 22 件が約 52 分、Notification の 3 クラスが約 29 分、Share 約 3 分、Dialog 約 3.5 分、そのほか約 3 分、単体テスト約 1.5 分、ビルドと列挙と呼び出しごとの起動で約 5 分）。実機は許す区分で変わる。

## 7. 後始末

xcodebuild・simctl・待ちのループで残っているものは無い。シミュレーターは Shutdown。クリップボードと通知の権限は 0c の後のまま（Dialog と識別子のテストだけを流した）。実機の許可の台帳（`~/Library/Application Support/native-toolkit/`）は作っていない。

## 8. 残り

- 全件の実行と基準の記録（シミュレーター、iPhone 17 / 26.2）
- 実機: 6.5 の確認と利用者の許可の後に、`--dry-run` の一覧を見せて許可を得てから流す（このときに 3 章の確かめていないことを確かめる）
- README 7 章の全体の時間（全件の実行で測る）

## 9. `NavigationUITests`（M1、M2）を足したこと

0c で書かれていなかった設計の 3.1 の M1、M2 を足した。信頼する部分（`Support/` のハッシュで固定したファイル）は変えていない（`SampleApp` の今の口で足りた）。

| 所 | 中身 |
|---|---|
| `IosLibraryExampleUITests/NavigationUITests.swift` | `final class NavigationUITests: SampleUITestCase`。上書きは `setUpAfterGate()` / `tearDownAfterGate()` だけ。M1: メニューのカードが 4 つ出ていることを確かめ、Dialog・Notification・Share を順に開いて結果の行（初めの文）を確かめ、戻る。戻った後は閉じた画面の結果の行が消えるまで待ち、カードが 4 つまた出ていることを確かめる（Clipboard の画面は開かない）。M2: Dialog で ShowAlert → OK（回数 `completion=1,callback=1` と結果の行の全文）→ 戻る → 開き直すと `Result will be displayed here` と `completion=0,callback=0`。Notification で `HasPermission`（`updates=1`）→ 戻る → 開き直すと `Result will be displayed here` と `updates=0` |
| `Support/DeviceRequirements.json` | 2 件とも `[]`（`HasPermission` は権限の状態を読むだけ。設計 6.1 の `SampleApp` の行で印の要らないボタン） |
| `scripts/ios_ui_runner.py` | `UI_CLASSES` の先頭に `("NavigationUITests", "Common")`（設計 3.1 の表の順）。どの `--feature` でも流れる |
| `scripts/tests/fixtures/ios_ui_runner/` | `enumeration.json` を今の木の列挙の出力に、`otool-ov-device.txt` と `otool-l-device.txt` を署名しない `generic/platform=iOS` のビルドの出力に取り替えた（どちらも端末には触れていない） |
| `scripts/tests/test_ios_ui_runner.py` | 97 件を前提にした 4 か所を 99 件に、`--feature Dialog` のクラスの集合と呼び出しの順の期待に `NavigationUITests` を足した |

M2 の `HasPermission` の結果の行は、`[hasPermission] true` と `false` のどちらかの全文と比べる。区分の無いテストは権限が許可されていることを前提にしない（設計 3.0 の前提は通知のテストのもの）ので、どちらでも「結果の行が変わってから、開き直すと初めに戻る」ことは確かめられる。

確かめたこと（シミュレーター iPhone 17 / iOS 26.2 だけ。実機には触れていない）:

| 確かめ | 結果 |
|---|---|
| 閉じた形の規則（`check-sources`） | 通った |
| 信頼する部分のハッシュ | 変わっていない |
| 自己テスト（`python3 -m unittest scripts/tests/test_ios_ui_runner.py`） | 93 件が通った |
| `--dry-run` | 約 40 秒。99 件が宣言の表と一致、99 件を選び 0 件を除いた、呼び出し 12 回（権限 2、クラス 9、CB2 1） |
| `NavigationUITests` を 3 回（`xcodebuild test-without-building -only-testing:IosLibraryExampleUITests/NavigationUITests`） | 3 回とも 2/2 が通った（M1 約 17 秒、M2 約 23 秒）。押したボタンの添付は M1 が `[]`、M2 が `dialog.button.showAlert` と `notification.button.hasPermission` |

後始末: xcodebuild の残りは無い。シミュレーターは Shutdown。

## 10. レビュー v1 の対応（`reviews/2026-10-24-ios-c-abi-stage0d-review-v1.md`）

シミュレーター（iPhone 17 / iOS 26.2）、`simctl list` に無い作り物の UDID の dry-run、差し替えたコマンドだけで確かめた。**実機には触れていない。** 凍結の `IosLibraryExampleUITests.swift` は変えていない。

### 10.1 直したこと

| ID | 直したこと |
|---|---|
| R-1 | `Springboard.expandedScope()` を `throws` にし、根がちょうど 1 つでなければ押さない（springboard 全体に戻る道を消した）。返信の欄と Send は根の外の別の window にあった（`probes/stage0d/Stage0dProbeTests.swift` で測った。どの要素にも identifier が無い）ので、根がちょうど 1 つあることを確かめたうえで、サンプルの placeholder（`Type a message`）か入力した文字を持つ欄の window がちょうど 1 つのときだけ、その中で欄と Send を取る。`actionCount` も `throws`（N24 の呼び出しを直した） |
| R-2 | `tapAlertButton` は、ただ 1 つのアラートのラベルに `“IosLibraryExample”` があることを確かめ、その名前を持つアラートの中のボタンを取り、押す直前にもアラートが 1 つであることを確かめる |
| R-3 | 判定を純粋な関数 `Springboard.pasteAlertNamesKnownSource(_:)` にした。ラベルの `“…”` の引用を取り出し（`quotedNames(in:)`。対にならなければ不可）、引用がちょうど 2 つで、1 つ目がサンプル（`IosLibraryExample`）、2 つ目（出どころ）がランナー（`IosLibraryExampleUITests-Runner`）かサンプル自身のときだけ、CB1 は Allow Paste を押す（`tapPasteAlertFromKnownSource`）。en は 0c の `“IosLibraryExample” would like to paste from “IosLibraryExampleUITests-Runner”`、ja は 0a 7.2 の実機の `“IosLibraryExample”に“IosLibraryExample”からペーストしようとしています` で、どちらもアプリが先、出どころが後。Mac の名前などほかの出どころ、引用が 1 つや 3 つ、対にならない引用では押さずに失敗する。押す直前にも、アラートが 1 つでラベルが同じ判定を通ることを確かめる。判定は自己テスト（`PasteAlert`）で Python に写して en / ja / Mac の名前 / 引用の数を確かめ、写した Swift の文がそのままであることも照らす（UI テストのターゲットに判定だけのテストを足すと件数と宣言の表が変わるので、外で確かめた） |
| R-4 | 実機で監視が割り込みを記録したら、tearDown の springboard の片付け（ホーム）を飛ばす |
| R-5 | `waitForNoSampleBanner` を `throws` にし、待った直後に `checkInterruption()` |
| R-6 | 台帳はアカウントのホーム（`getpwuid`）の決まった場所だけ。環境変数と `$HOME` では動かない。差し替えは `approve` の隠れた引数 `--ledger-for-self-test` だけで、`test_ios.sh` は渡さない（自己テストで確かめる） |
| R-7 | 専用のロックファイルの下で全行を `ID<TAB>時刻<TAB>udid` として照らし、壊れた行・改行の無い最後の行・symlink なら実機を拒む。書き込みは一時ファイル → fsync → rename → フォルダーの fsync |
| R-8 | 今の選び方から許可の一覧を作り直し、ID と時刻のほかを丸ごと比べる（テストの順・ID・区分、除いたもの、信頼する部分、知らないキー・欠けたキー）。時刻の形も照らす |
| R-9 | `git status --porcelain -uall -- ios` に `ios/IosLibraryExample/build/` 以外の変更があれば、`approve`（ID を消費する前）と `verify-tree` で実機を拒む。dry-run では警告を出す |
| R-10 | `sim_xcodebuild` は `platform=iOS Simulator,id=` 以外の `-destination` を 97 で拒む。静的な検査は続きの行をつないでから、実機の宛先・devicectl・素の xcodebuild を探す |
| R-11 | 結果を 1 件ずつ（結果、正規化した名前）の組で持つ。名前を読めない、繰り返し・引数・端末・構成の子を持つ形、別のバンドル、宛先の食い違い、時間切れ、summary の食い違い、読めた件数が全件と違う、を実機の即時の停止の条件にした |
| R-12 | 実機の test-without-building に `-derivedDataPath "${DEVICE_TMP}/dd-test" -collect-test-diagnostics never`（効く範囲は実機で確かめる） |
| R-13 | `exec @ARGV or die` |
| R-14 | `check-binary` で実機のバンドルの `DeviceRequirements.json` と `Info.plist` も照らす |
| R-15 | 実機で選んだテストが 0 件の計画を拒む |
| R-16 | 下の 10.2 |
| R-17 | `--name-each-test`（シミュレーターでも 1 件ずつ名指し）。`--feature Notification --name-each-test` を通しで流した（10.3） |

ほか: 同じ秒に 2 回流すと結果のフォルダーが重なるのを直した。xcresult の失敗の文を結果に残すようにした（これまでは `failed` だけ）。

### 10.2 自己テストと変異

- 自己テストは 120 件（93 件から 27 件増えた。R-3 の直し直しの 4 件を含む）。`scripts/tests` 全体は 328 件。すべて通った
- 足したもの: `cmd_*` を subprocess で呼ぶテスト（approve・record・may-uninstall・verify-tree（一時の git リポジトリ）・preflight・summary・check-binary）、R-6〜R-15 と R-17 のテスト、`test_ios.sh` を最後まで流す 3 本（xcodebuild・xcrun・otool・git を記録するだけの差し替え。①実機の dry-run は devicectl も実機の宛先も呼ばない、②使用済みの許可は devicectl の前に止まる、③読めない名前の結果で exit 3 になり実機の実行全体が止まり、一時フォルダーが消え、devicectl を呼んだ時点で ID が台帳にある）
- 変異（ランナーの写しで 1 つずつ壊して自己テストを流す）: 変異なしの基準は通り、61 個とも捕まった（前の 32 個、レビューで通ってしまった 11 個、R-6〜R-15 と R-17 の 18 個）。最初の実行では、写しが git のリポジトリでないために preflight のテストが変異と関係なく落ち、また `&` で起動したため SIGINT が無視されてシグナルのテストが落ちていたので、両方を直して変異なしの基準を足してから流し直した
- 注意: R-6 の変異（台帳を環境変数・`$HOME` で動かせる形）を入れた写しでは、自己テストが本物の台帳（`~/Library/Application Support/native-toolkit/`）に作り物の UDID の ID を 3 行書いた。作ったのはこの作業だけなので、フォルダーごと消した。変異の実行は、写しの台帳の場所と `HOME` を一時フォルダーに替えてから流すようにし、R-6 の 2 つの変異が捕まり、本物の台帳が作られないことを確かめた

### 10.3 シミュレーターで流したもの

| 実行 | 結果 |
|---|---|
| `--feature Notification --name-each-test`（1 回目） | 40/42。N29 と N32 が「Send did not appear」で落ちた（入力すると欄の placeholder が消え、window の照合が外れた）。欄の値（入力した文字）でも照らすように直した |
| N29、N32、CB1、CB3、CB4 を名指し、CB2 を単独 | すべて通った |
| `--feature Notification --name-each-test`（2 回目） | 42/42（約 33 分。権限の段 2 件、Navigation 2、Inventory 4、Notification 23、Event 7、ColdStart 4。どれも 1 件ずつ名指し） |
| R-3 の直し直しの後に CB1 と CB2（単独） | どちらも通った（26.2 のシミュレーター、en。出どころはランナー） |
| 作り物の UDID の dry-run（`--device-allow systemui`） | 50 件を選び 49 件を除いた。差し替えの記録で devicectl と実機の宛先は 0 回。`ios/` のコミットしていない変更を警告した |

### 10.4 新しいハッシュ（2 章の値を置き換える）

| ファイル | sha256 |
|---|---|
| `Support/SampleUITestCase.swift` | `f9ac9bc5b9aac62afae0499e27bc1ab7b64f5e7361229402b8d34591eb461499` |
| `Support/Springboard.swift` | `b4b0d4e37c1137c7feab7fc4c8cf07c2860a710f12c078f8419c20cdba14530a` |
| `Support/NotificationCleanup.swift` | `64a33263710150a505c14adcfeaf0144b8a43172194878ab652182284595f384` |
| `Support/SystemLabels.swift` | `160ac7dba6f46cb0eedec72ff53d90a8db43e3060e904e495acd5318d887b264` |
| `Support/SampleApp.swift`、`ShareSheet.swift`、`RunnerPasteboard.swift`、`UnexpectedAlertGuard.swift`、凍結の `IosLibraryExampleUITests.swift` | 変わらない |

信頼する部分を変えたので、設計の 2 章のとおり、直した所の再レビュー（別のモデル）を通してから実機で流す。

後始末: xcodebuild・simctl・変異の実行の残りは無い。シミュレーターは Shutdown。作り物の UDID の dry-run の結果のフォルダーは消した。実機の台帳は作っていない。

## 11. レビュー v2 の対応（`reviews/2026-10-24-ios-c-abi-stage0d-review-v2.md`）

シミュレーター（iPhone 17 / iOS 26.2）、差し替えたコマンド、ランナーの写しだけで確かめた。**実機には触れていない。** 凍結の `IosLibraryExampleUITests.swift` は変えていない。

### 11.1 直したこと

| ID | 直したこと |
|---|---|
| R-18 | 実機では `scripts/ios_ui_runner.py` と `scripts/test_ios.sh` もコミット済み（追跡されていて、作業ツリーの差分が無い）で、計画を作ったときの SHA-256（計画と許可の一覧の `runnerFiles`）と同じであることを求める。`approve`（ID を消費する前）と、実機のどの呼び出しの前にも照らす。dry-run では警告だけを出す（今は未コミットなので、実機の前に利用者にコミットを確かめてもらう前提） |
| R-19 | 許可の一覧に計画全体の正規化した SHA-256（`planDigest`）を入れた。許可を使った後は、計画を一時フォルダーの読むだけの写し（`plan.approved.json`、0444）に替え、それだけを使う。`device_guard` は、実機のどの呼び出し（devicectl、xcodebuild）の前にも `device-gate` を呼び、計画の digest、ID が台帳にあること、ランナーのファイル、木（HEAD・テストのフォルダー・`ios/` の差分）を照らし、外れれば 97 で止まる |
| R-20 | xcresult の Test Case の子は `Failure Message` だけを許す閉じた一覧にした。ほかの種類（名前を問わない）があれば、結果を信じずに止める |
| R-21 | サンプルの返信の placeholder を `Type a message` から `IosLibraryExample reply` に変えた（`NotificationSampleView.swift` の 1 か所だけ。0c の「サンプルは変えない」の例外として、0b の結果の 5 章と設計書の 8.7 に書いた）。`SystemLabels.sampleReplyPlaceholder` を足した。`expandedScope(title:body:)` は、根がちょうど 1 つで、その広げた表示がサンプルの題と本文であることも確かめる。`tapAction`・`waitForActions`・`actionCount`・`sendReply` は題と本文を受け、押す直前・入力の前・Send の前に根と返信の window を取り直す。window はサンプルの placeholder の欄（入力の後は入力した文字の欄）をちょうど 1 つ持つものに限る |
| C（`NTK_TEST_IOS_SOURCE_ONLY`） | 読み込まれた（source された）ときだけ効く。直接実行で値が残っていればエラー（exit 2） |
| C（偽の xcrun） | ShellGuards の差し替えに偽の xcrun を足し、devicectl の本物に届かない |
| C（変異の仕組み） | `scripts/tests/ios_ui_runner_mutations.py` をリポジトリに置いた。写しには、スクリプト・UI テストのフォルダー・サンプルのソース・pbxproj を入れ、写しのランナーの台帳のホームを写しのフォルダーに替え（替えられなければ止まる）、`HOME` も写しにする。流す前と後に本物の台帳のフォルダーを比べる。単体テストではない |

ほか: `set -u` の下で `PLAN` と `APPROVED` を先に宣言した（関数だけを読み込む自己テストで、ガードが未定義の変数で落ちていた）。

### 11.2 自己テストと変異

- 自己テストは 129 件（v1 の後の 120 件から 9 件増えた）。`scripts/tests` 全体は 337 件。すべて通った
- 変異（`python3 scripts/tests/ios_ui_runner_mutations.py`）: 変異なしの基準は通り、75 個とも捕まった（前の 61 個と、R-18 が 3、R-19 が 4、R-20 が 1、R-21 が 3、R-3 が 1、C が 2）。最初に流したとき、「ガードを外す」変異が生き残った（R-19 のゲートが代わりに拒むので、承認と trap の印の確かめを外しても自己テストが気づかなかった）。ゲートを通す形にして印だけで拒むことを確かめるテストに直し、流し直した。R-21 の Swift の変異は、信頼する部分のハッシュの照合と、写した文の照らし合わせで捕まる
- 本物の台帳（`~/Library/Application Support/native-toolkit/`）は、変異を流す前も後も無い

### 11.4 新しいハッシュ（10.4 の値を置き換える）

| ファイル | sha256 |
|---|---|
| `Support/Springboard.swift` | `427a3b7bddb7aef5f9604c3bc41df8e2516b1989fa872b62cbfddf5549a05be3` |
| `Support/SystemLabels.swift` | `f8d3e5807ede8eac4a54384338f4307f2d42a05908cf441c86d3b70a9548c0e7` |
| ほかの 6 つと凍結の `IosLibraryExampleUITests.swift` | 10.4 と同じ |

後始末: xcodebuild・simctl・変異の実行の残りは無い。シミュレーターは Shutdown。実機の台帳は作っていない。

### 11.3 シミュレーターで流したもの

| 実行 | 結果 |
|---|---|
| `NotificationEventUITests`（7）、`NotificationColdStartUITests`（4）、CB1 を 1 回の xcodebuild で | 11/12。N32 が「reply text view of the sample did not appear」で落ちた。同じ実行の後の N29 は通った |
| N32 だけを 2 回 | 2 回とも通った |
| `NotificationColdStartUITests`（4）と N29 | 5/5 |

N32 の 1 回目は、placeholder を変えた後の最初のコールドスタートで、OS に残っていた前の category（`Type a message`）で返信の画面が出たためと見ている（N32 は RegisterCategory の直後にアプリを止めるので、登録の `Task` が終わる前に止まりうる。確かめてはいない）。そのときは押さずに失敗する（安全の側）。実機で最初に流すときも 1 回落ちうる。
