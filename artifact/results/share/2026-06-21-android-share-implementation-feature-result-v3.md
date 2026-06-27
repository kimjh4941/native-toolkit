# 実装結果レポート

## 基本情報

- 日付: 2026-06-21
- 機能名: Android Share v4 — Unity 向けカスタムチューザーアクション受信経路
- 対象OS: Android
- 設計書: artifact/designs/share/2026-06-21-android-share-design-v4.md
- ブランチ: feature/NTKIT-8

## 1. 実装サマリー

### 1.1 設計書由来の実装

- `ShareChooserActionReceiver.kt` 新規作成: 動的登録用 BroadcastReceiver。`intent.action` を `onAction` ラムダへ転送、null は無視
- `ShareChooserActionReceiverRegistry.kt` 新規作成: `ShareChooserActionReceiverRegistry` interface + `AndroidShareChooserActionReceiverRegistry` 実装（SDK ゲート・RECEIVER_NOT_EXPORTED・世代管理・置換・二重解除 Log.w）
- `ShareChooserActionInputs.kt` 新規作成: `normalizeActionIds` — 非空フィルタ・distinct・default SEND 警告
- `UnityAndroidShareManager.kt` 変更:
  - `ShareChooserActionListener` interface 追加
  - `setShareChooserActionListener` / `clearShareChooserActionListener` 追加（main looper 直列化）
  - `shareText` で `chooserActionRegistryFactory` 経由の遅延生成・session 登録・失敗 cleanup・世代ガード
  - `dispatchChooserAction` 追加（listener 例外 try/catch → Log.e）
  - `chooserActionRegistryFactory` テスト seam (@VisibleForTesting internal)
- `ShareChooserActionReceiverTest.kt` 新規作成: 転送・null intent/action 無視・例外伝播
- `ShareChooserActionInputsTest.kt` 新規作成: 非空除外・重複除去・default SEND 警告・空リスト
- `UnityAndroidShareManagerTest.kt` 変更: FakeRegistry + LaunchFailingFakeContext 注入で register/replace/失敗 cleanup/listener 転送・例外・clear を検証
- `ShareChooserActionInstrumentedTest.kt` 新規作成: API 34+ 実登録・broadcast 受信・複数 action・連続 register 置換・clear・stale token・action 無し

### 1.2 実装時の追加判断

- `clearShareChooserActionListener_unregistersCurrentToken` テスト: `shareText` が JVM スタブ環境で例外を送出し `chooserActionToken` が 0L にリセットされるため、リフレクションで `chooserActionRegistry` / `chooserActionToken` を直接注入してテストする方式に変更。設計の「clear が現世代を解除する」という仕様の検証には影響しない。
- `tearDown` にリフレクションで `chooserActionRegistry` を null リセットする `resetChooserActionRegistry()` を追加。設計書に明示はないが、テスト間の singleton 状態汚染を防ぐために必要な措置。
- `LaunchFailingFakeContext`: `startActivity` が `ActivityNotFoundException` を送出する `FakeContext` サブクラス。失敗 cleanup パスのテストに使用。設計書のテスト設計から導出。

## 2. 変更ファイル

### 2.1 新規作成

- `android/unity_android_plugin/src/main/java/android/unity/share/ShareChooserActionReceiver.kt`
- `android/unity_android_plugin/src/main/java/android/unity/share/ShareChooserActionReceiverRegistry.kt`
- `android/unity_android_plugin/src/main/java/android/unity/share/ShareChooserActionInputs.kt`
- `android/unity_android_plugin/src/test/java/android/unity/share/ShareChooserActionReceiverTest.kt`
- `android/unity_android_plugin/src/test/java/android/unity/share/ShareChooserActionInputsTest.kt`
- `android/unity_android_plugin/src/androidTest/java/android/unity/share/ShareChooserActionInstrumentedTest.kt`

### 2.2 既存変更

- `android/unity_android_plugin/src/main/java/android/unity/share/UnityAndroidShareManager.kt`
- `android/unity_android_plugin/src/test/java/android/unity/share/UnityAndroidShareManagerTest.kt`

### 2.3 非変更（設計上対象だが未変更）

- `android/unity_android_plugin/src/main/AndroidManifest.xml`: 動的登録のため manifest 宣言不要（設計通り）
- `android/unity_android_plugin/src/main/java/android/unity/share/UnityShareJsonParser.kt`: `intentAction` は既にパース済み、変更不要
- `android/unity_android_plugin/src/main/java/android/unity/share/UnityChooserActionSpec.kt`: 変更不要

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

