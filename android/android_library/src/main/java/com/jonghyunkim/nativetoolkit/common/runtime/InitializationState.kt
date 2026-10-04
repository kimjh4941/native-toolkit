package com.jonghyunkim.nativetoolkit.common.runtime

import android.util.Log

/**
 * The not-started / in-progress / done state of the library initialization and its
 * "run when done" listeners (Kotlin API design 8.1).
 *
 * The state and the listener list change together under one short lock, so a listener is never
 * lost and never posted twice. No I/O and no callback runs inside the lock.
 *
 * @param post Posts a listener to the main thread.
 */
internal class InitializationState(private val post: (() -> Unit) -> Unit) {

    /** The result of [tryBegin]. */
    enum class Begin { WON, IN_PROGRESS, DONE }

    private enum class State { NOT_STARTED, IN_PROGRESS, DONE }

    private companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.common.runtime.InitializationState"
    }

    private val lock = Any()
    private var state = State.NOT_STARTED
    private val pending = mutableListOf<() -> Unit>()

    /** Returns whether the initialization is done. */
    fun isDone(): Boolean {
        Log.d(TAG, "[isDone]")
        return synchronized(lock) { state == State.DONE }
    }

    /**
     * Moves not-started to in-progress. Only the caller that gets [Begin.WON] runs the work and
     * must then call [succeed] or [fail].
     */
    fun tryBegin(): Begin {
        Log.d(TAG, "[tryBegin]")
        return tryBeginLocked()
    }

    private fun tryBeginLocked(): Begin = synchronized(lock) {
        when (state) {
            State.DONE -> Begin.DONE
            State.IN_PROGRESS -> Begin.IN_PROGRESS
            State.NOT_STARTED -> {
                state = State.IN_PROGRESS
                Begin.WON
            }
        }
    }

    /** Marks the work done and posts every pending listener once. */
    fun succeed() {
        Log.d(TAG, "[succeed]")
        val toRun = synchronized(lock) {
            state = State.DONE
            val listeners = pending.toList()
            pending.clear()
            listeners
        }
        toRun.forEach(post)
    }

    /** Returns to not-started so that a later call can try again. Pending listeners stay. */
    fun fail() {
        Log.d(TAG, "[fail]")
        synchronized(lock) { state = State.NOT_STARTED }
    }

    /**
     * Posts [listener] once after the work is done: now if it is already done, otherwise when
     * [succeed] runs.
     */
    fun addListener(listener: () -> Unit) {
        Log.d(TAG, "[addListener] listener: $listener")
        val runNow = synchronized(lock) {
            if (state == State.DONE) {
                true
            } else {
                pending.add(listener)
                false
            }
        }
        if (runNow) post(listener)
    }
}
