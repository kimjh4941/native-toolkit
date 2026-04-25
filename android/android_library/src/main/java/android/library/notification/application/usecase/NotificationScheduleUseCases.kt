package android.library.notification.application.usecase

import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.domain.model.NotificationSchedule
import android.util.Log

class ScheduleNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand, schedule: NotificationSchedule): Result<Unit> {
        Log.d(TAG, "[invoke] command: $command, schedule: $schedule")
        return runCatching { repository.schedule(command, schedule) }
    }
    companion object { private const val TAG = "ScheduleNotificationUseCase" }
}

class CancelScheduledNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(id: Int, tag: String? = null): Result<Unit> {
        Log.d(TAG, "[invoke] id: $id, tag: $tag")
        return runCatching { repository.cancelScheduled(id, tag) }
    }
    companion object { private const val TAG = "CancelScheduledNotificationUseCase" }
}

class CancelAllScheduledNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Result<Unit> {
        Log.d(TAG, "[invoke]")
        return runCatching { repository.cancelAllScheduled() }
    }
    companion object { private const val TAG = "CancelAllScheduledNotificationsUseCase" }
}

class RestoreScheduledNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Result<Unit> {
        Log.d(TAG, "[invoke]")
        return runCatching { repository.restoreScheduled() }
    }
    companion object { private const val TAG = "RestoreScheduledNotificationsUseCase" }
}
