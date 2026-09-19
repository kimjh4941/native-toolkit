# macOS Clipboard サンプルアプリ実装レビュー v3

## レビュー対象

- 日付: 2026-09-02
- 対象 OS: macOS 15 以降
- ブランチ: `feature/NTKIT-15`
- HEAD: `a634619bd4cb0c8f32d1f891bd187eabf9c6fee3`
- 比較基準: `develop`（merge-base: `9367da5c6aeb634c26944c9ec7d4385c54e40d13`）
- サンプル計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v3.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implement-sample-app-review-v2.md`
- 機能設計（参照のみ）: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 対象差分:
  - `git diff develop...HEAD`: clipboard 機能実装全体を含む 135 ファイル
  - `git status --porcelain`: サンプル本体・unit test・UI test・共有 scheme は未追跡、`ContentView.swift` と `scripts/check_design_consistency.py` は変更済み
  - 本再レビューは、指定された worktree のサンプル実装と v2 後の変更、およびその成立に必要な `MacLibrary` の公開契約を対象とした

## レビュー概要

- 10 セクション、35 個の `sampleButton`、`MacClipboardManager` の公開操作名 16 種への呼び出し、メニュー導線、共有 scheme は実装されている。
- v2 の H-01〜H-05、M-01〜M-05、L-01 は大半が意図どおり修正された。特に、Picker は `activeScope` から導出する `Binding` となり、Detect は押下時に捕捉した scope を arrange / act の双方へ渡している。
- ただし、unique pasteboard を作成ボタンから再作成すると古い handle を失う経路、Append の setup failure が `ClipboardError` を失う経路、通常 Copy が Copy Options の toggle に影響される経路が残る。
- 指摘は **A 3 件 / B 4 件 / C 1 件**。**A-count は 0 ではない（3 件）**。

## 前回指摘の追跡

| 前回 | 区分 | 判定 | 再確認結果 |
|---|---|---|---|
| H-01 Picker の作成・状態不整合・競合 | A | 解消 | Picker は導出 Binding で既存 scope を選ぶだけになった。4 点の個別回答は後述。ただし作成ボタンの連打による別の unique 孤立経路を新規 H-01 とした |
| H-02 Detect の scope 固定・arrange error 保持 | A | 解消 | 4 個の Detect ボタンは押下時に `let scope = activeScope` を行い、DetectMetadata の arrange failure は `reportFailure` へ渡す |
| H-03 MS-01〜MS-03 の不足 | B | 解消 | MS-01 はソース由来 35 ボタン、MS-02 は unmet の画面経路、MS-03 は Picker と実データを使用する。ただし実行は本環境で再現できなかった |
| H-04 MS-07 の入力不一致 | B | 一部解消 | `CreateNamedPasteboard` に実際に渡す非空名を画面上で検査する。ログ側の検証は残る（M-04） |
| H-05 ST-05 scanner | B | 解消 | 入れ子コメント、通常・複数行・raw 文字列、補間を状態として扱い、6 テストがある |
| M-01 到達コードの共通記録 | A | 一部解消 | `run` / `runSync` / DetectMetadata / ClipboardError の paste button 構築失敗は `reportFailure` を通る。Append setup に迂回が残る（H-02） |
| M-02 stale result 待ち | B | 実装修正済み・変異証明未完 | 連番増加と label 一致を待つ。変異検査の妥当性は M-02 で指摘 |
| M-03 button identifier | B | 解消 | `sampleButton` が名前から identifier を導出し、section は children を `.contain` する |
| M-04 scrollIntoView | B | 解消 | 各試行の距離で方向を再判定し、失敗文に frame と距離列を含める |
| M-05 v1 全指摘の追跡 | C | 解消 | result v3 §1 が 10 件を状態つきで追跡する |
| L-01 Doc comment | C | 解消 | AppKit 利用を OP-19 の hosting に限定して記述する |

## H-01 の 4 点への回答

1. **unique を選び直しても pasteboard が孤立しないか: はい（Picker 経路）。** `scopeSelection` の setter は保持済み `createdUnique` を `activeScope` へ入れるだけで、`createPasteboard` を呼ばない（`ClipboardSampleView.swift:106-147`）。ただし `CreateUniquePasteboard` 自体を再押下する別経路は H-01 の新規指摘に該当する。
2. **作成失敗時に Picker 表示と `activeScope` が食い違わないか: はい。** `runScopeCreating` は `createPasteboard` 成功後だけ `createdNamed` / `createdUnique` と `activeScope` を更新し、失敗は `run` から `reportFailure` へ流れる（同 `:544-560`, `:614-647`）。Picker は `activeScope` の getter から表示されるため二重状態がない。
3. **完了順逆転で古い選択結果が新しい選択を上書きしないか: Picker 経路では起きない。** Picker の選択処理から非同期作成と `onChange` が消え、選択要求同士に pending result がない（同 `:53-60`, `:106-147`）。作成ボタンの再実行による資源の上書きは別問題として H-01 に記載した。
4. **導出 Binding の setter が SwiftUI 再評価中に問題を起こさないか: 確認した範囲では問題なし。** 再評価は getter `choice(for: activeScope)` を読むだけで、setter は Picker が selection を書くときに `selectScope` を同期実行する。結果表示の `@State` 更新は `DispatchQueue.main.async` に送られる（同 `:106-108`, `:125-147`, `:698-705`）。setter を再評価から呼ぶ `onChange` や副作用付き getter は存在しない。

## 重大な問題（high）

### H-01 [A]: `CreateUniquePasteboard` の再押下で古い unique pasteboard が回収不能になる

- 対象: `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:544-560`
- unique 作成成功時は `createdUnique = scope` で 1 個の handle を上書きする。既存 handle がある場合も古い scope を remove せず、結果文に「previous one is no longer reachable」と表示するだけである。
- `MacClipboardManager.createPasteboard` の契約は unique pasteboard の明示 release を要求し、計画 §6.4 も OP-07 から `RemoveCurrentPasteboard` までを lifecycle としている。古い handle を意図的に失う現在の処理は、その lifecycle を満たせない。
- Picker の再選択による v2 H-01 は解消しているが、35 ボタンを再実行可能にした UI から同じ資源孤立を起こせる新経路である。
- `createdUnique != nil` の間は新規作成を拒否する、古い unique を解放してから置換する、または複数 handle を保持して全て解放可能にする必要がある。

### H-02 [A]: `AppendWithStaleOwnership` の setup failure が `ClipboardError` と到達コードを失う

- 対象: `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:277-294`
- 2 回の setup copy を `try?` で実行し、どちらかが失敗すると固定の `.otherFailure("the setup copies failed")` を表示する。1506 / 1507 / 1509 / 1513 等の `ClipboardError` でも code / message を失い、`reachedCodes` に入らない。
- result v3 §2 は `reportFailure` を唯一の失敗表示経路にしたとするが、この経路は迂回している。MS-01 は「何らかの Result 更新」だけを見るため、この誤変換でも通過する。
- setup を `do / catch` にし、失敗時は元 error を `reportFailure(label:error:)` へ渡して act を止める必要がある。

## 改善提案（medium）

### M-01 [A]: 通常 Copy ボタンまで `localOnly` toggle の現在値を使用する

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:187-232`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:534-540`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md:478-490`
- `CopyText` / `CopyURL` / `CopyImage` 等は共通 `copy` helper を通り、この helper が常に `ClipboardCopyOptions(localOnly: localOnly)` を渡す。したがって Copy Options セクションで toggle を off にした後は、通常 Copy セクションの全操作まで off になる。
- 計画は通常 Copy と `Toggle localOnly + CopyWithCurrentOptions` を別の実演経路としており、公開 API の既定値も `true` である。通常 Copy は `.default`、現在値を試すのは `CopyWithCurrentOptions` に限定するのが計画と一致する。
- 併せて `CopyWithCurrentOptions` は押下時に toggle 値を捕捉し、scope と同じ時点の入力として Task に渡すべきである。

