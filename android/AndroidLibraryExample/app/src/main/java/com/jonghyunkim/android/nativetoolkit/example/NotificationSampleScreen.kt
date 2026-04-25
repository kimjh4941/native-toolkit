package com.jonghyunkim.android.nativetoolkit.example

import android.app.PendingIntent
import android.app.NotificationManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.library.notification.application.model.AndroidNotificationAction
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidPendingIntentType
import android.library.notification.application.model.RemoteViewAction
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
        mutableStateOf("Explore notification samples. Start by checking the current permission state.")
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
                statusText = "✅ Action button pressed: $actionLabel (id=$actionId, notificationId=$notificationId)"
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
        statusText = "✅ Channel created: ${channel.id}"
    }

    fun buildActivityPendingIntentRequest(
        targetActivityClass: Class<*>,
        requestCode: Int,
        action: String
    ): AndroidPendingIntentRequest {
        Log.d(TAG, "[buildActivityPendingIntentRequest] requestCode: $requestCode, action: $action")
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
        Log.d(TAG, "[buildActivityPendingIntentRequest] requestCode: $requestCode, action: $action")
        return buildActivityPendingIntentRequest(
            targetActivityClass = MainActivity::class.java,
            requestCode = requestCode,
            action = action
        )
    }

    fun buildBroadcastPendingIntentRequest(intent: Intent, requestCode: Int): AndroidPendingIntentRequest {
        Log.d(TAG, "[buildBroadcastPendingIntentRequest] requestCode: $requestCode")
        return AndroidPendingIntentRequest(
            intent = intent,
            requestCode = requestCode,
            type = AndroidPendingIntentType.BROADCAST,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
        )
    }

    fun buildDefaultOpenAppPlatformOptions(requestCode: Int): AndroidNotificationPlatformOptions {
        Log.d(TAG, "[buildDefaultOpenAppPlatformOptions] requestCode: $requestCode")
        return AndroidNotificationPlatformOptions(
            contentIntent = buildActivityPendingIntentRequest(
                requestCode = requestCode,
                action = ACTION_OPEN_NOTIFICATION_SAMPLE
            )
        )
    }

    fun buildMediaActions(baseRequestCode: Int): List<AndroidNotificationAction> {
        Log.d(TAG, "[buildMediaActions] baseRequestCode: $baseRequestCode")
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
        Log.d(TAG, "[buildAcceptDeclineActions] baseRequestCode: $baseRequestCode")
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
        Log.d(TAG, "[buildStyleCommand] id: $id, title: $title, style: $style")
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
        Log.d(TAG, "[buildDefaultStyleCommand]")
        return buildStyleCommand(
            id = 1001,
            title = "Native Toolkit",
            message = "Default style notification sample",
            style = NotificationStyle.Default,
            subText = "Default"
        )
    }

    fun buildBigTextStyleCommand(): AndroidNotificationCommand {
        Log.d(TAG, "[buildBigTextStyleCommand]")
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
        Log.d(TAG, "[buildInboxStyleCommand]")
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
        Log.d(TAG, "[buildBigPictureStyleCommand]")
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
        Log.d(TAG, "[buildMessagingStyleCommand]")
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
        Log.d(TAG, "[buildMediaStyleCommand]")
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
        Log.d(TAG, "[buildDecoratedCustomViewStyleCommand]")
        return buildStyleCommand(
            id = 1007,
            title = "Native Toolkit",
            message = "Decorated custom view notification sample",
            style = NotificationStyle.DecoratedCustomView(
                customView = NotificationCustomViewStyleData(
                    layoutResId = R.layout.notification_custom_style_sample,
                    bigLayoutResId = R.layout.notification_custom_style_sample_expanded
                )
            ),
            subText = "DecoratedCustomView",
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildActivityPendingIntentRequest(2100, "native.toolkit.custom.open"),
                customViewOptions = AndroidNotificationCustomViewPlatformOptions(
                    viewActions = listOf(
                        RemoteViewAction.SetText(R.id.notification_title, "Native Toolkit"),
                        RemoteViewAction.SetText(R.id.notification_message, "Decorated custom view sample"),
                        RemoteViewAction.SetImage(R.id.notification_icon, R.mipmap.ic_launcher_round),
                        RemoteViewAction.SetClickIntent(
                            viewId = R.id.notification_btn_dismiss,
                            pendingIntent = buildBroadcastPendingIntentRequest(
                                intent = NotificationActionReceiver.createIntent(
                                    context = activity,
                                    actionId = "custom_view_dismiss",
                                    actionLabel = "Dismiss",
                                    notificationId = 1007
                                ),
                                requestCode = 2101
                            )
                        )
                    )
                )
            )
        )
    }

    fun buildDecoratedMediaCustomViewStyleCommand(): AndroidNotificationCommand {
        Log.d(TAG, "[buildDecoratedMediaCustomViewStyleCommand]")
        return buildStyleCommand(
            id = 1008,
            title = "Native Toolkit Player",
            message = "Decorated media custom view sample",
            style = NotificationStyle.DecoratedMediaCustomView(
                customView = NotificationCustomViewStyleData(
                    layoutResId = R.layout.notification_media_custom_style_sample,
                    bigLayoutResId = R.layout.notification_media_custom_style_sample_expanded
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
                actions = buildMediaActions(2210),
                customViewOptions = AndroidNotificationCustomViewPlatformOptions(
                    viewActions = listOf(
                        RemoteViewAction.SetText(R.id.notification_title, "Native Toolkit Player"),
                        RemoteViewAction.SetText(R.id.notification_message, "Decorated media custom view sample"),
                        RemoteViewAction.SetImage(R.id.notification_icon, R.mipmap.ic_launcher_round)
                    )
                )
            )
        )
    }

    fun buildScheduledCommand(): AndroidNotificationCommand {
        Log.d(TAG, "[buildScheduledCommand]")
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
        Log.d(TAG, "[buildProgressCommand] progressValue: $progressValue, max: $max")
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
        Log.d(TAG, "[buildIndeterminateProgressCommand]")
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
        Log.d(TAG, "[buildProgressForegroundCommand] progressValue: $progressValue, max: $max")
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
        Log.d(TAG, "[buildProgressForegroundCompleteCommand]")
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
        Log.d(TAG, "[buildGroupChild1Command]")
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
        Log.d(TAG, "[buildGroupChild2Command]")
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
        Log.d(TAG, "[buildGroupSummaryCommand]")
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
        Log.d(TAG, "[buildGroupAlertBehaviorCommands]")
        return listOf(
            buildGroupChild1Command(),
            buildGroupChild2Command(),
            buildGroupSummaryCommand()
        )
    }

    fun buildDeleteIntentSampleCommand(): AndroidNotificationCommand {
        Log.d(TAG, "[buildDeleteIntentSampleCommand]")
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
        Log.d(TAG, "[buildFullScreenIntentSampleCommand]")
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
        Log.d(TAG, "[buildActionButtonsSampleCommand]")
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
        Log.d(TAG, "[startProgressForegroundService]")
        createChannel(progressForegroundSampleChannel)
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ Unable to show the progress foreground service. Check permissions or notification settings."
            return
        }

        runCatching {
            ProgressForegroundNotifications.start(activity, buildProgressForegroundCommand(progressValue = 10))
        }.onSuccess {
            statusText = "✅ Started dataSync progress foreground service. A 10% notification is now shown."
        }.onFailure { throwable ->
            Log.e(TAG, "[startProgressForegroundService] failed", throwable)
            statusText = "❌ Failed to start progress foreground service: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun updateProgressForegroundService(progressValue: Int) {
        Log.d(TAG, "[updateProgressForegroundService] progressValue: $progressValue")
        runCatching {
            ProgressForegroundNotifications.update(activity, buildProgressForegroundCommand(progressValue = progressValue))
        }.onSuccess {
            statusText = "✅ Updated dataSync progress foreground service to ${progressValue.coerceIn(0, 100)}%."
        }.onFailure { throwable ->
            Log.e(TAG, "[updateProgressForegroundService] failed progressValue=$progressValue", throwable)
            statusText = "❌ Failed to update progress foreground service: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun completeProgressForegroundService() {
        Log.d(TAG, "[completeProgressForegroundService]")
        runCatching {
            ProgressForegroundNotifications.complete(activity, buildProgressForegroundCompleteCommand())
        }.onSuccess {
            statusText = "✅ Completed progress foreground service. It has been downgraded to a regular notification."
        }.onFailure { throwable ->
            Log.e(TAG, "[completeProgressForegroundService] failed", throwable)
            statusText = "❌ Failed to complete progress foreground service: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun stopProgressForegroundService() {
        Log.d(TAG, "[stopProgressForegroundService]")
        runCatching {
            ProgressForegroundNotifications.stop(activity)
        }.onSuccess {
            statusText = "ℹ️ Requested progress foreground service stop."
        }.onFailure { throwable ->
            Log.e(TAG, "[stopProgressForegroundService] failed", throwable)
            statusText = "❌ Failed to stop progress foreground service: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun startCallForegroundService(type: CallStyleType, label: String) {
        Log.d(TAG, "[startCallForegroundService] type: $type, label: $label")
        createChannel(callSampleChannel)
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ Unable to show call notifications. Check permissions or notification settings."
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
            statusText = "✅ Started foreground service CallStyle sample for $label."
        }.onFailure { throwable ->
            Log.e(TAG, "[startCallForegroundService] failed type=$type", throwable)
            statusText = "❌ Failed to start call foreground service: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun stopCallForegroundService() {
        Log.d(TAG, "[stopCallForegroundService]")
        runCatching {
            activity.startService(CallStyleForegroundService.createStopIntent(activity))
        }.onSuccess {
            statusText = "ℹ️ Requested call foreground service sample stop."
        }.onFailure { throwable ->
            Log.e(TAG, "[stopCallForegroundService] failed", throwable)
            statusText = "❌ Failed to stop call foreground service: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun showNotificationSample(command: AndroidNotificationCommand, successMessage: String) {
        Log.d(TAG, "[showNotificationSample] id: ${command.content.id}, successMessage: $successMessage")
        val channel = command.content.channel
        ensureChannel(channel)
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ Unable to show notifications. Check permissions or notification settings."
            return
        }

        useCases.show(command)
            .onSuccess { statusText = successMessage }
            .onFailure { throwable ->
                Log.e(TAG, "[showNotificationSample] failed to show notification", throwable)
                statusText = "❌ Failed to show notification: ${throwable.message ?: throwable::class.java.simpleName}"
            }
    }

    fun showNotificationSamples(commands: List<AndroidNotificationCommand>, successMessage: String) {
        Log.d(TAG, "[showNotificationSamples] count: ${commands.size}, successMessage: $successMessage")
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ Unable to show notifications. Check permissions or notification settings."
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
            statusText = "❌ Failed to show multiple notifications: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun deleteNotificationSample(command: AndroidNotificationCommand, label: String) {
        Log.d(TAG, "[deleteNotificationSample] id: ${command.content.id}, label: $label")
        useCases.cancel(command.content.id, command.content.tag)
            .onSuccess { statusText = "🗑️ Deleted $label notification." }
            .onFailure { throwable ->
                Log.e(TAG, "[deleteNotificationSample] failed to delete notification label=$label", throwable)
                statusText = "❌ Failed to delete notification: ${throwable.message ?: throwable::class.java.simpleName}"
            }
    }

    fun deleteScheduledNotificationSample(command: AndroidNotificationCommand, label: String) {
        Log.d(TAG, "[deleteScheduledNotificationSample] id: ${command.content.id}, label: $label")
        useCases.cancelScheduled(command.content.id, command.content.tag)
            .mapCatching { useCases.cancel(command.content.id, command.content.tag).getOrThrow() }
            .onSuccess {
                val scheduled = useCases.isScheduled(activity, command.content.id, command.content.tag)
                statusText = "🗑️ Deleted $label. Cleared both scheduled and active notifications. (isScheduled=$scheduled)"
            }
            .onFailure { throwable ->
                Log.e(TAG, "[deleteScheduledNotificationSample] failed to delete scheduled notification label=$label", throwable)
                statusText = "❌ Failed to delete scheduled notification: ${throwable.message ?: throwable::class.java.simpleName}"
            }
    }

    fun checkScheduledNotificationStatus(command: AndroidNotificationCommand) {
        Log.d(TAG, "[checkScheduledNotificationStatus] id: ${command.content.id}")
        val scheduled = useCases.isScheduled(activity, command.content.id, command.content.tag)
        statusText = if (scheduled) {
            "ℹ️ Schedule Notification is currently scheduled. (isScheduled=true)"
        } else {
            "ℹ️ Schedule Notification is currently not scheduled. (isScheduled=false)"
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
                                    "✅ Notification permission granted."
                                } else {
                                    "❌ Notification permission is not granted. Use 'Open Notification Settings' above to enable it."
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
                                "ℹ️ Opened notification settings or app details settings."
                            } else {
                                "❌ Failed to open settings screen. This device may not support the target settings screen."
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
                                "ℹ️ Opened app details settings."
                            } else {
                                "❌ Failed to open app details settings."
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
                                "ℹ️ Opened exact alarm settings or app details settings."
                            } else {
                                "❌ Failed to open exact alarm settings."
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
                                successMessage = "✅ Displayed Default style notification."
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
                                successMessage = "✅ Displayed BigText style notification."
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
                                successMessage = "✅ Displayed Inbox style notification."
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
                                successMessage = "✅ Displayed BigPicture style notification."
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
                                successMessage = "✅ Displayed Messaging style notification."
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
                                successMessage = "✅ Displayed Media style notification."
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
                                successMessage = "✅ Displayed DecoratedCustomView style notification."
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
                                successMessage = "✅ Displayed DecoratedMediaCustomView style notification."
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
                                successMessage = "✅ Displayed Group Child 1 notification."
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
                                successMessage = "✅ Displayed Group Child 2 notification."
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
                                successMessage = "✅ Displayed Group Summary notification."
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
                                successMessage = "✅ Displayed Group Alert Behavior sample. Verify summary-only alert behavior."
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
                                successMessage = "✅ Displayed DeleteIntent sample. Swipe the notification and verify the receiver callback."
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
                                successMessage = "✅ Displayed FullScreenIntent reference sample. Depending on device state, it appears as heads-up or full-screen."
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
                                successMessage = "✅ Displayed action button sample notification. Press Accept / Decline and check the status text."
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
                                successMessage = "✅ Displayed progress notification at 10%."
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
                                successMessage = "✅ Updated progress notification to 50%."
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
                                successMessage = "✅ Updated progress notification to 100%."
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
                                successMessage = "✅ Displayed indeterminate progress notification."
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
                                statusText = "❌ Unable to schedule notifications. Check permissions or notification settings."
                            } else if (!permissionHelper.canScheduleExactAlarms()) {
                                statusText = "❌ Exact alarms are not allowed. Use 'Open Exact Alarm Settings' above to enable them."
                            } else {
                                val triggerAt = System.currentTimeMillis() + 15_000L
                                useCases.schedule(
                                    buildScheduledCommand(),
                                    NotificationSchedule(triggerAtMillis = triggerAt)
                                ).onSuccess {
                                    val command = buildScheduledCommand()
                                    val scheduled = useCases.isScheduled(activity, command.content.id, command.content.tag)
                                    statusText = "✅ Scheduled a high-priority notification for 15 seconds later. (isScheduled=$scheduled)"
                                }.onFailure { throwable ->
                                    Log.e(TAG, "[schedule] failed", throwable)
                                    statusText = "❌ Failed to schedule notification: ${throwable.message ?: throwable::class.java.simpleName}"
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
                            checkScheduledNotificationStatus(buildScheduledCommand())
                        },
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Text(text = "Check Schedule isScheduled")
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
