package com.jonghyunkim.nativetoolkit.notification.presentation.progress

import android.content.Context
import android.content.Intent
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCasesFactory

/**
 * Intent factory for [ProgressForegroundService].
 *
 * Provides action constants and intent creation methods.
 */
object ProgressForegroundServiceIntents {

    /** Action to start the service. */
    const val ACTION_START = "native.toolkit.progress.fgs.START"
    /** Action to update progress. */
    const val ACTION_UPDATE = "native.toolkit.progress.fgs.UPDATE"
    /** Action to complete progress, stop foreground mode, and show completion notification. */
    const val ACTION_COMPLETE = "native.toolkit.progress.fgs.COMPLETE"
    /** Action to stop the service. */
    const val ACTION_STOP = "native.toolkit.progress.fgs.STOP"

    private const val EXTRA_COMMAND = "native.toolkit.progress.fgs.extra.COMMAND"
    private const val SERVICE_CLASS_NAME =
        "com.jonghyunkim.nativetoolkit.notification.presentation.progress.ProgressForegroundService"

    /**
     * Creates an intent for start action.
     */
    fun createStartIntent(context: Context, command: AndroidNotificationCommand): Intent {
        return createCommandIntent(context, ACTION_START, command)
    }

    /**
     * Creates an intent for update action.
     */
    fun createUpdateIntent(context: Context, command: AndroidNotificationCommand): Intent {
        return createCommandIntent(context, ACTION_UPDATE, command)
    }

    /**
     * Creates an intent for completion action.
     */
    fun createCompleteIntent(context: Context, command: AndroidNotificationCommand): Intent {
        return createCommandIntent(context, ACTION_COMPLETE, command)
    }

    /**
     * Creates an intent for stop action.
     */
    fun createStopIntent(context: Context): Intent {
        return Intent().setClassName(context, SERVICE_CLASS_NAME).apply {
            action = ACTION_STOP
        }
    }

    internal fun extractCommand(intent: Intent?): AndroidNotificationCommand? =
        NotificationUseCasesFactory.commandOf(intent, EXTRA_COMMAND)

    private fun createCommandIntent(
        context: Context,
        action: String,
        command: AndroidNotificationCommand
    ): Intent {
        val intent = Intent().setClassName(context, SERVICE_CLASS_NAME).setAction(action)
        return NotificationUseCasesFactory.putCommand(intent, EXTRA_COMMAND, command)
    }
}
