package android.library.notification.application.usecase

import android.library.notification.application.port.NotificationCommandRepository
import android.library.notification.domain.model.ActiveNotification

class GetActiveNotificationsUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): List<ActiveNotification> {
        return repository.getActive()
    }
}

class HasNotificationPermissionUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Boolean {
        return repository.hasPermission()
    }
}

class AreNotificationsEnabledUseCase(private val repository: NotificationCommandRepository) {
    operator fun invoke(): Boolean {
        return repository.areNotificationsEnabled()
    }
}
