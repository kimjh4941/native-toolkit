package android.library.notification.data.repository

import android.os.Parcelable
import kotlinx.parcelize.Parcelize

@Parcelize
internal data class NotificationSchedulePayload(
    val triggerAtMillis: Long,
    val exact: Boolean,
    val allowWhileIdle: Boolean,
    val persistAcrossBoot: Boolean,
    val alarmType: Int
) : Parcelable

