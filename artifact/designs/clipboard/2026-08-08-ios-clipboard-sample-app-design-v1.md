# iOS Clipboard サンプルアプリ実装計画 v1

## 基本情報

- 日付: 2026-08-08
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 対象サンプルアプリ: `ios/IosLibraryExample`
- 設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 対応タスク: 設計書 T-12

---

## 1. 前提情報の抽出（設計書・実装結果由来）

### 1.1 in-scope 機能

| ID | サブ機能 |
|---|---|
| S1 | ペーストボード解決（`general` / 名前付き / ユニーク名の参照・作成・破棄） |
| S2 | コピー（9 content kind） |
| S3 | コピーオプション（`localOnly` / `expirationDate`。置換コピーのみ） |
| S4 | 追記（`append`。options なし・privacy 継承保証なし） |
| S5 | ペースト（同期）: text / urls / image / color / 任意 UTI `Data` / 全アイテムのメタ情報 |
| S6 | ペースト（`NSItemProvider` 非同期）: text / url / image / file、キャンセル、タイムアウト |
| S7 | 内容確認（`snapshot`） |
| S8 | クリア |
| S9 | 変更監視（`changedNotification` / `removedNotification` / `changeCount` 差分） |
| S10 | パターン検出（11 パターン） |
| S11 | 貼り付け UI（`UIPasteControl` + 受信 View のコンテナ。**ネイティブのみ**） |

S12（Unity Bridge）はサンプルアプリの対象外。

### 1.2 公開 API（`IosLibrary.IosClipboardManager`）

| ID | API | 形態 |
|---|---|---|
| P-1 | `copy(_:options:scope:)` | callback / `async throws` |
| P-2 | `append(_:scope:)` | callback / `async throws` |
| P-3 | `read(scope:)` | callback / `async throws` → `ClipboardReadResult` |
| P-4 | `readData(utType:scope:)` | callback / `async throws` → `Data?` |
| P-5 | `snapshot(matchingTypes:scope:)` | callback / `async throws` → `ClipboardSnapshot` |
| P-6 | `clear(scope:)` | callback / `async throws` |
| P-7 | `createPasteboard(_:)` | callback / `async throws` → `PasteboardScope` |
| P-8 | `removePasteboard(_:)` | callback / `async throws` |
| P-9 | `detectPatterns(_:scope:)` | callback / `async throws` |
| P-10 | `detectValues(_:scope:)` | callback / `async throws` |
| P-11 | `loadItem(_:scope:)` | callback / `async throws` → `ClipboardLoadedItem` |
| P-12 | `cancelAllLoads()` | 同期 |
| P-13 | `startObserving(scope:onEvent:)` | 同期 `throws` |
| P-14 | `stopObserving()` | 同期 |
| P-15 | `checkForegroundChange(scope:)` | 同期 → `Bool` |
| P-16 | `makePasteControl(acceptedTypes:displayMode:onPaste:onPartialFailure:onPasteFailure:)` | 同期 `throws` → `ClipboardPasteControlContainerView` |

`IosClipboardManager` は `@MainActor`。SwiftUI の View から直接呼べる。

### 1.3 入力制約

- `acceptedTypes` は 1 件以上必須。空配列 / 空 identifier / 不正 identifier は control 生成前に throw
- `multipleText` の空配列、`multiRepresentation` の空 object は `CLIPBOARD_EMPTY_ITEMS`
- `append` は `ClipboardCopyOptions` を受け取らない
- サイズ上限: `maxCopyByteCount` / `maxLoadByteCount` 各 64 MiB、`maxImagePixelCount` 100 MP
- タイムアウト: detection 5s / providerLoad 15s / imageCoding 10s
- 名前付き / ユニークペーストボードは**非永続**。作成アプリの実行中のみ存在する

### 1.4 エラー契約

