# macOS Clipboard サンプルアプリ実装計画 v1

## 基本情報

- 日付: 2026-08-30
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/MacLibraryExample/`
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v7.md`
- 実装結果: `artifact/results/clipboard/2026-08-30-macos-clipboard-implementation-feature-result-v8.md`
- 対応タスク: T-18
- 主参照ペア: Windows（`windows/WindowsLibraryExample/`）

> T-18 の完了条件（設計書 §17）:
> 「全公開 OP が `MacLibraryExample` から Unity 非依存で実行できること」
> 「MT-05 用の最小 drag harness を含むこと」

---

## 1. 前提情報の抽出（設計書・実装結果より）

### 1.1 in-scope 機能

公開 OP は **20 件**（OP-01〜OP-20）。すべて `MacClipboardManager`（`MacLibrary`）の public API。

| 分類 | OP |
|---|---|
| 書き込み | OP-01 copy / OP-02 append |
| 読み出し | OP-03 read / OP-04 readData / OP-05 snapshot |
| 消去 | OP-06 clear |
| pasteboard 管理 | OP-07 createPasteboard / OP-08 removePasteboard |
| 検出 | OP-09 detectPatterns / OP-10 detectValues / OP-11 detectMetadata |
| 環境 | OP-12 accessBehavior |
| 監視 | OP-13 startObserving / OP-14 stopObserving / OP-15 checkForegroundChange |
| File Promise 提供 | OP-16 provideFilePromise / OP-17 releaseFilePromise |
| File Promise 受領 | OP-18 receiveFilePromises（callback / stream / async の 3 形態） / OP-20 cancelReceiveFilePromises |
| UI 部品 | OP-19 makePasteButton |

### 1.2 公開 API と入力制約

- **実行方式**: OP-01〜OP-11 と OP-16 は `async throws`。OP-12〜OP-15 / OP-17 / OP-19 / OP-20 は同期
- **`@discardableResult` なし**: OP-16 と callback 版 OP-18。戻り値の handle を捨てると登録と staging、または receipt session が解放不能になる。**サンプルは必ず handle を保持する**
- **scope**: `.general` / `.named(String)` / `.unique(String)`
- **content**: `ClipboardContent(items: [ClipboardItemData(representations: [UTI: Data])])`。UTI と生バイトの辞書であり、`.text` のような便宜 case は**ない**
- **copy options**: `ClipboardCopyOptions(localOnly: Bool)`。既定は `localOnly: true`
- **append**: 自所有時のみ成功。他者所有なら `ownershipLost`（1511）
- **removePasteboard**: `.general` と標準名 5 種（`general` / `font` / `ruler` / `find` / `drag`）は `cannotReleaseStandardPasteboard`（1508）
- **file promise**: `fileTypeIdentifier` は `public.data` または `public.directory` 準拠。`fileName` は空・パス区切り・`.`・`..` を禁止
- **detect**: macOS 15.4 未満は `detectionUnavailable`（1513）。平文テキストへの `detectMetadata` は失敗する（型契約どおり）

### 1.3 エラー契約

`ClipboardError` は public な `errorCode: Int` と `errorMessage: String` を持つ。サンプルは既存 3 画面と同じく `errorCode` / `errorMessage` の両方を表示する。

主な範囲: 1501〜1524（ドメイン）、1599（unknown）。1301 / 1302 は Bridge 専用のためサンプルからは到達しない。

### 1.4 テスト観点（設計書 §15 の手動確認）

MT-01〜MT-09。うち MT-05（Finder へのドラッグ）は**サンプル側の drag harness が前提**。MT-08 は実機 Mac + iPhone、MT-09 は RK-22 により判定保留。

### 1.5 不足前提

- **MT-09（プライバシーアラート）の判定基準**は設計書で保留。サンプルでは観察のみとし、成否判定はしない
- **`localOnly` の実効性**（MT-08）は未検証。`ClipboardCopyOptions` の DocC 自身が "has not been verified on real hardware yet" と述べている。サンプルは切り替え UI を提供するに留める

