# iOS ライブラリ C ABI 実装設計書（第 1 部: スレッド・寿命・通知の delegate）

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/ios-c-abi/README.md`（以下「README」） |
| 対象段階 | 段階 1a の後、1b の前に第 1 部（この版。スレッド・寿命・入口の層・エラーの規則・文字列・通知の delegate・前面・メモリ）。段階 2b の前に第 2 部（関数の一覧、README 6 章の振る舞いの集合との対応表、エラーの表、付録 A のヘッダー） |
| 対象 OS | iOS 18.0 以降（D-15）。スライスは `ios-arm64` と `ios-arm64_x86_64-simulator`（D-11） |
| 作成日 | 2026-10-31（第 1 版） |
| 状態 | **決定（2026-10-31、利用者）。P1-1〜P1-24 はすべて推奨のとおり**（P1-10・P1-24 の D-5 の決め直しを含む）。レビューは v1〜v4 の 4 回で、v3 で約束の範囲を絞った。README の直し（11 章）は反映済み |
| 改訂 | v2: レビュー v1 を反映（R-1〜R-42）。v3: レビュー v2 を反映（R2-1〜R2-18）。**v5（2026-10-31）: レビュー v4（R4-1〜R4-9。A は 0）を反映した。要求の箱を受け付けの時点で作って表示の口に渡す（R4-1）、表示の途中の取り消しは `present` の完了まで閉じるのを待つ（R4-2）、ほかは書き方の直し**。**v4（2026-10-31）: レビュー v3（R3-1〜R3-19）と、その「決定」（利用者、2026-10-31）を反映した。同じ論点の A が 3 回続いたので、仕組みを足すのをやめて約束の範囲を絞った**: 循環の防止は最初の転送の呼び出しの中の同期の戻りだけを止め、それ以外はホストの契約違反とした（P1-21、5.12.5）。表示の完了がちょうど 1 回なのは、ライブラリが受け持つ終わり方と UIKit が知らせる終わり方だけとし、ホストが表示中に画面の構成を変える場合を約束の外にした（1.3、P1-14、5.13.1）。1 秒ごとの階層の見張りは外した。各版で直した所は各レビューの「対応」の列にある |
| ブランチ | `feature/NTKIT-18`（HEAD `aa8c9922`） |
| 前段階 | 段階 0a〜0g は完了（実機の `clipboard`・`files`・`reinstall`・`credentials` の 39 件と人の確認の手順書は残る）。段階 1a のシミュレーターの下調べは完了し、13 の決定をした（README 8.2.1） |
| 元にした文書 | Android の C ABI の設計書 第 1 部（`artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-c-abi-design.md`。以下「Android 第 1 部」）と第 2 部（`...-c-abi-design-part2.md`。以下「Android 第 2 部」）、そのレビュー（`android-c-abi/reviews/2026-10-04-android-c-abi-c-abi-design-review-v1.md`〜`-v5.md`）、Windows の C ABI の設計書（`artifact/topics/windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md`。以下「Windows の設計書」）、1a の作業の記録 2 つ（`results/2026-10-31-ios-c-abi-stage1a-entry-working-notes.md`。以下「1a 入口」、`results/2026-10-31-ios-c-abi-stage1a-delegate-working-notes.md`。以下「1a delegate」）と雛形（`results/probes/stage1a/`）、Android から引き継ぐ知見（`results/2026-10-18-ios-c-abi-android-lessons.md`。以下「知見」）、0e・0f の作業の記録（`results/2026-10-24-ios-c-abi-stage0e-working-notes.md`、`results/2026-10-25-ios-c-abi-stage0f-working-notes.md`）、今の Swift の API（`ios/IosLibrary/IosLibrary/`） |
| 後に続く文書 | Swift の API の補完の設計書（9.1 の条件を満たすように書く。README 5.1）、第 2 部（8 章と 9.2 の条件）、`unity-native-plugin` の agent への申し送り（10 章） |
| レビュー | v1・v2・v3（`reviews/2026-10-31-ios-c-abi-c-abi-design-review-v1.md`〜`-v3.md`。どれも要修正）、v4（`-v4.md`。範囲を絞った回。A は 0、B 5 件・C 4 件。v5 で直した）。P1 の一覧は利用者が決める |

- **`PLANNED_SYMBOLS_EXEMPT`**: この設計書は、まだ書かれていない C ABI と Swift の名前（`ntk_notification_install`、`NTK_NOTIFICATION_ERROR_WRONG_THREAD`、`Registration`、`CompletionOnce` など）を定める。名前が実装に存在するかの照合は、第 2 部と 2a の機械照合が受け持つ

## 0. この文書の読み方

| 印 | 意味 |
|---|---|
| D-n | README 8.1 の決定（2026-10-18、利用者）。この文書では変えない |
| 1a-n | README 8.2.1 の段階 1a の決定（2026-10-31、利用者）。この文書では変えない |
| AC-n / AP-n / E-n | Android 第 1 部・第 2 部、Windows の設計書の決定。README 3.2 の「そのまま引き継ぐ」に入るものは、iOS でも同じにする |
| **P1-n** | **この文書が出した提案**。4.2 の表に、案・推奨・理由を置く。2026-10-31 に利用者がすべて推奨のとおり決めた（推奨の欄に「決定」） |
| DF-n | Windows・Android と意図して違うところ（4.3）。本文では「（DF-n）」と書く |

本文の「〜する」は、決定（D-n、1a-n、引き継ぎ）に基づくものと、提案（P1-n）に基づくものがある。提案に基づく文には必ず P1-n を付ける。**例外は P1-10 と P1-24 で、どちらも D-5（C ABI の範囲）の決め直しにあたる**。

### 0.1 約束の範囲（レビュー v3 の決定）

この設計書が約束するのは、**ホストと利用者が契約を守る場合**の振る舞いである（UI テストの設計で守る相手を「うっかりした誤り」に絞ったのと同じ考え方）。契約の外の振る舞いは定めず、マニュアルに「してはいけないこと」として書く。

| 契約（ホストがしないこと） | 守られなかったとき | 節 |
|---|---|---|
| ライブラリから受けた通知を、ライブラリへ転送し直す。**ホストの側のことばでは: 前の delegate へ非同期に転送する delegate（completion を後で呼ぶ、別のキューや `Task` から転送する）を入れた後で、`ntk_notification_install` の入れ直しを呼ばない**（R4-9。前の delegate へその場で同期に転送する delegate の上なら入れ直してよい） | 最初の転送の呼び出しの中で同期に戻ってきたものだけ止める。ほかは定めない | 5.12.5 |
| ライブラリが表示している間に、window や `rootViewController` を差し替える、scene を外す、表示した ViewController や古い表示元を持ち続ける | 完了も `release` も来ないことがある。Dialog は要求の ID で取り消せば完了と `release` が来る（画面が閉じるとは限らない。P1-24。R4-8）。Share は取り消せないので `user_data` が漏れうる | 1.3、5.13.1 |

契約とは別に、**ホストの操作でなくても約束の外になるもの**: システムが後ろの scene を切り、表示した ViewController が解放されない場合（R4-4。P1-15）。完了も `release` も来ないことがあり、Share では `user_data` が漏れうる。ヘッダーとマニュアルに書く。

## 1. 利用者が最初に知ること

README 3.1 が冒頭に置くよう求める前提と、Windows の設計書 1 章・Android 第 1 部 1 章に当たる名前・受け渡し・スレッドの決まり。

### 1.1 Windows・Android と同じもの

次は Windows の設計書と Android 第 1 部をそのまま引き継ぐ（README 3.2 の「そのまま引き継ぐ」）。この設計書では繰り返さず、違うところだけを書く。

| 項目 | 出典 | iOS での注意 |
|---|---|---|
| 名前の規則（`ntk_<機能>_<動詞>`、ハンドルは不完全型、列挙は `typedef int32_t` と無名の `enum`、コールバックは `_fn`） | Windows の設計書 1.1、Android 第 1 部 1.1 | 同じ意味の操作は同じ名前（README 3.3）。Dialog と Share の名前は第 2 部の最初に Android と照らす |
| 受け渡しの 3 方式（出力のハンドル、`struct_size` 付きの構造体、ビルダーのハンドル） | Windows の設計書 1.2、E-5 | どれを使うかは第 2 部 |
| エラーは戻り値（機能ごとの `int32_t`、0 が成功、欠番は詰めない、0〜5 は共通の意味） | Windows の設計書 7.3、Android 第 2 部 AP-12 | 5.10。Notification に iOS だけの値が 1 つ（`WRONG_THREAD = 16`。P1-7）。Share と Clipboard にも Android に無い値が出る（`CANCELED` など。数は第 2 部）。Dialog は Android と同じ名前の値で足りる見込み |
| 出力引数: **ハンドルの出力は入口で必ず `NULL` を書いてから処理し、成功したときだけハンドルが入る。値の出力（列挙、真偽値、要求の ID）は成功したときだけ書く** | Windows の設計書 7.3 | 5.7 の手順 1、6 章（R-8） |
| メモリ（`_free` は確保した側、`_free(NULL)` は何もしない、読み取りのポインタは元のハンドルを解放するまで有効） | Windows の設計書 7.4 | **コールバックの引数は Android と同じ所有権ごと渡す形**（AC-18。5.8） |
| 入力（引数の文字列、配列、構造体とその中のポインタ、ビルダー）は**呼び出しの間だけ**有効であればよい。ライブラリは要るものを呼び出しの中で写す | Windows の設計書 7.4 | iOS では非同期の操作でも、**main に積む前に**深く写す（Swift の `String`・`Data`・値型に変える）。生のポインタを積まない。ビルダーは渡した時点の写しを使い、利用者は戻った後に解放してよい（5.7 の手順 1。R-5） |
| すべてのコールバックの第 1 引数が `void* user_data`、`release != NULL` ならちょうど 1 回 | Windows の設計書 7.5.1、AC-6、AC-21 | 状態機械は 5.7。iOS では「積めない」経路が無い（DF-10） |
| 非同期の完了は `uint32_t system_code` を引数で渡し、スレッドごとの値を更新しない | E-18 | iOS では常に 0（D-13、1a-3） |
| ライブラリはコールバックを呼ぶ間、利用者が触れるロックを持たない | Windows の設計書 7.5.5、Android 第 1 部 K-2 | 5.7 |
| 文字列は NUL で終わる UTF-8、`NULL` と `""` の区別、不正な UTF-8 は `INVALID_PARAMETER`、出力の不正なサロゲートと U+0000 は U+FFFD | Windows の設計書 7.6、E-7、E-15、E-16、AC-19 | 実装は 5.9（Swift の `String` を通す） |
| 真偽値は `int32_t`、0 で埋めた構造体が既定値、件数は `size_t` | E-8、E-9、E-17 | iOS は 64 ビットだけなので、`size_t` は 8 バイト（D-11） |
| `struct_size` の読み方（先頭 8 バイト、詰め物の明示、最小は 2.0.0 の `sizeof`、上限 4096、未知の部分は 0 なら受け付ける、8 バイトの倍数で増やす） | Windows の設計書 7.8 | **1a で確かめたのは `@c @implementation` から読めることだけ**（1a 入口 2.1 の `testStructSize`）。雛形は 7.8 の規則 1（`reserved` が 0 でなければ `INVALID_PARAMETER`）、規則 2 の上限 4096、規則 4（知らない部分が 0 でなければ `NOT_SUPPORTED`）を実装しておらず、後ろを 0xAB で埋めた構造体を受け付けるテストもある。**2b はこれを写さない**。`StructReader` は 7.8 の 5 つの規則のとおりに作り、規則を 1 つずつ壊すと落ちることをテストで確かめる（6 章。R-9） |
| 公開ヘッダーは `<stdint.h>` と `<stddef.h>` だけを include、ASCII、C99 と C++、include ガードと `extern "C"`、`#pragma pack(push, 8)` | Windows の設計書 7.2 | 機能のヘッダーが `Common.h` を include する書き方だけが違う（1a-5。5.2） |
| 64 ビットの要求の ID（使い回さない） | AC-17 | Windows は 32 ビット。iOS は Android に合わせる |
| Dialog は非同期だけ | AC-7、D-8 | - |
| 今のブリッジを 1 つずつ写さない。違いは第 2 部の対応表に書く | AC-23 | - |
| 値の補正をせず、エラーで返す | AP-8 | - |
| 入口で決まる失敗は戻り値、受け付けた後の失敗は完了の引数 | AP-19 | 5.10 |

### 1.2 iOS の前提（README 3.1）

前提の表は README 3.1 にある。この設計書が足すのは次の 3 つ。

| 前提 | 成り立たない使い方 | 節 |
|---|---|---|
| 2 つの xcframework（`ios-native-toolkit-2.0.0` と `ios-native-toolkit-capi-2.0.0`）は**同じ版の組**で埋め込む | 版の違う `IosLibrary` と `IosLibraryCApi` を混ぜること（P1-19） | 5.4 |
| 通知のイベントを受けるなら、受け手を登録する前に delegate が入っている（C の `ntk_notification_install` か、Swift の同じ口のどちらでもよい） | delegate を入れずに、またはその前に受け手を登録すること。登録は `NOT_INITIALIZED` を返す（P1-6） | 1.4、5.10 |
| コールバックは例外を外へ出さない（C++、Objective-C、Rust の panic、C# の例外） | 例外を出すコールバック。振る舞いは定めない（多くはプロセスが終わる。P1-16） | 5.11 |

Swift のアプリは C ABI を使わず、`IosLibrary` を直接呼ぶ（README 3.1）。Swift から C ABI を呼ぶこともできる（1a 入口 3 章の `swiftapp`）が、案内しない。

### 1.3 スレッドと完了の規則（D-6、AC-4〜AC-6）

**Windows の「オーナーのスレッドとメッセージループ」、Android の main スレッドに当たるのは、iOS の main スレッドと main キューである。** 利用者は run loop を回す必要が無い（UIKit が回している）。

| 規則 | 内容 |
|---|---|
| 呼べるスレッド | **すべての関数は、どのスレッドからでも呼べる**（main を含む）。**例外は `ntk_notification_install` だけで、main スレッドからしか呼べない**（1.4。D-4、D-6、1a-9） |
| main を待たない | **どの関数も、main スレッドの処理が終わるのを待たない**（D-6、AC-5）。`DispatchQueue.main.sync`、`dispatch_sync`、セマフォやロックで main の処理を待つこと、main への同期の受け渡しを作らない。`ntk_notification_install` も待たない（main 以外から呼ばれたら、すぐにエラーを返す） |
| いつも積む | main で動かす処理は、**main から呼ばれた場合も**その場では動かさず、main キューに積む（AC-5。知見 1 章）。例外は `ntk_notification_install`（その場で同期に終える。D-6）と、main を要しない同期の関数（ハンドルの読み取り、`_free`、`ntk_version`、`ntk_last_system_code`、解除・取り消しの受け付け。第 2 部で数える） |
| コールバックのスレッド | **完了・イベント・受け付けた後の `release` は、すべて main スレッドで呼ぶ**（main キューに積んだブロックの中。D-6、AC-4） |
| 完了の時刻 | 受け付けた操作の完了と `release` を、開始した関数の中から呼ぶことは無い。**main から呼んだ場合は、関数が戻った後に来る。main 以外から呼んだ場合は、関数が戻る前に（main の上で）来うる**（AC-5、Windows の設計書 7.5.4）。**契約は Android と同じで、出力引数（要求の ID など）が利用者に見える前に完了が来うると考え、完了と要求の対応付けは `user_data` で行う**。実装は出力を積む前に書く（P1-5）が、これは利用者に約束しない（2c の同じ C# のコードが Android でも動くように。R-11、DF-11） |
| 入口で拒んだとき | 入口の検査（`NULL`、不正な UTF-8、長さ、`struct_size`、範囲、入れる関数の前の受け手の登録。5.10）で拒んだときは、エラーを戻り値で返し、完了を**呼ばず**、`release` を**呼び出しスレッドで関数が戻る前に**呼ぶ（E-12、AC-6、D-6） |
| 受け付けた後の失敗 | 受け付けた後に分かった失敗（前面でない、ユーザーの取り消し、UIKit が表示を断った、scene が切れた、`IosLibrary` の失敗）は、**すべて完了の引数で返す**。戻り値は受け付けたことだけを表す（AP-19） |
| ちょうど 1 回の完了 | **受け付けた完了つきの操作は、プロセスが生きている限り、ちょうど 1 回完了する**（AC-22、K-3）。表示を伴う操作（Dialog、Share）では、**ライブラリが受け持つ終わり方（ボタンなどの handler、取り消し、表示の失敗）と、UIKit が知らせる終わり方（Share の完了の handler、表示した ViewController の解放）について約束する**（5.13.1、P1-14）。scene が切れたときは、表示した ViewController が解放されたときだけ完了する（P1-15。R4-4）。**ホストが表示中に window や `rootViewController` を差し替える、scene を外す、表示した ViewController や古い表示元を持ち続ける場合は約束の外**で、完了も `release` も来ないことがある（0.1）。システムが scene を切って ViewController が解放されない場合も同じく約束の外。Dialog は要求の ID で取り消せば完了と `release` が来る（画面が閉じるとは限らない。P1-24。R4-8）。**Share は取り消せないので、その場合は `user_data` が漏れうる**。ヘッダーとマニュアルに書く |
| 順序 | 1 つの登録への配送は、main キューに積んだ順に呼ぶ。イベントが起きた時刻の順ではない。別の操作どうしの完了の順は約束しない（`IosLibrary` の中の処理の長さで決まる） |
| 解除とイベント | **main から呼んだ解除は、その場で以後の配送を止める**。**main 以外から呼んだ解除は、`release` が呼ばれるまで配送が来うる**。どちらも、`user_data` を片付けてよいのは `release` の後（AC-6。5.7） |
| プロセスの終わり | プロセスが終わるとき（`exit`、OS が止める）は、**完了も `release` も呼ばない**（Android 第 1 部 1.3） |

**なぜ main を待たないか**: iOS の Unity の C# は main スレッドで動き（README 0 章。`UnityAppController+Rendering.mm` の `CADisplayLink`）、Flutter の Dart も 3.29 から main で動く（D-6）。ライブラリが main を待つと、main から呼んだ時点で必ず止まる。**同じ理由で、利用者もどのスレッドからも完了や `release` を同期で待たない**（Android 第 1 部 1.3）。

**なぜ main かどうかをスレッドで見るか**: 入れる関数は `pthread_main_np()`（main スレッドかどうか）で判定する。main キューかどうか（`dispatch_assert_queue` の類）で見ると、main スレッドの上で `DispatchQueue(label:).sync` の中から呼ばれたときに拒むことになり、UIKit と `MainActor.assumeIsolated`（どちらもスレッドで動く）と食い違う（1a delegate 4 章・5 章の D-6 の行）。ただし、main スレッドの上の `DispatchQueue(label:).sync` の中で `MainActor.assumeIsolated` が止まらなかったのは、iOS 18.3 のシミュレーターで 1 回測っただけである。26.x でも同じかを 1b で確かめる（R-23）。

**なぜ main から呼ばれても積むか**: その場で動かすと、main から呼んだときと別のスレッドから呼んだときで、画面の動きと状態の変わる順序が変わる（AC-5、知見 1 章）。Unity の C# はいつも main から呼ぶので、Unity では「完了はいつも関数が戻った後」になる。

#### 1.3.1 ハンドルごとの約束

| ハンドル | 作る・操作・解放 | 同時の呼び出し |
|---|---|---|
| イベントの登録のハンドル（型は第 2 部。Android の AP-6 に合わせる見込み） | どのスレッドでもよい | **解除は、同じハンドルのほかの呼び出しと同時に呼ばない。解除の後、そのハンドルは無効**（2 回目の解除は未定義。AC-17）。**ライブラリの側で解除・差し替えをすることは無い**（AC-21） |
| 完了つきの操作 | ハンドルを持たない（関数に完了のコールバック、`user_data`、`release` を渡す）。取り消せる操作は、出力引数で**使い回さない 64 ビットの要求の ID**（1 から増やす。0 は「無い」）を返し、取り消しの関数はその ID を取る | 取り消しはどのスレッドからでもよい。**完了の後の取り消しと、知らない ID の取り消しは何もしない**（Android 第 1 部 1.3.1）。ID を持たない一括の取り消しは作らない |
| ビルダー（使うなら。第 2 部） | どのスレッドでもよい | スレッドセーフでない。1 つのスレッドで作って渡す（Android 第 1 部 1.3.1） |
| 出力のハンドル（`ntk_string`、`ntk_bytes`、`ntk_string_list`）と、コールバックで受け取ったハンドル | 読み取りと解放はどのスレッドでもよい | 中身は不変で、読み取りどうしは同時でよい。**同じハンドルの `_free` を、そのハンドルの読み取りや、読み取りが返したポインタの使用と重ねないのは利用者の責任**（ライブラリは守らない。重ねたときは未定義。R-6） |

