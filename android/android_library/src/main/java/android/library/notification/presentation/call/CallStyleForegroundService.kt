package android.library.notification.presentation.call

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.usecase.StartForegroundNotificationUseCase
import android.library.notification.application.usecase.StopForegroundNotificationUseCase
import android.library.notification.application.usecase.UpdateForegroundNotificationUseCase
import android.library.notification.data.repository.NotificationRepositoryImpl
import android.os.Build
import android.os.IBinder
import android.util.Log

class CallStyleForegroundService : Service() {

    private val repository by lazy { NotificationRepositoryImpl(this) }
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
    private var currentType: CallStyleType = CallStyleType.INCOMING
    private val callForegroundServiceType: Int? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
        ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
    } else {
        null
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_STOP_CALL
        Log.d(TAG, "[onStartCommand] action=$action currentType=$currentType")

        when (action) {
            ACTION_START_INCOMING_CALL -> showCall(CallStyleType.INCOMING)
            ACTION_START_ONGOING_CALL -> showCall(CallStyleType.ONGOING)
            ACTION_START_SCREENING_CALL -> showCall(CallStyleType.SCREENING)
            ACTION_ANSWER_CALL -> showCall(CallStyleType.ONGOING)
            ACTION_DECLINE_CALL,
            ACTION_HANG_UP_CALL,
            ACTION_STOP_CALL -> stopCall()
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isForegroundStarted = false
        super.onDestroy()
    }

    private fun showCall(type: CallStyleType) {
        val command = CallStyleNotificationFactory.createCommand(this, type)
        currentType = type

        runCatching {
            startOrUpdateForeground(command, foregroundServiceType = callForegroundServiceType)
        }.recoverCatching { throwable ->
            Log.w(TAG, "[showCall] retry without specialUse foregroundServiceType for type=$type", throwable)
            startOrUpdateForeground(command, foregroundServiceType = null)
        }.onSuccess {
            isForegroundStarted = true
        }.onFailure { throwable ->
            Log.e(TAG, "[showCall] failed for type=$type", throwable)
            stopCall()
        }
    }

    private fun startOrUpdateForeground(
        command: AndroidNotificationCommand,
        foregroundServiceType: Int?
    ) {
        if (isForegroundStarted) {
            updateForegroundNotificationUseCase(this, command, foregroundServiceType)
        } else {
            startForegroundNotificationUseCase(this, command, foregroundServiceType)
        }
    }

    private fun stopCall() {
        Log.d(TAG, "[stopCall]")
        runCatching {
            if (isForegroundStarted) {
                stopForegroundNotificationUseCase(this, removeNotification = true)
            }
        }
        isForegroundStarted = false
        stopSelf()
    }

    companion object {
        private const val TAG = "CallStyleFgsService"

        const val ACTION_START_INCOMING_CALL = "native.toolkit.call.START_INCOMING"
        const val ACTION_START_ONGOING_CALL = "native.toolkit.call.START_ONGOING"
        const val ACTION_START_SCREENING_CALL = "native.toolkit.call.START_SCREENING"
        const val ACTION_ANSWER_CALL = "native.toolkit.call.ANSWER"
        const val ACTION_DECLINE_CALL = "native.toolkit.call.DECLINE"
        const val ACTION_HANG_UP_CALL = "native.toolkit.call.HANG_UP"
        const val ACTION_STOP_CALL = "native.toolkit.call.STOP"

        fun createIncomingStartIntent(context: Context): Intent {
            return Intent(context, CallStyleForegroundService::class.java).apply {
                action = ACTION_START_INCOMING_CALL
            }
        }

        fun createOngoingStartIntent(context: Context): Intent {
            return Intent(context, CallStyleForegroundService::class.java).apply {
                action = ACTION_START_ONGOING_CALL
            }
        }

        fun createScreeningStartIntent(context: Context): Intent {
            return Intent(context, CallStyleForegroundService::class.java).apply {
                action = ACTION_START_SCREENING_CALL
            }
        }

        fun createStopIntent(context: Context): Intent {
            return Intent(context, CallStyleForegroundService::class.java).apply {
                action = ACTION_STOP_CALL
            }
        }
    }
}
