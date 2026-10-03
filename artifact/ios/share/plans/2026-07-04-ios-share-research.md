# iOS 共有（Share）機能 調査企画書

- 対象OS: iOS 18 以降
- 使用言語: Swift
- 作成日: 2026-07-04
- 出力言語: 日本語

---

## 1. 目的

iOS における「共有（Share）」機能を、公式ドキュメントを最優先ソースとして API 全網羅で調査し、実装着手に耐える企画書としてまとめる。対象は次の 2 方向を含む。

- 送る側（Export）: 自アプリのコンテンツを共有シート経由で他アプリ・サービスへ渡す
- 受ける側（Import）: 他アプリから共有された内容を Share Extension で受け取る

UIKit / SwiftUI 双方の標準 API を対象とし、iOS 18 以降で利用可能な構成を整理する。

---

## 2. 調査対象範囲（in / out）

### in（対象）

- 共有シート（Activity View / Share Sheet）の表示: `UIActivityViewController`
- SwiftUI での共有: `ShareLink` / `SharePreview`
- 共有アイテムのモデル化: `Transferable`（Core Transferable）と各 Representation
- 共有アイテムのカスタマイズ: `UIActivityItemSource` / `UIActivityItemProvider` / `UIActivityItemsConfiguration`
- プレビュー表示: `LPLinkMetadata`（LinkPresentation）
- 受け取り側: Share Extension（`NSExtensionActivationRule`, `SLComposeServiceViewController`, `NSItemProvider`）
- 除外・制御: `excludedActivityTypes`, `allowsProminentActivity`, `excludedActivitySectionTypes`, `completionWithItemsHandler`

### out（対象外）

- iCloud 共同編集（Collaboration / `NSItemProvider` collaboration mode）は概要のみ触れ、詳細実装は対象外
- AirDrop 固有の低レベル制御
- Messages App Extension / Sticker などの共有以外の拡張
- Universal Links / カスタム URL スキーム経由の受け渡し

---

## 3. 公式文書一覧（最優先ソース）

| 区分 | タイトル | URL |
| --- | --- | --- |
| HIG | Activity views（デザインガイドライン） | https://developer.apple.com/design/human-interface-guidelines/activity-views |
| UIKit | UIActivityViewController | https://developer.apple.com/documentation/uikit/uiactivityviewcontroller |
| UIKit | UIActivityItemSource | https://developer.apple.com/documentation/uikit/uiactivityitemsource |
| UIKit | UIActivityItemProvider | https://developer.apple.com/documentation/uikit/uiactivityitemprovider |
| UIKit | UIActivityItemsConfiguration | https://developer.apple.com/documentation/uikit/uiactivityitemsconfiguration |
| UIKit | UIActivity.ActivityType | https://developer.apple.com/documentation/uikit/uiactivity/activitytype |
| UIKit | activityViewControllerLinkMetadata(_:) | https://developer.apple.com/documentation/uikit/uiactivityitemsource/activityviewcontrollerlinkmetadata(_:) |
| UIKit | Collaborating and sharing copies of your data | https://developer.apple.com/documentation/uikit/collaborating-and-sharing-copies-of-your-data |
| SwiftUI | ShareLink | https://developer.apple.com/documentation/swiftui/sharelink |
| SwiftUI | SharePreview | https://developer.apple.com/documentation/swiftui/sharepreview |
| Core Transferable | Transferable | https://developer.apple.com/documentation/coretransferable/transferable |
| Core Transferable | TransferRepresentation | https://developer.apple.com/documentation/coretransferable/transferrepresentation |
| Core Transferable | FileRepresentation / SentTransferredFile / ReceivedTransferredFile | https://developer.apple.com/documentation/coretransferable/filerepresentation |
| LinkPresentation | LPLinkMetadata | https://developer.apple.com/documentation/linkpresentation/lplinkmetadata |
| Extension | App Extension Programming Guide: Share | https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/Share.html |
| Extension | App Extension Programming Guide: 制約・ライフサイクル（Extension Points / Handling Scenarios） | https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html |
| Extension | App Extension Keys（Info.plist 一覧） | https://developer.apple.com/library/archive/documentation/General/Reference/InfoPlistKeyReference/Articles/AppExtensionKeys.html |
| Extension | NSExtensionActivationRule | https://developer.apple.com/documentation/bundleresources/information-property-list/nsextension/nsextensionattributes/nsextensionactivationrule |
| Extension | NSExtensionContext | https://developer.apple.com/documentation/foundation/nsextensioncontext |
| Extension | NSExtensionItem | https://developer.apple.com/documentation/foundation/nsextensionitem |
| Foundation | NSItemProvider | https://developer.apple.com/documentation/foundation/nsitemprovider |
| UniformTypeIdentifiers | UTType | https://developer.apple.com/documentation/uniformtypeidentifiers/uttype |
| Bundle Resources | Exported/Imported Type Declarations（UTExportedTypeDeclarations） | https://developer.apple.com/documentation/bundleresources/information-property-list/utexportedtypedeclarations |
| Entitlements | App Groups Entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups |
| Social | SLComposeServiceViewController | https://developer.apple.com/documentation/social/slcomposeserviceviewcontroller |

