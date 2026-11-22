# レビュー結果

- 日付: 2026-10-31
- 対象: `designs/2026-10-31-ios-c-abi-c-abi-design.md`（C ABI の設計書の第 1 部、v2。レビュー v1 の R-1〜R-42 を反映したもの）
- 判定: **要修正**（A 2 件を直し、直した所を再レビューする）
- 別モデルによる独立レビュー: 実施済み。1 回目と同じ 2 者（Claude のサブエージェント: 正しさと整合、Codex（設定のモデル）: 並行と寿命）で並行。どちらも読むだけ
- v1 の指摘の確かめ: Claude は R-1・R-10・R-13・R-14・R-18・R-19 を「足りない」、ほかは直ったとした。Codex は R-3〜R-7 を直った、R-2 を一部とした

区分: A = 決める前に必ず直す、B = 直す、C = 軽い。「対応」は設計書の v3 で埋める。

## A

| ID | 出典 | 所 | 指摘 | 直し方の案 | 対応 |
|---|---|---|---|---|---|
| R2-1 | Codex A | P1-21、5.12.5 | 循環の鍵を completion が呼ばれた時点で外すと、ホストが completion を呼んだ後に同じ通知を同期で proxy へ転送し直す形で、proxy → ホストの再帰が復活する（completion の重複を止めても転送は止まらない） | 「最初の転送の呼び出しが戻った」と「completion が呼ばれた／包みが解放された」の両方まで鍵を持つ。完了の後の遅れた転送し直しを防止の範囲に入れるか、契約の外と書く | v3: P1-21 と 5.12.5 を直した。鍵は (a) 最初の転送の呼び出しが戻った、(b) completion が呼ばれたか包みが解放された、の両方が済むまで持ち、済んだら「鍵を外す」を main に積んでその回まで残す。completion の前後どちらの同期の転送し直しも、転送の中で main に積んで戻す形も見つかる。鍵を外した後の転送し直し（別のキュー・`asyncAfter`・`Task`）は契約の外と書き、マニュアルに「転送し直すなら同期で」と書く。6 章に completion の後の同期の転送し直しのテストを足した |
| R2-2 | Codex A、Claude B-2 | P1-14、5.13.1、1.3、S-5 | 見張りは ViewController の解放に頼るので、ホストが表示した ViewController か表示元（古い root）を持ち続けると、handler も来なければ完了と `release` が来ない。1.3 と S-5 の「プロセスが生きている限りちょうど 1 回」と食い違う。「どの終わり方も最後は解放に行き着く」は測っていない（root を表示中に差し替えると古い root と表示した ViewController が残る例がよく報告されている） | 解放とは別の終わりの検出（表示の階層から外れたことを見る、など）を足すか、持ち続ける場合の例外を 1.3・S-5 の契約に書く。P1-14 の理由は「見込み」に直す。G-7 で解放されない経路が見つかったときの扱いを、約束が成り立つための条件にする | v3: 解放とは別の検出を足した（P1-14 の A を書き直し、B・C を選択肢に）。階層の見張り: `present` の完了の後、main の 1 秒ごとの timer で ViewController の `window` と `presentingViewController` を見て、2 回続けて両方 `nil` なら `CANCELED_BY_SYSTEM`。解放の見張りと同じ箱につなぐ（5.13.1）。残る例外（window の中に残ったまま見えない）を 1.3 と S-5 に書き、Dialog は取り消せる（P1-24）とした。P1-14 の理由を「見込み」に直し、G-7 に「階層から外れるか」を足して約束の条件にした |

## B

