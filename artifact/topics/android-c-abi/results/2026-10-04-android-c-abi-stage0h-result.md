# 段階 0h の結果: サンプルの targetSdk 36 と、0e〜0h の後の全体の実行

- 実施日: 2026-10-04
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0h と、7 章の「全体の実行の時期」の 1 回目の区切り
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（UI テストは直さずに通った。0e〜0h の後の全体の実行は、両方の環境とも 0d の基準と同じ）

## 1. 結論

サンプル（`AndroidLibraryExample/app`）の targetSdk を 35 から 36 にした。0e〜0h の変更（パッケージ名、ビルドの道具、compileSdk と依存、targetSdk）をすべて入れた状態で、両方の環境で全体（Host を含む）を流し、どちらも 317 件すべて成功し、0d の基準とテストごとに同じだった。これで段階 0 はすべて終わった。

## 2. 変えたもの

| 対象 | 変更 |
|---|---|
| `android/AndroidLibraryExample/app/build.gradle.kts` | `targetSdk = 36` |

共有先アプリ（`testShareTarget`）はテスト専用で配らないので、targetSdk 35 のままにした。ライブラリとブリッジのテストの APK は、AGP 9 の既定で compileSdk（0g から 36）が targetSdk になっている（0f の結果 4 章）。

**targetSdk 36 で変わる動作とサンプル:** Android 16 は、targetSdk 36 のアプリで edge-to-edge の解除（`windowOptOutEdgeToEdgeEnforcement`）を無視し、予測型の「戻る」を既定にする。サンプルは既に `enableEdgeToEdge()` を呼び、画面の「戻る」を Compose の `BackHandler`（`OnBackPressedDispatcher` を使う）で扱い、`onBackPressed` を上書きしていないので、直すところは無かった。これらの変化は Android 16（API 36）の端末でだけ効くので、確かめになるのは実機の結果である。

## 3. 全体の実行（1 回目の区切り）

`scripts/test_android.sh --serial <端末> --include-host`。

| 環境 | 結果 | 0d の基準との比べ合わせ | 所要時間 |
|---|---|---|---|
| 実機（Pixel 6a、API 36） | 317 件すべて成功（単体 161、UI 116、instrumented 30、HostState 6、Host 4） | 変わったもの 0、増えたもの 0、無くなったもの 0 | 19 分 |
| エミュレータ（API 35） | 317 件すべて成功（同じ内訳） | 変わったもの 0、増えたもの 0、無くなったもの 0 | 46 分 |

fingerprint は両方とも基準と同じだった。基準のファイルは取り直していない（0e でテストの名前だけを置き換えたもののまま）。

README 7 章に「全体の実行は 1 回に約 2 時間」と書いていたが、実際は両方の環境を順に流して約 65 分だった（0d の頃の実行は、エミュレータの不安定さで流し直したり、取り直したりしていて長く見えた）。README の数字を直した。区切りで全体を流す方針は変えない。

## 4. 0h で決めたこと

| 項目 | 決めたこと | 理由 |
|---|---|---|
| Compose のテストの `createAndroidComposeRule` / `createEmptyComposeRule` の非推奨（0g で発生。`androidx.compose.ui.test.junit4.v2` へ移るよう求める） | **移さない**。非推奨のまま使い、v1 が消えるとき（Compose の BOM を上げて使えなくなったとき）に移す | v2 は `StandardTestDispatcher` を使い、coroutine の進め方が変わる。今のテストは v1 のまま両方の環境で通っており、移すと 1b の前後の比べ合わせの根拠になるテストの動作が変わりうる。テストを直してよいのは 0h だけなので、1b より後で移す場合は、その段の結果に理由を書く |
| androidx.media 1.8.0 の非推奨（0g で発生） | 0g の結果のとおり、Media の style を C ABI に入れるとき（D-5 の残り）に Media3 への移行を検討する | ライブラリのコードの変更で、0h（UI テスト）の範囲ではない |
