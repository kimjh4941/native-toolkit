package android.library.notification.application.usecase

import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.port.NotificationCommandRepository

class ShowNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand) {
        repository.send(command)
    }
}

class UpdateNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(command: AndroidNotificationCommand) {
        repository.update(command)
    }
}

class CancelNotificationUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(id: Int, tag: String? = null) {
        repository.cancel(id, tag)
    }
}

class CancelAllNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke() {
        repository.cancelAll()
    }
}

