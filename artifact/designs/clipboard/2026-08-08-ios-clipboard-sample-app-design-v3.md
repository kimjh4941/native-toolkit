# iOS Clipboard サンプルアプリ実装計画 v3

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 対象サンプルアプリ: `ios/IosLibraryExample`
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-sample-app-design-review-v2.md`
- 前版: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v2.md`
- 対応タスク: 設計書 T-12

### v2 からの変更

| 優先度 | 指摘 | 対応 |
|---|---|---|
| 高 1 | `Copy Custom Data` → `Load File (public.data)` が UTI conform しない | **専用 fixture `Copy File Fixture (public.data)` を新設**し、Copy と Load で同一 identifier を使う（5.2 / 5.6） |
| 高 2 | T-00 対応表が複数ケースを過大評価 | **「直前の状況 / サンプル操作 / 判定 / 実施可否」の 4 列**へ改め、case 1〜3 を分割。case 7 / 8 / 12〜15 を harness へ移管（6） |
| 高 3 | Paste Control の「対応外型のみ → all failure」が到達不能 | 期待値を「**control が無効、callback 0 回**」へ訂正。partial / all failure はライブラリテストへ委譲（5.9 / 8.1） |
| 中 1 | identifier の単一情報源が UI test target から参照できない | app 側は enum、UI test 側は private 定数。同期方法を明記（9.1） |
| 中 2 | UI test の非同期待機と ScrollView 操作が不足 | label 変化待機・scroll-to-hittable helper と positive/negative assertion を定義（9.4） |
| 中 3 | request directory と session directory の混同 | 用語を訂正（5.6 / 8.1 #12） |
| 中 4 | M-12 / M-13 の手順と fixture が不足 | M-12 は専用手順を定義、M-13 は境界を扱わないと訂正（8.2） |
| 中 5 | cleanup 失敗が結果領域から識別できない | `cleanup=failed` を警告表示（5.6） |
| 中 6 | 自動化可能な観点が手動に残っている | Error Cases 11 件を全自動化、terminate/relaunch を追加、U-9 の対応を訂正（9.2 / 9.3） |
| 中 7 | Observe 異常系で状態不整合 | 観測中は当該 Error Case を無効化。catch 時の状態更新を明記（5.8 / 5.11） |
| 低 1 | `.unknown(...)` が擬似コード | `ClipboardError.unknown(ClipboardFailureDetail(systemError:))` へ確定（5.9） |
| 低 2 | UI test の初期化順が不足 | 共通 setup helper の手順を明記（9.4） |

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

`IosLibrary.IosClipboardManager`（`@MainActor`）の P-1〜P-16。本サンプルは `async throws` 版と同期 API のみを使う。

### 1.3 入力制約

- `acceptedTypes` は 1 件以上必須。空配列 / 空 identifier / 不正 identifier は control 生成前に throw
- `multipleText` の空配列、`multiRepresentation` の空 object は `CLIPBOARD_EMPTY_ITEMS`
- `append` は `ClipboardCopyOptions` を受け取らない
- URL は `http` / `https`（host 必須）または `file` のみ。scheme なしは拒否
- custom UTI は `UTType` が解決するか、ASCII 英数字 + `-` `_` の 2 セグメント以上の逆 DNS 形式のみ
- サイズ上限: copy / load 各 64 MiB、画像 100 MP
- タイムアウト: detection 5s / providerLoad 15s / imageCoding 10s
- 名前付き / ユニークペーストボードは**非永続**

**`.file(utType:)` の選択規則（高 1 の根拠）**

`ClipboardItemLoaderImpl` は `providers.first { $0.hasItemConformingToTypeIdentifier(utType) }` で対象を選ぶ。
**未登録の custom UTI は `public.data` へ conform しない**ため、custom UTI でコピーした内容を
`.file(utType: "public.data")` でロードすると `CLIPBOARD_NO_MATCHING_ITEM` になる。

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
| 空内容 / 空アイテム / 不正 UTI / 不正 URL / 不正色 / 存在しないファイル / 解決不能 scope / general の remove / 空パターン集合 / 空 acceptedTypes | 扱う | 5.11（11 件） |
| 空文字列の許可（境界） | 扱う | 5.2 |
| **64 MiB 上限 / 100 MP 上限** | **扱わない** | unit test で担保済み。**M-13 でも扱わない**（8.2・中 4） |
| タイムアウト | 扱わない | unit test（短縮設定）で担保済み |

### 1.6 不足前提

