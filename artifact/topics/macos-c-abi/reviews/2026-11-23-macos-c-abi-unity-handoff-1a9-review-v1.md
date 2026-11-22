# レビュー結果

- 日付: 2026-11-23
- 対象: `results/2026-11-23-macos-c-abi-unity-handoff-1a9.md`（1a-9 の申し送りの下書き）と雛形 `results/probes/1a9-unity-handoff/`（コミット前）
- トピック名: macos-c-abi（1a-9 の申し送り）
- 判定: **要修正 → 直した**（区分 A をすべて直し、組み直して smoke を流し直した。再レビューは親が決める）
- 別モデルによる独立レビュー: 実施済み（Claude のサブエージェントと Codex の 2 者で並行。互いの結果は見せていない）。全文は scratchpad の `review/handoff-1a9-claude-v1.md`・`handoff-1a9-codex-v1.md`
- 機械照合: 対象外（設計書ではない）。代わりに雛形の smoke（`smoke/run.sh`）を流し直した

区分: A = このまま渡すと向こうの確かめが誤った結論を出すか、決定の材料にならない、B = 確かめの手段の不足、C = 記述だけ。「出典」は指摘したレビュアーとその番号。R は統合後の番号。

## 件数

| 区分 | Claude | Codex | 統合後 |
|---|---|---|---|
| A | 5 | 7 | 10（両方が挙げたもの: R-A1・R-A3・R-A5〜R-A8・R-A10。片方が B か C にしたものも A にまとめた） |
| B | 9 | 7 | 11（両方が挙げたもの: R-B1・R-B10・R-B11。Claude の B-1 と Codex の B-1〜B-3 は A に入れた） |
| C | 13 | 2 | 12（両方が挙げたもの: R-C1。Claude の C-3・C-4・C-12 は A・B に入れた。R-C12 はこちらで足した） |

## 強み（両者）

- 1a-9 の項目のほぼすべてが M-1〜M-12 に入り、条件付きの決定（D-4・D-6・D-8・D-24）ごとに材料が出る形になっている（Claude）
- 3 章の記号・C の形・エラーの番号、C# の `DllImport` の引数と戻り値が、ヘッダーと `Entry.swift` と一致する（Claude）
- C# のデリゲートは `static readonly` と static の `[MonoPInvokeCallback]` で保たれ、GC で消える欠陥は無い。文字列は受け付けの中で Swift の値にするので、`byte[]` を非同期の間保つ必要は無い（Codex）
- `Main.cpp` の差し込みは、Unity の書き出しの `UNITY_ASAN` と `PlayerMain` の順を保っている（両方）
- Dialog の自動で閉じる処理は、前のモーダルが自分のアラートのときだけ閉じる（Claude）

