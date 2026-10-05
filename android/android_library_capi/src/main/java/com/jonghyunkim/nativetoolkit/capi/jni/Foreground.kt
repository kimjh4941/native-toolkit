package com.jonghyunkim.nativetoolkit.capi.jni

import android.util.Log
import com.jonghyunkim.nativetoolkit.common.presentation.ForegroundActivityTracker

/**
 * The foreground check of the C ABI (C ABI design part 1, 5.8, C-4): operations that need the
 * foreground - dialogs, the permission request when not granted, the settings screen, opening
 * the Sharesheet - complete with NOT_FOREGROUND without calling Kotlin when this is false.
 */
internal object Foreground {

    private const val TAG = "com.jonghyunkim.nativetoolkit.capi.jni.Foreground"

    /** Whether an Activity of the app is in the foreground. Main thread only. */
    fun isForeground(): Boolean {
        Log.d(TAG, "[isForeground]")
        return ForegroundActivityTracker.current() != null
    }
}
