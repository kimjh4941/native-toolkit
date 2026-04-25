package android.library.notification.presentation.progress

import android.app.Service
import android.content.pm.ServiceInfo
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.usecase.ShowNotificationUseCase
import android.library.notification.application.usecase.StartForegroundNotificationUseCase
import android.library.notification.application.usecase.StopForegroundNotificationUseCase
import android.library.notification.application.usecase.UpdateForegroundNotificationUseCase
import android.library.notification.data.repository.NotificationRepositoryImpl
import android.os.IBinder
import android.util.Log

class ProgressForegroundService : Service() {

    private val repository by lazy { NotificationRepositoryImpl(this) }
    private val showNotificationUseCase by lazy { ShowNotificationUseCase(repository) }
    private val startForegroundNotificationUseCase by lazy {
        StartForegroundNotificationUseCase(repository)
    }
    private val updateForegroundNotificationUseCase by lazy {
        UpdateForegroundNotificationUseCase(repository)
    }
    private val stopForegroundNotificationUseCase by lazy {
        StopForegroundNotificationUseCase(repository)
    }

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
                updateForegroundNotificationUseCase(this, command, progressForegroundServiceType)
            } else {
                startForegroundNotificationUseCase(this, command, progressForegroundServiceType)
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
                stopForegroundNotificationUseCase(this, removeNotification = false)
            }
            isForegroundStarted = false
            showNotificationUseCase(command)
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
                stopForegroundNotificationUseCase(this, removeNotification = true)
            }
        }
        isForegroundStarted = false
        stopSelf()
    }

    companion object {
        private const val TAG = "ProgressForegroundService"
    }
}


