package com.jonghyunkim.android.nativetoolkit.example

import androidx.compose.ui.test.onNodeWithText
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.jonghyunkim.android.nativetoolkit.example.infra.CategoryNavigation
import com.jonghyunkim.android.nativetoolkit.example.infra.SampleUiTest
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith

/** Menu and navigation (6.1 of the android-c-abi UI test design). */
@CategoryNavigation
@RunWith(AndroidJUnit4::class)
class NavigationUiTest : SampleUiTest() {

    @Test
    fun m01_eachScreenOpensAndBackButtonReturnsToMenu() {
        for ((screen, heading) in SCREENS) {
            app.open(screen)
            compose.onNodeWithText(heading).assertExists()
            app.back(screen)
            compose.onNodeWithText("Native Toolkit Example").assertExists()
        }
    }

    @Test
    fun m02_systemBackReturnsToMenu() {
        for ((screen, _) in SCREENS) {
            app.open(screen)
            device.pressBack()
            compose.waitUntil(5_000) { app.exists("menu.dialog") }
        }
    }

    @Test
    fun m03_dialogResultSurvivesLeavingTheScreen() {
        app.open("dialog")
        app.click("dialog.showDialog")
        dialogs.waitFor("Hello from Android")
        dialogs.positive().click()
        app.waitForStatus("dialog", "Result: onDialog - buttonText: OK, errorMessage: null")
        app.back("dialog")
        app.open("dialog")
        app.waitForStatus("dialog", "Result: onDialog - buttonText: OK, errorMessage: null")
    }

    @Test
    fun m04_statusResetsWhenTheScreenIsOpenedAgain() {
        app.open("notification")
        app.click("notification.checkNotificationPermission")
        app.waitForStatus("notification", "permissionGranted=")
        app.back("notification")
        app.open("notification")
        assertEquals(NOTIFICATION_INITIAL, app.status("notification"))
        app.back("notification")

        app.open("share")
        app.click("share.cancelPendingCallback")
        app.waitForStatus("share", "✅ cancelPendingCallback called")
        app.back("share")
        app.open("share")
        assertEquals(INITIAL, app.status("share"))
        app.back("share")

        app.open("clipboard")
        app.click("clipboard.hasClip")
        app.waitForStatus("clipboard", "✅ hasClip = ")
        app.back("clipboard")
        app.open("clipboard")
        assertEquals(INITIAL, app.status("clipboard"))
    }

    private companion object {
        val SCREENS = listOf(
            "dialog" to "Dialog Example",
            "notification" to "Notification Example",
            "share" to "Share Example",
            "clipboard" to "Clipboard Example"
        )
        const val INITIAL = "Result will be displayed here"
        const val NOTIFICATION_INITIAL = "Explore notification samples. Start by checking the current permission state."
    }
}
