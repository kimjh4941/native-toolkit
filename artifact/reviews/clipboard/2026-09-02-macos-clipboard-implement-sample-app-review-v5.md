# macOS Clipboard サンプルアプリ実装レビュー v5

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- ブランチ: `feature/NTKIT-15`
- レビュー対象: 未コミットの作業ツリー（`git status --porcelain` で取得。`git diff develop...HEAD` には現れない）
- 計画ファイル: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md`
- 実装結果ファイル: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v5.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implement-sample-app-review-v4.md`
- 機能設計（参照のみ）: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- ラウンド: v1 から数えて 5 回目

---

## 0. 判定サマリー

| 区分 | 件数 |
|---|---|
| **A. 振る舞いを変える** | **0** |
| **B. 検証手段を変える** | **8** |
| **C. 記述だけを変える** | **8** |

**総合評価: 要修正（軽微）。A は 0。**

ただし**「止める基準」の条件 2 は満たしていない**。追加・修正した検査のうち、
**壊しても落ちないものが 4 件あった**（B-01 / B-02 / B-03 / B-04）。うち B-01 は
**このラウンドで直した A 区分（H-01）そのものを丸ごと戻しても 32 件全通過する**。
条件 1（レビュアー交替）と条件 3（残件の理由つき明記）は満たしている。

---

## 1. レビュー概要

### 対象

| ファイル | 状態 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift` | 新規（808 行） |
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleSupport.swift` | 新規（194 行） |
| `mac/MacLibraryExample/MacLibraryExample/ContentView.swift` | 変更（メニューカード 1 枚） |
| `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift` | 新規（532 行） |
| `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift` | 新規（342 行） |
| `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleWaitRuleTests.swift` | 新規（58 行） |
| `mac/MacLibraryExample/MacLibraryExample.xcodeproj/xcshareddata/` | 新規（共有 scheme） |
| `scripts/check_design_consistency.py` | 変更（免除範囲を front matter に限定） |
| `scripts/tests/test_check_design_consistency.py` | **新規**（本リポジトリで scripts に対する最初のテスト） |
| `agent-rules/coding-rules/common.md` | 変更（新節「検査の書き方（必須）」） |
| `agent-rules/workflows/review-implementation-{feature,sample-app}/workflow.md` | 変更（停止基準の条件 2 から上記を参照） |

### 実測（ベースライン）

すべて再現した。**報告値は正しい。**

| 対象 | 宣言数 | 展開後 | 失敗 |
|---|---|---|---|
| clipboard 分合計（`MacLibraryExampleTests` + UI テスト 2 本） | **32** | **33** | **0** |
| `scripts/tests` | 5 | 5 | 0 |

- `xcresult` の `totalTestCount` = 32、`devicesAndConfigurations[].passedTests` = 33、`failedTests` = 0
- `clean test` のログ中の `warning:` は 4 件すべて `appintentsmetadataprocessor` の
  `No AppIntents.framework dependency found`。**Clipboard 由来の警告 0 件**
- `python3 scripts/check_design_consistency.py <計画 v5>`: FAIL 0
- 実装ファイルは変更していない。開始時と `shasum` および `git status --porcelain` が一致することを確認済み

### 前回からの変化

レビュー v4 の 13 件（A 1 / B 6 / C 6）は、L-02 を除きすべて反映されている。
L-02 の未対応理由は result v5 §3 に記録されており、**新規指摘には数えない**。

---

## 2. 変異検査（本レビューで実施）

**「壊すと落ちる」ことを確認した検査は 3 件、「壊しても落ちない」ことが判明したものが 4 件。**

| # | 壊した内容 | 落ちるべき検査 | 結果 |
|---|---|---|---|
| MU-1 | `private var currentScope: PasteboardScope { activeScope }` を足し、`CopyText` を `Task { await copy(..., scope: currentScope) }` に変更（= レビュー v2 H-02 の再導入） | ST-09 | **通過（穴）** |
| MU-2 | `sampleButton(_ name:)` の引数ラベルを `_ title:` に改名（`buttonBodies` の定義除外が外れる） | ST-09 | **落ちた**（`(bodies.count → 36) == (names.count → 35)`） |
| MU-3 | `private var boardLabel: String { sampleName }` を足し、`Log.d(TAG, "[select] ... board: \(boardLabel) ...")` に変更（= 利用者が付けた名前をログへ出す） | ST-10 | **通過（穴）** |
| MU-4 | `isResultOfThisClick` の `text.contains("[\(label)]")` を `text.contains(label)` に戻す | `ClipboardSampleWaitRuleTests` | **落ちた**（2 件） |
| MU-5 | `tap` の読み取り順を text → sequence に戻す（レビュー v4 M-04 の再導入） | （該当なし） | **通過（検査ゼロ）** |
| MU-6 | `releasePrevious` を named にも効かせる（**このラウンドで直した A 区分 H-01 の再導入**） | （該当なし） | **通過（検査ゼロ）** |
| MU-7 | 免除判定の正規表現から行頭・箇条書きの錨 `^- ` を外す（`**\`PLANNED_SYMBOLS_EXEMPT\`**` だけで一致） | `scripts/tests` 5 件 | **5 件全通過（穴）** |
| MU-8 | `front_matter = text[: headings[1]]` を `text[: headings[-1]]` に変更（front matter = 最後の見出しの手前まで） | `scripts/tests` 5 件 | **5 件全通過（穴）** |

