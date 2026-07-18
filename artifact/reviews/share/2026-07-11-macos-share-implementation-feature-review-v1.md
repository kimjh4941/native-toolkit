# macOS Share 実装レビュー結果 v1

- 日付: 2026-07-11
- ブランチ: `feature/NTKIT-11`
- 対象実装結果: `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v1.md`
- 対象設計書: `artifact/designs/share/2026-07-11-macos-share-design.md`
- 比較範囲: `develop...HEAD` は空。ローカル未追跡の Share 実装ファイルと実装結果 artifact を対象にレビュー。

## Findings

### High: T5/T8 の必須完了条件である picker / Unity Bridge の実 UI 検証が未完了のまま、実装完了扱いになっている

- 根拠:
  - 設計書は T5 の完了条件として、実機での picker 表示・直接実行、`show()` を `mouseDown` 文脈で呼んだ場合の安定表示、分岐判断の確定を要求している: `artifact/designs/share/2026-07-11-macos-share-design.md:816`
  - T8 も Unity Bridge 経由で picker が `mouseDown` 制約を満たして安定表示できること、満たせない場合は代替分岐を採用することを完了条件にしている: `artifact/designs/share/2026-07-11-macos-share-design.md:819`
  - リスク欄でも、通常の Unity Bridge 呼び出しで `mouseDown` 文脈が保証されないため、T5 で早期検証して分岐確定することが明記されている: `artifact/designs/share/2026-07-11-macos-share-design.md:831`, `artifact/designs/share/2026-07-11-macos-share-design.md:846`
  - 実装結果では該当検証が未実施として残っている: `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v1.md:135`, `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v1.md:136`, `artifact/results/share/2026-07-11-macos-share-implementation-feature-result-v1.md:168`

影響: 主 API の `shareContent` は picker 方式であり、Unity からボタン起点で呼んだときに安定表示できるかが未確定です。設計上はこの検証結果で分岐 A/B/C を確定する前提なので、現時点では T5/T8 を完了扱いにできません。

推奨対応:
- 実 macOS UI / Unity Bridge 経由で `shareContent` をボタン押下起点で呼び、picker 表示・選択・キャンセル・callback 返却を確認する。
- 安定しない場合は設計どおり分岐 B または C を採用し、実装結果の T5/T8 / DoD 判定を更新する。

### High: 共有処理の多重起動で既存 continuation が上書きされ、先行リクエストの callback / async が戻らない可能性がある

- 根拠:
  - `SharePickerPresenter` は単一の `continuation` スロットだけを保持している: `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:65`
  - `presentPicker` は進行中チェックなしに `self.continuation = continuation` を再代入する: `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:78`, `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:79`
  - `performService` も同じく進行中チェックなしに continuation を再代入する: `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:102`, `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift:103`
  - Manager の callback API は呼び出しごとに `Task { @MainActor in ... }` を起動し、進行中操作を直列化または拒否していない: `mac/MacLibrary/MacLibrary/Share/MacShareManager.swift:81`, `mac/MacLibrary/MacLibrary/Share/MacShareManager.swift:82`, `mac/MacLibrary/MacLibrary/Share/MacShareManager.swift:105`, `mac/MacLibrary/MacLibrary/Share/MacShareManager.swift:106`

影響: ユーザーの連打、Unity 側の二重呼び出し、または picker 表示中の direct service 呼び出しで、先行操作の continuation が失われます。その場合、先行の Unity callback または Swift async 呼び出しが完了しないままになります。設計書が要求する「continuation を必ず 1 回だけ resume」の性質も、多重起動時には満たせません。

推奨対応:
- `SharePickerPresenter` または `MacShareManager` で進行中状態を管理し、同時起動を明示的な `ShareError` として拒否する。
- あるいは share 操作をキューイングして直列化する。
- 該当ケースの単体テストを追加し、2 回目呼び出し時に先行 callback が失われないことを確認する。

## 確認できたこと

- Clean Architecture の層構成、Port の Domain 型境界、Presenter への delegate 集約、`NSSharingService.title` による best-effort 除外は設計意図と整合している。
- `NSSharingService` インスタンスから存在しない `name` を読まず、設計レビュー後の `title` 方針で実装されている。
- `BOOL` / `bool` の使い分けは設計どおり。Swift completion block 側は `BOOL`、C ABI typedef は `bool`。
- `ShareError` / UseCase / Converter / Manager / JSON Parser の単体テストは実装されている。

## 実行した検証

- `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary -configuration Debug build` -> 成功
- `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -configuration Debug build` -> 成功
- `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme MacLibrary -destination 'platform=macOS' test` -> 成功
- `xcodebuild -workspace mac/MacWorkspace.xcworkspace -scheme UnityMacPlugin -destination 'platform=macOS' test` -> 成功

注: sandbox 内の `xcodebuild` は workspace 判定 / CoreSimulator 関連で失敗したため、上記は権限付きで再実行した結果。

## 総合評価

現時点では **要修正**。ビルドと自動テストは通っており構成も概ね設計どおりですが、設計で完了条件に引き上げた picker / Unity Bridge の実 UI 検証が未完了です。また、多重起動時に continuation が上書きされる実行時リスクが残っています。
