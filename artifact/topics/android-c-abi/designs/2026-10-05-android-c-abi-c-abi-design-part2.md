# Android ライブラリ C ABI 実装設計書（第 2 部: 関数・対応表・ヘッダー）

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/android-c-abi/README.md` |
| 対象段階 | 段階 2（2a の機械照合、2b の実装、2c に渡す対応表）の前 |
| 対象 OS | Android 12（API 31）以降、`arm64-v8a` と `x86_64` |
| 作成日 | 2026-10-05（第 3 版。2 回目のレビューを反映） |
| ブランチ | `feature/NTKIT-17` |
| 前段階 | 第 1 部（`designs/2026-10-04-android-c-abi-c-abi-design.md`。以下「第 1 部」。スレッド・寿命・Context・初期化・`release` の状態機械を決めた）、段階 1b（Kotlin の API の補完。`results/2026-10-05-android-c-abi-stage1b-implementation-feature-result-v1.md`。以下「1b の結果」） |
| 元にした文書 | Kotlin の API の設計書（`designs/2026-10-04-android-c-abi-kotlin-api-design.md`。以下「Kotlin の設計書」）、Windows の C ABI の設計書（`windows-architecture/designs/2026-09-21-windows-architecture-c-abi-design.md`。以下「Windows の設計書」）、今のブリッジ（`android/unity_android_plugin`） |
| レビュー | `reviews/2026-10-05-android-c-abi-c-abi-design-part2-review-v1.md`（1 回目。W-C、W-X）、`-v2.md`（2 回目。Y-C、Y-X） |
| 章立て | Windows の設計書と同じ番号にする（8.1 の操作、8.2 の関数の全体、11 章のエラー、付録 A）。2a の機械照合が同じ見出しを読むため |

- **`PLANNED_SYMBOLS_EXEMPT`**: この設計書は、まだ書かれていない C ABI の名前（`ntk_*`）と受け口（`capi.jni`）を定める。名前が実装にあるかの照合は 2a の機械照合と 2b の DoD が受け持つ

## 0. この設計書で決めたこと

ID は `AP-n`（第 2 部）。第 1 部の `AC-n` は変えない。

| ID | 決めること | 決定 | 理由 |
|---|---|---|---|
| AP-1 | 入口 | **C ABI の受け口は、機能ごとに `Android*Manager` を `getInstance` で得て呼ぶ**（Kotlin の設計書 KA-18、8.15）。`*UseCases` は呼ばない | `common.md`「機能の公開の入口」 |
| AP-2 | 同期と非同期の分け方 | **前面が要る操作だけを非同期（完了のコールバック）にし、ほかは同期で戻り値を返す**。非同期: Dialog、通知の権限の要求、設定の画面、Share の Chooser を開く操作。同期: Clipboard の書き込み・消去・読み取り・問い合わせ、通知の表示・更新・消去・チャンネル・予約・Progress・問い合わせ、Direct Share。**Clipboard の監視の開始と停止は main に積むが、完了のコールバックは持たない**（戻り値は main への受け付けを表す。6.1） | 第 1 部 8 章「main を要しない処理は同期の関数で返してよい」と common.md の「システム API に合わせた同期・非同期設計」。同期にする経路が main と Looper に依存しないことをコードで確かめた（第 2 版。Clipboard の読み書きは Binder の呼び出し、通知は `NotificationManager`・`AlarmManager`・予約のファイル・サービスの起動、Direct Share は `Bitmap` の解読と `ShortcutManagerCompat`。どれにも `Handler` の作成も main の検査も無い。main の検査を持つのは Clipboard の監視だけ） |
| AP-3 | Clipboard の読み書きを main に積むか | **積まない**（AP-2）。Kotlin の設計書 7 章の「Clipboard と Share の操作を main で動かす（C ABI の受け口が main に積む）」の Clipboard の部分を改める。Share は前面の判定が要るので main に積む | 書き込みはフォーカスも main も要らない。読み取りはフォーカスが要るが、main に積んでも得られない（フォーカスはアプリの窓の状態で決まる）。同期にすれば、利用者は戻り値で結果を得られる |
| AP-4 | 受け渡しの形 | 第 1 部 1.1 の 3 方式。**通知の内容とチャンネルはビルダーのハンドル**（Windows の `ntk_notification_content_*` と同じくビルダーにする。必須の項目を `_create` の引数で受ける点は Windows と違う）、Dialog の要求・予約・Share の内容・Direct Share の共有先・通知のアクションは `struct_size` 付きの構造体、Chooser Action は `struct_size` を持たない組の配列（Windows の `ntk_dialog_filter` と同じ） | 通知の内容は 30 項目と入れ子（style、アクション、data）を持ち、既定値が 0 でない項目が多い。ビルダーは Kotlin の既定値で始まるので、0 で埋める規則（E-9）の名前の反転が要らない |
| AP-5 | 名前 | 同じ意味の操作は Windows と同じ名前（`ntk_clipboard_copy_text`、`ntk_notification_show`、`ntk_notification_schedule`、`ntk_notification_cancel_scheduled`、`ntk_notification_update_progress`、`ntk_notification_remove_all`）。**`_async` を付けるのは、Dialog の 6 つ（第 1 部 AC-7）と、Windows に同期の同じ名前がある設定の画面（`ntk_notification_open_settings_async`）**。Android だけのもの（Share、権限の要求）は付けない | 同じ名前は同じ意味にそろえる。ただし引数、列挙の値、構造体の配置は OS ごとに違うので、**C# のバインディングは関数・列挙・構造体を OS ごとに宣言する**（RP-5、16 章）。Dialog の 6 つに `_async` を付けるのは第 1 部 AC-7（Windows に同じ名前が無い `confirm` なども含め、Dialog はすべて非同期で名前を分ける）。設定の画面の `_async` は、Windows の同期の `ntk_notification_open_settings` と取り違えないため |
| AP-6 | イベントの登録 | 機能ごとに 1 つのハンドルの型（`ntk_clipboard_listener`、`ntk_notification_listener`、`ntk_share_listener`）と、種類ごとの `_add_*_listener`、機能ごとの `_listener_remove` | 第 1 部 AC-21（足す・外す形）と 1.3.1（「第 2 部で決める」） |
| AP-7 | 型のある Chooser Action の世代 | **`ntk_share_text` はアクションが 0 個でも `shareTextWithActions(content, emptyList(), preview)` を呼ぶ**（前の Share のアクションを止める） | 今のブリッジは Share のたびに前のアクションを外していた（1b の結果 7 章の申し送り）。`AndroidShareManager.shareText` は世代を上げない |
| AP-8 | 値の補正と代わりの値 | **C ABI は補正も代わりの値も行わず、範囲外や引けない名前をエラーで返す**。例外は Progress の前景サービスの 3 つの補正（AP-9）だけ。**名前を引く型は関数で決まり、利用者は指定しない**: アイコンと画像は型を指定せずに引く（`NotificationResourceResolver.resolve(name)`。drawable、無ければ mipmap）、layout の名前は `layout`、view の ID は `id`（第 3 版で直した） | 今のブリッジの補正と代わりの値は、利用者に見えない形で入力を変えていた。importance・visibility の丸め、BigPicture や layout が引けないときの Default、Messaging の名前の既定 `"You"` と時刻の既定、小さいアイコンが引けないときの既定のアイコン、大きいアイコン（BigPicture の分を含む）が引けないときの省略、アクションのアイコンが引けないときの 0、view の ID か `actionId` の無いクリックを捨てること、`bigText` の `null` を空にすること。C ABI は新しい契約なので（AC-23）、黙って変えずに知らせる。Unity から見た今の動作は 2c の包みが保つ（16 章）。**ブリッジの JSON はアイコンのリソースの型（`{name, type}`）を指定できたが、C ABI は名前だけを受ける**（アイコンと画像は drawable と mipmap 以外の型では引けない。layout と view の ID は今のブリッジと同じ型で引く） |
| AP-9 | Progress の前景サービスの補正 | `ntk_notification_start_progress` と `_update_progress` は、内容の `ongoing` を真、`auto_cancel` を偽、`only_alert_once` を真にして渡す。`_complete_progress` は `ongoing` を偽、`auto_cancel` を真、`only_alert_once` を真、`current` を `max` にして渡す。進み具合が無ければ `INVALID_PARAMETER` | 前景サービスの通知として成り立つための条件で、利用者が選ぶ値ではない（Kotlin の設計書 7 章 N12 は「C ABI か包み」とした。C ABI に置けば、どの利用者にも同じになる） |
| AP-10 | Clipboard の監視の問い合わせ（`isObserving`） | **出さない** | README 6 章の振る舞いの集合に無く、main だけの状態をほかのスレッドから読む口になる。監視の開始と停止は冪等 |
| AP-11 | 解除の副作用 | **`_listener_remove` は登録を外すだけ**。今のブリッジの `clear*Listener` の副作用（Clipboard の監視を止める、Share の選択の待ちを消す、Chooser Action の Receiver を外す）は持たない | 副作用は別の関数（`ntk_clipboard_stop_observing`、`ntk_share_cancel_selection`）で選べる。Unity から見た今の動作は 2c の包みが保つ（10 章） |
| AP-12 | エラーの値 | **各機能のエラーは、0〜5 を共通の意味（`NONE`、`INVALID_PARAMETER`、`NOT_INITIALIZED`、`NOT_SUPPORTED`、`UNKNOWN`、`OUT_OF_MEMORY`）にし、6 から機能ごとの値を置く** | Windows は C++ の `enum class` の順を写したので機能ごとに番号がそろっていない。Android は Kotlin に対応する列挙が Clipboard だけなので、そろえられる |
| AP-13 | Dialog を閉じたときの値 | 戻るや外側のタップで閉じたときは、結果の種類 `DISMISSED` だけを返し、選択の状態は返さない | Kotlin の `DialogResult.Dismissed` が値を持たない。今のブリッジは閉じたときも選択の状態を返していた。違いは 8.3 に書く |
| AP-14 | 前面が要る操作 | 第 1 部 5.8 の表に、Progress の前景サービスの行を足す: **前面は判定しない**。後ろからの開始・更新・完了・停止を OS が止めたら（`ServiceStartNotAllowedException` とその子の `ForegroundServiceStartNotAllowedException`・`BackgroundServiceStartNotAllowedException`）`SERVICE_START_NOT_ALLOWED` を返す | 前景サービスの開始は Activity を起動しない。開始は `startForegroundService`、更新・完了・停止は `startService` で、どちらも後ろからは OS が止めうる。例外で分かるので、同期の戻り値で返せる |
| AP-15 | 2a の照合の入力 | 8.1 の表（操作）、8.2 の表（関数の数と合計）、10 章の表（振る舞いの集合）、11 章の表（エラーの値）、付録 A（宣言）。公開シンボルは、ソースの照合をヘッダー・8.2・付録 A の 3 者で行い、ビルドの後に `llvm-nm -D --defined-only` を別に照らす | version script が `ntk_*` のワイルドカードなので、Windows の `.def` に当たる一覧がソースに無い |
| AP-16 | Kotlin が黙って成功にする場面（第 2 版、第 3 版で範囲を決めた） | **受け口が Kotlin を呼ぶ前に、呼び出し時点の状態で確かめる**（最善の努力）。通知の表示と更新と、**過ぎた時刻の予約**（Kotlin は Alarm を使わずにすぐ出す）は、`hasPermission()` か `areNotificationsEnabled()` が偽なら `PERMISSION_DENIED`（Kotlin は黙って成功で戻る。`NotificationRepositoryImpl.notify`）。**未来の時刻の正確な予約**（`inexact` が 0）は、`canScheduleExactAlarms()` が偽なら `EXACT_ALARM_NOT_ALLOWED`（Kotlin は黙って不正確な Alarm に下げる。`scheduleAlarm`）。**確かめた後に状態が変わった場合は守らない**: 確かめと Kotlin の呼び出しの間に利用者が通知を切ると、黙って表示されずに `NONE` になりうる（通知の権限（`POST_NOTIFICATIONS`）や正確なアラームの許可（ライブラリが宣言する `SCHEDULE_EXACT_ALARM`）を取り消すとアプリのプロセスが止まるので、残るのは「通知が無効」に変わる場合だけ）。予約した通知が発火した時点で権限が無いときも、黙って出ない（1.x と同じ。8.3 の NT-21） | AP-8 の「黙って変えない」。Kotlin の振る舞いは 1.x からのもので変えない（K-9）。第 1 部 5.11 の「通知は `PERMISSION_DENIED`」はこの値。完全に守るには Kotlin が採った経路を結果で返す必要があり、K-9 に反するので、最善の努力とその限りを契約に書く |
| AP-17 | Share の要求の ID（第 2 版、第 3 版で取り消しの経路を決めた） | **C が受け付けの時点で ID を付け、帳簿（main だけが触る）で Kotlin の印（`shareForSelection` が返す値）と対にする**。Kotlin の印は main で前面を確かめた後に初めてできるので、関数が戻る時点では無い（第 1 部 1.3、5.7）。**取り消しは必ず main に積み**、main で帳簿から印を引いて `cancelShareSelection` を呼ぶ（main は積んだ順に処理するので、開く処理は常に取り消しより先に動く）。選択のイベントは印を C の ID に変えて配り、**帳簿に対の無い印（アプリの Kotlin が直接 `shareForSelection` を呼んだものなど）の選択は捨てる**。前面でなくて開かなかった要求は印を持たず、選択も来ず、前の待ちも消さない。**開く処理が失敗したとき、帳簿は変えない**: Kotlin は前の待ちを新しい印で置き換えた後に Chooser を開き、開けなければ新しい印を取り消して投げ直す（`ShareRepositoryImpl.openWithResult`）。C からは印ができた後の失敗かが見えないので、利用者には値で分ける。印を作る前の失敗（`NOT_FOREGROUND`、空白だけの本文の `EMPTY_CONTENT`）では前の要求の待ちが残り、印を作った後の失敗（`NO_SHARE_TARGET`、`UNKNOWN`）では前の要求の選択はもう届かない。後者で帳簿に残った前の対は、選択が来ないだけで害は無い。対は、次の `shareForSelection` が印を得たとき・取り消し・選択のイベントで外す | Dialog と権限の要求と同じ形にする |
| AP-18 | 通知の本文のタップと dismiss の既定（第 2 版） | **ビルダーの既定は、本文のタップでアプリを開いてタップのイベントを出し、dismiss のイベントも出す**（今のブリッジと同じ）。`_set_tap(content, mode)` で「アプリを開いてイベント」「イベントだけ」「何もしない」を選び、`_set_dismiss_event(content, 0)` で dismiss のイベントを外す | ブリッジはどの通知にも本文のタップ（`launchAppOnTap` の既定は真）と dismiss の Intent を付けていた。Kotlin の `contentIntent` の既定は `null` なので、何も足さなければタップでアプリが開かない |
| AP-19 | 入口で返す失敗と完了で返す失敗（第 2 版） | **Kotlin を呼ばずに C の入口で決まる検査は、非同期の操作でも戻り値で返す**（`NULL`、不正な UTF-8、`struct_size`、範囲、件数 0（`EMPTY_FILE_LIST`、`EMPTY_ID_LIST`、`EMPTY_ITEMS`）、空文字列の本文（`EMPTY_CONTENT`）、Chooser Action の空の ID・重複した ID・`NULL` か大きさ 0 のアイコン（`INVALID_CHOOSER_ACTION`））。入口で拒んだときは完了を呼ばず、`release` だけを呼び出しスレッドで 1 回呼ぶ（第 1 部 1.3）。Kotlin を呼んで分かる失敗（空白だけの本文の `EMPTY_CONTENT`（Kotlin の `isBlank`）、読めないアイコン、ファイルが無い、前面でない）は完了で返す。**同じ値が入口と完了の両方から来うる**（空文字列は入口、空白だけは完了） | 第 1 部 1.3 の「入口で拒んだとき」。どの値がどちらで来るかを、利用者とテストが決められるようにする |
| AP-20 | 大きいアイコンのバイト列（第 2 版） | **出さない**（第 1 版の `_set_large_icon_bytes` を外した） | ブリッジに無く、README D-5 の範囲（今のブリッジの振る舞いの集合）を超える。要るなら後の版で足す（ビルダーの関数なので互換を壊さずに足せる） |
| AP-21 | イベントの受け手と保持（第 2 版、第 3 版で直した） | **受け口は、その種類の最初の C の登録で `EventHub.addListener` を 1 つ足し、以後は外さない。通知の操作のイベントは、その種類の `ACTIVE` な C の登録が 0 の間に受け口に届いたものを、受け口が 32 件まで保ち（古いものから捨てる）、次の C の登録の挿入のメッセージの中で配る**。最初の C の登録より前のイベントは `EventHub` が保ち、`addListener` の中で届くので、同じ規則で配る | `EventHub` は受け手が 0 の間だけイベントを保つ（Kotlin の設計書 8.4）。第 2 版の「0 に戻ったら外す」は、コールバックの中で唯一の登録を外して足し直すと、`EventHub` が `addListener` の中で同期に配っている途中のイベントを失った（Y-X2）。保持を受け口に持たせれば、外す・足すの順序に関係なく失わない。保つのは Kotlin の設計書 8.4 と同じく通知の操作のイベントだけ |
| AP-22 | 予約の Alarm の種類（第 2 版） | **`alarm_type` は 0（`RTC_WAKEUP`）と 1（`RTC`）だけを受ける** | 予約の時刻は Unix ミリ秒で、2・3（`ELAPSED_REALTIME`）は起動からの時間なので食い違う |
| AP-23 | マニュアル（第 2 版） | **2b に入れない**。README の段階 4 で書く | README 5 章の段の分け方。第 1 版の TB-12（マニュアル）を外し、TB-12 は文書の直しのタスクにした |

### 0.1 第 2 版での反映（v1 のレビュー）

1 回目のレビュー（Claude と Codex）の区分 A は 6 件で、どれも Kotlin の実際の振る舞いとの食い違いか、第 1 部との食い違いだった。反映先は `reviews/...-part2-review-v1.md` の表にある。

| # | 指摘 | 反映 |
|---|---|---|
| W-X1、W-C1 | Share の要求の ID を Kotlin の印にすると、関数が戻る時点で ID が無い | AP-17 |
| W-X2、W-X3、W-C2 | `PERMISSION_DENIED` と `EXACT_ALARM_NOT_ALLOWED` は Kotlin からは起きない（黙って成功、黙って不正確な Alarm） | AP-16 |
| W-X4 | Progress の更新・完了・停止の `startService` の制限と、サービスの `SecurityException` の写しが無い | AP-14、11.2 |
| W-C3 | ブリッジは本文のタップと dismiss の Intent を必ず付けていたが、C ABI は既定で付けない | AP-18 |

### 0.2 第 3 版での反映（v2 のレビュー）

2 回目の区分 A は 4 件で、どれも第 2 版で足した文の範囲だった。

| # | 指摘 | 反映 |
|---|---|---|
| Y-X1 | AP-16 は確かめと Kotlin の呼び出しの間の変化を守れない | AP-16 を「呼び出し時点の最善の努力」とし、限りを契約に書いた |
| Y-X2 | AP-21 の付け外しは、コールバックの中で外して足し直すと保持のイベントを失う | AP-21 を「受け口が保つ」形に直した |
| Y-X3、Y-C2 | 12.1 の入口で拒んだときのテストが「完了と `release`」になっていた | 「完了を呼ばず、`release` だけ」に直した |
| Y-C1 | AP-8 が layout と view の ID も drawable・mipmap で引くと読める | 名前を引く型は関数で決まる、に直した |

区分 B は、過ぎた時刻の予約（AP-16 に入れた）、AP-17 の取り消しの経路（main に積む）、Progress のサービスの中の失敗が C に届かないこと（6.3、11.2。1 回目の W-X4 で足した `SecurityException` の写しを直した）、importance 5 を受けないこと（6.3）、入口と完了の両方から来る `EMPTY_CONTENT` と Chooser Action のアイコン（AP-19）、11.5 を表にしたこと。細目は `reviews/...-part2-review-v2.md`。

### 0.3 利用者の決定（2026-10-05）

| 決定 | 反映 |
|---|---|
| 2a の照合のスクリプトは、1 つのファイルを設定で切り替えるのではなく、**共通の部分を 1 つのモジュールにし、OS ごとの照合を OS ごとのファイルに分ける**。共通: 設計書の表と付録 A の読み取り、C の宣言の解析、報告、OS に依らない照合（関数・8.2・付録 A、エラーの値、名前、ASCII）、2 つの OS の `Common.h` の照合。Windows だけ: `.def`、C++ の API との写し。Android だけ: Kotlin の Manager との照合、10 章、ビルドの後の `llvm-nm`。理由は、OS だけの照合が重ならないこと、Windows のファイルにほとんど手を入れずに「今と同じ結果」を守れること、リポジトリの名前の付け方（`check_windows_dist.py`、`test_android.sh`）と同じこと。解析を OS ごとに写さないのは、片方だけ直してずれるのを避け、`Common.h` を同じ解析器で読むため。TA-2 も同じ形にする | 12.3、13 章の TA-1・TA-2 |

### 0.4 2a の実装レビューを受けた直し（2026-10-05）

2a の照合を強めたところ（`reviews/2026-10-05-android-c-abi-stage2a-review-v1.md`）、10 章の BH-45（Share の選択の待ちを取り消す）が「同期の結果」のままで、第 3 版の AP-17（取り消しは main に積む）と 9 章の OP-51 に合っていなかった。「受け付けだけ（main に積む）」に直した。あわせて、12.1 に system_code と構造体の配置の行を、12.3 に照合の流し方を足し、TB-1・TB-10・TB-11 の中身と完了の条件に照合の流し方を書いた。

## 1. 設計目的

- 第 1 部の約束（スレッド、寿命、初期化、`release`、前面）の上に、**公開する C の関数・型・エラーの値をすべて決める**
- README 6 章の振る舞いの集合（操作 45、完了、自発のイベント、登録と解除、通知の権限の要求）を、C の関数の集合として閉じる（10 章）
- 今のブリッジの 69 メソッドとの対応を、Unity の包み（2c）が使える形で示す（8.3）
- 2a の機械照合と 2b の実装が、この設計書だけを入力にできるようにする

## 2. スコープ

### 2.1 In scope

- `Common.h`（Windows と共通）、`Android.h`（第 1 部で決めたもの）、`Clipboard.h`、`Dialog.h`、`Notification.h`、`Share.h` の全宣言（付録 A）
- 受け口（`com.jonghyunkim.nativetoolkit.capi.jni`）の機能ごとの役割と、Kotlin の Manager の呼び方（5 章）
- 8.3 の対応表と、`unity-native-plugin` に渡す範囲（16 章）

### 2.2 Out of scope

- 第 1 部で決めたもの（初期化の状態の表、`release` の状態機械、JNI の作法、文字列の変換、ビルドと R8）。変えない
- `android_library` にあるがブリッジが公開していない機能（CallStyle、Media の style、`getActive`、`createChannels`、`restoreScheduled`。README D-5）
- iOS と macOS の C ABI

## 3. 前提

### 3.1 企画書と第 1 部から

| 前提 | 出典 |
|---|---|
| C ABI の範囲は、今のブリッジの振る舞いの集合と通知の権限の要求 | README D-5、6 章 |
| すべての関数はどのスレッドからでも呼べ、main を待たない。main で動かす処理は main から呼ばれても積む | 第 1 部 1.3、AC-5 |
| 完了・イベント・受け付けた後の `release` は main で呼ぶ。入口で拒んだときは完了を呼ばず、`release` を呼び出しスレッドで呼ぶ | 第 1 部 1.3、AC-4 |
| 受け付けた完了つきの操作は、ちょうど 1 回完了する | 第 1 部 1.3、K-3 |
| コールバックの引数は値か、所有権ごと渡すハンドル。戻り値は `void` | 第 1 部 AC-18 |
| 未初期化では、すべての操作が `NOT_INITIALIZED` を返す。読み取りと `_free` とビルダーは初期化に関係なく動く | 第 1 部 AC-3 |
| 前面が要る操作の `NOT_FOREGROUND` は完了で返す | 第 1 部 AC-15、5.8 |
| Share の選ばれたアプリはイベントで、要求の ID が付く。選択の待ちの取り消しは要求の ID で行う | 第 1 部 AC-22 |
| 今のブリッジを写さず、違いは対応表に書く | 第 1 部 AC-23 |
| `ntk_last_system_code` と完了の `system_code` は常に 0 | 第 1 部 AC-10 |
| 文字列は厳密な UTF-8 で受け、出力は U+FFFD に置き換える | 第 1 部 5.10、AC-19 |

### 3.2 不足前提

| ID | 不足している前提 | 扱い |
|---|---|---|
| G-4 | 通知の表示が権限の無いとき、予約が正確なアラームを使えないときに Kotlin が何を返すか | **解決（第 2 版）**: Kotlin はどちらも黙って成功にする（表示しない、不正確な Alarm に下げる）。受け口が事前に確かめる（AP-16） |
| G-5 | 過ぎた時刻の予約の振る舞い（すぐ出すか、失敗か）は、Kotlin の設計書 8.6 の対応表の「過ぎた時刻」の行に従う | C ABI は Kotlin の結果をそのまま写す |

## 4. 実装方針の適用

### 4.1 common.md

| 方針 | 適合 | 内容 |
|---|---|---|
| 機能の公開の入口 | 適合 | 受け口は `Android*Manager` だけを呼ぶ（AP-1） |
| システム API に合わせた同期・非同期 | 適合 | AP-2 |
| 層と依存の向き | 適合 | `android_library_capi` → `android_library` の一方向（第 1 部 5.1）。受け口は Manager と、Manager が公開する型（モデル、`NotificationEventIntents`、`NotificationResourceResolver`、`LibraryRuntime`、`ForegroundActivityTracker`）だけを使う |
| 検査の書き方 | 適合 | 12 章。足した検査は壊すと落ちることを確かめる |

### 4.2 android.md

| 方針 | 適合 | 内容 |
|---|---|---|
| ログ（先頭の `Log.d`、秘密の値を伏せる） | 適合 | 受け口の Kotlin の関数は先頭で `Log.d` を出す。Clipboard の本文、Dialog の入力、Share の本文、通知の `data` の値は長さかキーだけ。C のログは第 1 部 5.12 |
| Manager の役 | 適合 | 受け口は Manager を呼ぶだけで、Manager に C 向けの口を足さない |
| KDoc | 適合 | 受け口の公開の関数（`capi.jni` の中の JNI から引くもの）に KDoc を書く |

## 5. 実装アーキテクチャ

### 5.1 受け口（`capi.jni`）

| クラス | 役 | 呼ぶ Manager |
|---|---|---|
| `ClipboardBridge` | Clipboard の同期の操作を呼び出しスレッドで行い、監視の開始・停止とイベントの登録を main に積む | `AndroidClipboardManager` |
| `DialogBridge` | 要求を main に積み、前面を判定して `show(request, onResult)` を呼ぶ。取り消し | `AndroidDialogManager` |
| `NotificationBridge` | 同期の操作、設定の画面と権限の要求（main に積む）、イベントの登録 | `AndroidNotificationManager`、`NotificationEventIntents`、`NotificationResourceResolver` |
| `ShareBridge` | Share を開く操作（main に積み、前面を判定）、Direct Share（同期）、選択の待ちの取り消し、イベントの登録 | `AndroidShareManager` |
| `Ledger` | 帳簿（ID → 登録）。第 1 部 5.7 の main の上の出来事 | - |
| `Foreground` | 前面の判定（`ForegroundActivityTracker.current()`） | - |
| `Utf8` | 第 1 部 5.10 の変換 | - |

- 受け口のメソッドは `@JvmStatic`、`internal` にしない、例外を外へ出さない（第 1 部 AC-20、C-1）
- 同期の操作の受け口は、Kotlin の例外を捕まえて機能のエラーの値（11 章の写しの表）にして返す。C は戻り値の整数を機能のエラーとして返す
- 非同期の操作の受け口は、「挿入と操作の開始」を 1 つの Runnable にして main に `post` し、`post` したかを返す（第 1 部 5.7）

### 5.2 同期の操作の流れ

```
C の入口（検査、UTF-8、struct_size、初期化の確認）
  → JNI で受け口の static メソッド（Kotlin の値に変える）
  → Android*Manager の口（呼び出しスレッドで）
  → 戻り値か例外 → 機能のエラーの値（11 章）→ C の戻り値
