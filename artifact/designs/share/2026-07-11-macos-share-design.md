# macOS 共有（Share）機能 実装設計書

- 対象企画書: artifact/plans/share/2026-07-11-macos-share-research.md
- 対象OS: macOS 15 以降
- 使用言語: Swift（AppKit） / Objective-C（Bridge）
- 作成日: 2026-07-11
- 設計粒度: Detailed（関数・型・ファイル単位）

---

## 1. 設計目的

企画書で網羅した macOS 共有 API のうち、native-toolkit（Unity 向けネイティブプラグイン）の既存アーキテクチャに適合する範囲を、Clean Architecture に沿って実装可能な粒度まで設計する。

送信側（自アプリのコンテンツを共有先へ渡す）を AppKit の `NSSharingServicePicker`（ピッカー方式）と `NSSharingService`（個別サービス直接実行方式）で提供する。iOS の `Share`（`UIActivityViewController` ベース、実装済み）と機能パリティを取りつつ、macOS 固有の delegate 所有・anchor view・完了/キャンセル判定を吸収する。既存の `MacNotificationManager`（Clean Architecture フル構成）と `MacDialogManager`（AppKit プレゼンテーション / main 스レッド dispatch）のパターンを踏襲する。

---

## 2. スコープ（in / out）

### in（本設計の対象）

- 共有ピッカー表示（`NSSharingServicePicker` + `show(relativeTo:of:preferredEdge:)`）による送信
- 共有アイテム種別: テキスト / URL / 画像（ファイルパス）/ 任意ファイル（ファイルパス）
- ピッカーのサービス絞り込み（`NSSharingServicePickerDelegate.sharingServicesForItems`）と選択通知（`didChoose`）
- 個別サービスの直接実行（`NSSharingService(named:)` + `canPerform` + `perform`）と可否照会
- 個別サービスのメタ設定（書き込み可能な `recipients` / `subject`。本文・添付は items 側で表現）
- 完了ハンドリング（`NSSharingServiceDelegate` の willShare/didShare/didFailToShare を Manager 側 delegate で受ける）
- anchor view 解決（key window contentView フォールバック、`mouseDown` 起点制約の明示）
- Unity Bridge（Swift facade + Obj-C C ABI）

### out（本設計では扱わない。企画書からの意図的スコープ縮小）

| 項目 | 企画書での扱い | out とする理由 |
| --- | --- | --- |
| カスタム共有サービス `NSSharingService(title:image:alternateImage:handler:)`（S4） | in | `NSImage` と `() -> Void` handler を含み JSON/C ABI でシリアライズ不能。Unity Bridge から供給できないため本設計では未提供（ネイティブ API としては将来拡張余地に残す） |
| `standardShareMenuItem`（メニュー統合） | in（代替経路） | `NSMenu` を常設するホストアプリ向け。Unity ホストはメニューを自前で持たないため、ボタン起点ピッカーを優先。将来別タスク |
| ツールバー統合 `NSSharingServicePickerToolbarItem` | out（概要のみ） | 企画書同様、対象外 |
| 共同編集（Collaboration / iCloud 共有） | out（概要のみ） | 企画書同様、対象外 |
| 受信側（Share Extension） | out | 別ターゲット・別 entitlement。framework + Bridge 構成に統合不可 |
| `sharingServices(forItems:)`（S7） | 補助・非推奨 | deprecated のため主経路に採用しない。ピッカー + delegate で代替 |

注: 上記は企画書に新要件を追加するものではなく、toolkit アーキテクチャ適合のためのスコープ縮小である。out 項目はいずれも後続タスクで拡張可能な形にする。

補足（ピッカー方式の成立条件）: 主 API の `shareContent`（ピッカー方式）は `NSSharingServicePicker.show(...)` の `mouseDown` 起点制約に依存する。Unity Bridge 経由で安定表示できるかは実装 T5 で早期検証し、結果に応じて第 12 章「設計上の分岐」（A: ピッカー主経路 / B: 直接実行を主経路へ / C: `standardShareMenuItem` 追加）を確定する。分岐 B/C でも Domain〜Manager 層は不変で、Presentation と Bridge 公開範囲のみが変わる。

---

## 3. 共通実装方針の適用チェック（common.md 準拠）

| 方針 | 適用 | 反映内容 |
| --- | --- | --- |
| Clean Architecture 層・依存方向 | 適用 | Domain → Application → Data / Presentation → Manager → Bridge |
| Domain にプラットフォーム型を持ち込まない | 適用 | Domain は `String` / `URL`（Foundation）のみ。`NSSharingService` / `NSSharingServicePicker` / `NSView` / `NSImage` は Data・Presentation に隔離 |
| Port はドメイン型のみ | 適用 | `ShareRepository` は `ShareContent` / `ShareResult` / `ShareError` / `String`（serviceName raw）のみを使用。anchor（`NSView`/`NSRect`）は Port に載せず Presentation 内で解決 |
| Manager は UseCase 経由で Data へ | 適用 | `MacShareManager` → `SharePickerUseCase`/`ShareServiceUseCase`/`ShareServiceQueryUseCase` → `ShareRepository` |
| システム Delegate 所有は 1 クラス | 適用（macOS 適応） | `NSSharingServicePickerDelegate` / `NSSharingServiceDelegate` は Presentation の単一クラス `SharePickerPresenter` のみが実装・所有する。RepositoryImpl / Bridge には delegate を実装しない（common.md の趣旨に準拠。iOS はクロージャ完結だったが macOS は delegate が必須のため Presentation の 1 クラスに集約） |
| エラー変換経路 | 適用 | システムエラー → `ShareRepositoryImpl`/`SharePickerPresenter` → `ShareError` → `MacShareManager` → `(Bool, String?)` → Bridge |
| TDD（UseCase 単位、Swift Testing、Mock 注入） | 適用 | `MockShareRepository` を DI、`@Test`/`#expect`。XCTest は使わない |
| Unity Bridge を薄く保つ | 適用 | `UnityMacShareManager` は `MacShareManager` へ委譲するのみ |
| Minimum macOS 15 | 適用 | `close()` / `standardShareMenuItem`（13.0+）も使用可。15 未満向け分岐は設けない |

---

## 4. 個別実装方針の適用チェック（mac.md 準拠）

| 方針 | 適用 | 反映内容 |
| --- | --- | --- |
| 全メソッド先頭に全パラメータの `Log.d`/`Log.e` | 適用 | public / internal / @objc / override / Bridge C 関数すべてに付与 |
| Obj-C ブロック引数型（`BOOL`/`NSInteger`/`NSString* _Nullable`） | 適用 | Swift completion を Obj-C から呼ぶ箇所は `BOOL`。C ABI typedef は `bool`（両者を混同しない） |
| Manager の公開 API（callback 版 + async throws 版を最初から併設） | 適用 | `MacShareManager` は callback 版（`share(content:completion:)` 等、Bridge 向け）と `async throws` 版（`share(content:) async throws`/`shareViaService(...)`/`canPerform(...)`、`@discardableResult` 付き）を新規実装時点で両方用意する（第 7 章 S7）。サンプルアプリ（`MacLibraryExample`）は `async throws` 版を `Task { await ... }` で使う |
| public シンボルに DocC / 公開ヘッダに HeaderDoc | 適用 | public class/struct/enum/func に DocC、`.h` の関数・typedef に HeaderDoc |
| コメント・UI 文言は英語 | 適用 | エラーメッセージ・DocC 含め英語 |

