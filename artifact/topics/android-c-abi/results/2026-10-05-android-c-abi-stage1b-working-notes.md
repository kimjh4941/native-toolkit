# 段階 1b の作業メモ（T-23 の実装結果の文書の材料）

実装の途中で書きためたメモ（英語のまま）。T-23 で実装結果の文書（`results/...-implementation-feature-result-v1.md`）にまとめた後は消してよい。

## 次の作業（2026-10-04 の終わり）

- 済み: T-01〜T-20、T-24（最後のコミットは `65dd0fa3`）
- T-21 は 2026-10-05 に実装した（下の「T-21」）。利用者の決定は設計書 0.8
- 次は T-22（ブリッジのテストの書き直し）、T-23（両方の環境での全体の実行、CU-03、実装結果の文書、UI テストの設計書への追記）

## 書きためたメモ


## Design deviations
- UiHostCore.kt split out of UiHost (testable core)
- Theme file named ntk_themes.xml
- AndroidNotificationSettingsGateway omits the data URI (NOTIFICATIONS settings intent with `package:` data matched no activity → OPENED_FALLBACK)
- LegacyScheduleCleaner triggered from LibraryRuntime (common → notification data dependency, as design says "LibraryRuntime が済みになったとき")
- ScheduleLock.kt also holds ScheduleIdentity and ScheduleTestHooks (test seams for IT-12/IT-13: send wall, write failure, Alarm failure)
- ScheduledAlarmExtras.kt holds the Alarm extras; NotificationSchedulerSupport keeps scheduleKey/scheduleIntent(id,tag)/idAndTagOf
- LegacyScheduleCleaner: an entry that is not readable JSON is skipped like an unparsable key (same on every try; not counted as a failure). Design only named "後ろが整数でなければ"
- LegacyScheduleCleaner split into LegacyScheduleDiscard (pure states, UT-05) + AndroidLegacyScheduleEnvironment
- ScheduleIdentity.isAlarmAlive pure function (unit-tested; boot count -1 on both sides cannot be produced on device)
- Receiver: on a decode failure, id/tag for the generation-matched removal come from the data URI (idAndTagOf)
- restoreScheduled past entries: re-check (same generation still saved) before send, removeIfGeneration after (design text: 項目ごとに読み直し)
- ScheduleLock.withLock not inline (logging rule: internal fun needs Log.d with TAG; inline cannot use private TAG)

## Design table corrected by test
- 8.6 toUri table: sourceBounds, identifier → 残る (IT-14, API 35/36)

## Defects found, not fixed in 1b (existing APIs, K-9)
- NotificationPermissionHelper / bridge open the notification settings with a `package:` data URI → falls back

## Accepted
- PermissionSessions: gate + session state both guard exactly-once (defense in depth)

## Tests not done in-process (to T-21 / host)
- IT-12: reinstall from backup (covered by installId mismatch in-process), OS-cleared Alarm after update (exact alarm revoke), Alarm due during update (3.4)
- IT-13: process kill right after schedule then reboot (H-02 host)
- IT-26: two APK versions with R8

## Test counts so far
- android_library unit: 144
- schedule ITs: ScheduleFlowTest 26, ScheduleIdentifiersTest 7, NotificationJsonCodecTest 11, ScheduleToUriTest 7, LegacyScheduleCleanerTest 6 = 57 (both envs)

## T-15
- NotificationUseCasesFactory (internal object, data) next to the public NotificationUseCases(context): foregroundServiceUseCases(context), putCommand/commandOf (in-process Parcelable payload). ForegroundServiceUseCases (internal, application) groups show/start/update/stop
- The two foreground services and ProgressForegroundServiceIntents no longer import data classes except the factory; only NotificationUseCases.isScheduled reads data directly (user decision)
- foregroundServiceUseCases also triggers LegacyScheduleCleaner (design: "NotificationUseCasesFactory が初めて UseCase を作るとき")

## Sample UI runs after T-12..T-14 (filter Notification 36, HostState 6): both envs passed, changed=0 added=0
- First Pixel run hung 16 min in `adb install` (environment; manual retry succeeded at once)