```

- 出力のハンドル（`ntk_clipboard_content` など）は、受け口が返した Kotlin の値（UTF-8 の `ByteArray` の配列など）から C のヒープに写す。JNI の参照を持たない（第 1 部 5.7）

### 5.3 非同期の操作の流れ

```
C の入口（検査、登録を ACTIVE で作る、ID を付ける）
  → 受け口が「挿入と開始」を main に post（第 1 部 5.7）
  → main: 帳簿に入れる → 前面の判定（要る操作だけ）→ Manager の口（onResult 付き）
  → Manager の onResult（main）→ 完了（第 1 部 5.7 の「完了」の行）→ TryRelease
```

- 前面の判定は、Dialog・権限の要求（未許可のとき）・設定の画面・Share を開く操作だけで行う（第 1 部 5.8、AP-14）
- Dialog・権限の要求・Share の選択の待ちは、Kotlin の ID（Dialog と権限は Manager が返す要求の ID、Share は `shareForSelection` が返す印）と C の要求の ID（受け付けの時点で C が付ける、使い回さない 64 ビット）を帳簿で対にする。Kotlin の ID は main で Manager を呼んだときにできる。取り消しは必ず main に積み、main で帳簿を引く（main は積んだ順に処理するので、開く処理が常に先に動く。AP-17）
- 同期の操作の前の確かめ（AP-16）は、受け口が Manager を呼ぶ前に呼び出しスレッドで行う

### 5.4 イベントの流れ

- `_add_*_listener` は登録を作り、受け口が main で帳簿に入れる。その種類の最初の C の登録のときだけ `EventHub.addListener` を呼び、以後は外さない（AP-21）。通知の操作のイベントは、`ACTIVE` な登録が無い間は受け口が 32 件まで保ち、次の登録の挿入のメッセージの中で配る（第 1 部 5.7、K-7）
- 1 つの `EventHub` の受け手が、帳簿のその種類の登録すべてに配る（同じ種類に複数の登録を許す。AC-21）
- `_listener_remove(NULL)` は何もしない（`_free(NULL)` と同じ）
- 配送の直前に状態を確かめ、`ACTIVE` の登録だけに呼ぶ（第 1 部 5.7）

## 6. サブ機能別詳細設計

### 6.1 Clipboard（`Clipboard.h`）

| 操作 | 形 | 中身 |
|---|---|---|
| 書き込み 4 つ（`copy_text`、`copy_html`、`copy_uri`、`copy_texts`） | 同期 | `options` は `NULL` で既定（ラベル無し、秘密でない）。`copy_texts` は 0 個で `EMPTY_ITEMS`（Kotlin の `EmptyItemList`）。`copy_html` の `plain_text` の `NULL` は `""` |
| `clear` | 同期 | |
| `read` | 同期。`ntk_clipboard_content` を出力する | クリップが空、または入力のフォーカスが無いときは `NONE` で出力を `NULL` にする（区別できない。第 1 部 5.8） |
| `has_clip` | 同期。`int32_t` を出力する | 失敗は戻り値で返す（今のブリッジは失敗を偽にした。AC-23） |
| `get_description` | 同期。`ntk_clipboard_description` を出力する | 空なら `NULL` |
| `start_observing`、`stop_observing` | main に積む。完了は無い。**戻り値は main への受け付けを表し、監視が始まったことは表さない** | 冪等。`ClipboardManager` が取れないときは監視が始まらず、logcat に出るだけ。監視が止まっている間、変更のイベントは来ない。フォーカスが無い間の変更は届かない（第 1 部 5.8） |
| `add_change_listener`、`listener_remove` | 第 1 部 5.7 | 登録しただけでは監視は始まらない（`start_observing` が要る） |

### 6.2 Dialog（`Dialog.h`）

| 操作 | 形 | 中身 |
|---|---|---|
| 6 種の `ntk_dialog_show_*_async` | 非同期。出力に要求の ID | 前面が要る。`FragmentActivity` でなければ透明な宿主に出る（Kotlin の設計書 8.3） |
| `ntk_dialog_cancel` | どのスレッドからでも。待たない | 完了の後と知らない ID は何もしない。取り消した要求は `CANCELED` で完了する |

**結果**（`ntk_dialog_result`。`error == NONE` のときだけ渡す。利用者が `ntk_dialog_result_free` で解放する）:

| 種類 | 読める値 |
|---|---|
| `NTK_DIALOG_ANSWER_BUTTON` | 押したボタン（`POSITIVE` / `NEGATIVE`）と文言。Dialog の種類ごとの値（単一選択の添字。選ばれていなければ -1、複数選択の真偽の並び、入力の文字列、ユーザー名とパスワード） |
| `NTK_DIALOG_ANSWER_DISMISSED` | 値は無い（AP-13） |

**要求の構造体の既定値**: 0 で埋めた構造体が Kotlin の既定値になるように、真が既定の項目は名前を反転する（E-9）。`not_cancelable`（既定は戻るで閉じられる）、`not_cancelable_on_touch_outside`。ボタンと入力欄のヒントの文言の `NULL` は Kotlin の既定の文言（`"OK"`、`"Yes"`、`"No"`、`"Cancel"`、`"Username"`、`"Password"`、`"Login"`）。`title`、`message`、`hint`（入力）の `NULL` は `""`（Windows の E-15 と同じ）。

### 6.3 Notification（`Notification.h`）

**内容のビルダー**（`ntk_notification_content`）: `_create(id, title, message, &out)` で必須の 3 つを受け（`title` と `message` の `NULL` は `""`）、ほかは Kotlin の既定値と AP-18 のタップと dismiss で始まる。`_set_*` で上書きする。スレッドセーフでない（第 1 部 1.3.1）。初期化に関係なく使える。**setter は、受け取った文字列・配列・チャンネルのビルダーを、呼び出しの中で深く写す**（setter が戻った後、利用者は元の引数を壊してよい。チャンネルのビルダーを後で変えても、写した内容は変わらない）。setter の文字列の `NULL` は「その項目を設定しない（既定値に戻す）」。

| 群 | 関数 | Kotlin の項目 |
|---|---|---|
| 基本 | `_set_tag`、`_set_channel`、`_set_sub_text`、`_set_ticker`、`_set_category`、`_set_sort_key`、`_set_sound` | `tag`、`channel`、`subText`、`ticker`、`category`、`sortKey`、`soundUri` |
| アイコン | `_set_small_icon(name)`、`_set_large_icon(name)` | `smallIconResId`（名前を `NotificationResourceResolver` で引く。設定しなければ `defaultSmallIcon()`）、`largeIconResId`。バイト列の大きいアイコンは出さない（AP-20） |
| 数値 | `_set_priority`、`_set_visibility`、`_set_color`、`_set_number`、`_set_group_alert_behavior`、`_set_timestamp`、`_set_timeout_after` | `priority`、`visibility`、`color`、`number`、`groupAlertBehavior`、`timestampMillis`、`timeoutAfterMillis` |
| 真偽 | `_set_auto_cancel`、`_set_ongoing`、`_set_show_timestamp`、`_set_group_summary`、`_set_only_alert_once`、`_set_local_only`、`_set_silent`、`_set_uses_chronometer` | `autoCancel`、`ongoing`、`showTimestamp`、`isGroupSummary`、`onlyAlertOnce`、`localOnly`、`silent`、`usesChronometer` |
| まとまり | `_set_group(key)` | `groupKey` |
| 進み具合 | `_set_progress(max, current, indeterminate)` | `progress` |
| style | `_set_style_big_text`、`_set_style_inbox`、`_set_style_big_picture`、`_set_style_messaging` と `_add_message`、`_set_style_custom_view` と `_add_view_click` | `NotificationStyle` の 6 種（Default、BigText、Inbox、BigPicture、Messaging、DecoratedCustomView）。最後に設定した style が勝つ。`_add_message` と `_add_view_click` は、対応する style が設定されていないと `INVALID_PARAMETER`。`big_text` と `user_display_name` の `NULL` は `INVALID_PARAMETER`（Kotlin で必須）。BigPicture は `picture_name` と `picture_uri` のどちらかが要る（両方 `NULL` は `INVALID_PARAMETER`。両方あれば名前が勝つ） |
| イベント | `_set_tap(mode)`、`_add_data(key, value)`、`_set_dismiss_event(enabled)`、`_set_full_screen(enabled)`、`_add_action(action)` | 受け口が `NotificationEventIntents.bodyTap` / `dismiss` / `fullScreenLaunch` / `action` で要求を作り、`AndroidNotificationPlatformOptions` に入れる。`data` は本文のタップ・アクション・dismiss に同じものを付ける |

- 範囲の検査は入口で行う（AP-8）: `priority` は -2〜2、`visibility` は -1〜1、`group_alert_behavior` は 0〜2、`timeout_after` と `timestamp` は 0 以上、`progress` は `0 <= current <= max`（`indeterminate` のときは問わない）
- 名前（アイコン、BigPicture の画像、layout、view の ID）は、表示する時点で受け口が引く（型は AP-8）。引けなければ `RESOURCE_NOT_FOUND`
- `_add_data` の `data` は、本文のタップ・アクション・dismiss に加えて、カスタムビューのクリック（`_add_view_click`）にも付ける（今のブリッジと同じ）
- 本文のタップ（AP-18）: 既定は `NTK_NOTIFICATION_TAP_OPEN_APP`（見えない Activity を通してアプリを開き、タップのイベントを出す。Kotlin の設計書 8.5）。`NTK_NOTIFICATION_TAP_EVENT_ONLY` はアプリを開かずにイベントだけ、`NTK_NOTIFICATION_TAP_NONE` は何も付けない
- dismiss のイベント: 既定は付ける。`_set_dismiss_event(content, 0)` で外す
- 全画面: アプリの起動の Intent（ランチャーの Activity）が無いときは付けない（`fullScreenLaunch` が `null`）

**チャンネルのビルダー**（`ntk_notification_channel`）: `_create(id, name, importance, &out)`。`importance` は 0〜4（Kotlin は 5（`IMPORTANCE_MAX`）を黙って 3 に変えるので、受けない。AP-8）、`lockscreen_visibility` は -1〜1、`light_color` を設定しなければ既定の色。

**予約**（`ntk_notification_schedule_options` の構造体）: `trigger_at_millis`（1 以上。Unix ミリ秒）、`inexact`（既定は正確）、`not_allow_while_idle`、`not_persist_across_boot`、`alarm_type`（0 か 1。AP-22）。0 で埋めれば Kotlin の既定値（正確、Doze 中も、再起動の後も戻す、`RTC_WAKEUP`）になる（E-9）。

| 操作 | 形 | 中身 |
|---|---|---|
| `show`、`update`、`remove`、`remove_all`、`create_channel`、`delete_channel`、`schedule`、`cancel_scheduled`、`cancel_all_scheduled` | 同期 | `show` と `update` は先に権限を確かめる（AP-16）。`schedule` は、未来の時刻の正確な予約なら正確なアラームの許可を、過ぎた時刻の予約なら通知の権限を先に確かめる（AP-16）。Kotlin の `Result` の失敗を 11.2 の値に写す。`schedule` は呼び出しスレッドでファイルを書く（main から呼ぶと main でディスクに触る。マニュアルに書く） |
| `start_progress`、`update_progress`、`complete_progress`、`stop_progress` | 同期 | AP-9 の補正。後ろからの開始・更新・完了・停止を OS が止めたら `SERVICE_START_NOT_ALLOWED`（AP-14）。権限は確かめない（前景サービスの通知は、通知の権限が無くても動く）。**戻り値はサービスに頼んだことまでを表す**: サービスの中の失敗（前景サービスの種類の権限が無いときの `startForeground` の `SecurityException`、完了の通知の表示の失敗、権限が無いときに完了の通知が出ないこと）は C には届かない（`ProgressForegroundService` が `startForeground` と更新を `runCatching` で包んで logcat に出し、完了の通知の `show` の `Result` は見ていないので何も出ないこともある） |
| `has_permission`、`are_enabled`、`is_scheduled`、`can_schedule_exact_alarms` | 同期。`int32_t` を出力する | `is_scheduled` は 1.x と同じく保存した予約だけを見る（`not_persist_across_boot` の予約は偽。Kotlin の設計書 3.3 の直さない不具合。8.3） |
| `open_settings_async(target, ...)` | 非同期 | 前面の Activity から開く（第 1 部 5.8）。結果は `OPENED` / `OPENED_FALLBACK`。開けなければ `SETTINGS_NOT_OPENED` |
| `request_permission(...)` | 非同期。出力に要求の ID | 第 1 部 5.8 の行。結果は `GRANTED` / `DENIED`。取り消し・宿主の破棄は `CANCELED` / `CANCELED_BY_SYSTEM` |
| `cancel_permission_request(id)` | どのスレッドからでも | Dialog の取り消しと同じ規則 |
| `add_interaction_listener`、`add_shown_listener`、`listener_remove` | 第 1 部 5.7 | 本文のタップ・アクション・dismiss は受け手が無い間 32 件まで保ち、最初の登録に渡す（Kotlin の設計書 8.4）。shown は保たない |

**イベントの値**（所有権ごと渡すハンドル。利用者が `_free` する）:

| ハンドル | 読める値 |
|---|---|
| `ntk_notification_interaction` | 種類（`BODY_TAP` / `ACTION` / `DISMISS`）、通知の ID、tag（無ければ `NULL`）、アクションの ID（`ACTION` のとき）、`data` の鍵と値の組 |
| `ntk_notification_shown` | 通知の ID、tag、チャンネルの ID |

### 6.4 Share（`Share.h`）

| 操作 | 形 | 中身 |
|---|---|---|
| `ntk_share_text(content, actions, action_count, ...)` | 非同期 | 前面が要る。いつも `shareTextWithActions` を呼ぶ（AP-7）。API 33 以下ではアクションを付けない（今と同じ） |
| `ntk_share_image`、`_images`、`_file`、`_files` | 非同期 | 前面が要る |
| `ntk_share_text_for_selection(content, ..., &out_request_id)` | 非同期。出力に要求の ID（C が付ける。AP-17。`NULL` を渡してよいが、渡すと選択のイベントと対応付けられない） | 前面が要る。開けたら完了。選ばれたアプリは選択のイベントで、要求の ID が付く（AC-22）。前面でなくて開かなかったときは、前の要求の待ちを消さない |
| `ntk_share_cancel_selection(request_id)` | どのスレッドからでも | その要求の選択の待ちを取り消す（第 1 部 1.3.1 の例外） |
| `ntk_share_register_direct_target`、`ntk_share_remove_direct_targets` | 同期 | 前面は要らない |
| `add_chooser_action_listener`、`add_selection_listener`、`listener_remove` | 第 1 部 5.7 | どちらも保たない |

- 完了の結果は「開けた（`NONE`）／`NOT_FOREGROUND`／失敗の値」まで（AC-22）。Chooser を閉じたときと、選ばれなかったときは何も来ない
- Chooser Action の組（`ntk_share_chooser_action`）は `id`、`label`、アイコンのバイト列（PNG などの画像）。空の ID と重複した ID は入口で `INVALID_CHOOSER_ACTION` を返し（AP-19）、読めないアイコンは `INVALID_CHOOSER_ACTION` で完了する。どちらも前の Share のアクションは生きたまま（Kotlin の設計書 8.9）。`label` の `NULL` は `""`、`icon` が `NULL` か大きさ 0 は `INVALID_CHOOSER_ACTION`
- Direct Share の共有先の `label` と `id` の `NULL` は `INVALID_PARAMETER`、`icon` が `NULL` か大きさ 0 は `INVALID_ICON`
- Share には `CANCELED` が無い。開く操作は Chooser が開いた時点で完了し、取り消しの口を持たないため（選択の待ちの取り消しは OP-51 で、完了とは別。AC-22）。`ntk_share_done_fn` は要求の ID を持たない（対応付けは `user_data`。選択の待ちの ID は `out_request_id`）

### 6.5 初期化（`Android.h`）

第 1 部 1.4 と 5.3 のとおり（`ntk_android_init`、`ntk_android_is_initialized`）。この設計書では変えない。

## 7. 変える文書

2026-10-05 に TB-12 として直した（2b の前。Kotlin の設計書 0.9、第 1 部 0.6、README 6 章）。

| 文書 | 変えること |
|---|---|
| Kotlin の設計書 5.1 の C1 と「共通」の行、7 章の「Clipboard と Share の操作を main で動かす」の行 | Clipboard の読み書きは同期にした（AP-3）と書き足す |
| Kotlin の設計書 7 章と 8.15 の、C ABI 側の写しの行 | `HOST_START_FAILED` と `SHOW_FAILED` は `UNKNOWN` ではなく別の値に、`CancelReason` は `CANCELED` と `CANCELED_BY_SYSTEM` に分けて写す（11.1）。style の代わりの値と `Dismissed` の今の値への写しは、C ABI ではなく Unity の包みが持つ（AP-8、AP-13、16 章）。Share の要求の ID は C が付ける（AP-17） |
| 第 1 部 5.8 の表 | Progress の前景サービスの行を足す（AP-14） |
| 第 1 部 5.11 | 「通知は `PERMISSION_DENIED`」が受け口の事前の確かめで出る値であることを書き足す（AP-16） |
| README 6 章 | 振る舞いの集合に ID を付けた表を、この設計書の 10 章へ指す |

## 8. API 設計

### 8.1 OP ごとの C 関数

戻り値の型は機能のエラー（`ntk_clipboard_error` / `ntk_dialog_error` / `ntk_notification_error` / `ntk_share_error` / `ntk_android_error`）。`_listener_remove` は `void`。完全な宣言は付録 A。「Kotlin の口」は受け口が呼ぶ Manager の口（AP-1）。

| OP | Kotlin の口 | C 関数 | 変換 |
|---|---|---|---|
| OP-01 | `AndroidClipboardManager.copyPlainText` | `ntk_clipboard_copy_text(text, options)` | 構造体（`NULL` 可）→ `ClipContent.PlainText` |
| OP-02 | `AndroidClipboardManager.copyHtmlText` | `ntk_clipboard_copy_html(html, plain_text, options)` | → `ClipContent.HtmlText` |
| OP-03 | `AndroidClipboardManager.copyUri` | `ntk_clipboard_copy_uri(uri, options)` | → `ClipContent.UriContent` |
| OP-04 | `AndroidClipboardManager.copyMultipleText` | `ntk_clipboard_copy_texts(texts, count, options)` | 配列 → `ClipContent.MultipleText` |
| OP-05 | `AndroidClipboardManager.clear` | `ntk_clipboard_clear()` | - |
| OP-06 | `AndroidClipboardManager.read` | `ntk_clipboard_read(out_content)` | `ClipReadResult` → ハンドル。`null` は出力 `NULL` |
| OP-07 | `AndroidClipboardManager.hasClip` | `ntk_clipboard_has_clip(out_has_clip)` | - |
| OP-08 | `AndroidClipboardManager.getDescription` | `ntk_clipboard_get_description(out_description)` | `ClipDescriptionInfo` → ハンドル |
| OP-09 | `AndroidClipboardManager.startObserving` | `ntk_clipboard_start_observing()` | main に積む |
| OP-10 | `AndroidClipboardManager.stopObserving` | `ntk_clipboard_stop_observing()` | main に積む |
| OP-11 | `AndroidClipboardManager.changes` | `ntk_clipboard_add_change_listener(callback, user_data, release, out_listener)` | `EventHub.addListener`（main） |
| OP-12 | `EventHub.Registration.remove` | `ntk_clipboard_listener_remove(listener)` | 第 1 部 5.7 の解除 |
| OP-13 | `AndroidDialogManager.show` | `ntk_dialog_show_alert_async(request, callback, user_data, release, out_request_id)` | 構造体 → `DialogRequest.Alert`。`DialogResult` → `ntk_dialog_result` |
| OP-14 | `AndroidDialogManager.show` | `ntk_dialog_show_confirm_async(...)` | → `DialogRequest.Confirm` |
| OP-15 | `AndroidDialogManager.show` | `ntk_dialog_show_single_choice_async(...)` | → `DialogRequest.SingleChoice`。添字 -1 は `null` |
| OP-16 | `AndroidDialogManager.show` | `ntk_dialog_show_multi_choice_async(...)` | → `DialogRequest.MultiChoice` |
| OP-17 | `AndroidDialogManager.show` | `ntk_dialog_show_text_input_async(...)` | → `DialogRequest.TextInput` |
| OP-18 | `AndroidDialogManager.show` | `ntk_dialog_show_login_async(...)` | → `DialogRequest.Login` |
| OP-19 | `AndroidDialogManager.cancel` | `ntk_dialog_cancel(request_id)` | C の ID → Kotlin の ID（帳簿） |
| OP-20 | `AndroidNotificationManager.show` | `ntk_notification_show(content)` | ビルダー → `AndroidNotificationCommand`。先に権限を確かめる（AP-16） |
| OP-21 | `AndroidNotificationManager.update` | `ntk_notification_update(content)` | 同上 |
| OP-22 | `AndroidNotificationManager.cancel` | `ntk_notification_remove(id, tag)` | `NULL` の tag は `null` |
| OP-23 | `AndroidNotificationManager.cancelAll` | `ntk_notification_remove_all()` | - |
| OP-24 | `AndroidNotificationManager.createChannel` | `ntk_notification_create_channel(channel)` | ビルダー → `NotificationChannel` |
| OP-25 | `AndroidNotificationManager.deleteChannel` | `ntk_notification_delete_channel(channel_id)` | - |
| OP-26 | `AndroidNotificationManager.schedule` | `ntk_notification_schedule(content, schedule)` | 構造体 → `NotificationSchedule`。未来の時刻の正確な予約は正確なアラームの許可を、過ぎた時刻の予約は通知の権限を先に確かめる（AP-16） |
| OP-27 | `AndroidNotificationManager.cancelScheduled` | `ntk_notification_cancel_scheduled(id, tag)` | - |
| OP-28 | `AndroidNotificationManager.cancelAllScheduled` | `ntk_notification_cancel_all_scheduled()` | - |
| OP-29 | `AndroidNotificationManager.startProgress` | `ntk_notification_start_progress(content)` | AP-9 の補正 |
| OP-30 | `AndroidNotificationManager.updateProgress` | `ntk_notification_update_progress(content)` | AP-9 の補正 |
| OP-31 | `AndroidNotificationManager.completeProgress` | `ntk_notification_complete_progress(content)` | AP-9 の補正 |
| OP-32 | `AndroidNotificationManager.stopProgress` | `ntk_notification_stop_progress()` | - |
| OP-33 | `AndroidNotificationManager.hasPermission` | `ntk_notification_has_permission(out_value)` | - |
| OP-34 | `AndroidNotificationManager.areNotificationsEnabled` | `ntk_notification_are_enabled(out_value)` | - |
| OP-35 | `AndroidNotificationManager.isScheduled` | `ntk_notification_is_scheduled(id, tag, out_value)` | - |
| OP-36 | `AndroidNotificationManager.canScheduleExactAlarms` | `ntk_notification_can_schedule_exact_alarms(out_value)` | - |
| OP-37 | `AndroidNotificationManager.openSettings` | `ntk_notification_open_settings_async(target, callback, user_data, release)` | 列挙 → `NotificationSettingsTarget`。`from` に前面の Activity |
| OP-38 | `AndroidNotificationManager.requestPermission` | `ntk_notification_request_permission(callback, user_data, release, out_request_id)` | `PermissionRequestResult` → 結果とエラー |
| OP-39 | `AndroidNotificationManager.cancelPermissionRequest` | `ntk_notification_cancel_permission_request(request_id)` | C の ID → Kotlin の ID |
| OP-40 | `AndroidNotificationManager.interactions` | `ntk_notification_add_interaction_listener(callback, user_data, release, out_listener)` | `NotificationInteraction` → ハンドル |
| OP-41 | `AndroidNotificationManager.shown` | `ntk_notification_add_shown_listener(callback, user_data, release, out_listener)` | `NotificationShown` → ハンドル |
| OP-42 | `EventHub.Registration.remove` | `ntk_notification_listener_remove(listener)` | - |
| OP-43 | `AndroidShareManager.shareTextWithActions` | `ntk_share_text(content, actions, action_count, callback, user_data, release)` | 構造体 → `ShareContent` と `SharePreviewOptions`。組 → `ShareChooserAction`（AP-7） |
| OP-44 | `AndroidShareManager.shareImage` | `ntk_share_image(path, mime_type, callback, user_data, release)` | `NULL` の mime は `"image/*"` |
| OP-45 | `AndroidShareManager.shareImages` | `ntk_share_images(paths, count, callback, user_data, release)` | - |
| OP-46 | `AndroidShareManager.shareFile` | `ntk_share_file(path, callback, user_data, release)` | - |
| OP-47 | `AndroidShareManager.shareFiles` | `ntk_share_files(paths, count, callback, user_data, release)` | - |
| OP-48 | `AndroidShareManager.registerDirectShareTarget` | `ntk_share_register_direct_target(target)` | 構造体 → `DirectShareTarget` とアイコンのバイト列 |
| OP-49 | `AndroidShareManager.removeDirectShareTargets` | `ntk_share_remove_direct_targets(ids, count)` | - |
| OP-50 | `AndroidShareManager.shareForSelection` | `ntk_share_text_for_selection(content, callback, user_data, release, out_request_id)` | C が付けた ID と Kotlin の印を帳簿で対にする（AP-17） |
| OP-51 | `AndroidShareManager.cancelShareSelection` | `ntk_share_cancel_selection(request_id)` | - |
| OP-52 | `AndroidShareManager.chooserActions` | `ntk_share_add_chooser_action_listener(callback, user_data, release, out_listener)` | ID → `ntk_string` |
| OP-53 | `AndroidShareManager.selections` | `ntk_share_add_selection_listener(callback, user_data, release, out_listener)` | `ShareSelection` → 要求の ID と `ntk_string` |
| OP-54 | `EventHub.Registration.remove` | `ntk_share_listener_remove(listener)` | - |
| OP-55 | `LibraryRuntime.ensureInitialized` | `ntk_android_init(env, context)` | 第 1 部 5.3 |
| OP-56 | - | `ntk_android_is_initialized()`（戻り値 `int32_t`） | 第 1 部 5.3 |

### 8.2 公開する関数の全体（155）

8.1 の 56 操作のほかに、出力のハンドルの読み取りと解放、ビルダーの関数を公開する。**ヘッダー、付録 A、ビルドの後の公開シンボル（`llvm-nm -D --defined-only` の `ntk_*`）はこの表と一致させる**。群の関数は、`_` で始まる末尾を「〜の後に続く」の名前に付けて読む（AP-15）。

| ヘッダー | 群 | 関数 | 数 |
|---|---|---|---|
| `Common.h` | 版とエラー | `ntk_version`、`ntk_last_system_code` | 2 |
| `Common.h` | `ntk_string` | `ntk_string_data`、`ntk_string_size`、`ntk_string_free` | 3 |
| `Common.h` | `ntk_bytes` | `ntk_bytes_data`、`ntk_bytes_size`、`ntk_bytes_free` | 3 |
| `Common.h` | `ntk_string_list` | `ntk_string_list_count`、`ntk_string_list_at`、`ntk_string_list_free` | 3 |
| `Android.h` | 初期化（OP-55、OP-56） | `ntk_android_init`、`ntk_android_is_initialized` | 2 |
| `Clipboard.h` | 操作（OP-01〜OP-12） | 8.1 の 12 関数 | 12 |
| `Clipboard.h` | 読み取りの結果（OP-06 の出力） | `_label`、`_mime_type_count`、`_mime_type_at`、`_item_count`、`_item_text_at`、`_item_html_at`、`_item_uri_at`、`_item_coerced_text_at`、`_free`（いずれも `ntk_clipboard_content` の後に続く） | 9 |
| `Clipboard.h` | 説明（OP-08 の出力） | `_label`、`_mime_type_count`、`_mime_type_at`、`_is_styled_text`、`_classification_status`、`_free`（いずれも `ntk_clipboard_description` の後に続く） | 6 |
| `Dialog.h` | 操作（OP-13〜OP-19） | 8.1 の 7 関数 | 7 |
| `Dialog.h` | 結果（完了の引数） | `_answer`、`_button`、`_button_text`、`_checked_index`、`_checked_count`、`_checked_at`、`_text`、`_username`、`_password`、`_free`（いずれも `ntk_dialog_result` の後に続く） | 10 |
| `Notification.h` | 操作（OP-20〜OP-42） | 8.1 の 23 関数 | 23 |
| `Notification.h` | 内容のビルダー | `_create`、`_free`、`_set_tag`、`_set_channel`、`_set_small_icon`、`_set_large_icon`、`_set_priority`、`_set_auto_cancel`、`_set_ongoing`、`_set_sub_text`、`_set_show_timestamp`、`_set_timestamp`、`_set_sound`、`_set_category`、`_set_visibility`、`_set_color`、`_set_number`、`_set_ticker`、`_set_group`、`_set_group_summary`、`_set_group_alert_behavior`、`_set_sort_key`、`_set_only_alert_once`、`_set_local_only`、`_set_silent`、`_set_uses_chronometer`、`_set_timeout_after`、`_set_progress`、`_set_style_big_text`、`_set_style_inbox`、`_set_style_big_picture`、`_set_style_messaging`、`_add_message`、`_set_style_custom_view`、`_add_view_click`、`_set_tap`、`_add_data`、`_set_dismiss_event`、`_set_full_screen`、`_add_action`（いずれも `ntk_notification_content` の後に続く） | 40 |
| `Notification.h` | チャンネルのビルダー | `_create`、`_free`、`_set_description`、`_set_show_badge`、`_set_enable_lights`、`_set_light_color`、`_set_enable_vibration`、`_set_vibration_pattern`、`_set_sound`、`_set_lockscreen_visibility`、`_set_group`（いずれも `ntk_notification_channel` の後に続く） | 11 |
| `Notification.h` | 操作のイベント（コールバックの引数） | `_kind`、`_notification_id`、`_tag`、`_action_id`、`_data_count`、`_data_key_at`、`_data_value_at`、`_free`（いずれも `ntk_notification_interaction` の後に続く） | 8 |
| `Notification.h` | 表示のイベント（コールバックの引数） | `_notification_id`、`_tag`、`_channel_id`、`_free`（いずれも `ntk_notification_shown` の後に続く） | 4 |
| `Share.h` | 操作（OP-43〜OP-54） | 8.1 の 12 関数 | 12 |
| 合計 | | | 155 |

### 8.3 今のブリッジの 69 メソッドとの対応表

AC-23 の列（ブリッジ／C ABI／違いと理由／Unity の包みが保つこと）。「包み」は 2c の `unity-native-plugin` の C# の層。

| # | ブリッジ | C ABI | 違いと理由 | Unity の包みが保つこと |
|---|---|---|---|---|
| CL-01 | `UnityAndroidClipboardManager.getInstance()` | （無い。関数を直接呼ぶ） | ハンドルの無い関数の集まり | - |
| CL-02 | `setClipboardOperationListener` | （無い） | 操作は同期の戻り値で結果を返す（AP-2） | 戻り値を見て、今の `onClipboardOperation(op, ok, msg)` を UnityMain で呼ぶ |
| CL-03 | `clearClipboardOperationListener` | （無い） | 同上 | 包みの中の受け手を外す |
| CL-04 | `setClipboardChangeListener` | OP-11 | 足す・外す形（AC-21）。登録しただけでは監視しない（今と同じ） | 1 つのハンドルを持ち、`set` は外してから足す（C-6） |
| CL-05 | `clearClipboardChangeListener` | OP-12 | 監視は止めない（AP-11） | 続けて OP-10 を呼ぶ |
| CL-06 | `copyPlainText(context, json)` | OP-01 | JSON をやめ、同期の戻り値（AP-2、AP-3）。今は main に積んで listener で返す | JSON を解いて呼ぶ。結果を listener で返す |
| CL-07 | `copyHtmlText` | OP-02 | 同上 | 同上 |
| CL-08 | `copyUri` | OP-03 | 同上 | 同上 |
| CL-09 | `copyMultipleText` | OP-04 | 同上。0 個は `EMPTY_ITEMS` | 同上 |
| CL-10 | `read(context): String` | OP-06 | JSON の文字列ではなくハンドル。空は出力 `NULL`。失敗は戻り値のエラー（今は `{error, message}` の JSON で、`INVALID_URI` と `SECURITY` の `message` には例外の中身が入っていた） | ハンドルから今の JSON を組む。エラーは今の `{error, message}` にする（`message` の文言は包みが持つ。例外の中身は C ABI から来ないので作り直せない） |
| CL-11 | `hasClip(context): String` | OP-07 | 失敗をエラーで返す（今は `"false"`） | 失敗を `"false"` にする |
| CL-12 | `getDescription(context): String` | OP-08 | CL-10 と同じ | CL-10 と同じ |
| CL-13 | `clear(context)` | OP-05 | 同期の戻り値 | listener で返す |
| CL-14 | `startObserving(context)` | OP-09 | 同じ（結果の通知は無い） | - |
| CL-15 | `stopObserving()` | OP-10 | 結果の通知は無い（今は `onClipboardOperation("stopObserving", true, null)`） | 呼んだ後に成功の listener を呼ぶ |
| DL-01 | `UnityAndroidDialogManager.getInstance()` | （無い） | | - |
| DL-02 | `setDialogListener` | （無い） | 要求ごとの完了のコールバック | 種類ごとの受け手を持ち、完了で呼ぶ |
| DL-03 | `setConfirmDialogListener` | （無い） | 同上 | 同上 |
| DL-04 | `setSingleChoiceItemDialogListener` | （無い） | 同上 | 同上 |
| DL-05 | `setMultiChoiceItemDialogListener` | （無い） | 同上 | 同上 |
| DL-06 | `setTextInputDialogListener` | （無い） | 同上 | 同上 |
| DL-07 | `setLoginDialogListener` | （無い） | 同上 | 同上 |
| DL-08 | `showDialog(...)` | OP-13 | 非同期だけ（AC-7）。前面でなければ `NOT_FOREGROUND` で完了（今は呼び出しスレッドで同期に失敗）。`FragmentActivity` でなくても透明な宿主に出る（今は失敗）。閉じたとき（`DISMISSED`）の値が無い（AP-13） | 完了を `onDialog(buttonText, isSuccessful, errorMessage)` に写す。`DISMISSED` は今と同じ `("Cancel", true, "")` に写す。`errorMessage` の文言は包みが持つ |
| DL-09 | `showConfirmDialog(...)` | OP-14 | 同上 | 同上（`DISMISSED` は `("Cancel", true, "")`） |
| DL-10 | `showSingleChoiceItemDialog(...)` | OP-15 | 同上。閉じたときに選択の状態を返さない（AP-13） | 選ばれていない添字 -1 は今と同じ。`DISMISSED` は今は閉じたときの選択の状態を返していたが、C ABI から来ないので包みは保てない（移行ガイドに書く） |
| DL-11 | `showMultiChoiceItemDialog(...)` | OP-16 | 同上（AP-13） | 同上 |
| DL-12 | `showTextInputDialog(...)` | OP-17 | 同上 | `DISMISSED` は今と同じく入力 `""` に写す |
| DL-13 | `showLoginDialog(...)` | OP-18 | 同上 | `DISMISSED` は今と同じくユーザー名とパスワード `""` に写す |
| NT-01 | `UnityAndroidNotificationManager.getInstance()` | （無い） | | - |
| NT-02 | `setNotificationOperationListener` | （無い） | 同期の戻り値（今も呼び出しスレッドで同期） | 戻り値で listener を呼ぶ |
| NT-03 | `clearNotificationOperationListener` | （無い） | 同上 | 同上 |
| NT-04 | `setNotificationActionListener` | OP-40 | 足す・外す形。イベントに種類・tag・`data` の組が入る（今は固定の actionId と `dataJson`）。受け手が無い間のタップを保ち、最初の登録に渡す（今は捨てる）。アプリを開く起動の Intent の action は `actionId` ではなくなる（Kotlin の設計書 8.5） | 種類を今の固定の actionId（本文のタップ、dismiss）に写し、`data` を JSON にする。`set` は外してから足す。起動の Intent の action を読む Unity のコードがあれば 2c で確かめる |
| NT-05 | `clearNotificationActionListener` | OP-42 | | - |
| NT-06 | `setNotificationShownListener` | OP-41 | 足す・外す形 | `set` は外してから足す |
| NT-07 | `clearNotificationShownListener` | OP-42 | | - |
| NT-08 | `hasPermission(context): Boolean` | OP-33 | 失敗をエラーで返す（今は例外が上がる） | 失敗の扱いを 2c で決める（今と同じなら例外にする） |
| NT-09 | `areNotificationsEnabled(context): Boolean` | OP-34 | 同上 | 同上 |
| NT-10 | `isNotificationScheduled(context, id, tag)` | OP-35 | 同上。**1.x から直していない不具合**（Kotlin の設計書 3.3）: 保存しない予約（`not_persist_across_boot`）は見ない | 同上 |
| NT-11 | `canScheduleExactAlarms(context)` | OP-36 | 同上 | 同上 |
| NT-12 | `openNotificationSettings(context)` | OP-37（`NOTIFICATIONS`） | 非同期。前面でなければ `NOT_FOREGROUND`。`package:` の data を付けない（1b の結果 1.2） | 完了を listener に写す |
| NT-13 | `openAppDetailsSettings(context)` | OP-37（`APP_DETAILS`） | 同上 | 同上 |
| NT-14 | `openExactAlarmSettings(context)` | OP-37（`EXACT_ALARM`） | 同上 | 同上 |
| NT-15 | `createChannel(context, json)` | OP-24 | ビルダー。importance と visibility を丸めず範囲外はエラー（AP-8） | JSON を解いてビルダーで組む。今の丸めを包みで行う |
| NT-16 | `deleteChannel(context, id)` | OP-25 | | listener で返す |
| NT-17 | `showNotification(context, json)` | OP-20 | ビルダー。権限が無いか通知が無効なら `PERMISSION_DENIED`（今は黙って成功。AP-16）。本文のタップと dismiss は今と同じく既定で付く（AP-18）。BigPicture の画像や layout が引けないときに Default にせず `RESOURCE_NOT_FOUND`、Messaging の名前の既定 `"You"` を持たない（AP-8）。全画面の起動の Intent の flags は Kotlin の `fullScreenLaunch` のもの（`NEW_TASK` と `RESET_TASK_IF_NEEDED`） | JSON を解いてビルダーで組む。`launchAppOnTap` を `_set_tap` に写す。今の代わりの値（AP-8 の一覧）を包みで行う。`PERMISSION_DENIED` を今と同じ成功に写すか、失敗として出すかは 2c で決める |
| NT-18 | `updateNotification(context, json)` | OP-21 | 同上 | 同上 |
| NT-19 | `cancelNotification(context, id, tag)` | OP-22 | 名前の動詞を Windows の `remove_by_id` / `remove_all` の `remove` にそろえた（AP-5。引数は Android の id と tag） | - |
| NT-20 | `cancelAllNotifications(context)` | OP-23 | 同上 | - |
| NT-21 | `scheduleNotification(context, json)` | OP-26 | 予約を構造体で渡す。未来の時刻の正確な予約で正確なアラームが許されていなければ `EXACT_ALARM_NOT_ALLOWED`（今は黙って不正確な Alarm に下げる。AP-16）。過ぎた時刻の予約は、権限が無ければ `PERMISSION_DENIED`（今はすぐ出そうとして黙って何もしない）。予約が発火した時点で権限が無ければ黙って出ない（今と同じ）。**1.x から直していない不具合**（Kotlin の設計書 3.3）: 過ぎた時刻で予約し直すと前の Alarm が残る、Alarm の失敗で保存と食い違う、強制停止で Alarm が消えても保存は残る | JSON を解く。今と同じにするなら、`EXACT_ALARM_NOT_ALLOWED` のときに `inexact` を立てて呼び直す |
| NT-22 | `cancelScheduledNotification(context, id, tag)` | OP-27 | | - |
| NT-23 | `cancelAllScheduledNotifications(context)` | OP-28 | **1.x から直していない不具合**: 保存しない予約は取り消さない | - |
| NT-24 | `startProgressForegroundService(context, json)` | OP-29 | 補正は C ABI が行う（AP-9）。後ろからの開始は `SERVICE_START_NOT_ALLOWED`（AP-14）。サービスの中の失敗は C に届かない（今と同じく logcat だけ。6.3） | - |
| NT-25 | `updateProgressForegroundService(context, json)` | OP-30 | 同上 | - |
| NT-26 | `completeProgressForegroundService(context, json)` | OP-31 | 同上 | - |
| NT-27 | `stopProgressForegroundService(context)` | OP-32 | 後ろからの停止も `SERVICE_START_NOT_ALLOWED` になりうる（`startService`。AP-14） | - |
| SH-01 | `UnityAndroidShareManager.getInstance()` | （無い） | | - |
| SH-02 | `setShareOperationListener` | OP-53（`onShareResult` の部分） | 操作の結果は完了のコールバック。選択はイベント（AC-22） | 完了を `onShareOperation` に、選択のイベントを `onShareResult` に写す |
| SH-03 | `clearShareOperationListener` | OP-54 | 選択の待ちを消さない（AP-11） | 続けて OP-51 を呼ぶ |
| SH-04 | `setShareChooserActionListener` | OP-52 | 足す・外す形 | `set` は外してから足す |
| SH-05 | `clearShareChooserActionListener` | OP-54 | 受け手を外しても、直前の Share のアクションは押せる（届かないだけ）（AP-11） | - |
| SH-06 | `shareText(context, json)` | OP-43 | アクションのアイコンはバイト列（今は Base64）。空・重複の ID はエラー（今は黙って除く）。読めないアイコンがあると Share 全体が `INVALID_CHOOSER_ACTION` で失敗する（今はその項目を黙って除く）。`android.intent.action.SEND` の ID もふつうの ID（1b の結果 2.3） | Base64 を解いて渡す。今の「空白・重複を除く」を包みで行う。読めないアイコンの除外は、包みが画像として読めるかを事前に確かめられないので保てない（移行ガイドに書く） |
| SH-07 | `shareImage(context, json)` | OP-44 | 非同期。前面でなければ `NOT_FOREGROUND`（今は OS が黙って止める） | 完了を listener に写す |
| SH-08 | `shareImages(context, json)` | OP-45 | 同上 | 同上 |
| SH-09 | `shareFile(context, json)` | OP-46 | 同上 | 同上 |
| SH-10 | `shareFiles(context, json)` | OP-47 | 同上 | 同上 |
| SH-11 | `registerDirectShareTarget(context, json)` | OP-48 | 同期。アイコンはバイト列 | Base64 を解く |
| SH-12 | `removeDirectShareTargets(context, json)` | OP-49 | 同期 | - |
| SH-13 | `shareWithCallback(context, json)` | OP-50 | 選択は要求の ID 付きのイベント。古い Chooser の選択は届かない（1b で直した不具合） | 選択のイベントを `onShareResult` に写す |
| SH-14 | `cancelPendingShareCallback(context)` | OP-51 | 要求の ID で取り消す。結果の通知は無い（今は `onShareOperation` で成功を返す） | 直前の要求の ID を持って渡し、成功の listener を呼ぶ |

## 9. 同期・非同期レイヤー対応表

Repository と UseCase の列は Kotlin の設計書 9 章の表のとおりで、この表では Manager から上を書く。スレッドは完了・イベントが届くスレッド。

| OP | System API と実行方式 | Manager callback / native | C ABI（Bridge） | スレッド | キャンセル・資源の持ち主 | 方式を変える理由 |
|---|---|---|---|---|---|---|
| OP-01 | `ClipboardManager.setPrimaryClip`（Binder、同期） | 同期（`Unit`、投げる） | 同期の戻り値 | 呼び出しスレッド | - | 変えない |
| OP-02 | `ClipboardManager.setPrimaryClip`（Binder、同期） | 同期（`Unit`、投げる） | 同期の戻り値 | 呼び出しスレッド | - | 変えない |
| OP-03 | `ClipboardManager.setPrimaryClip`（Binder、同期） | 同期（`Unit`、投げる） | 同期の戻り値 | 呼び出しスレッド | - | 変えない |
| OP-04 | `ClipboardManager.setPrimaryClip`（Binder、同期） | 同期（`Unit`、投げる） | 同期の戻り値 | 呼び出しスレッド | - | 変えない |
| OP-05 | `clearPrimaryClip`（同期） | 同期 | 同期 | 呼び出しスレッド | - | 変えない |
| OP-06 | `getPrimaryClip` / `hasPrimaryClip` / `getPrimaryClipDescription`（同期） | 同期（値） | 同期。出力のハンドルは利用者が `_free` | 呼び出しスレッド | ハンドルは利用者 | 変えない |
| OP-07 | `getPrimaryClip` / `hasPrimaryClip` / `getPrimaryClipDescription`（同期） | 同期（値） | 同期。出力のハンドルは利用者が `_free` | 呼び出しスレッド | ハンドルは利用者 | 変えない |
| OP-08 | `getPrimaryClip` / `hasPrimaryClip` / `getPrimaryClipDescription`（同期） | 同期（値） | 同期。出力のハンドルは利用者が `_free` | 呼び出しスレッド | ハンドルは利用者 | 変えない |
| OP-09 | `addPrimaryClipChangedListener`（main） | 同期（main だけ） | main に積む。完了は無い | main | - | Kotlin の口が main だけなので積む |
| OP-10 | `addPrimaryClipChangedListener`（main） | 同期（main だけ） | main に積む。完了は無い | main | - | Kotlin の口が main だけなので積む |
| OP-11 | Receiver・監視（main） | `EventHub`（main） | イベントの登録（第 1 部 5.7） | main | `user_data` は `release` まで利用者 | C の関数ポインタへ配るため |
| OP-12 | Receiver・監視（main） | `EventHub`（main） | イベントの登録（第 1 部 5.7） | main | `user_data` は `release` まで利用者 | C の関数ポインタへ配るため |
| OP-13 | `DialogFragment`（main） | callback（main で 1 回）。suspend 版は使わない | 非同期（完了のコールバック） | main | 要求の ID で取り消し。結果のハンドルは利用者 | 変えない（Kotlin も callback） |
| OP-14 | `DialogFragment`（main） | callback（main で 1 回）。suspend 版は使わない | 非同期（完了のコールバック） | main | 要求の ID で取り消し。結果のハンドルは利用者 | 変えない（Kotlin も callback） |
| OP-15 | `DialogFragment`（main） | callback（main で 1 回）。suspend 版は使わない | 非同期（完了のコールバック） | main | 要求の ID で取り消し。結果のハンドルは利用者 | 変えない（Kotlin も callback） |
| OP-16 | `DialogFragment`（main） | callback（main で 1 回）。suspend 版は使わない | 非同期（完了のコールバック） | main | 要求の ID で取り消し。結果のハンドルは利用者 | 変えない（Kotlin も callback） |
| OP-17 | `DialogFragment`（main） | callback（main で 1 回）。suspend 版は使わない | 非同期（完了のコールバック） | main | 要求の ID で取り消し。結果のハンドルは利用者 | 変えない（Kotlin も callback） |
| OP-18 | `DialogFragment`（main） | callback（main で 1 回）。suspend 版は使わない | 非同期（完了のコールバック） | main | 要求の ID で取り消し。結果のハンドルは利用者 | 変えない（Kotlin も callback） |
| OP-19 | - | 同期（main に積む） | 同期の戻り値。待たない | - | - | 変えない |
| OP-20 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-21 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-22 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-23 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-24 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-25 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-26 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-27 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-28 | `NotificationManager`、`AlarmManager`、ファイル（同期） | 同期（`Result`） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-29 | `startForegroundService` / `startService`（同期） | 同期（`Unit`、投げる） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-30 | `startForegroundService` / `startService`（同期） | 同期（`Unit`、投げる） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-31 | `startForegroundService` / `startService`（同期） | 同期（`Unit`、投げる） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-32 | `startForegroundService` / `startService`（同期） | 同期（`Unit`、投げる） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-33 | `NotificationManagerCompat`、`AlarmManager`、ファイル（同期） | 同期（値） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-34 | `NotificationManagerCompat`、`AlarmManager`、ファイル（同期） | 同期（値） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-35 | `NotificationManagerCompat`、`AlarmManager`、ファイル（同期） | 同期（値） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-36 | `NotificationManagerCompat`、`AlarmManager`、ファイル（同期） | 同期（値） | 同期 | 呼び出しスレッド | - | 変えない |
| OP-37 | `startActivity`（前面の Activity から） | 同期（`NotificationSettingsOpenResult`） | 非同期（main で前面を判定してから呼ぶ） | main | - | 前面の判定は main でしかできない（AC-15） |
| OP-38 | Activity Result の権限の要求（main） | callback（main で 1 回） | 非同期 | main | 要求の ID で取り消し | 変えない |
| OP-39 | - | 同期（main に積む） | 同期の戻り値。待たない | - | - | 変えない |
| OP-40 | Receiver・監視（main） | `EventHub`（main） | イベントの登録（第 1 部 5.7） | main | `user_data` は `release` まで利用者 | C の関数ポインタへ配るため |
| OP-41 | Receiver・監視（main） | `EventHub`（main） | イベントの登録（第 1 部 5.7） | main | `user_data` は `release` まで利用者 | C の関数ポインタへ配るため |
| OP-42 | Receiver・監視（main） | `EventHub`（main） | イベントの登録（第 1 部 5.7） | main | `user_data` は `release` まで利用者 | C の関数ポインタへ配るため |
| OP-43 | `startActivity`（Chooser） | 同期（`Unit`、投げる） | 非同期（main で前面を判定してから呼ぶ） | main | - | 前面の判定は main でしかできない（AC-15） |
| OP-44 | `startActivity`（Chooser） | 同期（`Unit`、投げる） | 非同期（main で前面を判定してから呼ぶ） | main | - | 前面の判定は main でしかできない（AC-15） |
| OP-45 | `startActivity`（Chooser） | 同期（`Unit`、投げる） | 非同期（main で前面を判定してから呼ぶ） | main | - | 前面の判定は main でしかできない（AC-15） |
| OP-46 | `startActivity`（Chooser） | 同期（`Unit`、投げる） | 非同期（main で前面を判定してから呼ぶ） | main | - | 前面の判定は main でしかできない（AC-15） |
| OP-47 | `startActivity`（Chooser） | 同期（`Unit`、投げる） | 非同期（main で前面を判定してから呼ぶ） | main | - | 前面の判定は main でしかできない（AC-15） |
| OP-48 | `ShortcutManagerCompat`（同期） | 同期 | 同期 | 呼び出しスレッド | - | 変えない |
| OP-49 | `ShortcutManagerCompat`（同期） | 同期 | 同期 | 呼び出しスレッド | - | 変えない |
| OP-50 | `startActivity`（Chooser） | 同期（印、投げる） | 非同期（main で前面を判定してから呼ぶ） | main | 選択の待ちは C の要求の ID で取り消す（AP-17） | 前面の判定は main でしかできない（AC-15） |
| OP-51 | - | 同期 | 同期（main に積む。待たない） | - | - | 第 1 部 5.7 |
| OP-52 | Receiver・監視（main） | `EventHub`（main） | イベントの登録（第 1 部 5.7） | main | `user_data` は `release` まで利用者 | C の関数ポインタへ配るため |
| OP-53 | Receiver・監視（main） | `EventHub`（main） | イベントの登録（第 1 部 5.7） | main | `user_data` は `release` まで利用者 | C の関数ポインタへ配るため |
| OP-54 | Receiver・監視（main） | `EventHub`（main） | イベントの登録（第 1 部 5.7） | main | `user_data` は `release` まで利用者 | C の関数ポインタへ配るため |
| OP-55 | 第 1 部 5.3 | `LibraryRuntime.ensureInitialized` | 同期。待たない | 呼び出しスレッド | - | 第 1 部 |
| OP-56 | 第 1 部 5.3 | （Kotlin は呼ばない。C の状態を読む） | 同期。待たない | 呼び出しスレッド | - | 第 1 部 |

### 9.1 C ABI で加わる変換

- 文字列: 厳密な UTF-8 の検査と U+FFFD の置き換え（第 1 部 5.10）
- 前面の判定と `NOT_FOREGROUND`（第 1 部 5.8、AP-14）
- Kotlin の例外とエラーの値の写し（11 章）
- Kotlin の要求の ID と C の要求の ID の対応（帳簿。5.3）
- 名前（アイコン、layout、view の ID）を `NotificationResourceResolver` で引く（6.3）
- Progress の補正（AP-9）

## 10. 振る舞いの集合との対応（README 6 章）

README 6 章の振る舞いの集合に ID を付け、C ABI の OP に対応させる。**2a の機械照合はこの表の ID と OP の対応を読み、どの振る舞いにも C ABI の OP があることを確かめる。** B は今のブリッジの ID（8.3）。

| ID | 振る舞い | 種類 | C ABI での区分 | B | C ABI |
|---|---|---|---|---|---|
| BH-01 | テキストをコピーする | 操作 | 同期の結果 | CL-06 | OP-01 |
| BH-02 | HTML をコピーする | 操作 | 同期の結果 | CL-07 | OP-02 |
| BH-03 | URI をコピーする | 操作 | 同期の結果 | CL-08 | OP-03 |
| BH-04 | 複数のテキストをコピーする | 操作 | 同期の結果 | CL-09 | OP-04 |
| BH-05 | クリップボードを読む | 問い合わせ | 同期の結果 | CL-10 | OP-06 |
| BH-06 | クリップの有無 | 問い合わせ | 同期の結果 | CL-11 | OP-07 |
| BH-07 | クリップの説明 | 問い合わせ | 同期の結果 | CL-12 | OP-08 |
| BH-08 | クリップボードを消す | 操作 | 同期の結果 | CL-13 | OP-05 |
| BH-09 | 変更の監視を始める | 操作 | 受け付けだけ（main に積む） | CL-14 | OP-09 |
| BH-10 | 変更の監視を止める | 操作 | 受け付けだけ（main に積む） | CL-15 | OP-10 |
| BH-11 | Alert を出す | 操作と完了 | 受け付けた後の完了 | DL-08 | OP-13 |
| BH-12 | Confirm を出す | 操作と完了 | 受け付けた後の完了 | DL-09 | OP-14 |
| BH-13 | 単一選択を出す | 操作と完了 | 受け付けた後の完了 | DL-10 | OP-15 |
| BH-14 | 複数選択を出す | 操作と完了 | 受け付けた後の完了 | DL-11 | OP-16 |
| BH-15 | 入力を出す | 操作と完了 | 受け付けた後の完了 | DL-12 | OP-17 |
| BH-16 | ログインを出す | 操作と完了 | 受け付けた後の完了 | DL-13 | OP-18 |
| BH-17 | 通知の権限の有無 | 問い合わせ | 同期の結果 | NT-08 | OP-33 |
| BH-18 | 通知が有効か | 問い合わせ | 同期の結果 | NT-09 | OP-34 |
| BH-19 | 予約があるか | 問い合わせ | 同期の結果 | NT-10 | OP-35 |
| BH-20 | 正確なアラームを使えるか | 問い合わせ | 同期の結果 | NT-11 | OP-36 |
| BH-21 | 通知の設定の画面を開く | 操作と完了 | 受け付けた後の完了 | NT-12 | OP-37 |
| BH-22 | アプリの詳細の画面を開く | 操作と完了 | 受け付けた後の完了 | NT-13 | OP-37 |
| BH-23 | 正確なアラームの設定の画面を開く | 操作と完了 | 受け付けた後の完了 | NT-14 | OP-37 |
| BH-24 | チャンネルを作る | 操作 | 同期の結果 | NT-15 | OP-24 |
| BH-25 | チャンネルを消す | 操作 | 同期の結果 | NT-16 | OP-25 |
| BH-26 | 通知を出す | 操作 | 同期の結果 | NT-17 | OP-20 |
| BH-27 | 通知を更新する | 操作 | 同期の結果 | NT-18 | OP-21 |
| BH-28 | 通知を消す | 操作 | 同期の結果 | NT-19 | OP-22 |
| BH-29 | 通知をすべて消す | 操作 | 同期の結果 | NT-20 | OP-23 |
| BH-30 | 通知を予約する | 操作 | 同期の結果 | NT-21 | OP-26 |
| BH-31 | 予約を取り消す | 操作 | 同期の結果 | NT-22 | OP-27 |
| BH-32 | 予約をすべて取り消す | 操作 | 同期の結果 | NT-23 | OP-28 |
| BH-33 | Progress の前景サービスを始める | 操作 | 同期の結果 | NT-24 | OP-29 |
| BH-34 | Progress を更新する | 操作 | 同期の結果 | NT-25 | OP-30 |
| BH-35 | Progress を完了する | 操作 | 同期の結果 | NT-26 | OP-31 |
| BH-36 | Progress を止める | 操作 | 同期の結果 | NT-27 | OP-32 |
| BH-37 | テキストを共有する（Chooser Action を含む） | 操作と完了 | 受け付けた後の完了 | SH-06 | OP-43 |
| BH-38 | 画像を共有する | 操作と完了 | 受け付けた後の完了 | SH-07 | OP-44 |
| BH-39 | 複数の画像を共有する | 操作と完了 | 受け付けた後の完了 | SH-08 | OP-45 |
| BH-40 | ファイルを共有する | 操作と完了 | 受け付けた後の完了 | SH-09 | OP-46 |
| BH-41 | 複数のファイルを共有する | 操作と完了 | 受け付けた後の完了 | SH-10 | OP-47 |
| BH-42 | Direct Share の共有先を登録する | 操作 | 同期の結果 | SH-11 | OP-48 |
| BH-43 | Direct Share の共有先を消す | 操作 | 同期の結果 | SH-12 | OP-49 |
| BH-44 | 選ばれたアプリを受ける Share を開く | 操作と完了 | 受け付けた後の完了 | SH-13 | OP-50 |
| BH-45 | 選択の待ちを取り消す | 操作 | 受け付けだけ（main に積む） | SH-14 | OP-51 |
| EV-01 | クリップボードの変更 | 自発のイベント | イベント | CL-04 | OP-11 |
| EV-02 | 通知の本文のタップ・アクション・dismiss・カスタムビューのクリック | 自発のイベント | イベント | NT-04 | OP-40 |
| EV-03 | 予約した通知が出た | 自発のイベント | イベント | NT-06 | OP-41 |
| EV-04 | Chooser Action が押された | 自発のイベント | イベント | SH-04 | OP-52 |
| EV-05 | Share で選ばれたアプリ | 自発のイベント | イベント | SH-02 | OP-53 |
| RG-01 | クリップボードの変更の登録と解除 | 登録と解除 | 登録と解除 | CL-04、CL-05 | OP-11、OP-12 |
| RG-02 | 通知の操作のイベントの登録と解除 | 登録と解除 | 登録と解除 | NT-04、NT-05 | OP-40、OP-42 |
| RG-03 | 通知の表示のイベントの登録と解除 | 登録と解除 | 登録と解除 | NT-06、NT-07 | OP-41、OP-42 |
| RG-04 | Chooser Action の登録と解除 | 登録と解除 | 登録と解除 | SH-04、SH-05 | OP-52、OP-54 |
| RG-05 | 選ばれたアプリの登録と解除 | 登録と解除 | 登録と解除 | SH-02、SH-03 | OP-53、OP-54 |
| RG-06 | クリップボードの監視の開始と停止（README 6 章は登録と解除に含める） | 登録と解除 | 受け付けだけ（main に積む） | CL-14、CL-15 | OP-09、OP-10 |
| PR-01 | 通知の権限の要求（ブリッジに無い。README D-5） | 操作と完了 | 受け付けた後の完了 | - | OP-38、OP-39 |

- 「C ABI での区分」は第 1 部 8 章が求めた分け方（同期の結果／受け付けた後の完了／イベント／登録と解除）。2a はこの列から完了とイベントの数を導く
- 操作の完了（README 6 章の「操作の完了」）は、ブリッジの 4 つの結果の listener（Clipboard、Dialog、Notification、Share）にまとまっていた。C ABI では「操作と完了」の行の OP の完了のコールバックか、同期の戻り値になる
- Dialog の要求の取り消し（OP-19）と通知の権限の要求の取り消し（OP-39）は、ブリッジに無い新しい操作

## 11. エラー

0〜5 はすべての機能で同じ意味（AP-12）。**Kotlin を呼ばずに入口で決まる失敗は戻り値で、受け付けた後の失敗は完了の引数で返す**（第 1 部 1.3、AP-19）。「Kotlin の結果」は受け口が写す元。節の順は Windows の設計書と同じ（11.1 Dialog、11.2 Notification、11.3 Clipboard）で、Android だけの 11.4 Share と 11.5 初期化を後に置く。

| 値 | 名前の末尾 | 意味 |
|---|---|---|
| 0 | `NONE` | 成功 |
| 1 | `INVALID_PARAMETER` | `NULL`、不正な UTF-8、長さ、`struct_size` が小さい、範囲外の値、`IllegalArgumentException` |
| 2 | `NOT_INITIALIZED` | 初期化の前（AC-3）。戻り値が `void` の関数（`_free`、`_listener_remove`）と読み取りとビルダーは除く |
| 3 | `NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値がある（第 1 部 1.1、Windows の設計書 7.8） |
| 4 | `UNKNOWN` | 写しの表に無い例外、JNI の失敗（logcat に詳細。AC-10） |
| 5 | `OUT_OF_MEMORY` | `std::bad_alloc`、`OutOfMemoryError` |

