# Android Share v3 実装レビュー v1

## 基本情報

- 日付: 2026-06-20
- 対象OS: Android
- 対象ブランチ: `feature/NTKIT-8`
- 設計書: `artifact/designs/share/2026-06-20-android-share-design-v3.md`
- 実装結果: `artifact/results/share/2026-06-20-android-share-implementation-feature-result-v1.md`
- レビュー範囲: 実装結果レポートに記載された Android Share v3 の未コミット差分

## レビュー概要

API 35 の結果判定、application スコープ Coordinator、起動失敗時の token 指定解除、リッチプレビュー、quota 事前チェック撤廃は概ね設計方針に沿って実装されている。単体テストも強制再実行で全件成功した。

一方、公開 API の JVM シグネチャを壊す変更が minor version のまま導入されており、実装結果レポートの「API 互換は維持」と一致しない。また、Direct Share 登録時のプラットフォーム例外変換が設計どおり実装されていない。主要な競合条件を検証するとされる Coordinator テストにも実効的な assertion がなく、現状では採用不可と判断する。

## 重大な問題（high）

### 1. 公開 API の JVM バイナリ互換性が壊れている

対象:

- `android/android_library/src/main/java/android/library/share/application/port/ShareRepository.kt:23-27,85-94`
- `android/android_library/src/main/java/android/library/share/application/usecase/ShareTextUseCase.kt:21-29`
- `android/android_library/src/main/java/android/library/share/application/usecase/ShareWithCallbackUseCase.kt:23-30`
- `android/android_library/src/main/java/android/library/share/domain/model/ShareContent.kt:12-17`
- `android/AndroidLibraryExample/gradle.properties:25-26`
- `artifact/results/share/2026-06-20-android-share-implementation-feature-result-v1.md:160-165`

`shareText` と `shareWithCallback` にデフォルト引数を追加しているが、Kotlin のデフォルト引数は既存 JVM descriptor の overload を自動保持しない。既存 AAR に対してコンパイル済みの利用側は、旧 descriptor を呼び出して `NoSuchMethodError` になる。`ShareContent` の primary constructor へのプロパティ追加も constructor / `copy` の ABI を変更する。さらに、公開 interface への抽象メソッド `cancelPendingCallback` 追加は外部実装を破壊する。

実装結果は「API 互換は維持」としており、version も `1.2.0` の minor 更新であるため、この状態はリリース契約と一致しない。旧シグネチャを明示的な overload として残し、新機能へ委譲する必要がある。interface の追加メソッドには既定実装を持たせるか、外部実装を非サポートと明記した major version 更新が必要である。`ShareContent` は既存 constructor ABI を保てる別 options 型等へ分離するか、major version 更新として扱うこと。

### 2. Direct Share 登録時のシステム例外が DomainError に変換されない

対象:

- `android/android_library/src/main/java/android/library/share/data/repository/ShareRepositoryImpl.kt:101-121`
- `artifact/designs/share/2026-06-20-android-share-design-v3.md:595-602`
- `agent-rules/coding-rules/common.md:130-136`

設計では `pushDynamicShortcut` の戻り値 `false` に加え、`IllegalArgumentException` 等も `DirectShareRegistrationFailed(reason)` へ変換する。しかし実装は `false` のみを変換し、`ShortcutInfoCompat.Builder.build()` や `pushDynamicShortcut()` が投げるプラットフォーム例外をそのまま外へ漏らす。

その結果、native library 利用時は DomainError 契約を満たさず、Unity 経路でも `DirectShareRegistrationFailed` 専用メッセージではなく汎用例外処理へ流れる。対象 API 呼び出しを捕捉し、原因を保持した `DirectShareRegistrationFailed` へ正規化すること。併せて例外経路のテストを追加すること。

## 改善提案（medium）

### 1. Coordinator テストが stale / cancel / 置換の動作を検証していない

対象:

- `android/android_library/src/test/java/android/library/share/data/ShareCallbackCoordinatorTest.kt:31-44`
- `android/android_library/src/test/java/android/library/share/data/ShareCallbackCoordinatorTest.kt:53-75`
- `android/android_library/src/test/java/android/library/share/data/ShareCallbackCoordinatorTest.kt:109-153`
- `artifact/designs/share/2026-06-20-android-share-design-v3.md:621-645`

`cancelWithStaleToken...` は `received` を一度も assertion していない。`register_twice...` は broadcast を配送せず、登録直後に first callback が 0 である自明な事実だけを確認している。cancel テストも解除前の Receiver を保持して遅延配送していないため、atomic claim の成否を通過しない。

FakeContext が登録履歴を保持し、旧 Receiver を明示的に呼べる構造にして、少なくとも以下を assertion すること。

- stale token の cancel 後は現在の callback が 1 回呼ばれる
- 置換後に旧 Receiver を呼んでも旧 callback は 0 回、新 Receiver は 1 回
- cancel 後に保存済み Receiver を呼んでも callback は 0 回
- 1 回受信後の再配送でも callback は合計 1 回

### 2. 設計で必須とした主要テストが未実施のまま DoD を満たした扱いになっている

