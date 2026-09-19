# iOS Clipboard サンプルアプリ実装計画 v4

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 対象サンプルアプリ: `ios/IosLibraryExample`
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-sample-app-design-review-v3.md`
- 前版: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v3.md`
- 対応タスク: 設計書 T-12

### v3 からの変更

| 優先度 | 指摘 | 対応 |
|---|---|---|
| 高 1 | `checkForegroundChange` の初回が必ず `false` で T-00 case 4 / 10 が成立しない | **baseline 確立を含む 5 段階手順**へ改訂。初回 `false` の意味を画面注記へ明記（5.8 / 6 / 8.1 #24） |
| 高 2 | T-00 必須観点 M-16（append の privacy 継承）が欠落 | **2 台での観測手順と記録先を新設**（6.3） |
| 高 3 | M-08 が対象 pasteboard を作らず偽陽性 | **作成 → 成功確認 → remove せず terminate** の一続き手順へ（8.1 #25 / U-10） |
| 中 1 | T-00 の記録軸が OS 別 DoD を満たさない | **iOS 18 / 26 × プロンプト / 通知の 4 列テンプレート**を新設（6.4） |
| 中 2 | M-12 の cleanup 契機が不正確 | 「manager 初参照時点で起こり得る」へ訂正。active-session 除外は harness へ委譲（8.2） |
| 中 3 | scroll helper が上方へ戻れない | 方向を引数化し、最大試行後に明示 fail（9.4） |
| 中 4 | 古い `✅` を拾う偽陽性 | **operation marker を必須化**し、marker + payload を同時待機（4.5 / 9.4） |
| 中 5 | #18 が監視停止を証明できない | 手動 DoD から削除。integration test へ一本化（8.1 / 9.3） |
| 中 6 | M-14 の判定規約がない | event count と Check 結果の組で期待値を定義（8.2） |
| 中 7 | unsupported-only fixture の保証がない | **要検証**と明記し、決定的でない場合の委譲先を記載（8.1 #21） |
| 中 8 | M-13 が部分実施 | 「部分実施」と明記し、上限値の妥当性を harness へ移管（8.2） |
| 低 1 | File fixture の payload が未確定 | 固定 byte 列と期待 `fileSize` を確定（5.2 / 9.2） |
| 低 2 | `public.data` の end-to-end が未実測 | 「決定的に成功」を撤回し、**U-11 を受け入れ試験**として扱う（5.6 / 9.2） |

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

`ClipboardItemLoaderImpl` は `providers.first { $0.hasItemConformingToTypeIdentifier(utType) }` で対象を選ぶ。
未登録の custom UTI は `public.data` へ conform しない。

**`checkForegroundChange` の baseline 契約（高 1・v4 で新規記載）**

```swift
// CheckForegroundChangeUseCase.execute
guard let current = try? repository.changeCount(scope: scope) else { return false }
var tracker = trackers[scope] ?? ClipboardChangeTracker(baseline: current)   // ← 初回は current が baseline
let changed = tracker.hasChanged(current: current)                           // ← 同じ値と比較
```

**scope ごとの tracker が存在しない状態での初回呼び出しは、必ず `false` を返す。**
これは「変化なし」ではなく **baseline の初期化**である。変化検出には最低 2 回の呼び出しが要る。

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
| 100 MP という**上限値の妥当性** | 扱わない | T-13 harness（中 8・8.2） |
| タイムアウト | 扱わない | unit test（短縮設定） |
| Paste Control の partial / all failure | 扱わない | ライブラリ unit / integration test |
| 監視停止の証明 | 扱わない | integration test（中 5・9.3） |
| active session の cleanup 除外 | 扱わない | 注入可能な harness（中 2・8.2） |

### 1.6 不足前提

| 項目 | 内容 |
|---|---|
| T-00 未実施 | **本サンプル単独では完遂できない**（6 章） |
| `UIColor` の UTI | `"com.apple.uikit.color"` は公式ドキュメント未確認。**要検証** |
| App Group（M-09） | entitlement と 2 アプリ目が必要。**対象外** |
| `public.data` の end-to-end | `UIPasteboard.items` へ Data を書いた後の `itemProviders → loadFileRepresentation` 経路は未実測。**U-11 を受け入れ試験として扱う**（低 2・5.6） |
| unsupported-only fixture | Files 由来 provider が `public.file-url` やプレビュー画像も広告しうるため、「対応外型のみ」を決定的に作れる保証がない。**要検証**（中 7・8.1 #21） |

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

