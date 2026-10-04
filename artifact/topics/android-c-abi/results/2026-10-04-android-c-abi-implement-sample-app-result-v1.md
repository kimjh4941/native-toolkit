# Android サンプル（段階 1b）実装結果

## 基本情報

| 項目 | 内容 |
|---|---|
| 計画 | `designs/2026-10-04-android-c-abi-sample-app-design-v3.md`（決定） |
| 対象 OS | Android（Pixel 6a・API 36、エミュレーター・API 35） |
| 対象サンプル | `android/AndroidLibraryExample` |
| 作成日 | 2026-10-04 |
| ブランチ | `feature/NTKIT-17` |

## 1. 変更ファイル

`android/AndroidLibraryExample/app/src/` の下（`.../example` は `com/jonghyunkim/android/nativetoolkit/example`）。

| 区分 | ファイル |
|---|---|
| 新規 | `main/java/.../example/SampleEvents.kt`（`SampleEvents`、`ScreenResultSink`、`ScreenResults`）、`main/java/.../example/DialogSampleScreen.kt`、`androidTest/java/.../example/NotificationEventDeliveryUiTest.kt`、`androidTest/java/.../example/ScreenResultSinkInstrumentedTest.kt` |
| 変更 | `main/java/.../example/MainActivity.kt`、`MainRouter.kt`、`NotificationSampleScreen.kt`、`ShareSampleScreen.kt`、`ClipboardSampleScreen.kt`、`main/AndroidManifest.xml` |
| 変更（試験） | `androidTest/java/.../example/` の `DialogUiTest.kt`、`NavigationUiTest.kt`、`NotificationHostStateUiTest.kt`、`NotificationInteractionUiTest.kt`、`NotificationTapUiTest.kt`、`NotificationScheduleUiTest.kt`、`ShareUiTest.kt`、`ClipboardSampleScreenUiTest.kt`、`TagInventoryTest.kt`、`infra/DeviceState.kt`、`infra/Toasts.kt` |
| 削除 | `main/java/.../example/NotificationActionReceiver.kt`、`NotificationDeleteReceiver.kt`、`ShareChooserActionReceiver.kt`、`AndroidDialogFragmentTestScreen.kt`、manifest の 3 つの `<receiver>` |
| `app/src` の外 | `scripts/test_android.sh`（`UI_CLASSES` に `NotificationEventDeliveryUiTest` と `ScreenResultSinkInstrumentedTest`、`HOST_STATE_CASES` に 3 行（n10・n11・n12）） |

## 2. 実装したサンプル機能

計画どおり（計画由来）:

- **入口**: 4 つの画面がすべて `Android*Manager.getInstance(context)` を使う。Manager に口が無い 2 つ（`shouldShowRationale` は `NotificationPermissionHelper`、CallStyle は `CallStyleForegroundService` の公開の Intent の factory）だけ既存の口のまま（計画 2.2、10 章）
- **イベント**: `SampleEvents` が `MainActivity.onCreate` で `interactions`・`shown`・`chooserActions` に登録し、`onDestroy` で外す。画面へは `MutableSharedFlow(replay = 0, extraBufferCapacity = 64)` で渡し、購読の数が 0 ならアクションは Toast。文言は今の Receiver と同じ
- **通知の画面**: イベントの行（`notification.events`、通し番号つき、初期は「ℹ️ #0 No events yet」）、権限のコルーチン版のボタン、本文のタップのサンプル（id 1120、`bodyTap(launchApp = true)`）。メディアの 3 つのアクションは `action(..., launchApp = true)`（`actionId` は `previous`・`play`・`next`）、Accept / Decline・カスタムビューの Dismiss・deleteIntent は `NotificationEventIntents` の `data` に `label` を入れる。設定の画面は `openSettings(target, activity)` で、`FAILED` 以外は今の ℹ️ の文言
- **Share の画面**: Chooser Action は `shareTextWithActions`（名前は今と同じ「Custom」）。不正なアクション（重複した id）のボタン、選択のイベントの節（`shareForSelection`・`cancelShareSelection`、`null` のパッケージは「(unknown package)」）。画面を閉じると `cancelPendingCallback()` で両方の待ちを消す
- **Clipboard の画面**: 監視は `startObserving`・`changes`・`stopObserving`。エラーの文言の後ろに ` [errorCode=<コード>]`
- **Dialog の画面**: `DialogSampleScreen` が `AndroidDialogManager` を使う。6 つの要求の値と options（閉じられない）は今のまま。コルーチン版、閉じられる Dialog、2 秒後の取り消しのボタンを足した。結果は今と同じく `MainRouter` の `rememberSaveable` で持つ

