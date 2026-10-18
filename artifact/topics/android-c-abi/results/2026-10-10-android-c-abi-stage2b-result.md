# 段階 2b の結果: Android の C ABI を実装する

- 実施日: 2026-10-05〜2026-10-10
- 対象: `artifact/topics/android-c-abi/README.md` の段階 2b、C ABI の設計書 第 1 部（`designs/2026-10-04-android-c-abi-c-abi-design.md`）と第 2 部（`designs/2026-10-05-android-c-abi-c-abi-design-part2.md`）の 13 章の TB-1〜TB-12
- ブランチ: `feature/NTKIT-17`
- 作業記録: `results/2026-10-05-android-c-abi-stage2b-working-notes.md`（TB ごとの判断、分かったこと、変異の表）
- 判定: **完了**（2026-10-10）。1〜3 回目のレビュー（`reviews/2026-10-10-android-c-abi-stage2b-review-v1.md`、`-v2.md`、`-v3.md`）の指摘をすべて対処し、両方の環境の全件の実行で基準を取り直した（4 章）

## 1. 結論

`android_library_capi`（Gradle のプロジェクトは `:ntk`）に、第 2 部の 155 関数を実装した。C ABI のテスト（`android_library_capi_test`）、配布物だけで組む smoke（`android_library_capi_smoke`）、古い Kotlin の利用者（`android_library_kotlin_consumer`）、配布物の照合（`check_android_dist.py`）を作り、`test_android.sh` につないだ。

- 公開の 155 関数は、すべてどれかのテストが呼ぶ。release の `libntk.so` の公開は 155 関数と `JNI_OnLoad` だけ（arm64-v8a・x86_64）
- テストは 2 台（Pixel 6a・API 36、エミュレータ・API 35、どちらも arm64）で通る。HWASan のビルドでも Pixel で通り、報告は 0 件
- 足した検査は変異で確かめた（82 本。捕まらなかった 4 本のうち 3 本は等価な変異、1 本は ART では区別できない確かめ）
- 実装の中で、設計と食い違った点や、設計に書いていなかった判断は、作業記録の各 TB の「実装の判断」に残した

## 2. 作ったもの

| TB | 中身 | コミット |
|---|---|---|
| TB-1 | 雛形、6 つの公開ヘッダー、初期化（`JNI_OnLoad`、`ntk_android_init`、Kotlin の `NativeToolkitCApi`） | `4519869d` |
| TB-2 | 共通の部品（文字列、`struct_size`、出力のハンドル、登録の表と帳簿、前面の判定、エラーの写しの土台）とデバッグ用のプローブ | `54455d25` |
| TB-3 | Clipboard（27 関数） | `eea2a207` |
| TB-4 | Dialog（17 関数） | `823e278f` |
| TB-5 | 通知のビルダー（内容 40、チャンネル 11） | `2d2c45c3` |
| TB-6 | 通知の操作（OP-20〜OP-39、20 関数）、ビルダーの写し、名前の解決、Progress の補正 | `43957965` |
| TB-7 | 通知のイベント（OP-40〜OP-42 と読み取り 12、計 15 関数）、受け口の保持（AP-21） | `ca1a612b` |
| TB-8 | Share（OP-43〜OP-54、12 関数） | `3fac0c36` |
| TB-9 | main を待たないテスト（155 関数）、初期化の競合のテスト、HWASan の試験用ビルド | `c2818a8e` |
| TB-10 | Maven の発行、ビルドスクリプト、配布物の照合、smoke、Kotlin の利用者 | `7bf7f6ab`、`b240afe5` |
| TB-11 | `test_android.sh` への接続（C ABI のテスト、契約の照合、smoke、`--hwasan`） | `f988c7e0` |
| TB-12 | 第 2 部 7 章の文書の直し（2b の前に済ませた） | - |

## 3. 完了の条件（第 2 部 15 章）

### 3.1 機能