## 区分 A

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| R-A1 | 両方（Claude A-1、Codex A-1） | M-1 の「呼んだフレームより後」は、完了が同じフレームの中で届いても契約どおり（iOS の 1 回目の結果でもそうだった）なので、正しい動きを不合格にし D-9・D-24 の見直しに誤って向かう。`after-return` を測る手段も無い | C# に `MarkReturned(tag)` を足し、完了と `release` の行に `after-return=` を出す形にした。M-1 の合格の条件を「戻った直後に立てた印が完了の時点で立っている」に替え、フレーム番号は記録だけにした（同じフレームでもよいと明記）。M-3 の echo も同じ扱い |
| R-A2 | Codex A-3 | 別のスレッドから呼んだとき、main に積んだ直後にそのスレッドが止まれば、入口が戻る前に main で完了が走りうる。smoke は `pthread_join` の後に main を回すので、この競合を見られない | **雛形に `ReturnGate` を足した**: 受け付けたすべての入口が最後に「戻った」印を立て、main での配送（完了・受け手の登録）は印が立つまで 1 ms ごとに積み直して待つ。smoke は別のスレッドを動かしている間に main を回す形にし、雛形だけの遅延のフック（`NTK_PROBE_ENTRY_DELAY_MS`。別のスレッドの入口が戻る前に眠る）を付けた実行を足した。300 ms のフックで、完了は戻りの 0.1〜1.1 ms 後に来た。**`ReturnGate` を一時的に外すと、完了が戻りの約 304〜310 ms 前に来て 4 件が落ちた**（守りが効いていることの確かめ）。`Common.h` と申し送りの約束に「始めた関数の中では呼ばない。別のスレッドの呼び出し元が呼び出しの後に実行するコードとの順は決まらない」を書いた |
| R-A3 | 両方（Codex A-2、Claude B-1） | M-3 の `Task.Run` の行で、`LogThread`→`Where()` が worker から `Time.frameCount`・`Time.realtimeSinceStartup` を読み、シーンの `Log` が画面に触れる。測る側の例外や競合を、ネイティブのスレッドの問題と取り違える | C# の `Log` をどのスレッドからでも安全にした（`Stopwatch` の時刻、`Pump` が main で写したフレーム番号、lock の中のファイルへの追記、画面へは `Pump` が main で渡す）。`LogThread` を `try`/`catch` で囲んだ。2 章 8 に「main 以外で `Time`・画面・`Debug.Log` を触らない」を書いた |
| R-A4 | Codex A-4 | M-7 で「すぐ Cmd-Q」だと、予約の処理（main に積み、OS の `add` も非同期）より先に終了しうる。バナーが出ない原因を install の失敗と取り違える | M-7 の手順を「`notification-done tag=72 error=0` と `release tag=72` が来るまで待ち、画面に『終了してよい』と出してから利用者に終了してもらう」に直し、予約を 20 秒にして、`pgrep` で終わったことを確かめる手順を足した |
| R-A5 | 両方（Claude A-2、Codex A-5） | M-7 の合格の条件が、D-4（間に合って届くか）を、未決の起動の分類（`launch=1`）に結び付けている | 合格の条件を「D-4 の材料: `m7-cold` がそのプロセスにちょうど 1 回届き、install が `didReceive` より前（`launch` の値は問わない）」と、「1a-8・D-7 の材料（合否ではない）: `launch`・取得・起動の通知の順と時刻」に分けた。要約の欄も `delivered=` と `launch=` に分けた。**あわせて雛形を直した**: 1a-8 の VM の測り（作業の記録 5.1）で `NSApp.isActive` が `willFinishLaunching` で既に true と分かったので、「入れた時点で active なら起動のきっかけ無し」の近道を外した（`willFinishLaunching` で入れるとコールドスタートを全部「無し」と誤るため）。active は `didBecomeActive` の通知だけで見る。記録に `didFinishLaunching` の `NSApplicationLaunchUserNotificationKey` の有無を足した |
| R-A6 | 両方（Claude A-3、Codex B-2） | M-7 でどのコピーが起動したかを確かめる手順が無い。何通りも同じ bundle id で組むので、LaunchServices が別のコピーを起動しうる。既存の書き出しの bundle id のままだと前の通知の許可を引き継ぎ、許可の求めが出ない | 確かめ専用の bundle id（`com.jonghyunkim.nativetoolkit.probe1a9`）を 2 章 4 に書いた。`Info.plist` の `NTKProbeBuildToken` を `ntk_probe_describe` が `build-token=` で返し、`pid=` と bundle の道（`~` で伏せる）も返すようにした。M-7 の合格の条件に「(b) の build-token で、前と違う pid」を足し、別のコピーが起動したらほかのコピーを消してよいかを利用者に尋ねる（1 回ごとの許可）、とした。**許可の状態を読む `ntk_probe_notification_get_authorization_status` を足し**、許可の求めが出なかったことを失敗にしない、と書いた |
| R-A7 | 両方（Claude A-4、Codex B-1） | M-11 は Mono の Hardened Runtime に要る JIT の entitlement が無く、関係の無い理由で落ちて D-18 の見直しに誤って向かうか、Unity の案内に従って `disable-library-validation` を足すと Library Validation を確かめないまま通る | M-11 を「(1) entitlement なしで起動し、落ちたらどの image が何の理由か（`Team IDs` なら framework の拒否、JIT なら Mono）を記録、(2) `allow-jit` だけを足す（それでも落ちるときだけ `allow-unsigned-executable-memory`）、**`disable-library-validation` は足さない**」にした。合格の条件に「実効の entitlement に `disable-library-validation` が無く、flags に `runtime`」を足した |
| R-A8 | 両方（Claude A-5、Codex B-3） | Share のピッカーを強く保たず、自動で閉じる処理が `[weak picker]`。AppKit が保たなければ閉じず、完了も `release` も来ない（1a-7 の試作は閉包が強く握っていた）。私物の画面にピッカーが開いたまま残る | `PickerBox` がピッカーを `didChoose` まで強く保ち、自動で閉じる処理は箱を通して `close()` を呼ぶ形にした。`share auto-close open=` を記録に出す |
| R-A9 | Codex A-6 | ホストの delegate を置く確かめが無く、全 M が通っても D-7 の転送の材料にならない。雛形の転送も、system の completion を前の delegate にそのまま渡し（二度呼ばれれば二度通る）、`openSettingsFor(nil)` を転送せず、`openSettingsFor` の転送に循環の防止が無い | **雛形の転送を iOS の `NotificationDelegateRouter` に合わせた**（`willPresent`・`didReceive` の completion を `CompletionOnce` で包む、`nil` の `openSettingsFor` はライブラリのものでないとして転送する、3 つとも同じ循環の鍵（method・identifier・date・action）で同期の循環を止める）。ホストの delegate を置く確かめは足さず、**申し送りの冒頭と 7 章に「1a-9 の結果では D-7 は決まらない」と書いた** |
| R-A10 | 両方（Codex A-7、Claude C-3） | 試しの dist を作るだけでは、`PreBuildProcessor` は隣の `native-toolkit/dist` を読んで `9.9.9` が無く止まる。`MacFrameworkPatcher` は dist を読まず `Plugins/macOS` の物だけを写す | 2 章 3 に、ビルドの段の経路は `NATIVE_TOOLKIT_DIST_ROOT=<試しの dist>` を入れること、メニューの経路は書き出しの前に 2 つを `Plugins/macOS/` に `ditto` で置くことを書いた。VERSION.txt のパスをフルで書いた。この準備の不足を D-24 の失敗に数えない、とした |

