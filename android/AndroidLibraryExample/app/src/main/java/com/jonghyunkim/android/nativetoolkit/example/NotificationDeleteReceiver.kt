package com.jonghyunkim.android.nativetoolkit.example

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast

class NotificationDeleteReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        Log.d(TAG, "[onReceive] context: $context, intent: $intent")
        if (intent?.action != ACTION_NOTIFICATION_DELETED) {
            return
        }

        val sampleLabel = intent.getStringExtra(EXTRA_SAMPLE_LABEL) ?: "Notification"
        Log.d(TAG, "[onReceive] deleteIntent triggered for sampleLabel=$sampleLabel")
        Toast.makeText(context, "$sampleLabel dismissed (deleteIntent)", Toast.LENGTH_SHORT).show()
    }

    companion object {
        private const val TAG = "NotificationDeleteReceiver"
        const val ACTION_NOTIFICATION_DELETED = "native.toolkit.notification.DELETE"
        private const val EXTRA_SAMPLE_LABEL = "native.toolkit.notification.extra.SAMPLE_LABEL"

        fun createIntent(context: Context, sampleLabel: String): Intent {
            Log.d(TAG, "[createIntent] sampleLabel: $sampleLabel")
            return Intent(context, NotificationDeleteReceiver::class.java).apply {
                action = ACTION_NOTIFICATION_DELETED
                putExtra(EXTRA_SAMPLE_LABEL, sampleLabel)
            }
        }
    }
}

