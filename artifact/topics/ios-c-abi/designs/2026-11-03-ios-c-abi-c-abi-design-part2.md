# iOS ライブラリ C ABI 実装設計書（第 2 部: 関数・対応表・ヘッダー）

## 基本情報

| 項目 | 内容 |
|---|---|
| 対象企画書 | `artifact/topics/ios-c-abi/README.md`（以下「README」） |
| 対象段階 | 段階 2（2a の機械照合、2b の実装、2c に渡す対応表）の前 |
| 対象 OS | iOS 18.0 以降（D-15）。スライスは `ios-arm64` と `ios-arm64_x86_64-simulator`（D-11） |
| 作成日 | 2026-11-03（第 4 版。3 回のレビューとシミュレーターの測りを反映） |
| 状態 | **決定（2026-11-03、利用者）。P2-1〜P2-29 はすべて推奨のとおり** |
| ブランチ | `feature/NTKIT-18` |
| 前段階 | 第 1 部（`designs/2026-10-31-ios-c-abi-c-abi-design.md`。以下「第 1 部」。スレッド・寿命・通知の delegate・前面・エラーの規則を決めた）、段階 1b（Swift の API の補完。`results/2026-10-31-ios-c-abi-stage1b-result.md`。以下「1b の結果」。作業の記録は `results/2026-10-31-ios-c-abi-stage1b-working-notes.md`。以下「1b の記録」） |
| 元にした文書 | Swift の API の設計書（`designs/2026-10-31-ios-c-abi-swift-api-design.md`。以下「Swift の設計書」）、Android の C ABI の設計書 第 2 部（`artifact/topics/android-c-abi/designs/2026-10-05-android-c-abi-c-abi-design-part2.md`。以下「Android 第 2 部」）、今のブリッジ（`ios/UnityIosPlugin/`）、公開 API（`results/swiftinterface/IosLibrary-after-1b-c6.swiftinterface`） |
| レビュー | `reviews/2026-11-03-ios-c-abi-c-abi-design-part2-review-v1.md`（1 回目。Claude 2 本と Codex）、`-v2.md`（2 回目。Claude と Codex）、`-v3.md`（3 回目。A なし） |
| 測り | 0.2（シミュレーター。M1〜M8） |
| 章立て | Windows の設計書・Android 第 2 部と同じ番号にする（8.1 の操作、8.2 の関数の全体、11 章のエラー、付録 A）。2a の機械照合が同じ見出しを読むため |

- **`PLANNED_SYMBOLS_EXEMPT`**: この設計書は、まだ書かれていない C ABI の名前（`ntk_*`）と受け口、`IosLibrary` に足す口（7 章）を定める。名前が実装にあるかの照合は 2a の機械照合と 2b の DoD が受け持つ
- **公開 API の数**: 操作 46、公開する関数 134（8.2）。Android は 56 と 155、Windows は 47 と 105

## 0. この設計書で決めること

ID は `P2-n`（第 2 部）。第 1 部の `P1-n` は変えない（第 1 部の文の直しは 7 章）。**2026-11-03 に利用者がすべて推奨のとおり決めた**（P2-24 はその前に決定済み）。

| ID | 決めること | 案と推奨 | 理由 |
|---|---|---|---|
| P2-1 | 入口 | **推奨: 受け口は機能ごとの Manager だけを呼ぶ**（`IosClipboardManager`、`IosDialogManager`、`IosNotificationManager`、`IosShareManager`。P1-2、Swift の設計書 8.9）。Dialog・Share・権限の要求・設定の画面は `.foreground` を渡す。C から表示元を渡す口は設けない（1b の結果 7 章） | `common.md`「機能の公開の入口」 |
| P2-2 | 同期と非同期の分け方 | **推奨: main が要る操作はすべて完了のコールバックで返す**（D-6）。**同期は** `ntk_notification_install`、取り消し 2 つ、イベントの登録 3 つと解除 2 つ、読み取りと `_free`、ビルダーだけ。完了を持たず受け付けだけを返す操作は作らない（P2-6） | `IosClipboardManager` はクラス全体が `@MainActor`、通知の操作は `async`。Android の AP-2 は「前面が要る操作だけ非同期」だが、iOS は main への受け渡しが要るので形が違う（第 1 部 8 章） |
| P2-3 | 名前の `_async` | **推奨: 完了のコールバックで返す操作には、例外なく `_async` を付ける**（`ntk_notification_request_permission_async`、`ntk_share_content_async` も）。Android の同じ名前（`ntk_notification_request_permission`）は引数と結果の型が違うので、名前をそろえる利益が小さい。逆の考え: Android に合わせて付けないものを残すと、名前から同期か非同期かが分からない | 同じ名前は同じ意味（AP-5、README 3.3）。Android の `ntk_clipboard_copy_text` は同期で戻り値を返し、形が違う |
| P2-4 | Dialog と Share の名前（第 1 部 8 章、README 3.3） | **推奨: Dialog は Android の名前に合わせる**（`ntk_dialog_show_alert_async`、`_confirm_async`、`_text_input_async`、`_login_async`、`ntk_dialog_cancel`、`ntk_dialog_result_*`）。iOS だけの種類を `_destructive_async`、`_action_sheet_async` で足す。Android の `_single_choice_async`、`_multi_choice_async` は無い。**Share は合わせられない**: Android は種類ごとの関数（`ntk_share_text` など）、`IosLibrary` は種類の混ざった項目の配列を 1 回の `share` に渡す（今のブリッジも同じ）。**`ntk_share_content_async` の 1 つにする**。結果は読み取りを足して広げられるようにハンドル（`ntk_share_result`）で返す | Share を種類ごとに分けると、テキストと画像を一緒に共有する今の振る舞い（SH-01）を失う。`completionWithItemsHandler` には `returnedItems` もあり、広げる理由が見えている |
| P2-5 | 受け渡しの形（AP-4、R-34） | **推奨: 通知の内容はビルダー**（`sound` の既定が `.default` で 0 と違い、`userInfo` と添付を持つ）。**Clipboard の書き込み内容、Dialog の要求、Share の要求、通知の trigger と category、Clipboard の options と scope は `struct_size` 付きの構造体**。**配列の要素（通知のアクション、テキスト入力のアクション、Share の項目、Clipboard の複数の表現）も `struct_size` を持つ。受け口は各要素の `struct_size` で次の要素へ進む。同じ配列の要素はすべて同じ大きさでなければ `INVALID_PARAMETER`** | ビルダーは Swift の既定値で始まるので、E-9 の名前の反転が要らない。Clipboard の内容は 9 種の `kind` を持つ 1 つの構造体にし、`copy` と `append` の 2 関数で受ける。逆の考え: Android のように種類ごとの関数にすると 9 × 2 = 18 関数になる。要素に `struct_size` が無いと、後で項目を足せない（Windows の `ntk_dialog_filter` は「足さない」と決めた組で、Android の `ntk_notification_action` は `struct_size` を持つ） |
| P2-6 | 戻り値の無い Notification の操作（README 6 章、8.6、第 1 部 8 章） | **推奨: すべて完了を持つ `_async` にする**（`ntk_notification_remove_async`、`_remove_all_async`、`_cancel_scheduled_async`、`_cancel_all_scheduled_async`）。**`IosLibrary` の Manager に、完了を取る形を足す**（既定は `nil`。7 章）。今の口は同期のシステム API を `Task` に積むだけで順序が決まらず、`cancel_all` の直後の `schedule` が消えうる（今のブリッジも同じ）。**順序は完了で繋ぐ**（M6: 20 回とも崩れなかった。観測で、OS の保証は確かめていない）。完了の失敗の値は無い。`cancelNotification` と `cancelScheduledNotification`、`cancelAllNotifications` と `cancelAllScheduledNotifications` はライブラリで同じ操作なので、C は 2 つにする（Swift の設計書 S-P16）。逆の考え（第 1 版の案）: 完了なしは `IosLibrary` を変えずに済むが、呼ぶ人が順序を確定できない | 完了の役目は失敗の通知だけでなく順序の確定でもある。`common.md`「同期システム API は同期関数として扱い、不必要に `async` で包まない」にも今の口は合わないが、Manager の既存の振る舞いは変えない（完了を足すだけ） |
| P2-7 | userInfo の C での形（第 1 部 8 章、R-32） | **推奨: JSON の文字列（UTF-8）**。入力は `ntk_notification_content_set_user_info_json`（オブジェクトだけ。`null` と最上位の予約のキーは**その関数の戻り値**で `INVALID_PARAMETER`）。**1 回だけ解いて `NotificationUserInfoValue` で持つ**。出力は `ntk_notification_interaction_user_info_json`。変換は 6.3 の表。逆の考え: キーと値の組（Android の `data`）にすると、入れ子と型を失う | userInfo は入れ子で 9 種の値を持つ。今のブリッジも JSON で渡している。今のブリッジは日付やデータで落ちるおそれがあった（8.3 の NT-20） |
| P2-8 | `detectValues` の結果の形 | **推奨: JSON の文字列 1 つ**（`ntk_clipboard_values_fn` の `ntk_string`）。**形は 6.1 の表で ABI として決め、足すのはよいが変えない**。ゴールデンのテストで守る。逆の考え: 読み取りの関数にすると約 30 関数増える | 使う人が少なく、後で読み取りの関数を足しても互換を壊さない |
| P2-9 | エラーの番号（第 1 部 8 章、P1-7） | **推奨: 11 章の表**。規則で決まらなかったものの案: (1) Dialog の `presentationFailed` は `SHOW_FAILED`（10）、Share の同じ case も同じ名前（19）。(2) Share の `noValidItems` は `EMPTY_CONTENT`（7）。(3) `openSettingsFailed` は `SETTINGS_NOT_OPENED`（15）。(4) `invalidURL` は Clipboard（8）も Share（17）も `INVALID_URI`。(5) Clipboard の `cancelled` の C の名前は `CANCELED`（1 つの L）。(6) `attachmentLoadFailed` は iOS だけの値（Android の `RESOURCE_NOT_FOUND` は名前を引けないという別の意味）。(7) iOS だけの値の順は `IosLibrary` の宣言の順。**この順を照らすのは初版を作るときの 1 回だけで、以後は番号の表が変わらないことを照らす**（Swift の enum の並びを C の番号に縛らない）。(8) Clipboard の `invalidRequest` は `INVALID_PARAMETER`（1）に写し、値を足さない。(9) **貼り付けの拒否に Android の `READ_NOT_ALLOWED`（10）を当てない**: OS の知らせは文書の無い `PBErrorDomain` の 13 で、頼れない（M3）。読み込みの拒否は `LOAD_FAILED`（24）、値を調べるのは `DETECTION_FAILED`（29）、同期の読み出しは**成功**で内容が無い（6.1） | 第 1 部 5.10「同じ意味の値には Android と同じ名前」。番号は一度出すと変えられないので、ここが最も後戻りしにくい |
| P2-10 | Notification の `CANCELED`、`CANCELED_BY_SYSTEM`、`PERMISSION_DENIED`（6、7、10） | **推奨: 6 と 7 は欠番にする**（権限の要求も設定の画面も取り消せず、C の経路に当たる失敗が無い）。**`PERMISSION_DENIED`（10）は使う: `show_async`、`update_async`、`schedule_async` は、受け口が先に権限の状態を確かめ、`authorized`、`provisional`、`ephemeral` のどれでもなければ `add` を呼ばずに `PERMISSION_DENIED` で完了する**（Android の AP-16 と同じ考え。`unknown` も通さない）。理由は M2: 権限が無いと `add` は成功を返し、pending に残らない（`notDetermined` の即時の分だけ配信済みに載り、拒否で消える）。`notDetermined` で足した予約は許可した後も発火しない。**確かめた後に状態が変わった場合は守らない**（最善の努力。AP-16 の限りと同じ）。権限の要求の拒否は `NONE` で `granted == 0` のまま。**`IosLibrary` の Swift の口は変えない**: P2-26 は落ちる入力を失敗にするので誰も損をしないが、これは今成功している呼び出しを失敗に変えるので、既存の Swift の利用者の動作が変わる（K-9）。Swift の利用者には DocC で知らせる（7 章） | AP-8 の「黙って変えない」。今のブリッジは黙って成功していた（包みの扱いは 16 章）。第 1 部 2 章の「振る舞いは Swift の API が決める」の例外なので 7 章に書く |
| P2-11 | Share の `CANCELED` | **推奨: 置かない**。Share は取り消せず（P1-24）、利用者が閉じたのは `completed == 0` の成功。第 1 部 1.1 と 8 章の「Share に `CANCELED`」は直す（7 章） | `ShareError` に当たる case が無い |
| P2-12 | Clipboard の読み込みの取り消しを、どのスレッドからでも呼ぶ（S-15） | **推奨: `IosClipboardManager` に `nonisolated public static func cancelLoad(_ box: RequestBox)` を足す**（`IosLibrary` の変更。2b の前）。M1 で、別のモジュールの nonisolated の関数から呼べることを確かめた。インスタンスの `cancelLoad` は `self` を使っていない。**第 1 版の「`shared` を `nonisolated` にする」は組めない**（M1: `main actor-isolated default value in a nonisolated context`）。**1b の結果 7 章の「同じモジュールなので箱を直接閉じる」も成り立たない**（`RequestBox` を閉じる口は internal で、capi は別のモジュール。7 章で直す） | `shared` が `@MainActor` なので、main で得た参照が無いと呼べない。受け付けの時点（main に積む前）には参照が無い |
| P2-13 | Clipboard の失敗の写し | **推奨: callback の形を呼び、文字列の `errorCode` を表で値に写す**（11.3）。箱を取る `loadItem` は callback の形しか無いので、ほかもそろえる。`IosLibrary` の列挙は別のモジュールからは `@frozen` でないので、case を足してもコンパイラーは止めない。**2a の照合が swiftinterface の全 case と 11 章の表を比べて止める**（12.3）。表に無い文字列は `UNKNOWN` とログ | Swift の設計書 8.9 は読み込みの箱の形だけを決めていた。第 1 部 5.10 の「case を写す」は、Clipboard では `errorCode` を通して行う |
| P2-14 | 通知の問い合わせの呼び方（Swift の設計書 8.9 で決まっていないもの） | **推奨: 権限があるか、権限の状態、2 つの一覧は callback の形を呼ぶ**（どれも失敗せず、完了が main で来る）。`show`、`update`、`schedule`、`setBadgeCount` の `async throws` と、category の callback は 8.9 のとおり | `NotificationError` の case が要るのは前者だけ。`throws` は型なしなので、`NotificationError` でない失敗は `UNKNOWN` |
| P2-15 | 値の補正と代わりの値（AP-8） | **推奨: C ABI は補正も代わりの値も行わず、エラーで返す。Unity の包みも補正を持たない**（`common.md`「ラッパーは機能のロジックを持たない」）。**エラーを今の失敗のコールバックに写し、2.0.0 の破壊的変更として移行ガイドに書く**。今のブリッジの次の振る舞いをやめる: 不正な trigger を即時にする（`showNotification`、`updateNotification`）、範囲外の `timeInterval` でプロセスが落ちる、未知の `interruptionLevel` を `.active` にする、壊れた添付やアクションや未知の項目を黙って捨てる、オブジェクトでない `userInfo` を空にする | 第 1 部 1.1 の「値の補正をせず、エラーで返す」。逆の考え: 今の Unity の利用者の振る舞いが変わる。黙って続くより失敗で知らせる方がよく、2.0.0 は破壊的な版である |
| P2-16 | Clipboard の監視の形（R-34） | **推奨: Android と同じく開始・停止と `add_change_listener` / `listener_remove` を分ける**。開始は pasteboard が無いと失敗するので完了で知らせ、停止も完了を持つ（`ntk_clipboard_start_observing_async`、`_stop_observing_async`。P2-2）。受け手は複数にでき、登録しただけでは監視は始まらない | `IosLibrary` の監視は同時に 1 つで、ライブラリの `startObserving` に渡す受け手は受け口の 1 つだけ。受け口が登録に配る。**別の部品の停止で全員が止まる**（今のライブラリの制約。ヘッダーに書く） |
| P2-17 | 解除の副作用（AP-11） | **推奨: `_listener_remove` は登録を外すだけ**。監視は止めない | Android と同じ |
| P2-18 | 通知のイベントの形 | **推奨: Android の名前に合わせる**（`ntk_notification_add_interaction_listener`、`ntk_notification_interaction_*`、`ntk_notification_event_kind`）。設定の要求は別の受け手（`_add_settings_request_listener`）。**今のブリッジの 2 つの受け手（アクションとテキスト入力）は 1 つにまとめ、`_kind` で分ける**（`BODY_TAP`、`ACTION`、`DISMISS` は Android と同じ番号、`TEXT_INPUT` は iOS だけで 3）。ハンドルは所有権ごと渡す（AC-18）。保ったイベントは次の登録 1 つに渡す（AP-21。第 1 部 5.12.7） | 同じ意味は同じ名前（README 3.3）。1a の雛形の「`event_kind` で分ける 1 つの受け手」は下調べの形 |
| P2-19 | 起動のきっかけの通知の取得（第 1 部 8 章） | **推奨: `ntk_notification_get_launch_response_async`**。`launchResponse()` が `@MainActor` なので main に積み、完了で返す。delegate が入っていなければ入口で `NOT_INITIALIZED`。**`NULL` は「今は無い」で、最初に active になるまでは後で値に変わりうる**（ライブラリの DocC）。決まった後は同じ内容。遅く届く場合に確実なのは受け手（`_is_launch`）で、取得の関数は受け手を登録できない時期の補助 | 第 1 部 5.12.7、P1-6、P1-22 |
| P2-20 | 前面の表示の選択肢を変える関数（第 1 部 8 章） | **推奨: 出さない**（D-5）。ブリッジに無く、既定の `[.banner, .list, .sound, .badge]` のまま。要るなら後の版で足す | 互換を壊さずに足せる |
| P2-21 | `out_request_id` の `NULL`（R-34） | **推奨: 許す**。そのときは取り消せない | Android の Share の `out_request_id` と同じ。1a の雛形も許した |
| P2-22 | 0 で埋めた構造体の Dialog の文言（R-34、README 4 章） | **推奨: `NULL` はライブラリの既定の文言**（`"OK"`、`"Cancel"`、`"Delete"`、`"Username"`、`"Password"`、`"Login"`）。`title`、`message`、`placeholder` の `NULL` は「無い」（`nil`。空文字にしない）。真が既定の項目は名前を反転する（`confirm_disabled_when_empty`、`login_disabled_when_empty`。E-9）。「0 で埋める」は `struct_size` のほかの項目のこと | ブリッジは C の `NULL` を空文字のボタンにしていた（8.3 の DL-04） |
| P2-23 | BOM の無い UTF-16 や UTF-8 のデータ（第 1 部 8 章、5.9） | **推奨: 文字列として読まない**。`ntk_clipboard_read_data_async` はバイト列のまま返し、解釈しない | 型の決めつけはライブラリの外の仕事。今のブリッジも Base64 のバイト列を返す |
| P2-24 | 読み込みの時間切れの案内 | **決定済み（2026-11-03、利用者。1b の記録 24.4）**: 既定の 15 秒を変えない。`ntk_clipboard_load_item_async` のヘッダーに「時間切れに利用者が答える時間も入る」と書く（付録 A.2）。同期の読み出しのヘッダーに「答えるまで main が止まる」と書く。**同じことは `detect_values_async` の 5 秒にもある**（M3。答えないまま 5 秒で `TIMED_OUT`。ヘッダーに書く） | MS-08 の実機の結果、M3 |
| P2-25 | 2a の照合の入力（AP-15） | **推奨: Android と同じ**: 8.1、8.2、10 章、11 章、付録 A。`scripts/check_c_abi_contract_ios.py` と `scripts/c_abi_error_numbers.json`（P1-7）を足す。ビルドの後は `nm -gU` で `_ntk_*` を照らす（第 1 部 5.5） | - |
| P2-26 | 落ちる trigger の守りの置き場所 | **推奨: 落ちる入力だけを `IosLibrary` で守る**。`NotificationTrigger` に `public var isValid: Bool` を足す。**偽になるのは、今プロセスが落ちる入力だけ**: `.timeInterval(t, repeats: r)` は `t > 0` で、`r` が真なら `t >= 60` も（M5。`NSInternalInconsistencyException`）、`.calendar` と `.location` は常に真。**M8 で負の値、59.9 と 60、NaN、無限大を測り、落ちるものだけが偽になることを確かめた**（NaN は偽、無限大は落ちずに pending に残るので真）。無限大は C の入力の形の規則で入口で拒み、Swift は変えない。Repository はこれを見て `NotificationError.invalidTrigger`（新しい case）を投げ、受け口は入口で同じ関数を呼び `INVALID_PARAMETER` を返す。**今成功している入力は変えない**（`.calendar` の項目なしは pending 0、`.location` の半径 0 と空の識別子は pending 1。M5）。これらは C の入力の形として受け口の入口で拒む（6 章の基準）ので、Swift と C で結果が違う | 第 1 部 2 章「振る舞いは Swift の API が決める」、P1-2。落ちる入力を受け口にだけ置くと、Swift の利用者は落ちたままになる |
| P2-27 | 権限の要求の選択肢 | **推奨: `ntk_notification_request_permission_async(options, ...)` で受ける**。`options` は `NTK_NOTIFICATION_AUTH_*` の組で、値は `UNAuthorizationOptions` の `rawValue`。0 は既定の `[.alert, .sound, .badge]`。知らないビットは `INVALID_PARAMETER`。**`PROVISIONAL` は 2.0.0 では出さない**: M7 で、OS は `provisional` の後に求めれば通常のダイアログを出すが、`.foreground` の口は `provisional` を許可済みとして求めないので、C からは上げられない。**`openSettingsFor`（OP-43）は `.providesAppNotificationSettings` を求めたアプリにだけ来る**（`IosNotificationManager` の DocC）。**`.foreground` の口は状態が決まった後は OS に求めない**（第 1 部 5.13.2 の表）ので、**既に決まっているアプリ（1.x から上げたアプリを含む）は、この関数では `PROVIDES_APP_SETTINGS` を足せない**。そのときはホストのネイティブのコードが `requestAuthorization` を呼ぶ（16 章） | 選択肢が無いと C だけのアプリでは OP-43 のイベントが決して来ず、P1-10 で足した機能が使えない |
| P2-28 | `callback` の `NULL` | **推奨: 入口で `INVALID_PARAMETER`**（Windows と同じ）。結果が要らないなら空の関数を渡す。所有権ごと渡すハンドルを誰が解放するかの問題も無くなる。今のブリッジは Clipboard・Notification・Share で受けていたので、包みが空の受け手を渡す（8.3） | 状態機械とハンドルの解放を単純に保つ |
| P2-29 | 列挙を返す読み取りの `NULL` | **推奨: `NULL` のハンドルには -1 を返す**（`ntk_dialog_result_button`、`ntk_dialog_result_option_index`、`ntk_clipboard_loaded_item_kind`、`ntk_clipboard_change_kind`、`ntk_clipboard_change_scope_kind`、`ntk_notification_interaction_kind`、`ntk_clipboard_snapshot_matching_at`）。ほかの読み取りは第 1 部 5.7 のとおり 0 か `NULL`（5.7 との違いは 7 章） | `NTK_DIALOG_BUTTON_POSITIVE` は 0 で、`_option_index` の 0 は最初の選択肢なので、失敗のときの読み忘れが「肯定」になる |

### 0.1 利用者に決めてもらったもの

後戻りしにくい順に P2-9（番号）、P2-10・P2-11（どの値を宣言するか）、P2-5・P2-8（関数と構造体の形）、P2-3（名前）。**`IosLibrary` を変えるものは P2-6、P2-12、P2-26**（足すだけで、普通の呼び出しの動作は変えない。関数の参照は組めなくなる。Swift の設計書 3.3）。ほかは Android にそろえたものか、第 1 部から決まるもの。

### 0.2 シミュレーターの測り（2026-11-03）

使い捨ての写しで測った（iPhone 17 Pro / 26.2 と iPhone 16 / 18.3。リポジトリは変えていない。実機は使っていない）。両方の OS で同じ結果だった。

