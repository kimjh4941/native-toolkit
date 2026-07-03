# Android Share v3 サンプルアプリ実装レビュー v1

## レビュー対象

- 日付: 2026-06-20
- 対象OS: Android
- ブランチ: `feature/NTKIT-8`
- 計画ファイル: `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md`
- 実装結果ファイル: 該当する v3 sample-app result は未作成
- diff:
  - `develop...HEAD` は Share v1/v2 や skill 移行を含む広範な差分
  - 本レビューは、現在の未コミット差分のうち `android/AndroidLibraryExample/app` 配下の Share v3 サンプル実装を対象とする

## レビュー概要

Share v3 サンプルとして、text / image / multiple image の受信 filter、`singleTop`、受信 Intent parser、受信内容画面、自動 routing、リッチプレビュー送信、callback cleanup が計画どおり追加されている。`FileProvider` は `exported=false`、既存 `text/plain` share target も維持されている。

app、androidTest APK、unit test の build は成功した。接続実機 Pixel 6a（Android 16）で新規 `IncomingShareParserInstrumentedTest` 7 件は全件成功した。一方、全 instrumented suite は既存テンプレートテストの package assertion が古いため 8 件中 1 件失敗する。また、受信 Intent を消費していないため、Back 後に Activity が再生成されると古い共有を再処理する問題が残る。

## 重大な問題（high）

なし。

## 改善提案（medium）

### 1. Back で状態を消しても Activity の share Intent が残り、再生成時に古い共有が再表示される

対象:

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainActivity.kt:23-30`
- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainActivity.kt:40-44`
- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainActivity.kt:56-60`
- `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md:485-487`

`clearReceivedShare()` は Compose state だけを null にし、`Activity.intent` に残る `ACTION_SEND` / `ACTION_SEND_MULTIPLE` を消費済みにしない。`onNewIntent()` でも `setIntent(intent)` しているため、画面内 Back またはシステム Back の後に process recreation / configuration recreation が起きると、`onCreate()` が同じ share Intent を再び parse して `ReceivedShareScreen` を再表示する。

受信を state へ取り込んだ後に Activity の current Intent を非 share Intent へ差し替えるか、share Intent の一意な消費状態を `savedInstanceState` 等で管理すること。Back 後に `ActivityScenario.recreate()` して受信画面へ戻らないテストを追加すること。

### 2. 全 instrumented test suite が既存 package assertion で失敗する

対象:

- `android/AndroidLibraryExample/app/src/androidTest/java/example/android/ExampleInstrumentedTest.kt:17-23`

`ExampleInstrumentedTest` は `targetContext.packageName == "example.android"` を期待するが、実際の `applicationId` は `com.jonghyunkim.android.nativetoolkit.example` である。このため `:app:connectedDebugAndroidTest` は 8 件中 1 件失敗し、計画の「instrumented test が passed」という完了条件を満たさない。

assertion を現 applicationId に更新するか、価値のないテンプレートテストであれば削除すること。なお、`IncomingShareParserInstrumentedTest` のみを指定した実行では 7 件すべて成功した。

### 3. Share v3 サンプルアプリの実装結果ファイルがない

対象:

- `artifact/results/share/`（`2026-06-20-android-share-*-sample-app-result-vN.md` が存在しない）
- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ShareSampleScreen.kt:180-208`

計画に対応する result がないため、変更ファイル一覧、追加判断、build / test 結果、手動確認の実施状況を照合できない。特に rich preview の画像を計画の `R.mipmap.ic_launcher` ではなく `android.R.mipmap.sym_def_app_icon` に変更した判断が記録されていない。

`implement-sample-app` workflow の result template に従って v3 result を作成し、設計差分と未実施の end-to-end 項目を明記すること。

## 軽微な指摘（low）

### 1. 変更した public UI / Activity が Android の Log.d・KDoc 規約を満たしていない

対象:

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainRouter.kt:24-28`
- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainActivity.kt:15-25`
- `agent-rules/coding-rules/android.md:3-39,64-100`

public composable `AppRouter` に KDoc と先頭 `Log.d` がない。public `MainActivity` にも class KDoc がない。また `onCreate` / `onNewIntent` は `Log.d` が `super` 呼び出し後にあり、「対象メソッドの先頭1行目」という規約には一致しない。今回変更した surface について規約へ揃えること。

