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
| [manual-integrity](topics/manual-integrity/README.md) | ドキュメント | 一部対応 | 2026-09-06 | マニュアルの画像リンク切れ・アンカー切れ（index 機能一覧は修正済み） |
| general-c-abi（README は着手時に作る） | アーキテクチャ | 未着手 | 2026-10-03 | Android / iOS / macOS にも、Windows（windows-architecture）と同じ汎用 C ABI を 1 OS ずつ作る予定。今の JSON ブリッジは C 構造体に書き換えず、新しい C ABI を別の成果物として足してからブリッジを消す（Windows の段階 5 の順番）。Windows の C ABI 設計書の E-1〜E-21、`struct_size` による版の管理、対応表（8.3）、`check_c_abi_contract.py` / `check_manual_c_examples.py` を引き継ぐ。OS ごとの違いは、スレッドモデルと、ホスト言語の寿命の規則（ARC、JNI のグローバル参照）になる見込み |
| [windows-architecture](topics/windows-architecture/README.md) | アーキテクチャ | 進行中 | 2026-10-03 | Windows ライブラリの構成再編と、C++ API（`WindowsLibrary`）/ 汎用 C ABI（`WindowsLibraryCApi`）への分離。段階 0〜6 と、その後に見つかった 4 件の対処は完了。develop へのマージ、1.12.0 のリリース、活性化の自動テスト、段階 7（CI）が残り（README 5.3） |

状態の語彙: 未着手 / 企画中 / 設計済 / 進行中 / 一部対応 / 完了

### ここに書かないもの

| 書かないもの | 書く場所 |
|---|---|
| 機能開発のタスク | `<os>/<feature>/` の設計書とチケット |
| 作業ごとの進捗 | 各トピックの README、または `results/` |
| 件数・診断数などの実測値 | 各トピックの README（生成ファイルがあればそちら） |
