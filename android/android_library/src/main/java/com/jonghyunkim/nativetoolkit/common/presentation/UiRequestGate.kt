package com.jonghyunkim.nativetoolkit.common.presentation

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster

/**
 * The "already completed" gate for dialog and permission requests (Kotlin API design 8.3).
 *
 * Every completion calls [tryComplete] and calls the user's function only when it returns `true`,
 * so a request completes exactly once whatever order its events arrive in. Main thread only.
 *
 * @param checkMain Throws when the caller is not on the main thread. Tests replace it.
 */
internal class UiRequestGate(
    private val checkMain: (String) -> Unit = MainPoster::checkMainThread
) {

    private val active = HashSet<Long>()

    /**
     * Marks [requestId] active.
     *
     * @param requestId The request ID.
     */
    fun open(requestId: Long) {
        Log.d(TAG, "[open] requestId: $requestId")
        checkMain("UiRequestGate.open")
        active.add(requestId)
    }

    /**
     * Returns whether [requestId] is still active.
     *
     * @param requestId The request ID.
     */
    fun isActive(requestId: Long): Boolean {
        Log.d(TAG, "[isActive] requestId: $requestId")
        checkMain("UiRequestGate.isActive")
        return requestId in active
    }

    /**
     * Completes [requestId]: returns `true` the first time and `false` afterwards or for an unknown ID.
     *
     * @param requestId The request ID.
     */
    fun tryComplete(requestId: Long): Boolean {
        Log.d(TAG, "[tryComplete] requestId: $requestId")
        checkMain("UiRequestGate.tryComplete")
        return active.remove(requestId)
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.common.presentation.UiRequestGate"

        /** The gate shared by every dialog and permission request in the process. */
        val shared: UiRequestGate by lazy { UiRequestGate() }
    }
}