#### 1.3.2 コールバックの中と、`release` のロック

| 対象 | 規則 |
|---|---|
| すべてのコールバック | **main を長く塞がない**（ネットワーク、大きなファイルの読み書き、ほかのスレッドを待つこと）。コールバックは main で呼ぶので、塞ぐとアプリ全体が止まり、起動の間なら OS の見張り（watchdog）にアプリを止められうる。**例外を外へ出さない**（5.11） |
| コールバックの中から `ntk_*` | 呼んでよい（ライブラリの関数は main を待たないので止まらない）。解除も呼んでよい（main からの解除なので、その場で以後の配送が止まる）。`ntk_notification_install` も main なので呼べるが、起動の後なので 1.4 の「起動の後」の扱いになる |
| `release` が取るロック | 受け付けた後の `release` は main の上で呼ぶ。**入口で拒んだときの `release` は、登録・開始の関数の中で同期に呼ぶので、`release` が取るロックを持ったまま登録・開始の関数を呼ばない**（Android 第 1 部 1.3.2） |

#### 1.3.3 起動の途中と、終わり

| 時期 | 振る舞い |
|---|---|
| `UIApplicationMain` の前（`+load`、C の constructor、C++ の静的な初期化、`main` の中の `UIApplicationMain` の前） | **契約の外**。`ntk_notification_install` は呼ばない（D-4 で C を採らなかった理由と同じ。`UIApplication` がまだ無い）。main スレッドから呼べば判定（`pthread_main_np`）を通り、`NONE` を返して delegate を設定する見込みだが、`UNUserNotificationCenter.current()` がこの時期に使えるかを含めて確かめていない（G-9。R-40）。ほかの関数は呼べるが、完了は main の run loop が回ってから来る。確かめていない |
| `application(_:willFinishLaunchingWithOptions:)` から `application(_:didFinishLaunchingWithOptions:)` が戻るまで（scene のアプリは `scene(_:willConnectTo:options:)` が戻るまでも） | `ntk_notification_install` を呼ぶ期限（D-4、1a delegate 2.4）。`didFinishLaunchingNotification` の受け手からでも間に合う見込み（応答より先に来ることは測ったが、その受け手から入れてタップが届くかは測っていない推測。U-3 と 1b で確かめる。R-21）。ほかの関数も呼べる。前面が要る操作は、この時期は scene が前面に無い（scene のアプリでは `applicationState` が background）ので、`NOT_FOREGROUND` で完了しうる（P1-11） |
| 起動の後 | `ntk_notification_install` は成功を返してログを出す（1a-11）。コールドスタートのタップは失う。Unity の C#、Dart はこの時期に始まる（README 0 章、D-4） |
| 後ろにいる間（background） | 前面が要らない操作は動く。前面が要る操作は `NOT_FOREGROUND` で完了する（5.13）。表示中の Dialog・Share は、後ろに回っても取り消さない（P1-15） |
| 背景で止められている（suspended） | main は回らない。積んだ完了とイベントは、アプリが再び動くまで来ない。ライブラリも利用者も待たない契約なので、固まりはしない |
| 通知の背景のアクション（`options: []`）でアプリが背景で起動した | `didReceive` のイベントは保たれ（受け手がいなければ。5.12.7）、system の completion はその後に呼ぶ（1a-12）。アプリが止められた後、再び前面に来て受け手が登録されれば届く。その前にプロセスが終わると失う |
| 終わり（`exit`、OS が止める、`applicationWillTerminate(_:)` の後） | 完了も `release` も呼ばない。積んだものは捨てられる。ライブラリは静的なデストラクタを持たない（5.14） |

#### 1.3.4 言語ごとの受け方

| 言語 | コールバックの受け方 |
|---|---|
| C# / Unity | `[MonoPInvokeCallback]` の static メソッドで受ける。**本体を `try` / `catch` で囲む**（P1-16。Android と同じで、Windows とは違う）。iOS の Unity の C# は main で動くので、受けたスレッドがそのまま Unity のスレッドで、受け渡しは要らない。`user_data` は登録ごとに別のものを、呼ぶ前に表へ入れて渡す（知見 3 章） |
| Dart / Flutter | `NativeCallable.listener`（README 3.1。`isolateLocal` は使わない）。コールバックの戻り値はすべて `void`（5.8） |
| Rust | `extern "C" fn`。`user_data` で受けた状態を `Send` にする。`catch_unwind` で panic を止める |
| C / Objective-C | 普通の関数ポインタ。main は UI のスレッドなので、重い処理は自分のスレッドへ渡す。Objective-C の `@try` で止めるのは利用者の責任（ライブラリの中には `@try` が無い。5.11） |

### 1.4 通知の delegate を入れる関数（D-4、D-6、D-7、1a-9〜1a-11）

iOS には一般の初期化の関数が無い（D-4）。**通知の機能（イベントを受けること、前面にいるときの表示）を使うときだけ**、ホストのネイティブのコードが起動の処理の中で次を呼ぶ。

```c
/* Notification.h */
/* Installs the library's UNUserNotificationCenter delegate, keeping the current one as the
   previous delegate. Main thread only; synchronous; never waits. Call it before
   application(_:didFinishLaunchingWithOptions:) returns (or inside scene(_:willConnectTo:options:)).
   Off the main thread it returns NTK_NOTIFICATION_ERROR_WRONG_THREAD at once and does nothing. */
ntk_notification_error NTK_CALL ntk_notification_install(void);
```

名前は README 3.3 のとおり `Notification.h` の `ntk_notification_*` に置く。引数は持たない（P1-8）。

| 項目 | 契約 | 出典 |
|---|---|---|
| 呼べるスレッド | **main スレッドだけ**（`pthread_main_np()`）。main 以外から呼ばれたら、**積まずに、待たずに**、`NTK_NOTIFICATION_ERROR_WRONG_THREAD` を返す。delegate は変えない | D-4、D-6、1a-9、P1-7。1a delegate 4 章（0.2〜0.4 ms で返った） |
| 同期 | main から呼ばれたら、**戻る前に**転送の delegate（proxy）を `UNUserNotificationCenter.current().delegate` に設定し終える。proxy はライブラリが強く持つ（delegate は weak） | D-4、1a delegate 2.3・4 章 |
| 期限 | `didFinishLaunching` から戻るまで（scene のアプリは `willConnectTo` の中でもよい）。それより後はコールドスタートのタップを失う。main キューに積んで後で呼ぶのも間に合わない | D-4 の 1a、1a delegate 2.4 |
| 冪等 | 今の delegate が proxy なら、何もせずに `NONE`。proxy 自身を前の delegate にしない | D-4、1a delegate 4 章 |
| 差し替えられた後の呼び出し | 入れた後にホストが delegate を差し替えていたら、**入れ直して `NONE`** を返す（そのときの delegate を新しい前の delegate にする）。自動では入れ直さない | 1a-10 |
| 起動の後の呼び出し | `NONE` を返し、ログに出す。前面の表示とその後のイベントは受けられる | 1a-11 |
| 戻り値 | `NONE` か `WRONG_THREAD` のどちらか（ほかの値を返す経路は無い） | P1-7 |
| 呼ばなかったとき | 前面にいる間、通知は表示されない（delegate が無いと `willPresent` が呼ばれない。1a delegate 2.1）。C の口でも Swift の口でも proxy が一度も入っていなければ、通知のイベントの受け手の登録と、起動のきっかけの通知の取得は `NOT_INITIALIZED` を返す（P1-6）。表示・予約・取り消しなどの操作は動く | D-4、P1-6 |
| 外す関数 | 作らない（P1-8） | P1-8 |
| Swift の API | 同じ働きの口を `IosLibrary` に足し（今の `IosNotificationManager.setup()` に代わる）、C の関数はそれを呼ぶ。Swift と C の両方から呼んでも同じ proxy なので冪等。「proxy がこのプロセスで一度でも入ったか」を読む口も持つ（`Atomic` の印。C の受け口が P1-6 の判定に使う。S-14） | 9.1 の S-1、S-14 |

呼ぶ場所の例（README D-4）: Unity は `unity-native-plugin` の `.mm`（`AppDelegateListener` の `kUnityWillFinishLaunchingWithOptions` か `didFinishLaunching`。どちらが良いかは 10 章の U-3・U-4）、Flutter はプラグインのクラスが受ける起動の通知、C / Objective-C のアプリは `application(_:willFinishLaunchingWithOptions:)`。

## 2. 設計目的

- `UnityIosPlugin`（Objective-C の `.m` と JSON のブリッジ）に代わる、汎用の C ABI（`IosLibraryCApi`）を作る（README 1.1）
- C ABI は **`IosLibrary` の Swift の API の薄い包み**にする。振る舞いは Swift の API が決め、C ABI は型の変換、寿命の管理、スレッドの受け渡し、検査だけを受け持つ（README 3 章、Windows の E-2）
- Windows・Android と同じ規約にし、同じ意味の操作には同じ名前を付ける（README 3.2、3.3、D-3）。ただし iOS の前提（Swift の `@c`、UIKit の main スレッド、通知の delegate、scene）から来る違いは無理にそろえず、4.3 に理由とともに書く

## 3. スコープ

### 3.1 第 1 部（この版）

- 1 章の利用者の前提、スレッドと完了の規則、起動と終わり、入れる関数の契約
- 5 章の実装アーキテクチャ（成果物とフォルダ、ヘッダー、入口の層、ビルドと公開シンボル、2a の照合の形、スレッドの受け渡し、寿命と `release` の状態機械、コールバックの引数、文字列、エラーの規則、例外、通知の delegate、前面、終わり、ログ）
- README 8.6 のうち「C ABI 第 1 部」の行（前面の扱い、`release` の状態機械、例外、通知の delegate、文字列の変換、Swift の受け口の隠し方とクラス名）と、D-4・D-7 の「第 1 部で決めること」
- テストの方針（メモリとサニタイザーを含む。6 章）、第 2 部に送るもの（8 章）、後に続く文書の条件（9 章）、`unity-native-plugin` の agent に任せる確かめ（10 章）

### 3.2 第 2 部（2b の前）

- 機能ごとの関数の一覧と型、同期・非同期の別、コールバックの型、イベントの種類
- エラーの表（各機能の 6 以降の値）と、`IosLibrary` のエラーの case との対応表
- 今のブリッジの 43 関数と README 6 章の振る舞いの集合から新しい関数への対応表（README 5.1）
- 付録 A の公開ヘッダーの全宣言
- 8 章に挙げたこと

### 3.3 対象外

- Swift の API の補完の中身（イベントの口、Dialog の結果の型、エラーの case、転送の delegate の型の形）。この設計書は、それらが C ABI に対して満たすべき条件（9.1）だけを書く
- `IosLibrary` にあってブリッジが公開していない機能（D-5）
- macOS の C ABI（D-1）、App Extension（README 8.4）

## 4. 前提と決定

### 4.1 決定済みの前提（README 由来）

| 前提 | 出典 |
|---|---|
| C ABI の範囲は、今のブリッジの振る舞いの集合と、受け手の解除・起動のきっかけの通知の取得 | D-5、README 6 章 |
| 一般の初期化の関数は作らない。通知の機能を使うときだけ、ホストのネイティブのコードが起動の終わりまでに入れる関数を呼ぶ | D-4 |
| 完了・イベント・`release` は main に非同期に。入口で拒んだときの `release` は呼び出しスレッドで戻る前に。入れる関数だけは main からの同期 | D-6 |
| 通知の delegate は、起動の終わりまでに入れ、前の delegate を覚えて転送する | D-7、1a-6〜1a-13 |
| Dialog は非同期だけ | D-8 |
| 2 つの dynamic の xcframework（`IosLibrary` と、それに依存する `IosLibraryCApi`） | D-9 |
| C の入口は `@c @implementation`（Swift 6.3）。Objective-C は使わない。関数は `public`、Swift の名前は C の名前と同じ | D-10、1a-1 |
| `EXPORTED_SYMBOLS_FILE` で `_ntk_*` だけを公開する。capi の Swift のモジュールと `-Swift.h` を配らない。内部の C の名前は `ntk_` で始めない。2a でヘッダーの関数と公開シンボルを照らす | D-11、1a-2 |
| bundle id は `com.jonghyunkim.nativetoolkit.IosLibrary` と `com.jonghyunkim.nativetoolkit.IosLibraryCApi` | D-12 |
| `ntk_last_system_code()` と完了の `system_code` は常に 0。`_Thread_local` は持たない。詳細は `os_log` | D-13、1a-3 |
| 新しいコードは Swift 6 / complete で書く | D-14 |
| 最小 iOS 18.0。`Synchronization` の `Mutex` / `Atomic` を使える | D-15 |
| ビルドは Xcode 26.6（Swift 6.3）。利用者は Xcode 26.3 以上（C ABI だけなら Xcode 26 のどれでもよい）。条件は capi の Swift のモジュールを配らないこと | D-16、1a 入口 3 章 |
| 配る framework に署名しない。実機の署名の確かめは `unity-native-plugin` の agent の Release のアーカイブで行う | D-18、1a-4 |
| 機能のヘッダーは `__has_include` で framework の形を先に書き、モジュールの検証を有効のままにする | 1a-5 |
| 版は 2.0.0 | D-19 |

### 4.2 この設計書の提案（P1-n。2026-10-31 に利用者がすべて推奨のとおり決定）

