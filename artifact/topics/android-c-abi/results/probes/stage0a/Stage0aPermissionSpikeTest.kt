package com.jonghyunkim.android.nativetoolkit.example.spike

import android.util.Log
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.android.nativetoolkit.example.MainActivity
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Throwaway spike for stage 0a (not committed): the POST_NOTIFICATIONS dialog.
 *
 * Revoking the permission kills the app process, so the host revokes it before this runs:
 * `pm revoke <pkg> android.permission.POST_NOTIFICATIONS` and
 * `pm clear-permission-flags <pkg> android.permission.POST_NOTIFICATIONS user-set user-fixed`.
 */
@RunWith(AndroidJUnit4::class)
class Stage0aPermissionSpikeTest {

    @get:Rule
    val compose = createAndroidComposeRule<MainActivity>()

    private val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())

    @Test
    fun spike09_permissionDialogAllow() {
        Log.d(TAG, "[spike09_permissionDialogAllow]")
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("Notification Example"))
        compose.onNodeWithText("Notification Example").performClick()
        compose.onNode(hasScrollAction()).performScrollToNode(hasText("Request Notification Permission"))
        compose.onNodeWithText("Request Notification Permission").performClick()
        val allow = device.wait(
            Until.findObject(By.res("com.android.permissioncontroller", "permission_allow_button")),
            10_000L
        )
        Log.d(TAG, "[spike09] allow button=${allow != null} text=${allow?.text}")
        assertNotNull("permission dialog allow button", allow)
        allow.click()
        compose.waitUntil(timeoutMillis = 10_000L) {
            compose.onAllNodesWithText("Notification permission granted", substring = true)
                .fetchSemanticsNodes().isNotEmpty()
        }
    }

    private companion object {
        const val TAG = "Spike0a"
    }
}
