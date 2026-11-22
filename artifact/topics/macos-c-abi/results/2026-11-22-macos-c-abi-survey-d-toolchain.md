# D. macOS のツールチェーンとテストの基盤（2026-11-22 の調査）

> この記録は、企画（`../plans/2026-11-22-macos-c-abi-plan.md`）のための調査の全文を、scratchpad から写したもの（2026-11-22）。写すときに、利用者の氏名・証明書の ID・Team ID を `<氏名>`・`<証明書の ID>`・`<Team ID>` に、scratchpad の道を `<scratchpad>` に置き換えた。試作と生成物は scratchpad に残し、リポジトリには入れていない。日付の記録として本文は直さない

観点: macOS の C ABI の企画（iOS の `artifact/topics/ios-c-abi/README.md` の 8.3 と段階 0d〜0g が手本）の前提になる、今のツールチェーン・設定・テストの基盤。
リポジトリは変えていない（調べ終わりの `git status` は開始時と同じ。生成物はすべて scratchpad の `survey/` の下）。
HEAD は `1bd0f118`（branch `feature/NTKIT-19`）。

置いたもの（すべて `<scratchpad>/survey/` の下）:

| パス | 中身 |
|---|---|
| `logs/s5-*.log`、`logs/s6-*.log` | Xcode 26.3 の strict complete（Swift 5）と Swift 6 のビルドの記録 |
| `logs/x266-*.log` | 同じものを Xcode 26.6 で |
| `logs/cur-*.log` | 今の設定のまま（whole-module、clean）のビルド |
| `logs/test-lib.log`、`logs/test-unity.log`、`results/*.xcresult`、`results/*.json` | 単体テストの実行と結果 |
| `swiftinterface/MacLibrary-current-1bd0f118-{arm64,x86_64}.swiftinterface` | 今の `MacLibrary` の公開 API |
| `bin/builds.sh`、`bin/builds2.sh`、`bin/tests.sh`、`bin/count.py` | 使ったコマンドと集計（migration README 4.3 の「位置 + 診断文の unique 行」） |

---

## 1. 手元の環境

| 項目 | 値 | コマンド |
|---|---|---|
| macOS | 26.3（25D125） | `sw_vers` |
| CPU | Apple M1、arm64（`hw.optional.arm64` = 1） | `uname -m`、`sysctl` |
| `xcode-select -p` | `/Applications/Xcode26.3.app/Contents/Developer` | |
| Xcode 26.3 | 17C529、Swift 6.2.4（swiftlang-6.2.4.1.4）、macOS SDK 26.2 | `DEVELOPER_DIR=... xcodebuild -version`、`xcrun swift --version`、`xcrun --sdk macosx --show-sdk-version` |
| Xcode 26.6 | 17F113、Swift 6.3.3（swiftlang-6.3.3.1.3）、macOS SDK 26.5 | 同上 |
| Unity | `6000.0.44f1`、`6000.4.2f1`（`/Applications/Unity/Hub/Editor`） | `ls` |

iOS の 8.3 との対応: iOS はビルドを 26.6（Swift 6.3）に上げ、利用者の下限を 26.3（Swift 6.2.4）にした（D-16）。macOS も同じ 2 本が手元にある。macOS の実機＝この Mac（26.3）で、シミュレーターは無い。最小 macOS 15 の環境は手元に無い（下の 6 章）。

## 2. 各 pbxproj の設定

3 つとも `objectVersion = 77`、`LastUpgradeCheck = 1620`、`LastSwiftUpdateCheck = 1620`（Xcode 16.2 のまま。iOS の 0e の前と同じ）。共有スキームの `LastUpgradeVersion` も 3 つとも `1620`。ワークスペース `mac/MacWorkspace.xcworkspace` は 3 つの project を並べるだけ（`group:` / `container:` の参照。設定は無い）。

