# HC11: 貼り付けのコントロールでテキストを読む（CB3 の実機）

- 対象: `artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md` の 4 章 HC11、3.5 の CB3
- 自動のテストで確かめていること: シミュレーターでは `ClipboardPasteUITests/testCB3_pasteControlReadsText` が同じことを確かめる。実機ではシステムの貼り付けのコントロールが XCUITest の合成のタップを受け付けない見込みなので、`scripts/ios_ui_runner.py` の `SIMULATOR_ONLY_TESTS` に入れ、実機は人が指で押す（段階 2 の作業の記録 17 章の持ち主の決定 1。段階 1b の作業の記録 24 章）
- 手段: 利用者が実機を手で操作し、結果の行を読む。agent は画面を見ない（実機の画面を見るには、その都度利用者の許可が要る。U-19）
- 判定があいまいなら失敗とする

## 前提

- 実機（iPhone XS / iOS 18.7.2）にサンプル（IosLibraryExample、Debug）が入っている
- Handoff を切ってある（Mac のコピーが入らないように。`agent-rules/device-testing.md` の準備）
- この確認は利用者自身のクリップボードを使う。手順 1 で自分のコピーを上書きするので、残したい内容は先に別の所へ移しておく

## 手順

1. メモなどで、私物でない文字列 `ntk-hc11` を入力して選び、「コピー」を押す
2. サンプルを開き、メニューの Clipboard を開く
3. 画面を下へ送り、「Paste Control (UI)」の節の「Mount Paste Control」を押す。そのボタンがシステムの貼り付けのボタン（「ペースト」）に替わる
4. 押す前に、画面の上の方の行が `Paste result: -` であることを確かめる（前の結果が残っていると、押した結果と見分けられない。違えばサンプルを終了して開き直し、手順 2 からやり直す）
5. その貼り付けのボタンを指で押す
6. 2 秒待ち、`Paste result:` の行を読む

## 期待する結果

- `Paste result: items=1, failures=0`
- 押してから、システムの「ペーストを許可」のダイアログが出ない（貼り付けのコントロールは許可なしで読む）

## 失敗とするもの

- `Paste result: -` のまま、`items=0`、`failures=1` 以上、`paste failed: …`、`control creation failed: …`
- 貼り付けの許可のダイアログが出る
- 貼り付けのボタンが現れない

## 証拠

結果を段階の結果のファイルに書く（環境・日付・合否・読んだ行）。スクリーンショットは残さない（実機は私物。残すなら `Paste result:` の行だけに切り取る）。