| ID | 決めること | 案 | 推奨 | 理由 |
|---|---|---|---|---|
| P1-1 | 入口の層のファイルの形 | A: 機能ごとに入口のファイル（`<機能>/<機能>Entry.swift`。`@c @implementation` の関数だけを 1〜3 行で書き、受け口を呼ぶ）と受け口のファイル（`<機能>/<機能>Receiver.swift`。検査・変換・`IosLibrary` の呼び出し）に分ける。README 3 章の `Adapter/` は作らない。**capi の中で `public` にするのは入口の関数だけ** / B: 入口の関数の中に検査と変換を書く | **A（決定）** | 入口のファイルがヘッダーの写しになり、ヘッダーと見比べるレビューと 2a の照合（5.5）がしやすい。1a の雛形もこの形（`Entry.swift` 42 行で 14 関数）。受け口は普通の Swift の名前で書け、テストから直接呼べる。`public` を入口だけにすれば、2a が `public` の数で漏れを見つけられる |
| P1-2 | 受け口から `IosLibrary` への届き方 | A: `import IosLibrary` で、**公開の API だけ**を呼ぶ（機能ごとの manager。Android の AP-1 と同じ）/ B: `@_spi(CApi)` で C ABI だけの口を持つ / C: `@testable import` | **A（決定）** | README 4 章の目的（ネイティブの利用者が Swift だけで全機能を使える）と合う。C ABI が要る口は Swift の利用者にも要る。B は下線付きの機能に頼る（D-10 で `@_cdecl` を採らなかったのと同じ理由）。C は Release で組めない |
| P1-3 | 公開ヘッダーの nullability の注釈（`_Nonnull` など） | A: 付けない（Windows・Android と同じ。Swift の側はすべて Optional で受け、入口で `NULL` を検査する）/ B: 付ける | **A（決定）** | `Common.h` は OS 間で「空白とコメントを除いて同じ」に照らす（AC-11）ので、付けると Windows・Android の `Common.h` も変えることになる。`@c @implementation` は注釈の無いポインタを Optional で受ければ組める（1a 入口 2.2）。`NULL` の扱いは E-15 の規則で入口が決める |
| P1-4 | main への積み方 | A: C ABI の受け口は **`DispatchQueue.main.async`** だけで積み、ブロックの中で `MainActor.assumeIsolated` を使って `IosLibrary` の main actor の API を呼ぶ / B: `Task { @MainActor in }` で積む | **A（決定）** | 状態機械（5.7）は「挿入の後に外す」が積んだ順に動くことを前提にする。main キューが FIFO であることは GCD の文書にあるが、`Task` の開始の順は文書に無い。1a の雛形もこの形で、Swift 6 の complete で警告 0 件（1a 入口 2.2） |
| P1-5 | 出力引数を書く時期 | A: **契約は Android と同じ**（出力が利用者に見える前に完了が来うる。対応付けは `user_data`）。**実装は積む前に書く**が、利用者に約束しない / B: 契約も「積む前に書く」にする / C: 実装も受け付けの後に書く | **A（決定）** | iOS では `dispatch_async` が失敗しないので、積む前に書くのがいちばん単純。B の強い約束に利用者が頼ると、2c の同じ C# のコードが Android では壊れる。約束は OS をまたいで同じにする |
| P1-6 | `NOT_INITIALIZED`（共通の番号の 2）を iOS で返す場面（D-4 が第 1 部に任せたもの） | A: **通知のイベントの受け手の登録と、起動のきっかけの通知の取得だけ**が、**proxy がこのプロセスで一度も入っていない（C の口か Swift の口かを問わない）**ときに返す。印は `IosLibrary` の `Atomic` で、読む口を足す（S-14）。ほかの機能は返さない（番号は欠番にせず残す）/ B: 登録を受け付け、ログだけ出す / C: どこでも返さない | **A（決定）** | B では、入れ忘れた利用者がイベントの来ない理由を知れない（AP-8 の「黙って変えない」）。入れる関数はネイティブのコードが起動の中で呼び、受け手の登録は C# や Dart が起動の後に行うので、普通の順では起きない。表示・予約などは delegate が無くても動くので拒まない。入口の検査（引数）を先に、この確かめを後に行う（Android 第 2 部 11 章） |
| P1-7 | 入れる関数を main 以外から呼んだときのエラーの名前と番号、機能のエラーの番号の付け方（1a-9。**v4 で番号の表の置き場所を決めた**。R3-13） | A: **名前は `NTK_NOTIFICATION_ERROR_WRONG_THREAD`、番号は 16**。**機能ごとに、OS をまたいだ 1 つの番号の表（名前 → 番号）を `scripts/c_abi_error_numbers.json` に持つ。同じ名前は同じ番号、ある OS が使った番号を別の OS が別の名前に使わない、ある OS に無い名前の番号はその OS では欠番**。2a の照合（`check_c_abi_contract_ios.py` と `_android.py`）が、各 OS のヘッダーとこの表を照らし、どちらかの OS のヘッダーかこの表を変えたら両方を流す。**Windows は対象外**（C++ の `enum class` の順を写した別の番号。Clipboard の `WRONG_THREAD = 14` など。AP-12）/ B: 名前は `NOT_MAIN_THREAD`、番号は 6（共通の名前の値がすべて Android と番号違いになる）/ C: 番号は第 2 部で決める | **A（決定）** | Windows の Clipboard に同じ意味の `WRONG_THREAD` があり、同じ意味には同じ名前を付ける（README 3.3）。Android の Notification は 6〜8 が `CANCELED`・`CANCELED_BY_SYSTEM`・`NOT_FOREGROUND` で、B ではすべて番号違いになる。表を 1 つのファイルにして照合で強制すれば、OS ごとに宣言する C# のバインディング（RP-5）でも同じ名前が同じ番号であることを機械で守れる |
| P1-8 | 入れる関数の形と、外す関数 | A: **引数なし**（`ntk_notification_install(void)`）。外す関数は作らない / B: `struct_size` 付きの選択肢（前面の表示の選択肢など）を取る / C: A に加えて `ntk_notification_uninstall` を作る | **A（決定）** | 起動の処理から呼ぶ所で選ぶものが無い。前面の表示の選択肢は、今の `foregroundPresentationOptions` と同じく別の関数で後から変えられる（第 2 部）。関数は後から足せる。外すと、ホストの delegate を戻すか、前の delegate が既に無いか、で状態が増え、Unity の通知パッケージとの奪い合いも増える |
| P1-9 | ライブラリの通知の印（D-7 の「userInfo の印」） | A: **userInfo のキー `com.jonghyunkim.nativetoolkit`、値は整数 `1`（印の形の版）**。ライブラリが作るすべての要求（表示・予約・更新）に付ける。**利用者の userInfo にこのキーがあれば `INVALID_PARAMETER`**。イベント・予約の一覧・表示中の一覧で利用者に返す userInfo からは外す / B: 利用者のキーと重なったら上書きする / C: identifier の接頭辞で見分ける | **A（決定）** | 1a の雛形のキーと同じ（1a delegate 1 章）。値は plist の型でなければ保存されないので整数にする。重なりを上書きすると利用者の値が黙って変わる（AP-8）。外して返せば、利用者から見た userInfo は入れたとおりになる。C は利用者が identifier を決める API（`content.id`）とぶつかる |
| P1-10 | `openSettingsFor`（アプリの中の通知の設定の画面を開くよう求められた）を、ライブラリが受けるとき（**D-5 の決め直し**） | A: **イベントとして受け手に渡す**（通知のイベントの種類を 1 つ足す）/ B: 1.x と同じく設定の App を開く / C: 何もしない | **A（決定）** | これは「設定の App の中のリンクから、アプリの中の設定の画面を開いてほしい」という知らせで、1.x のように設定の App を開き直すのは意味が逆（1a delegate 3.4）。開く画面はアプリが持つので、アプリに知らせるしかない。1.x の動きは意味が逆なので、破壊的変更の 2.0.0 で直す。`notification` が `nil` のときは「ライブラリの通知でない」として扱う（5.12.3） |
| P1-11 | 「前面」の定義と、判定する所（README 8.6） | A: 今のまま（`IosLibrary` が `foregroundActive` の `UIWindowScene` を `first(where:)` で選ぶ）/ B: `IosLibrary` の既定の探し方を変える（1b で既存の動作が変わる）/ C: **`IosLibrary` の表示の口（Dialog・Share・権限の要求・設定の画面）に、表示元の決め方を選ぶ引数（`presenter`）を足す。既定（渡さないとき）は今の探し方のままで、待ちも入れない。新しい定義の前面か、呼び出し側が渡す ViewController を選ぶと、5.13.2 の手順で判定と表示を行う。C ABI の受け口は新しい定義の前面を選んで渡すだけ** | **C（決定）**（新しい定義の 2 つの前提が 1b で成り立つことが条件。成り立たなければ新しい定義を `foregroundActive` だけにする） | A は `connectedScenes`（`Set`）の順で選ぶので、iPad で前面の scene が 2 つあると決まらない。起動の直後や Control Center を引き出した間は `foregroundInactive` で、A では出せない。C は README 1b の「ネイティブの利用者から見た動作を変えない」を守り、判定・待ち・判定し直しを `IosLibrary` の 1 か所に置ける。今の public の `getRootViewController()` は残し、新しい定義の口は別の名前にする。前提 2 つは G-6 |
| P1-12 | 同時の要求（README 8.6。**v4 で手順を直した**。R3-6、R3-10、R3-11） | A: 落ち着いていればその上に重ね、移り変わりの途中なら失敗で完了する / B: 前の表示が閉じるまで待たせる / C: 何かが表示されていれば断る / D: **5.13.2 の手順: 落ち着いていなければ、移り変わりの終わり（`transitionCoordinator` の完了）か main キューの次の回を 1 回だけ待ち、その後の main キューの回でもう一度前面を探して確かめ、落ち着いていれば重ねて出す。2 回目も落ち着かなければ表示の失敗。待つ間に取り消されたら表示しない。待ちの列は持たない** | **D（決定）** | A では、同じ main の回で Dialog を 2 つ続けて呼ぶと 2 つ目が失敗する。Unity の C# は同じフレームで続けて呼びやすい。Android は両方出す（Kotlin の設計書 KA-4）。D は待ちを 1 回に限るので、B の列と取り消しの規則が要らない。coordinator の completion の中ではまだ落ち着いていない見込みなので、確かめは次の回に置く（G-4） |
| P1-13 | iPad のアクションシートと Share の基点（README 8.6） | A: **2.0.0 の C ABI は矩形を受けない**。基点はいつも最上位の ViewController の view の中央（今のライブラリの既定）/ B: key window の座標（point）の矩形を、省略できる項目として受ける | **A（決定）** | ブリッジも基点を受けていない（README 1.2）ので、D-5 の範囲に入らない。項目は `struct_size` の規則で後から足せる（Windows の設計書 7.8）。どちらの案でも、基点は表示の前に必ず設定する（5.11） |
| P1-14 | 表示の完了をちょうど 1 回にする仕組み（README 1.4 の「完了が 1 回も呼ばれない経路」。**v4 で約束の範囲を絞った**。R3-2、レビュー v3 の決定） | A: **約束するのは、ライブラリが受け持つ終わり方（ボタンなどの handler、取り消し、表示の失敗）と、UIKit が知らせる終わり方（Share の `completionWithItemsHandler`、表示した ViewController の解放）だけ**。解放は、要求の箱を持つ小さな見張りを表示する ViewController に関連オブジェクトで結び付けて見つける（外から `dismiss` された Dialog は、ライブラリも handler も持たないので解放される見込み）。ホストが表示中に画面の構成を変える場合は約束の外（0.1）/ B: A から解放の見張りを外す（外から閉じられた Dialog も約束の外になる） | **A（決定）** | 解放の見張りは、ライブラリが ViewController を強く持たないことだけを前提にする小さな仕組みで、ホストが契約を守る範囲では外からの `dismiss` と UIKit が断った表示を閉じられる。v3 の 1 秒ごとの階層の見張りは、移り変わりの一瞬や Share の活動の画面で本当の結果を誤って上書きする危険のほうが大きいので外した（R3-2、R3-5、R3-8）。外からの `dismiss` で解放されることは見込みで、1b で確かめる（G-7）。解放されないと分かれば、その経路は約束の外に移す |
| P1-15 | 後ろに回ったとき、scene が切れたとき（README 8.6。**v4 で範囲を絞った**） | A: **後ろに回っても取り消さない**（利用者が戻って選んだときに完了する）。**表示した scene が切れたときは、表示した ViewController が解放されれば解放の見張りで `CANCELED_BY_SYSTEM`。解放されなければ約束の外**（システムが切った場合を含む。Share では `user_data` が漏れうる。**v5 で書き足した**。R4-4）/ B: 後ろに回ったら取り消す | **A（決定）** | UIKit は後ろに回っても表示を残すので、戻った利用者はそのまま選べる。B はアプリの切り替えのたびに入力を失う。scene が切れたときの handler と解放は測っていない（G-7） |
| P1-16 | 利用者のコールバックの例外 | A: **コールバックは例外を外へ出してはならない。出した場合の振る舞いは定めない**（多くはプロセスが終わる）。ライブラリは捕まえない / B: C++ の小さな踏み台で C++ の例外を捕まえる | **A（決定）** | capi は C と Swift だけで書く（D-10）。Swift は C++ の例外も Objective-C の例外も捕まえられない。B は C++ を持ち込むうえ、Objective-C と C# の例外は止められない。1a で、main に積んだブロックの中の捕まえられない UIKit の例外は `SIGABRT` で終わることを確かめた（1a 入口 5.1）。**利用者のコールバックの C++・Objective-C の例外が Swift のフレームを越えるときの振る舞いは測っていない**（G-8。1b で 1 回確かめて記録する。R-24）。Android 第 1 部 5.11 と同じ扱いで、Windows の「包みが捕まえて捨てる」（7.7）とは違う（DF-9） |
| P1-17 | `@unchecked Sendable` と `nonisolated(unsafe)` を使ってよいもの | A: **使ってよいものを決めて一覧にする**。capi: (1) C のコールバックを main へ運ぶ箱（関数ポインタ、`user_data`、`release`）、(2) 登録（`Registration`。状態は `Atomic`）。`IosLibrary`: (3) system の completion を 1 回だけ通す包み（`CompletionOnce`。5.12.4）、(4) 要求の箱（5.13.1。`Mutex` で守る）と解放の見張り、(5) 関連オブジェクトの鍵（`nonisolated(unsafe) static let`。番地を鍵に使うだけ）。前の delegate に渡す closure は `@unchecked` にしない。それぞれに理由をコメントで書き、TSan のテストを持つ / B: 使わない | **A（決定）** | B はできない。`user_data`（`UnsafeMutableRawPointer`）と、SDK の delegate の completion（`@Sendable` でない）は `Sendable` にならない（1a 入口 2.2、1a delegate 5 章）。`IosLibrary` には前から `@unchecked Sendable` が 5 つと `nonisolated(unsafe)` が 1 つある（Clipboard）。(1) は `user_data` を `UInt(bitPattern:)` で運べば減らせるかもしれないので、2b で試す |
| P1-18 | C ABI のログ（D-13 の「`os_log` の subsystem とカテゴリ」） | A: **`os.Logger`、subsystem は capi の bundle id（`com.jonghyunkim.nativetoolkit.IosLibraryCApi`）、カテゴリは機能名（`Common`、`Clipboard`、`Dialog`、`Notification`、`Share`）**。関数名・エラーの値・ID・件数は `.public`、利用者の値は `.private`、秘密の値（パスワード、入力欄、通知の返信、クリップボードの本文、通知と Share の内容）は出さない / B: `IosLibrary` の `Log`（`print`）に合わせる | **A（決定）** | `IosLibrary` の `Log` は `internal` で capi から呼べない。`print` は Release でも出て伏せる仕組みが無い（README 1.4）。`os_log` は D-13 の決定。Swift の API の設計書がログの規則（README 8.6）を決めたら、出す項目をそちらに合わせる |
| P1-19 | 2 つの framework の版と、capi のライブラリの進化 | A: **同じ版の組だけを支える**。capi は `BUILD_LIBRARY_FOR_DISTRIBUTION=NO`（1a の雛形の設定）。`check_ios_dist.py` で 2 つの `CFBundleShortVersionString` が同じことを照らし、capi の最初の呼び出しで `IosLibrary` の版を読み、違えばログに出す（止めない）/ B: capi も `YES` にし、版の違う組も支える | **A（決定）** | capi は Swift の公開面を配らない（1a-2）ので、モジュールの安定性が要らない。版の違う組を支えると、確かめる組み合わせが増える。実行時のログで、利用者が組を混ぜたときに気付ける |
| P1-20 | メモリとサニタイザーの確かめ方 | A: **C ABI のテストを、シミュレーター（iPhone 17 / 26.2 と iPad Pro 11-inch (M4) / 18.3）で通常・ASan・TSan の 3 通りに流し、`test_ios.sh` につなぐ。実機（iPhone XS）の ASan は区切り（2b の DoD）でだけ、毎回利用者の許可を得て流す。実機の TSan は Xcode の文書で対応を確かめ、端末では試さない** / B: 実機でも毎回流す | **A（決定）** | ASan と TSan はシミュレーターで動き、TSan が実際に報告することも確かめた（1a 入口 5.4）。iPad の iOS 18 は popover の例外が出る唯一の環境（1a 入口 5.1）。実機は利用者の私物で、流すたびに許可が要る（`agent-rules/device-testing.md`、D-21） |
| P1-21 | 循環の防止の範囲（1a-8 の「循環を防ぐ」の形。**v4 で範囲を絞った**。R3-1、R3-3、レビュー v3 の決定） | A: **契約を「ホストは、ライブラリから受けた通知をライブラリへ転送し直さない」とする。防止は、3 つのメソッドそれぞれで、最初の転送の呼び出しの中で同期に proxy へ戻ってきた呼び出しだけを止める**（転送の呼び出しの間だけ、その通知の鍵を集合に入れる）。それ以外の転送し直し（completion を呼んだ後、別のスレッドやキュー、遅らせて戻す形）は契約の外で、振る舞いは定めない / B: v3 の形（completion と main の次の回まで鍵を持つ）/ C: 防止を入れない | **A（決定）** | ライブラリの通知はもともとホストに渡さない（1a-7）ので、循環はホストがホストの通知をライブラリへ転送し直したときだけ起きる。止めないと落ちるのは同期の再帰（1a delegate 3.3）で、A はそれを確実に止める。B は 3 回のレビューのたびにホストのもっと変わった振る舞いで穴が見つかった（R-2、R2-1、R3-1）。鍵の持ち主は proxy の集合だけで、包みを持たないので、包みの寿命と絡まない（R3-3） |
| P1-22 | 起動のきっかけの通知の見分け方（D-7 の追加） | A: **プロセスで最初の `didReceive`（転送したものも数える）が、プロセスで最初の `UIApplication.didBecomeActiveNotification` より前に来て、かつライブラリが扱った（ライブラリの通知、誰も受けない通知）なら、それを起動のきっかけとする。ホストへ転送したなら、起動のきっかけは無い。循環（転送の中で同期に戻ってきたもの）は起動のきっかけにしない（外側の `didReceive` をホストへ転送しているため。v5 で明記。R4-3）**。proxy を初めて入れた時点で `didBecomeActive` の受け手を登録し、そのとき既に `applicationState` が `active` なら起動のきっかけは無い / B: A のうち、背景のアクションを除く / C: 最初の `didReceive` を常に起動のきっかけとする | **A（決定）** | 関数の中で起動の途中かを知る方法は無い（1a delegate 4 章）。コールドスタートの応答は 1 つで、`didFinishLaunching`（scene では `willConnectTo`）から戻った直後に来た（1a delegate 2.4）。それがホストの通知なら、ライブラリの起動のきっかけは無い。B の「背景のアクション」は届いた時点の `applicationState` では見分けられない。C は起動の後に入れたアプリで普通のタップを誤る。scene のアプリでの `UIApplication.didBecomeActiveNotification` の順は測っていない（G-7） |
| P1-23 | `unity-native-plugin` への申し送りの分け方 | A: **2 回に分ける。1 回目（今）は 1a の入口の雛形に Dialog と Share の雛形の関数（10 章）を足して U-1・U-2・U-5・U-8・U-9・U-10（U-8 は結果を記録する）。2 回目は、1a の delegate の雛形を、入れる関数を `@c @implementation` にし、循環の防止を P1-21 の形に直してから capi の雛形に足し、通知の関数を入れて U-3・U-4・U-6・U-7。2 回目も Swift の API の設計書を書く前に頼む** / B: 1b の後に、本物の `IosLibrary` の口で U-3・U-4・U-6・U-7 を頼む / C: 雛形を全部そろえてから 1 回で頼む | **A（決定）** | U-3・U-4 の結果は 1a-13（ホストから応答を渡してもらう関数を足すか）を変え、それは Swift の API の形を変える。B では 1b を作り直すことになりうる。C は、通知に関係の無い U-1（D-9 を変えうる）の結果まで遅らせる |
| P1-24 | 要求ごとの取り消しの関数（**D-5 の決め直し**。**v4 で重なったときの動きを決めた**。R3-7、R3-12） | A: **Dialog は要求の ID で取り消す関数を出す（Android の `ntk_dialog_cancel` と同じ名前と意味）。取り消すと要求の箱を `CANCELED` で閉じ、Dialog の上にほかの画面が重なっていなければ閉じる。重なっていれば閉じずに残す（上のホストの画面を閉じないため。残った Dialog のボタンは閉じた箱に当たるので効かない）。Clipboard の読み込みは、今のブリッジの一括の取り消し（`clipboardCancelLoads`）を要求の ID ごとの取り消しに置き換える（一括は Unity の包みが ID を覚えて繰り返す。AC-23）。Share と通知の権限の要求は取り消しを出さない。取り消しが必ず効くように、`IosLibrary` の要求の手がかり（要求の箱）を受け付けの時点で C の受け口が作り、表示の口・読み込みの口に渡す（v5 で足した。R4-1。5.7、S-15）** / B: Dialog だけ出し、Clipboard はブリッジと同じ一括を残す / C: Dialog・Share・Clipboard のすべてに出す / D: どれも出さない（ブリッジの一括だけ） | **A（決定）** | Dialog の取り消しは Android にある（Android 第 2 部 OP-19）ので、同じ C# の包みで扱える。`dismiss` は上に重なった画面まで閉じるので、重なっているときは閉じない。Clipboard を ID ごとにするのは、ほかの取り消しと形をそろえ、一括で他人の要求まで止めないため（Android 第 1 部 1.3.1）。Share のシートを閉じる取り消しは Android に無く（Android の Share の取り消しは「選択の待ち」で意味が違う。OP-51）、ブリッジにも無い。通知の権限のシステムのダイアログは閉じられない |

### 4.3 Windows・Android と意図して違うところ

| ID | 項目 | Windows / Android | iOS | 理由 |
|---|---|---|---|---|
| DF-1 | 入口を書く言語 | C++（Windows は C++ の API を包む。Android は JNI で Kotlin を呼ぶ） | Swift の `@c @implementation` | D-10、1a-1。1 関数を 1 か所に書け、ヘッダーとの型の食い違いをコンパイラーが止める |
| DF-2 | 公開の仕方 | `.def`（Windows）、version script（Android） | `EXPORTED_SYMBOLS_FILE`（`_ntk_*`） | D-11、1a-2 |
| DF-3 | 初期化 | Windows は Runtime のハンドル、Android は Startup と `ntk_android_init` | 一般の初期化は無い。通知の delegate を入れる関数だけ（main からの同期。AC-5 の例外） | D-4、D-6 |
| DF-4 | `NOT_INITIALIZED` | Android は未初期化のすべての操作 | 通知のイベントの受け手の登録と起動の通知の取得だけ（P1-6） | iOS は初期化が要らない（D-4） |
| DF-5 | iOS だけのエラー | Windows の Clipboard に同じ名前の `WRONG_THREAD` がある。Android には無い | `NTK_NOTIFICATION_ERROR_WRONG_THREAD = 16`（P1-7）。同じ名前の値は Android と同じ番号 | 入れる関数が main だけ（D-6） |
| DF-6 | `ntk_last_system_code()` | Windows は OS の値。Android は 0 | 0（Android と同じ）。`_Thread_local` も持たない | D-13、1a-3 |
| DF-7 | 機能のヘッダーの `Common.h` の include | `#include "Common.h"` | `__has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)` の形（5.2） | 1a-5。モジュールの検証が `"Common.h"` を誤りにする |
| DF-8 | 利用者の include の書き方 | `#include <NativeToolkitC/Common.h>` | `@import IosLibraryCApi;`、`#include <IosLibraryCApi/NativeToolkitC/*.h>`、Swift の `import IosLibraryCApi`。`dist/include` の写しは `-I` で使う | framework の形（1a 入口 4.2）。`<NativeToolkitC/...>` は確かめていない（G-3） |
| DF-9 | 利用者のコールバックの例外 | Windows は包みが捕まえて捨てる。Android は `std::terminate` | 定めない（多くはプロセスが終わる。P1-16） | Swift は捕まえられない |
| DF-10 | 状態機械の「積めない」経路 | Android は `post` の失敗を表に持つ（印を付けて後で外す） | 無い | `dispatch_async` は失敗しない（D-6、知見 1 章） |
| DF-11 | 出力引数を書く時期（実装だけ。**利用者には見せない**） | Android は受け付けの後に局所の写しから書く | 積む前に書く（P1-5）。契約は Android と同じ（出力より先に完了が来うる） | DF-10 と同じ理由。契約を同じにするのは R-11 |
| DF-12 | UIKit・Foundation の例外 | Android は Java の例外を JNI の境界で捕まえる。Windows は C++ の例外を入口で捕まえる | 捕まえられない。起こさない検査を入口と表示の前に行い、起きたら落ちる | D-10、1a 入口 5.1 |
| DF-13 | 前面 | Android は前面の Activity（started で stopped でない）。判定は C ABI の受け口 | 前面（active か inactive）の `UIWindowScene` の key window（P1-11）。判定は `IosLibrary` の表示の手順（5.13.2）で、C ABI の受け口は方針を渡すだけ。Swift の API の既定は `foregroundActive` のままで、inactive の間だけ C ABI と違う | UIKit の形。意味は Android にそろえる。待ちと判定し直しを 1 か所に置くため `IosLibrary` に入れた（R2-4）。Swift の既定は 1b で変えない（README 1b の行） |
| DF-14 | 通知の delegate の転送 | 当たるものが無い | 5.12 | delegate が 1 つしか持てない（D-7） |
| DF-15 | 操作の同期性 | Android は Clipboard と、通知の表示・更新・消去・予約・問い合わせを同期で返す（AP-2・AP-3）。Windows も Clipboard は同期 | **Clipboard も Notification の操作の多くも、完了のコールバックで返す見込み**（第 2 部で決める） | `IosClipboardManager` は `@MainActor` で、C ABI は main を待てない（D-6）。`IosNotificationManager` の操作は完了で返す（0e 8.1）。今のブリッジもコールバック（R-31） |
| DF-16 | 実体を作れない時の値 | Android・Windows は `OUT_OF_MEMORY` を返しうる | 5（`OUT_OF_MEMORY`）は番号だけ残し、返さない | Swift はメモリの確保に失敗するとその場で止まる |
| DF-17 | プロセスの終わりの静的なオブジェクト | Android は `NeverDestroyed`（placement new）にした | C++ を持たず、Swift の大域の値はデストラクタを走らせない | 5.14 |
| DF-18 | 取り消し | Android は Dialog（OP-19）、通知の権限の要求（OP-39）、Share の選択の待ち（OP-51）を取り消せる。Android の Clipboard の読み込みは同期なので、取り消しが無い | Dialog と Clipboard の読み込みだけ（P1-24）。権限の要求と Share は取り消せない | iOS のシステムの権限のダイアログは閉じられない。Share の選択の待ちに当たるものが iOS に無い（完了で選ばれたアプリが分かる）。iOS の Clipboard の読み込みは非同期（DF-15）なので取り消しが要る |

