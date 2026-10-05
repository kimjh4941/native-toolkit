package com.jonghyunkim.nativetoolkit.notification

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.nativetoolkit.testing.HelperActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.util.concurrent.LinkedBlockingQueue
import java.util.concurrent.TimeUnit

/**
 * IT-23 of the Kotlin API design (permission part): the 1.x NotificationPermissionHelper answers
 * as the stage 0c UI tests expected (NotificationHostStateUiTest n03 and n04 before the sample
 * moved to AndroidNotificationManager): deny gives false, allow gives true, and an already granted
 * permission gives true without a dialog.
 *
 * The runner revokes the permission before the class starts, as for
 * NotificationPermissionRequestTest. The methods run in name order. When the permission is
 * already granted at the start, the first two are skipped.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class ExistingPermissionHelperTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private var scenario: ActivityScenario<HelperActivity>? = null
    private val answers = LinkedBlockingQueue<Boolean>()

    @After
    fun tearDown() {
        scenario?.close()
    }

    private fun granted() = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED

    private fun request() {
        scenario = ActivityScenario.launch(HelperActivity::class.java)
        device.wait(Until.hasObject(By.text("HelperActivity")), 5_000)
        scenario!!.onActivity { it.helper.requestPermission { granted -> answers.add(granted) } }
    }

    // A click while the dialog is still animating in can be lost: click until the dialog is gone.
    private fun clickPermissionButton(id: String) {
        val selector = By.res("com.android.permissioncontroller", id)
        assertNotNull("the permission dialog did not show $id", device.wait(Until.findObject(selector), 30_000))
        repeat(3) {
            device.waitForIdle()
            device.findObject(selector)?.click()
            if (device.wait(Until.gone(selector), 5_000)) return
        }
        assertTrue("the permission dialog did not close after clicking $id", device.wait(Until.gone(selector), 5_000))
    }

    @Test
    fun a_deny_answersFalse() {
        assumeFalse("the permission is already granted", granted())
        request()
        clickPermissionButton("permission_deny_button")
        assertEquals(false, answers.poll(15, TimeUnit.SECONDS))
        scenario!!.onActivity { assertFalse(it.helper.hasPermission()) }
    }

    @Test
    fun b_allow_answersTrue() {
        assumeFalse("the permission is already granted", granted())
        request()
        clickPermissionButton("permission_allow_button")
        assertEquals(true, answers.poll(15, TimeUnit.SECONDS))
        scenario!!.onActivity { assertTrue(it.helper.hasPermission()) }
    }

    @Test
    fun c_alreadyGranted_answersTrueWithoutADialog() {
        assumeFalse("the permission is not granted", !granted())
        request()
        assertEquals(true, answers.poll(5, TimeUnit.SECONDS))
        assertFalse(device.hasObject(By.res("com.android.permissioncontroller", "permission_allow_button")))
    }
}
