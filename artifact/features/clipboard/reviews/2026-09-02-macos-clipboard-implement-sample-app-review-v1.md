# macOS Clipboard サンプルアプリ実装レビュー v1

## レビュー対象

- 日付: 2026-09-02
- ブランチ: `feature/NTKIT-15`
- HEAD: `a634619bd4cb0c8f32d1f891bd187eabf9c6fee3`
- 比較基準: `develop...HEAD`（merge-base: `9367da5c6aeb634c26944c9ec7d4385c54e40d13`）
- 追加対象: 未コミット・未追跡の `mac/MacLibraryExample/` 配下および実装結果 v1
- 計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v1.md`
- 対象 OS: macOS 15 以降

> `develop...HEAD` は機能ブランチ全体の差分を含む。一方、今回のサンプル本体・テスト・共有
> scheme は未追跡で同 diff に現れないため、worktree の実ファイルを追加対象としてレビューした。

## レビュー概要

- `ContentView` に Clipboard 画面への導線を追加し、`ClipboardSampleView` に計画 §3.1 の
  10 セクションを配置している。
- `MacClipboardManager.shared` の公開操作 16 名はすべてサンプルソースから呼ばれており、
  `UnityMacPlugin` への import・build dependency はない。
- native `async throws`、同期 control / factory、paste button の `NSViewRepresentable` hosting は
  機能 API の実行方式に沿っている。
- 単体テストは再実行して成功した。UI テストと MT-01〜MT-09 は、実装結果どおり未確認である。
- ただし、Active scope Picker の欠落、`DetectMetadata` の arrange 失敗握りつぶし、UI テストと
  ST-05 の偽陽性経路があり、計画の中心契約を満たしたとは判定できない。

## 重大な問題（high）

### H-01: 計画で必須の Active scope Picker が実装されていない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:45`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:81`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:264`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:451`
- 計画は画面上部に Active scope の `Picker` を置き、`general / named / unique` を選べることを
  画面要件としている。
- 実装は現在値を表示する `Text` と create / remove ボタンだけで、`Picker` は存在しない。
  `rg 'Picker' ClipboardSampleView.swift` も 0 件である。
- そのため利用者は scope を独立して切り替えられず、「同じ操作を scope 別に試す」という
  画面契約が欠けている。MS-03 も create / remove による遷移しか見ておらず、この欠落を検出しない。
- 作成済み named / unique scope を安全に選択できる UI モデルを定義して Picker を実装し、
  general への切り替えと scope 引数を持つ操作への反映を検証すること。

### H-02: `DetectMetadata` だけ arrange 失敗を無視し、古い pasteboard を検査する

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:290`
  - 実装結果 `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v1.md:50`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:482`
- `DetectPatterns` / `DetectValues` は arrange の copy を同じ `run` 内で `try await` するが、
  `DetectMetadata` は `try? await arrangePlainText()` で失敗を捨てた後に OP-11 を実行する。
- named pasteboard の解決失敗や copy 失敗が起きても、前に残っていた内容で OP-11 を実行するため、
  1515 の一致・不一致が fixture ではなく外部状態に依存する。実装結果の「各ボタンが
  arrange → act を一続きで行う」という記載とも一致しない。
- arrange の失敗はその ClipboardError を表示して act を行わないこと。arrange 成功後だけ
  `runExpectingError` へ進む構造にし、この分岐をテストすること。

### H-03: UI テストが前回の結果を新しい結果として受理し、MS-01 / MS-03 を偽陽性にできる

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:58`
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:62`
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:83`
  - `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift:97`
  - 実装結果 `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v1.md:117`
- `tap` はボタン押下後、表示が placeholder でなければ即時 return する。2 回目以降は非同期処理が
  更新する前の前回結果が既に placeholder ではないため、新しい操作が何も報告しなくても成功扱いになる。
- MS-01 の配列は 6 ボタンだけで、実際に触るのは Copy / Read / Observe / Clear の 4 セクションである。
  コメントと result の「各セクションの代表ボタン」に反し、Scope / Copy Options / Append / Detect /
  Paste Control / Error Cases を検証していない。計画 MS-01 の「10 セクションすべてのボタン」とも一致しない。
- MS-02 のテスト名は「期待失敗が成功した場合の失敗表示」を掲げるが、実際には `RemoveGeneral` が
  1508 を返した正常な matched 経路だけを確認し、unexpected success の画面経路は実行していない。
- 押下前の結果を保存し、対象 label の新しい result へ変わるまで待ち、timeout 時は必ず fail すること。
  MS-01 の対象を計画どおり定義し直し、MS-02 は純粋判定の ST-07 と UI 統合の責務を明確に分けること。

