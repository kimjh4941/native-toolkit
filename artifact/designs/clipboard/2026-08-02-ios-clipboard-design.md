# iOS クリップボード機能 実装設計書

- 作成日: 2026-08-02
- 最新版: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v2.md`（第 1 回レビュー反映済み。以降はこちらを参照する）
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
| DoD | 企画書の 5 カテゴリ 55 項目（本設計書の DoD で実装観点へ再構成） |

### 不足前提（企画書に記載がなく、本設計で判断した事項）

企画書が「設計段階で決定する（要判断）」としていた項目について、本設計で次のとおり確定する。新規判断であることを明示するため、企画書由来の前提とは分けて記載する。

| # | 企画書の未確定事項 | 本設計での判断 | 理由 |
|---|---|---|---|
| D-1 | `UIPasteControl` を公開 API として提供するか | **ネイティブライブラリでは提供する**（Presentation 層 + Manager のファクトリ）。**Unity Bridge では提供しない** | UIKit の `UIView` は C ABI を越えられない。ネイティブ利用者には許可プロンプト回避経路が必須 |
| D-2 | パターン検出の結果をどこまで公開するか | ドメイン型 `ClipboardDetectedValues`（`Bool` フラグ + 文字列配列）へ変換して公開。`PartialKeyPath` / `DDMatch*` は公開 API に露出させない | 企画書リスク「キーパス API が Swift 専用」。Objective-C / Unity から利用可能にする |
| D-3 | `contains(pasteboardTypes:)` / `changeCount` を事前判定に使うか | **`changeCount` は使う**（フォアグラウンド差分検知に代替手段がない）。**`contains(pasteboardTypes:)` は内部利用のみ**とし公開 API から外す | 企画書「公式の非対象 API 列挙に含まれない」。代替のある `contains` は避け、代替のない `changeCount` は要検証項目として残す |
| D-4 | 複数 provider の型優先順位・部分失敗仕様 | 優先順位は text > image > url > file。1 件失敗しても他 provider を継続し、結果は集約して 1 回返す | 企画書サンプルの方針を踏襲し、完了通知の曖昧さを排除 |
| D-5 | HTML の扱い（iOS には HTML 専用プロパティがない） | `ClipboardContent.htmlText(plain:html:)` を用意し、1 アイテム複数表現型（`public.utf8-plain-text` + `public.html`）で実装 | Android の `CopyHtmlTextUseCase` と機能パリティを取る |
| D-6 | 名前付きペーストボードの公開範囲 | `PasteboardScope`（`.general` / `.named(String)` / `.unique`）としてすべての操作に付与。作成・破棄も公開 | 企画書 In scope。寿命の注意はドキュメントで明示 |
| D-7 | 一時ディレクトリの残留対策 | Manager 初期化時に自ライブラリ専用ルート（`tmp/IosLibraryClipboard/`）配下の残骸を一括削除 | 企画書要検証「アプリ強制終了時の残留」への対処 |

---

## 設計目的

- 企画書で網羅した `UIPasteboard` API を、Clean Architecture の層構成に沿って `IosLibrary` へ実装する
- ネイティブ呼び出し元（`IosLibraryExample`）と Unity 呼び出し元の双方から、同一の機能範囲を利用できるようにする（`UIPasteControl` を除く。D-1 参照）
- OS 依存のプライバシー挙動（通知 / プロンプト）を隠蔽せず、呼び出し元が経路を選べる API とする

---

## スコープ（in / out）

### In scope（実装対象）

| サブ機能 | 内容 |
|---|---|
| S1 ペーストボード解決 | `general` / 名前付き / ユニーク名の取得・作成・破棄 |
| S2 コピー | plainText / htmlText / url / imageFile / imageData / color / customData / multipleText / multiRepresentation |
| S3 コピーオプション | `localOnly` / `expirationDate` |
| S4 ペースト（同期） | text / urls / image / color / 任意 UTI `Data` / 全アイテムのメタ情報 |
| S5 ペースト（`NSItemProvider` 非同期） | text / image / file の非同期ロード、キャンセル、エラー分類 |
| S6 内容確認 | `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `numberOfItems` / `types` / `itemSet` |
| S7 クリア | `items = []`、名前付きの `remove(withName:)` |
| S8 変更監視 | `changedNotification` / `removedNotification` / `changeCount` 差分 |
| S9 パターン検出 | `detectedPatterns` / `detectedValues`（キーパス版のみ） |
| S10 貼り付け UI | `UIPasteControl` ファクトリと受信 View（ネイティブのみ） |
| S11 Unity Bridge | S1〜S9 の JSON ベース公開（S10 を除く） |

### Out of scope（実装しない）

- 企画書の Out of scope 全項目
- App Group shared container のファイル入出力（責務境界のドキュメント記載のみ）
- `contains(pasteboardTypes:)` の公開 API 化（内部利用に限定。D-3）
- `loadTransferable` / `loadInPlaceFileRepresentation` / `loadItem`（非推奨）
- `docs/` 配下の変更（固定で対象外）

---

## 共通実装方針の適用チェック（common.md 準拠）

| 方針 | 適用 | 本設計での対応 |
|---|---|---|
| Clean Architecture の層と依存方向 | 適合 | Domain → Application → Data / Presentation → Manager → Unity Bridge の順で配置 |
| 層とモジュールの対応（Manager までネイティブライブラリ） | 適合 | Domain 〜 Manager を `ios/IosLibrary` に配置。`ios/UnityIosPlugin` には Unity Bridge 層のみ |
| Port はドメイン型のみ | 適合 | `ClipboardRepository` / `ClipboardItemLoader` の引数・戻り値は全てドメイン型。`UIPasteboard` / `NSItemProvider` / `UTType` は Data 層に閉じる |
| Manager は UseCase 経由で Data にアクセス | 適合 | `IosClipboardManager` は `ClipboardUseCases` 経由のみ。Repository を直接呼ばない |
| system Delegate / Listener の所有は Manager 層の 1 クラス | 適合 | `changedNotification` / `removedNotification` の `NotificationCenter` 監視トークンは `IosClipboardManager` のみが保持。Presentation / Data / Unity Bridge には置かない（Android の過去違反例の再発防止） |
| Manager の公開 API は callback 版 + `async throws` 版を併設 | 適合 | 全操作で両方を用意（新規 Manager のため設計時点で両方定義） |
| エラー変換の流れ | 適合 | システムエラー → `ClipboardRepositoryImpl` → `ClipboardError` → Manager → `(Bool, String?)` / エラーコード → Bridge |
| TDD（UseCase 単位・Mock は Port 実装 + `shouldFail` + CallCount + `stubbedXxx`） | 適合 | `MockClipboardRepository` / `MockClipboardItemLoader` を同パターンで作成 |
| Swift Testing（`@Test` / `#expect`、XCTest 不使用） | 適合 | 既存 `IosLibraryTests` と同形式 |
| Unity Bridge は薄く保つ | 適合 | `UnityIosClipboardManager` は JSON 変換と `IosClipboardManager` 呼び出しのみ |
| サンプルアプリはネイティブライブラリのみに依存 | 適合 | `IosLibraryExample` は `IosLibrary` のみ import。`UIPasteControl` もライブラリ側から取得（D-1） |
| 最小 OS バージョン iOS 18 | 適合 | 使用 API は全て iOS 16 以前の導入。`ChangedMessage`（iOS 26）は不使用 |

---

## 個別実装方針の適用チェック（ios.md 準拠）

| 方針 | 適用 | 本設計での対応 |
|---|---|---|
| 全メソッド先頭に全パラメータの `Log.d`（エラーは `Log.e`） | 適合 | 対象は `public` / `internal` / `override` / `@objc` 関数と Bridge C 関数。`private let TAG = "<FullClassName>"` を各クラス先頭に置く |
| ログ対象外（model / enum / protocol 宣言、private utility） | 適合 | Domain の `enum` / `struct` 宣言にはログを入れない |
| クリップボード内容のログ | **本設計で追加**（下記） | 値そのものは出さず、長さ・型のみ出力する（Android の `maskJson` に相当） |
| ObjC ブロック引数型（`BOOL` / `NSInteger` / `NSString * _Nullable`） | 適合 | Bridge `.m` の完了ブロックは `BOOL` を使用（`bool` 不可） |
| Manager は callback 版 + `async throws` 版 | 適合 | 上記のとおり |
| private helper を一律 `async` にしない | 適合 | `FileManager` の一時ファイル操作は同期関数 |
| UI 更新は main へ戻す | 適合 | Manager の callback は全経路で main actor から 1 回だけ呼ぶ |
| DocC コメント（public シンボル必須、本文は英語） | 適合 | 全 public 型・関数に付与 |
| ユーザー向け文言は英語 | 適合 | `ClipboardError` の `errorDescription` は英語 |

