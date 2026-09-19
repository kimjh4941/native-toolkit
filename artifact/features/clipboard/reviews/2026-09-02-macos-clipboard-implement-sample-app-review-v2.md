# macOS Clipboard サンプルアプリ実装レビュー v2

## レビュー対象

- 日付: 2026-09-02
- ブランチ: `feature/NTKIT-15`
- HEAD: `a634619bd4cb0c8f32d1f891bd187eabf9c6fee3`
- 比較基準: `develop`（merge-base: `9367da5c6aeb634c26944c9ec7d4385c54e40d13`）
- 追加対象: 未コミット・未追跡の `mac/MacLibraryExample/` 配下、実装結果 v2、前回レビュー v1
- サンプル計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v2.md`
- 機能設計（参照のみ）: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 対象 OS: macOS 15 以降

> サンプル実装の大半は未追跡であり、`git diff develop...HEAD` には現れない。指定された新規 4
> ファイル、共有 scheme、`ContentView.swift` の worktree 実体をレビューした。File Promise、
> MT-01〜MT-09、機能側の既知未実装テストは今回の再判定対象にしていない。

## 結論

**要修正。A 区分 3 件、B 区分 6 件、C 区分 2 件。**

今回の再実行では単体テスト 11 宣言 / 12 展開、UI テスト 5 / 5 がすべて通過し、既知の
accessibility hierarchy 空事象は発生しなかった。しかし、通過した UI テストは計画の MS-01〜
MS-03 / MS-07 を十分には検査していない。加えて、Picker の新しい状態遷移は scope を重複作成・
孤立させる経路と非同期競合を持つ。A が 0 件ではないため、workflow の停止基準上、次工程へ進める
判定にはできない。

## 前回指摘の追跡

| 前回 | 区分 | 状態 | 今回の確認 |
|---|---|---|---|
| H-01 Active scope Picker | A | 部分反映 | Picker は追加されたが、計画の「状態のみ」と異なり作成 API を呼び、失敗・競合・unique 孤立経路がある（H-01） |
| H-02 DetectMetadata arrange | A | 部分反映 | act は停止するが、元の ClipboardError を失い、arrange と act の scope も固定していない（H-02） |
| H-03 UI test の偽陽性 | B | 部分反映 | label 待ちは改善したが、MS-01〜MS-03 の対象不足と同一 label 再実行の stale 経路が残る（H-03、M-02） |
| H-04 ST-05 block comment | B | 部分反映 | 単純 block comment は除去するが、Swift の nested comment と文字列内 delimiter を扱えない（H-05） |
| M-01 reached error code | A | 未反映 | 通常 runner と PasteButton 構築で到達した ClipboardError は一覧に入らない（M-01） |
| M-02 button identifier | B | 未反映 | `clipboard.button.*` は依然 0 件（M-03） |
| M-03 scheme / 実行方針 | B | 解消 | 共有 scheme から指定コマンドを実行し、unit / UI とも成功した |
| M-04 UI test の追加判断 | C | 未反映 | 計画との差分として理由・直列化・既知環境事象を result の追加判断に整理していない（M-04） |
| L-01 xcuserstate | C | 解消 | worktree の対象差分から除外されている |
| L-02 Doc comment | C | 未反映 | AppKit の利用範囲より強い文言が残る（L-01） |

## 重大な問題（high）

### H-01 [A]: Picker の選択が pasteboard を作成し、状態不整合・競合・unique の孤立を起こす

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:53`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:106`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:466`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:475`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:451`
- 計画は Picker を「状態のみ」と定義するが、`applyScopeChoice` は named / unique の選択ごとに
  `createPasteboard` を実行する。general へ切り替えた後に unique を選ぶと新しい unique を作り、以前の
  unique への参照を失う。明示 remove が必要な pasteboard を画面から回収できなくなる。
- `scopeChoice` は API 成功前に変更済みである。作成が失敗すると Picker は named / unique のまま、
  `activeScope` は以前の値のままになり、表示と実際の操作対象が分岐する。
- 選択を素早く変えると複数の非同期作成に順序保証がない。古い要求が後から完了して新しい選択・結果を
  上書きできる。`isSyncingScopeChoice` は programmatic assignment の echo を 1 回抑えるだけで、
  transaction の順序と rollback は保証しない。
- Picker は保持済み scope を選ぶだけにし、named / unique の作成は既存ボタンへ限定すること。
  あるいは単一の状態機械で pending generation、成功時 commit、失敗時 rollback、保持済み unique の
  明示的な ownership を定義すること。作成失敗と完了順逆転を変異テストに含めること。

### H-02 [A]: Detect の arrange と act が同一 scope に固定されず、arrange の ClipboardError も失う

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:320`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:333`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:496`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:484`
- `arrangeDetectionText` / `arrangePlainText` と後続 detect は、それぞれ実行時点の `activeScope` を読む。
  最初の `await` 中に利用者が Picker を変更すると、fixture を scope A に書き、scope B を detect する。
  「arrange → act を一続き」「現在内容に依存しない」という決定性を満たさない。
