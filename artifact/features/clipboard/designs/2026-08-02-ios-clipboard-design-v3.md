# iOS クリップボード機能 実装設計書 v3

- 作成日: 2026-08-02
- 改訂日: 2026-08-02（v3: 第 2 回レビュー指摘を反映）
- 前版: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v2.md`
- 対象OS: iOS 18 以降
- 対象機能: クリップボード（Clipboard / Pasteboard）
- 使用言語: Swift（Bridge の一部は Objective-C）
- 対象モジュール: `ios/IosLibrary`（Domain 〜 Manager）、`ios/UnityIosPlugin`（Unity Bridge のみ）

---

## 対象企画書

- `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`（第 4 回レビュー反映版）

企画書から引き継いだ前提:

| 項目 | 内容 |
|---|---|
| 目的 | `UIPasteboard` 系 API を native-toolkit へ組み込む |
| In scope | ペーストボード取得 / コピー / ペースト / 型判定 / クリア / 変更監視 / パターン検出 / 貼り付け UI / プライバシー / 名前付きペーストボード |
| Out of scope | ドラッグ&ドロップ、編集メニュー構築、Find ペーストボード、`NSItemProvider` 登録側 API、App Group shared container 入出力、iOS 26 の `ChangedMessage` / `RemovedMessage` |
| 主要リスク | iOS 14 アクセス通知 / iOS 16 許可プロンプト、Universal Clipboard 流出、名前付きペーストボードの非永続、`NSItemProvider` の完了スレッド・キャンセル契約・一時ファイル寿命、キーパス API が Swift 専用、**画像のサイズ上限とタイムアウト** |

### 企画書の不足前提（本設計で補った事項）

| # | 企画書に無い前提 | 本設計での補完 |
|---|---|---|
| L-1 | 同期・非同期 API 分類表（`common.md` 131-136 行が Research 段階に要求） | 「採用 System API の実行方式分類」を新設 |
| L-2 | 層をまたぐ実行方式の対応関係 | 「同期・非同期レイヤー対応表」を新設（P-1〜P-16 × 12 列） |
| L-3 | 画像デコード / エンコードのスレッド指定 | background executor を明示（S6） |
| L-4 | `NSItemProvider` の URL ロード契約 | `ClipboardLoadRequest.url` を定義（S6） |
| L-5 | 非同期 API のタイムアウト値と起算点 | `ClipboardTimeouts` を新設（企画書は「タイムアウトを設計する」とのみ記載） |
| L-6 | 画像・データのサイズ上限値 | `ClipboardLimits` を新設（企画書は「サイズ上限」とのみ記載） |
| L-7 | `append` した item への privacy option 継承可否 | 公式記述がないため保証せず、T-00 で実測（M-16） |

### 本設計での判断（新規設計判断）

| # | 未確定事項 | 本設計での判断 | 理由 |
|---|---|---|---|
| D-1 | `UIPasteControl` を公開 API とするか | ネイティブライブラリでは提供。Unity Bridge では提供しない | `UIView` は C ABI を越えられない |
| D-2 | パターン検出結果の公開範囲 | **全 11 パターンの値**をドメイン型へ変換して公開。`PartialKeyPath` / `DDMatch*` は露出しない | v2 は 6 種のみ値を返し、5 種が欠落していた |
| D-3 | `contains` / `changeCount` の採否 | `changeCount` は採用（T-00 で最終判断）、`contains(pasteboardTypes:)` は内部限定 | 代替のない前者のみ要検証つきで採用 |
| D-4 | 複数 provider の集約仕様 | 順序保持・部分失敗継続・コールバック回数・キャンセル時の非配信を確定（S11） | v2 はキャンセル契約が S6 と不整合だった |
| D-5 | HTML の扱い | 1 アイテム複数表現型で実装 | Android とのパリティ |
| D-6 | 名前付きペーストボードの型 | 参照用 `PasteboardScope` と作成用 `PasteboardCreationRequest` を分離 | - |
| D-7 | 一時ファイル cleanup | プロセス単位 1 回 + セッションディレクトリ + 24 時間経過 + 他セッション限定 | - |
| D-8 | append と privacy option | append を独立 API に分離し、**option の継承を保証しない**と明記 | `addItems(_:)` に option overload がなく、継承の公式記述もない |
| D-9 | 全層の actor 境界 | **Manager も `@MainActor`**。任意スレッド受付は Bridge facade のみ | v2 の「Manager nonisolated + `@MainActor` token 同期返却」は Swift 6 で実装不能 |
| D-10 | Task キャンセルの token 転送手段 | `ClipboardCancellationBox`（`Sendable` / `nonisolated cancel()`）を導入 | `withTaskCancellationHandler` の `onCancel` は `@Sendable` 同期クロージャで `@MainActor` に触れない |
| D-11 | `itemSet(withPasteboardTypes:)` の使い道 | `snapshot(matchingTypes:scope:)` の引数として採用し、`matchingItemIndexes` を返す | v2 は In scope としながら利用箇所がなかった |
| D-12 | UTI 検証の責務 | Application に `ClipboardTypeIdentifierValidating` Port を置き、Data 層で実装して注入 | UseCase で事前検証しつつ `UTType` を Application へ持ち込まないため |
| D-13 | 公開エラーメッセージの決定性 | case ごとの**固定英語文**とし、system の `localizedDescription` は公開しない | locale / OS 依存の文字列が Bridge JSON に出ると非決定的になる |

---

## 設計目的

- 企画書で網羅した `UIPasteboard` API を Clean Architecture の層構成に沿って `IosLibrary` へ実装する
- ネイティブ呼び出し元と Unity 呼び出し元の双方から同一の機能範囲を利用できるようにする（`UIPasteControl` を除く）
- System API の実行方式を各層で不必要に変換せず、変換箇所を Manager と Bridge に限定する（`common.md` 118-129 行）
- 非同期 API について完了 actor・exactly-once・キャンセル手段・タイムアウト・リソース所有権を全て明示する（`common.md` 125 行）

---

## スコープ（in / out）

### In scope

| サブ機能 | 内容 |
|---|---|
| S1 ペーストボード解決 | `general` / 名前付き / ユニーク名の参照・作成・破棄 |
| S2 コピー | plainText / htmlText / url / imageFile / imageData / color / customData / multipleText / multiRepresentation |
| S3 コピーオプション | `localOnly` / `expirationDate`（置換コピーのみ） |
| S4 追記（append） | 既存内容へアイテム追加（privacy option なし・継承保証なし） |
| S5 ペースト（同期） | text / urls / image / color / 任意 UTI `Data` / 全アイテムのメタ情報 |
| S6 ペースト（`NSItemProvider` 非同期） | text / url / image / file の非同期ロード、キャンセル、タイムアウト、エラー分類 |
| S7 内容確認 | `has*` / `numberOfItems` / `types` / `types(forItemSet:)` / `itemSet(withPasteboardTypes:)` |
| S8 クリア | `items = []`、名前付きの `remove(withName:)` |
| S9 変更監視 | `changedNotification` / `removedNotification` / `changeCount` 差分 |
| S10 パターン検出 | `detectedPatterns` / `detectedValues`（全 11 パターンの値を公開） |
| S11 貼り付け UI | `UIPasteControl` + 受信 View を保持するコンテナ（ネイティブのみ） |
| S12 Unity Bridge | S1〜S10 の JSON ベース公開（S11 を除く） |

### Out of scope

- 企画書の Out of scope 全項目
- App Group shared container のファイル入出力
- `contains(pasteboardTypes:)` の公開 API 化（内部限定。D-3）
- `loadTransferable` / `loadInPlaceFileRepresentation` / `loadItem`（非推奨）
- `docs/` 配下の変更

---

## 採用 System API の実行方式分類（L-1）

Repository / UseCase / private helper は **System API の実行方式をそのまま維持する**（`common.md` 120-127 行）。方式変換は Manager と Bridge でのみ行う。

| 分類 | System API | 完了方式 / 完了スレッド | 下位層で採る形 |
|---|---|---|---|
| sync | `UIPasteboard.general` / `init(name:create:)` / `withUniqueName()` / `remove(withName:)` | 即時 / 呼び出しスレッド | 同期関数 |
| sync | `setItems(_:options:)` / `addItems(_:)` / `items` | 即時 / 呼び出しスレッド | 同期関数 |
| sync | `string` / `urls` / `image` / `color` / `data(forPasteboardType:)` / `values(forPasteboardType:inItemSet:)` | 即時 | 同期関数 |
| sync | `has*` / `numberOfItems` / `types` / `types(forItemSet:)` / `itemSet(withPasteboardTypes:)` | 即時 | 同期関数 |
| sync | `changeCount` | 即時 | 同期関数 |
| async | `detectedPatterns(for:)` / `detectedValues(for:)` | `async throws` / 呼び出し元 actor へ復帰。**明示的な cancellation token を持たない**（Xcode 26.3 / iOS 26.2 SDK interface で確認） | `async throws` 関数 |
| callback | `NSItemProvider.loadObject` / `loadDataRepresentation` / `loadFileRepresentation` | completion + `Progress` / **完了スレッド不定**（公式に「The block may be executed on a background thread」） | completion + token |
| stream | `UIPasteboard.changedNotification` / `removedNotification` | `NotificationCenter` イベント / 登録 queue | 開始・停止は同期、配信は非同期 |
| UI callback | `UIPasteControl` → `paste(itemProviders:)` | UIKit responder / main | Presentation 内で完結 |
| 重い同期処理 | `UIImage.pngData()` / `UIImage(data:)` | 即時だが CPU 負荷大 | **background executor へ移し、呼び出し側には非同期として公開**（`common.md` 126 行の設計判断に該当。理由: 企画書リスク「デコード / エンコードはメインスレッド外で行う」） |

### 非同期 API のキャンセル可否（v2 の誤りを訂正）

v2 は P-9 / P-10 を「Task キャンセルで中断」と断定していたが、`detectedPatterns` / `detectedValues` に明示的な中断手段はない。v3 では次を契約とする。

- **OS 処理そのものの中断は保証しない**
- Task キャンセル時は **呼び出し側への配信を gate で抑止し、遅延到着した結果を破棄する**
- タイムアウト時も同様（gate で抑止 + 破棄）

---

## タイムアウトとサイズ上限（L-5 / L-6、`common.md` 125 行）

```swift
public struct ClipboardTimeouts: Equatable, Sendable {
    public static let `default` = ClipboardTimeouts(
        detection: 5.0,       // P-9 / P-10
        providerLoad: 15.0,   // P-11 / P-16（1 provider あたり）
        imageCoding: 10.0     // 画像エンコード / デコード
    )
    public let detection: TimeInterval
    public let providerLoad: TimeInterval
    public let imageCoding: TimeInterval
}

