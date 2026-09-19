# iOS 共有（Share）機能 実装設計書

- 対象企画書: artifact/plans/share/2026-07-04-ios-share-research.md
- 対象OS: iOS 18 以降
- 使用言語: Swift / Objective-C（Bridge）
- 作成日: 2026-07-04
- 設計粒度: Detailed（関数・型・ファイル単位）

---

## 1. 設計目的

企画書で網羅した iOS 共有 API のうち、native-toolkit（Unity 向けネイティブプラグイン）の既存アーキテクチャに適合する範囲を、Clean Architecture に沿って実装可能な粒度まで設計する。

送信側（自アプリのコンテンツを共有シート経由で他アプリへ渡す）を `UIActivityViewController` ベースで提供する。既存の `Notification`（Clean Architecture フル構成）と `Dialog`（UIKit プレゼンテーション / root VC 解決）のパターンを踏襲する。

---

## 2. スコープ（in / out）

### in（本設計の対象）

- 共有シート表示（`UIActivityViewController`）による送信
- 共有アイテム種別: テキスト / URL / 画像（ファイルパス） / 任意ファイル（ファイルパス）
- 共有先の除外（`excludedActivityTypes`）
- 完了ハンドリング（選択 activityType / 完了・キャンセル・失敗の区別）
- iPad popover 対応（root VC 中央フォールバック、既存 Dialog と同方針）
- リッチプレビュー（`LPLinkMetadata` / `UIActivityItemSource`）
- Unity Bridge（Swift facade + Obj-C C ABI）

### out（本設計では扱わない。企画書からの意図的スコープ縮小）

| 項目 | 企画書での扱い | out とする理由 |
| --- | --- | --- |
| SwiftUI `ShareLink` / `Transferable` | in | Unity ホストは UIKit ベース。`UIActivityViewController` で要件を満たすため二重提供しない |
| Share Extension（受信側） | in | 別 App Extension ターゲット + App Group + 独自 entitlement が必要で、`IosLibrary` framework + Unity Bridge の構成に統合できない。将来別タスクとして切り出す |
| 共同編集（Collaboration mode） | out（概要のみ） | 企画書同様、対象外 |
| iOS 18 宛先プリフィル（`activityViewControllerShareRecipients`） | in（要検証付き） | `INPerson`（Intents）依存で Unity 連携の需要が薄い。将来拡張余地として API 予約のみ（本設計では未実装、要検証） |

注: 上記は企画書に新要件を追加するものではなく、toolkit アーキテクチャ適合のためのスコープ縮小である。out 項目はいずれも後続タスクで拡張可能な形にする。

---

## 3. 共通実装方針の適用チェック（common.md 準拠）

| 方針 | 適用 | 反映内容 |
| --- | --- | --- |
| Clean Architecture 層・依存方向 | 適用 | Domain → Application → Data / Presentation → Manager → Bridge |
| Domain にプラットフォーム型を持ち込まない | 適用 | Domain は `String` / `URL`（Foundation）のみ。`UIImage` / `UIActivityViewController` は Data・Presentation に隔離 |
| Port はドメイン型のみ | 適用 | `ShareRepository` は `ShareContent` / `ShareResult` / `ShareError` のみを使用 |
| Manager は UseCase 経由で Data へ | 適用 | `IosShareManager` → `ShareContentUseCase` → `ShareRepository` |
| Delegate 所有は Manager の 1 クラス | 適用 | 本機能は永続 Delegate を持たない（`completionWithItemsHandler` はクロージャで完結）。root VC 解決は Presentation の `ShareSheetPresenter` に隔離 |
| エラー変換経路 | 適用 | システムエラー → `ShareRepositoryImpl` → `ShareError` → `IosShareManager` → `(Bool, String?)` → Bridge |
| TDD（UseCase 単位、Swift Testing、Mock 注入） | 適用 | `MockShareRepository` を DI、`@Test`/`#expect` |
| Unity Bridge を薄く保つ | 適用 | `UnityIosShareManager` は `IosShareManager` へ委譲するのみ |
| Minimum iOS 18 | 適用 | `allowsProminentActivity`(15.4+) 等は 18 で問題なし。18 固有 API は使用しない |