## 区分 B

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| R-B1 | 両方（Claude B-2、Codex B-7） | M-8 で echo が届かない・フレームが止まるとき、Unity の構造か雛形の誤りかを分ける記録が無い。1.x（A）との比べも無い。`runInBackground: 0` なので、フォーカスの変化で止まるのかモーダルのループで止まるのかも分けられない | 雛形の Dialog の入口の記録に、main の run loop の mode と呼び出し元の関数名（アドレスとパスなし）を足した。**比べるための A の形 `ntk_probe_dialog_show_alert_gcd_async` を足した**（1.x の xcframework を入れずに A と比べられる）。M-8 に A の比べ、`runInBackground = true` の比べ、`runInBackground`・`isFocused`・`OnApplicationFocus` と `Stopwatch` の記録を足した |
| R-B2 | Claude B-3 | 「ボタンから」の手順は利用者のクリックが要るのに、許可の欄に書いていない。M-8 は「人の操作が要らない」と書いていた | 手順を起動からの時刻で自動に始める形（`-ntkStep` の引数と `open --args`）を 2 章 8 に書き、クリックそのものを見る M-3 の `OnGUI` と M-10 (2) だけをボタンにした。各 M-n の許可の欄に「利用者の操作」を書いた |
| R-B3 | Claude B-4 | M-2 は、このリポジトリの写しを 6000.0.44f1 で開くと版が下がる、1.x の `__Internal` が `GameAssembly` のリンクに紛れる、`GameAssembly.xcodeproj` が書き出しの直下にあると `FindPbxprojPath` が止まる | M-2 を、両方のリポジトリの外の、6000.0.44f1 で新しく作った使い捨てのプロジェクト（パッケージなし）で行い、リンクと埋め込みは手か小さな PostProcessBuild で行う、とした。`GameAssembly.xcodeproj` の置き場を記録の項目にした |
| R-B4 | Claude B-5 | 「書き出しは `ENABLE_APP_SANDBOX = YES` が既定」は確かめられない（`Build/Mac` は手で足した見込み、Unity の雛形と build program に文字列が無い） | 2 章 9 を「`ENABLE_APP_SANDBOX = YES` を明示し、`codesign -d --entitlements -` で確かめる」にした。M-1 の合格の条件に `sandbox=1` を足した |
| R-B5 | Claude B-6 | 書き出すシーンにサンプルのシーンが入ると 1.x の `__Internal` を呼ぶ。`usePlayerLog = false` で `Debug.Log` は残らない。sandbox では `persistentDataPath` が container の中 | 2 章 4 に「書き出すシーンは確かめのシーンだけ」、2 章 8 に「ファイルが記録の正。場所は container の中」を書いた |
| R-B6 | Claude B-7 | 集中モードの許可に試すアプリを入れられるか分からない。許可の状態を読む手段が無い | M-7 の準備に「入れられたかを利用者に確かめ、入れられなければ集中モードなしで流すかを尋ねる」を足した。許可の状態は R-A6 の関数で読む |
| R-B7 | Claude B-8 | M-7 は 1 つの形でしか行わない。温かい起動の予約とアプリを後ろに回す操作が書かれていない | M-7 の (6) に「1 で届かなければ 2 でもう一度」、(7) に `m7-warm` の予約と利用者の操作を書いた |
| R-B8 | Claude B-9 | 1a-7 の Unity の部分のうち「key window が無いとき」が無い。`Update` の中とクリックの中は、どちらも積んだ先で出すので違いは `currentEvent` だけ | M-10 に (3)「利用者にほかのアプリを前に出してもらい、時刻の引き金で出す」を足し、(1)・(2) の意味を 1 行書いた。記録に `key=`・`active=`・`share no window` を足した |
| R-B9 | Codex B-4 | 最初の登録の後、受け手を全部外すと、その間のイベントは保たれずに消える（「受け手が無い間は 32 件保つ」に合わない） | C ABI の台帳が、有効な受け手が無い間のイベントを 32 件まで保ち、次の登録の中で渡す形にした。受け手の登録も `ReturnGate` で戻った後に入れる。ここでは bundle が無く流せないので、M-7 の (8) に「外した後の保持」を足した（できれば） |
| R-B10 | 両方（Codex B-5、Claude C-12） | `describe` が読み込んだ image の絶対パス（ホームを含む）を返し、伏せる前に画面・ファイルに残る。ログのファイルを消す手順も無い | 雛形がパスを `<名前>.app/…` か `~/…` の形でしか返さないようにした（smoke に「describe にホームのパスが無い」を足した）。0 章 6 と 5 章 3 に、試すアプリのログのファイルを書き写した後に利用者に知らせて消すことを書いた |
| R-B11 | 両方（Codex B-6、Claude C-4） | M-12 の `stage_a.sh`・`stage_b.sh` は前の `ntk-probe-1.0.0`・`NtkProbe` と 1.3.0 を決め打ちしており、そのままでは今回の 2 つを確かめない | M-12 に「写しを作り、置く物・名前・探す名前・照らす名前をこの 2 つに直して流す。照らした framework の名前と `built` を記録に出し、前の成功を流用しない」を書いた |