### 11.1 `ntk_dialog_error`

| 値 | 名前 | Kotlin の結果 |
|---|---|---|
| 0 | `NTK_DIALOG_ERROR_NONE` | 成功 |
| 1 | `NTK_DIALOG_ERROR_INVALID_PARAMETER` | 入口の検査、`IllegalArgumentException` |
| 2 | `NTK_DIALOG_ERROR_NOT_INITIALIZED` | 初期化の前 |
| 3 | `NTK_DIALOG_ERROR_NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値 |
| 4 | `NTK_DIALOG_ERROR_UNKNOWN` | 写しの表に無い例外、JNI の失敗 |
| 5 | `NTK_DIALOG_ERROR_OUT_OF_MEMORY` | `std::bad_alloc`、`OutOfMemoryError` |
| 6 | `NTK_DIALOG_ERROR_CANCELED` | `DialogResult.Canceled(REQUESTED)`（OP-19 の取り消し） |
| 7 | `NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM` | `DialogResult.Canceled(HOST_DESTROYED)`（宿主や Activity が壊れた） |
| 8 | `NTK_DIALOG_ERROR_NOT_FOREGROUND` | 受け口の前面の判定、`DialogResult.Failed(NOT_FOREGROUND)` |
| 9 | `NTK_DIALOG_ERROR_HOST_START_FAILED` | `DialogResult.Failed(HOST_START_FAILED)` |
| 10 | `NTK_DIALOG_ERROR_SHOW_FAILED` | `DialogResult.Failed(SHOW_FAILED)` |

- `DialogResult.Failed(NOT_INITIALIZED)` は、受け口が入口で初期化を確かめるので起きない（起きたら 2）

### 11.2 `ntk_notification_error`

| 値 | 名前 | Kotlin の結果 |
|---|---|---|
| 0 | `NTK_NOTIFICATION_ERROR_NONE` | 成功 |
| 1 | `NTK_NOTIFICATION_ERROR_INVALID_PARAMETER` | 入口の検査、`IllegalArgumentException` |
| 2 | `NTK_NOTIFICATION_ERROR_NOT_INITIALIZED` | 初期化の前 |
| 3 | `NTK_NOTIFICATION_ERROR_NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値 |
| 4 | `NTK_NOTIFICATION_ERROR_UNKNOWN` | 写しの表に無い例外、JNI の失敗 |
| 5 | `NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY` | `std::bad_alloc`、`OutOfMemoryError` |
| 6 | `NTK_NOTIFICATION_ERROR_CANCELED` | `PermissionRequestResult.Canceled(REQUESTED)` |
| 7 | `NTK_NOTIFICATION_ERROR_CANCELED_BY_SYSTEM` | `PermissionRequestResult.Canceled(HOST_DESTROYED)` |
| 8 | `NTK_NOTIFICATION_ERROR_NOT_FOREGROUND` | 受け口の前面の判定、`PermissionRequestResult.Failed(NOT_FOREGROUND)` |
| 9 | `NTK_NOTIFICATION_ERROR_HOST_START_FAILED` | `PermissionRequestResult.Failed(HOST_START_FAILED)` |
| 10 | `NTK_NOTIFICATION_ERROR_PERMISSION_DENIED` | 受け口の事前の確かめ（`show`、`update`、過ぎた時刻の `schedule`。AP-16） |
| 11 | `NTK_NOTIFICATION_ERROR_EXACT_ALARM_NOT_ALLOWED` | 受け口の事前の確かめ（未来の時刻の正確な `schedule`。過ぎた時刻の予約には当てない。AP-16） |
| 12 | `NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND` | 受け口がアイコン・画像・layout・view の ID の名前を引けない（AP-8） |
| 13 | `NTK_NOTIFICATION_ERROR_STORAGE_FAILED` | 予約の保存の `IOException`（Kotlin の設計書 8.6） |
| 14 | `NTK_NOTIFICATION_ERROR_SERVICE_START_NOT_ALLOWED` | `ServiceStartNotAllowedException` とその子（Progress の 4 つの操作。AP-14） |
| 15 | `NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED` | `NotificationSettingsOpenResult.FAILED` |

