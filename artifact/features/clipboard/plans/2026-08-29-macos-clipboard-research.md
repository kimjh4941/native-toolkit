# macOS クリップボード機能 調査企画書

- 作成日: 2026-08-29
- 対象OS: macOS 15 以降（本リポジトリの `MACOSX_DEPLOYMENT_TARGET` は 15.0 / 15.1）
- 対象機能: クリップボード（Clipboard / Pasteboard: コピー / ペースト）
- 使用言語: Swift
- 対象フレームワーク: AppKit（`NSPasteboard` / `NSPasteboardItem` / `NSFilePromiseProvider` / `NSFilePromiseReceiver`）、UniformTypeIdentifiers（`UTType`）、DataDetection（`DDMatch*`）、SwiftUI（`PasteButton`）
- 検証環境: macOS 26.3 / Xcode 26.3 / MacOSX26.2.sdk（AppKit ヘッダ・`AppKit.swiftinterface` を一次確認に使用）
- 関連: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`（iOS 版）、`artifact/plans/clipboard/2026-07-25-android-clipboard-research.md`（Android 版）

---

## 1. 目的

macOS のネイティブクリップボード API（`NSPasteboard` 系）を全網羅し、native-toolkit（`mac/MacLibrary`）への組み込み設計に必要な情報を整理する。

対象は次のとおり。テキスト / URL / 画像 / 色 / 属性文字列 / 任意 UTI データのコピー・ペースト、複数アイテム操作、遅延データ提供（promise）、内容確認・型判定、変更監視、macOS 15 以降のペーストボードアクセスアラートと macOS 15.4 以降の検出 API（ユーザー通知なしの事前判定）、Universal Clipboard（デバイス間同期）の抑止、名前付きペーストボードの寿命とリソース解放責務。

あわせて、既存 iOS 実装（`IosClipboardManager`）との API パリティを取るために、iOS には存在するが macOS には存在しない機能（`expirationDate` 等）を明示する。

---

## 2. 調査対象範囲（in / out）

### in（対象）

- ペーストボード取得と寿命管理（`general` / `init(name:)` / `withUniqueName()` / `releaseGlobally()`）
- コピー（書き込み）: `writeObjects(_:)` / `setString` / `setData` / `setPropertyList` / 複数 `NSPasteboardItem`
- 遅延データ提供（promise）: `NSPasteboardItemDataProvider` / `NSPasteboardTypeOwner` / `NSPasteboardWritingOptions.promised`
- ペースト（読み取り）: `readObjects(forClasses:options:)` / `string(forType:)` / `data(forType:)` / `propertyList(forType:)` / `pasteboardItems`
- 内容確認・型判定（データ本体を読まない経路）: `types` / `availableType(from:)` / `canReadItem(withDataConformingToTypes:)` / `canReadObject(forClasses:options:)`
- クリア: `clearContents()` / `prepareForNewContents(with:)`
- 変更監視: `changeCount` ポーリング（macOS には変更通知が存在しない）
- 検出・プライバシー（macOS 15.4+）: `detectedPatterns(for:)` / `detectedValues(for:)` / `detectedMetadata(for:)` / `accessBehavior`
- デバイス間同期制御: `NSPasteboard.ContentsOptions.currentHostOnly`
- ユーザー起点の貼り付け経路: SwiftUI `PasteButton`、`NSResponder.paste(_:)`、`NSServicesMenuRequestor`
- ファイル約束（File Promise）: `NSFilePromiseProvider` / `NSFilePromiseProviderDelegate` / `NSFilePromiseReceiver`
- カスタム型の読み書きプロトコル: `NSPasteboardWriting` / `NSPasteboardReading`
- Filter Services（レガシー・参考）: `init(byFilteringFile:)` / `init(byFilteringData:ofType:)` / `init(byFilteringTypesIn:)` / `types(filterableTo:)`
- 廃止済みシンボル（全網羅の担保として一覧化のみ）

### out（対象外）

- iOS（`UIPasteboard`）/ Android / Windows のクリップボード API
- ドラッグ&ドロップ（`NSDraggingSession` / `NSDraggingInfo` / `registerForDraggedTypes(_:)`）。`NSPasteboard.Name.drag` および File Promise を共有するが、D&D の UI 実装そのものは本調査対象外
- Services メニューの提供側実装（`NSApplication.servicesProvider`、`NSServices` Info.plist 定義）。読み取り経路として `NSServicesMenuRequestor` のみ扱う
- 編集メニュー UI そのものの構築（`NSMenu` / `NSMenuItem` / `validateMenuItem(_:)` の一般論）
- `NSPasteboard.Name.font` / `.ruler` / `.find` を用いたフォント・ルーラ・検索文字列の連携（`NSTextView` 固有機能。API 表には存在のみ記載）
- CoreFoundation の Pasteboard Manager（`PasteboardCreate` 等の C API）
- 永続的なアプリ間データ共有（App Group / XPC）。ペーストボードは一時転送用途に限定し、責務境界のみ記載
- サードパーティ SDK

---

## 3. 公式文書一覧（最優先ソース）

| タイトル | URL |
|---|---|
| NSPasteboard（概説・全 API） | https://developer.apple.com/documentation/appkit/nspasteboard |
| NSPasteboard.Name | https://developer.apple.com/documentation/appkit/nspasteboard/name-swift.struct |
| NSPasteboard.PasteboardType | https://developer.apple.com/documentation/appkit/nspasteboard/pasteboardtype |
| NSPasteboard.general | https://developer.apple.com/documentation/appkit/nspasteboard/general |
| NSPasteboard.init(name:) | https://developer.apple.com/documentation/appkit/nspasteboard/init(name:) |
| NSPasteboard.withUniqueName() | https://developer.apple.com/documentation/appkit/nspasteboard/withuniquename() |
| NSPasteboard.releaseGlobally() | https://developer.apple.com/documentation/appkit/nspasteboard/releaseglobally() |
| NSPasteboard.changeCount | https://developer.apple.com/documentation/appkit/nspasteboard/changecount |
| NSPasteboard.clearContents() | https://developer.apple.com/documentation/appkit/nspasteboard/clearcontents() |
| NSPasteboard.prepareForNewContents(with:) | https://developer.apple.com/documentation/appkit/nspasteboard/preparefornewcontents(with:) |
| NSPasteboard.ContentsOptions | https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions |
| NSPasteboard.ContentsOptions.currentHostOnly | https://developer.apple.com/documentation/appkit/nspasteboard/contentsoptions/currenthostonly |
| NSPasteboard.writeObjects(_:) | https://developer.apple.com/documentation/appkit/nspasteboard/writeobjects(_:) |
| NSPasteboard.readObjects(forClasses:options:) | https://developer.apple.com/documentation/appkit/nspasteboard/readobjects(forclasses:options:) |
| NSPasteboard.ReadingOptionKey | https://developer.apple.com/documentation/appkit/nspasteboard/readingoptionkey |
| NSPasteboard.ReadingOptions | https://developer.apple.com/documentation/appkit/nspasteboard/readingoptions |
| NSPasteboard.WritingOptions | https://developer.apple.com/documentation/appkit/nspasteboard/writingoptions |
| NSPasteboard.accessBehavior | https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-86972 |
| NSPasteboard.AccessBehavior | https://developer.apple.com/documentation/appkit/nspasteboard/accessbehavior-swift.enum |
| NSPasteboard.detectedPatterns(for:) | https://developer.apple.com/documentation/appkit/nspasteboard/detectedpatterns(for:) |
| NSPasteboard.detectedValues(for:) | https://developer.apple.com/documentation/appkit/nspasteboard/detectedvalues(for:) |
| NSPasteboard.detectedMetadata(for:) | https://developer.apple.com/documentation/appkit/nspasteboard/detectedmetadata(for:) |
| NSPasteboard.DetectedValues | https://developer.apple.com/documentation/appkit/nspasteboard/detectedvalues-swift.struct |
| NSPasteboard.DetectedMetadata | https://developer.apple.com/documentation/appkit/nspasteboard/detectedmetadata-swift.struct |
| Pasteboard detection patterns | https://developer.apple.com/documentation/appkit/nspasteboard-detection-patterns |
| Pasteboard detection metadata types | https://developer.apple.com/documentation/appkit/nspasteboard-detection-metadata-types |
| NSPasteboardItem | https://developer.apple.com/documentation/appkit/nspasteboarditem |
| NSPasteboardItemDataProvider | https://developer.apple.com/documentation/appkit/nspasteboarditemdataprovider |
| NSPasteboardTypeOwner | https://developer.apple.com/documentation/appkit/nspasteboardtypeowner |
| NSPasteboardWriting | https://developer.apple.com/documentation/appkit/nspasteboardwriting |
| NSPasteboardReading | https://developer.apple.com/documentation/appkit/nspasteboardreading |
| NSFilePromiseProvider | https://developer.apple.com/documentation/appkit/nsfilepromiseprovider |
| NSFilePromiseProviderDelegate | https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate |
| NSFilePromiseReceiver | https://developer.apple.com/documentation/appkit/nsfilepromisereceiver |
| NSServicesMenuRequestor | https://developer.apple.com/documentation/appkit/nsservicesmenurequestor |
| SwiftUI PasteButton | https://developer.apple.com/documentation/swiftui/pastebutton |
| UniformTypeIdentifiers / UTType | https://developer.apple.com/documentation/uniformtypeidentifiers/uttype |
| DataDetection DDMatchLink（検出値の型） | https://developer.apple.com/documentation/datadetection/ddmatchlink |
| App Sandbox | https://developer.apple.com/documentation/security/app-sandbox |

### 3.1 SDK ヘッダ（一次ソース。公式文書と同格に扱う）

Xcode 26.3 / MacOSX26.2.sdk 同梱ヘッダを直接確認済み。バージョン制約・シグネチャ・注意書きの根拠はここにある。

- `AppKit.framework/Headers/NSPasteboard.h`
- `AppKit.framework/Headers/NSPasteboardItem.h`
- `AppKit.framework/Headers/NSFilePromiseProvider.h`
- `AppKit.framework/Headers/NSFilePromiseReceiver.h`
- `AppKit.framework/Headers/NSApplication.h`（`NSServicesMenuRequestor`）
- `AppKit.framework/Versions/C/Modules/AppKit.swiftmodule/arm64e-apple-macos.swiftinterface`（Swift 側の refined API）

### 3.2 公式文書・ヘッダからの主要引用（設計根拠）

- 「The default behavior for the General pasteboard is to ask upon programmatic access. All other pasteboards default to always allow access.」（`NSPasteboardAccessBehaviorDefault`、NSPasteboard.h）
- 「The system will notify the user and ask for permission before granting pasteboard access. However, access that is both user originated and paste related will always be allowed, and will not result in a notification.」（`NSPasteboardAccessBehaviorAsk`、NSPasteboard.h）
- 「This method only gives an indication of whether the first pasteboard item matches a particular pattern, and doesn't allow the app to access the item's contents. As a result, the system doesn't notify the person using the app about reading the contents of the pasteboard.」（`detectPatternsForPatterns:completionHandler:`、NSPasteboard.h）
- 「If the system finds a match when calling this method, the system informs the person using the app that the app is trying to read the contents of the pasteboard. If the person denies access to the pasteboard, the completion handler receives an error.」（`detectValuesForPatterns:completionHandler:`、NSPasteboard.h）
- 「Specifies that the pasteboard contents should not be available to other devices」（`NSPasteboardContentsCurrentHostOnly`、NSPasteboard.h）
- 「Any options specified will persist until prepareForNewContentsWithOptions: or clearContents is called.」（`prepareForNewContentsWithOptions:`、NSPasteboard.h）
- 「Because the lifetime of a unique pasteboard is not related to the lifetime of the creating app, you must release a unique pasteboard by calling `releaseGlobally()` to avoid possible leaks.」（`withUniqueName()`）
- 「Although you must call this method to release a temporary, privately named pasteboard to avoid leaks, you should never call it on a standard pasteboard.」（`releaseGlobally()`）
- 「Pasteboard items are intended to be used during a single pasteboard interaction, not held onto and used repeatedly. A pasteboard item is only valid until the owner of the pasteboard changes.」（NSPasteboardItem.h）
- 「Passing a pasteboard item that is aready associated with a pasteboard into -writeObjects: causes an exception to be raised.」（NSPasteboardItem.h。原文ママ）
- 「In general, this method should not be used with -writeObjects: since -writeObjects: will always write additional items to the pasteboard, and will not affect items already on the pasteboard.」（`declareTypes:owner:`、NSPasteboard.h）
- 「The change count subsequently increments each time the pasteboard ownership changes.」（`changeCount`）
- 「A paste button automatically validates and invalidates based on changes to the pasteboard on iOS, but not on macOS.」（SwiftUI `PasteButton`）
- 「Writing of the promised file may be cancelled or fail. When either occurs, the readerBlock is still called, but with a non-nil NSError.」（`receivePromisedFilesAtDestination:...`、NSFilePromiseReceiver.h）

---

## 4. 補助ソース一覧（必要時のみ）

公式文書とヘッダで設計根拠は充足しているため、非公式情報は採用していない。代わりに、公式文書に記載がない事項をローカル検証で確定した。検証手順は再現可能な形で以下に記す。

| 内容 | 検証方法 | 結果 | 信頼度 |
|---|---|---|---|
| `NSPasteboard` / `NSPasteboardItem` の Sendable 適合 | `swiftc -swift-version 6 -typecheck` で `Sendable` 制約に渡す | いずれも `@_nonSendable(_assumed)` により **非 Sendable**（コンパイルエラー） | high（コンパイラ出力） |
| `NSPasteboard` の MainActor 隔離 | Swift 6 の `nonisolated func` から同期 API・async 検出 API を呼ぶ | エラーなし。**MainActor 隔離ではない** | high（コンパイラ出力） |
| 検出 API の Swift シグネチャ | `AppKit.swiftinterface` を直接参照 | ObjC の completionHandler 版は `NS_REFINED_FOR_SWIFT` で隠蔽され、Swift では `async throws` のみ | high（SDK 一次情報） |
| `NSServicesMenuRequestor` 適合時の Swift 6 隔離エラー | `NSView` サブクラスで適合させて `-swift-version 6` でコンパイル | `ConformanceIsolation` エラー。`@MainActor` 適合隔離が必要 | high（コンパイラ出力） |
| 本書のサンプルコード全件 | `xcrun swiftc -swift-version 6 -typecheck -target arm64-apple-macos15.4` | 全件エラー・警告なし | high |

---

## 5. 機能マップ（サブ機能分解）

```
macOS クリップボード機能
├── P. ペーストボード取得・寿命管理
│   ├── general（システム全体・Universal Clipboard 同期対象）
│   ├── init(name:)（名前付き。ペーストボードサーバ常駐）
│   ├── withUniqueName()（一意名。releaseGlobally() 必須）
│   ├── releaseGlobally()
│   └── ＜責務境界＞永続共有は App Group / XPC（本機能の対象外）
├── C. コピー（書き込み）
│   ├── 所有権取得（clearContents / prepareForNewContents）※必須の先頭手順
│   ├── オブジェクト書き込み（writeObjects: NSString / NSURL / NSColor / NSImage / NSSound / NSAttributedString）
│   ├── 先頭アイテムへの型別書き込み（setString / setData / setPropertyList）
│   ├── 複数アイテム（NSPasteboardItem 配列）
│   └── カスタム型（NSPasteboardWriting 適合）
├── L. 遅延データ提供（promise）
│   ├── NSPasteboardItemDataProvider（推奨）
│   ├── NSPasteboardTypeOwner + declareTypes / addTypes（レガシー）
│   └── NSPasteboardWritingOptions.promised
├── H. デバイス間同期制御（Universal Clipboard）
│   └── prepareForNewContents(with: .currentHostOnly)
├── R. ペースト（読み取り）
│   ├── オブジェクト読み取り（readObjects(forClasses:options:)）
│   ├── 型別読み取り（string / data / propertyList）
│   ├── アイテム単位（pasteboardItems / index(of:) / NSPasteboardItem の各アクセサ）
│   └── カスタム型（NSPasteboardReading 適合）
├── V. 内容確認・型判定（本体を読まない）
│   ├── types / availableType(from:)
│   ├── canReadItem(withDataConformingToTypes:)
│   └── canReadObject(forClasses:options:)
├── X. クリア
│   └── clearContents()
├── M. 変更監視
│   └── changeCount ポーリング（※通知 API は存在しない）
├── D. 検出・プライバシー（macOS 15.4+）
│   ├── detectedPatterns(for:)（通知なし）
│   ├── detectedValues(for:)（通知あり・拒否時 error）
│   ├── detectedMetadata(for:)（通知なし）
│   └── accessBehavior（現在のアクセス設定の照会）
├── U. ユーザー起点の貼り付け UI（アラートを避ける経路）
│   ├── SwiftUI PasteButton
│   ├── NSResponder.paste(_:)（Edit メニュー / Cmd+V）
│   └── NSServicesMenuRequestor（readSelection(from:) / writeSelection(to:types:)）
├── F. ファイル約束（File Promise）
│   ├── NSFilePromiseProvider + NSFilePromiseProviderDelegate（提供側）
│   └── NSFilePromiseReceiver（受領側）
└── G. レガシー / 参考
    ├── Filter Services（init(byFilteringFile:) 他）
    ├── File Contents（writeFileContents / readFileContentsType / write(_:) / readFileWrapper）
    └── 廃止済み定数群（NSStringPboardType 等、macOS 10.14 で廃止）
