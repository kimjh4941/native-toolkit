# レビュー結果

- 日付: 2026-11-23
- 対象: `scripts/mac_unit_audit.json`（U-29。この Mac で許可なしに流してよい `MacLibraryTests` の suite の表）と、それを照らすランナーの関数（`audit_state`、`_audit_for`、`AUDIT_TREE_PATHS`）
- トピック名: macos-c-abi（段階 0d の単体テストの監査、1 回目）
- 判定: **区分 A は 0 → 直した**。`review` はまだ null のまま（直した表を Codex に短く確かめてもらってから埋める）
- 別モデルによる独立レビュー: Codex（読むだけ。テストもスクリプトも流していない）
- 全文: scratchpad の `review/unit-audit-codex-v1.md`（A 0、B 4、C 2）

区分: A = 私物に届く suite を許している / B = 確かめの不足 / C = 記述。

## Codex の結論（要約）

許可した 20 suite に、一般の貼り付け板・通知の権限・通知センター・本物の共有のサービス・画面の表示・私物のファイル・設定の変更に届く経路は見つからなかった。今の表は `review: null` なので、ランナーが許すのは 0 件（20 は候補の数）。

## 指摘と直したこと

| # | 指摘 | 直したこと |
|---|---|---|
| B-1 | 入れ子の suite `ClipboardPasteLoaderTests.ItemProviderSourceTests` が、`suites` にも `notListed` にも無い（親が除外なので、今は流れない） | 表の `notListed` に完全名（`Outer.Inner`）で足した（今の除外は保つ）。ランナーは、計画を作るときに `MacLibraryTests` の列挙から入れ子を含む suite の一覧を作り（`enumerated_suites`）、表と突き合わせる（`audit_inventory_problems`）。表に無い suite がある、または許した suite の中の入れ子が許されていない（外側を流すと入れ子も流れる）ときは、表を失効させて何も流さない。VM で取った列挙の fixture で、今の表に漏れが無いことを自己テストで確かめる |
| B-2 | `ClipboardDocumentationTests` と `ClipboardLogAuditTests` が読む `mac/UnityMacPlugin/UnityMacPlugin/Clipboard` が、監査のハッシュの範囲の外 | `AUDIT_TREE_PATHS` に足した。2 つの suite の理由を「MacLibrary/Clipboard と UnityMacPlugin/Clipboard の Swift のソースを `#filePath` から読んで文字を確かめる（両方の木が treeHash に入る）」にした |
| B-3 | `reviewed` は、`by`・`date` があって `treeHash` が同じかを見るだけ。表の中身にも、別のモデルかにも結んでいない | `review` は `by`・`model`・`file`（`artifact/topics/macos-c-abi/reviews/` の下のレビューの記録）・`date`・`treeHash`・`tableDigest`（`review` を除いた表の sha256）を持つ。照合は、どれも埋まっていて、記録が reviews の下にあり、`model` が表の `auditedModel`（今は Claude）と違い、`treeHash` と `tableDigest` が今の表と木に一致するときだけ通す。表が少しでも変われば review は失効する。表の `about` に書いた |
| B-4 | 独自の SHA-256 の集約の値を、別の計算で確かめていない | 下の「ハッシュ」の節。直した後の treeHash を、ランナーの関数を使わずに shell で計算し、一致した |
| C-1 | `ClipboardRepositoryImplTests` の理由が、一般の貼り付け板を resolve すると読める | 「integration tests against real unique and named pasteboards; removing the general or a standard pasteboard checks the refusal before any resolve; adding it to the allowed suites needs its own review」にした |
| C-2 | `ClipboardTypeIdentifierValidatorTests` を「pure」とするのは広すぎる（`UTType` の解決と conformance を呼ぶ） | 「string syntax, and UTType resolution and conformance of synthetic type identifiers; no app registration, no file opening, no settings change」にした |

## ハッシュ（B-4）

直した後の `treeHash` は `50c3fda00d98bfc548517118d37a034355940f7176a58db96b21bc1fdce99259`（前は `884fb805…`。範囲に plugin の Clipboard を足したため変わった）。

規則（`tree_hash` と同じものを、ランナーを使わずに書いた）:

1. 対象の道（`mac/MacLibrary/MacLibrary`、`mac/MacLibrary/MacLibraryTests`、`mac/UnityMacPlugin/UnityMacPlugin/Clipboard`、`mac/MacLibrary/MacLibrary.xcodeproj/project.pbxproj`、`mac/MacLibrary/MacLibrary.xcodeproj/xcshareddata/xcschemes`、`mac/MacWorkspace.xcworkspace/contents.xcworkspacedata`）について `git ls-files -co --exclude-standard -z -- <道...>` でファイルを並べる
2. `mac/MacLibraryExample/build/` で始まるものと `.DS_Store` を除き、バイト順（`LC_ALL=C sort`）に並べる
3. 各ファイルについて `<道>\0<中身の sha256 の 16 進>\n` を作る（symlink は指す先の文字列の sha256。無いファイルは飛ばす）
4. それをすべてつないだものの sha256

shell（`git`、`tr`、`grep`、`sort`、`shasum -a 256`、`awk` だけ）で計算した値は `50c3fda0…9259` で、ランナーの `tree_hash` と一致した（114 ファイル）。

## 確かめ

この Mac の自己テスト（偽の口）で、入れ子の漏れ・許した suite の中の許されていない入れ子・review の各欄の欠け・同じモデル・別の表の digest・reviews の外の記録・表の変更による失効を確かめた。VM の変異に、この 6 つの判定を壊す変異を足した（作業の記録の 15.1）。

## 残したこと

- `review` を埋めること（直した表を Codex に短く確かめてもらってから。`model` は Codex、`file` はその確かめの記録）。それまで、この Mac で流せる単体テストは 0 件
- 計画を作るときに列挙を渡すつなぎ（`cmd_preflight` → `_audit_for`）は、関数の自己テストと、`--where mac --dry-run`（VM で取った本物の列挙を使う。表との突き合わせに漏れは無く、`[audit]` は review が無いことだけを出した）で確かめた。つなぎだけを壊す変異は置いていない
