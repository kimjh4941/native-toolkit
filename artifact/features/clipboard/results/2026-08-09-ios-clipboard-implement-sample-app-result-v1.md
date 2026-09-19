# iOS Clipboard サンプルアプリ実装結果 v1

## 基本情報

- 日付: 2026-08-09
- 機能名: clipboard
- 対象OS: iOS 18 以降
- 対象サンプルアプリ: `ios/IosLibraryExample`
- 計画ファイル: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v6.md`
- 機能設計書: `artifact/designs/clipboard/2026-08-02-ios-clipboard-design-v4.md`
- 企画書: `artifact/plans/clipboard/2026-08-01-ios-clipboard-research-v4.md`
- 機能実装結果: `artifact/results/clipboard/2026-08-08-ios-clipboard-implementation-feature-result-v8.md`
- 対応タスク: 設計書 T-12
- ビルド環境: Xcode 26.3 / Swift 6.2.4 コンパイラ / `SWIFT_VERSION = 5.0`

本レポートは計画 v6 の §1〜§5・§7・§9（T-12 の範囲）を実装した結果である。
§6（T-00）と §8.2（T-13）は別タスクの成果物であり、本作業の対象外。

---

## 1. 変更ファイル

### 1.1 新規作成

| パス | 内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift` | 機能本体。`ClipboardSampleIdentifiers` / `ClipboardPasteControlView` / `FullWidthPressableButtonStyle` を同ファイル内に定義（計画 §7.1・追加判断 6） |
| `ios/IosLibraryExample/IosLibraryExampleTests/ClipboardSampleViewTests.swift` | View 単体テスト 8 件（計画 §9.2 U-12 の「View unit test でも固定」に対応） |

### 1.2 既存変更

| パス | 変更内容 |
|---|---|
| `ios/IosLibraryExample/IosLibraryExample/ContentView.swift` | `Clipboard Example` の `NavigationLink` + `menuCard` を追加。`menu.clipboard` identifier を付与 |
| `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift` | `ClipboardUITests` クラス（U-1〜U-20、21 テスト）と helper を追加。既存 `IosLibraryExampleUITests` クラスは無変更 |
| `ios/IosLibraryExample/IosLibraryExample.xcodeproj/xcshareddata/xcschemes/IosLibraryExample.xcscheme` | `IosLibraryExampleUITests` の並列実行を無効化（計画 §7.2・追加判断 20）。下記注記を参照 |

> **scheme の正規化について**: 当初 `parallelizable = "YES"` → `"NO"` へ書き換えたが、その後
> Xcode 26.3 でプロジェクトを開いた際に scheme が正規化され、`IosLibraryExampleUITests` の
> `parallelizable` **属性自体が削除**された。属性なしは既定値（並列無効）を意味するため、
> 「Clipboard UI テストを直列実行する」という §9.4 の要件は満たされたままである。
> `IosLibraryExampleTests`（単体テスト）は `parallelizable = "YES"` のまま変更していない。

### 1.3 非変更（計画 §7.3 のとおり）

`IosLibraryExampleApp.swift` / 既存 3 サンプル View / `project.pbxproj` / `ios/IosLibrary/**`。

`project.pbxproj` は `PBXFileSystemSynchronizedRootGroup` 採用済みのため、新規 2 ファイルの追加でも変更不要だった（ビルドで確認済み）。

---

## 2. 実装したサンプル機能

### 2.1 画面構成

計画 §4.2 の wireframe どおり。

```
[IosClipboardManager Example]
[✅ #12 [read] numberOfItems=1, items=[...]]     <- clipboard.result
[Scope: general | Observing: off | Events: 0]    <- clipboard.status
[Paste result: -]                                <- clipboard.pasteSummary
ScrollView
  ├─ Scope / Copy / Copy Options / Append / Read / Inspect
  └─ Load (async) / Detect / Observe / Paste Control (UI) / Clear / Error Cases
```

### 2.2 操作一覧