### H-04: T-18 の中心検査 ST-05 は block comment で偽の green になる

- 対象:
  - `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:171`
  - `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift:199`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:645`
- `stripped(_:)` が除去するのは `//` 以降だけで、`/* ... */` の block comment はそのまま残る。
  したがって実呼び出しを `/* MacClipboardManager.shared.clear(...) */` に置換しても、正規表現は
  `clear` を called として抽出する。
- result v1 の変異検査は削除と line comment だけで、計画が要求する「コメントを除外」を完全には
  壊して確認できていない。ST-05 / ST-06 は T-18 完了条件の機械検査と明記された中心契約なので、
  この穴は記録だけではなく修正対象である。
- SwiftSyntax 等で call expression を抽出するか、少なくとも line / block comment、通常文字列、
  multiline string を区別できる scanner にすること。block comment 変異で落ちることも記録すること。

## 改善提案（medium）

### M-01: Error Cases 一覧が通常 runner で到達した ClipboardError を記録しない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:389`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:474`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:487`
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:529`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:518`
- `reachedCodes` へ追加するのは expected-error runner の `report` だけである。通常の `run` / `runSync`
  や paste button 構築で ClipboardError に到達しても一覧へ残らない。
- 特に計画 §6.6 が「到達したら記録」とする環境依存の 1513 / 1514 は通常 detect 経路で発生するため、
  現在の Error Cases には記録されない。
- ClipboardError の表示経路を一元化し、すべての到達コードを同じ場所で記録すること。

### M-02: 計画で定義した button accessibility identifier がない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:81`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:676`
- section / result / observe status には identifier があるが、各 `Button` に
  `clipboard.button.<name>` が付いていない。UI テストは可変な表示 label に依存している。
- 計画どおり button identifier を付け、UI テストも identifier を使うこと。長い ScrollView 内の
  off-screen 要素については、存在確認だけでなく scroll / hittable の処理も用意するとよい。

### M-03: 共有 scheme と計画の標準 test コマンドが両立していない