## 区分 C

| # | 出典 | 指摘 | 直したこと |
|---|---|---|---|
| R-C1 | 両方（Claude C-1、Codex C-1） | 雛形のソースのコミットの状態が「まだコミットしていない」と「コミット済み・push 済み」で食い違う | 親の書き換え（ソースはコミット済み・push 済み、xcframework は渡さず向こうで組む）に合わせ、冒頭と 6 章を直した。6 章は「コミットの直前の作業コピーから組んだもの（`built` の値）。ソースはそのままコミットした」と書いた |
| R-C2 | Claude C-2 | 「読むもの」に D-7 と D-18 が無い | 足した。作業の記録の 5 章（1a-8）も足した |
| R-C3 | Claude C-5 | `ExclusiveFullScreen` は macOS に無い | M-9 から外し、「macOS には無い」と書いた |
| R-C4 | Claude C-6 | `add_listener` の `release` は約束の文の例外 | 3 章の約束と `ProbeNotification.h` に「受け手の登録は完了を持たず、`release` は外した後に来る」を書いた |
| R-C5 | Claude C-7 | M-7 の期待の文字列が C# の出力の形と違う | 3 章に「出力は `欄=値` の並び。合格の条件は欄ごとに一致を見る」を書き、M-7 の条件を「…の欄を持つ行」にした |
| R-C6 | Claude C-8 | M-6 の「置き換えか追記か」は GUI のときだけ | 「batchmode で同じフォルダーにもう一度書き出す。GUI の問いを見るなら利用者に頼む」にした |
| R-C7 | Claude C-9 | シーンの C# も `#if` で囲む | 2 章 8 と `NtkProbeMac.cs` の先頭に書いた |
| R-C8 | Claude C-10 | `Main.cpp` の場所と、設定を入れるターゲット | `<product name>/Main.cpp`、product name のターゲット、`$(inherited)` を残すことを 2 章 6 に書いた |
| R-C9 | Claude C-11 | 埋め込んだ後の symlink の期待の本数 | 「`Headers` が外れ、4 本ずつ（`Versions/Current`・本体・`Resources`・`Modules`）。違えば記録」にした |
| R-C10 | Claude C-13 | M-5 の 3 回の起動の許可のまとめ方 | 0 章 2 に「1 つの M-n の中の複数の起動は、一覧にして 1 回の許可でよい。一覧に無い起動はしない」を書き、M-5・M-11 の許可の欄に書いた |
| R-C11 | Codex C-2 | M-8 の「A' の確定」は範囲が広すぎる（取り消し・ホストのモーダル・2 つ目は対象外） | 「Unity での A' の判断材料」に直し、残る基準と担当（第 1 部の前に native-toolkit）を冒頭と M-8 に書いた |
| R-C12 | こちら（直しの中で見つけた） | 置き場の行に、利用者のホームを含む絶対パスがあった（`device-testing.md` の「ホームのパスを書かない」） | `<native-toolkit>` に直した |