### 4.4 不足前提

| ID | 不足している前提 | この設計書での扱い |
|---|---|---|
| G-1 | Swift の API の補完（イベントの口、転送の delegate の型、Dialog の結果、エラーの case）がまだ無い | C ABI が求める条件を 9.1 に書き、中身は Swift の API の設計書に任せる |
| G-2 | 本物の Unity での組み込み・起動の順・通知のパッケージとの共存・実機の振る舞いは、まだ誰も確かめていない | `unity-native-plugin` の agent に任せる（1a-4、README 5 章の 1a の行）。確かめることと、結果で変わる決定を 10 章に書く |
| G-3 | `#include <NativeToolkitC/Common.h>`（Windows・Android と同じ書き方）を iOS の framework で使えるかは確かめていない（1a 入口 4.2・8 章） | 2b の smoke で確かめる。使えなければマニュアルに iOS の書き方（DF-8）を書く |
| G-4 | `present` の直後の `presentingViewController`（表示の失敗を早く見つける補い）と `transitionCoordinator`、coordinator の completion の中で落ち着いているか（P1-12）、表示の途中（`isBeingPresented`）の `dismiss` が無視されるか（R4-2）、起動の直後の表示（0a の R-9）は確かめていない | 1b のテストで確かめる。`presentingViewController` が直後に設定されないなら補いを外す。`transitionCoordinator` が取れないなら、待ちは main の次の回の確かめ直しだけになる（5.13.2） |
| G-5 | 1a の雛形が `__cxa_atexit` などの終わりの登録を import していないかは見ていない | 2b の `check_ios_dist.py`（README 7.3 の「終わるときの処理」）で照らす |
| G-6 | P1-11 の定義の前提 2 つ: `foregroundInactive` の間も UIKit が `UIAlertController` と `UIActivityViewController` を表示できる、`isKeyWindow` が真の window がアプリで 1 つ（iPad の複数の window を含む）。測っていない（R-15） | 1b の iPad のシミュレーター（26.2 と 18.3）で確かめる。成り立たなければ口の定義を `foregroundActive` だけにし、P1-11 を直す |
| G-7 | UIKit の振る舞いで測っていないもの: 外から `dismiss` した Dialog と Share の ViewController が解放されるか（いつか）、そのとき `UIAlertAction` の handler と Share の `completionWithItemsHandler` が呼ばれるか、handler がどのスレッドで呼ばれるか。Share で活動を選んだとき、活動の画面の間に ViewController が解放されないか。scene を切ったときの handler と解放（P1-15）。`UIApplication.open` を後ろから呼んだとき。権限が未決で後ろにいるときの `requestAuthorization`。scene のアプリでの `UIApplication.didBecomeActiveNotification` の順（P1-22） | 1b で確かめて記録する。**外から `dismiss` した Dialog が解放されないと分かれば、その経路を約束の外に移す**（P1-14）。window や root の差し替えは約束の外なので確かめない（記録だけはしてよい） |
| G-8 | 利用者のコールバックの C++・Objective-C の例外が Swift のフレームを越えるときの振る舞い（R-24） | 1b で 1 回確かめて記録する（P1-16 の契約は変えない） |
| G-9 | `UIApplicationMain` の前に `ntk_notification_install` を呼んだときの振る舞い（R-40） | 契約の外のまま。1b で 1 回確かめて、マニュアルに書く |

## 5. 実装アーキテクチャ

### 5.1 成果物とフォルダ

README 3 章の木を、1a の決定（1a-1〜1a-3）と P1-1 に合わせて直したもの。

```
ios/
  IosLibraryCApi/
    include/NativeToolkitC/                 # 公開ヘッダー（xcframework の Headers/NativeToolkitC と dist/include に同じものを入れる）
      Common.h                              # Windows・Android と照らす（5.2）
      Clipboard.h  Dialog.h  Notification.h  Share.h
    IosLibraryCApi/
      module.modulemap                      # framework module IosLibraryCApi { header "NativeToolkitC/*.h" ...; export * }
      IosLibraryCApi.exp                    # _ntk_*（1 行）
      Common/
        CommonEntry.swift                   # Common.h の入口（ntk_version、ntk_last_system_code、ntk_string_* など）
        Handle.swift                        # 出力のハンドル（Unmanaged）と読み取り
        CApiString.swift                    # UTF-8 の入りと出（5.9）
        StructReader.swift                  # struct_size の読み方（Windows の設計書 7.8）
        Registry.swift                      # 登録、ID の表、帳簿、tryRelease（5.7）
        MainQueue.swift                     # main への積み方（P1-4）
        CApiLog.swift                       # ログ（P1-18）
      Clipboard/  Dialog/  Notification/  Share/
        <機能>Entry.swift                   # @c @implementation の関数だけ。1 関数 1〜3 行で受け口を呼ぶ（P1-1）
        <機能>Receiver.swift                # 検査・型の変換・IosLibrary の公開 API の呼び出し（P1-1、P1-2）
  IosLibraryCApiTests/                      # C ABI のテスト（XCTest から C の関数を呼ぶ。6 章）
  IosLibraryCApiSmoke/                      # dist の 2 つの xcframework だけを使う C / Objective-C のアプリ（Swift のコードを持たない）
```

- 依存の向きは `IosLibraryCApi` → `IosLibrary` だけ。`IosLibrary` は C ABI を知らない（README 3 章）
- C のファイルは持たない（1a-3 で `_Thread_local` が要らなくなったため）。`@c` で書けない形（可変長引数、`va_list`、変数。1a 入口 2.3）が要るようになったら、その関数だけ C のファイルにしてよい。その C の関数・変数の名前は `ntkc_` で始め、`ntk_` で始めない（1a-2、1a 入口 4.1）
- 通知の delegate の proxy と、イベントを保つ仕組みは `IosLibrary` に置く（README 3 章の `Notification/Presentation/`。9.1）。capi の Notification の受け口は、それを呼ぶだけにする

### 5.2 公開ヘッダーと `Common.h` の照合

| ヘッダー | 中身 |
|---|---|
| `Common.h` | Windows・Android と共通の宣言。iOS の `NTK_VERSION_*`（2.0.0 → `0x020000`）。`NTK_SYSTEM_CODE_*` は置かない（D-13）。宣言は Android の `Common.h`（`android/android_library_capi/src/main/cpp/include/NativeToolkitC/Common.h`）と同じで、違うのはコメントだけ（1a 入口 1 章で確かめた）。ファイルの先頭のコメントの「every function may be called from any thread」に、`ntk_notification_install` の例外を書く（コメントは照合しない） |
| `Clipboard.h`、`Dialog.h`、`Share.h` | 機能ごと（第 2 部） |
| `Notification.h` | 機能の関数（第 2 部）と、`ntk_notification_install`（1.4）。iOS だけの関数をほかに置く `Ios.h`（接頭辞 `ntk_ios_`）は、要るものが出るまで作らない（README 3.3） |

**機能のヘッダーの `Common.h` の取り込み**（1a-5。DF-7）:

```c
#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif
```

- 前の枝は framework の中（モジュールの検証が `"Common.h"` を誤りにするため）、後の枝は `dist/include` の写し（ClangSharp・bindgen・ffigen がヘッダーだけで読むとき）のため。どちらの枝でも include ガード（`NATIVETOOLKITC_COMMON_H`）が同じなので、両方が見える構成でも 2 回にならない
- この形で C・C++・Objective-C・Objective-C++ × c99・gnu11・c++11・gnu++17 のモジュールの検証が通った（1a 入口 4.2）
- module map の `header` の並びは `include/NativeToolkitC/*.h` と同じにする（2a で照らす）

**`Common.h` の OS 間の照合**（Android 第 1 部 5.2 の 4 区分。README 3.3）:

| 区分 | 対象 | iOS |
|---|---|---|
| 一致させる | 不完全型、`ntk_release_fn`、`ntk_version`、`ntk_last_system_code`、`ntk_string_*`、`ntk_bytes_*`、`ntk_string_list_*` | 同じ |
| OS ごとの展開 | `NTK_CALL` | 空（`_MSC_VER` の枝に入らない） |
| 名前と計算だけ一致 | `NTK_VERSION_*`、`NTK_VERSION` | 2.0.0、`0x020000` |
| OS ごとに許す | `NTK_SYSTEM_CODE_*` | 置かない |

`c_abi_contract_common.common_header_problems` を N 個の OS に直すのは 2a（README 3.3、5 章）。

### 5.3 入口の層（`@c @implementation`。D-10、1a-1、P1-1）

```swift
// Clipboard/ClipboardEntry.swift (shape only; the functions are fixed by part 2)
@c @implementation
public func ntk_clipboard_read_text(_ callback: ntk_clipboard_text_fn?, _ userData: UnsafeMutableRawPointer?,
                                    _ release: ntk_release_fn?, _ outRequestId: UnsafeMutablePointer<UInt64>?) -> ntk_clipboard_error {
    ClipboardReceiver.readText(callback, userData, release, outRequestId)
}
```

| 規則 | 内容 | 出典 |
|---|---|---|
| 1 関数 1 か所 | 入口のファイルには `@c @implementation` の関数だけを置き、本体は受け口の 1 回の呼び出しにする | P1-1、1a 入口 2.4 |
| 名前 | Swift の関数名は C の名前と同じ（snake_case）。`@c(ntk_x) @implementation func other()` は組めない | 1a-1、1a 入口 2.2 |
| `public` | 入口の関数は `public`（`internal` だと C のシンボルが hidden になり、公開の一覧に入れても出ない）。**capi の中で `public` にするのは入口の関数だけ** | 1a-1、1a 入口 2.2、P1-1 |
| 型 | ヘッダーと 1 つでも違えば誤り（`Int32` と `UInt32`、`UnsafePointer` と `UnsafeMutablePointer`、nullability）。注釈の無いポインタは Optional で受ける | 1a 入口 2.2、P1-3 |
| 無名の `enum` の定数 | `Int` として取り込まれるので、戻り値の型に変換する（`ntk_clipboard_error(NTK_CLIPBOARD_ERROR_NONE)`） | 1a 入口 2.2 |
| ヘッダーにあって実装が無い関数 | コンパイラーは止めない（利用者の側のリンクで初めて分かる）。2a の照合で止める（5.5） | 1a-2 |
| Swift の名前のシンボル | `public` の `@c @implementation` の関数は、Swift の名前の公開シンボルを出さない（公開の一覧を外しても、増えたのは Xcode の版の記号と C の関数だけだった） | 1a 入口 4.1 |
| 受け口 | `enum <機能>Receiver` の `static` 関数（`internal`）。検査（5.9、5.10）→ 登録（5.7）→ main に積む（5.6）→ `IosLibrary` の公開 API（P1-2）。受け口の名前は普通の Swift の名前 | P1-1、P1-2 |
| `IosLibrary` の呼び方 | `import IosLibrary`。機能ごとの manager（`IosClipboardManager.shared`、`IosNotificationManager.shared` など）の公開 API だけ。`IosClipboardManager` は `@MainActor` なので、main に積んだブロックの中でだけ触る。`IosNotificationManager`・`IosDialogManager`・`IosShareManager` は `Sendable` でどのスレッドからも呼べるが、C ABI は main に積んでから呼ぶ（完了と前面の判定の順をそろえるため） | P1-2、0e 8.1、0f 4.1・4.2、README 4.1 |
| Objective-C のクラス | `@objc` で名前を固定したクラスを capi に置かない。Swift のクラスの実行時の名前はモジュール名で区切られる（`_TtC14IosLibraryCApi9NTKBuffer`）ので、ほかの framework とぶつかるのは同じモジュール名のときだけ。どうしても要るときは `NTKCApi` の接頭辞を付ける | D-11 (2)、1a 入口 4.3 |
| Swift のトラップ | 入力から来る値に `!`、`try!`、範囲外の添字、`precondition` を使わない。`MainActor.assumeIsolated` は main キューのブロックの中だけで使う（Swift 6 は main 以外で止まる。0f 4.1） | 5.11 |

### 5.4 ビルドの設定と公開シンボル（D-9、D-11、D-16、D-18、1a-2）

1a の雛形（`results/probes/stage1a/entry/gen_projects.rb`）の設定を本番に移す。

| 設定 | 値 | 理由 |
|---|---|---|
| `MACH_O_TYPE` | dynamic | D-9 |
| `DEFINES_MODULE`、`MODULEMAP_FILE` | `YES`、`IosLibraryCApi/module.modulemap` | C の利用者の `@import` と、`@c @implementation` の underlying module（1a 入口 4.2） |
| `PUBLIC_HEADERS_FOLDER_PATH` | `$(CONTENTS_FOLDER_PATH)/Headers/NativeToolkitC` | `Headers/NativeToolkitC/*.h` |
| `EXPORTED_SYMBOLS_FILE` | `IosLibraryCApi/IosLibraryCApi.exp`（`_ntk_*`） | D-11、1a-2。外すと `_IosLibraryCApiVersionNumber` / `String` が出る（1a 入口 4.1） |
| `SWIFT_INSTALL_MODULE` | `NO` | 1a-2。配ると Xcode 26.3 の `import IosLibraryCApi` が止まる（1a 入口 3 章）。**利用者の下限を 26.3 にする条件**（D-16） |
| `SWIFT_INSTALL_OBJC_HEADER` | `NO` | 1a-2。`-Swift.h` を配らない |
| `BUILD_LIBRARY_FOR_DISTRIBUTION` | `NO` | P1-19 |
| `ENABLE_MODULE_VERIFIER` | `YES`（C・C++・Objective-C・Objective-C++） | 1a-5 |
| `SWIFT_VERSION` | 6.0（complete は既定） | D-14 |
| `IPHONEOS_DEPLOYMENT_TARGET` | 18.0 | D-15 |
| `PRODUCT_BUNDLE_IDENTIFIER` | `com.jonghyunkim.nativetoolkit.IosLibraryCApi` | D-12 |
| archive の署名 | `CODE_SIGNING_ALLOWED=NO` | D-18。シミュレーターのスライスはリンカーの ad-hoc の署名だけになる（1a 入口 4.5） |
| ビルドの Xcode | 26.6（`DEVELOPER_DIR` で選ぶ） | D-16。Swift 6.2.4 は `@c` を知らない |

配布物の照合（`check_ios_dist.py`。README 7.3）に、この設計書から次を足す。

- capi と `IosLibrary` の `CFBundleShortVersionString` が同じ（P1-19）
- `__cxa_atexit`・`atexit`・`__cxa_thread_atexit` を import していない（G-5、5.14）

### 5.5 2a の照合: ヘッダーの関数と公開シンボル（1a-2）

`check_c_abi_contract_ios.py`（2a）が、次の 4 つの集合を比べる。どれか 1 つでも食い違えば落ちる。

| 集合 | 取り方 |
|---|---|
| H: ヘッダーの関数 | `include/NativeToolkitC/*.h` の `NTK_CALL ntk_...(` の宣言の名前 |
| E: 入口の関数 | capi の Swift のソースの `@c @implementation` に続く `public func ntk_...` の名前 |
| P: capi の `public` | capi の Swift のソースの `public` の宣言（P1-1 で E と同じになるはず） |
| S: 公開シンボル | ビルドした xcframework の各スライス（`ios-arm64`、シミュレーターの `arm64` と `x86_64`）の `nm -gU` から、先頭の `_` を外したもの |

| 照らすこと | 落ちる例 |
|---|---|
| H = E | ヘッダーに足して実装を忘れた（コンパイラーは止めない。1a 入口 2.2） |
| E = P | 入口でない `public` を足した |
| H = S（スライスごと） | 公開の一覧の誤り、`internal` にした入口 |
| S の中に `_ntk_` で始まらないものが無い | 公開の一覧を外した |
| capi の C のソース（あれば）に `ntk_` で始まる定義が無い | 内部の C の関数が `_ntk_*` に入る（1a 入口 4.1） |
| module map の `header` の並び = `include/NativeToolkitC/*.h` | ヘッダーを足して module map を忘れた |
| `Headers/` に `-Swift.h` が無く、`Modules/` に `.swiftmodule` / `.swiftinterface` が無い | `SWIFT_INSTALL_MODULE` を戻した（README 7.3） |
| `Common.h` の OS 間の照合（5.2） | 宣言を 1 つ変えた |
| 機能のエラーの名前と番号 = `scripts/c_abi_error_numbers.json` の表（P1-7）。iOS と Android の両方のヘッダーで、両方向に | 片方の OS で番号を別の名前に使った、同じ名前を別の番号にした |

照合の自己テストで、規則を 1 つずつ壊すと落ちることを確かめる（知見 2.2・4 章）。H と E はソースだけで比べられるので、ビルドの前にも流せる。S はビルドの後に流す。

### 5.6 スレッドの受け渡しの実装（D-6、P1-4）

| 場面 | 実装 |
|---|---|
| main に積む | `DispatchQueue.main.async { MainActor.assumeIsolated { ... } }`（P1-4）。`dispatch_async` は失敗しない |
| main かどうか | 入れる関数だけが見る。`pthread_main_np() != 0`（1.3） |
| `IosLibrary` の完了 | 機能ごとに違う（R-27）。Notification・Dialog・Share の完了は `@MainActor @Sendable` で、main で 1 回、いつも非同期に来る（0e 8.4、README 4.1）。Clipboard は `IosClipboardManager` が `@MainActor` のクラスで、完了は普通の closure（`@Sendable` でない）。受け口は main に積んだブロックの中から呼ぶので、どれも main で返る。受け口は完了の中から、5.7 の「完了」の行を同期に行う（もう main にいるので、もう一度積まない）。`async` の形の API を使うときは、main actor の `Task` の中で待ち、結果を同じ行に渡す |
| C のコールバックを main へ運ぶ | 関数ポインタ、`user_data`、`release` を `@unchecked Sendable` の箱（または `Registration`）に入れて運ぶ（P1-17）。`user_data` のスレッドの安全は利用者が持つ（C ABI の契約） |
| 待たない | `DispatchQueue.main.sync`、`DispatchSemaphore.wait`、`Mutex` を持ったままの main への受け渡しを書かない。6 章の「main を止めた状態」のテストで、すべての関数が期限内に戻ることを確かめる |

### 5.7 寿命と `release`（AC-6、AC-17、AC-21、D-6）

Android 第 1 部 5.7 の形を引き継ぐ。iOS では「積めない」経路が無いので小さくなる（DF-10。知見 1 章の推測のとおり）。

**ハンドルと登録の実体**:

| 種類 | 実体 |
|---|---|
| 出力のハンドル（`ntk_string`、`ntk_bytes`、`ntk_string_list` など） | `Unmanaged.passRetained` した Swift のオブジェクト。**ハンドルの型ごとにクラスを分ける**（`NTKString`、`NTKBytes`、`NTKStringList`。1a の雛形は `ntk_string` と `ntk_bytes` が同じ `NTKBuffer` だったので、型の確かめが効かなかった。R-30）。`_free` が 1 回 `release` する。`NULL` のハンドルには `NULL` / 0 を返す。**違う型のハンドルを渡すことと、解放した後のハンドルは未定義**（実装は `as?` で確かめて `NULL` / 0 を返すが、約束しない） |
| イベントの登録のハンドル | `Registration`（下）を `passRetained` したもの。利用者が 1 つの参照を持ち、解除の関数がそれを手放す |
| 完了つきの操作 | `Registration`。利用者にはハンドルを渡さない。取り消せる操作は ID の表に入れる |
| `Registration` | 関数ポインタ、`user_data`、`release`、ID、種類、**状態（`Atomic<UInt8>`: `ACTIVE`、`CANCEL_REQUESTED`、`RELEASED`）**、完了つきの操作なら **main だけが読み書きする「完了済み」の印** |
| ID の表 | ID → `Registration`。`Mutex` で守り、どのスレッドからも引く。プロセスで 1 つで、解放しない |
| 帳簿 | イベントの種類ごとの、有効な登録の並び（登録した順）と、**その種類の `ACTIVE` な C の登録が 0 の間に届いたイベントの保ち**（R-7。5.12.7）。**main だけが触る**（`@MainActor` の状態） |