### 追加ルール（本機能で新設・要合意）

クリップボードの内容は機微情報を含みうるため、**コピー / ペーストする値そのものをログに出力しない**。ios.md の「全パラメータをログに出す」ルールは、本機能では次のとおり適用する。

```swift
// NG: Log.d(TAG, "[copy] text: \(text)")
// OK:
Log.d(TAG, "[copy] kind: plainText, length: \(text.count), scope: \(scope), localOnly: \(options.localOnly)")
```

Android の `UnityAndroidClipboardManager.maskJson` が同じ考え方で JSON 本文を秘匿しており、その先例に合わせる。

---

## 既存実装差分サマリー

### 破壊的変更

**なし。** 既存の Notification / Dialog / Share 機能のファイルは変更しない。追加のみ。

### Xcode プロジェクト設定

`IosLibrary.xcodeproj` / `UnityIosPlugin.xcodeproj` / `IosLibraryExample.xcodeproj` はいずれも `PBXFileSystemSynchronizedRootGroup` を採用しているため、**ファイル追加時に `project.pbxproj` を編集する必要はない**（ディレクトリに置けばターゲットに含まれる）。

### 追加ファイル一覧

`ios/IosLibrary/IosLibrary/Clipboard/` 配下（Domain 〜 Manager）:

| パス | 層 | 役割 |
|---|---|---|
| `Domain/Model/PasteboardScope.swift` | Domain | `.general` / `.named(String)` / `.unique(String)` |
| `Domain/Model/ClipboardContent.swift` | Domain | コピー内容の sealed 表現 |
| `Domain/Model/ClipboardCopyOptions.swift` | Domain | `localOnly` / `expirationDate` |
| `Domain/Model/ClipboardItemData.swift` | Domain | 1 アイテムの表現型と値 |
| `Domain/Model/ClipboardReadResult.swift` | Domain | 読み取り結果 |
| `Domain/Model/ClipboardSnapshot.swift` | Domain | 内容確認（型有無・件数・UTI 一覧） |
| `Domain/Model/ClipboardChangeEvent.swift` | Domain | 変更 / 破棄イベント |
| `Domain/Model/ClipboardDetectedValues.swift` | Domain | パターン検出結果 |
| `Domain/Model/ClipboardLoadedItem.swift` | Domain | `NSItemProvider` から読み出した結果 |
| `Domain/Model/ClipboardError.swift` | Domain | ドメインエラー |
| `Application/Port/ClipboardRepository.swift` | Application | 同期操作 Port |
| `Application/Port/ClipboardItemLoader.swift` | Application | 非同期ロード Port |
| `Application/UseCase/CopyContentUseCase.swift` | Application | コピー（検証込み） |
| `Application/UseCase/ReadContentUseCase.swift` | Application | 同期読み取り |
| `Application/UseCase/GetSnapshotUseCase.swift` | Application | 内容確認 |
| `Application/UseCase/ClearClipboardUseCase.swift` | Application | クリア |
| `Application/UseCase/CreatePasteboardUseCase.swift` | Application | 名前付き / ユニーク作成 |
| `Application/UseCase/RemovePasteboardUseCase.swift` | Application | 名前付き破棄 |
| `Application/UseCase/DetectPatternsUseCase.swift` | Application | パターン検出（有無 / 値） |
| `Application/UseCase/LoadItemUseCase.swift` | Application | provider 非同期ロード |
| `Application/UseCase/ClipboardChangeTracker.swift` | Application | `changeCount` 基準値の同期規則（純ロジック） |
| `Application/UseCase/ClipboardUseCases.swift` | Application | UseCase 集約 |
| `Data/Repository/ClipboardRepositoryImpl.swift` | Data | `UIPasteboard` 実装 |
| `Data/Repository/ClipboardItemLoaderImpl.swift` | Data | `NSItemProvider` 実装 |
| `Data/Repository/ClipboardMappers.swift` | Data | ドメイン型 ↔ `UIPasteboard` 型変換 |
| `Data/Repository/PasteboardResolver.swift` | Data | `PasteboardScope` → `UIPasteboard` 解決 |
| `Data/File/ClipboardTemporaryFileStore.swift` | Data | UUID 一時ディレクトリ管理・cleanup |
| `Presentation/ClipboardPasteReceiverView.swift` | Presentation | `UIPasteConfigurationSupporting` 実装 View |
| `Presentation/PasteControlFactory.swift` | Presentation | `UIPasteControl` 生成 |
| `IosClipboardManager.swift` | Manager | 公開 API・監視トークン所有 |

`ios/UnityIosPlugin/UnityIosPlugin/Clipboard/` 配下（Unity Bridge のみ）:

| パス | 役割 |
|---|---|
| `UnityIosClipboardManager.swift` | Swift facade（singleton、JSON ↔ ドメイン変換の呼び出し） |
| `UnityIosClipboardJsonParser.swift` | JSON パース / シリアライズ |
| `UnityIosClipboardManagerBridge.h` | C ABI 宣言（callback typedef + 関数） |
| `UnityIosClipboardManagerBridge.m` | C 関数実装（Swift singleton へ委譲） |

テスト:

| パス | 対象 |
|---|---|
| `ios/IosLibrary/IosLibraryTests/Clipboard/Application/Mock/MockClipboardRepository.swift` | Port Mock |
| `ios/IosLibrary/IosLibraryTests/Clipboard/Application/Mock/MockClipboardItemLoader.swift` | Port Mock |
| `ios/IosLibrary/IosLibraryTests/Clipboard/Application/*UseCaseTests.swift` | UseCase 単体 |
| `ios/IosLibrary/IosLibraryTests/Clipboard/Application/ClipboardChangeTrackerTests.swift` | 差分検知ロジック |
| `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardRepositoryImplTests.swift` | `UIPasteboard` 実装（ユニーク名 pasteboard 使用） |
| `ios/IosLibrary/IosLibraryTests/Clipboard/Data/ClipboardTemporaryFileStoreTests.swift` | 一時ファイル・sanitization |
| `ios/IosLibrary/IosLibraryTests/Clipboard/Domain/ClipboardErrorTests.swift` | エラー文言 |
| `ios/IosLibrary/IosLibraryTests/Clipboard/Presentation/IosClipboardManagerTests.swift` | Manager |
| `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardJsonParserTests.swift` | JSON |
| `ios/UnityIosPlugin/UnityIosPluginTests/Clipboard/UnityIosClipboardManagerTests.swift` | facade |

ドキュメント:

| パス | 変更 |
|---|---|
| `ios/IosLibrary/IosLibrary/IosLibrary.docc/IosLibrary.md` | Clipboard セクション追記 |

サンプルアプリ（`design-sample-app` で詳細設計。本設計ではファイルパスを定めない）:

- `IosLibraryExample` に Clipboard 検証画面を追加する（タスク T-12 の完了条件のみ定義）

### 既存規約との整合

| 観点 | 既存 | 本設計 |
|---|---|---|
| ディレクトリ構成 | `Share/{Domain,Application,Data,Presentation}` + `IosShareManager.swift` | 同一構成を `Clipboard/` で踏襲 |
| Manager 命名 | `IosShareManager` / `IosNotificationManager` | `IosClipboardManager` |
| Bridge 命名 | `UnityIosShareManager` + `UnityIosShareManagerBridge.h/.m` + `UnityIosShareJsonParser` | `UnityIosClipboardManager` + 同構成 |
| singleton | `public static let shared` + `private override init()` + test 用 `init(repository:)` | 同一 |
| エラーコード | Android は `CLIPBOARD_*`（`CLIPBOARD_EMPTY_CONTENT` 等） | iOS も同じ接頭辞・同じ意味で命名（クロスプラットフォーム整合） |

