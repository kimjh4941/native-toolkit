package android.library.notification.domain.model

data class NotificationProgress(
    val max: Int,
    val current: Int,
    val indeterminate: Boolean = false
)

