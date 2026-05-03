package com.jonghyunkim.android.nativetoolkit.example

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import android.widget.Toast

class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        Log.d(TAG, "[onReceive] context: $context, intent: $intent")
        if (intent?.action != ACTION_NOTIFICATION_ACTION_BUTTON) {
            return
        }

        val actionId = intent.getStringExtra(EXTRA_ACTION_ID).orEmpty()
        val actionLabel = intent.getStringExtra(EXTRA_ACTION_LABEL).orEmpty()
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)

        Log.d(
            TAG,
            "[onReceive] action button tapped: actionId=$actionId, actionLabel=$actionLabel, notificationId=$notificationId"
        )

        if (isSampleScreenActive) {
            context.sendBroadcast(
                Intent(ACTION_NOTIFICATION_BUTTON_INTERNAL).apply {
                    `package` = context.packageName
                    putExtra(EXTRA_ACTION_ID, actionId)
                    putExtra(EXTRA_ACTION_LABEL, actionLabel)
                    putExtra(EXTRA_NOTIFICATION_ID, notificationId)
                }
            )
        } else {
            Toast.makeText(context, "$actionLabel action pressed", Toast.LENGTH_SHORT).show()
        }
    }

    companion object {
        private const val TAG = "NotificationActionReceiver"

        const val ACTION_NOTIFICATION_ACTION_BUTTON = "native.toolkit.notification.ACTION_BUTTON"
        const val ACTION_NOTIFICATION_BUTTON_INTERNAL = "native.toolkit.notification.ACTION_BUTTON.INTERNAL"

        const val EXTRA_ACTION_ID = "native.toolkit.notification.extra.ACTION_ID"
        const val EXTRA_ACTION_LABEL = "native.toolkit.notification.extra.ACTION_LABEL"
        const val EXTRA_NOTIFICATION_ID = "native.toolkit.notification.extra.NOTIFICATION_ID"

        @Volatile
        var isSampleScreenActive: Boolean = false

        fun createIntent(
            context: Context,
            actionId: String,
            actionLabel: String,
            notificationId: Int
        ): Intent {
            Log.d(TAG, "[createIntent] actionId: $actionId, actionLabel: $actionLabel, notificationId: $notificationId")
            return Intent(context, NotificationActionReceiver::class.java).apply {
                action = ACTION_NOTIFICATION_ACTION_BUTTON
                putExtra(EXTRA_ACTION_ID, actionId)
                putExtra(EXTRA_ACTION_LABEL, actionLabel)
                putExtra(EXTRA_NOTIFICATION_ID, notificationId)
            }
        }
    }
}

