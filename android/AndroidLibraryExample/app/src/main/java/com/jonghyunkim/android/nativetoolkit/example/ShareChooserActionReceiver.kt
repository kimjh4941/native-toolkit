package com.jonghyunkim.android.nativetoolkit.example

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast

/**
 * Receives taps on the custom chooser action added to the Sharesheet.
 *
 * The action string must match the intentAction passed in chooserActionsJson.
 * Only accepts app-internal broadcasts (receiver is declared with exported="false").
 */
class ShareChooserActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context?, intent: Intent?) {
        Log.d(TAG, "[onReceive] context: $context, intent: $intent, action: ${intent?.action}")
        if (context != null) {
            Toast.makeText(context, "Custom chooser action tapped", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        private const val TAG = "ShareChooserActionReceiver"
        const val ACTION_CUSTOM_CHOOSER =
            "com.jonghyunkim.android.nativetoolkit.example.CUSTOM_CHOOSER_ACTION"
    }
}
