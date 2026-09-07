# macOS Clipboard 機能実装レビュー v5

## レビュー対象

- ブランチ: `feature/NTKIT-15`
- 基準差分: `git diff develop...HEAD`（112 files、+29,310 / -19）
- 修正差分: 未コミットの `git diff`（追跡対象23 files、+1,050 / -204）および未追跡ファイル
- 対象 OS: macOS 15 以降
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v6.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-30-macos-clipboard-implementation-feature-review-v4.md`
- T-18（サンプルアプリ）およびSwift 6移行は指定どおり対象外

## レビュー概要

- M-7のproduction修正とsignature由来の対象集合は正しい。19 endpointから28個の`const char*`引数が抽出され、現存する全引数は`NTLen` / `NTScope`を通る。ただし監査対象のログ自体を`stringWithFormat:`に限定する抜け道が残るため、**部分解消**と判定する。
- M-8はCT-17識別子、T-13、DoDへ追跡されたが、追加された`StartGate`は待機・解放を行わずテストへ実質接続されていない。3境界を決定的に作り、各境界で同じhandleを検査する要求には未到達のため、**部分解消**と判定する。
- L-2はstrict concurrency実績がDoDへ反映され、**解消**した。追加で完了化したDoDの大部分も実装と一致するが、`@discardableResult`の排他的記述だけはproductionと矛盾するため新規lowとした。
- 現在のproduction codeに新たな機能不具合・平文ログ・high / critical問題は検出しなかった。残件は手続きだけではなく回帰保証と設計契約の正確性に関わるため、マージは保留する。

## レビュー観点別の結論

| 観点 | 結論 | 根拠の要約 |
|---|---|---|
| 1. M-7 | **部分解消** | signatureから全28文字列引数を抽出でき、現productionは全て秘匿済み。一方、`logCalls(in:)`が`stringWithFormat:`以外の`Log`を見ないため監査の抜け道が残る。 |
| 2. M-8 / CT-17 | **部分解消** | 4テストは追加され全て通るが、`StartGate`はブロックせず未接続。「登録直後」は固定sleep、同一handle検査は1境界だけである。 |
| 3. L-2 / DoD | **L-2解消、新規lowあり** | strict concurrencyと実装構造のチェック状態は概ね妥当。ただし「`@discardableResult`はOP-01〜07 / 09〜11のみ」という完了項目はOP-16 / OP-18の実装と矛盾する。 |
| 4. production code | **新規production問題なし** | `optionsJson` / `utType`を含むC層28引数は全て長さまたはscope hashで記録され、今回の変更によるcallback・エラー・リソース経路の変更もない。 |
| 5. マージ可否 | **マージ保留** | 残るmedium 2件はproduction障害ではないが、過去の実害を防ぐ回帰監査・競合テストの実効性に関わる本質的な品質保証残件である。 |

## 前回指摘の解消状況

### M-7 [medium]: C層ログ監査が全payloadを保証しない

**判定: 部分解消**

解消した点:

- `payloadArguments(in:)` は各endpoint signatureに `/const char\*\s+(\w+)/` を適用し、手書きの引数辞書を廃止している（`mac/UnityMacPlugin/UnityMacPluginTests/Clipboard/UnityMacClipboardBridgeTests.swift:231-237`）。
- `endpointBodies()` は19 endpointを抽出し、`auditCoversEveryEndpoint()` はendpoint数19と抽出引数数28を検査する（同:243-255,314-335）。別途、ヘッダの`stringParameterConvention()`が全C文字列引数を`const char*`表記へ制約するため、現行規約内では正規表現の空白・ポインタ表記差による抽出漏れもない（同:172-180）。
- レビュー側でも同じ抽出条件を独立に適用し、19 endpoint / 28引数を確認した。`contentJson`、`optionsJson`、`utType`、`destinationPath`等、実装に存在する全C文字列引数が対象集合へ入る。
- productionの`clipboardCopy`は`NTLen(optionsJson)`、`clipboardReadData`は`NTLen(utType)`へ修正されている（`mac/UnityMacPlugin/UnityMacPlugin/Clipboard/UnityMacClipboardManagerBridge.m:40-45,82-86`）。他の26引数も`scope`を含むものは`NTScope`、それ以外は`NTLen`を通っており、現存コードに平文ログは確認されなかった。

残る抜け道:

- `noPayloadReachesLogRaw()` / `loggedArgumentsUseTheirHelper()`が調べるログ集合は、`logCalls(in:)`の戻り値だけである（テスト:269-305）。`logCalls(in:)`は関数本体を`stringWithFormat:`で分割して、その形式の引数リストだけを返す（同:257-267）。
- したがって、例えばendpoint先頭ログを`[Log d:TAG :NTStr(contentJson)]`、または`[Log d:TAG :[NSString stringWithUTF8String:contentJson]]`へ変更すると、そのログは監査集合に一度も入らない。endpoint数は19、signature引数数は28のままであり、残りの既存ログだけで`examined >= 20`も満たすため、3テストはいずれも成功し得る。
- signature由来への変更で「引数側が自分の列挙より狭い」問題は解消したが、「ログ呼び出し側が自分の列挙より狭い」構造が残る。これはv4で示した「`stringWithFormat:`に限定せず全`Log`呼び出しを検査する」という修正条件を満たしていない。

実害評価:

- **現在のproductionに平文漏えいはない**。前回の`optionsJson`漏えいは解消済みである。
- 残件は将来の平文ログ回帰をBT-25が黙って見逃せる問題である。BT-25は秘匿境界の回帰防止を目的とし、過去3回実際に検査漏れが平文ログを残したため、mediumを維持する。

修正条件:

- 各endpointの全`[Log ...]`式を抽出し、その式全体からsignature由来payloadの生参照を検査する。少なくとも、payloadを含む`Log`が`stringWithFormat:`を使わない場合にもテストが失敗することをmutationで確認する。
- `examined >= 20`ではなく、各endpointの各payloadについて「ログに出さない、または対応helperだけを経由する」の判定結果を集合として保持し、全28引数が分類済みであることをassertする。

### M-8 [medium]: CT-17の3境界が追跡・決定的テストされていない

**判定: 部分解消**

解消した点:

- 設計書T-13はCT-13〜CT-17、§15はCT-01〜CT-17へ更新されている（設計書:2344,2493）。前回の追跡漏れは解消した。
- `cancelJustAfterReservation`、`cancelDuringRegistration`、`cancelJustAfterRegistration`、`cancellationUsesTheReservedHandle`の4テストがCT-17として追加され、今回の再実行でも全て成功した（`mac/MacLibrary/MacLibraryTests/Clipboard/Manager/FilePromiseReceiveAsyncTests.swift:336-411`）。
- productionはhandleを先に予約し、そのimmutable値をcancellation handlerが捕捉する（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:668-705`）。開始transactionも同じhandleで`registerReceipt`からrepository startへ進む（`mac/MacLibrary/MacLibrary/Clipboard/Application/UseCase/ReceiveFilePromisesUseCase.swift:51-72`）。コード上、旧mutable handle publication raceは再導入されていない。

