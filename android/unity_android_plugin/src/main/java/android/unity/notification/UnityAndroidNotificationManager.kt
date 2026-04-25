package android.unity.notification

import android.app.NotificationManager
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.library.notification.application.model.AndroidNotificationAction
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.model.AndroidNotificationCustomViewPlatformOptions
import android.library.notification.application.model.AndroidNotificationPlatformOptions
import android.library.notification.application.model.AndroidPendingIntentRequest
import android.library.notification.application.model.AndroidPendingIntentType
import android.library.notification.application.model.RemoteViewAction
import android.library.notification.domain.model.NotificationCustomViewStyleData
import android.library.notification.data.repository.NotificationUseCases
import android.library.notification.domain.model.NotificationChannel
import android.library.notification.domain.model.NotificationContent
import android.library.notification.domain.model.NotificationMessage
import android.library.notification.domain.model.NotificationProgress
import android.library.notification.domain.model.NotificationSchedule
import android.library.notification.domain.model.NotificationStyle
import android.library.notification.presentation.progress.ProgressForegroundNotifications
import android.net.Uri
import android.provider.Settings
import android.app.AlarmManager
import android.library.notification.NotificationShownSupport
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

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

    private const val TAG = "UnityAndroidNotificationManager"

    const val OPERATION_OPEN_NOTIFICATION_SETTINGS = "openNotificationSettings"
    const val OPERATION_OPEN_APP_DETAILS_SETTINGS = "openAppDetailsSettings"
    const val OPERATION_OPEN_EXACT_ALARM_SETTINGS = "openExactAlarmSettings"
    const val OPERATION_CREATE_CHANNEL = "createChannel"
    const val OPERATION_DELETE_CHANNEL = "deleteChannel"
    const val OPERATION_SHOW_NOTIFICATION = "showNotification"
    const val OPERATION_UPDATE_NOTIFICATION = "updateNotification"
    const val OPERATION_CANCEL_NOTIFICATION = "cancelNotification"
    const val OPERATION_CANCEL_ALL_NOTIFICATIONS = "cancelAllNotifications"
    const val OPERATION_SCHEDULE_NOTIFICATION = "scheduleNotification"
    const val OPERATION_CANCEL_SCHEDULED_NOTIFICATION = "cancelScheduledNotification"
    const val OPERATION_CANCEL_ALL_SCHEDULED_NOTIFICATIONS = "cancelAllScheduledNotifications"
    const val OPERATION_START_PROGRESS_FOREGROUND_SERVICE = "startProgressForegroundService"
    const val OPERATION_UPDATE_PROGRESS_FOREGROUND_SERVICE = "updateProgressForegroundService"
    const val OPERATION_COMPLETE_PROGRESS_FOREGROUND_SERVICE = "completeProgressForegroundService"
    const val OPERATION_STOP_PROGRESS_FOREGROUND_SERVICE = "stopProgressForegroundService"

    private var notificationOperationListener: NotificationOperationListener? = null
    private var notificationActionListener: NotificationActionReceiver.NotificationActionListener? = null
    private var notificationShownListener: NotificationShownSupport.NotificationShownListener? = null

    interface NotificationOperationListener {
        fun onNotificationOperation(operation: String, isSuccessful: Boolean, errorMessage: String?)
    }

    @JvmStatic
    fun getInstance(): UnityAndroidNotificationManager {
        Log.d(TAG, "getInstance called")
        return this
    }

    fun setNotificationOperationListener(listener: NotificationOperationListener) {
        Log.d(TAG, "[setNotificationOperationListener] listener: $listener")
        notificationOperationListener = listener
    }

    fun clearNotificationOperationListener() {
        Log.d(TAG, "[clearNotificationOperationListener]")
        notificationOperationListener = null
    }

    fun setNotificationActionListener(listener: NotificationActionReceiver.NotificationActionListener) {
        Log.d(TAG, "[setNotificationActionListener] listener: $listener")
        notificationActionListener = listener
        NotificationActionReceiver.actionListener = listener
    }

    fun clearNotificationActionListener() {
        Log.d(TAG, "[clearNotificationActionListener]")
        notificationActionListener = null
        NotificationActionReceiver.actionListener = null
    }

    fun setNotificationShownListener(listener: NotificationShownSupport.NotificationShownListener) {
        Log.d(TAG, "[setNotificationShownListener] listener: $listener")
        notificationShownListener = listener
        NotificationShownSupport.shownListener = listener
    }

    fun clearNotificationShownListener() {
        Log.d(TAG, "[clearNotificationShownListener]")
        notificationShownListener = null
        NotificationShownSupport.shownListener = null
    }

    fun hasPermission(context: Context): Boolean {
        Log.d(TAG, "[hasPermission]")
        return NotificationUseCases(context).hasPermission()
    }

    fun areNotificationsEnabled(context: Context): Boolean {
        Log.d(TAG, "[areNotificationsEnabled]")
        return NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    fun isNotificationScheduled(context: Context, id: Int, tag: String? = null): Boolean {
        Log.d(TAG, "[isNotificationScheduled] id: $id, tag: $tag")
        return NotificationUseCases(context).isScheduled(context, id, tag)
    }

    fun canScheduleExactAlarms(context: Context): Boolean {
        Log.d(TAG, "[canScheduleExactAlarms]")
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            context.getSystemService(AlarmManager::class.java)?.canScheduleExactAlarms() == true
        } else {
            true
        }
    }

    fun openNotificationSettings(context: Context) {
        Log.d(TAG, "[openNotificationSettings]")
        openSettingsWithFallback(
            operation = OPERATION_OPEN_NOTIFICATION_SETTINGS,
            context = context,
            primaryIntent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
                data = packageUri(context)
            },
            fallbackIntent = appDetailsSettingsIntent(context),
            primaryLabel = "app notification settings"
        )
    }

    fun openAppDetailsSettings(context: Context) {
        Log.d(TAG, "[openAppDetailsSettings]")
        executeOperation(OPERATION_OPEN_APP_DETAILS_SETTINGS) {
            startActivity(context, appDetailsSettingsIntent(context))
        }
    }

    fun openExactAlarmSettings(context: Context) {
        Log.d(TAG, "[openExactAlarmSettings]")
        openSettingsWithFallback(
            operation = OPERATION_OPEN_EXACT_ALARM_SETTINGS,
            context = context,
            primaryIntent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                data = packageUri(context)
            },
            fallbackIntent = appDetailsSettingsIntent(context),
            primaryLabel = "exact alarm settings"
        )
    }

    fun createChannel(context: Context, channelJson: String) {
        Log.d(TAG, "[createChannel] channelJson: $channelJson")
        executeOperation(OPERATION_CREATE_CHANNEL) {
            val channel = UnityNotificationJsonParser.parseChannel(channelJson)
            NotificationUseCases(context).createChannel(channel.toDomainChannel()).getOrThrow()
        }
    }

    fun deleteChannel(context: Context, channelId: String) {
        Log.d(TAG, "[deleteChannel] channelId: $channelId")
        executeOperation(OPERATION_DELETE_CHANNEL) {
            NotificationUseCases(context).deleteChannel(channelId).getOrThrow()
        }
    }

    fun showNotification(context: Context, notificationJson: String) {
        Log.d(TAG, "[showNotification] notificationJson: $notificationJson")
        runShowOrUpdate(context, notificationJson, isUpdate = false)
    }

    fun updateNotification(context: Context, notificationJson: String) {
        Log.d(TAG, "[updateNotification] notificationJson: $notificationJson")
        runShowOrUpdate(context, notificationJson, isUpdate = true)
    }

    fun cancelNotification(context: Context, id: Int, tag: String? = null) {
        Log.d(TAG, "[cancelNotification] id: $id, tag: $tag")
        executeOperation(OPERATION_CANCEL_NOTIFICATION) {
            NotificationUseCases(context).cancel(id, tag).getOrThrow()
        }
    }

    fun cancelAllNotifications(context: Context) {
        Log.d(TAG, "[cancelAllNotifications]")
        executeOperation(OPERATION_CANCEL_ALL_NOTIFICATIONS) {
            NotificationUseCases(context).cancelAll().getOrThrow()
        }
    }

    fun scheduleNotification(context: Context, scheduleJson: String) {
        Log.d(TAG, "[scheduleNotification] scheduleJson: $scheduleJson")
        executeOperation(OPERATION_SCHEDULE_NOTIFICATION) {
            val scheduleSpec = UnityNotificationJsonParser.parseScheduledNotification(scheduleJson)
            val command = scheduleSpec.notification.toCommand(context)
            NotificationUseCases(context).schedule(
                command = command,
                schedule = NotificationSchedule(
                    triggerAtMillis = scheduleSpec.triggerAtMillis,
                    exact = scheduleSpec.exact,
                    allowWhileIdle = scheduleSpec.allowWhileIdle,
                    persistAcrossBoot = scheduleSpec.persistAcrossBoot,
                    alarmType = scheduleSpec.alarmType
                )
            ).getOrThrow()
        }
    }

    fun cancelScheduledNotification(context: Context, id: Int, tag: String? = null) {
        Log.d(TAG, "[cancelScheduledNotification] id: $id, tag: $tag")
        executeOperation(OPERATION_CANCEL_SCHEDULED_NOTIFICATION) {
            NotificationUseCases(context).cancelScheduled(id, tag).getOrThrow()
        }
    }

    fun cancelAllScheduledNotifications(context: Context) {
        Log.d(TAG, "[cancelAllScheduledNotifications]")
        executeOperation(OPERATION_CANCEL_ALL_SCHEDULED_NOTIFICATIONS) {
            NotificationUseCases(context).cancelAllScheduled().getOrThrow()
        }
    }

    fun startProgressForegroundService(context: Context, notificationJson: String) {
        Log.d(TAG, "[startProgressForegroundService] notificationJson: $notificationJson")
        runProgressOperation(context, notificationJson, ProgressOperation.START)
    }

    fun updateProgressForegroundService(context: Context, notificationJson: String) {
        Log.d(TAG, "[updateProgressForegroundService] notificationJson: $notificationJson")
        runProgressOperation(context, notificationJson, ProgressOperation.UPDATE)
    }

    fun completeProgressForegroundService(context: Context, notificationJson: String) {
        Log.d(TAG, "[completeProgressForegroundService] notificationJson: $notificationJson")
        runProgressOperation(context, notificationJson, ProgressOperation.COMPLETE)
    }

    fun stopProgressForegroundService(context: Context) {
        Log.d(TAG, "[stopProgressForegroundService]")
        executeOperation(OPERATION_STOP_PROGRESS_FOREGROUND_SERVICE) {
            ProgressForegroundNotifications.stop(context)
        }
    }

    private fun runShowOrUpdate(
        context: Context,
        notificationJson: String,
        isUpdate: Boolean
    ) {
        executeOperation(if (isUpdate) OPERATION_UPDATE_NOTIFICATION else OPERATION_SHOW_NOTIFICATION) {
            val command = UnityNotificationJsonParser.parseNotification(notificationJson).toCommand(context)
            val useCases = NotificationUseCases(context)
            if (isUpdate) {
                useCases.update(command).getOrThrow()
            } else {
                useCases.show(command).getOrThrow()
            }
        }
    }

    private fun runProgressOperation(
        context: Context,
        notificationJson: String,
        operation: ProgressOperation
    ) {
        executeOperation(operation.operationName) {
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
        }
    }

    private fun executeOperation(name: String, block: () -> Unit) {
        try {
            block()
            notifyOperationResult(name, true, null)
        } catch (exception: IllegalArgumentException) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Invalid argument for $name: ${exception.message ?: "Please verify the input parameters."}"
            )
        } catch (exception: ActivityNotFoundException) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "No Activity found to handle $name. Please check device settings support."
            )
        } catch (exception: SecurityException) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Security restriction while executing $name: ${exception.message ?: "Permission or device policy denied this operation."}"
            )
        } catch (exception: Exception) {
            notifyOperationFailure(
                name = name,
                throwable = exception,
                errorMessage = "Failed to $name: ${exception.message ?: exception.javaClass.simpleName}"
            )
        }
    }

    private fun notifyOperationFailure(name: String, throwable: Exception, errorMessage: String) {
        Log.e(TAG, "[$name] failed: $errorMessage", throwable)
        notifyOperationResult(name, false, errorMessage)
    }

    private fun notifyOperationResult(operation: String, isSuccessful: Boolean, errorMessage: String?) {
        val listener = notificationOperationListener
        if (listener == null) {
            Log.w(
                TAG,
                "NotificationOperationListener is not set. operation=$operation, isSuccessful=$isSuccessful, errorMessage=$errorMessage"
            )
            return
        }

        listener.onNotificationOperation(operation, isSuccessful, errorMessage)
    }

    private fun openSettingsWithFallback(
        operation: String,
        context: Context,
        primaryIntent: Intent,
        fallbackIntent: Intent,
        primaryLabel: String
    ) {
        executeOperation(operation) {
            try {
                startActivity(context, primaryIntent)
            } catch (exception: ActivityNotFoundException) {
                Log.w(TAG, "[$operation] $primaryLabel is unavailable. Falling back to app details settings.", exception)
                startFallbackActivity(operation, context, fallbackIntent, primaryLabel)
            } catch (exception: SecurityException) {
                Log.w(TAG, "[$operation] $primaryLabel is restricted. Falling back to app details settings.", exception)
                startFallbackActivity(operation, context, fallbackIntent, primaryLabel)
            }
        }
    }

    private fun startFallbackActivity(
        operation: String,
        context: Context,
        fallbackIntent: Intent,
        primaryLabel: String
    ) {
        try {
            startActivity(context, fallbackIntent)
        } catch (_: ActivityNotFoundException) {
            throw ActivityNotFoundException(
                "Unable to open $primaryLabel or app details settings for $operation."
            )
        } catch (_: SecurityException) {
            throw SecurityException(
                "Unable to open $primaryLabel or app details settings for $operation due to security restrictions."
            )
        }
    }

    private fun startActivity(context: Context, intent: Intent) {
        if (context !is android.app.Activity) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun packageUri(context: Context): Uri {
        val packageUri: Uri? = Uri.fromParts("package", context.packageName, null)
        if (packageUri != null) {
            return packageUri
        }

        Log.w(TAG, "[packageUri] Uri.fromParts returned null. Falling back to Uri.EMPTY.")
        return Uri.EMPTY
    }

    private fun appDetailsSettingsIntent(context: Context): Intent {
        return Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = packageUri(context)
        }
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
                contentIntent = buildContentIntent(context),
                deleteIntent = buildDeleteIntent(context),
                fullScreenIntent = if (fullScreenIntent) buildFullScreenIntent(context) else null,
                actions = actions.mapIndexed { index, action -> action.toAndroidAction(context, id, index, data) },
                customViewOptions = style.buildCustomViewOptions(context, id, data)
            )
        )
    }

    private fun UnityNotificationSpec.buildContentIntent(context: Context): AndroidPendingIntentRequest {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            putExtra(NotificationActionReceiver.EXTRA_ACTION_ID, NotificationActionReceiver.ACTION_BODY_TAP)
            putExtra(NotificationActionReceiver.EXTRA_NOTIFICATION_ID, id)
            putExtra(NotificationActionReceiver.EXTRA_LAUNCH_APP, launchAppOnTap)
            this@buildContentIntent.data?.let { map ->
                val jsonObj = JSONObject()
                map.forEach { (k, v) -> jsonObj.put(k, v) }
                putExtra(NotificationActionReceiver.EXTRA_DATA, jsonObj.toString())
            }
        }
        return AndroidPendingIntentRequest(
            intent = intent,
            requestCode = id,
            type = AndroidPendingIntentType.BROADCAST
        )
    }

    private fun UnityNotificationSpec.buildDeleteIntent(context: Context): AndroidPendingIntentRequest {
        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            putExtra(NotificationActionReceiver.EXTRA_ACTION_ID, NotificationActionReceiver.ACTION_NOTIFICATION_DISMISSED)
            putExtra(NotificationActionReceiver.EXTRA_NOTIFICATION_ID, id)
            putExtra(NotificationActionReceiver.EXTRA_LAUNCH_APP, false)
            this@buildDeleteIntent.data?.let { map ->
                val jsonObj = JSONObject()
                map.forEach { (k, v) -> jsonObj.put(k, v) }
                putExtra(NotificationActionReceiver.EXTRA_DATA, jsonObj.toString())
            }
        }
        return AndroidPendingIntentRequest(
            intent = intent,
            requestCode = id + Int.MAX_VALUE / 4,
            type = AndroidPendingIntentType.BROADCAST
        )
    }

    private fun UnityNotificationSpec.buildFullScreenIntent(context: Context): AndroidPendingIntentRequest? {
        val intent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            }
            ?: return null

        return AndroidPendingIntentRequest(
            intent = intent,
            requestCode = id + Int.MAX_VALUE / 2,
            type = AndroidPendingIntentType.ACTIVITY,
            mutable = true
        )
    }

    private fun UnityNotificationActionSpec.toAndroidAction(
        context: Context,
        notificationId: Int,
        index: Int,
        notificationData: Map<String, String>? = null
    ): AndroidNotificationAction {
        val resolver = ContextResourceResolver(context)
        val requestCode = notificationId * 100 + index

        val intent = Intent(context, NotificationActionReceiver::class.java).apply {
            putExtra(NotificationActionReceiver.EXTRA_ACTION_ID, actionId)
            putExtra(NotificationActionReceiver.EXTRA_NOTIFICATION_ID, notificationId)
            putExtra(NotificationActionReceiver.EXTRA_LAUNCH_APP, launchApp)
            notificationData?.let { map ->
                val jsonObj = JSONObject()
                map.forEach { (k, v) -> jsonObj.put(k, v) }
                putExtra(NotificationActionReceiver.EXTRA_DATA, jsonObj.toString())
            }
        }
        val pendingIntent = AndroidPendingIntentRequest(
            intent = intent,
            requestCode = requestCode,
            type = AndroidPendingIntentType.BROADCAST
        )

        return AndroidNotificationAction(
            title = title,
            pendingIntent = pendingIntent,
            iconResId = resolver.resolve(icon) ?: 0,
            allowGeneratedReplies = allowGeneratedReplies,
            semanticAction = semanticAction,
            contextual = contextual,
            showsUserInterface = showsUserInterface
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

            UnityNotificationStyleSpec.TYPE_DECORATED_CUSTOM_VIEW -> {
                val layoutId = customViewLayoutName?.let {
                    resolver.resolve(UnityNotificationResourceRef(it, "layout"))
                }
                if (layoutId == null) NotificationStyle.Default
                else NotificationStyle.DecoratedCustomView(
                    customView = NotificationCustomViewStyleData(
                        layoutResId = layoutId,
                        bigLayoutResId = bigCustomViewLayoutName?.let {
                            resolver.resolve(UnityNotificationResourceRef(it, "layout"))
                        }
                    )
                )
            }

            else -> NotificationStyle.Default
        }
    }

    private fun UnityNotificationStyleSpec.buildCustomViewOptions(
        context: Context,
        notificationId: Int,
        notificationData: Map<String, String>?
    ): AndroidNotificationCustomViewPlatformOptions? {
        if (type != UnityNotificationStyleSpec.TYPE_DECORATED_CUSTOM_VIEW) return null
        if (viewActions.isEmpty()) return null
        val resolver = ContextResourceResolver(context)
        val remoteViewActions = viewActions.mapIndexedNotNull { index, viewAction ->
            when (viewAction.type) {
                UnityNotificationViewActionSpec.TYPE_SET_CLICK_INTENT -> {
                    val viewId = resolver.resolve(UnityNotificationResourceRef(viewAction.viewId, "id"))
                        ?: return@mapIndexedNotNull null
                    val actionId = viewAction.actionId ?: return@mapIndexedNotNull null
                    val intent = Intent(context, NotificationActionReceiver::class.java).apply {
                        putExtra(NotificationActionReceiver.EXTRA_ACTION_ID, actionId)
                        putExtra(NotificationActionReceiver.EXTRA_NOTIFICATION_ID, notificationId)
                        putExtra(NotificationActionReceiver.EXTRA_LAUNCH_APP, false)
                        notificationData?.let { map ->
                            val jsonObj = JSONObject()
                            map.forEach { (k, v) -> jsonObj.put(k, v) }
                            putExtra(NotificationActionReceiver.EXTRA_DATA, jsonObj.toString())
                        }
                    }
                    RemoteViewAction.SetClickIntent(
                        viewId = viewId,
                        pendingIntent = AndroidPendingIntentRequest(
                            intent = intent,
                            requestCode = notificationId * 100 + 50 + index,
                            type = AndroidPendingIntentType.BROADCAST
                        )
                    )
                }
                else -> null
            }
        }
        if (remoteViewActions.isEmpty()) return null
        return AndroidNotificationCustomViewPlatformOptions(viewActions = remoteViewActions)
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
                // Use getIdentifier() to search the compiled resource table directly.
                // This works regardless of whether AGP uses transitive or non-transitive R classes,
                // which is important for resources defined in unityLibrary (e.g. res/layout/).
                val id = context.resources.getIdentifier(name, normalizedType, context.packageName)
                if (id != 0) id else MISSING_RESOURCE_ID
            }
            return resolved.takeIf { it != MISSING_RESOURCE_ID }
        }

        private companion object {
            const val MISSING_RESOURCE_ID = 0
            val SUPPORTED_RESOURCE_TYPES = setOf("drawable", "mipmap", "layout", "id")
        }
    }

    private enum class ProgressOperation(val operationName: String) {
        START(OPERATION_START_PROGRESS_FOREGROUND_SERVICE),
        UPDATE(OPERATION_UPDATE_PROGRESS_FOREGROUND_SERVICE),
        COMPLETE(OPERATION_COMPLETE_PROGRESS_FOREGROUND_SERVICE)
    }
}


