package com.jonghyunkim.nativetoolkit.notification.application.usecase

import android.content.Context
import android.util.Log
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationCommandRepository
import com.jonghyunkim.nativetoolkit.notification.data.repository.JsonNotificationScheduleStore

/**
 * Use-case suite for notification features.
 *
 * Exposes all notification use cases such as show, update, cancel,
 * scheduling, and channel management.
 *
 * @param repository [NotificationCommandRepository] used to execute notification operations.
 */
class NotificationUseCases(repository: NotificationCommandRepository) {

    val show = ShowNotificationUseCase(repository)
    val update = UpdateNotificationUseCase(repository)
    val cancel = CancelNotificationUseCase(repository)
    val cancelAll = CancelAllNotificationsUseCase(repository)

    val schedule = ScheduleNotificationUseCase(repository)
    val cancelScheduled = CancelScheduledNotificationUseCase(repository)
    val cancelAllScheduled = CancelAllScheduledNotificationsUseCase(repository)
    val restoreScheduled = RestoreScheduledNotificationsUseCase(repository)

    val createChannel = CreateNotificationChannelUseCase(repository)
    val createChannels = CreateNotificationChannelsUseCase(repository)
    val deleteChannel = DeleteNotificationChannelUseCase(repository)

    val hasPermission = HasNotificationPermissionUseCase(repository)
    val areNotificationsEnabled = AreNotificationsEnabledUseCase(repository)
    val getActive = GetActiveNotificationsUseCase(repository)

    /**
     * Checks whether the specified notification ID is scheduled.
     *
     * Reads the saved schedules directly, so only schedules with `persistAcrossBoot` are found.
     *
     * @return True if scheduled.
     */
    fun isScheduled(context: Context, id: Int, tag: String? = null): Boolean {
        Log.d(TAG, "[isScheduled] context: $context, id: $id, tag: $tag")
        return JsonNotificationScheduleStore(context).loadAll().any { entry ->
            entry.command.content.id == id && entry.command.content.tag == tag
        }
    }

    private companion object {
        private const val TAG = "NotificationUseCases"
    }
}