---

## 2. 既存サンプルコードの深掘り

### 2.1 主参照ペア（Windows）の状況

`windows/WindowsLibraryExample/` に存在するページは `MainMenuPage` / `DialogPage` / `NotificationPage` の 3 つで、**Clipboard 画面はまだない**。

したがって主参照ペアからは「メインメニューのカード -> 機能別ページ -> 先頭に結果表示 -> カテゴリ別ボタン群」という**構造**のみを引き継ぎ、具体的な UI 規約・命名は workflow ステップ 4 の規定どおり**対象OS自身の既存サンプルを優先**する。

### 2.2 macOS サンプルの既存規約（`mac/MacLibraryExample/MacLibraryExample/`）

| ファイル | 行数 | 役割 |
|---|---|---|
| `ContentView.swift` | 89 | `NavigationStack` + `menuCard` のメインメニュー |
| `DialogSampleView.swift` | 199 | 機能画面 |
| `NotificationSampleView.swift` | 426 | 機能画面 |
| `ShareSampleView.swift` | 404 | 機能画面。最も新しく、規約の基準として扱う |
| `MacLibraryExampleApp.swift` | 32 | 起動セットアップ |

`ShareSampleView` から読み取れる規約:

- `private let TAG = "XxxSampleView"` を持ち、`Log.d` / `Log.e` で入出力を残す
- `@State private var resultText = "Result will be displayed here"`
- 画面先頭は「タイトル -> 結果表示ボックス -> `ScrollView`」の順
- 操作は `sectionView(title:)` で機能カテゴリ別にグルーピング
- ボタンは `FullWidthPressableButtonStyle`（`private struct`、ファイル末尾に定義）
- 結果表示は `updateResult(isSuccess:result:)` に一本化。成功は `✅`、失敗は `❌` を先頭に付け、`DispatchQueue.main.async` で反映
- エラーは `catch let error as XxxError` で `errorCode=` / `errorMessage=` を並記し、その他は `localizedDescription`
- 実行処理は `runXxx(label:...) async` の形に切り出し、ボタン側は `Task { await runXxx(...) }` のみ

### 2.3 iOS Clipboard サンプルとの突き合わせ（参考）

`ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift`（1,070 行）は同じ機能の先行実装であり、**セクション構成の網羅性チェックに使う**（主参照ではない）。

そのセクション: Scope / Copy / Copy Options / Append / Read・Inspect / Load (async) / Detect / Observe / Paste Control (UI) / Clear / Error Cases。

macOS で**追加が必要**なもの（iOS に存在しない）:

- **File Promise（提供）**: OP-16 / OP-17 と drag harness
- **File Promise（受領）**: OP-18 の 3 形態と OP-20
- **accessBehavior**: OP-12
- **checkForegroundChange**: OP-15（iOS は別機構）
- **named / unique pasteboard の作成・削除**: OP-07 / OP-08（iOS の scope 概念と異なる）

iOS 側の `// MARK: - Formatting helpers (no clipboard values, paths, URLs or pasteboard names)` は**秘匿方針**を表す。macOS では `ClipboardLog`（public）をそのまま使えるため、独自ヘルパーを再実装せず**ライブラリ側の秘匿ヘルパーを流用する**。これは iOS 版からの改善点。

### 2.4 深掘り結論

**再利用する既存コンポーネント**

- `ContentView.menuCard`（メニューカード）
- `ShareSampleView` の `sectionView(title:)` / `updateResult(isSuccess:result:)` / `FullWidthPressableButtonStyle` の各パターン（コピーではなく同型で新設。既存 3 画面もファイル内に private 定義を持つ規約のため）
- `MacLibrary.ClipboardLog`（`text` / `data` / `url` / `path` / `scope` / `content` / `types`）

**追加するコンポーネント**