MU-5 と MU-6 は同一実行に同時に適用し、**clipboard 32 宣言 / 33 展開が全通過**することを確認した。
MU-7 / MU-8 はいずれも 5 件全通過したうえで、**免除の穴が実際に再現する**ことを別の入力文書で確認した
（MU-7: 基本情報の表に `**\`PLANNED_SYMBOLS_EXEMPT\`**` と書いた文書が免除される。
MU-8: 4 節ある文書の第 3 節に宣言を置いた文書が免除される）。

### 補足: 誤検知として棄却した仮説

`ClipboardSampleView` の `async` ヘルパー（`run` / `runScopeCreating` / `reportFailure`）が
非分離となり `@State` をメインスレッド外で書き換えているのではないか、という仮説を立てたが、
`run(label:)` の先頭に `precondition(Thread.isMainThread)` を差し込んで UI テストを実行し、
**メインスレッド上で動作していること**を実測で確認した（SwiftUI の `View` プロトコル由来の
分離継承）。**A 区分ではない。**

---

## 3. 重大な問題（A: 振る舞いを変える） — なし

利用者から見た動作が変わる欠陥は見つからなかった。以下は個別に確認済み。

- `releasePrevious` を `.unique` に限定したことで、`CreateNamedPasteboard` → `CopyText` →
  `CreateNamedPasteboard` → `Read` が `items=1` を返す（H-01 の解消）
- `createdUnique` のクリアを `removePasteboard` の成功後に移したことで、
  「作成が失敗」「解放が失敗」のどちらでも回収不能な資源が残らない（L-01 の解消）
- scope の遷移を全経路（named → unique / unique → named / 選択 → 削除 / 一意の連続作成）で
  追い、handle と `activeScope` が食い違う経路は見つからなかった

### 重点 3 への回答: A の修正は狭すぎないか

**狭すぎない。「named は解放しない」が正しい。** 根拠は 3 点。

1. **ライブラリの契約**: `MacClipboardManager.createPasteboard` の DocC は
   「Creates **or fetches** a pasteboard」であり、`- Important:` は
   「**Release a unique one** with `removePasteboard(_:)`」と明示的に unique だけを指す
   （`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:345-354`）。
   named を毎回解放すると、この API の「fetch」半分をサンプルから実演できない
2. **計画の契約**: 計画 §6.1「1. Scope」は `CreateNamedPasteboard` を
   「OP-07 `.named("nt-sample")` → 返る scope を Active に」とだけ定義しており、解放は求めていない。
   解放手段は `RemoveCurrentPasteboard` として別ボタンで用意されている（MS-04 の対象）
3. **回収可能性**: named は固定名で常に再アドレスできるため孤立しない。unique だけが
   「新しい名前が毎回振られ、前の handle が画面から失われる」という孤立条件を満たす

「広げすぎ → 狭めすぎ」の往復にはなっていない。**ただし、この判断を固定する検査が
1 本もない**（B-01）。往復が止まったことを確認する手段がないまま次へ進むことになる。

---

## 4. 改善提案（B: 検証手段を変える） — 8 件

### B-01: このラウンドで直した A 区分（H-01）に検査がない

- 対象: `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:597-608`（`releasePrevious`）、
  `.../ClipboardSampleViewUITests.swift` 全体
- **変異 MU-6 の結果: `releasePrevious` を named にも効かせても、clipboard 32 宣言 / 33 展開が全通過した。**
- 失敗するシナリオ: 誰かが「unique だけ解放するのは非対称で読みづらい」と考えて
  `releasePrevious` を対称化する。`CreateNamedPasteboard` の 2 回目が内容を黙って捨てる
  H-01 が復活するが、テストは緑のまま
