# 段階 1b の作業メモ（T-23 の実装結果の文書の材料）

実装の途中で書きためたメモ（英語のまま）。T-23 で実装結果の文書（`results/...-implementation-feature-result-v1.md`）にまとめた後は消してよい。

## 次の作業（2026-10-04 の終わり）

- 済み: T-01〜T-20、T-24（最後のコミットは `65dd0fa3`）
- T-21・T-22 は 2026-10-05 に実装した（下の「T-21」「T-22」）。T-21 の利用者の決定は設計書 0.8
- 次は T-23（両方の環境での全体の実行、CU-03、実装結果の文書、UI テストの設計書への追記）

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

## T-22 bridge tests → android_library tests (2026-10-05)
Mapping made by a subagent from the test bodies and the bridge code; spot-checked against design 8.9 and the code. 85 bridge tests (Example tests excluded): B (stays in the bridge, not rewritten) 63, M (moved logic) 13, D (moved, contract differs by design) 9.
- B: all of UnityClipboardJsonParserTest (12), UnityNotificationJsonParserTest (4), UnityShareJsonParserTest (21), UnityAndroidNotificationManagerTest (5: JSON checks, message texts, Progress FGS value checks), UnityAndroidShareManagerTest 10 (JSON checks, message texts, the bridge's pendingCallbackContext field, listener-less calls), UnityAndroidClipboardManagerTest 4 + the JSON/message part of 2 (design 2.2 out: JSON parsing, op names, message texts, value corrections; 7 C4: false for hasClip is the C ABI side)
- M/D with library tests:
  - Clipboard error classification (read/getDescription unavailable → CLIPBOARD_UNAVAILABLE): ClipboardErrorCodeTest (4; all 7 codes), ManagersTest#clipboard_operationsDelegate_withTheSameResultsAndExceptions
  - normalizeActionIds blank/duplicate (D, 8.9: throws InvalidChooserAction instead of dropping, and keeps the earlier actions): ShareSelectionUseCasesTest#shareTextWithActions_emptyOrDuplicateId_throwsInvalidChooserAction_withoutOpening, ShareSelectionTest#aRejectedShare_keepsThePreviousActionsWorking, ManagersTest#share_validationExceptionsAreTheUseCases
  - normalizeActionIds SEND excluded (D, 8.9: the id is in the data URI, not the Intent action): ShareSelectionTest#anIdThatLooksLikeTheSendAction_isAnOrdinaryId (new)
  - empty list allowed: ShareSelectionUseCasesTest#shareTextWithActions_delegates_emptyActionsAllowed
  - receiver forwards / dispatch to listener / manager end to end: ShareSelectionTest#aTypedActionArrivesWithItsId, ManagersTest#share_operationsDelegate_andShareTextIsTheUseCaseWithEmptyActions
  - receiver null action (D: data URI): ShareSelectionTest#malformedActionIntents_andActionsOfAnEarlierProcess_areDropped (new); null Intent: not expressible (non-null parameter)
  - listener throws (D, 6.2: the library catches): EventHubTest#throwingListener_doesNotStopTheOthers
  - listener not set → dropped: EventHubTest#nonRetainingHub_dropsEventsWithoutListeners, ShareSelectionTest#anActionWithoutAListener_isNotKeptForALaterListener (new)
  - multiple actions each delivered: ShareSelectionTest#aTypedActionArrivesWithItsId (now sends both)
  - consecutive / empty share replaces the registration: ShareSelectionTest#actionsOfAnEarlierShare_doNotArrive_evenAfterAShareWithoutActions
  - launch failure unregisters: ShareSelectionTest#aLaunchFailure_throws_andTheActionsOfTheEarlierShareStopWorking (new)
  - unregister by token / stale token / clear listener (D, 8.9: no per-share removal; generations drop old actions): EventHubTest#removedListenerIsNotCalledEvenWithinTheSameEmit, #removeTwice_doesNothing, ShareSelectionTest#aRejectedShare_keepsThePreviousActionsWorking
  - API 33 and lower register nothing (register_validActionIds lower branch): not run — the test devices are API 35/36 (3.4); the code adds the extra only for API 34+ and actions.isNotEmpty()
- Resource resolution: the bridge has no test (private ContextResourceResolver); NotificationResourceResolverTest (4). Not tested: finding a drawable/mipmap when no type is given (only the negative form)
- Tests: ShareSelectionTest 13 → 17 on both envs
- Mutations (Pixel), each killed by its own new test only: no nonce check (malformed…), the generation rolled back on a launch failure (aLaunchFailure…), every PendingIntent with the last id (aTypedAction…), chooserActions kept until the first listener (anActionWithoutAListener…), the receiver drops the SEND id (anIdThatLooksLike…)
- Findings to record in the 1b result (not 1b defects; the code follows the design text):
  - Only shareTextWithActions starts a new generation; plain shareText (ShareTextUseCase) keeps the earlier typed actions alive. The bridge re-registered on every shareText. For stage 2, the C ABI should map a share without actions to shareTextWithActions(content, emptyList()) to keep the bridge's behaviour. Not written in design 6.3/8.9
  - The id check is isEmpty (design 8.9 "空"); a whitespace-only id is accepted. The bridge dropped blank ids (isNotBlank)
  - ClipboardErrorCode.of(Throwable) maps an Error to UNKNOWN; the bridge classified only Exception

## T-23 DoD check (2026-10-05; two read-only subagents, findings verified by hand)
- Declarations: all of appendix A exists with the same names, parameters, return types and visibility. Files are grouped differently from 6.1 (C; fix the 6.1 table): RuntimeSupport.kt (LibraryExecutors/RequestIds/ProcessNonce), UiReasons.kt, UiHostCore.kt, DialogRequest/DialogResult/DialogError.kt, DialogUseCases.kt, NotificationPermissionModels/Ports/UseCases.kt, ScheduledNotificationEntry in JsonNotificationScheduleStore.kt, no InstallId (ScheduleIdentity.installId), NotificationEvents.kt, NotificationEventReceivers.kt, FragmentPermissionRequester.kt + PermissionSessions.kt, ntk_themes.xml. Design 6.1 says ShareRepositoryImpl is internal; it is public as in 1.12.0 (design wording error)
- PLANNED_SYMBOLS_EXEMPT: 265 names checked against android/; the only project name missing is InstallId (above). check_design_consistency.py has no source root for android-c-abi, so removing the declaration alone keeps it SKIP
- Fixed: EventHub.Registration.remove had no main-thread check (design 6.2) → checkMain before anything changes; unit test removeOffTheMainThread_throws_andTheListenerStaysRegistered (mutation: check after marking removed → fails)
- Fixed: design 8.13 @Deprecated on ShareTextUseCase's JSON form (both invoke operators; ShareUseCases.shareText calls them). AndroidShareManager.shareText suppresses it (IT-27 delegates to it)
- Fixed: NotificationEventIntents' four constants were public and not in appendix A → internal (only the library's own test used them)
- C, not changed: UiHostCore returns NOT_FOREGROUND when the foreground FragmentActivity has saved its state (no row in the 8.3 table); IllegalStateException from showNow/commitNow is always treated as state-saved; PermissionSessions does not post finishIfIdle after commitNow throws (NtkHostActivity.onCreate calls it anyway)
- Tests: IT-21 and IT-23 had no tests (not assigned to any task). User decision (design 0.8): write IT-21, IT-23 and the A gaps (IT-01/02 Startup-disabled path and foreground, IT-03/07 after process death, IT-10/11 cold start); fill cheap B/C gaps; record the rest in the 1b result
- B/C gaps listed by the check (to record or fill): IT-05 wrong seed → watchdog NOT_FOREGROUND; IT-04 show failure closes the host, complete the first right after the second; IT-03/IT-27 Dialog suspend cancel/failure, ManagersTest without Dialog/Progress delegation; IT-12 OS-cleared Alarm after update, Alarm due during the update; IT-19 RECEIVE_BOOT_COMPLETED removed, no notification shown; IT-20 notification PendingIntent identity (no tag, empty tag, encoded chars, extra update, setIdentifier); IT-08 fallback screen; UT-01 real LibraryRuntime rollback, concurrent tryBegin; UT-03 table cells, host destroyed vs result both orders; UT-06 API 32 branch; UT-07 DialogValue/NotificationInteraction toString; IT-14 reboot simulated by bootCount; IT-18 runs inside the library stage


