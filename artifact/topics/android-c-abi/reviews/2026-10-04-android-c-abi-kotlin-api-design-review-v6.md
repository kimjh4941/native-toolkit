# レビュー結果（Kotlin の API の補完の設計書・第 7 版の確かめ）

- 日付: 2026-10-04
- 対象ファイル: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`（第 7 版）
- トピック名: android-c-abi（Kotlin の API の補完）
- 判定: **合格**（A 1 件、B 1 件を直して止めた）
- レビュアー: Codex 1 者（第 7 版で直した所だけ）
- 機械照合: `python3 scripts/check_design_consistency.py` → FAIL 0

## 第 7 版で変えたこと（利用者の決定。2026-10-04）

第 6 版で決定の後、ほかの OS（iOS・macOS の機能ごとの Manager、Windows の Manager）とそろえるため、`android_library` に機能ごとの入口 `AndroidClipboardManager`、`AndroidDialogManager`、`AndroidNotificationManager`、`AndroidShareManager` を置くと決めた。名前はほかの OS とそろえる。入口だけの薄い層で、C ABI の受け口は機能ごとにこの Manager を呼ぶ。第 6 版の `DialogManager`、`NotificationPermissionManager`、`NotificationSettingsManager` はこの 4 つにまとめた。イベントと監視の持ち主は internal にした。既存の公開の口は今のまま残す（K-9）。`agent-rules/coding-rules/android.md` の Manager の節も直した。

## 指摘

| ID | 区分 | 問題 | 対処 |
|---|---|---|---|
| V7-X1 | A | `AndroidShareManager.shareText(content, preview)` の形が、委ねる既存の `ShareTextUseCase`（Chooser Action の JSON を取る）と合わず、6.3 の「同じ引数」に反する | 6.3 に唯一の例外として「JSON の引数を出さず `ShareTextUseCase(content, "[]", preview)` に委ねる」と書き、付録 A と IT-27 にも入れた（README 4 章の「Kotlin の API では Chooser Action を型にする」） |
| V7-X2 | B | Manager のタスク（T-24）が shown のイベントのタスク（T-15）に依存していない | T-24 の依存に T-15 を足した |

ほかの変えた所（旧 Manager の名前の残り、README 6 章の 45 の操作の欠け、見積の合計、`android.md` と 6.3・common.md の食い違い）に問題は無かった。どちらの直しも 1 行で、ほかの節に影響しないので、確かめのやり直しはしない。
