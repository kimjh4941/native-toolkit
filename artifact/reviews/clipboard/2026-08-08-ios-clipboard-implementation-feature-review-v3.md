# iOS Clipboard 実装レビュー v3

## レビュー対象

- 日付: 2026-08-08
- 対象OS: iOS 18以降
- ブランチ: `feature/NTKIT-14`
- 比較差分: `develop...feature/NTKIT-14` と未コミットのv1〜v3修正差分
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v3.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v2.md`

## レビュー概要

- v2のH-01は解消した。source size取得不能時はcopy開始前に`fileCopyFailed`となり、oversize、image境界、temp cleanupのテストも追加された。
- S11の内部cancel completionとUI callback抑止、`localOnly`既定値、ISO 8601小数秒有無、U-83、3者競合の修正を確認した。
- SimulatorテストはIosLibrary 184件、UnityIosPlugin 73件、失敗0を再現した。
- ただし、設計D-16で必須の`PasteItemProviderLoader.isolated deinit`が存在せず、raw factory経路でreceiver / loaderを解放した場合にpending provider loadと一時fileをcleanupできない。
- I-10の13 errorは再現したが、レポートのmodule別内訳と「通常build warning 0」は実測と一致しない。

## 重大な問題（high）

### H-01: `PasteItemProviderLoader`解放時にpending loadをcancelせず、一時fileが残りうる

- 設計D-16 / S6は`PasteItemProviderLoader`自身に`isolated deinit`を要求しているが、実装にはdeinitがない。
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:455`
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:766`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:21`
- 推奨container経路はcontainerのdeinitがreceiver経由でcancelするが、公開された`PasteControlFactory.makeComponents`経路ではreceiverの解放時cleanupを保証できない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteControlFactory.swift:16`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/ClipboardPasteReceiverView.swift:30`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/ClipboardPasteControlContainerView.swift:83`
- provider completionは`ClipboardProviderLoadHandle`を強くcaptureする。loader解放後にfile loadが成功すると、handleのcompletion内の`[weak self]`は何も処理せず、成功fileは呼び出し側にも渡らずdiscardもされない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:104`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift:229`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift:283`
- `PasteItemProviderLoader`へ`isolated deinit { cancelAll() }`を追加し、loader / receiver解放後に遅延file completionが到着してもtemp directoryが空で、内部completionが`.cancelled`を1回受けるテストを追加する必要がある。設計U-95/U-138もこの経路を含めて確認すること。

## 改善提案（medium）

### M-01: strict errorのmodule別内訳がまだ誤っている

- whole-module strict buildで13 errorは再現したが、正しい内訳は次のとおり。
  - Dialog: 1件
  - Notification: 9件（`NotificationActionOptions` 3、`NotificationCategoryOptions` 4、`NotificationPermissionHelper.shared` 1、`IosNotificationManager.shared` 1）
  - Share: 3件（`ShareSheetPresenter` 2、`IosShareManager.shared` 1）
- v3レポートの「Dialog 1 / Notification 8 / Share 4」は合計こそ13だが分類が異なる。
  - `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v3.md:35`
- `ShareResult`の行は`ShareSheetPresenter` errorに対するnoteであり、独立errorではない。内訳を1 / 9 / 3へ訂正すること。

### M-02: 「通常ビルドのwarningは0件」は再現しない

- cleanなtest buildで、少なくとも既存機能由来の次のwarningを確認した。
  - `NotificationRepositoryImpl.swift:294`: `allowAnnouncement` deprecated
  - Unity schemeでは加えて`UnityIosNotificationManager.swift:169`: unknown valueを扱わないswitch（Swift 6ではerror）
- Clipboard由来warning 0という限定評価は妥当だが、target全体の通常warning 0とは区別して記載する必要がある。

### M-03: source size取得不能テストの失敗原因を明示的に固定するとよい

