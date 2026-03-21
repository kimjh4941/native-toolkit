package android.library.notification.domain.model

data class ActiveNotification(
    val id: Int,
    val tag: String?,
    val channelId: String?,
    val title: String?,
    val message: String?,
    val isOngoing: Boolean,
    val groupKey: String?
)

