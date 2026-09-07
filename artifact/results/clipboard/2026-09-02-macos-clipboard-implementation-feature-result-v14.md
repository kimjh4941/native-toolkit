# 実装結果レポート v14

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v12 の指摘 17 件の反映と、実装レビューの収束**
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v13.md`

> **本版で実装レビューを一区切りとする。** 判断の根拠は §5。

---

## 1. まず訂正

**v13 の反映表は 5 項目で実態より進んだ状態を書いていた。** レビュー v12 の判定は
「反映 9 / 一部 7 / 未対応 2」で、私は 18 件すべて反映と報告した。

| 実態 | 項目 |
|---|---|
| 未対応 | L-2（設計の `Timer` 記述）、L-7（削除跡の空行） |
| 半分 | L-6（`run()` だけ修正、他 3 経路が残存）、M-1 / M-2（§15 と §4.1 に残存） |

確認せずに「完了」と書いた。本版ではすべて反映済みで、検証コマンドも §4 に記載する。

---

## 2. レビュー v12 の 17 件

### H-1: DoD が存在しないテストを [x] にしていた

BT 9 件 / CT 3 件 / PT 5 件が「全通過する」の対象に入っていたが、実体がなかった。

**原因は生成元の取り違えである。** v12 で「手書きをやめて生成する」と決めたとき、
生成元を**設計表の行**にした。表に行があれば通る。**テストの実在は一度も見ていない。**

対応:

- **DoD の「12.x が全通過する」5 行を削除した。** 測定ではなく主張であり、実際に嘘だった。
  テストが通ることは実行が示すもので、文書のチェックでは検証にならない
- 調査の結果、17 行のうち **10 行は検証が実在**していた（ID を書いていないだけ）。
  PT-09〜15 は `H-4: a second press delivers its own result` のように R 番号で書かれていた
- 本当に未検証だったのは 7 行

### H-4: 機械照合に同型の穴が 3 つ

すべて再現し、すべて塞ぎ、再現テストで検出を確認した。

| 穴 | 原因 | 修正 | 検証 |
|---|---|---|---|
| 部分文字列一致 | `ident in corpus` が文字列包含 | 単語単位の集合照合 | `ScopeResult` が CAUGHT |
| コメント混入 | production のコメントが corpus に入る | corpus からコメント除去 | `domains` が CAUGHT |
| **設計→実装の向き未検査** | 実装→設計しか見ていなかった | 逆方向の対応検査を追加 | 実装に無い `detectionDenie` が CAUGHT |

**3 つ目が本質である。** 取り残しは常にこの向きで起きるのに、一度も見ていなかった。

厳密化の副作用で誤検出が 4 件出た。うち 1 件は本物で、T-17 の DocC 要件に File Promise の
`finished` が残っていた。

### H-2 / H-3

- `.h` と §8.4.3 の `_Nullable` 不一致を訂正
- `makePasteButton` の throw 契約を設計 §8.2 / §7.11 と公開 DocC に反映。**throw させる変更を
  入れながら契約の記述を更新していなかった**

### medium / low

| ID | 対応 |
|---|---|
| L-2 | 設計の `Timer` 記述 5 箇所を、実装どおりポーリング `Task` へ。§4.1 の所有者も訂正 |
| L-6 | encode 失敗の誤報告を残り 3 経路にも適用 |
| L-7 | 削除跡の空行、および中身が空の `// MARK: - Privacy` を整理 |
| M-1 / M-2 | §15 の残骸 3 件、§4.1 の `Coordinator/` パスを訂正 |

---

## 3. 中心契約テストの実装（BT-05 / BT-22 / BT-23）

未検証 7 行のうち 3 件を実装した。基準は「出荷される振る舞いの契約か」である。

| ID | 契約 |
|---|---|
| BT-05 | 非メインスレッドから呼んでも callback がメインスレッドで来る |
| BT-22 | パース失敗・引数 NULL の早期リターンも main で exactly-once |
| BT-23 | nil callback で trap しない。start / stop 境界で handler が交差しない |

**変異検査で有効性を確認した。** L-5 で「空回りする監査」を指摘された直後なので、
通ることではなく落ちることを確かめた。

| 注入した欠陥 | 落ちたテスト |
|---|---|
| 早期リターンを呼び出し元スレッドで返す | `earlyReturnsKeepTheContract`（BT-22） |
| `run()` が結果を 2 回通知する | `callbacksArriveOnMain`（BT-05） |