---

## 実装アーキテクチャ

```
[Unity C#]
    │ P/Invoke (C ABI)
[UnityIosClipboardManagerBridge.h/.m]        ← ios/UnityIosPlugin
    │
[UnityIosClipboardManager (@objcMembers)]    ← Unity Bridge 層
    │ + UnityIosClipboardJsonParser
    ▼
[IosClipboardManager]                        ← Manager 層 / ios/IosLibrary
    │ - NotificationCenter トークンを単独所有
    │ - callback 版 + async throws 版
    ▼
[ClipboardUseCases]                          ← Application 層
    │ CopyContent / ReadContent / GetSnapshot / Clear /
    │ CreatePasteboard / RemovePasteboard / DetectPatterns / LoadItem
    │ + ClipboardChangeTracker（純ロジック）
    ▼
[ClipboardRepository] [ClipboardItemLoader]  ← Application 層 Port（ドメイン型のみ）
    ▲                        ▲
[ClipboardRepositoryImpl] [ClipboardItemLoaderImpl]   ← Data 層（UIKit / NSItemProvider 依存）
    │ + ClipboardMappers / PasteboardResolver / ClipboardTemporaryFileStore
    ▼
[UIPasteboard] [NSItemProvider] [FileManager]

[PasteControlFactory] [ClipboardPasteReceiverView]    ← Presentation 層（UIKit）
    ▲ IosClipboardManager が生成し、ネイティブ呼び出し元へ返す（Unity 非公開）
```

依存方向の確認:

- Domain は他層へ依存しない（`Foundation` のみ。`UIKit` を import しない）
- Application は Domain のみに依存
- Data は Application（Port）と Domain に依存し、`UIKit` / `UniformTypeIdentifiers` / `DataDetection` を閉じ込める
- Presentation は Domain と `UIKit` に依存（Data には依存しない）
- Manager は Application（UseCase）と Presentation に依存
- Unity Bridge は Manager にのみ依存

---

## サブ機能別詳細設計

### S1 ペーストボード解決

**変更対象モジュール**: `IosLibrary`（Domain / Application / Data）

**データ構造**

```swift
public enum PasteboardScope: Equatable, Sendable {
    case general
    case named(String)     // App Group ID などの共有名（非永続）
    case unique(String)    // withUniqueName() の生成名を保持
}
```

**制御フロー**

1. Manager が `PasteboardScope` を UseCase へ渡す
2. `PasteboardResolver.resolve(_:createIfNeeded:)` が `UIPasteboard` を返す
   - `.general` → `UIPasteboard.general`
   - `.named(n)` / `.unique(n)` → `UIPasteboard(name:create:)`。nil なら `ClipboardError.pasteboardUnavailable(name:)`
3. 作成は `CreatePasteboardUseCase`（`.named` は `create: true`、`.unique` は `withUniqueName()` の結果名を `.unique` として返す）
4. 破棄は `RemovePasteboardUseCase`。`.general` を渡した場合は `ClipboardError.cannotRemoveGeneralPasteboard` を投げる（OS は黙って無視するため、呼び出し側の誤りを検出できるようにする）

**エラーハンドリング**: `invalidPasteboardName` / `pasteboardUnavailable` / `cannotRemoveGeneralPasteboard`

**互換性方針**: 全 API が `scope: PasteboardScope = .general` のデフォルト引数を持つ。既存呼び出し元は影響なし。

---

### S2 コピー / S3 コピーオプション

**データ構造**

```swift
public enum ClipboardContent: Equatable, Sendable {
    case plainText(String)
    case htmlText(plain: String, html: String)          // D-5
    case url(String)
    case imageFile(path: String)
    case imageData(Data, utType: String)                // png / jpeg など
    case color(red: Double, green: Double, blue: Double, alpha: Double)
    case customData(Data, utType: String)
    case multipleText([String])
    case multiRepresentation([String: Data])            // UTI -> Data
}

public struct ClipboardCopyOptions: Equatable, Sendable {
    public let localOnly: Bool          // default true（安全側）
    public let expirationDate: Date?    // default nil
    public let replaceExisting: Bool    // default true。false は addItems 相当
}
```

`localOnly` の既定値を `true` にする理由: 企画書リスク「Universal Clipboard による外部流出」。明示的に `false` を渡した場合のみ他デバイスへ転送される。

**制御フロー（`CopyContentUseCase`）**

1. 入力検証（下表）
2. `repository.copy(content:options:scope:)` を呼ぶ
3. Data 層 `ClipboardMappers.makeItems(from:)` が `[[String: Any]]` を生成
4. `replaceExisting == true` → `setItems(_:options:)`、`false` → `addItems(_:)`
   - `addItems` はオプションを取れないため、`replaceExisting == false` かつ `localOnly` / `expirationDate` が既定以外の場合は `ClipboardError.optionsNotApplicableForAppend` を投げる（サイレントに無視しない）

**入力検証（UseCase 層）**

| ケース | 判定 | エラー |
|---|---|---|
| `plainText("")` | 許可（Android の `PlainText` も空文字を許可） | - |
| `htmlText` の `html` が空白のみ | 拒否 | `emptyContent` |
| `url` が空 / スキーム無し / http(s) で host 無し | 拒否 | `invalidURL` |
| `imageFile` のパスが存在しない | 拒否 | `fileNotFound` |
| `imageFile` が `UIImage` にできない | 拒否 | `imageLoadFailed` |
| `imageData` / `customData` が空 | 拒否 | `emptyContent` |
| `imageData` / `customData` の UTI が空 / 不正形式 | 拒否 | `invalidTypeIdentifier` |
| `multipleText` が空配列 | 拒否 | `emptyItemList` |
| `multiRepresentation` が空辞書 | 拒否 | `emptyItemList` |
| `expirationDate` が過去 | 許可（OS 挙動は要検証。警告ログのみ） | - |

`setValue(_:forPasteboardType:)` は使用しない（既存アイテムを暗黙置換する仕様が誤用を招くため。企画書リスク参照）。書き込みは `setItems` / `addItems` に統一する。

**互換性方針**: 追加のみ。既存 API への影響なし。

---

### S4 ペースト（同期）

**データ構造**

```swift
public struct ClipboardItemData: Equatable, Sendable {
    public let typeIdentifiers: [String]
    public let text: String?
    public let urlString: String?
    public let imageDataUTType: String?   // 画像がある場合の UTI（本体は返さない）
}

public struct ClipboardReadResult: Equatable, Sendable {
    public let items: [ClipboardItemData]
    public let numberOfItems: Int
}
```

**制御フロー（`ReadContentUseCase`）**

1. `repository.read(scope:)`
2. Data 層は `pasteboard.items` を走査し、`ClipboardMappers.toItemData` でドメイン型へ変換
3. 画像・大きな `Data` は本体を返さず UTI のみ返す。本体が必要な場合は `readData(utType:scope:)` または S5 を使う

**プライバシー上の注意**: `read` は本体を読むため、iOS 16+ の許可プロンプト / iOS 14+ のアクセス通知の対象になりうる。Manager の DocC に明記し、事前判定には S6 を使うよう誘導する。

**エラーハンドリング**: 空の場合は `items: []` を返し、エラーにしない（Android の「空は正常系」方針に合わせる）。

---

### S5 ペースト（`NSItemProvider` 非同期）

企画書の「設計上の契約 6 点」をそのまま実装契約として採用する。

**データ構造**

```swift
public enum ClipboardLoadRequest: Equatable, Sendable {
    case text
    case image           // UIImage としてロード
    case file(utType: String)   // 一時ファイルへ書き出して URL を返す
}

public enum ClipboardLoadedItem: Sendable {
    case text(String)
    case imageData(Data, utType: String)   // UIImage は Domain に持ち込まない
    case file(URL)                          // 削除責務は呼び出し側
}
```

