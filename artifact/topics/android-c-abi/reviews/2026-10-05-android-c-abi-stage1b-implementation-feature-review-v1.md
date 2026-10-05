# レビュー結果（段階 1b の実装・1 回目）

- 日付: 2026-10-05
- レビュー対象: ブランチ `feature/NTKIT-17`、`git diff b4e54ce0..HEAD`（`16eda22b`〜`95184759`）。中心は `android/android_library/src/main` とそのテスト、サンプル、`releaseProbe`、`scripts/test_android.sh`
- 設計書: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`
- 実装結果: `artifact/topics/android-c-abi/results/2026-10-05-android-c-abi-stage1b-implementation-feature-result-v1.md`
- レビュアー: Claude のサブエージェント（`general-purpose`。設計との整合、規則、テストの網羅、実装結果の記述）と Codex（`gpt-5.6-sol`、`medium`。ライブラリのコードのスレッド・寿命・ちょうど 1 回・競合）の 2 本。観点が 2 つに分かれるので 2 本にした
- 総合評価: **要修正（重大）**（Codex が A を 1 件出した。直した後の確かめは末尾）

ID の `I-C` は Claude、`I-X` は Codex。区分はワークフローの止める基準（A: 利用者から見た動作が変わる、B: 検証の穴、C: 記述だけ）。

## 設計書整合性チェック（Claude）

| 項目 | 判定 |
|---|---|
| 企画書との整合性 | ○ |
| Clean Architecture 準拠 | △（data から presentation への依存が 3 か所あり、記録が無かった。I-C1） |
| 既存実装との差分分析の正確性 | ○ |
| テスト設計の網羅性 | △（I-C9〜I-C14） |
| ドメインエラー全ケース実装 | ○（`DialogDomainError.Canceled` のテストが無かった。I-C10） |
| エラーコード/メッセージ対応表との整合 | ○（`ClipboardErrorCode` の 7 つ） |

## プロジェクトルール適合チェック（Claude）

common.md △（I-C1）、android.md △（I-C6〜I-C8）、エラー契約反映 ○、既存 API 互換性 ○（I-C19 のソースの互換は記録が要る）。

## 区分 A

| ID | 問題 | 確かめた結果 | 対処 |
|---|---|---|---|
| I-X1 | `addOnInitializedListener` の利用者の関数を、例外を捕まえずに main の `Handler` に積んでいる。設計 6.2 は「新しい完了のコールバックの例外は、ライブラリが捕まえてログを出し、続ける」 | 正しい（`InitializationState.kt` の `succeed` と `addListener` が `post(listener)` をそのまま呼ぶ。投げるとアプリが落ちる） | 積むときに `try` で包み、`Exception` を捕まえてログを出す（`EventHub` と同じ）。単体テスト `aThrowingListener_doesNotStopTheOthers` を足した |

## 区分 B

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| I-X2 | 型のある Chooser Action の受け手で、世代の照合と `emit` の間に、ほかのスレッドの新しい Share が世代を上げると、古いアクションが届きうる | Codex（要確認） | 記録して先へ（設計 0.8）。照合の時点を区切りとみなす。新しい Share を開く操作と同時に古い Chooser のアクションを押したときだけで、`emit` はロックの外で行う決まり（利用者のコードをロックの中で呼ばない）とも両立する |
| I-X3 | Alarm の extra の command の JSON は版（`v`）を書くが、読むときに確かめていない（設計 8.6 は「版の規則は上と同じ」） | Codex | 直した。版が違えば `JSONException` を投げ、受け手は表示しない（欄が無ければ版 1）。codec のテストを 1 件足した |
| I-C9 | UT-08 の「利用者の関数はロックの外で呼ぶ」が確かめになっていない（ロックは同じスレッドで入り直せる） | Claude | 直した。コールバックの中から別のスレッドで `cancel`・`register` を呼び、終わるのを待つ |
| I-C10 | IT-03 の `suspend` 版で `DialogDomainError.Canceled` を確かめるテストが無い | Claude | 足した（宿主を外から閉じて `Canceled(HOST_DESTROYED)`） |
| I-C11 | IT-21 の Clipboard の確かめが常に真。予約の経路を通っていない | Claude | 直した。読み戻した本文を比べ、予約（`data` が Alarm の JSON と保存に入る）も通す |
| I-C12 | IT-07 の `suspend` 版の例外は `ManagersTest`（偽物の port）だけ。プロセスの死の後は「launch しない」を直接には見ていない | Claude | 記録して先へ（実装結果 5.1 を △ にした） |
| I-C13 | IT-19 の実行の検査は権限の問い合わせと要求だけ | Claude | 記録して先へ（5.1 の注記を広げた） |
| I-C14 | IT-25 のカスタムビューの動作は数を比べない。IT-26 の `Bitmap` は欠けていないことだけ | Claude | 記録して先へ（5.1 を △ にした） |
| I-C15 | UT-03・UT-06・IT-12・IT-27 の △ の注記に欠け | Claude | 記録を直した |
| I-C16 | 実装結果の変異の数（T-23 は 22）と、途中で落ちなかった変異の記録 | Claude | 直した（作業メモにも記録を足した） |

## 区分 C

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| I-C1 | data から presentation への依存が 3 か所（`ShareRepositoryImpl` → `ShareChooserActionReceiver`、`ShareCallbackCoordinator` → `ShareEvents`、`ScheduledNotificationReceiver` → `NotificationEvents`） | Claude | 設計 4.1 に例外として書き、実装結果 1.2 にも書いた |
| I-C2 | `kotlinx-coroutines-core` の依存が 6.1 の「ほかに」に無い | Claude | 実装結果 1.2 に書いた |
| I-C3 | `finishIfIdle` が取り除かれている途中の Fragment を数えない（8.3 に無い詳細） | Claude | 実装結果 1.2 に書いた |
| I-C4 | `MainPoster.isMainThread()`（RG）が付録 A に無い | Claude | 実装結果 1.2 と 6 章に書いた |
| I-C5 | 設計 8.12 に「IT-19 の版はサンプルの flavor」が残る | Claude | 直した |
| I-C6 | 先頭の `Log.d` が無い関数 | Claude | 直した（`UiHost`・`FragmentPermissionRequester` の環境の関数、`MainPoster`、`LogRedaction`。`LogRedaction` は長さだけを出す）。domain の 2 つ（`ClipboardErrorCode`、`DialogError`）は `android.util.Log` を使わない層の規則を優先し、実装結果 1.2 に書いた |
| I-C7 | 新しいコードの TAG がクラスの完全名でない 5 か所 | Claude | 直した |
| I-C8 | `AndroidDialogFragment` の KDoc の位置がずれ、`setDialogListener` に KDoc が無い | Claude | 直した |
| I-C17 | 実装結果の「androidx.startup 1.1.1」は 1.2.0 | Claude | 直した |
| I-C18 | 実装結果の CU-03 の根拠が作業メモにしか無い。存在しない節（4.3）を指す | Claude | 実装結果に 5.3 を足し、参照を直した |
| I-C19 | 公開の sealed class `ShareDomainError` に `InvalidChooserAction` を足したので、利用者の網羅的な `when` のソースの互換が壊れる | Claude | 記録（設計 0.8、実装結果 7 章） |
| I-C20 | `ShareTextUseCase` の `@Deprecated` が JSON を渡さない呼び出しにも警告を出す | Claude | 記録（設計 0.8、実装結果 7 章） |
| I-C21 | 実装結果 1.2 の「初めて UseCase を作るとき」は実装（呼ぶたびに済みかを見る）と言い方が違う。Boot の受け手から呼ぶ所が無い | Claude | 直した |

## 直した後の確かめ（2026-10-05）

| ID | 確かめ |
|---|---|
| I-X1 | 単体テストが通る。捕まえる例外を `IllegalArgumentException` に狭める変異で落ちる |
| I-X3 | codec のテスト（12 件）が両方の環境で通る。版の判定を 1 つずらす変異で落ちる |
| I-C9 | 単体テストが通る。コールバックを関数 1 つを挟んでロックの中で呼ぶ変異で落ちる（前の形では通っていた） |
| I-C10 | `AndroidDialogManagerTest`（14 件）が両方の環境で通る。`suspend` 版で `Canceled` を別の例外に写す変異で落ちる |
| I-C11 | `LogSentinelTest` が両方の環境で通る。予約の保存が JSON をログに出す変異で落ちる |
| I-C6〜I-C8 | 単体テスト（166 件）が通る |

## 総合評価

A は I-X1 の 1 件で、直した。B は中心の契約に当たるもの（I-X3 の版、I-C9 のロックの外、I-C10・I-C11）を直し、網羅系（I-C12〜I-C15）と I-X2 は理由つきで記録した。C は安いものを直し、残りは記録した。止める基準の 3 条件のうち、1（レビュアーを替えて 1 回通す。この回で Claude と Codex の 2 本）と 3（直さない残件を設計書 0.8 に理由つきで書いた）は満たす。2（足した検査が壊すと落ちる）は上の表で確かめた。A を直したので、直した所を Codex 1 本で確かめる（下に追記する）。

## Codex による修正の確かめ（2026-10-05）

- A: なし（`InitializationState` の包みは、後の利用者の関数を妨げない。足した `Log.d` に秘密の値は出ない。小さな関数の動作は変わらない。保存のファイルの経路の `decodeCommand` は壊れていない）
- I-X2（Chooser Action の隙間）を受け入れた判断は妥当（世代の照合を区切りとみなせば、照合が先なら古い操作が先、世代を上げるのが先なら捨てる）
- B: (1) 版の判定が `optInt` なので、`v` が整数でない（`{}` など）ときに今の版として読む → 整数の版だけを受け付ける形に直し、`{}`・`"x"`・`1.5` のテストを足した（直す途中で `1.5` を数として 1 に丸めて通していたのに気づき、整数だけにした）。(2) UT-08 は、別のスレッドが 2 秒待った後にコールバックが終わってから `register` が済めば通ってしまう → コールバックの中で「戻る前に別のスレッドの呼び出しが終わったか」を記録し、それを確かめる形に直した
- C: なし

| 直し | 確かめ |
|---|---|
| 版の判定 | codec のテスト（12 件）と `ScheduleFlowTest`（26 件）が両方の環境で通る。`optInt` に戻す変異で落ちる |
| UT-08 | 単体テストが通る。コールバックをロックの中で呼ぶ変異で 3 回とも落ちる |
| レビューの直しの全体 | ライブラリの instrumented テストの全体（153 件と、権限を外した 4 件・3 件）が両方の環境で通る（版の判定を整数だけにする前のソース。その後の直しは codec の 1 か所で、上の 2 クラスを流し直した） |

止める基準: A が 0。レビュアーを替えて 1 回通した（1 回目に Claude と Codex）。足した検査は壊すと落ちることを確かめた。直さない残件（I-X2、I-C12〜I-C15、I-C19、I-C20）は設計書 0.8 と実装結果に理由つきで書いた。ここで止める。

