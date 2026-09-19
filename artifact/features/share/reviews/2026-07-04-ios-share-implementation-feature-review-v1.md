# iOS Share 実装レビュー結果 v1

## レビュー対象

- 日付: 2026-07-04
- ブランチ: `feature/NTKIT-10`
- PR: なし（ローカルブランチ差分）
- diff: `git diff develop...HEAD`
- 設計書: `artifact/designs/share/2026-07-04-ios-share-design.md`
- 実装結果: `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v1.md`
- 対象 OS: iOS 18 以降

## レビュー概要

`develop` との差分では、iOS Share 機能の Clean Architecture 構成、Unity Bridge、Swift Testing ベースの単体テスト、設計・実装結果 artifact が追加されています。実装の大枠は設計書と整合しており、Domain / Application / Data / Presentation / Manager / Bridge の分離、URL 検証、`UIActivityItemSource` の primary item 置き換え、エラー契約は概ね実装されています。

一方で、Bridge が公開ヘッダで約束している callback thread 契約と、設計書が求める Presenter の main actor resume guard がコード上で保証されていません。

## 重大な問題（high）

### H1. Bridge callback の main thread 契約が保証されていない

- 対象:
  - `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManagerBridge.h:8`
  - `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManager.swift:46`
  - `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManager.swift:48`
  - `ios/IosLibrary/IosLibrary/Share/IosShareManager.swift:64`
  - `ios/IosLibrary/IosLibrary/Share/IosShareManager.swift:67`
  - `ios/IosLibrary/IosLibrary/Share/IosShareManager.swift:70`
- 問題: C Bridge ヘッダは `Callbacks are invoked on the main thread.` と明記していますが、実装では main thread への dispatch がありません。JSON 不正時は `UnityIosShareManager.share` が呼び出し元スレッドで即時 `handler?(false, ...)` を呼び、通常経路も `IosShareManager.share` の unstructured `Task` 内で `completion?` を呼ぶだけです。`ShareSheetPresenter` は `@MainActor` ですが、その後の `Task` 継続・callback 実行スレッドまでは公開契約として保証されません。
- 影響: Unity/C# 側が callback 内で Unity API や UI 状態を触る場合、main thread 前提が崩れて不安定になります。公開ヘッダの契約とも不一致です。
- 修正案: `UnityIosShareManager` または `IosShareManager` の callback 境界で `Task { @MainActor in handler?(...) }` / `await MainActor.run { ... }` に寄せ、成功・失敗・JSON 不正の全経路で同じ thread 契約にする。あわせて callback が main thread で呼ばれるテスト、またはヘッダ契約の見直しを追加してください。

## 改善提案（medium）

### M1. Presenter の `hasResumed` guard が設計どおり main actor 上に再隔離されていない

- 対象:
  - `artifact/designs/share/2026-07-04-ios-share-design.md:275`
  - `ios/IosLibrary/IosLibrary/Share/Presentation/ShareSheetPresenter.swift:57`
  - `ios/IosLibrary/IosLibrary/Share/Presentation/ShareSheetPresenter.swift:61`
  - `ios/IosLibrary/IosLibrary/Share/Presentation/ShareSheetPresenter.swift:77`
- 問題: 設計書は `completionWithItemsHandler` のコールバックキュー差異に備え、guard 判定と resume を main actor 上で実行することを求めています。実装は `present` メソッド自体を `@MainActor` にしていますが、`completionWithItemsHandler` 内では `resumeOnce(...)` を直接呼んでおり、callback が main actor 外から呼ばれた場合の再隔離がありません。
- 影響: UIKit が main thread で呼ぶ前提に依存しており、設計書で明示した Swift concurrency 警告・データ競合回避策としては弱いです。
- 修正案: `completionWithItemsHandler` 内を `Task { @MainActor in ... }` で包む、または `@MainActor` helper に寄せて、`hasResumed` の読み書きと continuation resume を main actor isolation 内に固定してください。

### M2. 実装結果レポートが pbxproj 変更を「既存変更なし」としている

- 対象:
  - `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v1.md:55`
  - `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v1.md:57`
  - `ios/IosLibrary/IosLibrary.xcodeproj/project.pbxproj`
  - `ios/UnityIosPlugin/UnityIosPlugin.xcodeproj/project.pbxproj`
- 問題: 実装結果では既存ファイル変更なし、pbxproj 手動追記不要と記載されていますが、develop 差分では両 xcodeproj の `CURRENT_PROJECT_VERSION` が更新されています。
- 影響: 実装 artifact と実差分のトレーサビリティがずれます。リリース番号や build number の意図確認にも影響します。
- 修正案: 実装結果の「既存変更」に xcodeproj の build version 変更を追記し、意図した変更か、ビルド時の副作用なら戻すかを明確にしてください。

## 軽微な指摘（low）

### L1. iOS ログルールの DoD が一部未達

- 対象:
  - `agent-rules/coding-rules/ios.md:11`
  - `agent-rules/coding-rules/ios.md:31`
  - `ios/IosLibrary/IosLibrary/Share/Application/UseCase/ShareUseCases.swift:21`
  - `artifact/results/share/2026-07-04-ios-share-implementation-feature-result-v1.md:175`
- 問題: iOS ルールは public / internal Swift 関数の先頭ログを求めていますが、`ShareContentUseCase.execute(content:)` に `Log.d` がありません。実装結果では「全 public/@objc/Bridge 関数に先頭 Log.d/Log.e が付与」となっています。
- 影響: 動作には影響しませんが、プロジェクトルールと DoD の記述に対して不一致です。
- 修正案: UseCase に `TAG` と先頭ログを追加するか、UseCase は既存 Notification 実装と同様にログ対象外とするなら DoD / ルール側に例外を明記してください。

## 設計書整合性チェック

- 企画書との整合性: ○
- Clean Architecture 準拠: ○
- 既存実装との差分分析の正確性: △（pbxproj 変更が実装結果に未記載）
- テスト設計の網羅性: △（Bridge callback thread 契約と Presenter main actor resume guard の検証が不足）
- ドメインエラー全ケース実装: ○
- エラーコード/メッセージ対応表との整合: ○

## プロジェクトルール適合チェック

- common.md 準拠: ○
- ios.md 準拠: △（public UseCase のログ不足、callback thread 契約未保証）
- エラー契約反映: ○
- 既存 API 互換性: △（新規 API の公開ヘッダ thread 契約と実装が不一致）

## テストカバレッジ

カバーできている観点:

- UseCase 正常系・異常系・items 空
- Manager 完了・キャンセル・失敗
- `ShareError` 全ケースの英語メッセージ
- Data 層の URL scheme 検証、file/image 変換、excluded activity 変換、primary item 置き換え
- JSON Parser の正常系、未知 type / value 欠落、invalid JSON、任意項目

不足している観点:

- Bridge callback が公開ヘッダどおり main thread で呼ばれること
- JSON 不正時の `UnityIosShareManager.share` callback 契約
- `completionWithItemsHandler` からの resume guard が main actor 上で行われること
- 実機/シミュレータでの共有シート表示、iPad popover、各共有先の実受領、previewTitle 表示
- Unity C# 側からの P/Invoke 実呼び出し

## 総合評価

要修正（重大）

実装の大半は設計に沿っていますが、公開 Bridge 契約の callback thread 保証が実装されていない点は修正必須です。あわせて Presenter の continuation resume guard を設計どおり main actor 上に固定すれば、実装リスクの中心はかなり収まります。