---

## 4. 個別実装方針の適用チェック（ios.md 準拠）

| 方針 | 適用 | 反映内容 |
| --- | --- | --- |
| 全メソッド先頭に全パラメータの `Log.d`/`Log.e` | 適用 | public / internal / @objc / Bridge C 関数すべてに付与 |
| Obj-C ブロック引数型（`BOOL`/`NSInteger`/`NSString* _Nullable`） | 適用 | Bridge callback は `BOOL isSuccess` を使用 |
| public シンボルに DocC | 適用 | public class/struct/enum/func に付与 |
| コメント・UI 文言は英語 | 適用 | エラーメッセージ含め英語 |

---

## 5. 既存実装差分サマリー

- 新規モジュール `Share` を `Notification` / `Dialog` と並列に追加する。既存コードへの破壊的変更はない。
- 追加先:
  - `ios/IosLibrary/IosLibrary/Share/` 配下（Domain/Application/Data/Presentation/Manager）
  - `ios/UnityIosPlugin/UnityIosPlugin/Share/` 配下（Bridge）
  - `ios/IosLibrary/IosLibraryTests/Share/` 配下（テスト）
- Xcode プロジェクトへのファイル追加（`IosLibrary.xcodeproj` / `UnityIosPlugin.xcodeproj`）が必要。`.docc` への追記は任意。
- `docs/` 配下は変更対象外。
- 破壊的変更: なし。

---

## 6. 実装アーキテクチャ

```
Domain:        ShareItem, ShareContent, ShareResult, ShareError
                （activity type は raw String で扱い、専用 Domain 型は作らない）
                     │
Application:   ShareRepository(Port) ← ShareContentUseCase
                     │
Data:          ShareRepositoryImpl ──(uses)──▶ ShareItemSource(UIActivityItemSource)
                     │                          （LPLinkMetadata 供給）
Presentation:  ShareSheetPresenter （root VC 解決 / popover / present）
                     │
Manager:       IosShareManager（singleton, 公開API, (Bool,String?)/result 変換）
                     │
Bridge:        UnityIosShareManager(Swift facade) + UnityIosShareManagerBridge(.h/.m)
                                                   + UnityIosShareJsonParser
```

制御フロー（share 実行）:

1. Bridge C 関数 `shareContent(...)` → `UnityIosShareManager.share(...)`
2. facade が JSON/引数を `ShareContent`（Domain）へ変換（`UnityIosShareJsonParser`）
3. `IosShareManager.share(content:completion:)` → `ShareContentUseCase.execute(content:)`
4. UseCase → `ShareRepository.present(content:)`
5. `ShareRepositoryImpl` が `ShareItem` → `[Any]`（活性化アイテム）を構築。先頭 item のみ `ShareItemSource` で**置き換え**（追加ではない）、`ShareSheetPresenter` に委譲
6. Presenter が root VC 解決 → `UIActivityViewController` 生成 → popover 設定 → present
7. `completionWithItemsHandler` → `ShareResult`（completed / activityType）へ変換 → Manager → `(Bool, String?, ...)` → Bridge callback

---

## 7. サブ機能別詳細設計

### S1. 共有アイテムのモデル化（Domain）

ファイル: `Share/Domain/Model/ShareItem.swift`

```swift
/// A single item to be shared through the system share sheet.
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

- 設計判断: `.url` は `URL` ではなく **raw `String`** を保持する。URL 妥当性検証は Data 層（`buildActivityItems`）で行い、失敗を `ShareError.invalidURL` として到達可能にする。Domain は検証責務を持たない。
- 活性化アイテムには型を作らず、除外・選択 activity は raw `String`（`UIActivity.ActivityType` の rawValue）で通す。専用 Domain 型（`ShareActivityType`）は作らない。

ファイル: `Share/Domain/Model/ShareContent.swift`

```swift
/// The full payload for a share invocation.
public struct ShareContent {
    /// Items to share (must be non-empty).
    public let items: [ShareItem]
    /// Optional subject (used by Mail and similar activities).
    public let subject: String?
    /// Optional preview title shown in the share sheet header.
    public let previewTitle: String?
    /// Activity types to exclude (raw identifiers, e.g. "com.apple.UIKit.activity.PostToFacebook").
    public let excludedActivityTypes: [String]