| ID | 出典 | 所 | 指摘 | 直し方の案 | 対応 |
|---|---|---|---|---|---|
| R2-3 | Claude B-1 | 5.13.1 の規則 5 | 見張りが普通の経路の結果を上書きしうる。Share の handler は `Task { @MainActor }` に移ってから continuation を再開し、`IosShareManager` もさらに移ってから completion を呼ぶので、見張りの `deinit` が積む `main.async` が先に走りうる（Task の順は文書に無いと P1-4 自身が書く） | 「箱は UIKit の handler の中で、どこにも移らずに同期に閉じる（結果も箱に書く）。後ろの非同期の配送は閉じた箱の値を運ぶだけ」を規則に足す。Share は continuation の `resumeOnce` を箱にする | v3: 5.13.1 の「1 回だけ通す箱」の 2 に、箱は UIKit の handler などの中で同期に閉じて結果も書き、後ろの非同期の配送は閉じた値を運ぶだけ、と書いた。Share は `resumeOnce` を箱にする（同 3） |
| R2-4 | Claude B-3、Codex B×2 | P1-12 の案 D、5.13 | 待つ処理（`IosLibrary`）と判定し直し（受け口が 1 回だけ）の置き場所が食い違う。閉じかけの下の ViewController が最上位になると、`presentedViewController` が残っていて UIKit が表示を断る。`present` の直後の `transitionCoordinator` は測っておらず、`nil` のときと、待ちを始められなかったときの終わり方が無い。待っている間に取り消された後に表示を再開しうる | 待つ処理と判定し直しを置く所を 1 つに決める。「落ち着いている」に `presentedViewController == nil` と `transitionCoordinator == nil` を足す。`nil` のときの扱いを決め G-4 に足す。待ちを始められなければ同じ箱で失敗で完了する。再開のときに未完了・未取り消しを確かめ、取り消し・待ちの失敗・handler・見張りが同じ終わりの状態を共有すると書く | v3: 待ちと判定し直しを `IosLibrary` の 1 つの表示の手順（5.13.2）に置き、受け口は `presenter` を渡すだけにした（P1-11 の C を直した）。「落ち着いている」に `presentedViewController == nil` と `transitionCoordinator == nil` を足した。coordinator が `nil`・`animate` が偽なら main の次の回に 1 回だけ確かめ直し、2 回目も落ち着かなければ表示の失敗。待ちの後に箱が開いているかを見て、取り消されていれば表示しない。どの終わり方も同じ箱。G-4 に `transitionCoordinator` を足した |
| R2-5 | Claude B-4 | P1-7 | 番号の規則が一方向（Android が後で 16 を別の名前に使わない決まりが無い）。Windows は同じ名前でも番号が違う（`WRONG_THREAD = 14`）ことが書かれていない | 「機能ごとに OS をまたいで 1 つの番号の表を持ち、どの OS も別の OS が使った番号を別の名前に使わない」にし、2a の照合を両方向にする。Windows は対象外と書く | v3: P1-7 と 5.10 を「機能ごとに OS をまたいだ 1 つの番号の表。同じ名前は同じ番号、ある OS が使った番号を別の OS が別の名前に使わない。2a は両方向。Windows は対象外（`WRONG_THREAD = 14` など）」に直した |
| R2-6 | Claude B-5 | 99 行、588 行 | 「iOS だけの値が 1 つ」は事実と合わない。Android の Share には `CANCELED`・`CANCELED_BY_SYSTEM`・表示の失敗が無く、Clipboard には `CANCELED` が無いのに、v2 は入れている。同じ OS の中で機能によって `CANCELED` の番号が違う | 「Notification は 1 つ（16）。Share と Clipboard にも Android に無い値が出る（第 2 部で数える）」に直し、機能で番号が違うことを 8 章に書く | v3: 1.1 の行を「Notification は 1 つ（16）。Share・Clipboard・Dialog にも Android に無い値が出る（第 2 部）」に、5.10 に機能で番号が違うことを書き、8 章に数と番号を第 2 部で決めることを足した |
| R2-7 | Claude B-6 | 0 章、5.7、S-15、5.13 | D-5 を広げるのは P1-10 だけではない。Dialog・Share の要求の ID による取り消しと、Clipboard の要求ごとの取り消しは、今のブリッジの振る舞いの集合の外（Android の Share にも取り消しは無い） | 0 章の例外に足して P1-n として決めてもらう（8 章の「取り消しの関数を出さないか」を移す）。Android との違いを DF に足す | v3: P1-24 を新設（D-5 の決め直し。A を推奨: Dialog の取り消しと、Clipboard の読み込みの要求ごとの取り消し。Share と権限の要求は出さない）。0 章の例外に足し、DF-18 を足した。8 章の「出さないか」を P1-24 に移した。S-15、5.7、5.13 を合わせた |
| R2-8 | Claude B-7 | P1-23、10 章 | 1 回目の申し送りの雛形に Dialog・Share の関数が無く、U-5・U-8 を流せない。U-8 の合格の条件は未決の P1-11・P1-12 に立つ。2 回目の元にする delegate の雛形は入れる関数が `@_cdecl` で、循環の防止が古い形なので、U-4 は P1-21 を確かめたことにならない | 1 回目の雛形に入れる関数を書くか、U-5・U-8 を 2 回目に移す。2 回目は入れる関数を `@c @implementation` に、循環の防止を P1-21 の形に直してから渡すと書く | v3: 1 回目の雛形に足す Dialog と Share の関数を 10 章に書いた。U-8 は合否でなく記録にした（P1-11・P1-12 が未決のため）。2 回目は入れる関数を `@c @implementation` に、循環の防止を P1-21 の形に直してから渡すと 10 章と P1-23 に書いた |
| R2-9 | Claude B-8 | P1-22 | 「最初の `didReceive`」がどの通知を指すか決まっていない（ホストの通知で前の delegate に転送したものを数えるか） | 「`didBecomeActive` より前に来た、ライブラリが扱った（イベントを出した）最初の `didReceive`。それより前のホストの通知は数えない」のように決める | v3: P1-22 を「プロセスで最初の `didReceive`（転送したものも数える）が最初の `didBecomeActive` より前で、ライブラリが扱ったものなら起動のきっかけ。ホストへ転送したなら無し」に直した |

