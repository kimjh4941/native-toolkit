# iOS クリップボード機能 実装設計書 v2

- 作成日: 2026-08-02
- 改訂日: 2026-08-02（v2: 第 1 回レビュー指摘を反映）
- 前版: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design.md`
- 最新版: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v3.md`（第 2 回レビュー反映済み。以降はこちらを参照する）
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
| 主要リスク | iOS 14 アクセス通知 / iOS 16 許可プロンプト、Universal Clipboard 流出、名前付きペーストボードの非永続、`NSItemProvider` の完了スレッド・キャンセル契約・一時ファイル寿命、キーパス API が Swift 専用 |

### 企画書の不足前提（本設計で補った事項）

企画書 v4 には次が存在しないため、本設計で補完する。企画書由来の前提と区別するため明示する。

| # | 企画書に無い前提 | 本設計での補完 |
|---|---|---|
| L-1 | **同期・非同期 API 分類表** | 「採用 System API の実行方式分類」（後述）を新設し、各 API を `sync` / `callback` / `async` / `stream` に分類した |
| L-2 | **層をまたぐ実行方式の対応関係** | 「同期・非同期レイヤー対応表」（後述）を新設し、P-1〜P-16 について System API から Bridge までの実行方式・actor・キャンセル・所有権を縦断定義した |
| L-3 | 画像デコード / エンコードを実行するスレッドの具体指定 | 「メインスレッド外で行う」という方針のみのため、本設計で background executor を明示した（S5） |
| L-4 | `NSItemProvider` の URL ロード契約 | 企画書は標準型に URL を含むが読み取り契約が無いため、`ClipboardLoadRequest.url` として定義した（S5） |

### 本設計での判断（新規設計判断）

| # | 未確定事項 | 本設計での判断 | 理由 |
|---|---|---|---|
| D-1 | `UIPasteControl` を公開 API とするか | ネイティブライブラリでは提供。**Unity Bridge では提供しない** | `UIView` は C ABI を越えられない。ネイティブ利用者には許可プロンプト回避経路が必須 |
| D-2 | パターン検出結果の公開範囲 | ドメイン型へ変換。`PartialKeyPath` / `DDMatch*` を露出しない | 企画書リスク「キーパス API が Swift 専用」 |
| D-3 | `contains` / `changeCount` の採否 | `changeCount` は採用、`contains(pasteboardTypes:)` は内部利用のみ | 代替のない前者のみ要検証つきで採用 |
| D-4 | 複数 provider の集約仕様 | 順序保持・部分失敗継続・コールバック回数を確定（S10） | v1 で未定義だったため |
| D-5 | HTML の扱い | 1 アイテム複数表現型で実装 | Android の `CopyHtmlTextUseCase` とのパリティ |
| D-6 | 名前付きペーストボードの公開範囲 | 参照用 `PasteboardScope` と作成用 `PasteboardCreationRequest` を型分離 | v1 は `.unique(String)` を作成要求にも使い矛盾していた |
| D-7 | 一時ファイル cleanup | プロセス単位 1 回 + セッションディレクトリ + 経過時間ベース | v1 の「Manager 初期化ごとに全削除」は他インスタンスの成功ファイルを消しうる |
| D-8 | append と privacy option の関係 | **append を独立 API に分離**し、privacy option を受け取らない | `addItems` はオプションを適用できず、既定 `localOnly: true` を黙って無視する契約になっていた |
| D-9 | 全層の actor 境界 | Repository / Loader / UseCase / Presentation を `@MainActor`、Manager を nonisolated、画像変換のみ background | Swift 6 で protocol requirement と実装の isolation 不一致がコンパイルエラーになるため |

---

## 設計目的

- 企画書で網羅した `UIPasteboard` API を Clean Architecture の層構成に沿って `IosLibrary` へ実装する
- ネイティブ呼び出し元（`IosLibraryExample`）と Unity 呼び出し元の双方から同一の機能範囲を利用できるようにする（`UIPasteControl` を除く）
- System API の実行方式を各層で不必要に変換せず、変換箇所を Manager と Bridge に限定する
- OS 依存のプライバシー挙動を隠蔽せず、呼び出し元が経路を選べる API とする

---

## スコープ（in / out）

### In scope

| サブ機能 | 内容 |
|---|---|
| S1 ペーストボード解決 | `general` / 名前付き / ユニーク名の参照・作成・破棄 |
| S2 コピー | plainText / htmlText / url / imageFile / imageData / color / customData / multipleText / multiRepresentation |
| S3 コピーオプション | `localOnly` / `expirationDate`（置換コピーのみ） |
| S4 追記（append） | 既存内容へアイテム追加（privacy option なし） |
| S5 ペースト（同期） | text / urls / image / color / 任意 UTI `Data` / 全アイテムのメタ情報 |
| S6 ペースト（`NSItemProvider` 非同期） | text / url / image / file の非同期ロード、キャンセル、エラー分類 |
| S7 内容確認 | `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `numberOfItems` / `types` / `itemSet` |
| S8 クリア | `items = []`、名前付きの `remove(withName:)` |
| S9 変更監視 | `changedNotification` / `removedNotification` / `changeCount` 差分 |
| S10 パターン検出 | `detectedPatterns` / `detectedValues`（キーパス版のみ） |
| S11 貼り付け UI | `UIPasteControl` ファクトリと受信 View（ネイティブのみ） |
| S12 Unity Bridge | S1〜S10 の JSON ベース公開（S11 を除く） |

### Out of scope

- 企画書の Out of scope 全項目
- App Group shared container のファイル入出力（責務境界のドキュメント記載のみ）
- `contains(pasteboardTypes:)` の公開 API 化（内部限定。D-3）
- `loadTransferable` / `loadInPlaceFileRepresentation` / `loadItem`（非推奨）
- `docs/` 配下の変更（固定で対象外）

---

## 採用 System API の実行方式分類（L-1）

Repository / UseCase / private helper は **System API の実行方式をそのまま維持する**。方式変換は Manager（呼び出し規約への適合）と Bridge（C ABI への適合）でのみ行う。これにより不要な `async` 化・actor hop・callback の二重変換を防ぐ。

| 分類 | System API | 実行方式 | 下位層で採る形 |
|---|---|---|---|
| sync | `UIPasteboard.general` / `init(name:create:)` / `withUniqueName()` / `remove(withName:)` | 同期・throw なし | 同期関数（`throws` はドメイン検証由来のみ） |
| sync | `setItems(_:options:)` / `addItems(_:)` / `items` | 同期 | 同期関数 |
| sync | `string` / `urls` / `image` / `color` / `data(forPasteboardType:)` / `values(forPasteboardType:inItemSet:)` | 同期 | 同期関数 |
| sync | `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `numberOfItems` / `types` / `types(forItemSet:)` / `itemSet(withPasteboardTypes:)` | 同期 | 同期関数 |
| sync | `changeCount` | 同期 | 同期関数 |
| async | `detectedPatterns(for:)` / `detectedValues(for:)` | `async throws` | `async throws` 関数 |
| callback | `NSItemProvider.loadObject` / `loadDataRepresentation` / `loadFileRepresentation` | completion + `Progress`（完了スレッド不定） | completion + token（`async` 化しない） |
| stream | `UIPasteboard.changedNotification` / `removedNotification` | `NotificationCenter` イベント | 購読 start/stop は同期、イベント配信は非同期 |
| UI callback | `UIPasteControl` → `paste(itemProviders:)` | UIKit responder コールバック | Presentation 内で完結し、Application 層へは流さない |

補足: `UIPasteboard` の同期 API は UIKit の慣例に従い main actor 上で呼ぶ（D-9）。同期であることと actor 隔離は別問題であり、隔離のために `async` にはしない。

---

## 同期・非同期レイヤー対応表（L-2）

全公開 API について、System API から Bridge までの実行方式・actor・キャンセル・リソース所有権を縦断定義する。

凡例: `S` = 同期、`A` = `async throws`、`C` = completion コールバック、`E` = イベント配信、`-` = 該当なし。

| # | 操作 | System API と実行方式 | Repository / Loader | UseCase | Manager callback | Manager native | Bridge | actor / thread | キャンセル | リソース所有権 | 方式変換の理由 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| P-1 | `copy` | `setItems(_:options:)` = sync | S `throws` | S `throws` | C `(Bool, String?, String?)` | A | `clipboardCopy` | `@MainActor`（Manager が hop） | 不可（即時完了） | なし | Bridge が C ABI で throw を扱えないため Manager で C 化 |
| P-2 | `append` | `addItems(_:)` = sync | S `throws` | S `throws` | C | A | `clipboardAppend` | 同上 | 不可 | なし | 同上 |
| P-3 | `read` | `items` = sync | S `throws` | S `throws` | C `(json?, ...)` | A | `clipboardRead` | 同上 | 不可 | なし | 同上 |
| P-4 | `readData` | `data(forPasteboardType:)` = sync | S `throws` | S `throws` | C | A | `clipboardReadData` | 同上 | 不可 | 返却 `Data` は呼び出し側 | Bridge は Base64 文字列へ変換 |
| P-5 | `snapshot` | `has*` / `types` 等 = sync | S | S | C | A | `clipboardGetSnapshot` | 同上 | 不可 | なし | 同上 |
| P-6 | `clear` | `items = []` = sync | S `throws` | S `throws` | C | A | `clipboardClear` | 同上 | 不可 | なし | 同上 |
| P-7 | `createPasteboard` | `init(name:create:)` / `withUniqueName()` = sync | S `throws` | S `throws` | C | A | `clipboardCreatePasteboard` | 同上 | 不可 | 生成 pasteboard は呼び出し側（`remove` 責務） | 同上 |
| P-8 | `removePasteboard` | `remove(withName:)` = sync | S `throws` | S `throws` | C | A | `clipboardRemovePasteboard` | 同上 | 不可 | なし | 同上 |
| P-9 | `detectPatterns` | `detectedPatterns(for:)` = async | A | A | C | A | `clipboardDetectPatterns` | `@MainActor`（await 中は解放） | `Task` キャンセルで中断 | なし | System が async のため下位層も async を維持 |
| P-10 | `detectValues` | `detectedValues(for:)` = async | A | A | C | A | `clipboardDetectValues` | 同上 | 同上 | なし | 同上 |
| P-11 | `loadItem` | `loadObject` 等 = callback + `Progress` | C + token | C + token | C + token | A（`withTaskCancellationHandler` で token を cancel） | `clipboardLoadItem` | Loader は `@MainActor`。画像変換のみ background（L-3） | token / `cancelAllLoads()` / `deinit` | `.file` 成功時のみ URL とその親ディレクトリが呼び出し側所有 | System が callback のため `async` 化せず維持。Manager native のみ薄く async ラップ |
| P-12 | `cancelAllLoads` | - | S | - | S | S | `clipboardCancelLoads` | `@MainActor` | - | 未配信の一時ディレクトリは Loader が削除 | - |
| P-13 | `startObserving` | `addObserver` = sync、通知 = stream | S（Manager が直接所有） | - | S（登録） + E（配信） | S | `clipboardStartObserving` | 登録・配信とも `@MainActor` | `stopObserving` | なし | 購読開始は同期、配信のみ非同期 |
| P-14 | `stopObserving` | `removeObserver` = sync | S | - | S | S | `clipboardStopObserving` | `@MainActor` | - | なし | - |
| P-15 | `checkForegroundChange` | `changeCount` = sync | S | S（`ClipboardChangeTracker`） | S（`Bool` 返却） | S | `clipboardCheckForegroundChange` | `@MainActor` | 不可 | なし | 同期で完結するため callback 化しない |
| P-16 | `makePasteControl` | `UIPasteControl` 生成 = sync、貼り付け = UI callback | Presentation 内 `PasteItemProviderLoader`（C + token） | - | S（生成） + C（貼り付け結果） | S | **非公開** | `@MainActor` | View の `deinit` / 次回 paste 開始時 | `.file` 成功時のみ呼び出し側所有。未配信分は Presentation が削除 | UIKit 型のため Bridge 非公開（D-1） |

