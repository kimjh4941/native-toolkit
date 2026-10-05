package com.jonghyunkim.nativetoolkit.capitest

import android.app.Activity
import android.os.Bundle
import android.widget.TextView

/** A plain Activity that holds the window focus while a test reads the clipboard. */
class FocusActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "ntk capi test" })
    }
}
