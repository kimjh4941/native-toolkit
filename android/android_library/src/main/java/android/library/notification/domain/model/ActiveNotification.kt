package android.library.notification.domain.model

/**
 * Information for a currently displayed notification.
 *
 * @property id Notification ID.
 * @property tag Notification tag.
 * @property channelId Channel ID.
 * @property title Notification title.
 * @property message Notification message.
 * @property isOngoing Whether the notification is ongoing.
 * @property groupKey Notification group key.
 */
data class ActiveNotification(
    val id: Int,
    val tag: String?,
    val channelId: String?,
    val title: String?,
    val message: String?,
    val isOngoing: Boolean,
    val groupKey: String?
)