- **前回 A で挙げた欠陥に対して、今回追加された検査は 0 本である。** v4 の H-01 も
  「レビュアーが手で `CreateNamedPasteboard` を 2 回押して」見つけたものであり、
  同じ発見手段が次も必要になる
- 提案（UI テスト 1 本、既存の `tap` で書ける）:

  ```
  tap(app, "CreateNamedPasteboard")
  tap(app, "CopyText")
  tap(app, "CreateNamedPasteboard")       // 2 回目: fetch であって作り直しではない
  XCTAssertTrue(tap(app, "Read").contains("items=1"))
  tap(app, "RemoveCurrentPasteboard")     // 後始末
  ```

### B-02: ST-09 は 1 ホップの間接参照で黙る

- 対象: `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:171-221`
- **変異 MU-1 の結果: 通過した。**
- 失敗するシナリオ: `private var currentScope: PasteboardScope { activeScope }` を足し、
  ボタン本体を `Task { await copy("copyText", ..., scope: currentScope) }` にする。
  `activeScope` はボタン本体のテキストから消えるので ST-09 の走査対象外になり、
  実際の読み取りは suspend 後（= 画面が変わった後）に起きる。**レビュー v2 H-02 と同じ欠陥**
- 原因: ST-09 の主題は「ボタンが画面から取る入力を suspend 前に読むこと」だが、
  検査しているのは「ボタン本体のテキストに `@State` 名が現れる位置」である。
  主題は本体テキストの外（computed property、ヘルパーメソッド）へ 1 ホップで逃げられる
- v4 M-01 の修正（入力の一覧を `@State` 宣言から導出）は**左辺**を直したが、
  **右辺（走査範囲）は手つかず**だった

### B-03: ST-10 も 1 ホップの間接参照で黙る

- 対象: `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:223-252`
- **変異 MU-3 の結果: 通過した。**
- 失敗するシナリオ: `private var boardLabel: String { sampleName }` を足し、
  `Log.d(TAG, "[select] kind: \(kind), board: \(boardLabel), ...")` と書く。
  呼び出しテキストに `sampleName` も `nt-sample` も現れないので
  `call.contains("sampleName")` / `call.contains(name)` のどちらも当たらない。
  実行時のログには `nt-sample` が出る（MS-07 違反）
- B-02 と同一の機構。v4 M-02 の修正（床を主題のファイル群で持つ）は**床**を直したが、
  **走査が捕まえられる形**は手つかずだった

### B-04: 「sequence を先に読む」（v4 M-04）に検査が 1 本もない

- 対象: `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:99-110`
- **変異 MU-5 の結果: 順序を text → sequence に戻しても 32 宣言 / 33 展開が全通過した。**
- `ClipboardSampleWaitRuleTests` が検査しているのは `isResultOfThisClick`（判定規則）だけで、
  **「どの順で読むか」という規則は `tap` の中にインラインで残っている**
- common.md 新節はまさにこの形について
  「判定規則そのものが対象なら、規則を純関数に切り出して直接壊す」と書いている。
  **v4 M-04 の修正はその指示に従っていない**
- 提案: 読み取りを `(sequence, text)` を返す 1 つのクロージャに畳み、
  「text を読む前に sequence を読む」ことを注入した fake reader で観測できるようにする

### B-05: 待機規則の「包含関係のある対」が手書きで、ボタン名から導出されていない

- 対象: `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleWaitRuleTests.swift:34-43`
- `snapshot`/`snapshotFiltered`、`read`/`readDataPlainText`、`copyEmpty`/`copyEmptyRepresentations`
  の 3 対が定数として書かれている。**common.md 規則 1（両辺をソースから導出する）に反する**
- 失敗するシナリオ: 新しい包含対（例: `clear` / `clearAll`、`detectValues` / `detectValuesFiltered`）を
  追加する。錨が外れても、この 3 対しか見ていないので気づけない。
  逆に既存ボタンを改名して 3 対が実在しなくなっても、テストは通り続ける（空回りの床がない）
- 同ファイルには `ClipboardSampleViewUITests.buttonNames()` と同じ手段でソースを読む経路が
  すでにあるので、**対の集合はボタン名から機械的に作れる**（`a` が `b` の接頭辞である全対に対し、
  長い方のラベルで短い方の待機が成立しないことを検査する）

### B-06: ST-08 が件数の一致を検査していない（規則 3 を、規則を書いた本人が破っている）

- 対象: `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:151-169`
- `names`（正規表現 `sampleButton\("(\w+)"\)`）と `bodies`（`components(separatedBy: "sampleButton(\"")`）を
  `zip` で対応づけているが、検査しているのは `names.count >= 30` という**床だけ**である。
  ST-09 は同じ 2 集合について `bodies.count == names.count` を持っている。**ST-08 だけ持っていない**