---

## 5. 既存実装差分サマリー

- 新規モジュール `Share` を `MacLibrary` の `Notification` / `Dialog` と並列に追加する。既存コードへの破壊的変更はない。
- 追加先:
  - `mac/MacLibrary/MacLibrary/Share/` 配下（Domain/Application/Data/Presentation/Manager）
  - `mac/UnityMacPlugin/UnityMacPlugin/Share/` 配下（Bridge）
  - `mac/MacLibrary/MacLibraryTests/Share/` 配下（テスト）
- Xcode プロジェクトへのファイル追加（`MacLibrary.xcodeproj` / `UnityMacPlugin.xcodeproj`）が必要。
- 既存 `Common/Log.swift` を再利用する（新規追加しない）。
- `docs/` 配下は変更対象外。
- 破壊的変更: なし。

### 追加ファイル一覧（具体パス）

| 層 | ファイル |
| --- | --- |
| Domain | `mac/MacLibrary/MacLibrary/Share/Domain/Model/ShareItem.swift` |
| Domain | `mac/MacLibrary/MacLibrary/Share/Domain/Model/ShareContent.swift` |
| Domain | `mac/MacLibrary/MacLibrary/Share/Domain/Model/ShareResult.swift` |
| Domain | `mac/MacLibrary/MacLibrary/Share/Domain/Error/ShareError.swift` |
| Application | `mac/MacLibrary/MacLibrary/Share/Application/Port/ShareRepository.swift` |
| Application | `mac/MacLibrary/MacLibrary/Share/Application/UseCase/ShareUseCases.swift` |
| Data | `mac/MacLibrary/MacLibrary/Share/Data/Repository/ShareRepositoryImpl.swift` |
| Data | `mac/MacLibrary/MacLibrary/Share/Data/Converter/ShareItemConverter.swift` |
| Presentation | `mac/MacLibrary/MacLibrary/Share/Presentation/SharePickerPresenter.swift` |
| Manager | `mac/MacLibrary/MacLibrary/Share/MacShareManager.swift` |
| Bridge | `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareManager.swift` |
| Bridge | `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareJsonParser.swift` |
| Bridge | `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareManagerBridge.h` |
| Bridge | `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareManagerBridge.m` |
| Test | `mac/MacLibrary/MacLibraryTests/Share/ShareUseCasesTests.swift` |
| Test | `mac/MacLibrary/MacLibraryTests/Share/MacShareManagerTests.swift` |
| Test | `mac/MacLibrary/MacLibraryTests/Share/ShareErrorTests.swift` |
| Test | `mac/MacLibrary/MacLibraryTests/Share/ShareItemConverterTests.swift` |
| Test | `mac/MacLibrary/MacLibraryTests/Share/Mock/MockShareRepository.swift` |
| Test | `mac/UnityMacPlugin/UnityMacPluginTests/Share/UnityMacShareJsonParserTests.swift` |

---

## 6. 実装アーキテクチャ

```
Domain:        ShareItem, ShareContent, ShareResult, ShareError
                （service 名は raw String で扱い、専用 Domain 型は作らない）
                     │
Application:   ShareRepository(Port)
                   ← SharePickerUseCase / ShareServiceUseCase / ShareServiceQueryUseCase
                     │
Data:          ShareRepositoryImpl ──(uses)──▶ ShareItemConverter（ShareItem → [Any]）
                     │
Presentation:  SharePickerPresenter
                 （NSSharingServicePickerDelegate + NSSharingServiceDelegate を単独所有、
                   anchor view 解決 / show / didChoose・didShare・didFail → async）
                     │
Manager:       MacShareManager（singleton, 公開API, (Bool,String?)/result 変換）
                     │
Bridge:        UnityMacShareManager(Swift facade) + UnityMacShareManagerBridge(.h/.m)
                                                   + UnityMacShareJsonParser
```

### 制御フロー A: ピッカー方式（`shareContent`）

1. Bridge C 関数 `shareContent(...)` → `UnityMacShareManager.share(contentJson:handler:)`
2. facade が JSON を `ShareContent`（Domain）へ変換（`UnityMacShareJsonParser`）。パース失敗時は main で `handler(false,false,nil,"Invalid share content JSON.")`
3. `MacShareManager.share(content:completion:)` → `SharePickerUseCase.execute(content:)`（items 空チェック）
4. UseCase → `ShareRepository.presentPicker(content:)`
5. `ShareRepositoryImpl` が `ShareItemConverter` で `ShareItem` → `[Any]` を構築（throws `ShareError`）→ `SharePickerPresenter` に委譲
6. Presenter（`@MainActor`）が anchor view 解決 → `NSSharingServicePicker(items:)` 生成 → `delegate = self` → `show(relativeTo:of:preferredEdge:)`
7. delegate コールバック:
   - `sharingServicesForItems`: `excludedServiceTitles` に `title` が一致するサービスを best-effort 除外して返す
   - `didChoose(nil)`: ユーザーが未選択で閉じた → `ShareResult(completed:false, serviceName:nil)` で resume（キャンセル）
   - `didChoose(service)`: resume せず、`delegateFor` で自身を service delegate に設定して完了を待つ
   - `didShareItems`: `ShareResult(completed:true, serviceName:service.title)` で resume
   - `didFailToShareItems(error)`: cancel error は `completed:false`（キャンセル扱い）、その他は `ShareError.presentationFailed(error)` で resume
8. Presenter → Manager → `(Bool, String?, ...)` → Bridge callback（main thread）

### 制御フロー B: 個別サービス直接実行方式（`shareViaService`）

1. Bridge C 関数 `shareViaService(serviceName, contentJson, ...)` → facade → `MacShareManager.share(content:serviceName:completion:)`
2. `ShareServiceUseCase.execute(content:serviceName:)`（items 空チェック + serviceName 空チェック）
3. UseCase → `ShareRepository.performService(content:serviceName:)`
4. `ShareRepositoryImpl` が `NSSharingService(named:)` 生成（nil → `ShareError.serviceUnavailable`）→ `recipients`/`subject`（書き込み可能プロパティ）を設定 → `ShareItemConverter` で items 構築 → `canPerform` 判定（false → `serviceUnavailable`）→ `SharePickerPresenter` に service delegate を委譲 → `perform(withItems:)`
5. 完了は制御フロー A と同じく `NSSharingServiceDelegate` の didShare/didFail で resume

---

## 7. サブ機能別詳細設計

### S1. 共有アイテムのモデル化（Domain）

ファイル: `Share/Domain/Model/ShareItem.swift`

```swift
/// A single item to be shared through the macOS sharing service.
public enum ShareItem {
    /// Plain text.
    case text(String)
    /// A web or file URL, held as a raw string. Validated/parsed in the Data layer
    /// (invalid strings surface as `ShareError.invalidURL`).
    case url(String)
    /// An image located at a local file path.
    case imageFile(path: String)
    /// An arbitrary file located at a local file path.
    case file(path: String)
}
```

