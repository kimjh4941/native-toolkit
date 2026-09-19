# サンプルアプリ実装結果 v3

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/`
- 計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md`（本版で v4 から更新）
- 対応タスク: T-18（機能設計 §13）
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v2.md`
- 反映したレビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implement-sample-app-review-v2.md`

> **v2 の「レビュー v1 の 4 件」という記載は誤りだった。** レビュー v1 は 10 件（高 4 / 中 4 /
> 低 2）で、v2 が扱ったのは高 4 件だけである。残り 6 件は反映も記録もされないまま追跡表から
> 消えていた（レビュー v2 M-05）。本版は v1 / v2 の全 21 件を状態つきで残す。

---

## 1. レビュー v1（10 件）の追跡

| ID | 区分 | v2 時点 | 本版 | 対応 |
|---|---|---|---|---|
| H-01 Active scope Picker 未実装 | A | 部分 | **解消** | Picker を追加（v2）。本版で計画どおり「選択のみ」に是正（レビュー v2 H-01） |
| H-02 DetectMetadata が arrange 失敗を握りつぶす | A | 部分 | **解消** | act を止める（v2）。本版で scope 固定と `ClipboardError` の保持を追加 |
| H-03 UI テストの偽陽性 | B | 部分 | **解消** | ラベル待ち（v2）。本版で連番待ちと対象拡張 |
| H-04 ST-05 の block comment | B | 部分 | **解消** | 単純除去（v2）。本版で入れ子と文字列を扱う走査に置換 |
| M-01 到達エラーコード一覧 | A | **未反映** | **解消** | `reportFailure` に集約。UI テストを追加 |
| M-02 button の accessibility identifier | B | **未反映** | **解消** | 全 35 ボタンに `clipboard.button.<name>` |
| M-03 共有 scheme と test コマンド | B | 解消 | 解消 | - |
| M-04 UI テスト追加を「追加判断」に記録 | C | **未反映** | **解消** | 本書 §6 と計画 v5 §7.2 |
| L-01 `xcuserstate` の混入 | C | 解消 | 解消 | - |
| L-02 Doc comment が実装より強い | C | **未反映** | **解消** | AppKit の利用範囲（OP-19 の hosting）に限定 |

---

## 2. レビュー v2（11 件）の対応

### A 区分（3 件）

| ID | 内容 | 対応 |
|---|---|---|
| H-01 | Picker が pasteboard を作成し、unique を孤立させ、失敗時に表示と実状態が食い違い、非同期の完了順も保証されない | **Picker の選択値を `activeScope` から導出する**（別 `@State` を廃止）。作成は section 1 のボタンだけが行う。未作成の scope を選ぶと理由を表示して拒否する |
| H-02 | Detect の arrange と act が別々に `activeScope` を読む／arrange の `ClipboardError` を捨てる | ボタン押下時に `let scope = activeScope` を **1 回だけ**捕まえ、arrange と act の両方へ渡す。arrange の失敗は `reportFailure` を通す |
| M-01 | 通常 runner で到達した `ClipboardError` が「到達一覧」に入らない | `reportFailure` を唯一の失敗表示経路にし、そこで記録する。`buildPasteButton` も通す |

**H-01 の設計上の要点。** 状態を 2 か所（`activeScope` と Picker の選択値）で持つ限り、同期の
代入と利用者のクリックを `onChange` は区別できない。**フラグで区別する方法は、飛ばす回数が
ずれた瞬間に利用者の操作を飲み込む。** 導出値にすれば同期する対象そのものが無くなる。

### B 区分（6 件）

