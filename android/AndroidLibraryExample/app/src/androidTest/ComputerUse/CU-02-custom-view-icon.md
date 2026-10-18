# CU-02: カスタムビューのアイコン

- 対象: `artifact/topics/android-c-abi/designs/2026-10-03-android-c-abi-ui-test-design.md` の 7 章、6.3 N-16 / N-17
- 自動のテストで確かめていること: カスタムビューの通知の文言（`Decorated custom view sample`、`Expanded custom notification sample`、`Decorated media custom view sample`）と `Dismiss` のボタン。アイコンの画像は確かめられない
- 手段と判定の決まりは CU-01 と同じ

## 前提

CU-01 と同じ。

## 手順

1. Notification の画面で「Show DecoratedCustomView Style」を押す
2. シェードを開き、本文 `Decorated custom view sample` の通知を展開する
3. シェードを閉じ、「Delete DecoratedCustomView Style」を押す
4. 「Show DecoratedMediaCustomView Style」を押し、シェードで本文 `Decorated media custom view sample` の通知を展開する

## 期待する結果

- 2 と 4 の通知の中のアイコン（`notification_icon`）が、丸いランチャーのアイコン（`R.mipmap.ic_launcher_round`）
- 2 の展開した表示に `Expanded custom notification sample` と `Dismiss` のボタン、4 の展開した表示に `Expanded media custom notification sample`

## 合格の条件

上の 2 つがすべて見えていること。

## 証拠

CU-01 と同じ決まりで `evidence/CU-02/` に保存する。
