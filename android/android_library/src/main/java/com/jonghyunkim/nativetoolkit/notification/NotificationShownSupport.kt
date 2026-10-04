package com.jonghyunkim.nativetoolkit.notification

/**
 * Listener registration support for notification display events.
 *
 * Calls [shownListener] when a notification is displayed.
 */
@Deprecated(
    "Use the shown events of AndroidNotificationManager. Kept only for the Unity bridge; removed in stage 3 before 2.0.0 ships."
)
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
