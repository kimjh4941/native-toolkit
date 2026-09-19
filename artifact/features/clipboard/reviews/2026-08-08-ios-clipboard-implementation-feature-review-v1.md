# iOS Clipboard 実装レビュー v1

## レビュー対象

- 日付: 2026-08-08
- 対象OS: iOS 18以降
- ブランチ: `feature/NTKIT-14`
- 比較差分: `develop...feature/NTKIT-14`
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-02-ios-clipboard-implementation-feature-result-v1.md`
- 差分概要: 93ファイル、16,218行追加、12行削除。ClipboardのDomain〜Manager、Unity Bridge、テスト、規約・成果物を追加

## レビュー概要

- `UIPasteboard` / `NSItemProvider` / `UIPasteControl` をClean Architectureの各層へ分割し、24ケースのドメインエラーと15個のBridge endpointを追加している。
- 通常設定では `IosLibrary` / `UnityIosPlugin` のgeneric iOS Simulator buildが成功した。
- 一方、設計上の必須契約であるS11のprovider load、サイズ上限、監視開始エラー、世代gate、Swift 6 strict concurrency、テストU-01〜U-148などに未達がある。
- 実装結果レポートも未実施テストを記載しているが、実コードにはレポートに記載されていない重大な契約違反がある。

## 重大な問題（high）

### H-01: `UIPasteControl` 経路が `acceptedTypes` と異なる型を返し、file・timeout・実キャンセルを実装していない

- `ClipboardPasteReceiverView.canPaste` は `acceptedTypes` で判定するが、ロード時にはその配列を `PasteItemProviderLoader` へ渡していない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/ClipboardPasteReceiverView.swift:39`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/ClipboardPasteReceiverView.swift:48`
- `PasteItemProviderLoader.loadSingle` はproviderがtextを広告していれば常にtextを優先する。そのため、例えば `acceptedTypes == [public.image]` でもtext+image providerからtextを返しうる。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:104`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:108`
- fileをロードする分岐がなく、custom/file UTIを受け入れても `.noMatchingItem` になる。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:121`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:164`
- `ClipboardTimeouts.providerLoad`、`Progress`、request単位gateを持たず、providerが完了しなければUI pasteが永久に完了しない。`cancelAll()` もsessionを捨てるだけでsystem loadをキャンセルしない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:41`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteItemProviderLoader.swift:70`
- text / URLの `maxLoadByteCount` 検査もない。
- 設計のP-16、U-80〜U-96、U-142、U-147と不一致。accepted typeをloaderへ渡し、text/url/image/fileを同じtimeout・token・exactly-once gate・cleanup契約で処理する必要がある。

### H-02: 非協調的async処理でattach前キャンセルを取りこぼす

- `ClipboardAsyncRaceCoordinator.resolve` はcontinuation未attach時に結果を破棄し、保留結果やcancel flagを残さない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Concurrency/ClipboardAsyncRaceCoordinator.swift:22`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Concurrency/ClipboardAsyncRaceCoordinator.swift:28`
- 既にcancel済みのTaskで `withTaskCancellationHandler` に入るなど、`onCancel` がcontinuation attachより先に走ると `.cancelled` が失われる。その後はsystem完了またはtimeoutまでcallerが待つため、「キャンセル時に即時復帰」を満たさない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Concurrency/ClipboardAsyncRaceCoordinator.swift:49`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Concurrency/ClipboardAsyncRaceCoordinator.swift:68`
- 設計D-14はattach前cancelをflagで回収するよう明記している。`ClipboardCancellationBox` と同様、未attach時の勝者を保持し、attach直後にresumeする必要がある。

### H-03: 監視開始失敗が成功として返り、stop/start境界で古いイベントを新購読者へ誤配信する

- `IosClipboardManager.startObserving` は設計上 `throws` だが、名前付きpasteboardが解決できない場合にログを出してreturnするだけである。
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:297`
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:300`
- Unity facadeはその直後に必ず `startHandler(true, nil, nil)` を返すため、存在しないscopeでも開始成功となる。
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:289`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardManager.swift:293`
- observer closureのgateはscope比較だけで、設計で要求したgeneration IDがない。同じscopeでstop/startした場合、queue済みの旧closureが新しい `onEvent` へ配信されうる。
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:308`
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:311`
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:317`
- `startObserving` を `throws` に戻し、Bridgeで失敗をoperation callbackへ伝播し、購読世代をclosureへcaptureして照合する必要がある。

### H-04: 名前付きpasteboard名が通常ログへ漏れる