| # | 測ったこと | 結果 | 効いた所 |
|---|---|---|---|
| M1 | `nonisolated static let shared` / `nonisolated static func cancelLoad` | 前者は組めない（`IosClipboardManager.swift:68:35: error: main actor-isolated default value in a nonisolated context`）。後者は組め、別のモジュールの nonisolated の関数から呼べる | P2-12 |
| M2 | 権限が無いときの `add`（`notDetermined`、`denied`） | どちらも error は `nil`、`IosNotificationManager.show` も投げない。`getPending` は 0。`notDetermined` の即時の分だけ配信済みに載り、拒否で消える。`notDetermined` で足した 30 秒の予約は、許可した後も pending 0 で発火しない | P2-10 |
| M3 | 貼り付けの拒否 | 4 つの API のどれでもダイアログが出る。`read` は成功で項目 1 件（型の一覧は空、`text` は `nil`）、`readData` は成功で `nil`、`loadItem` は `CLIPBOARD_LOAD_FAILED`（`NSItemProviderErrorDomain` -1200、underlying `PBErrorDomain` 13）、`detectValues` は `CLIPBOARD_DETECTION_FAILED`。答えないと `detectValues` は 5 秒で `CLIPBOARD_TIMED_OUT`（main は止まらない）。後から答えても 2 回目の完了は無い | P2-9、P2-24、6.1 |
| M4 | 添付 | 1 回目の `show` の後にファイルは無くなる（システムが移動する）。2 回目と `file:///nonexistent.png` は `attachmentLoadFailed`（`NSCocoaErrorDomain` 260）、`https://…` は `addRequestFailed`（`UNErrorDomain` 100） | 6.3 |
| M5 | 空の値と範囲外 | `.timeInterval(0, repeats: false)` と `.timeInterval(30, repeats: true)` は例外でプロセスが落ちる。空の `id` は成功を返して何も残らない。空の category とアクションは登録される。`.calendar` の項目なしは pending 0。`location` の半径 0 と空の識別子は pending 1 | P2-26、6.3 |
| M6 | 削除の後の `add` の順 | `authorized` で、`cancelAll` の完了から `show`、直接の `removeAll` の直後の `add`、`remove(["z"])` の直後の `add` のどれも、新しい要求が残った（各 OS 20/20）。**観測で、OS の保証は確かめていない** | P2-6 |
| M7 | `.provisional` | `[.alert, .sound, .badge, .provisional]` は警告なしで `provisional`。その後に `.provisional` なしで求めると警告が出て、`authorized` か `denied` になる | P2-27 |
| M8 | `timeInterval` の境界 | `(-1, false)`、`(-1, true)`、`(59.9, true)`、`(NaN, false)`、`(NaN, true)`、`(-∞, false)` は例外でプロセスが落ちる。`(60, true)`、`(∞, false)`、`(∞, true)` は pending に残る。`(0.001, false)` と最小の正の値は配信された | P2-26 |

### 0.3 第 2 版での反映（v1 のレビュー）

区分 A は 7 件（重なりを除く）で、どれも直した。全件と対応は `reviews/2026-11-03-ios-c-abi-c-abi-design-part2-review-v1.md`。

| 指摘 | 反映 |
|---|---|
| `shared` の `nonisolated` は 1 語では組めない | P2-12（M1 で確かめた） |
| `RequestTable` が第 1 部の状態機械と合わない | 5.3 を第 1 部 5.7 のとおりに直した |
| 配列の要素に `struct_size` が無く、広げられない | P2-5 |
| C だけでは OP-43 が来ない | P2-27 |
| 権限が無いときの主張に根拠が無い | M2 で測り、P2-10 を逆にした |
| 完了が無いと順序を確定できない | P2-6 を逆にした |
| `_async` の例外の食い違い | P2-3 を例外なしにした |

### 0.4 第 3 版での反映（v2 のレビュー）

区分 A は 1 件: `isValid` の範囲が決まっておらず、「今の口の動作は変えない」と矛盾した。P2-26 で「落ちる入力だけ」と決めた。B は、順序の未測定（M6）、権限のテストの空振り（12.1）、決まった後のアプリと `PROVISIONAL`（M7。P2-27）、第 1 部 2 章の例外（P2-10、7 章）、Swift の DocC（7 章）、`RELEASED` の後の `.file` の成功（5.3）、ヘッダーの規則（listener と install）。全件は `reviews/…-review-v2.md`。

### 0.5 第 4 版での反映（v3 のレビュー）

区分 A は無い。`isValid` の式（P2-26）、12.2 の行の抜けと TB-7 の条件、2 つのホストの分け方、細かい入口の値を直した（`reviews/…-review-v3.md`）。

## 1. 設計目的

- 第 1 部の約束（スレッド、寿命、`release`、前面、通知の delegate）の上に、**公開する C の関数・型・エラーの値をすべて決める**
- README 6 章の振る舞いの集合（操作 37、完了、自発のイベント 3、登録と解除、追加）を、C の関数の集合として閉じる（10 章）
- 今のブリッジの 43 関数との対応を、Unity の包み（2c）が使える形で示す（8.3）
- 2a の機械照合と 2b の実装が、この設計書だけを入力にできるようにする

## 2. スコープ

### 2.1 In scope

- `Common.h`（Windows・Android と同じ）、`Clipboard.h`、`Dialog.h`、`Notification.h`、`Share.h` の全宣言（付録 A）
- 受け口の機能ごとの役割と、Manager の呼び方（5 章）
- `IosLibrary` に足す口（7 章。P2-6、P2-12、P2-26）
- 8.3 の対応表と、`unity-native-plugin` に渡す範囲（16 章）

### 2.2 Out of scope

- 第 1 部で決めたもの（スレッド、`release` の状態機械、通知の delegate、前面の定義と表示の手順、文字列の変換、ビルドの設定）。変えない
- `IosLibrary` にあるがブリッジが公開していない機能（D-5）: `makePasteControl`、`ClipboardTimeouts` と `ClipboardLimits` の差し替え、`PresenterSelection` の選択、`foregroundPresentationOptions`（P2-20）
- macOS の C ABI（D-1）、App Extension（README 8.4）

## 3. 前提

### 3.1 企画書と第 1 部から

| 前提 | 出典 |
|---|---|
| C ABI の範囲は、今のブリッジの振る舞いの集合と、受け手の解除、起動のきっかけの通知の取得、Dialog と読み込みの要求ごとの取り消し、`openSettingsFor` のイベント | README D-5、6 章、P1-10、P1-24 |
| すべての関数はどのスレッドからでも呼べ、main を待たない。main で動かす処理は main から呼ばれても積む。例外は `ntk_notification_install` | 第 1 部 1.3 |
| 完了・イベント・受け付けた後の `release` は main で呼ぶ。入口で拒んだときは完了を呼ばず、`release` を呼び出しスレッドで呼ぶ | 第 1 部 1.3 |
| 受け付けた完了つきの操作は、プロセスが生きている限りちょうど 1 回完了する。表示を伴う操作は 5.13.1 の範囲で | 第 1 部 1.3、P1-14 |
| コールバックの引数は値か、所有権ごと渡すハンドル。戻り値は `void` | 第 1 部 5.8、AC-18 |
| `NOT_INITIALIZED` を返すのは、通知のイベントの受け手の登録と起動のきっかけの通知の取得だけ | P1-6 |
| 前面が要る操作の `NOT_FOREGROUND` は完了で返す | 第 1 部 5.10、5.13 |
| `ntk_last_system_code` と完了の `system_code` は常に 0 | D-13 |
| 文字列は厳密な UTF-8 で受け、出力は U+FFFD に置き換える | 第 1 部 5.9 |
| 今のブリッジを写さず、違いは対応表に書く | AC-23 |

### 3.2 不足前提

| ID | 不足している前提 | 扱い |
|---|---|---|
| G2-1 | 「今のブリッジ」をどの時点の姿として書くか | **今のソース（1b の後のライブラリの上のブリッジ）として読んだ結果を書く**。README 1.3・1.4 の一部（通知のスレッド、`showLoginDialog` の失敗、`setup()`）は 1b の前の姿。配布済みの 1.x の動作は 8.3 の範囲外で、1.x からの変化は 1b の結果にある。今のブリッジは `IosWorkspace` のビルドから外れており（D-22）、今のライブラリの上で組めるかは確かめていない |
| G2-2 | 貼り付けの許可の実機の振る舞い | **シミュレーターでは M3 で測った**。実機は `loadItem` の拒否（CB2）と MS-08 だけで、同期の `read` の拒否の値は測っていない。2.0.0 の前の実機の区切りで見る |
| G2-3 | ブリッジの C# の呼び方（呼ぶスレッド、`NULL` を渡す経路、`notificationSetup` を呼ぶ時期）。EditMode の JSON のテストの実際の数 | このリポジトリの外。2c の申し送りで数える。第 1 部 8 章の「実物を数えてから書く」はここでは満たせない（16 章） |
| G2-4 | 後ろで動いているアプリが他のアプリの内容を読んだときの実機の振る舞い | 測れていない（1b の記録 24.4 の D〜G は、戻ったときに要求が動いた見込み）。C ABI は判定しないので契約に影響しない。**マニュアルには「後ろでは貼り付けのダイアログが見えないことがある」とだけ書く** |

## 4. 実装方針の適用

### 4.1 common.md

| 方針 | 適合 | 内容 |
|---|---|---|
| 機能の公開の入口 | 適合 | 受け口は Manager だけを呼ぶ（P2-1）。`*UseCases` を呼ばない |
| システム API に合わせた同期・非同期 | 適合 | P2-2。9 章 |
| 層と依存の向き | 適合 | `IosLibraryCApi` → `IosLibrary` の一方向（第 1 部 5.1）。受け口は公開の API だけを使う（P1-2、C-1）。Clean Architecture の層は `IosLibrary` の中で変えない。機能の規則（trigger の妥当性）は `IosLibrary` に置く（P2-26） |
| ラッパーは機能のロジックを持たない | 適合 | 受け口と Unity の包みは補正をしない（P2-15）。**例外は P2-10 の権限の事前の確かめ**で、Android の AP-16 と同じく、Swift の口の振る舞いを変えない（K-9）ために受け口に置く |
| 検査の書き方 | 適合 | 12 章。足した検査は壊すと落ちることを確かめる |

### 4.2 ios.md

| 方針 | 適合 | 内容 |
|---|---|---|
| ログ（先頭のログ、秘密の値を伏せる） | 適合 | 受け口の関数は先頭でログを出す（第 1 部 5.15、P1-18）。Clipboard の本文、Dialog の入力とパスワード、通知の本文と userInfo、Share の内容は長さか件数だけ |
| Manager の役 | 適合 | 受け口は Manager を呼ぶだけ。Manager に足す口（7 章）は C 向けでなく Swift の利用者にも同じ |
| DocC | 適合 | capi の公開の関数は C のヘッダーに書く。Swift の受け口は `public` にしない（P1-1） |

## 5. 実装アーキテクチャ

### 5.1 受け口

第 1 部 5.3 と P1-1 のとおり、機能ごとに `<機能>/<機能>Entry.swift`（`@c @implementation` の関数だけ）と `<機能>/<機能>Receiver.swift`（検査・変換・Manager の呼び出し）に分ける。

| ファイル | 役 | 呼ぶ Manager |
|---|---|---|
| `Clipboard/ClipboardReceiver.swift` | 入力の検査と写し、main に積む、結果のハンドルを作る、`errorCode` の写し（P2-13）、監視の受け手を 1 つ持ち登録に配る | `IosClipboardManager` |
| `Dialog/DialogReceiver.swift` | 要求を写して `show(_:presenter:requestBox:completion:)` を呼ぶ。取り消し | `IosDialogManager` |
| `Notification/NotificationReceiver.swift` | `ntk_notification_install`、権限の事前の確かめ（P2-10）、操作、問い合わせ、イベントの登録と保持（AP-21） | `IosNotificationManager` |
| `Notification/NotificationContentBuilder.swift` | ビルダーの状態（Swift の値で持つ）と setter の検査 | - |
| `Notification/NotificationJson.swift` | userInfo の JSON の入出力（P2-7） | - |
| `Share/ShareReceiver.swift` | 要求を写して `share(content:presenter:completion:)` を呼ぶ | `IosShareManager` |
| `Common/Registry.swift` | 第 1 部 5.1、5.7 の登録と状態機械。要求の ID の表（ID → `Registration`。`Mutex`）。登録は `RequestBox` を持つ | - |
| `Common/StructReader.swift`、`Common/CApiString.swift` | 第 1 部 5.9（UTF-8 の入出力は `CApiString`）、1.1 の `struct_size` の読み方。配列の要素（P2-5） | - |

### 5.2 操作の流れ

```
C の入口（第 1 部 5.7 の手順 1〜3: 出力の NULL、struct_size、NULL、UTF-8、範囲を検査し、入力を Swift の値に深く写す）
  → 入口で拒むなら、戻り値でエラーを返し、完了を呼ばず、release を呼び出しスレッドで呼ぶ
  → Registration を作る。取り消せる操作は要求の ID と RequestBox を持たせて表に入れ、出力に書く
  → DispatchQueue.main.async（P1-4）
  → main: Registration が ACTIVE でなければ何もしない（完了と release は「外す」が行う。第 1 部 5.7）。ACTIVE なら MainActor.assumeIsolated で Manager を呼ぶ
  → Manager の完了（main）→ 結果のハンドルを作る → 完了のコールバック → tryRelease
```

- 通知の `show` などは、main のブロックの中で `Task { @MainActor in ... }` を始めて `async throws` を呼ぶ（Swift の設計書 8.9）。`Task` を取り消さない（Swift の設計書 10.2）
- **権限の事前の確かめ**（P2-10）: `show`、`update`、`schedule` は、その `Task` の中で `authorizationStatus()` を読み、許されていなければ `add` を呼ばずに `PERMISSION_DENIED` で完了する
- `NotificationContent` は `Sendable` でない（`userInfo` が `Any`）。**ビルダーは Swift の値と `NotificationUserInfoValue`（`Sendable`）を持ち、main のブロックの中で `NotificationContent` を作る**。生のポインタも `Any` も積まない
- `P1-17` の一覧に足すものは無い

### 5.3 取り消し

**第 1 部 5.7 のとおり**（第 1 版の「ID → `RequestBox` の表」は取り消した。Manager を呼ばなかった要求の完了と `release` が来ないため）。表は ID → `Registration` で、登録が箱を持つ。

| 操作 | 流れ |
|---|---|
| Dialog（OP-24） | 表を鍵の中で引き、`ACTIVE` → `CANCEL_REQUESTED` を CAS する。鍵の外で `IosDialogManager.shared.cancel(box)`（箱を閉じ、閉じる処理は `IosLibrary` が main に積む。S-15）。「外す」を main に積む。Dialog の上に画面が重なっていれば閉じない（P1-24） |
| Clipboard の読み込み（OP-12） | 同じ。`IosClipboardManager.cancelLoad(box)`（P2-12） |
| 最初の main の処理より前の取り消し | 挿入のブロックは `CANCEL_REQUESTED` を見て何もせず、「外す」が `CANCELED` で完了し `release` する（第 1 部 5.7）。**Dialog は出ず、読み込みは始まらない** |
| 開始と同時の取り消し | 箱の確かめの後に閉じられると、読み込みや表示は始まることがある。完了は `CANCELED` で、Dialog は閉じる。**貼り付けのダイアログが出ないことは約束しない**（`Progress.cancel()` は最善の努力） |

- **`.file` の成功を C が捨てるとき**: 箱が成功で閉じた後、C の完了の前に取り消されると、Swift は成功を返すが C は `CANCELED` を返す。**受け手に渡らなかった `.file` の成功は、受け口がファイルと親のフォルダーを消す**（ライブラリの `discard` は箱の競争に負けたときだけ動く）。**`RELEASED` の後に届いた成功も同じ**（箱を閉じてから `onClose` までの間に取り消しが割り込むと、「外す」が先に動く。第 1 部 5.7 の表の「何もしない」より先に消す。`user_data` には触らない）。渡す前に「渡した」と印を付ける（コールバックの中の取り消しで、渡したファイルを消さない）
- 知らない ID、完了の後の ID は何もせず `NONE`（第 1 部 1.3.1）。行は `tryRelease` で外す
- ID は `Atomic<UInt64>` の 1 から増やし、使い回さない（AC-17）

### 5.4 イベント

- `_add_*_listener` は登録を作り、main に積む
- **通知は、その種類の最初の登録のブロックの中でだけ `IosLibrary` の受け手を 1 つ足し、以後は外さない**（AP-21。第 1 部 5.12.7）。登録を帳簿に入れた後に足す（足す途中で配られるので）
- 通知の操作と設定の要求は、`ACTIVE` な登録が無い間は受け口が 32 件まで保ち（Swift の口と同じ数。古いものから捨てる）、次の登録の挿入のブロックの中で配る
- **配っている途中に届いたイベント**（コールバックの中から同期に届いたもの）は、その場で配らない。保っているものがあれば、その後ろに並ぶ。無ければ、今の配送が終わった後に、届いた順に、そのとき `ACTIVE` な登録へ配る。`ACTIVE` な登録が無ければ保つ（32 件の上限はこの「保つ」の数）。どの登録も同じ順で受ける（TB-2 のレビュー）
- Clipboard の変更は、`start_observing_async` がライブラリに渡す受け手から配る。保たない（Android と同じ。Swift の口も保たない）
- 1 つの受け手が帳簿のその種類の登録すべてに配る。ハンドルは登録ごとに別に作る（受け手が `_free` するので）
- `_listener_remove(NULL)` は何もしない

### 5.5 どのスレッドで動くか

「非同期」は、入口のスレッド・積む先・実行する所・完了のスレッドが別である。**約束するのは、UIKit の操作と完了が main で動くことまで**。main のブロックの中で始めた操作の全体が main で動くとは約束しない。

| 操作 | 実行する所（今の `IosLibrary`） |
|---|---|
| Clipboard | ペーストボードは main actor。画像の準備は main の外に出ることがある |
| 通知の `show` など、問い合わせ、削除 | nonisolated の `async`。callback の形は完了を main に返す |
| category | 呼んだ時点で積む（同期）、nonisolated の Task で流す、完了は main |
| 権限の要求、設定の画面 | 前面の判定は main actor。Repository の処理は main の外に出ることがある。`UIApplication.open` は main |
| Share | 項目の構築と画像の読み込みは nonisolated。表示と完了は main actor |

## 6. サブ機能別詳細設計

**入口と完了の分け方の基準**（AP-19）: **入口は C の値を Swift の値に写すための検査と、C の入力の形の規則だけを行う**。**内容の妥当性（空白だけ、Clipboard の URL の scheme、色の範囲、ファイルの有無、general の削除）は `IosLibrary` が判定して完了で返す。** 同じ値が入口と完了の両方から来うるので、呼ぶ人は両方を見る。

| 入口で拒むもの | 例 | Swift の口との違い |
|---|---|---|
| 写すための検査 | `NULL`、UTF-8、`struct_size`、列挙とビットの範囲、配列の件数 0 | 型で表せないので無い |
| ライブラリが公開する純粋な検査 | `NotificationTrigger.isValid`（P2-26） | 同じ（Swift は完了で `invalidTrigger`） |
| **C の入力の形の規則**（黙って失うのを防ぐ。P2-15） | 空の `id`・識別子、数値の範囲（`badge`、`relevance_score`、緯度と経度と半径）、`calendar_fields` の 0、`file://` でない添付、`MULTI_REPRESENTATION` の重複 | **Swift の口は受け付ける**（M4、M5。何も残らないか、OS の失敗になる） |

### 6.1 Clipboard（`Clipboard.h`）

**対象の選び方**（`ntk_clipboard_scope`。`NULL` は general）: `kind` は `GENERAL`、`NAMED`、`UNIQUE`。`NAMED` と `UNIQUE` は `name` が必須で、`NULL` と空文字は入口で `INVALID_PARAMETER`。`ntk_clipboard_remove_pasteboard_async` の `scope` は `NULL` を受けない（今のブリッジの「省くと general で `CANNOT_REMOVE_GENERAL`」をやめる）。

**書き込む内容**（`ntk_clipboard_write_content`）: `kind` で読む項目が決まり、ほかの項目は読まない。

| `kind` | 読む項目 | 入口の検査 | `IosLibrary` の検査（完了で返す） |
|---|---|---|---|
| `PLAIN_TEXT` | `text` | `NULL` | 64 MiB 超は `CONTENT_TOO_LARGE`（URL と色のほか） |
| `HTML` | `text`（plain）、`html` | `NULL` | 空白だけの `html` は `EMPTY_CONTENT` |
| `URL` | `url` | `NULL` | http、https、file の外は `INVALID_URI` |
| `IMAGE_FILE` | `path` | `NULL`、空文字（P2-9 の (8)） | 無いファイルは `FILE_NOT_FOUND`、読めないのは `IMAGE_LOAD_FAILED` |
| `IMAGE_DATA` | `data`、`data_size`、`ut_type` | `ut_type` の `NULL`。`data` が `NULL` で大きさが 0 でない | 大きさ 0 は `EMPTY_CONTENT`、`INVALID_TYPE`、`INVALID_IMAGE_DATA` |
| `COLOR` | `red`、`green`、`blue`、`alpha` | - | 0.0〜1.0 の外は `INVALID_COLOR`。**`alpha` は必須で、0.0 は透明** |
| `CUSTOM_DATA` | `data`、`data_size`、`ut_type` | `IMAGE_DATA` と同じ | 大きさ 0 は `EMPTY_CONTENT`、`INVALID_TYPE` |
| `MULTIPLE_TEXT` | `texts`、`text_count` | 件数 0 は `EMPTY_ITEMS`（入口）。`NULL` の要素 | - |
| `MULTI_REPRESENTATION` | `representations`、`representation_count` | 件数 0 は `EMPTY_ITEMS`（入口）。`ut_type` の `NULL`。`data` が `NULL` で大きさが 0 でない。同じ `ut_type` の重複は `INVALID_PARAMETER`（`[String : Data]` で黙って失うので） | 大きさ 0 の表現は `EMPTY_CONTENT`、`INVALID_TYPE` |

**コピーの選択肢**（`ntk_clipboard_copy_options`。`NULL` と `struct_size` のほかが 0 は `.default`）: `not_local_only`（既定は `localOnly: true`。E-9 の反転）、`has_expiration` と `expiration_unix_seconds`（有限でなければ入口で `INVALID_PARAMETER`）。過去の日時は `INVALID_EXPIRATION`。

| 操作 | 形 | 中身 |
|---|---|---|
| `copy_async`、`append_async` | 非同期 | `append` は選択肢を取らない（今のライブラリと同じ） |
| `read_async`、`read_data_async` | 非同期。結果はハンドル / バイト列 | **ほかのアプリの内容では、利用者が答えるまで main が止まる**（MS-08。前面で 44 秒止まり、アプリは終了させられなかった。P2-24）。**拒否は失敗にならない**: `read_async` は `NONE` で項目 1 件（型の一覧は空、文字列は `NULL`）、`read_data_async` は `NONE` で `NULL`（M3） |
| `get_snapshot_async` | 非同期 | `matching_types` が `NULL` か件数 0 なら、一致の添字は無い（`_has_matching` が 0）。`NULL` の要素は `INVALID_PARAMETER` |
| `clear_async` | 非同期 | |
| `create_pasteboard_async(kind, name, ...)` | 非同期 | `NAMED` は `name` が必須。`UNIQUE` は `name` を読まない。`GENERAL` は `INVALID_PARAMETER`。完了の `ntk_string` が以後の `scope.name` |
| `remove_pasteboard_async` | 非同期 | general は `CANNOT_REMOVE_GENERAL`。無い名前は成功（今のまま） |
| `detect_patterns_async(patterns, ...)` | 非同期。完了の値はビットの組 | `patterns` は `NTK_CLIPBOARD_PATTERN_*` の組。0 は `EMPTY_PATTERNS`（入口）、知らないビットは `INVALID_PARAMETER`。5 秒で `TIMED_OUT` |
| `detect_values_async(patterns, ...)` | 非同期。JSON（P2-8） | 同上。**内容を読むので貼り付けのダイアログが出て、答えないと 5 秒で `TIMED_OUT`、拒否は `DETECTION_FAILED`**（M3。P2-24）。main は止まらない |
| `load_item_async(kind, ut_type, ...)` | 非同期。出力に要求の ID | `kind` は `TEXT`、`URL`、`IMAGE`、`FILE`。`FILE` は `ut_type` が必須。**時間切れ（15 秒）に利用者が答える時間も入る**（P2-24）。拒否は `LOAD_FAILED`。main は止まらない |
| `cancel_load(id)` | どのスレッドからでも。待たない | 取り消した読み込みは `CANCELED` で完了する（5.3） |
| `start_observing_async(scope, ...)` | 非同期 | 同時に 1 つ。2 回目は前を止める。**2 回目が `UNAVAILABLE` で失敗すると 1 回目も止まったまま**（今のライブラリの動作。変えない。ヘッダーに書く） |
| `stop_observing_async(...)` | 非同期 | 失敗しない。監視していなくても `NONE`。積まれた配送も届かない。**別の部品が始めた監視も止まる**（P2-16） |
| `check_foreground_change_async(scope, ...)` | 非同期。完了の値は 0 か 1 | 前面かどうかを見ない。初回は 0。解決できない pasteboard は 0（今のまま） |
| `add_change_listener`、`listener_remove` | 第 1 部 5.7 | 登録しただけでは監視は始まらない（P2-16）。保たない |

