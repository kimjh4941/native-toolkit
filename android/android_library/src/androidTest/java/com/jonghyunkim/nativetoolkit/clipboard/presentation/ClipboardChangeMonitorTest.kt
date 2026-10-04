package com.jonghyunkim.nativetoolkit.clipboard.presentation

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import com.jonghyunkim.nativetoolkit.testing.FocusActivity
import androidx.core.content.ContextCompat
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * Instrumented tests for [ClipboardChangeMonitor] against the real system ClipboardManager.
 *
 * Verifies single-listener ownership, duplicate-start no-op, and leak-free stop.
 */
@RunWith(AndroidJUnit4::class)
class ClipboardChangeMonitorTest {

    /** Keeps an activity of this app in front: only the focused app can use the clipboard (Android 10+). */
    @get:Rule
    val focus = ActivityScenarioRule(FocusActivity::class.java)

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
        // The platform can notify more than once per copy (twice on API 35 and 36), so compare
        // against a listener registered directly with the platform.
        val clipboardManager = ContextCompat.getSystemService(appContext, ClipboardManager::class.java)!!
        val platformCount = AtomicInteger()
        val reference = ClipboardManager.OnPrimaryClipChangedListener { platformCount.incrementAndGet() }
        clipboardManager.addPrimaryClipChangedListener(reference)
        try {
            val monitorCount = AtomicInteger()
            monitor.start(appContext) { monitorCount.incrementAndGet() }
            monitor.start(appContext) { monitorCount.incrementAndGet() }

            setPrimaryClip("trigger-2")
            // Wait for the first notification, then give any follow-up notifications time to arrive.
            val deadline = System.currentTimeMillis() + 5_000
            while (platformCount.get() == 0 && System.currentTimeMillis() < deadline) Thread.sleep(50)
            Thread.sleep(1_000)

            // Only one listener should be registered: the monitor fires once per platform notification.
            assertTrue(platformCount.get() > 0)
            assertEquals(platformCount.get(), monitorCount.get())
        } finally {
            clipboardManager.removePrimaryClipChangedListener(reference)
        }
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
