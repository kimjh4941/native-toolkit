# macOS Clipboard 機能実装レビュー v3

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`（112 files、+29,310 / -19）
- 修正差分: 未コミットの `git diff`（追跡対象 23 files、+778 / -188）および未追跡ファイル
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v4.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v2.md`
- T-18（サンプルアプリ）および Swift 6 移行は指定どおり対象外

## レビュー概要

- v2 の M-4〜M-6に対する実装、テスト、設計書の未コミット修正を確認した。
- M-4 は解消、M-6 は解消。M-5 は production adapter／façadeを通るテストが追加された一方、BT-25 の全 endpoint 検査が網羅的でないため部分解消と判定する。
- H-1 は、非構造化 provider task、独立 deadline、`LoadGate`、キャンセル状態を保持する `ProgressBox` が揃い、**完全解消**と判定する。
- 新規の production code 不具合、high 指摘は検出しなかった。テスト回帰防止の medium 1件、設計書の軽微な追跡不整合 1件を検出した。

## 前回指摘の解消状況

| ID | 判定 | 根拠 | 実害シナリオの評価 |
|---|---|---|---|
| M-4 | **解消** | `ProgressBox.install` は lock 内で `stored` を設定して `isCancelled` を読み、cancel 済みなら lock 解放後に新しい `Progress` を即 cancel する。`cancel` は同じ lock 内で `isCancelled = true` と保存済み値の取得を行う（`mac/MacLibrary/MacLibrary/Clipboard/Presentation/PasteButtonFactory.swift:98-120`）。 | cancel-before-install は後着 `install` が cancel、install-before-cancel は `cancel` が保存済み値を cancel する。両操作は同じ lock で順序付けられるため、前回の空窓は残らない。lock 外で `Progress.cancel()` を呼ぶため再入による deadlock も避けている。 |
| M-5 | **部分解消** | PT-14/PT-15 は実 `NSItemProvider` と production `PasteButtonFactory.ItemProviderSource` を使用し、adapter、`ProgressBox`、`LoadGate` を通る（`mac/MacLibrary/MacLibraryTests/Clipboard/Presentation/ClipboardPasteLoaderTests.swift:364-451`）。BT-24 は `UnityMacClipboardManager.shared.copy` の callback で不正値の 1301 を確認する（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift:183-217`）。late-cancel は `discardedURLs == [stubbedStagingRoot]` を確認する（`mac/MacLibrary/MacLibraryTests/Clipboard/Application/FilePromiseUseCaseTests.swift:165-183`）。ただし BT-25 は M-7 の検出漏れがある。 | H-1/M-4 の本番 adapter 境界と M-3 の façade error 経路は覆われた。Cログの現実装は安全だが、全 endpoint の将来回帰をテストが保証する状態には未到達。 |
| M-6 | **解消** | §7.11 は旧 task group 方式を削除し、非構造化 provider task + 独立 deadline に統一（設計書:931-965）。T-14 は PT-01〜PT-15（2345）、DoD は PT-15／IT-53／BT-25まで更新（2490-2492）。§8.4.5 は1〜10の連番（1961-1973）。PT-14/PT-15もテスト表へ追加（2252-2253）。 | H-1を再導入する旧実装指示は残っておらず、M-4/M-5の教訓と現実装が一致する。 |

## H-1 再判定

**完全解消**

- `ClipboardPasteLoader` は provider taskを非構造化で開始し、独立した deadline が未完了 index を確定するため、callbackを返さない Sourceを awaitして deadline配送が止まることはない（`mac/MacLibrary/MacLibrary/Clipboard/Presentation/ClipboardPasteLoader.swift:84-116,157-179`）。
- `LoadGate` は provider callback と task cancellation のどちらが先でも continuationを1回だけ resumeする（`PasteButtonFactory.swift:123-159`）。
- `ProgressBox` は M-4 の両順序を原子的に扱い、underlying `NSItemProvider` workも確実に cancelする（同:98-120）。
- PT-12/PT-13が無応答 Sourceに対する deadlineを、PT-14/PT-15が実 `NSItemProvider` adapterのloadと cancellationを分担して検証する。今回の再実行でも全て通過した。

## 重大な問題（high）

- なし。

## 改善提案（medium）

### M-7: BT-25 は「全 endpoint」の生ログ回帰を網羅的には検出しない

- `cLayerRedactsEveryPayload` は各行を先に `stringWithFormat` 行、または行頭が `contentJson` / `scopeJson` の行へ絞り、その後 `contentJson ?: "` / `scopeJson ?: "` など特定の式だけを検出する（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift:221-240`）。
- そのため、例えば `clipboardProvideFilePromise` の引数行（production: `UnityMacClipboardManagerBridge.m:273-274`）で `NTScope(scopeJson)` を `scopeJson ?: "(null)"` に戻しても、同じ行は `(unsigned long)` から始まるため最初の filterで除外される。`scopeJson` を nil fallbackなしで直接 `%s` に渡す回帰も、2段目が `scopeJson ?: ` しか探さないため検出されない。
- `cLayerUsesRedactionHelpers` も `NTScope(scopeJson)` がファイル内に1件以上あることしか確認せず、scopeを受ける全 endpointとの1対1対応を検証しない（同:242-250）。したがってテスト名・設計書 BT-25 の「全 endpoint」を満たさない。
- 現在の C 実装自体は、全 `contentJson` が `NTLen`、全 `scopeJson` が `NTScope` を通っており平文漏えいは確認されない。指摘対象は回帰検査の不足である。
- 修正案: `endpointNames(in:)` と同様に各 C 関数本体を分割し、scope引数を持つ全 endpointではログ部分に `NTScope(scopeJson)` があり、`contentJson`を持つ全 endpointでは `NTLen(contentJson)` があることを endpoint名の固定集合と照合する。生ポインタ禁止は `?:` の有無に依存しない式で検査する。

