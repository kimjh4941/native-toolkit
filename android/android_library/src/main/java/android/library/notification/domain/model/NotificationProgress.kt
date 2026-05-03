package android.library.notification.domain.model

/**
 * Progress bar configuration for notifications.
 *
 * @property max Maximum value.
 * @property current Current value.
 * @property indeterminate Whether progress is indeterminate. If true, max and current are ignored.
 */
data class NotificationProgress(
    val max: Int,
    val current: Int,
    val indeterminate: Boolean = false
)

