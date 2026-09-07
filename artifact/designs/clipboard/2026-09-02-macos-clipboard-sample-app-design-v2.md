# macOS Clipboard サンプルアプリ実装計画 v2

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/MacLibraryExample/`
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v14.md`
- 対応タスク: T-18（設計書 **§13**）
- 前版: `artifact/designs/clipboard/2026-08-30-macos-clipboard-sample-app-design-v1.md`
- レビュー: `artifact/reviews/clipboard/2026-09-02-macos-clipboard-sample-app-design-review.md`

> T-18 の完了条件（設計書 §13）:
> **「全公開 OP が `MacLibraryExample` から Unity 非依存で実行できること」**
>
> v1 にあった「MT-05 用の最小 drag harness」は、機能設計 v9 で File Promise を範囲外に
> したため消滅した。

---

## 0. v1 からの変更点

| レビュー指摘 | 状態 |
|---|---|
| **高優先度 1**: 現行 API で drag harness を構築できない | **消滅**。File Promise を v1 対象外にした（機能設計 §7.12） |
| M-1: OP-18 の overload 数え落とし | 消滅（同上） |
| M-4: File Promise の `source` と fixture が未定義 | 消滅（同上） |
| L-2: 受領ディレクトリの作成と cleanup | 消滅（同上） |
| M-2: Observe の画面寿命と cleanup | **§6.4 に lifecycle 表を新設** |
| M-3: `(expect error)` の成功条件 | **§6.3 に専用 runner を定義** |
| M-5: Detection の入力が非決定的 | **§6.2 に固定 fixture と arrange → act を定義** |
| M-6: Active scope が OP-19 に効かない | **§3.2 に明記。MS-03 を限定** |
| M-7: `PasteButtonHost` の throwing factory | **§5.4 に契約を定義**（実装が throw するようになった） |
| M-8: 自動テスト・accessibility・再現コマンド | **§7 に新設** |
| M-9: 秘匿方針が実挙動と一致しない | **§3.4 を実測に基づいて書き直し** |
| L-1: `project.pbxproj` は変更不要 | **§4.2 から削除**（`PBXFileSystemSynchronizedRootGroup` 使用） |
| L-3: T-18 の参照節が誤り（§17 → §13） | **訂正** |

---

## 1. 前提情報の抽出

### 1.1 in-scope

公開 OP は **16 件**。すべて `MacClipboardManager`（`MacLibrary`）の public API。

| 分類 | OP |
|---|---|
| 書き込み | OP-01 copy / OP-02 append |
| 読み出し | OP-03 read / OP-04 readData / OP-05 snapshot |
| 消去 | OP-06 clear |
| pasteboard 管理 | OP-07 createPasteboard / OP-08 removePasteboard |
| 検出 | OP-09 detectPatterns / OP-10 detectValues / OP-11 detectMetadata |
| 環境 | OP-12 accessBehavior |
| 監視 | OP-13 startObserving / OP-14 stopObserving / OP-15 checkForegroundChange |
| UI 部品 | OP-19 makePasteButton |

OP-16 / OP-17 / OP-18 / OP-20 は v1 対象外（欠番。機能設計 §7.12）。

### 1.2 公開 API の制約

- **実行方式**: OP-01〜OP-11 は `async throws`。OP-12〜OP-15 / OP-19 は同期
- **scope**: `.general` / `.named(String)` / `.unique(String)`
- **content**: `ClipboardContent(items: [ClipboardItemData(representations: [UTI: Data])])`。
  UTI と生バイトの辞書であり、`.text` のような便宜 case は**ない**
- **copy options**: `ClipboardCopyOptions(localOnly: Bool)`。既定 `true`
- **append**: 自所有時のみ成功。他者所有なら `ownershipLost`（1511）
- **removePasteboard**: `.general` と標準名 5 種は `cannotReleaseStandardPasteboard`（1508）
- **detect**: macOS 15.4 未満は `detectionUnavailable`（1513）
- **OP-19**: `acceptedTypes` に `UTType` 解決できない識別子があると
  `invalidTypeIdentifier`（1504）を **throw する**（R11-H2 で変更）