| 項目 | 内容 |
|---|---|
| T-00 未実施 | **本サンプル単独では完遂できない**（6 章）。P-15 と `append` の仕様が変わりうる |
| `UIColor` の UTI | `"com.apple.uikit.color"` は公式ドキュメント未確認。**要検証** |
| App Group（M-09） | entitlement と 2 アプリ目が必要。**対象外** |
| custom UTI の file 表現 | 未登録 UTI に対する `loadFileRepresentation` の挙動は**要検証**（5.6 の注記） |

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
- **プラットフォーム制約を画面内の注記テキストで示す**
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

**問題なし。** S1〜S11 のすべてが `IosLibrary` の P-1〜P-16 で到達可能。Unity プラグイン経由でしか呼べない API は存在しない。

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
[✅/❌/ℹ️ Result: ...]                        <- clipboard.result
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
| **`Observe Unresolvable Named → UNAVAILABLE`**（Error Cases） | 有効 | **無効**（中 7） |

### 4.5 エラー表示

- 形式: `❌ \nResult: [<label>] errorCode=<code>, errorMessage=<message>`
- **`.cancelled` のみ中立表示**: `ℹ️ \nResult: [<label>] Cancellation completed (CLIPBOARD_CANCELLED)`
- **cleanup 失敗は警告表示**: `⚠️ \nResult: [<label>] fileSize=<n>, cleanup=failed`（中 5）

### 4.6 値の表示方針（確定）

| 対象 | 画面表示 | ログ |
|---|---|---|
| 外部由来のクリップボード値 | 表示しない | 出さない |
| ファイルパス・URL・pasteboard 名 | 表示しない | 出さない |
| 件数 / byte 数 / 文字数 / 型識別子 / kind / errorCode | 表示する | 出す |

`updateResult` は `resultText` を更新するが、**result 本文をログへ出さない**（`isSuccess` と label のみ）。

### 4.7 ログ表示

画面内にログ領域は設けない。`Log.d` / `Log.e` で Xcode コンソールへ出力する。

---

## 5. 実装詳細

### 5.1 Scope（S1 / P-7 / P-8）

| ボタン | 動作 |
|---|---|
| `Use General` | `activeScope = .general` |
| `Create Named Pasteboard` | `createPasteboard(.named(Self.fixedName))` → `activeScope` へ |
| `Use Fixed Named Scope (no create)` | `activeScope = .named(Self.fixedName)`（作成しない） |
| `Create Unique Pasteboard` | `createPasteboard(.unique)` → `activeScope` へ |
| `Remove Active Pasteboard` | `removePasteboard(activeScope)` → `lastRemovedScope = activeScope`、`activeScope = .general` |
| `Probe Last Removed Scope` | `read(scope: lastRemovedScope)` → `CLIPBOARD_UNAVAILABLE` を確認 |

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
| `Copy Custom Data` | `.customData(_, utType: Self.customTypeIdentifier)` |
| **`Copy File Fixture (public.data)`** | **`.customData(_, utType: "public.data")`**（高 1・下記） |
| `Copy Multiple Text` | `.multipleText(["first", "second", "third"])` |
| `Copy Multi Representation` | `.multiRepresentation(["public.plain-text": ..., "public.utf8-plain-text": ...])` |

`Self.customTypeIdentifier = "com.jonghyunkim.nativetoolkit.example.custom"`

#### `Copy File Fixture (public.data)` を分ける理由（高 1）

`.file(utType:)` は `hasItemConformingToTypeIdentifier(utType)` で provider を選ぶ。
**未登録の custom UTI は `public.data` へ conform しない**ため、`Copy Custom Data` の直後に
`Load File (public.data)` を実行しても `CLIPBOARD_NO_MATCHING_ITEM` になり、
一時ファイルの cleanup 経路（#12）にも到達しない。

そこで `.file` の確認専用に、**`public.data`（登録済み UTType）として書き込む fixture** を分けて用意する。
これにより Copy と Load が同一 identifier で対応し、決定的に成功する。

`Copy Custom Data` は custom UTI の**コピー経路の確認**として残す（Load 対象にはしない）。

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

注記: `append` は options を受け取れず、privacy option の継承は保証されない（M-16 / 要検証）。

> T-00 の結果で変わりうる箇所。

### 5.5 Read / Inspect（S5 / S7 / P-3 / P-4 / P-5）

