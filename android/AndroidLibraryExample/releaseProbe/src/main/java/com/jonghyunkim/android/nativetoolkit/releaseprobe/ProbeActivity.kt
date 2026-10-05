package com.jonghyunkim.android.nativetoolkit.releaseprobe

import android.app.Activity
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.TextView
import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.notification.AndroidNotificationManager
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationPlatformOptions
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentRequest
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidPendingIntentType
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationCommandRepository
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationContent
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEventIntents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationShown
import java.lang.reflect.Proxy
import java.util.concurrent.CopyOnWriteArrayList
import com.jonghyunkim.nativetoolkit.notification.application.usecase.NotificationUseCases as UseCasesWithRepository

/**
 * Runs one release check of android_library and logs `RESULT <case> PASS|FAIL <detail>` with the
 * tag [TAG] (Kotlin API design 12: IT-01, IT-03, IT-07, IT-10, IT-11, IT-19, IT-22, IT-23,
 * IT-26). scripts/test_android.sh starts it with `--es case <case>` and reads the log; for the
 * checks across a process death it kills the process in between. It is a plain Activity, so
 * library UI needs the library's transparent host.
 */
class ProbeActivity : Activity() {

    private val main = Handler(Looper.getMainLooper())
    private lateinit var status: TextView
    private val manager by lazy { AndroidNotificationManager.getInstance(this) }

    // Set while verifyAfterUpdate waits for the content intent of the notification to come back.
    private var awaitingContentIntent = false

