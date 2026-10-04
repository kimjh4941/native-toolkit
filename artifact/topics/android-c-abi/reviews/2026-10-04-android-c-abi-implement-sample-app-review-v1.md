# レビュー結果（段階 1b のサンプルの実装・1 回目）

- 日付: 2026-10-04
- レビュー対象: ブランチ `feature/NTKIT-17` の未コミットの差分（`android/AndroidLibraryExample/app/src/`、`scripts/test_android.sh`）
- 計画: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-sample-app-design-v3.md`
- 実装結果: `artifact/topics/android-c-abi/results/2026-10-04-android-c-abi-implement-sample-app-result-v1.md`
- レビュアー: Claude のサブエージェント（`general-purpose`。計画との一致・規則・試験の書き方）と Codex（`gpt-5.6-sol`、`medium`。寿命とスレッドの正しさ）の 2 本。観点が 2 つに分かれるので 2 本にした
- 総合評価: **要修正（重大）**（Codex が A を出した。確かめた結果、A は 2 件）

ID の `I-C` は Claude、`I-X` は Codex。区分はワークフローの止める基準（A: 利用者から見た動作が変わる、B: 検証の穴、C: 記述だけ）。

## 計画書整合性チェック（Claude）

| 項目 | 判定 |
|---|---|
| 全セクション・全ボタンの実装 | ○（testTag・文言・要求の値・options・`launchApp`・`actionId`・`data` の `label`・初期の文言がすべて一致） |
| API 呼び出し方針の一致 | ○（例外は計画 2.2 の 2 か所だけ） |
| システム設定（Manifest） | ○ |
| 変更ファイル一覧との diff 整合 | △（UI テストの設計書が未更新。I-C3） |
| 計画との差分の result への記録 | △（I-C3 と、n10・n11 の書き方。I-C2） |

## サンプルアプリパターン適合チェック（Claude）

メニュー導線 ○、画面構成 ○、成功・失敗の表示 ○、共通 UI 部品 ○。

## プロジェクトルール適合チェック（Claude）

common.md ○、android.md △（I-C9）、依存の向き ○（Unity にも、プラットフォームの API の直接の呼び出しにも依存しない）、Log.d △（I-C9）、KDoc ○。

## 区分 A

| ID | 問題 | 確かめた結果 | 対処 |
|---|---|---|---|
| I-X2 | Dialog の callback 版は、画面の `onResult` をプロセス全体の presenter が持つ。MainActivity が作り直されると、復元された Dialog の結果は古い `MainRouter` の状態に入り、新しい画面に出ない。2 秒後の取り消しは composition の scope にあるので、作り直しで取り消しが消え、Dialog だけが残る | 正しい（`FragmentDialogPresenter.kt:29-65` が `onResult` を要求ごとに持つ。`DialogSampleScreen.kt:188` の `scope` は composition に属する） | 結果は「今の画面の受け口」へ渡す（プロセスで 1 つの小さな受け口を置き、画面が出ている間だけ自分の状態を登録する。文言は今と同じく `MainRouter` の `rememberSaveable` で持つ）。2 秒後の取り消しは main の Handler で行う。`DialogUiTest` に作り直しの 2 件を足す |
| I-X3 | 通知の権限の callback 版も、作り直しの後に古い画面の `statusText` を更新する（権限の会は作り直しをまたいで続く） | 正しい | I-X2 と同じ受け口で、今の通知の画面の `statusText` へ渡す（画面に入り直すと初期の文言に戻る今の動作（`NavigationUiTest.m04`）は保つ） |

## 区分 A でないと判断したもの

| ID | 問題 | 判断 |
|---|---|---|
| I-X1 | アプリが動いていないときに `launchApp = true` の通知を押すと、イベントは MainActivity の登録の中（画面より前）で渡り、BODY_TAP は捨てられ、メディアのアクションは Toast になる | 計画 4.2 のとおりの動作。プロセスから起動したときは画面がメインメニューから始まり、通知の画面は出ていない（BODY_TAP は「通知の画面が出ていれば」表示する。ACTION は出ていなければ Toast）。今までも本文のタップは画面に何も出していなかった。C として結果に書く |

## 区分 B

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| I-C1 | s20 は、アイコンが読めない（`byteArrayOf(0)`）ことでも同じ `InvalidChooserAction(dup)` が出るので、重複の検査が壊れても通る。Sharesheet が開かないことも見ていない | Claude | 読めるアイコン（Custom と同じ PNG）にし、2 つ目だけ id を重複させる。Sharesheet が出ないことも確かめる |
| I-C2 | 追加したホストの状態のケース n10・n11 が実行されていない | Claude | **事実と違う**。全体の実行でスクリプトが `HOST_STATE_CASES` も流し、2 件とも両方の環境で成功している（実行の結果に `n10…: passed`）。実装結果の「ホストのケースなし」が、再起動を伴う H-01〜H-04 のことだと分からない書き方だったので、文書を直す |
| I-X4 | Share と Clipboard の画面を閉じたときの後始末（待ちの取り消し、監視の停止）を UI テストが見ていない | Codex | 記録して先へ。待ちの取り消しはライブラリの IT-15、監視の停止は IT-17 で確かめている。画面の後始末は 1 行の呼び出しで、網羅系の穴として扱う |
| I-X6 | `Toasts.count` は Toast の個体ではなく、部分一致するアクセシビリティのイベントの数を数える | Codex | 記録して先へ（両方の環境で n61 は 1 件で通った） |

## 区分 C・軽微

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| I-C3 | 計画 8 章が変更に挙げた UI テストの設計書が更新されておらず、先送りの記録も無い | Claude | 実装結果の 5 章（T-23 へ書くこと）に記録する |
| I-C4 | s18 は開いたときの印と選んだ後の印が同じかを比べていない | Claude | 比べる |
| I-C5 | s19 の取り消しの確かめは、画面が書く文言だけを見る | Claude | 取り消しの契約はライブラリの IT-15 で確かめているとコメントに書く |
| I-C6 | n60 は入り直した直後に「#0」を 1 回見るだけ | Claude | 少し待ってから見直す |
| I-C7 | `ShareUiTest` の `shareTo` の KDoc が s18 に付いている | Claude | 直す |
| I-C8 | 古い KDoc と文言（`ShareSampleScreen` の `[ShareUseCases]`、通知の本文の「BroadcastReceiver callback」） | Claude | 直す |
| I-C9 | `DialogSampleScreen` の `show` の `Log.d` に引数が無い。コルーチン版と取り消しのボタンに `Log.d` が無く、取り消しのボタンは `IllegalArgumentException` の捕まえ方が他とそろっていない | Claude | 直す |
| I-C10 | 通知の画面の DISMISS の分岐には届かない（`SampleEvents` は DISMISS を画面へ渡さない） | Claude | 届かないことをコメントに書く（`when` は網羅が要るので分岐は残す） |
| I-C11 | 実装結果の「足した UI テスト 12 件」が数えにくい | Claude | 10 件（普段の実行）と 2 件（ホストの状態）に分けて書く |
| I-X5 | `subscriptionCount` の確かめと `tryEmit` は不可分ではなく、隙間でアクションが Toast にもならず消えうる | Codex | 計画 4.2 で受け入れた隙間（S2-C3）。記録のまま |

## 総合評価

A は I-X2 と I-X3 の 2 件で、どちらも「Activity の作り直しをまたいで、ライブラリの callback が古い画面の状態に届く」という同じ種類の問題である。サンプルは利用者の手本になるので、結果を今の画面へ渡す形に直す。今までの `AndroidDialogFragment` の listener の形でも作り直しで結果は失われていたので、退行ではない。B は s20 を直し、ほかは記録する。直した後は、直した所を Codex 1 本で確かめる（レビュアーを替えて 1 回通す条件は、この回で Claude と Codex の 2 本を通したので満たしている）。

## 直した後の確かめ（2026-10-04）

| ID | 直し | 確かめ |
|---|---|---|
| I-X2（取り消し） | 2 秒後の取り消しを main の Handler で行う | `DialogUiTest.d21` を足した。取り消しを composition の scope に戻すと落ちる |
| I-X2（結果） | Dialog の結果を `ScreenResults.dialog`（router が登録する受け口）へ渡す | `DialogUiTest.d20` を足し、両方の環境で成功。ただし受け口が古い router を持ち続ける形に壊しても d20 は通った。**観測した事実**: その形で流すと、古い router の受け口が文言を書いた直後に、新しい画面が書かれた文言で描き直された（デバッグのログで確かめた）。**理由（仮説。確かめていない）**: `MainRouter` の文言は `rememberSaveable` で持ち、プロセスの中での作り直し（`Activity.recreate()`）では保存の Bundle が parcel されずに渡るので、Parcelable の `MutableState` が同じオブジェクトのまま復元されたのかもしれない（Codex の 2 回目の確かめは、saver は通常新しい `MutableState` を作るとして、この説明に異を唱えた）。どちらにしても、この持ち方では結果の部分の不具合は観測されなかった。受け口は、結果を今の画面へ明示的に渡す形の手本として残し、受け口そのものの差し替えと外す順序は `ScreenResultSinkInstrumentedTest` で確かめる（Codex の 2 回目の確かめの B） |
| I-X3 | 権限の callback 版の答えを `ScreenResults.notificationStatus`（通知の画面が登録する受け口）へ渡す | `NotificationHostStateUiTest.n12` を足した（権限を外した状態で要求し、ダイアログが出ている間に MainActivity を作り直してから許可する）。両方の環境で成功。受け口を通さず画面の状態へ直接書く形に戻すと落ちる。通知の画面の文言は `remember` で持つので、こちらは実際に起きていた |
| I-C1 | s20 は読める PNG で id だけを重複させ、Sharesheet が開かないことも確かめる | UseCase と repository の重複の検査を外すと落ちる |

- n12 を書く途中で分かったこと: `ActivityScenario.recreate()` は作り直しの後に RESUMED を待つので、権限のダイアログが上にある間は使えない。Activity 自身の `recreate()` を使った。また Compose の試験の規則が入っている間は描き直しの時計を試験の側が進めるので、UiAutomator だけで待つと画面が描き直されない。`compose.waitUntil` の中で読む

## Codex による修正の確かめ（2026-10-04）

- A: なし（直したコードに、利用者から見た不具合は残っていない）
- B: 受け口そのものの差し替えと外す順序の確かめが無い → `ScreenResultSinkInstrumentedTest` を足した（両方の環境で 3 件成功。外すときに誰の登録かを見ない形に壊すと落ちる）
- C: `rememberSaveable` の説明は言い切れない → 観測した事実と仮説に分けて書き直した（上の表）。実装結果の件数が古い → 直した

止める基準: A が 0、レビュアーを替えて 1 回通した（1 回目に Claude と Codex）、足した検査は壊すと落ちることを確かめた（d20 だけは落ちず、理由と扱いを書いた）、直さない残件（I-X1、I-X4、I-X5、I-X6）は実装結果に理由つきで書いた。ここで止める。