**操作ごとの写し**（表に無い例外は 4。`SecurityException` は、操作ごとに次のとおり）:

| 操作 | `SecurityException` | そのほか |
|---|---|---|
| `show`、`update` | 4（事前の確かめの後に起きるのは想定外） | - |
| `schedule` | 4（事前の確かめの後に起きるのは想定外） | `IOException` → 13 |
| `start_progress`〜`stop_progress` | 4（サービスの起動そのものの拒否。前景サービスの種類の権限が無いときの `SecurityException` はサービスの中で起き、C には届かない。6.3） | `ServiceStartNotAllowedException` → 14 |
| `open_settings_async` | 4 | `FAILED` → 15 |

- `PermissionRequestResult.Failed(NOT_INITIALIZED)` は、受け口が入口で初期化を確かめるので起きない（起きたら 2）
- `PermissionRequestResult.Granted` と `Denied` は、エラー 0 で結果の値（`GRANTED` / `DENIED`）
- `NotificationSettingsOpenResult.OPENED` と `OPENED_FALLBACK` は、エラー 0 で結果の値

### 11.3 `ntk_clipboard_error`

| 値 | 名前 | Kotlin の結果 |
|---|---|---|
| 0 | `NTK_CLIPBOARD_ERROR_NONE` | 成功 |
| 1 | `NTK_CLIPBOARD_ERROR_INVALID_PARAMETER` | 入口の検査、`IllegalArgumentException` |
| 2 | `NTK_CLIPBOARD_ERROR_NOT_INITIALIZED` | 初期化の前 |
| 3 | `NTK_CLIPBOARD_ERROR_NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値 |
| 4 | `NTK_CLIPBOARD_ERROR_UNKNOWN` | 写しの表に無い例外、JNI の失敗 |
| 5 | `NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY` | `std::bad_alloc`、`OutOfMemoryError` |
| 6 | `NTK_CLIPBOARD_ERROR_EMPTY_CONTENT` | `ClipboardErrorCode.EMPTY_CONTENT` |
| 7 | `NTK_CLIPBOARD_ERROR_EMPTY_ITEMS` | `ClipboardErrorCode.EMPTY_ITEMS` |
| 8 | `NTK_CLIPBOARD_ERROR_INVALID_URI` | `ClipboardErrorCode.INVALID_URI` |
| 9 | `NTK_CLIPBOARD_ERROR_UNAVAILABLE` | `ClipboardErrorCode.UNAVAILABLE` |
| 10 | `NTK_CLIPBOARD_ERROR_READ_NOT_ALLOWED` | `ClipboardErrorCode.READ_NOT_ALLOWED` |
| 11 | `NTK_CLIPBOARD_ERROR_SECURITY` | `ClipboardErrorCode.SECURITY` |

- 受け口は `AndroidClipboardManager.errorCodeOf(e)` で写す。`ClipboardErrorCode.UNKNOWN` は 4（`UNKNOWN`）。6〜11 は `ClipboardErrorCode` の宣言の順（`UNKNOWN` を除く）で、2a はこの順を照合する

### 11.4 `ntk_share_error`

| 値 | 名前 | Kotlin の結果 |
|---|---|---|
| 0 | `NTK_SHARE_ERROR_NONE` | 成功 |
| 1 | `NTK_SHARE_ERROR_INVALID_PARAMETER` | 入口の検査、`IllegalArgumentException` |
| 2 | `NTK_SHARE_ERROR_NOT_INITIALIZED` | 初期化の前 |
| 3 | `NTK_SHARE_ERROR_NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値 |
| 4 | `NTK_SHARE_ERROR_UNKNOWN` | 写しの表に無い例外、JNI の失敗 |
| 5 | `NTK_SHARE_ERROR_OUT_OF_MEMORY` | `std::bad_alloc`、`OutOfMemoryError` |
| 6 | `NTK_SHARE_ERROR_NOT_FOREGROUND` | 受け口の前面の判定 |
| 7 | `NTK_SHARE_ERROR_EMPTY_CONTENT` | `ShareDomainError.EmptyContent`（空の本文は入口で返す。AP-19） |
| 8 | `NTK_SHARE_ERROR_NO_SHARE_TARGET` | `ShareDomainError.NoShareTarget` |
| 9 | `NTK_SHARE_ERROR_FILE_NOT_FOUND` | `ShareDomainError.FileNotFound` |
| 10 | `NTK_SHARE_ERROR_ILLEGAL_FILE_ACCESS` | `ShareDomainError.IllegalFileAccess` |
| 11 | `NTK_SHARE_ERROR_INVALID_MIME_TYPE` | `ShareDomainError.InvalidMimeType` |
| 12 | `NTK_SHARE_ERROR_DIRECT_SHARE_REGISTRATION_FAILED` | `ShareDomainError.DirectShareRegistrationFailed` |
| 13 | `NTK_SHARE_ERROR_EMPTY_ID_LIST` | `ShareDomainError.EmptyIdList`（入口で返す） |
| 14 | `NTK_SHARE_ERROR_EMPTY_FILE_LIST` | `ShareDomainError.EmptyFileList`（入口で返す） |
| 15 | `NTK_SHARE_ERROR_INVALID_ICON` | `ShareDomainError.InvalidBase64Icon`（Direct Share のアイコンが画像として読めない） |
| 16 | `NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION` | `ShareDomainError.InvalidChooserAction`（空・重複の ID は入口で、読めないアイコンは完了で返す） |

