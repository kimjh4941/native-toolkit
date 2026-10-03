# 段階 0 の結果: Gradle のルートを `android/` に移す

- 実施日: 2026-10-03
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0（D-16）
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（動作の変更は無し。release の AAR は 1.12.0 で配ったものと中身が同じ）

## 1. 変えたこと

| 対象 | 変更 |
|---|---|
| Gradle のルート | `android/AndroidLibraryExample/` から `android/` に移した（`settings.gradle.kts`、`build.gradle.kts`、`gradle.properties`、`gradle/`（wrapper と `libs.versions.toml`）、`gradlew`、`gradlew.bat`、`.gitignore`） |
| `settings.gradle.kts` | 絶対パス（`/Users/jonghyunkim/...`）の include をやめた。`:android_library` と `:unity_android_plugin` は既定の場所、サンプルは `:app` のまま `projectDir = file("AndroidLibraryExample/app")`。`rootProject.name` は `native-toolkit-android` |
| `.idea/`（Git の管理下のもの） | ルートと一緒に `android/.idea/` に移した。`gradle.xml` のモジュールのパスと、`vcs.xml` の Git のルート（`$PROJECT_DIR$/..` の 1 つにした）を直した |
| `.gitignore` | `.kotlin` を足した |
| 古い雛形 | `android/AndroidLibraryExample/android_library/` と `android/AndroidLibraryExample/unity_android_plugin/` を消した（どこからも使っていなかった） |
| 誤って Git に入っていたもの | `android/AndroidLibraryExample/.kotlin/errors/` の Kotlin のエラーログ 3 つを外した |
| `scripts/build_android_library_aar.sh` | Gradle を呼ぶ場所を `android/` にした（変数名も `ANDROID_EXAMPLE_DIR` から `ANDROID_GRADLE_ROOT` に） |
| `scripts/publish_docs.sh` | Dokka を呼ぶ場所を `android/` にした |
| `README.md` / `README.ja.md` / `README.ko.md` | API ドキュメントの生成の `cd android/AndroidLibraryExample` を `cd android` にした |
| `agent-rules/workflows/implement-feature/workflow.md`、`implement-sample-app/workflow.md` | Android の Gradle を `android/` で実行することと、サンプルのモジュールが `:app` であることを書いた |

手元の状態として、`android/AndroidLibraryExample/` に残っていた古いルートの `build/`、`.gradle/`、`.kotlin/`、`.idea/`（`workspace.xml` とキャッシュ）、`local.properties` を消した（どれも Git の管理外）。`local.properties` は `android/` に写した（Git の管理外のまま）。

直さなかったもの（サンプルのソースの場所を指していて、移動の後も正しい）: `scripts/check_design_consistency.py`、`scripts/check_sample_app_inputs.py`、`scripts/verify_manual.sh`、`agent-rules/coding-rules/{android,common}.md`、`agent-rules/workflows/design-sample-app/workflow.md`。

出荷済みのマニュアル（`manual/1.0.0`〜`1.12.0` の `index`）は「`android/AndroidLibraryExample` を Android Studio で開く」と書いているが、出荷した版の記録なので直さない。2.0.0 のマニュアルは段階 4 で直す（Android Studio で開くのは `android/`）。

## 2. 確かめたこと

| 確認 | 結果 |
|---|---|
| `./gradlew :android_library:assembleRelease :unity_android_plugin:assembleRelease :app:assembleDebug`（`android/` で実行） | 成功 |
| release の AAR を `dist/1.12.0/android` の AAR と比べる（展開して `diff -r`） | `android-native-toolkit-1.3.0.aar`、`unity-android-native-toolkit-1.3.0.aar` とも**中身が同じ** |
| `./gradlew :android_library:testReleaseUnitTest :unity_android_plugin:testReleaseUnitTest :app:testDebugUnitTest` | 成功。`android_library` 83 件、`unity_android_plugin` 77 件、`app` 1 件、失敗 0 |
| `scripts/build_android_library_aar.sh -m android_library -b release -v 1.3.0 -o <作業用のフォルダ>` | 成功。`dist/` と `gradle.properties` は変わっていない |
| Git の管理外のファイルが新しく見えていないか | 無い（`local.properties` などは `.gitignore` で無視される） |

確かめていないもの:

- instrumented テストとサンプルの UI テスト（端末かエミュレータが要る）。ビルドの結果の AAR が出荷物と同じで、テストのコードも変えていないので、段階 0d でまとめて流す
- `scripts/publish_docs.sh`（`docs/` を作り直すので、リリースのときに流す）
- Android Studio で `android/` を開いて同期すること（IDE の操作が要る）
