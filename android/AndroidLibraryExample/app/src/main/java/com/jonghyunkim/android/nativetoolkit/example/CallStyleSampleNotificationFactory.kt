package com.jonghyunkim.android.nativetoolkit.example

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.library.notification.application.model.AndroidNotificationCallPlatformOptions
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidPendingIntentType
import android.library.notification.domain.model.NotificationCallPerson
import android.library.notification.domain.model.NotificationCallType
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationStyle
import androidx.core.app.NotificationCompat
import kotlin.jvm.java

internal enum class CallStyleSampleType {
    INCOMING,
    ONGOING,
    SCREENING
}

internal object CallStyleSampleNotificationFactory {

    private const val CALL_NOTIFICATION_ID = 1200
    private const val CALL_CHANNEL_ID = "native_toolkit_call_sample"

    fun createCommand(context: Context, sampleType: CallStyleSampleType): AndroidNotificationCommand {
        return when (sampleType) {
            CallStyleSampleType.INCOMING -> createIncomingCommand(context)
            CallStyleSampleType.ONGOING -> createOngoingCommand(context)
            CallStyleSampleType.SCREENING -> createScreeningCommand(context)
        }
    }

    fun createChannel(): NotificationChannel {
        return NotificationChannel(
            id = CALL_CHANNEL_ID,
            name = "Native Toolkit Call Sample",
            importance = NotificationManager.IMPORTANCE_HIGH,
            description = "Foreground service CallStyle sample channel"
        )
    }

    private fun createIncomingCommand(context: Context): AndroidNotificationCommand {
        return AndroidNotificationCommand(
            content = NotificationContent(
                id = CALL_NOTIFICATION_ID,
                title = "Incoming call",
                message = "Native Toolkit Support is calling",
                channel = createChannel(),
                category = NotificationCompat.CATEGORY_CALL,
                priority = NotificationCompat.PRIORITY_HIGH,
                ongoing = true,
                autoCancel = false,
                subText = "Call / Incoming",
                largeIconResId = R.mipmap.ic_launcher_round,
                style = NotificationStyle.Call(
                    callType = NotificationCallType.INCOMING,
                    person = NotificationCallPerson(
                        name = "Native Toolkit Support",
                        avatarResId = R.mipmap.ic_launcher_round
                    ),
                    isVideo = true,
                    verificationText = "Verified sample caller"
                )
            ),
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = activityPendingIntent(
                    context = context,
                    requestCode = 3100,
                    action = "native.toolkit.call.incoming.open"
                ),
                fullScreenIntent = activityPendingIntent(
                    context = context,
                    requestCode = 3101,
                    action = "native.toolkit.call.incoming.fullscreen"
                ),
                callStyleOptions = AndroidNotificationCallPlatformOptions(
                    answerIntent = servicePendingIntent(
                        context = context,
                        requestCode = 3102,
                        action = CallStyleSampleForegroundService.ACTION_ANSWER_CALL
                    ),
                    declineIntent = servicePendingIntent(
                        context = context,
                        requestCode = 3103,
                        action = CallStyleSampleForegroundService.ACTION_DECLINE_CALL
                    )
                )
            )
        )
    }

    private fun createOngoingCommand(context: Context): AndroidNotificationCommand {
        return AndroidNotificationCommand(
            content = NotificationContent(
                id = CALL_NOTIFICATION_ID,
                title = "Call in progress",
                message = "Native Toolkit Support connected",
                channel = createChannel(),
                category = NotificationCompat.CATEGORY_CALL,
                priority = NotificationCompat.PRIORITY_DEFAULT,
                ongoing = true,
                autoCancel = false,
                subText = "Call / Ongoing",
                usesChronometer = true,
                largeIconResId = R.mipmap.ic_launcher_round,
                style = NotificationStyle.Call(
                    callType = NotificationCallType.ONGOING,
                    person = NotificationCallPerson(
                        name = "Native Toolkit Support",
                        avatarResId = R.mipmap.ic_launcher_round
                    ),
                    isVideo = true,
                    verificationText = "Connected sample caller"
                )
            ),
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = activityPendingIntent(
                    context = context,
                    requestCode = 3200,
                    action = "native.toolkit.call.ongoing.open"
                ),
                callStyleOptions = AndroidNotificationCallPlatformOptions(
                    hangUpIntent = servicePendingIntent(
                        context = context,
                        requestCode = 3201,
                        action = CallStyleSampleForegroundService.ACTION_HANG_UP_CALL
                    )
                )
            )
        )
    }

    private fun createScreeningCommand(context: Context): AndroidNotificationCommand {
        return AndroidNotificationCommand(
            content = NotificationContent(
                id = CALL_NOTIFICATION_ID,
                title = "Screening call",
                message = "Review this call request from Native Toolkit Support",
                channel = createChannel(),
                category = NotificationCompat.CATEGORY_CALL,
                priority = NotificationCompat.PRIORITY_HIGH,
                ongoing = true,
                autoCancel = false,
                subText = "Call / Screening",
                largeIconResId = R.mipmap.ic_launcher_round,
                style = NotificationStyle.Call(
                    callType = NotificationCallType.SCREENING,
                    person = NotificationCallPerson(
                        name = "Native Toolkit Support",
                        avatarResId = R.mipmap.ic_launcher_round
                    ),
                    isVideo = false,
                    verificationText = "Unknown caller screening sample"
                )
            ),
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = activityPendingIntent(
                    context = context,
                    requestCode = 3300,
                    action = "native.toolkit.call.screening.open"
                ),
                fullScreenIntent = activityPendingIntent(
                    context = context,
                    requestCode = 3301,
                    action = "native.toolkit.call.screening.fullscreen"
                ),
                callStyleOptions = AndroidNotificationCallPlatformOptions(
                    answerIntent = servicePendingIntent(
                        context = context,
                        requestCode = 3302,
                        action = CallStyleSampleForegroundService.ACTION_ANSWER_CALL
                    ),
                    hangUpIntent = servicePendingIntent(
                        context = context,
                        requestCode = 3303,
                        action = CallStyleSampleForegroundService.ACTION_HANG_UP_CALL
                    )
                )
            )
        )
    }

    private fun activityPendingIntent(
        context: Context,
        requestCode: Int,
        action: String
    ): AndroidPendingIntentRequest {
        return AndroidPendingIntentRequest(
            intent = Intent(context, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            requestCode = requestCode,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun servicePendingIntent(
        context: Context,
        requestCode: Int,
        action: String
    ): AndroidPendingIntentRequest {
        return AndroidPendingIntentRequest(
            intent = Intent(context, CallStyleSampleForegroundService::class.java).apply {
                this.action = action
            },
            requestCode = requestCode,
            type = AndroidPendingIntentType.FOREGROUND_SERVICE,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    }
}

