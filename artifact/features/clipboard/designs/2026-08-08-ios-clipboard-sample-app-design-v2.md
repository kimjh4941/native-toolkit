# iOS Clipboard サンプルアプリ実装計画 v2

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 対象サンプルアプリ: `ios/IosLibraryExample`
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 対象レビュー: `artifact/reviews/clipboard/2026-08-08-ios-clipboard-sample-app-design-review.md`
- 前版: `artifact/designs/clipboard/2026-08-08-ios-clipboard-sample-app-design-v1.md`
- 対応タスク: 設計書 T-12

### v1 からの主な変更

| 優先度 | 指摘 | 対応 |
|---|---|---|
| 高 1 | Error Cases 10 行中 6 行の期待コードが実装と不一致 | 実装の `errorCode` を全件照合し、確実に到達する固定入力とともに再定義（5.11） |
| 高 2 | `loadItem(.file)` の一時ディレクトリ削除責務が欠落 | `consumeLoadedFile` helper を新設し、手動確認・UI テスト観点を追加（5.6 / 8） |
| 高 3 | XCUITest と accessibility identifier の計画が欠落 | `IosLibraryExampleUITests` の変更を計画へ追加。identifier 規約と自動化／手動の分類を定義（7 / 9） |
| 高 4 | T-00 を現行 API だけで実施可能としていた | 企画書 16 ケースとの対応表を作成し、**ケース 12〜15 は専用 harness が必要**と明記（6） |
| 中 1〜7 | 状態遷移・キャンセル契約・Paste Control 契約・値表示方針・境界値・fixture | 各節で確定（5.1 / 5.6 / 5.9 / 5.5 / 1.5 / 8.2） |
| 低 1〜3 | pbxproj 要検証・状態の表示位置・導出状態 | 確認済みへ変更、wireframe と truth table を追加、`activeScopeLabel` を computed property 化 |

---

## 1. 前提情報の抽出（設計書・実装結果由来）

### 1.1 in-scope 機能

| ID | サブ機能 |
|---|---|
| S1 | ペーストボード解決（`general` / 名前付き / ユニーク名の参照・作成・破棄） |
| S2 | コピー（9 content kind） |
| S3 | コピーオプション（`localOnly` / `expirationDate`。置換コピーのみ） |
| S4 | 追記（`append`。options なし・privacy 継承保証なし） |
| S5 | ペースト（同期） |
| S6 | ペースト（`NSItemProvider` 非同期）: text / url / image / file、キャンセル、タイムアウト |
| S7 | 内容確認（`snapshot`） |
| S8 | クリア |
| S9 | 変更監視 |
| S10 | パターン検出（11 パターン） |
| S11 | 貼り付け UI（`UIPasteControl`。**ネイティブのみ**） |

S12（Unity Bridge）はサンプルアプリの対象外。

### 1.2 公開 API

`IosLibrary.IosClipboardManager`（`@MainActor`）の P-1〜P-16。callback 版と `async throws` 版の両方があるが、
本サンプルは `async throws` 版と同期 API のみを使う（9 章 追加判断 1）。

### 1.3 入力制約

- `acceptedTypes` は 1 件以上必須。空配列 / 空 identifier / 不正 identifier は control 生成前に throw
- `multipleText` の空配列、`multiRepresentation` の空 object は `CLIPBOARD_EMPTY_ITEMS`
- `append` は `ClipboardCopyOptions` を受け取らない
- URL は `http` / `https`（host 必須）または `file` のみ許可。scheme なしは拒否
- custom UTI は `UTType` が解決するか、ASCII 英数字 + `-` `_` の 2 セグメント以上の逆 DNS 形式のみ
- サイズ上限: `maxCopyByteCount` / `maxLoadByteCount` 各 64 MiB、`maxImagePixelCount` 100 MP
- タイムアウト: detection 5s / providerLoad 15s / imageCoding 10s
- 名前付き / ユニークペーストボードは**非永続**

### 1.4 エラー契約（実装から全件照合済み）

`ios/IosLibrary/IosLibrary/Clipboard/Domain/Model/ClipboardError.swift` の 24 ケース。

| case | errorCode |
|---|---|
| `emptyContent` | `CLIPBOARD_EMPTY_CONTENT` |
| `emptyItemList` | `CLIPBOARD_EMPTY_ITEMS` |
| `emptyDetectionPatterns` | `CLIPBOARD_EMPTY_PATTERNS` |
| `invalidURL` | `CLIPBOARD_INVALID_URL` |
| `invalidTypeIdentifier` | **`CLIPBOARD_INVALID_TYPE`** |
| `invalidPasteboardName` | `CLIPBOARD_INVALID_NAME` |
| `invalidColor` | `CLIPBOARD_INVALID_COLOR` |
| `invalidImageData` | `CLIPBOARD_INVALID_IMAGE_DATA` |
| `invalidExpirationDate` | `CLIPBOARD_INVALID_EXPIRATION` |
| `invalidRequest` | `CLIPBOARD_INVALID_REQUEST` |
| `contentTooLarge` | `CLIPBOARD_CONTENT_TOO_LARGE` |
| `fileNotFound` | `CLIPBOARD_FILE_NOT_FOUND` |
| `imageLoadFailed` | `CLIPBOARD_IMAGE_LOAD_FAILED` |
| `imageEncodingFailed` | `CLIPBOARD_IMAGE_ENCODE_FAILED` |
| `pasteboardUnavailable` | **`CLIPBOARD_UNAVAILABLE`** |
| `cannotRemoveGeneralPasteboard` | **`CLIPBOARD_CANNOT_REMOVE_GENERAL`** |
| `noMatchingItem` | `CLIPBOARD_NO_MATCHING_ITEM` |
| `providerLoadFailed` | `CLIPBOARD_LOAD_FAILED` |
| `unexpectedType` | `CLIPBOARD_UNEXPECTED_TYPE` |
| `fileCopyFailed` | `CLIPBOARD_FILE_COPY_FAILED` |
| `cancelled` | `CLIPBOARD_CANCELLED` |
| `timedOut` | `CLIPBOARD_TIMED_OUT` |
| `detectionFailed` | `CLIPBOARD_DETECTION_FAILED` |
| `unknown` | `CLIPBOARD_UNKNOWN` |

