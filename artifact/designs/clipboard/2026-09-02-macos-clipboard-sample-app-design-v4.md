# macOS Clipboard サンプルアプリ実装計画 v4

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/MacLibraryExample/`
- 設計書: `artifact/designs/clipboard/2026-08-29-macos-clipboard-design-v9.md`
- 実装結果: `artifact/results/clipboard/2026-09-02-macos-clipboard-implementation-feature-result-v14.md`
- 対応タスク: T-18（設計書 **§13**）
- 前版: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v3.md`
- **`PLANNED_SYMBOLS_EXEMPT`**: 本書は未実装のコードを名指すため、機械照合の
  「識別子の実在」検査を対象外とする（`scripts/check_design_consistency.py`）
- レビュー: `.../2026-09-02-macos-clipboard-sample-app-design-review-v2.md`（v2 に対して）、
  `.../2026-09-02-macos-clipboard-sample-app-design-review.md`（v1 に対して）

> T-18 の完了条件（設計書 §13）:
> **「全公開 OP が `MacLibraryExample` から Unity 非依存で実行できること」**
>
> v1 にあった「MT-05 用の最小 drag harness」は、機能設計 v9 で File Promise を範囲外に
> したため消滅した。

---

## 0. v3 からの変更点（レビュー v3 の反映）

**レビュー v3 の判定: 解消 4 / 一部 7 / 未対応 8。§0 の対応表が 3 回続けて実態より進んでいた。**
本節はその訂正を含む。

| 指摘 | 対応 |
|---|---|
| **高 1**: §3.3（errorMessage を画面表示）と §3.4（pasteboard 名を出さない）が矛盾。1505 / 1507 / 1508 のメッセージが名前を含む | **§3.4 を粒度で書き直した**。標準名は公開定数、利用者が付けた名前だけが機微。§3.3 に例外を明記し、ST-04 の対象を確定 |
| **高 2**: 新設した log 監査の行フィルタが、検査対象の欠陥そのもので無効化される | **ライブラリ側を修正**。行単位をやめ `Log.` 呼び出し全体を追う。**穴を再現した同じ変異で落ちることを確認** |
| 中 1: §6.6 の到達可能性が誤り（1502 / 1505 は到達可能、1521 が §6.2 と矛盾） | **§6.6 を訂正** |
| 中 3: ST-05 の走査対象・コメント除外・パス解決が未定義 | **§7.1 に明記** |
| 中 6: 監査の走査根が `MacLibrary/Clipboard` のみで、プラグインの Swift が全監査の外 | **ライブラリ側を修正**。両ツリーを走査。実際に 6 件検出し、いずれも機微でないことを確認して規則を整えた |
| 中 7: 機械照合を黙って緩めていた（FAIL 2 → 0 は除外によるもの） | **除外を明示的な opt-in に変更**。文書が `PLANNED_SYMBOLS_EXEMPT` と宣言した場合のみ SKIP。本書は宣言する |
| 低 1〜8 | **§7.4 と各節に反映**（v3 は「§7.4 に注記」と書きながら 1 行も書いていなかった） |

**v3 の §0 の誤り**

- 「低 3 件 → §7.4 に注記」と書いたが、低は **8 件**あり、§7.4 に注記は **1 行もなかった**
- 「一部」7 件は、指摘の前半だけを引用して解消と記載していた
- 件数を v1 レビューの 13 件と取り違えていた（v2 レビューは 19 件）

---

## 0.1 v2 からの変更点（レビュー v2 の反映）