- `ClipboardSampleView`（本体）
- `PasteButtonHost`: `NSViewRepresentable`。OP-19 が返す `NSView` を SwiftUI に載せる
- `FilePromiseDragHost`: `NSViewRepresentable`。MT-05 用の最小 drag harness（詳細は §5）
- `ClipboardSampleFixtures`: サンプル用の `ClipboardContent` / 一時ファイル生成（`ShareSampleView` の `prepareSampleXxx` 群に相当）

**変更するファイルと理由**

- `ContentView.swift`: Clipboard 画面へのメニューカードを 1 枚追加

---

## 3. 画面要件

### 3.1 機能一覧（セクション構成）

| # | セクション | 対象 OP |
|---|---|---|
| 1 | Scope | OP-07 / OP-08 |
| 2 | Copy | OP-01 |
| 3 | Copy Options | OP-01（`localOnly` 切り替え） |
| 4 | Append | OP-02 |
| 5 | Read / Inspect | OP-03 / OP-04 / OP-05 / OP-12 |
| 6 | Detect | OP-09 / OP-10 / OP-11 |
| 7 | Observe | OP-13 / OP-14 / OP-15 |
| 8 | File Promise - Provide | OP-16 / OP-17 + drag harness |
| 9 | File Promise - Receive | OP-18（3 形態） / OP-20 |
| 10 | Paste Control | OP-19 |
| 11 | Clear | OP-06 |
| 12 | Error Cases | 代表エラーの再現 |

20 OP すべてがいずれかのセクションに現れる。この対応表が T-18 完了条件の第 1 項（全公開 OP を Unity 非依存で実行できる）の検査対象になる。

### 3.2 操作導線

`Main Menu -> Clipboard Example` の 1 階層のみ。既存 3 画面と同じ。

画面上部に、以降のすべての操作へ影響する状態を置く。

- **Active scope**: `general` / `named("nt-sample")` / `unique(...)` のいずれか。`Picker` で選択
- **Result**: `updateResult` が更新する 1 行表示

各操作は「押す -> 実行 -> Result 更新」で完結する。入力欄は最小限に留め、値はフィクスチャから供給する（既存 3 画面と同じ方針）。

### 3.3 エラー表示

`ShareSampleView` と同一形式。

```
[<label>] errorCode=<Int>, errorMessage=<String>
```

`ClipboardError` 以外は `[<label>] error=<localizedDescription>`。

### 3.4 ログ表示

- 画面には**クリップボードの値そのものを出さない**。要素数・バイト数・UTI 名までとする
- `Log.d` / `Log.e` に渡す値も `ClipboardLog` を通す
- pasteboard 名、ファイルパス、URL は `ClipboardLog.scope` / `.path` / `.url` を経由する

この方針は設計書のログ秘匿契約（BT-25 が production 側を機械監査している範囲）をサンプルへ延長したもので、サンプル側に自動監査は置かない（手動確認 MS-08 で見る）。

---

## 4. 変更ファイル一覧

### 4.1 新規作成

| パス | 内容 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift` | 本体。12 セクションと操作関数 |
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleSupport.swift` | `PasteButtonHost` / `FilePromiseDragHost` / `ClipboardSampleFixtures` |

分割理由: `NSViewRepresentable` 2 種とフィクスチャ生成を本体に入れると、`ShareSampleView`（404 行）の 2 倍以上になり、既存画面の可読性水準から外れる。

### 4.2 既存変更