**`release` を呼ぶのは、1 つの関数 `tryRelease(登録, 期待する状態)` だけ**（AC-6、Android レビュー v2 の S-C2、v3 の T-X10）。この関数は、ID の表の `Mutex` の中で状態を `RELEASED` に CAS し、成功したときだけ ID の表から外し、**`Mutex` の外で** `release(user_data)` を呼ぶ。下の表の「`tryRelease`」はすべてこの関数を呼ぶ。

**受け付け**（どのスレッドからでも）:

1. ハンドルの出力引数に `NULL` を書く（Windows の設計書 7.3。R-8）
2. 入口の検査（5.10 の並び）。失敗したら、`release != NULL` なら呼び出しスレッドで `release(user_data)` を直接呼び（`Registration` はまだ無いので `tryRelease` を通らない）、エラーを返す。完了は呼ばない。値の出力引数は書かない
3. **入力を深く写す**: 文字列は Swift の `String`、バイト列は `Data`、構造体とその中のポインタの先は Swift の値、ビルダーは今の中身の写しにする。生のポインタも利用者のハンドルも main へ運ばない（R-5）
4. `Registration` を `ACTIVE` で作り、ID を付ける（`Atomic` を 1 から増やす）。取り消せる操作（P1-24）なら、`IosLibrary` の要求の箱（S-15）をここで作って `Registration` に持たせ、ID の表に入れる。箱は「挿入と開始」で `IosLibrary` の表示の口・読み込みの口に渡す（R4-1）
5. 出力引数（`*out_request_id`、`*out_listener`）を書く（P1-5。実装の性質で、契約ではない）
6. 「挿入と開始」を main に積む（`DispatchQueue.main.async`。失敗しない）。**ここで受け付けが成り立つ**
7. `NONE` を返す。**受け付けの後、呼び出しスレッドは登録に触れない**（ID の表と、利用者が持つハンドルを通す場合を除く）

**main の上の出来事**（すべて main キューのブロック。積んだ順に動く）:

| 出来事 \ 登録の状態 | `ACTIVE` | `CANCEL_REQUESTED` | `RELEASED` / 表に無い |
|---|---|---|---|
| 挿入と開始（受け付けで積んだもの） | イベントの登録なら帳簿の末尾に入れ、保っていたイベント（5.12.7）をこのブロックの中で配る。完了つきの操作なら処理を始める（前面の判定、`IosLibrary` の呼び出し） | 何もしない（後から来る「外す」に任せる） | 何もしない |
| イベントの配送 | 呼ぶ直前に状態を確かめ、`ACTIVE` なら利用者の関数を呼ぶ | 呼ばない | 何もしない |
| 完了（`IosLibrary` の完了が main で来た、または前面の判定などで決まった） | 印が無ければ、完了を呼んで印を立てる → `tryRelease(ACTIVE)`。失敗したら（完了を呼ぶ間に取り消された）何もしない（後から来る「外す」が `tryRelease` する） | 印が無ければ、完了を `CANCELED` で呼んで印を立てる（得た結果は捨てる）→ `tryRelease(CANCEL_REQUESTED)` | 何もしない |
| 外す（解除・取り消しで積んだもの） | （起きない。解除は先に状態を `CANCEL_REQUESTED` にしてから積む） | (1) イベントの登録なら帳簿から外す。(2) 完了つきの操作で印が無ければ、完了を `CANCELED` で呼んで印を立てる（`IosLibrary` の要求の取り消しは、取り消しの関数の中で既に頼んである。下の「解除と取り消し」）。(3) **(1)・(2) の後に、種類と印に関わらず必ず `tryRelease(CANCEL_REQUESTED)`**（R-3） | 何もしない |

**解除と取り消し**（どのスレッドからでも）:

- イベントの登録の解除（ハンドルを取る）: ハンドルの `Registration` の状態を `ACTIVE` → `CANCEL_REQUESTED` に CAS し、成功したら「外す」を積み、利用者の参照を手放して戻る（待たない）。積んだブロックは自分の参照を持つので、手放しても登録は消えない。**2 回目の解除は未定義**（AC-17）。1 回目で利用者の参照を手放しているので、2 回目は解放した後のオブジェクトに触れうる（R-29）
- 完了つきの操作の取り消し（ID を取る）: ID の表の `Mutex` の中で ID から登録を引き、`ACTIVE` → `CANCEL_REQUESTED` を CAS し、成功したら、**`Registration` が持つ要求の箱の取り消し（S-15。どのスレッドからでも呼べ、待たない）をその場で呼んで `CANCELED` で閉じさせ**、「外す」を積んで戻る。箱は受け付けの時点で作ってあるので、挿入と開始より先の取り消しでも必ず閉じる箱がある（R4-1）。箱が先に閉じるので、挿入と開始や待ちの再開（5.13.2）が後から動いても表示しない。登録が無い（完了の後、知らない ID）か CAS に失敗したら何もせずに `NONE`（Android 第 1 部 1.3.1）
- main から呼んだ場合も同じ。状態が `CANCEL_REQUESTED` になった時点で、以後の配送は呼ばれない（配送は呼ぶ直前に確かめる）。これが 1.3 の「main から呼んだ解除は、その場で以後の配送を止める」
- main 以外から呼んだ場合、CAS より前に main で始まっていた配送は呼ばれる（1.3 の「`release` まで配送が来うる」）
- **「外す」を積めない場合は無い**（DF-10）。Android の「積めなかった印」（Android 第 1 部 5.7）は持たない

**この表で閉じる順序**（6 章のテストにする。Android レビュー v3 で Claude が追った順と同じ）:

| 順序 | 結果 |
|---|---|
| main 以外で登録し、関数が戻る前に main が挿入と完了を処理する | 完了 1 回、`release` 1 回（出力は実装では積む前に書いてあるが、契約では頼らない） |
| 挿入より先に解除・取り消しが積まれる | 挿入は `CANCEL_REQUESTED` を見て何もしない。「外す」が完了（`CANCELED`）と `tryRelease` を行う |
| 完了のコールバックの中で、同じ要求を取り消す | 取り消しは `CANCEL_REQUESTED` にして積む。完了の後の `tryRelease(ACTIVE)` は失敗し、「外す」が印を見て完了を呼ばず、`tryRelease(CANCEL_REQUESTED)` だけを行う（R-3）。完了 1 回、`release` 1 回 |
| イベントの登録を解除する（どのスレッドからでも） | 「外す」が帳簿から外し、`tryRelease(CANCEL_REQUESTED)`。`release` 1 回 |
| C の登録が 0 件に戻った後に、イベントが来て、また登録される | 受け口が保ち、次の登録の挿入のブロックで配る（R-7。5.12.7） |
| main 以外の取り消しと、main の完了が重なる | どちらの CAS が先でも、完了 1 回、`release` 1 回（上の 2 行） |
| イベントのコールバックの中で、自分の登録を解除する | その場で以後の配送が止まる。`release` は後で 1 回 |
| 同じ回（main の 1 つのブロックの中）で登録して解除する | 挿入が先、外すが後に動く。`release` 1 回 |
| 完了の後に取り消す、知らない ID で取り消す | 何もしない |
| 入口で拒む | 完了 0 回、`release` は呼び出しスレッドで戻る前に 1 回 |
| プロセスが終わる | 完了も `release` も呼ばない |

**ライブラリの側で終わるもの**（AC-21）:

- イベントの登録は、ライブラリの側で解除・差し替えをしない。今のブリッジの受け手の登録（Notification の 2 つの setter など。1 つを差し替える）は、足す・外す形にする（AP-6）。Unity から見た差し替えは 2c の包みが保つ（Android 第 1 部 C-6）
- 完了つきの操作がライブラリの側で終わる（5.13.1 の終わり方の一覧）ときは、「完了」の行の処理を、決めた値（`CANCELED_BY_SYSTEM`、表示の失敗の値など。第 2 部）で行う。Swift の API の設計書は、終わるすべての場面で完了を出す（9.1 の S-5）。見つける仕組みは P1-14 の見張り

### 5.8 コールバックの引数（AC-18）

- コールバックに渡すのは、**値（整数、真偽値、列挙、要求の ID、`system_code`）か、所有権ごと渡すハンドル（利用者が対応する `_free` を呼ぶ）だけ**。コールバックから戻った後も、ハンドルは利用者が解放するまで有効（Android 第 1 部 5.9。Windows の「戻るまで有効」とは逆。知見 2.3）
- 借りるポインタは渡さない（Dart の `NativeCallable.listener` は戻った後に引数を読む）
- コールバックの戻り値はすべて `void`
- 引数の並び（`user_data` の次に要求の ID を置くか、など）は第 2 部で決める。1a の雛形は `(user_data, request_id, error, system_code, text)` だった
- 利用者がハンドルを解放し忘れるとメモリが漏れる。マニュアルの言語ごとの例に解放を書く

### 5.9 文字列とバイト列（E-7、E-15、E-16、AC-19、README 8.6）

| 向き | 規則 | 実装 |
|---|---|---|
| 入力 | NUL で終わる UTF-8。**RFC 3629 の厳密な検査**（サロゲートを UTF-8 にした列、過長の表現、U+10FFFF を超える値を拒む）。不正なら `INVALID_PARAMETER` | `String(validatingCString:)`。`C3 28`、`ED A0 80`、`C0 AF`、`FF` を拒むことを確かめた（1a 入口 2.1）。U+10FFFF を超える値（`F4 90 80 80`）は確かめていないので、2b のテストに入れる |
| 入力の `NULL` | 省略できる値は `NULL` が「無い」、`""` が「空で在る」。意味の上で必須な値の `NULL` は `INVALID_PARAMETER`。ほかは `NULL` を `""` とする | E-15 |
| 入力のバイト列 | `const uint8_t*` と `size_t`。長さが 0 でないのに `NULL` は `INVALID_PARAMETER`。`Int(exactly:)` に入らない長さも `INVALID_PARAMETER` | Android 第 1 部 5.6 の「長さ」に当たる |
| 出力 | NUL で終わる UTF-8。対になっていないサロゲートと U+0000 を U+FFFD に置き換え、成功を返す。途中に NUL は入らない | **Swift の `String` の `unicodeScalars` から UTF-8 を作り、U+0000 を U+FFFD にする**（1a の `CApiString.outputUTF8`）。Swift の `String` は、橋渡しした `NSString` の対になっていないサロゲートを U+FFFD に直す（1a 入口 5.3） |
| 出力で使わないもの | `-[NSString UTF8String]`、`lengthOfBytesUsingEncoding:`、`dataUsingEncoding:` | 対になっていないサロゲートがあると `NULL` / 0 / `nil` になる（1a 入口 5.3） |
| 出力の所有権 | 文字列は `ntk_string`（`ntk_string_list`）のハンドルで返し、利用者が `ntk_string_free` で解放する。`ntk_string_data` のポインタは解放するまで有効 | Windows の設計書 7.4、1.3.1 |
| 出力のバイト列 | `ntk_bytes_data` は長さ 0 でも `NULL` でない | 1a の `NTKBuffer` は長さ + 1 を確保する |

- 置き換えは損失を伴うので、ヘッダーとマニュアルに書く（AC-19）
- ほかのアプリが置いたクリップボードからは、BOM 付きの UTF-16 のときに対になっていないサロゲートを持つ文字列が届きうる。BOM の無い UTF-16 や不正な UTF-8 のデータは、今の `IosLibrary` が文字列として扱わず空になる（1a 入口 5.3）。文字列として読むかは第 2 部で決める（8 章）

### 5.10 エラー（AP-12、AP-19、D-13）

共通の 0〜5（AP-12）の iOS での意味:

