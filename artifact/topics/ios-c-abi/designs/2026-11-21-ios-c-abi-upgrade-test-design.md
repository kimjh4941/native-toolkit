# 更新のテストの設計（1.13.0 のサンプルから 2.0.0 へ）

- 日付: 2026-11-21
- 状態: **v3**。v1 のレビュー（`reviews/2026-11-21-ios-c-abi-upgrade-test-design-review-v1.md`。C-n・K-n）と v2 のレビュー（同 `-review-v2.md`。C2-n・K2-n）の指摘を入れた。v2 で測っていなかった前提（上書きの後の位置の条件と許可、印のファイル、前面での展開と 1.x の入力欄での返信）は v3 の前に測った（8 章）。利用者の指示（2026-11-21「推奨案でいい」）で推奨案のまま実装に進み、実装のレビューで設計との一致も見てもらう
- 対象: README 7 章の「更新のテスト」と 9 章の DoD「1.x（1.13.0 のサンプル）から 2.0.0 への更新のテストで、予約した通知・category・表示中の通知が壊れない」。UI テストの設計書 8.4 で「1b の後に別に設計する」とした
- 期待値の元: Swift の API の設計書 S-P17 と 8.5.6（1.x の通知には何もしない。予約・表示中のものは `identifier` で取り消せ、一覧に印の無い userInfo のまま出る）と 5.12.3（印の無い通知と応答は、前の delegate が無ければライブラリが扱う）。README D-12（サンプルのアプリの bundle id は変えない）

---

## 1. 目的と範囲

1.x の `IosLibrary`（1.3.0）が OS に残したもの（予約した要求、表示中の通知、登録した category、通知の権限）が、同じアプリを 2.0.0 に上書きした後も壊れずに扱えることを確かめる。

| 含む | 含まない（理由） |
|---|---|
| シミュレーター（iPhone 17 Pro / iOS 26.2）での自動のテスト | 実機（アプリの削除と上書き、位置の許可と位置の変更は「危ない操作」で、毎回の許可が要る。D-21。U-1） |
| 予約の一覧・取り消し、表示中の通知の一覧・削除、更新の後の発火（背後と前面）、タップ（既定の動作）、文字入力のアクション、category と権限の残り | 更新の**前**に表示された 1.x の通知を、更新の**後**に通知センターから操作すること（通知センターの操作は自動化の外。UI テストの設計書 2.1。応答の経路は、更新の後に発火した印の無い通知と同じ `didReceive` なので、組 B・C で見る） |
| 一覧の userInfo がそのまま返ること（単体テスト。U-8） | ホストが自分の delegate を入れている場合（サンプルは標準の形では入れない。5.12.3 のその枝は 1b の単体テストが見る）。`customDismissAction` の dismiss の応答（1.x の category が持つが、2.0.0 の扱いは 1b の単体テストの範囲） |
| 1.13.0 のタグ（`b507c42c`）のサンプル → 今のサンプル | 1.13.0 より前の版。C ABI（更新で変わるのは OS に残ったもので、C ABI は Swift の API を呼ぶだけ） |

## 2. 決めたこと