| 設定 | MacLibrary | MacLibraryTests | UnityMacPlugin | UnityMacPluginTests | MacLibraryExample | MacLibraryExampleTests | MacLibraryExampleUITests |
|---|---|---|---|---|---|---|---|
| `SWIFT_VERSION` | 5.0 | 5.0 | 5.0 | 5.0 | 5.0 | 5.0 | 5.0 |
| `MACOSX_DEPLOYMENT_TARGET` | **15.0**（target） | **15.1**（project を継ぐ） | **15.0** | **15.1** | **15.0** | **15.1**（target に明記） | **15.1**（project を継ぐ） |
| `SWIFT_STRICT_CONCURRENCY` | 未設定（minimal） | 同 | 同 | 同 | 同 | 同 | 同 |
| `SWIFT_DEFAULT_ACTOR_ISOLATION`・`SWIFT_APPROACHABLE_CONCURRENCY`・`SWIFT_UPCOMING_FEATURE_*` | どの階層にも無い（`-showBuildSettings` にも出ない） | 同 | 同 | 同 | 同 | 同 | 同 |
| `CODE_SIGN_STYLE` | Automatic | Automatic | Automatic | Automatic | Automatic | Automatic | Automatic |
| `DEVELOPMENT_TEAM` | <Team ID> | 同 | 同 | 同 | 同 | 同 | 同 |
| `CODE_SIGN_IDENTITY` | pbxproj に無い。解決値 `Apple Development` | 同 | 同 | 同 | 同 | 同 | 同 |
| `ENABLE_HARDENED_RUNTIME` | NO | NO | NO | NO | **YES** | NO | NO |
| entitlements | - | - | - | - | `MacLibraryExample.entitlements`（App Sandbox、Downloads 読み取り、ユーザーが選んだファイルの読み書き。`ENABLE_APP_SANDBOX` の build setting は使わず entitlements で） | - | - |
| `PRODUCT_BUNDLE_IDENTIFIER` | `mac.library.MacLibrary.MacLibrary` | `mac.library.MacLibrary.MacLibraryTests` | `unity.mac.plugin.UnityMacPlugin` | `unity.mac.plugin.UnityMacPluginTests` | `com.jonghyunkim.mac.nativetoolkit.example` | `mac.library.example.MacLibraryExampleTests` | `mac.library.example.MacLibraryExampleUITests` |
| `MARKETING_VERSION` | 1.3.0 | 1.3.0 | 1.3.0 | 1.3.0 | 1.0.0 | 1.0 | 1.0 |
| `CURRENT_PROJECT_VERSION` | 11 | 11 | 10 | 10 | 1 | 1 | 1 |
| `BUILD_LIBRARY_FOR_DISTRIBUTION` | YES | NO | YES | NO | NO | NO | NO |
| `MACH_O_TYPE`（解決値） | mh_dylib | mh_bundle | mh_dylib | mh_bundle | mh_execute | mh_bundle | mh_bundle |
| `ARCHS`（解決値） | arm64 x86_64 | 同 | 同 | 同 | 同 | 同 | 同 |

行番号:

- `mac/MacLibrary/MacLibrary.xcodeproj/project.pbxproj`: `LastUpgradeCheck` 158。target `MacLibrary` Debug 232–263（BLFD 234、署名 235・239、CPV 237、最小 252、MV 253、bundle id 256、Swift 261）、Release 266–297。project Debug 300–363（最小 15.1 は 353、CPV 11 は 333）、Release 366–421（最小 413）。`MacLibraryTests` 424–451（最小の行が無い）
- `mac/UnityMacPlugin/UnityMacPlugin.xcodeproj/project.pbxproj`: `LastUpgradeCheck` 186。target 261–329（最小 282、bundle id 286、CPV 10 は 267）。project 332–453（最小 15.1 は 385・445）。Tests 456–483。`Embed Frameworks` で `MacLibrary.framework` を自分の中に埋める（25–36）。`LD_RUNPATH_SEARCH_PATHS` に `@loader_path/Frameworks`（277–281）
- `mac/MacLibraryExample/MacLibraryExample.xcodeproj/project.pbxproj`: `LastUpgradeCheck` 205。app 422–475（entitlements 426、hardened 432、最小 440、MV 441、bundle id 442）。Tests 478–511（最小 15.1 は 485、`TEST_HOST` はサンプルのアプリ 491）。UITests 514–543（最小の行が無い）
- `mac/MacLibraryExample/MacLibraryExample/MacLibraryExample.entitlements`（全体 12 行）

ずれ・気づいたこと:

1. **最小 macOS のずれ**: 本体 3 つは 15.0、テスト 4 つは 15.1（project の既定 15.1 を継ぐか、明記）。iOS の 0e（テストのターゲットの 18.2 を 18.0 に）と同じ直しが要る
2. bundle id が `mac.library.*` / `unity.mac.plugin.*` / `mac.library.example.*` と、サンプルのアプリだけ `com.jonghyunkim.mac.nativetoolkit.example`。iOS の 0g（`com.jonghyunkim.nativetoolkit.IosLibrary`）の相当が要る
3. `CURRENT_PROJECT_VERSION` が MacLibrary 11 と UnityMacPlugin 10 でずれている（ビルドスクリプトが「明示した module」だけ +1 するため。5 章）
4. 並行性の設定は何も固定していない。Xcode 26 の推奨設定（`LastUpgradeCheck` の更新）を受けると `SWIFT_DEFAULT_ACTOR_ISOLATION` などが入りうる。iOS の 0e と同じく、先に明示的に固定する必要がある
5. 解決値の `ARCHS` は arm64 x86_64。配布物も universal（5 章）