```

---

## 6. API 全網羅表（サブ機能別）

型表記は Swift。`最小 OS` は SDK ヘッダの `API_AVAILABLE` に基づく。

### P. ペーストボード取得・寿命管理

| API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `NSPasteboard.general` | 汎用ペーストボードの取得 | なし | `NSPasteboard` | 同期 | なし | macOS 10.0 |
| `NSPasteboard(name:)` | 名前付きペーストボードの取得・生成 | `name: NSPasteboard.Name` | `NSPasteboard` | 同期 | なし | macOS 10.0 |
| `NSPasteboard.withUniqueName()` | 一意名ペーストボードの生成 | なし | `NSPasteboard` | 同期 | なし | macOS 10.0 |
| `NSPasteboard.releaseGlobally()` | ペーストボードサーバ上のリソース解放 | なし | `Void`（`oneway`） | 同期（片方向） | 標準ペーストボードに呼ぶと不正動作 | macOS 10.0 |
| `NSPasteboard.name` | ペーストボード名の照会 | なし | `NSPasteboard.Name` | 同期 | なし | macOS 10.0 |
| `NSPasteboard.Name` | 標準名の名前空間 | - | `.general` / `.font` / `.ruler` / `.find` / `.drag` | 定数 | - | macOS 10.13（旧定数は 10.13 で廃止） |

### C. コピー（書き込み）

| API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `clearContents()` | 内容消去・所有権取得 | なし | `Int`（新しい `changeCount`） | 同期 | なし | macOS 10.6 |
| `prepareForNewContents(with:)` | 内容消去 + オプション指定 | `options: NSPasteboard.ContentsOptions` | `Int` | 同期 | なし | macOS 10.12 |
| `writeObjects(_:)` | `NSPasteboardWriting` 適合物の一括書き込み | `[NSPasteboardWriting]` | `Bool` | 同期 | 追加失敗で `false` / 既に他ペーストボードに紐づく `NSPasteboardItem` を渡すと例外 | macOS 10.6 |
| `setString(_:forType:)` | 先頭アイテムへ文字列を設定 | `String`, `NSPasteboard.PasteboardType` | `Bool` | 同期 | 所有権未取得・不正 UTI で `false` | macOS 10.0 |
| `setData(_:forType:)` | 先頭アイテムへバイナリを設定 | `Data?`, `PasteboardType` | `Bool` | 同期 | 同上 | macOS 10.0 |
| `setPropertyList(_:forType:)` | 先頭アイテムへ plist を設定 | `Any`, `PasteboardType` | `Bool` | 同期 | plist 非適合で `false` | macOS 10.0 |
| `NSPasteboardItem()` | アイテム生成 | なし | `NSPasteboardItem` | 同期 | なし | macOS 10.6 |
| `NSPasteboardItem.setString/setData/setPropertyList(_:forType:)` | アイテム単位の型別設定 | 値, `PasteboardType` | `Bool` | 同期 | 不正 UTI で `false` | macOS 10.6 |
| `NSPasteboard.PasteboardType` | 標準型定数 | - | `.string` `.pdf` `.tiff` `.png` `.rtf` `.rtfd` `.html` `.tabularText` `.font` `.ruler` `.color` `.sound` `.multipleTextSelection` `.textFinderOptions` `.URL` `.fileURL` | 定数 | - | `.URL` / `.fileURL` は macOS 10.13、他は 10.6 / 10.7 |
| `NSPasteboardWriting`（プロトコル） | カスタム型の書き込み対応 | - | `writableTypes(forPasteboard:)` / `writingOptions(forType:pasteboard:)` / `pasteboardPropertyList(forType:)` | 同期（実装側） | - | macOS 10.6 |
| `NSPasteboard.WritingOptions` | 書き込み方式指定 | - | `.promised` | 定数 | - | macOS 10.6 |

標準で `NSPasteboardWriting` / `NSPasteboardReading` の双方に適合する Cocoa クラス: `NSString` / `NSAttributedString` / `NSURL` / `NSColor` / `NSSound` / `NSImage` / `NSPasteboardItem`（NSPasteboard.h の記載による）。

### L. 遅延データ提供（promise）

| API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `NSPasteboardItem.setDataProvider(_:forTypes:)` | 型を約束し提供者を登録 | `NSPasteboardItemDataProvider`, `[PasteboardType]` | `Bool` | 同期（登録） | 不正 UTI で `false` | macOS 10.6 |
| `NSPasteboardItemDataProvider.pasteboard(_:item:provideDataForType:)` | 要求時にデータを供給 | `NSPasteboard?`, `NSPasteboardItem`, `PasteboardType` | `Void`（要求駆動コールバック） | callback（同期呼び出し） | 供給しない場合は読み手が nil を受け取る | macOS 10.6。Swift では `nonisolated` |
| `NSPasteboardItemDataProvider.pasteboardFinishedWithDataProvider(_:)` | 提供者が不要になった通知 | `NSPasteboard` | `Void` | callback | - | macOS 10.6（optional） |
| `declareTypes(_:owner:)` | 先頭アイテムの型宣言（レガシー） | `[PasteboardType]`, `Any?` | `Int` | 同期 | `writeObjects(_:)` との併用は非推奨 | macOS 10.0 |
| `addTypes(_:owner:)` | 先頭アイテムへ型を追加 | `[PasteboardType]`, `Any?` | `Int` | 同期 | 所有権未取得で無効 | macOS 10.0 |
| `NSPasteboardTypeOwner.pasteboard(_:provideDataForType:)` | 要求時にデータを供給（レガシー） | `NSPasteboard`, `PasteboardType` | `Void` | callback | - | macOS 11.0 でプロトコル化（旧 informal protocol は 10.0–11.0 で廃止） |
| `NSPasteboardTypeOwner.pasteboardChangedOwner(_:)` | 所有権喪失の通知 | `NSPasteboard` | `Void` | callback | - | macOS 11.0（optional） |

### H. デバイス間同期制御（Universal Clipboard）

| API 名 | 目的 | 主要引数 | 返却値 | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `NSPasteboard.ContentsOptions.currentHostOnly` | 他デバイスへ内容を渡さない | - | - | 定数 | `clearContents()` を後から呼ぶと解除される | macOS 10.12 |
| `prepareForNewContents(with: .currentHostOnly)` | 上記オプション付きで所有権取得 | `ContentsOptions` | `Int` | 同期 | 同上 | macOS 10.12 |

iOS の `UIPasteboard.OptionsKey.localOnly` に相当する。**iOS の `expirationDate` に相当する API は macOS に存在しない。**

### R. ペースト（読み取り）

| API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `readObjects(forClasses:options:)` | 指定クラスのオブジェクトを一括読み取り | `[AnyClass]`, `[ReadingOptionKey: Any]?` | `[Any]?` | 同期 | 取得失敗・生成不可で `nil` | macOS 10.6 |
| `NSPasteboard.ReadingOptionKey.urlReadingFileURLsOnly` | ファイル URL のみに限定 | `NSNumber(Bool)` | - | 定数 | - | macOS 10.6 |
| `NSPasteboard.ReadingOptionKey.urlReadingContentsConformToTypes` | URL の内容 UTI で絞り込み | `[String]` | - | 定数 | 内容型が判定不能なら不一致扱い | macOS 10.6 |
| `string(forType:)` | 全アイテムの最良表現を文字列で取得 | `PasteboardType` | `String?` | 同期 | 該当なしで `nil` | macOS 10.0 |
| `data(forType:)` | 同上（バイナリ） | `PasteboardType` | `Data?` | 同期 | 同上 | macOS 10.0 |
| `propertyList(forType:)` | 同上（plist） | `PasteboardType` | `Any?` | 同期 | 同上 | macOS 10.0 |
| `pasteboardItems` | 全アイテムの取得 | なし | `[NSPasteboardItem]?` | 同期 | 取得失敗で `nil` | macOS 10.6 |
| `index(of:)` | アイテムのインデックス取得 | `NSPasteboardItem` | `Int`（未所属は `NSNotFound`） | 同期 | - | macOS 10.6 |
| `NSPasteboardItem.string/data/propertyList(forType:)` | アイテム単位の型別取得 | `PasteboardType` | 値 or `nil` | 同期 | 所有者変更後は `nil` | macOS 10.6 |
| `NSPasteboardReading`（プロトコル） | カスタム型の読み取り対応 | - | `readableTypes(forPasteboard:)` / `readingOptions(forType:pasteboard:)` / `init?(pasteboardPropertyList:ofType:)` | 同期（実装側） | - | macOS 10.6 |
| `NSPasteboard.ReadingOptions` | 読み取り前処理の指定 | - | `.asData` / `.asString` / `.asPropertyList` / `.asKeyedArchive` | 定数 | 複数指定は不可（1 つのみ） | macOS 10.6 |

`string(forType:)` / `data(forType:)` は「全アイテムの最良表現」を返す。テキスト系（string / RTF / RTFD）では複数アイテムのテキストが改行連結されて 1 つの結果になる（NSPasteboard.h 記載）。アイテム単位の厳密な取得が必要なら `pasteboardItems` を使う。

### V. 内容確認・型判定（データ本体を読まない）

| API 名 | 目的 | 主要引数 | 返却値 | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `types` | ペーストボード全体の型一覧 | なし | `[PasteboardType]?` | 同期 | 取得失敗で `nil` | macOS 10.0 |
| `availableType(from:)` | 指定候補のうち最初に合致する型 | `[PasteboardType]` | `PasteboardType?` | 同期 | 該当なしで `nil` | macOS 10.0 |
| `canReadItem(withDataConformingToTypes:)` | 指定 UTI に適合するアイテムの有無 | `[String]` | `Bool` | 同期 | - | macOS 10.6 |
| `canReadObject(forClasses:options:)` | 指定クラスを生成可能かの判定 | `[AnyClass]`, `[ReadingOptionKey: Any]?` | `Bool` | 同期 | - | macOS 10.6 |
| `NSPasteboardItem.types` | アイテムの型一覧 | なし | `[PasteboardType]` | 同期 | - | macOS 10.6 |
| `NSPasteboardItem.availableType(from:)` | アイテム内の合致型 | `[PasteboardType]` | `PasteboardType?` | 同期 | 該当なしで `nil` | macOS 10.6 |
| `NSPasteboard.types(filterableTo:)` | 指定型へ変換可能な型一覧（Filter Services） | `PasteboardType` | `[PasteboardType]` | 同期 | - | macOS 10.0 |

これらが「アクセスアラートを発生させない」ことは公式文書に明記がない。**要検証（V-1）**。ただしデータ本体を返さない点で `detectedPatterns` と同性質であり、通知経路としては安全側と推定される。

### X. クリア

| API 名 | 目的 | 主要引数 | 返却値 | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `clearContents()` | 内容の消去 | なし | `Int` | 同期 | なし。`prepareForNewContents(with:)` で設定した `currentHostOnly` を解除する | macOS 10.6 |

### D. 検出・プライバシー（macOS 15.4+）

Swift では ObjC の completionHandler 版が `NS_REFINED_FOR_SWIFT` により隠蔽され、`async throws` 版のみが公開される（`AppKit.swiftinterface` で確認済み）。

| API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `detectedPatterns(for:)` | 先頭アイテムのパターン一致判定（**通知なし**） | `Set<PartialKeyPath<DetectedValues>>` | `Set<PartialKeyPath<DetectedValues>>` | async throws | 検出失敗時に throw | macOS 15.4 |
| `detectedValues(for:)` | 一致時に内容も取得（**通知あり**） | 同上 | `NSPasteboard.DetectedValues` | async throws | ユーザー拒否時に throw | macOS 15.4 |
| `detectedMetadata(for:)` | メタデータのみ取得（**通知なし**） | `Set<PartialKeyPath<DetectedMetadata>>` | `NSPasteboard.DetectedMetadata` | async throws | 検出失敗時に throw | macOS 15.4 |
| `NSPasteboardItem.detectedPatterns/detectedValues/detectedMetadata(for:)` | アイテム単位の同等 API | 同上 | 同上 | async throws | 同上 | macOS 15.4 |
| `accessBehavior` | 現在のアクセス設定の照会 | なし | `NSPasteboard.AccessBehavior` | 同期 | - | macOS 15.4 |
| `NSPasteboard.AccessBehavior` | アクセス設定の列挙 | - | `.default` / `.ask` / `.alwaysAllow` / `.alwaysDeny` | 定数 | - | macOS 15.4 |
| `NSPasteboard.DetectedValues` | 検出値のコンテナ | - | `patterns` / `probableWebURL: String` / `probableWebSearch: String` / `number: Double?` / `links: [DDMatchLink]` / `phoneNumbers` / `emailAddresses` / `postalAddresses` / `calendarEvents` / `shipmentTrackingNumbers` / `flightNumbers` / `moneyAmounts` | 構造体 | - | macOS 15.4（`DDMatch*` は macOS 12.0） |
| `NSPasteboard.DetectedMetadata` | 検出メタデータのコンテナ | - | `metadataTypes` / `contentType: UTType?` | 構造体 | - | macOS 15.4 |

ObjC 側の対応シンボル（Swift からは不可視。全網羅の担保として記載）: `detectPatternsForPatterns:completionHandler:` / `detectValuesForPatterns:completionHandler:` / `detectMetadataForTypes:completionHandler:` / `NSPasteboardDetectionPattern*`（11 定数）/ `NSPasteboardMetadataTypeContentType`。

`.default` の意味（NSPasteboard.h 記載）: アクセスアラートを一度も発生させていないアプリは `.default` を返し、System Settings のペーストボード欄に現れない。最初のアラート発生時に `.ask` へ自動遷移し、以後ユーザーが `.ask` / `.alwaysAllow` / `.alwaysDeny` を切り替えられる。

### M. 変更監視

| API 名 | 目的 | 主要引数 | 返却値 | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `changeCount` | 所有権変更回数の取得 | なし | `Int` | 同期 | - | macOS 10.0 |

**macOS には `UIPasteboard.changedNotification` に相当する通知 API が存在しない**（AppKit ヘッダ全文検索で該当なし）。`changeCount` のポーリングが唯一の公式手段。`changeCount` の読み取りは内容を読まないためアラート対象外と推定されるが **要検証（V-1）**。

### U. ユーザー起点の貼り付け UI

| API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| SwiftUI `PasteButton(payloadType:onPaste:)` | システム提供の貼り付けボタン | `T.Type where T: Transferable`, `([T]) -> Void` | `View` / クロージャ呼び出し | callback（MainActor） | 型不一致時は呼ばれない | macOS 10.15 |
| SwiftUI `PasteButton(supportedContentTypes:payloadAction:)` | UTType 指定版 | `[UTType]`, `([NSItemProvider]) -> Void` | `View` | callback | - | macOS 11.0 |
| `NSResponder.paste(_:)` | Edit メニュー / Cmd+V の受け口 | `Any?` | `Void` | callback（MainActor） | - | macOS 10.0（`NSText` 系。自前 View では `@objc func paste(_:)` を実装） |
| `NSServicesMenuRequestor.readSelection(from:)` | Services / 貼り付けからの読み取り | `NSPasteboard` | `Bool` | callback | 受理不可で `false` | macOS 10.0 |
| `NSServicesMenuRequestor.writeSelection(to:types:)` | Services への書き出し | `NSPasteboard`, `[PasteboardType]` | `Bool` | callback | 提供不可で `false` | macOS 10.0 |

`PasteButton` は macOS では iOS と異なり **ペーストボード変更に応じた自動 validate / invalidate を行わない**（公式文書に明記）。これらの経路が「user originated かつ paste related」としてアラート免除に該当するかは **要検証（V-2）**。

### F. ファイル約束（File Promise）

| API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|
| `NSFilePromiseProvider(fileType:delegate:)` | 約束提供者の生成 | `String`(UTI), `NSFilePromiseProviderDelegate` | `NSFilePromiseProvider` | 同期 | `fileType` が `data`/`directory` に非適合なら例外 | macOS 10.12 |
| `NSFilePromiseProvider.fileType` / `.delegate` / `.userInfo` | 設定の参照・変更 | - | 各値 | 同期 | 同上 | macOS 10.12 |
| `NSFilePromiseProviderDelegate.filePromiseProvider(_:fileNameForType:)` | ファイル名の決定 | provider, `String` | `String` | callback（MainActor） | - | macOS 10.12。Swift では `NS_SWIFT_UI_ACTOR` |
| `NSFilePromiseProviderDelegate.filePromiseProvider(_:writePromiseTo:completionHandler:)` | 実データの書き出し | provider, `URL`, `(Error?) -> Void` | `Void` | callback → completion | 書き出し失敗を `completionHandler` に渡す | macOS 10.12。`nonisolated`。`operationQueue(for:)` のキューで呼ばれる |
| `NSFilePromiseProviderDelegate.operationQueue(for:)` | 書き出しキューの指定 | provider | `OperationQueue` | callback（MainActor） | 未実装時は `OperationQueue.main` | macOS 10.12（optional） |
| `NSFilePromiseReceiver.readableDraggedTypes` | 受領可能な型一覧 | なし | `[String]` | 同期 | - | macOS 10.12 |
| `NSFilePromiseReceiver.fileTypes` / `.fileNames` | 約束されたファイルの情報 | なし | `[String]` | 同期 | `fileNames` は `receivePromisedFiles` 前は空配列 | macOS 10.12 |
| `NSFilePromiseReceiver.receivePromisedFiles(atDestination:options:operationQueue:reader:)` | 約束の実行と受領 | `URL`, `[AnyHashable: Any]`, `OperationQueue`, `(URL, Error?) -> Void` | `Void` | callback（指定キュー） | 失敗・キャンセル時も reader が呼ばれ `error` が非 nil | macOS 10.12 |

### G. レガシー / 参考（全網羅の担保）

| API 名 | 目的 | 状態 |
|---|---|---|
| `NSPasteboard(byFilteringFile:)` / `(byFilteringData:ofType:)` / `(byFilteringTypesIn:)` | Filter Services による型変換 | 現行 SDK で非推奨マークなし。ただし Filter Services 自体がレガシー機構。新規採用しない |
| `writeFileContents(_:)` / `readFileContentsType(_:toFile:)` | ファイル内容の直接受け渡し | UTI + `.fileURL` で代替可能。ヘッダに「now replaces this functionality」の記載 |
| `write(_:)`（`writeFileWrapper:`）/ `readFileWrapper()` | `NSFileWrapper` の受け渡し | 同上 |
| `NSFileContentsPboardType` / `NSCreateFilenamePboardType` / `NSCreateFileContentsPboardType` / `NSGetFileType` / `NSGetFileTypes` | 旧ファイル型ヘルパ | レガシー。採用しない |
| `NSPasteboard.Name.font` / `.ruler` / `.find` | フォント・ルーラ・検索文字列の連携 | 本機能の対象外（`NSTextView` 固有） |
| 廃止済み型定数（macOS 10.14 で廃止） | `NSStringPboardType` / `NSFilenamesPboardType` / `NSTIFFPboardType` / `NSRTFPboardType` / `NSRTFDPboardType` / `NSHTMLPboardType` / `NSTabularTextPboardType` / `NSFontPboardType` / `NSRulerPboardType` / `NSColorPboardType` / `NSURLPboardType` / `NSPDFPboardType` / `NSMultipleTextSelectionPboardType` / `NSPostScriptPboardType` / `NSVCardPboardType` / `NSInkTextPboardType` / `NSFilesPromisePboardType` / `NSPasteboardTypeFindPanelSearchOptions` | すべて `NSPasteboardType*` へ置換。**採用禁止** |
| 廃止済み名前定数（macOS 10.13 で廃止） | `NSGeneralPboard` / `NSFontPboard` / `NSRulerPboard` / `NSFindPboard` / `NSDragPboard` | `NSPasteboard.Name.*` へ置換。**採用禁止** |
| `NSPICTPboardType` | PICT 画像型 | macOS 10.6 で廃止。**採用禁止** |
| `NSObject(NSPasteboardOwner)` の `pasteboard(_:provideDataForType:)` / `pasteboardChangedOwner(_:)` | informal protocol 版 | macOS 11.0 で廃止。`NSPasteboardTypeOwner` を使う |

---

## 7. 同期・非同期 API 分類表（全サブ機能）

| サブ機能 / 操作 | システム API | 実行方式 | 完了方式 | 完了スレッド・actor | キャンセル手段 | リソース所有権・寿命 |
|---|---|---|---|---|---|---|
| P: 汎用取得 | `NSPasteboard.general` | 同期 | 戻り値 | 呼び出しスレッド（MainActor 隔離なし。検証済み） | なし | シングルトン。解放不可 |
| P: 名前付き取得 | `NSPasteboard(name:)` | 同期 | 戻り値 | 同上 | なし | ペーストボードサーバに常駐。アプリ終了で消えない |
| P: 一意名生成 | `NSPasteboard.withUniqueName()` | 同期 | 戻り値 | 同上 | なし | アプリ寿命と無関係。`releaseGlobally()` 必須 |
| P: 解放 | `releaseGlobally()` | 同期（`oneway`） | なし | 同上 | なし | 以後どのアプリからも使用不可 |
| C: 所有権取得 | `clearContents()` / `prepareForNewContents(with:)` | 同期 | 戻り値（`changeCount`） | 同上 | なし | 呼び出し側が所有者になる |
| C: オブジェクト書き込み | `writeObjects(_:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 書き込んだ `NSPasteboardItem` は当該ペーストボードに束縛される |
| C: 型別書き込み | `setString` / `setData` / `setPropertyList(_:forType:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 先頭アイテムのみ対象 |
| C: アイテム構築 | `NSPasteboardItem` 各 setter | 同期 | 戻り値（`Bool`） | 同上 | なし | 所有者変更まで有効。再利用不可 |
| L: 遅延提供の登録 | `setDataProvider(_:forTypes:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | provider は強参照で保持する必要あり（**要検証 V-3**） |
| L: 遅延提供の実行 | `pasteboard(_:item:provideDataForType:)` | callback（要求駆動） | delegate 呼び出し | 呼び出し元スレッド不定（**要検証 V-4**）。Swift では `nonisolated` | なし | `pasteboardFinishedWithDataProvider(_:)` で終了 |
| L: 遅延提供（レガシー） | `declareTypes(_:owner:)` + `NSPasteboardTypeOwner` | 同期登録 / callback 実行 | delegate 呼び出し | 同上 | なし | `pasteboardChangedOwner(_:)` で所有権喪失 |
| H: 同期抑止 | `prepareForNewContents(with: .currentHostOnly)` | 同期 | 戻り値 | 同上 | なし | 次の `clearContents()` / `prepareForNewContents` まで有効 |
| R: オブジェクト読み取り | `readObjects(forClasses:options:)` | 同期 | 戻り値（`[Any]?`） | 同上 | なし | 返却オブジェクトは呼び出し側所有 |
| R: 型別読み取り | `string` / `data` / `propertyList(forType:)` | 同期 | 戻り値 | 同上 | なし | 同上 |
| R: アイテム取得 | `pasteboardItems` / `index(of:)` | 同期 | 戻り値 | 同上 | なし | 所有者変更で無効化（以後 nil / NO を返す） |
| V: 型一覧 | `types` / `availableType(from:)` | 同期 | 戻り値 | 同上 | なし | - |
| V: 適合判定 | `canReadItem(withDataConformingToTypes:)` / `canReadObject(forClasses:options:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | - |
| V: 変換可能型 | `NSPasteboard.types(filterableTo:)` | 同期 | 戻り値 | 同上 | なし | - |
| X: クリア | `clearContents()` | 同期 | 戻り値 | 同上 | なし | `currentHostOnly` を解除する |
| M: 変更監視 | `changeCount`（ポーリング） | 同期 | 戻り値 | 呼び出しスレッド。`Timer` 併用時は MainActor 推奨 | タイマ停止（`invalidate()`） | 通知 API なし |
| D: パターン判定 | `detectedPatterns(for:)` | **async throws** | Swift Concurrency（`await`） | 呼び出し元のアクター文脈で再開（`nonisolated async`。MainActor から呼べば MainActor に戻る） | Task キャンセル対応は **要検証（V-5）** | 戻り値は値型 `Set` |
| D: 値取得 | `detectedValues(for:)` | **async throws** | 同上 | 同上 | 同上 | 戻り値は値型 `DetectedValues` |
| D: メタデータ取得 | `detectedMetadata(for:)` | **async throws** | 同上 | 同上 | 同上 | 戻り値は値型 `DetectedMetadata` |
| D: アイテム単位の検出 | `NSPasteboardItem.detected*(for:)` | **async throws** | 同上 | 同上 | 同上 | アイテムは非 Sendable。同一隔離内で扱う |
| D: 設定照会 | `accessBehavior` | 同期 | 戻り値 | 呼び出しスレッド | なし | - |
| D: ObjC 版検出（参考） | `detectPatternsForPatterns:completionHandler:` 他 | callback | completion block | **要検証（V-4）**。公式文書に記載なし | なし | Swift からは不可視 |
| U: 貼り付けボタン | SwiftUI `PasteButton` | callback | クロージャ | MainActor | View の破棄 | - |
| U: メニュー貼り付け | `NSResponder.paste(_:)` | callback | メソッド呼び出し | MainActor | なし | - |
| U: Services 読み書き | `readSelection(from:)` / `writeSelection(to:types:)` | callback | 戻り値（`Bool`） | 実質 MainActor（プロトコル要件は `nonisolated`。**Swift 6 では適合隔離が必要**） | なし | - |
| F: 約束の書き出し | `filePromiseProvider(_:writePromiseTo:completionHandler:)` | callback → completion | completion block | `operationQueue(for:)` が返す `OperationQueue`（未実装時は `.main`） | なし（失敗を error で返す） | 書き出し先 URL はシステム指定。必ず引数の URL を使う |
| F: 約束の受領 | `receivePromisedFiles(atDestination:options:operationQueue:reader:)` | callback | reader block | 引数の `OperationQueue` | なし（キャンセル時も reader が error 付きで呼ばれる） | 受領先ディレクトリは呼び出し側所有 |
| G: Filter Services | `NSPasteboard(byFilteringFile:)` 他 | 同期 | 戻り値 | 呼び出しスレッド | なし | 生成されたペーストボードの解放責務は不明瞭。新規採用しない |

**非同期 API は macOS 15.4+ の検出 API 3 種（および `NSPasteboardItem` の同名 3 種）のみ。** それ以外の `NSPasteboard` API はすべて同期であり、ペーストボードサーバへの同期 IPC としてブロックする。

---

## 8. 実装リスク（権限・制約・互換性）

| ID | 種別 | 内容 | 影響 | 対応方針 |
|---|---|---|---|---|
| RK-01 | 互換性 | `mac/MacLibrary` の `MACOSX_DEPLOYMENT_TARGET` は 15.0 / 15.1 だが、検出 API と `accessBehavior` は **macOS 15.4+** | 15.0–15.3 では検出経路が使えない。無条件呼び出しはリンク時／実行時エラー | `if #available(macOS 15.4, *)` で分岐し、未満では `canReadItem(withDataConformingToTypes:)` による型判定にフォールバック。公開 API では「検出未対応」を表す結果を返す |
| RK-02 | プライバシー | macOS 15（Sequoia）以降、プログラムからの汎用ペーストボード読み取りはユーザーへのアラート対象。ただし設定を照会する `accessBehavior` は 15.4+ | 15.0–15.3 では自アプリの許可状態を判定できない | 読み取り前に必ず `detectedPatterns` / `canReadItem` で事前判定し、実読み取りを最小化。15.4 未満は「状態不明」として扱う |
| RK-03 | プライバシー | `detectedValues(for:)` は一致時に**ユーザー通知が発生し、拒否されると throw する**（ヘッダに明記） | 「通知なしの内容取得」はできない | 通知を避ける用途では `detectedPatterns` / `detectedMetadata` のみを使う。`detectedValues` はユーザー操作起点でのみ呼ぶ |
| RK-04 | 機能欠落 | iOS の `UIPasteboard.OptionsKey.expirationDate` に相当する API が macOS に**存在しない** | クリップボード内容の自動失効ができない。iOS と API パリティが取れない | 公開 API で `expirationDate` 相当を受け付けない、または「macOS では無視される」ことを DocC に明記。自前タイマで `clearContents()` する代替は所有権を他アプリに奪われた後に誤消去する危険があるため、`changeCount` 一致時のみ消去する |
| RK-05 | 仕様差異 | `clearContents()` は `prepareForNewContents(with: .currentHostOnly)` で設定したオプションを**解除する**（ヘッダに明記） | 「ローカル限定でコピー」を意図した実装が Universal Clipboard に流出する | ローカル限定コピーでは `clearContents()` を呼ばず、必ず `prepareForNewContents(with: .currentHostOnly)` を先頭手順にする。Repository 層で所有権取得を 1 経路に集約する |
| RK-06 | 寿命 | 名前付き / 一意名ペーストボードは**アプリ終了後もペーストボードサーバに残る**（`withUniqueName()` の公式文書「lifetime ... is not related to the lifetime of the creating app」） | 機密データが終了後も他アプリから読める。iOS 版で検出済みの M-08 と同種の露出が macOS では**仕様として発生する** | 一意名ペーストボードは使用後に必ず `releaseGlobally()` を呼ぶ（`defer` で保証）。機密データは名前付きペーストボードに置かない。DocC の契約文で「終了後も残存しうる」ことを明記する。関連: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md` |
| RK-07 | 寿命 | `releaseGlobally()` を標準ペーストボード（`general` 等）に呼ぶと「no other application can use the receiver」となる | システム全体のクリップボードを破壊しうる | Repository 層で `general` および標準名に対する `releaseGlobally()` を**呼べない構造**にする（一意名生成経路のみが解放責務を持つ） |
| RK-08 | 並行性 | `NSPasteboard` / `NSPasteboardItem` は **非 Sendable**（`@_nonSendable(_assumed)`。コンパイラで確認済み）。ただし MainActor 隔離でもない | Swift 6 でアクター境界を越えて渡すとコンパイルエラー。誤って `nonisolated(unsafe)` で回避するとデータ競合 | ペーストボードインスタンスを保持して受け渡さず、使用箇所ごとに `NSPasteboard.general` を取得する。Repository を `@MainActor` に固定するか、専用のシリアル実行文脈に閉じる |
| RK-09 | 並行性 | `NSServicesMenuRequestor` の要件は `nonisolated`。`NSView`（MainActor）で適合すると Swift 6 で `ConformanceIsolation` エラー（実測） | ビルド不能 | 適合を `@MainActor` で隔離する（`final class V: NSView, @MainActor NSServicesMenuRequestor`）。または要件実装を `nonisolated` にする |
| RK-10 | 並行性 | `changeCount` ポーリングに `Timer` を使うと、Swift 6 でクロージャが `@Sendable` 扱いになり非 Sendable な self を捕捉できない（実測） | ビルド不能 | 監視クラスを `@MainActor` にし、`MainActor.assumeIsolated { }` で本体を包む。コールバックも `@MainActor` クロージャとして受け取る |
| RK-11 | 監視 | macOS には `UIPasteboard.changedNotification` に相当する通知が**存在しない**（ヘッダ全文検索で該当なし） | 変更検知は必ずポーリングになる。間隔を詰めると電力・CPU コスト、空けると取りこぼし | 既定 0.5 秒程度のポーリングとし、間隔を設定可能にする。アプリ非アクティブ時は停止し、`applicationDidBecomeActive` で 1 回だけ照合する（iOS 版 `checkForegroundChange` に相当） |
| RK-12 | サンドボックス | `MacLibraryExample` は App Sandbox 有効（`com.apple.security.app-sandbox`）。ペーストボードから取得した `fileURL` に対しサンドボックス例外が自動付与されるかは公式文書に記載がない | ファイル URL をペーストしても読み込めない可能性 | **要検証（V-6）**。読み込み失敗を握り潰さず明示エラーとして返す。必要なら `com.apple.security.files.user-selected.read-only` の範囲で扱う |
| RK-13 | API 誤用 | `writeObjects(_:)` は既存アイテムを消さず**追加**する。`declareTypes(_:owner:)` との併用はヘッダで非推奨とされる | 意図しないアイテム重複、所有権の取り違え | コピー処理を「所有権取得 → `writeObjects` のみ」に固定し、`declareTypes` 経路は遅延提供のレガシー用途以外で使わない |
| RK-14 | API 誤用 | 既にペーストボードに束縛済みの `NSPasteboardItem` を再度 `writeObjects(_:)` に渡すと**例外が送出される**（ヘッダに明記） | クラッシュ | `NSPasteboardItem` を再利用せず、書き込みのたびに生成する。読み取りで得たアイテムを書き込みに回さない |
| RK-15 | 読み取り仕様 | `string(forType:)` / `data(forType:)` は「全アイテムの最良表現」であり、テキスト系では複数アイテムが改行連結される | 複数アイテムのコピー内容を 1 件と誤認する | 件数が意味を持つ経路では `pasteboardItems` を使い、`string(forType:)` は単一値取得の簡易経路に限定する |
| RK-16 | UI | SwiftUI `PasteButton` は macOS ではペーストボード変更に応じた自動 validate / invalidate を行わない（公式文書に明記） | ボタンが常時有効に見え、押下しても何も起きないことがある | 有効／無効の表示制御を自前で行う場合は `canReadObject(forClasses:options:)` を用い、ポーリング（RK-11）と連動させる |
| RK-17 | 遅延提供 | `NSPasteboardItem` は「所有者が変わるまでのみ有効」。遅延提供の data provider は要求されるまで呼ばれない | provider が先に解放されるとデータが供給されない | provider をリポジトリ層で強参照し、`pasteboardFinishedWithDataProvider(_:)` で解放する。参照保持の必要性自体は **要検証（V-3）** |
| RK-18 | 型指定 | `NSPasteboardItem` は「有効な UTI 文字列」のみ受け付け、非 UTI を渡すと呼び出しが失敗する（ヘッダに明記） | サイレントな `false` 返却 | カスタム型は `UTType(exportedAs:)` で宣言し、Info.plist に `UTExportedTypeDeclarations` を追加する。UTI 検証を Data 層に置く（iOS 版 `ClipboardTypeIdentifierValidator` に相当） |
| RK-19 | レガシー | macOS 10.13 / 10.14 で廃止された定数群（`NSStringPboardType`、`NSGeneralPboard` 等）が SDK に残存 | 補完候補から誤って選択されうる | Lint / レビュー観点として「`NSPasteboardType*` / `NSPasteboard.Name.*` のみ使用」を明文化する |
| RK-20 | 性能 | すべての `NSPasteboard` 同期 API はペーストボードサーバへの IPC。大きな画像・ファイルデータで顕著にブロックする | MainActor で実行するとフリーズ | 大容量データの読み書きは遅延提供（`NSPasteboardItemDataProvider`）または File Promise に寄せる。同期 API を MainActor 外で呼ぶ場合は RK-08 の隔離方針に従う |

---

## 9. 簡単なサンプルコード集（サブ機能別）

すべて `xcrun swiftc -swift-version 6 -typecheck -target arm64-apple-macos15.4` で検証済み（エラー・警告なし）。

### P. ペーストボード取得・寿命管理

```swift
import AppKit

func acquirePasteboards() {
    let general = NSPasteboard.general
    _ = general.name                                   // .general

    // 名前付き: ペーストボードサーバに常駐し、アプリ終了後も残る
    let named = NSPasteboard(name: .init("com.example.toolkit.private"))
    _ = named.name

    // 一意名: 寿命がアプリと無関係なため releaseGlobally() が必須
    let unique = NSPasteboard.withUniqueName()
    defer { unique.releaseGlobally() }
    _ = unique.changeCount
}
```

### C. コピー — 標準オブジェクト

```swift
import AppKit

func copyStandardObjects() {
    let pb = NSPasteboard.general
    pb.clearContents()                                  // 所有権取得（必須の先頭手順）
    let ok = pb.writeObjects([
        "hello" as NSString,
        NSURL(string: "https://example.com")!,
        NSColor.systemBlue,
        NSAttributedString(string: "rich"),
    ])
    _ = ok                                              // 追加失敗時は false
}
```

### C. コピー — 任意 UTI / 型別書き込み

```swift
import AppKit
import UniformTypeIdentifiers

func copyTypedData(image: NSImage, json: Data) {
    let pb = NSPasteboard.general
    pb.clearContents()
    _ = pb.setString("hello", forType: .string)
    _ = pb.setData(image.tiffRepresentation, forType: .tiff)
    _ = pb.setPropertyList(["k": "v"], forType: .init(UTType.propertyList.identifier))
    _ = pb.setData(json, forType: .init("com.example.toolkit.payload"))
}
```

### C. コピー — 複数アイテム

```swift
import AppKit

func copyMultipleItems() {
    let pb = NSPasteboard.general
    pb.clearContents()
    var items: [NSPasteboardItem] = []
    for (i, s) in ["a", "b"].enumerated() {
        let item = NSPasteboardItem()                   // 再利用禁止。毎回生成する
        item.setString(s, forType: .string)
        item.setString("\(i)", forType: .init("com.example.toolkit.index"))
        items.append(item)
    }
    _ = pb.writeObjects(items)
}
```

### L. 遅延データ提供（NSPasteboardItemDataProvider）

```swift
import AppKit

final class LazyProvider: NSObject, NSPasteboardItemDataProvider {
    let payload: () -> Data
    init(payload: @escaping () -> Data) { self.payload = payload }

    // 要求されたときに初めて呼ばれる。Swift では nonisolated
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem,
                    provideDataForType type: NSPasteboard.PasteboardType) {
        item.setData(payload(), forType: type)
    }

    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}

func copyPromised(provider: LazyProvider) {
    let pb = NSPasteboard.general
    pb.clearContents()
    let item = NSPasteboardItem()
    _ = item.setDataProvider(provider, forTypes: [.pdf, .tiff])
    _ = pb.writeObjects([item])                          // provider は強参照で保持する
}
```

### L. 遅延データ提供（レガシー: NSPasteboardTypeOwner）

```swift
import AppKit

final class LegacyOwner: NSObject, NSPasteboardTypeOwner {
    func pasteboard(_ sender: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .string { sender.setString("late", forType: .string) }
    }
    func pasteboardChangedOwner(_ sender: NSPasteboard) {}   // 所有権喪失
}

func copyPromisedLegacy(owner: LegacyOwner) {
    let pb = NSPasteboard.general
    _ = pb.declareTypes([.string], owner: owner)             // clearContents 相当を内包
    _ = pb.addTypes([.html], owner: owner)
}
```

### H. Universal Clipboard の抑止（iOS の localOnly 相当）

```swift
import AppKit

func copyLocalOnly() {
    let pb = NSPasteboard.general
    // clearContents() ではなくこちらを使う。clearContents() はオプションを解除する
    _ = pb.prepareForNewContents(with: .currentHostOnly)
    _ = pb.writeObjects(["local only" as NSString])
}
```

### R. ペースト — オブジェクト読み取り

```swift
import AppKit

func pasteObjects() {
    let pb = NSPasteboard.general
    let strings = pb.readObjects(forClasses: [NSString.self], options: nil) as? [String]
    let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage]
    let fileURLs = pb.readObjects(forClasses: [NSURL.self],
                                  options: [.urlReadingFileURLsOnly: true]) as? [URL]
    let imageURLs = pb.readObjects(forClasses: [NSURL.self],
                                   options: [.urlReadingContentsConformToTypes: NSImage.imageTypes]) as? [URL]
    _ = (strings, images, fileURLs, imageURLs)
}
```

### R. ペースト — 型別 / アイテム単位

```swift
import AppKit
import UniformTypeIdentifiers

