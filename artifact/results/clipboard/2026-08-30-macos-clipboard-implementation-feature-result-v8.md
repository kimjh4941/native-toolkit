# 実装結果レポート v8

## 基本情報

- 日付: 2026-08-30
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- ブランチ: feature/NTKIT-15
- スコープ: **実装レビュー v6 の指摘 5 件（M-8 / M-9 / L-4 / L-5 / L-6）の反映**
- 前版: `2026-08-30-macos-clipboard-implementation-feature-result-v7.md`

> 本版は第 6 ラウンドの記録である。v3 の実装サマリーは引き続き有効。

---

## 1. レビュー v6 の判定

レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v6.md`

- M-7: **解消**（signature 由来の payload 集合 × 全 `Log` 形式）
- L-3: **解消**（OP-16 / OP-18 の `@discardableResult` 契約を統一）
- M-8: 部分解消（CT-17 の handle 同一性が条件付き、cleanup が固定 sleep 依存）
- M-9: **新規 medium**（`defaultObservationInterval` の actor isolation 警告）
- L-4 / L-5 / L-6: 新規 low
- 総合判定: 要修正（軽微）／マージ保留

**M-9 は v1 以来はじめての production code への新規指摘である。** 5 ラウンドにわたり
「Clipboard 由来の strict concurrency 診断 0 件」と報告してきたが、それは CT-01 条件
（Swift 5 + complete + whole-module + clean）の測定値だけであり、**通常の
`xcodebuild test` を一度も見ていなかった**。同じファイルの警告を 6 ラウンド見逃した。

---

## 2. 指摘 5 件の反映

### M-9: default argument の actor isolation（production）

`MacClipboardManager` は `@MainActor` なので、その `public static let` も暗黙に
main actor 隔離される。default argument は**呼び出し側の文脈**で評価されるため、
nonisolated からの参照になる。

```
MacClipboardManager.swift:503:77: warning: main actor-isolated static property
'defaultObservationInterval' can not be referenced from a nonisolated context;
this is an error in the Swift 6 language mode
```

`nonisolated public static let` を明示した。`TimeInterval` は `Sendable` な値型なので
隔離を外しても競合の余地はなく、意味は変わらない。なぜ `nonisolated` が必要かを
DocC に残した — 外すと再発するため。

### M-8: CT-17 の 3 境界（テスト）

指摘は 3 点あり、いずれも当たっていた。

| 指摘 | 反映 |
|---|---|
| `cancelJustAfterReservation` が session 数しか見ず `repository` 未使用 | `onStart` で coordinator が保持する予約 handle を記録し、start に渡された handle との一致を assert |
| `if let started` により 3 境界の equality が条件付き | `try #require` に変更。start が呼ばれない実装になればテストが**落ちる** |
| cleanup 完了が 150〜200ms の固定 sleep | 状態条件で待つ `waitUntil` に置換。5 秒で成立しなければ `Issue.record` で明示的に失敗 |

identity の取り方を変えた点が要点である。以前は「start に渡された handle の session が
消えたか」しか見ておらず、*予約* handle との一致は証明していなかった。
`registerReceipt` は `startReceivingFilePromises` より先に走るので、start の内側では
coordinator が予約 handle を保持している。そこから読むことで
「reserve が返した handle == start が受け取った handle == teardown された handle」が
1 本の assert 列でつながる。

同じ固定 sleep が CT-17 外の 2 テスト（購読破棄・cancel 後の cleanup）にもあったため、
同じ `waitUntil` に寄せた。ファイル内に残る `Task.sleep` は「時間そのものを検査する」
テスト（timeout / quiet interval）だけになった。

### M-9 の続き: 通常ビルドを見たら、テストコードにも 5 件あった

M-9 を直したあと、はじめて通常 test build を通しで見た。production は 0 件になったが、
**テストコードに Clipboard 由来の警告が 5 件残っていた**（いずれも Swift 6 では error）。

| 箇所 | 内容 |
|---|---|
| `FilePromiseReceiveAsyncTests.swift` 4 件 | `ReceiptCompletionGate.attach` は `@escaping @Sendable` を取るため、捕捉した `var delivered` / `var count` の変更がデータ競合 |
| `ClipboardPasteLoaderTests.swift` 1 件 | 使われていない `let recorder` |

前者は lock で守った `OutcomeLog` に置き換えた。テストが単一スレッドで走るのは事実だが、
`@Sendable` の境界を跨ぐ以上、コンパイラの言い分のほうが正しい。後者は削除した。

**インクリメンタルビルドではこれらが見えなかった。** 変更のないファイルの警告は再出力
されないためで、直前の実行では 0 件に見えていた。`clean test` で測り直してはじめて
5 件が出た。M-9 を見逃した構図と同じもので、条件を 1 つ変えると診断の集合が変わる。
以後、警告数は `clean` を付けて測る。

### L-4: 結果レポートのテスト件数

v7 の 421 / 79 は誤りだった。数え方を定義して両方を記録する。