| パス | 変更理由 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ContentView.swift` | Clipboard Example のメニューカードを追加 |
| `mac/MacLibraryExample/MacLibraryExample.xcodeproj/project.pbxproj` | 新規 2 ファイルの登録（Xcode が自動採番） |

### 4.3 非変更

- `MacLibraryExampleApp.swift`: Clipboard は起動時セットアップを必要としない（通知と異なり、権限要求も action handler 登録もない）
- `DialogSampleView.swift` / `NotificationSampleView.swift` / `ShareSampleView.swift`
- `MacLibraryExample.entitlements`: §5.3 の判断により**現状のまま**。変更が必要と判明した場合は要検証項目として再提起する
- `MacLibrary` / `UnityMacPlugin` の一切: サンプル対応のためにライブラリを変更しない

---

## 5. 実装方針

### 5.1 共通実装パターン: 維持するもの

- メインメニュー -> サンプル画面の導線（`NavigationStack` + `menuCard`）
- 画面先頭のタイトルと結果表示領域
- `sectionView` による機能カテゴリ別グルーピング
- `updateResult` による `✅` / `❌` の一目判定
- コールバック結果の UI 反映をメインスレッドで行う
- 公開 API 呼び出し前後のログ

### 5.2 共通実装パターン: 拡張するもの

| 拡張 | 理由 |
|---|---|
| 画面上部に **Active scope の Picker** を追加 | 既存 3 画面は状態を持たない。Clipboard は同じ操作を scope 別に試す必要があり、ボタンを 3 倍に増やすより状態で切り替えるほうが画面が保つ |
| **Observe の実行中表示** | OP-13 は開始/停止のある唯一の操作。停止し忘れを画面で分かるようにする |
| **保持中 handle の表示** | OP-16 / OP-18 は handle を捨てると解放不能になる（`@discardableResult` を外した理由そのもの）。保持件数を出して、解放漏れを目視できるようにする |
| `NSViewRepresentable` の導入 | OP-19 が `NSView` を返すため。既存 3 画面には AppKit 埋め込みがない |

### 5.3 サンドボックス下の書き込み先（要検証）

`MacLibraryExample.entitlements` は `app-sandbox` + `files.user-selected.read-write` + `files.downloads.read-only`。

- **Downloads は読み取り専用**のため、OP-18 の受領先には**使えない**
- 既定の受領先を **アプリコンテナ内**（`Application Support/ClipboardReceive/`）とする。サンドボックス下でも無条件に書ける
- 併せて「Choose destination...」（`NSOpenPanel`）を用意し、`user-selected.read-write` 経由の任意ディレクトリも試せるようにする
- **要検証**: `NSOpenPanel` で選んだディレクトリへ、`NSFilePromiseReceiver` がサンドボックス越しに書けるか。書けない場合はコンテナ内固定に落とし、その事実を実装結果へ記録する

### 5.4 依存方向の確認（workflow ステップ 6）

**確認結果: 問題なし。**

OP-01〜OP-20 の 20 件すべてが `MacClipboardManager`（`mac/MacLibrary/`）の public API として実在することを確認した。Unity プラグイン経由でしか呼べない API は**ない**。

- 検査方法: `MacClipboardManager.swift` の `public func` 一覧と §1.1 の OP 表を突き合わせた
- サンプルの import は `MacLibrary` のみ。`UnityMacPlugin` を参照しない
- `ClipboardLog` も `MacLibrary` の public API であり、秘匿ヘルパーのためにプラグインへ依存する必要はない

---

## 6. 実装詳細

### 6.1 セクション別の UI 要素と呼び出し方針

以下、`await run(label:)` は「`Task` で包み、`ClipboardError` を `errorCode` / `errorMessage` に、その他を `localizedDescription` に落として `updateResult` する」共通ラッパーを指す。

#### 1. Scope

| UI | 呼び出し |
|---|---|
| Picker: `general` / `named` / `unique` | 状態のみ（API 呼び出しなし） |
| Button `CreateNamedPasteboard` | OP-07 `createPasteboard(.named("nt-sample"))` -> 返る scope を Active scope に設定 |
| Button `CreateUniquePasteboard` | OP-07 `createPasteboard(.unique)` -> 同上 |
| Button `RemoveCurrentPasteboard` | OP-08 `removePasteboard(activeScope)` -> 成功時は Active scope を `general` に戻す |
| Button `RemoveGeneral (expect error)` | OP-08 `removePasteboard(.general)` -> 1508 を期待 |

#### 2. Copy

| UI | 呼び出し |
|---|---|
| `CopyText` | OP-01。`public.utf8-plain-text` の 1 item |
| `CopyURL` | OP-01。`public.url` |
| `CopyImage` | OP-01。`public.png`。フィクスチャで生成 |
| `CopyMultipleItems` | OP-01。2 item |
| `CopyMultipleRepresentations` | OP-01。1 item に plain text と RTF の 2 representation |
| `CopyEmpty (expect error)` | OP-01。`items: []` -> 1501 を期待 |

`ClipboardContent` は UTI と `Data` の辞書であり便宜 case を持たないため、フィクスチャ側に `text(_:)` / `url(_:)` / `png()` の生成関数を用意して呼び出し側を短く保つ。

#### 3. Copy Options

| UI | 呼び出し |
|---|---|
| Toggle `localOnly` | 状態。既定 `true`（ライブラリ既定と一致） |
| `CopyWithCurrentOptions` | OP-01 に `ClipboardCopyOptions(localOnly:)` を渡す |

MT-08 の観察に使う。効果自体は未検証（§1.5）。

#### 4. Append

| UI | 呼び出し |
|---|---|
| `CopyThenAppend` | OP-01 -> 返る `PasteboardOwnership` を保持 -> OP-02 |
| `AppendWithStaleOwnership (expect error)` | OP-01 -> 別内容で OP-01 -> 最初の ownership で OP-02 -> 1511 を期待 |

#### 5. Read / Inspect

| UI | 呼び出し |
|---|---|
| `Read` | OP-03。item 数、item ごとの UTI 一覧と合計バイト数を表示 |
| `ReadDataPlainText` | OP-04 `readData(utType: "public.utf8-plain-text")`。バイト数のみ表示。該当なしは成功かつ `nil` |
| `Snapshot` | OP-05 `snapshot(matchingTypes: nil)` |
| `SnapshotFiltered` | OP-05 `matchingTypes: ["public.utf8-plain-text"]` |
| `SnapshotEmptyFilter (expect error)` | OP-05 `matchingTypes: []` -> 1512 を期待 |
| `AccessBehavior` | OP-12。同期。戻り値をそのまま表示 |

#### 6. Detect

| UI | 呼び出し |
|---|---|
| `DetectPatterns` | OP-09。検出されたパターン名の集合 |
| `DetectValues` | OP-10。**値は出さず件数のみ** |
| `DetectMetadata` | OP-11。平文テキストでは失敗する契約（1515）を確認できる |
| `DetectEmptyPatterns (expect error)` | OP-09 に空集合 -> 1503 を期待 |

macOS 15.4 未満では 1513。MT-07 の確認点。

#### 7. Observe

| UI | 呼び出し |
|---|---|
| `StartObserving` | OP-13。既定間隔（`defaultObservationInterval` = 0.5 秒）。`onEvent` で `updateResult` |
| `StartObservingInvalidInterval (expect error)` | OP-13 に `interval: 0` -> 1523 を期待 |
| `StopObserving` | OP-14。同期 |
| `CheckForegroundChange` | OP-15。同期。`Bool` を表示 |

監視中は画面にその旨を出す（§5.2）。`onEvent` は MainActor で来るため、`updateResult` をそのまま呼べる。

#### 8. File Promise - Provide

| UI | 呼び出し |
|---|---|
| `ProvideFilePromise` | OP-16。`fileTypeIdentifier: "public.plain-text"`、`fileName: "promised.txt"`。**返る handle を保持** |
| `ProvideFilePromiseInvalidType (expect error)` | OP-16 に `public.url` 以外の非 `public.data` 型 -> 1516 を期待 |
| `ProvideFilePromiseInvalidName (expect error)` | OP-16 に `fileName: "../escape.txt"` -> 1517 を期待 |
| `ReleaseFilePromise` | OP-17。同期・冪等。保持 handle を解放 |
| drag harness（下記） | MT-05 |

#### 9. File Promise - Receive

| UI | 呼び出し |
|---|---|
| `ReceiveCallback` | OP-18 callback 版。**handle を保持**。イベントごとに件数を更新 |
| `ReceiveStream` | OP-18 stream 版（`receiveFilePromiseEvents`）。`for await` で消費 |
| `ReceiveAsync` | OP-18 async 版。集約 `FilePromiseReceipt` を表示 |
| `CancelReceive` | OP-20。同期・冪等。未知 handle も no-op 成功 |
| `ReceiveToUnwritableDir (expect error)` | 存在しないパス -> 1520 を期待 |
| `Choose destination...` | `NSOpenPanel`（§5.3） |

終端は**ヒューリスティック**（静穏 or 全体タイムアウト）であることを画面の注記に出す。設計書が「保証しない」と明記している性質で、サンプルが誤解を与えないようにする。

#### 10. Paste Control

`PasteButtonHost`（`NSViewRepresentable`）が OP-19 の `NSView` を保持する。

- `acceptedTypes: ["public.utf8-plain-text", "public.png"]`
- `timeout: 5`
- `onPaste` で件数と部分失敗の有無を `updateResult`
- `MakePasteButtonInvalidType (expect error)`: 不正 UTI -> 1504 を期待

**設計書の注記どおり、この Button は自身の有効性を検証しない**（accepted type が無くても押せる）。画面にその旨を書く。

#### 11. Clear

| UI | 呼び出し |
|---|---|
| `Clear` | OP-06。消した item 数を表示 |

#### 12. Error Cases

上記各セクションの `(expect error)` ボタンを再掲せず、**このセクションには「代表エラーの一覧表示」だけ**を置く。到達したエラーコードを記録し、どの契約を確認済みかを見えるようにする。

### 6.2 MT-05 用 drag harness（要検証・最重要）

**目的**: OP-16 で提供した File Promise を Finder へドラッグし、実ファイルが生成されることを確認する。

**現状の制約**:

- OP-16 は `pasteboard.writeObjects([provider])` により、指定 scope の pasteboard へ promise を書く
- Finder へのドラッグは `NSView.beginDraggingSession(with:event:source:)` を必要とし、これは**ドラッグ用 pasteboard へ item を書き直す**
- ライブラリが保持する `NSFilePromiseProvider` 実体はサンプルから参照できない（coordinator が単独所有。H-5）
- D&D の UI 実装は調査段階から明示的に対象外（`research-v3.md`）であり、**この経路は未調査**

**方針**: `FilePromiseDragHost`（`NSViewRepresentable`）で次を試し、成立した経路を採用する。

1. OP-16 を `scope: .named(NSPasteboard.Name.drag.rawValue)` で呼び、`mouseDown` で `beginDraggingSession` を開始する
   - 懸念: セッション開始時にドラッグ pasteboard が書き直され、promise が失われる可能性
2. 1 が成立しない場合、`NSDraggingItem` の生成に必要なオブジェクトを公開する API が**ライブラリ側に不足している**と判断する

**2 に至った場合はサンプル側で回避しない。** `NSFilePromiseProvider` をサンプルで直接生成すればドラッグは成立するが、それは「サンプルはライブラリ経由でのみ機能を使う」という前提を壊し、MT-05 が検証したい対象（ライブラリの promise 実装）を検証しないものに変える。

その場合の扱い:

- 機能設計側の不足として報告し、設計書へ OP 追加（例: promise を `NSDraggingItem` として取り出す API）を提案する
- T-18 は「drag harness を含むこと」を完了条件に持つため、**この検証が終わるまで T-18 は完了にできない**
- MT-05 は未実施として残す

この項目は本計画で唯一、実装前に結論の出ていない箇所である。実装は §6.1 の 12 セクションから着手し、drag harness は最後に回す。

### 6.3 入力バリデーション方針

- サンプル側で事前検証を**行わない**。不正値はそのままライブラリへ渡し、返るエラーコードを表示する
- 理由: 各 `(expect error)` ボタンの目的が、まさにライブラリの検証契約の確認であるため。サンプルが先回りして弾くと契約が見えなくなる
- 例外は `NSOpenPanel` の選択結果のみ（キャンセル時は API を呼ばずに終了）

### 6.4 handle 管理

- `@State private var promiseHandles: [FilePromiseHandle]`
- `@State private var receiptHandles: [FilePromiseReceiptHandle]`
- 画面に保持件数を表示する
- 画面破棄時（`onDisappear`）に OP-17 と OP-20 で全解放する。どちらも冪等・非 throwing

---

## 7. 手動確認観点

### 7.1 設計書 MT の対応

| MT | サンプル上の確認手順 | 状態 |
|---|---|---|
| MT-01 | 他アプリでコピー -> `Read` | 実施可 |
| MT-02 | `CopyText` -> 他アプリで貼り付け | 実施可 |
| MT-03 | `CopyThenAppend` と `AppendWithStaleOwnership` | 実施可 |
| MT-04 | `StartObserving` -> 他アプリでコピー -> 非アクティブ化 -> 復帰 | 実施可 |
| MT-05 | drag harness -> Finder へドラッグ | **§6.2 の検証待ち** |
| MT-06 | Paste Control の Button から貼り付け。部分失敗表示 | 実施可 |
| MT-07 | 15.4.1 と 15.2 の両方で `Detect` 各種 | 実施可（2 環境必要） |
| MT-08 | `localOnly` Toggle を切り替えて実機 Mac + iPhone で確認 | 実施可（実機 2 台必要） |
| MT-09 | 各操作時のプライバシーアラート | 観察のみ。判定保留（RK-22） |

### 7.2 サンプル固有の確認観点

| ID | 観点 |
|---|---|
| MS-01 | 12 セクションすべてのボタンが押下可能で、Result が必ず更新される |
| MS-02 | `(expect error)` ボタンが設計書どおりの errorCode を返す |
| MS-03 | Active scope の切り替えが以降のすべての操作へ反映される |
| MS-04 | `named` / `unique` pasteboard を作成 -> 操作 -> 削除まで通る |
| MS-05 | Observe を開始したまま画面を離れても停止する（`onDisappear`） |
| MS-06 | promise / receipt handle の保持件数が 0 に戻る |
| MS-07 | OP-18 の 3 形態が同じ受領結果を返す |
| MS-08 | 画面表示とログのどちらにも、クリップボードの値・パス・URL・pasteboard 名が出ない |
| MS-09 | サンプルが `UnityMacPlugin` を import していない（T-18 完了条件） |

---

## 8. 実装順序

1. `ContentView` へのメニューカード追加と `ClipboardSampleView` の骨格（タイトル / Result / scope Picker / `sectionView` / `updateResult`）
2. セクション 1〜7、11、12（同期・async の通常 API）
3. セクション 9（File Promise 受領。3 形態と cancel）
4. セクション 8 の OP-16 / OP-17（drag を除く）
5. セクション 10（`PasteButtonHost`）
6. §6.2 の drag harness 検証 -> 成立すれば実装、不成立なら設計不足として報告

1〜5 の完了時点で T-18 完了条件の第 1 項（全公開 OP を Unity 非依存で実行）は満たされる。第 2 項（drag harness）は 6 に依存する。

---

## 9. 要検証項目

| # | 内容 | 影響 |
|---|---|---|
| 1 | ドラッグ pasteboard へ書いた File Promise が `beginDraggingSession` を越えて残るか（§6.2） | T-18 の完了条件 第 2 項と MT-05 |
| 2 | `NSOpenPanel` で選んだディレクトリへ `NSFilePromiseReceiver` がサンドボックス越しに書けるか（§5.3） | 受領先の既定値。不可ならコンテナ内固定 |
| 3 | 平文テキストに対する `detectMetadata` が 1515 を返すこと（設計書は「失敗する」と述べる） | セクション 6 の期待値 |