| ID | 内容 | 対応 |
|---|---|---|
| H-03 | MS-01〜MS-03 が計画の要求を検査していない | MS-01 は**ソースから導出した全 35 ボタン**を押す。MS-02 は後述の新ボタンで unmet 分岐を画面で通す。MS-03 は Picker を実際に操作し、scope 引数が選択に従うことを確認する |
| H-04 | MS-07 が実際に渡していない名前を検査していた | `CreateNamedPasteboard`（`nt-sample` を実際に渡す）で確認する。**計画 v4 の MS-07 手順自体が成立していなかったため、計画を v5 で訂正した** |
| H-05 | ST-05 の regex が入れ子コメント・文字列内の delimiter を扱えない | 文字単位の走査に置換（入れ子ブロック、行コメント、通常／複数行／raw 文字列、補間）。走査自体に 6 件の単体テストを追加 |
| M-02 | `tap` が同じラベルの前回結果を即時受理する | 画面に結果の連番（`clipboard.resultSequence`）を出し、**連番が増え、かつラベルが一致する**まで待つ |
| M-03 | button identifier が無い | `sampleButton(_:action:)` を経由させ、identifier をボタン名から導出する |
| M-04 | `scrollIntoView` が初回無移動だと方向を決め直さない | **毎回距離が縮んだかで判定**し、縮まなければ反転する。失敗文に viewport・要素・距離の推移を含める |

### C 区分（2 件）

| ID | 対応 |
|---|---|
| M-05 | 本書 §1 で v1 の全 10 件を状態つきで追跡 |
| L-01 | Doc comment を AppKit の実際の利用範囲に限定 |

---

## 3. 対応の過程で見つけた 2 件

### R-SA15: section の identifier が中のボタンの identifier を消していた

`sectionView` が付けた `clipboard.section.<name>` が子へ伝播し、**全ボタンの identifier が
セクション名になっていた**（M-03 を入れた直後、UI テストが全滅して判明）。
`.accessibilityElement(children: .contain)` を先に宣言して解消。計画 v5 §7.2 に記録した。

### R-SA16: 機械照合の免除が、本文で言及するだけで有効になっていた

`check_design_consistency.py` は `PLANNED_SYMBOLS_EXEMPT` を**文書のどこかに含めば**免除して
いた。計画 v5 は変更履歴の表でこの語に触れているだけだが、それで「識別子の実在」検査が
SKIP になっていた。**免除の宣言行（`- **`PLANNED_SYMBOLS_EXEMPT`**` で始まる行）だけを見る**
よう修正した。

修正後に検査を通したところ、計画が実装に無い名前を 8 件挙げていた。

| 名前 | 実際 |
|---|---|
| `detectionFixture`（4 箇所） | 実装は `detectionText` |
| `plainTextOnly` | 実装は既定の `text()` |
| `observationActive` | 実装は `isObserving` |
| copyable / cuttable / pasteDestination | 対象外の Unity 操作。このリポジトリの記号ではないのでコード記法をやめた |
| PBXFileSystemSynchronizedRootGroup | Xcode の project 構造。同上 |

**免除が効いていた間、計画と実装の名前のずれは 1 件も検出されていなかった。**

---

## 4. 変異検査

追加・修正した検査が、契約を壊すと落ちることを確認した。

| 壊した内容 | 落ちるべき検査 | 結果 |
|---|---|---|
| `Clear` ボタンを無反応にする | MS-01 | **落ちた**（`Clear did not report. sequence stayed at 32`） |
| `copy` が渡された scope を無視して `.general` を使う | MS-03 | **落ちた**（`clearing general emptied the named pasteboard`） |
| 満たされなかった期待を成功として表示する | MS-02 | **落ちた** |
| `createPasteboard` の結果に pasteboard 名を含める | MS-07 | **落ちた**（`the pasteboard name 'nt-sample' reached the screen`） |
| Picker の `unique` 選択が作成を行う（R-SA9 の再現） | MS-03 | **落ちた**（`selecting an uncreated scope was not refused`） |
| 通常の失敗を到達一覧に記録しない | 到達一覧のテスト | **落ちた**（`No error code reached yet.`） |
| 入れ子ブロックコメントの深さを数えない | ST-05 の走査テスト | **落ちた** |
| 文字列内のエスケープを扱わない | 同上 | **落ちた** |
| `Snapshot` が `Task` の中で `activeScope` を直接読む | ST-09 | **落ちた**（`Snapshot reads activeScope somewhere other than its capture`） |

