# Android の C ABI から引き継ぐ知見

- 記録日: 2026-10-18
- 出典: Android の C ABI（`artifact/topics/android-c-abi/`、1.13.0）を進めたセッション（native-toolkit-ea）から、iOS の企画のために受け取ったまとめ。章の番号は `android-c-abi` のもの。「推測」と書いたものは向こうでも確かめていない
- 置いた理由: 個々の事実は `android-c-abi` の README・設計書・段階の結果・申し送りにあるが、「iOS で最初から気を付けること」としてのまとめはどこにも無かった。向こうは develop にいて、このブランチとぶつけないため、こちらに書く
- 使い方: `README.md` の企画が、各項目をどの決定（D-n）か章で扱うかを示す

## 1. やり直した決定と遠回り

| 項目 | Android で起きたこと | iOS で最初にすること |
|---|---|---|
| D-7（Activity が要る機能の出し方） | 「いつも透明な Activity を前に出す」から「前面の Activity の上に出す」に変えた。Unity の GameActivity が FragmentActivity なので、前者ではダイアログのたびにゲームが `onPause` する | ホスト（Unity の `UnityAppController` / ルートの ViewController、Flutter）がどの型の画面を持つかを、企画の段で調べる |
| D-10（32 ビット） | レビューで `armeabi-v7a` を外した（`struct_size` の規則とヘッダーの `/* sizeof N */` が 64 ビット前提）。さらに 2c で、Prefab を有効にした Unity の `unityLibrary` では 32 ビットを含むと `CXX1210` でビルドが止まると分かり、申し送りの「落ちずに `DllNotFoundException`」が誤りだった。smoke（Prefab を使わない）でしか確かめていなかったため | 本物のホスト（Unity の実際のビルド）での組み込みを早めに 1 回通す |
| D-11（1.x の予約） | 2 回決め直した。パッケージ名を変えると、保存した PendingIntent を作り直せない | モジュール名・クラス名・識別子を変えるなら、1.x が保存したもの（通知の identifier、UserDefaults のキー、カテゴリ）が更新の後どうなるかを最初に洗う |
| D-17（配布） | 「AAR だけ」から「AAR と、POM・Module Metadata 付きの Maven リポジトリ」に変えた。AAR だけでは依存が利用者に伝わらない | xcframework の依存、Swift のランタイム、SPM / CocoaPods のメタデータ、最小の Xcode と Swift の版を、配布の形として最初に決める |
| D-6 → AC-5 | 「main から呼ばれたらその場で実行」をやめ、「main から呼ばれても必ず積んで、完了で返す」にした。順序と再入が、呼ぶスレッドで変わらないようにするため | main キューへの async だけにし、main で同期して待つ形（`dispatch_sync` など）は作らない。Unity の iOS はスクリプトが UI の main スレッドで動くので、待てば必ずデッドロックする |
| 登録の状態機械（Registry） | 「main に積めなかった解除」の巻き戻しに、レビュー 3 回かかった。キューの形から、登録ごとの印の形に変えた | 失敗の経路（積めない、途中で例外）を、状態機械の表に最初から入れる。`dispatch_async` は失敗しないので、この種類は小さくなるはず（推測） |
| プロセスの終わりの C++ の静的オブジェクト | デストラクタを持つ静的オブジェクト（`__cxa_atexit`）は、終わるときにほかのスレッドとぶつかる。実行時のテストでは確かめられず、`NeverDestroyed`（placement new）にし、配布物の照合で `__cxa_atexit` などを import していないことを見る形にした | C++ の静的オブジェクトを持つなら同じ問題がある |
| ツールチェーン | 0f で AGP を 9.3.1 に上げたとき、Android Studio の対応を確かめておらず、Panda 1 では開けないとリリースの後に分かった。JDK を Android Studio のパスに結び付けていて壊れた（2026-10-18 に Daemon JVM criteria と toolchain に直した） | 必要な Xcode の版（ビルドする側と利用者の側）と、Swift の言語モードを最初の表に入れる |
| 利用者の Kotlin の版 | KGP 2.4 の既定では利用者に Kotlin 2.3 以上を求めてしまう。`languageVersion` / `apiVersion` を 2.2 にし、POM の stdlib の版を固定した（1a の 3.6） | 相当するのは `BUILD_LIBRARY_FOR_DISTRIBUTION`（モジュールの安定性）と、最小の deployment target |
| dist | 2c で `unity-native-plugin` が試すには `dist/<リリース版>` が要り、利用者に指摘されて先に作った。`unity-native-plugin` の `PreBuildProcessor` は「最新の dist を前方一致で選ぶ」ので、新しい dist を置いた時点で向こうのビルドが壊れた（Windows の 1.12.0 でも同じ）。向こうは `VERSION.txt` で完全なファイル名に固定した | dist を置く日を向こうに知らせる |
| 順番 | 段階 3（ブリッジの削除）を利用者の決定で 2c の前に行い、「2c の成功」をリリースの条件にした。問題なく進んだ | 同じ形を使える |

