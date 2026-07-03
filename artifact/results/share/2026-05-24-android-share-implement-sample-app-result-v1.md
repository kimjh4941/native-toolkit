# 実装結果: Share サンプルアプリ（AndroidLibraryExample）

- 日付: 2026-05-24
- 対象アプリ: `android/AndroidLibraryExample`
- 参照計画ファイル: `artifact/designs/share/2026-05-24-android-share-implement-sample-app-v2.md`
- ビルド結果: BUILD SUCCESSFUL

---

## 変更ファイル

| ファイル | 種別 | 内容 |
|---|---|---|
| `app/src/main/java/.../ShareSampleScreen.kt` | 新規 | Share サンプル画面 Composable（9 ボタン） |
| `app/src/main/java/.../MainRouter.kt` | 変更 | `SHARE_TEST` enum 追加、ShareSampleScreen ルーティング追加、MainMenuScreen に `onSelectShareTest` 追加 |
| `app/src/main/java/.../MainMenuScreen.kt` | 変更 | "Share Example" メニュー項目追加、`onSelectShareTest` 引数追加、Preview 更新 |
| `app/src/main/AndroidManifest.xml` | 変更 | FileProvider provider 宣言追加 |
| `app/src/main/res/xml/file_paths.xml` | 新規 | `files-path` / `cache-path` / `external-files-path` 定義 |
| `app/proguard-rules.pro` | 変更 | FileProvider / ShareCompat / ShortcutInfoCompat / IconCompat keep ルール追加 |

---

## 実装したサンプル機能

| セクション | ボタン | UseCase 呼び出し |
|---|---|---|
| Text Share | Share Text | `shareUseCases.shareText(ShareContent(text="Hello from native-toolkit"), chooserActionsJson = "[]")` |
| Text Share | Share URL | `shareUseCases.shareText(ShareContent(text="https://example.com", mimeType="text/plain"), chooserActionsJson = "[]")` |
| Image Share | Share Image | `shareUseCases.shareImage(path, "image/png")` |
| Multiple Images | Share Multiple Images | `shareUseCases.shareImages(listOf(path1, path2))` |
| File Share | Share File | `shareUseCases.shareFile(path)` |
| Multiple Files | Share Multiple Files | `shareUseCases.shareFiles(listOf(path1, path2))` |
| Direct Share Target | Register Direct Share Target | `shareUseCases.registerDirectShareTarget(target, iconBytes)` |
| Direct Share Target | Remove Direct Share Target | `shareUseCases.removeDirectShareTargets(listOf("sample_1"))` |
| Share with Callback | Share with Callback | `shareUseCases.shareWithCallback(content) { pkg -> ... }` |

---

## ビルド / 実行結果

- `assembleDebug`: BUILD SUCCESSFUL
- Java 17（Homebrew OpenJDK 17.0.18）使用
- 実機テスト: 実機依存のため未実施（下記「手動確認観点」参照）

### 追加判断（計画書との差分）

- **TAG 定数の命名**: `NotificationSampleScreen.kt` に package-level `const val TAG` が非 private で定義されているため、`ShareSampleScreen.kt` では `private const val SHARE_TAG` という名前を使用した（命名衝突回避。値は `"ShareSampleScreen"` で android.md の intent を維持）
- **Icon リソース**: `R.mipmap.ic_launcher` が AndroidLibraryExample のデフォルト設定では利用できなかったため、`android.R.mipmap.sym_def_app_icon` を使用（システム標準アイコン。実際のアプリではアプリアイコンを指定する）
- **スクロールバー**: `NotificationSampleScreen.kt` の `AlwaysVisibleLazyColumnScrollbar` は private のため再利用不可。同じロジックを `ShareSampleScrollbar` / `ShareScrollbarMetrics` / `calculateShareScrollbarMetrics` として複製
- **画面タイトル**: 計画書では `"Share"`（28sp, Bold）と記載されているが、メニュー項目名（"Share Example"）との一貫性を優先して `"Share Example"` を採用した

---

## 実機確認手順

### インストール方法

```bash
cd android/AndroidLibraryExample
JAVA_HOME=/opt/homebrew/Cellar/openjdk@17/17.0.18/libexec/openjdk.jdk/Contents/Home \
  ./gradlew installDebug
```

接続済み実機（または Android Emulator）にインストールされる。

### 確認手順

1. アプリを起動し、Main Menu で "Share Example" をタップ → ShareSampleScreen に遷移することを確認
2. 以下の観点を上から順に実施し、結果を記録する（確認済み / NG / 実機未確認）
3. NG が出た場合は原因を特定して修正し、該当観点から再確認する

---

## 手動確認観点

| 観点 | 操作 | 期待結果 | 状態 |
|---|---|---|---|
| テキスト共有 | "Share Text" タップ | Sharesheet が開く | 実機未確認 |
| URL 共有 | "Share URL" タップ | Sharesheet が開く（リンクプレビュー表示） | 実機未確認 |
| 画像共有 | "Share Image" タップ | Sharesheet が開く | 実機未確認 |
| 複数画像共有 | "Share Multiple Images" タップ | Sharesheet が開く | 実機未確認 |
| ファイル共有 | "Share File" タップ | Sharesheet が開く | 実機未確認 |
| 複数ファイル共有 | "Share Multiple Files" タップ | Sharesheet が開く | 実機未確認 |
| Direct Share 登録 | "Register Direct Share Target" タップ | statusText に `✅ registerDirectShareTarget called` 表示 | 実機未確認 |
| Direct Share 削除 | Register 後に "Remove Direct Share Target" タップ | Sharesheet からショートカットが消える | 実機未確認 |
| コールバック成功 | "Share with Callback" タップ → アプリを選択 | statusText に `✅ Selected: <packageName>` 表示 | 実機未確認 |
| コールバックキャンセル | "Share with Callback" タップ → 外タップで閉じる | statusText に `ℹ️ Cancelled` 表示 | 実機未確認 |
| BroadcastReceiver リーク | 連続で "Share with Callback" を複数回実行 | 古い receiver が誤発火しない | 実機未確認 |
| Back ナビゲーション | Back ボタンタップ | Main Menu に戻る | ビルド確認済み |
| メニュー導線 | Main Menu で "Share Example" タップ | ShareSampleScreen に遷移 | ビルド確認済み |

---

## 未実施項目と理由

| 項目 | 理由 |
|---|---|
| 全実機確認 | 実機接続が必要なため本工程では未実施 |
| ChooserAction（API 34+）確認 | サンプルでは `chooserActionsJson = "[]"` を渡すため確認不可。Unity Bridge 経由で別途確認する |
| FileProvider URI 生成の Instrumented Test | 設計書 Task 5 で言及済み。本タスクスコープ外 |
