# iOS Clipboard 実装レビュー v5

## レビュー対象

- 日付: 2026-08-08
- 対象OS: iOS 18以降
- ブランチ: `feature/NTKIT-14`
- 比較差分: `develop...feature/NTKIT-14` と未コミットのv1〜v5修正差分
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v5.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v4.md`
- 追加参照: `artifact/MIGRATION.md`

## レビュー概要

- result v5の自主訂正は正しい。Swift 5 + strict concurrency + whole-module + clean buildで、修正前のClipboard診断19件と、局所修正後に残る16件の内訳を再現した。
- `IosClipboardManager`は`Notification`から`[String]`をactor境界の外で抽出するようになり、`MainActor.assumeIsolated`による同期配信と順序性を維持しながら診断を解消している。
- `UnityIosClipboardJsonParser`は共有`ISO8601DateFormatter`をSendableな`Date.ISO8601FormatStyle`へ置換し、2件の診断を解消している。
- 過去result v2〜v4とreview v4のErrataは、監査性を残して誤評価を明示する方式として妥当である。
- IosLibrary 186件、UnityIosPlugin 73件、失敗0を再現した。
- ただし、`UnityIosClipboardManager`に16件の`sending 'handler'`診断が残る。すべてNTKIT-14が`develop`へ追加する新規診断であり、baselineへ取り込めないため受け入れブロッカーである。

## 重大な問題（high）

### H-01: Bridge callbackのactor境界が未解決で、Clipboard差分が16件のstrict診断を追加する

- `UnityIosClipboardManager`は任意スレッドから受け取った非Sendableなcallbackを`Task { @MainActor in }`へ渡しており、Swift 5 strict buildで16件の`sending 'handler'`診断が出る。
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:51`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:79`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:99`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:289`
- Swift 6ではerrorになる契約違反候補であり、設計I-10と、設計v5で予定する「Clipboard差分が新規strict診断を追加しない」というDoDの双方に未達である。
- `artifact/MIGRATION.md`のBridge callback actor-boundary先行設計で案A / Bを比較し、決定した共通方針をClipboardへ適用して16件を0にする必要がある。
- 修正後はSwift 5 strict whole-module clean buildでClipboard診断0件を確認し、全endpointのcallbackがmain threadでexactly-once、nil callback、C文字列・block寿命、start/stop観測境界を保つテストを追加すること。

## 改善提案（medium）

### M-01: ISO 8601シリアライズ側の回帰テストがない

- formatter置換はparseだけでなく`serializeDetectedValues`の`calendarEvents.startDate` / `endDate`出力も変更している。
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:276`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:289`
- 現在のテストはexpirationDateの入力parseだけを検証し、シリアライズ結果の小数秒、UTC表現、nilの扱いを固定していない。
  - `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardJsonParserTests.swift:59`
- `ClipboardDetectedValues`へcalendar eventを設定し、開始・終了日時が小数秒付きISO 8601として出力され、再parse可能であることを追加テストで固定するとよい。

### M-02: Swift 5 / Swift 6診断の比較母集団と「unique」の定義を揃える必要がある

- result v5はiOSのSwift 5 strict 129件と、iOS 13件 + macOS 8件のSwift 6診断21件を直接比較し、差分を早期停止分としている。対象platform / schemeが一致しないため、この差分をそのまま未診断数とは評価できない。
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v5.md:83`
  - `artifact/MIGRATION.md:206`
- 比較はiOS 129対iOS 13、またはmacOSのSwift 5 readinessも取得したうえでApple全体同士に揃える必要がある。
- 独立再計測した修正後126件は、full source-location行を`sort -u`した場合、`sending` 39、`static property` 14、その他73だった。MIGRATION.mdの「sending 34 / static property 8」は別の正規化単位に見えるため、baseline schema確定前は「出現」と断定せず、unique keyの定義または集計コマンドを明記すること。
  - `artifact/MIGRATION.md:147`
  - `artifact/MIGRATION.md:162`

## 軽微な指摘（low）

### L-01: `isolated deinit`の個別評価までErrataで撤回している

- result v4の「新規追加した`isolated deinit`は新たな診断を発生させていない」という個別主張は、Clipboard全体に別診断が19件あったこととは独立しており、現在も成立する。
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v4.md:6`
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v5.md:26`
- Errataは「Clipboard全体が0件という根拠にはならない」と限定し、deinit自体の評価は撤回しない方が正確である。

### L-02: xcframework生成後のbuild numberをresult v5へ記録するとよい

- 現在値はIosLibrary 12、UnityIosPlugin 11で、xcframework生成によりv4時点の11 / 10から増えている。
- 生成成功だけでなく最終値もresult v5へ記録すると、前回レビューL-01と同じ追跡性を維持できる。

## 設計書整合性チェック

- 企画書との整合性: △ — T-00 / T-13の実機確認が未実施
- Clean Architecture準拠: ○
- 既存実装との差分分析の正確性: △ — strict診断は訂正されたが、診断比較の母集団と集計定義に修正余地あり
- テスト設計の網羅性: △ — unit testsはgreenだが、Bridge 16件、ISO 8601出力、I-08 / I-09が未達
- ドメインエラー全ケース実装: ○
- エラーコード/メッセージ対応表との整合: ○

## プロジェクトルール適合チェック

- common.md準拠: △ — callbackのactor/thread契約が16件のstrict診断を残している
- ios.md準拠: ○
- エラー契約反映: ○
- 既存API互換性: ○ — 今回の局所修正は公開signatureを変更していない。Bridge先行設計では再確認が必要

## テストカバレッジ

### カバーできている観点

- expirationDate入力のISO 8601小数秒あり / なしと不正値
- observer通知payloadのSendable化後も既存manager testsがgreen
- 既存のcancel / timeout / exactly-once / resource cleanup
- IosLibrary 186件、UnityIosPlugin 73件

### 不足している観点

- Bridge callback actor-boundaryの全15 endpoint
- callbackのmain-thread / exactly-once / nil / lifetime契約
- calendar event日時のISO 8601シリアライズ形式
- I-08 Bridge end-to-end
- I-09 `ClipboardRedaction`独立module境界
- T-00 / T-12 / T-13

## 検証結果

- `git diff --check`: 問題なし
- Swift 5 + strict whole-module clean build: 成功、source warning 126件、Clipboard 16件
- Clipboard診断: `UnityIosClipboardManager`の`sending 'handler'`系16件のみ
- IosLibrary tests: 186件、失敗0（iPhone 17 Pro / iOS 26.2 Simulator）
- UnityIosPlugin tests: 73件、失敗0（iPhone 17 Pro Max / iOS 26.2 Simulator）
- xcframework: ユーザー報告では両モジュール成功。レビューでは再生成していない

## 総合評価

**要修正（重大）**

局所修正3件、Errata、result v5の主要な訂正判断は妥当である。しかし、NTKIT-14が追加するBridge callback診断16件が残り、Swift 6ではerrorになる。MIGRATION.mdで定義した先行設計を実施し、Clipboardへ適用して診断0件とcallback契約を検証するまで受け入れできない。併せてISO 8601出力テストと診断集計文を修正してから再レビューが必要である。
