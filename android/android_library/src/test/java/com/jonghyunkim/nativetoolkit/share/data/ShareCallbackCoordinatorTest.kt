package com.jonghyunkim.nativetoolkit.share.data

import com.jonghyunkim.nativetoolkit.share.data.repository.CallbackResult
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareCallbackCoordinator
import com.jonghyunkim.nativetoolkit.share.data.repository.ShareWaitMode
import com.jonghyunkim.nativetoolkit.share.domain.model.ShareSelection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

// UT-08 of the Kotlin API design: the share wait of 8.9.
class ShareCallbackCoordinatorTest {

    private val nonce = 77L
    private var receiverRegistrations = 0
    private var receiverFails = false
    private val selections = mutableListOf<ShareSelection>()
    private val coordinator = ShareCallbackCoordinator(
        nonce = nonce,
        ensureReceiver = {
            if (receiverFails) throw IllegalStateException("register")
            receiverRegistrations++
        },
        emitSelection = { selections += it }
    )

    private class Calls {
        val selected = mutableListOf<String?>()
        var finished = 0
        val mode = ShareWaitMode.Callback({ selected += it }, { finished++ })
    }

    private val selected = CallbackResult.Selected("com.example.app")

    @Test
    fun tokensStartAtOne_andTheReceiverIsRegisteredOnce() {
        assertEquals(1L, coordinator.register(ShareWaitMode.Event))
        assertEquals(2L, coordinator.register(ShareWaitMode.Event))
        assertEquals(1, receiverRegistrations)
    }

    @Test
    fun receiverRegistrationFails_registerThrows_andTheNextOneRetries() {
        receiverFails = true
        try {
            coordinator.register(ShareWaitMode.Event)
            fail("expected an exception")
        } catch (_: IllegalStateException) {
        }
        receiverFails = false
        coordinator.register(ShareWaitMode.Event)
        assertEquals(1, receiverRegistrations)
    }

    @Test
    fun callback_selected_callsOnSelectedThenOnFinishedOnce() {
        val calls = Calls()
        val token = coordinator.register(calls.mode)
        coordinator.deliver(nonce, token, selected)
        coordinator.deliver(nonce, token, selected)
        assertEquals(listOf<String?>("com.example.app"), calls.selected)
        assertEquals(1, calls.finished)
    }

    @Test
    fun callback_ignored_callsOnlyOnFinishedOnce() {
        val calls = Calls()
        val token = coordinator.register(calls.mode)
        coordinator.deliver(nonce, token, CallbackResult.Ignored)
        assertTrue(calls.selected.isEmpty())
        assertEquals(1, calls.finished)
    }

    @Test
    fun event_selected_emitsWithTheToken_andIgnoredEmitsNothing() {
        val first = coordinator.register(ShareWaitMode.Event)
        coordinator.deliver(nonce, first, CallbackResult.Ignored)
        val second = coordinator.register(ShareWaitMode.Event)
        coordinator.deliver(nonce, second, CallbackResult.Selected(null))
        assertEquals(listOf(ShareSelection(second, null)), selections)
    }

    @Test
    fun anOlderToken_isDropped_andTheNewWaitStays() {
        val old = Calls()
        val new = Calls()
        val oldToken = coordinator.register(old.mode)
        val newToken = coordinator.register(new.mode)
        coordinator.deliver(nonce, oldToken, selected)
        assertTrue(old.selected.isEmpty())
        assertEquals(0, old.finished)
        coordinator.deliver(nonce, newToken, selected)
        assertEquals(1, new.finished)
    }

    @Test
    fun anOlderProcessNonce_isDropped() {
        val calls = Calls()
        val token = coordinator.register(calls.mode)
        coordinator.deliver(nonce + 1, token, selected)
        assertEquals(0, calls.finished)
        coordinator.deliver(nonce, token, selected)
        assertEquals(1, calls.finished)
    }

    @Test
    fun cancelWithAnOlderToken_keepsTheCurrentWait() {
        val calls = Calls()
        val old = coordinator.register(ShareWaitMode.Event)
        val token = coordinator.register(calls.mode)
        coordinator.cancel(old)
        coordinator.cancel(Long.MAX_VALUE)
        coordinator.deliver(nonce, token, selected)
        assertEquals(1, calls.finished)
    }

    @Test
    fun cancelWithTheToken_andCancelAll_dropTheWait() {
        val first = Calls()
        val token = coordinator.register(first.mode)
        coordinator.cancel(token)
        coordinator.deliver(nonce, token, selected)
        assertEquals(0, first.finished)

        val second = Calls()
        val secondToken = coordinator.register(second.mode)
        coordinator.cancel()
        coordinator.deliver(nonce, secondToken, selected)
        assertEquals(0, second.finished)
    }

    @Test
    fun cancelAndRegisterFromInsideTheCallback_doNotBlock() {
        val nextToken = AtomicReference<Long?>(null)
        val finishedInsideTheCallback = AtomicReference<Boolean?>(null)
        val done = CountDownLatch(1)
        // From another thread: the lock is reentrant, so a call on the callback's own thread would
        // pass even if the callback ran inside the lock.
        val mode = ShareWaitMode.Callback(
            onSelected = {
                val other = Thread {
                    coordinator.cancel()
                    nextToken.set(coordinator.register(ShareWaitMode.Event))
                }
                other.start()
                other.join(2_000)
                // Recorded before the callback returns: a callback inside the lock would block the
                // other thread until after this point.
                finishedInsideTheCallback.set(!other.isAlive && nextToken.get() != null)
            },
            onFinished = { done.countDown() }
        )
        val token = coordinator.register(mode)
        val thread = Thread { coordinator.deliver(nonce, token, selected) }.apply { start() }
        assertTrue("the callback blocked", done.await(5, TimeUnit.SECONDS))
        thread.join(5_000)
        assertEquals("register from another thread blocked inside the callback", true, finishedInsideTheCallback.get())
        // The wait registered inside the callback is the current one.
        coordinator.deliver(nonce, nextToken.get()!!, selected)
        assertEquals(listOf(ShareSelection(nextToken.get()!!, "com.example.app")), selections)
    }

    @Test
    fun onSelectedThrows_onFinishedRunsOnce_andTheExceptionPropagates() {
        val finished = AtomicInteger(0)
        val token = coordinator.register(
            ShareWaitMode.Callback({ throw IllegalArgumentException("boom") }, { finished.incrementAndGet() })
        )
        try {
            coordinator.deliver(nonce, token, selected)
            fail("expected the callback's exception")
        } catch (e: IllegalArgumentException) {
            assertEquals("boom", e.message)
        }
        assertEquals(1, finished.get())
        coordinator.deliver(nonce, token, selected)
        assertEquals(1, finished.get())
    }

    @Test
    fun concurrentRegisterAndCancel_doesNotThrow() {
        val errors = AtomicReference<Throwable?>(null)
        val latch = CountDownLatch(2)
        val registerThread = Thread {
            runCatching { repeat(50) { coordinator.register(ShareWaitMode.Event) } }.exceptionOrNull()?.let(errors::set)
            latch.countDown()
        }
        val cancelThread = Thread {
            runCatching { repeat(50) { coordinator.cancel() } }.exceptionOrNull()?.let(errors::set)
            latch.countDown()
        }
        registerThread.start()
        cancelThread.start()
        assertTrue(latch.await(5, TimeUnit.SECONDS))
        assertNull(errors.get())
    }
}