`UIImage` を Domain へ持ち込まないため、画像は Data 層で `pngData()` へ変換して返す（企画書の要検証「Data 化コスト」は計測タスク T-13 で確認する）。

**Port**

```swift
public protocol ClipboardItemLoader: AnyObject {
    /// Loads the first matching item. The completion is invoked exactly once on the main actor.
    /// Returns a token that cancels the request.
    @discardableResult
    func load(
        _ request: ClipboardLoadRequest,
        scope: PasteboardScope,
        completion: @escaping (Result<ClipboardLoadedItem, ClipboardError>) -> Void
    ) -> ClipboardLoadToken

    func cancelAll()
}

public protocol ClipboardLoadToken: AnyObject {
    func cancel()
}
```

**制御フロー（`ClipboardItemLoaderImpl`、`@MainActor`）**

1. リクエスト ID を採番し、**発行時点で管理表へ登録**（provider 不在の即時失敗もキャンセル対象にするため）
2. `itemProviders` から条件に合う provider を検索。無ければ `DispatchQueue.main.async` 経由で `noMatchingItem` を配信
3. `loadObject` / `loadDataRepresentation` / `loadFileRepresentation` を呼び、返却された `Progress` を管理表へ格納
4. completion（任意スレッド）で結果を組み立て、main へディスパッチ
5. main 側の `finish(id:)` が管理表から ID を除去できた場合のみ配信。除去できない（= キャンセル済み）場合は結果を破棄し、生成済み一時ディレクトリを削除
6. `cancelAll()` / `deinit` は各リクエストへ `.cancelled` を **1 回**配信してから管理表を空にする

**一時ファイル（`ClipboardTemporaryFileStore`）**

```
<NSTemporaryDirectory()>/IosLibraryClipboard/<UUID>/<UUID>.<検証済み拡張子>
```

- 保存名は外部由来の `suggestedName` をそのまま使わない。UUID を基礎にし、拡張子のみ許可リスト（`png` / `jpg` / `jpeg` / `heic` / `heif` / `gif` / `tiff` / `webp` / `txt` / `pdf`、非該当は `bin`）で検証する
- 標準化パスが専用ディレクトリ配下であることを検証してからコピーする
- 失敗・キャンセル・loader 解放時はディレクトリ単位で削除する
- 成功時のみ所有権が呼び出し側へ移る（削除責務も呼び出し側。DocC に明記）
- `IosClipboardManager` の初期化時に `IosLibraryClipboard/` 配下の残骸を一括削除する（D-7）

**エラーハンドリング**: `noMatchingItem` / `providerLoadFailed` / `unexpectedType` / `fileCopyFailed` / `cancelled`

---

### S6 内容確認

**データ構造**

```swift
public struct ClipboardSnapshot: Equatable, Sendable {
    public let hasStrings: Bool
    public let hasURLs: Bool
    public let hasImages: Bool
    public let hasColors: Bool
    public let numberOfItems: Int
    public let typeIdentifiers: [String]          // 先頭アイテムの types
    public let allTypeIdentifiers: [[String]]     // types(forItemSet: nil)
}
```

**制御フロー**: `GetSnapshotUseCase` → `repository.snapshot(scope:)`。使用するのは公式が「通知・アラートを避ける API」として列挙しているものだけ（`has*` / `numberOfItems` / `types` / `types(forItemSet:)`）。`contains(pasteboardTypes:)` は内部の型判定にのみ使い、公開しない（D-3）。

**エラーハンドリング**: なし（常に値を返す）。

---

### S7 クリア

- `ClearClipboardUseCase` → `repository.clear(scope:)` → `pasteboard.items = []`
- 名前付きペーストボードそのものの破棄は S1 の `RemovePasteboardUseCase`
- エラー: `pasteboardUnavailable` のみ

---

### S8 変更監視

**Delegate 所有**: `IosClipboardManager` が `NotificationCenter` の 2 トークン（`changedNotification` / `removedNotification`）を単独で保持する。Presentation / Data / Unity Bridge には置かない。

**データ構造**

```swift
public struct ClipboardChangeEvent: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case changed(typesAdded: [String], typesRemoved: [String])
        case changedDetectedOnForeground     // changeCount 差分による検知
        case removed                          // 名前付きペーストボードの破棄
    }
    public let kind: Kind
    public let scope: PasteboardScope
}
```

**`ClipboardChangeTracker`（Application 層 / 純ロジック / テスト対象）**

```swift
public struct ClipboardChangeTracker {
    private var baseline: Int
    public init(baseline: Int)
    /// Resyncs on start so a stop/start cycle never compares against a stale baseline.
    public mutating func resync(to current: Int)
    /// Advances the baseline when a notification already reported the change.
    public mutating func markReported(current: Int)
    /// Returns true only when the current count differs from the baseline; always advances it.
    public mutating func hasChanged(current: Int) -> Bool
}
```

同期規則（企画書の 4 点をそのまま実装）:

1. `startObserving` で `resync`
2. `changedNotification` 受信時に `markReported`（通知経路で報告済みの変更を foreground 比較で二重報告しない）
3. `checkForegroundChange()` は比較後に必ず基準値を更新
4. `stopObserving` 後に到着した通知は購読者へ配信しない（トークン解除 + 世代 ID でガード）

**制御フロー**

1. `startObserving(scope:onEvent:)`: 既に監視中なら先に `stopObserving()`（二重登録防止）→ トラッカー resync → トークン登録
2. 通知ブロックは `Sendable` 制約のため `Task { @MainActor in ... }` で状態更新し、`onEvent` を main で呼ぶ
3. `stopObserving()`: 両トークンを `removeObserver` し nil 化。二重停止しても安全
4. `deinit` でも `stopObserving()`

**エラーハンドリング**: 監視自体は失敗しない。`.named` が解決できない場合のみ `pasteboardUnavailable`。

---

### S9 パターン検出

**データ構造**

```swift
public struct ClipboardDetectedValues: Equatable, Sendable {
    public let probableWebURL: String?
    public let probableWebSearch: String?
    public let number: Double?
    public let links: [String]
    public let emailAddresses: [String]
    public let phoneNumbers: [String]
    // 住所 / 日時 / 便名 / 金額 / 追跡番号は「検出有無」のみ公開する
    public let detectedPatterns: Set<ClipboardDetectionPattern>
}

public enum ClipboardDetectionPattern: String, CaseIterable, Sendable {
    case probableWebURL, probableWebSearch, number, link, emailAddress,
         phoneNumber, postalAddress, calendarEvent, flightNumber,
         moneyAmount, shipmentTrackingNumber
}
```

`DDMatch*` の構造化フィールドを全て公開すると Bridge の JSON が肥大化するため、文字列化しやすい 6 種のみ値を返し、残りは有無のみとする（D-2）。

**制御フロー**: `DetectPatternsUseCase.detectPatterns(_:scope:)` / `.detectValues(_:scope:)` → Data 層で `ClipboardDetectionPattern` → `PartialKeyPath<UIPasteboard.DetectedValues>` へ変換 → `detectedPatterns(for:)` / `detectedValues(for:)`（async 版）→ ドメイン型へ変換。

**エラーハンドリング**: `detectionFailed(Error)`。空セットを渡した場合は `emptyItemList` ではなく `emptyDetectionPatterns`。

---

### S10 貼り付け UI（ネイティブのみ）

**Presentation 層**

```swift
public final class ClipboardPasteReceiverView: UIView {
    public var onPaste: (([ClipboardLoadedItem]) -> Void)?
    public var onPasteFailure: ((ClipboardError) -> Void)?
    public override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool
    public override func paste(itemProviders: [NSItemProvider])
}

public enum PasteControlFactory {
    public static func makePasteControl(
        acceptedTypes: [String],
        displayMode: UIPasteControl.DisplayMode,
        receiver: ClipboardPasteReceiverView
    ) -> UIPasteControl
}
```

- `receiver.pasteConfiguration` を `acceptedTypes` で設定し、`control.target = receiver` を必ずセットする（未設定だとタップが無反応になる企画書リスクへの対処）
- 型の優先順位は text > image > url > file（D-4）
- 1 provider の失敗は他を止めず、全 provider 処理後に成功分をまとめて `onPaste`、失敗分は `onPasteFailure` へ（部分失敗仕様）

