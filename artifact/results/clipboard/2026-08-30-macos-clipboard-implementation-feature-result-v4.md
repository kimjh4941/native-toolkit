# 実装結果レポート v4

## 基本情報

- 日付: 2026-08-30
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v2 の指摘 3 件（M-4 / M-5 / M-6）の反映**
- 前版: `2026-08-30-macos-clipboard-implementation-feature-result-v3.md`

> 本版は v3 の §2（レビュー反映）を継ぐ第 2 ラウンドの記録である。
> v3 の他の節（実装サマリー、追加判断、DoD）は引き続き有効。

---

## 1. レビュー v2 の判定

レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v2.md`
実施者: Codex（gpt-5.6-sol、前スレッド継続）

- 前回 7 件: **解消 6 件 / 部分解消 1 件**（H-1）
- 新規 high: **0 件**、medium 3 件
- 総合判定: マージ保留（medium 修正後に再確認）

---

## 2. 指摘 3 件の反映

| ID | 指摘 | 対応 |
|---|---|---|
| M-4 | `Progress` の install と cancel が競合すると provider 処理を cancel できない | `ProgressBox` を「キャンセル済みを覚える箱」に変更。`install(_:)` は cancel 済みなら即 cancel し、`cancel()` は保存済みと以後の両方に効く |
| M-5 | 追加テストが修正した本番境界を通らない | 実 `NSItemProvider` を使う `ItemProviderSourceTests` を新設。BT-24 を facade 呼び出しへ、BT-25 を新規追加、late-cancel の discard が root であることを assert |
| M-6 | 設計書 §7.11 に旧 `withTaskGroup` 指示が残り実装と矛盾 | 旧記述を削除して非構造化 task + 独立 deadline に統一。T-14 / DoD のテスト範囲を更新。§8.4.5 の重複手順番号を連番へ |

### 2.1 M-4 の性質

`LoadGate` は状態機械にしたが `ProgressBox` は単純な値の箱のままだった、という**非対称な作り**が原因である。

provider は**ロード開始後**に `Progress` を返すため、箱が空のうちにキャンセルが到達し得る。
その場合 `onCancel` は `nil` を読んで何もせず、後から入った `Progress` は誰も cancel しない。
`LoadGate` が continuation を守るため呼び出し側は正常に戻り、**provider だけが読み続ける**。

### 2.2 M-5 の性質

v3 §2.1 で「テストが実装と同じ思い込みを共有していた」と記録したにもかかわらず、
**修正後のテストで同じ構造の穴を作っていた**。

PT-12 / PT-13 は `HangingSource` を注入するため loader 本体の deadline は通るが、
H-1 で同時に修正した `ItemProviderSource` / `ProgressBox` / `LoadGate` を一度も実行しない。
そのため M-4 を検出できなかった。

BT-25 は設計書のテスト表に追加しただけで、**テスト実体を作り忘れていた**。

### 2.3 M-6 の性質

設計還元の際、新しい記述を**追加**しただけで矛盾する旧記述を**削除**していなかった。
`scripts/check_design_consistency.py` は 22 検査を通すが、**意味上の矛盾は検査対象外**である。
機械照合が通ることと、記述が整合していることは別である。

---

## 3. テスト追加

| ID | 内容 |
|---|---|
| PT-14 | 実 `NSItemProvider` 経由で adapter がロードする（fake 注入では通らない本番境界） |
| PT-15 | `Progress` の install 前後どちらでキャンセルされても `Progress.cancel()` が呼ばれる |
| BT-24 | facade を実際に呼び `errorCode == 1301` を確認。absent が 1301 にならないことも |
| BT-25 | C 層の全 endpoint に生の `contentJson` / `scopeJson` が無い。helper の使用も検査 |
| （既存強化） | late-cancel の discard 対象が staging root であることを assert |

M-4 の再現テストは**修正前に失敗することを確認してから**修正した。

---

## 4. 検証結果

| 対象 | 件数 | 失敗 |
|---|---|---|
| MacLibrary | 417 | 0 |
| UnityMacPlugin | 78 | 0 |

- MacLibrary はタイマ・並行系を含むため 2 回連続実行で確認
- strict concurrency 診断: unique **173 件 / Clipboard 由来 0 件**（増減なし）
- 設計書の機械照合: **22 検査すべて通過**

レビュー v1 時点（413 / 73）から **+9 件**。

---

## 5. 残作業

1. **再レビュー**: 本版を対象に実装レビュー v3 を実施する
2. **T-18**: サンプルアプリ（`design-sample-app` で設計）
3. **手動確認**: MT-01〜MT-08 を実機で実施
4. `MIGRATION.md` の `swift6-migration` は別トピックで範囲外