- `ClipboardError` 24 ケース。`errorCode` は固定文字列、`errorDescription` は固定英語文
- 公開メッセージは**入力値を一切埋め込まない**
- Android と共通のコード 4 件: `CLIPBOARD_EMPTY_CONTENT` / `CLIPBOARD_EMPTY_ITEMS` / `CLIPBOARD_UNAVAILABLE` / `CLIPBOARD_UNKNOWN`
- `.cancelled`（`CLIPBOARD_CANCELLED`）は通常の結果として扱ってよい
- S11 のキャンセルは内部 completion のみで、UI コールバックへは伝播しない

### 1.5 テスト観点（設計書由来）

- 正常系: 9 content kind、3 scope kind、4 load request kind、11 検出パターン
- 異常系: 空内容 / 空アイテム / 不正 UTI / 不正 URL / 存在しないファイル / 解決不能な scope
- 境界値: サイズ上限ちょうど、空文字列（許可）、空配列（拒否）

### 1.6 不足前提（勝手に補完しない）

| 項目 | 内容 |
|---|---|
| T-00 未実施 | 実機プライバシースパイク（M-01〜M-05、M-16）が未実施。**結果次第で P-15 と `append` の仕様が変わりうる**（下記 6 章） |
| `UIColor` の UTI | `"com.apple.uikit.color"` は公式ドキュメント未確認。**要検証** |
| App Group | M-09 の App Group 間共有は entitlement 設定が前提。本計画では**扱わない**（サンプルアプリ単体で完結しないため） |

---

## 2. 既存サンプルコードの深掘り

### 2.1 確認したファイル

| パス | 役割 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ContentView.swift` | メインメニュー。`NavigationStack` + `menuCard` |
| `ios/IosLibraryExample/IosLibraryExample/ShareSampleView.swift` | 最も構成が近い参照元（321 行） |
| `ios/IosLibraryExample/IosLibraryExample/NotificationSampleView.swift` | `requirePermission` / `updateResult` の共通化パターン |
| `ios/IosLibraryExample/IosLibraryExample/DialogSampleView.swift` | 最小構成のサンプル |
| `ios/IosLibraryExample/IosLibraryExample/IosLibraryExampleApp.swift` | App 起動時セットアップ |
| `android/.../example/ClipboardSampleScreen.kt` | **相互参照ペア**（Android ⇔ iOS）。559 行 |

### 2.2 Android Clipboard サンプル（主参照）から踏襲する点

Android 版のセクション構成:

```
Copy / Copy - Sensitive / Read - Inspect / Clear / Observe / Error Cases
```

踏襲するもの:

- 機能カテゴリ単位のセクション分け
- 結果表示領域を画面上部に固定し、成功/失敗を一目で判別できる文言にする
- **プラットフォーム制約を画面内の注記テキストで示す**（Android 版は「preview suppression は Android 13+ のみ」「observation は foreground のみ」を明記）
- Error Cases を独立セクションにし、期待するエラーコードをボタン名に含める
- 画面破棄時に監視を停止する（Android は `DisposableEffect`、iOS は `onDisappear`）

踏襲しないもの:

- Android の `Toast` 通知（iOS 既存サンプルに相当パターンがない）
- Back ボタンの明示配置（iOS は `NavigationStack` が戻る導線を提供する）

### 2.3 iOS 既存サンプルの UI 規約（こちらを優先）

| 要素 | 規約 |
|---|---|
| 画面遷移 | `NavigationStack` + `NavigationLink`。`ContentView` の `menuCard` にエントリを追加 |
| 画面先頭 | `Text("<Manager> Example")` を `.title` + `.bold` |
| 結果表示 | `@State private var resultText`。灰色背景の角丸ボックス |
| セクション | `sectionView(title:content:)` の `@ViewBuilder` ヘルパー |
| ボタン | `FullWidthPressableButtonStyle`（private struct。各 View に定義） |
| 結果更新 | `updateResult(isSuccess:result:)`。`✅` / `❌` プレフィックス、`DispatchQueue.main.async` で反映 |
| ログ | `private let TAG`。`Log.d` / `Log.e` を API 呼び出し前後に出す |
| 入力 | **固定サンプルデータ + ボタン**。`TextField` による自由入力は既存サンプルに存在しない |

### 2.4 再利用 / 追加 / 変更

**再利用する既存コンポーネント**

- `ContentView.menuCard`（変更なしで流用）
- `sectionView` / `updateResult` / `FullWidthPressableButtonStyle` のパターン（`ShareSampleView` から移植）
- `Text.buttonStyle(backgroundColor:)`（`ContentView.swift` の extension）

**追加するコンポーネント**

| 名前 | 種別 | 理由 |
|---|---|---|
| `ClipboardSampleView` | `View` | 機能本体 |
| `ClipboardPasteControlView` | `UIViewRepresentable` | S11 の `ClipboardPasteControlContainerView` は `UIView`。SwiftUI へ埋め込むラッパーが必要 |

**変更するファイル**

| ファイル | 変更理由 |
|---|---|
| `ContentView.swift` | メニューへ Clipboard エントリを 1 件追加 |

---

## 3. 実装制約の確認

### 3.1 依存方向（`common.md` §サンプルアプリの依存方向）

**確認結果: 問題なし。**

`IosLibraryExample` は `IosLibrary` のみに依存し、`UnityIosPlugin` へは依存しない。

S1〜S11 のすべてが `IosLibrary` の公開 API（`IosClipboardManager` の P-1〜P-16）で到達可能であることを、
`ios/IosLibrary/IosLibrary/Clipboard/IosClipboardManager.swift` の public 宣言で確認した。
**Unity プラグイン経由でしか呼べない API は存在しない。**

S11（`UIPasteControl`）も `ClipboardPasteControlContainerView` として `IosLibrary` の Presentation 層に
公開されており、Unity Bridge 非対応（設計書「S11 はネイティブのみ」）である。

### 3.2 コーディングルール

- `agent-rules/coding-rules/common.md`: Clean Architecture、サンプルアプリの依存方向
- `agent-rules/coding-rules/ios.md`:
  - 全 `public` / `internal` / `override` 関数の先頭に `Log.d` / `Log.e`
  - **クリップボード値・パス・URL をログに出さない**（本機能特有。値ではなく長さ / 件数 / kind を出す）
- 既存サンプルの UI / 命名規約を優先し、不要な構造変更を行わない

---

## 4. 画面要件

### 4.1 導線

```
Main Menu (ContentView)
  └─ "Clipboard Example" → ClipboardSampleView
