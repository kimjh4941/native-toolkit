package com.jonghyunkim.android.nativetoolkit.example

import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.IBinder
import android.util.Log
import android.library.notification.application.usecase.StartForegroundNotificationUseCase
import android.library.notification.application.usecase.StopForegroundNotificationUseCase
import android.library.notification.application.usecase.UpdateForegroundNotificationUseCase
import android.library.notification.data.repository.NotificationRepositoryImpl

class CallStyleSampleForegroundService : Service() {

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
    private var currentSampleType: CallStyleSampleType = CallStyleSampleType.INCOMING
    private val callForegroundServiceType: Int = ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action ?: ACTION_STOP_CALL
        Log.d(TAG, "[onStartCommand] action=$action currentSampleType=$currentSampleType")

        when (action) {
            ACTION_START_INCOMING_CALL -> showSample(CallStyleSampleType.INCOMING)
            ACTION_START_ONGOING_CALL -> showSample(CallStyleSampleType.ONGOING)
            ACTION_START_SCREENING_CALL -> showSample(CallStyleSampleType.SCREENING)
            ACTION_ANSWER_CALL -> showSample(CallStyleSampleType.ONGOING)
            ACTION_DECLINE_CALL,
            ACTION_HANG_UP_CALL,
            ACTION_STOP_CALL -> stopCallSample()
        }

        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isForegroundStarted = false
        super.onDestroy()
    }

    private fun showSample(sampleType: CallStyleSampleType) {
        val command = CallStyleSampleNotificationFactory.createCommand(this, sampleType)
        currentSampleType = sampleType

        runCatching {
            startOrUpdateForeground(command, foregroundServiceType = callForegroundServiceType)
        }.recoverCatching { throwable ->
            Log.w(TAG, "[showSample] retry without specialUse foregroundServiceType for sampleType=$sampleType", throwable)
            startOrUpdateForeground(command, foregroundServiceType = null)
        }.onSuccess {
            isForegroundStarted = true
        }.onFailure { throwable ->
            Log.e(TAG, "[showSample] failed for sampleType=$sampleType", throwable)
            stopCallSample()
        }
    }

    private fun startOrUpdateForeground(
        command: android.library.notification.application.model.AndroidNotificationCommand,
        foregroundServiceType: Int?
    ) {
        if (isForegroundStarted) {
            updateForegroundNotificationUseCase(this, command, foregroundServiceType)
        } else {
            startForegroundNotificationUseCase(this, command, foregroundServiceType)
        }
    }

    private fun stopCallSample() {
        Log.d(TAG, "[stopCallSample]")
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

        const val ACTION_START_INCOMING_CALL = "native.toolkit.call.sample.START_INCOMING"
        const val ACTION_START_ONGOING_CALL = "native.toolkit.call.sample.START_ONGOING"
        const val ACTION_START_SCREENING_CALL = "native.toolkit.call.sample.START_SCREENING"
        const val ACTION_ANSWER_CALL = "native.toolkit.call.sample.ANSWER"
        const val ACTION_DECLINE_CALL = "native.toolkit.call.sample.DECLINE"
        const val ACTION_HANG_UP_CALL = "native.toolkit.call.sample.HANG_UP"
        const val ACTION_STOP_CALL = "native.toolkit.call.sample.STOP"

        fun createIncomingStartIntent(context: Context): Intent {
            return Intent(context, CallStyleSampleForegroundService::class.java).apply {
                action = ACTION_START_INCOMING_CALL
            }
        }

        fun createOngoingStartIntent(context: Context): Intent {
            return Intent(context, CallStyleSampleForegroundService::class.java).apply {
                action = ACTION_START_ONGOING_CALL
            }
        }

        fun createScreeningStartIntent(context: Context): Intent {
            return Intent(context, CallStyleSampleForegroundService::class.java).apply {
                action = ACTION_START_SCREENING_CALL
            }
        }

        fun createStopIntent(context: Context): Intent {
            return Intent(context, CallStyleSampleForegroundService::class.java).apply {
                action = ACTION_STOP_CALL
            }
        }
    }
}
