# サンプルアプリ実装結果 v6

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/`
- 計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md`
- 対応タスク: T-18（機能設計 §13）
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v5.md`
- 反映したレビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implement-sample-app-review-v5.md`

> レビュー v5 は **A 0 件**だったが、変異 8 件中 5 件が通過し、止める基準の条件 2 が未充足
> だった。**本版は個別の穴を塞ぐのではなく、走査で書いた検査が 1 ホップで黙る機構そのものを
> 直した。**

---

## 1. 機構への対処（レビュー v5 §8）

指摘の要点:

> v1〜v4 の修正はすべて「**何を探すか**」（左辺）を直してきたが、「**どこを探すか**」
> （走査範囲）は一度も直っていない。走査で書いた検査は computed property を 1 本足すだけで黙る

対処を 3 つ入れた。

### 1.1 構造で不可能にする: 入力の捕捉を `sampleButton` に集約

ボタン本体が画面の状態を読むのをやめ、`sampleButton` が押下時に `SampleInputs`
（scope と options）を作って本体に渡す。

**ST-09 の性質が変わった。** 「十分早く読んでいるか」（走査が知っている名前しか見られない）
から、**「そもそも読まないか」**になった。

### 1.2 走査するなら主題を推移的に閉じる

`namesReaching(_ seeds:in:)` を追加した。**主題を返す computed property / 関数は主題そのもの
として扱う。** ST-09 は `@State` の集合から、ST-10 は `sampleName` から閉包を取る。

閉じる対象は**値を返す宣言に限る**。戻り値のない関数（`run` / `updateResult` /
`reportFailure`）まで含めると、runner を呼ぶすべてのボタンが「状態を読んでいる」ことになり、
検査が意味を失う。**最初の実装ではこれで全ボタンが落ちた。**

### 1.3 順序を持たせない

結果の連番を `clipboard.result` の accessibility value に同梱し、UI テストは 1 回の読みで
連番と本文の両方を取る。**別々に読む限り順序を間違えられるが、1 回なら間違えようがない。**

---

## 2. レビュアーの変異 8 件に対する結果

| # | 変異 | v5 | v6 |
|---|---|---|---|
| MU-1 | computed property 経由で `activeScope` を本体から読む | 通過 | **落ちる**（`Clear reads currentScope`） |
| MU-2 | `sampleButton(_ name:)` を改名 | 落ちる | 落ちる（署名で判定するよう変更） |
| MU-3 | ヘルパー経由で pasteboard 名をログ出力 | 通過 | **落ちる**（`logs boardLabel, which carries the pasteboard name`） |
| MU-4 | `[label]` の錨を外す | 落ちる | 落ちる |
| MU-5 | `tap` の読み取り順を戻す | 通過（検査ゼロ） | **構造上不可能**（1 回の読み） |
| MU-6 | `releasePrevious` を named にも効かせる | 通過（検査ゼロ） | **落ちる**（`creating the named pasteboard again emptied it`） |
| MU-7 | 免除判定から `^- ` の錨を外す | 通過 | **落ちる** |
| MU-8 | front matter を最後の見出しまでに変更 | 通過 | **落ちる** |

**MU-6 の変異は、最初に作ったものが誤りだった。** `if case .named = request { return "" }` を
削るだけでは named が `createdUnique`（nil）を見るだけで v4 の挙動にならない。**変異が効いて
いないのに「検査が通った」と読むところだった。** 正しく v4 の二枠ロジックを復元して確認した。

### 新たに見つかった穴

`scripts/tests` に追加した「宣言の形」の検査が、**コードフェンス内の宣言行がまだ免除を成立
させる**ことを検出した。front matter からフェンスを除去して解消。**追加した検査がその場で
新しい穴を見つけた**のは今回が初めてである。

---

## 3. B 区分 8 件

| ID | 対応 |
|---|---|
| B-01 | A の回帰を固定する UI テスト 2 件を追加（named は内容が残る / unique は解放される） |
| B-02 | ST-09 を §1.1 + §1.2 で作り直し |
| B-03 | ST-10 を §1.2 で作り直し |
| B-04 | §1.3 で順序自体を無くした |
| B-05 | 包含関係のある対を**ボタン名から導出**（`labels.filter { $0.hasPrefix(short) }`）。対が 0 件なら検査が空回りするので、それも検査する |
| B-06 | ST-08 に件数の一致を追加（**規則 3 を書いた本人が破っていた**） |
| B-07 | `scripts/tests` に「宣言の形」3 種と「front matter の上限」を追加。5 → 7 件 |
| B-08 | 計画 §7.3 の再現コマンドに `unittest discover` を追加 |

## 4. C 区分 8 件

