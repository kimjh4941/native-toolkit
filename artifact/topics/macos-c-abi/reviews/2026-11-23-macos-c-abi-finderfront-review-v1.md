# レビュー結果

- 日付: 2026-11-24
- 対象: VM の通知の UI テストの揺れ（`NTK-STEP:finder` など）を直した UI テストの Support の変更と、VM で落ちたテストの結果のバンドルを残すランナーの変更。`MacLibraryExampleUITests/Support/OtherApps.swift`（`FinderFront.bringToFront`）、`Support/NotificationCenterUI.swift`（`SampleStateAtPress` の AppKit の見方、`checkBeforePress`）、`Support/NotificationRules.swift`（`SecondsWindow`）、`NotificationEventUITests.swift`（N21・N23・N24）、`SupportRuleTests.swift`、`scripts/test_mac.sh`（`~/ntk/failed`）、`scripts/tests/test_mac_ui_runner.py`
- トピック名: macos-c-abi（段階 0d、FinderFront）
- 判定: **v3 で致命的な A が 0 になり、閉じた**
- 別モデルによる独立レビュー: Codex（読むだけ。3 回）
- 全文: scratchpad の `review/finderfront-codex-v1.md`、`-v2.md`、`-v3.md`
- 経緯と確かめ: 作業の記録の 16・17 章

区分: A = 重大（致命的 = 私物の損傷・漏えい・誤操作、または誤った基準へ至る現実的な経路） / B = 機能上の懸念 / C = 軽微。

## 件数

| 回 | A | B | C |
|---|---|---|---|
| v1 | 0 | 1 | 2 |
| v2 | 1（致命的） | 0 | 0 |
| v3 | 0 | 0 | 1 |

## 指摘と直したこと

| 回 | # | 指摘 | 直したこと |
|---|---|---|---|
| v1 | B-1 | Finder の待ちを AppKit にしても、押す前の「サンプルが背景」の確かめが XCUITest の `.runningBackground` のままで、同じ食い違いで落ちうる | `SampleStateAtPress.sampleIsBehind()`（main の run loop を回してから、サンプルが動いていて、どれも active でなく前面の PID でもない）を足し、`checkBeforePress` は `.background` をこれで照らす。N24 の後条件も同じ見方にした。窓の持ち主・通知の根・入力の焦点の検査は保った |
| v1 | C-1 | 「古い値にならない」というコメントが実装より強い。初回の観測の前に run loop を回していない | コメントを実装どおりにし、`bringToFront` を `@MainActor` にし、最初に見る前にも run loop を回す |
| v1 | C-2 | 自己テストが、残したバンドルの数の知らせと、`finish` がそれを消さないことを見ていない | 両方を自己テストで確かめる |
| v1 の後 | — | VM の 3 回目で N14b `secondsWindow` が出た | 残したバンドルを読み、待ちが窓の端（5.000 秒）ちょうどを狙っていて、壁の時計で 4.998 秒に起きていたと分かった。`SecondsWindow.aimInside = 0.5` で窓の中を狙う |
| v2 | A-1（致命的） | 押す前を AppKit にしたので、押した後の「前面に来た」（N21・N23）が XCUITest の古い `runningForeground` で通りうる（Open の前面化が壊れる回帰を見逃して基準に入る） | `sampleIsInFront` と `waitForSampleInFront`（AppKit で、サンプルの 1 つのプロセスが active で前面の PID であることを待つ。前面化はしない）を足し、N21・N23 の押した後に呼ぶ。押す前に XCUITest と AppKit が食い違えば `NTK-NOTE` を手順に書く。VM で、Open を前面にしない形と、さらに N23 の XCUITest の待ちを外した形の 2 つで、N23 が落ちることを確かめた（一時の変更は戻した） |
| v3 | C-1 | 作業の記録の「assertEvent の中の押下」が実装と違う（assertEvent は読み取りだけで、押下は後始末） | 作業の記録 17.3 を直した |

## 確かめ

- VM の Notification だけの回: v1 の直しの後は 60・60・59（N14b `secondsWindow`）、`aimInside` の後は 60・60・60。v2 の直しの後は、ゲストを再起動してから 60・60（再起動の前の 2 回は NP2 の許可の戻しだけが落ちた）
- 信頼する部分のハッシュ（`NotificationCenterUI`・`NotificationRules`・`OtherApps`）を v3 の後に取り直した。この Mac の自己テスト（偽の口）は 190 件のうち 182 件が通り、8 件が skip（VM の本物の分）

## 残したこと

- N23 の `notificationRoot` の型は、負荷の無い回ではまだ出ておらず読めていない（出たら `~/ntk/failed` で読む）
- VM の全件と基準の取り直しは、コミットの後に親が頼む