**読み込みの結果**（`ntk_clipboard_loaded_item`）: `_kind` で読むものが決まる。`FILE` は**一時ファイルとその親のフォルダーの持ち主が受け手になる**（`_free` は消さない。今のブリッジと同じ。5.3）。

**変更のイベント**（`ntk_clipboard_change`）: `_kind`（`CHANGED`、`REMOVED`）、対象の `scope`、足された型と消された型。`changedDetectedOnForeground` は `IosLibrary` の中で作られないので、値を置かない。

**`detect_values_async` の JSON**（P2-8。ABI の一部で、キーは足すことはあっても変えない。キーはいつも全部ある。ゴールデンのテストで守る）:

| キー | 型 | 無いとき |
|---|---|---|
| `detectedPatterns` | 文字列の配列（`ClipboardDetectionPattern` の `rawValue`。順は決まらない） | `[]` |
| `probableWebURL`、`probableWebSearch` | 文字列 | `null` |
| `number` | 数 | `null` |
| `links` | 文字列の配列 | `[]` |
| `emailAddresses`、`phoneNumbers` | `{value: 文字列, label: 文字列か null}` の配列 | `[]` |
| `postalAddresses` | `{street, city, state, postalCode, country}`（どれも文字列か `null`）の配列 | `[]` |
| `calendarEvents` | `{startDate, endDate}`（小数秒つきの ISO 8601 か `null`）、`{startTimeZone, endTimeZone}`（文字列か `null`）、`isAllDay`（真偽）の配列 | `[]` |
| `flightNumbers` | `{airline, flightNumber}`（文字列）の配列 | `[]` |
| `moneyAmounts` | `{amount: 数, currency: 文字列}` の配列 | `[]` |
| `shipmentTrackingNumbers` | `{carrier, trackingNumber}`（文字列）の配列 | `[]` |

### 6.2 Dialog（`Dialog.h`）

| 操作 | 形 | 中身 |
|---|---|---|
| 6 種の `ntk_dialog_show_*_async` | 非同期。出力に要求の ID（`NULL` 可。P2-21） | 前面が要る。`.foreground` と箱を渡す。`request` の `NULL` は `INVALID_PARAMETER` |
| `ntk_dialog_cancel` | どのスレッドからでも。待たない | 5.3 |

**結果**（`ntk_dialog_result`。`error == NONE` のときだけ渡す。受け手が `_free` する）:

| `_button` | 読める値 |
|---|---|
| `NTK_DIALOG_BUTTON_POSITIVE` | `_button_text`。テキスト入力は `_text`、ログインは `_username`、`_password` |
| `NTK_DIALOG_BUTTON_NEGATIVE` | `_button_text`（入力は無い） |
| `NTK_DIALOG_BUTTON_DESTRUCTIVE` | `_button_text` |
| `NTK_DIALOG_BUTTON_OPTION` | `_button_text`、`_option_index`（0 から。ほかの種類では -1） |

- Android の `POSITIVE` と `NEGATIVE` は同じ意味なので同じ名前にする。**Android の `_answer` と `DISMISSED` は無い**: iOS のアラートは外側のタップで閉じない。アクションシートの外側のタップはキャンセルの handler が呼ばれて `NEGATIVE` になる見込み（測っていない。2b の 12.2 で確かめる）。外から閉じられたときは `CANCELED_BY_SYSTEM`
- **押したボタンを値で返す**（今のブリッジはラベルの文字列だけで、同じ文言を区別できなかった）
- アクションシートの基点はいつも最上位の ViewController の view の中央（P1-13）。**マルチウィンドウの iPad で利用者の期待と違う位置に出ることがある**（1b の記録 23.1。マニュアルの候補）
- アクションシートの `option_count` は 0 でもよい（キャンセルだけ）。`options` が `NULL` で件数が 0 でない、`NULL` の要素は `INVALID_PARAMETER`
- 同時の要求は第 1 部 5.13.2 の手順（P1-12）

### 6.3 Notification（`Notification.h`）

**内容のビルダー**（`ntk_notification_content`）: `_create(id, title, &out)` で必須の 2 つを受け（`id` の空文字は `INVALID_PARAMETER`。M5 で何も残らなかった）、ほかは `NotificationContent` の既定値で始まる（`sound` は `.default`）。`_set_*` で上書きする。スレッドセーフでない（第 1 部 1.3.1）。**setter は受け取った文字列を呼び出しの中で写す**。setter の文字列の `NULL` は「設定しない（既定に戻す）」。操作は渡された時点の写しを使い、利用者は戻った後にビルダーを解放・変更してよい（第 1 部 1.1）。

| 関数 | `NotificationContent` の項目 | 検査 |
|---|---|---|
| `_set_subtitle`、`_set_body`、`_set_category`、`_set_thread`、`_set_target_content`、`_set_filter_criteria` | `subtitle`、`body`、`categoryIdentifier`、`threadIdentifier`、`targetContentIdentifier`、`filterCriteria` | UTF-8 |
| `_set_badge(count)` | `badge` | 0 以上。-1 で未設定に戻す。ほかの負の値は `INVALID_PARAMETER` |
| `_set_sound(kind, name)` | `sound` | `DEFAULT`、`DEFAULT_CRITICAL`、`NAMED`（`name` が必須）、`NONE`（`nil`。今のブリッジでは表せなかった） |
| `_set_interruption_level(level)` | `interruptionLevel` | `NOT_SET`（`nil`）、`PASSIVE`、`ACTIVE`、`TIME_SENSITIVE`、`CRITICAL`。ほかは `INVALID_PARAMETER`（P2-15） |
| `_set_relevance_score(score)` | `relevanceScore` | 有限で 0.0〜1.0。ほかは `INVALID_PARAMETER` |
| `_set_user_info_json(json)` | `userInfo` | P2-7。`NULL` は空に戻す |
| `_add_attachment(identifier, file_url)` | `attachments` | `NULL`、`file://` の URL でないものは `INVALID_PARAMETER`（`https://` は完了の `ADD_REQUEST_FAILED` になるので入口で拒む。M4）。無いファイルは操作の完了で `ATTACHMENT_LOAD_FAILED`（`bb365277`）。**システムがファイルを移動するので、同じビルダーの 2 回目の操作は `ATTACHMENT_LOAD_FAILED` になる**（M4） |

**userInfo の JSON**（P2-7）:

| 値（`NotificationUserInfoValue`） | 入力の JSON | 出力の JSON |
|---|---|---|
| `string`、`bool` | 文字列、真偽 | 同じ |
| `integer`、`unsignedInteger`、`double` | 数。`1e400` のように解けないものは `INVALID_PARAMETER`。`1.0` が整数になるかは `JSONSerialization` のまま | 数。**有限でない `double` は `null`** |
| `array`、`dictionary` | 配列、オブジェクト | 同じ |
| `date` | 作れない（文字列になる） | **小数秒つきの ISO 8601 の文字列**（`detect_values_async` と同じ） |
| `data` | 作れない（文字列になる） | **Base64 の文字列** |
| JSON の `null` | **`INVALID_PARAMETER`**（入れ子も） | 有限でない数のときだけ出る |

- 最上位が配列などオブジェクトでないものは `INVALID_PARAMETER`
- **予約のキー `com.jonghyunkim.nativetoolkit` を拒むのは最上位だけ**（ライブラリと同じ。定数は internal なので受け口に写しを持ち、テストで同じことを確かめる）
- **入力と出力は対称でない**: 受け取った JSON をそのまま渡すと、`null` を含むときは拒まれる

**trigger**（`ntk_notification_trigger`。`show_async` と `update_async` では `NULL` は即時）: 下の検査はすべて入口で `INVALID_PARAMETER`。`TIME_INTERVAL` は `NotificationTrigger.isValid`（P2-26）と、有限であること（C の入力の形の規則）を見る。ほかは C の入力の形の規則（6 章の冒頭）。`schedule_async` の `trigger` の `NULL` も `INVALID_PARAMETER`。

| `kind` | 読む項目 | 検査 |
|---|---|---|
| `TIME_INTERVAL` | `interval_seconds`、`repeats` | 有限で 0 より大きい。`repeats` のときは 60 以上（M5。範囲外はプロセスが落ちる） |
| `CALENDAR` | `calendar_fields`（`NTK_NOTIFICATION_CALENDAR_*` の組）、`year`〜`second`、`repeats` | `calendar_fields` は 0 でなく（M5。何も残らない）、知らないビットが無い。ビットの立っていない項目は読まない（0 時と未設定を区別するため） |
| `LOCATION` | `location_identifier`、`latitude`、`longitude`、`radius`、`not_notify_on_entry`、`notify_on_exit` | 識別子の `NULL` と空文字、有限、緯度 ±90、経度 ±180、半径が 0 より大きい、入ると出るの両方が知らせない組（決して来ない見込み。測っていない）。既定は入るときに知らせ、出るときは知らせない（E-9）。**位置の権限と Info.plist の説明が要る**（ヘッダーに書く） |

**category**（`ntk_notification_category`）: `identifier`（必須）、`actions` と `action_count`、`text_input_actions` と `text_input_action_count`、`options`。`NULL` と空文字の識別子、知らないビットは `INVALID_PARAMETER`（今のブリッジは黙って捨てた。P2-15）。ビットの値は `NotificationActionOptions` と `NotificationCategoryOptions` の `rawValue` と同じ。`title`、`button_title`、`placeholder` は `NULL` を拒み、空文字は通す。`action_count` と `text_input_action_count` の 0 は許す（Swift の既定）。削除の関数の識別子は `NULL` だけを拒み、空文字は `NONE`（何も消えない）。

| 操作 | 形 | 中身 |
|---|---|---|
| `install` | 同期。main だけ | 第 1 部 1.4 |
| `show_async(content, trigger, ...)` | 非同期 | 要求の識別子は `content.id`。`trigger` があれば発火のときに届く。権限が無ければ `PERMISSION_DENIED`（P2-10） |
| `update_async(identifier, content, trigger, ...)` | 非同期 | pending を消してから足す。無い識別子でも足す。`content.id` は使わない。`trigger` の `NULL` は即時（今のまま）。**`ADD_REQUEST_FAILED` のとき、前の要求はもう無い**。権限が無ければ `PERMISSION_DENIED` で、前の要求は消さない |
| `schedule_async(identifier, content, trigger, ...)` | 非同期 | `trigger` は必須。`content.id` は使わない。権限が無ければ `PERMISSION_DENIED` |
| `remove_async`、`remove_all_async`、`cancel_scheduled_async`、`cancel_all_scheduled_async` | 非同期（P2-6）。失敗の値は無い | `remove` は配信済みを、`cancel_scheduled` は予約を消す。**`remove_all` と `cancel_all_scheduled` はホストが自分で出した通知まで消す**（Swift の設計書 8.9）。**続けて通知を足すなら完了の後に**（順序は完了で繋ぐ） |
| `get_scheduled_async`、`get_delivered_async` | 非同期。`ntk_notification_list` | 識別子・題・副題・本文・category。`get_delivered_async` は時刻も。**userInfo と trigger は返さない**（今のブリッジと同じ。D-5） |
| `request_permission_async(options, ...)` | 非同期。値は 0 か 1 | P2-27。拒否は `NONE` で 0。`authorized`、`provisional`、`ephemeral` は 1。未決で前面でなければ `NOT_FOREGROUND`。取り消せない |
| `get_authorization_status_async` | 非同期。値は `ntk_notification_authorization_status` | 失敗しない |
| `has_permission_async` | 非同期。値は 0 か 1 | `authorized` か `provisional` で 1（**`ephemeral` は 0 で、`request_permission_async` と `show_async` の扱いと違う**。今のライブラリの動作） |
| `open_settings_async` | 非同期 | 前面が要る。今のブリッジは完了も前面の確かめも無かった |
| `set_badge_count_async(count, ...)` | 非同期 | 負の値は `INVALID_PARAMETER`（入口） |
| `register_category_async`、`remove_category_async` | 非同期 | **完了は書き込みと 1 回の読み返しの後**（Swift の設計書の `NotificationCategoryQueue`）。読み返しに無くても `NONE` で、ログに出るだけ。今のブリッジは積んだだけで成功を返した。失敗の値は無い |
| `add_interaction_listener`、`add_settings_request_listener`、`listener_remove` | 第 1 部 5.7 | delegate が一度も入っていなければ `NOT_INITIALIZED`（P1-6）。保ち方は 5.4。**設定の要求は `.providesAppNotificationSettings` を求めたアプリにだけ来る**（P2-27） |
| `get_launch_response_async` | 非同期 | P2-19 |

**イベントの値**（所有権ごと渡すハンドル。受け手が `_free` する）:

| ハンドル | 読める値 |
|---|---|
| `ntk_notification_interaction` | `_kind`、`_notification_id`、`_action_id`、`_category_id`（無ければ `""`）、`_user_text`（`TEXT_INPUT` のときだけ。空の返信は `""`）、`_user_info_json`（`{}` もある。印は外してある）、`_is_launch` |
| `ntk_notification_settings_request` | `_notification_id`（設定の App から来たら `NULL`） |

`_kind` は `userText` があれば `TEXT_INPUT`、`actionIdentifier` が `UNNotificationDefaultActionIdentifier` なら `BODY_TAP`、`UNNotificationDismissActionIdentifier` なら `DISMISS`、ほかは `ACTION`。

**背景のアクションの直後に利用者がアプリを前面に出すと、その応答が `_is_launch` で来ることがある**（1b の記録 23.3。マニュアルの候補）。

### 6.4 Share（`Share.h`）

| 操作 | 形 | 中身 |
|---|---|---|
| `ntk_share_content_async(request, ...)` | 非同期 | 前面が要る。取り消せない（P1-24）。完了は `(user_data, error, system_code, result)` |

- `ntk_share_request`: `items` と `item_count`、`subject`、`preview_title`、`excluded_activity_types` と件数（`NULL` で件数が 0 でない、`NULL` の要素は `INVALID_PARAMETER`）。件数 0 は `EMPTY_CONTENT`（入口）。項目の `kind` の範囲外と `value` の `NULL` は `INVALID_PARAMETER`（今のブリッジは未知の `type` を黙って捨てた。P2-15）
- 結果（`ntk_share_result`。`error == NONE` のときだけ渡す）: `_completed`（利用者がシートを閉じたのは 0）、`_activity_type`（選ばれた活動の識別子。無ければ `NULL`）、`_free`
- 基点は 6.2 と同じ（P1-13）
- 無いファイルは `FILE_NOT_FOUND`（`file`）、`IMAGE_LOAD_FAILED`（`image`）。今のライブラリの動作

## 7. 変える文書とコード

2b の前に直す（13 章の TB-0）。**`IosLibrary` の変更は足すだけで、普通の呼び出しの動作は変えない**（`results/swiftinterface/` の基準を取り直す。関数の参照の破壊は Swift の設計書 3.3）。

| 対象 | 変えること |
|---|---|
| `IosClipboardManager` | `nonisolated public static func cancelLoad(_ box: RequestBox)` を足す（P2-12）。DocC の「`shared` を main で読み、参照を持って呼ぶ」を直し、`cancelLoad(_:)` のリンクを曖昧でなくする |
| `IosNotificationManager` | `removeDelivered`、`removeAllDelivered`、`cancelScheduled`、`cancelAllScheduled` に `completion: (@MainActor @Sendable () -> Void)? = nil` を足す（P2-6。`registerCategory` と同じ形）。**`show`、`update`、`schedule` の DocC に、権限が無いと成功を返して pending に残らないことを書く**（M2。P2-10） |
| `NotificationTrigger`、`NotificationError`、`NotificationRepositoryImpl` | `isValid` を足す（偽は落ちる入力だけ）。`invalidTrigger` の case を足し、`makeTrigger` の前で投げる（P2-26）。**今まで落ちていた入力だけが `invalidTrigger` の失敗になる**（1b の記録に足す） |
| `Common/Domain/PresenterSelection.swift` の DocC の Note | 「権限の要求と設定の画面の口は後のコミットで足す」は古いので消す |
| 第 1 部 1.1 の表、5.10、8 章 | 「Share と Clipboard に `CANCELED`」を「Clipboard に `CANCELED`」に直す（P2-11）。「Notification に iOS だけの値が 1 つ」「iOS で新しく足す値: `WRONG_THREAD`」に 17〜20 を足す。`CANCELED`、`CANCELED_BY_SYSTEM` の例は Notification では欠番と書き足す（P2-10） |
| 第 1 部 5.13.1 | 「権限の要求・設定の画面も同じ箱」は `IosLibrary` の中の話で、C から取り消せないと書き足す |
| 第 1 部 9.1 の S-6 | 箱を取るのは Dialog と読み込みだけ（Swift の設計書 18.1 の 12 の決め直し）と書き足す |
| 第 1 部 1.1 | 配列の要素の `struct_size` の読み方（P2-5）を `struct_size` の行に足す |
| 第 1 部 2 章 | 「振る舞いは Swift の API が決める」の例外に、権限の事前の確かめ（P2-10）を足す |
| 第 1 部 5.7、6 章 | 列挙を返す読み取りの `NULL` は -1（P2-29）。`RELEASED` の後の `.file` の成功（5.3） |
| 第 1 部 6 章 | 後ろから呼ぶ口を「サンプルに `#if DEBUG`」から、C を呼ぶテスト用のアプリに変える（TB-2b。サンプルは Swift の API だけを使う） |
| 1b の結果 7 章、1b の記録 10 章の第 2 部の行、12 章の B-1 | 「箱を直接閉じる」を P2-12 に直す |
| Swift の設計書 10.1 | 「第 2 部」の行に 11 章の名前を書く。`attachmentLoadFailed` の場面に無いファイル（`bb365277`）を足す。`invalidTrigger` を足す |
| README 6 章 | 振る舞いの集合の表をこの設計書の 10 章へ指す |
| README 3.3 | Share は名前を合わせられない（P2-4）と書く |

## 8. API 設計

### 8.1 OP ごとの C 関数

戻り値の型は機能のエラー（`ntk_clipboard_error` / `ntk_dialog_error` / `ntk_notification_error` / `ntk_share_error`）。`_listener_remove` は `void`。完全な宣言は付録 A。「Swift の口」は受け口が呼ぶ Manager の口（P2-1）。「（受け口の帳簿）」の行は OP-16、OP-17、OP-44 だけで、Swift の口を呼ばない（2a が読む）。完了つきの関数は最後に `callback, user_data, release` を取り、8.1 では `...` と書く。`callback` の `NULL` は `INVALID_PARAMETER`（P2-28）。

| OP | Swift の口 | C 関数 | 変換 |
|---|---|---|---|
| OP-01 | `IosClipboardManager.copy(_:options:scope:completion:)` | `ntk_clipboard_copy_async(content, options, scope, ...)` | 構造体 → `ClipboardContent`、`ClipboardCopyOptions`、`PasteboardScope` |
| OP-02 | `append(_:scope:completion:)` | `ntk_clipboard_append_async(content, scope, ...)` | 同上 |
| OP-03 | `read(scope:completion:)` | `ntk_clipboard_read_async(scope, ...)` | `ClipboardReadResult` → ハンドル |
| OP-04 | `readData(utType:scope:completion:)` | `ntk_clipboard_read_data_async(ut_type, scope, ...)` | `Data?` → `ntk_bytes`（無ければ `NULL`） |
| OP-05 | `snapshot(matchingTypes:scope:completion:)` | `ntk_clipboard_get_snapshot_async(matching_types, matching_type_count, scope, ...)` | `ClipboardSnapshot` → ハンドル |
| OP-06 | `clear(scope:completion:)` | `ntk_clipboard_clear_async(scope, ...)` | - |
| OP-07 | `createPasteboard(_:completion:)` | `ntk_clipboard_create_pasteboard_async(kind, name, ...)` | → `PasteboardCreationRequest`。`PasteboardScope` の名前 → `ntk_string` |
| OP-08 | `removePasteboard(_:completion:)` | `ntk_clipboard_remove_pasteboard_async(scope, ...)` | `scope` は `NULL` を受けない |
| OP-09 | `detectPatterns(_:scope:completion:)` | `ntk_clipboard_detect_patterns_async(patterns, scope, ...)` | ビットの組 ↔ `Set<ClipboardDetectionPattern>` |
| OP-10 | `detectValues(_:scope:completion:)` | `ntk_clipboard_detect_values_async(patterns, scope, ...)` | `ClipboardDetectedValues` → JSON の `ntk_string`（P2-8） |
| OP-11 | `loadItem(_:scope:requestBox:completion:)` | `ntk_clipboard_load_item_async(kind, ut_type, scope, ..., out_request_id)` | → `ClipboardLoadRequest`。`ClipboardLoadedItem` → ハンドル |
| OP-12 | `IosClipboardManager.cancelLoad(_:)`（`static`。P2-12） | `ntk_clipboard_cancel_load(request_id)` | ID → `Registration` の `RequestBox` |
| OP-13 | `startObserving(scope:onEvent:)` | `ntk_clipboard_start_observing_async(scope, ...)` | 受け手は受け口の 1 つ（P2-16） |
| OP-14 | `stopObserving()` | `ntk_clipboard_stop_observing_async(...)` | - |
| OP-15 | `checkForegroundChange(scope:)` | `ntk_clipboard_check_foreground_change_async(scope, ...)` | `Bool` → 0 / 1 |
| OP-16 | （受け口の帳簿） | `ntk_clipboard_add_change_listener(callback, user_data, release, out_listener)` | `ClipboardChangeEvent` → ハンドル |
| OP-17 | （受け口の帳簿） | `ntk_clipboard_listener_remove(listener)` | 第 1 部 5.7 の解除 |
| OP-18 | `IosDialogManager.show(_:presenter:requestBox:completion:)` | `ntk_dialog_show_alert_async(request, ..., out_request_id)` | 構造体 → `DialogRequest.alert`。`DialogAnswer` → ハンドル |
| OP-19 | 同上 | `ntk_dialog_show_confirm_async(request, ..., out_request_id)` | → `.confirm` |
| OP-20 | 同上 | `ntk_dialog_show_destructive_async(request, ..., out_request_id)` | → `.destructive` |
| OP-21 | 同上 | `ntk_dialog_show_action_sheet_async(request, ..., out_request_id)` | → `.actionSheet` |
| OP-22 | 同上 | `ntk_dialog_show_text_input_async(request, ..., out_request_id)` | → `.textInput` |
| OP-23 | 同上 | `ntk_dialog_show_login_async(request, ..., out_request_id)` | → `.login` |
| OP-24 | `IosDialogManager.cancel(_:)` | `ntk_dialog_cancel(request_id)` | ID → `Registration` の `RequestBox` |
| OP-25 | `IosNotificationManager.installDelegate()` | `ntk_notification_install()` | `notMainThread` → `WRONG_THREAD` |
| OP-26 | `show(content:trigger:) async throws` | `ntk_notification_show_async(content, trigger, ...)` | ビルダー → `NotificationContent`。構造体 → `NotificationTrigger?`。先に権限を確かめる（P2-10） |
| OP-27 | `update(identifier:content:trigger:) async throws` | `ntk_notification_update_async(identifier, content, trigger, ...)` | 同上 |
| OP-28 | `schedule(content:trigger:identifier:) async throws` | `ntk_notification_schedule_async(identifier, content, trigger, ...)` | 同上 |
| OP-29 | `removeDelivered(identifier:completion:)`（足す。P2-6） | `ntk_notification_remove_async(identifier, ...)` | - |
| OP-30 | `removeAllDelivered(completion:)`（足す） | `ntk_notification_remove_all_async(...)` | - |
| OP-31 | `cancelScheduled(identifier:completion:)`（足す） | `ntk_notification_cancel_scheduled_async(identifier, ...)` | - |
| OP-32 | `cancelAllScheduled(completion:)`（足す） | `ntk_notification_cancel_all_scheduled_async(...)` | - |
| OP-33 | `getScheduled(completion:)` | `ntk_notification_get_scheduled_async(...)` | `[ScheduledNotification]` → ハンドル |
| OP-34 | `getDelivered(completion:)` | `ntk_notification_get_delivered_async(...)` | `[ActiveNotification]` → ハンドル |
| OP-35 | `requestPermission(options:presenter:completion:)` | `ntk_notification_request_permission_async(options, ...)` | ビットの組 → `UNAuthorizationOptions`（P2-27）。`Result<Bool, NotificationError>` → `granted` とエラー |
| OP-36 | `authorizationStatus(completion:)` | `ntk_notification_get_authorization_status_async(...)` | 列挙の値（`ntk_notification_status_fn`） |
| OP-37 | `hasPermission(completion:)` | `ntk_notification_has_permission_async(...)` | `Bool` → 0 / 1（`ntk_notification_permission_fn`） |
| OP-38 | `openNotificationSettings(presenter:completion:)` | `ntk_notification_open_settings_async(...)` | `Result<Void, NotificationError>` |
| OP-39 | `setBadgeCount(_:) async throws` | `ntk_notification_set_badge_count_async(count, ...)` | - |
| OP-40 | `registerCategory(_:completion:)` | `ntk_notification_register_category_async(category, ...)` | 構造体 → `NotificationCategory` |
| OP-41 | `removeCategory(identifier:completion:)` | `ntk_notification_remove_category_async(identifier, ...)` | - |
| OP-42 | `responses.addListener(_:)` | `ntk_notification_add_interaction_listener(callback, user_data, release, out_listener)` | `NotificationResponseEvent` → ハンドル（P2-18） |
| OP-43 | `settingsRequests.addListener(_:)` | `ntk_notification_add_settings_request_listener(callback, user_data, release, out_listener)` | `NotificationSettingsRequest` → ハンドル |
| OP-44 | （受け口の帳簿） | `ntk_notification_listener_remove(listener)` | 第 1 部 5.7 の解除 |
| OP-45 | `launchResponse()` | `ntk_notification_get_launch_response_async(...)` | `NotificationResponseEvent?` → ハンドルか `NULL` |
| OP-46 | `IosShareManager.share(content:presenter:completion:)` | `ntk_share_content_async(request, ...)` | 構造体 → `ShareContent`。`ShareResult` → ハンドル |