**変更**: `ContentView.swift`、`IosLibraryExampleUITests.swift`

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
[✅/❌/ℹ️/⚠️ [<marker>] ...]                  <- clipboard.result
[Scope: general | Observing: off | Events: 0] <- clipboard.status
[Paste result: -]                             <- clipboard.pasteSummary
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
| `activeScope: PasteboardScope` | `@State` | 操作対象 scope |
| `lastRemovedScope: PasteboardScope?` | `@State` | remove 後の解決不能確認 |
| `observedEventCount: Int` | `@State` | 監視イベント受信数 |
| `isObserving: Bool` | `@State` | 監視中フラグ |
| `pastedSummary: String` | `@State` | S11 の結果集約 |
| `activeScopeLabel: String` | computed | `activeScope` から導出。kind と名前長のみ |

### 4.4 ボタン活性条件

| ボタン | `isObserving == false` | `isObserving == true` |
|---|---|---|
| `Start Observing` | 有効 | 無効 |
| `Stop Observing` | 無効 | 有効 |
| Scope セクションの全ボタン | 有効 | 無効 |
| `Observe Unresolvable Named → UNAVAILABLE` | 有効 | 無効 |

### 4.5 結果表示形式（中 4・operation marker を必須化）

**すべての結果に、操作を一意に識別する marker を含める。**
marker がないと、UI テストが直前の操作の結果を拾って偽陽性になる（9.4）。

| 種別 | 形式 |
|---|---|
| 成功 | `✅ [<marker>] <payload>` |
| 失敗 | `❌ [<marker>] errorCode=<code>, errorMessage=<message>` |
| キャンセル | `ℹ️ [<marker>] Cancellation completed (CLIPBOARD_CANCELLED)` |
| 警告（cleanup 失敗） | `⚠️ [<marker>] fileSize=<n>, cleanup=failed` |

marker は**ボタンごとに一意**とする（例: `copyPlainText` / `read` / `snapshotMatching` /
`errorRemoveGeneral`）。同じ errorCode を返すボタンが複数あるため、コードだけでは識別できない。

### 4.6 値の表示方針（確定）

| 対象 | 画面表示 | ログ |
|---|---|---|
| 外部由来のクリップボード値 | 表示しない | 出さない |
| ファイルパス・URL・pasteboard 名 | 表示しない | 出さない |
| 件数 / byte 数 / 文字数 / 型識別子 / kind / errorCode | 表示する | 出す |

`updateResult` は `resultText` を更新するが、**result 本文をログへ出さない**（marker と `isSuccess` のみ）。

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
| **`Copy File Fixture (public.data)`** | **`.customData(Self.fileFixturePayload, utType: "public.data")`** |
| `Copy Multiple Text` | `.multipleText(["first", "second", "third"])` |
| `Copy Multi Representation` | `.multiRepresentation(["public.plain-text": ..., "public.utf8-plain-text": ...])` |
| `Copy Detection Fixture` | 5.7 の固定文字列 |
| `Copy Universal Fixture (localOnly=false)` | M-16 用（6.3） |

定数（低 1）:

```swift
static let customTypeIdentifier = "com.jonghyunkim.nativetoolkit.example.custom"
/// 64 bytes の固定 payload。U-11 が `fileSize=64` を期待値として判定できるようにする。
static let fileFixturePayload = Data(repeating: 0x41, count: 64)
```

#### `Copy File Fixture (public.data)` を分ける理由

`.file(utType:)` は `hasItemConformingToTypeIdentifier(utType)` で provider を選ぶ。
未登録の custom UTI は `public.data` へ conform しないため、`Copy Custom Data` の直後に
`Load File (public.data)` を実行しても `CLIPBOARD_NO_MATCHING_ITEM` になる。

`.file` 確認専用に、**登録済み UTType である `public.data` として書き込む fixture** を分ける。
`Copy Custom Data` は custom UTI のコピー経路の確認として残す（Load 対象にしない）。

### 5.3 Copy Options（S3 / P-1）

| ボタン | options |
|---|---|
| `Copy (localOnly = true)` | `ClipboardCopyOptions(localOnly: true, expirationDate: nil)` |
| `Copy (localOnly = false)` | `localOnly: false`（M-06 の正の対照） |
| `Copy (expires in 30s)` | `expirationDate: Date().addingTimeInterval(30)`（M-07） |

### 5.4 Append（S4 / P-2）

| ボタン | 動作 |
|---|---|
| `Append Plain Text` | `append(.plainText("appended item"))` |
| `Append URL` | `append(.url("https://developer.apple.com"))` |
| **`Append Universal Marker`** | M-16 用（6.3）。`append(.plainText("APPENDED-MARKER-<UUID prefix>"))` |

注記: `append` は options を受け取れず、privacy option の継承は保証されない（M-16）。

> T-00 の結果で変わりうる箇所。継承されないと判明した場合、`appendPreservingOptions`（R-13）が検討される。

### 5.5 Read / Inspect（S5 / S7 / P-3 / P-4 / P-5）

