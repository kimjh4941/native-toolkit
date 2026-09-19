# macOS クリップボード機能 調査企画書 v3

- 作成日: 2026-08-29
- 改訂日: 2026-08-29（v3: 実機検証 V-11 / V-13 の結果を反映、RK-22 / RK-23 新設）
- 前版: `artifact/plans/clipboard/2026-08-29-macos-clipboard-research-v2.md`
- 初版: `artifact/plans/clipboard/2026-08-29-macos-clipboard-research.md`
- レビュー: `artifact/reviews/clipboard/2026-08-29-macos-clipboard-research-review.md`
- 対象OS: macOS 15 以降（本リポジトリの `MACOSX_DEPLOYMENT_TARGET` は 15.0 / 15.1）
- 対象機能: クリップボード（Clipboard / Pasteboard: コピー / ペースト）
- 使用言語: Swift
- 対象フレームワーク: AppKit（`NSPasteboard` / `NSPasteboardItem` / `NSFilePromiseProvider` / `NSFilePromiseReceiver`）、UniformTypeIdentifiers（`UTType`）、DataDetection（`DDMatch*`）、SwiftUI（`PasteButton` / `copyable` / `cuttable` / `pasteDestination`）
- 検証環境: macOS 26.3 / Xcode 26.3 / MacOSX26.2.sdk（AppKit・SwiftUI のヘッダと `.swiftinterface` を一次確認に使用）
- 関連: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`（iOS 版）、`artifact/plans/clipboard/2026-07-25-android-clipboard-research.md`（Android 版）

---

## 0. v3 での変更点（実測反映サマリ）

2026-08-29 に検証アプリ `ClipboardProbe`（Apple Development 署名 / App Sandbox 有効 / macOS 26.3）
で実測した結果を反映した。

| 項目 | 結果 | 反映先 |
|---|---|---|
| V-11 | **解決。macOS 26.3 と 15.4.1 の両方で同一結果。provider はシステムが保持するが `weak` delegate は即座に解放される** | RK-21 を確定事項へ格上げし、「provider だけが生き残る」悪化条件を追記 |
| V-13a | **解決。macOS 26.3 と 15.4.1 の両方で同一結果。他アプリが所有者のペーストボードへの `writeObjects` は `false` を返し、一切変化しない** | 第 8 章 P-2 / 8.1 / RK-23 へ反映 |
| V-13b | **解決。macOS 15.4.1 で確認。自分が所有権を持つ間の 2 回目以降の `writeObjects` は成立する**（items 1→2、`changeCount` は不変で所有権を維持） | P-2 を「自所有時のみ対応」へ。RK-23 を「限定的に提供可能」へ改訂 |
| V-1 の測定 | **試した全構成でアラートを再現できず、判定保留**（26.3 実機・15.4.1 VM の両方、クリック起点・無人バックグラウンドの両方で `readObjects` が無警告で成功） | RK-22 新設。V-1 / V-2 / V-12 は「正の対照が成立しないため結果を採用しない」として保留 |

## 0.1 v2 での変更点（レビュー反映サマリ）

| 反映先 | 指摘 | 対応 |
|---|---|---|
| 6.F / 7 / 8 / 9 | `NSFilePromiseProvider.delegate` は `weak` だが保持責務が未定義（高） | F-03 に weak を明記。RK-21 を新設。分類表に provider / delegate の寿命列を記載。サンプルを所有権を持つセッション型へ書き換え。**`NSFilePromiseProviderDelegate` には完了通知が存在しない**ことを明記し、解放判断を `changeCount` に紐づけた |
| 8 RK-01 / RK-02 | 未検証の `canRead*` を通知回避策として確定採用（高） | RK-01 / RK-02 を書き換え。`canRead*` は「型判定の最適化」に限定し、アラート非発生を保証しないと明記。通知回避が契約上必要な操作はユーザー起点 UI 経路（U）へ限定。採用判断を V-1 の結果に条件付けた |
| 6.U | `PasteButton(payloadType:onPaste:)` の最小 OS が誤り（中） | 型 10.15 / `supportedContentTypes:payloadAction:` 11.0 / `payloadType:onPaste:` **13.0** に分離。非推奨 initializer 2 種も追加 |
| 3 / 5 / 6.U | `NSResponder.paste(_:)` は不正確（中） | responder chain の `paste:` action（`NSText.paste(_:)` / カスタム responder は `@objc paste(_:)`）へ表記変更。`NSText` と `NSResponder` の公式文書を一次ソースへ追加 |
| 1 / 8（新設）/ 11 | iOS 公開 API パリティ表が未作成（中） | 第 8 章としてパリティ表を新設（iOS `IosClipboardManager` の P-1〜P-16 を全件対応付け） |
| 6 / 7 / 11 | API 表と分類表の対応関係が追跡不能（中） | 全 API 表に **行 ID 列**を追加し、分類表を同じ ID で引けるようにした。定数・値型は「分類対象外」として ID を明示列挙 |
| 10 V-8 / V-9 | `.currentHostOnly` 検証に正の対照がない（中） | V-8 を「通常コピーの転送成功を先に確認 → その後 `.currentHostOnly` の非転送を確認」へ書き換え。環境記録条件を DoD に追加 |
| 10 V-8 | 端末 A / B の役割記述がプレースホルダー（低） | 「送信元 = Mac、受信先 = 同一 iCloud アカウントの iPhone」へ明示 |
| 9 | 「全件検証済み」がコンパイル検証の範囲を超える（低） | 「**コンパイル検証済み**」へ限定し、実行時契約は V-1〜V-13 へリンク |
| 6.U（追加発見） | レビュー未指摘の網羅漏れ | SwiftUI `copyable(_:)` / `cuttable(for:action:)` / `pasteDestination(for:action:validator:)`（いずれも **macOS 13.0+ / macOS 専用**）を U-05〜U-07 として追加。検証項目 V-12 も新設 |

サブ機能記号の変更: v1 の `V.（内容確認・型判定）` は要検証 ID（V-1〜）と紛らわしいため、v2 では **`Q.`** に改称した。要検証 ID は v1 の V-1〜V-10 をそのまま維持し、V-11 / V-12 を追加している。

---

## 1. 目的

macOS のネイティブクリップボード API（`NSPasteboard` 系）を全網羅し、native-toolkit（`mac/MacLibrary`）への組み込み設計に必要な情報を整理する。

対象は次のとおり。テキスト / URL / 画像 / 色 / 属性文字列 / 任意 UTI データのコピー・ペースト、複数アイテム操作、遅延データ提供（promise）、内容確認・型判定、変更監視、macOS 15 以降のペーストボードアクセスアラートと macOS 15.4 以降の検出 API（ユーザー通知なしの事前判定）、Universal Clipboard（デバイス間同期）の抑止、名前付きペーストボードの寿命とリソース解放責務。

あわせて、既存 iOS 実装（`IosClipboardManager`）の公開操作それぞれについて、macOS における **対応 / 代替 / 非対応** を第 8 章のパリティ表で確定する。公開シグネチャそのものの決定は設計工程に委ねる。

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
- ユーザー起点の貼り付け・コピー経路: SwiftUI `PasteButton` / `copyable(_:)` / `cuttable(for:action:)` / `pasteDestination(for:action:validator:)`、responder chain の `paste:` action、`NSServicesMenuRequestor`
- ファイル約束（File Promise）: `NSFilePromiseProvider` / `NSFilePromiseProviderDelegate` / `NSFilePromiseReceiver`
- カスタム型の読み書きプロトコル: `NSPasteboardWriting` / `NSPasteboardReading`
- Filter Services（レガシー・参考）: `init(byFilteringFile:)` / `init(byFilteringData:ofType:)` / `init(byFilteringTypesIn:)` / `types(filterableTo:)`
- 廃止済みシンボル（全網羅の担保として一覧化のみ）

### out（対象外）

- iOS（`UIPasteboard`）/ Android / Windows のクリップボード API
- ドラッグ&ドロップ（`NSDraggingSession` / `NSDraggingInfo` / `registerForDraggedTypes(_:)`、SwiftUI `dropDestination(for:action:)` / `draggable(_:)`）。`NSPasteboard.Name.drag` および File Promise を共有するが、D&D の UI 実装そのものは本調査対象外
- Services メニューの提供側実装（`NSApplication.servicesProvider`、`NSServices` Info.plist 定義、SwiftUI `importableFromServices(for:action:)`）。読み取り経路として `NSServicesMenuRequestor` のみ扱う
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
| NSFilePromiseProvider.delegate（weak の根拠） | https://developer.apple.com/documentation/appkit/nsfilepromiseprovider/delegate |
| NSFilePromiseProviderDelegate | https://developer.apple.com/documentation/appkit/nsfilepromiseproviderdelegate |
| NSFilePromiseReceiver | https://developer.apple.com/documentation/appkit/nsfilepromisereceiver |
| NSServicesMenuRequestor | https://developer.apple.com/documentation/appkit/nsservicesmenurequestor |
| NSText.paste(_:)（`paste:` action の宣言元） | https://developer.apple.com/documentation/appkit/nstext/paste(_:) |
| NSResponder（responder chain と action 送出） | https://developer.apple.com/documentation/appkit/nsresponder |
| SwiftUI PasteButton | https://developer.apple.com/documentation/swiftui/pastebutton |
| SwiftUI View.copyable(_:) | https://developer.apple.com/documentation/swiftui/view/copyable(_:) |
| SwiftUI View.cuttable(for:action:) | https://developer.apple.com/documentation/swiftui/view/cuttable(for:action:) |
| SwiftUI View.pasteDestination(for:action:validator:) | https://developer.apple.com/documentation/swiftui/view/pastedestination(for:action:validator:) |
| UniformTypeIdentifiers / UTType | https://developer.apple.com/documentation/uniformtypeidentifiers/uttype |
| DataDetection DDMatchLink（検出値の型） | https://developer.apple.com/documentation/datadetection/ddmatchlink |
| App Sandbox | https://developer.apple.com/documentation/security/app-sandbox |

### 3.1 SDK ヘッダ・Swift interface（一次ソース。公式文書と同格に扱う）

Xcode 26.3 / MacOSX26.2.sdk 同梱ファイルを直接確認済み。バージョン制約・シグネチャ・注意書きの根拠はここにある。

- `AppKit.framework/Headers/NSPasteboard.h`
- `AppKit.framework/Headers/NSPasteboardItem.h`
- `AppKit.framework/Headers/NSFilePromiseProvider.h`（`delegate` の `weak` 宣言）
- `AppKit.framework/Headers/NSFilePromiseReceiver.h`
- `AppKit.framework/Headers/NSApplication.h`（`NSServicesMenuRequestor`）
- `AppKit.framework/Headers/NSResponder.h`（`paste` の宣言が **存在しない**ことの確認）
- `AppKit.framework/Headers/NSText.h`（`- (void)paste:(nullable id)sender;` の宣言。128 行目）
- `AppKit.framework/Versions/C/Modules/AppKit.swiftmodule/arm64e-apple-macos.swiftinterface`（検出 API の Swift refined 形）
- `SwiftUI.framework/Modules/SwiftUI.swiftmodule/arm64e-apple-macos.swiftinterface`（`PasteButton` の initializer 別 availability、`copyable` / `cuttable` / `pasteDestination`）

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
- **「Your object that is ultimately responsible for determining the final file name and writing the promised data to the destination.」に付随する宣言 `@property(weak, nullable) id <NSFilePromiseProviderDelegate> delegate;`**（NSFilePromiseProvider.h。**weak 保持**の根拠）
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
| `PasteButton` の initializer 別 availability | `SwiftUI.swiftinterface` の該当行を直接参照 | 型は macOS 10.15、`supportedContentTypes:payloadAction:` は 11.0、`payloadType:onPaste:` は **13.0** | high（SDK 一次情報） |
| `paste:` action の宣言元 | `NSResponder.h` / `NSText.h` を全文検索 | `NSResponder.h` に `paste` の宣言は 0 件。`NSText.h:128` が実体 | high（SDK 一次情報） |
| `copyable` / `cuttable` / `pasteDestination` の availability | `SwiftUI.swiftinterface` の該当行を直接参照 | いずれも macOS 13.0+ かつ **iOS / tvOS / watchOS / visionOS では unavailable**（macOS 専用） | high（SDK 一次情報） |
| F-06 の Swift `async throws` 形の有無 | `filePromiseProvider(_:writePromiseTo:)` のみを実装した `NSFilePromiseProviderDelegate` 適合を `-swift-version 6` でコンパイル | エラーなし。**`async throws` 形でも適合できる**（completionHandler 形と択一） | high（コンパイラ出力） |
| F-10 の Swift `async throws` 形の有無 | `receivePromisedFiles` を `reader` 引数なしで `try await` 呼び出し | `missing argument for parameter 'reader'`。**async 形は存在しない** | high（コンパイラ出力） |
| 本書のサンプルコード全件 | `xcrun swiftc -swift-version 6 -typecheck -target arm64-apple-macos15.4` | 全件エラー・警告なし（**型検査のみ**。実行時契約は保証しない） | high（型検査の範囲で） |

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
│   ├── NSPasteboardItemDataProvider（推奨。完了通知あり）
│   ├── NSPasteboardTypeOwner + declareTypes / addTypes（レガシー）
│   └── NSPasteboardWritingOptions.promised
├── H. デバイス間同期制御（Universal Clipboard）
│   └── prepareForNewContents(with: .currentHostOnly)
├── R. ペースト（読み取り）
│   ├── オブジェクト読み取り（readObjects(forClasses:options:)）
│   ├── 型別読み取り（string / data / propertyList）
│   ├── アイテム単位（pasteboardItems / index(of:) / NSPasteboardItem の各アクセサ）
│   └── カスタム型（NSPasteboardReading 適合）
├── Q. 内容確認・型判定（本体を読まない。※アラート非発生は未保証。V-1）
│   ├── types / availableType(from:)
│   ├── canReadItem(withDataConformingToTypes:)
│   └── canReadObject(forClasses:options:)
├── X. クリア
│   └── clearContents()（※ currentHostOnly を解除する）
├── M. 変更監視
│   └── changeCount ポーリング（※通知 API は存在しない）
├── D. 検出・プライバシー（macOS 15.4+）
│   ├── detectedPatterns(for:)（通知なし）
│   ├── detectedValues(for:)（通知あり・拒否時 error）
│   ├── detectedMetadata(for:)（通知なし）
│   └── accessBehavior（現在のアクセス設定の照会）
├── U. ユーザー起点のコピー / 貼り付け UI（アラート免除が期待される経路。V-2 / V-12）
│   ├── SwiftUI PasteButton（型 10.15 / init により 11.0・13.0）
│   ├── SwiftUI copyable / cuttable / pasteDestination（macOS 13.0+・macOS 専用）
│   ├── responder chain の paste: action（NSText.paste(_:) / カスタム responder は @objc paste(_:)）
│   └── NSServicesMenuRequestor（readSelection(from:) / writeSelection(to:types:)）
├── F. ファイル約束（File Promise）
│   ├── NSFilePromiseProvider + NSFilePromiseProviderDelegate（提供側。delegate は weak・完了通知なし）
│   └── NSFilePromiseReceiver（受領側）
└── G. レガシー / 参考
    ├── Filter Services（init(byFilteringFile:) 他）
    ├── File Contents（writeFileContents / readFileContentsType / write(_:) / readFileWrapper）
    └── 廃止済み定数群（NSStringPboardType 等、macOS 10.14 で廃止）
```

