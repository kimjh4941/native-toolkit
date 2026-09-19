# iOS クリップボード機能 調査結果

- 作成日: 2026-08-01
- 改訂日: 2026-08-01（v4: 第 4 回レビュー指摘を反映）
- 前版: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v3.md`
- 対象OS: iOS 18 以降
- 対象機能: クリップボード（Clipboard / Pasteboard: コピー / ペースト）
- 使用言語: Swift
- 対象フレームワーク: UIKit（`UIPasteboard`）、Foundation（`NSItemProvider`）、UniformTypeIdentifiers（`UTType`）、DataDetection（`DDMatch*`）

---

## 目的

iOS のネイティブクリップボード API（`UIPasteboard` 系）を全網羅し、native-toolkit への組み込み設計に必要な情報を整理する。テキスト / URL / 画像 / 色 / 任意 UTI データのコピー・ペースト、`NSItemProvider` 経由の非同期読み取り、複数アイテム操作、内容確認、変更監視、iOS 14 以降のアクセス通知と iOS 16 以降の貼り付け許可アラートを避ける手段（`UIPasteControl` / パターン検出 API）、Universal Clipboard（Handoff）制御、名前付きペーストボードの寿命と App Group shared container との責務境界を対象とする。

---

## 調査対象範囲

### In scope

- ペーストボードの取得（general / 名前付き / ユニーク名）
- コピー（書き込み）: 文字列・URL・画像・色・任意 UTI データ・複数アイテム
- ペースト（読み取り）: 同上および `NSItemProvider` 経由の非同期ロード（型判定・キャンセル・エラー処理を含む）
- 内容確認 / 型判定（`hasStrings` 等、`types`、`contains(pasteboardTypes:)`、`itemSet(withPasteboardTypes:)`）
- クリップボードのクリア
- 変更監視（`changeCount`、`changedNotification`、`removedNotification`）
- パターン検出（`detectPatterns` / `detectValues`、ユーザー通知なしの事前判定）
- 貼り付け UI（`UIPasteControl`、`UIPasteConfiguration`、`UIPasteConfigurationSupporting`）
- プライバシー（iOS 14+ のアクセス通知、iOS 16+ の貼り付け許可アラート、`localOnly` / `expirationDate`）
- 名前付きペーストボードによる同一 Team ID アプリ間の**一時的**データ転送、および App Group shared container との責務境界

### Out of scope

- Android / macOS（`NSPasteboard`）/ Windows のクリップボード API
- ドラッグ&ドロップ（`UIDragInteraction` / `UIDropInteraction`。`NSItemProvider` を共有するが本調査対象外）
- 編集メニュー UI そのものの構築（`UIEditMenuInteraction` / `UIMenuController`）
- Find ペーストボード（`UIPasteboardNameFind` は廃止済み）
- `NSItemProvider` の **登録側 API 群**（`registerDataRepresentation` / `registerFileRepresentation` / `registerObject` / `registerCloudKitShare` / `registerGroupActivity` 等）。クリップボードへの書き込みは `setObjects` / `setItemProviders` で足りるため。存在のみ API 表に記載
- App Group shared container 上のファイル入出力そのもの（永続共有が必要な場合の受け皿として責務境界のみ記載。`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)` の実装は Clipboard 機能の責務外）
- `UIPasteboard.ChangedMessage` / `RemovedMessage`（iOS 26 追加。最小サポート iOS 18 では利用不可のため、存在のみ API 表に記載＝「全網羅」の担保）
- サードパーティ SDK

---

## 公式文書一覧（最優先ソース）

| タイトル | URL |
|---|---|
| UIPasteboard（概説・全 API） | https://developer.apple.com/documentation/uikit/uipasteboard |
| UIPasteboard – Deprecated symbols | https://developer.apple.com/documentation/uikit/uipasteboard-deprecated-symbols |
| UIPasteboard.Name | https://developer.apple.com/documentation/uikit/uipasteboard/name-swift.struct |
| Pasteboard Names | https://developer.apple.com/documentation/uikit/pasteboard-names |
| UIPasteboard.OptionsKey | https://developer.apple.com/documentation/uikit/uipasteboard/optionskey |
| Pasteboard Data Type Representations（typeList*） | https://developer.apple.com/documentation/uikit/pasteboard-data-type-representations |
| UserInfo Dictionary Keys（変更通知） | https://developer.apple.com/documentation/uikit/userinfo-dictionary-keys |
| UIPasteboard.DetectionPattern | https://developer.apple.com/documentation/uikit/uipasteboard/detectionpattern |
| UIPasteboard.DetectedValues | https://developer.apple.com/documentation/uikit/uipasteboard/detectedvalues |
| UIPasteControl | https://developer.apple.com/documentation/uikit/uipastecontrol |
| UIPasteControl.Configuration | https://developer.apple.com/documentation/uikit/uipastecontrol/configuration |
| UIPasteConfiguration | https://developer.apple.com/documentation/uikit/uipasteconfiguration |
| UIPasteConfigurationSupporting | https://developer.apple.com/documentation/uikit/uipasteconfigurationsupporting |
| UIPasteboard.ChangedMessage（iOS 26、参考） | https://developer.apple.com/documentation/uikit/uipasteboard/changedmessage |
| UIPasteboard.RemovedMessage（iOS 26、参考） | https://developer.apple.com/documentation/uikit/uipasteboard/removedmessage |
| UIPasteboard.init(name:create:)（寿命の根拠） | https://developer.apple.com/documentation/uikit/uipasteboard/init(name:create:) |
| UIPasteboard.withUniqueName()（寿命の根拠） | https://developer.apple.com/documentation/uikit/uipasteboard/withuniquename() |
| UIPasteboard.setValue(_:forPasteboardType:)（受け入れ型の根拠） | https://developer.apple.com/documentation/uikit/uipasteboard/setvalue(_:forpasteboardtype:) |
| NSItemProvider（読み取り API・Progress） | https://developer.apple.com/documentation/foundation/nsitemprovider |
| NSItemProviderReading | https://developer.apple.com/documentation/foundation/nsitemproviderreading |
| NSItemProviderWriting | https://developer.apple.com/documentation/foundation/nsitemproviderwriting |
| NSItemProvider.loadFileRepresentation（一時 URL の寿命） | https://developer.apple.com/documentation/foundation/nsitemprovider/loadfilerepresentation(fortypeidentifier:completionhandler:) |
| NSItemProvider.loadItem（非推奨・完了スレッドの根拠） | https://developer.apple.com/documentation/foundation/nsitemprovider/loaditem(fortypeidentifier:options:completionhandler:) |
| Progress.cancel()（キャンセル契約の根拠） | https://developer.apple.com/documentation/foundation/progress/cancel() |
| CoreTransferable | https://developer.apple.com/documentation/coretransferable |
| Transferable（`loadTransferable` の型制約） | https://developer.apple.com/documentation/coretransferable/transferable |
| Uniform Type Identifiers（UTType） | https://developer.apple.com/documentation/uniformtypeidentifiers |
| UTType | https://developer.apple.com/documentation/uniformtypeidentifiers/uttype |
| App Groups Entitlement | https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups |
| FileManager.containerURL(forSecurityApplicationGroupIdentifier:)（shared container） | https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:) |

公式文書からの主要引用（設計根拠）:

- 「In iOS 16 and later, programmatic pasting raises a user alert that prompts the user for approval before the app gains access to pasteboard contents. Use this class to paste without a user prompt.」（UIPasteControl）
- 「The system notifies the user when you access properties or call methods that pull data from the pasteboard if the system doesn't determine that the user intends to access that data.」（UIPasteboard）
- 「Use these properties, rather than attempting to read pasteboard data, to avoid causing the system to needlessly attempt to fetch data」（UIPasteboard、`hasStrings` 等の説明）
- 「When a user signs into iCloud, the general pasteboard automatically transfers its contents to nearby devices that use the same iCloud account.」（UIPasteboard、Universal Clipboard）
- 「For sharing data with another app from your team — that has the same team ID as the app to share from — configure an App Group.」（UIPasteboard、名前付きペーストボード）
- 「App pasteboards this method returns aren't persistent, existing only until the app quits. Starting in iOS 10, persistent, named pasteboards are deprecated. Instead, use a shared container」（`init(name:create:)`。`withUniqueName()` にも同一の記述あり）
- 「Use this method to put an object—such as an NSString, NSArray, NSDictionary, NSDate, NSNumber, UIImage, or NSURL object—on the pasteboard. ... Calling this method replaces any items currently in the pasteboard.」（`setValue(_:forPasteboardType:)`）

---

## 補助ソース一覧（必要時のみ）

| 内容 | 情報源 | 信頼度 |
|---|---|---|
| `UIPasteControl` の target 設定要件（`UIPasteConfigurationSupporting` を実装した responder が必要）と実機挙動 | Apple Developer Forums（公式運営フォーラム） | medium |

補足: 本調査書の設計根拠は全て Apple 公式 API リファレンスで裏付け済み。補助ソースは実機挙動の参考としてのみ利用し、公式文書と矛盾する記述は採用しない。

---

## 機能マップ（サブ機能分解）

```
iOS クリップボード機能
├── ペーストボード取得
│   ├── general（システム全体・唯一の永続ペーストボード）
│   ├── init(name:create:)（名前付き。非永続・アプリ終了まで）
│   ├── withUniqueName()（同上）
│   ├── remove(withName:)
│   └── ＜責務境界＞永続共有は App Group shared container（本機能の対象外）
├── コピー（書き込み）
│   ├── 標準型（string / strings / url / urls / image / images / color / colors）
│   ├── 任意 UTI（setData(_:forPasteboardType:) / setValue(_:forPasteboardType:)）
│   ├── 複数アイテム（items / setItems(_:options:) / addItems）
│   └── ItemProvider（setObjects / setItemProviders、localOnly / expirationDate）
├── ペースト（読み取り）
│   ├── 標準型（string / urls / image / colors）
│   ├── 任意 UTI（data(forPasteboardType:) / value(forPasteboardType:) / values(...inItemSet:)）
│   └── itemProviders（NSItemProvider 経由）
│       ├── 型判定（registeredTypeIdentifiers / hasItemConformingToTypeIdentifier / canLoadObject）
│       ├── 非同期ロード（loadObject / loadDataRepresentation / loadFileRepresentation）
│       └── キャンセル・エラー（Progress.cancel / NSItemProvider.ErrorCode）
├── 内容確認 / 型判定（アラートを出さない事前判定）
│   ├── hasStrings / hasURLs / hasImages / hasColors
│   ├── numberOfItems / types / types(forItemSet:)
│   ├── contains(pasteboardTypes:) / contains(pasteboardTypes:inItemSet:)
│   ├── itemSet(withPasteboardTypes:)
│   └── typeListString / typeListURL / typeListImage / typeListColor / typeAutomatic
├── クリア（items = [] / remove(withName:)）
├── 変更監視
│   ├── changeCount
│   ├── changedNotification（+ userInfo キー）
│   └── removedNotification
├── パターン検出（ユーザー通知なし）
│   ├── detectPatterns / detectedPatterns（keyPath 版、iOS 15+）
│   ├── detectValues / detectedValues（keyPath 版、iOS 15+）
│   └── DetectionPattern 版（iOS 14、非推奨）
├── 貼り付け UI
│   ├── UIPasteControl（iOS 16+、アラートなし）
│   ├── UIPasteConfiguration
│   └── UIPasteConfigurationSupporting（canPaste / paste(itemProviders:)）
└── プライバシー
    ├── iOS 14+ アクセス通知（読み取り後に「〇〇からペースト」バナー）
    ├── iOS 16+ 貼り付け許可アラート（読み取り前に承認ダイアログ）
    ├── Universal Clipboard 抑止（localOnly）
    └── 有効期限（expirationDate）