- 7〜16 は `ShareDomainError` の宣言の順で、2a はこの順を照合する
- `CANCELED` は無い（6.4）

### 11.5 `ntk_android_error`

第 1 部 1.4 のとおり。初期化の関数だけが返す。共通の 0〜5 の決まり（AP-12）は当てない（第 1 部で決めた値のまま）。

| 値 | 名前 | 意味 |
|---|---|---|
| 0 | `NTK_ANDROID_ERROR_NONE` | 初期化が済んだ |
| 1 | `NTK_ANDROID_ERROR_INVALID_PARAMETER` | `env` か `context` が `NULL` |
| 2 | `NTK_ANDROID_ERROR_CLASS_NOT_FOUND` | AAR のクラスかメンバーが無い（直らない） |
| 3 | `NTK_ANDROID_ERROR_JNI_FAILURE` | 一時的な失敗（やり直せる） |
| 4 | `NTK_ANDROID_ERROR_IN_PROGRESS` | ほかのスレッドが初期化している（やり直せる） |

## 12. テスト設計

### 12.1 C ABI のテスト（`android_library_capi_test`。GoogleTest、AC-14）

| 観点 | 中身 |
|---|---|
| 入口の検査 | 8.2 のすべての関数で、`NULL`、厳密な UTF-8 の 3 種の拒否、長さ、`struct_size`（小さい、上限、知らない部分の 0 と 0 以外）、範囲（6.3 の数値）。出力の引数に入口で `NULL` を書くこと |
| 未初期化 | 8.1 の OP-01〜OP-54 のうち戻り値がエラーのものが `NOT_INITIALIZED` を返し、ビルダーと読み取りと `_free` と `_listener_remove(NULL)` が動く（第 1 部 6 章の初期化の経路のテストと同じプロセスの分け方） |
| 写しの表 | 11 章の各行を、Kotlin の結果を起こして確かめる（空の内容、0 個の配列、存在しないファイル、読めないアイコン、重複した Chooser Action の ID、権限を外した状態の表示、正確なアラームを拒んだ状態の予約、引けない名前、後ろからの Progress の開始） |
| 完了 | 非同期の OP のちょうど 1 回、main で来ること、main から呼んだときは戻った後、`release` のちょうど 1 回（第 1 部 6 章の表の項目を、第 2 部の関数で行う） |
| 前面 | 後ろから呼んだ OP-13〜OP-18、OP-37、OP-38（未許可）、OP-43〜OP-47、OP-50 が `NOT_FOREGROUND` で完了する。OP-38 は許可済みなら後ろからでも `GRANTED` |
| イベント | 同じ種類に 2 つの登録で両方に届く、解除の後に届かない、保っていた操作のイベントが最初の登録に挿入のメッセージの中で届く、**保っていたイベントを配っているコールバックの中で唯一の登録を外して新しく足しても、残りのイベントが新しい登録に届く**（AP-21）、`ACTIVE` な登録が無い間のタップが次の登録に届く、受け口の保持は 33 件目で最も古いものを捨て、届いた順に配る（再入で配っている途中も 32 件を超えない）、イベントのハンドルの値（種類、ID、tag、`data`） |
| Dialog | 6 種の結果の値、`DISMISSED`、取り消しの `CANCELED`、宿主の破棄の `CANCELED_BY_SYSTEM`、透明な宿主 |
| Share | AP-7（アクションの無い `ntk_share_text` の後に前のアクションが届かない）、選択のイベントの要求の ID、取り消しの後に選択が届かない、`NOT_FOREGROUND` で前の待ちが消えない |
| Progress | AP-9 の補正が通知に表れる（`getActiveNotifications` の flags）、進み具合が無いと `INVALID_PARAMETER`、後ろからの 4 つの操作が `SERVICE_START_NOT_ALLOWED`（起こせる版で） |
| ビルダー | style の上書き、対応する style の無い `_add_message` / `_add_view_click` が `INVALID_PARAMETER`、範囲外の値 |
| 出力のハンドル | 範囲外の添字は `NULL` か 0、`_free(NULL)` と `_listener_remove(NULL)` が何もしない、文字列の U+FFFD |
| 0 で埋めた構造体 | 0 で埋めた各構造体（と `NULL`）で呼んだ結果が Kotlin の既定値で呼んだ結果と同じ（E-9 の反転した名前を含む） |
| 事前の確かめ（AP-16） | 権限を外した状態の `show`、`update`、過ぎた時刻の `schedule` が `PERMISSION_DENIED`。正確なアラームを拒んだ状態の未来の正確な `schedule` が `EXACT_ALARM_NOT_ALLOWED` で、不正確な `schedule` と過ぎた時刻の正確な `schedule`（権限があるとき）は成功する。通知を無効にした状態の `show` が `PERMISSION_DENIED` |
| 既定のタップと dismiss（AP-18） | 何も設定しない内容の通知を押すとアプリが開いてタップのイベントが来る、消すと dismiss のイベントが来る。`_set_tap` の 3 つのモード |
| 解除の副作用（AP-11） | 変更の受け手を外しても監視は続く、選択の受け手を外しても待ちは消えない |
| Share の要求の ID（AP-17） | 出力の ID と選択のイベントの ID が同じ。前の要求を待っている間に、空白だけの本文で開いて失敗すると前の要求の選択が届き、Chooser を開けない（`NO_SHARE_TARGET`）で失敗すると前の要求の選択が届かない。2 つのスレッドから続けて開いたとき、古い Chooser の選択は届かず、新しい要求の選択は新しい ID で届く。開いた直後（main で開く処理の後）の取り消しで選択が届かない。`NOT_FOREGROUND` の要求の ID で取り消しても前の待ちが消えない。帳簿に無い印の選択（Kotlin から直接開いた Share）は C に届かない |
| 入口と完了の分け方（AP-19） | 件数 0、空文字列の本文、空・重複の Chooser Action の ID、`NULL` のアイコンが戻り値で返り、**完了は呼ばれず、`release` だけが呼び出しスレッドで関数が戻る前に 1 回**（第 1 部 1.3）。空白だけの本文は完了で `EMPTY_CONTENT` |
| Dialog を閉じたとき（AP-13） | 戻るで閉じると `DISMISSED` で、値の読み取りが既定（-1、0 件、`NULL`） |
| system_code（第 1 部 AC-10） | 失敗しうる関数の後の `ntk_last_system_code()` と、完了の `system_code` が 0（第 1 部 6 章の「公開面」の行。値は実行時にしか分からないので 2a の照合ではなくここで確かめる） |
| 構造体の配置 | 付録 A の各構造体の `sizeof` と各欄の `offsetof` を、arm64-v8a と x86_64 で `static_assert` する（2a の照合は `#pragma pack(push, 8)` の有無と位置までを見る） |

