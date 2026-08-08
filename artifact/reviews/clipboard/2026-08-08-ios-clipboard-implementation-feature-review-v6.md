# iOS Clipboard 実装レビュー v6

## レビュー対象

- 日付: 2026-08-08
- 対象OS: iOS 18以降
- ブランチ: `feature/NTKIT-14`
- 比較差分: `develop...feature/NTKIT-14` と未コミットのv1〜v6修正差分
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v5.md`
- 追加参照: `artifact/MIGRATION.md`

## レビュー概要

- handlerへの`@Sendable`付与により、Swift 5 + strict concurrency + whole-module + clean buildのClipboard診断が16件から0件になったことを独立再計測で確認した。案Cはclosureをactor間で安全に運ぶための型契約として妥当であり、保持してよい。
- ISO 8601のシリアライズ回帰テストは、小数秒、UTC、`nil`、元の`Date`との往復一致を固定しており、前回M-01を解消している。
- 診断比較の母集団、`isolated deinit`のErrata範囲、build numberの記録も前回指摘を概ね解消している。
- UnityIosPlugin tests 79件、失敗0を再現した。
- ただし、`@Sendable`はcallbackの実行executorをmain actorへ固定しない。不正requestの早期return経路はhandlerを呼出元スレッドで同期実行しており、任意スレッドから不正入力を渡すとmain-thread契約に違反する。新規テストは「background正常系」と「不正入力」を別々に検証しているため、この組合せを検出できていない。

## 重大な問題（high）

### H-01: 不正requestのcallbackが呼出元スレッドで実行され、全経路main-thread契約が未達

- façade、Bridge header、設計書はいずれもcallbackを全経路でmain thread / main actorから1回だけ呼ぶと規定している。
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:16`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManagerBridge.h:13`
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:1000`
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:1154`
- 正常系は`Task { @MainActor in ... }`へ入るが、parse / validation失敗はその前にhandlerを直接呼んでいる。したがってC entry pointまたはSwift façadeがbackground threadから不正requestを受けると、callbackもbackground threadで実行される。
  - operation callback: `copy`の`deliverInvalidRequest`、`append`のoptions拒否、`clear`、`removePasteboard`、`startObserving`
    - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:42`
    - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:74`
    - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:285`
    - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:345`
  - JSON callback: `read`、`readData`、`getSnapshot`、`createPasteboard`、`detectPatterns`、`detectValues`、`loadItem`、`checkForegroundChange`
    - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:95`
    - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:133`
    - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:315`
- 新規の正常系テストはbackgroundから呼び、main threadをassertしている。一方、不正requestテストはテスト実行threadから直接呼び、回数しかassertしていない。observeの不正requestも同様である。
  - `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardManagerCallbackContractTests.swift:48`
  - `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardManagerCallbackContractTests.swift:65`
  - `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardManagerCallbackContractTests.swift:111`
- result v6の「Bridge callbackがmain threadでexactly-once」と「H-01解消」は、診断解消については正しいが、実行時契約については成立しない。
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md:183`
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md:215`

**修正方針**

- 案Cの`@Sendable`は維持し、すべての早期失敗callbackも`Task { @MainActor in ... }`またはmain-actor-isolatedな共通delivery helperを経由させる。
- operation callbackとJSON callbackの両方に共通delivery helperを設け、`append`のoptions拒否を含む直接呼出しを残さない。
- background queueからmalformed requestを渡すテストを少なくとも次の3分類で追加し、回数1とmain threadを同時にassertする。
  1. operation callback（例: `copy`）
  2. JSON callback（例: `getSnapshot`）
  3. observe開始失敗（startHandler 1回、changeHandler 0回）
- 修正後、正常・不正の両経路でcallbackのmain-thread / exactly-once契約を再確認する。

## 改善提案（medium）

### M-01: 「コンパイラが全呼び出し側で検証」はObjective-C callerには成立しない

