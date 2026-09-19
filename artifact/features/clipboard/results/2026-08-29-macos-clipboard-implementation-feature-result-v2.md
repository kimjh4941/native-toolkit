# 実装結果レポート v2

## 基本情報

- 日付: 2026-08-30
- 機能名: clipboard
- 対象OS: macOS
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- ブランチ: feature/NTKIT-15
- スコープ: **T-01 / T-02 / T-11a / T-11b の 4 タスクに限定**（ユーザー指示による先行実装）
- 前版: `2026-08-29-macos-clipboard-implementation-feature-result-v1.md`

> **本版は v1 の §7.2 と §8 を置き換える。** それ以外の節（実装サマリー・変更ファイル・
> エラー契約・ビルド結果・テスト結果）は v1 のまま有効である。
> v1 には Errata を追記済み。

---

## 1. 訂正: v1 §7.2 の Swift 6 測定は無効だった

v1 §7.2 は「新規ソース 15 本を `swiftc -swift-version 6` で単体型検査し、警告ゼロを確認した」と
記載している。**この測定方法は `artifact/MIGRATION.md` §4.3 の必須条件を満たしておらず、
移行規模の判断材料として使ってはならない。**

| §4.3 の必須条件 | v1 の測定 |
|---|---|
| `SWIFT_COMPILATION_MODE=wholemodule` | 満たさず（`swiftc -typecheck`） |
| `clean` build | 満たさず |
| 依存関係の**最下流** scheme を指定 | 満たさず（`MacLibrary` のソースのみ。`UnityMacPlugin` / Example / Test 未計測） |

`-typecheck` は SIL 生成前に終了するため、**フロー解析段階の `sending` 系診断が構造的に 1 件も
出ない**。これは `MIGRATION.md` §1 の背景表にある**誤り #3 と同一の失敗**である。

さらに `MIGRATION.md` §4.2 B は macOS の Swift 6 language mode を **MacLibrary 8 件**
（Dialog 1 / Notification 1 / Share 6）と whole-module で実測しており、v1 の観測（1 件）と矛盾する。
同節は「この数値を**規模の見積もりに使ってはならない**」とも明記している。

---

## 2. 正しい計測（`swift5-concurrency-readiness` / macOS）

`MIGRATION.md` §4.2 D で「未計測」とされていた macOS 分を、§4.3 の条件で取得した。

```bash
xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin \
  -destination 'platform=macOS' \
  SWIFT_VERSION=5.0 SWIFT_STRICT_CONCURRENCY=complete \
  SWIFT_COMPILATION_MODE=wholemodule clean build
```

集計は §4.3 の正規化コマンド（フルソース位置 + 診断文の unique 行。出現回数ではない）。

**結果: BUILD SUCCEEDED / exit 0 / error 0 / unique warning 173**

| 領域 | 件数 |
|---|---|
| MacLibrary / Dialog | 100 |
| MacLibrary / Notification | 52 |
| MacLibrary / Share | 13 |
| UnityMacPlugin / Share | 5 |
| UnityMacPlugin / Notification | 2 |
| UnityMacPlugin / Dialog | 1 |
| **MacLibrary / Clipboard** | **0** |

### 2.1 positive control

「0 件」が「診断なし」なのか「そもそもコンパイルされていない」のかを区別するため、
ログ中のコンパイル対象を確認した。**Clipboard の新規 15 ファイルすべてがこのビルドで
コンパイルされている**（`MIGRATION.md` §1 誤り #3 の後半、依存先失敗による未コンパイルではない）。

### 2.2 この 0 件が意味しないこと

**完成後の Clipboard が 0 件であることを意味しない。** 現時点で実装済みなのは
T-01 / T-02 / T-11a / T-11b の 15 ファイルのみで、**Unity Bridge（T-16a / T-16b）は未実装**である。
iOS Clipboard では Bridge の `sending 'handler'` が **16 件**発生した（`MIGRATION.md` §4.2）。
macOS も同じ構造を取るため、案 C を適用せずに Bridge を書けば同数の診断が新規に発生する。