## 3. strict concurrency と Swift 6

### 3.1 migration README の記録（`artifact/topics/migration/README.md`）

- 12 行: macOS（`MacLibrary` / `UnityMacPlugin`。Swift 5.0 のまま）は対象として残る
- 51–52 行: Bridge callback actor-boundary は「残りは macOS」。Swift 6 の移行も「残りは macOS」
- 217–243 行（B、2026-08-30、`feature/NTKIT-15` の dirty worktree、baseline ではない）: `UnityMacPlugin` scheme で 173 件（MacLibrary Dialog 100 / Notification 52 / Share 13、UnityMacPlugin Share 5 / Notification 2 / Dialog 1、Clipboard 0。当時 Unity の Clipboard bridge は未実装）
- 245–255 行（C）: Swift 6 の言語モードで MacLibrary 8 エラー（Dialog 1 / Notification 1 / Share 6）。UnityMacPlugin は計測不能
- 274–281 行（D）: 今の設定の警告は MacLibrary 0、UnityMacPlugin 1（`UnityMacNotificationJsonParser.swift:198`）
- 283–285 行（E）: Example と各テストのターゲットは未計測
- 4.4・4.5（`artifact/baselines/` と検証スクリプト）は未作成のまま

### 3.2 今のコードで測った値

コマンド（`bin/builds.sh`。Xcode 26.3、`-derivedDataPath` は scratchpad、`build-for-testing` なのでテストのターゲットも組む）:

```bash
DEVELOPER_DIR=/Applications/Xcode26.3.app/Contents/Developer xcodebuild \
  -workspace mac/MacWorkspace.xcworkspace -scheme <MacLibrary|UnityMacPlugin|MacLibraryExample> \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath <scratchpad>/dd-<tag> \
  SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete SWIFT_COMPILATION_MODE=wholemodule \
  CODE_SIGNING_ALLOWED=NO clean build-for-testing
```

集計は migration README 4.3 の単位（フルソース位置 + 診断文の unique 行）。3 つのスキームのログを合わせて重複を除いた値。

**A. Swift 5 + strict complete（Xcode 26.3）: 3 つとも `TEST BUILD SUCCEEDED`、エラー 0、unique warning 215 件**

| ターゲット | 機能 | 件数 | ファイル |
|---|---|---|---|
| MacLibrary | Dialog | 100 | `Dialog/MacDialogManager.swift` 100 |
| MacLibrary | Notification | 52 | `MacNotificationManager.swift` 27、`NotificationRepositoryImpl.swift` 15、`NotificationPermissionHelper.swift` 10 |
| MacLibrary | Share | 13 | `MacShareManager.swift` 7、`SharePickerPresenter.swift` 6 |
| MacLibrary | Clipboard | **0** | - |
| UnityMacPlugin | Share | 5 | `UnityMacShareManager.swift` |
| UnityMacPlugin | Notification | 2 | `UnityMacNotificationManager.swift` 1、`UnityMacNotificationJsonParser.swift` 1 |
| UnityMacPlugin | Dialog | 1 | `UnityMacDialogManager.swift` |
| UnityMacPlugin | Clipboard | **0** | （Unity の Clipboard bridge は今は実装済み。案 C が効いている） |
| MacLibraryTests | Share | 17 | `SharePickerPresenterTests.swift` |
| MacLibraryExample | Share | 3 | `ShareSampleView.swift` |
| MacLibraryExampleUITests | Clipboard / Share | 18 / 4 | `ClipboardSampleViewUITests.swift`、`ShareSampleViewUITests.swift` |
| UnityMacPluginTests、MacLibraryExampleTests | - | 0 | - |

スキームごと: `MacLibrary` 182（ライブラリ 165 + テスト 17）、`UnityMacPlugin` 173（MacLibrary 165 + bridge 8。B と同じ 173 で、内訳も B と同じ）、`MacLibraryExample` 190。

