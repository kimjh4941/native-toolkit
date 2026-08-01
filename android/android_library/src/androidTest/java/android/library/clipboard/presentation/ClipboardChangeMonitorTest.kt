package android.library.clipboard.presentation

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.core.content.ContextCompat
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Instrumented tests for [ClipboardChangeMonitor] against the real system ClipboardManager.
 *
 * Verifies single-listener ownership, duplicate-start no-op, and leak-free stop.
 */
@RunWith(AndroidJUnit4::class)
class ClipboardChangeMonitorTest {

    private lateinit var appContext: Context
    private lateinit var monitor: ClipboardChangeMonitor

    @Before
    fun setUp() {
        appContext = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext
        monitor = ClipboardChangeMonitor()
    }

    @After
    fun tearDown() {
        monitor.stop()
    }

    @Test
    fun start_thenCopy_firesOnChange() {
        val latch = CountDownLatch(1)
        monitor.start(appContext) { latch.countDown() }

        setPrimaryClip("trigger-1")

        assertTrue(latch.await(5, TimeUnit.SECONDS))
    }

    @Test
    fun start_marksObserving() {
        monitor.start(appContext) { }
        assertTrue(monitor.isObserving())
    }

    @Test
    fun start_calledTwice_doesNotRegisterDuplicateListener() {
        var firstCallbackCount = 0
        monitor.start(appContext) { firstCallbackCount++ }
        monitor.start(appContext) { firstCallbackCount++ }

        val latch = CountDownLatch(1)
        setPrimaryClip("trigger-2")
        // Give the system listener a moment to fire, then verify only one registration exists.
        Thread.sleep(200)

        // Only one listener should be registered: a single change fires at most once via this monitor.
        assertTrue(firstCallbackCount <= 1)
        latch.countDown()
    }

    @Test
    fun stop_afterStart_stopsFiring() {
        var callbackCount = 0
        monitor.start(appContext) { callbackCount++ }
        monitor.stop()

        setPrimaryClip("trigger-3")
        Thread.sleep(200)

        assertEquals(0, callbackCount)
    }

    @Test
    fun stop_marksNotObserving() {
        monitor.start(appContext) { }
        monitor.stop()
        assertFalse(monitor.isObserving())
    }

    @Test
    fun stop_withoutStart_isNoOp() {
        monitor.stop()
        assertFalse(monitor.isObserving())
    }

    private fun setPrimaryClip(text: String) {
        val clipboardManager = ContextCompat.getSystemService(appContext, ClipboardManager::class.java)!!
        clipboardManager.setPrimaryClip(ClipData.newPlainText("test", text))
    }
}
