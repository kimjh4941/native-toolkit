# 実装結果レポート v9

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- ブランチ: feature/NTKIT-15
- スコープ: **File Promise 4 操作（OP-16 / OP-17 / OP-18 / OP-20）の削除**
- 前版: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v8.md`

> **本版はレビュー指摘への対応ではない。** 実装レビュー v7 は LGTM を出しており、その後に
> 行った**スコープ変更**の記録である。
>
> **削除の根拠は本ファイルには書かない。** 実測 3 件と判断理由は設計書 §7.12 が唯一の出典で
> あり、ここへ複製すると次のドリフト源になる。本ファイルは「何を削り、どう検証したか」に
> 限る。

---

## 1. 経緯

| 版 | 内容 |
|---|---|
| 実装レビュー v7 | **LGTM**（0H / 0M / 0L）。7 ラウンドで収束 |
| サンプル設計 v1 | T-18 の実装計画を作成 |
| サンプル設計レビュー | **高優先度 1 件**: 現行 public API では MT-05 の drag harness を構築できない |
| 設計書 v8 | MT-05 をペーストボード経路へ差し替え |
| 設計書 v8 差分レビュー | **高優先度 1 件**: §12.6.1 の許容分岐と T-18 完了条件が矛盾 |
| 実測 | ペーストボード経由では 3 経路とも成立しないことを確認（設計書 §7.12） |
| **本版** | File Promise を v1 対象外にし、実装ごと削除 |

未知の上に分岐を置いたまま実装へ渡そうとしたのが v8 の誤りだった。分岐は測定で消した。

---

## 2. 削除内容

### 2.1 削除したファイル（19 本）

| 層 | ファイル |
|---|---|
| Domain | `FilePromise.swift` |
| Application/Port | `FilePromiseSnapshotting.swift` |
| Application/UseCase | `ProvideFilePromiseUseCase` / `ReleaseFilePromiseUseCase` / `ReceiveFilePromisesUseCase` / `CancelReceiveFilePromisesUseCase` |
| Data/Promise | `FilePromiseDelegate` / `FilePromiseLifecycleState` / `FilePromiseReceiptSession` / `FilePromiseSnapshotter` / `ReceiptCompletionGate` |
| Tests | `FilePromiseUseCaseTests` / `FilePromiseLifecycleStateTests` / `FilePromiseProvisionTests` / `FilePromiseReceiptCancelTests` / `FilePromiseReceiptSessionTests` / `FilePromiseSnapshotterTests` / `FilePromiseReceiveAsyncTests` / `MockFilePromiseSnapshotter` |

### 2.2 縮小したファイル

| ファイル | 変更 |
|---|---|
| `ClipboardSystemCoordinator.swift` | **470 → 106 行**。stale 監視・staging 掃除・fulfilment queue・receipt session を削除。残るのは paste loader と lazy data provider のみ |
| `MacClipboardManager.swift` | OP-16〜18 / OP-20 を削除。**DI の循環が消え `attachStaleQuery` が不要になった**（R6-H3 で苦労した箇所） |
| `ClipboardRepositoryImpl.swift` | `writeFilePromise` / `startReceivingFilePromises` / `receiptSink` / `receiveQueue` を削除 |
| `ClipboardPromiseRegistry.swift` | 13 メソッド → **2 メソッド**（lazy data provider のみ） |
| `PromiseObjectLookup.swift` | `filePromiseProvider(for:)` を削除 |
| `ClipboardError.swift` | 5 ケース削除（1516〜1520）。**番号は詰めない** |
| `UnityMacClipboardManagerBridge.h` / `.m` | 4 endpoint と `ClipboardReceiptCallback` typedef を削除 |
| `UnityMacClipboardManager.swift` / `JsonParser.swift` | 対応する façade と JSON 形状を削除 |

**エラーコードを詰めなかった理由**: 1521〜1524 を動かすと既存の利用者側の契約が壊れる。
欠番のまま残すほうが安全である。

### 2.3 差分規模

```
mac/ 配下   46 files changed, 77 insertions(+), 4861 deletions(-)
うち削除    19 files
```

---

## 3. 検証結果

| 対象 | 結果 |
|---|---|
| MacLibrary | `clean test` **357 passed / 0 failed** |
| UnityMacPlugin | `clean test` **74 passed / 0 failed** |
| 通常 `clean test` の Clipboard 警告 | **0 件**（両ターゲット） |
| CT-01 strict whole-module build | `BUILD SUCCEEDED` |
| strict 診断（path+message で一意） | **173 件 / Clipboard 由来 0 件**（v8 から増減なし） |
| MacLibraryExample | `BUILD SUCCEEDED` |
| 設計書の機械照合 | **22 / 22 通過** |

再現コマンドは v8 と同じ。`clean` を落とすと Clipboard 警告数は無条件に 0 件へ化ける。

### 3.1 テスト件数の内訳

| | v8 | v9 |
|---|---|---|
| MacLibrary（宣言） | 437 | **357** |
| UnityMacPlugin（宣言） | 80 | **74** |

削除した 80 件はすべて File Promise の回帰テストである。**残った 357 件は 1 件も落ちていない。**
削除対象の切り分けが正しかったことの傍証になる。

---

## 4. 削除中に見つけたこと

コンパイラとテストが、手作業では見落としていた依存を 6 回捕まえた。

| # | 見落とし | 検出 |
|---|---|---|
| 1 | `ClipboardPromiseRegistry` を丸ごと削除したが、lazy data provider（OP-01 の内部機構）が使っていた | ビルドエラー |
| 2 | `PromiseObjectLookup` も同様 | ビルドエラー |
| 3 | `MockClipboardPromiseRegistry` を削除したが Manager テストが使っていた | ビルドエラー |
| 4 | `ClipboardErrorTests.caseCount` の期待値 25 が古い | テスト失敗 |
| 5 | `ClipboardDocumentationTests` が削除済み契約の DocC 文言を検査していた | テスト失敗 |
| 6 | Bridge 監査の期待値（19 endpoint / 28 引数 / 4 typedef） | テスト失敗 |

6 はレビュー v3〜v6 で 4 回作り直した監査そのものである。**削除に対しても正しく落ちた。**

設計書側でも機械照合が 4 回捕まえた（§6.1 ファイル構成、§6.5.1 isolation 表、§8.4.4 JSON 型表、
§15 DoD）。いずれも手作業なら残していた。

---

## 5. 副産物: `check_design_consistency.py` の改善

`## 0.x` の変更履歴セクションを旧表現スキャンの対象外にした。

履歴は「当時こう決めた」という記録であり、後の版で削除した語がそこに現れるのは正しい。
除外しないと、正しい履歴記述が毎回 FAIL として報告される。

---

## 6. レビュー時に見てほしい点

1. **削除漏れがないか**: `FilePromise` / `Receipt` を名前に含む production シンボルが残っていないか
2. **削り過ぎていないか**: lazy data provider（OP-01）と paste loader（OP-19）は coordinator に
   残す必要がある。§2.2 のとおり縮小して残した
3. **エラーコードの欠番**: 1516〜1520 を欠番のままにした判断（§2.2）
4. **設計書との一致**: 公開 OP 16 / Bridge endpoint 15 / UseCase 14 / Port 3

---

## 7. 残作業

1. **サンプル計画 v2**: File Promise セクションと drag harness を落とす。サンプル設計レビューの
   高優先度 1 件は本版で解消済み。medium 9 / low 3 は未対応
2. **T-18**: サンプルアプリ実装
3. **手動確認**: MT-01〜MT-04 / MT-06 / MT-07（MT-05 は削除、MT-08 は実機 2 台、MT-09 は判定保留）
4. **再レビュー**: 本版を対象に実装レビューを実施する
