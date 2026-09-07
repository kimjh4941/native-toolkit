# iOS Clipboard サンプルアプリ実装レビュー v1

## レビュー対象

- 日付: 2026-08-11
- ブランチ: `feature/NTKIT-14`
- HEAD: `ab7f6aa24006f2dc3aa3bd941fffffcd03d5da44`
- 比較基準: `develop...HEAD`（merge-base: `dea227c9b00cc30f42a6c46827cb8988f32a1607`）
- 追加対象: 未コミットの `ios/IosLibraryExample` 配下、計画・実装結果ファイル
- 計画: `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v6.md`
- 実装結果: `artifact/results/clipboard/2026-08-09-ios-clipboard-implement-sample-app-result-v1.md`
- 対象OS: iOS 18以降

## レビュー概要

- `ContentView`へClipboard画面の導線を追加し、`ClipboardSampleView`にS1〜S11、結果marker 50件、control-only 2件を実装している。
- `IosLibrary`のnative APIだけを使用し、`UnityIosPlugin`や`UIPasteboard`の直接利用はない。
- 50 result markerと2 control identifierは一元化され、全ボタンがUIテストで少なくとも1回実行されている。
- 計画外のU-13〜U-20、View単体テスト、スクロール安定化は実装結果の追加判断へ記録されている。
- 実装結果はSimulator / iOS 18実機で20 passed / 1 skippedと報告している。今回の再検証では単体テスト9件が成功し、U-10bはSimulatorで7 read / 21秒後もreadableのためskipとなった。

## 重大な問題（high）

### H-01: U-10bがpreflightを行わず、M-08の主要結論を証明できない

- 対象:
  - `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift:316`
  - `artifact/results/clipboard/2026-08-09-ios-clipboard-implement-sample-app-result-v1.md:288`
  - 計画 `artifact/designs/clipboard/2026-08-09-ios-clipboard-sample-app-design-v6.md:1034`
- 計画v6は、固定named pasteboardをcreate → remove → no-create Readし、`CLIPBOARD_UNAVAILABLE`を確認してからfresh createすることをU-10の前提にしている。
- U-10aはpreflightを持つが、U-10b自身は`useFixedNamed` → `createNamed`から始まり、既存pasteboardのremove / unavailable確認を行わない。XCTestの実行順や前回失敗したrunの後処理へ依存している。
- `createNamed`は`create: true`で既存pasteboardも解決する。開始時に残存していた場合、今回のprocessが新規作成したpasteboardとは言えず、terminate後にreadableでも「作成process終了後にOSが回収しなかった」証拠にならない。
- そのため、result v1の「OSがプロセス終了時に回収しない」「ライブラリの不具合ではない」という断定は、現在のテストからは導けない。
- U-10bの先頭にも独立したpreflightを追加し、明示削除後のunavailableを確認してからfresh createすること。実機・Simulatorの測定を再実行し、その結果に基づいてresultの結論を訂正すること。
- unavailableを観測できない場合の`XCTSkip`自体は測定結果を残す方法として許容できるが、計画の受け入れ条件は未達である。controlled runの後に機能設計 / researchの寿命記述を再評価すること。

## 改善提案（medium）

### M-01: 到達可能なローカル失敗経路が共通の失敗表示契約を破る

- 対象:
  - `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift:250`
  - `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift:279`
  - `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift:286`
  - `ios/IosLibraryExample/IosLibraryExample/ClipboardSampleView.swift:671`
- 計画§4.5は失敗を`❌ #<seq> [<marker>] errorCode=<code>, errorMessage=<message>`へ統一している。
- 次の画面内失敗は`kind: .failure`なのに`errorCode=`を持たない。
  - remove前の`Probe Last Removed Scope`
  - bundle画像が見つからない`Copy Image File` / `Copy Image Data`
  - resilient enumの未知`ClipboardLoadedItem`
- result v1の追加判断7はProbeだけを例外化しているが、表示契約そのものは改訂されておらず、他の2系統も記録されていない。
- Probeを`lastRemovedScope == nil`の間は無効化するか、画面ローカル失敗にも固定の`CLIPBOARD_UNKNOWN`と公開メッセージを付けること。bundle / unknown enum経路も同じformatterを通し、resultの追加判断を更新すること。

### M-02: M-08の未達を成功したtest runと分離して受け入れ判定する必要がある

- 対象:
  - `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift:331`
  - `artifact/results/clipboard/2026-08-09-ios-clipboard-implement-sample-app-result-v1.md:190`
- `xcodebuild`は20 passed / 1 skipped / 0 failedで成功するが、U-10bは計画§9.2の必須期待値を確認していない。
- resultはskipを開示しているため隠蔽ではないが、総合受け入れでは「test command成功」と「計画のU-10完了」を分離する必要がある。
- controlled preflight後も同じなら、U-10bを単にgreen化せず、設計v6と機能設計v4を改訂して期待値・観測期間・T-13への移管条件を確定すること。それまでは計画書整合性を未達として扱うこと。

## 軽微な指摘（low）

### L-01: U-10bのコメントとskip文言が現在の実測状態と一致しない

