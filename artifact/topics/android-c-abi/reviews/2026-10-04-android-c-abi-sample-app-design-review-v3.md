# レビュー結果（段階 1b のサンプルの設計書・第 3 版の確かめ）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-sample-app-design-v3.md`（第 3 版）
- トピック名: android-c-abi（段階 1b のサンプル）
- 対象 OS: Android
- 判定: **合格**（B 1 件、C 2 件を直して止めた）
- レビュアー: Codex 1 者（`gpt-5.6-sol`、`medium`。第 3 版で直した所だけ）

## 2 回目の指摘の確かめ

S2-A1（Chooser Action の名前）、S2-B1〜B3、S2-X1〜X6、S2-C1〜C7 は、コードと照らしてすべて直っていた。`ExternalLaunchUiTest` の上で `ActivityLifecycleMonitorRegistry` から MainActivity を取って `finish()`・`recreate()` できること、今の `Toasts` の記録に `count` を足せることも確かめた。

## 指摘

| ID | 区分 | 問題 | 対処 |
|---|---|---|---|
| S3-X1 | B | 新しい `NotificationEventDeliveryUiTest` を `scripts/test_android.sh` の `UI_CLASSES` に足すと書いていない。スクリプトは並べたクラスだけを流す | 5 章と 8 章に、`UI_CLASSES` に足すと書いた |
| S3-X2 | C | Activity の取り方と、`finish()` の後・`recreate()` の後の待ち方が書かれていない | `runOnMainSync` の中で `ActivityLifecycleMonitorRegistry` から RESUMED の MainActivity を取り、DESTROYED・RESUMED になるまで上限つきで待つと書いた（5 章） |
| S3-X3 | C | まだイベントを受けていない間のイベントの行の文言が無い（試験は「#0」を前提にする） | 「ℹ️ #0 No events yet」と決めた（4.2） |

どれも数行の追記で、ほかの節に及ばないので、確かめのやり直しはしない。第 3 版を決定とする。