| 条件 | 結果 | 根拠 |
|---|---|---|
| 8.1 の 56 操作と 8.2 の 155 関数が付録 A のとおりに公開されている | 満たす | `check_c_abi_contract_android.py --library`（両 ABI）が functions・signatures・symbols まで通る |
| 10 章のすべての振る舞いに OP がある | 満たす | 同上の behaviours |
| 11 章のすべてのエラーの値が写しの表のとおりに返る | 満たす（端末で起こせない値を除く） | 各 TB のテスト。起こせない値は 6 章 |
| 9 章の表とスレッド・同期性・キャンセルの契約が一致している | テストで確かめた。実装のレビューで照らす | 12.1 の完了・前面・イベントの行のテスト、main を待たないテスト |

### 3.2 品質

| 条件 | 結果 | 根拠 |
|---|---|---|
| 12.1〜12.4 が両方の環境で通る（x86_64 は G-3） | 満たす（x86_64 は G-3 のとおり組めることと照合まで）。12.1 の「構造体の配置」は、レビュー前の版には無かった（K-C1。前の版の「満たす」は誤り）。レビューの対処で足した | 4 章 |
| 第 1 部 6 章のテスト（初期化の経路、`release` と完了、main を待たない、競合の再現）が通る | 満たす | TB-1、TB-2、TB-9。HWASan と CheckJNI の下でも通る。スレッドの detach と前面の Clipboard のテストはレビューの対処で足した（K-C5）。「`exit` で落ちない」は、テストでは確かめられないと分かり、配布物の照合（終わりの登録を import しない）にして、行の名前も「`exit` の中で libntk が何も壊さない」に直した（第 1 部 0.7） |
| 32 ビットで入れたアプリが落ちない | 満たす | smoke の 32-bit（Pixel。C ABI は `UNAVAILABLE`、Kotlin の API は動く） |
| `llvm-nm -D` に `ntk_*` と `JNI_OnLoad` だけ、libc++ の名前が出ない | 満たす | 契約の照合の symbols、配布物の照合の native |
| 16 KB の整列 | 満たす | 配布物の照合（jni/ と Prefab の両方、両 ABI） |
| Prefab の `abi.json` の `"stl": "none"` | 満たす | 配布物の照合の prefab |
| POM と依存の一覧 | POM は満たす。依存の一覧は段階 4 | 配布物の照合の m2（座標、版、Kotlin の版を POM と Module Metadata の両方で）。D-17 の「依存の一覧をビルドから機械的に作ってマニュアルに載せ、照合する」はマニュアルの段（段階 4）で行う（7 章） |
| R8 の keep の規則を外した版で初期化が `CLASS_NOT_FOUND` | 満たす | smoke の no keep（自動・手動。C と Kotlin の両方、アプリは落ちない） |
| Kotlin 2.2 と 2.1 の利用者で組める | 満たす | smoke の kotlin 2.2.21・2.1.21 |
| 2a の機械照合が通り、照合の自己テストが壊すと落ちる | 満たす | `scripts/tests` の 196 件 |
| 足した検査は変異で落ちることを確かめた | 満たす | 5 章 |

### 3.3 構成と文書

| 条件 | 結果 |
|---|---|
| 7 章の文書の直し（TB-12） | 済み（2026-10-05） |
| `unity-native-plugin` に 8.3 と 16 章を渡した | 段階 2c（TC-1）で行う |
| マニュアル | 段階 4（AP-23）。渡すことは 7 章 |

## 4. 確かめたこと

`test_android.sh --include-host --baseline` を両方の端末で流し、基準を取り直した（2026-10-10）。

| 端末 | 結果 | 基準との比べ |
|---|---|---|
| Pixel 6a（API 36） | 728 件すべて通る | 変わった 0、なくなった 0、足した 161 |
| エミュレータ（API 35、arm64） | 727 件が通り、1 件 SKIP（smoke の 32-bit。32 ビットの ABI が無い） | 変わった 0、なくなった 0、足した 161 |