### 方式維持の原則（実装規約）

1. **同期 System API を下位層で `async` にしない。** `snapshot` / `read` / `copy` などは Repository も UseCase も同期 `throws`。Manager だけが `async throws` の薄いラッパーと callback ラッパーを持つ。
2. **callback System API を下位層で `async` にしない。** `NSItemProvider` のロードは Port も UseCase も completion + token を維持する。`async` 化するのは Manager native 版のみで、`withTaskCancellationHandler` により Task キャンセルを token へ転送する。
3. **async System API を下位層で callback にしない。** パターン検出は Port も UseCase も `async throws`。
4. **イベント配信は Manager が唯一の発生源。** 購読開始・停止は同期、配信は `@MainActor` 上の非同期。
5. **actor hop は Manager と Bridge に限定する。** UseCase / Repository 内で `DispatchQueue` へ切り替えない（例外は画像変換の background executor のみで、変換後に必ず main へ戻す）。

---

## 共通実装方針の適用チェック（common.md 準拠）

| 方針 | 適用 | 対応 |
|---|---|---|
| Clean Architecture の層と依存方向 | 適合 | Domain → Application → Data / Presentation → Manager → Unity Bridge |
| 層とモジュールの対応（Manager までネイティブライブラリ） | 適合 | Domain 〜 Manager を `ios/IosLibrary`、`ios/UnityIosPlugin` は Unity Bridge のみ |
| Port はドメイン型のみ | 適合 | Application 層 Port の引数・戻り値は全てドメイン型。`NSItemProvider` を扱う loader は **Presentation 層に閉じ込め**、Port には出さない（S11） |
| Manager は UseCase 経由で Data にアクセス | 適合 | 全 16 操作に対応する UseCase を用意し、Repository 直呼びをなくした（v1 で `readData` が欠落していた） |
| system Delegate / Listener の所有は Manager 層の 1 クラス | 適合 | `NotificationCenter` トークンは `IosClipboardManager` のみが保持 |
| Manager は callback 版 + `async throws` 版を併設 | 適合 | 全操作で両方を用意 |
| エラー変換の流れ | 適合 | システムエラー → Repository で `ClipboardError` へ正規化 → Manager で `(Bool, errorCode, errorMessage)` → Bridge |
| TDD / Mock パターン | 適合 | `shouldFail` / per-method CallCount / `stubbedXxx` |
| Swift Testing（XCTest 不使用） | 適合 | 既存 `IosLibraryTests` と同形式 |
| Unity Bridge は薄く保つ | 適合 | Bridge は JSON 変換と Manager 呼び出しのみ。エラー変換は Manager 側の `errorCode` を透過 |
| サンプルアプリはネイティブライブラリのみに依存 | 適合 | `IosLibraryExample` は `IosLibrary` のみ import |
| 最小 OS バージョン iOS 18 | 適合 | 使用 API は全て iOS 16 以前の導入 |

### common.md「Domain は標準ライブラリのみ」の例外（要合意）

本設計の Domain 層は `Foundation` の `Data` / `Date` / `URL` を使用する。common.md は「純粋モデル・エラー型（プラットフォーム依存なし、標準ライブラリのみ）」としており、厳密には逸脱となるため、例外として理由を明記する。

- 既存の `Share/Domain/Model/ShareContent.swift` / `ShareError.swift` も `import Foundation` している（リポジトリの確立された慣例）
- `Data` / `Date` / `URL` は Swift の実質的な標準型であり、`UIKit` のようなプラットフォーム UI 依存ではない
- byte 配列 / epoch 秒 / パス文字列へ置き換えると、Data 層との変換コードが増えるだけで移植性は向上しない

**ただし `UIKit` 型（`UIImage` / `UIColor` / `UIPasteboard` / `NSItemProvider` / `UTType`）は Domain に持ち込まない**。この境界は厳守する。

### underlying error の正規化（レビュー指摘対応）

v1 は `providerLoadFailed(Error)` のように system error をそのまま Domain へ保持していた。v2 では **Repository / Loader が安定した値へ正規化してから** Domain エラーへ載せる。

```swift
public struct ClipboardFailureDetail: Equatable, Sendable {
    public let domain: String    // 例: NSItemProvider.errorDomain
    public let code: Int         // 例: NSItemProvider.ErrorCode.itemUnavailableError.rawValue
    public let message: String   // localizedDescription を英語で正規化した文字列
}
```

これにより Domain が任意の `Error` を抱えなくなり、Bridge の JSON 化も決定的になる。

---

## 個別実装方針の適用チェック（ios.md 準拠）

| 方針 | 適用 | 対応 |
|---|---|---|
| 全メソッド先頭に全パラメータの `Log.d` / `Log.e` | 適合 | `private let TAG = "<FullClassName>"` を各クラス先頭に置く |
| クリップボード値のログ秘匿 | **追加ルール**（下記） | 専用 logger 経由で値を出さない |
| ObjC ブロック引数型（`BOOL` / `NSInteger` / `NSString * _Nullable`） | 適合 | Bridge `.m` の完了ブロックは `BOOL` |
| Manager は callback 版 + `async throws` 版 | 適合 | 全 16 操作 |
| private helper を一律 `async` にしない | 適合 | 「方式維持の原則」として明文化 |
| UI 更新は main へ戻す | 適合 | callback は全経路で main actor から 1 回 |
| DocC コメント（public 必須、英語） | 適合 | 全 public 型・関数 |
| ユーザー向け文言は英語 | 適合 | `errorDescription` は英語 |

### 追加ルール: ログ秘匿（レビュー指摘対応）

クリップボードは機微情報を含みうるため、**値そのものをログに出さない**。v1 は方針のみだったため、v2 では実装手段と検査手順を定める。

**専用ロガー**（`Clipboard/Common/ClipboardLog.swift`、internal）

```swift
enum ClipboardLog {
    /// Redacts a value to "<kind:length>" form. Never logs the value itself.
    static func redact(_ text: String) -> String        // "<text:12>"
    static func redact(_ data: Data) -> String          // "<data:2048>"
    static func redact(json: String) -> String          // "<json:340>"
    static func redact(path: String) -> String          // "<path:ext=png,len=48>"
    static func describe(_ error: ClipboardFailureDetail) -> String  // domain+code のみ
}
```

**秘匿対象**: コピー / ペーストの値本体、Bridge の request JSON 全文、Base64 文字列、ファイルパスとファイル名、URL 文字列、underlying error の message（domain + code のみ出す）。

**非秘匿（出してよい）**: 種別（kind）、長さ、件数、UTI、`PasteboardScope` の種別、`localOnly`、`errorCode`。

**既存 Share Bridge との差**: `UnityIosShareManager` は `contentJson` を全文ログ出力しているが、Clipboard ではこれを踏襲しない。Bridge C 関数でも `ClipboardLog.redact(json:)` を通す。

**検査**: T-09 / T-10 に静的レビュー手順を含め、U-58 で「禁止値がログ文字列に含まれない」ことを自動検証する。

---

## 既存実装差分サマリー

### 破壊的変更

**なし。** 既存 Notification / Dialog / Share のファイルは変更しない。追加のみ。

### Xcode プロジェクト設定

3 つの `.xcodeproj` はいずれも `PBXFileSystemSynchronizedRootGroup` を採用しているため、ファイル追加時に `project.pbxproj` の編集は不要。

Swift 6 strict concurrency の検証は、既存ターゲット設定（`SWIFT_VERSION = 5.0`）を変更せず、**CI / ローカルで一時的にフラグを上書きして実行する**（T-11a）。

```
xcodebuild build -project ios/IosLibrary/IosLibrary.xcodeproj -scheme IosLibrary \
  SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete
```

### 追加ファイル一覧

`ios/IosLibrary/IosLibrary/Clipboard/` 配下:

| パス | 層 | 役割 |
|---|---|---|
| `Common/ClipboardLog.swift` | Common | ログ秘匿ヘルパー |
| `Domain/Model/PasteboardScope.swift` | Domain | 参照用スコープ |
| `Domain/Model/PasteboardCreationRequest.swift` | Domain | 作成要求（D-6 で分離） |
| `Domain/Model/ClipboardContent.swift` | Domain | コピー内容 |
| `Domain/Model/ClipboardCopyOptions.swift` | Domain | `localOnly` / `expirationDate` |
| `Domain/Model/ClipboardItemData.swift` | Domain | 1 アイテムの表現 |
| `Domain/Model/ClipboardReadResult.swift` | Domain | 読み取り結果 |
| `Domain/Model/ClipboardSnapshot.swift` | Domain | 内容確認 |
| `Domain/Model/ClipboardChangeEvent.swift` | Domain | 変更 / 破棄イベント |
| `Domain/Model/ClipboardDetectedValues.swift` | Domain | パターン検出結果 |
| `Domain/Model/ClipboardLoadRequest.swift` | Domain | ロード要求（text/url/image/file） |
| `Domain/Model/ClipboardLoadedItem.swift` | Domain | ロード結果 |
| `Domain/Model/ClipboardFailureDetail.swift` | Domain | 正規化済み system error |
| `Domain/Model/ClipboardError.swift` | Domain | ドメインエラー（`errorCode` を保持） |
| `Application/Port/ClipboardRepository.swift` | Application | 同期 + async 操作 Port |
| `Application/Port/ClipboardItemLoader.swift` | Application | callback + token Port |
| `Application/UseCase/CopyContentUseCase.swift` | Application | コピー |
| `Application/UseCase/AppendContentUseCase.swift` | Application | 追記（D-8） |
| `Application/UseCase/ReadContentUseCase.swift` | Application | 同期読み取り |
| `Application/UseCase/ReadDataUseCase.swift` | Application | 任意 UTI の `Data` 取得（v1 欠落分） |
| `Application/UseCase/GetSnapshotUseCase.swift` | Application | 内容確認 |
| `Application/UseCase/ClearClipboardUseCase.swift` | Application | クリア |
| `Application/UseCase/CreatePasteboardUseCase.swift` | Application | 作成 |
| `Application/UseCase/RemovePasteboardUseCase.swift` | Application | 破棄 |
| `Application/UseCase/DetectPatternsUseCase.swift` | Application | パターン検出（有無 / 値） |
| `Application/UseCase/LoadItemUseCase.swift` | Application | provider 非同期ロード |
| `Application/UseCase/ClipboardChangeTracker.swift` | Application | `changeCount` 同期規則（純ロジック） |
| `Application/UseCase/ClipboardContentValidator.swift` | Application | 純粋検証（Data 非依存） |
| `Application/UseCase/ClipboardUseCases.swift` | Application | UseCase 集約 |
| `Data/Repository/ClipboardRepositoryImpl.swift` | Data | `UIPasteboard` 実装 |
| `Data/Repository/ClipboardItemLoaderImpl.swift` | Data | `NSItemProvider` 実装 |
| `Data/Repository/ClipboardMappers.swift` | Data | 型変換 |
| `Data/Repository/PasteboardResolver.swift` | Data | スコープ解決 |
| `Data/Repository/ClipboardTypeIdentifierValidator.swift` | Data | UTI 検証（`UTType` 依存のため Data 層） |
| `Data/File/ClipboardTemporaryFileStore.swift` | Data | 一時ディレクトリ管理・cleanup |
| `Data/Image/ClipboardImageEncoder.swift` | Data | background での画像エンコード（L-3） |
| `Presentation/PasteItemProviderLoader.swift` | Presentation | `[NSItemProvider]` の集約ロード（S11） |
| `Presentation/ClipboardPasteReceiverView.swift` | Presentation | `UIPasteConfigurationSupporting` 実装 |
| `Presentation/PasteControlFactory.swift` | Presentation | `UIPasteControl` 生成 |
| `IosClipboardManager.swift` | Manager | 公開 API・監視トークン所有 |

`ios/UnityIosPlugin/UnityIosPlugin/Clipboard/` 配下:

| パス | 役割 |
|---|---|
| `UnityIosClipboardManager.swift` | Swift facade（singleton） |
| `UnityIosClipboardJsonParser.swift` | JSON パース / シリアライズ |
| `UnityIosClipboardManagerBridge.h` | C ABI 宣言 |
| `UnityIosClipboardManagerBridge.m` | C 関数実装 |

テスト（詳細は「テスト設計」）: `IosLibraryTests/Clipboard/{Domain,Application,Data,Presentation}` および `UnityIosPluginTests/Clipboard/`。

ドキュメント: `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md` に Clipboard セクションを追記。

サンプルアプリ: `design-sample-app` で詳細設計（本設計ではファイルパスを定めない）。

### 既存規約との整合

| 観点 | 既存 | 本設計 |
|---|---|---|
| ディレクトリ構成 | `Share/{Domain,Application,Data,Presentation}` + `IosShareManager.swift` | 同一構成を `Clipboard/` で踏襲 |
| Manager 命名 | `IosShareManager` | `IosClipboardManager` |
| Bridge 命名 | `UnityIosShareManager` + Bridge `.h` / `.m` + JsonParser | 同構成 |
| singleton | `public static let shared` + `private override init()` + test 用 init | 同一 |
| エラーコード | Android の `CLIPBOARD_*` | 共通コードは完全一致、iOS 固有コードのみ追加（差異表を後述） |

---

## 実装アーキテクチャ

```
[Unity C#]
    │ P/Invoke (C ABI)
[UnityIosClipboardManagerBridge.h/.m]              ← ios/UnityIosPlugin
    │  各 C 関数は JSON を渡すだけ
[UnityIosClipboardManager (@objcMembers)]          ← Unity Bridge 層
    │  + UnityIosClipboardJsonParser
    │  Manager の async throws を Task { @MainActor } で呼び、
    │  catch した ClipboardError.errorCode / message を JSON へ変換（変換は 1 箇所）
    ▼
[IosClipboardManager]                              ← Manager 層 / ios/IosLibrary（nonisolated）
    │  - NotificationCenter トークンを単独所有
    │  - callback 版 + async throws 版
    ▼
[ClipboardUseCases]                                ← Application 層（@MainActor）
    │  Copy / Append / Read / ReadData / GetSnapshot / Clear /
    │  CreatePasteboard / RemovePasteboard / DetectPatterns / LoadItem
    │  + ClipboardChangeTracker / ClipboardContentValidator（純ロジック・nonisolated）
    ▼
[ClipboardRepository] [ClipboardItemLoader]        ← Port（@MainActor / ドメイン型のみ）
    ▲                        ▲
[ClipboardRepositoryImpl] [ClipboardItemLoaderImpl]   ← Data 層（@MainActor）
    │  + Mappers / PasteboardResolver / TypeIdentifierValidator
    │  + TemporaryFileStore / ImageEncoder（encoder のみ background）
    ▼
[UIPasteboard] [NSItemProvider] [FileManager]

[PasteControlFactory] → [ClipboardPasteReceiverView] → [PasteItemProviderLoader]
    ← Presentation 層（@MainActor / UIKit）。NSItemProvider はここに閉じ込める
    ▲ IosClipboardManager が生成してネイティブ呼び出し元へ返す（Unity 非公開）
```

### actor 境界（D-9 / レビュー指摘対応）

Swift 6 strict concurrency では、非隔離 protocol requirement を `@MainActor` 実装が満たすと conformance error になる。**Port と実装の isolation を宣言単位で一致させる。**

| 宣言 | isolation | 理由 |
|---|---|---|
| `ClipboardRepository`（protocol） | `@MainActor` | 実装が `UIPasteboard` を触るため |
| `ClipboardRepositoryImpl` | `@MainActor` | Port と一致 |
| `ClipboardItemLoader`（protocol） | `@MainActor` | 実装が管理表を持ち main で配信するため |
| `ClipboardItemLoaderImpl` | `@MainActor` | Port と一致 |
| `ClipboardLoadToken`（protocol） | `@MainActor` | `cancel()` が管理表へ触れるため |
| UseCase 群 | `@MainActor` | Port を呼ぶため |
| `ClipboardChangeTracker` / `ClipboardContentValidator` | `nonisolated`（`struct`） | 純ロジック。どのスレッドからでもテスト可能 |
| `ClipboardImageEncoder` | `nonisolated` + 内部で `Task.detached` | 画像変換を main から外すため（L-3） |
| Presentation（`PasteItemProviderLoader` / `ClipboardPasteReceiverView` / `PasteControlFactory`） | `@MainActor` | UIKit |
| `IosClipboardManager` | **nonisolated**（`final class`） | Unity から任意スレッドで呼ばれる。内部で `Task { @MainActor in }` により hop（既存 `IosShareManager` と同一パターン） |
| `UnityIosClipboardManager` | nonisolated | 同上 |
| Domain 型 | `Sendable`（`nonisolated`） | 値型のみ |

---

## サブ機能別詳細設計

### S1 ペーストボード解決（型分離: D-6）

```swift
/// Reference to an existing pasteboard.
public enum PasteboardScope: Equatable, Sendable {
    case general
    case named(String)     // App Group ID などの共有名（非永続）
    case unique(String)    // withUniqueName() が生成した名前
}

/// Request to create a pasteboard. Separated from `PasteboardScope` because
/// `withUniqueName()` takes no argument and the resulting name is an output.
public enum PasteboardCreationRequest: Equatable, Sendable {
    case named(String)
    case unique
}
```

**境界ケース（v1 未定義分を確定）**

| ケース | 挙動 |
|---|---|
| `createPasteboard(.named(n))` で n が既存 | 既存を返す（`UIPasteboard(name:create:true)` の仕様。エラーにしない） |
| `createPasteboard(.named(""))` / 空白のみ | `invalidPasteboardName` |
| `createPasteboard(.unique)` | `withUniqueName()` の結果を `.unique(生成名)` として返す |
| `createPasteboard` に `.general` を渡す | 型として表現できない（`PasteboardCreationRequest` に `.general` が無い） |
| `removePasteboard(.general)` | `cannotRemoveGeneralPasteboard` |
| `removePasteboard(.named(n))` で n が未作成 | 成功扱い（OS が無視するため。冪等） |
| 破棄済みスコープへの読み書き | `pasteboardUnavailable(name:)` |

**制御フロー**: `PasteboardResolver.resolve(_:)` が `PasteboardScope` → `UIPasteboard` を返す。nil なら `pasteboardUnavailable`。

**互換性方針**: 全 API が `scope: PasteboardScope = .general` のデフォルト引数を持つ。

---

### S2 コピー / S3 コピーオプション / S4 追記（D-8）

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

/// Privacy options. Applies to `copy` only; `append` cannot carry them
/// because `UIPasteboard.addItems(_:)` has no options overload.
public struct ClipboardCopyOptions: Equatable, Sendable {
    public static let `default` = ClipboardCopyOptions(localOnly: true, expirationDate: nil)
    public let localOnly: Bool          // 既定 true（Universal Clipboard 流出対策）
    public let expirationDate: Date?
}
```

**append の分離（レビュー指摘対応）**

v1 は `replaceExisting: Bool` を options に持たせたため、`false` のとき既定 `localOnly: true` を黙って無視するか、既定値でも必ず失敗するかの二択になり矛盾していた。v2 では:

- `copy(_:options:scope:)` … `setItems(_:options:)`。options を適用する
- `append(_:scope:)` … `addItems(_:)`。**options を引数に取らない**（型として渡せない）

これにより「安全な既定値を黙って破る」経路が存在しなくなる。追記時のプライバシー設定は直前の `copy` のものが残る旨を DocC に明記する。Bridge JSON でも `clipboardAppend` は `options` キーを受け付けず、指定された場合は `invalidRequest` を返す。

**入力検証（責務分離: レビュー指摘対応）**

v1 は UseCase 表と Repository エラー表の双方にファイル / 画像検証を書いており責務が不一致だった。v2 では次のとおり分離する。

**(a) 純粋検証** — `ClipboardContentValidator`（Application 層、`nonisolated struct`、Data / UIKit 非依存）

| ケース | 判定 | エラー |
|---|---|---|
| `plainText("")` | 許可 | - |
| `htmlText` の `html` が空白のみ | 拒否 | `emptyContent` |
| `htmlText` の `plain` が空白のみ | 許可（HTML からの生成を呼び出し側に強制しない） | - |
| `url` が空 / スキーム無し / http(s) で host 無し | 拒否 | `invalidURL` |
| `imageData` / `customData` の `Data` が空 | 拒否 | `emptyContent` |
| `color` が非有限値、または 0.0...1.0 の範囲外 | 拒否 | `invalidColor` |
| `multipleText` が空配列 | 拒否 | `emptyItemList` |
| `multiRepresentation` が空辞書 | 拒否 | `emptyItemList` |
| `multiRepresentation` に空 `Data` の値が 1 つでもある | 拒否 | `emptyContent` |
| `multiRepresentation` のキーが空文字 | 拒否 | `invalidTypeIdentifier` |
| `expirationDate <= now` | 拒否 | `invalidExpirationDate`（L-1 の低優先度指摘に対応。初期版で契約を確定させる） |
| `imageFile(path:)` が空文字 | 拒否 | `invalidRequest` |

**(b) 型・データ依存検証** — Data 層

| ケース | 実施箇所 | エラー |
|---|---|---|
| UTI が `UTType(_:)` で解決できない | `ClipboardTypeIdentifierValidator` | `invalidTypeIdentifier` |
| `imageData` の UTI が `UTType.image` に conform しない | 同上 | `invalidTypeIdentifier` |
| `imageData` が `UIImage(data:)` でデコードできない | `ClipboardRepositoryImpl` | `invalidImageData` |
| `imageFile` のパスが存在しない | `ClipboardRepositoryImpl` | `fileNotFound` |
| `imageFile` が `UIImage(contentsOfFile:)` で読めない | `ClipboardRepositoryImpl` | `imageLoadFailed` |
| 名前付きスコープが解決できない | `PasteboardResolver` | `pasteboardUnavailable` |

UTI 判定を「逆 DNS 形式かどうか」で行うと `public.utf8-plain-text` などの標準 UTI を誤って拒否するため、**`UTType(_:)` による SDK の型解決に寄せる**（レビュー指摘対応）。`UTType` は `UniformTypeIdentifiers` 依存のため Data 層に置く。

**書き込み方式**: `setValue(_:forPasteboardType:)` は使用しない（暗黙置換が誤用を招く）。`setItems` / `addItems` に統一。

---

### S5 ペースト（同期）

```swift
public struct ClipboardItemData: Equatable, Sendable {
    public let typeIdentifiers: [String]
    public let text: String?
    public let urlString: String?
    public let imageDataUTType: String?   // 本体は返さない。必要なら readData / loadItem
}

public struct ClipboardReadResult: Equatable, Sendable {
    public let items: [ClipboardItemData]
    public let numberOfItems: Int
}
```

**P-4 `readData` の縦断設計（v1 欠落分・レビュー高優先度指摘）**

| 層 | シグネチャ |
|---|---|
| Port | `func readData(utType: String, scope: PasteboardScope) throws -> Data?` |
| UseCase | `ReadDataUseCase.execute(utType:scope:) throws -> Data?` |
| Data | `pasteboard.data(forPasteboardType:)`。UTI は事前に `ClipboardTypeIdentifierValidator` で検証 |
| Manager callback | `readData(utType:scope:completion: (Data?, String?, String?) -> Void)` |
| Manager native | `readData(utType:scope:) async throws -> Data?` |
| Bridge | `clipboardReadData(const char* requestJson, ClipboardJsonCallback)` |
| Bridge JSON | request: `{"scope": {...}, "utType": "public.png"}` / success: `{"ok": true, "data": {"utType": "public.png", "base64": "...", "byteCount": 2048}}`。該当なしは `{"ok": true, "data": null}` |
| テスト | U-13（UseCase 正常）、U-14（UTI 不正）、U-31（Data 実機）、U-47（Manager）、U-57（Bridge JSON） |

**プライバシー**: `read` / `readData` は本体を読むため許可プロンプト / アクセス通知の対象になりうる。事前判定には `snapshot`（P-5）を使うよう DocC で誘導する。

**エラーハンドリング**: 空クリップボードは `items: []` / `nil` を返し、エラーにしない。

---

### S6 ペースト（`NSItemProvider` 非同期）

企画書の「設計上の契約 6 点」をそのまま実装契約とする。

```swift
public enum ClipboardLoadRequest: Equatable, Sendable {
    case text
    case url                     // L-4 で追加（企画書の標準型に URL があるため）
    case image                   // Data 層で PNG へエンコードして返す
    case file(utType: String)
}

