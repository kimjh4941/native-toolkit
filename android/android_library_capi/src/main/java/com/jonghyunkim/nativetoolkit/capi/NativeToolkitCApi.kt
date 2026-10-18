package com.jonghyunkim.nativetoolkit.capi

import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.capi.jni.NtkRuntime
import com.jonghyunkim.nativetoolkit.common.runtime.LibraryRuntime

/**
 * The only Kotlin surface of the C ABI (C ABI design part 1, 5.1).
 *
 * Apps that keep androidx.startup need nothing here: [NtkInitializer] initializes the C ABI at app
 * start. Apps that disable Startup, or run the C ABI in a process other than the default one, call
 * [init] (or `ntk_android_init` from C) before the first `ntk_*` operation.
 */
object NativeToolkitCApi {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi"
    private const val LIBRARY = "ntk"
    private const val RUNTIME_CLASS = "com.jonghyunkim.nativetoolkit.capi.jni.NtkRuntime"

    /** The result of [init] (design 5.3). */
    enum class InitResult {
        /** The C ABI is ready. */
        INITIALIZED,

        /** Another thread is initializing. Call [init] again later; this call did not wait. */
        IN_PROGRESS,

        /** This call failed for a reason that may pass. Call [init] again later. */
        RETRYABLE_ERROR,

        /**
         * libntk.so is loaded but its class table is not built, which Kotlin cannot do. Call
         * `ntk_android_init` from C.
         */
        NATIVE_SETUP_REQUIRED,

        /**
         * The C ABI's classes are missing or renamed: the AAR is not in the app, or R8 dropped the
         * keep rules. Retrying does not help.
         */
        CLASS_NOT_FOUND,

        /** libntk.so is not there, for example in an app installed as 32-bit. */
        UNAVAILABLE
    }

    @Volatile
    private var loaded: Boolean? = null

    /**
     * Initializes the C ABI. Never waits; safe from any thread and more than once.
     *
     * @param context Any Context. Its application context is kept; an Activity is also taken as
     *   the foreground Activity.
     * @return What happened; see [InitResult].
     */
    fun init(context: Context): InitResult {
        Log.d(TAG, "[init] context: $context")
        if (!runtimeClassPresent()) return InitResult.CLASS_NOT_FOUND
        if (!loadLibrary()) return InitResult.UNAVAILABLE
        return when (NtkRuntime.ensureInitialized(context)) {
            NtkRuntime.KOTLIN_DONE -> fromState(NtkRuntime.notifyKotlinReady())
            NtkRuntime.KOTLIN_IN_PROGRESS -> InitResult.IN_PROGRESS
            else -> InitResult.RETRYABLE_ERROR
        }
    }

    /** Whether libntk.so could be loaded. False in an app installed as 32-bit. */
    val isAvailable: Boolean
        get() {
            Log.d(TAG, "[isAvailable]")
            return loadLibrary()
        }

    /** Whether the C ABI is ready; the same as `ntk_android_is_initialized`. */
    val isInitialized: Boolean
        get() {
            Log.d(TAG, "[isInitialized]")
            return NtkRuntime.stateOrMissing() == NtkRuntime.STATE_READY
        }

    /**
     * Loads libntk.so once. Its JNI_OnLoad builds the class table. Loading again is harmless, but
     * the result is kept.
     */
    internal fun loadLibrary(): Boolean {
        Log.d(TAG, "[loadLibrary]")
        loaded?.let { return it }
        val result = try {
            System.loadLibrary(LIBRARY)
            true
        } catch (e: UnsatisfiedLinkError) {
            Log.w(TAG, "[loadLibrary] libntk.so is not available", e)
            false
        }
        loaded = result
        return result
    }

    // R8 renames NtkRuntime together with the references here, so only a lookup by name, as C
    // does, tells whether the keep rules were applied (design 5.3). The members are looked up too:
    // without the rules, the default R8 configuration keeps the name of a class with native
    // methods but still renames or removes its other members, and C then reports CLASS_NOT_FOUND.
    private fun runtimeClassPresent(): Boolean {
        Log.d(TAG, "[runtimeClassPresent]")
        return try {
            val runtime = Class.forName(RUNTIME_CLASS, false, NativeToolkitCApi::class.java.classLoader)
            runtime.getDeclaredMethod("ensureInitialized", Context::class.java)
            runtime.getDeclaredMethod("onKotlinReady")
            runtime.getDeclaredMethod("nativeState")
            true
        } catch (e: ReflectiveOperationException) {
            Log.e(TAG, "[runtimeClassPresent] $RUNTIME_CLASS or a member is missing; check the R8 keep rules", e)
            false
        }
    }

    private fun fromState(state: Int): InitResult {
        Log.d(TAG, "[fromState] state: $state")
        return when (state) {
            NtkRuntime.STATE_READY -> InitResult.INITIALIZED
            NtkRuntime.STATE_FAILED -> InitResult.CLASS_NOT_FOUND
            NtkRuntime.NATIVES_MISSING -> InitResult.NATIVE_SETUP_REQUIRED
            else -> InitResult.IN_PROGRESS
        }
    }
}
