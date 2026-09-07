# 実装結果レポート v12

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v10 の指摘 3 件（H 1 / M 1 / L 1）の反映**
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v11.md`

> v10 / v11 は修正せず保持する。各版はそれを対象としたレビューが読んだ状態のままである。

---

## 1. レビュー v10 の判定

レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implementation-feature-review-v10.md`

| ID | severity | 内容 | 本版 |
|---|---|---|---|
| **H-4** | high | 現行章に `HandleJson` サンプル、File Promise 由来 CT、存在しない IT / BT 範囲、削除済み OP-16 の DoD が残存。機械照合 26/26 が false green | 反映 |
| **M-6** | medium | `MacClipboardManager` の型 DocC が「Every operation has a native `async throws` form」と誤記 | 反映 |
| **L-4** | low | 設計書の機械照合説明が 26 検査に追随していない | 反映 |

総合: **要修正（重大）**。**3 件とも正しく、すべて反映した。**

---

## 2. H-4: 検査の 3 つの盲点

### 2.1 何が残っていたか

| 箇所 | 残骸 |
|---|---|
| §8.4.4 の JSONC サンプル | `// HandleJson (required: id)` と `{ "id": ... }` |
| §12.5 | CT-09 / CT-10 / CT-15 / CT-17（File Promise lifecycle 用語） |
| §13 T-16b | `BT-12〜BT-19`（BT-13〜16 / 18 / 19 は存在しない） |
| §15 実装完了条件 | `OP-16 が async throws`、`IT-21〜IT-53 全通過`、`BT-01〜BT-25`、`CT-01〜CT-17` |
| §2 リスク | RK-21（削除済み `NSFilePromiseProvider.delegate` の所有規約） |
| §15 設計完了条件 | `DV-01〜DV-06`（DV-04 / DV-05 は削除済み） |

### 2.2 なぜ v11 の検査が見逃したか

v11 で入れた「識別子の実在」検査は backtick 内の `\w{6,}` を見る。**残骸はそのどれにも
該当しなかった。**

| 盲点 | 実例 | なぜ掛からないか |
|---|---|---|
| ID 参照 | `OP-16` | ハイフンを含むため `\w+` に一致しない |
| 範囲表記 | `IT-21〜IT-53` | 1 トークンに見えるが、実際は存在しない 30 件を要求している |
| コードブロック | `// HandleJson` | backtick ではなく JSONC コメント |

### 2.3 追加した 3 検査

| # | 検査 | 導出元 |
|---|---|---|
| 14 | **ID 参照の実在** | 表の行が定義する ID 集合。範囲表記を展開して照合する |
| 15 | **schema サンプル** | §8.4.4 の在庫表。コードブロック内の型名と突き合わせる |
| （12 を改良） | 識別子の実在 | 複数 ID を 1 行で定義する行（`\| RK-01 / RK-02 \|`）に対応 |

再現テストで 3 件とも捕まえることを確認した。

```
IT range:           CAUGHT   missing=[('IT-21',…), ('IT-22',…), …]
HandleJson sample:  CAUGHT   not in the inventory: [('HandleJson', 1295)]
OP-16 DoD:          CAUGHT   missing=[('OP-16', 1782)]
```

### 2.4 DoD の範囲表記を生成に切り替えた

範囲を人が書くこと自体が今回の失敗の形だったため、**表の実 ID から生成**するようにした。

```
IT-01〜IT-11 / IT-20 / IT-50
BT-01〜BT-03 / BT-05〜BT-08 / BT-10〜BT-12 / BT-17 / BT-20〜BT-25
CT-01〜CT-02 / CT-04〜CT-05 / CT-07
PT-01〜PT-15
```

連続する ID だけを範囲に畳み、欠番は明示的に分割する。手で書いていた
`BT-01〜BT-25` は、実在する 18 件に対して 25 件を要求していた。

### 2.5 検査自身のバグ 2 件

新検査を作る過程で、検査側の欠陥が 2 件出た。**いずれも設計書ではなく検査が誤っていた。**