`errorDescription` は固定英語文で入力値を含まないため、そのまま画面表示してよい。

### 1.5 テスト観点と、サンプルアプリでの扱い

| 観点 | サンプルで扱うか | 理由・委譲先 |
|---|---|---|
| 9 content kind / 3 scope kind / 4 load kind / 11 検出パターン | 扱う | 5.2 / 5.1 / 5.6 / 5.7 |
| 空内容 / 空アイテム / 不正 UTI / 不正 URL / 存在しないファイル / 解決不能 scope | 扱う | 5.11 |
| 空文字列の許可（境界） | 扱う | 5.2 |
| **64 MiB 上限ちょうど / 100 MP 上限** | **扱わない** | 端末メモリ負荷が高く、UI 操作で再現する価値が低い。**unit test（U-13 / U-75 相当）で担保済み**。実機での挙動は T-13 の M-13（Instruments 計測）へ対応付ける |
| タイムアウト（15s / 5s / 10s） | 扱わない | 実 pasteboard では再現困難。unit test で短縮設定により担保済み |

### 1.6 不足前提（勝手に補完しない）

| 項目 | 内容 |
|---|---|
| T-00 未実施 | **本サンプルだけでは完遂できない**（6 章）。P-15 と `append` の仕様が変わりうる |
| `UIColor` の UTI | `"com.apple.uikit.color"` は公式ドキュメント未確認。**要検証** |
| App Group（M-09） | entitlement と 2 アプリ目が必要。**本計画の対象外** |

---

## 2. 既存サンプルコードの深掘り

### 2.1 確認したファイル

| パス | 役割 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ContentView.swift` | メインメニュー。`NavigationStack` + `menuCard` |
| `ios/IosLibraryExample/IosLibraryExample/ShareSampleView.swift` | 最も構成が近い参照元 |
| `ios/IosLibraryExample/IosLibraryExample/NotificationSampleView.swift` | `sectionView` / `updateResult` の共通化 |
| `ios/IosLibraryExample/IosLibraryExample/DialogSampleView.swift` | 最小構成 |
| `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift` | **既存 UI テストターゲット** |
| `android/.../example/ClipboardSampleScreen.kt` | **相互参照ペア**（Android ⇔ iOS） |

### 2.2 Android Clipboard サンプル（主参照）から踏襲する点

Android のセクション構成: `Copy` / `Copy - Sensitive` / `Read - Inspect` / `Clear` / `Observe` / `Error Cases`

踏襲するもの:

- 機能カテゴリ単位のセクション分け
- 結果表示領域を画面上部に固定し、成功/失敗を一目で判別できる文言にする
- **プラットフォーム制約を画面内の注記テキストで示す**
- Error Cases を独立セクションにし、期待するエラーコードをボタン名に含める
- 画面破棄時に監視を停止する（Android は `DisposableEffect`、iOS は `onDisappear`）

踏襲しないもの: `Toast`（iOS 既存サンプルに前例なし）、Back ボタンの明示配置（`NavigationStack` が提供）

### 2.3 iOS 既存サンプルの UI 規約（こちらを優先）

| 要素 | 規約 |
|---|---|
| 画面遷移 | `NavigationStack` + `NavigationLink`。`ContentView` の `menuCard` にエントリ追加 |
| 画面先頭 | `Text("<Manager> Example")` を `.title` + `.bold` |
| 結果表示 | `@State private var resultText`。灰色背景の角丸ボックス |
| セクション | `sectionView(title:content:)` の `@ViewBuilder` |
| ボタン | `FullWidthPressableButtonStyle`（private struct） |
| 結果更新 | `updateResult(...)`。`✅` / `❌` プレフィックス、`DispatchQueue.main.async` |
| ログ | `private let TAG`。`Log.d` / `Log.e` |
| 入力 | **固定サンプルデータ + ボタン**。`TextField` は既存サンプルに前例なし |

### 2.4 再利用 / 追加 / 変更

**再利用**: `ContentView.menuCard`、`sectionView` / `updateResult` / `FullWidthPressableButtonStyle` のパターン、`Text.buttonStyle(backgroundColor:)`

**追加**

| 名前 | 種別 | 理由 |
|---|---|---|
| `ClipboardSampleView` | `View` | 機能本体 |
| `ClipboardPasteControlView` | `UIViewRepresentable` | `ClipboardPasteControlContainerView` は `UIView` |
| `ClipboardSampleIdentifiers` | `enum` | UI テスト用 accessibility identifier の定数（9 章） |

**変更**: `ContentView.swift`（メニュー 1 件追加）、`IosLibraryExampleUITests.swift`（UI テスト追加）

---

## 3. 実装制約の確認

### 3.1 依存方向（`common.md` §サンプルアプリの依存方向）

**確認結果: 問題なし。** S1〜S11 のすべてが `IosLibrary` の `IosClipboardManager`（P-1〜P-16）で到達可能。
Unity プラグイン経由でしか呼べない API は存在しない。S11 も `IosLibrary` の Presentation 層に公開済み。

### 3.2 コーディングルール

- `agent-rules/coding-rules/common.md`: Clean Architecture、サンプルアプリの依存方向
- `agent-rules/coding-rules/ios.md`: 全 `public` / `internal` / `override` 関数の先頭に `Log.d` / `Log.e`
- **本機能特有**: クリップボード値・パス・URL・pasteboard 名をログへ出さない（値ではなく長さ / 件数 / kind）

---

## 4. 画面要件

### 4.1 導線

```
Main Menu (ContentView)
  └─ "Clipboard Example" → ClipboardSampleView
