# Windows Clipboard サンプルアプリ実装レビュー v1

## レビュー対象

- 日付: 2026-08-21
- 対象 OS: Windows 11 以降
- ブランチ: `feature/NTKIT-13`
- PR: 指定なし
- 差分: `git diff develop...HEAD` のうち、`windows/WindowsLibraryExample`、`windows/WindowsLibraryExampleUITest`、関連ルール・成果物を対象
- 計画: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v5.md`
- 実装結果: `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md`
- 参照ルール:
  - `agent-rules/coding-rules/common.md`
  - `agent-rules/coding-rules/windows.md`

## 検証結果

| 検証 | 結果 |
|---|---|
| `git diff --check`（Clipboard sample / UI test） | 成功 |
| `MSBuild WindowsLibraryExample.vcxproj -t:Build -p:Configuration=Debug -p:Platform=x64` | 成功。既存由来の `MSB3106` 2件 |
| `dotnet test WindowsLibraryExampleUITest.csproj --no-restore --configuration Release` | **失敗: 27 passed / 1 failed、合計28件** |
| 失敗テスト | `PageReentry_KeepsManagerStateAndClearsTheLog` |
| 実測された失敗内容 | 再入場後のログに deferred provider の size / fill ログが入り、空ログの期待に失敗 |

## レビュー概要

- `ClipboardPage`、メニュー導線、49ボタン、52個の一意な `AutomationId`、worker runner、履歴 callback、deferred provider が実装されている。
- C# / `net10.0-windows` の独立UIテストプロジェクトが追加され、FlaUI依存はInfra層へ概ね隔離されている。
- UIテストは直列化され、AUMID解決、MSIX起動、Error cases、Lifecycle / Busyの一部を自動化している。
- ただし、現在のUIテストは再実行で失敗し、二重Initializeには偽陽性がある。計画の自動化可能観点をすべて検証したという実装結果の記載とも一致しない。

## 重大な問題（high）

### H1. UIテストが再現可能に成功せず、ページ再入場の契約が未達

- 該当:
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardBusyAndNavigationTests.cs:99`
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardBusyAndNavigationTests.cs:113`
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp:76`
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp:83`
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp:528`
  - `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:21`
  - `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:339`
- 実測: 28件中1件失敗。再入場後のログは placeholder ではなく、旧予約に由来する provider query / fill ログになった。
- 原因候補:
  - テストが後続イベントを発生し得る `ReserveDeferredFormats` でログ状態を作っており、「再入場時にログが初期化されたこと」と「再入場後に新しいproviderイベントが来ないこと」を混同している。
  - `PostLog` / request callback のdispatcher lambdaが実行時点のグローバル `g_logSink` / `g_requestSink` を参照するため、旧ページ向けにqueueされた処理が新ページのsinkへ届く余地がある。`OnNavigatedFrom` はsinkをnullにするが、`g_dispatcher`と既にqueueされた処理を世代分離していない。
- 影響:
  - v5 §8.4「page Back -> re-entry: manager state維持、page logはclear」を安定して検証できない。
  - 実装結果の「28 passed / 0 failed」は現在のコードと環境で再現しない。
- 修正方針:
  - callback配送にページ世代または当時のweak sinkを持たせ、離脱前・離脱中に生成された配送が再入場後のページへ流れないようにする。
  - ログ初期化テストは、後続callbackが発生しない確定済み操作でログを作るか、再入場前ログ固有のtokenが新ページへ残っていないことを検証する。
  - 修正後に28件全件を複数回実行する。

## 改善提案（medium）

### M1. 二重Initializeテストが2回目のBridge呼び出しを証明していない

- 該当:
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardLifecycleTests.cs:74`
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardLifecycleTests.cs:80`
  - `windows/WindowsLibraryExampleUITest/Pages/ClipboardPage.cs:60`
- 1回目のInitialize後、結果欄には既に `[InitializeManager] errorCode=0` がある。2回目の押下直後に同じmarkerを待つため、Bridgeが呼ばれなくても古い値で即成功する。
- v5 §0 M2は「二重Initを実際に確認する」ことを要求しており、現在のテストでは保証できない。
- 操作連番をUIへ出す、完了ログを追加する、または2回目の前に結果を別markerへ変えてから待つ。

### M2. 自動化範囲の集計が誤り、未検証観点が残る

- 該当:
  - `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v5.md:627`
  - `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:206`
  - `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:339`
- v5 §8.4は17確認項目だが、resultは16項目としている。
- 少なくとも次が未検証または検証不十分:
  - cleanup完了ログ
  - Uninitialize完了後の再Initialize -> Copy
  - requestを発行してページ離脱した間に届いたcallbackが復元されないこと（現在のテストはcallbackが離脱中に届いたことを保証しない）
  - §8.2の `Reserve -> enumerate` はアプリ内で完結するが自動化されていない
  - §8.2の self copy通知抑止も、負の待機条件を設計すれば自動化候補になる
