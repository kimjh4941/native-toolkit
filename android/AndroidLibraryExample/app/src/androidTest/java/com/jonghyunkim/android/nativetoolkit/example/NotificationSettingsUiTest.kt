package com.jonghyunkim.android.nativetoolkit.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNotification
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/** Notification permission state and settings screens (6.3 N-01, N-06 to N-08). */
@CategoryNotification
@RunWith(AndroidJUnit4::class)
class NotificationSettingsUiTest : SampleUiTest() {

    @Before
    fun openScreen() {
        app.open("notification")
    }

    @Test
    fun n01_checkReportsGrantedState() {
        app.click("notification.checkNotificationPermission")
        val status = app.waitForStatus("notification", "permissionGranted=true")
        assertTrue(status, status.contains("notificationsEnabled=true"))
        assertTrue(status, status.contains("shouldShowRationale=false"))
        assertTrue(status, status.contains("exactAlarmAllowed=true"))
    }

    @Test
    fun n06_openNotificationSettings() {
        openSettingsAndReturn("notification.openNotificationSettings")
        app.waitForStatus("notification", "ℹ️ Opened notification settings or app details settings.")
    }

    @Test
    fun n07_openAppDetailsSettings() {
        openSettingsAndReturn("notification.openAppDetailsSettings")
        app.waitForStatus("notification", "ℹ️ Opened app details settings.")
    }

    @Test
    fun n08_openExactAlarmSettings() {
        openSettingsAndReturn("notification.openExactAlarmSettings")
        app.waitForStatus("notification", "ℹ️ Opened exact alarm settings or app details settings.")
    }

    /** Waits for a Settings window (3.3), then goes back to the sample. */
    private fun openSettingsAndReturn(tag: String) {
        app.click(tag)
        assertTrue("Settings did not open", device.wait(Until.hasObject(By.pkg(SETTINGS).depth(0)), 10_000))
        device.pressBack()
        assertTrue("did not return to the sample", device.wait(Until.hasObject(By.pkg(context.packageName).depth(0)), 10_000))
    }

    private companion object {
        const val SETTINGS = "com.android.settings"
    }
}
