package com.jonghyunkim.nativetoolkit.common

import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason
import com.jonghyunkim.nativetoolkit.common.presentation.UiHostClient
import com.jonghyunkim.nativetoolkit.common.presentation.UiHostCore
import com.jonghyunkim.nativetoolkit.common.presentation.UiHostEnvironment
import com.jonghyunkim.nativetoolkit.common.presentation.UiRequestGate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// UT-03 of the Kotlin API design: the request gate and the host record of 8.3, in both orders.
class UiHostCoreTest {

    private class FakeEnv : UiHostEnvironment<String, String> {
        var initialized = true
        var host: String? = null
        var activity: String? = "plain-activity"
        var savedFragmentActivity = false
        var launchThrows = false
        val launched = mutableListOf<Long>()
        val delayed = mutableListOf<Runnable>()

        override fun isInitialized() = initialized
        override fun currentActivity() = activity
        override fun currentHost() = host
        override fun isSavedFragmentActivity(activity: String) = savedFragmentActivity
        override fun launchHost(from: String, token: Long) {
            if (launchThrows) throw IllegalStateException("blocked")
            launched += token
        }
        override fun postDelayed(delayMillis: Long, runnable: Runnable) { delayed += runnable }
        override fun cancel(runnable: Runnable) { delayed -= runnable }
    }

    private class Client(var active: Boolean = true) : UiHostClient<String> {
        val ready = mutableListOf<String>()
        val unavailable = mutableListOf<UiUnavailableReason>()
        override fun isActive() = active
        override fun onReady(host: String) { ready += host }
        override fun onUnavailable(reason: UiUnavailableReason) { unavailable += reason }
        fun calls() = ready.size + unavailable.size
    }

    private val env = FakeEnv()
    private val core = UiHostCore(env)

    @Test
    fun notInitialized_isUnavailable() {
        env.initialized = false
        val client = Client()
        core.acquire(client)
        assertEquals(listOf(UiUnavailableReason.NOT_INITIALIZED), client.unavailable)
    }

    @Test
    fun fragmentActivityInForeground_isReadyAtOnce() {
        env.host = "fragment-activity"
        val client = Client()
        core.acquire(client)
        assertEquals(listOf("fragment-activity"), client.ready)
        assertTrue(env.launched.isEmpty())
    }

    @Test
    fun noForeground_isNotForeground() {
        env.activity = null
        val client = Client()
        core.acquire(client)
        assertEquals(listOf(UiUnavailableReason.NOT_FOREGROUND), client.unavailable)
    }

    @Test
    fun savedFragmentActivity_isNotForeground_withoutStartingAHost() {
        env.savedFragmentActivity = true
        val client = Client()
        core.acquire(client)
        assertEquals(listOf(UiUnavailableReason.NOT_FOREGROUND), client.unavailable)
        assertTrue(env.launched.isEmpty())
    }

    @Test
    fun plainActivity_startsOneHost_forRequestsThatArriveWhileItStarts() {
        val first = Client()
        val second = Client()
        core.acquire(first)
        core.acquire(second)
        assertEquals(1, env.launched.size)
        assertTrue(core.onHostCreated("host", env.launched.single()))
        assertEquals(listOf("host"), first.ready)
        assertEquals(listOf("host"), second.ready)
        assertTrue(env.delayed.isEmpty())
    }

    @Test
    fun launchThrows_isHostStartFailed_andTheRecordIsGone() {
        env.launchThrows = true
        val client = Client()
        core.acquire(client)
        assertEquals(listOf(UiUnavailableReason.HOST_START_FAILED), client.unavailable)
        env.launchThrows = false
        val next = Client()
        core.acquire(next)
        assertEquals(1, env.launched.size)
    }

    @Test
    fun watchdogThenLateHost_isNotForegroundOnce_andTheLateHostFinishes() {
        val client = Client()
        core.acquire(client)
        val token = env.launched.single()
        env.delayed.single().run()
        assertEquals(listOf(UiUnavailableReason.NOT_FOREGROUND), client.unavailable)
        assertFalse(core.onHostCreated("host", token))
        assertEquals(1, client.calls())
    }

    @Test
    fun hostThenWatchdog_isReadyOnce() {
        val client = Client()
        core.acquire(client)
        val token = env.launched.single()
        val watchdog = env.delayed.single()
        assertTrue(core.onHostCreated("host", token))
        watchdog.run()
        assertEquals(listOf("host"), client.ready)
        assertEquals(1, client.calls())
    }

    @Test
    fun canceledWhileWaiting_isSkippedWhenTheHostArrives() {
        val canceled = Client()
        val live = Client()
        core.acquire(canceled)
        core.acquire(live)
        canceled.active = false
        assertTrue(core.onHostCreated("host", env.launched.single()))
        assertTrue(canceled.ready.isEmpty())
        assertEquals(listOf("host"), live.ready)
    }

    @Test
    fun hostWithAnUnknownToken_finishes() {
        assertFalse(core.onHostCreated("host", 42L))
    }

    @Test
    fun gate_completesOnce_andIgnoresUnknownIds() {
        val gate = UiRequestGate { }
        gate.open(1L)
        assertTrue(gate.isActive(1L))
        assertTrue(gate.tryComplete(1L))
        assertFalse(gate.tryComplete(1L))
        assertFalse(gate.tryComplete(2L))
        assertFalse(gate.isActive(1L))
    }

    @Test
    fun gate_bothOrdersOfCancelAndResult_completeOnce() {
        for (cancelFirst in listOf(true, false)) {
            val gate = UiRequestGate { }
            gate.open(7L)
            val results = mutableListOf<String>()
            val cancel = { if (gate.tryComplete(7L)) results += "canceled" }
            val answer = { if (gate.tryComplete(7L)) results += "answered" }
            if (cancelFirst) { cancel(); answer() } else { answer(); cancel() }
            assertEquals(1, results.size)
        }
    }
}