### 12.2 端末の上の通しの確かめ

| 観点 | 中身 |
|---|---|
| 通知のイベント | C から出した通知をシェードで押し、操作のイベントが C の受け手に届く（UiAutomator） |
| Dialog と権限 | C から出した Dialog と権限のダイアログを UiAutomator で押し、完了の値を確かめる |
| Share | C から開いた Chooser で選び、選択のイベントが要求の ID 付きで届く（試験の共有先のアプリ） |
| Clipboard | C から書いて C で読む（フォーカスのある Activity の上で）。監視のイベント |

### 12.3 機械照合（2a）

- 照合のスクリプトは、共通のモジュール `scripts/c_abi_contract_common.py` と OS ごとの `scripts/check_c_abi_contract_windows.py`・`scripts/check_c_abi_contract_android.py` に分ける（0.3、13 章 TA-1）。Android の入力: 付録 A、8.1、8.2、10 章、11 章、`android/android_library_capi/src/main/cpp/include/NativeToolkitC/*.h`
- 照らすもの: 8.2 = ヘッダー = 付録 A の関数（合計 155）、宣言の一致（関数、コールバック、構造体、列挙の値、typedef）、10 章のどの振る舞いにも OP がある、11 章の値 = ヘッダー、11.3 と 11.4 の順 = Kotlin の宣言の順、10 章の「C ABI での区分」の数、名前の規則、ASCII、2 つの OS の `Common.h` の一致（第 1 部 5.2）
- ビルドの後: `llvm-nm -D --defined-only libntk.so` の `ntk_*` = 8.2（AP-15）
- 照合のスクリプトの自己テストで、各照合を 1 つずつ壊すと落ちることを確かめる
- 流し方: ヘッダーが無い間（2a）は `--design-only` で付録 A を代わりに照らす。ヘッダーが 1 つでもあれば `--design-only` は失敗するので、TB-1 で 6 つのヘッダーを付録 A からまとめて作り、以後は `--design-only` なしで流す。ビルドの後は、各 ABI の `libntk.so` に `--library` を付けて流す（TB-10、TB-11）。`--library` が無ければ symbols は SKIP と出る
- 照合は宣言を `#` の行を除いて読むので、ヘッダーに許す前処理の行（インクルードガード、`#include`、`extern "C"` の囲み、`Common.h` の `NTK_CALL` の囲みと `#define`、構造体を囲む `#pragma pack(push, 8)` と `(pop)` の 1 組）のほかは失敗にする（`#if` の中の宣言が無条件に見えるのを防ぐ）
- Windows の `Common.h` だけを変えたときは、`check_c_abi_contract_windows.py` では落ちない（OS 間の照合は Android の側にある）。Windows の `Common.h` を変えたら、Android の照合も流す

### 12.4 smoke（`android_library_capi_smoke`）

- 配布物（`m2/`）だけで組む C のアプリが、R8 を有効にした release で、初期化・通知の表示・Clipboard の書き込みと読み取り・Dialog（完了まで）を通す

### 12.5 変異

足した検査は、契約を保ったまま形を変える変異で壊して落ちることを確かめる（common.md「検査の書き方」）。

## 13. 実装タスク分解

| ID | 内容 | 見積 | 依存 | 完了の条件 |
|---|---|---|---|---|
| TA-1 | `check_c_abi_contract.py` を、共通のモジュール `c_abi_contract_common.py`（読み取り、解析、報告、OS に依らない照合、OS 間の `Common.h` の照合）と、OS ごとの `check_c_abi_contract_windows.py`（`.def`、C++ の API との写し）・`check_c_abi_contract_android.py`（Kotlin の Manager、10 章、`llvm-nm`）に分ける（0.3）。操作の数は表から導く。自己テストと `scripts/README.md` を新しい名前に合わせる | 1.5日 | - | Windows の照合が今と同じ結果。Android は付録 A とヘッダーの雛形で動く。自己テストで壊すと落ちる |
| TA-2 | `check_manual_c_examples.py` を TA-1 と同じ形で、共通のモジュールと OS ごとのファイルに分ける（章の見出し、前置き、NDK の clang は OS ごと） | 1.0日 | TA-1 | Windows が今と同じ。Android の例が無いときは SKIP と出す |
| TB-1 | `android_library_capi` の雛形（第 1 部 5.1、5.4）、6 つの公開ヘッダー（付録 A からまとめて作る。12.3）、初期化（第 1 部 5.3） | 1.5日 | - | 第 1 部 6 章の初期化の経路のテスト。`check_c_abi_contract_android.py` が `--design-only` なしで通る |
| TB-2 | 共通の部品（文字列、`struct_size`、出力のハンドル、登録の表と帳簿、前面の判定、エラーの写しの土台） | 1.5日 | TB-1 | 第 1 部 6 章の `release` と完了のテスト |
| TB-3 | Clipboard（OP-01〜OP-12、読み取りの結果と説明） | 1.0日 | TB-2 | 12.1 の Clipboard の行。第 1 部 6 章の「未初期化の `NOT_INITIALIZED`」（TB-1 から移した。TB-1 には操作が無い） |
| TB-4 | Dialog（OP-13〜OP-19、結果） | 1.5日 | TB-2 | 12.1 の Dialog の行と 12.2。第 1 部 6 章の「手動の経路の後に Dialog が出る」「Activity を渡して後ろへ回すと `NOT_FOREGROUND`」（TB-1 から移した）。main を止めた間に受け付けて取り消した要求の Dialog が出ないこと（第 1 部 5.7 の挿入の行。TB-2 の試験用の操作では見えない） |
| TB-5 | 通知のビルダー（内容とチャンネル）。ビルダーを Kotlin の値に変える処理と名前の解決は TB-6 に移した（ビルダーに読み出しの口が無く、写した中身と名前は表示して確かめるため。2026-10-05） | 1.5日 | TB-2 | 12.1 のビルダーの行 |
| TB-6 | 通知の操作（OP-20〜OP-39）と Progress の補正。ビルダーを Kotlin の値に変える処理、名前の解決、イベントの Intent（TB-5 から移した） | 1.5日 | TB-5 | 12.1 の写しの表・前面・Progress の行（後ろからの Progress の `SERVICE_START_NOT_ALLOWED` は TB-10 へ移した。計装の下では後ろからの開始が許され、端末のテストで起こせない） |
| TB-7 | 通知のイベント（OP-40〜OP-42） | 1.0日 | TB-6 | 12.1 のイベントの行と 12.2 |
| TB-8 | Share（OP-43〜OP-54） | 1.5日 | TB-2 | 12.1 の Share の行と 12.2 |
| TB-9 | main を待たないことのテスト、競合の再現のテスト（第 1 部 6 章） | 1.0日 | TB-3〜TB-8 | すべての公開の関数 |
| TB-10 | ビルドスクリプト（capi の AAR、`m2/`）と smoke | 1.5日 | TB-3〜TB-9 | 12.4 と 15.2 の配布物の項目。各 ABI の `libntk.so` で `check_c_abi_contract_android.py --library` が通る。第 1 部 6 章の R8 の 2 項目（名前が変わった版で C と Kotlin がどちらも `CLASS_NOT_FOUND`、keep の規則を外した版で表づくりが失敗してもアプリが落ちない）を、smoke に keep の規則を外した版（`optimization.keepRules.ignoreFrom` で AAR の座標を外す）を足して確かめる（TB-1 から移した。プロジェクトの依存には `ignoreFrom` が効かない）。smoke のアプリが後ろから Progress を始めて `SERVICE_START_NOT_ALLOWED` が返ること（TB-6 から移した） |
| TB-11 | `test_android.sh` に C ABI のテスト・smoke・経路ごとのプロセスと、`--library` を付けた契約の照合をつなぐ（第 1 部 C-5） | 0.5日 | TB-10 | 全件が両方の環境で通る |
| TB-12 | 7 章の文書の直し | 0.5日 | - | 7 章の表のすべての行 |
| TC-1 | `unity-native-plugin` に渡す対応表と移行の手引き（16 章） | 0.5日 | TB-11 | 8.3 と 16 章を渡した |

合計見積: 17.5 日（TA 2.5、TB 14.5、TC 0.5）。マニュアルの Android の C ABI の章は README の段階 4 で書く（AP-23）

## 14. リスクと緩和策

| ID | リスク | 緩和策 |
|---|---|---|
| RP-1 | 関数が多く（155）、2b の手間とテストが大きい | ビルダーの関数は同じ形なので、受け口の側を表から作る。12.1 の入口の検査は関数の一覧からテストを生成する |
| RP-2 | 例外の型でエラーを決めるので、Kotlin の側が例外を変えると黙って `UNKNOWN` になる | 11 章の各行をテストで起こす（12.1 の写しの表） |
| RP-3 | AP-8 で今のブリッジの補正をやめたので、Unity の包みが写し損ねると動作が変わる | 8.3 の「Unity の包みが保つこと」の列と、2c の Unity のテスト |
| RP-4 | Clipboard を同期にしたので、main から呼ぶと Binder の呼び出しで main が少し止まる | 今のブリッジも main で呼んでいる。マニュアルに書く |
| RP-5 | 同じ名前で OS ごとに引数・列挙の値・構造体の配置が違う（例: `ntk_clipboard_copy_text`、`ntk_dialog_alert_request`、`NTK_DIALOG_ERROR_CANCELED`、`NTK_NOTIFICATION_ERROR_INVALID_PARAMETER`） | 機能のヘッダーは OS ごと（README D-3）。C# のバインディングは関数・列挙・構造体を OS ごとに宣言する（16 章）。共通の宣言は `Common.h` だけ |

## 15. Definition of Done

### 15.1 機能

- 8.1 の 56 操作と 8.2 の 155 関数が、付録 A の宣言のとおりに公開されている
- 10 章のすべての振る舞いに C ABI の OP がある
- 11 章のすべてのエラーの値が、写しの表のとおりに返る
- 9 章の表と、実装のスレッド・同期性・キャンセルの契約が一致している（12.1 の完了・前面・イベントの行で確かめ、実装のレビューで照らす）

### 15.2 品質

- 12.1〜12.4 が両方の環境で通る（x86_64 は第 1 部の G-3）
- 第 1 部 6 章のテスト（初期化の経路、`release` と完了、main を待たない、競合の再現）が通る
- README 9 章の 2b の項目: 32 ビットで入れたアプリが落ちない、`llvm-nm -D` に `ntk_*` と `JNI_OnLoad` だけが出て libc++ の名前が出ない、16 KB の整列、Prefab の `abi.json` の `"stl": "none"`、POM と依存の一覧、R8 の keep の規則を外した版で初期化が `CLASS_NOT_FOUND` になる、Kotlin 2.2 と 2.1 の利用者で組める
- 2a の機械照合が通り、照合の自己テストが壊すと落ちる
- 足した検査は変異で落ちることを確かめた

### 15.3 構成と文書

- 7 章の文書の直しを済ませた（TB-12）
- `unity-native-plugin` に 8.3 と 16 章を渡した
- マニュアルは README の段階 4（AP-23）

## 16. `unity-native-plugin` に渡す範囲（README 8.6）

