package android.unity.notification

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val actionId = intent?.getStringExtra(EXTRA_ACTION_ID) ?: return
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        val launchApp = intent.getBooleanExtra(EXTRA_LAUNCH_APP, false)

        actionListener?.onNotificationAction(actionId, notificationId)

        if (launchApp) {
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    action = actionId
                }
                ?.let { context.startActivity(it) }
        }
    }

    interface NotificationActionListener {
        fun onNotificationAction(actionId: String, notificationId: Int)
    }

    companion object {
        const val EXTRA_ACTION_ID = "android.unity.notification.extra.ACTION_ID"
        const val EXTRA_NOTIFICATION_ID = "android.unity.notification.extra.NOTIFICATION_ID"
        const val EXTRA_LAUNCH_APP = "android.unity.notification.extra.LAUNCH_APP"

        internal var actionListener: NotificationActionListener? = null
    }
}