```

### 4.2 wireframe

```
[Clipboard Example]                         <- タイトル
[✅/❌ Result: ...]                          <- 結果表示（固定・上部）
[Scope: general | Observing: off | Events: 0]  <- 状態バー（1 行に集約）
[Paste result: -]                            <- pastedSummary（S11 専用・状態バー直下）
ScrollView
  ├─ Scope
  ├─ Copy
  ├─ Copy Options
  ├─ Append
  ├─ Read / Inspect
  ├─ Load (async)
  ├─ Detect
  ├─ Observe
  ├─ Paste Control (UI)
  ├─ Clear
  └─ Error Cases
```

### 4.3 状態

| 状態 | 種別 | 用途 |
|---|---|---|
| `resultText` | `@State` | 結果表示 |
| `activeScope: PasteboardScope` | `@State` | 操作対象 scope |
| `lastRemovedScope: PasteboardScope?` | `@State` | remove 後に「解決できないこと」を確認するために保持（中 1） |
| `observedEventCount: Int` | `@State` | 監視イベント受信数 |
| `isObserving: Bool` | `@State` | 監視中フラグ |
| `pastedSummary: String` | `@State` | S11 の貼り付け結果（成功件数 + failure code を 1 つに集約） |
| `activeScopeLabel: String` | **computed property** | `activeScope` から導出。kind と名前長のみ（低 3） |

### 4.4 ボタン活性条件（truth table・低 2）

| ボタン | `isObserving == false` | `isObserving == true` |
|---|---|---|
| `Start Observing` | 有効 | **無効** |
| `Stop Observing` | **無効** | 有効 |
| Scope セクションの全ボタン | 有効 | **無効**（中 7） |

観測中の scope 変更・remove は禁止する。誤って観測対象が消えた状態を作らないため。

### 4.5 エラー表示

- `catch let error as ClipboardError` で捕捉し、`errorCode` と `errorDescription` を表示
- 形式: `❌ \nResult: [<label>] errorCode=<code>, errorMessage=<message>`
- **`.cancelled` のみ中立表示**（中 2）: `ℹ️ \nResult: [<label>] Cancellation completed (CLIPBOARD_CANCELLED)`
  - 設計 v4 が「呼び出し側起点の通常系」と規定しているため、失敗として見せない

### 4.6 値の表示方針（中 4・**本版で確定**）

| 対象 | 画面表示 | ログ |
|---|---|---|
| 外部（他アプリ / 他デバイス）由来のクリップボード値 | **表示しない** | 出さない |
| ファイルパス・URL・pasteboard 名 | **表示しない** | 出さない |
| 件数 / byte 数 / 文字数 / 型識別子 / kind / errorCode | 表示する | 出す |

`updateResult` は `resultText` を更新するが、**result 本文をログへは出さない**。ログには
`isSuccess` と label のみを出す（v1 の実装例はログへ result を出していたため、この点を変更する）。

外部由来の値を一切表示しないため、`Read` などの確認はサンプル自身が直前にコピーした内容を前提とし、
件数・型・長さの一致で判定する。

### 4.7 ログ表示

画面内にログ領域は設けない。`Log.d` / `Log.e` で Xcode コンソールへ出力する。

---

## 5. 実装詳細

### 5.1 Scope（S1 / P-7 / P-8）

| ボタン | 動作 |
|---|---|
| `Use General` | `activeScope = .general` |
| `Create Named Pasteboard` | `createPasteboard(.named(Self.fixedName))` → 結果を `activeScope` へ |
| `Use Fixed Named Scope (no create)` | `activeScope = .named(Self.fixedName)`（**作成しない**。中 1） |
| `Create Unique Pasteboard` | `createPasteboard(.unique)` → 結果を `activeScope` へ |
| `Remove Active Pasteboard` | `removePasteboard(activeScope)` → 成功後 `lastRemovedScope = activeScope`、`activeScope = .general` |
| `Probe Last Removed Scope` | `lastRemovedScope` に対し `read(scope:)` → **`CLIPBOARD_UNAVAILABLE` を確認** |

`Self.fixedName = "com.jonghyunkim.nativetoolkit.example.sample"`

`Use Fixed Named Scope (no create)` があることで、**アプリ再起動後に「作成せずに参照」して非永続性（M-08）を確認**できる。
`Create` を押すとその場で再生成されてしまうため、この導線がないと M-08 が成立しない。

注記テキスト: 名前付き / ユニークペーストボードは非永続。アプリ終了で消滅する。

### 5.2 Copy（S2 / P-1）— 9 content kind

| ボタン | content |
|---|---|
| `Copy Plain Text` | `.plainText("Hello from IosLibraryExample")` |
| `Copy Plain Text (empty, allowed)` | `.plainText("")` |
| `Copy HTML Text` | `.htmlText(plain: "plain body", html: "<b>html body</b>")` |
| `Copy URL` | `.url("https://www.apple.com")` |
| `Copy Image File` | `.imageFile(path:)`（バンドルの `app-icon-attachment.png`） |
| `Copy Image Data` | `.imageData(_, utType: "public.png")` |
| `Copy Color` | `.color(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0)` |
| `Copy Custom Data` | `.customData(_, utType: "com.jonghyunkim.nativetoolkit.example.custom")` |
| `Copy Multiple Text` | `.multipleText(["first", "second", "third"])` |
| `Copy Multi Representation` | `.multiRepresentation(["public.plain-text": ..., "public.utf8-plain-text": ...])` |

すべて `activeScope` を対象にする。

### 5.3 Copy Options（S3 / P-1）

| ボタン | options |
|---|---|
| `Copy (localOnly = true)` | `ClipboardCopyOptions(localOnly: true, expirationDate: nil)` |
| `Copy (localOnly = false)` | `localOnly: false`（M-06 の正の対照） |
| `Copy (expires in 30s)` | `expirationDate: Date().addingTimeInterval(30)`（M-07） |

注記: `localOnly` の既定は `true`。`expirationDate` の効果は経過後の `Read` で確認する。

### 5.4 Append（S4 / P-2）

| ボタン | 動作 |
|---|---|
| `Append Plain Text` | `append(.plainText("appended item"))` |
| `Append URL` | `append(.url("https://developer.apple.com"))` |

注記: `append` は options を受け取れず、**先行 `copy` の privacy option 継承は保証されない**（M-16 / 要検証）。

> T-00 の結果で変わりうる箇所。継承されないと判明した場合、`appendPreservingOptions`（R-13）が追加されうる。

### 5.5 Read / Inspect（S5 / S7 / P-3 / P-4 / P-5）

| ボタン | 表示する内容（4.6 の方針に従い**値は出さない**） |
|---|---|
| `Read` | `numberOfItems`、各 item の `typeIdentifiers.count`、`text` の**有無と文字数**、`urlString` の**有無** |
| `Read Data (public.png)` | `Data` の byte 数、または `nil` |
| `Snapshot` | `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `numberOfItems` / `typeIdentifiers.count` |
| `Snapshot (matching public.plain-text)` | 上記 + `matchingItemIndexes` |