**連番待ち（M-02）は変異で証明できていない。** 「2 回目のクリックだけが無反応になる」状態を
作るには条件分岐を書く必要があり、実際の欠陥はその形を取らない。代わりに**同じボタンを 2 回
押す経路を MS-02 に入れた**（結果の文言が前回と一字一句同じになる経路）。これは連番待ちが
偽陰性を防ぐ証明ではなく、**偽陽性を起こさない**ことの確認である。

---

## 5. テスト結果

| 対象 | 宣言数 | 展開後 | 失敗 |
|---|---|---|---|
| `MacLibraryExampleTests` | 19 | 20 | 0 |
| `MacLibraryExampleUITests/ClipboardSampleViewUITests` | 6 | 6 | 0 |
| `MacLibrary` | 307 | 351 | 0 |
| `UnityMacPlugin` | 75 | 76 | 0 |

- 件数は xcresult から取得（`xcrun xcresulttool get test-results summary`）。
- **`clean test` で警告 0 件。** 差分ビルドでは変更していないファイルの警告が再出力されない
  ため、警告の計測は clean で行う。v2 の「警告 0」はこの条件を満たしておらず、実際には
  `PasteboardScope` の switch に 2 件出ていた（`@unknown default` を追加して解消）。
- `git diff develop --check`: 0 件。
- `scripts/check_design_consistency.py` 計画 v5: **全項目 OK**（免除なし）。

### MS の確認状況

| MS | 内容 | v2 | v3 |
|---|---|---|---|
| MS-01 | 全ボタンが Result を更新する | 6 ボタンのみ | **全 35 ボタン（ソースから導出）** |
| MS-02 | 期待が満たされない場合に失敗と表示される | matched のみ | **unmet を画面経路で確認** |
| MS-03 | scope 引数が Active scope に従う | 表示遷移のみ | **Picker 操作 + 実データで確認** |
| MS-05 | 画面離脱で監視が停止する | 確認済み | 確認済み |
| MS-07 | 利用者が付けた名前が画面に出ない | **空文字を検査（無効）** | **実際に渡す名前で確認** |
| MS-04 / MS-06 | - | 未実施 | 未実施 |
| MS-08 | Unity 非依存 | ST-06 | ST-06 |

---

## 6. 計画からの追加判断

| 判断 | 理由 |
|---|---|
| UI テストを書く（計画 v4 は「書かない」） | T-18 の完了条件を実行で確認するため。計画 v5 §7.2 で撤回を明記 |
| `ExpectFailureThatSucceeds` ボタンを追加 | MS-02 の unmet 分岐を画面で通す経路が無かった。計画 v5 §5「10. Error Cases」に追加 |
| ST-05 の走査を SwiftSyntax ではなく自前の状態機械で書く | レビュー v2 H-05 は SwiftSyntax を提案したが、テストターゲットにビルド依存を足す。約 90 行の走査と、それ自体に対する 6 件のテストで釣り合うと判断した。**入れ子コメントと文字列内 delimiter の変異で落ちることは確認済み** |
| MS-01 の対象をソースから導出 | 手書きの一覧は、抜けたボタンを検査対象外にできる |
| ST-09 を追加（レビュー v2 の指摘ではない） | **H-02 の修正は 19 か所への機械的な置換で、それを守る検査が無かった。** 後から `Task` の中で `activeScope` を直接読んでも従来のテストは全部通る。「ボタンの中で `activeScope` は `let scope = activeScope` の形でしか現れない」をソースから検査する |

---

## 7. 残作業

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
| 旧版の設計文書が機械照合で FAIL する | 現行版（機能設計 v9、計画 v5）は OK。旧版は superseded なので追わない |
| `ShareSampleViewUITests` の再実行 | **未実施**。clipboard の範囲外 |