## 直さなかったこと

| 出典 | 指摘 | 理由 |
|---|---|---|
| Codex A-6 の一部 | 合成のホストの delegate を置いて、印の有無・selector の有無・同期の循環・二重の completion・`nil` の設定を Unity で試す | 通知を出して利用者のクリックが要る確かめが増え、1a-9 の目的（Unity の取り込みと install の時期）から外れる。転送は iOS と同じ形に直し、D-7 は 1a-9 では決まらないと明記した。転送の確かめは native-toolkit の第 1 部の前（VM の XCUITest で通知を操作できる。作業の記録の 4 章）で行う見込み |
| Codex A-3 の一部 | 別のスレッドの呼び出し元が呼び出しの後に実行するコードとの順まで保証する（受け付けと寿命の協調の設計） | C ABI からは呼び出し元のスレッドのその後が見えず、保証できない。ライブラリの入口が戻るまで待たせる形にし、その外は契約の外と明記した。本番の契約の書き方は第 1 部で決める |
| Claude B-2 の一部 | 1.x の `MacDialogManager`（A）を Unity の同じシーンで出して比べる | 1.x の xcframework を同じアプリに入れられない（VERSION.txt で外す）。代わりに雛形に A の形の関数を足した（R-B1） |
| Codex B-1 の一部 | NTK を呼ばない同じ設定の Unity のホストと比べる | dyld と crash の文で、framework の拒否（`Team IDs`）と Mono の JIT の失敗を分けられるので、記録の項目で分ける形にした |

## 確かめ（直した後）

- 組み直し: Xcode 26.6、Swift の警告 0 件。C ABI の公開シンボルは arm64・x86_64 とも `_ntk_*` の 19 個だけ（足した 2 つ: `ntk_probe_dialog_show_alert_gcd_async`、`ntk_probe_notification_get_authorization_status`）。symlink 5 本ずつ、install name `@rpath/…/Versions/A/…`、rpath に `@loader_path/../../..`。本体はリンカーの ad-hoc、`ditto` の写しを ad-hoc で署名し直すと `codesign --verify --strict` が通る
- smoke: arm64・Rosetta の x86_64 のそれぞれで、普通と遅延のフック（300 ms）付きの計 4 回、47 件ずつすべて通った。`dlopen` の兄弟の置き方も 2 つのアーキテクチャで通った。`ReturnGate` を外した組み立てでは、フック付きの 4 件が落ちた（元に戻して取り直した）
- `unity/Main.cpp` は 0〜3 の形でリンクでき、`unity/NtkProbeMac.cs` は Unity 6000.4.2f1 の Roslyn でコンパイルが通った（どちらも動かしていない）
- この Mac では画面・通知・クリップボードを使うものは動かしていない（区分 1 だけ）
