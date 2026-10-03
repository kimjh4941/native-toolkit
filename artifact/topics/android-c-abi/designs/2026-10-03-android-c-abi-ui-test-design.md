# UI テスト設計書（段階 0）

- 作成日: 2026-10-03
- 改訂: 2026-10-03 に別モデル 2 者のレビュー（`reviews/2026-10-03-android-c-abi-ui-test-design-review-v1.md`）を反映した
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0b 〜 0d
- 入力:
  - `artifact/topics/android-c-abi/README.md`（7 章 検証方法、7.2 の試験環境）
  - `artifact/topics/android-c-abi/results/2026-10-03-android-c-abi-stage0a-spike-result.md`（段階 0a）
  - `artifact/android/clipboard/designs/2026-07-25-android-clipboard-sample-app-design-v3.md` の 6 章（手動確認の観点 23 項目）
  - `artifact/android/share/designs/2026-06-21-android-share-sample-app-design-v4.md` と `2026-06-20-android-share-sample-app-design-v3.md` の手動確認
  - サンプルアプリのコード（Notification と Dialog はサンプルアプリの設計書が無いので、確かめる観点はコードから起こした）
- 手本: `artifact/topics/windows-architecture/designs/2026-09-19-windows-architecture-ui-test-design.md`
- 決定事項: 10 章（U-1 〜 U-10。2026-10-03 にすべて決定）

## 1. 目的と範囲

段階 0e〜0h と 1b の前後で「ネイティブの利用者から見た動作が変わっていないこと」を判定できるよう、サンプルアプリの Dialog / Notification / Share / Clipboard のすべてに UI テストをそろえる（README 7.1）。手動テストは行わない。

| 範囲 | 内容 |
|---|---|
| 対象 | Dialog・Notification・Share の UI テストの新規作成、受け取った共有の画面のテスト、Clipboard の既存の UI テスト（14 件）に無い観点の追加。テストの基盤（`infra`）。テスト専用の共有先アプリ（U-10）。人の確認の手順書。サンプルへの testTag の追加（段階 0b）。検証スクリプト（段階 0d） |
| 対象外 | 音・振動（どの手段でも確かめられない。チャンネルの設定値は確かめる）。外部のアプリとのクリップボードのやり取り（U-7）。2 台目の端末が要る確認。環境に依存して起こせない異常系（`ClipboardUnavailable`、FileProvider の失敗、Share の `❌ null` の経路など）。全画面の通知が拒否されたときの動作（拒否の状態が、アプリの入れ方によって変わり、テストの環境で作れない。3.5） |

ライブラリの C ABI は、このテストの対象ではない（サンプルは Kotlin の API だけを使う。README 7.1）。

## 2. 方針

- **2 つの手段を使い分ける。** アプリ内の画面は Compose UI test（`createAndroidComposeRule<MainActivity>`）で、システムの UI（通知のシェード、Sharesheet、権限のダイアログ、設定の画面）と View の Dialog（`DialogFragment`）と共有先アプリの画面は UiAutomator で扱う
- **通知の中身はアプリの中から読む。** テストはサンプルと同じプロセスで動くので、`NotificationManager.getActiveNotifications()` で通知の中身を読める（3.2）。シェードは、押す・スワイプする・表示されることを確かめるときだけ使う
- **今の動作を基準にする。** 気になる動作（3.8）を見つけても段階 0 では直さず、今の動作のままを期待値にする。直すのは段階 1b 以降で、そのとき期待値を変えた理由を記録する
- **期待値はコードの文字列そのもの。** 6 章の期待値は、サンプルとライブラリのコードの文字列を写す。「全文」「各段」のような書き方はしない
- **他のアプリの情報を記録しない。** シェードと Sharesheet には他のアプリの通知や共有先・連絡先が出る。ログ・ダンプ・スクリーンショットには、サンプルの通知と、サンプルと共有先アプリが扱う中身だけを残す。**失敗したときもシェードと Sharesheet の画面の構造を書き出さない。** `dumpsys notification` はサンプルのパッケージと対象の ID の行だけを、流れの中で取り出し、元の出力は保存しない
- **固定の待ち時間を使わない。** 条件が満たされるまで待つ。例外は 2 つ: 予約した時刻の前に「まだ出ていない」ことを確かめるとき（U-3）と、予約を取り消した後に「出ない」ことを確かめるとき（N-53）
- **テストは互いに独立させる。** テストごとにアプリの画面を開き直し、前後で 4 章の `Cleanup` を行う。スクリプトは実行の最初にアプリのデータを消す（3.5）
- **表示言語に依存しない。** サンプルと共有先アプリの文言（英語の定数）で探すのはよい。システムの UI は、リソース ID か、サンプルの文言か、並び（通話のボタン）で探す。システムの文言（「Allow」「Answer」「Clear all」など）では探さない

## 3. 操作の技法

### 3.1 段階 0a で確かめたもの

`results/2026-10-03-android-c-abi-stage0a-spike-result.md` の 3 章・4.2 のとおり（API 36 の実機）。API 35 のエミュレータでは段階 0c の最初に同じものを確かめる。

| 対象 | 技法 |
|---|---|
| 通知のシェード | `UiDevice.openNotification()`。通知は、サンプルの文言で探す。**BigText の通知は展開されると、タイトルが `bigContentTitle`、本文が `bigText` に置き換わる** |
| 通知のボタン | 文言（`Accept` など）で探して押す。見えなければ通知を下へスワイプして展開する |
| 通知のスワイプ（dismiss） | 通知の行の高さで、画面の幅いっぱいに右へスワイプする |
| アプリ内の Dialog | UiAutomator でボタンの文言を探して押す（`DialogFragment` は View なので Compose のルールからは見えない） |
| Sharesheet | 共有先と Chooser Action を文言で探して押す。共有先の並びは使用の履歴で変わるので、見つからなければ一覧をスクロールして探す |
| 通知の権限のダイアログ | ホストで取り消してから（3.5）、`com.android.permissioncontroller:id/permission_allow_button` / `permission_deny_button` を押す |
| Toast | `UiAutomation.setOnAccessibilityEventListener` で `TYPE_NOTIFICATION_STATE_CHANGED` のうち、クラスが `android.widget.Toast`、パッケージがサンプルのもので、操作の後に来たものだけを集める |

### 3.2 通知の中身を読む

`NotificationManager.getActiveNotifications()` の `StatusBarNotification` から読む。**ID で探す。** Android 15/16 はアプリの通知を自動でまとめることがあり、そのときシステムが作るまとめ役の通知（tag `ranker_group`）が一覧に入るので、件数では判定せず、tag `ranker_group` は無視する。