- common.md「集合を機械的に集めるときは、定義側・ヘルパー側を明示的に除き、**件数の一致を検査する**。
  『N 件以上』で済ませない」の直接の違反
- 実害の程度は正直に書く: **通過する変異は作れなかった。** ずれが起きる入力
  （名前に `\w` 以外を含むボタン、コメント中の `sampleButton("Xxx")`）はいずれも
  ずれた対がラベル照合に失敗するか、`Set(names).count == names.count` に引っかかって落ちた。
  **潜在的な規則違反として直す価値はあるが、現時点で生きた穴ではない**

### B-07: `scripts/tests` の 5 件は「宣言の形」も「front matter の範囲」も固定していない

- 対象: `scripts/tests/test_check_design_consistency.py`
- こちらで確認した 2 つの歴史的欠陥（トークンの出現だけで免除 / 宣言行がどこにあっても免除）は
  確かに落ちる。**抜けは 2 つある。**

| 抜け | 変異 | 5 件の結果 | 再現する穴 |
|---|---|---|---|
| 宣言の**形**（行頭 `- ` と太字）を固定していない | 正規表現から `^- ` を外す（MU-7） | **全通過** | 基本情報の表・散文に `**\`PLANNED_SYMBOLS_EXEMPT\`**` と書いた文書が免除される |
| front matter の**上限**を固定していない | `headings[1]` → `headings[-1]`（MU-8） | **全通過** | 4 節ある文書の第 3 節に宣言を置いた文書が免除される |

- 1 番目は机上の話ではない。**計画 v5 の基本情報（`## 0.` の直前まで）には
  `> **v5 の変更（実装レビュー v2 の反映）**` の変更表が入っており**、この種の文書で
  トークンを太字で書く動機は実在する。実際 v5 §0 の表には `PLANNED_SYMBOLS_EXEMPT` への言及がある
- 提案: 次の 2 件を足す
  - 基本情報に `| ... | **\`PLANNED_SYMBOLS_EXEMPT\`** を宣言制にした | ...` という**表の行**を置いた文書が免除**されない**こと
  - 4 節以上ある文書の中間の節に宣言を置いた文書が免除**されない**こと

### B-08: `scripts/tests` を走らせる手順がどこにもない

- 対象: `agent-rules/workflows/design-feature/workflow.md:104`、
  `agent-rules/workflows/review-document/workflow.md:59`、計画 §7.3
- `check_design_consistency.py` を実行する手順は 2 つの workflow にあるが、
  **その checker のテストを実行する手順は workflow にも計画 §7.3 にも無い**。CI も無い
  （`.github/workflows/` が存在しない）
- 失敗するシナリオ: 誰かが checker の免除条件を触る。手元で checker は動くのでそのまま進み、
  `scripts/tests` は誰にも走らされない。**免除条件が 3 回目に壊れても、壊れたことが誰にも見えない**
- 提案: checker を実行する 2 か所に `python3 -m unittest discover -s scripts/tests` を併記する。
  計画 §7.3 の再現コマンドにも足す

---

## 5. 軽微な指摘（C: 記述だけを変える） — 8 件

### C-01: 計画 §4.1 / §4.2 が今回の新規・変更ファイルを取りこぼしている

- 対象: 計画 §4.1 / §4.2（`artifact/designs/.../sample-app-design-v5.md:355-375`）
- 一覧に無いのに作業ツリーで作成・変更されているもの:
  - `scripts/tests/test_check_design_consistency.py`（**新規**）
  - `agent-rules/coding-rules/common.md`（**変更**）
  - `agent-rules/workflows/review-implementation-feature/workflow.md`（**変更**）
  - `agent-rules/workflows/review-implementation-sample-app/workflow.md`（**変更**）
- workflow ステップ 6「変更ファイル一覧と実際の diff が一致しているか」に反する。
  同じ趣旨の指摘（レビュー v3 L-01）が 2 ラウンド前にも出ている

### C-02: 計画 §7.3 の再現コマンドに python 側の 2 コマンドが無い

- 対象: 計画 §7.3（同 `:734-750`）
- 実際の検証には `python3 scripts/check_design_consistency.py <計画>` と
  `python3 -m unittest discover -s scripts/tests` の 2 つが要るが、§7.3 は `xcodebuild` と
  `git diff develop --check` しか書いていない（B-08 と対）

### C-03: 計画 §0 の「本書は宣言する」が実態と食い違う

- 対象: 計画 v5 §0 の中 7 の行（同 `:49`）
  「文書が `PLANNED_SYMBOLS_EXEMPT` と宣言した場合のみ SKIP。**本書は宣言する**」