| 指摘 | 対応 |
|---|---|
| **高 1**: §3.4 / MS-07 の秘匿要件が達成不能。`createPasteboard` 系 5 箇所が pasteboard 名を verbatim ログ出力 | **ライブラリ側を修正**。`ClipboardLog.request(_:)` を追加し 5 箇所を通した。MacLibrary に log 監査テストを新設。**サンプル計画ではなく機能側の不具合だった** |
| **高 2**: ST-05 が機械的検査になっていない（手書き同士の照合） | **§7.1 で実コードから導出する形へ再設計** |
| 中: §1.2 が OP-12 / 13 / 15 の `throws` を落としている | **§1.2 を実シグネチャから引き写した 1 行 1 OP の表に置換** |
| 中: §3.2 の Active scope 分類が API と不一致 | **§3.2 を同じ表から導出。OP-02 は scope を持たない** |
| 中: `MacClipboardManager` のインスタンス方針が未定義 | **§5.5 に明記** |
| 中: ST-03 / ST-04 が現契約では書けない | **§7.1 で書ける形に定義し直した** |
| 中: 共有 scheme が git に無い | **§7.3 に前提として明記** |
| 中: エラー 20 ケースの到達方針が無い | **§6.6 に到達可能性の分類を追加** |
| 中: 機能設計 §2.1 の U-05〜U-07 が計画に不在 | **§1.4 に対象外の理由を明記** |
| 中: MT-06 の部分失敗 fixture が無い | **§6.2 に追加** |
| 中: `PasteButtonHost` の生成タイミング未定義 | **§5.4 に明記** |
| 低 3 件 | §7.4 に注記 |

**高 1 は本計画の欠陥ではなく、レビューの過程で露出したライブラリの不具合である。**
実装レビュー 12 ラウンドで検出されなかった。BT-25 がブリッジの C 層しか監査しておらず、
MacLibrary 側に同等の監査が無かったため。

---

## 0.2 v1 からの変更点

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

### 1.2 公開 API（`MacClipboardManager` の実シグネチャより）

**1 行 1 OP。**`MacClipboardManager.swift` の `public func` から引き写した。v2 は散文で
書いたため OP-12 / 13 / 15 の `throws` を落としていた。

| OP | 関数 | scope 引数 | 実行方式 | callback 版 |
|---|---|---|---|---|
| OP-01 | `copy` | あり | `async throws` | あり |
| OP-02 | `append` | **なし**（`ownership` が scope を運ぶ） | `async throws` | あり |
| OP-03 | `read` | あり | `async throws` | あり |
| OP-04 | `readData` | あり | `async throws` | あり |
| OP-05 | `snapshot` | あり | `async throws` | あり |
| OP-06 | `clear` | あり | `async throws` | あり |
| OP-07 | `createPasteboard` | **なし**（`request` を取る） | `async throws` | あり |
| OP-08 | `removePasteboard` | あり | `async throws` | あり |
| OP-09 | `detectPatterns` | あり | `async throws` | あり |
| OP-10 | `detectValues` | あり | `async throws` | あり |
| OP-11 | `detectMetadata` | あり | `async throws` | あり |
| OP-12 | `accessBehavior` | あり | **同期 `throws`** | なし |
| OP-13 | `startObserving` | あり | **同期 `throws`** | なし |
| OP-14 | `stopObserving` | **なし** | **同期・非 throws** | なし |
| OP-15 | `checkForegroundChange` | あり | **同期 `throws`** | なし |
| OP-19 | `makePasteButton` | **なし** | **同期 `throws`** | なし |

「callback 版」列は **Unity ブリッジ向けの `completion:` 形**の有無を指す。OP-13
`startObserving` は `onEvent` クロージャを取るが、これはイベント購読であって callback 版では
ない。

**同期 `throws` が 4 件ある**（OP-12 / 13 / 15 / 19）。サンプルはこれらを `Task` で包まず、
`do / catch` で直接扱う。**表示は非同期の操作と同じ規約に落とす。**

```swift
func runSync(label: String, _ body: () throws -> String) {
    do { updateResult(.success(label: label, detail: try body())) }
    catch let error as ClipboardError {
        updateResult(.clipboardFailure(label: label, code: error.errorCode,
                                       message: error.errorMessage))
    } catch {
        updateResult(.otherFailure(label: label, description: error.localizedDescription))
    }
}
```

`AccessBehavior` と `CheckForegroundChange` の失敗時に何を出すかを実装者判断にしない
（レビュー v3 低 8）。

### 1.2.1 値の制約

- **scope**: `.general` / `.named(String)` / `.unique(String)`
- **content**: `ClipboardContent(items: [ClipboardItemData(representations: [UTI: Data])])`。
  UTI と生バイトの辞書であり、`.text` のような便宜 case は**ない**
