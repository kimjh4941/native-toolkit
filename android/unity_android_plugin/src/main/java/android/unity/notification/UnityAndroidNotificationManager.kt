package android.unity.notification

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidPendingIntentType
import android.library.notification.application.usecase.CancelAllNotificationsUseCase
import android.library.notification.application.usecase.CancelAllScheduledNotificationsUseCase
import android.library.notification.application.usecase.CancelNotificationUseCase
import android.library.notification.application.usecase.CancelScheduledNotificationUseCase
import android.library.notification.application.usecase.CreateNotificationChannelUseCase
import android.library.notification.application.usecase.DeleteNotificationChannelUseCase
import android.library.notification.application.usecase.ScheduleNotificationUseCase
import android.library.notification.application.usecase.ShowNotificationUseCase
import android.library.notification.application.usecase.UpdateNotificationUseCase
import android.library.notification.data.repository.NotificationRepositoryImpl
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationMessage
import android.library.notification.domain.model.NotificationProgress
import android.library.notification.domain.model.NotificationSchedule
import android.library.notification.domain.model.NotificationStyle
import android.library.notification.presentation.progress.ProgressForegroundNotifications
import android.net.Uri
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.concurrent.ConcurrentHashMap

/**
 * Unity-facing notification bridge for native-toolkit.
 *
 * Initial release scope:
 * - Basic notifications (show / update / cancel)
 * - Schedule notifications
 * - Progress foreground service notifications
 * - Permission / settings query helpers
 *
 * Complex Android-only notification features such as CallStyle, RemoteViews custom styles,
 * inline reply, and fullScreenIntent are intentionally left to later Unity integration stages.
 */
object UnityAndroidNotificationManager {

    private const val TAG = "UnityAndroidNotificationMgr"

    @JvmStatic
    fun getInstance(): UnityAndroidNotificationManager {
        Log.d(TAG, "getInstance called")
        return this
    }

    fun hasPermission(context: Context): Boolean {
        return NotificationRepositoryImpl(context).hasPermission()
    }

    fun areNotificationsEnabled(context: Context): Boolean {
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun openNotificationSettings(context: Context): Boolean {
        val opened = startActivitySafely(
            context,
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                data = packageUri(context)
            }
        )
        return opened || openAppDetailsSettings(context)
    }