| ID | 内容 | 決定 | 理由 |
|---|---|---|---|
| U-1 | 流す環境 | **シミュレーターだけ** | 回ごとにアプリを消し、位置の許可と位置を変える。実機では毎回の許可が要る。更新で変わるのは OS に残ったデータの読み方で、シミュレーターと実機で違う理由が無い |
| U-2 | 1.x のアプリの動かし方 | **今の UI テストの target を使い、前半だけ `.xctestrun` を写し（写しは元と同じフォルダに置く。`__TESTROOT__` が変わらないように）、UI テストの target の `UITargetAppPath`・`DependentProductPaths` の中のアプリ・`UITargetAppEnvironmentVariables` の framework の探し先（`DYLD_FRAMEWORK_PATH`・`DYLD_LIBRARY_PATH`・`__XPC_DYLD_FRAMEWORK_PATH`・`__XPC_DYLD_LIBRARY_PATH`・`__XCODE_BUILT_PRODUCTS_DIR_PATHS`）を 1.x の組み立ての置き場（絶対パス）に替え、`test-without-building` で流す**（C-1） | bundle id が同じなので `XCUIApplication()` がそのまま 1.x のアプリを指す。探し先を替えないと、1.x のアプリが今の組み立ての `IosLibrary`（2.0.0）を読む（8 章）。後半は元の `.xctestrun` で流すと、`xcodebuild` が 2.0.0 のアプリを上から入れる（消さない）ので、それが「更新」になる |
| U-3 | 1.x のサンプルの組み方 | **`git worktree` でタグ `1.13.0` を作業用のフォルダに出し、その木のワークスペースからサンプルをシミュレーター向けに組む**（Debug。成果物は作業用のフォルダの中だけ） | 1.13.0 の `IosLibrary` 1.3.0 のソースから組むので、出した版と同じコード。リポジトリの木を変えない |
| U-4 | 入った版の確かめ | **(1) スクリプトが写しの `.xctestrun` を読み、UI テストの target の替えた鍵に `__TESTROOT__` が 1 つも残っていないことを確かめる（K2-8）。(2) 前半の後に `IosLibrary.framework` の `CFBundleIdentifier` が `ios.library.IosLibrary`（版 1.3.0）、後半の後に `com.jonghyunkim.nativetoolkit.IosLibrary`（2.0.0）であることを確かめる。(3) 前半のテストは、1.x の通知の画面を開いた後で、2.0.0 にしか無い識別子（`notification.` で始まるもの）が 0 個であることを確かめる**（K-1） | 差し替えが効かずに 2.0.0 → 2.0.0 になると、文字で押す前半も 2.0.0 で動き、全部通ってしまう。(2) はアプリの中の framework を見るだけで、実際に読まれたものは (1) で守る |
| U-5 | 発火のさせ方 | **予約は位置の条件（1.x の `ScheduleLocation(Tokyo Station, onEntry)`）。前半の前に `simctl privacy grant location <bundle id>` で位置の許可を与え、位置を大阪に置く。後半のテストは用意ができたら、スクリプトが `TEST_RUNNER_NTK_UPGRADE_SIGNAL` で渡したファイルに自分の段の名前（`UB2` など）を書く。スクリプトは後半の `xcodebuild` を背後で始め、そのファイルに段の名前が書かれるのを最長 180 秒待ち、来たら位置を東京駅へ動かす。来る前に `xcodebuild` が終わった、または 180 秒を過ぎたら、`xcodebuild` を止めて FAIL**（K-2、C-3、C2-1、K2-4） | 1.x のカレンダーの予約は押した 60 秒後ちょうどに発火し、間に後半の準備が入るので間に合わない。位置の条件なら発火の時刻をスクリプトが決められる。シミュレーターのプロセスは Mac のファイルを書けるので、出力のバッファに頼らない（8 章で、書いてから約 1 秒で見えた） |
| U-6 | 組の分け方 | **3 つの組（A・B・C）。組ごとにアプリを消し、位置の許可を与え直してから始める。前半が落ちたら、その組の後半は流さずに FAIL** | 1.x のサンプルは予約の ID が 1 つ（`scheduled-notification`）で、予約のボタンは互いに置き換える。組を分けると、前の組の残りが次の組の期待値を変えない |
| U-7 | ランナーへの組み込み | **新しい表 `SCRIPT_ONLY_CLASSES = (("UpgradeUITests", "Notification"),)` を設ける。`check_enumeration` の既知のクラスと機能の表には含め、`select_tests` は理由 `UPGRADE_SCRIPT_ONLY` を付けて `excluded` に入れる**（シミュレーターでも）。`print_selection`・`cmd_summary` がその理由を出す。`CLASS_MINIMUMS` に `{"reinstall", "systemui"}`。`DeviceRequirements.json` に 6 つを `["reinstall", "systemui"]`、`SIMULATOR_ONLY_TESTS` にも入れる（K-3、C-2、K2-7） | `SEPARATE_CLASSES` は「普段の計画の中で別の段として流すクラス」なので混ぜない。`UI_CLASSES` に入れると、普段の実行で 6 件が skip になり、ランナーは意図しない skip を失敗にする。外した理由が計画と要約に出る |
| U-8 | 一覧の userInfo | **単体テストで見る**: 印の無い要求（1.x の形）を偽の通知の中心に置き、`getScheduled` と、配られた通知の変換が userInfo をそのまま返すこと（`source`・`id` が残り、2 つだけ）、`cancelScheduled` で消えることを確かめる（C-4、K-13）。**作った（`NotificationRepositoryMarkerTests` の 2 件。`removing` が `source` も消す変異で 2 件とも落ちた）** | サンプルの一覧は ID と件数しか出さない。サンプルを変えずに済む |
| U-9 | 1.x のボタンの押し方 | **ボタンの文字で押す**。押す口と結果の読み方は信頼する部分の新しいファイル `Support/LegacySampleApp.swift` に置く。テストのセッションは `SampleUITestCase` の `SystemUIToken` から受け、システムの UI を出すボタン（`RequestPermission`・`Show*`・`Schedule*`）はそのトークンを求める（今の `SampleApp` と同じ規則。K-5、K2-5） | 1.13.0 のサンプルにはアクセシビリティの識別子が無い（0b の前）。`XCUIApplication` を使うコードは信頼する部分に置く（6.1） |
| U-10 | 普段の実行での止め方 | **テストは環境変数 `NTK_UPGRADE_STEP` が自分の段の名前（`UA1` など）のときだけ動き、それ以外は `XCTSkip`**。`xcodebuild` には `TEST_RUNNER_NTK_UPGRADE_STEP` で渡す。`test_ios.sh` は `NTK_UPGRADE_STEP`・`TEST_RUNNER_NTK_UPGRADE_STEP`・`SIMCTL_CHILD_NTK_UPGRADE_STEP` と `*_NTK_UPGRADE_SIGNAL` を外して `xcodebuild` を呼ぶ（K-14、K2-9） | U-7 で普段は選ばれないが、手で `-only-testing` したときにも勝手に動かないように重ねる |
| U-11 | 信頼する部分の変更 | **`LegacySampleApp.swift`（新）、`Springboard.sendReply` に入力欄の文字を受ける引数（既定は今の `SystemLabels.sampleReplyPlaceholder`）、`SystemLabels.legacySampleReplyPlaceholder = "Type a message"`、`UnexpectedAlertGuard.pressNothingClasses` に `UpgradeUITests`**。`TRUSTED_FILES` と `DANGEROUS_NAME_FILES` に `LegacySampleApp.swift` を足し、ハッシュを取り直す。取り直しは別のモデルのレビュー（実装のレビュー）の後で、その記録を残す（K2-5、K2-6） | 1.x の入力欄で返信を送る口が要る。前半は毎回、消してから入れ直した状態で権限の確認を出して明示的に許可するので、権限のクラスと同じく見張りは何も押さないモードにする（標準のモードでは見張りが「許可しない」を押しうる） |

