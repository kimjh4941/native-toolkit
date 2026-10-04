package com.jonghyunkim.nativetoolkit.common

import com.jonghyunkim.nativetoolkit.common.runtime.InitializationState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections
import java.util.concurrent.CountDownLatch
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

// UT-01 of the Kotlin API design: the three-valued state and the "run when done" listeners.
class InitializationStateTest {

    private val posted = Collections.synchronizedList(mutableListOf<() -> Unit>())
    private val state = InitializationState { posted.add(it) }

    @Test
    fun firstCallerWins_othersSeeInProgress_thenDone() {
        assertEquals(InitializationState.Begin.WON, state.tryBegin())
        assertEquals(InitializationState.Begin.IN_PROGRESS, state.tryBegin())
        state.succeed()
        assertEquals(InitializationState.Begin.DONE, state.tryBegin())
        assertTrue(state.isDone())
    }

    @Test
    fun failReturnsToNotStarted_andTheNextCallerRetries() {
        assertEquals(InitializationState.Begin.WON, state.tryBegin())
        state.fail()
        assertFalse(state.isDone())
        assertEquals(InitializationState.Begin.WON, state.tryBegin())
    }

    @Test
    fun listenerAddedBeforeDone_isPostedOnceOnSuccess_andKeptAcrossFailure() {
        val calls = AtomicInteger()
        state.addListener { calls.incrementAndGet() }
        state.tryBegin()
        state.fail()
        assertTrue(posted.isEmpty())
        state.tryBegin()
        state.succeed()
        assertEquals(1, posted.size)
        posted.forEach { it() }
        assertEquals(1, calls.get())
        state.succeed()
        assertEquals(1, posted.size)
    }

    @Test
    fun listenerAddedAfterDone_isPostedImmediately() {
        state.tryBegin()
        state.succeed()
        state.addListener { }
        assertEquals(1, posted.size)
    }

    @Test
    fun addingAndSucceedingConcurrently_postsEveryListenerExactlyOnce() {
        repeat(200) {
            val local = Collections.synchronizedList(mutableListOf<() -> Unit>())
            val s = InitializationState { local.add(it) }
            s.tryBegin()
            val barrier = CyclicBarrier(2)
            val done = CountDownLatch(2)
            val listeners = 50
            Thread {
                barrier.await()
                repeat(listeners) { s.addListener { } }
                done.countDown()
            }.start()
            Thread {
                barrier.await()
                s.succeed()
                done.countDown()
            }.start()
            assertTrue(done.await(5, TimeUnit.SECONDS))
            assertEquals(listeners, local.size)
        }
    }
}
