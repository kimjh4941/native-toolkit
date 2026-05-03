package android.library.notification.data.repository

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.library.notification.NotificationShownSupport
import android.util.Log
import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.data.repository.NotificationSchedulerSupport.parcelableExtra

internal class ScheduledNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "[onReceive] intent: $intent")
        val command = intent.parcelableExtra<AndroidNotificationCommandPayload>(EXTRA_NOTIFICATION_COMMAND)
            ?.toCommand()
            ?: return

        val repository: NotificationCommandRepository = NotificationRepositoryImpl(context.applicationContext)
        repository.send(command)
        NotificationSchedulerSupport.remove(context.applicationContext, command.content.id, command.content.tag)

        NotificationShownSupport.shownListener?.onNotificationShown(
            command.content.id,
            command.content.tag,
            command.content.channel.id
        )
    }

    companion object {
        private const val TAG = "ScheduledNotificationReceiver"
    }
}
