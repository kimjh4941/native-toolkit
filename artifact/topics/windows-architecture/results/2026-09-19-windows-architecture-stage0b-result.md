# 段階 0b 結果: サンプルアプリへの AutomationId の追加

- 実施日: 2026-09-19
- 対象: `artifact/topics/windows-architecture/README.md` の段階 0b、`designs/2026-09-19-windows-architecture-ui-test-design.md` の 5 章
- ブランチ: `feature/NTKIT-16`

## 1. 変更したこと

| ファイル | 変更 |
|---|---|
| `windows/WindowsLibraryExample/DialogPage.xaml` | 6 つのボタンに AutomationId を付けた（`ShowAlertDialog` など。ハンドラ名から `Button_Click` を除いたもの） |
| `windows/WindowsLibraryExample/NotificationPage.xaml` | 21 のボタンに AutomationId を付けた（ハンドラ名から `_Click` を除いたもの）。`Schedule (+5s)` ボタン（`ScheduleSoon`）を `Schedule (+1m)` の直後に足した |
| `windows/WindowsLibraryExample/NotificationPage.xaml.h` | `ScheduleSoon_Click` の宣言を足した |
| `windows/WindowsLibraryExample/NotificationPage.xaml.cpp` | `ScheduleSoon_Click` を足した。`Schedule_Click` と同じ書き方で、予約時刻を 5 秒後、本文を `Fires in ~5 seconds` にした。タイトル（`Scheduled`）とタグ（`scheduled`）は同じなので、`CancelScheduled` で取り消せる |

`ResultTextBlock` と `BackButton` は `x:Name` がそのまま AutomationId として見えるので変えていない（設計書 5.1 のとおり）。

## 2. 確かめたこと

| 確認 | 結果 |
|---|---|
| Dialog 画面の AutomationId | 8 / 8（ボタン 6、`ResultTextBlock`、`BackButton`） |
| Notification 画面の AutomationId | 24 / 24（ボタン 22、`ResultTextBlock`、`BackButton`） |
| `Schedule (+5s)` | 予約の直後は `GetAllNotifications` が 0 件、8 秒後に `count=1` |
| 既存の UI テスト（Clipboard 31 件、スモーク 2 件） | 33 / 33 成功（2 分 12 秒） |

AutomationId と `Schedule (+5s)` の確認は、調査用のテスト（`windows/WindowsLibraryExampleUITest/Spike/AutomationIdCheck.cs`。コミットしない）で行った。段階 0c の正式なテストが同じ範囲を確かめるので、段階 0c で削除する。

## 3. サンプルの配置の方法

MSBuild でビルドしただけでは、登録されている AppX のフォルダ（`x64\Release\WindowsLibraryExample\AppX`）は更新されない。Visual Studio の「配置」は、ビルドの出力にある `WindowsLibraryExample.build.appxrecipe` の一覧（コピー元とコピー先の組）に従って AppX のフォルダへコピーし、登録している。

今回は同じことを PowerShell で行った。段階 0d の `scripts/test_windows.ps1` に組み込む。

1. `MSBuild WindowsLibraryExample.sln -p:Configuration=Release -p:Platform=x64`
2. `.appxrecipe` の `AppxPackagedFile` と `AppXManifest` を読み、それぞれ `Include` から AppX のフォルダの `PackagePath` へコピーする（15 件のうち 13 件。2 件は元から AppX のフォルダの中にある）
3. `Add-AppxPackage -Register <AppX>\AppxManifest.xml -ForceApplicationShutdown`

XAML をコンパイルした `.xbf` は一覧に無いが、WinUI 3 では `resources.pri` に埋め込まれるので、`resources.pri` のコピーで反映される。

## 4. 段階 0d に持ち越すこと

- **テストの実行中は、画面の消灯とスリープを抑える。** 画面がロックされると、クリックやキー入力がアプリに届かず UI テストが失敗する。`SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED)` を使えば、電源設定を変えずに実行中だけ抑えられる。PowerShell 5.1 では `0x80000003` が負の数として解釈されて呼び出しに失敗したので、`[Convert]::ToUInt32('80000003', 16)` のように書く（今回の実行では抑止が効いていなかったが、2 分で終わり画面は消えなかった）
- 開始時に画面がロックされていたら、分かりやすいメッセージで止める
