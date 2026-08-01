# サンプルアプリ実装レビュー結果

- 日付: 2026-07-25
- 対象ブランチ: feature/NTKIT-12
- 対象差分:
  - `git diff develop...HEAD`
  - 追加確認: sample app 実装は未コミット working tree 差分として存在したため、`git diff` / 未追跡ファイルもレビュー対象に含めた
- 計画ファイル: artifact/designs/clipboard/2026-07-25-android-clipboard-sample-app-design-v3.md
- 実装結果ファイル: artifact/results/clipboard/2026-07-25-android-clipboard-implement-sample-app-result-v1.md
- 対象 OS: Android

---

## レビュー概要

AndroidLibraryExample に clipboard サンプル画面を追加し、Main Menu / Router から遷移できるようにした実装。新規 `ClipboardSampleScreen.kt` は `android_library` の `ClipboardUseCases` と `ClipboardChangeMonitor` を使い、copy / read / hasClip / getDescription / clear / observe / error cases を固定値ボタンで確認する構成。

実装は計画 v3 の方針どおり、`unity_android_plugin` への依存を追加せず、ネイティブサンプルアプリの依存方向を維持している。`./gradlew :app:compileDebugKotlin :app:lintDebug` は SUCCESS。

## 重大な問題（high）

- なし。

## 改善提案（medium）

- なし。

## 軽微な指摘（low）

1. `ClipboardSampleScreen.kt` の TAG が Android ルールの「フルクラス名」形式ではない
   - 対象: android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ClipboardSampleScreen.kt:40
   - 問題: `private const val CLIPBOARD_TAG = "ClipboardSampleScreen"` になっている。`agent-rules/coding-rules/android.md` は TAG にクラスのフルネームを使う方針。
   - 提案: top-level composable の package-level TAG として、`"com.jonghyunkim.android.nativetoolkit.example.ClipboardSampleScreen"` など一意なフル名へ寄せる。

2. 変更対象の public composable `MainMenuScreen` に KDoc がない
   - 対象: android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainMenuScreen.kt:22
   - 問題: `onSelectClipboardTest` を追加して public API の引数が増えているが、Android ルールの public 関数 KDoc 対象に対して説明がない。既存からの不足ではあるが、今回 public signature を変更しているため合わせて補うとよい。
   - 提案: 画面概要と `onSelectDialogTest` / `onSelectNotificationTest` / `onSelectShareTest` / `onSelectClipboardTest` の `@param` を追加する。

## 計画書整合性チェック

- 全セクション・全ボタンの実装: ○
  - Copy / Copy - Sensitive / Read / Inspect / Clear / Observe / Error Cases が計画 v3 の一覧どおり実装されている。
- API 呼び出し方針の一致: ○
  - copy/read 系は `ClipboardUseCases`、監視は `ClipboardChangeMonitor`、URI は FileProvider 実 URI 生成。
- システム設定（Manifest / FileProvider 等）の正確性: ○
  - app manifest / Gradle の追加変更なし。FileProvider は `android_library` 側の既存 provider を利用。
- 変更ファイル一覧との diff 整合: △
  - 計画の本体変更ファイル（`ClipboardSampleScreen.kt` / `MainRouter.kt` / `MainMenuScreen.kt`）は一致。実装結果では UI テスト `ClipboardSampleScreenUiTest.kt` も追加されており、これは追加判断として result に記録済み。
- 計画書との差分（追加判断）の result ファイルへの記録: ○
  - UI テスト追加、スクロール方式、監視 callback の複数発火に伴う期待値調整が記録されている。

## サンプルアプリパターン適合チェック

- メニュー導線（Router / MainMenu）: ○
- 画面構成パターン（タイトル / statusText / LazyColumn）: ○
- 成功/失敗表示フォーマット: ○
- 共通 UI 部品の利用: ○
  - 既存 `ShareSampleScreen` と同系統の Compose 構成。private helper の無理な共通化は行っていない。

## プロジェクトルール適合チェック

- common.md 準拠: ○
- android.md 準拠: △
  - TAG フルネーム形式と `MainMenuScreen` KDoc に軽微な不足あり。
- サンプルアプリの依存方向（Unity プラグイン非依存）: ○
  - `app/build.gradle.kts` に `unity_android_plugin` 依存なし。`android.unity.*` import なし。
- Log.d 網羅性: ○
  - public composable と各操作 callback にログあり。private formatting helper は対象外と判断。
- KDoc 網羅性: △
  - `ClipboardSampleScreen` / UI test class は KDoc あり。`MainMenuScreen` は public function だが KDoc なし。

## 手動確認観点の充足

| # | 観点 | 状況 |
|---|---|---|
| 1 | プレーンテキストのコピー | ○ UI テストで成功表示を確認 |
| 2 | 空文字コピー | ○ UI テストで成功表示を確認 |
| 3 | HTML コピー→他アプリ貼り付け | △ result 上も未実施。他アプリ操作が必要 |
| 4 | URI コピー→Read Clipboard | ○ UI テストで `content://` を確認 |
| 5 | URI の他アプリ貼り付け | △ result 上も未実施。他アプリ操作が必要 |
| 6 | 複数テキストコピー | ○ UI テストで read 結果を確認 |
| 7 | 読み取り往復 | ○ UI テストで一部確認 |
| 8 | 空クリップボードの読み取り | ○ UI テストで正常系表示を確認 |
| 9 | hasClip | ○ UI テストで true/false を確認 |
| 10 | クリア | ○ UI テストで確認 |
| 11 | 機微フラグ（API 33+） | △ system UI の目視確認が必要 |
| 12 | API 32 以下の自前 Toast | △ system UI の目視確認が必要 |
| 13 | 貼り付けアクセス通知（API 31+） | △ 他アプリ操作と system toast 目視確認が必要 |
| 14 | 監視の発火 | ○ UI テストで通知到達を確認 |
| 15 | 監視の二重開始 no-op | △ UI 安定性は確認済み。厳密な二重登録防止は library 側 test で担保 |
| 16 | 監視停止 | ○ UI テストで停止後の非通知を確認 |
| 17 | 画面離脱時の解除 | △ 実装は `DisposableEffect` で対応。画面再入場込みの目視確認は未実施 |
| 18 | エラー: 空 HTML | ○ UI テストで確認 |
| 19 | エラー: 空リスト | ○ UI テストで確認 |
| 20 | エラー: blank URI | ○ UI テストで確認 |
| 21 | エラー: 未対応 scheme | ○ UI テストで確認 |
| 22 | ログに本文が出ないこと | ○ result 上で実機 logcat 確認済み |
| 23 | Unity 非依存の確認 | ○ grep で確認済み |

## 総合評価

総合評価: 要修正（軽微）。

実装は計画 v3 と整合しており、サンプルアプリの依存方向・画面構成・主要 API 呼び出しに重大な問題はない。残るのは Android ルール上の TAG/KDoc の軽微な不足と、他アプリ・system UI を伴う手動確認の未実施項目。コード修正としては TAG と KDoc の補完で十分。