- `fileLoadFailsWhenTheSourceSizeCannotBeVerified`はdirectory URLを`NSItemProvider`へ渡している。現在は期待どおり失敗するが、provider自身のfile representation errorでも同じassertionを通過できる。
  - `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardProviderLoadExecutorTests.swift:234`
  - `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardProviderLoadExecutorTests.swift:253`
- error codeが`CLIPBOARD_FILE_COPY_FAILED`であることに加え、detailのtest-visible codeがpre-size検証用`-3`であること、またはresource-value readerを注入してcopy未呼び出しを直接検証すると回帰検出力が上がる。

## 軽微な指摘（low）

なし。

## I-10に関する判断

- **提案どおり、既存Dialog / Notification / ShareのSwift 6移行を別タスクへ切り出す方針でよい。**
- Clipboardタスクで既存3機能へ変更を広げると、設計DoDの「既存Notification / Dialog / Shareを変更しない」と衝突し、既存APIのactor isolationや挙動を別機能のレビューなしに変更することになる。
- 設計v4は次版へ改訂し、本タスクのI-10を次のように分離することを推奨する。
  1. Clipboard追加・変更sourceからSwift 6 strict error / warningを新規発生させない。
  2. target全体の既存13 errorと既存warningはbaselineとして列挙し、別タスクIDへリンクする。
  3. 将来の全module strict-greenは別タスクのDoDとして維持する。
- 単純な`grep Clipboard == 0`だけではcompilerの早期停止時に未診断となる可能性があるため、whole-module buildとbaseline差分比較を検証手順にすること。

## 設計書整合性チェック

- 企画書との整合性: △ — 実機T-00 / T-13が未実施
- Clean Architecture準拠: ○
- 既存実装との差分分析の正確性: △ — strict内訳と通常warning記録に誤りあり
- テスト設計の網羅性: △ — v2残件は大きく改善したが、loader解放cleanup、I-08 / I-09、実機確認が未達
- ドメインエラー全ケース実装: ○
- エラーコード/メッセージ対応表との整合: ○

## プロジェクトルール適合チェック

- common.md準拠: △ — 非同期契約は改善したが、loader解放時のresource cleanupが不足
- ios.md準拠: ○ — v2で指摘した新規internal APIの先頭ログは反映済み
- エラー契約反映: ○
- 既存API互換性: ○

## テストカバレッジ

### カバーできている主な観点

- pre-copy size検証、oversize拒否、image / file境界、cancel / timeout後cleanup
- S11内部`.cancelled` exactly-onceとUI callback抑止の分離
- 空providerのU-83 / U-89責務分離
- completion / cancel / timeoutの3到着順
- `localOnly`既定値と型不正
- expirationDateの小数秒あり / なしとinvalid値
- observerの基本的なstop/start、重複抑止

### 不足している主な観点

- `PasteItemProviderLoader` / raw receiver解放時のpending cancelと遅延file cleanup
- queue済み旧observer eventのgeneration gate直接再現（制約は適切に記録済み）
- I-08 Bridge 15 endpoint end-to-end
- I-09 ClipboardRedaction独立module境界テスト
- I-10 full-module strict-green
- T-00 / T-12 / T-13と実機M-01〜M-16

## 検証結果

- `git diff --check`: 問題なし
- IosLibrary tests: 184件、失敗0（iPhone 17 Pro / iOS 26.2 Simulator）
- UnityIosPlugin tests: 73件、失敗0（iPhone 17 Pro Max / iOS 26.2 Simulator）
- IosLibrary whole-module Swift 6 strict build: 失敗（exit 65、既存機能由来13 error）
- Clipboard pathを発生元とするstrict errorは確認されなかった
- 通常test build: 成功。ただし既存Notification / Unity Notification warningを確認

## 総合評価

**要修正（重大）**

v2指摘の実装修正と追加テストは概ね適切である。ただし、設計で明示されたPresentation loader自身のdeinit cleanupが欠落し、raw factory利用時にpending file loadの成果物が未配信・未削除となりうる。H-01を修正し、結果レポートのstrict内訳と通常warning記録を訂正してから再レビューが必要である。
