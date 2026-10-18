package com.jonghyunkim.android.nativetoolkit.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNotification
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import com.jonghyunkim.android.nativetoolkit.example.infra.isForegroundService
import com.jonghyunkim.android.nativetoolkit.example.infra.template
import com.jonghyunkim.android.nativetoolkit.example.infra.text
import com.jonghyunkim.android.nativetoolkit.example.infra.title
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Call-style foreground service notifications (6.3 N-40 to N-47).
 *
 * The call buttons are labelled by the system, so they are pressed by position (3.9): the left one
 * declines or hangs up, the right one answers. CallStyle replaces the content title with the
 * caller's name, so the three samples are told apart by their text.
 */
@CategoryNotification
@RunWith(AndroidJUnit4::class)
class NotificationCallUiTest : SampleUiTest() {

    @Before
    fun openScreen() {
        app.open("notification")
    }

    @Test
    fun n40_incomingCall() {
        val sbn = start("incomingCall", "Incoming Call", INCOMING)
        assertEquals("Native Toolkit Support", sbn.title)
        assertEquals("call", sbn.notification.category)
        assertEquals(CALL_STYLE, sbn.template)
        assertEquals("native_toolkit_call_v3", sbn.notification.channelId)
        assertTrue("not a foreground service notification", sbn.isForegroundService)
    }

    @Test
    fun n41_incomingCallAnswer() {
        start("incomingCall", "Incoming Call", INCOMING)
        pressCallButton(RIGHT)
        notifications.waitFor(1200) { it.text == ONGOING }
    }

    @Test
    fun n42_incomingCallDecline() {
        start("incomingCall", "Incoming Call", INCOMING)
        pressCallButton(LEFT)
        notifications.waitGone(1200)
    }

    @Test
    fun n43_ongoingCallStopButton() {
        start("ongoingCall", "Ongoing Call", ONGOING)
        app.click("notification.stopCallForegroundService")
        app.waitForStatus("notification", "ℹ️ Requested call foreground service sample stop.")
        notifications.waitGone(1200)
    }

    @Test
    fun n44_ongoingCallHangUp() {
        start("ongoingCall", "Ongoing Call", ONGOING)
        pressCallButton(LEFT)
        notifications.waitGone(1200)
    }

    @Test
    fun n45_screeningCall() {
        start("screeningCall", "Screening Call", SCREENING)
    }

    @Test
    fun n46_screeningCallAnswer() {
        start("screeningCall", "Screening Call", SCREENING)
        pressCallButton(RIGHT)
        notifications.waitFor(1200) { it.text == ONGOING }
    }

    @Test
    fun n47_screeningCallHangUp() {
        start("screeningCall", "Screening Call", SCREENING)
        pressCallButton(LEFT)
        notifications.waitGone(1200)
    }

    /** Starts a call sample and waits for its notification, told apart by its text (3.9). */
    private fun start(button: String, label: String, text: String) =
        run {
            app.click("notification.$button")
            app.waitForStatus("notification", "✅ Started foreground service CallStyle sample for $label.")
            notifications.waitFor(1200) { it.text == text }
        }

    private fun pressCallButton(index: Int) {
        shade.open()
        shade.clickActionAt("Native Toolkit Support", index)
        shade.close()
    }

    private companion object {
        const val CALL_STYLE = "android.app.Notification\$CallStyle"
        const val INCOMING = "Native Toolkit Support is calling"
        const val ONGOING = "Native Toolkit Support connected"
        const val SCREENING = "Review this call request from Native Toolkit Support"
        const val LEFT = 0
        const val RIGHT = 1
    }
}
