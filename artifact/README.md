# artifact

設計・検討文書の置き場。機能とそれ以外で分ける。

| ディレクトリ | 対象 | 作り方 |
|---|---|---|
| `features/<feature>/` | OS 機能の追加（clipboard / notification / share など） | `agent-rules/workflows/` のワークフローで作成する |
| `topics/<topic>/` | 機能単位でない課題（移行・検証負債・構成変更など） | 手動で作成する。ワークフローは使わない |

## features/

`features/<feature>/{plans,designs,results,reviews}/` に、各ワークフローが保存先として指定する文書を置く。

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

状態の語彙: 未着手 / 企画中 / 設計済 / 進行中 / 一部対応 / 完了

### ここに書かないもの

| 書かないもの | 書く場所 |
|---|---|
| 機能開発のタスク | `features/` の設計書とチケット |
| 作業ごとの進捗 | 各トピックの README、または `results/` |
| 件数・診断数などの実測値 | 各トピックの README（生成ファイルがあればそちら） |