**Manager からの公開**

```swift
public func makePasteControl(
    acceptedTypes: [String],
    displayMode: UIPasteControl.DisplayMode = .iconAndLabel,
    onPaste: @escaping ([ClipboardLoadedItem]) -> Void
) -> (control: UIPasteControl, receiver: ClipboardPasteReceiverView)
```

呼び出し側は `receiver` も view 階層に追加する必要がある（responder chain 上に存在しないと動作しないため）。DocC に明記する。

**Unity Bridge には公開しない**（D-1）。

---

### S11 Unity Bridge

**JSON 仕様（抜粋）**

コピー要求:

```json
{
  "scope": { "kind": "general" },
  "content": { "kind": "plainText", "text": "hello" },
  "options": { "localOnly": true, "expirationDate": null, "replaceExisting": true }
}
```

`imageData` / `customData` の `data` は Base64 文字列で受け渡す（C ABI はバイナリを直接扱えないため）。

読み取り結果:

```json
{
  "numberOfItems": 1,
  "items": [{ "typeIdentifiers": ["public.utf8-plain-text"], "text": "hello", "urlString": null, "imageDataUTType": null }]
}
```

エラー:

```json
{ "error": "CLIPBOARD_EMPTY_CONTENT", "message": "Clipboard content is empty. Please provide text or HTML." }
```

**C ABI**

```c
typedef void (*ClipboardOperationCallback)(bool isSuccess,
                                           const char* errorCode,
                                           const char* errorMessage);
typedef void (*ClipboardJsonCallback)(const char* json);
typedef void (*ClipboardChangeCallback)(const char* eventJson);

void clipboardCopy(const char* requestJson, ClipboardOperationCallback callback);
void clipboardRead(const char* scopeJson, ClipboardJsonCallback callback);
void clipboardGetSnapshot(const char* scopeJson, ClipboardJsonCallback callback);
void clipboardClear(const char* scopeJson, ClipboardOperationCallback callback);
void clipboardCreatePasteboard(const char* requestJson, ClipboardJsonCallback callback);
void clipboardRemovePasteboard(const char* scopeJson, ClipboardOperationCallback callback);
void clipboardDetectValues(const char* requestJson, ClipboardJsonCallback callback);
void clipboardLoadItem(const char* requestJson, ClipboardJsonCallback callback);
void clipboardCancelLoads(void);
void clipboardStartObserving(const char* scopeJson, ClipboardChangeCallback callback);
void clipboardStopObserving(void);
void clipboardCheckForegroundChange(ClipboardJsonCallback callback);
```

`.m` の完了ブロック引数は `BOOL` / `NSString * _Nullable` を使う（ios.md）。

---

## API 設計（公開 / 内部）

### 公開 API（`IosClipboardManager`）

全メソッドに callback 版と `async throws` 版を用意する（common.md / ios.md）。callback は**全経路で main actor から 1 回だけ**呼ぶ。

| # | callback 版 | `async throws` 版 | 備考 |
|---|---|---|---|
| P-1 | `copy(_:options:scope:completion:(Bool, String?) -> Void)` | `copy(_:options:scope:) async throws` | |
| P-2 | `read(scope:completion:(ClipboardReadResult?, String?) -> Void)` | `read(scope:) async throws -> ClipboardReadResult` | |
| P-3 | `readData(utType:scope:completion:)` | `readData(utType:scope:) async throws -> Data?` | 任意 UTI の本体取得 |
| P-4 | `snapshot(scope:completion:)` | `snapshot(scope:) async throws -> ClipboardSnapshot` | 通知非対象 API のみ使用 |
| P-5 | `clear(scope:completion:)` | `clear(scope:) async throws` | |
| P-6 | `createPasteboard(_:completion:)` | `createPasteboard(_:) async throws -> PasteboardScope` | `.unique` は生成名入りで返る |
| P-7 | `removePasteboard(_:completion:)` | `removePasteboard(_:) async throws` | `.general` は拒否 |
| P-8 | `detectPatterns(_:scope:completion:)` | `detectPatterns(_:scope:) async throws -> Set<ClipboardDetectionPattern>` | |
| P-9 | `detectValues(_:scope:completion:)` | `detectValues(_:scope:) async throws -> ClipboardDetectedValues` | |
| P-10 | `loadItem(_:scope:completion:) -> ClipboardLoadToken` | `loadItem(_:scope:) async throws -> ClipboardLoadedItem` | async 版は `withTaskCancellationHandler` でトークンを cancel |
| P-11 | `cancelAllLoads()` | 同左（同期） | 各 pending に `.cancelled` を 1 回配信 |
| P-12 | `startObserving(scope:onEvent:)` | 同左（同期） | 二重開始時は先に stop |
| P-13 | `stopObserving()` | 同左（同期） | 二重停止安全 |
| P-14 | `checkForegroundChange(scope:) -> Bool` | 同左（同期） | `changeCount` 差分（D-3） |
| P-15 | `makePasteControl(acceptedTypes:displayMode:onPaste:)` | 同左（同期） | Unity 非公開（D-1） |

### 内部 API

| 型 | 可視性 | 理由 |
|---|---|---|
| `ClipboardRepository` / `ClipboardItemLoader` | `public`（protocol） | Manager の test 用 init で注入するため（`ShareRepository` と同じ扱い） |
| `ClipboardRepositoryImpl` / `ClipboardItemLoaderImpl` | `internal` | UIKit 依存を外部へ露出しない（`ShareRepositoryImpl` と同じ） |
| `PasteboardResolver` / `ClipboardMappers` / `ClipboardTemporaryFileStore` | `internal` | Data 層の実装詳細 |
| `ClipboardChangeTracker` | `public` | 単体テスト対象かつ純ロジック |
| UseCase 群 | `public` | 既存 `ShareContentUseCase` に合わせる |

---

## ドメインエラー一覧（全ケース）

```swift
public enum ClipboardError: Error {
    case emptyContent
    case emptyItemList
    case emptyDetectionPatterns
    case invalidURL(String)
    case invalidTypeIdentifier(String)
    case invalidPasteboardName(String)
    case fileNotFound(path: String)
    case imageLoadFailed(path: String)
    case imageEncodingFailed
    case pasteboardUnavailable(name: String)
    case cannotRemoveGeneralPasteboard
    case optionsNotApplicableForAppend
    case noMatchingItem
    case providerLoadFailed(Error)
    case unexpectedType
    case fileCopyFailed(Error)
    case cancelled
    case detectionFailed(Error)
    case unknown(Error)
}
```

| # | ケース | 発生箇所 | 発生条件 |
|---|---|---|---|
| E-1 | `emptyContent` | `CopyContentUseCase` | `htmlText` の html が空白のみ / `imageData` / `customData` が空 |
| E-2 | `emptyItemList` | `CopyContentUseCase` | `multipleText` が空配列 / `multiRepresentation` が空辞書 |
| E-3 | `emptyDetectionPatterns` | `DetectPatternsUseCase` | 検出パターン集合が空 |
| E-4 | `invalidURL` | `CopyContentUseCase` | 空 / スキーム無し / http(s) で host 無し |
| E-5 | `invalidTypeIdentifier` | `CopyContentUseCase` | UTI が空 / 逆 DNS 形式でない |
| E-6 | `invalidPasteboardName` | `CreatePasteboardUseCase` | 名前が空白のみ |
| E-7 | `fileNotFound` | `ClipboardRepositoryImpl` | `imageFile` のパスが存在しない |
| E-8 | `imageLoadFailed` | `ClipboardRepositoryImpl` | `UIImage(contentsOfFile:)` が nil |
| E-9 | `imageEncodingFailed` | `ClipboardItemLoaderImpl` | `UIImage` → `pngData()` が nil |
| E-10 | `pasteboardUnavailable` | `PasteboardResolver` | `UIPasteboard(name:create:)` が nil |
| E-11 | `cannotRemoveGeneralPasteboard` | `RemovePasteboardUseCase` | `.general` を破棄しようとした |
| E-12 | `optionsNotApplicableForAppend` | `CopyContentUseCase` | `replaceExisting == false` かつ非既定オプション指定 |
| E-13 | `noMatchingItem` | `ClipboardItemLoaderImpl` | 条件に合う provider が無い |
| E-14 | `providerLoadFailed` | `ClipboardItemLoaderImpl` | provider の completion が error を返した |
| E-15 | `unexpectedType` | `ClipboardItemLoaderImpl` | error は nil だが期待型に変換できない |
| E-16 | `fileCopyFailed` | `ClipboardTemporaryFileStore` | ディレクトリ作成 / コピー失敗、containment 検証失敗 |
| E-17 | `cancelled` | `ClipboardItemLoaderImpl` | `cancelAll()` / `deinit` / token `cancel()` |
| E-18 | `detectionFailed` | `ClipboardRepositoryImpl` | `detectedValues(for:)` が throw |
| E-19 | `unknown` | 全層 | 上記に該当しないシステムエラー |

