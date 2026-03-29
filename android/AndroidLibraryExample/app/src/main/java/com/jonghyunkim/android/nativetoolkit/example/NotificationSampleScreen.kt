package com.jonghyunkim.android.nativetoolkit.example

import android.app.PendingIntent
import android.content.Intent
import android.library.notification.application.model.AndroidNotificationAction
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.usecase.CancelNotificationUseCase
import android.library.notification.application.usecase.CancelScheduledNotificationUseCase
import android.library.notification.application.usecase.CreateNotificationChannelUseCase
import android.library.notification.application.usecase.ScheduleNotificationUseCase
import android.library.notification.application.usecase.ShowNotificationUseCase
import android.library.notification.data.repository.NotificationRepositoryImpl
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationCustomViewStyleData
import android.library.notification.domain.model.NotificationMessage
import android.library.notification.domain.model.NotificationSchedule
import android.library.notification.domain.model.NotificationStyle
import android.library.notification.presentation.permission.NotificationPermissionHelper
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

@Composable
fun NotificationSampleScreen(
    modifier: Modifier = Modifier,
    activity: AppCompatActivity,
    permissionHelper: NotificationPermissionHelper,
    onBack: () -> Unit
) {
    Log.d(TAG, "[NotificationSampleScreen] modifier: $modifier, activity: $activity, permissionHelper: $permissionHelper, onBack: $onBack")
    val repository = remember(activity) { NotificationRepositoryImpl(activity) }
    val createChannelUseCase = remember(repository) { CreateNotificationChannelUseCase(repository) }
    val showNotificationUseCase = remember(repository) { ShowNotificationUseCase(repository) }
    val cancelNotificationUseCase = remember(repository) { CancelNotificationUseCase(repository) }
    val scheduleNotificationUseCase = remember(repository) { ScheduleNotificationUseCase(repository) }
    val cancelScheduledNotificationUseCase = remember(repository) { CancelScheduledNotificationUseCase(repository) }

    var statusText by remember {
        mutableStateOf("通知サンプルを確認できます。まずは権限状態を確認してください。")
    }

    val sampleChannel = remember {
        NotificationChannel(
            id = "native_toolkit_sample",
            name = "Native Toolkit Sample",
            description = "Notification sample channel"
        )
    }
    val callSampleChannel = remember { CallStyleSampleNotificationFactory.createChannel() }

    fun createChannel(channel: NotificationChannel = sampleChannel) {
        Log.d(TAG, "[createChannel] channelId=${channel.id}")
        createChannelUseCase(channel)
        statusText = "✅ チャンネルを作成しました: ${channel.id}"
    }

    fun buildActivityPendingIntentRequest(requestCode: Int, action: String): AndroidPendingIntentRequest {
        return AndroidPendingIntentRequest(
            intent = Intent(activity, MainActivity::class.java).apply {
                this.action = action
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            requestCode = requestCode,
            flags = PendingIntent.FLAG_UPDATE_CURRENT
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
        platformOptions: AndroidNotificationPlatformOptions = AndroidNotificationPlatformOptions()
    ): AndroidNotificationCommand {
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
                style = style
            ),
            platformOptions = platformOptions
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
            subText = "Scheduled"
        )
    }

    fun startCallSampleForegroundService(sampleType: CallStyleSampleType, label: String) {
        createChannel(callSampleChannel)
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ 通話通知を表示できません。権限または通知設定を確認してください。"
            return
        }

        val intent = when (sampleType) {
            CallStyleSampleType.INCOMING -> CallStyleSampleForegroundService.createIncomingStartIntent(activity)
            CallStyleSampleType.ONGOING -> CallStyleSampleForegroundService.createOngoingStartIntent(activity)
            CallStyleSampleType.SCREENING -> CallStyleSampleForegroundService.createScreeningStartIntent(activity)
        }

        runCatching {
            ContextCompat.startForegroundService(activity, intent)
        }.onSuccess {
            statusText = "✅ $label の foreground service CallStyle サンプルを開始しました。"
        }.onFailure { throwable ->
            Log.e(TAG, "[startCallSampleForegroundService] failed sampleType=$sampleType", throwable)
            statusText = "❌ 通話 foreground service の開始に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun stopCallSampleForegroundService() {
        runCatching {
            activity.startService(CallStyleSampleForegroundService.createStopIntent(activity))
        }.onSuccess {
            statusText = "ℹ️ 通話 foreground service サンプルの停止を要求しました。"
        }.onFailure { throwable ->
            Log.e(TAG, "[stopCallSampleForegroundService] failed", throwable)
            statusText = "❌ 通話 foreground service を停止できませんでした: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun showNotificationSample(command: AndroidNotificationCommand, successMessage: String) {
        val channel = command.content.channel
        createChannel(channel)
        if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
            statusText = "❌ 通知を表示できません。権限または通知設定を確認してください。"
            return
        }

        runCatching {
            showNotificationUseCase(command)
        }.onSuccess {
            statusText = successMessage
        }.onFailure { throwable ->
            Log.e(TAG, "[showNotificationSample] failed to show notification", throwable)
            statusText = "❌ 通知表示に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun deleteNotificationSample(command: AndroidNotificationCommand, label: String) {
        runCatching {
            cancelNotificationUseCase(command.content.id, command.content.tag)
        }.onSuccess {
            statusText = "🗑️ $label 通知を削除しました。"
        }.onFailure { throwable ->
            Log.e(TAG, "[deleteNotificationSample] failed to delete notification label=$label", throwable)
            statusText = "❌ 通知削除に失敗しました: ${throwable.message ?: throwable::class.java.simpleName}"
        }
    }

    fun deleteScheduledNotificationSample(command: AndroidNotificationCommand, label: String) {
        runCatching {
            cancelScheduledNotificationUseCase(command.content.id, command.content.tag)
            cancelNotificationUseCase(command.content.id, command.content.tag)
        }.onSuccess {
            statusText = "🗑️ $label を削除しました。予約済み通知と表示中通知をクリアしました。"
        }.onFailure { throwable ->
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
                            statusText = buildString {
                                appendLine("permissionGranted=${permissionHelper.hasPermission()}")
                                appendLine("notificationsEnabled=${permissionHelper.areNotificationsEnabled()}")
                                append("shouldShowRationale=${permissionHelper.shouldShowPermissionRationale()}")
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
                                    "❌ 通知権限が未許可です。設定画面から有効化してください。"
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
                            startCallSampleForegroundService(
                                sampleType = CallStyleSampleType.INCOMING,
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
                            startCallSampleForegroundService(
                                sampleType = CallStyleSampleType.ONGOING,
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
                            startCallSampleForegroundService(
                                sampleType = CallStyleSampleType.SCREENING,
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
                        onClick = { stopCallSampleForegroundService() },
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
                            createChannel()
                            if (!permissionHelper.hasPermission() || !permissionHelper.areNotificationsEnabled()) {
                                statusText = "❌ 予約通知を設定できません。権限または通知設定を確認してください。"
                            } else {
                                val triggerAt = System.currentTimeMillis() + 15_000L
                                scheduleNotificationUseCase(
                                    buildScheduledCommand(),
                                    NotificationSchedule(triggerAtMillis = triggerAt)
                                )
                                statusText = "✅ 15秒後の予約通知を設定しました。"
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