| ボタン | 表示内容（値は出さない） |
|---|---|
| `Read` | `numberOfItems`、各 item の `typeIdentifiers.count`、`text` の有無と文字数、`urlString` の有無 |
| `Read Data (public.png)` | byte 数、または `nil` |
| `Snapshot` | `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `numberOfItems` / `typeIdentifiers.count` |
| `Snapshot (matching public.plain-text)` | 上記 + `matchingItemIndexes` |

### 5.6 Load（S6 / P-11 / P-12）

| ボタン | request | 前提 | 表示 |
|---|---|---|---|
| `Load Text` | `.text` | `Copy Plain Text` | 文字数のみ |
| `Load URL` | `.url` | `Copy URL` | 文字数のみ |
| `Load Image` | `.image` | `Copy Image File` | byte 数 |
| `Load File (public.data)` | `.file(utType: "public.data")` | **`Copy File Fixture (public.data)`**（高 1） | file size のみ。取得後に削除 |
| `Cancel All Loads` | — | — | `cancelAllLoads()` |

> 要検証: 未登録 custom UTI に対する `loadFileRepresentation` の挙動は不確実なため、
> `.file` の確認は登録済みの `public.data` で行う。custom UTI での file load は本サンプルでは扱わない。

#### `.file` の所有権と cleanup（中 3 で用語訂正）

`ClipboardLoadedItem.file(URL)` は「呼び出し側が返却 URL と**その親ディレクトリ**を削除する」契約である。

一時ファイルの階層は次のとおり。

```
<NSTemporaryDirectory()>/IosLibraryClipboard/<sessionID>/<requestID>/<UUID>.<ext>
                                              ^^^^^^^^^  ^^^^^^^^^
                                              session    request ← 呼び出し側が削除するのはこちら