| 値 | 名前の末尾 | iOS での意味 |
|---|---|---|
| 0 | `NONE` | 成功（非同期の関数では受け付けたこと） |
| 1 | `INVALID_PARAMETER` | `NULL`、不正な UTF-8、長さ、`struct_size` が小さいか 4096 を超える、`reserved` が 0 でない、範囲外の値、予約したキー（P1-9。userInfo を受け取る入口の戻り値で返す。R-32）、アクションシートにテキスト入力（5.11） |
| 2 | `NOT_INITIALIZED` | **通知のイベントの受け手の登録と、起動のきっかけの通知の取得だけ**。C の口でも Swift の口でも、proxy がこのプロセスで一度も入っていない（P1-6）。ほかの機能は返さない |
| 3 | `NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値がある（Windows の設計書 7.8） |
| 4 | `UNKNOWN` | 対応表に無い `IosLibrary` の失敗。詳細は `os_log`（P1-18） |
| 5 | `OUT_OF_MEMORY` | 番号だけ残し、返さない（DF-16） |

iOS で新しく足す値: **`NTK_NOTIFICATION_ERROR_WRONG_THREAD = 16`**（入れる関数だけが返す。P1-7）。Notification の 6〜15 は、Android の同じ名前の値に同じ番号を使い、iOS で使わない値（`EXACT_ALARM_NOT_ALLOWED` など）は欠番にする（第 2 部）。

**`IosLibrary` のエラーを写す規則**（対応表そのものは第 2 部）:

| 規則 | 内容 | 理由・出典 |
|---|---|---|
| 1 つの case に 1 つの値 | `IosLibrary` の各エラーの case（1b で直した後の `NotificationError`、`ShareError`、`ClipboardError`、新しい Dialog のエラー）を、ちょうど 1 つの C の値に写す。表に無いものだけが `UNKNOWN` | 1b で任意の `Error` を持つ case を無くす（README 4 章）ので、写しを全部書ける |
| 文字列を渡さない | `localizedDescription` やエラーのメッセージは C ABI に出さない。詳細はログ | Windows・Android と同じ。今のブリッジは文字列だけを返していた（README 1.2） |
| システムコードは 0 | `ntk_last_system_code()` は常に 0、完了の `system_code` も 0。`NSError` の code はログに出す | D-13、1a-3 |
| 入口と完了の分け方 | `IosLibrary` を呼ばずに入口で決まる検査は、非同期の関数でも戻り値。受け付けた後に分かる失敗は完了の引数。同じ値が両方から来うる | AP-19 |
| 検査の並び | 入口では、引数の検査（`NULL`、UTF-8、長さ、`struct_size`、範囲、予約したキー）を先に、`NOT_INITIALIZED` の確かめを後に行う | Android 第 2 部 11 章 |
| 番号 | 6 以降を機能ごとに置く。欠番は詰めない。出した番号は変えない。同じ意味の値には Android と同じ名前を付ける（`CANCELED`、`CANCELED_BY_SYSTEM`、`NOT_FOREGROUND`、`PERMISSION_DENIED` など）。**機能ごとに OS をまたいだ 1 つの番号の表（`scripts/c_abi_error_numbers.json`）を持ち、同じ名前は同じ番号、ある OS が使った番号を別の OS が別の名前に使わない。無い名前の番号は欠番。2a が両方の OS のヘッダーと照らす。Windows は対象外**（P1-7）。同じ OS の中でも、同じ名前の番号は機能ごとに違いうる（Android の `NOT_FOREGROUND` は Share で 6、Dialog で 8） | AP-12、E-10、Android 第 2 部 RP-5 |
| 前面 | 前面が要る操作の「前面でない」は、呼び出しスレッドでは判定せず、main で判定して必ず完了で返す | AC-15。前面は main の上で変わる |

### 5.11 例外（D-10、P1-16）

| 種類 | 扱い | 出典 |
|---|---|---|
| 利用者のコールバックの例外（C++、Objective-C、Rust の panic、C#） | **外へ出してはならない。出した場合の振る舞いは定めない**。ライブラリは捕まえない（Swift は捕まえられない）。多くは `SIGABRT` で終わる | P1-16、1a 入口 5.1 |
| UIKit・Foundation の `NSException` | **捕まえられない**。main に積んだブロックの中で起きると、`NSSetUncaughtExceptionHandler` を通って `SIGABRT` で終わり、完了も `release` も来ない。iOS 18 では、こちらのブロックが戻った後の UIKit の表示の処理で起きることもある（スタックにライブラリのフレームが無い） | D-10、1a 入口 5.1 |
| Swift のトラップ | 入力から起こさない（5.3） | 0f 4.1 |

**起こさない検査**（UIKit・Foundation の例外の元を入口か表示の前で止める。どれも「起きたら落ちる」を前提にした予防）:

| 例外の元 | 検査 | 確かめ |
|---|---|---|
| アクションシートに `addTextField`（`NSInternalInconsistencyException`） | 入口で `INVALID_PARAMETER`（第 2 部の Dialog の形で、そもそも書けない形にできればそうする） | 1a 入口 5.1 の種類 1（iPhone と iPad、26.2 と 18.3） |
| 基点の無い popover（iPad。`NSGenericException`） | アクションシートと Share は、**表示の前に必ず基点を設定する**（`sourceView` と `sourceRect`。P1-13） | 1a 入口 5.1 の種類 2（iPad の 18.3 だけで落ち、26.2 では落ちない）。**テストは iOS 18 の iPad でも流す**（P1-20） |
| 表示中・閉じかけの ViewController の上への表示 | 5.13 の表示の前の検査 | 0e（README 1.4） |
| `JSONSerialization` に JSON にできない値 | 使うなら `isValidJSONObject` を先に見る（userInfo の受け渡しの形は第 2 部） | README 1.4 |

### 5.12 通知の delegate（D-4、D-6、D-7、1a-6〜1a-13）

転送の delegate（proxy）は `IosLibrary` に置く（9.1 の S-2）。C ABI の `ntk_notification_install` は、その口を呼ぶだけにする。ここでは、C ABI が頼る振る舞いを決める。

#### 5.12.1 持ち方

| 項目 | 決め方 | 出典 |
|---|---|---|
| proxy を誰が持つか | ライブラリが強く持つ（プロセスで 1 つ、解放しない） | D-7、1a delegate 2.3（`delegate` は weak で、誰も持たないと同じターンで `nil` になった） |
| 前の delegate | **weak** で持つ。消えていたら「前の delegate が無い」と同じ | 1a delegate 5 章の D-7（転送）の行 |
| `responds(to:)` | proxy は 3 つのメソッドを常に実装し、前の delegate の `responds(to:)` は呼ぶたびに見る | 1a delegate 5 章 |
| 差し替えの見張り | `UNUserNotificationCenter.delegate` を KVO で見張り、差し替えられたら差し替えた型をログに出す。**自動では入れ直さない**。`delegate` を KVO で見張れることは Apple の文書に無く、シミュレーター（18.3・26.2）で確かめただけ。**ログにしか使わないので、効かなくなっても働きは失わない**（R-22） | 1a-10、1a delegate 2.3 |
| スレッド | 3 つのメソッドは、シミュレーターではすべて main で呼ばれた。ただし Apple の文書に書かれていないので、proxy は main を前提にしない: proxy のクラスとメソッドは nonisolated にし、ライブラリの通知のイベントはいつも main に積み（5.12.3）、状態（前の delegate、入れた印、循環の鍵の集合）は `Mutex`（`Synchronization`）で守る。**`Mutex` を持ったまま、前の delegate、system の completion、受け手のどれも呼ばない**（鍵の中で値を読み出し、鍵の外で呼ぶ。S-8。R-41） | 1a delegate 2.1・2.2・5 章 |

#### 5.12.2 通知の見分け方

| 順 | 条件 | 種類 |
|---|---|---|
| 1 | `trigger` が `UNPushNotificationTrigger` | **ライブラリの通知でない**（印があっても。1a-12） |
| 2 | userInfo に印（キー `com.jonghyunkim.nativetoolkit`。P1-9）がある | **ライブラリの通知** |
| 3 | それ以外（ホストの通知、印の無い 1.x の通知） | ライブラリの通知でない |

1.x の通知とホストのローカルの通知は、中身でも trigger でも見分けられない（1a delegate 3.5）。

#### 5.12.3 転送の規則

| メソッド | ライブラリの通知 | ライブラリの通知でなく、前の delegate がそのメソッドを実装している | ライブラリの通知でなく、前の delegate が無いか実装していない（誰も受けない） |
|---|---|---|---|
| `willPresent` | 前の delegate に見せない（1a-7）。その場で、ライブラリの表示の選択肢（今の `IosNotificationManager.foregroundPresentationOptions`。既定は `[.banner, .list, .sound, .badge]`）で 1 回完了する | 前の delegate に渡す。渡す completion は 1 回だけ通す包み（5.12.4）。前の delegate の選択肢をそのまま system に渡す | ライブラリが扱う（1a-6）。ライブラリの表示の選択肢で 1 回完了する |
| `didReceive` | 前の delegate に見せない（1a-7）。イベントを main に積み、**そのブロックの中で、受け手に渡すか保つか（5.12.7）した後に** system の completion を 1 回呼ぶ（1a-12） | 前の delegate に渡す（包みつき）。ライブラリのイベントは出さない | ライブラリが扱う（1a-6）。ライブラリの通知と同じく、イベントを積み、渡すか保つかした後に completion を呼ぶ |
| `openSettingsFor` | ライブラリが扱う（P1-10 のイベント） | 前の delegate に渡す（completion は無い）。`notification` が `nil` のときも、ライブラリの通知でないのでこの列（R-13） | ライブラリが扱う（P1-10 のイベント。`nil` なら通知の無いイベント） |

- `willPresent` はイベントを出さない（今の `IosLibrary` と同じ）
- 最初の転送の呼び出しの中で同期に proxy へ戻ってきた呼び出し（循環）は、5.12.5 のとおり「誰も受けない」の列で扱う
- 前の delegate が completion を呼ばないときの期限（watchdog）は入れない（1a-8）。呼ばずに捨てたときは system が終わりとみなし、持ち続けたときはその通知の `add` の完了も止まる（1a delegate 2.1）。どちらもライブラリが無いときと同じ結果である
- 誰も受けない、印の無い通知をライブラリが扱うので、ホストの delegate が無いアプリでは、ホストの通知も前面で表示され、タップがライブラリの受け手に届く。1.x はすべての通知をそう扱っていた（1a delegate 7 章の 1）。移行ガイドに書く
- 逆に、ホストの delegate が `didReceive` を実装しているアプリでは、**印の無い 1.x の通知のタップはホストに渡り、ライブラリの受け手に届かない**。見分けられないため（5.12.2）。更新の後に 1.x の通知をどう扱うかは Swift の API の設計書で決める（README 8.6）

#### 5.12.4 1 回だけ通す包み（`CompletionOnce`。P1-17）

```swift
/// Passes the system's completion handler through at most once; later calls are dropped and logged.
/// @unchecked Sendable: the SDK's completion type is not @Sendable, and a previous delegate may call it
/// from any thread (stage 1a saw a global queue). The only mutable state is guarded by the Mutex,
/// and the wrapped closure is taken out under the lock and called once outside it.
/// The class and `call` are nonisolated; the closure handed to the previous delegate is a
/// nonisolated @Sendable closure, so calling it off the main thread trips no actor check.
final class CompletionOnce<Value>: @unchecked Sendable { ... }
```

| 規則 | 内容 | 出典 |
|---|---|---|
| 1 回だけ | 鍵の中で closure を取り出して `nil` にし、鍵の外で呼ぶ。2 回目からは捨ててログに出す（1a delegate 3.1 の twice） | 1a-8 |
| どのスレッドから呼ばれてもよい | 前の delegate は completion をほかのスレッドから呼べる（asyncBg）。system はそれを受けた | 1a delegate 3.1・5 章 |
| **隔離を継がない**（R-4） | 鍵が保つのは「取り出しが 1 回」だけで、どのスレッドから呼べるかは別の前提である。前の delegate に渡す closure と `CompletionOnce` の入口は、**明示的に nonisolated で `@Sendable`** にする。main actor の文脈で closure を書くと main actor を継ぎ、ホストが背景のスレッドから呼んだときに Swift 6 の実行時の隔離の検査で止まる（0f 4.1）。`@unchecked Sendable` はこの検査を外さない。6 章で、背景のキューから呼ぶテストを持つ | 0f 4.1、R-4 |
| 解放されたとき | 一度も呼ばれずに解放されたら（前の delegate が closure を捨てた）、何もしない。system の completion は呼ばない（1a-8。捨てたときは system が終わりとみなす） | 1a delegate 2.1 の never |
| `@unchecked Sendable` の理由 | 上のコメントのとおり。`IosLibrary` の `@unchecked Sendable` の一覧（P1-17）に入れ、TSan のテストを持つ | P1-17、1a delegate 5 章 |

#### 5.12.5 循環の防止（1a-8、P1-21）

ホストが proxy の後に入れ直し、自分の前の delegate（proxy）に転送すると、入れる関数をもう一度呼んだときに proxy → ホスト → proxy の循環ができる。防がないと無限の再帰で落ちる（1a delegate 3.3。`EXC_BAD_ACCESS`）。ライブラリの通知はもともとホストに渡さない（1a-7）ので、循環はホストがホストの通知をライブラリへ転送し直したときだけ起きる。

| 項目 | 決め方（P1-21 の A） |
|---|---|
| 契約 | **ホストは、ライブラリから受けた通知をライブラリへ転送し直さない**。マニュアルには、ホストのすることで「前の delegate へ非同期に転送する delegate を入れた後で、`ntk_notification_install` の入れ直しを呼ばない」と書く（0.1。R4-9） |
| 止めるもの | 3 つのメソッドそれぞれで、**最初の転送の呼び出しの中で同期に proxy へ戻ってきた呼び出し**だけ |
| 鍵 | 「メソッド、通知の `request.identifier`、通知の `date`、`didReceive` なら `actionIdentifier`」の値。`openSettingsFor` の `notification == nil` は決まった鍵 1 つ。proxy の `Mutex` の集合に、転送の呼び出しの直前に入れ、その呼び出しから戻った直後に外す（`defer`）。集合は値だけを持ち、包みを持たない |
| 見つけたとき | 転送せず、「誰も受けない」として扱う（1a-6 にそろえる）: `willPresent` はライブラリの表示の選択肢でその呼び出しの包みを 1 回呼ぶ。`didReceive` はライブラリのイベントを積み、渡すか保つかした後にその呼び出しの包みを 1 回呼ぶ。`openSettingsFor` は P1-10 のイベント。ログに出す |
| 契約の外 | それ以外の転送し直し（completion を呼んだ後、別のスレッドやキュー、`asyncAfter`、`Task` で戻す形）。振る舞いは定めない |

#### 5.12.6 入れ直しと、起動の後の呼び出し（1a-10、1a-11）

| 場面 | 振る舞い | 結果 |
|---|---|---|
| 今の delegate が proxy | 何もしない | `NONE` |
| 初めて | 今の delegate を前の delegate にし、proxy を入れる | `NONE` |
| 入れた後に差し替えられていた | 今の delegate（差し替えた側）を新しい前の delegate にし、proxy を入れ直す。ログに出す | `NONE`。差し替えた側が元のホストに転送しないなら、元のホストは鎖から外れたまま（1a delegate 3.3） |
| 差し替えた側が proxy に転送する形 | 入れ直すと循環になる。**差し替えた側が同期に転送するときだけ** 5.12.5 で止まる。非同期に転送するなら、入れ直しは契約の外（0.1。R4-5） | `NONE` |
| 起動の後 | 上のどれかと同じに入れ、「起動の後かもしれない」のログを出す。関数の中で起動の後かを正しく知る方法は無い（scene のアプリは起動の処理の中でも `applicationState` が background）。**ログを出す判定は `UIApplication.shared.applicationState == .active` だけにする**（active なら必ず起動の後。background・inactive では出さない。R-36） | `NONE`。コールドスタートのタップは失う |

#### 5.12.7 コールドスタートと、受け手が登録されるまでの保ち方

事実（1a delegate 2.4）:

- コールドスタートの応答は、`didFinishLaunching`（scene のアプリでは `scene(_:willConnectTo:options:)`）から戻った直後、main キューの次の処理より前に 1 回だけ delegate に渡される。**system は delegate が置かれるまで応答を保たない**
- `launchOptions` と `connectionOptions.notificationResponse` はホストの delegate にしか渡らないので、ライブラリが後から自分で取ることはできない。ライブラリが応答を得られるのは delegate からだけ

決めること（C ABI の側）:

| 項目 | 決め方 | 出典 |
|---|---|---|
| 保つもの | 通知のイベント（タップ、アクション、テキスト入力、P1-10 の設定の画面）。`willPresent` は保たない | README 4 章、Android 第 2 部 AP-21 |
| 保つ場所 | 2 か所（AP-21 と同じ形。R-7）。(1) 最初の C の登録より前: `IosLibrary` のイベントの口（受け手が 0 の間）。(2) その後: **C ABI の受け口は、その種類の最初の C の登録のときに `IosLibrary` の受け手を 1 つ足し、以後は外さない。その種類の `ACTIVE` な C の登録が 0 の間に届いたイベントは、受け口が帳簿に保つ**。どちらも、次の C の登録の「挿入と開始」のブロックの中で配る（5.7）。その後に積まれた新しいイベントより先に届く。受け口が保つ件数は Swift の API の口と同じにする | Android 第 2 部 AP-21、Android 第 1 部 5.7 |
| system の completion | 保った時点（main のブロックの中）で呼ぶ。受け手を待たない（待つと背景のアクションの間アプリが止められない。逆に、待たずに先に呼ぶと利用者のコールバックの前にアプリが止まりうるので、積んだブロックの中まで遅らせる） | 1a-12 |
| 起動のきっかけの通知 | P1-22 の規則（プロセスで最初の `didReceive` が最初の `UIApplication.didBecomeActiveNotification` より前に来て、ライブラリが扱ったものなら起動のきっかけ。ホストへ転送したなら無し。循環は起動のきっかけにしない（R4-3）。初めて入れたときに既に active なら無し）で見分け、別に持ち、取得の関数で返す（D-7 の追加。形は第 2 部）。保ったイベントとしても配る | D-5、D-7、README 6 章の「追加」、P1-22 |
| proxy を入れなかった（C の口でも Swift の口でも） | 応答はライブラリに来ないので、何も保たない。受け手の登録と取得は `NOT_INITIALIZED`（P1-6） | P1-6 |
| プロセスが終わる | 保ったものは失う（ディスクに書かない） | 1.3.3 |

第 2 部と Swift の API の設計書が決めること（8 章・9.1）: 保つ件数・期限・順序・重複（README 8.6 では Swift の API の設計書。Android は 32 件、期限なし、受けた順、重複を除かない）、同じ回に複数の受け手が登録されたときに誰に渡すか（Android は最初の登録）、起動のきっかけの通知の取得の形（同期の取得の関数で所有権ごと渡すハンドルを返すか、イベントに「起動のきっかけ」の印を付けるか）。起動のきっかけは取得の関数とイベントの両方で届く（上の表）ので、利用者が二重に処理しない書き方をマニュアルに書く。

#### 5.12.8 Unity の通知パッケージとの共存（D-7）

Unity の通知パッケージ（`com.unity.mobile.notifications`）も `kUnityWillFinishLaunchingWithOptions` で delegate を上書きする（README D-7、8.5）。どちらが後に入るかで、次のようになる。

| 順 | 結果 |
|---|---|
| パッケージ → ライブラリ | ライブラリの proxy が前に立ち、パッケージの delegate を前の delegate にする。パッケージの通知（印が無い）はパッケージに転送される。成り立つ |
| ライブラリ → パッケージ（パッケージが転送しない） | ライブラリの通知も届かない（1a delegate 3.3）。KVO のログで分かる。`ntk_notification_install` をもう一度呼べば戻る（1a-10）が、コールドスタートのタップは失う |

どの順になるか、ライブラリが必ず後に入る形（`didFinishLaunching` の受け手）でコールドスタートのタップを受けられるかは、`unity-native-plugin` の agent が確かめる（10 章の U-3・U-4）。結果で、ホストから応答を渡してもらう関数を足すか（1a-13）を決め直す。

### 5.13 前面の扱い（README 8.6、P1-11〜P1-15、P1-24）

**前面の定義**（P1-11）: `UIApplication.shared.connectedScenes` の `UIWindowScene` のうち、`activationState` が `foregroundActive` か `foregroundInactive` で、**アプリの key window（`isKeyWindow` が真の window）を持つもの**。その window の `rootViewController` から、`isBeingDismissed` でない `presentedViewController` をたどった最上位を「前面の ViewController」とする。見つからなければ前面でない。scene の無い構成でも UIKit が暗黙に `UIWindowScene` を作るので同じ探し方で動く（0a 3.8）。Unity 6000.4.2f1 は scene を使う（`UnityScene`。0a 3.8）。前提 2 つ（inactive の間も表示できる、key window がアプリで 1 つ）は 1b で確かめる（G-6）。今の public の `getRootViewController()` は残し、この定義の口は別の名前にする。

**判定する所**（P1-11 の C）: `IosLibrary` の表示の口が、`presenter` の値に応じて 5.13.2 の手順で行う。C ABI の受け口は「新しい定義の前面」を選んで渡すだけ。既定（`presenter` を渡さないとき）は今の探し方のままで、待ちも入れない（README 1b の行）。

| 操作 | 前面が要るか | 前面でないとき |
|---|---|---|
| Dialog（すべて） | 要る | `NOT_FOREGROUND` で完了する |
| Share | 要る | `NOT_FOREGROUND` で完了する |
| 通知の権限の要求 | 権限の状態が未決（`notDetermined`）のときだけ要る（システムのダイアログが出るため）。決まっていれば、前面に関係なく今の状態で完了する | 未決で前面でなければ `NOT_FOREGROUND` で完了する |
| 通知の設定の画面を開く | 要る（`UIApplication.open` は後ろからは開けない見込み。G-7） | `NOT_FOREGROUND` で完了する。今のブリッジは確かめていない（AC-23。第 2 部の対応表に書く） |
| 通知の表示・予約・取り消し・一覧・category・バッジ | 要らない | - |
| Clipboard | C ABI では判定しない | 後ろでの OS の振る舞いは `IosLibrary` の結果のまま返す（1b で確かめる） |

`IosLibrary` に足すもの（README 4.1 と 1b の行に書く）: `presenter` の引数、新しい定義の前面を返す口、要求の箱と解放の見張り（5.13.1）、表示の手順の待ち（5.13.2）、P1-24 の取り消しの口（S-15）。既定の動作は変えない。

#### 5.13.1 要求の箱と、表示の完了（P1-14）

**要求の箱**: 完了つきの要求ごとに 1 つ持つ、1 回だけ閉じられる箱。Dialog・Share・権限の要求・設定の画面・Clipboard の読み込みのどれも同じ箱を使う（Clipboard の読み込みは ViewController を持たない。R3-7）。

| 規則 | 内容 |
|---|---|
| 状態 | 開いている / 閉じた（結果つき）。`Mutex` で守り、**どのスレッドからでも閉じられる**（UIKit の handler がどのスレッドで呼ばれるかに頼らない。R3-9） |
| 閉じる | 最初に閉じたものだけが効き、結果を箱に書く。2 回目からは捨てる。閉じた後に、結果を main に積んで呼び出し側の完了へ渡す（後ろの非同期の配送は閉じた値を運ぶだけ） |
| 閉じるもの | handler（ボタン、Share の完了の handler）、取り消し（S-15）、表示の手順の失敗（5.13.2）、解放の見張り、Clipboard の読み込みの結果 |
| 作る時期 | 取り消せる要求（P1-24）の箱は、C の受け口が受け付けの時点で作って渡す（5.7。R4-1）。渡されなければ表示の口・読み込みの口が作る。完了の受け先は口が付け、付けた時点で箱がもう閉じていれば、閉じた結果を main に積んで渡す |
| 取り消し | 箱を `CANCELED` で閉じてから、Dialog を閉じる（上にほかの画面が重なっていれば閉じない。P1-24）、Clipboard の読み込みを止める。**Dialog がまだ表示の途中（`isBeingPresented`、または `present` の完了がまだ）なら、閉じるのは `present` の完了の中で行う**（途中の `dismiss` は UIKit が無視することがある見込み。G-4。R4-2）。遅れて来た結果と handler は閉じた箱に当たって捨てられる |
| Share | `ShareSheetPresenter` の continuation の再開を、箱が閉じたときの 1 回の処理にする（見張りや取り消しで閉じたときも再開し、continuation を漏らさない） |
| 1 要求 1 つ | 1 つの要求に 1 つの箱と、表示するなら 1 つの ViewController。ViewController を使い回さず、見張りを 2 度付けない |

**解放の見張り**（P1-14 の A）: 表示する ViewController（`UIAlertController`、`UIActivityViewController`）に、箱を強く持つ小さなオブジェクトを関連オブジェクト（`objc_setAssociatedObject`。Objective-C のソースは要らない）で結び付ける。ViewController が解放されたとき、その `deinit`（nonisolated。ViewController にも `self` にも触れない）が箱を閉じる。`present` の完了が一度も来ていなければ表示の失敗、来ていれば `CANCELED_BY_SYSTEM`。箱が既に閉じていれば何もしない。

前提: ライブラリは表示した ViewController を強く持たない（`weak` で持つ）。handler と observer は ViewController を強く捕まえない（README 1.4 の循環参照を 1b で直す。S-5）。

| 終わり方 | 閉じるもの | 完了の値 | 約束 |
|---|---|---|---|
| 利用者がボタンを押した・Share を終えた | handler、`completionWithItemsHandler` | 結果 | する |
| ライブラリの取り消し（Dialog。P1-24） | 取り消し | `CANCELED` | する（完了と `release` は来る。画面は上に重なりがあれば閉じない。R4-8） |
| 表示の前の検査、待ちの失敗（5.13.2） | 表示の手順 | 表示の失敗 | する |
| UIKit が表示を断った | 解放の見張り（`present` の完了が来ていない）。補いとして `present` の直後の `presentingViewController`（G-4） | 表示の失敗 | する |
| ホストや別のコードが Dialog を外から `dismiss` した | 解放の見張り（解放される見込み。G-7） | `CANCELED_BY_SYSTEM` | する（G-7 で解放されないと分かれば約束の外に移す） |
| Share を外から閉じた | `completionWithItemsHandler`（呼ばれる見込み。G-7）か解放の見張り | 結果か `CANCELED_BY_SYSTEM` | する（同上） |
| 表示した scene が切れた | 解放されれば解放の見張り | `CANCELED_BY_SYSTEM` | 解放されるときだけ（P1-15）。システムが切って解放されないときは約束の外（0.1。R4-4） |
| ホストが表示中に window や `rootViewController` を差し替えた、scene を外した、表示した ViewController や古い表示元を持ち続けた | - | 来ないことがある | **約束の外**（0.1）。Dialog は取り消せば完了と `release` が来る。Share は `user_data` が漏れうる |
| 後ろに回った | 終わりではない | - | P1-15 |
| プロセスが終わった | - | 呼ばない | 1.3 |

#### 5.13.2 表示の手順（P1-11、P1-12）

`presenter` の値と操作ごとに、行う段（R3-10）:

| `presenter` | Dialog・Share（表示する） | 権限の要求・設定の画面（表示しない） |
|---|---|---|
| 既定（渡さない） | 今のまま（今の探し方で 1 回探して表示する。待たない）。箱と見張りは付ける | 今のまま |
| 新しい定義の前面（C ABI の受け口が渡す） | 段 1〜6 | 段 1・2 だけ（前面かどうかを見て、前面なら操作する。落ち着きは求めない） |
| 呼び出し側が渡した ViewController | 段 1、3〜6（段 2 で前面を探さず、渡された ViewController の落ち着きだけを見る） | 渡された ViewController の window があれば前面とする |

**落ち着いている**: 前面の ViewController が見つかり、その `viewIfLoaded?.window` が `nil` でなく、`isBeingPresented` でも `isBeingDismissed` でもなく、`presentedViewController` が `nil` で、`transitionCoordinator` が `nil`。

| 段 | すること | 結果 |
|---|---|---|
| 1 | 渡された箱を使う（無ければ作る）。**箱が既に閉じていれば（受け付けの後すぐ取り消された）何もしない**。権限の要求は先に状態を読み、未決でなければ今の状態で箱を閉じて終わる | - |
| 2 | 前面を探す | 見つからなければ `NOT_FOREGROUND` で箱を閉じる |
| 3 | 箱が開いていて、落ち着いていれば、基点を設定して（P1-13）`present` し、見張りを付ける | 表示した |
| 4 | 落ち着いていなければ、移り変わりの途中の ViewController の `transitionCoordinator` の completion を 1 回だけ待つ。coordinator が `nil` か `animate` が偽なら待たない | - |
| 5 | 待ちの completion（または段 4 で待たなかったとき）から、**main キューの次の回に積んで**、箱が開いていれば段 2 から（「渡された ViewController」の行では段 3 から。R4-7）1 回だけやり直す（completion の中ではまだ落ち着いていない見込み。G-4。R3-11）。箱が閉じていれば（取り消された）何もしない | - |
| 6 | 2 回目も落ち着いていなければ | 表示の失敗で箱を閉じる |

- 取り消しは、どのスレッドからでもその場で箱を閉じ、Dialog を閉じる処理を main に積む（5.7、5.13.1）。段 1・3・5 は箱が閉じていれば表示しない。段 3 で開いていることを見た直後に別のスレッドから取り消された場合は、表示した後に、積まれた閉じる処理が動く。そのとき表示の途中なら `present` の完了まで待って閉じる（5.13.1 の「取り消し」。R4-2）
- 同じ main の回で続けて呼んだ 2 つの Dialog は、2 つ目が段 4・5 で 1 つ目の表示の終わりを待って重なる見込み（G-4）

| 場面 | 振る舞い | 出典 |
|---|---|---|
| 同時の要求 | 5.13.2 の手順 | P1-12（D） |
| 通知の権限の要求を重ねる | それぞれの要求にそれぞれの完了を返す（今の static の受け手の上書きは 1b で直す。README 1.4） | README 4 章 |
| 後ろに回った | 取り消さない。利用者が戻って選んだときに完了する | P1-15 |
| 取り消し | Dialog と Clipboard の読み込みは要求の ID で取り消す（P1-24）。Share と権限の要求は取り消せない | P1-24、S-15 |
| Unity のゲームが止まるか | C ABI は変えない。10 章の U-5 | README 8.2、知見 1 章 |

### 5.14 共有の状態とプロセスの終わり（知見 1 章、D-11）

- ID の表、ID の数、帳簿、proxy、入れた印、保ったイベントは、**プロセスが終わるまで持ち、解放しない**（Swift の `static let` と大域の値）
- Swift の大域の値は、プロセスの終わりにデストラクタを走らせない。capi は C++ を持たない（D-10）。したがって Android の `__cxa_atexit` の問題（Android 第 1 部 5.5、0.7）は起きない見込み。`check_ios_dist.py` で、終わりの登録を import していないことを照らす（G-5、5.4）
- プロセスが終わるとき、完了も `release` も呼ばない（1.3）

### 5.15 ログ（P1-18）

- `os.Logger(subsystem: "com.jonghyunkim.nativetoolkit.IosLibraryCApi", category: <機能名>)`
- 受け口の先頭で、関数名と引数を出す（`agent-rules/coding-rules/ios.md` の「全パラメータ」）。ただし、よく呼ぶハンドルの読み取り（`ntk_string_data` など）、`_free`、`ntk_version`、`ntk_last_system_code` は先頭のログから除く（R-35）。ただし**秘密の値（パスワード、入力欄、通知の返信、クリップボードの本文、通知と Share の内容）は出さない**。関数名・エラーの値・ID・件数・列挙は `.public`、そのほかの利用者の値は `.private`
- 失敗したときは、関数名、C のエラーの値、`IosLibrary` のエラーの case、`NSError` の domain と code を出す（D-13 の「詳細は `os_log`」）
- `ios.md` に秘密の値を伏せる例外を足すのは 1b の前（README 8.6、9 章）。capi の規則はそれに合わせて直す

## 6. テストの方針

| テスト | 置き場所 | 中身 |
|---|---|---|
| 入口の検査 | `IosLibraryCApiTests` | `NULL`、厳密な UTF-8 の拒否（1a の 4 種と U+10FFFF を超える値）、長さ、`struct_size` の 5 つの規則（小さい、4096 を超える、`reserved` が 0 でない、知らない部分が 0 でない、知らない部分が 0 なら受け付ける。規則を 1 つずつ壊すと落ちる。R-9）、予約したキーが入口の戻り値で `INVALID_PARAMETER`（P1-9。R-32）、検査の並び（引数の誤りが `NOT_INITIALIZED` より先）。**失敗したときもハンドルの出力に `NULL` が書かれ、値の出力は書かれない**（R-8） |
| 入力の写し | 同上 | 非同期の関数に渡した文字列・バイト列・構造体・ビルダーを、関数が戻った直後に利用者が書き換え・解放しても、結果が呼んだ時点の値になる。ASan で、解放した入力に触れないこと（R-5） |
| `release` のちょうど 1 回 | 同上 | 5.7 の「この表で閉じる順序」の全行。入口で拒んだときは呼び出しスレッドで戻る前に。`release == NULL` を受け付ける |
| 完了のちょうど 1 回 | 同上と、1b のテスト | 取り消し、完了の後の取り消し、知らない ID。5.13.1 の「約束する」の終わり方: ボタン、取り消し（上に画面が重なったときは閉じない）、表示の前の検査と待ちの失敗、UIKit が表示を断った、外から `dismiss`（G-7 で解放を確かめる）、Share を外から閉じる。見張りが普通の経路の結果を上書きしない（handler の直後に ViewController を解放しても結果が残る）。見張りや取り消しで閉じたときも Share の continuation が再開する。handler を背景のスレッドから呼んでも箱が 1 回で閉じる。Clipboard の読み込みを取り消した後に来た結果が捨てられる。約束の外の経路（root の差し替えなど）はテストしない |
| 表示の手順 | 1b の UI テストと単体テスト | 5.13.2 の `presenter` ごとの段: 既定の経路が今と同じ（待たない）、同じ main の回の 2 つの Dialog、閉じかけの ViewController の上への表示、coordinator が `nil` のときの次の回の確かめ直し、2 回目も落ち着かないときの表示の失敗、待つ間の取り消しで表示しない、権限の要求と設定の画面が落ち着きを求めない |
| C の登録が 0 件に戻った間のイベント | 同上 | 唯一の登録を外し、その間にイベントを起こし、また登録すると、保っていたイベントが届く（R-7） |
| スレッド | 同上 | 全コールバックの型について、完了・イベント・受け付けた後の `release` が main で来ること、関数の中で呼ばれないこと（呼び出しのスレッドと「戻った後か」を記録する）。8 スレッド × 25 回の同時の呼び出し（1a 入口 2.1 の `testConcurrentRequests`） |
| main を待たない | 同上 | main を止めた状態（テストの本体が main で、別のスレッドの完了を期限つきで待つ間）に、別のスレッドから全関数（第 2 部の一覧から作る）を呼び、期限内に戻ること。`ntk_notification_install` は `WRONG_THREAD` を戻すこと |
| 競合を決まった順で再現する | 同上 | main に「ラッチで止めるブロック」を積んで main を止め、その間に配送・解除・完了を積んでから放す（Android 第 1 部 6 章） |
| 入れる関数 | 同上と 1b のテスト | main から呼ぶと戻る前に delegate が proxy になっている。2 回目は何もしない（前の delegate が proxy 自身にならない）。差し替えの後の入れ直し。main 以外は即 `WRONG_THREAD` で delegate が変わらない。入れる前の受け手の登録が `NOT_INITIALIZED`。**Swift の口で入れた後の C の受け手の登録が `NONE`**（R-12、R-37） |
| 転送の組み合わせ | 1b の Swift の単体テスト | 1a delegate 3 章の組み合わせの表（メソッド 3 つ × 前の delegate の振る舞い × 通知の種類 × 時期）。**循環**: 3 つのメソッドそれぞれで、最初の転送の呼び出しの中の同期の転送し直しが止まり、「誰も受けない」として扱われる（`didReceive` はイベントを出す）。`openSettingsFor` の `nil`。同じ identifier で `date` の違う配信は循環と見なさない（P1-21）。契約の外の形はテストしない。包みを背景のキューから呼んでも止まらない。`UNUserNotificationCenter` は作れないので、転送の判定と包みを分けて確かめる形を 1b で決める（1a delegate 8 章） |
| 文字列 | `IosLibraryCApiTests` | BMP の外の文字、対になっていないサロゲートと U+0000 が `EF BF BD` になる（1a 入口 5.3）、出力の途中に NUL が無い |
| ハンドル | 同上 | `_free(NULL)`、`NULL` のハンドルの読み取りが `NULL` / 0。違う型のハンドルの読み取りは契約では未定義だが、実装が `NULL` / 0 を返すことを確かめる（型ごとにクラスを分けたことの確かめ。R-30） |
| 構造体の配置 | 同上 | `sizeof` / `offsetof` を、ヘッダーの `/* sizeof N */` と照らす（C# の EditMode のテストと同じ値。知見 3 章） |
| Objective-C のクラス | 同上 | `objc_copyClassNamesForImage` で capi のクラスを挙げ、すべてモジュール名で区切られた Swift のクラスで、`@objc` で名前を固定したクラスが無いこと（5.3） |
| ヘッダー | 2a | C99・C11・C++・Objective-C でヘッダーだけをコンパイル（`-Wall -Wextra -Werror`）、モジュールの検証、5.5 の照合 |
| smoke | `IosLibraryCApiSmoke` | dist の 2 つの xcframework だけで組む C / Objective-C のアプリを、Xcode 26.6 と 26.3 で組む（D-16）。`#include <NativeToolkitC/...>` の形（G-3） |
| 前面 | 1b と 2b の UI テスト | 5.13 の表の操作を前面・後ろ・`foregroundInactive`（Control Center を引き出す間など）で。**後ろにいるまま操作を起こすテスト専用の口**（Android の S-X6 と同じ。サンプルに `#if DEBUG` の口を置く）。iPad の iOS 18.3 のシミュレーターでアクションシートと Share（P1-20）。同じ main の回で 2 つの Dialog を呼ぶと両方出る（P1-12。R-18）。G-6 の 2 つの前提（R-15、R-37） |

