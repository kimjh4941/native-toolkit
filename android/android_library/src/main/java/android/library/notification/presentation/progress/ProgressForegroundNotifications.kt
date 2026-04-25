package android.library.notification.presentation.progress

import android.content.Context
import android.library.notification.application.model.AndroidNotificationCommand
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Entry point for progress foreground notification operations.
 *
 * Works as a facade that sends intents to [ProgressForegroundService].
 */
object ProgressForegroundNotifications {

    private const val TAG = "ProgressForegroundNotifications"

    /**
     * Starts progress foreground notification flow.
     */
    fun start(context: Context, command: AndroidNotificationCommand) {
        Log.d(TAG, "[start] id: ${command.content.id}")
        ContextCompat.startForegroundService(
            context,
            ProgressForegroundServiceIntents.createStartIntent(context, command)
        )
    }

    /**
     * Updates a progress notification.
     */
    fun update(context: Context, command: AndroidNotificationCommand) {
        Log.d(TAG, "[update] id: ${command.content.id}")
        context.startService(ProgressForegroundServiceIntents.createUpdateIntent(context, command))
    }

    /**
     * Marks progress as complete, stops foreground mode, and shows the completion notification.
     */
    fun complete(context: Context, command: AndroidNotificationCommand) {
        Log.d(TAG, "[complete] id: ${command.content.id}")
        context.startService(ProgressForegroundServiceIntents.createCompleteIntent(context, command))
    }

    /**
     * Stops progress foreground notification flow.
     */
    fun stop(context: Context) {
        Log.d(TAG, "[stop]")
        context.startService(ProgressForegroundServiceIntents.createStopIntent(context))
    }
}
