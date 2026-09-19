# 実装結果: Share サンプルアプリ v3（Android）

- 実施日: 2026-06-20
- 対象アプリ: `android/AndroidLibraryExample`
- 参照計画: `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md`
- バージョン: v1（初版）

---

## 変更ファイル

### 新規

| ファイル | 内容 |
|---|---|
| `app/src/main/java/.../ReceivedShareContent.kt` | 受信内容モデル（action / mimeType / text / streamUris / shortcutId） |
| `app/src/main/java/.../IncomingShareParser.kt` | Intent → ReceivedShareContent? 変換（IntentCompat で API 差分吸収） |
| `app/src/main/java/.../ReceivedShareScreen.kt` | 受信内容表示画面（Back ボタン + フィールド一覧 + null ガード） |
| `app/src/androidTest/java/.../IncomingShareParserInstrumentedTest.kt` | 6 ケースのインストゥルメントテスト |

### 変更

| ファイル | 変更内容 |
|---|---|
| `app/src/main/AndroidManifest.xml` | `singleTop` 追加 / `image/*` の `ACTION_SEND` / `ACTION_SEND_MULTIPLE` filter 追加 |
| `app/src/main/java/.../MainActivity.kt` | `receivedShare` 状態（mutableStateOf）/ `onNewIntent` / `handleIncomingShare` / `clearReceivedShare` |
| `app/src/main/java/.../MainRouter.kt` | `RECEIVED_SHARE` enum 追加 / `LaunchedEffect` 自動遷移 / `BackHandler` でクリア / ルーティング / 引数型を `AppCompatActivity` → `MainActivity` へ変更 |
| `app/src/main/java/.../ShareSampleScreen.kt` | "Share Text with Rich Preview" ボタン追加 / コールバック null 時文言を `"ℹ️ Shared (package unavailable)"` に修正 / `DisposableEffect` で `cancelPendingCallback` 配線 |

---

## 実装したサンプル機能

### 受信側（v3 主目的）

- `MainActivity` が `onCreate`（コールドスタート）と `onNewIntent`（起動中受信）の両方で `IncomingShareParser.parse` を呼び出す
- パース結果が非 null の場合 `receivedShare` 状態を更新 → `AppRouter` の `LaunchedEffect` が `RECEIVED_SHARE` 画面へ自動遷移
- `ReceivedShareScreen` に action / mimeType / text / streamUris（件数と URI 文字列）/ shortcutId を表示
- Back ボタン・システム Back 両方で `clearReceivedShare()` を呼び出し、再表示ループを防止
- テキスト・単一画像・複数画像・Direct Share ターゲット受信の各パスを網羅

### 送信側（v3 追加分）

- "Share Text with Rich Preview" ボタン: `cacheDir` にアイコン PNG を書き出し `SharePreviewOptions(title, thumbnailPath)` で渡す（API 31 以降で Sharesheet 上部にプレビュー表示）
- "Share with Callback" コールバック文言: `null` 時は `"ℹ️ Shared (package unavailable)"` に変更（キャンセルでは `onResult` 自体が呼ばれない仕様と一致）
- `DisposableEffect(shareUseCases) { onDispose { shareUseCases.cancelPendingCallback() } }` を配線

### API 使用

```kotlin
// リッチプレビュー送信
shareUseCases.shareText(
    ShareContent(text = "...", mimeType = "text/plain"),
    chooserActionsJson = "[]",
    SharePreviewOptions(title = "Introducing content previews", thumbnailPath = file.absolutePath)
)
// cancelPendingCallback
shareUseCases.cancelPendingCallback()
```

計画書の擬似コード（`previewTitle` / `previewThumbnailPath` 直接渡し）は旧 API 表記。実装では `SharePreviewOptions` を使用する現行 API に合わせた。

---

## ビルド/実行結果

### ビルド

```
./gradlew assembleDebug
BUILD SUCCESSFUL in 5s
85 actionable tasks: 7 executed, 78 up-to-date
```