| セクション | identifier | 結果 marker | 件数 |
|---|---|---|---:|
| Scope | `clipboard.section.scope` | `useGeneral` / `createNamed` / `useFixedNamed` / `createUnique` / `removeActive` / `probeRemoved` | 6 |
| Copy | `clipboard.section.copy` | `copyPlainText` / `copyPlainTextEmpty` / `copyHtml` / `copyURL` / `copyImageFile` / `copyImageData` / `copyColor` / `copyCustomData` / `copyFileFixture` / `copyMultipleText` / `copyMultiRepresentation` / `copyDetectionFixture` | 12 |
| Copy Options | `clipboard.section.copyOptions` | `copyLocalOnlyTrue` / `copyLocalOnlyFalse` / `copyBBaseline` / `copyExpiring` | 4 |
| Append | `clipboard.section.append` | `appendPlainText` / `appendURL` / `appendUniversalMarker` | 3 |
| Read / Inspect | `clipboard.section.read` | `read` / `readData` / `snapshot` / `snapshotMatching` | 4 |
| Load (async) | `clipboard.section.load` | `loadText` / `loadURL` / `loadImage` / `loadFile` | 4 |
| Detect | `clipboard.section.detect` | `detectPatterns` / `detectValues` | 2 |
| Observe | `clipboard.section.observe` | `startObserving` / `stopObserving` / `checkForeground` | 3 |
| Clear | `clipboard.section.clear` | `clear` | 1 |
| Error Cases | `clipboard.section.errorCases` | `errMultipleEmpty` / `errMultiRepEmpty` / `errImageMissing` / `errCopyInvalidUTI` / `errInvalidURL` / `errInvalidColor` / `errReadInvalidUTI` / `errRemoveGeneral` / `errObserveMissing` / `errEmptyPatterns` / `errEmptyAcceptedTypes` | 11 |
| **結果 marker 合計** | — | — | **50** |
| control-only | Load / Paste Control | `cancelLoads` / `mountPasteControl` | 2 |

marker は `ClipboardSampleIdentifiers.Action` の値をそのまま使い、identifier は
`ClipboardSampleIdentifiers.button(_:)` が `clipboard.button.<marker>` を組み立てる。
実装差が構造的に発生しない（計画 §4.5）。単体テストで 50 件の一意性を固定している。

### 2.3 結果表示形式（計画 §4.5）

| 種別 | 形式 |
|---|---|
| 成功 | `✅ #<seq> [<marker>] <payload>` |
| 失敗 | `❌ #<seq> [<marker>] errorCode=<code>, errorMessage=<message>` |
| キャンセル | `ℹ️ #<seq> [<marker>] Cancellation completed (CLIPBOARD_CANCELLED)` |
| 警告 | `⚠️ #<seq> [<marker>] fileSize=<n>, cleanup=failed` |

`#<seq>` は同一 View / process epoch 内でのみ単調増加する。

### 2.4 セキュリティ方針の実装（計画 §4.6）

| 対象 | 画面 | ログ |
|---|---|---|
| クリップボード値 | 表示しない | 出さない |
| ファイルパス・URL・pasteboard 名 | 表示しない | 出さない |
| 件数 / byte 数 / 文字数 / 型識別子 / kind / errorCode | 表示する | 出す |

- `scopeLabel(_:)` は kind と名前長のみを返す（`named(len=44)`）
- `updateResult` は seq・marker・kind だけをログへ出し、payload は出さない
- `consumeLoadedFile` の cleanup 失敗ログにパスを含めない
- `Read` は item ごとに `index / hasText / textLength / typeIdentifiers.count / urlString の有無` を出し、raw 値は出さない（M-16 の 14 / 24 / 31 文字判別に使う）
- `detectValues` は各配列の件数と `probableWebURL` / `probableWebSearch` / `number` の有無のみ

### 2.5 依存方向

`ClipboardSampleView.swift` の import は `SwiftUI` / `UIKit` / `IosLibrary` のみ。
`UnityIosPlugin` への依存や `UIPasteboard` の直接呼び出しはない。
S1〜S11 のすべてが `IosLibrary` の P-1〜P-16 で到達できた（計画 §3.1 のとおり、設計不備なし）。

`UIKit` の import は `ClipboardPasteControlView: UIViewRepresentable` が `UIView` を返すために必要で、
`UIPasteControl` の生成自体はライブラリの `makePasteControl` に委譲している。

