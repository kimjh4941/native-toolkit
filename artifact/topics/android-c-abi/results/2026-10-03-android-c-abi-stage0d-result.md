# 段階 0d の結果: テストのスクリプトと基準

- 実施日: 2026-10-03
- 対象: `artifact/topics/android-c-abi/README.md` の段階 0d、`designs/2026-10-03-android-c-abi-ui-test-design.md` の 3.7・7・8 章と 9 章の 0d
- ブランチ: `feature/NTKIT-17`
- 判定: **完了**（サンプルとライブラリのコードは変えていない。今のコードで全件が通り、基準を 2 つ記録した）

## 1. 結論

`scripts/test_android.sh` を設計書 8 章の全体（`Host` の段、基準の保存と比べ合わせ、端末の状態の確認）まで広げた。今のコードで、API 36 の実機と API 35 のエミュレータの両方で全件が通り、それぞれの結果を基準として保存した。0e〜0h と 1b は、この基準とテストごとに比べて判定する。

人の確認（CU-01、CU-02）も両方の環境で行い、すべて合格した（4 章）。

## 2. 基準

`scripts/test_android.sh --serial <端末> --include-host --baseline` で流し、失敗が 0 件だったので保存した。

| 対象 | 実機（Pixel 6a、API 36） | エミュレータ（API 35） |
|---|---|---|
| 基準のファイル | `scripts/test_android.baseline.Pixel_6a-36.json` | `scripts/test_android.baseline.sdk_gphone64_arm64-35.json` |
| 単体テスト（`android_library`、`unity_android_plugin`、`:app`） | 161 | 161 |
| サンプルの UI テスト（18 クラスと雛形 1 件） | 116 | 116 |
| ライブラリの instrumented テスト（`android_library` 20、`unity_android_plugin` 10） | 30 | 30 |
| `HostState`（N-02〜N-05、N-09、N-50） | 6 | 6 |
| `Host`（H-01〜H-04） | 4 | 4 |
| 合計（すべて成功） | 317 | 317 |
| fingerprint | `google/bluejay/bluejay:16/BP2A.250705.008/13578956:user/release-keys` | `google/sdk_gphone64_arm64/emu64a:15/AE3A.240806.036/12592187:user/release-keys` |

エミュレータで基準を取るまでに 3 回流した。1 回目は N-22、2 回目は S-03 が 1 件ずつ失敗し、どちらもテストの基盤の不安定さだったので直した（5 章）。3 回目で全件が通った。実機の基準はこの 2 つの直しの前に保存したが、直したのはテストの基盤だけで、実機での結果は変わらない（直した後の `NotificationInteractionUiTest` を両方の環境で 2 回ずつ流して 7/7、`ShareUiTest` を実機で 1 回・エミュレータで 3 回流して 17/17）。そのため、実機の基準は取り直していない。両方の基準のテストの集合は同じ。

## 3. スクリプトに足したもの（設計書 8 章）

| 項目 | 内容 |
|---|---|
| `--include-host` | H-01〜H-04 を 3.7 のとおり流す。各 H-xx の前後で `pm clear`（アプリを強制停止するので、Alarm と通知も消える）と権限の付け直しで片付ける |
| `--baseline` | 失敗が 0 件のときだけ、結果（テストごとの成否）と機種・API・fingerprint を `scripts/test_android.baseline.<機種>-<API>.json` に保存する。`--include-host` が要り、`--filter` と `--skip-unit` とは併用できない |
| 基準との比べ合わせ | 基準があれば、結果が変わったテスト・増えたテスト・無くなったテストを表示する |
| fingerprint | 基準と違えば警告を出す（基準を取り直す合図。README 7.2） |
| 端末の状態の確認 | 最後に通知の権限と正確なアラームの許可が戻っているかを確かめ、戻っていなければ終了コードを 1 にする |
| セキュアなロック | `--include-host` のとき、`dumpsys window` のキーガードの `secure=true` を見て、PIN などのロックがあれば止める（再起動の後、解除するまで `BOOT_COMPLETED` が届かないため） |

**Host の段の作り:**

