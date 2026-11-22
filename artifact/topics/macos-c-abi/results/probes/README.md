# 試作（段階 0a と 1a-前）

企画の調べの試作のソース。組み立てと実行の結果は `../2026-11-22-macos-c-abi-stage0a-working-notes.md` に書く。組み立ての物（`.app`）はリポジトリに入れない。

| フォルダー | 確かめること | 組み方 |
|---|---|---|
| `1a6-dialog-main-queue/` | 1a-6: `NSAlert.runModal()` の入り方（GCD のブロックの中、main actor の Task、run loop のブロック、Timer）ごとに、開いている間に main キューなどの積み方が捌かれるか、別のスレッドから取り消せるか | `xcrun swiftc -swift-version 5 -O -target arm64-apple-macos15.0 main.swift`、最小の `Info.plist` を持つ `.app` にして ad-hoc で署名。アラートは自分で閉じる（人の操作は要らない） |
| `1a7-share-picker-context/` | 1a-7: `NSSharingServicePicker` を mouseDown の外（GCD、main actor の Task、合成の mouseDown・keyDown）で出せるか。出して `close()` で閉じるだけで、サービスは選ばない | 同上 |

どちらも画面にアラートやピッカーを出すので、`agent-rules/device-testing.md` の区分 3 に当たる。この Mac では流さず、条件を満たす VM の中で流す。