| 項目 | 渡すもの |
|---|---|
| 対応表 | 8.3（69 メソッド。Unity の包みが保つことの列） |
| Runtime テストの約 60 件の JSON のテスト | C ABI では意味を失う。**JSON を解く処理は包みに残る**（ブリッジの JSON の形を包みが保つ）ので、包みの JSON の解析と、解析した値から C の関数を呼ぶところをテストにする。基準は 8.3 の「Unity の包みが保つこと」の列 |
| コールバックの例外 | Android では利用者のコールバックの例外でプロセスが終わる（第 1 部 5.11）。Windows では包みが捕まえる。包みの `[MonoPInvokeCallback]` の本体を `try` / `catch` で囲む |
| 差し替え型の listener | 第 1 部 C-6（種類ごとに 1 つのハンドルと「今のハンドル」の印） |
| 解除の副作用 | AP-11。`clear*Listener` で今の副作用を包みが続けて呼ぶ |
| `NOT_FOREGROUND` | Dialog・Share・設定の画面を後ろから呼ぶと `NOT_FOREGROUND` で完了する。今は Dialog は同期に失敗し、Share と設定の画面は OS が黙って止める |
| 値の補正と代わりの値 | AP-8 の一覧（importance・visibility の丸め、BigPicture や layout が引けないときの Default、Messaging の名前 `"You"` と時刻の既定、小さいアイコンの既定、引けない大きいアイコンとアクションのアイコンの省略、view の ID や `actionId` の無いクリックを捨てること、`bigText` の空）と、Chooser Action の空白と重複の除外、Base64 を包みが行う。読めない Chooser Action のアイコンの除外は保てない |
| 通知のタップと dismiss | `launchAppOnTap` を `_set_tap` に写す（既定は今と同じく開く。AP-18） |
| Kotlin が黙って成功にしていた場面 | `PERMISSION_DENIED` と `EXACT_ALARM_NOT_ALLOWED`（AP-16）を、今と同じ成功に写すか（正確な予約は `inexact` で呼び直す）、失敗として出すかを 2c で決める |
| 問い合わせの失敗 | NT-08〜NT-11 は今は例外が上がる。C ABI はエラーを返す |
| Dialog を閉じたときの値 | AP-13。`DISMISSED` を今の値（`"Cancel"`、入力は `""`）に写す。選択の状態は来ないので保てない |
| C# のバインディング | 機能の関数・列挙・構造体は OS ごとに宣言する（AP-5、RP-5）。`ntk_version()` は OS ごとの期待値と比べる（第 1 部 AC-11） |

## 付録 A. 公開ヘッダーの宣言

`#pragma pack(push, 8)` と include ガード、`extern "C"` はすべてのヘッダーにある（第 1 部 1.1）。コメントは要点だけ。2a は宣言（関数、コールバック、構造体の項目、列挙の値、typedef）をこの付録と照らす。

### A.1 `NativeToolkitC/Common.h`

宣言は Windows の `Common.h` と同じ（第 1 部 5.2）。`NTK_SYSTEM_CODE_*` は置かない。版は Android のライブラリの版。

```c
#ifndef NATIVETOOLKITC_COMMON_H
#define NATIVETOOLKITC_COMMON_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(_MSC_VER)
#define NTK_CALL __cdecl
#else
#define NTK_CALL
#endif

#define NTK_VERSION_MAJOR 2
#define NTK_VERSION_MINOR 0
#define NTK_VERSION_PATCH 0
/** (MAJOR << 16) | (MINOR << 8) | PATCH, written as a literal so that every binding generator can read it. */
#define NTK_VERSION 0x020000

/** Tells the caller that the library is done with a user_data pointer. Called exactly once. */
typedef void (NTK_CALL *ntk_release_fn)(void* user_data);

/** The version of the library, in the form of NTK_VERSION. */
uint32_t NTK_CALL ntk_version(void);

/** The raw value the OS reported for the last failure on this thread. Always 0 on Android. */
uint32_t NTK_CALL ntk_last_system_code(void);

/** A string the library returned. */
typedef struct ntk_string ntk_string;
/** The text, NUL-terminated. Valid until the handle is freed. */
const char* NTK_CALL ntk_string_data(const ntk_string* s);
/** The length in bytes, without the terminator. */
size_t      NTK_CALL ntk_string_size(const ntk_string* s);
/** Releases the string. Does nothing for NULL. */
void        NTK_CALL ntk_string_free(ntk_string* s);

/** Bytes the library returned. */
typedef struct ntk_bytes ntk_bytes;
/** The bytes; never NULL for a valid handle, even when the size is 0. */
const uint8_t* NTK_CALL ntk_bytes_data(const ntk_bytes* b);
/** The number of bytes. */
size_t         NTK_CALL ntk_bytes_size(const ntk_bytes* b);
/** Releases the bytes. Does nothing for NULL. */
void           NTK_CALL ntk_bytes_free(ntk_bytes* b);

/** A list of strings the library returned. */
typedef struct ntk_string_list ntk_string_list;
/** The number of strings. */
size_t      NTK_CALL ntk_string_list_count(const ntk_string_list* list);
/** The string at index, or NULL when index is out of range. out_size may be NULL. */
const char* NTK_CALL ntk_string_list_at(const ntk_string_list* list, size_t index, size_t* out_size);
/** Releases the list. Does nothing for NULL. */
void        NTK_CALL ntk_string_list_free(ntk_string_list* list);

#ifdef __cplusplus
}
#endif
#endif
```

### A.2 `NativeToolkitC/Android.h`

第 1 部 1.4 のとおり。

```c
#ifndef NATIVETOOLKITC_ANDROID_H
#define NATIVETOOLKITC_ANDROID_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_android_error;
enum {
    NTK_ANDROID_ERROR_NONE = 0,
    NTK_ANDROID_ERROR_INVALID_PARAMETER = 1,
    NTK_ANDROID_ERROR_CLASS_NOT_FOUND = 2,
    NTK_ANDROID_ERROR_JNI_FAILURE = 3,
    NTK_ANDROID_ERROR_IN_PROGRESS = 4
};

/** env: JNIEnv* of the calling thread. context: any Context (jobject). Never waits. */
ntk_android_error NTK_CALL ntk_android_init(void* env, void* context);
/** Nonzero once both the native tables and the Kotlin side are ready. */
int32_t           NTK_CALL ntk_android_is_initialized(void);

#ifdef __cplusplus
}
#endif
#endif
```

### A.3 `NativeToolkitC/Clipboard.h`

```c
#ifndef NATIVETOOLKITC_CLIPBOARD_H
#define NATIVETOOLKITC_CLIPBOARD_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_clipboard_error;
enum {
    NTK_CLIPBOARD_ERROR_NONE = 0,
    NTK_CLIPBOARD_ERROR_INVALID_PARAMETER = 1,
    NTK_CLIPBOARD_ERROR_NOT_INITIALIZED = 2,
    NTK_CLIPBOARD_ERROR_NOT_SUPPORTED = 3,
    NTK_CLIPBOARD_ERROR_UNKNOWN = 4,
    NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY = 5,
    NTK_CLIPBOARD_ERROR_EMPTY_CONTENT = 6,
    NTK_CLIPBOARD_ERROR_EMPTY_ITEMS = 7,
    NTK_CLIPBOARD_ERROR_INVALID_URI = 8,
    NTK_CLIPBOARD_ERROR_UNAVAILABLE = 9,
    NTK_CLIPBOARD_ERROR_READ_NOT_ALLOWED = 10,
    NTK_CLIPBOARD_ERROR_SECURITY = 11
};

/** What ntk_clipboard_read returned. */
typedef struct ntk_clipboard_content ntk_clipboard_content;
/** What ntk_clipboard_get_description returned. */
typedef struct ntk_clipboard_description ntk_clipboard_description;
/** A change listener registration. */
typedef struct ntk_clipboard_listener ntk_clipboard_listener;

/** The clipboard changed. Called on the main thread. */
typedef void (NTK_CALL *ntk_clipboard_change_fn)(void* user_data);

#pragma pack(push, 8)
/** NULL means: no label, not sensitive. */
typedef struct ntk_clipboard_copy_options {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* label;            /**< NULL: no label. */
    int32_t     sensitive;        /**< Nonzero: mark the clip as sensitive. */
    uint32_t    reserved1;
} ntk_clipboard_copy_options;
#pragma pack(pop)

/* Writes, reads and queries run on the calling thread (AP-2). */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_text(const char* text, const ntk_clipboard_copy_options* options);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_html(const char* html, const char* plain_text,
                                                     const ntk_clipboard_copy_options* options);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_uri(const char* uri, const ntk_clipboard_copy_options* options);
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_texts(const char* const* texts, size_t count,
                                                      const ntk_clipboard_copy_options* options);
ntk_clipboard_error NTK_CALL ntk_clipboard_clear(void);
/** *out_content is NULL when the clipboard is empty or the app has no input focus. */
ntk_clipboard_error NTK_CALL ntk_clipboard_read(ntk_clipboard_content** out_content);
ntk_clipboard_error NTK_CALL ntk_clipboard_has_clip(int32_t* out_has_clip);
/** *out_description is NULL when the clipboard is empty. */
ntk_clipboard_error NTK_CALL ntk_clipboard_get_description(ntk_clipboard_description** out_description);

/* Posted to the main thread; NONE means accepted, not that observing started. Idempotent. */
ntk_clipboard_error NTK_CALL ntk_clipboard_start_observing(void);
ntk_clipboard_error NTK_CALL ntk_clipboard_stop_observing(void);

ntk_clipboard_error NTK_CALL ntk_clipboard_add_change_listener(ntk_clipboard_change_fn callback, void* user_data,
                                                               ntk_release_fn release,
                                                               ntk_clipboard_listener** out_listener);
/** Removes the registration. The handle is invalid afterwards. Does nothing for NULL. */
void NTK_CALL ntk_clipboard_listener_remove(ntk_clipboard_listener* listener);

/* Readers: pointers stay valid until the handle is freed. out_size may be NULL. */
const char* NTK_CALL ntk_clipboard_content_label(const ntk_clipboard_content* content, size_t* out_size);
size_t      NTK_CALL ntk_clipboard_content_mime_type_count(const ntk_clipboard_content* content);
const char* NTK_CALL ntk_clipboard_content_mime_type_at(const ntk_clipboard_content* content, size_t index,
                                                        size_t* out_size);
size_t      NTK_CALL ntk_clipboard_content_item_count(const ntk_clipboard_content* content);
const char* NTK_CALL ntk_clipboard_content_item_text_at(const ntk_clipboard_content* content, size_t index,
                                                        size_t* out_size);
const char* NTK_CALL ntk_clipboard_content_item_html_at(const ntk_clipboard_content* content, size_t index,
                                                        size_t* out_size);
const char* NTK_CALL ntk_clipboard_content_item_uri_at(const ntk_clipboard_content* content, size_t index,
                                                       size_t* out_size);
const char* NTK_CALL ntk_clipboard_content_item_coerced_text_at(const ntk_clipboard_content* content, size_t index,
                                                                size_t* out_size);
void        NTK_CALL ntk_clipboard_content_free(ntk_clipboard_content* content);

const char* NTK_CALL ntk_clipboard_description_label(const ntk_clipboard_description* description,
                                                     size_t* out_size);
size_t      NTK_CALL ntk_clipboard_description_mime_type_count(const ntk_clipboard_description* description);
const char* NTK_CALL ntk_clipboard_description_mime_type_at(const ntk_clipboard_description* description,
                                                            size_t index, size_t* out_size);
int32_t     NTK_CALL ntk_clipboard_description_is_styled_text(const ntk_clipboard_description* description);
/** The classification status, or -1 when the OS did not report one. */
int32_t     NTK_CALL ntk_clipboard_description_classification_status(const ntk_clipboard_description* description);
void        NTK_CALL ntk_clipboard_description_free(ntk_clipboard_description* description);

#ifdef __cplusplus
}
#endif
#endif
```

### A.4 `NativeToolkitC/Dialog.h`

```c
#ifndef NATIVETOOLKITC_DIALOG_H
#define NATIVETOOLKITC_DIALOG_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_dialog_error;
enum {
    NTK_DIALOG_ERROR_NONE = 0,
    NTK_DIALOG_ERROR_INVALID_PARAMETER = 1,
    NTK_DIALOG_ERROR_NOT_INITIALIZED = 2,
    NTK_DIALOG_ERROR_NOT_SUPPORTED = 3,
    NTK_DIALOG_ERROR_UNKNOWN = 4,
    NTK_DIALOG_ERROR_OUT_OF_MEMORY = 5,
    NTK_DIALOG_ERROR_CANCELED = 6,
    NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM = 7,
    NTK_DIALOG_ERROR_NOT_FOREGROUND = 8,
    NTK_DIALOG_ERROR_HOST_START_FAILED = 9,
    NTK_DIALOG_ERROR_SHOW_FAILED = 10
};

typedef int32_t ntk_dialog_answer;
enum {
    NTK_DIALOG_ANSWER_BUTTON = 0,
    NTK_DIALOG_ANSWER_DISMISSED = 1
};

typedef int32_t ntk_dialog_button;
enum {
    NTK_DIALOG_BUTTON_POSITIVE = 0,
    NTK_DIALOG_BUTTON_NEGATIVE = 1
};

/** The answer of a dialog. Owned by the receiver: free it with ntk_dialog_result_free. */
typedef struct ntk_dialog_result ntk_dialog_result;

/** Called once on the main thread. result is NULL unless error is NTK_DIALOG_ERROR_NONE. */
typedef void (NTK_CALL *ntk_dialog_result_fn)(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                              uint32_t system_code, ntk_dialog_result* result);

#pragma pack(push, 8)
/* NULL texts take the library's defaults; a zero-filled struct is the default dialog. */
typedef struct ntk_dialog_alert_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* button_text;                      /**< NULL: "OK". */
    int32_t     not_cancelable;                   /**< Nonzero: Back does not close it. */
    int32_t     not_cancelable_on_touch_outside;  /**< Nonzero: an outside tap does not close it. */
} ntk_dialog_alert_request;

typedef struct ntk_dialog_confirm_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* negative_text;                    /**< NULL: "No". */
    const char* positive_text;                    /**< NULL: "Yes". */
    int32_t     not_cancelable;
    int32_t     not_cancelable_on_touch_outside;
} ntk_dialog_confirm_request;

typedef struct ntk_dialog_single_choice_request {
    uint32_t           struct_size;
    uint32_t           reserved0;
    const char*        title;
    const char* const* items;
    size_t             item_count;
    int32_t            checked_index;             /**< -1: none checked. */
    int32_t            not_cancelable;
    int32_t            not_cancelable_on_touch_outside;
    uint32_t           reserved1;
    const char*        negative_text;             /**< NULL: "Cancel". */
    const char*        positive_text;             /**< NULL: "OK". */
} ntk_dialog_single_choice_request;

typedef struct ntk_dialog_multi_choice_request {
    uint32_t           struct_size;
    uint32_t           reserved0;
    const char*        title;
    const char* const* items;
    size_t             item_count;
    const int32_t*     checked;                   /**< NULL: none checked; else item_count values. */
    const char*        negative_text;             /**< NULL: "Cancel". */
    const char*        positive_text;             /**< NULL: "OK". */
    int32_t            not_cancelable;
    int32_t            not_cancelable_on_touch_outside;
} ntk_dialog_multi_choice_request;

typedef struct ntk_dialog_text_input_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* hint;
    const char* negative_text;                    /**< NULL: "Cancel". */
    const char* positive_text;                    /**< NULL: "OK". */
    int32_t     enable_positive_when_empty;
    int32_t     not_cancelable;
    int32_t     not_cancelable_on_touch_outside;
    uint32_t    reserved1;
} ntk_dialog_text_input_request;

typedef struct ntk_dialog_login_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* username_hint;                    /**< NULL: "Username". */
    const char* password_hint;                    /**< NULL: "Password". */
    const char* negative_text;                    /**< NULL: "Cancel". */
    const char* positive_text;                    /**< NULL: "Login". */
    int32_t     enable_positive_when_empty;
    int32_t     not_cancelable;
    int32_t     not_cancelable_on_touch_outside;
    uint32_t    reserved1;
} ntk_dialog_login_request;
#pragma pack(pop)

/* Asynchronous (AC-7): NONE means accepted; the answer comes through callback on the main thread.
   out_request_id may be NULL. */
ntk_dialog_error NTK_CALL ntk_dialog_show_alert_async(const ntk_dialog_alert_request* request,
                                                      ntk_dialog_result_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_confirm_async(const ntk_dialog_confirm_request* request,
                                                        ntk_dialog_result_fn callback, void* user_data,
                                                        ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_single_choice_async(const ntk_dialog_single_choice_request* request,
                                                              ntk_dialog_result_fn callback, void* user_data,
                                                              ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_multi_choice_async(const ntk_dialog_multi_choice_request* request,
                                                             ntk_dialog_result_fn callback, void* user_data,
                                                             ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_text_input_async(const ntk_dialog_text_input_request* request,
                                                           ntk_dialog_result_fn callback, void* user_data,
                                                           ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_login_async(const ntk_dialog_login_request* request,
                                                      ntk_dialog_result_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);
/** Never waits. Does nothing after completion or for an unknown ID. */
ntk_dialog_error NTK_CALL ntk_dialog_cancel(uint64_t request_id);

/* Readers: pointers stay valid until the result is freed. out_size may be NULL. */
ntk_dialog_answer NTK_CALL ntk_dialog_result_answer(const ntk_dialog_result* result);
ntk_dialog_button NTK_CALL ntk_dialog_result_button(const ntk_dialog_result* result);
const char*       NTK_CALL ntk_dialog_result_button_text(const ntk_dialog_result* result, size_t* out_size);
/** Single choice: the checked index, or -1. */
int32_t           NTK_CALL ntk_dialog_result_checked_index(const ntk_dialog_result* result);
/** Multi choice: the number of items and whether each is checked. */
size_t            NTK_CALL ntk_dialog_result_checked_count(const ntk_dialog_result* result);
int32_t           NTK_CALL ntk_dialog_result_checked_at(const ntk_dialog_result* result, size_t index);
/** Text input: the text. */
const char*       NTK_CALL ntk_dialog_result_text(const ntk_dialog_result* result, size_t* out_size);
/** Login: the username and the password. */
const char*       NTK_CALL ntk_dialog_result_username(const ntk_dialog_result* result, size_t* out_size);
const char*       NTK_CALL ntk_dialog_result_password(const ntk_dialog_result* result, size_t* out_size);
void              NTK_CALL ntk_dialog_result_free(ntk_dialog_result* result);

#ifdef __cplusplus
}
#endif
#endif
```

### A.5 `NativeToolkitC/Notification.h`

