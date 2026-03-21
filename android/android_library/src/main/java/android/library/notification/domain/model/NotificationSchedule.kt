package android.library.notification.domain.model

data class NotificationSchedule(
    val triggerAtMillis: Long,
    val exact: Boolean = true,
    val allowWhileIdle: Boolean = true,
    val persistAcrossBoot: Boolean = true,
    val alarmType: Int = 0
) {
    init {
        require(triggerAtMillis > 0L) { "triggerAtMillis must be greater than 0." }
    }
}

