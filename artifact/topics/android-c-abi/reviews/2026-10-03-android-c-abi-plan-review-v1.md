# レビュー結果

- 日付: 2026-10-03
- 対象ファイル: `artifact/topics/android-c-abi/README.md`（コミット `93ffbc4a` の版。447 行）
- トピック名: android-c-abi（企画書）
- 対象 OS: Android 12 以降（minSdk 31）
- 判定: **要修正**（区分 A が残るので、README を直して再レビューする）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行。互いの結果は見せていない）
- 機械照合: 対象外（`check_design_consistency.py` は設計書用）

区分は review-document の止める基準に従う。A = このまま進むと後の成果物の動作・API・契約が変わる、B = 検証の手段が変わる、C = 記述の整合だけ。「出典」は指摘したレビュアー（Claude / Codex / 両方）。

---

## 強み

- 依存の向き（C ABI は `android_library` の上の薄い変換層、機能は Kotlin にだけ置く）が明確（両方）
- `c++_static`、version script、JNI の `.so` を 1 つ、Prefab、という配布の方針は、Google の middleware ベンダー向けガイドと合う（Codex）
- リポジトリの事実（ブリッジの公開メソッド 69・操作 45、テストの件数、testTag 0 個、consumer-rules.pro が空、パスワードの `Log.d` など）は、実物と照合して正しい（両方）
- 1.2 でブリッジにしか無いロジックを具体的に洗い出し、7.1 でサンプルの UI テストで守れる範囲の限界を自分で書いている（Claude）
- 8.3 で、利用者の側の上限から逆算して版を選んでいる（Claude）
- Dialog を非同期だけにする判断（D-8）は妥当（Codex）

## 事実の照合

| 主張 | 結果 | 根拠 |
|---|---|---|
| 公開メソッド 69・操作 45、テストの件数（android_library unit 83、ブリッジ unit 77 / instrumented 10、サンプル androidTest 23） | 正しい | `@Test` などを数えた（両方） |
| サンプルの androidTest 23 件の内訳（7 章では「Clipboard 14 件と、受け取った共有の解析」） | 1 件足りない | 雛形の `ExampleInstrumentedTest` 1 件が入っていない（Codex） |
| Unity の Runtime 97 件 | メソッドの数 | `[TestCase]` を展開すると 116 ケース（Codex） |
| Unity の PlayMode 12 件 | メソッドの数としては正しい | `[UnityTest]` 11 件 + `[Test]` 1 件（2026-10-03 に確認。Codex は 11 件、Claude は 12 件とした） |
| 予約した通知は「タップ先の Intent を Parcel ごと保存」 | 結論は正しいが不正確 | 保存しているのは `AndroidNotificationCommandPayload` の Parcel で、その `platformOptions` が旧 Receiver を指す Intent を含む（Codex）。影響は README の見積もりより大きい（A-3） |
| `unity-native-plugin` は androidx の依存を `PostBuildProcessor` で補っている（D-17 の根拠） | **誤り** | `PostBuildProcessor` が足すのは KGP、`kotlin-stdlib`、`kotlin-reflect` の 2.0.21 だけ。androidx は Unity の GameActivity のテンプレート（appcompat 1.6.1、core 1.9.0、games-activity 4.4.0）にたまたま乗っている（Claude） |
| `UnityPlayerActivity extends android.app.Activity` | 正しいが不完全 | GameActivity の基底の `com.google.androidgamesdk.GameActivity` は `AppCompatActivity` の派生で、`FragmentActivity` である（Claude。2026-10-03 に javap で再確認） |
| 「GameActivity では Unity のメインスレッドは Android の main ではない」（D-6） | 正しいが誤解を招く | `UnityPlayerActivity` でもスクリプトは UnityMain スレッドで動く（Claude） |
| KGP 2.4.20 が確かめている範囲（AGP 9.3.1 / Gradle 9.7.0 まで）の外の AGP 9.3.3 / Gradle 9.7.1 を選んでいる | 計画の中の矛盾 | 8.3 の表（Codex） |
| 外部の版情報（AGP 9.3.3 / 9.4.1、AGP 9.3 の Gradle の下限 9.5.0 と既定の NDK r28.2、AGP 9.0 の変更、Gradle 9.7.1、Kotlin 2.4.20 と KGP の対応表、Dokka 2.2.0、NDK r30 の LTS、Play の targetSdk 36 の期限、16 KB の 2027-02-01、Unity のパッチごとの AGP、Flutter 3.47.6 の既定値、ARCore / PGS の初期化のシグネチャ、`NativeCallable`、`FlutterActivity` の基底） | 正しい | Claude のレビュアーが裏で動かした検証（公式の出典と、Google Maven の AAR の `aar-metadata.properties` の実物）。Unity は 6000.0.85f1 以降と 6000.3.26f1 以降が Gradle 9.3.1 / AGP 9.1.1 で、計画に無い行がある |
| 依存の AGP の最大 8.9.1、compileSdk の最大 36 | 8.3 の組み合わせでは正しい | Gradle の `.module` を辿って確かめた。最大の出どころは activity 1.13.0、core 1.18.0、navigationevent 1.0.0。Compose BOM 2026.08.00、core 1.19.x、lifecycle 2.11.0 と activity-compose の組み合わせのどれかを入れると、9.1.0 / 37 に上がる。テストの依存（UiAutomator 2.4.0 など）は 8.1.1 / 34 まで |
| AGP の既定の CMake | **誤り（文書が古い）** | 公式の install-ndk のページは 3.10.2 と書くが、AGP のソース（`CmakeLocator.kt`）の既定は 3.22.1。計画の「版を明示する」方針は変わらない |
| Flutter 3.29 の main スレッドの統合の出典 | **出典の誤り** | 計画の URL は macOS / Windows のページ。Android / iOS の出典は https://flutter.dev/blog/whats-new-in-flutter-3-29 。無効にする選択肢は flutter/flutter#174408（2025-08-28）で削除済みなので、今の Flutter では避けられない |
| `JNI_OnLoad` は `dlopen` では呼ばれない | 正しい | ART の `JavaVMExt::LoadNativeLibrary` だけが `JNI_OnLoad` を探す |