---

## 3. Android/iOS 共通実装パターンに対する維持・拡張

| 観点 | 維持 | 拡張 |
|---|---|---|
| 機能カテゴリ単位のセクション分け | 維持（Android `ClipboardSampleScreen.kt` と同じ 11 分類） | — |
| 結果表示を画面上部に固定 | 維持 | 状態バー（`Scope / Observing / Events`）と貼り付け結果バーを追加 |
| Error Cases を独立セクションにし期待コードをボタン名に含める | 維持 | — |
| 画面破棄時に監視を停止 | 維持（`onDisappear`） | — |
| `Toast` / Back ボタンの明示配置 | 踏襲しない（iOS 既存サンプルに前例がない） | — |
| 固定サンプルデータ + ボタン（`TextField` なし） | 維持 | — |

iOS 既存サンプル（`ShareSampleView` / `NotificationSampleView` / `DialogSampleView`）に対して:

| 要素 | 維持 | 拡張 |
|---|---|---|
| `NavigationStack` + `NavigationLink` 導線 | 維持 | — |
| `Text("<Manager> Example")` を `.title` + `.bold` | 維持 | — |
| 灰色背景の角丸ボックスによる結果表示 | 維持 | `#<seq>` と `[<marker>]` を追加 |
| `sectionView(title:content:)` | 維持 | `identifier:` 引数を追加（UI テスト用） |
| `FullWidthPressableButtonStyle` | 同一実装を複製 | — |
| `updateResult` の `✅` / `❌` | 維持 | `ℹ️` / `⚠️` を追加 |
| `DispatchQueue.main.async` による UI 更新 | 維持（`ios.md` の規約） | — |
| `async throws` 版 API の利用 | 維持 | 同期 control API（`startObserving` / `stopObserving` / `checkForegroundChange` / `cancelAllLoads` / `makePasteControl`）はそのまま同期呼び出し |

`ShareSampleView` の `FullWidthPressableButtonStyle` は `private struct`（ファイルスコープ）のため
参照できず、同一内容を `ClipboardSampleView.swift` にも定義した。

---

## 4. ビルド結果

| コマンド | 結果 |
|---|---|
| `xcodebuild build -workspace ios/IosWorkspace.xcworkspace -scheme IosLibraryExample -destination 'platform=iOS Simulator,id=<iPhone 17 Pro / iOS 26.2>'` | `** BUILD SUCCEEDED **` |
| `xcodebuild build-for-testing`（Simulator） | `** TEST BUILD SUCCEEDED **` |
| `xcodebuild build-for-testing -destination 'platform=iOS,id=<iPhone XS>' -allowProvisioningUpdates` | `** TEST BUILD SUCCEEDED **` |

実機ビルドでは `iOS Team Provisioning Profile: *` が自動解決され、アプリ本体だけでなく
UI テスト Runner（`IosLibraryExampleUITests-Runner.app`）にもプロビジョニングが埋め込まれた。

- 新規 warning: **0 件**
- `ios/IosLibraryExample/IosLibraryExample.xcodeproj` は `PBXFileSystemSynchronizedRootGroup` のため、新規 2 ファイルの追加で pbxproj 変更は不要だった

### 4.1 Swift 6 移行負債を増やさないための対応

バイナリ framework 経由で import した `IosLibrary` の enum は resilient enum として扱われ、
網羅した `switch` でも `switch covers known cases, but ... may have additional unknown values;
this is an error in the Swift 6 language mode` が出る。初回ビルドで 4 件発生したため、
すべて `@unknown default` を追加して解消した。

| 箇所 | 対象 enum |
|---|---|
| `load(_:request:)` | `ClipboardLoadedItem` |
| `scopeKind(_:)` | `PasteboardScope` |
| `scopeLabel(_:)` | `PasteboardScope` |
| `eventKindLabel(_:)` | `ClipboardChangeEvent.Kind` |

既存の `NotificationSampleView.swift:486` に同種の warning が 1 件残っているが、本作業の対象外。

---

## 5. 自動テスト結果

**Simulator と実機の両方で実行した。** どちらも本レポートのソースと一致するビルドである。