残る欠陥:

- `StartGate.waitForRelease()`はlockから`reached` closureを取り出して呼ぶだけで、待機しない。`release`プロパティは一度も読み書きされず、`onReached`もテストから一度も呼ばれない（テスト:242-256）。コメントにある「stop the start sequence」「blocks on demand」という動作は実装されていない。
- `cancelDuringRegistration`は`started.waitForRelease()`を呼ぶが、`started`をrepositoryへ渡していないため即returnする。実際の同期点は`GatedRepository.onStart`だけであり、これは`registry.registerReceipt(...)`が完了した後に呼ばれるrepositoryメソッドの先頭でself-cancelする（テスト:258-273,353-370、UseCase:61-65）。開始transaction途中の一境界は再現するが、「登録中」をgateで停止して外部からcancelする検査ではない。
- `cancelJustAfterRegistration`と`cancellationUsesTheReservedHandle`は80msの固定sleepで到達を待ち、cancel後も150ms sleepでcleanupを待つ（テスト:373-410）。状態assertが未到達を検出はするものの、実行点をgateで決定しておらず、負荷によって失敗し得る。
- `cancellationUsesTheReservedHandle`は登録後の1ケースだけでhandleを取得して消滅を確認する。テスト名は「every cancellation point」だが、予約直後・transaction途中の2ケースではcancel対象handleを記録・比較しない。`cancelJustAfterReservation`末尾の`_ = repository.startCallCount`もassertではない（同:336-350）。