### 8.2 公開する関数の全体（134）

8.1 の 46 操作のほかに、出力のハンドルの読み取りと解放、ビルダーの関数を公開する。**ヘッダー、付録 A、ビルドの後の公開シンボル（`nm -gU` の `_ntk_*`）はこの表と一致させる**。群の関数は、`_` で始まる末尾を「〜の後に続く」の名前に付けて読む（AP-15）。

| ヘッダー | 群 | 関数 | 数 |
|---|---|---|---|
| `Common.h` | 版とエラー | `ntk_version`、`ntk_last_system_code` | 2 |
| `Common.h` | `ntk_string` | `ntk_string_data`、`ntk_string_size`、`ntk_string_free` | 3 |
| `Common.h` | `ntk_bytes` | `ntk_bytes_data`、`ntk_bytes_size`、`ntk_bytes_free` | 3 |
| `Common.h` | `ntk_string_list` | `ntk_string_list_count`、`ntk_string_list_at`、`ntk_string_list_free` | 3 |
| `Clipboard.h` | 操作（OP-01〜OP-17） | 8.1 の 17 関数 | 17 |
| `Clipboard.h` | 読み取りの結果（OP-03 の完了） | `_item_count`、`_item_type_count`、`_item_type_at`、`_item_text_at`、`_item_url_at`、`_item_image_type_at`、`_free`（いずれも `ntk_clipboard_read_result` の後に続く） | 7 |
| `Clipboard.h` | 概要（OP-05 の完了） | `_has_strings`、`_has_urls`、`_has_images`、`_has_colors`、`_number_of_items`、`_type_count`、`_type_at`、`_item_type_count`、`_item_type_at`、`_has_matching`、`_matching_count`、`_matching_at`、`_free`（いずれも `ntk_clipboard_snapshot` の後に続く） | 13 |
| `Clipboard.h` | 読み込みの結果（OP-11 の完了） | `_kind`、`_text`、`_url`、`_image_data`、`_image_type`、`_file_path`、`_free`（いずれも `ntk_clipboard_loaded_item` の後に続く） | 7 |
| `Clipboard.h` | 変更のイベント（OP-16 のコールバック） | `_kind`、`_scope_kind`、`_scope_name`、`_types_added_count`、`_types_added_at`、`_types_removed_count`、`_types_removed_at`、`_free`（いずれも `ntk_clipboard_change` の後に続く） | 8 |
| `Dialog.h` | 操作（OP-18〜OP-24） | 8.1 の 7 関数 | 7 |
| `Dialog.h` | 結果（完了の引数） | `_button`、`_option_index`、`_button_text`、`_text`、`_username`、`_password`、`_free`（いずれも `ntk_dialog_result` の後に続く） | 7 |
| `Notification.h` | 操作（OP-25〜OP-45） | 8.1 の 21 関数 | 21 |
| `Notification.h` | 内容のビルダー | `_create`、`_free`、`_set_subtitle`、`_set_body`、`_set_badge`、`_set_sound`、`_set_category`、`_set_interruption_level`、`_set_thread`、`_set_target_content`、`_set_relevance_score`、`_set_filter_criteria`、`_set_user_info_json`、`_add_attachment`（いずれも `ntk_notification_content` の後に続く） | 14 |
| `Notification.h` | 操作のイベント（コールバックの引数） | `_kind`、`_notification_id`、`_action_id`、`_category_id`、`_user_text`、`_user_info_json`、`_is_launch`、`_free`（いずれも `ntk_notification_interaction` の後に続く） | 8 |
| `Notification.h` | 設定の要求（コールバックの引数） | `_notification_id`、`_free`（いずれも `ntk_notification_settings_request` の後に続く） | 2 |
| `Notification.h` | 一覧（OP-33、OP-34 の完了） | `_count`、`_identifier_at`、`_title_at`、`_subtitle_at`、`_body_at`、`_category_at`、`_date_millis_at`、`_free`（いずれも `ntk_notification_list` の後に続く） | 8 |
| `Share.h` | 操作（OP-46） | 8.1 の 1 関数 | 1 |
| `Share.h` | 結果（完了の引数） | `_completed`、`_activity_type`、`_free`（いずれも `ntk_share_result` の後に続く） | 3 |
| 合計 | | | 134 |

### 8.3 今のブリッジの 43 関数との対応表

AC-23 の列（ブリッジ／C ABI／違いと理由／Unity の包みが保つこと）。「包み」は 2c の `unity-native-plugin` の C# の層。「ブリッジ」は今のソースを読んだ姿（G2-1）。

**どの行にも共通する違い**（包みの列には繰り返さない）:

- ブリッジのコールバックに `user_data` が無い → C ABI は `user_data` と `release` を持つ
- ブリッジのコールバックの `const char*` はコールバックの間だけ有効 → C ABI は所有権ごと渡すハンドル（AC-18）
- **入口で拒むと完了は来ない**（ブリッジは不正な要求も必ずコールバックに返した）→ 包みは戻り値が `NONE` でなければ、main に積んで今のコールバックを呼ぶ
- **`callback` の `NULL` は `INVALID_PARAMETER`**（P2-28。ブリッジは Clipboard・Notification・Share で受けて結果を捨てた）→ 包みは空の受け手を渡す
- ブリッジは文言のエラーを返す（Clipboard は `errorCode` の文字列も）→ C ABI は整数の値だけを返し、文言はログ（第 1 部 5.10）。**包みは今の文言を保てない**ので、値から今の文字列に写す。Clipboard は 11.3 の表を逆に使う（`CANCELED` → `CLIPBOARD_CANCELLED`、`INVALID_URI` → `CLIPBOARD_INVALID_URL`、`INVALID_PARAMETER` → `CLIPBOARD_INVALID_REQUEST`）
- **Clipboard の今の JSON の失敗の `error.details`（domain と code）は保てない**（`system_code` は常に 0。D-13）
- ブリッジのログはパスワードを含めて平文で出す（README 1.4）→ C ABI は伏せる（P1-18）
- ブリッジは必須の文字列の `NULL` でプロセスが落ちる（Clipboard を除く）→ C ABI は `INVALID_PARAMETER`

| # | ブリッジ | C ABI | 違いと理由 | Unity の包みが保つこと |
|---|---|---|---|---|
| CL-01 | `clipboardCopy` | OP-01 | JSON → 構造体。Base64 → バイト列。`options` の既定の `localOnly: true` は 0 埋めで同じ（E-9） | JSON を解いて構造体に写す。`INVALID_REQUEST` の文字列を解析の失敗に返す |
| CL-02 | `clipboardAppend` | OP-02 | `options` キーがあると拒む振る舞いは C に無い（引数が無い） | 包みが `options` キーを拒む |
| CL-03 | `clipboardRead` | OP-03 | JSON → ハンドル。`{"ok":...}` の封筒は無い | ハンドルから今の JSON を作る |
| CL-04 | `clipboardReadData` | OP-04 | Base64 → `ntk_bytes`。無いのは `NULL`（今の `data:null`） | Base64 にして今の JSON を作る |
| CL-05 | `clipboardGetSnapshot` | OP-05 | JSON → ハンドル | 今の JSON を作る |
| CL-06 | `clipboardClear` | OP-06 | - | - |
| CL-07 | `clipboardCreatePasteboard` | OP-07 | 空の名前は入口で `INVALID_PARAMETER`。結果は名前の文字列 | `{"scope":...}` を作る。今の `INVALID_NAME`（空白だけ）はそのまま完了で来る |
| CL-08 | `clipboardRemovePasteboard` | OP-08 | `scope` の省略を受けない（今は省くと general で失敗） | 省略を general にして `CANNOT_REMOVE_GENERAL` を返す |
| CL-09 | `clipboardDetectPatterns` | OP-09 | 文字列の配列 → ビットの組。未知の値は C には渡らない | 文字列をビットに写す。未知は `INVALID_REQUEST` |
| CL-10 | `clipboardDetectValues` | OP-10 | 封筒が無い JSON（P2-8） | 封筒を付ける |
| CL-11 | `clipboardLoadItem` | OP-11 | 要求の ID を返し、要求ごとに取り消せる。`.file` の持ち主は同じ | 今の JSON を作る。ID を覚えて CL-12 を保つ |
| CL-12 | `clipboardCancelLoads` | OP-12 を ID ごとに | **一括の取り消しは C に無い**（第 1 部 1.3.1、R-33）。今の順序（一括の完了が先、読み込みの完了が後）は約束しない | 未完了の ID を覚えて 1 つずつ取り消し、main に積んで今のコールバックを `true` で呼ぶ |
| CL-13 | `clipboardStartObserving` | OP-13、OP-16 | 開始と受け手を分けた（P2-16）。受け手を複数にできる。`changeCallback` が `NULL` でも動くのは同じ | 登録して開始する。前の登録を外す（C-7） |
| CL-14 | `clipboardStopObserving` | OP-14 | - | - |
| CL-15 | `clipboardCheckForegroundChange` | OP-15 | - | `{"changed":...}` を作る |
| DL-01 | `showDialog` | OP-18 | **前面でなければ `NOT_FOREGROUND` で完了**（今は `.firstActiveScene` で探して失敗の文言）。押したボタンの値を返す。**外から閉じたら `CANCELED_BY_SYSTEM` で完了**（今は 0 回） | 値を今の `(buttonText, isSuccess, errorMessage)` に写す。**今は 0 回だった場面でコールバックが来る** |
| DL-02 | `showConfirmDialog` | OP-19 | 同上 | 同上 |
| DL-03 | `showDestructiveDialog` | OP-20 | 同上 | 同上 |
| DL-04 | `showActionSheet` | OP-21 | 同上。添字を返す。`NULL` の文言は既定か「無い」（今は空文字になる）。**今は入口の中で失敗が返る経路があったが、無くなる**。基点は view の中央（P1-13。今は `sourceRect` が無く、iPad で選択肢なしで出るおそれがあった） | 同上。今の空文字の見た目は保たない |
| DL-05 | `showTextInputDialog` | OP-22 | 同上。`enable_confirm_when_empty` は反転した名前（P2-22） | 同上。真偽を反転して渡す |
| DL-06 | `showLoginDialog` | OP-23 | 同上。パスワードをログに出さない | 同上 |
| NT-01 | `notificationSetup` | OP-25 | **main 以外ではエラーを返す**（今は黙って何もしない）。戻り値を見られる | `.mm` が起動の中で呼ぶ（第 1 部 1.4）。C# からは呼ばない |
| NT-02 | `showNotification` | OP-26 | **不正な trigger は `INVALID_PARAMETER`**（今は即時に出す。P2-15）。**範囲外の `timeInterval` で落ちない**（P2-26）。今は通って C ではエラーになる値: 空の `id`、負の `badge`、0〜1 の外の `relevanceScore`、`file://` でない添付、項目の無い calendar、範囲外の location と空の識別子、入ると出るの両方が知らせない組、オブジェクトでない `userInfo`。予約のキーは setter で返す。**権限が無ければ `PERMISSION_DENIED`**（今は黙って成功。P2-10） | JSON を解いてビルダーと構造体に写す。エラーを今の失敗のコールバックに写す（P2-15）。`PERMISSION_DENIED` は今の成功に写すかを 2c で決める（今は `notDetermined` の即時の分だけ配信済みに載るので、完全には同じにならない） |
| NT-03 | `scheduleNotification` | OP-28 | NT-02 と同じ。今も不正な trigger は失敗で返す。引数の順は `(identifier, content, trigger, ...)` で今と違う | 不正な trigger は今の失敗の文言で返す。ほかは NT-02 と同じ |
| NT-04 | `updateNotification` | OP-27 | NT-02 と同じ | NT-02 と同じ |
| NT-05 | `cancelNotification` | OP-31 | NT-09 と同じ操作なので 1 つにした（P2-6）。完了を持つ | NT-09 と同じ関数を呼ぶ。完了を捨てれば今と同じ |
| NT-06 | `cancelAllNotifications` | OP-32 | NT-10 と同じ操作。完了を持つ | NT-10 と同じ関数を呼ぶ |
| NT-07 | `removeDeliveredNotification` | OP-29 | 名前は Android に合わせた。完了を持つ | 完了を捨てれば今と同じ |
| NT-08 | `removeAllDeliveredNotifications` | OP-30 | 同上 | 同上 |
| NT-09 | `cancelScheduledNotification` | OP-31 | 完了を持つ | 完了を捨てれば今と同じ |
| NT-10 | `cancelAllScheduledNotifications` | OP-32 | 同上 | 同上 |
| NT-11 | `getScheduledNotifications` | OP-33 | JSON → ハンドル | 今の JSON を作る |
| NT-12 | `getDeliveredNotifications` | OP-34 | 同上。時刻は Unix ミリ秒 | 小数秒なしの ISO 8601 に写す |
| NT-13 | `requestNotificationPermission` | OP-35 | **拒否は `NONE` で 0**（今は失敗の文言）。未決で前面でなければ `NOT_FOREGROUND`。**既に決まっているときは OS に求めず今の状態で答える**（`provisional` と `ephemeral` は 1）。`options` は 0 で今の選択肢 | 0 を今の `(false, "Notification permission was denied.")` に写す |
| NT-14 | `getNotificationAuthorizationStatus` | OP-36 | 文字列 → 列挙の値 | 今の文字列に写す |
| NT-15 | `openNotificationSettings` | OP-38 | **完了を持ち、前面でなければ `NOT_FOREGROUND`**（今は OS が黙って止める） | 空の受け手を渡せば今と同じ |
| NT-16 | `setNotificationBadgeCount` | OP-39 | 負の値は `INVALID_PARAMETER` | エラーを今の失敗のコールバックに写す（P2-15） |
| NT-17 | `registerNotificationCategory` | OP-40 | **完了は書き込みと 1 回の読み返しの後に来る**（今は積んだだけで入口の中で成功）。不正な要素を捨てず `INVALID_PARAMETER` | エラーを今の失敗のコールバックに写す（P2-15）。今の入口の中のコールバックは保たない |
| NT-18 | `removeNotificationCategory` | OP-41 | 完了を持つ | 空の受け手を渡せば今と同じ |
| NT-19 | `hasNotificationPermission` | OP-37 | **重ねても要求ごとに 1 回来る**（今は static の上書きで前の受け手に来ない） | - |
| NT-20 | `setNotificationActionReceivedCallback` | OP-42 | 足す・外す形（AC-21）。複数の受け手。**登録の前に届いたものが最大 32 件まとめて届き、コールドスタートのタップも届く**（今は失う。第 1 部 5.12.7）。userInfo の日付やデータで落ちない（P2-7）。本文のタップも来るのは同じで、`_kind` で分かる | 種類ごとに 1 つのハンドルと「今のハンドル」の印（C-7）。`_kind` が `TEXT_INPUT` でないものを今のコールバックへ。保った分を捨てるかは 2c で決める |
| NT-21 | `setNotificationTextInputActionReceivedCallback` | OP-42 | 同じ受け手に `_kind == TEXT_INPUT` で来る（P2-18） | 同上。`TEXT_INPUT` だけを今のコールバックへ |
| SH-01 | `shareContent` | OP-46 | JSON → 構造体。**前面でなければ `NOT_FOREGROUND`**（今は `.firstActiveScene` で探す）。不正な項目を捨てず `INVALID_PARAMETER`。エラーに入力の URL やパスを含まない | JSON を解いて写す。エラーを今の失敗のコールバックに写す（P2-15） |

### 8.4 ブリッジに無く、足すもの

| 足すもの | OP | 理由 |
|---|---|---|
| 取り消し | OP-12、OP-24 | 要求ごとの取り消し（P1-24） |
| 解除 | OP-17、OP-44 | 受け手の解除（README 6 章） |
| 設定の要求 | OP-43 | `openSettingsFor` のイベント（P1-10） |
| 起動のきっかけ | OP-45 | 起動のきっかけの通知の取得（D-7） |

## 9. 同期・非同期レイヤー対応表

Repository と UseCase の列は Swift の設計書 9 章の表のとおりで、この表では Manager から上を書く。スレッドは完了・イベントが届くスレッド。C ABI の列の「非同期」は、main に積み、完了のコールバックで返す。実行する所は 5.5。

| OP | System API と実行方式 | Manager | C ABI（受け口） | スレッド | キャンセル・資源の持ち主 | 方式を変える理由 |
|---|---|---|---|---|---|---|
| OP-01 | `UIPasteboard.setItems`（同期、main） | callback（`Task` の後に main） | 非同期 | main | - | クラスが `@MainActor`（D-6） |
| OP-02 | `UIPasteboard.addItems`（同期、main） | 同上 | 非同期 | main | - | 同上 |
| OP-03 | `UIPasteboard.items` など（同期、ダイアログの答えを待つ） | 同上 | 非同期。**答えるまで main が止まる** | main | ハンドルは受け手 | 同上。OS の同期の API なので止まるのは変えられない |
| OP-04 | `UIPasteboard.data(forPasteboardType:)`（同上） | 同上 | 非同期。同上 | main | `ntk_bytes` は受け手 | 同上 |
| OP-05 | `UIPasteboard` の問い合わせ（同期。ダイアログを出さない） | 同上 | 非同期 | main | ハンドルは受け手 | 同上 |
| OP-06 | `UIPasteboard.items = []`（同期） | 同上 | 非同期 | main | - | 同上 |
| OP-07 | `UIPasteboard(name:create:)` / `withUniqueName()`（同期） | 同上 | 非同期 | main | `ntk_string` は受け手 | 同上 |
| OP-08 | `UIPasteboard.remove(withName:)`（同期） | 同上 | 非同期 | main | - | 同上 |
| OP-09 | `detectPatterns(for:completionHandler:)`（非同期） | 同上。期限 5 秒 | 非同期 | main | - | 同上 |
| OP-10 | `detectValues(for:completionHandler:)`（非同期） | 同上 | 非同期 | main | `ntk_string` は受け手 | 同上 |
| OP-11 | `NSItemProvider.load*`（非同期。ダイアログの答えを待つ。main を止めない） | callback（箱）。期限 15 秒（答える時間を含む） | 非同期 | main | ID で取り消す。ハンドルは受け手。`FILE` のファイルは受け手 | - |
| OP-12 | - | `nonisolated static`。その場で箱を閉じる | 同期 | 呼び出しスレッド | - | 待たない（S-15） |
| OP-13 | `UIPasteboard.changedNotification`（`NotificationCenter`、main） | 同期（`throws`） | 非同期 | main | 登録とは別 | 失敗を知らせる（P2-16） |
| OP-14 | 同上の解除 | 同期 | 非同期 | main | - | `@MainActor` |
| OP-15 | `UIPasteboard.changeCount`（同期） | 同期 | 非同期 | main | - | `@MainActor` |
| OP-16 | - | `onEvent`（main） | 登録。同期に戻る | main | `release` | 第 1 部 5.7 |
| OP-17 | - | - | 解除。同期に戻る | 呼び出しスレッド | `release` は main | 第 1 部 5.7 |
| OP-18 | `UIViewController.present`（main） | callback（箱） | 非同期。前面が要る | main | ID で取り消す。ハンドルは受け手 | - |
| OP-19 | `UIViewController.present`（main） | callback（箱） | 非同期。前面が要る | main | ID で取り消す。ハンドルは受け手 | - |
| OP-20 | `UIViewController.present`（main） | callback（箱） | 非同期。前面が要る | main | ID で取り消す。ハンドルは受け手 | - |
| OP-21 | `UIViewController.present`（main） | callback（箱） | 非同期。前面が要る | main | ID で取り消す。ハンドルは受け手 | - |
| OP-22 | `UIViewController.present`（main） | callback（箱） | 非同期。前面が要る | main | ID で取り消す。ハンドルは受け手 | - |
| OP-23 | `UIViewController.present`（main） | callback（箱） | 非同期。前面が要る | main | ID で取り消す。ハンドルは受け手 | - |
| OP-24 | - | どのスレッドからでも。その場で箱を閉じる | 同期 | 呼び出しスレッド | - | 待たない（S-15） |
| OP-25 | `UNUserNotificationCenter.delegate`（main） | 同期 | **同期。main だけ** | main | - | D-4、D-6 |
| OP-26 | `UNUserNotificationCenter.add`（非同期） | `async throws` | 非同期 | main | 取り消さない | case を受け取る（P2-14） |
| OP-27 | `UNUserNotificationCenter.add`（非同期） | `async throws` | 非同期 | main | 取り消さない | case を受け取る（P2-14） |
| OP-28 | `UNUserNotificationCenter.add`（非同期） | `async throws` | 非同期 | main | 取り消さない | case を受け取る（P2-14） |
| OP-29 | `removeDelivered*` / `removePending*`（同期、戻り値なし） | 中で `Task`。完了（足す） | 非同期 | main | - | 順序を繋ぐ（P2-6） |
| OP-30 | `removeDelivered*` / `removePending*`（同期、戻り値なし） | 中で `Task`。完了（足す） | 非同期 | main | - | 順序を繋ぐ（P2-6） |
| OP-31 | `removeDelivered*` / `removePending*`（同期、戻り値なし） | 中で `Task`。完了（足す） | 非同期 | main | - | 順序を繋ぐ（P2-6） |
| OP-32 | `removeDelivered*` / `removePending*`（同期、戻り値なし） | 中で `Task`。完了（足す） | 非同期 | main | - | 順序を繋ぐ（P2-6） |
| OP-33 | `getPendingNotificationRequests` / `getDeliveredNotifications`（非同期） | callback（main） | 非同期 | main | ハンドルは受け手 | - |
| OP-34 | `getPendingNotificationRequests` / `getDeliveredNotifications`（非同期） | callback（main） | 非同期 | main | ハンドルは受け手 | - |
| OP-35 | `requestAuthorization`（非同期） | callback（`Result`） | 非同期。未決のとき前面が要る | main | 取り消さない | - |
| OP-36 | `getNotificationSettings`（非同期） | callback（main） | 非同期 | main | - | - |
| OP-37 | `getNotificationSettings`（非同期） | callback（main） | 非同期 | main | - | - |
| OP-38 | `UIApplication.open`（main、非同期） | callback（`Result`） | 非同期。前面が要る | main | - | - |
| OP-39 | `setBadgeCount`（非同期） | `async throws` | 非同期 | main | - | P2-14 |
| OP-40 | `setNotificationCategories`（呼んだ順に積む） | callback | 非同期 | main | - | - |
| OP-41 | `setNotificationCategories`（呼んだ順に積む） | callback | 非同期 | main | - | - |
| OP-42 | `didReceive`、`openSettingsFor` | ハブ（main） | 登録。同期に戻る | main | `release` | AP-21 |
| OP-43 | `didReceive`、`openSettingsFor` | ハブ（main） | 登録。同期に戻る | main | `release` | AP-21 |
| OP-44 | - | - | 解除。同期に戻る | 呼び出しスレッド | `release` は main | 第 1 部 5.7 |
| OP-45 | - | 同期（`@MainActor`、`throws`） | 非同期 | main | ハンドルは受け手 | P2-19 |
| OP-46 | `UIActivityViewController`（main） | callback（`Result`） | 非同期。前面が要る | main | 取り消せない。ハンドルは受け手 | - |

### 9.1 C ABI で加わる変換

| 変換 | 中身 | 節 |
|---|---|---|
| 入力の深い写し | main に積む前に、文字列・配列・バイト列を Swift の値にする | 第 1 部 1.1、C-8 |
| UTF-8 | 入力は厳密に。出力は `CApiString` | 第 1 部 5.9、C-4 |
| エラー | 11 章の表 | 第 1 部 5.10 |
| JSON | 通知の userInfo（P2-7）、`detect_values`（P2-8） | 6.1、6.3 |
| 時刻 | `Date` ↔ Unix（秒は `double`、一覧のミリ秒は `int64_t`） | 6.1、6.3 |

