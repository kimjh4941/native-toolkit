package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.Context
import com.jonghyunkim.nativetoolkit.notification.application.usecase.NotificationUseCases

/**
 * Factory function for [NotificationUseCases].
 *
 * Builds [NotificationUseCases] with [NotificationRepositoryImpl].
 *
 * @param context Context converted internally to [Context.getApplicationContext].
 */
fun NotificationUseCases(context: Context): NotificationUseCases =
    NotificationUseCases(NotificationRepositoryImpl(context.applicationContext))
