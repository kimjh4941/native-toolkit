# 実装結果レポート（段階 1b: Kotlin API の補完）

## 基本情報

- 日付: 2026-10-05
- 機能名: android-c-abi 段階 1b（`android_library` の Kotlin API の補完）
- 対象OS: Android（Pixel 6a・API 36、エミュレーター・API 35）
- 設計書: `artifact/topics/android-c-abi/designs/2026-10-04-android-c-abi-kotlin-api-design.md`（v7 と 0.7・0.8 の利用者の決定）
- サンプルの設計と実装結果: `designs/2026-10-04-android-c-abi-sample-app-design-v3.md`、`results/2026-10-04-android-c-abi-implement-sample-app-result-v1.md`（T-20）
- ブランチ: `feature/NTKIT-17`
- コミット: `16eda22b`（T-01〜T-07）、`aca14449`（T-08〜T-11）、`03bc0b8d`（T-12〜T-15）、`4be9be97`（T-16、T-17）、`d3d48c4b`（T-18）、`7f3d8946`・`4ba60200`（T-24 と置き場所）、`81c8709a`・`65dd0fa3`（T-20）、`afef9d0c`（T-21）、`83a35154`（T-22）、`23294197`・`b17011c0`（T-23）

## 1. 実装サマリー

### 1.1 設計書由来の実装

| タスク | 中身 |
|---|---|
| T-01 | `LogRedaction` と、入力の全文を出していた既存のログ 2 か所（Dialog の入力欄、Share の本文） |
| T-02〜T-05 | `LibraryRuntime`・`LibraryInitializer`（Startup）、`MainPoster`・`LibraryExecutors`・`RequestIds`・`ProcessNonce`、`ForegroundActivityTracker`、`EventHub`、透明な宿主（`UiHost`・`UiRequestGate`・`NtkHostActivity`） |
| T-06・T-07 | Dialog の domain・application・presentation（`FragmentDialogPresenter`、`AndroidDialogFragment` の要求の ID） |
| T-08・T-09 | 通知の権限の要求（port、UseCase、`FragmentPermissionRequester`）、設定の画面の port・UseCase・gateway |
| T-10・T-11 | 通知のイベント（`NotificationEventIntents`、受け手、見えない起動の Activity、`NotificationEvents`）、リソース名の解決 |
| T-12〜T-15 | 予約の保存（JSON、`AtomicFile`、版の規則、`lossy`・`installId`・`bootCount`）、Alarm の extra と宛先、`ScheduleLock`、受け手、Boot、1.x の破棄、依存の向きの修正と shown のイベント |
| T-16・T-17 | Share の要求ごとの PendingIntent と印、選択のイベント、型のある Chooser Action と受け手 |
| T-18 | Clipboard のエラーの分類（7 つ）とプロセスで 1 つの監視 |
| T-19 | manifest と `consumer-rules.pro`（コードの変更は T-02・T-10 で済み） |
| T-24 | 4 つの Manager（`<機能>/Android*Manager.kt`。委ねるだけの入口、`getInstance`、テスト用の constructor）と IT-27 |
| T-20 | サンプルを 4 つの Manager とライブラリのイベントへ移した（サンプルの設計 v3） |
| T-21 | 試験専用のアプリ `releaseProbe`（R8・権限を外した版・前後の版）と `test_android.sh` の段 5b・6b |
| T-22 | ブリッジのテストの書き直し（2.3） |
| T-23 | 全体の実行、CU-03、DoD の照合と、見つかった不足の補い（1.2 の後半） |

### 1.2 実装時の追加判断

**利用者の決定（設計書 0.7・0.8 に記録）**

- Manager は機能のパッケージの直下に置く（0.7）
- IT-19・IT-22・IT-26 は、サンプルに flavor を足さず、試験専用のアプリで行い、残して毎回流す（0.8）
- T-23 の照合で、IT-21・IT-23 にテストが無い（タスク表のどの行にも割り当てていなかった）と分かった。IT-21・IT-23 と、利用者から見える動作の欠け（A）を T-23 で書き、検証の穴（B）と記述（C）は安いものだけ埋める（0.8）

**設計から変えたもの（理由つき）**

