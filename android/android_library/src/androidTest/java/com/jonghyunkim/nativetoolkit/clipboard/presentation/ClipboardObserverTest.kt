package com.jonghyunkim.nativetoolkit.clipboard.presentation

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.test.ext.junit.rules.ActivityScenarioRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.testing.FocusActivity
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

// IT-17 of the Kotlin API design (8.10): the one clipboard observation of the process, its
// events and several listeners.
@RunWith(AndroidJUnit4::class)
class ClipboardObserverTest {

    /** Keeps an activity of this app in front: only the focused app can use the clipboard (Android 10+). */
    @get:Rule
    val focus = ActivityScenarioRule(FocusActivity::class.java)

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext
    private val clipboard = context.getSystemService(ClipboardManager::class.java)
    private val registrations = mutableListOf<EventHub.Registration>()

    @After
    fun tearDown() {
        instrumentation.runOnMainSync {
            registrations.forEach { it.remove() }
            ClipboardObserver.stop()
        }
    }

    private fun main(block: () -> Unit) = instrumentation.runOnMainSync(block)

    private fun listen(counter: AtomicInteger, latch: CountDownLatch? = null) = main {
        registrations += ClipboardEvents.changes.addListener { _, _ ->
            counter.incrementAndGet()
            latch?.countDown()
        }
    }

    private fun copy(text: String) = main { clipboard.setPrimaryClip(ClipData.newPlainText("it17", text)) }

    @Test
    fun startTwice_isOneObservation_andEveryListenerGetsOneEventPerPlatformNotification() {
        // The platform can notify more than once per copy (twice on API 35 and 36), so compare
        // against a listener registered directly with the platform.
        val platform = AtomicInteger()
        val reference = ClipboardManager.OnPrimaryClipChangedListener { platform.incrementAndGet() }
        main { clipboard.addPrimaryClipChangedListener(reference) }
        try {
            val first = AtomicInteger()
            val second = AtomicInteger()
            listen(first)
            listen(second)
            main {
                ClipboardObserver.start(context)
                ClipboardObserver.start(context)
                assertTrue(ClipboardObserver.isObserving())
            }
            copy("one")
            val deadline = System.currentTimeMillis() + 5_000
            while (platform.get() == 0 && System.currentTimeMillis() < deadline) Thread.sleep(50)
            Thread.sleep(1_000)
            instrumentation.waitForIdleSync()
            assertTrue(platform.get() > 0)
            assertEquals(platform.get(), first.get())
            assertEquals(platform.get(), second.get())
        } finally {
            main { clipboard.removePrimaryClipChangedListener(reference) }
        }
    }

    @Test
    fun stop_endsTheEvents_andStopTwiceIsANoOp() {
        val count = AtomicInteger()
        listen(count)
        main {
            ClipboardObserver.start(context)
            ClipboardObserver.stop()
            ClipboardObserver.stop()
            assertFalse(ClipboardObserver.isObserving())
        }
        copy("after stop")
        Thread.sleep(1_000)
        instrumentation.waitForIdleSync()
        assertEquals(0, count.get())
    }

    @Test
    fun aRemovedListener_getsNothing_whileTheOthersDo() {
        val removed = AtomicInteger()
        val kept = AtomicInteger()
        val latch = CountDownLatch(1)
        listen(removed)
        listen(kept, latch)
        main {
            registrations.first().remove()
            ClipboardObserver.start(context)
        }
        copy("two")
        assertTrue(latch.await(5, TimeUnit.SECONDS))
        assertEquals(0, removed.get())
    }

    @Test
    fun callsOffTheMainThread_throw() {
        for (call in listOf<() -> Unit>({ ClipboardObserver.start(context) }, { ClipboardObserver.stop() }, { ClipboardObserver.isObserving() })) {
            val error = runCatching { call() }.exceptionOrNull()
            assertTrue("expected IllegalStateException, got $error", error is IllegalStateException)
        }
    }
}
