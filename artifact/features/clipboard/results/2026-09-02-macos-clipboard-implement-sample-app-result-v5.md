# サンプルアプリ実装結果 v5

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/`
- 計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v5.md`（§7.1 / §7.4 / §8.1 を更新）
- 対応タスク: T-18（機能設計 §13）
- 前版: `artifact/results/clipboard/2026-09-02-macos-clipboard-implement-sample-app-result-v4.md`
- 反映したレビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-implement-sample-app-review-v4.md`

> レビュー v4 の 13 件（A 1 / B 6 / C 6）をすべて反映した。**併せて、4 ラウンド続いた
> 「検査が自分で対象を決める」形に対して、個別修正ではなく規則を
> `agent-rules/coding-rules/common.md` に追加した**（レビュー v4 のサーキットブレーカー指摘）。

---

## 1. A 区分（1 件）

### H-01: `CreateNamedPasteboard` の再押下が内容を黙って破棄していた

**前ラウンドの修正を、指摘の範囲を超えて適用していた。** v3 H-01 が問題にしたのは unique の
孤立だが、`releasePrevious` を named にも効かせたため、次の経路で内容が消えていた。

```
CreateNamedPasteboard → CopyText → CreateNamedPasteboard → Read
  修正前: items=1   v4: items=0   v5: items=1
```

named は固定名で常に再アドレスできるので孤立しない。解放する理由がなかった。
`createPasteboard` の doc が言う「Creates **or fetches**」の後半を、サンプルから実演できなく
していた。**`releasePrevious` を `.unique` 要求に限定した。**

併せて L-01（解放失敗で handle だけ先に失われる）も直した。`createdUnique` のクリアを
`removePasteboard` の**成功後**に移し、`activeScope` の退避だけを前に置く。これで
「作成が失敗した場合」「解放が失敗した場合」の両方で回収不能な資源が残らない。

---

## 2. B 区分（6 件）: 検査が主題を取れていなかった

| ID | 何が起きていたか | 対応 |
|---|---|---|
| M-01 | ST-09 が `activeScope` 決め打ちで、後から足した `localOnly` を見ていなかった。**v3 M-01 の欠陥を再導入しても 20 件すべて通過した** | 入力の一覧を `@State` 宣言から導出し、**画面から取る入力すべて**を対象にする |
| M-02 | ST-10 の床「合計 10 件以上」が他画面のログ 69 件で満たされ、**clipboard 画面のログを全削除しても通った** | 床を clipboard のファイル群の合計で持つ |
| M-03 | ボタン一覧 35 件に対し body 一覧が 36 件（`sampleButton` の定義を拾う）で、`zip` がずれを黙って捨てていた | 定義を除外し、**件数の一致**を検査する |
| M-04 | `tap` が text → sequence の順に読み、古い text と新しい sequence の組を評価しうる | **sequence を先に読む** |
| M-05 | ラベル照合が錨のない部分一致。`snapshot` ⊂ `snapshotFiltered` など実在の包含関係がある | `[label]` で照合し、包含関係のある対をテストに追加 |
| M-06 | 免除範囲が `##` 見出し 1 個以下の文書で全文走査に戻る。`scripts/` にテストが 0 本 | 見出し不足なら免除しない。**`scripts/tests/` を新設し 5 件** |

**M-01 と M-02 は、検査を足した本人（私）が空回りに気づいていなかった。** どちらも
「レビュアーが変異を作って実証した」ことで判明している。

---

## 3. C 区分（6 件）

| ID | 対応 |
|---|---|
| L-01 | 解放失敗時に handle を失わない（§1 に記載） |
| L-02 | 解放中に Picker が一瞬 general に戻る件。**未対応**。資源の不整合はなく、退避を先に行う方が安全なため現状を選ぶ。理由をここに記録する |
| L-03 | 計画が求めていた画面注記 2 件（Append は ownership に従う / named・unique は画面破棄で解放されない）を追加 |
| L-04 | 計画 §7.1 に ST-08 / ST-09 / ST-10、§7.4 の合格条件を ST-01〜ST-10 と UI テストに更新 |
| L-05 | 計画 §8.1 の MT-08 に `CopyWithCurrentOptions` を明記 |
| L-06 | 未参照の `lastOwnership` を削除 |
| L-07 | 非 `ClipboardError` を丸めた 1599 を「到達したコード」に記録しない |
| L-08 | `DetectPatterns` / `DetectValues` の arrange を `DetectMetadata` と同じ形に揃え、どちらで失敗したか分かるようにした |

