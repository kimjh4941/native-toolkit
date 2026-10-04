package com.jonghyunkim.nativetoolkit.common.event

import android.util.Log
import androidx.annotation.MainThread
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster

/**
 * Delivers library events to any number of listeners on the main thread (Kotlin API design 8.4).
 *
 * A hub that retains events keeps the events that arrive while it has no listener and hands them to
 * the next listener inside [addListener], in the order they arrived. That is the only case in which
 * the library calls a listener synchronously from a call. Adding and removing listeners is
 * main-thread only.
 *
 * @param retention Whether events that arrive with no listener are kept.
 * @param checkMain Throws when the caller is not on the main thread. Tests replace it.
 */
class EventHub<T> internal constructor(
    private val retention: Retention,
    private val checkMain: (String) -> Unit = MainPoster::checkMainThread
) {

    /**
     * Receives events.
     */
    fun interface Listener<T> {
        /**
         * Called on the main thread for each event.
         *
         * @param event The event.
         * @param registration This listener's registration. Removing it here stops later events,
         *   even before [addListener] has returned it.
         */
        fun onEvent(event: T, registration: Registration)
    }

    /**
     * A listener's registration.
     */
    class Registration internal constructor(private val onRemove: (Registration) -> Unit) {

        internal var removed: Boolean = false
            private set

        /**
         * Stops delivery to this listener. Calling it twice does nothing. Main thread only.
         */
        @MainThread
        fun remove() {
            Log.d(TAG, "[remove]")
            if (removed) return
            removed = true
            onRemove(this)
        }
    }

    /** Whether events that arrive with no listener are kept. */
    internal sealed interface Retention {
        /** Events with no listener are dropped. */
        data object None : Retention

        /** Up to [capacity] events are kept, dropping the oldest first. */
        data class UntilFirstListener(val capacity: Int) : Retention
    }

    private class Entry<T>(val listener: Listener<T>, val registration: Registration)

    private val entries = mutableListOf<Entry<T>>()
    private val retained = ArrayDeque<T>()
    private var deliveringRetained = false

    /**
     * Adds [listener]. Events retained while the hub had no listener are delivered to it inside
     * this call, in arrival order.
     *
     * @param listener The listener.
     * @return The registration used to remove the listener.
     */
    @MainThread
    fun addListener(listener: Listener<T>): Registration {
        Log.d(TAG, "[addListener] listener: $listener")
        checkMain("EventHub.addListener")
        val registration = Registration { removed -> entries.removeAll { it.registration === removed } }
        entries.add(Entry(listener, registration))
        if (!deliveringRetained) deliverRetained()
        return registration
    }

    /**
     * Delivers [event] to every listener, or retains it when there is none and this hub retains.
     *
     * @param event The event.
     */
    @MainThread
    internal fun emit(event: T) {
        Log.d(TAG, "[emit] event: $event")
        checkMain("EventHub.emit")
        if (entries.isEmpty()) {
            retain(event)
            return
        }
        for (entry in entries.toList()) {
            if (!entry.registration.removed) call(entry, event)
        }
    }

    private fun retain(event: T) {
        val keep = retention as? Retention.UntilFirstListener ?: return
        retained.addLast(event)
        while (retained.size > keep.capacity) {
            retained.removeFirst()
            Log.w(TAG, "[retain] dropped the oldest retained event; capacity: ${keep.capacity}")
        }
    }

    // Retained events go to the oldest listener still registered. If that listener removes itself
    // during delivery, the rest go to the next oldest; with none left they stay retained for the
    // next addListener (Kotlin API design 8.4).
    private fun deliverRetained() {
        deliveringRetained = true
        try {
            while (retained.isNotEmpty()) {
                val target = entries.firstOrNull { !it.registration.removed } ?: return
                call(target, retained.removeFirst())
            }
        } finally {
            deliveringRetained = false
        }
    }

    private fun call(entry: Entry<T>, event: T) {
        try {
            entry.listener.onEvent(event, entry.registration)
        } catch (e: Exception) {
            Log.e(TAG, "[call] listener: ${entry.listener}", e)
        }
    }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.common.event.EventHub"
    }
}