新しく足すテストは、守る対象を壊すと落ちることを確かめる（`common.md` の「検査の書き方」、知見 4 章）。

### 6.1 メモリとサニタイザー（P1-20、README 7.4）

| 環境 | 流すもの | 状態 |
|---|---|---|
| シミュレーター iPhone 17 / iOS 26.2 | `IosLibraryCApiTests` を通常・ASan・TSan の 3 通り（ASan と TSan は同時に使えないので別に） | 1a で雛形の 10 件が 3 通りとも通った。TSan は実際に報告し、テストのホストを止める（1a 入口 5.4） |
| シミュレーター iPad Pro 11-inch (M4) / iOS 18.3 | 同上と、アクションシートと Share の UI テスト | popover の例外が出る唯一の環境（1a 入口 5.1） |
| シミュレーター x86_64（iOS 18.3、Rosetta） | 組めること、公開シンボル、smoke | README 7.4 |
| 実機 iPhone XS / iOS 18.7.2 | `IosLibraryCApiTests` の ASan と smoke を、2b の DoD の区切りでだけ。**流す前に毎回利用者の許可を得る** | 未実施（`agent-rules/device-testing.md`） |
| 実機の TSan | 端末では試さない。Xcode の文書で対応を確かめて記録する | 未確認（README 7.4） |

- framework もテストと同じプロジェクトでソースから組むので、サニタイザーは capi の中も計測する（1a 入口 5.4）。`IosLibrary` も同じワークスペースで組めば計測される
- TSan が報告したときにテストのホストが止まり、Mac に crash report が残る。事実を記録してから消す（1a 入口 5.4・9 章）
- `test_ios.sh` に、C ABI のテストを 3 通りで流す区分を足す（2b の成果物。Android 第 1 部 6 章の `test_android.sh` への接続と同じ）

## 7. リスクと緩和策

| リスク | 緩和策 |
|---|---|
| ヘッダーにあって実装の無い関数が配られる（コンパイラーが止めない） | 5.5 の H = E = S の照合。自己テストで壊すと落ちることを確かめる |
| capi の Swift のモジュールを誤って配り、Xcode 26.3 の利用者が組めなくなる | `SWIFT_INSTALL_MODULE=NO` を `check_ios_dist.py` と 5.5 で照らす |
| UIKit の例外でアプリが落ちる | 5.11 の起こさない検査。iPad の iOS 18 でテストする |
| ホストが後から delegate を上書きし、イベントが届かなくなる | KVO のログ。入れ直しの関数（1a-10）。マニュアルの契約。Unity は 10 章の U-4 |
| 前の delegate が completion を持ち続け、背景のアクションでアプリが止められない | ライブラリが無いときと同じ結果なので watchdog を入れない（1a-8）。実機での振る舞いは 10 章の U-6 |
| main 以外から呼んだ操作の完了が、利用者の戻った後の処理より先に来る | ヘッダーの Doxygen とマニュアルに書く。対応付けは `user_data` |
| コールバックで受けたハンドルの解放を忘れる | マニュアルの言語ごとの例に書く |
| 印の無い 1.x の通知のタップが、ホストの delegate に渡って届かない | 移行ガイドに書く。Swift の API の設計書で扱いを決める（README 8.6） |
| `foregroundInactive` を前面に含めたことで、後ろに回る途中に表示が出る | 表示は残り、戻ったときに選べる（P1-15）。UI テストで確かめる |
| ホストが表示中に画面の構成を変える、ViewController を持ち続けると、完了と `release` が来ない | 約束の外とヘッダーとマニュアルに書く（0.1）。Dialog は取り消せる。Share は `user_data` が漏れうると書く |
| 外から閉じた Dialog が解放されない（ライブラリの中に循環参照が残る） | 1b で循環参照を直し（S-5）、外から閉じたときに解放されることを確かめる（G-7） |
| ホストがライブラリから受けた通知をライブラリへ転送し直す | 最初の転送の呼び出しの中の同期の戻りだけ止める。ほかは契約の外とマニュアルに書く（P1-21） |
| 決めた後に README の表が古くなる | P1-n を決めたら、その場で README の 8.1・8.2.1・8.6・5 章・9 章を直す（README 5.1） |

## 8. 第 2 部に送るもの

- 機能ごとの関数・型・同期と非同期の別。**iOS では、`IosLibrary` が完了で返す操作と `@MainActor` の操作は完了のコールバックで返す**（D-6。Clipboard も非同期になる見込み。DF-15）。そのうえで、Android の名前（AP-5 の `_async` の付け方）に合わせるか、iOS だけ `_async` を付けるかを決める
- Dialog と Share の名前を Android の名前（`ntk_dialog_show_*_async`、`ntk_dialog_cancel`、`ntk_share_*`、`ntk_<機能>_add_*_listener`、`ntk_<機能>_listener_remove`）に合わせられるか（README 3.3）。iOS だけの種類（destructive、アクションシート）を同じ形で足す
- コールバックの型と引数の並び（5.8）、イベントの種類（P1-10 の設定の画面を含む）、登録のハンドルの型（AP-6）
- エラーの表（6 以降の値）と、`IosLibrary` のエラーの case との対応表（5.10 の規則）。番号は P1-7 の規則（Android の同じ機能の同じ名前は同じ番号、iOS だけの値は Android の最後の番号の次から、Android だけの番号は欠番）。2a がこの規則を Android のヘッダーと照らす。Notification の `WRONG_THREAD` は 16（P1-7）。v1 の「`IosLibrary` の宣言の順」の推奨は、この規則と両立しないので取り下げた
- 起動のきっかけの通知の取得の形と、保ったイベントを複数の受け手のどれに渡すか（5.12.7）
- 通知の内容の渡し方（ビルダーか `struct_size` の構造体か。AP-4）と、userInfo の C での形（JSON の文字列か、キーと値の組か）。予約したキー（P1-9）は、userInfo を受け取る入口（ビルダーの設定の関数か、操作の関数）の戻り値で `INVALID_PARAMETER` を返す。どの関数かは形とともに決める（R-32）
- 前面の表示の選択肢を変える関数（P1-8 で入れる関数から外したもの）
- 戻り値の無い Notification の操作（`cancel*`、`remove*`、`openNotificationSettings`、`removeCategory`）を、完了とエラーを返す形にするか（README 6 章、8.6）
- 表示の失敗の値（5.13）、`CANCELED_BY_SYSTEM` を返す場面
- BOM の無い UTF-16 や UTF-8 のデータのクリップボードを文字列として読むか（5.9）
- 今のブリッジの 43 関数と README 6 章の振る舞いの集合から新しい関数への対応表。列に「ブリッジの振る舞い」「C ABI の振る舞い」「違いと理由」「Unity の包みが保つこと」を持たせる（AC-23）。前面の判定を足した操作（設定の画面など）はここに書く
- `unity-native-plugin` に渡す対応表の範囲（EditMode の JSON のテスト 126 件の扱い。実物を数えてから書く。知見 3 章、README 8.6）
- `out_request_id` に `NULL` を渡してよいか（1a の雛形は `NULL` を許した）、0 で埋めた構造体のときの Dialog の既定の文言（今のライブラリの既定。README 4 章）、Clipboard の監視を `add` / `remove` の登録の形にするか（今のブリッジは開始と停止）（R-34）
- 今のブリッジの `clipboardCancelLoads`（読み込みの一括の取り消し）を、P1-24 の要求ごとの取り消しに置き換えたことを対応表に書く（Unity の包みが一括を保つ。R-33）
- P1-24 の取り消しの関数の名前（Dialog は Android の `ntk_dialog_cancel`）と、Clipboard の読み込みの取り消しの名前
- `scripts/c_abi_error_numbers.json` の機能ごとの番号の表（P1-7）の中身: 同じ名前は Android と同じ番号、iOS だけの値は Android のその機能の最後の番号の次から、Android だけの番号は iOS で欠番。Share と Clipboard に出る、Android に無い値（`CANCELED`、`CANCELED_BY_SYSTEM`、表示の失敗など）の名前と番号（R4-6）
- 付録 A の全宣言

## 9. 後に続く文書に任せる条件

### 9.1 Swift の API の補完の設計書（1b の前）

`IosLibrary` に足す口が満たすこと。この設計書のレビューの観点にもする。

