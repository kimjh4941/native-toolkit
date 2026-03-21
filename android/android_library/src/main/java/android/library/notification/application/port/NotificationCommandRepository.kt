package android.library.notification.application.port

import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.domain.model.ActiveNotification
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationSchedule

interface NotificationCommandRepository {
    fun send(command: AndroidNotificationCommand)
    fun update(command: AndroidNotificationCommand)
    fun cancel(id: Int, tag: String? = null)
    fun cancelAll()
    fun createChannel(channel: NotificationChannel)
    fun createChannels(channels: List<NotificationChannel>)
    fun deleteChannel(channelId: String)
    fun schedule(command: AndroidNotificationCommand, schedule: NotificationSchedule): Boolean
    fun cancelScheduled(id: Int, tag: String? = null)
    fun cancelAllScheduled()
    fun restoreScheduled()
    fun getActive(): List<ActiveNotification>
    fun hasPermission(): Boolean
    fun areNotificationsEnabled(): Boolean
}