func pasteTyped() {
    let pb = NSPasteboard.general
    _ = pb.string(forType: .string)                      // 全アイテムの最良表現（改行連結あり）
    _ = pb.data(forType: .init("com.example.toolkit.payload"))
    _ = pb.propertyList(forType: .init(UTType.propertyList.identifier))

    for item in pb.pasteboardItems ?? [] {               // 件数が意味を持つ場合はこちら
        _ = item.types
        _ = item.availableType(from: [.string, .html])
        _ = item.string(forType: .string)
        _ = pb.index(of: item)                           // 未所属なら NSNotFound
    }
}
```

### V. 内容確認 / 型判定（データ本体を読まない）

```swift
import AppKit
import UniformTypeIdentifiers

func inspectWithoutReading() -> Bool {
    let pb = NSPasteboard.general
    let hasText = pb.canReadItem(withDataConformingToTypes: [UTType.plainText.identifier])
    let hasImage = pb.canReadObject(forClasses: [NSImage.self], options: nil)
    _ = pb.types
    _ = pb.availableType(from: [.string, .fileURL])
    _ = NSPasteboard.types(filterableTo: .tiff)          // Filter Services（レガシー）
    return hasText || hasImage
}
```

### X. クリップボードのクリア

```swift
import AppKit

func clearClipboard() {
    _ = NSPasteboard.general.clearContents()             // 戻り値は新しい changeCount
}
```

### D. 検出・プライバシー（macOS 15.4+）

```swift
import AppKit

