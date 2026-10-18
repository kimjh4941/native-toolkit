# レビュー結果（Kotlin の API の補完の設計書・1 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`（第 1 版）
- トピック名: android-c-abi（Kotlin の API の補完）
- 判定: **要修正**（A が Claude 7 件、Codex 14 件。第 2 版で反映した）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0

ID の `W-C` は Claude、`W-X` は Codex。

## 区分 A

| ID | 問題 | 出典 | 対処（第 2 版） |
|---|---|---|---|
| W-X1、W-C1 | 1b で既存の API の動作を変える（`isScheduled` / `cancelAllScheduled` の対象、`toUri` で残らない extra での失敗、`AndroidDialogFragment` の場所、`shareWithCallback` の戻り値）。README の 1b の行と D-11 の範囲を設計書の側で書き換えている | 両方 | **既存の動作をすべて残す形に改めた**。保存は今と同じく再起動をまたぐ予約だけ、Alarm の発火は今と同じく extra の Parcel を使い（名前を `-keepnames` で固定）、`toUri` の欠落は D-11 の範囲（再起動の後に置き直すとき）だけ。`AndroidDialogFragment` は今の場所、`shareWithCallback` は今の形。新しい意味は新しい口（`ShareForResultUseCase` など）に分けた（3.3、8.6、8.8、8.9） |
| W-X2 | 非同期の UI の操作に Manager と `suspend` の版が無い。UseCase が 1 操作 1 クラスでない | Codex | `DialogManager`、`NotificationPermissionManager`（callback 版と `suspend` 版）を置き、UseCase を操作ごとに分けた（8.7、8.8） |
| W-X3 | domain の `ShareChooserAction` が `Bitmap` を持つ。`ScheduledNotificationEntry` の置き場所 | Codex | アイコンは `ByteArray`。entry は `application/model/` へ移す（8.6、8.9） |
| W-X4、W-C2 | 6.2（呼び出しの中で呼ばない）と 8.4（足す呼び出しの中で保ったものを渡す）が逆。途中で外したときの扱い | 両方 | 6.2 に `EventHub` の例外を書き、受け手に `Registration` を渡す。途中で外されたら残りを保ちに戻す（6.2、8.4） |
| W-X5、W-C10 | 「済んだら呼ぶ」の取りこぼしと二重の呼び出し | 両方 | 状態の遷移と一覧を 1 つの短いロックで扱い、済んだ時に一覧を外して 1 回ずつ積む（8.1） |
| W-X6 | `internal` の型が公開の型から見える。`request` が Context を取らない | Codex | 公開のエラーの型にし、`request(context, ...)` にした（8.3、8.7） |
| W-X7 | Share の新しい要求が、開く前に前の待ちを消す（AC-22 に反する） | Codex | 2 段の更新: 開けた後に今の要求を入れ替える（8.9） |
| W-C3 | Share の印と Chooser Action の世代がプロセスをまたいで使い回される | Claude | URI にプロセスごとの乱数を入れる（8.9） |
| W-X8 | `toUri` は extra 以外（`ClipData`、URI の権限）も落とす | Codex | 残るものと落ちるものの表を置き、`URI_ALLOW_UNSAFE` で読む（8.6） |
| W-X9 | 重い I/O を main と Receiver で行う | Codex | Receiver は `goAsync` と I/O のスレッド。同期の予約は呼び出しスレッドで書き、KDoc に書く（8.6） |
| W-X10、W-C4 | 発火と予約し直しの競合で新しい項目が消える。置き換えに失敗したときに前の項目を失う | 両方 | 項目に世代を持たせ、発火の後は同じ世代のときだけ消す。失敗したら前の項目を書き戻す（8.6） |
| W-X11、W-C7 | ちょうど 1 回の完了の状態機械が閉じていない（起動待ちの取り消し、宿主の作り直し、起動待ちの間の 2 つ目、`startActivity` の例外、権限の待ちの門、プロセスの死の後の Fragment、コールバックの例外） | 両方 | `UiHost` と要求の状態の表（起動待ち・宿主に渡した・完了）、共通の門 `UiRequestGate`、宿主の `savedInstanceState` の扱い、待ちの一覧を外してから個別に呼ぶこと（8.3、8.7、8.8） |
| W-X12、W-C5 | 秘密の値を伏せる規則が既存のログに届かない（`AndroidDialogFragment` の入力、`ShareContent`） | 両方 | 1b で既存のログも直す（ログだけの変更で K-9 に当たらない）。直す箇所を挙げた（8.11） |
| W-C6 | Dialog の公開の範囲と作り方 | Claude | 可視性の表（6.1）と入口の `DialogManager` |
| W-X13 | 権限の表が 7 つのうち 4 つ | Codex | 7 つすべてを書いた（8.12） |
| W-X14 | 1.x の破棄の失敗とやり直し | Codex | 状態（未着手・実行中・済み）、要素ごとの失敗の扱い、最後の `::` で分けること、印を書く条件（8.6） |

## 区分 B

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| W-C8 | `src/test` はフレームワークが既定値を返すので、多くの単体テストが黙って通る | Claude | フレームワークに触れるものを `androidTest` へ（12 章） |
| W-C9 | 非同期の `commit` と宿主の終わりの隙間 | Claude | `showNow` / `commitNow` で出す（8.3、8.8） |
| W-C11 | 更新のテストの手順 | Claude | 1.x の状態を作る自動のテストと、1.12.0 から組んだ APK での人の確認に分けた（12 章） |
| W-C12 | トランポリンの禁止はアプリが後ろにいるときだけ | Claude | 条件を書き、IT-11 を 3 通りにした |
| W-C13 | 権限を外した版のテスト | Claude | 7 つと版の作り方（8.12、IT-19） |
| W-C14 | API 32 以下は試験の環境に無い | Claude | 分岐を差し替えて単体テストで確かめ、端末では確かめないと書いた |
| W-C15 | D-11 が求める `toUri` の対応表 | Claude | 8.6 の表 |
| W-C16、W-X15 | 状態機械の両順のテスト、プロセスの死、入れ子、競合 | 両方 | 12 章に足した |
| W-X16 | PendingIntent の同一性と `IntentFilter` の照合を実物で確かめていない | Codex | IT-20 |
| W-X17 | 保存の失敗の注入 | Codex | IT-12、IT-13、IT-14 |
| W-X18 | 伏せる規則のテストが helper だけ | Codex | logcat に番兵の値が出ないことを確かめる IT-21 |
| W-C17、W-X19 | DoD の不足、R8 を有効にした利用者での確かめ | 両方 | DoD と IT-22 |

## 区分 C

W-C18〜W-C34 は第 2 版で直した（README と `android.md` を直す時期を「決定と同じ PR」に統一、README 8.6 の参照の書き方、`register` の戻り値、317 件の意味、`excludeFromRecents` の理由、宿主のテーマ、型の置き場所、main だけの口の一覧、全画面の Intent、起動の flags、組み立ての根の例外、強制停止の制限、`HostPhaseTest` の補い、権限の合流、前面の判定の受け持ち）。W-C22（ブリッジの import）は、`AndroidDialogFragment` を動かさないので起きなくなった。

## 総合評価

2 者の A は、(1) 1b の「変えない」との関係、(2) ちょうど 1 回の完了の状態機械、(3) 予約の保存の順序と競合、(4) 層の規則、に集まった。(1) は既存の動作をすべて残す形に改め、README は直さない。2 回目のレビューで A が 0 になったかを確かめる。