---

## 4. 補助ソース一覧（必要時のみ）

| 情報源 | 用途 | 信頼度 |
| --- | --- | --- |
| WWDC22 「Meet Transferable」 (Session 10062) | Transferable の設計思想と Representation の使い分け | high（Apple 公式動画） |
| Apple Developer Forums（各 ShareLink/Transferable スレッド） | 既知の制約・不具合の把握（例: `suggestedFileName`、copy 動作の挙動差） | medium |

補足: 非公式の実装ブログ等は本企画書には採用せず、公式文書と WWDC 公式動画のみで構成した。

---

## 5. 機能マップ（サブ機能分解）

- S1. 共有シートの表示（UIKit） — `UIActivityViewController`
- S2. 共有シートの表示（SwiftUI） — `ShareLink` / `SharePreview`
- S3. 共有アイテムのモデル化 — `Transferable` / 各 Representation
- S4. 共有アイテムのカスタマイズ（UIKit） — `UIActivityItemSource` / `UIActivityItemProvider`
- S5. プレビュー（リッチリンク）表示 — `LPLinkMetadata`
- S6. 共有先の制御・除外・完了ハンドリング — `excludedActivityTypes` 他
- S7. 受け取り側（Share Extension） — `NSExtensionActivationRule` / `NSItemProvider` / `SLComposeServiceViewController`

---

## 6. API 全網羅表（サブ機能別）

### S1. 共有シートの表示（UIKit / UIActivityViewController）

| API | 目的 | 主要引数 | 返却/コールバック | エラーケース | 最小利用条件 |
| --- | --- | --- | --- | --- | --- |
| `init(activityItems:applicationActivities:)` | 共有対象と独自アクティビティを指定して初期化 | `activityItems: [Any]`, `applicationActivities: [UIActivity]?` | インスタンス | activityItems が空だと有効な共有先が出ない | iOS 6.0+ |
| `init(activityItemsConfiguration:)` | 構成オブジェクトで初期化 | `any UIActivityItemsConfigurationReading` | インスタンス | 構成が不正だと共有先が出ない | iOS 14.0+ |
| `completionWithItemsHandler` | 完了/キャンセル後のコールバック | `(activityType, completed, returnedItems, error)` | クロージャ | error 非 nil 時は失敗 | iOS 8.0+ |
| `excludedActivityTypes` | 表示しない共有先を指定 | `[UIActivity.ActivityType]?` | - | - | iOS 6.0+ |
| `allowsProminentActivity` | システムアクティビティを強調表示 | `Bool` | - | - | iOS 15.4+ |
| `popoverPresentationController` | iPad でのポップオーバー起点設定 | `sourceView` / `sourceRect` / `barButtonItem` | - | iPad で未設定だとクラッシュ | iOS 8.0+ |

iOS 18 固有 API（既存 API と分離）:

| API | 目的 | 型 | 最小利用条件 |
| --- | --- | --- | --- |
| `excludedActivitySectionTypes` | 特定セクション（例: People Suggestions）を非表示 | `UIActivitySectionTypes` | iOS 18.0+ |
| `UIActivitySectionTypes.peopleSuggestions` | 連絡先候補セクションの指定 | `UIActivitySectionTypes`（OptionSet） | iOS 18.0+ |

出典: Apple Developer Documentation および Xcode 26.3 / iPhoneOS 26.2 SDK ヘッダ（`UIActivityViewController.h` 等）で availability を確認。Apple の Web ドキュメントは JS 必須表示のため、SDK ヘッダを一次確認の補強に用いた。