### 5.6 Load（S6 / P-11 / P-12）

| ボタン | request | 表示 |
|---|---|---|
| `Load Text` | `.text` | 文字数のみ |
| `Load URL` | `.url` | URL の**文字数のみ**（値は出さない） |
| `Load Image` | `.image` | PNG の byte 数 |
| `Load File (public.data)` | `.file(utType: "public.data")` | file size のみ。**取得後に削除**（下記） |
| `Cancel All Loads` | — | `cancelAllLoads()` |

#### `.file` の所有権と cleanup（高 2）

`ClipboardLoadedItem.file(URL)` は「**呼び出し側が返却 URL と親ディレクトリを削除する**」契約である
（`ClipboardLoadRequest.swift` の doc comment）。サンプルはこれを守る。

```swift
/// Reads the size of a loaded file and then deletes the request-scoped directory the library
/// handed over. The caller owns that directory; leaving it behind leaks one directory per tap.
/// The path is never shown on screen or logged.
private func consumeLoadedFile(_ url: URL) -> String {
    defer {
        let requestDirectory = url.deletingLastPathComponent()
        do { try FileManager.default.removeItem(at: requestDirectory) }
        catch { Log.e(TAG, "[consumeLoadedFile] cleanup failed") }   // パスは出さない
    }
    let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1
    return "fileSize=\(size)"
}
```

- 削除失敗時もユーザー操作は成功として扱い、`Log.e` に記録するのみ（サンプルの目的は API 確認のため）
- **Paste Control の `acceptedTypes` を将来 file 系へ広げた場合も、必ずこの helper を通す**

#### キャンセル契約（中 2・v1 の記述を訂正）

v1 は「配信抑止のみ」と書いたが、これは P-9 / P-10（非協調的検出 API）の説明である。P-11 は次のとおり。

| 項目 | 契約 |
|---|---|
| 呼び出し側への通知 | `CLIPBOARD_CANCELLED` を**完了として返す** |
| system load | `Progress.cancel()` を試みる |
| 遅延到着した結果 | 破棄する（一時ファイルも削除される） |
| **OS 処理そのものの中断** | **保証しない** |