- 設計判断: `.url` は `URL` ではなく **raw `String`** を保持する。URL 妥当性検証は Data 層（`ShareItemConverter`）で行い、失敗を `ShareError.invalidURL` として到達可能にする（iOS Share と同一方針）。
- 共有アイテムは `String` / `URL`（web・file）/ `NSImage` を `perform`/`picker` の `items: [Any]` に渡す。service の扱いは用途で分かれる: **直接実行の `serviceName` は raw `NSSharingService.Name`（rawValue の文字列）**、**ピッカー除外は `excludedServiceTitles`（`NSSharingService.title` の表示名 best-effort 一致）** で通し、いずれも専用 Domain 型は作らない。

ファイル: `Share/Domain/Model/ShareContent.swift`

```swift
/// The full payload for a share invocation.
public struct ShareContent {
    /// Items to share (must be non-empty).
    public let items: [ShareItem]
    /// Recipients for direct-service mode (email/message). Ignored in picker mode.
    public let recipients: [String]
    /// Subject for direct-service mode (Mail etc.). Ignored in picker mode.
    public let subject: String?
    /// Service display titles to exclude from the picker (best-effort match against
    /// `NSSharingService.title`). Applied in picker mode only. See note below.
    public let excludedServiceTitles: [String]

    public init(items: [ShareItem],
                recipients: [String] = [],
                subject: String? = nil,
                excludedServiceTitles: [String] = [])
}
```

- 注: `recipients` / `subject` は書き込み可能プロパティ（`NSSharingService.recipients` / `.subject`）に対応。企画書 S5 の readonly（`messageBody` / `attachmentFileURLs`）はモデルに含めず、本文は `.text`、添付は `.file` として `items` で表現する。
- **サービス除外の設計判断（レビュー指摘反映）**: Xcode 26.3 SDK の `NSSharingService` インスタンスには raw `NSSharingService.Name` を読み出す公開メンバー（`name`）が存在しない（`xcrun swiftc -typecheck` で `value of type 'NSSharingService' has no member 'name'` を確認）。インスタンスから読み取れる識別子は `title`（表示名）のみのため、除外は **`title` に対する best-effort 一致**で行う。
  - 比較キー: `NSSharingService.title`（完全一致、大文字小文字区別あり）
  - 制約: `title` はローカライズされ得るため、環境（言語設定）依存で一致しない場合がある。**確実なサービス制御が必要な場合は、ピッカー方式（除外）ではなく個別サービス直接実行（`shareViaService`）を使う**方針とする
  - 検証: best-effort であることをテスト（比較ロジック）と手動確認（実 UI での非表示）で担保する
- anchor（表示基準 `NSView`/`NSRect`）は **プラットフォーム型のため Domain に含めない**。Presentation で解決する。

### S2. 結果・エラー（Domain）

ファイル: `Share/Domain/Model/ShareResult.swift`

```swift
/// The outcome of a share interaction.
public struct ShareResult {
    /// true if the user completed a service; false if cancelled.
    public let completed: Bool
    /// The chosen service's display name (`NSSharingService.title`), or nil (cancelled / unknown).
    public let serviceName: String?

    public init(completed: Bool, serviceName: String?)
}
```

- macOS には iOS の `completed` フラグ相当が無い（企画書リスク）。本設計では **`didChoose(nil)` = キャンセル**、**`didShareItems` = 完了(true)**、**`didFailToShareItems` の cancel error = キャンセル(false)** として `completed` を合成する。cancel error 判定は第 14 章の要検証項目。

ファイル: `Share/Domain/Error/ShareError.swift`（全ケースは第 8 章参照）

### S3. Port（Application）

ファイル: `Share/Application/Port/ShareRepository.swift`

```swift
/// Contract for presenting the macOS sharing UI / performing services.
/// Implemented by `ShareRepositoryImpl` in the Data layer.
public protocol ShareRepository {
    /// Presents the sharing service picker for the given content.
    /// - Throws: `ShareError` on failure before or during presentation.
    func presentPicker(content: ShareContent) async throws -> ShareResult

    /// Performs a single named sharing service directly.
    /// - Parameter serviceName: Raw `NSSharingService.Name` value (e.g. "com.apple.share.Mail.compose").
    /// - Throws: `ShareError` (`.serviceUnavailable` when the service is unknown or cannot perform).
    func performService(content: ShareContent, serviceName: String) async throws -> ShareResult

    /// Reports whether a named service can share the given content.
    /// - Returns: `true` if the service exists and `canPerform(withItems:)` is true.
    func canPerformService(content: ShareContent, serviceName: String) async throws -> Bool
}
```

- Port はドメイン型 + raw `String`（serviceName）のみ。`NSSharingService` / `NSView` は漏らさない。
- 3 メソッドはいずれも `async throws`（Presentation の delegate 完了を continuation で待つため）。

### S4. UseCase（Application）

ファイル: `Share/Application/UseCase/ShareUseCases.swift`

```swift
/// Presents the sharing service picker.
public struct SharePickerUseCase {
    private let TAG = "SharePickerUseCase"
    private let repository: ShareRepository
    public init(repository: ShareRepository)
    /// - Throws: `ShareError.noValidItems` when items is empty; otherwise repository errors.
    public func execute(content: ShareContent) async throws -> ShareResult {
        Log.d(TAG, "[execute] items: \(content.items.count)")
        guard !content.items.isEmpty else { throw ShareError.noValidItems }
        return try await repository.presentPicker(content: content)
    }
}

/// Performs a named sharing service directly.
public struct ShareServiceUseCase {
    private let TAG = "ShareServiceUseCase"
    private let repository: ShareRepository
    public init(repository: ShareRepository)
    /// - Throws: `ShareError.noValidItems` (empty items) / `.serviceUnavailable` (empty name),
    ///   otherwise repository errors.
    public func execute(content: ShareContent, serviceName: String) async throws -> ShareResult {
        Log.d(TAG, "[execute] serviceName: \(serviceName), items: \(content.items.count)")
        guard !content.items.isEmpty else { throw ShareError.noValidItems }
        guard !serviceName.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ShareError.serviceUnavailable(name: serviceName)
        }
        return try await repository.performService(content: content, serviceName: serviceName)
    }
}

/// Queries whether a named service can share the content (for button enable/disable).
public struct ShareServiceQueryUseCase {
    private let TAG = "ShareServiceQueryUseCase"
    private let repository: ShareRepository
    public init(repository: ShareRepository)
    public func canPerform(content: ShareContent, serviceName: String) async throws -> Bool {
        Log.d(TAG, "[canPerform] serviceName: \(serviceName), items: \(content.items.count)")
        guard !content.items.isEmpty else { return false }
        return try await repository.canPerformService(content: content, serviceName: serviceName)
    }
}
```

- 入力検証（items 空・serviceName 空）は UseCase に集約。各メソッド先頭に `Log.d` を付与済み（上記コード例に反映）。mac.md「全メソッド先頭に全パラメータの `Log.d`」に合わせ、本設計のコード例はログ付きの実装形とする。

### S5. Repository 実装 + Item Converter（Data）

