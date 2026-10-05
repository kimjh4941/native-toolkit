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

    /** Runs one GoogleTest case; true when it ran and passed. */
    @JvmStatic
    external fun runCase(name: String): Boolean
}