---

## 6. API 全網羅表（サブ機能別）

型表記は Swift。`最小 OS` は SDK ヘッダ・`.swiftinterface` の availability に基づく。
**ID 列**は第 7 章の同期・非同期分類表と 1 対 1 で対応する（定数・値型を除く。除外分は 7.1 に列挙）。

### P. ペーストボード取得・寿命管理

| ID | API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| P-01 | `NSPasteboard.general` | 汎用ペーストボードの取得 | なし | `NSPasteboard` | 同期 | なし | macOS 10.0 |
| P-02 | `NSPasteboard(name:)` | 名前付きペーストボードの取得・生成 | `name: NSPasteboard.Name` | `NSPasteboard` | 同期 | なし | macOS 10.0 |
| P-03 | `NSPasteboard.withUniqueName()` | 一意名ペーストボードの生成 | なし | `NSPasteboard` | 同期 | なし | macOS 10.0 |
| P-04 | `releaseGlobally()` | ペーストボードサーバ上のリソース解放 | なし | `Void`（`oneway`） | 同期（片方向） | 標準ペーストボードに呼ぶと不正動作 | macOS 10.0 |
| P-05 | `name` | ペーストボード名の照会 | なし | `NSPasteboard.Name` | 同期 | なし | macOS 10.0 |
| P-06 | `NSPasteboard.Name`（定数） | 標準名の名前空間 | - | `.general` / `.font` / `.ruler` / `.find` / `.drag` | 定数 | - | macOS 10.13（旧定数は 10.13 で廃止） |

### C. コピー（書き込み）

| ID | API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| C-01 | `clearContents()` | 内容消去・所有権取得 | なし | `Int`（新しい `changeCount`） | 同期 | なし。`currentHostOnly` を解除する | macOS 10.6 |
| C-02 | `prepareForNewContents(with:)` | 内容消去 + オプション指定 | `options: NSPasteboard.ContentsOptions` | `Int` | 同期 | なし | macOS 10.12 |
| C-03 | `writeObjects(_:)` | `NSPasteboardWriting` 適合物の一括書き込み | `[NSPasteboardWriting]` | `Bool` | 同期 | 追加失敗で `false` / 既に他ペーストボードに紐づく `NSPasteboardItem` を渡すと例外 | macOS 10.6 |
| C-04 | `setString(_:forType:)` | 先頭アイテムへ文字列を設定 | `String`, `PasteboardType` | `Bool` | 同期 | 所有権未取得・不正 UTI で `false` | macOS 10.0 |
| C-05 | `setData(_:forType:)` | 先頭アイテムへバイナリを設定 | `Data?`, `PasteboardType` | `Bool` | 同期 | 同上 | macOS 10.0 |
| C-06 | `setPropertyList(_:forType:)` | 先頭アイテムへ plist を設定 | `Any`, `PasteboardType` | `Bool` | 同期 | plist 非適合で `false` | macOS 10.0 |
| C-07 | `NSPasteboardItem()` | アイテム生成 | なし | `NSPasteboardItem` | 同期 | なし | macOS 10.6 |
| C-08 | `NSPasteboardItem.setString(_:forType:)` | アイテムへ文字列を設定 | `String`, `PasteboardType` | `Bool` | 同期 | 不正 UTI で `false` | macOS 10.6 |
| C-09 | `NSPasteboardItem.setData(_:forType:)` | アイテムへバイナリを設定 | `Data`, `PasteboardType` | `Bool` | 同期 | 同上 | macOS 10.6 |
| C-10 | `NSPasteboardItem.setPropertyList(_:forType:)` | アイテムへ plist を設定 | `Any`, `PasteboardType` | `Bool` | 同期 | 同上 | macOS 10.6 |
| C-11 | `NSPasteboard.PasteboardType`（定数） | 標準型定数 | - | `.string` `.pdf` `.tiff` `.png` `.rtf` `.rtfd` `.html` `.tabularText` `.font` `.ruler` `.color` `.sound` `.multipleTextSelection` `.textFinderOptions` `.URL` `.fileURL` | 定数 | - | `.URL` / `.fileURL` は 10.13、`.textFinderOptions` は 10.7、他は 10.6 |
| C-12 | `NSPasteboardWriting.writableTypes(forPasteboard:)` | 書き込み可能型の申告（required） | `NSPasteboard` | `[PasteboardType]` | callback（実装側・同期） | 実装内で他のペーストボード操作を行うと未定義 | macOS 10.6 |
| C-13 | `NSPasteboardWriting.writingOptions(forType:pasteboard:)` | 型ごとの書き込み方式（optional） | `PasteboardType`, `NSPasteboard` | `NSPasteboard.WritingOptions` | callback（実装側・同期） | 同上 | macOS 10.6 |
| C-14 | `NSPasteboardWriting.pasteboardPropertyList(forType:)` | 実データの供給（required） | `PasteboardType` | `Any?` | callback（実装側・同期。`.promised` 指定時は要求駆動） | `nil` 返却で当該型は提供されない | macOS 10.6 |
| C-15 | `NSPasteboard.WritingOptions`（定数） | 書き込み方式指定 | - | `.promised` | 定数 | - | macOS 10.6 |

標準で `NSPasteboardWriting` / `NSPasteboardReading` の双方に適合する Cocoa クラス: `NSString` / `NSAttributedString` / `NSURL` / `NSColor` / `NSSound` / `NSImage` / `NSPasteboardItem`（NSPasteboard.h の記載による）。

### L. 遅延データ提供（promise）

| ID | API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| L-01 | `NSPasteboardItem.setDataProvider(_:forTypes:)` | 型を約束し提供者を登録 | `NSPasteboardItemDataProvider`, `[PasteboardType]` | `Bool` | 同期（登録） | 不正 UTI で `false` | macOS 10.6 |
| L-02 | `NSPasteboardItemDataProvider.pasteboard(_:item:provideDataForType:)` | 要求時にデータを供給（required） | `NSPasteboard?`, `NSPasteboardItem`, `PasteboardType` | `Void`（要求駆動コールバック） | callback | 供給しない場合は読み手が nil を受け取る | macOS 10.6。Swift では `nonisolated` |
| L-03 | `NSPasteboardItemDataProvider.pasteboardFinishedWithDataProvider(_:)` | 提供者が不要になった通知（optional） | `NSPasteboard` | `Void` | callback | - | macOS 10.6。Swift では `nonisolated` |
| L-04 | `declareTypes(_:owner:)` | 先頭アイテムの型宣言（レガシー） | `[PasteboardType]`, `Any?` | `Int` | 同期 | `writeObjects(_:)` との併用は非推奨 | macOS 10.0 |
| L-05 | `addTypes(_:owner:)` | 先頭アイテムへ型を追加 | `[PasteboardType]`, `Any?` | `Int` | 同期 | 所有権未取得で無効 | macOS 10.0 |
| L-06 | `NSPasteboardTypeOwner.pasteboard(_:provideDataForType:)` | 要求時にデータを供給（required） | `NSPasteboard`, `PasteboardType` | `Void` | callback | - | macOS 11.0 でプロトコル化（旧 informal protocol は 10.0–11.0 で廃止） |
| L-07 | `NSPasteboardTypeOwner.pasteboardChangedOwner(_:)` | 所有権喪失の通知（optional） | `NSPasteboard` | `Void` | callback | - | macOS 11.0 |

### H. デバイス間同期制御（Universal Clipboard）

| ID | API 名 | 目的 | 主要引数 | 返却値 | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| H-01 | `NSPasteboard.ContentsOptions.currentHostOnly`（定数） | 他デバイスへ内容を渡さない | - | - | 定数 | `clearContents()`（C-01）を後から呼ぶと解除される | macOS 10.12 |

適用手段は C-02（`prepareForNewContents(with:)`）。iOS の `UIPasteboard.OptionsKey.localOnly` に相当する。**iOS の `expirationDate` に相当する API は macOS に存在しない**（第 8 章 / RK-04）。

### R. ペースト（読み取り）

