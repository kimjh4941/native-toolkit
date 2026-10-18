# probes

確かめるのに使った使い捨てのコード。ビルドには入れない（記録として置く）。

| フォルダ | 段階 | 中身 | 動かし方 |
|---|---|---|---|
| `stage0a/` | 0a | `Stage0aSpikeTest.kt`（通知のシェード、Dialog、Chooser、Toast、進捗、Media、Direct Share）、`Stage0aPermissionSpikeTest.kt`（通知の権限のダイアログ）、`Stage0aScheduleSpikeTest.kt`（更新と再起動の確認のための予約） | `android/AndroidLibraryExample/app/src/androidTest/java/com/jonghyunkim/android/nativetoolkit/example/spike/` に写し、`androidTestImplementation("androidx.test.uiautomator:uiautomator:2.4.0")` を足して、`./gradlew :app:installDebug :app:installDebugAndroidTest` の後に `adb shell am instrument -w -e class <クラス> com.jonghyunkim.android.nativetoolkit.example.test/androidx.test.runner.AndroidJUnitRunner`。`connectedDebugAndroidTest` はテストの後にアプリを消すので、ダンプが残らない。手順の詳細は `../2026-10-03-android-c-abi-stage0a-spike-result.md` |
| `stage0c/` | 0c | `Stage0cProbeTest.kt`（API 35 のエミュレータでの 0a の技法、style の値、サンプル自身が Sharesheet に並ぶか、通話のボタン、前景サービスの通知の遅れ） | `stage0a/` と同じ手順。結果は `../2026-10-03-android-c-abi-stage0c-result.md` の 3 章 |
| `stage1a/` | 1a | `spike1a/`（C ABI の雛形 `capi`、利用者のアプリ `consumer`、GoogleTest の `capitest`）と `kc22/`（Kotlin 2.2 / 2.1 でコンパイルする利用者） | それぞれ独立した Gradle のプロジェクト（`settings.gradle.kts` はこの場所からの相対パスで、このリポジトリの `android_library` と、`spike1a` が出すファイルの Maven リポジトリ `spike1a/m2` を指す）。`android/gradle` の wrapper を写して `JAVA_HOME` に JDK 17 以上を指定して組む。手順と結果は `../2026-10-04-android-c-abi-stage1a-spike-result.md` |