## 10. 振る舞いの集合との対応（README 6 章）

README 6 章の振る舞いの集合に ID を付け、C ABI の OP に対応させる。**2a の機械照合はこの表の ID と OP の対応を読み、どの振る舞いにも C ABI の OP があることを確かめる。** B は今のブリッジの ID（8.3）。

| ID | 振る舞い | 種類 | C ABI での区分 | B | C ABI |
|---|---|---|---|---|---|
| BH-01 | 内容をコピーする | 操作 | 受け付けた後の完了 | CL-01 | OP-01 |
| BH-02 | 内容を足す | 操作 | 受け付けた後の完了 | CL-02 | OP-02 |
| BH-03 | クリップボードを読む | 問い合わせ | 受け付けた後の完了 | CL-03 | OP-03 |
| BH-04 | 型を指定して読む | 問い合わせ | 受け付けた後の完了 | CL-04 | OP-04 |
| BH-05 | 概要を得る | 問い合わせ | 受け付けた後の完了 | CL-05 | OP-05 |
| BH-06 | クリップボードを消す | 操作 | 受け付けた後の完了 | CL-06 | OP-06 |
| BH-07 | ペーストボードを作る | 操作 | 受け付けた後の完了 | CL-07 | OP-07 |
| BH-08 | ペーストボードを消す | 操作 | 受け付けた後の完了 | CL-08 | OP-08 |
| BH-09 | パターンを調べる | 問い合わせ | 受け付けた後の完了 | CL-09 | OP-09 |
| BH-10 | 値を調べる | 問い合わせ | 受け付けた後の完了 | CL-10 | OP-10 |
| BH-11 | 読み込む | 操作 | 受け付けた後の完了 | CL-11 | OP-11 |
| BH-12 | 前面での変更を確かめる | 問い合わせ | 受け付けた後の完了 | CL-15 | OP-15 |
| BH-13 | アラート | 操作 | 受け付けた後の完了 | DL-01 | OP-18 |
| BH-14 | 確認 | 操作 | 受け付けた後の完了 | DL-02 | OP-19 |
| BH-15 | 破壊的な確認 | 操作 | 受け付けた後の完了 | DL-03 | OP-20 |
| BH-16 | アクションシート | 操作 | 受け付けた後の完了 | DL-04 | OP-21 |
| BH-17 | テキスト入力 | 操作 | 受け付けた後の完了 | DL-05 | OP-22 |
| BH-18 | ログイン | 操作 | 受け付けた後の完了 | DL-06 | OP-23 |
| BH-19 | 通知を出す | 操作 | 受け付けた後の完了 | NT-02 | OP-26 |
| BH-20 | 通知を予約する | 操作 | 受け付けた後の完了 | NT-03 | OP-28 |
| BH-21 | 通知を更新する | 操作 | 受け付けた後の完了 | NT-04 | OP-27 |
| BH-22 | 通知を取り消す | 操作 | 受け付けた後の完了 | NT-05 | OP-31 |
| BH-23 | 通知を全部取り消す | 操作 | 受け付けた後の完了 | NT-06 | OP-32 |
| BH-24 | 配信済みを消す | 操作 | 受け付けた後の完了 | NT-07 | OP-29 |
| BH-25 | 配信済みを全部消す | 操作 | 受け付けた後の完了 | NT-08 | OP-30 |
| BH-26 | 予約を取り消す | 操作 | 受け付けた後の完了 | NT-09 | OP-31 |
| BH-27 | 予約を全部取り消す | 操作 | 受け付けた後の完了 | NT-10 | OP-32 |
| BH-28 | 予約の一覧 | 問い合わせ | 受け付けた後の完了 | NT-11 | OP-33 |
| BH-29 | 配信済みの一覧 | 問い合わせ | 受け付けた後の完了 | NT-12 | OP-34 |
| BH-30 | 権限を要求する | 操作 | 受け付けた後の完了 | NT-13 | OP-35 |
| BH-31 | 権限の状態 | 問い合わせ | 受け付けた後の完了 | NT-14 | OP-36 |
| BH-32 | 設定の画面を開く | 操作 | 受け付けた後の完了 | NT-15 | OP-38 |
| BH-33 | バッジ | 操作 | 受け付けた後の完了 | NT-16 | OP-39 |
| BH-34 | category を登録する | 操作 | 受け付けた後の完了 | NT-17 | OP-40 |
| BH-35 | category を消す | 操作 | 受け付けた後の完了 | NT-18 | OP-41 |
| BH-36 | 権限があるか | 問い合わせ | 受け付けた後の完了 | NT-19 | OP-37 |
| BH-37 | 共有する | 操作 | 受け付けた後の完了 | SH-01 | OP-46 |
| EV-01 | クリップボードの変更 | 自発のイベント | イベント | CL-13 | OP-16 |
| EV-02 | 通知のアクション（本文のタップを含む） | 自発のイベント | イベント | NT-20 | OP-42 |
| EV-03 | 通知のテキスト入力のアクション | 自発のイベント | イベント | NT-21 | OP-42 |
| RG-01 | 通知の受け手の登録と解除 | 登録と解除 | 登録と解除 | NT-20、NT-21 | OP-42、OP-44 |
| RG-02 | クリップボードの変更の登録と解除 | 登録と解除 | 登録と解除 | CL-13 | OP-16、OP-17 |
| RG-03 | クリップボードの監視の開始 | 登録と解除 | 受け付けた後の完了 | CL-13 | OP-13 |
| RG-04 | クリップボードの監視の停止 | 登録と解除 | 受け付けた後の完了 | CL-14 | OP-14 |
| RG-05 | delegate を入れる | 登録と解除 | 同期の結果 | NT-01 | OP-25 |
| RG-06 | 読み込みの取り消し | 登録と解除 | 同期の結果 | CL-12 | OP-12 |
| PR-01 | Dialog の要求ごとの取り消し（追加。P1-24） | 操作 | 同期の結果 | - | OP-24 |
| PR-02 | `openSettingsFor` のイベント（追加。P1-10） | 自発のイベント | イベント | - | OP-43、OP-44 |
| PR-03 | 起動のきっかけの通知の取得（追加。D-7） | 問い合わせ | 受け付けた後の完了 | - | OP-45 |

- 「C ABI での区分」は Android 第 2 部と同じ分け方（同期の結果／受け付けた後の完了／イベント／登録と解除）。2a はこの列から完了とイベントの数を導く
- 操作の完了（README 6 章の「操作の完了」）は、「受け付けた後の完了」の行の OP の完了のコールバック

## 11. エラー

0〜5 はすべての機能で同じ意味（AP-12、第 1 部 5.10）。**入口の検査（6 章の基準）の失敗は戻り値で、受け付けた後の失敗は完了の引数で返す**（AP-19）。**同じ値が両方から来うる。****入口では、入口の検査のすべて（`NULL`、厳密な UTF-8、長さ、`struct_size`、範囲、入口の値）を先に、`NOT_INITIALIZED` の確かめを後に行う**（第 1 部 5.10）。番号は P1-7 の規則（同じ名前は Android と同じ番号、iOS だけの値は Android の最後の番号の次から、Android だけの番号は欠番）。**欠番は宣言しない。** 節の順は Android 第 2 部と同じ。

| 値 | 名前の末尾 | iOS での意味 |
|---|---|---|
| 0 | `NONE` | 成功（非同期の関数では受け付けたこと） |
| 1 | `INVALID_PARAMETER` | `NULL`、不正な UTF-8、`struct_size` が小さいか 4096 を超える、`reserved` が 0 でない、範囲外の値、知らないビット、予約したキー |
| 2 | `NOT_INITIALIZED` | Notification の OP-42、OP-43、OP-45 だけ（P1-6）。ほかの機能の値にも番号はあるが返さない |
| 3 | `NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値がある |
| 4 | `UNKNOWN` | 表に無い `IosLibrary` の失敗。詳細はログ（P1-18） |
| 5 | `OUT_OF_MEMORY` | 番号だけ残し、返さない（DF-16） |

### 11.1 `ntk_dialog_error`

| 値 | 名前 | `IosLibrary` の結果 |
|---|---|---|
| 0 | `NTK_DIALOG_ERROR_NONE` | `.success` |
| 1 | `NTK_DIALOG_ERROR_INVALID_PARAMETER` | 入口の検査。`DialogError.invalidRequest`（使い回した箱。C は箱を使い回さないので届かない） |
| 2 | `NTK_DIALOG_ERROR_NOT_INITIALIZED` | 返さない |
| 3 | `NTK_DIALOG_ERROR_NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値 |
| 4 | `NTK_DIALOG_ERROR_UNKNOWN` | 届かない（`DialogError` の case はすべて表にある） |
| 5 | `NTK_DIALOG_ERROR_OUT_OF_MEMORY` | 返さない |
| 6 | `NTK_DIALOG_ERROR_CANCELED` | `.canceled`（OP-24） |
| 7 | `NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM` | `.dismissedBySystem` |
| 8 | `NTK_DIALOG_ERROR_NOT_FOREGROUND` | `.notForeground` |
| 10 | `NTK_DIALOG_ERROR_SHOW_FAILED` | `.presentationFailed` |

欠番: 9（`HOST_START_FAILED`）。

### 11.2 `ntk_notification_error`

| 値 | 名前 | `IosLibrary` の結果 |
|---|---|---|
| 0 | `NTK_NOTIFICATION_ERROR_NONE` | 成功 |
| 1 | `NTK_NOTIFICATION_ERROR_INVALID_PARAMETER` | 入口の検査。`.reservedUserInfoKey`、`.invalidUserInfo`、`.invalidTrigger`（どれも入口で返すので、完了で来るのは想定外だけ） |
| 2 | `NTK_NOTIFICATION_ERROR_NOT_INITIALIZED` | OP-42、OP-43、OP-45 の入口。`.delegateNotInstalled` |
| 3 | `NTK_NOTIFICATION_ERROR_NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値 |
| 4 | `NTK_NOTIFICATION_ERROR_UNKNOWN` | `NotificationError` でない失敗、`.permissionDenied`（deprecated の helper だけが投げ、C の経路では届かない） |
| 5 | `NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY` | 返さない |
| 8 | `NTK_NOTIFICATION_ERROR_NOT_FOREGROUND` | `.notForeground`（OP-35、OP-38） |
| 10 | `NTK_NOTIFICATION_ERROR_PERMISSION_DENIED` | 受け口の事前の確かめ（OP-26〜OP-28。P2-10） |
| 15 | `NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED` | `.openSettingsFailed`（OP-38） |
| 16 | `NTK_NOTIFICATION_ERROR_WRONG_THREAD` | `NotificationDelegateInstallResult.notMainThread`（OP-25 の戻り値だけ。P1-7） |
| 17 | `NTK_NOTIFICATION_ERROR_ATTACHMENT_LOAD_FAILED` | `.attachmentLoadFailed`（無いファイルを含む。`bb365277`） |
| 18 | `NTK_NOTIFICATION_ERROR_ADD_REQUEST_FAILED` | `.addRequestFailed` |
| 19 | `NTK_NOTIFICATION_ERROR_SET_BADGE_COUNT_FAILED` | `.setBadgeCountFailed` |
| 20 | `NTK_NOTIFICATION_ERROR_AUTHORIZATION_FAILED` | `.authorizationFailed` |

欠番: 6、7、9、11、12、13、14（P2-10）。

### 11.3 `ntk_clipboard_error`

受け口は `errorCode` の文字列を写す（P2-13）。12〜29 の順は `ClipboardError` の宣言の順で作った（P2-9 の (7)。以後は順を照らさない）。

| 値 | 名前 | `errorCode`（`ClipboardError` の case） |
|---|---|---|
| 0 | `NTK_CLIPBOARD_ERROR_NONE` | 成功 |
| 1 | `NTK_CLIPBOARD_ERROR_INVALID_PARAMETER` | 入口の検査。`CLIPBOARD_INVALID_REQUEST`（`invalidRequest`。空のパスは入口で返すので、使い回した箱とともに C からは届かない） |
| 2 | `NTK_CLIPBOARD_ERROR_NOT_INITIALIZED` | 返さない |
| 3 | `NTK_CLIPBOARD_ERROR_NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値 |
| 4 | `NTK_CLIPBOARD_ERROR_UNKNOWN` | `CLIPBOARD_UNKNOWN`（`unknown`）、表に無い文字列 |
| 5 | `NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY` | 返さない |
| 6 | `NTK_CLIPBOARD_ERROR_EMPTY_CONTENT` | `CLIPBOARD_EMPTY_CONTENT`（`emptyContent`） |
| 7 | `NTK_CLIPBOARD_ERROR_EMPTY_ITEMS` | `CLIPBOARD_EMPTY_ITEMS`（`emptyItemList`）。入口でも返す |
| 8 | `NTK_CLIPBOARD_ERROR_INVALID_URI` | `CLIPBOARD_INVALID_URL`（`invalidURL`） |
| 9 | `NTK_CLIPBOARD_ERROR_UNAVAILABLE` | `CLIPBOARD_UNAVAILABLE`（`pasteboardUnavailable`） |
| 12 | `NTK_CLIPBOARD_ERROR_EMPTY_PATTERNS` | `CLIPBOARD_EMPTY_PATTERNS`（`emptyDetectionPatterns`）。入口でも返す |
| 13 | `NTK_CLIPBOARD_ERROR_INVALID_TYPE` | `CLIPBOARD_INVALID_TYPE`（`invalidTypeIdentifier`） |
| 14 | `NTK_CLIPBOARD_ERROR_INVALID_NAME` | `CLIPBOARD_INVALID_NAME`（`invalidPasteboardName`） |
| 15 | `NTK_CLIPBOARD_ERROR_INVALID_COLOR` | `CLIPBOARD_INVALID_COLOR`（`invalidColor`） |
| 16 | `NTK_CLIPBOARD_ERROR_INVALID_IMAGE_DATA` | `CLIPBOARD_INVALID_IMAGE_DATA`（`invalidImageData`） |
| 17 | `NTK_CLIPBOARD_ERROR_INVALID_EXPIRATION` | `CLIPBOARD_INVALID_EXPIRATION`（`invalidExpirationDate`） |
| 18 | `NTK_CLIPBOARD_ERROR_CONTENT_TOO_LARGE` | `CLIPBOARD_CONTENT_TOO_LARGE`（`contentTooLarge`） |
| 19 | `NTK_CLIPBOARD_ERROR_FILE_NOT_FOUND` | `CLIPBOARD_FILE_NOT_FOUND`（`fileNotFound`） |
| 20 | `NTK_CLIPBOARD_ERROR_IMAGE_LOAD_FAILED` | `CLIPBOARD_IMAGE_LOAD_FAILED`（`imageLoadFailed`） |
| 21 | `NTK_CLIPBOARD_ERROR_IMAGE_ENCODE_FAILED` | `CLIPBOARD_IMAGE_ENCODE_FAILED`（`imageEncodingFailed`） |
| 22 | `NTK_CLIPBOARD_ERROR_CANNOT_REMOVE_GENERAL` | `CLIPBOARD_CANNOT_REMOVE_GENERAL`（`cannotRemoveGeneralPasteboard`） |
| 23 | `NTK_CLIPBOARD_ERROR_NO_MATCHING_ITEM` | `CLIPBOARD_NO_MATCHING_ITEM`（`noMatchingItem`） |
| 24 | `NTK_CLIPBOARD_ERROR_LOAD_FAILED` | `CLIPBOARD_LOAD_FAILED`（`providerLoadFailed`）。**読み込みで貼り付けの許可を拒んだとき**（M3、CB2。P2-9 の (9)） |
| 25 | `NTK_CLIPBOARD_ERROR_UNEXPECTED_TYPE` | `CLIPBOARD_UNEXPECTED_TYPE`（`unexpectedType`） |
| 26 | `NTK_CLIPBOARD_ERROR_FILE_COPY_FAILED` | `CLIPBOARD_FILE_COPY_FAILED`（`fileCopyFailed`） |
| 27 | `NTK_CLIPBOARD_ERROR_CANCELED` | `CLIPBOARD_CANCELLED`（`cancelled`）。文字列の綴りは変えず、C の名前は 1 つの L（P2-9） |
| 28 | `NTK_CLIPBOARD_ERROR_TIMED_OUT` | `CLIPBOARD_TIMED_OUT`（`timedOut`） |
| 29 | `NTK_CLIPBOARD_ERROR_DETECTION_FAILED` | `CLIPBOARD_DETECTION_FAILED`（`detectionFailed`）。値を調べるときに貼り付けの許可を拒んだときも（M3） |

欠番: 10（`READ_NOT_ALLOWED`）、11（`SECURITY`）。

### 11.4 `ntk_share_error`

17〜21 の順は `ShareError` の宣言の順で作った（P2-9 の (7)）。

| 値 | 名前 | `IosLibrary` の結果 |
|---|---|---|
| 0 | `NTK_SHARE_ERROR_NONE` | `.success`（`ntk_share_result` に写す） |
| 1 | `NTK_SHARE_ERROR_INVALID_PARAMETER` | 入口の検査 |
| 2 | `NTK_SHARE_ERROR_NOT_INITIALIZED` | 返さない |
| 3 | `NTK_SHARE_ERROR_NOT_SUPPORTED` | `struct_size` の知らない部分に 0 でない値 |
| 4 | `NTK_SHARE_ERROR_UNKNOWN` | 届かない（`ShareError` の case はすべて表にある） |
| 5 | `NTK_SHARE_ERROR_OUT_OF_MEMORY` | 返さない |
| 6 | `NTK_SHARE_ERROR_NOT_FOREGROUND` | `.notForeground`。`.noRootViewController`（`.firstActiveScene` だけなので届かない） |
| 7 | `NTK_SHARE_ERROR_EMPTY_CONTENT` | `.noValidItems`（入口で返す。AP-19） |
| 9 | `NTK_SHARE_ERROR_FILE_NOT_FOUND` | `.fileNotFound` |
| 17 | `NTK_SHARE_ERROR_INVALID_URI` | `.invalidURL`（P2-9 の (4)） |
| 18 | `NTK_SHARE_ERROR_IMAGE_LOAD_FAILED` | `.imageLoadFailed` |
| 19 | `NTK_SHARE_ERROR_SHOW_FAILED` | `.presentationFailed` |
| 20 | `NTK_SHARE_ERROR_CANCELED_BY_SYSTEM` | `.dismissedBySystem` |
| 21 | `NTK_SHARE_ERROR_ACTIVITY_FAILED` | `.activityFailed` |

欠番: 8、10、11、12、13、14、15、16。`CANCELED` は無い（P2-11）。

### 11.5 番号の表（`scripts/c_abi_error_numbers.json`）

2a で 11.1〜11.4 と Android のヘッダーから作る（P1-7）。形は次のとおりで、機能ごとに名前 → 番号の 1 つの表を持つ。

```json
{
  "dialog": { "NONE": 0, "INVALID_PARAMETER": 1, "...": 5, "CANCELED": 6, "CANCELED_BY_SYSTEM": 7, "NOT_FOREGROUND": 8, "HOST_START_FAILED": 9, "SHOW_FAILED": 10 },
  "notification": { "...": "..." }
}
```

- 0〜5 も表に入れる（「表に無い値がヘッダーに無い」を例外なしで照らすため）
- `iOS` と `Android` の列は持たず、ヘッダーと表を照らす: **どちらの OS のヘッダーの値も表と同じ番号で、表に無い値がヘッダーに無い**。ある OS に無い名前はその OS の欠番になる。Windows は対象外
- Android が後で値を足すときは、表の最後の次から取る。今の表の最後は Dialog 10、Notification 20、Clipboard 29、Share 21（Android の照合 `check_c_abi_contract_android.py` にも表を足す）。**Android のヘッダーの今の値は変わらない**

## 12. テスト設計

### 12.1 C ABI のテスト（`IosLibraryCApiTests`。XCTest から C の関数を呼ぶ。README 7 章）

通常・ASan・TSan の 3 通りで流す（P1-20）。**`IosLibraryCApiTests` のホストは権限を一度も求めない専用のアプリで、TB-2b の UI テスト用のアプリと bundle を分ける**（同じにすると、12.2 が許可を押した後に `PERMISSION_DENIED` の行が落ちる）。

| 観点 | 中身 |
|---|---|
| 入口の検査 | 8.2 のすべての関数で、`NULL`（`callback` を含む。P2-28）、厳密な UTF-8 の拒否（第 1 部 6 章の 5 つの列）、`struct_size`（小さい、上限 4096、知らない部分の 0 と 0 以外、`reserved`）、**配列の要素の `struct_size`（広げた要素を各要素の大きさで進む、大きさの混ざった配列を拒む。P2-5）**、範囲（列挙、ビット、6.3 の数値）。出力の引数に入口で `NULL` を書くこと。**すべての関数を網羅したことは 2a で照らす**（8.2 の名前がテストのソースに現れる。`common.md` の両辺の導出） |
| 入口と完了の分け方（AP-19） | 件数 0 の `EMPTY_ITEMS`・`EMPTY_PATTERNS`・`EMPTY_CONTENT`、空のパス、範囲外の trigger が戻り値で返り、**完了は呼ばれず、`release` だけが呼び出しスレッドで関数が戻る前に 1 回** |
| 写しの表 | **写しは受け口の純粋な関数にして `@testable import IosLibraryCApi` で確かめる**: 各エラーの型の全 case の値を手で書いて比べる（case の増減は 2a の照合が止める。12.3）。`ClipboardError` は `errorCode` を通して 11.3 と比べる（P2-13。別のモジュールからの `switch` は `@unknown default` が要り、止めない）。**実際に起こせるものだけを C から通す**（空の内容、無いファイル、前面でない）。`.addRequestFailed` など起こせないものは写しの関数のテストだけ |
| 完了 | 非同期の OP のちょうど 1 回、main で来ること、main から呼んだときは戻った後、`release` のちょうど 1 回（第 1 部 6 章の表の項目を、第 2 部の関数で行う） |
| main を待たない | main を止めた状態で、`ntk_notification_install` のほかの全関数が待たずに戻る（第 1 部 6 章） |
| 前面 | **UI テスト用のアプリ（TB-2b）で流す**。後ろから呼んだ OP-18〜OP-23、OP-35（未決）、OP-38、OP-46 が `NOT_FOREGROUND` で完了する。OP-35 は決まっていれば後ろからでも値で完了する |
| 取り消し | OP-24: `CANCELED` で完了し閉じる。上に画面が重なっていれば閉じない。**受け付けの後、最初の main の処理の前の取り消し（main を止めて行う）で、Dialog が出ず、読み込みが始まらず、完了と `release` が来る**。OP-12: `CANCELED`、main 以外から呼んでその場で閉じる（P2-12）。**箱が閉じたのが開始の確かめより前なら、貼り付けのダイアログが出ない**（12.2 で確かめる。開始と同時の取り消しは約束しない。5.3）。`.file` の成功を C が捨てたときと、`RELEASED` の後に届いたときにファイルとフォルダーが消える。渡した後の取り消しでは消えない。知らない ID と完了の後の ID は `NONE` で何もしない |
| イベント | **受け口の帳簿をイベントの型に依存しない形で組み、`@testable import` で流す**: 同じ種類に 2 つの登録で両方に届く、解除の後に届かない、保っていたイベントが次の登録に挿入のブロックの中で届く、**保っていたイベントを配っているコールバックの中で唯一の登録を外して新しく足しても、残りが新しい登録に届く**（AP-21）、33 件目で最も古いものを捨てる。**ハンドルの値（`_kind` の 4 種、userInfo、`_is_launch`）は純粋な変換のテストと 12.2 の 1 件ずつ**（`NotificationResponseEvent` の init は internal で、C から作れない） |
| delegate | `NOT_INITIALIZED`（OP-42、OP-43、OP-45。Swift の口で入れたときは通る。P1-6）、`WRONG_THREAD`、起動のきっかけの取得（`NULL` の後に値に変わりうる。決まった後は 2 回呼んでも同じ。P2-19） |
| userInfo の JSON（P2-7） | オブジェクトでない、不正な JSON、`1e400`、入れ子の `null`、最上位の予約のキーが setter の戻り値で `INVALID_PARAMETER`。入れ子の同じキーは通る。受け口の予約のキーの写しがライブラリと同じ（`reservedUserInfoKey` が出ないこと）。出力の変換表の全行（`date`・`data`・有限でない `double` が落ちずに決まった形になる。ブリッジの S-11 の場面）。`detect_values` の JSON のゴールデン |
| trigger（P2-26） | **`IosLibrary` のテスト**: `isValid` の式の各分岐と M8 で測った値、`invalidTrigger`。**C のテスト**: 範囲外の `interval`、`repeats` で 60 未満、`calendar_fields` の 0 と知らないビット、緯度と経度と半径が `INVALID_PARAMETER` で、**プロセスが落ちない** |
| 0 で埋めた構造体 | `struct_size` のほかを 0 で埋めた各構造体（選択肢は `NULL` も）を、**構造体 → Swift の値の写しの関数で直接比べる**（E-9 の反転した名前を含む。`localOnly` や trigger は OS から読めないので完了では確かめられない）。Dialog の文言（P2-22） |
| ビルダー | 既定値、`NULL` の setter、範囲外の値、空の `id`、`file://` でない添付。**渡した後に変更・解放しても内容が変わらないことは、ビルダー → `NotificationContent` の写しの関数で確かめる**（`IosLibraryCApiTests` のホストには権限が無く、操作は `PERMISSION_DENIED` で止まる） |
| Clipboard | 9 種の `kind` のラウンドトリップ、`MULTI_REPRESENTATION` の重複の拒否、`read_data` の `NULL`、`get_snapshot` の `has_matching`、`.file` のファイルが `_free` で消えない、監視の開始の `UNAVAILABLE`、登録しただけでは始まらない、解除しても監視は続く（P2-17）（貼り付けの拒否の 4 つの値は 12.2） |
| 権限の事前の確かめ（P2-10） | **判定を受け口の純粋な関数にして 6 つの状態の全行を確かめる**（`ephemeral` と `unknown` を含む。`IosLibrary` の internal の判定と同じ集合）。`IosLibraryCApiTests` で OP-26〜OP-28 が `PERMISSION_DENIED` で完了する。**`update_async` が `update` を呼ばないことは、受け口の中の口を差し替えて確かめる**（権限が無いと pending は常に 0 で、前の要求を作れない。M2）。許可の後に通ることは 12.2 |
| 列挙の読み取り（P2-29） | `NULL` のハンドルに -1 を返す（`_option_index`、`_matching_at` を含む） |
| 権限の要求の選択肢（P2-27） | 知らないビット（`1u << 6`、`1u << 7`、`1u << 8`）が `INVALID_PARAMETER`。ビットの組 → `UNAuthorizationOptions` の写しの関数で、0 が既定の選択肢、`PROVIDES_APP_SETTINGS` が渡る |
| 順序（P2-6） | 12.2 の「通知の順序と許可の後」の行で確かめる |
| 出力のハンドル | 範囲外の添字は `NULL` か 0 か -1、`_free(NULL)` と `_listener_remove(NULL)` が何もしない、文字列の U+FFFD |
| system_code | 失敗しうる関数の後の `ntk_last_system_code()` と、完了の `system_code` が 0 |
| 構造体の配置 | 付録 A の各構造体の `sizeof` と各欄の `offsetof` を、3 つのスライスで確かめる |
| 実行時のクラス | `IosLibraryCApi` の Objective-C の実行時のクラスに `@objc` で名前を固定したものが無い（D-11、第 1 部 6 章） |

