package com.jonghyunkim.android.nativetoolkit.example.spike

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.os.SystemClock
import android.util.Log
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.core.app.NotificationManagerCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.android.nativetoolkit.example.MainActivity
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * Throwaway probes for the start of stage 0c (not committed; copied to results/probes/stage0c/).
 * Each probe only logs what it sees (tag Probe0c) and dumps the window hierarchy.
 */
@RunWith(AndroidJUnit4::class)
class Stage0cProbeTest {

    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context = instrumentation.targetContext
    private val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    @Before
    fun setUp() {
        instrumentation.uiAutomation.grantRuntimePermission(context.packageName, Manifest.permission.POST_NOTIFICATIONS)
        instrumentation.uiAutomation.executeShellCommand("appops set ${context.packageName} SCHEDULE_EXACT_ALARM allow").close()
        instrumentation.uiAutomation.executeShellCommand("appops set ${context.packageName} USE_FULL_SCREEN_INTENT allow").close()
        NotificationManagerCompat.from(context).cancelAll()
    }

    @After
    fun tearDown() {
        device.pressHome()
        NotificationManagerCompat.from(context).cancelAll()
    }

    @Test
    fun probe01_styleExtras() {
        open("menu.notification")
        val buttons = listOf(
            "showDefaultStyle" to 1001, "showBigTextStyle" to 1002, "showInboxStyle" to 1003,
            "showBigPictureStyle" to 1004, "showMessagingStyle" to 1005, "showMediaStyle" to 1006,
            "showDecoratedCustomViewStyle" to 1007, "showDecoratedMediaCustomViewStyle" to 1008,
            "showGroupSummary" to 1100, "showProgress50" to 1009
        )
        for ((tag, id) in buttons) {
            click("notification.$tag")
            val sbn = waitFor(id, 10_000)
            if (sbn == null) {
                Log.d(TAG, "[style] id=$id NOT FOUND")
                continue
            }
            val n = sbn.notification
            val e = n.extras
            Log.d(
                TAG,
                "[style] id=$id template=${e.getString(Notification.EXTRA_TEMPLATE)} " +
                    "compat=${e.getString("androidx.core.app.extra.COMPAT_TEMPLATE")} " +
                    "picture=${e.containsKey(Notification.EXTRA_PICTURE)} pictureIcon=${e.containsKey(Notification.EXTRA_PICTURE_ICON)} " +
                    "largeIcon=${n.getLargeIcon() != null} titleBig=${e.getCharSequence(Notification.EXTRA_TITLE_BIG)} " +
                    "lines=${e.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)?.size} " +
                    "messages=${e.getParcelableArray(Notification.EXTRA_MESSAGES)?.size} " +
                    "progress=${e.getInt(Notification.EXTRA_PROGRESS)}/${e.getInt(Notification.EXTRA_PROGRESS_MAX)} " +
                    "group=${n.group} sortKey=${n.sortKey} actions=${n.actions?.map { it.title }} keys=${e.keySet().sorted()}"
            )
        }
        Log.d(TAG, "[style] active=${manager.activeNotifications.map { "${it.id}/${it.tag}/${it.notification.group}" }}")
    }

    @Test
    fun probe02_foregroundServiceDelay() {
        open("menu.notification")
        val start = SystemClock.elapsedRealtime()
        click("notification.startProgressFgs10")
        val sbn = waitFor(1011, 20_000)
        Log.d(TAG, "[fgs] found=${sbn != null} after ${SystemClock.elapsedRealtime() - start} ms flags=${sbn?.notification?.flags}")
        click("notification.stopProgressFgs")
    }

    @Test
    fun probe03_callButtons() {
        open("menu.notification")
        for ((tag, name) in listOf("incomingCall" to "incoming", "ongoingCall" to "ongoing", "screeningCall" to "screening")) {
            click("notification.$tag")
            val sbn = waitFor(1200, 10_000)
            val e = sbn?.notification?.extras
            Log.d(
                TAG,
                "[call:$name] found=${sbn != null} template=${e?.getString(Notification.EXTRA_TEMPLATE)} " +
                    "actions=${sbn?.notification?.actions?.map { it.title }} " +
                    "answer=${e?.containsKey(Notification.EXTRA_ANSWER_INTENT)} decline=${e?.containsKey(Notification.EXTRA_DECLINE_INTENT)} " +
                    "hangUp=${e?.containsKey(Notification.EXTRA_HANG_UP_INTENT)}"
            )
            device.openNotification()
            device.wait(Until.hasObject(By.textContains("Native Toolkit Support")), 5_000)
            dump("probe03-$name")
            val buttons = device.findObjects(By.clazz("android.widget.Button"))
            Log.d(TAG, "[call:$name] shade buttons=${buttons.map { "${it.text}|${it.contentDescription}|${it.resourceName}|${it.visibleBounds}" }}")
            device.pressBack()
            click("notification.stopCallForegroundService")
            waitGone(1200, 10_000)
        }
    }

    @Test
    fun probe04_selfInSharesheet() {
        open("menu.share")
        click("share.shareText")
        device.wait(Until.hasObject(By.pkg("com.android.intentresolver")), 10_000)
        Log.d(TAG, "[share] resolver=${device.currentPackageName}")
        var found = device.findObject(By.text("Native Toolkit Example")) != null
        var swipes = 0
        while (!found && swipes < 6) {
            device.findObject(By.scrollable(true))?.scroll(Direction.DOWN, 0.8f)
            swipes++
            found = device.wait(Until.hasObject(By.text("Native Toolkit Example")), 1_000)
        }
        Log.d(TAG, "[share] self listed=$found swipes=$swipes")
        device.pressBack()
    }

    private fun open(menuTag: String) {
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag(menuTag))
        compose.onNodeWithTag(menuTag).performClick()
        compose.waitForIdle()
    }

    private fun click(tag: String) {
        compose.onNode(hasScrollAction()).performScrollToNode(hasTestTag(tag))
        compose.onNodeWithTag(tag).performClick()
        compose.waitForIdle()
    }

    private fun waitFor(id: Int, timeoutMs: Long): android.service.notification.StatusBarNotification? {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < end) {
            manager.activeNotifications.firstOrNull { it.id == id }?.let { return it }
            Thread.sleep(100)
        }
        return null
    }

    private fun waitGone(id: Int, timeoutMs: Long) {
        val end = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < end && manager.activeNotifications.any { it.id == id }) Thread.sleep(100)
    }

    private fun dump(name: String) {
        val dir = context.getExternalFilesDir("probe") ?: return
        device.dumpWindowHierarchy(File(dir, "$name.xml"))
    }

    private companion object {
        const val TAG = "Probe0c"
    }
}
