package android.library.notification.application.usecase

import android.app.Notification
import android.app.Service
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.port.AndroidNotificationRuntimeRepository

class BuildNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(command: AndroidNotificationCommand): Notification {
        return repository.build(command)
    }
}

class StartForegroundNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(
        service: Service,
        command: AndroidNotificationCommand,
        foregroundServiceType: Int? = null
    ) {
        repository.startForeground(service, command, foregroundServiceType)
    }
}

class UpdateForegroundNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(
        service: Service,
        command: AndroidNotificationCommand,
        foregroundServiceType: Int? = null
    ) {
        repository.updateForeground(service, command, foregroundServiceType)
    }
}

class StopForegroundNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(service: Service, removeNotification: Boolean = true) {
        repository.stopForeground(service, removeNotification)
    }
}

