# macOS Clipboard サンプルアプリ実装レビュー v4

## レビュー対象

- 日付: 2026-09-02
- 対象 OS: macOS 15 以降（実行ホストは macOS 26.3 / Xcode 26.3）
- ブランチ: `feature/NTKIT-15`
- サンプル計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v4.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implement-sample-app-review-v3.md`
- 機能設計（参照のみ）: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 対象差分: `git status --porcelain`（サンプル本体・unit test・UI test 2 本・共有 scheme は untracked、
  `ContentView.swift` と `scripts/check_design_consistency.py` は変更済み）

**指摘は A 1 件 / B 6 件 / C 6 件。A-count は 0 ではない。**

---

## レビュー概要

- レビュー v3 の 8 件はすべて実装に反映されている。`try?` はサンプル配下から消え（`grep` で 0 件）、
  `CopyWithCurrentOptions` は toggle を押下時に捕捉し、待機規則は純関数 `isResultOfThisClick` に
  切り出されて 4 件のテストが付いた。ST-09 は capture 位置を、ST-10 はサンプルのログを検査する。
- 報告された数値はすべて xcresult で再現した（後述「検証結果」）。テスト 30 宣言 / 31 展開 / 失敗 0、
  clean build の Clipboard 由来警告 0。MacLibrary 307 / 351、UnityMacPlugin 75 / 76 も再現した。
- result v4 §2 が主張する 4 件の変異はいずれも独立に再現した（ST-09 / ST-10 / 待機規則 / 免除範囲）。
- **一方、H-01 の修正が過剰適用されている。** `releasePrevious` は unique だけでなく named にも
  適用され、`CreateNamedPasteboard` の再押下が named pasteboard の内容を黙って破棄する。
- **「同じ形が別の場所に残っていないか」の答えは「コードには残っていないが、検査には残っている」。**
  押下時入力の捕捉漏れも `try?` もサンプルコードには third instance がない（機械的に列挙して確認）。
  しかし今回追加した検査 3 本のうち 2 本が、**自分で対象を決めている**（ST-09 は `activeScope` 決め打ち、
  ST-10 は空回り防止の下限を他画面のログで満たす）。両方とも変異で実証した。

---

## 前回指摘の追跡

| 前回 | 区分 | 判定 | 再確認結果 |
|---|---|---|---|
| H-01 unique 再押下で孤立 | A | **一部解消・過剰適用** | 作成前に解放するようになり unique の孤立は解消。ただし named にも同じ解放を適用したため新規 H-01（本書）が発生 |
| H-02 Append setup の `try?` | A | 解消 | `do / catch` で `reportFailure` へ渡す（`ClipboardSampleView.swift:287-296`）。サンプル配下に `try?` は 0 件 |
| M-01 通常 Copy が toggle に従う | A | 解消 | `copy` helper は `MacClipboardManager.shared.copy(content, scope:)` の既定（`.default` = `localOnly: true`）を使い、toggle は `CopyWithCurrentOptions` の押下時にだけ読む（`:244-257`, `:546-553`） |
| M-02 待機規則の変異証明 | B | 解消 | 規則を純関数へ切り出し、連番条件を落とす mutant で `testTheSameTextFromAnEarlierClickIsNotAccepted` が落ちることを独立に再現 |
| M-03 ST-09 の capture 位置 | B | **一部解消** | `activeScope` については capture が最初の `Task` / `await` より前であることを検査し、mutant で落ちる。ただし対象が `activeScope` 決め打ちで、M-01 が足した `localOnly` を見ていない（本書 M-01） |
| M-04 サンプルのログ監査 | B | **一部解消** | ST-10 は継続行を含めて `Log.` を拾い、名前をログする mutant で落ちる。ただし空回り防止が効いていない（本書 M-02） |
| M-05 免除の front matter 限定 | B | **一部解消** | appendix へ移した宣言行は免除されないことを実測。ただし `## ` 見出しが 1 個以下の文書では全文走査に戻る。スクリプトのテストは依然 0 本（本書 M-06） |
| L-01 計画のファイル一覧 | C | 解消 | 計画 v5 §4.1 に UI テスト 2 本と共有 scheme、§4.2 に検査スクリプトがある |