| 環境 | 種別 | UI テスト | 単体テスト |
|---|---|---|---|
| iPhone 17 Pro / **iOS 26.2 Simulator** | ビルド確認 + 動作確認 | 21 件中 20 passed / 1 skipped / **0 failed** | 9 passed |
| iPhone XS / **iOS 18.7.2 実機** | **実機動作確認済み** | 21 件中 20 passed / 1 skipped / **0 failed**（2868 秒） | 9 passed |

> Simulator の内訳: U-1〜U-12 を 1289 秒で、U-13〜U-20 を 1233 秒で実行した（別ラン）。
> 実機は全 21 件を 1 ランで実行している。

```
** TEST EXECUTE SUCCEEDED **   (both environments)
```

**両環境で結果は完全に一致した。** skip 1 件（U-10b）も同じ理由で、環境差ではない（5.4）。

実機ビルドは `-allowProvisioningUpdates` により `iOS Team Provisioning Profile: *` が自動解決され、
UI テスト Runner（`IosLibraryExampleUITests-Runner.app`）にもプロビジョニングが埋め込まれた。

これにより設計 6.4 が要求する **iOS 18 / iOS 26 の 2 軸**が、自動化できた範囲については両方埋まった。
（プロンプト / 通知の目視観測は T-00 の担当のままで、本作業では未実施。）

実機は Simulator よりおおむね 1.2〜1.5 倍遅く、UI 往復 1 回に最大 28 秒かかった。

### 5.1 単体テスト（`IosLibraryExampleTests`）

`ClipboardSampleViewTests` 8 件すべて passed。

| テスト | 固定した契約 | 由来 |
|---|---|---|
| `checkForegroundPayloadKeepsTheRealReturnValue` | `changed` の実戻り値を false へ上書きしない（4 組合せ） | §5.8 / U-12 |
| `checkForegroundPayloadNeverClaimsManagerState` | `baseline` / `established` / `updated` を表示に含めない | §5.8 高 3 |
| `m16FixturesHaveDistinctLengths` | 14 / 24 / 31 文字が相互に異なる | §6.3 |
| `appendMarkerLengthIsStable` | `appendMarker` が毎回 24 文字（UUID 先頭 8 文字連結） | §5.4 |
| `fileFixtureIs64Bytes` | `fileFixturePayload` が 64 byte | §5.2 / U-11 |
| `detectionFixtureCoversEveryPattern` | 11 パターン分の入力語を含む | §5.7 |
| `buttonIdentifierIsDerivedFromTheMarker` | identifier が marker から導出される | §4.5 / §9.1 |
| `markersAreDistinct` | 結果 marker 50 件が一意、control 2 件と重複しない | §4.5 |

### 5.2 UI テスト（`IosLibraryExampleUITests/ClipboardUITests`）

| # | テスト | iOS 26.2 Sim | **iOS 18.7.2 実機** | 対応する手動観点 |
|---|---|---|---|---|
| U-1 | 画面遷移と 11 セクションの存在 | passed | **passed** | 8.1 #1 |
| U-2 | `Copy Plain Text` → `Read` で `numberOfItems=1` | passed | **passed** | 8.1 #2 |
| U-3 | `Snapshot` で `hasStrings=true` / `numberOfItems>=1` | passed | **passed** | 8.1 #3 |
| U-4 | `Copy` → `Append` → `Read` で件数増加 | passed | **passed** | 8.1 #6 |
| U-5 | 監視中 Events 増加 / 停止後は増えない | passed | **passed** | 8.1 #14 / #15 |
| U-6 | 監視中に Scope 6 件と `errObserveMissing` が無効 | passed | **passed** | 8.1 #16 |
| U-7 | Error Cases **11 件すべて**が marker + 期待コード | passed | **passed** | 8.1 #21 |
| U-8 | named 作成 → copy → read → remove → probe = `UNAVAILABLE` | passed | **passed** | 8.1 #4 / #5 |
| U-9 | `Clear` 後の `Snapshot` で `numberOfItems=0` | passed | **passed** | — |
| **U-10a** | preflight remove → unavailable、background 復帰後も read 成功 | passed | **passed** | 8.1 #26 の 1〜4 |
| **U-10b** | terminate 後に unavailable になること | skipped | **skipped（下記 5.4）** | 8.1 #26 の 5〜8 |
| U-11 | `Copy File Fixture` → `Load File` で `fileSize=64`、`cleanup=failed` なし | passed | **passed** | 8.1 #10 / #11 |
| U-12 | fresh process の初回 Check が実戻り値 `changed=false` + 注記 | passed | **passed** | 8.1 #17 |
| U-13 | 9 content kind + 空文字列が pasteboard へ書かれ `Snapshot` に現れる | passed | **passed** | 8.1 #3 |
| U-14 | `loadText` / `loadURL` / `loadImage` が payload を返す | passed | **passed** | 8.1 #7 / #8 / #9 |
| U-15 | `detectPatterns` / `detectValues` が成功して件数を返す | passed | **passed** | 8.1 #13 |
| U-16 | `readData` / `snapshotMatching` の**成功パス** | passed | **passed** | — |
| U-17 | `createUnique` の一連と `useGeneral` 復帰 | passed | **passed** | — |
| U-18 | `appendURL` / `appendUniversalMarker` で件数増加、marker が 24 文字で読み戻せる | passed | **passed** | — |
| U-19 | Copy Options 4 種の fixture が設計どおりの文字数で書かれる | passed | **passed** | — |
| U-20 | control-only 2 種が結果行を上書きしない | passed | **passed** | — |

