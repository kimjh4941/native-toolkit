# レビュー結果

- 日付: 2026-07-11
- 対象ファイル: `artifact/designs/share/2026-07-11-macos-share-design.md`
- 機能名: share
- 対象 OS: macOS 15 以降
- 種別: 再レビュー

---

## 強み

- 前回残っていた `ShareItem` 説明内の古い「除外 service は raw String」表現が修正され、直接実行は raw `NSSharingService.Name`、ピッカー除外は `excludedServiceTitles`（`NSSharingService.title` の best-effort 一致）という方針に揃った
- `NSSharingService.name` 依存は残っておらず、ピッカー除外の実装案は `proposed.filter { !excludedServiceTitles.contains($0.title) }` に統一されている
- `excludedServiceTitles` の制約（表示名・ローカライズ依存）と、確実な制御が必要な場合は `shareViaService` を使う方針が Scope / Domain / Parser / Risk / DoD に通っている
- Unity Bridge 経由の `mouseDown` 制約は T5/T8 の完了条件と設計上の分岐 A/B/C に反映されている
- UseCase サンプルの先頭 `Log.d`、未使用 `AnchorUnavailableError` 削除、エラー契約、テスト観点が整っており、mac.md / common.md と整合している

## 改善点

### 高優先度

- なし

### 中優先度

- なし

### 低優先度

- なし

## 不足項目

- なし

## 前回指摘の消し込み

- 解消済み: `excludedServiceNames` が `NSSharingService.name` に依存してコンパイル不能だった問題
- 解消済み: Unity Bridge 経由の `mouseDown` 制約が完了条件に入っていなかった問題
- 解消済み: UseCase サンプルコードと mac.md ログ規約の不整合
- 解消済み: 未使用 `AnchorUnavailableError` のノイズ
- 解消済み: `ShareItem` 説明内の古い raw service 文言

## 検証メモ

- 前回再レビュー時に `/private/tmp/macos_share_design_typecheck.swift` で `NSSharingService.title`、`NSSharingService(named: .init(raw))`、`services.filter { !excludedServiceTitles.contains($0.title) }` の typecheck を実施し、成功済み
- 今回は文書反映確認と前回指摘の消し込みを実施し、新しい指摘はなし

## 総合評価

前回までの指摘はすべて解消されています。macOS Share の実装設計書として、研究企画書との整合、Clean Architecture、エラー契約、Bridge 仕様、テスト計画、実機検証リスクの扱いが揃っており、実装工程へ進めて問題ありません。LGTM です。
