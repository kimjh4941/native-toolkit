# Windows Notification サンプルアプリ実装結果

## 基本情報

- 日付: 2026-05-31
- 対象OS: Windows（最小: Windows 11）
- 対象機能: notification
- 計画ファイル: `artifact/designs/notification/2026-05-31-windows-notification-sample-app-design-v2.md`
- 対象サンプルアプリ: `windows/WindowsLibraryExample`（WinUI 3 / C++/WinRT）

---

## 1. 実装サマリー

### 1.1 計画書由来の実装

- **メインメニュー（メニューカード）→ サンプル画面**の導線を導入（macOS `MacLibraryExample` 構成に整合）。`MainWindow` を `Frame` シェル化し、初期ページ `MainMenuPage` へ遷移。
- `MainMenuPage`: タイトル `Native Toolkit Windows Example` + メニューカード（`Dialog Example` / `Notification Example`）→ `Frame.Navigate`（文字列 `TypeName` 経由）。
- 既存 Dialog サンプルを **`DialogPage`** へ移設（ボタン・ハンドラ・`SetResultText` をそのまま移動。機能は無変更）。各ページ先頭に `Back` ボタン（`Frame().GoBack()`）。
- **`NotificationPage`** を新規実装。セクション: Init/Setting・Show（7種）・Schedule・Progress・Badge・Remove/Query。
  - 公開API 12関数すべてを UI から呼び出し（init/uninit/show/schedule/cancelScheduled/updateProgress/setBadge/removeById/removeByTag/removeAll/getAll/getSetting）。
  - JSON ペイロードはハードコード（UI 入力バリデーション不要）。
  - 結果表示は `pError == 0` を ✅、`1〜7` を ❌ とし `[method] errorCode=<n>`。`GetSetting` は状態ラベル（`-1` は `Error(-1)`）。
  - ログは **`DLog`/`DFLog`**（`common.h`）に統一。
- コールバック（`NotificationInvokedCallback`）: 翻訳単位 static の転送ハブ（`std::function`）に C 関数ポインタ thunk を渡し、`OnNavigatedTo` で登録・`OnNavigatedFrom` で解除。UI 反映は `DispatcherQueue().TryEnqueue` でメインスレッドへマーシャリング。
- 画像は `ms-appx:///Assets/StoreLogo.png`（既存アセット流用、新規追加なし）。

### 1.2 実装時の追加判断

- コールバックの UI 反映は、計画の「App 所有ハブ + ページの get_self」案から **NotificationPage 内 static ハブ + `ResultTextBlock` の weak 参照（`winrt::make_weak`）** に変更。
  - 理由: ページ実装型に対する `get_weak()`/`get_self()` が C++/WinRT の `produce<NotificationPage, NotificationPage>` 未定義（base.h C2079）を誘発したため。TextBlock の weak 参照で UI を直接更新する方式に変更し回避。
- ページ遷移は `winrt::Windows::UI::Xaml::Interop::TypeName`（cppwinrt 提供）+ 文字列クラス名で実装（同一プロジェクト型の projection 依存を避け堅牢化）。
- `winrt/Windows.Data.Json.h` は `pch.h` に集約（GetAll の id パース用）。
- 各ページは `.idl`（runtimeclass）を付与（XAML ページの型システム解決のため。原則なし方針だが WinUI 3 / C++/WinRT のページは XAML コンパイラ連携上 idl を採用）。

### 1.3 レビュー反映（review-v1 / 2026-05-31）

- レビュー指摘（medium: 未初期化ゲートの非対称）を反映し、Manager を要する操作（`GetAllNotifications` / `RemoveById` / `RemoveByTag` / `RemoveAll` / `CancelScheduled` / `SetBadge` / `SetBadgeGlyph` / `ClearBadge`）にも `EnsureInitialized()` ゲートを追加。Show 系と挙動を統一し、未初期化時は「Tap InitializeManager first」を表示（従来は `NOT_INITIALIZED(1)` の `❌` 表示）。
- toast activation 拡張（T-21）・`MinVersion` 整合は実機検証/設計判断を要する open 項目のため本修正では未変更（下記 4. を維持）。
- `DialogPage` の結果表示体裁は計画で「移設・無変更」と確定済みのため変更せず。
- 反映後、Debug|x64 で再ビルド成功（EXIT 0。警告のみ、エラーなし）。
- レビュー結果: `artifact/reviews/notification/2026-05-31-windows-notification-implement-sample-app-review-v1.md`

---

## 2. 変更ファイル

### 2.1 新規作成