**ビルド確認済み**（コンパイル・リンク通過）

### 実機動作確認

**実機未確認**（接続端末なし）

実機での確認は下記「手動確認観点」を参照。

---

## 手動確認観点

### 受信側

| 観点 | 操作 | 期待結果 | 確認結果 |
|---|---|---|---|
| テキスト通常共有（コールドスタート） | Chrome で任意 URL を開き「共有」→ 本アプリを選択 | `ReceivedShareScreen` に action=ACTION_SEND / mimeType=text/plain / text=URL が表示 | 実機未確認 |
| テキスト通常共有（起動中受信） | アプリ起動後に上記操作 | `onNewIntent` 経由で `ReceivedShareScreen` へ自動遷移 | 実機未確認 |
| 単一画像受信 | ギャラリー等で画像 1 枚を共有 → 本アプリを選択 | action=ACTION_SEND / mimeType=image/xxx / streamUris に 1 件 URI が表示 | 実機未確認 |
| 複数画像受信 | ギャラリー等で画像複数枚を共有 → 本アプリを選択 | action=ACTION_SEND_MULTIPLE / streamUris に複数 URI が表示 | 実機未確認 |
| Direct Share 受信 | "Register Direct Share Target" 実行後、他アプリで Direct Share の "Sample User" を選択 | shortcutId = "sample_1" が表示 | 実機未確認 |
| Back ボタンでクリア | `ReceivedShareScreen` 表示中に画面内 Back ボタンを押す | メインメニューに戻り、再度共有しない限り受信画面に遷移しない | 実機未確認 |
| システム Back でクリア | `ReceivedShareScreen` 表示中にシステム Back を押す | 同上 | 実機未確認 |

### 送信側（v3 追加分）

| 観点 | 操作 | 期待結果 | 確認結果 |
|---|---|---|---|
| リッチプレビュー | "Share Text with Rich Preview" ボタンを押す | Sharesheet 上部にタイトル "Introducing content previews" とサムネイルが表示（API 31+） | 実機未確認 |
| コールバック文言 | "Share with Callback" を押してアプリ選択（パッケージ名あり） | `"✅ Selected: <pkg>"` と表示 | 実機未確認 |
| コールバック null 文言 | "Share with Callback" でパッケージ名なし選択 | `"ℹ️ Shared (package unavailable)"` と表示（`"Cancelled"` でない） | 実機未確認 |
| cancelPendingCallback | `ShareSampleScreen` を表示後 Back で離脱 | `DisposableEffect.onDispose` で `cancelPendingCallback` が呼ばれ、スタレな BroadcastReceiver が解除される | 実機未確認 |

---

## 追加判断（計画書外）

- `MainRouter.kt` の `AppRouter` 引数型を `AppCompatActivity` → `MainActivity` へ変更した（キャスト不要、型安全）。呼び出し元は `MainActivity` のみのため破壊的変更なし。
- `ReceivedShareScreen.kt` のファイルレベル定数を `RECEIVED_SHARE_TAG` にした（同パッケージの `NotificationSampleScreen.kt` が非 private の `const val TAG` を持ちコンパイルエラーとなるため）。
- `IncomingShareParserInstrumentedTest.kt` は `com.jonghyunkim.android.nativetoolkit.example` パッケージに配置（既存の `example.android` パッケージのテストとは別）。

---

## 未実施項目

| 項目 | 理由 |
|---|---|
| 実機での全手動確認観点 | 接続端末なし |
| `IncomingShareParserInstrumentedTest` の実機実行 | 接続端末なし |
| リッチプレビューの API バージョン別（API 31 / 35 / 36）動作確認 | 接続端末なし |
| 画像 URI のサムネイル表示（`contentResolver` / `ImageDecoder`） | 計画書では「最小実装では URI 文字列の表示で可」とされており、文字列表示で実装した |