---

## 重点確認への回答

### 1. 同型の欠陥が他に残っていないか

**サンプルコードには残っていない。機械的に確認した。**

- **`try?` による arrange 失敗の握りつぶし**: `mac/MacLibraryExample/` 配下の `try?` は
  `ClipboardSampleTests.swift:383`（ソース読み取りのファイル欠落許容）1 件のみ。実装経路には無い。
- **押下時に捕捉すべき入力の捕捉漏れ**: 35 個の `sampleButton` の body を全部取り出し、11 個の
  `@State` のうちどれを読むかを列挙した。押下時入力（操作の引数になるもの）は `activeScope` と
  `localOnly` の 2 つだけで、両方とも `Task` より前で捕捉されている。残りの `isObserving` /
  `reachedCodes` / `lastOwnership` / `pasteButton` / `resultText` / `resultSequence` は出力側で、
  押下時に読む必要がない。`createdNamed` / `createdUnique` は資源台帳で、最新値を読むのが正しい。
- **third instance は「検査」の側にある。** 下の M-01 / M-02 / M-03 を参照。押下時入力という
  「規則」を検査する代わりに `activeScope` という 1 変数を検査した ST-09 は、M-01 が足した 2 つ目の
  入力をそのまま素通しにする。実際に mutant で確認した。

### 2. H-01 の解放順序

質問された 2 つの失敗ケースを個別に見た。

- **作成が失敗した場合: 回収不能な資源は残らない。** `releasePrevious` が先に古いものを解放し、
  handle を nil、`activeScope` を general にしてから `createPasteboard` を呼ぶ。作成が throw すれば
  `run` → `reportFailure` へ流れ、画面は general のまま、台帳は空。孤立資源はない。
  なお `createPasteboard(.unique)` と `.named("nt-sample")` はライブラリ実装上 throw しない
  （`PasteboardResolver.create` は空名だけを拒否する）ので、この経路自体が現状は到達しない。
- **解放が失敗した場合: 回収不能になる（ただし現状は到達しない）。** `releasePrevious` は
  `removePasteboard` を呼ぶ**前**に `createdUnique = nil` としてしまう
  （`ClipboardSampleView.swift:578-582`）。解放が throw すると、pasteboard は残ったまま handle だけが
  失われる。unique は名前がシステム生成なので、この状態は H-01 が塞いだはずの「回収不能」そのもの。
  現行ライブラリでは `removePasteboard` が非空名の named / unique に対して throw する経路がない
  （`resolve` は空名のみ拒否、`isStandard` は false、`releaseGlobally()` は非 throw）ため**現時点では
  到達しない**。よって A ではなく C として記録する（下の L-01）。result v4 §1 の「作成が失敗しても
  回収不能な資源は残らない」は正しいが、解放の失敗を含んでいない点で記述が不足している。
- **不整合な表示**: `removePasteboard` の `await` 中に、`activeScope = .general` かつ
  `createdUnique = nil` の中間状態が描画されうる。Picker が一瞬 general に戻り、その間に利用者が
  unique を選ぶと「no unique pasteboard exists yet」が出て、直後に作成完了で上書きされる。一過性で
  資源の不整合はないが、下の L-02 に記録する。
- **過剰適用が見つかった。** 下の H-01 を参照。

### 3. ST-09 / ST-10 / 待機規則テストが自分の主題を取れているか

- **待機規則テスト: 取れている。** 4 件は 2 つの連言をそれぞれ固定する。連番条件を落とす mutant で
  `testTheSameTextFromAnEarlierClickIsNotAccepted` が落ちることを独立に再現した。
  ただし採取順序と照合の錨は範囲外（下の M-04 / M-05）。
- **ST-09: 取れていない。** 主題は「押下時の入力は押下時に読む」だが、検査しているのは
  `activeScope` という 1 変数。M-01 で追加された `localOnly` を対象にしていない（下の M-01）。
  加えて body の対応付けが件数一致でなく位置合わせ（下の M-03）。