| 確かめるもの | 読み方 |
|---|---|
| 出ている・消えた | ID（1001〜1200）の有無 |
| タイトル・本文・サブテキスト | `extras` の `EXTRA_TITLE` / `EXTRA_TEXT` / `EXTRA_SUB_TEXT` |
| style | `extras` の `EXTRA_TEMPLATE` と `NotificationCompat.EXTRA_COMPAT_TEMPLATE` の両方を見て、どちらかが期待の style なら合格（ライブラリは全 style を `NotificationCompat` で作るので、API の版で入り方が変わりうる）。段階 0c の最初に、両方の環境で style ごとの実際の値を確かめて記録する |
| 展開したときの中身 | `EXTRA_TITLE_BIG`（展開したときのタイトル）、`EXTRA_BIG_TEXT`、`EXTRA_TEXT_LINES`、`EXTRA_MESSAGES`、`EXTRA_SUMMARY_TEXT`、`EXTRA_CONVERSATION_TITLE` |
| 画像 | `EXTRA_PICTURE` か `EXTRA_PICTURE_ICON` のどちらかがある（API 31 以降は Icon のとき後者に入る）。大きいアイコンは `EXTRA_LARGE_ICON` か `getLargeIcon()` |
| 進捗 | `EXTRA_PROGRESS` / `EXTRA_PROGRESS_MAX` / `EXTRA_PROGRESS_INDETERMINATE` |
| ongoing・前景サービス | `flags` の `FLAG_ONGOING_EVENT` / `FLAG_FOREGROUND_SERVICE` |
| グループ | `notification.group`（`sbn.groupKey` ではない）、`sortKey`、`FLAG_GROUP_SUMMARY`、`groupAlertBehavior` |
| チャンネル | `notification.channelId` と、`NotificationManager.getNotificationChannel(id)` の名前・重要度（スクリプトがアプリのデータを消すので、サンプルの定義どおりになる。3.5） |
| アクション | `notification.actions` の `title`（通話のボタンは入らない。3.9） |
| カテゴリ・全画面 | `notification.category`、`notification.fullScreenIntent` |

**待ち時間:**

- dataSync の前景サービスの通知は、即時表示の条件に当たらない。Android 12 以降は、起動から最長 10 秒表示が遅れ、その間は一覧にも出ない。前景サービスの通知を待つときは 15 秒まで待つ。実際に遅れるかを段階 0c で両方の環境で確かめる
- 通知の更新は 1 アプリあたり 1 秒に約 5 回までに制限され、超えた分は捨てられる。同じ ID を続けて更新するテスト（N-30、N-32）は、前の値が一覧に出たのを確かめてから次のボタンを押す

画面に表示されることは、シェードで代表の文言を 1 つ見つけて確かめる（3.1）。

### 3.3 設定の画面

設定の画面を開くボタンは、ボタンを押した後に `com.android.settings` のウィンドウ（`By.pkg("com.android.settings")`）が出るのを待つ（`UiDevice.currentPackageName` は最後にイベントを出したパッケージなので、それだけでは判定しない）。Back でサンプルのウィンドウに戻るのを待ってから、状態の表示を確かめる（サンプルは `startActivity` の直後に状態の表示を変えるので、戻った後に見える）。

### 3.4 共有の中身の確かめ方

| 確かめるもの | 方法 |
|---|---|
| 共有の中身（S-01〜S-09、S-11〜S-15） | **テスト専用の共有先アプリ（`testShareTarget`。U-10）**を Sharesheet で選ぶ。共有先アプリは受け取った中身を画面に出すので、UiAutomator で読む。Back で閉じるとサンプルの Share の画面に戻る（サンプルの画面は残り、コールバックの結果も出る） |
| Direct Share（S-10） | サンプルのショートカット `Sample User` はサンプル自身を指すので、サンプルの受け取りの画面（`Received Share`）で `Direct Share target` を確かめる |
| サンプル自身が共有先に並び、受け取れること（S-16） | Sharesheet でサンプル（`Native Toolkit Example`）を選び、受け取りの画面を確かめる。並ぶかは段階 0c の最初に確かめ、並ばなければ S-16 を対象外にする（受け取りは R-xx で確かめる） |
| 受け取り（R-01〜R-07） | Sharesheet を通さず、テストから `SEND` / `SEND_MULTIPLE` の Intent を `startActivity` で送る |

**共有先アプリ（`testShareTarget`）:**

| 項目 | 内容 |
|---|---|
| 置き場所 | `android/AndroidLibraryExample/testShareTarget/`（Gradle のモジュール `:testShareTarget`。application id `com.jonghyunkim.android.nativetoolkit.testsharetarget`、表示名 `NTK Share Target`） |
| 受けるもの | `SEND` / `SEND_MULTIPLE` の `text/*`、`image/*`、`*/*` |
| 画面に出すもの | `action`、`type`、`EXTRA_TEXT`、`EXTRA_SUBJECT`、`EXTRA_TITLE`、Stream の URI の数と、URI ごとの表示名（`OpenableColumns.DISPLAY_NAME`）・MIME・中身（テキストなら先頭 200 文字、画像なら大きさ）。各値の View にリソース ID（`result_action` など）を付ける |
| 動作 | 表示するだけ。保存も送信もしない。Back で終わる |
| 配り方 | 配布物（`dist/`）にもサンプルにも入れない。スクリプトが `:testShareTarget:installDebug` で入れる |

### 3.5 端末の状態

| 状態 | 切り替え方 | テストの中でできるか |
|---|---|---|
| 通知の権限（許可） | `UiAutomation.grantRuntimePermission` | できる |
| 通知の権限（取り消し） | `pm revoke` と `pm clear-permission-flags ... user-set user-fixed` | **できない**（取り消すとアプリのプロセスが止まる）。ホストのスクリプトが行う |
| アプリの通知の無効化 | API 33 以降は、設定の通知のスイッチが通知の権限の取り消しそのもの | 通知の権限の取り消しと同じ扱い（ホスト） |
| 正確なアラーム（許可） | `appops set <pkg> SCHEDULE_EXACT_ALARM allow` | できる |
| 正確なアラーム（拒否） | `appops set <pkg> SCHEDULE_EXACT_ALARM default` | **できない**（取り消すとアプリのプロセスが止まり、予約した正確なアラームもすべて取り消される。公式文書）。ホストのスクリプトが行う |
| 全画面の通知 | `appops set <pkg> USE_FULL_SCREEN_INTENT allow` | できる。`default` が拒否になるかはアプリの入れ方で変わる（Play から入れたアプリ以外は既定で許可されうる）ので、拒否の状態はテストしない。スクリプトは `appops get` の値を結果に記録する |

**スクリプトがそろえる状態**（実行の最初。8 章）:

| 状態 | 内容 |
|---|---|
| アプリのデータ | `pm clear` でサンプルのデータを消す（チャンネルは一度作ると重要度を上げられないので、前の版のサンプルや手動の確認で作ったチャンネルを消すため。予約・ショートカット・権限も消える） |
| 権限 | 通知の権限を許可、正確なアラームと全画面の通知を `allow` |
| 画面 | `svc power stayon true`（終わったら元に戻す）。ロックされていれば止める。アニメーションを切る（`am instrument --no-window-animation`） |
| 応答不可（DND） | 切れていることを確かめる。入っていれば止める |
| 再起動を伴う段（`Host`） | PIN などのロックがかかっていないことを確かめる（ロックがあると、解除するまで `BOOT_COMPLETED` が届かない） |

実行の最後には、権限を許可、`appops` を `allow` に戻し、`svc power stayon` を元の値に戻す。開発用の実機（利用者の確認済み）なので、利用者のデータへの影響は考えなくてよい。

