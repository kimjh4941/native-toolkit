package com.jonghyunkim.nativetoolkit.notification

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason
import com.jonghyunkim.nativetoolkit.notification.application.usecase.RequestNotificationPermissionUseCase
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult
import com.jonghyunkim.nativetoolkit.notification.presentation.permission.FragmentPermissionRequester
import com.jonghyunkim.nativetoolkit.testing.PlainActivity
import com.jonghyunkim.nativetoolkit.testing.TestFragmentActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.FixMethodOrder
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.MethodSorters
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * IT-07 of the Kotlin API design: the notification permission request without an Activity.
 *
 * Revoking the permission kills the process, so the runner revokes it before the class starts
 * (`pm revoke` and `pm clear-permission-flags ... user-set user-fixed`). The methods run in name
 * order: deny, background, allow on the host, already granted. When the permission is already
 * granted at the start, the first three are skipped.
 */
@RunWith(AndroidJUnit4::class)
@FixMethodOrder(MethodSorters.NAME_ASCENDING)
class NotificationPermissionRequestTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val device = UiDevice.getInstance(instrumentation)
    private val request = RequestNotificationPermissionUseCase(FragmentPermissionRequester.get(context))
    private var scenario: ActivityScenario<out Activity>? = null

    private class Capture {
        val latch = CountDownLatch(1)
        val calls = AtomicInteger()
        @Volatile var result: PermissionRequestResult? = null
        @Volatile var onMain = false
        val callback: (PermissionRequestResult) -> Unit = {
            result = it
            onMain = Looper.myLooper() == Looper.getMainLooper()
            calls.incrementAndGet()
            latch.countDown()
        }

        fun await(): PermissionRequestResult {
            assertTrue("no result within 15 s", latch.await(15, TimeUnit.SECONDS))
            Thread.sleep(300)
            assertEquals("completed more than once", 1, calls.get())
            assertTrue("completed off the main thread", onMain)
            return result!!
        }
    }

    @After
    fun tearDown() {
        // Restore the orientation first: closing or launching while a rotation is pending
        // recreates the next Activity under ActivityScenario.
        device.setOrientationNatural()
        device.waitForIdle()
        device.unfreezeRotation()
        scenario?.close()
    }

    private fun granted() = ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
        PackageManager.PERMISSION_GRANTED

    private fun launch(activity: Class<out Activity>) {
        device.waitForIdle()
        scenario = ActivityScenario.launch(activity)
        device.wait(Until.hasObject(By.text(activity.simpleName)), 5_000)
    }

    private fun permissionButton(id: String) =
        device.wait(Until.findObject(By.res("com.android.permissioncontroller", id)), 30_000).also {
            assertNotNull("the permission dialog did not show $id", it)
        }!!

    // A click while the dialog is still animating in can be lost on a slow emulator: click until
    // the dialog is gone.
    private fun clickPermissionButton(id: String) {
        val selector = By.res("com.android.permissioncontroller", id)
        permissionButton(id)
        repeat(3) {
            device.waitForIdle()
            device.findObject(selector)?.click()
            if (device.wait(Until.gone(selector), 5_000)) return
        }
        assertTrue("the permission dialog did not close after clicking $id", device.wait(Until.gone(selector), 5_000))
    }

    @Test
    fun a1_twoRequestsOnAFragmentActivity_shareOneDialog_acrossRotation_andAreDenied() {
        assumeFalse("the permission is already granted", granted())
        launch(TestFragmentActivity::class.java)
        val first = Capture()
        val second = Capture()
        request(first.callback)
        request(second.callback)
        permissionButton("permission_deny_button")
        device.setOrientationLeft()
        device.waitForIdle()
        clickPermissionButton("permission_deny_button")
        assertEquals(PermissionRequestResult.Denied, first.await())
        assertEquals(PermissionRequestResult.Denied, second.await())
    }

    @Test
    fun a2_inTheBackground_isNotForeground() {
        assumeFalse("the permission is already granted", granted())
        launch(PlainActivity::class.java)
        device.pressHome()
        device.waitForIdle()
        Thread.sleep(500)
        val capture = Capture()
        request(capture.callback)
        assertEquals(PermissionRequestResult.Failed(UiUnavailableReason.NOT_FOREGROUND), capture.await())
    }

    @Test
    fun b_onAPlainActivity_theHostShowsTheDialog_andAllowIsGranted() {
        assumeFalse("the permission is already granted", granted())
        launch(PlainActivity::class.java)
        val capture = Capture()
        request(capture.callback)
        clickPermissionButton("permission_allow_button")
        assertEquals(PermissionRequestResult.Granted, capture.await())
    }

    @Test
    fun c_alreadyGranted_isGrantedWithoutUi() {
        assumeFalse("the permission is not granted", !granted())
        val capture = Capture()
        request(capture.callback)
        assertEquals(PermissionRequestResult.Granted, capture.await())
    }
}
