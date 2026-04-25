package android.library.notification.presentation.call

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
import android.util.Log
import androidx.core.app.NotificationCompat

object CallStyleNotificationFactory {

    private const val TAG = "CallStyleNotificationFactory"
    private const val CALL_NOTIFICATION_ID = 1200
    private const val CALL_CHANNEL_ID = "native_toolkit_call_v3"
    private const val CALL_STYLE_SERVICE_CLASS_NAME =
        "android.library.notification.presentation.call.CallStyleForegroundService"

    fun createCommand(context: Context, type: CallStyleType): AndroidNotificationCommand {
        Log.d(TAG, "[createCommand] type: $type")
        return when (type) {
            CallStyleType.INCOMING -> createIncomingCommand(context)
            CallStyleType.ONGOING -> createOngoingCommand(context)
            CallStyleType.SCREENING -> createScreeningCommand(context)
        }
    }

    fun createChannel(): NotificationChannel {
        Log.d(TAG, "[createChannel]")
        return NotificationChannel(
            id = CALL_CHANNEL_ID,
            name = "Native Toolkit Call",
            importance = NotificationManager.IMPORTANCE_HIGH,
            description = "Foreground service CallStyle notification channel"
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
                largeIconResId = resolveAppIconResId(context),
                style = NotificationStyle.Call(
                    callType = NotificationCallType.INCOMING,
                    person = NotificationCallPerson(
                        name = "Native Toolkit Support",
                        avatarResId = resolveAppIconResId(context)
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
                        action = CallStyleForegroundService.ACTION_ANSWER_CALL
                    ),
                    declineIntent = servicePendingIntent(
                        context = context,
                        requestCode = 3103,
                        action = CallStyleForegroundService.ACTION_DECLINE_CALL
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
                largeIconResId = resolveAppIconResId(context),
                style = NotificationStyle.Call(
                    callType = NotificationCallType.ONGOING,
                    person = NotificationCallPerson(
                        name = "Native Toolkit Support",
                        avatarResId = resolveAppIconResId(context)
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
                        action = CallStyleForegroundService.ACTION_HANG_UP_CALL
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
                largeIconResId = resolveAppIconResId(context),
                style = NotificationStyle.Call(
                    callType = NotificationCallType.SCREENING,
                    person = NotificationCallPerson(
                        name = "Native Toolkit Support",
                        avatarResId = resolveAppIconResId(context)
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
                        action = CallStyleForegroundService.ACTION_ANSWER_CALL
                    ),
                    hangUpIntent = servicePendingIntent(
                        context = context,
                        requestCode = 3303,
                        action = CallStyleForegroundService.ACTION_HANG_UP_CALL
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
        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                `package` = context.packageName
                this.action = action
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

        return AndroidPendingIntentRequest(
            intent = launchIntent,
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
            intent = Intent().setClassName(context, CALL_STYLE_SERVICE_CLASS_NAME).apply {
                this.action = action
            },
            requestCode = requestCode,
            type = AndroidPendingIntentType.FOREGROUND_SERVICE,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    private fun resolveAppIconResId(context: Context): Int? {
        return context.applicationInfo.icon.takeIf { it != 0 }
    }
}
