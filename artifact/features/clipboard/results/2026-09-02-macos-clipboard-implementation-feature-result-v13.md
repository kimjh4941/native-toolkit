# 実装結果レポート v13

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v11 の指摘 18 件（H 4 / M 7 / L 7）の反映**
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v12.md`

> v10 / v11 / v12 は修正せず保持する。各版はそれを対象としたレビューが読んだ状態のままである。

---

## 1. レビュー v11 の位置づけ

レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implementation-feature-review-v11.md`

**このレビューだけレビュアーが違う。** v1〜v10 は同一のレビューエージェントが担当し、
v11 は別のエージェントが独立して実施した。

結果は **high 4 / medium 7 / low 7 = 18 件**。直前の v10 は 3 件だった。

**10 ラウンドで見つからなかったものが、レビュアーを替えた 1 ラウンドで 18 件出た。**
特に「検査自身を検査する」視点は、私にも従来のレビュアーにも無かった。私が書いた検査を
私が説明し、それを同じ相手が読む形が続いていたためである。

---

## 2. H-1: 私の検査が、削除を主張するテストによって無力化されていた

### 2.1 何が起きていたか

v11 で入れた `check_live_symbols` は「設計が名指す識別子が `mac/` のソースに実在するか」を
見る。この corpus は**全ソースの単純連結で、テストコードを含んでいた**。

BT-11 に私が書いた「消えたことを主張する」アサーションはこうである。

```swift
for gone in ["FilePromiseRequestJson", "PolicyJson", "ReceiptEventJson", "HandleJson"] {
    #expect(!all.contains(gone), "\(gone) is still declared")
}
```

**削除済みの型名が文字列として corpus に入る。** 結果、それらを設計の現行章へ書き戻しても
検査は通った。レビュアーが実証し、こちらでも再現した。

> **削除を検出するための検査が、削除を主張するテストによって無効化されていた。**

### 2.2 修正

テストソースからは**文字列リテラルだけ**を落とす。

```python
if TEST_DIR.search(str(f)):
    body = STRING_LITERAL.sub('""', body)
```

削除を主張するテストは型名を**文字列**で書き、生きている型は**コード**として参照する。
この境界で正しく分かれる。テストごと除外する案も試したが、設計が正当に言及する
`MockClipboardRepository` などを誤検出したため採らなかった。

### 2.3 私の再現テストが空回りしていた

修正の検証中に、**これまでの再現テストがこの検査を測っていなかった**ことが分かった。

一時ファイルを `/tmp/xxxx/r.md` に書いていたが、`SOURCE_ROOTS` は文書パスに機能名が
含まれることを前提にキーを引く。`clipboard` を含まないため **SKIP** になっていた。
`FAIL` だけを grep していたので、SKIP は目に入らなかった。

v11 / v12 で「再現テストで確認済み」と書いた分のうち、**この検査に関する主張は成立して
いなかった**。パスを `clipboard-regression.md` に直して測り直し、5 パターンすべてで
CAUGHT を確認した。

| 再現パターン | 結果 |
|---|---|
| 削除済み JSON 型を散文に戻す | CAUGHT（`named symbols`） |
| 存在しない IT 範囲を DoD に書く | CAUGHT（`referenced IDs`） |
| JSONC サンプルに `HandleJson` を戻す | CAUGHT（`schema samples`） |
| 削除済み OP-16 を DoD に書く | CAUGHT（`referenced IDs`） |
| 削除済みシンボル名を散文に書く | CAUGHT（`named symbols`） |

**SKIP は OK ではない。** スクリプト冒頭にそう書いておきながら、自分の検証で見落とした。

---

## 3. H-2 / H-3 / H-4: 公開契約の不具合

### H-2: `makePasteButton` が独自 UTI を無言で捨てていた

`acceptedTypes.compactMap { UTType($0) }`。設計 §8.2 は「`UTType` で検証すると独自
フォーマットを不当に拒否する」と明記し、7 行上の validator はその方針に従っている。
その直後に同じ識別子を黙って落としていた。

`com.mycompany.myformat` を渡すと throw もログもなく、**何も受け付けないボタン**が返る。

`PasteButton` は `UTType` からしか作れないため成立はさせられない。**明示的に throw する**
形にし、DocC に「pasteboard より狭い集合しか受け付けない」ことを書いた。
**登録より前に検証する**ので、失敗時に loader が残らない。

`makePasteButton` を通るテストは 0 件だった。PT-16 を 2 件追加した。

### H-3: 必須引数 NULL が 1301 を返していた

設計 §8.4.1 は「NULL は 1302、パース失敗は 1301」と定める。実装は `parseScope(nil)` の
失敗を一律 1301 で返していた。**何も送っていない呼び出し元に「あなたの JSON が不正」と
返していた**ことになる。

`argumentError(_:)` で分類し、18 箇所を通した。BT-26 を追加。

### H-4: ヘッダの wire format 誤記

`UnityMacClipboardManagerBridge.h` が「Returns ScopeJson」。実装は `ScopeResultJson`
（`{"scope": {...}}`）。**私は v12 で設計書の prototype コメントだけ直し、ヘッダを
取り残していた。**

---

## 4. medium 7 件