```

**削除対象は `<requestID>` ディレクトリであり、session ディレクトリではない。**
active session ディレクトリはライブラリが管理し、残存して正常である。

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

**cleanup 失敗は `⚠️` の警告表示にする**（中 5）。console log だけに留めると、手動確認者が
結果領域から storage leak を識別できないため。

Paste Control の `acceptedTypes` を将来 file 系へ広げた場合も、必ずこの helper を通す。

#### キャンセル契約

| 項目 | 契約 |
|---|---|
| 呼び出し側への通知 | `CLIPBOARD_CANCELLED` を**完了として返す** |
| system load | `Progress.cancel()` を試みる |
| 遅延到着した結果 | 破棄する（一時ファイルも削除される） |
| **OS 処理そのものの中断** | **保証しない** |

`Cancel All Loads` の確認手順:

| 前提 | 操作 | 期待結果 |
|---|---|---|
| `Copy Image File` 済み | `Load Image` → 完了前に `Cancel All Loads` | `ℹ️ CLIPBOARD_CANCELLED` |
| 同上 | `Load Image` が先に完了 | `✅` の load 結果（**これも正常**） |

`Cancel` ボタンは結果表示を上書きしない。`loadItem` 側の completion が唯一の更新元。

### 5.7 Detect（S10 / P-9 / P-10）

| ボタン | 動作 |
|---|---|
| `Copy Detection Fixture` | 11 パターンを含む固定文字列をコピー |
| `Detect Patterns (all 11)` | `detectPatterns(Set(ClipboardDetectionPattern.allCases))` → パターン名の一覧 |
| `Detect Values (all 11)` | `detectValues(...)` → 各配列の件数のみ |

fixture 文字列:

```
Visit https://www.apple.com or email support@example.com.
Call +1 (408) 996-1010. Ship to 1 Infinite Loop, Cupertino, CA 95014.
Meeting on March 3, 2027 at 10:00 AM. Flight AA100. Total 1,234.56 USD.
Tracking 1Z999AA10123456784. Search: swift concurrency. Number 42.
```

> 要検証: DataDetection の結果は OS バージョンとロケールに依存する。11 パターンすべてが
> 単一文字列で検出される保証はない。検出されなかったパターンは、**fixture の不備か API の挙動かを
> 切り分けて記録する**（断定しない）。

### 5.8 Observe（S9 / P-13 / P-14 / P-15）

| ボタン | 動作 |
|---|---|
| `Start Observing` | `try startObserving(scope: activeScope) { ... }`。成功時のみ `isObserving = true` |
| `Stop Observing` | `stopObserving()`。`isObserving = false` |
| `Check Foreground Change` | `checkForegroundChange(scope:)` → `Bool` |

#### 状態遷移（中 7）

`IosClipboardManager.startObserving` は**新しい scope を解決する前に既存観測を停止する**。
したがって観測中に解決不能な scope で `startObserving` を呼ぶと、
manager 側は観測停止済み・画面側は `isObserving == true` という不整合が起きる。

対策を 2 段構えにする。

1. **観測中は `Observe Unresolvable Named` ボタンを無効化する**（4.4）
2. **`startObserving` の catch でも `isObserving = false` にする**

```swift
do {
    try IosClipboardManager.shared.startObserving(scope: scope) { ... }
    isObserving = true
} catch let error as ClipboardError {
    isObserving = false        // manager 側は停止済み。画面状態を実態へ合わせる
    updateResult(isSuccess: false, result: "...")
}
```

`onDisappear` では `stopObserving()` を呼び `isObserving = false`。
サンプルが作成した named / unique pasteboard は破棄しない（非永続性の確認に使うため）。

注記: 通知はアプリが foreground の間のみ届く。background 中の変更は `Check Foreground Change` で検知する（M-14）。

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
                onCreationFailure(.unknown(ClipboardFailureDetail(systemError: error)))   // 低 1
            }
            return UIView()
        }
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

`acceptedTypes` は `["public.plain-text", "public.url", "public.image"]`。

#### 結果集約と期待契約（高 3 で訂正）

| 状況 | control | callback | `pastedSummary` |
|---|---|---|---|
| accepted type を含む内容がある | 有効 | `onPaste` 1 回 | `items=N, failures=0` |
| **対応外の型のみ** | **無効（タップ不可）** | **0 回** | **更新されない**（高 3） |
| 部分成功 | 有効 | `onPaste` → `onPartialFailure` | `items=N, failures=M [codes]` |
| 生成失敗 | — | `onCreationFailure` | `control creation failed: <code>` |

`ClipboardPasteReceiverView.canPaste` は provider に accepted type が 1 件もなければ `false` を返すため、
**「対応外型のみ → all failure」には到達しない**。control 自体が無効になる。

**partial failure / all failure は本サンプルの手動 DoD から外す。** これらを決定的に再現するには
「accepted type を宣言しつつ load に失敗する provider」が必要で、通常の外部アプリ操作では作れない。
ライブラリの unit / integration test（`PasteItemProviderLoaderTests` / `ClipboardPasteReceiverViewTests`）へ委譲する。

`resultText` は Paste Control では更新しない（他セクションの結果を消さないため）。

注記: `UIPasteControl` はユーザーが明示的にタップした場合のみ動作し、許可プロンプトを出さない（M-10 / M-11）。

### 5.10 Clear（S8 / P-6）

| ボタン | 動作 |
|---|---|
| `Clear Active Scope` | `clear(scope: activeScope)` |

### 5.11 Error Cases（実装と全件照合済み）

| ボタン | 入力 | 期待 errorCode |
|---|---|---|
| `Copy Multiple (empty list) → EMPTY_ITEMS` | `.multipleText([])` | `CLIPBOARD_EMPTY_ITEMS` |
| `Copy Multi Representation (empty) → EMPTY_ITEMS` | `.multiRepresentation([:])` | `CLIPBOARD_EMPTY_ITEMS` |
| `Copy Image File (missing) → FILE_NOT_FOUND` | `.imageFile(path: "/nonexistent/clipboard-missing.png")` | `CLIPBOARD_FILE_NOT_FOUND` |
| `Copy Custom Data (invalid UTI) → INVALID_TYPE` | `.customData(Data([1]), utType: "not a valid identifier!!")` | `CLIPBOARD_INVALID_TYPE` |
| `Copy URL (no scheme) → INVALID_URL` | `.url("example.com")` | `CLIPBOARD_INVALID_URL` |
| `Copy Color (out of range) → INVALID_COLOR` | `.color(red: 2.0, green: 0, blue: 0, alpha: 1)` | `CLIPBOARD_INVALID_COLOR` |
| `Read Data (invalid UTI) → INVALID_TYPE` | `readData(utType: "not a valid identifier!!")` | `CLIPBOARD_INVALID_TYPE` |
| `Remove General → CANNOT_REMOVE_GENERAL` | `removePasteboard(.general)` | `CLIPBOARD_CANNOT_REMOVE_GENERAL` |
| `Observe Unresolvable Named → UNAVAILABLE` | `startObserving(scope: .named("...missing-\(UUID())"))` | `CLIPBOARD_UNAVAILABLE` |
| `Detect Patterns (empty set) → EMPTY_PATTERNS` | `detectPatterns([])` | `CLIPBOARD_EMPTY_PATTERNS` |
| `Make Paste Control (empty types) → INVALID_REQUEST` | `makePasteControl(acceptedTypes: [])` | `CLIPBOARD_INVALID_REQUEST` |

入力の根拠:

- `"not a valid identifier!!"` — `UTType` が解決せず逆 DNS 形式でもないため `validateGeneric` が拒否
- `"example.com"` — scheme が nil のため `validateURL` が拒否
- `.color(red: 2.0, ...)` — `validateColor` が 0...1 の範囲外を拒否

`Observe Unresolvable Named` は**観測中は無効**（4.4）。実行時は catch で `isObserving = false` にする（5.8）。

---

## 6. T-00（実機プライバシースパイク）の実施境界（高 2 で全面改訂）

企画書のテスト行列は「**直前の状況**」と「**実行する操作**」の組であり、同じ API を押せるだけでは
ケースを満たさない。v2 の対応表はこの点を無視していたため、4 列で作り直す。

| # | 直前の状況 | サンプルでの操作 | 判定 | 実施可否 |
|---|---|---|---|---|
| 1 | **自アプリ**でコピーした直後 | `Copy Plain Text` → `Read` | プロンプト / 通知の有無 | **可** |
| 2 | **他アプリ**でコピーされた内容 | （外部アプリでコピー後）`Read` | 同上 | **可** |
| 3 | **他アプリ**でコピーされた内容 | （外部アプリでコピー後）`Snapshot` のみ（body を読まない） | 同上 | **可** |
| 4 | 他アプリでコピーされた内容 | `Check Foreground Change`（`changeCount` のみ） | 同上 | **可** |
| 5 | **他アプリ**でコピーされた内容 | （外部アプリでコピー後）`Detect Patterns` | 同上 | **可** |
| 6 | **他アプリ**でコピーされた内容 | （外部アプリでコピー後）`Detect Values` | 同上 | **可** |
| 7 | 他アプリでコピーされた内容 | `UIPasteControl` を**タップのみ**（ロードしない） | tap 自体が契機か | **不可**（下記） |
| 8 | 他アプリでコピーされた内容 | 標準の編集メニューの「ペースト」 | 同上 | **不可**（下記） |
| 9 | 一度承認した直後に再度読む | `Read` を連続実行 | 再表示の有無 | **可** |
| 10 | background 復帰直後 | `Check Foreground Change` → **true のときだけ** `Read` | 読み取り時に出るか | **可**（手順を 8.1 #24 に定義） |
| 11 | Universal Clipboard 経由 | `Snapshot` → `Read` | 転送遅延とあわせて確認 | **可**（2 台必要） |
| 12 | 他アプリでコピーされた内容 | `contains(pasteboardTypes:)` のみ | — | **不可**（公開 API 外） |
| 13 | 他アプリでコピーされた内容 | `itemProviders` getter のみ | 取得時点が契機か | **不可**（`loadItem` に内包） |
| 14 | ケース 13 の直後 | 取得済み provider へ `canLoadObject` のみ | 型判定が契機か | **不可**（同上） |
| 15 | ケース 14 の直後 | 取得済み provider へ実ロード | ロードが契機か | **不可**（同上） |
| 16 | 他アプリでコピーされた内容 | `UIPasteControl` タップ → 内部で自動ロード | 経路全体で出るか | **可** |

### 実施不能ケースの理由と移管先

| ケース | 理由 | 移管先 |
|---|---|---|
| 7 | 現在の control は tap 後に必ず receiver 内の load へ進むため、**ケース 16 と分離できない** | T-00 harness |
| 8 | 標準編集メニューを表示し、receiver を first responder にして paste を実行する UI 導線がない。responder chain に入っているだけでは手順にならない | T-00 harness（明示的な paste 受信 UI と first-responder 操作が必要） |
| 12 | `contains(pasteboardTypes:)` は公開 API に含まれない（設計で内部限定） | T-00 harness |
| 13〜15 | `loadItem` が 3 段階を 1 操作へ内包しており分離できない | T-00 harness |

**T-00 harness には生 UIKit 呼び出しが必要になるため、本サンプルアプリへは混ぜない**
（サンプルアプリはライブラリ経由のみという依存方針に反するため）。

**分離できない操作を一括実行して「privacy 契機を特定した」と判断してはならない。**
本サンプルで観測できるのは、ケース 16 のように「経路全体として出るか」までである。

---

## 7. 変更ファイル一覧

### 7.1 新規作成

| パス | 内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift` | 機能本体。`ClipboardPasteControlView` と `ClipboardSampleIdentifiers` も同ファイル内 |