- **copy options**: `ClipboardCopyOptions(localOnly: Bool)`。既定 `true`
- **append**: 自所有時のみ成功。他者所有なら `ownershipLost`（1511）
- **removePasteboard**: `.general` と標準名 5 種は `cannotReleaseStandardPasteboard`（1508）
- **detect**: macOS 15.4 未満は `detectionUnavailable`（1513）
- **OP-19**: `UTType` 解決できない識別子は `invalidTypeIdentifier`（1504）を **throw する**

### 1.3 エラー契約

`ClipboardError` は public な `errorCode: Int` / `errorMessage: String` を持つ。
範囲は 1501〜1515 / 1521〜1524 / 1599。**1516〜1520 は欠番**（File Promise と共に削除、
番号は詰めていない）。

### 1.4 対象外（機能設計 §2.1 の申し送り）

**U-05 / U-06 / U-07（`copyable` / `cuttable` / `pasteDestination`）はサンプルでも扱わない。**
機能設計 §2.1 がこれらを対象外としており、SwiftUI の View modifier でライブラリの公開 API
ではないためである。サンプルが独自に使うと、ライブラリを通らない経路を実演することになる。

### 1.5 不足前提

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

**16 OP すべてがいずれかのセクションに現れる。** ただし**この表は説明であって検査ではない**。
T-18 完了条件の機械的な検査は §7.1 の **ST-05 と ST-06** である（§7.1 で導出する）。

### 3.2 操作導線と Active scope

`Main Menu → Clipboard Example` の 1 階層。画面上部に **Active scope** の `Picker` を置く。

**Active scope が効くのは、§1.2 の表で「scope 引数あり」の 12 操作だけである。**

| | OP |
|---|---|
| 効く（12） | OP-01 / 03 / 04 / 05 / 06 / 08 / 09 / 10 / 11 / 12 / 13 / 15 |
| 効かない（4） | **OP-02**（`ownership` が scope を運ぶ）、**OP-07**（`request` を取る）、**OP-14**、**OP-19**（general 固定） |

v2 は「OP-01〜OP-11 と OP-15 に効く」と書いたが、OP-02 は scope 引数を持たず、
OP-12 / OP-13 は持つ。**表を散文に言い換えたことが誤りの原因だった**ため、§1.2 の表を
唯一の出典とする。

画面には次を注記する。

- **Paste Control は general 固定**（OP-19 は scope 引数を持たない）
- **Append は直前の copy が返した ownership に従う**（Active scope ではない）

### 3.3 エラー表示

原則は既存 3 画面と同じ。

```
[<label>] errorCode=<Int>, errorMessage=<String>
```

`ClipboardError` 以外は `[<label>] error=<localizedDescription>`。

**例外が 2 件ある**（§3.4）。`invalidPasteboardName`（1505）と `pasteboardUnavailable`（1507）は
**errorMessage を出さず、コードと固定文だけを表示する**。

```
[<label>] errorCode=1505 (the requested pasteboard name is not shown)
```

### 3.4 秘匿方針

**機微なのは「利用者が付けた pasteboard 名」であって、標準名ではない。** v3 は両者を
区別せず「pasteboard 名を出さない」と書いたため、標準名を含む 1508 を期待する
`RemoveGeneral` と矛盾していた。

| 種別 | 例 | 扱い |
|---|---|---|
| 標準名 | `general` / `font` / `ruler` / `find` / `drag` | **公開定数。表示してよい** |
| 利用者が付けた名前 | `.named("com.myapp.session")` | **機微。表示しない** |
| システム生成の一意名 | `.unique` の結果 | 機微。表示しない |

したがって errorMessage の扱いはこうなる。

| コード | 埋め込まれる値 | 表示 |
|---|---|---|
| 1505 `invalidPasteboardName` | **利用者が渡した名前** | **出さない**（コードと固定文のみ） |
| 1507 `pasteboardUnavailable` | 名前（どちらもあり得る） | **出さない**（同上） |
| 1508 `cannotReleaseStandardPasteboard` | **標準名のみ**（定義上そうなる） | 表示してよい |
| その他 | 値・長さ・理由 | 表示してよい |