public struct ClipboardLimits: Equatable, Sendable {
    public static let `default` = ClipboardLimits(
        maxCopyByteCount: 64 * 1024 * 1024,      // copy / append の 1 アイテム合計
        maxLoadByteCount: 64 * 1024 * 1024,      // loadItem の受け入れ上限
        maxImagePixelCount: 100_000_000          // width * height
    )
    public let maxCopyByteCount: Int
    public let maxLoadByteCount: Int
    public let maxImagePixelCount: Int
}
```

- `IosClipboardManager.init(timeouts:limits:)` で差し替え可能（テストで短縮するため）
- **起算点**: `detection` は UseCase が System API を呼ぶ直前。`providerLoad` は `load...Representation` 呼び出し直前。`imageCoding` は background タスク投入直前
- **所有者**: いずれも呼び出した層（UseCase / Loader）がタイマーを保持し、完了・キャンセル時に破棄する
- **超過時**: `ClipboardError.timedOut(operation:)` を配信し、以後 System 側から届いた結果は gate で破棄。一時ディレクトリは削除する
- **サイズ超過**: `ClipboardError.contentTooLarge(byteCount:limit:)`。copy は書き込み前、load は `Data` 取得直後に判定
- **競合**: キャンセル / 完了 / タイムアウトの 3 者はリクエスト ID の単一 gate で解決し、**配信は必ず 1 回**

---

## 同期・非同期レイヤー対応表（L-2、`common.md` 136 行）

凡例: `S` = 同期、`A` = `async throws`、`C` = completion コールバック、`E` = イベント配信、`-` = 該当なし。

| # | 操作 | System API と実行方式 | Repository / Loader | UseCase | Manager callback | Manager native | Bridge | actor / thread | タイムアウト | キャンセル | リソース所有権 | 方式変換の理由 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| P-1 | `copy` | `setItems(_:options:)` = sync | S `throws` | S `throws` | C | A | `clipboardCopy` | Manager 以下すべて `@MainActor` | なし（即時） | 不可 | なし | Bridge が throw を扱えないため Manager で C 化 |
| P-2 | `append` | `addItems(_:)` = sync | S `throws` | S `throws` | C | A | `clipboardAppend` | 同上 | なし | 不可 | なし | 同上 |
| P-3 | `read` | `items` = sync | S `throws` | S `throws` | C | A | `clipboardRead` | 同上 | なし | 不可 | なし | 同上 |
| P-4 | `readData` | `data(forPasteboardType:)` = sync | S `throws` | S `throws` | C | A | `clipboardReadData` | 同上 | なし | 不可 | 返却 `Data` は呼び出し側 | Bridge は Base64 化 |
| P-5 | `snapshot` | `has*` / `types` / `itemSet` = sync | S | S | C | A | `clipboardGetSnapshot` | 同上 | なし | 不可 | なし | 同上 |
| P-6 | `clear` | `items = []` = sync | S `throws` | S `throws` | C | A | `clipboardClear` | 同上 | なし | 不可 | なし | 同上 |
| P-7 | `createPasteboard` | `init(name:create:)` / `withUniqueName()` = sync | S `throws` | S `throws` | C | A | `clipboardCreatePasteboard` | 同上 | なし | 不可 | 生成 pasteboard は呼び出し側（`remove` 責務） | 同上 |
| P-8 | `removePasteboard` | `remove(withName:)` = sync | S `throws` | S `throws` | C | A | `clipboardRemovePasteboard` | 同上 | なし | 不可 | なし | 同上 |
| P-9 | `detectPatterns` | `detectedPatterns(for:)` = async（中断手段なし） | A | A | C | A | `clipboardDetectPatterns` | `@MainActor`（await 中は解放） | `detection` = 5s | **配信抑止のみ**（OS 中断は保証しない） | なし | System が async のため下位層も async |
| P-10 | `detectValues` | `detectedValues(for:)` = async（中断手段なし） | A | A | C | A | `clipboardDetectValues` | 同上 | `detection` = 5s | 同上 | なし | 同上 |
| P-11 | `loadItem` | `loadObject` 等 = callback + `Progress`（完了スレッド不定） | C + token | C + token | C + token（同期で token 返却） | A（`ClipboardCancellationBox` 経由で token を cancel） | `clipboardLoadItem` | Loader は `@MainActor`。画像コーディングのみ background | `providerLoad` = 15s、`imageCoding` = 10s | token / `cancelAllLoads()` / `deinit` / Task キャンセル。`Progress.cancel()` は補助（completion 抑止は保証されない） | `.file` 成功時のみ URL と親ディレクトリが呼び出し側所有 | System が callback のため維持。native 版のみ薄く async 化 |
| P-12 | `cancelAllLoads` | - | S | - | S | S | `clipboardCancelLoads` | `@MainActor` | - | - | 未配信の一時ディレクトリは Loader が削除 | 同期完結のため callback / async を設けない（`common.md` 129 行の「してよい」に基づく任意適用） |
| P-13 | `startObserving` | `addObserver` = sync、通知 = stream | S（Manager 直接所有） | - | S（登録） + E（配信） | S | `clipboardStartObserving`（開始結果は専用 operation callback） | 登録・配信とも `@MainActor` | - | `stopObserving` | なし | 開始は同期、配信のみ非同期 |
| P-14 | `stopObserving` | `removeObserver` = sync | S | - | S | S | `clipboardStopObserving` | `@MainActor` | - | - | なし | 同上 |
| P-15 | `checkForegroundChange` | `changeCount` = sync | S | S | S（`Bool` 返却） | S | `clipboardCheckForegroundChange` | `@MainActor` | - | 不可 | なし | 同期完結のため callback 化しない |
| P-16 | `makePasteControl` | `UIPasteControl` 生成 = sync、貼り付け = UI callback | Presentation `PasteItemProviderLoader`（C + token） | - | S（生成） + C（貼り付け結果） | S | **非公開** | `@MainActor` | `providerLoad` / `imageCoding` | コンテナ `deinit` / 次回 paste 開始時。**キャンセル時は UI callback を呼ばない**（D-4） | `.file` 成功時のみ呼び出し側所有。未配信分は Presentation が削除 | UIKit 型のため Bridge 非公開 |

### 方式維持の原則（実装規約）

1. 同期 System API を下位層で `async` にしない
2. callback System API を下位層で `async` にしない（`async` 化は Manager native 版のみ）
3. async System API を下位層で callback にしない
4. イベント配信は Manager が唯一の発生源
5. actor hop は Manager と Bridge、および画像コーディングの background executor に限定する
6. **P-12〜P-16 は同期完結の control API のため callback / async 版を設けない**（`common.md` 129 行は併設を「してよい」とする任意規定。Data 層アクセスを伴わないため UseCase も持たない）

---

## 共通実装方針の適用チェック（common.md 準拠）

| 方針 | 判定 | 対応 |
|---|---|---|
| Clean Architecture の層と依存方向 | 適合 | Domain → Application → Data / Presentation → Manager → Unity Bridge |
| 層とモジュールの対応（Manager までネイティブライブラリ） | 適合 | Domain 〜 Manager を `ios/IosLibrary`、`ios/UnityIosPlugin` は Unity Bridge のみ |
| Port はドメイン型のみ | 適合 | Application 層 Port の引数・戻り値は全てドメイン型。`NSItemProvider` は Data / Presentation に閉じ込め |
| Manager は UseCase 経由で Data にアクセス | 適合 | **Data 層アクセスを伴う P-1〜P-11 に 11 個の UseCase を用意**。P-12〜P-16 は Data 層に触れないため UseCase を持たない（理由を明記） |
| system Delegate / Listener の所有は Manager 層の 1 クラス | 適合 | `NotificationCenter` トークンは `IosClipboardManager` のみ |
| Manager は callback 版 + `async throws` 版を併設 | 適合（一部任意規定を適用） | P-1〜P-11 は併設。P-12〜P-16 は同期 control API のため単一形式（`common.md` 129 行） |
| システム API に合わせた同期・非同期設計（118-129 行） | 適合 | 「方式維持の原則」6 項目として明文化 |
| 非同期 API の完了 actor / exactly-once / キャンセル / タイムアウト / 所有権（125 行） | 適合 | レイヤー対応表の 8〜12 列で全て明示 |
| Research / Design の追跡表（131-136 行） | 適合 | Design 段階の必須列を全て含む |
| エラー変換の流れ | 適合 | システムエラー → Repository で `ClipboardError` へ正規化 → Manager で `(Bool, errorCode, errorMessage)` → Bridge |
| TDD / Mock パターン | 適合 | `shouldFail` / per-method CallCount / `stubbedXxx` |
| Swift Testing（XCTest 不使用） | 適合 | 既存 `IosLibraryTests` と同形式 |
| Unity Bridge は薄く保つ | 適合 | JSON 変換と Manager 呼び出しのみ。エラーは `errorCode` を透過 |
| サンプルアプリはネイティブライブラリのみに依存 | 適合 | `IosLibraryExample` は `IosLibrary` のみ import |
| 最小 OS バージョン iOS 18 | 適合 | 使用 API は全て iOS 16 以前の導入 |
| **Domain は標準ライブラリのみ** | **未合意（要判断）** | 下記参照 |

### Domain の `Foundation` 依存（未合意事項・v2 の「合意済み」表記を訂正）

本設計の Domain 層は `Foundation` の `Data` / `Date` / `URL` / `TimeInterval` を使用する。`common.md` 23 行は「純粋モデル・エラー型（プラットフォーム依存なし、標準ライブラリのみ）」としており、**現時点では未合意の逸脱**である。v2 は適用チェック表で「適合」「合意済み」と記載していたが誤りのため訂正する。

選択肢と本設計の推奨:

| 案 | 内容 | 影響 |
|---|---|---|
| **A（推奨）** | `common.md` 23 行に「`Foundation` の値型（`Data` / `Date` / `URL` / `UUID` 等）は標準ライブラリに準ずるものとして許容する。ただし UI フレームワーク型（`UIKit` / `AppKit` 等）は不可」を追記する | 既存 `ShareContent` / `ShareError` も同様に `import Foundation` しており、追記により現状追認できる |
| B | Domain を `[UInt8]` / epoch 秒 / パス文字列へ変換する | Data 層との変換コードが増え、既存 Share と不整合になる |

**この判断が下りるまで実装（T-01）を開始しない。** 案 A を採る場合は `common.md` の改訂を先行タスク T-R として実施する。いずれの場合も `UIKit` 型（`UIImage` / `UIColor` / `UIPasteboard` / `NSItemProvider` / `UTType`）を Domain に持ち込まない境界は厳守する。

### underlying error の正規化（D-13）

```swift
/// Diagnostic detail for a normalized system failure.
/// `debugMessage` は診断専用で、公開メッセージにも Bridge JSON にも載せない。
public struct ClipboardFailureDetail: Equatable, Sendable {
    public let domain: String     // 例: NSItemProvider.errorDomain
    public let code: Int          // 例: itemUnavailableError.rawValue
    internal let debugMessage: String
}
```

- **公開メッセージは error case ごとの固定英語文**（locale / OS / provider に依存しない）
- Bridge JSON の `message` も固定文。`domain` / `code` は `details` オブジェクトとして任意で載せる
- `debugMessage` は `internal`。ログにも出さない（`ClipboardLog` は `domain` + `code` のみ出力）

---

## 個別実装方針の適用チェック（ios.md 準拠）

| 方針 | 判定 | 対応 |
|---|---|---|
| 全メソッド先頭に全パラメータの `Log.d` / `Log.e` | 適合 | `private let TAG = "<FullClassName>"` |
| クリップボード値のログ秘匿 | 追加ルール | `ClipboardLog`（library 内）+ `ClipboardRedaction`（`@objc public` facade）経由 |
| ObjC ブロック引数型（`BOOL` / `NSInteger` / `NSString * _Nullable`） | 適合 | Bridge `.m` の完了ブロックは `BOOL` |
| Manager は callback 版 + `async throws` 版 | 適合（P-12〜P-16 は任意規定を適用） | 上表参照 |
| private helper を一律 `async` にしない | 適合 | 「方式維持の原則」 |
| UI 更新は main へ戻す | 適合 | Manager 自体が `@MainActor` |
| DocC コメント（public 必須、英語） | 適合 | 全 public 型・関数 |
| ユーザー向け文言は英語 | 適合 | 固定英語メッセージ |

### 追加ルール: ログ秘匿（モジュール境界を修正）

v2 は `internal enum ClipboardLog` を別モジュール（`UnityIosPlugin`）と Objective-C から呼ぶ設計で、可視性・ObjC 相互運用のいずれからも成立しなかった。v3 では 2 層に分ける。

| 型 | モジュール | 可視性 | 用途 |
|---|---|---|---|
| `ClipboardRedactionCore` | `IosLibrary` | `internal` | 実装本体（Swift） |
| `ClipboardRedaction` | `IosLibrary` | `@objc public final class : NSObject` | Swift / ObjC 双方から呼べる facade。`UnityIosPlugin` の Swift と `.m` の両方がこれを使う |
| `ClipboardLog` | `IosLibrary` | `internal enum` | library 内部からの薄いラッパー |

```swift
@objc public final class ClipboardRedaction: NSObject {
    @objc public static func text(_ value: String) -> String   // "<text:12>"
    @objc public static func data(byteCount: Int) -> String    // "<data:2048>"
    @objc public static func json(_ value: String) -> String   // "<json:340>"
    @objc public static func path(_ value: String) -> String    // "<path:ext=png,len=48>"
}
```

`.m` からは `#import <IosLibrary/IosLibrary-Swift.h>` 済みのため `[ClipboardRedaction json:nsJson]` として呼べる。**モジュール境界の成立を U-104 とビルドテスト I-09 で検証する。**

**秘匿対象**: コピー / ペーストの値本体、Bridge の request JSON 全文、Base64 文字列、ファイルパス・ファイル名、URL 文字列、system error の message。
**非秘匿**: 種別、長さ、件数、UTI、`PasteboardScope` の種別、`localOnly`、`errorCode`、failure detail の `domain` / `code`。
**既存 Share Bridge との差**: `UnityIosShareManager` は `contentJson` を全文ログ出力しているが、Clipboard では踏襲しない。

---

## 既存実装差分サマリー

### 破壊的変更

**なし。** 既存 Notification / Dialog / Share のファイルは変更しない。追加のみ。ただし `common.md` の改訂（案 A 採用時）は別途発生する。

### Xcode プロジェクト設定

3 つの `.xcodeproj` は `PBXFileSystemSynchronizedRootGroup` を採用しているため `project.pbxproj` の編集は不要。Swift 6 strict concurrency はターゲット設定を変えずフラグ上書きで検証する。

```
xcodebuild build -project ios/IosLibrary/IosLibrary.xcodeproj -scheme IosLibrary \
  SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete
xcodebuild build -project ios/UnityIosPlugin/UnityIosPlugin.xcodeproj -scheme UnityIosPlugin \
  SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete
```

### 追加ファイル一覧

`ios/IosLibrary/IosLibrary/Clipboard/` 配下:

| パス | 層 | 役割 |
|---|---|---|
| `Common/ClipboardRedactionCore.swift` | Common | 秘匿実装 |
| `Common/ClipboardRedaction.swift` | Common | `@objc public` facade |
| `Common/ClipboardLog.swift` | Common | library 内部ラッパー |
| `Domain/Model/PasteboardScope.swift` | Domain | 参照用スコープ |
| `Domain/Model/PasteboardCreationRequest.swift` | Domain | 作成要求 |
| `Domain/Model/ClipboardContent.swift` | Domain | コピー内容（9 kind） |
| `Domain/Model/ClipboardCopyOptions.swift` | Domain | `localOnly` / `expirationDate` |
| `Domain/Model/ClipboardLimits.swift` | Domain | サイズ上限（L-6） |
| `Domain/Model/ClipboardTimeouts.swift` | Domain | タイムアウト（L-5） |
| `Domain/Model/ClipboardItemData.swift` | Domain | 1 アイテムの表現 |
| `Domain/Model/ClipboardReadResult.swift` | Domain | 読み取り結果 |
| `Domain/Model/ClipboardSnapshot.swift` | Domain | 内容確認（`matchingItemIndexes` 含む） |
| `Domain/Model/ClipboardChangeEvent.swift` | Domain | 変更 / 破棄イベント |
| `Domain/Model/ClipboardDetectionPattern.swift` | Domain | 検出パターン 11 種 |
| `Domain/Model/ClipboardDetectedValues.swift` | Domain | 検出結果（全 11 項目の値） |
| `Domain/Model/ClipboardDetectedEntities.swift` | Domain | `ClipboardPostalAddress` / `ClipboardCalendarEvent` / `ClipboardFlightNumber` / `ClipboardMoneyAmount` / `ClipboardShipmentTracking` |
| `Domain/Model/ClipboardLoadRequest.swift` | Domain | ロード要求（text/url/image/file） |
| `Domain/Model/ClipboardLoadedItem.swift` | Domain | ロード結果 |
| `Domain/Model/ClipboardFailureDetail.swift` | Domain | 正規化済み system error |
| `Domain/Model/ClipboardError.swift` | Domain | ドメインエラー 24 ケース + `errorCode` |
| `Application/Port/ClipboardRepository.swift` | Application | 同期 + async 操作 Port |
| `Application/Port/ClipboardItemLoader.swift` | Application | callback + token Port |
| `Application/Port/ClipboardTypeIdentifierValidating.swift` | Application | UTI 検証 Port（D-12） |
| `Application/Port/ClipboardClock.swift` | Application | `now` 注入（テスト安定化） |
| `Application/UseCase/CopyContentUseCase.swift` | Application | P-1 |
| `Application/UseCase/AppendContentUseCase.swift` | Application | P-2 |
| `Application/UseCase/ReadContentUseCase.swift` | Application | P-3 |
| `Application/UseCase/ReadDataUseCase.swift` | Application | P-4 |
| `Application/UseCase/GetSnapshotUseCase.swift` | Application | P-5 |
| `Application/UseCase/ClearClipboardUseCase.swift` | Application | P-6 |
| `Application/UseCase/CreatePasteboardUseCase.swift` | Application | P-7 |
| `Application/UseCase/RemovePasteboardUseCase.swift` | Application | P-8 |
| `Application/UseCase/DetectPatternsUseCase.swift` | Application | P-9 |
| `Application/UseCase/DetectValuesUseCase.swift` | Application | P-10（v2 で欠落） |
| `Application/UseCase/LoadItemUseCase.swift` | Application | P-11 |
| `Application/UseCase/ClipboardChangeTracker.swift` | Application | 差分同期規則（純ロジック） |
| `Application/UseCase/ClipboardContentValidator.swift` | Application | 純粋検証（純ロジック） |
| `Application/UseCase/ClipboardUseCases.swift` | Application | 集約 |
| `Data/Repository/ClipboardRepositoryImpl.swift` | Data | `UIPasteboard` 実装 |
| `Data/Repository/ClipboardItemLoaderImpl.swift` | Data | `NSItemProvider` 実装 |
| `Data/Repository/ClipboardMappers.swift` | Data | 型変換 |
| `Data/Repository/ClipboardDetectionMapper.swift` | Data | `DDMatch*` → ドメイン型 |
| `Data/Repository/PasteboardResolver.swift` | Data | スコープ解決 |
| `Data/Repository/ClipboardTypeIdentifierValidator.swift` | Data | `ClipboardTypeIdentifierValidating` 実装（`UTType`） |
| `Data/File/ClipboardTemporaryFileStore.swift` | Data | 一時ディレクトリ管理・cleanup |
| `Data/Image/ClipboardImageCoder.swift` | Data | background での画像 encode / decode + サイズ検証 |
| `Data/Concurrency/ClipboardCancellationBox.swift` | Data | Task キャンセル転送（D-10） |
| `Presentation/PasteItemProviderLoader.swift` | Presentation | `[NSItemProvider]` の集約ロード |
| `Presentation/ClipboardPasteReceiverView.swift` | Presentation | `UIPasteConfigurationSupporting` 実装 |
| `Presentation/ClipboardPasteControlContainerView.swift` | Presentation | control + receiver を保持する公開コンテナ |
| `Presentation/PasteControlFactory.swift` | Presentation | 生成ヘルパー |
| `IosClipboardManager.swift` | Manager | 公開 API・監視トークン所有（`@MainActor`） |