### 1.3 エラー契約

`ClipboardError` は public な `errorCode: Int` / `errorMessage: String` を持つ。
範囲は 1501〜1515 / 1521〜1524 / 1599。**1516〜1520 は欠番**（File Promise と共に削除、
番号は詰めていない）。

### 1.4 不足前提

- **MT-09**（プライバシーアラート）の判定基準は機能設計で保留。観察のみとし成否判定しない
- **`localOnly` の実効性**（MT-08）は未検証。`ClipboardCopyOptions` の DocC 自身が
  "has not been verified on real hardware yet" と述べている

---

## 2. 既存サンプルコードの深掘り

### 2.1 主参照ペア（Windows）

`windows/WindowsLibraryExample/` のページは `MainMenuPage` / `DialogPage` / `NotificationPage`
の 3 つで、**Clipboard 画面はない**。

主参照ペアからは「メインメニューのカード → 機能別ページ → 先頭に結果表示 → カテゴリ別
ボタン群」という**構造**のみを引き継ぎ、UI 規約と命名は workflow ステップ 4 の規定どおり
**対象OS自身の既存サンプルを優先**する。

### 2.2 macOS サンプルの既存規約

`ShareSampleView.swift`（404 行、最新）を基準とする。

- `private let TAG = "XxxSampleView"`、`Log.d` / `Log.e` で入出力を残す
- `@State private var resultText = "Result will be displayed here"`
- 画面先頭は「タイトル → 結果表示ボックス → `ScrollView`」
- 操作は `sectionView(title:)` でカテゴリ別にグルーピング
- ボタンは `FullWidthPressableButtonStyle`（ファイル末尾に private 定義）
- 結果は `updateResult(isSuccess:result:)` に一本化。`DispatchQueue.main.async` で反映
- エラーは `catch let error as XxxError` で `errorCode=` / `errorMessage=` を並記
- 実行処理は `runXxx(label:...) async` に切り出し、ボタン側は `Task { await ... }` のみ

### 2.3 iOS Clipboard サンプルとの突き合わせ（参考）

`ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift`（1,070 行）は同機能の
先行実装で、**セクション構成の網羅性チェックに使う**（主参照ではない）。

macOS で追加が必要なもの: `accessBehavior`（OP-12）、`checkForegroundChange`（OP-15）、
named / unique pasteboard の作成・削除（OP-07 / OP-08）。

iOS 側の秘匿ヘルパーは、macOS では `ClipboardLog`（public）で代替できる。ただし §3.4 の
とおり**そのままでは要件を満たさない**。

### 2.4 深掘り結論

**再利用**: `ContentView.menuCard`、`ShareSampleView` の `sectionView` / `updateResult` /
`FullWidthPressableButtonStyle` の各パターン（同型で新設）、`MacLibrary.ClipboardLog`。

**追加**: `ClipboardSampleView`（本体）、`PasteButtonHost`（`NSViewRepresentable`）、
`ClipboardSampleFixtures`（決定的な入力の生成）。

**変更**: `ContentView.swift` にメニューカードを 1 枚追加。

---

## 3. 画面要件

### 3.1 セクション構成

| # | セクション | 対象 OP |
|---|---|---|
| 1 | Scope | OP-07 / OP-08 |
| 2 | Copy | OP-01 |
| 3 | Copy Options | OP-01（`localOnly`） |
| 4 | Append | OP-02 |
| 5 | Read / Inspect | OP-03 / OP-04 / OP-05 / OP-12 |
| 6 | Detect | OP-09 / OP-10 / OP-11 |
| 7 | Observe | OP-13 / OP-14 / OP-15 |
| 8 | Paste Control | OP-19 |
| 9 | Clear | OP-06 |
| 10 | Error Cases | 到達済みエラーコードの一覧 |

**16 OP すべてがいずれかのセクションに現れる。** この対応表が T-18 完了条件の検査対象。

### 3.2 操作導線と Active scope