## T-16 / T-17 (Share)
- ShareCallbackCoordinator rewritten: one receiver per process registered on first request (IntentFilter action + data scheme/authority, NOT_EXPORTED), result data `ntk-share-result://<pkg>/<nonce>/<token>`, request code 0, UPDATE_CURRENT|MUTABLE; Callback/Event modes; user functions and events outside the lock. `currentToken()` added (internal) for tests
- The old per-request receiver registry (ShareCallbackReceiverRegistry) and the action `<pkg>.SHARE_CALLBACK` are gone; UT for the old internals replaced (5 → 12 tests)
- ShareResultIntents (data) holds the result action/scheme/filter/parse
- ShareChooserActionReceiver (presentation) holds nonce+generation; ShareRepositoryImpl (data) calls it — data → presentation, like the coordinator → ShareEvents (design file layout)
- Validation of actions also in ShareTextWithActionsUseCase (ids); the repository re-checks ids and decodes icons before bumping the generation
- IT-15 "process kill then reopen" simulated with a different nonce (sendBroadcast), not a real process kill
- Copy/Selected on API 35+ simulated with a ChooserResult built from its Parcel form (no public constructor)
- Tests: unit 159; ShareSelectionTest 13 on both envs; mutation checks all killed

## T-18 Clipboard
- ClipboardErrorCode (domain, no Log: domain stays free of android.util.Log, same as DialogError), ClipboardEvents, ClipboardObserver (object, main-only via MainPoster.checkMainThread)
- IT-17 compares with a platform listener: API 35/36 notify twice per copy
- UT-04 4 tests; IT-17 4 tests both envs; mutations killed

## T-24 Managers
- AndroidNotificationManager / AndroidShareManager / AndroidClipboardManager: internal constructors with use cases (+ settingsPort factory for notifications), getInstance keeps the Application Context only (lazy, double-checked)
- NotificationUseCasesFactory.settingsPort(context) added so the manager does not touch AndroidNotificationSettingsGateway directly
- canScheduleExactAlarms/openSettings build the use case per call (port depends on `from`)
- IT-27 ManagersTest 12 tests both envs (fakes for ports; leak check with WeakReference after closing the Activity); mutations killed

## T-19
- No code change: the components, meta-data and consumer rule were added in 16eda22b/aca14449. Release AAR checked: 7 permissions (FOREGROUND_SERVICE_PHONE_CALL only inside an XML comment), NtkHostActivity/NotificationEventReceiver/NotificationLaunchActivity exported=false, no intent-filter on the 3 explicit receivers, InitializationProvider meta-data LibraryInitializer, proguard.txt = LibraryInitializer keep only
- Sample release has isMinifyEnabled=false: IT-22 needs an R8 variant (T-21)

## Manager placement (user decision 2026-10-04)
- Managers moved to the feature package root (4ba60200); common.md/android.md rule; macOS Clipboard/Manager/ recorded as remaining exception

## T-21 (2026-10-05; design 0.8)
- Test-only app `android/AndroidLibraryExample/releaseProbe` (module `:releaseProbe`, depends on `android_library` only). Flavors: full / fullNext (versionCode 2, other R8 dictionary) / noPermissions (tools:node="remove" for the 7 permissions and the two foreground services). Release builds use R8 (proguard-android-optimize), signed with the debug key
- ProbeActivity checks itself per case (`--es case r8|permissions|scheduleForUpdate|verifyAfterUpdate`) and logs `RESULT <case> PASS|FAIL <detail>` (tag NtkProbe); the script reads logcat
- scripts/test_android.sh: step 6b (`--filter Probe` or no filter) builds the three APKs and records Probe#IT-22_r8, Probe#IT-26_update, Probe#IT-19_permissions, Probe#IT-19_manifest (aapt2 xmltree of both merged manifests: every permission and both services in full; none of the 7 permissions and no service without its FGS permission in noPermissions)
- IT-07: the library package run leaves out NotificationPermissionRequestTest (`--not-class` → `-e notClass`); step 5b (`--filter Library` or no filter) revokes POST_NOTIFICATIONS of `com.jonghyunkim.nativetoolkit.test` and runs the class (a1/a2 deny, b allows, c then granted). Dry run (`-e log true`) confirmed the exclusion (8 lines → 0)
- Runs: Library 4/4 and Probe 4/4 passed on Pixel 6a API 36 and the emulator API 35 (no assumption skips)
- Mutations (Pixel): noPermissions keeps ProgressForegroundService → IT-19_manifest fails; codec drops largeIconBitmap on read → IT-26 fails ("no large icon"); the probe app removes the LibraryInitializer meta-data → IT-22 fails ("the library is not initialized") and IT-19_permissions fails (NOT_INITIALIZED)
- Mutation survived, with the reason: removing the library's consumer rule (`-keep LibraryInitializer { <init>(); }`) does not break IT-22, because androidx.startup 1.1.1's own consumer rule keeps `* extends androidx.startup.Initializer { <init>(); }`. The library's rule is a duplicate; kept as design 8.12 asks (harmless, and safe if startup's rule changes)
- IT-26 deviations (design 0.8): the later version adds no JSON field (IT-25 covers it); one Bitmap (`largeIconBitmap`) only
- To T-23: document the new filters `Library` and `Probe` and steps 5b/6b in the UI test design (the script's "README" sections)
