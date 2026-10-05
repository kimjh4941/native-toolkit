package com.jonghyunkim.nativetoolkit.capi.jni

import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime

/**
 * The Kotlin side of the C ABI's initialization (C ABI design part 1, 5.3). libntk.so looks this
 * class up by name and binds its native methods with RegisterNatives, so it lives in the capi.jni
 * package that consumer-rules.pro keeps (AC-20). It has no static initializer that loads the
 * library: looking up its methods from the class table would run it again (design 5.3).
 */
internal object NtkRuntime {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.NtkRuntime"

    /** [ensureInitialized] results, by the ordinal of [LibraryRuntime.InitState]. */
    const val KOTLIN_DONE = 0
    const val KOTLIN_IN_PROGRESS = 1
    const val KOTLIN_ERROR = 2

    /** The C states [onKotlinReady] and [nativeState] return (Runtime.h). */
    const val STATE_UNINIT = 0
    const val STATE_NATIVE_READY = 1
    const val STATE_READY = 2
    const val STATE_FAILED = 3

    /** What [notifyKotlinReady] returns when the natives are not registered yet. */
    const val NATIVES_MISSING = -1

    /**
     * Runs the Kotlin side once, from any of the three entries of the C ABI. When it is not done
     * yet, LibraryRuntime is asked to tell C once it is, so that the state still reaches READY
     * (design 5.3). Never waits.
     *
     * Called from C by name (ntk_android_init).
     *
     * @param context Any Context; an Activity is also taken as the foreground.
     * @return [KOTLIN_DONE], [KOTLIN_IN_PROGRESS] or [KOTLIN_ERROR].
     */
    @JvmStatic
    fun ensureInitialized(context: Context): Int {
        Log.d(TAG, "[ensureInitialized] context: $context")
        val state = LibraryRuntime.ensureInitialized(context)
        if (state != LibraryRuntime.InitState.DONE) {
            LibraryRuntime.addOnInitializedListener { notifyKotlinReady() }
        }
        return state.ordinal
    }

    /**
     * Tells C that the Kotlin side is done.
     *
     * @return The C state afterwards, or [NATIVES_MISSING] when the class table is not built
     *   (the natives are bound when it is).
     */
    fun notifyKotlinReady(): Int {
        Log.d(TAG, "[notifyKotlinReady]")
        return try {
            onKotlinReady()
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "[notifyKotlinReady] the native class table is not built yet", e)
            NATIVES_MISSING
        }
    }

    /**
     * Returns the C state, or [NATIVES_MISSING] when the class table is not built.
     */
    fun stateOrMissing(): Int {
        Log.d(TAG, "[stateOrMissing]")
        return try {
            nativeState()
        } catch (e: UnsatisfiedLinkError) {
            NATIVES_MISSING
        }
    }

    /** Marks the Kotlin side done in C and returns the C state. Bound by RegisterNatives. */
    @JvmStatic
    external fun onKotlinReady(): Int

    /** Returns the C state. Bound by RegisterNatives. */
    @JvmStatic
    external fun nativeState(): Int
}