```

### 4.2 画面構成

```
[Clipboard Example]                    <- タイトル
[✅/❌ Result: ...]                     <- 結果表示（固定・上部）
[Active scope: general]                <- 現在の対象 scope（状態表示）
[Observed events: 0]                   <- 監視イベント数（状態表示）
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

| `@State` | 用途 |
|---|---|
| `resultText` | 結果表示 |
| `activeScope: PasteboardScope` | 現在の操作対象。`createPasteboard` の結果を保持し、以降の copy / read に反映する |
| `activeScopeLabel: String` | 画面表示用（**名前そのものは表示しない**。kind と名前長のみ） |
| `observedEventCount: Int` | 監視イベントの受信数 |
| `isObserving: Bool` | 監視中フラグ（ボタンの活性制御） |
| `pastedSummary: String` | S11 の貼り付け結果サマリ |

### 4.4 エラー表示

- `catch let error as ClipboardError` で捕捉し、`errorCode` と `errorDescription` を表示する
- 表示形式: `❌ \nResult: [<label>] errorCode=<code>, errorMessage=<message>`
- **`errorDescription` は固定英語文であり入力値を含まない**ため、そのまま表示してよい

### 4.5 ログ表示

- 画面内にログ領域は設けない（既存サンプルに前例がない）
- `Log.d` / `Log.e` で Xcode コンソールへ出力する
- **クリップボードの値・パス・URL・pasteboard 名は出力しない。** 件数 / 長さ / kind / errorCode のみ

---

## 5. 実装詳細