### 3.6 Compose の要素の探し方

- ボタンと状態の表示は testTag で探す（段階 0b。5 章）。文言では探さない（Share の「Share with Callback」のように、同じ文言のノードが 2 つある）
- 状態の表示の文言は部分一致で比べる
- 一覧は `LazyColumn` なので、押す前に `performScrollToNode` でスクロールする
- UiAutomator から状態の表示を読むときは `By.res(<testTag>)` で探す（`testTagsAsResourceId`）

### 3.7 プロセスをまたぐ確認（`Host`）

再起動・アプリの更新・プロセスの停止をまたぐ確認は、テストの中ではできないので、ホストのスクリプトが段を分けて行う。

| ID | 1 段目（テスト） | ホストの操作 | 2 段目（ホストの確認） |
|---|---|---|---|
| H-01 | 保存する予約（ID 9101）と保存しない予約（ID 9102）を 120 秒後に作る | `adb install -r`（同じ APK） | 予約の時刻の後に、2 つとも出ている |
| H-02 | 同じものを 120 秒後に作る | `adb reboot`。起動の完了（`sys.boot_completed=1`）を 180 秒まで待つ | 予約の時刻の後に、9101 だけが出ている |
| H-03 | 保存する予約（ID 9103）を 15 秒後に作る | すぐに `adb reboot` し、起動の完了を待つ | 起動の後に 9103 が出ている（`restoreScheduled` が時刻を過ぎた分をその場で出す） |
| H-04 | 無し | `am force-stop` の後、`am start -W -a android.intent.action.SEND -t text/plain --es android.intent.extra.TEXT <本文> -n <サンプル>/.MainActivity` | ホストが `uiautomator dump` で画面の構造を読み、リソース ID `receivedShare.action` / `receivedShare.mimeType` / `receivedShare.text` の値だけを取り出して確かめる（testTag がリソース ID として見えるため。5.1）。`am instrument` は始めに対象のアプリを止めるので、2 段目にテストのクラスは使わない。元のダンプは端末から消し、保存しない |

1 段目のテストは、Kotlin の API（`NotificationUseCases.schedule`）を直接呼んで遅い時刻の予約を作る（サンプルの予約は 15 秒後で、再起動に足りない）。保存の書き込みは `apply()` なので（段階 0a の 4.1）、作った後に同じ `SharedPreferences`（`android.library.notification.scheduler`）に空の `commit()` をして、書き込みが終わるのを待つ（`commit()` は手元の内容全体を同期で書く）。

2 段目の確認は `dumpsys notification --noredact` の出力を流しながら、サンプルのパッケージと対象の ID の行だけを取り出して判定する（2 章）。H-04 は `uiautomator dump` から、サンプルのリソース ID の値だけを取り出す。どちらも 2 段目でテストのクラスを流さない（`am instrument` は対象のアプリを止め直すため）。

**結果のまとめ方:** スクリプトは H-xx を 1 件のテストとして扱い、`am instrument` の結果と同じ形式（クラス `Host`、名前 `H-01_installReplace` など、結果 passed / failed、失敗の理由）で結果のファイルに書く。どの段で失敗しても、その H-xx は failed にし、後片付け（予約の取り消し、通知の片付け）をしてから次へ進む。再起動の完了を待ち切れなかったときは、残りの H-xx を飛ばして failed にする。

### 3.8 今の動作で気になったもの（段階 0 では直さない）

| 動作 | 扱い |
|---|---|
| Share のエラーの表示が `❌ null`（`ShareDomainError` が message を持たない） | 起こせる場面が無いので、テストの対象外 |
| Dialog のログインの結果に、パスワードが平文で出る | 今の動作のまま期待値にする。ログの規則の例外（README 8.6）と合わせて 1b で扱う |
| 「Use 'Open Notification Settings' above」「Use 'Open Exact Alarm Settings' above」の「above」は誤り | 今の文言のまま期待値にする |
| `✅ Channel created: <id>` は同じクリックの中ですぐ上書きされ、見えない | 期待値にしない |
| 前景サービスの中での失敗は、状態の表示に出ない（`startService` の成否だけ） | 通知の中身（3.2）で確かめる |
| `Stop Progress FGS` は、`Complete` の後の通知を消さない | 今の動作のまま期待値にする |
| Dialog はすべて `cancelable=false` で、キャンセルの経路に届かない | 期待値にする（Back と外側のタップで閉じないこと） |
| 受け取りの画面は `SEND_MULTIPLE` の本文を表示しない | 今の動作のまま期待値にする |
| Share のコールバックは、Sharesheet を閉じても結果を出さない（waiting のまま） | 今の動作のまま期待値にする |

### 3.9 通話のボタン

プラットフォームの CallStyle（API 31 以降）は、応答・拒否・切るのボタンを `notification.actions` に入れず、`extras` の PendingIntent（`EXTRA_ANSWER_INTENT`、`EXTRA_DECLINE_INTENT`、`EXTRA_HANG_UP_INTENT`）からシステムが描く。文言もシステムが付け、ビデオの着信では応答が「Video」になりうる。そこで:

1. シェードで通話の通知の中のボタンを、並び（左が拒否・切る、右が応答）で押す
2. 段階 0c の最初に両方の環境で 1 の取り方が成り立つかを確かめる。成り立たなければ、`extras` の PendingIntent をテストから `send()` する（シェードは通らないが、サービスの状態の変化は確かめられる）。どちらにしたかを 0c の結果に記録する

## 4. テストの基盤（`infra`）

`android/AndroidLibraryExample/app/src/androidTest/java/com/jonghyunkim/android/nativetoolkit/example/infra/` に置く。テストは画面ごとのクラスを使い、UiAutomator と `NotificationManager` を直接使うのは `infra` だけにする。

| 追加するもの | 役割 |
|---|---|
| `SampleApp` | メニューから画面を開く、testTag のボタンを押す、状態の表示を待つ（Compose） |
| `NotificationShade` | 開く、閉じる、サンプルの文言で通知を探す、展開する、ボタンを押す、通話のボタンを並びで押す、スワイプで消す |
| `ActiveNotifications` | ID で通知を探し、3.2 の項目を読む。出るまで待つ（既定 10 秒、前景サービスは 15 秒）、消えるまで待つ |
| `Sharesheet` | 開いたのを待つ、共有先・Chooser Action・Direct Share の共有先を文言で探し（スクロールして）押す、閉じる |
| `ShareTargetApp` | 共有先アプリの画面の値を読む、閉じる |
| `SystemWindows` | 通知の権限のダイアログ、設定の画面の判定と戻り（3.3） |
| `ViewDialogs` | `DialogFragment` のタイトル・本文・ボタン・項目・入力欄を UiAutomator で操作し、読む。入力欄が伏せ字かは `AccessibilityNodeInfo.isPassword` で読む |
| `Toasts` | 3.1 の条件で Toast の文言を集め、待つ |
| `DeviceState` | 権限の許可、正確なアラームと全画面の通知の `allow` |
| `Cleanup` | テストの前後に行う: 進捗の前景サービスの停止（`ProgressForegroundNotifications.stop`）、通話の前景サービスの停止（停止の Intent）、予約の取り消し（ID 1010 と H-xx の ID）、Direct Share のショートカット `sample_1` の削除、`cancelAll()`、サンプルの通知が一覧から無くなるまで待つ、シェードと Sharesheet と共有先アプリを閉じる |

