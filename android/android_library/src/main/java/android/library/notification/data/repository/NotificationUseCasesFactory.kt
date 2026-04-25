package android.library.notification.data.repository

import android.content.Context
import android.library.notification.application.usecase.NotificationUseCases

/**
 * Factory function for [NotificationUseCases].
 *
 * Builds [NotificationUseCases] with [NotificationRepositoryImpl].
 *
 * @param context Context converted internally to [Context.getApplicationContext].
 */
fun NotificationUseCases(context: Context): NotificationUseCases =
    NotificationUseCases(NotificationRepositoryImpl(context.applicationContext))