ファイル: `Share/Data/Converter/ShareItemConverter.swift`

責務: `ShareItem` → 共有アイテム `[Any]` への変換 + 妥当性検証（UIKit/AppKit 依存の変換をここへ集約）。

```swift
/// Converts domain `ShareItem` values into AppKit share activation items.
struct ShareItemConverter {
    private let TAG = "ShareItemConverter"
    private let fileManager: FileManager
    init(fileManager: FileManager = .default)

    /// - Throws: `ShareError` on invalid URL, missing file, or unreadable image.
    func convert(_ items: [ShareItem]) throws -> [Any]
    // .text  -> String
    // .url   -> validated URL (http/https/file), else ShareError.invalidURL
    // .imageFile -> NSImage(contentsOfFile:) or ShareError.imageLoadFailed
    // .file  -> URL(fileURLWithPath:) if exists else ShareError.fileNotFound
}
```

- URL 検証は iOS Share と同一ルール:
  - 空文字・空白のみは不可
  - `url.scheme` を小文字化し許可 scheme（`http` / `https` / `file`）のいずれか
  - `http`/`https` は `url.host` が非 nil・非空
  - `file` は `url.isFileURL == true`
  - scheme なし・`ftp` 等は `ShareError.invalidURL`
- 画像は `NSImage(contentsOfFile:)`（iOS の `UIImage` に対応）。

ファイル: `Share/Data/Repository/ShareRepositoryImpl.swift`

```swift
/// Concrete `ShareRepository` backed by NSSharingServicePicker / NSSharingService.
///
/// - Note: Not `public` because its `presenter` parameter type (`SharePickerPresenting`) is an
///   internal Presentation-layer abstraction (AppKit dependency confined there).
final class ShareRepositoryImpl: ShareRepository {
    private let TAG = "ShareRepositoryImpl"
    private let presenter: SharePickerPresenting
    private let converter: ShareItemConverter
    init(presenter: SharePickerPresenting = SharePickerPresenter(),
         converter: ShareItemConverter = ShareItemConverter())

    func presentPicker(content: ShareContent) async throws -> ShareResult {
        Log.d(TAG, "[presentPicker] items: \(content.items.count), excluded: \(content.excludedServiceTitles.count)")
        let items = try converter.convert(content.items)
        return try await presenter.presentPicker(items: items,
                                                 excludedServiceTitles: content.excludedServiceTitles)
    }

    func performService(content: ShareContent, serviceName: String) async throws -> ShareResult {
        Log.d(TAG, "[performService] serviceName: \(serviceName), items: \(content.items.count)")
        let items = try converter.convert(content.items)
        return try await presenter.performService(items: items,
                                                  serviceName: serviceName,
                                                  recipients: content.recipients,
                                                  subject: content.subject)
    }

    func canPerformService(content: ShareContent, serviceName: String) async throws -> Bool {
        Log.d(TAG, "[canPerformService] serviceName: \(serviceName), items: \(content.items.count)")
        let items = try converter.convert(content.items)
        return await presenter.canPerform(items: items, serviceName: serviceName)
    }
}
```

- Repository は変換 + Presenter 委譲に徹する。`NSSharingService` の生成・`recipients`/`subject` 設定は Presenter 内で行い（AppKit 型を Presentation に閉じ込める）、Repository は raw `String`/`[String]` を渡す。

### S6. Presenter（Presentation, delegate 単独所有）

ファイル: `Share/Presentation/SharePickerPresenter.swift`

責務（AppKit 依存はここまで）:
- `NSSharingServicePickerDelegate` と `NSSharingServiceDelegate` を **この 1 クラスだけが実装・所有**する（common.md 準拠）
- anchor view 解決（`NSApp.keyWindow?.contentView`、無ければ `mainWindow`。いずれも無ければ `ShareError.noAnchorView`）
- `NSSharingServicePicker` 生成・`show(relativeTo:of:preferredEdge:)`
- 個別サービス `NSSharingService(named:)` 生成・`recipients`/`subject` 設定・`canPerform`・`perform`
- delegate コールバックを `async` へ橋渡し（`withCheckedThrowingContinuation`）

```swift
protocol SharePickerPresenting {
    func presentPicker(items: [Any], excludedServiceTitles: [String]) async throws -> ShareResult
    func performService(items: [Any], serviceName: String,
                        recipients: [String], subject: String?) async throws -> ShareResult
    func canPerform(items: [Any], serviceName: String) async -> Bool
}

@MainActor
final class SharePickerPresenter: NSObject, SharePickerPresenting,
                                  NSSharingServicePickerDelegate, NSSharingServiceDelegate {
    private let TAG = "SharePickerPresenter"

    // continuation state (accessed on main actor only)
    private var continuation: CheckedContinuation<ShareResult, Error>?
    private var excludedServiceTitles: [String] = []
    private var didChooseService = false   // guards picker-cancel vs service-completion

    // MARK: presentPicker
    func presentPicker(items: [Any], excludedServiceTitles: [String]) async throws -> ShareResult {
        Log.d(TAG, "[presentPicker] items: \(items.count), excluded: \(excludedServiceTitles.count)")
        guard let anchor = resolveAnchorView() else { throw ShareError.noAnchorView }
        self.excludedServiceTitles = excludedServiceTitles
        self.didChooseService = false
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let picker = NSSharingServicePicker(items: items)
            picker.delegate = self
            // NOTE: show() must be called within a mouseDown event context (see risk §12).
            picker.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        }
    }

    // MARK: performService (direct)
    func performService(items: [Any], serviceName: String,
                        recipients: [String], subject: String?) async throws -> ShareResult {
        Log.d(TAG, "[performService] serviceName: \(serviceName), items: \(items.count)")
        guard let service = NSSharingService(named: .init(serviceName)) else {
            throw ShareError.serviceUnavailable(name: serviceName)
        }
        service.delegate = self
        if !recipients.isEmpty { service.recipients = recipients }
        if let subject { service.subject = subject }
        guard service.canPerform(withItems: items) else {
            throw ShareError.serviceUnavailable(name: serviceName)
        }
        self.didChooseService = true
        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            service.perform(withItems: items)
        }
    }

    func canPerform(items: [Any], serviceName: String) async -> Bool {
        Log.d(TAG, "[canPerform] serviceName: \(serviceName), items: \(items.count)")
        guard let service = NSSharingService(named: .init(serviceName)) else { return false }
        return service.canPerform(withItems: items)
    }

    // MARK: single-resume guard
    private func resume(_ result: Result<ShareResult, Error>) {
        guard let cont = continuation else { return }
        continuation = nil
        cont.resume(with: result)
    }

    // MARK: NSSharingServicePickerDelegate
    func sharingServicePicker(_ p: NSSharingServicePicker, sharingServicesForItems items: [Any],
                              proposedSharingServices proposed: [NSSharingService]) -> [NSSharingService] {
        Log.d(TAG, "[sharingServicesForItems] proposed: \(proposed.count)")
        guard !excludedServiceTitles.isEmpty else { return proposed }
        // best-effort: NSSharingService exposes no raw name, only a (possibly localized) title.
        return proposed.filter { !excludedServiceTitles.contains($0.title) }
    }

    func sharingServicePicker(_ p: NSSharingServicePicker, didChoose service: NSSharingService?) {
        Log.d(TAG, "[didChoose] service: \(service?.title ?? "nil")")
        if let service {
            didChooseService = true
            // completion handled by NSSharingServiceDelegate (delegateFor supplies self)
        } else {
            resume(.success(ShareResult(completed: false, serviceName: nil)))   // cancelled
        }
    }

    func sharingServicePicker(_ p: NSSharingServicePicker,
                              delegateFor service: NSSharingService) -> NSSharingServiceDelegate? {
        Log.d(TAG, "[delegateFor] service: \(service.title)")
        return self
    }

    // MARK: NSSharingServiceDelegate
    func sharingService(_ s: NSSharingService, didShareItems items: [Any]) {
        Log.d(TAG, "[didShareItems] service: \(s.title)")
        resume(.success(ShareResult(completed: true, serviceName: s.title)))
    }

    func sharingService(_ s: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        Log.e(TAG, "[didFailToShareItems] service: \(s.title), error: \(error)")
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSUserCancelledError {
            resume(.success(ShareResult(completed: false, serviceName: s.title)))   // user cancelled
        } else {
            resume(.failure(ShareError.presentationFailed(error)))
        }
    }
}
```

