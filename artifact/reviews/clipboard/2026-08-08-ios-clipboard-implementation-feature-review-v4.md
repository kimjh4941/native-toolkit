# iOS Clipboard 実装レビュー v4

> **Errata（2026-08-08）**
> 本レビューの **strict 診断に関する評価は、実装結果レポート v5 により撤回・再評価が必要**。
> 具体的には次の記述が成立しない。
> - 「Clipboard path を発生元とする strict error は確認されなかった」（検証結果）
> - 「今回の修正差分に新たな High / Medium / Low のコード不具合は確認されなかった」（レビュー概要）
> - **総合評価の「今回のコード差分は LGTM」**
>
> 原因は計測方法にある。Swift 6 言語モードは型検査段階の既存 error で停止するため、
> フロー解析段階の `sending` 系診断に到達せず、`UnityIosPlugin` は自身のソースが未コンパイルだった。
> Swift 5 + `SWIFT_STRICT_CONCURRENCY=complete` で再計測すると Clipboard 由来 19 件が検出される。
>
> うち 3 件は v5 で修正済み。残る 16 件（Bridge callback の `sending 'handler'`）は
> **NTKIT-14 受け入れ前に解消が必要**。
> 詳細: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v5.md`
> 監査性のため本文は当時のまま保持している。再レビュー（v5）は別途実施が必要。

## レビュー対象

- 日付: 2026-08-08
- 対象OS: iOS 18以降
- ブランチ: `feature/NTKIT-14`
- 比較差分: `develop...feature/NTKIT-14` と未コミットのv1〜v4修正差分
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v4.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v3.md`

## レビュー概要

- v3のHigh 1件、Medium 3件はすべて解消した。
- `PasteItemProviderLoader.isolated deinit`によりraw factory経路でもpending loadがcancelされ、遅延file completionが生成した一時fileをdiscardできることをコードと回帰テストで確認した。
- strict error内訳はDialog 1 / Notification 9 / Share 3へ、通常clean buildの既存warningは2件へ正しく訂正された。
- `FailureDetailCode.sourceSizeUnverifiable`により、source size検証不能の失敗境界がテストで固定された。
- SimulatorテストはIosLibrary 186件、UnityIosPlugin 73件、失敗0を再現した。
- 今回の修正差分に新たなHigh / Medium / Lowのコード不具合は確認されなかった。
- ただし、現行の設計v4に対してはI-10、I-08、I-09、T-00、T-12、T-13が未達であり、機能全体のDoDはまだ完了していない。

## 重大な問題（high）

なし。

## 改善提案（medium）

なし。

## 軽微な指摘（low）

なし。

## v3指摘の解消確認

| ID | 判定 | 確認内容 |
|---|---|---|
| H-01 | 解消 | `PasteItemProviderLoader`へ`isolated deinit { cancelAll() }`を追加。loader / receiver解放後の内部`.cancelled` exactly-once、UI callback抑止、遅延file cleanupを回帰テストで確認 |
| M-01 | 解消 | strict error内訳をDialog 1 / Notification 9 / Share 3へ訂正 |
| M-02 | 解消 | 通常clean buildの既存warning 2件を明記し、「Clipboard由来0件」とtarget全体を区別 |
| M-03 | 解消 | `FailureDetailCode`を導入し、source size検証不能が`sourceSizeUnverifiable = -3`であることを検証 |

## I-10と設計改訂に関する判断

- 前回判断どおり、既存Dialog / Notification / ShareのSwift 6移行を別タスクへ切り出す方針は妥当である。
- v4結果レポート7.2の設計v5改訂案も妥当である。
  1. Clipboard差分がSwift 6 strict診断を新規追加しないことを本タスクのDoDにする。
  2. 既存13 error / 2 warningをbaselineとして固定し、別タスクIDへリンクする。
  3. 検証はwhole-module buildとbaseline差分比較を必須にする。
- ただし、設計v5が未作成のため、現時点の正本である設計v4ではI-10が未達のままである。実装受け入れ前にdesignワークフローで設計を改訂し、別タスクIDを確定させる必要がある。

## 設計書整合性チェック

- 企画書との整合性: △ — 実機T-00 / T-13が未実施
- Clean Architecture準拠: ○
- 既存実装との差分分析の正確性: ○ — strict内訳と通常warning記録を実測値へ訂正済み
- テスト設計の網羅性: △ — v3の回帰観点は解消したが、I-08 / I-09と実機確認が未達
- ドメインエラー全ケース実装: ○
- エラーコード/メッセージ対応表との整合: ○
- D-16 cleanup契約: ○ — Manager / ItemLoader / Presentation loader / Containerの4型すべてに`isolated deinit`あり

## プロジェクトルール適合チェック

- common.md準拠: ○ — 非同期完了、cancel、timeout、resource ownershipの契約と実装が一致
- ios.md準拠: ○
- エラー契約反映: ○
- 既存API互換性: ○
- 同期 / 非同期設計表との整合: ○

## テストカバレッジ

### 今回追加・強化された観点

- loader解放時のpending load cancelと内部`.cancelled` exactly-once
- raw factory経路でreceiver解放後にUI callbackを配信しないこと
- loader / receiver解放後に遅延到着したfileをdiscardすること
- source size検証不能とcopy後size検証不能のfailure detail識別

### 未完了の検証

- queue済み旧observer eventのgeneration gate直接再現（Simulator制約は結果レポートに記録済み）
- I-08 Bridge 15 endpoint / 9 content kind end-to-end
- I-09 `ClipboardRedaction`独立module境界テスト
- 設計v4上のI-10 full-module strict-green（設計v5でbaseline差分方式へ改訂予定）
- T-00プライバシー実機スパイク
- T-12サンプルアプリ
- T-13実機M-01〜M-16

## 検証結果

- `git diff --check`: 問題なし
- IosLibrary tests: 186件、失敗0（iPhone 17 Pro / iOS 26.2 Simulator）
- UnityIosPlugin tests: 73件、失敗0（iPhone 17 Pro Max / iOS 26.2 Simulator）
- 新規回帰テスト2件はいずれもpass
- 通常test build: 成功
- 既存warning: Notification 1件、Unity Notification 1件
- strict baseline: 既存13 error（Dialog 1 / Notification 9 / Share 3）、Clipboard由来0件

## 総合評価

**要修正（軽微）**

v3で指摘した実装不具合とレポート誤記はすべて解消しており、今回のコード差分はLGTMである。残る修正はコード不具合ではなく、合意済みのI-10分離を設計v5へ反映して正本と実態を一致させることである。機能完了判定には、別途I-08 / I-09、T-00 / T-12 / T-13の実施または明示的なスコープ分離も必要である。