| # | 条件 | この設計書の節 |
|---|---|---|
| S-1 | delegate を入れる公開の口（今の `setup()` に代わる）。main スレッドだけ、同期、待たない、冪等、差し替えの後の入れ直し、結果（成功 / main でない）を返す。初めて入れたときに `didBecomeActive` の受け手を登録する（P1-22）。C の `ntk_notification_install` はこれを呼ぶだけ | 1.4、5.12.6、5.12.7 |
| S-2 | 転送の delegate: ライブラリが強く持つ、前の delegate を weak、3 つのメソッドを常に実装、`responds(to:)` を呼ぶたびに見る、5.12.2 の見分け方、5.12.3 の転送の規則、5.12.4 の包み（nonisolated で `@Sendable`）、5.12.5 の循環の防止（P1-21）、KVO のログ。状態は `Mutex` で守り、鍵の中で外のコードを呼ばない | 5.12 |
| S-3 | ライブラリが作るすべての通知の要求に印を付ける。利用者の userInfo の同じキーを拒む。利用者に返す userInfo から印を外す | P1-9、5.12.2 |
| S-4 | イベントの口: 複数の受け手、受け手が 0 の間は保つ（件数・期限・順序・重複を決める）、起動のきっかけの通知を P1-22 の規則で別に持つ、イベントは main に積んで配る、`didReceive` の completion は渡すか保つかした後に呼ぶ。C ABI の受け口が、その種類の最初の登録の挿入のブロックの中で保ったものを受け取れる（受け口は受け手を 1 つ足したら外さない。AP-21） | 5.12.7、5.7 |
| S-5 | 完了つきの操作は、プロセスが生きている限りちょうど 1 回完了する。表示を伴う操作は 5.13.1 の「約束する」の終わり方で（ボタン、取り消し、表示の失敗、UIKit が知らせる終わり方）。`showLoginDialog` の失敗も（README 1.4）。仕組みは要求の箱と解放の見張り。**ホストが表示中に画面の構成を変える場合は約束の外**（0.1）。前提として、確定ボタンの handler と observer の循環参照を直し、ライブラリが表示した ViewController を強く持たない（README 1.4）。外から閉じたときの解放は G-7 で確かめる | 1.3、5.7、5.13.1 |
| S-6 | Dialog・Share・権限の要求・設定の画面の表示の口に、表示元の決め方を選ぶ引数（`presenter`。既定は今の探し方、新しい定義の前面、渡された ViewController）を**足す**（既定は変えない。P1-11 の C）。要求の箱（S-15）を受け取る引数も足す。新しい定義の前面を返す公開の口は、今の `getRootViewController()` と別の名前にし、意味の違いを DocC に書く。表示の手順（5.13.2。`presenter` ごとの段）は `IosLibrary` の 1 か所に置く。基点（P1-13）。前面でない・表示の失敗・外から閉じられた（`CANCELED_BY_SYSTEM`）を別の case で返す | 5.13 |
| S-7 | エラーを安定した case にする（任意の `Error` を持たない）。C の値に 1 対 1 で写せる | 5.10 |
| S-8 | 受け手やコールバックを呼ぶ間、利用者のコールバックから届きうる鍵を持たない | 1.1 |
| S-9 | C ABI が要る口はすべて公開の API にする（`@_spi` を使わない） | P1-2 |
| S-10 | `openSettingsFor` をイベントにする（P1-10） | 5.12.3 |
| S-11 | ログの規則（秘密の値を伏せる）。capi の規則（5.15）と合わせる | 5.15 |
| S-12 | 印の無い 1.x の通知の扱いと、更新のテスト（README 7 章）での確かめ | 5.12.3、README 8.6 |
| S-13 | 権限の要求の口も S-6 の `presenter` を取る。新しい定義の前面を選ばれたときは、未決（`notDetermined`）のときだけ前面を要し、落ち着きは求めない（5.13.2 の表）。重ねて呼んでも受け手が上書きされない | 5.13 |
| S-14 | 「proxy がこのプロセスで一度でも入ったか」を読む公開の口（`Atomic` の印。C の口でも Swift の口でも立つ）。C の受け口が P1-6 の判定に使う（R-12） | 1.4、P1-6 |
| S-15 | P1-24 の取り消しに要る公開の口: Dialog を要求ごとに閉じる、Clipboard の読み込みを要求ごとに取り消す（今は `cancelAllLoads` だけ）。**要求の箱は表示の口・読み込みの口を呼ぶ前から作れ（公開の型。C の受け口が受け付けの時点で作って渡す。R4-1）、取り消しはどのスレッドからでも呼べて待たず、その場で箱を `CANCELED` で閉じ、閉じる・止める処理を main に積む**。表示の途中なら `present` の完了の中で閉じる（R4-2）。Dialog の上にほかの画面が重なっていれば閉じない | 5.7、5.13.1 |
| S-16 | `CompletionOnce`、要求の箱と解放の見張り、関連オブジェクトの鍵を、`@unchecked Sendable` と `nonisolated(unsafe)` の一覧（P1-17）に入れ、理由と TSan のテストを持つ。前の delegate に渡す closure は `@unchecked` にしない | P1-17 |

### 9.2 第 2 部と 2b（C ABI の受け口）

| # | 条件 | この設計書の節 |
|---|---|---|
| C-1 | 入口のファイルは `@c @implementation` の関数だけで、`public` はそれだけ（P1-1）。受け口は `IosLibrary` の公開 API だけを呼ぶ（P1-2） | 5.3 |
| C-2 | main へは `DispatchQueue.main.async` だけで積む。待つ形を書かない | 5.6 |
| C-3 | **受け付けた後の** `release` は `tryRelease` だけが呼ぶ。入口で拒んだときは、`Registration` を作る前に呼び出しスレッドで直接呼ぶ（R-28）。5.7 の表のとおり | 5.7 |
| C-4 | 出力の文字列は `CApiString` の変換を通す。Foundation の UTF-8 の変換を使わない | 5.9 |
| C-5 | 5.4 の設定、5.5 の照合、`check_ios_dist.py` の追加（版の組、終わりの登録） | 5.4、5.5 |
| C-6 | `test_ios.sh` に C ABI のテストを 3 通りでつなぐ | 6.1 |
| C-7 | 2c の Unity の包みは、今のブリッジの受け手の差し替えを、種類ごとに 1 つのハンドルと「今のハンドル」の印で表し、今のハンドルでない配送を捨てる（Android 第 1 部 C-6）。iOS の Unity は main で受けるので、判定は受けたその場でよい | 5.7 |
| C-8 | 入力は main に積む前に深く写す。出力の `NULL` を入口で書く。ハンドルの型ごとにクラスを分ける | 5.7 |
| C-9 | 最初の呼び出しで `IosLibrary` の版を読み、capi と違えばログに出す（P1-19） | P1-19 |

## 10. `unity-native-plugin` の agent に任せる確かめ（1a-4、README 5 章の 1a の行、8.2）

こちらは雛形の 2 つの xcframework・ヘッダー・申し送り（確かめること、合格の条件、手順、実機の決まり）を `results/` に出し、向こうの結果をこの第 1 部に反映する（README 5 章）。実機は利用者の私物なので、向こうでも危ない操作は毎回許可を得る（D-21）。

**申し送りの分け方**（P1-23 の A）: 1a の入口の雛形には通知の関数が無いので、U-3・U-4・U-6・U-7 は今の雛形では流せない（R-19）。2 回に分ける。

| 回 | 雛形 | 確かめ | 時期 |
|---|---|---|---|
| 1 回目 | 1a の入口の雛形（`results/probes/stage1a/entry/`。`ntk_version`、`Common.h` のハンドル、コールバック付きの非同期の関数、UIKit の例外を起こす関数）に、下の Dialog と Share の関数を足したもの | U-1、U-2、U-5、U-8、U-9、U-10 | すぐ |
| 2 回目 | 1 回目の雛形に、1a の delegate の雛形（`results/probes/stage1a/delegate/` の proxy と入れる関数）を、**入れる関数を `@c @implementation` にし、循環の防止を P1-21 の形（5.12.5）に直してから**足し、下の関数を入れたもの（R2-8） | U-3、U-4、U-6、U-7 | Swift の API の設計書を書く前（U-3・U-4 の結果が 1a-13 と Swift の API の形を変えうるため） |

1 回目の雛形に足す関数（名前は雛形だけのもの。本番の名前は第 2 部で決める。R2-8）:

| 関数 | 中身 |
|---|---|
| `ntk_probe_dialog_show_alert(title, message, fn, user_data, release, out_request_id)` | 5.13.2 の手順（P1-11 の C、P1-12 の D の推奨の形）でアラートを出し、押したボタンで完了する |
| `ntk_probe_dialog_cancel(request_id)` | P1-24 の取り消し |
| `ntk_probe_share_text(text, fn, user_data, release)` | 同じ手順で Share のシートを出し、完了する |

2 回目の雛形に入れる関数:

| 関数 | 中身 |
|---|---|
| `ntk_notification_install(void)` | 1.4 の契約のとおり（`NONE` / `WRONG_THREAD = 16`） |
| `ntk_probe_notification_add_listener(fn, user_data, release, out_listener)` と `ntk_probe_notification_listener_remove(listener)` | タップ・アクション・テキスト入力のイベントを受ける（受け手が 0 の間は保つ。5.12.7） |
| `ntk_probe_notification_get_launch_response(out_identifier, out_action)` | P1-22 の規則の起動のきっかけ。無ければ `NULL` を書いて `NONE` |
| `ntk_probe_notification_schedule_marked(seconds, identifier, with_background_action)` | 印のある通知（P1-9）を何秒か後に予約する。背景のアクション（`options: []`）を持つ category を付けられる |
| `ntk_probe_notification_request_permission(fn, user_data, release)` | 権限の要求（前面の判定つき） |

| ID | 回 | 確かめること | 合格の条件 | 結果で変わる決定 |
|---|---|---|---|---|
| U-1 | 1 | Unity 6000.4.2f1 の書き出した Xcode プロジェクト（release ビルド）に 2 つの xcframework を手で入れ（UnityFramework にリンク、アプリに Embed & Sign、`CodeSignOnCopy`）、`DllImport("__Internal")` で `ntk_version()` とコールバック付きの関数を呼ぶ | 実機（iPhone XS）で `0x020000` が返り、コールバックが main で 1 回、`release` がその後に 1 回来る | 失敗したら D-9（dynamic の 2 つ）を見直す（static を足す C 案など）。知見 1 章の D-10 の反省 |
| U-2 | 1 | Release のアーカイブで、2 つの framework がアプリの証明書で署名し直され、Team ID が付いている（`codesign --verify --deep --strict`）。可能なら Organizer の Validate App | 両方とも valid で、TeamIdentifier がアプリと同じ | 失敗したら D-18（署名しない）を見直す |
| U-3 | 2 | `.mm` の `AppDelegateListener` から `ntk_notification_install` を呼ぶ時期（`kUnityWillFinishLaunchingWithOptions` と `didFinishLaunching`。`didFinishLaunchingNotification` の受け手も。R-21）。アプリを止めてから通知をタップするコールドスタートで、起動のきっかけの通知とタップのイベントが C# に届くか。Unity 6000.4 の起動の順（scene の `willConnectTo` との前後） | どちらかの時期で、コールドスタートのタップが 1 回届き、起動のきっかけとして取れる。戻り値が `NONE` | 間に合わなければ 1a-13 を決め直し、ホストから応答を渡してもらう関数を足す。D-4 の期限の書き方。P1-22 |
| U-4 | 2 | Unity の通知パッケージ（`com.unity.mobile.notifications`）を入れたときに、どちらが後に入るか（リンクの順を入れ替える）。ライブラリが必ず後に入る形（`didFinishLaunching` の受け手）で、パッケージの通知とライブラリの通知の両方が正しい受け手に届き、コールドスタートのタップも受けられるか。Unity の本体（パッケージ無し）が delegate を設定するか。パッケージが proxy に転送するか（循環の防止が働くか。P1-21） | 両方の通知が自分の受け手に届く順が 1 つ以上あり、その順をホストの側で固定できる。入れ直しを使う順なら、**パッケージの delegate が前の delegate へ同期に転送すること**（非同期なら、その順は契約の外。R4-5） | 成り立たなければ、マニュアルに「共存できない」と書くか、1a-13 の関数を足す。5.12.8 の表 |
| U-5 | 1 | Unity の root の ViewController の上に Dialog と Share を出したまま、ゲームのフレームが進むか（1 回目の雛形の Dialog と Share の関数で） | 結果を記録する（合否ではない） | C ABI は変えない。マニュアルと `unity-native-plugin` の案内。知見 1 章の D-7 と同じ観点 |
| U-6 | 2 | 通知の背景のアクション（`options: []`）で、ライブラリの通知の completion を main のブロックの中で呼ぶ形（1a-12）のとき、C# のコールバックが動く前にアプリが止められないか。前の delegate が completion を呼ばない・遅れて呼ぶ場合に、実機で止められる時期 | 背景のアクションのイベントが、受け手がいれば C# に届き、いなければ保たれて次に前面に来たときに届く | 1a-12（completion の時期）、1a-8（watchdog を入れない）を見直す |
| U-7 | 2 | アプリが後ろに移った直後の `willPresent`（シミュレーターでは約 3 秒の間呼ばれた）が実機でも起きるか | 結果を記録する | 5.12.3 の `willPresent` の説明 |
| U-8 | 1 | 起動の直後（`foregroundInactive` の間を含む）と、Unity の `Start()` から Dialog を呼んだときに出るか。同じフレームで Dialog を 2 つ呼んだとき | **結果を記録する**（合否ではない。P1-11・P1-12 は未決なので、雛形は推奨の形で組み、結果を判断の材料にする。R2-8） | P1-11（前面の定義）、P1-12。利用者が別の案を選んだら、その形で流し直す |
| U-9 | 1 | C# のコールバックが例外を投げたときの振る舞い（IL2CPP の iOS） | 結果を記録する | P1-16 のマニュアルの書き方（「必ず try / catch」） |
| U-10 | 1 | 実機の TSan（Xcode の文書で対応を確かめる。端末では試さない）と、実機の ASan（許可を得て） | ASan で報告が 0 | P1-20。README 7.4 の DoD の行 |

こちらで行う確かめ（Unity は要らない。1b）: `openSettingsFor` をシステムから呼ばせること（Xcode で組んだサンプルなら設定の App の一覧に出る見込み。1a delegate 3.4・6 章）、G-4、G-6、G-7、G-8、G-9。

## 11. 入力の食い違いと、README を直す所

この設計書を書く中で見つけた、入力どうしの食い違いと、README の直し。P1-n の決定（2026-10-31）の後に、下の表の README の直しを行った（状態の「済み」）。

### 11.1 入力の食い違い

| # | 食い違い | どちらに合わせるか | 状態 |
|---|---|---|---|
| 1 | README D-4・D-7 の末尾が「8.2.1 の 1a-5〜1a-13」だった（1a-5 はヘッダーの include の決定） | 1a-6〜1a-13 | **済み**（README は直してある。R-20） |
| 2 | README 3 章の木は、機能のフォルダを「C の入口（C。Objective-C は使わない）」、`Common/` を「スレッドごとの `ntk_last_system_code`」とし、`Adapter/` を置く。1a-1 と 1a-3 の前に書かれたまま | 5.1 の木（P1-1） | 済み |
| 3 | README 7 章の C ABI のテストの行、7.3 の表（「クラス名の接頭辞は 7 章の C ABI のテストで照らす」）、D-11 (2)、8.2 の表の行、8.6 の行は、Objective-C のクラスの接頭辞を条件にする。`@c` の形では `@objc` のクラスが無く、Swift のクラスはモジュール名で区切られる（1a 入口 4.3） | 「`@objc` で名前を固定したクラスが無く、すべてモジュール名で区切られている」（6 章。R-42） | 済み |
| 4 | README 8.3 の表の `BUILD_LIBRARY_FOR_DISTRIBUTION`（capi は「要否を 1a で決める」）と「C の入口」（「形は 1a で決める」）が古い | P1-19 と 1a-1 | 済み |
| 5 | README D-7 は「受け手が登録されるまでイベントを保つ件数」「1.x で予約した通知（印が無い）の扱い」を第 1 部で決めるとし、README 8.6 は同じ 2 つを Swift の API の設計書に置く | 8.6。第 1 部は C ABI の側の規則（5.12.7、5.12.3）だけ（9.1 の S-4・S-12） | 済み |
| 6 | 1a delegate 7 章の 5 は「第 1 部で番号を決める」とし、依頼は「対応表は第 2 部」とする | P1-7 で番号の規則と `WRONG_THREAD` の番号だけを第 1 部で決め、表は第 2 部 | 済み |
| 7 | README 1.3 は通知のアクションのスレッドを「文書に書かれていない」とし、`IosNotificationManager` の DocC は「system が使うスレッドで呼ぶ」とする。1a ではシミュレーターですべて main | 「シミュレーターでは main。文書には無い」。main を前提にしない（5.12.1） | 済み（README 1.3。DocC は 1b） |
| 8 | `IosClipboardManager` の DocC は「Unity のブリッジだけがどのスレッドからも呼べる入口」と書く。ブリッジは 0e でビルドから外した（D-22） | 1b で DocC を直す | 1b（DocC。README の直しは無い） |
| 9 | 知見 2.3 は「iOS の `__Internal` は静的リンク」とする。配布物は dynamic（D-9）で、知見 3 章で訂正済み | D-9。capi は C++ を持たない（5.14） | 記録だけ（知見のファイルは変えない） |
| 10 | `IosNotificationManager.foregroundPresentationOptions` の既定は `[.banner, .list, .sound, .badge]`、1a の雛形は `[.banner, .list]` | 今のライブラリの既定（5.12.3） | 文書の中は済み |
| 11 | README 1b の行は「ネイティブの利用者から見た動作は変えない」とする。P1-11 の C（口と引数を足す）、P1-12 の D（移り変わりを待つ）、P1-14 の見張りと P1-15（完了が来なかった経路で完了する）、P1-9（印、予約したキーの拒否）、P1-10（`openSettingsFor`）は `IosLibrary` に足すか変える | P1-11・P1-12・P1-14・P1-15 は 1.4 の不備の直しか追加として、P1-9・P1-10 は動作の変更として、README 4.1 と 1b の行に書く | 済み |
| 12 | README D-7 の「`didReceive` の completionHandler をちょうど 1 回呼ぶこと（前の delegate が呼ばない場合を含む）」と、1a-8（watchdog を入れない。2 回目を捨てるだけで、前の delegate が呼ばなければ 0 回） | 1a-8。D-7 の文を「多くても 1 回。前の delegate が呼ばなければ、ライブラリが無いときと同じく呼ばれない」に直す（R-20） | 済み |
| 13 | 起動のきっかけの通知の取り方（D-7 の「第 1 部で決めること」） | 見分け方は P1-22、取得の形は第 2 部（8 章）に送った（R-20） | 済み |
| 14 | README 3.1 の前提の表は、後ろにいるときの Dialog・Share・権限の要求に「専用のエラーを返す。設計で決める」とする | `NOT_FOREGROUND`（Android と同じ名前。完了で返す。5.13。R-20） | 済み |
| 15 | README 6 章の振る舞いの集合の「登録と解除」は Clipboard の読み込みの一括の取り消しを含むが、P1-24 は要求ごとの取り消しに置き換え、Dialog の取り消しを足す | P1-24 が決まったら 6 章の表の数と「追加」の行を直す | 済み |
| 16 | README 3.1 の「成り立たない使い方」に、0.1 の 2 つの契約（前の delegate へ非同期に転送する delegate を入れた後で入れ直しを呼ばない、表示中に画面の構成を変えない・ViewController を持ち続けない）と、システムが scene を切って ViewController が解放されない場合が無い | P1-14・P1-15・P1-21 が決まったら 3.1 に足す。Share は `user_data` が漏れうることも | 済み |

### 11.2 P1-n が決まった後に README で直す所

| README の所 | 直し | 元 | 状態 |
|---|---|---|---|
| 8.1 の D-5 | `openSettingsFor` のイベント（P1-10）と、Dialog の取り消し・Clipboard の読み込みの要求ごとの取り消し（P1-24）を範囲に足す（決め直し） | P1-10、P1-24 | 済み |
| 8.1 の D-4 | `NOT_INITIALIZED` を返す場面（proxy がどの経路でも一度も入っていないときの、通知のイベントの受け手の登録と起動のきっかけの取得） | P1-6 | 済み |
| 8.1 の D-6・D-7 | 入れる関数のエラーは `WRONG_THREAD = 16`。D-7 の「第 1 部で決めること」の各項目に、この文書の節を書く（11.1 の 5・12・13） | P1-7、5.12 | 済み |
| 8.1 の D-11 | (2) を 11.1 の 3 のとおりに直す | 1a 入口 4.3 | 済み |
| 8.2.1 | 1a-8 の「循環を防ぐ」に P1-21 の範囲を、1a-9 に番号を書き足す | P1-7、P1-21 | 済み |
| 8.6 の「C ABI 第 1 部」の 6 行 | 決めた節（5.7、5.9、5.11、5.12、5.13、5.3）を書き、済みにする | この文書 | 済み |
| 3 章の木 | 5.1 の木に直す | P1-1 | 済み |
| 3.1 の表 | 後ろにいるときは `NOT_FOREGROUND`。通知の行に、Swift の口で入れてもよいこと。0.1 の 2 つの契約（11.1 の 16） | 11.1 の 14・16、P1-6、P1-14、P1-21 | 済み |
| 6 章の表 | P1-24 の取り消し（11.1 の 15） | P1-24 | 済み |
| 4 章の表と 4.1 | 足す口（`presenter` の引数、新しい定義の前面を返す口、要求ごとの取り消し、proxy が入ったかを読む口、`didBecomeActive` の受け手）、印と予約したキー、`openSettingsFor` のイベント、要求の箱と解放の見張り、表示の手順の待ち | S-6、S-14、S-15、P1-9、P1-10、P1-12、P1-14 | 済み |
| 5 章の 1a の行 | 申し送りを 2 回に分ける（10 章） | P1-23 | 済み |
| 5 章の 1b の行 | 11.1 の 11 | P1-11、P1-12、P1-14、P1-15 | 済み |
| 7 章の C ABI のテストの行と 7.3 | 11.1 の 3。7.3 に版の組と終わりの登録の照合を足す | 5.4、P1-19 | 済み |
| 7.4 と 9 章の DoD | 実機の ASan は区切りでだけ毎回許可を得て流す。実機の TSan は文書で確かめる | P1-20 | 済み |
| 8.3 の表 | 11.1 の 4 | P1-19、1a-1 | 済み |
