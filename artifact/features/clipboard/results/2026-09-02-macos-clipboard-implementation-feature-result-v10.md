# 実装結果レポート v10

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v8 の指摘 7 件（H 2 / M 4 / L 1）の反映**
- 前版: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v9.md`

---

## 1. レビュー v8 の判定

レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implementation-feature-review-v8.md`

- 総合: **要修正（重大）**。high 2 / medium 4 / low 1
- File Promise 実行経路の削除、coordinator の縮小、エラーコードの欠番方針（実装側）は妥当と判定された
- **指摘 7 件はすべて正しく、すべて反映した**

---

## 2. high 2 件

### H-1: 設計書のエラーコード表が実装と全面的にずれていた

**私が v9 の作業中に入れたバグである。** ドメインエラー表の連番を詰めるために書いた正規表現が
広すぎ、§11 のエラーコード表まで巻き込んで**全 20 行を一律 5 ずつ下げていた**。

```
設計 v9（誤）  emptyContent 1496 … detectionFailed 1510 … cancelled 1519 … unknown 1594
実装（正）     emptyContent 1501 … detectionFailed 1515 … cancelled 1524 … unknown 1599
```

実装は正しく、設計書だけが壊れていた。Bridge 利用者が設計書を正として実装すると、
全ドメインエラーを誤解釈する。

**実装を出典として §11 を再生成した**（20 行すべて訂正）。

**なぜ 22 検査を素通りしたか**: 既存の検査は「コードの重複がないこと」と「帯域が交差しない
こと」だけを見ていた。**一律シフトはそのどちらも壊さない。** 表の内部だけで整合していたため、
実装と比べるまで矛盾が現れなかった。

**対策**: 機械照合に **`ClipboardError.swift` から `case .x: return NNNN` を読み、
設計書の表と 1 件ずつ突き合わせる検査**を追加した。併せて「実装にあるケースが表から
漏れていないこと」も検査する。

破損した表を再現して新検査にかけ、FAIL することを確認済み。

```
FAIL error codes match the implementation: documented != implemented for
  [('appendRejected', 1505, 1510), ('cancelled', 1519, 1524), ...]
```

### H-2: JSON schema が設計 16 型 / 実装 18 型 / テスト 20 型に分裂していた

3 つの原因が重なっていた。

| | 内容 | 対応 |
|---|---|---|
| 死んだコード | `HandleJson` / `parseHandleId` / `encodeHandle` は File Promise の handle 専用で、**production の呼び出し元が 0 件**だった | 削除 |
| 設計の欠落 | `AccessBehaviorJson` と `ScopeResultJson` が inventory になかった。`createPasteboard` は `ScopeJson` 直返しではなく `{"scope": ...}` を返す | 設計へ追記し、prototype のコメントも訂正 |
| テストの false green | BT-11 が**手書きの型名文字列を数えていた**。削除済みの `FilePromiseRequestJson` などが文字列として残っていたため、実装と無関係に 20 件で成功していた | 実型を読む検査へ書き換え |

**確定した wire format は 17 型**（入力 4 / 共用 3 / 出力 9 / イベント 1）。

BT-11 は `ClipboardJson` の宣言そのものを読み、MARK 見出しの件数と実際の宣言を突き合わせる。
削除済み 4 型が再出現しないことも明示的に検査する。**BT-25（Bridge ログ監査）と同じ、
「監査対象を signature から導出する」方式**である。

---

## 3. medium 4 件

### M-1: File Promise 専用の公開 Port API が残っていた

`ClipboardTypeIdentifierValidating.isValidFileType` は promised file の型判定専用で、
production の呼び出し元は 0 件だった。**名前に `FilePromise` を含まないため、
単純な残存検索を通り抜けていた。**

Port requirement、Data 実装、Mock、専用テスト 3 件をまとめて削除した。

### M-2: 設計書の現行章に削除済み契約が残っていた

