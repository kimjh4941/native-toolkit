# Windows Notification サンプルアプリ実装レビュー

## 基本情報

- 日付: 2026-05-31
- 対象OS: Windows（最小: Windows 11）
- 対象機能: notification
- ブランチ: `feature/NTKIT-9`
- レビュー対象: ローカル未コミット差分（`develop`/`main` との差分は未コミットのため `git diff` 相当を対象）
- 計画ファイル: `artifact/designs/notification/2026-05-31-windows-notification-sample-app-design-v2.md`
- 実装結果ファイル: `artifact/results/notification/2026-05-31-windows-notification-implement-sample-app-result-v1.md`
- 参照ルール: `agent-rules/coding-rules/common.md` / `agent-rules/coding-rules/windows.md`

---

## レビュー概要

- `MainWindow` を `Frame` シェル化し、`MainMenuPage`（メニューカード）→ `DialogPage` / `NotificationPage` の遷移を導入（macOS `MacLibraryExample` 構成準拠）。
- 既存 Dialog サンプルを `DialogPage` へ移設（ロジック無変更）。各ページに `Back` ボタン。
- `NotificationPage` を新規実装し、公開 Bridge API 12 関数すべてを UI 化（Init/Setting・Show×7・Schedule・Progress・Badge・Remove/Query）。
- コールバックは TU-static の転送ハブ（`std::function`）+ C 関数ポインタ thunk で受け、`DispatcherQueue().TryEnqueue` で UI スレッドへマーシャリング。
- Debug|x64 / Release|x64 ともビルド成功（result 記載）。

---

## 重大な問題（high）

- なし（コード上の修正必須欠陥は検出されず）。
- 【未実施・要検証 / high】toast activation（`Package.appxmanifest` の `ToastActivatorCLSID`）拡張は未追加。アプリ未起動時のアクティベーション経由コールバック（設計書 T-21）は本実装では未対応。result 4. に明記済みのため「既知の open 項目」として扱う（本レビューでのコード欠陥ではない）。

---

## 改善提案（medium）

- 計画 5.2 / 6.2 はコールバック転送ハブを **`App` 所有**（`App::OnNotificationInvoked`）と確定していたが、実装は **`NotificationPage.xaml.cpp` の TU-static `g_notificationHandler`** に変更。
  - サンプル用途として妥当かつ単純化されており、result 1.2 に逸脱理由（`produce<>` 未定義回避）とともに記録済み。指摘ではなく「計画逸脱の記録は適切」。ただし計画 4.2 で予定した `App.xaml.cpp` 変更が発生しなかった点は result の変更ファイル一覧（2.3）と整合している。
- 結果表示フォーマットの不統一（軽微）:
  - `DialogPage`: `✅\nShowAlertDialog Result: ...`（改行 + メソッド名 + Result）
  - `NotificationPage.ShowResult`: `✅ [method] errorCode=<n>`（1 行 + errorCode）
  - いずれも ✅/❌ ファミリで成功/失敗は一目判別可。計画 3.3 の `[method] errorCode=<n>` に準拠しており許容範囲だが、将来的に共通ヘルパー化すると保守性が上がる。
- `GetAllNotifications` / `RemoveByTag` / `RemoveAll` / `SetBadge*` は `EnsureInitialized()` ゲートを通さない。未初期化時は Bridge が `NOT_INITIALIZED(1)` を返し `❌` 表示になるため動作上の問題はないが、Show 系と挙動が非対称（要確認・設計判断）。

---

## 軽微な指摘（low）

- TAG 定義は `L"NotificationPage"` 等の単純クラス名。windows.md ログ規約は「クラスのフルネーム」を例示するが、当該規約の適用対象は `windows/WindowsLibrary/` 配下・Bridge C API であり、サンプルアプリは対象外。既存 `MainWindow` の `L"MainWindow"` パターンとも整合しており許容。
- `ShowResult` / `SetResultText` / `EnsureInitialized` などの内部 UI ユーティリティにはログなし。windows.md の除外（純粋 UI ユーティリティ・自明処理）に該当し問題なし。
- `NotificationPage.idl` / `MainMenuPage.idl` / `DialogPage.idl` を採用。計画 4.1 は「原則 `.idl` なし」だが、WinUImg 3 / C++/WinRT のページ型解決のため採用し result 1.2 に記録済み。逸脱記録あり、許容。
- `ShowWithProgress` の payload は `value:0.3`、`UpdateProgress` は `0.6` 固定。デモとして妥当（事前 Show が前提である旨は計画どおり）。

