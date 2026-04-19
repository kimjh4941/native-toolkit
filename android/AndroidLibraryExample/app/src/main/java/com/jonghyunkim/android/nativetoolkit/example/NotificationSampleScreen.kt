package com.jonghyunkim.android.nativetoolkit.example

import android.app.PendingIntent
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.library.notification.application.model.AndroidNotificationAction
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidPendingIntentType
import android.library.notification.data.repository.NotificationUseCases
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationCustomViewStyleData
import android.library.notification.domain.model.NotificationMessage
import android.library.notification.domain.model.NotificationProgress
import android.library.notification.domain.model.NotificationSchedule
import android.library.notification.domain.model.NotificationStyle
import android.library.notification.presentation.call.CallStyleForegroundService
import android.library.notification.presentation.call.CallStyleNotificationFactory
import android.library.notification.presentation.call.CallStyleType
import android.library.notification.presentation.permission.NotificationPermissionHelper
import android.library.notification.presentation.progress.ProgressForegroundNotifications
import android.util.Log
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

const val TAG = "NotificationSampleScreen"
private const val ACTION_OPEN_NOTIFICATION_SAMPLE = "native.toolkit.notification.open"
private const val ACTION_OPEN_GROUPING_SAMPLE = "native.toolkit.notification.grouping.open"
private const val ACTION_OPEN_FULL_SCREEN_SAMPLE = "native.toolkit.notification.fullscreen.open"
private const val GROUP_SAMPLE_KEY = "native.toolkit.grouping.sample"
private const val ACTION_SAMPLE_NOTIFICATION_ID = 1112

