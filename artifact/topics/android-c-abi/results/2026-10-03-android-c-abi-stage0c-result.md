# 段階 0c の結果: サンプルの UI テスト

- 実施日: 2026-10-03
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0c、`designs/2026-10-03-android-c-abi-ui-test-design.md` の 3・4・6・7 章と 9 章の 0c
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（サンプルとライブラリのコードは変えていない。新しいテストは今のコードで両方の環境で通る）

## 1. 結論

設計書 6 章のテストケース 98 件のうち、H-04（ホストのスクリプトだけで確かめる。段階 0d）を除く全件をテストにした。API 36 の実機と API 35 のエミュレータの両方で、サンプルの UI テスト・ライブラリの instrumented テスト・`HostState` の 6 件が通る（2 章。エミュレータの不安定さは、テストの基盤を直して流し直した）。

設計書から変えたのは、Compose のボタンの押し方、外からの Intent を受けるテストの土台、通知のタイトルの期待値など、OS の実際の動作に合わせたテストの側の作りだけである（4 章）。ライブラリの instrumented テストの失敗 9 件も、テストの作りの問題だったのでテストの側で直した（5 章）。

## 2. 確かめたこと

**全体の実行**（`scripts/test_android.sh --serial <端末>`。エミュレータは単体テストを省いた `--skip-unit`）:

| 対象 | 実機（Pixel 6a、API 36） | エミュレータ（API 35） |
|---|---|---|
| 単体テスト（`android_library`、`unity_android_plugin`、`:app`） | 161 件すべて成功 | 流していない（環境に依らない） |
| サンプルの UI テスト（18 クラス） | 115 件すべて成功 | 115 件のうち 113 件成功。S-12 と R-03 が失敗（下の再実行で解消） |
| ライブラリの instrumented テスト | `android_library` 20 件、`unity_android_plugin` 9 件、すべて成功 | 同じ |
| `HostState`（N-02〜N-05、N-09、N-50） | 6 件すべて成功 | 6 件すべて成功 |
| 合計 | 311 件すべて成功 | 150 件のうち 148 件成功 |

**全体の実行の後に直したものと、その再実行:** エミュレータの 2 件の失敗は、どちらも前の実行では通っていたもので、Sharesheet の読み込みと起動の遅さによる不安定さだった。テストの基盤（`Sharesheet`、`UiApp.launch`、`UiApp.open`。4 章）を直し、直したものを使うクラスだけを両方の環境で流し直した。全体の実行は、段階 0d で基準を取るときに行う。また、スクリプトが雛形のテスト 2 件（ブリッジのパッケージ `android.plugin` の 1 件と、サンプルのパッケージ `example.android` の 1 件）を流していなかったので足した（これで `unity_android_plugin` は設計書どおり 10 件）。

| 再実行 | 実機 | エミュレータ |
|---|---|---|
| `ShareUiTest`、`ReceivedShareUiTest`、`ReceivedShareLaunchUiTest`、`NotificationTapUiTest`、ブリッジの雛形 1 件（`Sharesheet.choose` と `UiApp.launch` を直した後） | 27 件すべて成功 | 27 件のうち 26 件成功。S-08 が「共有先が Sharesheet に出ない」で失敗 |
| `ShareUiTest`（`Sharesheet.find` を直した後） | 17 件のうち 16 件成功。S-12 が「Share の画面が開かない」で失敗 | 流していない（実行中に別のテストを流して止めてしまったため） |
| `ShareUiTest` 2 回、`ReceivedShareUiTest`、`ReceivedShareLaunchUiTest`、`NotificationTapUiTest`、サンプルの雛形 1 件（`UiApp.open` を直した後） | 44 件すべて成功 | 44 件すべて成功 |

`Host`（H-01〜H-03 の 1 段目の `HostPhaseTest`）は、2 段目をホストのスクリプトが行うので、段階 0d で流す。人の確認（CU-01、CU-02）の手順書は `android/AndroidLibraryExample/app/src/androidTest/ComputerUse/` に置いた。証拠のスクリーンショットは段階 0d の基準を取るときに撮る。

**環境:**

| 環境 | fingerprint | 備考 |
|---|---|---|
| 実機 | `google/bluejay/bluejay:16/BP2A.250705.008/13578956:user/release-keys` | Pixel 6a、Android 16、en-US |
| エミュレータ | `google/sdk_gphone64_arm64/emu64a:15/AE3A.240806.036/12592187:user/release-keys` | AVD `Pixel_8_Android_15`、イメージ `system-images/android-35/google_apis_playstore/arm64-v8a`、1080x2400、420dpi、メモリ 2048 MB、en-US |

## 3. 段階 0c の最初に確かめたもの（設計書 9 章）

確かめるのに使ったコードは `probes/stage0c/Stage0cProbeTest.kt`（ビルドには入れない）。

