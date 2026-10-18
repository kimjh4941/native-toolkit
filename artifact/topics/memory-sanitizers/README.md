# メモリのサニタイザーでテストを流す（Windows / iOS / macOS）

- 記録日: 2026-10-10
- 分類: テスト債務（横断課題）
- 状態: 未着手
- 関連: [android-c-abi](../android-c-abi/README.md)（Android は段階 2b の TB-9 で HWASan を入れた）、[bridge-testing](../bridge-testing/README.md)（iOS / macOS の橋渡しの層のテストの穴）

## 何が問題か

C / C++ / Objective-C のメモリの誤った使い方（解放した後のメモリを使う、確保した領域の外を読み書きする、寿命の終わったスタックの変数を使う）は、普通のビルドではたいてい落ちない。たまたま動くか、ずっと後で関係のない場所が壊れるので、テストが通っていても見逃される。サニタイザーを有効にしたビルドでテストを流すと、誤ったアクセスがあった瞬間に、確保・解放・使用の場所を報告して止まる。

Android の C ABI は、設計（`android-c-abi` の第 1 部 6 章）で「HWASan と CheckJNI を有効にして流す」と決め、TB-9 で試験用のビルド（`-Pntk.hwasan=true`）を作って全テストを流した（Pixel 6a で 140 件、報告 0 件）。**Windows・iOS・macOS では、サニタイザーを使ったことが無い**（2026-10-10 にリポジトリ全体を検索して確かめた。`/fsanitize=address`、`EnableASAN`、AddressSanitizer の設定・記述はどこにも無い）。

Android の TB-4 では、テストの側の use-after-free（早く終わったテストのスタックの変数に、後から完了が書き込む）を踏み、main スレッドが止まって原因の特定に時間がかかった。サニタイザーがあれば、書き込んだ瞬間に場所が分かる。

## OS ごとの対象と道具

| OS | ネイティブのコード | リスク | 道具 | 優先度 |
|---|---|---|---|---|
| Windows | C ABI（`WindowsLibraryCApi`）と C++ の実装。コールバック、`release`、スレッドの受け渡し | Android の C ABI と同じ作りなので高い | MSVC の AddressSanitizer（`/fsanitize=address`）。`WindowsLibraryCApiTest` に構成を 1 つ足す | 高 |
| macOS | ほとんどが Swift（131 ファイル）。Unity 向けの Objective-C と C の橋渡し（`.m` 10、`.mm` 6、`.c` 3） | Swift の部分は低い。橋渡しの層は C の関数ポインタとポインタを扱うのでありうる | Xcode の Address Sanitizer（テストの scheme の設定、または `xcodebuild -enableAddressSanitizer YES`）。Swift の並行処理には Thread Sanitizer も | 中 |
| iOS | macOS と同じ形（Swift 144、`.m` 7、`.mm` 3、`.c` 3） | 同上 | 同上 | 中 |

HWASan（ハードウェアを使う版）は arm64 の Android と Linux 向けで、Windows・Apple の OS には無い。これらでは ASan（AddressSanitizer）を使う。見つける誤りの種類はほぼ同じで、メモリと速度の負担が HWASan より大きい。

## 対応方針（案）

- 毎回のテストではなく、**リリースの前と、登録・解放・スレッド・コールバックのまわりを変えたとき**に流す。テストのスクリプトに「サニタイザーを有効にして流す」を選べる口を足す（Android は `test_android.sh` に、TB-11 で足す）
- 配る成果物には入れない。試験用のビルドだけで有効にする
- iOS / macOS は、橋渡しの層を通るテストがまだ無い（[bridge-testing](../bridge-testing/README.md)）。サニタイザーは、通るテストがあって初めて効くので、bridge-testing と合わせて進める
- 着手の順は Windows → macOS / iOS

## 着手するときに確かめること

- Windows: MSVC の ASan と、テストの枠組み・`WindowsLibraryCApi` のリンクの形（静的な CRT か動的か）との相性
- iOS / macOS: Unity の橋渡しが、将来 C ABI（Android・Windows と同じもの）に置き換わる予定か。置き換わるなら、サニタイザーはその C ABI のテストに入れる（`android-c-abi` の README のとおり、iOS / macOS の C ABI は Android の後に別のトピックにする）
