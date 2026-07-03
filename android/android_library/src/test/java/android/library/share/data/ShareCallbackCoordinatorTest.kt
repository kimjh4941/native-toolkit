package android.library.share.data

import android.content.BroadcastReceiver
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.library.share.data.repository.ShareCallbackCoordinator
import android.library.share.data.repository.ShareCallbackReceiverRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference

class ShareCallbackCoordinatorTest {

    private lateinit var context: Context
    private lateinit var registry: FakeReceiverRegistry
    private lateinit var coordinator: ShareCallbackCoordinator

    @Before
    fun setUp() {
        context = object : ContextWrapper(null) {}
        registry = FakeReceiverRegistry()
        coordinator = ShareCallbackCoordinator(context, registry)
    }

    @Test
    fun cancelWithStaleToken_currentCallbackStillRunsOnce() {
        val received = AtomicInteger(0)
        coordinator.register("action", onSelected = { received.incrementAndGet() })
        coordinator.cancel(Long.MAX_VALUE)

        registry.deliverCurrent(context)

        assertEquals(1, received.get())
        assertNull(registry.current)
    }

    @Test
    fun cancel_thenQueuedBroadcast_doesNotInvokeCallback() {
        val called = AtomicInteger(0)
        coordinator.register("action", onSelected = { called.incrementAndGet() })
        val queuedReceiver = registry.current
        coordinator.cancel()

        queuedReceiver?.onReceive(context, Intent())

        assertEquals(0, called.get())
        assertNull(registry.current)
    }

    @Test
    fun registerTwice_staleReceiverIgnoredAndCurrentReceiverRunsOnce() {
        val firstCalled = AtomicInteger(0)
        val secondCalled = AtomicInteger(0)
        coordinator.register("action", onSelected = { firstCalled.incrementAndGet() })
        val staleReceiver = registry.current
        coordinator.register("action", onSelected = { secondCalled.incrementAndGet() })
        val currentReceiver = registry.current

        staleReceiver?.onReceive(context, Intent())
        currentReceiver?.onReceive(context, Intent())

        assertEquals(0, firstCalled.get())
        assertEquals(1, secondCalled.get())
        assertTrue(registry.unregistered.contains(staleReceiver))
    }

    @Test
    fun deliverSameReceiverTwice_invokesCallbackAndFinishedOnce() {
        val called = AtomicInteger(0)
        val finished = AtomicInteger(0)
        coordinator.register("action", { called.incrementAndGet() }, { finished.incrementAndGet() })
        val receiver = registry.current

        receiver?.onReceive(context, Intent())
        receiver?.onReceive(context, Intent())

        assertEquals(1, called.get())
        assertEquals(1, finished.get())
    }

    @Test
    fun concurrentRegisterAndCancel_doesNotThrow() {
        val errors = AtomicReference<Throwable?>(null)
        val latch = CountDownLatch(2)
        val registerThread = Thread {
            runCatching { repeat(50) { coordinator.register("action", onSelected = {}) } }
                .exceptionOrNull()?.let(errors::set)
            latch.countDown()
        }
        val cancelThread = Thread {
            runCatching { repeat(50) { coordinator.cancel() } }
                .exceptionOrNull()?.let(errors::set)
            latch.countDown()
        }

        registerThread.start()
        cancelThread.start()

        assertTrue(latch.await(5, TimeUnit.SECONDS))
        assertNull(errors.get())
    }

    private class FakeReceiverRegistry : ShareCallbackReceiverRegistry {
        var current: BroadcastReceiver? = null
        val unregistered = mutableListOf<BroadcastReceiver>()

        override fun register(receiver: BroadcastReceiver, action: String) {
            current = receiver
        }

        override fun unregister(receiver: BroadcastReceiver) {
            unregistered += receiver
            if (current === receiver) current = null
        }

        fun deliverCurrent(context: Context) {
            val receiver = current
            assertSame(current, receiver)
            receiver?.onReceive(context, Intent())
        }
    }
}