    public init(items: [ShareItem], subject: String? = nil,
                previewTitle: String? = nil, excludedActivityTypes: [String] = [])
}
```

### S2. 結果・エラー（Domain）

ファイル: `Share/Domain/Model/ShareResult.swift`

```swift
/// The outcome of a share sheet interaction.
public struct ShareResult {
    /// true if the user completed an activity; false if cancelled.
    public let completed: Bool
    /// The selected activity's raw identifier, or nil (cancelled / unknown).
    public let activityType: String?
}
```

ファイル: `Share/Domain/Model/ShareError.swift`（全ケースは第 8 章参照）

### S3. Port（Application）

ファイル: `Share/Application/Port/ShareRepository.swift`

```swift
/// Contract for presenting the system share sheet.
/// Implemented by `ShareRepositoryImpl` in the Data layer.
public protocol ShareRepository {
    /// Presents the share sheet for the given content.
    /// - Returns: The interaction result.
    /// - Throws: `ShareError` on failure before or during presentation.
    func present(content: ShareContent) async throws -> ShareResult
}
```

- Port はドメイン型のみ。`UIActivityViewController` / `UIActivity.ActivityType` は漏らさない（excluded は `[String]` raw で受け、Data 層で `UIActivity.ActivityType` へ変換）。

### S4. UseCase（Application）

ファイル: `Share/Application/UseCase/ShareUseCases.swift`

```swift
/// Presents the system share sheet for the given content.
public struct ShareContentUseCase {
    private let repository: ShareRepository
    public init(repository: ShareRepository)
    public func execute(content: ShareContent) async throws -> ShareResult {
        try await repository.present(content: content)
    }
}
```

- 入力検証（items 空チェック）は UseCase 内で行い、空なら `ShareError.noValidItems` を throw する。

### S5. Repository 実装 + Item Source（Data）

ファイル: `Share/Data/Repository/ShareRepositoryImpl.swift`

責務:
- `ShareItem` → 活性化アイテム `[Any]` への変換
  - `.text` → `String`
  - `.url(string)` → `URL`。`URL(string:)` の生成成功だけでは不十分（相対 URL や scheme なし文字列も生成され得る）。以下を満たさない場合は `ShareError.invalidURL(string)`:
    - 空文字・空白のみは不可
    - `url.scheme` を小文字化し、許可 scheme（`http` / `https` / `file`）のいずれかであること
    - `http`/`https` の場合は `url.host` が非 nil・非空であること
    - `file` の場合は `url.isFileURL == true` であること
    - `ftp` や scheme なし等は不可
  - `.imageFile(path)` → `UIImage`（読込失敗で `ShareError.imageLoadFailed`）
  - `.file(path)` → `URL`（存在しなければ `ShareError.fileNotFound`）
- `previewTitle` / `subject` の適用ルール（重複防止）:
  - `subject` / `previewTitle` の少なくとも一方が指定されている場合のみ、**先頭アイテムを `ShareItemSource` で置き換える**（sidecar として追加しない。追加すると同一内容が共有先へ二重に渡るため）
  - `ShareItemSource` は先頭アイテムの実体（`String`/`URL`/`UIImage`）を保持し、`itemForActivityType` はその実体を返す
  - 2 番目以降のアイテムはそのまま `[Any]` に含める
  - `subject` / `previewTitle` がどちらも nil の場合は `ShareItemSource` を作らず、素の `[Any]` を渡す
- `excludedActivityTypes: [String]` → `[UIActivity.ActivityType]` へ変換
- `ShareSheetPresenter` に presentation を委譲し、結果を `ShareResult` へ変換
- システムエラー・前提失敗を `ShareError` へ変換

```swift
public final class ShareRepositoryImpl: ShareRepository {
    private let TAG = "ShareRepositoryImpl"
    private let presenter: ShareSheetPresenting
    public init(presenter: ShareSheetPresenting = ShareSheetPresenter())

