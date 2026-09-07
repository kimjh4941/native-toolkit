# 実装結果レポート v11

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v9 の指摘 4 件（H 1 / M 1 / L 2）の反映**
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v10.md`

> **v10 は修正せず保持する。** レビュー v9 が読んだ状態のままにしてある。件数の誤りも
> そのまま残っており、本版が訂正版である。

---

## 1. レビュー v9 の判定

レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implementation-feature-review-v9.md`

| ID | severity | v9 の判定 | 本版 |
|---|---|---|---|
| H-1 / H-2（v8） | high | 解消 | - |
| M-1 / M-4 / L-1（v8） | medium / low | 解消 | - |
| **H-3** | high | 新規 | 反映 |
| **M-5** | medium | 新規 | 反映 |
| **L-2 / L-3** | low | 新規 | 反映 |

総合: **要修正（重大）**。**指摘 4 件はすべて正しく、すべて反映した。**

---

## 2. H-3: 設計書の現行契約に削除済み File Promise が残っていた

### 2.1 何が残っていたか

| 章 | 残骸 |
|---|---|
| §5 common.md 適合表 | 存在しない `FilePromiseHandle` / `ReceiveFilePromisesUseCase` を適合根拠にしていた |
| §6.6 Bridge 方針 | 削除済み `releaseFilePromise` を同期 control の例に挙げていた |
| §12.1 | `ClipboardError` を 25 ケース、`ClipboardLimits` 境界に存在しない `quiet >= overall` |
| §12.2 | IT-14 / 16 / 17 / 18 / 21 / 22 / 23 / 30 / 39 / 51 / 52（削除済み経路） |
| §12.4 | 「資源を生成しない 16 endpoint」、BT-09 / 15 / 16 / 19 |
| §12.5 | CT-12（`scheduledGeneration`） |
| §13 | T-16a のレビュー条件に staging / `sourcePath` |
| §14.1 | DV-04 / DV-05（File Promise lifecycle / timeout） |
| §15 | `OP-16 async throws` を実装済み DoD として保持 |
| 用語 | **JSON 実体を 16 型のまま**（H-2 で §8.4.4 だけ直し、冒頭を直し忘れていた） |

最後の 1 件は、本版で入れた新検査が見つけた。

### 2.2 なぜ v10 の掃除で漏れたか

**削除対象を語で探していたから。** v9 の作業では `FilePromise` / `Receipt` / `staging` などの
キーワードで行を落としたが、生き残った行はこう書かれていた。

```
| IT-21 | 同一 provider に 2 件の書き出し要求が重なっても解放されない（`inFlightCount`） |
| IT-52 | 1 件も到達しない場合は `.overallTimeout` で終端する |
```

**「file promise」という語をどこにも含んでいない。** 語で探す限り永遠に見つからない。

### 2.3 検査方式の差し替え

v10 で追加した `superseded counts removed` は、**そのとき見つかった 8 個の文字列を deny-list に
しただけ**だった。レビューの指摘どおり、これは v10 自身が §5 で書いた教訓
「検査対象を実装から導出する」に違反している。同じコミットの中で違反していた。

deny-list を捨て、実装から導出する 2 検査に差し替えた。

| 検査 | 導出元 | 何を捕まえるか |
|---|---|---|
| `named symbols exist in the implementation` | `mac/` 配下の全 `.swift` / `.h` / `.m` | 現行章が backtick で名指す識別子がコードに実在しない |
| `quoted counts match the declarations` | 設計冒頭の宣言値 | 現行章の件数が宣言と食い違う |

前者が本質である。`inFlightCount` も `overallTimeout` も実装から消えているため、
語ではなく**存在**で判定できる。

**除外は章単位で限定した**（レビューの要求どおり）。

- 変更履歴（`## 0.x`）: 過去の版が何をしたかの記録
- §2.1 / §2.2: 対象外とした platform API の一覧
- §7.12: 作らなかった理由の実測記録
- 「実装しない」「対象外」等の不在表明を含む行
- `NS*` / `UT*` / `CF*` 等のプラットフォーム記号と全大文字のビルド設定

### 2.4 再現テストで検証済み