対象:

- `artifact/designs/share/2026-06-20-android-share-design-v3.md:647-653,686-708`
- `artifact/results/share/2026-06-20-android-share-implementation-feature-result-v1.md:124-156`

API 35 の Copy/Edit/Unknown、Unity 経路の Coordinator 共有、chooser 起動失敗時の解除、preview URI grant、main looper dispatch が未検証である。設計は API 依存部分を unit または instrumented test で直接検証し、API 34/35/36 の統合テストを行うとしているため、結果レポートの複数の DoD `○` はコード存在の確認に留まり、完了条件を満たしていない。

Robolectric または instrumented test を追加し、少なくとも設計上の HP1 / HP2 / HP4 / MP2 / MP3 を直接通すこと。実施できない項目は DoD を `△` または未完了のままにすること。

### 3. pendingCallbackContext が失敗・明示 cancel 後に残る

対象:

- `android/unity_android_plugin/src/main/java/android/unity/share/UnityAndroidShareManager.kt:210-243`

`pendingCallbackContext` は JSON parse より前に設定され、選択 callback または `clearShareOperationListener` でしか null にならない。JSON parse / chooser 起動失敗、Copy/Edit/Cancel、`cancelPendingShareCallback` の明示呼び出しでは application context が残る。Activity leak ではないが、pending callback が存在しない状態でも pending 所有状態だけが残り、後続 cleanup が不要な cancel を行う。

登録成功後にだけ保持する、失敗時に `finally` 相当で解除する、明示 cancel 時にも context を null にする、のいずれかで状態を Coordinator と一致させること。成功通知と選択結果通知の境界も含めて manager test を追加すること。

## 軽微な指摘（low）

### 1. 既存テスト名が新しいキャンセル契約と矛盾している

対象:

- `android/android_library/src/test/java/android/library/share/application/ShareUseCasesTest.kt:181-188`

`shareWithCallback_cancelledByUser_callsOnResultWithNull` は、現在の KDoc にある「Cancel は onResult を呼ばない」という契約と逆である。この FakeRepository の `null` は「選択されたが package name を取得できない」ケースとして命名し直し、キャンセルは Coordinator / instrumented test で callback なしを検証すること。

### 2. 実装結果レポートの変更ファイル一覧に version 変更がない

対象:

- `android/AndroidLibraryExample/gradle.properties:25-26`
- `artifact/results/share/2026-06-20-android-share-implementation-feature-result-v1.md:30-52`

`libraryVersion=1.2.0` への変更がレポートに記載されていない。採用判断に影響するため、変更理由と互換性方針を含めて追記すること。

## 設計書整合性チェック

| 項目 | 判定 | コメント |
|---|---|---|
| API 35 `ChooserResult.type` 判定 | ○ | `Selected` / `Ignored` の分離は設計どおり |
| application スコープ Coordinator | ○ | singleton + token + atomic claim を実装 |
| chooser 起動失敗時の token 指定解除 | ○ | catch 内で `cancel(token)` を実行 |
| 明示 cancel UseCase | ○ | Port / UseCase / suite / Unity operation を追加 |
| リッチプレビュー | ○ | title、thumbnail URI、read grant、invalid path fallback を実装 |
| Direct Share quota 事前チェック撤廃 | △ | 事前チェックは撤廃済みだが例外変換が不足 |
| 主要修正点の直接テスト | × | 設計指定ケースの多くが未実施、既存 Coordinator テストも核心を通らない |
| API 互換性 | × | 結果レポートの記述と公開 JVM ABI が不一致 |

## プロジェクトルール適合チェック

| 項目 | 判定 | コメント |
|---|---|---|
| Clean Architecture の呼び出し経路 | ○ | Manager → UseCase → Repository を維持 |
| Domain / Application への platform 型流入 | ○ | `String?` 等の plain type で受け渡し |
| システムエラーの DomainError 変換 | × | Direct Share 登録の例外が変換されない |
| KDoc | ○ | 追加・変更された主要 public API に記載あり |
| Log.d | △ | 主要メソッドには存在するが、今回の重大事項を優先し詳細な全メソッド監査は未実施 |
| テスト方針 | × | 修正点を直接検証する assertion / 統合テストが不足 |

## テストカバレッジ

- 実行: `JAVA_HOME='/Applications/Android Studio Panda 1 .app/Contents/jbr/Contents/Home' ./gradlew :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest --continue --rerun-tasks`
- 結果: `BUILD SUCCESSFUL`（30 tasks executed）
- 静的確認: `git diff --check` 成功
- 残存リスク: API 35/36 callback、実 Receiver の置換・遅延配送、chooser 起動失敗、FileProvider URI grant、Unity main looper dispatch は未検証

テストは green だが、重要な仕様を通っていないため品質ゲートとしては不十分である。

## 総合評価

**要修正（重大）**

公開 API の互換性方針を確定して ABI を修正し、Direct Share の例外変換を設計契約へ合わせる必要がある。その後、Coordinator の実効的な競合テストと API 依存ケースの自動テストを追加して再レビューすること。
