# レビュー結果

- 日付: 2026-08-02
- 対象ファイル: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design.md`
- 機能名: clipboard
- 対象 OS: iOS 18 以降
- 基準企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- レビュー方法: 本モデルによる全文確認、別モデルによる独立レビュー、既存 iOS 実装・共通ルール・Xcode 26.3 SDK による照合、同期・非同期設計ルール追加後の再確認

---

## 強み

- Domain〜Manager を `IosLibrary`、Unity Bridge のみを `UnityIosPlugin` に置く境界と、通知トークンを Manager が単独所有する方針は `common.md` に整合している。
- `NSItemProvider` の exactly-once、発行時登録、cancel gate、一時 URL の所有権、path traversal 防止、起動時 cleanup を具体的な実装契約へ落とし込んでいる。
- 変更監視の再同期、通知経路との二重報告防止、generation gate が明確で、企画書 v4 の改善点を維持している。
- プライバシー確認を iOS 18 / iOS 26、許可プロンプト / アクセス通知に分け、`localOnly` に正の対照を設けている。
- エラー19ケース、エラーコード、英語メッセージ、テストID、タスク依存を同じ文書内で追跡できる構成は良い。
- `PBXFileSystemSynchronizedRootGroup`、Swift Testing、既存 Share の Manager / Bridge 構成に関する差分分析は実リポジトリと一致した。

## 改善点

### 高優先度

- 対象: S4 / 公開 API P-3 / UseCase・Port・Bridge・テスト・タスク（152–163、362–366、635–647、661–675、896–906 行）
  - 問題点: `readData(utType:scope:)` は公開 API と S4 の必須経路に存在するが、`ReadDataUseCase`、Repository Port/Data のメソッド、C ABI、Unity JSON、個別テスト、タスクがない。
  - 影響: P-3 が未実装になるか、Manager が Repository を直接呼び `common.md` の必須経路に違反する。S11 の「S1〜S9をUnity公開」とDoDも満たせない。
  - 改善提案: `ReadDataUseCase` と `ClipboardRepository.readData`、Manager callback/async、`clipboardReadData`、成功/失敗 JSON schema、UTI 検証、UseCase/Data/Manager/Bridge テストを縦断追加する。

- 対象: S10 `ClipboardPasteReceiverView` / `ClipboardItemLoader`（399–424、554–589 行）
  - 問題点: Receiver は `paste(itemProviders:)` で個々の `NSItemProvider` を受け取るが、唯一の loader Port は `scope` から「最初の一致 item」を読む契約で、provider 配列を処理できない。URL load、複数 provider の全件集約、部分失敗を委譲する接続先もない。Port に `NSItemProvider` を追加するとドメイン型限定ルールに違反する。
  - 影響: S10 の中核要件を実装できず、Presentation が Data へ直接依存するか、S5 と重複した loader を暗黙実装することになる。
  - 改善提案: UIKit に閉じた Presentation 用 `PasteItemProviderLoader` などを明示し、Application Port へ UIKit 型を漏らさない。成功0件・混在・順序・failure callback回数・token・一時ファイル所有権を確定し、Presentationテストを追加する。

- 対象: Unity Bridge / Manager callback / エラーコード（65、595–649、657–675、691–765 行）
  - 問題点: C ABI は `errorCode` を要求するが、Manager callback は `(Bool, String?)` 等でコードを返さず、Bridge が型付き `ClipboardError` を失わず変換する経路が未定義である。P-3 `readData` と P-8 `detectPatterns` も C ABI にない。また JSON 仕様が「抜粋」のため、各 endpoint の request/success/error envelope、NULL、未知 kind、Base64 不正時の扱いが未確定。
  - 影響: Bridge が localized message を解析するか独自ロジックを持ち、「薄い Bridge」とエラー対応表が崩れる。S1〜S9 の Unity パリティも成立しない。
  - 改善提案: `ClipboardError` に正式な `errorCode` を定義し、Bridge が Manager の `async throws` を `Task { @MainActor }` で呼んで型付き error を一か所で変換する経路を明記する。全 endpoint と JSON schema、`clipboardReadData` / `clipboardDetectPatterns`、invalid request 専用 error を追加する。

- 対象: `ClipboardItemLoader` Port と Swift 6 strict concurrency（398–424、931、999 行）
  - 問題点: protocol requirement は非 actor-isolated だが、実装を `@MainActor` としている。Swift 6 strict concurrency ではこの conformance は `main actor-isolated instance method cannot satisfy nonisolated requirement` でコンパイルエラーになることを Xcode 26.3 で再現した。現行 project は `SWIFT_VERSION = 5.0` で、I-07 の strict 設定方法も未定義。
  - 改善提案: Port requirement と実装の isolation を一致させる。Repository / Loader / UseCase / Manager / Presentation の actor 境界を宣言単位で決め、専用 configuration または `xcodebuild` 引数を T-11 に記載する。

- 対象: 全公開操作の同期・非同期設計（S1〜S10、公開 API P-1〜P-15、340–424、635–675 行）
  - 問題点: 基準企画書 v4 に「同期・非同期 API 分類表」がなく、本設計にも必須の「同期・非同期レイヤー対応表」がない。公開 API 表は Manager の callback / `async throws` 形式だけを示しており、System API → Repository → UseCase → Manager callback → Manager native → Bridge の各実行方式、完了 thread / actor、変換箇所、キャンセル、リソース所有権を縦断確認できない。そのため、同期 `UIPasteboard` 操作の下位層まで不必要に非同期化しないこと、`NSItemProvider` の callback 完了契約、pattern detection の非同期契約、通知監視の同期 start/stop と非同期 event 配信の区別が設計上固定されていない。
  - 影響: 実装者ごとに Repository / UseCase のシグネチャが変わり、不要な `async` 化、actor hop、callback の二重変換、キャンセル漏れが発生しうる。Manager の公開規約とシステム API の実行方式も混同され、企画書・設計・実装の追跡性を満たせない。
  - 改善提案: 企画書側の不足前提を明記したうえで、全採用 System API を `sync` / `callback` / `async` / `stream` に分類する。続いて全 P-1〜P-15 を対象に、最低限「操作、System API と実行方式、Repository、UseCase、Manager callback、Manager native、Bridge、actor / thread、キャンセル・リソース所有権、方式変換の理由」を列とする対応表を追加する。Repository / UseCase / private helper は System API の方式を維持し、Manager の callback / native async は必要な箇所だけ薄いラッパーとして明記する。同期完了、exactly-once、Task/token cancel競合、event停止後の非配信をテストとDoDへ対応付ける。

- 対象: `ClipboardCopyOptions` と append（306–321、728 行）
  - 問題点: `localOnly` の既定値は `true` だが、`addItems` は privacy option を適用できない。`replaceExisting == false` で「非既定 option のみ拒否」とすると、既定 `true` を黙って無視して安全契約を破る。常に `true` を拒否すると、既定 options の append が必ず失敗する。
  - 改善提案: append を独立 API にして privacy option を受け取らない、または `localOnly: Bool?` のように「未指定」を表現する。許可・拒否条件、既定値、Bridge JSON省略時の挙動を一意にし、テストを追加する。

### 中優先度

- 対象: `PasteboardScope` / create API（267–285、666 行）
  - 問題点: `.unique(String)` は既存 scope の参照を表す一方、作成は引数不要の `withUniqueName()` であり、`createPasteboard(_:)` に何を渡すかが定義されていない。`.general`、既存 unique、named衝突時も未定義。
  - 改善提案: `PasteboardCreationRequest`（`.named(String)` / `.unique`）を参照用 `PasteboardScope` から分離し、全境界ケースとJSONを定義する。

- 対象: 入力検証とドメインエラー完全性（323–336、691–735、777–784 行）
  - 問題点: `multiRepresentation` 内の空Data/UTI、`htmlText.plain`、colorの有限値・0...1、imageDataの画像UTI/デコード可否、named/unique名が未定義である。UTIを「逆DNS形式」で判定すると標準UTIを誤拒否しうる。ファイル/画像検証をUseCase表とRepositoryエラー表の双方へ置いており責務も不一致。
  - 改善提案: 純粋検証とData依存検証を分け、UTIはSDKの型判定へ寄せる。必要な `invalidColor` / `invalidImageData` / `invalidRequest` を決定し、各エラーに発生元・コード・メッセージ・単体/Bridgeテストを対応させる。

- 対象: Domain純粋性 / `ClipboardError`（83、249、294–310、387–391、692–711 行）
  - 問題点: `common.md` は Domain を標準ライブラリのみとしているが、設計は Foundation の `Data` / `Date` / `URL` を Domain に使用し「Foundationのみ」としている。また `providerLoadFailed(Error)` 等が任意の system error を Domain へ保持し、Repositoryでの正規化境界が弱い。
  - 改善提案: canonical rule に従うなら byte配列、epoch、path文字列などのDomain表現へ変換する。Foundationを許容する既存慣例を優先するなら、共通ルールの例外として理由を明記する。underlying error は安定した message/code に正規化する。

- 対象: 企画書との整合性 — provider URL / 画像処理（381–394、417–424、937 行）
  - 問題点: 企画書の標準 provider 対象には URL があるが、`ClipboardLoadRequest` は text/image/file のみ。一方S10の優先順位にはURLがある。また企画書はデコード/エンコードをmain外とするが、`@MainActor` loader上で `pngData()` するよう読める。
  - 改善提案: URL provider loadを提供するか同期readに限定するか明記する。画像変換はbackground workerで実行し、state変更とcallbackだけをmain actorへ戻すフローにする。

- 対象: 自動テスト（180–193、777–869 行）
  - 問題点: S10のloader/receiver/factoryテストがなく、P-3/P-8の縦断テスト、token単体cancel、async Task cancel直後・完了競合、all-success/all-failure/mixed providerの集約テストもない。U-38「全API」だけでは仕様を固定できない。
  - 改善提案: 個別IDを付けてUseCase/Data/Manager/Presentation/Bridgeの各契約を自動テスト化する。

- 対象: タスク依存 / リスク検証順序（894–920、929–938 行）
  - 問題点: `changeCount` と `itemProviders` の採否を左右する実機検証がT-13まで遅く、実装後にS5/S8の再設計が起こりうる。T-08は接続不能なT-06へ依存し、T-14は最終API/Presentation/Bridge確定前に開始可能である。
  - 改善提案: privacy実機スパイクを初期ゲートに移し、Library統合とBridge統合を分離する。S10 loader設計確定後にT-08、全公開API確定後にDocCを置く。

- 対象: 一時ファイル起動cleanup（D-7、436、934 行）
  - 問題点: Managerの各初期化で専用ルート全体を削除すると、test用Managerや複数instanceが同時に存在する場合、別instanceが所有権移譲済みの成功ファイルを削除しうる。
  - 改善提案: processで一度だけのstartup cleanup、session directory、またはage-based cleanupにし、active sessionを削除しないテストを追加する。

### 低優先度

- 対象: `expirationDate`（336、998 行）
  - 問題点: 過去日時を許可しながら拒否/許容判断を実装後へ送っており、初期APIの結果が非決定的である。
  - 改善提案: 初期版では `expirationDate <= now` を専用errorで拒否するか、「即時失効しうる成功」として契約・テストを先に固定する。

- 対象: ログ秘匿（100–120、935、954 行）
  - 問題点: 方針は適切だが、request JSON、Base64、URL/path、underlying error messageをどのhelperでmaskするかと自動検査がない。既存Share BridgeはJSON本文をログ出力するため、単なる踏襲では漏洩する。
  - 改善提案: Clipboard専用のmask/metadata loggerと、禁止値がログへ含まれないテストまたは静的レビュー手順をT-09/T-10へ追加する。

- 対象: Androidとのエラーコード整合（214、741–763 行）
  - 問題点: 「同じ意味」とする一方、Androidの `CLIPBOARD_INVALID_URI` に対しiOSは `CLIPBOARD_INVALID_URL` で、共有可能なケースとiOS固有ケースの区別がない。
  - 改善提案: 共通コードは完全一致させ、iOS固有コードだけを追加する方針にするか、差異表を明示する。

## 不足項目

- `readData` のUseCase→Port→Data→Manager→Bridge→テストの完全な縦断設計
- `UIPasteControl` のprovider配列を処理するPresentation内loaderと集約契約
- 企画書の同期・非同期 API 分類表、および全 P-1〜P-15 を縦断する同期・非同期レイヤー対応表
- actor isolationを一致させたPort/実装/API宣言
- 全Unity endpointのJSON schema、errorCode変換経路、invalid request error
- appendとprivacy optionsを矛盾なく表現する公開API
- unique作成要求と既存scope参照の型分離
- provider URL loadと画像変換スレッドの方針
- S10、per-token/Task cancellation、P-3/P-8、Bridge endpointの自動テスト

## 総合評価

企画書v4の主要リスクをよく設計へ落とし込み、アーキテクチャ、監視、プライバシー、一時ファイル、エラー表、タスク管理の骨格は高水準である。一方、複数の公開APIがUseCase/Port/Bridgeまで接続されておらず、S10は現行loader契約では実装不能、actor isolationはSwift 6でコンパイルエラーになる。さらにappendの安全既定値が`addItems`と矛盾し、全公開操作の同期・非同期レイヤー対応表もないため、System API と各層の実行方式を追跡できない。現状は実装開始前に差し戻し、同期・非同期表を含むすべてのHigh項目を解消したv2を作成すべきである。

## 検証メモ

- Xcode 26.3 / Swift 6 strict concurrencyで、非隔離protocolを`@MainActor` classが満たす最小例はconformance isolation errorになることを確認した。
- `IosLibrary` / `UnityIosPlugin` / `IosLibraryExample` が`PBXFileSystemSynchronizedRootGroup`を採用していることを確認した。
- 現行projectの`SWIFT_VERSION`は5.0であり、strict concurrency用の設定は設計書で追加指定が必要である。
- 基準企画書 v4 と設計書 v1 の双方に、現行ルールで必須の同期・非同期分類表／レイヤー対応表がないことを確認した。
