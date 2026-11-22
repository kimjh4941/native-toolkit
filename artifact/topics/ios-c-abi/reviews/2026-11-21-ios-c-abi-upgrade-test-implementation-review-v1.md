# 更新のテストの実装のレビューの結果（v1）

- 日付: 2026-11-21
- 対象: 更新のテストの実装（`UpgradeUITests.swift`、信頼する部分の `LegacySampleApp.swift`・`Springboard.swift`・`SystemLabels.swift`・`UnexpectedAlertGuard.swift`、`DeviceRequirements.json`、`ios_ui_runner.py` とその自己テスト・フィクスチャ、`test_ios_upgrade.sh`、`test_ios.sh`、`scripts/README.md`、UI テストの設計書）。設計は `designs/2026-11-21-ios-c-abi-upgrade-test-design.md`（v3）
- レビューした者: Codex（C3-n）と Claude のサブエージェント（K3-n）。どちらも読むだけ。同じ頼みの文（設計との一致、壊れているのに通る形と揺れ、信頼する部分の変更が実機で安全で今の呼び出しを変えないか、ランナーの除外の漏れ、スクリプトの片付けと終わり方）を渡した。**このレビューが、信頼する部分のハッシュの取り直しのための別のモデルのレビュー**（`ios_ui_runner.py` の `TRUSTED_FILES` の注）。レビューの途中で `test_ios_upgrade.sh` を C3-1 のとおり直したので、K3 は直した後の版を見た

---

## 強み（2 者に共通）

- 設計 v3 の U-2・U-4・U-5・U-6・U-10・U-11 と 4 章・6 章の手順に沿っている。前半が落ちたら後半を流さない、版の確かめ、印のファイルの照合、`upgrade-judge` の完全一致・`Passed`・終了コード 0・UDID
- ランナーの除外は `select_tests` で効き、`build_invocations` と `make_plan` の「ちょうど覆う」照合で二重に守られる。`print_selection`・`cmd_summary`・`in_run_scope`・基準の比べ方にも漏れが無い
- 信頼する部分の変更は、今の呼び出し（`sendReply` の 3 か所、ほかのクラスの見張りのモード）を変えない。実機には、ランナーの除外・スクリプト・環境変数の 3 段で届かない

## 改善点と対応

| ID | 重さ | 問題 | 対応 |
|---|---|---|---|
| C3-1 | high | `capped ... &` は関数のサブシェルを背後で動かすので、`kill $!` が xcodebuild に届かず、中断や印の待ちの時間切れの後に残りうる | 直した。`test_ios.sh` の `capped_group` と同じ perl を変数に持ち、背後でも直接起動する（`$!` が perl。TERM で xcodebuild の組全体を殺して回収する）。孫のプロセスまで止まることを確かめた（止める前 4、後 0、終わりの値 143） |
| K3-1 | medium | 組 C の後半が、バナーが出たときにサンプルが前面にいたこと、同じプロセスのままだったこと（`launch=false`）を見ていない。`willPresent` で落ちて冷えた起動で応答が届いても通りうる | 直した。バナーの後に `isForeground`、組 B・C の最後のイベントで `launch=false` |
| K3-2 | medium | 1.x の画面のスクロールが慣性のあるスワイプで、止まりの検出が無い（`SampleApp` は測った揺れのために、慣性の無い押しドラッグ・止まりの検出・2 方向にしている） | 直した。`SampleApp` と同じ形にし、一歩ごとに `checkInterruption()` |
| K3-3 | low〜medium | 見張りが何も押さないモードなので、1.x が前面でバナーを出している間の操作がバナーに当たると落ちうる | 直した。組 A の前半で `ShowImmediate` の後にバナーが消えるのを待つ |
| K3-4 | low〜medium | 段の表（`UPGRADE_STEPS`）は手で書いた表で、7 つ目のテストを足しても気づかず、誰も流さないまま残る | 直した。`upgrade-check` が宣言の `UpgradeUITests/*` と段の表を両方向で照らす。自己テストで、列挙と段の表の集合が一致することを見る |
| K3-5 | low | 信頼する部分が U-1（シミュレーターだけ）をコードで強制していない。`sendReply` に固有でない入力欄の文字を渡せる | 直した。`UpgradeStep.require()` は実機で失敗する。`sendReply` は既定以外の文字を実機で拒む |
| K3-6 | low | `-only-testing` の引数を作るのに失敗すると、空の引数で xcodebuild を呼ぶ | 直した。先に作って形を確かめ、だめなら組を FAIL |
| K3-7 | low | 後半の後の版の確かめが識別子だけ（設計 U-4 (2) は 2.0.0 も） | 直した。この回で組んだ `IosLibrary.framework` の版と一致することを見る |
| K3-8 | low | 除外の理由の表示と `upgrade-judge` の CLI に自己テストが無い | 直した（`print_selection` に 6 行、CLI で結果無し・時間切れが 1） |
| K3-9 | low | TERM・HUP でも 130 で終わる。前景の待ちの間にスクリプトだけへ TERM が来ると、前景の子が終わるまで遅れる | 終わりの値は分けた（130・143・129）。遅れは残す（Ctrl-C は前景の組全体に届くので問題にならない。前景の perl も時間の上限を持つ） |

## 総合評価

2 者とも、設計とのずれは記録済みの `SIMULATOR_ONLY_TESTS` のほかは小さいと見た。直すべき中心は、背後の xcodebuild の止め方（C3-1）と、組 C の「前面・同じプロセス」の確かめ（K3-1）、1.x の画面のスクロール（K3-2）。すべて直し、信頼する部分のハッシュは直した後の内容で固定した。