- 単一 resume 規則（T4 完了条件に含める）:
  - `continuation` を nil にしてからのみ resume する（`resume(_:)` helper に集約）。全 delegate は `@MainActor` 上で実行されるため main isolation は保証される
  - `didChoose(nil)` はキャンセル、`didChoose(service)` は resume せず service delegate の完了を待つ
  - `didFailToShareItems` の `NSUserCancelledError` はキャンセル（`completed:false`）、その他は失敗
- anchor 解決フォールバック: `NSApp.keyWindow?.contentView ?? NSApp.mainWindow?.contentView`。両方 nil で `ShareError.noAnchorView`。
- 注意: `NSSharingServicePicker.show(...)` は `mouseDown` 起点前提（企画書リスク）。Bridge/Manager からの任意呼び出しは表示不安定リスクを残すため、第 12 章・第 14 章に明記し、サンプルアプリではボタン押下起点で検証する。

### S7. Manager（公開 API）

ファイル: `Share/MacShareManager.swift`

```swift
public final class MacShareManager: NSObject {
    private let TAG = "MacShareManager"
    public static let shared = MacShareManager()

    private let repository: ShareRepository
    private let pickerUseCase: SharePickerUseCase
    private let serviceUseCase: ShareServiceUseCase
    private let queryUseCase: ShareServiceQueryUseCase

    private override init() { /* DI: ShareRepositoryImpl */ }
    init(repository: ShareRepository) { /* test DI */ }

    /// Presents the sharing service picker (Bridge-facing callback form).
    /// - completion: (isSuccess, completed, serviceName, errorMessage)
    ///   * isSuccess: presentation succeeded (user could interact)
    ///   * completed: user finished a service (false = cancelled)
    ///   * serviceName: chosen service display name or nil
    ///   * errorMessage: set only when isSuccess == false
    public func share(content: ShareContent,
                      completion: ((Bool, Bool, String?, String?) -> Void)? = nil) {
        Log.d(TAG, "[share] items: \(content.items.count)")
        Task { @MainActor in
            do {
                let r = try await pickerUseCase.execute(content: content)
                completion?(true, r.completed, r.serviceName, nil)
            } catch {
                Log.e(TAG, "[share] error: \(error)")
                completion?(false, false, nil, (error as? ShareError)?.errorMessage ?? error.localizedDescription)
            }
        }
    }

    /// Performs a named service directly (Bridge-facing callback form).
    public func share(content: ShareContent, serviceName: String,
                      completion: ((Bool, Bool, String?, String?) -> Void)? = nil) {
        Log.d(TAG, "[share:service] serviceName: \(serviceName), items: \(content.items.count)")
        Task { @MainActor in
            do {
                let r = try await serviceUseCase.execute(content: content, serviceName: serviceName)
                completion?(true, r.completed, r.serviceName, nil)
            } catch {
                Log.e(TAG, "[share:service] error: \(error)")
                completion?(false, false, nil, (error as? ShareError)?.errorMessage ?? error.localizedDescription)
            }
        }
    }

    /// Native async form for pure-Swift callers (sample app). Surfaces typed `ShareError`.
    @discardableResult
    public func share(content: ShareContent) async throws -> ShareResult {
        Log.d(TAG, "[share:async] items: \(content.items.count)")
        return try await pickerUseCase.execute(content: content)
    }

    @discardableResult
    public func shareViaService(content: ShareContent, serviceName: String) async throws -> ShareResult {
        Log.d(TAG, "[shareViaService:async] serviceName: \(serviceName)")
        return try await serviceUseCase.execute(content: content, serviceName: serviceName)
    }

    /// Whether a named service can share the content (async, native).
    public func canPerform(content: ShareContent, serviceName: String) async throws -> Bool {
        Log.d(TAG, "[canPerform] serviceName: \(serviceName)")
        return try await queryUseCase.canPerform(content: content, serviceName: serviceName)
    }
}
```

- common.md「callback 版 + ネイティブ版の併設」に準拠。callback 版は Bridge 向け、`async throws` 版はサンプルアプリ等ネイティブ向け。
- ユーザーキャンセルはエラーではない（`isSuccess=true, completed=false`）。企画書 DoD「キャンセルと失敗を区別」を満たす。

### S8. Unity Bridge

ファイル: `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareManager.swift`（Swift facade, `@objcMembers`）

```swift
@objcMembers
public class UnityMacShareManager: NSObject {
    private let TAG = "UnityMacShareManager"
    public static let shared = UnityMacShareManager()
    private let parser = UnityMacShareJsonParser()

    /// Presents the sharing picker from a JSON content string.
    /// - handler: (isSuccess, completed, serviceName, errorMessage). Always invoked on main thread.
    public func share(contentJson: String, handler: ((Bool, Bool, String?, String?) -> Void)?) {
        Log.d(TAG, "[share] contentJson: \(contentJson)")
        guard let content = parser.parseContent(from: contentJson) else {
            Log.e(TAG, "[share] failed to parse content JSON")
            DispatchQueue.main.async { handler?(false, false, nil, "Invalid share content JSON.") }
            return
        }
        MacShareManager.shared.share(content: content, completion: handler)
    }

    /// Performs a named service directly from a JSON content string.
    public func shareViaService(serviceName: String, contentJson: String,
                                handler: ((Bool, Bool, String?, String?) -> Void)?) {
        Log.d(TAG, "[shareViaService] serviceName: \(serviceName), contentJson: \(contentJson)")
        guard let content = parser.parseContent(from: contentJson) else {
            Log.e(TAG, "[shareViaService] failed to parse content JSON")
            DispatchQueue.main.async { handler?(false, false, nil, "Invalid share content JSON.") }
            return
        }
        MacShareManager.shared.share(content: content, serviceName: serviceName, completion: handler)
    }
}
```

ファイル: `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareJsonParser.swift`