| ID | API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| R-01 | `readObjects(forClasses:options:)` | 指定クラスのオブジェクトを一括読み取り | `[AnyClass]`, `[ReadingOptionKey: Any]?` | `[Any]?` | 同期 | 取得失敗・生成不可で `nil` | macOS 10.6 |
| R-02 | `ReadingOptionKey.urlReadingFileURLsOnly`（定数） | ファイル URL のみに限定 | `NSNumber(Bool)` | - | 定数 | - | macOS 10.6 |
| R-03 | `ReadingOptionKey.urlReadingContentsConformToTypes`（定数） | URL の内容 UTI で絞り込み | `[String]` | - | 定数 | 内容型が判定不能なら不一致扱い | macOS 10.6 |
| R-04 | `string(forType:)` | 全アイテムの最良表現を文字列で取得 | `PasteboardType` | `String?` | 同期 | 該当なしで `nil` | macOS 10.0 |
| R-05 | `data(forType:)` | 同上（バイナリ） | `PasteboardType` | `Data?` | 同期 | 同上 | macOS 10.0 |
| R-06 | `propertyList(forType:)` | 同上（plist） | `PasteboardType` | `Any?` | 同期 | 同上 | macOS 10.0 |
| R-07 | `pasteboardItems` | 全アイテムの取得 | なし | `[NSPasteboardItem]?` | 同期 | 取得失敗で `nil` | macOS 10.6 |
| R-08 | `index(of:)` | アイテムのインデックス取得 | `NSPasteboardItem` | `Int`（未所属は `NSNotFound`） | 同期 | - | macOS 10.6 |
| R-09 | `NSPasteboardItem.string/data/propertyList(forType:)` | アイテム単位の型別取得 | `PasteboardType` | 値 or `nil` | 同期 | 所有者変更後は `nil` | macOS 10.6 |
| R-10 | `NSPasteboardReading.readableTypes(forPasteboard:)` | 読み取り可能型の申告（required・static） | `NSPasteboard` | `[PasteboardType]` | callback（実装側・同期） | 実装内で他のペーストボード操作を行うと未定義 | macOS 10.6 |
| R-11 | `NSPasteboardReading.readingOptions(forType:pasteboard:)` | 読み取り前処理の指定（optional・static） | `PasteboardType`, `NSPasteboard` | `NSPasteboard.ReadingOptions` | callback（実装側・同期） | 同上 | macOS 10.6 |
| R-12 | `NSPasteboardReading.init?(pasteboardPropertyList:ofType:)` | データからのインスタンス生成（optional） | `Any`, `PasteboardType` | `Self?` | callback（実装側・同期） | `nil` 返却で当該アイテムは結果から除外 | macOS 10.6 |
| R-13 | `NSPasteboard.ReadingOptions`（定数） | 読み取り前処理の指定値 | - | `.asData` / `.asString` / `.asPropertyList` / `.asKeyedArchive` | 定数 | 複数指定は不可（1 つのみ） | macOS 10.6 |

`string(forType:)` / `data(forType:)` は「全アイテムの最良表現」を返す。テキスト系（string / RTF / RTFD）では複数アイテムのテキストが改行連結されて 1 つの結果になる（NSPasteboard.h 記載）。アイテム単位の厳密な取得が必要なら R-07 を使う。

### Q. 内容確認・型判定（データ本体を読まない）

| ID | API 名 | 目的 | 主要引数 | 返却値 | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| Q-01 | `types` | ペーストボード全体の型一覧 | なし | `[PasteboardType]?` | 同期 | 取得失敗で `nil` | macOS 10.0 |
| Q-02 | `availableType(from:)` | 指定候補のうち最初に合致する型 | `[PasteboardType]` | `PasteboardType?` | 同期 | 該当なしで `nil` | macOS 10.0 |
| Q-03 | `canReadItem(withDataConformingToTypes:)` | 指定 UTI に適合するアイテムの有無 | `[String]` | `Bool` | 同期 | - | macOS 10.6 |
| Q-04 | `canReadObject(forClasses:options:)` | 指定クラスを生成可能かの判定 | `[AnyClass]`, `[ReadingOptionKey: Any]?` | `Bool` | 同期 | - | macOS 10.6 |
| Q-05 | `NSPasteboardItem.types` | アイテムの型一覧 | なし | `[PasteboardType]` | 同期 | - | macOS 10.6 |
| Q-06 | `NSPasteboardItem.availableType(from:)` | アイテム内の合致型 | `[PasteboardType]` | `PasteboardType?` | 同期 | 該当なしで `nil` | macOS 10.6 |
| Q-07 | `NSPasteboard.types(filterableTo:)` | 指定型へ変換可能な型一覧（Filter Services） | `PasteboardType` | `[PasteboardType]` | 同期 | - | macOS 10.0 |

> **これらがアクセスアラートを発生させないという公式の保証はない（V-1 で要検証）。** Q 群は「型判定の最適化」として扱い、「通知なしで内容を判定できる」契約には使わない。通知回避が契約上必要な場合は D-01 / D-03（macOS 15.4+）または U 群のユーザー起点 UI を用いる。詳細は RK-01 / RK-02。

### X. クリア

`clearContents()`（C-01）を用いる。新規 ID は割り当てない。戻り値は新しい `changeCount`。`prepareForNewContents(with:)`（C-02）で設定した `currentHostOnly` を**解除する**点に注意（RK-05）。

### M. 変更監視

| ID | API 名 | 目的 | 主要引数 | 返却値 | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| M-01 | `changeCount` | 所有権変更回数の取得 | なし | `Int` | 同期 | - | macOS 10.0 |

**macOS には `UIPasteboard.changedNotification` に相当する通知 API が存在しない**（AppKit ヘッダ全文検索で該当なし）。M-01 のポーリングが唯一の公式手段。

### D. 検出・プライバシー（macOS 15.4+）

Swift では ObjC の completionHandler 版が `NS_REFINED_FOR_SWIFT` により隠蔽され、`async throws` 版のみが公開される（`AppKit.swiftinterface` で確認済み）。

| ID | API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| D-01 | `detectedPatterns(for:)` | 先頭アイテムのパターン一致判定（**通知なし**） | `Set<PartialKeyPath<DetectedValues>>` | `Set<PartialKeyPath<DetectedValues>>` | async throws | 検出失敗時に throw | macOS 15.4 |
| D-02 | `detectedValues(for:)` | 一致時に内容も取得（**通知あり**） | 同上 | `NSPasteboard.DetectedValues` | async throws | ユーザー拒否時に throw | macOS 15.4 |
| D-03 | `detectedMetadata(for:)` | メタデータのみ取得（**通知なし**） | `Set<PartialKeyPath<DetectedMetadata>>` | `NSPasteboard.DetectedMetadata` | async throws | 検出失敗時に throw | macOS 15.4 |
| D-04 | `NSPasteboardItem.detectedPatterns(for:)` | アイテム単位の D-01 | 同上 | 同上 | async throws | 同上 | macOS 15.4 |
| D-05 | `NSPasteboardItem.detectedValues(for:)` | アイテム単位の D-02 | 同上 | 同上 | async throws | 同上 | macOS 15.4 |
| D-06 | `NSPasteboardItem.detectedMetadata(for:)` | アイテム単位の D-03 | 同上 | 同上 | async throws | 同上 | macOS 15.4 |
| D-07 | `accessBehavior` | 現在のアクセス設定の照会 | なし | `NSPasteboard.AccessBehavior` | 同期 | - | macOS 15.4 |
| D-08 | `NSPasteboard.AccessBehavior`（定数） | アクセス設定の列挙 | - | `.default` / `.ask` / `.alwaysAllow` / `.alwaysDeny` | 定数 | - | macOS 15.4 |
| D-09 | `NSPasteboard.DetectedValues`（値型） | 検出値のコンテナ | - | `patterns` / `probableWebURL: String` / `probableWebSearch: String` / `number: Double?` / `links: [DDMatchLink]` / `phoneNumbers` / `emailAddresses` / `postalAddresses` / `calendarEvents` / `shipmentTrackingNumbers` / `flightNumbers` / `moneyAmounts` | 構造体 | - | macOS 15.4（`DDMatch*` は macOS 12.0） |
| D-10 | `NSPasteboard.DetectedMetadata`（値型） | 検出メタデータのコンテナ | - | `metadataTypes` / `contentType: UTType?` | 構造体 | - | macOS 15.4 |
| D-11 | ObjC 版（Swift 不可視・参考） | 全網羅の担保 | - | `detectPatternsForPatterns:completionHandler:` / `detectValuesForPatterns:completionHandler:` / `detectMetadataForTypes:completionHandler:` / `NSPasteboardDetectionPattern*`（11 定数）/ `NSPasteboardMetadataTypeContentType` | callback | - | macOS 15.4 |

`.default` の意味（NSPasteboard.h 記載）: アクセスアラートを一度も発生させていないアプリは `.default` を返し、System Settings のペーストボード欄に現れない。最初のアラート発生時に `.ask` へ自動遷移し、以後ユーザーが `.ask` / `.alwaysAllow` / `.alwaysDeny` を切り替えられる。

### U. ユーザー起点のコピー / 貼り付け UI

| ID | API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| U-01 | `PasteButton(payloadType:onPaste:)` | Transferable 型で受け取る貼り付けボタン | `T.Type where T: Transferable`, `([T]) -> Void` | `View` / クロージャ呼び出し | callback（MainActor） | 型不一致時は呼ばれない | **macOS 13.0**（型自体は 10.15） |
| U-02 | `PasteButton(supportedContentTypes:payloadAction:)` | UTType 指定版 | `[UTType]`, `([NSItemProvider]) -> Void` | `View` | callback（MainActor） | - | macOS 11.0 |
| U-03 | `PasteButton(supportedContentTypes:validator:payloadAction:)` | 検証付き UTType 版 | `[UTType]`, `([NSItemProvider]) -> Payload?`, `(Payload) -> Void` | `View` | callback（MainActor） | validator が `nil` を返すと無効 | macOS 11.0。**非推奨**（macOS 専用） |
| U-04 | `PasteButton(supportedTypes:payloadAction:)` / `(supportedTypes:validator:payloadAction:)` | 文字列型指定版 | `[String]`, ... | `View` | callback（MainActor） | - | macOS 10.15。**非推奨**（「Provide `UTType`s as the `supportedContentTypes` instead.」） |
| U-05 | `View.copyable(_:)` | Edit メニューの Copy を有効化 | `@autoclosure () -> [T] where T: Transferable` | `some View` | callback（MainActor） | - | **macOS 13.0。iOS 等では unavailable（macOS 専用）** |
| U-06 | `View.cuttable(for:action:)` | Edit メニューの Cut を有効化 | `T.Type`, `() -> [T]` | `some View` | callback（MainActor） | - | 同上 |
| U-07 | `View.pasteDestination(for:action:validator:)` | Edit メニューの Paste 受け口 | `T.Type`, `([T]) -> Void`, `([T]) -> [T]` | `some View` | callback（MainActor） | validator が空配列を返すと action は呼ばれない | 同上 |
| U-08 | responder chain の `paste:` action | Edit メニュー / Cmd+V の受け口 | `Any?` | `Void` | callback（MainActor） | responder chain 上に実装がないと無反応 | 宣言元は `NSText.paste(_:)`（macOS 10.0）。**`NSResponder` には宣言がない**。カスタム responder は `@objc func paste(_ sender: Any?)` を実装して action を受ける |
| U-09 | `NSServicesMenuRequestor.readSelection(from:)` | Services / 貼り付けからの読み取り | `NSPasteboard` | `Bool` | callback | 受理不可で `false` | macOS 10.0。要件は `nonisolated` |
| U-10 | `NSServicesMenuRequestor.writeSelection(to:types:)` | Services への書き出し | `NSPasteboard`, `[PasteboardType]` | `Bool` | callback | 提供不可で `false` | macOS 10.0。要件は `nonisolated` |

`PasteButton` は macOS では iOS と異なり **ペーストボード変更に応じた自動 validate / invalidate を行わない**（公式文書に明記。RK-16）。U 群が「user originated かつ paste related」としてアラート免除に該当するかは **要検証（U-01〜U-04 / U-08〜U-10 は V-2、U-05〜U-07 は V-12）**。

### F. ファイル約束（File Promise）