### M-02 [B]: M-02 の連番待ちは、壊したとき落ちることがまだ確認されていない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:81-105`
  - 同 `:168-189`
  - 実装結果 `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v3.md:116-119`
- 現在の `tap` が `sequence > before && label matches` を待つ実装自体は妥当である。同じボタンを 2 回押すテストも、同一文言の正常な再実行で偽陰性を起こさないことを確認する。
- しかしこれは、sequence 条件を削除した mutant、または 2 回目だけ Result を更新しない mutant をテストが確実に殺す証明ではない。「条件分岐を書かないと mutant を作れない」ことは変異検査を省略する理由にはならない。mutant はその検証契約だけを意図的に壊すためのものだからである。
- よって result v3 の自己評価どおり、現状は偽陽性防止の証明ではない。全ボタン検査の共通 harness という中心的な B なので、workflow の停止条件 2 は未充足である。待機判定を純粋関数へ分離して「label は一致するが sequence は同じ」を拒否するテストを置くか、2 回目だけ Result 更新を抑止する UI mutant で落ちることを確認する必要がある。

### M-03 [B]: ST-09 は capture が最初の `await` より前であることを検査しない

- 対象: `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:171-190`
- 検査は各 button body の `activeScope` 出現数と `let scope = activeScope` 出現数が等しいこと、および capture が 1 回以下であることだけを見る。
- 例えば `Task { await prepare(); let scope = activeScope; ... }` は `reads == captures == 1` で通るが、押下後の suspension 中に変更された scope を読む。テスト名とコメントがいう「at the moment of the click」「before anything is awaited」は保証していない。
- 記録された「Task 内で `activeScope` を直接読む」mutant は落とすが、H-02 の時間的性質を壊す mutant は残る。capture が `Task` より外側にあること、少なくとも body の最初の `await` より前にあることを構文上検査する必要がある。