`Cancel All Loads` の確認手順:

| 前提 | 操作 | 期待結果 |
|---|---|---|
| `Copy Image File` で画像をコピー済み | `Load Image` をタップ → **完了前に** `Cancel All Loads` | `ℹ️ Cancellation completed (CLIPBOARD_CANCELLED)` |
| 同上 | `Load Image` が先に完了してしまった場合 | `✅` の load 結果が表示される。**これも正常**（実 pasteboard は短時間で完了しうる） |

表示の上書き順: `Cancel` ボタンは結果を上書きしない。`loadItem` 側の completion（成功 / cancelled）が
結果表示の唯一の更新元とする。

### 5.7 Detect（S10 / P-9 / P-10）

| ボタン | 動作 |
|---|---|
| `Copy Detection Fixture` | 11 パターンを含む固定文字列をコピー（下記） |
| `Detect Patterns (all 11)` | `detectPatterns(Set(ClipboardDetectionPattern.allCases))` → 検出されたパターン名の一覧 |
| `Detect Values (all 11)` | `detectValues(...)` → **各配列の件数のみ**（値は出さない） |

fixture 文字列（中 6）:

```
Visit https://www.apple.com or email support@example.com.
Call +1 (408) 996-1010. Ship to 1 Infinite Loop, Cupertino, CA 95014.
Meeting on March 3, 2027 at 10:00 AM. Flight AA100. Total 1,234.56 USD.
Tracking 1Z999AA10123456784. Search: swift concurrency. Number 42.
```

> 要検証: DataDetection の検出結果は OS バージョンとロケールに依存する。11 パターンすべてが
> 単一文字列で検出される保証はない。実機確認時に検出されなかったパターンは、
> **fixture の不備か API の挙動かを切り分けて記録する**（断定しない）。

### 5.8 Observe（S9 / P-13 / P-14 / P-15）

| ボタン | 動作 |
|---|---|
| `Start Observing` | `try startObserving(scope: activeScope) { event in ... }`。`isObserving = true` |
| `Stop Observing` | `stopObserving()`。`isObserving = false` |
| `Check Foreground Change` | `checkForegroundChange(scope:)` → `Bool` |

- イベント表示は `kind`（`changed` / `changedDetectedOnForeground` / `removed`）と `typesAdded.count` / `typesRemoved.count`
- `startObserving` は `throws`。解決不能な scope では `CLIPBOARD_UNAVAILABLE`

#### 状態遷移（中 7）

| 契機 | 動作 |
|---|---|
| scope 変更・remove | 観測中は**ボタンを無効化**（4.4）。そもそも遷移させない |
| `onDisappear` | `stopObserving()` を呼び、`isObserving = false` |
| `onDisappear` | サンプルが作成した named / unique pasteboard は**破棄しない**（非永続性の確認に使うため。アプリ終了で自動消滅する） |

注記: 通知は**アプリが foreground の間のみ**届く。background 中の変更は `Check Foreground Change` で検知する（M-14）。

> `Check Foreground Change` は T-00 の結果で変わりうる箇所。`changeCount` が許可プロンプトの契機だった場合、
> 設計 D-3 が覆り P-15 が縮退または廃止される。

### 5.9 Paste Control（S11 / P-16）

#### scope の制約（中 6）

`makePasteControl` に **scope 引数はない**。Paste Control は画面の `activeScope` とは独立して
**system の general pasteboard を対象**にする。この点をセクション注記と状態バーの近くに明記する。

#### `UIViewRepresentable`

```swift
struct ClipboardPasteControlView: UIViewRepresentable {
    let acceptedTypes: [String]
    let onPaste: ([ClipboardLoadedItem]) -> Void
    let onPartialFailure: ([ClipboardError]) -> Void
    let onPasteFailure: (ClipboardError) -> Void
    /// 生成失敗を親へ通知する（中 3）。`makeUIView` 内で SwiftUI state を同期変更すると
    /// "Modifying state during view update" になるため、main actor の次 turn で通知する。
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
            Task { @MainActor in onCreationFailure(error) }   // 次 turn で通知
            return UIView()
        } catch {
            Task { @MainActor in onCreationFailure(.unknown(...)) }
            return UIView()
        }
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}
```

- `acceptedTypes` は `["public.plain-text", "public.url", "public.image"]`

#### 結果集約（中 3）

部分成功では `onPaste` の直後に `onPartialFailure` が呼ばれる。単一の `resultText` を順に上書きすると
成功件数が失われるため、**`pastedSummary` に集約**して 1 行で表示する。

| 状況 | `pastedSummary` |
|---|---|
| 全成功 | `items=3, failures=0` |
| 部分成功 | `items=2, failures=1 [CLIPBOARD_LOAD_FAILED]` |
| 全失敗 | `items=0, failures=1 [CLIPBOARD_NO_MATCHING_ITEM]` |
| 生成失敗 | `control creation failed: CLIPBOARD_INVALID_REQUEST` |

`onPaste` は件数のみを記録し、`onPartialFailure` は同じ `pastedSummary` へ failure code を**追記**する。
`resultText` は Paste Control では更新しない（他セクションの結果を消さないため）。

