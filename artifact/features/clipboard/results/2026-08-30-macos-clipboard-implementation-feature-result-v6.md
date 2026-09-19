# 実装結果レポート v6

## 基本情報

- 日付: 2026-08-30
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v4 の指摘 3 件（M-7 再修正 / M-8 / L-2）の反映**
- 前版: `2026-08-30-macos-clipboard-implementation-feature-result-v5.md`

> 本版は第 4 ラウンドの記録である。v3 の実装サマリーは引き続き有効。

---

## 1. レビュー v4 の判定

レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v4.md`

- M-7: **未解消**（`optionsJson` の平文ログと監査漏れ）
- M-8: 新規 medium（CT-17 の追跡・テスト欠落）
- L-2: 新規 low（strict concurrency 実績の DoD 反映漏れ）
- 総合判定: **マージ不可**

---

## 2. 指摘 3 件の反映

### M-7 再修正: 監査の対象集合を signature 由来にした

**なぜ前回直らなかったか**

v5 で「行ベースから引数ベースへ」構造を直したが、**対象集合を手書きの辞書
`redactionHelpers` で持っていた**。そこに `optionsJson` が無かったため、
`clipboardCopy` が `optionsJson` を `%s` で平文出力していても検出できなかった。

指摘は「全 endpoint の全 payload を検査しているか」だったが、endpoint 側だけを網羅し
**引数側を網羅していなかった**。監査が自分の列挙より広くなれない、という性質が残っていた。

**対応**

- 監査対象を **signature から `const char*` 引数を機械抽出**する形へ変更した。
  引数が増えても辞書の更新は不要で、未分類の引数も自動的に対象に入る
- helper は引数名から導出する（`scope` を含めば `NTScope`、それ以外は `NTLen`）
- 「宣言された `const char*` パラメータが 28 件」であることも検査に加えた。
  パラメータが増えて監査から漏れれば落ちる

**新しい監査が実装の平文出力を 2 件検出した**

| endpoint | 引数 | 状態 |
|---|---|---|
| `clipboardCopy` | `optionsJson` | `%s` で平文（レビューの指摘どおり） |
| `clipboardReadData` | `utType` | `%s` で平文（**レビューでも挙がっていなかった**） |

`utType` は監査対象を機械化した副産物として出てきたものである。

### M-8: CT-17 の実装とタスク追跡

設計 §12.5 に定義がありながら、テスト実体も T-13 / §15 の追跡も欠けていた。

- `GatedRepository` を用意し、`startReceivingFilePromises` にフックを刺して
  **予約直後・登録中・登録直後**の 3 時点を決定的に作れるようにした
- 4 件目として「どの時点でキャンセルしても、予約済み handle が cancel され
  `registeredReceiptCount == 0` になる」ことを検証する
- T-13 の完了条件を CT-13〜**CT-17** へ、§15 を CT-01〜**CT-17** へ更新

### L-2 と DoD の追随

strict concurrency の実績を §15 へ反映した。あわせて**実装で確認できる DoD 項目 6 件**を
実測してから完了へ更新した。

| 項目 | 確認方法 |
|---|---|
| 案 C（全 handler に `@Sendable`） | facade の全 public func を機械監査。欠落 0 |
| `@discardableResult` の配置 | `removePasteboard` に付いていないことを機械確認 |
| OP-16 の `async throws` と MainActor 外コピー | 実装確認 |
| `FilePromiseLifecycleState` の nonisolated 性 | 実装確認 |
| Unity Bridge に Delegate 実装が無い | `grep` で 0 件 |
| system delegate の強参照が coordinator のみ | 参照元が `ClipboardSystemCoordinator` のみ |

**残る未完了は 2 件のみ**である。

```
- [ ] MacLibraryExample が MacLibrary のみに依存して全公開 OP を実行できる   ← T-18
- [ ] MT-01〜MT-07 を macOS 15.x で実施した                                  ← 実機確認
```

---

## 3. 検証結果

| 対象 | 件数 | 失敗 |
|---|---|---|
| MacLibrary | 421 | 0 |
| UnityMacPlugin | 79 | 0 |

- MacLibrary はタイマ・並行系を含むため 2 回連続実行で確認
- strict concurrency 診断: unique **173 件 / Clipboard 由来 0 件**（増減なし）
- 設計書の機械照合: **22 検査すべて通過**

---

## 4. 4 ラウンドの推移

| ラウンド | high | medium | low | 判定 |
|---|---|---|---|---|
| v1 | 4 | 3 | 0 | 要修正（重大） |
| v2 | 0 | 3 | 0 | マージ保留 |
| v3 | 0 | 1 | 1 | 要修正（軽微） |
| v4 | 0 | 2 | 1 | マージ不可 |

production code の不具合は v1 で出尽くしている。v2 以降の指摘はすべて
**検査する側の不備**であった。

- v2: fake を注入したテストが本番境界を通らない
- v3: 「全 endpoint を検査する」と名乗る検査が一部しか見ていない
- v4: 検査の対象集合が手書きで、そこに漏れがある

同じ性質の指摘が 3 回続いた。いずれも**検査が自分の列挙より広くなれない**という形をしている。
今回の修正は対象集合を signature から導出することで、この形自体を断つことを狙っている。

---

## 5. 残作業

1. **再レビュー**: 本版を対象に実装レビュー v5 を実施する
2. **T-18**: サンプルアプリ（`design-sample-app` で設計）
3. **手動確認**: MT-01〜MT-08 を実機で実施
4. `MIGRATION.md` の `swift6-migration` は別トピックで範囲外
