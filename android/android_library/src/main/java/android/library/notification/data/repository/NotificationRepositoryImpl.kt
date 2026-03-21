package android.library.notification.data.repository

import android.Manifest
import android.annotation.SuppressLint
import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationChannelGroup
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.os.Build
import android.widget.RemoteViews
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.app.Person
import androidx.core.content.ContextCompat
import androidx.core.graphics.drawable.IconCompat
import androidx.core.net.toUri
import androidx.media.app.NotificationCompat as MediaNotificationCompat
import android.library.notification.application.model.AndroidNotificationAction
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidPendingIntentType
import android.library.notification.application.port.AndroidNotificationRuntimeRepository
import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.domain.model.ActiveNotification
import android.library.notification.domain.model.NotificationCallType
import android.library.notification.domain.model.NotificationCustomViewStyleData
import android.library.notification.domain.model.NotificationChannel as DomainNotificationChannel
import android.library.notification.domain.model.NotificationSchedule
import android.library.notification.domain.model.NotificationStyle

class NotificationRepositoryImpl(context: Context) :
    NotificationCommandRepository,
    AndroidNotificationRuntimeRepository {

    private val appContext: Context = context.applicationContext
    private val notificationManager =
        appContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
    private val alarmManager = appContext.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    override fun hasPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            ContextCompat.checkSelfPermission(
                appContext,
                Manifest.permission.POST_NOTIFICATIONS
            ) == PackageManager.PERMISSION_GRANTED
        } else {
            true
        }
    }

    override fun areNotificationsEnabled(): Boolean {
        return NotificationManagerCompat.from(appContext).areNotificationsEnabled()
    }

    override fun send(command: AndroidNotificationCommand) {
        notify(command)
    }

    override fun update(command: AndroidNotificationCommand) {
        notify(command)
    }

    override fun cancel(id: Int, tag: String?) {
        if (tag.isNullOrBlank()) {
            notificationManager.cancel(id)
        } else {
            notificationManager.cancel(tag, id)
        }
    }

    override fun cancelAll() {
        notificationManager.cancelAll()
    }

    override fun createChannel(channel: DomainNotificationChannel) {
        channel.groupId?.takeIf { it.isNotBlank() }?.let { groupId ->
            val groupName = channel.groupName ?: groupId
            notificationManager.createNotificationChannelGroup(
                NotificationChannelGroup(groupId, groupName)
            )
        }

        val notificationChannel = NotificationChannel(
            channel.id,
            channel.name,
            normalizeChannelImportance(channel.importance)
        ).apply {
            description = channel.description
            setShowBadge(channel.showBadge)
            enableLights(channel.enableLights)
            channel.lightColor?.let(::setLightColor)
            enableVibration(channel.enableVibration)
            vibrationPattern = channel.vibrationPattern?.toLongArray()
            lockscreenVisibility = normalizeVisibility(channel.lockscreenVisibility)
            group = channel.groupId
            channel.soundUri?.let { setSound(it.toUri(), null) }
        }
        notificationManager.createNotificationChannel(notificationChannel)
    }

    override fun createChannels(channels: List<DomainNotificationChannel>) {
        channels.forEach(::createChannel)
    }

    override fun deleteChannel(channelId: String) {
        notificationManager.deleteNotificationChannel(channelId)
    }

    override fun schedule(command: AndroidNotificationCommand, schedule: NotificationSchedule): Boolean {
        if (schedule.triggerAtMillis <= System.currentTimeMillis()) {
            send(command)
            NotificationSchedulerSupport.remove(appContext, command.content.id, command.content.tag)
            return true
        }

        val pendingIntent = createSchedulePendingIntent(command)
        scheduleAlarm(schedule, pendingIntent)

        if (schedule.persistAcrossBoot) {
            NotificationSchedulerSupport.persist(
                appContext,
                ScheduledNotificationEntry(command = command, schedule = schedule)
            )
        } else {
            NotificationSchedulerSupport.remove(appContext, command.content.id, command.content.tag)
        }
        return true
    }

    override fun cancelScheduled(id: Int, tag: String?) {
        alarmManager.cancel(createSchedulePendingIntent(id = id, tag = tag))
        NotificationSchedulerSupport.remove(appContext, id, tag)
    }

    override fun cancelAllScheduled() {
        NotificationSchedulerSupport.loadAll(appContext).forEach { entry ->
            alarmManager.cancel(createSchedulePendingIntent(entry.command))
        }
        NotificationSchedulerSupport.clear(appContext)
    }

    override fun restoreScheduled() {
        val now = System.currentTimeMillis()
        NotificationSchedulerSupport.loadAll(appContext).forEach { entry ->
            if (entry.schedule.triggerAtMillis <= now) {
                send(entry.command)
                NotificationSchedulerSupport.remove(appContext, entry.command.content.id, entry.command.content.tag)
            } else {
                scheduleAlarm(entry.schedule, createSchedulePendingIntent(entry.command))
            }
        }
    }

    override fun getActive(): List<ActiveNotification> {
        return notificationManager.activeNotifications.map { statusBarNotification ->
            val notification = statusBarNotification.notification
            ActiveNotification(
                id = statusBarNotification.id,
                tag = statusBarNotification.tag,
                channelId = notification.channelId,
                title = notification.extras.getCharSequence(Notification.EXTRA_TITLE)?.toString(),
                message = notification.extras.getCharSequence(Notification.EXTRA_TEXT)?.toString(),
                isOngoing = notification.flags and Notification.FLAG_ONGOING_EVENT != 0,
                groupKey = statusBarNotification.groupKey
            )
        }
    }

    override fun build(command: AndroidNotificationCommand): Notification {
        val content = command.content
        val platform = command.platformOptions
        createChannel(content.channel)

        return NotificationCompat.Builder(appContext, content.channel.id).apply {
            setContentTitle(content.title)
            setContentText(content.message)
            setSmallIcon(content.smallIconResId ?: android.R.drawable.ic_dialog_info)
            setPriority(content.priority)
            setAutoCancel(content.autoCancel)
            setOngoing(content.ongoing)
            setShowWhen(content.showTimestamp)
            setVisibility(normalizeVisibility(content.visibility))
            setGroupAlertBehavior(content.groupAlertBehavior)
            setOnlyAlertOnce(content.onlyAlertOnce)
            setLocalOnly(content.localOnly)
            setSilent(content.silent)
            setUsesChronometer(content.usesChronometer)

            platform.contentIntent?.let { setContentIntent(createPendingIntent(it)) }
            platform.deleteIntent?.let { setDeleteIntent(createPendingIntent(it)) }
            platform.fullScreenIntent?.let { setFullScreenIntent(createPendingIntent(it), true) }
            content.subText?.let(::setSubText)
            platform.largeIconBitmap?.let(::setLargeIcon)
            content.largeIconResId?.let { resId -> loadBitmapFromResource(resId)?.let(::setLargeIcon) }
            content.timestampMillis?.let(::setWhen)
            content.soundUri?.let { setSound(it.toUri()) }
            content.category?.let(::setCategory)
            content.color?.let(::setColor)
            content.number?.let(::setNumber)
            content.ticker?.let(::setTicker)
            content.groupKey?.let(::setGroup)
            if (content.isGroupSummary) {
                setGroupSummary(true)
            }
            content.sortKey?.let(::setSortKey)
            content.timeoutAfterMillis?.let(::setTimeoutAfter)
            content.progress?.let { progress ->
                setProgress(progress.max, progress.current, progress.indeterminate)
            }
            platform.actions.forEach { action -> addNotificationAction(action) }
            applyStyle(content.style, platform)
        }.build()
    }

    override fun startForeground(
        service: Service,
        command: AndroidNotificationCommand,
        foregroundServiceType: Int?
    ) {
        val notification = build(command)
        if (foregroundServiceType != null) {
            service.startForeground(command.content.id, notification, foregroundServiceType)
        } else {
            service.startForeground(command.content.id, notification)
        }
    }

    override fun updateForeground(
        service: Service,
        command: AndroidNotificationCommand,
        foregroundServiceType: Int?
    ) {
        startForeground(service, command, foregroundServiceType)
    }

    override fun stopForeground(service: Service, removeNotification: Boolean) {
        service.stopForeground(
            if (removeNotification) Service.STOP_FOREGROUND_REMOVE else Service.STOP_FOREGROUND_DETACH
        )
    }

    private fun notify(command: AndroidNotificationCommand) {
        if (!areNotificationsEnabled() || !hasPermission()) {
            return
        }

        val notification = build(command)
        val content = command.content
        if (content.tag.isNullOrBlank()) {
            notificationManager.notify(content.id, notification)
        } else {
            notificationManager.notify(content.tag, content.id, notification)
        }
    }

    private fun createSchedulePendingIntent(command: AndroidNotificationCommand): PendingIntent {
        return createSchedulePendingIntent(id = command.content.id, tag = command.content.tag, command = command)
    }

    private fun createSchedulePendingIntent(
        id: Int,
        tag: String?,
        command: AndroidNotificationCommand? = null
    ): PendingIntent {
        val scheduleCommand = command ?: AndroidNotificationCommand(
            content = android.library.notification.domain.model.NotificationContent(
                id = id,
                title = "",
                message = "",
                tag = tag
            )
        )
        val intent = NotificationSchedulerSupport.buildScheduleIntent(appContext, scheduleCommand)
        return PendingIntent.getBroadcast(
            appContext,
            NotificationSchedulerSupport.scheduleKey(id, tag).hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    @SuppressLint("ScheduleExactAlarm")
    private fun scheduleAlarm(
        schedule: NotificationSchedule,
        pendingIntent: PendingIntent
    ) {
        val exactAllowed = alarmManager.canScheduleExactAlarms()
        when {
            schedule.exact && schedule.allowWhileIdle && exactAllowed -> {
                alarmManager.setExactAndAllowWhileIdle(
                    schedule.alarmType,
                    schedule.triggerAtMillis,
                    pendingIntent
                )
            }
            schedule.exact && exactAllowed -> {
                alarmManager.setExact(
                    schedule.alarmType,
                    schedule.triggerAtMillis,
                    pendingIntent
                )
            }
            schedule.allowWhileIdle -> {
                alarmManager.setAndAllowWhileIdle(
                    schedule.alarmType,
                    schedule.triggerAtMillis,
                    pendingIntent
                )
            }
            else -> {
                alarmManager.set(
                    schedule.alarmType,
                    schedule.triggerAtMillis,
                    pendingIntent
                )
            }
        }
    }

    private fun createPendingIntent(request: AndroidPendingIntentRequest): PendingIntent {
        val flags = request.flags or if (request.mutable) PendingIntent.FLAG_MUTABLE else PendingIntent.FLAG_IMMUTABLE
        return when (request.type) {
            AndroidPendingIntentType.ACTIVITY -> PendingIntent.getActivity(
                appContext,
                request.requestCode,
                request.intent,
                flags
            )
            AndroidPendingIntentType.BROADCAST -> PendingIntent.getBroadcast(
                appContext,
                request.requestCode,
                request.intent,
                flags
            )
            AndroidPendingIntentType.SERVICE -> PendingIntent.getService(
                appContext,
                request.requestCode,
                request.intent,
                flags
            )
            AndroidPendingIntentType.FOREGROUND_SERVICE -> PendingIntent.getForegroundService(
                appContext,
                request.requestCode,
                request.intent,
                flags
            )
        }
    }

    private fun NotificationCompat.Builder.addNotificationAction(action: AndroidNotificationAction) {
        addAction(
            NotificationCompat.Action.Builder(
                action.iconResId,
                action.title,
                createPendingIntent(action.pendingIntent)
            )
                .setAllowGeneratedReplies(action.allowGeneratedReplies)
                .setSemanticAction(action.semanticAction)
                .setContextual(action.contextual)
                .setShowsUserInterface(action.showsUserInterface)
                .build()
        )
    }

    private fun NotificationCompat.Builder.applyStyle(
        style: NotificationStyle,
        platform: AndroidNotificationPlatformOptions
    ) {
        when (style) {
            NotificationStyle.Default -> Unit
            is NotificationStyle.BigText -> {
                setStyle(
                    NotificationCompat.BigTextStyle()
                        .bigText(style.bigText)
                        .also { builder ->
                            style.summaryText?.let(builder::setSummaryText)
                            style.bigContentTitle?.let(builder::setBigContentTitle)
                        }
                )
            }
            is NotificationStyle.Inbox -> {
                setStyle(
                    NotificationCompat.InboxStyle()
                        .also { builder ->
                            style.lines.forEach(builder::addLine)
                            style.summaryText?.let(builder::setSummaryText)
                            style.bigContentTitle?.let(builder::setBigContentTitle)
                        }
                )
            }
            is NotificationStyle.BigPicture -> {
                val picture = style.pictureResId?.let(::loadBitmapFromResource)
                    ?: style.pictureUriString?.let(::loadBitmapFromUri)
                if (picture != null) {
                    setStyle(
                        NotificationCompat.BigPictureStyle()
                            .bigPicture(picture)
                            .also { builder ->
                                style.summaryText?.let(builder::setSummaryText)
                                style.bigContentTitle?.let(builder::setBigContentTitle)
                                when {
                                    style.hideExpandedLargeIcon -> builder.bigLargeIcon(null as Bitmap?)
                                    style.largeIconResId != null -> builder.bigLargeIcon(loadBitmapFromResource(style.largeIconResId))
                                }
                            }
                    )
                }
            }
            is NotificationStyle.Messaging -> {
                val styleBuilder = NotificationCompat.MessagingStyle(
                    Person.Builder().setName(style.userDisplayName).build()
                ).also { builder ->
                    style.messages.forEach { message ->
                        builder.addMessage(
                            NotificationCompat.MessagingStyle.Message(
                                message.text,
                                message.timestampMillis,
                                message.senderName?.let { sender -> Person.Builder().setName(sender).build() }
                            )
                        )
                    }
                    style.conversationTitle?.let(builder::setConversationTitle)
                    style.isGroupConversation?.let(builder::setGroupConversation)
                }
                setStyle(styleBuilder)
            }
            is NotificationStyle.Media -> {
                setStyle(
                    MediaNotificationCompat.MediaStyle().also { mediaStyle ->
                        style.compactActionIndices
                            .filter { it in 0 until platform.actions.size }
                            .takeIf { it.isNotEmpty() }
                            ?.toIntArray()
                            ?.let { mediaStyle.setShowActionsInCompactView(*it) }
                    }
                )
            }
            is NotificationStyle.DecoratedCustomView -> {
                setCustomContentView(buildRemoteViews(style.customView))
                style.customView.bigLayoutResId?.let { layoutResId ->
                    setCustomBigContentView(buildRemoteViews(style.customView, layoutResId))
                }
                setStyle(NotificationCompat.DecoratedCustomViewStyle())
            }
            is NotificationStyle.DecoratedMediaCustomView -> {
                setCustomContentView(buildRemoteViews(style.customView))
                style.customView.bigLayoutResId?.let { layoutResId ->
                    setCustomBigContentView(buildRemoteViews(style.customView, layoutResId))
                }
                setStyle(
                    MediaNotificationCompat.DecoratedMediaCustomViewStyle().also { mediaStyle ->
                        style.compactActionIndices
                            .filter { it in 0 until platform.actions.size }
                            .takeIf { it.isNotEmpty() }
                            ?.toIntArray()
                            ?.let { mediaStyle.setShowActionsInCompactView(*it) }
                    }
                )
            }
            is NotificationStyle.Call -> {
                buildCallStyle(style, platform)?.let(::setStyle)
            }
        }
    }

    private fun buildRemoteViews(
        styleData: NotificationCustomViewStyleData,
        layoutResId: Int = styleData.layoutResId
    ): RemoteViews {
        return RemoteViews(appContext.packageName, layoutResId).apply {
            if (styleData.titleViewId != null && styleData.titleText != null) {
                setTextViewText(styleData.titleViewId, styleData.titleText)
            }
            if (styleData.messageViewId != null && styleData.messageText != null) {
                setTextViewText(styleData.messageViewId, styleData.messageText)
            }
            if (styleData.iconViewId != null && styleData.iconResId != null) {
                setImageViewResource(styleData.iconViewId, styleData.iconResId)
            }
        }
    }

    private fun buildCallStyle(
        style: NotificationStyle.Call,
        platform: AndroidNotificationPlatformOptions
    ): NotificationCompat.CallStyle? {
        val personBuilder = Person.Builder().setName(style.person.name)
        style.person.avatarResId?.let { avatarResId ->
            personBuilder.setIcon(IconCompat.createWithResource(appContext, avatarResId))
        }
        val person = personBuilder.build()
        val callOptions = platform.callStyleOptions ?: return null

        val callStyle = when (style.callType) {
            NotificationCallType.INCOMING -> {
                val declineIntent = callOptions.declineIntent ?: return null
                val answerIntent = callOptions.answerIntent ?: return null
                NotificationCompat.CallStyle.forIncomingCall(
                    person,
                    createPendingIntent(declineIntent),
                    createPendingIntent(answerIntent)
                )
            }
            NotificationCallType.ONGOING -> {
                val hangUpIntent = callOptions.hangUpIntent ?: return null
                NotificationCompat.CallStyle.forOngoingCall(
                    person,
                    createPendingIntent(hangUpIntent)
                )
            }
            NotificationCallType.SCREENING -> {
                val hangUpIntent = callOptions.hangUpIntent ?: return null
                val answerIntent = callOptions.answerIntent ?: return null
                NotificationCompat.CallStyle.forScreeningCall(
                    person,
                    createPendingIntent(hangUpIntent),
                    createPendingIntent(answerIntent)
                )
            }
        }

        return callStyle
            .setIsVideo(style.isVideo)
            .also { builder ->
                style.verificationText?.let(builder::setVerificationText)
            }
    }

    private fun loadBitmapFromResource(resId: Int): Bitmap? {
        return runCatching { BitmapFactory.decodeResource(appContext.resources, resId) }.getOrNull()
    }

    private fun loadBitmapFromUri(uriString: String): Bitmap? {
        return runCatching {
            ImageDecoder.decodeBitmap(
                ImageDecoder.createSource(appContext.contentResolver, uriString.toUri())
            )
        }.getOrNull()
    }

    private fun normalizeChannelImportance(importance: Int): Int {
        return when (importance) {
            NotificationManager.IMPORTANCE_UNSPECIFIED,
            NotificationManager.IMPORTANCE_NONE,
            NotificationManager.IMPORTANCE_MIN,
            NotificationManager.IMPORTANCE_LOW,
            NotificationManager.IMPORTANCE_DEFAULT,
            NotificationManager.IMPORTANCE_HIGH -> importance
            else -> NotificationManager.IMPORTANCE_DEFAULT
        }
    }

    private fun normalizeVisibility(visibility: Int): Int {
        return when (visibility) {
            NotificationCompat.VISIBILITY_PUBLIC,
            NotificationCompat.VISIBILITY_PRIVATE,
            NotificationCompat.VISIBILITY_SECRET -> visibility
            else -> NotificationCompat.VISIBILITY_PUBLIC
        }
    }
}