削除済み行を戻すと 3 検査が落ちることを確認した。

```
FAIL IT ids ascending: drops=[(50, 21)]
FAIL named symbols exist in the implementation: hits=[(1588,'inFlightCount'), (1589,'overallTimeout')]
FAIL quoted counts match the declarations: hits=[(1615, '19 endpoint', 15)]
```

---

## 3. M-5: 実行数は 71 ではなく 72

`namedScopeRequiresName(kind:)` が 2 引数へ展開されるため、UnityMacPlugin の展開後実行数は
72 である。v10 の 71 は誤りだった。

**原因は数え方である。** `xcodebuild` の stdout を `grep -c "' passed on"` で数えていたが、
並列実行でログ行が壊れて 1 件取りこぼしていた。本セッション中に実際の行破損を観測している。

```
Test case 'UnityMacNotificationJsonParserTests/parseContentFailsOnInvalidJso2026-09-02 ...
```

**以後、テスト件数は xcresult から読む。**

```bash
xcrun xcresulttool get test-results summary --path <*.xcresult>
```

件数の誤りは v9（ラベル誤り）、v10（取りこぼし）と 2 版続いた。測定元を stdout から
xcresult へ変えることで、数え方そのものを外した。

---

## 4. L-2 / L-3

- **L-2**: `MockClipboardTypeIdentifierValidating.invalidFileTypeIdentifiers` を削除した。
  M-1 で `isValidFileType` を消した際の取り残しで、参照は 0 件だった
- **L-3**: 未コミット状態では `git diff develop...HEAD --check` が commit 側を見るため
  再現しない。working tree を含む `git diff develop --check` を記載する

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
| 設計書の機械照合 | **26 / 26 通過** |
| `git diff develop --check` | **0 件** |

再現コマンド:

```bash
xcodebuild clean test -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary     -destination 'platform=macOS'
xcodebuild clean test -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS'

# 件数は stdout ではなく xcresult から読む
xcrun xcresulttool get test-results summary --path <*.xcresult>

xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin \
  -destination 'platform=macOS' \
  SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_COMPILATION_MODE=wholemodule clean build

python3 scripts/check_design_consistency.py \
  artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md

git diff develop --check
```

### 5.1 機械照合の推移

| 版 | 検査数 | 追加した検査 |
|---|---|---|
| v7 | 22 | 初版 |
| v10 | 25 | エラーコード対応（実装由来）、実装ケースの網羅、旧件数の deny-list |
| **v11** | **26** | deny-list を廃止し、**識別子の実在検査**と**宣言値との件数照合**へ差し替え |

---

## 6. 今回の総括

レビュー v8 と v9 で指摘された 11 件のうち、**7 件が「検査が自分の対象を自分で決めていた」
ことに起因する**。

| 指摘 | 検査が見ていたもの | 差し替え後 |
|---|---|---|
| v8 H-1 | エラー表の内部（重複・帯域） | `ClipboardError.swift` の `case` |
| v8 H-2 | 手書きの型名文字列 | `ClipboardJson` の宣言 |
| v8 M-1 | `FilePromise` を含む名前 | （未機械化。§6.1） |
| v9 H-3 | 見つけた 8 語の deny-list | `mac/` 全ソースの識別子集合 |
| v9 M-5 | xcodebuild の stdout | xcresult |

いずれも「観測対象を人が列挙する」形から「実装から導出する」形へ変えた。

### 6.1 機械化していない 1 件

v8 M-1（production の呼び出し元が 0 件の公開 API）は検査を書けるが、**意図的に未使用の
公開 API と区別できない**。ライブラリは利用者のために API を公開するのであって、自分で
呼ぶために公開するわけではない。誤検出が多くなるため手動確認に留めている。

---

## 7. 残作業

1. **サンプル計画 v2**: File Promise セクションと drag harness を落とす。サンプル設計レビューの
   medium 9 / low 3 も併せて反映する
2. **T-18**: サンプルアプリ実装
3. **手動確認**: MT-01〜MT-04 / MT-06 / MT-07
4. **再レビュー**: 本版を対象に実装レビューを実施する
