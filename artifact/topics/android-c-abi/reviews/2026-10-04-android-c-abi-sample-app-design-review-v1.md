# レビュー結果（段階 1b のサンプルの設計書・1 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-sample-app-design-v1.md`（第 1 版）
- トピック名: android-c-abi（段階 1b のサンプル）
- 対象 OS: Android
- 判定: **要修正**（A が 3 件。第 2 版で反映する）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェント（`general-purpose`）と Codex（`gpt-5.6-sol`、`medium`）の 2 者で並行）
- 機械照合: サンプルの計画書なので `check_design_consistency.py` は対象外。Codex が `scripts/check_sample_app_inputs.py` を流し、98 ファイルで成功（入力欄なし）

ID の `S-C` は Claude、`S-X` は Codex。

## 強み（2 者で一致）

- 2.1 の口の名前・引数・結果の型は、4 つの Manager と `NotificationEventIntents`・`DialogResult` の実装とすべて合っている
- 既存の文言（「✅ Action button pressed: …」、アクション・dismiss・Chooser Action の Toast、設定の 3 つの ℹ️、権限の Granted / Denied）は、`NotificationInteraction` の欄と `data` の `label` でそのまま出せる
- サンプルは `android_library` だけに依存し、Unity のプラグインからしか届かない機能は無い
- 入力欄は無い。ログインの結果を長さだけにする点はログの規則と UI テストの設計書 3.8 に合う
- イベントの行を `statusText` と分けた点は、既存のテストの文言を守る
- S-1（rationale だけ `NotificationPermissionHelper`）と CallStyle の扱いは、既存の公開の口を使うので受け入れられる（ただし S-C5 の記録が要る）

## 区分 A

| ID | 問題 | 出典 | 対処（第 2 版） |
|---|---|---|---|
| S-X1、S-C1 | メディアの 3 つのアクションを `NotificationEventIntents.action(...)` にすると `launchApp` の既定値が `false` で broadcast になり、アプリが前に出ない。`NotificationTapUiTest.n28_mediaActionBringsTheSampleBack`（`NotificationTapUiTest.kt:38-48`）が落ちる | 両方 | メディアの 3 つは `launchApp = true` と明記する。n28 に、前に出た後の `statusText`（「✅ Action button pressed: Previous …」）の確かめを足す |
| S-X2、S-C2 | Dialog を Manager に替える範囲が「結果の文言」だけと書かれているが、実際は (1) 例の題・本文が今の「Hello from Android」と違い `DialogUiTest.d01` と `NavigationUiTest`（`NavigationUiTest.kt:35-44`）が落ちる、(2) `DialogOptions` の既定値（`cancelable=true`）が今のサンプル（全部 `false`）と違い D-16 が落ちる、(3) d11・d14 は入力の値そのものを期待値にしている。`NavigationUiTest.kt` が変更ファイルの一覧に無い | 両方 | 6 つの要求の題・本文・ボタン・項目・既定の選択は今の値を保ち、options は `DialogOptions(cancelable = false, cancelableOnTouchOutside = false)` と明記する。`Dismissed` を見せるボタンは別に足す。直す期待値をケースの ID（d01〜d15、`NavigationUiTest`）で列挙する。d11・d14 は値ではなく長さを確かめる形に直す（ログの規則。理由を結果に書く）。`NavigationUiTest.kt` を変更に足す |
| S-C3、S-X4 | 手動の項目「アプリを閉じた状態でアクションを押す」の理由「状態を誘発できない」は成り立たない。受け手は MainActivity の寿命に結びつくので、Activity を壊す（プロセスは残す）→ シェードで押す → 起動 → Toast、で自動化できる。プロセスを止めた後まで保つように読める書き方も契約（プロセスの寿命まで）より強い | 両方 | UI テスト（`NotificationInteractionUiTest`）へ移し、6 章は「なし」にする。保ちはプロセスの寿命までと書く |

## 区分 B