```

---

## API 全網羅表（サブ機能別）

最小サポートは iOS 18 のため、特記なき API は全て利用可能。「最小条件」列は API の導入バージョンを示す。

### ペーストボード取得

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `UIPasteboard.general` | システム全体の汎用ペーストボード取得 | なし | `UIPasteboard` | なし | iOS 3.0 |
| `UIPasteboard(name:create:)` | 名前付きペーストボードを取得（`create: true` で作成）。**非永続（作成アプリの終了まで）** | `name: UIPasteboard.Name`, `create: Bool` | `UIPasteboard?` | 存在せず `create: false` で nil。作成側アプリ終了後は取得できない | iOS 3.0 |
| `UIPasteboard.withUniqueName()` | システム生成のユニーク名でアプリ用ペーストボード作成。**非永続（同上）** | なし | `UIPasteboard` | なし | iOS 3.0 |
| `UIPasteboard.remove(withName:)` | 名前付きペーストボードを破棄（以降の呼び出しは無視される） | `name: UIPasteboard.Name` | Void | システムペーストボード（general）には無効 | iOS 3.0 |
| `UIPasteboard.Name.general` | general ペーストボード名の定数 | - | `UIPasteboard.Name` | なし | iOS 10.0 |
| `UIPasteboard.Name(rawValue:)` / `init(_:)` | 任意名の生成 | `String` | `UIPasteboard.Name` | なし | iOS 10.0 |
| `pasteboard.name` | ペーストボード名の取得 | なし | `UIPasteboard.Name` | なし | iOS 3.0 |
| `UIPasteboardNameFind` | Find ペーストボード名 | - | `String` | - | **廃止済み（使用しない）** |
| `pasteboard.isPersistent` / `setPersistent(_:)` | 永続化フラグ | `Bool` | `Bool` / Void | - | **非推奨**（iOS 10 以降、名前付きは常に非永続） |

名前付きペーストボードの寿命（重要）: `init(name:create:)` / `withUniqueName()` が返すアプリペーストボードは公式に「aren't persistent, existing only until the app quits」と明記されている。**App Group ID をペーストボード名に使っても永続化はされない**。App Group が必要なのは「同一 Team ID の別アプリからそのペーストボードにアクセスするため」であり、永続化のためではない。作成側アプリの終了後も残す必要があるデータは、公式が代替として挙げる **App Group shared container**（`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`）で扱う。これは Clipboard 機能の責務外とし、ツールキットの公開 API では「名前付きペーストボード = 生存中のアプリ間一時転送」に限定する。

### コピー（書き込み） — 標準型

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `pasteboard.string` (set) | 文字列を 1 アイテムとして書き込み | `String?` | - | nil 代入時の挙動は要検証（クリア用途には `items = []` を使う） | iOS 3.0 |
| `pasteboard.strings` (set) | 複数文字列を複数アイテムとして書き込み | `[String]?` | - | なし | iOS 3.0 |
| `pasteboard.url` / `urls` (set) | URL を書き込み | `URL?` / `[URL]?` | - | なし | iOS 3.0 |
| `pasteboard.image` / `images` (set) | 画像を書き込み | `UIImage?` / `[UIImage]?` | - | 大容量画像でメモリ圧迫 | iOS 3.0 |
| `pasteboard.color` / `colors` (set) | 色を書き込み | `UIColor?` / `[UIColor]?` | - | なし | iOS 3.0 |

### コピー（書き込み） — 任意 UTI / 複数アイテム / ItemProvider

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `setData(_:forPasteboardType:)` | 任意 UTI の `Data` を先頭アイテムに書き込み | `Data`, `String`（UTI） | Void | 不正 UTI 文字列でも例外は出ず受信側が解釈不能になる | iOS 3.0 |
| `setValue(_:forPasteboardType:)` | 共通オブジェクトを**先頭アイテムとして**書き込み。公式が挙げる受け入れ型は `NSString` / `NSArray` / `NSDictionary` / `NSDate` / `NSNumber` / `UIImage` / `NSURL` | `Any`, `String` | Void | **既存アイテムを全て置換する**（追加ではない）。列挙外オブジェクトを渡した際の挙動は要検証。生バイナリは `setData` を使う | iOS 3.0 |
| `pasteboard.items` (set) | アイテム配列（`[[UTI: Any]]`）を直接設定 | `[[String: Any]]` | - | 空配列でクリア | iOS 3.0 |
| `setItems(_:options:)` | アイテム配列 + プライバシーオプション設定 | `[[String: Any]]`, `[OptionsKey: Any]` | Void | オプション値の型不一致 | iOS 10.0 |
| `addItems(_:)` | 既存内容にアイテムを追加 | `[[String: Any]]` | Void | なし | iOS 3.0 |
| `setObjects(_:)` | `NSItemProviderWriting` 準拠オブジェクト配列を書き込み | `[any NSItemProviderWriting]` | Void | なし | iOS 11.0 |
| `setObjects<T>(_:)` | 上記のジェネリック版オーバーロード | `[T]`（`T: NSItemProviderWriting`） | Void | なし | iOS 11.0 |
| `setObjects(_:localOnly:expirationDate:)` | 上記 + Handoff 抑止 / 有効期限 | `[any NSItemProviderWriting]`, `Bool`, `Date?` | Void | なし | iOS 11.0 |
| `setObjects<T>(_:localOnly:expirationDate:)` | 上記のジェネリック版オーバーロード | `[T]`, `Bool`, `Date?` | Void | なし | iOS 11.0 |
| `setItemProviders(_:localOnly:expirationDate:)` | `NSItemProvider` 配列を明示的に設定 | `[NSItemProvider]`, `Bool`, `Date?` | Void | なし | iOS 11.0 |
| `UIPasteboard.OptionsKey.localOnly` | Universal Clipboard へ流さない | `Bool` | - | - | iOS 10.0 |
| `UIPasteboard.OptionsKey.expirationDate` | システムが自動削除する日時 | `Date` | - | 過去日時指定時の挙動は要検証 | iOS 10.0 |

### ペースト（読み取り）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `pasteboard.string` (get) | 先頭アイテムの文字列取得 | なし | `String?` | 文字列型でなければ nil。**OS がユーザー意図を認定しない場合、iOS 16+ で許可アラート / iOS 14+ でアクセス通知** | iOS 3.0 |
| `pasteboard.strings` (get) | 全アイテムの文字列配列 | なし | `[String]?` | 同上 | iOS 3.0 |
| `pasteboard.url` / `urls` (get) | URL 取得 | なし | `URL?` / `[URL]?` | 同上 | iOS 3.0 |
| `pasteboard.image` / `images` (get) | 画像取得 | なし | `UIImage?` / `[UIImage]?` | 同上。デコードコスト大 | iOS 3.0 |
| `pasteboard.color` / `colors` (get) | 色取得 | なし | `UIColor?` / `[UIColor]?` | 同上 | iOS 3.0 |
| `data(forPasteboardType:)` | 指定 UTI の `Data` を先頭アイテムから取得 | `String` | `Data?` | 型不一致で nil | iOS 3.0 |
| `data(forPasteboardType:inItemSet:)` | 指定アイテム群から `Data` 配列取得 | `String`, `IndexSet?` | `[Data]?` | 該当なしで nil | iOS 3.0 |
| `value(forPasteboardType:)` | 指定 UTI のオブジェクト取得 | `String` | `Any?` | 型不一致で nil | iOS 3.0 |
| `values(forPasteboardType:inItemSet:)` | 指定アイテム群からオブジェクト配列取得 | `String`, `IndexSet?` | `[Any]?` | 該当なしで nil | iOS 3.0 |
| `pasteboard.items` (get) | 全アイテムの辞書配列取得 | なし | `[[String: Any]]` | 空時は空配列 | iOS 3.0 |
| `pasteboard.itemProviders` (get) | `NSItemProvider` 配列取得（非同期ロード可能） | なし | `[NSItemProvider]` | なし。**通知・許可プロンプトの契機（getter / 型判定 / ロードのどの時点か）は要検証**（テスト行列ケース 13〜15） | iOS 11.0 |

### ペースト（読み取り） — NSItemProvider 経由

`pasteboard.itemProviders` および `paste(itemProviders:)` で受け取った `NSItemProvider` から実データを取り出す API 群。ツールキットが採用するのは型判定 3 種 + ロード 3 種 + キャンセル / エラーとし、それ以外は参考として列挙する。

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `registeredTypeIdentifiers` | 登録された UTI 一覧（登録順） | なし | `[String]` | 空配列 | iOS 8.0 |
| `registeredTypeIdentifiers(fileOptions:)` | ファイルオプション条件付きの UTI 一覧 | `NSItemProviderFileOptions` | `[String]` | 空配列 | iOS 11.0 |
| `registeredContentTypes` / `registeredContentTypes(conformingTo:)` | `UTType` ベースの型一覧 | なし / `UTType` | `[UTType]` | 空配列 | iOS 16.0 |
| `registeredContentTypesForOpenInPlace` | in-place で開ける型一覧 | なし | `[UTType]` | 空配列 | iOS 16.0 |
| `hasItemConformingToTypeIdentifier(_:)` | 指定 UTI に適合するデータ表現の有無 | `String` | `Bool` | なし | iOS 8.0 |
| `hasRepresentationConforming(toTypeIdentifier:fileOptions:)` | ファイルオプション込みの適合判定 | `String`, `NSItemProviderFileOptions` | `Bool` | なし | iOS 11.0 |
| `canLoadObject(ofClass:)` | 指定クラスとしてロード可能か（`NSItemProviderReading` 準拠） | `T.Type` | `Bool` | なし | iOS 11.0 |
| `loadObject(ofClass:completionHandler:)` | オブジェクトとして非同期ロード | `T.Type`, `(T?, Error?) -> Void` | `Progress` | ロード失敗 / 型不一致で `error`。**completion は任意スレッド**（メイン保証なし） | iOS 11.0 |
| `loadDataRepresentation(forTypeIdentifier:completionHandler:)` | 指定 UTI の `Data` を非同期ロード | `String`, `(Data?, Error?) -> Void` | `Progress` | 同上 | iOS 11.0 |
| `loadDataRepresentation(for:completionHandler:)` | 上記の `UTType` 版 | `UTType`, `(Data?, Error?) -> Void` | `Progress` | 同上 | iOS 16.0 |
| `loadFileRepresentation(forTypeIdentifier:completionHandler:)` | 一時ファイルへ書き出して URL を返す | `String`, `(URL?, Error?) -> Void` | `Progress` | **URL は completion 内でのみ有効**。抜ける前にコピーが必要 | iOS 11.0 |
| `loadFileRepresentation(for:openInPlace:completionHandler:)` | 上記の `UTType` / in-place 版 | `UTType`, `Bool`, `(URL?, Bool, Error?) -> Void` | `Progress` | 同上 | iOS 16.0 |
| `loadInPlaceFileRepresentation(forTypeIdentifier:completionHandler:)` | 可能なら元ファイルを直接開く | `String`, `(URL?, Bool, Error?) -> Void` | `Progress` | in-place 不可時はコピーの URL が返る | iOS 11.0 |
| `loadItem(forTypeIdentifier:options:completionHandler:)` | 型強制ポリシーに従って item をロード | `String`, `[AnyHashable: Any]?`, `CompletionHandler?` | Void | 型強制失敗。公式に「The block may be executed on a background thread」と明記 | iOS 8.0。**非推奨**（Swift の async 版 `loadItem(forTypeIdentifier:options:)` へ置換。非推奨バージョンは要検証）。本調査では参考扱いとし、`loadObject` / `loadDataRepresentation` を採用する |
| `loadTransferable(type:completionHandler:)` | `Transferable`（CoreTransferable）としてロード。`import CoreTransferable` が必要 | `T.Type`（`T: Transferable`）, `(Result<T, Error>) -> Void` | `Progress` | `.failure` | iOS 16.0（`Transferable` プロトコル自体も iOS 16.0） |
| `Progress.cancel()` | 進行中のロードをキャンセル | なし | Void | **completion が呼ばれないことは保証されない**（保証されるのは cancellation handler の実行と `isCancelled` の更新）。キャンセル後に結果が届く前提で自前 gate が必要 | iOS 7.0 |
| `NSItemProvider.errorDomain` / `NSItemProvider.ErrorCode` | エラー判定用のドメインとコード | - | `String` / `enum` | - | iOS 8.0（`unknownError` / `itemUnavailableError` / `unexpectedValueClassError` は iOS 8.0、`unavailableCoercionError` は **iOS 9.0**） |
| `suggestedName` | 書き出し時の推奨ファイル名 | なし | `String?` | nil あり | iOS 11.0 |
| `preferredPresentationSize` / `preferredPresentationStyle` | 表示ヒント | なし | `CGSize` / `enum` | - | iOS 11.0 |
| `NSItemProviderReading` / `NSItemProviderWriting` | 独自型を読み書き可能にするプロトコル | - | - | - | iOS 11.0 |
| `register*` 系（`registerDataRepresentation` / `registerFileRepresentation` / `registerObject` / `registerItem` / `registerCloudKitShare` / `registerGroupActivity` 等） | プロバイダへの表現登録 | - | - | - | **本調査では対象外・参考**（書き込みは `setObjects` / `setItemProviders` で足りる） |

責務境界: ツールキットは「`NSItemProvider` から標準型（テキスト / 画像 / URL）を非同期ロードしてメインスレッドで返す」までを担う。独自型の `NSItemProviderReading` 実装、ファイルの永続保存先の決定はアプリ側の責務とする。

### 内容確認 / 型判定（データ本体を読まない）

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `hasStrings` | 文字列の有無 | なし | `Bool` | なし。**アラートを出さない** | iOS 10.0 |
| `hasURLs` | URL の有無 | なし | `Bool` | 同上 | iOS 10.0 |
| `hasImages` | 画像の有無 | なし | `Bool` | 同上 | iOS 10.0 |
| `hasColors` | 色の有無 | なし | `Bool` | 同上 | iOS 10.0 |
| `numberOfItems` | アイテム数 | なし | `Int` | なし | iOS 3.0 |
| `pasteboard.types` | 先頭アイテムの表現型一覧 | なし | `[String]` | 空時は空配列 | iOS 3.0 |
| `types(forItemSet:)` | 指定アイテム群の表現型一覧 | `IndexSet?` | `[[String]]?` | 該当なしで nil | iOS 3.0 |
| `contains(pasteboardTypes:)` | 指定 UTI の保持有無 | `[String]` | `Bool` | なし。**通知・アラート非対象かは要検証**（下記注記参照） | iOS 3.0 |
| `contains(pasteboardTypes:inItemSet:)` | 指定アイテム群での保持有無 | `[String]`, `IndexSet?` | `Bool` | 同上 | iOS 3.0 |
| `itemSet(withPasteboardTypes:)` | 指定 UTI を持つアイテムの index 集合 | `[String]` | `IndexSet?` | 該当なしで nil | iOS 3.0 |
| `UIPasteboard.typeListString` | 文字列系 UTI 一覧 | - | `NSArray` | - | iOS 3.0 |
| `UIPasteboard.typeListURL` | URL 系 UTI 一覧 | - | `NSArray` | - | iOS 3.0 |
| `UIPasteboard.typeListImage` | 画像系 UTI 一覧 | - | `NSArray` | - | iOS 3.0 |
| `UIPasteboard.typeListColor` | 色系 UTI 一覧 | - | `NSArray` | - | iOS 3.0 |
| `UIPasteboard.typeAutomatic` | 型を自動判定させる表現型 | - | `String` | - | iOS 3.0 |

通知・アラート非対象 API の範囲（重要）: `UIPasteboard` 概説が「Use the following properties to avoid user notifications and alerts」として明示列挙しているのは `numberOfItems` / `types` / `types(forItemSet:)` / `itemSet(withPasteboardTypes:)` / `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `canLoadObject(ofClass:)` およびパターン検出 API である。**`contains(pasteboardTypes:)` と `changeCount` はこの列挙に含まれていない**。データ本体を読まない API であるため実際には安全な可能性が高いが、現時点では公式の明示保証ではない。事前判定には列挙済みの API を優先し、この 2 つは実機テスト行列で個別に観測してから採用可否を決める（要検証）。なお、`canLoadObject(ofClass:)` 自体は列挙済みだが、その前段となる `itemProviders` getter の通知・プロンプト契機は公式に明示されていないため、両操作を分けて観測する。