- **ST-10: 取れていない。** 空回り防止の `#expect(calls >= 10)` が、走査根に含まれる他のサンプル
  画面のログ 69 件で満たされる。clipboard サンプルのログを 1 行も読まなくても通る（下の M-02）。

### 4. `check_design_consistency.py` の免除範囲

- **実在の文書構造に対しては妥当。** 唯一の宣言文書 `sample-app-design-v4.md` は宣言行が offset 461、
  2 番目の `## ` が offset 878 で、免除は維持される。宣言行を `## Appendix` の下へ移すと免除されない
  ことを実測した。
- **他文書への影響は無い。** リポジトリ内で `PLANNED_SYMBOLS_EXEMPT` を含む 5 文書のうち、宣言行の
  形式（`- **\`PLANNED_SYMBOLS_EXEMPT\`**` 行頭）を持つのは v4 のみ。v5 / result v3 /
  review v3 / design-review v4 はいずれも旧条件・新条件とも非免除。計画 v5 と機能設計 v9 を実行し、
  `named symbols exist in the implementation` を含め FAIL 0 を確認した。
- **境界の抜けが 1 つある。** `## ` 見出しが 1 個以下の文書では `front_matter = text` に落ち、
  旧来の全文走査に戻る（下の M-06）。

---

## 重大な問題（high）

### H-01 [A]: `CreateNamedPasteboard` の再押下が named pasteboard の内容を黙って破棄する

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:555-584`（`runScopeCreating` / `releasePrevious`）
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md:462`（`CreateNamedPasteboard` の呼び出し方針）
- `releasePrevious(for:)` は `if case .named = request { previous = createdNamed } else { previous = createdUnique }`
  で、**named 要求でも既存の named を `removePasteboard` する**。
- v3 H-01 が問題にしたのは unique だけである。計画 §5.1 も「`unique` を選び直すたびに新しい
  pasteboard ができ、前のものは画面から回収できなくなる」と unique を名指ししている。
  named は固定名 `nt-sample` で常に再アドレスできるため、孤立しない。解放する理由がない。
- **失敗シナリオ（再現手順）**:
  1. `CreateNamedPasteboard` を押す（active scope が named になる）
  2. `CopyText` を押す（`nt-sample` に 1 item が入る）
  3. `CreateNamedPasteboard` をもう一度押す
  4. `Read` を押す → **`items=0`**。修正前は `items=1` だった
- 内容が失われることは AppKit で実測した。同じ名前を取り直すと内容は保たれる（`refetch without
  release: kept`）が、`releaseGlobally()` を挟むと空になる（`refetch after releaseGlobally: <nil>`）。
  ライブラリ側のテスト `PasteboardResolverTests`「resolving the same name twice addresses the same
  pasteboard」も同じ挙動を固定している。
- 影響は 2 つ。(1) 利用者のデータが無言で破棄される。(2) `createPasteboard` の公開 doc が言う
  「Creates **or fetches** a pasteboard」の後半を、サンプルから実演できなくなった。
  結果文に出る「; released the previous one」も、named では解放不要な資源の解放を報告している。
- また MS-04（named / unique を作成 → 操作 → 削除まで通る。未実施）の手順は、この変更で
  「作成 → 操作 → 再作成」で内容が消える経路を含むことになる。
- 修正方針: `releasePrevious` を `.unique` 要求に限定する。named は従来どおり fetch させる。

---

## 改善提案（medium）

### M-01 [B]: ST-09 は `localOnly` を対象にしていない。M-01 で足した 2 つ目の押下時入力に検査がない

- 対象: `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:171-203`
- ST-09 の主題は doc comment の言うとおり「押下の瞬間に読む」だが、検査しているのは文字列
  `"activeScope"` と `"let scope = activeScope"` の出現位置だけである。
- 前ラウンドの M-01 は「scope は押下時に捕捉するのに、同じ入力である toggle は捕捉していない」という
  指摘だった。実装は直ったが、**検査は同じ形のまま**で、`localOnly` を見ていない。
