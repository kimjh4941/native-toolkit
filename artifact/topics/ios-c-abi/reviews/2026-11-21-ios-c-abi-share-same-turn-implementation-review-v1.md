# 実装のレビューの結果（SH-13、v1）

- 日付: 2026-11-21
- 対象: SH-13 の直しの、コミット前の変更（`PresentationRecords`、`PresentationProcedure`、`ReleaseWatch`、DocC、`Share.h`、テスト、サンプル、C ABI のテストのアプリ、設計書と記録）
- 設計: `designs/2026-11-21-ios-c-abi-share-same-turn-design.md`（v3 と 10 章）
- レビューした者: Codex（C-n）と Claude のサブエージェント（K-n）。どちらも読むだけ（ビルド・テスト・シミュレーターは使っていない）。同じ頼みの文（どの順の出来事でも完了がちょうど 1 回か、設計との一致、今の呼び出し側への影響、テストの強さ、文書の一致、規則）を渡した

---

## 強み（2 者に共通）

- 記録の変更を main actor に集め、`ReleaseWatch.deinit` からは不変の `@Sendable` の closure で知らせている。`ReleaseWatch` は `@unchecked` なしの `Sendable` のまま。循環して持ち合う所は見つからなかった
- 記録は ID で終わらせ、古い知らせは何もしない。待つ要求は起こした時点で一覧から外す
- K: 手で追った範囲では、`present` の完了・解放・寿命・やり直し・取り消し・箱が早く閉じる、のどの順でも、受け付けた Share と Dialog の完了はちょうど 1 回
- C ABI の UI テストは、どちらの Share が失敗しても通る書き方で、完了と `release` が 1 回ずつ main で来ることを確かめている

## 改善点と対応

| ID | 重さ | 問題 | 対応 |
|---|---|---|---|
| C-1 | high | 寿命で記録を消すので、シートが出るのに 10 秒を超えた後に呼んだ Share が、UIKit がまだ出す途中のシートの上に出て、SH-13 と同じく完了しなくなる | **直した（利用者が決めた）**。寿命を過ぎた記録は「行き詰まり」として `present` の完了か解放まで残し、その間の同じ window の要求は待たずに表示の失敗にする（設計メモ 10.2） |
| C-2 | medium | S20 が固定の 3 秒の待ちに頼る | 直した。サンプルが Share ごとに結果の行を書き、UI テストは 1 本目（表示の失敗）を待ってから閉じる |
| C-3 / K-4 | low | 待つ間に取り消した Dialog を、記録が片付くまで（最長 10 秒）一覧が持ち続ける | 直さない（設計メモ 10.2 に書いた）。完了の回数は正しく、持つのは最長 10 秒。外すには箱の作りを変えることになる |
| C-4 | low | C ABI のテストが、寿命を過ぎた後に完了が増えないことを見ていない | 直した。始めてから 12 秒たつまで見てから、5 本目の行が無いことを確かめる |
| C-5 / K-1 | medium | Dialog の DocC（`IosDialogManager.show`、`DialogError`）に、共有のシートを待つことと、その失敗が書かれていない。README の行に今の口の Dialog の限定が無い | 直した |
| C-6 / K-9 | low | `PresentationRecords` のログの位置と引数が規則（`ios.md`）に合わない | 直した（各メソッドの 1 行目に引数のログ。結果は別の行） |
| K-2 | medium | 起こす相手を window で絞ることを落とすテストが無い | 直した。`theEndOfASheetWakesOnlyTheRequestsOfItsWindow` と変異 M14 |
| K-3 | low | `hasPending` の、解放済みのシートの記録を読むときに片付ける部分を通るテストが無い | 直した。`aRecordWhoseSheetIsFreedIsClearedWithoutTheNotice` と変異 M15 |
| K-5 | low | 範囲の印の `ObjectIdentifier` は、解放された window のアドレスを別の window が使い回しうる | 直した。window を `weak` で持ち、無くなった window の記録は片付いたとみなす（`aRecordWhoseWindowIsFreedIsCleared` と変異 M16） |
| K-6 | low | `Share.h` の行の長さ、寿命で失敗する場合が書かれていない、「same main-thread turn」が C の口に分かりにくい | 直した（第 2 部の付録 A の写しも） |
| K-7 | low | `IosShareManager` の DocC が「待った後に出る」と読める。`ShareSheetPresenter` の `.firstActiveScene` の段落に足りない | 直した |
| K-8 | low | サンプルの doc コメントが別の関数に付いた | 直した |
| K-10 | low | 作業の記録の単体テストの件数 | 直した |
| K-11 | low | 今の口の Dialog を、出る途中のシートと同じ回に出す場面を測った記録が無い | 未確認と設計メモ 10.1 に書いた（理屈では補いが表示の失敗にする） |
| K-12 | - | Share の完了の callback から続けて Share を呼ぶ流れ（確かめを勧めるもの） | 前のシートは閉じかけ（`isBeingDismissed`）なので、前面の探し方がその下を返し、段 4 で移り変わりを待ってから出る見込み。UI テストの S 系は、前のシートを閉じた後に次の Share を出す形で続けて通っている |

## 総合評価

2 者とも、SH-13 の直しの芯は設計どおりに入っていると見た。重い指摘は C-1 だけで、利用者の決定のとおり記録を残す形に直した。ほかは文書・テスト・ログの直し。
