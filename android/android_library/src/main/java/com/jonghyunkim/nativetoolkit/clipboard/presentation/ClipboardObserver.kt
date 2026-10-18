package com.jonghyunkim.nativetoolkit.clipboard.presentation

import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster

/**
 * The one clipboard change observation of the process (Kotlin API design 8.10). It owns one
 * [ClipboardChangeMonitor] and sends each change to [ClipboardEvents.changes], so any number of
 * listeners share one system listener. Start and stop are idempotent. Main thread only.
 */
internal object ClipboardObserver {

    private const val TAG = "com.jonghyunkim.nativetoolkit.clipboard.presentation.ClipboardObserver"

    private val monitor = ClipboardChangeMonitor()

    /**
     * Starts observing. Does nothing when already observing.
     *
     * @param context Any Context; its application context is used.
     * @throws IllegalStateException When not called on the main thread.
     */
    fun start(context: Context) {
        Log.d(TAG, "[start] context: $context")
        MainPoster.checkMainThread("ClipboardObserver.start")
        monitor.start(context.applicationContext) { onChange() }
    }

    /**
     * Stops observing. Does nothing when not observing.
     *
     * @throws IllegalStateException When not called on the main thread.
     */
    fun stop() {
        Log.d(TAG, "[stop]")
        MainPoster.checkMainThread("ClipboardObserver.stop")
        monitor.stop()
    }

    /**
     * Returns whether observation is active.
     *
     * @throws IllegalStateException When not called on the main thread.
     */
    fun isObserving(): Boolean {
        Log.d(TAG, "[isObserving]")
        MainPoster.checkMainThread("ClipboardObserver.isObserving")
        return monitor.isObserving()
    }

    // The system calls the listener on the thread that registered it (main); post when it does not.
    private fun onChange() {
        Log.d(TAG, "[onChange]")
        if (MainPoster.isMainThread()) {
            ClipboardEvents.changes.emit(Unit)
        } else {
            MainPoster.post { ClipboardEvents.changes.emit(Unit) }
        }
    }
}
