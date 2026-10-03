package com.jonghyunkim.android.nativetoolkit.example.spike

import android.Manifest
import android.app.UiAutomation
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
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
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/**
 * Throwaway spike for stage 0a of the android-c-abi topic (not committed).
 *
 * Each test checks whether one piece of system UI can be driven by UiAutomator, and dumps the
 * window hierarchy so the result can be inspected afterwards. Findings go to
 * artifact/topics/android-c-abi/results/.
 */
@RunWith(AndroidJUnit4::class)
class Stage0aSpikeTest {

    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val targetContext = instrumentation.targetContext
    private val packageName = targetContext.packageName
    private val toastTexts = CopyOnWriteArrayList<String>()

    @Before
    fun setUp() {
        Log.d(TAG, "[setUp]")
        instrumentation.uiAutomation.grantRuntimePermission(packageName, Manifest.permission.POST_NOTIFICATIONS)
        NotificationManagerCompat.from(targetContext).cancelAll()
        instrumentation.uiAutomation.executeShellCommand("appops set $packageName SCHEDULE_EXACT_ALARM allow").close()
        instrumentation.uiAutomation.setOnAccessibilityEventListener { event ->
            if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED) {
                val text = event.text.joinToString(" ")
                Log.d(TAG, "[accessibility] class=${event.className} package=${event.packageName} text=$text")
                toastTexts.add(text)
            }
        }
    }

    @After
    fun tearDown() {
        Log.d(TAG, "[tearDown]")
        instrumentation.uiAutomation.setOnAccessibilityEventListener(null)
        device.pressHome()
        NotificationManagerCompat.from(targetContext).cancelAll()
    }

    @Test
    fun spike01_actionButtonFromShade() {
        navigate("Notification Example")
        click("Show Action Buttons Sample")
        Thread.sleep(1_000)
        dump("spike01-app")
        device.openNotification()
        val title = device.wait(Until.findObject(By.text("Interaction / Action Buttons")), TIMEOUT)
        dump("spike01-shade")
        assertNotNull("notification title in shade", title)
        var accept = device.findObject(By.text("Accept"))
        if (accept == null) {
            Log.d(TAG, "[spike01] Accept not visible; expanding by swipe")
            title.swipe(Direction.DOWN, 0.8f)
            accept = device.wait(Until.findObject(By.text("Accept")), TIMEOUT)
        }
        dump("spike01-expanded")
        assertNotNull("Accept action button", accept)
        accept.click()
        device.pressBack()
        waitForStatus("Action button pressed: Accept")
    }

    @Test
    fun spike02_scheduledNotificationAppears() {
        navigate("Notification Example")
        click("Schedule Notification (15 sec)")
        Thread.sleep(1_000)
        dump("spike02-app")
        waitForStatus("Scheduled a high-priority notification")
        val start = System.currentTimeMillis()
        device.openNotification()
        val found = device.wait(Until.findObject(By.text("Scheduled BigText")), 45_000)
        Log.d(TAG, "[spike02] found=${found != null} after ${System.currentTimeMillis() - start} ms")
        dump("spike02-shade")
        assertNotNull("scheduled notification in shade", found)
    }

    @Test
    fun spike03_inAppDialog() {
        navigate("Dialog Example")
        click("ShowDialog")
        val ok = device.wait(Until.findObject(By.text("OK")), TIMEOUT)
        dump("spike03-dialog")
        assertNotNull("OK button", ok)
        ok.click()
        waitForStatus("buttonText: OK")
    }

    @Test
    fun spike04_chooserCustomAction() {
        navigate("Share Example")
        click("Share Text with Custom Action")
        val custom = device.wait(Until.findObject(By.text("Custom")), TIMEOUT)
        dump("spike04-chooser")
        assertNotNull("custom chooser action", custom)
        custom.click()
        assertTrue("toast captured: $toastTexts", waitForToast("Custom chooser action tapped"))
    }

    @Test
    fun spike05_deleteIntentBySwipe() {
        navigate("Notification Example")
        click("Show DeleteIntent Sample")
        Thread.sleep(1_000)
        dump("spike05-app")
        device.openNotification()
        val title = device.wait(Until.findObject(By.text("Interaction / deleteIntent")), TIMEOUT)
        assertNotNull("delete sample in shade", title)
        val y = title.visibleCenter.y
        device.swipe(device.displayWidth / 10, y, device.displayWidth - 10, y, 20)
        Thread.sleep(1_000)
        dump("spike05-after-swipe")
        assertTrue("toast captured: $toastTexts", waitForToast("dismissed (deleteIntent)"))
    }

    @Test
    fun spike06_progressForegroundService() {
        navigate("Notification Example")
        click("Start Progress FGS 10%")
        Thread.sleep(1_000)
        dump("spike06-app")
        device.openNotification()
        val bar = device.wait(Until.findObject(By.clazz("android.widget.ProgressBar")), TIMEOUT)
        dump("spike06-shade")
        Log.d(TAG, "[spike06] progressBar=${bar != null} desc=${bar?.contentDescription} text=${bar?.text}")
        logProgressRange()
        device.pressBack()
        click("Stop Progress FGS")
        assertNotNull("progress bar in shade", bar)
    }

    @Test
    fun spike07_mediaStyleLocation() {
        navigate("Notification Example")
        click("Show Media Style")
        device.openNotification()
        val found = device.wait(Until.findObject(By.textContains("Native Toolkit Player")), TIMEOUT)
        dump("spike07-shade")
        Log.d(TAG, "[spike07] found=${found != null} pkg=${found?.applicationPackage} res=${found?.resourceName}")
        assertNotNull("media notification text somewhere in system UI", found)
    }

    @Test
    fun spike08_directShareTargetInChooser() {
        navigate("Share Example")
        click("Register Direct Share Target")
        waitForStatus("registerDirectShareTarget called")
        click("Share Text")
        val target = device.wait(Until.findObject(By.text("Sample User")), TIMEOUT)
        dump("spike08-chooser")
        Log.d(TAG, "[spike08] direct share target visible=${target != null}")
        device.pressBack()
    }

    private fun navigate(title: String) {
        compose.onNode(hasScrollAction()).performScrollToNode(hasText(title))
        compose.onNodeWithText(title).performClick()
        compose.waitForIdle()
    }

    private fun click(label: String) {
        val scrollables = compose.onAllNodes(hasScrollAction()).fetchSemanticsNodes()
        if (scrollables.isNotEmpty()) {
            compose.onNode(hasScrollAction()).performScrollToNode(hasText(label))
        }
        compose.onNodeWithText(label).performClick()
        compose.waitForIdle()
    }

    private fun waitForStatus(substring: String) {
        compose.waitUntil(timeoutMillis = TIMEOUT) {
            compose.onAllNodesWithText(substring, substring = true).fetchSemanticsNodes().isNotEmpty()
        }
    }

    private fun waitForToast(substring: String): Boolean {
        val deadline = System.currentTimeMillis() + TIMEOUT
        while (System.currentTimeMillis() < deadline) {
            if (toastTexts.any { it.contains(substring) }) return true
            Thread.sleep(100)
        }
        return false
    }

    private fun logProgressRange() {
        val root = instrumentation.uiAutomation.rootInActiveWindow ?: return
        val queue = ArrayDeque(listOf(root))
        while (queue.isNotEmpty()) {
            val node = queue.removeFirst()
            node.rangeInfo?.let { Log.d(TAG, "[range] class=${node.className} current=${it.current} max=${it.max}") }
            for (i in 0 until node.childCount) node.getChild(i)?.let { queue.addLast(it) }
        }
    }

    private fun dump(name: String) {
        val dir = targetContext.getExternalFilesDir("spike") ?: return
        val file = File(dir, "$name.xml")
        device.dumpWindowHierarchy(file)
        Log.d(TAG, "[dump] ${file.absolutePath}")
    }

    private companion object {
        const val TAG = "Spike0a"
        const val TIMEOUT = 10_000L

        @Suppress("unused")
        val FLAGS = UiAutomation.FLAG_DONT_SUPPRESS_ACCESSIBILITY_SERVICES
    }
}
