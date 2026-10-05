# レビュー結果（C ABI の設計書 第 2 部・1 回目）

- 日付: 2026-10-05
- レビュー対象: `artifact/topics/android-c-abi/designs/2026-10-05-android-c-abi-c-abi-design-part2.md`（第 1 版）
- レビュアー: Claude のサブエージェント（`general-purpose`。企画書・第 1 部・Kotlin の設計書との整合、対応表の網羅、テストとタスク）と Codex（`gpt-5.6-sol`、`medium`。C ABI としての正しさ: スレッド、所有権、エラーの意味、構造体の配置、Android の API を呼び出しスレッドで呼んでよいか）の 2 本。観点が 2 つに分かれるので 2 本にした
- 総合評価: **要修正（重大）**（A が 6 件。重なりを除く）

ID の `W-C` は Claude、`W-X` は Codex。区分は止める基準（A: 実装か後の段を誤らせる、B: 検証の穴か記録の要る決定、C: 記述）。

## 確かめて合っていたこと

- 付録 A の関数は 156 で重複が無く、8.2 の群ごとの数と合う（Claude）。8.3 はブリッジの 69 メソッドを 1 回ずつ、10 章は README 6 章の 45 の操作を挙げる（Claude）
- 8.1 の Kotlin の口はすべて実在し、`ClipboardErrorCode` と `ShareDomainError` の並びは 11 章と合う（Claude）
- 同期にした経路（Clipboard の読み書き、通知、Alarm、予約のファイル、Progress、Direct Share）に、`Handler` の作成も main の検査も無い（Codex）
- コールバックに渡すハンドルは所有権ごと渡し、読み取りのポインタは元のハンドルの解放まで有効で、第 1 部 AC-18 と合う。付録 A は C99 と C++17 で `-Wpadded` まで通る（Codex）

## 区分 A

| ID | 問題 | 確かめた結果 | 対処 |
|---|---|---|---|
| W-X1、W-C1 | Share の要求の ID を Kotlin の印にすると、印は main で前面を確かめた後に `coordinator.register` で初めてできるので、関数が戻る時点で ID が無い（第 1 部 1.3、5.7 と矛盾） | 正しい（`ShareRepositoryImpl.openWithResult`、`ShareCallbackCoordinator.register`） | AP-17: C が受け付けの時点で ID を付け、帳簿で Kotlin の印と対にする |
| W-X2、W-C2 | `PERMISSION_DENIED` は Kotlin から起きない。表示と更新は、権限が無いか通知が無効だと黙って成功で戻る | 正しい（`NotificationRepositoryImpl.notify` 324 行） | AP-16: 受け口が先に確かめる |
| W-X3、W-C2 | `EXACT_ALARM_NOT_ALLOWED` も起きない。予約は黙って不正確な Alarm に下げる | 正しい（`scheduleAlarm` 362 行〜） | AP-16: 正確な予約は受け口が先に確かめる |
| W-X4 | Progress の更新・完了・停止は `startService` で、後ろからは `BackgroundServiceStartNotAllowedException` が出うる。サービスの `SecurityException` は通知の権限とは限らない | 正しい（`ProgressForegroundNotifications.kt`） | AP-14 と 11.2: `ServiceStartNotAllowedException` 系を `SERVICE_START_NOT_ALLOWED` に、`SecurityException` の写しを操作ごとの表にした |
| W-C3 | ブリッジはどの通知にも本文のタップと dismiss の Intent を付けていた。C ABI は既定で付けず、タップでアプリが開かない | 正しい（ブリッジの `toCommand`、`buildContentIntent`、`buildDeleteIntent`） | AP-18: ビルダーの既定をブリッジと同じにし、`_set_tap(mode)` で変える |