実装のときの追加の判断:

- `Toasts.count` は計画では「文言が一致する数」としたが、記録される Toast の文言に前後の文字が付くことがあり、既存の `waitFor` と同じ部分一致で数える形にした（初回の実行で n61 が 0 件と数えて落ちたため）
- 実装のレビュー（`reviews/2026-10-04-android-c-abi-implement-sample-app-review-v1.md`）の A 2 件（I-X2、I-X3）を受けて、`SampleEvents.kt` に `ScreenResultSink` と `ScreenResults` を足した。Dialog の結果と通知の権限の callback 版の結果は、MainActivity の作り直しをまたいで届くので、「今出ている画面」が登録した受け口へ渡す。Dialog の結果は今と同じく `MainRouter` の `rememberSaveable` で持ち、受け口は router が登録する。2 秒後の取り消しは composition の scope ではなく main の Handler で行う。`onResult` の引数は `DialogSampleScreen` から無くなった。コルーチン版（Dialog と権限）は画面に結びつき、画面を離れると要求ごと取り消される（Kotlin の `suspend` 版の契約どおり）
- s20 の不正な Chooser Action は、読める PNG のアイコンで id だけを重複させる（読めないアイコンでも同じエラーになり、重複の検査が壊れても通っていたため。I-C1）
- 共通の形（Android ⇔ iOS）は、メインメニューの導線・カテゴリのボタン・結果の表示を維持した。拡張したのは、イベントの行（iOS には無い。Android は通知のイベントを画面に出す）と、コルーチン版のボタン（Kotlin の `suspend` 版を見せるため）

## 3. ビルド・実行の結果

| 確かめ | 結果 |
|---|---|
| ビルド | サンプルと試験のコンパイルが通った。入力欄の検査（`scripts/check_sample_app_inputs.py`）は 97 ファイルで成功 |
| 実機（Pixel 6a・API 36）での全体の実行（`--skip-unit`。権限を外して流すホストの状態のケース（n02〜n11）は含み、再起動と更新を伴うホストのケース H-01〜H-04 は含まない） | 280 件。成功 276、失敗 1（n61。下）、スキップ 3（下） |
| エミュレーター（API 35）での全体の実行 | 280 件。成功 275、失敗 2（n61、n22。下）、スキップ 3 |
| n61 の直し（`Toasts.count`）の後 | `NotificationEventDeliveryUiTest` の 2 件が両方の環境で成功 |
| n22（エミュレーターの払いのけ） | 単独で 3 回流して 3 回とも成功。払いのけの操作は今回の変更に関係しないので、たまたまの失敗と判断した |
| スキップ 3 件 | ライブラリの `NotificationPermissionRequestTest`（IT-07）の 3 件。権限を外した状態を前提にし、外す手順を `test_android.sh` に足すのは T-21 の作業。今回の変更とは関係しない |
| 0d の基準との差（UI の側。この行は実装のレビューの前の全体の実行） | changed は 0（エミュレーターの n22 を除く）。基準に無いケースとして、足した UI テスト 12 件（普段の実行の 10 件: d17〜d19、n29、n60〜n62、s18〜s20。ホストの状態の 2 件: n10・n11。どちらも両方の環境で成功）と、1b でライブラリに足した試験が加わった。`DialogUiTest` の d01〜d15 と `NavigationUiTest.m03` は文言を直したうえで成功（基準では同じ名前で成功なので changed に出ない） |

実装のレビュー（`reviews/2026-10-04-android-c-abi-implement-sample-app-review-v1.md`）の後の実行:

| 確かめ | 結果 |
|---|---|
| 足した試験 | 計 18 件。普段の実行の 15 件（d17〜d21、n29、n60〜n62、s18〜s20、`ScreenResultSinkInstrumentedTest` の 3 件）、ホストの状態の 3 件（n10〜n12） |
| 通知・Dialog・Share の分類（`--filter`） | 両方の環境で、通知 40 件・Dialog 21 件・Share 20 件がすべて成功 |
| ホストの状態の分類（n02〜n12 の 9 件） | 両方の環境ですべて成功 |
| `ScreenResultSinkInstrumentedTest` | 両方の環境で 3 件成功 |
| 全体の実行（ほかの分類を含む） | レビューの後はまだ流していない。T-23 の全体の実行で流す |

変異の確かめ（ワークフローの「変異の作り方」に沿い、契約は保ったまま実装の形を変えた）:

| 変異 | 落ちた試験 |
|---|---|
| `MainActivity` がヘルパー越しに受け手を 2 回登録する | `NotificationEventDeliveryUiTest.n62` |
| 画面へ渡す口を再生あり（`replay = 1`）にする | `NotificationInteractionUiTest.n60` |
| `SingleChoice` の番号を間接的に 0 に変える | `DialogUiTest.d05` |
| エラーコードを別の例外から取る | `ClipboardSampleScreenUiTest.errorCase_copyHtmlEmpty_showsEmptyContent` |
| 選択のイベントを捨てる | `ShareUiTest.s18` |
| 2 秒後の取り消しを composition の scope に戻す（レビューの後） | `DialogUiTest.d21` |
| 権限の答えを受け口を通さず画面の状態へ直接書く（レビューの後） | `NotificationHostStateUiTest.n12` |
| UseCase と repository の重複の検査を外す（レビューの後） | `ShareUiTest.s20` |
| 受け口を外すとき、ヘルパー越しに誰の登録かを見ずに消す（レビューの後） | `ScreenResultSinkInstrumentedTest` |
| 受け口が古い router を持ち続ける（レビューの後） | **落ちなかった**（`DialogUiTest.d20`）。理由と扱いはレビューの文書の「直した後の確かめ」。受け口そのものは `ScreenResultSinkInstrumentedTest` で確かめる |

## 4. 手動で確かめる項目・確かめていない項目

| 項目 | 状態 | 理由 |
|---|---|---|
| 計画の手動の項目 | なし | 計画 6 章のとおり、第 1 版の 1 件は UI テスト（n61）へ移した |
| プロセスを止めた後の通知のアクション | このサンプルの試験では確かめていない | ライブラリの IT-10 で確かめ済み（受け手がプロセスを起こして保つ） |
| ホストのケース（H-01〜H-04） | 今回は流していない | 再起動と更新を伴うので、T-23 の全体の実行で流す |
| アプリが動いていないときに `launchApp = true` の通知を押したときの画面の表示 | 表示しない（計画どおり） | 起動直後はメインメニューが出ていて、通知の画面は出ていない。BODY_TAP は通知の画面が出ているときだけ表示し、ACTION は Toast になる（レビュー I-X1。今までも本文のタップは画面に何も出していなかった） |
| Share と Clipboard の画面を閉じたときの後始末（待ちの取り消し、監視の停止） | サンプルの UI テストでは確かめていない | 取り消しはライブラリの IT-15、監視の停止は IT-17 で確かめている（レビュー I-X4） |
| 画面へ渡す口の購読の確かめと `tryEmit` の隙間 | 受け入れた | 計画 4.2（S2-C3）。隙間でアクションが Toast にもならず消えうる（レビュー I-X5） |

## 5. 1b の実装結果（T-23）へ書くこと

- 直した UI テストと理由: `DialogUiTest` d01〜d15・`NavigationUiTest.m03`（入口を Manager に替えて結果の文言が変わった。d11・d14 は入力の値ではなく長さを確かめる）、`NotificationTapUiTest.n28`（表示の確かめを足した）
- 経路が変わったテスト: `NotificationStyleUiTest.n16`、`NotificationInteractionUiTest.n22・n24〜n26`、`NotificationTapUiTest.n28`、`ShareUiTest.s04`（Receiver → ライブラリのイベント）
- Manager に無い口（rationale、CallStyle）の申し送り（計画 10 章）
- UI テストの設計書（`designs/2026-10-03-android-c-abi-ui-test-design.md`）への追記（足したケースと直した文言。`TagInventoryTest` が元にする 5.1 と 6 章を含む）。計画 8 章では変更に挙げたが、1b の実装の全体が固まる T-23 でまとめて行う（レビュー I-C3）
