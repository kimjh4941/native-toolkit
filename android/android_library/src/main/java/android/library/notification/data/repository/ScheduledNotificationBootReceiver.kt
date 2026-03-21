package android.library.notification.data.repository

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.library.notification.application.port.NotificationCommandRepository

internal class ScheduledNotificationBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val repository: NotificationCommandRepository = NotificationRepositoryImpl(context.applicationContext)
                repository.restoreScheduled()
            }
        }
    }
}
