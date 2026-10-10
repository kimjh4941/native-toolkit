# 段階 3 の結果: `unity_android_plugin` を消す

- 実施日: 2026-10-10
- 対象: `artifact/topics/android-c-abi/README.md` の段階 3
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（2026-10-10）。ただし、設計 8.13 で段階 3 に消すと決めた 2 つの口が残っている（5 章）

## 1. 結論

Unity 向けの Android のブリッジ（`android/unity_android_plugin`。成果物は `unity-android-native-toolkit-*.aar`、パッケージは `android.unity.*` と `android.plugin`）を消した。2.0.0 から、Unity は汎用の C ABI（`android_library_capi`）を P/Invoke で呼ぶ（README D-2）。

- 2c（`unity-native-plugin` の移行）を待たずに進めた（利用者の決定。2026-10-10。README の「順番の理由」）。出し済みの `dist/`（1.12.0 まで）と `docs/`（過去の版）は、出した版の記録なので変えていない。2c が終わるまで 2.0.0 を出さないので、Unity が組めなくなる時期は生じない

## 2. 消したもの、直したもの

| 対象 | したこと |
|---|---|
| `android/unity_android_plugin/` | モジュールごと消した（追跡していた 32 ファイル: Kotlin のソース 14 と manifest、単体テスト 9、計装テスト 2、`MODULE.md`、`build.gradle.kts`、R8 の規則 2、`.gitignore`）。追跡していないビルドの出力も消した |
| `android/settings.gradle.kts`、`android/.idea/gradle.xml` | モジュールを外した |
| `scripts/build_android_library_aar.sh` | `--module unity_android_plugin` と出力の名前（`unity-android-native-toolkit`）を外し、例を capi に替えた |
| `scripts/publish_docs.sh` | Dokka の対象からプラグインを外した（C ABI のドキュメントは段階 4） |
| `scripts/test_android.sh` | 単体テスト、計装テストの APK の組み立てと導入、`android.unity` と `android.plugin` の計装テストの実行を外した |
| `scripts/check_design_consistency.py` | Android の Clipboard の設計書のソースの根を、プラグインから `android_library_capi` に替えた |
| `scripts/README.md`、`README.md`（3 言語） | モジュールの一覧、フォルダの構成、ビルドとドキュメントのコマンドを、capi に替えた。capi の説明は Windows の C ABI の書き方に合わせた |
| `agent-rules/coding-rules/android.md`、`common.md` | モジュール配置の表のプラグインの行を、C ABI の受け口（`android_library_capi`）の行に替えた。層とモジュールの対応に C ABI の行を足し、Android の Bridge の節を「2.0.0 から Bridge は無い」にした。過去の違反の例は、残して「2.0.0 で削除」と書き足した |
| `agent-rules/workflows/implement-sample-app`、`write-manual` | 例を iOS のプラグインに替えた。マニュアルの Android の記載対象に、C ABI の AAR を足した |
| `android_library` と サンプルの注記 | プラグインに触れていた 2 か所の KDoc を直した |
| 端末 | 古いプラグインのテスト APK（`android.plugin.test`）を両方の端末から消した |

## 3. 確かめたこと

- Gradle: サンプル、テストの APK、capi の release が組める。`android_library`、サンプル、`:ntk` の単体テストが通る
- `scripts/tests`: 205 件が通る
- 設計の照合（`check_design_consistency.py`）: 古い Android の Clipboard の設計書（2026-07-25）は、消す前から「名前が実装に無い」で失敗していた（実装が変わった後の古い名前が残っているため）。消したことで足されたのは `UnityAndroidClipboardManager` の 1 件だけ。この照合は書いている最中の設計書に使うもので、過去の設計書は直さない
- 全件の実行（`test_android.sh --include-host --baseline`。段階 3 の完了と、プラグインのテストが消えることによる基準の取り直しのため）:

| 端末 | 結果 | 基準との比べ |
|---|---|---|
| Pixel 6a（API 36） | 652 件すべて通る | 変わった 0、足した 0、消えた 87。基準を保存した |
| エミュレータ（API 35、arm64） | 651 件が通り、1 件 SKIP（smoke の 32-bit。前と同じ） | 変わった 0、足した 0、消えた 87。基準を保存した |

  消えた 87 件は、すべてプラグインのテスト（単体テストの `android.unity.*` と `android.plugin`、計装テストの `android.unity` と `android.plugin`）。ほかのテストの結果は 1 件も変わらなかった

## 4. 後の段に渡すこと

- 段階 4（マニュアル）: 2.0.0 の移行ガイドに、ブリッジの AAR の廃止を書く。マニュアルの Android の記載対象は、Kotlin の API の AAR と C ABI の AAR（`write-manual` のワークフロー）
- 2c: `unity-native-plugin` への申し送りは最後に渡す（`results/2026-10-10-android-c-abi-stage2c-handoff.md`）

## 5. 取りこぼし（後で片付ける）

段階 4 のマニュアルのレビューで分かった。Kotlin の API の設計書 8.13（KA-16）は、ブリッジだけが使う次の 2 つの公開の口を「段階 3 で消す」と決めていたが、この段階で消していなかった。

| 口 | 今 |
|---|---|
| `com.jonghyunkim.nativetoolkit.notification.NotificationShownSupport` | `@Deprecated` のまま残っている |
| `ShareTextUseCase` と `ShareUseCases.shareText` の `chooserActionsJson: String` の形（ポートの `ShareRepository.shareText` と実装を含む） | `@Deprecated` のまま残っている |

全件の実行の途中でライブラリのコードを変えないために、この実行の後に消し、関係するテストだけで確かめる（利用者の方針）。マニュアルは、どちらにも触れていない。
