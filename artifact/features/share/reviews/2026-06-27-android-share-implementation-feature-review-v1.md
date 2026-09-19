# Android Share v4 実装レビュー v1

## レビュー対象

- ブランチ: `feature/NTKIT-8`
- PR番号: なし（ローカル差分レビュー）
- 差分:
  - `git diff develop...HEAD`
  - 未コミット差分（`git status --short` 上の Share Chooser Action 追加分を含めて確認）
- 設計書: `artifact/designs/share/2026-06-21-android-share-design-v4.md`
- 実装結果: `artifact/results/share/2026-06-21-android-share-implementation-feature-result-v3.md`
- 対象OS: Android

## レビュー概要

Unity 向け Share Chooser Action 受信経路として、動的 `BroadcastReceiver`、registry、入力正規化、`UnityAndroidShareManager` の listener API、JVM/計装テストが追加されている。設計の主要方針（`android_library` 不変更、動的 receiver、世代 token、listener 例外封じ込め）は概ね反映されている。

一方で、設計書が必須としている入力契約・API 34+ 実経路の検証・プロジェクトルール準拠に未解消が残る。総合評価は **要修正（軽微）**。

## 重大な問題（high）

1. `android/AndroidLibraryExample/gradle.properties:26`
   `libraryVersion` が `1.2.0` から `1.0.0` に戻っている。今回の Unity Share Chooser Action 実装設計にない変更で、IDE sync / sample app build が意図せず古いライブラリを参照する可能性がある。差分から外すか、必要性を実装結果に明記して設計対象に含めるべき。

2. `android/unity_android_plugin/src/main/java/android/unity/share/UnityShareJsonParser.kt:97` / `android/unity_android_plugin/src/main/java/android/unity/share/ShareChooserActionInputs.kt:19`
   設計書は callback 利用時の `intentAction` を「必須・一意・非空」「`android.intent.action.SEND` 既定値は識別に使わない」としているが、実装は未指定時に `SEND` を補完し、normalize 側も warning のみで登録対象に残している。複数 action が `SEND` になると Unity 側で識別不能になり、設計の「タップされた actionId を返す」契約を満たせない。callback 付き chooser action では `intentAction` の未指定/default SEND/重複を失敗扱いにするか、少なくとも登録対象から除外し表示対象とも一致させる必要がある。

## 改善提案（medium）

1. `android/unity_android_plugin/src/androidTest/java/android/unity/share/ShareChooserActionInstrumentedTest.kt:57`
   計装テストは registry に直接 `sendBroadcast` しているだけで、設計書の「`shareText` 後、Sharesheet custom action の PendingIntent 経由で `UnityAndroidShareManager.ShareChooserActionListener` が発火する」経路を検証していない。`RECEIVER_NOT_EXPORTED` で PendingIntent 由来 broadcast を受信できるかも、現状は通常 broadcast の検証に留まる。設計書の必須テストとしては不足なので、Manager 経由の登録と PendingIntent 相当の発火経路を追加するべき。

2. `android/unity_android_plugin/src/androidTest/java/android/unity/share/ShareChooserActionInstrumentedTest.kt:33`
   `tearDown` が `registry.unregister(Long.MAX_VALUE)` を呼んでいるため、テスト途中で失敗した場合に現在 token と一致せず cleanup されない。各テストで保持した token を `@After` で解除できるようにし、失敗時も receiver が残らない形にするべき。

3. `android/unity_android_plugin/src/test/java/android/unity/share/UnityAndroidShareManagerTest.kt:195`
   `chooserActions` 無し share が旧 receiver を解除する DoD に対し、FakeRegistry は `register(emptyList())` の記録しか持たず、旧 token の解除/置換を検証していない。設計上の stale receiver 防止は重要なので、FakeRegistry に register 回数・unregister 相当の置換挙動を持たせるか、Manager レベルで旧 token が消えることを検証した方がよい。

