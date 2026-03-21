package android.library.notification.domain.model

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