| ID | 対応 |
|---|---|
| C-01 | 計画 §4 に今回の新規・変更 4 件を追加 |
| C-02 | §7.3（B-08 と同じ） |
| C-03 | 「本書は宣言する」を「v4 までは宣言していたが v5 では外した」に訂正 |
| C-04 | common.md 規則 1 の適用範囲を「実装の集合を主題にする検査」に限定。**純粋関数の単体テストでは期待値を手で書くのが正しい**と明記 |
| C-05 | 規則 3 を「2 つの集合を対応づける検査」に限定 |
| C-06 | `buttonBodies` の定義除外をリテラルから**署名の形**（パラメータリストの有無）へ |
| C-07 | ST-10 の床は据え置き。実際の呼び出し 11 件に対し床 5 は、ログを減らす変更で偽陽性を出さないための余裕。理由をここに記録 |
| C-08 | `logCalls` の括弧数えが文字列中の `)` で早く閉じる件。**未対応**。現行のログ行に該当形はなく、`codeOnly` を通すと補間内の呼び出しが失われるため。理由をここに記録 |

## 5. 共通ルールの更新

`agent-rules/coding-rules/common.md`「検査の書き方」に **5 つ目の規則**を追加した。

> **走査で書いた検査は、主題を推移的に閉じる。** 主題を返す computed property やヘルパーは
> 主題そのものとして扱う。閉じられないなら、**走査ではなく構造で不可能にする**。

併せて `implement-feature` / `implement-sample-app` に「変異の作り方」を追加した。

> **前回のレビュー指摘をそのまま戻す変異だけを作らない。** 契約は保ったまま、実装の形だけを
> 変える（間接参照を挟む、名前を変える、順序を入れ替える、主題を空にする）。

**これはレビュー v5 §8.3(d) の指摘への対処である。** v4 / v5 の 2 ラウンド続けて、穴を見つけた
のはレビュアーが作った変異だけで、こちらの自己変異は「前回の指摘の再導入」しかなかった。

---

## 6. テスト結果

| 対象 | 宣言数 | 展開後 | 失敗 |
|---|---|---|---|
| `MacLibraryExampleTests` | 20 | 21 | 0 |
| `ClipboardSampleViewUITests` | 11 | 11 | 0 |
| `ClipboardSampleWaitRuleTests` | 6 | 6 | 0 |
| `MacLibrary` | 307 | 351 | 0 |
| `UnityMacPlugin` | 75 | 76 | 0 |
| `scripts/tests` | 7 | 7 | 0 |

- clipboard 分の合計 **37 宣言 / 38 展開 / 失敗 0**。件数は xcresult から取得。
- `clean test` で **Clipboard 由来の警告 0 件**。
- `git diff develop --check`: 0 件。
- `check_design_consistency.py`: 計画 v5・機能設計 v9 とも全項目 OK。

## 6.1 追加分（自動化の取りこぼし）

**「自動化できるものは網羅した」という認識が誤っていた。** MS-04 と MT-03 は他アプリも別端末も
要らずアプリ内で完結するのに、計画の手動欄に置いたままだった。**5 ラウンドのレビューはどれも
これを指摘していない。** レビューは「書いた検査が正しいか」を見たが、「手動欄に置いた前提が
正しいか」は誰も疑わなかった。

| 追加 | 内容 |
|---|---|
| MS-04 | named / unique を 作成 → copy → read → snapshot → clear → remove まで通す 2 件 |
| MT-03 | `CopyThenAppend` の成功と、`AppendWithStaleOwnership` が **1511** を返すこと |

変異でも確認した。

| 壊した内容 | 結果 |
|---|---|
| `AppendWithStaleOwnership` が有効な ownership を使う | **落ちた**（`did not report 1511`） |
| `RemoveCurrentPasteboard` が scope を general に戻さない | **落ちた** |

### MT-03 を書いて見つかった `clear` の表示の誤り

`clear` が返すのは `NSPasteboard.clearContents()` の値、すなわち**新しい changeCount** であって、
消した item 数ではない。

| | 記述 | 判定 |
|---|---|---|
| 機能設計 v9 | 「`clearContents()` を呼び、新しい `changeCount` を返す」 | **正しい** |
| サンプル計画 v5 | 「消した item 数を表示」 | **誤り。訂正した** |
| サンプル実装 | `removed=42` | **誤り。`changeCount=` に訂正した** |
| ライブラリの DocC | `/// Empties the pasteboard.` のみ | **戻り値の説明が無かった。追加した** |

**DocC に戻り値が書かれていなかったことが、この取り違えを支えていた。** 機能設計だけが正しく
書いており、公開 API を読んだ人には確かめる手段がなかった。

## 7. 残作業

| 項目 | 状態 |
|---|---|
| MT-01〜MT-04 / MT-06 / MT-07 | **未実施**（手動確認） |
| MT-08 | **未実施**（端末 2 台） |
| MT-09 | 判定保留 |
| MS-06 | **未実施**。進行中の load を誘発できないため自動化できない |
| L-02（解放中の中間状態）、C-07、C-08 | **未対応**。理由は §4 と result v5 §3 |
| 平文 `detectMetadata` が 1515 を返す件 | **要検証** |
| `PasteButton` が `supportedContentTypes` に一致しない provider を渡すか | **要検証** |
| BT-01 / BT-08 / BT-12 / CT-05 | **未実装**（機能設計 §12.4） |
| `MacLibraryExampleUITestsLaunchTests/testLaunch` | 環境事象で失敗。テンプレート由来で範囲外 |