## 3. 組と手順

各組は「前半（1.x）」と「後半（2.0.0）」の 2 つのテスト。前半の後に、後半の `xcodebuild` が 2.0.0 を上から入れる。

**どちらの半分でも `NotificationCleanup.inApp` を呼ばない**（1.x の残りを消すので）。`SampleUITestCase` のゲートは通すが、通知のクラスの清掃は持たない。後半は権限を**直さない**（`NotificationPrecondition.requireAuthorized` を使わず、`AuthorizationStatus` が `authorized` であることを要件にする。権限も 1.x が OS に残したものの 1 つ。K-8）。

1.x の結果の行は識別子も更新の回数も持たないので、`LegacySampleApp` は「期待した全文になるまで 0.5 秒ごとに最大 10 秒読む」。同じ文が続く段は置かない（K-12）。2.0.0 の一覧が取り消しや削除の後に変わるのを待つときも、最大 10 秒読み直す（K2-10）。

### 組 A: 予約と表示中の通知の一覧・取り消し

| 段 | テスト | 手順 | 確かめること |
|---|---|---|---|
| 前半 | `testUA1_legacySchedulesAndShows` | 通知の画面を開く → `RequestPermission` → 許可 → `ShowImmediate` → `ScheduleLocation(Tokyo Station, onEntry)` → `GetScheduled` → `GetDelivered` | 2.0.0 の識別子が 0 個。1.x の結果の行に `scheduled-notification`（予約）と `sample-notification`（表示中）が出る |
| 後半 | `testUA2_upgradedListsAndCancels` | 2.0.0 で通知の画面を開く → `AuthorizationStatus` → `GetScheduled` → `GetDelivered` → `CancelScheduledById` → `GetScheduled` → `RemoveDeliveredById` → `GetDelivered` | 権限が `authorized`。一覧に 1.x の `scheduled-notification` と `sample-notification` が出る。取り消しと削除の後は出ない（S-P17） |