多い種類: `main actor-isolated property 'X' can not be referenced from a nonisolated context` 53、`sending 'X' risks causing data races` 43、`capture of 'X' with non-Sendable type` 42、`main actor-isolated property 'X' can not be mutated from a nonisolated context` 37、`call to main actor-isolated instance method` 9、`static property 'X' is not concurrency-safe` 6、`type 'X' does not conform to the 'Sendable' protocol` 6。

iOS との比べ方（母集団に注意）: iOS の 0e の前は 423 件（うち `IosLibrary` 104）。macOS のライブラリは 165 件で Dialog が 100 件を占める。

**A'. 同じものを Xcode 26.6（Swift 6.3.3）で: 219 件**。26.3 との差は `MacShareManager.swift` 101・125 行の `sending 'content'` / `sending 'self.pickerUseCase'` / `sending 'self.serviceUseCase'` の 4 件が増えただけ（26.3 だけに出るものは 0）。

**B. 今の設定（minimal、whole-module、clean、Xcode 26.3）: 1 件**。`UnityMacPlugin/UnityMacPlugin/Notification/UnityMacNotificationJsonParser.swift:198`（`NotificationAuthorizationStatus` の switch に `@unknown default` が無い）。migration README の D と同じ。Example とテストのターゲットも 0（E の未計測を埋めた）。

**C. Swift 6 の言語モード（`SWIFT_VERSION=6.0`、同じ上書き）: `MacLibrary` で 8 エラーで止まる（3 つのスキームとも `TEST BUILD FAILED`）**。下流（UnityMacPlugin、Example、テスト）は組まれないので計測不能。Xcode 26.6 でも同じ 8 件。

| ファイル:行 | エラー |
|---|---|
| `Dialog/MacDialogManager.swift:287` | `static property 'shared' is not concurrency-safe`（非 Sendable の `MacDialogManager`） |
| `Notification/MacNotificationManager.swift:41` | 同上（`MacNotificationManager`） |
| `Share/MacShareManager.swift:54` | 同上（`MacShareManager`） |
| `Share/Presentation/SharePickerPresenter.swift:75` | `[Any]` を main actor の実装へ送れない / `ShareResult` を返せない（`presentPicker`） |
| `Share/Presentation/SharePickerPresenter.swift:96` | 同上 2 件（`performService`） |
| `Share/Presentation/SharePickerPresenter.swift:121` | `[Any]` を送れない（`canPerform`） |

migration README の C（8 件、Dialog 1 / Notification 1 / Share 6）と一致。README 253–255 行のとおり、型検査で止まるので規模の見積もりには使えない（A の 165 件のうち、フロー解析の `sending` 系はここに出ない）。

注意: この計測も baseline ではない（migration README 4.1 の条件を満たすかは見ていない）。ただし作業ツリーは clean な HEAD（`1bd0f118`。変更は android/.idea だけ）。

## 4. テスト

### 4.1 単体テストの安全性の確かめ（ソースを読んだ）

| ターゲット | 触れるもの | 判断 |
|---|---|---|
| `MacLibraryTests`（ホスト無し、xctest の中） | Clipboard の結合テストは `createPasteboard(.unique)` で作った自前の pasteboard を使い、終わりに消す（`ClipboardRepositoryImplTests.swift` 11–32 行の方針）。general は `PasteboardResolver.resolve(.general)` の同一性（`PasteboardResolverTests.swift:17`）、`accessBehavior` の値の読み取り（`ClipboardDetectionMapperTests.swift:172`。内容は読まない）、`removePasteboard(.general)` が拒まれること（`ClipboardRepositoryImplTests.swift:280`。解放の前に拒む）、`writePromised(... .general)` が空の型で拒まれること（`LazyDataProviderTests.swift:189`。実装 `ClipboardRepositoryImpl.swift:114` で pasteboard を解決する前に throw）だけ。Notification・Share は mock の repository。`UNUserNotificationCenter` を使うテストは無い。`SharePickerPresenterTests` は UI を出さない test helper | **流した** |
| `UnityMacPluginTests` の `UnityMacClipboardBridgeTests`（23 件） | **general pasteboard を消す**（`UnityMacClipboardBridgeTests.swift:175` の `manager.clear(scopeJson: {"kind":"general"})`）。general を読む（129・174 行）。general を監視する（161・184 行）。名前付きの pasteboard `com.nativetoolkit.tests.bt24` に書いて残す（343 行） | **流していない**（利用者のクリップボードを消す） |
| `UnityMacPluginTests` のそれ以外（parser 3 つと雛形。52 件） | JSON の parser だけ | **流した**（`-only-testing` で 4 つの suite に絞った） |
| `MacLibraryExampleTests`（20 件） | テストのホストがサンプルのアプリ（`TEST_HOST`）。起動でウィンドウが画面に出て、`MacLibraryExampleApp.init` が `MacNotificationManager.shared.setup()` → `UNUserNotificationCenter.current().delegate = self`（`MacNotificationManager.swift:93`）を呼ぶ。テストの中身はソースの読み取りと fixture だけ | **流していない**（通知センターに触れ、画面に出る） |
| `MacLibraryExampleUITests` | - | **流していない**（指示どおり） |