| 項目 | 理由 |
|---|---|
| `UiHostCore.kt` を `UiHost` から分けた | 宿主の状態の表を単体テスト（UT-03）で確かめるため |
| テーマのファイル名を `ntk_themes.xml` にした | 利用者のアプリの `themes.xml` と名前がぶつからないようにするため |
| `AndroidNotificationSettingsGateway` は通知の設定の Intent に `package:` の data を付けない | 付けると開く Activity が無く、必ず代わりの画面（`OPENED_FALLBACK`）になった |
| 1.x の破棄（`LegacyScheduleCleaner.runOnceInBackground`）は、`LibraryRuntime` が済みになったとき、`NotificationUseCasesFactory` が UseCase を作るたび、Boot の受け手が動くたびに呼び、済んでいれば何もしない | 設計の「済みになったとき」「初めて UseCase を作るとき」を、呼ぶたびに済みかを見る形で書いた。common から notification の data への依存が 1 つ増える |
| data から presentation のイベントの持ち主と受け手への依存が 3 か所（`ShareRepositoryImpl` → `ShareChooserActionReceiver`、`ShareCallbackCoordinator` → `ShareEvents`、`ScheduledNotificationReceiver` → `NotificationEvents`） | 6.1 の置き場所から出る。設計 4.1 に例外として書いた（レビューで記録） |
| `kotlinx-coroutines-core` を `android_library` の依存に足した | `suspend` 版の口（8.7・8.8）のため。6.1 の「ほかに」の表には無かった |
| 宿主が閉じてよいかは、取り除かれている途中の Fragment（`isRemoving`）を数えない | 8.3 は「`ntk.` の Fragment が 1 つも無ければ」とだけ書く。取り消した Fragment の後始末の最中に閉じ損ねないための詳細化 |
| `MainPoster.isMainThread()` が RG の公開のメンバー | 付録 A に無い。C ABI の受け口が main の判定に使う想定 |
| domain の型（`ClipboardErrorCode`、`DialogError`）の関数は先頭の `Log.d` を持たない | domain は `android.util.Log` を使わない（common.md「Domain はプラットフォーム依存なし」）。android.md のログの規則より層の規則を優先した |
| 1.x の破棄で、JSON として読めない項目は、解析できない鍵と同じく飛ばす（失敗に数えない） | 設計は「後ろが整数でなければ」だけを挙げていた。毎回同じ結果になるので、やり直しても変わらない |
| `ScheduleLock.kt` に `ScheduleIdentity` と `ScheduleTestHooks`（IT-12・IT-13 の注入の口）を置いた。`InstallId` という型は作らず `ScheduleIdentity.installId()` にした | 識別の値と試験の口を、ロックと同じ場所で持つため |
| 受け手が extra を読めないとき、同じ世代の削除に使う id と tag は data の URI から取る | extra が読めなくても、保存の項目を消せるようにするため |
| 期限の過ぎた項目の置き直しは、送る前に「同じ世代がまだ保存にあるか」を読み直し、送った後は同じ世代のときだけ消す | 設計の「項目ごとに読み直し」を、送る処理の前後に分けて書いた |
| `ScheduleLock.withLock` を inline にしない | ログの規則（internal の関数は先頭に `Log.d`）で private の TAG を使うため |
| ファイルのまとめ方が 6.1 の表と違った（`RuntimeSupport.kt`、`UiReasons.kt`、`DialogRequest.kt` など 15 か所） | 中身・名前・可視性は付録 A と同じ。T-23 で 6.1 の表を実装に合わせた |
| `IT-14` の `toUri` の表のうち `sourceBounds`・`identifier` は「残る」が正しかった | API 35・36 で確かめ、設計書の表を直した |
| IT-26 は「後の版で JSON に欄を足す」を行わず、R8 の名前の付け方を変えた。`Bitmap` は 1 つ | 0.8 |

**T-23 で直したもの（DoD の照合で見つかった）**