- 足した 161 件: C ABI のテスト 140（startup 120、noStartup 17、noNtkInitializer 3）、契約の照合 2（両 ABI）、smoke 12、`:ntk` の単体テスト 7
- C ABI を足しても、既存のサンプルとライブラリのテストの結果は 1 件も変わらなかった
- HWASan（`--hwasan` に当たる実行。Pixel、TB-9）: 140 件が通り、`HWAddressSanitizer` の報告は 0 件
- 配布物の照合（2.0.0 を作って流した、TB-10）: すべて OK
- `scripts/tests`: 196 件が通る

**レビューの対処の後（2026-10-10、Pixel）**: 直したところに関係するテストだけを流した（利用者の方針）。

- `test_android.sh --filter CApi --skip-unit`: startup 125 件のうち 123 件、noStartup 17 件、noNtkInitializer 3 件、契約の照合 2、smoke 12 が通った。落ちた 2 件と照合の自己テストの 1 件は、どれもテストの側の誤りだった（6 章）。直した後、startup の関係するケース 22 件（Registry、Share、NoWait、Home を使う 2 件）を流し直してすべて通り、照合の自己テスト（19 件）は 3 回続けて通った
**2 回目のレビューの対処の後（2026-10-10、Pixel）**: startup の Probe・Registry・Thread の 25 件、noStartup の 17 件、noNtkInitializer の 3 件がすべて通った。照合の自己テストは 23 件が通った。

**3 回目のレビューの対処の後（2026-10-10、Pixel）**: startup の Probe と Registry の 24 件、noStartup の 17 件、noNtkInitializer の 3 件がすべて通った。照合の自己テストは 24 件が通った。release の `libntk.so` の公開は 156、終わりの登録の import は 0。

**2b を閉じる全件の実行（2026-10-10、`test_android.sh --include-host --baseline`）**:

| 端末 | 結果 | 基準との比べ |
|---|---|---|
| Pixel 6a（API 36） | 739 件すべて通る（2 回目。1 回目は下のとおり） | 変わった 0、足した 12、消えた 1。基準を保存した |
| エミュレータ（API 35、arm64） | 738 件が通り、1 件 SKIP（smoke の 32-bit。前回と同じ） | 変わった 0、足した 12、消えた 1。基準を保存した |

- 足した 12 件はレビューで足したケース（下の 11 件と `capi-dist-selftest`）、消えた 1 件は置き換えた `Registry.CancelMovesActiveToCancelRequestedOnce`
- Pixel の 1 回目は、startup の最初のケース（`Share.TheEntryChecksReturnAndReleaseOnTheCallingThread`）で、計装のプロセスが開始から 1 ms で落ちた（`Test instrumentation process crashed`）。テストのコード（`@Before` の Activity の起動、GoogleTest の本体）が動く前で、端末のログは残っていなかった。直前は Probe の段（別のアプリの導入とプロセスの終了）と、Gradle によるテストの APK の導入だった。失敗があると基準は保存されないので、Pixel だけ全件を流し直した（2 回目は logcat を取り続けた）。2 回目は再現しなかったので、環境の一回きりの事象と見ている（原因は確かめていない）
- 基準から見ると、足したケースは 11 件（`StructLayout` 1、`Thread` 2、`Clipboard` 1、`Registry` 2、`Probe` 5）と `capi-dist-selftest`。消えたケースは 1 件（`Registry.CancelMovesActiveToCancelRequestedOnce`。取り消しの振る舞いが変わったので置き換えた）。基準は、上の全件の実行で取り直した

## 5. 変異