    public func present(content: ShareContent) async throws -> ShareResult {
        Log.d(TAG, "[present] items: \(content.items.count), subject: \(content.subject ?? "nil")")
        let items = try buildActivityItems(from: content)   // throws ShareError
        let excluded = content.excludedActivityTypes.map { UIActivity.ActivityType($0) }
        return try await presenter.present(items: items, excluded: excluded)
    }
    // buildActivityItems(from:) -> [Any] : 変換 + 検証
}
```

ファイル: `Share/Data/ItemSource/ShareItemSource.swift`

```swift
/// Wraps a single primary share item, supplying subject and rich link metadata.
/// This REPLACES the primary item in the activity items array (it is not an
/// additional sidecar item), so the content is never shared twice.
final class ShareItemSource: NSObject, UIActivityItemSource {
    // holds the primary item (String / URL / UIImage), subject, previewTitle
    func activityViewControllerPlaceholderItem(_:) -> Any          // returns the primary item
    func activityViewController(_:itemForActivityType:) -> Any?    // returns the same primary item
    func activityViewController(_:subjectForActivityType:) -> String
    func activityViewControllerLinkMetadata(_:) -> LPLinkMetadata? // returns metadata when previewTitle is set
}
```

- 重要: `ShareItemSource` は「追加のアイテム」ではなく「先頭アイテムの置き換え」。`placeholderItem` / `itemForActivityType` が同じ primary item を返すことで、共有先には 1 部だけ渡る。

### S6. Presenter（Presentation）

ファイル: `Share/Presentation/ShareSheetPresenter.swift`

責務（UIKit 依存はここまで）:
- root VC 解決（Dialog の `getRootViewController()` と同ロジックを踏襲）
- `UIActivityViewController` 生成、`excludedActivityTypes` 設定
- iPad popover 設定（sourceView 未指定時は root view 中央にフォールバック、既存 Dialog と同方針）
- `present` と `completionWithItemsHandler` を `async` へ橋渡し（`withCheckedThrowingContinuation`）

continuation を必ず 1 回だけ resume する実装規則（T4 完了条件に含める）:
- `hasResumed` フラグを持ち、resume 時に必ずガードする。`completionWithItemsHandler` は escaping かつコールバックキューが将来変わり得るため、**guard 判定と resume は main actor 上で実行する**（`@MainActor func resumeOnce(...)` helper に寄せる、または `Task { @MainActor in ... }` / `MainActor.assumeIsolated` 相当で main isolation を保証する）。これにより Swift concurrency 警告とデータ競合を避ける
- 提示前の前提失敗は resume の前に判定し、continuation を作らず throw する:
  - root VC が nil → `ShareError.noRootViewController`
  - root VC が `isBeingDismissed` / `isBeingPresented` / 既に `presentedViewController` を持つ → `ShareError.presentationFailed`（提示不能）
- `present(_:animated:completion:)` の completion（提示成功）と `completionWithItemsHandler`（ユーザー操作完了）は別物として扱い、resume は **`completionWithItemsHandler` 側のみ**で行う
- `completionWithItemsHandler` の `error` 非 nil → `resume(throwing: ShareError.presentationFailed(error))`、else → `resume(returning:)`。いずれも `hasResumed` ガード経由

```swift
protocol ShareSheetPresenting {
    func present(items: [Any], excluded: [UIActivity.ActivityType]) async throws -> ShareResult
}

final class ShareSheetPresenter: ShareSheetPresenting {
    private let TAG = "ShareSheetPresenter"

