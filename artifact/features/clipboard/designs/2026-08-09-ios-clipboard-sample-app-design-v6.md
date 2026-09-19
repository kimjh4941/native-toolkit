# iOS Clipboard サンプルアプリ実装計画 v6

## 基本情報

- 日付: 2026-08-09
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 対象サンプルアプリ: `ios/IosLibraryExample`
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-09-ios-clipboard-sample-app-design-review-v2.md`
- 前版: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v5.md`
- 対応タスク: 設計書 T-12

### v5 からの変更

| 優先度 | 指摘 | 対応 |
|---|---|---|
| 高 1 | M-16 は実際には3観測値なのに2 bitへ縮約されている | `bodyBeforeAppend` / `bodyAfterAppend` / `appendAfterAppend`の3値へ統一し、8組合せの帰結を定義（6.3 / 6.5） |
| 高 2 | M-16に正の対照と端末Bの事前条件がない | 同一試行で`localOnly=false`正対照、Bの既知baseline、Paste許可・接続条件を固定（6.3 / 6.5） |
| 高 3 | 初回Checkが実戻り値をfalseへ上書きし、baseline更新を誤断定する | 常に実際の`changed=<bool>`を表示し、初回注記をUI-localな文言だけに変更（5.8 / 9.2） |
| 中 1 | sequenceの単調増加範囲と再起動後初期値が未定義 | 同一View / process epoch内に限定し、launch後は旧seqを破棄（4.3 / 9.4） |
| 中 2 | U-10が前回残存と削除遅延を排除しない | 開始前にremove / unavailableを確認し、terminate後は上限つきpoll（9.2） |
| 中 3 | case 4で画面表示時にPaste Controlが生成されうる | Paste Controlを明示的なMount操作まで生成しない（5.9 / 6.2） |
| 中 4 | M-16結果表がA/B両端の条件を表現できない | 1 trial 1行で両端OS build・接続・許可・正対照・3観測値を保存（6.5） |
| 低 1 | marker件数と`cancelLoads`の位置づけが不一致 | 結果markerとcontrol-only操作を分離。Cancelは結果を上書きしない（4.5 / 5.6） |
| 低 2 | U-2 / U-11の期待文字列が正式表示形式と一致しない | marker条件とpayload条件へ分離（9.2） |

---

## 1. 前提情報の抽出（設計書・実装結果由来）

### 1.1 in-scope 機能

S1〜S11。S12（Unity Bridge）は対象外。

| ID | サブ機能 |
|---|---|
| S1 | ペーストボード解決（`general` / 名前付き / ユニーク名） |
| S2 | コピー（9 content kind） |
| S3 | コピーオプション（`localOnly` / `expirationDate`） |
| S4 | 追記（`append`） |
| S5 | ペースト（同期） |
| S6 | ペースト（`NSItemProvider` 非同期） |
| S7 | 内容確認（`snapshot`） |
| S8 | クリア |
| S9 | 変更監視 |
| S10 | パターン検出（11 パターン） |
| S11 | 貼り付け UI（`UIPasteControl`。ネイティブのみ） |

### 1.2 公開 API

`IosLibrary.IosClipboardManager`（`@MainActor`）の P-1〜P-16。`async throws` 版と同期 API のみ使う。

### 1.3 入力制約と状態契約

- `acceptedTypes` は 1 件以上必須
- `multipleText` の空配列、`multiRepresentation` の空 object は `CLIPBOARD_EMPTY_ITEMS`
- `append` は `ClipboardCopyOptions` を受け取らない
- URL は `http` / `https`（host 必須）または `file` のみ。scheme なしは拒否
- custom UTI は `UTType` が解決するか、ASCII 英数字 + `-` `_` の 2 セグメント以上の逆 DNS 形式のみ
- サイズ上限: copy / load 各 64 MiB、画像 100 MP
- タイムアウト: detection 5s / providerLoad 15s / imageCoding 10s
- 名前付き / ユニークペーストボードは**非永続**

**`.file(utType:)` の選択規則**

`providers.first { $0.hasItemConformingToTypeIdentifier(utType) }` で対象を選ぶ。
未登録の custom UTI は `public.data` へ conform しない。

**`checkForegroundChange` の baseline 契約**

```swift
guard let current = try? repository.changeCount(scope: scope) else { return false }
var tracker = trackers[scope] ?? ClipboardChangeTracker(baseline: current)   // 初回は current が baseline
let changed = tracker.hasChanged(current: current)                           // 同じ値と比較
```

scope ごとの tracker が存在しない状態での初回呼び出しは、必ず `false` を返す。

**tracker が作られる / 更新される契機は Check だけではない**（中 1）:

| 契機 | メソッド |
|---|---|
| `checkForegroundChange` | `execute`（scope の tracker がなければ作る） |
| `startObserving` | `resync(scope:)` |
| `changedNotification` 受信 | `markReported(scope:)` |
| 前の View instance での Check | `execute`（manager は singleton なので View 破棄後も残る） |

逆に、**解決不能 scope では `changeCount` の取得に失敗して early return するため tracker は作られない**。
したがって「View 側で初回かどうか」と「manager 側に tracker があるか」は一致しない。

### 1.4 エラー契約（実装から全件照合済み）

| case | errorCode |
|---|---|
| `emptyContent` | `CLIPBOARD_EMPTY_CONTENT` |
| `emptyItemList` | `CLIPBOARD_EMPTY_ITEMS` |
| `emptyDetectionPatterns` | `CLIPBOARD_EMPTY_PATTERNS` |
| `invalidURL` | `CLIPBOARD_INVALID_URL` |
| `invalidTypeIdentifier` | `CLIPBOARD_INVALID_TYPE` |
| `invalidPasteboardName` | `CLIPBOARD_INVALID_NAME` |
| `invalidColor` | `CLIPBOARD_INVALID_COLOR` |
| `invalidImageData` | `CLIPBOARD_INVALID_IMAGE_DATA` |
| `invalidExpirationDate` | `CLIPBOARD_INVALID_EXPIRATION` |
| `invalidRequest` | `CLIPBOARD_INVALID_REQUEST` |
| `contentTooLarge` | `CLIPBOARD_CONTENT_TOO_LARGE` |
| `fileNotFound` | `CLIPBOARD_FILE_NOT_FOUND` |
| `imageLoadFailed` | `CLIPBOARD_IMAGE_LOAD_FAILED` |
| `imageEncodingFailed` | `CLIPBOARD_IMAGE_ENCODE_FAILED` |
| `pasteboardUnavailable` | `CLIPBOARD_UNAVAILABLE` |
| `cannotRemoveGeneralPasteboard` | `CLIPBOARD_CANNOT_REMOVE_GENERAL` |
| `noMatchingItem` | `CLIPBOARD_NO_MATCHING_ITEM` |
| `providerLoadFailed` | `CLIPBOARD_LOAD_FAILED` |
| `unexpectedType` | `CLIPBOARD_UNEXPECTED_TYPE` |
| `fileCopyFailed` | `CLIPBOARD_FILE_COPY_FAILED` |
| `cancelled` | `CLIPBOARD_CANCELLED` |
| `timedOut` | `CLIPBOARD_TIMED_OUT` |
| `detectionFailed` | `CLIPBOARD_DETECTION_FAILED` |
| `unknown` | `CLIPBOARD_UNKNOWN` |

### 1.5 テスト観点とサンプルアプリでの扱い

| 観点 | サンプルで扱うか | 委譲先 |
|---|---|---|
| 9 content kind / 3 scope kind / 4 load kind / 11 検出パターン | 扱う | 5.1〜5.7 |
| Error Cases 11 件 | 扱う | 5.11 |
| 空文字列の許可（境界） | 扱う | 5.2 |
| 64 MiB / 100 MP 上限**判定** | 扱わない | unit test |
| 100 MP という**上限値の妥当性** | 扱わない | T-13 harness |
| タイムアウト | 扱わない | unit test（短縮設定） |
| Paste Control の partial / all failure | 扱わない | ライブラリ unit / integration test |
| 監視停止の証明 | 扱わない | integration test |
| active session の cleanup 除外 | 扱わない | 注入可能な harness |

### 1.6 不足前提

| 項目 | 内容 |
|---|---|
| T-00 未実施 | **本サンプル単独では完遂できない**（6 章） |
| `UIColor` の UTI | `"com.apple.uikit.color"` は公式ドキュメント未確認。**要検証** |
| App Group（M-09） | entitlement と 2 アプリ目が必要。**対象外** |
| `public.data` の end-to-end | `UIPasteboard.items` へ Data を書いた後の `itemProviders → loadFileRepresentation` 経路は未実測。**U-11 を受け入れ試験として扱う**（5.6） |
| unsupported-only fixture | Files 由来 provider が `public.file-url` やプレビュー画像も広告しうる。**要検証**（8.1 #20） |

