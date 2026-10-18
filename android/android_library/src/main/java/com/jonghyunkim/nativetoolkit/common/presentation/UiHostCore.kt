package com.jonghyunkim.nativetoolkit.common.presentation

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.domain.UiUnavailableReason
import com.jonghyunkim.nativetoolkit.common.runtime.RequestIds

/**
 * A request that needs a FragmentActivity to show UI (a dialog, or a permission-request session).
 * Main thread only.
 *
 * @param H The FragmentActivity type.
 */
internal interface UiHostClient<H : Any> {
    /** Returns whether the request still wants UI. Inactive clients are skipped. */
    fun isActive(): Boolean

    /** Shows the UI on [host]. */
    fun onReady(host: H)

    /** Ends the request because UI cannot be shown. */
    fun onUnavailable(reason: UiUnavailableReason)
}

/**
 * What [UiHostCore] needs from Android. Tests replace it.
 *
 * @param H The FragmentActivity type.
 * @param A The Activity type.
 */
internal interface UiHostEnvironment<H : Any, A : Any> {
    fun isInitialized(): Boolean
    fun currentActivity(): A?
    /** The foreground Activity as a host when it is a FragmentActivity that can still commit. */
    fun currentHost(): H?
    /** Whether [activity] is a FragmentActivity whose state is already saved. */
    fun isSavedFragmentActivity(activity: A): Boolean
    /** Starts the transparent host from [from]. Throws when the start fails. */
    fun launchHost(from: A, token: Long)
    fun postDelayed(delayMillis: Long, runnable: Runnable)
    fun cancel(runnable: Runnable)
}

/**
 * Finds a FragmentActivity for UI requests and starts the transparent host when the foreground
 * Activity is not one (Kotlin API design 8.3, README D-7). Main thread only.
 *
 * At most one host is being started at a time. Requests that arrive while it starts wait for it.
 * The host record is removed when the host arrives, when the 5-second watchdog fires, or when
 * starting it throws.
 */
internal class UiHostCore<H : Any, A : Any>(private val env: UiHostEnvironment<H, A>) {

    private class PendingHost<H : Any>(
        val token: Long,
        val clients: MutableList<UiHostClient<H>>,
        val watchdog: Runnable
    )

    private var pending: PendingHost<H>? = null

    /**
     * Calls [client] back exactly once with [UiHostClient.onReady] or [UiHostClient.onUnavailable],
     * unless it becomes inactive first.
     *
     * @param client The request.
     */
    fun acquire(client: UiHostClient<H>) {
        Log.d(TAG, "[acquire] client: $client")
        if (!env.isInitialized()) {
            client.onUnavailable(UiUnavailableReason.NOT_INITIALIZED)
            return
        }
        env.currentHost()?.let {
            client.onReady(it)
            return
        }
        pending?.let {
            it.clients.add(client)
            return
        }
        val from = env.currentActivity()
        if (from == null || env.isSavedFragmentActivity(from)) {
            client.onUnavailable(UiUnavailableReason.NOT_FOREGROUND)
            return
        }
        val token = RequestIds.next()
        val record = PendingHost(token, mutableListOf(client), Runnable { onWatchdog(token) })
        pending = record
        try {
            env.launchHost(from, token)
        } catch (e: Exception) {
            Log.e(TAG, "[acquire] client: $client", e)
            pending = null
            record.clients.filter { it.isActive() }
                .forEach { it.onUnavailable(UiUnavailableReason.HOST_START_FAILED) }
            return
        }
        env.postDelayed(WATCHDOG_MILLIS, record.watchdog)
    }

    /**
     * Called by a host created without saved state.
     *
     * @param host The host.
     * @param token The token the host was started with.
     * @return `true` when the host belongs to the waiting record; `false` when it should finish
     *   (the watchdog already fired, or the process was recreated).
     */
    fun onHostCreated(host: H, token: Long): Boolean {
        Log.d(TAG, "[onHostCreated] host: $host, token: $token")
        val record = pending
        if (record == null || record.token != token) return false
        pending = null
        env.cancel(record.watchdog)
        record.clients.filter { it.isActive() }.forEach { it.onReady(host) }
        return true
    }

    private fun onWatchdog(token: Long) {
        Log.d(TAG, "[onWatchdog] token: $token")
        val record = pending
        if (record == null || record.token != token) return
        pending = null
        record.clients.filter { it.isActive() }
            .forEach { it.onUnavailable(UiUnavailableReason.NOT_FOREGROUND) }
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.common.presentation.UiHostCore"

        /** How long a host may take to start before its requests end with NOT_FOREGROUND. */
        const val WATCHDOG_MILLIS: Long = 5_000L
    }
}
