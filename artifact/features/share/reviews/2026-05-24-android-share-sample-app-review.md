# レビュー結果

- 日付: 2026-05-24
- 対象ファイル: artifact/designs/share/2026-05-24-android-share-implement-sample-app-v1.md
- 機能名: android-share
- 対象 OS: Android

---

## 強み

- NotificationSampleScreen の UI パターン（statusText 1行表示、LazyColumn + Scrollbar、Back+タイトル、絵文字プレフィックス）を踏襲しており Android サンプルアプリの共通実装パターンが維持されている
- 全 8 種類のシェア操作（shareText / shareImage / shareImages / shareFile / shareFiles / registerDirectShareTarget / removeDirectShareTargets / shareWithCallback）を網羅しており、設計書の公開 API と対応している
- FileProvider 設定（AndroidManifest provider 宣言、file_paths.xml の files-path / cache-path / external-files-path 網羅、ProGuard keep ルール）が設計書 Task 5 の定義に正確に一致している
- コーディングルール（Log.d 先頭挿入、TAG companion object、KDoc）が明示されており android.md 準拠の指示が含まれる
- ShareDomainError と Exception を二段でキャッチするエラーハンドリング方針が明示されている
- ファイル生成（cacheDir への PNG/テキスト書き込み）を IO ディスパッチャに分離する coroutine 方針が明示されている

## 改善点

### 高優先度

**ShareTextUseCase のシグネチャ確認不足**
- 対象セクション: `ShareSampleScreen.kt / 依存 import`
- 問題点: `shareUseCases.shareText(ShareContent(...), "[]")` の呼び出しが UseCase の実シグネチャ（chooserActionsJson 引数）と一致するか計画書内で確認・明記されていない
- 改善提案: 実装結果 v1 の ShareUseCases.shareText シグネチャを確認し、呼び出し方針を計画書内に明記する

**ファイル生成と Share 呼び出しのスレッド境界が曖昧**
- 対象セクション: `セクション 2〜5 ファイル生成`
- 問題点: `lifecycleScope.launch(Dispatchers.IO)` でファイル生成 → share 呼び出しまで IO スレッドで実行する記述だと、`startActivity` が UI スレッドを要求するためクラッシュリスクがある
- 改善提案: ファイル生成（IO）→ `withContext(Dispatchers.Main)` で `shareUseCases.shareXxx()` + `statusText` 更新、の擬似コードを各セクションに追加する

### 中優先度

**MainRouter.kt 変更点に `onSelectShareTest` 渡しが未記載**
- 対象セクション: `5. MainMenuScreen.kt（変更）`
- 問題点: MainMenuScreen のシグネチャ変更に伴い、MainRouter.kt の呼び出し側（`MainMenuScreen(onSelectShareTest = { ... })`）の修正が変更点として漏れている
- 改善提案: MainRouter.kt 変更点 3 として `onSelectShareTest` パラメータ追加を明示する

**入力バリデーション方針が未明示**
- 対象セクション: `6. ShareSampleScreen.kt`
- 問題点: サンプルが固定値のみ使用する設計なのかが明記されていない
- 改善提案: 「サンプル画面は固定値で各 API を呼び出す。空文字/不正 MIME 等のエラー系は domain エラー catch によって statusText に表示する形で確認する」と明記する

**`shareWithCallback` の onResult スレッドガードが不正確**
- 対象セクション: `セクション 7: Share with Callback`
- 問題点: onResult ラムダ内では suspend 関数を呼べないため `withContext(Dispatchers.Main)` は使えない
- 改善提案: `activity.runOnUiThread { statusText = ... }` または `lifecycleScope.launch(Dispatchers.Main.immediate) { ... }` に変更する

**手動確認観点が不足**
- 対象セクション: `完了条件`
- 問題点: URL シェア、複数画像/ファイルシェア、Direct Share 削除後の確認、コールバックキャンセル確認、BroadcastReceiver リークなしが欠落
- 改善提案: 上記項目を完了条件に追加する

### 低優先度

- `RegisterDirectShareTarget` の UseCase シグネチャ（target, iconBytes）を実装結果との対応付きで明示する
- URL シェア確認用ボタン（`text = "https://example.com"`）の追加
- ChooserAction（API 34+）の手動確認方法または「Unity Bridge 経由で別途確認」旨の明記
- `rememberCoroutineScope()` vs `activity.lifecycleScope` の選択理由を一行記載する
- `android.support.FILE_PROVIDER_PATHS` は AndroidX でも変更しない旨を注意事項に補足

## 不足項目

- ShareUseCases の各メソッドの実シグネチャ（実装結果 v1 を反映した chooserActionsJson 引数含む）と呼び出しサンプルの対応表
- URL シェア確認用ボタン
- ChooserAction（API 34+）確認用ボタンまたは未確認である旨の明記
- BroadcastReceiver リークなし（ワンショット解除）の手動確認手順
- コールバックキャンセル時の手動確認手順（Sharesheet を外タップで閉じて Cancelled 表示）
- Direct Share 削除後に Sharesheet からショートカットが消えることの手動確認
- MainRouter.kt 側で MainMenuScreen 呼び出しに `onSelectShareTest` を渡す変更の明記
- onResult コールバック内でのスレッド切り替えコード（runOnUiThread 等）の正確な記述
- ファイル生成（IO）→ shareXxx 呼び出し（Main）のスレッド境界を示す擬似コード
- Composable サンプルでの状態管理スコープ（rememberCoroutineScope vs lifecycleScope）選択理由

## 総合評価

**要修正（軽微）**

骨子は完成しているが、スレッド境界の記述誤り（high 2件）と MainRouter 変更漏れを修正してから実装着手することを推奨。全体として Notification サンプル画面の共通実装パターンを正しく踏襲し、設計書の 8 つの公開 API と FileProvider / ProGuard 設定をカバーした計画書としての完成度は高い。上記修正後であれば実装可能なレベル。