## T-23 full runs (2026-10-05, --include-host)
- Pixel 6a API 36: 539 passed; baseline changed=0, added=226, removed=4 (the old ShareCallbackCoordinatorTest unit tests replaced in T-16)
- Emulator API 35: 535 passed up to H-04; step 6b stopped in the probe build (`lintVitalAnalyzeRelease`: FileNotFoundException for a library source). Cause: my mutation loop replaced android_library/src/main (rm + cp) at that moment. Not a test failure; the probe stage is run again with the new cases
- Note: never restore sources by `git checkout` while there are uncommitted changes (a first mutation loop did; stopped before it ran), and do not run mutation loops while another run builds from the same tree

## T-23 added tests (2026-10-05)
- IT-21 LogSentinelTest: login and text-input dialogs, clipboard copy/read, every text share path (text and subject), notification data through an event; reads `logcat -d --pid` without UiAutomator's own `UiObject2: Setting text` lines; checks the library's lines are present. First run found the sentinel only in UiAutomator's line and in SharePreviewOptions(title) — the preview title is not a value 8.11 hides, so the test no longer puts the sentinel there
- IT-23 ExistingDialogApiTest (6: the 0c DialogUiTest d01–d16 expectations through newInstance + listeners), ExistingPermissionHelperTest (3, run in step 5b with the permission revoked), ExistingShareApiTest (2: JSON chooser actions, skipped entries, broken JSON), ExistingNotificationApiTest (1: an app's own repository, as a Proxy that fails on any call, reads the library store for isScheduled)
- IT-02 ForegroundActivityTrackerTest (1), IT-03 AndroidDialogManagerTest#suspend_answer_cancelByTheCoroutine_andUnavailable
- Mutations (Pixel): killed — text-input watcher logs the text, login watcher logs the text, text-input cancel passes "" instead of null, JSON intentAction ignored, suspend cancellation does not cancel the dialog, isScheduled ignores the tag, helper always answers true. Survived (equivalent): ForegroundActivityTracker without the `stopped` condition — onSaveInstanceState marks a stopped, non-finishing Activity in the same transaction, and a finishing one is excluded by isFinishing, so no normal flow tells them apart
- UI test design updated for 1b (subagent; 5.1 counts Dialog 6→9, Notification 46→48, Share 14→17; 6.x rows; 6.6 new; 8 steps 5b/6b). Open points it found: HostState n10–n12 share numbers with style N-10–N-12 (written as `N-10（HostState）`); the library counts in step 4 were removed (unknown without a run). Existing script behaviour (stage 0d, not changed): `--filter` greps `${class}.kt`, so ReceivedShareLaunchUiTest and ReceivedShareTagInventoryTest (in other classes' files) do not run with `--filter ReceivedShare`

## T-23 probe stage (2026-10-05)
- Probe cases added: withoutStartup (noStartup flavor, versionCode 3, removes LibraryInitializer and ScheduledNotificationBootReceiver; installed over fullNext), postColdTap/coldEvents, postColdLaunch/coldLaunch, dialogBeforeKill/permissionBeforeKill on ProbeFragmentActivity (own task) + afterKill
- Probe fixes found while running: a recreated ProbeActivity re-ran its launch case (now only when savedInstanceState is null); two notifications were auto-grouped and a tap on the group only opened the app (one notification at a time); bringing back the singleTask ProbeActivity cleared the Activities above it (ProbeFragmentActivity in its own task, brought back directly); the library closes a restored fragment inside super.onCreate, so restored fragments are counted with FragmentLifecycleCallbacks registered before it
- Script fixes: `am start` that brings a task to the front exits non-zero (|| true); probe_case/probe_wait returned non-zero with no result, which stopped the script under set -e
- Results: 9/9 on Pixel 6a API 36 and the emulator API 35
- Mutations (Pixel, probe stage; set A at once, each affects a different case): restored dialog not dismissed → IT-03 FAIL (1 fragment left); restored permission fragment not removed → IT-07 FAIL; interactions not kept → IT-10 and IT-11 FAIL (events []); ensureInitialized does not seed → IT-01 FAIL (NOT_FOREGROUND). Set B: isScheduled initializes the library → IT-01/IT-23 case FAIL; the launch Activity does not open the app → IT-11 FAIL (no result). Every other case passed in both sets
- Not covered (recorded for the 1b result): IT-11 comparison "a Receiver that starts an Activity does not open it from the background" (platform behaviour, not library code) and the foreground variant beyond the r8 case (the launch Activity path while the app is in front)


## CU-03 (2026-10-05; done with adb and UiAutomator dumps on both devices)
- The 1.12.0 tag's Gradle root is android/AndroidLibraryExample and its settings.gradle.kts points at the library by absolute path (the working tree's android_library); a git worktree of 1.12.0 was pointed at its own library. The 1.12.0 sample offers only one schedule (15 s, persistAcrossBoot defaults to true), so only the worktree's sample screen was changed: 120 s, and a second schedule id 1011 with persistAcrossBoot = false on the same button. The library stayed at 1.12.0
- Steps: install the 1.12.0-based sample (same applicationId, debug key), schedule (1010 persisted, 1011 not), `adb install -r` the current sample, wait past the trigger, schedule again with the current sample
- Results (emulator API 35 and Pixel 6a API 36 alike): before the update 2 RTC alarms and the 1.x preferences file; after the update 1 alarm (1010 canceled), shared_prefs empty, marker no_backup/ntk/legacy_v1_discarded; LegacyScheduleCleaner log: cancelAlarm 1010, deletePreferences, mark. After the trigger time: 0 alarms, 0 notifications (the 1.x alarm targets the 1.x receiver class, which 2.0.0 does not have). A new schedule from the current sample showed 1010 after 15 s and wrote files/ntk/notification_schedules.json

## T-23 cheap B gaps filled (2026-10-05)
- UT-07 LogRedactionTest#newTypesToString_hideTheValues (DialogValue.Text/Login, NotificationInteraction); IT-04 AndroidDialogManagerTest#plainActivity_theFirstEndsRightAfterTheSecondArrives_theSecondStays; IT-20 NotificationPendingIntentIdentityTest (2: tags/actions/kinds are separate keys and the same key is one PendingIntent; the same key again replaces the extras). The full-screen launch identity moved to the probe (postColdTap/postColdLaunch), because the library test APK has no launcher Activity and fullScreenLaunch returns null there
- Mutations: empty tag = no tag → killed; FLAG_UPDATE_CURRENT removed → first survived (a PendingIntent of the same key left by an earlier run; the test now cancels it first) then killed; no identifier → probe killed (identifier null check); constant identifier → probe killed (two notifications share a PendingIntent); Login toString shows the password through a helper → killed; host finish decided by the first fragment only → survived (equivalent: finishIfIdle is posted, so the canceled fragment is already out of the list), host finishing after every dialog → killed
- AAR: `scripts/build_android_library_aar.sh -b release -m android_library -v 2.0.0 -o <scratch>/android_library-verify.aar` → `[done] Created ...`. The script writes `libraryVersion` into android/gradle.properties; reverted to 1.3.0 (choosing the version belongs to the release)

## Mutations that first survived (recorded at the implementation review, 2026-10-05)
- IT-21: the text-input watcher logging the text survived at first, because the test used only the login dialog; a text-input dialog was added, then both watchers' mutations were killed
- IT-20: FLAG_UPDATE_CURRENT removed survived at first (a PendingIntent of the same key from an earlier run); the test now cancels it first
- Full-screen launch identifier removed survived at first in the library test, which returned early (no launcher Activity in the test APK); the check moved to the probe and was killed there
- Count: T-21 4, T-22 5, T-23 22 (remove check 1, IT-21/IT-23/IT-02/IT-03 8, probe 6, cheap B 7); after the review 5 more (initialized listener catch, command version, UT-08 lock, store JSON log, suspend Canceled), all killed