| 見つかったこと | 直し |
|---|---|
| `EventHub.Registration.remove()` に main の検査が無い（設計 6.2 は main 以外で `IllegalStateException`） | 何も変える前に検査する。単体テストを 1 件足した |
| 8.13 の `@Deprecated` が `ShareTextUseCase` の JSON の形に無い | 2 つの `invoke` に付けた（`ShareUseCases.shareText` もこれを通る）。`AndroidShareManager.shareText` は IT-27 のとおりこれに委ねるので、警告を抑えた |
| `NotificationEventIntents` の 4 つの定数が public で、付録 A に無い | internal にした（使うのはライブラリ自身のテストだけ） |
| （実装レビュー A）`addOnInitializedListener` の利用者の関数を、例外を捕まえずに main に積んでいた（設計 6.2 は捕まえてログを出し、続ける） | `InitializationState` が積むときに包む。単体テストを 1 件足した |
| （実装レビュー B）Alarm の extra の command の JSON の版（`v`）を読むときに確かめていなかった（8.6） | 整数の今の版でなければ読まない（受け手は表示しない。欄が無ければ版 1）。codec のテストを 1 件足した |
| （実装レビュー C）新しいコードの TAG がクラスの完全名でない 5 か所、先頭の `Log.d` が無い小さな関数 12 個、`AndroidDialogFragment` の KDoc の位置のずれ | 直した。`LogRedaction.redact` のログは長さだけを出す |

## 2. 変更ファイル

### 2.1 新規作成

- `android_library` の本体: `common/`（runtime、event、logging、presentation の宿主と前面の追跡、domain の理由）、`dialog/`（`AndroidDialogManager`、domain・application・presentation）、`notification/`（`AndroidNotificationManager`、権限・設定・イベント・リソース・予約の保存と識別・1.x の破棄・ファクトリー）、`share/`（`AndroidShareManager`、選択の待ち・Chooser Action の受け手・結果の Intent）、`clipboard/`（`AndroidClipboardManager`、`ClipboardErrorCode`、`ClipboardObserver`、`ClipboardEvents`）、`res/values/ntk_themes.xml`、`consumer-rules.pro`
- `android_library` のテスト: 単体（`EventHubTest`、`InitializationStateTest`、`UiHostCoreTest`、`LogRedactionTest`、`PermissionSessionsTest`、`LegacyScheduleDiscardTest`、`ScheduleIdentityTest`、`ShareSelectionUseCasesTest`、`ShareCallbackCoordinatorTest` の書き直し、`ClipboardErrorCodeTest` ほか）、instrumented（4.2 の表）
- `android/AndroidLibraryExample/releaseProbe/`（試験専用のアプリ。flavor は `full`・`fullNext`・`noPermissions`・`noStartup`）
- サンプル: `SampleEvents.kt`、`DialogSampleScreen.kt` と、UI テスト `NotificationEventDeliveryUiTest`・`ScreenResultSinkInstrumentedTest`

### 2.2 既存変更

- `android_library`: `AndroidDialogFragment`（要求の ID、ログ）、`ShareRepositoryImpl`・`ShareUseCases`・`ShareTextUseCase`、通知の repository と前景サービス、`AndroidManifest.xml`、`build.gradle.kts`（Startup、coroutines、consumer rule）
- サンプル: `MainActivity`、`MainRouter`、各画面、manifest（受け手を消した）、UI テストと基盤
- `scripts/test_android.sh`（段 5b・6b、`--filter Library`・`Probe`）、`scripts/android_instrument.py`（`--not-class`）、`android/settings.gradle.kts`
- `agent-rules/coding-rules/android.md`・`common.md`（ログの例外、Manager の役と置き場所）
- 設計書（0.7・0.8、6.1 のファイルの表、8.3 の表、IT-14 の表、IT の行）、UI テストの設計書（1b の改訂）

### 2.3 非変更（設計上対象だが未変更）

- `unity_android_plugin`（ブリッジ）: 設計 2 章のとおり手を入れない（段階 3 で消す）。T-22 でテストの対応を取った（下）

**T-22 ブリッジのテストの対応（85 件。Example の 2 件を除く）**