---

## エラーコード / メッセージ対応表

Bridge 返却仕様。`errorCode` は Android の `CLIPBOARD_*` 命名と揃える。`message` は英語（ios.md）。

| ドメインエラー | errorCode | message | callback 版の値 |
|---|---|---|---|
| `emptyContent` | `CLIPBOARD_EMPTY_CONTENT` | `Clipboard content is empty. Please provide text or HTML.` | `(false, message)` |
| `emptyItemList` | `CLIPBOARD_EMPTY_ITEMS` | `No items provided for clipboard copy.` | `(false, message)` |
| `emptyDetectionPatterns` | `CLIPBOARD_EMPTY_PATTERNS` | `No detection patterns were specified.` | `(false, message)` |
| `invalidURL(v)` | `CLIPBOARD_INVALID_URL` | `Invalid URL: {v}` | `(false, message)` |
| `invalidTypeIdentifier(v)` | `CLIPBOARD_INVALID_TYPE` | `Invalid uniform type identifier: {v}` | `(false, message)` |
| `invalidPasteboardName(v)` | `CLIPBOARD_INVALID_NAME` | `Invalid pasteboard name: {v}` | `(false, message)` |
| `fileNotFound(path)` | `CLIPBOARD_FILE_NOT_FOUND` | `File not found at path: {path}` | `(false, message)` |
| `imageLoadFailed(path)` | `CLIPBOARD_IMAGE_LOAD_FAILED` | `Failed to load image at path: {path}` | `(false, message)` |
| `imageEncodingFailed` | `CLIPBOARD_IMAGE_ENCODE_FAILED` | `Failed to encode the pasted image.` | `(false, message)` |
| `pasteboardUnavailable(name)` | `CLIPBOARD_UNAVAILABLE` | `Pasteboard is unavailable: {name}. A named pasteboard exists only while its creating app is running.` | `(false, message)` |
| `cannotRemoveGeneralPasteboard` | `CLIPBOARD_CANNOT_REMOVE_GENERAL` | `The general pasteboard cannot be removed.` | `(false, message)` |
| `optionsNotApplicableForAppend` | `CLIPBOARD_OPTIONS_NOT_APPLICABLE` | `localOnly and expirationDate cannot be applied when appending items.` | `(false, message)` |
| `noMatchingItem` | `CLIPBOARD_NO_MATCHING_ITEM` | `No clipboard item matches the requested type.` | `(false, message)` |
| `providerLoadFailed(e)` | `CLIPBOARD_LOAD_FAILED` | `Failed to load clipboard item: {e.localizedDescription}` | `(false, message)` |
| `unexpectedType` | `CLIPBOARD_UNEXPECTED_TYPE` | `The clipboard item could not be converted to the requested type.` | `(false, message)` |
| `fileCopyFailed(e)` | `CLIPBOARD_FILE_COPY_FAILED` | `Failed to copy the pasted file: {e.localizedDescription}` | `(false, message)` |
| `cancelled` | `CLIPBOARD_CANCELLED` | `The clipboard load was cancelled.` | `(false, message)` |
| `detectionFailed(e)` | `CLIPBOARD_DETECTION_FAILED` | `Pattern detection failed: {e.localizedDescription}` | `(false, message)` |
| `unknown(e)` | `CLIPBOARD_UNKNOWN` | `An unknown error occurred: {e.localizedDescription}` | `(false, message)` |

`cancelled` を `isSuccess == false` として扱う理由: Share の「ユーザーキャンセルは成功」とは異なり、クリップボードのロードキャンセルは呼び出し側（画面破棄など）が起点であり、結果を利用できないため。呼び出し側は `errorCode == "CLIPBOARD_CANCELLED"` を正常系として無視できる。この扱いは DocC と Bridge ヘッダに明記する。

---

## テスト設計

### 単体テスト（Swift Testing / `IosLibraryTests`）

#### Application 層（Mock 注入）

| ID | 対象 | 系 | ケース |
|---|---|---|---|
| U-01 | `CopyContentUseCase` | 正常 | 各 `ClipboardContent` で `copyCallCount == 1`、渡した options が一致 |
| U-02 | 〃 | 異常 | `htmlText` の html 空白 → `emptyContent` |
| U-03 | 〃 | 異常 | `multipleText([])` → `emptyItemList` |
| U-04 | 〃 | 異常 | `url("")` / `url("example.com")` / `url("https://")` → `invalidURL` |
| U-05 | 〃 | 異常 | UTI 空 / 不正 → `invalidTypeIdentifier` |
| U-06 | 〃 | 異常 | `replaceExisting == false` + `expirationDate` 指定 → `optionsNotApplicableForAppend` |
| U-07 | 〃 | 境界 | `plainText("")` は成功する |
| U-08 | 〃 | 異常 | `shouldFail = true` → Repository のエラーがそのまま伝播 |
| U-09 | `ReadContentUseCase` | 正常 | `stubbedReadResult` をそのまま返す |
| U-10 | 〃 | 境界 | 空クリップボード → `items == []` かつ throw しない |
| U-11 | `GetSnapshotUseCase` | 正常 | `stubbedSnapshot` を返す |
| U-12 | `ClearClipboardUseCase` | 正常 | `clearCallCount == 1` |
| U-13 | `CreatePasteboardUseCase` | 異常 | 空白名 → `invalidPasteboardName` |
| U-14 | `RemovePasteboardUseCase` | 異常 | `.general` → `cannotRemoveGeneralPasteboard` |
| U-15 | `DetectPatternsUseCase` | 異常 | 空集合 → `emptyDetectionPatterns` |
| U-16 | 〃 | 正常 | `stubbedDetectedValues` を返す |
| U-17 | `LoadItemUseCase` | 正常 / 異常 | 各 `ClipboardLoadedItem` / 各エラーの伝播 |

#### `ClipboardChangeTracker`（純ロジック）

| ID | 系 | ケース |
|---|---|---|
| U-18 | 正常 | `hasChanged` は基準値と異なるとき true、同じとき false |
| U-19 | 正常 | `hasChanged` 呼び出し後は基準値が更新され、連続呼び出しは false |
| U-20 | 境界 | `markReported` 後の `hasChanged` は false（通知と foreground の二重報告防止） |
| U-21 | 境界 | `resync` 後は停止中の変更を検知しない |

#### Data 層（実 `UIPasteboard` = `withUniqueName()` を使用。general は汚染しない）

| ID | 系 | ケース |
|---|---|---|
| U-22 | 正常 | 各 `ClipboardContent` を書き込み → `read` で往復一致 |
| U-23 | 正常 | `multiRepresentation` で 1 アイテムに 2 UTI が載る |
| U-24 | 正常 | `replaceExisting == false` で件数が増える |
| U-25 | 正常 | `clear` 後に `numberOfItems == 0` |
| U-26 | 正常 | `snapshot` の `has*` が内容と一致 |
| U-27 | 異常 | 存在しない画像パス → `fileNotFound` |
| U-28 | 異常 | 解決できない名前 → `pasteboardUnavailable` |
| U-29 | 正常 | `remove(withName:)` 後に `create: false` で解決できない |

#### `ClipboardTemporaryFileStore`