    private val prefs by lazy { getSharedPreferences(PREFS, MODE_PRIVATE) }

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState")
        super.onCreate(savedInstanceState)
        status = TextView(this).apply { text = "NTK release probe" }
        setContentView(status)
        // Recreated after a process death: the launch intent's case already ran in the old process.
        if (savedInstanceState == null) handle(intent) else Log.d(TAG, "[onCreate] restored; the launch case is not run again")
    }

    override fun onNewIntent(intent: Intent) {
        Log.d(TAG, "[onNewIntent] intent: $intent")
        super.onNewIntent(intent)
        setIntent(intent)
        handle(intent)
    }

    // The library's launch Activity and the content intent open this Activity again without a case.
    private fun handle(intent: Intent) {
        Log.d(TAG, "[handle] intent: $intent")
        if (awaitingContentIntent && intent.hasExtra(EXTRA_VALUE)) {
            awaitingContentIntent = false
            val value = intent.getStringExtra(EXTRA_VALUE)
            if (value == "kept") pass(CASE_VERIFY, "content intent extra kept") else fail(CASE_VERIFY, "content intent extra <$value>")
            return
        }
        val case = intent.getStringExtra(EXTRA_CASE)
        if (case == null) {
            checkColdLaunch()
            return
        }
        when (case) {
            CASE_R8 -> checkStartup()
            CASE_PERMISSIONS -> checkPermissions()
            CASE_SCHEDULE -> scheduleForUpdate()
            CASE_VERIFY -> verifyAfterUpdate()
            CASE_WITHOUT_STARTUP -> checkWithoutStartup()
            CASE_POST_COLD_TAP -> postForColdStart(launchApp = false)
            CASE_POST_COLD_LAUNCH -> postForColdStart(launchApp = true)
            CASE_COLD_EVENTS -> checkColdEvents()
            CASE_DIALOG_KILL, CASE_PERMISSION_KILL ->
                startActivity(Intent(this, ProbeFragmentActivity::class.java).putExtra(EXTRA_CASE, case).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            else -> fail(case, "unknown case")
        }
    }

    // --- IT-22 ---------------------------------------------------------------------------------

    private fun checkStartup() {
        Log.d(TAG, "[checkStartup]")
        if (!LibraryRuntime.isInitialized()) return fail(CASE_R8, "startup: the library is not initialized")
        checkHost()
    }

    // A plain Activity cannot hold the dialog fragment, so the library starts its transparent host.
    private fun checkHost() {
        Log.d(TAG, "[checkHost]")
        val dialogs = AndroidDialogManager.getInstance(this)
        var result: DialogResult? = null
        val requestId = dialogs.show(DialogRequest.Alert(title = "Probe", message = "R8 check")) { result = it }
        main.postDelayed({
            val hostResumed = ProbeApplication.resumed.contains(HOST_ACTIVITY)
            dialogs.cancel(requestId)
            main.postDelayed({
                val canceled = result
                when {
                    !hostResumed -> fail(CASE_R8, "host: not resumed; resumed=${ProbeApplication.resumed}")
                    canceled !is DialogResult.Canceled || canceled.reason != CancelReason.REQUESTED ->
                        fail(CASE_R8, "host: result <$canceled>")
                    else -> checkEvents()
                }
            }, 1_000)
        }, 2_500)
    }

    // A tap that opens the app goes through the invisible launch Activity, an action through the
    // library's receiver.
    private fun checkEvents() {
        Log.d(TAG, "[checkEvents]")
        val events = CopyOnWriteArrayList<NotificationInteraction>()
        val registration = manager.interactions.addListener { event, _ -> events += event }
        send(NotificationEventIntents.bodyTap(this, EVENT_ID, "probe", mapOf("k" to "v"), launchApp = true))
        main.postDelayed({
            val tap = events.firstOrNull { it.kind == NotificationInteraction.Kind.BODY_TAP }
            if (tap == null || tap.notificationId != EVENT_ID || tap.data["k"] != "v") {
                registration.remove()
                return@postDelayed fail(CASE_R8, "launch activity: events $events")
            }
            send(NotificationEventIntents.action(this, EVENT_ID, "probe", "probe_action", launchApp = false))
            main.postDelayed({
                registration.remove()
                val action = events.firstOrNull { it.kind == NotificationInteraction.Kind.ACTION }
                if (action?.actionId != "probe_action") fail(CASE_R8, "receiver: events $events") else checkSchedule()
            }, 3_000)
        }, 4_000)
    }

    private fun checkSchedule() {
        Log.d(TAG, "[checkSchedule]")
        val shown = CopyOnWriteArrayList<NotificationShown>()
        val registration = manager.shown.addListener { event, _ -> shown += event }
        val command = command(SCHEDULE_ID, "Probe scheduled", "Scheduled by the R8 check")
        manager.schedule(command, NotificationSchedule(System.currentTimeMillis() + 3_000, persistAcrossBoot = true))
            .onFailure {
                registration.remove()
                return fail(CASE_R8, "schedule: $it")
            }
        poll(seconds = 60, onTimeout = {
            registration.remove()
            fail(CASE_R8, "schedule: not shown within 60 s")
        }) {
            if (shown.none { it.notificationId == SCHEDULE_ID }) return@poll false
            registration.remove()
            if (manager.isScheduled(SCHEDULE_ID)) fail(CASE_R8, "schedule: still saved after it was shown")
            else pass(CASE_R8, "startup, host, launch activity, receiver and schedule")
            true
        }
    }

    // --- IT-19 ---------------------------------------------------------------------------------

    private fun checkPermissions() {
        Log.d(TAG, "[checkPermissions]")
        if (manager.hasPermission()) return fail(CASE_PERMISSIONS, "hasPermission is true")
        if (manager.canScheduleExactAlarms()) return fail(CASE_PERMISSIONS, "canScheduleExactAlarms is true")
        if (Build.VERSION.SDK_INT >= 34 && getSystemService(NotificationManager::class.java).canUseFullScreenIntent()) {
            return fail(CASE_PERMISSIONS, "canUseFullScreenIntent is true")
        }
        var answered = false
        manager.requestPermission { result ->
            answered = true
            if (result == PermissionRequestResult.Denied) pass(CASE_PERMISSIONS, "not granted, exact alarms off, full screen off, request denied")
            else fail(CASE_PERMISSIONS, "request: $result")
        }
        main.postDelayed({ if (!answered) fail(CASE_PERMISSIONS, "request: no answer within 15 s") }, 15_000)
    }

    // --- IT-26 ---------------------------------------------------------------------------------

    private fun scheduleForUpdate() {
        Log.d(TAG, "[scheduleForUpdate]")
        val icon = Bitmap.createBitmap(64, 64, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.RED) }
        val contentIntent = AndroidPendingIntentRequest(
            intent = Intent(this, ProbeActivity::class.java).putExtra(EXTRA_VALUE, "kept"),
            requestCode = 26,
            type = AndroidPendingIntentType.ACTIVITY
        )
        val command = command(UPDATE_ID, UPDATE_TITLE, UPDATE_TEXT).copy(
            platformOptions = AndroidNotificationPlatformOptions(largeIconBitmap = icon, contentIntent = contentIntent)
        )
        val triggerAt = System.currentTimeMillis() + 60_000
        // A second schedule far ahead stays saved for the check without Startup (IT-23).
        manager.schedule(command(KEEP_ID, "Probe kept", "Read without Startup"), NotificationSchedule(triggerAt + 3_600_000, persistAcrossBoot = true))
            .onFailure { return fail(CASE_SCHEDULE, "schedule $KEEP_ID: $it") }
        manager.schedule(command, NotificationSchedule(triggerAt, persistAcrossBoot = true))
            .onSuccess { pass(CASE_SCHEDULE, "triggerAt=$triggerAt") }
            .onFailure { fail(CASE_SCHEDULE, "schedule: $it") }
    }

    private fun verifyAfterUpdate() {
        Log.d(TAG, "[verifyAfterUpdate]")
        val version = packageManager.getPackageInfo(packageName, 0).longVersionCode
        if (version != 2L) return fail(CASE_VERIFY, "version code $version")
        val posted = getSystemService(NotificationManager::class.java).activeNotifications.firstOrNull { it.id == UPDATE_ID }
            ?: return fail(CASE_VERIFY, "notification $UPDATE_ID is not shown")
        val extras = posted.notification.extras
        when {
            extras.getCharSequence(android.app.Notification.EXTRA_TITLE)?.toString() != UPDATE_TITLE -> fail(CASE_VERIFY, "title")
            extras.getCharSequence(android.app.Notification.EXTRA_TEXT)?.toString() != UPDATE_TEXT -> fail(CASE_VERIFY, "text")
            posted.notification.getLargeIcon() == null -> fail(CASE_VERIFY, "no large icon")
            posted.notification.contentIntent == null -> fail(CASE_VERIFY, "no content intent")
            else -> {
                // The content intent opens this Activity with the extra it was scheduled with.
                awaitingContentIntent = true
                posted.notification.contentIntent.send()
                main.postDelayed({ if (awaitingContentIntent) fail(CASE_VERIFY, "content intent did not arrive") }, 10_000)
            }
        }
    }

    // --- IT-01, IT-23: Startup disabled -----------------------------------------------------------

    // The noStartup flavor removes the initializer and the package-replaced receiver. isScheduled
    // with an app's own repository reads the store without initializing anything (IT-23); manual
    // initialization after this Activity started seeds it as the foreground (IT-01, IT-02).
    private fun checkWithoutStartup() {
        Log.d(TAG, "[checkWithoutStartup]")
        if (LibraryRuntime.isInitialized()) return fail(CASE_WITHOUT_STARTUP, "initialized before the check")
        val ownRepository = Proxy.newProxyInstance(
            NotificationCommandRepository::class.java.classLoader,
            arrayOf(NotificationCommandRepository::class.java)
        ) { _, method, _ -> throw IllegalStateException("the app's repository was called: ${method.name}") } as NotificationCommandRepository
        if (!UseCasesWithRepository(ownRepository).isScheduled(this, KEEP_ID, null)) return fail(CASE_WITHOUT_STARTUP, "isScheduled is false")
        if (LibraryRuntime.isInitialized()) return fail(CASE_WITHOUT_STARTUP, "isScheduled initialized the library")
        // After the lifecycle callbacks of this Activity have passed, so only the seed reports it.
        main.postDelayed({
            val state = LibraryRuntime.ensureInitialized(this)
            if (state != LibraryRuntime.InitState.DONE) return@postDelayed fail(CASE_WITHOUT_STARTUP, "ensureInitialized: $state")
            showOnHost(CASE_WITHOUT_STARTUP) {
                manager.cancelAllScheduled()
                pass(CASE_WITHOUT_STARTUP, "isScheduled from the store, manual initialization, seeded foreground")
            }
        }, 1_000)
    }

    // --- IT-10, IT-11: cold start ---------------------------------------------------------------

    // Posts one notification: a tap that stays in the background, or one that opens the app. Only
    // one is shown at a time, because the system groups two and a tap on the group opens the app.
    // The script kills the process before the tap.
    private fun postForColdStart(launchApp: Boolean) {
        Log.d(TAG, "[postForColdStart] launchApp: $launchApp")
        val case = if (launchApp) CASE_POST_COLD_LAUNCH else CASE_POST_COLD_TAP
        val fullScreen = NotificationEventIntents.fullScreenLaunch(this, COLD_LAUNCH_ID, null)
            ?: return fail(case, "no full-screen launch request")
        if (fullScreen.intent.data != null || fullScreen.intent.identifier == null) {
            return fail(case, "full-screen intent: data ${fullScreen.intent.data}, identifier ${fullScreen.intent.identifier}")
        }
        // Request code 0 for every notification: the identifier keeps the PendingIntents apart (IT-20).
        val other = NotificationEventIntents.fullScreenLaunch(this, COLD_TAP_ID, null)!!
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        if (PendingIntent.getActivity(this, 0, fullScreen.intent, flags) == PendingIntent.getActivity(this, 0, other.intent, flags)) {
            return fail(case, "full-screen intents of two notifications share a PendingIntent")
        }
        getSystemService(NotificationManager::class.java).cancelAll()
        val id = if (launchApp) COLD_LAUNCH_ID else COLD_TAP_ID
        val title = if (launchApp) COLD_LAUNCH_TITLE else COLD_TAP_TITLE
        val tap = NotificationEventIntents.bodyTap(this, id, null, mapOf("cold" to if (launchApp) "launch" else "tap"), launchApp)
        val command = command(id, title, "Tap after the process is killed").copy(
            platformOptions = AndroidNotificationPlatformOptions(contentIntent = tap)
        )
        manager.show(command).onFailure { return fail(case, "show $id: $it") }
        // The launch check runs only in a process started after this one is killed.
        if (launchApp) prefs.edit().putBoolean(PREF_COLD_LAUNCH, true).putLong(PREF_KILLED_AT, System.currentTimeMillis()).commit()
        pass(case, "posted; full-screen intents have no data and do not share a PendingIntent")
    }

    // The tap reached the library's receiver in a new process with no listener; the first
    // listener gets it inside addListener (IT-10).
    private fun checkColdEvents() {
        Log.d(TAG, "[checkColdEvents]")
        val events = CopyOnWriteArrayList<NotificationInteraction>()
        manager.interactions.addListener { event, _ -> events += event }.remove()
        val tap = events.singleOrNull()
        if (tap?.kind == NotificationInteraction.Kind.BODY_TAP && tap.notificationId == COLD_TAP_ID && tap.data["cold"] == "tap") {
            pass(CASE_COLD_EVENTS, "kept while no listener and delivered to the first one")
        } else {
            fail(CASE_COLD_EVENTS, "events $events")
        }
    }

    // The tap that opens the app started the process through the launch Activity (IT-11).
    private fun checkColdLaunch() {
        Log.d(TAG, "[checkColdLaunch]")
        if (!prefs.getBoolean(PREF_COLD_LAUNCH, false) || ProbeApplication.startedAt < prefs.getLong(PREF_KILLED_AT, Long.MAX_VALUE)) return
        prefs.edit().remove(PREF_COLD_LAUNCH).commit()
        val events = CopyOnWriteArrayList<NotificationInteraction>()
        val registration = manager.interactions.addListener { event, _ -> events += event }
        poll(seconds = 5, onTimeout = {
            registration.remove()
            fail(CASE_COLD_LAUNCH, "events $events")
        }) {
            val tap = events.firstOrNull { it.notificationId == COLD_LAUNCH_ID } ?: return@poll false
            registration.remove()
            if (tap.kind == NotificationInteraction.Kind.BODY_TAP && tap.data["cold"] == "launch") pass(CASE_COLD_LAUNCH, "the app opened and got the tap")
            else fail(CASE_COLD_LAUNCH, "event $tap")
            true
        }
    }

    // --- helpers -------------------------------------------------------------------------------

    // Shows an alert, which needs the foreground Activity, and checks that the host came up.
    private fun showOnHost(case: String, then: () -> Unit) {
        Log.d(TAG, "[showOnHost] case: $case")
        val dialogs = AndroidDialogManager.getInstance(this)
        var result: DialogResult? = null
        val requestId = dialogs.show(DialogRequest.Alert(title = "Probe", message = case)) { result = it }
        main.postDelayed({
            val hostResumed = ProbeApplication.resumed.contains(HOST_ACTIVITY)
            dialogs.cancel(requestId)
            main.postDelayed({
                val canceled = result
                when {
                    !hostResumed -> fail(case, "host: not resumed; result=$canceled")
                    canceled !is DialogResult.Canceled || canceled.reason != CancelReason.REQUESTED -> fail(case, "host: result <$canceled>")
                    else -> then()
                }
            }, 1_000)
        }, 2_500)
    }

    private fun command(id: Int, title: String, message: String): AndroidNotificationCommand {
        Log.d(TAG, "[command] id: $id")
        val channel = NotificationChannel(id = "ntk_probe", name = "NTK Probe")
        manager.createChannel(channel)
        return AndroidNotificationCommand(NotificationContent(id = id, title = title, message = message, channel = channel))
    }

    private fun send(request: AndroidPendingIntentRequest) {
        Log.d(TAG, "[send] type: ${request.type}, requestCode: ${request.requestCode}")
        val flags = request.flags or if (request.mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
        val pendingIntent = when (request.type) {
            AndroidPendingIntentType.ACTIVITY -> PendingIntent.getActivity(this, request.requestCode, request.intent, flags)
            AndroidPendingIntentType.BROADCAST -> PendingIntent.getBroadcast(this, request.requestCode, request.intent, flags)
            else -> throw IllegalArgumentException("unexpected ${request.type}")
        }
        pendingIntent.send()
    }

    // Calls [check] once a second until it returns true, or calls [onTimeout] after [seconds].
    private fun poll(seconds: Int, onTimeout: () -> Unit, check: () -> Boolean) {
        Log.d(TAG, "[poll] seconds: $seconds")
        var left = seconds
        lateinit var tick: Runnable
        tick = Runnable {
            when {
                check() -> Unit
                --left <= 0 -> onTimeout()
                else -> main.postDelayed(tick, 1_000)
            }
        }
        main.postDelayed(tick, 1_000)
    }

    private fun pass(case: String, detail: String) = report(case, "PASS", detail)

    private fun fail(case: String, detail: String) = report(case, "FAIL", detail)

    private fun report(case: String, outcome: String, detail: String) {
        Log.i(TAG, "RESULT $case $outcome $detail")
        status.text = "$case: $outcome\n$detail"
    }

    companion object {
        /** The log tag the test script reads. */
        const val TAG = "NtkProbe"

        const val EXTRA_CASE = "case"
        private const val EXTRA_VALUE = "probe.value"

        const val CASE_R8 = "r8"
        const val CASE_PERMISSIONS = "permissions"
        const val CASE_SCHEDULE = "scheduleForUpdate"
        const val CASE_VERIFY = "verifyAfterUpdate"
        const val CASE_WITHOUT_STARTUP = "withoutStartup"
        const val CASE_POST_COLD_TAP = "postColdTap"
        const val CASE_POST_COLD_LAUNCH = "postColdLaunch"
        const val CASE_COLD_EVENTS = "coldEvents"
        const val CASE_COLD_LAUNCH = "coldLaunch"
        const val CASE_DIALOG_KILL = "dialogBeforeKill"
        const val CASE_PERMISSION_KILL = "permissionBeforeKill"

        private const val PREF_COLD_LAUNCH = "coldLaunch"
        const val PREF_AFTER_KILL = "afterKill"
        const val PREF_KILLED_AT = "killedAt"

        const val PREFS = "probe"
        private const val HOST_ACTIVITY = "com.jonghyunkim.nativetoolkit.common.presentation.NtkHostActivity"
        private const val EVENT_ID = 2201
        private const val SCHEDULE_ID = 2202
        private const val UPDATE_ID = 2601
        private const val KEEP_ID = 2602
        private const val COLD_TAP_ID = 2701
        private const val COLD_LAUNCH_ID = 2702
        const val COLD_TAP_TITLE = "Probe cold tap"
        const val COLD_LAUNCH_TITLE = "Probe cold launch"
        private const val UPDATE_TITLE = "Probe update"
        private const val UPDATE_TEXT = "Scheduled before the update"
    }
}
