# 段階 0f の結果: ビルドの道具を上げる

- 実施日: 2026-10-04
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0f と 8.3
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（SDK と依存の版は変えていない）

## 1. 結論

ビルドの道具を 8.3 の版に上げた。全モジュールが組め、単体テストは全件通り、道具の変更で影響しうる所のテストは両方の環境で通った（3 章）。全体の実行と 0d の基準との比べ合わせは、README 7 章の決定どおり 0h の後に行う。

| 対象 | 前 | 後 |
|---|---|---|
| AGP | 8.9.1 | 9.3.1 |
| Gradle（wrapper） | 8.11.1 | 9.7.0（wrapper の jar と起動スクリプトも 9.7.0 で作り直した） |
| Kotlin（KGP） | 2.0.21 | 2.4.20。ライブラリ 2 つは `languageVersion = apiVersion = 2.2` |
| Dokka | 2.0.0 | 2.2.0（Dokka Gradle Plugin v2） |
| Java の source / target、Kotlin の `jvmTarget` | 11 | 17 |

## 2. 変えたもの

| 対象 | 変更 |
|---|---|
| `android/gradle/libs.versions.toml` | 版を上げた。`org.jetbrains.kotlin.android` を外し、`kotlin-gradle-plugin`（ライブラリ）と `kotlin-parcelize`（プラグイン）を足した |
| `android/build.gradle.kts` | `buildscript` の classpath に KGP 2.4.20 を足した（AGP 9 は自分が依存する KGP 2.2.10 を使うので、新しい版は classpath で渡す。AGP 9.0 のリリースノート）。`kotlin.android` を外し、`kotlin.parcelize` と `dokka` を `apply false` で宣言した |
| 各モジュールの `build.gradle.kts`（4 つ） | `org.jetbrains.kotlin.android` を外した（AGP 9 の組み込みの Kotlin を使う）。`kotlinOptions` は AGP 9 の新しい DSL に無いので外し、ライブラリ 2 つは `kotlin { compilerOptions { jvmTarget, languageVersion, apiVersion } }` にした。アプリ 2 つは `jvmTarget` の既定（`compileOptions.targetCompatibility`）に任せる。`android_library` の `id("kotlin-parcelize")` は `alias(libs.plugins.kotlin.parcelize)` にした |
| Dokka の設定（ライブラリ 2 つ） | `tasks.dokkaHtml` を `dokka { dokkaPublications.html { ... } }` に移した。Dokka v2 の Android の source set は variant の名前（`debug`、`release`、`debugUnitTest`、`debugAndroidTest`）で、遅れて作られるので、`configureEach` の中で `release` だけを残して `MODULE.md` を含めた（v1 の `main` は無い） |
| `unity_android_plugin/build.gradle.kts` | Gradle 9 の Kotlin DSL は型を厳しく見るので、`version = libraryVersion` を `libraryVersion!!` にした（直前で空なら止めている。`android_library` と同じ形） |
| `scripts/test_android.sh`、`agent-rules/workflows/implement-feature/workflow.md` | 単体テストを `testReleaseUnitTest` から `testDebugUnitTest` にした。AGP 9 は単体テストを、テストする build type（debug）にだけ作る（`android.onlyEnableUnitTestForTheTestedBuildType` の既定が true になった）。どちらも難読化は無効で、テストの中身は同じ。基準のテストの名前は build type を含まないので、そのまま比べられる |
| `scripts/publish_docs.sh`、`README.md` / `README.ja.md` / `README.ko.md`、`MODULE.md` 2 つ | Dokka のタスクを `dokkaHtml` から `dokkaGeneratePublicationHtml` にした。出力先（`build/dokka/html`）は変えていない |

**手元の JDK:** Gradle 9 は起動に Java 17 以上を求める。利用者のターミナルは `JAVA_HOME` が Android Studio の JBR（21）を指しているので、そのまま動く。Claude の作業用のシェルは `~/.zprofile` を読まず `/usr/bin/java`（11）が使われるので、`JAVA_HOME` を明示して実行した。

## 3. 確かめたこと

| 確認 | 結果 |
|---|---|
| ビルド | 全モジュール（release の AAR 2 つ、サンプル、テストの APK 3 つ、共有先アプリ）が組めた。Kotlin の警告は 0 件 |
| 単体テスト | 161 件すべて成功（ライブラリ 83、ブリッジ 77、サンプル 1） |
| AAR のクラス | Java 17 のクラスファイル（版 61）。Kotlin のメタデータは 2.2.0（Kotlin 2.1 以上の利用者が読める） |
| Dokka | ライブラリ 648 ページ、ブリッジ 145 ページ。前の版（`docs/latest/android/`）と同じ規模・同じ構成で、パッケージの名前だけが 0e の名前になった |
| 道具の変更で影響しうる所のテスト（両方の環境） | 実機・エミュレータとも 63 件すべて成功。内訳は、Compose のコンパイラが変わったので全画面の testTag の `TagInventoryTest` 5 件・`ReceivedShareTagInventoryTest` 1 件と `NavigationUiTest` 4 件、Fragment の Dialog の `DialogUiTest` 16 件、Parcelize で payload を渡す・保存する `NotificationProgressUiTest` 4 件と `NotificationScheduleUiTest` 3 件、テストの APK の targetSdk が 35 になったライブラリの instrumented テスト 20 件とブリッジの 10 件。端末に入った 4 つの APK が今回のビルド（targetSdk 35）であることを `dumpsys package` で確かめた |

## 4. 道具を上げたことで変わったもの（利用者とテストに見えるもの）

| 変化 | 内容 | 扱い |
|---|---|---|
| AAR の `minCompileSdk` | 1.12.0 の AAR は `minCompileSdk=1`（制約なし）。AGP 9 は既定で compileSdk の値（35）を入れるので、利用者に compileSdk 35 以上を求めるようになった | 0g で計画どおり `aarMetadata.minCompileSdk = 36` を明示する。35・36 は 8.3 の利用者の上限の内 |
| テストの APK の targetSdk | ライブラリ・ブリッジのテストの APK は targetSdk を書いていない。AGP 9 はその既定を compileSdk にしたので（`android.sdk.defaultTargetSdkToCompileSdkIfUnset`。AGP 9.0 のリリースノート）、35 になった（`aapt2 dump badging` で確認）。前の既定（AGP 8）の値は、前の APK では確かめていない | テストの APK だけで、配る AAR には関係しない。instrumented テストで確かめた（3 章） |
| 単体テストのタスク | `testReleaseUnitTest` が無くなり、`testDebugUnitTest` だけになった | 2 章 |