| ID | 系 | ケース |
|---|---|---|
| U-30 | 正常 | コピー成功時にファイルが存在し、専用ディレクトリ配下にある |
| U-31 | 異常 | `suggestedName` が `../../evil.png` → 専用ディレクトリ外に出ない |
| U-32 | 異常 | `suggestedName` にパス区切り / 制御文字 / 1000 文字超 → 生成名は UUID + 許可拡張子のみ |
| U-33 | 境界 | 許可外拡張子 → `bin` になる |
| U-34 | 正常 | コピー失敗時にディレクトリが残らない |
| U-35 | 正常 | 起動時 cleanup で `IosLibraryClipboard/` 配下の残骸が消える |

#### `ClipboardError`

| ID | 系 | ケース |
|---|---|---|
| U-36 | 正常 | 全 19 ケースの `errorDescription` が非 nil かつ英語 |
| U-37 | 正常 | 全 19 ケースの errorCode が対応表と一致し、重複がない |

#### Manager（Mock 注入）

| ID | 系 | ケース |
|---|---|---|
| U-38 | 正常 | callback 版が **main thread** で **1 回だけ** 呼ばれる（全 API） |
| U-39 | 異常 | Repository エラー → `(false, errorMessage != nil)` |
| U-40 | 正常 | `async throws` 版が型付きエラーを throw する |
| U-41 | 正常 | `startObserving` 二重呼び出しでイベントが重複しない |
| U-42 | 正常 | `stopObserving` 後にイベントが届かない |
| U-43 | 正常 | `stopObserving` → `startObserving` で古いイベントが新購読者へ届かない |
| U-44 | 正常 | `cancelAllLoads()` で各 pending に `.cancelled` が 1 回だけ届く |
| U-45 | 正常 | provider 不在の即時失敗直後に `cancelAllLoads()` → 通知は 1 回のみ |
| U-46 | 正常 | Manager 解放時に pending へ `.cancelled` が 1 回届く |

#### Unity Bridge（`UnityIosPluginTests`）

| ID | 系 | ケース |
|---|---|---|
| U-47 | 正常 | 各 `ClipboardContent` の JSON パース往復 |
| U-48 | 異常 | 不正 JSON → `CLIPBOARD_UNKNOWN` 相当のエラー JSON を main で 1 回返す |
| U-49 | 正常 | Base64 の `imageData` / `customData` を復元できる |
| U-50 | 正常 | `ClipboardReadResult` / `ClipboardSnapshot` / `ClipboardDetectedValues` の JSON 化キーが仕様と一致 |
| U-51 | 正常 | エラー JSON が `{"error": code, "message": msg}` 形式 |

### 統合テスト

| ID | 内容 |
|---|---|
| I-01 | `IosClipboardManager` 実体（Mock なし）で copy → snapshot → read → clear が一貫する（`.unique` scope） |
| I-02 | `.named` を 2 つのスコープから読み書きし、`remove` 後に解決できない |
| I-03 | `setItems` の `localOnly` / `expirationDate` が例外なく適用される |
| I-04 | `startObserving` 中に自アプリで copy → `changed` イベントが 1 回届く |
| I-05 | `loadItem(.file)` の成功 URL が completion 後も読める |
| I-06 | `loadItem` 実行中に `cancelAllLoads()` → `.cancelled` 1 回、一時ディレクトリ残留なし |
| I-07 | Swift 6 strict concurrency 設定でビルド警告が出ない |

### 手動確認項目（企画書リスク対応。実機必須）

| ID | 対応リスク | 内容 |
|---|---|---|
| M-01 | プライバシー | 企画書「テスト行列」16 ケースを iOS 18 / iOS 26 実機で観測し、許可プロンプトとアクセス通知を別列で記録する |
| M-02 | プライバシー | `snapshot` のみの呼び出しで通知・プロンプトが出ないことを確認 |
| M-03 | プライバシー | `checkForegroundChange`（`changeCount`）で通知・プロンプトが出るかを確認し、出る場合は D-3 の判断を見直す |
| M-04 | プライバシー | `detectValues` で通知・プロンプトが出ないことを確認 |
| M-05 | Universal Clipboard | 同一 2 台・同一 iCloud・同一 Handoff 設定で、`localOnly: false` の転送成功（正の対照）→ `true` の非転送を確認 |
| M-06 | 機微データ残留 | `expirationDate` 経過後に内容が取得できないことを確認 |
| M-07 | 名前付き寿命 | 送信側アプリ終了後に受信側から解決できないこと、バックグラウンド中は解決できることを確認 |
| M-08 | App Group | entitlement 設定済みの同一 Team ID 別アプリ間で読み書きできることを確認 |
| M-09 | `UIPasteControl` | ボタンが表示され、タップで許可プロンプトなしに貼り付けできる。`target` / `pasteConfiguration` 未設定時の挙動も確認 |
| M-10 | `UIPasteControl` | 画像のみのクリップボードでも動作する（宣言型と実処理の一致） |
| M-11 | 一時ファイル | アプリ強制終了後の再起動で残骸が cleanup される |
| M-12 | 画像コスト | `imageData` 経路と `image` プロパティ経路のエンコード時間・ピークメモリを Instruments で比較 |
| M-13 | 変更監視 | 通知経路で報告済みの変更が foreground 復帰時に二重報告されない |
| M-14 | ログ | コピー / ペーストした値そのものがログに出ていない |

---

## 実装タスク分解（依存関係付き）

| ID | タスク | 粒度 | 依存 | 完了条件 | レビュー観点 |
|---|---|---|---|---|---|
| T-01 | Domain 層（モデル 9 種 + `ClipboardError`）を作成 | 0.5日 | なし | 全 public 型に DocC。`UIKit` を import していない。U-36 / U-37 が green | Domain の純粋性、エラー網羅（19 ケース） |
| T-02 | Application Port 2 種 + `ClipboardChangeTracker` を作成 | 0.5日 | T-01 | Port の引数・戻り値がドメイン型のみ。U-18〜U-21 が green | Port の型制約、同期規則 4 点 |
| T-03 | UseCase 8 種 + `ClipboardUseCases` + Mock 2 種を作成 | 1.5日 | T-02 | U-01〜U-17 が green。Mock は `shouldFail` / CallCount / `stubbedXxx` パターン | 入力検証の網羅、TDD 順序 |
| T-04 | `PasteboardResolver` / `ClipboardMappers` / `ClipboardRepositoryImpl` を実装 | 1.5日 | T-03 | U-22〜U-29 が green。`setValue` 不使用 | UIKit 依存の閉じ込め、UTI 変換 |
| T-05 | `ClipboardTemporaryFileStore` を実装 | 1日 | T-01 | U-30〜U-35 が green | path traversal 防止、cleanup 網羅 |
| T-06 | `ClipboardItemLoaderImpl` を実装（契約 6 点） | 1.5日 | T-05, T-03 | 全経路で completion が main から 1 回。キャンセル gate が機能 | exactly-once、`Progress` 蓄積なし |
| T-07 | `IosClipboardManager` を実装（callback + async throws、監視トークン所有） | 1.5日 | T-04, T-06 | U-38〜U-46 が green。監視トークンが Manager 以外に存在しない | Delegate 所有ルール、二重開始 / 停止 |
| T-08 | Presentation（`ClipboardPasteReceiverView` / `PasteControlFactory`）を実装 | 1日 | T-06 | 受信 View が text / image / url / file を優先順位どおり処理。部分失敗で他を止めない | responder chain 要件、型の一致 |
| T-09 | `UnityIosClipboardJsonParser` を実装 | 1日 | T-01 | U-47〜U-51 が green | Base64、キー名、エラー JSON 形式 |
| T-10 | `UnityIosClipboardManager` + Bridge `.h` / `.m` を実装 | 1日 | T-09, T-07 | 全 C 関数が動作。ブロック引数が `BOOL` | Bridge の薄さ、main 配信、HeaderDoc |
| T-11 | 統合テスト I-01〜I-07 を追加 | 1日 | T-07, T-10 | 全て green。Swift 6 strict concurrency で警告なし | 実 `UIPasteboard` の汚染防止（`.unique` 使用） |
| T-12 | サンプルアプリ対応（詳細は `design-sample-app`） | - | T-07, T-08 | S1〜S10 の全サブ機能を `IosLibraryExample` から操作でき、`IosLibrary` のみに依存する | Unity プラグイン非依存 |
| T-13 | 手動確認 M-01〜M-14 を実施し結果を記録 | 1.5日 | T-12 | 企画書テスト行列の観測欄が iOS 18 / iOS 26 で埋まる | 断定せず観測値を記載しているか |
| T-14 | DocC（`IosLibrary.md`）に Clipboard セクションを追記 | 0.5日 | T-07 | 名前付きの寿命、一時ファイルの削除責務、プライバシー挙動、`cancelled` の扱いが明記されている | 誤用を招く記述がないか |

