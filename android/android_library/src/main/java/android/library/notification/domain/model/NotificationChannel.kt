package android.library.notification.domain.model

/**
 * Notification channel settings.
 *
 * @property id Channel ID.
 * @property name Display name for the channel.
 * @property importance Importance constant from [android.app.NotificationManager].
 * @property lockscreenVisibility Visibility constant from [android.app.Notification].
 * @property groupId Channel group ID, or null if not grouped.
 * @property groupName Channel group name, or null if not grouped.
 */
data class NotificationChannel(
    val id: String = "default_channel",
    val name: String = "Default Channel",
    val importance: Int = 3,
    val description: String? = null,
    val showBadge: Boolean = true,
    val enableLights: Boolean = true,
    val lightColor: Int? = null,
    val enableVibration: Boolean = true,
    val vibrationPattern: List<Long>? = null,
    val soundUri: String? = null,
    val lockscreenVisibility: Int = 1,
    val groupId: String? = null,
    val groupName: String? = null
)