`Main Menu → Clipboard Example` の 1 階層。画面上部に **Active scope** の `Picker` を置く。

**Active scope が効くのは `scope` 引数を持つ操作だけである。**（M-6）

| | |
|---|---|
| 効く | OP-01〜OP-11、OP-15 |
| 効かない | **OP-19 `makePasteButton`**（`scope` 引数を持たず general 固定）、OP-12 / OP-13 / OP-14 は §6 のとおり個別に扱う |

Paste Control セクションには「**general 固定**」と画面に注記する。

### 3.3 エラー表示

```
[<label>] errorCode=<Int>, errorMessage=<String>
```

`ClipboardError` 以外は `[<label>] error=<localizedDescription>`。

### 3.4 秘匿方針（M-9。実測に基づく）

**`ClipboardLog` をそのまま使っても要件を満たさない。** 実挙動は次のとおり。

| ヘルパー | 出力 |
|---|---|
| `ClipboardLog.path` | **最後のパス成分**（`path(export.txt)`） |
| `ClipboardLog.url` | file URL は **basename**、他は **scheme + host** |
| `ClipboardLog.scope` | named / unique は**短縮ハッシュ**（名前は出ない） |
| `ClipboardLog.text` / `.data` / `.json` | 長さ・バイト数のみ |

したがってサンプルの要件はこう定義する。

> **画面とログのどちらにも、クリップボードの値そのもの・完全パス・URL の query・
> pasteboard 名を出さない。ファイル名と host は `ClipboardLog` 経由でのみ出てよい。**

加えて、**サンプル専用の `updateResult` はログへ payload を複製しない**。

既存 `ShareSampleView.updateResult` は `Log.d(TAG, "[updateResult] ... result: \(result)")` と
result 全文をログに出す。`ClipboardError.errorMessage` は入力値や system reason を含むため、
そのまま踏襲すると画面用の文字列がログへ複製される。**サンプルのログは marker、成功可否、
errorCode に限定する。**

---

## 4. 変更ファイル一覧

### 4.1 新規作成

| パス | 内容 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift` | 本体。10 セクションと操作関数 |
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleSupport.swift` | `PasteButtonHost` / `ClipboardSampleFixtures` / `updateResult` |
| `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift` | §7.1 の自動テスト |

### 4.2 既存変更