## 5. サンプルアプリの変更（段階 0b）

### 5.1 testTag を付ける

すべてのボタンと状態の表示に testTag を付ける。`MainActivity` の Compose のルートに `Modifier.semantics { testTagsAsResourceId = true }` を付け、UiAutomator からもリソース ID として見えるようにする。

| 対象 | testTag の付け方 | 例 |
|---|---|---|
| メニューのカード | `menu.<画面>` | `menu.dialog`、`menu.notification`、`menu.share`、`menu.clipboard` |
| ボタン | `<画面>.<ボタンの文言の lowerCamelCase>`（記号と括弧は除く） | `notification.showActionButtonsSample`、`share.shareWithCallback`、`clipboard.copyUriContentViaFileProvider` |
| 状態の表示 | `<画面>.status` | `dialog.status`、`notification.status` |
| 戻るボタン | `<画面>.back` | `share.back` |
| 受け取りの画面の値 | `receivedShare.<ラベル>` | `receivedShare.action`、`receivedShare.mimeType`、`receivedShare.text`、`receivedShare.streamUris`、`receivedShare.directShareTarget` |

ボタンの数: メニュー 4、Dialog 6、Notification 46、Share 14、Clipboard 16、各画面の戻る 5。

**見た目も動作も変えない。** testTag は見た目に影響しない。

**一覧のテスト（`TagInventoryTest`）を足す。** 各画面を開き、上の数の testTag がすべて在り、重複していないことを確かめる。段階 0b では、既存の Clipboard の 14 件とこのテストが通ることを確かめる。

### 5.2 そのほかの変更

無い（U-3、U-4）。Windows では 5 秒後に予約するボタンを足したが、Android の予約は 15 秒後なので足さない。Toast でしか結果を出さないもの（DeleteIntent、Chooser Action、画面の外での通知のボタン）は、3.1 のとおり Toast を読むので、サンプルは変えない。共有先アプリ（U-10）はサンプルの変更ではなく、テストのためのモジュールとして段階 0c で足す。

## 6. テストケース

期待値は、サンプルとライブラリのコードの文字列そのもの（2 章）。`✅` などの記号を含めて部分一致で比べる。表の「状態」は状態の表示（`<画面>.status`）に出る文言。

### 6.1 メニューと移動（`Navigation`）

| ID | 操作 | 期待 |
|---|---|---|
| M-01 | メニュー → 各画面（4）→ `← Back to Main` | 各画面の見出し（`Dialog Example` / `Notification Example` / `Share Example` / `Clipboard Example`）が出て、メニュー（`Native Toolkit Example`）に戻る |
| M-02 | 各画面でシステムの Back | メニューに戻る |
| M-03 | Dialog の結果を出す → メニュー → Dialog に戻る | 結果の表示が残っている（`rememberSaveable`） |
| M-04 | Notification / Share / Clipboard で状態を変える → メニュー → 戻る | 状態の表示が初期値（Notification は `Explore notification samples. Start by checking the current permission state.`、Share と Clipboard は `Result will be displayed here`）に戻る |

### 6.2 Dialog（新規。`Dialog`）

結果の表示は `✅` の後に改行して `Result: ...` が続く。下の表は `Result: ` より後ろを書く。

| ID | 操作 | 期待 |
|---|---|---|
| D-01 | ShowDialog → `OK` | タイトル `Hello from Android`、本文 `This is a native Android dialog!`、ボタン `OK`。結果 `onDialog - buttonText: OK, errorMessage: null` |
| D-02 | ShowConfirmDialog → `Yes` | タイトル `Confirmation`、本文 `Do you want to proceed with this action?`、ボタン `No` / `Yes`。結果 `onConfirmDialog - buttonText: Yes, errorMessage: null` |
| D-03 | ShowConfirmDialog → `No` | `onConfirmDialog - buttonText: No, errorMessage: null` |
| D-04 | ShowSingleChoiceItemDialog → そのまま `OK` | タイトル `Please select one`、項目 `Option 1` / `Option 2` / `Option 3`、`Option 1` が選ばれている。結果 `onSingleChoiceItemDialog - buttonText: OK, checkedItem: 0, errorMessage: null` |
| D-05 | ShowSingleChoiceItemDialog → `Option 3` → `OK` | `buttonText: OK, checkedItem: 2, errorMessage: null` |
| D-06 | ShowSingleChoiceItemDialog → `Cancel` | `buttonText: Cancel, checkedItem: null, errorMessage: null` |
| D-07 | ShowMultiChoiceItemDialog → そのまま `OK` | タイトル `Multiple Selection`、項目 `Option 1`〜`Option 4`、`Option 2` と `Option 4` にチェック。結果 `onMultiChoiceItemDialog - buttonText: OK, checkedItems: [false, true, false, true], errorMessage: null` |
| D-08 | ShowMultiChoiceItemDialog → `Option 1` にチェック → `OK` | `checkedItems: [true, true, false, true]` |
| D-09 | ShowMultiChoiceItemDialog → `Cancel` | `buttonText: Cancel, checkedItems: null, errorMessage: null` |
| D-10 | ShowTextInputDialog | タイトル `Text Input`、本文 `Please enter your name`、入力欄のヒント `Enter here...`。空の間は `OK` が押せない（`enabled=false`） |
| D-11 | ShowTextInputDialog → `Alice` → `OK` | `onTextInputDialog - buttonText: OK, inputText: Alice, errorMessage: null` |
| D-12 | ShowTextInputDialog → `Cancel` | `buttonText: Cancel, inputText: null, errorMessage: null` |
| D-13 | ShowLoginDialog | タイトル `Login`、本文 `Please enter your credentials`、ヒント `Username` / `Password`。片方だけ入れた間は `Login` が押せない。パスワードの入力欄が伏せ字（`isPassword`） |
| D-14 | ShowLoginDialog → `user1` / `pass1` → `Login` | `onLoginDialog - buttonText: Login, username: user1, password: pass1, errorMessage: null` |
| D-15 | ShowLoginDialog → `Cancel` | `buttonText: Cancel, username: null, password: null, errorMessage: null` |
| D-16 | 各 Dialog を出して Back、Dialog の外側をタップ | どちらでも閉じない（`cancelable=false`、`cancelableOnTouchOutside=false`） |

### 6.3 Notification（新規。`Notification`）

通知の中身は 3.2 で、表示は代表の文言をシェードで確かめる。各テストの前に `Cleanup` をする。

権限と設定（`Notification`）:

| ID | 操作 | 期待 |
|---|---|---|
| N-01 | Check Notification Permission | 状態に `permissionGranted=true`、`notificationsEnabled=true`、`shouldShowRationale=false`、`exactAlarmAllowed=true` |
| N-06 | Open Notification Settings → Back | 設定の画面が開く（3.3）。状態 `ℹ️ Opened notification settings or app details settings.` |
| N-07 | Open App Details Settings → Back | 同上。状態 `ℹ️ Opened app details settings.` |
| N-08 | Open Exact Alarm Settings → Back | 同上。状態 `ℹ️ Opened exact alarm settings or app details settings.` |

