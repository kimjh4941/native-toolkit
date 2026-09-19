# 実装結果レポート v2（レビュー指摘反映）

## 基本情報

- 日付: 2026-07-11
- 機能名: share
- 対象OS: macOS
- 設計書: artifact/designs/share/2026-07-11-macos-share-design.md
- 対象レビュー: artifact/reviews/share/2026-07-11-macos-share-implementation-feature-review-v1.md
- 対象実装結果（前版）: artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v1.md
- ブランチ: feature/NTKIT-11

本ファイルは v1 を置き換えるものではなく、レビュー v1 で指摘された 2 件（High×2）への対応結果を記録する。

---

## 1. レビュー指摘への対応サマリー

### 1.1 High: 共有処理の多重起動で continuation が上書きされる問題 — 対応済み

- 問題: `SharePickerPresenter` は単一の `continuation` スロットを進行中チェックなしに再代入しており、多重起動（連打・Unity 側二重呼び出し・picker 表示中の direct service 呼び出し等）で先行操作の callback/async が失われる可能性があった。
- 対応:
  - `ShareError` に `.alreadyInProgress`（errorCode 1408, "A share operation is already in progress."）を追加した。
  - `SharePickerPresenter.presentPicker` / `performService` の先頭（AppKit 操作より前）に `guard continuation == nil else { throw ShareError.alreadyInProgress }` を追加し、進行中の操作がある場合は新規呼び出しを即座に拒否するようにした。既存の継続を上書きすることはなくなった。
  - `resume(_:)` ヘルパー自体は変更なし（`continuation` を nil 化してから 1 回だけ resume する既存の安全性は維持）。
- 回帰テスト:
  - `mac/MacLibrary/MacLibraryTests/Share/SharePickerPresenterTests.swift`（新規）: `presentPickerThrowsAlreadyInProgressWhenBusy` / `performServiceThrowsAlreadyInProgressWhenBusy` の 2 件。`SharePickerPresenter` の module-internal テスト専用ヘルパー（`beginInFlightForTesting()` / `resumeInFlightForTesting(_:)`、いずれも AppKit に依存しない）で「進行中」を模擬し、2 回目の呼び出しが即座に `ShareError.alreadyInProgress` を throw することを確認した。
  - `ShareErrorTests.swift` に `alreadyInProgressHasCode1408` / `alreadyInProgressMessage` を追加。
  - 全 88 件（新規 4 件含む）が green。詳細は 3 章参照。

### 1.2 High: T5/T8 の picker / Unity Bridge 実UI検証（mouseDown 制約）— 未解決。実施できなかった理由と対応方針を記録

- 対応試行の経緯:
  1. `MacLibraryExample` に一時的な検証用ビュー（Share ボタン1つ + 結果表示ラベル）を追加し、実際にビルド・起動して実機で動作するアプリとして起動した（起動自体は成功）。
  2. `osascript`（System Events）でボタンへの実クリックを自動化しようとしたが、`osascript is not allowed assistive access (-1728)` により失敗した。このサンドボックス環境には Accessibility 権限（UI 自動操作の許可）が付与されておらず、対話的な承認（System Settings でのユーザー操作）なしに権限を取得する手段がない。
  3. 権限の有無を確認するために TCC（Transparency, Consent, and Control）データベースを直接照会しようとしたが、ユーザーのプライバシー関連システムデータへの不適切なアクセスであるため中止した。
  4. 上記により、実際のマウスクリック（真の `mouseDown` イベント）でピッカー表示を検証する自動化された手段はこの環境には存在しないと判断した。検証用の一時ファイル・一時変更（`TempShareMouseDownVerify.swift` 追加、`MacLibraryExampleApp.swift` の一時的な差し替え）はすべて `git checkout` / 削除で元に戻し、リポジトリには残していない（`git status` で確認済み）。
- 実装コードの精査で判明した具体的な追加リスク（新規発見。設計書 §12 に追記済み）:
  - `MacShareManager.share(content:completion:)` / `share(content:serviceName:completion:)` は内部で `Task { @MainActor in ... }` を経由してから picker/service を呼ぶ。Swift の並行性モデルはこの `Task {}` が呼び出し元と同一コールスタック上で同期的に実行されることを保証しない。したがって、たとえ Unity/native 側が実際のボタン mouseDown ハンドラから同期的に `share(content:completion:)` を呼んだとしても、内部の `Task {}` によって `NSSharingServicePicker.show(...)` の呼び出しが mouseDown コンテキストから外れてしまう可能性が構造的に残る。
  - この点は実装時に新たに判明した知見であり、設計書のレビュー時点（設計フェーズ）では明示されていなかった。`MacShareManager.swift` の DocC コメントに追記し、設計書 §12（リスク表）・§14（要検証）にも反映した。
- 現時点の結論と対応方針:
  - **T5/T8 の mouseDown 実UI検証は、本セッションでは完了できなかった。** 実機・実ユーザー操作（またはユーザー自身による Accessibility 権限の付与）が必要な、コードでは閉じられない検証項目として明示的に「未完了」のまま記録する。
  - 安全側の運用として、確実性が求められる呼び出し元には **`shareViaService`（個別サービス直接実行）を推奨経路とする**注記を `MacShareManager` の DocC コメントに追加した（設計書の分岐Bに相当する注意喚起。コードの構造自体は変更していない — pickerモードのAPIは維持しつつ、リスクを文書化した）。
  - DoD 該当項目は v1 の `△` から実質的な状態は変わっていないが、判定根拠（なぜ実機必須か、何を試して何が阻害要因だったか）を明確化した。4章参照。