### クリア

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `pasteboard.items = []` | 全アイテム削除（クリアの標準手段） | `[[String: Any]]` | - | なし | iOS 3.0 |
| `setItems([], options: [:])` | オプション指定つきクリア | `[]`, `[:]` | Void | なし | iOS 10.0 |
| `UIPasteboard.remove(withName:)` | 名前付きペーストボード自体を破棄 | `UIPasteboard.Name` | Void | general は破棄不可 | iOS 3.0 |

### 変更監視

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `pasteboard.changeCount` | 内容変更回数（ポーリング判定用） | なし | `Int` | なし。**通知・アラート非対象かは要検証**（公式の非対象 API 列挙に含まれない） | iOS 3.0 |
| `UIPasteboard.changedNotification` | 内容変更通知 | - | `NSNotification.Name` | **他アプリによる変更・バックグラウンド中は配信されない**（要検証） | iOS 3.0 |
| `UIPasteboard.removedNotification` | ペーストボード破棄直前の通知 | - | `NSNotification.Name` | 名前付きペーストボードのみ対象 | iOS 3.0 |
| `UIPasteboard.changedTypesAddedUserInfoKey` | 追加された表現型（userInfo キー） | - | `String` | なし | iOS 3.0 |
| `UIPasteboard.changedTypesRemovedUserInfoKey` | 削除された表現型（userInfo キー） | - | `String` | なし | iOS 3.0 |
| `UIPasteboard.ChangedMessage` / `RemovedMessage` | NotificationCenter の型付きメッセージ版 | `typesAdded` / `typesRemoved` | - | - | **iOS 26.0**（対象外・参考） |

### パターン検出（ユーザー通知なしの内容判定）

`DDMatch*` 型は DataDetection フレームワーク（`import DataDetection`）。キーパス版は `PartialKeyPath<UIPasteboard.DetectedValues>` を使うため **Swift 専用**（Objective-C からは呼べない）。

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `detectPatterns(for:completionHandler:)` | 指定パターンの一致有無を判定（値は返さない） | `Set<PartialKeyPath<DetectedValues>>`, `(Result<Set<...>, Error>) -> Void` | Void | 検出器不可・キャンセルで `.failure` | iOS 15.0 |
| `detectedPatterns(for:)` | 上記の async 版 | `Set<PartialKeyPath<DetectedValues>>` | `Set<PartialKeyPath<DetectedValues>>` | `throws` | iOS 15.0 |
| `detectPatterns(for:inItemSet:completionHandler:)` | アイテム単位でのパターン判定 | + `IndexSet?` | Void | 同上 | iOS 15.0 |
| `detectedPatterns(for:inItemSet:)` | 上記の async 版 | + `IndexSet?` | `[Set<PartialKeyPath<DetectedValues>>]` | `throws` | iOS 15.0 |
| `detectValues(for:completionHandler:)` | 指定パターンの一致値を取得 | `Set<PartialKeyPath<DetectedValues>>`, `(Result<DetectedValues, Error>) -> Void` | Void | 同上 | iOS 15.0 |
| `detectedValues(for:)` | 上記の async 版 | `Set<PartialKeyPath<DetectedValues>>` | `DetectedValues` | `throws` | iOS 15.0 |
| `detectValues(for:inItemSet:completionHandler:)` / `detectedValues(for:inItemSet:)` | アイテム単位での値取得 | + `IndexSet?` | `[DetectedValues]` | 同上 | iOS 15.0 |
| `UIPasteboard.DetectedValues` | 検出結果コンテナ | - | - | - | iOS 15.0 |
| `DetectedValues.patterns` | 検出されたパターンのキーパス集合 | - | `Set<PartialKeyPath<DetectedValues>>` | - | iOS 15.0 |
| `DetectedValues.probableWebURL` / `probableWebSearch` | URL らしい文字列 / 検索語らしい文字列 | - | `String` | 未検出時は空文字（要検証） | iOS 15.0 |
| `DetectedValues.number` | 数値 | - | `Double?` | 未検出で nil | iOS 15.0 |
| `DetectedValues.links` | Web リンク | - | `[DDMatchLink]` | 未検出で空 | iOS 15.0 |
| `DetectedValues.emailAddresses` | メールアドレス | - | `[DDMatchEmailAddress]` | 同上 | iOS 15.0 |
| `DetectedValues.phoneNumbers` | 電話番号 | - | `[DDMatchPhoneNumber]` | 同上 | iOS 15.0 |
| `DetectedValues.postalAddresses` | 住所 | - | `[DDMatchPostalAddress]` | 同上 | iOS 15.0 |
| `DetectedValues.calendarEvents` | 日時 / イベント | - | `[DDMatchCalendarEvent]` | 同上 | iOS 15.0 |
| `DetectedValues.flightNumbers` | 便名 | - | `[DDMatchFlightNumber]` | 同上 | iOS 15.0 |
| `DetectedValues.moneyAmounts` | 金額・通貨 | - | `[DDMatchMoneyAmount]` | 同上 | iOS 15.0 |
| `DetectedValues.shipmentTrackingNumbers` | 配送追跡番号 | - | `[DDMatchShipmentTrackingNumber]` | 同上 | iOS 15.0 |
| `UIPasteboard.DetectionPattern`（`.probableWebURL` / `.probableWebSearch` / `.number`） | 旧パターン定数 | - | - | - | iOS 14.0（構造体自体は有効） |
| `detectPatterns(for: Set<DetectionPattern>, ...)` / `detectValues(for: Set<DetectionPattern>, ...)` | 旧 API（4 オーバーロード） | - | - | - | **非推奨**。キーパス版へ移行 |

### 貼り付け UI（許可プロンプトを回避する経路）

`UIPasteControl` について Apple が直接保証しているのは「paste without a user prompt」＝ **iOS 16 型の許可プロンプトを出さないこと**である。iOS 14 型のアクセス通知（読み取り後バナー）まで常に出ないとは公式に明記されていないため、テスト行列で別項目として観測する。

| API | 目的 | 主要引数 | 返却値 | エラーケース | 最小条件 |
|---|---|---|---|---|---|
| `UIPasteControl(configuration:)` | 貼り付けボタン生成（**許可プロンプトを回避**。アクセス通知の有無は要検証） | `UIPasteControl.Configuration` | `UIPasteControl` | なし | iOS 16.0 |
| `UIPasteControl(frame:)` / `init?(coder:)` | フレーム / Storyboard から生成 | `CGRect` / `NSCoder` | `UIPasteControl` | なし | iOS 16.0 |
| `pasteControl.target` | 貼り付け先 responder | `(any UIPasteConfigurationSupporting)?` | - | 未設定 / 型不適合でタップが無反応 | iOS 16.0 |
| `pasteControl.configuration` | 外観設定 | `UIPasteControl.Configuration` | - | なし | iOS 16.0 |
| `Configuration.displayMode` | アイコン / ラベル / 両方 | `UIPasteControl.DisplayMode` | - | なし | iOS 16.0 |
| `Configuration.baseBackgroundColor` / `baseForegroundColor` | 配色 | `UIColor?` | - | なし | iOS 16.0 |
| `Configuration.cornerRadius` / `cornerStyle` / `imagePlacement` | 形状・配置 | `CGFloat` / `UIButton.Configuration.CornerStyle` / `NSDirectionalRectEdge` | - | なし | iOS 16.0 |
| `UIPasteConfiguration()` | 受け入れ可能 UTI 設定オブジェクト | なし | `UIPasteConfiguration` | なし | iOS 11.0 |
| `UIPasteConfiguration(acceptableTypeIdentifiers:)` | UTI 配列で初期化 | `[String]` | 同上 | なし | iOS 11.0 |
| `UIPasteConfiguration(forAccepting:)` | `NSItemProviderReading` 型から初期化 | `T.Type` | 同上 | なし | iOS 11.0 |
| `acceptableTypeIdentifiers` / `addAcceptableTypeIdentifiers(_:)` / `addTypeIdentifiers(forAccepting:)` | 受け入れ型の取得・追加 | `[String]` / `T.Type` | `[String]` / Void | なし | iOS 11.0 |
| `UIResponder.pasteConfiguration` | responder に受け入れ型を関連付け | `UIPasteConfiguration?` | - | 未設定だと `UIPasteControl` が動作しない | iOS 11.0 |
| `canPaste(_:)` | 受け入れ可否の判定（オーバーライド可能） | `[NSItemProvider]` | `Bool` | なし | iOS 11.0 |
| `paste(itemProviders:)` | 貼り付け実行（オーバーライドして受信処理を実装） | `[NSItemProvider]` | Void | 非同期ロード失敗は自前ハンドリング | iOS 11.0 |

