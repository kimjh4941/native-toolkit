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

/** The test app's launch Activity: what a notification tap with OPEN_APP opens (part 2, AP-18). */
class LaunchTargetActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(TextView(this).apply { text = "ntk capi launch target" })
    }
}

/** A share target the Sharesheet lists, for picking an app (part 2, 12.2). It closes at once. */
class ShareTargetActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        finish()
    }
}
