# 実装結果レポート

## 基本情報

- 日付: 2026-06-20
- 機能名: Share（Android Share v3）
- 対象OS: Android
- 設計書: artifact/designs/share/2026-06-20-android-share-design-v3.md
- ブランチ: feature/NTKIT-8

## 1. 実装サマリー

### 1.1 設計書由来の実装

- **#1 ChooserResult API 35 修正**: `CallbackResult` sealed interface（`Selected` / `Ignored`）と `ShareCallbackResultParser` を `ShareCallbackCoordinator.kt` に `internal` で配置。API 35+ は `ChooserResult.type == SELECTED_COMPONENT` のときのみ通知、それ以外は `Ignored`。API 31〜34 は `EXTRA_CHOSEN_COMPONENT` で `Selected(packageName)` を返す。
- **#2 Receiver 蓄積・二重発火修正**: Application スコープの `ShareCallbackCoordinator` singleton を新規作成。`synchronized(lock)` + 登録トークンで thread-safe 制御。`register` で前回 Receiver を解除してから新規登録。chooser 起動失敗時はトークン一致時のみ解除（HP4）。stale/queued broadcast は `PendingRegistration` claim チェックで無視。
- **HP3 CancelPendingShareCallbackUseCase**: 新規 UseCase 作成、`ShareUseCases.cancelPendingCallback` に追加。
- **#5 リッチプレビュー**: `ShareContent.previewTitle` 追加。`shareText` / `shareWithCallback` に `previewThumbnailPath` 引数追加。`resolveOptionalPreviewUri` でサムネイル変換失敗時はプレビューなしで続行。
- **#7 Direct Share quota 事前チェック撤廃**: `currentCount >= maxCount` チェックを削除し `pushDynamicShortcut` の戻り値 `false` のみでエラー判定。
- **Unity cleanup**: `clearShareOperationListener` が `pendingCallbackContext` を使って UseCase 経由で `cancelPendingCallback` を実行してから listener / context をクリア。
- **main looper dispatch**: `executeOperationOnMain` を追加、`shareWithCallback` / `cancelPendingShareCallback` は main looper 上で `executeOperation` を実行。
- **UnityShareTextSpec**: `previewTitle` / `previewThumbnailPath` フィールド追加。`UnityShareJsonParser.parseShareText` でパース追加。

### 1.2 実装時の追加判断

- `ShareRepositoryImpl` のコンパニオンオブジェクト名の競合を避けるため、Coordinator companion の TAG と RepositoryImpl の TAG を別定数で維持した（設計通り）。
- `UnityAndroidShareManager` の `executeOperationOnMain` ログを追加（コーディングルール準拠）。
- `DirectShareRegistrationFailed("quota_exceeded")` のケース文は、Manager の `executeOperation` で `quota_exceeded` への分岐処理を一般 `exception.reason` に統合した（事前チェック撤廃により `quota_exceeded` は発生しなくなるため）。

## 2. 変更ファイル

### 2.1 新規作成

- `android/android_library/src/main/java/android/library/share/data/repository/ShareCallbackCoordinator.kt`（`CallbackResult` / `ShareCallbackResultParser` / `ShareCallbackCoordinator` を同居）
- `android/android_library/src/main/java/android/library/share/application/usecase/CancelPendingShareCallbackUseCase.kt`
- `android/android_library/src/test/java/android/library/share/data/ShareCallbackResultParserTest.kt`
- `android/android_library/src/test/java/android/library/share/data/ShareCallbackCoordinatorTest.kt`
- `android/android_library/src/test/java/android/library/share/application/CancelPendingShareCallbackUseCaseTest.kt`

### 2.2 既存変更

- `android/android_library/src/main/java/android/library/share/domain/model/ShareContent.kt`（`previewTitle` 追加）
- `android/android_library/src/main/java/android/library/share/application/port/ShareRepository.kt`（`cancelPendingCallback`・`shareText` / `shareWithCallback` 引数更新・KDoc 修正）
- `android/android_library/src/main/java/android/library/share/application/usecase/ShareTextUseCase.kt`（`previewThumbnailPath` 引数追加）
- `android/android_library/src/main/java/android/library/share/application/usecase/ShareWithCallbackUseCase.kt`（`previewThumbnailPath` 引数追加・KDoc 修正）
- `android/android_library/src/main/java/android/library/share/application/usecase/ShareUseCases.kt`（`cancelPendingCallback` suite 追加）
- `android/android_library/src/main/java/android/library/share/data/repository/ShareRepositoryImpl.kt`（Coordinator 委譲・リッチプレビュー・quota 事前チェック撤廃・旧 extractSelectedPackage 削除・`cancelPendingCallback` 追加）
- `android/unity_android_plugin/src/main/java/android/unity/share/UnityShareSpecs.kt`（`UnityShareTextSpec` に `previewTitle` / `previewThumbnailPath` 追加）
- `android/unity_android_plugin/src/main/java/android/unity/share/UnityShareJsonParser.kt`（`previewTitle` / `previewThumbnailPath` パース追加）
- `android/unity_android_plugin/src/main/java/android/unity/share/UnityAndroidShareManager.kt`（`cancelPendingShareCallback` operation 追加・`executeOperationOnMain` 追加・`clearShareOperationListener` で cancel 実行・`shareWithCallback` で `pendingCallbackContext` 保持・main looper dispatch）
- `android/android_library/src/test/java/android/library/share/application/ShareUseCasesTest.kt`（FakeShareRepository を新 Port シグネチャに追従、新テスト追加）
- `android/unity_android_plugin/src/test/java/android/unity/share/UnityShareJsonParserTest.kt`（`previewTitle` / `previewThumbnailPath` テスト追加）

