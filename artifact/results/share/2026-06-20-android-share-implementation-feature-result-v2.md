# 実装結果レポート

## 基本情報

- 日付: 2026-06-20
- 機能名: Share（Android Share v3 レビュー指摘修正）
- 対象OS: Android
- 設計書: `artifact/designs/share/2026-06-20-android-share-design-v3.md`
- レビュー: `artifact/reviews/share/2026-06-20-android-share-implementation-feature-review-v1.md`
- ブランチ: `feature/NTKIT-8`

## 1. 実装サマリー

### 1.1 設計書由来の実装

- API 35 の `ChooserResult` を `Selected` / `Ignored` に分離し、Copy / Edit / Unknown を通知対象外とした。
- application スコープの `ShareCallbackCoordinator` で Receiver を単一所有し、token と receiver identity による atomic claim を維持した。
- rich preview の title / thumbnail path を `SharePreviewOptions` として UseCase から Repository へ渡す。
- chooser 起動失敗時の token 指定解除、明示 cancel UseCase、Direct Share quota 事前チェック撤廃を維持した。

### 1.2 実装時の追加判断

- 既存 JVM ABI を保持するため、既存 `ShareRepository` と `ShareContent` は旧シグネチャへ戻し、新機能を `RichPreviewShareRepository` / `SharePreviewOptions` に分離した。
- `ShareTextUseCase` / `ShareWithCallbackUseCase` は旧 `invoke` descriptor を残し、新 options overload を追加した。旧 Repository 実装では preview なしへ fallback する。
- Direct Share の Android API 呼び出しを内部 `DirectShareShortcutPublisher` に分離し、`false` と `RuntimeException` を `DirectShareRegistrationFailed` へ変換した。
- Coordinator の Receiver 登録を内部 registry として注入可能にし、stale / queued broadcast を JVM テストで直接配送できるようにした。
- chooser callback の terminal hook を追加し、選択だけでなく Copy / Edit / Unknown 後も Unity の pending context を解放する。起動失敗・明示 cancel 時も解放する。

## 2. 変更ファイル

### 2.1 新規作成

- `android/android_library/src/main/java/android/library/share/application/port/RichPreviewShareRepository.kt`
- `android/android_library/src/main/java/android/library/share/domain/model/SharePreviewOptions.kt`
- `android/android_library/src/main/java/android/library/share/data/repository/DirectShareShortcutPublisher.kt`
- `android/android_library/src/main/java/android/library/share/data/repository/ShareCallbackCoordinator.kt`
- `android/android_library/src/main/java/android/library/share/application/usecase/CancelPendingShareCallbackUseCase.kt`
- `android/android_library/src/test/java/android/library/share/data/ShareCallbackCoordinatorTest.kt`
- `android/android_library/src/test/java/android/library/share/data/ShareCallbackResultParserTest.kt`
- `android/android_library/src/test/java/android/library/share/data/ShareRepositoryImplTest.kt`
- `android/android_library/src/test/java/android/library/share/application/CancelPendingShareCallbackUseCaseTest.kt`

### 2.2 既存変更

- `android/AndroidLibraryExample/gradle.properties`: default version を `1.2.0` へ更新。
- `android/android_library/src/main/java/android/library/share/application/port/ShareRepository.kt`: 旧 ABI を維持。
- `android/android_library/src/main/java/android/library/share/application/usecase/ShareTextUseCase.kt`: preview options overload と旧 Repository fallback を追加。
- `android/android_library/src/main/java/android/library/share/application/usecase/ShareWithCallbackUseCase.kt`: preview options / terminal callback overload と fallback を追加。
- `android/android_library/src/main/java/android/library/share/application/usecase/ShareUseCases.kt`: cancel UseCase を追加。
- `android/android_library/src/main/java/android/library/share/data/repository/ShareRepositoryImpl.kt`: rich preview capability、例外変換、Coordinator 委譲を実装。
- `android/android_library/src/test/java/android/library/share/application/ShareUseCasesTest.kt`: options、fallback 契約、テスト名を更新。
- `android/unity_android_plugin/src/main/java/android/unity/share/UnityAndroidShareManager.kt`: options 利用、main dispatch、pending lifecycle cleanup を実装。
- `android/unity_android_plugin/src/main/java/android/unity/share/UnityShareJsonParser.kt`
- `android/unity_android_plugin/src/main/java/android/unity/share/UnityShareSpecs.kt`
- `android/unity_android_plugin/src/test/java/android/unity/share/UnityAndroidShareManagerTest.kt`: failure / cancel cleanup テストを追加。
- `android/unity_android_plugin/src/test/java/android/unity/share/UnityShareJsonParserTest.kt`

### 2.3 非変更（設計上対象だが未変更）

- サンプルアプリ v3: 別実装スコープのため非変更。

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

- `DirectShareRegistrationFailed("push_failed")`: publisher が `false` を返した場合に変換。
- `DirectShareRegistrationFailed(reason)`: publisher が `RuntimeException` を投げた場合に message または例外クラス名を reason として変換。
- `InvalidBase64Icon`: bitmap decode 失敗は従来どおり専用 DomainError を維持。
- その他の ShareDomainError は v1 の契約を変更していない。

