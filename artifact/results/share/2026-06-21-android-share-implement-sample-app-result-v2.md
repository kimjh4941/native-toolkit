# 実装結果: Share サンプルアプリ v3 レビュー指摘修正（Android）

- 実施日: 2026-06-21
- 対象アプリ: `android/AndroidLibraryExample`
- 参照計画: `artifact/designs/share/2026-06-20-android-share-sample-app-design-v3.md`
- 参照レビュー: `artifact/reviews/share/2026-06-20-android-share-implement-sample-app-review-v1.md`
- 前回結果: `artifact/results/share/2026-06-20-android-share-implement-sample-app-result-v1.md`
- バージョン: v2

## 実装サマリー

### 計画書由来で維持した実装

- `ACTION_SEND` / `ACTION_SEND_MULTIPLE` の受信と `ReceivedShareScreen` への routing。
- `singleTop` と `onCreate` / `onNewIntent` の両受信経路。
- text / single stream / multiple streams / Direct Share shortcut ID の parser。
- rich preview 送信、callback 文言、`DisposableEffect` による pending callback cleanup。

### レビュー指摘による追加修正

- `clearReceivedShare()` で Activity の current share Intent を `ACTION_MAIN` に置換し、Back 後の Activity 再生成で古い共有を再処理しないようにした。
- `MainActivityIncomingShareInstrumentedTest` を追加し、受信状態の clear と Intent 消費を直接検証する。
- 既存 `ExampleInstrumentedTest` の期待 package 名を現 applicationId へ修正した。
- `MainActivity` class と `AppRouter` に KDoc を追加した。
- `AppRouter` に全引数を含む `Log.d` を追加し、Activity lifecycle のログをメソッド先頭へ移動した。
- `ShareSampleScreen` の `activity` KDoc から削除済み `runOnUiThread` の記述を除いた。

### 追加判断

- share Intent は受信直後ではなく `clearReceivedShare()` 時に消費する。受信画面表示中の Activity recreation では共有内容を復元でき、Back 後のみ再処理を防げるため。
- `ActivityScenario` は Activity の current Intent を変更すると終了時の同一性判定に使えないため、テスト assertion 後のみ起動 Intent を戻して Scenario を close する。production state の検証内容には影響しない。
- rich preview の画像は v1 どおり `android.R.mipmap.sym_def_app_icon` を使用する。アプリの `R.mipmap.ic_launcher` は adaptive icon XML のため `BitmapFactory.decodeResource` で bitmap を得られない端末がある。

## 変更ファイル

### 今回変更

- `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainActivity.kt`
- `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/MainRouter.kt`
- `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ShareSampleScreen.kt`
- `app/src/androidTest/java/example/android/ExampleInstrumentedTest.kt`

### 今回追加

- `app/src/androidTest/java/com/jonghyunkim/android/nativetoolkit/example/MainActivityIncomingShareInstrumentedTest.kt`

### v3 既存変更（維持）

- `app/src/main/AndroidManifest.xml`
- `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ReceivedShareContent.kt`
- `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/IncomingShareParser.kt`
- `app/src/main/java/com/jonghyunkim/android/nativetoolkit/example/ReceivedShareScreen.kt`
- `app/src/androidTest/java/com/jonghyunkim/android/nativetoolkit/example/IncomingShareParserInstrumentedTest.kt`

## ビルド・静的検証

| 項目 | 結果 | 備考 |
|---|---|---|
| `:app:assembleDebug` | SUCCESS | app APK build |
| `:app:assembleDebugAndroidTest` | SUCCESS | 最終 androidTest コードを compile / package |
| `:app:testDebugUnitTest` | SUCCESS | local JVM tests |
| `:app:lintDebug` | SUCCESS | 0 errors / 21 warnings。今回差分由来の新規 error なし |
| `git diff --check` | SUCCESS | whitespace error なし |

## Instrumented Test

### 確認済み

- Pixel 6a（Android 16）で `IncomingShareParserInstrumentedTest` 7 件成功。
- text、CharSequence、single stream、multiple streams、shortcut ID、unsupported action、null intent を確認。
- レビュー時に失敗した `ExampleInstrumentedTest` の原因は旧 package 名であり、現 applicationId へ修正済み。最終コードは androidTest APK の compile に成功。

### 最終 suite の未完了事項

- 最終 `:app:connectedDebugAndroidTest`（9件）は接続端末が外れたため再実行できなかった。
- Activity intent 消費テストは最終形へ修正後、compile / package 済みだが実機実行は未確認。
- `./gradlew installDebug` も接続端末がないため未実施。

## 手動確認観点

| 観点 | 結果 | 理由 / 実績 |
|---|---|---|
| Chrome から text / URL を通常共有 | 実機未確認 | 外部アプリ操作が必要 |
| 起動中の `onNewIntent` 受信 | 実機未確認 | 外部アプリ操作が必要 |
| 単一画像 / 複数画像受信 | 実機未確認 | parser test は成功、Gallery end-to-end は未実施 |
| Direct Share の "Sample User" 選択 | 実機未確認 | Sharesheet の ranking / cache を含む操作が必要 |
| 画面内 Back / system Back | 一部確認 | state / Intent 消費コードと test compile は確認、最終実機 test は端末切断 |
| rich preview title / thumbnail | 実機未確認 | API 31 / 35 / 36 の Sharesheet 確認が必要 |
| callback 表示 / cancel cleanup | 実機未確認 | Sharesheet 操作が必要 |

## Definition of Done

- ○ `singleTop` と text / image / multiple image filter を維持。
- ○ cold start / `onNewIntent` の受信コードを維持。
- ○ parser の主要 7 分岐を Pixel 6a Android 16 で確認済み。
- ○ Back 時に state と current share Intent を消費する実装を追加。
- ○ stale package assertion を修正。
- ○ Log.d / KDoc 指摘を修正。
- ○ rich preview button / callback 文言 / `cancelPendingCallback` を維持。
- △ 最終全9件 instrumented suite は端末再接続後に要実行。
- △ Chrome / Gallery / Direct Share / rich preview の end-to-end は要手動確認。

## 次工程確認

- 提示文:
  - 「このサンプル実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して `review-implementation-sample-app` の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま終了
- ユーザー回答:
  - 未回答
