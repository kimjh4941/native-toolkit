# レビュー結果（段階 1b のサンプルの設計書・2 回目の確かめ）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-sample-app-design-v2.md`（第 2 版）
- トピック名: android-c-abi（段階 1b のサンプル）
- 対象 OS: Android
- 判定: **要修正**（第 2 版で入った A が 1 件。第 3 版で反映した）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェント（`general-purpose`）と Codex（`gpt-5.6-sol`、`medium`）の 2 者で並行。1 回目の指摘が直ったかと、直しで新しい問題が入っていないかを、コードと照らして確かめた）

ID の `S2-C` は Claude、`S2-X` は Codex。

## 1 回目の指摘の確かめ

| ID | Claude | Codex | まとめ |
|---|---|---|---|
| S-X1、S-C1（メディアのアクション） | 解消 | 解消 | 解消。`NotificationLaunchActivity` が先にイベントを出し、`singleTask` の MainActivity が前に出て通知の画面のまま残るので、n28 の表示の確かめも作れる |
| S-X2、S-C2（Dialog の値と options） | 解消 | 解消 | 解消。6 つの要求の値は今のサンプルと完全に一致 |
| S-C3、S-X4（手動の項目） | 解消 | 不十分 | 試験の置き場所に問題が残る（S2-X2、S2-C4） |
| S-C4、S-X3（イベントの受け渡し） | 解消 | 不十分 | 溢れたときの扱いと、1 回だけを確かめる方法が足りない（S2-X1、S2-X3、S2-B3） |
| S-C5〜S-C12 | 解消 | 解消 | 解消 |
| S-C13（`DeviceState.kt` の分類） | 不十分 | 不十分 | 3.3 と 8 章が食い違う（S2-C1、S2-X4） |

## 区分 A

| ID | 問題 | 出典 | 対処（第 3 版） |
|---|---|---|---|
| S2-A1 | 第 2 版で Chooser Action の名前を「Custom action」に変えた。今のサンプルも第 1 版も「Custom」で、`ShareUiTest.s04` は `sharesheet.choose("Custom")` を完全一致で探すので落ちる（第 2 版で入った退行） | Claude | 名前を「Custom」に戻し、本文と結果の文言も今のままと明記した（4.4） |

## 区分 B

| ID | 問題 | 出典 | 対処（第 3 版） |
|---|---|---|---|
| S2-B1、S2-X6 | Dialog の新しいボタンの文言に `<kind>` が無く、共通の表とずれる | 両方 | 共通の形（`<kind> - …`）にそろえた（4.5） |
| S2-B2 | コルーチン版の権限の試験は `@CategoryHostState` のクラスにあり、`scripts/test_android.sh` の `HOST_STATE_CASES` に載せないと流れない | Claude | 2 行足すと書き、スクリプトを変更の一覧に入れた（5 章、8 章） |
| S2-B3、S2-X3、S2-C5 | `statusText` は置き換えなので、二重に届いても同じ文言になり、「1 回だけ」「2 回とも」を見分けられない | 両方 | イベントの行に受けた順の通し番号を出し、番号の増え方で確かめる（4.2、5 章） |
| S2-X1、S2-C3 | 画面へ渡す `SharedFlow` の容量と、溢れたとき（`tryEmit` が偽）の扱いが無い。購読の数は少し遅れて変わる | 両方 | 容量 64・溢れたら待つ既定の形にし、`tryEmit` が偽なら ACTION は Toast、ほかはログだけ。購読の切り替わりの隙間を受け入れると明記した（4.2） |
| S2-X2、S2-C4 | Activity を壊すケースを Compose の rule のクラスに足す計画だが、rule は Activity を失うと使えない。壊す手順も無い | 両方 | 外からの起動の土台（`ExternalLaunchUiTest`）の新しいクラス `NotificationEventDeliveryUiTest` に分け、`finish()` と `recreate()` を instrumentation の main の上で呼ぶ手順を書いた。Toast を数える `count` を足す（5 章、8 章） |
| S2-X4、S2-C1 | `DeviceState.kt` が 3.3 では「変えない」、8 章では「変更」 | 両方 | 3.3 も「変更」にそろえ、`HostPhaseTest.kt` だけを「変えない」にした |

## 区分 C

| ID | 問題 | 出典 | 対処（第 3 版） |
|---|---|---|---|
| S2-C2 | 保たれたイベントを捨てる後始末は、Compose の rule の土台では `onCreate` より後になり効かない | Claude | 効く範囲を書き、Activity が無い間に押す試験は外からの起動の土台に置き、終わりに必ず起動して受け取らせる（4.2） |
| S2-C6 | `ShareDomainError` は message を持たないので、今の汎用の捕まえ方では「❌ null」になる | Claude | `InvalidChooserAction` を専用に捕まえて `id` を出す（4.4） |
| S2-C7 | Dialog の `value` の入り方は今のコードで決まる。メディアの `actionId` と、Dialog の画面の見出し・初期の文言を保つことが書かれていない | Claude | 値の入り方と d04・d06・d11 の期待値の例を書き、9 章から外した。`actionId` は `previous`・`play`・`next`。見出し「Dialog Example」と初期の文言を保つ（4.3、4.5） |
| S2-X5 | UI テストの設計書を追記すると書いたが、変更の一覧に無い | Codex | `app/src` の外の変更として一覧に入れた（8 章） |

## 総合評価

2 者とも、1 回目の A 3 件（メディアのアクション、Dialog の値と options、手動の項目）とほとんどの B・C は、コードと照らして正しく直ったと確かめた。第 2 版で入った退行（S2-A1）は 1 行の直しで、ほかはイベントの受け渡しと試験の置き場所の細部である。第 3 版で全件を反映した。直した所は狭く、ほかの節に及ばないので、第 3 版は直した所だけを Codex 1 者で確かめる（これまでの例と同じ）。