- **実証（本レビューで実行）**: `ClipboardSampleView.swift:244-257` の
  `let options = ClipboardCopyOptions(localOnly: localOnly)` を `Task { await run(...) { ... } }` の
  内側へ移す mutant を作り、`-only-testing:MacLibraryExampleTests` を実行した。
  **20 件すべて通過（ST-09 を含む）。** つまり v3 M-01 が指摘した欠陥を再導入しても検査は落ちない。
- 修正方針: 押下時入力の名前をハードコードせず、`sampleButton` の body 内で `Task` / `await` より
  後に読まれる `@State` プロパティを一般に禁じる形にする（`@State private var (\w+)` を宣言から
  導出すれば、両辺とも手書きにならない）。少なくとも `localOnly` を対象へ加える。

### M-02 [B]: ST-10 の空回り防止が、clipboard サンプル以外のログで満たされる

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:205-223`（`#expect(calls >= 10)`）
  - 同 `:376-387`（`sampleSources()` の走査根）
- `sampleSources()` は `MacLibraryExample/MacLibraryExample` 配下の全 `.swift` を返す。
  `Log.` 呼び出しの内訳は ClipboardSampleView 11 / DialogSampleView 18 / NotificationSampleView 29 /
  ShareSampleView 19 / MacLibraryExampleApp 3 / ClipboardSampleSupport 0 の計 80 件。
- したがって `calls >= 10` は、clipboard サンプルのログを 1 行も読まなくても成立する。
- **実証（本レビューで実行）**: `ClipboardSampleView.swift` から `Log.d` を全削除する mutant を作り、
  `-only-testing:MacLibraryExampleTests` を実行した。**ST-10 を含む 20 件すべて通過。**
- 計画 §7.1 の「監査が空回りしないこと ―― 左辺が 0 件になれば『すべて呼ばれている』が無条件に真」
  という原則が、ST-10 では実装されていない。ST-05 / ST-06 と同じ形の穴である。
- 修正方針: ファイル単位で下限を持つ（`ClipboardSampleView.swift` から拾えた件数が 0 でないこと）か、
  対象を clipboard サンプルの 2 ファイルに絞る。

### M-03 [B]: ST-09 の button body 対応が件数一致でなく、位置合わせに依存している

- 対象: `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:174-184`, `:318-343`
- `names` は raw source の `/sampleButton\("(\w+)"\)/` から 35 件。`bodies` は `codeOnly` 後の
  `sampleButton(` マーカー走査で、**`private func sampleButton(_ name:` の定義も拾うため 36 件**になる。
- `#expect(bodies.count >= names.count)` は通り、`zip(names, bodies)` が 36 番目を捨てる。
  現在の対応が正しいのは、定義が全呼び出しより後（:735）にあるという偶然による。
- 失敗シナリオ: 将来 `sampleButton(` を含むヘルパーがセクション定義より前に置かれると、全ペアが
  1 つずつずれる。ずれた先は多くの場合 `reads == captures == 0` で通るため、**検査は黙って
  無意味になる**（このプロジェクトで繰り返し出ている形）。
- 修正方針: 定義を明示的に除いたうえで `#expect(bodies.count == names.count)` にする。

### M-04 [B]: `tap` が text と sequence を別の時点で読み、対にならない

- 対象: `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:99-106`

```swift
lastText = result(app)
if Self.isResultOfThisClick(text: lastText, sequence: sequence(app),
                            before: before, expecting: expected) {
```

- text を読んでから sequence を読むため、その間に新しい結果が届くと「古い text」と「新しい
  sequence」の組を評価する。判定が真になる条件は「古い text が expected を含む」＝同じボタンの
  再実行のときで、これは規則が存在する理由そのもののケースである。
- 待機規則を純関数へ切り出したことで規則自体は検査できるようになったが、**入力の採取順序**は
  `ClipboardSampleWaitRuleTests` の範囲外に残った。規則を守っても、規則へ渡す値の取り方で同じ
  偽陽性が起きうる。