### 5.1 Scope（S1 / P-7 / P-8）

| ボタン | 動作 |
|---|---|
| `Use General` | `activeScope = .general` |
| `Create Named Pasteboard` | `createPasteboard(.named("com.jonghyunkim.nativetoolkit.example.sample"))` → 結果を `activeScope` へ |
| `Create Unique Pasteboard` | `createPasteboard(.unique)` → 結果を `activeScope` へ |
| `Remove Active Pasteboard` | `removePasteboard(activeScope)` → 成功後 `activeScope = .general` |

注記テキスト: 名前付き / ユニークペーストボードは非永続であり、アプリ終了で消滅する。

### 5.2 Copy（S2 / P-1）— 9 content kind

| ボタン | content |
|---|---|
| `Copy Plain Text` | `.plainText("Hello from IosLibraryExample")` |
| `Copy Plain Text (empty, allowed)` | `.plainText("")` |
| `Copy HTML Text` | `.htmlText(plain:html:)` |
| `Copy URL` | `.url("https://www.apple.com")` |
| `Copy Image File` | `.imageFile(path:)`（バンドルの `app-icon-attachment.png`） |
| `Copy Image Data` | `.imageData(_, utType: "public.png")`（バンドル画像を `Data` 化） |
| `Copy Color` | `.color(red:green:blue:alpha:)` |
| `Copy Custom Data` | `.customData(_, utType: "com.jonghyunkim.nativetoolkit.example.custom")` |
| `Copy Multiple Text` | `.multipleText(["first", "second", "third"])` |
| `Copy Multi Representation` | `.multiRepresentation(["public.plain-text": ..., "public.utf8-plain-text": ...])` |

すべて `activeScope` を対象にする。

### 5.3 Copy Options（S3 / P-1）

| ボタン | options |
|---|---|
| `Copy (localOnly = true)` | `ClipboardCopyOptions(localOnly: true, expirationDate: nil)` |
| `Copy (localOnly = false)` | `localOnly: false`（Universal Clipboard 転送の正の対照。M-06） |
| `Copy (expires in 30s)` | `expirationDate: Date().addingTimeInterval(30)`（M-07） |

注記テキスト: `localOnly` の既定は `true`。`expirationDate` の効果は実機での経過後確認が必要。

### 5.4 Append（S4 / P-2）

| ボタン | 動作 |
|---|---|
| `Append Plain Text` | `append(.plainText("appended item"))` |
| `Append URL` | `append(.url("https://developer.apple.com"))` |

注記テキスト: `append` は `ClipboardCopyOptions` を受け取れず、**先行 `copy` の privacy option 継承は保証されない**。機微データは常に `copy` を使う（M-16 / 要検証）。

### 5.5 Read / Inspect（S5 / S7 / P-3 / P-4 / P-5）

| ボタン | 動作 |
|---|---|
| `Read` | `read(scope:)` → `items.count` と各 item の `typeIdentifiers` 件数を表示 |
| `Read Data (public.png)` | `readData(utType: "public.png")` → byte 数のみ表示 |
| `Snapshot` | `snapshot()` → `hasStrings` / `hasURLs` / `hasImages` / `hasColors` / `numberOfItems` / `typeIdentifiers.count` |
| `Snapshot (matching public.plain-text)` | `snapshot(matchingTypes: ["public.plain-text"])` → `matchingItemIndexes` を表示 |

**値そのものは表示しない。** 件数・長さ・型識別子のみ表示する（本機能のセキュリティ方針）。

> 要検討: サンプルアプリでは動作確認のためにテキスト値を表示したい場面がある。
> **ログには出さず、画面表示に限る**という運用にするか、値も一切出さないかを実装時に確定する。

### 5.6 Load（S6 / P-11 / P-12）

| ボタン | request |
|---|---|
| `Load Text` | `.text` |
| `Load URL` | `.url` |
| `Load Image` | `.image` → 取得した PNG の byte 数を表示 |
| `Load File (public.data)` | `.file(utType: "public.data")` → 一時ファイルのサイズのみ表示 |
| `Cancel All Loads` | `cancelAllLoads()` |