| 症状 | 原因 |
|---|---|
| `OP-01〜OP-08` が `OP-00` としても報告される | `(\d+)(?!〜)` が貪欲一致から後退し `0` を拾っていた。`(\d+)(?![\d〜])` に修正 |
| `RK-01` が「定義されていない」と報告される | `\| RK-01 / RK-02 \|` のように 1 行で複数 ID を定義する行を認識していなかった |

2 件目を直した副産物として、RK-21 の残骸が見つかった。

---

## 3. M-6: 公開 DocC の同期契約が誤り

`MacClipboardManager` の型 DocC は「Every operation has a native `async throws` form」と
書いていたが、OP-12〜OP-15 と OP-19 は common.md の即時 control / factory 例外で同期である。
**同じ DocC 内の「Immediate control operations are synchronous」と矛盾していた。**

同期 API を名指しする形に直した。

```
Reading and writing are `async throws`, and each also has a callback form for the Unity
bridge... Operations that complete immediately are synchronous and have no callback form:
accessBehavior, startObserving, stopObserving, checkForegroundChange, makePasteButton.
```

これは File Promise 削除で生じた矛盾ではなく、**以前から誤っていた記述**である。

---

## 4. L-4: 機械照合の説明

設計書 §16.1 の検査項目表を 10 → **15 行**へ更新し、冒頭の要約も「28 項目」に直した。
併せて、11〜15 が実装または文書自身から対象を導出すること、除外を章単位で限定することを
明記した。

---

## 5. 検証結果

| 対象 | 宣言数（`@Test`） | 実行数（xcresult） | 失敗 |
|---|---|---|---|
| MacLibrary | **302** | **346** | 0 |
| UnityMacPlugin | **71** | **72** | 0 |

| 対象 | 結果 |
|---|---|
| 通常 `clean test` の Clipboard 警告 | **0 件**（両ターゲット） |
| CT-01 strict whole-module build | `BUILD SUCCEEDED` / 173 件 / Clipboard 由来 **0 件** |
| 設計書の機械照合 | **28 / 28 通過** |
| `git diff develop --check` | **0 件** |

### 5.1 機械照合の推移

| 版 | 検査数 | 追加 |
|---|---|---|
| v7 | 22 | 初版 |
| v10 | 25 | エラーコード対応、実装ケースの網羅、旧件数の deny-list |
| v11 | 26 | deny-list を廃止し、識別子の実在と件数照合へ差し替え |
| **v12** | **28** | **ID 参照の実在、schema サンプルの照合** |

---

## 6. 4 ラウンドの総括

レビュー v8 〜 v10 の指摘 14 件のうち、**9 件が同じ原因**である。

> **検査が、自分の見る対象を自分で決めていた。**

| 指摘 | 検査が見ていたもの | 差し替え後 |
|---|---|---|
| v8 H-1 | エラー表の内部（重複・帯域） | `ClipboardError.swift` の `case` |
| v8 H-2 | 手書きの型名文字列 | `ClipboardJson` の宣言 |
| v9 H-3 | 見つけた 8 語の deny-list | `mac/` 全ソースの識別子集合 |
| v9 M-5 | xcodebuild の stdout | xcresult |
| v10 H-4 | backtick 内の識別子のみ | ID 参照・範囲展開・コードブロック |

**毎ラウンド、前ラウンドで作った検査の穴が次の指摘になっている。** 穴の位置は毎回違うが、
形は同じで、「人が列挙した集合」を見ていた点が共通している。

現在、設計書に対する 15 検査のうち **5 検査が実装または文書自身から対象を導出する**。
残る 10 は構造的な不変条件（件数一致、ID 昇順、表の列数、見出し順）で、これらは
対象の列挙を必要としない。

### 6.1 残る手動確認 1 件

v8 M-1（production の呼び出し元が 0 件の公開 API）は機械化していない。ライブラリは
利用者のために API を公開するため、呼び出し元 0 件を欠陥と判定できない。

---

## 7. 残作業

1. **サンプル計画 v2**: File Promise セクションと drag harness を落とす。サンプル設計レビューの
   medium 9 / low 3 も併せて反映する
2. **T-18**: サンプルアプリ実装
3. **手動確認**: MT-01〜MT-04 / MT-06 / MT-07
4. **再レビュー**: 本版を対象に実装レビューを実施する