### 12.2 端末の上の通しの確かめ

| 観点 | 中身 |
|---|---|
| 通知のイベント | C から出した通知をバナーで押し、操作のイベントが C の受け手に届く（XCUITest。シミュレーター）。`BODY_TAP`、`ACTION`、`TEXT_INPUT`、`DISMISS` を 1 件ずつ。コールドスタートのタップと `_is_launch`。`openSettingsFor`（PR-02）は 1b の MS-07 の方法で |
| 通知の順序と許可の後 | 許可の後に `show_async`・`update_async`・`schedule_async` が通り pending に残る。`update_async` が前の要求を置き換える。`cancel_all_scheduled_async` の完了の中の `schedule_async` が残る（M6 と同じ確かめ） |
| Dialog と権限 | C から出した Dialog と権限のダイアログを XCUITest で押し、完了の値を確かめる。アクションシートの外側のタップ（6.2） |
| Share | C から開いたシートで「コピー」を選び、`completed` と `activity_type` を確かめる |
| Clipboard | C から書いて C で読む。監視のイベント。**ランナーが書いた内容を `load_item_async`、`read_async`、`read_data_async`、`detect_values_async` で読み、貼り付けのダイアログで許可と拒否を押す**（CB1・CB2 の C 版。M3 の値。取り消した読み込みでダイアログが出ないこと）。読み込みの時間切れ（`CLIPBOARD_TIMED_OUT`）は `init(timeouts:)` が C から使えないので、15 秒待つ 1 件だけにする |
| 実機（iPhone XS / 18.7.2） | **第 1 部 P1-20 のとおり、`IosLibraryCApiTests` の ASan と smoke を 2b の DoD の区切りで流す**（毎回利用者の許可を得る。`agent-rules/device-testing.md`）。12.2 の上の行は**シミュレーターだけ**（springboard、権限のダイアログの操作になり、集中モードで新しいアプリの通知も出ないため）。**実機で流す `IosLibraryCApiTests` の Clipboard の行は名前付きのペーストボードに限る**（general を書き換えると私物のクリップボードを上書きする。`device-testing.md`）。実機で確かめたいものは利用者に別に尋ねる |

### 12.3 機械照合（2a）

- `scripts/check_c_abi_contract_ios.py` を `scripts/c_abi_contract_common.py` の上に作る（Android の 0.3 の決定と同じ形）。入力: 付録 A、8.1、8.2、10 章、11 章、`ios/IosLibraryCApi/.../NativeToolkitC/*.h`
- 照らすもの: 8.2 = ヘッダー = 付録 A の関数（合計 134）、宣言の一致、10 章のどの振る舞いにも OP がある、11 章の値 = ヘッダー、**`scripts/c_abi_error_numbers.json` = iOS と Android のヘッダー（P1-7）**、**`ClipboardError`・`ShareError`・`DialogError`・`NotificationError` の全 case が 11 章の表にある**（順は見ない。P2-9 の (7)）、10 章の区分の数、名前の規則、ASCII、3 つの OS の `Common.h` の一致（第 1 部 5.2。コメントを除く）
- Swift の口の照合: 8.1 の「Swift の口」が swiftinterface にある（TB-0 で取り直した基準）
- ヘッダーだけのコンパイル（C99、C11、C++、Objective-C。`-Wall -Wextra -Werror`。README 7 章）。構造体の `sizeof` の期待値はテストの中に置く
- ビルドの後: 各スライスの `nm -gU` の `_ntk_*` = 8.2（AP-15、第 1 部 5.5）
- 自己テストで、各照合を 1 つずつ壊すと落ちることを確かめる
- 流し方は Android 第 2 部 12.3 と同じ（`--design-only`、`--library`）

### 12.4 smoke（`IosLibraryCApiSmoke`）

配布物の 2 つの xcframework だけで組む C / Objective-C のアプリが、Xcode 26.6 と 26.3 の両方で組め、`ntk_notification_install`・Clipboard の書き込みと読み取り・Dialog（完了まで）を通す（README 7 章、D-16）。

### 12.5 変異

足した検査は、契約を保ったまま形を変える変異で壊して落ちることを確かめる（`common.md`「検査の書き方」）。

## 13. 実装タスク分解

| ID | 内容 | 見積 | 依存 | 完了の条件 |
|---|---|---|---|---|
| TB-0 | 7 章の変更: `IosLibrary` に足す口（P2-6、P2-12、P2-26）と Swift のテスト、文書の直し | 1.0日 | - | 足した口のテスト。`results/swiftinterface/` の基準を取り直した。シミュレーターの基準の差が足したものだけ。7 章の表のすべての行 |
| TA-1 | `check_c_abi_contract_ios.py`、`c_abi_error_numbers.json`、Android の照合にも表を足す、README 3.3 の照合を OS の数によらない形に直す | 1.0日 | TB-0 | Windows の照合が今と同じ。Android は表の照合が増えるだけ。iOS は付録 A で通る（`--design-only`）。自己テストで壊すと落ちる |
| TA-2 | `check_manual_c_examples_ios.py` を足す（`manual_c_examples_common.py` の上） | 0.5日 | TA-1 | iOS の例が無いときは SKIP |
| TB-1 | `IosLibraryCApi` の本番の形（第 1 部 5.1、5.3、5.4）、5 つの公開ヘッダー（付録 A からまとめて作る）、`ntk_notification_install` | 1.0日 | TB-0 | `--design-only` なしで通る。雛形の `ntk_probe_*` が無い。**ヘッダーだけのコンパイル（C99、C11、C++、Objective-C。12.3）、第 1 部 5.5 の H = E、E = P、module map の照合を `check_c_abi_contract_ios.py` に足す**（TA-1 は入口のソースが無いので足せなかった） |
| TB-2 | 共通の部品（`StructReader`（配列の要素を含む）、`CApiString`、`Registration` と ID の表、エラーの土台）、最初の呼び出しの版の確かめ（C-9、P1-19） | 1.5日 | TB-1 | 第 1 部 6 章の `release` と完了のテスト。1a の雛形の `struct_size` の穴（第 1 部 1.1）を写していない |
| TB-2b | C を呼ぶ UI テスト用のアプリとターゲット（第 1 部 6 章の「テストの口」。サンプルは Swift の API だけを使うので別に作る）。`test_ios.sh` のランナーの区分 | 1.5日 | TB-2 | 12.1 の前面の行と 12.2 を流せる。**権限を未決に戻す方法を確かめた**（`simctl uninstall` で足りるか、足りなければ `erase`） |
| TB-3 | Clipboard の書き込みと問い合わせ（OP-01〜OP-10、OP-15、結果のハンドル） | 1.5日 | TB-2b | 12.1 の Clipboard の行、写しの関数 |
| TB-4 | Clipboard の読み込みと監視（OP-11〜OP-14、OP-16、OP-17） | 1.0日 | TB-3 | 12.1 の取り消しとイベントの行 |
| TB-5 | Dialog（OP-18〜OP-24、結果） | 1.0日 | TB-2b | 12.1 の前面・取り消しの行、12.2。**アクションシートは iPad Pro 11-inch (M4) / 18.3 でも通す**（TB-2b のアプリはまだ iPad で起動していない） |
| TB-6 | 通知のビルダーと userInfo の JSON、trigger、category | 1.5日 | TB-2 | 12.1 のビルダー・userInfo・trigger の行 |
| TB-7 | 通知の操作（OP-26〜OP-41）、権限の事前の確かめ | 1.0日 | TB-6、TB-2b | 12.1 の写しの関数・前面・事前の確かめ・権限の要求の選択肢の行、12.2 の「通知の順序と許可の後」の行 |
| TB-8 | 通知のイベント（OP-42〜OP-45）。**TB-2b のアプリに起動の形を伝える口を足す**（システムが起こしたプロセスは起動の引数を受けないので、サンプルの SA-18 と同じくファイルで。コールドスタートの中で受け手を登録するため） | 1.0日 | TB-7 | 12.1 のイベント・delegate の行と 12.2 |
| TB-9 | Share（OP-46、結果） | 0.5日 | TB-2b | 12.1 の前面の行と 12.2。**iPad Pro 11-inch (M4) / 18.3 でも通す**（TB-5 と同じ） |
| TB-10 | main を待たないことのテスト、競合の再現のテスト（第 1 部 6 章） | 1.0日 | TB-3〜TB-9 | すべての公開の関数。**`check_c_abi_contract_ios.py` の未実装の一覧（`NOT_IMPLEMENTED_YET`）が空で、第 1 部 5.5 の H = E がそのまま成り立つ**（TB-1 の照合は「E は H の部分集合、残りはこの一覧」。実装が増えるたびに一覧が減る）。**`--require-complete` を付けて通る**（一覧に名前を足す変更を止めるのはこの旗だけ） |
| TB-11 | dist、`check_ios_dist.py`、smoke（第 1 部 C-5） | 1.5日 | TB-3〜TB-10 | 12.4 と 15.2 の配布物の項目。3 つのスライスで `--library` が `--architectures` と `--require-complete` つきで通る。第 1 部 5.5 の残り（`-Swift.h`、`.swiftmodule`、C のソースの `ntk_`）。**capi の xcframework は Release だけを受ける**（今のビルドのスクリプトの `--configuration debug` を写さない。Debug には `.swiftmodule` と `_$s14IosLibraryCApi*` が入る。第 1 部 5.4） |
| TB-12 | `test_ios.sh` に C ABI のテスト 3 通り、smoke、`--library` と `--require-compile`、`--require-complete` を付けた照合をつなぐ（第 1 部 C-6） | 0.5日 | TB-11 | 全件が通る |
| TC-1 | `unity-native-plugin` に渡す対応表と移行の手引き（16 章） | 0.5日 | TB-12 | 8.3 と 16 章を渡した |

合計見積: 17.5 日（TA 1.5、TB 15.5、TC 0.5）。マニュアルの iOS の C ABI の章は README の段階 4 で書く（AP-23）。

## 14. リスクと緩和策

| ID | リスク | 緩和策 |
|---|---|---|
| RP-1 | 同じ名前で OS ごとに引数・列挙の値・同期の別が違う（例: `NTK_DIALOG_BUTTON_*` の 2 と 3、Notification の値、`ntk_notification_add_interaction_listener` の種類） | 機能のヘッダーは OS ごと（README D-3）。C# のバインディングは関数・列挙・構造体を OS ごとに宣言する（16 章）。共通の宣言は `Common.h` だけ |
| RP-2 | `errorCode` の文字列でエラーを決めるので、`IosLibrary` が文字列を変えると黙って `UNKNOWN` になる | 12.1 の写しの関数のテストと 2a の全 case の照合（P2-13） |
| RP-3 | P2-15 で今のブリッジの補正をやめたので、Unity の包みが写し損ねると動作が変わる | 8.3 の「Unity の包みが保つこと」の列と、2c の Unity のテスト |
| RP-4 | 同期の読み出しで main が止まる（MS-08） | ヘッダーとマニュアルに書く（P2-24）。Unity の包みは今のブリッジの `read` を保つので、ゲームの main が止まる場面は今と同じ。止めたい利用者は `load_item_async` |
| RP-5 | 読み込みの時間切れに答える時間が入る。15 秒以内に答えないと `TIMED_OUT` | ヘッダーとマニュアルに書く（P2-24）。動作を変える価値があるかは Unity の実利用で見る |
| RP-6 | 実機でしか分からない失敗がある。CB1 の原因が分からない、CB3・CB4 は合成のタップを受けない見込み（1b の記録 24 章） | **12.2 の貼り付けはシミュレーターで確かめ、実機は 1b の手の確認（ダイアログと許可）に頼る**。`UIPasteControl` は C に出ない（D-5）。CB の扱いは `clipboard` を許す次の実機の回の前に決める |
| RP-7 | P2-10 の事前の確かめは、確かめた後に状態が変わると守らない。Swift の口は今も成功を返して残らない | 最善の努力とヘッダーに書く。Swift の口の DocC に書く（7 章） |
| RP-8 | 「出した番号は変えない」を止めるものが無い。`c_abi_error_numbers.json` とヘッダーを一緒に変えると照合は通る | リリースの前に、前の版のタグの表と比べる照合を足すかを決める（2.0.0 が iOS の最初の版なので、今は比べる相手が無い） |

## 15. Definition of Done

### 15.1 機能

- 8.1 の 46 操作と 8.2 の 134 関数が、付録 A の宣言のとおりに公開されている
- 10 章のすべての振る舞いに C ABI の OP がある
- 11 章のすべてのエラーの値が、写しの表のとおりに返る
- 9 章の表と、実装のスレッド・同期性・キャンセルの契約が一致している（12.1 の行で確かめ、実装のレビューで照らす）

### 15.2 品質

- 12.1〜12.4 が通る（シミュレーターは iPhone 17 / 26.2 と iPad Pro 11-inch (M4) / 18.3、通常・ASan・TSan。P1-20）。**12.1 の前面の行は、この 2 つのシミュレーターで、サニタイザーなしで流す**。サニタイザーの網羅は `IosLibraryCApiTests` が受け持つ
- 第 1 部 6 章のテストが通る
- 実機（iPhone XS / 18.7.2）の区切りの ASan と smoke を、利用者の許可を得て流した（P1-20）
- README 7.3 の配布物の照合が通る（`check_ios_dist.py`）
- 2a の機械照合が通り、照合の自己テストが壊すと落ちる
- 足した検査は変異で落ちることを確かめた

### 15.3 構成と文書

- 7 章の文書の直しを済ませた（TB-0）
- `unity-native-plugin` に 8.3 と 16 章を渡した
- マニュアルは README の段階 4（AP-23）。`agent-rules/workflows/verify-manual/workflow.md` に `check_manual_c_examples_ios.py` を足すのも段階 4。候補: `sourceRect`、マルチウィンドウの iPad、起動のきっかけの限り、読み込みの時間切れ、後ろの貼り付けのダイアログ

## 16. `unity-native-plugin` に渡す範囲（README 8.6）

| 項目 | 渡すもの |
|---|---|
| 対応表 | 8.3（43 関数。Unity の包みが保つことの列） |
| EditMode の JSON のテスト | 第 1 部の時点の数は 126 件（知見 3 章、README 8.6）。**実物はこのリポジトリの外なので、2c の申し送りで数える**（G2-3）。**JSON を解く処理は包みに残る**ので、包みの JSON の解析と、解析した値から C の関数を呼ぶところをテストにする。基準は 8.3 の「Unity の包みが保つこと」の列 |
| コールバックの例外 | 利用者のコールバックの例外の振る舞いは定めない（P1-16）。包みの `[MonoPInvokeCallback]` の本体を `try` / `catch` で囲む |
| 差し替え型の受け手 | C-7（種類ごとに 1 つのハンドルと「今のハンドル」の印） |
| 解除の副作用 | P2-17 |
| `NOT_FOREGROUND` | Dialog・Share・設定の画面・未決の権限の要求を後ろから呼ぶと `NOT_FOREGROUND` で完了する。今は失敗の文言か、OS が黙って止める |
| 値の補正と代わりの値 | **包みは補正を持たない**（P2-15）。エラーを今の失敗のコールバックに写す。8.3 の NT-02 に今は通る値の一覧がある。移行ガイドに書く。Base64 と文字列の列挙は包みが写す |
| 回数が変わるコールバック | Dialog は外から閉じたときに `CANCELED_BY_SYSTEM` で来る（今は 0 回）。`registerNotificationCategory` は登録の後に来る。`hasNotificationPermission` は要求ごとに 1 回。**入口で拒むと完了は来ない**（8.3 の共通の違い） |
| コールドスタート | `ntk_notification_install` は `.mm` が起動の中で呼ぶ（第 1 部 1.4、U-3・U-4）。受け手を登録する前のタップが届くようになる |
| 2 回目の申し送りの雛形との違い | `Notification.h` の 6、7 は無い（P2-10）。`ntk_probe_*` は無い。`event_kind` の 1 つの受け手は `add_interaction_listener` と `add_settings_request_listener` に分かれた |
| 権限が無いときの通知 | `PERMISSION_DENIED`（P2-10）を今の成功に写すかを確かめる（8.3 の NT-02）。今は黙って成功で、pending に残らない。**既に権限を決めたアプリ（1.x から上げたアプリ）は C から `.providesAppNotificationSettings` を足せない**（P2-27）ので、設定の要求のイベントが要るなら `.mm` が `requestAuthorization` を呼ぶ |
| C# のバインディング | 機能の関数・列挙・構造体は OS ごとに宣言する（RP-1）。`ntk_version()` は OS ごとの期待値と比べる |

## 付録 A. 公開ヘッダーの宣言

`#pragma pack(push, 8)` と include ガード、`extern "C"` はすべてのヘッダーにある（第 1 部 5.2）。機能のヘッダーの `Common.h` の取り込みは第 1 部 5.2 の形（`__has_include`）。コメントは要点だけ。2a は宣言（関数、コールバック、構造体の項目、列挙の値、typedef）をこの付録と照らす。

### A.1 `NativeToolkitC/Common.h`

宣言は Windows・Android の `Common.h` と同じ（第 1 部 5.2）。版は iOS のライブラリの版。

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

/** The raw value the OS reported for the last failure on this thread. Always 0 on iOS. */
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

### A.2 `NativeToolkitC/Clipboard.h`