注記テキスト: キャンセルは配信抑止のみで、OS 側の処理中断は保証しない。

### 5.7 Detect（S10 / P-9 / P-10）

| ボタン | 動作 |
|---|---|
| `Detect Patterns (all 11)` | `detectPatterns(Set(ClipboardDetectionPattern.allCases))` → 検出されたパターン名の一覧 |
| `Detect Values (all 11)` | `detectValues(...)` → 各配列の件数を表示 |
| `Copy Sample For Detection` | 検出対象を含むテキストをコピーするショートカット（URL / メール / 電話番号 / 金額を含む文字列） |

### 5.8 Observe（S9 / P-13 / P-14 / P-15）

| ボタン | 動作 |
|---|---|
| `Start Observing` | `try startObserving(scope: activeScope) { event in ... }`。`observedEventCount += 1` |
| `Stop Observing` | `stopObserving()` |
| `Check Foreground Change` | `checkForegroundChange(scope:)` → `Bool` を表示 |

- イベント表示は `kind`（`changed` / `changedDetectedOnForeground` / `removed`）と `typesAdded.count` / `typesRemoved.count`
- `startObserving` は `throws`。解決できない scope では `CLIPBOARD_PASTEBOARD_UNAVAILABLE`
- `onDisappear` で `stopObserving()` を呼ぶ

注記テキスト: 通知は**アプリが foreground の間のみ**届く。background 中の変更は `checkForegroundChange` で差分検知する（M-14）。

### 5.9 Paste Control（S11 / P-16）

`ClipboardPasteControlContainerView` は `UIView` なので `UIViewRepresentable` でラップする。

```swift
struct ClipboardPasteControlView: UIViewRepresentable {
    let acceptedTypes: [String]
    let onPaste: ([ClipboardLoadedItem]) -> Void
    let onPartialFailure: ([ClipboardError]) -> Void
    let onPasteFailure: (ClipboardError) -> Void
    // makeUIView で IosClipboardManager.shared.makePasteControl(...) を呼び、
    // 生成した container をそのまま返す（container が control と receiver を強保持する）
}
```

- `acceptedTypes` は `["public.plain-text", "public.url", "public.image"]`
- 生成に失敗した場合（`invalidRequest` / `invalidTypeIdentifier`）は空の `UIView` を返し、結果領域へエラーを表示する
- コールバックは 3 種すべてを結果領域へ反映する（`onPaste` / `onPartialFailure` / `onPasteFailure`）

注記テキスト: `UIPasteControl` はユーザーが明示的にタップした場合のみ動作し、許可プロンプトを出さない（M-10 / M-11）。

### 5.10 Clear（S8 / P-6）

| ボタン | 動作 |
|---|---|
| `Clear Active Scope` | `clear(scope: activeScope)` |

### 5.11 Error Cases

| ボタン | 期待するエラー |
|---|---|
| `Copy Multiple (empty list) → EMPTY_ITEMS` | `CLIPBOARD_EMPTY_ITEMS` |
| `Copy Multi Representation (empty) → EMPTY_ITEMS` | `CLIPBOARD_EMPTY_ITEMS` |
| `Copy Image File (missing) → IMAGE_LOAD_FAILED` | `CLIPBOARD_IMAGE_LOAD_FAILED` |
| `Copy Custom Data (invalid UTI) → INVALID_TYPE_IDENTIFIER` | `CLIPBOARD_INVALID_TYPE_IDENTIFIER` |
| `Copy URL (invalid) → INVALID_URL` | `CLIPBOARD_INVALID_URL` |
| `Read Data (invalid UTI) → INVALID_TYPE_IDENTIFIER` | `CLIPBOARD_INVALID_TYPE_IDENTIFIER` |
| `Remove General → INVALID_REQUEST` | `general` は破棄不可 |
| `Start Observing (unresolvable named) → PASTEBOARD_UNAVAILABLE` | `CLIPBOARD_PASTEBOARD_UNAVAILABLE` |
| `Detect Patterns (empty set) → INVALID_REQUEST` | 空 Set は拒否 |
| `Make Paste Control (empty acceptedTypes) → INVALID_REQUEST` | 空配列は control 生成前に throw |