ホストが状態を切り替えるもの（`HostState`。スクリプトが 1 件ずつ状態を作ってから流す。U-5）:

| ID | ホストが作る状態 | 操作 | 期待 |
|---|---|---|---|
| N-02 | 正確なアラーム `default` | Check Notification Permission | `exactAlarmAllowed=false` |
| N-03 | 通知の権限を取り消し | Request Notification Permission → 許可 | ダイアログが出る。状態 `✅ Notification permission granted.`。権限が許可になる |
| N-04 | 通知の権限を取り消し | Request → 拒否 → Check | 状態 `❌ Notification permission is not granted. Use 'Open Notification Settings' above to enable it.`。続けて Check で `permissionGranted=false`、`shouldShowRationale=true` |
| N-05 | 通知の権限を取り消し | Show Default Style | 状態 `❌ Unable to show notifications. Check permissions or notification settings.`。通知が無い |
| N-09 | 通知の権限を取り消し | Start Progress FGS 10% / Incoming Call / Schedule Notification (15 sec) | 状態がそれぞれ `❌ Unable to show the progress foreground service. Check permissions or notification settings.` / `❌ Unable to show call notifications. Check permissions or notification settings.` / `❌ Unable to schedule notifications. Check permissions or notification settings.` |
| N-50 | 正確なアラーム `default` | Schedule Notification (15 sec) | 状態 `❌ Exact alarms are not allowed. Use 'Open Exact Alarm Settings' above to enable them.` |

style:

| ID | 操作 | 期待（3.2） |
|---|---|---|
| N-10 | Show Default Style → Delete Default Style | 状態 `✅ Displayed Default style notification.`。ID 1001、タイトル `Native Toolkit`、本文 `Default style notification sample`、サブテキスト `Default`、チャンネル `native_toolkit_sample`（名前 `Native Toolkit Sample`、重要度 3）。シェードに `Default style notification sample`。Delete で消え、状態 `🗑️ Deleted Default Style notification.` |
| N-11 | Show BigText Style → Delete | 状態 `✅ Displayed BigText style notification.`。ID 1002、BigText、`EXTRA_TITLE_BIG` `BigText Style`、`EXTRA_SUMMARY_TEXT` `BigText`、`EXTRA_BIG_TEXT` `This is a BigText notification sample from Native Toolkit Example. Expand the notification to verify the full body text rendering.`。Delete で `🗑️ Deleted BigText Style notification.` |
| N-12 | Show Inbox Style → Delete | 状態 `✅ Displayed Inbox style notification.`。ID 1003、Inbox、行 `• Permission status checked` / `• Channel created successfully` / `• Immediate notification sent` / `• Scheduled notification ready`、`number=4`、要約 `4 sample events`、`EXTRA_TITLE_BIG` `Inbox Style` |
| N-13 | Show BigPicture Style → Delete | 状態 `✅ Displayed BigPicture style notification.`。ID 1004、BigPicture、画像（3.2）と大きいアイコンがある、要約 `Launcher image preview`、`EXTRA_TITLE_BIG` `BigPicture Style`。画像の中身は CU-01 |
| N-14 | Show Messaging Style → Delete | 状態 `✅ Displayed Messaging style notification.`。ID 1005、タイトル `Native Toolkit Team`、`number=3`、Messaging、会話のタイトル `Native Toolkit Example`、グループの会話、メッセージ 3 つ（`Alex` / `Can you verify the notification styles?`、`Jordan` / `Sure, BigText / Inbox / BigPicture / Messaging are ready.`、`You` / `Confirmed. This is the Messaging sample.`） |
| N-15 | Show Media Style → Delete | 状態 `✅ Displayed Media style notification.`。ID 1006、タイトル `Native Toolkit Player`、Media、ongoing、カテゴリ `transport`、アクション `Previous` / `Play` / `Next`。シェードに `Native Toolkit Player` |
| N-16 | Show DecoratedCustomView Style → 展開 → `Dismiss` → Delete | 状態 `✅ Displayed DecoratedCustomView style notification.`。ID 1007。シェードに `Expanded custom notification sample`。`Dismiss` で状態 `✅ Action button pressed: Dismiss (id=custom_view_dismiss, notificationId=1007)`、通知は残る。Delete で消え、`🗑️ Deleted DecoratedCustomView Style notification.`。画像は CU-02 |
| N-17 | Show DecoratedMediaCustomView Style → Delete | 状態 `✅ Displayed DecoratedMediaCustomView style notification.`。ID 1008、ongoing、アクション 3 つ。シェードに `Decorated media custom view sample`。Delete で `🗑️ Deleted DecoratedMediaCustomView Style notification.` |

操作とグループ:

| ID | 操作 | 期待 |
|---|---|---|
| N-20 | Show Group Child 1 → Child 2 → Summary | 状態が順に `✅ Displayed Group Child 1 notification.` / `✅ Displayed Group Child 2 notification.` / `✅ Displayed Group Summary notification.`。ID 1101 / 1102 / 1100、グループ `native.toolkit.grouping.sample`、sortKey `01` / `02` / `00`、1100 が `FLAG_GROUP_SUMMARY`、`groupAlertBehavior` が SUMMARY |
| N-21 | Show Group Alert Behavior | 3 つが出る。状態 `✅ Displayed Group Alert Behavior sample. Verify summary-only alert behavior.` |
| N-22 | Show DeleteIntent Sample → シェードで右へスワイプ | 状態 `✅ Displayed DeleteIntent sample. Swipe the notification and verify the receiver callback.`。通知が消え、Toast `DeleteIntent Sample dismissed (deleteIntent)` |
| N-23 | Show FullScreenIntent Sample | 状態 `✅ Displayed FullScreenIntent reference sample. Depending on device state, it appears as heads-up or full-screen.`。ID 1111、カテゴリ `alarm`、チャンネル `native_toolkit_fullscreen_sample`（重要度 4）、`fullScreenIntent` が null でない。**heads-up か全画面かは判定しない**（端末の状態で変わる） |
| N-24 | Show Action Buttons Sample → シェードで `Accept` → Delete Action Buttons Sample | 状態 `✅ Action button pressed: Accept (id=accept, notificationId=1112)`、通知は残る。Delete で消え、`🗑️ Deleted Action Buttons Sample notification.` |
| N-25 | 同上で `Decline` | `✅ Action button pressed: Decline (id=decline, notificationId=1112)` |
| N-26 | Show Action Buttons Sample → メニューに戻る → シェードで `Accept` | Toast `Accept action pressed` |
| N-27 | Show Default Style → `pressHome` → シェードで通知の本文を押す | サンプルのウィンドウが前面に戻り、Notification の画面のまま。通知は消える（autoCancel） |
| N-28 | Show Media Style → `pressHome` → シェードで `Previous` | サンプルのウィンドウが前面に戻る。通知は残る（ongoing） |

進捗:

| ID | 操作 | 期待 |
|---|---|---|
| N-30 | Show Progress 10% → 50% → 100%（各段で値が出たのを待ってから次） | ID 1009、タイトル `Native Toolkit Download`。進捗 10 → 50 → 100（max 100）。本文 `Downloading sample asset... 10%` → `... 50%` → `Download completed`。10% と 50% は ongoing、100% は ongoing でない。状態 `✅ Displayed progress notification at 10%.` → `✅ Updated progress notification to 50%.` → `✅ Updated progress notification to 100%.` |
| N-31 | Show Indeterminate Progress → Delete Progress | 同じ ID 1009 が、タイトル `Native Toolkit Sync`、本文 `Syncing sample data...`、不定の進捗に置き換わる。状態 `✅ Displayed indeterminate progress notification.`。Delete で消え、`🗑️ Deleted Progress notification.` |
| N-32 | Start Progress FGS 10% → Update 50% → Update 90% → Stop（各段で値が出たのを待つ。前景サービスは 15 秒まで） | ID 1011、タイトル `Native Toolkit Background Sync`、本文 `Running background sync... 10%`、`FLAG_FOREGROUND_SERVICE`、進捗 10 → 50 → 90。状態 `✅ Started dataSync progress foreground service. A 10% notification is now shown.` → `✅ Updated dataSync progress foreground service to 50%.` → `✅ Updated dataSync progress foreground service to 90%.` → `ℹ️ Requested progress foreground service stop.`。Stop で消える |
| N-33 | Start Progress FGS 10% → Complete Progress FGS | 状態 `✅ Completed progress foreground service. It has been downgraded to a regular notification.`。通知は残り、`FLAG_FOREGROUND_SERVICE` でない。本文 `Background sync completed`、`EXTRA_TITLE_BIG` `Background Sync Completed`、`EXTRA_BIG_TEXT` `The background sync finished successfully. This notification was downgraded from a foreground service to a normal notification.`、進捗 100 |
| N-34 | N-33 の後に Stop Progress FGS | 完了の通知は残る（3.8） |

通話（ボタンの押し方は 3.9）:

| ID | 操作 | 期待 |
|---|---|---|
| N-40 | Incoming Call | 状態 `✅ Started foreground service CallStyle sample for Incoming Call.`。ID 1200、カテゴリ `call`、CallStyle、`FLAG_FOREGROUND_SERVICE`、タイトル `Incoming call`、本文 `Native Toolkit Support is calling`、チャンネル `native_toolkit_call_v3` |
| N-41 | Incoming Call → 応答 | 通知のタイトルが `Call in progress` に変わる |
| N-42 | Incoming Call → 拒否 | 通知が消える |
| N-43 | Ongoing Call → Stop Call Foreground Service | 状態 `✅ Started foreground service CallStyle sample for Ongoing Call.`、タイトル `Call in progress`、本文 `Native Toolkit Support connected`。Stop で消え、状態 `ℹ️ Requested call foreground service sample stop.` |
| N-44 | Ongoing Call → 切る | 通知が消える |
| N-45 | Screening Call | 状態 `✅ Started foreground service CallStyle sample for Screening Call.`、タイトル `Screening call`、本文 `Review this call request from Native Toolkit Support` |
| N-46 | Screening Call → 応答 | タイトルが `Call in progress` に変わる |
| N-47 | Screening Call → 切る | 通知が消える |

予約:

| ID | 操作 | 期待 |
|---|---|---|
| N-51 | Schedule Notification (15 sec) | 状態 `✅ Scheduled a high-priority notification for 15 seconds later. (isScheduled=true)`。予約の 10 秒後の時点で ID 1010 が無い（U-3）。予約の時刻の後、25 秒まで待つと出る: タイトル `Native Toolkit`、本文 `Scheduled notification sample`、`EXTRA_TITLE_BIG` `Scheduled BigText`、`EXTRA_BIG_TEXT` `This scheduled notification was queued from Native Toolkit Example.`、カテゴリ `alarm`、チャンネル `native_toolkit_schedule_high`（重要度 4）。出た後の Check Schedule isScheduled は状態 `ℹ️ Schedule Notification is currently not scheduled. (isScheduled=false)` |
| N-52 | Schedule → Check Schedule isScheduled | 状態 `ℹ️ Schedule Notification is currently scheduled. (isScheduled=true)` |
| N-53 | Schedule → Delete Schedule Notification | 状態 `🗑️ Deleted Schedule Notification. Cleared both scheduled and active notifications. (isScheduled=false)`。予約の時刻から 10 秒過ぎても ID 1010 が出ない |

プロセスをまたぐもの（`Host`）は 3.7 の H-01〜H-04。

### 6.4 Share（新規。`Share`）

Sharesheet が開いたことは、Sharesheet のウィンドウが出るのを待って確かめる。中身は共有先アプリ（3.4）の画面で確かめる。

| ID | 操作 | 期待 |
|---|---|---|
| S-01 | Share Text → `NTK Share Target` | 状態 `✅ shareText called`。共有先: action `android.intent.action.SEND`、type `text/plain`、TEXT `Hello from native-toolkit` |
| S-02 | Share URL → 共有先 | 状態 `✅ shareText (URL) called`。TEXT `https://developer.android.com/` |
| S-03 | Share Text with Rich Preview | 状態 `✅ shareText (rich preview) called`。Sharesheet にプレビューのタイトル `Introducing content previews`。共有先: TEXT が URL、TITLE `Introducing content previews` |
| S-04 | Share Text with Custom Action → `Custom` | 状態 `✅ shareText (custom action) called`。Toast `Custom chooser action tapped` |
| S-05 | Share Text with Custom Action → 共有先 | TEXT `Shared with a custom chooser action` |
| S-06 | Share with Subject & Title → 共有先 | 状態 `✅ shareText (subject & title) called`。TEXT `Body text shared from native-toolkit`、SUBJECT `Sample subject line` |
| S-07 | Share Image → 共有先 | 状態 `✅ shareImage called`。type `image/png`、Stream 1 つ、表示名 `share_sample.png` |
| S-08 | Share Multiple Images → 共有先 | 状態 `✅ shareImages called`。action `SEND_MULTIPLE`、Stream 2 つ、表示名 `share_sample_1.png` / `share_sample_2.png` |
| S-09 | Share File → 共有先 | 状態 `✅ shareFile called`。type `text/plain`、表示名 `share_sample.txt`、中身 `Share sample from native-toolkit` |
| S-10 | Register Direct Share Target → Share Text → `Sample User` | 状態 `✅ registerDirectShareTarget called`。サンプルの受け取りの画面に Direct Share target `sample_1`、Text `Hello from native-toolkit` |
| S-11 | Share Multiple Files → 共有先 | 状態 `✅ shareFiles called`。`SEND_MULTIPLE`、表示名 `share_sample_1.txt` / `share_sample_2.txt` |
| S-12 | Share with Callback → 共有先 | 状態 `ℹ️ Sharesheet opened, waiting for result...` → 共有先を閉じた後に `✅ Selected: com.jonghyunkim.android.nativetoolkit.testsharetarget`。TEXT `Hello with callback from native-toolkit` |
| S-13 | Share with Callback → Back で Sharesheet を閉じる | 状態が `ℹ️ Sharesheet opened, waiting for result...` のまま変わらない（3.8） |
| S-14 | Share with Callback + Rich Preview → 共有先 | 状態 `ℹ️ Sharesheet (callback + preview) opened...` → `✅ Selected: com.jonghyunkim.android.nativetoolkit.testsharetarget`。Sharesheet にプレビューのタイトル `Callback with rich preview` |
| S-15 | Share with Callback → Back で閉じる → Cancel Pending Callback | 状態 `✅ cancelPendingCallback called` |
| S-16 | Share Text → `Native Toolkit Example` | サンプルの受け取りの画面に Text `Hello from native-toolkit`（並ばなければ対象外。3.4） |
| S-17 | Register → Remove Direct Share Target | 状態 `✅ removeDirectShareTargets called`。`ShortcutManager` の動的・キャッシュのショートカットに `sample_1` が無い |