### 組 B: 背後での発火とタップ（OS が出すバナー）

| 段 | テスト | 手順 | 確かめること |
|---|---|---|---|
| 前半 | `testUB1_legacySchedulesALocationNotification` | 許可 → `ScheduleLocation(Tokyo Station, onEntry)` → `GetScheduled` | 2.0.0 の識別子が 0 個。予約された |
| 後半 | `testUB2_upgradedReceivesTheTapInTheBackground` | 2.0.0 で通知の画面を開く → 状態の行を読む → `GetScheduled` → ホーム画面へ → 印のファイルに `UB2` → （スクリプトが東京駅へ）→ バナー（題 `Scheduled Location`、本文 `You arrived at Tokyo Station`）を最長 60 秒待つ → タップ | 状態の行が `install=installed`、`hostDelegate=off`。予約が一覧にある（無ければ「準備した予約が一覧に無い」で失敗し、原因は断定しない。C-6）。サンプルが前面に戻り、最後のイベントが `kind=action`、`actionId=com.apple.UNNotificationDefaultActionIdentifier`、`notificationId=scheduled-notification`、`path=hub`（K-11） |

### 組 C: 前面での発火と文字入力のアクション（`willPresent` と category の残り）

| 段 | テスト | 手順 | 確かめること |
|---|---|---|---|
| 前半 | `testUC1_legacyRegistersTheCategoryAndSchedules` | 許可 → `RegisterCategory` → `ShowTimeInterval(5s)` → ホーム画面へ → バナーを広げ、`Open`・`Delete`・`Reply` が出ることを見る → ホーム画面へ → 1.x を前面に戻す → `ScheduleLocation(Tokyo Station, onEntry)` → `GetScheduled` | 2.0.0 の識別子が 0 個。1.x の時点で category が登録されている（K-6。展開は測った経路のホーム画面で。K2-2）。予約された |
| 後半 | `testUC2_upgradedRepliesThroughTheLegacyCategoryInTheForeground` | 2.0.0 で通知の画面を開いたまま（前面）→ `GetScheduled` → 印のファイルに `UC2` → （東京駅へ）→ 前面でバナーを待つ → 長押しで広げる → `Open`・`Delete`・`Reply` を待つ → `Reply` → 入力欄の文字が `Type a message` の窓に `upgraded` を入れて `Send` | 前面でバナーが出る（印の無い通知に、前の delegate が無いので、ライブラリの `willPresent` が表示を返す。K-7）。アクションが 1.x の category のもの（入力欄の文字が `Type a message`。2.0.0 のサンプルの category は `IosLibraryExample reply`。K-10）。最後のイベントが `kind=textInput`、`actionId=reply`、`userText=upgraded`、`notificationId=scheduled-notification`、`path=hub`（K2-1: 閉じてから広げ直す手順は、閉じた通知が通知センターにしか残らず実行できないので、1 回の展開で返信まで行う。既定の動作のタップは組 B で見る） |