### M-04 [B]: MS-07 のログ側は sample app を対象にした検証がない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:269-294`
  - `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:76-109`
  - `mac/MacLibrary/MacLibraryTests/Clipboard/ClipboardLogAuditTests.swift:44-64`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md:770-782`
- UI test は実入力 `nt-sample` が画面へ出ないことを正しく確認する。unit test は `SampleOutcome.logText` が message / payload を含まないことを確認する。
- しかしライブラリ側の log audit の走査根は `MacLibrary/Clipboard` と `UnityMacPlugin/Clipboard` の 2 本だけで、`MacLibraryExample` は対象外である。sample action に `Log.d(TAG, "name: \(sampleName)")` を追加する mutant は UI test と `SampleOutcome` test の双方を通る。
- 現在の sample source を目視した範囲では名前の直接ログはなく、これは A の現存不具合ではない。ただし MS-07 の「画面とログ」を確認済みとするには sample source の log audit または実ログ capture が必要である。

### M-05 [B]: exemption の正規表現はコメントどおりの front matter 限定ではない

- 対象: `scripts/check_design_consistency.py:354-373`
- 本文中の単なる語への言及で免除される欠陥は解消し、v5 の 8 件の名称ずれを検出できた点は正しい。
- ただし判定は `re.search(..., re.M)` で文書全体を走査するため、`- **\`PLANNED_SYMBOLS_EXEMPT\`**` で始まる行が appendix、変更履歴、コード例にあっても免除される。実際に同形式を `## Appendix` 下へ置いた入力で match することを確認した。コードコメントの「Only the front matter can declare it」は実装されていない。
- front matter / 基本情報セクションの範囲を切り出してから宣言行を探すか、ファイル先頭から最初の見出しまで等の明確な境界を導入し、その誤配置ケースのテストを追加する必要がある。

## 軽微な指摘（low）

### L-01 [C]: 計画の変更ファイル一覧が UI test と検査スクリプトを含まない