## 改善点

### 区分 A（後の成果物を変える）

| ID | 節 | 問題 | 提案 | 出典 |
|---|---|---|---|---|
| A-1 | 6 / D-5 / 9 | 「45 操作 + 権限の要求」を完了条件にすると、イベントと listener（Clipboard の変更、通知のアクションと shown、Chooser Action、Dialog と Share の完了）が抜けたままブリッジを消せてしまう | 69 メソッドの対応表とは別に、イベントの種類・登録・解除・配送・`release` を含む「振る舞いの集合」を定義し、機械照合と DoD の対象にする | Codex |
| A-2 | 3.2 / D-10 | `armeabi-v7a`（32 ビット）を出しながら、64 ビットが前提の `struct_size` の規則（sizeof を 8 バイトの倍数で増やす、最小の大きさを「2.0.0 の sizeof」に固定、ヘッダーの `/* sizeof 56 */`）をそのまま引き継いでいる。32 ビットではポインタが 4 バイトで、`ntk_dialog_alert_request` は 44 バイトになる。照合スクリプトの sizeof の照合と、1 つのヘッダーから作るバインディングが成り立たない | 32 ビットを落とす（`arm64-v8a` と `x86_64` だけ。Windows の E-17 と同じ前提）か、`struct_size` の規則を ABI ごとに書き直す。D-10 で決める | Claude |
| A-3 | 1.4 / D-11 / D-15 / 段階 0e | 影響の見積もりが小さい。改名で `AlarmManager` に登録済みの PendingIntent の明示的なコンポーネント（`ScheduledNotificationReceiver`）が無くなり、予約した通知は**表示もされない**。保存した Parcel にはクラス名が入っており、改名後は `loadAll` の `runCatching` で黙って捨てられ、`restoreScheduled` も作り直せない。R8 で難読化しても同じ形で壊れる | 0e の前に、旧データの扱い（移行・互換の Receiver・明示的な破棄）を決める。保存形式をクラス名に依存しない形（JSON など）に変えるかも決める。1.x から 2.0.0 への実際の更新テストを足す | 両方 |
| A-4 | D-7 | 「透明な Activity に統一」の根拠が崩れている。主な利用者の GameActivity は `FragmentActivity` なので、今のブリッジはゲームの上にそのまま Dialog を出している。統一すると、ゲームが新しく止まる（`onPause`）。透明な Activity は、Android 10 以降のバックグラウンドからの Activity の起動の制限も回避できず、回転やプロセスの死の後に native のコールバックを保つことも保証しない | D-7 を決め直す（ホストが `FragmentActivity` ならその上に出し、違えば透明な Activity）。前面にいることの前提と専用のエラー、同時の要求、タスクと launch mode、終わる条件、回転とプロセスの死のときの結果の契約を設計書の項目にする | 両方 |
| A-5 | D-17 / 3.1 | 根拠が誤り（上の事実の照合）。POM が無いと、Gradle は利用者が宣言した古い androidx を選び、`NoSuchMethodError` になりうる。`UnityPlayerActivity` を選んだ利用者には appcompat も fragment も入らない。「Maven で配るには Maven Central の登録と署名が要る」は二択として誤りで、`maven-publish` でファイルの Maven リポジトリ（POM と Gradle Module Metadata 付き）を `dist/` に置けば登録なしで依存を伝えられる | D-17 を決め直す（`dist/<版>/android/` にファイルの Maven リポジトリも置く案を足す）。依存の一覧はビルドから機械的に作り、DoD で照合する。使っていない `material` を外し、appcompat も外せるか検討して、利用者の依存を減らす | Claude（Codex も、依存を持たない AAR を 2 つ手で入れる前提が 3.1 に無いと指摘） |
| A-6 | 4 / D-6 | プロセスの死やコールドスタートの後は、利用者の関数ポインタがまだ登録されていないので、通知のタップ・アクション・dismiss が捨てられる（今のブリッジも同じ）。androidx.startup で `.so` を読み込んでも、利用者の登録は戻らない | ハンドラが登録されるまでイベントを保ち、登録したときに 1 回だけ渡す（Windows のコールドスタートの活性化と同じ考え方）か、取りに行く API にする。順序、重複、期限を契約にする | Codex |
| A-7 | D-4 | `ntk_android_init` の契約（JavaVM の一致、Context の参照の持ち方、Application の Context にするか、2 回目の呼び出し、途中の失敗、Java の例外の扱い、終わるときのグローバル参照の解放）が無い。`System.loadLibrary` を通らずに呼ばれると `JNI_OnLoad` が走らず、システムの ClassLoader ではアプリのクラスを引けない。「androidx.startup がどの利用者より先に必ず走る」も、ContentProvider の順序と、利用者が manifest で無効にできることを考えると強すぎる | すべての入口で初期化の状態を確かめる。明示的な初期化では `context.getClassLoader()` からクラスを引く。`JNI_GetCreatedJavaVMs`（NDK の `jni.h` に宣言がある）で JavaVM を取れれば `ntk_android_init(void* context)` にできるかを 2a で確かめる。自動・明示・Startup の無効・`dlopen` だけ・別の provider が先、をテストする | 両方 |
| A-8 | 3.1 / D-6 | 3.1 は「コールバックは main から呼ぶ」、D-6 は「受け付けなかった失敗の `release` は呼び出し元のスレッドで呼ぶ」で、食い違う。main に積んだ後に解除・close・再入・post の失敗・差し替えが重なったときに、`release` がちょうど 1 回になる規則も無い | 完了とイベントのコールバックと、`release` の規則を分けて書く。状態機械と競合のテストを設計書で決める | Codex |
| A-9 | D-6 / D-8 | main をブロックしない規則が Dialog にしか無い。同期の関数を「main に投げて待つ」形で作ると、Flutter（Dart が main で動く）では呼び出し元自身が main なのでデッドロックする | C ABI 全体の規則として「どの関数も main を待たない。main で呼ばれたらその場で実行する」を足す。D-6 の括弧書きを「Unity では Activity の種類によらず」に直す | Claude |
| A-10 | D-4 / 3.1 | Initializer から得られるのは Application の Context だけ。今のブリッジはどのメソッドも Unity の Activity を受けている。Share と設定画面を開く処理を Application の Context で行うと `FLAG_ACTIVITY_NEW_TASK` が付き、Chooser のタスクの扱いが変わる | 設計書に「機能ごとに使う Context（Application / 前面の Activity / ホストの Activity）」の表を作る。前面の Activity を `ActivityLifecycleCallbacks` で追うかを決める | Claude |
| A-11 | 5 / D-2 | 段階 4 で古い AAR を消す前に、Unity が C ABI に移り終わっている条件が無い。`unity-native-plugin` の `PreBuildProcessor` は 2 つの古い AAR を必須にしており、`PostBuildProcessor` は KGP 2.0.21 を当てている（Unity 6000.4.4f1 以降の AGP 9 ではビルドの失敗の原因になりうる） | 段階 2c として `unity-native-plugin` の移行（AAR のコピー、P/Invoke、KGP の適用をやめて実行時の stdlib 2.2 以上と androidx だけを足す、Runtime / PlayMode / Player テスト）を置き、その成功を段階 4 を始める条件にする | 両方 |
| A-12 | 8.3 / D-14 | KGP 2.4.20 が確かめている範囲（AGP 9.3.1 / Gradle 9.7.0）の外を選んでいる | AGP 9.3.1 / Gradle 9.7.0 に下げる。外部の版情報は、確定する前に公式の出典でもう一度確かめる | Codex |
| A-13 | 3.3 | `Common.h` には Windows 専用のもの（`NTK_SYSTEM_CODE_E_OUTOFMEMORY` = HRESULT）と「DLL の版」の説明がある。`ntk_last_system_code` の意味は D-13 で決め直すので「違うのは版の値だけ」は成り立たない。`NTK_VERSION` が OS ごとの版か、OS をまたいだ規約の版かも決まっていない | `Common.h` を OS に依存しない部分と OS ごとの定数（`Windows.h` / `Android.h`）に分けるかを D-3 か D-13 で決める。`NTK_VERSION` の意味を決める | Claude |
| A-14 | 段階 1 / 7.1 | 「移す」と「ブリッジには手を入れない」を両立させると、段階 1 は移設ではなく一時的な複製になる（ブリッジは旧 Receiver を Intent に埋め込んでいる） | 複製の期間（段階 1 〜 4）と、その間にどちらを直すかの決まりを明記する | Codex |
| A-15 | 1.4 / agent-rules | 規則（全メソッドの先頭で全パラメータを `Log.d`）どおりに受け口を書くと、パスワードやクリップボードの本文がまたログに出る。C / C++ のログの規則も無い | 秘密の値は伏せる例外をルールに足すことを段階 1 の前提にする | Claude |