`ios/UnityIosPlugin/UnityIosPlugin/Clipboard/` 配下:

| パス | 役割 |
|---|---|
| `UnityIosClipboardManager.swift` | Swift facade（nonisolated singleton。任意スレッド受付 → main hop） |
| `UnityIosClipboardJsonParser.swift` | JSON パース / シリアライズ |
| `UnityIosClipboardManagerBridge.h` | C ABI 宣言 |
| `UnityIosClipboardManagerBridge.m` | C 関数実装 |

### 既存規約との整合

| 観点 | 既存 | 本設計 |
|---|---|---|
| ディレクトリ構成 | `Share/{Domain,Application,Data,Presentation}` + `IosShareManager.swift` | 同一構成を `Clipboard/` で踏襲 |
| Manager 命名 | `IosShareManager` | `IosClipboardManager` |
| Bridge 命名 | `UnityIosShareManager` + Bridge `.h` / `.m` + JsonParser | 同構成 |
| singleton | `public static let shared` + `private init()` + test 用 init | 同一（ただし `@MainActor`） |
| エラーコード | Android の `CLIPBOARD_*` | 共通 4 コードは完全一致、iOS 固有 20 コードを追加 |

---

## 実装アーキテクチャ

```
[Unity C#]
    │ P/Invoke (C ABI) — 任意スレッド
[UnityIosClipboardManagerBridge.h/.m]              ← ios/UnityIosPlugin
    │  各 C 関数は JSON を渡すだけ（ログは ClipboardRedaction 経由）
[UnityIosClipboardManager]  nonisolated singleton  ← Unity Bridge 層
    │  + UnityIosClipboardJsonParser
    │  Task { @MainActor } で hop し、Manager の async throws を呼ぶ
    │  catch した ClipboardError.errorCode / message を JSON へ変換（唯一の変換点）
    ▼
[IosClipboardManager]  @MainActor                  ← Manager 層 / ios/IosLibrary
    │  - NotificationCenter トークンを単独所有
    │  - P-1〜P-11: callback 版 + async throws 版
    │  - P-12〜P-16: 同期 control API
    ▼
[ClipboardUseCases]  @MainActor                    ← Application 層
    │  Copy / Append / Read / ReadData / GetSnapshot / Clear /
    │  CreatePasteboard / RemovePasteboard / DetectPatterns / DetectValues / LoadItem（11 個）
    │  + ChangeTracker / ContentValidator（nonisolated 純ロジック）
    ▼
[ClipboardRepository] [ClipboardItemLoader] [ClipboardTypeIdentifierValidating] [ClipboardClock]
    ▲            ▲                    ▲                                ▲       ← Port（ドメイン型のみ）
[ClipboardRepositoryImpl] [ClipboardItemLoaderImpl] [ClipboardTypeIdentifierValidator] [SystemClock]
    │  + Mappers / DetectionMapper / PasteboardResolver
    │  + TemporaryFileStore / ImageCoder（background）/ CancellationBox
    ▼
[UIPasteboard] [NSItemProvider] [FileManager] [DataDetection]

[ClipboardPasteControlContainerView]（公開）
   └ holds → [UIPasteControl] + [ClipboardPasteReceiverView] → [PasteItemProviderLoader]
   ← Presentation 層（@MainActor / UIKit）。NSItemProvider はここに閉じ込める
```

### actor 境界（D-9 / v2 の実装不能箇所を修正）

v2 は Manager を nonisolated としながら `@MainActor` の token を同期返却し、`@MainActor` の Loader / UIKit 状態を同期操作していたため、Swift 6 で成立しなかった。v3 では境界を 1 段上げる。

| 宣言 | isolation | 理由 |
|---|---|---|
| Domain 型 | `Sendable`（値型） | 純粋モデル |
| `ClipboardChangeTracker` / `ClipboardContentValidator` | `nonisolated struct` | 純ロジック。任意スレッドでテスト可能 |
| `ClipboardClock` / `SystemClock` | `nonisolated` | `now` の注入 |
| `ClipboardTypeIdentifierValidating` / 実装 | `nonisolated` | `UTType` はスレッドセーフ |
| `ClipboardRepository` / `Impl` | `@MainActor` | `UIPasteboard` を触る |
| `ClipboardItemLoader` / `Impl` / `ClipboardLoadToken` | `@MainActor` | 管理表を持ち main で配信 |
| UseCase 群 | `@MainActor` | `@MainActor` Port を呼ぶ |
| `ClipboardImageCoder` | `nonisolated` + 内部 `Task.detached` | 画像コーディングを main から外す |
| `ClipboardCancellationBox` | `final class`, `@unchecked Sendable`（内部ロック） | `nonisolated cancel()` を提供 |
| Presentation 全体 | `@MainActor` | UIKit |
| **`IosClipboardManager`** | **`@MainActor final class`** | 同期 control API と token 同期返却を成立させる |
| `UnityIosClipboardManager` | **nonisolated final class** | Unity から任意スレッドで呼ばれる唯一の入口。内部で `Task { @MainActor in }` |

**呼び出し規約の変更点**: `IosClipboardManager` が `@MainActor` になったため、ネイティブ呼び出し元（SwiftUI / UIKit）は main actor から直接呼べる。非 main から呼ぶ場合は `await MainActor.run { }` が必要になる旨を DocC に明記する。

### Task キャンセルの token 転送（D-10）

`withTaskCancellationHandler` の `onCancel` は `@Sendable` な**同期**クロージャで、`@MainActor` の token には直接触れられない。中継役を導入する。

```swift
/// Thread-safe relay that forwards a Task cancellation to a main-actor load token.
public final class ClipboardCancellationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var token: (any ClipboardLoadToken)?
    private var isCancelled = false

    /// Callable from any thread, including a `@Sendable` cancellation handler.
    public nonisolated func cancel() {
        lock.lock()
        isCancelled = true
        let captured = token
        token = nil
        lock.unlock()
        guard let captured else { return }
        Task { @MainActor in captured.cancel() }
    }

    /// Attaches the token once the load has started. Cancels immediately if already cancelled.
    @MainActor func attach(_ newToken: any ClipboardLoadToken) {
        lock.lock()
        let alreadyCancelled = isCancelled
        if !alreadyCancelled { token = newToken }
        lock.unlock()
        if alreadyCancelled { newToken.cancel() }
    }
}
```

Manager native 版の P-11:

```swift
public func loadItem(_ request: ClipboardLoadRequest, scope: PasteboardScope = .general)
    async throws -> ClipboardLoadedItem
{
    let box = ClipboardCancellationBox()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            let token = loadItemUseCase.execute(request, scope: scope) { result in
                continuation.resume(with: result)   // Loader の gate により必ず 1 回
            }
            box.attach(token)
        }
    } onCancel: {
        box.cancel()                                 // nonisolated。main へ hop して token を cancel
    }
}
```

`attach` 前にキャンセルされた場合も `isCancelled` フラグで拾えるため、取りこぼしがない。continuation の resume が 1 回であることは Loader 側の単一 gate（キャンセル / 完了 / タイムアウトの 3 者解決）が保証する。

---

## サブ機能別詳細設計

### S1 ペーストボード解決

```swift
public enum PasteboardScope: Equatable, Sendable {
    case general
    case named(String)
    case unique(String)
}

public enum PasteboardCreationRequest: Equatable, Sendable {
    case named(String)
    case unique
}
```

| 境界ケース | 挙動 |
|---|---|
| `createPasteboard(.named(n))` で n が既存 | 既存を返す（エラーにしない） |
| `createPasteboard(.named(""))` / 空白のみ | `invalidPasteboardName` |
| `createPasteboard(.unique)` | `.unique(生成名)` を返す |
| `removePasteboard(.general)` | `cannotRemoveGeneralPasteboard` |
| `removePasteboard(.named(n))` で n が未作成 | 成功（冪等） |
| 破棄済みスコープへの読み書き | `pasteboardUnavailable(name:)` |

全 API が `scope: PasteboardScope = .general` のデフォルト引数を持つ。

---

### S2 コピー / S3 コピーオプション / S4 追記

```swift
public enum ClipboardContent: Equatable, Sendable {
    case plainText(String)
    case htmlText(plain: String, html: String)
    case url(String)
    case imageFile(path: String)
    case imageData(Data, utType: String)
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    case customData(Data, utType: String)
    case multipleText([String])
    case multiRepresentation([String: Data])
}

/// Privacy options. `copy` only — `append` cannot carry them.
public struct ClipboardCopyOptions: Equatable, Sendable {
    public static let `default` = ClipboardCopyOptions(localOnly: true, expirationDate: nil)
    public let localOnly: Bool          // 既定 true
    public let expirationDate: Date?
}
```

#### append の privacy 契約（D-8 / v2 の断定を撤回）

v2 は「追記時のプライバシー設定は直前の copy のものが残る」と書いたが、`addItems(_:)` に option overload はなく、既存 item の option が新規 item へ継承されるという公式記述も存在しない。v3 では:

- **`append` は `localOnly` / `expirationDate` を保証しない**。DocC・Bridge ヘッダ・エラー表の 3 箇所に明記する
- **機微データの `append` は非推奨**とし、DocC に「機微データは `copy(_:options:)` を使うこと」と記載する
- 継承の実挙動は **T-00 の実機スパイク（M-16）で確認**する
- 継承されないと判明した場合の代替 API（既存 items を読み直して `setItems(_:options:)` で置換する `appendPreservingOptions`）は、**読み直しが許可プロンプトの契機になりうる**ため、T-00 の結果を見て採否を決める（要判断・R-13）

#### 入力検証（責務分離）

**(a) 純粋検証** — `ClipboardContentValidator`（`nonisolated struct`、`ClipboardClock` 注入）

| ケース | 判定 | エラー |
|---|---|---|
| `plainText("")` | 許可 | - |
| `htmlText` の `html` が空白のみ | 拒否 | `emptyContent` |
| `htmlText` の `plain` が空白のみ | 許可 | - |
| `url` が空 / スキーム無し / http(s) で host 無し | 拒否 | `invalidURL` |
| `imageData` / `customData` の `Data` が空 | 拒否 | `emptyContent` |
| `color` が非有限値、または 0.0...1.0 の範囲外 | 拒否 | `invalidColor` |
| `multipleText` が空配列 | 拒否 | `emptyItemList` |
| `multiRepresentation` が空辞書 | 拒否 | `emptyItemList` |
| `multiRepresentation` に空 `Data` の値 | 拒否 | `emptyContent` |
| `multiRepresentation` のキーが空文字 | 拒否 | `invalidTypeIdentifier` |
| `expirationDate <= clock.now()` | 拒否 | `invalidExpirationDate` |
| `imageFile("")` | 拒否 | `invalidRequest` |
| `Data` 合計が `limits.maxCopyByteCount` 超 | 拒否 | `contentTooLarge` |

`ClipboardClock` を注入することで `expirationDate` の境界テストが決定的になる（v2 は `Date()` 直参照で不安定だった）。

**(b) 型検証** — `ClipboardTypeIdentifierValidating`（Port。実装は Data 層、UseCase に注入）

| ケース | エラー |
|---|---|
| UTI が `UTType(_:)` で解決できない | `invalidTypeIdentifier` |
| `imageData` の UTI が `UTType.image` に conform しない | `invalidTypeIdentifier` |

UseCase が Port 経由で事前検証するため、`UTType` は Application に現れない（D-12）。v2 の「Data 層で検証」記述と U-26 の矛盾を解消。

**(c) データ依存検証** — Data 層

| ケース | 実施箇所 | エラー |
|---|---|---|
| `imageData` がデコードできない / ピクセル数超過 | `ClipboardImageCoder` | `invalidImageData` / `contentTooLarge` |
| `imageFile` のパスが存在しない | `ClipboardRepositoryImpl` | `fileNotFound` |
| `imageFile` が読めない | `ClipboardRepositoryImpl` | `imageLoadFailed` |
| 名前付きスコープが解決できない | `PasteboardResolver` | `pasteboardUnavailable` |

**書き込み方式**: `setValue(_:forPasteboardType:)` は使用しない。`setItems` / `addItems` に統一。

---

### S5 ペースト（同期）

```swift
public struct ClipboardItemData: Equatable, Sendable {
    public let typeIdentifiers: [String]
    public let text: String?
    public let urlString: String?
    public let imageDataUTType: String?
}

public struct ClipboardReadResult: Equatable, Sendable {
    public let items: [ClipboardItemData]
    public let numberOfItems: Int
}
```

**P-4 `readData` の縦断**

| 層 | シグネチャ |
|---|---|
| Port（validating） | `func validate(_ utType: String) throws` |
| Port（repository） | `func readData(utType: String, scope: PasteboardScope) throws -> Data?` |
| UseCase | `ReadDataUseCase.execute(utType:scope:) throws -> Data?`（先に validating Port で検証） |
| Data | `pasteboard.data(forPasteboardType:)` |
| Manager callback | `readData(utType:scope:completion: (Data?, String?, String?) -> Void)` |
| Manager native | `readData(utType:scope:) async throws -> Data?` |
| Bridge | `clipboardReadData` |
| テスト | U-30（UseCase 正常）、U-31（UTI 不正で Repository 未呼び出し）、U-32（該当なし → nil）、U-52（Data 実機）、U-86（Manager）、U-110（Bridge schema） |

**プライバシー**: `read` / `readData` は本体を読むため許可プロンプト / アクセス通知の対象になりうる。事前判定には `snapshot`（P-5）を使うよう DocC で誘導する。

---

### S6 ペースト（`NSItemProvider` 非同期）