| 区分 | 件数 | 中身 |
|---|---|---|
| ブリッジに残る（書き直さない） | 63 | JSON の解析、操作の名前、エラーの文言、Progress の前景サービスの値の補正、ブリッジの欄（設計 2.2 の対象外。`hasClip` を偽にするのは C ABI 側） |
| ライブラリへ移した | 13 | Clipboard のエラーの分類、Chooser Action の登録・置き換え・受け手・複数のアクション・起動の失敗など。対応するライブラリのテストを確かめ、無かった 4 つを `ShareSelectionTest` に足した |
| 移したが契約が違う | 9 | 空・重複の id は黙って除かず `InvalidChooserAction` を投げる（8.9）、SEND の id を除かない（id は data の URI にある）、受け手の例外は捕まえる（6.2）、Share ごとに外す口は無く世代で捨てる（8.9） |

- 試していないもの: API 33 以下でアクションを付けないこと（試験の端末が API 35・36 だけ）
- リソース名の解決は、ブリッジにテストが無い（private な実装）。ライブラリの `NotificationResourceResolverTest`（4 件）がある

## 3. エラー契約反映

### 3.1 ドメインエラー実装反映

- Dialog: `DialogDomainError.Canceled(reason)`・`Unavailable(error)`（`suspend` 版）、callback 版は `DialogResult.Canceled`・`Failed`。`DialogError` は `NOT_FOREGROUND`・`SHOW_FAILED`・`HOST_START_FAILED`・`NOT_INITIALIZED` ほか（付録 A のとおり）
- 権限の要求: `PermissionRequestResult`（`Granted`・`Denied`・`Failed(reason)`）と `suspend` 版の例外
- Share: 既存の 9 つに `InvalidChooserAction(id)` を足した（検査で投げたときは世代を上げない）
- Clipboard: 例外の型は変えず、`ClipboardErrorCode.of` が 7 つのコードに分ける（ブリッジの表と同じ。`Error` も `UNKNOWN` にする点だけブリッジと違う）

### 3.2 errorCode / errorMessage 対応反映

- C ABI のエラーの値への写しは段階 2（C ABI の設計書 第 2 部）で行う。1b で値を持つのは `ClipboardErrorCode` だけで、`ClipboardErrorCodeTest` が 7 つの対応を確かめた

### 3.3 success時契約

- `isSuccess` / `errorCode` / `errorMessage` は C ABI の契約で、1b の Kotlin API には無い（-）

## 4. ビルド結果

- 実行コマンド:
  - `android/` で `./gradlew :android_library:testDebugUnitTest :android_library:assembleDebugAndroidTest :app:assembleDebug :releaseProbe:assembleFullRelease ...`（`scripts/test_android.sh` の中）
  - `./scripts/build_android_library_aar.sh -b release -m android_library -v 2.0.0 -o <スクラッチ>/android_library-verify.aar`
- 結果: SUCCESS（`[done] Created .../android_library-verify.aar`）
- 補足:
  - AAR の生成スクリプトは `android/gradle.properties` の `libraryVersion` を書き換える。確かめの版（2.0.0）が書かれたので 1.3.0 に戻した（版を決めるのはリリースの作業）
  - リリースの AAR の manifest: 権限 7 つ、`NtkHostActivity`・受け手・起動の Activity は `exported=false`、明示の受け手 3 つに intent-filter が無い、Startup の meta-data。`proguard.txt` は `LibraryInitializer` の keep だけ

## 5. テスト結果

- 実行したテスト:
  - `scripts/test_android.sh --serial <端末> --include-host`（単体、UI、ライブラリの instrumented、HostState、段 5b、ホストの H-01〜H-04、段 6b、基準との比べ）を両方の環境で
  - 機能ごとの段階では、関係するテストのクラスだけを両方の環境で流した
- 結果サマリー（最後の全体の実行、2026-10-05。`--include-host`、`b17011c0` の後のコード）:
  - 実行件数: 564（Pixel 6a・API 36）、564（エミュレーター・API 35）
  - 成功: 564、564
  - 失敗: 0、0
- 0d の基準との比べ: 両方の環境で、結果が変わったテスト 0、増えたテスト 251、無くなったテスト 4。無くなった 4 件は、T-16 で書き直した `ShareCallbackCoordinatorTest` の古い単体テスト（新しい 12 件に置き換えた）
- 失敗時の対応: 1.2 の後半（T-23 で直したもの）と 7 章
- 未実施項目: 5.2

### 5.1 テスト詳細