### 2.3 baseline としては保存していない

`MIGRATION.md` §4.1 は「baseline はクリーンな `develop`、または明示した commit から生成する。
feature branch 上で生成してはならない」と定める。本計測は `feature/NTKIT-15` の
dirty worktree 上で取得した**確認目的の観測値**であり、`artifact/baselines/` へは保存していない。

---

## 3. 設計書への還元（v7 を更新済み）

| # | 内容 | 反映先 |
|---|---|---|
| A-1 | `FilePromiseSnapshotting` 実装は `FileManager` を保持せず、`makeFileManager: @Sendable () -> FileManager` を注入して serial queue 内で生成する | §7.12 |
| A-2 | 前提の使用言語を **Swift 5.0 言語モード**へ訂正。Swift 6 移行は `MIGRATION.md` の別トピックである旨を明記 | 冒頭「前提」 |
| A-3 | CT-01 を「Swift 6 strict concurrency で警告ゼロ」から「**差分が strict concurrency 診断を増やさない**（`Clipboard/` 配下 0 件）」へ変更。`MIGRATION.md` §3.3 準拠 | §12.5 |
| A-4 | 実装完了条件（DoD）を同様に差分基準へ変更。「プロジェクトを Swift 6 へ切り替えることは本タスクの完了条件ではない」を明記 | §15 |
| A-5 | **案 C（Bridge の Swift facade handler へ `@Sendable`）を新設 §8.4.6 として規定**。§8.4.1 の共通規約表にも 1 行追加 | §8.4.1 / §8.4.6 |
| A-6 | 案 C の検証テスト **BT-20〜BT-23** を追加。T-16a のレビュー観点にも追加 | §12.4 / §13 |

§16.2 の機械照合は **22 検査すべて通過**（exit 0）。

---

## 4. Swift バージョン方針の決定

**(c) 現状維持**（`SWIFT_VERSION = 5.0` のまま）。

根拠は `MIGRATION.md`。

- §3.3 — 機能タスクの DoD は「変更差分が baseline に新規診断を追加しない」。「Swift 6 に上げる」ではない
- §4.1 / §8 手順 8 — baseline はクリーンな `develop` から取得する。手順 1（チケット採番）・7（`check_baseline.sh`）・8・9 がいずれも未着手
- §6 — `shared` シングルトンへの `@MainActor` 追加は**ソース互換性に影響する公開 API 変更**であり、単なるコンパイル修正として扱ってはならない

なお v1 §7.2 が挙げた選択肢 (b)「Clipboard ターゲットのみ `SWIFT_VERSION = 6.0`」は**成立しない**。
`SWIFT_VERSION` はターゲット単位の設定で、`MacLibrary.xcodeproj` のネイティブターゲットは
`MacLibrary` と `MacLibraryTests` の 2 つのみであり、Clipboard は独立ターゲットではない。

---

## 5. 未達項目

| 項目 | 状態 |
|---|---|
| Port Mock 4 種 | **T-06 へ繰り延べ**。T-02 の完了条件「4 種の Mock が実装できる」は満たすが、Mock 実体は未作成 |
| T-03 〜 T-18 | 未着手（今回スコープ外） |

---

## 6. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- **ユーザー回答: キャンセル**
- 結果: **ここまでの差分を保持したまま終了**。`review-implementation-feature` へは進まない

### 保持されている未コミットの差分

```
 M agent-rules/workflows/design-feature/workflow.md      機械照合を step 9 に追加
 M agent-rules/workflows/research-feature/workflow.md    実機検証ルール 5 件
 M agent-rules/workflows/review-document/workflow.md     レビュー前の機械照合
?? scripts/check_design_consistency.py                   設計書の機械照合（22 検査）
?? artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md
?? artifact/plans/clipboard/*.md, artifact/reviews/clipboard/*.md
?? artifact/results/clipboard/*.md
?? mac/MacLibrary/MacLibrary/Clipboard/          新規 15 ファイル
?? mac/MacLibrary/MacLibraryTests/Clipboard/     新規 4 ファイル / 44 テスト
```
