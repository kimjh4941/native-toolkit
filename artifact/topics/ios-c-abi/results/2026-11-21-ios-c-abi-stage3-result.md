# 段階 3 の結果: `UnityIosPlugin` を消す

- 実施日: 2026-11-21
- 対象: `artifact/topics/ios-c-abi/README.md` の段階 3
- ブランチ: `feature/NTKIT-18`
- 判定: **完了**（2026-11-21）。ブリッジだけのために公開した口が 1 つ残る（5 章。持ち主の判断）

## 1. 結論

Unity 向けの iOS のブリッジ（`ios/UnityIosPlugin`。成果物は `unity-ios-native-toolkit-*.xcframework`、Swift の facade と Objective-C の `.h` / `.m`）を消した。2.0.0 から、Unity は汎用の C ABI（`IosLibraryCApi`）を P/Invoke で呼ぶ（README D-2）。2c（`unity-native-plugin` の移行）は済み、作り直した `dist/1.14.0` での SH-13 の確かめまで通っている（段階 2 の作業の記録 17.16）。

- ブリッジは 0e でワークスペースのビルドと `test_ios.sh` の基準から外していた（D-22）。消す前の結果は `results/2026-10-24-ios-c-abi-bridge-tests-before-0e.md` にある
- 出し済みの `dist/`（1.13.0 まで）と `docs/`（過去の版）は、出した版の記録なので変えていない。README の「Distributables (1.13.0)」の `unity-ios-native-toolkit-1.3.0.xcframework` の行も、1.13.0 の中身なので残した（リリースで 1.14.0 の一覧に替わる→2026-11-22 に替えた。`d4091ca1`）
- 2.0.0 から、iOS のライブラリに Objective-C は無い（D-10）

## 2. 消したもの、直したもの

| 対象 | したこと |
|---|---|
| `ios/UnityIosPlugin/` | 追跡していた 27 ファイルを消した（Swift の facade と JSON の変換 7、Objective-C の `.h` / `.m` 8、アンブレラヘッダ 1、DocC 1、テスト 6、プロジェクトの 4）。追跡していない出力（`ios/Build/UnityIosPlugin`、`ios/Docs/UnityIosPlugin`、`.DS_Store`）も消した |
| `scripts/build_ios_library_xcframework.sh` | `UnityIosPlugin` のモジュールと出力の名前を外した。**知らないモジュールの名前を、組み立ての前に拒む**ようにした（今までは並べ直しで知らない名前を黙って落としていたので、外したままだと `-m UnityIosPlugin` が何も言わずに無視された）。例と使い方を capi に替えた |
| `scripts/tests/test_build_ios_library_xcframework.py` | `-m UnityIosPlugin` を拒むことのテストを足した。確かめを外すと落ちることを見た |
| `ios/generate_docc.sh`、`scripts/publish_docs.sh` | ブリッジの DocC の作成と写しを外した（C ABI のドキュメントは段階 4） |
| `scripts/check_design_consistency.py` | iOS の Clipboard の設計書のソースの根を、ブリッジから `ios/IosLibraryCApi` に替えた（Android と同じ） |
| `scripts/README.md`、`README.md`（3 言語） | モジュールの一覧、フォルダの構成、ビルドのコマンドを capi に替えた。capi の説明は Android の C ABI の書き方に合わせた |
| `agent-rules/coding-rules/common.md` | C ABI への置き換えに iOS を足した。モジュール配置の表の Unity Bridge の行を macOS だけにし、`Unity*Manager` の例を macOS にした。Swift と Objective-C の Bridge の例は macOS の例として残し、「iOS（2.0.0 から Bridge は無い）」の節を足した。サンプルの依存の表の iOS の行を capi にした |
| `agent-rules/coding-rules/ios.md`、`agent-rules/index.md` | 適用対象からブリッジを外し、C ABI の公開ヘッダを足した。テストと smoke の C / Objective-C の扱いと、「C ABI の置き方」（入口 → 受け口 → `IosLibrary`）を足した。ログの対象を C ABI の受け口にし、入口と第 1 部 5.15（R-35）の除外を書いた。Objective-C のログの書き方と、Objective-C / Swift の型の節を消した（macOS は `mac.md` に自分の節がある）。コメントの規則の Objective-C（HeaderDoc）を、C ABI の公開ヘッダ（`/** */`、`@file`・`@brief`、ASCII だけ）にした。callback 版の説明の「Bridge 向け」を「C ABI と、callback で受ける呼び出し元向け」にした |
| `agent-rules/workflows/implement-sample-app`、`write-manual` | 例を macOS のプラグインに替えた。マニュアルの iOS の記載対象に、C ABI の XCFramework（`ios-native-toolkit-capi-*.xcframework` と `include/NativeToolkitC/`）を足した |
| `IosLibrary.docc/IosLibrary.md`、`IosClipboardManager.swift` の `// MARK:` | ブリッジに触れていた 4 か所（DocC のカタログの 3 か所と `MARK` の 1 か所）を C ABI に直した（DocC のカタログと `//` のコメントなので、配布物の中身は変わらない） |