| ボタン | marker | 表示内容（値は出さない） |
|---|---|---|
| `Read` | `read` | `numberOfItems`、各 item の `typeIdentifiers.count`、`text` の有無と文字数、`urlString` の有無 |
| `Read Data (public.png)` | `readData` | byte 数、または `nil` |
| `Snapshot` | `snapshot` | `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `numberOfItems` / `typeIdentifiers.count` |
| `Snapshot (matching public.plain-text)` | `snapshotMatching` | 上記 + `matchingItemIndexes` |

### 5.6 Load（S6 / P-11 / P-12）

| ボタン | marker | request | 前提 | 表示 |
|---|---|---|---|---|
| `Load Text` | `loadText` | `.text` | `Copy Plain Text` | 文字数のみ |
| `Load URL` | `loadURL` | `.url` | `Copy URL` | 文字数のみ |
| `Load Image` | `loadImage` | `.image` | `Copy Image File` | byte 数 |
| `Load File (public.data)` | `loadFile` | `.file(utType: "public.data")` | `Copy File Fixture (public.data)` | `fileSize`（期待 64）。取得後に削除 |
| `Cancel All Loads` | — | — | — | `cancelAllLoads()` |

> **要検証（低 2）**: provider 選択が成立することは実装から確認できるが、
> `UIPasteboard.items` へ Data を書いた後の `itemProviders → loadFileRepresentation` 経路は未実測である。
> 既存の file load テストは `registerFileRepresentation` 済みの provider を使っており、経路が異なる。
> **U-11 は「決定的に成功する前提の回帰テスト」ではなく、この経路の受け入れ試験として扱う。**
> 失敗した場合は、Files 由来の既知 file representation を外部 fixture として使う方式へ切り替える。

#### `.file` の所有権と cleanup

一時ファイルの階層:

```
<NSTemporaryDirectory()>/IosLibraryClipboard/<sessionID>/<requestID>/<UUID>.<ext>
                                              ^^^^^^^^^  ^^^^^^^^^
                                              session    request ← 呼び出し側が削除するのはこちら