```c
#ifndef NATIVETOOLKITC_CLIPBOARD_H
#define NATIVETOOLKITC_CLIPBOARD_H

#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* The rules of this header (design part 1, chapter 1):
   - Every function can be called from any thread and never waits for the main thread. Completions,
     events and an accepted call's release run on the main thread, and never inside the function when
     you call it on the main thread; called elsewhere, a completion can come before the function
     returns, before an output parameter is visible. Match results through user_data.
   - NONE from a function with a completion callback means accepted, and then the callback comes exactly once
     while the process lives (dialogs and shares: see their callback types). A listener gets zero or more
     events until it is removed. Any other value means rejected: no callback, and release (if not NULL) has
     already been called on your thread. Do not free user_data yourself then. A NULL callback is rejected.
   - After removing a listener off the main thread, events can still come until release. Free user_data
     in release, not when the function returns.
   - Callbacks must not let exceptions escape, and must not block the main thread for long.
   - Text comes back as UTF-8; invalid surrogates and U+0000 become U+FFFD.
   - Zero-filled means every field except struct_size.
   - Enumerations can grow: write a default branch. */
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
    NTK_CLIPBOARD_ERROR_EMPTY_PATTERNS = 12,
    NTK_CLIPBOARD_ERROR_INVALID_TYPE = 13,
    NTK_CLIPBOARD_ERROR_INVALID_NAME = 14,
    NTK_CLIPBOARD_ERROR_INVALID_COLOR = 15,
    NTK_CLIPBOARD_ERROR_INVALID_IMAGE_DATA = 16,
    NTK_CLIPBOARD_ERROR_INVALID_EXPIRATION = 17,
    NTK_CLIPBOARD_ERROR_CONTENT_TOO_LARGE = 18,
    NTK_CLIPBOARD_ERROR_FILE_NOT_FOUND = 19,
    NTK_CLIPBOARD_ERROR_IMAGE_LOAD_FAILED = 20,
    NTK_CLIPBOARD_ERROR_IMAGE_ENCODE_FAILED = 21,
    NTK_CLIPBOARD_ERROR_CANNOT_REMOVE_GENERAL = 22,
    NTK_CLIPBOARD_ERROR_NO_MATCHING_ITEM = 23,
    NTK_CLIPBOARD_ERROR_LOAD_FAILED = 24,
    NTK_CLIPBOARD_ERROR_UNEXPECTED_TYPE = 25,
    NTK_CLIPBOARD_ERROR_FILE_COPY_FAILED = 26,
    NTK_CLIPBOARD_ERROR_CANCELED = 27,
    NTK_CLIPBOARD_ERROR_TIMED_OUT = 28,
    NTK_CLIPBOARD_ERROR_DETECTION_FAILED = 29
};

typedef int32_t ntk_clipboard_scope_kind;
enum {
    NTK_CLIPBOARD_SCOPE_GENERAL = 0,
    NTK_CLIPBOARD_SCOPE_NAMED = 1,
    NTK_CLIPBOARD_SCOPE_UNIQUE = 2
};

typedef int32_t ntk_clipboard_content_kind;
enum {
    NTK_CLIPBOARD_CONTENT_PLAIN_TEXT = 0,
    NTK_CLIPBOARD_CONTENT_HTML = 1,
    NTK_CLIPBOARD_CONTENT_URL = 2,
    NTK_CLIPBOARD_CONTENT_IMAGE_FILE = 3,
    NTK_CLIPBOARD_CONTENT_IMAGE_DATA = 4,
    NTK_CLIPBOARD_CONTENT_COLOR = 5,
    NTK_CLIPBOARD_CONTENT_CUSTOM_DATA = 6,
    NTK_CLIPBOARD_CONTENT_MULTIPLE_TEXT = 7,
    NTK_CLIPBOARD_CONTENT_MULTI_REPRESENTATION = 8
};

/* What to load, and what a load returned. */
typedef int32_t ntk_clipboard_item_kind;
enum {
    NTK_CLIPBOARD_ITEM_TEXT = 0,
    NTK_CLIPBOARD_ITEM_URL = 1,
    NTK_CLIPBOARD_ITEM_IMAGE = 2,
    NTK_CLIPBOARD_ITEM_FILE = 3
};

typedef int32_t ntk_clipboard_change_event_kind;
enum {
    NTK_CLIPBOARD_CHANGE_CHANGED = 0,
    NTK_CLIPBOARD_CHANGE_REMOVED = 1
};

/* A set of detection patterns: an OR of these bits. */
typedef uint32_t ntk_clipboard_patterns;
enum {
    NTK_CLIPBOARD_PATTERN_PROBABLE_WEB_URL = 1u << 0,
    NTK_CLIPBOARD_PATTERN_PROBABLE_WEB_SEARCH = 1u << 1,
    NTK_CLIPBOARD_PATTERN_NUMBER = 1u << 2,
    NTK_CLIPBOARD_PATTERN_LINK = 1u << 3,
    NTK_CLIPBOARD_PATTERN_EMAIL_ADDRESS = 1u << 4,
    NTK_CLIPBOARD_PATTERN_PHONE_NUMBER = 1u << 5,
    NTK_CLIPBOARD_PATTERN_POSTAL_ADDRESS = 1u << 6,
    NTK_CLIPBOARD_PATTERN_CALENDAR_EVENT = 1u << 7,
    NTK_CLIPBOARD_PATTERN_FLIGHT_NUMBER = 1u << 8,
    NTK_CLIPBOARD_PATTERN_MONEY_AMOUNT = 1u << 9,
    NTK_CLIPBOARD_PATTERN_SHIPMENT_TRACKING_NUMBER = 1u << 10
};

/** What ntk_clipboard_read_async returned. */
typedef struct ntk_clipboard_read_result ntk_clipboard_read_result;
/** What ntk_clipboard_get_snapshot_async returned. */
typedef struct ntk_clipboard_snapshot ntk_clipboard_snapshot;
/** What ntk_clipboard_load_item_async returned. */
typedef struct ntk_clipboard_loaded_item ntk_clipboard_loaded_item;
/** A change of the observed pasteboard. */
typedef struct ntk_clipboard_change ntk_clipboard_change;
/** A change listener registration. */
typedef struct ntk_clipboard_listener ntk_clipboard_listener;

/* Every callback is called on the main thread. A handle or string it receives is owned by the
   receiver and is NULL unless error is NTK_CLIPBOARD_ERROR_NONE. */
typedef void (NTK_CALL *ntk_clipboard_done_fn)(void* user_data, ntk_clipboard_error error, uint32_t system_code);
typedef void (NTK_CALL *ntk_clipboard_read_fn)(void* user_data, ntk_clipboard_error error, uint32_t system_code,
                                               ntk_clipboard_read_result* result);
/** data is NULL when the pasteboard has no item of the type. */
typedef void (NTK_CALL *ntk_clipboard_data_fn)(void* user_data, ntk_clipboard_error error, uint32_t system_code,
                                               ntk_bytes* data);
typedef void (NTK_CALL *ntk_clipboard_snapshot_fn)(void* user_data, ntk_clipboard_error error, uint32_t system_code,
                                                   ntk_clipboard_snapshot* snapshot);
/** name is the pasteboard's name, to use in ntk_clipboard_scope. */
typedef void (NTK_CALL *ntk_clipboard_name_fn)(void* user_data, ntk_clipboard_error error, uint32_t system_code,
                                               ntk_string* name);
typedef void (NTK_CALL *ntk_clipboard_patterns_fn)(void* user_data, ntk_clipboard_error error, uint32_t system_code,
                                                   ntk_clipboard_patterns patterns);
/** values_json is a JSON object: detectedPatterns, probableWebURL, probableWebSearch, number, links,
    emailAddresses, phoneNumbers, postalAddresses, calendarEvents, flightNumbers, moneyAmounts,
    shipmentTrackingNumbers. */
typedef void (NTK_CALL *ntk_clipboard_values_fn)(void* user_data, ntk_clipboard_error error, uint32_t system_code,
                                                 ntk_string* values_json);
typedef void (NTK_CALL *ntk_clipboard_load_fn)(void* user_data, uint64_t request_id, ntk_clipboard_error error,
                                               uint32_t system_code, ntk_clipboard_loaded_item* item);
/** changed is nonzero when the pasteboard changed since the last check. */
typedef void (NTK_CALL *ntk_clipboard_foreground_change_fn)(void* user_data, ntk_clipboard_error error,
                                                            uint32_t system_code, int32_t changed);
/** The observed pasteboard changed. change is owned by the receiver. */
typedef void (NTK_CALL *ntk_clipboard_change_fn)(void* user_data, ntk_clipboard_change* change);

#pragma pack(push, 8)
/** NULL means the general pasteboard. */
typedef struct ntk_clipboard_scope {
    uint32_t                 struct_size;
    uint32_t                 reserved0;
    ntk_clipboard_scope_kind kind;
    uint32_t                 reserved1;
    const char*              name;           /**< Required for NAMED and UNIQUE. */
} ntk_clipboard_scope;

/** One type of a MULTI_REPRESENTATION content. Every element of an array has the same struct_size. */
typedef struct ntk_clipboard_representation {
    uint32_t       struct_size;
    uint32_t       reserved0;
    const char*    ut_type;
    const uint8_t* data;
    size_t         data_size;
} ntk_clipboard_representation;

/** kind decides which fields are read; the others are not. */
typedef struct ntk_clipboard_write_content {
    uint32_t                   struct_size;
    uint32_t                   reserved0;
    ntk_clipboard_content_kind kind;
    uint32_t                   reserved1;
    const char*                text;         /**< PLAIN_TEXT; the plain text of HTML. */
    const char*                html;         /**< HTML. */
    const char*                url;          /**< URL. */
    const char*                path;         /**< IMAGE_FILE. */
    const uint8_t*             data;         /**< IMAGE_DATA, CUSTOM_DATA. */
    size_t                     data_size;
    const char*                ut_type;      /**< IMAGE_DATA, CUSTOM_DATA. */
    double                     red;          /**< COLOR: 0.0 to 1.0. */
    double                     green;
    double                     blue;
    double                     alpha;        /**< Required; 0.0 is transparent. */
    const char* const*         texts;        /**< MULTIPLE_TEXT. */
    size_t                     text_count;
    const ntk_clipboard_representation* representations;  /**< MULTI_REPRESENTATION. */
    size_t                     representation_count;
} ntk_clipboard_write_content;

/** NULL or zero-filled: local to this device, no expiration. */
typedef struct ntk_clipboard_copy_options {
    uint32_t struct_size;
    uint32_t reserved0;
    int32_t  not_local_only;                 /**< Nonzero: Handoff may carry it to other devices. */
    int32_t  has_expiration;                 /**< Nonzero: expiration_unix_seconds is read. */
    double   expiration_unix_seconds;
} ntk_clipboard_copy_options;
#pragma pack(pop)

/* The pasteboard is used on the main thread. scope may be NULL (general) unless noted. */
ntk_clipboard_error NTK_CALL ntk_clipboard_copy_async(const ntk_clipboard_write_content* content,
                                                      const ntk_clipboard_copy_options* options,
                                                      const ntk_clipboard_scope* scope,
                                                      ntk_clipboard_done_fn callback, void* user_data,
                                                      ntk_release_fn release);
ntk_clipboard_error NTK_CALL ntk_clipboard_append_async(const ntk_clipboard_write_content* content,
                                                        const ntk_clipboard_scope* scope,
                                                        ntk_clipboard_done_fn callback, void* user_data,
                                                        ntk_release_fn release);
/** When another app wrote the content, iOS asks the user to allow the paste and the main thread stops
    until the answer. A denied paste is not a failure: one item with no types and no text. To avoid the
    wait, use ntk_clipboard_load_item_async. */
ntk_clipboard_error NTK_CALL ntk_clipboard_read_async(const ntk_clipboard_scope* scope,
                                                      ntk_clipboard_read_fn callback, void* user_data,
                                                      ntk_release_fn release);
/** Stops the main thread like ntk_clipboard_read_async; a denied paste gives NULL. The bytes are returned
    as they are. */
ntk_clipboard_error NTK_CALL ntk_clipboard_read_data_async(const char* ut_type, const ntk_clipboard_scope* scope,
                                                           ntk_clipboard_data_fn callback, void* user_data,
                                                           ntk_release_fn release);
/** matching_types may be NULL when matching_type_count is 0: no matching is done. */
ntk_clipboard_error NTK_CALL ntk_clipboard_get_snapshot_async(const char* const* matching_types,
                                                              size_t matching_type_count,
                                                              const ntk_clipboard_scope* scope,
                                                              ntk_clipboard_snapshot_fn callback, void* user_data,
                                                              ntk_release_fn release);
ntk_clipboard_error NTK_CALL ntk_clipboard_clear_async(const ntk_clipboard_scope* scope,
                                                       ntk_clipboard_done_fn callback, void* user_data,
                                                       ntk_release_fn release);
/** kind is NAMED (name is required) or UNIQUE (name is not read); GENERAL is rejected. */
ntk_clipboard_error NTK_CALL ntk_clipboard_create_pasteboard_async(ntk_clipboard_scope_kind kind, const char* name,
                                                                   ntk_clipboard_name_fn callback, void* user_data,
                                                                   ntk_release_fn release);
/** scope must not be NULL. */
ntk_clipboard_error NTK_CALL ntk_clipboard_remove_pasteboard_async(const ntk_clipboard_scope* scope,
                                                                   ntk_clipboard_done_fn callback, void* user_data,
                                                                   ntk_release_fn release);
ntk_clipboard_error NTK_CALL ntk_clipboard_detect_patterns_async(ntk_clipboard_patterns patterns,
                                                                 const ntk_clipboard_scope* scope,
                                                                 ntk_clipboard_patterns_fn callback, void* user_data,
                                                                 ntk_release_fn release);
/** Reads the content, so iOS can ask the user to allow the paste; the main thread does not stop. The 5-second
    timeout includes the time to answer (NTK_CLIPBOARD_ERROR_TIMED_OUT); a denied paste gives
    NTK_CLIPBOARD_ERROR_DETECTION_FAILED. */
ntk_clipboard_error NTK_CALL ntk_clipboard_detect_values_async(ntk_clipboard_patterns patterns,
                                                               const ntk_clipboard_scope* scope,
                                                               ntk_clipboard_values_fn callback, void* user_data,
                                                               ntk_release_fn release);
/** Does not stop the main thread. The 15-second timeout includes the time the user takes to answer the
    paste prompt; a load not answered by then ends with NTK_CLIPBOARD_ERROR_TIMED_OUT, and a later answer
    delivers nothing. A denied paste gives NTK_CLIPBOARD_ERROR_LOAD_FAILED. ut_type is required for NTK_CLIPBOARD_ITEM_FILE and not read otherwise.
    out_request_id may be NULL; then the load cannot be cancelled. */
ntk_clipboard_error NTK_CALL ntk_clipboard_load_item_async(ntk_clipboard_item_kind kind, const char* ut_type,
                                                           const ntk_clipboard_scope* scope,
                                                           ntk_clipboard_load_fn callback, void* user_data,
                                                           ntk_release_fn release, uint64_t* out_request_id);
/** From any thread; does not wait. The load ends with NTK_CLIPBOARD_ERROR_CANCELED. A paste prompt can still
    appear when the load is starting at that moment. An unknown or finished request_id does nothing. */
ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_load(uint64_t request_id);
/** Only one pasteboard is observed at a time; this replaces the previous one. When this fails with
    NTK_CLIPBOARD_ERROR_UNAVAILABLE, the previous one has already stopped. */
ntk_clipboard_error NTK_CALL ntk_clipboard_start_observing_async(const ntk_clipboard_scope* scope,
                                                                 ntk_clipboard_done_fn callback, void* user_data,
                                                                 ntk_release_fn release);
/** Stops observing for everyone in the process, also when another component started it. */
ntk_clipboard_error NTK_CALL ntk_clipboard_stop_observing_async(ntk_clipboard_done_fn callback, void* user_data,
                                                                ntk_release_fn release);
/** Compares the change count with the last check; it does not look at the foreground. The first check gives 0. */
ntk_clipboard_error NTK_CALL ntk_clipboard_check_foreground_change_async(const ntk_clipboard_scope* scope,
                                                                         ntk_clipboard_foreground_change_fn callback,
                                                                         void* user_data, ntk_release_fn release);

/** Registering does not start observing. */
ntk_clipboard_error NTK_CALL ntk_clipboard_add_change_listener(ntk_clipboard_change_fn callback, void* user_data,
                                                               ntk_release_fn release,
                                                               ntk_clipboard_listener** out_listener);
/** Removes the registration; observing goes on. The handle is invalid afterwards; user_data is not until
    release. Does nothing for NULL. */
void NTK_CALL ntk_clipboard_listener_remove(ntk_clipboard_listener* listener);

/* Readers: pointers stay valid until the handle is freed. out_size may be NULL. An index out of range
   gives NULL or 0. */
size_t      NTK_CALL ntk_clipboard_read_result_item_count(const ntk_clipboard_read_result* result);
size_t      NTK_CALL ntk_clipboard_read_result_item_type_count(const ntk_clipboard_read_result* result, size_t item);
const char* NTK_CALL ntk_clipboard_read_result_item_type_at(const ntk_clipboard_read_result* result, size_t item,
                                                            size_t index, size_t* out_size);
const char* NTK_CALL ntk_clipboard_read_result_item_text_at(const ntk_clipboard_read_result* result, size_t item,
                                                            size_t* out_size);
const char* NTK_CALL ntk_clipboard_read_result_item_url_at(const ntk_clipboard_read_result* result, size_t item,
                                                           size_t* out_size);
const char* NTK_CALL ntk_clipboard_read_result_item_image_type_at(const ntk_clipboard_read_result* result, size_t item,
                                                                  size_t* out_size);
void        NTK_CALL ntk_clipboard_read_result_free(ntk_clipboard_read_result* result);

int32_t     NTK_CALL ntk_clipboard_snapshot_has_strings(const ntk_clipboard_snapshot* snapshot);
int32_t     NTK_CALL ntk_clipboard_snapshot_has_urls(const ntk_clipboard_snapshot* snapshot);
int32_t     NTK_CALL ntk_clipboard_snapshot_has_images(const ntk_clipboard_snapshot* snapshot);
int32_t     NTK_CALL ntk_clipboard_snapshot_has_colors(const ntk_clipboard_snapshot* snapshot);
size_t      NTK_CALL ntk_clipboard_snapshot_number_of_items(const ntk_clipboard_snapshot* snapshot);
size_t      NTK_CALL ntk_clipboard_snapshot_type_count(const ntk_clipboard_snapshot* snapshot);
const char* NTK_CALL ntk_clipboard_snapshot_type_at(const ntk_clipboard_snapshot* snapshot, size_t index,
                                                    size_t* out_size);
size_t      NTK_CALL ntk_clipboard_snapshot_item_type_count(const ntk_clipboard_snapshot* snapshot, size_t item);
const char* NTK_CALL ntk_clipboard_snapshot_item_type_at(const ntk_clipboard_snapshot* snapshot, size_t item,
                                                         size_t index, size_t* out_size);
/** Nonzero when matching was requested; 0 means the two functions below have nothing. */
int32_t     NTK_CALL ntk_clipboard_snapshot_has_matching(const ntk_clipboard_snapshot* snapshot);
size_t      NTK_CALL ntk_clipboard_snapshot_matching_count(const ntk_clipboard_snapshot* snapshot);
/** The index of the matching item, or -1 when index is out of range or for NULL. */
int64_t     NTK_CALL ntk_clipboard_snapshot_matching_at(const ntk_clipboard_snapshot* snapshot, size_t index);
void        NTK_CALL ntk_clipboard_snapshot_free(ntk_clipboard_snapshot* snapshot);

/** -1 for NULL. */
ntk_clipboard_item_kind NTK_CALL ntk_clipboard_loaded_item_kind(const ntk_clipboard_loaded_item* item);
const char*    NTK_CALL ntk_clipboard_loaded_item_text(const ntk_clipboard_loaded_item* item, size_t* out_size);
const char*    NTK_CALL ntk_clipboard_loaded_item_url(const ntk_clipboard_loaded_item* item, size_t* out_size);
const uint8_t* NTK_CALL ntk_clipboard_loaded_item_image_data(const ntk_clipboard_loaded_item* item, size_t* out_size);
const char*    NTK_CALL ntk_clipboard_loaded_item_image_type(const ntk_clipboard_loaded_item* item, size_t* out_size);
/** You own the file and its parent directory: delete them when done. ntk_clipboard_loaded_item_free does not. */
const char*    NTK_CALL ntk_clipboard_loaded_item_file_path(const ntk_clipboard_loaded_item* item, size_t* out_size);
void           NTK_CALL ntk_clipboard_loaded_item_free(ntk_clipboard_loaded_item* item);

/** -1 for NULL. */
ntk_clipboard_change_event_kind NTK_CALL ntk_clipboard_change_kind(const ntk_clipboard_change* change);
/** -1 for NULL. */
ntk_clipboard_scope_kind        NTK_CALL ntk_clipboard_change_scope_kind(const ntk_clipboard_change* change);
const char* NTK_CALL ntk_clipboard_change_scope_name(const ntk_clipboard_change* change, size_t* out_size);
size_t      NTK_CALL ntk_clipboard_change_types_added_count(const ntk_clipboard_change* change);
const char* NTK_CALL ntk_clipboard_change_types_added_at(const ntk_clipboard_change* change, size_t index,
                                                         size_t* out_size);
size_t      NTK_CALL ntk_clipboard_change_types_removed_count(const ntk_clipboard_change* change);
const char* NTK_CALL ntk_clipboard_change_types_removed_at(const ntk_clipboard_change* change, size_t index,
                                                           size_t* out_size);
void        NTK_CALL ntk_clipboard_change_free(ntk_clipboard_change* change);

#ifdef __cplusplus
}
#endif
#endif
```

### A.3 `NativeToolkitC/Dialog.h`

```c
#ifndef NATIVETOOLKITC_DIALOG_H
#define NATIVETOOLKITC_DIALOG_H

#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* The rules of this header (design part 1, chapter 1):
   - Every function can be called from any thread and never waits for the main thread. Completions,
     events and an accepted call's release run on the main thread, and never inside the function when
     you call it on the main thread; called elsewhere, a completion can come before the function
     returns, before an output parameter is visible. Match results through user_data.
   - NONE from a function with a completion callback means accepted, and then the callback comes exactly once
     while the process lives (dialogs and shares: see their callback types). A listener gets zero or more
     events until it is removed. Any other value means rejected: no callback, and release (if not NULL) has
     already been called on your thread. Do not free user_data yourself then. A NULL callback is rejected.
   - After removing a listener off the main thread, events can still come until release. Free user_data
     in release, not when the function returns.
   - Callbacks must not let exceptions escape, and must not block the main thread for long.
   - Text comes back as UTF-8; invalid surrogates and U+0000 become U+FFFD.
   - Zero-filled means every field except struct_size.
   - Enumerations can grow: write a default branch. */
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
    NTK_DIALOG_ERROR_SHOW_FAILED = 10
};

typedef int32_t ntk_dialog_button;
enum {
    NTK_DIALOG_BUTTON_POSITIVE = 0,
    NTK_DIALOG_BUTTON_NEGATIVE = 1,
    NTK_DIALOG_BUTTON_DESTRUCTIVE = 2,
    NTK_DIALOG_BUTTON_OPTION = 3
};

/** The answer of a dialog. Owned by the receiver: free it with ntk_dialog_result_free. */
typedef struct ntk_dialog_result ntk_dialog_result;

/** result is NULL unless error is NTK_DIALOG_ERROR_NONE. The callback and release do not come while a host
    that replaced its window or root view controller, or a scene the system disconnected, keeps the dialog
    alive: ntk_dialog_cancel ends the request then. On an iPad with several windows, which one shows the
    dialog is not decided. */
typedef void (NTK_CALL *ntk_dialog_result_fn)(void* user_data, uint64_t request_id, ntk_dialog_error error,
                                              uint32_t system_code, ntk_dialog_result* result);

#pragma pack(push, 8)
/* NULL button texts take the library's defaults; NULL title, message and placeholder mean none. A
   zero-filled struct is the default dialog. */
typedef struct ntk_dialog_alert_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* button_text;                 /**< NULL: "OK". */
} ntk_dialog_alert_request;

typedef struct ntk_dialog_confirm_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* confirm_text;                /**< NULL: "OK". */
    const char* cancel_text;                 /**< NULL: "Cancel". */
} ntk_dialog_confirm_request;

typedef struct ntk_dialog_destructive_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* destructive_text;            /**< NULL: "Delete". */
    const char* cancel_text;                 /**< NULL: "Cancel". */
} ntk_dialog_destructive_request;

typedef struct ntk_dialog_action_sheet_request {
    uint32_t           struct_size;
    uint32_t           reserved0;
    const char*        title;
    const char*        message;
    const char* const* options;
    size_t             option_count;
    const char*        cancel_text;          /**< NULL: "Cancel". */
} ntk_dialog_action_sheet_request;

typedef struct ntk_dialog_text_input_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* placeholder;
    const char* confirm_text;                /**< NULL: "OK". */
    const char* cancel_text;                 /**< NULL: "Cancel". */
    int32_t     confirm_disabled_when_empty; /**< Nonzero: the input is required. */
    uint32_t    reserved1;
} ntk_dialog_text_input_request;

typedef struct ntk_dialog_login_request {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* title;
    const char* message;
    const char* username_placeholder;        /**< NULL: "Username". */
    const char* password_placeholder;        /**< NULL: "Password". */
    const char* login_text;                  /**< NULL: "Login". */
    const char* cancel_text;                 /**< NULL: "Cancel". */
    int32_t     login_disabled_when_empty;   /**< Nonzero: both fields are required. */
    uint32_t    reserved1;
} ntk_dialog_login_request;
#pragma pack(pop)

/* Needs the foreground: otherwise the callback gets NTK_DIALOG_ERROR_NOT_FOREGROUND. request must not be NULL.
   out_request_id may be NULL; then the request cannot be cancelled. */
ntk_dialog_error NTK_CALL ntk_dialog_show_alert_async(const ntk_dialog_alert_request* request,
                                                      ntk_dialog_result_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_confirm_async(const ntk_dialog_confirm_request* request,
                                                        ntk_dialog_result_fn callback, void* user_data,
                                                        ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_destructive_async(const ntk_dialog_destructive_request* request,
                                                            ntk_dialog_result_fn callback, void* user_data,
                                                            ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_action_sheet_async(const ntk_dialog_action_sheet_request* request,
                                                             ntk_dialog_result_fn callback, void* user_data,
                                                             ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_text_input_async(const ntk_dialog_text_input_request* request,
                                                           ntk_dialog_result_fn callback, void* user_data,
                                                           ntk_release_fn release, uint64_t* out_request_id);
ntk_dialog_error NTK_CALL ntk_dialog_show_login_async(const ntk_dialog_login_request* request,
                                                      ntk_dialog_result_fn callback, void* user_data,
                                                      ntk_release_fn release, uint64_t* out_request_id);
/** From any thread; does not wait. The request ends with NTK_DIALOG_ERROR_CANCELED; a dialog covered by
    another screen stays. An unknown or finished request_id does nothing. */
ntk_dialog_error NTK_CALL ntk_dialog_cancel(uint64_t request_id);

/* Readers: pointers stay valid until the handle is freed. out_size may be NULL. */
/** -1 for NULL: check error first. */
ntk_dialog_button NTK_CALL ntk_dialog_result_button(const ntk_dialog_result* result);
/** The index of the chosen option from 0, or -1 unless the button is OPTION or for NULL. */
int64_t     NTK_CALL ntk_dialog_result_option_index(const ntk_dialog_result* result);
const char* NTK_CALL ntk_dialog_result_button_text(const ntk_dialog_result* result, size_t* out_size);
/** The input of a confirmed text input dialog, or NULL. */
const char* NTK_CALL ntk_dialog_result_text(const ntk_dialog_result* result, size_t* out_size);
/** The username of a confirmed login dialog, or NULL. */
const char* NTK_CALL ntk_dialog_result_username(const ntk_dialog_result* result, size_t* out_size);
/** The password of a confirmed login dialog, or NULL. */
const char* NTK_CALL ntk_dialog_result_password(const ntk_dialog_result* result, size_t* out_size);
void        NTK_CALL ntk_dialog_result_free(ntk_dialog_result* result);

#ifdef __cplusplus
}
#endif
#endif
```

### A.4 `NativeToolkitC/Notification.h`