    @MainActor
    func present(items: [Any], excluded: [UIActivity.ActivityType]) async throws -> ShareResult {
        Log.d(TAG, "[present] items: \(items.count), excluded: \(excluded.count)")
        guard let root = getRootViewController() else { throw ShareError.noRootViewController }
        guard !root.isBeingDismissed, !root.isBeingPresented, root.presentedViewController == nil else {
            throw ShareError.presentationFailed(PresentationUnavailableError())
        }
        var hasResumed = false   // main actor 上でのみアクセス
        return try await withCheckedThrowingContinuation { continuation in
            // resume は main actor 上で 1 回だけ（guard も main isolation 内で実行）
            func resumeOnce(_ result: Result<ShareResult, Error>) {   // @MainActor helper 相当
                guard !hasResumed else { return }
                hasResumed = true
                continuation.resume(with: result)
            }
            let av = UIActivityViewController(activityItems: items, applicationActivities: nil)
            av.excludedActivityTypes = excluded
            // popover: sourceView = root.view 中央フォールバック
            av.completionWithItemsHandler = { activityType, completed, _, error in
                if let error {
                    resumeOnce(.failure(ShareError.presentationFailed(error)))
                } else {
                    resumeOnce(.success(ShareResult(completed: completed,
                                                    activityType: activityType?.rawValue)))
                }
            }
            root.present(av, animated: true)   // 提示 completion では resume しない
        }
    }
}
```

- 注意: iPad で popover 未設定はクラッシュのため、フォールバック設定を必須とする（企画書リスク S1）。

### S7. Manager（公開 API）

ファイル: `Share/IosShareManager.swift`

```swift
public final class IosShareManager: NSObject {
    private let TAG = "IosShareManager"
    public static let shared = IosShareManager()

    private let repository: ShareRepository
    private let shareUseCase: ShareContentUseCase

    private override init() { /* DI: ShareRepositoryImpl */ }
    init(repository: ShareRepository) { /* test DI */ }

    /// Presents the share sheet.
    /// - completion: (isSuccess, completed, activityType, errorMessage)
    ///   * isSuccess: presentation succeeded (user could interact)
    ///   * completed: user finished an activity (false = cancelled)
    ///   * activityType: selected activity raw id or nil
    ///   * errorMessage: set only when isSuccess == false
    public func share(
        content: ShareContent,
        completion: ((Bool, Bool, String?, String?) -> Void)? = nil
    ) {
        Log.d(TAG, "[share] items: \(content.items.count)")
        Task {
            do {
                let result = try await shareUseCase.execute(content: content)
                completion?(true, result.completed, result.activityType, nil)
            } catch {
                Log.e(TAG, "[share] error: \(error)")
                completion?(false, false, nil, error.localizedDescription)
            }
        }
    }
}
```

- ユーザーキャンセルはエラーではない（`isSuccess=true, completed=false`）。企画書 DoD の「キャンセルと失敗を区別」を満たす。

### S8. Unity Bridge

ファイル: `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManager.swift`（Swift facade, `@objcMembers`）

```swift
@objcMembers
public class UnityIosShareManager: NSObject {
    public static let shared = UnityIosShareManager()
    /// - contentJson: JSON describing items/subject/previewTitle/excludedActivityTypes
    public func share(contentJson: String,
                      handler: ((Bool, Bool, String?, String?) -> Void)?) {
        // parser.parse(contentJson) -> ShareContent?（nil なら handler(false,false,nil,"invalid json")）
        // IosShareManager.shared.share(content:) { ... handler?(...) }
    }
}
```

ファイル: `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareJsonParser.swift`

- 期待 JSON:
  ```json
  {
    "items": [
      { "type": "text", "value": "hello" },
      { "type": "url", "value": "https://example.com" },
      { "type": "image", "value": "/path/to.png" },
      { "type": "file", "value": "/path/to.pdf" }
    ],
    "subject": "optional",
    "previewTitle": "optional",
    "excludedActivityTypes": ["com.apple.UIKit.activity.PostToFacebook"]
  }
  ```
- `type` → `ShareItem` の対応: `text`→`.text`, `url`→`.url(value)`（**文字列のまま保持**。妥当性は Data 層で検証し `invalidURL` へ）, `image`→`.imageFile(path:)`, `file`→`.file(path:)`。
- 未知 `type` は無視。`value` 欠落エントリも無視。すべて無視され `items` が空になった場合は `ShareContent(items: [])` を返し、UseCase 側で `noValidItems`。
- エラー責務の分離:
  - Parser: JSON 構文不正のみを担当（`nil` を返し Bridge が `"Invalid share content JSON."`）。未知 type は「無視」であってエラーではない。
  - Data 層: URL 文字列不正（`invalidURL`）・画像読込失敗（`imageLoadFailed`）・ファイル不在（`fileNotFound`）を担当。
  - UseCase: items 空（`noValidItems`）を担当。
  - この分離により、Bridge 返却表の `invalidURL` は Data 層で到達可能となる。

ファイル: `ios/UnityIosPlugin/UnityIosPlugin/Share/UnityIosShareManagerBridge.h` / `.m`（C ABI）

```c
/// - buttonText 相当なし。共有結果を返す。
/// - isSuccess: presentation succeeded. completed: user finished. activityType: raw id or NULL.
typedef void (*ShareCallback)(bool isSuccess,
                              bool completed,
                              const char* activityType,
                              const char* errorMessage);