注意（iPad 必須）: iPad では必ずポップオーバーとして提示する。`popoverPresentationController` の `sourceView`/`sourceRect` または `barButtonItem` を設定しないとクラッシュする。

### S2. 共有シートの表示（SwiftUI / ShareLink）

対象: iOS 16.0+。下表は init を「主要利用パターン」（単一/複数 × プレビュー有無 × ラベル形態）で整理したもの。SwiftUI SDK 上は各パターンの `titleKey` 引数がさらに `LocalizedStringKey` / `LocalizedStringResource` / `StringProtocol` / `Text` に overload されており（加えて `item` が `URL`/`String` の場合の特殊化 overload もある）、実際の init 個数は下表より多い。網羅列挙ではなく「利用パターン」として参照すること。

| API | 目的 | 主要引数 |
| --- | --- | --- |
| `init(item:subject:message:)` | 単一アイテム共有（既定ラベル） | `item: Transferable`, `subject: Text?`, `message: Text?` |
| `init(_:item:subject:message:)` | タイトル文字列付き | `titleKey`/`title`, `item`, ... |
| `init(item:subject:message:label:)` | カスタムラベル（closure） | `label: () -> Label` |
| `init(item:subject:message:preview:)` | 単一 + プレビュー | `preview: SharePreview` |
| `init(_:item:subject:message:preview:)` | タイトル + プレビュー | - |
| `init(item:subject:message:preview:label:)` | プレビュー + カスタムラベル | - |
| `init(items:subject:message:)` | 複数アイテム共有 | `items: Collection` |
| `init(_:items:subject:message:)` | 複数 + タイトル | - |
| `init(items:subject:message:label:)` | 複数 + カスタムラベル | - |
| `init(items:subject:message:preview:)` | 複数 + プレビュー | `preview: (Element) -> SharePreview` |
| `init(_:items:subject:message:preview:)` | 複数 + タイトル + プレビュー | - |
| `init(items:subject:message:preview:label:)` | 複数 + プレビュー + ラベル | - |

補足:
- `item`/`items` は `Transferable` 準拠が必須。`URL` / `String` / `Image` は標準で準拠済み。
- `URL`/`String` 以外や、ネットワーク取得を伴う型は `preview:`（`SharePreview`）を明示するとプレースホルダ待ちを回避できる。
- `SharePreview` は `SharePreview(_:image:icon:)` などで `title` / `image` / `icon` を指定する。

### S3. 共有アイテムのモデル化（Transferable / Core Transferable, iOS 16.0+）

| API | 目的 | 主要引数 | 備考 |
| --- | --- | --- | --- |
| `Transferable`（protocol） | 共有/ドラッグ&ドロップ/コピペ用のモデル化 | `static var transferRepresentation` | 唯一の必須要件は transferRepresentation |
| `CodableRepresentation(contentType:)` | Codable 型を自動で Data 変換 | `contentType: UTType` | カスタム UTType は Info.plist に宣言 |
| `DataRepresentation(contentType:exporting:importing:)` | 非同期 Data の入出力 | `contentType`, `exporting`, `importing` | ネットワーク取得等に適する |
| `FileRepresentation(contentType:exporting:importing:)` | ファイル単位の入出力 | `contentType`, `exporting: (Item) -> SentTransferredFile`, `importing: (ReceivedTransferredFile) -> Item` | ファイル共有時に使用 |
| `ProxyRepresentation(exporting:)` / `ProxyRepresentation(importing:)` / `ProxyRepresentation(exporting:importing:)` | 既存フレームワーク型へ委譲（フォールバック） | `KeyPath`/closure | 例: `ProxyRepresentation(exporting: \.title)` |
| `DataRepresentation(exportedContentType:exporting:)` | 出力専用（export のみ） | `exportedContentType`, `exporting` | 送信のみ対応する型 |
| `DataRepresentation(importedContentType:importing:)` | 入力専用（import のみ） | `importedContentType`, `importing` | 受信のみ対応する型 |
| `.suggestedFileName(_:)`（modifier, `String` 版） | 共有・保存時の既定ファイル名（固定） | `String` | iOS 16.0+ |
| `.suggestedFileName(_:)`（modifier, closure 版） | 共有・保存時の既定ファイル名（アイテム依存） | `(Item) -> String?` | iOS 17.0+ |
| `SentTransferredFile` | export でファイル URL を渡す型 | `URL`, `allowAccessingOriginalFile` | FileRepresentation の戻り値 |
| `ReceivedTransferredFile` | import で受領ファイル URL を得る型 | `file: URL`, `isOriginalFile` | 受領後はコピー必須（一時ファイル寿命に注意） |

