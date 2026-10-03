# CU-01: BigPicture の画像と大きいアイコン

- 対象: `artifact/topics/android-c-abi/designs/2026-10-03-android-c-abi-ui-test-design.md` の 7 章、6.3 N-13
- 自動のテストで確かめていること: 通知に画像（`EXTRA_PICTURE` か `EXTRA_PICTURE_ICON`）と大きいアイコンがあること。どの画像かは確かめられない
- 手段: Claude のデスクトップアプリの computer use（実機は scrcpy などで画面を Mac に映す。エミュレータはそのまま見る）か、`adb` で手順どおりに操作し、`adb exec-out screencap` で撮った画面を Claude が見る
- 判定があいまいなら失敗とする

## 前提

- サンプル（debug）を入れてあり、通知の権限が許可されている
- サンプルの通知が 1 件も出ていない（Notification の画面で各 Delete を押すか、`adb shell cmd notification` で片付ける）

## 手順

1. サンプルを開き、メニューの「Notification Example」を押す
2. 「Show BigPicture Style」を押す。状態の表示が `✅ Displayed BigPicture style notification.` になる
3. 通知のシェードを開き、タイトル `Native Toolkit` / 本文 `BigPicture style notification sample` の通知を探す
4. 通知を下へスワイプして展開する

## 期待する結果

- 展開した画像が、サンプルのランチャーのアイコン（`R.mipmap.ic_launcher`。緑の地に Android のロボット）
- 通知の右の大きいアイコンが、丸いランチャーのアイコン（`R.mipmap.ic_launcher_round`）
- 展開したときのタイトルが `BigPicture Style`、要約が `Launcher image preview`

## 合格の条件

上の 3 つがすべて見えていること。

## 証拠

サンプルの通知の範囲だけに切り取ったスクリーンショットを `evidence/CU-01/<日付>-<段階>-<環境>.png`（環境は `api35-emulator` か `api36-pixel6a`）に保存する。シェードの全体や、ほかのアプリの通知は写さない。
