# iOS Clipboard 実装レビュー v2

## レビュー対象

- 日付: 2026-08-08
- 対象OS: iOS 18以降
- ブランチ: `feature/NTKIT-14`
- 比較差分: `develop...feature/NTKIT-14` に加え、実装レビュー v1 反映分の未コミット差分を含む
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v2.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-implementation-feature-review-v1.md`

## レビュー概要

- v1 の high 7件に対し、provider load 共通化、attach 前キャンセルのラッチ、監視開始失敗伝播、observer 世代 gate、ログ秘匿、JSON malformed 判定、Clipboard 配下の actor isolation 修正が実装された。
- 通常設定の `IosLibrary` / `UnityIosPlugin` build は成功し、Simulator テストもそれぞれ166件 / 69件、失敗0を再現した。
- 一方、file load はコピー前サイズを取得できない場合に無制限のコピーへ進み、設計上のセキュリティ境界を満たさない。S11 の内部キャンセル完了、JSON options の既定値、設計テストと実テストの対応にも差分が残る。
- I-10 の full-module strict build は未達である。さらに、実測ではレポート記載の「Notification 5件」ではなく、Dialog / Notification / Share にまたがる13件の concurrency error が確認された。

## v1 指摘の反映状況

| v1 ID | 判定 | 確認結果 |
|---|---|---|
| H-01 | △ | `acceptedTypes`、file 分岐、timeout、`Progress.cancel()`、request gate、text/URL limit は実装済み。ただしS11内部キャンセル完了とcopy前file size契約に残件あり |
| H-02 | ○ | `pendingResult` によりattach前の勝者を保持し、timeout taskも決着時にcancelする |
| H-03 | ○ | `startObserving` がthrowしBridgeへ伝播する。generation照合も実装済み |
| H-04 | ○ | scope / creation request はkindとUTF-8長だけをログ出力する |
| H-05 | △ | text/URL、imageFile decode前、post-copy sizeは実装済み。pre-copy size取得不能時の扱いが未解消 |
| H-06 | ○ | omittedとpresent-but-malformedを区別する |
| H-07 | △ | Clipboard起因のstrict診断は今回確認されなかったが、I-10のtarget全体は失敗 |
| M-01〜M-04 | ○ | identifierベースmapper、ASCII UTI、public configuration initializer、iOS rule例外参照を確認 |
| M-05 | △ | Parserは改善済みだが、新規executorのinternal関数に先頭ログがない |
| M-06 | ○ | version bumpの由来は結果レポートに記載された |
| L-01〜L-03 | ○ | 不要attribute / `var` とtimeout task保持を解消した |

## 重大な問題（high）

### H-01: source file sizeを検証できない場合でも、一時領域へコピーを開始する

- `preCopySize` の取得に失敗すると、`else` 側へ入り `fileStore.store` でsource全体をコピーする。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift:234`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift:237`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift:239`
- post-copy sizeを取得できなければ最終的には失敗するが、巨大または特殊なprovider fileを上限なしで一度ディスクへコピーできる。これは設計S6の「copy前にresource file sizeを取得」と、結果レポートの「サイズ検証不能時を失敗扱い」に反する。
- size limitをセキュリティ境界とするなら、pre-copy sizeが取得不能な時点で `fileCopyFailed` とし、copyを開始しない必要がある。取得不能ケースと、oversize fileがcopyされないことをテストすること。

## 改善提案（medium）

### M-01: S11の内部キャンセルcompletionが設計どおりexactly-onceで配信されない

- `PasteItemProviderLoader.cancelAll()` は各handleへ `.cancelled` を発生させるが、先に `session.isCancelled = true` としているため `finishOne` は結果を破棄し、aggregate completionを呼ばない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:94`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:99`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:112`
- `cancelAllSuppressesTheCompletionEntirely` も非配信を期待しており、設計U-84「内部 completion に `.cancelled` が1回」と逆である。
  - `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/PasteItemProviderLoaderTests.swift:88`
- UI callbackを抑止する契約U-90とは分離する必要がある。loader内部completionはcancel結果を1回返し、Receiver/View側がcancelled sessionのUI callbackだけを抑止する構造にするか、設計側で「executor単体completion」を内部completionと呼ぶよう契約を明確化すること。

### M-02: `options.localOnly` の既定値がJSON schemaへ反映されていない

- 設計は`options.localOnly`の既定を`true`としているが、`options: {}` またはexpirationDateだけのobjectは `localOnly` 欠落でinvalid requestになる。
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:1043`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:131`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:135`
- `localOnly`省略時は `true` を使用し、型が存在して不正な場合だけrejectするテストを追加すること。

### M-03: I-10の実測結果と結果レポートが一致しない

- full-module strict buildは両schemeともexit 65で失敗した。確認したerrorは次の13件で、Notification 5件だけではない。
  - Dialog: `IosDialogManager.shared` 1件
  - Notification: `NotificationActionOptions` 3件、`NotificationCategoryOptions` 4件、`NotificationPermissionHelper.shared` 1件、`IosNotificationManager.shared` 1件
  - Share: `ShareSheetPresenter` 2件、`IosShareManager.shared` 1件
- 通常buildにも既存Notificationのdeprecated warningがあり、Unity側にはSwift 6でerrorになるswitch warningがある。したがって現行設計の「両モジュールでwarning / errorなし」は未達である。
- 2つのDoDは論理的な矛盾ではなく、現在のbaselineでは同一Clipboardタスク内で同時達成できないスコープ衝突である。推奨は、既存機能のSwift 6移行を別タスクへ切り出し、本タスクのDoDを「Clipboard差分が新しいstrict診断を追加しないこと」に変更すること。現行I-10を維持するならDialog / Notification / Shareの修正も本タスクの明示スコープへ追加する必要がある。

