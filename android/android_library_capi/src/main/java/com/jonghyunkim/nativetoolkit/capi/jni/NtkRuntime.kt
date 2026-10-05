package com.jonghyunkim.nativetoolkit.capi.jni

import android.app.Application
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

    @Volatile
    private var appContext: Context? = null

    /**
     * The application context passed to the initialization, for the bridges to reach the
     * Managers. Set before the C ABI can become ready, so an operation that passed the
     * initialization check finds it.
     */
    fun context(): Context {
        Log.d(TAG, "[context]")
        return checkNotNull(appContext) { "The C ABI is not initialized" }
    }

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
        if (state == LibraryRuntime.InitState.DONE) {
            keepApplication(context)
        } else {
            LibraryRuntime.addOnInitializedListener {
                keepApplication(context)
                notifyKotlinReady()
            }
        }
        return state.ordinal
    }

    // Keeps the application context once the library is initialized, before C can become READY,
    // and only a real Application: a Context that failed the initialization must not stay. Read
    // after LibraryRuntime, which is the one to ask for the application context first.
    private fun keepApplication(context: Context) {
        Log.d(TAG, "[keepApplication] context: $context")
        (context.applicationContext as? Application)?.let { appContext = it }
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