---

## 実装リスク（権限・制約・互換性）

| リスク | 詳細 | 対策 |
|---|---|---|
| iOS 14+ のアクセス通知と iOS 16+ の許可アラートは別仕様 | iOS 14 以降は general pasteboard を読み取った**後**に「〇〇からペースト」バナーが表示される。iOS 16 以降は読み取りの**前**に承認ダイアログが表示される。両者を混同すると「アラートが出ない」判定を誤る | 二段構えで整理する。事前判定（`hasStrings` 等）と検出 API（`detectPatterns` / `detectValues`）は本体を読まないため通知・アラートいずれの対象外。ユーザー起点の貼り付けは `UIPasteControl` / 標準ペーストメニュー経由にする。バージョン境界の実挙動は要検証扱い |
| アラート発生条件はシステムのユーザー意図判定に依存 | 公式は「if the system doesn't determine that the user intends to access that data」としており、「毎回必ず出る」とは書かれていない。同一アプリのコピー直後や標準ペースト経由では出ないことがある | ツールキットの仕様として「アラート表示の有無は OS 判断であり保証しない」と明記。下記テスト行列でパターン別に実測し、DoD では「出る／出ない」を断定せず観測結果の記録を条件にする |
| 権限 API が存在しない | クリップボードには `Info.plist` の usage description や明示的パーミッション API がない | 実装は不要。アラートは OS 側が自動表示するのみ |
| Universal Clipboard による外部流出 | iCloud サインイン時、general の内容が近接デバイスへ自動転送される | 機微データは `localOnly: true` を指定。`setItems(_:options:)` / `setObjects(_:localOnly:expirationDate:)` を使う |
| 機微データの残留 | 有効期限を設定しないとクリップボードに残り続ける | `expirationDate` を設定。必要に応じ `items = []` でクリア |
| コピー時のシステム UI がない | iOS はコピー完了の標準トーストを出さない | アプリ側でフィードバック UI（トースト等）を用意する前提を設計に含める |
| 変更通知の配信条件 | `changedNotification` は他アプリによる変更やバックグラウンド中に配信されない可能性が高い | フォアグラウンド復帰時に `changeCount` を比較するポーリング方式を併用。ただし `changeCount` は公式の「通知・アラート非対象 API」列挙に含まれないため、実機観測で確認してから採用する |
| 事前判定 API の通知非対象は一部のみ公式保証 | 公式が非対象として列挙するのは `numberOfItems` / `types` / `types(forItemSet:)` / `itemSet` / `has*` / `canLoadObject` / パターン検出。`contains(pasteboardTypes:)` と `changeCount` は列挙外 | 列挙済み API を第一選択とする。`itemProviders` getter と `canLoadObject` 自体は分けて評価する。列挙外の 2 つはテスト行列（`changeCount` はケース 4、`contains` はケース 12）で個別観測し、結果と OS バージョンを記録してから公開 API に採用する |
| `UIPasteControl` の保証範囲 | 公式が保証するのは iOS 16 型の許可プロンプトを出さないこと。iOS 14 型のアクセス通知まで出ないとは明記されていない | 「許可プロンプトを回避する経路」と表現し、アクセス通知はテスト行列ケース 7・16 で別列として観測する |
| 通知オブザーバの解除漏れ | `changedNotification` / `removedNotification` の登録を解除しないとリーク | ライフサイクルに合わせて `removeObserver`。Swift の block 版は通知ごとの `NSObjectProtocol` トークンを保持して解除 |
| `UIPasteControl` の設定不足 | `target` に `UIPasteConfigurationSupporting` 準拠 responder を設定し、その `pasteConfiguration` に受け入れ UTI を設定しないとタップしても何も起きない | 生成時に target と pasteConfiguration をセットで設定する API 設計にする |
| `UIPasteControl` は UIKit ビュー | ツールキットが非 UI 層 API のみ提供する場合、ボタンをアプリ側に配置してもらう必要がある | 公開 API として「ボタン生成 + 受信コールバック」を提供する形を設計段階で検討（要判断） |
| パターン検出のキーパス API が Swift 専用 | `PartialKeyPath` は Objective-C 非対応。Unity / ObjC ブリッジから直接呼べない | ブリッジ層で Swift 側にラップし、結果を文字列 / 単純型に変換して公開する |
| 旧 `DetectionPattern` 版の非推奨 | `Set<UIPasteboard.DetectionPattern>` を取る 4 オーバーロードは非推奨 | 新しい `PartialKeyPath<DetectedValues>` 版のみ採用する |
| 画像コピーのメモリ・性能 | `image` / `images` は `UIImage` を保持するため大容量でメモリ圧迫。読み取り時もデコードコストが発生 | デコード / エンコードはメインスレッド外で行う。サイズ上限とタイムアウトを設計する |
| 画像を Data 化する判断 | `setData(_:forPasteboardType:)` + PNG/JPEG は**相互運用する表現形式を明示的に選ぶための手段**であり、メモリ削減を一般には保証しない。`pngData()` / `jpegData(compressionQuality:)` は再エンコード中に `UIImage` と `Data` を同時保持するため、ピークメモリと CPU が増える場合がある | 「受信側が期待する形式を確定させたい」「元データが既に `Data` である」場合に Data 経路を選ぶ。メモリ目的で採用する場合は画像サイズ・形式ごとにエンコード時間とピークメモリを実機計測してから決める（要検証・DoD に計測項目を追加） |
| 複数表現型の扱い | 1 アイテムに複数 UTI を持たせられるため、受信側が期待する型を取り違えると nil になる | `types` / `contains(pasteboardTypes:)` で型を確認してから読み取る |
| `setValue` が既存アイテムを置換 | 公式に「Calling this method replaces any items currently in the pasteboard」とある。追加のつもりで呼ぶと既存内容が消える | 追加は `addItems(_:)`、複数表現型は `items` への辞書設定を使う。公開 API 名で「置換」であることを明示する |
| `NSItemProvider` ロードの完了スレッド | `loadObject` / `loadDataRepresentation` の completion はメインスレッド保証がない。UI 更新をそのまま行うとクラッシュ | ブリッジ層でメインスレッドへディスパッチしてから呼び出し側へ返す |
| `loadFileRepresentation` の一時 URL 寿命 | completion ブロックを抜けると一時ファイルが削除される | ブロック内で `FileManager` によりコピーしてから返す |
| `NSItemProvider` ロードのキャンセル漏れ | `Progress` を保持していないと画面破棄後もロードが継続する | 返却された `Progress` を保持し、破棄時に `cancel()` する。キャンセル時のエラーを正常系として扱う |
| 変更監視の二重開始 | 監視オブジェクトの `start` を複数回呼ぶと、旧オブザーバを解除しないまま上書きして重複通知とリークになる | `start` の冒頭で `stop()` を呼ぶ（または開始済みなら再登録しない）。`deinit` でも解除する |
| `isPersistent` の非推奨 | iOS 10 以降、名前付きペーストボードは非永続。`isPersistent` / `setPersistent(_:)` は非推奨 | 使用しない。永続共有が必要なら App Group shared container を使い、名前付きペーストボードは双方のプロセス生存中の一時転送のみに限定する |
| 名前付きペーストボードは非永続 | 公式に「existing only until the app quits」と明記。作成側アプリが終了すると内容ごと消える。App Group ID を名前に使っても永続化されない | 用途を「双方が生存している間の一時転送」に限定する。作成側終了後も必要なデータは App Group shared container（`FileManager.containerURL(forSecurityApplicationGroupIdentifier:)`）へ分離し、Clipboard 機能の責務外とする |
| 名前付きペーストボードの共有制約 | 他アプリとの共有には同一 Team ID と App Group エンタイトルメントが必要 | App Group ID をペーストボード名に使う（共有スコープの確立が目的であり永続化のためではない）。ツールキット利用側に `com.apple.security.application-groups` の設定を要求する旨をマニュアルに記載 |
| 永続共有の設計ミス | 名前付きペーストボードを永続共有手段として採用すると、受信アプリ起動時に既にデータが消えている不具合になる | 公開 API のドキュメントに寿命を明記し、サンプルアプリで「送信側終了後は取得できない」ことを実演する |
| `UIPasteboardNameFind` の廃止 | Find ペーストボードは廃止済み | 使用しない |
| `ChangedMessage` / `RemovedMessage` は iOS 26 | 最小サポート iOS 18 では利用不可 | 通知名ベースの API を使用する |

---

## プライバシー挙動のテスト行列（iOS 14 通知 / iOS 16 プロンプトの切り分け）

各セルは実機で観測して埋める。事前の期待値は公式記述からの推定であり、断定しない（要検証）。

観測は 2 系統を**別の列**で記録する。混同すると「プロンプトが出ない＝通知も出ない」と誤判定する。

- **許可プロンプト**: iOS 16+ の読み取り前ダイアログ
- **アクセス通知**: iOS 14+ の読み取り後バナー（「〇〇からペースト」）

各ケースは **iOS 18 と iOS 26 の双方**で観測し、OS バージョンとともに記録する。

| # | 直前の状況 | 実行する操作 | 期待: 許可プロンプト | 期待: アクセス通知 | 観測（iOS 18） | 観測（iOS 26） |
|---|---|---|---|---|---|---|
| 1 | 自アプリでコピーした直後 | `general.string` を読む | 出ない可能性（ユーザー意図が認定される） | 出ない可能性 | 未計測 | 未計測 |
| 2 | 他アプリでコピーされた内容 | `general.string` を読む | 出る見込み | 承認後に出る見込み | 未計測 | 未計測 |
| 3 | 他アプリでコピーされた内容 | `hasStrings` / `numberOfItems` / `types` / `types(forItemSet:)` / `itemSet` のみ（公式が非対象と列挙する API） | 出ない（公式列挙） | 出ない（公式列挙） | 未計測 | 未計測 |
| 4 | 他アプリでコピーされた内容 | `changeCount` のみ読む（公式列挙外） | 出ない見込みだが公式保証なし | 同左 | 未計測 | 未計測 |
| 5 | 他アプリでコピーされた内容 | `detectedPatterns(for:)` | 出ない（公式列挙） | 出ない（公式列挙） | 未計測 | 未計測 |
| 6 | 他アプリでコピーされた内容 | `detectedValues(for:)` | 出ない（値は取得できる） | 出ない | 未計測 | 未計測 |
| 7 | 他アプリでコピーされた内容 | `UIPasteControl` をタップ | 出ない（公式に「paste without a user prompt」） | **公式保証なし。要観測** | 未計測 | 未計測 |
| 8 | 他アプリでコピーされた内容 | 標準の編集メニューの「ペースト」 | 出ない見込み | 要観測 | 未計測 | 未計測 |
| 9 | 一度承認した直後に再度読む | `general.string` を再読 | 再表示の有無を確認 | 同左 | 未計測 | 未計測 |
| 10 | バックグラウンド復帰直後 | `changeCount` 比較 → 変化ありなら読み取り | 読み取り時に出る見込み | 同左 | 未計測 | 未計測 |
| 11 | Universal Clipboard 経由（他デバイスでコピー） | `hasStrings` → `string` | 転送待ちの遅延とあわせて確認 | 同左 | 未計測 | 未計測 |
| 12 | 他アプリでコピーされた内容 | `contains(pasteboardTypes:)` のみ（公式列挙外） | 出ない見込みだが公式保証なし | 同左 | 未計測 | 未計測 |
| 13 | 他アプリでコピーされた内容 | `itemProviders` **getter のみ**（ロードしない） | 取得時点が契機かを切り分ける | 同左 | 未計測 | 未計測 |
| 14 | ケース 13 の直後 | 取得済み provider に対し `canLoadObject(ofClass:)` のみ実行（公式列挙 API） | 型判定自体では出ない（公式列挙） | 同左 | 未計測 | 未計測 |
| 15 | ケース 14 の直後 | 取得済み provider に対し `loadObject` / `loadDataRepresentation` を実行 | ロード時が契機かを切り分ける | 同左 | 未計測 | 未計測 |
| 16 | 他アプリでコピーされた内容 | `UIPasteControl` タップ → `paste(itemProviders:)` 内でロード | 経路全体で出ないか | **プロンプトなしでも通知が出る可能性を要観測** | 未計測 | 未計測 |

