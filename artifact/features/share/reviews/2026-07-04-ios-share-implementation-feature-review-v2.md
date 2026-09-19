# iOS Share 実装レビュー結果 v2

## レビュー対象

- 日付: 2026-07-04
- ブランチ: `feature/NTKIT-10`
- PR: なし（ローカルブランチ + 反映済み作業ツリー差分）
- diff:
  - `git diff develop...HEAD`
  - `git diff develop`（v2 反映分が未コミット作業ツリーにあるため併用）
- 設計書: `artifact/designs/share/2026-07-04-ios-share-design.md`
- 実装結果: `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v2.md`
- 前回レビュー: `artifact/reviews/share/2026-07-04-ios-share-implementation-feature-review-v1.md`
- 対象 OS: iOS 18 以降

## レビュー概要

v1 レビューで指摘した H1/M1/M2/L1 の反映を中心に再レビューした。現在の作業ツリーでは、Bridge callback の main thread 契約、Presenter の main actor resume guard、UseCase のログ追加、pbxproj の build number 差分戻しが反映されている。

`develop...HEAD` だけでは未コミットの v2 反映分が含まれないため、今回の判定は `git diff develop` で現在の作業ツリーも含めて確認した。

## 重大な問題（high）

なし。

前回 H1「Bridge callback の main thread 契約が保証されていない」は解消済み。

- `ios/IosLibrary/IosLibrary/Share/IosShareManager.swift:67` で `Task { @MainActor in ... }` により成功・失敗 callback が main actor 上に統一されている
- `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManager.swift:51` で JSON 不正時の早期 callback も main actor 上に統一されている
- `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManagerBridge.h:8` の `Callbacks are invoked on the main thread.` 契約と整合している

## 改善提案（medium）

なし。

前回 M1/M2 は解消済み。

- `ios/IosLibrary/IosLibrary/Share/Presentation/ShareSheetPresenter.swift:81` で `completionWithItemsHandler` から `Task { @MainActor in ... }` に再隔離され、`hasResumed` と continuation resume が main actor 上で実行される
- `git diff develop -- ios/IosLibrary/IosLibrary.xcodeproj/project.pbxproj ios/UnityIosPlugin/UnityIosPlugin.xcodeproj/project.pbxproj` が空で、pbxproj の `CURRENT_PROJECT_VERSION` 副作用差分は現在の作業ツリーでは解消されている

## 軽微な指摘（low）

### L1. main thread callback 契約の専用テストは未追加

- 対象:
  - `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v2.md:194`
  - `ios/IosLibrary/IosLibrary/Share/IosShareManager.swift:67`
  - `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManager.swift:51`
- 問題: 実装結果でも「コードレビューで確認。専用のスレッド検証テストは未追加」とされている。コード上は main actor に統一されているため実装ブロッカーではないが、Bridge 公開ヘッダの thread 契約は Unity 側利用者に影響するため、将来の回帰を防ぐテストがあるとより堅い。
- 改善案: `IosShareManagerTests` または `UnityIosShareManager` のテストで、成功・失敗・JSON 不正の callback 内から `Thread.isMainThread` を確認するケースを追加する。C Bridge 直下までの検証が難しければ Swift facade レベルでよい。

## 設計書整合性チェック

- 企画書との整合性: ○
- Clean Architecture 準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △（公開 thread 契約の専用テストは未追加。ただしコードレビュー上は反映済み）
- ドメインエラー全ケース実装: ○
- エラーコード/メッセージ対応表との整合: ○

## プロジェクトルール適合チェック

- common.md 準拠: ○
- ios.md 準拠: ○
- エラー契約反映: ○
- 既存 API 互換性: ○

## テストカバレッジ

カバーできている観点:

- UseCase 正常系・異常系・items 空
- Manager 完了・キャンセル・失敗
- `ShareError` 全ケースの英語メッセージ
- Data 層の URL scheme 検証、file/image 変換、excluded activity 変換、primary item 置き換え
- JSON Parser の正常系、未知 type / value 欠落、invalid JSON、任意項目

不足・未実施の観点:

- Bridge / Swift facade callback が main thread で呼ばれることの専用自動テスト
- 実機/シミュレータでの共有シート表示、iPad popover、各共有先の実受領、previewTitle 表示
- Unity C# 側からの P/Invoke 実呼び出し

## 総合評価

LGTM。

前回の重大指摘は解消され、設計書・実装結果・現在のコードは整合している。残る thread 契約テストの追加は推奨だが、現時点のコードレビュー上は実装ブロッカーではない。