@available(macOS 15.4, *)
func detect() async throws {
    let pb = NSPasteboard.general
    _ = pb.accessBehavior                                 // .default / .ask / .alwaysAllow / .alwaysDeny

    // 通知なし: 一致の有無だけを判定する
    let matched = try await pb.detectedPatterns(for: [\.probableWebURL, \.emailAddresses])

    if matched.contains(\.probableWebURL) {
        // 通知あり: 一致時に内容を取得する。拒否されると throw する
        let values = try await pb.detectedValues(for: [\.probableWebURL])
        _ = values.probableWebURL
    }

    // 通知なし: ファイル参照の内容タイプのみ取得する
    let meta = try await pb.detectedMetadata(for: [\.contentType])
    _ = meta.contentType

    for item in pb.pasteboardItems ?? [] {                // アイテム単位でも同じ 3 種が使える
        _ = try await item.detectedPatterns(for: [\.phoneNumbers])
    }
}
```

### M. 変更監視（changeCount ポーリング）

```swift
import AppKit

@MainActor
final class ClipboardMonitor {
    private var last: Int
    private var timer: Timer?

    init() { last = NSPasteboard.general.changeCount }

    func start(_ onChange: @escaping @MainActor (Int) -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let current = NSPasteboard.general.changeCount
                guard current != self.last else { return }
                self.last = current
                onChange(current)
            }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
}
```

### U. ユーザー起点の貼り付け UI（SwiftUI PasteButton）

```swift
import SwiftUI
import AppKit

