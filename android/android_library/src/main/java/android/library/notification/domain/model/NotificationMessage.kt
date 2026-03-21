package android.library.notification.domain.model

data class NotificationMessage(
    val text: String,
    val timestampMillis: Long,
    val senderName: String? = null
)