    fun openAppDetailsSettings(context: Context): Boolean {
        return startActivitySafely(
            context,
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = packageUri(context)
            }
        )
    }

    fun openExactAlarmSettings(context: Context): Boolean {
        val opened = startActivitySafely(
            context,
            Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = packageUri(context)
            }
        )
        return opened || openAppDetailsSettings(context)
    }

    fun createChannel(context: Context, channelJson: String): Boolean {
        return runOperation("createChannel") {
            val channel = UnityNotificationJsonParser.parseChannel(channelJson)
            CreateNotificationChannelUseCase(NotificationRepositoryImpl(context))(channel.toDomainChannel())
            true
        }
    }

    fun deleteChannel(context: Context, channelId: String) {
        runOperation("deleteChannel") {
            DeleteNotificationChannelUseCase(NotificationRepositoryImpl(context))(channelId)
            true
        }
    }

    fun showNotification(context: Context, notificationJson: String): Boolean {
        return runShowOrUpdate(context, notificationJson, isUpdate = false)
    }

    fun updateNotification(context: Context, notificationJson: String): Boolean {
        return runShowOrUpdate(context, notificationJson, isUpdate = true)
    }

    fun cancelNotification(context: Context, id: Int, tag: String? = null) {
        runOperation("cancelNotification") {
            CancelNotificationUseCase(NotificationRepositoryImpl(context))(id, tag)
            true
        }
    }

    fun cancelAllNotifications(context: Context) {
        runOperation("cancelAllNotifications") {
            CancelAllNotificationsUseCase(NotificationRepositoryImpl(context))()
            true
        }
    }

    fun scheduleNotification(context: Context, scheduleJson: String): Boolean {
        return runOperation("scheduleNotification") {
            val scheduleSpec = UnityNotificationJsonParser.parseScheduledNotification(scheduleJson)
            val command = scheduleSpec.notification.toCommand(context)
            ScheduleNotificationUseCase(NotificationRepositoryImpl(context))(
                command = command,
                schedule = NotificationSchedule(
                    triggerAtMillis = scheduleSpec.triggerAtMillis,
                    exact = scheduleSpec.exact,
                    allowWhileIdle = scheduleSpec.allowWhileIdle,
                    persistAcrossBoot = scheduleSpec.persistAcrossBoot,
                    alarmType = scheduleSpec.alarmType
                )
            )
        }
    }

    fun cancelScheduledNotification(context: Context, id: Int, tag: String? = null) {
        runOperation("cancelScheduledNotification") {
            CancelScheduledNotificationUseCase(NotificationRepositoryImpl(context))(id, tag)
            true
        }
    }

    fun cancelAllScheduledNotifications(context: Context) {
        runOperation("cancelAllScheduledNotifications") {
            CancelAllScheduledNotificationsUseCase(NotificationRepositoryImpl(context))()
            true
        }
    }

    fun startProgressForegroundService(context: Context, notificationJson: String): Boolean {
        return runProgressOperation(context, notificationJson, ProgressOperation.START)
    }

    fun updateProgressForegroundService(context: Context, notificationJson: String): Boolean {
        return runProgressOperation(context, notificationJson, ProgressOperation.UPDATE)
    }

    fun completeProgressForegroundService(context: Context, notificationJson: String): Boolean {
        return runProgressOperation(context, notificationJson, ProgressOperation.COMPLETE)
    }

    fun stopProgressForegroundService(context: Context) {
        runOperation("stopProgressForegroundService") {
            ProgressForegroundNotifications.stop(context)
            true
        }
    }

    private fun runShowOrUpdate(
        context: Context,
        notificationJson: String,
        isUpdate: Boolean
    ): Boolean {
        return runOperation(if (isUpdate) "updateNotification" else "showNotification") {
            val command = UnityNotificationJsonParser.parseNotification(notificationJson).toCommand(context)
            val repository = NotificationRepositoryImpl(context)
            if (isUpdate) {
                UpdateNotificationUseCase(repository)(command)
            } else {
                ShowNotificationUseCase(repository)(command)
            }
            true
        }
    }

    private fun runProgressOperation(
        context: Context,
        notificationJson: String,
        operation: ProgressOperation
    ): Boolean {
        return runOperation("${operation.logName}ProgressForegroundService") {
            val notificationSpec = UnityNotificationJsonParser.parseNotification(notificationJson)
            require(notificationSpec.progress != null) { "progress is required for Progress FGS operations." }

            val command = when (operation) {
                ProgressOperation.START,
                ProgressOperation.UPDATE -> notificationSpec.asProgressForegroundNotification().toCommand(context)
                ProgressOperation.COMPLETE -> notificationSpec.asProgressCompletionNotification().toCommand(context)
            }

            when (operation) {
                ProgressOperation.START -> ProgressForegroundNotifications.start(context, command)
                ProgressOperation.UPDATE -> ProgressForegroundNotifications.update(context, command)
                ProgressOperation.COMPLETE -> ProgressForegroundNotifications.complete(context, command)
            }
            true
        }
    }

    private fun runOperation(name: String, block: () -> Boolean): Boolean {
        return runCatching(block)
            .onFailure { throwable -> Log.e(TAG, "[$name] failed", throwable) }
            .getOrDefault(false)
    }

    private fun startActivitySafely(context: Context, intent: Intent): Boolean {
        return try {
            if (context !is android.app.Activity) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: SecurityException) {
            false
        }
    }

    private fun packageUri(context: Context): Uri {
        return Uri.fromParts("package", context.packageName, null)
    }

    private fun UnityNotificationChannelSpec.toDomainChannel(): NotificationChannel {
        return NotificationChannel(
            id = id,
            name = name,
            importance = normalizeImportance(importance),
            description = description,
            showBadge = showBadge,
            enableLights = enableLights,
            lightColor = lightColor,
            enableVibration = enableVibration,
            vibrationPattern = vibrationPattern,
            soundUri = soundUriString,
            lockscreenVisibility = normalizeVisibility(lockscreenVisibility),
            groupId = groupId,
            groupName = groupName
        )
    }

    private fun UnityNotificationSpec.toCommand(context: Context): AndroidNotificationCommand {
        val resolver = ContextResourceResolver(context)
        return AndroidNotificationCommand(
            content = NotificationContent(
                id = id,
                title = title,
                message = message,
                tag = tag,
                channel = channel.toDomainChannel(),
                smallIconResId = resolver.resolve(smallIcon) ?: resolver.defaultSmallIconResId(),
                largeIconResId = resolver.resolve(largeIcon),
                priority = priority,
                autoCancel = autoCancel,
                ongoing = ongoing,
                subText = subText,
                showTimestamp = showTimestamp,
                timestampMillis = timestampMillis,
                soundUri = soundUriString,
                category = category,
                visibility = normalizeVisibility(visibility),
                color = color,
                number = number,
                ticker = ticker,
                groupKey = groupKey,
                isGroupSummary = isGroupSummary,
                groupAlertBehavior = groupAlertBehavior,
                sortKey = sortKey,
                onlyAlertOnce = onlyAlertOnce,
                localOnly = localOnly,
                silent = silent,
                usesChronometer = usesChronometer,
                timeoutAfterMillis = timeoutAfterMillis,
                progress = progress?.toDomainProgress(),
                style = style.toDomainStyle(resolver)
            ),
            platformOptions = AndroidNotificationPlatformOptions(
                contentIntent = buildContentIntent(context)
            )
        )
    }

    private fun UnityNotificationSpec.buildContentIntent(context: Context): AndroidPendingIntentRequest? {
        if (!launchAppOnTap) {
            return null
        }

        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                launchAction?.let { action = it }
            }
            ?: Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                `package` = context.packageName
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
                launchAction?.let { action = it }
            }

        return AndroidPendingIntentRequest(
            intent = intent,
            requestCode = id,
            type = AndroidPendingIntentType.ACTIVITY
        )
    }

    private fun UnityNotificationProgressSpec.toDomainProgress(): NotificationProgress {
        return NotificationProgress(
            max = max,
            current = current,
            indeterminate = indeterminate
        )
    }

    private fun UnityNotificationStyleSpec.toDomainStyle(
        resolver: ContextResourceResolver
    ): NotificationStyle {
        return when (type) {
            UnityNotificationStyleSpec.TYPE_BIG_TEXT -> {
                NotificationStyle.BigText(
                    bigText = bigText.orEmpty(),
                    summaryText = summaryText,
                    bigContentTitle = bigContentTitle
                )
            }

            UnityNotificationStyleSpec.TYPE_INBOX -> {
                NotificationStyle.Inbox(
                    lines = lines,
                    summaryText = summaryText,
                    bigContentTitle = bigContentTitle
                )
            }

            UnityNotificationStyleSpec.TYPE_BIG_PICTURE -> {
                val pictureResId = resolver.resolve(picture)
                if (pictureResId == null && pictureUriString.isNullOrBlank()) {
                    NotificationStyle.Default
                } else {
                    NotificationStyle.BigPicture(
                        pictureResId = pictureResId,
                        pictureUriString = pictureUriString,
                        summaryText = summaryText,
                        bigContentTitle = bigContentTitle,
                        largeIconResId = resolver.resolve(largeIcon),
                        hideExpandedLargeIcon = hideExpandedLargeIcon
                    )
                }
            }

            UnityNotificationStyleSpec.TYPE_MESSAGING -> {
                NotificationStyle.Messaging(
                    userDisplayName = userDisplayName ?: "You",
                    messages = messages.map { message ->
                        NotificationMessage(
                            text = message.text,
                            timestampMillis = message.timestampMillis,
                            senderName = message.senderName
                        )
                    },
                    conversationTitle = conversationTitle,
                    isGroupConversation = isGroupConversation
                )
            }

            else -> NotificationStyle.Default
        }
    }

    private fun UnityNotificationSpec.asProgressForegroundNotification(): UnityNotificationSpec {
        return copy(
            ongoing = true,
            autoCancel = false,
            onlyAlertOnce = true
        )
    }

    private fun UnityNotificationSpec.asProgressCompletionNotification(): UnityNotificationSpec {
        return copy(
            ongoing = false,
            autoCancel = true,
            onlyAlertOnce = true,
            progress = progress?.copy(current = progress.max)
        )
    }

    private fun normalizeImportance(importance: Int): Int {
        return when (importance) {
            NotificationManager.IMPORTANCE_UNSPECIFIED,
            NotificationManager.IMPORTANCE_NONE,
            NotificationManager.IMPORTANCE_MIN,
            NotificationManager.IMPORTANCE_LOW,
            NotificationManager.IMPORTANCE_DEFAULT,
            NotificationManager.IMPORTANCE_HIGH,
            NotificationManager.IMPORTANCE_MAX -> importance
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

    private class ContextResourceResolver(private val context: Context) {

        private val resourceIdCache = ConcurrentHashMap<String, Int>()

        fun resolve(resourceRef: UnityNotificationResourceRef?): Int? {
            resourceRef ?: return null
            val explicitType = resourceRef.type?.takeIf { it.isNotBlank() }
            if (explicitType != null) {
                return resolveByRClass(resourceRef.name, explicitType)
            }

            return listOf("drawable", "mipmap").firstNotNullOfOrNull { type ->
                resolveByRClass(resourceRef.name, type)
            }
        }

        fun defaultSmallIconResId(): Int {
            return context.applicationInfo.icon.takeIf { it != 0 }
                ?: android.R.drawable.ic_dialog_info
        }

        private fun resolveByRClass(name: String, type: String): Int? {
            val normalizedType = type.trim()
            if (normalizedType !in SUPPORTED_RESOURCE_TYPES) {
                return null
            }

            val cacheKey = "$normalizedType:$name"
            val resolved = resourceIdCache.getOrPut(cacheKey) {
                runCatching {
                    val rClass = Class.forName("${context.packageName}.R$$normalizedType")
                    rClass.getField(name).getInt(null)
                }.getOrDefault(MISSING_RESOURCE_ID)
            }
            return resolved.takeIf { it != MISSING_RESOURCE_ID }
        }

        private companion object {
            const val MISSING_RESOURCE_ID = 0
            val SUPPORTED_RESOURCE_TYPES = setOf("drawable", "mipmap")
        }
    }

    private enum class ProgressOperation(val logName: String) {
        START("start"),
        UPDATE("update"),
        COMPLETE("complete")
    }
}


