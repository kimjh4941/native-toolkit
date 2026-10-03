# 段階 0c 結果: Dialog / Notification / Clipboard の UI テスト

- 実施日: 2026-09-19
- 対象: `artifact/topics/windows-architecture/README.md` の段階 0c、`designs/2026-09-19-windows-architecture-ui-test-design.md` の 4 章、6 章、7 章
- ブランチ: `feature/NTKIT-16`
- コミット: `b62cf9fe`（事前確認）、`aa958eda`（Dialog）、`310d01c4`（Notification）、`c5d2b1bd`（CU-02 の取りやめ）、`30173e15`（Clipboard）、このまとめ

## 1. 結果

UI テストは全体で 94 件。**93 件が成功し、1 件（履歴の `Clear`）は既定どおり実行されずに終わった**（約 8 分）。

| カテゴリ | クラス | 件数 | 設計書 |
|---|---|---|---|
| `Dialog` | `DialogTests` | 13 | 6.1（D-01 〜 D-13） |
| `Notification` | `NotificationTests` | 21 | 6.2（N-01 〜 N-20、N-23） |
| `NotificationBanner` | `NotificationBannerTests` | 2 | 6.2（N-21、N-22） |
| `Clipboard` | 既存の 4 クラス | 31 | 6.3 |
| `Clipboard` | `ClipboardInteropTests` | 11 | 付録 B の 8.1 |
| `Clipboard` | `ClipboardExternalChangeTests` | 5 | 付録 B の 8.2 |
| `ClipboardHistory` | `ClipboardHistoryTests` | 8 | 付録 B の 8.3（`Clear` 以外） |
| `ClipboardHistoryDestructive` | `ClipboardHistoryDestructiveTests` | 1 | 付録 B の 8.3 の `Clear`。環境変数 `NTK_UITEST_DESTRUCTIVE=1` が無いと `Inconclusive`（U-6） |
| （無し） | `SmokeTests` | 2 | 既存 |

テストが切り替えた OS の設定（集中モード、クリップボードの履歴、アプリの通知）は、どれも元の値に戻り、記録のファイルも消えていることを確かめた。

computer use の確認手順書は `windows/WindowsLibraryExampleUITest/ComputerUse/CU-01-hero-image.md` の 1 件。実行は段階 0d で、スクリプトの後に行う。

## 2. テスト基盤（`Infra`）に足したもの

設計書 4 章の一覧のとおり。FlaUI を使うのは `Infra` の中だけで、テストとページオブジェクトは FlaUI の型に依存していない。

| ファイル | 役割 |
|---|---|
| `UiElement.cs`（`Click`）、`IUiDialog.cs` | ダイアログを開くボタンのマウスクリック、モーダルダイアログの操作（3.1、3.2） |
| `INotificationCenter.cs`、`IBanners.cs`、`ITaskbarBadge.cs`、`FlaUiNotifications.cs` | 通知センター、バナー、バッジ（3.3 〜 3.5） |
| `IOsSettings.cs`、`FlaUiOsSettings.cs` | OS の設定の切り替えと記録、復元（3.6） |
| `IExternalClipboard.cs`、`Win32ExternalClipboard.cs` | 外部アプリとしてのクリップボードの読み書き（3.7） |
| `TestRunHooks.cs` | 実行の最初に、前回残った設定の復元と、利用者のクリップボードの文字列の保存。最後にその文字列を戻す（3.6、3.8） |
| `Native.cs` | Win32 の宣言 |
| `AppIdentity.cs` | サンプルの表示名と AUMID |

## 3. 段階 0c で分かったこと

設計書にはすでに反映した。

| 分かったこと | 対処 | 設計書 |
|---|---|---|
| ダイアログを開くボタンを Invoke で押すと、以後の UI Automation の呼び出しがすべて時間切れになる | マウスクリックで押す。位置が動かなくなるのを待ってから | 3.1 |
| バッジのグリフは名前がアイコン用フォントの文字 1 つで、alert は `U+EDAD`。段階 0a では空に見えていた | FlaUI で文字コードを確かめる。computer use の CU-02 は取りやめた | 3.5、U-7。段階 0a の結果の 9 章 |
| 設定ページは読み込みが終わるまでアプリの通知のスイッチを「オフ」と表示する。バナーのテストの後に N-20 を実行すると、これを「既にオフ」と読み違えた | 「オン」と表示されるまで待ってから切り替える。切り替えた状態が 2 秒保たれることを確かめる。`GetSetting` は期待する値になるまで押し直す | 3.6 |
| 設定アプリが別の仮想デスクトップで開いていると、UI Automation から操作できない | テストの前に設定アプリを閉じる | 3.6、U-5 |
| クリップボードの履歴を無効にすると、約 0.5 秒後に Windows がクリップボードを空にする。直後にテストが書き込んだ内容が消えた | 切り替えた後、クリップボードの変更の番号が変わり、500 ms 変わらなくなるまで待つ | 3.6、付録 C |
| 履歴の結果の表示には、利用者の履歴の文字列が含まれうる | 失敗のメッセージやログに出さない（`ClipboardPage.WaitForRedacted`） | 3.8 |
| SENSITIVE のコピーは、Win+V の画面ではなく、履歴の追加のログと GetHistory で確かめられる | 付録 B の見込み（Win+V の画面を読む）を置き換えた | 付録 B |
| 履歴の `Clear` をカテゴリだけで除外すると、フィルタを付けない `dotnet test` で利用者の履歴が消える | 環境変数で明示したときだけ実行する | 8 章、U-6 |
| ヒーロー画像は通知の幅に拡大され、上半分だけが見える（通知の項目 334×295 のうち画像 334×180） | CU-01 の合格の条件を実際の見え方で書いた | 7 章 |

## 4. 削除したもの

調査用のコード `windows/WindowsLibraryExampleUITest/Spike/`（コミットしていない）を削除した。結果は段階 0a の結果、段階 0b の結果、設計書の付録 A と付録 C、本書に書き写してある。

| ファイル | 調べたこと |
|---|---|
| `NotificationSpike.cs` | 通知センター、バナー、バッジを FlaUI で読めるか（段階 0a） |
| `AutomationIdCheck.cs` | 段階 0b の AutomationId と `Schedule (+5s)` |
| `DialogSpike.cs` | モーダルダイアログの操作（付録 A） |
| `SettingsSpike.cs` | 履歴とアプリの通知の切り替え（付録 C） |
| `ExternalClipboardSpike.cs` | 外部アプリとしての読み書き（付録 C） |
| `BadgeGlyphCheck.cs` | バッジのグリフの文字コード（U-7） |
| `HistoryOffSpike.cs` | 履歴を無効にした直後のクリップボード |
| `HeroImageCapture.cs` | ヒーロー画像の見え方（CU-01） |

## 5. 段階 0d に持ち越すこと

- 段階 0b の結果の 4 章（画面の消灯とスリープの抑止、画面がロックされていたら止める）
- CU-01 を初めて実行し、スクリーンショットを `ComputerUse/evidence/CU-01/` に残す
- テストの件数と所要時間を、スクリプトから実行した結果として記録する（段階 1 〜 6 の判定の基準）
