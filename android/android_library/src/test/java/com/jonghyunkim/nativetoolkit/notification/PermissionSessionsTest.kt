package com.jonghyunkim.nativetoolkit.notification

import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason
import com.jonghyunkim.nativetoolkit.common.presentation.UiHostClient
import com.jonghyunkim.nativetoolkit.common.presentation.UiRequestGate
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult
import com.jonghyunkim.nativetoolkit.notification.presentation.permission.PermissionEnvironment
import com.jonghyunkim.nativetoolkit.notification.presentation.permission.PermissionSessions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// UT-06 of the Kotlin API design: the permission session table of 8.7.
class PermissionSessionsTest {

    private class FakeEnv : PermissionEnvironment<String> {
        var granted = false
        var initialized = true
        var readyAtOnce = false
        var addThrows: Exception? = null
        val clients = mutableListOf<UiHostClient<String>>()
        val fragments = mutableListOf<Long>()

        override fun isGrantedOrNotNeeded() = granted
        override fun isInitialized() = initialized
        override fun acquire(client: UiHostClient<String>) {
            clients += client
            if (readyAtOnce) client.onReady("host")
        }
        override fun addFragment(host: String, sessionId: Long) {
            addThrows?.let { throw it }
            fragments += sessionId
        }
        override fun isStateSaved(error: Exception) = error is IllegalStateException
    }

    private val env = FakeEnv()
    private val sessions = PermissionSessions(env, UiRequestGate { })
    private val results = mutableMapOf<Long, MutableList<PermissionRequestResult>>()

    private fun request(id: Long) = sessions.request(id) { results.getOrPut(id) { mutableListOf() } += it }

    @Test
    fun grantedOrApi32_isGrantedAtOnce_withoutUi() {
        env.granted = true
        request(1)
        assertEquals(listOf(PermissionRequestResult.Granted), results[1])
        assertTrue(env.clients.isEmpty())
    }

    @Test
    fun notInitialized_isFailed() {
        env.initialized = false
        request(1)
        assertEquals(listOf<PermissionRequestResult>(PermissionRequestResult.Failed(UiUnavailableReason.NOT_INITIALIZED)), results[1])
    }

    @Test
    fun twoRequests_shareOneSession_andGetTheSameAnswer() {
        request(1)
        request(2)
        assertEquals(1, env.clients.size)
        env.clients.single().onReady("host")
        val sessionId = env.fragments.single()
        sessions.onResult(sessionId, granted = false)
        assertEquals(listOf(PermissionRequestResult.Denied), results[1])
        assertEquals(listOf(PermissionRequestResult.Denied), results[2])
    }

    @Test
    fun readyInsideAcquire_addsTheFragment() {
        env.readyAtOnce = true
        request(1)
        assertEquals(1, env.fragments.size)
    }

    @Test
    fun cancelWhileWaitingForTheHost_lastWaiter_dropsTheSession() {
        request(1)
        sessions.cancel(1)
        assertEquals(listOf<PermissionRequestResult>(PermissionRequestResult.Canceled(CancelReason.REQUESTED)), results[1])
        val client = env.clients.single()
        assertFalse(client.isActive())
        request(2)
        assertEquals(2, env.clients.size)
    }

    @Test
    fun cancelAfterTheFragment_keepsTheSession_andALaterRequestJoinsIt() {
        request(1)
        env.clients.single().onReady("host")
        val sessionId = env.fragments.single()
        sessions.cancel(1)
        assertTrue(sessions.isCurrent(sessionId))
        request(2)
        assertEquals(1, env.clients.size)
        sessions.onResult(sessionId, granted = true)
        assertEquals(listOf<PermissionRequestResult>(PermissionRequestResult.Canceled(CancelReason.REQUESTED)), results[1])
        assertEquals(listOf(PermissionRequestResult.Granted), results[2])
    }

    @Test
    fun unavailable_failsEveryWaiter() {
        request(1)
        request(2)
        env.clients.single().onUnavailable(UiUnavailableReason.NOT_FOREGROUND)
        val expected = listOf<PermissionRequestResult>(PermissionRequestResult.Failed(UiUnavailableReason.NOT_FOREGROUND))
        assertEquals(expected, results[1])
        assertEquals(expected, results[2])
    }

    @Test
    fun addFragmentThrowsStateSaved_isNotForeground_otherwiseHostStartFailed() {
        env.addThrows = IllegalStateException("saved")
        request(1)
        env.clients.single().onReady("host")
        assertEquals(listOf<PermissionRequestResult>(PermissionRequestResult.Failed(UiUnavailableReason.NOT_FOREGROUND)), results[1])
        env.addThrows = RuntimeException("other")
        request(2)
        env.clients.last().onReady("host")
        assertEquals(listOf<PermissionRequestResult>(PermissionRequestResult.Failed(UiUnavailableReason.HOST_START_FAILED)), results[2])
    }

    @Test
    fun fragmentDestroyed_isHostDestroyed_andALateAnswerIsIgnored() {
        request(1)
        env.clients.single().onReady("host")
        val sessionId = env.fragments.single()
        sessions.onFragmentDestroyed(sessionId)
        sessions.onResult(sessionId, granted = true)
        assertEquals(listOf<PermissionRequestResult>(PermissionRequestResult.Canceled(CancelReason.HOST_DESTROYED)), results[1])
    }

    @Test
    fun answerThenDestroy_completesOnceWithTheAnswer() {
        request(1)
        env.clients.single().onReady("host")
        val sessionId = env.fragments.single()
        sessions.onResult(sessionId, granted = true)
        sessions.onFragmentDestroyed(sessionId)
        assertEquals(listOf(PermissionRequestResult.Granted), results[1])
    }

    @Test
    fun afterAnAnswer_aNewRequestStartsANewSession() {
        request(1)
        env.clients.single().onReady("host")
        sessions.onResult(env.fragments.single(), granted = false)
        request(2)
        assertEquals(2, env.clients.size)
        assertTrue(env.clients.last().isActive())
        assertFalse(env.clients.first().isActive())
    }

    @Test
    fun restoredFragmentOfAnOldSession_isNotCurrent() {
        assertFalse(sessions.isCurrent(12345L))
    }

    @Test
    fun callbackThatThrows_doesNotStopTheOtherWaiters() {
        sessions.request(1) { throw IllegalStateException("boom") }
        request(2)
        env.clients.single().onReady("host")
        sessions.onResult(env.fragments.single(), granted = true)
        assertEquals(listOf(PermissionRequestResult.Granted), results[2])
    }
}
