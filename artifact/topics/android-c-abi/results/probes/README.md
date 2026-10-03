# probes

確かめるのに使った使い捨てのコード。ビルドには入れない（記録として置く）。

| フォルダ | 段階 | 中身 | 動かし方 |
|---|---|---|---|
| `stage0a/` | 0a | `Stage0aSpikeTest.kt`（通知のシェード、Dialog、Chooser、Toast、進捗、Media、Direct Share）、`Stage0aPermissionSpikeTest.kt`（通知の権限のダイアログ）、`Stage0aScheduleSpikeTest.kt`（更新と再起動の確認のための予約） | `android/AndroidLibraryExample/app/src/androidTest/java/com/jonghyunkim/android/nativetoolkit/example/spike/` に写し、`androidTestImplementation("androidx.test.uiautomator:uiautomator:2.4.0")` を足して、`./gradlew :app:installDebug :app:installDebugAndroidTest` の後に `adb shell am instrument -w -e class <クラス> com.jonghyunkim.android.nativetoolkit.example.test/androidx.test.runner.AndroidJUnitRunner`。`connectedDebugAndroidTest` はテストの後にアプリを消すので、ダンプが残らない。手順の詳細は `../2026-10-03-android-c-abi-stage0a-spike-result.md` |