| 項目 | 実機（API 36） | エミュレータ（API 35） | テストでの扱い |
|---|---|---|---|
| 段階 0a の技法（エミュレータ） | - | シェード・Dialog・Sharesheet・Toast・権限のダイアログとも、0a と同じ技法で扱えた | そのまま使う |
| style の値（3.2） | 下の表 | 実機と同じ | `EXTRA_TEMPLATE` と `EXTRA_COMPAT_TEMPLATE` のどちらかが期待の style なら合格 |
| サンプル自身が Sharesheet に並ぶか（S-16） | 並ぶ（一覧のスクロール 1 回） | 並ぶ（スクロール無し） | S-16 をテストにした |
| 通話のボタン（3.9） | シェードに `android:id/action0` のボタンとして並ぶ。文言は `content-desc` にある。着信 [Decline, Video]、通話中 [Hang Up]、スクリーニング [Hang Up, Answer] | 同じ | シェードで、左から順に押す（`extras` の PendingIntent は使わない） |
| 前景サービスの通知の遅れ | 10.8 秒 | 10.7 秒 | 15 秒まで待つ（設計書どおり） |
| アプリの通知の自動のまとめ | まとめ役は ID 0、group `g:Aggregate_AlertingSection` | まとめ役は tag `ranker_group`、ID 2147483647 | ID だけで探す。件数では判定しない |

**style ごとの値**（両方の環境で同じ）:

| 通知 | `EXTRA_TEMPLATE` | `EXTRA_COMPAT_TEMPLATE` |
|---|---|---|
| Default（1001）、Progress（1009） | 無し | 無し |
| BigText（1002） | `Notification$BigTextStyle` | `NotificationCompat$BigTextStyle` |
| Inbox（1003）、まとめ（1100） | `Notification$InboxStyle` | `NotificationCompat$InboxStyle` |
| BigPicture（1004） | `Notification$BigPictureStyle` | `NotificationCompat$BigPictureStyle` |
| Messaging（1005） | `Notification$MessagingStyle` | `NotificationCompat$MessagingStyle` |
| Media（1006） | `Notification$MediaStyle` | 無し |
| DecoratedCustomView（1007） | `Notification$DecoratedCustomViewStyle` | `NotificationCompat$DecoratedCustomViewStyle` |
| DecoratedMediaCustomView（1008） | `Notification$DecoratedMediaCustomViewStyle` | 無し |
| 通話（着信・通話中・スクリーニング） | `Notification$CallStyle` | 無し |

## 4. 設計書から変えたこと（テストの作り）

| 項目 | 設計書 | 実際 | 理由 |
|---|---|---|---|
| Compose のボタンの押し方 | testTag で探して押す | testTag で探し、`performSemanticsAction(SemanticsActions.OnClick)` で押す | `performClick`（タッチの注入）は、シェードを閉じた直後や画面の配置が動いた直後に別のボタンに当たり、ほかのテストの状態の表示が出ることがあった |
| 外から Intent を受けるテスト | Compose のルール | Compose のルールを使わない土台 `ExternalLaunchUiTest`。サンプルを `UiApp`（UiAutomator）で起動し、testTag のリソース ID で操作する。各テストの後にサンプルを閉じる | `MainActivity`（`singleTask`）が `onNewIntent` を受けるか背面に回ると（Sharesheet は別のタスクで開く、通知のタップ、共有の受け取り）、Compose のルールが Activity を見失い「Current state was null」「No compose hierarchies found」で落ちた。Share・受け取り・通知のタップのテストをこちらに移した |
| R-02（アプリが動いていない状態からの受け取り） | 受け取りのテストと同じ | `createEmptyComposeRule` と `ActivityScenario` で、SEND の Intent から起動する別のクラス（`ReceivedShareLaunchUiTest`） | 起動の Intent そのものを渡す必要がある |
| Messaging の通知のタイトル（N-14） | サンプルの文言 | `Native Toolkit Example: You` | API 35/36 は MessagingStyle の `EXTRA_TITLE` をシステムが付け直す |
| 通話の通知のタイトル（N-40〜N-47） | サンプルの文言 | 発信者の名前 `Native Toolkit Support`。着信・通話中・スクリーニングは本文（`INCOMING` など）で見分ける | CallStyle の `EXTRA_TITLE` は発信者の名前になる |
| Media の通知のボタン | 文言で探す | 文言が無ければ `content-desc` で探す | Media のボタンは画像だけで、文言を持たない |
| Dialog のボタンの文言 | 完全一致 | 大文字と小文字を区別しない | プラットフォームの Dialog はボタンの文言を大文字で描く（`NO`） |
| 通知のスワイプ | 行の高さで右へ | 通知の行（`expandableNotificationRow`）そのものを右へスワイプ | エミュレータで、座標のスワイプでは消えないことがあった |
| Sharesheet の共有先 | 文言で探して押す | 探すときは、まず 5 秒待ち、出なければ下へ、それでも出なければ上へ、それぞれ 6 回までスクロールして探す。押した後に Sharesheet が閉じるのを 3 秒待ち、閉じなければ（見つけた要素が古くなったときも）3 回まで探し直して押す。閉じるときは開いたのを待ってから Back | エミュレータでは共有先の読み込みが遅く、読み込みの途中で一覧が並び直る。先に下までスクロールすると、後から上に出た共有先を見逃し（S-08）、押しが外れることもあった（S-12） |
| サンプルの起動（`UiApp.launch`） | - | メニューが 10 秒で出なければ、ホームに戻して 1 回だけ起動し直す | エミュレータで一度、起動の後 10 秒たってもメニューが出なかった（R-03） |
| メニューから画面を開く（`UiApp.open`） | - | 開いた画面の Back が 4 秒で出なければ、メニューが残っている間は 3 回まで押し直す | 実機で一度、起動の直後にメニューを押しても画面が開かなかった（S-12） |
| 待つものが無い確認（S-13、C-06） | - | 2 秒待ってから、変わっていないことを確かめる | 「何も起きない」ことには待つ合図が無い |
| 基盤のクラス | `SystemWindows`、`Cleanup` | `DeviceState` にまとめた（`allowAll`、`cleanup`、`closeSystemWindows`）。設定の画面と権限のダイアログは、それを使う 2 つのテストクラスの中で扱う | 使う所が少ない |

