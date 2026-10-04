package com.jonghyunkim.android.nativetoolkit.example

import android.app.Activity
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.runner.lifecycle.Stage
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNotification
import com.jonghyunkim.android.nativetoolkit.example.infra.ExternalLaunchUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Delivery of the library's notification events across MainActivity's lifecycle (sample app
 * design 4.2 and 5). The sample's listener lives as long as MainActivity, so these cases destroy
 * and recreate it while the process lives. They use UiAutomator, because the Compose rule loses
 * the activity in both cases.
 */
@CategoryNotification
@RunWith(AndroidJUnit4::class)
class NotificationEventDeliveryUiTest : ExternalLaunchUiTest() {

    @Before
    fun showActionButtons() {
        app.open("notification")
        app.click("notification.showActionButtonsSample")
        app.waitForStatus("notification", "✅ Displayed action button sample notification.")
        notifications.waitFor(1112)
    }

    @Test
    fun n61_actionWhileMainActivityIsGone_isToastedOnceAfterTheRelaunch() {
        val activity = resumedMainActivity()
        instrumentation.runOnMainSync { activity.finish() }
        waitUntil("MainActivity was not destroyed") { stageOf(activity) == Stage.DESTROYED }

        shade.open()
        shade.clickButton("Interaction / Action Buttons", "Accept")
        shade.close()
        // No listener while MainActivity is gone: the library keeps the event.
        Thread.sleep(SETTLE_MS)
        assertEquals(0, toasts.count("Accept action pressed"))

        app.launch()
        toasts.waitFor("Accept action pressed")
        Thread.sleep(SETTLE_MS)
        assertEquals(1, toasts.count("Accept action pressed"))
    }

    @Test
    fun n62_recreatedMainActivity_receivesEachActionOnce() {
        val old = resumedMainActivity()
        instrumentation.runOnMainSync { old.recreate() }
        waitUntil("MainActivity was not recreated") { resumedMainActivityOrNull()?.let { it !== old } == true }
        app.waitForText("notification.events", "ℹ️ #0 No events yet")

        shade.open()
        shade.clickButton("Interaction / Action Buttons", "Accept")
        shade.close()
        app.waitForText("notification.events", "ℹ️ #1 Action Accept (notificationId=1112)")
        Thread.sleep(SETTLE_MS)
        // One listener only: a second one would make #2 or a toast.
        assertEquals("ℹ️ #1 Action Accept (notificationId=1112)", app.text("notification.events"))
        assertEquals(0, toasts.count("Accept action pressed"))
    }

    private fun resumedMainActivity(): Activity {
        waitUntil("MainActivity is not resumed") { resumedMainActivityOrNull() != null }
        return resumedMainActivityOrNull()!!
    }

    private fun resumedMainActivityOrNull(): Activity? {
        var found: Activity? = null
        instrumentation.runOnMainSync {
            found = ActivityLifecycleMonitorRegistry.getInstance()
                .getActivitiesInStage(Stage.RESUMED)
                .firstOrNull { it is MainActivity }
        }
        return found
    }

    private fun stageOf(activity: Activity): Stage? {
        var stage: Stage? = null
        instrumentation.runOnMainSync {
            // The monitor forgets an activity once it is gone; treat that as destroyed.
            stage = runCatching { ActivityLifecycleMonitorRegistry.getInstance().getLifecycleStageOf(activity) }
                .getOrDefault(Stage.DESTROYED)
        }
        return stage
    }

    private fun waitUntil(message: String, condition: () -> Boolean) {
        val end = System.currentTimeMillis() + TIMEOUT_MS
        while (System.currentTimeMillis() < end) {
            if (condition()) return
            Thread.sleep(100)
        }
        assertTrue(message, condition())
    }

    private companion object {
        const val TIMEOUT_MS = 10_000L
        const val SETTLE_MS = 1_500L
    }
}