- 実際には **v5 は宣言していない**（基本情報に宣言行が無い）。checker も
  `OK named symbols exist in the implementation` を返しており、免除されずに通っている
- 宣言していないほうが正しい状態なので、直すべきは文言のほう

### C-04: common.md 規則 1 の適用範囲が広すぎる

- 対象: `agent-rules/coding-rules/common.md:200`
  「**両辺をソースから導出する。** 期待値を手で書き写さない」
- 文字どおり読むと、純関数の単体テストがすべて違反になる。実際、この規則に照らすと
  ST-01（fixture の期待値）、ST-03（formatter の期待文字列）、
  ST-04 の `arguments: [1505, 1507]` が違反に見える。
  **しかし ST-04 は手書きが正しい**: `SampleOutcome.codesWithACallerSuppliedName` から
  導出してしまうと、集合から 1507 を外したときにテスト側も一緒に外れて黙って通る
- 提案: 適用範囲を「**ソースから集合または対応づけを取り出して突き合わせる検査**」に限定し、
  「関数の入出力を直接与える検査には適用しない」と明記する

### C-05: common.md 規則 3 の「件数の一致」は対応づけを作る検査にしか意味がない

- 対象: 同 `:202`
- ST-05 の `publicOperations()` のように**単一の集合**を集める検査には、
  突き合わせる相手の件数が存在しない（ST-05 は `published.count >= 16` という床を持ち、
  これは規則 3 が禁じている「N 件以上」に見える）。実際には ST-05 の設計は正しい
  （`published ⊆ called` が自己強制になっている）
- 提案: 「**2 つの集合を `zip` などで位置対応させるとき**は件数の一致を検査する」と条件を付ける

### C-06: `buttonBodies` の定義除外がリテラル `"_ name:"` に依存している

- 対象: `ClipboardSampleTests.swift:364-365`
- 変異 MU-2（引数ラベルを `_ title:` に改名）で確認したとおり、**件数一致の検査が拾うので
  実害は無い**。ただし落ちたときのメッセージは
  `(bodies.count → 36) == (names.count → 35)` であり、「除外が壊れた」とは読めない
- 提案: 除外の根拠を「`sampleButton(` の直後が `_` で始まる（= 宣言）」のように
  引数名から独立させるか、除外が 1 件だけ効いたことを別に検査する

### C-07: ST-10 の床 5 に対し、実際の呼び出しは 11 件

- 対象: `ClipboardSampleTests.swift:248`
- `ClipboardSampleView` の `Log.` 呼び出しは 11 件、`ClipboardSampleSupport` は 0 件。
  床が 5 なので**6 件消しても通る**。規則 2（主題の単位で床を持つ）は満たしているが余裕が大きい

### C-08: `logCalls` の括弧数えが、文字列中の `)` で呼び出しを早く閉じる

- 対象: `ClipboardSampleTests.swift:313-335`
- `depth` は蓄積したテキスト全体の `(` と `)` を数え直しているため、ログ本文に `)` が
  含まれると継続行に到達する前に呼び出しが閉じる。例:

  ```swift
  Log.d(TAG, "[x] :) " +
      "\(sampleName)")
  ```

  1 行目で depth が 0 になり、`sampleName` を含む 2 行目は検査対象から外れる
- 実コードには該当が無い（要確認ではなく、現時点では潜在）

---

## 6. 重点 2 への回答: common.md「検査の書き方（必須）」の妥当性

### 6.1 規則そのもの

**方向は正しい。4 規則はいずれも、このプロジェクトで実際に起きた欠陥から抽出されており、
実務で守れる粒度である。** 修正すべき点は C-04 / C-05 の 2 点（適用範囲の限定）。

### 6.2 今回の実装は規則を守れているか

規則を物差しに全検査を当てた結果は次のとおり。

| 検査 | 規則1 導出 | 規則2 床 | 規則3 件数一致 | 規則4 錨 | 「壊して確認」 |
|---|---|---|---|---|---|
| ST-01 / ST-02 | 対象外（C-04） | - | - | - | 未実施 |
| ST-03 / ST-04 / ST-07 | 対象外（C-04） | - | - | 適合 | 未実施 |
| ST-05 | 適合 | 適合（16 / 非空） | 対象外（C-05） | 適合 | 済（v3） |
| ST-06 | 適合 | 適合（4 件） | - | 適合 | 済（v3） |
| ST-08 | 適合 | 床のみ | **違反（B-06）** | 適合 | 未実施 |
| ST-09 | 適合 | 適合 | 適合 | 適合 | **済だが穴（B-02）** |
| ST-10 | 適合 | 適合 | - | 適合 | **済だが穴（B-03）** |
| `tap` の読み取り順 | - | - | - | - | **検査ゼロ（B-04）** |
| `isResultOfThisClick` | 適合 | - | - | 適合 | 済（MU-4 で再確認） |
| WaitRule の包含対 | **違反（B-05）** | **床なし（B-05）** | - | 適合 | 未実施 |
| `scripts/tests` | 適合 | 適合（非免除時に走ることを確認） | - | **不足（B-07）** | 済だが穴（B-07） |

