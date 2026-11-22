# iOS の汎用 C ABI: 終わりの記録（リリースの前）

- 記録日: 2026-11-22
- 対象: `artifact/topics/ios-c-abi/README.md` の全体
- ブランチ: `feature/NTKIT-18`
- 状態: すべての段階と README 9 章の DoD が済んだ。残りはリリース（PR・マージ・タグ。README 5 章の「2.0.0 を出す条件と戻り先」）だけ。リリースでこの作業の区切りを終えるので、後の作業のために、古くなった記述の対応（2 章）と、リリースの後に残す項目（3 章）をここにまとめる
- 洗い出し: 利用者の指示（リリースでこのセッションを終えるので、その前に記録の漏れを確かめて残すこと）で、観点を 2 つに分けて頼んだ。照らす先が違うため。課題の中の記録で「残る」と書いたものが後の記録で閉じたか（Claude のサブエージェント）と、課題の外の文書が今のリリースに対して古くないか（Codex）。どちらも読むだけ

## 1. 出来上がったもの

| 物 | 中身 | 記録 |
|---|---|---|
| `IosLibrary` 2.0.0（Swift の API） | 4 機能の Swift 6 の API。要求の箱と取り消し、presenter、通知の delegate の転送とイベント、エラーの case の整理、プライバシーマニフェスト、ログの規則 | 段階 0e〜1b、`designs/2026-10-31-ios-c-abi-swift-api-design.md`、README 4.1 |
| `IosLibraryCApi` 2.0.0（C ABI） | `ntk_*` の 134 関数（`@c @implementation`、どのスレッドからも呼べて待たない）。ヘッダーは `include/NativeToolkitC/`、Doxygen の警告 0 | 段階 2、設計書の第 1 部・第 2 部 |
| 配布物 | `dist/1.14.0/ios` の 2 つの xcframework（署名なし、IosLibrary ビルド 20、capi ビルド 4）とヘッダー。`check_ios_dist.py` は FAIL・SKIP 0 | 段階 2 の作業の記録 17.14・17.16、段階 4 の結果 |
| 消したもの | `ios/UnityIosPlugin`（Objective-C のブリッジ） | 段階 3 の結果 |
| ドキュメント | `manual/1.14.0`（4 章の iOS と `### C ABI`、index の組み込みと 2.0.0 への移行、3 言語、写真）、DocC、Doxygen、`docs/1.14.0`・`docs/latest`、ルートの README（3 言語） | 段階 4 の結果 |
| テスト | シミュレーターの全件 726（ボタンの網羅の 1 行を含む。725 が通り、U10b が skip）、実機の基準 72、C ABI の 474 件（通常・ASan・TSan）と smoke、`--capi-ui` 59、更新のテスト（1.13.0 → 2.0.0）、人の確認 HC11〜HC13 | 段階 4 の結果の 6 章、段階 2 の作業の記録 17 章 |
| `unity-native-plugin` | 2c（C ABI を呼ぶ形への移行）、シミュレーターと実機の確かめが済んだ。向こうはリリースの手順だけが残る | 段階 2 の作業の記録 17.14・17.16 |

## 2. 古くなった記述の対応

主なもの（README の状態の行、0c・0e・1b の行、7.4 の TSan、8.6 の MS-10 と P2-6・P2-7、9 章の DoD の注、段階 3・4 の結果、1b の結果、2c の申し送り、署名の手順、第 1 部の 6 章（6.1 の表）の実機の行、第 2 部の基本情報、Swift の API の設計書の 17 章、Share の設計の D-3）は、その場所に「後の経過」を書き足した（2026-11-22）。下は、日付の記録としてそのままにしたもの。今の状態はこの表の右の列。

