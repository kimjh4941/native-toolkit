# レビュー結果（C ABI の設計書 第 1 部・5 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-c-abi-design.md`（第 5 版）
- トピック名: android-c-abi（C ABI の設計書 第 1 部）
- 判定: **合格**（第 5 版で足した文言から A が出たので第 6 版で直し、直した所だけを Codex が確かめた。そこで見つかった反映の漏れ 1 件を直して止めた）
- 別モデルによる独立レビュー: 実施済み（これまでとは別の Claude のサブエージェントと Codex の 2 者で並行）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0

ID の `V-C` は Claude、`V-X` は Codex。

## 4 回目の区分 A の確認

| 判定 | Claude | Codex |
|---|---|---|
| 直った | 4（U-C1、U-X1、U-X2、T-X3 の残り） | 3（U-X1、U-X2、U-C1） |
| 一部だけ | 0 | 1（T-X3 の残り: 印を extra だけに入れる案が残っていた） |
| 直っていない | 0 | 0 |

Claude は 5.3 の表を 4 つの順序で追い、両方の準備の前に `READY` が立つ順序、デッドロック、main を待つ経路は無いと確かめた（`NATIVE_SETUP_REQUIRED` の後のやり直しを除く。V-C2）。Codex は新しい A を 0 件とした。

## 区分 A

| ID | 問題 | 出典 | 対処（第 6 版） |
|---|---|---|---|
| V-C1 | Share を開く操作は Chooser が開いた時点で完了するので、「完了の後の取り消しは何もしない」のとおりだと選択の待ちを取り消せない（今の `cancelPendingShareCallback` が消える） | Claude | Share の要求の ID の取り消しは「選択の待ち」を取り消す、と 1.3.1 の例外として書いた（AC-22） |
| V-C2 | `NATIVE_SETUP_REQUIRED` をやり直せるとしたが、`JNI_OnLoad` の失敗の後は Kotlin の `init` をやり直しても直らない。R8 で名前が変わった場合に C と Kotlin が逆を返す | Claude | `NATIVE_SETUP_REQUIRED` は「C の `ntk_android_init` を呼ぶ」の意味にした。Kotlin の側も `capi.jni` のクラスを確かめて `CLASS_NOT_FOUND` を返す（5.3）。公開シンボルは増やさない（`Java_*` を公開する案は採らない） |
| T-X3 の残り、V-C4 | 印を extra だけに入れると、固定の request code と `FLAG_UPDATE_CURRENT` で上書きされる | 両方 | 要求ごとに別の PendingIntent（data の URI に印）を作る形に限り、extra だけには頼らないと書いた（AC-22、K-4） |

## 区分 B

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| V-C3 | 既定の経路で `NtkInitializer` が `IN_PROGRESS` か `ERROR` を見ると、後で C に知らせる者がいない | Claude | C ABI の側の入口が `LibraryRuntime` に「済んだら呼ぶ」関数を登録し、それが `onKotlinReady()` を呼ぶ（5.3） |
| V-C5 | `onKotlinReady()` の後、`READY` の前でも `INITIALIZED` を返しうる | Claude | `onKotlinReady()` は C の状態を返し、`READY` のときだけ `INITIALIZED`（5.3） |
| V-C6 | 前面でない Share が前の待ちを消すか | Claude | 消さない（AC-22） |

## 区分 C

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| V-C7 | 2 つの原子変数のメモリ順序 | Claude | `seq_cst` と書いた |
| V-C8 | `ensureInitialized` を呼ぶ経路 | Claude | `capi.jni` の受け口を通す、と書いた |
| V-C9 | Kotlin の側の CAS に負けた側の Activity | Claude | 負けた側も前面の初期値を積む |
| V-C10 | C-6 の「今のハンドルか」の判定のスレッド | Claude | UnityMain で行う |

## 止め方（手順の決まりの 5 回の上限）

5 回目で、2 つの状態の表と互換の原則（AC-23）は崩れなかった。残った A は、どれも第 5 版で足した文言から出た局所的なもので、第 6 版で直した。直した所（0.5 の表、1.3.1 の例外、AC-22、5.3 の Kotlin の行と結果の表、K-4）だけを、別のレビュアー 1 者に確かめてもらうかどうかを、利用者に相談する。

## 直した所の確かめ（利用者の決定: 直した所だけを確かめる）

Codex 1 者に、第 6 版で直した所（0.5 の表、1.3.1 の例外、AC-22、K-4、5.3 の Kotlin の行と結果の表、やり直しの約束、`onKotlinReady` の段落、対応する 6 章の文言）だけを見てもらった。

| ID | 判定 | 理由 |
|---|---|---|
| V-C2 | 直った | Kotlin の `init` も `Class.forName` で `CLASS_NOT_FOUND` を返し、`NATIVE_SETUP_REQUIRED` は C の `ntk_android_init` を求める。結果の表、やり直しの約束、`onKotlinReady()` の戻り値、`IN_PROGRESS` / `ERROR` のときの通知の登録、6 章が一致する |
| T-X3 の残り | 直った | 要求ごとに data の URI の印で PendingIntent を分け、extra だけに頼らず、古い broadcast を捨てる |
| V-C1 | 反映の漏れ | 1.3.1・AC-22・K-4 は直ったが、5.7 の取り消しの規則（C の登録の表を引き、完了の後は何もしない）と 6 章の文言が古い契約のままだった |

新しい指摘は無し。V-C1 の反映の漏れは、Share の選択の待ちは C の登録ではなく Kotlin の側の印で、取り消しは C の登録の表を通らない、と 5.7 に書き、6 章を直して閉じた。**これで区分 A は 0 になり、第 1 部を決定にした。**

手順の決まり（`review-document` の止める基準）との照らし合わせ:

1. レビュアーを替えて通した: 5 回とも、前の回とは別の Claude のサブエージェントと Codex で行った
2. 機械照合: `check_design_consistency.py` は FAIL 0
3. 直さない残件: 無し（第 2 部に送るものは設計書 8 章、後に続く文書の条件は 9 章に書いた）
