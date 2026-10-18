# レビュー結果（Kotlin の API の補完の設計書・3 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`（第 3 版）
- トピック名: android-c-abi（Kotlin の API の補完）
- 判定: **要修正**（新しい A が Claude 4 件、Codex 4 件。第 4 版で反映した）
- 別モデルによる独立レビュー: 実施済み（これまでとは別の Claude のサブエージェントと Codex の 2 者で並行）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0

ID の `Y-C` は Claude、`Y-X` は Codex。

## 2 回目の区分 A の確認

| 判定 | Claude | Codex |
|---|---|---|
| 直った | 14 | 14（X-X2〜X-X6、X-C1、X-C2、X-C4〜X-C7、W-X10、W-X11、W-X12、W-X14） |
| 一部だけ | 1（X-C3） | 3（X-X1、X-X7、X-C3） |
| 直っていない | 0 | 0 |

宿主の記録の寿命、権限の会の表、`EventHub` の残りの受け渡し、Share の登録を先にする形とロックの外での呼び出し、Chooser Action の世代、`setIdentifier`、Alarm の extra を JSON と OS の Parcelable に分けたことは、2 者とも崩れなかったと判断した。

## 区分 A

| ID | 問題 | 出典 | 対処（第 4 版） |
|---|---|---|---|
| Y-C1 | `MY_PACKAGE_REPLACED` で置き直さないと、OS が Alarm を消していた場面で今と結果が変わる | Claude | 置き直しを今の契機・対象に戻した。`toUri` で欠ける項目（`lossy`）だけ、保存した時から再起動していなければ置き直さない（その Alarm は欠けていない内容を持つ）。残る違いは D-11 の結果として 3.3 に書いた（8.6） |
| Y-C2 | 公開の `restoreScheduled` が生きている Alarm の extra を欠けた内容に書き換える | Claude | Y-C1 と同じ規則を公開の口にも当てる（8.6） |
| Y-C3、Y-X1 | 失敗の後の「その鍵の予約は無い」が成り立たない経路がある。後始末の失敗が無い | 両方 | 「その鍵の予約は無い」の約束をやめ、今の流れのまま（Alarm の失敗は今と同じく例外が伝わり、保存は変えない）とした。保存の書き込みの失敗だけを新しく `Result.failure(IOException)` にし、そのときの状態を表に書いた。後始末はしない（8.6、3.3） |
| Y-C4 | Alarm の Intent と保存するイベントの Intent が、ライブラリのクラス名（component）を持つ（README 1.4 の壊れた原因と同じ） | Claude | component を使わず、`setPackage` と action と data、Receiver・Activity の `<intent-filter>` で届ける。action と scheme を「変えない識別子」として表にし、テストで守る（8.5、8.6） |
| Y-X2 | `android.md` に例外を書くだけでは `common.md` の規則を解決しない | Codex | 予約の保存の port を application に置くのをやめ、data の中に閉じた。`isScheduled` は既存の port に足す（引数は基本の型だけ）。例外が要らなくなった（6.3、8.14） |
| Y-X3 | Manager の `suspend` 版が `suspend fun` + 例外送出の規則に合わない | Codex | `suspend` 版は答え（`DialogResult.Answer`、許可の真偽）を返し、取り消しと失敗は型のある例外で投げる（8.7、8.8、付録 A） |
| Y-X4 | 既存の `shareWithCallback` の、選択でない結果（Copy・Edit）のときの `onFinished` が表から落ちた。例外を捕まえる新しい規則が既存の口の例外の伝わり方を変える | Codex | 表に足した。既存の口の例外の伝わり方は今のまま、捕まえるのは新しい口だけ（6.2、8.9） |

## 区分 B

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| Y-C5 | JSON を使う単体テストが `src/test` にある | Claude | `androidTest` へ（IT-25） |
| Y-C6 | codec が欄を落とさないことのテストが無い | Claude | IT-25 |
| Y-C7 | Y-C1〜Y-C3 の場面のテスト、3.4 の前提が成り立たないときの扱い | Claude | IT-12・IT-13 に足し、3.4 に書いた |
| Y-C8 | 公開の前景サービスの Intent を予約の通知に使うと、ライブラリのクラスが Alarm に入る | Claude | 「ライブラリが Alarm に入れるもの」に言い方を狭め、KDoc とマニュアルに書く |
| Y-C9 | UseCase を置かない口の根拠の引用が違う | Claude | `android.md` に UseCase を置かない条件を書く。`NotificationResourceResolver` を presentation へ |
| Y-C10 | `ScheduleLock` で main が書き込みを待ちうる | Claude | RK-10 と KDoc を直した |
| Y-X5 | 付録 A が Kotlin としてそのままでは通らない、Share の追加がコメント | Codex | 付録 A を「擬似宣言（本体を省く）」と明記し、Share の追加を宣言にした |
| Y-X6 | 更新をまたぐ Alarm の互換を実物で確かめていない | Codex | IT-26（2 つの版の APK） |

## 区分 C

Y-C11〜Y-C22 は第 4 版で直した（`identifier` の言い方、`MainThread` の名前、`ShareUseCases` の `val`、Share の port の形、権限の `commitNow` の失敗の値、保存しない予約の世代、保存の場所とバックアップ、知らない版のファイル、アクションの検査と世代の順、RG の宣言と `AndroidDialogFragment` の口、`iconBytes`、1.x の破棄の手順 6 の言い方）。

## 止め方（サーキットブレーカー）

予約（8.6）の A が 1 回目（W-X10、W-C4）、2 回目（X-C1〜X-C3）、3 回目（Y-C1〜Y-C4、Y-X1）と 3 回続いた。原因は、保存の形を変えるのに合わせて流れ（順序、契機、対象、失敗の後の状態）まで設計し直したことにある。第 4 版では**今の流れを 1 行ずつ写し、変えるのは直列化の形と書き方だけ**という原則にし、変える所を対応表（8.6）で今のコードの行と並べた。4 回目のレビューで A が 0 になったかを確かめる。
