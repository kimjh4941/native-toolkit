package android.library.notification.application.usecase

import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.domain.model.NotificationSchedule

class ScheduleNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand, schedule: NotificationSchedule): Boolean {
        return repository.schedule(command, schedule)
    }
}

class CancelScheduledNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(id: Int, tag: String? = null) {
        repository.cancelScheduled(id, tag)
    }
}

class CancelAllScheduledNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke() {
        repository.cancelAllScheduled()
    }
}

class RestoreScheduledNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke() {
        repository.restoreScheduled()
    }
}