| 対象 | 宣言数（`@Test`） | 実行数（展開後） | 失敗 |
|---|---|---|---|
| MacLibrary | 437 | 497 | 0 |
| UnityMacPlugin | 80 | 81 | 0 |

宣言数と実行数が食い違うのは `arguments:` 付き `@Test` が展開されるためで、
どちらか一方だけでは再現できない。以後は両方を書く。

### L-5: 設計書末尾の余分な空行

`design-v7.md:2547` を削除。`git diff develop...HEAD --check` が通るようになった。

### L-6: scope 外差分

`ios/.../UserInterfaceState.xcuserstate` を追跡から外し、`ios/.gitignore` と
`mac/.gitignore` に `xcuserdata/` を追加した。`Debug/` `Release/` と違い
`xcuserdata` は Xcode 予約名で `.xcworkspace` / `.xcodeproj` の中にしか現れないため、
深さを固定しないパターンで安全である（`.gitignore` 先頭の注記と同じ判断基準）。

同じ差分に含まれる以下は**意図した変更**であり、除外しない。

| ファイル | 理由 |
|---|---|
| `agent-rules/workflows/{design-feature,research-feature,review-document}/workflow.md` | 設計レビューが 6 ラウンド収束しなかったことへの再発防止。機械照合をワークフローに組み込んだ |
| `scripts/check_design_consistency.py` | 同上。相互参照のドリフトを人手で追うのをやめるための検査 |
| `artifact/MIGRATION.md` | macOS の `swift5-concurrency-readiness` 実測を追記（未計測欄の解消） |
| `artifact/plans/clipboard/*` | 本機能の調査記録 |

追跡済みの `xcuserdata` は他に 15 件あるが、いずれも develop 時点からの既存状態であり
本ブランチの差分ではないため触っていない。別途のリポジトリ整理とする。

---

## 3. 検証結果

| 対象 | 結果 |
|---|---|
| MacLibrary | 宣言 437 / 実行 497 / 失敗 0 |
| UnityMacPlugin | 宣言 80 / 実行 81 / 失敗 0 |
| 通常 `clean test` の Clipboard 警告 | **0 件**（修正前: production 1 件 + test 5 件） |
| CT-01 strict whole-module build | `BUILD SUCCEEDED` |
| strict 診断（path+message で一意） | 173 件 / **Clipboard 由来 0 件** |
| 設計書の機械照合 | 22 / 22 通過 |
| `git diff develop --check` | 0 件 |

再現コマンド:

```bash
# clean を付けないと、変更のないファイルの警告が再出力されず 0 件に見える
xcodebuild clean test -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary     -destination 'platform=macOS'
xcodebuild clean test -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS'

xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin \
  -destination 'platform=macOS' \
  SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_COMPILATION_MODE=wholemodule clean build

python3 scripts/check_design_consistency.py \
  artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md
```

strict 診断 173 件の内訳は Dialog 101 / Notification 54 / Share 18 で、Clipboard の
ファイルは 1 件も含まれない。v7 の 173 件と同じ数え方（path + message で一意）であり、
増減もない。

なお素の `grep` は 175 行を返す。差の 2 行は `appintentsmetadataprocessor` の
`No AppIntents.framework dependency found.` で、コンパイラ診断ではなく、行頭の
タイムスタンプのせいで一意化されずに 2 回残るだけである。数える前にファイル起因の
警告へ絞る必要がある。

---

## 4. 6 ラウンドの推移

| ラウンド | high | medium | low | 判定 |
|---|---|---|---|---|
| v1 | 4 | 3 | 0 | 要修正（重大） |
| v2 | 0 | 3 | 0 | マージ保留 |
| v3 | 0 | 1 | 1 | 要修正（軽微） |
| v4 | 0 | 2 | 1 | マージ不可 |
| v5 | 0 | 2 | 1 | 要修正（軽微）／マージ保留 |
| v6 | 0 | 2 | 3 | 要修正（軽微）／マージ保留 |

v7 で「production code の不具合は v1 で出尽くしている」と書いたが、**これは誤りだった**。
v6 の M-9 は production code の指摘である。誤らせた原因は指摘の内容ではなく測定条件で、
CT-01 という**厳しい方の**ビルドだけを見て、通常ビルドを見ていなかった。
厳しい条件が緩い条件を包含するという思い込みで、実際には診断の集合が違った。

以後、実装結果には CT-01 の診断数と**通常 `clean test` の Clipboard 警告数**の両方を書く。
本版の表に後者を追加した。`clean` を落とすと後者は無条件に 0 件へ化けるため、条件込みで
書くこと自体が要件である。

---

## 5. 残作業

1. **再レビュー**: 本版を対象に実装レビュー v7 を実施する
2. **T-18**: サンプルアプリ（`design-sample-app` で設計）
3. **手動確認**: MT-01〜MT-08 を実機で実施
4. `MIGRATION.md` の `swift6-migration` は別トピックで範囲外
5. 追跡済み `xcuserdata` 15 件の整理（本ブランチ範囲外）
