# トピックの README が大きすぎる

- 記録日: 2026-10-31
- 分類: ドキュメント（agent の作業のしやすさ）
- 状態: 未着手
- 関連: [ios-c-abi](../ios-c-abi/README.md)、[android-c-abi](../android-c-abi/README.md)、[artifact/README.md](../../README.md)

## 何が問題か

トピックの README に、課題・決定・段階の表・検証・DoD・状態の記録をすべて書いているので、大きいトピックの README が一度に読めない大きさになっている（2026-10-31 に測った値）。

| ファイル | 大きさ |
|---|---|
| `artifact/topics/ios-c-abi/README.md` | 119 KB |
| `artifact/topics/android-c-abi/README.md` | 108 KB |
| `artifact/topics/windows-architecture/README.md` | 48 KB |
| `artifact/topics/migration/README.md` | 33 KB |

agent はファイルを分けて読むことになり、決定（D-x）の 1 行を確かめるにも長い範囲を読む。表の 1 行に段階の経過を書き足し続けているので、行も長い（`artifact/README.md` のトピック一覧は 1 行が 3,000 文字を超える）。状態の行と段階の表と DoD に同じことを何度も書き、書き漏れて食い違うこともあった（ios-c-abi の 0d の行の `UnityIosPluginTests` の記述が古いまま残っていた）。

## 対応方針（案）

- README には、状態・要約・次にすること・ほかのファイルへのリンクだけを置く
- 決定（D-x）、段階の表、検証、DoD を、`plans/` などの別のファイルに分ける
- 段階の経過（何をいつ確かめたか）は、段階の行に書き足さず、`results/` の作業の記録へのリンクにする
- `artifact/README.md` のトピック一覧の要約は数行に収め、経過はトピックの README に任せる

## 着手するときに確かめること

- 着手の時期: 進行中のトピックの途中で分けると、作業の記録や設計書からの参照（「README の D-16」「5 章の 0e の行」など）が崩れる。ios-c-abi の区切り（リリースの後）で行うか、新しいトピックから新しい形で始める
- 分けた後も、ワークフローやスクリプト（`scripts/check_design_consistency.py` など）が README の決まった場所を読んでいないか