- `DetectMetadata` の catch は元の `ClipboardError.errorCode / errorMessage` を捨て、固定文
  `the arrange copy failed` を表示する。act を止める修正自体は正しいが、共通 runner の表示契約と
  Error Cases 到達記録を迂回している。
- ボタン押下時に `let scope = activeScope` を一度だけ capture し、arrange helper と act の双方へ渡す
  こと。arrange 失敗も共通の ClipboardError 表示・記録経路へ流し、act が未実行であることをテストすること。

### H-03 [B]: 通過した MS-01〜MS-03 は計画で要求した振る舞いを検査していない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:117`
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:132`
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:145`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:740`
  - 実装結果 `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v2.md:136`
- MS-01 は 6 ボタンだけで、実際には Copy、Read、Observe、Clear の 4 セクションしか触らない。
  Scope、Copy Options、Append、Detect、Paste Control、Error Cases は未検査であり、計画の
  「10 セクションすべてのボタン」と result の「確認済み」は成立しない。
- MS-02 は 1508 が期待どおり返る matched 分岐だけを見る。テスト名と計画が要求する
  「期待失敗が成功してしまった場合に失敗表示」は画面経路で実行されない。
- MS-03 は create / remove ボタンによる表示遷移だけで、今回追加した Picker を操作しない。
  scope 引数を持つ別操作が選択 scope へ実際に作用したことも確認しないため、H-01 の失敗・競合や
  Picker の action を検出できない。
- MS の名称を狭い検査内容へ変更して未確認事項を残すか、計画どおりの統合検査へ拡張すること。
  result の「確認済み」は検査が証明する範囲に限定すること。

### H-04 [B]: MS-07 は実際に渡した caller-supplied name を検査していない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:183`
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:204`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:746`
- テストが押す `CreateEmptyNamedPasteboard` の実入力は空文字である。一方、非表示を検査する値は
  ソースから読んだ `sampleName`（`nt-sample`）であり、その操作には渡されていない。実装が実入力を
  そのまま表示しても空文字なので、この assertion は常に通る。
- `callerSuppliedName()` 自体は、パス解決・ファイル読取・正規表現一致に失敗すれば throw / unwrap
  failure になるため、読み取り失敗が空振りする構造ではない。問題は取得値と操作入力の不一致である。
- 非空の caller-supplied name を実際に渡す操作で画面非表示を確認すること。1505 の契約を同時に
  検査するなら、入力値を秘匿できる別の不正 request を用意するか、計画側の MS-07 手順を分離すること。
  「ログにも出ない」は UI assertion とは別の検査が必要である。

### H-05 [B]: ST-05 の regex scanner は Swift の comment / string 構文を扱えず偽陽性・偽陰性になる

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:199`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:645`
- Swift の block comment はネスト可能だが、非貪欲 regex は最初の `*/` で終了する。例えば外側
  comment 内で内側 comment の後ろに置いた偽の manager call が右辺へ残り、未実装操作を called と
  数えられる。
- block comment を文字列より先に除去するため、文字列内の `/* ... */` も comment と誤認する。
  その範囲にある実際の `\(...)` call を消す偽陰性も起こる。line ごとの `//` 除去も URL 等の
  string literal 内 delimiter を区別しない。
- SwiftSyntax の call expression を用いるか、nested comment、通常 / multiline / raw string、
  interpolation を状態として扱う lexer に置き換えること。少なくとも nested block comment と
  string 内 comment delimiter の変異で、誤った green / red が起きないことを記録すること。

## 改善提案（medium）

### M-01 [A]: 通常の ClipboardError が Error Cases の到達一覧に残らない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:519`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:539`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:594`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:518`
- `reachedCodes` を更新するのは expected-error の `report` だけである。通常の `run` / `runSync` と
  `buildPasteButton` で ClipboardError に到達しても表示一覧に残らない。環境依存の 1513 / 1514
  などを実際に観測しても、「到達したコード一覧」という画面の意味が変わる。
- ClipboardError の表示と到達記録を一つの helper に集約し、すべての入口から同じ経路を通すこと。

### M-02 [B]: `tap` は同じ label の前回結果を新しい結果として即時受理する

- 対象: `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:87`
- `before` を保存するが待ち条件では使わず、結果が `expected` label を含むだけで return する。同じ
  ボタンを同一テスト内で再実行すると、click の直後に前回結果を読んで成功できる。
- 少なくとも `text != before && text.contains(expected)` を条件にすること。より堅牢には operation
  ごとの sequence / marker を UI に出し、それが増えたことを待つこと。

### M-03 [B]: button の accessibility identifier が計画どおり付いていない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:124`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:676`
- section / result / status には identifier があるが、`clipboard.button.<name>` は 0 件である。
  UI テストは表示 label に依存し、UI の文言変更と機能識別を分離できない。
