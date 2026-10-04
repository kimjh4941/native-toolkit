package com.jonghyunkim.nativetoolkit.notification.presentation

import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.common.event.EventHub
import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationSettingsPort
import com.jonghyunkim.nativetoolkit.notification.application.usecase.CanScheduleExactAlarmsUseCase
import com.jonghyunkim.nativetoolkit.notification.application.usecase.CancelNotificationPermissionRequestUseCase
import com.jonghyunkim.nativetoolkit.notification.application.usecase.NotificationUseCases
import com.jonghyunkim.nativetoolkit.notification.application.usecase.OpenNotificationSettingsUseCase
import com.jonghyunkim.nativetoolkit.notification.application.usecase.RequestNotificationPermissionUseCase
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCasesFactory
import com.jonghyunkim.nativetoolkit.notification.domain.error.PermissionRequestDomainError
import com.jonghyunkim.nativetoolkit.notification.domain.model.ActiveNotification
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationChannel
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsOpenResult
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSettingsTarget
import com.jonghyunkim.nativetoolkit.notification.domain.model.PermissionRequestResult
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationEvents
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationInteraction
import com.jonghyunkim.nativetoolkit.notification.presentation.event.NotificationShown
import com.jonghyunkim.nativetoolkit.notification.presentation.permission.FragmentPermissionRequester
import com.jonghyunkim.nativetoolkit.notification.presentation.progress.ProgressForegroundNotifications
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import com.jonghyunkim.nativetoolkit.notification.data.repository.NotificationUseCases as createNotificationUseCases

/**
 * The entry point for notifications (Kotlin API design 6.3).
 *
 * The existing operations take the same arguments and give the same results and exceptions as
 * [NotificationUseCases]. This class only delegates; it keeps the Application Context only.
 *
 * @param appContext The Application Context.
 * @param useCases The existing notification use cases.
 * @param requestPermissionUseCase Requests the notification permission.
 * @param cancelPermissionRequestUseCase Cancels a permission request.
 * @param settingsPort Builds the settings port that opens screens from a Context.
 */