### 区分 B（検証の手段を変える）

| ID | 節 | 問題 | 提案 | 出典 |
|---|---|---|---|---|
| B-1 | 7 | テスト専用の JNI の入口の置き場所、version script でテスト用のものが混ざらないこと、`RegisterNatives` の失敗、R8 を有効にした利用者、Startup の無効、Modified UTF-8、attach / detach、ABI ごとの構造体の配置、の確かめ方が無い。AGP はビルドの種類ごとに組むので、「debug の androidTest のときだけ組む」では debug の AAR にテスト用の `.so` が入る | テスト用の入口は別のモジュール（smoke と同じ形）の別の `.so` に置く。R8 を有効にした release の利用者のアプリを確認の組み合わせに足す。D-10 に「native メソッドはすべて `JNI_OnLoad` の `RegisterNatives` で登録する」と書く | 両方 |
| B-2 | 3 / 7 | smoke のモジュールが `project(":android_library_capi")` に依存すると、配布物だけで使えることを確かめられない | 一時的なリポジトリかファイルの AAR から、2 つの AAR だけを解決する。Prefab、C99 / C++、全 ABI のリンクを確かめる | Codex |
| B-3 | 段階 0f / 7.2 | targetSdk 36 で変わる振る舞いは API 36 の端末でしか出ないが、基準を取るエミュレータは API 35。0f は AGP 9 の DSL・組み込みの Kotlin・Dokka v2・依存 10 個・JVM 17・compileSdk 36・targetSdk 36 を 1 つにまとめ、テストを直すことも同じ PR で認めているので、差が出たときに原因を切り分けられない | 0f を 3 つに分ける（ビルドの道具 / 依存と compileSdk / targetSdk）。基準は API 36 のエミュレータでも取る。テストを直すのは targetSdk の段だけに限る | Claude |
| B-4 | 段階 0c / 8.3 | 0c で足すテストの依存（UiAutomator 2.4.0 など）が、0f より前の今のツールチェーンで入れられるか確かめていない | 0c のテストの依存は今のツールチェーンで入る版に固定すると明記する | Claude |
| B-5 | 段階の順序 | 段階 1 で足す Kotlin の API の形（イベントの口、ホストの Activity、権限の要求）は C ABI の要求で決まるのに、2a のスパイクと C ABI の設計が段階 1 の後にある。2a は段階 1 に依存しない | 2a を段階 1 の前に移す。段階 1 の設計書は、C ABI の設計書のスレッド・寿命・Context の章を先に決めてから書く。段階 3（照合スクリプト）を 2b と同時か先にし、2b の完了の条件に機械照合を入れる | Claude |
| B-6 | 7 / 7.1 | 段階 1 で移すロジックの多く（リソース名の解決、request code、Clipboard のエラー、Activity の要らない Dialog と権限の要求）は、サンプルの UI テストを通らない | 段階 1 の DoD に、移すロジックに当たるブリッジのテストを `android_library` のテストに書き直してすべて通すこと、新しい API を使う画面をサンプルに足して UI テストで通すこと、を足す | Claude |
| B-7 | 7.2 | 再起動の後の予約の復元は、テストのプロセスが再起動をまたげないことを理由に人の確認の候補にしているが、`test_android.sh` から 2 段の instrumentation / adb の手順で自動化できる | 予約、プロセスの終了か再起動、再接続、復元の確認を 2 段で行う仕組みにし、A-3 の更新テストにも使う | Codex |
| B-8 | 7 | テストの件数があいまい（Runtime 97 はメソッドの数で展開すると 116、サンプルの内訳が 1 件足りない） | ランナーが報告する展開後の件数を記録し、Android 向け・Editor だけ・端末だけを分ける | Codex |
| B-9 | 9 / 8.3 | 8.3 は依存の AGP の最大を 8.9.1 として Unity の対象を決めているが、DoD は「8.10.0 以下」で合格にしている。依存が 8.10.0 に上がっても通り、Unity の対象が黙って変わる | DoD を「8.3 の表と一致すること」にする。自分の AAR の `minCompileSdk=36` と `minAgpVersion` も確かめる | Claude |