U-13〜U-20 は実機ラン完了後に追加したが、その後に全 21 件で実機ランを再実行したため、**Simulator と実機の両方で実行済み**である（5.6）。

### 5.2.1 操作カバレッジ

| 区分 | 件数 | UI テストで実行 |
|---|---:|---:|
| 結果 marker | 50 | **50** |
| control-only marker | 2 | **2** |
| **合計** | **52** | **52（100%）** |

U-1〜U-12 だけでは 25 / 52 だった。U-13〜U-20 の追加で、**サンプルアプリのすべてのボタンが
自動 UI テストで最低 1 回は実行される**状態になった。

ただしこれは「ボタンを押して期待した結果が返る」ことの確認（T-12 の DoD）であり、
そのボタンが調べようとしている **OS 側の挙動**の検証ではない。後者は自動化できず、T-00 / T-13 に残る。

| ボタン自体（自動化済み） | OS 挙動（T-00 / T-13 に残る） |
|---|---|
| Copy Options 4 種が成功し fixture 長が一致する | `localOnly` が Universal Clipboard を実際に抑止するか（M-06 / M-16、2 台必要） |
| `detectPatterns` / `detectValues` が成功し件数を返す | どのパターンが検出されるかの妥当性（OS 版・ロケール依存） |
| `mountPasteControl` で control が生成される | 外部アプリからの実際の貼り付け（8.1 #18〜#20） |
| `cancelLoads` が結果行を上書きしない | load 完了前に割り込むレース（8.1 #12、非決定的） |
| `copyExpiring` が成功する | 30 秒経過後に item が消えるか（M-07） |

### 5.3 U-11（受け入れ試験）の結論: **成立（実機で確認済み）**

計画 §5.6 / §1.6 は `UIPasteboard.items` へ `Data` を書いた後の
`itemProviders → loadFileRepresentation` 経路を「未実測」としていた。

**U-11 が Simulator と iOS 18.7.2 実機の両方で passed したため、この経路は成立する。**
`fileSize=64` を取得し、request スコープのディレクトリ削除も成功している（`cleanup=failed` なし）。

したがって §5.6 と §9.2 低 2 が用意していた「Files 由来 fixture への切替」「U-11 を manual / harness へ移す」
という代替案は**発動不要**である。§1.6 の不足前提からこの項目を落とせる。

### 5.4 U-10b（M-08）: 設計の前提が実機でも成立しなかった

これは本作業で最も重要な観測結果である。

| 条件 | iOS 26.2 Simulator | **iOS 18.7.2 実機** |
|---|---|---|
| 明示的な `removePasteboard` の直後 | `CLIPBOARD_UNAVAILABLE` | **`CLIPBOARD_UNAVAILABLE`** |
| background → foreground 復帰後 | read 成功（設計どおり） | **read 成功（設計どおり）** |
| **`terminate()` → `launch()` の後** | **90 秒 / 43 回の Read すべてで読めた** | **28 秒後の初回 Read で読めた** |

