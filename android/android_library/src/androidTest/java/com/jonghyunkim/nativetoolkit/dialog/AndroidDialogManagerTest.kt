package com.jonghyunkim.nativetoolkit.dialog

import android.app.Activity
import android.os.Looper
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.Until
import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.presentation.ForegroundActivityTracker
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogDomainError
import com.jonghyunkim.nativetoolkit.dialog.domain.error.DialogError
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogButton
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogRequest
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogResult
import com.jonghyunkim.nativetoolkit.dialog.domain.model.DialogValue
import com.jonghyunkim.nativetoolkit.dialog.AndroidDialogManager
import com.jonghyunkim.nativetoolkit.testing.PlainActivity
import com.jonghyunkim.nativetoolkit.testing.TestFragmentActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

// IT-03 to IT-06 of the Kotlin API design: dialogs through AndroidDialogManager.
@RunWith(AndroidJUnit4::class)
class AndroidDialogManagerTest {

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val manager = AndroidDialogManager.getInstance(instrumentation.targetContext)
    private var scenario: ActivityScenario<out Activity>? = null

    private class Capture {
        val latch = CountDownLatch(1)
        val calls = AtomicInteger()
        @Volatile var result: DialogResult? = null
        @Volatile var onMain = false

        val callback: (DialogResult) -> Unit = {
            result = it
            onMain = Looper.myLooper() == Looper.getMainLooper()
            calls.incrementAndGet()
            latch.countDown()
        }

        fun await(): DialogResult {
            assertTrue("no result within 10 s", latch.await(10, TimeUnit.SECONDS))
            // Give a second completion the chance to arrive, so exactly-once is checked.
            Thread.sleep(300)
            assertEquals("completed more than once", 1, calls.get())
            assertTrue("completed off the main thread", onMain)
            return result!!
        }
    }