**先行タスク（基盤）**: T-01 〜 T-07
**後続タスク（拡張）**: T-08 〜 T-14

依存グラフ:

```
T-01 → T-02 → T-03 → T-04 ┐
  └──→ T-05 → T-06 ───────┴→ T-07 → T-08 → T-12 → T-13
  └──→ T-09 → T-10 ────────→ T-11
                    T-07 → T-14
```

---

## リスクと緩和策

| # | リスク | 影響 | 緩和策 | 状態 |
|---|---|---|---|---|
| R-01 | `changeCount` が通知・プロンプトの対象だった場合、`checkForegroundChange` が使えない | S8 の foreground 検知が成立しない | M-03 で先に観測する。対象だった場合は `changedNotification` のみに縮退し、その制約を DocC に明記する | 要検証 |
| R-02 | `itemProviders` getter 自体がプロンプト契機の場合、S5 / S6 の分離が崩れる | 事前判定の意味が薄れる | M-01（ケース 13〜15）で切り分け。getter が契機なら S5 は `UIPasteControl` 経路を推奨に格上げする | 要検証 |
| R-03 | Swift 6 strict concurrency で `NSItemProvider` 捕捉の警告 | 将来の移行が困難 | `@MainActor` loader + 必要値のみ捕捉（provider を closure に持ち込まない）。I-07 で検証 | 緩和済み（要検証） |
| R-04 | 実 `UIPasteboard` を使うテストが CI 環境で不安定 | テストの信頼性低下 | Data 層テストは `withUniqueName()` を使い general を触らない。CI で不安定な場合はシミュレータ限定タグを付ける | 緩和済み |
| R-05 | `UIPasteControl` が Unity から使えない | Unity 利用者は許可プロンプトを回避できない | D-1 として明示し、Unity 側はプロンプト前提の API とすることをドキュメント化。将来 Unity の UI 統合が必要になった場合は別機能として設計 | 受容 |
| R-06 | 一時ファイルがアプリ強制終了時に残る | ストレージ圧迫 | Manager 初期化時に専用ルートを一括削除（D-7）。M-11 で確認 | 緩和済み |
| R-07 | クリップボード値がログに出て情報漏洩 | 機微情報の露出 | 追加ルール（値を出さず長さ・型のみ）を全 Manager / Bridge に適用。M-14 で確認 | 緩和済み |
| R-08 | `localOnly` 既定 `true` が既存 Android 実装と挙動差になる | クロスプラットフォームの体感差 | Android には対応概念がないため差分は不可避。README / マニュアルで iOS 固有オプションとして説明する | 受容 |
| R-09 | Domain から `UIImage` を排除したことで画像ペーストに再エンコードが入る | 性能低下 | M-12 で計測し、閾値超なら `imageDataUTType` のみ返して本体取得を別 API に分ける案へ切り替える | 要検証 |
| R-10 | `cancelled` を `isSuccess == false` とする扱いが Share の慣例と異なる | 利用者の混乱 | エラーコード表・DocC・Bridge ヘッダの 3 箇所で理由を明記。サンプルアプリでも無視例を示す | 緩和済み |

---

## Definition of Done

### 実装

- [ ] `ios/IosLibrary/IosLibrary/Clipboard/` に Domain / Application / Data / Presentation / Manager が揃い、依存方向違反がない
- [ ] Port の引数・戻り値にプラットフォーム型（`UIPasteboard` / `NSItemProvider` / `UTType` / `UIImage`）が含まれない
- [ ] `IosClipboardManager` が全操作で callback 版と `async throws` 版を提供する
- [ ] Manager が Repository を直接呼ばず、全て UseCase 経由である
- [ ] `changedNotification` / `removedNotification` の監視トークンを `IosClipboardManager` のみが保持し、Presentation / Data / Unity Bridge に監視コードがない
- [ ] `ios/UnityIosPlugin/UnityIosPlugin/Clipboard/` に Unity Bridge 層のみが存在し、Manager 層以下のクラスが置かれていない
- [ ] 全 public シンボルに DocC コメント（英語）がある
- [ ] 全 `public` / `internal` / `override` / `@objc` 関数と Bridge C 関数の先頭に `Log.d` / `Log.e` がある
- [ ] クリップボードの値そのものがログに出力されない（長さ・型のみ）
- [ ] Bridge `.m` の完了ブロック引数が `BOOL` / `NSString * _Nullable` である
- [ ] 既存 Notification / Dialog / Share のファイルに変更がない（破壊的変更なし）

### 機能

- [ ] S1: `.general` / `.named` / `.unique` の解決・作成・破棄が動作する
- [ ] S2 / S3: 9 種の `ClipboardContent` と `localOnly` / `expirationDate` / `replaceExisting` が動作する
- [ ] S4: 同期読み取りと任意 UTI の `Data` 取得が動作する
- [ ] S5: text / image / file の非同期ロードが契約 6 点どおりに動作する
- [ ] S6: `ClipboardSnapshot` が公式の通知非対象 API のみで構成される
- [ ] S7: クリアと名前付き破棄が動作する
- [ ] S8: 変更 / 破棄イベントと foreground 差分検知が動作し、二重報告がない
- [ ] S9: パターン検出が動作し、`PartialKeyPath` / `DDMatch*` が公開 API に露出しない
- [ ] S10: `UIPasteControl` + 受信 View がネイティブから利用でき、宣言型と実処理が一致する
- [ ] S11: 全 C 関数が JSON 仕様どおりに動作する

### テスト

- [ ] 単体テスト U-01 〜 U-51 が全て green（Swift Testing、XCTest 不使用）
- [ ] 統合テスト I-01 〜 I-07 が全て green
- [ ] Mock が `shouldFail` / per-method CallCount / `stubbedXxx` パターンに従う
- [ ] 実 `UIPasteboard` を使うテストが `general` を汚染しない
- [ ] `IosLibrary` / `UnityIosPlugin` の全スキームでテストが passed
- [ ] 手動確認 M-01 〜 M-14 を実施し、結果を記録した（プライバシー挙動は断定せず観測値を記載）

### ドキュメント

- [ ] `IosLibrary.docc/IosLibrary.md` に Clipboard セクションがある
- [ ] 名前付きペーストボードが非永続であること、永続共有は App Group shared container の責務であることを明記した
- [ ] `loadItem(.file)` の成功 URL の削除責務が呼び出し側にあることを明記した
- [ ] `read` 系がプロンプト / 通知の対象になりうること、事前判定には `snapshot` を使うことを明記した
- [ ] `cancelled` を `isSuccess == false` として返す理由を明記した
- [ ] `docs/` 配下を変更していない

---

## 要検証事項（設計時点で未確定）

| 項目 | 内容 | 確認タイミング |
|---|---|---|
| `changeCount` の通知非対象性 | 対象だった場合 D-3 と S8 の設計を見直す | T-13（M-03） |
| `itemProviders` getter の契機 | 対象だった場合 S5 の推奨経路を変更する | T-13（M-01） |
| 画像の Data 化コスト | 閾値超なら R-09 の代替案へ | T-13（M-12） |
| `expirationDate` に過去日時を渡した場合の挙動 | 拒否すべきか許容すべきかを再判断 | T-11 / T-13 |
| Swift 6 strict concurrency の警告有無 | 警告が残る場合は async API 化を追加タスク化 | T-11（I-07） |
| `loadItem` の非推奨バージョン | 使用しないため実装影響はないが、API 表の正確性のため SDK header で確認 | T-01 |