12 章の行ごとの対応（L = `android_library`、S = サンプルの UI テスト、P = 試験専用のアプリ）。結果はどれも両方の環境で成功。

| 行 | テスト | 確かめ | 備考 |
|---|---|---|---|
| UT-01 | L `InitializationStateTest` | △ | 実際の `LibraryRuntime` で途中の例外の後に登録を戻すこと、本当に同時の `tryBegin` は試していない |
| UT-02 | L `EventHubTest` | ○ | `remove` の main の検査を T-23 で足した |
| UT-03 | L `UiHostCoreTest` | △ | Dialog の状態の表の全セル、「宿主の破棄と結果」の両順、起動待ちの取り消しと宿主の到着の片方の順、見張りや起動の失敗で非 active の利用者を飛ばすことは試していない |
| UT-04 | L `ClipboardErrorCodeTest` | ○ | |
| UT-05 | L `LegacyScheduleDiscardTest` | ○ | |
| UT-06 | L `PermissionSessionsTest` | △ | API 32 以下の分岐（SDK の判定の差し替え）、宿主待ちと Fragment を足した後の (1)(2) の判定のセルは試していない |
| UT-07 | L `LogRedactionTest` | ○ | 新しい型の `toString` を T-23 で足した |
| UT-08 | L `ShareCallbackCoordinatorTest` | ○ | 「利用者の関数はロックの外で呼ぶ」は、レビューの指摘で、コールバックの中から別のスレッドで `register` を呼ぶ形に直した（ロックは同じスレッドで入り直せるので、前の形では確かめになっていなかった） |
| IT-01 | P `withoutStartup`、L の各テストの前提 | ○ | Startup を外した版で、手動の初期化の後に前面が取れる（T-23） |
| IT-02 | L `ForegroundActivityTrackerTest`、P `withoutStartup`（`seed`） | ○ | T-23 |
| IT-03 | L `AndroidDialogManagerTest`、`ExistingDialogApiTest`、S `DialogUiTest`、P `dialogBeforeKill`・`afterKill` | ○ | `suspend` 版（答え・取り消し・前面が無いときの例外・宿主の破棄での `Canceled`）とプロセスの死の後を T-23 で足した。`suspend` 版で試した種類は Confirm と Alert |
| IT-04 | L `AndroidDialogManagerTest` | △ | 表示の失敗で宿主が閉じることは試していない |
| IT-05 | L `AndroidDialogManagerTest` | △ | 誤った `seed` の後に見張りで `NOT_FOREGROUND` になることは試していない（見張りの論理は UT-03） |
| IT-06 | L `AndroidDialogManagerTest` | ○ | |
| IT-07 | L `NotificationPermissionRequestTest`（段 5b）、`ManagersTest`（`suspend` 版の例外。偽物の port）、S `NotificationHostStateUiTest` n03〜n12、P `permissionBeforeKill`・`afterKill` | △ | プロセスの死の後は、戻した後に権限のダイアログが出ていれば BACK で閉じてから、戻った Fragment が残らないこととダイアログが出直さないことを見る。戻った Fragment が `launch` しないことを直接には確かめていない |
| IT-08 | L `NotificationSettingsGatewayTest`、`ManagersTest` | △ | 代わりの画面（`OPENED_FALLBACK`）は偽物の値だけ |
| IT-09 | L `NotificationEventsTest`、S `NotificationStyleUiTest` n16 | ○ | |
| IT-10 | L `NotificationEventsTest`、S `NotificationEventDeliveryUiTest`、P `coldEvents` | ○ | コールドスタートを T-23 で足した |
| IT-11 | L `NotificationEventsTest`、S `NotificationTapUiTest` n28・n29、P `r8`・`coldLaunch` | △ | 「Receiver から起動する形は後ろのとき開かない」の比べは行っていない（OS の動作でライブラリのコードではない） |
| IT-12 | L `ScheduleFlowTest` | △ | OS が Alarm を消した後の更新、更新の途中に期限が来た Alarm は行っていない。バックアップからの戻しは `installId` の違いで代えた。`MY_PACKAGE_REPLACED` の置き直しは `restoreScheduled()` を直接呼び、受け手の経路は通らない（受け手の経路は IT-26 と CU-03） |
| IT-13 | L `ScheduleFlowTest`、ホストの H-02 | ○ | プロセスの停止と再起動は H-02 |
| IT-14 | L `ScheduleToUriTest` | ○ | 再起動は `bootCount` を変えて擬似 |
| IT-15 | L `ShareSelectionTest`、S `ShareUiTest` | ○ | プロセスの停止は別の nonce で擬似 |
| IT-16 | L `ShareSelectionTest` | ○ | |
| IT-17 | L `ClipboardObserverTest` | ○ | |
| IT-18 | L `LegacyScheduleCleanerTest`、CU-03 | ○ | |
| IT-19 | P `noPermissions`、段 6b の manifest の検査 | △ | 実行で見るのは、権限の問い合わせが偽になることと、権限の要求が `Denied` になることだけ。正確でない Alarm で予約が動くこと、全画面が heads-up になること、`RECEIVE_BOOT_COMPLETED` を外したときに再起動の後に戻らないこと、通知が出ないことは見ていない |
| IT-20 | L `ShareSelectionTest`、`NotificationPendingIntentIdentityTest`、P `postColdTap`（全画面の起動） | ○ | 通知の側を T-23 で足した |
| IT-21 | L `LogSentinelTest` | ○ | T-23。レビューの指摘で、Clipboard は読み戻した本文を比べ、予約の経路（`data` が Alarm の JSON と保存に入る）も通すようにした |
| IT-22 | P `r8` | ○ | |
| IT-23 | L `ExistingDialogApiTest`、`ExistingPermissionHelperTest`（段 5b）、`ExistingShareApiTest`、`ExistingNotificationApiTest`、`ShareSelectionTest`（`shareWithCallback`）、`ScheduleFlowTest`、P `withoutStartup` | ○ | T-23 |
| IT-24 | L `ScheduleIdentifiersTest` | ○ | |
| IT-25 | L `NotificationJsonCodecTest` | △ | カスタムビューの動作は数を比べていない（復号で欠けても落ちない）。レビューの指摘で、版の違う command を読まないことを足した |
| IT-26 | P `scheduleForUpdate`・`verifyAfterUpdate` | △ | 0.8 の形。`Bitmap` は欠けていないことだけを見て、中身は比べていない |
| IT-27 | L `ManagersTest` | △ | Dialog と Progress の委ね先との比べは無い（Dialog は L `AndroidDialogManagerTest` が Manager を通して試している）。スレッドの比べは無く、失敗の比べは show と schedule だけ |
| CU-03 | adb と UiAutomator の画面の読み取りで両方の環境 | ○ | 5.3 |