設計指針: 精度の高い Representation を先頭に、互換性重視のものを後方に並べる。複数併記で共有先の対応幅を広げる。export/import が片方向のみの型には専用 initializer を使う。

### S4. 共有アイテムのカスタマイズ（UIKit / UIActivityItemSource, iOS 6.0+）

| API | 目的 | 必須 | 返却値 |
| --- | --- | --- | --- |
| `activityViewControllerPlaceholderItem(_:)` | 型判定用のプレースホルダ | 必須 | `Any` |
| `activityViewController(_:itemForActivityType:)` | 実際の共有データを返す | 必須 | `Any?` |
| `activityViewController(_:subjectForActivityType:)` | 件名（メール等）を返す | 任意 | `String` |
| `activityViewController(_:dataTypeIdentifierForActivityType:)` | データの UTI を返す | 任意 | `String` |
| `activityViewController(_:thumbnailImageForActivityType:suggestedSize:)` | サムネイル画像 | 任意 | `UIImage?` |
| `activityViewControllerLinkMetadata(_:)` | プレビューヘッダ用メタデータ | 任意 | `LPLinkMetadata?` |
| `activityViewControllerShareRecipients(_:)` | 宛先候補の供給（iOS 18 固有、S6 参照） | 任意（iOS 18.0+） | `[INPerson]` |

関連: `UIActivityItemProvider`（`UIActivityItemSource` 準拠の抽象クラス）はバックグラウンドスレッドで重いデータ生成を行いたい場合に継承して使う。

`UIActivityItemsConfiguration`（class 自体は iOS 13.0+）は複数アイテムやメタデータ供給を宣言的に扱う。これを `UIActivityViewController` に渡す `init(activityItemsConfiguration:)` は iOS 14.0+。主要 provider は次のとおり。

| プロパティ | 目的 |
| --- | --- |
| `init(objects:)` / `init(itemProviders:)` | 対象アイテムの指定 |
| `metadataProvider` | key（`.title`, `.linkPresentationMetadata` 等）に応じたメタデータ供給 |
| `perItemMetadataProvider` | アイテム index ごとのメタデータ供給 |
| `previewProvider` | プレビュー（`UIActivityItemsConfigurationPreviewIntent`）の供給 |
| `supportedInteractions` | 対応する `UIActivityItemsConfigurationInteraction`（share/copy 等）を制御 |
| `applicationActivitiesProvider` | 独自 `UIActivity` の供給 |
| `localObject` | 共有対象に紐づく任意のローカルオブジェクト（`Any?`） |

生成 factory と protocol メンバー（補足）:

| API | 区分 | 目的 |
| --- | --- | --- |
| `UIActivityItemsConfiguration(objects:)` | class factory（init） | オブジェクト配列から構成を生成 |
| `UIActivityItemsConfiguration(itemProviders:)` | class factory（init） | `NSItemProvider` 配列から構成を生成 |
| `UIActivityItemsConfigurationReading.itemProvidersForActivityItemsConfiguration` | protocol 必須 | 共有アイテムの `NSItemProvider` を供給 |
| `UIActivityItemsConfigurationReading.activityItemsConfigurationSupportsInteraction(_:)` 他 | protocol 任意 | interaction/metadata 等のカスタム供給 |

### S5. プレビュー（リッチリンク）表示（LinkPresentation / LPLinkMetadata, iOS 13.0+）

| API | 目的 | 主要プロパティ |
| --- | --- | --- |
| `LPLinkMetadata` | 共有シートのヘッダに表示するリンクメタデータ | `title`, `originalURL`, `url`, `iconProvider`, `imageProvider` |
| `LPMetadataProvider.startFetchingMetadata(for:)` | URL から自動でメタデータ取得 | `for url: URL` |

活用: `UIActivityItemSource.activityViewControllerLinkMetadata(_:)` から `LPLinkMetadata` を返すと、ネットワーク待ちなしで即時にリッチプレビューを表示できる。

### S6. 共有先の制御・除外・完了ハンドリング