    @Before
    fun setUp() {
        assertTrue(LibraryRuntime.isInitialized())
        device.unfreezeRotation()
        device.setOrientationNatural()
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

    private fun launch(activity: Class<out Activity>) {
        scenario = ActivityScenario.launch(activity)
        device.wait(Until.hasObject(By.text(activity.simpleName)), 5_000)
    }

    private fun waitText(text: String) =
        assertNotNull("'$text' did not appear", device.wait(Until.findObject(By.text(text)), 5_000))

    // Clicks a list item until it shows as checked: a click during the dialog's enter animation
    // can be lost.
    private fun selectItem(text: String) {
        repeat(3) {
            device.waitForIdle()
            device.findObject(By.text(text))?.click()
            if (device.wait(Until.hasObject(By.text(text).checked(true)), 2_000)) return
        }
        fail("'$text' did not become checked")
    }

    private fun currentActivity(): Activity? {
        var activity: Activity? = null
        instrumentation.runOnMainSync { activity = ForegroundActivityTracker.current() }
        return activity
    }

    private fun waitForegroundIs(type: Class<out Activity>) {
        val deadline = System.currentTimeMillis() + 5_000
        while (System.currentTimeMillis() < deadline) {
            if (type.isInstance(currentActivity())) return
            Thread.sleep(100)
        }
        fail("${type.simpleName} did not come back to the foreground (the host may still be open)")
    }

    // --- IT-03: FragmentActivity in the foreground ---

    @Test
    fun fragmentActivity_confirm_positiveButton() {
        launch(TestFragmentActivity::class.java)
        val capture = Capture()
        manager.show(DialogRequest.Confirm(title = "it03-confirm", message = "m"), capture.callback)
        waitText("Yes")
        device.findObject(By.text("Yes")).click()
        assertEquals(DialogResult.Button(DialogButton.POSITIVE, "Yes", DialogValue.None), capture.await())
    }

    @Test
    fun fragmentActivity_textInput_returnsTheText() {
        launch(TestFragmentActivity::class.java)
        val capture = Capture()
        manager.show(DialogRequest.TextInput(title = "it03-text", message = "m"), capture.callback)
        waitText("it03-text")
        device.findObject(By.clazz("android.widget.EditText")).text = "typed value"
        device.findObject(By.text("OK")).click()
        assertEquals(
            DialogResult.Button(DialogButton.POSITIVE, "OK", DialogValue.Text("typed value")),
            capture.await()
        )
    }

    @Test
    fun fragmentActivity_singleChoice_keepsTheSelectionAndTheResultAcrossRotation() {
        launch(TestFragmentActivity::class.java)
        val capture = Capture()
        manager.show(
            DialogRequest.SingleChoice(title = "it03-single", items = listOf("alpha", "beta", "gamma")),
            capture.callback
        )
        waitText("beta")
        selectItem("beta")
        device.setOrientationLeft()
        device.waitForIdle()
        waitText("it03-single")
        device.findObject(By.text("OK")).click()
        assertEquals(
            DialogResult.Button(DialogButton.POSITIVE, "OK", DialogValue.SingleChoice(1)),
            capture.await()
        )
    }

    @Test
    fun fragmentActivity_backKey_isDismissed() {
        launch(TestFragmentActivity::class.java)
        val capture = Capture()
        manager.show(DialogRequest.Alert(title = "it03-back", message = "m"), capture.callback)
        waitText("it03-back")
        device.pressBack()
        assertEquals(DialogResult.Dismissed, capture.await())
    }

    @Test
    fun fragmentActivity_cancel_closesTheDialog() {
        launch(TestFragmentActivity::class.java)
        val capture = Capture()
        val id = manager.show(DialogRequest.Alert(title = "it03-cancel", message = "m"), capture.callback)
        waitText("it03-cancel")
        manager.cancel(id)
        assertEquals(DialogResult.Canceled(CancelReason.REQUESTED), capture.await())
        assertTrue(device.wait(Until.gone(By.text("it03-cancel")), 5_000))
    }

    @Test
    fun invalidRequest_throwsAtOnce() {
        try {
            manager.show(DialogRequest.SingleChoice(title = "t", items = emptyList())) { }
            fail("expected IllegalArgumentException")
        } catch (expected: IllegalArgumentException) {
        }
    }

    // --- IT-04: a plain Activity in the foreground (the transparent host) ---

    @Test
    fun plainActivity_dialogShowsOnTheHost_andTheHostFinishes() {
        launch(PlainActivity::class.java)
        val capture = Capture()
        manager.show(DialogRequest.Alert(title = "it04-alert", message = "m"), capture.callback)
        waitText("it04-alert")
        device.findObject(By.text("OK")).click()
        assertEquals(DialogResult.Button(DialogButton.POSITIVE, "OK", DialogValue.None), capture.await())
        waitForegroundIs(PlainActivity::class.java)
    }

    @Test
    fun plainActivity_theFirstEndsRightAfterTheSecondArrives_theSecondStays() {
        launch(PlainActivity::class.java)
        val first = Capture()
        val second = Capture()
        val firstId = manager.show(DialogRequest.Alert(title = "it04-early", message = "m"), first.callback)
        waitText("it04-early")
        manager.show(DialogRequest.Confirm(title = "it04-late", message = "m", positiveText = "Late"), second.callback)
        waitText("Late")
        // Both dialogs are on the host; the first ends right after the second arrived.
        manager.cancel(firstId)
        assertEquals(DialogResult.Canceled(CancelReason.REQUESTED), first.await())
        Thread.sleep(1_000)
        assertNotNull("the second dialog closed with the first", device.findObject(By.text("Late")))
        device.findObject(By.text("Late")).click()
        assertEquals(DialogResult.Button(DialogButton.POSITIVE, "Late", DialogValue.None), second.await())
        waitForegroundIs(PlainActivity::class.java)
    }

    @Test
    fun plainActivity_twoRequestsShareOneHost_andBothComplete() {
        launch(PlainActivity::class.java)
        val first = Capture()
        val second = Capture()
        manager.show(DialogRequest.Confirm(title = "it04-first", message = "m", positiveText = "First"), first.callback)
        manager.show(DialogRequest.Confirm(title = "it04-second", message = "m", positiveText = "Second"), second.callback)
        waitText("Second")
        device.findObject(By.text("Second")).click()
        assertEquals(DialogResult.Button(DialogButton.POSITIVE, "Second", DialogValue.None), second.await())
        waitText("First")
        device.findObject(By.text("First")).click()
        assertEquals(DialogResult.Button(DialogButton.POSITIVE, "First", DialogValue.None), first.await())
        waitForegroundIs(PlainActivity::class.java)
    }

    @Test
    fun plainActivity_cancelWhileTheHostStarts_neverShowsTheDialog() {
        launch(PlainActivity::class.java)
        val capture = Capture()
        val id = manager.show(DialogRequest.Alert(title = "it05-early-cancel", message = "m"), capture.callback)
        manager.cancel(id)
        assertEquals(DialogResult.Canceled(CancelReason.REQUESTED), capture.await())
        assertNull(device.wait(Until.findObject(By.text("it05-early-cancel")), 2_000))
        waitForegroundIs(PlainActivity::class.java)
    }

    // --- IT-05: not in the foreground ---

    @Test
    fun background_isNotForeground() {
        launch(PlainActivity::class.java)
        device.pressHome()
        device.waitForIdle()
        Thread.sleep(500)
        val capture = Capture()
        manager.show(DialogRequest.Alert(title = "it05-background", message = "m"), capture.callback)
        assertEquals(DialogResult.Failed(DialogError.NOT_FOREGROUND), capture.await())
    }

    // --- IT-06: the host is destroyed ---

    @Test
    fun hostFinishedFromOutside_isCanceledHostDestroyedOnce() {
        launch(PlainActivity::class.java)
        val capture = Capture()
        manager.show(DialogRequest.Alert(title = "it06-destroyed", message = "m"), capture.callback)
        waitText("it06-destroyed")
        instrumentation.runOnMainSync { ForegroundActivityTracker.current()?.finish() }
        assertEquals(DialogResult.Canceled(CancelReason.HOST_DESTROYED), capture.await())
    }

    // --- IT-03: the suspend version ---

    @Test
    fun suspend_hostDestroyed_throwsCanceled() {
        launch(PlainActivity::class.java)
        val shown = CoroutineScope(Dispatchers.Default).async { manager.show(DialogRequest.Alert(title = "it03-suspend-destroyed", message = "m")) }
        waitText("it03-suspend-destroyed")
        instrumentation.runOnMainSync { ForegroundActivityTracker.current()?.finish() }
        val error = runCatching { runBlocking { withTimeout(10_000) { shown.await() } } }.exceptionOrNull()
        assertEquals(DialogDomainError.Canceled(CancelReason.HOST_DESTROYED), error)
    }

    @Test
    fun suspend_answer_cancelByTheCoroutine_andUnavailable() {
        launch(TestFragmentActivity::class.java)
        val scope = CoroutineScope(Dispatchers.Default)
        val answer = scope.async { manager.show(DialogRequest.Confirm(title = "it03-suspend", message = "m")) }
        waitText("Yes")
        device.findObject(By.text("Yes")).click()
        assertEquals(DialogResult.Button(DialogButton.POSITIVE, "Yes", DialogValue.None), runBlocking { withTimeout(10_000) { answer.await() } })

        // Cancelling the coroutine closes the dialog.
        val canceled = scope.async { manager.show(DialogRequest.Alert(title = "it03-suspend-cancel", message = "m")) }
        waitText("it03-suspend-cancel")
        canceled.cancel()
        assertTrue("the dialog stayed", device.wait(Until.gone(By.text("it03-suspend-cancel")), 5_000))
        assertTrue(runCatching { runBlocking { canceled.await() } }.exceptionOrNull() is CancellationException)

        // With no foreground Activity the suspend version throws the domain error.
        device.pressHome()
        device.waitForIdle()
        Thread.sleep(500)
        val error = runCatching { runBlocking { withTimeout(10_000) { manager.show(DialogRequest.Alert(title = "it03-suspend-bg", message = "m")) } } }.exceptionOrNull()
        assertEquals(DialogDomainError.Unavailable(DialogError.NOT_FOREGROUND), error)
    }
}
