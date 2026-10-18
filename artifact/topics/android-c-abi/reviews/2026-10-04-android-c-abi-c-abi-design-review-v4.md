# レビュー結果（C ABI の設計書 第 1 部・4 回目）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-c-abi-design.md`（第 4 版）
- トピック名: android-c-abi（C ABI の設計書 第 1 部）
- 判定: **要修正**（A が Claude 1 件、Codex 2 件。第 5 版で反映した）
- 別モデルによる独立レビュー: 実施済み（これまでとは別の Claude のサブエージェントと Codex の 2 者で並行）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0

ID の `U-C` は Claude、`U-X` は Codex。

## 3 回目の区分 A の確認

| 判定 | Claude | Codex |
|---|---|---|
| 直った | 10 | 5 |
| 一部だけ | 1（T-X2） | 6（T-X1、T-X2、T-X3、T-C1、T-C2、T-C3） |
| 直っていない | 0 | 0 |

Claude は、初期化の表（5.3）を既定の経路、Startup を無効にした手動の初期化 2 つの競合、`JNI_OnLoad` の失敗の後の手動の初期化、`LibraryInitializer` だけの構成、`dlopen` だけの経路で追い、両方の準備の前に `READY` が立つ順序、デッドロック、main を待つ経路は無いと確かめた（Kotlin の側の失敗を除く）。登録の表（5.7）も、取り消しと完了の重なり、挿入の前の取り消し、完了のコールバックの中の取り消し、完了の後と知らない ID の取り消し、受け付けの失敗で崩れなかった。

**AC-23**: 2 者とも、README の D-2、D-5、6 章、1b の範囲、利用者の決定（README 7.1 と 2c の行）と矛盾しないと判断した。

## 区分 A（新規と残り）

| ID | 問題 | 出典 | 対処（第 5 版） |
|---|---|---|---|
| U-C1、U-X2 | Kotlin の側の初期化が失敗した後の遷移が無い。「途中」に残ると `IN_PROGRESS` が続き、C は `JNI_FAILURE`（やり直せる）、Kotlin は `FAILED`（直らない）と逆を伝える | 両方 | 失敗した呼び出しは登録を戻して「未着手」に戻す。結果を「やり直せる」と「直らない」にそろえ、C と Kotlin の対応表を書いた（5.3、K-8） |
| U-X1 | Kotlin の側が済んだことを C に知らせる役が無い。`android_library` から呼ぶと逆の依存になる | Codex | C ABI の側の 3 つの入口だけが、`DONE` を見るたびに `onKotlinReady()` を呼ぶ（何度でも安全、`LinkageError` を捕まえる）（5.3） |
| T-X3（残り） | 今の Share は全要求が同じ PendingIntent なので、古い Chooser の選択が新しい要求の ID に付きうる | Codex | 要求ごとの印を broadcast に入れ、今の要求でないものを捨てる。今の不具合の修正として 1b で行い、README の 1b の行に書いた（AC-22、K-4） |

## 区分 B

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| U-C2 | AC-23 の「Unity から見た動作は包みが保つ」は言い過ぎ（`NOT_FOREGROUND` は包みが隠せない） | Claude | 「保てるものは保ち、保てない違いは対応表と移行ガイドに書く」に直した |
| U-C3 | `onKotlinReady` を誰が呼ぶかが 2 通りに読め、既定の経路が止まりうる。`LinkageError` の扱い | Claude | U-X1 と同じ |
| U-C4 | `NoSuchMethodError` と `RegisterNatives` の失敗が直らない失敗か一時的か | Claude | 名前が見つからない失敗は `CLASS_NOT_FOUND`（直らない）、それ以外の JNI の失敗は `JNI_FAILURE`（やり直せる）（5.3） |
| U-C5 | 待っている Share の取り消し（`cancelPendingShareCallback`）の行き先が無い | Claude | 取り消しは要求の ID を取り、今の要求でなければ何もしない（AC-22、K-4） |
| U-C6 | 「外してから足す」だけでは Unity の差し替えを保てない（`release` までは前の受け手に来うる） | Claude | 包みが「今のハンドル」の印を持ち、今でないハンドルへの配送を捨てる（C-6） |

## 区分 C

| ID | 問題 | 出典 | 対処 |
|---|---|---|---|
| U-C7 | `NATIVE_SETUP_REQUIRED` は、ほかのスレッドが表を作っている場合にも返る | Claude | 説明を「少し後でもう一度呼ぶか、C の `ntk_android_init` を呼ぶ」に直した |
| U-C8 | 手動の初期化が 2 つ重なると、Activity を渡した側の前面の初期値が失われる | Claude | ミューテックスを取れなかった側も前面の初期値を積む（5.3） |
| U-C9 | AC-23 が挙げる利用者の決定が README の決定の表に無い | Claude | 出典を README 7.1 と 2c の行と書いた |

## 総合評価

2 つの状態の表は崩れなくなり、互換の原則（AC-23）は README と矛盾しないと 2 者とも判断した。残った A は初期化の合流と失敗の後の遷移、Share の要求の ID の付け方で、第 5 版で反映した。5 回目（手順の決まりの上限）で A が 0 になったかを確かめる。