## C

| ID | 出典 | 所 | 指摘 | 対応 |
|---|---|---|---|---|
| R2-10 | Claude C-1 | P1-22 | scene のアプリで測ったのは `sceneDidBecomeActive` で、`UIApplication.didBecomeActiveNotification` の順は測っていない。G-7 に | v3: P1-22 に書き、G-7 に `UIApplication.didBecomeActiveNotification` と `sceneDidBecomeActive` の順を足した |
| R2-11 | Claude C-2 | P1-21 | `openSettingsFor` を `Task { @MainActor }` で戻す形も、順が文書に無いので見つけられるとは限らない。契約の外に足す | v3: 5.12.5 の「契約の外」の行と P1-21 に、`Task { @MainActor }` で戻す形を足した |
| R2-12 | Claude C-3 | P1-17、S-16 | 前の delegate に渡す closure は `@unchecked Sendable` にできない。見張りが main へ運ぶ箱と、関連オブジェクトの鍵（`nonisolated(unsafe)` が要る見込み）が一覧に無い | v3: P1-17 と S-16 を直した。前の delegate に渡す closure は `@unchecked` にしない。表示の完了の箱と見張り、関連オブジェクトの鍵（`nonisolated(unsafe) static let`）を一覧に足した |
| R2-13 | Claude C-4 | 5.13.1 | 「1 つの要求に 1 つの ViewController、使い回さない、同じ鍵の見張りを 2 度付けない」と書く。見張りの `deinit` は main 以外で走りうるので ViewController に触れず nonisolated にする | v3: 5.13.1 の箱の規則 1 と見張りの表に書いた（1 要求 1 ViewController、使い回さない、2 度付けない。`deinit` は nonisolated で ViewController と `self` に触れない） |
| R2-14 | Claude C-5 | Share | 見張りは continuation を再開しなければならない（しないと checked continuation が漏れ、Task が止まる） | v3: 5.13.1 の箱の規則 3 に、見張りが閉じたときも continuation を必ず 1 回再開すると書いた。6 章にテスト |
| R2-15 | Claude C-6 | P1-11 の C、S-6 | `getRootViewController()` はすでに public で `foregroundActive` で選ぶ。前面の ViewController を返す口が 2 つになるので、名前と意味の違いを書く。表示元を渡されたら `IosLibrary` の検査が前面を探し直さないと書く | v3: P1-11、5.13、S-6 に、今の `getRootViewController()` は残し、新しい定義の口は別の名前にして意味の違いを DocC に書くこと、ViewController を渡されたら前面を探し直さないことを書いた |
| R2-16 | Claude C-7 | S-13 | 権限の要求の前面を `IosLibrary` の条件のように書き、5.13 の「判定は受け口」と食い違う | v3: 判定を `IosLibrary` の表示の手順に置いたので、S-13 を「権限の要求の口も `presenter` を取り、手順の中で判定する」に直し、5.13 とそろえた |
| R2-17 | Claude C-8 | S-15 | 取り消しで閉じるときは、`dismiss` の前に箱を `CANCELED` で閉じる順を書く | v3: S-15、5.13.1 の箱の規則 4、5.7 の「外す」に、`dismiss` の前に箱を `CANCELED` で閉じる順を書いた |
| R2-18 | Claude C-9 | 9.2 | C-8、C-9 が C-7 より前に並んでいる | v3: 9.2 を C-7、C-8、C-9 の順に並べ直した |

## 見張りの解放のスレッド（Codex、問題なし）

`deinit` から main へ非同期に積む形なので、背景での解放から利用者のコールバックを直接呼ぶことはなく、`@MainActor` の検査にも掛からない。実装では箱を局所に取り出して捕まえ、`deinit` の `self` を持ち越さない。actor に隔離した箱に触れるのは main の中だけにする。
