package com.jonghyunkim.nativetoolkit.capitest

import android.content.Context

/**
 * The JNI helpers of libntk_test.so: ntk_android_init and ntk_android_is_initialized called from
 * C, and the GoogleTest cases one at a time.
 */
object NtkTestNative {

    /** Loads libntk_test.so, which opens libntk.so through the linker only. */
    fun load() {
        System.loadLibrary("ntk_test")
    }

    /** `ntk_android_init(env, context)` with this thread's JNIEnv. */
    @JvmStatic
    external fun init(context: Context?): Int

    /** `ntk_android_init(NULL, context)`. */
    @JvmStatic
    external fun initWithoutEnv(context: Context): Int

    /** `ntk_android_is_initialized()`. */
    @JvmStatic
    external fun isInitialized(): Int

    /** The GoogleTest cases, as `Suite.Name`. */
    @JvmStatic
    external fun listCases(): Array<String>

    /**
     * `ntk_debug_probe_start` before initialization: [error, 1 when release ran on this thread
     * before the call returned, the id written].
     */
    @JvmStatic
    external fun probeStartRejected(): IntArray

    /** Clipboard operations before initialization; see ntk_test_jni.cpp for the layout. */
    @JvmStatic
    external fun clipboardUninitialized(): IntArray

    /** `ntk_dialog_show_alert_async` with [message]; returns the entry's error. */
    @JvmStatic
    external fun showAlert(message: String): Int

    /** Waits for the alert of [showAlert]: [its error, 1 when release followed], or [-1, 0]. */
    @JvmStatic
    external fun awaitAlert(): IntArray

    /** Runs one GoogleTest case; true when it ran and passed. */
    @JvmStatic
    external fun runCase(name: String): Boolean
}