| API | 目的 | 最小利用条件 |
| --- | --- | --- |
| `excludedActivityTypes` | `.postToFacebook`, `.copyToPasteboard` 等を非表示 | iOS 6.0+ |
| `allowsProminentActivity` | 主要アクションを強調 | iOS 15.4+ |
| `completionWithItemsHandler` | 選択された `activityType` / 成否 / error を受領 | iOS 8.0+ |
| `excludedActivitySectionTypes` | セクション単位で非表示（iOS 18 固有、S1 参照） | iOS 18.0+ |

宛先プリフィル（iOS 18 固有）:

| API | 目的 | 最小利用条件 |
| --- | --- | --- |
| `UIActivityItemSource.activityViewControllerShareRecipients(_:)` | 共有先の宛先候補（`[INPerson]`）を供給しプリフィル | iOS 18.0+ |
| `UIActivityItemsConfigurationMetadataKeyShareRecipients` | `UIActivityItemsConfiguration` 経由で宛先を供給する metadata key | iOS 18.0+ |
| `INPerson`（Intents） | 宛先を表す型 | - |

補足（SDK ヘッダで確認済みの仕様）: People suggestion がユーザーに選択された場合、その system suggestion が `activityViewControllerShareRecipients` で提供した recipients を上書きする。要検証は「共有先アプリが `INPerson` を認識できずプリフィルに失敗するケース」のみに限定する。共同編集の制限（`UIActivityItemsConfigurationMetadataKeyCollaborationModeRestrictions` / `UIActivityViewController.CollaborationModeRestriction`）は本企画書では概要のみ扱い、詳細は対象外（第 2 章参照）。

### S7. 受け取り側（Share Extension）

| API / キー | 目的 | 主要点 |
| --- | --- | --- |
| Share Extension ターゲット | 他アプリの共有シートに自アプリを表示 | Xcode の Share Extension テンプレートで生成 |
| `NSExtensionActivationRule`（Info.plist） | 受け入れるデータ型・件数を宣言 | `NSExtensionActivationSupportsImageWithMaxCount` 等。開発中の `TRUEPREDICATE` は提出前に必ず置換 |
| `NSExtensionActivationUsesStrictMatching` | 厳密マッチ | 1（YES）で厳密化 |
| `SLComposeServiceViewController` | 標準コンポーズ UI の基底クラス | `isContentValid()`, `didSelectPost()`, `configurationItems()` をオーバーライド |
| `NSExtensionItem` / `NSItemProvider` | 受け取ったコンテンツの取り出し | `extensionContext?.inputItems`, `loadItem(forTypeIdentifier:)` / `loadDataRepresentation` |
| `extensionContext?.completeRequest(returningItems:)` | 処理完了・ホストへ返却 | キャンセルは `cancelRequest(withError:)` |

---

## 7. 実装リスク（権限・制約・互換性）

### 7-1. 送信側（Export）

| リスク | 内容 | 検証方法 / fallback |
| --- | --- | --- |
| iPad クラッシュ | `UIActivityViewController` を iPad で popover 未設定提示するとクラッシュ | iPad 実機で提示確認 / `sourceView`・`sourceRect` or `barButtonItem` を必ず設定 |
| プレビュー遅延 | URL/String 以外は system プレビュー生成にネットワーク待ちが発生し得る | 実機で表示待ち計測 / `SharePreview`・`LPLinkMetadata` を明示 |
| Transferable の順序依存 | Representation の並び順で共有先の受け取り型が変わる | Mail/メモ/サードパーティで受領型を確認（要検証）/ 精度優先の順で列挙 |
| カスタム UTType | 独自型は Info.plist の UTExportedTypeDeclarations 宣言が必要 | 共有先での型認識を確認 / 型宣言を先に整備 |

### 7-2. 受信側（Share Extension）

