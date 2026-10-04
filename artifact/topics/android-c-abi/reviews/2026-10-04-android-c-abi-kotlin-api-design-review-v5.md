# レビュー結果（Kotlin の API の補完の設計書・5 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`（第 5 版）
- トピック名: android-c-abi（Kotlin の API の補完）
- 判定: **合格**（5 回目で残った A を、利用者の決定に沿って第 6 版で直し、直した所だけを Codex が確かめて A が 0 になった）
- 別モデルによる独立レビュー: 実施済み（これまでとは別の Claude のサブエージェントと Codex の 2 者で並行）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0

ID の `V5-C` は Claude、`V5-X` は Codex。

## 4 回目の区分 A の確認

| 項目 | Claude | Codex |
|---|---|---|
| Y-C4 の残り（Intent の宛先。明示の component とクラス名の固定） | 直った | 直った |
| Y-C1・Y-C2 の残り（`lossy` の規則を未来の項目だけに） | 直った | 直った |
| Z-C1・Z-X1（発火の順序） | 直った | 直った |
| Z-C2（`installId` と `bootCount`） | 直った | 直った |
| Y-X2・Z-X2・Z-C4（`isScheduled` の互換） | 一部だけ（V5-C1） | 一部だけ（V5-X1、V5-X2） |

## 区分 A

| ID | 問題 | 出典 | 対処（第 6 版） |
|---|---|---|---|
| V5-C1 | 公開の `NotificationRepositoryImpl` を直接使う経路で、`isScheduled` の実装の登録が漏れ、今と結果が変わる | Claude | 下の利用者の決定で、登録の仕組みそのものをやめた |
| V5-X1 | 登録が無い場面で `isScheduled` が偽を返すのは既存の口の動作の変更（K-9） | Codex | 同上 |
| V5-X2 | 登録所が application に `Context` を持ち込む（common.md の依存のルール） | Codex | 同上 |

**利用者の決定（2026-10-04、手順の決まりの 5 回の上限で相談）**: README 4 章の「依存の向きを直す」と、1b の「既存の口の動作を変えない」がぶつかった。3 つの案（今の直接の参照を残す／小さな違いを受け入れる／口を移す）から、「今の直接の参照を残す」を選んだ。既存の `NotificationUseCases.isScheduled(context, id, tag)` は今と同じく data の保存を直接読み、README 4 章の同じ行と `android.md` に、この 1 つの既存の口だけの例外として書いた。

## 区分 B・C

| ID | 問題 | 対処 |
|---|---|---|
| V5-C2 | `ScheduleLock` の範囲に PendingIntent を作る処理が入っていない | 入れた |
| V5-C3 | 置き直しで、ロックを取り直したときの読み直しが無い | 項目ごとに同じ世代かを読み直す |
| V5-C4 | 11 の K-9 の行の数が 3.3 の表と合わない | 数を書かない言い方に直した |
| V5-X3、V5-X4 | 登録の無い経路のテスト、`send` を壁で止めたときの交差のテスト | IT-23、IT-12 に足した |
| Claude の C | tag `untagged` と tag 無しが今は同じ予約になる、起動回数が読めないときの 3.3、公開の `restoreScheduled` の書き込みの失敗、6.1 に直す既存のファイル | 予約の鍵を今と同じ形にした。ほかも直した |

## 直した所の確かめ

Codex 1 者に、第 6 版で直した所（0.5、4.1、6.1、6.3、8.6、8.14、3.3、11、IT-12、IT-23、T-12、README の行）だけを見てもらった。V5-X1、V5-X2、V5-C1〜V5-C4、`untagged`、V5-X3・V5-X4 はすべて「解消」、新しい指摘は無し。**区分 A は 0 になり、設計書を決定にした。**

手順の決まり（`review-document` の止める基準）との照らし合わせ:

1. レビュアーを替えて通した: 5 回とも、前の回とは別の Claude のサブエージェントと Codex で行った
2. 機械照合: `check_design_consistency.py` は FAIL 0
3. 直さない残件: 設計書 3.3 の「1b で直さない既存の口の不具合」と、README 8.6・D-11 から出る違いに理由つきで書いた
4. サーキットブレーカー: 予約（8.6）の A が 3 回続いたので、3 回目の後に「今の流れを写し、直列化だけを変える」原則に切り替えた（レビューの記録 v3）