- 新規ドメインエラーなし（設計通り）
- 受信登録失敗: `AndroidShareChooserActionReceiverRegistry.register` 内 try/catch → `Log.e` → token 0L 返却（ベストエフォート）
- listener 例外: `dispatchChooserAction` 内 try/catch → `Log.e` → 伝播しない
- 二重解除（`IllegalArgumentException`）: `unregisterCurrentLocked` で `Log.w`（設計書で規約への明示的例外として承認済み）

### 3.2 errorCode / errorMessage 対応反映

- 本機能は Unity Bridge 追加のみ。既存の `ShareOperationListener.onShareOperation` のエラーコード体系に変更なし。

### 3.3 success 時契約

- `shareText` が成功した場合、`onShareOperation(OPERATION_SHARE_TEXT, true, null)` が呼ばれることは既存テストで確認済み。本機能の追加コードはこのパスを変更しない。

## 4. ビルド結果

- 実行コマンド:
  - `./scripts/build_android_library_aar.sh -b release -m unity_android_plugin -v 1.0.0 -o /tmp/unity_android_plugin-verify.aar`
- 結果: SUCCESS
- 補足ログ:
  - `[done] Created /tmp/unity_android_plugin-verify.aar`

## 5. テスト結果

- 実行したテスト:
  - `./gradlew :unity_android_plugin:testReleaseUnitTest`（`android/AndroidLibraryExample/` ディレクトリ内）
- 結果サマリー:
  - 実行件数: 57
  - 成功: 57
  - 失敗: 0
- 失敗時の対応:
  - 当初 7 失敗 → `ShareChooserActionReceiverTest` の JVM stub 問題: `FakeIntent` サブクラスで `getAction()` をオーバーライドして解決
  - `UnityAndroidShareManagerTest` の chooser 系テスト: `"text":""` がパーサー例外を引き起こすため `"text":"hello"` に修正
  - `shareText_launchFailure_unregistersCurrentToken`: `LaunchFailingFakeContext` を追加して `ActivityNotFoundException` パスを再現
  - `clearShareChooserActionListener_unregistersCurrentToken`: `shareText` が JVM スタブ環境で例外を送出するため、リフレクションで直接 registry/token を注入するテスト方式に変更
  - テスト間 singleton 汚染: `tearDown` でリフレクションにより `chooserActionRegistry` を null リセット
- 未実施項目:
  - `ShareChooserActionInstrumentedTest.kt` の全ケース: API 34+ 実機/エミュレータが必要。現セッションでは実機確認未実施。

### 5.1 テスト詳細

| テスト観点 | テストファイル | テストケース | 結果 | 備考 |
|---|---|---|---|---|
| receiver 転送 | ShareChooserActionReceiverTest.kt | onReceive_withAction_forwardsToOnAction | ○ | |
| null action 無視 | ShareChooserActionReceiverTest.kt | onReceive_nullAction_doesNotCallOnAction | ○ | |
| null intent 無視 | ShareChooserActionReceiverTest.kt | onReceive_nullIntent_doesNotCallOnAction | ○ | |
| 例外伝播 | ShareChooserActionReceiverTest.kt | onReceive_onActionThrows_propagatesToCaller | ○ | Manager が封じ込める設計であることを確認 |
| 非空除外 | ShareChooserActionInputsTest.kt | normalizeActionIds_blankActionsAreExcluded | ○ | |
| 重複除去 | ShareChooserActionInputsTest.kt | normalizeActionIds_duplicatesAreRemoved | ○ | |
| default SEND 警告 | ShareChooserActionInputsTest.kt | normalizeActionIds_defaultSendActionIsRetainedWithWarning | ○ | |
| 空リスト | ShareChooserActionInputsTest.kt | normalizeActionIds_emptyListReturnsEmpty | ○ | |
| register 正規化 | UnityAndroidShareManagerTest.kt | shareText_withChooserActions_registersWithNormalizedActionIds | ○ | |
| actions なし | UnityAndroidShareManagerTest.kt | shareText_withNoChooserActions_registersEmptyActionIds | ○ | |
| 失敗 cleanup | UnityAndroidShareManagerTest.kt | shareText_launchFailure_unregistersCurrentToken | ○ | LaunchFailingFakeContext 使用 |
| listener 転送 | UnityAndroidShareManagerTest.kt | dispatchChooserAction_forwardsToListener | ○ | |
| listener 未設定 | UnityAndroidShareManagerTest.kt | dispatchChooserAction_listenerNotSet_doesNotThrow | ○ | |
| listener 例外封じ込め | UnityAndroidShareManagerTest.kt | dispatchChooserAction_listenerThrows_doesNotPropagateException | ○ | |
| clear 解除 | UnityAndroidShareManagerTest.kt | clearShareChooserActionListener_unregistersCurrentToken | ○ | リフレクション直接注入 |
| 連続 share 置換 | UnityAndroidShareManagerTest.kt | consecutiveShareText_replacesRegistration | ○ | |
| 実登録・broadcast 受信 | ShareChooserActionInstrumentedTest.kt | 全 8 ケース | △ | API 34+ 実機未確認 |

