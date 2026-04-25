package android.library.notification

/**
 * Listener registration support for notification display events.
 *
 * Calls [shownListener] when a notification is displayed.
 */
object NotificationShownSupport {

    /**
     * Listener for notification display events.
     */
    interface NotificationShownListener {
        fun onNotificationShown(notificationId: Int, tag: String?, channelId: String)
    }

    /**
     * Listener invoked when a notification is displayed.
     */
    var shownListener: NotificationShownListener? = null
}
