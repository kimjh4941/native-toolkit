package android.library.notification.presentation.progress

import android.content.Context
import android.library.notification.application.model.AndroidNotificationCommand
import androidx.core.content.ContextCompat

object ProgressForegroundNotifications {

    fun start(context: Context, command: AndroidNotificationCommand) {
        ContextCompat.startForegroundService(
            context,
            ProgressForegroundServiceIntents.createStartIntent(context, command)
        )
    }

    fun update(context: Context, command: AndroidNotificationCommand) {
        context.startService(ProgressForegroundServiceIntents.createUpdateIntent(context, command))
    }

    fun complete(context: Context, command: AndroidNotificationCommand) {
        context.startService(ProgressForegroundServiceIntents.createCompleteIntent(context, command))
    }

    fun stop(context: Context) {
        context.startService(ProgressForegroundServiceIntents.createStopIntent(context))
    }
}

