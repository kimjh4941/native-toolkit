package com.jonghyunkim.nativetoolkit.common.presentation

import android.app.Activity
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.fragment.app.FragmentActivity

/**
 * The transparent FragmentActivity that shows library UI when the foreground Activity is not a
 * FragmentActivity (Kotlin API design 8.3, README D-7).
 *
 * It joins the foreground Activity's task, is not recreated by most configuration changes, and
 * finishes once no library fragment is left in it.
 */
internal class NtkHostActivity : FragmentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        Log.d(TAG, "[onCreate] savedInstanceState: $savedInstanceState")
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            val token = intent.getLongExtra(EXTRA_TOKEN, NO_TOKEN)
            if (token == NO_TOKEN || !UiHost.onHostCreated(this, token)) {
                finish()
                return
            }
        }
        // When recreated, the FragmentManager has restored the library fragments in super.onCreate,
        // and they go on with the same request IDs.
        finishIfIdle()
    }

    /**
     * Finishes the host when no library fragment is left in it.
     */
    fun finishIfIdle() {
        Log.d(TAG, "[finishIfIdle]")
        if (isFinishing || isDestroyed) return
        val hasLibraryFragment = supportFragmentManager.fragments.any { fragment ->
            fragment.tag?.startsWith(UiHost.FRAGMENT_TAG_PREFIX) == true && !fragment.isRemoving
        }
        if (!hasLibraryFragment) finish()
    }

    override fun finish() {
        Log.d(TAG, "[finish]")
        super.finish()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(Activity.OVERRIDE_TRANSITION_CLOSE, 0, 0)
        } else {
            @Suppress("DEPRECATION")
            overridePendingTransition(0, 0)
        }
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.common.presentation.NtkHostActivity"

        /** The token of the host record this host belongs to. */
        const val EXTRA_TOKEN: String = "com.jonghyunkim.nativetoolkit.extra.HOST_TOKEN"

        private const val NO_TOKEN = -1L
    }
}