struct PasteDemo: View {
    @State private var pasted: String = ""
    var body: some View {
        HStack {
            // macOS では変更に応じた自動 validate / invalidate は行われない
            PasteButton(payloadType: String.self) { strings in
                pasted = strings.first ?? ""
            }
            Button("Copy") {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.writeObjects(["copied" as NSString])
            }
            Text(pasted)
        }
    }
}
```

### U. ユーザー起点の貼り付け UI（NSResponder / NSServicesMenuRequestor）

```swift
import AppKit

// Swift 6 では適合を @MainActor で隔離しないと ConformanceIsolation エラーになる
final class PasteView: NSView, @MainActor NSServicesMenuRequestor {
    @objc func paste(_ sender: Any?) {                   // Edit メニュー / Cmd+V
        _ = readSelection(from: .general)
    }

    func readSelection(from pboard: NSPasteboard) -> Bool {
        guard pboard.canReadObject(forClasses: [NSString.self], options: nil) else { return false }
        return (pboard.readObjects(forClasses: [NSString.self], options: nil) as? [String])?.isEmpty == false
    }

    func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
        pboard.clearContents()
        return pboard.writeObjects(["selection" as NSString])
    }
}
```

### F. ファイル約束 — 提供側

```swift
import AppKit
import UniformTypeIdentifiers

