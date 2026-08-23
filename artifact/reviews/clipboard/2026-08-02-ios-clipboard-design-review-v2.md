# 再レビュー結果

- 日付: 2026-08-02
- 対象ファイル: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v2.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-02-ios-clipboard-design-review.md`
- 基準企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 機能名: clipboard
- 対象 OS: iOS 18 以降
- レビュー方法: 本モデルによる全文・前回指摘追跡、別モデルによる独立再レビュー、`common.md` / `ios.md` / design workflow、Xcode 26.3 iOS 26.2 SDK interface との照合

---

## 強み

- 前回 High の `readData` 縦断、S11 provider 配列用 loader、Bridge endpoint、actor 宣言、同期・非同期表、append 分離を設計へ追加している。
- 「採用 System API の実行方式分類」と P-1〜P-16 のレイヤー対応表により、同期 / callback / async / stream の違いを追跡できる骨格になった。
- `PasteboardCreationRequest` の分離、URL provider load、入力検証の責務分割、一時ファイルの session / age-based cleanup は前回指摘を具体的に解消している。
- `ClipboardError.errorCode`、全 endpoint 一覧、Manager / Bridge テストを追加し、Unity パリティの追跡性が向上した。
- privacy 実機スパイクを T-00 へ移し、Library と Bridge の統合タスクを分けた順序は妥当である。
- Markdown のコードフェンスは対応しており、禁止された `jp.ubint` identifier は含まれていない。

## 改善点

### 高優先度

- 対象: actor isolation / Manager / token cancellation（119–142、354–371、539–579、856–877 行）
  - 問題点: `ClipboardLoadToken.cancel()` は `@MainActor` だが、Manager native 版の `withTaskCancellationHandler` の同期・`@Sendable` な `onCancel` から直接呼ぶ設計である。また `IosClipboardManager` を nonisolated としながら、P-11 callback 版は main actor-isolated token を同期返却し、P-12〜P-16 は `@MainActor` の Loader / UIKit /状態を同期操作する。`Task { @MainActor }` では同期戻り値を返せず、Swift 6 strict concurrency で実装できない。
  - 影響: v1 の protocol conformance mismatch は直ったが、Manager 境界で別の isolation / Sendable エラーになる。同期・非同期表の P-11〜P-16 も実際のシグネチャと一致しない。
  - 改善提案: UIKit と同期状態を扱う Manager メソッドを宣言単位で `@MainActor` にする。任意スレッド受付は Bridge facade に限定して main actor へ hop する。Task cancellation が必要なら、`Sendable` かつ `nonisolated cancel()` を持つ thread-safe proxy token、または actor へ安全に転送する cancellation box を設計し、P-11 の同期 token 返却契約を確定する。`ios.md` が求める Manager callback / native async 併設と同期 control API の関係も、例外をルール側へ追加するか薄い wrapper を追加して整合させる。

- 対象: 非同期 API の timeout・サイズ上限・実キャンセル契約（91–142、519–594、661–683、1212–1227 行）
  - 問題点: `common.md` が非同期 API に要求する timeout が分類表・レイヤー表・詳細設計のいずれにもない。企画書 v4 が画像処理に要求するサイズ上限と timeout も未反映である。P-9 / P-10 は「Task キャンセルで中断」と断定するが、採用する `detectedPatterns` / `detectedValues` に明示的 cancellation token はなく、OS 処理の中断保証が定義されていない。P-11 / P-16 は provider が完了しない場合の管理表・一時領域の解放期限がない。
  - 影響: 応答しない provider、大容量画像、cancel / completion / timeout の競合でメモリ・タスク・一時ファイルが長時間残る。表と実装の cancellation semantics も不一致になる。
  - 改善提案: P-9〜P-11 / P-16 に timeout 値、起算点、所有者、`timedOut` error、cleanup、競合 gate を定義する。System API の中断保証がない場合は「呼び出し側への配信を gate で抑止し、遅延結果を破棄」とする。入力 / 出力 byte・pixel 上限と、cancel-vs-completion-vs-timeout のテストを追加する。

- 対象: P-10 `detectValues` の UseCase と結果モデル（153、276–280、336–339、661–683、1033–1056、1241 行）
  - 問題点: P-9 と P-10 を `DetectPatternsUseCase` 1 個で扱い、`DetectValuesUseCase` が追加ファイル・タスクにない。さらに `ClipboardDetectionPattern` は `postalAddress` / `calendarEvent` / `flightNumber` / `moneyAmount` / `shipmentTrackingNumber` を列挙するが、`ClipboardDetectedValues` に対応する値フィールドがない。
  - 影響: 企画書の `UIPasteboard.DetectedValues` 採用項目を Domain へ変換できず、P-10 の結果が欠落する。「Manager は UseCase 経由」と全 API 網羅性も満たせない。
  - 改善提案: `DetectValuesUseCase` を独立追加し、残り 5 種を platform 非依存の Domain model で表現する。Mapper、JSON schema、UseCase / Data / Manager / Bridge テスト、タスクを縦断追加する。

- 対象: Unity Bridge JSON schema / error delivery（755–850 行）
  - 問題点: 「全 endpoint の JSON schema」とするが、`content` 9 union、pattern / detected value 全項目、scope の kind 別 required field が `{...}` や例示のままである。`clipboardStartObserving` は request 不正を返す operation callback を持たず、change event callback に error envelope を返すかも未定義である。read 系の値を返せない `run(_:handler:) -> Void` 例しかなく、JSON変換の型付き経路と C 文字列の有効期間もない。
  - 影響: Bridge 実装者が discriminator、optional / null、失敗通知、文字列解放規約を推測する必要があり、前回 High の「完全な schema」は一部解消に留まる。
  - 改善提案: 9 content kind と全 request / response union を required / optional / nullable まで表で定義する。observe 開始失敗の専用 callback または同一 callback の envelope 規約を決める。operation / value の generic runner、UTF-8 C 文字列の所有・有効期間、NULL callback の扱いを明記する。

- 対象: Bridge logger のモジュール境界（202–225、246–300、824–850 行）
  - 問題点: `ClipboardLog` は `IosLibrary` module の `internal` Swift enum だが、別 module の `UnityIosPlugin`、さらに Objective-C `.m` の全 C 関数から `ClipboardLog.redact(json:)` を呼ぶ設計になっている。この可視性と ObjC interoperability では呼び出せない。
  - 影響: Bridge がコンパイルできないか、実装時に秘匿 logger を迂回して request JSON を出力する危険がある。
  - 改善提案: `UnityIosPlugin` 内に Bridge 専用 redaction helper を置くか、IosLibrary に Objective-C 公開可能な facade を用意する。Swift facade / `.m` それぞれの呼び出し形と module build test を追加する。

- 対象: P-16 `UIPasteControl` receiver の生成・保持（687–751、856–877 行）
  - 問題点: 詳細設計の `PasteControlFactory` は外部から `receiver` を受け取り、呼び出し側へ receiver も view 階層に追加するよう要求する。一方 Manager API は callback 群だけを受け取る形で、receiver を引数にも戻り値にも含めない。Manager が内部生成した場合、control の target だけでは receiver の寿命と view hierarchy 参加を保証できない。
  - 影響: receiver が解放される、responder chain に入らない、または呼び出し側が必要な View を取得できず、ボタンを表示しても paste callback が動かない可能性がある。
  - 改善提案: control と receiver を強保持する公開 container viewを返すか、`PasteControlComponents(control:receiver:)` を返して配置責務を明示する。Manager / Factory のシグネチャ、所有権、deinit cancellation、テストを同じ契約へ揃える。

- 対象: append の privacy 契約（428–444 行）
  - 問題点: append を options から分離した点は正しいが、「追記時のプライバシー設定は直前の copy のものが残る」と断定する根拠がない。`addItems(_:)` 自体は `localOnly` / `expirationDate` を受け取らず、新規追加 item に既存 option が継承される保証を設計で示していない。
  - 影響: 機微データを append した利用者が Universal Clipboard 抑止や失効を期待し、実際には保証されない可能性がある。
  - 改善提案: 継承を公式仕様または T-00 実機スパイクで確認するまでは保証しない。初期版で general pasteboard の sensitive append を非推奨 / 禁止とするか、安全要件がある場合は既存 items を読み直して `setItems(_:options:)` で置換する別 API として設計する。

### 中優先度

- 対象: S7 `itemSet(withPasteboardTypes:)`（62–85、91–105、597–611、856–877 行）
  - 問題点: In scope と System API 分類に採用すると記載したが、`snapshot(scope:)` は検索 UTI を受け取らず、一致した item index も返さない。実際の利用箇所が未定義である。
  - 改善提案: `snapshot(matchingTypes:scope:)` 等で index set を Domain 型として返すか、`itemSet` を内部限定 / 非採用へ変更し、企画書との差分を新規設計判断に記載する。

- 対象: S11 cancellation contract（561–570、713–725、940–945、1086–1101 行）
  - 問題点: エラー表では Presentation loader の cancel が `.cancelled` 発生元だが、U-66 は cancel 時に結果を配信しない。S6 の「cancel も completion 1 回」と同一 token protocolを使いながら契約が異なる。
  - 改善提案: loader内部 completion の exactly-once と UI callback の抑止を分けて定義するか、P-16 でも `onPasteFailure(.cancelled)` を 1 回返すかを確定する。

- 対象: `readData` の UTI 検証責務（467–478、500–511、1043–1045 行）
  - 問題点: `UTType` 検証を Data 層へ置く一方、U-26 は UseCase が不正 UTI を検出して Repository を呼ばないとしており矛盾する。
  - 改善提案: Data 層で検証するなら U-26 と縦断表を修正する。UseCase で事前検証するなら platform 非依存 Port として注入し、Application に `UTType` を持ち込まない。

- 対象: Clean Architecture 自己評価 / DoD（146–171、1233–1243 行）
  - 問題点: 実際の UseCase は10種で、P-12〜P-14 / P-16 は Manager / Presentation 所有なのに「全16操作に対応する UseCase」としている。また P-12〜P-16 は通常の callback + `async throws` 併設ではない。Domain の Foundation 依存も R-11 で「要合意」のまま `common.md` 適合としている。
  - 改善提案: Dataアクセスを伴う操作だけを UseCase 必須として正確に列挙し、Manager所有操作の例外理由を示す。Foundation を許容するなら先に canonical rule を変更し、許容しないなら byte列 / epoch / path文字列へ変換する。未合意状態で「適合」「合意済み」としない。

- 対象: `ClipboardFailureDetail.message` と公開エラー文言（173–185、950–977 行）
  - 問題点: `localizedDescription` は locale・OS・provider依存であり、「英語へ正規化」「Bridge JSONが決定的」という記述と両立しない。
  - 改善提案: 公開 message は error case ごとの固定英語文にし、診断情報は domain / code だけを保持する。system messageを保持する場合は非決定的・非公開の debug情報として分離する。

- 対象: testability / task dependencies（1026、1175–1207 行）
  - 問題点: `expirationDate <= now` は Clock 注入がなく境界テストが不安定になりうる。T-11a は `UnityIosPlugin` の strict build を完了条件に含むが、Bridge 実装 T-10 に依存していない。
  - 改善提案: Validator に Clock / `now` closure を注入する。T-11a を IosLibrary 限定にするか T-10 依存を追加する。

### 低優先度

- 対象: 参照 ID（225、500–511、1001–1138 行）
  - 問題点: P-4 のテスト参照 `U-13 / U-14 / U-31 / U-47 / U-57` は実際の readData テスト ID と一致しない。ログテストを U-58 とする記載も、実表では U-61 である。
  - 改善提案: P-4 は U-25〜U-27 / U-44 / U-77 / U-97 または該当 Bridge testへ修正し、全文のID参照を機械的に照合する。

- 対象: エラー件数・未知エラー定数（776、892–993、1182、1327 行）
  - 問題点: iOS 固有コード数が14 / 15で揺れ、22ケースから共通4ケースを引いた件数とも一致しない。コード例の `ClipboardError.unknownCode` も型定義にない。
  - 改善提案: error case / code の単一一覧から件数を算出し、`unknownCode` を正式APIに追加するか `.unknown(...).errorCode` と同じ定数源を定義する。

## 不足項目

- Swift 6で成立する Manager / token / cancellation proxy のactor設計
- P-9〜P-11 / P-16 のtimeout、サイズ上限、timeout error、3者競合テスト
- `DetectValuesUseCase` と全 `DetectedValues` 項目のDomain model / Mapper / JSON / tests
- 9 content kind を含む完全なJSON union schema、observe開始失敗経路、C文字列寿命
- UnityIosPlugin / Objective-C から利用可能な秘匿logger
- `UIPasteControl` と receiver を同時に保持・配置できる公開API
- append itemの `localOnly` / `expirationDate` 保証可否
- `itemSet(withPasteboardTypes:)` の採用または非採用判断
- canonical ruleとDomain Foundation依存の正式な合意

## 前回レビュー指摘の解消状況

| 前回指摘 | 判定 | コメント |
|---|---|---|
| `readData` 縦断 | 一部解消 | 全層は追加されたが、UTI検証責務とテストIDが不一致 |
| S11 provider配列の接続先 | 一部解消 | loaderは追加。cancel契約とreceiver寿命が未確定 |
| Bridge errorCode / endpoint / schema | 一部解消 | codeとendpointは追加。完全schema・開始失敗・logger境界が残る |
| actor isolation | 未解消 | Port conformanceは解消したが、Manager/token境界が実装不能 |
| 同期・非同期レイヤー表 | 一部解消 | 表は追加。timeout・実キャンセル可否・actor実現性が不足 |
| append / privacy options | 一部解消 | API分離は解消。option継承の断定は未検証 |
| create request / scope分離 | 解消 | 境界ケースも追加済み |
| URL provider / background画像変換 | 一部解消 | APIとexecutorは追加。サイズ上限・timeoutが不足 |
| 自動テスト不足 | 一部解消 | 大幅拡充。timeout、全DetectedValues、P-16寿命等が不足 |
| task順序 / cleanup / expiration / log方針 | 概ね解消 | 一部の依存・参照ID・module可視性を要修正 |
| Domain純粋性 | 未解消 | 設計内の例外宣言だけでcanonical rule未変更 |

## 総合評価

v2 は前回レビューの多くを具体的に反映し、同期・非同期の分類と全層対応表も追加された。ただし、その表の P-11〜P-16 は actor isolation と同期戻り値の関係上そのまま実装できず、非同期APIのtimeout・サイズ上限もない。`detectValues` の値モデル、完全なBridge schema、Bridge loggerのmodule境界、PasteControl receiverの寿命、appendのprivacy保証にも実装阻害または安全性上の欠落が残る。

総合判定は **要差し戻し**。少なくとも高優先度項目を解消した設計 v3 を作成してから実装へ進むべきである。

## 検証メモ

- Xcode 26.3 / iOS 26.2 SDK interface で、採用した `detectedPatterns(for:)` / `detectedValues(for:)` が `async throws` であることを確認した。
- 別モデルも、actor / token cancellation、timeout、`detectValues`、Bridge logger のmodule境界を実装阻害要因として独立に指摘した。
- 対象設計の Markdown code fence は42個で対応している。