/// Presents the system share sheet.
/// - contentJson: UTF-8 JSON (required, non-NULL).
void shareContent(const char* contentJson, ShareCallback callback);
```

- `.m` は既存 Dialog Bridge と同様、`NSString` 変換 → `[[UnityIosShareManager shared] shareWithContentJson:handler:]` → callback へ C 文字列変換。

---

## 8. ドメインエラー一覧（全ケース）

ファイル: `Share/Domain/Model/ShareError.swift`

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
    /// No root view controller was available to present the sheet.
    case noRootViewController
    /// The share sheet failed to present or completed with a system error.
    case presentationFailed(Error)
    /// An unknown error occurred.
    case unknown(Error)
}
```

- `LocalizedError` 準拠で `errorDescription`（英語）を提供し、Manager の `error.localizedDescription` に反映する。
- ユーザーキャンセルは **エラーに含めない**（`ShareResult.completed == false` で表現）。

## 9. エラーコード/メッセージ対応表（Bridge 返却仕様）

Manager は `(isSuccess, completed, activityType, errorMessage)` を返す。`errorMessage` は `isSuccess == false` のときのみ非 nil。

| ケース | isSuccess | completed | activityType | errorMessage（英語） |
| --- | --- | --- | --- | --- |
| 共有完了 | true | true | 選択 activity raw id | nil |
| ユーザーキャンセル | true | false | nil | nil |
| items 空/全無効 | false | false | nil | "No shareable items were provided." |
| URL 不正 | false | false | nil | "Invalid URL: \<value\>." |
| 画像読込失敗 | false | false | nil | "Failed to load image at path: \<path\>." |
| ファイル不在 | false | false | nil | "File not found at path: \<path\>." |
| root VC なし | false | false | nil | "No root view controller available to present the share sheet." |
| 提示/システム失敗 | false | false | nil | "Failed to present the share sheet: \<detail\>." |
| JSON 不正（Bridge） | false | false | nil | "Invalid share content JSON." |

注: 数値エラーコードは既存 Notification/Dialog Bridge が未採用（`(Bool, String?)` 方式）のため、本設計も文字列メッセージ方式に統一する。

---

## 10. テスト設計

フレームワーク: Swift Testing（`@Test` / `#expect`）。Mock は `ShareRepository` を実装し UseCase / Manager に DI。

ファイル: `IosLibraryTests/Share/Application/Mock/MockShareRepository.swift`

```swift
final class MockShareRepository: ShareRepository {
    var shouldFail = false
    var errorToThrow: ShareError = .noRootViewController
    var presentCallCount = 0
    var lastContent: ShareContent?
    var stubbedResult = ShareResult(completed: true, activityType: "com.apple.UIKit.activity.CopyToPasteboard")
    func present(content: ShareContent) async throws -> ShareResult {
        presentCallCount += 1; lastContent = content
        if shouldFail { throw errorToThrow }
        return stubbedResult
    }
}
```