共有先アプリ（`testShareTarget`）は設計書どおり作った。targetSdk 35 は edge-to-edge が強制され、値の View がステータスバーの下に入って UiAutomator から見えなかったので、`fitsSystemWindows` を付けた。

## 5. ライブラリの instrumented テストの直し

段階 0c で初めて、ライブラリの instrumented テストを 2 つの環境で流した。今のコードのまま 9 件が落ちたが、どれもテストの作りの問題で、ライブラリとブリッジのコードは変えていない。

| テスト | 原因 | 直し |
|---|---|---|
| `ClipboardRepositoryImplTest`、`ClipboardChangeMonitorTest`（7 件） | Android 10 以降は、入力のフォーカスを持つアプリしかクリップボードを読めず、変更の通知も届かない。テストの APK には前面に出る Activity が無かった | テスト専用の空の Activity（`android/library/testing/FocusActivity`、androidTest の AndroidManifest）を足し、`ActivityScenarioRule` で前面に出す |
| `ClipboardChangeMonitorTest#start_calledTwice_doesNotRegisterDuplicateListener` | 前面に出したことで通知が届くようになり、1 回のコピーで通知が 2 回届いて「1 回以下」の判定が落ちた（モニターの登録は 1 回だけで、2 回目の `start` は無視されたとログで確かめた。システムがコピーした文字の分類の後にもう一度送るためと考えられる）。これまでは通知が 0 回で、たまたま通っていた | システムに直接登録した基準のリスナーと同じ回数だけ呼ばれることを確かめる（重複して登録すれば 2 倍になるので、テストの意図は保つ） |
| `ShareChooserActionInstrumentedTest#manager_shareTextThenBroadcast_listenerReceivesAction` | `shareText` は Receiver の登録を main スレッドに回すので、登録の前にブロードキャストを送ることがあった | `shareText` の後に `waitForIdleSync()` で登録を待つ |

## 6. スクリプト

設計書 9 章の「最小のスクリプト」より先まで作った（8 章の 0〜5 と 7、8 の件数の表示）。基準の保存と比べ合わせ（8 の残り）と `Host` の段（6）は段階 0d で足す。

| ファイル | 内容 |
|---|---|
| `scripts/android_instrument.py` | 1 回の `am instrument -w -r` を流し、テストごとの `INSTRUMENTATION_STATUS_CODE` を JSON の行で出す。終わりの無いテスト、プロセスの停止、最後の行が無い、0 件、時間切れを失敗にする |
| `scripts/test_android.sh` | ブリッジの instrumented テストは、パッケージ `android.unity` と `android.plugin`（雛形の 1 件）の 2 回に分けて流す。サンプルの雛形（`example.android.ExampleInstrumentedTest`）も流す。端末の記録、単体テスト、APK のビルドと導入、端末の状態（3.5）、クラスごとの UI テスト、ライブラリの instrumented テスト、`HostState` の 1 件ずつの実行、後片付けと件数の表示 |

**端末の状態で見つけたこと:**

- エミュレータでは、`SCHEDULE_EXACT_ALARM` の appop が UID の単位で `allow` になっていて、パッケージの単位で `default` にしても拒否にならなかった（N-02、N-50 が落ちた）。スクリプトは、状態をそろえるときと「正確なアラームの拒否」を作るときに、UID の単位の値も `default` に戻す
- 端末の再起動の後に画面のロック（キーガード）が残っていると、Compose のテストがすべて落ちる。スクリプトは最初に `wm dismiss-keyguard` で外す（0b の結果と同じ）
