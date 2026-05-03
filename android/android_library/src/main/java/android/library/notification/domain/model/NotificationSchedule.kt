package android.library.notification.domain.model

/**
 * Scheduling configuration for notifications.
 *
 * @property triggerAtMillis Trigger time in epoch milliseconds. Must be greater than 0.
 * @property exact Whether to use an exact alarm. If false, an inexact alarm is used.
 * @property allowWhileIdle Whether the alarm can fire during Doze mode.
 * @property persistAcrossBoot Whether to restore this schedule after device reboot.
 * @property alarmType Alarm type constant from [android.app.AlarmManager].
 */
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

