package android.library.notification.presentation.progress

import android.content.Context
import android.library.notification.application.model.AndroidNotificationCommand
import android.util.Log
import androidx.core.content.ContextCompat

object ProgressForegroundNotifications {

    private const val TAG = "ProgressForegroundNotifications"

    fun start(context: Context, command: AndroidNotificationCommand) {
        Log.d(TAG, "[start] id: ${command.content.id}")
        ContextCompat.startForegroundService(
            context,
            ProgressForegroundServiceIntents.createStartIntent(context, command)
        )
    }

    fun update(context: Context, command: AndroidNotificationCommand) {
        Log.d(TAG, "[update] id: ${command.content.id}")
        context.startService(ProgressForegroundServiceIntents.createUpdateIntent(context, command))
    }

    fun complete(context: Context, command: AndroidNotificationCommand) {
        Log.d(TAG, "[complete] id: ${command.content.id}")
        context.startService(ProgressForegroundServiceIntents.createCompleteIntent(context, command))
    }

    fun stop(context: Context) {
        Log.d(TAG, "[stop]")
        context.startService(ProgressForegroundServiceIntents.createStopIntent(context))
    }
}
