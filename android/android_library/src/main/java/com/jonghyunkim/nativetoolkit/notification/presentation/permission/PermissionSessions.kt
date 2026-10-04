package com.jonghyunkim.nativetoolkit.notification.presentation.permission

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.domain.CancelReason
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason
import com.jonghyunkim.nativetoolkit.common.presentation.UiHostClient
import com.jonghyunkim.nativetoolkit.common.presentation.UiRequestGate
import com.jonghyunkim.nativetoolkit.common.runtime.RequestIds
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult

/**
 * What [PermissionSessions] needs from Android. Tests replace it.
 *
 * @param H The FragmentActivity type.
 */
internal interface PermissionEnvironment<H : Any> {
    /** API 32 and lower, or the permission is already granted. */
    fun isGrantedOrNotNeeded(): Boolean
    fun isInitialized(): Boolean
    fun acquire(client: UiHostClient<H>)
    /** Adds the request fragment for [sessionId] to [host] synchronously. Throws when it cannot. */
    fun addFragment(host: H, sessionId: Long)
    /** Whether [error] from [addFragment] means the host's state is already saved. */
    fun isStateSaved(error: Exception): Boolean
}

/**
 * The notification permission request sessions (Kotlin API design 8.7). Main thread only.
 *
 * At most one session shows the system dialog. Requests that arrive while a session exists join
 * it and all get the same answer. Each request completes exactly once through [gate]; the session
 * ID never enters the gate.
 */
internal class PermissionSessions<H : Any>(
    private val env: PermissionEnvironment<H>,
    private val gate: UiRequestGate
) {

    private inner class Session(val id: Long) : UiHostClient<H> {
        val waiters = LinkedHashMap<Long, (PermissionRequestResult) -> Unit>()
        var fragmentAdded = false

        // A session is dropped when its last waiter is canceled before the fragment is added, so
        // being the current session is enough.
        override fun isActive(): Boolean = current === this

        override fun onReady(host: H) {
            Log.d(TAG, "[onReady] sessionId: $id, host: $host")
            try {
                env.addFragment(host, id)
                fragmentAdded = true
            } catch (e: Exception) {
                Log.e(TAG, "[onReady] sessionId: $id", e)
                val reason = if (env.isStateSaved(e)) {
                    UiUnavailableReason.NOT_FOREGROUND
                } else {
                    UiUnavailableReason.HOST_START_FAILED
                }
                finish(this, PermissionRequestResult.Failed(reason))
            }
        }

        override fun onUnavailable(reason: UiUnavailableReason) {
            Log.d(TAG, "[onUnavailable] sessionId: $id, reason: $reason")
            finish(this, PermissionRequestResult.Failed(reason))
        }
    }

    private var current: Session? = null

    /**
     * Starts or joins a request.
     *
     * @param requestId The request ID.
     * @param onResult Receives the result once.
     */
    fun request(requestId: Long, onResult: (PermissionRequestResult) -> Unit) {
        Log.d(TAG, "[request] requestId: $requestId, onResult: $onResult")
        gate.open(requestId)
        if (env.isGrantedOrNotNeeded()) {
            complete(requestId, onResult, PermissionRequestResult.Granted)
            return
        }
        if (!env.isInitialized()) {
            complete(requestId, onResult, PermissionRequestResult.Failed(UiUnavailableReason.NOT_INITIALIZED))
            return
        }
        val session = current
        if (session != null) {
            session.waiters[requestId] = onResult
            return
        }
        val created = Session(RequestIds.next())
        current = created
        // Add the waiter before acquire: acquire may call onReady at once, which checks isActive.
        created.waiters[requestId] = onResult
        env.acquire(created)
    }

    /**
     * Cancels [requestId]. The session goes on while the system dialog is up.
     *
     * @param requestId The request ID.
     */
    fun cancel(requestId: Long) {
        Log.d(TAG, "[cancel] requestId: $requestId")
        val session = current ?: return
        val onResult = session.waiters.remove(requestId) ?: return
        complete(requestId, onResult, PermissionRequestResult.Canceled(CancelReason.REQUESTED))
        if (!session.fragmentAdded && session.waiters.isEmpty()) current = null
    }

    /**
     * The system dialog answered.
     *
     * @param sessionId The session of the fragment that got the answer.
     * @param granted Whether the permission was granted.
     */
    fun onResult(sessionId: Long, granted: Boolean) {
        Log.d(TAG, "[onResult] sessionId: $sessionId, granted: $granted")
        val session = current?.takeIf { it.id == sessionId } ?: return
        finish(session, if (granted) PermissionRequestResult.Granted else PermissionRequestResult.Denied)
    }

    /**
     * The request fragment was destroyed for good before the answer.
     *
     * @param sessionId The fragment's session.
     */
    fun onFragmentDestroyed(sessionId: Long) {
        Log.d(TAG, "[onFragmentDestroyed] sessionId: $sessionId")
        val session = current?.takeIf { it.id == sessionId } ?: return
        finish(session, PermissionRequestResult.Canceled(CancelReason.HOST_DESTROYED))
    }

    /**
     * Returns whether [sessionId] is the current session. A fragment restored after the process
     * died belongs to no current session and must not launch the request.
     *
     * @param sessionId The fragment's session.
     */
    fun isCurrent(sessionId: Long): Boolean {
        Log.d(TAG, "[isCurrent] sessionId: $sessionId")
        return current?.id == sessionId
    }

    // Detach the waiters before calling them, so that a callback that starts a new request starts
    // a new session.
    private fun finish(session: Session, result: PermissionRequestResult) {
        if (current === session) current = null
        val waiters = session.waiters.toList()
        session.waiters.clear()
        waiters.forEach { (requestId, onResult) -> complete(requestId, onResult, result) }
    }

    private fun complete(
        requestId: Long,
        onResult: (PermissionRequestResult) -> Unit,
        result: PermissionRequestResult
    ) {
        if (!gate.tryComplete(requestId)) return
        try {
            onResult(result)
        } catch (e: Exception) {
            Log.e(TAG, "[complete] requestId: $requestId", e)
        }
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.presentation.permission.PermissionSessions"
    }
}
