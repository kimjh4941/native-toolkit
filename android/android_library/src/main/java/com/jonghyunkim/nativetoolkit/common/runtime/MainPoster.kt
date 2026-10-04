package com.jonghyunkim.nativetoolkit.common.runtime

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RestrictTo

/**
 * Posts work to the main thread through one [Handler] with synchronous messages only.
 *
 * Everything the library runs on main goes through this handler, so work posted earlier always runs
 * earlier (Kotlin API design 6.2; the C ABI design 5.7 relies on this order). Work is posted even
 * when the caller is already on main.
 */
@RestrictTo(RestrictTo.Scope.LIBRARY_GROUP)
object MainPoster {

    private const val TAG = "com.jonghyunkim.nativetoolkit.common.runtime.MainPoster"

    private val handler: Handler by lazy { Handler(Looper.getMainLooper()) }

    /**
     * Posts [block] to the main thread.
     *
     * @param block The work to run on main.
     * @return `true` when the work was queued; `false` when the main looper is exiting.
     */
    fun post(block: () -> Unit): Boolean {
        Log.d(TAG, "[post] block: $block")
        return handler.post(block)
    }

    /**
     * Posts [runnable] to the main thread after [delayMillis].
     *
     * @param delayMillis The delay in milliseconds.
     * @param runnable The work to run on main. Keep the instance to cancel it with [cancel].
     * @return `true` when the work was queued.
     */
    internal fun postDelayed(delayMillis: Long, runnable: Runnable): Boolean {
        Log.d(TAG, "[postDelayed] delayMillis: $delayMillis, runnable: $runnable")
        return handler.postDelayed(runnable, delayMillis)
    }

    /**
     * Removes [runnable] if it has not run yet.
     *
     * @param runnable The work given to [postDelayed].
     */
    internal fun cancel(runnable: Runnable) {
        Log.d(TAG, "[cancel] runnable: $runnable")
        handler.removeCallbacks(runnable)
    }

    /**
     * Returns whether the caller runs on the main thread.
     */
    fun isMainThread(): Boolean = Looper.myLooper() == Looper.getMainLooper()

    /**
     * Throws [IllegalStateException] unless the caller runs on the main thread.
     *
     * @param name The API name used in the error message.
     */
    internal fun checkMainThread(name: String) {
        check(isMainThread()) { "$name must be called on the main thread" }
    }
}