各ボタン名に**期待するエラーコードを含める**（Android 版の踏襲）。

### 5.12 API 呼び出し方針

- **`async throws` 版を使う。** `IosClipboardManager` は `@MainActor` なので、SwiftUI の `Task { }` から直接 `await` できる
- callback 版は使わない（既存 `ShareSampleView` も `async throws` 版を使用）
- 同期 API（P-12 / P-13 / P-14 / P-15 / P-16）はそのまま呼ぶ
- 共通ヘルパー `run(label:operation:)` を設け、`do / catch` と `updateResult` の重複を排除する

```swift
private func run(label: String, operation: @escaping () async throws -> String) async {
    Log.d(TAG, "[run] label: \(label)")
    do {
        let detail = try await operation()
        updateResult(isSuccess: true, result: "[\(label)] \(detail)")
    } catch let error as ClipboardError {
        Log.e(TAG, "[run][error] label: \(label), errorCode: \(error.errorCode)")
        updateResult(isSuccess: false, result: "[\(label)] errorCode=\(error.errorCode), errorMessage=\(error.errorDescription ?? "nil")")
    } catch {
        updateResult(isSuccess: false, result: "[\(label)] unexpected error")
    }
}
```

### 5.13 入力バリデーション方針

- サンプルアプリ側でのバリデーションは**行わない**
- 不正値はライブラリへそのまま渡し、**ライブラリのエラー契約を画面で確認する**のが目的
- Error Cases セクションはこの方針の実演を兼ねる

---

## 6. T-00 未実施による変更リスク（実装前に認識すべき点）

T-00（実機プライバシースパイク）が未実施のため、次の 2 箇所は**結果次第で仕様変更が入りうる**。

| 箇所 | リスク | 影響範囲 |
|---|---|---|
| 5.8 `Check Foreground Change` | `changeCount` が許可プロンプトの契機だった場合、設計 D-3 が覆り P-15 が縮退または廃止される | Observe セクションのボタン 1 個と注記 |
| 5.4 Append | `append` が privacy option を継承しない場合、R-13 の `appendPreservingOptions` 追加が検討される | Append セクションに API が 1 個増える可能性 |

**影響は限定的で、着手を止める理由にはならない。** むしろサンプルアプリは T-00 / T-13 を実機で回すための手段になる。
実装時は上記 2 箇所を「T-00 の結果で変わりうる」とコメントで明示しておく。

---

## 7. 変更ファイル一覧

### 7.1 新規作成

| パス | 内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift` | 機能本体。`ClipboardPasteControlView`（`UIViewRepresentable`）も同ファイル内に private で定義 |

### 7.2 既存変更

| パス | 変更内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ContentView.swift` | `NavigationLink` + `menuCard("Clipboard Example", "Test system clipboard features")` を 1 件追加 |

### 7.3 非変更

| パス | 理由 |
|---|---|
| `IosLibraryExampleApp.swift` | Clipboard は起動時セットアップ不要（Notification と異なり `setup()` に相当する API がない） |
| `DialogSampleView.swift` / `NotificationSampleView.swift` / `ShareSampleView.swift` | 影響なし |
| `IosLibraryExample.xcodeproj/project.pbxproj` | `PBXFileSystemSynchronizedRootGroup` のためファイル追加で編集不要（**要検証**: 対象プロジェクトが同方式か実装時に確認する） |
| `ios/IosLibrary/**` | ライブラリ側の変更は行わない |

---

## 8. 手動確認観点

### 8.1 サンプルアプリ単体（Simulator で確認可能）