実害評価:

- 追加テストは旧raceの主要経路を以前より強く覆い、現在のproduction構造も正しい。
- ただし設計CT-17の「3境界のいずれでも同じhandle」を決定的に保証するテストにはなっていない。並行性回帰テストとしての再現性と検出力が不足するためmediumを維持する。

修正条件:

- coordinatorをforwardするtest-only `ClipboardPromiseRegistry` spy等で、reserve直後、register処理中、register完了直後の各hookを実際に待機可能なgateへ接続する。
- 各ケースで予約したhandleと`terminateReceiptWithoutDelivery`へ渡されたhandleを記録して一致をassertし、cleanup完了も固定sleepではなくsignal / eventual conditionで待つ。
- 未使用の`StartGate.release`を含むdead codeを除去するか、到達通知と明示releaseを持つ本物のbarrierとして実装する。

### L-2 [low]: strict concurrency実績がDoDへ反映されていない

**判定: 解消**

- 設計書§15のstrict concurrency項目は`[x]`へ更新されている（設計書:2482）。実装結果v6はunique 173件 / Clipboard由来0件を記録し、確定済みの検証事実と一致する（実装結果:78）。
- Swift 6言語モード移行は同項目でも明確に対象外のままであり、範囲の拡張はない。

## DoD更新の実態確認

| 完了化した項目 | 評価 | コード上の根拠 |
|---|---|---|
| Swift façadeの全handlerが`@Sendable` | ○ | 19 facadeメソッドの`handler` / `onChange` / `onEvent`は`(@Sendable (...) -> Void)?`。BT-20も全public funcの該当引数を抽出して検査する（`UnityMacClipboardBridgeTests.swift:102-115`）。 |
| §9のsignature / actor / cancel / timeout / exactly-once | ○ | 前回までのレビュー対象と今回のproduction再確認で、新たな乖離は検出しなかった。OP-18は予約handle、`ReceiptCompletionGate`、MainActor cleanupを使用する（`MacClipboardManager.swift:661-705`）。 |
| `@discardableResult`配置 | × | 新規L-3のとおり、完了条件の排他的記述とOP-16 / OP-18実装が一致しない。 |
| OP-16 `async throws` / MainActor外copy | ○ | native APIは`async throws`（`MacClipboardManager.swift:538-544`）。UseCaseはsnapshotterをawaitし、実コピーは専用queueで行う（`ProvideFilePromiseUseCase.swift:44-70`、`FilePromiseSnapshotter.swift:35-73`）。 |
| `FilePromiseLifecycleState`のnonisolated性 | ○ | 型に`@MainActor`はなく、全mutable stateをprivate `NSLock`で保護する（`FilePromiseLifecycleState.swift:22-50,62-187`）。 |
| Unity BridgeにDelegate実装なし / coordinatorだけがsystem delegateを強参照 | ○ | Unity Clipboard配下にDelegate protocol適合はない。`FilePromiseDelegate`と`LazyDataProvider`の生成・保持は`ClipboardSystemCoordinator`に集約される（`ClipboardSystemCoordinator.swift:46,255-307`）。 |

### L-3 [low]: `@discardableResult`の完了済みDoDがproductionと矛盾する

- 設計書§8.1、§12.1、T-08、§15は「`@discardableResult`はOP-01〜OP-07 / OP-09〜OP-11 **のみ**」と記述し、§15を完了扱いにした（設計書:1486,2173,2336,2485）。
- productionでは上記に加えて、OP-16 `provideFilePromise`に`@discardableResult`がある（`mac/MacLibrary/MacLibrary/Clipboard/Manager/MacClipboardManager.swift:538-540`）。OP-18のcallback形式`receiveFilePromises`にも付いている（同:584-589）。
- OP-16は値を返すnative async APIであり、mac.mdの方針上も付与が自然である。OP-18も取消用handleを返すため、productionから削除する必然性は確認できない。問題はproductionではなく、設計書が「のみ」として実態を除外したまま完了化されている点である。

修正条件: productionで意図する付与集合を確定し、§8.1、§12.1、T-08、§15の4箇所を同じ集合へ更新する。少なくとも「OP-08には付けない」という本来の警告回避要件と、OP-16 / OP-18への意図的な付与を分けて記述する。

## production code再確認