- `@Sendable`はSwift側の型検査には有効だが、Objective-C blockのcaptureをSwift concurrency checkerが全件検証するものではない。Bridge `.m`がC関数ポインタだけをcaptureしていることは、実装監査によって確認した安全性である。
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md:28`
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md:39`
- result v6とMIGRATION.mdは「Swift callerはコンパイラが検証し、Objective-C callerはblock capture監査とBridgeテストで担保する」と区別すると正確である。

### M-02: MIGRATION.mdの129件とカテゴリ内訳126件が同じ観測段階として並んでいる

- §4.2は冒頭で初期観測値129件、Clipboard 19件を示しているが、カテゴリ表は`32 + 17 + 14 + 13 + 11 + 7 + 32 = 126`件である。
  - `artifact/MIGRATION.md:147`
  - `artifact/MIGRATION.md:163`
- カテゴリ表は局所3件修正後の126件を示しているように見える。初期129件の内訳へ直すか、「局所3件修正後・126件」と段階を明記し、領域別129件の表と混在させないこと。

## 軽微な指摘（low）

### L-01: result v6の「修正前126件」は段階名が不正確

- 同じresult内の検証表ではv4時点129件、局所3件修正後126件としているため、「修正前126件」は案C適用前という意味でも曖昧である。
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md:100`
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v6.md:152`
- 「局所3件修正後（案C適用前）126件」と記載すると観測段階が一意になる。

## 設計書整合性チェック

- 企画書との整合性: △ — T-00 / T-13の実機確認が未実施
- Clean Architecture準拠: ○
- 既存実装との差分分析の正確性: △ — strict診断0は正しいが、callback runtime契約と診断表の段階表記に誤りがある
- テスト設計の網羅性: △ — unit testsはgreenだが、background + malformedの組合せ、I-08 / I-09が未達
- ドメインエラー全ケース実装: ○
- エラーコード/メッセージ対応表との整合: ○

## プロジェクトルール適合チェック

- common.md準拠: ○
- ios.md準拠: ○
- エラー契約反映: ○
- 既存API互換性: ○ — `@Sendable`付与後もObjective-C Bridgeはビルド成功。ただしmain-thread runtime契約の修正が必要

## テストカバレッジ

### カバーできている観点

- Swift 5 strict whole-module clean buildでClipboard診断0件
- 正常requestをbackgroundから呼んだ場合のmain-thread / exactly-once
- malformed requestのexactly-once
- nil handler
- start / stopの正常系境界
- calendar event日時のISO 8601シリアライズと元の`Date`への往復
- 既存のcancel / timeout / resource cleanup

### 不足している観点

- malformed requestをbackgroundから呼んだ場合のmain-thread callback
- malformed observeをbackgroundから呼んだ場合のstartHandler main-thread / changeHandler非配信
- operation / JSON callbackの全早期失敗分岐
- I-08 Bridge 15 endpoint end-to-end
- I-09 `ClipboardRedaction`独立module境界
- T-00 / T-12 / T-13

## 検証結果

- `git diff --check`: 問題なし
- Swift 5 + strict whole-module clean build: 成功、source warning 110件、Clipboard 0件
- UnityIosPlugin tests: 79件、失敗0（iPhone 17 Pro Max / iOS 26.2 Simulator）
- IosLibrary tests: result v6では186件、失敗0。レビューv5で同件数を再現済みで、今回のv6差分にIosLibrary実装変更がないため再実行していない
- xcframework: ユーザー報告では両モジュール成功。レビューでは再生成していない

## 総合評価

**要修正（重大）**

案CによってClipboardのstrict診断16件を0件にした点は正しく、ISO 8601テストを含む前回指摘の大半も解消している。しかし、`@Sendable`はmain actor実行を保証せず、不正requestの早期returnではcallbackが呼出元threadで同期実行される。設計・Bridge headerが要求する「全経路main thread」に違反するため、H-01の受け入れブロッカーは実行時契約の観点で継続する。全早期失敗callbackをmain actorへ統一し、background + malformedの組合せテストを追加してから再レビューが必要である。