```c
#ifndef NATIVETOOLKITC_NOTIFICATION_H
#define NATIVETOOLKITC_NOTIFICATION_H

#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* The rules of this header (design part 1, chapter 1):
   - Every function except ntk_notification_install can be called from any thread, and none waits for the main thread. Completions,
     events and an accepted call's release run on the main thread, and never inside the function when
     you call it on the main thread; called elsewhere, a completion can come before the function
     returns, before an output parameter is visible. Match results through user_data.
   - NONE from a function with a completion callback means accepted, and then the callback comes exactly once
     while the process lives (dialogs and shares: see their callback types). A listener gets zero or more
     events until it is removed. Any other value means rejected: no callback, and release (if not NULL) has
     already been called on your thread. Do not free user_data yourself then. A NULL callback is rejected.
   - After removing a listener off the main thread, events can still come until release. Free user_data
     in release, not when the function returns.
   - Callbacks must not let exceptions escape, and must not block the main thread for long.
   - Text comes back as UTF-8; invalid surrogates and U+0000 become U+FFFD.
   - Zero-filled means every field except struct_size.
   - Enumerations can grow: write a default branch. */
typedef int32_t ntk_notification_error;
enum {
    NTK_NOTIFICATION_ERROR_NONE = 0,
    NTK_NOTIFICATION_ERROR_INVALID_PARAMETER = 1,
    NTK_NOTIFICATION_ERROR_NOT_INITIALIZED = 2,
    NTK_NOTIFICATION_ERROR_NOT_SUPPORTED = 3,
    NTK_NOTIFICATION_ERROR_UNKNOWN = 4,
    NTK_NOTIFICATION_ERROR_OUT_OF_MEMORY = 5,
    NTK_NOTIFICATION_ERROR_NOT_FOREGROUND = 8,
    NTK_NOTIFICATION_ERROR_PERMISSION_DENIED = 10,
    NTK_NOTIFICATION_ERROR_SETTINGS_NOT_OPENED = 15,
    NTK_NOTIFICATION_ERROR_WRONG_THREAD = 16,
    NTK_NOTIFICATION_ERROR_ATTACHMENT_LOAD_FAILED = 17,
    NTK_NOTIFICATION_ERROR_ADD_REQUEST_FAILED = 18,
    NTK_NOTIFICATION_ERROR_SET_BADGE_COUNT_FAILED = 19,
    NTK_NOTIFICATION_ERROR_AUTHORIZATION_FAILED = 20
};

typedef int32_t ntk_notification_sound_kind;
enum {
    NTK_NOTIFICATION_SOUND_DEFAULT = 0,
    NTK_NOTIFICATION_SOUND_DEFAULT_CRITICAL = 1,
    NTK_NOTIFICATION_SOUND_NAMED = 2,
    NTK_NOTIFICATION_SOUND_NONE = 3
};

typedef int32_t ntk_notification_interruption_level;
enum {
    NTK_NOTIFICATION_INTERRUPTION_NOT_SET = 0,
    NTK_NOTIFICATION_INTERRUPTION_PASSIVE = 1,
    NTK_NOTIFICATION_INTERRUPTION_ACTIVE = 2,
    NTK_NOTIFICATION_INTERRUPTION_TIME_SENSITIVE = 3,
    NTK_NOTIFICATION_INTERRUPTION_CRITICAL = 4
};

typedef int32_t ntk_notification_trigger_kind;
enum {
    NTK_NOTIFICATION_TRIGGER_TIME_INTERVAL = 0,
    NTK_NOTIFICATION_TRIGGER_CALENDAR = 1,
    NTK_NOTIFICATION_TRIGGER_LOCATION = 2
};

/* Which calendar fields of ntk_notification_trigger are read: an OR of these bits. */
enum {
    NTK_NOTIFICATION_CALENDAR_YEAR = 1u << 0,
    NTK_NOTIFICATION_CALENDAR_MONTH = 1u << 1,
    NTK_NOTIFICATION_CALENDAR_DAY = 1u << 2,
    NTK_NOTIFICATION_CALENDAR_HOUR = 1u << 3,
    NTK_NOTIFICATION_CALENDAR_MINUTE = 1u << 4,
    NTK_NOTIFICATION_CALENDAR_SECOND = 1u << 5
};

/* ntk_notification_action.options. */
enum {
    NTK_NOTIFICATION_ACTION_AUTHENTICATION_REQUIRED = 1u << 0,
    NTK_NOTIFICATION_ACTION_DESTRUCTIVE = 1u << 1,
    NTK_NOTIFICATION_ACTION_FOREGROUND = 1u << 2
};

/* ntk_notification_category.options. */
enum {
    NTK_NOTIFICATION_CATEGORY_CUSTOM_DISMISS_ACTION = 1u << 0,
    NTK_NOTIFICATION_CATEGORY_ALLOW_IN_CAR_PLAY = 1u << 1,
    NTK_NOTIFICATION_CATEGORY_HIDDEN_PREVIEWS_SHOW_TITLE = 1u << 2,
    NTK_NOTIFICATION_CATEGORY_ALLOW_ANNOUNCEMENT = 1u << 3
};

typedef int32_t ntk_notification_authorization_status;
enum {
    NTK_NOTIFICATION_STATUS_NOT_DETERMINED = 0,
    NTK_NOTIFICATION_STATUS_DENIED = 1,
    NTK_NOTIFICATION_STATUS_AUTHORIZED = 2,
    NTK_NOTIFICATION_STATUS_PROVISIONAL = 3,
    NTK_NOTIFICATION_STATUS_EPHEMERAL = 4,
    NTK_NOTIFICATION_STATUS_UNKNOWN = 5
};

/* The options of ntk_notification_request_permission_async: an OR of these bits; the values are those of
   UNAuthorizationOptions. 0 means ALERT, SOUND and BADGE. */
enum {
    NTK_NOTIFICATION_AUTH_BADGE = 1u << 0,
    NTK_NOTIFICATION_AUTH_SOUND = 1u << 1,
    NTK_NOTIFICATION_AUTH_ALERT = 1u << 2,
    NTK_NOTIFICATION_AUTH_CAR_PLAY = 1u << 3,
    NTK_NOTIFICATION_AUTH_CRITICAL_ALERT = 1u << 4,
    NTK_NOTIFICATION_AUTH_PROVIDES_APP_SETTINGS = 1u << 5
};

typedef int32_t ntk_notification_event_kind;
enum {
    NTK_NOTIFICATION_EVENT_KIND_BODY_TAP = 0,
    NTK_NOTIFICATION_EVENT_KIND_ACTION = 1,
    NTK_NOTIFICATION_EVENT_KIND_DISMISS = 2,
    NTK_NOTIFICATION_EVENT_KIND_TEXT_INPUT = 3
};

/** The content of a notification. Not thread safe: build it on one thread. */
typedef struct ntk_notification_content ntk_notification_content;
/** The user's response to a notification. Owned by the receiver. */
typedef struct ntk_notification_interaction ntk_notification_interaction;
/** The system asked the app to show its notification settings. Owned by the receiver. */
typedef struct ntk_notification_settings_request ntk_notification_settings_request;
/** Pending or delivered notifications. Owned by the receiver. */
typedef struct ntk_notification_list ntk_notification_list;
/** An event listener registration. */
typedef struct ntk_notification_listener ntk_notification_listener;

typedef void (NTK_CALL *ntk_notification_done_fn)(void* user_data, ntk_notification_error error, uint32_t system_code);
/** granted is 1 when permitted, 0 when not. ntk_notification_has_permission_async gives 0 for
    NTK_NOTIFICATION_STATUS_EPHEMERAL; ntk_notification_request_permission_async gives 1. */
typedef void (NTK_CALL *ntk_notification_permission_fn)(void* user_data, ntk_notification_error error,
                                                        uint32_t system_code, int32_t granted);
typedef void (NTK_CALL *ntk_notification_status_fn)(void* user_data, ntk_notification_error error,
                                                    uint32_t system_code,
                                                    ntk_notification_authorization_status status);
/** list is NULL unless error is NTK_NOTIFICATION_ERROR_NONE. */
typedef void (NTK_CALL *ntk_notification_list_fn)(void* user_data, ntk_notification_error error,
                                                  uint32_t system_code, ntk_notification_list* list);
/** response is NULL when there is none for now: until the app first becomes active it can appear later. Use
    the interaction listener when you can (ntk_notification_interaction_is_launch). */
typedef void (NTK_CALL *ntk_notification_launch_fn)(void* user_data, ntk_notification_error error,
                                                    uint32_t system_code, ntk_notification_interaction* response);
typedef void (NTK_CALL *ntk_notification_interaction_fn)(void* user_data, ntk_notification_interaction* event);
typedef void (NTK_CALL *ntk_notification_settings_request_fn)(void* user_data,
                                                              ntk_notification_settings_request* request);

#pragma pack(push, 8)
/** kind decides which fields are read; the others are not. */
typedef struct ntk_notification_trigger {
    uint32_t                      struct_size;
    uint32_t                      reserved0;
    ntk_notification_trigger_kind kind;
    int32_t                       repeats;              /**< TIME_INTERVAL, CALENDAR. */
    double                        interval_seconds;     /**< TIME_INTERVAL: above 0; 60 or more when repeating. */
    uint32_t                      calendar_fields;      /**< CALENDAR: NTK_NOTIFICATION_CALENDAR_*; not 0. */
    int32_t                       year;
    int32_t                       month;
    int32_t                       day;
    int32_t                       hour;
    int32_t                       minute;
    int32_t                       second;
    uint32_t                      reserved1;
    const char*                   location_identifier;  /**< LOCATION. */
    double                        latitude;
    double                        longitude;
    double                        radius;
    int32_t                       not_notify_on_entry;  /**< Nonzero: do not notify when entering. */
    int32_t                       notify_on_exit;       /**< Nonzero: notify when leaving. Location triggers need the
                                                             location permission and its Info.plist text. */
} ntk_notification_trigger;

/* Every element of an array has the same struct_size. */
typedef struct ntk_notification_action {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* identifier;
    const char* title;
    const char* sf_symbol_name;                         /**< NULL: none. */
    uint32_t    options;                                /**< NTK_NOTIFICATION_ACTION_*. */
    uint32_t    reserved1;
} ntk_notification_action;

typedef struct ntk_notification_text_input_action {
    uint32_t    struct_size;
    uint32_t    reserved0;
    const char* identifier;
    const char* title;
    const char* button_title;
    const char* placeholder;
} ntk_notification_text_input_action;

typedef struct ntk_notification_category {
    uint32_t                                  struct_size;
    uint32_t                                  reserved0;
    uint32_t                                  options;  /**< NTK_NOTIFICATION_CATEGORY_*. */
    uint32_t                                  reserved1;
    const char*                               identifier;
    const ntk_notification_action*            actions;
    size_t                                    action_count;
    const ntk_notification_text_input_action* text_input_actions;
    size_t                                    text_input_action_count;
} ntk_notification_category;
#pragma pack(pop)

/** Installs the library's UNUserNotificationCenter delegate, keeping the current one as the previous
    delegate. Main thread only; synchronous; never waits. Call it before
    application(_:didFinishLaunchingWithOptions:) returns (or inside scene(_:willConnectTo:options:)).
    Off the main thread it returns NTK_NOTIFICATION_ERROR_WRONG_THREAD at once and does nothing. It may be called
    from SwiftUI's App.init. Calling it before UIApplicationMain is outside the contract. */
ntk_notification_error NTK_CALL ntk_notification_install(void);

/* Without permission (the status is not authorized, provisional or ephemeral) these three end with
   NTK_NOTIFICATION_ERROR_PERMISSION_DENIED and add nothing; a status that changes right after the check is not
   caught. */
/** trigger may be NULL: deliver now. */
ntk_notification_error NTK_CALL ntk_notification_show_async(const ntk_notification_content* content,
                                                            const ntk_notification_trigger* trigger,
                                                            ntk_notification_done_fn callback, void* user_data,
                                                            ntk_release_fn release);
/** Replaces the pending request of identifier, or adds it. The id of content is not used. trigger may be
    NULL: deliver now. With NTK_NOTIFICATION_ERROR_ADD_REQUEST_FAILED the previous request is already gone. */
ntk_notification_error NTK_CALL ntk_notification_update_async(const char* identifier,
                                                              const ntk_notification_content* content,
                                                              const ntk_notification_trigger* trigger,
                                                              ntk_notification_done_fn callback, void* user_data,
                                                              ntk_release_fn release);
/** The id of content is not used. trigger must not be NULL. */
ntk_notification_error NTK_CALL ntk_notification_schedule_async(const char* identifier,
                                                                const ntk_notification_content* content,
                                                                const ntk_notification_trigger* trigger,
                                                                ntk_notification_done_fn callback, void* user_data,
                                                                ntk_release_fn release);

/* The order against other calls is decided by these completions: add new requests after the callback. */
ntk_notification_error NTK_CALL ntk_notification_remove_async(const char* identifier,
                                                              ntk_notification_done_fn callback, void* user_data,
                                                              ntk_release_fn release);
/** Also removes what the host app delivered itself. */
ntk_notification_error NTK_CALL ntk_notification_remove_all_async(ntk_notification_done_fn callback, void* user_data,
                                                                  ntk_release_fn release);
ntk_notification_error NTK_CALL ntk_notification_cancel_scheduled_async(const char* identifier,
                                                                        ntk_notification_done_fn callback,
                                                                        void* user_data, ntk_release_fn release);
/** Also cancels what the host app scheduled itself. */
ntk_notification_error NTK_CALL ntk_notification_cancel_all_scheduled_async(ntk_notification_done_fn callback,
                                                                            void* user_data, ntk_release_fn release);

ntk_notification_error NTK_CALL ntk_notification_get_scheduled_async(ntk_notification_list_fn callback,
                                                                     void* user_data, ntk_release_fn release);
ntk_notification_error NTK_CALL ntk_notification_get_delivered_async(ntk_notification_list_fn callback,
                                                                     void* user_data, ntk_release_fn release);
/** options: NTK_NOTIFICATION_AUTH_*; an unknown bit is rejected. Put everything in the first request: once the
    status is decided, the system is not asked again and the current status is reported. Needs the foreground
    only while the status is undetermined. */
ntk_notification_error NTK_CALL ntk_notification_request_permission_async(uint32_t options,
                                                                          ntk_notification_permission_fn callback,
                                                                          void* user_data, ntk_release_fn release);
ntk_notification_error NTK_CALL ntk_notification_get_authorization_status_async(ntk_notification_status_fn callback,
                                                                                void* user_data,
                                                                                ntk_release_fn release);
ntk_notification_error NTK_CALL ntk_notification_has_permission_async(ntk_notification_permission_fn callback,
                                                                      void* user_data, ntk_release_fn release);
/** Needs the foreground. */
ntk_notification_error NTK_CALL ntk_notification_open_settings_async(ntk_notification_done_fn callback,
                                                                     void* user_data, ntk_release_fn release);
ntk_notification_error NTK_CALL ntk_notification_set_badge_count_async(int32_t count,
                                                                       ntk_notification_done_fn callback,
                                                                       void* user_data, ntk_release_fn release);
/** The callback comes after the write and one read-back; the read-back is not reported. */
ntk_notification_error NTK_CALL ntk_notification_register_category_async(const ntk_notification_category* category,
                                                                         ntk_notification_done_fn callback,
                                                                         void* user_data, ntk_release_fn release);
ntk_notification_error NTK_CALL ntk_notification_remove_category_async(const char* identifier,
                                                                       ntk_notification_done_fn callback,
                                                                       void* user_data, ntk_release_fn release);

/* These three return NTK_NOTIFICATION_ERROR_NOT_INITIALIZED until the delegate has been installed. Up to
   32 events wait for the next listener when there is none. */
ntk_notification_error NTK_CALL ntk_notification_add_interaction_listener(ntk_notification_interaction_fn callback,
                                                                          void* user_data, ntk_release_fn release,
                                                                          ntk_notification_listener** out_listener);
/** Comes only for an app that asked for NTK_NOTIFICATION_AUTH_PROVIDES_APP_SETTINGS: in its first request here, or
    natively with requestAuthorization. */
ntk_notification_error NTK_CALL ntk_notification_add_settings_request_listener(
    ntk_notification_settings_request_fn callback, void* user_data, ntk_release_fn release,
    ntk_notification_listener** out_listener);
ntk_notification_error NTK_CALL ntk_notification_get_launch_response_async(ntk_notification_launch_fn callback,
                                                                           void* user_data, ntk_release_fn release);
/** Removes the registration. The handle is invalid afterwards; user_data is not until release. Does nothing
    for NULL. */
void NTK_CALL ntk_notification_listener_remove(ntk_notification_listener* listener);

/* The builder. Setters copy what they receive. A NULL string restores the default. */
/** id must not be empty. */
ntk_notification_error NTK_CALL ntk_notification_content_create(const char* id, const char* title,
                                                                ntk_notification_content** out_content);
void NTK_CALL ntk_notification_content_free(ntk_notification_content* content);
ntk_notification_error NTK_CALL ntk_notification_content_set_subtitle(ntk_notification_content* content,
                                                                       const char* subtitle);
ntk_notification_error NTK_CALL ntk_notification_content_set_body(ntk_notification_content* content, const char* body);
/** 0 or more; -1 means not set. */
ntk_notification_error NTK_CALL ntk_notification_content_set_badge(ntk_notification_content* content, int32_t badge);
/** name is required for NTK_NOTIFICATION_SOUND_NAMED and not read otherwise. */
ntk_notification_error NTK_CALL ntk_notification_content_set_sound(ntk_notification_content* content,
                                                                    ntk_notification_sound_kind kind,
                                                                    const char* name);
ntk_notification_error NTK_CALL ntk_notification_content_set_category(ntk_notification_content* content,
                                                                       const char* identifier);
ntk_notification_error NTK_CALL ntk_notification_content_set_interruption_level(
    ntk_notification_content* content, ntk_notification_interruption_level level);
ntk_notification_error NTK_CALL ntk_notification_content_set_thread(ntk_notification_content* content,
                                                                     const char* identifier);
ntk_notification_error NTK_CALL ntk_notification_content_set_target_content(ntk_notification_content* content,
                                                                             const char* identifier);
/** 0.0 to 1.0. */
ntk_notification_error NTK_CALL ntk_notification_content_set_relevance_score(ntk_notification_content* content,
                                                                              double score);
ntk_notification_error NTK_CALL ntk_notification_content_set_filter_criteria(ntk_notification_content* content,
                                                                              const char* criteria);
/** A JSON object without null and without the reserved top-level key "com.jonghyunkim.nativetoolkit". */
ntk_notification_error NTK_CALL ntk_notification_content_set_user_info_json(ntk_notification_content* content,
                                                                             const char* json);
/** file_url is a file:// URL. The system moves the file when the notification is added, so a second use of the
    same builder fails with NTK_NOTIFICATION_ERROR_ATTACHMENT_LOAD_FAILED. */
ntk_notification_error NTK_CALL ntk_notification_content_add_attachment(ntk_notification_content* content,
                                                                         const char* identifier,
                                                                         const char* file_url);

/* Readers: pointers stay valid until the handle is freed. out_size may be NULL. */
/** -1 for NULL. */
ntk_notification_event_kind NTK_CALL ntk_notification_interaction_kind(const ntk_notification_interaction* event);
const char* NTK_CALL ntk_notification_interaction_notification_id(const ntk_notification_interaction* event,
                                                               size_t* out_size);
const char* NTK_CALL ntk_notification_interaction_action_id(const ntk_notification_interaction* event, size_t* out_size);
/** "" when the notification has no category. */
const char* NTK_CALL ntk_notification_interaction_category_id(const ntk_notification_interaction* event,
                                                           size_t* out_size);
/** The reply of a TEXT_INPUT response, or NULL. */
const char* NTK_CALL ntk_notification_interaction_user_text(const ntk_notification_interaction* event, size_t* out_size);
/** A JSON object. Dates are ISO 8601 strings, data is Base64, values that are not finite are null. */
const char* NTK_CALL ntk_notification_interaction_user_info_json(const ntk_notification_interaction* event,
                                                              size_t* out_size);
/** Nonzero when this response launched the app. A background action followed at once by bringing the app forward
    can also count. */
int32_t     NTK_CALL ntk_notification_interaction_is_launch(const ntk_notification_interaction* event);
void        NTK_CALL ntk_notification_interaction_free(ntk_notification_interaction* event);

/** NULL when the request came from the Settings app. */
const char* NTK_CALL ntk_notification_settings_request_notification_id(
    const ntk_notification_settings_request* request, size_t* out_size);
void        NTK_CALL ntk_notification_settings_request_free(ntk_notification_settings_request* request);

size_t      NTK_CALL ntk_notification_list_count(const ntk_notification_list* list);
const char* NTK_CALL ntk_notification_list_identifier_at(const ntk_notification_list* list, size_t index,
                                                         size_t* out_size);
const char* NTK_CALL ntk_notification_list_title_at(const ntk_notification_list* list, size_t index, size_t* out_size);
const char* NTK_CALL ntk_notification_list_subtitle_at(const ntk_notification_list* list, size_t index,
                                                       size_t* out_size);
const char* NTK_CALL ntk_notification_list_body_at(const ntk_notification_list* list, size_t index, size_t* out_size);
const char* NTK_CALL ntk_notification_list_category_at(const ntk_notification_list* list, size_t index,
                                                       size_t* out_size);
/** Unix milliseconds of a delivered notification; 0 for a scheduled one or an index out of range. */
int64_t     NTK_CALL ntk_notification_list_date_millis_at(const ntk_notification_list* list, size_t index);
void        NTK_CALL ntk_notification_list_free(ntk_notification_list* list);

#ifdef __cplusplus
}
#endif
#endif
```

### A.5 `NativeToolkitC/Share.h`

```c
#ifndef NATIVETOOLKITC_SHARE_H
#define NATIVETOOLKITC_SHARE_H

#if defined(__has_include) && __has_include(<IosLibraryCApi/NativeToolkitC/Common.h>)
#include <IosLibraryCApi/NativeToolkitC/Common.h>
#else
#include "Common.h"
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* The rules of this header (design part 1, chapter 1):
   - Every function can be called from any thread and never waits for the main thread. Completions,
     events and an accepted call's release run on the main thread, and never inside the function when
     you call it on the main thread; called elsewhere, a completion can come before the function
     returns, before an output parameter is visible. Match results through user_data.
   - NONE from a function with a completion callback means accepted, and then the callback comes exactly once
     while the process lives (dialogs and shares: see their callback types). A listener gets zero or more
     events until it is removed. Any other value means rejected: no callback, and release (if not NULL) has
     already been called on your thread. Do not free user_data yourself then. A NULL callback is rejected.
   - After removing a listener off the main thread, events can still come until release. Free user_data
     in release, not when the function returns.
   - Callbacks must not let exceptions escape, and must not block the main thread for long.
   - Text comes back as UTF-8; invalid surrogates and U+0000 become U+FFFD.
   - Zero-filled means every field except struct_size.
   - Enumerations can grow: write a default branch. */
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
    NTK_SHARE_ERROR_FILE_NOT_FOUND = 9,
    NTK_SHARE_ERROR_INVALID_URI = 17,
    NTK_SHARE_ERROR_IMAGE_LOAD_FAILED = 18,
    NTK_SHARE_ERROR_SHOW_FAILED = 19,
    NTK_SHARE_ERROR_CANCELED_BY_SYSTEM = 20,
    NTK_SHARE_ERROR_ACTIVITY_FAILED = 21
};

typedef int32_t ntk_share_item_kind;
enum {
    NTK_SHARE_ITEM_TEXT = 0,
    NTK_SHARE_ITEM_URL = 1,
    NTK_SHARE_ITEM_IMAGE_FILE = 2,
    NTK_SHARE_ITEM_FILE = 3
};

/** The result of a share. Owned by the receiver: free it with ntk_share_result_free. */
typedef struct ntk_share_result ntk_share_result;

/** result is NULL unless error is NTK_SHARE_ERROR_NONE. A share cannot be cancelled, so the callback and release,
    and with them user_data, can be held for as long as a host that replaced its window or root view controller,
    or a scene the system disconnected, keeps the sheet alive. On an iPad with several windows, which one shows
    the sheet is not decided. The order of the callbacks of several shares is not promised. */
typedef void (NTK_CALL *ntk_share_result_fn)(void* user_data, ntk_share_error error, uint32_t system_code,
                                             ntk_share_result* result);

#pragma pack(push, 8)
/** Every element of an array has the same struct_size. */
typedef struct ntk_share_item {
    uint32_t            struct_size;
    uint32_t            reserved0;
    ntk_share_item_kind kind;
    uint32_t            reserved1;
    const char*         value;                   /**< The text, the URL, or the file path. */
} ntk_share_item;

typedef struct ntk_share_request {
    uint32_t              struct_size;
    uint32_t              reserved0;
    const ntk_share_item* items;
    size_t                item_count;
    const char*           subject;               /**< NULL: none. */
    const char*           preview_title;         /**< NULL: none. */
    const char* const*    excluded_activity_types;
    size_t                excluded_activity_type_count;
} ntk_share_request;
#pragma pack(pop)

/** Needs the foreground: otherwise the callback gets NTK_SHARE_ERROR_NOT_FOREGROUND. */
ntk_share_error NTK_CALL ntk_share_content_async(const ntk_share_request* request, ntk_share_result_fn callback,
                                                 void* user_data, ntk_release_fn release);

/** 0 when the user closed the sheet. */
int32_t     NTK_CALL ntk_share_result_completed(const ntk_share_result* result);
/** The identifier of the chosen activity, or NULL. Valid until the handle is freed. out_size may be NULL. */
const char* NTK_CALL ntk_share_result_activity_type(const ntk_share_result* result, size_t* out_size);
void        NTK_CALL ntk_share_result_free(ntk_share_result* result);

#ifdef __cplusplus
}
#endif
#endif
```