```c
#ifndef NATIVETOOLKITC_NOTIFICATION_H
#define NATIVETOOLKITC_NOTIFICATION_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_notification_error;
enum {
    NTK_NOTIFICATION_ERROR_NONE = 0,
    NTK_NOTIFICATION_ERROR_INVALID_PARAMETER = 1,
    NTK_NOTIFICATION_ERROR_NOT_INITIALIZED = 2,
    NTK_NOTIFICATION_ERROR_NOT_SUPPORTED = 3,
    NTK_NOTIFICATION_ERROR_UNKNOWN = 4,
    NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY = 5,
    NTK_NOTIFICATION_ERROR_CANCELED = 6,
    NTK_NOTIFICATION_ERROR_CANCELED_BY_SYSTEM = 7,
    NTK_NOTIFICATION_ERROR_NOT_FOREGROUND = 8,
    NTK_NOTIFICATION_ERROR_HOST_START_FAILED = 9,
    NTK_NOTIFICATION_ERROR_PERMISSION_DENIED = 10,
    NTK_NOTIFICATION_ERROR_EXACT_ALARM_NOT_ALLOWED = 11,
    NTK_NOTIFICATION_ERROR_RESOURCE_NOT_FOUND = 12,
    NTK_NOTIFICATION_ERROR_STORAGE_FAILED = 13,
    NTK_NOTIFICATION_ERROR_SERVICE_START_NOT_ALLOWED = 14,
    NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED = 15
};

typedef int32_t ntk_notification_settings_target;
enum {
    NTK_NOTIFICATION_SETTINGS_TARGET_NOTIFICATIONS = 0,
    NTK_NOTIFICATION_SETTINGS_TARGET_APP_DETAILS = 1,
    NTK_NOTIFICATION_SETTINGS_TARGET_EXACT_ALARM = 2
};

typedef int32_t ntk_notification_settings_result;
enum {
    NTK_NOTIFICATION_SETTINGS_RESULT_OPENED = 0,
    NTK_NOTIFICATION_SETTINGS_RESULT_OPENED_FALLBACK = 1
};

typedef int32_t ntk_notification_permission_result;
enum {
    NTK_NOTIFICATION_PERMISSION_RESULT_GRANTED = 0,
    NTK_NOTIFICATION_PERMISSION_RESULT_DENIED = 1
};

typedef int32_t ntk_notification_tap;
enum {
    NTK_NOTIFICATION_TAP_OPEN_APP = 0,            /**< The default: open the app and send a BODY_TAP event. */
    NTK_NOTIFICATION_TAP_EVENT_ONLY = 1,
    NTK_NOTIFICATION_TAP_NONE = 2
};

typedef int32_t ntk_notification_event_kind;
enum {
    NTK_NOTIFICATION_EVENT_KIND_BODY_TAP = 0,
    NTK_NOTIFICATION_EVENT_KIND_ACTION = 1,
    NTK_NOTIFICATION_EVENT_KIND_DISMISS = 2
};

/** A notification being built. Not thread-safe; usable before initialization. Setters copy their arguments. */
typedef struct ntk_notification_content ntk_notification_content;
/** A channel being built. Not thread-safe; usable before initialization. */
typedef struct ntk_notification_channel ntk_notification_channel;
/** An event listener registration. */
typedef struct ntk_notification_listener ntk_notification_listener;
/** A tap, an action or a dismissal. Owned by the receiver: free it. */
typedef struct ntk_notification_interaction ntk_notification_interaction;
/** A scheduled notification was shown. Owned by the receiver: free it. */
typedef struct ntk_notification_shown ntk_notification_shown;

typedef void (NTK_CALL *ntk_notification_settings_fn)(void* user_data, ntk_notification_error error,
                                                      uint32_t system_code,
                                                      ntk_notification_settings_result result);
typedef void (NTK_CALL *ntk_notification_permission_fn)(void* user_data, uint64_t request_id,
                                                        ntk_notification_error error, uint32_t system_code,
                                                        ntk_notification_permission_result result);
typedef void (NTK_CALL *ntk_notification_interaction_fn)(void* user_data, ntk_notification_interaction* event);
typedef void (NTK_CALL *ntk_notification_shown_fn)(void* user_data, ntk_notification_shown* event);

#pragma pack(push, 8)
/** A zero-filled struct with trigger_at_millis set is the default schedule. */
typedef struct ntk_notification_schedule_options {
    uint32_t struct_size;
    uint32_t reserved0;
    int64_t  trigger_at_millis;                   /**< Unix time in milliseconds; at least 1. */
    int32_t  inexact;                             /**< Nonzero: an inexact alarm. */
    int32_t  not_allow_while_idle;                /**< Nonzero: not while idle (Doze). */
    int32_t  not_persist_across_boot;             /**< Nonzero: not restored after a reboot. */
    int32_t  alarm_type;                          /**< 0 (RTC_WAKEUP) or 1 (RTC). */
} ntk_notification_schedule_options;

typedef struct ntk_notification_action {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* action_id;                        /**< Delivered in the ACTION event. */
    const char* icon_name;                        /**< NULL: no icon. */
    int32_t     launch_app;                       /**< Nonzero: open the app when pressed. */
    int32_t     allow_generated_replies;
    int32_t     semantic_action;
    int32_t     contextual;
    int32_t     no_user_interface;                /**< Nonzero: the action does not show UI. */
    uint32_t    reserved1;
} ntk_notification_action;
#pragma pack(pop)

/* Operations run on the calling thread unless marked asynchronous (AP-2). */
/** PERMISSION_DENIED when notifications are not allowed (checked before showing). */
ntk_notification_error NTK_CALL ntk_notification_show(const ntk_notification_content* content);
/** PERMISSION_DENIED when notifications are not allowed (checked before updating). */
ntk_notification_error NTK_CALL ntk_notification_update(const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_remove(int32_t id, const char* tag);
ntk_notification_error NTK_CALL ntk_notification_remove_all(void);
ntk_notification_error NTK_CALL ntk_notification_create_channel(const ntk_notification_channel* channel);
ntk_notification_error NTK_CALL ntk_notification_delete_channel(const char* channel_id);
/** Writes the schedule to a file on the calling thread. A future exact schedule without the exact
    alarm permission returns EXACT_ALARM_NOT_ALLOWED; a past one without the notification permission
    returns PERMISSION_DENIED. */
ntk_notification_error NTK_CALL ntk_notification_schedule(const ntk_notification_content* content,
                                                          const ntk_notification_schedule_options* schedule);
ntk_notification_error NTK_CALL ntk_notification_cancel_scheduled(int32_t id, const char* tag);
/** Cancels only schedules persisted across boot (as in 1.x). */
ntk_notification_error NTK_CALL ntk_notification_cancel_all_scheduled(void);
ntk_notification_error NTK_CALL ntk_notification_start_progress(const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_update_progress(const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_complete_progress(const ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_stop_progress(void);
ntk_notification_error NTK_CALL ntk_notification_has_permission(int32_t* out_value);
ntk_notification_error NTK_CALL ntk_notification_are_enabled(int32_t* out_value);
/** Sees only schedules persisted across boot (as in 1.x). */
ntk_notification_error NTK_CALL ntk_notification_is_scheduled(int32_t id, const char* tag, int32_t* out_value);
ntk_notification_error NTK_CALL ntk_notification_can_schedule_exact_alarms(int32_t* out_value);
/** Asynchronous; needs the app in the foreground. */
ntk_notification_error NTK_CALL ntk_notification_open_settings_async(ntk_notification_settings_target target,
                                                                     ntk_notification_settings_fn callback,
                                                                     void* user_data, ntk_release_fn release);
/** Asynchronous. out_request_id may be NULL. */
ntk_notification_error NTK_CALL ntk_notification_request_permission(ntk_notification_permission_fn callback,
                                                                    void* user_data, ntk_release_fn release,
                                                                    uint64_t* out_request_id);
/** Never waits. Does nothing after completion or for an unknown ID. */
ntk_notification_error NTK_CALL ntk_notification_cancel_permission_request(uint64_t request_id);
ntk_notification_error NTK_CALL ntk_notification_add_interaction_listener(ntk_notification_interaction_fn callback,
                                                                          void* user_data, ntk_release_fn release,
                                                                          ntk_notification_listener** out_listener);
ntk_notification_error NTK_CALL ntk_notification_add_shown_listener(ntk_notification_shown_fn callback,
                                                                    void* user_data, ntk_release_fn release,
                                                                    ntk_notification_listener** out_listener);
/** The handle is invalid afterwards. Does nothing for NULL. */
void NTK_CALL ntk_notification_listener_remove(ntk_notification_listener* listener);

/* Content builder. Starts from the library's defaults. */
ntk_notification_error NTK_CALL ntk_notification_content_create(int32_t id, const char* title, const char* message,
                                                                ntk_notification_content** out_content);
void NTK_CALL ntk_notification_content_free(ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_content_set_tag(ntk_notification_content* content, const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_channel(ntk_notification_content* content,
                                                                     const ntk_notification_channel* channel);
ntk_notification_error NTK_CALL ntk_notification_content_set_small_icon(ntk_notification_content* content,
                                                                        const char* name);
ntk_notification_error NTK_CALL ntk_notification_content_set_large_icon(ntk_notification_content* content,
                                                                        const char* name);
ntk_notification_error NTK_CALL ntk_notification_content_set_priority(ntk_notification_content* content, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_auto_cancel(ntk_notification_content* content,
                                                                         int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_ongoing(ntk_notification_content* content, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_sub_text(ntk_notification_content* content,
                                                                      const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_show_timestamp(ntk_notification_content* content,
                                                                            int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_timestamp(ntk_notification_content* content,
                                                                       int64_t unix_ms);
ntk_notification_error NTK_CALL ntk_notification_content_set_sound(ntk_notification_content* content,
                                                                   const char* uri);
ntk_notification_error NTK_CALL ntk_notification_content_set_category(ntk_notification_content* content,
                                                                      const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_visibility(ntk_notification_content* content,
                                                                        int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_color(ntk_notification_content* content, uint32_t argb);
ntk_notification_error NTK_CALL ntk_notification_content_set_number(ntk_notification_content* content, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_ticker(ntk_notification_content* content,
                                                                    const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_group(ntk_notification_content* content, const char* key);
ntk_notification_error NTK_CALL ntk_notification_content_set_group_summary(ntk_notification_content* content,
                                                                           int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_group_alert_behavior(ntk_notification_content* content,
                                                                                  int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_sort_key(ntk_notification_content* content,
                                                                      const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_only_alert_once(ntk_notification_content* content,
                                                                             int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_local_only(ntk_notification_content* content,
                                                                        int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_silent(ntk_notification_content* content, int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_uses_chronometer(ntk_notification_content* content,
                                                                              int32_t value);
ntk_notification_error NTK_CALL ntk_notification_content_set_timeout_after(ntk_notification_content* content,
                                                                           int64_t millis);
ntk_notification_error NTK_CALL ntk_notification_content_set_progress(ntk_notification_content* content,
                                                                      int32_t max, int32_t current,
                                                                      int32_t indeterminate);
ntk_notification_error NTK_CALL ntk_notification_content_set_style_big_text(ntk_notification_content* content,
                                                                            const char* big_text,
                                                                            const char* summary_text,
                                                                            const char* big_content_title);
ntk_notification_error NTK_CALL ntk_notification_content_set_style_inbox(ntk_notification_content* content,
                                                                         const char* const* lines, size_t line_count,
                                                                         const char* summary_text,
                                                                         const char* big_content_title);
ntk_notification_error NTK_CALL ntk_notification_content_set_style_big_picture(ntk_notification_content* content,
                                                                               const char* picture_name,
                                                                               const char* picture_uri,
                                                                               const char* summary_text,
                                                                               const char* big_content_title,
                                                                               const char* large_icon_name,
                                                                               int32_t hide_expanded_large_icon);
/** group_conversation: -1 leaves it unset, 0 or 1 sets it. */
ntk_notification_error NTK_CALL ntk_notification_content_set_style_messaging(ntk_notification_content* content,
                                                                             const char* user_display_name,
                                                                             const char* conversation_title,
                                                                             int32_t group_conversation);
ntk_notification_error NTK_CALL ntk_notification_content_add_message(ntk_notification_content* content,
                                                                     const char* text, int64_t timestamp_ms,
                                                                     const char* sender_name);
ntk_notification_error NTK_CALL ntk_notification_content_set_style_custom_view(ntk_notification_content* content,
                                                                               const char* layout_name,
                                                                               const char* big_layout_name);
ntk_notification_error NTK_CALL ntk_notification_content_add_view_click(ntk_notification_content* content,
                                                                        const char* view_id_name,
                                                                        const char* action_id);
ntk_notification_error NTK_CALL ntk_notification_content_set_tap(ntk_notification_content* content,
                                                                 ntk_notification_tap mode);
ntk_notification_error NTK_CALL ntk_notification_content_add_data(ntk_notification_content* content, const char* key,
                                                                  const char* value);
ntk_notification_error NTK_CALL ntk_notification_content_set_dismiss_event(ntk_notification_content* content,
                                                                           int32_t enabled);
ntk_notification_error NTK_CALL ntk_notification_content_set_full_screen(ntk_notification_content* content,
                                                                         int32_t enabled);
ntk_notification_error NTK_CALL ntk_notification_content_add_action(ntk_notification_content* content,
                                                                    const ntk_notification_action* action);

/* Channel builder. Starts from the library's defaults. importance is 0..4 (5 is rejected because
   the library would silently lower it to 3). */
ntk_notification_error NTK_CALL ntk_notification_channel_create(const char* id, const char* name, int32_t importance,
                                                                ntk_notification_channel** out_channel);
void NTK_CALL ntk_notification_channel_free(ntk_notification_channel* channel);
ntk_notification_error NTK_CALL ntk_notification_channel_set_description(ntk_notification_channel* channel,
                                                                         const char* value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_show_badge(ntk_notification_channel* channel,
                                                                        int32_t value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_enable_lights(ntk_notification_channel* channel,
                                                                           int32_t value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_light_color(ntk_notification_channel* channel,
                                                                         uint32_t argb);
ntk_notification_error NTK_CALL ntk_notification_channel_set_enable_vibration(ntk_notification_channel* channel,
                                                                              int32_t value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_vibration_pattern(ntk_notification_channel* channel,
                                                                               const int64_t* pattern, size_t count);
ntk_notification_error NTK_CALL ntk_notification_channel_set_sound(ntk_notification_channel* channel, const char* uri);
ntk_notification_error NTK_CALL ntk_notification_channel_set_lockscreen_visibility(ntk_notification_channel* channel,
                                                                                   int32_t value);
ntk_notification_error NTK_CALL ntk_notification_channel_set_group(ntk_notification_channel* channel,
                                                                   const char* group_id, const char* group_name);

/* Event readers: pointers stay valid until the event is freed. out_size may be NULL. */
ntk_notification_event_kind NTK_CALL ntk_notification_interaction_kind(const ntk_notification_interaction* event);
int32_t     NTK_CALL ntk_notification_interaction_notification_id(const ntk_notification_interaction* event);
/** NULL when the notification has no tag. */
const char* NTK_CALL ntk_notification_interaction_tag(const ntk_notification_interaction* event, size_t* out_size);
/** NULL unless the kind is ACTION. */
const char* NTK_CALL ntk_notification_interaction_action_id(const ntk_notification_interaction* event,
                                                            size_t* out_size);
size_t      NTK_CALL ntk_notification_interaction_data_count(const ntk_notification_interaction* event);
const char* NTK_CALL ntk_notification_interaction_data_key_at(const ntk_notification_interaction* event, size_t index,
                                                              size_t* out_size);
const char* NTK_CALL ntk_notification_interaction_data_value_at(const ntk_notification_interaction* event,
                                                                size_t index, size_t* out_size);
void        NTK_CALL ntk_notification_interaction_free(ntk_notification_interaction* event);

int32_t     NTK_CALL ntk_notification_shown_notification_id(const ntk_notification_shown* event);
const char* NTK_CALL ntk_notification_shown_tag(const ntk_notification_shown* event, size_t* out_size);
const char* NTK_CALL ntk_notification_shown_channel_id(const ntk_notification_shown* event, size_t* out_size);
void        NTK_CALL ntk_notification_shown_free(ntk_notification_shown* event);

#ifdef __cplusplus
}
#endif
#endif
```

### A.6 `NativeToolkitC/Share.h`

```c
#ifndef NATIVETOOLKITC_SHARE_H
#define NATIVETOOLKITC_SHARE_H

#include "Common.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef int32_t ntk_share_error;
enum {
    NTK_SHARE_ERROR_NONE = 0,
    NTK_SHARE_ERROR_INVALID_PARAMETER = 1,
    NTK_SHARE_ERROR_NOT_INITIALIZED = 2,
    NTK_SHARE_ERROR_NOT_SUPPORTED = 3,
    NTK_SHARE_ERROR_UNKNOWN = 4,
    NTK_SHARE_ERROR_OUT_OF_MEMORY = 5,
    NTK_SHARE_ERROR_NOT_FOREGROUND = 6,
    NTK_SHARE_ERROR_EMPTY_CONTENT = 7,
    NTK_SHARE_ERROR_NO_SHARE_TARGET = 8,
    NTK_SHARE_ERROR_FILE_NOT_FOUND = 9,
    NTK_SHARE_ERROR_ILLEGAL_FILE_ACCESS = 10,
    NTK_SHARE_ERROR_INVALID_MIME_TYPE = 11,
    NTK_SHARE_ERROR_DIRECT_SHARE_REGISTRATION_FAILED = 12,
    NTK_SHARE_ERROR_EMPTY_ID_LIST = 13,
    NTK_SHARE_ERROR_EMPTY_FILE_LIST = 14,
    NTK_SHARE_ERROR_INVALID_ICON = 15,
    NTK_SHARE_ERROR_INVALID_CHOOSER_ACTION = 16
};

/** An event listener registration. */
typedef struct ntk_share_listener ntk_share_listener;

/** Called once on the main thread: the Sharesheet opened (NONE), or why it did not. */
typedef void (NTK_CALL *ntk_share_done_fn)(void* user_data, ntk_share_error error, uint32_t system_code);
/** A custom action was pressed. action_id is owned by the receiver. */
typedef void (NTK_CALL *ntk_share_chooser_action_fn)(void* user_data, ntk_string* action_id);
/** An app was chosen in the Sharesheet of request_id. package_name is NULL when unknown; owned by the receiver. */
typedef void (NTK_CALL *ntk_share_selection_fn)(void* user_data, uint64_t request_id, ntk_string* package_name);

#pragma pack(push, 8)
typedef struct ntk_share_text_content {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* text;
    const char* title;                            /**< NULL: none. */
    const char* subject;                          /**< NULL: none. */
    const char* mime_type;                        /**< NULL: "text/plain". */
    const char* preview_title;                    /**< NULL: none. */
    const char* preview_thumbnail_path;           /**< NULL: none. */
} ntk_share_text_content;

/** A custom Sharesheet action (API 34 and later). No struct_size: this set of fields is fixed. */
typedef struct ntk_share_chooser_action {
    const char*    id;
    const char*    label;
    const uint8_t* icon;                          /**< An image (PNG, JPEG, WebP). */
    size_t         icon_size;
} ntk_share_chooser_action;

typedef struct ntk_share_direct_target {
    uint32_t       struct_size;
    uint32_t       reserved0;
    const char*    id;
    const char*    label;
    const char*    category;                      /**< NULL: "android.shortcut.conversation". */
    const uint8_t* icon;
    size_t         icon_size;
} ntk_share_direct_target;
#pragma pack(pop)

/* Opening the Sharesheet is asynchronous and needs the app in the foreground. */
ntk_share_error NTK_CALL ntk_share_text(const ntk_share_text_content* content,
                                        const ntk_share_chooser_action* actions, size_t action_count,
                                        ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
ntk_share_error NTK_CALL ntk_share_image(const char* path, const char* mime_type,
                                         ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
ntk_share_error NTK_CALL ntk_share_images(const char* const* paths, size_t count,
                                          ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
ntk_share_error NTK_CALL ntk_share_file(const char* path,
                                        ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
ntk_share_error NTK_CALL ntk_share_files(const char* const* paths, size_t count,
                                         ntk_share_done_fn callback, void* user_data, ntk_release_fn release);
/* Direct Share targets are synchronous. */
ntk_share_error NTK_CALL ntk_share_register_direct_target(const ntk_share_direct_target* target);
ntk_share_error NTK_CALL ntk_share_remove_direct_targets(const char* const* ids, size_t count);
/** Opens the Sharesheet; the chosen app arrives as a selection event with this request ID.
    out_request_id may be NULL, but then the selection cannot be matched. */
ntk_share_error NTK_CALL ntk_share_text_for_selection(const ntk_share_text_content* content,
                                                      ntk_share_done_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);
/** Never waits; the cancel is posted to the main thread. Does nothing unless request_id is the
    waiting request. */
ntk_share_error NTK_CALL ntk_share_cancel_selection(uint64_t request_id);
ntk_share_error NTK_CALL ntk_share_add_chooser_action_listener(ntk_share_chooser_action_fn callback, void* user_data,
                                                               ntk_release_fn release,
                                                               ntk_share_listener** out_listener);
ntk_share_error NTK_CALL ntk_share_add_selection_listener(ntk_share_selection_fn callback, void* user_data,
                                                          ntk_release_fn release, ntk_share_listener** out_listener);
/** The handle is invalid afterwards. Does nothing for NULL. */
void NTK_CALL ntk_share_listener_remove(ntk_share_listener* listener);

#ifdef __cplusplus
}
#endif
#endif
```