- 対象: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md:350-378`
- §7.2 は UI test を作成済みと明記するが、§4.1 の新規作成一覧に `ClipboardSampleViewUITests.swift` がない。今回の worktree 変更である `scripts/check_design_consistency.py` も一覧にない。
- result v3 には両変更の理由があるため実装判断は追跡できるが、workflow の「変更ファイル一覧と実際の diff」の記述上は不一致である。

## design-consistency exemption 修正の影響範囲

- 指定コマンドを v5 に対して実行し、`named symbols exist in the implementation` を含め FAIL なし。免除は適用されなかった。
- 現行機能設計 v9 も全検査が OK。
- 旧条件と新条件の差を repository 内の全 Markdown で比較した結果:
  - sample plan v4: 旧条件・新条件とも免除（基本情報に宣言行がある）
  - sample plan v5: 旧条件では変更履歴の言及だけで免除、新条件では非免除。意図した判定変化
  - result v3 と sample-app-design-review-v4: 旧条件では言及だけで免除、新条件では非免除。スクリプトをこれら非 design 文書へ実行すると `named symbols` が検査され、実際に FAIL する。ただし CLI の契約は design document 用なので通常運用の対象外
- `artifact/designs` 配下で v5 以外に判定が変わる文書はない。v4 は宣言済みのため維持される。superseded 文書の既知 FAIL には新たな影響を確認していない。
- 将来文書への残存リスクは M-05 のとおり、宣言形式の行を front matter 外へ置いても免除になる点である。

## 計画書整合性チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| 全セクション・全ボタンの実装 | ○ | 10 セクション、35 ボタンをソースから確認 |
| API 呼び出し方針の一致 | △ | 16 操作は呼ばれるが、通常 Copy の options が計画と異なる（M-01） |
| システム設定（Manifest / FileProvider 等）の正確性 | ○ | macOS Clipboard では追加設定不要。共有 scheme は存在する |
| 変更ファイル一覧との diff 整合 | △ | UI test と検査スクリプトが計画 §4 にない（L-01） |
| 計画との差分（追加判断）の result への記録 | ○ | UI test、scanner、MS-01 導出、ST-09 を result v3 §6 に記録 |

## サンプルアプリパターン適合チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| メニュー導線（Router / MainMenu） | ○ | `ContentView` の既存 `NavigationLink` / `menuCard` パターンに追加 |
| 画面構成パターン（タイトル / statusText / ScrollView） | ○ | macOS 既存 sample の構成に適合 |
| 成功/失敗表示フォーマット | ○ | `SampleOutcome` で成功 / 失敗を一元化し、秘匿対象コードを分岐 |
| 共通 UI 部品の利用 | ○ | 既存画面と同型の section / full-width button pattern を private 実装 |

## プロジェクトルール適合チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| common.md 準拠 | ○ | native sample から Manager native API を利用 |
| mac.md 準拠 | ○ | clipboard operation は `MacLibrary` 経由。UI / comment は英語 |
| サンプルアプリの依存方向（Unity プラグイン非依存） | ○ | sample source に `import UnityMacPlugin` なし。ST-06 も source を走査 |
| Log.d 網羅性 | ○ | mac.md の直接適用対象は library / plugin。sample の operation runner も安全な label / marker を記録 |
| KDoc 網羅性 | N/A | macOS / Swift のため対象外 |

## 手動確認観点の充足

| ID | 評価 | 状態 |
|---|---|---|
| MT-01〜MT-04 | △ | result v3 §7 で未実施 |
| MT-06〜MT-08 | △ | result v3 §7 で未実施。MT-07 は 2 OS、MT-08 は実機 2 台が必要 |
| MT-09 | △ | 機能設計 RK-22 により判定保留 |
| MS-01 | △ | 35 ボタンを導出して押す test code はあるが、本環境では UI test を完走できず独立再確認なし |
| MS-02 | △ | matched / unmet / 同一ボタン再実行の test code はある。連番条件の変異証明は M-02 |
| MS-03 | △ | 未作成拒否と named/general の実データ分離を検査する test code はあるが実行再現なし |
| MS-04 | △ | 未実施 |
| MS-05 | △ | 離脱・再入場 test code はあるが実行再現なし |
| MS-06 | △ | 未実施 |
| MS-07 | △ | 画面側 test は改善。sample のログ側検証が不足（M-04） |
| MS-08 | ○ | source と project 参照を静的確認し、Unity 依存なし |

## 検証結果

### design consistency / whitespace

- `python3 scripts/check_design_consistency.py artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md`: FAIL なし。`named symbols exist in the implementation` は OK（免除なし）。
- `python3 scripts/check_design_consistency.py artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`: 全項目 OK。
- `git diff develop --check`: 出力なし。
- 未追跡の sample Swift 4 ファイルも `git diff --no-index --check /dev/null <file>` で whitespace error なし。

### xcodebuild / xcresult

- 指定の `xcodebuild clean test -workspace MacWorkspace.xcworkspace ... -resultBundlePath /tmp/example.xcresult` を実行したが、テスト開始前に exit 66 となった。
- 主な環境出力: `CoreSimulatorService connection became invalid`、ユーザー Library の simulator log への `Operation not permitted`、最終的に `MacWorkspace.xcworkspace is not a workspace file`。
- workspace XML は `xmllint` で妥当、3 project の参照先も実在し、`xcodebuild -list -project MacLibraryExample/MacLibraryExample.xcodeproj` は target / scheme を列挙できた。拡張属性を持たない一時 workspace でも同じ制限環境エラーとなったため、コードや workspace XML の欠陥とは判定しない。
- `xcrun xcresulttool get test-results summary --path /tmp/example.xcresult` の実測は `result: unknown`、`totalTestCount: 0`、passed / failed / skipped すべて 0。これはテスト未開始の bundle であり、通過結果ではない。
- ソース上の宣言数は `MacLibraryExampleTests` 19（Clipboard 18 + 既存 1）、UI 6、合計 25 で報告値と一致する。parameterized 展開後 26、MacLibrary 307 / 351、UnityMacPlugin 75 / 76、失敗 0 は xcresult を生成できず独立確認できなかった。
- compile に到達していないため clean build warning も計測不能。preflight の Xcode framework warning をアプリの build warning には数えない。報告された warning 0 と矛盾する証拠は得ていないが、再現済みとも扱わない。
- 既知の accessibility hierarchy 空事象とは異なり、今回は app launch / UI test より前の環境失敗だった。

## 総合評価

**要修正（重大）**。

- **A-count: 3。0 ではない。** unique pasteboard の回収不能、Append setup error の誤表示・未記録、通常 Copy の options 逸脱を修正して再レビューが必要。
- 中心検証 B のうち、M-02 の mutation proof、ST-09 の時間的位置、MS-07 の sample log、exemption の front matter 境界も未完である。
- workflow の停止条件では A が 0 でないため次工程へ進めない。加えて「追加検査を壊すと落ちる」の条件は M-02 / M-03 / M-04 / M-05 の範囲で未充足。
- MT-01〜MT-09、MS-04、MS-06、および機能設計 §12.4 の既知未実装項目は result v3 に open として残っており、今回新規の A には数えていない。