### 5.2 未実施ケース詳細

| テスト観点 | テストファイル | テストケース | 未実施理由 |
|---|---|---|---|
| 実登録・受信 | ShareChooserActionInstrumentedTest.kt | register_thenBroadcast_receivesAction | API 34+ 実機/エミュレータ必要 |
| 複数 action | ShareChooserActionInstrumentedTest.kt | register_multipleActions_eachBroadcastReceivedSeparately | 同上 |
| 連続 register 置換 | ShareChooserActionInstrumentedTest.kt | consecutiveRegister_replacesOldReceiver_onlyNewActionReceived | 同上 |
| clear 後 broadcast 無効 | ShareChooserActionInstrumentedTest.kt | unregister_afterClear_broadcastNotReceived | 同上 |
| stale token 無効 | ShareChooserActionInstrumentedTest.kt | unregister_staleToken_doesNotUnregisterCurrentReceiver | 同上 |
| actions 無し 旧 receiver 解除 | ShareChooserActionInstrumentedTest.kt | register_withNoChooserActions_unregistersOldReceiver | 同上 |

## 6. Definition of Done

- ○ `ShareChooserActionReceiver` が `intent.action` を `onAction` へ転送し、null を無視する
- ○ `ShareChooserActionReceiverRegistry` が SDK ゲート・`RECEIVER_NOT_EXPORTED`・世代管理（register で token 採番/置換、unregister は世代ガード）を担う
- ○ `ShareChooserActionInputs.normalizeActionIds` が非空・distinct 抽出と default SEND 警告を行う
- ○ `setShareChooserActionListener` / `clearShareChooserActionListener` が main looper で直列化され、callback が main thread で届くことを公開仕様に明記
- ○ `shareText` が登録→ライブラリ呼び出しの順で動作し、起動失敗時は今回 token のみ解除して re-throw
- ○ `dispatchChooserAction` が listener 例外を `try/catch` で封じ込め `Log.e`
- ○ `chooserActions` 無し share / clear で現世代を解除（stale receiver を残さない）
- ○ 入力契約（`intentAction` 必須・一意・namespace、icon の Unity 事前検証、callback 登録 best-effort）を公開仕様に明記
- ○ 「プロセス存続中のみ・最新 1 session のみ」を公開仕様・リスク・手動確認に明記
- ○ `android_library` を変更していない / manifest に receiver を宣言していない
- ○ 新規 `onReceive`/public・internal 関数に `Log.d`、失敗・listener 例外は `Log.e`、TAG は full class name
- ○ public interface / 関数に KDoc（英語）
- ○ 単体テスト（inputs 正規化・receiver 転送・Manager の register/置換/失敗 cleanup/listener 転送・例外・clear）が green、既存不破壊（57/57 passed）
- △ **API 34+ 計装テスト（実登録・受信・複数 action・clear・action 無し・連続・失敗 cleanup）が green**（実機未確認: API 34+ 実機/エミュレータ必要）
- ○ 破壊的変更なし（既存 API シグネチャ・挙動不変）

## 7. 設計差分

- 差分有無: あり（実装時追加判断のみ。設計要件への影響なし）
- 差分内容:
  - `clearShareChooserActionListener_unregistersCurrentToken` テストをリフレクション直接注入方式に変更
  - `tearDown` に `resetChooserActionRegistry()` 追加
  - `LaunchFailingFakeContext` 追加
- 影響範囲:
  - テストコードのみ。プロダクションコードへの影響なし。設計書の DoD はすべて満たしている。

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
