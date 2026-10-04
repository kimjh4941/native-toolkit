# 段階 0e の結果: パッケージ名の変更

- 実施日: 2026-10-04
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0e と D-15
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（機械的な改名だけ。0d の基準と同じ結果になった）

## 1. 結論

`android_library` の名前空間（`namespace`）と Kotlin の package を、`android.library` から `com.jonghyunkim.nativetoolkit` に変えた。確かめは、改名で実際に壊れうる所（クラス名を文字列や manifest で持つ所）に絞って両方の環境で流した（3 章）。全体の実行と 0d の基準との比べ合わせは、README 7 章の決定（2026-10-04）に従って 0h の後に行う。

保存と通信の識別子（`SharedPreferences` の名前、Alarm の action、Intent の extra の名前）は、クラス名ではないので変えていない。1b で予約の保存形式を作り直すときに、新しい名前を設計書で決める。

## 2. 変えたもの

| 対象 | 変更 |
|---|---|
| `android/android_library/build.gradle.kts` | `namespace = "com.jonghyunkim.nativetoolkit"`（テストの APK の id も `com.jonghyunkim.nativetoolkit.test` になる） |
| `android_library` の `src/{main,test,androidTest}/java/` | `android/library/` を `com/jonghyunkim/nativetoolkit/` に `git mv` で移し、package の宣言・import・KDoc の参照・クラス名と同じログのタグを置き換えた |
| クラス名を文字列で持つ所 | `CallStyleNotificationFactory` と `ProgressForegroundServiceIntents` が前景サービスのクラス名を文字列で持つ。新しい名前に変えた（変えないとサービスが見つからない） |
| `android_library` の androidTest の manifest | `FocusActivity` の名前 |
| `android/android_library/MODULE.md`（Dokka） | package の名前 |
| `unity_android_plugin`（ブリッジ） | `android_library` を呼ぶ import だけ。ブリッジ自身の package（`android.unity.*`、テストは `android.plugin`）は変えない（段階 3 で消す） |
| サンプル（`AndroidLibraryExample/app`）と、その androidTest | `android_library` を呼ぶ import だけ |
| `scripts/test_android.sh` | ライブラリの instrumented テストの実行先を `com.jonghyunkim.nativetoolkit.test/...` とパッケージ `com.jonghyunkim.nativetoolkit` に |
| `scripts/test_android.baseline.*.json` | ライブラリのテストの名前（単体テスト 83 件と instrumented テスト 20 件の計 103 件）を、新しいパッケージの名前に機械的に置き換えた。成否は変えていない（0h の後の比べ合わせで、名前の変わったテストが「無くなった・増えた」と出ないようにするため。0d の時点の内容は git の履歴にある） |

置き換えは `.kt` と `.xml` の `android.library.` を `com.jonghyunkim.nativetoolkit.` に変える機械的なもので、Gradle のプラグインの id（`com.android.library`、`libs.plugins.android.library`）には触れていない。

**変えなかったもの:**

| 対象 | 理由 |
|---|---|
| `NotificationSchedulerSupport` の `android.library.notification.action.SHOW_SCHEDULED`（action）、`android.library.notification.scheduler`（`SharedPreferences` の名前）、`android.library.notification.extra.COMMAND`（extra の名前） | クラス名ではなく、保存と通信の識別子。0e は動作を変えない段で、1b で保存形式を作り直す（D-11）。`HostPhaseTest` の同じ名前の定数もそのまま |
| マニュアル（`manual/<版>/`） | 版ごとのフォルダで、1.12.0 までの内容は正しい。2.0.0 のマニュアルは段階 4 で書く |
| `docs/`（Dokka が生成したもの） | リリースのときに作り直す |
| `artifact/` の過去の記録 | 当時の名前のまま残す |

## 3. 確かめたこと