| ID | 1 段目 | ホストの操作 | 2 段目 |
|---|---|---|---|
| H-01 | `HostPhaseTest#h01`（9101 保存する・9102 保存しない、120 秒後） | `adb install -r`（同じ APK） | 予約の時刻の 15 秒後から、9101 と 9102 が出るまで最長 240 秒待つ |
| H-02 | `HostPhaseTest#h02`（同じ） | `adb reboot`、`sys.boot_completed=1` を 180 秒まで待つ | 予約の時刻の 15 秒後から、9101 が出るまで最長 240 秒待ち、9102 が無いことを確かめる |
| H-03 | `HostPhaseTest#h03`（9103 保存する、15 秒後） | すぐに `adb reboot` | 起動の後、9103 が出るまで最長 240 秒待つ |
| H-04 | 無し | `am force-stop` の後、`am start -W -a SEND ... -n <サンプル>/.MainActivity` | `uiautomator dump` から `receivedShare.action` / `mimeType` / `text` の値だけを取り出す。ダンプは端末から消す |

通知は `dumpsys notification --noredact` の出力を流しながら、サンプルのパッケージの `NotificationRecord` の ID だけを取り出して判定する（出力は保存しない）。1 段目が予約した時刻は、テストが logcat に出した値（`HostPhaseTest` の `HOST_TRIGGER_AT=`）を読む。

## 4. 人の確認（設計書 7 章）

手順書は Claude のデスクトップアプリの computer use を前提にしているが、今回は `adb` で手順どおりに画面を操作し、`adb exec-out screencap` で撮った画面をサンプルの通知の行の範囲（`uiautomator dump` の `expandableNotificationRow` の範囲）だけに切り取り、Claude が画像を見て判定した。手順書の「手段」にこの方法を足した。

| ID | 実機（API 36） | エミュレータ（API 35） | 証拠 |
|---|---|---|---|
| CU-01 BigPicture | 合格。展開した画像がランチャーのアイコン（緑の格子の地に Android のロボット）、大きいアイコンが丸いランチャーのアイコン、タイトル `BigPicture Style`、要約 `Launcher image preview` | 合格。実機と同じ | `ComputerUse/evidence/CU-01/` |
| CU-02 カスタムビュー | 合格。DecoratedCustomView と DecoratedMediaCustomView の両方で、通知の中のアイコンが丸いランチャーのアイコン。`Expanded custom notification sample` と `Dismiss`、`Expanded media custom notification sample` が見えた | 合格。実機と同じ | `ComputerUse/evidence/CU-02/` |

Pixel のランチャーは `ic_launcher`（アダプティブアイコン）も丸く切り抜いて描くので、CU-01 の展開した画像が `ic_launcher` か `ic_launcher_round` かは、見た目では区別できない。確かめられるのは「ランチャーの画像であること」までである。

## 5. 見つけたことと直したこと

| 見つけたこと | 扱い |
|---|---|
| エミュレータでは、起動の完了（`sys.boot_completed=1`）から約 85 秒後にサンプルへ `BOOT_COMPLETED` が届く（ほかのアプリへの配信が順に続くため）。届いた後は、保存した予約がその場で表示された | 2 段目を「予約の時刻の後に 1 回見る」から「出るまで最長 240 秒待つ」に変えた |
| エミュレータでは、再起動の直後に SystemUI の「応答なし」のダイアログが前面に出て、H-04 の受け取りの画面を覆った | H-04 の前に、`mCurrentFocus` が「Not Responding」なら `CLOSE_SYSTEM_DIALOGS` と Back で閉じる |
| `HostPhaseTest` の `println` は `am instrument` の出力に出ず、logcat に出る | `Log.i` に変え、スクリプトが logcat から読む |
| エミュレータの最初の基準の実行で、N-22（通知のスワイプ）が 1 回だけ失敗した（スワイプの後も通知が残った） | `NotificationShade.swipeAway` を、消えるまで行を探し直して 3 回までスワイプする形にした |
| エミュレータの 2 回目の基準の実行で、S-03 が「Sharesheet が開かない」で失敗した。共有先を押した後、Sharesheet が閉じるのに 3 秒以上かかり、0c で足した押し直しに入って、もう閉じた Sharesheet が開くのを待っていた（押しは効いていた。押し直しの作りの誤り） | 押し直す前に Sharesheet がもう無ければ選べたとみなす。閉じるのを待つ時間を 5 秒にした |
| `am instrument` で予約だけをした後も、サンプルは停止状態（`stopped=true`）にならない | 調べた結果、原因ではなかった（再起動の後に通知が出なかったのは、上の配信の遅れのため） |