- 期待 JSON:
  ```json
  {
    "items": [
      { "type": "text",  "value": "hello" },
      { "type": "url",   "value": "https://example.com" },
      { "type": "image", "value": "/path/to.png" },
      { "type": "file",  "value": "/path/to.pdf" }
    ],
    "recipients": ["a@example.com"],
    "subject": "optional",
    "excludedServiceTitles": ["Add to Reading List"]
  }
  ```
- `type` → `ShareItem`: `text`→`.text`, `url`→`.url(value)`（**文字列のまま保持**、妥当性は Data 層）, `image`→`.imageFile(path:)`, `file`→`.file(path:)`。
- 未知 `type` は無視、`value` 欠落エントリも無視（エラーではない）。全無視で items 空なら `ShareContent(items: [])` を返し、UseCase 側で `noValidItems`。
- `excludedServiceTitles` は `NSSharingService.title` への best-effort 一致（表示名ベース。ローカライズ依存の制約は S1 の注記参照）。
- エラー責務の分離（iOS Share と同一）:
  - Parser: JSON 構文不正のみ（`nil` → Bridge が `"Invalid share content JSON."`）
  - Data 層: `invalidURL` / `imageLoadFailed` / `fileNotFound`
  - UseCase: `noValidItems` / `serviceUnavailable`（空名）

ファイル: `mac/UnityMacPlugin/UnityMacPlugin/Share/UnityMacShareManagerBridge.h` / `.m`（C ABI）

```c
/// Callback for a share interaction.
/// - isSuccess: presentation/perform succeeded (user could interact). false = error.
/// - completed: user finished a service. false = cancelled.
/// - serviceName: chosen service display name, or NULL if cancelled/unknown.
/// - errorMessage: NULL unless isSuccess=false.
typedef void (*ShareCallback)(bool isSuccess,
                              bool completed,
                              const char* serviceName,
                              const char* errorMessage);

/// Presents the sharing service picker.
/// - contentJson: UTF-8 JSON (required, non-NULL).
void shareContent(const char* contentJson, ShareCallback callback);

/// Performs a single named sharing service directly.
/// - serviceName: raw NSSharingService.Name value (required, non-NULL).
/// - contentJson: UTF-8 JSON (required, non-NULL).
void shareViaService(const char* serviceName, const char* contentJson, ShareCallback callback);
```

- `.m` は既存 `UnityMacDialogManagerBridge.m` と同様、`NSString` 変換 → `[[UnityMacShareManager shared] shareWithContentJson:handler:]` 呼び出し → callback へ C 文字列変換。Swift completion block を Obj-C から呼ぶため block 引数は `BOOL`（`bool` 不可）、C ABI typedef は `bool`。各 C 関数先頭に `[Log d:TAG ...]`。

---

## 8. ドメインエラー一覧（全ケース）

ファイル: `Share/Domain/Error/ShareError.swift`

```swift
/// Errors that can occur during a share operation.
public enum ShareError: Error {
    /// No shareable items were provided (empty or all invalid).
    case noValidItems
    /// A shared URL string could not be parsed.
    case invalidURL(String)
    /// The image at the given path could not be loaded.
    case imageLoadFailed(path: String)
    /// The file at the given path does not exist.
    case fileNotFound(path: String)
    /// No key window / view was available to anchor the sharing picker.
    case noAnchorView
    /// The requested named service is unknown or cannot share the items.
    case serviceUnavailable(name: String)
    /// The share failed or completed with a system error.
    case presentationFailed(Error)
    /// An unknown error occurred.
    case unknown(Error)

    public var errorCode: Int { /* 第 9 章の表 */ }
    public var errorMessage: String { /* 第 9 章の表（英語） */ }
}
```

- `LocalizedError` 準拠で `errorDescription` に `errorMessage` を返す。
- `errorCode` は mac Notification（`NotificationDomainError`）の慣習に合わせて数値コードを提供（ログ/将来のコード返却用）。現行 Bridge は文字列メッセージ方式（iOS Share と統一）で返却する。
- ユーザーキャンセルは **エラーに含めない**（`ShareResult.completed == false` で表現）。

## 9. エラーコード/メッセージ対応表（Bridge 返却仕様）

Manager callback は `(isSuccess, completed, serviceName, errorMessage)`。`errorMessage` は `isSuccess == false` のときのみ非 nil。`errorCode` は `ShareError` が保持し、ログ/将来利用向けに定義する。

| ケース | ShareError | errorCode | isSuccess | completed | serviceName | errorMessage（英語） |
| --- | --- | --- | --- | --- | --- | --- |
| 共有完了 | — | 0 | true | true | 選択 service 名 | nil |
| ユーザーキャンセル（picker 未選択） | — | 0 | true | false | nil | nil |
| ユーザーキャンセル（service 内で中断） | — | 0 | true | false | service 名 | nil |
| items 空/全無効 | `noValidItems` | 1401 | false | false | nil | "No shareable items were provided." |
| URL 不正 | `invalidURL` | 1402 | false | false | nil | "Invalid URL: \<value\>." |
| 画像読込失敗 | `imageLoadFailed` | 1403 | false | false | nil | "Failed to load image at path: \<path\>." |
| ファイル不在 | `fileNotFound` | 1404 | false | false | nil | "File not found at path: \<path\>." |
| anchor（window/view）なし | `noAnchorView` | 1405 | false | false | nil | "No key window available to anchor the sharing picker." |
| サービス不明/実行不可 | `serviceUnavailable` | 1406 | false | false | nil | "Sharing service unavailable: \<name\>." |
| 共有/システム失敗 | `presentationFailed` | 1407 | false | false | nil | "Failed to share: \<detail\>." |
| 不明なエラー | `unknown` | 1499 | false | false | nil | "An unknown share error occurred: \<detail\>." |
| JSON 不正（Bridge） | —（Parser） | — | false | false | nil | "Invalid share content JSON." |

注: 数値エラーコードは既存 Share Bridge（iOS）が未採用のため、Bridge callback は文字列メッセージで統一する。`errorCode` は診断・将来のコード返却互換のために定義する。

---

## 10. テスト設計

フレームワーク: Swift Testing（`@Test` / `#expect`）。XCTest は使わない。Mock は `ShareRepository` を実装し UseCase / Manager に DI。

ファイル: `MacLibraryTests/Share/Mock/MockShareRepository.swift`

```swift
final class MockShareRepository: ShareRepository {
    var shouldFail = false
    var errorToThrow: ShareError = .noAnchorView
    var presentPickerCallCount = 0
    var performServiceCallCount = 0
    var lastContent: ShareContent?
    var lastServiceName: String?
    var stubbedResult = ShareResult(completed: true, serviceName: "Mail")
    var stubbedCanPerform = true

    func presentPicker(content: ShareContent) async throws -> ShareResult {
        presentPickerCallCount += 1; lastContent = content
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }
    func performService(content: ShareContent, serviceName: String) async throws -> ShareResult {
        performServiceCallCount += 1; lastContent = content; lastServiceName = serviceName
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }
    func canPerformService(content: ShareContent, serviceName: String) async throws -> Bool {
        if shouldFail { throw errorToThrow }
        return stubbedCanPerform
    }
}
```

### 単体テスト