```swift
public enum ClipboardLoadRequest: Equatable, Sendable {
    case text
    case url
    case image
    case file(utType: String)
}

public enum ClipboardLoadedItem: Sendable, Equatable {
    case text(String)
    case url(String)
    case imageData(Data, utType: String)   // PNG。background でエンコード
    case file(URL)
}
```

**Port**

```swift
@MainActor
public protocol ClipboardItemLoader: AnyObject {
    /// Loads the first matching item. `completion` is invoked exactly once on the main actor,
    /// including the cancelled and timed-out paths.
    @discardableResult
    func load(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> any ClipboardLoadToken

    func cancelAll()
}

@MainActor
public protocol ClipboardLoadToken: AnyObject {
    func cancel()
}
```

**制御フロー（`ClipboardItemLoaderImpl`、`@MainActor`）**

1. リクエスト ID を採番し、**発行時点で管理表へ登録**
2. `timeouts.providerLoad` のタイマーを開始（起算点 = System API 呼び出し直前）
3. provider を検索。無ければ main へ hop して `noMatchingItem` を配信（同期実行しない）
4. `loadObject` / `loadDataRepresentation` / `loadFileRepresentation` を呼び `Progress` を格納
5. completion（任意スレッド）で結果を組み立てる
   - `Data` が `limits.maxLoadByteCount` 超 → `contentTooLarge`
   - `.image` は `ClipboardImageCoder` の background executor でピクセル数検証 + PNG エンコード（`timeouts.imageCoding` 付き）
   - `.file` は `ClipboardTemporaryFileStore` へコピー
6. main へ hop し、**単一 gate**（`finish(id:)`）で解決
   - 管理表から ID を除去できた場合のみ配信
   - できない（キャンセル済み / タイムアウト済み）場合は破棄し、一時ディレクトリを削除
7. `cancelAll()` / `deinit` / token `cancel()` / タイムアウトは、それぞれ `.cancelled` / `.timedOut(operation:)` を **1 回**配信してから管理表から除去する

**キャンセル / 完了 / タイムアウトの 3 者競合**: すべて `finish(id:)` を通るため、最初に到達した 1 つだけが配信される。残りは破棄され、一時領域も解放される。

**一時ファイル（`ClipboardTemporaryFileStore`、D-7）**

```
<NSTemporaryDirectory()>/IosLibraryClipboard/<sessionUUID>/<requestUUID>/<UUID>.<検証済み拡張子>
```

- 保存名は `suggestedName` をそのまま使わない。UUID + 許可拡張子（`png` / `jpg` / `jpeg` / `heic` / `heif` / `gif` / `tiff` / `webp` / `txt` / `pdf`、非該当は `bin`）
- 標準化パスが専用ディレクトリ配下であることを検証してからコピー
- 失敗・キャンセル・タイムアウト・loader 解放時は requestUUID ディレクトリ単位で削除
- 起動時 cleanup はプロセス単位 1 回、自セッション以外かつ 24 時間より古いものだけを削除

---

### S7 内容確認（D-11）

```swift
public struct ClipboardSnapshot: Equatable, Sendable {
    public let hasStrings: Bool
    public let hasURLs: Bool
    public let hasImages: Bool
    public let hasColors: Bool
    public let numberOfItems: Int
    public let typeIdentifiers: [String]           // 先頭アイテム
    public let allTypeIdentifiers: [[String]]      // types(forItemSet: nil)
    public let matchingItemIndexes: [Int]?         // matchingTypes 指定時のみ非 nil
}
```

`snapshot(matchingTypes: [String]? = nil, scope: PasteboardScope = .general)`。`matchingTypes` が非 nil のとき `itemSet(withPasteboardTypes:)` を呼び、結果の `IndexSet` を `[Int]`（昇順）へ変換して返す。これにより v2 で採用宣言のみだった `itemSet` に実利用箇所ができる。

使用する System API は公式が「通知・アラートを避ける」として列挙するもののみ。`contains(pasteboardTypes:)` は内部限定（D-3）。

---

### S8 クリア

`ClearClipboardUseCase` → `repository.clear(scope:)` → `pasteboard.items = []`。名前付きの破棄は P-8。エラーは `pasteboardUnavailable`。

---

### S9 変更監視

**Delegate 所有**: `IosClipboardManager` が `changedNotification` / `removedNotification` の 2 トークンを単独保持。

```swift
public struct ClipboardChangeEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case changed(typesAdded: [String], typesRemoved: [String])
        case changedDetectedOnForeground
        case removed
    }
    public let kind: Kind
    public let scope: PasteboardScope
}
```

**`ClipboardChangeTracker`**（`nonisolated struct`）: `resync(to:)` / `markReported(current:)` / `hasChanged(current:) -> Bool`。

同期規則:

1. `startObserving` で `resync`
2. `changedNotification` 受信時に `markReported`
3. `checkForegroundChange()` は比較後に必ず基準値を更新
4. `stopObserving` 後に到着した通知は配信しない（トークン解除 + 世代 ID）

`startObserving` は既に監視中なら先に `stopObserving()`。`deinit` でも `stopObserving()`。

---

### S10 パターン検出（D-2 / 値モデルの欠落を修正）

```swift
public enum ClipboardDetectionPattern: String, CaseIterable, Sendable {
    case probableWebURL, probableWebSearch, number, link, emailAddress,
         phoneNumber, postalAddress, calendarEvent, flightNumber,
         moneyAmount, shipmentTrackingNumber
}

public struct ClipboardDetectedValues: Equatable, Sendable {
    public let detectedPatterns: Set<ClipboardDetectionPattern>
    public let probableWebURL: String?
    public let probableWebSearch: String?
    public let number: Double?
    public let links: [String]                                   // DDMatchLink.url.absoluteString
    public let emailAddresses: [ClipboardLabeledValue]           // DDMatchEmailAddress
    public let phoneNumbers: [ClipboardLabeledValue]             // DDMatchPhoneNumber
    public let postalAddresses: [ClipboardPostalAddress]
    public let calendarEvents: [ClipboardCalendarEvent]
    public let flightNumbers: [ClipboardFlightNumber]
    public let moneyAmounts: [ClipboardMoneyAmount]
    public let shipmentTrackingNumbers: [ClipboardShipmentTracking]
}

public struct ClipboardLabeledValue: Equatable, Sendable {
    public let value: String; public let label: String?
}
public struct ClipboardPostalAddress: Equatable, Sendable {
    public let street: String?; public let city: String?; public let state: String?
    public let postalCode: String?; public let country: String?
}
public struct ClipboardCalendarEvent: Equatable, Sendable {
    public let startDate: Date?; public let endDate: Date?
    public let startTimeZoneIdentifier: String?; public let endTimeZoneIdentifier: String?
    public let isAllDay: Bool
}
public struct ClipboardFlightNumber: Equatable, Sendable {
    public let airline: String; public let flightNumber: String
}
public struct ClipboardMoneyAmount: Equatable, Sendable {
    public let amount: Double; public let currency: String
}
public struct ClipboardShipmentTracking: Equatable, Sendable {
    public let carrier: String; public let trackingNumber: String
}
```

フィールド構成は Apple 公式ドキュメントの `DDMatch*` プロパティに一致させた（`DDMatchPostalAddress`: street/city/state/postalCode/country、`DDMatchCalendarEvent`: startDate/endDate/startTimeZone/endTimeZone/isAllDay、`DDMatchFlightNumber`: airline/flightNumber、`DDMatchMoneyAmount`: amount/currency、`DDMatchShipmentTrackingNumber`: carrier/trackingNumber、`DDMatchLink`: url、`DDMatchEmailAddress` / `DDMatchPhoneNumber`: 値 + label）。`TimeZone` は Domain へ持ち込まず identifier 文字列へ変換する。

**UseCase を 2 つに分離**（v2 は `DetectValuesUseCase` が欠落していた）:

- `DetectPatternsUseCase.execute(_:scope:) async throws -> Set<ClipboardDetectionPattern>` → `detectedPatterns(for:)`
- `DetectValuesUseCase.execute(_:scope:) async throws -> ClipboardDetectedValues` → `detectedValues(for:)`

**変換**: `ClipboardDetectionMapper` が `ClipboardDetectionPattern` ↔ `PartialKeyPath<UIPasteboard.DetectedValues>` と `DDMatch*` → ドメイン型を担う。

**タイムアウト**: `timeouts.detection`（5 秒）。超過時は `timedOut(operation: .detection)` を配信し、遅延結果は破棄する（OS 中断は保証しない）。

**エラー**: 空集合は `emptyDetectionPatterns`。System の throw は `detectionFailed(ClipboardFailureDetail)` へ正規化。

---

### S11 貼り付け UI（receiver の寿命問題を修正）

v2 は Manager がコールバックのみ受け取り receiver を返さなかったため、receiver の保持と responder chain 参加を保証できなかった。v3 では **control と receiver を強保持する公開コンテナ**を返す。

```swift
/// A ready-to-place container that owns both the paste button and its receiver.
/// Add this single view to your hierarchy; the receiver joins the responder chain automatically.
@MainActor
public final class ClipboardPasteControlContainerView: UIView {
    public var onPaste: ((_ items: [ClipboardLoadedItem]) -> Void)?
    public var onPartialFailure: ((_ failures: [ClipboardError]) -> Void)?
    public var onPasteFailure: ((_ error: ClipboardError) -> Void)?

    public private(set) var control: UIPasteControl!             // strong
    public private(set) var receiver: ClipboardPasteReceiverView! // strong / subview

    public init(acceptedTypes: [String], displayMode: UIPasteControl.DisplayMode)
    // deinit: cancels pending loads and removes undelivered temporary directories
}
```

- コンテナが `control` と `receiver` を強保持し、`receiver` を subview として追加する（responder chain 参加を保証）
- 呼び出し側は**このコンテナ 1 つだけ**を view 階層に追加する
- `intrinsicContentSize` は `control` に委譲する
- 詳細制御が必要な場合のために `PasteControlFactory.makeComponents(...) -> (control: UIPasteControl, receiver: ClipboardPasteReceiverView)` も残すが、**その場合の保持責務は呼び出し側**である旨を DocC に明記する

**Manager API（P-16）**

```swift
public func makePasteControl(
    acceptedTypes: [String],
    displayMode: UIPasteControl.DisplayMode = .iconAndLabel,
    onPaste: @escaping ([ClipboardLoadedItem]) -> Void,
    onPartialFailure: (([ClipboardError]) -> Void)? = nil,
    onPasteFailure: ((ClipboardError) -> Void)? = nil
) -> ClipboardPasteControlContainerView
```

**集約契約（D-4）**

| 状況 | コールバック |
|---|---|
| 成功 1 件以上 | `onPaste(items)` を 1 回（入力 provider の順序を保持） |
| 成功 1 件以上 + 失敗あり | 上記に加えて `onPartialFailure(failures)` を 1 回（`onPaste` の後） |
| 成功 0 件 + 失敗 1 件以上 | `onPasteFailure(failures.first!)` を 1 回 |
| 成功 0 件 + 失敗 0 件 | `onPasteFailure(.noMatchingItem)` を 1 回 |
| **キャンセル（次回 paste 開始 / コンテナ解放）** | **UI コールバックを呼ばない**（下記） |

**キャンセル契約の明確化（v2 の S6 との不整合を解消）**

- **内部 completion**（`PasteItemProviderLoader` が `ClipboardLoadToken` 経由で扱う層）は S6 と同じく exactly-once であり、キャンセル時にも `.cancelled` を 1 回受け取る
- **UI コールバック**（`onPaste` / `onPartialFailure` / `onPasteFailure`）は、キャンセルが呼び出し側（View 解放・次の貼り付け）起因であるため**呼ばない**
- したがってエラー表の `cancelled` の発生元は「内部 completion」であり、UI へは伝播しない。U-79 はこの契約を検証する

- 1 provider あたりの型優先順位: text > url > image > file
- 部分失敗は他 provider の処理を止めない
- 一時ファイル: `onPaste` に載った `.file` は呼び出し側所有。載らなかった分は Presentation が削除

---

### S12 Unity Bridge

#### エラーコード変換経路

1. `ClipboardError` が `public var errorCode: String` を持つ
2. Manager callback は `(Bool, String? errorCode, String? errorMessage)`
3. Bridge は Manager の `async throws` 版を `Task { @MainActor in }` で呼び、`catch let error as ClipboardError` で **1 箇所だけ**変換する（message 解析はしない）

```swift
// 値を返さない操作
private func runVoid(_ operation: @escaping @MainActor () async throws -> Void,
                     handler: ((Bool, String?, String?) -> Void)?) {
    Task { @MainActor in
        do { try await operation(); handler?(true, nil, nil) }
        catch let e as ClipboardError { handler?(false, e.errorCode, e.errorDescription) }
        catch { handler?(false, ClipboardError.unknownErrorCode, ClipboardError.unknownMessage) }
    }
}

// 値を返す操作（v2 に無かった generic runner）
private func runValue<T>(_ operation: @escaping @MainActor () async throws -> T,
                         encode: @escaping (T) -> Any?,
                         handler: ((String) -> Void)?) {
    Task { @MainActor in
        do {
            let value = try await operation()
            handler?(Self.successEnvelope(encode(value)))
        } catch let e as ClipboardError {
            handler?(Self.errorEnvelope(code: e.errorCode, message: e.errorDescription))
        } catch {
            handler?(Self.errorEnvelope(code: ClipboardError.unknownErrorCode,
                                        message: ClipboardError.unknownMessage))
        }
    }
}
```

`ClipboardError.unknownErrorCode` / `unknownMessage` は Domain の `public static let` として定義する（v2 は `unknownCode` を例示しながら型に無かった）。

#### C 文字列と callback の規約（v2 に無かった項目）

| 事項 | 規約 |
|---|---|
| 文字列エンコーディング | すべて UTF-8 の `const char*` |
| 引数文字列の寿命 | Bridge が同期的に `NSString` へコピーする。Unity 側は呼び出し後に解放してよい |
| callback 引数文字列の寿命 | **callback 実行中のみ有効**。Unity 側は即座に managed string へコピーすること（既存 Share Bridge ヘッダと同一規約） |
| callback が NULL | 許容。結果は破棄し、ログのみ残す（クラッシュさせない） |
| callback のスレッド | 常に main thread |
| 引数 JSON が NULL | `CLIPBOARD_INVALID_REQUEST` |

#### JSON schema（全 endpoint・全 union）

**共通 envelope**

- 成功（JSON callback）: `{"ok": true, "data": <object|null>}`
- 失敗（JSON callback）: `{"ok": false, "error": {"code": "CLIPBOARD_*", "message": "...", "details": {"domain": "...", "code": 0}}}`（`details` は任意）
- Operation callback: `(BOOL isSuccess, NSString* errorCode, NSString* errorMessage)`

**`scope` オブジェクト**

