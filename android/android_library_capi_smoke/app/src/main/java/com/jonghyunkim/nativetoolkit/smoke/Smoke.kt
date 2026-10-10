package com.jonghyunkim.nativetoolkit.smoke

import android.content.Context
import com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi

/** The smoke's C code (smoke.c) and the Kotlin entry of the C ABI, for the test and MainActivity. */
object Smoke {

    /** libsmoke.so needs libntk.so, which the linker loads with it (no JNI_OnLoad on the manual path). */
    fun load() {
        System.loadLibrary("smoke")
    }

    /**
     * NativeToolkitCApi.init, what a Kotlin host calls (C ABI design part 1, 1.4), as a fixed text:
     * without the AAR's keep rules R8 may rename the enum's constants too.
     */
    fun kotlinInit(context: Context): String = when (NativeToolkitCApi.init(context)) {
        NativeToolkitCApi.InitResult.INITIALIZED -> "INITIALIZED"
        NativeToolkitCApi.InitResult.IN_PROGRESS -> "IN_PROGRESS"
        NativeToolkitCApi.InitResult.RETRYABLE_ERROR -> "RETRYABLE_ERROR"
        NativeToolkitCApi.InitResult.NATIVE_SETUP_REQUIRED -> "NATIVE_SETUP_REQUIRED"
        NativeToolkitCApi.InitResult.CLASS_NOT_FOUND -> "CLASS_NOT_FOUND"
        NativeToolkitCApi.InitResult.UNAVAILABLE -> "UNAVAILABLE"
    }

    @JvmStatic external fun init(context: Context): Int
    @JvmStatic external fun isInitialized(): Int
    @JvmStatic external fun notify(id: Int): Int
    @JvmStatic external fun clipboardRoundTrip(text: String): Int
    @JvmStatic external fun showAlert(): Int
    @JvmStatic external fun awaitAlert(timeoutMs: Int): IntArray
    @JvmStatic external fun startProgress(): Int
    @JvmStatic external fun stopProgress(): Int

    /** Only with an STL (smoke_cxx.cpp). */
    @JvmStatic external fun cxxLength(): Int
}