final class PromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    let queue = OperationQueue()

    func filePromiseProvider(_ p: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "export.txt"                                     // ここではまだ書き出さない
    }

    func filePromiseProvider(_ p: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        do { try "content".write(to: url, atomically: true, encoding: .utf8); completionHandler(nil) }
        catch { completionHandler(error) }               // 必ず引数の url に書く
    }

    func operationQueue(for p: NSFilePromiseProvider) -> OperationQueue { queue }
}

func copyFilePromise(delegate: PromiseDelegate) {
    let provider = NSFilePromiseProvider(fileType: UTType.plainText.identifier, delegate: delegate)
    let pb = NSPasteboard.general
    pb.clearContents()
    _ = pb.writeObjects([provider])
}
```

### F. ファイル約束 — 受領側

```swift
import AppKit

func receiveFilePromises(destination: URL) {
    let pb = NSPasteboard.general
    _ = NSFilePromiseReceiver.readableDraggedTypes       // registerForDraggedTypes 用
    let receivers = pb.readObjects(forClasses: [NSFilePromiseReceiver.self],
                                   options: nil) as? [NSFilePromiseReceiver]
    for receiver in receivers ?? [] {
        _ = receiver.fileTypes
        receiver.receivePromisedFiles(atDestination: destination, options: [:],
                                      operationQueue: .main) { url, error in
            _ = (url, error)                             // キャンセル・失敗時も error 付きで呼ばれる
        }
    }
}
```

### G. Filter Services（レガシー・参考）

```swift
import AppKit