| リスク | 内容 | 検証方法 / fallback |
| --- | --- | --- |
| メモリ制限 | Extension は本体アプリより厳しいメモリ上限（大容量画像/動画で落ちやすい） | 大容量ファイルで実機検証 / `loadFileRepresentation` によるファイル参照 + コピーで処理 |
| データ共有 | 本体アプリと Extension 間の受け渡しには App Group が必要 | 受領データが本体に届くか確認 / App Group（`group.*`）と共有コンテナ・`UserDefaults(suiteName:)` を設定 |
| 一時ファイル寿命 | `ReceivedTransferredFile` / `loadFileRepresentation` の URL は callback を抜けると無効化され得る | コピー後に再読込を確認 / callback 内で共有コンテナへコピー |
| security-scoped URL | 受領 URL がアクセス権限付きの場合、`startAccessingSecurityScopedResource()` が必要な場面がある | 読み取り失敗の有無を確認（要検証）/ 必要時にアクセス開始/終了で囲む |
| background execution | `didSelectPost` 後の非同期処理は Extension 終了で中断され得る | 完了前に `completeRequest` を呼ばない / 重い処理は本体アプリ起動後に実施 |
| ホストアプリ依存 | 提供される型・件数はホスト側の共有内容に依存 | 複数ホスト（Safari/写真/Files 等）で確認 / `hasItemConformingToTypeIdentifier` で分岐 |

### 7-3. 審査・配布

| リスク | 内容 | 検証方法 / fallback |
| --- | --- | --- |
| `TRUEPREDICATE` 残置 | Extension の Info.plist に `TRUEPREDICATE` が残ると App Store 却下 | 提出前に文字列検索 / 実 predicate・活性化キー（`NSExtensionActivationSupports...`）へ置換 |
| entitlement 不整合 | App Group entitlement が本体/Extension 双方に必要 | Capability 設定を両ターゲットで確認 |

### 7-4. 性能・互換性

| リスク | 内容 | 検証方法 / fallback |
| --- | --- | --- |
| iOS 18 の UI 変更 | 共有シートの見た目は更新されているが、記載 API 自体は互換維持（要最終確認） | iOS 18 実機で表示確認（要検証） |
| availability 境界 | `excludedActivitySectionTypes` は iOS 18.0+、`allowsProminentActivity` は iOS 15.4+ 等、下限が API ごとに異なる | `@available` / `if #available` で分岐、下位バージョンで挙動確認 |

---

## 8. 簡単なサンプルコード集（サブ機能別）

### S1. UIActivityViewController（UIKit・最小）

```swift
import UIKit
import LinkPresentation

func presentShareSheet(from vc: UIViewController, sourceView: UIView) {
    let text = "共有テキスト"
    let url = URL(string: "https://example.com")!
    let av = UIActivityViewController(activityItems: [text, url], applicationActivities: nil)
    av.excludedActivityTypes = [.assignToContact]
    av.completionWithItemsHandler = { activityType, completed, _, error in
        print("type=\(String(describing: activityType)) completed=\(completed) error=\(String(describing: error))")
    }
    // iPad 対応（未設定だとクラッシュ）
    av.popoverPresentationController?.sourceView = sourceView
    av.popoverPresentationController?.sourceRect = sourceView.bounds
    vc.present(av, animated: true)
}
```

### S2. ShareLink（SwiftUI・最小）

```swift
import SwiftUI

struct ShareDemoView: View {
    let url = URL(string: "https://example.com")!
    var body: some View {
        VStack(spacing: 16) {
            // 単一アイテム
            ShareLink(item: url)

            // 件名・メッセージ・プレビュー付き
            ShareLink(
                item: url,
                subject: Text("おすすめ記事"),
                message: Text("これ良かったです"),
                preview: SharePreview("Example サイト", image: Image(systemName: "link"))
            ) {
                Label("共有する", systemImage: "square.and.arrow.up")
            }
        }
    }
}
```

### S3. Transferable（Core Transferable・最小）

```swift
import CoreTransferable
import UniformTypeIdentifiers

struct Note: Codable {
    var title: String
    var body: String
}

extension Note: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        // 精度優先: 独自型を JSON として入出力
        CodableRepresentation(contentType: .json)
        // フォールバック: タイトル文字列（export）
        ProxyRepresentation(exporting: \.title)
    }
}

// 使用例: ShareLink(item: note, preview: SharePreview(note.title))
```

ファイル共有の例（`FileRepresentation` + ファイル名）:

```swift
import CoreTransferable
import UniformTypeIdentifiers

struct ExportedDoc { var fileURL: URL; var name: String }

extension ExportedDoc: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .pdf) { doc in
            SentTransferredFile(doc.fileURL)          // export: 既存ファイルを渡す
        } importing: { received in
            // import: 一時 URL は寿命が短いため必ずコピーしてから保持
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent(received.file.lastPathComponent)
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return ExportedDoc(fileURL: dest, name: dest.lastPathComponent)
        }
        .suggestedFileName { $0.name }
    }
}
```

