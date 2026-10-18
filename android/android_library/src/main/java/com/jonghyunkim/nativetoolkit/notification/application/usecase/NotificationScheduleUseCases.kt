package com.jonghyunkim.nativetoolkit.notification.application.usecase

import com.jonghyunkim.nativetoolkit.notification.application.model.AndroidNotificationCommand
import com.jonghyunkim.nativetoolkit.notification.application.port.NotificationCommandRepository
import com.jonghyunkim.nativetoolkit.notification.domain.model.NotificationSchedule
import android.util.Log

/**
 * Use case for scheduling a notification.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class ScheduleNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand, schedule: NotificationSchedule): Result<Unit> {
        Log.d(TAG, "[invoke] command: $command, schedule: $schedule")
        return runCatching { repository.schedule(command, schedule) }
    }
    companion object { private const val TAG = "ScheduleNotificationUseCase" }
}

/**
 * Use case for canceling a specific scheduled notification.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class CancelScheduledNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(id: Int, tag: String? = null): Result<Unit> {
        Log.d(TAG, "[invoke] id: $id, tag: $tag")
        return runCatching { repository.cancelScheduled(id, tag) }
    }
    companion object { private const val TAG = "CancelScheduledNotificationUseCase" }
}

/**
 * Use case for canceling all scheduled notifications.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class CancelAllScheduledNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Result<Unit> {
        Log.d(TAG, "[invoke]")
        return runCatching { repository.cancelAllScheduled() }
    }
    companion object { private const val TAG = "CancelAllScheduledNotificationsUseCase" }
}

/**
 * Use case for restoring previously scheduled notifications, mainly after reboot.
 *
 * @return Result of the operation. Failures are returned via [Result.failure].
 */
class RestoreScheduledNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Result<Unit> {
        Log.d(TAG, "[invoke]")
        return runCatching { repository.restoreScheduled() }
    }
    companion object { private const val TAG = "RestoreScheduledNotificationsUseCase" }
}