| kind | 必須 | 任意 |
|---|---|---|
| `general` | `kind` | - |
| `named` | `kind`, `name`（非空文字列） | - |
| `unique` | `kind`, `name`（非空文字列） | - |

省略時は `general`。未知 kind / 必須欠落は `CLIPBOARD_INVALID_REQUEST`。

**`content` union（9 kind、v2 の `{...}` を全展開）**

| kind | 必須フィールド | 型 | nullable |
|---|---|---|---|
| `plainText` | `text` | string | 不可（空文字は可） |
| `htmlText` | `plain`, `html` | string, string | 不可 |
| `url` | `urlString` | string | 不可 |
| `imageFile` | `path` | string | 不可 |
| `imageData` | `base64`, `utType` | string, string | 不可 |
| `color` | `red`, `green`, `blue`, `alpha` | number ×4 | 不可 |
| `customData` | `base64`, `utType` | string, string | 不可 |
| `multipleText` | `texts` | string[] | 不可（空配列は `EMPTY_ITEMS`） |
| `multiRepresentation` | `representations` | `{utType: base64}` の object | 不可（空 object は `EMPTY_ITEMS`） |

**`options` オブジェクト**（`clipboardCopy` のみ）

| フィールド | 型 | 既定 | nullable |
|---|---|---|---|
| `localOnly` | bool | `true` | 不可 |
| `expirationDate` | ISO 8601 string | `null` | 可 |

**`loadRequest` union**

| kind | 必須 |
|---|---|
| `text` / `url` / `image` | `kind` のみ |
| `file` | `kind`, `utType` |

**`loadedItem` union（レスポンス）**

| kind | フィールド |
|---|---|
| `text` | `text`: string |
| `url` | `urlString`: string |
| `imageData` | `base64`: string, `utType`: string |
| `file` | `path`: string |

**`patterns` 配列**: `ClipboardDetectionPattern` の rawValue（11 種）。未知値は `CLIPBOARD_INVALID_REQUEST`。空配列は `CLIPBOARD_EMPTY_PATTERNS`。

**`detectedValues` オブジェクト（全 11 項目）**

| フィールド | 型 | nullable |
|---|---|---|
| `detectedPatterns` | string[] | 不可（空配列可） |
| `probableWebURL` / `probableWebSearch` | string | 可 |
| `number` | number | 可 |
| `links` | string[] | 不可 |
| `emailAddresses` / `phoneNumbers` | `{value: string, label: string?}[]` | 不可 |
| `postalAddresses` | `{street?, city?, state?, postalCode?, country?}[]` | 不可 |
| `calendarEvents` | `{startDate?: ISO8601, endDate?: ISO8601, startTimeZone?: string, endTimeZone?: string, isAllDay: bool}[]` | 不可 |
| `flightNumbers` | `{airline: string, flightNumber: string}[]` | 不可 |
| `moneyAmounts` | `{amount: number, currency: string}[]` | 不可 |
| `shipmentTrackingNumbers` | `{carrier: string, trackingNumber: string}[]` | 不可 |

**endpoint 一覧**

| C 関数 | request | success `data` | 対応 |
|---|---|---|---|
| `clipboardCopy` | `{scope?, content, options?}` | `null` | P-1 |
| `clipboardAppend` | `{scope?, content}`（`options` 指定は `INVALID_REQUEST`） | `null` | P-2 |
| `clipboardRead` | `{scope?}` | `{numberOfItems: int, items: [{typeIdentifiers: string[], text: string?, urlString: string?, imageDataUTType: string?}]}` | P-3 |
| `clipboardReadData` | `{scope?, utType}` | `{utType: string, base64: string, byteCount: int}` または `null` | P-4 |
| `clipboardGetSnapshot` | `{scope?, matchingTypes?: string[]}` | `{hasStrings, hasURLs, hasImages, hasColors: bool, numberOfItems: int, typeIdentifiers: string[], allTypeIdentifiers: string[][], matchingItemIndexes: int[]?}` | P-5 |
| `clipboardClear` | `{scope?}` | `null` | P-6 |
| `clipboardCreatePasteboard` | `{request: {kind: "named", name} \| {kind: "unique"}}` | `{scope: {kind, name}}` | P-7 |
| `clipboardRemovePasteboard` | `{scope}` | `null` | P-8 |
| `clipboardDetectPatterns` | `{scope?, patterns: string[]}` | `{patterns: string[]}` | P-9 |
| `clipboardDetectValues` | `{scope?, patterns: string[]}` | 上記 `detectedValues` | P-10 |
| `clipboardLoadItem` | `{scope?, request: loadRequest}` | `loadedItem` | P-11 |
| `clipboardCancelLoads` | 引数なし | - | P-12 |
| `clipboardStartObserving` | `{scope?}` | 開始結果は **operation callback**。イベントは change callback へ `{kind, typesAdded?, typesRemoved?, scope}` | P-13 |
| `clipboardStopObserving` | 引数なし | - | P-14 |
| `clipboardCheckForegroundChange` | `{scope?}` | `{changed: bool}` | P-15 |

**未知キー**: 無視する（前方互換）。**Base64 不正**: `CLIPBOARD_INVALID_REQUEST`。

**C ABI**

```c
typedef void (*ClipboardOperationCallback)(bool isSuccess,
                                           const char* errorCode,
                                           const char* errorMessage);
typedef void (*ClipboardJsonCallback)(const char* json);
typedef void (*ClipboardChangeCallback)(const char* eventJson);

void clipboardCopy(const char* requestJson, ClipboardOperationCallback callback);
void clipboardAppend(const char* requestJson, ClipboardOperationCallback callback);
void clipboardRead(const char* requestJson, ClipboardJsonCallback callback);
void clipboardReadData(const char* requestJson, ClipboardJsonCallback callback);
void clipboardGetSnapshot(const char* requestJson, ClipboardJsonCallback callback);
void clipboardClear(const char* requestJson, ClipboardOperationCallback callback);
void clipboardCreatePasteboard(const char* requestJson, ClipboardJsonCallback callback);
void clipboardRemovePasteboard(const char* requestJson, ClipboardOperationCallback callback);
void clipboardDetectPatterns(const char* requestJson, ClipboardJsonCallback callback);
void clipboardDetectValues(const char* requestJson, ClipboardJsonCallback callback);
void clipboardLoadItem(const char* requestJson, ClipboardJsonCallback callback);
void clipboardCancelLoads(void);
/// startCallback reports whether observation started; changeCallback receives events.
void clipboardStartObserving(const char* requestJson,
                             ClipboardChangeCallback changeCallback,
                             ClipboardOperationCallback startCallback);
void clipboardStopObserving(void);
void clipboardCheckForegroundChange(const char* requestJson, ClipboardJsonCallback callback);
```

`.m` の完了ブロック引数は `BOOL` / `NSString * _Nullable`。全 C 関数の先頭で `[ClipboardRedaction json:...]` を通したログを出す。

---

## API 設計（公開 / 内部）

### 公開 API（`IosClipboardManager`、`@MainActor`）

callback は全経路で main actor から 1 回だけ呼ぶ。

| # | callback 版 | `async throws` 版 |
|---|---|---|
| P-1 | `copy(_:options:scope:completion: (Bool, String?, String?) -> Void)` | `copy(_:options:scope:) async throws` |
| P-2 | `append(_:scope:completion:)` | `append(_:scope:) async throws` |
| P-3 | `read(scope:completion: (ClipboardReadResult?, String?, String?) -> Void)` | `read(scope:) async throws -> ClipboardReadResult` |
| P-4 | `readData(utType:scope:completion: (Data?, String?, String?) -> Void)` | `readData(utType:scope:) async throws -> Data?` |
| P-5 | `snapshot(matchingTypes:scope:completion:)` | `snapshot(matchingTypes:scope:) async throws -> ClipboardSnapshot` |
| P-6 | `clear(scope:completion:)` | `clear(scope:) async throws` |
| P-7 | `createPasteboard(_:completion:)` | `createPasteboard(_:) async throws -> PasteboardScope` |
| P-8 | `removePasteboard(_:completion:)` | `removePasteboard(_:) async throws` |
| P-9 | `detectPatterns(_:scope:completion:)` | `detectPatterns(_:scope:) async throws -> Set<ClipboardDetectionPattern>` |
| P-10 | `detectValues(_:scope:completion:)` | `detectValues(_:scope:) async throws -> ClipboardDetectedValues` |
| P-11 | `loadItem(_:scope:completion:) -> any ClipboardLoadToken` | `loadItem(_:scope:) async throws -> ClipboardLoadedItem` |

| # | 同期 control API（callback / async 版なし。`common.md` 129 行の任意規定を適用） |
|---|---|
| P-12 | `cancelAllLoads()` |
| P-13 | `startObserving(scope:onEvent:) throws` |
| P-14 | `stopObserving()` |
| P-15 | `checkForegroundChange(scope:) -> Bool` |
| P-16 | `makePasteControl(acceptedTypes:displayMode:onPaste:onPartialFailure:onPasteFailure:) -> ClipboardPasteControlContainerView` |

### 内部 API

| 型 | 可視性 | 理由 |
|---|---|---|
| `ClipboardRepository` / `ClipboardItemLoader` / `ClipboardLoadToken` / `ClipboardTypeIdentifierValidating` / `ClipboardClock` | `public`（protocol） | Manager の test 用 init で注入 |
| `ClipboardRepositoryImpl` / `ClipboardItemLoaderImpl` / `ClipboardTypeIdentifierValidator` | `internal` | UIKit / `UTType` 依存を露出しない |
| `PasteboardResolver` / `ClipboardMappers` / `ClipboardDetectionMapper` / `ClipboardTemporaryFileStore` / `ClipboardImageCoder` / `ClipboardLog` / `ClipboardRedactionCore` | `internal` | 実装詳細 |
| `ClipboardRedaction` | `@objc public` | 別モジュール / ObjC から利用 |
| `PasteItemProviderLoader` | `internal` | `NSItemProvider` を露出しない |
| `ClipboardPasteControlContainerView` / `ClipboardPasteReceiverView` / `PasteControlFactory` | `public` | 呼び出し側が配置するため |
| `ClipboardCancellationBox` | `public` | Manager が返す token の補助として公開 |
| `ClipboardChangeTracker` / `ClipboardContentValidator` | `public` | 純ロジックの単体テスト対象 |
| UseCase 群（11 個） | `public` | 既存 `ShareContentUseCase` に合わせる |

---

## ドメインエラー一覧（全 24 ケース）

```swift
public enum ClipboardError: Error, Equatable {
    case emptyContent
    case emptyItemList
    case emptyDetectionPatterns
    case invalidURL(String)
    case invalidTypeIdentifier(String)
    case invalidPasteboardName(String)
    case invalidColor
    case invalidImageData
    case invalidExpirationDate
    case invalidRequest(String)
    case contentTooLarge(byteCount: Int, limit: Int)
    case fileNotFound(path: String)
    case imageLoadFailed(path: String)
    case imageEncodingFailed
    case pasteboardUnavailable(name: String)
    case cannotRemoveGeneralPasteboard
    case noMatchingItem
    case providerLoadFailed(ClipboardFailureDetail)
    case unexpectedType
    case fileCopyFailed(ClipboardFailureDetail)
    case cancelled
    case timedOut(operation: ClipboardOperationKind)
    case detectionFailed(ClipboardFailureDetail)
    case unknown(ClipboardFailureDetail)

    public static let unknownErrorCode = "CLIPBOARD_UNKNOWN"
    public static let unknownMessage = "An unknown error occurred."
}

public enum ClipboardOperationKind: String, Sendable {
    case detection, providerLoad, imageCoding
}
```

**件数の単一情報源**: 24 ケース。うち Android 共通 4、iOS 固有 20（下記対応表の行数と一致する）。

| # | ケース | 発生元 | 発生条件 |
|---|---|---|---|
| E-01 | `emptyContent` | `ClipboardContentValidator` | html 空白のみ / `Data` が空 / `multiRepresentation` に空 `Data` |
| E-02 | `emptyItemList` | `ClipboardContentValidator` | `multipleText` 空配列 / `multiRepresentation` 空辞書 |
| E-03 | `emptyDetectionPatterns` | `DetectPatternsUseCase` / `DetectValuesUseCase` | パターン集合が空 |
| E-04 | `invalidURL` | `ClipboardContentValidator` | 空 / スキーム無し / http(s) で host 無し |
| E-05 | `invalidTypeIdentifier` | `ClipboardTypeIdentifierValidator` | `UTType(_:)` 解決不能 / image 非適合 / キーが空 |
| E-06 | `invalidPasteboardName` | `CreatePasteboardUseCase` | 名前が空白のみ |
| E-07 | `invalidColor` | `ClipboardContentValidator` | 非有限値 / 0.0...1.0 外 |
| E-08 | `invalidImageData` | `ClipboardImageCoder` | デコード不能 |
| E-09 | `invalidExpirationDate` | `ClipboardContentValidator` | `expirationDate <= clock.now()` |
| E-10 | `invalidRequest` | Bridge / Manager | JSON 不正・必須欠落・未知 kind・Base64 不正・`append` に options・空パス |
| E-11 | `contentTooLarge` | Validator / Loader / ImageCoder | `maxCopyByteCount` / `maxLoadByteCount` / `maxImagePixelCount` 超過 |
| E-12 | `fileNotFound` | `ClipboardRepositoryImpl` | `imageFile` のパスが存在しない |
| E-13 | `imageLoadFailed` | `ClipboardRepositoryImpl` | `UIImage(contentsOfFile:)` が nil |
| E-14 | `imageEncodingFailed` | `ClipboardImageCoder` | `pngData()` が nil |
| E-15 | `pasteboardUnavailable` | `PasteboardResolver` | `UIPasteboard(name:create:)` が nil |
| E-16 | `cannotRemoveGeneralPasteboard` | `RemovePasteboardUseCase` | `.general` を破棄しようとした |
| E-17 | `noMatchingItem` | Loader / Presentation loader | 条件に合う provider が無い |
| E-18 | `providerLoadFailed` | Loader | provider の completion が error を返した |
| E-19 | `unexpectedType` | Loader | error は nil だが期待型へ変換できない |
| E-20 | `fileCopyFailed` | `ClipboardTemporaryFileStore` | ディレクトリ作成 / コピー失敗、containment 検証失敗 |
| E-21 | `cancelled` | Loader / Presentation loader の**内部 completion** | `cancelAll()` / `deinit` / token `cancel()` / Task キャンセル。**S11 の UI コールバックへは伝播しない** |
| E-22 | `timedOut` | Loader / DetectUseCase / ImageCoder | `providerLoad` / `detection` / `imageCoding` の各タイムアウト超過 |
| E-23 | `detectionFailed` | `ClipboardRepositoryImpl` | 検出 API が throw |
| E-24 | `unknown` | 全層 | 上記に該当しないシステムエラー |

---