- `windows/WindowsLibraryExample/MainMenuPage.{idl,xaml,xaml.h,xaml.cpp}`
- `windows/WindowsLibraryExample/DialogPage.{idl,xaml,xaml.h,xaml.cpp}`
- `windows/WindowsLibraryExample/NotificationPage.{idl,xaml,xaml.h,xaml.cpp}`

### 2.2 既存変更

- `MainWindow.xaml` / `.xaml.h` / `.xaml.cpp` — `Frame` シェル化 + `MainMenuPage` へ遷移（Dialog 内容は `DialogPage` へ移設）。
- `pch.h` — `winrt/Windows.Data.Json.h` を追加。
- `WindowsLibraryExample.vcxproj` — 新規3ページの `<Page>`/`<Midl>`/`<ClInclude>`/`<ClCompile>`（`DependentUpon` 付き）を登録。

### 2.3 非変更

- `WindowsLibrary`（ライブラリ本体）・Bridge API・`Package.appxmanifest`（toast activation は本実装では未追加。下記 4. 要検証）。

---

## 3. ビルド/実行結果

- 実行コマンド: MSBuild `WindowsLibraryExample.vcxproj`（Debug|x64 / Release|x64）
- 結果: **成功**
  - Debug|x64 → `WindowsLibraryExample.exe` 生成（EXIT 0）
  - Release|x64 → `WindowsLibraryExample.exe` 生成（EXIT 0）
  - 依存 `WindowsLibrary.dll` も同時生成（AppSDK 1.7 構成）
- 実行（起動・通知表示）の確認は VS からの実機実行が必要（下記 5.）。

---

## 4. 手動確認観点 / 未実施項目（要検証含む）

| 観点 | 状態 | 備考 |
|-----|------|------|
| メニューカード→各画面遷移・Back でメインメニュー復帰 | 実機未確認 | 要 VS 実行 |
| `InitializeManager` 後の各 Show で Toast 表示 | 実機未確認 | 要 VS 実行 |
| ボタン付き通知のボタン押下で `argsJson`（action）反映 | 実機未確認 | アプリ起動中。`OnNavigatedTo` のハブで反映 |
| 入力付き通知（textBox/comboBox）の入力/選択値が `argsJson` に含まれる | 実機未確認 | 要 VS 実行 |
| 画像付き通知（`ms-appx:///Assets/StoreLogo.png`）表示 | 実機未確認 | 要 VS 実行 |
| 進捗表示 → `UpdateProgress` で更新 / 未表示で `PROGRESS_NOT_FOUND(4)` | 実機未確認 | 要 VS 実行 |
| `Schedule(+1m)` 着信 / `CancelScheduled` で抑止 | 実機未確認 | 要 VS 実行 |
| `SetBadge(5)` / `ClearBadge` | 実機未確認 | 要 VS 実行 |
| `GetAllNotifications`（id/tag/group・4096境界） / `RemoveById` / `RemoveByTag` / `RemoveAll` | 実機未確認 | 要 VS 実行 |
| `GetSetting`（`-1` 異常含む） | 実機未確認 | 要 VS 実行 |
| 起動時に `RPC_E_CHANGED_MODE` が出ず正常起動 | 実機未確認 | ライブラリ側修正済みの回帰確認 |
| **【要検証 / high】アプリ未起動時のアクティベーション経由コールバック**（T-21） | 未実施 | `Package.appxmanifest` の toast activation（`ToastActivatorCLSID`）拡張が必要か要検証。本実装は未追加。アプリ起動中のフォアグラウンドコールバックのみ対象 |
| 最小 Windows 11 と実 `MinVersion`(10.0.17763.0) | 未対応 | 引き上げ要否は要判断（本実装では未変更） |

- `INVALID_PAYLOAD(3)` / `INVALID_PARAMETER(7)` / `HRESULT_FAILURE(5)` / `BADGE_FAILED(6)` の異常系は WindowsLibrary 単体テストでカバー済み（サンプルの手動確認対象外）。

### 共通実装パターンの維持/拡張（Windows ⇔ macOS）

- 維持: タイトル+結果表示（✅/❌）、機能カテゴリ別ボタン群、メインスレッド反映。
- 拡張: macOS `NavigationStack` + `menuCard` を WinUI の `Frame` + メニューカード + 明示 `Back` ボタンで再現。

---

## 5. 実機確認の必要性

- 本サンプルはパッケージ済み（MSIX）アプリのため、通知表示・コールバック・スケジュール・バッジの確認は **VS から Release|x64 を実機実行**して行う必要がある（CLI 非対話では通知 UI を確認できない）。
- ビルドは Debug/Release ともに成功しており、コンパイル・リンク・XAML/ページ構成・Bridge 呼び出しの整合は確認済み。

---

## 6. ステップ8 実行確認

- 提示文: 「このサンプル実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-sample-app の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