## 4. 判定と失敗の見分け

**スクリプトの判定**（K-4、C-2、C2-2、K2-10）: 6 つの半分それぞれについて、次をすべて満たしたときだけ PASS。

- `xcodebuild` が期限（1 回 10 分）の内に終わり、終了コードが 0
- 結果のバンドルがあり、ランナーの `summary_problems` が空、結果の形が知っているもの（`unknownShape` が無い）、実行した端末が指定の UDID
- 結果が**ちょうど 1 件で、名指しした名前と完全一致し、`Passed`**（`parse_xcresult_tests` と `ran_exactly_problems`）。skip、0 件、2 件以上、別の名前はどれも FAIL
- U-4 の版の確かめと、組 B・C は U-5 の印のファイル

読み方は、`ios_ui_runner.py` に、`record_invocation` と同じ確かめを 1 つの呼び出しに使う口（`upgrade-judge`）を足して使う。6 つが全部通って初めて PASS。

| 起きたこと | 結果 |
|---|---|
| 後半だけを流した、または前半の後にアプリを消した | 組 A は一覧が空、組 B・C は予約が一覧に無く、失敗（skip にはしない） |
| 差し替えが効かず前半にも 2.0.0 が入った、探し先を替え忘れた | 前半の識別子の確かめ、スクリプトの版と `.xctestrun` の確かめで失敗 |
| 環境変数が届かない（綴りの誤りなど） | 半分が skip になり、スクリプトが FAIL にする。組 B・C は印のファイルも来ない |
| `xcodebuild` が 0 以外で終わった（テストは `Passed` でも） | FAIL |
| 2.0.0 が 1.x の予約・表示中の通知を一覧に出さない、取り消せない、消せない | 組 A（一覧は B・C の最初の確かめでも） |
| 2.0.0 が印の無い通知の応答を捨てる | 組 B・C |
| 2.0.0 が前面で印の無い通知を出さない | 組 C |
| category が消えた | 組 C（1.x の時点で出たことは前半で確かめてある） |
| 権限が消えた | 組 A の後半 |

## 5. 壊して確かめること（変異）

使い捨ての写しで入れ、組を流し、落ちることを見る（common.md の「検査の書き方」）。

| ID | 壊し方 | 落ちるはずの組 |
|---|---|---|
| UM1 | 前半を流さずに後半だけを流す | A・B・C |
| UM2 | 前半と後半の間でアプリを消す | A・B・C |
| UM3 | 前半にも 2.0.0 を入れる（差し替えをしない） | A・B・C（前半とスクリプトの確かめ） |
| UM4 | 環境変数を渡さない | A・B・C（skip を FAIL にする） |
| UM5 | `getScheduled` が印のある要求だけを返す | A・B・C（B・C は最初の確かめ） |
| UM6 | `getDelivered` が印のあるものだけを返す | A |
| UM7a | `cancelScheduled` が印の無いものを無視する | A |
| UM7b | `removeDelivered` が印の無いものを無視する（UM7a と別に。A は取り消しを先に見るので、まとめると削除の確かめが無くても落ちる。C2-4） | A |
| UM8 | `responses` が印の無い応答を捨てる | B・C |
| UM9 | `willPresent` が印の無い通知に `[]` を返す | C |
| UM10 | 2.0.0 のサンプルが起動で category を全部消す | C |
| UM11 | 写しの `.xctestrun` の framework の探し先を替えない（K2-8） | スクリプトの `.xctestrun` の確かめで止まる |