## エラーコード / メッセージ対応表（24 行）

`ClipboardError.errorCode` と `errorDescription` は**固定英語文**（D-13）。system の `localizedDescription` は載せない。

| ドメインエラー | errorCode | message（固定英語） | Android |
|---|---|---|---|
| `emptyContent` | `CLIPBOARD_EMPTY_CONTENT` | `Clipboard content is empty. Please provide text or HTML.` | 共通 |
| `emptyItemList` | `CLIPBOARD_EMPTY_ITEMS` | `No items provided for clipboard copy.` | 共通 |
| `pasteboardUnavailable(name)` | `CLIPBOARD_UNAVAILABLE` | `Pasteboard is unavailable: {name}. A named pasteboard exists only while its creating app is running.` | 共通 |
| `unknown(_)` | `CLIPBOARD_UNKNOWN` | `An unknown error occurred.` | 共通 |
| `emptyDetectionPatterns` | `CLIPBOARD_EMPTY_PATTERNS` | `No detection patterns were specified.` | iOS 固有 |
| `invalidURL(v)` | `CLIPBOARD_INVALID_URL` | `Invalid URL: {v}` | iOS 固有 |
| `invalidTypeIdentifier(v)` | `CLIPBOARD_INVALID_TYPE` | `Invalid uniform type identifier: {v}` | iOS 固有 |
| `invalidPasteboardName(v)` | `CLIPBOARD_INVALID_NAME` | `Invalid pasteboard name: {v}` | iOS 固有 |
| `invalidColor` | `CLIPBOARD_INVALID_COLOR` | `Color components must be finite and within 0.0...1.0.` | iOS 固有 |
| `invalidImageData` | `CLIPBOARD_INVALID_IMAGE_DATA` | `The provided image data could not be decoded.` | iOS 固有 |
| `invalidExpirationDate` | `CLIPBOARD_INVALID_EXPIRATION` | `expirationDate must be in the future.` | iOS 固有 |
| `invalidRequest(reason)` | `CLIPBOARD_INVALID_REQUEST` | `Invalid request: {reason}` | iOS 固有 |
| `contentTooLarge(b, l)` | `CLIPBOARD_CONTENT_TOO_LARGE` | `Content is too large: {b} bytes exceeds the limit of {l} bytes.` | iOS 固有 |
| `fileNotFound(path)` | `CLIPBOARD_FILE_NOT_FOUND` | `File not found at path: {path}` | iOS 固有 |
| `imageLoadFailed(path)` | `CLIPBOARD_IMAGE_LOAD_FAILED` | `Failed to load image at path: {path}` | iOS 固有 |
| `imageEncodingFailed` | `CLIPBOARD_IMAGE_ENCODE_FAILED` | `Failed to encode the pasted image.` | iOS 固有 |
| `cannotRemoveGeneralPasteboard` | `CLIPBOARD_CANNOT_REMOVE_GENERAL` | `The general pasteboard cannot be removed.` | iOS 固有 |
| `noMatchingItem` | `CLIPBOARD_NO_MATCHING_ITEM` | `No clipboard item matches the requested type.` | iOS 固有 |
| `providerLoadFailed(_)` | `CLIPBOARD_LOAD_FAILED` | `Failed to load the clipboard item.` | iOS 固有 |
| `unexpectedType` | `CLIPBOARD_UNEXPECTED_TYPE` | `The clipboard item could not be converted to the requested type.` | iOS 固有 |
| `fileCopyFailed(_)` | `CLIPBOARD_FILE_COPY_FAILED` | `Failed to copy the pasted file.` | iOS 固有 |
| `cancelled` | `CLIPBOARD_CANCELLED` | `The clipboard load was cancelled.` | iOS 固有 |
| `timedOut(op)` | `CLIPBOARD_TIMED_OUT` | `The operation timed out: {op}.` | iOS 固有 |
| `detectionFailed(_)` | `CLIPBOARD_DETECTION_FAILED` | `Pattern detection failed.` | iOS 固有 |

**内訳**: 全 24 行 = Android 共通 4 + iOS 固有 20。

### Android とのコード差異表

| コード | Android | iOS | 備考 |
|---|---|---|---|
| `CLIPBOARD_EMPTY_CONTENT` / `CLIPBOARD_EMPTY_ITEMS` / `CLIPBOARD_UNAVAILABLE` / `CLIPBOARD_UNKNOWN` | あり | あり | **完全一致（4 種）** |
| `CLIPBOARD_INVALID_URI` | あり | なし | Android 固有（`content://` URI） |
| `CLIPBOARD_READ_NOT_ALLOWED` | あり | なし | Android 固有（iOS はプロンプトを OS が処理） |
| `CLIPBOARD_SECURITY` | あり | なし | Android 固有（`SecurityException`） |
| 上記以外の iOS コード **20 種** | なし | あり | iOS 固有（`UIPasteboard` / `NSItemProvider` / `DataDetection` 由来） |

### `cancelled` の扱い

クリップボードのロードキャンセルは呼び出し側起点で結果を利用できないため `isSuccess == false` とする。呼び出し側は `errorCode == "CLIPBOARD_CANCELLED"` を正常系として無視できる。DocC・Bridge ヘッダ・サンプルアプリの 3 箇所で示す。S11 の UI コールバックには伝播しない（E-21）。

---

## テスト設計

### 単体テスト（Swift Testing / `IosLibraryTests`）

#### Domain

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-01 | `ClipboardError` | 正常 | 全 24 ケースの `errorCode` が対応表と一致し、重複がない |
| U-02 | 〃 | 正常 | 全 24 ケースの `errorDescription` が固定英語文で、system message を含まない |
| U-03 | 〃 | 正常 | `unknownErrorCode` / `unknownMessage` が `.unknown(_)` の値と一致 |
| U-04 | `ClipboardFailureDetail` | 正常 | `debugMessage` が公開 API から見えない（`internal`） |
| U-05 | `ClipboardTimeouts` / `ClipboardLimits` | 正常 | `.default` の値が設計値と一致 |

#### Application（純ロジック）

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-06 | `ClipboardContentValidator` | 正常 | `plainText("")` は成功 |
| U-07 | 〃 | 異常 | html 空白のみ → `emptyContent` |
| U-08 | 〃 | 正常 | `htmlText` の plain が空でも成功 |
| U-09 | 〃 | 異常 | `url("")` / `"example.com"` / `"https://"` → `invalidURL` |
| U-10 | 〃 | 異常 | `multipleText([])` / `multiRepresentation([:])` → `emptyItemList` |
| U-11 | 〃 | 異常 | `multiRepresentation` に空 `Data` → `emptyContent` |
| U-12 | 〃 | 異常 | `multiRepresentation` のキーが空文字 → `invalidTypeIdentifier` |
| U-13 | 〃 | 異常 | `color` が `.infinity` / `-0.1` / `1.1` → `invalidColor` |
| U-14 | 〃 | 境界 | `color` が 0.0 / 1.0 は成功 |
| U-15 | 〃 | 異常 | **注入 Clock** で `expirationDate == now` / 過去 → `invalidExpirationDate` |
| U-16 | 〃 | 境界 | 注入 Clock で `now + 1s` は成功（決定的） |
| U-17 | 〃 | 異常 | `imageFile("")` → `invalidRequest` |
| U-18 | 〃 | 異常 | `Data` 合計が `maxCopyByteCount` 超 → `contentTooLarge` |
| U-19 | `ClipboardChangeTracker` | 正常 | 基準値と異なるとき true、同じとき false |
| U-20 | 〃 | 正常 | `hasChanged` 後に基準値が更新され、連続呼び出しは false |
| U-21 | 〃 | 境界 | `markReported` 後の `hasChanged` は false |
| U-22 | 〃 | 境界 | `resync` 後は停止中の変更を検知しない |

#### Application（UseCase / Mock 注入）

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-23 | `CopyContentUseCase` | 正常 | 9 kind で `copyCallCount == 1`、options 一致 |
| U-24 | 〃 | 異常 | Validator エラーが伝播し Repository 未呼び出し |
| U-25 | 〃 | 異常 | UTI 検証 Port が throw → Repository 未呼び出し |
| U-26 | 〃 | 異常 | `shouldFail = true` → Repository エラー伝播 |
| U-27 | `AppendContentUseCase` | 正常 | `appendCallCount == 1`。options 引数が型として存在しない |
| U-28 | `ReadContentUseCase` | 正常 | `stubbedReadResult` を返す |
| U-29 | 〃 | 境界 | 空 → `items == []` かつ throw しない |
| U-30 | `ReadDataUseCase` | 正常 | `stubbedData` を返し `readDataCallCount == 1` |
| U-31 | 〃 | 異常 | UTI 検証 Port が throw → `invalidTypeIdentifier`、Repository 未呼び出し |
| U-32 | 〃 | 境界 | 該当なし → `nil`、throw しない |
| U-33 | `GetSnapshotUseCase` | 正常 | `stubbedSnapshot` を返す |
| U-34 | 〃 | 正常 | `matchingTypes` 指定時に `matchingItemIndexes` が渡る |
| U-35 | 〃 | 境界 | `matchingTypes` 未指定時は `matchingItemIndexes == nil` |
| U-36 | `ClearClipboardUseCase` | 正常 | `clearCallCount == 1` |
| U-37 | `CreatePasteboardUseCase` | 異常 | 空白名 → `invalidPasteboardName` |
| U-38 | 〃 | 正常 | `.unique` → `.unique(生成名)` |
| U-39 | `RemovePasteboardUseCase` | 異常 | `.general` → `cannotRemoveGeneralPasteboard` |
| U-40 | 〃 | 境界 | 未作成の名前 → 成功（冪等） |
| U-41 | `DetectPatternsUseCase` | 異常 | 空集合 → `emptyDetectionPatterns` |
| U-42 | 〃 | 正常 | `stubbedPatterns` を返す |
| U-43 | 〃 | 異常 | タイムアウト超過 → `timedOut(.detection)`、遅延結果は破棄 |
| U-44 | `DetectValuesUseCase` | 異常 | 空集合 → `emptyDetectionPatterns` |
| U-45 | 〃 | 正常 | **全 11 項目**が `stubbedDetectedValues` から往復する |
| U-46 | 〃 | 異常 | タイムアウト超過 → `timedOut(.detection)` |
| U-47 | `LoadItemUseCase` | 正常 | text / url / image / file の 4 種を返す |
| U-48 | 〃 | 異常 | 各エラー（`noMatchingItem` / `providerLoadFailed` / `unexpectedType` / `fileCopyFailed` / `cancelled` / `timedOut` / `contentTooLarge`）が伝播 |
| U-49 | 〃 | 正常 | 返却 token の `cancel()` が Loader の `cancelCallCount` を増やす |

#### Data

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-50 | `ClipboardRepositoryImpl` | 正常 | 9 kind を書き込み → `read` で往復一致（`.unique` scope） |
| U-51 | 〃 | 正常 | `multiRepresentation` で 1 アイテムに 2 UTI |
| U-52 | 〃 | 正常 | `readData` が指定 UTI の `Data` を返し、非該当は nil |
| U-53 | 〃 | 正常 | `append` で件数が増える |
| U-54 | 〃 | 正常 | `clear` 後に `numberOfItems == 0` |
| U-55 | 〃 | 正常 | `snapshot` の `has*` が内容と一致 |
| U-56 | 〃 | 正常 | `snapshot(matchingTypes:)` の `matchingItemIndexes` が昇順で一致 |
| U-57 | 〃 | 異常 | 存在しない画像パス → `fileNotFound` |
| U-58 | 〃 | 異常 | 解決できない名前 → `pasteboardUnavailable` |
| U-59 | 〃 | 正常 | `remove(withName:)` 後に `create: false` で解決できない |
| U-60 | `ClipboardTypeIdentifierValidator` | 正常 | `public.utf8-plain-text` / `public.png` などが通る |
| U-61 | 〃 | 異常 | 解決不能な文字列 → `invalidTypeIdentifier` |
| U-62 | 〃 | 異常 | `imageData` に非画像 UTI → `invalidTypeIdentifier` |
| U-63 | `ClipboardDetectionMapper` | 正常 | 11 パターン ↔ キーパスの双方向変換 |
| U-64 | 〃 | 正常 | `DDMatch*` → ドメイン型のフィールド対応（postal / calendar / flight / money / shipment / link / email / phone） |
| U-65 | 〃 | 正常 | `TimeZone` が identifier 文字列へ変換される |
| U-66 | `ClipboardTemporaryFileStore` | 正常 | コピー成功時にファイルが専用ディレクトリ配下に存在 |
| U-67 | 〃 | 異常 | `suggestedName` が `../../evil.png` → 専用ディレクトリ外に出ない |
| U-68 | 〃 | 異常 | パス区切り / 制御文字 / 1000 文字超 → UUID + 許可拡張子のみ |
| U-69 | 〃 | 境界 | 許可外拡張子 → `bin` |
| U-70 | 〃 | 正常 | コピー失敗時にディレクトリが残らない |
| U-71 | 〃 | 正常 | 起動時 cleanup が 24 時間より古い他セッションのみ削除 |
| U-72 | 〃 | 正常 | **アクティブな自セッションを削除しない**（回帰） |
| U-73 | `ClipboardImageCoder` | 正常 | main 以外のスレッドでエンコードされる |
| U-74 | 〃 | 異常 | エンコード不能 → `imageEncodingFailed` |
| U-75 | 〃 | 異常 | ピクセル数が `maxImagePixelCount` 超 → `contentTooLarge` |
| U-76 | 〃 | 異常 | `imageCoding` タイムアウト超過 → `timedOut(.imageCoding)` |
| U-77 | `ClipboardCancellationBox` | 正常 | `attach` 後の `cancel()` が token を cancel する |
| U-78 | 〃 | 境界 | `attach` 前に `cancel()` → `attach` 時に即 cancel される |
| U-79 | 〃 | 正常 | 任意スレッドから `cancel()` を呼べる（`Sendable` 要件） |

