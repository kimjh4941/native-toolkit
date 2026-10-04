package com.jonghyunkim.nativetoolkit.testing

import android.app.Activity
import android.os.Bundle
import android.util.Log

/**
 * Empty activity the clipboard instrumented tests keep in front, because since Android 10 only
 * the app with input focus can read the clipboard or receive its change callbacks.
 */
class FocusActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState")
        super.onCreate(savedInstanceState)
    }

    private companion object {
        const val TAG = "com.jonghyunkim.nativetoolkit.testing.FocusActivity"
    }
}
