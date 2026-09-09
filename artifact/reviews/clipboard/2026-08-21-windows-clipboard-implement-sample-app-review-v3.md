# Windows Clipboard サンプルアプリ実装 再レビュー v3

## レビュー対象

- ブランチ: `feature/NTKIT-13`
- 対応コミット: `4393934ff91c923862815e9fe8ead4dd422c9aaf`
- 比較: `develop...HEAD`、およびレビュー v2 対応差分 `4393934f^...4393934f`
- 計画: `artifact/designs/clipboard/2026-07-31-windows-clipboard-sample-app-design-v5.md`
- 実装結果: `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md`
- 前回レビュー: `artifact/reviews/clipboard/2026-08-21-windows-clipboard-implement-sample-app-review-v2.md`
- 対象OS: Windows 11以降

## 検証結果

| 検証 | 結果 |
|---|---|
| `WindowsLibraryExample.vcxproj` Release / x64 Build | 成功。既存の `Microsoft.Windows.AI.Foundation.winmd` に関する `MSB3106` 警告2件のみ |
| `dotnet test ... --configuration Release --no-restore` | 33 passed / 0 failed、1分9秒 |
| テスト終了後の `WindowsLibraryExample` プロセス | 残存なし |
| `git diff --check 4393934f^ 4393934f`（対象ファイル） | 問題なし |

## レビュー概要

- request受付時に発行ページIDを記録し、completionをそのページだけへ配送する方式へ変更された。離脱後・再入場後に完了しても新ページへ流れないため、v2 H1は解消している。
- ライブイベントは発生時の表示ページへ配送され、再入場後のdeferred providerログを新ページへ表示する契約とも両立している。
- 負条件は3秒間のbounded pollingになり、瞬時検査の偽陽性を改善した。テスト専用遅延フックを追加しなかった判断は妥当で、必須対応とはしない。
- 通常終了経路は例外伝播を含め改善されたが、main window取得失敗経路だけはKill後の終了確認がない。

## 重大な問題（high）

なし。

## 改善提案（medium）

### M1. main window取得失敗時のプロセス終了を最後まで保証していない

- 該当: `windows/WindowsLibraryExampleUITest/Infra/FlaUiSession.cs:48`
- `LaunchStoreApp` 成功後にmain window取得が失敗すると `TryTerminate` が `Kill()` を呼ぶようになった点は改善されている。
- ただし `Kill()` 後の終了を待たず、Kill失敗も無条件に握り潰してから次のテストへ進む。`Process.Kill`相当は終了完了待ちではないため、v2 M1で求めたセットアップ失敗時のプロセス分離はまだ保証されない。
- `TryTerminate`でもbounded waitを行い、終了しなければ元のsetup例外にcleanup失敗を付加するか、明示的なcleanup例外として伝播させる。通常の `WaitForExit` と終了処理を共通化するとよい。

### M2. 実装結果のページ離脱時callback説明が旧実装のまま

- 該当: `artifact/results/clipboard/2026-08-20-windows-clipboard-implement-sample-app-result-v1.md:145`
- §2.4は「`OnNavigatedFrom`でhubをnull、`OnRequestCompleted`のunknown id分岐」と記載しているが、現在の主契約は `g_requestOwners[requestId] = m_pageId` と `g_activePageId` の照合である。
- §5.11には新方式が正しく記録されているため、§2.4も同じ説明へ更新し、最終状態の要約と対応履歴を一致させる。

## 軽微な指摘（low）

### L1. `StaysFalse` に `Dispose` のXMLコメントが付いている

- 該当: `windows/WindowsLibraryExampleUITest/Infra/FlaUiSession.cs:107`
- 「Closes the app and waits...」というsummary/remarksが `StaysFalse` の直前にあり、API内容と一致しない。`StaysFalse`用コメントへ差し替え、終了処理のコメントは `Dispose` の直前へ移す。

## v2指摘対応状況

| v2指摘 | 評価 | 再レビュー結果 |
|---|---|---|
| H1 request completionのページ所有 | ○ | 受付時のページIDへ固定し、完了時にactive pageと照合してowner情報を削除 |
| M1 終了不能がログのみ | △ | 通常Disposeは例外伝播。main window取得失敗経路はKill後の確認なし |
| M2 負条件が瞬時検査 | ○ | `StaysFalse` / `LogStaysWithout`で3秒間polling |
| M3 ファイル数12→14 | ○ | 14ファイルとTests 5ファイルを全列挙 |

## 計画書整合性チェック

| 項目 | 評価 | 根拠 |
|---|---|---|
| 全セクション・全ボタンの実装 | ○ | 48操作と導線を維持 |
| API呼び出し方針の一致 | ○ | request completionとライブイベントの配送先を分離し、ページ離脱契約を満たす |
| システム設定の正確性 | ○ | MSIX設定・既存solution構成に追加変更なし |
| 変更ファイル一覧とのdiff整合 | ○ | UIテスト14ファイルを正しく列挙 |
| 追加判断のresult記録 | △ | §5.11は正確だが§2.4に旧説明が残る |

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
| `common.md`準拠 | ○ | アプリ内完結の対象を独立UIテストで直列実行 |
| `windows.md`準拠 | △ | 33件成功、Adapter、bounded pollingは適合。setup失敗時cleanupのみ改善余地あり |
| Unityプラグイン非依存 | ○ | Sample / UI testともUnity参照なし |
| Log.d網羅性 | — | Android専用規約のため対象外 |
| KDoc網羅性 | — | Android専用規約のため対象外 |

## 手動確認観点の充足

記号: ○ = UIテストまたは今回の実測で確認、△ = 実機・外部UI未確認、× = 契約違反を確認。

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
| 8.2-2 | self copyの通知抑止 | ○ | 3秒間の負条件テスト成功 |
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
| 8.4-12 | Back -> re-entry | ○ | 旧tokenが3秒間現れないことを確認 |
| 8.4-13 | request -> Back -> re-entry | ○ | 所有ページ固定を静的確認し、旧request logの負条件テスト成功 |
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

**要修正（軽微）**

- v2の重大指摘は解消し、C++ビルド、UIテスト33件、通常終了時のプロセス分離は成立している。
- setup失敗時のKill後終了確認、実装結果の旧説明、XMLコメントの3点は修正推奨だが、通常機能の成立を妨げる問題ではない。
- 外部アプリ、Win+V、別デバイス、deferred renderingの実機確認は引き続きopenである。
