package com.jonghyunkim.android.nativetoolkit.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.ActiveNotifications.Companion.FOREGROUND_SERVICE_TIMEOUT_MS
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNotification
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import com.jonghyunkim.android.nativetoolkit.example.infra.bigText
import com.jonghyunkim.android.nativetoolkit.example.infra.bigTitle
import com.jonghyunkim.android.nativetoolkit.example.infra.isForegroundService
import com.jonghyunkim.android.nativetoolkit.example.infra.isIndeterminate
import com.jonghyunkim.android.nativetoolkit.example.infra.isOngoingEvent
import com.jonghyunkim.android.nativetoolkit.example.infra.progress
import com.jonghyunkim.android.nativetoolkit.example.infra.progressMax
import com.jonghyunkim.android.nativetoolkit.example.infra.text
import com.jonghyunkim.android.nativetoolkit.example.infra.title
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Progress notifications (6.3 N-30 to N-34). Each step waits for the previous value to appear,
 * because notification updates are rate-limited (3.2).
 */
@CategoryNotification
@RunWith(AndroidJUnit4::class)
class NotificationProgressUiTest : SampleUiTest() {

    @Before
    fun openScreen() {
        app.open("notification")
    }

    @Test
    fun n30_progress10To50To100() {
        app.click("notification.showProgress10")
        app.waitForStatus("notification", "✅ Displayed progress notification at 10%.")
        var sbn = notifications.waitFor(1009) { it.progress == 10 }
        assertEquals("Native Toolkit Download", sbn.title)
        assertEquals("Downloading sample asset... 10%", sbn.text)
        assertEquals(100, sbn.progressMax)
        assertTrue(sbn.isOngoingEvent)

        app.click("notification.showProgress50")
        app.waitForStatus("notification", "✅ Updated progress notification to 50%.")
        sbn = notifications.waitFor(1009) { it.progress == 50 }
        assertEquals("Downloading sample asset... 50%", sbn.text)
        assertTrue(sbn.isOngoingEvent)

        app.click("notification.showProgress100")
        app.waitForStatus("notification", "✅ Updated progress notification to 100%.")
        sbn = notifications.waitFor(1009) { it.progress == 100 }
        assertEquals("Download completed", sbn.text)
        assertFalse(sbn.isOngoingEvent)
    }

    @Test
    fun n31_indeterminateThenDelete() {
        app.click("notification.showIndeterminateProgress")
        app.waitForStatus("notification", "✅ Displayed indeterminate progress notification.")
        val sbn = notifications.waitFor(1009) { it.isIndeterminate }
        assertEquals("Native Toolkit Sync", sbn.title)
        assertEquals("Syncing sample data...", sbn.text)
        app.click("notification.deleteProgress")
        app.waitForStatus("notification", "🗑️ Deleted Progress notification.")
        notifications.waitGone(1009)
    }

    @Test
    fun n32_foregroundServiceProgressThenStop() {
        app.click("notification.startProgressFgs10")
        app.waitForStatus("notification", "✅ Started dataSync progress foreground service. A 10% notification is now shown.")
        val sbn = notifications.waitFor(1011, FOREGROUND_SERVICE_TIMEOUT_MS) { it.progress == 10 }
        assertEquals("Native Toolkit Background Sync", sbn.title)
        assertEquals("Running background sync... 10%", sbn.text)
        assertTrue("not a foreground service notification", sbn.isForegroundService)

        app.click("notification.updateProgressFgs50")
        app.waitForStatus("notification", "✅ Updated dataSync progress foreground service to 50%.")
        notifications.waitFor(1011) { it.progress == 50 }

        app.click("notification.updateProgressFgs90")
        app.waitForStatus("notification", "✅ Updated dataSync progress foreground service to 90%.")
        notifications.waitFor(1011) { it.progress == 90 }

        app.click("notification.stopProgressFgs")
        app.waitForStatus("notification", "ℹ️ Requested progress foreground service stop.")
        notifications.waitGone(1011)
    }

    @Test
    fun n33_n34_completeDowngradesAndStopKeepsTheNotification() {
        app.click("notification.startProgressFgs10")
        notifications.waitFor(1011, FOREGROUND_SERVICE_TIMEOUT_MS) { it.progress == 10 }

        app.click("notification.completeProgressFgs")
        app.waitForStatus("notification", "✅ Completed progress foreground service. It has been downgraded to a regular notification.")
        val sbn = notifications.waitFor(1011) { !it.isForegroundService && it.progress == 100 }
        assertEquals("Background sync completed", sbn.text)
        assertEquals("Background Sync Completed", sbn.bigTitle)
        assertEquals(
            "The background sync finished successfully. This notification was downgraded from a foreground service to a normal notification.",
            sbn.bigText
        )

        app.click("notification.stopProgressFgs")
        app.waitForStatus("notification", "ℹ️ Requested progress foreground service stop.")
        notifications.assertPresentFor(1011, 2_000)
    }
}