受け取り（`ReceivedShare`。Sharesheet を通さない）:

| ID | 操作 | 期待 |
|---|---|---|
| R-01 | 起動中に `SEND`（`text/plain`、本文 `Received text`）を送る | 受け取りの画面（見出し `Received Share`）に自動で移り、Action `android.intent.action.SEND`、MIME type `text/plain`、Text `Received text`、Stream URIs `(none)` |
| R-02 | Activity が無い状態で同じものを送る（`ActivityScenario.launch(Intent)`。プロセスが無い状態は H-04） | 同上 |
| R-03 | `SEND`（`image/png`、Stream 1 つ） | Stream URIs が `1 URI(s):` と URI、Text `(none)` |
| R-04 | `SEND_MULTIPLE`（`image/png`、Stream 2 つ、本文つき） | Stream URIs が `2 URI(s):`、Text `(none)`（3.8） |
| R-05 | `SEND`（本文）に `EXTRA_SHORTCUT_ID=sample_1` | Direct Share target `sample_1` |
| R-06 | R-01 の後に `← Back to Main` → `pressHome` → ランチャーからサンプルを開き直す | メニューに戻る。開き直しても受け取りの画面にならない |
| R-07 | R-01 の後にシステムの Back | 同上 |

既存の `IncomingShareParserInstrumentedTest`（7 件）と `MainActivityIncomingShareInstrumentedTest`（1 件）はそのまま使う。

### 6.5 Clipboard（既存 14 件 + 追加。`Clipboard`）

既存の `ClipboardSampleScreenUiTest` の 14 件はそのまま使う（ボタンを探す方法だけを testTag に変える）。サンプルアプリの設計書の手動確認（23 項目）のうち、既存のテストに無いものを足す。

| ID | 操作 | 期待 | 手動確認の項目 |
|---|---|---|---|
| C-01 | Copy HTML Text → Read Clipboard | 状態 `✅ copyHtmlText called` の後、`✅ Read: label=, mimeTypes=[text/html], items=[{text=Hello, htmlText=<b>Hello</b>, uri=null, coercedText=Hello}]` | 7 |
| C-02 | Copy Plain Text → Read Clipboard | `✅ Read: label=sample, mimeTypes=[text/plain], items=[{text=Hello from native-toolkit, htmlText=null, uri=null, coercedText=Hello from native-toolkit}]` | 7 |
| C-03 | Copy Multiple Text → Read Clipboard | items が 3 つで、全文が `{text=first, ...}, {text=second, ...}, {text=third, ...}`（既存のテストは `text=first` だけを見ている） | 6 |
| C-04 | Copy Plain Text → Get Description | `✅ label=sample, mimeTypes=[text/plain], isStyledText=false, classificationStatus=` で始まる（分類の値は端末で変わるので比べない） | 8 |
| C-05 | Copy Sensitive Text → Read Clipboard | 状態 `✅ copySensitive called (preview suppressed on API 33+)`。Read の items に `text=P@ssw0rd-sample` | 11 の一部 |
| C-06 | Start Observing → `← Back to Main` → Clipboard に戻る → Copy Plain Text | `ℹ️ Clipboard changed` が出ない（再入場で監視が解除されている） | 17 |
| C-07 | Start Observing → Copy Plain Text を 1 回 | `ℹ️ Clipboard changed (1)` か `(2)`（端末によって 2 回届く）。`(0)` でない | 14、15 の一部 |

C-01 の HTML の `coercedText` は `Hello` と書いたが、`coerceToText` の結果は端末で変わりうるので、段階 0c で両方の環境の値を確かめ、違えば `coercedText` は比べない。

対象外（U-7）: 外部のアプリへの貼り付け（手動確認の 1・3・5）、他のアプリでのコピー（13・14 の外部の部分）、センシティブの内容がシステムのプレビューに出ないこと（11）、API 32 以下の Toast（12。試験環境は API 35 と 36）。

## 7. 人の確認の手順書

`android/AndroidLibraryExample/app/src/androidTest/ComputerUse/` に 1 項目 1 ファイルで置く。Windows の決まり（`windows-architecture/README.md` 7.3）に合わせ、判定があいまいなら失敗とする。

| ID | 対象 | 手順の要点 | 合格の条件 |
|---|---|---|---|
| CU-01 | BigPicture の画像と大きいアイコン（`CU-01-bigpicture.md`） | Show BigPicture Style → シェードで展開する | 展開した画像がランチャーのアイコン（`ic_launcher`）。大きいアイコンが丸いランチャーのアイコン（`ic_launcher_round`） |
| CU-02 | カスタムビューのアイコン（`CU-02-custom-view-icon.md`） | Show DecoratedCustomView Style と Show DecoratedMediaCustomView Style → シェードで展開する | 通知の中のアイコン（`notification_icon`）が丸いランチャーのアイコン（`ic_launcher_round`） |

スクリーンショットはサンプルの通知の範囲だけに切り取り、`ComputerUse/evidence/<ID>/<日付>-<段階>-<環境>.png` に保存してコミットする。Claude のデスクトップアプリの computer use で、実機は scrcpy などで画面を Mac に映して確かめる（エミュレータはそのまま見られる）。

## 8. 実行（段階 0d）

`scripts/test_android.sh` で次を順に行う。

0. 対象の端末（`--serial`）を確かめ、機種・API・fingerprint を記録する。基準の fingerprint と違えば警告を出す（基準を取り直す合図。README 7.2）
1. `android/` で単体テストを流す（`:android_library:testReleaseUnitTest`、`:unity_android_plugin:testReleaseUnitTest`、`:app:testDebugUnitTest`）
2. サンプル（`:app:installDebug`）、サンプルのテスト（`:app:installDebugAndroidTest`）、共有先アプリ（`:testShareTarget:installDebug`）、ライブラリの instrumented テストの APK を入れる
3. 端末の状態をそろえる（3.5 の表。`pm clear` の後に権限と `appops`、画面、DND、`appops get` の記録）
4. **テストのクラスごとに** `am instrument -w -r --no-window-animation -e class <クラス> -e notAnnotation <HostState と Host のアノテーション>` を流す。1 つのクラスが落ちても、残りのクラスは流す。ライブラリの instrumented テスト（`android_library` 20 件、`unity_android_plugin` 10 件）も同じく流す
5. `HostState` のテストを 1 件ずつ流す。各テストの前にスクリプトが状態（通知の権限の取り消し、正確なアラームの `default`）を作り、後に 3 の状態へ戻す。途中で止まっても `trap` で戻す
6. `--include-host` を付けたときだけ、`Host` の H-01〜H-04 を 3.7 のとおり流す
7. 端末の状態を 3 に戻し、`svc power stayon` を元に戻す（`trap` で、途中で止まっても戻す）
8. 結果（件数と失敗の一覧）を表示し、基準（`scripts/test_android.baseline.<機種>-<API>.json`）とテストごとに比べ、結果が変わったテスト、増えたテスト、無くなったテストを表示する。`--baseline` を付けたときは、失敗が無ければこの実行の結果を新しい基準として保存する

