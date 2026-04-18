package android.library.notification.data.repository

import android.content.Context
import android.library.notification.application.usecase.NotificationUseCases

fun NotificationUseCases(context: Context): NotificationUseCases =
    NotificationUseCases(NotificationRepositoryImpl(context.applicationContext))