設計 v6 §8.1 #26・§8.2 M-08、および設計書 `2026-08-02-ios-clipboard-design-v4.md` の
「名前付き / ユニークペーストボードは**非永続**」「送信側終了後は解決できない」という前提は、
**Simulator でも実機でも観測できなかった**。当初は Simulator 固有の挙動を疑ったが、
実機で同じ結果が出たため**その仮説は否定された**。

**ライブラリの不具合ではない。** `removePasteboard` は Simulator / 実機の双方で即座に
`CLIPBOARD_UNAVAILABLE` を返しており（U-8 / U-10a、両環境で passed）、明示削除の経路は正しい。
OS がプロセス終了時に名前付きペーストボードを回収しない、という OS 側の挙動である。

#### 実機側の証拠の強さ（限界）

実機は UI 往復 1 回に最大 28 秒かかり、20 秒の poll 予算では **1 回しか試行できていない**。
Simulator の 43 回 / 90 秒に比べて弱い。「28 秒時点では消えていない」ことしか言えず、
**それより後に回収されるかどうかは未測定**である。

> **要追試（T-13 / M-08）**: 実機で数分〜数十分オーダーの再測定を行い、
> 「いずれ回収されるが遅い」のか「まったく回収されない」のかを切り分ける必要がある。
> 切り分け結果しだいで、設計書の「非永続」という記述に注記を追加すべきかが決まる。

#### テストの扱い

U-10b は判定を強制せず、次の設計にした。

- unavailable になった場合は **passed**
- ならなかった場合は測定値（試行回数・経過秒・最後の結果）を添えて **`XCTSkip`**

実機での skip メッセージ:

```
M-08 could not be decided here: the named pasteboard was still readable after 1 reads
over 28s following terminate()/launch(). Last result: "✅ #2 [read] numberOfItems=1,
items=[0:text(len=28) types=1 url=no]".
```

無条件 skip ではないため、将来 OS が回収するようになれば skip は自動的に消えて passed になり、
退行を隠さない。

> **注**: skip メッセージ末尾の `Requires device verification (T-13).` という文言は、
> Simulator でしか測定していなかった時点のものである。実機でも同じ結果が出た現在は
> 「実機での長時間追試が必要」が正しい。文言の修正は次の実装サイクルで行う。

### 5.5 テスト安定化のために解決した問題（実装時の追加判断）

| 問題 | 原因 | 対応 |
|---|---|---|
| ボタンへスクロールできず失敗 | `swipeUp()` / `swipeDown()` は慣性つき fling で 1 画面以上動くため、**両方向で対象を飛び越える**。50 ボタンの長い画面で顕在化 | 慣性のない `press(forDuration:thenDragTo:)`（画面高の約 30%）へ変更し、`scrollToDiscover` は「短い下方向プローブ → 先頭へ巻き戻し → 全長スイープ」の決定的手順にした |
| 監視中は先頭ボタンが無効で巻き戻せない | `scrollToTop` の anchor（`useGeneral`）が `.disabled` だと永久に hittable にならない | anchor の `frame.origin.y` が動かなくなった時点でも停止する進捗判定を追加 |
| セクション見出しへスクロールできない | 素の `Text` は hittable と報告されないことがある | 各セクションの代表ボタンを anchor にし、見出しは `exists` で検証 |
| poll が 1 回しか試行しない | UI 往復 1 回に約 4 秒かかり、計画 §8.1 #26 の「上限 5 秒」では 2 回目に入れない | 初回は必ず実行し、予算を 20 秒へ。**計画からの逸脱**（7.2 に記載） |

---

### 5.6 環境別カバレッジ

U-13〜U-20 は 1 回目の実機ラン完了後に追加したため一時的に実機側が 25 / 52 だったが、
**全 21 件で実機ランを再実行して解消した**。

| テスト | iOS 26.2 Simulator | iOS 18.7.2 実機 |
|---|---|---|
| U-1〜U-12（13 件） | 実行済み | 実行済み |
| U-13〜U-20（8 件） | 実行済み | 実行済み |
| **操作カバレッジ** | **52 / 52** | **52 / 52** |