- 対象: `ios/IosLibraryExample/IosLibraryExampleUITests/IosLibraryExampleUITests.swift:308`
- コメントは「Simulator cannot decide」、skip文言は`Requires device verification`としているが、result v1ではiOS 18.7.2実機でも同じ結果を測定済みである。
- result自身も古い文言だと認識している。`controlled long-duration device verification`など、現在残っている確認内容へ修正すること。
- クラスdoc commentも`U-1〜U-12`のままなので、U-20までを含む説明へ更新するとよい。

### L-02: ユーザー固有のXcode状態ファイルが未コミット差分に混入している

- 対象: `ios/IosWorkspace.xcworkspace/xcuserdata/jonghyunkim.xcuserdatad/UserInterfaceState.xcuserstate`
- 計画・resultの変更ファイル一覧に含まれないIDE状態のバイナリ差分であり、サンプル実装と無関係である。
- コミット対象から除外すること。既存追跡方針を変更する場合は別タスクで扱うこと。

## 計画書整合性チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| 全セクション・全ボタンの実装 | ○ | 11セクション、50 result marker、2 control-onlyを確認 |
| API呼び出し方針の一致 | ○ | native `IosClipboardManager`を使用。同期control / async throwsの区別も一致 |
| システム設定の正確性 | ○ | iOSではFileProvider / Manifest追加なし。schemeのUI test並列属性を削除 |
| 変更ファイル一覧とのdiff整合 | △ | View単体テスト追加はresultに記録済み。無関係な`xcuserstate`が残る |
| 計画との差分のresult記録 | ○ | U-10分割、poll延長、U-13〜U-20等を§7に記録 |
| U-10 / M-08の受け入れ条件 | × | U-10bはskip。さらに独立preflightを欠く |

## サンプルアプリパターン適合チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| メニュー導線 | ○ | 既存`NavigationLink` / `menuCard`パターンに一致 |
| 画面構成パターン | ○ | title、固定結果領域、status、ScrollView、section構成 |
| 成功/失敗表示フォーマット | △ | 通常経路は一致。M-01のローカル失敗が不一致 |
| 共通UI部品の利用 | ○ | private部品の同パターン複製はルール上許容 |

## プロジェクトルール適合チェック

| 観点 | 評価 | 注記 |
|---|---|---|
| `common.md`準拠 | ○ | native sample → native libraryの依存方向を維持 |
| `ios.md`準拠 | ○ | async throws APIと同期control APIを適切に使用 |
| Unityプラグイン非依存 | ○ | import / build依存ともに追加なし |
| `Log.d`網羅性 | ○ | 操作メソッドに先頭ログあり。pure UI / formatterは除外対象 |
| KDoc網羅性 | N/A | iOS / Swift対象。主要ViewとhelperのDocCコメントは付与済み |

## 手動確認観点の充足

| 範囲 | 評価 | 状態 |
|---|---|---|
| §8.1 #1〜#11 | ○ | UIテストで主要happy pathを確認。U-11 file経路も成功 |
| §8.1 #12 Cancel race | △ | control-onlyは確認、pending loadとの実レースは未確認 |
| §8.1 #13 Detection内容妥当性 | △ | API成功と件数のみ。OS / locale別の妥当性は未確認 |
| §8.1 #14〜#17 | ○ | observe、disable、初回Check表示を確認 |
| §8.1 #18〜#20 Paste Control | △ | mountのみ確認。外部アプリからの貼り付けは未確認 |
| §8.1 #21 Error Cases | ○ | 11件の正式errorCodeを確認 |
| §8.1 #22 M-15ログ目視 | △ | 未実施 |
| §8.1 #23〜#25 / T-00 / M-16 | △ | 別タスク。privacy prompt、2台試験は未実施 |
| §8.1 #26 / M-08前半 | ○ | background復帰後のreadと明示removeを確認 |
| §8.1 #26 / M-08終了後 | × | U-10bはskip。controlled preflightも欠く |
| M-06〜M-15 | △ | M-08以外もT-13の実機手動確認が残る。M-09は対象外 |

## 検証結果

- `xcodebuild test ... -only-testing:IosLibraryExampleTests`: **TEST SUCCEEDED**、9 passed
- `xcodebuild test ... -only-testing:.../testU10b_namedPasteboardAfterProcessTermination`: command成功、1 skipped
  - 再観測: terminate / launch後も7 read・21秒にわたりreadable
- `git diff --check`: 問題なし
- 依存・セキュリティ静的確認: `UnityIosPlugin` / `UIPasteboard`直接利用なし、`jp.ubint`なし

## 総合評価

**要修正（重大）**

画面実装、native APIの利用、操作カバレッジ、fixture、ファイルcleanup、observer、marker / sequenceの実装品質は高く、M-08以外は計画に概ね整合している。

ただし、U-10bは計画で必須とした独立preflightを欠いたまま、固定named pasteboardの終了後寿命について最も重要な結論を出している。この測定条件では既存pasteboardを再利用した可能性を排除できず、result v1のOS挙動・非不具合判定を受け入れられない。H-01を修正して再測定し、U-10 / M-08の設計上の扱いを確定するまでLGTMとはしない。

T-00、M-16、Paste Control実貼り付け、M-15などの未実施項目は別タスクとして明示されているが、完了まではopen riskとして維持する。