§12.1 の UseCase テスト 2 行、§12.4 の BT 件数（19 endpoint / 20 型）、T-06b の完了条件、
§15 の DoD、§8.4.5 の facade 規約を訂正した。

**機械照合が検出できなかった点も指摘どおり。** 「後の版が破棄した件数が現行章に残っていないか」
を検査する `superseded counts removed` を追加した。変更履歴（`## 0.x`）は対象外とする。

### M-3: 実装結果 v9 のテスト件数のラベルが誤り

v9 は 357 / 74 を「宣言」と書いたが、実際には**展開後の実行数**だった。v8 で決めた
「宣言数 / 展開後実行数」の両方を書く規約を、次の版で守れていなかった。

本版の実測値は §4 のとおり。削除件数も同じ基準同士で計算し直した。

### M-4: 削除済み契約を説明する production DocC が残っていた

| ファイル | 修正 |
|---|---|
| `BridgeError.swift` | NULL callback の資源例から file promise / receive session を削除。該当は unique pasteboard のみ |
| `GetChangeCountUseCase.swift` | 用途から stale check を削除。現在の呼び出し元は change monitor だけ |
| `UnityMacClipboardManager.swift` | section MARK から `file promises` を削除 |
| `UnityMacClipboardManagerBridge.h` | create endpoint の戻り値を「handle」→「scope」に訂正 |

---

## 4. low 1 件と検証結果

**L-1**: `UnityMacClipboardManagerBridge.m` 末尾の余分な空行を削除した。

| 対象 | 宣言数（`@Test`） | 実行数（展開後） | 失敗 |
|---|---|---|---|
| MacLibrary | **302** | **346** | 0 |
| UnityMacPlugin | **71** | **71** | 0 |

| 対象 | 結果 |
|---|---|
| 通常 `clean test` の Clipboard 警告 | **0 件**（両ターゲット） |
| CT-01 strict whole-module build | `BUILD SUCCEEDED` / Clipboard 由来 **0 件** |
| 設計書の機械照合 | **25 / 25 通過**（v9 の 22 + 本版で追加した 3） |
| `git diff develop...HEAD --check` | 0 件 |

### 4.1 v8 からのテスト件数推移

| | v8 | v9（レビュー時） | v10 |
|---|---|---|---|
| MacLibrary 宣言 | 437 | 305 | **302** |
| MacLibrary 実行 | 497 | 357 | **346** |
| UnityMacPlugin 宣言 | 80 | 73 | **71** |
| UnityMacPlugin 実行 | 81 | 74 | **71** |

v9 → v10 の減少は M-1（validator の型判定テスト 3 件）と H-2（`HandleJson` の
round-trip テスト）の削除による。いずれも削除済み契約の検査だった。

---

## 5. 今回の教訓

**3 件とも「検査が自分の対象を自分で決めていた」ことが原因である。**

| 指摘 | 検査が見ていたもの | 実装との接点 |
|---|---|---|
| H-1 | 表の内部（重複・帯域） | なし。一律シフトを見逃す |
| H-2 | 手書きの型名文字列 | なし。削除しても通る |
| M-1 | `FilePromise` を含む名前 | 名前に依存。`isValidFileType` を見逃す |

対策も同じ形に揃えた。**検査対象を実装から導出する。**

- エラーコード → `ClipboardError.swift` の `case` を読む
- JSON 型 → `ClipboardJson` の宣言を読む
- Bridge ログ → C の signature を読む（BT-25。v6 で導入済み）

M-1 だけは機械化していない。「production の呼び出し元が 0 件の public API」を検出する検査は
書けるが、意図的に未使用の公開 API と区別できないため、今回は手動確認に留めた。

---

## 6. 残作業

1. **サンプル計画 v2**: File Promise セクションと drag harness を落とす。サンプル設計レビューの
   medium 9 / low 3 も併せて反映する
2. **T-18**: サンプルアプリ実装
3. **手動確認**: MT-01〜MT-04 / MT-06 / MT-07
4. **再レビュー**: 本版を対象に実装レビューを実施する