| パス | 変更理由 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ContentView.swift` | Clipboard Example のメニューカードを追加 |

**`project.pbxproj` は変更しない。**（L-1）対象 project は
`PBXFileSystemSynchronizedRootGroup` を使っており、フォルダに追加した Swift ファイルは
自動で target に含まれる。テストターゲットが未作成の場合のみ、その追加で変更が生じる。

### 4.3 非変更

- `MacLibraryExampleApp.swift`: Clipboard は起動時セットアップを必要としない
- `DialogSampleView.swift` / `NotificationSampleView.swift` / `ShareSampleView.swift`
- `MacLibraryExample.entitlements`
- `MacLibrary` / `UnityMacPlugin` の一切

---

## 5. 実装方針

### 5.1 維持する共通パターン

メインメニュー → サンプル画面の導線、先頭のタイトルと結果表示、`sectionView` による
グルーピング、`updateResult` の成功可否表示、コールバックのメインスレッド反映、
公開 API 呼び出し前後のログ。

### 5.2 拡張する点

| 拡張 | 理由 |
|---|---|
| Active scope の Picker | 同じ操作を scope 別に試す必要がある。ボタンを 3 倍に増やすより状態で切り替える |
| Observe の実行中表示 | OP-13 は開始/停止のある唯一の操作。停止し忘れを画面で分かるようにする |
| `NSViewRepresentable` の導入 | OP-19 が `NSView` を返すため |

### 5.3 依存方向の確認（workflow ステップ 6）

**問題なし。** OP-01〜OP-15 と OP-19 の 16 件すべてが `MacClipboardManager`（`mac/MacLibrary`）
の public API として実在する。Unity プラグイン経由でしか呼べない API は**ない**。

- 検査方法: `MacClipboardManager.swift` の `public func` 一覧と §1.1 の OP 表を突き合わせた
- サンプルの import は `MacLibrary` のみ。`UnityMacPlugin` を参照しない

### 5.4 `PasteButtonHost` の契約（M-7）

`NSViewRepresentable.makeNSView` は throw できないが、OP-19 は `throws -> NSView` である。
さらに R11-H2 で、**`UTType` 解決できない識別子は throw する**ようになった。

**View を作る前に生成し、結果を保持する。**

```swift
struct PasteButtonHost: NSViewRepresentable {
    let view: NSView            // 生成済み。makeNSView は返すだけ
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
```

- 生成は `ClipboardSampleView` 側で行い、`Result<NSView, Error>` として保持する
- 失敗時は Host を作らず、`updateResult` にエラーを出す
- 不正 UTI の操作は Host を経由せず `MacClipboardManager.makePasteButton` を直接呼ぶ
- View 破棄で進行中の paste load がキャンセルされることを MS-05 で確認する

---

## 6. 実装詳細

### 6.1 セクション別の操作

`await run(label:)` は「`Task` で包み、`ClipboardError` を `errorCode` / `errorMessage` に、
その他を `localizedDescription` に落として `updateResult` する」共通ラッパー。

#### 1. Scope

| UI | 呼び出し |
|---|---|
| Picker: `general` / `named` / `unique` | 状態のみ |
| `CreateNamedPasteboard` | OP-07 `.named("nt-sample")` → 返る scope を Active に |
| `CreateUniquePasteboard` | OP-07 `.unique` → 同上 |
| `RemoveCurrentPasteboard` | OP-08 → 成功時は Active を `general` へ |
| `RemoveGeneral` | OP-08 `.general` → **1508 を期待** |

#### 2. Copy / 3. Copy Options / 4. Append / 9. Clear

| UI | 呼び出し |
|---|---|
| `CopyText` / `CopyURL` / `CopyImage` | OP-01。UTI と `Data` の辞書はフィクスチャが組む |
| `CopyMultipleItems` / `CopyMultipleRepresentations` | OP-01 |
| `CopyEmpty` | OP-01 `items: []` → **1501 を期待** |
| Toggle `localOnly` + `CopyWithCurrentOptions` | OP-01 に `ClipboardCopyOptions(localOnly:)` |
| `CopyThenAppend` | OP-01 → 返る ownership で OP-02 |
| `AppendWithStaleOwnership` | OP-01 → 別内容で OP-01 → 最初の ownership で OP-02 → **1511 を期待** |
| `Clear` | OP-06。消した item 数を表示 |

#### 5. Read / Inspect

| UI | 呼び出し |
|---|---|
| `Read` | OP-03。item 数、UTI 一覧、合計バイト数 |
| `ReadDataPlainText` | OP-04。**バイト数のみ**。該当なしは成功かつ `nil` |
| `Snapshot` / `SnapshotFiltered` | OP-05 |
| `SnapshotEmptyFilter` | OP-05 `matchingTypes: []` → **1512 を期待** |
| `AccessBehavior` | OP-12。同期 |

#### 6. Detect（M-5。決定的にする）

**各ボタンは arrange → act を一続きで行う。** 現在のペーストボード内容に依存しない。

| UI | arrange | act | 期待 |
|---|---|---|---|
| `DetectPatterns` | `detectionFixture` を copy | OP-09 に固定 pattern set | 検出されたパターン名の集合 |
| `DetectValues` | 同上 | OP-10 | **値は出さず、field ごとの件数と optional の有無のみ** |
| `DetectMetadata` | 平文テキストを copy | OP-11 | **1515 を期待**（システムが記述できない） |
| `DetectEmptyPatterns` | なし | OP-09 に空集合 | **1503 を期待** |

`detectionFixture` は URL と email を含む固定文字列とする。pattern set も固定する。
macOS 15.4 未満では全操作が **1513**。

#### 7. Observe

| UI | 呼び出し |
|---|---|
| `StartObserving` | OP-13。既定間隔 0.5 秒。`onEvent` で `updateResult` |
| `StartObservingInvalidInterval` | OP-13 `interval: 0` → **1523 を期待** |
| `StopObserving` | OP-14。同期 |
| `CheckForegroundChange` | OP-15。同期。`Bool` を表示 |

`onEvent` は MainActor で来るため `updateResult` をそのまま呼べる。

#### 8. Paste Control

`PasteButtonHost` が OP-19 の `NSView` を保持する（§5.4）。

- `acceptedTypes: ["public.utf8-plain-text", "public.png"]`、`timeout: 5`
- `onPaste` で件数と部分失敗の有無を表示
- `MakePasteButtonInvalidType`: 不正 UTI → **1504 を期待**
- `MakePasteButtonUndeclaredType`: `com.mycompany.myformat` → **1504 を期待**（R11-H2）

**この Button は自身の有効性を検証しない**（accepted type が無くても押せる）ことを画面に注記。

#### 10. Error Cases

到達したエラーコードの一覧を表示する。どの契約を確認済みかを見えるようにする。

### 6.2 フィクスチャ（M-5）

`ClipboardSampleFixtures` が決定的な入力を組む。

| 名前 | 内容 |
|---|---|
| `text` | 固定文字列 |
| `url` | 固定 URL |
| `png` | 固定サイズの生成画像 |
| `detectionFixture` | URL と email を含む固定文字列 |
| `plainTextOnly` | `detectMetadata` を失敗させるための平文 |

### 6.3 期待エラー専用の runner（M-3）

共通 `run` は `ClipboardError` を失敗として表示する。一方、`(expect error)` 系のボタンは
**指定コードが返れば成功**である。この 2 つを混ぜると MS-01 と MS-02 が衝突する。

```swift
func runExpectingError(label: String, expected: Int, _ body: () async throws -> Void) async
```

| 結果 | 表示 |
|---|---|
| 指定コードを throw | **成功**（`expected 1508 as designed`） |
| 成功してしまった | **失敗**（`expected 1508, but the call succeeded`） |
| 別のコード | **失敗**（`expected 1508, got 1512`） |

### 6.4 lifecycle（M-2）

| 状態 | 開始 | 終了 | 画面破棄時 |
|---|---|---|---|
| `observationActive` | `StartObserving` 成功 | `StopObserving` | **`onDisappear` で `stopObserving()`** |
| Active scope の named / unique | OP-07 成功 | `RemoveCurrentPasteboard` | **解放しない**（pasteboard server に残るのが正しい挙動。画面に注記） |
| `PasteButtonHost` の loader | Host 生成 | View 破棄 | View の `deinit` で `cancelPaste`（ライブラリ側の責務） |

**`onDisappear` は `stopObserving()` を必ず呼ぶ。** v1 は handle 解放しか書いておらず、
MS-05 の要求を満たしていなかった。

### 6.5 入力バリデーション方針

サンプル側で事前検証は**行わない**。不正値はそのままライブラリへ渡し、返るエラーコードを
表示する。各 `(expect error)` の目的が、ライブラリの検証契約の確認そのものであるため。

---

## 7. 検証（M-8）

### 7.1 自動テスト

`MacLibraryExampleTests` に置く。**UI 操作ではなく、サンプルが依存する純粋な部分**を対象とする。

| ID | 内容 |
|---|---|
| ST-01 | `ClipboardSampleFixtures` の各 fixture が期待する UTI とバイト数を持つ |
| ST-02 | `detectionFixture` が URL と email を含む |
| ST-03 | `runExpectingError` が 3 分岐（一致 / 成功 / 別コード）を正しく判定する |
| ST-04 | 結果 formatter が値・完全パス・query・pasteboard 名を含まない |
| ST-05 | セクション定義が公開 OP 16 件をすべて含む（§3.1 の対応表を機械照合） |

**ST-05 が T-18 完了条件の機械的な検査である。**

### 7.2 accessibility identifier

section / button / result / observe status に一意な identifier を与える。

```
clipboard.section.<name>
clipboard.button.<name>
clipboard.result
clipboard.observeStatus
```

UI テストは本計画では書かない（ペーストボードを共有するため直列化が必要で、
費用対効果が見合わない）。identifier は手動確認と将来の UI テストのために定義する。

### 7.3 再現コマンド

```bash
xcodebuild clean test -workspace mac/MacWorkspace.xcworkspace \
  -scheme MacLibraryExample -destination 'platform=macOS'
xcrun xcresulttool get test-results summary --path <*.xcresult>

xcodebuild build -workspace mac/MacWorkspace.xcworkspace \
  -scheme MacLibraryExample -destination 'platform=macOS'

git diff develop --check
```

### 7.4 合格条件

| | |
|---|---|
| ST-01〜ST-05 | 全通過 |
| ビルド警告 | Clipboard 由来 0 件 |
| `UnityMacPlugin` の import | **0 件**（T-18 完了条件） |
| `git diff develop --check` | 0 件 |

---

## 8. 手動確認観点

### 8.1 機能設計の MT との対応

| MT | 手順 | 状態 |
|---|---|---|
| MT-01 | 他アプリでコピー → `Read` | 実施可 |
| MT-02 | `CopyText` → 他アプリで貼り付け | 実施可 |
| MT-03 | `CopyThenAppend` と `AppendWithStaleOwnership` | 実施可 |
| MT-04 | `StartObserving` → 他アプリでコピー → 非アクティブ → 復帰 | 実施可 |
| MT-06 | Paste Control から貼り付け。部分失敗表示 | 実施可 |
| MT-07 | 15.4.1 と 15.2 の両方で Detect 各種 | 実施可（2 環境必要） |
| MT-08 | `localOnly` を切り替えて実機 Mac + iPhone | 実施可（実機 2 台必要） |
| MT-09 | 各操作時のプライバシーアラート | 観察のみ。判定保留（RK-22） |

MT-05 は機能設計 v9 で削除された。

### 8.2 サンプル固有

| ID | 観点 |
|---|---|
| MS-01 | 10 セクションすべてのボタンが押下可能で、Result が必ず更新される |
| MS-02 | `(expect error)` が設計どおりの errorCode を返し、**成功してしまった場合に失敗と表示される** |
| MS-03 | Active scope の切り替えが**`scope` 引数を持つ操作**に反映される（Paste Control は general 固定） |
| MS-04 | named / unique を作成 → 操作 → 削除まで通る |
| MS-05 | Observe を開始したまま画面を離れると停止する |
| MS-06 | Paste Control の View 破棄で進行中の load がキャンセルされる |
| MS-07 | 画面表示とログのどちらにも、値・完全パス・query・pasteboard 名が出ない（§3.4） |
| MS-08 | サンプルが `UnityMacPlugin` を import していない |

---

## 9. 実装順序

1. `ContentView` へのメニューカード追加と `ClipboardSampleView` の骨格
   （タイトル / Result / scope Picker / `sectionView` / `updateResult` / `runExpectingError`）
2. `ClipboardSampleFixtures` と ST-01 / ST-02 / ST-03 / ST-04
3. セクション 1〜5、9、10（同期・async の通常 API）
4. セクション 6（Detect。arrange → act）
5. セクション 7（Observe。lifecycle 込み）
6. セクション 8（`PasteButtonHost`）
7. ST-05（セクション定義と公開 OP の機械照合）

**3〜6 の完了時点で T-18 完了条件の大部分が満たされ、7 で機械的に確認できる。**

---

## 10. 要検証項目

| # | 内容 | 影響 |
|---|---|---|
| 1 | 平文テキストへの `detectMetadata` が 1515 を返すこと（機能設計は「失敗する」と述べる） | §6.1 セクション 6 の期待値 |
| 2 | ~~`MacLibraryExampleTests` ターゲットの有無~~ → **解決**。`mac/MacLibraryExample/MacLibraryExampleTests/` が実在し、project も `PBXFileSystemSynchronizedRootGroup` を使う。§4.2 の「`project.pbxproj` を変更しない」は成立する | - |
