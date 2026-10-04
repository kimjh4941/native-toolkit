package com.jonghyunkim.nativetoolkit.notification.presentation.progress

import android.app.Service
import android.content.pm.ServiceInfo
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCasesFactory
import android.os.IBinder
import android.util.Log

/**
 * Service that displays and updates progress notifications in foreground mode.
 *
 * Handles start, update, complete, and stop phases from intents sent by [ProgressForegroundNotifications].
 */
class ProgressForegroundService : Service() {

    private val useCases by lazy { NotificationUseCasesFactory.foregroundServiceUseCases(this) }

    private var isForegroundStarted: Boolean = false
    private val progressForegroundServiceType: Int = ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC

    override fun onBind(intent: android.content.Intent?): IBinder? {
        Log.d(TAG, "[onBind] intent: $intent")
        return null
    }

    override fun onStartCommand(intent: android.content.Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ProgressForegroundServiceIntents.ACTION_STOP
        Log.d(TAG, "[onStartCommand] action=$action isForegroundStarted=$isForegroundStarted")

        when (action) {
            ProgressForegroundServiceIntents.ACTION_START,
            ProgressForegroundServiceIntents.ACTION_UPDATE -> {
                val command = ProgressForegroundServiceIntents.extractCommand(intent)
                if (command == null) {
                    Log.w(TAG, "[onStartCommand] missing command for action=$action")
                    stopProgress()
                } else {
                    showProgress(command)
                }
            }

            ProgressForegroundServiceIntents.ACTION_COMPLETE -> {
                val command = ProgressForegroundServiceIntents.extractCommand(intent)
                if (command == null) {
                    Log.w(TAG, "[onStartCommand] missing completion command")
                    stopProgress()
                } else {
                    completeProgress(command)
                }
            }

            ProgressForegroundServiceIntents.ACTION_STOP -> stopProgress()
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        Log.d(TAG, "[onDestroy]")
        isForegroundStarted = false
        super.onDestroy()
    }

    private fun showProgress(command: AndroidNotificationCommand) {
        Log.d(TAG, "[showProgress] id: ${command.content.id}")
        runCatching {
            if (isForegroundStarted) {
                useCases.updateForeground(this, command, progressForegroundServiceType)
            } else {
                useCases.startForeground(this, command, progressForegroundServiceType)
                isForegroundStarted = true
            }
        }.onFailure { throwable ->
            Log.e(TAG, "[showProgress] failed for id=${command.content.id}", throwable)
            stopProgress()
        }
    }

    private fun completeProgress(command: AndroidNotificationCommand) {
        Log.d(TAG, "[completeProgress] id: ${command.content.id}")
        runCatching {
            if (isForegroundStarted) {
                useCases.stopForeground(this, removeNotification = false)
            }
            isForegroundStarted = false
            useCases.show(command)
        }.onFailure { throwable ->
            Log.e(TAG, "[completeProgress] failed for id=${command.content.id}", throwable)
            stopProgress()
            return
        }

        stopSelf()
    }

    private fun stopProgress() {
        Log.d(TAG, "[stopProgress]")
        runCatching {
            if (isForegroundStarted) {
                useCases.stopForeground(this, removeNotification = true)
            }
        }
        isForegroundStarted = false
        stopSelf()
    }

    companion object {
        private const val TAG = "ProgressForegroundService"
    }
}


