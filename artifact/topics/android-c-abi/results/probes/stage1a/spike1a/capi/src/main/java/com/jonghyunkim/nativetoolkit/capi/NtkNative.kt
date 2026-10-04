package com.jonghyunkim.nativetoolkit.capi

import android.content.Context
import android.util.Log
import androidx.startup.Initializer

/** Kotlin side of the spike: loads libntk.so and receives calls from C. */
object NtkNative {
    @Volatile var loadError: Throwable? = null
    @Volatile @JvmStatic var lastCallback: Int = -1
    @Volatile @JvmStatic var lastCallbackThread: String = ""

    /** Bound with RegisterNatives in JNI_OnLoad (no Java_ symbol is exported). */
    @JvmStatic external fun nativeHello(input: String): String

    /** Called from C through a cached jmethodID, possibly on a native thread. */
    @JvmStatic
    fun onNativeCallback(value: Int) {
        Log.d(TAG, "[onNativeCallback] value: $value")
        lastCallback = value
        lastCallbackThread = Thread.currentThread().name
    }

    fun load() {
        Log.d(TAG, "[load]")
        try {
            System.loadLibrary("ntk")
        } catch (e: UnsatisfiedLinkError) {
            loadError = e
        }
    }

    private const val TAG = "NtkNative"
}

class NtkInitializer : Initializer<Unit> {
    override fun create(context: Context) {
        Log.d("NtkInitializer", "[create] context: $context")
        NtkNative.load()
    }

    override fun dependencies(): List<Class<out Initializer<*>>> = emptyList()
}