func legacyFiltering(data: Data) {
    _ = NSPasteboard(byFilteringData: data, ofType: .tiff)
    _ = NSPasteboard(byFilteringTypesIn: NSPasteboard.general)
    // 新規実装では採用しない。UTType による型判定で代替する
}
```

---

## 10. 要検証事項（断定を避けた項目）

| ID | 内容 | 検証方法 |
|---|---|---|
| V-1 | `types` / `availableType(from:)` / `canReadItem(withDataConformingToTypes:)` / `canReadObject(forClasses:options:)` / `changeCount` がペーストボードアクセスアラートを発生させないか | macOS 15.4 実機で `accessBehavior` を `.ask` にした状態で各 API を単独実行し、アラートおよび System Settings のペーストボード欄への登録有無を確認する |
| V-2 | SwiftUI `PasteButton` / `NSResponder.paste(_:)` / `NSServicesMenuRequestor.readSelection(from:)` が「user originated かつ paste related」としてアラート免除に該当するか | 同上の設定で各経路から貼り付けを実行し、アラート表示の有無を比較する。`.alwaysDeny` 設定下でも読み取れるかも確認する |
| V-3 | `NSPasteboardItemDataProvider` を呼び出し側が強参照しなくてもシステムが保持するか | provider をローカル変数のみで生成して `writeObjects` 後に解放し、別アプリから該当型を要求して供給されるか確認する |
| V-4 | `pasteboard(_:item:provideDataForType:)` および ObjC 版検出 API の completionHandler が呼ばれるスレッド | 実機で `Thread.isMainThread` / `dispatch_queue_get_label` をログ出力して確認する |
| V-5 | `detectedPatterns(for:)` 系が Swift の Task キャンセルを尊重するか（`CancellationError` を throw するか） | 大きなペーストボード内容に対して呼び出し直後に `Task.cancel()` し、throw される error の型を確認する |
| V-6 | App Sandbox 下で、ペーストボードから取得した `fileURL` の内容を読めるか（サンドボックス例外が自動付与されるか） | `MacLibraryExample`（サンドボックス有効）で Finder からコピーしたファイルの URL を読み、`Data(contentsOf:)` の成否を確認する。失敗する場合は D&D 経路との差分も記録する |
| V-7 | 名前付き / 一意名ペーストボードが実際にアプリ終了後も他プロセスから読めるか、および `releaseGlobally()` 後に読めなくなるか | 一意名ペーストボードへ書き込み → アプリ終了 → 別プロセスから同名で読み取り。`releaseGlobally()` 実行後も同様に確認する（iOS 版 M-08 と対比する） |
| V-8 | `prepareForNewContents(with: .currentHostOnly)` が実際に Universal Clipboard 同期を抑止するか | 同一 iCloud アカウントの iPhone（`macos-clipboard は端末 B` 側）で、通常コピーと `.currentHostOnly` コピーの受信可否を比較する |
| V-9 | `.currentHostOnly` 設定後に `writeObjects` 以外（`setString` 等）で書いた場合もオプションが維持されるか | 上記 V-8 と同じ手順を `setString` 経路で実施する |
| V-10 | macOS 15.0 / 15.1 / 15.3 におけるアラートの実挙動差 | 各バージョンの実機または VM で、`readObjects` 実行時のアラート表示頻度と文言を記録する |

---

## 11. Definition of Done

### 調査完了条件

- [x] 対象 OS（macOS 15 以降）の公式ドキュメント URL を一覧化した
- [x] SDK ヘッダ（MacOSX26.2.sdk）を一次ソースとして参照し、シグネチャとバージョン制約を確定した
- [x] 対象機能をサブ機能（P / C / L / H / R / V / X / M / D / U / F / G）へ分解した
- [x] 各サブ機能について API 一覧を作成し、目的・主要引数・返却値・実行方式・エラーケース・最小利用条件を記載した
- [x] 廃止予定 API・廃止済み API と代替 API を注記した（macOS 10.13 / 10.14 廃止分を全件列挙）
- [x] **全採用 API を同期・非同期 API 分類表へ収録した**（サブ機能 / 操作、システム API、実行方式、完了方式、完了スレッド・actor、キャンセル手段、リソース所有権・寿命の全列を記載）
- [x] 非同期 API（検出 API 3 種 + アイテム版 3 種）について、完了方式・完了アクター・キャンセル手段・リソース所有権を記載した
- [x] 公式文書で確定できない事項を推測せず「要検証」として V-1〜V-10 に分離し、検証方法を記載した
- [x] 各サブ機能に最小サンプルコードを記載し、**全件を Swift 6 strict concurrency でコンパイル検証した**
- [x] 実装リスクを権限・制約・互換性の観点で RK-01〜RK-20 として整理した
- [x] 公式ソースと補助ソースを分離した（補助ソースは採用せず、ローカル検証結果として明示した）

### 次工程（設計）への引き継ぎ条件

- [ ] macOS 15.0–15.3 と 15.4+ の分岐方針を設計書で確定する（RK-01 / RK-02）
- [ ] iOS 版 `IosClipboardManager` との公開 API パリティ表を作成し、`expirationDate` 非対応（RK-04）と Universal Clipboard 抑止（`.currentHostOnly`）の対応関係を明記する
- [ ] 所有権取得を `clearContents()` / `prepareForNewContents(with:)` のどちらに集約するかを 1 経路に決める（RK-05）
- [ ] 名前付き / 一意名ペーストボードの公開可否と `releaseGlobally()` の責務所在を決める（RK-06 / RK-07）
- [ ] `NSPasteboard` 非 Sendable を前提とした並行性方針（`@MainActor` 固定か専用実行文脈か）を決める（RK-08）
- [ ] 変更監視のポーリング間隔既定値とアプリ非アクティブ時の停止方針を決める（RK-11）
- [ ] V-1〜V-10 の検証を実機で消化し、結果を設計書または本書の改訂版へ反映する

---

## 12. 次の workflow

本調査結果を確定後、`review-document` workflow でレビューする。