判定（4 章）は、`upgrade-judge` の自己テストで、「`Passed` 1 件でも終了コードが 0 以外」「skip 1 件」「0 件」「2 件」「別の名前」「端末が違う」をそれぞれ FAIL にすることを確かめる。単体テスト（U-8）は、`NotificationMarker.removing` が `source` を消す変異で落ちる（済み）。

## 6. 流し方（スクリプト）

`scripts/test_ios_upgrade.sh --udid <シミュレーター>`（新しい。シミュレーターの UDID だけを受け、実機の口を持たない）:

1. `Simulator.app` が開いていたら止まる。`TEST_RUNNER_NTK_DEVICE_ALLOW`・`NTK_DEVICE_ALLOW` と、U-10 の変数を外す
2. ランナーの確かめを呼ぶ: 閉じた形のソースの規則（`check_test_folder`）、信頼する部分のハッシュ（`trusted_part_changes`）、宣言の照合。1 つでも外れれば止まる（K-5）
3. 作業用のフォルダ（`ios/IosLibraryExample/build/test_ios_upgrade/<時刻>/`）に `git worktree add --detach <フォルダ>/legacy 1.13.0`。`trap`（EXIT・INT・TERM）で、背後の `xcodebuild` を止め、位置を消し（`simctl location clear`）、サンプルの位置の許可を戻し（`simctl privacy reset location <bundle id>`）、サンプルを消し、`git worktree remove --force` と `git worktree prune` を行う（K2-9）
4. 1.x のサンプルを組む（1.13.0 の木で `xcodebuild build -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryExample -destination 'generic/platform=iOS Simulator'`。derived data は作業用のフォルダ）
5. 今の木で `build-for-testing`（derived data は作業用のフォルダ）。`.xctestrun` を同じフォルダに写し、写しを U-2 のとおり替え、U-4 (1) を確かめる
6. シミュレーターを起動して待つ（`simctl boot` と `simctl bootstatus -b`。前もって起動したシミュレーターは `xcodebuild` が止めない。8 章）。始めの状態（起動していたか）を覚える
7. 組 A・B・C ごとに:
   1. `simctl uninstall`（サンプル）、1.x を `simctl install`、`simctl privacy grant location`、位置を大阪へ、印のファイルを消す
   2. 前半（写しの `.xctestrun`、`-only-testing` で前半の 1 つ、`TEST_RUNNER_NTK_UPGRADE_STEP=<前半>`）→ 判定 → 版の確かめ（1.3.0）。落ちたら後半を流さない
   3. 後半（元の `.xctestrun`、後半の 1 つ、`TEST_RUNNER_NTK_UPGRADE_STEP=<後半>`、`TEST_RUNNER_NTK_UPGRADE_SIGNAL=<印のファイル>`）を背後で始める。組 B・C は U-5 のとおり印を待って東京駅へ → 終わりを待つ → 判定 → 版の確かめ（2.0.0）
8. 組ごとの PASS / FAIL と、全体の結果を出す。`trap` の片付けの後、シミュレーターを始めの状態に戻す（`test_ios.sh` の `restore_simulator` と同じ）

## 7. 変えるもの