| 確認 | 結果 |
|---|---|
| ビルド | 全モジュール（release の AAR 2 つ、サンプル、テストの APK、共有先アプリ）が組めた |
| AAR の中身 | `classes.jar` のクラスはすべて `com/jonghyunkim/nativetoolkit/` の下。manifest の `package` は `com.jonghyunkim.nativetoolkit` |
| サンプルに組み込まれた後の manifest | ライブラリの Receiver 2 つ（`ScheduledNotificationReceiver`、`ScheduledNotificationBootReceiver`）と Service 2 つ（`CallStyleForegroundService`、`ProgressForegroundService`）が `com.jonghyunkim.nativetoolkit.notification.…` になった |
| 単体テスト | 161 件すべて成功（ライブラリ 83、ブリッジ 77、サンプル 1）。ライブラリのテストは新しいパッケージの名前で報告された |
| 改名で壊れうる所のテスト（両方の環境） | 実機・エミュレータとも 45 件すべて成功。内訳は、前景サービスをクラス名で起動する `NotificationCallUiTest` 8 件と `NotificationProgressUiTest` 4 件、manifest の Receiver で予約を出す `NotificationScheduleUiTest` 3 件、ライブラリの instrumented テスト 20 件（テストの APK の id が `com.jonghyunkim.nativetoolkit.test` に変わった）、ブリッジの instrumented テスト 10 件 |
| 全体の実行と 0d の基準との比べ合わせ | 0h の後に行う（README 7 章、2026-10-04 の決定）。Host（再起動の後の `BOOT_COMPLETED` の Receiver）もそこで確かめる |

## 4. 改名の前の作り方（1b で 1.x の Alarm を取り消すため）

PendingIntent が同じかどうかは、action・data・type・受け手のクラス名（component）・package・category と request code で比べられる。改名で受け手のクラス名が変わったので、**2.0.0 のコードがそのまま `alarmManager.cancel` を呼んでも、1.x で登録した Alarm には当たらない**。1b では、下の値で Intent を組み直し、`FLAG_NO_CREATE` で探してから取り消す。

| 項目 | 1.x（改名の前）の値 |
|---|---|
| Alarm の受け手（component） | `<アプリのパッケージ>/android.library.notification.data.repository.ScheduledNotificationReceiver` |
| action | `android.library.notification.action.SHOW_SCHEDULED` |
| data の URI | `native-toolkit-notification://<アプリのパッケージ>/<tag か untagged>/<id>`（`Uri.Builder` の scheme・authority・path 2 つ） |
| package | `Intent.setPackage(<アプリのパッケージ>)` |
| request code | `"<tag か untagged>::<id>".hashCode()`（`NotificationSchedulerSupport.scheduleKey`） |
| PendingIntent の種類と flags | `PendingIntent.getBroadcast`、`FLAG_UPDATE_CURRENT or FLAG_IMMUTABLE` |
| Alarm の種類 | `setExactAndAllowWhileIdle` / `setExact` / `setAndAllowWhileIdle` / `set`（予約の `exact`・`allowWhileIdle` と正確なアラームの許可で選ぶ） |
| 保存 | `SharedPreferences` `android.library.notification.scheduler` の `entries`（文字列の集合）。各要素は JSON で、キー `android.intent.extra.shortcut.ID` に `"<tag か untagged>::<id>"`、`command` と `schedule` に Parcel を Base64 にしたもの。**取り消しに要る id と tag は、Parcel を読まずに `android.intent.extra.shortcut.ID` から取り出せる** |
| extra | `android.intent.extra.shortcut.ID`（上と同じキー）、`android.library.notification.extra.COMMAND`（Parcel の payload） |

1.x で予約した Alarm が 2.0.0 への更新の後に発火すると、受け手のクラス名が manifest に無いので、配られずに捨てられると考えられる（確かめていない。1b の更新のテストで確かめる）。更新の後の `MY_PACKAGE_REPLACED` で動く `restoreScheduled` は、保存の Parcel に古いクラス名が入っているため読めず、`runCatching` で黙って捨てる（README 1 章、D-11）。

## 5. このリポジトリの外への影響

`unity-native-plugin`（別リポジトリ）の `Runtime/Notification/AndroidNotificationManager.cs`（654 行）が、通知の表示のイベントを `AndroidJavaProxy("android.library.notification.NotificationShownSupport$NotificationShownListener")` で受けている。0e の後にこのリポジトリで作った AAR を Unity で使うと、このイベントだけが受け取れなくなる。

- Unity の側は段階 2c で C ABI に移し、この参照は無くなる。それまでに Unity の側で取る基準（段階 1 の前）は、1.12.0 の出荷物の AAR で取る
- README 5.2 の「段階ごとに壊れる場所」に足した