| TB | 本数 | 捕まらなかったもの |
|---|---|---|
| TB-1 | 5 | なし |
| TB-2 | 8 | なし |
| TB-3 | 7 | なし |
| TB-4 | 7 | なし（D1 は最初に通ったので、テストを直してから捕まえた） |
| TB-5 | 7 | なし |
| TB-6 | 16 | N3（`trigger_at_millis` 0）と K8（前面でない権限の要求）。どちらも Kotlin が同じ値を返す等価な変異 |
| TB-7 | 9 | なし（T1 は最初に通ったので、テストの準備を直してから捕まえた） |
| TB-8 | 12 | S3（前の対を消さない）。Kotlin が古い印の選択を出さない等価な変異 |
| TB-9 | 3 | なし（R1 は `ntk_android_init` の経路では通ったので、`JNI_OnLoad` の経路のテストにした） |
| レビュー v1 | 3 | なし（構造体の配置の値、静的なデストラクタ、消えたケースと SKIP） |
| レビュー v2 | 3 | `GetEnv` の確かめを外す変異（ART では区別できない。8 章）。積めなかった解除を流さない変異と、前の「ACTIVE に戻す」形は捕まえた（後者はテストを 1 件直してから） |
| レビュー v3 | 2 | なし（流す処理を空にする、流しを 1 周で止める） |
| 計 | 82 | 4（3 は等価。1 は ART では区別できない） |

TB-10 の照合のスクリプトは、自己テスト（1 つずつ壊して落ちることを確かめる 15 件。レビュー v1 の対処で 19 件、v2 で 23 件、v3 で 24 件）で確かめた。レビューの対処で足した検査は、次の変異で確かめた: 構造体の配置の値を 1 つ変えると組めない、デストラクタを持つ静的な変数を足すと release の `libntk.so` に `__cxa_atexit` の import が現れる、基準から消えたケースと SKIP に変わったケースを作った結果が全件の実行で失敗になる。TB-11 の結果の読み取りは、結果を 1 件消して `#resultLost` を拾えることを確かめた。

## 6. 分かったことと直したこと（主なもの）

| 事柄 | 直したこと | TB |
|---|---|---|
| JNI の署名の書き間違いで表づくりが失敗し、全部が `NOT_INITIALIZED` になった（2 回） | 署名を直した。表づくりは全部か無しかなので、1 か所の誤りで全テストが落ちて見つかる | TB-4、TB-7 |
| テストの側の use-after-free で main が止まった（Pixel の画面が白いまま） | 失敗の途中でも生きている形（`Leaked<T>()`）にした | TB-4 |
| 13 関数がどのテストからも呼ばれていなかった。Dialog と通知の操作の初期化の前のテストが無かった | テストを足した。初期化の前は全操作を 1 つのテストで呼ぶ | TB-6、TB-7 |
| capi の Module Metadata が Kotlin 2.4 の標準ライブラリを求め、Kotlin 2.1/2.2 の利用者が組めなかった（POM は正しかった） | capi にも Parcelize のランタイムの固定を入れ、照合で Module Metadata も見るようにした | TB-10 |
| テストのプロセスが「タスクの削除」で止められ、結果が届かなかった（2 回、同じケース） | 前のテストの後片づけ（設定の画面、Sharesheet）を、次のケースの前に終わらせる | TB-11 |
| Sharesheet は前面を奪わない。続けて 2 つ開くと 1 つしか出ない | テストの前提を直した（設計どおりの動き） | TB-8 |
| HWASan のプロセスでは Dialog のボタンが大文字で出る | UiDriver の探し方を大文字・小文字を区別しない形にした | TB-9 |
| 別のプロセスで `exit` を呼ぶテストは、C の `exit` なら C ABI と関係なく ART の JIT のスレッドが落ち、`System.exit` なら静的なデストラクタが走らない | 「`exit` で落ちない」を配布物の照合にした（第 1 部 0.7、作業記録） | レビュー |
| Sharesheet は半透明で、その下のアプリの Activity は前面のまま。`backToApp` が Back を押さずに戻り、Sharesheet が残っていた | 「前にいる」を、操作の対象の窓がアプリのものかで見るようにした。後片づけの結果を確かめる（K-X8）ようにして見つかった | レビュー |
| 照合の自己テストが、dist と m2 の AAR を別々に書き直していたので、2 秒の区切りをまたぐと zip の時刻が違って落ちた | m2 には dist の AAR を写す | レビュー |
| Registry の競合のテストが、解除を積めない写しで、K-M2 の後に誰も解放しない回を出した | v1 の対処ではテストを合わせたが、2 回目のレビューで「ACTIVE に戻す」形そのものが main と競うと `release` を落とすと分かった。戻さずに列に入れ、main の次の入口で外す形に作り直し、テストを元の主張に戻した | レビュー |

