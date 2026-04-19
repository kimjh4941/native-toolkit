package android.library.notification

object NotificationShownSupport {

    interface NotificationShownListener {
        fun onNotificationShown(notificationId: Int, tag: String?, channelId: String)
    }

    var shownListener: NotificationShownListener? = null
}