**要件の確定形**

> 画面とログのどちらにも、クリップボードの値そのもの・完全パス・URL の query・
> **利用者が付けた pasteboard 名**を出さない。標準名、ファイル名、host は出してよい。

**ログ側の要件**

`ClipboardLog` の実挙動は次のとおりで、上の要件を満たす。

| ヘルパー | 出力 |
|---|---|
| `ClipboardLog.scope` / `.request` | named / unique は**短縮ハッシュ**（名前は出ない） |
| `ClipboardLog.path` | 最後のパス成分 |
| `ClipboardLog.url` | file は basename、他は scheme + host |
| `ClipboardLog.text` / `.data` / `.json` | 長さ・バイト数のみ |

加えて、**サンプルの `logText` は payload を複製しない**（§7.1 の `SampleOutcome`）。
既存 `ShareSampleView.updateResult` は result 全文をログへ出すため、そのまま踏襲すると
画面用の文字列がログへ複製される。サンプルのログは marker・成否・errorCode に限定する。

## 4. 変更ファイル一覧

### 4.1 新規作成

| パス | 内容 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift` | 本体。10 セクションと操作関数 |
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleSupport.swift` | `PasteButtonHost` / `ClipboardSampleFixtures` / `updateResult` |
| `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift` | §7.1 の自動テスト |
| `mac/MacLibraryExample/MacLibraryExample.xcodeproj/xcshareddata/xcschemes/MacLibraryExample.xcscheme` | **共有 scheme**。現在 git に無く、無いと §7.3 が他の環境で動かない |

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
- `MacLibrary` / `UnityMacPlugin` — **ただし T-18 の前提として 2 件を先に修正済み**:
  `ClipboardLog.request(_:)` の追加と log 監査テストの新設（レビュー v2 高 1 / v3 高 2 / 中 6）。
  いずれも T-18 とは独立した機能側の不具合で、**別コミットで扱う**

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

- **生成タイミングを固定する。** `makePasteButton` は loader を coordinator へ登録する
  副作用を持つため、View の再評価ごとに呼ぶと登録が積み上がる。**`onAppear` で 1 回だけ生成し、
  `@State` に保持する**。`makeNSView` は保持済みの View を返すだけにする
- 生成結果は `Result<NSView, Error>` として保持する
- 失敗時は Host を作らず、`updateResult` にエラーを出す
- 不正 UTI の操作は Host を経由せず `MacClipboardManager.makePasteButton` を直接呼ぶ
- View 破棄で進行中の paste load がキャンセルされることを **MS-06** で確認する

---

## 6. 実装詳細

### 5.5 `MacClipboardManager` のインスタンス方針

**サンプルは `MacClipboardManager.shared` のみを使う。**

理由は Unity 利用者と同じ経路を通すためである。ブリッジは `MacClipboardManager.shared` を
呼ぶので、サンプルが独自インスタンスを持つと別の状態を見ることになる。

**その結果、次はプロセス全体で 1 つになる。**

| 状態 | 影響 |
|---|---|
| 監視（OP-13 / OP-14） | 画面を出入りしても同じ監視。`onDisappear` の `stopObserving()` が必須（§6.4） |
| 変更追跡（OP-15） | 前回値がプロセス全体で共有される。初回 `true` は最初の 1 回だけ |
| paste loader の登録 | coordinator が保持。View 破棄で解放される |

MS-05 はこの前提のもとで確認する。

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
| `partialPasteContent` | **MT-06 用**。accepted type に合う item と合わない item を混ぜた 2 item。Paste Control で部分失敗の表示を作る。**導線**: §6.1 セクション 2 に `CopyPartialPasteContent` ボタンを置き、これを押してから Paste Control で貼り付ける |

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

### 6.6 エラーコードの到達可能性

`ClipboardError` は 20 ケース。**v3 の分類は 3 箇所誤っていた**（1502 / 1505 は到達可能、
1521 は §6.2 の fixture と矛盾）。実 API から引き直す。