## 7. 後の段に渡すこと

- **段階 2c（TC-1）**: `unity-native-plugin` に第 2 部 8.3 と 16 章を渡す
- **段階 4（マニュアル）**: 2b で分かった、利用者に書くこと
  - 32 ビットも CMake で組むアプリは、C ABI を使う CMake の ABI を 64 ビットに絞る（AGP の `CXX1210`）
  - 手動の経路（Startup なし）では、`ntk_android_init` に Activity を渡す（第 1 部 1.4、K-5）
  - Kotlin の API も使う利用者は、2 つの AAR を両方宣言する（capi の POM は Kotlin の API に実行時の依存）
  - 依存の一覧を `releaseRuntimeClasspath` から作ってマニュアルに載せ、照合する（D-17）
  - Unity の利用者の Minimum API Level は 31 以上（1a の 3.7）
- **リリース（2.0.0）**: `build_android_library_aar.sh -m android_library -m android_library_capi -v 2.0.0 --m2` で `dist/2.0.0/android/` を作り、`check_android_dist.py 2.0.0` を流す
- **ほかの OS**: Windows・iOS・macOS のメモリのサニタイザーは別のトピック（`topics/memory-sanitizers`）

## 8. 確かめていないこと、残したこと

| 事柄 | 理由・扱い |
|---|---|
| x86_64 で動かすこと | 手元の 2 台は arm64（第 1 部 G-3）。組めること、公開関数、16 KB の整列、`libc++_shared` に依存しないことは照合で確かめた |
| 端末で起こせない失敗: `NO_SHARE_TARGET`、通知を無効にした状態（権限ありで無効は API 32 以下だけ）、後ろからの Progress の計装の下での `SERVICE_START_NOT_ALLOWED` | 写しは表のとおり。後ろからの Progress は smoke で計装の外から確かめた |
| 「再入で配っている途中も 32 件を超えない」（AP-21） | 配っている間に届いたイベントも同じ列と上限に入る作りで満たす。端末で再入の最中にイベントを起こすテストは無い |
| 公開の各関数をテストが呼んでいることの機械の照合 | 利用者の決定で足さない（TB-6） |
| 解除を main に積めなかった取り消しの遅れ（レビュー v3 の S-M1） | 登録に印を付け、main が次に C に入ったときに外す（第 1 部 5.7）。どの登録についても main が C に入らなければ、その間 `release` は来ない。積めないのは attach の失敗か記憶が足りないときだけなので、main を C の側から起こす仕組み（eventfd と `ALooper_addFd`）は足していない |
| スレッドの終わりの detach の前の `GetEnv` の確かめ（第 1 部 5.6） | ART は attach していないスレッドの detach に `JNI_ERR` を返すだけなので、外してもテストは通る。テストが示すのは「利用者が先に detach しても静かに終わる」まで |
| Share の Chooser Action の重複の確かめが件数の 2 乗 | かかるのは CPU だけ。件数の上限は決めていない |
| Pixel の全件の実行の 1 回目で、startup の最初のケースの計装のプロセスが落ちた | 2 回目は再現しなかった。原因は確かめていない（4 章）。また起きたら、logcat を取り続けた実行で追う |
| 結果が Gradle に届かないことの原因（TB-9 で 2 回） | TB-11 で原因（タスクの削除）を見つけて直した。HWASan の 1 回目に Gradle が止まった件も同じ原因と見られるが、確かめていない |