ケース 12〜16 は、事前判定 API の安全性（12）、`itemProviders` getter（13）、公式列挙済みの provider 型判定（14）、データロード（15）の契機を分離し、`UIPasteControl` 経路（16）と比較することを目的とする。ケース 7・16 は「許可プロンプト回避＝アクセス通知も回避」ではない可能性を確認する。

---

## 簡単なサンプルコード集（サブ機能別）

### ペーストボード取得

```swift
import UIKit

// システム全体の汎用ペーストボード（唯一の永続ペーストボード）
let general = UIPasteboard.general

// 同一 Team ID のアプリ間で「一時的に」データを渡すための名前付きペーストボード。
// 注意: これは非永続で、作成したアプリが終了すると消える（永続共有には使えない）。
// App Group entitlement が必要なのは共有スコープの確立が目的であり、永続化のためではない。
func transientSharedPasteboard(appGroupId: String) -> UIPasteboard? {
    UIPasteboard(name: UIPasteboard.Name(appGroupId), create: true)
}

// アプリ内専用のユニーク名ペーストボード（同じく非永続。使い終わったら破棄する）
func makeScratchPasteboard() -> UIPasteboard {
    UIPasteboard.withUniqueName()
}

func disposeScratchPasteboard(_ pasteboard: UIPasteboard) {
    UIPasteboard.remove(withName: pasteboard.name)  // general には無効
}
```

作成側アプリの終了後も残す必要があるデータは、ペーストボードではなく App Group shared container に置く（Clipboard 機能の責務外）。

```swift
// 責務境界の参考: 永続共有はこちらで扱う（本機能では提供しない）
func sharedContainerURL(appGroupId: String) -> URL? {
    FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId)
}
```

### 文字列のコピー

```swift
func copyPlainText(_ text: String) {
    UIPasteboard.general.string = text
    // iOS はコピー完了の標準 UI を出さないため、アプリ側でフィードバックを表示する
}

// Universal Clipboard へ流さず、5 分で自動失効させる場合
func copySensitiveText(_ text: String) {
    let item: [String: Any] = [UTType.plainText.identifier: text]
    UIPasteboard.general.setItems(
        [item],
        options: [
            .localOnly: true,
            .expirationDate: Date().addingTimeInterval(300)
        ]
    )
}
```

`UTType` は `import UniformTypeIdentifiers` が必要。

### URL / 画像 / 色のコピー

```swift
func copyURL(_ url: URL) {
    UIPasteboard.general.url = url
}

func copyImage(_ image: UIImage) {
    UIPasteboard.general.image = image
}

// 受信側に渡す表現形式を明示的に確定させたい場合は Data で書き込む。
// 注意: pngData() は再エンコード中に UIImage と Data を同時保持するため、
// メモリ削減になるとは限らない（ピークメモリ・時間は実機計測で判断する）。
func copyImageAsPNG(_ image: UIImage) {
    guard let png = image.pngData() else { return }
    UIPasteboard.general.setData(png, forPasteboardType: UTType.png.identifier)
}

func copyColor(_ color: UIColor) {
    UIPasteboard.general.color = color
}
```

### 任意 UTI データのコピー / 複数アイテムのコピー

```swift
// アプリ独自型は逆 DNS 表記の UTI を使う
let customType = "com.jonghyunkim.nativetoolkit.custom-payload"

func copyCustom(_ payload: Data) {
    UIPasteboard.general.setData(payload, forPasteboardType: customType)
}

// 1 アイテムに複数表現型を持たせる（受信側が扱える型を選べる）
func copyMultiRepresentation(text: String, html: String) {
    let item: [String: Any] = [
        UTType.plainText.identifier: text,
        UTType.html.identifier: html
    ]
    UIPasteboard.general.items = [item]
}

// 複数アイテムのコピー
func copyMultipleTexts(_ texts: [String]) {
    UIPasteboard.general.strings = texts
}
```

### NSItemProvider によるコピー

```swift
func copyObjects(_ image: UIImage, text: String) {
    UIPasteboard.general.setObjects(
        [image, text as NSString] as [any NSItemProviderWriting],
        localOnly: false,
        expirationDate: nil
    )
}

func copyItemProviders(_ providers: [NSItemProvider]) {
    UIPasteboard.general.setItemProviders(providers, localOnly: true, expirationDate: nil)
}
```

### NSItemProvider 経由のペースト（型判定・非同期ロード・キャンセル）

設計上の契約（この 6 点を公開 API の仕様として固定する）:

1. **completion は必ず 1 回だけ、メインスレッドから返す**。対象は成功・provider エラー・型不一致・provider 不在・明示キャンセル・**loader 解放を含む全経路**。provider 不在の即時失敗も同期実行せずメインへディスパッチする。
2. **キャンセル時は `cancelAll()` または `deinit` が `.cancelled` を各リクエストへ 1 回だけ返す**（0 回ではない）。`Progress.cancel()` が公式に保証するのは cancellation handler の実行と `isCancelled` の更新のみで「completion が呼ばれないこと」ではないため、その後に provider から届いた結果はリクエスト ID の gate で破棄する（利用側へは通知しない = 通知は既に 1 回済んでいる）。
3. **リクエストは発行時点で管理表に登録する**。provider 不在で main queue へ失敗を積んだ直後の `cancelAll()` でも、そのコールバックがキャンセル対象になるようにする。
4. **ファイルコピーは失敗を成功にしない**。provider の `error`、nil URL、コピー失敗をそれぞれ区別して返す。
5. **保存ファイル名は外部由来の `suggestedName` をそのまま使わない**。UUID を基礎に生成し、許可リストで検証した拡張子のみを付与する。生成した destination が専用ディレクトリ配下であることを標準化パスで確認する。
6. **一時ディレクトリの後始末は全経路で行う**。失敗・キャンセル・loader 解放時はツールキット側がディレクトリごと削除する。成功時のみ所有権が呼び出し側へ移り、削除責務も呼び出し側になる（API ドキュメントに明記）。

```swift
import UIKit
import UniformTypeIdentifiers

enum ClipboardLoadError: Error {
    case noMatchingItem          // 該当する provider がない
    case providerFailed(Error)   // provider 側のロード失敗
    case unexpectedType          // 型不一致
    case fileCopyFailed(Error)   // 一時ファイルのコピー失敗
    case cancelled               // cancelAll() または loader 解放による中断
}

@MainActor
final class ItemProviderLoader {
    private struct FileRequest {
        let deliver: (Result<URL, ClipboardLoadError>) -> Void
        var progress: Progress?
    }

    private struct TextRequest {
        let deliver: (Result<String, ClipboardLoadError>) -> Void
        var progress: Progress?
    }

    private var nextId = 0
    private var fileRequests: [Int: FileRequest] = [:]
    private var textRequests: [Int: TextRequest] = [:]

    // 成功時に返る URL とその親ディレクトリの削除は呼び出し側の責務
    func loadFirstImageFile(completion: @escaping (Result<URL, ClipboardLoadError>) -> Void) {
        let type = UTType.image.identifier
        let id = nextId
        nextId += 1
        // provider 不在の経路も cancelAll の対象にするため、先に登録する
        fileRequests[id] = FileRequest(deliver: completion)

        guard let provider = UIPasteboard.general.itemProviders.first(
            where: { $0.hasItemConformingToTypeIdentifier(type) }
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.finish(id: id, outcome: .failure(.noMatchingItem), workDirectory: nil)
            }
            return
        }

        // Sendable completion へ NSItemProvider 自体を捕捉しないよう、必要な値だけ先に取り出す
        let suggestedExtension = (provider.suggestedName as NSString?)?.pathExtension ?? ""
        let progress = provider.loadFileRepresentation(forTypeIdentifier: type) { [weak self] url, error in
            // 一時 URL はこのブロックを抜けると無効になるため、ここでコピーする
            var workDirectory: URL?
            let outcome: Result<URL, ClipboardLoadError>
            if let error {
                outcome = .failure(.providerFailed(error))
            } else if let url {
                let dir = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                workDirectory = dir
                // 外部アプリ由来の suggestedName はそのまま使わない（下記 safeFileName 参照）
                let dest = dir.appendingPathComponent(
                    Self.safeFileName(url: url, suggestedExtension: suggestedExtension)
                )
                do {
                    guard Self.isContained(dest, in: dir) else { throw CocoaError(.fileWriteInvalidFileName) }
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: dest)
                    outcome = .success(dest)   // コピー成功時のみ success
                } catch {
                    outcome = .failure(.fileCopyFailed(error))
                }
            } else {
                outcome = .failure(.unexpectedType)
            }
            let captured = workDirectory
            DispatchQueue.main.async {
                guard let self else {
                    Self.cleanup(captured)   // loader 解放時もディレクトリごと後始末する
                    return
                }
                self.finish(id: id, outcome: outcome, workDirectory: captured)
            }
        }
        fileRequests[id]?.progress = progress
    }

    private func finish(
        id: Int,
        outcome: Result<URL, ClipboardLoadError>,
        workDirectory: URL?
    ) {
        guard let request = fileRequests.removeValue(forKey: id) else {
            // キャンセル済み: .cancelled は通知済みなので結果は破棄し、ディレクトリを削除
            Self.cleanup(workDirectory)
            return
        }
        if case .failure = outcome {
            Self.cleanup(workDirectory)   // 空ディレクトリを残さない
        }
        // 成功時はディレクトリの所有権が呼び出し側へ移る
        request.deliver(outcome)
    }

    // キャンセル時も completion を 1 回だけ返す（@MainActor なので main 上で実行される）
    func cancelAll() {
        let pendingFiles = fileRequests
        let pendingTexts = textRequests
        fileRequests.removeAll()
        textRequests.removeAll()
        for request in pendingFiles.values {
            request.progress?.cancel()
            request.deliver(.failure(.cancelled))
        }
        for request in pendingTexts.values {
            request.progress?.cancel()
            request.deliver(.failure(.cancelled))
        }
    }

    // self が無くても、バックグラウンドからも呼べるよう nonisolated static にする
    // （@MainActor をクラスに付けると static メンバーも隔離されるため明示が必要）
    nonisolated private static func cleanup(_ directory: URL?) {
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
    }

    // 外部由来の名前は信頼しない。UUID を基礎にし、許可リストの拡張子だけを付与する
    nonisolated private static func safeFileName(
        url: URL,
        suggestedExtension: String
    ) -> String {
        let allowed: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "webp"]
        let ext = [url.pathExtension, suggestedExtension]
            .map { $0.lowercased() }
            .first { allowed.contains($0) } ?? "img"
        return "\(UUID().uuidString).\(ext)"
    }

    // 標準化したパスが専用ディレクトリ配下であることを確認する（path traversal 防止）
    nonisolated private static func isContained(_ dest: URL, in directory: URL) -> Bool {
        let base = directory.standardizedFileURL.path
        return dest.standardizedFileURL.path.hasPrefix(base.hasSuffix("/") ? base : base + "/")
    }

    // テキストは型別の管理表で同じ gate / exactly-once 契約を実装する
    func loadFirstText(completion: @escaping (Result<String, ClipboardLoadError>) -> Void) {
        let id = nextId
        nextId += 1
        textRequests[id] = TextRequest(deliver: completion)

        guard let provider = UIPasteboard.general.itemProviders.first(
            where: { $0.canLoadObject(ofClass: NSString.self) }
        ) else {
            DispatchQueue.main.async { [weak self] in
                self?.finishText(id: id, outcome: .failure(.noMatchingItem))
            }
            return
        }

        let progress = provider.loadObject(ofClass: NSString.self) { [weak self] object, error in
            let outcome: Result<String, ClipboardLoadError>
            if let error {
                outcome = .failure(.providerFailed(error))
            } else if let text = object as? NSString {
                outcome = .success(text as String)
            } else {
                outcome = .failure(.unexpectedType)
            }
            DispatchQueue.main.async { self?.finishText(id: id, outcome: outcome) }
        }
        textRequests[id]?.progress = progress
    }

    private func finishText(
        id: Int,
        outcome: Result<String, ClipboardLoadError>
    ) {
        guard let request = textRequests.removeValue(forKey: id) else {
            // キャンセル済み: .cancelled は通知済みなので遅延結果を破棄する
            return
        }
        request.deliver(outcome)
    }

    // @MainActor のインスタンスは main actor で破棄される。
    // 明示的な cancelAll() なしで所有者が解放しても pending callback を 0 回にしない。
    deinit {
        for request in fileRequests.values {
            request.progress?.cancel()
            request.deliver(.failure(.cancelled))
        }
        for request in textRequests.values {
            request.progress?.cancel()
            request.deliver(.failure(.cancelled))
        }
    }
}
```

