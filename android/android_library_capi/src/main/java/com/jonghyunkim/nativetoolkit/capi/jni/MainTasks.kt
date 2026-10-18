package com.jonghyunkim.nativetoolkit.capi.jni

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.MainPoster

/**
 * Posts a bridge's work to the main thread with the exceptions caught (C ABI design part 1, 5.11):
 * an exception thrown in a Handler message would end the app. The work logs what failed and stops;
 * the C side already returned when the post was accepted.
 */
internal object MainTasks {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.MainTasks"

    /** [MainPoster.post] of [block], caught. Returns whether it was posted. */
    fun post(name: String, block: () -> Unit): Boolean {
        Log.d(TAG, "[post] name: $name")
        return MainPoster.post {
            try {
                block()
            } catch (e: Throwable) {
                // The class name only: a message may hold user data (part 1, 5.12).
                Log.e(TAG, "[$name] failed: ${e.javaClass.name}")
            }
        }
    }
}