- 現在の押下順では非同期に Result を書く経路が observe callback（label は `observed`）と
  paste callback（`onPaste`）だけで、どちらもボタン名を含まないため実害には至っていない。
- 修正方針: sequence を先に読む（保守側に倒れる）か、両方を 1 回のスナップショットで取る。

### M-05 [B]: 待機規則の label 照合が部分一致で、実在するボタン名の包含関係を許す

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:117-120`
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleWaitRuleTests.swift:17-40`
- `text.contains(label)` は結果文全体に対する部分一致で、`[label]` に錨を打っていない。
  実在するボタン名に包含関係がある: `snapshot` ⊂ `snapshotFiltered` / `snapshotEmptyFilter`、
  `copyEmpty` ⊂ `copyEmptyRepresentations`、`read` ⊂ `readDataPlainText`、
  `startObserving` ⊂ `startObservingInvalidInterval`。detail 側にも `clear` ⊂ `resetReachedCodes` の
  「cleared」がある。
- 追加された 4 件のテストは、この形のケースを 1 つも持たない（`copyText` と `clear` という
  包含関係のない対だけを使う）。`text.contains(label.prefix(4))` のような mutant は 4 件を通過する。
- 現在の押下順では偽陽性に到達しないが、規則を検査すると決めた以上、規則の弱点である
  「錨のない部分一致」を対象に含めるべきである。
- 修正方針: `text.contains("[\(label)]")` にし、包含関係のあるラベル対のケースを追加する。

### M-06 [B]: 免除範囲の変更にテストがなく、`##` 見出しが 1 個以下の文書では全文走査へ戻る

- 対象: `scripts/check_design_consistency.py:366-373`
- `headings = [m.start() for m in re.finditer(r"^## ", text, re.M)]` に対し
  `front_matter = text[: headings[1]] if len(headings) > 1 else text`。
  **`## ` 見出しが 0 個か 1 個の文書では、front matter が文書全体になる。**
- **実証（本レビューで実行）**: v4 から `## 基本情報` 以降を落として `## ` を 1 個だけにし、
  宣言行を末尾に置いた文書を作って実行したところ、
  `SKIP named symbols exist in the implementation: the document declares PLANNED_SYMBOLS_EXEMPT`
  となった。宣言行が front matter の外でも免除される、v3 M-05 と同じ状態である。
- 併せて、`scripts/` に自動テストが 1 本もなく、この境界は手動確認だけで支えられている。
  workflow の停止条件 2（追加した検査が壊すと落ちること）を、この検査については機械的に担保できない。
- 修正方針: 見出しが足りない場合は免除しない（`else` を `text[:0]` にする）。
  スクリプトに最小のテスト（front matter 内 / appendix / 見出し不足の 3 ケース）を置く。

---

## 軽微な指摘（low）