---

## 2. 変更ファイル（v1 からの追加差分）

### 2.1 新規作成

- `mac/MacLibrary/MacLibraryTests/Share/SharePickerPresenterTests.swift`

### 2.2 既存変更

- `mac/MacLibrary/MacLibrary/Share/Domain/Error/ShareError.swift`: `.alreadyInProgress` ケース追加（errorCode 1408）
- `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift`: `presentPicker`/`performService` に busy-guard 追加、テスト専用ヘルパー（`beginInFlightForTesting`/`resumeInFlightForTesting`）追加、ドキュメントコメント更新
- `mac/MacLibrary/MacLibrary/Share/MacShareManager.swift`: DocC コメントに `Task { @MainActor }` の mouseDown リスクと `shareViaService` 推奨を追記（コードロジックは無変更）
- `mac/MacLibrary/MacLibraryTests/Share/ShareErrorTests.swift`: `alreadyInProgress` のテスト2件追加
- `artifact/designs/share/2026-07-11-macos-share-design.md`: §12 リスク表・§14 要検証に、実装で判明した `Task {}` hop リスクと実機検証未完了の記録を追記

### 2.3 一時作成後に削除・復元済み（リポジトリに残っていない）

- `mac/MacLibraryExample/MacLibraryExample/TempShareMouseDownVerify.swift`: 検証用に作成、検証断念後に削除
- `mac/MacLibraryExample/MacLibraryExample/MacLibraryExampleApp.swift`: 検証用に一時差し替え、`git checkout` で復元（`git status` で無差分を確認済み）

---

## 3. ビルド・テスト結果

- 実行コマンド:
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary -configuration Debug build`
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary -destination 'platform=macOS' test`
  - `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS' test`
- 結果: すべて SUCCESS
  - MacLibrary ビルド: `** BUILD SUCCEEDED **`
  - MacLibrary テスト: `** TEST SUCCEEDED **`（86件 passed / 0件 failed。新規 `SharePickerPresenterTests` 2件、`ShareErrorTests` 追加2件を含む）
  - UnityMacPlugin テスト: `** TEST SUCCEEDED **`（28件 passed / 0件 failed。MacLibrary の `ShareError` 追加による影響なしを確認）
- 補足: `SharePickerPresenterTests` に当初含めていた3件目のテスト（busy 解消後に実際の `presentPicker` を再度呼び、AppKit の `NSApp.keyWindow` へアクセスする内容）は、ヘッドレスな xctest プロセス内で `NSApp` へアクセスするとプロセスクラッシュを起こすことが判明したため削除した。この知見（headless xctest 環境での `NSApp` アクセスは不可）は今後 macOS AppKit 関連のテスト設計における制約として有用なため本記録に残す。

---

## 4. Definition of Done（レビュー対応後の再判定）

- 判定基準:
  - ○: 今回の実装・コード・テスト確認の範囲では OK かつ設計書とズレていない
  - △: 一部 OK だが、追加確認が必要
  - ×: 未達、または設計書との差分が未解消
  - -: 対象外

| DoD項目 | v1判定 | v2判定 | 差分理由 |
| --- | --- | --- | --- |
| continuation の単一 resume（多重起動保護含む） | （未記載/暗黙に○としていた） | ○ | busy-guard 追加 + 回帰テストで確定 |
| ボタン押下起点でピッカーを表示でき、テキスト等を共有できる | △ | △（根拠明確化） | 実機・Accessibility権限のいずれも本環境になく自動検証不可と判明。`Task{}` hop の具体的リスクをコードに文書化。実機での人手確認が必須である理由を明記した |
| Unity Bridge経由で共有を起動でき、結果コールバックが返る | △ | △（根拠明確化） | 同上。ビルド・単体テストは green だが、mouseDown文脈での実UI起動確認は本セッションでは不可能だった |
| 他のDoD項目 | v1のまま | 変更なし | 本レビュー対応の範囲外 |

---

## 5. 未解決事項（次工程への申し送り）

- **T5/T8 の mouseDown 実UI検証は依然未完了。** 実施には以下のいずれかが必要:
  - 実 Mac 実機で人手によりボタンを実際にクリックし、`NSSharingServicePicker` が表示されるか目視確認する、または
  - 本開発環境に Accessibility 権限（System Settings > プライバシーとセキュリティ > アクセシビリティ）をユーザー自身が付与し、UI 自動操作によるクリックシミュレーションを許可する。
- 検証の結果、不安定と判明した場合は設計書 §12 の分岐Bを採用し、`MacShareManager.share(content:completion:)`（picker方式）を best-effort 扱いに格下げし、`shareViaService`（個別サービス直接実行）を主経路とする設計変更が必要になる。
- 上記が解消するまで、`shareContent`（ピッカー方式）を製品採用する前に必ず実機での目視確認を実施すること。

---

## 6. ステップ10 実行確認（再掲・更新）

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む（ただし mouseDown 実UI検証は未完了のまま持ち越し）
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