テキストの読み取りはファイルを伴わないため cleanup は不要だが、型別の request 管理表を使って同じ「登録 → gate → 1 回配信 → キャンセル時 `.cancelled`」の規約に従う。loader の解放もキャンセルとして扱い、pending completion へ `.cancelled` を返す。

Swift 6 対応の注意: v4 サンプルは `NSItemProvider` 自体を `@Sendable` completion に捕捉せず、必要な拡張子文字列だけを事前取得する。Xcode 26.3 / iPhoneSimulator 26.2 SDK では Swift 5 通常設定と Swift 6 strict concurrency の双方で警告なしに型チェック済み。実装時も同じ build setting で回帰確認し、公開 API は `withCheckedThrowingContinuation` で包んだ async 版も検討する。

### 内容確認（アラートを出さない事前判定）

```swift
func clipboardSummary() -> String {
    let pb = UIPasteboard.general
    var kinds: [String] = []
    // has* / numberOfItems は公式が「通知・アラートを避ける API」として列挙している
    if pb.hasStrings { kinds.append("string") }
    if pb.hasURLs { kinds.append("url") }
    if pb.hasImages { kinds.append("image") }
    if pb.hasColors { kinds.append("color") }
    return "items=\(pb.numberOfItems) kinds=\(kinds.joined(separator: ","))"
}

// 注意: contains(pasteboardTypes:) は公式の「通知・アラートを避ける API」列挙に含まれない。
// 通知非対象であることは未保証のため、実機観測（テスト行列ケース 12）で確認してから採用する。
func containsCustomType() -> Bool {
    UIPasteboard.general.contains(
        pasteboardTypes: ["com.jonghyunkim.nativetoolkit.custom-payload"]
    )
}

func indexesHavingImages() -> IndexSet? {
    UIPasteboard.general.itemSet(withPasteboardTypes: UIPasteboard.typeListImage as! [String])
}
```

### 文字列のペースト

```swift
// iOS 16 以降、この読み取りは貼り付け許可アラートを表示しうる
func pasteText() -> String? {
    let pb = UIPasteboard.general
    guard pb.hasStrings else { return nil }  // 事前判定でムダな読み取りを避ける
    return pb.string
}

func pasteURL() -> URL? {
    let pb = UIPasteboard.general
    guard pb.hasURLs else { return nil }
    return pb.url
}
```

### 任意 UTI データのペースト

```swift
func pasteCustom() -> Data? {
    let type = "com.jonghyunkim.nativetoolkit.custom-payload"
    let pb = UIPasteboard.general
    guard pb.contains(pasteboardTypes: [type]) else { return nil }
    return pb.data(forPasteboardType: type)
}

// 複数アイテムから指定型のみを取り出す
func pasteAllTexts() -> [String] {
    let type = UTType.plainText.identifier
    let pb = UIPasteboard.general
    guard let set = pb.itemSet(withPasteboardTypes: [type]),
          let values = pb.values(forPasteboardType: type, inItemSet: set) else { return [] }
    return values.compactMap { $0 as? String }
}
```

### クリップボードのクリア

```swift
func clearClipboard() {
    UIPasteboard.general.items = []
}

// 名前付きペーストボードは破棄することでクリアできる
func removeNamedPasteboard(_ name: String) {
    UIPasteboard.remove(withName: UIPasteboard.Name(name))
}
```

### 変更監視（通知 + changeCount ポーリング）

```swift
enum ClipboardWatchEvent {
    case changed(typesAdded: [String], typesRemoved: [String])
    case removed
}

@MainActor
final class ClipboardWatcher {
    private var changedToken: NSObjectProtocol?
    private var removedToken: NSObjectProtocol?
    private var pasteboard: UIPasteboard?
    private var lastChangeCount = 0
    private var onEvent: ((ClipboardWatchEvent) -> Void)?
    private var generation = 0

    func start(
        pasteboard: UIPasteboard = .general,
        onEvent: @escaping (ClipboardWatchEvent) -> Void
    ) {
        stop()  // 二重開始で旧 observer が解除されずリークするのを防ぐ
        // 再開時に基準値を再同期する（停止中の変更を古い基準と比較しない）
        self.pasteboard = pasteboard
        self.onEvent = onEvent
        lastChangeCount = pasteboard.changeCount
        let generation = self.generation
        changedToken = NotificationCenter.default.addObserver(
            forName: UIPasteboard.changedNotification,
            object: pasteboard,
            queue: .main
        ) { [weak self] note in
            let added = note.userInfo?[UIPasteboard.changedTypesAddedUserInfoKey] as? [String] ?? []
            let removed = note.userInfo?[UIPasteboard.changedTypesRemovedUserInfoKey] as? [String] ?? []
            Task { @MainActor [weak self] in
                guard let self,
                      self.generation == generation,
                      let pasteboard = self.pasteboard else { return }
                // 通知で報告した変更を foreground 比較で二重報告しないよう基準値を進める
                self.lastChangeCount = pasteboard.changeCount
                self.onEvent?(.changed(typesAdded: added, typesRemoved: removed))
            }
        }
        removedToken = NotificationCenter.default.addObserver(
            forName: UIPasteboard.removedNotification,
            object: pasteboard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == generation else { return }
                self.onEvent?(.removed)
            }
        }
    }

    // 他アプリによる変更やバックグラウンド中の変更は通知されないため、
    // フォアグラウンド復帰時に changeCount を比較する。
    // changeCount は本体を読まないが、公式の「通知・アラートを避ける API」列挙には
    // 含まれないため、実機観測（テスト行列ケース 4）で確認してから採用する。
    func checkOnForeground() -> Bool {
        guard let pasteboard else { return false }
        let current = pasteboard.changeCount
        defer { lastChangeCount = current }
        return current != lastChangeCount
    }

    // 二重停止しても安全。generation を進め、既に queue 済みの旧 callback も無効化する。
    func stop() {
        generation += 1
        if let changedToken { NotificationCenter.default.removeObserver(changedToken) }
        if let removedToken { NotificationCenter.default.removeObserver(removedToken) }
        changedToken = nil
        removedToken = nil
        pasteboard = nil
        onEvent = nil
    }

    deinit {
        if let changedToken { NotificationCenter.default.removeObserver(changedToken) }
        if let removedToken { NotificationCenter.default.removeObserver(removedToken) }
    }
}
```

`changeCount` の同期規則（設計時に固定する）:

- `start()` 時に基準値を再同期する（停止中の変更を古い基準と比較しない）
- `changedNotification` 受信時に基準値を進める（通知経路で報告済みの変更を foreground 比較で再報告しない）
- `changedTypesAddedUserInfoKey` と `changedTypesRemovedUserInfoKey` を同じイベントで返す
- 名前付きペーストボードの `removedNotification` を独立した `.removed` イベントで返す
- `checkOnForeground()` は比較後に必ず基準値を更新する
- `@MainActor` により token と `lastChangeCount` の全操作をメインスレッドへ固定する
- generation gate により、stop / start 前の queue 済み callback を新しい購読者へ誤配信しない
- 上記により、同一の変更が通知経路と foreground 比較経路で二重に報告されないことを DoD で検証する

### パターン検出（ユーザー通知なしで内容種別を判定）

```swift
import UIKit
import DataDetection

// パターンの有無のみ判定する（値は取得しない）
func detectPatterns() async {
    let patterns: Set<PartialKeyPath<UIPasteboard.DetectedValues>> = [
        \.probableWebURL, \.phoneNumbers, \.emailAddresses
    ]
    do {
        let found = try await UIPasteboard.general.detectedPatterns(for: patterns)
        print("hasURL=\(found.contains(\.probableWebURL))")
    } catch {
        print("detect failed: \(error)")
    }
}

// 値まで取得する
func detectValues() async {
    do {
        let values = try await UIPasteboard.general.detectedValues(
            for: [\.probableWebURL, \.emailAddresses]
        )
        print("url=\(values.probableWebURL) emails=\(values.emailAddresses.count)")
    } catch {
        print("detect failed: \(error)")
    }
}
```

### UIPasteControl（許可アラートを出さない貼り付けボタン）

```swift
import UIKit
import UniformTypeIdentifiers

final class PasteReceiverViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        // 受け入れ可能な型を responder に宣言する（未設定だとボタンが反応しない）
        pasteConfiguration = UIPasteConfiguration(acceptableTypeIdentifiers: [
            UTType.plainText.identifier,
            UTType.image.identifier
        ])

        let config = UIPasteControl.Configuration()
        config.displayMode = .iconAndLabel
        config.cornerStyle = .capsule

        let control = UIPasteControl(configuration: config)
        control.target = self          // UIPasteConfigurationSupporting 準拠が必要
        control.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(control)

        // 制約を張らないと位置とサイズが確定せず表示されない
        NSLayoutConstraint.activate([
            control.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            control.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24
            )
        ])
    }

    // acceptableTypeIdentifiers で宣言した型を、判定・ロードの両方で扱う
    override func canPaste(_ itemProviders: [NSItemProvider]) -> Bool {
        itemProviders.contains {
            $0.canLoadObject(ofClass: NSString.self) || $0.canLoadObject(ofClass: UIImage.self)
        }
    }

    override func paste(itemProviders: [NSItemProvider]) {
        for provider in itemProviders {
            // 型の優先順位: テキストを優先し、なければ画像を試す
            if provider.canLoadObject(ofClass: NSString.self) {
                provider.loadObject(ofClass: NSString.self) { object, error in
                    DispatchQueue.main.async {
                        if let error { print("text load failed: \(error)"); return }
                        guard let text = object as? NSString else { return }
                        print("pasted text: \(text)")
                    }
                }
            } else if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { object, error in
                    DispatchQueue.main.async {
                        if let error { print("image load failed: \(error)"); return }
                        guard let image = object as? UIImage else { return }
                        print("pasted image: \(image.size)")
                    }
                }
            }
            // どちらも不可の provider はスキップ（部分失敗は他 provider の処理を止めない）
        }
    }
}
```

