# macOS Clipboard 機能実装レビュー v4

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`（112 files、+29,310 / -19）
- 修正差分: 未コミットの `git diff`（追跡対象 23 files、+863 / -196）および未追跡ファイル
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v5.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v3.md`
- T-18（サンプルアプリ）および Swift 6 移行は指定どおり対象外

## レビュー概要

- M-7 は行ベース監査の欠陥自体は解消したが、監査対象を定める手書き辞書から `optionsJson` が漏れており、production code にも `optionsJson` の平文ログが残るため **未解消**と判定する。
- L-1 で指摘したタスク別完了条件と6件のテストDoDは更新され、当該指摘は **解消**した。
- 一方、設計書が定義する CT-17 はタスク、DoD、テスト実装へ追跡されておらず、新規 medium として指摘する。strict concurrency の実績がチェック状態に反映されていない点も新規 low とした。
- high / critical は検出しなかった。production code のログ秘匿違反1件と並行性回帰テストの欠落が残るため、現時点ではマージ不可と判定する。

## レビュー観点別の結論

| 観点 | 結論 | 要約 |
|---|---|---|
| 1. M-7 | **未解消** | 19 endpoint の関数本体抽出と引数リスト抽出は有効になったが、payload集合が手書き辞書であり `optionsJson` を検査しない。実際に `clipboardCopy` が同引数を `%s` へ渡している。 |
| 2. L-1 | **解消。ただし新規指摘あり** | 指定されたタスク対応と6件のDoDは更新済み。別途、CT-17の追跡・実装欠落（M-8）とstrict concurrencyチェック状態の不一致（L-2）が残る。 |
| 3. 修正による新規問題 | **新規指摘あり** | M-7修正時に監査の網羅性を過大評価できる構造が入り、既存の `optionsJson` 平文ログを「全payload監査済み」として見逃している。 |
| 4. production code 再確認 | **残存問題あり** | `clipboardCopy` の `optionsJson` 平文ログ以外には、今回確認したClipboardのログ、キャンセル、exactly-once、File Promise経路で新たなproduction不具合を検出しなかった。 |
| 5. マージ可否 | **マージ不可** | M-7のproduction秘匿違反とM-8の設計済み並行性テスト欠落を解消後に再確認が必要。 |

## 前回指摘の解消状況

### M-7: BT-25 が全 endpoint の全 payload 引数を検査しない

**判定: 未解消**

改善された点:

- `endpointBodies()` はC実装を19個のendpointへ分割し、`auditCoversEveryEndpoint()` は抽出数が19であることを確認している（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift:242-254,303-322`）。前回の「引数行がfilterから外れる」問題は解消した。
- `logCalls(in:)` は `stringWithFormat:` の引数リストだけを取り出し、フォーマット文字列中のラベルを誤検出しない（同:324-336）。`?:` の有無に依存せず、既知の引数については生値とhelper経由を区別できる。
- production側では `clipboardProvideFilePromise` が `NTLen(requestJson)` / `NTScope(scopeJson)` に統一され、`clipboardReceiveFilePromises` は `destinationPath`、`scopeJson`、`policyJson`をそれぞれhelper経由で記録する（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.m:273-294`）。申告された2件の不整合は解消している。

残る欠陥:

- 監査対象はsignatureから自動導出されていない。`redactionHelpers` は引数名を列挙した手書き辞書であり、コメントの「function's own signatureから導出」と矛盾する（テスト:226-236）。辞書には `contentJson`、`policyJson`、`scopeJson`等はあるが、`clipboardCopy` のsignatureが持つ **`optionsJson` がない**。
- `noPayloadReachesLogRaw()` と `loggedArgumentsUseTheirHelper()` はどちらもこの辞書だけを反復するため、辞書にないpayloadは検査されない（同:257-295）。`auditCoversEveryEndpoint()` の `examined >= 20` も既知引数の検査箇所数しか数えず、26箇所が対象になる現状では `optionsJson` 欠落があっても通過する。
- 実際にproductionの `clipboardCopy` は `optionsJson:%s` とし、`optionsJson ?: "(null)"` をそのままログへ渡している（C実装:40-45）。設計書 §4.2 の「文字列は長さのみ」（設計書:331-339）およびC層にも同じ秘匿方針を適用する契約（同:876）に反する。現在のschemaは主にbooleanだが、将来のschema拡張も含めて入力JSONを平文記録しないという境界契約を破っている。
- `logCalls(in:)` は `stringWithFormat:` のみを監査するため、将来 `[Log ... :NTStr(payload)]` のような直接ログへ変更された場合も空振りする余地がある。

実害シナリオ:

- Unity呼び出し側が渡した `optionsJson` がmacOSのログへ平文複写される。
- `optionsJson` や新しいpayload引数を生ログへ渡しても、現在のBT-25は成功する。今回のUnityMacPlugin全79テスト成功と、この現存する平文ログが両立していることが検出漏れの実証になっている。

修正条件:

1. `clipboardCopy` を `%@` + `NTLen(optionsJson)` へ変更する。
2. 全19 endpoint のsignatureから `const char*` 引数を抽出し、UTIのように設計上平文許可された引数だけを明示的に除外する。抽出した秘匿対象集合とhelper対応表が完全一致することをassertし、件数の下限ではなく集合の一致で監査する。
3. `stringWithFormat:` に限定せず、各endpointの全 `Log` 呼び出しに生payload識別子が到達しないことを検査する。

### L-1: 設計書の追跡状態が実績に追随していない

**判定: 解消**

