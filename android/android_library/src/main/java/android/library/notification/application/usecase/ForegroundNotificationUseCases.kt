package android.library.notification.application.usecase

import android.app.Notification
import android.app.Service
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.port.AndroidNotificationRuntimeRepository
import android.util.Log

/**
 * Use case for building a notification object.
 */
class BuildNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(command: AndroidNotificationCommand): Notification {
        Log.d(TAG, "[invoke] command: $command")
        return repository.build(command)
    }
    companion object { private const val TAG = "BuildNotificationUseCase" }
}

/**
 * Use case for starting foreground mode and showing a notification.
 */
class StartForegroundNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(
        service: Service,
        command: AndroidNotificationCommand,
        foregroundServiceType: Int? = null
    ) {
        Log.d(TAG, "[invoke] id: ${command.content.id}, foregroundServiceType: $foregroundServiceType")
        repository.startForeground(service, command, foregroundServiceType)
    }
    companion object { private const val TAG = "StartForegroundNotificationUseCase" }
}

/**
 * Use case for updating a foreground notification.
 */
class UpdateForegroundNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(
        service: Service,
        command: AndroidNotificationCommand,
        foregroundServiceType: Int? = null
    ) {
        Log.d(TAG, "[invoke] id: ${command.content.id}, foregroundServiceType: $foregroundServiceType")
        repository.updateForeground(service, command, foregroundServiceType)
    }
    companion object { private const val TAG = "UpdateForegroundNotificationUseCase" }
}

/**
 * Use case for stopping foreground mode.
 */
class StopForegroundNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(service: Service, removeNotification: Boolean = true) {
        Log.d(TAG, "[invoke] removeNotification: $removeNotification")
        repository.stopForeground(service, removeNotification)
    }
    companion object { private const val TAG = "StopForegroundNotificationUseCase" }
}
