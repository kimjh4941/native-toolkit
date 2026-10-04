# レビュー結果（Kotlin の API の補完の設計書・4 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`（第 4 版）
- トピック名: android-c-abi（Kotlin の API の補完）
- 判定: **要修正**（新しい A が Claude 2 件、Codex 2 件、3 回目の A の残りが Codex 4 件。第 5 版で反映した）
- 別モデルによる独立レビュー: 実施済み（これまでとは別の Claude のサブエージェントと Codex の 2 者で並行）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0

ID の `Z-C` は Claude、`Z-X` は Codex。

## 3 回目の区分 A の確認

| ID | Claude | Codex | 対処（第 5 版） |
|---|---|---|---|
| Y-X1、Y-C3 | 直った | 直った | - |
| Y-X2 | 直った | 一部だけ（既存の port の既定の実装が投げる） | Z-X2 と同じ |
| Y-X3、Y-X4 | 直った | 直った | - |
| Y-C1、Y-C2 | 直った | 一部だけ（`lossy` の規則が期限の過ぎた項目にもかかると読める） | 規則を未来の項目の置き直しだけにかけた |
| Y-C4 | 直った（component を使わない形は暗黙の Intent の制限に当たらない） | **直っていない**（targetSdk 34 以降、明示でない Intent は `exported=false` に届かない） | 2 者の判断が分かれたので、確かでない形を本線に置かず、明示の component に戻し、クラス名を変えない識別子にした |

## 区分 A（新規）

| ID | 問題 | 出典 | 対処（第 5 版） |
|---|---|---|---|
| Z-C1、Z-X1 | 発火の順序が今の「出す → 消す → shown」から「出す → shown → 後で消す」に変わる。shown の受け手の中の `isScheduled` が変わる | 両方 | 受け手は今と同じく main の上で同期に「出す → 同じ世代なら消す → shown」 |
| Z-C2 | `bootCount` の判定が Auto Backup（入れ直し、端末の移行）と両立しない。読めないときの扱いが無い | Claude | インストールごとの印（`noBackupFilesDir`）と `bootCount` の両方で判定。読めなければ生きていないとする |
| Z-X2 | 既存の port の `isScheduled` の既定の実装が投げるので、利用者が自分で実装した repository で動作が変わる | Codex | 既存の port は変えない。application の問い合わせの口と登録所を置き、組み立ての根が data の実装を登録する。repository に関係なくライブラリの保存を引く（今と同じ）。登録が 1 度も無い場面に限る違いを KDoc に書いた |

## 区分 B・C

| ID | 問題 | 対処 |
|---|---|---|
| Z-C3 | 置き直した Alarm の世代 | 保存した世代をそのまま使う |
| Z-C4 | Z-X2 と同じ | 同上 |
| Z-C5 | 受け手の中の書き込みの失敗 | 捕まえてログ、続ける（3.3 に足した） |
| Z-C6 | `ScheduleLock` の型、ロックの中の `send` | `ReentrantLock`。`send` はロックの外 |
| Z-C7 | 読めない要素を書き直しで残すか | 元の JSON のまま残す |
| Z-X3、Z-X4 | 発火の順序と、自前の repository の `isScheduled` のテスト | IT-12、IT-23 に足した |
| Z-C8〜Z-C12 | 発火の失敗、バックアップの規則、過ぎた `lossy` の項目、カスタムビュー、呼び名 | 8.6 と 3.3 の書き直しで閉じた（過ぎた `lossy` の項目は出して消す。発火の `send` の例外は今と同じく伝わる） |

## 総合評価

8.6 以外（初期化、宿主、イベント、Share、Dialog、権限、付録 A）に新しい A は無かった（Claude）。残った A は予約の受け手の順序と判定の細部、既存の口の互換、Intent の宛先で、第 5 版で反映した。次の 5 回目が手順の決まりの上限である。