- `common.md:180` の「アプリ内で完結するものを自動化する」に照らし、対象表とテスト対応表を修正する。

### M3. Store app終了を待たず、テストごとのプロセス分離を保証していない

- 該当:
  - `windows/WindowsLibraryExampleUITest/Infra/FlaUiSession.cs:102`
  - `windows/WindowsLibraryExampleUITest/Infra/FlaUiSession.cs:106`
- `Application.Close()` はStore appの場合、`CloseMainWindow()`後にプロセス終了を待たずreturnする。各テストがfresh processを前提にしていても、次のLaunchが終了前プロセスを再アクティベートする可能性がある。
- Close後にprocess IDの終了をbounded waitし、残存時はKillしてから次テストへ進む。終了失敗を無条件に握り潰さず、cleanup failureとして記録する。
- 参照: `https://github.com/FlaUI/FlaUI/blob/main/src/FlaUI.Core/Application.cs`

### M4. AUMID照会の30秒timeoutが実質的に機能しない

- 該当:
  - `windows/WindowsLibraryExampleUITest/Infra/AppIdentity.cs:54`
  - `windows/WindowsLibraryExampleUITest/Infra/AppIdentity.cs:55`
- `ReadToEnd()`を`WaitForExit(30_000)`より先に呼ぶため、PowerShellが停止した場合はtimeoutへ到達せずblockする。
- `WaitForExit`の戻り値、exit code、stderrを検査し、timeout時はprocessを終了して明示的な配置エラーにする。
- 複数候補対策としてPowerShell側も `Select-Object -First 1 -ExpandProperty PackageFamilyName` で単一値にする。

### M5. 実装結果の変更ファイル一覧と現在の実装が一致しない

- 該当:
  - `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:27`
  - `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:47`
  - `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:178`
- §1は「新規4 + 既存4だけ」「v5 §11を満たす」としたままだが、その後 `.gitignore`、ルール2ファイル、UIテストプロジェクト11ファイル、AutomationIdが追加されている。
- 別タスクで追加した経緯は§5にあるが、レビュー対象時点の最終変更一覧と検証結果に更新されていない。27/28という最新結果も反映する。

## 軽微な指摘（low）

### L1. `CompleteWorkerOperation` が計画に反してpublic

- 該当:
  - `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v5.md:497`
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.h:129`
- 計画はprivate memberを要求するが、実装はpublicへ切り替えている。member function内で定義したlambdaからprivate memberを呼べるため、公開する必然性はない。

### L2. テストシナリオがFlaUI固有factory名を直接参照する

- 該当:
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardLifecycleTests.cs:40`
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardErrorCaseTests.cs:32`
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardBusyAndNavigationTests.cs:33`
- ページオブジェクトは`IUiSession`へ分離されているが、テストは`FlaUiSession.Launch()`を直接呼ぶ。将来raw UIAへ変更するとテストファイルも変更対象になる。
- `UiSessionFactory.Launch()`などの中立名をInfraに置けば、置換をInfra内へ閉じ込められる。

## 計画書整合性チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| 全セクション・全ボタンの実装 | ○ | 9セクション、機能48ボタン + Backを確認 |
| API呼び出し方針の一致 | ○ | UI直呼び / worker分離、buffer、callbackを静的確認 |
| システム設定の正確性 | △ | manifest非変更、配置済みMSIXからテスト起動済み。ただし全実機観点は未確認 |
| 変更ファイル一覧とのdiff整合 | × | result §1が後続UIテスト追加を反映していない |
| 追加判断のresultへの記録 | △ | 選定・Phase追加は記録済みだが、最終ファイル一覧・失敗結果・不足観点が未反映 |

## サンプルアプリパターン適合チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| メニュー導線 | ○ | 既存`NavigateTo`でClipboard cardを追加 |
| 画面構成パターン | ○ | Back / title / result / scroll / section構成を踏襲 |
| 成功・失敗表示フォーマット | ○ | Bridge errorとsample failureを分離 |
| 共通UI部品の利用 | ○ | `NotificationButtonStyle`を再利用 |

## プロジェクトルール適合チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| `common.md`準拠 | △ | 独立UIテストは追加したが、アプリ内完結の自動化可能観点が残る |
| `windows.md`準拠 | × | UIテスト全件成功、bounded process cleanup、安定した待機契約が未達 |
| Unityプラグイン非依存 | ○ | Sample / UI testともUnity参照追加なし |
| Log.d網羅性 | — | Android専用規約のため対象外 |
| KDoc網羅性 | — | Android専用規約のため対象外 |

## 手動確認観点の充足

記号: ○ = UIテストまたは実測で確認、△ = 実機・外部UI未確認または検証不十分、× = 今回の再実行で失敗。

### v5 §8.1 Interoperability

