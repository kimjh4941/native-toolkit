package com.jonghyunkim.android.nativetoolkit.example

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.uiautomator.By
import androidx.test.uiautomator.Until
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNotification
import com.jonghyunkim.android.nativetoolkit.example.infra.ExternalLaunchUiTest
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Tapping a notification while the sample is in the background (6.3 N-27, N-28). The tap reaches
 * the `MainActivity` through `onNewIntent`, so this class drives the sample with UiAutomator.
 */
@CategoryNotification
@RunWith(AndroidJUnit4::class)
class NotificationTapUiTest : ExternalLaunchUiTest() {

    @Before
    fun openScreen() {
        app.open("notification")
    }

    @Test
    fun n27_tappingTheBodyBringsTheSampleBack() {
        app.click("notification.showDefaultStyle")
        app.waitForStatus("notification", "✅ Displayed Default style notification.")
        notifications.waitFor(1001)
        goHome()
        shade.open()
        shade.clickBody("Default style notification sample")
        assertTrue("the sample did not come back on its notification screen", device.wait(Until.hasObject(By.res("notification.back")), 10_000))
        notifications.waitGone(1001)
    }

    @Test
    fun n28_mediaActionBringsTheSampleBack() {
        app.click("notification.showMediaStyle")
        app.waitForStatus("notification", "✅ Displayed Media style notification.")
        notifications.waitFor(1006)
        goHome()
        shade.open()
        shade.clickButton("Native Toolkit Player", "Previous")
        assertTrue("the sample did not come back on its notification screen", device.wait(Until.hasObject(By.res("notification.back")), 10_000))
        notifications.waitFor(1006)
    }

    private fun goHome() {
        device.pressHome()
        device.wait(Until.gone(By.pkg(context.packageName).depth(0)), 5_000)
    }
}
