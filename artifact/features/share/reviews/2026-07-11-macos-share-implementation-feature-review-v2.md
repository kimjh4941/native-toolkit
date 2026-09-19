# macOS Share 実装レビュー結果 v2

- 日付: 2026-07-11
- ブランチ: `feature/NTKIT-11`
- 対象実装結果: `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v2.md`
- 対象設計書: `artifact/designs/share/2026-07-11-macos-share-design.md`
- 前回レビュー: `artifact/reviews/share/2026-07-11-macos-share-implementation-feature-review-v1.md`
- 比較範囲: `develop...HEAD` は空。ローカル未追跡の Share 実装ファイルと v2 実装結果 artifact を対象に再レビュー。

## レビュー概要

v1 の High 2件への反映状況を中心に確認した。

- v1 High: picker / Unity Bridge の実 UI 検証未完了 -> **未解決（継続）**
- v1 High: 多重起動で continuation が上書きされる -> **コード上は解消**

## 重大な問題（high）

### 1. T5/T8 の必須完了条件である picker / Unity Bridge の実 UI 検証が未完了のまま残っている

- 設計書は T5 の完了条件として、実機での picker 表示・直接実行、`show()` を `mouseDown` 文脈で呼んだ場合の安定表示、分岐判断の確定を要求している: `artifact/designs/share/2026-07-11-macos-share-design.md:816`
- T8 も Unity Bridge 経由で picker が `mouseDown` 制約を満たして安定表示できること、満たせない場合は代替分岐を採用することを完了条件にしている: `artifact/designs/share/2026-07-11-macos-share-design.md:819`
- v2 実装結果自身も「T5/T8 の mouseDown 実UI検証は、本セッションでは完了できなかった」と明記している: `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v2.md:41`, `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v2.md:42`
- DoD でも picker 表示と Unity Bridge 経由起動は `△` のまま: `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v2.md:93`, `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v2.md:95`
- 設計書にも、分岐 A を実証的には確定できておらず、実機再検証が必要と追記されている: `artifact/designs/share/2026-07-11-macos-share-design.md:832`

影響: v2 は未完了理由と安全側の運用を明確化しているが、設計が T5/T8 の完了条件として要求していた「実 UI での picker / Unity Bridge 安定表示確認」は満たしていない。したがって、この実装を「T5/T8 完了」として次工程へ進める判断はまだ危険。

推奨対応:
- 実 Mac で人手クリックまたは Accessibility 権限付き UI 自動化により、`shareContent` の picker 表示・選択・キャンセル・callback 返却を確認する。
- 検証できるまでは、実装結果の採用判断を「picker は best-effort / 実機検証待ち」と明示して進める。
- 不安定なら設計書 §12 の分岐 B/C を正式採用し、DoD と公開 API の主経路を更新する。

## 改善提案（medium）

### 1. `SharePickerPresenterTests` が `alreadyInProgress` そのものを検証していない

- `presentPickerThrowsAlreadyInProgressWhenBusy` は `#expect(throws: ShareError.self)` のため、busy guard が壊れて `noAnchorView` 等の別 `ShareError` が投げられてもテストが通る: `mac/MacLibrary/MacLibraryTests/Share/SharePickerPresenterTests.swift:22`, `mac/MacLibrary/MacLibraryTests/Share/SharePickerPresenterTests.swift:23`
- `performServiceThrowsAlreadyInProgressWhenBusy` も同様に、`serviceUnavailable` 等の別 `ShareError` でも合格し得る: `mac/MacLibrary/MacLibraryTests/Share/SharePickerPresenterTests.swift:35`, `mac/MacLibrary/MacLibraryTests/Share/SharePickerPresenterTests.swift:36`
- 実装コード自体は `continuation == nil` guard で `.alreadyInProgress` を throw しており、v1 の continuation 上書き問題はコード上解消している: `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:77`, `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:79`, `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:99`, `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:101`

推奨対応:
- `#expect(throws:)` の matcher で `ShareError.alreadyInProgress` と完全一致することを検証する。
- `ShareError` が `Equatable` でないため直接比較しにくい場合は、捕捉した error を `ShareError` に cast し、`errorCode == 1408` または `errorMessage` を検証する。

## 軽微な指摘（low）

なし。

## 前回指摘の状態

- v1 High 1: T5/T8 の実 UI 検証未完了 -> **未解決**。未完了理由とリスクは v2 で明確化されたが、完了条件自体は満たしていない。
- v1 High 2: continuation 上書き -> **解消**。`ShareError.alreadyInProgress` と busy guard が追加され、既存 continuation を上書きしない実装になった。

## 設計書整合性チェック

- 企画書との整合性: △（picker の mouseDown 制約は未検証のまま）
- Clean Architecture 準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △（busy guard のテスト期待値が広い。実 UI は未実施）
- ドメインエラー全ケース実装: ○（`.alreadyInProgress` 追加含む）
- エラーコード/メッセージ対応表との整合: ○（1408 追加とテストを確認）

## プロジェクトルール適合チェック

- common.md 準拠: ○
- mac.md 準拠: ○
- エラー契約反映: ○
- 既存 API 互換性: ○（新規エラー追加のみ。既存 API 形状は維持）

## テストカバレッジ

確認済み:
- `ShareError.alreadyInProgress` の code/message テスト
- `SharePickerPresenter` の busy 状態での throw テスト
- UseCase / Manager / Converter / Parser の既存テスト

不足:
- `SharePickerPresenterTests` は throw される具体ケースが `.alreadyInProgress` であることを厳密に検証していない。
- 実 UI / Unity Bridge 経由の picker 表示、mouseDown 文脈、選択・キャンセル・callback 返却は未検証。

## 実行した検証

- `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary -destination 'platform=macOS' test` -> 成功
- `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS' test` -> 成功

## 総合評価

**要修正（重大）**。

多重起動による continuation 上書きは解消している。一方で、設計上の必須完了条件だった T5/T8 の実 UI 検証は v2 でも未完了であり、picker 方式を完了済みとして扱うにはまだ足りない。加えて busy guard の回帰テストは、具体的な `.alreadyInProgress` を検証するように締めるのが望ましい。