public enum ClipboardLoadedItem: Sendable, Equatable {
    case text(String)
    case url(String)
    case imageData(Data, utType: String)
    case file(URL)               // 成功時のみ呼び出し側所有
}
```

**Port（callback + token を維持: L-2 原則 2）**

```swift
@MainActor
public protocol ClipboardItemLoader: AnyObject {
    /// Loads the first matching item. `completion` is invoked exactly once on the main actor.
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
2. `itemProviders` から条件に合う provider を検索。無ければ `Task { @MainActor in }` 経由で `noMatchingItem` を配信（同期実行しない）
3. `loadObject` / `loadDataRepresentation` / `loadFileRepresentation` を呼び、`Progress` を管理表へ格納
4. completion（任意スレッド）で結果を組み立てる
   - `.image` は `ClipboardImageEncoder` の background executor で `pngData()` を実行（L-3）。main では変換しない
   - `.file` は `ClipboardTemporaryFileStore` へコピー
5. main へ hop し、`finish(id:)` が管理表から ID を除去できた場合のみ配信。除去できない（キャンセル済み）場合は結果を破棄し、生成済み一時ディレクトリを削除
6. `cancelAll()` / `deinit` / token `cancel()` は各リクエストへ `.cancelled` を **1 回**配信してから管理表を空にする

**Manager native 版のキャンセル転送（L-2）**

```swift
public func loadItem(_ request: ClipboardLoadRequest, scope: PasteboardScope = .general)
    async throws -> ClipboardLoadedItem
```

`withTaskCancellationHandler` + `withCheckedThrowingContinuation` で実装し、Task キャンセル時に token を cancel する。continuation は必ず 1 回だけ resume する（token cancel と provider 完了の競合は Loader 側の gate で吸収されるため、continuation の二重 resume は発生しない）。

**一時ファイル（`ClipboardTemporaryFileStore`、D-7 改訂）**

```
<NSTemporaryDirectory()>/IosLibraryClipboard/<sessionUUID>/<requestUUID>/<UUID>.<検証済み拡張子>
```

- 保存名は `suggestedName` をそのまま使わない。UUID + 許可リスト検証済み拡張子（`png` / `jpg` / `jpeg` / `heic` / `heif` / `gif` / `tiff` / `webp` / `txt` / `pdf`、非該当は `bin`）
- 標準化パスが専用ディレクトリ配下であることを検証してからコピー
- 失敗・キャンセル・loader 解放時は **requestUUID ディレクトリ単位**で削除
- **起動時 cleanup（v1 の問題を修正）**: Manager 初期化ごとに全削除すると、別インスタンスが所有権移譲済みのファイルを消しうる。v2 では
  - プロセスごとに **1 回だけ**実行（`static let cleanupOnce: Void = { ... }()`）
  - 削除対象は **自セッション以外**の session ディレクトリのうち、更新時刻が **24 時間より古い**もの
  - 現在アクティブな session ディレクトリは対象外

---

### S7 内容確認

```swift
public struct ClipboardSnapshot: Equatable, Sendable {
    public let hasStrings: Bool
    public let hasURLs: Bool
    public let hasImages: Bool
    public let hasColors: Bool
    public let numberOfItems: Int
    public let typeIdentifiers: [String]          // 先頭アイテム
    public let allTypeIdentifiers: [[String]]     // types(forItemSet: nil)
}
```

公式が「通知・アラートを避ける API」として列挙しているもののみを使う。`contains(pasteboardTypes:)` は内部の型判定にのみ使い公開しない（D-3）。

---

### S8 クリア

- `ClearClipboardUseCase` → `repository.clear(scope:)` → `pasteboard.items = []`
- 名前付きペーストボードそのものの破棄は S1 の `RemovePasteboardUseCase`
- エラー: `pasteboardUnavailable`

---

### S9 変更監視

**Delegate 所有**: `IosClipboardManager` が `changedNotification` / `removedNotification` の 2 トークンを単独保持する。

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

**`ClipboardChangeTracker`**（Application 層 / `nonisolated struct` / テスト対象）

```swift
public struct ClipboardChangeTracker {
    public init(baseline: Int)
    public mutating func resync(to current: Int)
    public mutating func markReported(current: Int)
    public mutating func hasChanged(current: Int) -> Bool
}
```

同期規則:

1. `startObserving` で `resync`
2. `changedNotification` 受信時に `markReported`
3. `checkForegroundChange()` は比較後に必ず基準値を更新
4. `stopObserving` 後に到着した通知は配信しない（トークン解除 + 世代 ID）

**制御フロー**: `startObserving` は既に監視中なら先に `stopObserving()` → resync → トークン登録。通知ブロックは `Task { @MainActor in }` で状態更新し `onEvent` を main で呼ぶ。`deinit` でも `stopObserving()`。

---

### S10 パターン検出

```swift
public struct ClipboardDetectedValues: Equatable, Sendable {
    public let probableWebURL: String?
    public let probableWebSearch: String?
    public let number: Double?
    public let links: [String]
    public let emailAddresses: [String]
    public let phoneNumbers: [String]
    public let detectedPatterns: Set<ClipboardDetectionPattern>
}

public enum ClipboardDetectionPattern: String, CaseIterable, Sendable {
    case probableWebURL, probableWebSearch, number, link, emailAddress,
         phoneNumber, postalAddress, calendarEvent, flightNumber,
         moneyAmount, shipmentTrackingNumber
}
```

**制御フロー**: Port も UseCase も `async throws`（L-2 原則 3）。Data 層で `ClipboardDetectionPattern` → `PartialKeyPath<UIPasteboard.DetectedValues>` へ変換 → `detectedPatterns(for:)` / `detectedValues(for:)` → ドメイン型へ変換。

**エラー**: 空集合は `emptyDetectionPatterns`。System の throw は `detectionFailed(ClipboardFailureDetail)` へ正規化。

---

### S11 貼り付け UI（レビュー高優先度指摘への対応）

v1 は受信 View が受け取る `[NSItemProvider]` を処理する接続先が無く、S6 の Port（スコープから最初の 1 件を読む契約）では実装できなかった。v2 では **Presentation 層に専用ローダーを新設**し、`NSItemProvider` を Presentation に閉じ込める（Application Port へ UIKit 型を漏らさない）。

```swift
/// Loads data from an explicit `[NSItemProvider]` array handed over by UIKit paste.
/// Lives in Presentation because `NSItemProvider` must not appear in Application Ports.
@MainActor
final class PasteItemProviderLoader {
    @discardableResult
    func load(
        providers: [NSItemProvider],
        accepting requests: [ClipboardLoadRequest],
        completion: @escaping (PasteAggregateResult) -> Void
    ) -> any ClipboardLoadToken
    func cancelAll()
}

public struct PasteAggregateResult: Sendable {
    public let items: [ClipboardLoadedItem]        // 入力 provider の順序を保持
    public let failures: [ClipboardError]          // 失敗した provider のエラー
}
```

`ClipboardTemporaryFileStore` / `ClipboardImageEncoder` は S6 と共用する（重複実装を作らない）。

**集約契約（D-4 で確定）**

| 状況 | コールバック |
|---|---|
| 成功 1 件以上 | `onPaste(items)` を **1 回**。`items` は入力 provider の順序を保持 |
| 成功 1 件以上 + 失敗あり | 上記に加えて `onPartialFailure(failures)` を **1 回**（`onPaste` の後） |
| 成功 0 件 + 失敗 1 件以上 | `onPasteFailure(failures.first!)` を **1 回**。`onPaste` は呼ばない |
| 成功 0 件 + 失敗 0 件（provider が空 / 受理型なし） | `onPasteFailure(.noMatchingItem)` を **1 回** |

- 1 provider あたりの型優先順位: text > url > image > file（D-4）
- 部分失敗は他 provider の処理を止めない
- **token**: `paste(itemProviders:)` の開始時に前回の未完了ロードを `cancelAll()` する（新しい貼り付けを優先）。View の `deinit` でも `cancelAll()`
- **一時ファイル所有権**: `onPaste` に載った `.file` は呼び出し側所有。`onPaste` が呼ばれない経路（キャンセル、成功 0 件）では Presentation 側がディレクトリごと削除する

**受信 View / ファクトリ**

```swift
@MainActor
public final class ClipboardPasteReceiverView: UIView {
    public var onPaste: ((_ items: [ClipboardLoadedItem]) -> Void)?
    public var onPartialFailure: ((_ failures: [ClipboardError]) -> Void)?
    public var onPasteFailure: ((_ error: ClipboardError) -> Void)?
    public override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool
    public override func paste(itemProviders: [NSItemProvider])
}

@MainActor
public enum PasteControlFactory {
    public static func makePasteControl(
        acceptedTypes: [String],
        displayMode: UIPasteControl.DisplayMode,
        receiver: ClipboardPasteReceiverView
    ) -> UIPasteControl
}
```

`receiver.pasteConfiguration` を `acceptedTypes` で設定し、`control.target = receiver` を必ずセットする。`canPaste` は `acceptedTypes` と同じ判定ロジックを使い、宣言型と実処理を一致させる。呼び出し側は `receiver` も view 階層に追加する必要がある（responder chain 要件）ことを DocC に明記する。

**Unity Bridge には公開しない**（D-1）。

---

### S12 Unity Bridge

#### エラーコード変換経路（レビュー高優先度指摘への対応）

v1 は Manager callback が `(Bool, String?)` でコードを返さず、Bridge が型付きエラーを失っていた。v2 では:

1. **`ClipboardError` 自身が `errorCode: String` を持つ**（Domain 層で定義）
2. **Manager callback のシグネチャを `(Bool, String? errorCode, String? errorMessage)` に統一**
3. **Bridge は Manager の `async throws` 版を `Task { @MainActor in }` で呼び、`catch let error as ClipboardError` で 1 箇所だけ変換する**。localized message の解析は行わない

```swift
// UnityIosClipboardManager 内の唯一の変換点
private func run(_ operation: @escaping () async throws -> Void,
                 handler: ((Bool, String?, String?) -> Void)?) {
    Task { @MainActor in
        do {
            try await operation()
            handler?(true, nil, nil)
        } catch let error as ClipboardError {
            handler?(false, error.errorCode, error.errorDescription)
        } catch {
            handler?(false, ClipboardError.unknownCode, error.localizedDescription)
        }
    }
}
```

#### JSON schema（全 endpoint。v1 の「抜粋」を解消）

**共通 envelope**

- JSON callback の成功: `{"ok": true, "data": <object|null>}`
- JSON callback の失敗: `{"ok": false, "error": {"code": "CLIPBOARD_*", "message": "..."}}`
- Operation callback: `(BOOL isSuccess, NSString* errorCode, NSString* errorMessage)`

**共通規約**

| 事項 | 規約 |
|---|---|
| `scope` オブジェクト | `{"kind": "general"}` / `{"kind": "named", "name": "..."}` / `{"kind": "unique", "name": "..."}` |
| `scope` 省略 | `.general` として扱う |
| JSON が NULL / 空文字 / パース不能 | `CLIPBOARD_INVALID_REQUEST` |
| 未知の `kind` 値 | `CLIPBOARD_INVALID_REQUEST`（メッセージに受領値は含めない。ログも秘匿） |
| 必須キー欠落 | `CLIPBOARD_INVALID_REQUEST` |
| Base64 が不正 | `CLIPBOARD_INVALID_REQUEST` |
| 想定外の余分なキー | 無視する（前方互換のため） |
| `expirationDate` | ISO 8601 文字列。`null` 可 |
| バイナリ | Base64 文字列（`data` キー） |

**endpoint 一覧**

| C 関数 | request JSON | success `data` | 対応 API |
|---|---|---|---|
| `clipboardCopy` | `{"scope":{...},"content":{...},"options":{"localOnly":true,"expirationDate":null}}` | `null` | P-1 |
| `clipboardAppend` | `{"scope":{...},"content":{...}}`（`options` を含むと `INVALID_REQUEST`） | `null` | P-2 |
| `clipboardRead` | `{"scope":{...}}` | `{"numberOfItems":1,"items":[{"typeIdentifiers":[...],"text":null,"urlString":null,"imageDataUTType":null}]}` | P-3 |
| `clipboardReadData` | `{"scope":{...},"utType":"public.png"}` | `{"utType":"public.png","base64":"...","byteCount":2048}` または `null` | P-4 |
| `clipboardGetSnapshot` | `{"scope":{...}}` | `{"hasStrings":true,...,"numberOfItems":1,"typeIdentifiers":[...],"allTypeIdentifiers":[[...]]}` | P-5 |
| `clipboardClear` | `{"scope":{...}}` | `null` | P-6 |
| `clipboardCreatePasteboard` | `{"request":{"kind":"named","name":"..."}}` または `{"request":{"kind":"unique"}}` | `{"scope":{"kind":"unique","name":"..."}}` | P-7 |
| `clipboardRemovePasteboard` | `{"scope":{...}}` | `null` | P-8 |
| `clipboardDetectPatterns` | `{"scope":{...},"patterns":["probableWebURL","number"]}` | `{"patterns":["probableWebURL"]}` | P-9 |
| `clipboardDetectValues` | `{"scope":{...},"patterns":[...]}` | `{"probableWebURL":null,"probableWebSearch":null,"number":null,"links":[],"emailAddresses":[],"phoneNumbers":[],"detectedPatterns":[]}` | P-10 |
| `clipboardLoadItem` | `{"scope":{...},"request":{"kind":"file","utType":"public.png"}}` | `{"kind":"file","path":"/.../x.png"}` / `{"kind":"text","text":"..."}` / `{"kind":"url","urlString":"..."}` / `{"kind":"imageData","utType":"public.png","base64":"..."}` | P-11 |
| `clipboardCancelLoads` | 引数なし | - | P-12 |
| `clipboardStartObserving` | `{"scope":{...}}` | イベント JSON: `{"kind":"changed","typesAdded":[...],"typesRemoved":[...],"scope":{...}}` / `{"kind":"changedDetectedOnForeground",...}` / `{"kind":"removed",...}` | P-13 |
| `clipboardStopObserving` | 引数なし | - | P-14 |
| `clipboardCheckForegroundChange` | `{"scope":{...}}` | `{"changed":true}` | P-15 |

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
void clipboardStartObserving(const char* requestJson, ClipboardChangeCallback callback);
void clipboardStopObserving(void);
void clipboardCheckForegroundChange(const char* requestJson, ClipboardJsonCallback callback);
```

`.m` の完了ブロック引数は `BOOL` / `NSString * _Nullable`（ios.md）。全 C 関数の先頭で `ClipboardLog.redact(json:)` を通したログを出す。

---

## API 設計（公開 / 内部）

### 公開 API（`IosClipboardManager`）

callback は**全経路で main actor から 1 回だけ**呼ぶ。callback 版のエラーは `(errorCode, errorMessage)` の 2 つを返す。

| # | callback 版 | `async throws` 版 |
|---|---|---|
| P-1 | `copy(_:options:scope:completion: (Bool, String?, String?) -> Void)` | `copy(_:options:scope:) async throws` |
| P-2 | `append(_:scope:completion:)` | `append(_:scope:) async throws` |
| P-3 | `read(scope:completion: (ClipboardReadResult?, String?, String?) -> Void)` | `read(scope:) async throws -> ClipboardReadResult` |
| P-4 | `readData(utType:scope:completion: (Data?, String?, String?) -> Void)` | `readData(utType:scope:) async throws -> Data?` |
| P-5 | `snapshot(scope:completion:)` | `snapshot(scope:) async throws -> ClipboardSnapshot` |
| P-6 | `clear(scope:completion:)` | `clear(scope:) async throws` |
| P-7 | `createPasteboard(_:completion:)` | `createPasteboard(_:) async throws -> PasteboardScope` |
| P-8 | `removePasteboard(_:completion:)` | `removePasteboard(_:) async throws` |
| P-9 | `detectPatterns(_:scope:completion:)` | `detectPatterns(_:scope:) async throws -> Set<ClipboardDetectionPattern>` |
| P-10 | `detectValues(_:scope:completion:)` | `detectValues(_:scope:) async throws -> ClipboardDetectedValues` |
| P-11 | `loadItem(_:scope:completion:) -> any ClipboardLoadToken` | `loadItem(_:scope:) async throws -> ClipboardLoadedItem` |
| P-12 | `cancelAllLoads()` | 同左（同期） |
| P-13 | `startObserving(scope:onEvent:)` | 同左（同期） |
| P-14 | `stopObserving()` | 同左（同期） |
| P-15 | `checkForegroundChange(scope:) -> Bool` | 同左（同期） |
| P-16 | `makePasteControl(acceptedTypes:displayMode:onPaste:onPartialFailure:onPasteFailure:)` | 同左（同期・Unity 非公開） |

### 内部 API

| 型 | 可視性 | 理由 |
|---|---|---|
| `ClipboardRepository` / `ClipboardItemLoader` / `ClipboardLoadToken` | `public`（protocol） | Manager の test 用 init で注入するため |
| `ClipboardRepositoryImpl` / `ClipboardItemLoaderImpl` | `internal` | UIKit 依存を露出しない |
| `PasteboardResolver` / `ClipboardMappers` / `ClipboardTypeIdentifierValidator` / `ClipboardTemporaryFileStore` / `ClipboardImageEncoder` / `ClipboardLog` | `internal` | 実装詳細 |
| `PasteItemProviderLoader` | `internal` | `NSItemProvider` を露出しない |
| `ClipboardChangeTracker` / `ClipboardContentValidator` | `public` | 純ロジックの単体テスト対象 |
| UseCase 群 | `public` | 既存 `ShareContentUseCase` に合わせる |

---

## ドメインエラー一覧（全ケース）

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
    case invalidRequest(String)          // Bridge / 引数レベルの不正
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
    case detectionFailed(ClipboardFailureDetail)
    case unknown(ClipboardFailureDetail)
}
```

`optionsNotApplicableForAppend`（v1）は append を独立 API にしたため不要となり削除した。

| # | ケース | 発生元 | 発生条件 |
|---|---|---|---|
| E-01 | `emptyContent` | `ClipboardContentValidator` | html が空白のみ / `Data` が空 / `multiRepresentation` に空 `Data` |
| E-02 | `emptyItemList` | `ClipboardContentValidator` | `multipleText` 空配列 / `multiRepresentation` 空辞書 |
| E-03 | `emptyDetectionPatterns` | `DetectPatternsUseCase` | パターン集合が空 |
| E-04 | `invalidURL` | `ClipboardContentValidator` | 空 / スキーム無し / http(s) で host 無し |
| E-05 | `invalidTypeIdentifier` | `ClipboardTypeIdentifierValidator` | `UTType(_:)` で解決不能 / `imageData` の UTI が image に非適合 / `multiRepresentation` のキーが空 |
| E-06 | `invalidPasteboardName` | `CreatePasteboardUseCase` | 名前が空白のみ |
| E-07 | `invalidColor` | `ClipboardContentValidator` | 非有限値 / 0.0...1.0 の範囲外 |
| E-08 | `invalidImageData` | `ClipboardRepositoryImpl` | `UIImage(data:)` でデコード不能 |
| E-09 | `invalidExpirationDate` | `ClipboardContentValidator` | `expirationDate <= now` |
| E-10 | `invalidRequest` | Bridge / Manager | JSON 不正・必須キー欠落・未知 kind・Base64 不正・`append` に options 指定・空パス |
| E-11 | `fileNotFound` | `ClipboardRepositoryImpl` | `imageFile` のパスが存在しない |
| E-12 | `imageLoadFailed` | `ClipboardRepositoryImpl` | `UIImage(contentsOfFile:)` が nil |
| E-13 | `imageEncodingFailed` | `ClipboardImageEncoder` | `pngData()` が nil |
| E-14 | `pasteboardUnavailable` | `PasteboardResolver` | `UIPasteboard(name:create:)` が nil |
| E-15 | `cannotRemoveGeneralPasteboard` | `RemovePasteboardUseCase` | `.general` を破棄しようとした |
| E-16 | `noMatchingItem` | Loader / Presentation loader | 条件に合う provider が無い |
| E-17 | `providerLoadFailed` | Loader | provider の completion が error を返した |
| E-18 | `unexpectedType` | Loader | error は nil だが期待型へ変換できない |
| E-19 | `fileCopyFailed` | `ClipboardTemporaryFileStore` | ディレクトリ作成 / コピー失敗、containment 検証失敗 |
| E-20 | `cancelled` | Loader / Presentation loader | `cancelAll()` / `deinit` / token `cancel()` / Task キャンセル |
| E-21 | `detectionFailed` | `ClipboardRepositoryImpl` | 検出 API が throw |
| E-22 | `unknown` | 全層 | 上記に該当しないシステムエラー |

---

## エラーコード / メッセージ対応表

`ClipboardError` に `public var errorCode: String` を実装し、Bridge はこの値をそのまま返す（文字列解析をしない）。

| ドメインエラー | errorCode | message（英語） | Android 共通 |
|---|---|---|---|
| `emptyContent` | `CLIPBOARD_EMPTY_CONTENT` | `Clipboard content is empty. Please provide text or HTML.` | 共通 |
| `emptyItemList` | `CLIPBOARD_EMPTY_ITEMS` | `No items provided for clipboard copy.` | 共通 |
| `pasteboardUnavailable(name)` | `CLIPBOARD_UNAVAILABLE` | `Pasteboard is unavailable: {name}. A named pasteboard exists only while its creating app is running.` | 共通 |
| `unknown(detail)` | `CLIPBOARD_UNKNOWN` | `An unknown error occurred: {detail.message}` | 共通 |
| `invalidURL(v)` | `CLIPBOARD_INVALID_URL` | `Invalid URL: {v}` | iOS 固有（下記差異表） |
| `emptyDetectionPatterns` | `CLIPBOARD_EMPTY_PATTERNS` | `No detection patterns were specified.` | iOS 固有 |
| `invalidTypeIdentifier(v)` | `CLIPBOARD_INVALID_TYPE` | `Invalid uniform type identifier: {v}` | iOS 固有 |
| `invalidPasteboardName(v)` | `CLIPBOARD_INVALID_NAME` | `Invalid pasteboard name: {v}` | iOS 固有 |
| `invalidColor` | `CLIPBOARD_INVALID_COLOR` | `Color components must be finite and within 0.0...1.0.` | iOS 固有 |
| `invalidImageData` | `CLIPBOARD_INVALID_IMAGE_DATA` | `The provided image data could not be decoded.` | iOS 固有 |
| `invalidExpirationDate` | `CLIPBOARD_INVALID_EXPIRATION` | `expirationDate must be in the future.` | iOS 固有 |
| `invalidRequest(reason)` | `CLIPBOARD_INVALID_REQUEST` | `Invalid request: {reason}` | iOS 固有 |
| `fileNotFound(path)` | `CLIPBOARD_FILE_NOT_FOUND` | `File not found at path: {path}` | iOS 固有 |
| `imageLoadFailed(path)` | `CLIPBOARD_IMAGE_LOAD_FAILED` | `Failed to load image at path: {path}` | iOS 固有 |
| `imageEncodingFailed` | `CLIPBOARD_IMAGE_ENCODE_FAILED` | `Failed to encode the pasted image.` | iOS 固有 |
| `cannotRemoveGeneralPasteboard` | `CLIPBOARD_CANNOT_REMOVE_GENERAL` | `The general pasteboard cannot be removed.` | iOS 固有 |
| `noMatchingItem` | `CLIPBOARD_NO_MATCHING_ITEM` | `No clipboard item matches the requested type.` | iOS 固有 |
| `providerLoadFailed(d)` | `CLIPBOARD_LOAD_FAILED` | `Failed to load clipboard item: {d.message}` | iOS 固有 |
| `unexpectedType` | `CLIPBOARD_UNEXPECTED_TYPE` | `The clipboard item could not be converted to the requested type.` | iOS 固有 |
| `fileCopyFailed(d)` | `CLIPBOARD_FILE_COPY_FAILED` | `Failed to copy the pasted file: {d.message}` | iOS 固有 |
| `cancelled` | `CLIPBOARD_CANCELLED` | `The clipboard load was cancelled.` | iOS 固有 |
| `detectionFailed(d)` | `CLIPBOARD_DETECTION_FAILED` | `Pattern detection failed: {d.message}` | iOS 固有 |

### Android とのコード差異表（レビュー指摘対応）

v1 は「同じ意味で命名」とだけ書いていたが、実際には共有できないコードがある。共通コードは**完全一致**させ、それ以外は「片側固有」として明示する。

| コード | Android | iOS | 備考 |
|---|---|---|---|
| `CLIPBOARD_EMPTY_CONTENT` | あり | あり | 完全一致 |
| `CLIPBOARD_EMPTY_ITEMS` | あり | あり | 完全一致 |
| `CLIPBOARD_UNAVAILABLE` | あり | あり | 完全一致（意味: サービス / ペーストボードが利用不可） |
| `CLIPBOARD_UNKNOWN` | あり | あり | 完全一致 |
| `CLIPBOARD_INVALID_URI` | あり | **なし** | Android 固有。`content://` URI が対象 |
| `CLIPBOARD_READ_NOT_ALLOWED` | あり | **なし** | Android 固有。iOS に対応する API エラーがない（プロンプトは OS が処理） |
| `CLIPBOARD_SECURITY` | あり | **なし** | Android 固有（`SecurityException`） |
| `CLIPBOARD_INVALID_URL` | なし | あり | iOS 固有。http(s) / file URL が対象 |
| 上記以外の iOS コード 14 種 | なし | あり | iOS 固有（`UIPasteboard` / `NSItemProvider` 由来） |

### `cancelled` の扱い

Share の「ユーザーキャンセルは成功」とは異なり、クリップボードのロードキャンセルは呼び出し側（画面破棄など）が起点で結果を利用できないため `isSuccess == false` とする。呼び出し側は `errorCode == "CLIPBOARD_CANCELLED"` を正常系として無視できる。この扱いは DocC・Bridge ヘッダ・サンプルアプリの 3 箇所で示す。

---

## テスト設計

### 単体テスト（Swift Testing / `IosLibraryTests`）

#### Domain

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-01 | `ClipboardError` | 正常 | 全 22 ケースの `errorCode` が対応表と一致し、重複がない |
| U-02 | 〃 | 正常 | 全 22 ケースの `errorDescription` が非 nil かつ英語 |
| U-03 | `ClipboardFailureDetail` | 正常 | `domain` / `code` / `message` が保持される |

#### Application（純ロジック）

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-04 | `ClipboardContentValidator` | 正常 | `plainText("")` は成功 |
| U-05 | 〃 | 異常 | html 空白のみ → `emptyContent` |
| U-06 | 〃 | 正常 | `htmlText` の plain が空でも成功 |
| U-07 | 〃 | 異常 | `url("")` / `"example.com"` / `"https://"` → `invalidURL` |
| U-08 | 〃 | 異常 | `multipleText([])` / `multiRepresentation([:])` → `emptyItemList` |
| U-09 | 〃 | 異常 | `multiRepresentation` に空 `Data` → `emptyContent` |
| U-10 | 〃 | 異常 | `multiRepresentation` のキーが空文字 → `invalidTypeIdentifier` |
| U-11 | 〃 | 異常 | `color` が `.infinity` / `-0.1` / `1.1` → `invalidColor` |
| U-12 | 〃 | 境界 | `color` が 0.0 / 1.0 ちょうどは成功 |
| U-13 | 〃 | 異常 | `expirationDate` が現在時刻・過去 → `invalidExpirationDate` |
| U-14 | 〃 | 異常 | `imageFile("")` → `invalidRequest` |
| U-15 | `ClipboardChangeTracker` | 正常 | 基準値と異なるとき true、同じとき false |
| U-16 | 〃 | 正常 | `hasChanged` 後に基準値が更新され、連続呼び出しは false |
| U-17 | 〃 | 境界 | `markReported` 後の `hasChanged` は false（二重報告防止） |
| U-18 | 〃 | 境界 | `resync` 後は停止中の変更を検知しない |

#### Application（UseCase / Mock 注入）

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-19 | `CopyContentUseCase` | 正常 | 9 種の `ClipboardContent` で `copyCallCount == 1`、options が一致 |
| U-20 | 〃 | 異常 | Validator のエラーがそのまま伝播し、Repository が呼ばれない |
| U-21 | 〃 | 異常 | `shouldFail = true` → Repository のエラーが伝播 |
| U-22 | `AppendContentUseCase` | 正常 | `appendCallCount == 1`。options 引数が存在しない（型で保証） |
| U-23 | `ReadContentUseCase` | 正常 | `stubbedReadResult` を返す |
| U-24 | 〃 | 境界 | 空クリップボード → `items == []` かつ throw しない |
| U-25 | `ReadDataUseCase` | 正常 | `stubbedData` を返し、`readDataCallCount == 1` |
| U-26 | 〃 | 異常 | UTI 不正 → `invalidTypeIdentifier`（Repository は呼ばれない） |
| U-27 | 〃 | 境界 | 該当なし → `nil` を返し throw しない |
| U-28 | `GetSnapshotUseCase` | 正常 | `stubbedSnapshot` を返す |
| U-29 | `ClearClipboardUseCase` | 正常 | `clearCallCount == 1` |
| U-30 | `CreatePasteboardUseCase` | 異常 | 空白名 → `invalidPasteboardName` |
| U-31 | 〃 | 正常 | `.unique` → 生成名入りの `.unique(name)` を返す |
| U-32 | `RemovePasteboardUseCase` | 異常 | `.general` → `cannotRemoveGeneralPasteboard` |
| U-33 | 〃 | 境界 | 未作成の名前 → 成功（冪等） |
| U-34 | `DetectPatternsUseCase` | 異常 | 空集合 → `emptyDetectionPatterns` |
| U-35 | 〃 | 正常 | `stubbedDetectedValues` / `stubbedPatterns` を返す |
| U-36 | `LoadItemUseCase` | 正常 | text / url / image / file の 4 種を返す |
| U-37 | 〃 | 異常 | 各エラー（`noMatchingItem` / `providerLoadFailed` / `unexpectedType` / `fileCopyFailed` / `cancelled`）が伝播 |
| U-38 | 〃 | 正常 | 返却 token の `cancel()` が Loader の `cancelCallCount` を増やす |

#### Data

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-39 | `ClipboardRepositoryImpl` | 正常 | 9 種の内容を書き込み → `read` で往復一致（`.unique` scope 使用） |
| U-40 | 〃 | 正常 | `multiRepresentation` で 1 アイテムに 2 UTI が載る |
| U-41 | 〃 | 正常 | `append` で件数が増える |
| U-42 | 〃 | 正常 | `clear` 後に `numberOfItems == 0` |
| U-43 | 〃 | 正常 | `snapshot` の `has*` が内容と一致 |
| U-44 | 〃 | 正常 | `readData` が指定 UTI の `Data` を返し、非該当は nil |
| U-45 | 〃 | 異常 | 存在しない画像パス → `fileNotFound` |
| U-46 | 〃 | 異常 | デコード不能な `imageData` → `invalidImageData` |
| U-47 | 〃 | 異常 | 解決できない名前 → `pasteboardUnavailable` |
| U-48 | 〃 | 正常 | `remove(withName:)` 後に `create: false` で解決できない |
| U-49 | `ClipboardTypeIdentifierValidator` | 正常 | `public.utf8-plain-text` / `public.png` など標準 UTI が通る（逆 DNS 判定による誤拒否がない） |
| U-50 | 〃 | 異常 | 解決不能な文字列 → `invalidTypeIdentifier` |
| U-51 | 〃 | 異常 | `imageData` に非画像 UTI → `invalidTypeIdentifier` |
| U-52 | `ClipboardTemporaryFileStore` | 正常 | コピー成功時にファイルが存在し、専用ディレクトリ配下にある |
| U-53 | 〃 | 異常 | `suggestedName` が `../../evil.png` → 専用ディレクトリ外に出ない |
| U-54 | 〃 | 異常 | パス区切り / 制御文字 / 1000 文字超 → 生成名は UUID + 許可拡張子のみ |
| U-55 | 〃 | 境界 | 許可外拡張子 → `bin` |
| U-56 | 〃 | 正常 | コピー失敗時にディレクトリが残らない |
| U-57 | 〃 | 正常 | 起動時 cleanup が 24 時間より古い他セッションのみ削除する |
| U-58 | 〃 | 正常 | **アクティブな自セッションのディレクトリを削除しない**（v1 の不具合の回帰テスト） |
| U-59 | `ClipboardImageEncoder` | 正常 | main 以外のスレッドでエンコードが実行される |
| U-60 | 〃 | 異常 | エンコード不能 → `imageEncodingFailed` |
| U-61 | `ClipboardLog` | 正常 | `redact` の出力に元の値が含まれない（text / data / json / path / URL） |

#### Presentation（S11・v1 に無かった分）

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-62 | `PasteItemProviderLoader` | 正常 | 全 provider 成功 → `items` が入力順序を保持し、`failures` が空 |
| U-63 | 〃 | 正常 | 混在（成功 + 失敗）→ `items` に成功分のみ、`failures` に失敗分 |
| U-64 | 〃 | 異常 | 全 provider 失敗 → `items` 空、`failures` が全件 |
| U-65 | 〃 | 境界 | provider 配列が空 → `items` / `failures` とも空 |
| U-66 | 〃 | 正常 | `cancelAll()` で結果が配信されず、一時ディレクトリが残らない |
| U-67 | `ClipboardPasteReceiverView` | 正常 | 成功 1 件以上 → `onPaste` 1 回、`onPasteFailure` 0 回 |
| U-68 | 〃 | 正常 | 成功 + 失敗 → `onPaste` 1 回 + `onPartialFailure` 1 回（順序も検証） |
| U-69 | 〃 | 異常 | 成功 0 + 失敗あり → `onPasteFailure` 1 回、`onPaste` 0 回 |
| U-70 | 〃 | 境界 | 成功 0 + 失敗 0 → `onPasteFailure(.noMatchingItem)` 1 回 |
| U-71 | 〃 | 正常 | 連続 paste で前回の未完了ロードがキャンセルされる |
| U-72 | 〃 | 正常 | `canPaste` が `acceptedTypes` と同じ判定になる（宣言型と実処理の一致） |
| U-73 | `PasteControlFactory` | 正常 | 生成した control の `target` が receiver、`receiver.pasteConfiguration` が `acceptedTypes` と一致 |

#### Manager

| ID | 系 | ケース |
|---|---|---|
| U-74 | 正常 | P-1〜P-11 の callback 版が **main thread** で **1 回だけ** 呼ばれる（API ごとに個別ケース） |
| U-75 | 異常 | Repository エラー → `(false, errorCode, errorMessage)` で `errorCode` が対応表と一致 |
| U-76 | 正常 | `async throws` 版が型付き `ClipboardError` を throw する |
| U-77 | 正常 | P-4 `readData` が callback / async の双方で動作する |
| U-78 | 正常 | P-9 `detectPatterns` が callback / async の双方で動作する |
| U-79 | 正常 | `startObserving` 二重呼び出しでイベントが重複しない |
| U-80 | 正常 | `stopObserving` 後にイベントが届かない |
| U-81 | 正常 | `stopObserving` → `startObserving` で古いイベントが新購読者へ届かない |
| U-82 | 正常 | `cancelAllLoads()` で各 pending に `.cancelled` が 1 回だけ届く |
| U-83 | 正常 | provider 不在の即時失敗直後に `cancelAllLoads()` → 通知は 1 回のみ |
| U-84 | 正常 | Manager 解放時に pending へ `.cancelled` が 1 回届く |
| U-85 | 正常 | **token 単体の `cancel()`** で当該リクエストのみ `.cancelled`、他は影響なし |
| U-86 | 正常 | **async 版の Task キャンセル**で token が cancel され、continuation が 1 回だけ resume する |
| U-87 | 境界 | **Task キャンセルと provider 完了の競合**（cancel 直後に完了）で callback は 1 回のみ |
| U-88 | 正常 | `checkForegroundChange` が同期で `Bool` を返す（callback 化していない） |

#### Unity Bridge

| ID | 系 | ケース |
|---|---|---|
| U-89 | 正常 | 9 種の `ClipboardContent` の JSON パース往復 |
| U-90 | 正常 | `scope` 省略時に `.general` として扱われる |
| U-91 | 異常 | NULL / 空文字 / パース不能 JSON → `CLIPBOARD_INVALID_REQUEST` を main で 1 回 |
| U-92 | 異常 | 未知の `kind` → `CLIPBOARD_INVALID_REQUEST`（メッセージに受領値を含めない） |
| U-93 | 異常 | 必須キー欠落 → `CLIPBOARD_INVALID_REQUEST` |
| U-94 | 異常 | Base64 不正 → `CLIPBOARD_INVALID_REQUEST` |
| U-95 | 異常 | `clipboardAppend` に `options` 指定 → `CLIPBOARD_INVALID_REQUEST` |
| U-96 | 正常 | 余分なキーは無視される（前方互換） |
| U-97 | 正常 | 15 endpoint すべての success `data` スキーマが仕様と一致 |
| U-98 | 正常 | エラー envelope が `{"ok":false,"error":{"code":...,"message":...}}` |
| U-99 | 正常 | `errorCode` が Manager の値をそのまま透過している（Bridge が message を解析していない） |
| U-100 | 正常 | Bridge のログに request JSON 本文 / Base64 / パスが含まれない |

### 統合テスト

| ID | 内容 |
|---|---|
| I-01 | `IosClipboardManager` 実体で copy → snapshot → read → readData → append → clear が一貫する（`.unique` scope） |
| I-02 | `.named` を作成 → 読み書き → `remove` 後に解決できない |
| I-03 | `setItems` の `localOnly` / `expirationDate` が例外なく適用される |
| I-04 | `startObserving` 中に自アプリで copy → `changed` イベントが 1 回届く |
| I-05 | `loadItem(.file)` の成功 URL が completion 後も読める |
| I-06 | `loadItem` 実行中に `cancelAllLoads()` → `.cancelled` 1 回、一時ディレクトリ残留なし |
| I-07 | Bridge の 15 endpoint を通した end-to-end（JSON → Manager → UIPasteboard → JSON） |
| I-08 | `SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` で `IosLibrary` / `UnityIosPlugin` がビルド警告・エラーなし |

### 手動確認項目（実機必須）

| ID | 対応リスク | 内容 |
|---|---|---|
| M-01 | プライバシー | 企画書「テスト行列」16 ケースを iOS 18 / iOS 26 実機で観測し、許可プロンプトとアクセス通知を別列で記録 |
| M-02 | プライバシー | `snapshot` のみで通知・プロンプトが出ないことを確認 |
| M-03 | プライバシー | `checkForegroundChange`（`changeCount`）で通知・プロンプトが出るかを確認（D-3 の採否判断） |
| M-04 | プライバシー | `detectValues` で通知・プロンプトが出ないことを確認 |
| M-05 | プライバシー | `itemProviders` getter / `canLoadObject` / ロードのどこが契機かを切り分け（R-02 の判断） |
| M-06 | Universal Clipboard | 同一 2 台・同一 iCloud・同一 Handoff 設定で `localOnly: false` の転送成功（正の対照）→ `true` の非転送 |
| M-07 | 機微データ残留 | `expirationDate` 経過後に内容が取得できない |
| M-08 | 名前付き寿命 | 送信側終了後に解決できない / バックグラウンド中は解決できる |
| M-09 | App Group | entitlement 設定済みの同一 Team ID 別アプリ間で読み書きできる |
| M-10 | `UIPasteControl` | 表示され、タップで許可プロンプトなしに貼り付けできる。`target` / `pasteConfiguration` 未設定時の挙動も確認 |
| M-11 | `UIPasteControl` | 画像のみのクリップボードでも動作する |
| M-12 | 一時ファイル | 強制終了後の再起動で 24 時間経過分が cleanup され、アクティブセッションが消えない |
| M-13 | 画像コスト | `imageData` 経路と `image` プロパティ経路のエンコード時間・ピークメモリを Instruments で比較 |
| M-14 | 変更監視 | 通知経路で報告済みの変更が foreground 復帰時に二重報告されない |
| M-15 | ログ | コピー / ペーストした値、request JSON、パスがログに出ていない |

---

## 実装タスク分解（依存関係付き）

レビュー指摘に従い、**プライバシー実機スパイクを初期ゲート**に移し、**ライブラリ統合と Bridge 統合を分離**し、**DocC を全公開 API 確定後**に置く。

| ID | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| **T-00** | **プライバシー実機スパイク**（M-01〜M-05 の先行実施。使い捨てコードで可） | 1日 | なし | `changeCount` / `itemProviders` getter / `canLoadObject` の通知・プロンプト有無が iOS 18 / iOS 26 で判明し、D-3・R-01・R-02 の採否が確定 | 実装前に S6 / S9 の再設計要否を判断できているか |
| T-01 | Domain 層（モデル 13 種 + `ClipboardError` + `errorCode`） | 1日 | T-00 | U-01〜U-03 が green。`UIKit` を import していない | Domain の純粋性、エラー 22 ケース網羅、`errorCode` 重複なし |
| T-02 | `ClipboardContentValidator` / `ClipboardChangeTracker` / `ClipboardLog` | 1日 | T-01 | U-04〜U-18、U-61 が green | 純粋検証と Data 依存検証の責務分離、秘匿の網羅 |
| T-03 | Port 2 種（actor 境界を宣言）+ UseCase 10 種 + 集約 + Mock 2 種 | 1.5日 | T-02 | U-19〜U-38 が green。Port の isolation が実装と一致 | Port の型制約、`readData` / `append` の縦断、Mock パターン |
| T-04 | `PasteboardResolver` / `TypeIdentifierValidator` / `Mappers` / `ClipboardRepositoryImpl` | 1.5日 | T-03 | U-39〜U-51 が green。`setValue` 不使用 | UIKit 依存の閉じ込め、UTI を `UTType` で判定しているか |
| T-05 | `ClipboardTemporaryFileStore` / `ClipboardImageEncoder` | 1日 | T-01 | U-52〜U-60 が green | path traversal 防止、cleanup が他セッションを壊さない、encode が main 外 |
| T-06 | `ClipboardItemLoaderImpl`（契約 6 点 + token） | 1.5日 | T-05, T-03 | 全経路で completion が main から 1 回。キャンセル gate が機能 | exactly-once、`Progress` 蓄積なし、URL ロード対応 |
| T-07 | `IosClipboardManager`（callback + async throws、監視トークン所有、Task キャンセル転送） | 1.5日 | T-04, T-06 | U-74〜U-88 が green。監視トークンが Manager 以外に存在しない | Delegate 所有ルール、二重開始 / 停止、continuation の 1 回 resume |
| T-08 | Presentation（`PasteItemProviderLoader` → `ClipboardPasteReceiverView` → `PasteControlFactory`） | 1.5日 | T-06 | U-62〜U-73 が green | 集約契約 4 パターン、`NSItemProvider` が Presentation 外へ出ていないか |
| T-09 | `UnityIosClipboardJsonParser`（15 endpoint の schema） | 1.5日 | T-01 | U-89〜U-97 が green | Base64、未知 kind、余分キー、秘匿ログ |
| T-10 | `UnityIosClipboardManager` + Bridge `.h` / `.m`（errorCode 透過） | 1.5日 | T-09, T-07 | U-98〜U-100 が green。ブロック引数が `BOOL` | Bridge の薄さ（message 解析なし）、main 配信、HeaderDoc |
| T-11a | **ライブラリ統合テスト** I-01〜I-06、I-08 | 1日 | T-07, T-08 | 全て green。strict concurrency 指定でビルド警告なし | `.unique` 使用で general を汚染しないか |
| T-11b | **Bridge 統合テスト** I-07 | 0.5日 | T-10, T-11a | 15 endpoint の end-to-end が green | JSON schema と実挙動の一致 |
| T-12 | サンプルアプリ対応（詳細は `design-sample-app`） | - | T-07, T-08 | S1〜S11 の全サブ機能を `IosLibraryExample` から操作でき、`IosLibrary` のみに依存する | Unity プラグイン非依存 |
| T-13 | 手動確認 M-06〜M-15 を実施し結果を記録（M-01〜M-05 は T-00 で実施済み） | 1日 | T-12 | 企画書テスト行列の観測欄が iOS 18 / iOS 26 で埋まる | 断定せず観測値を記載しているか |
| T-14 | DocC（`IosLibrary.md`）に Clipboard セクションを追記 | 0.5日 | T-10, T-08, T-12 | 全公開 API 確定後に記述。名前付きの寿命、一時ファイルの削除責務、プライバシー挙動、`cancelled` の扱い、`append` の option 非対応が明記 | 誤用を招く記述がないか |

**先行タスク（基盤）**: T-00 〜 T-07
**後続タスク（拡張）**: T-08 〜 T-14

```
T-00 → T-01 → T-02 → T-03 → T-04 ┐
         ├──→ T-05 → T-06 ───────┴→ T-07 ┬→ T-11a → T-11b
         └──→ T-09 → T-10 ───────────────┘      │
                          T-06 → T-08 ──────────┤
                                  T-07/T-08 → T-12 → T-13
                          T-10 + T-08 + T-12 → T-14
```

---

## リスクと緩和策

| # | リスク | 影響 | 緩和策 | 状態 |
|---|---|---|---|---|
| R-01 | `changeCount` が通知・プロンプト対象だった場合、`checkForegroundChange` が使えない | S9 の foreground 検知が不成立 | **T-00 で実装前に判明させる**。対象なら `changedNotification` のみに縮退し、制約を DocC に明記 | T-00 で確定 |
| R-02 | `itemProviders` getter 自体がプロンプト契機の場合、S6 / S7 の分離が崩れる | 事前判定の意味が薄れる | T-00（M-05）で切り分け。getter が契機なら S6 は `UIPasteControl` 経路を推奨に格上げ | T-00 で確定 |
| R-03 | Swift 6 strict concurrency の conformance / capture エラー | 将来の移行が困難 | Port と実装の isolation を宣言単位で一致（D-9）。I-08 を `SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` で実行 | 緩和済み |
| R-04 | 実 `UIPasteboard` を使うテストが CI で不安定 | テストの信頼性低下 | Data 層テストは `withUniqueName()` を使い general を触らない | 緩和済み |
| R-05 | `UIPasteControl` が Unity から使えない | Unity 利用者はプロンプトを回避できない | D-1 として明示し、Unity 側はプロンプト前提とすることをドキュメント化 | 受容 |
| R-06 | 一時ファイルが強制終了時に残る | ストレージ圧迫 | プロセス単位 1 回 + 24 時間経過 + 他セッション限定の cleanup（D-7）。U-57 / U-58 / M-12 で確認 | 緩和済み |
| R-07 | クリップボード値がログに出て情報漏洩 | 機微情報の露出 | `ClipboardLog` 経由に統一。U-61 / U-100 / M-15 で確認 | 緩和済み |
| R-08 | `localOnly` 既定 `true` が Android と挙動差 | クロスプラットフォームの体感差 | Android に対応概念がないため差分は不可避。マニュアルで iOS 固有オプションとして説明 | 受容 |
| R-09 | 画像を Domain へ持ち込まないための再エンコードが性能低下を招く | ペースト遅延 | エンコードは background executor（L-3）。M-13 で計測し、閾値超なら `imageDataUTType` のみ返す案へ切り替え | 要検証 |
| R-10 | `cancelled` を `isSuccess == false` とする扱いが Share の慣例と異なる | 利用者の混乱 | エラーコード表・DocC・Bridge ヘッダ・サンプルの 4 箇所で理由を明記 | 緩和済み |
| R-11 | Domain が `Foundation` に依存することが common.md と厳密には不整合 | ルール逸脱 | 例外理由を本設計に明記（既存 `ShareContent` の慣例、`UIKit` は持ち込まない境界は厳守）。common.md 側の追記要否はレビューで判断 | **要合意** |
| R-12 | Bridge の endpoint が 15 に増え、JSON schema の保守コストが上がる | 仕様ドリフト | U-97 で全 endpoint の schema をテストで固定し、schema 変更時にテストが落ちるようにする | 緩和済み |

---

## Definition of Done

### 実装

- [ ] `ios/IosLibrary/IosLibrary/Clipboard/` に Domain / Application / Data / Presentation / Manager が揃い、依存方向違反がない
- [ ] Application 層 Port の引数・戻り値にプラットフォーム型（`UIPasteboard` / `NSItemProvider` / `UTType` / `UIImage` / `UIColor`）が含まれない
- [ ] `NSItemProvider` を扱うコードが Data 層と Presentation 層に閉じている
- [ ] Domain 層が `UIKit` を import していない（`Foundation` の使用は R-11 の例外として合意済み）
- [ ] Domain が任意の system `Error` を保持せず、`ClipboardFailureDetail` へ正規化されている
- [ ] Port と実装の actor isolation が宣言単位で一致している
- [ ] 全 16 操作に対応する UseCase が存在し、Manager が Repository を直接呼んでいない
- [ ] `IosClipboardManager` が全 16 操作で callback 版と `async throws` 版を提供する
- [ ] callback 版のエラーが `(errorCode, errorMessage)` の 2 値で返る
- [ ] `changedNotification` / `removedNotification` のトークンを `IosClipboardManager` のみが保持する
- [ ] `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/` に Unity Bridge 層のみが存在する
- [ ] Bridge が `ClipboardError.errorCode` を透過し、message 解析やエラー判定ロジックを持たない
- [ ] 全 public シンボルに DocC コメント（英語）がある
- [ ] 全 `public` / `internal` / `override` / `@objc` 関数と Bridge C 関数の先頭に `Log.d` / `Log.e` がある
- [ ] クリップボード値・request JSON・Base64・パス・URL がログに出力されない
- [ ] Bridge `.m` の完了ブロック引数が `BOOL` / `NSString * _Nullable` である
- [ ] 同期 System API に対応する Repository / UseCase が `async` 化されていない（「方式維持の原則」準拠）
- [ ] 既存 Notification / Dialog / Share のファイルに変更がない

### 機能

- [ ] S1: 参照用 `PasteboardScope` と作成用 `PasteboardCreationRequest` が型分離され、境界ケース表どおりに動作する
- [ ] S2 / S3: 9 種の `ClipboardContent` と `localOnly` / `expirationDate` が動作する
- [ ] S4: `append` が options を受け取らず、追記として動作する
- [ ] S5: 同期読み取りと `readData` が動作する
- [ ] S6: text / url / image / file の非同期ロードが契約 6 点どおりに動作する
- [ ] S7: `ClipboardSnapshot` が公式の通知非対象 API のみで構成される
- [ ] S8: クリアと名前付き破棄が動作する
- [ ] S9: 変更 / 破棄イベントと foreground 差分検知が動作し、二重報告がない
- [ ] S10: パターン検出が動作し、`PartialKeyPath` / `DDMatch*` が公開 API に露出しない
- [ ] S11: `UIPasteControl` + 受信 View が集約契約 4 パターンどおりに動作する
- [ ] S12: 15 endpoint すべてが JSON schema どおりに動作する

### テスト

- [ ] 単体テスト U-01 〜 U-100 が全て green（Swift Testing、XCTest 不使用）
- [ ] 統合テスト I-01 〜 I-08 が全て green
- [ ] I-08 が `SWIFT_VERSION=6.0 SWIFT_STRICT_CONCURRENCY=complete` で警告・エラーなし
- [ ] Mock が `shouldFail` / per-method CallCount / `stubbedXxx` パターンに従う
- [ ] 実 `UIPasteboard` を使うテストが `general` を汚染しない
- [ ] `IosLibrary` / `UnityIosPlugin` の全スキームでテストが passed
- [ ] 手動確認 M-01 〜 M-15 を実施し、結果を記録した（M-01〜M-05 は T-00 で先行実施）

### ドキュメント

- [ ] `IosLibrary.docc/IosLibrary.md` に Clipboard セクションがある
- [ ] 名前付きペーストボードが非永続であること、永続共有は App Group shared container の責務であることを明記した
- [ ] `loadItem(.file)` / `onPaste` の `.file` の削除責務が呼び出し側にあることを明記した
- [ ] `read` / `readData` がプロンプト / 通知の対象になりうること、事前判定には `snapshot` を使うことを明記した
- [ ] `append` が privacy option を受け取らない理由を明記した
- [ ] `cancelled` を `isSuccess == false` として返す理由を明記した
- [ ] `PasteControlFactory` の receiver を view 階層へ追加する必要があることを明記した
- [ ] `docs/` 配下を変更していない

---

## 要検証事項（設計時点で未確定）

| 項目 | 内容 | 確認タイミング |
|---|---|---|
| `changeCount` の通知非対象性 | 対象なら D-3 と S9 を見直す | **T-00**（M-03） |
| `itemProviders` getter の契機 | 対象なら S6 の推奨経路を変更 | **T-00**（M-05） |
| 画像の Data 化コスト | 閾値超なら R-09 の代替案へ | T-13（M-13） |
| Swift 6 strict concurrency の残存警告 | 残る場合は追加の isolation 調整をタスク化 | T-11a（I-08） |
| Domain の `Foundation` 依存の可否 | common.md の例外として認めるか、common.md 側を追記するか | 本レビュー（R-11） |
| `expirationDate` の過去日時 | 本設計では拒否で確定。OS 実挙動と齟齬がないか確認 | T-11a / T-13 |

---

## レビュー反映履歴

対象レビュー: `artifact/reviews/clipboard/2026-08-02-ios-clipboard-design-review.md`

### 第 1 回レビュー反映（v2 / 2026-08-02）

| 優先度 | 指摘 | 反映内容 |
|---|---|---|
| 高 | `readData` が UseCase / Port / C ABI / JSON / テスト / タスクに存在しない | `ReadDataUseCase` と `ClipboardRepository.readData` を追加。Manager callback / async、`clipboardReadData` endpoint、成功・失敗 JSON schema、UTI 検証、U-25〜U-27 / U-44 / U-77 / I-01 / I-07 を追加し縦断させた |
| 高 | S11 の receiver が `[NSItemProvider]` を処理できる接続先を持たない | Presentation 層に `PasteItemProviderLoader` を新設し `NSItemProvider` を閉じ込めた。集約契約（成功 0 件 / 混在 / 順序 / コールバック回数 / token / 一時ファイル所有権）を確定し、U-62〜U-73 を追加 |
| 高 | Bridge の `errorCode` 変換経路が未定義。`readData` / `detectPatterns` が C ABI に無い。JSON が「抜粋」 | `ClipboardError.errorCode` を Domain に定義。Manager callback を `(Bool, errorCode, errorMessage)` に統一。Bridge は `async throws` を `Task { @MainActor }` で呼び 1 箇所で変換する方式を明記。15 endpoint 全ての request / success / error schema、NULL・未知 kind・Base64 不正・余分キーの規約、`invalidRequest` を追加 |
| 高 | Port が非隔離なのに実装が `@MainActor` で Swift 6 コンパイルエラー | 「actor 境界」表を新設し、Port / 実装 / UseCase / Presentation を `@MainActor`、Manager と純ロジックを nonisolated に統一。strict concurrency の検証コマンドを T-11a / I-08 に明記 |
| 高 | 同期・非同期のレイヤー対応表がない | 企画書の不足前提（L-1 / L-2）として明記した上で、「採用 System API の実行方式分類」と「同期・非同期レイヤー対応表」（P-1〜P-16 × 11 列）、「方式維持の原則」5 項目を新設。U-88 / I-08 と DoD に対応付けた |
| 高 | `localOnly` 既定 `true` と `addItems` のオプション非対応が矛盾 | `replaceExisting` を廃し、**append を独立 API（P-2）に分離**。`ClipboardCopyOptions` は copy 専用とし、Bridge でも `clipboardAppend` に `options` を渡すと `INVALID_REQUEST`。`optionsNotApplicableForAppend` エラーは不要になり削除 |
| 中 | `.unique(String)` を作成要求にも使っており未定義な境界がある | `PasteboardCreationRequest`（`.named` / `.unique`）を参照用 `PasteboardScope` から型分離。既存名・空名・`.general`・未作成破棄の境界を表で確定 |
| 中 | 入力検証の網羅と責務が不一致。UTI の逆 DNS 判定は標準 UTI を誤拒否 | 純粋検証（`ClipboardContentValidator`）と Data 依存検証（Data 層）に分離。UTI は `UTType(_:)` へ寄せ、`invalidColor` / `invalidImageData` / `invalidExpirationDate` / `invalidRequest` を追加。各エラーに発生元・コード・メッセージ・テスト ID を対応付けた |
| 中 | Domain の `Foundation` 依存と、任意 `Error` の保持 | `Foundation` 依存を例外として理由を明記（R-11 で要合意）。`ClipboardFailureDetail` を導入し system error を domain / code / message へ正規化 |
| 中 | provider URL ロードが無い。画像変換が `@MainActor` 上に見える | `ClipboardLoadRequest.url` を追加（L-4）。`ClipboardImageEncoder` を background executor として分離し（L-3）、変換後に main へ戻す旨を明記。U-59 を追加 |
| 中 | S11 / P-4 / P-9 / token cancel / Task cancel 競合 / 集約のテストが無い | U-25〜U-27、U-38、U-62〜U-73、U-77、U-78、U-85〜U-87、U-97 を追加。単体テストを 51 → 100 件に拡張 |
| 中 | 実機検証が T-13 まで遅い。T-08 が接続不能な T-06 に依存。T-14 が早すぎる | **T-00 プライバシー実機スパイク**を初期ゲートに新設。統合を T-11a（ライブラリ）と T-11b（Bridge）に分離。T-08 を S11 loader 設計確定後に配置。T-14 を全公開 API 確定後（T-10 / T-08 / T-12 依存）に移動 |
| 中 | 一時ファイル cleanup が他インスタンスの成功ファイルを消しうる | プロセス単位 1 回 + セッションディレクトリ + 24 時間経過 + 他セッション限定へ変更。U-57 / U-58（回帰）と M-12 を追加 |
| 低 | `expirationDate` の過去日時が非決定的 | 初期版で `expirationDate <= now` を `invalidExpirationDate` として**拒否**に確定。U-13 を追加 |
| 低 | ログ秘匿の実装手段と検査が無い | `ClipboardLog`（`redact` 群）を新設し、秘匿対象・非秘匿対象を列挙。既存 Share Bridge の JSON 全文ログを踏襲しない旨を明記。U-61 / U-100 / M-15 を追加 |
| 低 | Android とのエラーコード整合が曖昧 | 共通 4 コードを完全一致とし、Android 固有 3 種・iOS 固有 15 種を差異表で明示 |
