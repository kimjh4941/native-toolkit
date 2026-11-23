# レビュー結果

- 日付: 2026-11-23
- 対象: `scripts/mac_unit_audit.json`（U-29）の v1 の直し（`88700f2a`）
- トピック名: macos-c-abi（段階 0d の単体テストの監査、2 回目）
- 判定: **区分 A・B・C とも 0 → 決定**。表の `review` に、この記録と Codex の値を書いた
- 別モデルによる独立レビュー: Codex（読むだけ。B-4 のため、読むだけの git・`shasum`・`python3 -I` でのハッシュの計算だけを許した。テスト・ランナー・自己テストは流していない）
- 全文: scratchpad の `review/unit-audit-codex-v2.md`
- 前の回: `2026-11-23-macos-c-abi-unit-audit-review-v1.md`

## v1 の指摘の確かめ

| v1 | 結果 |
|---|---|
| B-1（入れ子の suite） | 直った。`notListed` に完全名で載り、列挙と表の突き合わせがある |
| B-2（plugin の Clipboard がハッシュの外） | 直った。`AUDIT_TREE_PATHS` に入った |
| B-3（review が表の中身と別のモデルに結ばれていない） | 直った。`model` と `auditedModel` の比較、`treeHash` と `tableDigest` の両方の一致を求める |
| B-4（treeHash を独立に確かめていない） | 直った。Codex がランナーの関数を import せず、規則を読んで 114 ファイルから計算し、表の値と一致した |
| C-1・C-2（理由の文） | 直った |

## 表に書いた値

- `treeHash`: `50c3fda00d98bfc548517118d37a034355940f7176a58db96b21bc1fdce99259`
- `tableDigest`（`review` を除いた表）: `50d23b41254626b9db0bfb4d68e4591817d408458cad011b5ad164244b013cb6`。`review` を書いた後に計算し直し、同じ値だった
- 書いた後、ランナーの `_audit_for` で照らした（この Mac。読むだけ）: `expired` は false、許す suite は 20、問題は 0

## 残る限界

- preflight と `_audit_for` のつなぎだけを壊す変異は無い（v1 の記録に書いた既知の限界。つなぎは静的に確かめた）
- `review` の `file` と `model` の照合は文字の照合で、記録の中身やモデルの実体を認証するものではない
- `MacLibrary`・`MacLibraryTests`・plugin の Clipboard・プロジェクトのどれかが変われば表は失効する（0e で必ず変わるので、0e の後に監査とレビューをやり直す）