`ShareUseCasesTests`:
- `SharePickerUseCase` 正常系: presentPicker が 1 回呼ばれ stubbedResult を返す / 異常系: shouldFail で伝播 / 境界: items 空 → `noValidItems`（present 呼ばれない）
- `ShareServiceUseCase` 正常系 / serviceName 空 → `serviceUnavailable` / items 空 → `noValidItems`
- `ShareServiceQueryUseCase` canPerform: stubbedCanPerform を返す / items 空 → false

`MacShareManagerTests`（repository DI）:
- picker 完了: `(true, true, "Mail", nil)`
- picker キャンセル: stubbedResult.completed=false → `(true, false, nil, nil)`
- 失敗: shouldFail → `(false, false, nil, errorMessage)`（`ShareError.errorMessage` と一致）
- direct service 完了 / serviceName 空 → 失敗メッセージ

`ShareErrorTests`:
- 各ケースの `errorCode` / `errorMessage`（英語）が第 9 章の表通りであること

`ShareItemConverterTests`（Data 層変換）:
- `.url` 検証: `https://host`・`http://host`・`file:///path` は成功 / 空文字・空白のみ・scheme なし（`example.com`）・host なし（`https://`）・`ftp://host` は `invalidURL`
- `.file(path)` 存在パス → `URL` / 不在パス → `fileNotFound`
- `.imageFile(path)` 不正パス → `imageLoadFailed`
- `.text` → `String` そのまま
- 変換順序が入力順を保持すること

`UnityMacShareJsonParserTests`（UnityMacPluginTests/Share）:
- 4 種 type パース、未知 type / value 欠落の無視、全無視時の空 items
- `recipients` / `subject` / `excludedServiceTitles` の反映
- `url` type は `.url(String)`（未検証文字列）として保持されること
- JSON 構文不正 → nil

注: `SharePickerPresenter` は `NSSharingServicePicker`/`NSSharingService` の実 UI・システム delegate に依存するため単体テスト対象外とし、`SharePickerPresenting` を Mock 化して上位層を検証する。Presenter 自体は手動確認で担保する。

### 統合テスト / 手動確認（実機）

企画書リスクに対応:
- ボタン押下（`mouseDown` 起点）でピッカーが表示される（リスク: mouseDown 起点前提 / anchor 必須）
- テキスト / URL / 画像 / ファイルの各共有先（Mail / メッセージ / AirDrop / メモ / コピー）で内容が正しい
- `excludedServiceTitles`（表示名 best-effort）指定でサービスが非表示。ローカライズ環境では一致しない場合があることを確認
- 直接実行（`shareViaService` で `.composeEmail`）で `recipients` / `subject` が反映される
- ピッカーを未選択で閉じると `completed=false`、共有完了で `completed=true`
- サービス内（Mail compose 等）でキャンセルすると `completed=false`（`didFailToShareItems` の cancel error 判定 → 第 14 章要検証）
- 存在しない画像/ファイルパスで適切なエラー
- メインスレッド以外から呼んでも main で表示・コールバックされる

---

## 11. 実装タスク分解（依存関係付き）

| # | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
| --- | --- | --- | --- | --- | --- |
| T1 | Domain 定義（ShareItem/ShareContent/ShareResult。service 名は raw String） | 0.5日 | なし | 型がコンパイル、DocC 付与 | Domain がプラットフォーム非依存、anchor を含めない |
| T2 | ShareError 定義 + errorCode/errorMessage + LocalizedError | 0.5日 | なし | 全ケース + 英語メッセージ、ShareErrorTests green | 第 9 章表と一致 |
| T3 | Port + 3 UseCase + 入力検証 | 0.5日 | T1,T2 | ShareUseCasesTests green（正常/異常/境界） | Port がドメイン型 + raw String のみ |
| T4 | ShareItemConverter（変換 + URL/file/image 検証） | 0.5日 | T1,T2 | ShareItemConverterTests green | エラー変換の集約 |
| T5 | SharePickerPresenter（delegate 単独所有 / anchor / picker / direct / continuation） | 2.0日 | T1,T2 | 実機でピッカー表示・直接実行、**continuation を必ず 1 回だけ resume（didChoose(nil)=cancel, didShare=完了, didFail の cancel error 判定）**、delegate はこの 1 クラスのみ、**`show()` を `mouseDown` イベント文脈で呼んだ場合の安定表示を早期検証（第 12 章の分岐判断を確定）** | AppKit 隔離、delegate 所有、二重 resume なし、mouseDown/anchor 前提の検証結果が記録されている |
| T6 | ShareRepositoryImpl（変換 + Presenter 委譲） | 0.5日 | T3,T4,T5 | presentPicker/performService/canPerform が Presenter を呼ぶ | AppKit 型を Presentation に閉じ込め |
| T7 | MacShareManager（callback 版 + async 版、キャンセル/失敗区別） | 0.5日 | T3,T6 | MacShareManagerTests green | UseCase 経由、callback/native 併設 |
| T8 | Unity Bridge（Swift facade + JsonParser + .h/.m） | 1.0日 | T7 | **Unity Bridge 経由でピッカーが `mouseDown` 制約を満たして安定表示できること**（満たせない場合は第 12 章の代替分岐を採用）、Parser テスト green | Bridge は委譲のみ。**C ABI typedef は `bool`、Obj-C から呼ぶ Swift completion block は `BOOL`**。mouseDown 制約の検証結果が完了条件に反映されている |
| T9 | Xcode プロジェクトへのファイル追加・ビルド確認 | 0.5日 | T1–T8 | 両ターゲット（MacLibrary / UnityMacPlugin）ビルド成功、全テスト green | ターゲット所属の正しさ |
| T10 | サンプルアプリ検証（design-sample-app で実装） | - | T8 | 共有機能をボタン起点で手動確認できる導線が動作 | ※具体パスは design-sample-app で定義 |

先行（基盤）: T1–T4。後続（拡張）: T5–T9。T10 は別 workflow（design-sample-app / implement-sample-app）。

---

## 12. リスクと緩和策