@Composable
fun NotificationSampleScreen(
    modifier: Modifier = Modifier,
    activity: AppCompatActivity,
    permissionHelper: NotificationPermissionHelper,
    onBack: () -> Unit
) {
    Log.d(TAG, "[NotificationSampleScreen] modifier: $modifier, activity: $activity, permissionHelper: $permissionHelper, onBack: $onBack")
    val useCases = remember(activity) { NotificationUseCases(activity) }

    var statusText by remember {
        mutableStateOf("通知サンプルを確認できます。まずは権限状態を確認してください。")
    }

    DisposableEffect(activity) {
        NotificationActionReceiver.isSampleScreenActive = true

        val actionButtonReceiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context?, intent: Intent?) {
                if (intent?.action != NotificationActionReceiver.ACTION_NOTIFICATION_BUTTON_INTERNAL) {
                    return
                }

                val actionId = intent.getStringExtra(NotificationActionReceiver.EXTRA_ACTION_ID).orEmpty()
                val actionLabel = intent.getStringExtra(NotificationActionReceiver.EXTRA_ACTION_LABEL).orEmpty()
                val notificationId = intent.getIntExtra(NotificationActionReceiver.EXTRA_NOTIFICATION_ID, -1)
                statusText = "✅ Action button押下: $actionLabel (id=$actionId, notificationId=$notificationId)"
            }
        }

        val filter = IntentFilter(NotificationActionReceiver.ACTION_NOTIFICATION_BUTTON_INTERNAL)
        ContextCompat.registerReceiver(
            activity,
            actionButtonReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED
        )

        onDispose {
            NotificationActionReceiver.isSampleScreenActive = false
            runCatching { activity.unregisterReceiver(actionButtonReceiver) }
        }
    }

    val sampleChannel = remember {
        NotificationChannel(
            id = "native_toolkit_sample",
            name = "Native Toolkit Sample",
            description = "Notification sample channel"
        )
    }
    val callSampleChannel = remember { CallStyleNotificationFactory.createChannel() }
    val progressForegroundSampleChannel = remember {
        NotificationChannel(
            id = "native_toolkit_progress_fgs",
            name = "Native Toolkit Progress FGS",
            importance = NotificationManager.IMPORTANCE_LOW,
            description = "Foreground service progress sample channel"
        )
    }
    val interactionGroupingSampleChannel = remember {
        NotificationChannel(
            id = "native_toolkit_interaction_grouping",
            name = "Native Toolkit Interaction & Grouping",
            description = "Interaction and grouping notification sample channel"
        )
    }
    val fullScreenSampleChannel = remember {
        NotificationChannel(
            id = "native_toolkit_fullscreen_sample",
            name = "Native Toolkit FullScreen Sample",
            importance = NotificationManager.IMPORTANCE_HIGH,
            description = "Reference fullScreenIntent notification sample channel"
        )
    }
    val scheduleSampleChannel = remember {
        NotificationChannel(
            id = "native_toolkit_schedule_high",
            name = "Native Toolkit Schedule High Priority",
            importance = NotificationManager.IMPORTANCE_HIGH,
            description = "High-priority scheduled notification sample channel"
        )
    }

    fun ensureChannel(channel: NotificationChannel) {
        Log.d(TAG, "[ensureChannel] channelId=${channel.id}")
        useCases.createChannel(channel)
            .onFailure { Log.w(TAG, "[ensureChannel] failed: channelId=${channel.id}", it) }
    }

    fun createChannel(channel: NotificationChannel = sampleChannel) {
        Log.d(TAG, "[createChannel] channelId=${channel.id}")
        ensureChannel(channel)
        statusText = "✅ チャンネルを作成しました: ${channel.id}"
    }

    fun buildActivityPendingIntentRequest(
        targetActivityClass: Class<*>,
        requestCode: Int,
        action: String
    ): AndroidPendingIntentRequest {
        return AndroidPendingIntentRequest(
            intent = Intent(activity, targetActivityClass).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            requestCode = requestCode,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    fun buildActivityPendingIntentRequest(requestCode: Int, action: String): AndroidPendingIntentRequest {
        return buildActivityPendingIntentRequest(
            targetActivityClass = MainActivity::class.java,
            requestCode = requestCode,
            action = action
        )
    }

    fun buildBroadcastPendingIntentRequest(intent: Intent, requestCode: Int): AndroidPendingIntentRequest {
        return AndroidPendingIntentRequest(
            intent = intent,
            requestCode = requestCode,
            type = AndroidPendingIntentType.BROADCAST,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    fun buildDefaultOpenAppPlatformOptions(requestCode: Int): AndroidNotificationPlatformOptions {
        return AndroidNotificationPlatformOptions(
            contentIntent = buildActivityPendingIntentRequest(
                requestCode = requestCode,
                action = ACTION_OPEN_NOTIFICATION_SAMPLE
            )
        )
    }

    fun buildMediaActions(baseRequestCode: Int): List<AndroidNotificationAction> {
        return listOf(
            AndroidNotificationAction(
                title = "Previous",
                pendingIntent = buildActivityPendingIntentRequest(baseRequestCode, "native.toolkit.media.previous"),
                iconResId = android.R.drawable.ic_media_previous
            ),
            AndroidNotificationAction(
                title = "Play",
                pendingIntent = buildActivityPendingIntentRequest(baseRequestCode + 1, "native.toolkit.media.play"),
                iconResId = android.R.drawable.ic_media_play
            ),
            AndroidNotificationAction(
                title = "Next",
                pendingIntent = buildActivityPendingIntentRequest(baseRequestCode + 2, "native.toolkit.media.next"),
                iconResId = android.R.drawable.ic_media_next
            )
        )
    }

    fun buildAcceptDeclineActions(baseRequestCode: Int): List<AndroidNotificationAction> {
        return listOf(
            AndroidNotificationAction(
                title = "Accept",
                pendingIntent = buildBroadcastPendingIntentRequest(
                    intent = NotificationActionReceiver.createIntent(
                        context = activity,
                        actionId = "accept",
                        actionLabel = "Accept",
                        notificationId = ACTION_SAMPLE_NOTIFICATION_ID
                    ),
                    requestCode = baseRequestCode
                ),
                iconResId = android.R.drawable.ic_menu_call
            ),
            AndroidNotificationAction(
                title = "Decline",
                pendingIntent = buildBroadcastPendingIntentRequest(
                    intent = NotificationActionReceiver.createIntent(
                        context = activity,
                        actionId = "decline",
                        actionLabel = "Decline",
                        notificationId = ACTION_SAMPLE_NOTIFICATION_ID
                    ),
                    requestCode = baseRequestCode + 1
                ),
                iconResId = android.R.drawable.ic_menu_close_clear_cancel
            )
        )
    }

    fun buildStyleCommand(
        id: Int,
        title: String,
        message: String,
        style: NotificationStyle,
        channel: NotificationChannel = sampleChannel,
        subText: String? = null,
        largeIconResId: Int? = null,
        number: Int? = null,
        category: String? = null,
        priority: Int = NotificationCompat.PRIORITY_DEFAULT,
        ongoing: Boolean = false,
        autoCancel: Boolean = true,
        progress: NotificationProgress? = null,
        groupKey: String? = null,
        isGroupSummary: Boolean = false,
        groupAlertBehavior: Int = 0,
        sortKey: String? = null,
        platformOptions: AndroidNotificationPlatformOptions = AndroidNotificationPlatformOptions()
    ): AndroidNotificationCommand {
        val resolvedPlatformOptions = if (platformOptions.contentIntent == null) {
            platformOptions.copy(
                contentIntent = buildDefaultOpenAppPlatformOptions(requestCode = id).contentIntent
            )
        } else {
            platformOptions
        }

        return AndroidNotificationCommand(
            content = NotificationContent(
                id = id,
                title = title,
                message = message,
                channel = channel,
                subText = subText,
                largeIconResId = largeIconResId,
                number = number,
                category = category,
                priority = priority,
                ongoing = ongoing,
                autoCancel = autoCancel,
                progress = progress,
                groupKey = groupKey,
                isGroupSummary = isGroupSummary,
                groupAlertBehavior = groupAlertBehavior,
                sortKey = sortKey,
                style = style
            ),
            platformOptions = resolvedPlatformOptions
        )
    }

    fun buildDefaultStyleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1001,
            title = "Native Toolkit",
            message = "Default style notification sample",
            style = NotificationStyle.Default,
            subText = "Default"
        )
    }

    fun buildBigTextStyleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1002,
            title = "Native Toolkit",
            message = "BigText style notification sample",
            style = NotificationStyle.BigText(
                bigText = "This is a BigText notification sample from Native Toolkit Example. Expand the notification to verify the full body text rendering.",
                summaryText = "BigText",
                bigContentTitle = "BigText Style"
            ),
            subText = "BigText"
        )
    }

    fun buildInboxStyleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1003,
            title = "Native Toolkit",
            message = "Inbox style notification sample",
            style = NotificationStyle.Inbox(
                lines = listOf(
                    "• Permission status checked",
                    "• Channel created successfully",
                    "• Immediate notification sent",
                    "• Scheduled notification ready"
                ),
                summaryText = "4 sample events",
                bigContentTitle = "Inbox Style"
            ),
            subText = "Inbox",
            number = 4
        )
    }

    fun buildBigPictureStyleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1004,
            title = "Native Toolkit",
            message = "BigPicture style notification sample",
            style = NotificationStyle.BigPicture(
                pictureResId = R.mipmap.ic_launcher,
                summaryText = "Launcher image preview",
                bigContentTitle = "BigPicture Style",
                largeIconResId = R.mipmap.ic_launcher_round
            ),
            subText = "BigPicture",
            largeIconResId = R.mipmap.ic_launcher_round
        )
    }

    fun buildMessagingStyleCommand(): AndroidNotificationCommand {
        val now = System.currentTimeMillis()
        return buildStyleCommand(
            id = 1005,
            title = "Native Toolkit Team",
            message = "Messaging style notification sample",
            style = NotificationStyle.Messaging(
                userDisplayName = "You",
                conversationTitle = "Native Toolkit Example",
                isGroupConversation = true,
                messages = listOf(
                    NotificationMessage(
                        text = "Can you verify the notification styles?",
                        timestampMillis = now - 120_000L,
                        senderName = "Alex"
                    ),
                    NotificationMessage(
                        text = "Sure, BigText / Inbox / BigPicture / Messaging are ready.",
                        timestampMillis = now - 60_000L,
                        senderName = "Jordan"
                    ),
                    NotificationMessage(
                        text = "Confirmed. This is the Messaging sample.",
                        timestampMillis = now,
                        senderName = "You"
                    )
                )
            ),
            subText = "Messaging",
            number = 3
        )
    }

    fun buildMediaStyleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1006,
            title = "Native Toolkit Player",
            message = "Media style notification sample",
            style = NotificationStyle.Media(compactActionIndices = listOf(0, 1, 2)),
            subText = "Media",
            largeIconResId = R.mipmap.ic_launcher_round,
            category = NotificationCompat.CATEGORY_TRANSPORT,
            priority = NotificationCompat.PRIORITY_LOW,
            ongoing = true,
            autoCancel = false,
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(2000, "native.toolkit.media.open"),
                actions = buildMediaActions(2010)
            )
        )
    }

    fun buildDecoratedCustomViewStyleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1007,
            title = "Native Toolkit",
            message = "Decorated custom view notification sample",
            style = NotificationStyle.DecoratedCustomView(
                customView = NotificationCustomViewStyleData(
                    layoutResId = R.layout.notification_custom_style_sample,
                    bigLayoutResId = R.layout.notification_custom_style_sample_expanded,
                    titleViewId = R.id.notification_title,
                    titleText = "Native Toolkit",
                    messageViewId = R.id.notification_message,
                    messageText = "Decorated custom view sample",
                    iconViewId = R.id.notification_icon,
                    iconResId = R.mipmap.ic_launcher_round
                )
            ),
            subText = "DecoratedCustomView",
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(2100, "native.toolkit.custom.open")
            )
        )
    }

    fun buildDecoratedMediaCustomViewStyleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1008,
            title = "Native Toolkit Player",
            message = "Decorated media custom view sample",
            style = NotificationStyle.DecoratedMediaCustomView(
                customView = NotificationCustomViewStyleData(
                    layoutResId = R.layout.notification_media_custom_style_sample,
                    bigLayoutResId = R.layout.notification_media_custom_style_sample_expanded,
                    titleViewId = R.id.notification_title,
                    titleText = "Native Toolkit Player",
                    messageViewId = R.id.notification_message,
                    messageText = "Decorated media custom view sample",
                    iconViewId = R.id.notification_icon,
                    iconResId = R.mipmap.ic_launcher_round
                ),
                compactActionIndices = listOf(0, 1, 2)
            ),
            subText = "DecoratedMediaCustomView",
            largeIconResId = R.mipmap.ic_launcher_round,
            category = NotificationCompat.CATEGORY_TRANSPORT,
            priority = NotificationCompat.PRIORITY_LOW,
            ongoing = true,
            autoCancel = false,
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(2200, "native.toolkit.decorated.media.open"),
                actions = buildMediaActions(2210)
            )
        )
    }

    fun buildScheduledCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1010,
            title = "Native Toolkit",
            message = "Scheduled notification sample",
            style = NotificationStyle.BigText(
                bigText = "This scheduled notification was queued from Native Toolkit Example.",
                summaryText = "Scheduled",
                bigContentTitle = "Scheduled BigText"
            ),
            channel = scheduleSampleChannel,
            subText = "Scheduled",
            category = NotificationCompat.CATEGORY_ALARM,
            priority = NotificationCompat.PRIORITY_HIGH
        )
    }

    fun buildProgressCommand(progressValue: Int, max: Int = 100): AndroidNotificationCommand {
        val safeProgress = progressValue.coerceIn(0, max)
        val isComplete = safeProgress >= max
        return buildStyleCommand(
            id = 1009,
            title = "Native Toolkit Download",
            message = if (isComplete) {
                "Download completed"
            } else {
                "Downloading sample asset... $safeProgress%"
            },
            style = NotificationStyle.Default,
            subText = "Progress",
            ongoing = !isComplete,
            autoCancel = isComplete,
            progress = NotificationProgress(
                max = max,
                current = safeProgress,
                indeterminate = false
            )
        )
    }

    fun buildIndeterminateProgressCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1009,
            title = "Native Toolkit Sync",
            message = "Syncing sample data...",
            style = NotificationStyle.Default,
            subText = "Progress / Indeterminate",
            ongoing = true,
            autoCancel = false,
            progress = NotificationProgress(
                max = 0,
                current = 0,
                indeterminate = true
            )
        )
    }

    fun buildProgressForegroundCommand(progressValue: Int, max: Int = 100): AndroidNotificationCommand {
        val safeProgress = progressValue.coerceIn(0, max)
        return buildStyleCommand(
            id = 1011,
            title = "Native Toolkit Background Sync",
            message = "Running background sync... $safeProgress%",
            style = NotificationStyle.Default,
            channel = progressForegroundSampleChannel,
            subText = "FGS Progress / dataSync",
            ongoing = true,
            autoCancel = false,
            progress = NotificationProgress(
                max = max,
                current = safeProgress,
                indeterminate = false
            )
        )
    }

    fun buildProgressForegroundCompleteCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1011,
            title = "Native Toolkit Background Sync",
            message = "Background sync completed",
            style = NotificationStyle.BigText(
                bigText = "The background sync finished successfully. This notification was downgraded from a foreground service to a normal notification.",
                summaryText = "FGS Completed",
                bigContentTitle = "Background Sync Completed"
            ),
            channel = progressForegroundSampleChannel,
            subText = "FGS Progress / Completed",
            ongoing = false,
            autoCancel = true,
            progress = NotificationProgress(
                max = 100,
                current = 100,
                indeterminate = false
            )
        )
    }

    fun buildGroupChild1Command(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1101,
            title = "Native Toolkit Group",
            message = "Group child notification #1",
            style = NotificationStyle.BigText(
                bigText = "This is the first child notification in the Native Toolkit grouping sample.",
                summaryText = "Child 1",
                bigContentTitle = "Grouping / Child 1"
            ),
            channel = interactionGroupingSampleChannel,
            subText = "Grouping / Child 1",
            groupKey = GROUP_SAMPLE_KEY,
            groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
            sortKey = "01",
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(5101, ACTION_OPEN_GROUPING_SAMPLE)
            )
        )
    }

    fun buildGroupChild2Command(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1102,
            title = "Native Toolkit Group",
            message = "Group child notification #2",
            style = NotificationStyle.BigText(
                bigText = "This is the second child notification in the Native Toolkit grouping sample.",
                summaryText = "Child 2",
                bigContentTitle = "Grouping / Child 2"
            ),
            channel = interactionGroupingSampleChannel,
            subText = "Grouping / Child 2",
            groupKey = GROUP_SAMPLE_KEY,
            groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
            sortKey = "02",
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(5102, ACTION_OPEN_GROUPING_SAMPLE)
            )
        )
    }

    fun buildGroupSummaryCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1100,
            title = "Native Toolkit Group Summary",
            message = "2 notifications grouped together",
            style = NotificationStyle.Inbox(
                lines = listOf(
                    "Group child notification #1",
                    "Group child notification #2"
                ),
                summaryText = "2 grouped notifications",
                bigContentTitle = "Grouping / Summary"
            ),
            channel = interactionGroupingSampleChannel,
            subText = "Grouping / Summary",
            groupKey = GROUP_SAMPLE_KEY,
            isGroupSummary = true,
            groupAlertBehavior = NotificationCompat.GROUP_ALERT_SUMMARY,
            sortKey = "00",
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(5100, ACTION_OPEN_GROUPING_SAMPLE)
            )
        )
    }

    fun buildGroupAlertBehaviorCommands(): List<AndroidNotificationCommand> {
        return listOf(
            buildGroupChild1Command(),
            buildGroupChild2Command(),
            buildGroupSummaryCommand()
        )
    }

    fun buildDeleteIntentSampleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1110,
            title = "Native Toolkit Interaction",
            message = "Swipe away this notification to trigger deleteIntent.",
            style = NotificationStyle.BigText(
                bigText = "Dismiss this notification from the shade. The app will receive a BroadcastReceiver callback through deleteIntent.",
                summaryText = "deleteIntent",
                bigContentTitle = "Interaction / deleteIntent"
            ),
            channel = interactionGroupingSampleChannel,
            subText = "Interaction / deleteIntent",
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(5110, ACTION_OPEN_GROUPING_SAMPLE),
                deleteIntent = buildBroadcastPendingIntentRequest(
                    intent = NotificationDeleteReceiver.createIntent(
                        context = activity,
                        sampleLabel = "DeleteIntent Sample"
                    ),
                    requestCode = 5111
                )
            )
        )
    }

    fun buildFullScreenIntentSampleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = 1111,
            title = "Native Toolkit Alarm Sample",
            message = "Reference fullScreenIntent notification sample",
            style = NotificationStyle.BigText(
                bigText = "This is a reference sample for fullScreenIntent. Depending on the device state and Android policy, it may launch immediately or appear as a high-priority heads-up notification.",
                summaryText = "fullScreenIntent",
                bigContentTitle = "Interaction / fullScreenIntent"
            ),
            channel = fullScreenSampleChannel,
            subText = "Interaction / fullScreenIntent",
            category = NotificationCompat.CATEGORY_ALARM,
            priority = NotificationCompat.PRIORITY_HIGH,
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(5120, ACTION_OPEN_GROUPING_SAMPLE),
                fullScreenIntent = buildActivityPendingIntentRequest(
                    targetActivityClass = NotificationFullScreenSampleActivity::class.java,
                    requestCode = 5121,
                    action = ACTION_OPEN_FULL_SCREEN_SAMPLE
                )
            )
        )
    }

    fun buildActionButtonsSampleCommand(): AndroidNotificationCommand {
        return buildStyleCommand(
            id = ACTION_SAMPLE_NOTIFICATION_ID,
            title = "Native Toolkit Action Sample",
            message = "Use Accept / Decline action buttons",
            style = NotificationStyle.BigText(
                bigText = "Action button sample for notification interactions. Tap Accept or Decline and verify the status text update while this screen is visible.",
                summaryText = "action buttons",
                bigContentTitle = "Interaction / Action Buttons"
            ),
            channel = interactionGroupingSampleChannel,
            subText = "Interaction / Action Buttons",
            autoCancel = false,
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(5130, ACTION_OPEN_GROUPING_SAMPLE),
                actions = buildAcceptDeclineActions(baseRequestCode = 5131)
            )
        )
    }

    fun startProgressForegroundService() {
        createChannel(progressForegroundSampleChannel)
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ Progress foreground service を表示できません。権限または通知設定を確認してください。"
            return
        }

        runCatching {
            ProgressForegroundNotifications.start(activity, buildProgressForegroundCommand(progressValue = 10))
        }.onSuccess {
            statusText = "✅ dataSync Progress foreground service を開始しました。10% の通知を表示しています。"
        }.onFailure { throwable ->
            Log.e(TAG, "[startProgressForegroundService] failed", throwable)
            statusText = "❌ Progress foreground service の開始に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun updateProgressForegroundService(progressValue: Int) {
        runCatching {
            ProgressForegroundNotifications.update(activity, buildProgressForegroundCommand(progressValue = progressValue))
        }.onSuccess {
            statusText = "✅ dataSync Progress foreground service を ${progressValue.coerceIn(0, 100)}% に更新しました。"
        }.onFailure { throwable ->
            Log.e(TAG, "[updateProgressForegroundService] failed progressValue=$progressValue", throwable)
            statusText = "❌ Progress foreground service の更新に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun completeProgressForegroundService() {
        runCatching {
            ProgressForegroundNotifications.complete(activity, buildProgressForegroundCompleteCommand())
        }.onSuccess {
            statusText = "✅ Progress foreground service を完了しました。通常通知へ降格しています。"
        }.onFailure { throwable ->
            Log.e(TAG, "[completeProgressForegroundService] failed", throwable)
            statusText = "❌ Progress foreground service の完了処理に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun stopProgressForegroundService() {
        runCatching {
            ProgressForegroundNotifications.stop(activity)
        }.onSuccess {
            statusText = "ℹ️ Progress foreground service の停止を要求しました。"
        }.onFailure { throwable ->
            Log.e(TAG, "[stopProgressForegroundService] failed", throwable)
            statusText = "❌ Progress foreground service を停止できませんでした: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun startCallForegroundService(type: CallStyleType, label: String) {
        createChannel(callSampleChannel)
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ 通話通知を表示できません。権限または通知設定を確認してください。"
            return
        }

        val intent = when (type) {
            CallStyleType.INCOMING -> CallStyleForegroundService.createIncomingStartIntent(activity)
            CallStyleType.ONGOING -> CallStyleForegroundService.createOngoingStartIntent(activity)
            CallStyleType.SCREENING -> CallStyleForegroundService.createScreeningStartIntent(activity)
        }

        runCatching {
            ContextCompat.startForegroundService(activity, intent)
        }.onSuccess {
            statusText = "✅ $label の foreground service CallStyle サンプルを開始しました。"
        }.onFailure { throwable ->
            Log.e(TAG, "[startCallForegroundService] failed type=$type", throwable)
            statusText = "❌ 通話 foreground service の開始に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun stopCallForegroundService() {
        runCatching {
            activity.startService(CallStyleForegroundService.createStopIntent(activity))
        }.onSuccess {
            statusText = "ℹ️ 通話 foreground service サンプルの停止を要求しました。"
        }.onFailure { throwable ->
            Log.e(TAG, "[stopCallForegroundService] failed", throwable)
            statusText = "❌ 通話 foreground service を停止できませんでした: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun showNotificationSample(command: AndroidNotificationCommand, successMessage: String) {
        val channel = command.content.channel
        ensureChannel(channel)
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ 通知を表示できません。権限または通知設定を確認してください。"
            return
        }

        useCases.show(command)
            .onSuccess { statusText = successMessage }
            .onFailure { throwable ->
                Log.e(TAG, "[showNotificationSample] failed to show notification", throwable)
                statusText = "❌ 通知表示に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
            }
    }

    fun showNotificationSamples(commands: List<AndroidNotificationCommand>, successMessage: String) {
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ 通知を表示できません。権限または通知設定を確認してください。"
            return
        }

        runCatching {
            commands.forEach { command ->
                ensureChannel(command.content.channel)
                useCases.show(command).getOrThrow()
            }
        }.onSuccess {
            statusText = successMessage
        }.onFailure { throwable ->
            Log.e(TAG, "[showNotificationSamples] failed to show grouped notifications", throwable)
            statusText = "❌ 複数通知の表示に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun deleteNotificationSample(command: AndroidNotificationCommand, label: String) {
        useCases.cancel(command.content.id, command.content.tag)
            .onSuccess { statusText = "🗑️ $label 通知を削除しました。" }
            .onFailure { throwable ->
                Log.e(TAG, "[deleteNotificationSample] failed to delete notification label=$label", throwable)
                statusText = "❌ 通知削除に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
            }
    }

    fun deleteScheduledNotificationSample(command: AndroidNotificationCommand, label: String) {
        useCases.cancelScheduled(command.content.id, command.content.tag)
            .mapCatching { useCases.cancel(command.content.id, command.content.tag).getOrThrow() }
            .onSuccess { statusText = "🗑️ $label を削除しました。予約済み通知と表示中通知をクリアしました。" }
            .onFailure { throwable ->
                Log.e(TAG, "[deleteScheduledNotificationSample] failed to delete scheduled notification label=$label", throwable)
                statusText = "❌ 予約通知削除に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
            }
    }

    val listState = rememberLazyListState()

    Column(
        modifier = modifier
            .fillMaxSize()
            .padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Button(
            onClick = onBack,
            modifier = Modifier.fillMaxWidth()
        ) {
            Text(text = "← Back to Main")
        }

        Text(
            text = "Notification Example",
            fontSize = 28.sp,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
            lineHeight = 36.sp,
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp)
        )

        Text(
            text = statusText,
            modifier = Modifier
                .fillMaxWidth()
                .padding(8.dp)
        )

        Box(
            modifier = Modifier
                .fillMaxWidth()
                .weight(1f)
        ) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .fillMaxSize()
                    .padding(end = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(8.dp, Alignment.Top)
            ) {
                item {
                    Button(
                        onClick = {
                            val exactAlarmAllowed = permissionHelper.canScheduleExactAlarms()
                            statusText = buildString {
                                appendLine("permissionGranted=${permissionHelper.hasPermission()}")
                                appendLine("notificationsEnabled=${permissionHelper.areNotificationsEnabled()}")
                                appendLine("shouldShowRationale=${permissionHelper.shouldShowPermissionRationale()}")
                                append("exactAlarmAllowed=$exactAlarmAllowed")
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Check Notification Permission")
                    }
                }
                item {
                    Button(
                        onClick = {
                            permissionHelper.requestPermission { granted ->
                                statusText = if (granted) {
                                    "✅ 通知権限が許可されました。"
                                } else {
                                    "❌ 通知権限が許可されていません。上の「Open Notification Settings」ボタンから設定画面を開いて有効にしてください。"
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Request Notification Permission")
                    }
                }
                item {
                    Button(
                        onClick = {
                            val opened = permissionHelper.openNotificationSettings()
                            statusText = if (opened) {
                                "ℹ️ 通知設定またはアプリ詳細設定を開きました。"
                            } else {
                                "❌ 設定画面を開けませんでした。この端末では該当設定画面が利用できない可能性があります。"
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Open Notification Settings")
                    }
                }
                item {
                    Button(
                        onClick = {
                            val opened = permissionHelper.openAppDetailsSettings()
                            statusText = if (opened) {
                                "ℹ️ アプリ詳細設定を開きました。"
                            } else {
                                "❌ アプリ詳細設定を開けませんでした。"
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Open App Details Settings")
                    }
                }
                item {
                    Button(
                        onClick = {
                            val opened = permissionHelper.openExactAlarmSettings()
                            statusText = if (opened) {
                                "ℹ️ Exact alarm 設定またはアプリ詳細設定を開きました。"
                            } else {
                                "❌ Exact alarm 設定を開けませんでした。"
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Open Exact Alarm Settings")
                    }
                }
                item {
                    Text(
                        text = "Style",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp, bottom = 4.dp)
                    )
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildDefaultStyleCommand(),
                                successMessage = "✅ Default style 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Default Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildDefaultStyleCommand(),
                                label = "Default Style"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete Default Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildBigTextStyleCommand(),
                                successMessage = "✅ BigText style 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show BigText Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildBigTextStyleCommand(),
                                label = "BigText Style"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete BigText Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildInboxStyleCommand(),
                                successMessage = "✅ Inbox style 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Inbox Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildInboxStyleCommand(),
                                label = "Inbox Style"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete Inbox Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildBigPictureStyleCommand(),
                                successMessage = "✅ BigPicture style 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show BigPicture Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildBigPictureStyleCommand(),
                                label = "BigPicture Style"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete BigPicture Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildMessagingStyleCommand(),
                                successMessage = "✅ Messaging style 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Messaging Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildMessagingStyleCommand(),
                                label = "Messaging Style"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete Messaging Style")
                    }
                }
                item {
                    Text(
                        text = "Extended Style",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp, bottom = 4.dp)
                    )
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildMediaStyleCommand(),
                                successMessage = "✅ Media style 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Media Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildMediaStyleCommand(),
                                label = "Media Style"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete Media Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildDecoratedCustomViewStyleCommand(),
                                successMessage = "✅ DecoratedCustomView style 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show DecoratedCustomView Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildDecoratedCustomViewStyleCommand(),
                                label = "DecoratedCustomView Style"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete DecoratedCustomView Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildDecoratedMediaCustomViewStyleCommand(),
                                successMessage = "✅ DecoratedMediaCustomView style 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show DecoratedMediaCustomView Style")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildDecoratedMediaCustomViewStyleCommand(),
                                label = "DecoratedMediaCustomView Style"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete DecoratedMediaCustomView Style")
                    }
                }
                item {
                    Text(
                        text = "Notification Interaction & Grouping",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp, bottom = 4.dp)
                    )
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildGroupChild1Command(),
                                successMessage = "✅ Group Child 1 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Group Child 1")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildGroupChild2Command(),
                                successMessage = "✅ Group Child 2 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Group Child 2")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildGroupSummaryCommand(),
                                successMessage = "✅ Group Summary 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Group Summary")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSamples(
                                commands = buildGroupAlertBehaviorCommands(),
                                successMessage = "✅ Group Alert Behavior サンプルを表示しました。summary only alert を確認してください。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Group Alert Behavior")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildDeleteIntentSampleCommand(),
                                successMessage = "✅ DeleteIntent サンプルを表示しました。通知をスワイプして receiver を確認してください。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show DeleteIntent Sample")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildFullScreenIntentSampleCommand(),
                                successMessage = "✅ FullScreenIntent 参考サンプルを表示しました。端末状態によって heads-up または full screen で表示されます。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show FullScreenIntent Sample")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildActionButtonsSampleCommand(),
                                successMessage = "✅ Action buttonサンプル通知を表示しました。Accept / Decline を押して statusText を確認してください。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Action Buttons Sample")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildActionButtonsSampleCommand(),
                                label = "Action Buttons Sample"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete Action Buttons Sample")
                    }
                }
                item {
                    Text(
                        text = "Progress",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp, bottom = 4.dp)
                    )
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildProgressCommand(progressValue = 10),
                                successMessage = "✅ Progress 通知を 10% で表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Progress 10%")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildProgressCommand(progressValue = 50),
                                successMessage = "✅ Progress 通知を 50% に更新しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Progress 50%")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildProgressCommand(progressValue = 100),
                                successMessage = "✅ Progress 通知を 100% に更新しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Progress 100%")
                    }
                }
                item {
                    Button(
                        onClick = {
                            showNotificationSample(
                                command = buildIndeterminateProgressCommand(),
                                successMessage = "✅ Indeterminate Progress 通知を表示しました。"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Show Indeterminate Progress")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteNotificationSample(
                                command = buildProgressCommand(progressValue = 0),
                                label = "Progress"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete Progress")
                    }
                }

                item {
                    Text(
                        text = "Progress (Foreground Service / dataSync)",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp, bottom = 4.dp)
                    )
                }
                item {
                    Button(
                        onClick = { startProgressForegroundService() },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Start Progress FGS 10%")
                    }
                }
                item {
                    Button(
                        onClick = { updateProgressForegroundService(progressValue = 50) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Update Progress FGS 50%")
                    }
                }
                item {
                    Button(
                        onClick = { updateProgressForegroundService(progressValue = 90) },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Update Progress FGS 90%")
                    }
                }
                item {
                    Button(
                        onClick = { completeProgressForegroundService() },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Complete Progress FGS")
                    }
                }
                item {
                    Button(
                        onClick = { stopProgressForegroundService() },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Stop Progress FGS")
                    }
                }

                item {
                    Text(
                        text = "Call Style (Foreground Service)",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp, bottom = 4.dp)
                    )
                }
                item {
                    Button(
                        onClick = {
                            startCallForegroundService(
                                type = CallStyleType.INCOMING,
                                label = "Incoming Call"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Incoming Call")
                    }
                }
                item {
                    Button(
                        onClick = {
                            startCallForegroundService(
                                type = CallStyleType.ONGOING,
                                label = "Ongoing Call"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Ongoing Call")
                    }
                }
                item {
                    Button(
                        onClick = {
                            startCallForegroundService(
                                type = CallStyleType.SCREENING,
                                label = "Screening Call"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Screening Call")
                    }
                }
                item {
                    Button(
                        onClick = { stopCallForegroundService() },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Stop Call Foreground Service")
                    }
                }
                item {
                    Text(
                        text = "Schedule",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(top = 8.dp, bottom = 4.dp)
                    )
                }
                item {
                    Button(
                        onClick = {
                            createChannel(scheduleSampleChannel)
                            if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
                                statusText = "❌ 予約通知を設定できません。権限または通知設定を確認してください。"
                            } else if (!permissionHelper.canScheduleExactAlarms()) {
                                statusText = "❌ 正確なアラームが許可されていません。上の「Open Exact Alarm Settings」ボタンから設定画面を開いて有効にしてください。"
                            } else {
                                val triggerAt = System.currentTimeMillis() + 15_000L
                                useCases.schedule(
                                    buildScheduledCommand(),
                                    NotificationSchedule(triggerAtMillis = triggerAt)
                                ).onSuccess {
                                    statusText = "✅ 15秒後の予約通知を高優先度で設定しました。"
                                }.onFailure { throwable ->
                                    Log.e(TAG, "[schedule] failed", throwable)
                                    statusText = "❌ 予約通知の設定に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
                                }
                            }
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Schedule Notification (15 sec)")
                    }
                }
                item {
                    Button(
                        onClick = {
                            deleteScheduledNotificationSample(
                                command = buildScheduledCommand(),
                                label = "Schedule Notification"
                            )
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Delete Schedule Notification")
                    }
                }
            }

            AlwaysVisibleLazyColumnScrollbar(
                listState = listState,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(vertical = 8.dp)
                    .offset(x = 12.dp)
            )
        }
    }
}

private data class ScrollbarMetrics(
    val canScroll: Boolean,
    val thumbHeightPx: Float,
    val offsetPx: Float
)

@Composable
private fun AlwaysVisibleLazyColumnScrollbar(
    listState: LazyListState,
    modifier: Modifier = Modifier
) {
    val density = LocalDensity.current
    val minThumbHeightPx = with(density) { 36.dp.toPx() }
    val metrics = calculateScrollbarMetrics(
        listState = listState,
        minThumbHeightPx = minThumbHeightPx
    )

    if (!metrics.canScroll) return

    Box(
        modifier = modifier
            .offset { IntOffset(0, metrics.offsetPx.toInt()) }
            .clip(RoundedCornerShape(999.dp))
            .background(Color.Black.copy(alpha = 0.45f))
            .width(4.dp)
            .height(with(density) { metrics.thumbHeightPx.toDp() })
    )
}

private fun calculateScrollbarMetrics(
    listState: LazyListState,
    minThumbHeightPx: Float
): ScrollbarMetrics {
    val layoutInfo = listState.layoutInfo
    val visibleItems = layoutInfo.visibleItemsInfo
    if (visibleItems.isEmpty()) {
        return ScrollbarMetrics(false, minThumbHeightPx, 0f)
    }

    val viewportHeightPx = (layoutInfo.viewportEndOffset - layoutInfo.viewportStartOffset).toFloat()
    if (viewportHeightPx <= 0f) {
        return ScrollbarMetrics(false, minThumbHeightPx, 0f)
    }

    val averageItemSizePx = visibleItems.map { it.size }.average().toFloat().coerceAtLeast(1f)
    val totalItemsCount = layoutInfo.totalItemsCount.coerceAtLeast(1)
    val estimatedContentHeightPx = averageItemSizePx * totalItemsCount
    if (estimatedContentHeightPx <= viewportHeightPx) {
        return ScrollbarMetrics(false, viewportHeightPx, 0f)
    }

    val estimatedScrollOffsetPx =
        (listState.firstVisibleItemIndex * averageItemSizePx) + listState.firstVisibleItemScrollOffset
    val maxScrollOffsetPx = (estimatedContentHeightPx - viewportHeightPx).coerceAtLeast(1f)
    val thumbHeightPx =
        (viewportHeightPx * (viewportHeightPx / estimatedContentHeightPx))
            .coerceAtLeast(minThumbHeightPx)
            .coerceAtMost(viewportHeightPx)
    val availableTrackHeightPx = (viewportHeightPx - thumbHeightPx).coerceAtLeast(0f)
    val offsetRatio = (estimatedScrollOffsetPx / maxScrollOffsetPx).coerceIn(0f, 1f)

    return ScrollbarMetrics(
        canScroll = true,
        thumbHeightPx = thumbHeightPx,
        offsetPx = availableTrackHeightPx * offsetRatio
    )
}