| 分類 | コード | 到達方法 |
|---|---|---|
| **専用ボタンで到達**（11） | 1501 | `copy(items: [])` |
| | 1502 | `copy` に representations 空の item |
| | 1503 | `detectPatterns([])` |
| | 1504 | 不正 UTI での `copy` / `makePasteButton` |
| | 1505 | `createPasteboard(.named(""))` |
| | 1508 | `removePasteboard(.general)` |
| | 1511 | 古い ownership での `append` |
| | 1512 | `snapshot(matchingTypes: [])` |
| | 1515 | 平文への `detectMetadata` |
| | 1521 | **`partialPasteContent` を貼り付け**（§6.2） |
| | 1523 | `startObserving(interval: 0)` |
| **環境依存**（2） | 1513 / 1514 | macOS 15.4 未満 / ユーザーが拒否。到達したら記録 |
| **到達手段なし**（7） | 1506 / 1507 / 1509 / 1510 / 1522 / 1524 / 1599 | サンプルからは作れない |

**「全 20 ケースを画面から出す」ことは目標にしない。** 1506 は数百 MB の確保が要り、
1509 / 1510 は pasteboard が書き込みを拒否する状況を作れず、1522 は timeout を待つ間
画面が固まる。到達できないものを無理に作ると、サンプルが機能の実演ではなく異常系の
再現装置になる。これらはライブラリの単体テストが担保する。

**1505 は表示例外の確認も兼ねる**（§3.3）。押すと errorMessage ではなくコードと固定文が
出ることを、MS-07 で目視する。

## 7. 検証（M-8）

### 7.1 自動テスト

`MacLibraryExampleTests` に置く。`SampleOutcome`・fixtures・`runExpectingError` の判定部分は
`internal` とし、テストは `@testable import MacLibraryExample` で参照する。`private` にすると
ST-03 / ST-04 / ST-07 が書けない。

**v2 の ST-05 は機械的検査になっていなかった。** 「手書きのセクション注釈」と「テスト側の
手書き 16 件リスト」を突き合わせるだけで、注釈だけ書いて実装を忘れる経路が素通りした。
**両辺を実コードから導出する形に作り直す。**

| ID | 内容 | 両辺の出典 |
|---|---|---|
| **ST-01** | `ClipboardSampleFixtures` の各 fixture が期待する UTI とバイト数を持つ | fixture の実値 |
| **ST-02** | `detectionFixture` が URL と email の書式を含む | fixture の実値 |
| **ST-03** | `SampleOutcome` の formatter が、成功・`ClipboardError`・その他を所定の文字列に変換する | 純粋関数を直接呼ぶ |
| **ST-07** | **`runExpectingError` が 3 分岐を正しく判定する**（一致 = 成功 / 成功してしまった = 失敗 / 別コード = 失敗） | 判定関数を直接呼ぶ |
| **ST-04** | 同 formatter の出力が、値・完全パス・query・**利用者が付けた pasteboard 名**を含まない。標準名は許容（§3.4） | `invalidPasteboardName("com.myapp.secret")` などを与えて出力を検査 |
| **ST-05** | **`MacClipboardManager` の public 操作すべてが `ClipboardSampleView` から呼ばれている** | **両辺ともソースから抽出** |
| **ST-06** | `MacLibraryExample` のどのファイルも `UnityMacPlugin` を import していない | ソース走査 |

**ST-07 は MS-02 の裏づけである。** v2 にあった同趣旨の検査を v3 で落としてしまい、
「成功してしまった場合に失敗と表示される」を確認するものが計画から消えていた（レビュー v3 中 5）。
`runExpectingError` の判定部分を、表示から切り離した純粋関数にする。

#### ST-03 / ST-04 / ST-07 を書けるようにする設計

v2 の `updateResult` は `@State` を書き換えるだけで戻り値がなく、テストから検証できなかった。
**表示文字列の生成を純粋関数として切り出す。**

```swift
/// 表示とログの両方が、この 1 か所から作られる。
enum SampleOutcome {
    case success(label: String, detail: String)
    case clipboardFailure(label: String, code: Int, message: String)
    case otherFailure(label: String, description: String)

    var displayText: String { ... }   // 画面用
    var logText: String { ... }       // ログ用。marker / 成否 / errorCode のみ
}
```