**壊して落ちるかの確かめ（変異）**: 足した検査ごとに、契約は保ったまま形を変える変異を入れて流した。T-21〜T-23 の変異 31 個（T-21 で 4、T-22 で 5、T-23 で 22）と、レビューの後の直しの変異 7 個のうち、最後まで落ちなかったのは次の 3 つで、どれもふつうの流れでは区別できないか、別の規則が同じものを守っている。途中で落ちなかった 3 つ（IT-21 のテキスト入力の欄、IT-20 の `FLAG_UPDATE_CURRENT`、全画面の起動の identifier）は、テストの側の穴だったので直して落ちることを確かめた。

| 変異 | 落ちなかった理由 |
|---|---|
| ライブラリの consumer rule（`LibraryInitializer` の keep）を外す | androidx.startup（1.2.0）自身の consumer rule が `Initializer` の子クラスの constructor を残す。ライブラリの規則は重ねがけで、8.12 のとおり残す |
| `ForegroundActivityTracker` の「止まった」の条件を外す | 止まった Activity は同じ流れで状態の保存の印も付き、終わる Activity は `isFinishing` で外れる |
| 宿主が閉じてよいかを最初の Fragment だけで決める | 判定は main に積んで後で行うので、取り消した Fragment はもう一覧に無い。代わりに「毎回閉じる」変異で IT-04 のテストが落ちることを確かめた |

### 5.2 未実施ケース詳細