- C層19 endpoint / 28文字列引数を横断し、全ログ引数が`NTLen`または`NTScope`を通ることを確認した。`optionsJson`と`utType`の修正はSwift façadeへ渡す値を変更せず、ログ表現だけを秘匿している。
- Swift façade / parser側は引き続き`ClipboardLog.json` / `scopeJson` / `path`を使用し、生JSONや完全パスをログへ出す箇所は確認されなかった。
- CT-17対象のproductionはhandle予約後に同じimmutable handleをUseCaseとcleanup closureへ渡す。今回追加された変更はテストのみで、productionに新しいrace、二重resume、session残留経路は確認されなかった。
- 過去ラウンドで修正されたPasteButton cancellation / deadline / exactly-once、File Promise timeout / staging cleanup、UseCase経路、options parsingに新たなregressionは検出されなかった。

## 重大な問題（high）

- なし。

## 改善提案（medium）

- M-7: 全`Log`式を対象にしないC層ログ監査の残存抜け道。
- M-8: CT-17のgate未接続、固定sleep依存、3境界での同一handle確認不足。

## 軽微な指摘（low）

- L-3: `@discardableResult`の設計・DoD記述とproduction配置の不一致。

## 設計書整合性チェック

- 企画書との整合性: ○
- Clean Architecture準拠: ○
- 既存実装との差分分析の正確性: ○
- テスト設計の網羅性: △（M-7 / M-8）
- ドメインエラー全ケース実装: ○
- エラーコード／メッセージ対応表との整合: ○
- CT-17のタスク／DoD追跡: ○
- DoDとproductionの意味上の整合: △（L-3）
- T-18 / 手動確認の未完了表示: ○
- `scripts/check_design_consistency.py`: 22 / 22通過

## プロジェクトルール適合チェック

- `common.md`準拠: ○
- `mac.md`準拠: ○
- エラー契約反映: ○
- 既存API互換性: ○
- cancellation / exactly-once production実装: ○
- ログ秘匿production実装: ○
- ログ秘匿回帰監査: △（M-7）

## テストカバレッジ・検証結果

| 対象 | 結果 |
|---|---|
| MacLibrary | レビュー時に再実行し`TEST SUCCEEDED`。提示済み421件 / 0失敗、および2回連続成功と整合 |
| UnityMacPlugin | レビュー時に再実行し`TEST SUCCEEDED`。提示済み79件 / 0失敗と整合 |
| CT-17追加4テスト | 全て成功。ただしM-8のとおり同期点とassertの実効性が設計要求に未到達 |
| BT-25 | 全テスト成功。現行19 endpoint / 28引数を検査するが、M-7の直接`Log`形式は監査外 |
| strict concurrency | unique 173件 / Clipboard由来0件（確定済み事実。今回の通常test buildとは別の既検証結果） |
| 設計整合スクリプト | 22 / 22成功 |
| `git diff --check` | 問題なし |

## 指摘一覧

| ID | Severity | 判定 | 内容 |
|---|---|---|---|
| M-7 | medium | 部分解消 | signature由来の28引数抽出とproduction秘匿は解消。`stringWithFormat:`以外の`Log`を監査しない。 |
| M-8 | medium | 部分解消 | CT-17は追加されたが、gate未接続・sleep依存・3境界の同一handle確認不足。 |
| L-2 | low | 解消 | strict concurrency実績をDoDへ反映済み。 |
| L-3 | low | 新規 | `@discardableResult`の完了済み設計契約がOP-16 / OP-18の実装と矛盾。 |

- critical: 0件
- high: 0件
- medium: 2件
- low: 1件（解消済みL-2を除く）

## 総合評価

**要修正（軽微）／マージ保留**

現在のproduction codeには、前回の`optionsJson`平文ログを含む既知の機能不具合は残っていない。L-2も解消し、T-18とMT-01〜MT-07だけが未完了である点は設計上明示されている。

一方、M-7とM-8は単なる文書更新や手動実施待ちではない。過去に実害を見逃した秘匿監査とhandle publication raceの回帰テストが、現在も名目上の対象より狭いという**本質的な品質保証残件**である。全`Log`形式を覆う監査と、実際に接続されたbarrierで3境界・同一handleを検証するCT-17へ修正し、L-3の設計記述を実態へ合わせた後にマージ可能と判定する。