| # | 観点 |
|---|---|
| 1 | Main Menu から Clipboard Example へ遷移できる |
| 2 | 9 content kind すべてがコピーでき、`Read` / `Snapshot` に反映される |
| 3 | 名前付き / ユニークペーストボードを作成し、そこへ copy / read できる |
| 4 | `Remove Active Pasteboard` 後に同 scope を解決できない |
| 5 | `append` でアイテムが増える |
| 6 | 4 種の `loadItem` が成功し、`Cancel All Loads` でキャンセルされる |
| 7 | 11 パターンの検出が動作する |
| 8 | 監視開始後に自アプリで copy するとイベント数が増える |
| 9 | `Stop Observing` 後はイベント数が増えない |
| 10 | 画面を離れると監視が停止する |
| 11 | `UIPasteControl` をタップして貼り付けでき、3 種のコールバックが期待どおり呼ばれる |
| 12 | Error Cases の各ボタンがボタン名どおりの `errorCode` を表示する |
| 13 | 結果表示が `✅` / `❌` で判別できる |
| 14 | **Xcode コンソールにクリップボード値・パス・URL・pasteboard 名が出力されていない**（M-15） |

### 8.2 実機必須（T-13 / M-06〜M-15）

| M-ID | 観点 | 本サンプルアプリで実施可能か |
|---|---|---|
| M-06 | Universal Clipboard（`localOnly: false` 転送 → `true` 非転送） | 可（2 台必要） |
| M-07 | `expirationDate` 経過後に取得できない | 可 |
| M-08 | 名前付きの寿命（送信側終了後 / background 中） | 可 |
| M-09 | App Group 間の読み書き | **不可**（entitlement 設定が別途必要。本計画の対象外） |
| M-10 | `UIPasteControl` の表示・貼り付け、`acceptedTypes` 未設定時の挙動 | 可 |
| M-11 | 画像のみのクリップボードでも動作する | 可 |
| M-12 | 強制終了後の再起動で 24 時間経過分が cleanup される | 可（時刻操作が必要） |
| M-13 | `imageData` / `image` のエンコード時間・ピークメモリ比較 | 可（Instruments 併用） |
| M-14 | foreground 復帰時に二重報告されない | 可 |
| M-15 | ログに機微情報が出ていない | 可 |

### 8.3 T-00（実機プライバシースパイク・M-01〜M-05 / M-16）

本サンプルアプリで実施可能。`Snapshot` / `Check Foreground Change` / `Detect Values` / `Load` の各ボタンが、
許可プロンプトやアクセス通知の契機になるかを iOS 18 / iOS 26 で観測する。

---

## 9. 追加判断（計画作成時のもの・設計書由来ではない）

| # | 判断 | 理由 |
|---|---|---|
| 1 | `async throws` 版のみを使う | 既存 `ShareSampleView` と一致。callback 版は Unity Bridge が使う経路であり、ネイティブサンプルでは冗長 |
| 2 | `TextField` による自由入力を設けない | 既存 iOS サンプル 3 種に前例がなく、Android Clipboard サンプルも固定データ方式 |
| 3 | `activeScope` を状態として保持する | `createPasteboard` の結果を後続操作で使えないと S1 の確認が成立しない |
| 4 | 画面に値そのものを表示するかは実装時に確定（5.5 の要検討） | セキュリティ方針とサンプルアプリの確認容易性が競合するため |
| 5 | App Group（M-09）は対象外 | entitlement と 2 アプリ目が必要で、サンプルアプリ単体で完結しない |
| 6 | `ClipboardPasteControlView` を `ClipboardSampleView.swift` 内に private で定義 | 他画面から再利用しないため。ファイル数を増やさない |

---

## 10. ステップ8 実行確認

- 提示文:
  - 「この実装計画で進めますか？」
- 選択肢:
  - 承認する: 計画を確定、次のレビュー workflow（review-document）へ進む
  - 修正する: 指摘内容を反映して計画ファイルを更新
  - キャンセル: 計画ファイルは保持したまま終了
- ユーザー回答:
  - 未回答
