package android.library.notification.domain.model

/**
 * Individual message item used by Messaging style notifications.
 *
 * @property text Message text.
 * @property timestampMillis Message timestamp in epoch milliseconds.
 * @property senderName Sender name, or null for local user messages.
 */
data class NotificationMessage(
    val text: String,
    val timestampMillis: Long,
    val senderName: String? = null
)