### 3.2 errorCode / errorMessage 対応反映

- 数値 errorCode 体系は導入されていないため v1 と同じ。
- Unity では `DirectShareRegistrationFailed` を `Failed to register Direct Share target: {reason}` へ変換する。

### 3.3 success時契約

- `isSuccessful == true` の場合は `errorMessage == null` を維持。既存 Unity manager テストを含む全テストが passed。

## 4. ビルド結果

- 実行コマンド:
  - `./scripts/build_android_library_aar.sh -b release -m android_library -v 1.2.0 -o /tmp/android_library-verify.aar`
  - `./scripts/build_android_library_aar.sh -b release -m unity_android_plugin -v 1.2.0 -o /tmp/unity_android_plugin-verify.aar`
- 結果: SUCCESS
- 補足ログ:
  - `[done] Created /tmp/android_library-verify.aar`
  - `[done] Created /tmp/unity_android_plugin-verify.aar`

## 5. テスト結果

- 実行したテスト:
  - `./gradlew :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest --continue --rerun-tasks`
- 結果サマリー:
  - 実行件数: 100（android_library: 59 / unity_android_plugin: 41）
  - 成功: 100
  - 失敗: 0
- 静的確認:
  - `git diff --check`: SUCCESS
  - `javap`: `ShareRepository`、`ShareContent`、両 UseCase の旧 JVM descriptor が存在することを確認。

### 5.1 テスト詳細

| テスト観点 | テストファイル | 結果 | 備考 |
|---|---|---|---|
| stale token cancel | `ShareCallbackCoordinatorTest` | ○ | 現 callback が 1 回通知されることを確認 |
| replacement stale broadcast | `ShareCallbackCoordinatorTest` | ○ | 旧 callback 0 回、新 callback 1 回 |
| cancel 後 queued broadcast | `ShareCallbackCoordinatorTest` | ○ | 保存した旧 Receiver を直接配送して 0 回 |
| one-shot / terminal hook | `ShareCallbackCoordinatorTest` | ○ | 二重配送でも callback / finished は各 1 回 |
| API 35 result mapping | `ShareCallbackResultParserTest` | ○ | Selected / Copy / Edit / Unknown を直接検証 |
| Direct Share false / exception | `ShareRepositoryImplTest` | ○ | 両経路を DomainError へ変換 |
| Unity pending cleanup | `UnityAndroidShareManagerTest` | ○ | 起動失敗・明示 cancel で null 化 |
| preview options passthrough | `ShareUseCasesTest` / `UnityShareJsonParserTest` | ○ | title / thumbnail path を検証 |
| JVM ABI | `javap` | ○ | 旧 descriptor を bytecode で確認 |

### 5.2 未実施ケース詳細

| テスト観点 | 未実施理由 |
|---|---|
| 実 `ChooserResult` callback | `ChooserResult` に公開 constructor がなく、実 chooser 操作を伴うため API 35/36 実機確認が必要 |
| preview content URI の受信側 read | FileProvider と受信アプリを伴う instrumented / 手動確認が必要 |
| Direct Share の上限到達後同一 ID 更新 | ShortcutManager の実状態を伴う実機確認が必要 |
| Sharesheet の Copy / Edit UI 統合 | API 35/36 実機操作が必要。result type の mapping 自体は単体テスト済み |

## 6. Definition of Done

- ○ API 31〜34 の `EXTRA_CHOSEN_COMPONENT` mapping を維持。
- △ API 35+ の実 `ChooserResult` callback は mapping テスト済み、実機 UI 統合は未確認。
- ○ Copy / Edit / Unknown を `Ignored` とする判定を直接テスト。
- ○ Receiver 単一所有、置換、stale / queued broadcast、one-shot を直接テスト。
- ○ chooser 起動失敗時の token 指定解除を実装。
- ○ cancel UseCase と Unity operation を実装。
- ○ main looper dispatch と例外通知経路を維持。
- ○ pending context を selected / ignored / failure / explicit cancel で解放。
- ○ rich preview title / thumbnail options と invalid thumbnail fallback を実装。
- ○ Direct Share quota 事前チェックを撤廃し、false / exception を DomainError に変換。
- ○ 旧公開 JVM ABI を維持。
- △ API 31 / 34 / 35 / 36 の Sharesheet 実機確認は未実施。

## 7. 設計差分

- 差分有無: あり
- 差分内容:
  - 設計の `ShareContent.previewTitle` と既存 Port への引数追加は JVM ABI を破壊するため、`SharePreviewOptions` と optional capability interface へ分離した。
  - Coordinator に terminal callback を追加し、非選択 callback 後も Manager の pending state を解放する。
- 影響範囲:
  - 既存 API 利用側は再コンパイル不要。
  - 新しい rich preview API は `ShareTextUseCase` / `ShareWithCallbackUseCase` の options overload から利用する。

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して review-implementation-feature の工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 未回答