### 4.2 流した結果（Xcode 26.3、`CODE_SIGNING_ALLOWED=NO`、`-derivedDataPath` は scratchpad）

```bash
xcodebuild test -project mac/MacLibrary/MacLibrary.xcodeproj -scheme MacLibrary \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath <scratchpad>/dd-test-lib \
  -resultBundlePath <scratchpad>/results/MacLibraryTests.xcresult CODE_SIGNING_ALLOWED=NO
xcodebuild test -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin ... \
  -only-testing:UnityMacPluginTests/UnityMacClipboardJsonParserTests \
  -only-testing:UnityMacPluginTests/UnityMacNotificationJsonParserTests \
  -only-testing:UnityMacPluginTests/UnityMacShareJsonParserTests \
  -only-testing:UnityMacPluginTests/UnityMacPluginTests
```

| ターゲット | 合計 | Clipboard | Notification | Share | Dialog | 雛形 | 失敗 | skip | 時間 |
|---|---|---|---|---|---|---|---|---|---|
| MacLibraryTests | **308 成功** | 222 | 37 | 48 | **0（テストが無い）** | 1 | 0 | 0 | 約 23 秒（ビルド込み） |
| UnityMacPluginTests（4 suite） | **52 成功** | 24 | 18 | 9 | 0（テストが無い） | 1 | 0 | 0 | 約 22 秒 |
| UnityMacPluginTests の `UnityMacClipboardBridgeTests` | 未実行 23 件 | 23 | - | - | - | - | - | - | - |
| MacLibraryExampleTests | 未実行 20 件（Clipboard 19、雛形 1） | | | | | | | | |

件数は `xcresulttool get test-results summary/tests` の値で、`@Test` の静的な数と一致した（引数付きのテストは無い）。すべて Swift Testing。

### 4.3 UI テスト（ソースを数えただけ。流していない）

| ファイル | 件数 | 機能 |
|---|---|---|
| `ClipboardSampleViewUITests.swift` | 11 | Clipboard |
| `ClipboardSampleWaitRuleTests.swift` | 6 | Clipboard（待ちの規則の純粋なテスト。アプリを起動しない見込み） |
| `ShareSampleViewUITests.swift` | 17 | Share（`testShareViaMailCompletesWithMailService` は Mail.app の作成ウィンドウを開く） |
| `MacLibraryExampleUITests.swift` | 2 | 雛形（launch performance を含む） |
| `MacLibraryExampleUITestsLaunchTests.swift` | 1 | 雛形 |
| 計 | **37**（XCTest） | Dialog 0、Notification 0 |

サンプルの `accessibilityIdentifier`: `ClipboardSampleView.swift` に 11 か所（固定の 9 と、`clipboard.button.\(name)`・`clipboard.section.\(identifier)` の 2 つの生成）。`DialogSampleView`・`NotificationSampleView`・`ShareSampleView`・`ContentView` は **0**（Share の UI テストはボタンの表示名で探す）。iOS の 0b の相当（Dialog・Notification・Share への識別子と「最後のイベント」の表示）が要る。UI テストのターゲットは strict で 22 件の警告（3.2）。

### 4.4 macOS のテストのスクリプトと基準

`scripts/` に macOS のテストのスクリプトも基準の JSON も無い（`test_ios.sh`・`test_android.sh`・`test_windows.ps1` と基準 JSON だけ）。`check_*_dist.py` にも macOS は無い。

iOS の形:

- `scripts/test_ios.sh`（1043 行）が xcodebuild・simctl・devicectl を動かし、判断と照合はすべて `scripts/ios_ui_runner.py`（2939 行、純粋な関数。`scripts/tests/test_ios_ui_runner.py` で自己テスト）
- 柱は 3 つ: 区分（`systemui`・`sharesheet`・`clipboard`・`files`・`reinstall`・`credentials`）の宣言（`Support/DeviceRequirements.json`）と `--device-allow` による選別、宣言と信頼する部分のハッシュの照合、実機の実行ごとの許可（`--dry-run` で一覧と許可の ID、`--approved` で 1 回だけ。台帳はリポジトリの外）
- UI のクラスを 1 つずつ別の xcodebuild で流す（`UI_CLASSES`）、`SIMULATOR_ONLY_TESTS`、意図した skip（`INTENDED_SKIPS`）
- 基準 JSON（`scripts/test_ios.baseline.<model>-<os>.json`）: `model`・`os`・`osBuild`・`language`・`xcode`・`allowed`・`counts`（ターゲット → 機能 → passed/skipped）・`results`（`Target/Class/test` → 結果）。2 つの環境（iPhone 17 / 26.2 の全件、iPhone XS / 18.7.2 の許可した区分）

macOS で要る違い:

1. **実行先がこの Mac そのもの**: シミュレーターが無いので「シミュレーターで全件、実機は区分つき」の分け方が使えない。単体テストも含めて全部が利用者の私物の上で動く。iOS の `--dry-run` / `--approved` の許可の仕組みを、UI テストだけでなく、general pasteboard・通知センター・Share に触れる単体テスト（今の `UnityMacClipboardBridgeTests`、`MacLibraryExampleTests` のホスト）にもかける必要がある。逆に、触れない単体テストを区分なしで流せるように、ターゲットか suite で分けておくとよい（今は `UnityMacPluginTests` の中で混ざっている）
2. **画面を奪う**: XCUITest は Mac の前面を取り、マウスとキーボードを動かす。利用者が使っている間は流せない。流す時間の取り決め（いつ、どれだけ）と、止め方が要る
3. **クリップボードを汚す**: iOS のシミュレーターは自分の pasteboard（ただし Mac と同期する設定がある。`device-testing.md` 57–66 行）だが、macOS の UI テストは利用者の general pasteboard そのものを読み書きする（`ClipboardSampleViewUITests.swift` 229–245 行で general を clear する）。iOS の `clipboard` 区分と同じく、既定では流さない区分にする。前後で内容を退避して戻す案は、内容を読むこと自体が私物を読むことになるので不可（`device-testing.md` の決まり）
4. **通知**: 通知センターは利用者のものと共有。サンプルの通知の許可・取り消し（`tccutil reset` 相当）は利用者の設定を変える。集中モードの準備も iOS と同じく要る
5. **Share**: Mail.app など実在のアプリが開く（`ShareSampleViewUITests.swift:164–175`）。`sharesheet` 区分の相当
6. **入れ直し・更新のテスト**: iOS の `reinstall` の相当は、Mac ではアプリの置き場所（DerivedData の中で起動する）と TCC の記録の扱いが違う。別に設計が要る
7. **環境の記録**: 基準の `model`・`os` は Mac のモデルと macOS の版。最小の 15.x の環境は手元に無い（D-21 の「2 つの環境」の相当を作れない。仮想マシンを使うか、15 での確かめを諦めるかを決める必要がある）
8. **`.xcresult` の扱い**: 実機と同じく、UI テストのスクリーンショットに利用者の画面が入る。書き写したら消す

この Mac での単体テストの実績: 4.2 のとおり、触れないものは `CODE_SIGNING_ALLOWED=NO` で署名なしに流せた（ホスト無しのテストバンドル）。

## 5. ビルドスクリプトと `dist/1.14.0/mac`

`scripts/build_xcode26_library_xcframework.sh`（382 行）と `build_xcode16_library_xcframework.sh`（393 行）は、同じ流れで細部が違う。

共通:

- **Xcode を選ばない**: `xcode-select` のまま（`DEVELOPER_DIR` があればそれ）。CommandLineTools のときだけ `/Applications/Xcode*.app` の最初を使う（xcode26 版 109–125 行）。名前の 26 / 16 は対象にした Xcode の目安で、スクリプトは版を確かめない
- `xcodebuild archive`、`-destination generic/platform=macOS`、`SKIP_INSTALL=NO`、`BUILD_LIBRARY_FOR_DISTRIBUTION=YES`（xcode26 版 300–311 行）。スライスは `ARCHS` の既定のまま arm64 + x86_64 の 1 つ（`macos-arm64_x86_64`）
- **署名を外さない**: `CODE_SIGN_*` の上書きが無いので、project の Automatic・`Apple Development`・チーム <Team ID> で署名される
- **版の書き換え**: `--library-version` で `MARKETING_VERSION` を上書きし、release では `CURRENT_PROJECT_VERSION` を +1。さらに **リポジトリの `project.pbxproj` を awk で書き換える**（163–185 行、265–271 行。pbxproj の中の全部の `MARKETING_VERSION` と `CURRENT_PROJECT_VERSION` を同じ値にする。テストのターゲットも巻き込む）。依存で暗黙に組む MacLibrary（`-m UnityMacPlugin` だけのとき）は +1 しない
- 出力の既定は `dist/<version>/mac/mac-native-toolkit-<version>.xcframework` / `unity-mac-native-toolkit-<version>.xcframework`。中間物はリポジトリの中の `mac/Build/<module>/`（`.gitignore` 済み）に置き、`rm -rf` する
- UnityMacPlugin は MacLibrary の archive を `FRAMEWORK_SEARCH_PATHS` に渡し、`MacLibrary.framework` を自分の `Frameworks/` に埋める（275–296 行）