**規則を書いた本人が破っている箇所は 2 件（B-05、B-06）。** どちらも
「規則を追加したこのラウンドで触った検査」ではなく、前ラウンドまでに書かれ、
今回の見直し対象に入らなかったものである。**規則を足したときに既存の検査を
その規則で洗い直す手順が無い**ことが原因で、これは規則本文ではなく運用の問題にあたる。

### 6.3 停止基準の条件 2 からの参照の仕方

**適切である。** 参照先の見出し（`### 検査の書き方（必須）`）と参照文字列（「検査の書き方」）は
前方一致で解決でき、2 つの review workflow で文言も一致している。
「同じ種類の指摘が続くときは、個別の検査を足すのではなくその規則を疑う」の追記も、
サーキットブレーカーの表と役割が重複せず、条件 2 の側に置いたのは妥当。

1 点だけ: **規則は review 側の停止基準からしか参照されていない。**
`implement-feature` / `implement-sample-app` の workflow は common.md 全体を読み込むので
到達はできるが、「検査を書く」場面から名指しされていない。
検査を書くのは implement 側なので、そちらのテスト作成手順からも参照すると効く（C 相当、任意）。

---

## 7. 重点 4 への回答: `scripts/tests` の 5 件は過去 2 回の欠陥を捕まえるか

**捕まえる。ただし抜けが 2 つある**（B-07）。詳細は B-07 の表を参照。

補足で確認したこと:

- 5 件は「免除されない」ことだけを主張する形が 3 件あり、報告フォーマットが変われば
  空回りしうるが、`test_a_declaration_in_the_info_section_exempts_the_document`（免除される側）と
  `test_the_check_actually_runs_when_the_document_is_not_exempt`（検査が実際に走る側）が
  両方向を押さえているので、**空回りにはならない**
- `## ` がコードフェンス内にある文書では front matter の範囲が早く切れるが、
  その方向の誤りは「免除されない」（= 声を上げて落ちる）側なので安全
- `__pycache__/` は `.gitignore:35` で無視される。`scripts/tests/__init__.py` は不要
  （`unittest discover` は動作する）

---

## 8. サーキットブレーカー: 5 ラウンド目に対する所見

workflow の表では「5 ラウンドを超えた」「同じ種類の指摘が 3 回続く」が立ち止まる合図とされている。
**両方に該当している。**

### 8.1 同じ種類の指摘は、今回で 5 ラウンド連続

| ラウンド | 指摘の中身 | 修正した箇所 |
|---|---|---|
| v1〜v3 | 検査が手書きの一覧と突き合わせている | 両辺をソースから導出 |
| v4 M-01 | 入力の一覧が `activeScope` 決め打ち | 一覧を `@State` 宣言から導出 |
| v4 M-02 | 床が他画面のログで満たされる | 床を主題のファイル群で持つ |
| v4 M-03 | `zip` が定義側を拾ってずれる | 定義を除外し件数一致 |
| **v5（本レビュー）** | **走査範囲の外へ主題が 1 ホップで逃げる** | **未対応（B-02 / B-03）** |

### 8.2 これを生んでいる機構

**ST-08 / ST-09 / ST-10 はいずれも「ソースのテキストを走査して、そこに何が書かれているか」で
契約を判定している。** 走査で書いた検査は、次の 2 つを同時に決めなければならない。

1. **何を探すか**（左辺） — v1〜v4 の修正はすべてここを直してきた
2. **どこを探すか**（走査範囲） — **一度も直っていない**

MU-1 と MU-3 は、2 を直していない検査は **computed property を 1 本足すだけで黙る**ことを示す。
common.md の 4 規則は 1 については十分だが、2 について何も言っていない。
**個別に ST-09 と ST-10 を直しても、6 ラウンド目に同じ形が別の検査で出る。**

### 8.3 提案（個別の修正ではなく、機構への対処）

**(a) common.md に 5 つ目の規則を足す**