### 単体テスト

`ShareContentUseCaseTests`:
- 正常系: present が 1 回呼ばれ、stubbedResult を返す
- 異常系: `shouldFail` で `ShareError` を伝播
- 境界値: `items` 空 → `noValidItems` を throw（present は呼ばれない）

`IosShareManagerTests`（repository DI）:
- 完了: `(true, true, activityType, nil)`
- キャンセル: stubbedResult.completed=false → `(true, false, nil, nil)`
- 失敗: shouldFail → `(false, false, nil, errorMessage)`

`ShareErrorTests`:
- 各ケースの `errorDescription`（英語）が表通りであること

`ShareRepositoryImplTests`（Data 層変換。UIKit presentation は Mock presenter で分離）:
- `.url` 検証: `https://host`・`http://host`・`file:///path` は成功 / 空文字・空白のみ・scheme なし（`example.com`）・host なし（`https://`）・`ftp://host` は `invalidURL` を throw
- `.file(path)` 存在パス → 成功 / 不在パス → `fileNotFound`
- `.imageFile(path)` 読込失敗 → `imageLoadFailed`
- `excludedActivityTypes: [String]` → `UIActivity.ActivityType` 変換が rawValue 一致
- primary item 置き換え: subject/previewTitle 指定時のみ先頭が `ShareItemSource` になり、item 数が増えない（重複しない）
- ※ `ShareSheetPresenting` を Mock 化し、`buildActivityItems` の結果を検証する

`UnityIosShareJsonParserTests`（UnityIosPluginTests/Share）:
- 4 種 type のパース、未知 type / value 欠落の無視、全無視時の空 items、excludedActivityTypes 反映
- `url` type は `.url(String)`（未検証文字列）として保持されること

### 統合テスト / 手動確認（実機・シミュレータ）

企画書リスクに対応:
- iPhone / iPad で共有シート表示、iPad で popover クラッシュしない（リスク: iPad クラッシュ）
- テキスト / URL / 画像 / ファイルの各共有先（Mail / Messages / Files / AirDrop / コピー）で内容が正しい
- `previewTitle` 指定時にヘッダプレビューが即時表示（リスク: プレビュー遅延）
- `excludedActivityTypes` 指定で対象が非表示
- キャンセル時に `completed=false`、失敗時に `errorMessage` が返る
- 存在しない画像/ファイルパスで適切なエラー

---

## 11. 実装タスク分解（依存関係付き）

| # | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
| --- | --- | --- | --- | --- | --- |
| T1 | Domain 定義（ShareItem/ShareContent/ShareResult。activity type は raw String、専用型は作らない） | 0.5日 | なし | 型がコンパイル、DocC 付与 | Domain がプラットフォーム非依存 |
| T2 | ShareError 定義 + LocalizedError | 0.5日 | なし | 全ケース + 英語メッセージ、ShareErrorTests green | 表と一致 |
| T3 | Port + ShareContentUseCase + 入力検証 | 0.5日 | T1,T2 | UseCase テスト green（正常/異常/空） | Port がドメイン型のみ |
| T4 | ShareSheetPresenter（root VC/popover/continuation） | 1.0日 | T1,T2 | 実機で共有シート表示、iPad 非クラッシュ、**continuation を必ず 1 回だけ resume（resume guard を main actor 上で実行 + 提示前失敗判定）** | UIKit 隔離、iPad フォールバック、二重 resume なし、main isolation |
| T5 | ShareRepositoryImpl + ShareItemSource（変換/preview/excluded） | 1.0日 | T3,T4 | 4 種アイテム変換、primary item 置き換えで重複しない、ShareRepositoryImplTests green | エラー変換の集約、ItemSource 置き換え規則 |
| T6 | IosShareManager（公開API, (Bool,Bool,String?,String?)） | 0.5日 | T3,T5 | Manager テスト green | UseCase 経由、キャンセル/失敗区別 |
| T7 | Unity Bridge（Swift facade + JsonParser + .h/.m） | 1.0日 | T6 | Bridge 経由で共有起動、Parser テスト green | Bridge は委譲のみ。**C ABI typedef は `bool`、Obj-C から呼ぶ Swift completion block は `BOOL`**（両者を混同しない） |
| T8 | Xcode プロジェクトへのファイル追加・ビルド確認 | 0.5日 | T1–T7 | 両ターゲットビルド成功、全テスト green | ターゲット所属の正しさ |
| T9 | サンプルアプリ検証（design-sample-app で実装） | - | T7 | 共有機能を手動確認できる導線が動作 | ※具体パスは design-sample-app で定義 |

