# 段階 4 の結果: マニュアル、API リファレンス、配布物の照合

- 実施日: 2026-10-10
- 対象: `artifact/topics/android-c-abi/README.md` の段階 4
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（2026-10-10）。リリース（`dist/1.13.0` の作成と公開）は、2c の成功を待つ（7 章）

## 1. 決めたこと（利用者の決定。2026-10-10）

| # | 決定 | 理由 |
|---|---|---|
| M-1 | リリース版は **1.13.0**、Android のライブラリの版は **2.0.0**（`dist/1.13.0/android/android-native-toolkit-2.0.0.aar`） | Windows の F-1 と同じ。製品の版とライブラリの版は前から別で、Android だけの破壊的変更で製品の版を上げない |
| M-2 | マニュアルは **Kotlin の API を本文、C ABI を各機能の章の節**にし、1.x からの移行は index に書く | Windows の F-3 と同じ。コード例をサンプルと一致させられる |
| M-3 | C ABI のヘッダーの API リファレンスを、Windows と同じく Doxygen で作り、生成物をリポジトリに入れる | Homebrew で `doxygen` を入れて作った |

## 2. したこと

| 対象 | 内容 | コミット |
|---|---|---|
| マニュアルの写し | `manual/1.12.0` を `manual/1.13.0` に写した（ワークフローの手順） | `3b7dda23` |
| 機能の章（4 つ × 3 言語） | Android の部分を 2.0.0 の Kotlin の API で書き直し、C ABI の節を足した。英語を 4 本のサブエージェントで並行して書き、レビューの後に日本語と韓国語へ訳した。Windows の C ABI の目次のリンクは、Android の `### C ABI` が先に来たので `#c-abi-1` に直した | `79e9ac92` |
| index（3 言語） | 成果物の場所（1.13.0）、版、機能の一覧、Android の組み込み（2 つの AAR、方法 A の Maven リポジトリ、方法 B の AAR と依存の一覧、初期化、外せる権限、C ABI の組み込み、1.x からの移行、Unity の動作環境） | `79e9ac92` |
| 画像 | Share の選択のイベント（Share For Selection）の画面を Pixel 6a で撮った（試験専用の共有先を消してから） | `f2c02cd9` |
| サンプル | Share のエラーの表示が "null" だった（`ShareDomainError` は message を持たない）。型の名前を出す形にした | `b071d718` |
| 配布物の照合 | ライブラリ版を C ABI の AAR の名前から読み、リリース版と分けた。マニュアル（3 言語）の依存の一覧を、Module Metadata の実行時の依存と照らす検査を足した（README の完了の条件「依存の一覧がマニュアルの一覧と一致する」）。自己テストを 3 件足した | `7a6092a2` |
| ビルドのスクリプト | `--release-version`（`-r`）を足した | `495b2284` |
| API リファレンス | `android/android_library_capi/Doxyfile` と生成物（`docs/html`）。`publish_docs.sh` が作り直して `docs/<版>/android/android_library_capi` に写す。`docs/README.md` から消したプラグインを外した | `ac74901a` |

## 3. レビュー

`reviews/2026-10-10-android-c-abi-stage4-manual-review-v1.md`。英語の版を 3 本（Kotlin の API、C ABI と組み込み、利用者がこのとおりに進めて成功するか）で見て、A が 6 件だった。主なもの:

- 32 ビットも組む CMake の扱いの誤り（`if()` では AGP の `CXX1210` を防げない。CMake の ABI を 64 ビットに絞る）
- 1.x で表示中の通知が更新の後にタップに反応しないこと（D-11）が無かった
- Share の `shortcuts.xml` の例にサンプルのクラス名、index の「全機能が C ABI から使える」（共有の受け取りは除く）
- 手動の初期化は Activity を渡す（Application の Context だけだと、表示中の Activity を前面と認識しない）
- 利用者が `androidx.core.content.FileProvider` を宣言すると、ライブラリの宣言と manifest の merge で衝突する（1.x のマニュアルはその宣言を求めていた）

範囲外で、段階 3 の取りこぼし（設計 8.13 の 2 つの口）が分かり、段階 3 で片付けた（`results/2026-10-10-android-c-abi-stage3-result.md` 5 章）。

## 4. 確かめたこと

- `check_manual_c_examples_android.py 1.13.0 --require-examples --require-compile`: 公開の 155 関数がすべて例に出る、名前がヘッダーにある、3 言語でコードが同じ、17 の例が NDK の clang で組める
- `verify_manual.sh 1.13.0`: アンカー、文体（ja / ko）、機能の一覧は OK。止まる失敗は 2 つで、どちらも今回のものではない
  - 画像の 30 件: macOS の通知の画像と index の Android の画像。1.12.0 にもある既知の別の課題（`manual-integrity`）
  - 成果物の名前: `dist/1.13.0` がまだ無い（リリースで作る）
- `android.library.*` と `unity-android-native-toolkit` がマニュアルに残るのは、移行の表の「1.x」の側だけ
- `scripts/tests`: 208 件が通る
- Doxygen: 警告 0 件

## 5. 分かったこと

- 機能の章に Android の `### C ABI` を足すと、同じページの Windows の `### C ABI` のアンカーが `#c-abi-1` に変わる。`verify_manual.sh` はリンクの先が在るかしか見ないので、ずれても検出しない。マニュアルの C の例の照合は「C ABI」を含む見出しを `### C ABI` だけに限るので、見出しの名前を変えて避けることはできない
- マニュアルの照合の自己テストの 2 件が「最新のマニュアルに Android の C ABI の節が無い」ことを前提にしていた。1.12.0 を固定で使う形にした
- 共有の scratchpad で、並行のサブエージェントの下書きが同じ名前で上書きされた。各担当が仕上がったページを確かめ直し、照合も通ったので、影響は無かった。並行で書かせるときは、ファイル名に担当の名前を付けるよう最初に伝える

## 6. 確かめていないこと

- マニュアルの日本語と韓国語の訳のレビュー（サブエージェントによる）。照合（コード、見出し、画像の数、文体）で確かめた
- Dialog の画像は 1.x のまま（2.0.0 の Dialog は `DeviceDefault` の見た目で、写真と少し違いうる）

## 7. 後に残すこと（リリース、1.13.0）

2.0.0 は「2c（`unity-native-plugin` の移行）の成功」がリリースの条件（README の D-2 の段落と、利用者の決定）。2c の後に次を行う。

1. `dist/1.13.0/` を作る: Android は `scripts/build_android_library_aar.sh -m android_library -m android_library_capi -v 2.0.0 -r 1.13.0 --m2`、ほかの OS は `dist/1.12.0/` から写す（マニュアルのワークフロー）
2. `check_android_dist.py 1.13.0` と `verify_manual.sh 1.13.0`（成果物の名前）
3. ルートの README（3 言語）の「今のリリース」と配布物の一覧を 1.13.0 にする
4. `publish_docs.sh 1.13.0`（Windows の F-7 と同じく、リリースのときに公開する）
5. 段階 3 で消した `ExistingShareApiTest` の 2 件が基準から外れるので、リリースの前の全件の実行を `--baseline` で流す