残る 4 件（BT-01 / BT-08 / BT-12 / CT-05）は全 endpoint を一通り叩く網羅系で、契約の中心では
ないため後続タスクへ送った。**設計 §12.4 に理由つきで記録し、`**未実装**` が通過扱いでない
ことも明記した。**

---

## 4. 検証結果

| 対象 | 宣言数（`@Test`） | 実行数（xcresult） | 失敗 |
|---|---|---|---|
| MacLibrary | **304** | **348** | 0 |
| UnityMacPlugin | **75** | **76** | 0 |

| 対象 | 結果 |
|---|---|
| 通常 `clean test` の Clipboard 警告 | **0 件** |
| CT-01 strict whole-module build | `BUILD SUCCEEDED` / 173 件 / Clipboard 由来 **0 件** |
| 設計書の機械照合 | **29 / 29 通過（SKIP 0）** |
| `git diff develop --check` | **0 件** |

```bash
xcodebuild clean test -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary     -destination 'platform=macOS'
xcodebuild clean test -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS'
xcrun xcresulttool get test-results summary --path <*.xcresult>   # 件数は stdout ではなくここから

xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin \
  -destination 'platform=macOS' \
  SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_COMPILATION_MODE=wholemodule clean build

python3 scripts/check_design_consistency.py \
  artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md

git diff develop --check
```

---

## 5. 実装レビューの収束判断

### 5.1 件数では収束しない

| ラウンド | レビュアー | high | medium | low |
|---|---|---|---|---|
| v8 | A | 2 | 4 | 1 |
| v9 | A | 1 | 1 | 2 |
| v10 | A | 1 | 1 | 1 |
| v11 | **B** | 4 | 7 | 7 |
| v12 | B | 4 | 7 | 6 |

A の 3 ラウンドは減少して見えたが、B に替えた途端に跳ね上がった。**0 件は「問題がない」では
なく「その視点では見えない」を意味しうる。**

さらに、**修正がレビュー面積を増やす**。検査を足せば検査自身が対象になり、実際に検査の
バグが 3 ラウンド連続で出た。反復で 0 に収束する構造になっていない。

### 5.2 採用した停止基準

> **出荷される振る舞いを変える指摘が 0 になったら止める。**
> 文書・ツール・テスト網羅の指摘は、記録して先へ進む。

指摘の種類が変わったことが信号である。

| ラウンド | 見つかったもの |
|---|---|
| v11 | **製品の不具合** — paste button が独自 UTI で無言に死ぬ、Unity に誤ったエラーコード |
| v12 | **文書とツール** — DoD の虚偽、ヘッダ注記、機械照合の穴 |

v12 は出荷される振る舞いを一つも変えていない。

### 5.3 現在の状態

| | |
|---|---|
| 出荷される振る舞いを変える指摘 | **0** |
| 中心契約のうち未検証のもの | **0**（BT-05 / BT-22 / BT-23 を実装） |
| 文書の虚偽の主張 | **0**（DoD の [x] を削除、未実装を明記） |
| 機械照合 | 29 / 29、既知の穴なし |
| 残件 | 網羅系テスト 4 件（設計 §12.4 に記録） |

### 5.4 手順への反映

- **レビュアーを固定しない。** 同一レビュアーが 3 ラウンド続けて high を 1 件しか出さなく
  なったら、収束ではなく視点の固着を疑う
- **検査を書いたら、壊して落ちることを確認する。** 通ることの確認では足りない
- **SKIP を FAIL と同じ重さで見る。** v13 では再現テスト自体が SKIP で空回りしていた
- **件数は xcresult から読む。** stdout の grep は並列実行で行が壊れる

---

## 6. 残作業

1. **サンプル計画 v2**: File Promise セクションと drag harness を落とす。サンプル設計レビューの
   medium 9 / low 3 も併せて反映する
2. **T-18**: サンプルアプリ実装
3. **手動確認**: MT-01〜MT-04 / MT-06 / MT-07（MT-05 は v9 で削除、MT-08 は実機 2 台、
   MT-09 は RK-22 により判定保留）
4. **網羅系 Bridge テスト 4 件**: BT-01 / BT-08 / BT-12 / CT-05