注記: `UIPasteControl` はユーザーが明示的にタップした場合のみ動作し、許可プロンプトを出さない（M-10 / M-11）。

### 5.10 Clear（S8 / P-6）

| ボタン | 動作 |
|---|---|
| `Clear Active Scope` | `clear(scope: activeScope)` |

### 5.11 Error Cases（高 1・実装と全件照合済み）

各ボタンは**確実に当該エラーへ到達する固定入力**を使う。ボタン名に期待コードを含める。

| ボタン | 入力 | 期待 errorCode |
|---|---|---|
| `Copy Multiple (empty list) → EMPTY_ITEMS` | `.multipleText([])` | `CLIPBOARD_EMPTY_ITEMS` |
| `Copy Multi Representation (empty) → EMPTY_ITEMS` | `.multiRepresentation([:])` | `CLIPBOARD_EMPTY_ITEMS` |
| `Copy Image File (missing) → FILE_NOT_FOUND` | `.imageFile(path: "/nonexistent/clipboard-missing.png")` | **`CLIPBOARD_FILE_NOT_FOUND`** |
| `Copy Custom Data (invalid UTI) → INVALID_TYPE` | `.customData(Data([1]), utType: "not a valid identifier!!")` | **`CLIPBOARD_INVALID_TYPE`** |
| `Copy URL (no scheme) → INVALID_URL` | `.url("example.com")` | `CLIPBOARD_INVALID_URL` |
| `Copy Color (out of range) → INVALID_COLOR` | `.color(red: 2.0, green: 0, blue: 0, alpha: 1)` | `CLIPBOARD_INVALID_COLOR` |
| `Read Data (invalid UTI) → INVALID_TYPE` | `readData(utType: "not a valid identifier!!")` | **`CLIPBOARD_INVALID_TYPE`** |
| `Remove General → CANNOT_REMOVE_GENERAL` | `removePasteboard(.general)` | **`CLIPBOARD_CANNOT_REMOVE_GENERAL`** |
| `Observe Unresolvable Named → UNAVAILABLE` | `startObserving(scope: .named("com.jonghyunkim.nativetoolkit.example.missing-\(UUID())"))` | **`CLIPBOARD_UNAVAILABLE`** |
| `Detect Patterns (empty set) → EMPTY_PATTERNS` | `detectPatterns([])` | **`CLIPBOARD_EMPTY_PATTERNS`** |
| `Make Paste Control (empty types) → INVALID_REQUEST` | `makePasteControl(acceptedTypes: [])` | `CLIPBOARD_INVALID_REQUEST` |

入力の根拠:

- `"not a valid identifier!!"` — `UTType` が解決せず、逆 DNS 形式でもないため `validateGeneric` が拒否
- `"example.com"` — scheme が nil のため `validateURL` が拒否
- `.color(red: 2.0, ...)` — `validateColor` が 0...1 の範囲外を拒否

---

## 6. T-00（実機プライバシースパイク）の実施境界（高 4）

v1 は「Snapshot / Check / Detect / Load ボタンで T-00 を実施可能」と断定していた。**これは成立しない。**

企画書のテスト行列 16 ケースのうち、**ケース 12〜15 は UIKit API の各段階を個別に呼び分けて
通知・プロンプトの契機を切り分ける試験**である。現在の `IosClipboardManager.loadItem` は
`itemProviders` 取得・`canLoadObject` 判定・実ロードを 1 操作へ内包しており、
サンプル画面の `Load` ボタンでは段階を分離できない。ケース 12 の `contains(pasteboardTypes:)` は
そもそも公開 API に含まれない（設計で内部限定）。

### 対応表

| ケース | 内容 | 本サンプルで実施 |
|---|---|---|
| 1〜3 | 自アプリでコピーした内容の読み取り | 可（`Copy` → `Read`） |
| 4 | `changeCount` のみ読む | 可（`Check Foreground Change`） |
| 5 | `detectedPatterns` | 可（`Detect Patterns`） |
| 6 | `detectedValues` | 可（`Detect Values`） |
| 7 | `UIPasteControl` タップ | 可（Paste Control セクション） |
| 8 | 標準編集メニューのペースト | 可（受信 View が responder chain に入る） |
| 9 | 承認直後の再読 | 可（`Read` を連続実行） |
| 10 | background 復帰直後の `changeCount` 比較 | 可（`Check Foreground Change`） |
| 11 | Universal Clipboard 経由 | 可（2 台必要） |
| **12** | `contains(pasteboardTypes:)` のみ | **不可**（公開 API 外） |
| **13** | `itemProviders` getter のみ | **不可**（`loadItem` に内包） |
| **14** | 取得済み provider へ `canLoadObject` のみ | **不可**（同上） |
| **15** | 取得済み provider へ実ロード | **不可**（同上） |
| 16 | `UIPasteControl` → `paste(itemProviders:)` 内でロード | 可（経路全体としては観測できる） |

### 実施不能ケースの扱い

ケース 12〜15 は **T-00 専用の実験 harness** で UIKit API を直接呼び分けて観測する。
本サンプルアプリへ「切り分け用の生 UIKit 呼び出し」を持ち込むことは**しない**
（サンプルアプリはライブラリ経由のみという依存方針に反するため）。