## 2. iOS / macOS に関係する決定と保留

### 2.1 `Common.h`（AC-11、第 1 部 5.2）

`Common.h` は OS ごとに持ち、OS 間で次の 4 つの扱いで照らす。

| 扱い | 対象 |
|---|---|
| 一致させる（空白とコメントを除いて同じ） | 不完全型、`ntk_release_fn`、`ntk_version`、`ntk_last_system_code`、`ntk_string_*` / `ntk_bytes_*` / `ntk_string_list_*` |
| OS ごとの展開 | `NTK_CALL`（Windows は `__cdecl`、ほかは空） |
| 名前と計算だけ一致（値は OS ごと） | `NTK_VERSION_MAJOR` / `MINOR` / `PATCH` / `NTK_VERSION` |
| OS ごとに許す（許す名前の一覧を照合が持つ） | `NTK_SYSTEM_CODE_*`（Windows だけ） |

`NTK_VERSION` は、その OS のライブラリの版。1 つの C# のバインディングは、これを OS をまたいだ定数として持たず、OS ごとの期待値と実行時の `ntk_version()` を比べる。

### 2.2 照合

- `scripts/c_abi_contract_common.py` と `check_c_abi_contract_<os>.py`、`manual_c_examples_common.py` と `check_manual_c_examples_<os>.py` に分かれている。iOS / macOS は `_ios` / `_mac` を足す形
- 照合は、規則を 1 つずつ壊して落ちることを自己テストで確かめる（2a のレビューで、通ってしまう穴が見つかった）

### 2.3 名前と型

- 同じ意味の操作は Windows と同じ名前。Dialog は非同期だけなので、Windows（モーダルで塞ぐ）とは名前と形を分けた（AC-7）。Share は Android が最初なので、OS に依存しない名前にした。iOS は、Android の Dialog と Share の名前に合わせられるかを最初に見る
- 同じ名前でも、引数・値・構造体の配置は OS ごと（C# は機能ごとに OS 別に宣言する。申し送り 4.4）
- `ntk_last_system_code`: Android は常に 0 で、詳細は logcat に出す（AC-10）。iOS で `NSError` の code を入れるかは決めていない
- 要求の ID: Android は `uint64_t`、Windows は 32 ビット。iOS は最初から決める（64 ビットに合わせるのを向こうは勧める）
- コールバックで渡すハンドル: Android は所有権ごと渡し、受け手が `_free` する。Windows は戻るまで有効なだけ（借りる）。逆なので Unity の包みで混乱しやすい。iOS は最初に明示して決める
- 64 ビットだけ、`struct_size` の規則、公開シンボルは `ntk_*` だけ。Android は libc++ を静的にリンクして隠した（Unity の libc++ とぶつからないように。1a の 3.3）。iOS の `__Internal` は静的リンクなので、C++ のランタイムと内部シンボルの衝突は Android より出やすいはず（推測）

### 2.4 保留にしたトピック

- `feature-split-distribution`: 機能ごとの配布物。ほかの OS の C ABI の後に行う。iOS も、機能ごとに分けられる形（翻訳単位とヘッダーを機能ごとに）にしておくと後が楽
- `feature-scoped-testing`
- `memory-sanitizers`: iOS は ASan / TSan が使いやすい

### 2.5 Unity の記載

native-toolkit のマニュアルと README には書かない（利用者の決定。`android-c-abi` 段階 4 の結果の M-4）。`unity-native-plugin` のマニュアルが受け持つ。

## 3. `unity-native-plugin` への申し送りで分かったこと

iOS の `__Internal` でも起きそうなもの。