複数 provider を扱う場合の仕様（設計時に確定させる）:

- 型の優先順位: テキスト > 画像（上記サンプルの方針）
- 部分失敗: 1 つの provider のロードに失敗しても他の provider の処理は継続する
- 完了通知: 全 provider の処理完了をどう利用側へ通知するか（個別通知 / 集約通知）

---

## 要検証事項

| 項目 | 内容 |
|---|---|
| 許可アラート / アクセス通知の発生条件 | 上記「プライバシー挙動のテスト行列」16 パターンを iOS 18 / iOS 26 実機で実測し、iOS 14 のアクセス通知（読み取り後バナー）と iOS 16 の許可アラート（読み取り前ダイアログ）のどちらが出るかを区別して記録する |
| `contains(pasteboardTypes:)` / `changeCount` の通知非対象性 | 公式の「通知・アラートを避ける API」列挙に含まれないため、ケース 4・12 で個別に観測し、事前判定 API として採用可能か判断する |
| `itemProviders` の通知契機 | getter 取得時点（ケース 13）、`canLoadObject` 型判定（ケース 14）、ロード実行時（ケース 15）のどこが契機かを切り分ける |
| `Progress.cancel()` 後のキャンセル契約全般 | provider 実装ごとにキャンセル後 completion が呼ばれるか、呼ばれる場合のエラードメイン / コードは何か。リクエスト ID の gate が遅延結果を確実に破棄するか。破棄時に一時ディレクトリが残らないか。（旧・重複していた 2 項目を統合） |
| 外部由来ファイル名の安全性 | `suggestedName` にパス区切り・`..`・制御文字・極端に長い名前が含まれるケースを人為的に作り、`safeFileName` / `isContained` が専用ディレクトリ外への書き出しを防ぐことを確認する |
| 一時ディレクトリの残留 | 失敗・キャンセル・loader 解放・アプリ強制終了の各経路で UUID ディレクトリが残らないことを確認する（残る経路がある場合は起動時の一括クリーンアップを設計する） |
| `loadItem` の非推奨バージョン | Swift の async 版へ置換された正確な非推奨バージョン（ドキュメントの platform 情報に記載がないため SDK header で確認する） |
| Swift 6 strict concurrency | `SWIFT_VERSION = 6` 相当の設定で `ItemProviderLoader` をビルドし、`@Sendable` completion 内の非 Sendable 捕捉に関する警告有無と、`withCheckedThrowingContinuation` による async 化で解消するかを確認する |
| `detectPatterns` / `detectValues` のアラート有無 | 非推奨版のドキュメントには「without notifying the user」とある。キーパス版でも iOS 18 実機で通知・アラートが出ないことを確認する |
| 名前付きペーストボードの寿命 | 送信側アプリを終了・強制終了した後に、受信側から `init(name:create:false)` で取得できないことを実機確認する。バックグラウンド状態（未終了）では取得できることも併せて確認 |
| `NSItemProvider` ロードの完了スレッド | `loadObject` / `loadDataRepresentation` / `loadFileRepresentation` の completion がどのスレッドで呼ばれるか実測し、メインディスパッチの要否を確定する |
| `loadFileRepresentation` の一時 URL 寿命 | completion を抜けた後に URL が無効化されるタイミング |
| 画像の Data 化コスト | 画像サイズ・形式別に `pngData()` / `jpegData(compressionQuality:)` のエンコード時間とピークメモリを Instruments で計測し、`image` プロパティ直接設定との優劣を判断する |
| `changedNotification` の配信条件 | 他アプリによる変更・バックグラウンド中・Universal Clipboard 経由の変更で配信されるか |
| `string = nil` の挙動 | 文字列プロパティへの nil 代入がクリアになるか、無視されるか（クリアは `items = []` を正とする） |
| `expirationDate` の実効性 | 過去日時・短い有効期限を指定した場合の削除タイミング |
| `UIPasteControl` の非表示・無効時の挙動 | クリップボードが空のときのボタン状態、`target` 未設定時の挙動 |
| App Group 名前付きペーストボード | 同一 Team ID の別アプリ間で実際に読み書きできるかと、必要なエンタイトルメント（`com.apple.security.application-groups`）の設定範囲 |
| `setValue(_:forPasteboardType:)` の受け入れ型 | 公式が列挙する `NSString` / `NSArray` / `NSDictionary` / `NSDate` / `NSNumber` / `UIImage` / `NSURL` 以外を渡した際に例外か無視か |
| `DetectedValues.probableWebURL` の未検出値 | 未検出時に空文字が返るのか、`patterns` に含まれないだけなのか |

---

## Definition of Done

### コピー / ペースト

- [ ] 文字列のコピー / ペーストが動作する（iOS 18 実機・シミュレータ）
- [ ] URL・画像・色のコピー / ペーストが動作する
- [ ] 任意 UTI（アプリ独自型）の `Data` コピー / ペーストが動作する
- [ ] 1 アイテム複数表現型のコピーと、受信側での型選択が動作する
- [ ] 複数アイテム（`strings` / `items`）のコピー / ペーストが動作する
- [ ] `setValue(_:forPasteboardType:)` が既存アイテムを置換すること、`addItems(_:)` が追加であることを区別して確認済み
- [ ] `items = []` でクリップボードがクリアされる

### NSItemProvider 経由の読み取り

- [ ] `itemProviders` から `canLoadObject` / `hasItemConformingToTypeIdentifier` で型判定できる
- [ ] `loadObject` / `loadDataRepresentation` でテキスト・画像を非同期取得できる
- [ ] **成功・provider エラー・型不一致・provider 不在・キャンセルの全経路**で、completion がメインスレッドから**一度だけ**返る（provider 不在の即時失敗も同期実行しない）
- [ ] `cancelAll()` が各リクエストへ `.cancelled` を**1 回**返す（0 回でも 2 回でもない）
- [ ] `cancelAll()` 後に provider から遅延到着した結果が利用側へ通知されない（通知は `.cancelled` の 1 回のみ）
- [ ] provider 不在で main queue へ失敗を積んだ直後の `cancelAll()` でも、そのコールバックがキャンセル対象になり `.cancelled` が 1 回だけ返る
- [ ] loader を明示的に `cancelAll()` せず解放した場合も、全 pending completion に `.cancelled` がメインスレッドから 1 回だけ返る
- [ ] `loadFileRepresentation` の一時 URL を completion 内で UUID 付き専用ディレクトリへコピーし、抜けた後も利用できる
- [ ] コピー失敗（容量不足など）が `success` として返らず、`fileCopyFailed` として区別される
- [ ] provider の `error` と nil URL がそれぞれ区別して返る
- [ ] `suggestedName` にパス区切り・`..`・制御文字・長大な名前が含まれても、専用ディレクトリ外へ書き出されない（`safeFileName` / `isContained` の検証）
- [ ] 失敗・キャンセル・loader 解放の各経路で UUID 一時ディレクトリが残らない（空ディレクトリも残らない）
- [ ] 成功時のみディレクトリの所有権が呼び出し側へ移り、削除責務が呼び出し側にあることを公開 API ドキュメントに明記した
- [ ] ロード中に `Progress.cancel()` を呼べる
- [ ] 完了したリクエストが管理構造から除去され、長時間稼働で `Progress` が蓄積しない
- [ ] ロード失敗・型不一致時に `NSItemProvider.errorDomain` / `ErrorCode` でエラー種別を判別できる

### 名前付き / ユニーク名ペーストボード

- [ ] `init(name:create:true)` で作成、`init(name:create:false)` で取得できる
- [ ] 未作成の名前に対して `create: false` を渡すと nil が返る
- [ ] `withUniqueName()` で作成したペーストボードに読み書きでき、`name` が取得できる
- [ ] `remove(withName:)` 後にそのペーストボードへの操作が無視される
- [ ] `remove(withName:)` を general に対して呼んでも影響がない
- [ ] App Group entitlement を設定した同一 Team ID の別アプリから、送信側が生存中に読み取れる
- [ ] **送信側アプリ終了後は取得できない**ことを確認済み（非永続であることの実証）
- [ ] 永続共有が必要なケースを App Group shared container に分離し、Clipboard 機能の責務外であることをドキュメントに明記した

### プライバシー

- [ ] 「プライバシー挙動のテスト行列」16 パターンを iOS 18 / iOS 26 の双方の実機で実測し、iOS 14 アクセス通知と iOS 16 許可アラートを区別して結果を記録した（出る／出ないの断定はせず観測値を記載）
- [ ] 公式が非対象と列挙する API（`numberOfItems` / `types` / `types(forItemSet:)` / `itemSet(withPasteboardTypes:)` / `has*` / `canLoadObject(ofClass:)` / パターン検出）のみの使用で通知・アラートが観測されないことを記録した
- [ ] 公式列挙外の `contains(pasteboardTypes:)`（ケース 12）と `changeCount`（ケース 4）を個別に観測し、結果と OS バージョンを記録した上で採用可否を判断した
- [ ] `itemProviders` getter（ケース 13）、`canLoadObject` 型判定（ケース 14）、provider ロード（ケース 15）を分けて観測し、通知・プロンプトの契機を特定した
- [ ] `detectedPatterns` / `detectedValues` が動作し、通知・アラートの観測結果を記録した
- [ ] `UIPasteControl` のタップによる貼り付けで、通知・アラートの観測結果を記録した
- [ ] `localOnly` の効果を**正の対照つき**で確認済み: 同一の 2 台・同一 iCloud アカウント・同一 Handoff 設定で、まず `localOnly: false` の転送成功を確認し、続けて `localOnly: true` の非転送を確認する。観測待ち時間、両端の OS バージョン、Bluetooth / Wi-Fi 接続条件も記録する（対照なしでは Handoff 環境の不備と option の効果を区別できない）
- [ ] `expirationDate` 指定時に期限後の内容が取得できないことを確認済み

### 監視・UI・実装品質

- [ ] `changedNotification` の登録・解除ができ、解除後に通知が来ない（リークなし）
- [ ] `changedTypesAddedUserInfoKey` と `changedTypesRemovedUserInfoKey` を区別してイベントへ反映できる
- [ ] 名前付きペーストボードの `removedNotification` を受信でき、解除後には受信しない
- [ ] 監視の二重開始・二重停止・破棄時解除で重複通知とリークが発生しない
- [ ] フォアグラウンド復帰時の `changeCount` 比較で外部変更を検知できる
- [ ] `start()` 時に `changeCount` の基準値が再同期され、stop / start をまたいだ古い基準との比較が起きない
- [ ] `changedNotification` で報告済みの変更が、直後の foreground 比較で**二重報告されない**（通知経路で基準値が進む）
- [ ] `ClipboardWatcher` の全状態操作が main actor 上で行われ、Swift 6 strict concurrency でデータ競合警告がない
- [ ] stop / start 境界で旧 observer callback が既に queue 済みでも、新しい購読者へ古いイベントを誤配信しない
- [ ] `UIPasteControl` が Auto Layout 制約付きで実際に表示され、`target` と `pasteConfiguration` 未設定時の挙動を確認済み
- [ ] `pasteConfiguration.acceptableTypeIdentifiers` で宣言した型を `canPaste` / `paste(itemProviders:)` の両方が扱っている（画像のみのクリップボードでも動作する）
- [ ] 複数 provider 時の型の優先順位と、1 件失敗しても他が継続する部分失敗仕様を確認済み
- [ ] Swift 6 strict concurrency 設定でのビルド警告を確認し、async API 化の要否を判断した
- [ ] 画像の `image` プロパティ設定と `pngData()` / `jpegData(compressionQuality:)` 経由を、代表的な画像サイズでエンコード時間・ピークメモリを計測して比較した
- [ ] 非推奨 API（`isPersistent` / `setPersistent(_:)` / `Set<DetectionPattern>` 版 `detectPatterns` / `detectValues` / `UIPasteboardNameFind`）を使用していない
- [ ] Objective-C / Unity ブリッジから利用する公開 API に、Swift 専用のキーパス型が露出していない
- [ ] サンプルアプリで全サブ機能が確認できる

