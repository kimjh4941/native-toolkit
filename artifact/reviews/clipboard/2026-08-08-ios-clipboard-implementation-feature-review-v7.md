# iOS Clipboard 実装レビュー v7

## レビュー対象

- 日付: 2026-08-08
- 対象OS: iOS 18以降
- ブランチ: `feature/NTKIT-14`
- 比較差分: `develop...feature/NTKIT-14` と未コミットのv1〜v7修正差分
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v7.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v6.md`
- 追加参照: `artifact/MIGRATION.md`

## レビュー概要

- operation callback用とJSON callback用の`deliverOnMain`が追加され、早期失敗の直接callbackは解消されている。
- `deliverInvalidRequest`を共有するoperation系、`append`のoptions拒否、JSON callback 8箇所は、すべてmain actor deliveryを経由している。
- background caller + malformed requestを組み合わせた4分類の回帰テストは、回数1とmain threadを同時に検証しており、前回H-01を再現可能な形で固定している。
- Swift 5 strict whole-module clean buildは成功し、unique source warning 110件、Clipboard 0件を独立再現した。
- UnityIosPlugin tests 83件、失敗0を独立再現した。
- コード上の受け入れブロッカーは解消した。残るのはMIGRATION.mdの案C比較表に旧評価が残る文書上の矛盾と、result v7の経路数表記のみである。

## 重大な問題（high）

なし。

## 改善提案（medium）

### M-01: MIGRATION.mdの案C比較表が、直後の正しい担保範囲と矛盾している

- §6の案C評価には、現在も「実行時の変更ゼロ。コンパイラが全呼び出し側で検証する」と記載されている。
  - `artifact/MIGRATION.md:486`
- 直後の担保範囲では、Objective-C callerにコンパイラ検証は及ばず、capture監査とBridge契約テストで担保すると正しく訂正されている。
  - `artifact/MIGRATION.md:495`
  - `artifact/MIGRATION.md:500`
- また、最終的に採用した解決策は`@Sendable`だけでなくmain-actor delivery helperを含み、早期失敗callbackの実行threadを変更している。案C単体の型注釈は実行時変更ゼロでも、NTKIT-14へ適用した全体は実行時変更ゼロではない。
- 案Cの評価を次の趣旨へ更新すると決定記録が一貫する。
  - Swift callerのclosure transferはコンパイラが検証する
  - Objective-C callerはcapture監査とBridge契約テストで担保する
  - main-thread実行は別契約であり、全delivery経路をmain actorへ統一する

## 軽微な指摘（low）

### L-01: result v7の「早期失敗10経路」はcallsite数と公開経路数を区別するとよい

- 実装修正箇所としては、共通`deliverInvalidRequest`内部1箇所、append options拒否1箇所、JSON 8箇所で計10 callsiteである。
- 公開endpoint上の早期失敗分岐は、共通helperを使う`copy`、`append` parse失敗、`clear`、`removePasteboard`、`startObserving`の5経路に、append options拒否1経路、JSON 8経路を加えた14経路である。
- result v7の適用表はoperation parse失敗から`append`を落としている。
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v7.md:55`
- 「実装callsite 10箇所、公開早期失敗分岐14経路」と区別し、表へ`append` parse失敗を追加すると監査範囲が明確になる。実装自体に漏れはない。

## 設計書整合性チェック

- 企画書との整合性: △ — T-00 / T-13の実機確認が未実施
- Clean Architecture準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △ — H-01回帰観点は解消。I-08 / I-09、実機確認が未達
- ドメインエラー全ケース実装: ○
- エラーコード/メッセージ対応表との整合: ○

## プロジェクトルール適合チェック

- common.md準拠: ○ — callbackの完了threadとexactly-once契約を実装・テストで固定
- ios.md準拠: ○
- エラー契約反映: ○
- 既存API互換性: ○ — Objective-C Bridgeは無変更でビルド成功

## テストカバレッジ

### カバーできている観点

- 正常requestをbackgroundから呼んだ場合のmain-thread / exactly-once
- malformed operation requestをbackgroundから呼んだ場合のmain-thread / exactly-once
- append options拒否の独立guard
- malformed JSON callback requestのmain-thread / exactly-once
- malformed observeのstartHandler 1回 / main threadとchangeHandler 0回
- nil handler
- start / stop正常系境界
- calendar event日時のISO 8601往復
- 既存cancel / timeout / resource cleanup

### 不足している観点

- I-08 Bridge 15 endpoint end-to-end
- I-09 `ClipboardRedaction`独立module境界
- T-00 / T-12 / T-13

## 検証結果

- `git diff --check`: 問題なし
- Swift 5 + strict whole-module clean build: BUILD SUCCEEDED、unique source warning 110件、Clipboard 0件
- UnityIosPlugin tests: 83件、失敗0（iPhone 17 Pro Max / iOS 26.2 Simulator）
- IosLibrary tests: 本ラウンドではIosLibrary実装変更がないため再実行していない。result v7は186件、失敗0を記録
- xcframework: ユーザー報告では両モジュール成功。レビューでは再生成していない

## 総合評価

**要修正（軽微）**

前回H-01の実行時不具合は解消され、回帰テストとstrict診断の双方で確認できた。Clipboard実装コードに新たな重大・中程度の問題は見つからず、受け入れブロッカーは解消済みである。MIGRATION.mdの案C比較表に残る旧評価を後段の正しい担保範囲へ合わせ、result v7のcallsite数と公開経路数を区別すればLGTMと判断できる。
