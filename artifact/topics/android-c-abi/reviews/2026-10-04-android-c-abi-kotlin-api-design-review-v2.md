# レビュー結果（Kotlin の API の補完の設計書・2 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`（第 2 版）
- トピック名: android-c-abi（Kotlin の API の補完）
- 判定: **要修正**（新しい A が Claude 7 件、Codex 7 件。第 3 版で反映した）
- 別モデルによる独立レビュー: 実施済み（1 回目とは別の Claude のサブエージェントと Codex の 2 者で並行）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0

ID の `X-C` は Claude、`X-X` は Codex。

## 1 回目の区分 A の確認

| 判定 | Claude（16 行にまとめた） | Codex（21 件） |
|---|---|---|
| 直った | 12 | 13 |
| 一部だけ | 4（W-X1/W-C1、W-X2、W-X10/W-C4、W-X11/W-C7） | 8（W-X2、W-X10、W-X11、W-X12、W-X14、W-C4、W-C5、W-C7） |
| 直っていない | 0 | 0 |

一部だけのものは、下の新しい A に含まれる。

## 区分 A

| ID | 問題 | 出典 | 対処（第 3 版） |
|---|---|---|---|
| X-C1、X-X2 | Alarm の extra の Parcel が更新をまたいで読めなくなる道が残る（`-keepnames` の範囲の漏れ、項目の追加、読めないときに落ちる） | 両方 | Alarm の extra を「ライブラリのデータは JSON の文字列、利用者の `Intent` と `Bitmap` は OS の Parcelable」に分けた。ライブラリの Parcelable は Alarm に入らない。読めないときは捨ててログ。JSON の版の規則（8.6） |
| X-C2 | `FLAG_NO_CREATE` で「Alarm がまだある」を判定するのは更新の後に誤る | Claude | 判定をやめた。`MY_PACKAGE_REPLACED` では新しい形の予約を置き直さない（Alarm は更新の後も残る。期限の過ぎたものは Alarm が出す）。再起動の後だけ置き直す（8.6） |
| X-C3、X-X8 の一部、W-X10 の残り | 書き戻しの前提が誤り（PendingIntent を作った時点で前の extra が置き換わる）。put・Alarm・戻しが 1 つの排他でない | 両方 | 予約の操作・取り消し・発火の後の削除・再起動の後の置き直しを 1 つのロックで行う。失敗の後は「その鍵の予約は無い」（Alarm を消し、保存を消す）と定めた（3.3、8.6） |
| X-C4 | 既存の `shareWithCallback` に 2 段の更新を当てると、開けなかったときに前の待ちが残る（K-4 に反する） | Claude | 2 段の更新をやめ、今と同じく受け付けた時点で前の待ちを消す。AC-22 の「開かなかった Share は前の待ちを消さない」は `NOT_FOREGROUND` のときだけで、受け口が Kotlin を呼ぶ前に判定する（8.9） |
| X-C5 | 宿主の記録がいつ消えるかが無く、表が食い違う。取り消しなどで宿主が残る | Claude | 宿主の記録の寿命と、宿主が「ライブラリの Fragment が無くなったら閉じる」を、Fragment が消えるすべての経路から呼ぶ形にした（8.3） |
| X-C6 | `fullScreenLaunch` がアプリの起動の Intent に data を付け、偽の deep link になる | Claude | `Intent.setIdentifier` で区別する（8.5） |
| X-C7、X-X7 の一部 | 結果を待つ Share に Manager と `suspend` 版が無い。開く操作と選択のイベントの接続が無い | 両方 | 新しい口は「開く（同期、印を返す）」と「選択のイベント（`ShareEvents.selections`）」に分けた（AC-22 と同じ形）。待つ操作が無いので `suspend` 版は要らない（8.9） |
| X-X1、W-X2 の残り | Manager・UseCase の経路の欠け、Port に Android の型 | Codex | 公開の口ごとの層の表（6.3）。Android の Manager の役は機能ごとの `*UseCases`（集約）と presentation の Delegate の持ち主、と `android.md` に書く。設定の画面に UseCase と port を置いた。前景サービスの codec の port をやめた。notification の port が application の model（Android の型を含む）を使うのは、既存の `NotificationCommandRepository` と同じ例外として `android.md` に書く |
| X-X3、W-X11 の残り | 権限の要求の会と、個々の要求の門の関係が無い | Codex | 会の状態の表を、個々の待ちの門と分けて書いた（8.7） |
| X-X4 | `ShareCallbackCoordinator` のロックの中で利用者の関数を呼ぶ | Codex | ロックの中は印の照合と取り出しだけ（8.9） |
| X-X5 | アクションの無い Share で前の世代が残る | Codex | どの `shareText` も世代を上げる（8.9） |
| X-X6 | `NotificationShownSupport` を「移す」と「残す」が食い違う | Codex | 今の名前のまま残し、新しいイベントを別に置く（8.13、8.14） |
| X-X7 | 公開の宣言が実装できる精度で無い | Codex | 付録 A に公開の宣言を書いた |
| W-X14 の残り | 1.x の破棄で、要素の取り消しが失敗しても印を書く | Codex | 失敗した要素があれば `SharedPreferences` を残し、印を書かずに次の契機でやり直す（8.6） |
| W-X12、W-C5 の残り | `ShareContent.toString()` の上書きは公開の型の動作を変える | Codex（Claude は B） | 上書きをやめ、ログの箇所で長さだけを出す（8.11） |

## 区分 B・C（主なもの）

| ID | 問題 | 対処 |
|---|---|---|
| Claude の B | KA-17 が C ABI の設計書の C-4（受け口が判定する）と食い違う | 受け口は C-4 のとおり判定する。Kotlin の側の判定は、その後に状況が変わった場合にも同じ値で完了するためのもの（8.15） |
| Claude の B | `EventHub` の戻した残りが届かないことがある | 戻した残りは、残っている最も古い受け手に続けて渡す（8.4） |
| Claude の B | 権限の port が Context を持たず、未初期化のときに許可済みを判定できない | port の実装が Application の Context を持つ（Manager が作る）（8.7） |
| X-X8 | 予約の競合のテスト | IT-12 に、2 つの予約の交差、置き直しと予約の交差、戻しの失敗を足した |
| X-X9 | 更新をまたぐ Parcel のテスト | Alarm の extra にライブラリのクラスが無いことを確かめるテスト（IT-24）。JSON の古い版を読むテスト（UT-08） |
| X-X10 | 機械照合の SKIP | 15 章の DoD（実装の後の名前の照合）。照合の拡張はこのトピックの外 |
| X-X11 | 権限の検査の区分 | 4 つは実行のテスト、前景サービスの 3 つは manifest の merge の静的な検査とマニュアル（8.12） |
| X-X12 | `DialogError` の形 | enum で 4 つの値（付録 A） |
| Claude の C | `toUri` の表の `sourceBounds`、世代の詰め方、Share の印の型、`FOREGROUND_SERVICE` で CallStyle も失敗 | 直した |

## 総合評価

1 回目の A は 2 者とも「直っていない」が 0 になった。新しい A は、(1) 更新をまたぐ保存の互換、(2) 状態の表の細部（宿主の記録、権限の会、予約の排他）、(3) 層の規則の当て方、(4) 公開の宣言の精度、に集まった。(3) は 2 回続いたので、Android での Manager の役と port の例外を `android.md` に規則として書く形で閉じる（サーキットブレーカーの「仕組みを直す」）。3 回目のレビューで A が 0 になったかを確かめる。