#### Presentation（S11）

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-80 | `PasteItemProviderLoader` | 正常 | 全 provider 成功 → `items` が入力順序を保持、`failures` 空 |
| U-81 | 〃 | 正常 | 混在 → `items` に成功分、`failures` に失敗分 |
| U-82 | 〃 | 異常 | 全失敗 → `items` 空、`failures` 全件 |
| U-83 | 〃 | 境界 | provider 配列が空 → 両方空 |
| U-84 | 〃 | 正常 | `cancelAll()` で**内部 completion に `.cancelled` が 1 回**届き、一時ディレクトリが残らない |
| U-85 | 〃 | 異常 | provider タイムアウト → `timedOut(.providerLoad)` |
| U-86 | `ClipboardPasteReceiverView` | 正常 | 成功≥1 → `onPaste` 1 回、`onPasteFailure` 0 回 |
| U-87 | 〃 | 正常 | 成功 + 失敗 → `onPaste` 1 回 + `onPartialFailure` 1 回（順序も検証） |
| U-88 | 〃 | 異常 | 成功 0 + 失敗あり → `onPasteFailure` 1 回、`onPaste` 0 回 |
| U-89 | 〃 | 境界 | 成功 0 + 失敗 0 → `onPasteFailure(.noMatchingItem)` 1 回 |
| U-90 | 〃 | 正常 | **キャンセル時に UI コールバックが 1 回も呼ばれない**（E-21 の契約） |
| U-91 | 〃 | 正常 | 連続 paste で前回の未完了ロードがキャンセルされる |
| U-92 | 〃 | 正常 | `canPaste` が `acceptedTypes` と同じ判定になる |
| U-93 | `ClipboardPasteControlContainerView` | 正常 | `control` と `receiver` を強保持し、`receiver` が subview になっている |
| U-94 | 〃 | 正常 | コンテナのみを階層へ追加すれば `receiver` が responder chain に入る |
| U-95 | 〃 | 正常 | コンテナ解放時に未完了ロードがキャンセルされ、一時ディレクトリが残らない |
| U-96 | 〃 | 正常 | `intrinsicContentSize` が `control` に一致する |

#### Manager

| ID | 系 | ケース |
|---|---|---|
| U-97 | 正常 | P-1〜P-11 の callback 版が main actor で 1 回だけ呼ばれる（API ごとに個別ケース） |
| U-98 | 異常 | Repository エラー → `(false, errorCode, errorMessage)` で `errorCode` が対応表と一致 |
| U-99 | 正常 | `async throws` 版が型付き `ClipboardError` を throw |
| U-100 | 正常 | P-4 `readData` が callback / async の双方で動作 |
| U-101 | 正常 | P-9 `detectPatterns` / P-10 `detectValues` が callback / async の双方で動作 |
| U-102 | 正常 | P-12〜P-16 が同期で戻り値を返す（`@MainActor` 上で成立） |
| U-103 | 正常 | `startObserving` 二重呼び出しでイベントが重複しない |
| U-104 | 正常 | `stopObserving` 後にイベントが届かない |
| U-105 | 正常 | `stopObserving` → `startObserving` で古いイベントが新購読者へ届かない |
| U-106 | 正常 | `cancelAllLoads()` で各 pending に `.cancelled` が 1 回 |
| U-107 | 正常 | provider 不在の即時失敗直後に `cancelAllLoads()` → 通知は 1 回のみ |
| U-108 | 正常 | Manager 解放時に pending へ `.cancelled` が 1 回 |
| U-109 | 正常 | token 単体の `cancel()` で当該リクエストのみ `.cancelled` |
| U-110 | 正常 | async 版の Task キャンセルで token が cancel され、continuation が 1 回だけ resume |
| U-111 | 境界 | **キャンセル / 完了 / タイムアウトの 3 者競合**で配信が 1 回のみ（3 通りの到着順序を検証） |
| U-112 | 正常 | `checkForegroundChange` が同期で `Bool` を返す |

#### 秘匿ログ

| ID | 系 | ケース |
|---|---|---|
| U-113 | 正常 | `ClipboardRedaction` の出力に元の値が含まれない（text / data / json / path） |
| U-114 | 正常 | `ClipboardRedaction` が `@objc` として公開されている（ObjC から解決可能） |
| U-115 | 正常 | `ClipboardLog` が failure detail の `debugMessage` を出力しない |

#### Unity Bridge

| ID | 系 | ケース |
|---|---|---|
| U-116 | 正常 | 9 content kind の JSON パース往復（必須 / 任意 / nullable を含む） |
| U-117 | 正常 | `scope` 3 kind の往復と、省略時 `.general` |
| U-118 | 異常 | NULL / 空文字 / パース不能 → `CLIPBOARD_INVALID_REQUEST` を main で 1 回 |
| U-119 | 異常 | 未知の `kind`（scope / content / loadRequest / pattern）→ `CLIPBOARD_INVALID_REQUEST`。メッセージに受領値を含めない |
| U-120 | 異常 | 必須キー欠落 → `CLIPBOARD_INVALID_REQUEST` |
| U-121 | 異常 | Base64 不正 → `CLIPBOARD_INVALID_REQUEST` |
| U-122 | 異常 | `clipboardAppend` に `options` 指定 → `CLIPBOARD_INVALID_REQUEST` |
| U-123 | 正常 | 余分なキーは無視される |
| U-124 | 正常 | 15 endpoint すべての success `data` スキーマが仕様と一致 |
| U-125 | 正常 | `detectedValues` の全 11 項目が JSON 化される |
| U-126 | 正常 | `loadedItem` 4 kind の JSON 化 |
| U-127 | 正常 | エラー envelope が `{"ok":false,"error":{"code","message","details"?}}` |
| U-128 | 正常 | `errorCode` が Manager の値をそのまま透過（message 解析なし） |
| U-129 | 正常 | `clipboardStartObserving` の開始失敗が **operation callback** で返る |
| U-130 | 境界 | callback が NULL でもクラッシュしない（全 endpoint） |
| U-131 | 正常 | Bridge のログに request JSON 本文 / Base64 / パスが含まれない |

### 統合テスト

| ID | 内容 |
|---|---|
| I-01 | `IosClipboardManager` 実体で copy → snapshot → read → readData → append → clear が一貫（`.unique` scope） |
| I-02 | `.named` を作成 → 読み書き → `remove` 後に解決できない |
| I-03 | `setItems` の `localOnly` / `expirationDate` が例外なく適用される |
| I-04 | `startObserving` 中に自アプリで copy → `changed` イベントが 1 回届く |
| I-05 | `loadItem(.file)` の成功 URL が completion 後も読める |
| I-06 | `loadItem` 実行中に `cancelAllLoads()` → `.cancelled` 1 回、一時ディレクトリ残留なし |
| I-07 | `loadItem` のタイムアウト（短縮設定）→ `timedOut` 1 回、一時ディレクトリ残留なし |
| I-08 | Bridge の 15 endpoint を通した end-to-end |
| I-09 | **`ClipboardRedaction` が `UnityIosPlugin` の Swift と `.m` の双方からビルド・呼び出しできる**（モジュール境界） |
| I-10 | `SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` で `IosLibrary` と `UnityIosPlugin` がビルド警告・エラーなし |

### 手動確認項目（実機必須）

| ID | 対応リスク | 内容 |
|---|---|---|
| M-01 | プライバシー | 企画書「テスト行列」16 ケースを iOS 18 / iOS 26 実機で観測（許可プロンプト / アクセス通知を別列） |
| M-02 | プライバシー | `snapshot` のみで通知・プロンプトが出ない |
| M-03 | プライバシー | `checkForegroundChange`（`changeCount`）の通知・プロンプト有無（D-3 の採否） |
| M-04 | プライバシー | `detectValues` で通知・プロンプトが出ない |
| M-05 | プライバシー | `itemProviders` getter / `canLoadObject` / ロードの契機切り分け（R-02） |
| M-16 | **append の privacy 継承** | **`copy(localOnly:true)` の直後に `append` した item が Universal Clipboard へ転送されるかを 2 台で観測**（D-8 / R-13 の判断材料） |
| M-06 | Universal Clipboard | `localOnly: false` の転送成功（正の対照）→ `true` の非転送 |
| M-07 | 機微データ残留 | `expirationDate` 経過後に取得できない |
| M-08 | 名前付き寿命 | 送信側終了後に解決できない / バックグラウンド中は解決できる |
| M-09 | App Group | entitlement 済みの同一 Team ID 別アプリ間で読み書きできる |
| M-10 | `UIPasteControl` | コンテナ 1 つを配置するだけで表示・貼り付けできる。`acceptedTypes` 未設定時の挙動も確認 |
| M-11 | `UIPasteControl` | 画像のみのクリップボードでも動作する |
| M-12 | 一時ファイル | 強制終了後の再起動で 24 時間経過分が cleanup され、アクティブセッションが消えない |
| M-13 | 画像コスト | `imageData` 経路と `image` 経路のエンコード時間・ピークメモリを Instruments で比較し、`maxImagePixelCount` の妥当性を確認 |
| M-14 | 変更監視 | 通知経路で報告済みの変更が foreground 復帰時に二重報告されない |
| M-15 | ログ | コピー / ペースト値、request JSON、パスがログに出ていない |

---

## 実装タスク分解（依存関係付き）

| ID | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| **T-R** | **`common.md` の Domain 依存ルール改訂**（案 A 採用時）または案 B の採用決定 | 0.5日 | なし | Domain の `Foundation` 依存の可否が確定し、ルール文言が更新されている | 既存 Share との整合、UI 型を除外する境界の明記 |
| **T-00** | **プライバシー実機スパイク**（M-01〜M-05、M-16） | 1.5日 | なし | `changeCount` / `itemProviders` getter / `canLoadObject` の通知有無、**append の option 継承有無**が iOS 18 / iOS 26 で判明 | D-3 / D-8 / R-01 / R-02 / R-13 の判断材料が揃っているか |
| T-01 | Domain 層（モデル 17 種 + `ClipboardError` 24 ケース + `errorCode`） | 1.5日 | T-R, T-00 | U-01〜U-05 が green。`UIKit` を import していない | Domain 純粋性、エラー件数の単一情報源、`DDMatch*` 対応フィールド |
| T-02 | 純ロジック（`ContentValidator` / `ChangeTracker`）+ 秘匿ログ 3 種 | 1日 | T-01 | U-06〜U-22、U-113〜U-115 が green | Clock 注入、`@objc` facade の公開範囲 |
| T-03 | Port 4 種（actor 宣言）+ UseCase 11 種 + 集約 + Mock 4 種 | 2日 | T-02 | U-23〜U-49 が green。Port と実装の isolation が一致 | `DetectValuesUseCase` の存在、UTI 検証 Port の注入、タイムアウトの起算点 |
| T-04 | `PasteboardResolver` / `TypeIdentifierValidator` / `Mappers` / `DetectionMapper` / `ClipboardRepositoryImpl` | 2日 | T-03 | U-50〜U-65 が green。`setValue` 不使用 | UIKit 依存の閉じ込め、`DDMatch*` 変換の網羅、`matchingItemIndexes` |
| T-05 | `TemporaryFileStore` / `ImageCoder` / `CancellationBox` | 1.5日 | T-01 | U-66〜U-79 が green | path traversal、cleanup 範囲、background 実行、`Sendable` 要件 |
| T-06 | `ClipboardItemLoaderImpl`（契約 6 点 + token + タイムアウト + 単一 gate） | 2日 | T-05, T-03 | 全経路で completion が main から 1 回。3 者競合が解決される | exactly-once、`Progress` 蓄積なし、URL ロード、サイズ上限 |
| T-07 | `IosClipboardManager`（`@MainActor`、P-1〜P-16、監視トークン所有、Task キャンセル転送） | 2日 | T-04, T-06 | U-97〜U-112 が green。監視トークンが Manager 以外に存在しない | actor 境界、同期 control API、continuation の 1 回 resume |
| T-08 | Presentation（`PasteItemProviderLoader` → `ReceiverView` → `ContainerView` → `Factory`） | 2日 | T-06 | U-80〜U-96 が green | 集約契約 5 パターン、キャンセル時の UI 非配信、receiver の保持と responder chain |
| T-09 | `UnityIosClipboardJsonParser`（15 endpoint の完全 schema） | 2日 | T-01 | U-116〜U-127 が green | 全 union の必須 / 任意 / nullable、未知 kind、秘匿ログ |
| T-10 | `UnityIosClipboardManager` + Bridge `.h` / `.m`（errorCode 透過 + generic runner + observe 開始 callback） | 1.5日 | T-09, T-07 | U-128〜U-131 が green。ブロック引数が `BOOL` | Bridge の薄さ、C 文字列寿命、NULL callback、HeaderDoc |
| T-11a | ライブラリ統合テスト I-01〜I-07 | 1日 | T-07, T-08 | 全て green | `.unique` 使用で general を汚染しないか |
| T-11b | Bridge 統合テスト I-08、I-09、および **I-10（両モジュールの strict build）** | 1日 | T-10, T-11a | 全て green | モジュール境界、strict concurrency |
| T-12 | サンプルアプリ対応（詳細は `design-sample-app`） | - | T-07, T-08 | S1〜S11 の全サブ機能を `IosLibraryExample` から操作でき、`IosLibrary` のみに依存する | Unity プラグイン非依存 |
| T-13 | 手動確認 M-06〜M-15 を実施し結果を記録 | 1日 | T-12 | 企画書テスト行列の観測欄が iOS 18 / iOS 26 で埋まる | 断定せず観測値を記載しているか |
| T-14 | DocC（`IosLibrary.md`）に Clipboard セクションを追記 | 0.5日 | T-10, T-08, T-12 | 全公開 API 確定後に記述 | 誤用を招く記述がないか |

**先行タスク（基盤）**: T-R / T-00 〜 T-07
**後続タスク（拡張）**: T-08 〜 T-14

```
T-R ┐
T-00┴→ T-01 → T-02 → T-03 → T-04 ┐
         ├──→ T-05 → T-06 ───────┴→ T-07 ┬→ T-11a ┐
         └──→ T-09 → T-10 ───────────────┘         ├→ T-11b
                          T-06 → T-08 ─────────────┘
                                  T-07/T-08 → T-12 → T-13
                          T-10 + T-08 + T-12 → T-14
```

v2 からの変更: T-11b が I-10（`UnityIosPlugin` の strict build）を担当するよう修正した（v2 は T-10 に依存しない T-11a が Bridge のビルドを完了条件に含んでいた）。

---

## リスクと緩和策