---

## 計画書整合性チェック

- 全セクション・全ボタンの実装: ○（Init/Setting・Show×7・Schedule・Progress・Badge×3・Remove/Query×4 すべて実装。公開 API 12 関数を全カバー）
- API 呼び出し方針の一致: ○（init は packaged パス `TRUE,nullptr,nullptr`、各 payload・引数が計画 6.1 と一致）
- システム設定（Manifest / toast activation 等）の正確性: △（toast activation 拡張は未実装。計画上「要検証」のため逸脱ではないが open）
- 変更ファイル一覧との diff 整合: ○（新規3ページ idl/xaml/h/cpp・MainWindow×3・pch.h・vcxproj が diff と一致）
- 計画書との差分（追加判断）の result ファイルへの記録: ○（ハブの所在変更・make_weak・idl 採用を result 1.2 に記録）

---

## サンプルアプリパターン適合チェック

- メニュー導線（MainMenu / Frame.Navigate）: ○（`MainMenuPage` メニューカード → `Frame.Navigate`、`Back` ボタンで `GoBack`）
- 画面構成パターン（タイトル / ResultTextBlock / ScrollViewer / セクションヘッダ / フル幅ボタン）: ○
- 成功/失敗表示フォーマット（✅ / ❌）: ○（Dialog と表記体裁に差はあるが ✅/❌ で統一）
- 共通 UI 部品の利用（`ResultTextBlock` + `SetResultText` パターン踏襲）: ○

---

## プロジェクトルール適合チェック

- common.md 準拠: ○（Bridge は薄く、UI 反映はメインスレッド `DispatcherQueue`、コールバック所有は単一ハブ）
- windows.md 準拠: ○（コメント・UI テキストは英語、`wchar_t`/`std::wstring`、out 引数 `DWORD* pError` 利用。※同ルールの一次適用対象はライブラリ側）
- ログ（DLog/DFLog）網羅性: ○（全イベントハンドラ・thunk の先頭1行にログ。内部 UI ユーティリティは除外規定に合致）
- コメント（英語）/ 公開 API Doxygen: ○（サンプルは Bridge 公開 API ではないため Doxygen 必須対象外。コメントは英語）

---

## 手動確認観点の充足（UI 実装観点で評価。実機表示は要 VS 実行）

- メニューカード→各画面遷移・Back 復帰: ○（UI 実装あり）
- 各 Show で Toast 表示: △（UI/呼出は実装。実表示は実機未確認）
- ボタン押下で `argsJson`（action）反映: ○（ハブ→DispatcherQueue で反映実装）／実表示は実機未確認
- 入力付き通知の入力/選択値が `argsJson` に含まれる: △（payload 実装。実機未確認）
- 画像付き通知（`ms-appx:///Assets/StoreLogo.png`）: ○（既存アセット流用、実機未確認）
- 進捗表示→`UpdateProgress` / 未表示で `PROGRESS_NOT_FOUND(4)`: ○（実装あり、実機未確認）
- `Schedule(+1m)` / `CancelScheduled`: ○（+60s Unix ms 計算・tag 一致、実機未確認）
- `SetBadge(5)` / Glyph / Clear: ○
- `GetAll`（id/tag/group・4096 境界）/ `RemoveById` / `ByTag` / `All`: ○（4096 固定長 + bufferSize 渡し、id 保持→RemoveById 流用）
- `GetSetting`（-1 異常含む）: ○（ラベル化、`-1`→`Error(-1)`）
- 起動時 `RPC_E_CHANGED_MODE` 非発生: △（ライブラリ側修正済み。回帰は実機未確認）
- アプリ未起動時アクティベーションコールバック（T-21）: ×（未実装・要検証）
- 最小 Windows 11 と実 MinVersion(10.0.17763.0): ×（未対応・要判断）

---

## 総合評価

- **要修正（軽微）** — コード上の重大欠陥はなく、計画整合・パターン適合・ルール準拠は良好。残課題は (1) toast activation 拡張の要否検証（high・open）、(2) 実機での通知表示/コールバック確認、(3) MinVersion 整合方針の判断。いずれも result に open 項目として記録済み。コード修正としては結果表示フォーマットの共通化・未初期化ゲートの統一が任意の改善余地。
