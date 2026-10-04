# 段階 0g の結果: compileSdk と依存を上げる

- 実施日: 2026-10-04
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0g と 8.3
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（8.3 の版に上げ、使っていない依存を外した）

## 1. 結論

compileSdk と androidx の依存を 8.3 の版に上げ、ライブラリから `material` と `appcompat` を外した。全モジュールが組め、単体テストは全件通り、変えた依存に関係するテストは両方の環境で通った（3 章）。全体の実行と 0d の基準との比べ合わせは、0h の後に行う。

調べる中で、Kotlin の標準ライブラリの版が利用者に 2.4.20 で伝わることが分かった。Kotlin 2.2 でコンパイルする利用者が組めない可能性があるので、段階 1a で確かめる項目に足した（4 章）。

## 2. 変えたもの

| 対象 | 前 | 後 | 使う所 |
|---|---|---|---|
| compileSdk（全モジュール） | 35 | 36 | |
| `aarMetadata.minCompileSdk`（ライブラリ 2 つ） | AGP 9 の既定で 35（1.12.0 は 1） | 36 を明示 | 利用者に compileSdk 36 以上を求める（8.3） |
| core-ktx | 1.15.0 | 1.18.0 | 全モジュール |
| fragment | `appcompat` 経由で 1.8.x | `androidx.fragment:fragment` 1.9.1 を `android_library` に `api` で明示。ブリッジも明示 | `AndroidDialogFragment` が公開の API で `DialogFragment` を見せるので `api`。企画書の `fragment-ktx` ではなく `fragment` にした（ライブラリは Kotlin の拡張を使っておらず、利用者の依存が減る） |
| fragment-ktx（サンプルだけ） | 1.8.6 | 1.9.1 | |
| appcompat | 1.7.0（ライブラリ・サンプル）と 1.6.1（ブリッジ） | ライブラリとブリッジから外した。サンプルだけ 1.8.0 | ライブラリは `AppCompatResources.getDrawable` の 1 か所だけだったので、`ContextCompat.getDrawable` に置き換えた（minSdk 31 では同じ動作）。ブリッジは使っていなかった。サンプルは `AppCompatActivity` と `Theme.AppCompat` を使う |
| material | 1.12.0（ライブラリ・ブリッジ） | 外した | どこでも使っていなかった |
| androidx.media | 1.7.0 | 1.8.0 | |
| activity-compose（サンプル） | 1.8.0 | 1.13.0 | |
| lifecycle-runtime-ktx（サンプル） | 2.6.1 | 2.10.0 | |
| Compose BOM（サンプル） | 2024.09.00 | 2026.06.01 | |
| espresso / ext.junit（テスト） | 3.6.1 / 1.2.1 | 3.7.0 / 1.3.0 | 8.3 では 0c の行にあったが、0c では上げていなかった |

## 3. 確かめたこと

| 確認 | 結果 |
|---|---|
| ビルド | 全モジュールが組めた |
| 単体テスト | 161 件すべて成功（ライブラリ 83、ブリッジ 77、サンプル 1） |
| AAR | ライブラリ・ブリッジとも `minCompileSdk=36` |
| ライブラリが利用者に持ち込む依存（`releaseRuntimeClasspath` の直下） | `core-ktx` 1.18.0、`fragment` 1.9.1、`media` 1.8.0、`kotlin-stdlib` 2.4.20、`kotlin-parcelize-runtime` 2.4.20（推移的なものを含めて 53 個） |
| 変えた依存に関係するテスト（両方の環境） | 実機・エミュレータとも 79 件すべて成功。内訳は、Compose・activity・lifecycle を上げたので `TagInventoryTest` 5 件・`ReceivedShareTagInventoryTest` 1 件・`NavigationUiTest` 4 件と、非推奨になった Compose のテストのルールを使う `ClipboardSampleScreenUiTest` 14 件・`ReceivedShareLaunchUiTest` 1 件、fragment と appcompat の `DialogUiTest` 16 件、media と `ContextCompat.getDrawable`（大きいアイコンと画像）の `NotificationStyleUiTest` 8 件、ライブラリの instrumented テスト 20 件とブリッジの 10 件 |

**新しく出た警告**（0g では直さない）:

| 警告 | 場所 | 扱い |
|---|---|---|
| androidx.media 1.8.0 の非推奨（`androidx.media.app.NotificationCompat`、`MediaStyle`、`DecoratedMediaCustomViewStyle`） | `NotificationRepositoryImpl.kt` の 3 か所 | 8.3 で想定済み。Media3 への移行は、Media の style を C ABI に入れるとき（D-5 の残り）に検討する |
| Compose のテストの `createAndroidComposeRule` / `createEmptyComposeRule` の非推奨（`androidx.compose.ui.test.junit4.v2` に移るよう求める。v2 は `StandardTestDispatcher` を使う） | サンプルの androidTest の 5 か所 | UI テストを直してよいのは 0h だけ（README の段階の表）。v2 は coroutine の進め方が変わるので、0h でまとめて移すかを決める |

## 4. 利用者に伝わる Kotlin の標準ライブラリの版

KGP は既定で、自分の版の `kotlin-stdlib`（2.4.20）を依存に入れる（Kotlin の Gradle の文書）。Parcelize のランタイム `kotlin-parcelize-runtime:2.4.20` も `kotlin-stdlib:2.4.20` を求める（Maven Central の POM）。androidx の依存が求める stdlib は 2.1.20 まで。そのため、2b で POM を配ると、利用者は stdlib 2.4.20 を受け取る。

Kotlin のコンパイラは 1 つ先の版のメタデータまでしか読めないので、`languageVersion = apiVersion = 2.2`（0f）にしても、Kotlin 2.2 でコンパイルする利用者が組めない可能性がある。C ABI の利用者（Unity、Flutter の `dart:ffi`、Godot など）は Kotlin をコンパイルしないので関係しない。

配布物を作るのは 2b なので、今すぐ壊れる利用者はいない。README 8.2（段階 1a で確かめること）に足し、KGP 2.2.x の小さなアプリで実際に組んで決める。直すなら、stdlib と Parcelize のランタイムを 2.2.21 で明示し、Parcelize のプラグイン 2.4.20 が作るコードがそのランタイムで動くかも確かめる。