- `PasteboardScope` / `PasteboardCreationRequest` を文字列補間しているため、`.named("secret-name")` や `.unique(...)` のassociated valueがログへ出る。
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:87`
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:192`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/PasteboardResolver.swift:22`
  - `ios/IosLibrary/IosLibrary/Clipboard/Application/UseCase/CreatePasteboardUseCase.swift:19`
- 同じraw scope logがManager / UseCase / Repository / Loaderへ広く重複している。
- 設計D-18およびDoDはpasteboard nameをログへ出さないことを要求する。scopeはkindだけを出し、名前は長さなどのredacted metadataに置換する必要がある。

### H-05: size limitが全kindに適用されず、設定上限を超える入力を公開・デコードできる

- P-11のtext / URLロードはUTF-8 byte countを検査せず成功を返す。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardItemLoaderImpl.swift:151`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardItemLoaderImpl.swift:167`
- `.imageFile` copyは存在確認後すぐ `UIImage(contentsOfFile:)` へ進み、設計で要求したdecode前のresource file size検査がない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardRepositoryImpl.swift:141`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Image/ClipboardImageCoder.swift:45`
- file loadはresource size取得に失敗した場合もcopy・成功へ進むため、上限を保証できない。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardItemLoaderImpl.swift:235`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardItemLoaderImpl.swift:247`
- S2/S6とU-141/U-142の契約違反。上限値をセキュリティ境界として扱うなら、サイズ取得不能時も無条件成功にしない設計が必要である。

### H-06: malformedな`scope`を`.general`として処理する

- `scope`省略時だけ `.general` が仕様だが、現在は `"scope": null`、文字列、配列などobject以外の値も `.general` になる。
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:25`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:26`
- named scopeを意図した壊れたrequestがgeneral pasteboardへのcopy / clear / readへ化ける可能性がある。keyの不在と型不正を区別し、後者は `CLIPBOARD_INVALID_REQUEST` にする必要がある。
- 同様に `options` がobject以外の場合、コメントに反して「未指定」として扱われる。
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:119`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:122`

### H-07: Swift 6 strict concurrencyの完了条件を満たしていない

- 通常buildでClipboard自身に「Swift 6ではerror」となる警告を確認した。
  - `ClipboardRepositoryImpl` の `nonisolated init` からmain actor-isolated `fileManager` を設定: `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardRepositoryImpl.swift:23`、`:32`
  - NotificationCenterの`@Sendable` closureからmain actor状態へ同期アクセス: `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:311`、`:312`、`:315`、`:320`、`:321`
- `SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` の `IosLibrary` buildはexit 65で失敗した。既存Dialog / Notificationのエラーも含むが、設計I-10は「両モジュールが警告・エラーなし」を完了条件としており、対象外扱いでgreenにはできない。
- 実装結果の「Clipboard配下のエラー0件」は、現在のSwift 5 buildが出す将来error診断とも整合しない。observer callbackは `Task { @MainActor in ... }` でhopし、initializer isolationも再設計する必要がある。

## 改善提案（medium）

### M-01: `htmlText` のread結果が辞書順序に依存する

- `ClipboardMappers.toItemData` は最初に見つけた `String` をtextへ入れるため、plain textではなくHTML文字列を返しうる。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardMappers.swift:19`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardMappers.swift:24`
- `UTType.plainText.identifier` を明示的に優先し、URLもidentifierベースで決定するべきである。

### M-02: custom UTI検証が設計のASCII制約より広い

- `Character.isLetter` / `isNumber` はUnicodeを許容するため、非ASCII identifierが通る。
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardTypeIdentifierValidator.swift:33`
  - `ios/IosLibrary/IosLibrary/Clipboard/Data/Repository/ClipboardTypeIdentifierValidator.swift:37`
- 設計どおりASCII英数字・`-`・`_`・dotだけに制限するべきである。

### M-03: timeout / limitsをnative callerが設定できない

- 設計は `IosClipboardManager.init(timeouts:limits:)` で差し替え可能としているが、実装はprivate singleton initとinternal test initだけである。
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:58`
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:68`
- 実機調整やnative利用時に固定値しか使えない。public initializerまたは明示的なconfiguration APIが必要である。

### M-04: canonical rule更新が設計どおり完了していない

- T-Rは `common.md` と `ios.md` の双方を更新する設計だが、`ios.md` に同期control / factory例外が追加されていない。実装結果も意図的な未変更としている。
- 重複回避なら、少なくとも `ios.md` から `common.md` の例外規定へ明示的に参照させ、iOS固有の「常にasync throws」という記述との衝突を解消するべきである。

### M-05: iOSログ規約の自己評価が正確でない