> **走査で書いた検査は、走査範囲そのものも検査する。** 主題が範囲の外（別の関数、
> computed property、ヘルパー）へ移せる形なら、その検査は 1 ホップで黙る。
> 範囲を広げられないなら、**走査ではなく構造で不可能にする**（主題を 1 か所へ集約し、
> その 1 か所だけを検査対象にする）。

**(b) ST-09 を走査から構造へ移す**

`sampleButton` が入力の捕捉を担い、クロージャに値として渡す形にすると、
ボタン本体から `@State` を読む手段そのものが無くなる。

```swift
// 捕捉は sampleButton が 1 か所で行う。ボタン本体は値しか見られない。
private func sampleButton(_ name: String,
                          action: @escaping (SampleInputs) -> Void) -> some View
```

そうすると ST-09 は「**どのボタン本体にも `@State` 名が 1 つも現れない**」という
全ファイル的な性質になり、computed property を足しても迂回できない
（`currentScope` を足しても、それを読む場所がボタン本体である以上は検出される）。

**(c) ST-10 も同様に、ログの生成を 1 関数へ集約する**

サンプルのログを `logSample(_ marker: String)` の 1 本に集約し、
「`Log.` の呼び出しはその関数の中にしか現れない」を検査する。
そのうえで `logSample` の引数が補間を含まないことを検査すれば、
`boardLabel` のような間接参照が入り込む場所が無くなる。

**(d) レビュアーを再度替える**

条件 1 は満たされているが、**v4 と v5 の 2 ラウンド続けて、レビュアーが作った変異だけが
穴を見つけている**（v4: ST-09 / ST-10、v5: MU-1 / MU-3 / MU-5 / MU-6）。
実装側の自己変異検査（result v5 §5 の 4 件）は、いずれも
**「前ラウンドの指摘そのもの」を再導入する形**であり、指摘されていない形の変異が作られていない。
変異の作り方（指摘の再現ではなく、契約を保ったまま実装の形だけ変える）を
implement 側の手順に足すのが本質的な対処になる。

---

## 9. 計画書整合性チェック

| 項目 | 判定 | 補足 |
|---|---|---|
| 全セクション・全ボタンの実装 | **○** | 10 セクション / 35 ボタン。§6.1 の表と 1 対 1 で一致 |
| API 呼び出し方針の一致 | **○** | 公開 16 操作すべてがサンプルから呼ばれている（ST-05 で機械確認） |
| システム設定（scheme / entitlements 等）の正確性 | **○** | 共有 scheme を追加。`project.pbxproj` は非変更（§4.2 の前提どおり） |
| 変更ファイル一覧との diff 整合 | **△** | C-01（`scripts/tests/`、`common.md`、workflow 2 本が一覧に無い） |
| 計画書との差分（追加判断）の result ファイルへの記録 | **○** | result v5 §1〜§4 に記録。L-02 の未対応理由も §3 にある |

---

## 10. サンプルアプリパターン適合チェック

| 項目 | 判定 | 補足 |
|---|---|---|
| メニュー導線（`ContentView`） | **○** | 既存 3 画面と同じ `NavigationLink` + `menuCard` + `.buttonStyle(.plain)` |
| 画面構成パターン（タイトル / result / スクロール / セクション） | **○** | 既存パターンに沿う。`sectionView` は既存の `private` ヘルパーと同型（workflow ステップ 6 の複製許容に該当） |
| 成功 / 失敗表示フォーマット | **○** | `SampleOutcome.displayText` が 1 か所で生成。既存画面のマーカー体系と一致 |
| 共通 UI 部品の利用 | **○** | `PasteButtonHost` のみ新規。理由は計画 §5.4 に記載 |

---

## 11. プロジェクトルール適合チェック

| 項目 | 判定 | 補足 |
|---|---|---|
| `common.md` 準拠（Clean Architecture / 依存方向） | **○** | サンプルは `MacLibrary` のみ import。ST-06 が機械確認 |
| `common.md`「検査の書き方」準拠 | **△** | B-05 / B-06 の 2 件が違反（§6.2 の表） |
| `mac.md` 準拠 | **○** | `mac.md` の適用対象は `mac/MacLibrary/` と `mac/UnityMacPlugin/` でサンプルは範囲外。それでも `private let TAG` とメソッド先頭の `Log.d` の形は踏襲されている |
| サンプルアプリの依存方向（Unity プラグイン非依存） | **○** | `import UnityMacPlugin` 0 件（ST-06） |
| ログ網羅性 | **○** | 画面の入口関数と全 runner に `Log.d`。payload・利用者が付けた名前は出さない（ST-04 / ST-10） |
| ドキュメンテーションコメント網羅性 | **○** | 型・runner・非自明な private すべてに `///`。「なぜそうしたか」が書かれている |

