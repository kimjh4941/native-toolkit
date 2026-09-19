# レビュー結果

- 日付: 2026-05-31
- 対象ファイル: artifact/designs/notification/2026-05-31-windows-notification-sample-app-design-v1.md
- 機能名: notification
- 対象 OS: Windows（最小 Windows 11）
- ドキュメント種別: sample-app-design

---

## 強み

- 設計書（design-v2）・実装結果（result-v1）の公開API 12関数 + `NotificationInvokedCallback`、エラーコード体系 0〜7、`getNotificationSetting` の独立体系（0〜4）を前提情報に正確に整理し、`setBadge value<-6 → INVALID_PARAMETER(7)` 等の実装差分とも整合している。
- 実在サンプルが MFC ではなく WinUI 3 / C++/WinRT であることを正しく把握し、macOS の NavigationStack + menuCard 体験を `Frame` + メニューカードで再現する方針が、既存 `SetResultText`・✅/❌・`DialogButtonStyle` 再利用と矛盾なく具体的。
- WinUI 3 固有の難所（C 関数ポインタのコールバック → 静的イベント/弱参照 → `DispatcherQueue().TryEnqueue` で UI スレッド反映）を明示し、`RPC_E_CHANGED_MODE` 回帰確認も手動確認に取り込んでいる。
- ライブラリ側バリデーションを意図的に踏むデモ、`PROGRESS_NOT_FOUND(4)` の事前条件まで設計され、手動確認とエラーコードの対応付けが具体的。

## 改善点

### 高優先度

- **[3.1 / 6.1] `removeNotificationById(id)` が全欠落**
  - 公開API 12関数のうち ID 指定削除がUI・実装詳細・手動確認のいずれにも登場しない（Remove/Query は RemoveByTag/RemoveAll/GetAll のみ）。
  - 改善案: Remove/Query に `RemoveById` ボタンを追加し、`GetAllNotifications` が返す id を流用して `removeNotificationById(id,&err)` を呼ぶデモ + 手動確認観点を追加。
- **[1.4 / 4.2] Package.appxmanifest の toast activation 拡張が非言及**
  - パッケージ済みでもアプリ未起動→COM アクティベーション起動（設計書 T-21）でコールバックを受けるには、appxmanifest に `windows.toastNotificationActivation`（ToastActivatorCLSID）登録が必要となり得るが、実マニフェストに当該拡張がなく、変更ファイル一覧にも appxmanifest がない。
  - 改善案: 変更ファイル一覧に Package.appxmanifest を追加し、toast activation COM 拡張の要否・内容を明記（最低限 1.4 に要検証として立てる）。

### 中優先度

- **[基本情報 / appxmanifest] 最小 Windows 11 と実 MinVersion(10.0.17763.0) の不一致**
  - 計画は最小 Windows 11 前提だが、実マニフェストの TargetDeviceFamily MinVersion は Windows 10 1809。OS 前提とビルド/配布設定の齟齬に未言及。
  - 改善案: MinVersion 引き上げの要否を appxmanifest 変更として明記、または下位OSでも起動する旨を注記して前提を明確化。
- **[7 手動確認観点] エラー契約の確認漏れ**
  - `getNotificationSetting` のエラー時 -1 返却、`getAllNotifications` のバッファ不足時挙動（4096 固定長境界）、`HRESULT_FAILURE(5)` / `BADGE_FAILED(6)`（設計書 T-28/T-29 相当）の確認観点がない。
  - 改善案: 上記3点を手動確認観点に追加し、設計書 T-01〜T-29 とのトレーサビリティを取る。
- **[4.2 / 6.2] コールバック橋渡しのライフサイクル未設計**
  - `static OnNotificationInvoked` から現在の `NotificationPage` への到達手段（静的イベント/std::function/weak_ref）が未確定。ページ離脱後にコールバックが来た場合の購読解除・null安全が未設計（「必要に応じて」のまま）。
  - 改善案: 受け皿の所有者（App か NotificationPage）と購読/解除ライフサイクル、ページ非表示時の argsJson 取り扱いを確定。

### 低優先度

- **[4.1] 各ページの .idl 要否が「VS が自動追加」依存**
  - ナビゲーション専用ページは idl 無し（x:Class 直結）も選択肢。idl を付ける場合は runtimeclass 宣言・vcxproj の `<Page>/<Midl>/DependentUpon` 登録が必須で、`Frame.Navigate(xaml_typename)` の型解決にも影響。
  - 改善案: 各ページの idl 要否を判断基準付きで明記し、vcxproj 登録項目を具体化。
- **[6.1] 通知用画像アセット（Assets）の新規追加が未計上**
  - `ms-appx:///Assets/...png` を使うが、同梱画像の追加が変更ファイル一覧にない。
  - 改善案: Assets 配下の画像追加を計上、または既存 StoreLogo 等の流用を明記。

## 不足項目

- `removeNotificationById(id)` の UI・実装・手動確認（公開API 12関数中1関数が未カバー）
- Package.appxmanifest の toast activation（COM/CLSID）拡張登録の要否と変更ファイル計上
- `getNotificationSetting` のエラー時 -1 返却の手動確認観点
- `getAllNotifications` のバッファ境界（4096 固定長）超過時の挙動確認観点
- `HRESULT_FAILURE(5)` / `BADGE_FAILED(6)` の確認観点（環境依存注記付き）
- 通知用画像アセット（Assets）の新規追加計上
- 最小 Windows 11 方針と実 appxmanifest MinVersion(10.0.17763.0) の整合方針

## 総合評価

全体として完成度は高く、design-v2 / result-v1 の公開API・エラー契約・JSONペイロード仕様を正確に踏まえ、実在サンプルが WinUI 3 / C++/WinRT である点や `RPC_E_CHANGED_MODE` 回帰、`DispatcherQueue` マーシャリング、C 関数ポインタからの UI 橋渡しといった固有の難所まで具体的に織り込めている。macOS（MacLibraryExample）の NavigationStack + menuCard 構成を `Frame` + メニューカードで再現し、既存 DialogManager サンプルの DialogPage 移設・`ResultTextBlock`/✅❌/`DialogButtonStyle` 再利用も妥当。一方で網羅性に実害のある穴が残る。最大の問題は (a) `removeNotificationById` が UI・実装・確認のすべてから欠落し公開API 12関数中1つが未カバー、(b) パッケージ済みアプリでのコールバック受信に必要となり得る appxmanifest の toast activation 拡張が実マニフェストに存在せず計画でも非言及（特に T-21 のアクティベーション経由コールバックが届かないリスク）。加えて GetSetting の -1・GetAll のバッファ境界・HRESULT_FAILURE/BADGE_FAILED の確認漏れ、最小OS方針と実 MinVersion の不一致、画像アセット計上漏れがある。high 2 件・medium 3 件を中心に修正すれば着手可能なレベルであり、特に `removeNotificationById` の追加と appxmanifest 方針の確定を最優先で反映することを推奨する。