- 対象:
  - `mac/MacLibraryExample/MacLibraryExample.xcodeproj/xcshareddata/xcschemes/MacLibraryExample.xcscheme:26`
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:690`
  - 実装結果 `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v1.md:145`
- 共有 scheme の TestAction は unit test と UI test をどちらも `skipped="NO"` にしている。一方、
  計画の再現コマンドは対象を限定しない `xcodebuild clean test` であり、現在の環境では既知の
  UI test 失敗を含んで command 全体が失敗する。
- unit acceptance 用に `-only-testing:MacLibraryExampleTests` を明記し、UI test は別コマンドに分けるか、
  既定 scheme での実行方針を計画・result に明記すること。

### M-04: UI テスト追加という計画差分が「追加判断」に記録されていない

- 対象:
  - 計画 `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md:687`
  - 実装結果 `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v1.md:81`
- 計画は費用対効果を理由に UI テストを「書かない」と明記するが、実装は 5 件を追加した。
- result の追加判断には menu navigation fallback だけがあり、「UI テストを追加する判断」と
  pasteboard 共有時の直列化方針、未実行時の scheme 方針が記録されていない。
- 追加自体は有益だが、計画との差分として理由・実行方式・既知制約を §3 に追記すること。

## 軽微な指摘（low）

### L-01: ユーザー固有の Xcode 状態ファイルが変更に混入している

- 対象: `mac/MacWorkspace.xcworkspace/xcuserdata/jonghyunkim.xcuserdatad/UserInterfaceState.xcuserstate`
- result の変更ファイル一覧にない IDE 状態の binary diff で、サンプル実装とは無関係である。
- 既に追跡されているため ignore だけでは除外されない。コミット対象から外すこと。

### L-02: View の Doc comment が実装より強い禁止を述べている

- 対象: `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift:10`
- 「AppKit directly は使わない」と読めるが、同ファイルは OP-19 の hosting のため `AppKit` / `NSView`
  を直接使用している。禁止されるのはライブラリ API を迂回した機能実装であり、UI adaptation は必要である。
- 「clipboard operation は AppKit を直接呼ばず MacLibrary 経由」と範囲を限定すると実態に合う。

## 計画書整合性チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| 全セクション・全ボタンの実装 | △ | 10 セクションはあるが、必須の Active scope Picker がない |
| API 呼び出し方針の一致 | △ | 16 操作を native API から呼ぶが、DetectMetadata の arrange 契約が不一致 |
| システム設定の正確性 | ○ | Manifest / FileProvider 変更は不要。共有 scheme は作成済み |
| 変更ファイル一覧との diff 整合 | △ | sample ファイルは result と一致。未記載の xcuserstate 差分がある |
| 計画との差分の result 記録 | △ | source scanner 変更は記録済み。UI テスト追加判断が未記録 |

## サンプルアプリパターン適合チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| メニュー導線 | ○ | 既存の `NavigationLink` / `menuCard` パターンに一致 |
| 画面構成パターン | ○ | title、result、status、ScrollView、section 構成に一致 |
| 成功/失敗表示フォーマット | ○ | `SampleOutcome` で成功・ClipboardError・その他を統一 |
| 共通 UI 部品の利用 | ○ | private helper / ButtonStyle の同パターン複製は許容範囲 |

## プロジェクトルール適合チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| `common.md` 準拠 | ○ | native sample から native library のみへ依存 |
| `mac.md` 準拠 | ○ | async / sync の区別、Main thread 反映、英語 UI / comment に適合 |
| サンプルアプリの依存方向 | ○ | `UnityMacPlugin` import・build dependency ともに追加なし |
| `Log.d` 網羅性 | ○ | 操作 runner と lifecycle にログあり。pure UI helper は除外対象 |
| KDoc 網羅性 | N/A | macOS / Swift 対象。public symbol の追加なし |

## 手動確認観点の充足

| 観点 | 評価 | 状態 |
|---|---|---|
| MT-01 他アプリ copy → Read | △ | 未実施 |
| MT-02 Copy → 他アプリ paste | △ | 未実施 |
| MT-03 append ownership | △ | 未実施 |
| MT-04 observe / foreground | △ | 未実施 |
| MT-06 Paste Control 部分失敗 | △ | 未実施。provider 挙動も要検証 |
| MT-07 macOS 15.4.1 / 15.2 | △ | 2 環境とも未実施 |
| MT-08 Universal Clipboard | △ | 実機 Mac + iPhone 未実施 |
| MT-09 privacy alert | △ | 判定保留。観察も未実施 |
| MS-01 全ボタン結果更新 | × | UI 未実行に加え、対象不足と stale-result 偽陽性がある |
| MS-02 expected error 3 分岐 | △ | ST-07 の純粋判定は通過。UI integration は未確認・対象不足 |
| MS-03 Active scope | × | UI 未実行。Picker 自体が未実装 |
| MS-04 named / unique lifecycle | △ | 未実施 |
| MS-05 画面離脱時 observe 停止 | △ | teardown 実装あり。UI 未実行 |
| MS-06 paste load cancellation | △ | 未実施 |
| MS-07 機微情報非表示 | △ | formatter 単体テストは通過。画面・実ログ未確認 |
| MS-08 Unity 非依存 | ○ | source scan と project dependency を確認 |

## 検証結果

- `xcodebuild ... -only-testing:MacLibraryExampleTests clean test`: `TEST SUCCEEDED`
  - xcresult top-level: 11 tests / failed 0
  - device cases: 12 passed / failed 0
  - UI test targetを含め build は成功したが、UI test 自体は実行対象外
- `git diff develop --check`: clean
- 公開操作: `MacClipboardManager` の 16 operation name が sample source に実在
- 依存確認: sample project は `MacLibrary.framework` のみに link。`UnityMacPlugin` 参照なし
- UI テスト: 実装結果どおり未実行。既存 Share UI test も同じ accessibility hierarchy 問題との報告を確認
- MacLibrary / UnityMacPlugin 全テストは今回再実行していない。result v1 の 351 / 76 passed を参照

## 総合評価

**要修正（重大）**

公開操作 16 件の native 呼び出しと Unity 非依存という T-18 の骨格は成立し、単体テストも成功する。
一方、Active scope の操作 UI が欠け、`DetectMetadata` は fixture 設定に失敗しても古い内容で続行する。
これは利用者から見た振る舞いを変える A 区分の問題である。

さらに、中心契約を担う ST-05 と追加 UI テストには偽陽性経路があり、UI 未実行という open riskを
解消した後も現状のままでは計画を証明できない。H-01〜H-04 を修正し、壊すと落ちる変異検査を
追加して再レビューする必要がある。

MT-01〜MT-09 と MS-04 / MS-06 の未実施は result に明記されており隠蔽ではないが、完了扱いには
できない。特に Paste Control の実貼り付け、observer lifecycle、OS 2 バージョン、実機 2 台の
確認は残リスクとして維持する。