- `user_data` は登録ごとに別のものを、呼ぶ前に表へ入れて渡す。「`user_data` を NULL にし、出力の要求の ID で照合する」形（Windows の包み）は成り立たない。理由は、関数が戻る前に完了が来うることと、ID を持たないコールバックがあること（Share の完了、設定の画面、Clipboard の変更）。Unity の iOS は main スレッドで呼ぶので、「いつも積む」にしておけば戻る前に完了が来ることはなくなる（推測）が、それでも `user_data` を登録ごとにする設計が安全
- 表は 2 つ: `user_data` の表（スレッドの安全）と、manager の表（Unity のスレッドだけ）。コールバックの中で `user_data` から物を引いてから積む（後で引くと、`release` の後で消えている）。片付けは `release` の中だけ。`release` は登録ごとにちょうど 1 回来る。プロセスが終わるときは来ない
- コールバックで例外が C に抜けると、プロセスが終わる。`[MonoPInvokeCallback]` の本体はすべて try / catch で囲む。デリゲートは static に保つ
- 構造体の配置: C のテスト（`StructLayoutTest`）の `sizeof` / `offsetof` と、C# の `Marshal.SizeOf` / `OffsetOf` を、EditMode のテストで照らす形にした
- 差し替え型のリスナー: 配送が「今のハンドル」宛てでなければ捨てる。判定は Unity のスレッドで行う
- テストの作り直しの基準: Unity の Runtime テストの約 79 件は JSON の組み立てと解析のテストで、C ABI では意味を失い、書き換えではなく作り直しになった。申し送りに最初に書いた件数（約 60 件）は数え違いだった。実物を数えてから書く
- 古いものと新しいものの同居: Android は D-15 でパッケージ名が変わったので、古いブリッジと 2.0.0 を 1 つの APK に同居させられ、Unity は機能を 1 つずつ移せた。iOS で古い静的 xcframework（`unity-ios-native-toolkit`）と新しい C ABI を同時にリンクすると、シンボルの名前がぶつからないかを確かめておく（推測）。**訂正（2026-10-18、こちらの調査）**: `unity-ios-native-toolkit-1.3.0.xcframework` は静的ではなく dynamic の framework で、`@rpath/IosLibrary.framework` に依存する。同居の問題は、シンボルより先に「同じ名前の `IosLibrary.framework` を 2 つの版で埋め込めない」ことになる（`README.md` の D-12）
- Unity 6000.4.2f1 の API Updater は、名前が Unity で始まらないパッケージの `[MovedFrom]` を使わない（向こうの報告）

## 4. レビューで何度も指摘された種類

レビューは Claude のサブエージェントと Codex。

| 種類 | 例 | iOS での扱い |
|---|---|---|
| 何も確かめずに通るテスト | 2 件見つかった | 新しいテストは、守る対象を壊すと落ちること（ミューテーション）を確かめる |
| 文書とコードのずれ | 申し送りで、関数名、借りるか持つか、型（`ulong`）、件数、Gradle のタイミングが違っていた。設計書の決定の表が、決めた後も「設計で決める」のまま古くなっていた（リリースの直前に DoD を照らして見つかった） | 決めたら README の表をその場で直す |
| 失敗の経路 | 途中の失敗の巻き戻し（初期化、登録、main に積めない）、コールバックの中での取り消し（再入）、例外が残ったまま次の処理に進むこと | 設計書の状態機械と、テストに最初から入れる |
| 照合の穴 | 規則を壊しても通ってしまう | 照合の自己テスト（2.2） |
| マニュアル | サンプルのクラス名をそのまま例に書いた。「全機能を C ABI から使える」と言い過ぎた（共有の受け取りが無い）。ABI の絞り方（CMake の `abiFilters`）の誤り。移行の表の漏れ（1.x で表示中の通知、FileProvider の衝突） | 段階 4 のレビューの観点にする |
| マニュアルの見出しのアンカー | 同じページに Windows の「### C ABI」があると、Android の節を足したことで Windows の側が `#c-abi-1` にずれた。`verify_manual.sh` はリンク先があるかしか見ないので検出しない | iOS の節を足すと、さらにずれる。段階 4 で見出しの付け方を決める |

## 5. 運用の小さなこと

- 開いた Android Studio が adb のサーバーを起動し直し、端末のテストが途中で切れたことがある
- 並行のサブエージェントに下書きを書かせると、共有の scratchpad で同じ名前が上書きされた。担当ごとにファイル名を分ける（`android-c-abi` 段階 4 の結果の 5 章）
- エミュレータの全件の実行は不安定（落ちる、遅い）。基準の取り直しは Pixel を先に

`android-c-abi` に残っている小さなこと（README 5.3）: エミュレータの基準の取り直しと、`ShareUiTest` の s14 が時々失敗すること。
