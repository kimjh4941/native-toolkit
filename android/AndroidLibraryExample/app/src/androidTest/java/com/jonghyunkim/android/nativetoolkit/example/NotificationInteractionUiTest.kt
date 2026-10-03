package com.jonghyunkim.android.nativetoolkit.example

import android.app.Notification
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNotification
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import com.jonghyunkim.android.nativetoolkit.example.infra.isGroupSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Notification interactions and grouping (6.3 N-20 to N-26; N-27 and N-28 are in [NotificationTapUiTest]). */
@CategoryNotification
@RunWith(AndroidJUnit4::class)
class NotificationInteractionUiTest : SampleUiTest() {

    @Before
    fun openScreen() {
        app.open("notification")
    }

    @Test
    fun n20_groupChildrenAndSummary() {
        app.click("notification.showGroupChild1")
        app.waitForStatus("notification", "✅ Displayed Group Child 1 notification.")
        app.click("notification.showGroupChild2")
        app.waitForStatus("notification", "✅ Displayed Group Child 2 notification.")
        app.click("notification.showGroupSummary")
        app.waitForStatus("notification", "✅ Displayed Group Summary notification.")
        for ((id, sortKey) in listOf(1101 to "01", 1102 to "02", 1100 to "00")) {
            val n = notifications.waitFor(id).notification
            assertEquals(GROUP, n.group)
            assertEquals(sortKey, n.sortKey)
            assertEquals(Notification.GROUP_ALERT_SUMMARY, n.groupAlertBehavior)
        }
        assertTrue("1100 is not the summary", notifications.waitFor(1100).isGroupSummary)
    }

    @Test
    fun n21_groupAlertBehavior() {
        app.click("notification.showGroupAlertBehavior")
        app.waitForStatus("notification", "✅ Displayed Group Alert Behavior sample. Verify summary-only alert behavior.")
        for (id in listOf(1101, 1102, 1100)) notifications.waitFor(id)
    }

    @Test
    fun n22_deleteIntentBySwipe() {
        app.click("notification.showDeleteIntentSample")
        app.waitForStatus("notification", "✅ Displayed DeleteIntent sample. Swipe the notification and verify the receiver callback.")
        notifications.waitFor(1110)
        shade.open()
        val visible = shade.findAny(listOf("Interaction / deleteIntent", "Native Toolkit Interaction"))
        shade.swipeAway(visible) { notifications.find(1110) == null }
        notifications.waitGone(1110)
        toasts.waitFor("DeleteIntent Sample dismissed (deleteIntent)")
        shade.close()
    }

    @Test
    fun n23_fullScreenIntentPayload() {
        app.click("notification.showFullScreenIntentSample")
        app.waitForStatus(
            "notification",
            "✅ Displayed FullScreenIntent reference sample. Depending on device state, it appears as heads-up or full-screen."
        )
        val n = notifications.waitFor(1111).notification
        assertEquals("alarm", n.category)
        assertEquals("native_toolkit_fullscreen_sample", n.channelId)
        assertEquals(4, notifications.channel("native_toolkit_fullscreen_sample")!!.importance)
        assertNotNull("fullScreenIntent is null", n.fullScreenIntent)
        // Heads-up versus full screen depends on the device state, so it is not checked (6.3 N-23).
        state.closeSystemWindows()
    }

    @Test
    fun n24_actionAcceptOnScreenThenDelete() {
        showActionButtons()
        shade.open()
        shade.clickButton("Interaction / Action Buttons", "Accept")
        shade.close()
        app.waitForStatus("notification", "✅ Action button pressed: Accept (id=accept, notificationId=1112)")
        notifications.waitFor(1112)
        app.click("notification.deleteActionButtonsSample")
        app.waitForStatus("notification", "🗑️ Deleted Action Buttons Sample notification.")
        notifications.waitGone(1112)
    }

    @Test
    fun n25_actionDeclineOnScreen() {
        showActionButtons()
        shade.open()
        shade.clickButton("Interaction / Action Buttons", "Decline")
        shade.close()
        app.waitForStatus("notification", "✅ Action button pressed: Decline (id=decline, notificationId=1112)")
    }

    @Test
    fun n26_actionAcceptOffScreenShowsToast() {
        showActionButtons()
        app.back("notification")
        shade.open()
        shade.clickButton("Interaction / Action Buttons", "Accept")
        toasts.waitFor("Accept action pressed")
        shade.close()
    }

    private fun showActionButtons() {
        app.click("notification.showActionButtonsSample")
        app.waitForStatus("notification", "✅ Displayed action button sample notification. Press Accept / Decline and check the status text.")
        notifications.waitFor(1112)
    }

    private companion object {
        const val GROUP = "native.toolkit.grouping.sample"
    }
}