### S4. UIActivityItemSource（UIKit・最小）

```swift
import UIKit
import LinkPresentation

final class ArticleItemSource: NSObject, UIActivityItemSource {
    let url: URL
    let title: String
    init(url: URL, title: String) { self.url = url; self.title = title }

    func activityViewControllerPlaceholderItem(_ c: UIActivityViewController) -> Any { url }

    func activityViewController(_ c: UIActivityViewController,
                               itemForActivityType type: UIActivity.ActivityType?) -> Any? { url }

    func activityViewController(_ c: UIActivityViewController,
                               subjectForActivityType type: UIActivity.ActivityType?) -> String { title }

    func activityViewControllerLinkMetadata(_ c: UIActivityViewController) -> LPLinkMetadata? {
        let md = LPLinkMetadata()
        md.title = title
        md.originalURL = url
        return md
    }
}
```

### S5. LPLinkMetadata（LinkPresentation・最小）

```swift
import UIKit
import LinkPresentation

func makeMetadata() -> LPLinkMetadata {
    let md = LPLinkMetadata()
    md.title = "Example サイト"
    md.originalURL = URL(string: "https://example.com")
    if let icon = UIImage(systemName: "link") {
        md.iconProvider = NSItemProvider(object: icon)
    }
    return md
}
```

### S6. 共有先の除外・完了ハンドリング（UIKit・最小）

```swift
let av = UIActivityViewController(activityItems: [url], applicationActivities: nil)
av.excludedActivityTypes = [.postToFacebook, .postToTwitter, .assignToContact]
av.allowsProminentActivity = true   // iOS 15.4+
av.completionWithItemsHandler = { type, completed, items, error in
    guard error == nil else { return }
    if completed { print("shared via \(type?.rawValue ?? "unknown")") }
}
```

### S7. Share Extension 受け取り側（最小）

Info.plist（抜粋）:

```xml
<key>NSExtension</key>
<dict>
  <key>NSExtensionAttributes</key>
  <dict>
    <key>NSExtensionActivationRule</key>
    <dict>
      <key>NSExtensionActivationSupportsWebURLWithMaxCount</key>
      <integer>1</integer>
      <key>NSExtensionActivationSupportsImageWithMaxCount</key>
      <integer>1</integer>
    </dict>
  </dict>
  <key>NSExtensionPointIdentifier</key>
  <string>com.apple.share-services</string>
  <key>NSExtensionPrincipalClass</key>
  <string>$(PRODUCT_MODULE_NAME).ShareViewController</string>
</dict>
```

ShareViewController（`SLComposeServiceViewController` 継承）:

複数の `NSExtensionItem` / 複数 attachment を全件走査し、全ロード完了後に一度だけ `completeRequest` する。各処理結果は lock 付きでメモリ配列へ集約し、App Group への保存は `group.notify` 後に一度だけ実施して read-modify-write の競合を防ぐ。全失敗時は `cancelRequest(withError:)` で本体へ伝える。

本体アプリへの受け渡しフォーマット（App Group / `UserDefaults(suiteName:)`）:

| キー | 型 | 内容 |
| --- | --- | --- |
| `sharedTexts` | `[String]` | 受領した URL/テキスト文字列の配列 |
| `sharedFiles` | `[String]` | 共有コンテナへコピー済みファイルの相対パス配列 |
| `failedCount` | `Int` | ロード/コピーに失敗した attachment 数 |

