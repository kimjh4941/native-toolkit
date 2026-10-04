package com.jonghyunkim.nativetoolkit.testing

import android.app.Activity
import android.os.Bundle
import android.util.Log
import android.widget.TextView
import androidx.fragment.app.FragmentActivity

/**
 * A FragmentActivity: library dialogs show directly on it (Kotlin API design 8.3).
 */
class TestFragmentActivity : FragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState")
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "TestFragmentActivity" })
    }

    private companion object {
        const val TAG = "com.jonghyunkim.nativetoolkit.testing.TestFragmentActivity"
    }
}

/**
 * A plain Activity, like UnityPlayerActivity or FlutterActivity: library dialogs need the
 * transparent host on top of it (Kotlin API design 8.3, README D-7).
 */
class PlainActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState")
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "PlainActivity" })
    }

    private companion object {
        const val TAG = "com.jonghyunkim.nativetoolkit.testing.PlainActivity"
    }
}
