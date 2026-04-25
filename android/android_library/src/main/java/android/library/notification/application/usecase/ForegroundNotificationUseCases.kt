package android.library.notification.application.usecase

import android.app.Notification
import android.app.Service
import android.library.notification.application.model.AndroidNotificationCommand
import android.library.notification.application.port.AndroidNotificationRuntimeRepository
import android.util.Log

class BuildNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(command: AndroidNotificationCommand): Notification {
        Log.d(TAG, "[invoke] command: $command")
        return repository.build(command)
    }
    companion object { private const val TAG = "BuildNotificationUseCase" }
}

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

class StopForegroundNotificationUseCase(private val repository: AndroidNotificationRuntimeRepository) {
    operator fun invoke(service: Service, removeNotification: Boolean = true) {
        Log.d(TAG, "[invoke] removeNotification: $removeNotification")
        repository.stopForeground(service, removeNotification)
    }
    companion object { private const val TAG = "StopForegroundNotificationUseCase" }
}
