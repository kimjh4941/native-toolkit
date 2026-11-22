# 試作（段階 0a と 1a-前）

企画の調べの試作のソース。組み立てと実行の結果は `../2026-11-22-macos-c-abi-stage0a-working-notes.md` に書く。組み立ての物（`.app`）はリポジトリに入れない。

| フォルダー | 確かめること | 組み方 |
|---|---|---|
| `1a6-dialog-main-queue/` | 1a-6: `NSAlert.runModal()` の入り方（GCD のブロックの中、main actor の Task、run loop のブロック、Timer）ごとに、開いている間に main キューなどの積み方が捌かれるか、別のスレッドから取り消せるか | `xcrun swiftc -swift-version 5 -O -target arm64-apple-macos15.0 main.swift`、最小の `Info.plist` を持つ `.app` にして ad-hoc で署名。アラートは自分で閉じる（人の操作は要らない） |
| `0a-uitest-spike/` | 0a と 1a-8: XCUITest で、通知の許可の問い合わせ・バナー・通知センターの一覧・アクション・テキスト入力・予約・コールドスタート、共有のピッカー、`NSAlert`、ファイルのパネル、`PasteButton` と貼り付けの確認を扱えるか。試作のアプリは通知の delegate を `applicationWillFinishLaunching` で入れ、起動の順と `NSApp.isActive` を記録する | `app/build.sh`（VM の中で組み、ad-hoc で署名して LaunchServices に登録。`SANDBOX=1` でサンドボックスありの版）。`uitest/` はサンプルの写しの `MacLibraryExampleUITests` のフォルダーに置き、`scripts/vmrun.sh` で流す。通知の前に `scripts/nc-allow-when-shared.sh`、許可を戻すときは `scripts/ncreset.sh` |
| `1a7-share-picker-context/` | 1a-7: `NSSharingServicePicker` を mouseDown の外（GCD、main actor の Task、合成の mouseDown・keyDown）で出せるか。出して `close()` で閉じるだけで、サービスは選ばない | 同上 |
| `1a9-unity-handoff/` | 1a-9 の申し送り（`../2026-11-23-macos-c-abi-unity-handoff-1a9.md`）で `unity-native-plugin` に渡す雛形の 2 つの xcframework（`NtkProbeMac` は `MacLibrary` の代わり、`NtkProbeMacCApi` は C ABI の代わり）と、Unity の書き出しに入れる `unity/Main.cpp`・`unity/NtkProbeMac.cs` | `DEVELOPER_DIR=<Xcode 26.6>/Contents/Developer ./build.sh <出力のフォルダー>`（xcodeproj gem が要る）。画面を使わない確かめは `smoke/run.sh <出力のフォルダー>`（区分 1。この Mac で流してよい） |

`0a-`・`1a6-`・`1a7-` は画面にアラートやピッカー（`0a-` は通知も）を出すので、`agent-rules/device-testing.md` の区分 3 に当たる。この Mac では流さず、条件を満たす VM の中で流す。
| `1a6b-panels-nesting-cancel/` | 1a-6 の続き: ファイルのパネルの A と A'、同じ回の 2 つ目の Dialog（何もしない場合と待たせる場合）、ホストのモーダルがあるときに自分のモーダルだけを取り消せるか | 1a-6 と同じ（VM で流す） |
