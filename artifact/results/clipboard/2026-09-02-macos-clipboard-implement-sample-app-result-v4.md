# サンプルアプリ実装結果 v4

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/`
- 計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md`（本版で §4.1 / §4.2 を更新）
- 対応タスク: T-18（機能設計 §13）
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v3.md`
- 反映したレビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implement-sample-app-review-v3.md`

> レビュー v3 の 8 件（A 3 / B 4 / C 1）をすべて反映した。**A 3 件のうち 2 件は、前ラウンドで
> 直したのと同じ欠陥が、直さなかった兄弟の経路に残っていたものである。**

---

## 1. レビュー v3 の対応

### A 区分（3 件）

| ID | 内容 | 対応 |
|---|---|---|
| H-01 | `CreateUniquePasteboard` を再押下すると古い unique が回収不能になる | **作成の前に古いものを解放する。** 結果文に「孤立した」と書くだけでは、明示 release を要求するライブラリの契約を満たせない |
| H-02 | `AppendWithStaleOwnership` の setup が `try?` で `ClipboardError` を捨てる | `do / catch` にして `reportFailure` へ渡す |
| M-01 | 通常の Copy まで Copy Options の `localOnly` toggle に従う | 通常 Copy は既定値を使う。`CopyWithCurrentOptions` は toggle を**押下時に捕捉**する |

**H-02 は、前ラウンドで `DetectMetadata` に対して直したのと同じ欠陥である。** 同じ形の
`try?` が Append にも残っていた。**1 箇所を直して、同型の残りを探さなかった。**

**M-01 も同型である。** scope は押下時に捕捉するようにしたのに、同じ入力である toggle は
そのままにしていた。

H-01 の解放順序について。**作成の後ではなく前に解放する。** 後にすると、解放の失敗が直後の
作成成功の下に埋もれる。前に解放し、`activeScope` を `general` に戻してから作成するので、
作成が失敗しても回収不能な資源は残らない。

### B 区分（4 件）

| ID | 内容 | 対応 |
|---|---|---|
| M-02 | 連番待ちが変異で確認されていない | **待機規則を純関数 `isResultOfThisClick` に切り出し、規則そのものを 4 件のテストで検査する**。「アプリを壊して mutant を作れないことは、変異検査を省く理由にならない」という指摘は正しい |
| M-03 | ST-09 が「最初の `await` より前」を検査していない | capture の位置が最初の `Task` / `await` より前であることを併せて検査する |
| M-04 | サンプル自身のログに対する検査が無い | ST-10 を追加。サンプルの全 `Log.` 呼び出しを継続行込みで拾い、pasteboard 名を含まないことを検査する |
| M-05 | 免除の宣言行が文書のどこにあっても成立する | **免除の判定範囲を「2 番目の `##` 見出しより前」に限定した。** 形ではなく範囲で決める |

**M-02 の指摘は私の判断が誤っていた。** v3 では「2 回目だけ無反応という状態は条件分岐なしに
作れないので変異で証明できない」と書いた。**壊すべき対象はアプリではなく判定規則そのもの
だった。** 規則を関数に出せば、「文言は一致するが連番は同じ」を受理する mutant を直接作れる。

### C 区分（1 件）

| ID | 対応 |
|---|---|
| L-01 | 計画 v5 §4.1 に UI テスト 2 ファイル、§4.2 に `check_design_consistency.py` を追加 |

---

## 2. 変異検査

| 壊した内容 | 落ちるべき検査 | 結果 |
|---|---|---|
| 待機規則から連番条件を外す | `ClipboardSampleWaitRuleTests` | **落ちた**（`testTheSameTextFromAnEarlierClickIsNotAccepted`） |
| `Clear` の capture を `Task` の中へ移す | ST-09 | **落ちた**（`Clear captures activeScope after its first Task`） |
| サンプルが pasteboard 名をログに出す | ST-10 | **落ちた**（`ClipboardSampleView.swift logs the caller supplied pasteboard name`） |
| 免除の宣言行を appendix に置く | 免除の範囲判定 | **免除されない**ことを確認（基本情報に置いた場合は免除される） |

v3 で確認済みの 9 件（MS-01 / MS-02 / MS-03 / MS-07 / 到達一覧 / ST-05 の 2 件 / ST-09 /
Picker の再作成）と合わせて **13 件**。

---

## 3. テスト結果

| 対象 | 宣言数 | 展開後 | 失敗 |
|---|---|---|---|
| `MacLibraryExampleTests` | 20 | 21 | 0 |
| `ClipboardSampleViewUITests` | 6 | 6 | 0 |
| `ClipboardSampleWaitRuleTests` | 4 | 4 | 0 |
| `MacLibrary` | 307 | 351 | 0 |
| `UnityMacPlugin` | 75 | 76 | 0 |

- 件数は xcresult から取得。clipboard 分の合計は **30 宣言 / 31 展開 / 失敗 0**。
- `clean test` の警告は `appintentsmetadataprocessor` の定型出力のみ。**Clipboard 由来 0 件。**
- `git diff develop --check`: 0 件。
- `scripts/check_design_consistency.py`: 計画 v5・機能設計 v9 とも全項目 OK。

### UI テストターゲット全体を回した場合

`-only-testing:MacLibraryExampleUITests`（50 宣言）では 1 件失敗する。
**Xcode テンプレートの `MacLibraryExampleUITestsLaunchTests/testLaunch`** が
`com.adobe.AdobeCRDaemon` の状態取得を 120 秒待って落ちる。**clipboard とは無関係の環境事象**
であり、本実装が触っていないファイルである。

なお同じ実行で `ShareSampleViewUITests` 13 件は通過した。result v1 に「同一症状で全件失敗
する」と記録した状態は、現在は再現しない。

### レビュー v3 が実測を再現できなかった件

レビュー環境では `xcodebuild` がテスト開始前に exit 66 となり（`CoreSimulatorService
connection became invalid`、simulator log への `Operation not permitted`、
`MacWorkspace.xcworkspace is not a workspace file`）、xcresult は `unknown / 0 tests` だった。
**レビューはこれを「通過」と扱わず未再現と記録している。判断として正しい。**
本書の件数はローカル実行の xcresult による。

---

## 4. 残作業

| 項目 | 状態 |
|---|---|
| MT-01 / MT-02 / MT-03 / MT-04 / MT-06 / MT-07 | **未実施**（手動確認） |
| MT-08 | **未実施**（端末 2 台が必要） |
| MT-09 | 判定保留 |
| MS-04（named / unique の作成→操作→削除の通し） | **未実施** |
| MS-06（View 破棄で進行中の load がキャンセルされる） | **未実施** |
| 平文 `detectMetadata` が 1515 を返す件 | **要検証** |
| `PasteButton` が `supportedContentTypes` に一致しない provider を渡すか | **要検証**（MT-06 と 1521 到達に必要） |
| BT-01 / BT-08 / BT-12 / CT-05 | **未実装**（機能設計 §12.4 に記載済み） |
| `MacLibraryExampleUITestsLaunchTests/testLaunch` | 環境事象で失敗。テンプレート由来で本タスクの範囲外 |
| 旧版の設計文書が機械照合で FAIL | 現行版は OK。superseded は追わない |