| No | 観点 | 評価 |
|---|---|---|
| 8.1-1 | CopyPlainText -> Notepad | △ |
| 8.1-2 | CopyHtml -> Word / browser | △ |
| 8.1-3 | CopyHtml -> Notepad | △ |
| 8.1-4 | CopyFiles <-> Explorer | △ |
| 8.1-5 | CopyImage <-> Paint | △ |
| 8.1-6 | CopyMultipleFormats -> Word / Notepad | △ |
| 8.1-7 | text + HTML -> GetPreferredFormat | △ |
| 8.1-8 | files only -> GetPreferredFormat | △ |
| 8.1-9 | image only -> GetPreferredFormat | △ |
| 8.1-10 | custom only -> GetPreferredFormat | △ |

### v5 §8.2 Monitoring / Deferred

| No | 観点 | 評価 |
|---|---|---|
| 8.2-1 | Init -> external copy | △ |
| 8.2-2 | self copyの通知抑止 | △ |
| 8.2-3 | Uninit TRUE -> external copy | △ |
| 8.2-4 | Reserve -> external paste | △ |
| 8.2-5 | Reserve -> Word paste | △ |
| 8.2-6 | Reserve -> enumerate | △ |
| 8.2-7 | Reserve -> app exit -> paste | △ |
| 8.2-8 | Reserve -> external copy | △ |

### v5 §8.3 History

| No | 観点 | 評価 |
|---|---|---|
| 8.3-1 | AvailabilityとWindows settingの一致 | △ |
| 8.3-2 | disabled -> GetHistory | △ |
| 8.3-3 | GetHistory callbackの順序・timestamp | △ |
| 8.3-4 | Restore callback待機 -> Paste | △ |
| 8.3-5 | Delete callback待機 -> GetHistory | △ |
| 8.3-6 | Clear callback待機 -> GetHistory | △ |
| 8.3-7 | history callbacks -> copy / setting change | △ |
| 8.3-8 | SENSITIVE -> Win+V | △ |
| 8.3-9 | EXCLUDE_ROAMING -> another device | △ |
| 8.3-10 | GetHistory -> Cancel | △ |

### v5 §8.4 Lifecycle / Thread / Busy

| No | 観点 | 評価 | 備考 |
|---|---|---|---|
| 8.4-1 | Initializeを2回 | △ | 2回目が古い結果で偽陽性になり得る |
| 8.4-2 | Request + Immediate Uninitialize | ○ | logでCANCELEDとFALSEを確認 |
| 8.4-3 | ShuttingDownで通常操作拒否 | ○ | UIテスト成功 |
| 8.4-4 | ShuttingDownで通常Initialize拒否 | ○ | UIテスト成功 |
| 8.4-5 | Force Initialize | ○ | UIテスト成功 |
| 8.4-6 | drain後CanDestroy | ○ | UIテスト成功 |
| 8.4-7 | Uninitialize retry | ○ | UIテスト成功 |
| 8.4-8 | cleanup完了ログ | △ | `temp cleanup pending`までしか検証していない |
| 8.4-9 | 再Initialize -> Copy | △ | 同一プロセス内の再初期化を未検証 |
| 8.4-10 | worker Reserve | ○ | WRONG_THREAD確認 |
| 8.4-11 | worker Uninit | ○ | WRONG_THREAD + Ready確認 |
| 8.4-12 | Back -> re-entry | × | 今回のテスト再実行でlog clearが失敗 |
| 8.4-13 | request -> Back -> re-entry | △ | callbackが離脱中に届いたことを保証しない |
| 8.4-14 | delayed中に通常操作 | ○ | Busy確認 |
| 8.4-15 | delayed中CanDestroy | ○ | FALSE + NONE確認 |
| 8.4-16 | delayed -> Back -> re-entry | ○ | Busy維持確認 |
| 8.4-17 | delayed完了後busy解除 | ○ | 次のCopy成功を確認 |

### v5 §8.5 Error cases

| No | 観点 | 評価 |
|---|---|---|
| 8.5-1 | null text | ○ |
| 8.5-2 | Paste after Clear | ○ |
| 8.5-3 | PasteHtml with text only | ○ |
| 8.5-4 | image size query | ○（CopyImage前提） |
| 8.5-5 | CF_BITMAP in multiple | ○ |
| 8.5-6 | duplicate format | ○ |
| 8.5-7 | CF_DIB + text payload | ○ |
| 8.5-8 | empty file array | ○ |
| 8.5-9 | Copy after Uninit | ○ |
| 8.5-10 | unknown cancel ID | ○ |

### v5 §8.6 Package

| 観点 | 評価 | 備考 |
|---|---|---|
| 配置済みMSIXの起動 | ○ | AUMIDから起動しUIA要素を取得 |
| Visual Studio Deploy + F5による手動確認 | △ | 未実施 |
| unpackaged history API | △ | 計画どおり未確認 |

## 総合評価

**要修正（重大）**

- C++サンプルのビルドと主要実装は成立している。
- ただし、必須UIテストが27/28で失敗し、二重Initなどの偽陽性・未検証観点もあるため、実装結果を「Phase 1 / 2完了、28 passed」として確定できない。
- 外部アプリ、Win+V、別デバイス、deferred renderingなどの実機確認は引き続きopenである。