### L-01 [C]: 解放が失敗したときに handle だけが先に失われる（現状は到達しない）

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:573-584`
  - `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v4.md:41-43`
- `createdUnique = nil` と `activeScope = .general` を `removePasteboard` の**前**に行うため、解放が
  throw すると資源は残り handle は失われる。unique は名前がシステム生成なので回収不能になる。
- 現行ライブラリではこの throw が起きない（`PasteboardResolver.resolve` は空名のみ拒否、
  `isStandard` は false、`releaseGlobally()` は非 throw）ため A ではない。
- ただし result v4 の「作成が失敗しても回収不能な資源は残らない」は解放失敗を含まない。
  成功後にクリアすれば両方の失敗ケースを満たせる。**`removePasteboard` に失敗経路が入った時点で
  A に変わる。**

### L-02 [C]: 解放中の中間状態が Picker に見える

- 対象: `ClipboardSampleView.swift:573-584`
- `removePasteboard` の `await` 中は `activeScope = .general` / `createdUnique = nil` で再描画されうる。
  Picker が一瞬 general へ戻り、その間の選択操作は「no unique pasteboard exists yet」になる。
  資源の不整合はないが、作成ボタンの結果としては説明のない遷移である。

### L-03 [C]: 計画が求める画面注記が 2 つ実装されていない

- 対象:
  - 計画 §3.2（`...design-v5.md:288-291`）「**Append は直前の copy が返した ownership に従う**
    （Active scope ではない）」を画面に注記する
  - 計画 §6.4（同 `:586`）named / unique は「画面破棄時は解放しない（画面に注記）」
- `appendSection`（`ClipboardSampleView.swift:263-304`）と `scopeSection`（同 `:152-181`）には
  説明用の `Text` が無い。注記があるのは Paste Control のみ（`:468-470`）。
- Append は特に紛らわしい。ボタンは押下時に `activeScope` を捕捉するが、OP-02 自体は scope 引数を
  持たず ownership に従う。画面上は Picker が効くように見える。

### L-04 [C]: 計画 §7.1 / §7.4 が ST-08 / ST-09 / ST-10 を含まない

- 対象: `...design-v5.md:641-651`（テスト一覧）、同 `:744-752`（合格条件「ST-01〜ST-07 全通過」）
- 実装には ST-08 / ST-09 / ST-10 がある。v3 L-01 でファイル一覧は実体へ合わせたが、テスト ID の
  一覧と合格条件は v5 のまま。今回追加した 2 本が計画の合格条件の対象外になっている。
- result v4 §1 に追加の経緯はあるので追跡はできるが、workflow の「計画書との整合」上は不一致である。

### L-05 [C]: MT-08 の手順が `CopyWithCurrentOptions` を指していない

- 対象: 計画 §8.1（`...design-v5.md:767`）「`localOnly` を切り替えて実機 Mac + iPhone」
- M-01 の修正で通常 Copy は既定値固定になったため、toggle を反映するのは
  `CopyWithCurrentOptions` だけである。手順にボタン名が無いと、`CopyText` で切り替えたつもりの
  検証が成立しない。

### L-06 [C]: `lastOwnership` が書かれるだけで読まれない

- 対象: `ClipboardSampleView.swift:32`, `:253`, `:273`, `:550`
- 3 か所で代入されるが参照が無い。`CopyThenAppend` は自前で ownership を持ち回るため使い道がない。
  `AppendWithLastOwnership` のようなボタンを置く意図があったなら計画に無く、無いなら削除でよい。

### L-07 [C]: 期待エラー runner の総括 catch が 1599 を「到達したコード」に混ぜる

- 対象: `ClipboardSampleView.swift:673-707`
- `catch { actual = ClipboardError.unknown("").errorCode }` で非 `ClipboardError` を 1599 に丸め、
  `report` の `differentCode` 経路が `reachedCodes.insert(actual)` する。ライブラリが 1599 を
  返していなくても section 10 に 1599 が並ぶ。到達経路は現状見当たらないが、「到達した一覧」という
  表示の意味を変える（v3 M-01 と同じ論点）。

### L-08 [C]: Detect の arrange 失敗の扱いが兄弟間で揃っていない

- 対象: `ClipboardSampleView.swift:373-397`（`DetectPatterns` / `DetectValues`）と
  同 `:398-416`（`DetectMetadata`）
- `DetectMetadata` は arrange を `do / catch` で分離するが、`DetectPatterns` / `DetectValues` は
  arrange を `run` の中に置くため、arrange の失敗が act のラベルで表示される。
  errorCode は保たれ act は実行されないので誤りではないが、表示上どちらで失敗したか分からない。

---

## 変異検査（本レビューで独立に再実行）

| 壊した内容 | 落ちるべき検査 | 結果 |
|---|---|---|
| `isResultOfThisClick` から `sequence > before` を外す | `ClipboardSampleWaitRuleTests` | **落ちた**（`testTheSameTextFromAnEarlierClickIsNotAccepted`。他 3 件は通過） |
| `Clear` の capture を `Task` の中へ移す | ST-09 | **落ちた**（`capture.lowerBound 91 < point.lowerBound 17` で 2 issue） |
| `teardown` のログに `\(sampleName)` を継続行で足す | ST-10 | **落ちた**（`... logs the caller supplied pasteboard name`） |
| 免除の宣言行を `## Appendix` へ移す | 免除の範囲判定 | **免除されない**ことを確認（基本情報に置いた v4 原本は免除される） |
| **`localOnly` の capture を `Task` の中へ移す** | ST-09（落ちるべき） | **落ちなかった。20 件すべて通過**（本書 M-01） |
| **`ClipboardSampleView.swift` の `Log.d` を全削除** | ST-10（空回り防止が働くべき） | **落ちなかった。20 件すべて通過**（本書 M-02） |
| **`## ` 見出しを 1 個にし宣言行を末尾へ** | 免除の範囲判定（免除すべきでない） | **免除された**（本書 M-06） |