xcode26 版だけ:

- `--minimum-macos`（既定 15.0、`MACOSX_DEPLOYMENT_TARGET` を上書き）、`ENABLE_MODULE_VERIFIER=NO`
- `create-xcframework` を `/tmp` の一時フォルダーに作り、`rsync -aL` で写す（349–379 行）。**`-L` で symlink を実体にする**ので、macOS の framework の `Versions/Current` と最上位の `MacLibrary`・`Headers` などがすべて実体の複製になる

**`dist/1.14.0/mac` を作ったのは xcode26 版**（根拠: git の 108 ファイルがすべて mode 100644 で symlink が無い＝`rsync -aL` の形。xcode26 版の使い方の例に `dist/1.10.0/mac/... --minimum-macos 15.0` がある。README 165 行の手順も xcode26 版）。

`dist/1.14.0/mac` の中身:

- `mac-native-toolkit-1.3.0.xcframework`、`unity-mac-native-toolkit-1.3.0.xcframework`。**バイナリは 1.10.0〜1.14.0 で同じ**（sha1 `b760814c…` / `b76d9f8b…`）。1.10.0 のもの（2026-09-06 のコミット `8f06a8a1`）を写し続けている。その後のソースの変更はコメントだけ（`e1107b10`）
- Info.plist: `DTXcode` 2630、`DTXcodeBuild` 17C529（Xcode 26.3）、SDK macosx26.2、`LSMinimumSystemVersion` 15.0、bundle id `mac.library.MacLibrary.MacLibrary` / `unity.mac.plugin.UnityMacPlugin`、`CFBundleVersion` 11 / 10
- Mach-O: universal（x86_64、arm64）、`minos 15.0`、`sdk 26.2`
- swiftinterface: `swift-compiler-version: Apple Swift version 6.2.4 effective-5.10`、`-swift-version 5`、`-target arm64-apple-macos15.0`
- **署名**: `Apple Development: <氏名> (…)`、Team <Team ID>、2026-09-03 に署名。**`codesign --verify` は失敗する**（`file missing: .../MacLibrary.swiftmodule/arm64-apple-macos.swiftmodule` など。`create-xcframework` がバイナリの `.swiftmodule` を外した後に、署名の封印が残っているため。`--strict` では symlink の実体化でも失敗）。UnityMacPlugin の中に埋めた MacLibrary も同じ証明書で署名
- iOS の D-18（配る framework は署名しない）に相当する決定が macOS にはまだ無い。壊れた開発用の署名を配っている状態

## 6. 公開 API の swiftinterface

作れた。`dist` と同じ組み方（Xcode 26.3、Release、`generic/platform=macOS`、`BUILD_LIBRARY_FOR_DISTRIBUTION=YES`、`ENABLE_MODULE_VERIFIER=NO`、`MACOSX_DEPLOYMENT_TARGET=15.0`、`CODE_SIGNING_ALLOWED=NO`、`-derivedDataPath` は scratchpad）。

- 置き場所: `swiftinterface/MacLibrary-current-1bd0f118-arm64.swiftinterface`、`...-x86_64.swiftinterface`（各 1101 行）
- `dist/1.14.0/mac` の swiftinterface と **完全に同じ**（`diff` で差 0。両方のスライス）。つまり今の HEAD の公開面 = 出し済みの 1.3.0
- `swift-frontend -typecheck-module-from-interface` で Xcode 26.3 と 26.6 の両方とも型検査が通った（エラー出力なし）
- iOS の手本（`artifact/topics/ios-c-abi/results/swiftinterface/` の `IosLibrary-before-0e-<commit>.swiftinterface` と段ごとの `.diff`）に合わせるなら、名前は `MacLibrary-before-0e-1bd0f118.swiftinterface`。arm64 の 1 枚で足りる（iOS も arm64 だけ）

