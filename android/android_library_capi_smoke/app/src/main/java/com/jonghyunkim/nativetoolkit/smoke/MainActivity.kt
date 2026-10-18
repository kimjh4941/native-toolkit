package com.jonghyunkim.nativetoolkit.smoke

import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.TextView
import com.jonghyunkim.nativetoolkit.capi.NativeToolkitCApi
import com.jonghyunkim.nativetoolkit.clipboard.AndroidClipboardManager
import com.jonghyunkim.nativetoolkit.clipboard.domain.model.ClipContent

/**
 * The window the smoke runs in. Two checks run outside instrumentation, started by adb with an
 * extra and read from logcat (tag ntk-smoke), because instrumentation changes what they see:
 *  - progressFromBack: 20 s after the app goes to the back, start a progress notification. Android
 *    refuses the foreground service there (SERVICE_START_NOT_ALLOWED); an instrumented app is exempt.
 *  - kotlinOnly: for the app installed as 32-bit, where libntk.so is missing: the C ABI reports
 *    UNAVAILABLE and the Kotlin API still works (README chapter 9).
 */
class MainActivity : Activity() {

    private val handler = Handler(Looper.getMainLooper())

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "NTK smoke" })
    }

    // Reading the clipboard needs the window focus (Android 10 and later).
    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus && intent.getBooleanExtra("kotlinOnly", false)) {
            val result = NativeToolkitCApi.init(this)
            val clipboard = AndroidClipboardManager.getInstance(this)
            clipboard.copyPlainText(ClipContent.PlainText("ntk smoke 32-bit"))
            val read = clipboard.read()
            Log.i(TAG, "kotlinOnly: capi=$result, clipboard=${read != null}")
        }
    }

    override fun onStop() {
        super.onStop()
        if (intent.getBooleanExtra("progressFromBack", false)) {
            handler.postDelayed({
                Smoke.load()
                if (BuildConfig.MANUAL) Smoke.init(applicationContext)
                Log.i(TAG, "progressFromBack: ${Smoke.startProgress()}")
                Smoke.stopProgress()
            }, 20_000)
        }
    }

    private companion object {
        const val TAG = "ntk-smoke"
    }
}