4. `android/unity_android_plugin/src/main/java/android/unity/share/UnityAndroidShareManager.kt:24`
   Android ルールでは `TAG` は full class name 必須だが、`UnityAndroidShareManager` のまま。今回追加した public/internal 関数も同じ TAG を使うため、`android.unity.share.UnityAndroidShareManager` に合わせるべき。

5. `android/unity_android_plugin/src/test/java/android/unity/share/UnityAndroidShareManagerTest.kt:286`
   `clearShareChooserActionListener()` は `runOnMain` で非同期 post される可能性があるが、テストは直後に `lastUnregisteredToken` を assert している。Robolectric/JVM 環境に依存して通っているだけに見えるため、main looper を明示的に drain するか、main thread 上で実行する前提をテストに固定した方がよい。`set`/`clear` 順序競合の設計リスクに対して、現状の単体テストはやや薄い。

## 軽微な指摘（low）

1. `android/unity_android_plugin/src/main/java/android/unity/share/ShareChooserActionInputs.kt:16`
   KDoc が `@param` を省略している。internal 関数なので必須対象外だが、設計上重要な入力契約を担う関数なので、`SEND` の扱いと重複除去の意味を KDoc に残すと読み手に親切。

2. `artifact/results/share/2026-06-21-android-share-implementation-feature-result-v3.md`
   実装結果では API 34+ 計装テスト未実施を明記している一方、DoD は概ね達成済みのように読める。必須テストが未実行なら、総合の達成状況は `△` として残した方が後続レビューで誤読しにくい。

## 設計書整合性チェック

- 企画書との整合性: △（専用企画書なし。設計書の前提とは概ね一致）
- Clean Architecture 準拠: ○（受信経路は Manager/Bridge 関心として実装され、`android_library` 不変更）
- 既存実装との差分分析の正確性: △（`gradle.properties` の version 変更が設計対象外）
- テスト設計の網羅性: △（API 34+ 実経路未実行、Manager/PendingIntent 経路の検証不足）
- ドメインエラー全ケース実装: ○（新規ドメインエラーなしの設計）
- エラーコード/メッセージ対応表との整合: ○（既存 `shareText` 成否通知の契約は維持）

## プロジェクトルール適合チェック

- common.md 準拠: ○（UseCase 非経由の理由は設計上妥当）
- android.md 準拠: △（`UnityAndroidShareManager` の TAG が full class name ではない）
- エラー契約反映: ○（登録失敗・listener 例外は Bridge 内で封じ込め）
- 既存 API 互換性: ○（既存 API は追加のみで破壊的変更なし）

## テストカバレッジ

カバーできている観点:

- `ShareChooserActionReceiver` の action 転送、null intent/action 無視
- `ShareChooserActionInputs` の空/重複/default SEND の正規化
- `UnityAndroidShareManager` の register 呼び出し、listener 転送、listener 例外封じ込め、起動失敗 cleanup
- registry の API 34+ 実登録に近い計装テストファイル追加

不足している観点:

- API 34+ 実機/エミュレータでの計装テスト実行結果
- `UnityAndroidShareManager.shareText` から listener callback までの end-to-end に近い検証
- PendingIntent 由来 broadcast + `RECEIVER_NOT_EXPORTED` の受信成立
- `intentAction` 必須・一意・namespace 契約の実装側担保
- `chooserActions` 無し share による旧 receiver 解除の Manager レベル検証
- main looper 直列化の順序保証テスト

## 実行確認

- 実行コマンド: `./gradlew :unity_android_plugin:testReleaseUnitTest`
- 実行場所: `android/AndroidLibraryExample`
- 結果: 未実行
- 理由: `JAVA_HOME` が `/Applications/Android Studio.app/Contents/jbr/Contents/Home` を指しているが、そのディレクトリが無効で Gradle が起動できなかった。

## 総合評価

**要修正（軽微）**

実装方針は良く、設計レビューで挙げた high 項目の多くは形として反映されている。ただし、入力契約の実装側担保、実機経路テスト、不要な version 巻き戻しは、このままでは後続で見落としやすい。上記 high 2 件と medium のテスト補強を入れてから再レビューするのがよい。