| ID | 内容 | 対応 |
|---|---|---|
| M-1 | 設計の現行章に取り残し 7 箇所（RK-20 の緩和策が File Promise を指す、§16.2 参照など） | 削除・訂正 |
| M-2 | §6.1 のファイル構成に**実在しない 14 ファイル** | **実ツリーからの生成に切り替え** |
| M-3 | `ClipboardRepository` の public DocC に "stale detection" | 削除。v12 は UseCase 側だけ直していた |
| M-4 | Unity facade の public 関数 **14 本に DocC なし**（mac.md 違反、DoD は [x]） | DocC 追加。**DocC テストが `MacLibrary/Clipboard` しか走査していなかった**ため両ツリーへ拡大 |
| M-5 | Manager が Data 層の具象 `ClipboardTypeIdentifierValidator()` を直接生成 | 注入に変更 |
| M-6 | 「error code bands disjoint」が**構造上決して失敗しない** | 所有者ごとの帯に収まるかの検査へ。1301→1501 に改変して FAIL を確認 |
| M-7 | `ClipboardChangeMonitor` が observer を `deinit` で解除せず、生成ごとに 2 件蓄積 | lock 付きボックスで保持し nonisolated deinit から解除 |

M-2 と M-4 は同型である。**手書きの一覧と、走査範囲を人が決めた検査**が、どちらも実装から
ずれていた。M-2 は生成に切り替え、M-4 は走査範囲を両ツリーへ広げた。

---

## 5. low 7 件

| ID | 内容 |
|---|---|
| L-1 | §12.2 の IT 表が削除跡の空行で 3 つに分断されていた |
| L-2 | 変更監視が設計の `Timer` ではなく `Task`（実装が正。設計を追随済み） |
| L-3 | `attachCoordinator` の呼び出し元が 0 件 → 削除 |
| L-4 | `Log.d` 先頭 1 行ルールの漏れ 5 箇所 |
| L-5 | **ブロック捕捉監査が本文を一切参照していなかった** |
| L-6 | encode 失敗が「成功 + json = NULL」として通知されていた → 1599 |
| L-7 | 削除跡の空行 |

### L-5 の詳細

```swift
for line in implementation.split(separator: "\n") where line.contains("^(") {
    #expect(callbackNames.contains { implementation.contains("\($0)(") })
    _ = line   // 未使用警告の抑止
}
```

**`#expect` が `line` を一切参照していない。** ファイル全体に `callback(` があれば全周回で
真になる。`_ = line` はコンパイラを黙らせるためのもので、監査は実際には行われていなかった。

ブロック本文を波括弧の対応で切り出し、1 つずつ解析する形に書き直した。

**書き直した監査は、書いた直後に実際に落ちた。** 原因はコメント内の
「isolation domains (…)」を関数呼び出しとして拾った誤検出で、コメント除去を足して解消した。
**検査を書くたびに検査側のバグが出るのは 3 回連続である。**

---

## 6. 検証結果

| 対象 | 宣言数（`@Test`） | 実行数（xcresult） | 失敗 |
|---|---|---|---|
| MacLibrary | **304** | **348** | 0 |
| UnityMacPlugin | **72** | **73** | 0 |

| 対象 | 結果 |
|---|---|
| 通常 `clean test` の Clipboard 警告 | **0 件** |
| CT-01 strict whole-module build | `BUILD SUCCEEDED` / 173 件 / Clipboard 由来 **0 件** |
| 設計書の機械照合 | **28 / 28 通過（SKIP 0）** |
| `git diff develop --check` | **0 件** |

v12 からの増加（+2 / +1 宣言）は PT-16 二件と BT-26 一件の追加による。

---

## 7. 総括: レビュアーを替えた効果

| ラウンド | 担当 | high | medium | low |
|---|---|---|---|---|
| v8 | A | 2 | 4 | 1 |
| v9 | A | 1 | 1 | 2 |
| v10 | A | 1 | 1 | 1 |
| **v11** | **B** | **4** | **7** | **7** |

A が 3 ラウンドで見つけた 13 件に対し、B は 1 ラウンドで 18 件。**収束したように見えていたのは、
同じ視点で見続けていたためだった。**

B が出した指摘のうち、A が原理的に出しにくかったものが 2 つある。

1. **検査自身の検証**（H-1 / M-6 / L-5）。私が書いた検査を私が説明し、同じ相手が読む形が
   10 ラウンド続いていた。「この検査は本当に落ちるのか」を独立に試す動機が働かなかった
2. **DoD が [x] なのに検証が無い項目**（M-4 / H-3）。結果レポートの主張を出発点にすると、
   主張そのものは疑いにくい

### 7.1 手順への反映

- **レビュアーを固定しない。** 同一レビュアーが 3 ラウンド続けて high を 1 件しか出さなく
  なったら、収束ではなく視点の固着を疑う
- **検査を書いたら、必ず落ちることを確認する。** ただし §2.3 のとおり、確認手順自体が
  空回りしうる。SKIP を FAIL と同じ重さで見る

---

## 8. 残作業

1. **サンプル計画 v2**: File Promise セクションと drag harness を落とす。サンプル設計レビューの
   medium 9 / low 3 も併せて反映する
2. **T-18**: サンプルアプリ実装
3. **手動確認**: MT-01〜MT-04 / MT-06 / MT-07
4. **再レビュー**: 本版を対象に実装レビューを実施する