先行（基盤）: T1–T3。後続（拡張）: T4–T8。T9 は別 workflow。

---

## 12. リスクと緩和策

| リスク | 緩和策 | 対応タスク |
| --- | --- | --- |
| iPad で popover 未設定クラッシュ | Presenter で sourceView フォールバック必須化、iPad 実機確認 | T4 |
| 画像/ファイルパス不正 | Data 層で存在チェックし `ShareError` 化、テストで異常系 | T5,T2 |
| プレビュー遅延 | `ShareItemSource.activityViewControllerLinkMetadata` で `LPLinkMetadata` 即時供給 | T5 |
| メインスレッド以外からの UI 操作 | Presenter を `@MainActor` に限定 | T4 |
| Unity JSON 不正 | Parser が nil を返し `(false,...,"invalid json")` | T7 |
| 大容量ファイル共有時のメモリ | 画像以外はファイル URL 参照で渡し UIImage 化しない | T5 |
| continuation の二重 resume / 未 resume | `hasResumed` ガード + 提示前失敗判定 + resume は completionWithItemsHandler のみ（S6） | T4 |
| ItemSource による共有内容の重複 | primary item を「置き換え」（sidecar 追加しない）、テストで item 数を検証 | T5 |
| iOS 18 宛先プリフィル未対応 | 本設計は未実装。将来 `ShareItemSource` に `activityViewControllerShareRecipients` を追加できる構造にする（要検証） | 将来 |

---

## 13. Definition of Done

### 実装・テスト

- [ ] `Share` モジュールが Clean Architecture 層構成で追加されている（Domain/Application/Data/Presentation/Manager/Bridge）
- [ ] Port はドメイン型のみ、UIKit 型が Domain/Application に漏れていない
- [ ] 全 public/@objc/Bridge 関数に先頭 `Log.d`/`Log.e` が付与されている
- [ ] `ShareError` 全ケースと英語メッセージが第 9 章の表と一致する
- [ ] UseCase / Manager / Parser / Error の単体テストが green（正常・異常・境界）
- [ ] `ShareRepositoryImplTests` が green（URL scheme 検証、file/image 変換、excluded activity 変換、primary item 置き換えで item 数が重複しない）
- [ ] 両ターゲット（IosLibrary / UnityIosPlugin）がビルド成功

### 動作（実機/シミュレータ）

- [ ] テキスト / URL / 画像 / ファイルを共有できる
- [ ] Mail / Messages / Files / AirDrop / コピー の各共有先で内容が正しい
- [ ] iPhone / iPad で表示でき、iPad で popover クラッシュしない
- [ ] `previewTitle` でヘッダプレビューが即時表示される
- [ ] `excludedActivityTypes` で共有先を除外できる
- [ ] キャンセル（completed=false）と失敗（errorMessage 非 nil）を区別できる
- [ ] Unity Bridge 経由で共有シートを起動でき、結果コールバックが返る

---

## 14. 要検証（断定を避けた項目）

- iOS 18 実機での共有シート表示・各共有先の受領挙動
- `LPLinkMetadata` の `iconProvider`/`imageProvider` 指定時のプレビュー表示タイミング
- 宛先プリフィル（`activityViewControllerShareRecipients`）を将来追加する際の `INPerson`（Intents）依存と Unity 連携方式

（continuation の単一 resume 保証は第 6/12 章で設計に落とし込み済み。T4 完了条件で検証する。）
