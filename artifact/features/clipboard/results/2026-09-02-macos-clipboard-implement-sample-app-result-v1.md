# サンプルアプリ実装結果 v1

## 基本情報

- 日付: 2026-09-02
- 機能名: clipboard
- 対象OS: macOS 15 以降
- 対象サンプルアプリ: `mac/MacLibraryExample/`
- 計画: `artifact/designs/clipboard/2026-09-02-macos-clipboard-sample-app-design-v4.md`
- 対応タスク: T-18（機能設計 §13）

> **ビルド確認と実機動作確認を区別する。** UI テストはこの環境で実行できていない（§5）。

---

## 1. 変更ファイル

### 1.1 新規作成

| パス | 内容 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleView.swift` | 本体。10 セクション |
| `mac/MacLibraryExample/MacLibraryExample/ClipboardSampleSupport.swift` | `SampleOutcome` / `ExpectedErrorJudge` / `ClipboardSampleFixtures` / `PasteButtonHost` |
| `mac/MacLibraryExample/MacLibraryExampleTests/ClipboardSampleTests.swift` | ST-01〜ST-07 |
| `mac/MacLibraryExample/MacLibraryExampleUITests/ClipboardSampleViewUITests.swift` | MS-01 / 02 / 03 / 05 / 07 の UI テスト |
| `mac/MacLibraryExample/MacLibraryExample.xcodeproj/xcshareddata/xcschemes/MacLibraryExample.xcscheme` | 共有 scheme（計画 §4.1。無いと再現コマンドが他環境で動かない） |

### 1.2 既存変更

| パス | 変更 |
|---|---|
| `mac/MacLibraryExample/MacLibraryExample/ContentView.swift` | Clipboard Example のメニューカードを追加 |

**`project.pbxproj` は変更していない**（計画 §4.2）。`PBXFileSystemSynchronizedRootGroup` により
フォルダへ置いたファイルは自動で target に含まれる。共有 scheme も別ファイルのため影響しない。

---

## 2. 実装したサンプル機能

計画 §3.1 の 10 セクションをすべて実装した。

| # | セクション | 操作 |
|---|---|---|
| 1 | Scope | CreateNamed / CreateUnique / RemoveCurrent / RemoveGeneral(1508) / CreateEmptyNamed(1505) |
| 2 | Copy | Text / URL / Image / MultipleItems / MultipleRepresentations / PartialPasteContent / Empty(1501) / EmptyRepresentations(1502) |
| 3 | Copy Options | localOnly トグル + CopyWithCurrentOptions |
| 4 | Append | CopyThenAppend / AppendWithStaleOwnership(1511) |
| 5 | Read / Inspect | Read / ReadDataPlainText / Snapshot / SnapshotFiltered / SnapshotEmptyFilter(1512) / AccessBehavior |
| 6 | Detect | DetectPatterns / DetectValues / DetectMetadata(1515) / DetectEmptyPatterns(1503)。**各ボタンが arrange → act を一続きで行う** |
| 7 | Observe | StartObserving / StartObservingInvalidInterval(1523) / StopObserving / CheckForegroundChange |
| 8 | Paste Control | PasteButtonHost / MakePasteButtonInvalidType(1504) / MakePasteButtonUndeclaredType(1504) |
| 9 | Clear | Clear |
| 10 | Error Cases | 到達済みコードの一覧と reset |

### 2.1 計画から維持したパターン

macOS 既存 3 画面（`ShareSampleView` 基準）の規約を維持した。

- `NavigationStack` + `menuCard` の導線
- 先頭のタイトルと結果表示ボックス、`sectionView` によるカテゴリ分け
- 成功 / 失敗が一目で分かる結果表示、コールバックのメインスレッド反映
- 公開 API 呼び出し前後の `Log.d`

### 2.2 計画で拡張した点

| 拡張 | 理由 |
|---|---|
| Active scope と observe 状態の表示 | 同じ操作を scope 別に試すため。停止し忘れを画面で見えるようにするため |
| `SampleOutcome` による表示とログの分離 | 表示規約をテスト可能にするため（計画 §7.1） |
| `runSync` / `runSyncExpectingError` | 同期 `throws` の 4 操作を非同期と同じ表示規約に落とすため |
| `PasteButtonHost` | OP-19 が `NSView` を返すため。`onAppear` で 1 回だけ生成する |

### 2.3 依存方向

**`MacLibrary` のみに依存する。** `UnityMacPlugin` を import していないことは **ST-06 が機械的に
検査する**。プラットフォーム API の直接呼び出しによる代替も行っていない。

---

## 3. 実装中に計画から外れた判断

| 判断 | 理由 |
|---|---|
| `ClipboardSampleTests` の呼び出し抽出を**文字列補間対応**にした | 計画 §7.1 は「コメントと文字列を除外」とのみ書いていた。文字列リテラルを丸ごと消すと `"removed=\(...clear(...))"` のような**補間の中の実コード**まで消え、ST-05 が誤って失敗した。補間部分は残す実装にした |
| UI テストのメニューカード遷移を `buttons` → `staticTexts` のフォールバックにした | `NavigationLink` にカスタムラベルを付けた場合、button として公開されないことがあるため |

---

## 4. 自動テスト

### 4.1 単体テスト（ST-01〜ST-07）

`MacLibraryExampleTests` に 10 件（parameterized 展開込み 12 件）。**すべて通過。**

| ID | 内容 |
|---|---|
| ST-01 | 各 fixture が期待する UTI とバイト数を持つ。partial fixture が 2 種の型を混ぜている |
| ST-02 | `detectionText` が URL と email を含む |
| ST-03 | `SampleOutcome` が 3 種を所定の文字列に変換する |
| ST-04 | **利用者が付けた名前（1505 / 1507）が画面にもログにも出ない。標準名（1508）は出る** |
| ST-05 | **公開操作 16 件すべてがサンプルから呼ばれている** |
| ST-06 | サンプルが `UnityMacPlugin` を import していない |
| ST-07 | 期待エラーの 3 分岐（一致 / 成功してしまった / 別コード）を判定する |

### 4.2 ST-05 の変異検査

**通ることではなく落ちることを確認した。**

| 注入した欠陥 | 結果 |
|---|---|
| `clear` の呼び出しを消す | **failed** |
| `clear` の呼び出しをコメントアウトに置き換える | **failed** |

2 番目は「コメントに書けば通る」偽の緑を防げているかの確認である。

### 4.3 UI テスト（MS-01 / 02 / 03 / 05 / 07）

`MacLibraryExampleUITests` に 5 件。**コンパイルは通るが、この環境では実行できていない。**

| MS | 内容 |
|---|---|
| MS-01 | 各セクションの代表ボタンが必ず結果を更新する |
| MS-02 | 期待どおり失敗した場合に成功として表示される（1508） |
| MS-03 | Active scope が scope 引数を持つ操作に反映される |
| MS-05 | 画面を離れると監視が停止する |
| MS-07 | 利用者が付けた名前が画面に出ない（1505）／標準名は出る（1508） |

---

## 5. ビルド / 実行結果

### 5.1 ビルド確認済み

| 対象 | 結果 |
|---|---|
| `MacLibraryExample` build | **BUILD SUCCEEDED**、警告 0 件 |
| `MacLibraryExample` build-for-testing | **成功**（UI テスト含む） |
| `MacLibraryExampleTests` | **12 passed / 0 failed**（xcresult より） |
| `MacLibrary` clean test | 351 passed / 0 failed |
| `UnityMacPlugin` clean test | 76 passed / 0 failed |
| Clipboard 由来の警告 | 0 件 |
| `git diff develop --check` | 0 件 |

### 5.2 実機動作確認: 未実施

**UI テストはこの環境で実行できなかった。**

```
Failed to click Button (First Match): No matches found ...
given input App element pid: 43722
```

アプリのプロセスは起動するが、XCUITest が取得するアクセシビリティ階層が空で、要素が
1 つも見つからない。

**原因はこのファイル群の外にある。** 同じ環境で**既存の `ShareSampleViewUITests` も同一の
症状で全件失敗する**ことを確認した。テストランナーがアプリを操作する権限を得られていない
（macOS の TCC）と考えられる。

したがって次のとおり記録する。

| | 状態 |
|---|---|
| UI テストのコード | **作成済み・コンパイル済み** |
| UI テストの実行 | **未実施**（環境制約。Xcode から実行すれば動くはず。要検証） |
| MS-01 / 02 / 03 / 05 / 07 | **未確認**（自動化済みだが実行できていない） |

**ビルド成功を機能動作と混同していない。** 本版で「動作確認済み」と言えるのは単体テストの
範囲だけである。

---

## 6. 手動確認観点

### 6.1 未実施（この環境で実行できない）

| ID | 理由 |
|---|---|
| MS-01 / 02 / 03 / 05 / 07 | UI テスト化済みだが §5.2 の制約で実行できない |
| MS-04 | named / unique の作成から削除まで。UI テスト未作成、手動確認が必要 |
| MS-06 | Paste Control の View 破棄でロードがキャンセルされる。破棄タイミングの制御が難しく UI テスト化していない |
| MS-08 | サンプルが `UnityMacPlugin` を import していない → **ST-06 が自動で検査するため手動確認は不要** |

### 6.2 機能設計の MT

| MT | 状態 | 理由 |
|---|---|---|
| MT-01 | 未実施 | 他アプリでのコピーが必要 |
| MT-02 | 未実施 | 他アプリでの貼り付けが必要 |
| MT-03 | 未実施 | `CopyThenAppend` / `AppendWithStaleOwnership` を実機で押す |
| MT-04 | 未実施 | 他アプリのコピーとアプリの非アクティブ化が必要 |
| MT-06 | 未実施 | Paste Control の部分失敗表示。**計画 §10 の要検証 2 が未解決**（`PasteButton` が非適合 provider を払い出すか） |
| MT-07 | 未実施 | macOS 15.4.1 と 15.2 の 2 環境が必要 |
| MT-08 | 未実施 | 実機 Mac + iPhone が必要 |
| MT-09 | 判定保留 | RK-22 |

**MT はすべて未実施である。** サンプルアプリは実装できたが、実機での確認は行っていない。

---

## 7. 要検証

| # | 内容 |
|---|---|
| 1 | 平文テキストへの `detectMetadata` が 1515 を返すこと（計画 §10 から継続） |
| 2 | `PasteButton` が `supportedContentTypes` に適合しない provider を払い出すか。払い出さない場合 MT-06 と 1521 の到達手段が別途必要（計画 §10 から継続） |
| 3 | **UI テストが権限のある環境で実際に通ること。** 本版では未確認 |

---

## 8. 残作業

1. **UI テストの実行**: 権限のある環境で 5 件を実行し、結果を記録する
2. **手動確認**: MT-01〜MT-04 / MT-06 / MT-07（MT-08 は実機 2 台）
3. **要検証 1 / 2 の解消**
4. **再レビュー**: 本版を対象に `review-implementation-sample-app` を実施する