| テスト観点 | テストファイル | テストケース | 未実施理由 |
|---|---|---|---|
| API 33 以下で Chooser Action を付けない | - | ブリッジの `register_validActionIds` の下の分岐 | 試験の端末が API 35・36 だけ（3.4） |
| 5.1 の表の △ の部分 | - | UT-01・UT-03・UT-06、IT-04・IT-05・IT-08・IT-11・IT-12・IT-19・IT-27 の欠け | 利用者の決定（0.8）で、検証の穴（B）と記述（C）は安いものだけ埋めた。ここは残す |
| ホストのケース以外の再起動 | - | IT-14 の「再起動の後」 | `bootCount` を変えて擬似にした |

### 5.3 CU-03（1.12.0 からの更新）

- 行った人と方法: Claude が adb と UiAutomator の画面の読み取りで、両方の環境で行った（2026-10-05）
- 準備:
  - 1.12.0 のタグの Gradle のルートは `android/AndroidLibraryExample` で、その `settings.gradle.kts` はライブラリを絶対パス（今のツリーの `android_library`）で指していた。1.12.0 の作業ツリーを作り、そのツリーのライブラリを指すように直した
  - 1.12.0 のサンプルにある予約は 15 秒後の 1 つだけで、保存する形しか作れない（`persistAcrossBoot` の既定が真）。作業ツリーのサンプルの画面だけを変え、予約を 120 秒後にし、同じボタンで保存しない予約（id 1011）も置くようにした。ライブラリは 1.12.0 のまま
- 手順: 1.12.0 を元にしたサンプル（同じ applicationId、debug の鍵）を入れて予約する（1010 は保存する、1011 は保存しない）→ 今のサンプルを `adb install -r` で入れる → 発火の時刻を過ぎるまで待つ → 今のサンプルで予約し直す
- 結果（両方の環境で同じ）:
  - 更新の前: Alarm 2 つ、1.x の保存（`android.library.notification.scheduler.xml`）
  - 更新の後: Alarm 1 つ（1010 を取り消した）、`shared_prefs` が空、破棄済みの印 `no_backup/ntk/legacy_v1_discarded`。`LegacyScheduleCleaner` のログに `cancelAlarm 1010`、`deletePreferences`、`mark`
  - 発火の時刻の後: Alarm 0、通知 0（1.x の Alarm の宛先は 1.x の受け手のクラスで、2.0.0 には無い）
  - 今のサンプルで予約し直すと、15 秒後に 1010 が出て、新しい保存 `files/ntk/notification_schedules.json` が書かれた

## 6. Definition of Done

- 判定基準:
  - ○: 今回の実装・コード・テスト確認の範囲では OK かつ設計書とズレていない
  - △: 一部 OK だが、追加確認が必要
  - ×: 未達、または設計書との差分が未解消
  - -: 対象外
- △ 6.1 のファイルと可視性、付録 A の宣言があり、8 章の動き、9 章のスレッド、取り消しの契約と一致している — 付録 A の宣言は名前・引数・戻り値・可視性まですべて実装にある（付録 A に無い公開のメンバーは `MainPoster.isMainThread()`（RG）だけで、1.2 に書いた）。9 章のスレッドと取り消しは主な 13 の文を照合して一致（`remove` の検査を直した）。6.1 のファイルのまとめ方の違い（15 か所）と 8.3 に無かった動きは、設計書を実装に合わせて直した（7 章）。△ は 8.3 の直しがまだレビューを通っていないため
- ○ `PLANNED_SYMBOLS_EXEMPT` の名前を実装と照合した — 265 の名前のうち、プロジェクトの名前で実装に無いのは `InstallId` だけ（`ScheduleIdentity.installId()`）
- ○ 5.1 のロジックがすべて `android_library` にあるか、7 章で C ABI / 包みの受け持ちと決めている
- ○ `android.md` に 2 つの書き足しがあり、IT-21 が通る
- △ 12 章のテストが両方の環境で通り、`test_android.sh` の全件が 0d の基準と同じ。IT-23 で既存の口の動作が変わっていない — 最後の全体の実行は両方の環境で 564 件すべて成功し、基準との比べで結果の変わったテスト 0。12 章の行は 5.1 の表の △ の部分が残る（利用者の決定 0.8）
- ○ IT-18 と CU-03 が通る
- ○ AAR の manifest に 8.12 のコンポーネントがあり、`consumer-rules.pro` が 8.12 のとおりで、IT-22、IT-24、IT-26 が通る
- ○ C ABI の設計書 9.1 の K-1〜K-9 を 11 章の表で確かめている — 表は 9 行そろっている。K-5（前面）・K-8（手動の初期化）・K-9（既存の口）は T-23 で IT-01・IT-02・IT-23 を足して裏付けた

