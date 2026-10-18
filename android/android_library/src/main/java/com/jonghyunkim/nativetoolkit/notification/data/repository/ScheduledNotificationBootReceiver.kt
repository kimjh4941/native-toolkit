package com.jonghyunkim.nativetoolkit.notification.data.repository

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationCommandRepository
import android.util.Log
import java.io.IOException

internal class ScheduledNotificationBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d(TAG, "[onReceive] intent: $intent")
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val repository: NotificationCommandRepository = NotificationRepositoryImpl(context.applicationContext)
                try {
                    repository.restoreScheduled()
                } catch (e: IOException) {
                    Log.e(TAG, "[onReceive] a saved schedule could not be written", e)
                }
                if (intent.action != Intent.ACTION_LOCKED_BOOT_COMPLETED) {
                    LegacyScheduleCleaner.runOnceInBackground(context)
                }
            }
        }
    }

    companion object {
        private const val TAG = "ScheduledNotificationBootReceiver"
    }
}