| 場所 | 書いてあること | 今 |
|---|---|---|
| `results/2026-10-24-ios-c-abi-stage0d-result.md` の 8 章（シミュレーターの基準、README 7 章の時間） | 0g の後に取り直す、まだ書いていない | 0g で取り直した（0g の区切り。README 5 章の 0g の行）。最新の基準は 2026-11-22（`65872e23`）。0d の約 94 分は README 7 章の「全体の実行の時期」に書いてある。2026-11-22 の全件（約 128 分）は書いていない |
| `results/2026-10-24-ios-c-abi-stage0c-result.md` の 7 章 | 実機の区分の要る 80 件と HC1・HC4・HC7・HC8 が残る | 大半は実機の回（段階 2 の作業の記録 17.2〜17.7）と HC11〜HC13 で済んだ。残りは 3 章の 3・4 |
| `results/2026-10-31-ios-c-abi-stage1b-result.md` の 62・106〜109 行目あたりと、1b の作業の記録 20.9 の表 | MS-10 のレポートは未、実機の `.private`、配布用の署名、更新のテストは後で | MS-10 と `.private` は 2026-11-14 に済んだ（17.10・17.15）。配布用の署名は行わない（README 9 章）。更新のテストは 2026-11-21 に済んだ |
| `results/2026-11-07-ios-c-abi-stage2c-handoff.md` の 96・332・357 行目あたり | `dist/<リリース版>` はまだ無い、配布用の署名は 2b の締めで | `dist/1.14.0` を作った（17.14）。配布用の署名は行わない |
| 第 1 部と Swift の API の設計書の「前段階」の行 | 実機の 39 件と人の確認の手順書が残る | 書いた時点の前提。今は 3 章の 3・4 |
| 段階 2 の作業の記録 17.3 の「持ち主の判断待ち」 | 7 項目 | 17.18 で閉じ方を書いた |
| README の頭の「チケット」の行 | チケット NTKIT-18 の中身は未確認 | 未確認のまま（3 章の 18） |

## 3. リリースの後に残す項目

「決定」は利用者が決めたもの、「未決」は決めていないもの、「実装者の判断」は利用者の決定を経ていないもの。未決のものに推奨を添える。