- 変異はすべて実行後に復元し、`shasum` と `git status --porcelain` で開始時と同一であることを確認した。

---

## 検証結果

### xcodebuild / xcresult

指定コマンド（`clean test` / workspace / 3 つの `-only-testing`）を実行し、**TEST SUCCEEDED**。

| 対象 | totalTestCount（宣言） | devicesAndConfigurations passedTests（展開） | 失敗 |
|---|---|---|---|
| `MacLibraryExampleTests` + `ClipboardSampleViewUITests` + `ClipboardSampleWaitRuleTests` | **30** | **31** | **0** |
| `MacLibrary` | **307** | **351** | **0** |
| `UnityMacPlugin` | **75** | **76** | **0** |

- 内訳は stdout でも一致した: `MacLibraryExampleTests` 20 件（Clipboard 19 + テンプレート 1、
  ST-04 が 2 ケースに展開して 21）、`ClipboardSampleViewUITests` 6 件（154.9 秒）、
  `ClipboardSampleWaitRuleTests` 4 件（0.37 秒）。
- **報告値はすべて再現した。** 既知の accessibility hierarchy 空事象は今回発生しなかった。
- 実行ホストは macOS 26.3 / arm64。**macOS 15 系での実行は未確認**（MT-07 が要求する 15.4.1 / 15.2 は
  result v4 の open 項目のまま）。

### 警告

- `clean test` のログ中の `warning:` は 4 件、すべて
  `appintentsmetadataprocessor ... No AppIntents.framework dependency found`。
  **コンパイラ警告 0 件、Clipboard 由来 0 件。**

### design consistency / whitespace

- `python3 scripts/check_design_consistency.py <計画 v5>`: FAIL 0。
  `named symbols exist in the implementation` は **OK（免除なし）**。
- `python3 scripts/check_design_consistency.py <機能設計 v9>`: 全項目 OK。
- `git diff develop --check`: 出力なし。
- 未追跡の Swift 5 ファイルと共有 scheme も `git diff --no-index --check /dev/null <file>` で
  whitespace error なし。

---

## 計画書整合性チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| 全セクション・全ボタンの実装 | ○ | 10 セクション、35 ボタンをソースから機械的に確認 |
| API 呼び出し方針の一致 | △ | `CreateNamedPasteboard` が計画に無い解放を行う（H-01）。他 15 操作は一致 |
| システム設定（Manifest / FileProvider 等）の正確性 | ○ | macOS Clipboard に追加設定は不要。共有 scheme は存在し、両テストターゲットを `skipped = "NO"` で含む |
| 変更ファイル一覧との diff 整合 | ○ | 計画 §4.1 / §4.2 の 8 項目と `git status` が一致 |
| 手動確認観点を満たす UI | △ | §3.2 の Append 注記と §6.4 の lifecycle 注記が未実装（L-03）。MT-08 の導線が手順に無い（L-05） |
| 計画との差分（追加判断）の result への記録 | △ | H-01 の解放は result v4 §1 に記録済み。ST-08 / ST-09 / ST-10 は計画 §7.1 / §7.4 に未反映（L-04） |