### 2. ShareSampleScreen の KDoc が削除済みの runOnUiThread を参照している

対象:

- `android/AndroidLibraryExample/app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ShareSampleScreen.kt:54-62`

`activity` の説明に `runOnUiThread` 用と残っているが、現実装では削除済みである。`ShareUseCases` の host context として利用する説明へ更新すること。

## 計画書整合性チェック

| 項目 | 判定 | コメント |
|---|---|---|
| 全セクション・全ボタンの実装 | ○ | 受信画面と rich preview ボタンを実装 |
| API 呼び出し方針の一致 | ○ | parser、UseCase、cancel cleanup は計画どおり |
| システム設定の正確性 | ○ | `singleTop`、3 種の filter、shortcuts meta-data、FileProvider を確認 |
| 変更ファイル一覧との diff 整合 | ○ | 計画記載の 8 ファイルすべてに対応 |
| 追加判断の result への記録 | × | 対応する v3 sample-app result がない |

Direct Share で `EXTRA_SHORTCUT_ID` が付与される前提は
[Android 公式仕様](https://developer.android.com/training/sharing/direct-share-targets)と一致する。

## サンプルアプリパターン適合チェック

| 項目 | 判定 | コメント |
|---|---|---|
| メニュー導線（Router / MainMenu） | ○ | 受信時のみ自動 routing、既存メニューは維持 |
| 画面構成パターン | ○ | Back、title、読み取り専用フィールド、scroll を実装 |
| 成功/失敗表示フォーマット | ○ | rich preview / callback は既存の記号付き形式を維持 |
| 共通 UI 部品の利用 | ○ | 既存画面の Compose パターンに準拠 |

## プロジェクトルール適合チェック

| 項目 | 判定 | コメント |
|---|---|---|
| `common.md` 準拠 | ○ | サンプル固有の受信責務として分離 |
| `android.md` 準拠 | △ | runtime 実装は妥当だが Log.d / KDoc の不足あり |
| Log.d 網羅性 | △ | `AppRouter` なし、lifecycle override の先頭行ではない |
| KDoc 網羅性 | △ | `AppRouter` / `MainActivity` class に不足 |

## 手動確認観点の充足

| 観点 | 判定 | コメント |
|---|---|---|
| Chrome から text / URL を通常共有 | △ | コード・filter は確認、end-to-end 未実施 |
| ギャラリーから単一画像を共有 | △ | filter / parser は確認、UI 起動は未実施 |
| ギャラリーから複数画像を共有 | △ | parser instrumented test は成功、end-to-end 未実施 |
| Direct Share の "Sample User" 表示・選択 | △ | 設定と ID parser は確認、Sharesheet 実操作は未実施 |
| cold start 受信 | △ | コード確認のみ |
| `onNewIntent` 受信 | △ | コード確認のみ |
| 画面内 Back / system Back | △ | 通常遷移は実装済みだが Activity 再生成時の再表示リスクあり |
| rich preview title / thumbnail | △ | コード確認のみ。API 31 / 35 / 36 の Sharesheet 未確認 |
| parser instrumented test | ○ | Pixel 6a Android 16 で新規 7 件成功 |
| 全 instrumented suite | × | 既存 package assertion 1 件失敗 |

## ビルド・テスト確認

- `:app:assembleDebug`: SUCCESS
- `:app:assembleDebugAndroidTest`: SUCCESS
- `:app:testDebugUnitTest`: SUCCESS
- `:app:connectedDebugAndroidTest`: FAILED（8 件中 1 件、既存 `ExampleInstrumentedTest`）
- `IncomingShareParserInstrumentedTest` 指定実行: SUCCESS（7 件）
- `git diff --check`: SUCCESS

## 総合評価

**要修正（軽微）**

計画した v3 UI と parser は概ね正しく、新規 parser テストも実機で成功している。ただし、消費済み share Intent の再処理と全 instrumented suite の失敗は完了条件に抵触する。これらと result ファイルを修正後、Chrome / ギャラリー / Direct Share / rich preview の end-to-end 確認を行う必要がある。
