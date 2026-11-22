# HC12: 貼り付けのコントロールで画像だけの内容を読む（CB4 の実機）

- 対象: `artifact/topics/ios-c-abi/designs/2026-10-18-ios-c-abi-ui-test-design.md` の 4 章 HC12、3.5 の CB4（Clipboard v6 の 8.1 #19）
- 自動のテストで確かめていること: シミュレーターでは `ClipboardPasteUITests/testCB4_pasteControlReadsImageOnly` が、ランナーが画像だけを書いたクリップボードを読む。実機は HC11 と同じ理由で人が指で押す（段階 2 の作業の記録 17 章の持ち主の決定 1）
- 手段: 利用者が実機を手で操作し、結果の行を読む。agent は画面を見ない（U-19）
- 判定があいまいなら失敗とする

## 前提

- HC11 の前提と同じ（サンプルが入っている、Handoff を切ってある、手順 1 で自分のクリップボードを上書きする）
- コピーする画像は何でもよい（結果の行は件数だけを出す）。私物の写真を使いたくなければ、何も写っていない画面のスクリーンショットを撮り、その編集画面の共有のボタン →「コピー」を使ってもよい。Safari の画像の長押しの「コピー」は URL も入りうるので使わない（「画像だけ」にならない）

## 手順

1. 写真の App で画像を 1 枚開き、共有のボタン →「コピー」を押す（またはスクリーンショットの編集画面の共有のボタン →「コピー」）
2. サンプルを開き、メニューの Clipboard を開く（前の確認の後なら、サンプルを終了して開き直してから）
3. 「Use General」を押し、続けて「Snapshot」を押す。Snapshot は型と件数だけを見る操作で、中身を読まないので貼り付けの許可のダイアログは出ない。結果の行が `hasStrings=false, hasURLs=false, hasImages=true, …` で、`typeIdentifiers=` の一覧に `public.plain-text` と `public.url` が無いことを確かめる。あれば画像だけではないので、手順 1 からやり直す（ダイアログが出たら、この確認は失敗として止める）
4. 「Paste Control (UI)」の節の「Mount Paste Control」を押す
5. 押す前に `Paste result: -` であることを確かめる
6. 現れたシステムの貼り付けのボタンを指で押す
7. 2 秒待ち、`Paste result:` の行を読む

## 期待する結果

- `Paste result: items=1, failures=0`（サンプルが受ける型に `public.image` がある。`ClipboardSampleView.swift` の `pasteAcceptedTypes`）
- 押してから、システムの「ペーストを許可」のダイアログが出ない

## 失敗とするもの

- HC11 と同じ（`items=0`、`failures=1` 以上、`paste failed: …`、`control creation failed: …`、ダイアログが出る、ボタンが現れない）
- 貼り付けのボタンが押せない（灰色のまま）: 受ける型に合う内容が無いと見なされている

## 証拠

HC11 と同じ。画像そのものは撮らない・書かない。