### M-04: 「不足観点をすべてカバー」の自己評価は正確でない

- `ClipboardAsyncRaceCoordinatorTests` は成功、operation error、timeout、cancel-before-attach、実行中cancelを確認するが、設計U-111のcompletion / cancel / timeout 3者について3通りの到着順とexactly-once回数を検証していない。
  - `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardAsyncRaceCoordinatorTests.swift:12`
- provider executor testにはimage / fileの入力・出力境界、pre/post size取得不能、失敗・timeout・cancel後のtemp cleanupがない。
  - `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardProviderLoadExecutorTests.swift:61`
- 空providerの実装は`failures == [.noMatchingItem]`だが、設計U-83はitems / failuresの双方を空としている。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:70`
  - `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md:1421`
- observer世代テストはstop/start後に新しいnotificationを同期postしているだけで、queue済みの旧observer closureが新購読者へ届かないことを直接再現していない。また `newSubscriberCount <= 1` は新購読者へ1回届くことを保証しない。
  - `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/IosClipboardManagerTests.swift:97`
  - `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/IosClipboardManagerTests.swift:107`

### M-05: 新規internal APIがiOSの先頭ログ規約を満たさない

- `ios.md` はinternal Swift関数の先頭にログを要求するが、少なくとも次の新規関数にログがない。
  - `ClipboardProviderLoadHandle.cancel`: `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift:32`
  - `ClipboardProviderLoadExecutor.requestKind`: `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardProviderLoadExecutor.swift:87`
- 機密値を出さず、kind / countだけを記録すること。規約の対象をpublic/internalの境界APIへ限定する意図なら、実装へ個別追加する代わりに`ios.md`を先に改訂すること。

## 軽微な指摘（low）

### L-01: 実装結果のbuild number説明が最終値を一意に示していない

- 現在の未コミット差分ではIosLibraryは8→9、UnityIosPluginは7→8である。レポートは前段の7→8 / 6→7と「さらにインクリメント」を併記しており、レビュー対象時点の最終値が読み取りにくい。
- 自動処理である説明自体は妥当。結果レポートにはレビュー対象時点の最終値9 / 8も明記すると差分監査が容易になる。

## 設計書整合性チェック

- 企画書との整合性: △ — 主要APIは整合するが、実機T-00 / T-13が未実施
- Clean Architecture準拠: ○ — Domain〜ManagerはIosLibrary、Unity BridgeはUnityIosPluginに配置
- 既存実装との差分分析の正確性: △ — strict errorの件数・対象moduleとテスト網羅の自己評価が実測と異なる
- テスト設計の網羅性: × — U-01〜U-148、I-01〜I-10を全件実装・greenにはしていない
- ドメインエラー全ケース実装: ○ — 24ケースと固定code/messageを維持
- エラーコード/メッセージ対応表との整合: ○ — 追加失敗経路は既存ケースへ正規化される

## プロジェクトルール適合チェック

- common.md準拠: △ — actor / timeout / cancellationは改善したが、S11内部completion契約に差分あり
- ios.md準拠: △ — 同期control例外は反映済み。新規internal関数の先頭ログに不足あり
- エラー契約反映: ○ — 監視開始失敗とmalformed requestは正しいcode/message経路へ入る
- 既存API互換性: ○ — Notification / Dialog / Shareのsource変更はなく、既存公開APIの破壊は確認されない

## テストカバレッジ

### カバーできている主な観点

- attach前Task cancelとtimeout即時復帰
- acceptedTypesによるtext/image選択、custom file UTIの選択
- text / URL loadのoversize拒否
- provider handleのcancel exactly-onceとprovider timeout
- S11の全成功、混在、全失敗、空、session上書き、UI callback抑止
- scope / optionsのpresent-but-malformed拒否
- pasteboard scope / creation requestのログ秘匿
- 監視開始失敗のthrowと基本的なstop/start動作

### 不足している主な観点

- pre-copy size取得不能時にcopyを開始しないこと
- image / fileの入力・出力上限、上限ちょうど、temp file cleanup
- completion / cancel / timeout 3者の全到着順とexactly-once
- S11内部completionのcancelled 1回とUI callback 0回の分離
- `options: {}` のlocalOnly既定値
- queue済み旧observer eventのgeneration gate
- 15 endpoint / 9 content kind / 全detected valuesのBridge end-to-end（I-08）
- ClipboardRedactionの独立module境界テスト（I-09）
- full-module strict build green（I-10）
- 実機M-01〜M-16とサンプルアプリT-12

## 検証結果

- `git diff --check`: 問題なし
- `IosLibrary` generic iOS Simulator build: 成功
- `UnityIosPlugin` generic iOS Simulator build: 成功
- `IosLibrary` tests: 166件、失敗0（iPhone 17 Pro / iOS 26.2 Simulator）
- `UnityIosPlugin` tests: 69件、失敗0（iPhone 17 Pro Max / iOS 26.2 Simulator）
- `IosLibrary` Swift 6 strict build: 失敗（exit 65、Clipboard外を含む13 concurrency errors）
- `UnityIosPlugin` Swift 6 strict build: 依存先IosLibraryの同じstrict errorsにより失敗（exit 65）
- Clipboard sourceに起因するstrict diagnosticは今回の出力では確認されなかった。ただしfull buildが先に失敗するため、I-10完了の証明にはならない

## 総合評価

**要修正（重大）**

v1の主要欠陥は大幅に改善され、通常buildと全既存テストはgreenである。しかし、size limitをセキュリティ境界とする設計に反して、source size取得不能時に無制限コピーへ進む経路が残る。H-01を修正し、S11内部キャンセル契約、JSON既定値、テスト対応表、I-10のスコープと実測記録を整合させてから再レビューが必要である。