```

**削除対象は `<requestID>` ディレクトリ。** active session ディレクトリはライブラリが管理し、残存して正常。

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

| 項目 | 契約 |
|---|---|
| 呼び出し側への通知 | `CLIPBOARD_CANCELLED` を完了として返す |
| system load | `Progress.cancel()` を試みる |
| 遅延到着した結果 | 破棄する（一時ファイルも削除） |
| **OS 処理そのものの中断** | **保証しない** |

| 前提 | 操作 | 期待結果 |
|---|---|---|
| `Copy Image File` 済み | `Load Image` → 完了前に `Cancel All Loads` | `ℹ️ [loadImage] CLIPBOARD_CANCELLED` |
| 同上 | `Load Image` が先に完了 | `✅ [loadImage] ...`（**これも正常**） |

`Cancel` ボタンは結果表示を上書きしない。`loadItem` 側の completion が唯一の更新元。

### 5.7 Detect（S10 / P-9 / P-10）

| ボタン | 動作 |
|---|---|
| `Copy Detection Fixture` | 11 パターンを含む固定文字列をコピー |
| `Detect Patterns (all 11)` | `detectPatterns(Set(ClipboardDetectionPattern.allCases))` → パターン名の一覧 |
| `Detect Values (all 11)` | `detectValues(...)` → 各配列の件数のみ |

fixture:

```
Visit https://www.apple.com or email support@example.com.
Call +1 (408) 996-1010. Ship to 1 Infinite Loop, Cupertino, CA 95014.
Meeting on March 3, 2027 at 10:00 AM. Flight AA100. Total 1,234.56 USD.
Tracking 1Z999AA10123456784. Search: swift concurrency. Number 42.
```

> 要検証: DataDetection の結果は OS バージョンとロケールに依存する。11 パターンすべてが
> 単一文字列で検出される保証はない。検出されなかったパターンは、fixture の不備か API の挙動かを
> 切り分けて記録する（断定しない）。

### 5.8 Observe（S9 / P-13 / P-14 / P-15）

| ボタン | marker | 動作 |
|---|---|---|
| `Start Observing` | `startObserving` | `try startObserving(scope: activeScope) { ... }`。成功時のみ `isObserving = true` |
| `Stop Observing` | `stopObserving` | `stopObserving()`。`isObserving = false` |
| `Check Foreground Change` | `checkForeground` | `checkForegroundChange(scope:)` → `Bool` |

#### `Check Foreground Change` の表示（高 1）

初回呼び出しは baseline 初期化のため必ず `false` を返す。これを「変化なし」と誤読させないため、
**画面表示と注記の双方で区別する**。

- 画面: `✅ [checkForeground] changed=false (baseline established)` / `changed=true`
- 内部で scope ごとに「1 回でも呼んだか」を保持し、初回だけ `(baseline established)` を付す

注記テキスト:

> `Check Foreground Change` の**初回は必ず false** です。これは変化がないという意味ではなく、
> 比較の基準（baseline）を作った、という意味です。変化を検出するには 2 回目以降を使ってください。

#### 状態遷移

`startObserving` は新しい scope を解決する**前に既存観測を停止する**。そのため観測中に
解決不能な scope で呼ぶと、manager は停止済み・画面は `isObserving == true` という不整合が起きる。

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
サンプルが作成した named / unique pasteboard は破棄しない（非永続性の確認に使うため）。

注記: 通知はアプリが foreground の間のみ届く。

> `Check Foreground Change` は T-00 の結果で変わりうる箇所。

### 5.9 Paste Control（S11 / P-16）

#### scope の制約

`makePasteControl` に scope 引数はない。Paste Control は `activeScope` とは独立して
**system の general pasteboard を対象**にする。セクション注記へ明記する。

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

`ClipboardPasteReceiverView.canPaste` は provider に accepted type が 1 件もなければ `false` を返すため、
**「対応外型のみ → all failure」には到達しない**。

**partial failure / all failure は本サンプルの手動 DoD から外す。** 決定的な再現には
「accepted type を宣言しつつ load に失敗する provider」が必要で、外部アプリ操作では作れない。
ライブラリの `PasteItemProviderLoaderTests` / `ClipboardPasteReceiverViewTests` へ委譲する。

`resultText` は Paste Control では更新しない。

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

**同じ errorCode を返すボタンが複数あるため（`EMPTY_ITEMS` 2 件、`INVALID_TYPE` 2 件）、
marker が識別に必須**（4.5 / 中 4）。

入力の根拠:

- `"not a valid identifier!!"` — `UTType` が解決せず逆 DNS 形式でもないため `validateGeneric` が拒否
- `"example.com"` — scheme が nil のため `validateURL` が拒否
- `.color(red: 2.0, ...)` — `validateColor` が 0...1 の範囲外を拒否

`Observe Unresolvable Named` は観測中は無効。実行時は catch で `isObserving = false`。

---

## 6. T-00（実機プライバシースパイク）の実施境界

### 6.1 対応表

企画書の行列は「**直前の状況**」と「**実行する操作**」の組であり、同じ API を押せるだけでは
ケースを満たさない。

| # | 直前の状況 | サンプルでの操作 | 実施可否 |
|---|---|---|---|
| 1 | **自アプリ**でコピーした直後 | `Copy Plain Text` → `Read` | 可 |
| 2 | **他アプリ**でコピーされた内容 | （外部コピー後）`Read` | 可 |
| 3 | **他アプリ**でコピーされた内容 | （外部コピー後）`Snapshot` のみ | 可 |
| 4 | 他アプリでコピーされた内容 | `Check Foreground Change`（**baseline 確立が前提**・6.2） | 可 |
| 5 | **他アプリ**でコピーされた内容 | （外部コピー後）`Detect Patterns` | 可 |
| 6 | **他アプリ**でコピーされた内容 | （外部コピー後）`Detect Values` | 可 |
| 7 | 他アプリでコピーされた内容 | `UIPasteControl` を**タップのみ**（ロードしない） | **不可** |
| 8 | 他アプリでコピーされた内容 | 標準の編集メニューの「ペースト」 | **不可** |
| 9 | 一度承認した直後に再度読む | `Read` を連続実行 | 可 |
| 10 | background 復帰直後 | 6.2 の 5 段階手順 | 可 |
| 11 | Universal Clipboard 経由 | `Snapshot` → `Read` | 可（2 台） |
| 12 | 他アプリでコピーされた内容 | `contains(pasteboardTypes:)` のみ | **不可**（公開 API 外） |
| 13 | 他アプリでコピーされた内容 | `itemProviders` getter のみ | **不可** |
| 14 | ケース 13 の直後 | 取得済み provider へ `canLoadObject` のみ | **不可** |
| 15 | ケース 14 の直後 | 取得済み provider へ実ロード | **不可** |
| 16 | 他アプリでコピーされた内容 | `UIPasteControl` タップ → 内部で自動ロード | 可 |

### 6.2 ケース 4 / 10 の手順（高 1）

`checkForegroundChange` は **scope ごとの初回呼び出しが必ず `false`**（1.3）。
v3 の手順は外部コピー・復帰後に初めて Check を押していたため、`false` になり
条件付きの `Read` へ到達しなかった。

**ケース 10 の正しい順序:**

1. foreground で `Check Foreground Change` を 1 回実行し、**baseline を確立**（`changed=false (baseline established)` を確認）
2. アプリを background へ移動
3. **外部アプリでコピー**
4. アプリへ復帰し、再度 `Check Foreground Change`
5. **`changed=true` のときだけ** `Read` を実行し、プロンプト / 通知を観測

**ケース 4 の扱い:** 初回 `false` は baseline 初期化である旨を記録し、
変化検出を見る場合は baseline 確立後の 2 回目以降で確認する。

### 6.3 M-16（append の privacy 継承）の手順（高 2）

設計 v4 は T-00 の必須観点として M-16 を定義している。
「`copy(localOnly: true)` の直後に `append` した item が Universal Clipboard へ転送されるか」を
2 台で観測し、**D-8 / R-13 の判断材料**にする。v3 には手順・期待結果・記録先がなかった。

| 手順 | 端末 | 操作 |
|---|---|---|
| 1 | A | `Use General` |
| 2 | A | `Copy (localOnly = true)` — 識別可能な固定文字列（例: `LOCALONLY-BODY`） |
| 3 | A | `Append Universal Marker` — 別内容の識別子（例: `APPENDED-MARKER-<UUID 先頭 8 桁>`） |
| 4 | B | 転送を待ち、`Read` で item を確認 |
| 5 | B | **copy 本体と append item を区別**して、どちらが転送されたかを記録 |

期待の分岐:

| 観測結果 | 意味 | 帰結 |
|---|---|---|
| 両方とも転送されない | `append` が privacy option を継承した | D-8 のまま。R-13 の追加 API は不要 |
| **append item だけ転送された** | **継承されない** | R-13 の `appendPreservingOptions` 採否を検討。ただし「読み直しが許可プロンプトの契機になりうる」問題があるため、ケース 2 の結果とあわせて判断する |
| copy 本体も転送された | `localOnly: true` が効いていない | M-06 の結果と矛盾。再試験 |

**iOS 18 / iOS 26 の双方で観測し、6.4 のテンプレートへ記録する。**

### 6.4 観測結果テンプレート（中 1）

企画書は 16 ケースを iOS 18 / iOS 26 の双方で観測し、「許可プロンプト」と「アクセス通知」を
**別々に**記録することを要求している。v3 の「プロンプト / 通知の有無」1 列では分離できない。

| # | 操作 | 許可プロンプト(iOS 18) | アクセス通知(iOS 18) | 許可プロンプト(iOS 26) | アクセス通知(iOS 26) |
|---|---|---|---|---|---|
| 1 | 自アプリ copy → Read | 未計測 | 未計測 | 未計測 | 未計測 |
| 2 | 外部 copy → Read | 未計測 | 未計測 | 未計測 | 未計測 |
| … | … | … | … | … | … |
| M-16 | localOnly copy → append → 2 台観測 | 未計測 | 未計測 | 未計測 | 未計測 |

実施可否が「不可」のケースは、この表で **harness 側の記録**として空欄のまま残す。

### 6.5 実施不能ケースの移管先

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
| 2 | — | `Copy Plain Text` → `Read` | `✅ [read] numberOfItems=1`、text あり |
| 3 | — | 9 種の Copy を順に実行し各回 `Snapshot` | `has*` と `numberOfItems` が kind に応じて変化 |
| 4 | — | `Create Named Pasteboard` → `Copy Plain Text` → `Read` | named scope で読み書きできる |
| 5 | #4 の後 | `Remove Active Pasteboard` → `Probe Last Removed Scope` | `❌ [probeRemoved] CLIPBOARD_UNAVAILABLE` |
| 6 | `Copy Plain Text` | `Append Plain Text` → `Read` | `numberOfItems` が増える |
| 7 | `Copy Plain Text` | `Load Text` | 文字数が表示される |
| 8 | `Copy URL` | `Load URL` | 文字数が表示される |
| 9 | `Copy Image File` | `Load Image` | byte 数が表示される |
| 10 | `Copy File Fixture (public.data)` | `Load File (public.data)` | `✅ [loadFile] fileSize=64`（**受け入れ試験**・低 2） |
| 11 | #10 の直後 | 一時ディレクトリを確認 | `<sessionID>/<requestID>` の request ディレクトリが残らない。**active session ディレクトリの残存は許容** |
| 12 | `Copy Image File` | `Load Image` → 完了前に `Cancel All Loads` | `ℹ️ CLIPBOARD_CANCELLED`。完了済みなら `✅`（どちらも正常） |
| 13 | `Copy Detection Fixture` | `Detect Patterns` / `Detect Values` | パターン名と各件数が表示される |
| 14 | — | `Start Observing` → `Copy Plain Text` | Events が増える |
| 15 | #14 の後 | `Stop Observing` → `Copy Plain Text` | Events が増えない |
| 16 | `Start Observing` 中 | Scope セクションと `Observe Unresolvable Named` | すべて無効（4.4） |
| 17 | — | `Check Foreground Change` を初回実行 | `✅ [checkForeground] changed=false (baseline established)`（高 1） |
| 18 | 外部アプリでテキストをコピー | Paste Control をタップ | `items>=1, failures=0` |
| 19 | 外部アプリで画像のみコピー | Paste Control をタップ | 画像として貼り付く（M-11） |
| 20 | 外部アプリで対応外の型のみコピー | Paste Control を見る | control が無効でタップできない。callback 0 回。**ただし要検証**（下記） |
| 21 | — | Error Cases の全 11 ボタン | ボタン名どおりの `errorCode`（5.11） |
| 22 | 一連の操作後 | Xcode コンソールを確認 | クリップボード値・パス・URL・pasteboard 名が出ていない（M-15） |
| 23 | 6.2 の 5 段階 | T-00 ケース 10 | `changed=true` のときだけ `Read` |
| 24 | 6.3 の 5 手順 | M-16（2 台） | copy 本体と append item の転送を区別して記録 |
| **25** | **下記の一続き** | **M-08（非永続性）** | **下記** |

#### #25 M-08 の一続き手順（高 3）

v3 の手順は「terminate → launch → no create → Read」だけで、**終了前に fixed named pasteboard を
作成していなかった**。最初から存在しない名前を読んでも `CLIPBOARD_UNAVAILABLE` になるため、
テストが偽陽性になる。さらに手動表を順に実施すると #5 で remove 済みのため、
非永続性ではなく remove 結果を再確認するだけになる。

**独立した一続きの手順として実施する。**

1. `Create Named Pasteboard` → `Copy Plain Text` → `Read` が**成功**することを確認
2. アプリを background へ → foreground へ復帰 → `Read` が**まだ成功**することを確認
3. **`Remove Active Pasteboard` を実行しない**まま、アプリを terminate
4. アプリを launch → `Use Fixed Named Scope (no create)` → `Read`
5. `❌ [read] CLIPBOARD_UNAVAILABLE` を確認

手順 1・2 の成功があって初めて、手順 5 の失敗が「アプリ終了による消滅」を意味する。

#### #20 の要検証（中 7）

Files 由来の provider は `public.file-url` やプレビュー画像も広告しうるため、
accepted type の `public.url` / `public.image` に適合してしまう可能性がある。
**「対応外型のみ」を決定的に作れる保証はない。**

実施時に provider の広告 UTI を実測し、決定的な外部 fixture を特定できなければ、
**#20 は決定的な harness / library test へ委譲する**。

#### 外部アプリが必要なケース

#18 / #19 / #20 / #23 / #24、および T-00 のケース 2 / 3 / 5 / 6 / 11。
Safari（URL / テキスト）、写真（画像）、ファイル（対応外の型）を使う。

#### 本サンプルの DoD から外す観点

| 観点 | 理由 | 委譲先 |
|---|---|---|
| Paste Control の partial / all failure | 決定的に再現できない | ライブラリ unit / integration test |
| **画面離脱で監視が停止すること** | 戻った画面は新しい View state になり得るため、Events が増えないことは**旧 View の observer 停止を証明しない**（中 5） | manager / observer token を直接観測できる integration test |

### 8.2 実機必須（T-13 / M-06〜M-15）

| M-ID | 観点 | 実施 | 手順・注記 |
|---|---|---|---|
| M-06 | Universal Clipboard | 可（2 台） | `Copy (localOnly = false)` → 他端末で確認 → `Copy (localOnly = true)` → 非転送を確認 |
| M-07 | `expirationDate` 経過後 | 可 | `Copy (expires in 30s)` → 30 秒後に `Read` |
| M-08 | 名前付きの寿命 | 可 | 8.1 #25 の一続き手順 |
| M-09 | App Group 間の読み書き | **不可** | 対象外 |
| M-10 | `UIPasteControl` の表示・貼り付け | 可 | 8.1 #18 |
| M-11 | 画像のみのクリップボード | 可 | 8.1 #19 |
| M-12 | 一時ファイル cleanup | **部分実施**（下記） | — |
| M-13 | 画像コスト | **部分実施**（下記） | — |
| M-14 | 二重報告なし | 可（下記） | — |
| M-15 | ログに機微情報が出ていない | 可 | 8.1 #22 |

#### M-12（中 2 で訂正）

`ClipboardTemporaryFileStore` は **manager の use case 構築時**に生成され、initializer 内で
process 単位の startup cleanup を実行する。**再起動後の最初の `Load File` が必ず契機になるわけではない**
（manager を最初に参照した時点で起こり得る）。

またその時点では新 session ディレクトリがまだ作られていない場合があるため、
cleanup 後の `Load File` で作られた session が残っていても、
**「cleanup が既存 active session を除外した」証明にはならない**。

サンプルで観測するのは**旧 session ディレクトリの削除のみ**とする。

1. `Copy File Fixture` → `Load File` を実行し、session ディレクトリを作らせる
2. アプリを強制終了する
3. 旧 session ディレクトリの更新日時を 24 時間より古くする（Simulator ではファイルシステム経由で可能。実機では困難）
4. アプリを起動し、Clipboard 画面を開く（manager 初参照で cleanup が起こり得る）
5. **旧 session ディレクトリが削除されている**ことを確認

**active-session 除外の確認は、`fileManager` と `sessionID` を注入できる unit / integration harness へ委譲する。**
手順 3 が実機で完遂できない場合は、M-12 全体を T-13 harness へ委譲してよい。

#### M-13（中 8 で訂正）

設計 v4 の M-13 は経路比較だけでなく **`maxImagePixelCount` の妥当性確認**も要求している。

| 部分 | サンプルで実施 |
|---|---|
| `imageData` 経路と `image` 経路のエンコード時間・ピークメモリ比較 | **可**（バンドル画像という通常 fixture + Instruments） |
| **100 MP という上限値が端末性能上妥当か** | **不可**。unit test は境界判定の正しさしか確認できない |

**サンプルでの実施は「部分実施」であり、上限値の性能妥当性は T-13 harness へ移管する。**

#### M-14 の判定規約（中 6）

「通知経路で報告済みの変更が foreground check で再報告されない」ことが要件。
操作列だけでなく、**event count と `Check` 結果の組**で判定する。

| 手順 | 操作 | 期待 |
|---|---|---|
| 1 | `Check Foreground Change` | `changed=false (baseline established)` |
| 2 | `Start Observing` | 成功 |
| 3 | アプリを background へ → **外部アプリでコピー** → 復帰 | — |
| 4 | 復帰時に通知経路でイベントが届いた場合 | **Events が 1 増える** |
| 5 | `Check Foreground Change` | **`changed=false`**（同一変更が再報告されない） |
| 6 | 全体 | **同一変更で Events が 2 回増えない** |

手順 4 でイベントが届かなかった場合（background 中は通知が来ない仕様のため）は、
手順 5 が `changed=true` になる。この場合は「通知経路では報告されていない」ため二重報告ではない。
**どちらの経路で報告されたかを記録する。**

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

不一致は UI テストの失敗で検出される。identifier 専用ファイルを両 target へ所属させる案は
project 設定変更が必要になるため採らない。

命名規約:

| 種別 | 命名 | 例 |
|---|---|---|
| メニューカード | `menu.<feature>` | `menu.clipboard` |
| 結果表示 | `clipboard.result` | — |
| 状態バー | `clipboard.status` | — |
| 貼り付け結果 | `clipboard.pasteSummary` | — |
| セクション | `clipboard.section.<name>` | `clipboard.section.copy` |
| ボタン | `clipboard.button.<action>` | `clipboard.button.copyPlainText` |

### 9.2 自動化する観点

| # | 対応する手動観点 | 内容 |
|---|---|---|
| U-1 | 8.1 #1 | Main Menu → Clipboard Example の遷移と主要セクションの存在 |
| U-2 | 8.1 #2 | `Copy Plain Text` → `Read` で `✅ [read]` |
| U-3 | 8.1 #3 | `Copy Plain Text` → `Snapshot` で `numberOfItems` が 1 以上 |
| U-4 | 8.1 #6 | `Copy` → `Append` → `Read` で件数が増える |
| U-5 | 8.1 #14/#15 | `Start Observing` → `Copy` で Events 増加、`Stop Observing` 後は増えない |
| U-6 | 8.1 #16 | 観測中に Scope セクションと `Observe Unresolvable Named` が無効 |
| U-7 | 8.1 #21 | **Error Cases 11 件すべて**が marker + 期待コードを表示 |
| U-8 | 8.1 #4/#5 | named 作成 → copy → read → remove → probe で `CLIPBOARD_UNAVAILABLE` |
| U-9 | — | `Clear Active Scope` 後の `Snapshot` で `numberOfItems=0` |
| U-10 | 8.1 #25 | **M-08 の一続き**: 作成 → copy → read 成功 → **remove せず** `terminate()` → `launch()` → `Use Fixed Named Scope (no create)` → `Read` で `CLIPBOARD_UNAVAILABLE`（高 3） |
| U-11 | 8.1 #10/#11 | `Copy File Fixture` → `Load File` で `✅ [loadFile] fileSize=64` が表示され、`cleanup=failed` が出ない。**受け入れ試験**（低 2） |
| U-12 | 8.1 #17 | `Check Foreground Change` の初回が `changed=false (baseline established)` |

**U-10 は必ず作成・成功確認・非 remove を含める。** これがないと最初から存在しない名前を
読むだけの偽陽性になる（高 3）。

### 9.3 自動化しない観点と理由

| 観点 | 理由 |
|---|---|
| 8.1 #11 の実ディレクトリ確認 | app sandbox 内のファイルシステム確認が必要。U-11 は結果表示による間接確認に留まる |
| 8.1 #12（キャンセル） | 実 pasteboard の load 完了時間に依存し非決定的 |
| **画面離脱で監視が停止すること** | UI から判定できない。**integration test へ一本化**（中 5）。手動 DoD からも外す |
| 8.1 #18〜#20（Paste Control） | 外部アプリでのコピーと system の paste UI に依存 |
| 8.1 #22（ログ確認） | Xcode コンソールの目視 |
| 8.1 #23〜#24 / 8.2 の M-06〜M-14 | 実機・複数端末・時刻操作・Instruments が必要 |
| 6 章の T-00 | 通知・プロンプトの目視観測 |

### 9.4 テスト helper と安定化

#### 共通 setup helper

`Clear Active Scope` は画面下部のボタンであり、launch 直後には操作できない。

```
launch → menu.clipboard を tap
       → clipboard.button.clearActiveScope まで scrollToHittable(.down)
       → tap → clipboard.result が "[clear]" を含むまで wait
       → 対象 section まで scrollToHittable(方向は対象位置に応じて)