---

## 2. 既存サンプルコードの深掘り

### 2.1 確認したファイル

| パス | 役割 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ContentView.swift` | メインメニュー |
| `ios/IosLibraryExample/IosLibraryExample/ShareSampleView.swift` | 最も構成が近い参照元 |
| `ios/IosLibraryExample/IosLibraryExample/NotificationSampleView.swift` | `sectionView` / `updateResult` |
| `ios/IosLibraryExample/IosLibraryExample/DialogSampleView.swift` | 最小構成 |
| `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift` | 既存 UI テストターゲット（`XCTest` のみ import） |
| `ios/IosLibraryExample/IosLibraryExample.xcodeproj/xcshareddata/xcschemes/IosLibraryExample.xcscheme` | **`IosLibraryExampleUITests` が `parallelizable = "YES"`**（中 4） |
| `android/.../example/ClipboardSampleScreen.kt` | 相互参照ペア |

### 2.2 Android Clipboard サンプルから踏襲する点

- 機能カテゴリ単位のセクション分け
- 結果表示領域を画面上部に固定
- プラットフォーム制約を画面内の注記テキストで示す
- Error Cases を独立セクションにし、期待エラーコードをボタン名に含める
- 画面破棄時に監視を停止する

踏襲しない: `Toast`、Back ボタンの明示配置

### 2.3 iOS 既存サンプルの UI 規約（優先）

| 要素 | 規約 |
|---|---|
| 画面遷移 | `NavigationStack` + `NavigationLink` |
| 画面先頭 | `Text("<Manager> Example")` を `.title` + `.bold` |
| 結果表示 | `@State resultText`。灰色背景の角丸ボックス |
| セクション | `sectionView(title:content:)` |
| ボタン | `FullWidthPressableButtonStyle` |
| 結果更新 | `updateResult(...)`。`✅` / `❌` |
| ログ | `Log.d` / `Log.e` |
| 入力 | 固定サンプルデータ + ボタン |

### 2.4 再利用 / 追加 / 変更

**再利用**: `ContentView.menuCard`、`sectionView` / `updateResult` / `FullWidthPressableButtonStyle`、`Text.buttonStyle(backgroundColor:)`

**追加**

| 名前 | 種別 | 理由 |
|---|---|---|
| `ClipboardSampleView` | `View` | 機能本体 |
| `ClipboardPasteControlView` | `UIViewRepresentable` | `ClipboardPasteControlContainerView` は `UIView` |
| `ClipboardSampleIdentifiers` | `enum` | accessibility identifier の単一情報源（app 側） |

**変更**: `ContentView.swift`、`IosLibraryExampleUITests.swift`、**`IosLibraryExample.xcscheme`**（中 4）

---

## 3. 実装制約の確認

### 3.1 依存方向

**問題なし。** S1〜S11 のすべてが `IosLibrary` の P-1〜P-16 で到達可能。

### 3.2 コーディングルール

- `common.md`: Clean Architecture、サンプルアプリの依存方向
- `ios.md`: 全 `public` / `internal` / `override` 関数の先頭に `Log.d` / `Log.e`
- **本機能特有**: クリップボード値・パス・URL・pasteboard 名をログへ出さない

---

## 4. 画面要件

### 4.1 導線

```
Main Menu (ContentView) → ClipboardSampleView
```

### 4.2 wireframe

```
[Clipboard Example]
[✅ #12 [read] numberOfItems=1, ...]           <- clipboard.result
[Scope: general | Observing: off | Events: 0]  <- clipboard.status
[Paste result: -]                              <- clipboard.pasteSummary
ScrollView
  ├─ Scope / Copy / Copy Options / Append
  ├─ Read / Inspect / Load (async) / Detect
  ├─ Observe / Paste Control (UI) / Clear
  └─ Error Cases
```

### 4.3 状態

| 状態 | 種別 | 用途 |
|---|---|---|
| `resultText` | `@State` | 結果表示 |
| `resultSequence: Int` | `@State` | **同一 View / process epoch 内**で単調増加。再生成・再起動時は 0 に戻る |
| `activeScope: PasteboardScope` | `@State` | 操作対象 scope |
| `lastRemovedScope: PasteboardScope?` | `@State` | remove 後の解決不能確認 |
| `observedEventCount: Int` | `@State` | 監視イベント受信数 |
| `isObserving: Bool` | `@State` | 監視中フラグ |
| `pastedSummary: String` | `@State` | S11 の結果集約 |
| `isPasteControlMounted: Bool` | `@State` | 初期値 `false`。明示操作まで `UIPasteControl` を生成しない |
| `didCheckForegroundInThisView: Set<String>` | `@State` | **View 内で Check を押した scope**（manager の tracker 有無とは別物・中 1） |
| `activeScopeLabel: String` | computed | `activeScope` から導出。kind と名前長のみ |

### 4.4 ボタン活性条件

| ボタン | `isObserving == false` | `isObserving == true` |
|---|---|---|
| `Start Observing` | 有効 | 無効 |
| `Stop Observing` | 無効 | 有効 |
| Scope セクションの全ボタン | 有効 | 無効 |
| `Observe Unresolvable Named → UNAVAILABLE` | 有効 | 無効 |

### 4.5 結果表示形式（sequence / marker）

**結果を生成する操作は invocation sequence と operation marker を含める。**

| 種別 | 形式 |
|---|---|
| 成功 | `✅ #<seq> [<marker>] <payload>` |
| 失敗 | `❌ #<seq> [<marker>] errorCode=<code>, errorMessage=<message>` |
| キャンセル | `ℹ️ #<seq> [<load marker>] Cancellation completed (CLIPBOARD_CANCELLED)` |
| 警告 | `⚠️ #<seq> [<marker>] fileSize=<n>, cleanup=failed` |

- **marker**: ボタンごとに一意。同じ errorCode を返すボタンが複数あるため、コードだけでは識別できない
- **`#<seq>`**: `updateResult` のたびに +1。同じ操作の再実行時に古い label へ一致するのを防ぐ
- 単調性は**同一 View / process epoch 内だけ**で保証する。View 再生成・app 再起動後は 0 へ戻り、前 epoch の値と比較しない
- Paste Control callback は `pastedSummary`、observer event は `clipboard.status` を更新し、sequence とは別系列

#### result marker 一覧: 50件

`ClipboardSampleIdentifiers` の button identifier 末尾（`clipboard.button.<action>` の `<action>`）を
**そのまま marker として使う**。これにより実装差が構造的に発生しない。

| セクション | 件数 | marker |
|---|---:|---|
| Scope | 6 | `useGeneral` / `createNamed` / `useFixedNamed` / `createUnique` / `removeActive` / `probeRemoved` |
| Copy | 12 | `copyPlainText` / `copyPlainTextEmpty` / `copyHtml` / `copyURL` / `copyImageFile` / `copyImageData` / `copyColor` / `copyCustomData` / `copyFileFixture` / `copyMultipleText` / `copyMultiRepresentation` / `copyDetectionFixture` |
| Copy Options | 4 | `copyLocalOnlyTrue` / `copyLocalOnlyFalse` / `copyBBaseline` / `copyExpiring` |
| Append | 3 | `appendPlainText` / `appendURL` / `appendUniversalMarker` |
| Read / Inspect | 4 | `read` / `readData` / `snapshot` / `snapshotMatching` |
| Load completion | 4 | `loadText` / `loadURL` / `loadImage` / `loadFile` |
| Detect | 2 | `detectPatterns` / `detectValues` |
| Observe | 3 | `startObserving` / `stopObserving` / `checkForeground` |
| Clear | 1 | `clear` |
| Error Cases | 11 | `errMultipleEmpty` / `errMultiRepEmpty` / `errImageMissing` / `errCopyInvalidUTI` / `errInvalidURL` / `errInvalidColor` / `errReadInvalidUTI` / `errRemoveGeneral` / `errObserveMissing` / `errEmptyPatterns` / `errEmptyAcceptedTypes` |
| **合計** | **50** | — |

#### control-only identifier: 2件

| 操作 | identifier末尾 | 結果更新 |
|---|---|---|
| Cancel All Loads | `cancelLoads` | `resultText`を更新しない。pending load completionが元のload markerで1回だけ更新 |
| Mount Paste Control | `mountPasteControl` | `resultText`を更新しない。callbackは`pastedSummary`だけを更新 |

### 4.6 値の表示方針（確定）

| 対象 | 画面表示 | ログ |
|---|---|---|
| 外部由来のクリップボード値 | 表示しない | 出さない |
| ファイルパス・URL・pasteboard 名 | 表示しない | 出さない |
| 件数 / byte 数 / 文字数 / 型識別子 / kind / errorCode | 表示する | 出す |

`updateResult` は result 本文をログへ出さない（seq と marker と `isSuccess` のみ）。

---

## 5. 実装詳細

### 5.1 Scope（S1 / P-7 / P-8）

| ボタン | marker | 動作 |
|---|---|---|
| `Use General` | `useGeneral` | `activeScope = .general` |
| `Create Named Pasteboard` | `createNamed` | `createPasteboard(.named(Self.fixedName))` → `activeScope` へ |
| `Use Fixed Named Scope (no create)` | `useFixedNamed` | `activeScope = .named(Self.fixedName)`（作成しない） |
| `Create Unique Pasteboard` | `createUnique` | `createPasteboard(.unique)` → `activeScope` へ |
| `Remove Active Pasteboard` | `removeActive` | `removePasteboard(activeScope)` → `lastRemovedScope` 更新、`activeScope = .general` |
| `Probe Last Removed Scope` | `probeRemoved` | `read(scope: lastRemovedScope)` → `CLIPBOARD_UNAVAILABLE` |

`Self.fixedName = "com.jonghyunkim.nativetoolkit.example.sample"`

### 5.2 Copy（S2 / P-1）

| ボタン | content |
|---|---|
| `Copy Plain Text` | `.plainText("Hello from IosLibraryExample")` |
| `Copy Plain Text (empty, allowed)` | `.plainText("")` |
| `Copy HTML Text` | `.htmlText(plain: "plain body", html: "<b>html body</b>")` |
| `Copy URL` | `.url("https://www.apple.com")` |
| `Copy Image File` | `.imageFile(path:)`（バンドルの `app-icon-attachment.png`） |
| `Copy Image Data` | `.imageData(_, utType: "public.png")` |
| `Copy Color` | `.color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)` |
| `Copy Custom Data` | `.customData(Data([0xCA, 0xFE]), utType: Self.customTypeIdentifier)` |
| `Copy File Fixture (public.data)` | `.customData(Self.fileFixturePayload, utType: "public.data")` |
| `Copy Multiple Text` | `.multipleText(["first", "second", "third"])` |
| `Copy Multi Representation` | `.multiRepresentation(["public.plain-text": ..., "public.utf8-plain-text": ...])` |
| `Copy Detection Fixture` | 5.7 の固定文字列 |

定数:

```swift
static let customTypeIdentifier = "com.jonghyunkim.nativetoolkit.example.custom"
/// 64 bytes の固定 payload。U-11 が `fileSize=64` を期待値として判定できるようにする。
static let fileFixturePayload = Data(repeating: 0x41, count: 64)
```

#### `Copy File Fixture (public.data)` を分ける理由

`.file(utType:)` は `hasItemConformingToTypeIdentifier(utType)` で provider を選ぶ。
未登録の custom UTI は `public.data` へ conform しないため、`Copy Custom Data` の直後に
`Load File (public.data)` を実行しても `CLIPBOARD_NO_MATCHING_ITEM` になる。

### 5.3 Copy Options（S3 / P-1）— M-16 用の内容を固定（中 6）

| ボタン | marker | content / options |
|---|---|---|
| `Copy (localOnly = true)` | `copyLocalOnlyTrue` | `.plainText(Self.localOnlyBody)`、`ClipboardCopyOptions(localOnly: true, expirationDate: nil)` |
| `Copy (localOnly = false)` | `copyLocalOnlyFalse` | `.plainText(Self.localOnlyBody)`、`localOnly: false`（M-06 の正の対照） |
| `Copy B Baseline (localOnly = true)` | `copyBBaseline` | `.plainText(Self.deviceBBaseline)`、`localOnly: true`（M-16専用、31文字） |
| `Copy (expires in 30s)` | `copyExpiring` | `.plainText("expiring body")`、`expirationDate: Date().addingTimeInterval(30)` |

```swift
/// 14 文字。M-16 で append marker（24 文字）と文字数だけで区別できるようにする。
static let localOnlyBody = "LOCALONLY-BODY"

/// 31文字。M-16で端末Bの既知baselineとして使い、14/24文字のtrial fixtureと区別する。
static let deviceBBaseline = String(repeating: "B", count: 31)
```

### 5.4 Append（S4 / P-2）

| ボタン | marker | 動作 |
|---|---|---|
| `Append Plain Text` | `appendPlainText` | `append(.plainText("appended item"))` |
| `Append URL` | `appendURL` | `append(.url("https://developer.apple.com"))` |
| `Append Universal Marker` | `appendUniversalMarker` | `append(.plainText(Self.appendMarker))` |

```swift
/// 24 文字固定（"APPENDED-MARKER-" 16 文字 + UUID 先頭 8 文字）。
/// M-16 では端末 B で raw 値を表示しないため、item index と文字数で body(14) と区別する。
static var appendMarker: String { "APPENDED-MARKER-" + UUID().uuidString.prefix(8) }
```

注記: `append` は options を受け取れず、privacy option の継承は保証されない（M-16）。

> T-00 の結果で変わりうる箇所。

### 5.5 Read / Inspect（S5 / S7 / P-3 / P-4 / P-5）

| ボタン | marker | 表示内容（値は出さない） |
|---|---|---|
| `Read` | `read` | `numberOfItems`、**各 item の index・`text` の有無・文字数**、`typeIdentifiers.count`、`urlString` の有無 |
| `Read Data (public.png)` | `readData` | byte 数、または `nil` |
| `Snapshot` | `snapshot` | `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `numberOfItems` / `typeIdentifiers.count` |
| `Snapshot (matching public.plain-text)` | `snapshotMatching` | 上記 + `matchingItemIndexes` |

**`Read` は item ごとに `index / hasText / textLength` を出す**（中 6）。
これにより、raw 値を表示せずに M-16 の body(14 文字) と append marker(24 文字) を区別できる。

表示例: `numberOfItems=2, items=[0:text(len=14), 1:text(len=24)]`

### 5.6 Load（S6 / P-11 / P-12）

| ボタン | marker | request | 前提 | 表示 |
|---|---|---|---|---|
| `Load Text` | `loadText` | `.text` | `Copy Plain Text` | 文字数のみ |
| `Load URL` | `loadURL` | `.url` | `Copy URL` | 文字数のみ |
| `Load Image` | `loadImage` | `.image` | `Copy Image File` | byte 数 |
| `Load File (public.data)` | `loadFile` | `.file(utType: "public.data")` | `Copy File Fixture` | `fileSize`（期待 64）。取得後に削除 |
| `Cancel All Loads` | `cancelLoads` | — | — | `cancelAllLoads()`。control-onlyで`resultText`を更新しない |

> **要検証（低 2）**: `UIPasteboard.items` へ Data を書いた後の `itemProviders → loadFileRepresentation`
> 経路は未実測。既存の file load テストは `registerFileRepresentation` 済み provider を使っており経路が異なる。
> **U-11 はこの経路の受け入れ試験として扱う。**
>
> **失敗した場合の切替判断**: Files 由来の既知 file representation を外部 fixture として使う方式へ切り替える。
> ただしその時点で**外部アプリ依存になるため、U-11 は自動 UI テストから外して manual / harness へ移す**。
> 自動試験側には「この経路が未成立であること」を失敗理由として記録する。

#### `.file` の所有権と cleanup

```
<NSTemporaryDirectory()>/IosLibraryClipboard/<sessionID>/<requestID>/<UUID>.<ext>
                                              ^^^^^^^^^  ^^^^^^^^^
                                              session    request ← 呼び出し側が削除するのはこちら
```

```swift
/// Reads the size of a loaded file and then deletes the **request-scoped** directory the library
/// handed over (the returned URL's parent). The active session directory is owned by the library
/// and must not be touched. The path is never shown on screen or logged.
private func consumeLoadedFile(_ url: URL) -> (detail: String, cleanupFailed: Bool) {
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    let requestDirectory = url.deletingLastPathComponent()
    do {
        try FileManager.default.removeItem(at: requestDirectory)
        return ("fileSize=\(size)", false)
    } catch {
        Log.e(TAG, "[consumeLoadedFile] cleanup failed")   // パスは出さない
        return ("fileSize=\(size), cleanup=failed", true)
    }
}
```

cleanup 失敗は `⚠️` の警告表示にする。

#### キャンセル契約

`Cancel All Loads`のtap自体は結果を表示しない。pending loadのcompletionだけが元のload markerで
`resultText`を1回更新し、control結果とload completionの競合を作らない。

| 項目 | 契約 |
|---|---|
| 呼び出し側への通知 | `CLIPBOARD_CANCELLED` を完了として返す |
| system load | `Progress.cancel()` を試みる |
| 遅延到着した結果 | 破棄する（一時ファイルも削除） |
| **OS 処理そのものの中断** | **保証しない** |

`Cancel` ボタンは結果表示を上書きしない。`loadItem` 側の completion が唯一の更新元。

### 5.7 Detect（S10 / P-9 / P-10）

| ボタン | marker | 動作 |
|---|---|---|
| `Copy Detection Fixture` | `copyDetectionFixture` | 11 パターンを含む固定文字列をコピー |
| `Detect Patterns (all 11)` | `detectPatterns` | `detectPatterns(Set(ClipboardDetectionPattern.allCases))` → パターン名の一覧 |
| `Detect Values (all 11)` | `detectValues` | `detectValues(...)` → 各配列の件数のみ |

fixture:

```
Visit https://www.apple.com or email support@example.com.
Call +1 (408) 996-1010. Ship to 1 Infinite Loop, Cupertino, CA 95014.
Meeting on March 3, 2027 at 10:00 AM. Flight AA100. Total 1,234.56 USD.
Tracking 1Z999AA10123456784. Search: swift concurrency. Number 42.
```

> 要検証: DataDetection の結果は OS バージョンとロケールに依存する。検出されなかったパターンは、
> fixture の不備か API の挙動かを切り分けて記録する（断定しない）。

### 5.8 Observe（S9 / P-13 / P-14 / P-15）

| ボタン | marker | 動作 |
|---|---|---|
| `Start Observing` | `startObserving` | `try startObserving(scope: activeScope) { ... }`。成功時のみ `isObserving = true` |
| `Stop Observing` | `stopObserving` | `stopObserving()`。`isObserving = false` |
| `Check Foreground Change` | `checkForeground` | `checkForegroundChange(scope:)` → `Bool` |

#### `Check Foreground Change`の表示

v4 は View 内の初回に `baseline established` と表示していたが、**manager の tracker は
`resync` / `markReported` / 前の View instance の Check でも作られる**（1.3）。
逆に解決不能 scope では tracker が作られない。したがって View 側の「初回」は
**manager 内部状態を断定できない**。

表示は実戻り値を保持し、manager内部を主張しない。

- View 内で初めて押した scope: `✅ #<seq> [checkForeground] changed=<actual bool> (first check in this screen)`
- 2 回目以降: `✅ #<seq> [checkForeground] changed=<bool>`

`<actual bool>`にはAPIの実戻り値をそのまま使い、falseへ上書きしない。公開Bool APIは
「解決成功してfalse」と「解決不能でfalse」を区別できないため、`baseline updated`とは表示しない。

注記テキスト:

> `Check Foreground Change`は、解決できたscopeについて、この呼び出し時の`changeCount`を
> 以後の比較基準にします。比較基準は監視開始や通知受信でも更新されるため、
> `first check in this screen`は画面内の操作履歴だけを表し、manager内部状態を表しません。

#### 状態遷移

`startObserving` は新しい scope を解決する前に既存観測を停止する。

1. **観測中は `Observe Unresolvable Named` を無効化する**（4.4）
2. **catch でも `isObserving = false` にする**

```swift
do {
    try IosClipboardManager.shared.startObserving(scope: scope) { ... }
    isObserving = true
} catch let error as ClipboardError {
    isObserving = false        // manager 側は停止済み。画面状態を実態へ合わせる
    updateResult(marker: "startObserving", isSuccess: false, ...)
}
```

`onDisappear` では `stopObserving()` を呼び `isObserving = false`。
サンプルが作成した named / unique pasteboard は破棄しない。

### 5.9 Paste Control（S11 / P-16）

#### 遅延mountとcase 4の分離

`UIPasteControl`は画面表示時に生成しない。初期状態では`Mount Paste Control`ボタンだけを表示し、
tap後に`isPasteControlMounted = true`として初めて`ClipboardPasteControlView`を構築する。
Mountはcontrol-only操作で`resultText`を更新しない。

これによりT-00 case 4では、最初のclipboard-aware操作を`Check Foreground Change`に限定する。
記録には`isPasteControlMounted == false`を前提として残す。

#### scope の制約

`makePasteControl` に scope 引数はない。Paste Control は `activeScope` とは独立して
**system の general pasteboard を対象**にする。

#### `UIViewRepresentable`

```swift
struct ClipboardPasteControlView: UIViewRepresentable {
    let acceptedTypes: [String]
    let onPaste: ([ClipboardLoadedItem]) -> Void
    let onPartialFailure: ([ClipboardError]) -> Void
    let onPasteFailure: (ClipboardError) -> Void
    let onCreationFailure: (ClipboardError) -> Void

    func makeUIView(context: Context) -> UIView {
        do {
            return try IosClipboardManager.shared.makePasteControl(
                acceptedTypes: acceptedTypes,
                onPaste: onPaste,
                onPartialFailure: onPartialFailure,
                onPasteFailure: onPasteFailure
            )
        } catch let error as ClipboardError {
            // makeUIView 中の同期 state 変更は "Modifying state during view update" になるため次 turn へ回す
            Task { @MainActor in onCreationFailure(error) }
            return UIView()
        } catch {
            Task { @MainActor in
                onCreationFailure(.unknown(ClipboardFailureDetail(systemError: error)))
            }
            return UIView()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

`acceptedTypes` は `["public.plain-text", "public.url", "public.image"]`。

#### 結果集約と期待契約

| 状況 | control | callback | `pastedSummary` |
|---|---|---|---|
| accepted type を含む内容がある | 有効 | `onPaste` 1 回 | `items=N, failures=0` |
| **対応外の型のみ** | **無効（タップ不可）** | **0 回** | **更新されない** |
| 部分成功 | 有効 | `onPaste` → `onPartialFailure` | `items=N, failures=M [codes]` |
| 生成失敗 | — | `onCreationFailure` | `control creation failed: <code>` |

**partial failure / all failure は本サンプルの手動 DoD から外す。**
ライブラリの `PasteItemProviderLoaderTests` / `ClipboardPasteReceiverViewTests` へ委譲する。

### 5.10 Clear（S8 / P-6）

| ボタン | marker | 動作 |
|---|---|---|
| `Clear Active Scope` | `clear` | `clear(scope: activeScope)` |

### 5.11 Error Cases（実装と全件照合済み）

| ボタン | marker | 入力 | 期待 errorCode |
|---|---|---|---|
| `Copy Multiple (empty list) → EMPTY_ITEMS` | `errMultipleEmpty` | `.multipleText([])` | `CLIPBOARD_EMPTY_ITEMS` |
| `Copy Multi Representation (empty) → EMPTY_ITEMS` | `errMultiRepEmpty` | `.multiRepresentation([:])` | `CLIPBOARD_EMPTY_ITEMS` |
| `Copy Image File (missing) → FILE_NOT_FOUND` | `errImageMissing` | `.imageFile(path: "/nonexistent/clipboard-missing.png")` | `CLIPBOARD_FILE_NOT_FOUND` |
| `Copy Custom Data (invalid UTI) → INVALID_TYPE` | `errCopyInvalidUTI` | `.customData(Data([1]), utType: "not a valid identifier!!")` | `CLIPBOARD_INVALID_TYPE` |
| `Copy URL (no scheme) → INVALID_URL` | `errInvalidURL` | `.url("example.com")` | `CLIPBOARD_INVALID_URL` |
| `Copy Color (out of range) → INVALID_COLOR` | `errInvalidColor` | `.color(red: 2.0, green: 0, blue: 0, alpha: 1)` | `CLIPBOARD_INVALID_COLOR` |
| `Read Data (invalid UTI) → INVALID_TYPE` | `errReadInvalidUTI` | `readData(utType: "not a valid identifier!!")` | `CLIPBOARD_INVALID_TYPE` |
| `Remove General → CANNOT_REMOVE_GENERAL` | `errRemoveGeneral` | `removePasteboard(.general)` | `CLIPBOARD_CANNOT_REMOVE_GENERAL` |
| `Observe Unresolvable Named → UNAVAILABLE` | `errObserveMissing` | `startObserving(scope: .named("...missing-\(UUID())"))` | `CLIPBOARD_UNAVAILABLE` |
| `Detect Patterns (empty set) → EMPTY_PATTERNS` | `errEmptyPatterns` | `detectPatterns([])` | `CLIPBOARD_EMPTY_PATTERNS` |
| `Make Paste Control (empty types) → INVALID_REQUEST` | `errEmptyAcceptedTypes` | `makePasteControl(acceptedTypes: [])` | `CLIPBOARD_INVALID_REQUEST` |

入力の根拠:

- `"not a valid identifier!!"` — `UTType` が解決せず逆 DNS 形式でもないため `validateGeneric` が拒否
- `"example.com"` — scheme が nil のため `validateURL` が拒否
- `.color(red: 2.0, ...)` — `validateColor` が 0...1 の範囲外を拒否

---

## 6. T-00（実機プライバシースパイク）の実施境界

### 6.1 対応表

| # | 直前の状況 | サンプルでの操作 | 実施可否 |
|---|---|---|---|
| 1 | **自アプリ**でコピーした直後 | `Copy Plain Text` → `Read` | 可 |
| 2 | **他アプリ**でコピーされた内容 | （外部コピー後）`Read` | 可 |
| 3 | **他アプリ**でコピーされた内容 | （外部コピー後）`Snapshot` のみ | 可 |
| 4 | **他アプリ**でコピーされた内容 | （外部コピー後）**fresh な状態で初回** `Check Foreground Change`。**戻り値は無視**（6.2） | 可 |
| 5 | **他アプリ**でコピーされた内容 | （外部コピー後）`Detect Patterns` | 可 |
| 6 | **他アプリ**でコピーされた内容 | （外部コピー後）`Detect Values` | 可 |
| 7 | 他アプリでコピーされた内容 | `UIPasteControl` を**タップのみ**（ロードしない） | **不可** |
| 8 | 他アプリでコピーされた内容 | 標準の編集メニューの「ペースト」 | **不可** |
| 9 | 一度承認した直後に再度読む | `Read` を連続実行 | 可 |
| 10 | background 復帰直後 | **baseline 確立を含む 5 段階**（6.2） | 可 |
| 11 | Universal Clipboard 経由 | `Snapshot` → `Read` | 可（2 台） |
| 12 | 他アプリでコピーされた内容 | `contains(pasteboardTypes:)` のみ | **不可**（公開 API 外） |
| 13 | 他アプリでコピーされた内容 | `itemProviders` getter のみ | **不可** |
| 14 | ケース 13 の直後 | 取得済み provider へ `canLoadObject` のみ | **不可** |
| 15 | ケース 14 の直後 | 取得済み provider へ実ロード | **不可** |
| 16 | 他アプリでコピーされた内容 | `UIPasteControl` タップ → 内部で自動ロード | 可 |

### 6.2 ケース 4 と 10 は別手順

**両者は目的が異なるため、準備を共通化してはならない。**

| | ケース 4 | ケース 10 |
|---|---|---|
| 目的 | **`changeCount` を読むこと自体が privacy 契機か**を観測 | background 中の変更を差分検出できるか |
| 事前 baseline 確立 | **行わない** | 行う |
| Paste Control | **mountしない** | mountしない |
| 戻り値 `Bool` | privacy判定には使わない。表示は実値のまま | 判定に使う |
| 記録対象 | 許可プロンプト / アクセス通知の有無のみ | 同左 + `changed` の値 |

#### ケース 4 の手順（fresh な許可状態で実施）

1. **アプリを削除して再インストール**、または許可状態をリセットする
2. 外部アプリでコピーする
3. アプリを起動し、Clipboard画面を開く
4. `isPasteControlMounted == false`であることを確認する。Mountを含む他の操作は行わない
5. `Check Foreground Change`を1回だけ押す
6. 実Boolは記録するが、**許可プロンプトとアクセス通知の有無だけ**をcase 4の判定に使う

> 画面mountから手順5まで、manager生成以外のclipboard read / preflightが発生しないことを
> Instrumentsまたはログで一度確認する。Paste Controlは明示mountまで生成しない。

#### ケース 10 の手順（baseline 差分の検出）

前提: **fresh process、`general` scope、未観測、Paste Control未mount**。

1. foregroundで`Check Foreground Change`を1回実行し、実戻り値がfalseであることを前提確認する
   （表示: `changed=false (first check in this screen)`）
2. trueの場合は前のtracker状態が残っているため、fresh processから試行をやり直す
3. アプリをbackgroundへ移動
4. **外部アプリでコピー**
5. アプリへ復帰し、再度`Check Foreground Change`
6. **`changed=true`のときだけ**`Read`を実行し、プロンプト / 通知を観測

case 4とcase 10は、許可状態とmanager trackerを共有しない別試行として実施する。

### 6.3 M-16（appendのprivacy継承）の手順

#### 試行の有効条件

M-16は、同一の2台・同一接続条件・同一試行内で正の対照が成功した場合だけ判定する。

- 両端末でHandoffを有効化し、同一iCloud account、Wi-Fi / Bluetooth有効を確認
- 端末A / Bの機種、OS version、OS buildを記録
- 端末BのPaste許可状態を記録し、正の対照Readを成功させて許可経路を確認
- 既定30秒は固定の成功条件ではない。正の対照に要した時間以上をtrialの待機下限にする
- 正の対照が失敗した試行は`invalid(control failed)`とし、D-8 / R-13を判断しない

#### 一続きの手順

| 手順 | 端末 | 操作 | 記録 |
|---|---|---|---|
| 1 | A/B | 接続・account・OS build・Paste許可を確認 | trial条件 |
| 2 | A | `Copy (localOnly = false)` | 正の対照開始 |
| 3 | B | 上限つきpollで`Read`し、14文字bodyの転送成功を確認 | `positiveControlTransferred=true`、所要時間 |
| 4 | A | `Clear Active Scope`し、正の対照の同期影響が収束するまで待機 | 収束時間 |
| 5 | B | `Copy B Baseline (localOnly = true)`で31文字sentinelを設定し、Readで確認 | `bBaselineSignature` |
| 6 | B | 事前signatureに14文字 / 24文字itemがないことを確認 | 衝突時はtrialをやり直す |
| 7 | A | `Copy (localOnly = true)`（body 14文字） | trial開始 |
| 8 | B | 正の対照実測時間を下限に待機後、Read | **`bodyBeforeAppend`** |
| 9 | A | `Append Universal Marker`（24文字） | — |
| 10 | B | 同条件で待機後、Read | **`bodyAfterAppend` / `appendAfterAppend`** |

端末Bの既知baselineは、Bで`localOnly=true`を使って作る。端末Bのgeneral pasteboardを単純にClearすると
そのClear自体が端末Aへ同期しうるため、Aのtrial開始前に同期影響の収束を確認する。

#### 端末Bでの判別方法

raw値は表示せず、`Read`の`index / hasText / textLength`から判定する。

| text length | 意味 |
|---:|---|
| 14 | trial body |
| 24 | append marker |
| 31 | 端末Bの既知baseline sentinel |

各Readでは全itemのsignatureを記録する。固定長の偶然衝突を避けるため、手順6で14 / 24文字itemが
事前に存在しないことを必須にする。存在した場合はsentinelを設定し直し、衝突が消えるまでtrialを開始しない。

#### 3観測値と帰結

bit順は`bodyBeforeAppend / bodyAfterAppend / appendAfterAppend`とする。

| bit | 解釈 | D-8 / R-13への帰結 |
|---|---|---|
| `000` | bodyはappend前後とも非転送、markerも非転送 | 正の対照成功済みの場合のみ「appendはlocal-only状態を維持」と観測。D-8維持、R-13追加API不要候補 |
| `001` | bodyは非転送、append markerだけ転送 | append itemにprivacy optionが継承されない。R-13で追加APIを検討 |
| `010` | append後にbodyだけ転送 | appendが既存bodyを再公開した異常候補。再試験しR-13を検討 |
| `011` | append後にbodyとmarkerが転送 | appendがpasteboard全体を再公開。R-13を検討 |
| `100` | bodyがappend前に転送、その後は見えない | `localOnly=true`不成立または観測不整合。append継承は判定不能 |
| `101` | bodyがappend前に転送、append後はmarkerだけ | `localOnly=true`不成立。append結果は診断情報として記録するがR-13判断に使わない |
| `110` | bodyがappend前後に転送、markerは非転送 | `localOnly=true`不成立。M-06と接続条件を再確認 |
| `111` | bodyもmarkerも転送 | `localOnly=true`不成立。append継承は単独評価できない |

`positiveControlTransferred != true`、Paste許可未確定、または事前signature衝突があるtrialは、
bit値にかかわらず`invalid`であり、D-8 / R-13の結論へ使用しない。

**iOS 18 / iOS 26を含む端末組合せで観測し、6.5へ1 trial 1行で記録する。**


### 6.4 プロンプト / 通知の観測テンプレート

企画書は 16 ケースを iOS 18 / iOS 26 の双方で観測し、「許可プロンプト」と「アクセス通知」を
**別々に**記録することを要求している。

| # | 操作 | 許可プロンプト(iOS 18) | アクセス通知(iOS 18) | 許可プロンプト(iOS 26) | アクセス通知(iOS 26) |
|---|---|---|---|---|---|
| 1 | 自アプリ copy → Read | 未計測 | 未計測 | 未計測 | 未計測 |
| 2 | 外部 copy → Read | 未計測 | 未計測 | 未計測 | 未計測 |
| 3 | 外部 copy → Snapshot のみ | 未計測 | 未計測 | 未計測 | 未計測 |
| 4 | 外部 copy → **fresh 初回 Check** | 未計測 | 未計測 | 未計測 | 未計測 |
| 5 | 外部 copy → Detect Patterns | 未計測 | 未計測 | 未計測 | 未計測 |
| 6 | 外部 copy → Detect Values | 未計測 | 未計測 | 未計測 | 未計測 |
| 7 | Paste Control タップのみ | `N/A (sample); harness: <ref>` | 〃 | 〃 | 〃 |
| 8 | 標準編集メニューの paste | `N/A (sample); harness: <ref>` | 〃 | 〃 | 〃 |
| 9 | 承認直後の再 Read | 未計測 | 未計測 | 未計測 | 未計測 |
| 10 | background 差分 → Read | 未計測 | 未計測 | 未計測 | 未計測 |
| 11 | Universal Clipboard → Read | 未計測 | 未計測 | 未計測 | 未計測 |
| 12 | `contains` のみ | `N/A (sample); harness: <ref>` | 〃 | 〃 | 〃 |
| 13 | `itemProviders` getter のみ | `N/A (sample); harness: <ref>` | 〃 | 〃 | 〃 |
| 14 | `canLoadObject` のみ | `N/A (sample); harness: <ref>` | 〃 | 〃 | 〃 |
| 15 | 実ロード | `N/A (sample); harness: <ref>` | 〃 | 〃 | 〃 |
| 16 | Paste Control → 自動ロード | 未計測 | 未計測 | 未計測 | 未計測 |

**実施不能ケースは空欄にせず `N/A (sample); harness: <結果 or 参照>` と記録する**（低 1）。
空欄では「未着手」「測定失敗」「サンプル対象外」を区別できない。

### 6.5 M-16専用のtrial結果表

Universal Clipboardは両端末と接続条件の組合せに依存するため、iOS versionを列にした集約表ではなく、
**1 trialを1行**として保存する。

| trial | A端末 / OS build | B端末 / OS build | account・Handoff・Wi-Fi・BT | B Paste許可 | 正対照 / 秒 | B事前signature | 待機秒（前/後） | bodyBefore | bodyAfter | appendAfter | bit | 有効性 | 結論 | D-8 / R-13 | 追跡 |
|---|---|---|---|---|---|---|---|---:|---:|---:|---|---|---|---|---|
| M16-001 | 未計測 | 未計測 | 未計測 | 未計測 | 未計測 | 未計測 | 未計測 | — | — | — | — | 未計測 | 未計測 | 未計測 | — |

記録規約:

- `正対照`は`localOnly=false`の転送成否と所要秒。falseならtrialは必ずinvalid
- `B事前signature`にはitem数と各itemの`hasText / textLength / typeIdentifierCount`を値なしで記録
- `bodyBefore` / `bodyAfter` / `appendAfter`は6.3の3観測値と同じ意味で、別名を使わない
- iOS 18 / iOS 26は片側OSの列ではなく、A/Bの具体的な組合せとして複数trialを追加する
- 有効な再試行は新しいtrial IDで追記し、失敗したtrialを上書きしない


### 6.6 実施不能ケースの移管先

| ケース | 理由 | 移管先 |
|---|---|---|
| 7 | 現在の control は tap 後に必ず receiver 内の load へ進み、**ケース 16 と分離できない** | T-00 harness |
| 8 | 標準編集メニューを表示し receiver を first responder にする UI 導線がない | T-00 harness |
| 12 | `contains(pasteboardTypes:)` は公開 API 外 | T-00 harness |
| 13〜15 | `loadItem` が 3 段階を 1 操作へ内包 | T-00 harness |

**T-00 harness には生 UIKit 呼び出しが必要なため、本サンプルアプリへは混ぜない。**
**分離できない操作を一括実行して「privacy 契機を特定した」と判断してはならない。**

---

## 7. 変更ファイル一覧

### 7.1 新規作成

| パス | 内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift` | 機能本体。`ClipboardPasteControlView` と `ClipboardSampleIdentifiers` も同ファイル内 |

### 7.2 既存変更

| パス | 変更内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ContentView.swift` | Clipboard の `NavigationLink` + `menuCard` を追加。identifier 付与 |
| `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift` | Clipboard の XCUITest を追加（9 章） |
| **`ios/IosLibraryExample/IosLibraryExample.xcodeproj/xcshareddata/xcschemes/IosLibraryExample.xcscheme`** | **`IosLibraryExampleUITests` の `parallelizable` を `YES` → `NO`**（中 4） |

`parallelizable = "YES"` のままだと、Simulator の general pasteboard を共有する Clipboard テストが
他テストと並列に走り、結果が非決定的になる。scheme を変更するか test plan を導入する必要がある。
**既存 scheme の変更が最小のため scheme を選ぶ。**

### 7.3 非変更

| パス | 理由 |
|---|---|
| `IosLibraryExampleApp.swift` | Clipboard は起動時セットアップ不要 |
| 既存 3 サンプル View | 影響なし |
| `IosLibraryExample.xcodeproj/project.pbxproj` | `PBXFileSystemSynchronizedRootGroup` 採用済み（確認済み）。UI test 側は identifier を private 定数にするため project 設定変更も不要 |
| `ios/IosLibrary/**` | ライブラリ側の変更は行わない |

---

## 8. 手動確認観点

### 8.1 準備 → 実行 → 期待結果

| # | 準備 | 実行 | 期待結果 |
|---|---|---|---|
| 1 | — | Main Menu → Clipboard Example | 画面遷移する |
| 2 | — | `Copy Plain Text` → `Read` | `✅ #<n> [read] numberOfItems=1`、text あり |
| 3 | — | 9 種の Copy を順に実行し各回 `Snapshot` | `has*` と `numberOfItems` が kind に応じて変化 |
| 4 | — | `Create Named Pasteboard` → `Copy Plain Text` → `Read` | named scope で読み書きできる |
| 5 | #4 の後 | `Remove Active Pasteboard` → `Probe Last Removed Scope` | `❌ #<n> [probeRemoved] CLIPBOARD_UNAVAILABLE` |
| 6 | `Copy Plain Text` | `Append Plain Text` → `Read` | `numberOfItems` が増える |
| 7 | `Copy Plain Text` | `Load Text` | 文字数が表示される |
| 8 | `Copy URL` | `Load URL` | 文字数が表示される |
| 9 | `Copy Image File` | `Load Image` | byte 数が表示される |
| 10 | `Copy File Fixture (public.data)` | `Load File (public.data)` | `✅ #<n> [loadFile] fileSize=64`（**受け入れ試験**） |
| 11 | #10 の直後 | 一時ディレクトリを確認 | `<sessionID>/<requestID>` が残らない。**active session ディレクトリの残存は許容** |
| 12 | `Copy Image File` | `Load Image` → 完了前に `Cancel All Loads` | `ℹ️ CLIPBOARD_CANCELLED`。完了済みなら `✅`（どちらも正常） |
| 13 | `Copy Detection Fixture` | `Detect Patterns` / `Detect Values` | パターン名と各件数が表示される |
| 14 | — | `Start Observing` → `Copy Plain Text` | Events が増える |
| 15 | #14 の後 | `Stop Observing` → `Copy Plain Text` | Events が増えない |
| 16 | `Start Observing` 中 | Scope セクションと `Observe Unresolvable Named` | すべて無効（4.4） |
| 17 | fresh process・general・未観測 | `Check Foreground Change`を初回実行 | 実戻り値を保持した`✅ #<n> [checkForeground] changed=false (first check in this screen)` |
| 18 | 外部アプリでテキストをコピー → `Mount Paste Control` | Paste Controlをタップ | `items>=1, failures=0` |
| 19 | 外部アプリで画像のみコピー → `Mount Paste Control` | Paste Controlをタップ | 画像として貼り付く（M-11） |
| 20 | 外部アプリで対応外の型のみコピー → `Mount Paste Control` | Paste Controlを見る | controlが無効でタップできない。callback 0回。**ただし要検証**（下記） |
| 21 | — | Error Cases の全 11 ボタン | ボタン名どおりの `errorCode`（5.11） |
| 22 | 一連の操作後 | Xcode コンソールを確認 | クリップボード値・パス・URL・pasteboard 名が出ていない（M-15） |
| 23 | 6.2 のケース 4 手順 | T-00 ケース 4 | **fresh な状態で初回 Check**。戻り値は無視し prompt / notification のみ記録 |
| 24 | 6.2 のケース 10 手順 | T-00 ケース 10 | `changed=true` のときだけ `Read` |
| 25 | 6.3 の一続き | M-16（2 台） | 正対照成功、B既知baseline、3観測値とtrial条件を6.5へ記録 |
| 26 | 下記の一続き | M-08（非永続性） | 下記 |

#### #26 M-08の一続き手順

1. **preflight**: create → remove → no-create Readし、`CLIPBOARD_UNAVAILABLE`を確認
2. fresh create → copy → 1回目Read成功
3. background → foreground復帰 → 2回目Read成功
4. removeせずにterminate
5. launchし、前epochのsequenceを破棄
6. no-create scopeを選び、上限5秒・250ms間隔でReadをpoll
7. `CLIPBOARD_UNAVAILABLE`を確認。timeout時は最後の結果と試行回数を記録してfail

preflightで前回失敗したtestの固定named pasteboard残存を排除する。終了後を即時1回だけ判定せず、
上限つきpollでprocess teardownとの競合を吸収する。

#### #20 の要検証

Files 由来 provider は `public.file-url` やプレビュー画像も広告しうるため、
accepted type の `public.url` / `public.image` に適合してしまう可能性がある。
実施時に provider の広告 UTI を実測し、決定的な外部 fixture を特定できなければ、
**#20 は決定的な harness / library test へ委譲する**。

#### 外部アプリが必要なケース

#18 / #19 / #20 / #23 / #24 / #25、および T-00 のケース 2 / 3 / 5 / 6 / 11。

#### 本サンプルの DoD から外す観点

| 観点 | 理由 | 委譲先 |
|---|---|---|
| Paste Control の partial / all failure | 決定的に再現できない | ライブラリ unit / integration test |
| 画面離脱で監視が停止すること | 戻った画面は新しい View state になり得るため、Events が増えないことは旧 View の observer 停止を証明しない | manager / observer token を直接観測できる integration test |

### 8.2 実機必須（T-13 / M-06〜M-15）

| M-ID | 観点 | 実施 | 手順・注記 |
|---|---|---|---|
| M-06 | Universal Clipboard | 可（2 台） | 6.3の正対照を共用。同一条件で`localOnly=false`転送成功後に3観測値を確認 |
| M-07 | `expirationDate` 経過後 | 可 | `Copy (expires in 30s)` → 30 秒後に `Read` |
| M-08 | 名前付きの寿命 | 可 | 8.1 #26 の一続き手順（background 維持の確認を含む） |
| M-09 | App Group 間の読み書き | **不可** | 対象外 |
| M-10 | `UIPasteControl` の表示・貼り付け | 可 | 8.1 #18 |
| M-11 | 画像のみのクリップボード | 可 | 8.1 #19 |
| M-12 | 一時ファイル cleanup | **部分実施** | 下記 |
| M-13 | 画像コスト | **部分実施** | 下記 |
| M-14 | 二重報告なし | 可 | 下記 |
| M-15 | ログに機微情報が出ていない | 可 | 8.1 #22 |

#### M-12（部分実施）

`ClipboardTemporaryFileStore` は **manager の use case 構築時**に生成され、initializer 内で
process 単位の startup cleanup を実行する。再起動後の最初の `Load File` が必ず契機になるわけではなく、
**manager を最初に参照した時点で起こり得る**。またその時点では新 session ディレクトリが
まだ作られていない場合があるため、cleanup 後に作られた session が残っていても
**「cleanup が既存 active session を除外した」証明にはならない**。

サンプルで観測するのは**旧 session ディレクトリの削除のみ**。

1. `Copy File Fixture` → `Load File` を実行し、session ディレクトリを作らせる
2. アプリを強制終了する
3. 旧 session ディレクトリの更新日時を 24 時間より古くする（Simulator ではファイルシステム経由で可能。実機では困難）
4. アプリを起動し、Clipboard 画面を開く
5. **旧 session ディレクトリが削除されている**ことを確認

**active-session 除外の確認は、`fileManager` と `sessionID` を注入できる harness へ委譲する。**
手順 3 が実機で完遂できない場合は、M-12 全体を T-13 harness へ委譲してよい。

#### M-13（部分実施）

| 部分 | サンプルで実施 |
|---|---|
| `imageData` 経路と `image` 経路のエンコード時間・ピークメモリ比較 | **可**（バンドル画像 + Instruments） |
| **100 MP という上限値が端末性能上妥当か** | **不可**。unit test は境界判定の正しさしか確認できない |

上限値の性能妥当性は T-13 harness へ移管する。

#### M-14 の判定規約（中 2 で強化）

v4 は「イベントが届かなければ Check=true を正常分岐」としていたが、
**Check の後に遅延 notification が届くと、同じ変更が Bool と event の 2 経路で報告される**。
Events 自体は 1 しか増えないため、「Events が 2 回増えない」だけでは検出できない。

**判定式:**

```
reportCount = eventDelta + (checkResult ? 1 : 0)
```

**settle 後の最終 `reportCount` が必ず 1 であること**を要求する。

| 手順 | 操作 | 記録 |
|---|---|---|
| 1 | `Check Foreground Change` | 比較基準の確立 |
| 2 | `Start Observing` | Events の初期値を記録 |
| 3 | アプリを background へ → **外部アプリでコピー** → 復帰 | — |
| 4 | 復帰後、**一定時間（5 秒）notification を待つ** | `eventDelta` を記録 |
| 5 | `Check Foreground Change` | `checkResult` を記録 |
| 6 | **Check 後も settle 期間（5 秒）を置く** | **late notification の有無**を記録。届いた場合は `eventDelta` を更新 |
| 7 | 最終判定 | **`reportCount == 1`** |

`reportCount == 2` は二重報告であり、M-14 の不合格。
`reportCount == 0` は「どちらの経路でも報告されなかった」ため、別の欠陥として記録する。

### 8.3 T-00

6 章を参照。**ケース 7 / 8 / 12〜15 は本サンプルでは実施できない。**

---

## 9. 自動 UI テスト計画

### 9.1 accessibility identifier の管理

XCUITest bundle は app とは**別 target・別 process**であり、app target の internal enum を
そのまま参照できない。

**方針: app 側だけを enum で一元化し、UI test 側は契約済みの identifier 文字列を private 定数として持つ。**

| target | 定義 |
|---|---|
| app | `ClipboardSampleIdentifiers`（`ClipboardSampleView.swift` 内） |
| UI test | `private enum ClipboardID { static let result = "clipboard.result" ... }` |

命名規約:

| 種別 | 命名 | 例 |
|---|---|---|
| メニューカード | `menu.<feature>` | `menu.clipboard` |
| 結果表示 | `clipboard.result` | — |
| 状態バー | `clipboard.status` | — |
| 貼り付け結果 | `clipboard.pasteSummary` | — |
| セクション | `clipboard.section.<name>` | `clipboard.section.copy` |
| ボタン | `clipboard.button.<action>` | `clipboard.button.copyPlainText` |

`<action>` は 4.5 の marker と同一の文字列にする。

### 9.2 自動化する観点

| # | 対応する手動観点 | 内容 |
|---|---|---|
| U-1 | 8.1 #1 | Main Menu → Clipboard Example の遷移と主要セクションの存在 |
| U-2 | 8.1 #2 | `Copy Plain Text` → `Read`。`marker=read`かつpayloadに`numberOfItems=1` |
| U-3 | 8.1 #3 | `Copy Plain Text` → `Snapshot` で `numberOfItems` が 1 以上 |
| U-4 | 8.1 #6 | `Copy` → `Append` → `Read` で件数が増える |
| U-5 | 8.1 #14/#15 | `Start Observing` → `Copy` で Events 増加、`Stop Observing` 後は増えない |
| U-6 | 8.1 #16 | 観測中に Scope セクションと `Observe Unresolvable Named` が無効 |
| U-7 | 8.1 #21 | **Error Cases 11 件すべて**が marker + 期待コードを表示 |
| U-8 | 8.1 #4/#5 | named 作成 → copy → read → remove → probe で `CLIPBOARD_UNAVAILABLE` |
| U-9 | — | `Clear Active Scope` 後の `Snapshot` で `numberOfItems=0` |
| U-10 | 8.1 #26 | **M-08 の完全な一続き**（下記・高 3） |
| U-11 | 8.1 #10/#11 | `Copy File Fixture` → `Load File`。`marker=loadFile`かつpayloadに`fileSize=64`、`cleanup=failed`なし。**受け入れ試験** |
| U-12 | 8.1 #17 | fresh process・general・未観測で実戻り値`changed=false`と`first check in this screen`を表示。falseへ上書きしないことはView unit testでも固定 |

#### U-10の手順

1. preflightで固定named pasteboardをcreate → remove → no-create Readし、unavailableを確認
2. fresh create → copy → 1回目Read成功
3. `XCUIDevice.shared.press(.home)`でbackgroundへ移動
4. `app.activate()`で復帰し、2回目Read成功
5. removeせずに`app.terminate()`
6. `app.launch()`後、**終了前のseqを破棄**する。result placeholderはseq 0として扱う
7. menu → `Use Fixed Named Scope (no create)`
8. 上限5秒・250ms間隔でReadをpollし、`CLIPBOARD_UNAVAILABLE`を確認

手順4は同じmarker・payloadを再実行するため、同一epoch内のsequenceでstale結果を防ぐ。
手順6以降は新process epochなので、終了前のseqと比較しない。

#### U-11 の切替条件（低 2）

`public.data` の end-to-end が成立しない場合は Files 由来 fixture へ切り替えるが、
**その時点で外部アプリ依存になるため U-11 は自動 UI テストから外し、manual / harness へ移す**。
自動試験側には「この経路が未成立であること」を失敗理由として記録する。

### 9.3 自動化しない観点と理由

| 観点 | 理由 |
|---|---|
| 8.1 #11 の実ディレクトリ確認 | app sandbox 内のファイルシステム確認が必要。U-11 は結果表示による間接確認に留まる |
| 8.1 #12（キャンセル） | 実 pasteboard の load 完了時間に依存し非決定的 |
| 画面離脱で監視が停止すること | UI から判定できない。integration test へ一本化 |
| 8.1 #18〜#20（Paste Control） | 外部アプリでのコピーと system の paste UI に依存 |
| 8.1 #22（ログ確認） | Xcode コンソールの目視 |
| 8.1 #23〜#25 / 8.2 の M-06〜M-14 | 実機・複数端末・時刻操作・Instruments が必要 |
| 6 章の T-00 | 通知・プロンプトの目視観測 |

### 9.4 テスト helper と安定化

#### 直列実行の担保（中 4）

計画は Clipboard UI テストの直列実行を前提とするが、既存 scheme は
`IosLibraryExampleUITests` が `parallelizable = "YES"` である。
**scheme を `NO` へ変更する**（7.2 に変更ファイルとして記載済み）。

単一 test class 内の順次実行だけでは、他 class との並列は防げない。
Simulator の general pasteboard は**プロセスをまたいで共有される**ため、
scheme か test plan での無効化が必要である。

#### 共通 setup helper

```
launch → menu.clipboard を tap
       → clipboard.button.clear まで scrollToHittable(.down)
       → tap → clipboard.result が "[clear]" を含むまで wait
       → 対象 section まで scrollToHittable(方向は対象位置に応じて)
```

#### scroll helper

```swift
enum ScrollDirection { case down, up }

/// Scrolls until `element` is hittable. Fails explicitly after `maxAttempts` instead of
/// swiping forever in the wrong direction.
func scrollToHittable(_ element: XCUIElement, direction: ScrollDirection, maxAttempts: Int = 10)
```

`.down` は `swipeUp()`、`.up` は `swipeDown()`。最大試行回数を超えたら `XCTFail`。

#### 待機helper

sequenceは同一View / process epoch内だけで単調増加する。

```swift
/// Returns 0 when the result is absent, is the initial placeholder, or has no valid #n.
func currentResultSequence() -> Int

/// Waits in the current process epoch until sequence > after and marker/payload both match.
func waitForResult(
    after: Int,
    marker: String,
    contains expected: String,
    timeout: TimeInterval = 5
)
```

通常の使い方:

```swift
let seq = currentResultSequence()
app.buttons[ClipboardID.read].tap()
waitForResult(after: seq, marker: "read", contains: "numberOfItems=1")
```

`app.launch()`、Clipboard画面の再生成、または明示的な再navigation後は旧seqを破棄する。
新しい画面で`currentResultSequence()`を再取得し、placeholder / parse不能なら0として次のtapを待つ。
processをまたぐ一意性はsequenceに要求しない。

U-10の終了後pollは、各tap直前に**そのepochの**seqを取得し、結果到着後にerrorCodeを評価する。
`XCTNSPredicateExpectation` + `XCTWaiter`を使い、全体上限5秒を超えたら最後のlabelを添えてfailする。


#### positive / negative assertion の分離

U-5 は次のように分ける。

1. `Start Observing` → `Copy` → **`clipboard.status` の Events 増加を predicate で待つ**（positive）
2. `Stop Observing` → `Copy` → **短い settle 期間（1 秒）を置いてから** Events が変化していないことを比較（negative）

negative assertion は predicate 待機ではなく固定 settle + 前後比較にする。

#### その他

- U-10 は `terminate()` / `launch()` をまたぐため、他テストと状態を共有しないよう独立させる

---

## 10. 追加判断（計画作成時のもの・設計書由来ではない）

| # | 判断 | 理由 |
|---|---|---|
| 1 | `async throws` 版のみを使う | 既存 `ShareSampleView` と一致 |
| 2 | `TextField` による自由入力を設けない | 既存 iOS サンプル 3 種に前例がない |
| 3 | `activeScope` と `lastRemovedScope` を保持 | S1 と M-08 の確認に必要 |
| 4 | 外部由来のクリップボード値は画面にもログにも出さない | セキュリティ方針を優先 |
| 5 | App Group（M-09）は対象外 | entitlement と 2 アプリ目が必要 |
| 6 | `ClipboardPasteControlView` / `ClipboardSampleIdentifiers` を `ClipboardSampleView.swift` 内に定義 | 他画面から再利用しない |
| 7 | 観測中は Scope 操作と `Observe Unresolvable Named` を無効化 | manager と画面の状態不整合を防ぐ |
| 8 | 上限判定はサンプルで扱わず、上限値の妥当性は harness へ | unit test と性能試験の役割分担 |
| 9 | T-00 専用 harness をサンプルアプリへ混ぜない | 生 UIKit 呼び出しは依存方針に反する |
| 10 | `Copy Custom Data` と `Copy File Fixture (public.data)` を分ける | `.file` load の provider 選択を成立させるため |
| 11 | Paste Control の partial / all failure は手動 DoD から外す | 決定的に再現できない |
| 12 | UI test 側の identifier は private 定数として複製する | project 設定変更を避ける |
| 13 | すべての結果に marker を含める | 同じ errorCode を返すボタンが複数ある |
| 14 | **結果生成操作に invocation sequence `#<n>` を含める** | 同一View / process epoch内で同じ操作のstale labelを拾わないため |
| 15 | `Check`は実Boolを表示し、初回は`first check in this screen`だけを付加 | View履歴からmanager trackerやbaseline更新成否を断定しないため |
| 16 | 監視停止の証明を手動 DoD から外す | 画面から判定できない |
| 17 | **M-16 は append 前に negative control を挟む** | `localOnly` 単独と append による再公開を分離するため（高 1） |
| 18 | **T-00 case 4 では事前 baseline 操作を行わない** | Check 自体が privacy 契機だった場合に許可状態を変え、本番観測が偽陰性になるため（高 2） |
| 19 | **M-16 の fixture は文字数を変えて区別する** | raw 値を表示しない方針を維持したまま端末 B で判別するため（中 6） |
| 20 | **xcscheme の `parallelizable` を `NO` にする** | Simulator の general pasteboard がプロセス間で共有されるため（中 4） |
| 21 | **M-16は正対照成功とB既知baselineを有効条件にする** | Handoff不調・許可拒否・既存clipboardをprivacy継承と誤判定しないため |
| 22 | **Paste Controlは明示mountまで生成しない** | T-00 case 4の最初のclipboard-aware操作をCheckに限定するため |
| 23 | **Cancelはresultを上書きしない** | pending load completionとの競合を作らないため |

---

## 11. ステップ8 実行確認

- 提示文:
  - 「この実装計画で進めますか？」
- 選択肢:
  - 承認する: 計画を確定、次のレビュー workflow（review-document）へ進む
  - 修正する: 指摘内容を反映して計画ファイルを更新
  - キャンセル: 計画ファイルは保持したまま終了
- ユーザー回答:
  - 未回答
