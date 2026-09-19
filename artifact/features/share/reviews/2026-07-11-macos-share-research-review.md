# レビュー結果

- 日付: 2026-07-11
- 対象ファイル: `artifact/plans/share/2026-07-11-macos-share-research.md`
- 機能名: share
- 対象 OS: macOS 15 以降
- 種別: 再レビュー

---

## 強み

- 前回残っていた `NSSharingServicePickerDelegate` の共同編集モード制限メソッド名が `sharingServicePickerCollaborationModeRestrictions(_:)` に修正され、Xcode 26.3 SDK で確認した Swift 名と一致した
- `messageBody` / `attachmentFileURLs` の readonly 扱い、本文・添付を `perform(withItems:)` の items 側で表現する方針、S5 サンプル、DoD が一貫している
- `NSSharingService.Name` 一覧が SDK 確認済みの有効定数と deprecated / unavailable 系に分離され、macOS 15 以降の実装者を誤誘導しない形になっている
- `close()` / `standardShareMenuItem` の macOS 13.0+ availability、`show(relativeTo:of:preferredEdge:)` の `mouseDown` 起点制約、`standardShareMenuItem` の代替経路が明記されている
- 公式文書一覧、実装リスク、Definition of Done が研究企画書として十分に具体化されており、設計工程へ渡せる粒度になっている

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

- 解消済み: `messageBody` / `attachmentFileURLs` を書き込み可能として扱っていた問題
- 解消済み: `.addToNotes` / `.postOnFacebook` を macOS 15 以降の主要 `NSSharingService.Name` として扱っていた問題
- 解消済み: `close()` の availability と `standardShareMenuItem` の不足
- 解消済み: `show(relativeTo:of:preferredEdge:)` の `mouseDown` 起点制約不足
- 解消済み: `NSPasteboardWriting` の区分誤り
- 解消済み: `NSSharingServicePickerToolbarItem` の概要・非採用理由不足
- 解消済み: 共同編集モード制限 delegate の Swift 名ずれ

## 検証メモ

- 前回再レビュー時に `xcrun swiftc -typecheck /private/tmp/macos_share_typecheck.swift` で、主要サンプル相当の `NSSharingServicePickerDelegate` / `NSSharingServiceDelegate` / `shareFileByEmail` は typecheck 済み
- 前回再レビュー時に `#selector(NSSharingServicePickerDelegate.sharingServicePickerCollaborationModeRestrictions(_:))` が通ることを確認済み
- 今回は文書反映確認と前回指摘の消し込みを実施し、新しい指摘はなし

## 総合評価

前回までの指摘はすべて解消されています。macOS Share の研究企画書として、公式 API の範囲、非推奨 API の扱い、サンプルコード方針、実装リスク、Definition of Done が整っており、設計工程へ進めて問題ありません。LGTM です。