| ファイル | 変更 |
|---|---|
| `IosLibraryExampleUITests/UpgradeUITests.swift`（新） | 6 つのテスト（3 章） |
| `IosLibraryExampleUITests/Support/LegacySampleApp.swift`（新。信頼する部分） | 1.x のサンプルの起動と前面の確かめ、ボタンを文字で押す口、結果の行を読む口、2.0.0 の識別子を数える口 |
| `Support/Springboard.swift`・`SystemLabels.swift`・`UnexpectedAlertGuard.swift`（信頼する部分） | U-11 |
| `Support/DeviceRequirements.json` | 6 つに `["reinstall", "systemui"]` |
| `scripts/ios_ui_runner.py` | `SCRIPT_ONLY_CLASSES` と除外の理由、`SIMULATOR_ONLY_TESTS`、`CLASS_MINIMUMS`、`TRUSTED_FILES` のハッシュ、`DANGEROUS_NAME_FILES`、`upgrade-judge` |
| `scripts/tests/test_ios_ui_runner.py` とフィクスチャ | 件数（125 → 131）、一覧とバイナリの取り直し、除外の理由、`upgrade-judge` の自己テスト |
| `scripts/test_ios.sh` | U-10 の変数を外す |
| `scripts/test_ios_upgrade.sh`（新）と `scripts/README.md` | 6 章 |
| `IosLibraryTests` の単体テスト | U-8（作った） |
| README 7 章・9 章、UI テストの設計書 6.1 と 8.4 | 結果と表 |

サンプルとライブラリのコードは変えない。

## 8. 前提の確かめ（2026-11-21、iPhone 17 Pro / 26.2）

| 前提 | 結果 |
|---|---|
| 1.13.0 のサンプルが今の Xcode（26.3）で組めること | **組めた**（1.13.0 の木のワークスペースから。警告だけ） |
| 差し替えた `.xctestrun` で 1.x のアプリが入り、1.x の `IosLibrary` で動くこと | **動いた**。初めは `UITargetAppPath` だけを替え、1.x のアプリは入ったが前面に来なかった（`UITargetAppEnvironmentVariables` の `DYLD_FRAMEWORK_PATH` が今の組み立ての置き場を指し、1.x のアプリが 2.0.0 の `IosLibrary` を読んでいた。C-1）。探し先も 1.x の置き場に替えると、1.x のアプリが前面に来て、文字のボタンが押せ、2.0.0 の識別子は 0 個、入っていた `IosLibrary.framework` は 1.3.0 |
| 上から入れてもアプリのデータが残ること | **残る**（コンテナの UUID は変わるが、中身は引き継がれた） |
| 位置の条件で、発火の時刻をスクリプトが決められること | **決められた**。1.x のまま予約して東京駅へ動かすと、3〜4 秒でバナーが出た（1.x のアプリには位置の利用の説明が無いが、`simctl privacy grant location` の許可は与えられた） |
| 前もって起動したシミュレーターを `xcodebuild` が止めないこと | **止めなかった**（起動していないときに `xcodebuild` が起動した場合は、終わると止まっていた） |
| 6 章 7 の順（`simctl install` → `grant` → 前半の `xcodebuild` が 1.x を入れ直す → 後半の `xcodebuild` が 2.0.0 を上から入れる）で、位置の許可と位置の条件の予約が残ること（K2-3） | **残った**。後半（2.0.0）の途中で東京駅へ動かすと、1.x が予約した通知が発火した。後半の後の `IosLibrary.framework` は `com.jonghyunkim.nativetoolkit.IosLibrary` |
| 印のファイルの受け渡し（K2-4、C2-1） | **使えた**。後半のテストが `TEST_RUNNER_` で受けた Mac の道にファイルを書き、スクリプトは約 1 秒で見つけた（書いた時刻から位置を動かすまで 3 秒） |
| 印の無い 1.x の通知が 2.0.0 の前面でバナーとして出て、長押しで広がり、1.x の入力欄で返信できること（K2-1、K2-2） | **できた**。前面でバナーが出て（約 17 秒後。東京駅へ動かしてから数秒）、長押しで `Open`・`Reply`・`Delete` が出た。`Reply` で入力欄の文字が `Type a message` の欄が出て、送ると最後のイベントは `kind=textInput`、`notificationId=scheduled-notification`、`actionId=reply`、`userText` は入れた文字、`path=hub` |

確かめは使い捨てのテストのファイル（コミットしない）で行い、後に消した。シミュレーターからサンプルを消し、位置の許可を戻し、位置を消して止めた。