| # | 項目 | 状態 | 記録 |
|---|---|---|---|
| 1 | 配布用の署名（Distribution のアーカイブ）と Validate App | 決定: Apple Developer Program に登録していないため、行わないと利用者が決めた（開発用の証明書での署名し直しは確かめた） | README 9 章、17.15・17.18 |
| 2 | Xcode 26 の推奨設定（`LastUpgradeCheck`）の反映。`IosLibrary` とサンプルの pbxproj は 1620 のまま（`IosLibraryCApi` は 2660） | 未決。推奨: 次にビルドの Xcode を上げる課題で、変わる build setting の差分を記録して行う | README 8.3（536 行目あたり）、0e の作業の記録 2.3 |
| 3 | 実機で流していない 9 件: `reinstall` の NP1・NP2、`files` の S8・S9、`credentials` の D11〜D13・D15・D16（D16 は 1b で足した）。`credentials` の前の手での確かめ（パスワードの保存の確認が出るか）も未 | 未決。推奨: 実機の区切りを次に設けるときに、許可を得て流す。どれもシミュレーターでは通る | 0c の結果の 7 章、UI テストの設計書 |
| 4 | 人の確認の手順書 HC1・HC4・HC7・HC8 が無い。HC3・HC5・HC6・HC9 を実機で行うかも決めていない | 未決 | 0c の結果の 7 章 |
| 5 | `ClipboardRedaction`（ブリッジのために公開した `@objc public` の型）を残すか | 未決のまま、残す形で 2.0.0 に入る（推奨どおり）。消すなら次の major で | 段階 3 の結果の 5 章 |
| 6 | 実機の ASan と smoke は 11-07 に `92a51809` で組んだもので流したきり（SH-13 の直しと段階 4 の作り直しの前。17.8） | DoD の注で受け入れた。作り直しはコメントと SH-13 の直しで、シミュレーターの `--capi` と smoke（26.6・26.3）は作り直した dist で通る | DoD、17.16 |
| 7 | アーカイブでの確かめ（`codesign` とプライバシーのレポート）は作り直す前の dist で行った | 未決（小さい）。`unity-native-plugin` の Release のアーカイブでの署名し直しで一部を代えた | 17.16 |
| 8 | 自動の CB1 で実機に貼り付けのアラートが出なかった原因 | 分からないまま。決定: 実機は HC13 で確かめる（合格） | 17.11・17.17 |
| 9 | 揺れたテスト: `testALoadAllowedAfterItTimedOutDeliversNothing`（後始末でアラートが残る）、`NotificationDelegateRouterTests.comingBackAfterTheForwardingCallReturnedIsNotStopped`（`settle()` の 150 ms）、D8（文字入力の Dialog が出ない） | どれも流し直しで通った。後の 2 つは 2026-11-22 の全件で、1 つ目は同じ日の 2 回目の `--capi-ui`（59/59）で通った。実装者の判断でテストは変えていない（利用者の決定ではない）。また落ちたら原因を調べる | 段階 4 の結果の 6 章、17.16 |
| 10 | `IosLibrary` のログが通知・category・アクションの識別子を `.public` で出す（`ios.md` の規則どおり） | 未決。TB-7 で「別の課題として持ち主に判断を仰ぐ」とした | 段階 2 の作業の記録の TB-7 のレビューの表 |
| 11 | 0d の残り: A-3 の変異、実機の言語を読む方法（U-16 が `unknown` の警告を出す）、レビュー v2 の区分 C の残り、既定の DerivedData と古いフォルダーを消すか | 未決 | 0d の結果の 8 章（DerivedData は 7・8 章） |
| 12 | 更新のテストの K3-9 の待ち | 実装者の判断でわざと残した（レビュー v1 の K3-9 への答え。利用者の決定ではない） | 更新のテストの実装のレビュー |
| 13 | マニュアルの範囲外: 1.13.0 以前の目次のずれ（検査 8 が見つける）、macOS の Share の例のリテラル、`verify_manual.sh` の画像の 30 件（1.12.0 から引き継いだ macOS の通知の画像と index の Android の画像） | 未決。画像は `manual-integrity` の範囲 | 段階 4 の結果の 4・5 章 |
| 14 | `unity-native-plugin` の macOS の xcframework の `VERSION.txt` での固定 | 決定: 後の macOS の C ABI の課題に回す | 17.14 |
| 15 | README 8.4「決めないこと」（macOS の C ABI、SwiftPM・CocoaPods、static framework、D-5 の B、iOS の CI、App Extension、Flutter などの確かめ、機能ごとの分割） | 決定: この課題では扱わない（2026-10-18） | README 8.4 |
| 16 | 利用者の端末とアカウントの残り: 実機に残したテストのホストと smoke のアプリ、App ID とプロファイル、アーカイブ | 決定: 消すかは利用者が決める | `agent-rules/device-testing.md`、署名の手順 |
| 17 | Share の設計の MS-S5 の残り（今の口の Dialog と、出る途中の共有のシートが同じ回） | 未決。小さい | `designs/2026-11-21-ios-c-abi-share-same-turn-design.md` の測りの表の「MS-S5 の残り」 |
| 18 | チケット NTKIT-18 の中身 | 未確認 | README の頭の「チケット」の行 |
| 19 | リリース（PR・`main` へのマージ・タグ `1.14.0`・GitHub Release） | 利用者の指示を待つ。`unity-native-plugin` は native-toolkit のリリースの後に自分の版を出す | README 5 章 |

リリースのチェックリストで流すもの: `check_ios_dist.py 1.14.0`、`check_android_dist.py 1.14.0`（2026-11-22 に流し直して FAIL 0。17.14 で落ちたマニュアルの項目も通る）、`verify_manual.sh 1.14.0` と 3 つの C の例の照合。

## 4. 課題の外で直したもの（2026-11-22）

課題の外の文書のうち、今のリリースに対して古いものを直した。日付の記録は本文を残し、2026-11-22 の注を足した。