**`am instrument -r` の結果の読み方:** `INSTRUMENTATION_STATUS_CODE` の 1（開始）・0（成功）・-1（エラー）・-2（失敗）・-3（無視）・-4（前提の不成立）をテストごとに読み、`INSTRUMENTATION_CODE`（最後）、`INSTRUMENTATION_RESULT: shortMsg=Process crashed.`、`INSTRUMENTATION_ABORTED` を見る。次のときはそのクラスを失敗にする: 最後の行が無い、プロセスが落ちた、テストが 0 件、開始したテストに終わりが無い、時間切れ（クラスごとに 15 分）。

| オプション | 内容 |
|---|---|
| `--serial <id>` | 対象の端末。必須（実機とエミュレータの両方がつながっていることがあるため） |
| `--baseline` | 結果を基準として保存する。**全件を流したときだけ受け付ける**（`--filter`、`--skip-unit` とは併用できず、`--include-host` が必要） |
| `--filter <カテゴリ>` | UI テストを絞る（`-e annotation`） |
| `--skip-unit` | 1 を飛ばす |
| `--include-host` | H-01〜H-04 を流す（再起動を伴う） |

失敗が 1 件でもあるか、端末の状態が戻っていなければ、終了コードは 1。結果のファイルは `android/AndroidLibraryExample/app/build/test_android/<日時>/` に出す（コミットしない）。`dumpsys` の元の出力は保存しない（2 章）。

テストのカテゴリ（JUnit のアノテーション）:

| カテゴリ | 内容 |
|---|---|
| `Navigation` | 6.1 |
| `Dialog` | 6.2 |
| `Notification` | 6.3 のうち `HostState` と `Host` 以外 |
| `HostState` | N-02〜N-05、N-09、N-50（ホストが状態を作る。前処理で通知の権限を許可しない） |
| `Share` | 6.4 の S-xx |
| `ReceivedShare` | 6.4 の R-xx |
| `Clipboard` | 6.5 と既存の 14 件 |
| `Host` | H-01〜H-03 の 1 段目のクラス（2 段目と H-04 はホストのスクリプトが確かめる） |

段階 0d で、今のコードで全件が通ることを、API 35（エミュレータ）と API 36（実機）の両方で確かめ、結果を `results/` に記録する。これが 0e〜0h と 1b の判定の基準になる。

## 9. 作業の分け方

| 段階 | 内容 | 確かめ方 |
|---|---|---|
| 0b | 5 章の testTag と `TagInventoryTest` | 既存の Clipboard の UI テスト（14 件）と `TagInventoryTest` が通る。見た目が変わっていない |
| 0c | 最初に、API 35 のエミュレータで段階 0a の技法を確かめ、両方の環境で 3.2 の style の値、3.4 の S-16、3.9 の通話のボタン、前景サービスの通知の遅れを確かめる。そのあと、4 章の基盤、共有先アプリ、6 章のテスト、7 章の手順書。UiAutomator 2.4.0 を足す。クラスごとに `am instrument` を流して結果を読む最小のスクリプトも作る（0d で 8 章の全体に広げる） | 新しいテストが、今のコードで両方の環境で通る |
| 0d | 8 章のスクリプトの全体（`HostState` と `Host` の段、基準） | 全件が通り、基準を記録した |

## 10. 決定事項

| ID | 決めたこと | 決定 | 理由 |
|---|---|---|---|
| U-1 | 通知の中身の確かめ方 | **決定（2026-10-03）: `getActiveNotifications()` で読み、シェードは代表の文言と操作だけ**（3.2） | テストがサンプルと同じプロセスで動くので読める。シェードの構造は OS の版とスキンで変わるが、`extras` は変わりにくい |
| U-2 | ボタンの探し方 | **決定（2026-10-03）: testTag**（5.1）。`testTagsAsResourceId` も付け、UiAutomator からは `By.res(tag)` で探す | 文言は同じものが 2 つある（Share の「Share with Callback」）。testTag は見た目を変えない |
| U-3 | 予約の待ち時間 | **決定（2026-10-03）: サンプルの 15 秒のまま**（ボタンを足さない） | 予約のテストは 3 件で、1 回の実行で 1 分ほど。サンプルの動作を変えずに済む。「まだ出ていない」は 10 秒の時点、「出た」は予約の時刻から 25 秒まで待って確かめる |
| U-4 | Toast でしか出ない結果 | **決定（2026-10-03）: Toast をアクセシビリティのイベントで読む**（サンプルは変えない） | 段階 0a で読めると確かめた |
| U-5 | アプリのプロセスを止める状態の切り替え | **決定（2026-10-03）: カテゴリ `HostState` に分け、ホストが 1 件ずつ状態を作ってから流す**（通知の権限の取り消しと、正確なアラームの拒否） | どちらもアプリのプロセスが止まるので、テストの中ではできない |
| U-6 | 端末の状態 | **決定（2026-10-03）: スクリプトが実行の最初に `pm clear` して状態をそろえ、最後と途中で止まったときに戻す。テストは許可（`allow`）の向きにだけ切り替える** | チャンネルの重要度など、前の実行や手動の確認の状態を持ち越さないため。拒否の向きはプロセスが止まる（U-5） |
| U-7 | 外部のアプリとのクリップボードのやり取り | **決定（2026-10-03）: 対象外** | 共有先アプリと同じく外部のアプリをテストのために作ればできるが、Android 10 以降は前面のアプリしかクリップボードを読めず、監視の通知も前面のアプリにしか届かないので、外部のアプリを前面にすると Clipboard の画面の確認ができない。ライブラリが責任を持つのは `ClipData` の中身で、Read の往復で確かめる |
| U-8 | Share の中身の確かめ方 | **決定（2026-10-03、利用者）: テスト専用の共有先アプリで確かめる**（3.4）。サンプル自身への共有は、並ぶかを確かめてから S-16 の 1 件だけ | サンプル自身を選ぶと受け取りの画面に移り、Share の画面とコールバックの受け取りが消えるので、S-12 と S-14 の結果が見えない（レビュー v1） |
| U-9 | 試験環境 | **決定（2026-10-03）: API 35 のエミュレータと API 36 の実機の両方で、同じテストを流す**（README 7.2） | 0h（targetSdk 36）の前後で、両方の版の基準が要る |
| U-10 | 共有先アプリ | **決定（2026-10-03、利用者）: `android/AndroidLibraryExample/testShareTarget/` に、受け取った中身を表示するだけのアプリを足す**。配布物には入れない | U-8 |