- 全 button に一意な identifier を付け、UI test は identifier で取得すること。

### M-04 [B]: `scrollIntoView` は初回が無移動だと方向を決め直さない

- 対象: `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:60`
- 符号反転を `attempt == 0` の一度だけ判断する。初回が boundary、遅延した frame 更新、0 delta 等で
  `moved == 0` になると方向を確定できず、同じ方向を最大 12 回試して最後に一般的な失敗文を出す。
- 各試行で `abs(element.midY - viewport.midY)` が減ったかを評価し、無移動・悪化なら方向を反転する
  こと。failure には viewport / element frame、各 delta、移動量を含めると原因を区別できる。

### M-05 [C]: result は前回 10 指摘のうち high 4 件だけを「レビュー v1 の 4 件」と記録している

- 対象: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v2.md:20`
- 前回レビューには high 4、medium 4、low 2 がある。v2 は high だけを列挙し、未反映の M-01、
  M-02、M-04、L-02 が追跡表から消えている。このため「すべて反映」と誤読できる。
- 全指摘を resolved / partial / open / rejected で追跡し、UI テスト追加という計画差分も追加判断へ
  記録すること。

## 軽微な指摘（low）

### L-01 [C]: View の Doc comment が必要な AppKit adapter まで禁止している

- 対象: `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:10`
- ファイルは OP-19 の hosting のため `AppKit` / `NSView` を使用する。「clipboard operation は
  AppKit を直接呼ばず MacLibrary 経由」と範囲を限定すると実装と一致する。

## 計画・パターン適合

| 観点 | 評価 | 注記 |
|---|---|---|
| 10 セクション / 公開 OP 16 | ○ | 画面と source call は存在。ST-05 scanner の信頼性は H-05 |
| Active scope | × | Picker はあるが計画の state-only 契約、失敗 rollback、非同期順序を満たさない |
| arrange → act | △ | 成功時の流れはあるが scope 固定と error 保存がない |
| Error Cases | × | 通常 runner の ClipboardError を到達一覧へ記録しない |
| Paste Control hosting | ○ | `NSViewRepresentable` adapter を一度構築し保持している |
| Unity 非依存 | ○ | sample app に import / link dependency の追加なし |
| UI identifier | △ | section / result / status はあるが button がない |
| 既存サンプル UI パターン | ○ | NavigationLink、結果表示、section、logging の構造に適合 |
| result と実装差分 | △ | v2 の変更ファイルは一致するが、前回指摘の追跡と MS 確認範囲が不正確 |

## 手動確認・MS の状態

| ID | 評価 | 状態 |
|---|---|---|
| MT-01〜MT-09 | △ | result v2 の open を維持。今回の欠陥として再計上しない |
| MS-01 | × | UI test は通過したが 10 セクション中 4 セクションのみ |
| MS-02 | △ | matched 1508 は通過。unexpected-success の画面分岐は未検査 |
| MS-03 | × | create / remove 表示だけ。Picker と scope 引数操作への反映は未検査 |
| MS-04 | △ | 未実施 |
| MS-05 | ○ | 今回 UI test を実行し、画面離脱後の停止を確認 |
| MS-06 | △ | 未実施 |
| MS-07 | × | テスト入力と秘匿を検査する名前が異なり、ログも未検査 |
| MS-08 | ○ | source / project の Unity 非依存を確認 |

## 検証結果

- 指定された workspace / scheme / `only-testing` コマンドを再実行: `TEST SUCCEEDED`
- xcresult summary:
  - `totalTestCount`: 16 宣言
  - `devicesAndConfigurations[].passedTests`: 17 展開
  - 内訳: `MacLibraryExampleTests` 11 宣言 / 12 展開、UI 5 / 5
  - failed 0、skipped 0
- 今回は accessibility hierarchy 空事象は発生せず、UI 5 件は実際に操作まで完走した。
- `git diff develop --check`: clean
- `MacLibrary` 307 宣言 / 351 展開、`UnityMacPlugin` 75 / 76、Clipboard 警告、CT-01 は今回
  再実行せず result v2 の実測値を参照した。
- worktree 確認時点で sample 実装 4 ファイル、共有 scheme、result / review は未追跡のままである。

## 次の再レビュー条件

1. A 区分 H-01、H-02、M-01 を修正し、Picker の失敗 rollback・完了順逆転・unique の lifecycle、
   Detect の scope 固定を壊すと落ちる検査を追加する。
2. B 区分 H-03〜H-05 を修正し、各 MS の名称・result の「確認済み」を実際の検査範囲と一致させる。
3. `scrollIntoView` の no-progress、同一 label 再実行、nested comment / string delimiter の変異を
   含め、unit 12 展開と UI 5 件以上を workspace から再実行する。
4. 前回レビューの全 10 指摘を result の追跡表に残し、open を消さない。

A 区分が 0 件になり、B 区分の中心検証が修復された時点で、再レビューに進める。
