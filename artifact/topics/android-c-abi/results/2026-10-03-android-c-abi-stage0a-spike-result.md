# 段階 0a スパイク結果: サンプルの UI テストで扱える項目

- 実施日: 2026-10-03
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0a（7.2 の UiAutomator と人の確認の分担を確定する）
- ブランチ: `feature/NTKIT-17`
- 調査用のコード: `probes/stage0a/`（ビルドには入れない。段階 0c で正式なテストに置き換える）

## 1. 結論

- **試した項目は、すべて自動化できる。** 通知のシェード、Dialog、Chooser と Chooser Action、Direct Share の共有先、通知の権限のダイアログ、スケジュール通知、前景サービスの進捗、Media の style、DeleteIntent のどれも UiAutomator で扱えた
- **Toast は、アクセシビリティのイベントで読める。** サンプルが結果を Toast でしか出していない DeleteIntent と Chooser Action も、サンプルを変えずに確かめられる
- **プロセスをまたぐ確認は、ホストのスクリプトの 2 段の手順で自動化できる。** 予約 → アプリの更新か端末の再起動 → `dumpsys notification` で確かめる
- **アプリを更新しても、OS は `AlarmManager` の Alarm を残す。** 保存しない予約（`persistAcrossBoot=false`）も、更新の後に予約どおり発火した。README の D-11 で「確かめていないこと」としていた点
- **見つけたこと:** 予約の保存は `apply()` で非同期に書くので、予約した直後にプロセスが止まると、保存が失われ再起動の後に戻らない（4 章）
- 人の確認に回すのは、README 7.2 の見込みのうち、画像の中身と、音・振動（対象外）だけになる見込み。Direct Share と Media の style は自動化できた

## 2. 環境

| 項目 | 内容 |
|---|---|
| 端末 | Pixel 6a（開発用の実機）、Android 16（API 36）、`google/bluejay/bluejay:16/BP2A.250705.008/13578956`、表示言語 en-US |
| サンプル | debug ビルド（`:app:installDebug`）。Gradle のルートは `android/`（段階 0 の後） |
| テスト | UiAutomator 2.4.0、Compose UI test（BOM 2024.09.00）、AndroidJUnitRunner。`am instrument` で 1 件ずつ実行 |
| エミュレータ（API 35） | このスパイクでは使っていない。0c で同じテストを流す |

## 3. 項目ごとの結果

| 項目 | 手段 | 確かめ方 | 結果 |
|---|---|---|---|
| 通知のアクションのボタン | UiAutomator | `openNotification()` → 通知の中の `Accept` を押す → サンプルの状態の表示 | 「Action button pressed: Accept」が出た |
| スケジュール通知（15 秒） | UiAutomator | 予約 → シェードで待つ | 約 15.5 秒で表示された |
| アプリ内の Dialog | UiAutomator | `ShowDialog` → `OK` を押す → 結果の表示 | 「buttonText: OK」が出た |
| Chooser Action | UiAutomator | `Share Text with Custom Action` → Chooser の `Custom` を押す | 押せた。結果の Toast「Custom chooser action tapped」をアクセシビリティのイベントで読めた |
| DeleteIntent | UiAutomator | シェードで通知の行を画面の幅いっぱいに右へスワイプ | 消えた。Toast「DeleteIntent Sample dismissed (deleteIntent)」を読めた |
| 前景サービスの進捗 | UiAutomator | `Start Progress FGS 10%` → シェードの `ProgressBar` | 見つかった。値は `AccessibilityNodeInfo.rangeInfo` で読む（0c で確かめる） |
| Media の style | UiAutomator | シェードで「Native Toolkit Player」 | シェードの中（`com.android.systemui`、`android:id/title`）にあった |
| Direct Share の共有先 | UiAutomator | `Register Direct Share Target` → `Share Text` → Chooser に「Sample User」 | 並んだ |
| 通知の権限のダイアログ | UiAutomator | ホストで `pm revoke` と `pm clear-permission-flags ... user-set user-fixed` → `Request Notification Permission` → `com.android.permissioncontroller:id/permission_allow_button` | 押せた。「Notification permission granted」が出て、権限が許可になった |
| アプリの更新の後の Alarm | ホストのスクリプト | 予約（保存する 1 件・しない 1 件）→ `adb install -r` → `dumpsys alarm` → 予約の時刻の後に `dumpsys notification` | 更新の後も Alarm が 2 件残り、予約の時刻の 3 秒後に 2 件とも表示された |
| 再起動の後の予約の復元 | ホストのスクリプト | 予約 → `adb reboot` → 起動を待つ → `dumpsys notification` | 保存した予約は、起動の後の `BOOT_COMPLETED` で戻り、予約の時刻に表示された。保存しない予約は消えた |

通知の中の入力欄（RemoteInput）は、ライブラリにもサンプルにも無いので対象外とした（README 7.2 の「自動化できる見込みのもの」から外す）。

## 4. 見つけたこと

### 4.1 予約の保存が失われることがある

`NotificationSchedulerSupport.persist` は `SharedPreferences` に `edit { }`（`apply()`）で書くので、ディスクへの書き込みは後回しになる。スパイクで予約の直後に `am instrument` が終わってプロセスが止まると、保存が失われていた（`entries` が空。Alarm は登録されていた）。そのまま再起動すると予約は戻らなかった。2 秒待ってから終わると保存されていた。

実際のアプリでも、予約した直後にプロセスが止まると起こりうる（`apply()` の書き込みは Activity や Service の停止のときに待たれるが、プロセスが殺されたときは待たれない）。段階 1b で保存形式を変えるとき（D-11）に、書き込みを確実にする（`commit()` にするか、書き終わりを待つ）かを決める。

### 4.2 テストを書くときの注意

| 注意 | 内容 |
|---|---|
| BigText の通知のタイトル | シェードで展開されると、タイトルが `bigContentTitle`（例: 「Interaction / Action Buttons」）、本文が `bigText` に置き換わる。`title` と `message` では見つからない |
| 正確なアラームの権限 | Android 14 以降は `SCHEDULE_EXACT_ALARM` が既定で許可されず、サンプルは「Exact alarms are not allowed」を返す。テストの前に `appops set <pkg> SCHEDULE_EXACT_ALARM allow` を実行する |
| 通知の権限 | テストの前に `UiAutomation.grantRuntimePermission` で許可する。権限のダイアログを試すときだけ、ホストで取り消してから流す（取り消すとアプリのプロセスが止まるため、テストの中ではできない） |
| ボタンを押した直後のシェード | 通知が出る前にシェードを開くと見つからないことがある。通知が出るのを待ってから開く |
| スワイプ | 文字の要素だけをスワイプしても消えない。通知の行を画面の幅いっぱいにスワイプする |
| `connectedDebugAndroidTest` | テストの後にアプリを消すので、アプリのフォルダに置いたダンプや保存データを後で見られない。調べるときは `installDebug` / `installDebugAndroidTest` と `am instrument` で流す |
| 予約の直後のプロセスの終了 | 4.1 のとおり。予約を作るテストは、保存の書き込みを待ってから終える |

## 5. README への反映

- 7.2: 自動化が難しい見込みの表から Direct Share と Media の style を外し、試験環境の結果を書いた
- D-11: 「アプリの更新で Alarm が残るか」を確認済みにした
- 8.6: 予約の保存の書き込みを確実にすることを、Kotlin の API の設計で決める項目に足した