```swift
import Foundation
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {
    private let appGroup = "group.com.example.app"

    // 処理結果の集約（lock で直列化）
    private struct Results { var texts: [String] = []; var files: [String] = []; var failed = 0 }
    private var results = Results()
    private let lock = NSLock()

    override func isContentValid() -> Bool { true }

    override func didSelectPost() {
        // 全 inputItems の全 attachment を対象にする
        let providers: [NSItemProvider] = (extensionContext?.inputItems as? [NSExtensionItem])?
            .flatMap { $0.attachments ?? [] } ?? []
        guard !providers.isEmpty else { finish(succeeded: false); return }

        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            handle(provider) { group.leave() }
        }

        // 全ロード完了後に App Group へ一度だけ保存（競合回避）
        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            let ud = UserDefaults(suiteName: self.appGroup)
            ud?.set(self.results.texts, forKey: "sharedTexts")
            ud?.set(self.results.files, forKey: "sharedFiles")
            ud?.set(self.results.failed, forKey: "failedCount")
            self.finish(succeeded: !self.results.texts.isEmpty || !self.results.files.isEmpty)
        }
    }

    override func configurationItems() -> [Any]! { [] }

    // 1 attachment を型に応じて処理し、結果を集約。完了で done() を呼ぶ
    private func handle(_ provider: NSItemProvider, done: @escaping () -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, error in
                if let error { NSLog("load url failed: \(error)") }
                self?.record { r in
                    if let url = data as? URL { r.texts.append(url.absoluteString) } else { r.failed += 1 }
                }
                done()
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            // 画像はファイル参照で受けてコピー（Extension のメモリ上限対策）
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] url, error in
                if let error { NSLog("load image failed: \(error)") }
                let dest = url.flatMap { self?.copyIntoSharedContainer($0) }
                self?.record { r in
                    if let dest { r.files.append(dest.lastPathComponent) } else { r.failed += 1 }
                }
                done()
            }
        } else {
            record { $0.failed += 1 }   // 未対応型
            done()
        }
    }

    private func record(_ body: (inout Results) -> Void) {
        lock.lock(); body(&results); lock.unlock()
    }

    private func finish(succeeded: Bool) {
        if succeeded {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            let err = NSError(domain: "ShareExtension", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "共有アイテムを保存できませんでした"])
            extensionContext?.cancelRequest(withError: err)
        }
    }

    // 衝突回避のため UUID を付与。失敗時は nil を返す
    private func copyIntoSharedContainer(_ src: URL) -> URL? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup) else { return nil }
        let name = "\(UUID().uuidString)-\(src.lastPathComponent)"
        let dest = container.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: src, to: dest)
            return dest
        } catch {
            NSLog("copy failed: \(error)")
            return nil
        }
    }
}
```

---

## 9. Definition of Done

### 送信側（データ種別 × 共有先）

- [ ] `UIActivityViewController`（UIKit）と `ShareLink`（SwiftUI）双方で共有シートを表示できる
- [ ] 共有データ種別: URL / String / Image / File / カスタム `Transferable` の 5 種を共有できる
- [ ] 共有先: Mail / Messages / Files / AirDrop / コピー の各先で受領内容が正しい
- [ ] `SharePreview` / `LPLinkMetadata` によりプレビューがネットワーク待ちなしで即時表示される
- [ ] `excludedActivityTypes` で共有先を除外でき、`completionWithItemsHandler` で選択 `activityType`・成否・error を取得できる

### 端末・状態条件

- [ ] iPhone / iPad の双方で表示でき、iPad で popover 提示が設定されクラッシュしない
- [ ] キャンセル時（completed=false）と失敗時（error 非 nil）を区別してハンドリングできる

### 受信側（Share Extension）

- [ ] Extension が Safari / 写真 / Files など複数ホストの共有シートに表示される
- [ ] URL / 画像 / 複数添付を受領し、`hasItemConformingToTypeIdentifier` で型分岐できる
- [ ] 複数 attachment を全件走査し、全ロード完了後に一度だけ `completeRequest` する
- [ ] 全失敗時は `cancelRequest(withError:)` で本体へ伝わり、保存名は衝突しない（UUID 付与）
- [ ] App Group 経由で本体アプリへデータが届く（一時ファイルは共有コンテナへコピー済み）
- [ ] 本体アプリが `sharedTexts` / `sharedFiles` / `failedCount` を読み取り、成功・部分失敗・全失敗を区別できる
- [ ] Extension の Info.plist から `TRUEPREDICATE` が排除されている

### 総合

- [ ] iOS 18 実機で送受信双方の動作を確認済み（第 10 章の要検証項目を消し込み）

---

## 10. 要検証（断定を避けた項目）

- iOS 18 での共有シート UI 変更が、本企画書記載の API 互換性に影響しないこと（実機確認が必要）
- `Transferable` の Representation 並び順が各共有先（メール/メモ/サードパーティ）で意図通り解決されること
- Share Extension のメモリ上限に対する大容量ファイルの実挙動
- `ReceivedTransferredFile` / `loadFileRepresentation` の一時ファイル寿命と、コピー要否の実挙動
- security-scoped URL 受領時に `startAccessingSecurityScopedResource()` が必要となる条件
- availability 値（SDK ヘッダ由来）と Apple Web ドキュメント記載の一致（JS 表示のため Web 側は未確認）