```

#### scroll helper（中 3）

v3 の `scrollToHittable` は `swipeUp()` しか行わず、setup で画面下部まで移動した後に
上部の Scope / Copy ボタンを探すと**さらに下へ進み続ける**。

```swift
enum ScrollDirection { case down, up }

/// Scrolls until `element` is hittable. Fails explicitly after `maxAttempts` instead of
/// swiping forever in the wrong direction.
func scrollToHittable(_ element: XCUIElement, direction: ScrollDirection, maxAttempts: Int = 10)
```

`.down` は `swipeUp()`、`.up` は `swipeDown()` を使う。最大試行回数を超えたら `XCTFail`。

#### 待機 helper（中 2 / 中 4）

`waitForExistence` は element の**出現**しか待たず、既に存在する `clipboard.result` の
**label 変化**は待たない。さらに setup の `Clear` 完了後は `clipboard.result` に既に `✅` が
残っているため、**単に `✅` を待つ predicate は新しい操作の完了前に成立する**。

**対策: operation marker と期待 payload を同時に待つ。**

```swift
/// Waits until `clipboard.result` contains BOTH the operation marker and the expected payload.
/// The marker is required: waiting on "✅" alone would match a stale result from setup, and
/// waiting on an errorCode alone would match another button that returns the same code.
func waitForResult(marker: String, contains expected: String, timeout: TimeInterval = 5)
```

実装は `XCTNSPredicateExpectation` + `XCTWaiter`。
必要に応じて **tap 前の label を控え、変化したこと**もあわせて assert する。

#### positive / negative assertion の分離

U-5 は次のように分ける。

1. `Start Observing` → `Copy` → **`clipboard.status` の Events 増加を predicate で待つ**（positive）
2. `Stop Observing` → `Copy` → **短い settle 期間（1 秒）を置いてから** Events が変化していないことを比較（negative）

negative assertion は「待って何も起きない」ことの確認なので、predicate 待機ではなく
固定 settle + 前後比較にする。

#### その他

- Simulator の general pasteboard は他テストと共有されるため、**Clipboard の UI テストは直列実行**する
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
| 8 | 上限判定はサンプルで扱わず、上限値の妥当性は harness へ | unit test と性能試験の役割分担（中 8） |
| 9 | T-00 専用 harness をサンプルアプリへ混ぜない | 生 UIKit 呼び出しは依存方針に反する |
| 10 | `Copy Custom Data` と `Copy File Fixture (public.data)` を分ける | `.file` load の provider 選択を成立させるため |
| 11 | Paste Control の partial / all failure は手動 DoD から外す | 決定的に再現できない |
| 12 | UI test 側の identifier は private 定数として複製する | project 設定変更を避ける |
| 13 | **すべての結果に operation marker を含める** | 同じ errorCode を返すボタンが複数あり、marker なしでは UI テストが偽陽性になる（中 4） |
| 14 | **`Check Foreground Change` の初回に `(baseline established)` を表示する** | 初回 `false` を「変化なし」と誤読させないため（高 1） |
| 15 | **監視停止の証明を手動 DoD から外す** | 画面から判定できない。integration test の担当（中 5） |

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