**分離できない操作を一括実行して「privacy 契機を特定した」と判断してはならない。**
本サンプルで観測できるのは「経路全体として通知・プロンプトが出るか」までである。

---

## 7. 変更ファイル一覧

### 7.1 新規作成

| パス | 内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift` | 機能本体。`ClipboardPasteControlView` と `ClipboardSampleIdentifiers` も同ファイル内に定義 |

### 7.2 既存変更

| パス | 変更内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ContentView.swift` | `NavigationLink` + `menuCard("Clipboard Example", "Test system clipboard features")` を追加。メニューカードへ accessibility identifier を付与 |
| `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift` | **Clipboard の XCUITest を追加**（9 章） |

### 7.3 非変更

| パス | 理由 |
|---|---|
| `IosLibraryExampleApp.swift` | Clipboard は起動時セットアップ不要 |
| `DialogSampleView.swift` / `NotificationSampleView.swift` / `ShareSampleView.swift` | 影響なし |
| `IosLibraryExample.xcodeproj/project.pbxproj` | `PBXFileSystemSynchronizedRootGroup` を採用済み（**確認済み**。低 1） |
| `ios/IosLibrary/**` | ライブラリ側の変更は行わない |

---

## 8. 手動確認観点

### 8.1 準備 → 実行 → 期待結果（中 6）

| # | 準備 | 実行 | 期待結果 |
|---|---|---|---|
| 1 | — | Main Menu → Clipboard Example | 画面遷移する |
| 2 | — | `Copy Plain Text` → `Read` | `numberOfItems=1`、text あり |
| 3 | — | 9 種の Copy を順に実行し各回 `Snapshot` | `has*` と `numberOfItems` が kind に応じて変化 |
| 4 | — | `Create Named Pasteboard` → `Copy Plain Text` → `Read` | named scope で読み書きできる |
| 5 | #4 の後 | `Remove Active Pasteboard` → `Probe Last Removed Scope` | `CLIPBOARD_UNAVAILABLE` |
| 6 | アプリ再起動 | `Use Fixed Named Scope (no create)` → `Read` | `CLIPBOARD_UNAVAILABLE`（非永続性 / M-08） |
| 7 | `Copy Plain Text` | `Append Plain Text` → `Read` | `numberOfItems` が増える |
| 8 | `Copy Plain Text` | `Load Text` | 文字数が表示される |
| 9 | `Copy URL` | `Load URL` | 文字数が表示される |
| 10 | `Copy Image File` | `Load Image` | byte 数が表示される |
| 11 | `Copy Custom Data` | `Load File (public.data)` | fileSize が表示される |
| 12 | #11 の直後 | 一時ディレクトリを確認 | **返却された session directory が残っていない**（高 2） |
| 13 | `Copy Image File` | `Load Image` → 完了前に `Cancel All Loads` | `ℹ️ CLIPBOARD_CANCELLED`。完了済みなら `✅`（どちらも正常） |
| 14 | `Copy Detection Fixture` | `Detect Patterns` / `Detect Values` | 検出パターン名と各件数が表示される |
| 15 | — | `Start Observing` → `Copy Plain Text` | Events が増える |
| 16 | #15 の後 | `Stop Observing` → `Copy Plain Text` | Events が増えない |
| 17 | `Start Observing` 中 | Scope セクションのボタン | すべて無効（4.4） |
| 18 | `Start Observing` 中 | 画面を離れる | 監視が停止する |
| 19 | 他アプリでテキストをコピー | Paste Control をタップ | `pastedSummary` に `items>=1` |
| 20 | 他アプリで画像のみコピー | Paste Control をタップ | 画像として貼り付く（M-11） |
| 21 | 他アプリで対応外の型のみコピー | Paste Control をタップ | `items=0, failures=1 [...]` |
| 22 | — | Error Cases の全ボタン | ボタン名どおりの `errorCode`（5.11） |
| 23 | 一連の操作後 | Xcode コンソールを確認 | **クリップボード値・パス・URL・pasteboard 名が出ていない**（M-15） |

#### 外部アプリが必要なケース

#19 / #20 / #21 は他アプリでのコピーが前提。Safari（URL / テキスト）、写真（画像）、
ファイル（対応外の型）を使う。

### 8.2 実機必須（T-13 / M-06〜M-15）

| M-ID | 観点 | 本サンプルで実施 |
|---|---|---|
| M-06 | Universal Clipboard（`localOnly: false` → `true`） | 可（2 台必要） |
| M-07 | `expirationDate` 経過後に取得できない | 可（`Copy (expires in 30s)` → 30 秒後 `Read`） |
| M-08 | 名前付きの寿命 | 可（#6） |
| M-09 | App Group 間の読み書き | **不可**（対象外） |
| M-10 | `UIPasteControl` の表示・貼り付け | 可（#19） |
| M-11 | 画像のみのクリップボード | 可（#20） |
| M-12 | 24 時間経過分の一時ファイル cleanup | 可（時刻操作が必要） |
| M-13 | `imageData` / `image` のエンコード時間・ピークメモリ | 可（Instruments 併用。1.5 のサイズ境界もここで扱う） |
| M-14 | foreground 復帰時の二重報告なし | 可（`Check Foreground Change`） |
| M-15 | ログに機微情報が出ていない | 可（#23） |