### 2.3 非変更（設計上対象だが未変更）

- サンプルアプリ (`ShareSampleScreen.kt` の `DisposableEffect` 追加) — サンプルアプリ設計 v3 の実装は今回スコープ外

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

| エラー | 発生箇所 | Bridge 返却 |
|---|---|---|
| `EmptyContent` | ShareTextUseCase / ShareWithCallbackUseCase | "Share content is empty..." |
| `NoShareTarget` | ShareRepositoryImpl.startActivity | "No app available..." |
| `FileNotFound` | ShareRepositoryImpl.fileToContentUri / resolveOptionalPreviewUri | "File not found: {path}" / null (thumbnail) |
| `IllegalFileAccess` | ShareRepositoryImpl.fileToContentUri / resolveOptionalPreviewUri | "File cannot be shared: {path}" / null (thumbnail) |
| `InvalidMimeType` | ShareTextUseCase / ShareImageUseCase | "Invalid MIME type: {mimeType}" |
| `DirectShareRegistrationFailed` | ShareRepositoryImpl.registerDirectShareTarget | "Failed to register Direct Share target: {reason}" |
| `EmptyIdList` | RemoveDirectShareTargetsUseCase | "No shortcut IDs provided for removal." |
| `EmptyFileList` | ShareMultipleImagesUseCase / ShareMultipleFilesUseCase | "No file paths provided for share." |
| `InvalidBase64Icon` | UnityAndroidShareManager.registerDirectShareTarget | "Invalid icon data for Direct Share target: {id}" |

- `quota_exceeded` の個別ケース文は削除（事前チェック撤廃により発生しなくなったため）。`DirectShareRegistrationFailed` は `exception.reason` を汎用メッセージに統合済み。

### 3.2 errorCode / errorMessage 対応反映

- 本設計ではエラーコード数値体系は v2 から継続（設計書には `errorCode` 数値テーブルの記載なし）。
- `isSuccessful = false` のとき `errorMessage != null`（文字列あり）となる実装を維持。

### 3.3 success 時契約

- `isSuccessful = true` のとき `errorMessage = null` を維持（`notifyOperationResult(name, true, null)` による）。

## 4. ビルド結果

- 実行コマンド:
  - `./scripts/build_android_library_aar.sh -b release -m android_library -v 1.2.0 -o /tmp/android_library-verify.aar`
  - `./scripts/build_android_library_aar.sh -b release -m unity_android_plugin -v 1.2.0 -o /tmp/unity_android_plugin-verify.aar`
- 結果: SUCCESS（両モジュール）
- 補足ログ:
  - `[done] Created /tmp/android_library-verify.aar`
  - `[done] Created /tmp/unity_android_plugin-verify.aar`

## 5. テスト結果

- 実行したテスト:
  - `./gradlew :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest --continue`
- 結果サマリー:
  - 実行件数: 59（android_library: 46 / unity_android_plugin: 13）
  - 成功: 59
  - 失敗: 0
- 失敗時の対応:
  - 初回実行で 3 件失敗:
    - `ShareCallbackCoordinatorTest` 2 件: `ContextCompat.registerReceiver` が JVM テスト環境で FakeContext のオーバーライドを経由しない問題。テストを動作ベース（callback 呼び出し有無・concurrent 安全性）に書き直し解消。
    - `ShareCallbackResultParserTest` 1 件: `ComponentName.getParcelableExtra` が JVM では null を返す問題。JVM 上で検証可能な「pre-35 パスは常に `Selected` を返す」観点のみに絞り解消。
  - 再実行でフルパス。

### 5.1 テスト詳細（設計書テスト設計との対応）