## サンプルアプリパターン適合チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| メニュー導線（Router / MainMenu） | ○ | `ContentView` の既存 `NavigationLink` / `menuCard` パターンに追加（+10 行） |
| 画面構成パターン（タイトル / statusText / ScrollView） | ○ | 既存 macOS サンプルと同型 |
| 成功/失敗表示フォーマット | ○ | `SampleOutcome` に一元化。秘匿対象コード（1505 / 1507）だけ分岐 |
| 共通 UI 部品の利用 | ○ | `sectionView` / full-width button style を private に複製（workflow の許容範囲） |

## プロジェクトルール適合チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| common.md 準拠 | ○ | ネイティブサンプルがネイティブライブラリのみを使う |
| mac.md 準拠 | ○ | ログ規約の適用対象は `mac/MacLibrary/` と `mac/UnityMacPlugin/`。サンプルは対象外だが安全な label / marker を記録している。UI とコメントは英語 |
| サンプルアプリの依存方向（Unity プラグイン非依存） | ○ | `import UnityMacPlugin` 0 件。ST-06 がソースを走査。AppKit の直接利用は OP-19 の `NSView` hosting のみ |
| Log.d 網羅性 | ○ | 対象外だが実質網羅（11 呼び出し）。ログに payload / pasteboard 名は無い |
| KDoc 網羅性 | N/A | Swift のため対象外。DocC 相当のコメントは全 public / 主要 private に存在 |

## 手動確認観点の充足

| ID | 評価 | 状態 |
|---|---|---|
| MT-01 / MT-02 / MT-03 / MT-04 / MT-06 / MT-07 | △ | 未実施（result v4 §4） |
| MT-08 | △ | 未実施。加えて手順が `CopyWithCurrentOptions` を指していない（L-05） |
| MT-09 | △ | 判定保留（RK-22） |
| MS-01 | ○ | 35 ボタンをソースから導出して押下。本環境で完走（154.9 秒、失敗 0） |
| MS-02 | ○ | matched / unmet / 同一ボタン再実行を通過。待機規則は純関数化され 4 件が固定 |
| MS-03 | ○ | 未作成 scope の拒否、named / general のデータ分離を通過 |
| MS-04 | △ | 未実施。H-01 の再作成経路を含むため、修正後に実施すべき |
| MS-05 | ○ | 離脱・再入場で `Not observing` を確認 |
| MS-06 | △ | 未実施 |
| MS-07 | △ | 画面側は通過。ログ側は ST-10 が加わったが空回り防止が効いていない（M-02） |
| MS-08 | ○ | ソースと project 参照を静的確認 |

---

## 総合評価

**要修正（重大）**。

- **A-count: 1。0 ではない。** `CreateNamedPasteboard` の再押下が named pasteboard の内容を破棄する。
  H-01 の修正を unique に限定して再レビューが必要。
- B 6 件のうち **M-01 / M-02 は中心契約に当たる**。今回追加した 2 本の検査が、それぞれ
  「押下時入力」「サンプル自身のログ」という主題を取れていないことを変異で実証した。
  workflow の停止条件 2（追加した検査が壊すと落ちること）は、この 2 本については未充足である。
- M-06 も同種で、`check_design_consistency.py` の免除範囲は 1 ケースが抜けており、
  スクリプトにテストが 1 本もない。
- C 6 件は計画・result の記述と、到達しない防御的経路。安いものから直してよい。
- **サーキットブレーカー**: サンプル実装レビューは本書で 4 ラウンド目。5 ラウンドは超えていない。
  ただし「検査が自分で対象を決める」形の指摘は v1 以降 4 ラウンド連続で出ており、
  **同じ種類の指摘が 3 回続いた**に該当する。個々の検査を足すのではなく、
  「両辺をソースから導出する」「空回り防止は主題のファイル単位で持つ」という規則自体を
  検査の書き方の共通ルールへ落とすことを勧める。
- MT-01〜MT-09（計画 §8.1 に MT-05 の行は無い）、MS-04、MS-06、および機能設計 §12.4 の BT-01 / BT-08 / BT-12 /
  CT-05 は open のまま。実機確認が必要な観点が △ で残るため、総合評価を楽観視していない。
