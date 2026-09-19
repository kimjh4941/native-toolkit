# Windows Clipboard サンプルアプリ実装 再レビュー v2

## レビュー対象

- ブランチ: `feature/NTKIT-13`
- 対応コミット: `92d26ffaa6fb913112767d6e50f572f1fbb743e9`
- 比較: `develop...HEAD`、およびレビュー v1 対応差分 `92d26ffa^...92d26ffa`
- 計画: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v5.md`
- 実装結果: `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-21-windows-clipboard-implement-sample-app-review-v1.md`
- 対象OS: Windows 11以降

## 検証結果

| 検証 | 結果 |
|---|---|
| `WindowsLibraryExample.vcxproj` Release / x64 Build | 成功。既存の `Microsoft.Windows.AI.Foundation.winmd` に関する `MSB3106` 警告2件のみ |
| `dotnet test ... --configuration Release --no-restore` | 33 passed / 0 failed、1分39秒 |
| テスト終了後の `WindowsLibraryExample` プロセス | 残存なし |
| `git diff --check 92d26ffa^ 92d26ffa`（対象ファイル） | 問題なし |

最初のサンドボックス内実行ではMSIX起動が `E_ACCESSDENIED` になったため、対話セッション権限で再実行した。上表は権限制限外での有効な実行結果である。

## レビュー概要

- v1の二重Initialize、AUMID timeout、private可視性、FlaUI参照分離、追加テストは適切に修正されている。
- UIテストは今回の再実行でも33件すべて成功した。
- ただしv1 H1の「離脱中に生成された配送を再入場先へ流さない」は、現在の世代管理では満たせない。テストもこの競合を待って検出する構造ではない。
- プロセス分離と実装結果の変更ファイル一覧にも不整合が残る。

## 重大な問題（high）

### H1. ページ世代分離が離脱後に到着したコールバックを除外できない

- 該当:
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp:89`
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp:140`
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp:519`
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp:544`
  - `windows/WindowsLibraryExample/ClipboardPage.xaml.cpp:861`
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardBusyAndNavigationTests.cs:125`
- `g_pageGeneration` は `OnNavigatedFrom` でのみ加算される。旧ページのrequest callbackが離脱後に到着すると、その時点の新しいgenerationを取得してqueueする。
- その後に再入場して新しい `g_requestSink` が登録されてもgenerationは変わらないため、queueされたlambdaの比較を通過し、新ページのsinkへ配送される。再入場後にcallbackが到着した場合も同様である。
- 新ページの `m_pendingRequests` に旧request IDはないため、`OnRequestCompleted` は `[Request] unknown request id=...` を新ページのログへ追加する。これはv5 §8.4-13「離脱中UI callbackは復元しない」と、コードコメント「Callbacks delivered while the page is away are dropped」に反する。
- 現在のテストは再入場直後に旧受付ログがないことを一度だけ確認する。旧callbackがその検査後に到着する競合は検出しないため、33件成功でも本契約の保証にはならない。
- 修正案:
  - request受付時に `requestId` と当時のpage generationまたはweak sinkを対応付け、completion時に同じpage instanceだけへ配送する。
  - 少なくともcallback thunkで実行時のグローバルsinkを参照せず、配送対象を確定してからqueueする。ただしrequestが再入場後に完了するケースまで扱うにはrequest単位の所有情報が必要。
  - テスト用にcompletionを遅延・制御できる境界を設け、「受付 -> Back -> 再入場 -> 旧completion」の順序を決定的に作り、新ページへログも状態も届かないことを検証する。

## 改善提案（medium）

### M1. プロセス終了失敗を記録するだけで、テスト分離失敗として扱っていない

- 該当: `windows/WindowsLibraryExampleUITest/Infra/FlaUiSession.cs:109`
- `WaitForExit` はbounded waitとKillを行うようになり、通常経路は改善された。
- しかしKill後も終了しない場合の例外を `Dispose` がcatchし、`Console.WriteLine`だけで正常終了する。コメントの「Surfaced」と異なり、テストは失敗せず次のテストが残存プロセスを再利用し得る。
- cleanup例外はMSTestへ伝播して当該テストを失敗させるか、少なくとも以後のテストを止める明示的な失敗状態にする。
- `LaunchStoreApp` 成功後にmain window取得が失敗した経路でも、現在は `Application.Dispose()`だけでアプリ終了を保証しない。同じ終了ヘルパーを利用するのが安全である。

### M2. self-copy通知抑止と再入場の負条件が瞬時検査で偽陽性になり得る

- 該当:
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardMonitoringTests.cs:37`
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardBusyAndNavigationTests.cs:117`
  - `windows/WindowsLibraryExampleUITest/Tests/ClipboardBusyAndNavigationTests.cs:144`
- いずれも操作直後のログを1回読むだけで、「後から対象ログが到着しない」ことを検証していない。
- fixed `Sleep` は使わず、短い観測期間の間pollし続け、禁止文字列が一度でも現れたら失敗するAdapter APIを追加する。H1のrequestテストは、さらにcompletion順序を制御できるテスト境界が必要である。

### M3. 実装結果のUIテストファイル一覧が再び現状と一致していない

- 該当: `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:51`
- §1.4は「新規12ファイル」と記載し、ツリーにも `ClipboardMonitoringTests.cs` がない。実際の `WindowsLibraryExampleUITest` は14ファイルである。
- v1 M5の目的は最終状態との一致なので、件数を14へ直し、Testsに5ファイルすべてを列挙する。

