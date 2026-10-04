package com.jonghyunkim.android.nativetoolkit.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.runner.lifecycle.Stage
import androidx.test.runner.lifecycle.ActivityLifecycleMonitorRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryHostState
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Cases whose device state the host prepares, one test at a time (6.3, U-5). Each method names the
 * state it expects; scripts/test_android.sh sets that state before running the method:
 *
 * - `exactAlarmDenied`: notification permission granted, `SCHEDULE_EXACT_ALARM` reset to default
 * - `permissionRevoked`: `POST_NOTIFICATIONS` revoked and its user-set / user-fixed flags cleared
 *
 * The tests never change these states themselves, because doing so kills the app process.
 */
@CategoryHostState
@RunWith(AndroidJUnit4::class)
class NotificationHostStateUiTest : SampleUiTest() {

    override val grantPermissions = false

    @Before
    fun openScreen() {
        app.open("notification")
    }

    @Test
    fun n02_exactAlarmDenied_checkReportsIt() {
        app.click("notification.checkNotificationPermission")
        app.waitForStatus("notification", "exactAlarmAllowed=false")
    }

    @Test
    fun n50_exactAlarmDenied_scheduleFails() {
        app.click("notification.scheduleNotification15Sec")
        app.waitForStatus("notification", "❌ Exact alarms are not allowed. Use 'Open Exact Alarm Settings' above to enable them.")
    }

    @Test
    fun n03_permissionRevoked_requestAndAllow() {
        app.click("notification.requestNotificationPermission")
        permissionButton("permission_allow_button").click()
        app.waitForStatus("notification", "✅ Notification permission granted.")
    }

    @Test
    fun n04_permissionRevoked_requestAndDenyThenCheck() {
        app.click("notification.requestNotificationPermission")
        permissionButton("permission_deny_button").click()
        app.waitForStatus("notification", "❌ Notification permission is not granted. Use 'Open Notification Settings' above to enable it.")
        app.click("notification.checkNotificationPermission")
        val status = app.waitForStatus("notification", "permissionGranted=false")
        assertTrue(status, status.contains("shouldShowRationale=true"))
    }

    @Test
    fun n10_permissionRevoked_requestCoroutineAndAllow() {
        app.click("notification.requestNotificationPermissionCoroutine")
        permissionButton("permission_allow_button").click()
        app.waitForStatus("notification", "✅ Notification permission granted (coroutine).")
    }

    @Test
    fun n11_permissionRevoked_requestCoroutineAndDeny() {
        app.click("notification.requestNotificationPermissionCoroutine")
        permissionButton("permission_deny_button").click()
        app.waitForStatus("notification", "❌ Notification permission is not granted (coroutine).")
    }

    @Test
    fun n12_permissionRevoked_requestSurvivesTheRecreation() {
        app.click("notification.requestNotificationPermission")
        permissionButton("permission_allow_button")
        // The permission dialog keeps MainActivity paused, and ActivityScenario.recreate waits for
        // RESUMED, so recreate the activity itself.
        instrumentation.runOnMainSync {
            ActivityLifecycleMonitorRegistry.getInstance().getActivitiesInStage(Stage.PAUSED)
                .first { it is MainActivity }
                .recreate()
        }
        permissionButton("permission_allow_button").click()
        // The answer goes to the notification screen of the new MainActivity (review I-X3). The
        // Compose rule still points at the old activity, so read the status with UiAutomator, inside
        // waitUntil: the rule drives the frames, and nothing is redrawn while the test only waits.
        val expected = "✅ Notification permission granted."
        compose.waitUntil(10_000) {
            device.findObject(By.res("notification.status"))?.text?.contains(expected) == true
        }
    }

    @Test
    fun n05_permissionRevoked_showFails() {
        app.click("notification.showDefaultStyle")
        app.waitForStatus("notification", "❌ Unable to show notifications. Check permissions or notification settings.")
        assertEquals(null, notifications.find(1001))
    }

    @Test
    fun n09_permissionRevoked_foregroundServicesAndScheduleFail() {
        app.click("notification.startProgressFgs10")
        app.waitForStatus("notification", "❌ Unable to show the progress foreground service. Check permissions or notification settings.")
        app.click("notification.incomingCall")
        app.waitForStatus("notification", "❌ Unable to show call notifications. Check permissions or notification settings.")
        app.click("notification.scheduleNotification15Sec")
        app.waitForStatus("notification", "❌ Unable to schedule notifications. Check permissions or notification settings.")
    }

    private fun permissionButton(id: String) =
        device.wait(Until.findObject(By.res(PERMISSION_CONTROLLER, id)), 10_000).also {
            assertNotNull("the permission dialog did not show $id", it)
        }!!

    private companion object {
        const val PERMISSION_CONTROLLER = "com.android.permissioncontroller"
    }
}