| ID | 問題 | 出典 | 対処（第 2 版） |
|---|---|---|---|
| S-C4、S-X3 | イベントの受け渡しの形が足りない。`MutableStateFlow` は最後の値を再生し、等しい値を捨てる（`NotificationInteraction` は値で比べる）ので、画面に入り直すと前のイベントが再び出て、同じイベントの 2 回目が届かない。MainActivity が無い間は Toast が次の起動まで遅れ（今の Receiver はその場）、同じプロセスで続けて流す試験の間でイベントが漏れうる | 両方 | 画面へは再生しない `SharedFlow`（replay 0）で渡し、「画面が出ているか」は購読の数で判定する。Toast の時機の違い（Activity が無い間は次の起動で出る）を明記する。UI テストの前に保たれたイベントを捨てる方針（`DeviceState` で受け手を一度足して外す）を書く。Activity の作り直しで二重にならないこと（`singleTask`・縦固定。作り直しでも受け手は 1 つ）を UI テストで確かめる |
| S-C5 | CallStyle の前景サービスと rationale は Manager に口が無い。`common.md` はこれを機能設計の不足として差し戻すよう求め、マニュアルは Manager を勧める入口として書く | Claude | Kotlin の API の設計書に「Manager に無い口」として記録し、段階 2 以降（C ABI の第 2 部、マニュアル）へ申し送る。`NotificationPermissionHelper` は今と同じく `MainActivity.onCreate` で作り、`AppRouter` から渡すと明記する |
| S-X5 | `InvalidChooserAction(id)` を見せる画面とテストが無い | Codex | 固定の不正な値（重複した id）のボタンを 1 つ足し、エラーの表示とテストを書く |
| S-X6 | `ShareSelection.packageName` は `null` になりうるが、表示の文言が無い | Codex | `null` の文言（「✅ Selected (token=<印>): (unknown package)」）を決める |
| S-C6 | UI テストの表が不正確。`TagInventoryTest` は足さなくても落ちない。Receiver の置き換えの影響を受けるテストが名前で挙がっていない。UI テストの設計書（2026-10-03 版）を直すかが無い | Claude | 「直す」を「足す」に。影響を受けるテスト（`NotificationStyleUiTest.n16`、`NotificationInteractionUiTest.n22・n24〜n26`、`NotificationTapUiTest.n28`、`ShareUiTest.s04`）を名前で挙げる。UI テストの設計書は、足したケースを 1b の実装の後に追記する |
| S-C7 | Dialog の結果の持ち方 | Claude | 画面の中へ移すときも `rememberSaveable` を保つ |
| S-C8 | Share の画面の破棄で呼ぶ `cancelPendingCallback()` が、選択の待ちも消すことが書かれていない | Claude | 明記する（Kotlin の API の設計書 8.9 の `cancel()`） |

## 区分 C

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| S-X7、S-C9 | `MainMenuScreen.kt` が 3.3 では「変更」、8 章では「変えない」 | 両方 | 「変えない」にそろえる |
| S-X8、S-C10 | Chooser Action のアイコンは今の `android.R.drawable.ic_menu_edit` を PNG にする処理（`ShareSampleScreen.kt:242-252`）を使える | 両方 | 明記し、9 章から外す |
| S-C11 | `DialogDomainError.Unavailable` の欄は `error`。取り消しの記号が callback 版（ℹ️）と `suspend` 版（❌）でそろっていない | Claude | 欄の名前を直し、記号をそろえる |
| S-C12 | `data = label` は略記 | Claude | `data = mapOf("label" to "Accept")` と書く |
| S-C13 | `HostPhaseTest` と `infra/DeviceState.kt` が既存の口を直接使う | Claude | 8 章の「変えない」に書く |

## 総合評価

2 者とも、口の照合、Manager にそろえる方針、iOS と対の形、文言の対応づけは正確と評価した。一方、メディアのアクションの `launchApp`、Dialog の要求の値と options、手動の項目の理由の 3 点は、このまま実装すると 0d の基準が壊れるか規則に反する。A の 3 件と B のイベントの受け渡しの形を直して第 2 版にし、直した所を確かめる。