### 8.3 T-00

6 章の対応表を参照。**ケース 12〜15 は本サンプルでは実施できない。**

---

## 9. 自動 UI テスト計画（高 3）

`implement-sample-app` workflow は「手動確認観点のうち自動化可能なものを既存 UI テストターゲットへ実装してから
実機確認へ進む」ことを必須としている。既存の `IosLibraryExampleUITests` へ追加する。

### 9.1 accessibility identifier 規約

`ClipboardSampleIdentifiers` enum に定数として定義し、View と UI テストの双方から参照する。

| 種別 | 命名 | 例 |
|---|---|---|
| メニューカード | `menu.<feature>` | `menu.clipboard` |
| 結果表示 | `clipboard.result` | — |
| 状態バー | `clipboard.status` | — |
| 貼り付け結果 | `clipboard.pasteSummary` | — |
| セクション | `clipboard.section.<name>` | `clipboard.section.copy` |
| ボタン | `clipboard.button.<action>` | `clipboard.button.copyPlainText` |

ボタンの表示名は変更しうるため、**テストは表示文字列ではなく identifier で特定する**。

### 9.2 自動化する観点

| # | 対応する手動観点 | 内容 |
|---|---|---|
| U-1 | 8.1 #1 | Main Menu → Clipboard Example の遷移と主要セクションの存在 |
| U-2 | 8.1 #2 | `Copy Plain Text` → `Read` で結果が `✅` になる |
| U-3 | 8.1 #3 | `Copy Plain Text` → `Snapshot` で `numberOfItems` が 1 以上 |
| U-4 | 8.1 #7 | `Copy` → `Append` → `Read` で件数が増える |
| U-5 | 8.1 #15/#16 | `Start Observing` → `Copy` で Events 増加、`Stop Observing` 後は増えない |
| U-6 | 8.1 #17 | 観測中に Scope セクションのボタンが無効 |
| U-7 | 8.1 #22 | 代表的 Error Cases 4 件（`EMPTY_ITEMS` / `INVALID_TYPE` / `CANNOT_REMOVE_GENERAL` / `EMPTY_PATTERNS`）が期待コードを表示 |
| U-8 | 8.1 #4/#5 | named 作成 → copy → read → remove → probe で `CLIPBOARD_UNAVAILABLE` |
| U-9 | 8.1 #18 | 画面を離れる操作（Back）でクラッシュしない |
| U-10 | — | `Clear Active Scope` 後の `Snapshot` で `numberOfItems=0` |

### 9.3 自動化しない（手動に残す）観点と理由

| 観点 | 理由 |
|---|---|
| 8.1 #6（再起動後の非永続性） | アプリ再起動をまたぐ状態確認。XCUITest の 1 セッションで完結しない |
| 8.1 #12（一時ディレクトリの残存確認） | アプリ sandbox 内のファイルシステム確認が必要。UI テストからは観測できない |
| 8.1 #13（キャンセル） | 実 pasteboard の load 完了時間に依存し、結果が非決定的 |
| 8.1 #19〜#21（Paste Control） | 他アプリでのコピーと system の paste 承認 UI に依存 |
| 8.1 #23（ログ確認） | Xcode コンソールの目視 |
| 8.2 の M-06〜M-14 | 実機・複数端末・時刻操作・Instruments が必要 |
| 6 章の T-00 | 通知・プロンプトの目視観測 |

### 9.4 テストの安定化

- 各テストの冒頭で `Clear Active Scope` を実行し、pasteboard 状態を初期化する
- 結果の判定は `clipboard.result` の `label` に対する `waitForExistence` + 部分一致
- Simulator の general pasteboard は他テストと共有されるため、**Clipboard の UI テストは直列実行**する

---

## 10. 追加判断（計画作成時のもの・設計書由来ではない）

| # | 判断 | 理由 |
|---|---|---|
| 1 | `async throws` 版のみを使う | 既存 `ShareSampleView` と一致。callback 版は Unity Bridge の経路 |
| 2 | `TextField` による自由入力を設けない | 既存 iOS サンプル 3 種に前例がなく、Android Clipboard サンプルも固定データ方式 |
| 3 | `activeScope` を状態として保持し、`lastRemovedScope` も持つ | S1 と M-08 の確認に必要 |
| 4 | **外部由来のクリップボード値は画面にもログにも出さない** | セキュリティ方針を優先。件数・byte 数・kind で確認可能と判断（中 4・本版で確定） |
| 5 | App Group（M-09）は対象外 | entitlement と 2 アプリ目が必要 |
| 6 | `ClipboardPasteControlView` / `ClipboardSampleIdentifiers` を `ClipboardSampleView.swift` 内に定義 | 他画面から再利用しないため |
| 7 | 観測中は Scope 操作を無効化する | 観測対象が消える状態を作らない。truth table は 4.4 |
| 8 | サイズ・pixel 境界はサンプル対象外 | unit test で担保済み。実機挙動は M-13 で扱う（中 5） |
| 9 | T-00 専用 harness をサンプルアプリへ混ぜない | 生 UIKit 呼び出しはサンプルの依存方針に反する（高 4） |

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