## 軽微な指摘（low）

### L-1: 設計書のタスク別テスト対応とDoD状態が実装結果v4に追随していない

- §13 の T-16a は BT-20〜BT-23までを挙げ、今回 façadeへ追加した BT-24を含まない。T-16bも BT-01〜BT-19のままで、C層の BT-25を含まない（設計書:2347-2348）。同様にT-12a/T-11cのタスク別条件にはIT-51〜IT-53が反映されていない。
- §15 のテスト範囲自体は正しく更新されたが、MacLibrary 417件／UnityMacPlugin 78件の全通過を記録する実装結果v4に対し、PT／IT／BT／CTのチェックボックスは未完了のままである（設計書:2489-2493）。実装方式の矛盾ではないが、設計書を完了記録として読む場合に状態が食い違う。

## 追加テストの本番境界評価

| テスト | 評価 | 根拠 |
|---|---|---|
| PT-14 | ○ | `NSItemProvider()` に `registerDataRepresentation`し、production `ItemProviderSource.conforms/loadData`を実行。fake `Source`を使わない。 |
| PT-15 cancel-before-install | ○ | `@MainActor` 上で作成した Taskをactorがyieldする前にcancelし、既にcancel済みのtaskがproduction adapterを開始する順序を作る。providerが生成した実 `Progress.isCancelled`を確認。 |
| PT-15 install-before-cancel | ○ | provider開始後にcancelし、保存済みの実 `Progress.isCancelled`を確認。 |
| cancelled load | ○ | production `LoadGate`がtask cancellationをthrowへ変換し、hangしないことを確認。 |
| late-cancel staging root | ○ | production UseCaseに注入されたPort mockを通し、discard回数だけでなくroot URLを確認。 |
| BT-24 malformed | ○ | production `UnityMacClipboardManager.shared.copy`を呼び、callbackの `isSuccess == false` / `errorCode == 1301`を確認。 |
| BT-24 absent | △ | production façadeは通るが、assertが `errorCode != 1301`のみであり、callback未到達時のnilでも成功する。parser側のnil／空／正常／不正テストとの組み合わせで分類は確認できるが、このテスト単独ではcallback到達を保証しない。 |
| BT-25 | △ | production C sourceを直接読むためfake迂回ではないが、M-7のとおり全 endpoint照合になっていない。 |

## 修正によるregression確認

- `ProgressBox` の状態は lockで保護され、`Progress.cancel()`はlock外で実行される。新しいdata race／deadlock／二重resume経路は確認されなかった。
- `ItemProviderSource.loadData` の成功callback、cancel-before-attach、cancel-after-attachはいずれも `LoadGate` の1回配送に収束する。
- façade BT-24の正常系は固定名のnamed pasteboardへ書き込むためテスト外部状態を変更するが、今回の反復実行で競合・失敗は再現しなかった。将来は一意名とcleanupを使うとテスト分離がより明確になる。
- production codeに新しいエラー経路、公開API破壊、Clean Architecture違反、ログ平文漏えいは検出しなかった。

## 設計書整合性チェック

- 企画書との整合性: ○
- Clean Architecture準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △（BT-25実装が設計上の「全 endpoint」を満たさない）
- ドメインエラー全ケース実装: ○
- エラーコード／メッセージ対応表との整合: ○
- M-6対象箇所の意味上の整合: ○
- その他の記録整合: △（L-1）
- `scripts/check_design_consistency.py`: 22 / 22通過

## プロジェクトルール適合チェック

- `common.md`準拠: ○
- `mac.md`準拠: ○
- エラー契約反映: ○
- 既存API互換性: ○
- cancellation / exactly-once: ○
- ログ秘匿実装: ○
- ログ秘匿回帰テスト: △（M-7）

## テストカバレッジ

- レビュー時にMacLibraryとUnityMacPluginの全テストを再実行し、両方 `TEST SUCCEEDED`。
- 提示済み件数: MacLibrary 417件、UnityMacPlugin 78件、失敗0件。提示済みのMacLibrary 2回連続成功も前提事実として扱う。
- strict concurrencyは提示済みのunique 173件／Clipboard由来0件を前提とし、今回の差分に新たな診断根拠は確認されない。
- `git diff --check`は問題なし。
- 不足はBT-25の全 endpoint回帰検査と、BT-24 absent testのcallback到達assert。

## 総合評価

**要修正（軽微）**

M-4のraceは完全に塞がり、実 `NSItemProvider` 境界の再現テストも通るため、H-1は完全解消した。M-6の実装方式上の矛盾も解消し、production codeに新規不具合はない。一方、M-5の目的である回帰検査のうちBT-25が全 endpointを保証していないため、M-7を修正してからLGTMとする。L-1は同時修正を推奨する。