### テスト確認 OS バージョン

| バージョン | 理由 |
|---|---|
| iOS 18 | 最小サポート。全サブ機能の基準検証 |
| iOS 26 | 最新メジャー版での回帰確認。貼り付け許可アラートの挙動変化、`ChangedMessage` / `RemovedMessage` 追加の影響確認 |

---

## レビュー反映履歴

対象レビュー: `artifact/reviews/clipboard/2026-08-01-ios-clipboard-research-review.md`

### 第 4 回レビュー反映（v4 / 2026-08-01）

| 優先度 | 指摘 | 反映内容 |
|---|---|---|
| 高 | loader 解放時に pending completion が 0 回になり exactly-once 契約が破れる | loader 解放をキャンセル経路として契約に追加。`deinit` で file / text request の `Progress` を cancel し、各 completion へ `.cancelled` を 1 回配信する完全実装と DoD を追加 |
| 高 | `loadFirstText` の helper が未定義でコンパイル不可。コードフェンスも破損 | 重複コードフェンスを削除。`FileRequest` / `TextRequest` の型別管理表、`finishText`、progress 登録、cancel gate を全て実装し、Swift 5 / Swift 6 strict concurrency で型チェック済みの単一サンプルへ変更 |
| 中 | 公式の通知・アラート回避 API 一覧から `types(forItemSet:)` と `canLoadObject(ofClass:)` が欠落 | 公式一覧、テスト行列、DoD に両 API を追加。`itemProviders` getter、`canLoadObject`、データロードをケース 13〜15 に分離し、`UIPasteControl` をケース 16 とした |
| 中 | `removedNotification` / removed types が scope にある一方、Watcher と DoD にない | `ClipboardWatchEvent` を追加し、added / removed types と pasteboard removal を実装。名前付きペーストボードを監視可能にし、登録解除と DoD を追加 |
| 中 | プライバシー行列は iOS 18 / 26 の双方を要求するが DoD は iOS 18 のみ | 16 ケースすべてを iOS 18 / iOS 26 双方で観測する完了条件へ統一 |
| 低 | `ClipboardWatcher` の状態アクセススレッドが未固定 | `@MainActor` を付与し、Sendable な NotificationCenter callback から `Task { @MainActor ... }` で状態更新する形へ変更。Swift 5 / Swift 6 strict concurrency で警告なしに型チェック済み |

### 第 3 回レビュー反映（v3 / 2026-08-01）

| 優先度 | 指摘 | 反映内容 |
|---|---|---|
| 高 | キャンセル時の completion 回数が 1 回か 0 回か矛盾。provider 不在の queued callback がキャンセル対象外 | 契約を「**キャンセルを含む全経路で 1 回だけ返す**」に統一。`cancelAll()` 自身が各リクエストへ `.cancelled` を 1 回配信し、その後の provider 結果は gate で破棄する方式へ変更。リクエストを**発行時点で管理表に登録**し、provider 不在の即時失敗経路もキャンセル対象にした。`ClipboardLoadError.cancelled` を追加。契約を 4 点 → 6 点に拡張し、DoD 3 項目を追加 |
| 中 | 外部由来 `suggestedName` の未検証利用（path traversal / コピー失敗） | 保存名を UUID ベースで生成する `safeFileName` を追加し、拡張子は許可リスト（png / jpg / jpeg / heic / heif / gif / tiff / webp、非該当は `img`）で検証。`isContained` で標準化パスが専用ディレクトリ配下であることを確認。要検証と DoD を追加 |
| 中 | 一時ディレクトリの cleanup 漏れ（キャンセル時・コピー失敗時の空ディレクトリ・loader 解放時） | `workDirectory` をリクエスト結果とともに引き回し、失敗・キャンセル・gate 破棄の全経路でディレクトリ単位に削除。`self == nil` でも動く `static func cleanup` を main queue ブロック内に配置。成功時のみ所有権が呼び出し側へ移る旨を契約 6 に明記し、要検証（強制終了時の残留）と DoD を追加 |
| 中 | `ClipboardWatcher` が通知受信時・`start()` 時に `changeCount` を同期しない | `start()` で基準値を再同期し、通知受信時にも基準値を進めるよう修正（`[weak self]` 付き）。同期規則 4 点をサンプル直後に明文化し、二重報告防止と再同期を DoD に追加 |
| 中 | `itemProviders` の「アラート対象」断定と `UIPasteControl` の保証範囲の誇張 | `itemProviders` を「通知・許可プロンプトの契機は要検証」に統一。`UIPasteControl` は「許可プロンプトを回避」と表現し、アクセス通知は公式保証がない旨を節見出し・API 表・実装リスクに明記。テスト行列を**許可プロンプト / アクセス通知の 2 列**に分離し、iOS 18 / iOS 26 の観測列も分けた |
| 中 | `localOnly` 検証に正の対照がない | DoD を「同一 2 台・同一 iCloud アカウント・同一 Handoff 設定で `localOnly: false` の転送成功を先に確認 → `true` の非転送を確認」に変更。観測時間・両端 OS・接続条件の記録も条件に追加 |
| 低 | 事前判定 API の観測先ケース番号の誤り | 「ケース 12・13」→「`changeCount` はケース 4、`contains` はケース 12」に修正 |
| 低 | 要検証事項の重複 | `Progress.cancel()` 関連の 2 行を「キャンセル契約全般」1 項目へ統合（completion 有無・エラードメイン / コード・gate・cleanup を包含） |

### 第 2 回レビュー反映（v2 / 2026-08-01）

| 優先度 | 指摘 | 反映内容 |
|---|---|---|
| 高 | `loadFirstImageFile` がコピー失敗を成功として返す | completion を `Result<URL, ClipboardLoadError>` に変更。provider の `error` / nil URL / コピー失敗を `providerFailed` / `unexpectedType` / `fileCopyFailed` で区別。UUID 付き専用一時ディレクトリへコピーし、成功時のみ URL を返す。一時ファイルの削除責務を呼び出し側と明記し、DoD 4 項目を追加 |
| 高 | `Progress.cancel()` は completion 抑止を保証しない | サンプルをリクエスト ID による gate 方式に変更（`active` から除去済みなら結果を破棄し、届いたファイルも削除）。API 表の `Progress.cancel()` 行に保証範囲を明記。DoD を「キャンセル後の結果を利用側へ通知しない」へ修正し、provider ごとの実挙動を要検証に追加 |
| 中 | 完了済み `Progress` の未除去と、guard 失敗経路の同期 completion | `[Int: Progress]` 管理に変更し完了時に除去。provider 不在の即時失敗も `DispatchQueue.main.async` 経由に統一。「全経路で 1 回だけメインスレッドから返す」を設計契約として明文化し DoD 化 |
| 中 | `isPersistent` 行に旧方針が残存 | 対策欄を「永続共有は App Group shared container、名前付きペーストボードはプロセス生存中の一時転送のみ」に統一 |
| 中 | `contains` / `changeCount` を「アラートを出さない」と断定 | 公式が非対象として列挙する API（`numberOfItems` / `types` / `itemSet` / `has*` / パターン検出）との差異を注記として追加。API 表 2 箇所を要検証へ変更。実装リスク 1 行追加、テスト行列にケース 4（changeCount）・12（contains）を配置し DoD 化 |
| 中 | `UIPasteControl` の宣言型と実処理が不一致 | `canPaste` / `paste(itemProviders:)` を画像にも対応。型の優先順位（テキスト > 画像）と部分失敗仕様を明記し DoD 2 項目を追加 |
| 中 | `itemProviders` の通知契機を確認するケースがない | テスト行列にケース 13（getter のみ）・14（取得後のロード）・15（UIPasteControl 経由）を追加。要検証と DoD にも反映 |
| 中 | v2 表記とファイル名の不整合 | 本ファイルを `2026-08-01-ios-clipboard-research-v2.md` として分離。ヘッダに前版へのパスを追記 |
| 低 | `NSItemProvider` の導入バージョン誤り | `registeredTypeIdentifiers` / `hasItemConformingToTypeIdentifier` を iOS 11 → **iOS 8.0** に修正。`unavailableCoercionError` が **iOS 9.0** である旨をエラーコード行に併記 |
| 低 | `registeredContentTypesForOpenInPlace` 欠落、`loadItem` の非推奨と CoreTransferable 参照不足 | `registeredContentTypesForOpenInPlace`（iOS 16.0）を追加。`loadItem` を非推奨・参考扱いとし代替（`loadObject` / `loadDataRepresentation`）を明記。`loadTransferable` に `import CoreTransferable` と `Transferable`（iOS 16.0）を併記し、公式文書一覧に CoreTransferable / Transferable / `Progress.cancel()` / `loadFileRepresentation` / `loadItem` を追加 |
| 低 | Swift 6 strict concurrency のリスク | サンプルを `@MainActor` クラス化。`withCheckedThrowingContinuation` による async API 化の検討を注記し、要検証と DoD に追加 |

### 第 1 回レビュー反映（2026-08-01）

| 優先度 | 指摘 | 反映内容 |
|---|---|---|
| 高 | 名前付きペーストボードの寿命と App Group の役割が不正確 | 公式記述「existing only until the app quits」を引用として追加。調査対象範囲・機能マップ・API 表の注記・実装リスク 3 行・サンプル（`groupPasteboard` → `transientSharedPasteboard`）・shared container の責務境界サンプル・DoD 8 項目を追加／修正 |
| 高 | `UIPasteControl` サンプルに制約がなく表示されない | `import` 2 行、`backgroundColor`、`NSLayoutConstraint.activate` による safe area 制約を追加。`Configuration` がクラスのため `var` → `let` に修正 |
| 中 | 「毎回表示される」が文書内で矛盾、iOS 14 通知と iOS 16 アラートの混同 | 実装リスクを 2 行に分離し「毎回」を「OS がユーザー意図を認定しない場合」へ修正。機能マップ・API 表・DoD も同様に区分。11 パターンのテスト行列セクションを新設 |
| 中 | `NSItemProvider` 読み取り API が未整理 | 「ペースト（読み取り） — NSItemProvider 経由」表（型判定 / 非同期ロード / キャンセル / エラー / 登録系は対象外明記）とサンプル `ItemProviderLoader` を新設。責務境界・要検証・DoD 6 項目を追加 |
| 中 | 公式文書一覧の不足 | UTType / UniformTypeIdentifiers / NSItemProvider / NSItemProviderReading / NSItemProviderWriting / App Groups Entitlement / shared container / `RemovedMessage` / `init(name:create:)` / `withUniqueName()` / `setValue(_:forPasteboardType:)` を追加 |
| 中 | 画像 Data 化のメモリ主張が保証できない | 「相互運用する表現形式の選択」として書き換え、ピークメモリ増の可能性を明記。実装リスク行を分離し、要検証と DoD に実機計測を追加。サンプル名を `copyImageData` → `copyImageAsPNG` に変更しコメント修正 |
| 中 | `ClipboardWatcher.start` の二重開始でリーク | `start` 冒頭で `stop()` を呼ぶよう修正し、`deinit` を追加。実装リスクと DoD に二重開始 / 二重停止 / 破棄時解除を追加 |
| 中 | 名前付き / ユニーク名 / App Group が DoD にない | DoD を 5 カテゴリに再編し、「名前付き / ユニーク名ペーストボード」8 項目を新設 |
| 低 | `setValue` の受け入れ型と `setObjects` オーバーロード | 公式の列挙（`NSString` / `NSArray` / `NSDictionary` / `NSDate` / `NSNumber` / `UIImage` / `NSURL`）に修正し、既存アイテムを置換する仕様を API 表・実装リスク・DoD に追加。`setObjects` を 4 オーバーロードに分けて記載 |