| # | リスク | 影響 | 緩和策 | 状態 |
|---|---|---|---|---|
| R-01 | `changeCount` が通知・プロンプト対象 | S9 の foreground 検知が不成立 | T-00 で実装前に判明させる。対象なら `changedNotification` のみに縮退 | T-00 で確定 |
| R-02 | `itemProviders` getter がプロンプト契機 | 事前判定の意味が薄れる | T-00（M-05）で切り分け | T-00 で確定 |
| R-03 | Swift 6 strict concurrency のエラー | 移行困難 | actor 境界を宣言単位で確定（D-9）、`ClipboardCancellationBox` で `@Sendable` 境界を橋渡し（D-10）。I-10 で両モジュール検証 | 緩和済み |
| R-04 | 実 `UIPasteboard` テストが CI で不安定 | 信頼性低下 | `withUniqueName()` を使い general を触らない | 緩和済み |
| R-05 | `UIPasteControl` が Unity から使えない | Unity 利用者はプロンプト回避不可 | D-1 として明示しドキュメント化 | 受容 |
| R-06 | 一時ファイルが強制終了時に残る | ストレージ圧迫 | プロセス 1 回 + 24 時間 + 他セッション限定（D-7）。U-71 / U-72 / M-12 | 緩和済み |
| R-07 | ログからの情報漏洩 | 機微情報露出 | `ClipboardRedaction` に統一し、モジュール境界を I-09 で検証。U-113〜U-115 / U-131 / M-15 | 緩和済み |
| R-08 | `localOnly` 既定 `true` が Android と挙動差 | 体感差 | マニュアルで iOS 固有オプションとして説明 | 受容 |
| R-09 | 画像再エンコードの性能低下 | ペースト遅延 | background executor + `maxImagePixelCount` + `imageCoding` タイムアウト。M-13 で計測 | 緩和済み |
| R-10 | `cancelled` の扱いが Share と異なる | 利用者の混乱 | エラーコード表・DocC・Bridge ヘッダ・サンプルの 4 箇所で明記 | 緩和済み |
| R-11 | Domain の `Foundation` 依存が `common.md` と不整合 | ルール逸脱 | **未合意。T-R で決着させてから T-01 を開始する** | **要判断（ブロッカー）** |
| R-12 | Bridge endpoint 15 と JSON schema の保守コスト | 仕様ドリフト | U-124〜U-127 で全 schema をテスト固定 | 緩和済み |
| R-13 | `append` した item に privacy option が継承されない | 機微データが Universal Clipboard へ流出 | 継承を保証しないと明記し、機微データは `copy` を使うよう DocC で誘導。T-00（M-16）で実測し、必要なら `appendPreservingOptions` の採否を判断 | T-00 で確定 |
| R-14 | `detectedPatterns` / `detectedValues` に中断手段がなく、タイムアウト後も OS 処理が継続する | リソースを一時的に消費する | 配信抑止 + 結果破棄を契約として明示。処理自体の中断は保証しないことを DocC に記載 | 受容（明示済み） |

---

## Definition of Done

### 前提条件

- [ ] R-11（Domain の `Foundation` 依存）が T-R で決着している
- [ ] T-00 の実機スパイクで D-3 / D-8 / R-01 / R-02 / R-13 の判断材料が揃っている

### 実装

- [ ] `ios/IosLibrary/IosLibrary/Clipboard/` に Domain / Application / Data / Presentation / Manager が揃い、依存方向違反がない
- [ ] Application 層 Port の引数・戻り値にプラットフォーム型（`UIPasteboard` / `NSItemProvider` / `UTType` / `UIImage` / `UIColor` / `TimeZone`）が含まれない
- [ ] `NSItemProvider` を扱うコードが Data 層と Presentation 層に閉じている
- [ ] Domain 層が `UIKit` を import していない
- [ ] Domain が system `Error` を保持せず `ClipboardFailureDetail` へ正規化されている
- [ ] 公開エラーメッセージが case ごとの固定英語文で、`localizedDescription` を含まない
- [ ] Port と実装の actor isolation が宣言単位で一致している
- [ ] **Data 層アクセスを伴う P-1〜P-11 に 11 個の UseCase が存在**し、Manager が Repository を直接呼んでいない
- [ ] **P-12〜P-16 が UseCase を持たない理由**（Data 層に触れない同期 control API）が設計どおりである
- [ ] `IosClipboardManager` が `@MainActor` で、P-1〜P-11 は callback + `async throws` を提供する
- [ ] callback 版のエラーが `(errorCode, errorMessage)` の 2 値で返る
- [ ] 非同期 API（P-9〜P-11、P-16）にタイムアウト値・起算点・所有者・超過時の挙動が実装されている
- [ ] copy / load / image にサイズ上限が実装され、超過時に `contentTooLarge` を返す
- [ ] キャンセル / 完了 / タイムアウトが単一 gate で解決され、配信が必ず 1 回である
- [ ] `changedNotification` / `removedNotification` のトークンを `IosClipboardManager` のみが保持する
- [ ] `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/` に Unity Bridge 層のみが存在する
- [ ] Bridge が `ClipboardError.errorCode` を透過し、message 解析やエラー判定ロジックを持たない
- [ ] `ClipboardRedaction` が `UnityIosPlugin` の Swift と `.m` の双方から呼べる
- [ ] 全 public シンボルに DocC コメント（英語）がある
- [ ] 全 `public` / `internal` / `override` / `@objc` 関数と Bridge C 関数の先頭に `Log.d` / `Log.e` がある
- [ ] クリップボード値・request JSON・Base64・パス・URL・system message がログに出力されない
- [ ] Bridge `.m` の完了ブロック引数が `BOOL` / `NSString * _Nullable` である
- [ ] 同期 System API に対応する Repository / UseCase が `async` 化されていない
- [ ] 既存 Notification / Dialog / Share のファイルに変更がない

### 機能

- [ ] S1: 参照用 `PasteboardScope` と作成用 `PasteboardCreationRequest` が型分離され、境界ケース表どおりに動作する
- [ ] S2 / S3: 9 kind と `localOnly` / `expirationDate` が動作する
- [ ] S4: `append` が options を受け取らず、privacy option を保証しない旨が明記されている
- [ ] S5: 同期読み取りと `readData` が動作する
- [ ] S6: text / url / image / file の非同期ロードが契約どおりに動作する
- [ ] S7: `snapshot(matchingTypes:)` が `matchingItemIndexes` を返す
- [ ] S8: クリアと名前付き破棄が動作する
- [ ] S9: 変更 / 破棄イベントと foreground 差分検知が動作し、二重報告がない
- [ ] S10: `detectPatterns` / `detectValues` が動作し、**全 11 パターンの値**がドメイン型で返る
- [ ] S11: コンテナ 1 つの配置で `UIPasteControl` が動作し、集約契約 5 パターンどおりに振る舞う
- [ ] S12: 15 endpoint すべてが JSON schema どおりに動作する

### テスト

- [ ] 単体テスト U-01 〜 U-131 が全て green（Swift Testing、XCTest 不使用）
- [ ] 統合テスト I-01 〜 I-10 が全て green
- [ ] I-10 が両モジュールで `SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` により警告・エラーなし
- [ ] Mock が `shouldFail` / per-method CallCount / `stubbedXxx` パターンに従う
- [ ] 実 `UIPasteboard` を使うテストが `general` を汚染しない
- [ ] `IosLibrary` / `UnityIosPlugin` の全スキームでテストが passed
- [ ] 手動確認 M-01 〜 M-16 を実施し、結果を記録した

### ドキュメント

- [ ] `IosLibrary.docc/IosLibrary.md` に Clipboard セクションがある
- [ ] `IosClipboardManager` が `@MainActor` であり、非 main から呼ぶ場合の作法を明記した
- [ ] 名前付きペーストボードが非永続であること、永続共有は App Group shared container の責務であることを明記した
- [ ] `loadItem(.file)` / `onPaste` の `.file` の削除責務が呼び出し側にあることを明記した
- [ ] `read` / `readData` がプロンプト / 通知の対象になりうること、事前判定には `snapshot` を使うことを明記した
- [ ] **`append` が privacy option を受け取らず、継承も保証しないこと、機微データには `copy` を使うこと**を明記した
- [ ] `cancelled` を `isSuccess == false` として返す理由と、S11 の UI コールバックへ伝播しないことを明記した
- [ ] `ClipboardPasteControlContainerView` を 1 つ配置すればよいこと、`PasteControlFactory.makeComponents` を使う場合は保持責務が呼び出し側にあることを明記した
- [ ] `detectPatterns` / `detectValues` のタイムアウト時に OS 処理の中断は保証されないことを明記した
- [ ] `docs/` 配下を変更していない

---

## 要検証事項（設計時点で未確定）

| 項目 | 内容 | 確認タイミング |
|---|---|---|
| Domain の `Foundation` 依存の可否 | `common.md` の改訂（案 A）か Domain 型の変換（案 B）か | **T-R（実装のブロッカー）** |
| `changeCount` の通知非対象性 | 対象なら D-3 と S9 を見直す | T-00（M-03） |
| `itemProviders` getter の契機 | 対象なら S6 の推奨経路を変更 | T-00（M-05） |
| `append` の privacy option 継承 | 継承されない場合、`appendPreservingOptions` の採否を判断（読み直しがプロンプト契機になりうる点も込みで） | T-00（M-16） |
| `DDMatch*` の実プロパティ | 本設計は Apple 公式ドキュメントのプロパティ一覧に基づく。SDK header で最終確認する | T-01 |
| タイムアウト値の妥当性 | 5s / 15s / 10s が実機で過不足ないか | T-11a / T-13 |
| サイズ上限値の妥当性 | 64 MiB / 100 MP が実機で過不足ないか | T-13（M-13） |
| Swift 6 strict concurrency の残存警告 | 残る場合は追加の isolation 調整をタスク化 | T-11b（I-10） |

---

## レビュー反映履歴

対象レビュー: `artifact/reviews/clipboard/2026-08-02-ios-clipboard-design-review-v2.md`

### 第 2 回レビュー反映（v3 / 2026-08-02）

| 優先度 | 指摘 | 反映内容 |
|---|---|---|
| 高 | Manager nonisolated + `@MainActor` token 同期返却 + 同期 control API が Swift 6 で実装不能 | **`IosClipboardManager` を `@MainActor` に変更**（D-9）。任意スレッド受付を `UnityIosClipboardManager`（nonisolated）に限定。Task キャンセル転送に `ClipboardCancellationBox`（`Sendable` / `nonisolated cancel()`）を新設（D-10）。P-12〜P-16 が同期 control API であることを `common.md` 129 行の任意規定に基づき明記し、レイヤー表・API 表・DoD を一致させた。U-102 / U-110 / U-111 / U-77〜U-79 を追加 |
| 高 | 非同期 API の timeout・サイズ上限・実キャンセル契約が無い | `ClipboardTimeouts`（detection 5s / providerLoad 15s / imageCoding 10s）と `ClipboardLimits`（64 MiB / 64 MiB / 100 MP）を新設（L-5 / L-6）。起算点・所有者・超過時挙動・3 者競合 gate をレイヤー表と S6 に明記。`timedOut(operation:)` / `contentTooLarge(byteCount:limit:)` を追加。**P-9 / P-10 の「Task キャンセルで中断」を「配信抑止のみ・OS 中断は保証しない」へ訂正**。U-43 / U-46 / U-48 / U-75 / U-76 / U-85 / U-111 / I-07 を追加 |
| 高 | `DetectValuesUseCase` 欠落と `DetectedValues` の値フィールド 5 種欠落 | `DetectValuesUseCase` を独立追加。`ClipboardPostalAddress` / `ClipboardCalendarEvent` / `ClipboardFlightNumber` / `ClipboardMoneyAmount` / `ClipboardShipmentTracking` / `ClipboardLabeledValue` を Apple 公式の `DDMatch*` プロパティに合わせて定義。`ClipboardDetectionMapper`、JSON schema（全 11 項目）、U-44〜U-46 / U-63〜U-65 / U-125、T-03 / T-04 を追加 |
| 高 | JSON schema が `{...}` のまま。observe 開始失敗経路・値返却 runner・C 文字列寿命が未定義 | 9 content kind / scope 3 kind / loadRequest / loadedItem / patterns / detectedValues を required・optional・nullable まで表で定義。`clipboardStartObserving` に **開始結果用 operation callback** を追加。`runVoid` / `runValue` の generic runner を明示。C 文字列の寿命・NULL callback・スレッドの規約表を追加。U-116〜U-130 を追加 |
| 高 | `ClipboardLog` が `internal` かつ Swift enum で、別モジュール / ObjC から呼べない | `ClipboardRedactionCore`（internal 実装）/ `ClipboardRedaction`（`@objc public` facade）/ `ClipboardLog`（internal ラッパー）の 3 層に分離。`.m` からは `[ClipboardRedaction json:]` で呼ぶ。U-113 / U-114 と **モジュール境界ビルドテスト I-09** を追加 |
| 高 | `PasteControlFactory` と Manager API が不整合で receiver の寿命・responder chain 参加を保証できない | **`ClipboardPasteControlContainerView`**（control と receiver を強保持し receiver を subview にする公開コンテナ）を新設し、Manager が返す型に変更。`makeComponents` を使う場合の保持責務も明記。U-93〜U-96 を追加 |
| 高 | append の「privacy 設定が残る」という断定に根拠がない | 断定を撤回。**継承を保証しない**と明記し、機微データには `copy` を使うよう誘導。T-00 に実機観測 **M-16** を追加。代替 API `appendPreservingOptions` の採否を R-13 として T-00 後に判断 |
| 中 | `itemSet(withPasteboardTypes:)` の利用箇所が無い | `snapshot(matchingTypes:scope:)` の引数として採用し、`ClipboardSnapshot.matchingItemIndexes` を追加（D-11）。U-34 / U-35 / U-56、Bridge schema を追加 |
| 中 | S11 の cancel 契約が S6 と不整合 | **内部 completion は exactly-once（`.cancelled` 含む）、UI コールバックはキャンセル時に呼ばない**と定義（D-4）。E-21 の発生元を「内部 completion」と明記。U-84 / U-90 を追加 |
| 中 | `readData` の UTI 検証責務が Data 層記述と U-26 で矛盾 | `ClipboardTypeIdentifierValidating` Port を Application に新設し、実装を Data 層に置いて注入（D-12）。UseCase が事前検証しつつ `UTType` を Application へ持ち込まない。U-25 / U-31 と縦断表を一致させた |
| 中 | 「全 16 操作に UseCase」「Foundation 依存は合意済み」が不正確 | **Data 層アクセスを伴う P-1〜P-11 の 11 UseCase**と訂正し、P-12〜P-16 が UseCase を持たない理由を明記。Foundation 依存を「未合意（要判断）」へ訂正し、案 A / 案 B と**先行タスク T-R** を追加。R-11 をブロッカーとして DoD の前提条件に入れた |
| 中 | `localizedDescription` の保持と「決定的」の主張が両立しない | 公開メッセージを case ごとの**固定英語文**に変更（D-13）。`ClipboardFailureDetail.debugMessage` を `internal` にして公開もログもしない。U-02 / U-115 を追加 |
| 中 | `expirationDate` の Clock 未注入、T-11a の依存不足 | `ClipboardClock` Port を追加し Validator に注入（U-15 / U-16 が決定的に）。**I-10 の Bridge strict build を T-11b へ移動**し、T-11a を IosLibrary 限定にした |
| 低 | P-4 のテスト ID 参照が実表と不一致、ログテスト ID の誤り | P-4 の参照を U-30〜U-32 / U-52 / U-86 / U-110 相当へ修正し、全 ID を通し番号（U-01〜U-131 / I-01〜I-10 / M-01〜M-16）で再採番して機械的に照合した |
| 低 | エラー件数の揺れ（14 / 15）と `unknownCode` の未定義 | エラーを 24 ケースに確定し、対応表 24 行 = 共通 4 + iOS 固有 20 として件数を単一情報源から算出。`ClipboardError.unknownErrorCode` / `unknownMessage` を `public static let` として正式に定義（U-03 で検証） |