- `ios.md` はpublic/internal関数の先頭ログを要求するが、`UnityIosClipboardJsonParser` のinternal関数群などにログがない。
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:19`
  - `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/UnityIosClipboardJsonParser.swift:25`
- 実装結果の「全public/internal/override/@objc関数にログあり」は修正が必要。機密値を含めない専用metadata logとの両立も一括確認するべきである。

### M-06: 実装結果の変更ファイル説明が差分と一致しない

- 設計はproject file編集不要としているが、実差分では両projectの `CURRENT_PROJECT_VERSION` が更新されている。
  - `ios/IosLibrary/IosLibrary.xcodeproj/project.pbxproj:236`
  - `ios/UnityIosPlugin/UnityIosPlugin.xcodeproj/project.pbxproj:250`
- 実装結果の「既存変更」に記載がない。意図したversion bumpなら結果レポートへ理由と影響を追記するべきである。

## 軽微な指摘（low）

- `@discardableResult` をVoid返却の `copy` / `append` へ付けており、compiler warningになる。
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:91`
  - `ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift:112`
- `UIPasteControl.Configuration` は参照型であり、`var` が不要というwarningが出る。
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/ClipboardPasteControlContainerView.swift:44`
  - `ios/IosLibrary/IosLibrary/Clipboard/Presentation/PasteControlFactory.swift:29`
- `ClipboardAsyncRaceCoordinator` は勝敗決着後もtimeout taskをcancelしないため、成功操作ごとに最大5〜10秒coordinatorを保持する。timer task handleを保持して決着時にcancelするとよい。

## 設計書整合性チェック

- 企画書との整合性: △ — 主機能は実装されているが、S11と実機プライバシー検証が未達
- Clean Architecture準拠: ○ — Domain〜ManagerをIosLibrary、Unity BridgeをUnityIosPluginへ配置
- 既存実装との差分分析の正確性: △ — project version変更とstrict concurrency警告が実装結果へ正確に反映されていない
- テスト設計の網羅性: × — U-80〜U-96、U-109〜U-111、U-116〜U-148の相当部分とI-01〜I-10が未実装・未確認
- ドメインエラー全ケース実装: ○ — 24ケースとcode/messageを実装
- エラーコード/メッセージ対応表との整合: ○ — 固定code/messageは設計表と一致

## プロジェクトルール適合チェック

- common.md準拠: △ — 層分離は適合するが、非同期timeout / cancellation / exactly-once契約がS11で未達
- ios.md準拠: × — Swift 6 actor isolation、全internal関数の先頭ログ、機密ログ秘匿に違反
- エラー契約反映: △ — 通常operationは整合するが、監視開始失敗を成功として返す
- 既存API互換性: ○ — 既存Notification / Dialog / Share APIの破壊的変更は確認されない

## テストカバレッジ

### カバーできている主な観点

- `ClipboardError` 24ケースのcode/message
- validator、change tracker、主要UseCaseの代表ケース
- `.unique` pasteboardによるcopy/read/append/clearの代表ケース
- custom UTI、temporary fileの基本的なpath traversal対策
- Manager callbackの一部とBridge JSON parserの代表ケース

### 不足している主な観点

- `PasteItemProviderLoader` / Receiver / Containerの専用テストが存在しない。Presentation配下はManagerテストのみ
- cancel-before-attach、cancel / completion / timeoutの3者競合
- text / URL / image / fileの全サイズ境界とcleanup
- observerの同一scope stop/start世代gate、開始失敗
- 15 endpoint、9 content kind、全detected values、全loaded itemのend-to-end
- Bridgeのmalformed scope/options
- Swift 6 strict buildの両モジュールgreen
- 実機M-01〜M-16

テスト宣言数はIosLibrary Clipboardが79、Unity Clipboardが18で、設計U-01〜U-148を網羅していない。実装結果もこの不足を認識しているため、DoDをgreenとして扱うことはできない。

## 検証結果

- `git diff --check develop...HEAD`: 問題なし
- `IosLibrary` generic iOS Simulator build: 成功
- `UnityIosPlugin` generic iOS Simulator build: 成功。ただしClipboardのSwift 6移行エラー候補を含むwarningあり
- `IosLibrary` Swift 6 strict build: 失敗（exit 65）。既存機能のエラーに加え、通常buildでClipboard actor-isolationの将来error診断あり
- テスト: 現環境に利用可能なiOS Simulator実体がなく、再実行不可。実装結果記載の過去実行結果は参照したが、本レビューでは再現確認できていない

## 総合評価

**要修正（重大）**

S11、監視開始、キャンセルrace、サイズ上限、ログ秘匿、Swift 6 strict concurrencyが公開契約またはDoDを満たしていない。特にH-01〜H-07を修正し、欠落テストを追加してから再レビューが必要である。
