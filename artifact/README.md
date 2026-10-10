# artifact

設計・検討文書の置き場。機能の文書は OS ごとに、それ以外はトピックごとに分ける。

| ディレクトリ | 対象 | 作り方 |
|---|---|---|
| `<os>/<feature>/` | OS 機能の追加（clipboard / notification / share など） | `agent-rules/workflows/` のワークフローで作成する |
| `topics/<topic>/` | 機能単位でない課題（移行・検証負債・構成変更など） | 手動で作成する。ワークフローは使わない |

## <os>/

`<os>` は `android` / `ios` / `macos` / `windows`（小文字）。`<os>/<feature>/{plans,designs,results,reviews}/` に、各ワークフローが保存先として指定する文書を置く。

- 文書は「機能 × OS × 版」で増え、作業は OS ごとに進むので、OS を最上位にする。コードの並び（`<Platform>/<Feature>`）とも揃う
- ファイル名は OS 名を含めたままにする（例: `2026-08-29-macos-clipboard-design-v7.md`）。ファイル名だけで引用されても、どの OS の文書か分かるようにするため
- OS を選ぶ前に候補を探すワークフローの手順は、`artifact/*/<feature>/<種類>/`（全 OS）を探す
- `unity-native-plugin` も同じ構成にしている

2026-09-29 に `features/<feature>/<種類>/` から今の形に移した。移動に伴うパスの書き換えは、版の付いた文書でも参照の機械的な更新として行い、中身は変えていない。記録として当時のパスを残した行が 3 つある（`git status` の出力をそのまま写した 2 行と、段階 2 の結果の記述 1 行）。

## topics/

- 各トピックは `topics/<topic>/README.md` を必ず持つ。課題の内容・状態・対応方針はここに書く
- `plans/` `designs/` `results/` `reviews/` は必要になったものだけ作る
- ディレクトリ名は kebab-case

### トピック一覧

1 行 1 トピック。詳細は各 README に書き、ここには要約だけを置く。

| トピック | 分類 | 状態 | 最終更新 | 概要 |
|---|---|---|---|---|
| [migration](topics/migration/README.md) | 移行 | 進行中 | 2026-08-30 | ツールチェーン・言語モード移行（Swift 6 / Android / Windows）の管理 |
| [bridge-testing](topics/bridge-testing/README.md) | テスト債務 | 未着手 | 2026-08-15 | Unity ブリッジ層（Objective-C `.m`）を通るテストが iOS の全機能に無い |
| [feature-scoped-testing](topics/feature-scoped-testing/README.md) | テスト基盤 | 未着手 | 2026-10-10 | 全 OS で、機能の名前か変えたファイルから、その機能のテストだけをまとめて流せる口を足す。共通の部分を変えたら全機能、機能をまたぐテストはいつも入れ、DoD と基準の取り直しの全件の実行は残す。Android と Windows から着手し、iOS / macOS は C ABI 化と合わせる |
| [feature-split-distribution](topics/feature-split-distribution/README.md) | アーキテクチャ | 未着手 | 2026-10-10 | 全 OS で、配布物が全機能を 1 つの成果物に入れている。利用者が必要な機能だけを入れられる形にする。案は「共通部分と機能ごとの成果物に分け、今の名前を全部入りの入口として残す」。2.0.0 は 1 つの成果物のまま出す。着手はほかの OS（iOS / macOS）の C ABI 化の後（利用者の決定）で、全 OS をまとめて設計し、測ってから決める |
| [manual-integrity](topics/manual-integrity/README.md) | ドキュメント | 一部対応 | 2026-09-06 | マニュアルの画像リンク切れ・アンカー切れ（index 機能一覧は修正済み） |
| [android-c-abi](topics/android-c-abi/README.md) | アーキテクチャ | 進行中 | 2026-10-10 | Windows（windows-architecture）と同じ汎用 C ABI を 1 OS ずつ作る、その最初の Android の分。iOS / macOS は Android の後に別のトピックにする。Android には C のコードが無く、ネイティブ利用者に届かないロジックが Unity のブリッジに残っているので、先に `android_library` へ移してから NDK の C ABI（`android_library_capi`）を足し、`unity_android_plugin` を消す。未決事項 D-1〜D-18 のうち 13 個を決定済み（D-10 は ABI だけ）。残りは C ABI の設計で決める。ツールチェーンの移行（Kotlin 2.4.20、AGP 9.3.1、compileSdk 36）もこのトピックで行う。企画書は別モデルのレビューを 3 回通した（区分 A は 0）。段階 0（Gradle のルートを `android/` に移す）は完了。段階 0a（UI テストのスパイク）も完了し、試した項目はすべて自動化できた。UI テストの設計書はレビューを通して決定済み。段階 0b（testTag）も完了。段階 0c（UI テスト）も完了し、設計書の全ケースが実機（API 36）とエミュレータ（API 35）の両方で通る。Dialog を層に分けることと、notification の依存の向きを直すことを 1b に足した。段階 0d（テストのスクリプトの全体と基準）も完了し、両方の環境で全 317 件の基準を記録した。段階 0e（パッケージ名を `com.jonghyunkim.nativetoolkit` に変更）も完了。全体の実行は、0h の後と 1b の後の区切りで行う。段階 0f（AGP 9.3.1、Gradle 9.7.0、Kotlin 2.4.20、Dokka 2.2.0、JVM 17）も完了。段階 0g（compileSdk 36 と androidx の依存）も完了。段階 0h（サンプルの targetSdk 36）も完了し、0e〜0h の後の全体の実行は両方の環境とも 317 件すべて成功で、0d の基準と同じだった。段階 0 はすべて完了。段階 1a のスパイクも完了し、前提 3 つ（Prefab と libc++、`JNI_OnLoad` の 2 回目、利用者に伝わる Kotlin の stdlib）の直し方を実物で確かめた。C ABI の設計書の第 1 部（スレッド・寿命・Context）も、別モデル 2 者のレビューを 5 回通して決定した。段階 1b（Kotlin の API の補完）、2a（照合を OS ごとに）、2b（C ABI の実装。155 関数、テスト、smoke、配布物の照合。実装のレビュー 3 回、両方の環境の全件の実行で基準を取り直した。2026-10-10）も完了。次は 2c（`unity-native-plugin` に渡す対応表と移行ガイド） |
| [memory-sanitizers](topics/memory-sanitizers/README.md) | テスト債務 | 未着手 | 2026-10-10 | Windows・iOS・macOS でメモリのサニタイザー（MSVC / Xcode の AddressSanitizer）を使ったテストをしたことが無い。Android の C ABI は TB-9 で HWASan を入れた。優先度は Windows（C ABI）が高、iOS / macOS（Unity の橋渡しの層）が中 |
| [windows-architecture](topics/windows-architecture/README.md) | アーキテクチャ | 進行中 | 2026-10-03 | Windows ライブラリの構成再編と、C++ API（`WindowsLibrary`）/ 汎用 C ABI（`WindowsLibraryCApi`）への分離。段階 0〜6 と、その後に見つかった 4 件の対処は完了し、1.12.0 でリリースした（2026-10-03）。活性化の自動テストと段階 7（CI）が残り（README 5.3） |

状態の語彙: 未着手 / 企画中 / 設計済 / 進行中 / 一部対応 / 完了

### ここに書かないもの

| 書かないもの | 書く場所 |
|---|---|
| 機能開発のタスク | `<os>/<feature>/` の設計書とチケット |
| 作業ごとの進捗 | 各トピックの README、または `results/` |
| 件数・診断数などの実測値 | 各トピックの README（生成ファイルがあればそちら） |