## 3. 確かめたこと

- `scripts/tests` の全件: 859 件のうち 6 件が落ちた。6 件とも SH-13 の直し（`0e4206e7`）でサンプルのボタンと信頼する部分（`Support/SampleApp.swift`）を変えたことによるもので、段階 3 とは関係しない（SH-13 のときにスクリプトのテストを流していなかった）。`6d85928c` で直した: `SampleApp.swift` のハッシュを固定し直し（足した case 1 つ。SH-13 の実装のレビューの対象だった）、`enumeration.json` を流した回の本物の出力から、`otool` の 2 つを署名なしの実機向けの組み立てから取り直した（125 件）。直した後、`test_ios_ui_runner` の 215 件と、ビルドスクリプトのテスト 9 件が通った
- `ios/generate_docc.sh`（Xcode 26.6）: `IosLibrary` の DocC が作れた。`ios/Docs/` には `IosLibrary` だけ
- ワークスペースと `test_ios.sh` は 0e からブリッジを含まないので、組み立てとテストの結果は変わらない（UI テストと単体テストは流し直していない。段階 3 でライブラリとサンプルのコードは、`//` のコメント 1 行のほか変えていない）
- 設計の照合: iOS の Clipboard の古い設計書（2026-08-02 の v4 など）は、ブリッジの名前（`clipboardCopy` など）が「実装に無い」と出るようになった。消す前はブリッジのソースに名前があったので通っていた（Android の段階 3 と同じ）。この照合は書いている最中の設計書に使うもので、過去の設計書は直さない（Android の段階 3 と同じ）。古い設計書には、ほかの FAIL（作業の粒度など）が前からある
- 残り: `git grep` で、`docs/`・`dist/`・`artifact/`・`manual/` の外に `UnityIosPlugin` と `unity-ios-native-toolkit` が残るのは、README の 1.13.0 の配布物の行（1 章）と、「2.0.0 で消した」と書いた規則・スクリプトの注だけ

レビュー: `reviews/2026-11-21-ios-c-abi-stage3-review-v1.md`（Codex と Claude のサブエージェント。medium 2 件（`ios.md` のログの対象とヘッダのコメントの規則）と low 7 件。`android/.idea` の 1 件のほかすべて直した）。直した後、ビルドスクリプトのテスト 9 件が通った。

## 4. 後の段に渡すこと

- 段階 4（マニュアル）: 2.0.0 の移行ガイドに、ブリッジの XCFramework（`unity-ios-native-toolkit-*.xcframework`）の廃止を書く。マニュアルの iOS の記載対象は、Swift の API の XCFramework と C ABI の XCFramework（`write-manual` のワークフロー）。C ABI の Doxygen を `publish_docs.sh` に足す（Android と同じ）
- README の「Distributables」は、リリースで 1.14.0 の一覧にする（2026-11-22 に済み。`d4091ca1`）
- C ABI の公開ヘッダの説明は、134 の宣言のうち 60 が `/* */` のまとめの説明か説明なし（`ntk_share_result_free` など）。段階 4 で Doxygen を入れるときに、Doxygen が拾う形に揃える（`ios.md` のコメントの規則。レビュー K-2）

## 5. 残したもの（持ち主の判断）

| 口 | 今 | 推奨 |
|---|---|---|
| `IosLibrary` の `ClipboardRedaction`（`@objc public final class`。`text`・`dataByteCount`・`json`・`path`） | ブリッジの Objective-C から呼ぶために公開した（DocC にそう書いてある）。今、公開の口として使うのはライブラリの中（`ClipboardLog`）とテストだけ | **2.0.0 では残す**。設計書で消すと決めていない。消すと公開の API が変わり、`dist/1.14.0` の作り直しと `unity-native-plugin` の取り込み直しが要る。残しても害は無い。DocC の「Unity Bridge の `.m` から使う」の記述は、配布物の `.swiftdoc` と `IosLibrary-Swift.h` に入るので、配布物とソースを揃えるために今は直していない（次に `IosLibrary` を組むときに直す→段階 4 の `d5c9889b` で直し、`68ca7674` の dist に入った） |

`ClipboardFailureDetail` の DocC の「Bridge JSON」の語も、同じ理由で今は直していない（→段階 4 の `d5c9889b` で直した）。`ClipboardRedaction` を残すかは決めないまま、残す形で 2.0.0 に入る（`results/2026-11-22-ios-c-abi-closing.md` の 3 章）。