| 場所 | 直したこと |
|---|---|
| ルートの README（3 言語）の「Requirements」と iOS のビルドのコマンド | ソースから組むには Xcode 26.4 以降（Swift 6.3 の `@c @implementation`。1.14.0 は 26.6 で組んだ）、`DEVELOPER_DIR` で選ぶ。組んだ framework を使うアプリはマニュアルを見る（26.3 以降、C だけなら Xcode 26 のどれでも） |
| `scripts/build_ios_library_xcframework.sh` の頭の例 | 古い版（1.2.0、1.3.0、`dist/1.6.0` など）を 2.0.0 と `dist/1.14.0/ios` に。`--library-version` の無い例は止まるので付けた。Xcode 26.4 以降が要ることを書いた（コメントだけ） |
| `agent-rules/workflows/release/workflow.md` | チェックリストに `check_ios_dist.py` と `check_android_dist.py`（どちらも FAIL 0）を足した |
| `agent-rules/workflows/design-sample-app/workflow.md` | iOS の通知の初期化を 2.0.0 の形（起動の中の `installDelegate()`、`responses`・`settingsRequests` の listener）に。`setup()` と古い受け口は互換の確かめだけ |
| `agent-rules/workflows/write-manual/workflow.md` | API が機能をまたいで変わる版では、`artifact/topics/<課題>/` の設計と結果も材料にし、後の記録を優先する |
| `agent-rules/device-testing.md` | simulator only の段落に、CB1・CB3・CB4 と実機の人の確認 HC11〜HC13 を足した（17.18） |
| `artifact/README.md` | ios-c-abi の行を今の状態に。bridge-testing・memory-sanitizers・feature-scoped-testing・migration の行も合わせた |
| `artifact/topics/bridge-testing/README.md` | iOS のブリッジは 2.0.0 で無くなり、C ABI のテストに置き換わった。Windows と Android も C ABI に移った |
| `artifact/topics/memory-sanitizers/README.md` | iOS の今の状態（シミュレーターの通常・ASan・TSan の 474 件、実機の ASan、実機の TSan は対応なし） |
| `artifact/topics/feature-scoped-testing/README.md` | iOS は `test_ios.sh --feature` がある（UI テストだけ）。macOS と分けた |
| `artifact/topics/migration/README.md` | iOS は 0e・0f で Swift 6 になり、`UnityIosPlugin` は消えた。`-scheme UnityIosPlugin` のコマンドは昔の記録 |
| `artifact/topics/windows-architecture/README.md` | `UnityIosPlugin` は 2.0.0 で消えた、iOS の C ABI は自分の Doxygen を持つ |
| `artifact/ios/share/designs/2026-07-04-ios-share-design.md`、`artifact/ios/clipboard/designs/2026-08-02-ios-clipboard-design-v4.md` | ブリッジの部分は 2.0.0 の設計に置き換わった、という注（Dialog と通知には iOS の機能の設計の文書が無い） |
| `scripts/README.md` | `verify_manual.sh` の検査は 8 つ、サンプルの言語に Swift |

直していないもの: サンプルの設計の文書には、画面の向きと Dialog の画面の形の記述が無い（向きの決まりと Dialog の形は段階 4 の結果の 6 章に書いた）。`scripts/README.md` の表に `check_android_dist.py` が無い（Android の課題の範囲）。

## 5. 次に始めるときの入口

- 今の状態: この記録の 3 章と README の状態の行
- 決定の一覧: README 8.1（D-1〜D-22）、第 1 部（P1-n）、Swift の API の設計書（S-P n）、第 2 部（P2-n）、段階 2 の作業の記録 17 章
- テストの流し方: `scripts/test_ios.sh`（`--baseline`、`--feature`、`--capi`、`--capi-ui`、実機は `--dry-run` と `--approved`）、`agent-rules/device-testing.md`
- 次の課題の候補: macOS の C ABI（README 8.4）、3 章の未決の項目