---

## 4. サーキットブレーカーへの対応

レビュー v4 の指摘:

> 「検査が自分で対象を決める」形の指摘は v1 以降 4 ラウンド連続。個別の検査を足すより、
> 検査の書き方の共通ルールに落とすことを勧める

`agent-rules/coding-rules/common.md` に「検査の書き方（必須）」を追加した。

| 規則 | 破ったときに起きること |
|---|---|
| 両辺をソースから導出する | 実装を変えると検査も変えることになり、ずれが検出できない |
| 空回り防止は主題そのものの単位で持つ | 無関係な対象が床を満たし、主題を全部消しても通る |
| 集合を集めるときは定義側を除き、**件数の一致**を検査する | ずれた対応のまま静かに無意味になる |
| 部分一致には錨を打つ | 名前に包含関係がある対が互いに成立する |

**「実装を壊す形で mutant を作れない」は変異検査を省く理由にならない**（v3 で私が誤った判断）
ことも明記した。`review-implementation-feature` / `review-implementation-sample-app` の停止基準
条件 2 からこの節を参照する。

**今回の B 6 件は、すべてこの 4 規則のいずれかの違反である。**

---

## 5. 変異検査

| 壊した内容 | 落ちるべき検査 | 結果 |
|---|---|---|
| `localOnly` の読みを `Task` の中へ移す（v3 M-01 の再導入） | ST-09 | **落ちた**（`CopyWithCurrentOptions reads localOnly after it has already suspended`） |
| clipboard 画面の `Log.d` を全削除 | ST-10 | **落ちた**（`the clipboard sample contributed 0 log calls`） |
| 免除の判定範囲を全文に戻す | checker のテスト | **落ちた** |
| 免除をトークンの出現だけで判定する（v2 時点の欠陥） | 同上 | **落ちた** |

v3 までの 13 件と合わせて **17 件**。

---

## 6. テスト結果

| 対象 | 宣言数 | 展開後 | 失敗 |
|---|---|---|---|
| `MacLibraryExampleTests` | 20 | 21 | 0 |
| `ClipboardSampleViewUITests` | 6 | 6 | 0 |
| `ClipboardSampleWaitRuleTests` | 6 | 6 | 0 |
| `MacLibrary` | 307 | 351 | 0 |
| `UnityMacPlugin` | 75 | 76 | 0 |
| `scripts/tests`（新設） | 5 | 5 | 0 |

- clipboard 分の合計 **32 宣言 / 33 展開 / 失敗 0**。件数は xcresult から取得。
- `clean test` で **Clipboard 由来の警告 0 件**。
- `git diff develop --check`: 0 件。
- `check_design_consistency.py`: 計画 v5・機能設計 v9 とも全項目 OK。
- `python3 -m unittest discover -s scripts/tests`: OK。

---

## 7. 残作業

| 項目 | 状態 |
|---|---|
| MT-01〜MT-04 / MT-06 / MT-07 | **未実施**（手動確認） |
| MT-08 | **未実施**（端末 2 台が必要）。手順は `CopyWithCurrentOptions` を使うよう更新済み |
| MT-09 | 判定保留 |
| MS-04 / MS-06 | **未実施** |
| L-02（解放中の中間状態） | **未対応**。理由は §3 |
| 平文 `detectMetadata` が 1515 を返す件 | **要検証** |
| `PasteButton` が `supportedContentTypes` に一致しない provider を渡すか | **要検証** |
| BT-01 / BT-08 / BT-12 / CT-05 | **未実装**（機能設計 §12.4） |
| `MacLibraryExampleUITestsLaunchTests/testLaunch` | 環境事象で失敗。テンプレート由来で範囲外 |
