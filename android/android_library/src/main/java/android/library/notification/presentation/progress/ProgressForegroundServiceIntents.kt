package android.library.notification.presentation.progress

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Parcelable
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.data.repository.AndroidNotificationCommandPayload
import android.library.notification.data.repository.toCommand
import android.library.notification.data.repository.toPayload

object ProgressForegroundServiceIntents {

    const val ACTION_START = "native.toolkit.progress.fgs.START"
    const val ACTION_UPDATE = "native.toolkit.progress.fgs.UPDATE"
    const val ACTION_COMPLETE = "native.toolkit.progress.fgs.COMPLETE"
    const val ACTION_STOP = "native.toolkit.progress.fgs.STOP"

    private const val EXTRA_COMMAND = "native.toolkit.progress.fgs.extra.COMMAND"
    private const val SERVICE_CLASS_NAME =
        "android.library.notification.presentation.progress.ProgressForegroundService"

    fun createStartIntent(context: Context, command: AndroidNotificationCommand): Intent {
        return createCommandIntent(context, ACTION_START, command)
    }

    fun createUpdateIntent(context: Context, command: AndroidNotificationCommand): Intent {
        return createCommandIntent(context, ACTION_UPDATE, command)
    }

    fun createCompleteIntent(context: Context, command: AndroidNotificationCommand): Intent {
        return createCommandIntent(context, ACTION_COMPLETE, command)
    }

    fun createStopIntent(context: Context): Intent {
        return Intent().setClassName(context, SERVICE_CLASS_NAME).apply {
            action = ACTION_STOP
        }
    }

    internal fun extractCommand(intent: Intent?): AndroidNotificationCommand? {
        val payload = intent?.parcelableExtra<AndroidNotificationCommandPayload>(EXTRA_COMMAND)
        return payload?.toCommand()
    }

    private fun createCommandIntent(
        context: Context,
        action: String,
        command: AndroidNotificationCommand
    ): Intent {
        return Intent().setClassName(context, SERVICE_CLASS_NAME).apply {
            this.action = action
            putExtra(EXTRA_COMMAND, command.toPayload())
        }
    }
}

private inline fun <reified T : Parcelable> Intent.parcelableExtra(key: String): T? {
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        getParcelableExtra(key, T::class.java)
    } else {
        @Suppress("DEPRECATION")
        getParcelableExtra(key)
    }
}