- T-11cにIT-53、T-12aにIT-51/IT-52、T-16aにBT-24、T-16bにBT-25が追加されている（設計書:2341-2348）。
- §15の単体、IT-01〜20、PT-01〜15、IT-21〜53、BT-01〜25、CT-01〜16の6項目が完了へ更新されている（同:2488-2493）。
- 前回L-1が具体的に指摘した箇所は実装結果v5の実績と一致した。以下のM-8/L-2は、この修正を確認する過程で別に検出した追跡不整合である。

## 新規指摘

### M-8 [medium]: 設計済みのCT-17がタスク、DoD、テスト実装から抜けている

- 設計書 §12.5 は、handle予約直後・登録中・登録直後のキャンセルで同一handleをcancelしsessionを残留させない検査を **CT-17** として定義している（設計書:2306）。
- しかしT-13の完了条件はCT-13〜CT-16まで（同:2344）、§15の完了済みチェックもCT-01〜CT-16まで（同:2493）で、CT-17を追跡していない。
- 実テストも `FilePromiseReceiveAsyncTests` の区分が明示的に「CT-13 to CT-16」で、CT-13〜CT-16は識別子付きで存在するが、リポジトリ内にCT-17を識別するテストはない（`mac/MacLibrary/MacLibraryTests/Clipboard/Manager/FilePromiseReceiveAsyncTests.swift:153-245`）。`alreadyCancelledTask` は開始前cancelの1ケースであり、設計が要求する予約直後・登録中・登録直後の3境界を個別に同期して検証していない。
- productionはhandleを先に予約し、`withTaskCancellationHandler` の `onCancel` が同じhandleを捕捉する構造になっている（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:668-705`）。コード上の同一handle利用は確認できるが、過去に問題となった競合契約に対する設計済み回帰テストが欠けたままDoDを完了扱いにはできない。

修正条件: 制御可能なhook/gateを用いて予約直後・登録中・登録直後の各時点を決定的に作り、同じhandleがcancelされ、最終的に `registeredReceiptCount == 0` となるCT-17を追加する。T-13と§15もCT-17までへ更新する。

### L-2 [low]: strict concurrencyの検証実績がDoDのチェック状態に反映されていない

- 実装結果v5はstrict concurrency診断をunique 173件、Clipboard由来0件として記録する（実装結果:78）。レビューでもこの確定済み事実を前提にした。
- 設計書 §15 の同一条件は未完了 `[ ]` のままである（設計書:2482）。テスト6項目を実績へ追随させた今回の更新後も、同じDoD内で状態が食い違う。

修正条件: 検証記録を根拠に当該チェックを完了へ更新する。

## production code 再確認

- `clipboardProvideFilePromise` と `clipboardReceiveFilePromises` の今回の変更は、引数値を長さ／scope hashへ変換するだけで実処理への引数受け渡しは変更していない。新しいエラー経路、callback回数変更、NULL契約変更は確認されなかった。
- C層19 endpointのログを横断確認し、設計上平文許可のUTIを除く既知の文字列payloadは、M-7記載の `optionsJson` 以外では `NTLen` / `NTScope` を通っている。
- Swift façade／parser側は `ClipboardLog.json` / `scopeJson` / `path` を使い、生のJSON・完全パスをログへ補間する箇所は確認されなかった。
- 前回までに解消したPasteButtonのcancel-before-install、deadline、exactly-once、およびFile Promise staging root経路に、今回の差分による変更はない。全テスト再実行でも回帰は検出されなかった。

## 設計書整合性

- L-1対象のタスク別完了条件: ○
- L-1対象のテストDoD 6項目: ○
- ログ秘匿方針とC実装: ×（M-7、`optionsJson`）
- テストIDのタスク／DoD追跡: ×（M-8、CT-17）
- その他の実績チェック状態: △（L-2）
- T-18とSwift 6移行の扱い: ○（範囲外として一貫）
- `scripts/check_design_consistency.py`: 22 / 22通過。M-7、M-8、L-2はいずれも機械照合対象外の意味上の不整合である。

## 検証結果

| 対象 | 結果 |
|---|---|
| MacLibrary | 417件成功、0失敗（レビュー時にも `TEST SUCCEEDED` を確認。提示済みの2回連続成功を前提事実として採用） |
| UnityMacPlugin | 79件成功、0失敗（レビュー時にも `TEST SUCCEEDED` を確認） |
| strict concurrency | unique 173件、Clipboard由来0件（確定済み事実） |
| 設計整合スクリプト | 22 / 22成功 |
| `git diff --check` | 問題なし |

テスト成功は確認できたが、M-7のとおりBT-25自身が `optionsJson` を監査対象に含めていないため、79件成功は全payloadの秘匿を保証しない。またCT-17はテスト集合に存在しないため、417件成功にも当該3境界の保証は含まれない。

## 指摘一覧

| ID | Severity | 区分 | 内容 |
|---|---|---|---|
| M-7 | medium | 前回指摘・未解消 | 手書き監査辞書から `optionsJson` が漏れ、productionにも平文ログが残る。 |
| M-8 | medium | 新規 | 設計済みCT-17がタスク、DoD、実テストに存在しない。 |
| L-2 | low | 新規 | strict concurrency合格実績がDoDで未完了のまま。 |

- critical: 0件
- high: 0件
- medium: 2件
- low: 1件

## 総合評価

**要修正（マージ不可）**

L-1の指定箇所と、M-7で前回問題になった行ベース抽出は修正された。しかしBT-25は全payloadをsignatureから導出しておらず、実際に `optionsJson` の平文ログを見逃しているため、M-7は完了していない。加えて、設計済みのキャンセル競合テストCT-17が追跡・実装とも欠ける。M-7とM-8を解消し、L-2を設計実績へ反映した後に再レビューする。