## 7. DocC・docs・マニュアル

- `mac/generate_docc.sh`（107 行）: `MacLibrary` と `UnityMacPlugin` をそれぞれ `xcodebuild docbuild`（`BUILD_LIBRARY_FOR_DISTRIBUTION=NO`、`generic/platform=macOS`）し、`docc process-archive transform-for-static-hosting` で `mac/Docs/<module>`（hosting base path は module 名）へ。中間物は `mac/Build/<module>`（どちらも `mac/.gitignore` の 1・2 行で除外。今 `mac/Build` は 1.6G、2026-11-22 09:14 の生成）。UnityMacPlugin の前に MacLibrary を同じ DerivedData で組む。Xcode は選ばない
- `scripts/publish_docs.sh`: `--os mac` で `generate_docc.sh` を呼び（275–282 行）、`mac/Docs/MacLibrary`・`mac/Docs/UnityMacPlugin` を `docs/<version>/mac/` へ写す（342–344 行）
- `docs/1.0.0`〜`docs/1.14.0` と `latest`（`VERSION.txt` = 1.14.0）のどれにも `mac/MacLibrary`・`mac/UnityMacPlugin` がある（各 1664 ファイル）。1.14.0 は作り直されていて 1.13.0 と 787 ファイルが違うが、見た限り JSON のキーの並びと `platforms` の追加などの生成の差（内容の変更ではない）
- マニュアル `manual/1.14.0`（en / ja / ko の 3 言語）:
  - `index.md`: 「Supported OS versions」に macOS 15+（59–64 行）、「Feature list」の `## Mac`（172–201 行。Dialog 6、Notification 5、Share 4、Clipboard 9 の項目）、「Samples」の Mac sample（240–248 行）、「Library integration」の `### macOS`（561–573 行。`mac-native-toolkit-1.3.0.xcframework` を Embed & Sign する 9 手順。手順 2 は「Xcode 26.2」と書いてあり、配布物を組んだ 26.3 とずれる）
  - 機能ごとの `## macOS` 節: `dialog.md` 1773 行（`### MacDialogManager` と 6 つの `####`）、`notification.md` 3392 行（Setup / Permission / Show / Update・Cancel / Schedule / Query / Badge / Category / Error Codes）、`share.md` 1607 行（Setup / Picker 3 種 / Direct Service / Error Handling）、`clipboard.md` 2367 行（Setup / Scope / Copy / Copy Options / Append / Read / Detect / Observe / Paste Control / Clear / Error Handling）
  - **Unity の章は無い**（どの OS にも）。Unity は `clipboard.md:2400`（completion の形は Unity bridge のため）と `share.md:1638`（callback は Unity Bridge 用）で触れるだけ。`unity-mac-native-toolkit` の導入手順もマニュアルには無い（README 58 行に成果物名があるだけ）
  - 画像は `images/mac/`（`Example_Top.png` と機能ごとのフォルダー 4 つ）
  - iOS の段階 4 の相当（C ABI の節、移行ガイド、Doxygen と DocC の整合）は macOS にはまだ何も無い

## 8. 企画への含意（iOS の段階との対応）

| iOS の段階 | macOS の今 |
|---|---|
| 0b（識別子） | Clipboard だけ済み（11 か所）。Dialog・Notification・Share は 0 |
| 0c（UI テスト） | Clipboard 17、Share 17、雛形 3。**Dialog・Notification は 0**。単体テストも Dialog は 0 |
| 0d（ランナーと基準） | 無い。実行先がこの Mac だけなので、iOS の許可の仕組みを全体にかける設計が要る（4.4） |
| 0e（設定・strict） | `LastUpgradeCheck` 1620、並行性の設定は未固定、最小 macOS がテストで 15.1。strict の警告 215 件（ライブラリ 165、うち Dialog 100）。26.6 では 219 件 |
| 0f（Swift 6） | `MacLibrary` で 8 エラー（`shared` 3、Share の presenter 5）。下流は未計測 |
| 0g（bundle id） | `mac.library.*` / `unity.mac.plugin.*` のまま |
| 2b（配布と署名） | 配布物は開発用の証明書で署名され、その署名は検証に通らない（5 章）。symlink も実体化されている |
| 8.3（版） | 手元は 26.3 / 26.6、macOS 26.3、Unity 6000.0.44f1 / 6000.4.2f1。最小 macOS 15 の確かめの環境が無い |