### 7.2 既存変更

| パス | 変更内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ContentView.swift` | Clipboard の `NavigationLink` + `menuCard` を追加。メニューカードへ identifier 付与 |
| `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift` | Clipboard の XCUITest を追加（9 章） |

### 7.3 非変更

| パス | 理由 |
|---|---|
| `IosLibraryExampleApp.swift` | Clipboard は起動時セットアップ不要 |
| 既存 3 サンプル View | 影響なし |
| `IosLibraryExample.xcodeproj/project.pbxproj` | `PBXFileSystemSynchronizedRootGroup` 採用済み（確認済み）。**UI test 側で identifier を private 定数にするため、project 設定変更も不要**（9.1） |
| `ios/IosLibrary/**` | ライブラリ側の変更は行わない |

---

## 8. 手動確認観点

### 8.1 準備 → 実行 → 期待結果

| # | 準備 | 実行 | 期待結果 |
|---|---|---|---|
| 1 | — | Main Menu → Clipboard Example | 画面遷移する |
| 2 | — | `Copy Plain Text` → `Read` | `numberOfItems=1`、text あり |
| 3 | — | 9 種の Copy を順に実行し各回 `Snapshot` | `has*` と `numberOfItems` が kind に応じて変化 |
| 4 | — | `Create Named Pasteboard` → `Copy Plain Text` → `Read` | named scope で読み書きできる |
| 5 | #4 の後 | `Remove Active Pasteboard` → `Probe Last Removed Scope` | `CLIPBOARD_UNAVAILABLE` |
| 6 | アプリ再起動 | `Use Fixed Named Scope (no create)` → `Read` | `CLIPBOARD_UNAVAILABLE`（M-08） |
| 7 | `Copy Plain Text` | `Append Plain Text` → `Read` | `numberOfItems` が増える |
| 8 | `Copy Plain Text` | `Load Text` | 文字数が表示される |
| 9 | `Copy URL` | `Load URL` | 文字数が表示される |
| 10 | `Copy Image File` | `Load Image` | byte 数が表示される |
| 11 | **`Copy File Fixture (public.data)`** | `Load File (public.data)` | `fileSize` が表示される（高 1） |
| 12 | #11 の直後 | 一時ディレクトリを確認 | **`<sessionID>/<requestID>` の request ディレクトリが残らない。active session ディレクトリ自体の残存は許容**（中 3） |
| 13 | `Copy Image File` | `Load Image` → 完了前に `Cancel All Loads` | `ℹ️ CLIPBOARD_CANCELLED`。完了済みなら `✅`（どちらも正常） |
| 14 | `Copy Detection Fixture` | `Detect Patterns` / `Detect Values` | パターン名と各件数が表示される |
| 15 | — | `Start Observing` → `Copy Plain Text` | Events が増える |
| 16 | #15 の後 | `Stop Observing` → `Copy Plain Text` | Events が増えない |
| 17 | `Start Observing` 中 | Scope セクションと `Observe Unresolvable Named` | すべて無効（4.4） |
| 18 | `Start Observing` 中 | 画面を離れる → 戻る → `Copy Plain Text` | Events が増えない（監視が停止している） |
| 19 | 外部アプリでテキストをコピー | Paste Control をタップ | `items>=1, failures=0` |
| 20 | 外部アプリで画像のみコピー | Paste Control をタップ | 画像として貼り付く（M-11） |
| 21 | **外部アプリで対応外の型のみコピー** | Paste Control を見る | **control が無効でタップできない。callback は 0 回**（高 3） |
| 22 | — | Error Cases の全 11 ボタン | ボタン名どおりの `errorCode`（5.11） |
| 23 | 一連の操作後 | Xcode コンソールを確認 | クリップボード値・パス・URL・pasteboard 名が出ていない（M-15） |
| 24 | 外部アプリでコピー → アプリを background → 復帰 | `Check Foreground Change` → **true のときだけ** `Read` | T-00 ケース 10 の手順（6 章） |

#### 外部アプリが必要なケース

#19 / #20 / #21 / #24、および T-00 のケース 2 / 3 / 5 / 6 / 11。
Safari（URL / テキスト）、写真（画像）、ファイル（対応外の型）を使う。

#### 本サンプルの DoD から外す観点（高 3）

Paste Control の **partial failure / all failure**。決定的に再現できないため、
ライブラリの `PasteItemProviderLoaderTests` / `ClipboardPasteReceiverViewTests` へ委譲する。

### 8.2 実機必須（T-13 / M-06〜M-15）

| M-ID | 観点 | 実施 | 手順 |
|---|---|---|---|
| M-06 | Universal Clipboard | 可（2 台） | `Copy (localOnly = false)` → 他端末で確認 → `Copy (localOnly = true)` → 非転送を確認 |
| M-07 | `expirationDate` 経過後 | 可 | `Copy (expires in 30s)` → 30 秒後に `Read` |
| M-08 | 名前付きの寿命 | 可 | 8.1 #6 |
| M-09 | App Group 間の読み書き | **不可** | 対象外（entitlement と 2 アプリ目が必要） |
| M-10 | `UIPasteControl` の表示・貼り付け | 可 | 8.1 #19 |
| M-11 | 画像のみのクリップボード | 可 | 8.1 #20 |
| M-12 | 24 時間経過分の一時ファイル cleanup | **条件付き可**（下記） | — |
| M-13 | エンコード時間・ピークメモリ | 可 | 下記 |
| M-14 | foreground 復帰時の二重報告なし | 可 | `Start Observing` → background → 外部コピー → 復帰 → `Check Foreground Change` |
| M-15 | ログに機微情報が出ていない | 可 | 8.1 #23 |

#### M-12 の手順（中 4）

単なる時刻操作では不足する。次の前後条件がそろって初めて成立する。

1. `Copy File Fixture (public.data)` → `Load File` を実行し、session ディレクトリを作らせる
2. **アプリを強制終了する**（次回起動を新しい session にするため）
3. デバイスの日付を 25 時間以上進める、または前回 session ディレクトリの更新日時を 24 時間より古くする
4. アプリを再起動し、**最初の file store 初期化**を起こす（`Load File` を 1 回実行）
5. 旧 session ディレクトリが削除され、**新 session ディレクトリは残っている**ことを確認

> 手順 3 のディレクトリ更新日時操作は、Simulator ではファイルシステム経由で可能だが実機では困難。
> **実機で完遂できない場合は T-13 の harness 側へ委譲する**と判断してよい。

#### M-13 の範囲（中 4・v2 の記述を訂正）

**サイズ・pixel の上限境界は M-13 で扱わない。** v2 は 1.5 で「扱わない」としながら
8.2 で「M-13 で扱う」と書いており矛盾していた。

M-13 は**バンドル画像という通常 fixture**での `imageData` 経路と `image` 経路の
エンコード時間・ピークメモリを Instruments で比較するに留める。
64 MiB / 100 MP の上限判定は unit test の担当であり、サンプルアプリでは扱わない。

### 8.3 T-00

6 章の 4 列対応表を参照。**ケース 7 / 8 / 12〜15 は本サンプルでは実施できない。**

---

## 9. 自動 UI テスト計画

`implement-sample-app` workflow は「手動確認観点のうち自動化可能なものを既存 UI テストターゲットへ
実装してから実機確認へ進む」ことを必須としている。既存の `IosLibraryExampleUITests` へ追加する。

### 9.1 accessibility identifier の管理（中 1）

XCUITest bundle は app とは**別 target・別 process**であり、app target の internal enum を
そのまま参照できない。現行の UI test file も `XCTest` のみを import している。

**方針: app 側だけを enum で一元化し、UI test 側は契約済みの identifier 文字列を private 定数として持つ。**

| target | 定義 |
|---|---|
| app | `ClipboardSampleIdentifiers`（`ClipboardSampleView.swift` 内） |
| UI test | `private enum ClipboardID { static let result = "clipboard.result" ... }` |

両者が一致していることは UI テストの失敗によって検出される。identifier 専用ファイルを両 target へ
所属させる案は、project 設定変更が必要になるため採らない（7.3 の非変更方針を維持）。

命名規約:

| 種別 | 命名 | 例 |
|---|---|---|
| メニューカード | `menu.<feature>` | `menu.clipboard` |
| 結果表示 | `clipboard.result` | — |
| 状態バー | `clipboard.status` | — |
| 貼り付け結果 | `clipboard.pasteSummary` | — |
| セクション | `clipboard.section.<name>` | `clipboard.section.copy` |
| ボタン | `clipboard.button.<action>` | `clipboard.button.copyPlainText` |

テストは**表示文字列ではなく identifier で特定する**。

### 9.2 自動化する観点

| # | 対応する手動観点 | 内容 |
|---|---|---|
| U-1 | 8.1 #1 | Main Menu → Clipboard Example の遷移と主要セクションの存在 |
| U-2 | 8.1 #2 | `Copy Plain Text` → `Read` で `✅` になる |
| U-3 | 8.1 #3 | `Copy Plain Text` → `Snapshot` で `numberOfItems` が 1 以上 |
| U-4 | 8.1 #7 | `Copy` → `Append` → `Read` で件数が増える |
| U-5 | 8.1 #15/#16 | `Start Observing` → `Copy` で Events 増加、`Stop Observing` 後は増えない |
| U-6 | 8.1 #17 | 観測中に Scope セクションと `Observe Unresolvable Named` が無効 |
| U-7 | 8.1 #22 | **Error Cases 11 件すべて**が期待コードを表示（中 6） |
| U-8 | 8.1 #4/#5 | named 作成 → copy → read → remove → probe で `CLIPBOARD_UNAVAILABLE` |
| U-9 | — | `Clear Active Scope` 後の `Snapshot` で `numberOfItems=0` |
| U-10 | 8.1 #6 | **`terminate()` → `launch()` → `Use Fixed Named Scope (no create)` → `Read` で `CLIPBOARD_UNAVAILABLE`**（M-08・中 6） |
| U-11 | 8.1 #11/#12 | `Copy File Fixture` → `Load File` で `fileSize` が表示され、`cleanup=failed` が**出ない** |

v2 の U-9（Back 後の no-crash）は手動 #18 の「監視が停止する」を検証していなかったため、
**#18 との対応を外した**。#18 は手動に残す（9.3）。

### 9.3 自動化しない観点と理由

| 観点 | 理由 |
|---|---|
| 8.1 #12 の実ディレクトリ確認 | app sandbox 内のファイルシステム確認が必要。UI テストからは観測できない（U-11 は結果表示による間接確認に留まる） |
| 8.1 #13（キャンセル） | 実 pasteboard の load 完了時間に依存し非決定的 |
| 8.1 #18（画面離脱で監視停止） | 画面を離れた後の観測状態を UI から判定できない。**手動、または manager を直接観測する integration test へ割り当てる** |
| 8.1 #19〜#21（Paste Control） | 外部アプリでのコピーと system の paste UI に依存 |
| 8.1 #23（ログ確認） | Xcode コンソールの目視 |
| 8.1 #24 / 8.2 の M-06〜M-14 | 実機・複数端末・時刻操作・Instruments が必要 |
| 6 章の T-00 | 通知・プロンプトの目視観測 |

### 9.4 テスト helper と安定化（中 2 / 低 2）

**共通 setup helper**（低 2）

`Clear Active Scope` は Clipboard 画面下部のボタンであり、launch 直後には操作できない。
次の順序を helper 化する。

```
launch → menu.clipboard を tap → clipboard.button.clearActiveScope まで scroll
       → tap → clipboard.result の label が "✅" を含むまで wait → 対象 section まで scroll
```

**待機 helper**（中 2）

`waitForExistence` は element の**出現**しか待たず、既に存在する `clipboard.result` /
`clipboard.status` の **label 変化**は待たない。async API の結果を即時に部分一致で読むと flaky になる。

| helper | 用途 |
|---|---|
| `waitForLabel(_ element:contains:timeout:)` | `XCTNSPredicateExpectation` + `XCTWaiter` で label の期待値を待つ |
| `scrollToHittable(_ element:)` | `isHittable` になるまで `swipeUp()` を繰り返す。off-screen ボタン対策 |

**positive / negative assertion の分離**（中 2）

U-5 は次のように分ける。

1. `Start Observing` → `Copy` → **`clipboard.status` の Events が増えるのを predicate で待つ**（positive）
2. `Stop Observing` → `Copy` → **短い settle 期間（1 秒）を置いてから** Events が変化していないことを比較（negative）

negative assertion は「待って何も起きない」ことの確認なので、predicate 待機ではなく
固定 settle + 前後比較にする。

**その他**

- Simulator の general pasteboard は他テストと共有されるため、**Clipboard の UI テストは直列実行**する
- U-10 は `terminate()` / `launch()` をまたぐため、他テストと状態を共有しないよう独立したテストにする

---

## 10. 追加判断（計画作成時のもの・設計書由来ではない）

| # | 判断 | 理由 |
|---|---|---|
| 1 | `async throws` 版のみを使う | 既存 `ShareSampleView` と一致 |
| 2 | `TextField` による自由入力を設けない | 既存 iOS サンプル 3 種に前例がなく、Android も固定データ方式 |
| 3 | `activeScope` と `lastRemovedScope` を保持 | S1 と M-08 の確認に必要 |
| 4 | 外部由来のクリップボード値は画面にもログにも出さない | セキュリティ方針を優先 |
| 5 | App Group（M-09）は対象外 | entitlement と 2 アプリ目が必要 |
| 6 | `ClipboardPasteControlView` / `ClipboardSampleIdentifiers` を `ClipboardSampleView.swift` 内に定義 | 他画面から再利用しない |
| 7 | 観測中は Scope 操作と `Observe Unresolvable Named` を無効化 | manager と画面の状態不整合を防ぐ（中 7） |
| 8 | サイズ・pixel 境界はサンプルでも M-13 でも扱わない | unit test で担保済み（中 4） |
| 9 | T-00 専用 harness をサンプルアプリへ混ぜない | 生 UIKit 呼び出しは依存方針に反する |
| 10 | **`Copy Custom Data` と `Copy File Fixture (public.data)` を分ける** | `.file` load を決定的に成功させるため（高 1） |
| 11 | **Paste Control の partial / all failure は手動 DoD から外す** | 決定的に再現できない。ライブラリテストへ委譲（高 3） |
| 12 | UI test 側の identifier は private 定数として複製する | project 設定変更を避ける。不一致はテスト失敗で検出される（中 1） |

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
