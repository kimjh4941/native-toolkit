# 実装結果レポート v7

## 基本情報

- 日付: 2026-08-30
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v5 の指摘 3 件（M-7 / M-8 / L-3）の反映**
- 前版: `2026-08-30-macos-clipboard-implementation-feature-result-v6.md`

> 本版は第 5 ラウンドの記録である。v3 の実装サマリーは引き続き有効。

---

## 1. レビュー v5 の判定

レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v5.md`

- M-7: **部分解消**（監査対象のログを `stringWithFormat:` に限定する抜け道）
- M-8: **部分解消**（`StartGate` が待機・解放を行わずテストへ未接続）
- L-2: 解消
- L-3: 新規 low（`@discardableResult` の DoD 記述が production と矛盾）
- production code の新規不具合・平文ログ: **なし**
- 総合判定: 要修正（軽微）／マージ保留

---

## 2. 指摘 3 件の反映

### L-3: `@discardableResult` — 実装のほうが誤りだった

**判断**: DoD 記述ではなく実装を直した。

`provideFilePromise`（OP-16）と callback 版 `receiveFilePromises`（OP-18）に
`@discardableResult` が付いていた。**返す handle を捨てると promise の登録と staging、
あるいは receipt session が解放不能になる**。捨てたときに警告が出るほうが正しい。

両者から属性を外し、設計 §8.1 に「OP-16 / OP-18 は戻り値があっても付けない」を明記した。

### M-7: 監査対象のログを全形式へ

**なぜ前回直らなかったか**

対象集合は signature 由来へ直したが、**ログ側の抽出を `stringWithFormat:` に限定**していた。
`[Log e:TAG :@"..."]` の直接文字列は対象外なので、そこに payload を混ぜれば通ってしまう。

**対応**

- `logCalls(in:)` を `[Log ` で分割する形へ変更し、`Log d:` / `Log e:` の全呼び出しを covers する
- 「監査が見た Log 呼び出し数 == ファイル内の全 Log 呼び出し数」を検査に追加。
  新しいログの書き方が増えて監査から漏れれば落ちる

**両方の回帰形で実効性を確認した**

| 注入した回帰 | 修正前 | 修正後 |
|---|---|---|
| `stringWithFormat` 経由の平文 | 検出 | 検出 |
| `Log e` の直接文字列に payload | **素通り** | **検出** |

### M-8: CT-17 のバリアを実際に機能させる

**なぜ前回直らなかったか**

`StartGate` を作りながら、`waitForRelease()` が hook を呼ぶだけで**何もブロックしない**中身に
していた。バリアとして機能しないものをバリアと呼んで置いたため、「登録直後」は固定 sleep 頼み、
同一 handle の検査も 1 境界だけになっていた。

**対応の過程**

最初に本物の `DispatchSemaphore` へ置き換えたが、**start は MainActor 上で走るため
ブロックするとテスト自身がデッドロック**した（実際に 2 テストが失敗した）。

最終的に、start の**内側で同期的に走るフック**へ変更した。

- 「登録中」: フックから `task.cancel()` を呼ぶ。sleep なしで確実にその時点を作れる
- 「登録直後」: `Task.yield()` で `startCallCount == 1` を待つ。時間ではなく状態で待つ
- 「予約直後」: task 本体が走る前に cancel

3 境界すべてで**start に渡された handle が torn down されること**を検査する。

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

## 4. 5 ラウンドの推移

| ラウンド | high | medium | low | 判定 |
|---|---|---|---|---|
| v1 | 4 | 3 | 0 | 要修正（重大） |
| v2 | 0 | 3 | 0 | マージ保留 |
| v3 | 0 | 1 | 1 | 要修正（軽微） |
| v4 | 0 | 2 | 1 | マージ不可 |
| v5 | 0 | 2 | 1 | 要修正（軽微）／マージ保留 |

production code の不具合は v1 で出尽くしている。v2 以降はすべて**検査する側の不備**であり、
形はその都度違うが、共通して「**検査が名乗っている範囲より実際には狭い**」という性質を持つ。

- v2: fake を注入したテストが本番境界を通らない
- v3: 「全 endpoint を検査する」が一部しか見ていない
- v4: 検査の対象集合が手書きで漏れがある
- v5: 対象集合は直したが、ログの**形**を限定していた／バリアが待っていなかった

v4 で対象集合を signature 由来に、v5 でログ形式を全 `Log` に広げ、いずれも
「監査が自分の見落としより広くなる」ことを機械的に保証する検査（宣言引数 28 件、
Log 呼び出し数の一致）を併せて入れた。

---

## 5. 残作業

1. **再レビュー**: 本版を対象に実装レビュー v6 を実施する
2. **T-18**: サンプルアプリ（`design-sample-app` で設計）
3. **手動確認**: MT-01〜MT-08 を実機で実施
4. `MIGRATION.md` の `swift6-migration` は別トピックで範囲外