## 7. 設計差分

- 差分有無: あり
- 差分内容:
  - 1.2 の「設計から変えたもの」の表
  - 6.1 のファイルの表と実装のまとめ方の違い（15 か所）。6.1 は `ShareRepositoryImpl` を internal と書いていたが、実装は 1.12.0 と同じ public（設計書の書き誤り。K-9 には実装が合っている）。T-23 で表を直した
  - 8.3 の表に無かった動き: 前面の `FragmentActivity` が状態を保存した後なら、宿主を起動せず `NOT_FOREGROUND` を返す。`showNow` と `commitNow` の `IllegalStateException` は理由を問わず状態の保存とみなす。権限の会は `commitNow` が投げた後に `finishIfIdle` を積まない（宿主の `onCreate` の最後で呼ばれるので害は無い）。T-23 で 8.3 に書き足した
- 影響範囲: 利用者から見える動作は変わらない（どれも設計書の記述の側の差で、設計書を実装に合わせた）

**レビューで記録したもの（直さない。設計書 0.8）**

- 型のある Chooser Action の受け手で、世代の照合と `emit` の間に新しい Share が世代を上げると、古いアクションが 1 度だけ届きうる（Codex。照合の時点を区切りとみなす）
- 公開の sealed class `ShareDomainError` に `InvalidChooserAction` を足したので、利用者の網羅的な `when` はコンパイルが通らなくなる（ソースの互換）
- `ShareTextUseCase` の `@Deprecated` は、JSON を渡さない `ShareUseCases.shareText(content)` にも警告を出す

**段階 2 への申し送り**

- 型のある Chooser Action の世代を上げるのは `shareTextWithActions` だけで、アクションの無い `shareText` の後も前のアクションは生きている。ブリッジは Share のたびに登録し直していた。C ABI でブリッジの動作を写すなら、アクションの無い Share も `shareTextWithActions(content, emptyList())` に写す（設計 6.3・8.9 には書かれていない）
- Chooser Action の id の検査は「空」だけで、空白だけの id は受け付ける（ブリッジは空白も除いていた）
- 既存の口の不具合（K-9 で直さない）: `NotificationPermissionHelper` とブリッジは、通知の設定の画面を `package:` の data 付きで開くので、代わりの画面になる
- サンプルの UI テストで残したもの: サンプルの実装結果 4 章（I-X1、I-X4、I-X5、I-X6）。Manager に無い口（rationale、CallStyle）はサンプルの設計 10 章

**スクリプトと試験の道具で分かったこと**

- `--filter` は `${class}.kt` を grep して絞るので、ほかのクラスのファイルにある `ReceivedShareLaunchUiTest` と `ReceivedShareTagInventoryTest` は `--filter ReceivedShare` では流れない（段階 0d からの動き。直していない）
- 試験専用のアプリでプロセスの死の後を確かめる形: `singleTask` の Activity をランチャーの Intent で前に戻すと上の Activity が消えるので、`FragmentActivity` を別のタスクで開き、そのタスクを直接戻す。通知は 2 つあると OS がまとめ、まとめの側を押すとアプリが開くだけなので、1 つずつ出す
- 私の作業の誤り: 変異の実行で `android_library/src/main` を戻す操作が、エミュレーターの全体の実行のビルドと重なり、その段 6b がビルドで止まった（テストの失敗ではない）。段 6b は後で流し直して通った。同じツリーでビルドしている間は変異を入れない

## 8. ステップ10 実行確認

- 提示文:
  - 「この実装結果を採用して、次工程へ進めますか？」
- 選択肢:
  - 実行する: この実装結果を採用して次工程へ進む
  - 修正する: 指摘内容を反映して再実装
  - キャンセル: ここまでの修正差分は保持したまま、終了
- ユーザー回答:
  - 実行する（2026-10-05）