**両環境とも 52 操作すべてを実行し、結果も一致した**（20 passed / 1 skipped / 0 failed）。

実機の全 21 件は 2868 秒（約 48 分）。最長は U-13 の 505 秒で、20 回の tap それぞれに
スクロール往復が入るためである。

---

## 6. 手動確認観点

### 6.1 自動化した観点（人手での再確認は不要）

8.1 の #1 / #2 / #3 / #4 / #5 / #6 / #10 / #11 / #14 / #15 / #16 / #17 / #21 / #26（前半）。
上記 5.2 の U-1〜U-12 で置き換え済み。

### 6.2 自動化していない観点（Simulator で実施可能・**本作業では未実施**）

| # | 観点 | 未実施の理由 |
|---|---|---|
| 8.1 #12 | `Load Image` 実行中の `Cancel All Loads` の**レース** | load 完了時間に依存し非決定的（§9.3）。control-only 契約は U-20 で自動化済み |
| 8.1 #13 の内容 | 検出された**パターンの妥当性** | OS 版とロケールに依存し期待値を固定できない（§5.7）。呼び出しの成否と件数は U-15 で自動化済み |
| 8.1 #22 | Xcode コンソールに機微情報が出ていないこと（M-15） | コンソールの目視（§9.3） |

8.1 #3（9 種の Copy）と #7 / #8 / #9（Load 3 種）は、当初この欄にあったが
**U-13 / U-14 として自動化したため解消した**。

#### 設計 §8.1 に手順がなかった 6 件（自動化で解消）

実装中に、計画 §8.1 のどの手動観点にも割り当てられていない操作が 6 件あることが分かった。
いずれも外部依存がないため自動 UI テストへ取り込んだ。

| marker | 状況 | 対応 |
|---|---|---|
| `copyPlainTextEmpty` | §1.5 が「空文字列の許可（境界）は扱う」としているのに 8.1 に手順がない | U-13 |
| `appendURL` | 8.1 #6 は `Append Plain Text` のみ | U-18 |
| `readData`（成功パス） | 失敗系 `errReadInvalidUTI` のみ U-7 で確認されていた | U-16 |
| `snapshotMatching` | `matchingItemIndexes` の確認手順がない | U-16 |
| `createUnique` | ユニークペーストボード作成の確認手順がない | U-17 |
| `useGeneral` | 既定 scope なので暗黙に使われるが明示確認がない | U-17 |

> **設計側への申し送り**: 上記 6 件は自動化で確認できるようになったが、
> **計画 §8.1 の手動確認表には依然として項目がない**。設計書を更新する場合は、
> 「自動 UI テストで担保」と明記して欠落を埋めるのが望ましい。

### 6.3 外部アプリが必要な観点（**未実施**）

8.1 #18 / #19 / #20、および T-00 のケース 2 / 3 / 5 / 6 / 11。
外部アプリでのコピー操作と system の paste UI に依存するため XCUITest から実行できない（§9.3）。

`Mount Paste Control` ボタンと `ClipboardPasteControlView` は実装済みで、U-1 が
`clipboard.button.mountPasteControl` の存在を確認している。貼り付け動作自体は未確認。

### 6.4 実機が必要な観点（**未実施** / 別タスク）

| 範囲 | 内容 | 担当タスク |
|---|---|---|
| 8.1 #23 / #24 | T-00 ケース 4 / ケース 10 | T-00 |
| 8.1 #25 | M-16（2 台・Universal Clipboard） | T-00 |
| 6 章全体 | 16 ケースの許可プロンプト / アクセス通知観測 | T-00 |
| 8.2 M-06〜M-15 | 実機手動確認 | T-13 |
| 8.2 M-08 | **設計の前提が実機でも成立せず。長時間追試が必要（5.4）** | T-13 |
| 8.2 M-09 | App Group | 対象外（entitlement と 2 アプリ目が必要） |

### 6.5 本サンプルの DoD から外した観点（計画どおり）