- `updateResult` は `SampleOutcome` を受け取り、`displayText` を `@State` へ、`logText` を
  `Log.d` へ渡すだけにする
- **ST-03 / ST-04 は `SampleOutcome` を直接呼ぶ**ので UI を起動しない
- `logText` が payload を含まないことは ST-04 が保証する（§3.4 の要件）

#### ST-05 の導出（レビュー高 2）

```
左辺: MacClipboardManager.swift から `public func <name>(` を抽出し、
      init / shared / defaultObservationInterval を除いた関数名の集合
右辺: MacLibraryExample/ 配下の全 .swift から `MacClipboardManager.shared.<name>(`
      を抽出した関数名の集合

検査: 左辺 ⊆ 右辺
```

**走査の条件**（レビュー中 3）

| 項目 | 決定 |
|---|---|
| 右辺の走査対象 | **`MacLibraryExample/` 配下の全 `.swift`**。§4.1 が support ファイルにも生成コードを置くため、`ClipboardSampleView.swift` 限定では漏れる |
| コメントと文字列 | **除外する**。`// MacClipboardManager.shared.detectMetadata(...)` と書くだけで通る偽の緑を防ぐ |
| パス解決 | `#filePath` から `mac` ディレクトリまで遡って解決する（`ClipboardLogAuditTests` と同じ方式） |

**どちらも手書きのリストを持たない。** 公開操作が増えればテストが落ち、サンプルに
呼び出しを足すまで通らない。逆にサンプルが呼んでいない操作があれば、その名前が
そのまま失敗メッセージに出る。

同じ理由で、§3.1 のセクション対応表は**説明であって検査ではない**。T-18 完了条件の
機械的な検査は ST-05 と ST-06 の 2 本である。

#### 監査が空回りしないこと

ST-05 / ST-06 は、抽出結果が空でないことを併せて検査する。左辺が 0 件になれば
「すべて呼ばれている」が無条件に真になるため（実装レビュー R11-L5 と同じ形）。

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

**前提**: `MacLibraryExample` の scheme は現在 git に共有されていない
（`MacLibraryExample.xcodeproj/xcshareddata/xcschemes/` が存在しない）。**共有 scheme を
コミットするまで下記コマンドは他の環境で動かない。** 実装時に共有する。

```bash
xcodebuild clean test -workspace mac/MacWorkspace.xcworkspace \
  -scheme MacLibraryExample -destination 'platform=macOS' \
  -resultBundlePath /tmp/MacLibraryExample.xcresult
xcrun xcresulttool get test-results summary --path /tmp/MacLibraryExample.xcresult

xcodebuild build -workspace mac/MacWorkspace.xcworkspace \
  -scheme MacLibraryExample -destination 'platform=macOS'

git diff develop --check
```

### 7.4 合格条件

| | |
|---|---|
| ST-01〜ST-07 | 全通過 |
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
7. **ST-05 / ST-06 / ST-07**（公開操作の呼び出し網羅、Unity 非依存、期待エラー判定）

**3〜6 の完了時点で T-18 完了条件の大部分が満たされ、7 で機械的に確認できる。**

---

## 10. 要検証項目

| # | 内容 | 影響 |
|---|---|---|
| 1 | 平文テキストへの `detectMetadata` が 1515 を返すこと（機能設計は「失敗する」と述べる） | §6.1 セクション 6 の期待値 |
| 2 | **`PasteButton` が `supportedContentTypes` に適合しない provider を払い出すか。** 払い出さない場合、`partialPasteContent` では部分失敗を作れず、MT-06 と 1521 の到達手段が別途必要になる | §6.2 / §6.6 / MT-06 |
| 2 | ~~`MacLibraryExampleTests` ターゲットの有無~~ → **解決**。`mac/MacLibraryExample/MacLibraryExampleTests/` が実在し、project も `PBXFileSystemSynchronizedRootGroup` を使う。§4.2 の「`project.pbxproj` を変更しない」は成立する | - |
