# 段階 0b の結果: サンプルに testTag を付ける

- 実施日: 2026-10-03
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0b、`designs/2026-10-03-android-c-abi-ui-test-design.md` の 5 章
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（見た目も動作も変えていない）

## 1. 変えたこと

| ファイル | 変更 |
|---|---|
| `AndroidDialogFragmentTestScreen.kt` | ボタン 6・戻る・結果の表示に testTag（`dialog.*`） |
| `NotificationSampleScreen.kt` | ボタン 46・戻る・状態の表示に testTag（`notification.*`） |
| `ShareSampleScreen.kt` | ボタン 14・戻る・状態の表示に testTag（`share.*`） |
| `ClipboardSampleScreen.kt` | ボタン 16・戻る・状態の表示に testTag（`clipboard.*`） |
| `ReceivedShareScreen.kt` | 戻ると、値 5 つ（`action` / `mimeType` / `text` / `streamUris` / `directShareTarget`）に testTag（`receivedShare.*`）。値の部品 `ReceivedShareField` に引数 `testTag` を足した |
| `MainMenuScreen.kt` | カード 4 枚に testTag（`menu.*`）。部品 `MainMenuListItem` に引数 `testTag` を足した |
| `MainActivity.kt` | Compose のルートを `Box(Modifier.semantics { testTagsAsResourceId = true })` で包んだ。今の Compose（BOM 2024.09.00）では `testTagsAsResourceId` が実験的な API なので、`onCreate` に `@OptIn(ExperimentalComposeUiApi::class)` を付けた |
| `androidTest/.../TagInventoryTest.kt`（新規） | `TagInventoryTest`（メニュー・Dialog・Notification・Share・Clipboard の 5 件）と `ReceivedShareTagInventoryTest`（1 件）。期待する testTag がすべてあり、それぞれ 1 つだけであることを確かめる |

testTag の名前は、ボタンの文言から記号と括弧を除いた lowerCamelCase（設計書 5.1）。ボタンの付け替えは、`Button(..., modifier = Modifier.fillMaxWidth()) { Text(text = "...") }` の形をスクリプトで見つけて機械的に行い、数を設計書と照らした（Dialog 6、Notification 46、Share 14、Clipboard 16。重複なし）。import は足した行だけで、元の並びは変えていない。

## 2. 確かめたこと

| 確認 | 結果 |
|---|---|
| サンプルの androidTest の全件（Pixel 6a、Android 16） | 29 件すべて成功（既存の Clipboard 14、受け取りの解析 7、`MainActivity` の受け取り 1、雛形 1、`TagInventoryTest` 5、`ReceivedShareTagInventoryTest` 1） |
| 一覧のテストが欠けた tag で落ちるか | 期待の一覧に存在しない `menu.bogus` を一時的に足すと、`No node found that matches TestTag = 'menu.bogus'` で失敗した（確かめた後に元に戻した） |
| 見た目 | メニューの画面を撮って、見出し・カード 4 枚・背景が画面いっぱいに今までどおり出ていることを確かめた。testTag は見た目に影響しない |

API 35 のエミュレータでは流していない（段階 0c の最初に流す。設計書 9 章）。

## 3. 気づいたこと

- 端末を再起動した後、画面のロック（キーガード）が残っていると、Compose のテストがすべて「No compose hierarchies found」で失敗する。この端末はセキュアなロックが無く、`wm dismiss-keyguard` で外れた。`test_android.sh` は、実行の最初にロックを確かめて外す（設計書 3.5 の「ロックされていれば止める」を、セキュアなロックでなければ外す、に読み替える）
- `INSTRUMENTATION_CODE: -1` は成功（`Activity.RESULT_OK`）を表す。結果の読み方（設計書 8 章）では、最後のコードではなくテストごとの `INSTRUMENTATION_STATUS_CODE` で判定する
