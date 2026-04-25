package android.unity.notification

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * [BroadcastReceiver] that receives notification action and body-tap events.
 *
 * Delivers tap, action-button, and dismissal events issued by
 * [UnityAndroidNotificationManager] to [NotificationActionListener].
 */
class NotificationActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        Log.d(TAG, "[onReceive] intent: $intent")
        val actionId = intent?.getStringExtra(EXTRA_ACTION_ID) ?: return
        val notificationId = intent.getIntExtra(EXTRA_NOTIFICATION_ID, -1)
        val launchApp = intent.getBooleanExtra(EXTRA_LAUNCH_APP, false)
        val dataJson = intent.getStringExtra(EXTRA_DATA)

        actionListener?.onNotificationAction(actionId, notificationId, dataJson)

        if (launchApp) {
            context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                    action = actionId
                }
                ?.let { context.startActivity(it) }
        }
    }

    /**
     * Listener that receives notification action events.
     */
    interface NotificationActionListener {
        fun onNotificationAction(actionId: String, notificationId: Int, dataJson: String?)
    }

    companion object {
        private const val TAG = "NotificationActionReceiver"
        /** Intent extra key for action ID. */
        const val EXTRA_ACTION_ID = "android.unity.notification.extra.ACTION_ID"
        /** Intent extra key for notification ID. */
        const val EXTRA_NOTIFICATION_ID = "android.unity.notification.extra.NOTIFICATION_ID"
        /** Intent extra key indicating whether to launch the app after action handling. */
        const val EXTRA_LAUNCH_APP = "android.unity.notification.extra.LAUNCH_APP"
        /** Intent extra key for custom data JSON. */
        const val EXTRA_DATA = "android.unity.notification.extra.DATA"
        /** Action identifier for notification body taps. */
        const val ACTION_BODY_TAP = "android.unity.notification.ACTION_BODY_TAP"
        /** Action identifier for notification dismiss events. */
        const val ACTION_NOTIFICATION_DISMISSED = "android.unity.notification.ACTION_NOTIFICATION_DISMISSED"

        internal var actionListener: NotificationActionListener? = null
    }
}