class AndroidNotificationManager internal constructor(
    private val appContext: Context,
    private val useCases: NotificationUseCases,
    private val requestPermissionUseCase: RequestNotificationPermissionUseCase,
    private val cancelPermissionRequestUseCase: CancelNotificationPermissionRequestUseCase,
    private val settingsPort: (Context) -> NotificationSettingsPort
) {

    /** Taps, actions and dismissals of notifications built with `NotificationEventIntents`. Main thread. */
    val interactions: EventHub<NotificationInteraction> get() = NotificationEvents.interactions

    /** Scheduled notifications that were shown. Main thread. */
    val shown: EventHub<NotificationShown> get() = NotificationEvents.shown

    /**
     * Shows a notification.
     *
     * @param command The notification.
     */
    fun show(command: AndroidNotificationCommand): Result<Unit> {
        Log.d(TAG, "[show] command: $command")
        return useCases.show(command)
    }

    /**
     * Updates a notification.
     *
     * @param command The notification.
     */
    fun update(command: AndroidNotificationCommand): Result<Unit> {
        Log.d(TAG, "[update] command: $command")
        return useCases.update(command)
    }

    /**
     * Removes a notification.
     *
     * @param id The notification ID.
     * @param tag The notification tag.
     */
    fun cancel(id: Int, tag: String? = null): Result<Unit> {
        Log.d(TAG, "[cancel] id: $id, tag: $tag")
        return useCases.cancel(id, tag)
    }

    /** Removes every notification of the app. */
    fun cancelAll(): Result<Unit> {
        Log.d(TAG, "[cancelAll]")
        return useCases.cancelAll()
    }

    /**
     * Creates a channel.
     *
     * @param channel The channel.
     */
    fun createChannel(channel: NotificationChannel): Result<Unit> {
        Log.d(TAG, "[createChannel] channel: $channel")
        return useCases.createChannel(channel)
    }

    /**
     * Creates channels.
     *
     * @param channels The channels.
     */
    fun createChannels(channels: List<NotificationChannel>): Result<Unit> {
        Log.d(TAG, "[createChannels] channels: $channels")
        return useCases.createChannels(channels)
    }

    /**
     * Deletes a channel.
     *
     * @param channelId The channel ID.
     */
    fun deleteChannel(channelId: String): Result<Unit> {
        Log.d(TAG, "[deleteChannel] channelId: $channelId")
        return useCases.deleteChannel(channelId)
    }

    /**
     * Schedules a notification. Saving a schedule with `persistAcrossBoot` finishes before this
     * returns, so calling it on the main thread may wait for another thread's write.
     *
     * @param command The notification.
     * @param schedule When and how.
     */
    fun schedule(command: AndroidNotificationCommand, schedule: NotificationSchedule): Result<Unit> {
        Log.d(TAG, "[schedule] command: $command, schedule: $schedule")
        return useCases.schedule(command, schedule)
    }

    /**
     * Cancels a schedule.
     *
     * @param id The notification ID.
     * @param tag The notification tag.
     */
    fun cancelScheduled(id: Int, tag: String? = null): Result<Unit> {
        Log.d(TAG, "[cancelScheduled] id: $id, tag: $tag")
        return useCases.cancelScheduled(id, tag)
    }

    /** Cancels every saved schedule. */
    fun cancelAllScheduled(): Result<Unit> {
        Log.d(TAG, "[cancelAllScheduled]")
        return useCases.cancelAllScheduled()
    }

    /** Restores the saved schedules, as the library does after a reboot or an update. */
    fun restoreScheduled(): Result<Unit> {
        Log.d(TAG, "[restoreScheduled]")
        return useCases.restoreScheduled()
    }

    /**
     * Returns whether a schedule with `persistAcrossBoot` is saved for [id] and [tag].
     *
     * @param id The notification ID.
     * @param tag The notification tag.
     */
    fun isScheduled(id: Int, tag: String? = null): Boolean {
        Log.d(TAG, "[isScheduled] id: $id, tag: $tag")
        return useCases.isScheduled(appContext, id, tag)
    }

    /** Returns the notifications the app shows now. */
    fun getActive(): List<ActiveNotification> {
        Log.d(TAG, "[getActive]")
        return useCases.getActive()
    }

    /** Returns whether the app holds the notification permission (always true on API 32 and lower). */
    fun hasPermission(): Boolean {
        Log.d(TAG, "[hasPermission]")
        return useCases.hasPermission()
    }

    /** Returns whether notifications of the app are enabled. */
    fun areNotificationsEnabled(): Boolean {
        Log.d(TAG, "[areNotificationsEnabled]")
        return useCases.areNotificationsEnabled()
    }

    /**
     * Starts a progress notification in a foreground service.
     *
     * @param command The notification.
     */
    fun startProgress(command: AndroidNotificationCommand) {
        Log.d(TAG, "[startProgress] id: ${command.content.id}")
        ProgressForegroundNotifications.start(appContext, command)
    }

    /**
     * Updates the progress notification.
     *
     * @param command The notification.
     */
    fun updateProgress(command: AndroidNotificationCommand) {
        Log.d(TAG, "[updateProgress] id: ${command.content.id}")
        ProgressForegroundNotifications.update(appContext, command)
    }

    /**
     * Ends the foreground service and shows [command] as the completed notification.
     *
     * @param command The notification.
     */
    fun completeProgress(command: AndroidNotificationCommand) {
        Log.d(TAG, "[completeProgress] id: ${command.content.id}")
        ProgressForegroundNotifications.complete(appContext, command)
    }

    /** Ends the foreground service and removes its notification. */
    fun stopProgress() {
        Log.d(TAG, "[stopProgress]")
        ProgressForegroundNotifications.stop(appContext)
    }

    /**
     * Requests the notification permission. Callable from any thread; [onResult] runs once on the
     * main thread, never inside this call. Requests made while one is in progress share its answer.
     *
     * @param onResult Receives the result.
     * @return The request ID, used with [cancelPermissionRequest].
     */
    fun requestPermission(onResult: (PermissionRequestResult) -> Unit): Long {
        Log.d(TAG, "[requestPermission] onResult: $onResult")
        return requestPermissionUseCase(onResult)
    }

    /**
     * Requests the notification permission and waits for the answer. Cancelling the coroutine
     * cancels the request.
     *
     * @return Whether the permission is granted.
     * @throws PermissionRequestDomainError.Canceled When the request ended without an answer.
     * @throws PermissionRequestDomainError.Unavailable When the system dialog could not be shown.
     */
    suspend fun requestPermission(): Boolean {
        Log.d(TAG, "[requestPermission]")
        return suspendCancellableCoroutine { continuation ->
            val requestId = requestPermissionUseCase { result ->
                when (result) {
                    PermissionRequestResult.Granted -> continuation.resume(true)
                    PermissionRequestResult.Denied -> continuation.resume(false)
                    is PermissionRequestResult.Canceled ->
                        continuation.resumeWithException(PermissionRequestDomainError.Canceled(result.reason))
                    is PermissionRequestResult.Failed ->
                        continuation.resumeWithException(PermissionRequestDomainError.Unavailable(result.reason))
                }
            }
            continuation.invokeOnCancellation { cancelPermissionRequestUseCase(requestId) }
        }
    }

    /**
     * Cancels a permission request. Its result becomes `Canceled(REQUESTED)` unless it already has
     * one; the system dialog stays for the other requests. Unknown IDs are ignored.
     *
     * @param requestId The ID returned by [requestPermission].
     */
    fun cancelPermissionRequest(requestId: Long) {
        Log.d(TAG, "[cancelPermissionRequest] requestId: $requestId")
        cancelPermissionRequestUseCase(requestId)
    }

    /** Returns whether the app may schedule exact alarms. */
    fun canScheduleExactAlarms(): Boolean {
        Log.d(TAG, "[canScheduleExactAlarms]")
        return CanScheduleExactAlarmsUseCase(settingsPort(appContext))()
    }

    /**
     * Opens a settings screen, falling back to the app details screen. Whether the app is in the
     * foreground is not checked.
     *
     * @param target The screen.
     * @param from The Activity to open it from; `null` opens it from the Application Context in a
     *   new task.
     */
    fun openSettings(target: NotificationSettingsTarget, from: Context? = null): NotificationSettingsOpenResult {
        Log.d(TAG, "[openSettings] target: $target, from: $from")
        return OpenNotificationSettingsUseCase(settingsPort(from ?: appContext))(target)
    }

    companion object {
        private const val TAG = "com.jonghyunkim.nativetoolkit.notification.presentation.AndroidNotificationManager"

        @Volatile
        private var instance: AndroidNotificationManager? = null

        /**
         * Returns the process-wide instance.
         *
         * @param context Any Context; only its Application Context is kept.
         */
        @JvmStatic
        fun getInstance(context: Context): AndroidNotificationManager {
            Log.d(TAG, "[getInstance] context: $context")
            return instance ?: synchronized(this) {
                instance ?: create(context.applicationContext).also { instance = it }
            }
        }

        private fun create(appContext: Context): AndroidNotificationManager {
            Log.d(TAG, "[create] appContext: $appContext")
            val permissionPort = FragmentPermissionRequester.get(appContext)
            return AndroidNotificationManager(
                appContext = appContext,
                useCases = createNotificationUseCases(appContext),
                requestPermissionUseCase = RequestNotificationPermissionUseCase(permissionPort),
                cancelPermissionRequestUseCase = CancelNotificationPermissionRequestUseCase(permissionPort),
                settingsPort = NotificationUseCasesFactory::settingsPort
            )
        }
    }
}
