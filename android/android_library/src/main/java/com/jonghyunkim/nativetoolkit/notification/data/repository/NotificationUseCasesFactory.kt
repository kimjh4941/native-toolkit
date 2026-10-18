package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationSettingsPort
import com.jonghyunkim.nativetoolkit.notification.application.usecase.ForegroundServiceUseCases
import com.jonghyunkim.nativetoolkit.notification.application.usecase.NotificationUseCases

private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCasesFactoryKt"

/**
 * Factory function for [NotificationUseCases].
 *
 * Builds [NotificationUseCases] with [NotificationRepositoryImpl]. The first call in a process also
 * starts discarding the schedules saved by 1.x in the background.
 *
 * @param context Context converted internally to [Context.getApplicationContext].
 */
fun NotificationUseCases(context: Context): NotificationUseCases {
    Log.d(TAG, "[NotificationUseCases] context: $context")
    LegacyScheduleCleaner.runOnceInBackground(context)
    return NotificationUseCases(NotificationRepositoryImpl(context.applicationContext))
}

/**
 * The composition root of the notification feature for the library's own presentation classes
 * (Kotlin API design 8.14). Presentation gets use cases and the in-process command conversion
 * here instead of using the data classes directly.
 */
internal object NotificationUseCasesFactory {

    private const val TAG = "com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCasesFactory"

    /**
     * Builds the use cases of the foreground services.
     *
     * @param context Any Context.
     */
    fun foregroundServiceUseCases(context: Context): ForegroundServiceUseCases {
        Log.d(TAG, "[foregroundServiceUseCases] context: $context")
        LegacyScheduleCleaner.runOnceInBackground(context)
        val repository = NotificationRepositoryImpl(context.applicationContext)
        return ForegroundServiceUseCases(commands = repository, runtime = repository)
    }

    /**
     * Builds the settings port that opens screens from [context]: from an Activity directly,
     * otherwise with `FLAG_ACTIVITY_NEW_TASK`.
     *
     * @param context The Context to open screens from.
     */
    fun settingsPort(context: Context): NotificationSettingsPort {
        Log.d(TAG, "[settingsPort] context: $context")
        return AndroidNotificationSettingsGateway(context)
    }

    /**
     * Puts [command] into an Intent that stays in this process.
     *
     * @param intent The Intent.
     * @param key The extra name.
     * @param command The command.
     */
    fun putCommand(intent: Intent, key: String, command: AndroidNotificationCommand): Intent {
        Log.d(TAG, "[putCommand] key: $key, id: ${command.content.id}, tag: ${command.content.tag}")
        return intent.putExtra(key, command.toPayload())
    }

    /**
     * Reads a command put by [putCommand], or `null`.
     *
     * @param intent The Intent.
     * @param key The extra name.
     */
    fun commandOf(intent: Intent?, key: String): AndroidNotificationCommand? {
        Log.d(TAG, "[commandOf] intent: $intent, key: $key")
        val payload = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent?.getParcelableExtra(key, AndroidNotificationCommandPayload::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent?.getParcelableExtra(key)
        }
        return payload?.toCommand()
    }
}
