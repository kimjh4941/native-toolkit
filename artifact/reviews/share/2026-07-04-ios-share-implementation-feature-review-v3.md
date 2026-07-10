# iOS Share 実装レビュー結果 v3

## レビュー対象

- 日付: 2026-07-04
- ブランチ: `feature/NTKIT-10`
- PR: なし（ローカルブランチ + 反映済み作業ツリー差分）
- diff:
  - `git diff develop...HEAD`
  - `git diff develop`（v3 反映分が未コミット作業ツリーにあるため併用）
- 設計書: `artifact/designs/share/2026-07-04-ios-share-design.md`
- 実装結果: `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v3.md`
- 前回レビュー: `artifact/reviews/share/2026-07-04-ios-share-implementation-feature-review-v2.md`
- 対象 OS: iOS 18 以降

## レビュー概要

v2 レビューの low 指摘だった main thread callback 契約の専用テスト追加を中心に再レビューした。`IosShareManagerTests` では完了・キャンセル・失敗の 3 経路で `Thread.isMainThread` を検証し、新規 `UnityIosShareManagerTests` では JSON 不正時の facade callback が main thread 上で返ることを検証している。

コードとテストは前回指摘を満たしており、実装上のブロッカーはない。

## 重大な問題（high）

なし。

## 改善提案（medium）

なし。

## 軽微な指摘（low）

### L1. 実装結果レポートに古い「専用ユニットテスト未追加」記述が残っている

- 対象:
  - `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v3.md:110`
- 問題: v3 で `UnityIosShareManagerTests/shareWithInvalidJsonInvokesHandlerOnMainThreadWithError` が追加され、JSON 不正時の `"Invalid share content JSON."` と main thread callback を検証済みだが、第 3.2 章の表には「専用ユニットテストは未追加」と残っている。
- 影響: 実装やテストには影響しないが、実装結果 artifact のテスト状況が一部矛盾して見える。
- 改善案: 当該行を「`UnityIosShareJsonParserTests/parseContentInvalidJsonReturnsNil` と `UnityIosShareManagerTests/shareWithInvalidJsonInvokesHandlerOnMainThreadWithError` で確認」に更新する。

## 設計書整合性チェック

- 企画書との整合性: ○
- Clean Architecture 準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: ○
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
- Manager callback の main thread 契約（完了・キャンセル・失敗）
- Unity facade の JSON 不正時 callback の main thread 契約と errorMessage
- `ShareError` 全ケースの英語メッセージ
- Data 層の URL scheme 検証、file/image 変換、excluded activity 変換、primary item 置き換え
- JSON Parser の正常系、未知 type / value 欠落、invalid JSON、任意項目

未実施の観点:

- 実機/シミュレータでの共有シート表示、iPad popover、各共有先の実受領、previewTitle 表示
- Unity C# 側からの P/Invoke 実呼び出し

## 総合評価

LGTM。

v2 の残指摘はテスト追加により解消されている。残る L1 は実装結果レポート内の記述更新だけで、実装・テストのブロッカーではない。
