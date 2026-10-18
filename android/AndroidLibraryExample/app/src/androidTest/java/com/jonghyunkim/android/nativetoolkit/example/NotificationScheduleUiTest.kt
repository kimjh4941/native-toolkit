package com.jonghyunkim.android.nativetoolkit.example

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNotification
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import com.jonghyunkim.android.nativetoolkit.example.infra.bigText
import com.jonghyunkim.android.nativetoolkit.example.infra.bigTitle
import com.jonghyunkim.android.nativetoolkit.example.infra.text
import com.jonghyunkim.android.nativetoolkit.example.infra.title
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** The sample's 15-second schedule (6.3 N-51 to N-53, U-3). */
@CategoryNotification
@RunWith(AndroidJUnit4::class)
class NotificationScheduleUiTest : SampleUiTest() {

    @Before
    fun openScreen() {
        app.open("notification")
    }

    @Test
    fun n51_scheduleFiresAfter15Seconds() {
        val scheduledAt = schedule()
        notifications.assertAbsentFor(1010, remainingUntil(scheduledAt + 10_000))
        val sbn = notifications.waitFor(1010, remainingUntil(scheduledAt + 40_000))
        assertEquals("Native Toolkit", sbn.title)
        assertEquals("Scheduled notification sample", sbn.text)
        assertEquals("Scheduled BigText", sbn.bigTitle)
        assertEquals("This scheduled notification was queued from Native Toolkit Example.", sbn.bigText)
        assertEquals("alarm", sbn.notification.category)
        assertEquals("native_toolkit_schedule_high", sbn.notification.channelId)
        assertEquals(4, notifications.channel("native_toolkit_schedule_high")!!.importance)
        // The library reports the shown schedule to the screen (sample app design 4.2).
        app.waitForText("notification.events", "ℹ️ #1 Scheduled notification shown (notificationId=1010)")
        app.click("notification.checkScheduleIsScheduled")
        app.waitForStatus("notification", "ℹ️ Schedule Notification is currently not scheduled. (isScheduled=false)")
    }

    @Test
    fun n52_checkWhileScheduled() {
        schedule()
        app.click("notification.checkScheduleIsScheduled")
        app.waitForStatus("notification", "ℹ️ Schedule Notification is currently scheduled. (isScheduled=true)")
    }

    @Test
    fun n53_deleteBeforeItFires() {
        val scheduledAt = schedule()
        app.click("notification.deleteScheduleNotification")
        app.waitForStatus(
            "notification",
            "🗑️ Deleted Schedule Notification. Cleared both scheduled and active notifications. (isScheduled=false)"
        )
        notifications.assertAbsentFor(1010, remainingUntil(scheduledAt + 25_000))
    }

    /** Presses the schedule button and returns the uptime at which it was pressed. */
    private fun schedule(): Long {
        val at = SystemClock.elapsedRealtime()
        app.click("notification.scheduleNotification15Sec")
        app.waitForStatus("notification", "✅ Scheduled a high-priority notification for 15 seconds later. (isScheduled=true)")
        return at
    }

    private fun remainingUntil(uptime: Long): Long = (uptime - SystemClock.elapsedRealtime()).coerceAtLeast(0)
}