| ID | API 名 | 目的 | 主要引数 | 返却値 / コールバック | 実行方式 | エラーケース | 最小利用条件 |
|---|---|---|---|---|---|---|---|
| F-01 | `NSFilePromiseProvider(fileType:delegate:)` | 約束提供者の生成 | `String`(UTI), `NSFilePromiseProviderDelegate` | `NSFilePromiseProvider` | 同期 | `fileType` が `data`/`directory` に非適合なら例外 | macOS 10.12 |
| F-02 | `NSFilePromiseProvider.fileType` | 提供する UTI の参照・変更 | - | `String` | 同期 | 同上 | macOS 10.12 |
| F-03 | `NSFilePromiseProvider.delegate` | delegate の参照・設定 | - | `id<NSFilePromiseProviderDelegate>?` | 同期 | **`weak` 保持。呼び出し側が強参照しないと約束の履行前に解放される** | macOS 10.12 |
| F-04 | `NSFilePromiseProvider.userInfo` | 提供元データの識別子 | - | `Any?` | 同期 | - | macOS 10.12 |
| F-05 | `NSFilePromiseProviderDelegate.filePromiseProvider(_:fileNameForType:)` | ファイル名の決定（required） | provider, `String` | `String` | callback（MainActor） | - | macOS 10.12。`NS_SWIFT_UI_ACTOR` |
| F-06 | `NSFilePromiseProviderDelegate.filePromiseProvider(_:writePromiseTo:completionHandler:)`<br>Swift 版: `filePromiseProvider(_:writePromiseTo:)` **`async throws`** | 実データの書き出し（required） | provider, `URL`, `(Error?) -> Void`（async 版は provider, `URL`） | `Void` / async 版は `Void` を返し throw で失敗を伝える | callback → completion **または async throws** | 書き出し失敗を `completionHandler` に渡す（async 版は throw）。**1 回の書き出し要求につき completion をちょうど 1 回呼ぶ** | macOS 10.12。`NS_SWIFT_NONISOLATED`。F-07 のキューで呼ばれる。**Swift ではどちらか一方を実装する**（コンパイル検証済み） |
| F-07 | `NSFilePromiseProviderDelegate.operationQueue(for:)` | 書き出しキューの指定（optional） | provider | `OperationQueue` | callback（MainActor） | 未実装時は `OperationQueue.main` | macOS 10.12。`NS_SWIFT_UI_ACTOR` |
| F-08 | `NSFilePromiseReceiver.readableDraggedTypes` | 受領可能な型一覧（class property） | なし | `[String]` | 同期 | - | macOS 10.12 |
| F-09 | `NSFilePromiseReceiver.fileTypes` / `.fileNames` | 約束されたファイルの情報 | なし | `[String]` | 同期 | `fileNames` は F-10 実行前は空配列 | macOS 10.12 |
| F-10 | `NSFilePromiseReceiver.receivePromisedFiles(atDestination:options:operationQueue:reader:)` | 約束の実行と受領 | `URL`, `[AnyHashable: Any]`, `OperationQueue`, `(URL, Error?) -> Void` | `Void` | callback（指定キュー） | 失敗・キャンセル時も reader が呼ばれ `error` が非 nil | macOS 10.12。**async throws 版は存在しない**（`reader` は複数回呼ばれうるため。コンパイル検証済み） |

> **`NSFilePromiseProviderDelegate` には `pasteboardFinishedWithDataProvider(_:)`（L-03）に相当する完了通知が存在しない。** そのため provider / delegate の解放タイミングを API から知る手段がなく、解放判断はアプリ側が `changeCount`（M-01）による所有権喪失検出で行う必要がある。詳細は RK-21。

### G. レガシー / 参考（全網羅の担保）

| ID | API 名 | 目的 | 状態 |
|---|---|---|---|
| G-01 | `NSPasteboard(byFilteringFile:)` / `(byFilteringData:ofType:)` / `(byFilteringTypesIn:)` | Filter Services による型変換 | 現行 SDK で非推奨マークなし。ただし Filter Services 自体がレガシー機構。新規採用しない |
| G-02 | `writeFileContents(_:)` / `readFileContentsType(_:toFile:)` | ファイル内容の直接受け渡し | UTI + `.fileURL` で代替可能。ヘッダに「now replaces this functionality」の記載 |
| G-03 | `write(_:)`（`writeFileWrapper:`）/ `readFileWrapper()` | `NSFileWrapper` の受け渡し | 同上 |
| G-04 | `NSFileContentsPboardType` / `NSCreateFilenamePboardType` / `NSCreateFileContentsPboardType` / `NSGetFileType` / `NSGetFileTypes` | 旧ファイル型ヘルパ | レガシー。採用しない |
| G-05 | `NSPasteboard.Name.font` / `.ruler` / `.find` | フォント・ルーラ・検索文字列の連携 | 本機能の対象外（`NSTextView` 固有） |
| G-06 | 廃止済み型定数（macOS 10.14 で廃止） | `NSStringPboardType` / `NSFilenamesPboardType` / `NSTIFFPboardType` / `NSRTFPboardType` / `NSRTFDPboardType` / `NSHTMLPboardType` / `NSTabularTextPboardType` / `NSFontPboardType` / `NSRulerPboardType` / `NSColorPboardType` / `NSURLPboardType` / `NSPDFPboardType` / `NSMultipleTextSelectionPboardType` / `NSPostScriptPboardType` / `NSVCardPboardType` / `NSInkTextPboardType` / `NSFilesPromisePboardType` / `NSPasteboardTypeFindPanelSearchOptions` | すべて `NSPasteboardType*` へ置換。**採用禁止** |
| G-07 | 廃止済み名前定数（macOS 10.13 で廃止） | `NSGeneralPboard` / `NSFontPboard` / `NSRulerPboard` / `NSFindPboard` / `NSDragPboard` | `NSPasteboard.Name.*` へ置換。**採用禁止** |
| G-08 | `NSPICTPboardType` | PICT 画像型 | macOS 10.6 で廃止。**採用禁止** |
| G-09 | `NSObject(NSPasteboardOwner)` の `pasteboard(_:provideDataForType:)` / `pasteboardChangedOwner(_:)` | informal protocol 版 | macOS 11.0 で廃止。`NSPasteboardTypeOwner`（L-06 / L-07）を使う |

---

## 7. 同期・非同期 API 分類表（全サブ機能）

第 6 章の全 ID を網羅する（7.1 の分類対象外を除く）。