## 軽微な指摘（low）

なし。

## v1指摘対応状況

| v1指摘 | 評価 | 再レビュー結果 |
|---|---|---|
| H1 テスト失敗 | △ | ログ初期化の期待修正は妥当。配送世代分離は未完 |
| M1 二重Initialize偽陽性 | ○ | 2回目前に別markerへ移し、旧結果で成功しない |
| M2 件数・未検証観点 | △ | 17行へ訂正し5テスト追加。負条件と8.4-13は保証不足 |
| M3 プロセス終了待ち | △ | bounded wait + Killは追加。終了不能を失敗扱いしない |
| M4 AUMID timeout | ○ | 非同期読み取り、timeout、exit code、stderr、単一値化を実装 |
| M5 変更ファイル一覧 | × | 12と記載したが実際は14、Monitoring testも一覧漏れ |
| L1 private可視性 | ○ | `CompleteWorkerOperation` をprivateへ戻した |
| L2 FlaUI直接参照 | ○ | scenarioは `UiSessionFactory` 経由になった |

## 計画書整合性チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| 全セクション・全ボタンの実装 | ○ | 48操作と導線を維持 |
| API呼び出し方針の一致 | △ | 通常操作は一致するが、ページ離脱中request completionの配送契約が未達 |
| システム設定の正確性 | ○ | MSIX設定・既存solution構成に追加変更なし |
| 変更ファイル一覧とのdiff整合 | × | UIテスト14ファイルに対してresultは12ファイル |
| 追加判断のresult記録 | △ | v1対応の判断は記録済みだが、世代分離を完了扱いしている |

## サンプルアプリパターン適合チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| メニュー導線 | ○ | MainMenuからClipboardPageへ遷移 |
| 画面構成パターン | ○ | title、result、section、scroll、Backを既存形式で実装 |
| 成功/失敗表示フォーマット | ○ | resultとlogの役割を分離し既存形式を維持 |
| 共通UI部品の利用 | ○ | 既存WinUI 3サンプルの構成に準拠 |

## プロジェクトルール適合チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| `common.md`準拠 | △ | UI自動化は拡充したが、決定的でない負条件テストが残る |
| `windows.md`準拠 | △ | 33件成功、直列化、Adapter化は適合。callback配送とcleanup failureの扱いが未完 |
| Unityプラグイン非依存 | ○ | Sample / UI testともUnity参照なし |
| Log.d網羅性 | — | Android専用規約のため対象外 |
| KDoc網羅性 | — | Android専用規約のため対象外 |

## 手動確認観点の充足

記号: ○ = UIテストまたは今回の実測で確認、△ = 実機・外部UI未確認または検証不十分、× = 契約違反を静的に確認。

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

| No | 観点 | 評価 | 備考 |
|---|---|---|---|
| 8.2-1 | Init -> external copy | △ | 外部操作未確認 |
| 8.2-2 | self copyの通知抑止 | △ | テスト成功だが負条件の観測期間なし |
| 8.2-3 | Uninit TRUE -> external copy | △ | 外部操作未確認 |
| 8.2-4 | Reserve -> external paste | △ | 外部操作未確認 |
| 8.2-5 | Reserve -> Word paste | △ | 外部操作未確認 |
| 8.2-6 | Reserve -> enumerate | ○ | UIテスト成功 |
| 8.2-7 | Reserve -> app exit -> paste | △ | 外部操作未確認 |
| 8.2-8 | Reserve -> external copy | △ | 外部操作未確認 |

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
| 8.4-1 | Initializeを2回 | ○ | 旧markerを除去して検証 |
| 8.4-2 | Request + Immediate Uninitialize | ○ | CANCELEDとFALSEをlogで確認 |
| 8.4-3 | ShuttingDownで通常操作拒否 | ○ | UIテスト成功 |
| 8.4-4 | ShuttingDownで通常Initialize拒否 | ○ | UIテスト成功 |
| 8.4-5 | Force Initialize | ○ | UIテスト成功 |
| 8.4-6 | drain後CanDestroy | ○ | UIテスト成功 |
| 8.4-7 | Uninitialize retry | ○ | UIテスト成功 |
| 8.4-8 | cleanup完了ログ | ○ | 成功ログを検証 |
| 8.4-9 | 再Initialize -> Copy | ○ | 同一プロセスで検証 |
| 8.4-10 | worker Reserve | ○ | WRONG_THREAD確認 |
| 8.4-11 | worker Uninit | ○ | WRONG_THREAD + Ready確認 |
| 8.4-12 | Back -> re-entry | △ | 旧token消去は確認。遅延配送の負条件は未保証 |
| 8.4-13 | request -> Back -> re-entry | × | 旧completionが新ページへ届くコード経路が残る |
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
| 配置済みMSIXの起動 | ○ | AUMIDから起動し33件成功 |
| Visual Studio Deploy + F5による手動確認 | △ | result上は未実施 |
| unpackaged history API | △ | 計画どおり未確認 |

## 総合評価

**要修正（重大）**

- ビルドとUIテスト33件は成功し、v1の多くの指摘は解消した。
- ただしv1 H1のrequest callback世代分離は完了しておらず、旧ページのcompletionを新ページへ配送できるため、8.4-13の契約違反が残る。
- 外部アプリ、Win+V、別デバイス、deferred renderingの実機確認は引き続きopenである。
