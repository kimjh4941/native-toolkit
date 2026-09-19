# 第3回レビュー結果

- 日付: 2026-08-02
- 対象ファイル: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v3.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-02-ios-clipboard-design-review-v2.md`
- 基準企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 機能名: clipboard
- 対象 OS: iOS 18 以降
- レビュー方法: 本モデルによる全文・前回指摘追跡、別モデルによる独立再レビュー、`common.md` / `ios.md` / design workflow、Xcode 26.3 iOS 26.2 SDK header / interface、Swift 6 strict concurrency 最小コードとの照合

---

## 強み

- `ClipboardCancellationBox` の提示コードは Swift 6 strict concurrency で型検査に成功し、v2 の cancellation handler から `@MainActor` token を直接呼ぶ問題を解消している。
- `DetectValuesUseCase` と不足していた5種類のDomain modelが追加され、`DDMatchPostalAddress` / `CalendarEvent` / `FlightNumber` / `MoneyAmount` / `ShipmentTrackingNumber` のフィールドはXcode 26.3 SDK headerと一致した。
- timeout、サイズ上限、単一gate、OS処理の中断を保証しない方針がレイヤー表・詳細設計・エラー・テスト・DoDへ追加された。
- 9 content kindを含むJSON union、observe開始結果callback、generic runner、C文字列寿命が追加され、Bridge仕様は大幅に具体化した。
- `ClipboardRedaction` facade、`ClipboardPasteControlContainerView`、appendのprivacy非保証、UTI validating Port、Clock注入は前回指摘への適切な改善である。
- エラー24ケースと対応表24行、単体テストU-01〜U-131の定義行は重複なく一致している。コードフェンス44個も対応している。

## 改善点

### 高優先度

- 対象: P-1 / P-2 の画像前処理と同期・非同期レイヤー表（111、123–154、164–165、181–188、524–596 行）
  - 問題点: `copy` / `append` は Repository・UseCaseを同期、timeoutなし、Manager以下を`@MainActor`としている。一方、`imageData` / `imageFile`は`ClipboardImageCoder`のbackground executorでdecode・pixel検証を行い、`imageCoding` timeoutを適用する設計である。同期UseCaseからbackground処理の完了を非同期に待つことはできず、mainで同期実行すると企画書の「画像処理はmain外」に違反する。
  - 影響: レイヤー表どおりのシグネチャでは画像copy/appendを実装できない。
  - 改善提案: 「pasteboardへの書き込みはsyncだが、画像前処理が非同期」という2段階フローに分ける。画像前処理Portを非同期化し、少なくとも画像を含みうるCopy/Append UseCaseを`async throws`とするか、content準備UseCaseと同期write UseCaseを分離する。P-1/P-2にもimage timeout、Task cancellation、cancel / completion / timeout競合テストを追加し、方式変換理由を表へ明記する。

- 対象: P-9 / P-10 のTask cancellation・timeout coordinator（113–120、172–173、760–818、1281–1284、1490 行）
  - 問題点: 「Taskキャンセル時は配信抑止」とするだけで、呼び出し中の`async throws` APIを何のerrorで、いつ完了させるかがない。非協調的なOS async処理を通常のstructured task groupでtimeoutと競争させると、timeout側が勝ってもgroup scope終了時にOS側childの完了を待つ可能性がある。
  - 影響: 5秒timeoutまたはTask cancel後もnative callerが復帰せず、設計したtimeout契約を満たせない可能性がある。
  - 改善提案: continuationまたは独立race coordinatorを定義し、callerにはcancel時に`CancellationError`または`.cancelled`、timeout時に`.timedOut(.detection)`を直ちに1回返す。OS処理は別所有で継続させ、遅延結果だけをgateで破棄する。cancel即時完了、timeout後にOS完了を待たないこと、遅延結果破棄を個別テストにする。

- 対象: `@MainActor`型のdeinit cleanup（427–433、687、699、756、839、868、1343、1361 行）
  - 問題点: Manager / Loader / Containerの通常`deinit`からactor-isolatedな`stopObserving()` / `cancelAll()`等を呼ぶ契約である。Swift 6 strict concurrencyの最小例で、通常`deinit`から`@MainActor` methodを呼ぶと`ActorIsolatedCall` compile errorになることを再現した。
  - 影響: v3のactor境界でもcleanup実装がstrict buildを通らない。
  - 改善提案: 対応compilerで`isolated deinit`を明示するか、nonisolatedかつSendableなcleanup handleへ委譲する。Manager / Loader / Containerそれぞれの実コードをI-10対象にし、deinit後のtoken解除・一時ファイル削除も検証する。

- 対象: Manager公開規約とcallback schema（175–188、199–203、244–255、616–627、884–919、1061–1085 行）
  - 問題点: `ios.md` 82–93行は新規Managerにcallback版とnative `async throws`版を必須としている。`common.md`の「提供してよい」はiOS固有の必須規定を無効化する根拠にはならず、P-12〜P-16の一括除外を「適合」とは判定できない。また`read` / `readData`等のcallbackには`Bool`がなく、本文の統一形 `(Bool, errorCode, errorMessage)`とも不一致である。
  - 影響: canonical rule、API表、Manager実装、Bridge変換のどれを正とするか実装者が判断できない。
  - 改善提案: 即時control/factory APIを単一同期形式にする意図なら、`ios.md`へ明示的な例外を先に追加する。そうでなければ規約どおりwrapperを併設する。P-1〜P-11のcallbackを `(Bool, value?, errorCode?, errorMessage?)` へ統一し、成功・失敗時のnil条件を定義する。

- 対象: P-12 / P-15 のUseCase経路（175、178、188–201、731–756、1079–1085、1510–1511 行）
  - 問題点: 「P-12〜P-16はData層に触れない」とするが、P-12はData実装を持つ`ClipboardItemLoader.cancelAll()`を操作し、P-15はRepositoryから現在の`changeCount`を取得しなければ成立しない。レイヤー表自身もP-15のRepository / UseCaseを`S`としており、本文・DoDと矛盾する。
  - 影響: ManagerがLoader / Repositoryを直接呼び、`common.md`のManager→UseCase→Data経路へ違反するか、P-12 / P-15が実装不能になる。
  - 改善提案: `CancelAllLoadsUseCase`と`CheckForegroundChangeUseCase`を追加するか、既存UseCaseに複数操作を持たせる正式な例外を定義する。P-13 / P-14はManagerのlistener所有責務、P-16はPresentation factoryとしてUseCase不要と個別に分類し、「P-12〜P-16」を一括扱いしない。

- 対象: custom UTI validation（527–537、578–585、1303–1305 行）
  - 問題点: 全UTIを`UTType(_:)`で解決できることを条件にすると、host appで型宣言されていない`com.jonghyunkim.nativetoolkit.custom-payload`はnilとなり、企画書の任意custom UTIを拒否する。ローカル環境でも当該identifierが`UTType(_:) == nil`であることを確認した。
  - 影響: `customData` / `multiRepresentation`の主要要件が動作しない。
  - 改善提案: `customData` / `multiRepresentation`は標準UTIを誤拒否しないidentifier構文検証と、未登録reverse-DNS identifierの許容を組み合わせる。`imageData`だけは既知`UTType`への解決と`.image`適合を要求する。`com.jonghyunkim.nativetoolkit.custom-payload`未登録時の成功テストを追加する。

### 中優先度

- 対象: サイズ上限の全kind適用（137–153、558–594、633–700 行）
  - 問題点: `maxCopyByteCount`は主に`Data`合計だけを検証し、plain/html/URL/multipleTextのUTF-8 byte、`imageFile`のfile sizeを定義していない。`maxLoadByteCount`もtext/URL/fileと画像encode後Dataへの適用箇所が不完全である。
  - 改善提案: 9 content kindと4 loaded item kindごとのbyte計算表を追加する。fileはcopy前、text/URLはUTF-8化後、画像は入力byte・pixel・出力byteをそれぞれ検証し、合計時の整数overflowも防ぐ。

- 対象: `ClipboardTimeouts` / `ClipboardLimits`公開初期化（125–149 行）
  - 問題点: public structのmemberwise initializerはpublicにならないが、Managerから外部差し替え可能としている。0以下・極端値の扱いもない。
  - 改善提案: 明示的な`public init`と、有限・正数・上限関係のvalidation / errorを定義する。外部設定を不要とするなら型とManager initializerをinternalにする。

- 対象: `DetectedValues` optional変換（769–807 行）
  - 問題点: SDK上の`probableWebURL` / `probableWebSearch`はnonoptional `String`だが、Domainはoptionalである。
  - 改善提案: 対応patternが未検出の場合、空文字をnilへ変換する等の規則をMapper契約とテストへ追加する。

- 対象: JSON / C callbackの残存省略（921–1055 行）
  - 問題点: schemaは改善したが、change eventのkind別required / optional / nullable、operation callbackの成功・失敗時文字列nil条件、error `details`を付けるcaseが未定義である。
  - 改善提案: event unionとoperation callback truth tableを追加し、`details`の対象errorを列挙する。

- 対象: 公開error文言と秘匿（226–240、1172–1201、1522–1523 行）
  - 問題点: 固定文を掲げる一方、URL、path、pasteboard name、invalid reasonを公開messageへ埋め込む。ios.mdの全parameterログ規約を機械的に実装すると、これらがログへ再流入しうる。
  - 改善提案: 公開messageを値なしの固定文へ統一し、入力値は非公開diagnostic detailへ分離する。error object自体をログする場合もredaction helperを必須とする。

- 対象: P-16 accepted types（838、1425 行）
  - 問題点: `acceptedTypes`は必須引数だが、M-10は「未設定時」を試験する。空配列・不正UTI時の挙動もない。
  - 改善提案: 空配列を拒否してthrowする、既定型を補う、disabled controlを返す、のいずれかを固定し、Manager signatureとtestを合わせる。

- 対象: Bridgeでの同期control操作（175–179、385–396、1019–1022 行）
  - 問題点: C関数は任意スレッドからnonisolated facadeへ入り、main actorへ非同期hopするため、Manager上で同期でも`clipboardCancelLoads` / `clipboardStopObserving`はC callerへ戻る時点で完了していない。停止後イベントやキャンセル完了との順序保証がない。
  - 改善提案: Bridgeではfire-and-forgetであると明記するか、完了callbackを追加する。特にstop後の非配信境界をtestする。

- 対象: 公開補助型の可視性（1091–1099 行）
  - 問題点: `ClipboardCancellationBox`はData層の内部実装だがpublicとしている。Managerと同一moduleで使うためpublicである必要がない。
  - 改善提案: internalへ下げ、public API surfaceを縮小する。

### 低優先度

- 対象: テストID参照（276、627、874 行）
  - 問題点: 定義行U-01〜U-131は連番だが、本文参照が一致しない。logger公開はU-114（U-104ではない）、P-4 Manager / BridgeはU-100 / U-124付近（U-86 / U-110ではない）、UI cancel契約はU-84 / U-90（U-79ではない）。
  - 改善提案: ID定義だけでなく本文からの参照先も機械照合する。

- 対象: append非保証の記載先（551 行）
  - 問題点: DocC・Bridge header・エラー表の3箇所へ記載するとするが、error対応表には該当する注記がない。
  - 改善提案: エラー表ではなくAPI制約表へ記載するか、対応表に注記を追加する。

## 不足項目

- 画像copy/appendのbackground前処理を含む実行方式と縦断シグネチャ
- 検出APIのcancel / timeout時にcallerを即時完了させるrace coordinator
- `isolated deinit`またはnonisolated cleanup handleの明示
- P-12 / P-15のUseCase経路
- Manager同期control APIに対する`ios.md`上の正式な例外
- 未登録custom UTIを許容するvalidation契約
- 全content / loaded item kindのサイズ算定規則
- R-11のcanonical rule改訂

## 第2回レビュー指摘の解消状況

| 第2回指摘 | 判定 | コメント |
|---|---|---|
| Manager / token actor設計 | 一部解消 | CancellationBoxは成立。deinit isolationが残る |
| timeout / size / cancellation | 一部解消 | 値とgateは追加。copy画像前処理、検出race、全kindサイズが不足 |
| DetectValuesモデル | 解消 | SDK headerとも一致 |
| Bridge JSON / error delivery | 概ね解消 | event unionとcallback nil条件を補足すべき |
| Bridge logger境界 | 解消 | facadeとmodule build testあり |
| PasteControl receiver寿命 | 解消 | containerで強保持・subview化 |
| append privacy | 解消 | 非保証・非推奨・実機確認へ変更 |
| itemSet利用 | 解消 | `matchingItemIndexes`へ反映 |
| S11 cancel契約 | 解消 | internal completionとUI callbackを分離 |
| UTI責務 | 一部解消 | Port分離は解消。custom UTIの許容条件が誤り |
| Foundation依存 | 判断待ち | 案Aを下記の限定条件で推奨 |
| 固定error message | 一部解消 | localizedDescriptionは排除。入力値埋め込みが残る |
| Clock / task依存 | 解消 | 注入とT-11b依存を修正 |
| ID / error件数 | 一部解消 | 24件は一致。本文ID参照が残る |

## R-11の判断

**案Aを推奨する。** ただし`Foundation`全体を「標準ライブラリに準ずる」と広く許可せず、次のように限定する。

- Domainで許容するのは、`Data` / `Date` / `URL` / `UUID`など、platform UIに依存せず`Sendable`な値型
- `UIKit` / `AppKit`、system service object、delegate、platform API objectは不許可
- public APIで許容するFoundation型を列挙するか、上記条件を満たすことを設計レビューで確認する
- `NSError`や任意のsystem `Error`はDomainへ保持しない

案Bは変換コードを増やし、型安全性と既存Share / Notification実装との整合性を悪化させる。

## 総合評価

v3はv2の7件を概ね反映し、設計品質は大きく向上した。ただし、画像copy/appendの同期・非同期矛盾、検出APIのcancel/timeout完了方式、actor-isolated deinit、Manager規約とP-12/P-15経路、custom UTI validationが実装阻害要因として残る。

総合判定は **要差し戻し**。R-11は案Aで決着してよいが、上記Highを修正したv4を作成してから実装へ進むべきである。

## 検証メモ

- `ClipboardCancellationBox`最小コードはSwift 6 strict concurrencyでtypecheck成功。
- 通常deinitから`@MainActor` methodを呼ぶ最小コードは`ActorIsolatedCall`で失敗し、`isolated deinit`ではSwift 5 / 6 modeとも成功。
- `com.jonghyunkim.nativetoolkit.custom-payload`は現ローカル環境で`UTType(_:) == nil`。
- `DDMatch*` 5型の設計フィールドはXcode 26.3 SDK headerと一致。
- Markdown code fenceは44個で対応し、U-01〜U-131の定義行は重複なし。