| 観点 | 委譲先 |
|---|---|
| Paste Control の partial / all failure | ライブラリの `PasteItemProviderLoaderTests` / `ClipboardPasteReceiverViewTests` |
| 画面離脱で監視が停止すること | manager / observer token を直接観測できる integration test |
| 64 MiB / 100 MP 上限判定 | unit test |
| 100 MP という上限値の妥当性 | T-13 harness |
| タイムアウト | unit test（短縮設定） |

---

## 7. 計画からの逸脱・実装時の追加判断

計画ファイル由来ではなく、実装時に判断した事項のみを挙げる。

| # | 判断 | 理由 |
|---|---|---|
| 1 | **U-10 を U-10a / U-10b へ分割**し、U-10b は判定不能時に `XCTSkip` する | terminate 後の unavailable が Simulator で観測できないため（5.4）。無条件 skip にせず、判定できた場合は passed になる形にして退行を隠さない |
| 2 | **U-10b の poll 予算を計画の「上限 5 秒」から 20 秒へ変更** | UI 往復 1 回に約 4 秒かかり、5 秒では 2 回目の試行に入れず「poll」として機能しないため。90 秒でも結果は変わらないことを測定済み |
| 3 | UI テストのスクロールを `swipeUp/Down` から `press(forDuration:thenDragTo:)` へ変更 | fling の慣性で対象を両方向に飛び越えるため（5.5） |
| 4 | `didCheckForegroundInThisView` を `Set<String>` ではなく `Set<PasteboardScope>` にした | 計画 §4.3 は `Set<String>` だが、表示ラベルは kind と名前長だけなので、**名前長が同じ別の named pasteboard を同一視してしまう**。scope 自体を key にすれば取り違えない。値は画面にもログにも出さない |
| 5 | `lastPastedItemCount` を `@State` に追加（計画 §4.3 の状態一覧にない） | §5.9 の partial failure が `items=N, failures=M` を要求し、`onPartialFailure` は `onPaste` の後に呼ばれるため、直前の item 数を保持する必要がある |
| 6 | `Copy Detection Fixture` を Detect セクションではなく **Copy セクション**へ配置 | §5.2 の Copy 表と §4.5 の marker 件数（Copy = 12）に合わせた。§5.7 にも同じボタンが載っているが、重複配置はしない |
| 7 | `Probe Last Removed Scope` を remove 前に押した場合、`❌ ... No pasteboard has been removed yet` を表示する | 画面側の事前条件エラーでライブラリの `errorCode` が存在しないため、失敗形式の `errorCode=` を持たない。U-8 は必ず remove 後に押すので試験には影響しない |
| 8 | `ClipboardSampleViewTests.swift` を新規追加 | §9.2 U-12 の「View unit test でも固定」に対応。あわせて M-16 / U-11 が依存する fixture 長（14 / 24 / 31 / 64）と marker 一意性も固定した |
| 9 | `checkForegroundPayload(changed:isFirstInThisView:)` を `static` として切り出した | 上記 8 を View の内部状態に触れずに単体テストするため。表示ロジックのみで副作用はない |
| 10 | resilient enum の `switch` に `@unknown default` を 4 箇所追加 | Swift 6 移行負債を新たに増やさないため（4.1） |
| 11 | **計画 §9.2 の U-1〜U-12 に加えて U-13〜U-20 を追加**した | U-1〜U-12 では 52 操作中 25 しか実行されず、残り 27 は「どの工程でも確認されない」状態だった。うち外部依存のないものはすべて自動化できると判断した（5.2.1） |
| 12 | U-15 / U-19 / U-20 は**呼び出しの成否までを判定範囲とし、OS 挙動は判定しない** | 検出パターンの中身・Universal Clipboard 転送・実際の貼り付けは自動化できず、T-00 / T-13 の担当だから。判定範囲を広げると環境依存で不安定になる |
| 13 | control-only 操作用に `tapControlAndAssertNoResult` helper を追加 | `tapAndWait` は新しい結果行を待つため、意図的に結果を出さない操作には使えない。固定 settle + 前後比較しか健全な判定手段がない |

---

## 8. ステップ8 実行確認

- 提示文: 「このサンプル実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して `review-implementation-sample-app` の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま終了
- ユーザー回答: 未回答