---

## 12. 手動確認観点の充足

| ID | 判定 | 補足 |
|---|---|---|
| MT-01 / MT-02 / MT-03 / MT-04 / MT-06 | **△（未実施）** | result v5 §7 に open として記録済み |
| MT-07 | **△（未実施）** | 2 OS 環境が必要 |
| MT-08 | **△（未実施）** | 実機 2 台が必要。手順は `CopyWithCurrentOptions` を名指しする形に更新済み |
| MT-09 | **△（判定保留）** | RK-22 |
| MS-01 | **○** | `testEveryButtonReportsAResult`（対象はソースから導出） |
| MS-02 | **○** | `testAnExpectationThatDoesNotHoldIsShownAsAFailure` + ST-07 |
| MS-03 | **○** | `testTheScopeArgumentFollowsThePicker` |
| MS-04 | **△（未実施）** | named / unique の作成 → 操作 → 削除。**B-01 の提案テストがこの一部を自動化できる** |
| MS-05 | **○** | `testObservationStopsWhenTheScreenIsLeft` |
| MS-06 | **△（未実施）** | View 破棄時の load キャンセル |
| MS-07 | **○** | `testACallerSuppliedPasteboardNameIsNotShown` + ST-04 + ST-10（ただし ST-10 に B-03 の穴） |
| MS-08 | **○** | ST-06 |

**△ は「充足」ではなく未完の open 項目として扱う。** GUI アプリであり、
ビルドと自動テストの成功だけでは MT-01〜MT-09 / MS-04 / MS-06 の確認にならない。

---

## 13. 総合評価

**要修正（軽微）。A は 0 件。**

### 次へ進めるか

**「A が 0」は満たしている。「止める基準」の 3 条件のうち、条件 2 が満たせていない。**

| 条件 | 判定 |
|---|---|
| 1. レビュアーを替えて 1 回通していること | **満たす**（v4 と v5 で別レビュアー） |
| 2. 追加した検査が、壊すと落ちることを確認済みであること | **満たさない**。B-01 / B-02 / B-03 / B-04 の 4 件は壊しても落ちない |
| 3. 直さない残件が、理由つきで明記されていること | **満たす**（result v5 §3 / §7） |

### 残リスク

- **実機確認が必須の観点が 10 件 open**（MT-01〜MT-04 / MT-06〜MT-09 / MS-04 / MS-06）。
  自動テストの全通過を機能確認の代替として楽観視しない
- **前回 A で直した H-01 に検査が無い**（B-01）。往復（広げすぎ → 狭めすぎ）が
  止まったことを機械的に確認する手段が今も無い
- **ST-09 / ST-10 は 1 ホップの間接参照で黙る**（B-02 / B-03）。
  この 2 本は MS-03 と MS-07 の裏づけであり、裏づけが穴を持ったまま合格条件に数えられている

### 推奨する進め方

1. **B-01 を先に足す**（UI テスト 1 本。MS-04 の自動化も兼ねる）
2. **B-02 / B-03 を、個別の穴埋めではなく §8.3 の (a)〜(c) として直す。**
   5 ラウンド連続で同じ種類が出ているため、ST-09 と ST-10 を継ぎ足しで直すと
   6 ラウンド目に同じ形が別の検査で出る
3. B-04 / B-05 / B-07 / B-08 は検査の追加のみで、実装には触れない
4. C 系はまとめて 1 コミットでよい

---

## 付録: 検証コマンド（本レビューで実行したもの）

```bash
cd /Users/jonghyunkim/Desktop/native-toolkit/mac
xcodebuild clean test -workspace MacWorkspace.xcworkspace -scheme MacLibraryExample \
  -destination 'platform=macOS' \
  -only-testing:MacLibraryExampleTests \
  -only-testing:MacLibraryExampleUITests/ClipboardSampleViewUITests \
  -only-testing:MacLibraryExampleUITests/ClipboardSampleWaitRuleTests \
  -resultBundlePath /tmp/rev5.xcresult
xcrun xcresulttool get test-results summary --path /tmp/rev5.xcresult

cd /Users/jonghyunkim/Desktop/native-toolkit
python3 -m unittest discover -s scripts/tests
python3 scripts/check_design_consistency.py \
  artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md
```

変異検査は上記に対して MU-1〜MU-8 を 1 件ずつ（MU-5 / MU-6 のみ同時に）適用して実行した。
**実行後、対象ファイルはすべて開始時の内容へ戻し、`shasum` と `git status --porcelain` が
開始時と一致することを確認済み。**