## 区分 B

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| W-X5 | ビルダーの setter が受け取る引数の寿命が決まっていない | Codex | 6.3: setter は呼び出しの中で深く写す |
| W-X6 | `_listener_remove(NULL)` の契約が無い | Codex | 何もしない（5.4、付録 A） |
| W-X7、W-C10 | 同じ名前で OS ごとに引数・列挙の値・構造体の配置が違う。AP-5 の理由（1 つのバインディング）が RP-5 と食い違う | 両方 | AP-5 の理由を直し、C# は関数・列挙・構造体を OS ごとに宣言すると書いた（RP-5、16 章） |
| W-C4 | イベントの受け手の付け方が 2 通りに読め、保つ動き（32 件）が壊れうる | Claude | AP-21: C の登録が 0→1 で足し、0 に戻ったら外す |
| W-C5 | Kotlin の設計書 8.15 と 7 章（`HOST_START_FAILED`・`SHOW_FAILED`・`CancelReason` の写し、style の代わりの値、`Dismissed`）を記録なしに上書きしている | Claude | 7 章の変える文書に足した |
| W-C6 | 1.x から直していない不具合（`isScheduled` と `cancelAllScheduled` が保存しない予約を見ない、など）が対応表に無い | Claude | 8.3 の NT-10、NT-21、NT-23 とヘッダーのコメント |
| W-C7 | Dialog を閉じたときの今の値への写しが無い | Claude | 8.3 の DL-08〜13 |
| W-C8 | ブリッジの黙った代わりの値の一覧が足りない。リソースの型を C で指定できない | Claude | AP-8 の一覧を足し、型を指定できないことを書いた |
| W-C9 | 8.3 に書かれていない違い（保っていたタップを渡す、起動の Intent の action、全画面の flags、読めない Chooser Action のアイコン、SH-14 の成功の通知、NT-08〜11 の例外） | Claude | 8.3 の各行 |
| W-C11 | `alarm_type` 2・3 は Unix ミリ秒の時刻と食い違う | Claude | AP-22: 0 と 1 だけ |
| W-C12 | 2a の入力: 8.2 の 3 行の書き方が照合スクリプトの読み方と合わない。11 章の共通の行に名前が無い。11 章の節の順が Windows と違う。10 章に区分の列が無い | Claude | 8.2 を末尾だけの書き方に、11 章に共通の行を書き、節の順を Windows とそろえ、10 章に「C ABI での区分」の列と RG-06 を足した |
| W-C13 | DoD に第 1 部 6 章と README 9 章の 2b の項目が無い。E-9、AP-11、AP-13 のテストが無い。件数 0 を入口と完了のどちらで返すかが決まっていない | Claude | 15.2 と 12.1 に足した。AP-19 で入口と完了の分け方を決めた |
| W-C14 | マニュアルを 2b に置いたが README では段階 4。7 章の文書を直すタスクが無い。TB-10 の依存と合計が誤り | Claude | AP-23、TB-12 を文書の直しに、TB-10 の依存と合計（17.5 日）を直した |
| W-C15 | Share に `CANCELED` が無い理由と、`ntk_share_done_fn` に要求の ID が無い理由が書かれていない | Claude | 6.4 と 11.4 に書いた |
| W-C16 | `_set_large_icon_bytes` はブリッジに無く、D-5 の範囲を超える | Claude | AP-20: 外した（関数は 155） |

## 区分 C

| ID | 問題 | 対処 |
|---|---|---|
| W-X8 | AP-2 の理由が Binder の呼び出しだけで、実際の経路を狭く書いている | 確かめた経路を書いた |
| W-X9 | Clipboard の監視は「失敗しない」は強すぎる | 戻り値は main への受け付けを表す、と書いた |
| W-C17 | 6.2 と付録 A の結果の種類の名前の食い違い、AP-2 の監視の書き方、AP-4・NT-19 の Windows との比べ、6.3 の項目名、`NULL` の意味の抜け、9 章の OP-43〜47 と OP-56 の列、`NOT_INITIALIZED` に `void` の関数が含まれる、RG-01 に監視が無い、CL-10 の `message` | それぞれ直した |

## 総合評価

A は 6 件で、どれも Kotlin の実際の振る舞い（黙って成功にする、印が main でできる、ブリッジが必ず付けていた Intent）か第 1 部との食い違いだった。設計書の文面だけでなく、Kotlin のコードとブリッジのコードを読み合わせて初めて見えたもので、2 本の観点がよく分かれた。直した所が広い（0 章、5〜16 章、付録 A）ので、2 回目も 2 本で通す。