| リスク | 緩和策 | 対応タスク |
| --- | --- | --- |
| `show(relativeTo:)` は `mouseDown` 起点前提。Unity Bridge の `shareContent` を通常呼び出しした際に AppKit の `mouseDown` 文脈内である保証がなく、対象環境でピッカーが安定表示できない恐れ | **T5 で早期検証し、以下の分岐で確定する（下記「設計上の分岐」）。** Manager/Bridge のドキュメントに「ユーザー操作起点で呼ぶこと」を明記。完了条件は T5/T8 に引き上げ済み | T5,T8 |
| **（実装時に判明した具体リスク）** `MacShareManager.share(content:completion:)` / `share(content:serviceName:completion:)` は内部で `Task { @MainActor in ... }` を経由してから picker/service を呼ぶ。この `Task {}` の生成は、たとえ呼び出し元が実際の mouseDown ハンドラ内・main thread から同期的に呼んでいたとしても、Swift ランタイムが同一コールスタック上で同期実行することを保証しない。したがって callback 版 API 経由の picker 表示は、意図せず mouseDown コンテキストから外れて呼ばれる可能性が構造的に残る | 実装済みの `MacShareManager` の DocC コメントに本リスクを明記。実機での対話的クリック検証（Accessibility 権限を要する UI 自動化）がサンドボックス環境で実施できなかったため、**分岐 A（ピッカー主経路のまま）を実証的には確定できていない**。安全側として、確実性が必要な呼び出し元には直接実行（`shareViaService`）を推奨する運用（分岐B相当の注意喚起）を採用し、ピッカー方式は「実機での目視確認が済むまで best-effort」として DoD 上も明記する | T5,T8（要実機再検証） |
| anchor view（key window/contentView）が無いと表示不可 | `NSApp.keyWindow ?? mainWindow` フォールバック、両方 nil で `noAnchorView` エラー化 | T5 |
| 完了/キャンセルの区別が API で不明瞭 | `didChoose(nil)`=cancel、`didShare`=完了、`didFail` の `NSUserCancelledError`=cancel として合成。要検証項目に残す | T5 |
| continuation の二重 resume / 未 resume | `continuation` を nil 化してから resume する helper に集約。全 delegate は `@MainActor` で main isolation 保証 | T5 |
| メインスレッド以外からの UI 操作 | Presenter を `@MainActor`、Manager の Task を `@MainActor` に固定 | T5,T7 |
| `messageBody`/`attachmentFileURLs` は readonly（企画書指摘） | モデルに含めず本文=`.text`・添付=`.file` として items で表現 | T1,T4 |
| 画像/ファイルパス不正 | Data 層で存在チェックし `ShareError` 化、テストで異常系 | T4,T2 |
| サービス環境依存（AirDrop 等が非表示） | 除外/非表示は環境依存として手動確認前提。`canPerform` で活性判定 | T5,T10 |
| ピッカーのサービス除外が best-effort（`NSSharingService` に raw name 非公開、`title` はローカライズ依存） | 除外は `title` 一致の best-effort と割り切り、確実な制御は直接実行（`shareViaService`）へ誘導。制約を DoD・API ドキュメントに明記し、実 UI で非表示を手動確認 | T5,T10 |
| サンドボックス/entitlement 依存 | ファイル共有・AirDrop の entitlement 要否は要検証（第 14 章）。配布形態別に手動確認 | T10 |
| カスタムサービス（S4）未提供 | Bridge では未提供と明記。将来ネイティブ API として `NSSharingService(title:image:...:handler:)` を追加できる構造に留める | 将来 |
| Unity JSON 不正 | Parser が nil を返し `(false,...,"Invalid share content JSON.")` | T8 |

### 設計上の分岐（`mouseDown` 制約の T5 検証結果に応じて確定）

T5 で「Unity Bridge 経由の通常呼び出し（ボタン起点）で `NSSharingServicePicker.show(...)` が安定表示できるか」を早期検証し、結果に応じて以下を採用する。分岐の採否と根拠を設計/実装結果に記録する。

- **分岐A（安定表示できる）**: 本設計のまま `shareContent`（ピッカー方式）を主 API として提供する。Bridge ドキュメントに「ユーザー操作イベント起点で呼ぶこと」を明記。
- **分岐B（不安定だが直接実行は可）**: ピッカー方式を「ベストエフォート（ユーザー操作起点必須）」に格下げし、**個別サービス直接実行（`shareViaService`）を確実な主経路として先行提供**する。ピッカーはサンプルアプリのボタン起点導線に限定。
- **分岐C（ピッカーがどうしても不安定）**: `standardShareMenuItem`（macOS 13.0+、メニュー統合）を用いる代替 API を追加検討する。ネイティブ側でボタン/ビューを所有し `mouseDown` 文脈を確保する方式を設計に追加する（別タスク化）。

いずれの分岐でも、Domain/Application/Data/Manager 層は不変で、差し替わるのは Presentation（`SharePickerPresenter`）と Bridge 公開範囲のみとなるよう設計している。

---

## 13. Definition of Done

### 実装・テスト

- [ ] `Share` モジュールが Clean Architecture 層構成で追加されている（Domain/Application/Data/Presentation/Manager/Bridge）
- [ ] Port はドメイン型 + raw String のみ、AppKit 型（`NSSharingService`/`NSView`/`NSImage`）が Domain/Application に漏れていない
- [ ] `NSSharingServicePickerDelegate` / `NSSharingServiceDelegate` は `SharePickerPresenter` の 1 クラスのみが実装している
- [ ] 全 public/internal/@objc/override/Bridge 関数に先頭 `Log.d`/`Log.e` が付与されている
- [ ] `ShareError` 全ケースと errorCode/英語メッセージが第 9 章の表と一致する
- [ ] UseCase / Manager / Parser / Error / Converter の単体テストが green（正常・異常・境界）
- [ ] 両ターゲット（MacLibrary / UnityMacPlugin）がビルド成功

### 動作（実機）

- [ ] ボタン押下起点でピッカーを表示でき、テキスト / URL / 画像 / ファイルを共有できる
- [ ] Mail / メッセージ / AirDrop / メモ / コピー の各共有先で内容が正しい
- [ ] `excludedServiceTitles`（`NSSharingService.title` best-effort 一致）でサービスを除外できる。確実な制御が必要な場合は直接実行（`shareViaService`）で代替できる
- [ ] 直接実行（`shareViaService`）で `recipients` / `subject` が反映される
- [ ] ピッカー未選択（cancel）と共有完了（completed=true）、サービス内キャンセルを区別できる
- [ ] メインスレッドで表示・コールバックされる
- [ ] Unity Bridge 経由で共有を起動でき、結果コールバックが返る

---

## 14. 要検証（断定を避けた項目）

- `NSSharingServiceDelegate.didFailToShareItems:error:` の `error` が「ユーザーキャンセル」を表す具体的な domain/code（`NSCocoaErrorDomain` / `NSUserCancelledError` で判定できるか）。判定が異なる場合はマッピングを修正
- `NSSharingServicePicker.show(...)` を Unity/native bridge から `mouseDown` イベント外で呼んだ際の表示安定性。不安定なら `standardShareMenuItem`（メニュー統合）または明示的なイベント連携へ設計変更
- **（未解決・実装完了時点でも未検証）** `MacShareManager.share(content:completion:)` 内部の `Task { @MainActor in ... }` 経由呼び出しが、実際のボタン mouseDown ハンドラから呼ばれた場合でも `NSSharingServicePicker.show(...)` の mouseDown コンテキスト要件を満たすか。実装レビュー時点でサンドボックス環境に Accessibility 権限（System Events による UI 自動操作）が無く、実機での対話的クリック検証ができなかったため未確定。**出荷前に実 Mac 実機・実ユーザー操作でのボタン押下 → ピッカー表示確認が必須**。不安定と判明した場合は設計第12章の分岐B（`shareViaService` を主経路に）へ切替える
- サンドボックス App でのファイル共有（`.file`）・AirDrop に必要な entitlement / security-scoped resource の要否（配布形態別）
- picker の完了/キャンセルを `didChoose` だけで判定できるか、`NSSharingServiceDelegate` 併用が本設計通り必要か（実機で delegate 発火順を確認）
- 各サンプルコードを Xcode（macOS 15 / Swift）で typecheck し、delegate selector 名・プロパティ read/write 区分にコンパイルエラーがないこと（T5 着手前）
