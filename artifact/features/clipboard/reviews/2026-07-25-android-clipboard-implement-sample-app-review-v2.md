# サンプルアプリ実装レビュー結果 v2

- 日付: 2026-07-25
- 対象ブランチ: feature/NTKIT-12
- 対象差分:
  - `git diff develop...HEAD`
  - 追加確認: sample app 実装は未コミット working tree 差分として存在するため、`git diff` / 未追跡ファイルもレビュー対象に含めた
- 計画ファイル: artifact/designs/clipboard/2026-07-25-android-clipboard-sample-app-design-v3.md
- 実装結果ファイル: artifact/results/clipboard/2026-07-25-android-clipboard-implement-sample-app-result-v2.md
- 前回レビュー: artifact/reviews/clipboard/2026-07-25-android-clipboard-implement-sample-app-review-v1.md
- 対象 OS: Android

---

## レビュー概要

AndroidLibraryExample に clipboard サンプル画面を追加し、Main Menu / Router から遷移できるようにした実装の再レビュー。v1 レビューで指摘した軽微2件（TAG のフルクラス名化、`MainMenuScreen` の KDoc 追加）はどちらも反映済み。

実装は計画 v3 の方針どおり、`unity_android_plugin` への依存を追加せず、`android_library` の `ClipboardUseCases` / `ClipboardChangeMonitor` を利用している。`./gradlew :app:compileDebugKotlin :app:lintDebug` は SUCCESS。

## 重大な問題（high）

- なし。

## 改善提案（medium）

- なし。

## 軽微な指摘（low）

- なし。

## 前回指摘の反映状況

1. `ClipboardSampleScreen.kt` の TAG が Android ルールの「フルクラス名」形式ではない
   - 反映済み。
   - 確認箇所: android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ClipboardSampleScreen.kt:40
   - `private const val CLIPBOARD_TAG = "com.jonghyunkim.android.nativetoolkit.example.ClipboardSampleScreen"` になっている。
2. 変更対象の public composable `MainMenuScreen` に KDoc がない
   - 反映済み。
   - 確認箇所: android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainMenuScreen.kt:22
   - public composable の概要と全 `@param` が追加されている。

## 計画書整合性チェック

- 全セクション・全ボタンの実装: ○
  - Copy / Copy - Sensitive / Read / Inspect / Clear / Observe / Error Cases が計画 v3 の一覧どおり実装されている。
- API 呼び出し方針の一致: ○
  - copy/read 系は `ClipboardUseCases`、監視は `ClipboardChangeMonitor`、URI は FileProvider 実 URI 生成。
- システム設定（Manifest / FileProvider 等）の正確性: ○
  - app manifest / Gradle の追加変更なし。FileProvider は `android_library` 側の既存 provider を利用。
- 変更ファイル一覧との diff 整合: ○
  - 計画の本体変更ファイルは一致。追加の UI テストは実装結果 v1/v2 の追加判断として記録済み。
- 計画書との差分（追加判断）の result ファイルへの記録: ○
  - UI テスト追加、スクロール方式、監視 callback の複数発火に伴う期待値調整、前回レビュー指摘の反映が記録されている。

## サンプルアプリパターン適合チェック

- メニュー導線（Router / MainMenu）: ○
- 画面構成パターン（タイトル / statusText / LazyColumn）: ○
- 成功/失敗表示フォーマット: ○
- 共通 UI 部品の利用: ○

## プロジェクトルール適合チェック

- common.md 準拠: ○
- android.md 準拠: ○
- サンプルアプリの依存方向（Unity プラグイン非依存）: ○
  - `app/build.gradle.kts` に `unity_android_plugin` 依存なし。`android.unity.*` import なし。
- Log.d 網羅性: ○
- KDoc 網羅性: ○

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

総合評価: LGTM。

前回レビューの軽微指摘はどちらも反映済みで、計画 v3・実装結果 v2・プロジェクトルールとの整合に新たな問題はない。残る △ は他アプリ操作や system UI 目視が必要な手動確認項目であり、コード修正を要求するレビュー指摘ではない。