### 区分 C（記述の整合）

| ID | 内容 | 出典 |
|---|---|---|
| C-1 | `scripts/publish_docs.sh` が `AndroidLibraryExample` の gradlew と `dokkaHtml` を呼んでいる。段階 0・0f（Dokka v2 で `dokkaHtml` が無くなる）・4 で壊れるが、対象に無い | Claude |
| C-2 | 段階 5 に、既存のマニュアルの `android.library.*` の書き換え（dialog と notification の 3 言語で計 75 か所）と、2.0.0 の移行ガイド（3 言語）が無い | Claude |
| C-3 | D-16 の「段階 7 に当たる CI」は、この計画に段階 7 が無い（Windows の段階 7 を指している） | Claude |
| C-4 | 「サンプルが 3 つの Receiver を重複して持つ」は、Toast や画面内の broadcast を含むサンプル固有の実装なので、単純な重複ではない | Codex |

## 不足項目

- Windows の README 6 章「段階ごとに壊れる場所」に当たる表（Claude）
- manifest の merge で利用者に入る権限とコンポーネント（`USE_FULL_SCREEN_INTENT`、`SCHEDULE_EXACT_ALARM`、前景サービスの権限、`RECEIVE_BOOT_COMPLETED`、exported の BootReceiver、前景サービス 2 つ）。C ABI を使うゲームにも全部入り、Play Console の申告の対象になる。任意の権限を利用者が選ぶ形にするか、`tools:node="remove"` の手順を書くか（Claude）
- `consumer-rules.pro` の中身（JNI から引くクラスと native メソッド、manifest の Receiver と Activity、Initializer、Parcel で保存するクラス）と、R8 を有効にした smoke（両方）
- JNI の作法（attach と `pthread_key` での detach、Go のようにスレッドを渡り歩く呼び出し元、JNI を呼ぶたびの例外の確認、Kotlin の例外とエラーの値の対応表）（両方）
- マルチプロセスのアプリ（`InitializationProvider` は既定のプロセスでしか動かない）（Claude）
- minSdk 31 の影響の評価（Unity 25、Flutter 24 の利用者に Android 7〜11 を切り捨てさせる。古い OS では `NOT_SUPPORTED` を返す形を検討した記録が無い）（Claude）
- GoogleTest のライセンス（BSD-3-Clause）と、ソースを取り込む場合の置き場所（Claude）
- `unity-native-plugin` の Runtime テストの約 60 件は JSON の組み立てと解析で、C ABI では意味を失う。「書き換え」ではなく「作り直し」として何を基準にするか（Claude）
- Unity の書き出し済みのプロジェクトの minSdk が 31 になっている理由（自動か手動か）（Claude）
- Unity / Flutter / Rust・NDK ごとの導入の手順（AAR の置き場所、Gradle の依存、`.so` の名前、Prefab、初期化、コールバックの受け方、R8、minSdk と ABI）（Codex）

## 総合評価

段階の骨組み（テストをそろえる → 改名 → ツールチェーン → 移設 → C ABI → 削除）と依存の向きは Windows の手本に沿っていて妥当である。ただし、このまま進むと後の成果物の契約が変わる箇所（A）が 15 ある。とくに影響が大きいのは次の 5 つで、どれも決定（D-5、D-7、D-10、D-11、D-17）の前提を変える。

1. イベントが完了条件に入っていない（A-1）
2. 32 ビットと `struct_size` の規則が合わない（A-2）
3. 改名で予約済みの通知が表示も復元もされなくなる（A-3）
4. 主な利用者の GameActivity が `FragmentActivity` で、D-7 の統一は後退になる（A-4）
5. D-17 の根拠が誤りで、登録の要らないファイルの Maven リポジトリという選択肢が抜けている（A-5）

README を直し、決定を決め直してから、レビュアーを替えてもう 1 回通す。外部の版情報は公式の出典で確かめ終えた（直すのは A-12 と、CMake の既定と Flutter の出典の 2 か所）。
