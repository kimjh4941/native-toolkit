package com.example.ntkconsumer

import android.app.Activity
import android.os.Bundle
import android.util.Log
import com.jonghyunkim.nativetoolkit.capi.NtkNative

class MainActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val lines = mutableListOf<String>()
        if (BuildConfigProbe.dlopenOnly(this)) {
            System.loadLibrary("dlopenprobe")
            Log.i("SPIKE1A", "loadError=${NtkNative.loadError}")
            Log.i("SPIKE1A", runDlopenChecks())
            Log.i("SPIKE1A", "lastCallback=${NtkNative.lastCallback}")
            return
        }
        lines += "loadError=${NtkNative.loadError}"
        lines += runCatching { "nativeHello=" + NtkNative.nativeHello("abc") }.getOrElse { "nativeHello failed: $it" }
        System.loadLibrary("consumer")
        lines += "checks: " + runChecks()
        lines += "lastCallback=${NtkNative.lastCallback} thread=${NtkNative.lastCallbackThread}"
        lines.forEach { Log.i("SPIKE1A", it) }
    }

    companion object {
        @JvmStatic external fun runChecks(): String
        @JvmStatic external fun runDlopenChecks(): String
    }
}

/** True when the app was started with --ez dlopen true. */
object BuildConfigProbe {
    fun dlopenOnly(activity: Activity): Boolean = activity.intent.getBooleanExtra("dlopen", false)
}
