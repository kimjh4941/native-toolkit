package android.library.notification.domain.model

/**
 * Notification content definition.
 *
 * @property id Notification ID.
 * @property title Notification title.
 * @property message Notification message.
 * @property channel Notification channel settings.
 * @property priority Priority constant from [androidx.core.app.NotificationCompat].
 * @property visibility Lock-screen visibility constant from [android.app.Notification].
 * @property style Notification style.
 * @property progress Progress bar settings, or null to hide progress.
 */
data class NotificationContent(
    val id: Int,
    val title: String,
    val message: String,
    val tag: String? = null,
    val channel: NotificationChannel = NotificationChannel(),
    val smallIconResId: Int? = null,
    val largeIconResId: Int? = null,
    val priority: Int = 0,
    val autoCancel: Boolean = true,
    val ongoing: Boolean = false,
    val subText: String? = null,
    val showTimestamp: Boolean = true,
    val timestampMillis: Long? = null,
    val soundUri: String? = null,
    val category: String? = null,
    val visibility: Int = 1,
    val color: Int? = null,
    val number: Int? = null,
    val ticker: String? = null,
    val groupKey: String? = null,
    val isGroupSummary: Boolean = false,
    val groupAlertBehavior: Int = 0,
    val sortKey: String? = null,
    val onlyAlertOnce: Boolean = false,
    val localOnly: Boolean = false,
    val silent: Boolean = false,
    val usesChronometer: Boolean = false,
    val timeoutAfterMillis: Long? = null,
    val progress: NotificationProgress? = null,
    val style: NotificationStyle = NotificationStyle.Default
)