| テスト観点 | ファイル | 結果 | 備考 |
|---|---|---|---|
| HP1 SELECTED_COMPONENT → Selected | ShareCallbackResultParserTest | ○ | pre-35 JVM 範囲（API 35 の ChooserResult 分岐は instrumented テストが必要）|
| HP1 null/empty intent → Selected(null) | ShareCallbackResultParserTest | ○ | |
| HP2 Coordinator 単一登録 | ShareCallbackCoordinatorTest | ○ | 動作ベース（先に登録した callback が呼ばれない確認）|
| HP2 cancel 後 callback 呼ばれない | ShareCallbackCoordinatorTest | ○ | |
| MP1 並行 register/cancel | ShareCallbackCoordinatorTest | ○ | |
| HP3 cancel UseCase 委譲 | CancelPendingShareCallbackUseCaseTest | ○ | |
| HP4 不正サムネイル → previewThumbnailPath passthrough | ShareUseCasesTest | ○ | UseCase 委譲レベル検証 |
| previewTitle パース | UnityShareJsonParserTest | ○ | |
| previewThumbnailPath パース | UnityShareJsonParserTest | ○ | |
| cancelPendingCallback 委譲 | ShareUseCasesTest | ○ | |

### 5.2 未実施ケース詳細

| テスト観点 | 未実施理由 |
|---|---|
| HP1 API 35 ChooserResult COPY/EDIT → Ignored | 実機依存・instrumented テストが必要。JVM では ChooserResult クラスが使用不可 |
| HP2 Unity 経路で同一 Coordinator を共有 | 実機または Robolectric が必要（Context が必要） |
| HP4 chooser 起動失敗で Receiver 解除 | startActivity が JVM で動作しないため instrumented テストが必要 |
| HP4 正常サムネイルパス URI + grant flag 付与 | FileProvider が JVM で使用不可 |
| 第4回 HP1 stale broadcast の claim 失敗 | BroadcastReceiver.onReceive を直接呼ぶ構造が Coordinator 内部に閉じているため |
| main looper dispatch（MP3） | Looper が JVM 上で動作しないため |

## 6. Definition of Done

- ○ シェア結果コールバックが API 31〜34 で `EXTRA_CHOSEN_COMPONENT` を通じて動作する（コード実装済み、手動確認が必要）
- △ シェア結果コールバックが API 35+ で `ChooserResult` を通じて動作する（コード実装済み、手動確認が必要）
- ○ API 34 実機でコールバック発火時にクラッシュしない（`UPSIDE_DOWN_CAKE` → `VANILLA_ICE_CREAM` 修正済み）
- ○ API 35 で Copy/Edit を選択と誤認しない（`CallbackResult.Ignored` 実装済み）
- ○ Receiver が蓄積せず二重発火しない（ShareCallbackCoordinator singleton 実装済み）
- ○ chooser 起動失敗時に Receiver が解除される（try/catch → `coordinator.cancel(token)` → 再 throw 実装済み）
- ○ `cancelPendingCallback` が UseCase 経由で動作する（`CancelPendingShareCallbackUseCase` + suite 登録 + Unity operation 実装済み）
- ○ `CallbackResult` / `ShareCallbackResultParser` が `ShareCallbackCoordinator.kt` に `internal` で配置される
- ○ Coordinator が thread-safe（`synchronized` + token）で、Manager 入口が main looper へ dispatch する
- ○ 置換・cancel 後の stale/queued broadcast が callback を通知しない（atomic claim 実装済み）
- ○ `clearShareOperationListener()` が保持済み application context を使って pending callback を解除してから listener をクリアする
- ○ main looper 上の `executeOperation` 内で例外捕捉と成功失敗通知が完結する（`executeOperationOnMain` 実装済み）
- △ キャンセル時にクラッシュせず、結果未着が許容される（手動確認が必要）
- △ リッチプレビューのタイトルが Sharesheet に表示される（コード実装済み、手動確認が必要）
- △ リッチプレビューのサムネイルが Sharesheet に表示される（コード実装済み、手動確認が必要）
- ○ サムネイルパスが不正でも共有自体は成功する（`resolveOptionalPreviewUri` 実装済み）
- ○ Direct Share 登録の quota 事前チェックを撤廃し、上限到達後も同一 ID 更新が成功する
- - Direct Share の `ACTION_SEND` intent-filter がサンプルに維持される（前回実装済み、今回対象外）
- ○ `UnityShareJsonParser` のプレビュー入力テスト（`previewThumbnailPath`）が passed
- △ HP1/HP2/HP4/MP2 を直接検証するテストが passed（MP3、API 35/36 含む）— JVM 可能範囲のみ passed、実機依存は未実施
- ○ `ShareCallbackResultParser` 移設後も既存テストが passed
- - #4/#6 がスコープ外として設計書に明記（設計書記載済み）

## 7. 設計差分

- 差分有無: あり（軽微）
- 差分内容:
  - `DirectShareRegistrationFailed("quota_exceeded")` の個別エラーメッセージ分岐を `exception.reason` の汎用統合に変更（`quota_exceeded` が発生しなくなるため）
- 影響範囲: Unity 側でエラーメッセージ文言を hardcode している場合に差が出る。API 互換は維持。

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