| ID | サブ機能 / 操作 | システム API | 実行方式 | 完了方式 | 完了スレッド・actor | キャンセル手段 | リソース所有権・寿命 |
|---|---|---|---|---|---|---|---|
| P-01 | 汎用取得 | `NSPasteboard.general` | 同期 | 戻り値 | 呼び出しスレッド（MainActor 隔離なし。検証済み） | なし | シングルトン。解放不可 |
| P-02 | 名前付き取得 | `NSPasteboard(name:)` | 同期 | 戻り値 | 同上 | なし | ペーストボードサーバに常駐。アプリ終了で消えない |
| P-03 | 一意名生成 | `withUniqueName()` | 同期 | 戻り値 | 同上 | なし | アプリ寿命と無関係。P-04 必須 |
| P-04 | 解放 | `releaseGlobally()` | 同期（`oneway`） | なし | 同上 | なし | 以後どのアプリからも使用不可。標準ペーストボードには呼ばない |
| P-05 | 名前照会 | `name` | 同期 | 戻り値 | 同上 | なし | - |
| C-01 | 所有権取得（消去） | `clearContents()` | 同期 | 戻り値（`changeCount`） | 同上 | なし | 呼び出し側が所有者になる。`currentHostOnly` を解除 |
| C-02 | 所有権取得（オプション付き） | `prepareForNewContents(with:)` | 同期 | 戻り値（`changeCount`） | 同上 | なし | オプションは次の C-01 / C-02 まで持続 |
| C-03 | オブジェクト書き込み | `writeObjects(_:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 書き込んだ `NSPasteboardItem` は当該ペーストボードに束縛される |
| C-04 | 文字列書き込み | `setString(_:forType:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 先頭アイテムのみ対象 |
| C-05 | バイナリ書き込み | `setData(_:forType:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 同上 |
| C-06 | plist 書き込み | `setPropertyList(_:forType:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 同上 |
| C-07 | アイテム生成 | `NSPasteboardItem()` | 同期 | 戻り値 | 同上 | なし | 所有者変更まで有効。書き込み後の再利用は例外 |
| C-08 | アイテム文字列設定 | `NSPasteboardItem.setString(_:forType:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 同上 |
| C-09 | アイテムバイナリ設定 | `NSPasteboardItem.setData(_:forType:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 同上 |
| C-10 | アイテム plist 設定 | `NSPasteboardItem.setPropertyList(_:forType:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 同上 |
| C-12 | 書き込み型申告 | `NSPasteboardWriting.writableTypes(forPasteboard:)` | callback | 戻り値 | システムからの呼び出し。スレッド不定（**V-4**） | なし | 実装オブジェクトは C-03 の間だけシステムに保持される（**V-3**） |
| C-13 | 書き込み方式申告 | `NSPasteboardWriting.writingOptions(forType:pasteboard:)` | callback | 戻り値 | 同上 | なし | 同上 |
| C-14 | 書き込みデータ供給 | `NSPasteboardWriting.pasteboardPropertyList(forType:)` | callback（`.promised` 時は要求駆動） | 戻り値 | 同上 | なし | `.promised` 指定時は所有権喪失まで実装オブジェクトが必要 |
| L-01 | 遅延提供の登録 | `setDataProvider(_:forTypes:)` | 同期 | 戻り値（`Bool`） | 呼び出しスレッド | なし | provider は呼び出し側が強参照する（**V-3**） |
| L-02 | 遅延提供の実行 | `pasteboard(_:item:provideDataForType:)` | callback（要求駆動） | delegate 呼び出し | スレッド不定（**V-4**）。Swift では `nonisolated` | なし | L-03 の到達で解放可能 |
| L-03 | 遅延提供の終了通知 | `pasteboardFinishedWithDataProvider(_:)` | callback | delegate 呼び出し | 同上 | なし | **解放点として利用できる唯一の公式通知**（F 群には存在しない） |
| L-04 | 型宣言（レガシー） | `declareTypes(_:owner:)` | 同期 | 戻り値（`changeCount`） | 呼び出しスレッド | なし | owner は所有権喪失まで必要 |
| L-05 | 型追加（レガシー） | `addTypes(_:owner:)` | 同期 | 戻り値（`changeCount`） | 同上 | なし | 同上 |
| L-06 | データ供給（レガシー） | `NSPasteboardTypeOwner.pasteboard(_:provideDataForType:)` | callback（要求駆動） | delegate 呼び出し | スレッド不定（**V-4**） | なし | L-07 の到達で解放可能 |
| L-07 | 所有権喪失通知（レガシー） | `pasteboardChangedOwner(_:)` | callback | delegate 呼び出し | 同上 | なし | 解放点 |
| R-01 | オブジェクト読み取り | `readObjects(forClasses:options:)` | 同期 | 戻り値（`[Any]?`） | 呼び出しスレッド | なし | 返却オブジェクトは呼び出し側所有 |
| R-04 | 文字列読み取り | `string(forType:)` | 同期 | 戻り値 | 同上 | なし | 同上。複数アイテムは改行連結 |
| R-05 | バイナリ読み取り | `data(forType:)` | 同期 | 戻り値 | 同上 | なし | 同上 |
| R-06 | plist 読み取り | `propertyList(forType:)` | 同期 | 戻り値 | 同上 | なし | 同上 |
| R-07 | アイテム取得 | `pasteboardItems` | 同期 | 戻り値 | 同上 | なし | 所有者変更で無効化（以後 nil を返す） |
| R-08 | インデックス取得 | `index(of:)` | 同期 | 戻り値 | 同上 | なし | 未所属は `NSNotFound` |
| R-09 | アイテム型別取得 | `NSPasteboardItem.string/data/propertyList(forType:)` | 同期 | 戻り値 | 同上 | なし | 所有者変更で無効化 |
| R-10 | 読み取り型申告 | `NSPasteboardReading.readableTypes(forPasteboard:)` | callback（static） | 戻り値 | システムからの呼び出し。スレッド不定（**V-4**） | なし | 型メソッドのためインスタンス寿命なし |
| R-11 | 読み取り方式申告 | `NSPasteboardReading.readingOptions(forType:pasteboard:)` | callback（static） | 戻り値 | 同上 | なし | 同上 |
| R-12 | インスタンス生成 | `NSPasteboardReading.init?(pasteboardPropertyList:ofType:)` | callback | 戻り値 | 同上 | なし | 生成物は R-01 の呼び出し側所有 |
| Q-01 | 型一覧 | `types` | 同期 | 戻り値 | 呼び出しスレッド | なし | - |
| Q-02 | 合致型 | `availableType(from:)` | 同期 | 戻り値 | 同上 | なし | - |
| Q-03 | UTI 適合判定 | `canReadItem(withDataConformingToTypes:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | アラート非発生は未保証（**V-1**） |
| Q-04 | クラス生成可否 | `canReadObject(forClasses:options:)` | 同期 | 戻り値（`Bool`） | 同上 | なし | 同上 |
| Q-05 | アイテム型一覧 | `NSPasteboardItem.types` | 同期 | 戻り値 | 同上 | なし | 所有者変更で無効化 |
| Q-06 | アイテム合致型 | `NSPasteboardItem.availableType(from:)` | 同期 | 戻り値 | 同上 | なし | 同上 |
| Q-07 | 変換可能型 | `NSPasteboard.types(filterableTo:)` | 同期 | 戻り値 | 同上 | なし | - |
| M-01 | 変更監視 | `changeCount`（ポーリング） | 同期 | 戻り値 | 呼び出しスレッド。`Timer` 併用時は MainActor 推奨 | タイマ停止（`invalidate()`） | 通知 API なし |
| D-01 | パターン判定 | `detectedPatterns(for:)` | **async throws** | Swift Concurrency（`await`） | 呼び出し元のアクター文脈で再開（`nonisolated async`。MainActor から呼べば MainActor に戻る） | Task キャンセル対応は **V-5** | 戻り値は値型 `Set` |
| D-02 | 値取得 | `detectedValues(for:)` | **async throws** | 同上 | 同上 | 同上 | 戻り値は値型 `DetectedValues` |
| D-03 | メタデータ取得 | `detectedMetadata(for:)` | **async throws** | 同上 | 同上 | 同上 | 戻り値は値型 `DetectedMetadata` |
| D-04 | アイテム単位パターン判定 | `NSPasteboardItem.detectedPatterns(for:)` | **async throws** | 同上 | 同上 | 同上 | アイテムは非 Sendable。同一隔離内で扱う |
| D-05 | アイテム単位値取得 | `NSPasteboardItem.detectedValues(for:)` | **async throws** | 同上 | 同上 | 同上 | 同上 |
| D-06 | アイテム単位メタデータ取得 | `NSPasteboardItem.detectedMetadata(for:)` | **async throws** | 同上 | 同上 | 同上 | 同上 |
| D-07 | 設定照会 | `accessBehavior` | 同期 | 戻り値 | 呼び出しスレッド | なし | - |
| D-11 | ObjC 版検出（参考） | `detectPatternsForPatterns:completionHandler:` 他 | callback | completion block | **V-4**。公式文書に記載なし | なし | Swift からは不可視 |
| U-01 | 貼り付けボタン（Transferable） | `PasteButton(payloadType:onPaste:)` | callback | クロージャ | MainActor | View の破棄 | - |
| U-02 | 貼り付けボタン（UTType） | `PasteButton(supportedContentTypes:payloadAction:)` | callback | クロージャ | MainActor | 同上 | `NSItemProvider` は呼び出し側所有 |
| U-03 | 貼り付けボタン（検証付き） | `PasteButton(supportedContentTypes:validator:payloadAction:)` | callback | クロージャ | MainActor | 同上 | 非推奨 |
| U-04 | 貼り付けボタン（文字列型） | `PasteButton(supportedTypes:...)` | callback | クロージャ | MainActor | 同上 | 非推奨 |
| U-05 | Copy メニュー | `View.copyable(_:)` | callback | `@autoclosure` 評価 | MainActor | View の破棄 | - |
| U-06 | Cut メニュー | `View.cuttable(for:action:)` | callback | クロージャ | MainActor | 同上 | - |
| U-07 | Paste メニュー | `View.pasteDestination(for:action:validator:)` | callback | クロージャ | MainActor | 同上 | - |
| U-08 | responder chain 貼り付け | `paste:` action（`NSText.paste(_:)` / `@objc paste(_:)`） | callback | メソッド呼び出し | MainActor | なし | - |
| U-09 | Services 読み取り | `readSelection(from:)` | callback | 戻り値（`Bool`） | 実質 MainActor（要件は `nonisolated`。**Swift 6 では適合隔離が必要**） | なし | - |
| U-10 | Services 書き出し | `writeSelection(to:types:)` | callback | 戻り値（`Bool`） | 同上 | なし | - |
| F-01 | 約束提供者の生成 | `NSFilePromiseProvider(fileType:delegate:)` | 同期 | 戻り値 | 呼び出しスレッド | なし | **provider は C-03 で書き込んだ後もアプリ側が強参照する必要がある**（RK-21） |
| F-02 | 提供 UTI | `fileType` | 同期 | 戻り値 | 同上 | なし | - |
| F-03 | delegate 参照 | `delegate` | 同期 | 戻り値 | 同上 | なし | **`weak`。アプリ側が強参照しないと約束履行前に解放される**（RK-21 / **V-11**） |
| F-04 | 付帯情報 | `userInfo` | 同期 | 戻り値 | 同上 | なし | 呼び出し側所有 |
| F-05 | ファイル名決定 | `filePromiseProvider(_:fileNameForType:)` | callback | 戻り値 | **MainActor**（`NS_SWIFT_UI_ACTOR`） | なし | この時点では書き出さない |
| F-06 | データ書き出し | `filePromiseProvider(_:writePromiseTo:completionHandler:)` / Swift 版 `filePromiseProvider(_:writePromiseTo:)` | callback → completion **または async throws**（Swift refined。どちらか一方を実装） | completion block / `await` の復帰または throw | F-07 が返す `OperationQueue`（未実装時は `.main`）。要件は `nonisolated` | なし（失敗を error / throw で返す） | 書き出し先 URL はシステム指定。必ず引数の URL を使う。**1 回の書き出し要求につき completion をちょうど 1 回**（要求が複数回来れば都度呼ぶ） |
| F-07 | 書き出しキュー指定 | `operationQueue(for:)` | callback | 戻り値 | **MainActor**（`NS_SWIFT_UI_ACTOR`） | なし | キューは呼び出し側所有 |
| F-08 | 受領可能型 | `NSFilePromiseReceiver.readableDraggedTypes` | 同期 | 戻り値 | 呼び出しスレッド | なし | - |
| F-09 | 約束情報 | `fileTypes` / `fileNames` | 同期 | 戻り値 | 同上 | なし | `fileNames` は F-10 実行後に確定 |
| F-10 | 約束の受領 | `receivePromisedFiles(atDestination:options:operationQueue:reader:)` | callback | reader block | 引数の `OperationQueue` | なし（キャンセル時も reader が error 付きで呼ばれる） | 受領先ディレクトリは呼び出し側所有 |
| G-01 | Filter Services | `NSPasteboard(byFilteringFile:)` 他 | 同期 | 戻り値 | 呼び出しスレッド | なし | 生成されたペーストボードの解放責務は不明瞭。新規採用しない |
| G-02 | ファイル内容受け渡し | `writeFileContents(_:)` / `readFileContentsType(_:toFile:)` | 同期 | 戻り値 | 同上 | なし | レガシー |
| G-03 | FileWrapper 受け渡し | `write(_:)` / `readFileWrapper()` | 同期 | 戻り値 | 同上 | なし | レガシー |

**アプリが呼び出す非同期 API は macOS 15.4+ の検出 API（D-01〜D-06）のみ。** それ以外の `NSPasteboard` API はすべて同期であり、ペーストボードサーバへの同期 IPC としてブロックする。

ただし**アプリが実装する側**には、もう 1 つ非同期形がある。F-06 は ObjC の `completionHandler:` 形に加えて Swift では `async throws` 形（`filePromiseProvider(_:writePromiseTo:)`）としても import され、どちらか一方を実装すれば適合する（`async throws` 版のみを実装した適合をコンパイルで確認済み）。一方 F-10 の `reader` は completion handler 命名規約に合致せず、`async throws` 版は生成されない（同じくコンパイルで確認済み）。

### 7.1 分類対象外の ID（定数・値型・列挙）

実行方式を持たないため分類表に行を持たない。**これら以外の全 ID は上表に存在する。**

`P-06` / `C-11` / `C-15` / `H-01` / `R-02` / `R-03` / `R-13` / `D-08` / `D-09` / `D-10` / `G-04` / `G-05` / `G-06` / `G-07` / `G-08` / `G-09`

---

## 8. iOS 公開 API パリティ表

iOS 版 `IosClipboardManager`（`ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift`）の公開操作 P-1〜P-16 に対する macOS の対応状況。macOS 側の公開シグネチャ決定は設計工程に委ねる。

| iOS 操作 | iOS の system API | macOS 対応 | macOS の system API（第 6 章 ID） | 備考 |
|---|---|---|---|---|
| P-1 `copy(_:options:scope:)` | `UIPasteboard.setItems(_:options:)` | 対応 | C-01 / C-02 / C-03 | `options.localOnly` は C-02 + H-01 へ写像。`options.expirationDate` は**非対応**（RK-04） |
| P-2 `append(_:scope:)` | `UIPasteboard.addItems(_:)` | **自所有時のみ対応**（V-13a / V-13b で確定） | C-03 | **自分が C-01 / C-02 で所有権を取得している間は追記が成立する**（15.4.1 実測: items 1→2、`changeCount` 不変で所有権維持）。一方**他アプリが所有者の場合は `writeObjects(_:)` が `false` を返し、`changeCount` も items も types も変化しない**（26.3 / 15.4.1 の両方で確認）。iOS の `addItems` は所有者を問わないため、契約は macOS の方が狭い。他アプリ所有時にエミュレートするには R-01 で全アイテムを読み、C-01 で所有権を取得して旧新まとめて書き直すしかないが、(1) `changeCount` が進む (2) 内容読み取りがアラート要因になる (3) 遅延提供アイテムを再現できない、と契約が大きく異なる。RK-23 |
| P-3 `read(scope:)` | `UIPasteboard.string` / `.urls` / `.image` 等 | 対応 | R-01 / R-04 | `readObjects(forClasses:)` で NSString / NSURL / NSImage / NSColor / NSAttributedString を一括取得 |
| P-4 `readData(utType:scope:)` | `UIPasteboard.data(forPasteboardType:)` | 対応 | R-05 / R-09 | - |
| P-5 `snapshot(matchingTypes:scope:)` | `UIPasteboard.items` / `.types` | 対応 | R-07 / Q-01 / Q-05 | アイテム単位の型一覧を `pasteboardItems` から構成 |
| P-6 `clear(scope:)` | `UIPasteboard.items = []` | 対応 | C-01 | 戻り値が `changeCount` になる点が iOS と異なる |
| P-7 `createPasteboard(_:)` | `UIPasteboard(name:create:)` / `withUniqueName()` | 対応（寿命が異なる） | P-02 / P-03 | iOS は「アプリ終了まで」、macOS は**アプリ終了後も残る**（RK-06） |
| P-8 `removePasteboard(_:)` | `UIPasteboard.remove(withName:)` | 対応 | P-04 | macOS は `releaseGlobally()`。標準ペーストボードへの誤適用が致命的（RK-07） |
| P-9 `detectPatterns(_:scope:)` | `UIPasteboard.detectPatterns(for:)` | **条件付き対応** | D-01 / D-04 | **macOS 15.4+**。15.0–15.3 は非対応（RK-01） |
| P-10 `detectValues(_:scope:)` | `UIPasteboard.detectValues(for:)` | **条件付き対応** | D-02 / D-05 | 同上。通知が発生する点も iOS と同じ |
| P-11 `loadItem(_:scope:)` | `NSItemProvider.loadDataRepresentation` 等 | **代替あり** | R-01 / R-05 / F-10 | macOS には `UIPasteboard.itemProviders` に相当する経路がなく、`readObjects` は同期。非同期ロードが必要なのは File Promise（F-10）のみ。iOS の「非同期ロード + キャンセルトークン」契約は macOS では**同期読み取り + File Promise 受領**に分解される |
| P-12 `cancelAllLoads()` | `Progress.cancel()` | **非対応** | — | macOS の同期読み取りにキャンセル概念がない。File Promise（F-10）にもキャンセル API がない。公開 API では no-op か、そもそも公開しない |
| P-13 `startObserving(scope:onEvent:)` | `UIPasteboard.changedNotification` | **代替あり（挙動差大）** | M-01 | macOS に通知 API がないためポーリング実装になる（RK-11）。イベント種別（changed / removed）の区別も不可 |
| P-14 `stopObserving()` | `NotificationCenter.removeObserver` | 対応 | M-01 | タイマ停止 |
| P-15 `checkForegroundChange(scope:)` | `UIPasteboard.changeCount` 比較 | 対応 | M-01 | macOS でも `changeCount` 比較で同等 |
| P-16 `makePasteControl(...)` | `UIPasteControl` | **代替あり** | U-01〜U-07 | macOS に `UIPasteControl` はない。SwiftUI `PasteButton`（U-01）が最も近い。Edit メニュー連携が必要なら U-05〜U-07。**AppKit ネイティブの貼り付けボタンは存在しない** |

### 8.1 iOS にあって macOS にない機能

| 項目 | iOS | macOS | 影響 |
|---|---|---|---|
| 有効期限 | `UIPasteboard.OptionsKey.expirationDate` | **なし** | RK-04 |
| 変更通知 | `changedNotification` / `removedNotification` | **なし**（ポーリングのみ） | RK-11 |
| 非同期アイテムロード | `itemProviders` + `NSItemProvider` + `Progress` キャンセル | **なし**（同期読み取り） | P-11 / P-12 |
| ネイティブ貼り付けコントロール | `UIPasteControl`（UIKit） | **なし**（SwiftUI `PasteButton` のみ） | P-16 |
| 追記（append） | `UIPasteboard.addItems(_:)`（所有者を問わない） | **自所有時のみ成立**（V-13b 実測）。他アプリ所有時は `false` で不可（V-13a 実測） | RK-23 |

### 8.2 macOS にあって iOS にない機能

| 項目 | macOS | iOS |
|---|---|---|
| ファイル約束 | `NSFilePromiseProvider` / `NSFilePromiseReceiver`（F 群） | なし |
| 遅延データ提供の終了通知 | `pasteboardFinishedWithDataProvider(_:)`（L-03） | なし |
| Edit メニュー連携 | `copyable` / `cuttable` / `pasteDestination`（U-05〜U-07） | なし（macOS 専用 API） |
| アクセス設定の照会 | `accessBehavior`（D-07） | なし |
| Services 連携 | `NSServicesMenuRequestor`（U-09 / U-10） | なし |

---

## 9. 実装リスク（権限・制約・互換性）

| ID | 種別 | 内容 | 影響 | 対応方針 |
|---|---|---|---|---|
| RK-01 | 互換性 / プライバシー | `mac/MacLibrary` の `MACOSX_DEPLOYMENT_TARGET` は 15.0 / 15.1 だが、検出 API（D-01〜D-06）と `accessBehavior`（D-07）は **macOS 15.4+**。15.0–15.3 には**通知を発生させずに内容種別を判定する公式手段が存在しない** | 15.0–15.3 で「通知なしの事前判定」を提供できない | `if #available(macOS 15.4, *)` で分岐する。15.0–15.3 では Q-03 / Q-04 を**型判定の最適化としてのみ**使い、公開 API の契約では「通知が発生しない」ことを**保証しない**。公開 API に「検出未対応」を表す明示的な結果を用意する。**Q 群をフォールバックとして正式採用するかは V-1 の結果が出るまで保留とする** |
| RK-02 | プライバシー | macOS 15（Sequoia）以降、プログラムからの汎用ペーストボード読み取りはユーザーへのアラート対象。`accessBehavior` による状態照会は 15.4+ | 15.0–15.3 では自アプリの許可状態を判定できない。アラートの発生自体は避けられない | 通知回避が契約上必要な操作は、D-01 / D-03（15.4+）または U 群のユーザー起点 UI 経路へ限定する。プログラム読み取り（R 群）は「アラートが出うる操作」として公開 API のドキュメントに明記する。15.4 未満は「許可状態不明」として扱う |
| RK-03 | プライバシー | `detectedValues(for:)`（D-02）は一致時に**ユーザー通知が発生し、拒否されると throw する**（ヘッダに明記） | 「通知なしの内容取得」はできない | 通知を避ける用途では D-01 / D-03 のみを使う。D-02 はユーザー操作起点でのみ呼ぶ |
| RK-04 | 機能欠落 | iOS の `expirationDate` に相当する API が macOS に**存在しない**（第 8.1 章） | クリップボード内容の自動失効ができない | 公開 API で `expirationDate` 相当を受け付けない、または「macOS では無視される」ことを DocC に明記。自前タイマで消去する代替は、他アプリが所有者になった後の誤消去を避けるため **`changeCount`（M-01）が自分の取得値と一致する場合のみ** `clearContents()` を呼ぶ |
| RK-05 | 仕様差異 | `clearContents()`（C-01）は C-02 で設定した `currentHostOnly`（H-01）を**解除する**（ヘッダに明記） | 「ローカル限定でコピー」を意図した実装が Universal Clipboard に流出する | ローカル限定コピーでは C-01 を呼ばず、必ず C-02 を先頭手順にする。Repository 層で所有権取得を 1 経路に集約する |
| RK-06 | 寿命 | 名前付き / 一意名ペーストボード（P-02 / P-03）は**アプリ終了後もペーストボードサーバに残る**（公式文書「lifetime ... is not related to the lifetime of the creating app」） | 機密データが終了後も他アプリから読める。iOS 版で検出済みの M-08 と同種の露出が macOS では**仕様として発生する** | 一意名ペーストボードは使用後に必ず P-04 を呼ぶ（`defer` で保証）。機密データは名前付きペーストボードに置かない。DocC の契約文で「終了後も残存しうる」ことを明記する |
| RK-07 | 寿命 | `releaseGlobally()`（P-04）を標準ペーストボードに呼ぶと「no other application can use the receiver」となる | システム全体のクリップボードを破壊しうる | Repository 層で `general` および標準名に対する P-04 を**呼べない構造**にする（一意名生成経路のみが解放責務を持つ） |
| RK-08 | 並行性 | `NSPasteboard` / `NSPasteboardItem` は **非 Sendable**（`@_nonSendable(_assumed)`。コンパイラで確認済み）。ただし MainActor 隔離でもない | Swift 6 でアクター境界を越えて渡すとコンパイルエラー。`nonisolated(unsafe)` で回避するとデータ競合 | ペーストボードインスタンスを保持して受け渡さず、使用箇所ごとに P-01 で取得する。Repository を `@MainActor` に固定するか、専用のシリアル実行文脈に閉じる |
| RK-09 | 並行性 | `NSServicesMenuRequestor`（U-09 / U-10）の要件は `nonisolated`。`NSView`（MainActor）で適合すると Swift 6 で `ConformanceIsolation` エラー（実測） | ビルド不能 | 適合を `@MainActor` で隔離する（`final class V: NSView, @MainActor NSServicesMenuRequestor`）。または要件実装を `nonisolated` にする |
| RK-10 | 並行性 | `changeCount`（M-01）ポーリングに `Timer` を使うと、Swift 6 でクロージャが `@Sendable` 扱いになり非 Sendable な self を捕捉できない（実測） | ビルド不能 | 監視クラスを `@MainActor` にし、`MainActor.assumeIsolated { }` で本体を包む。コールバックも `@MainActor` クロージャとして受け取る |
| RK-11 | 監視 | macOS には `changedNotification` に相当する通知が**存在しない**（ヘッダ全文検索で該当なし） | 変更検知は必ずポーリングになる。間隔を詰めると電力・CPU コスト、空けると取りこぼし。イベント種別の区別も不可 | 既定 0.5 秒程度のポーリングとし、間隔を設定可能にする。アプリ非アクティブ時は停止し、`applicationDidBecomeActive` で 1 回だけ照合する（iOS 版 P-15 に相当） |
| RK-12 | サンドボックス | `MacLibraryExample` は App Sandbox 有効。ペーストボードから取得した `fileURL` に対しサンドボックス例外が自動付与されるかは公式文書に記載がない | ファイル URL をペーストしても読み込めない可能性 | **V-6 で検証**。読み込み失敗を握り潰さず明示エラーとして返す |
| RK-13 | API 誤用 | `writeObjects(_:)`（C-03）は既存アイテムを消さず**追加**する。`declareTypes(_:owner:)`（L-04）との併用はヘッダで非推奨とされる | 意図しないアイテム重複、所有権の取り違え | コピー処理を「所有権取得（C-01 / C-02）→ C-03 のみ」に固定し、L-04 経路は遅延提供のレガシー用途以外で使わない |
| RK-14 | API 誤用 | 既にペーストボードに束縛済みの `NSPasteboardItem` を再度 C-03 に渡すと**例外が送出される**（ヘッダに明記） | クラッシュ | `NSPasteboardItem` を再利用せず、書き込みのたびに生成する。読み取りで得たアイテムを書き込みに回さない |
| RK-15 | 読み取り仕様 | R-04 / R-05 は「全アイテムの最良表現」であり、テキスト系では複数アイテムが改行連結される | 複数アイテムのコピー内容を 1 件と誤認する | 件数が意味を持つ経路では R-07 を使い、R-04 は単一値取得の簡易経路に限定する |
| RK-16 | UI | SwiftUI `PasteButton` は macOS ではペーストボード変更に応じた自動 validate / invalidate を行わない（公式文書に明記） | ボタンが常時有効に見え、押下しても何も起きないことがある | 有効／無効の表示制御を自前で行う場合は Q-04 を用い、ポーリング（RK-11）と連動させる |
| RK-17 | 遅延提供 | `NSPasteboardItem` は「所有者が変わるまでのみ有効」。data provider は要求されるまで呼ばれない | provider が先に解放されるとデータが供給されない | provider をリポジトリ層で強参照し、L-03 の到達で解放する。システム側の保持有無は **V-3** |
| RK-18 | 型指定 | `NSPasteboardItem` は「有効な UTI 文字列」のみ受け付け、非 UTI を渡すと呼び出しが失敗する（ヘッダに明記） | サイレントな `false` 返却 | カスタム型は `UTType(exportedAs:)` で宣言し、Info.plist に `UTExportedTypeDeclarations` を追加する。UTI 検証を Data 層に置く |
| RK-19 | レガシー | macOS 10.13 / 10.14 で廃止された定数群（G-06 / G-07）が SDK に残存 | 補完候補から誤って選択されうる | Lint / レビュー観点として「`NSPasteboardType*` / `NSPasteboard.Name.*` のみ使用」を明文化する |
| RK-20 | 性能 | すべての `NSPasteboard` 同期 API はペーストボードサーバへの IPC。大きな画像・ファイルデータで顕著にブロックする | MainActor で実行するとフリーズ | 大容量データの読み書きは遅延提供（L 群）または File Promise（F 群）に寄せる。同期 API を MainActor 外で呼ぶ場合は RK-08 の隔離方針に従う |
| **RK-21** | **寿命（V-11 で確定）** | **`NSFilePromiseProvider.delegate`（F-03）は `weak`。かつ `NSFilePromiseProviderDelegate` には L-03 に相当する完了通知が存在しない。2026-08-29 の実測で、C-03 後にローカル変数のスコープを抜けると `provider retained by system? true` / `delegate retained by system? false`、delegate の `deinit` が即座に発火することを確認した** | **想定より悪い。provider はシステムが保持するため、他アプリからは「約束されたファイルがペーストボード上に存在する」ように見えるまま、delegate が nil なので F-05 / F-06 が呼ばれず永久に履行できない。プロセスをまたいだ無言の失敗になり、受け手側は原因を特定できない** | **provider と delegate の双方を強参照するセッション型を設けることが必須（推測ではなく実測に基づく確定事項）。ペーストボードの所有権を保持している間は生存させる。解放判断は M-01 の `changeCount` が取得時の値と異なることで行う（所有権喪失＝約束不要）。F-06 の `completionHandler` は **1 回の書き出し要求につきちょうど 1 回**呼ぶ実装契約とする。書き出し要求は複数回来うるため、provider 全体で 1 回に絞るガードは置かない（2 回目以降の要求で completion が呼ばれず、受け手が待ち続ける）** |

| **RK-22** | **検証手段（新設）** | **Sequoia のペーストボードアクセスアラートを、試した全構成で一度も再現できなかった（2026-08-29 実測）。試した構成: macOS 26.3 実機 / macOS 15.4.1 VM、ad-hoc 署名 / Apple Development 署名、App Sandbox 有効、クリック起点の読み取り / タイマーによる無人バックグラウンド読み取り、別プロセス（`pbcopy`）が所有するペーストボード。いずれも `readObjects` が 10 ミリ秒未満で成功し、アラートも `accessBehavior` の遷移も発生しない。また新規バンドル ID が両 OS で `accessBehavior == alwaysAllow` を返し、NSPasteboard.h の「一度もアラートを出していないアプリは `.default` を返す」という記述と一致しない** | **アラート挙動を検証する手段が確立できていない。開発機でも VM でも「アラートが出ない」ため、実装が制限に触れているかを確認できず、V-1 / V-2 / V-12 の判定ができない。正の対照が成立していないので、「アラートが出なかった」という観測を「その API は安全」の根拠に使ってはならない。サンプルアプリの QA、マニュアルの手動確認手順、CI の対象 OS 選定すべてが「アラートを再現できない環境」で行われることになる** | **どの読み取り経路についても「通知なし」を保証しない前提で設計する（RK-01 / RK-02 の保守的な記述を維持する）。「開発機でアラートが出なかった」をプライバシー関連 DoD の根拠にしない。アラート挙動の確認が本当に必要になった時点で、実機の macOS 15.x を別途調達して検証手段の確立からやり直す。なおアラートが出る前提で設計している限り、再現できてもできなくても設計は変わらないため、優先度は低い** |
| **RK-23** | **契約差（V-13a / V-13b で確定）** | **`writeObjects(_:)`（C-03）による追記は所有権に依存する。自分が所有者である間は成立する（15.4.1 実測: items 1→2、`changeCount` 不変）が、他アプリが所有者の場合は `false` を返し何も変化しない（26.3 / 15.4.1 の両方で確認）。iOS の `UIPasteboard.addItems(_:)` は所有者を問わないため、契約が一致しない** | **`append` を iOS と同じ契約では提供できない。「直前に自分がコピーした内容に足す」ことはできるが、「他アプリがコピーした内容に足す」ことはできない。呼び出し側が後者を期待すると、エラーにもならず黙って何も起きない（`writeObjects` の戻り値を見なければ失敗に気づけない）** | **`append` を提供する場合、契約を「自分が所有権を保持している間のみ有効」と明示し、所有権を失っている場合は成功したように見せず明示的なエラーを返す。所有権の判定は C-01 / C-02 が返した `changeCount` と M-01 の現在値の一致で行う。他アプリ所有時のエミュレーション（読み取り＋所有権取得＋再書き込み）は、(1) `changeCount` が進み変更監視が発火する (2) 内容読み取りがアラート要因になる (3) 他アプリの遅延提供アイテムは再現できず失われる、の 3 点で契約が別物になるため、採用するなら別名の API にする** |

---

## 10. 簡単なサンプルコード集（サブ機能別）

> すべて `xcrun swiftc -swift-version 6 -typecheck -target arm64-apple-macos15.4` で**コンパイル検証済み**（エラー・警告なし）。
> これは **型検査の範囲のみ**を保証する。プライバシーアラートの発生有無、遅延コールバックの実効寿命、Universal Clipboard の抑止、サンドボックス下のファイル URL 権限といった**実行時契約は保証しない**。実行時の確認は第 11 章の V-1〜V-13 および RK-21 の delegate 寿命テストで行う。

### P. ペーストボード取得・寿命管理

```swift
import AppKit

func acquirePasteboards() {
    let general = NSPasteboard.general
    _ = general.name                                   // .general

    // 名前付き: ペーストボードサーバに常駐し、アプリ終了後も残る（RK-06）
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
        let item = NSPasteboardItem()                   // 再利用禁止。毎回生成する（RK-14）
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

    // F 群と違い、こちらには完了通知がある。ここが解放点になる
    func pasteboardFinishedWithDataProvider(_ pasteboard: NSPasteboard) {}
}

func copyPromised(provider: LazyProvider) {
    let pb = NSPasteboard.general
    pb.clearContents()
    let item = NSPasteboardItem()
    _ = item.setDataProvider(provider, forTypes: [.pdf, .tiff])
    _ = pb.writeObjects([item])                          // provider は呼び出し側が強参照する（RK-17）
}
```

### L. 遅延データ提供（レガシー: NSPasteboardTypeOwner）

```swift
import AppKit

final class LegacyOwner: NSObject, NSPasteboardTypeOwner {
    func pasteboard(_ sender: NSPasteboard, provideDataForType type: NSPasteboard.PasteboardType) {
        if type == .string { sender.setString("late", forType: .string) }
    }
    func pasteboardChangedOwner(_ sender: NSPasteboard) {}   // 所有権喪失＝解放点
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
    // clearContents() ではなくこちらを使う。clearContents() はオプションを解除する（RK-05）
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
    _ = pb.string(forType: .string)                      // 全アイテムの最良表現（改行連結あり。RK-15）
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

### Q. 内容確認 / 型判定（データ本体を読まない）

```swift
import AppKit
import UniformTypeIdentifiers

// 注意: これらがアクセスアラートを発生させない保証はない（V-1）。
// 「通知なしで判定できる」契約には使わず、型判定の最適化に限定する。
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
        // 通知あり: 一致時に内容を取得する。拒否されると throw する（RK-03）
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
            MainActor.assumeIsolated {                    // Swift 6 の @Sendable 制約回避（RK-10）
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

### U. 貼り付けボタン（SwiftUI PasteButton）

```swift
import SwiftUI
import AppKit

@available(macOS 13.0, *)                                // payloadType:onPaste: は macOS 13.0
struct PasteDemo: View {
    @State private var pasted: String = ""
    var body: some View {
        HStack {
            // macOS では変更に応じた自動 validate / invalidate は行われない（RK-16）
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

### U. Edit メニュー連携（copyable / cuttable / pasteDestination。macOS 専用）

```swift
import SwiftUI

@available(macOS 13.0, *)                                // いずれも macOS 13.0+ / macOS 専用
struct EditMenuClipboardDemo: View {
    @State private var text = "hello"
    var body: some View {
        Text(text)
            .copyable([text])                            // Edit > Copy
            .cuttable(for: String.self) {                // Edit > Cut
                let value = text
                return [value]
            }
            .pasteDestination(for: String.self) { items in   // Edit > Paste
                text = items.first ?? text
            }
    }
}
```

### U. responder chain の paste: action / NSServicesMenuRequestor

```swift
import AppKit

// paste: の宣言元は NSText。NSResponder には宣言がないため、
// カスタム responder では @objc func paste(_:) を実装して action を受ける。
// Swift 6 では NSServicesMenuRequestor 適合を @MainActor で隔離する（RK-09）。
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

### F. ファイル約束 — 提供側（provider / delegate の所有を明示する。RK-21）

```swift
import AppKit
import UniformTypeIdentifiers

// NSFilePromiseProviderDelegate は nonisolated な要件（writePromiseTo）を持つため、
// この型自体は MainActor 隔離しない。
final class FilePromiseDelegate: NSObject, NSFilePromiseProviderDelegate {
    private let queue = OperationQueue()

    func filePromiseProvider(_ p: NSFilePromiseProvider, fileNameForType fileType: String) -> String {
        "export.txt"                                     // ここではまだ書き出さない
    }

    // 書き出し要求は複数回来うる（複数の受け手が約束を引き取る場合）。
    // completion は「要求ごとに 1 回」であり、provider 全体で 1 回ではない。
    // 下の同期的な do/catch がその「要求ごとに 1 回」をそのまま満たす。
    func filePromiseProvider(_ p: NSFilePromiseProvider, writePromiseTo url: URL,
                             completionHandler: @escaping (Error?) -> Void) {
        do { try "content".write(to: url, atomically: true, encoding: .utf8); completionHandler(nil) }
        catch { completionHandler(error) }               // 必ず引数の url に書く
    }

    func operationQueue(for p: NSFilePromiseProvider) -> OperationQueue { queue }
}

// provider.delegate は weak。かつ delegate 側に完了通知がないため、
// セッションが provider と delegate の両方を強参照し、所有権喪失まで生存させる。
@MainActor
final class FilePromiseSession {
    private let delegate: FilePromiseDelegate
    private let provider: NSFilePromiseProvider
    private let ownedChangeCount: Int

    init(fileType: UTType) {
        delegate = FilePromiseDelegate()
        let pb = NSPasteboard.general
        ownedChangeCount = pb.clearContents()
        provider = NSFilePromiseProvider(fileType: fileType.identifier, delegate: delegate)
        _ = pb.writeObjects([provider])
    }

    /// 所有権を失ったら約束は履行されない。ここが解放判断点になる（完了通知が無いため）
    var isStale: Bool { NSPasteboard.general.changeCount != ownedChangeCount }
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

## 11. 要検証事項（断定を避けた項目）

ID は v1 の V-1〜V-10 を維持し、V-11 / V-12 / V-13 を追加した。
v3 で V-13 を V-13a（他アプリ所有時）と V-13b（自所有時）に分割した。

**測定状況（2026-08-29 時点）**

- macOS 26.3 で測定済・15.x 未確認: V-11、V-13a
- 未測定: V-1〜V-10、V-12、V-13b
- 判定保留（アラートを再現できる環境が未確立。RK-22）: V-1 / V-2 / V-10 / V-12

**26.3 の測定結果を 15.x にそのまま適用しない。** RK-22 のとおり 26.x と 15.x では
ペーストボード周りの挙動が現に異なっているため、15.x 環境を用意する際に V-11 / V-13a も
併せて再実行する（追加コストはボタン操作のみ）。

| ID | 内容 | 検証方法 |
|---|---|---|
| V-1 | Q-01〜Q-07 および M-01 がペーストボードアクセスアラートを発生させないか | **判定保留（2026-08-29）。**macOS 26.3 実機と macOS 15.4.1 VM の両方で、最もアラートが出やすいはずの R-01 `readObjects` すら、クリック起点でも無人バックグラウンド読み取りでも、別プロセス所有のペーストボードに対して 10 ミリ秒未満で無警告に成功した。**正の対照が一度も成立していないため、「アラートが出なかった」を「Q 群は安全」の根拠に採用しない**（RK-22）。再開する場合は、まずアラートを再現できる環境と手順を確立することが前提。**RK-01 の Q 群フォールバックは正式採用しない** |
| V-2 | U-01〜U-04（`PasteButton`）/ U-08（`paste:` action）/ U-09（`readSelection(from:)`）が「user originated かつ paste related」としてアラート免除に該当するか | **判定保留（RK-22）。**そもそもアラートを再現できないため、免除の有無を比較できない。なお 2026-08-29 の実測で、ボタンのクリックを起点とする `readObjects` は無警告で成功しており、NSPasteboard.h の「user originated and paste related なアクセスは常に許可され通知されない」という記述とは矛盾しない |
| V-3 | L-01 の `NSPasteboardItemDataProvider`、および C-12〜C-14 の `NSPasteboardWriting` 実装オブジェクトを、呼び出し側が強参照しなくてもシステムが保持するか | provider をローカル変数のみで生成して C-03 の後に解放し、別アプリから該当型を要求して供給されるか確認する |
| V-4 | L-02 / L-06 / R-10〜R-12 / C-12〜C-14 および D-11（ObjC 版検出 API）が呼ばれるスレッド | 実機で `Thread.isMainThread` / `dispatch_queue_get_label` をログ出力して確認する |
| V-5 | D-01〜D-06 が Swift の Task キャンセルを尊重するか（`CancellationError` を throw するか） | 大きなペーストボード内容に対して呼び出し直後に `Task.cancel()` し、throw される error の型を確認する |
| V-6 | App Sandbox 下で、ペーストボードから取得した `fileURL` の内容を読めるか（サンドボックス例外が自動付与されるか） | `MacLibraryExample`（サンドボックス有効）で Finder からコピーしたファイルの URL を読み、`Data(contentsOf:)` の成否を確認する。失敗する場合は D&D 経路との差分も記録する |
| V-7 | P-02 / P-03 のペーストボードが実際にアプリ終了後も他プロセスから読めるか、および P-04 実行後に読めなくなるか | 一意名ペーストボードへ書き込み → アプリ終了 → 別プロセスから同名で読み取り。P-04 実行後も同様に確認する（iOS 版 M-08 と対比する） |
| V-8 | H-01（`.currentHostOnly`）が実際に Universal Clipboard 同期を抑止するか。**正の対照を先に取る** | **端末 A = 送信元の Mac（`MacLibraryExample` 実行機）、端末 B = 同一 iCloud アカウントの iPhone（受信先）。手順: (1) 端末 A で `clearContents()` + `writeObjects` の通常コピーを行い、端末 B で受信できることを先に確認する（正の対照。Universal Clipboard 環境自体が機能していることの証明）。(2) 同一条件で `prepareForNewContents(with: .currentHostOnly)` + `writeObjects` を行い、端末 B で受信できないことを確認する。(3) 記録項目: 両端の OS バージョン、Bluetooth / Wi-Fi / Handoff の有効状態、同一 Apple Account へのサインイン確認、各コピー後の待機時間（最低 30 秒）。(1) が失敗する場合は (2) の結果を証拠として採用しない** |
| V-9 | H-01 設定後に C-03 以外（C-04 `setString` 等）で書いた場合もオプションが維持されるか | V-8 と同じ正の対照つき手順を `setString` 経路で実施する |
| V-10 | macOS 15.0 / 15.1 / 15.3 におけるアラートの実挙動差 | 各バージョンの実機または VM で、R-01 実行時のアラート表示頻度と文言を記録する |
| ~~V-11~~ **解決済** | F-01 / F-03 について、システムが provider / delegate を保持するか | **2026-08-29 実測（ClipboardProbe）。macOS 26.3 実機と macOS 15.4.1 VM で同一結果: `provider retained by system? true` / `delegate retained by system? false`、delegate の `deinit` はスコープ離脱と同時に発火。provider だけが生き残り、delegate が nil のまま約束が残るため、他アプリからは有効に見えて永久に履行できない。→ RK-21 へ反映済み** |
| V-12 | U-05〜U-07（`copyable` / `cuttable` / `pasteDestination`）がアラート免除に該当するか、および Edit メニュー項目が自動で有効化されるか | **アラート免除の部分は判定保留（RK-22）。**メニュー項目の enable / disable がペーストボード内容に応じて自動更新されるか（`PasteButton` の RK-16 と同じ制約があるか）は、アラートと無関係なので測定可能 |
| ~~V-13a~~ **解決済** | C-03 による追記が、**他アプリが所有者**のペーストボードに対して成立するか | **2026-08-29 実測。macOS 26.3 実機（`changeCount` 19→19）と macOS 15.4.1 VM（2→2）で同一結果: `writeObjects` は `false`、items 1→1、types 変化なし。他アプリ所有時の追記は成立しない。→ 第 8 章 P-2 / RK-23 へ反映済み** |
| ~~V-13b~~ **解決済** | C-03 による追記が、自分が所有者である間の 2 回目以降の呼び出しで成立するか | **2026-08-29 実測（macOS 15.4.1 VM）。`clearContents()` で `changeCount` 3 を取得した後、`writeObjects` #1 → `true`（items 1）、#2 → `true`（items 2）、`changeCount` は 3 のまま。**自所有ペーストボードへの追記は成立し、所有権も維持される**。NSPasteboard.h の記述と一致。→ P-2 / RK-23 へ反映済み** |

---

## 12. Definition of Done

### 調査完了条件

- [x] 対象 OS（macOS 15 以降）の公式ドキュメント URL を一覧化した
- [x] SDK ヘッダ・`.swiftinterface`（MacOSX26.2.sdk）を一次ソースとして参照し、シグネチャとバージョン制約を確定した
- [x] initializer 単位で availability が異なる API（`PasteButton`）を、型の availability と分離して記載した
- [x] API の宣言元を実際のヘッダで確認した（`paste:` が `NSResponder` ではなく `NSText` に宣言されていることを含む）
- [x] 対象機能をサブ機能（P / C / L / H / R / Q / X / M / D / U / F / G）へ分解した
- [x] 各サブ機能について API 一覧を作成し、目的・主要引数・返却値・実行方式・エラーケース・最小利用条件を記載した
- [x] 廃止予定 API・廃止済み API と代替 API を注記した（macOS 10.13 / 10.14 廃止分を全件列挙）
- [x] **API 全網羅表の全行に ID を付与し、同期・非同期分類表を同じ ID で引けるようにした**
- [x] **分類表に収録しない ID（定数・値型・列挙）を 7.1 に明示列挙し、それ以外の全 ID が分類表に存在することを機械的に照合できるようにした**
- [x] 分類表に protocol requirement（C-12〜C-14 / R-10〜R-12 / L-02 / L-03 / L-06 / L-07 / F-05〜F-07）を独立行として収録した
- [x] 非同期 API（D-01〜D-06）について、完了方式・完了アクター・キャンセル手段・リソース所有権を記載した
- [x] **`NSFilePromiseProvider.delegate` の `weak` 保持と、完了通知が存在しないことによる解放判断の困難さを API 表・分類表・リスク表・サンプルへ反映した**
- [x] **未検証事項をプライバシー緩和策として確定採用しないよう、RK-01 / RK-02 の記述を V-1 の結果に条件付けた**
- [x] 公式文書で確定できない事項を推測せず「要検証」として V-1〜V-13 に分離し、検証方法を記載した
- [x] **`.currentHostOnly` の検証手順に正の対照（通常コピーの転送成功確認）と環境記録条件を含めた**
- [x] **iOS 公開 API（`IosClipboardManager` の P-1〜P-16）に対する macOS の対応 / 代替 / 非対応を全件パリティ表に整理した**
- [x] 各サブ機能に最小サンプルコードを記載し、全件を Swift 6 strict concurrency で**コンパイル検証**した（型検査の範囲であることを明記）
- [x] 実装リスクを権限・制約・互換性の観点で RK-01〜RK-23 として整理した
- [x] **V-11 / V-13 を実機で検証し、結果を該当する API 表・パリティ表・リスク表へ反映した**
- [x] **検証環境そのものの制約（macOS 26.x では測定不能）を RK-22 として記録し、残る検証項目に必要な OS を明示した**
- [x] 公式ソースと補助ソースを分離した（補助ソースは採用せず、ローカル検証結果として明示した）

### 次工程（設計）への引き継ぎ条件

- [ ] macOS 15.0–15.3 と 15.4+ の分岐方針を設計書で確定する（RK-01 / RK-02）。**V-1 の結果を待って Q 群の位置づけを決める**
- [ ] 第 8 章パリティ表をもとに、macOS 公開 API のシグネチャを確定する。特に P-11（loadItem）/ P-12（cancelAllLoads）/ P-13（startObserving）/ P-16（makePasteControl）は iOS と契約が異なるため、非対応・代替のいずれで公開するかを決める
- [ ] **P-2（append）を「自所有時のみ有効」の契約で公開するか、非対応とするかを決める（RK-23。V-13a / V-13b で挙動は確定済み）。公開する場合、所有権喪失時に明示エラーを返す設計にする**
- [ ] 所有権取得を C-01 / C-02 のどちらに集約するかを 1 経路に決める（RK-05）
- [ ] 名前付き / 一意名ペーストボードの公開可否と `releaseGlobally()` の責務所在を決める（RK-06 / RK-07）
- [ ] `NSPasteboard` 非 Sendable を前提とした並行性方針（`@MainActor` 固定か専用実行文脈か）を決める（RK-08）
- [ ] File Promise を公開機能に含めるかを決める。**含める場合、provider / delegate を強参照するセッション型は必須で確定している**（RK-21 / V-11 実測済み）。設計すべきは解放契約（`changeCount` による所有権喪失検出）のみ
- [ ] **実装工程・サンプルアプリ工程・マニュアル工程の手動確認手順に「アラート関連は macOS 15.x で確認する」を明記する（RK-22）。開発機 26.x での確認はプライバシー系 DoD の根拠にならない**
- [ ] 変更監視のポーリング間隔既定値とアプリ非アクティブ時の停止方針を決める（RK-11）
- [ ] 残る V-1〜V-10 / V-12 の検証を消化し、結果を設計書または本書の改訂版へ反映する。**V-1 / V-2 / V-10 / V-12 は macOS 15.x の実機または VM が必須**（RK-22）。**V-8 は正の対照が成立した記録とセットで残す**

---

## 13. レビュー反映履歴

### 実測反映（v3 / 2026-08-29）

macOS 15.4.1 VM（Tart、`--no-clipboard`）での追加実測を反映。

- **V-13b 解決（新規発見）**: 自所有ペーストボードへの 2 回目以降の `writeObjects` は成立する（items 1→2、`changeCount` 不変）。`append` は「自所有時のみ」という狭い契約で提供可能。P-2 を「非対応」から「自所有時のみ対応」へ再度改めた
- **V-13a 解決**: 他アプリ所有時の追記不可を 15.4.1 でも確認。26.3 と同一結果
- **V-11 解決**: provider 保持・delegate 解放を 15.4.1 でも確認。26.3 と同一結果
- **RK-22 を全面改訂**: 当初「macOS 26.3 では制御が観測できない」としたが、15.4.1 でも同じだったため 26 固有ではない。「試した全構成でアラートを再現できず、検証手段が未確立」に改め、V-1 / V-2 / V-12 を判定保留とした。正の対照が成立していない以上「アラートが出なかった」を「安全」の根拠に使わない

検証アプリ `ClipboardProbe`（Apple Development 署名 / App Sandbox 有効）で実測。

- **V-11 解決**: provider はシステムが保持するが `weak` delegate は即座に解放される。provider だけが
  生き残るため、他アプリからは有効な約束に見えて永久に履行できない。RK-21 を推測から確定事項へ格上げし、
  この悪化条件を追記した
- **V-13 解決**: 所有権なしの `writeObjects` は `false` を返し、`changeCount` / items / types のいずれも
  変化しない。append は成立しない。第 8 章 P-2 を「対応（挙動差あり）」から**非対応**へ変更し、8.1 に
  追加、RK-23 を新設した
- **RK-22 新設**: macOS 26.3 では新規署名アプリが `accessBehavior == alwaysAllow` を返し、System Settings に
  "Paste from Other Apps" ペインが存在しない。構成プロファイル・グローバル設定・feature flag はいずれも
  未設定で環境固有の無効化ではない。開発機ではアラート系の挙動が再現しないため、V-1 / V-2 / V-10 / V-12 は
  macOS 15.x 必須とした
- 第 12 章の引き継ぎ条件に、append の扱い・File Promise セッション保持の確定・手動確認 OS の明記を追加した

### 第 2 回レビュー反映（v2 / 2026-08-29）

- F-06 に Swift の `async throws` 形（`filePromiseProvider(_:writePromiseTo:)`）が存在することをコンパイルで確認し、API 表・分類表・第 4 章へ反映。「非同期 API は D-01〜D-06 のみ」の断定を「アプリが**呼び出す**非同期 API は D-01〜D-06 のみ」に限定し、アプリが**実装する**側の非同期形を別途明記した
- あわせて F-10 には `async throws` 形が生成されないことをコンパイルで確認し、API 表に明記した
- サンプルの `FilePromiseDelegate` から `finished` ガードを削除。completion は「provider 全体で 1 回」ではなく「**書き出し要求ごとに 1 回**」であり、グローバルガードは 2 回目以降の要求で completion を呼ばず受け手を待たせるため。RK-21 の記述も同様に訂正した
- 第 0 章および第 10 章冒頭の実行時検証参照を `V-1〜V-12` から `V-1〜V-13` に訂正した

### 第 1 回レビュー反映（v2 / 2026-08-29）

- 高: `NSFilePromiseProvider.delegate` の weak 保持責務を F-03・分類表・RK-21・サンプルへ反映（完了通知が存在しないことの明記を含む）
- 高: RK-01 / RK-02 から未検証 `canRead*` の確定的採用を除去し、V-1 の結果に条件付け
- 中: `PasteButton` の availability を型（10.15）と initializer（11.0 / 13.0）に分離、非推奨 initializer 2 種を追加
- 中: `NSResponder.paste(_:)` を responder chain の `paste:` action（`NSText.paste(_:)`）へ訂正し、一次ソースを追加
- 中: 第 8 章に iOS 公開 API パリティ表を新設（P-1〜P-16 全件 + 双方向の機能差分）
- 中: 全 API 表に ID 列を追加し、分類表と 1 対 1 対応。分類対象外 ID を 7.1 に列挙
- 中: V-8 / V-9 に正の対照と環境記録条件を追加
- 低: V-8 の端末役割を「端末 A = Mac（送信元）/ 端末 B = iPhone（受信先）」と明示
- 低: サンプルコードの検証範囲を「コンパイル検証」に限定し、実行時契約の検証先を明記
- 追加: レビュー未指摘の網羅漏れとして SwiftUI `copyable` / `cuttable` / `pasteDestination`（U-05〜U-07、macOS 13.0+・macOS 専用）を追加し、V-12 を新設
- 追加: iOS `append` 相当の追記挙動が未確認であることを V-13 として新設
- 表記: サブ機能記号 `V.` を `Q.` へ改称（要検証 ID との衝突回避）
